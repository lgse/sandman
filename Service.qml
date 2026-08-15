import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var configState: ({ screensaver: 150, sleep: 0 })
  property bool saving: false
  property string lastError: ""
  property bool suspendPending: false
  property bool idleCycleRunning: false
  property var screensaverWindows: ({})
  property int screensaverWindowCount: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/sandman.json"
  readonly property string screensaverClass: "org.omarchy.screensaver"
  readonly property int screensaverSeconds: Model.normalizedSeconds(configState.screensaver, 150, false)
  readonly property int sleepSeconds: Model.normalizedSeconds(configState.sleep, 0, true)
  readonly property bool sleepEnabled: sleepSeconds > 0
  readonly property int firstIdleSeconds: sleepEnabled ? Math.min(screensaverSeconds, sleepSeconds) : 1
  readonly property int sleepDelaySeconds: sleepEnabled ? Math.max(0, sleepSeconds - firstIdleSeconds) : 0
  readonly property string helperPath: {
    var url = String(Qt.resolvedUrl("sandman.py"))
    return decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)
  }

  function runHelper(arguments) {
    if (settingsProcess.running) return false
    root.saving = true
    root.lastError = ""
    settingsProcess.command = ["python3", root.helperPath].concat(arguments)
    settingsProcess.running = true
    return true
  }

  function setScreensaver(seconds) {
    return runHelper(["set-screensaver", String(seconds)])
  }

  function setSleep(seconds) {
    return runHelper(["set-sleep", String(seconds)])
  }

  function refresh() {
    configFile.reload()
  }

  function resetScreensaverWindows() {
    root.screensaverWindows = ({})
    root.screensaverWindowCount = 0
  }

  function setScreensaverWindow(address, visible) {
    var key = String(address || "")
    if (!key) return
    var next = Object.assign({}, root.screensaverWindows)
    if (visible) next[key] = true
    else delete next[key]
    root.screensaverWindows = next
    root.screensaverWindowCount = Object.keys(next).length
  }

  function eventParts(event, count) {
    try {
      if (event && event.parse) return event.parse(count)
    } catch (error) {
    }
    return String(event && event.data ? event.data : "").split(",")
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    var parts = eventParts(event, name === "openwindow" ? 4 : 1)
    if (name === "openwindow" && String(parts[2] || "") === root.screensaverClass) {
      setScreensaverWindow(parts[0], true)
      screensaverGrace.stop()
    } else if (name === "closewindow" && root.screensaverWindows[String(parts[0] || "")]) {
      setScreensaverWindow(parts[0], false)
      if (root.screensaverWindowCount === 0) cancelIdleCycle()
    }
  }

  function startIdleCycle() {
    if (!root.sleepEnabled || root.idleCycleRunning) return
    root.idleCycleRunning = true
    resetScreensaverWindows()

    if (root.sleepDelaySeconds === 0) requestSuspend()
    else {
      sleepTimer.restart()
      // Omarchy starts the screensaver at this same idle boundary. It briefly
      // reports compositor activity while opening, so allow its window event
      // to arrive before deciding that the user really returned.
      if (root.firstIdleSeconds === root.screensaverSeconds)
        screensaverGrace.restart()
    }
  }

  function cancelIdleCycle() {
    sleepTimer.stop()
    screensaverGrace.stop()
    root.idleCycleRunning = false
    resetScreensaverWindows()
  }

  function handleIdleChanged() {
    if (sleepMonitor.isIdle) startIdleCycle()
    else if (root.idleCycleRunning
             && root.screensaverWindowCount === 0
             && !screensaverGrace.running) cancelIdleCycle()
  }

  function requestSuspend() {
    if (!root.sleepEnabled || suspendProcess.running) return
    root.suspendPending = true
    root.lastError = ""
    suspendProcess.running = true
  }

  onScreensaverSecondsChanged: cancelIdleCycle()
  onSleepSecondsChanged: cancelIdleCycle()

  Process {
    id: initializeProcess
    command: ["python3", root.helperPath, "init"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.configState = Model.parseConfig(text)
    }
    Component.onCompleted: running = true
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "Could not initialize Sandman settings"
      configFile.reload()
    }
  }

  Process {
    id: settingsProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.configState = Model.parseConfig(text)
    }
    onExited: function(exitCode) {
      root.saving = false
      if (exitCode !== 0) root.lastError = "Could not save that setting"
      configFile.reload()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.configState = Model.parseConfig(text())
    onFileChanged: reload()
  }

  IdleMonitor {
    id: sleepMonitor
    enabled: root.sleepEnabled
    timeout: root.firstIdleSeconds
    respectInhibitors: true
    onIsIdleChanged: root.handleIdleChanged()
  }

  Timer {
    id: sleepTimer
    interval: root.sleepDelaySeconds * 1000
    repeat: false
    onTriggered: root.requestSuspend()
  }

  Timer {
    id: screensaverGrace
    interval: 3000
    repeat: false
    onTriggered: if (root.idleCycleRunning && !sleepMonitor.isIdle
                     && root.screensaverWindowCount === 0) root.cancelIdleCycle()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Process {
    id: suspendProcess
    command: ["systemctl", "suspend"]
    onExited: function(exitCode) {
      root.suspendPending = false
      root.cancelIdleCycle()
      if (exitCode !== 0)
        root.lastError = "Sleep was blocked by the system or an application"
    }
  }

  IpcHandler {
    target: "lgse.sandman"

    function status(): string {
      return JSON.stringify({
        screensaver: root.screensaverSeconds,
        sleep: root.sleepSeconds,
        idle: sleepMonitor.isIdle,
        idleCycleRunning: root.idleCycleRunning,
        sleepDelay: root.sleepDelaySeconds,
        screensaverWindows: root.screensaverWindowCount,
        saving: root.saving,
        suspendPending: root.suspendPending,
        error: root.lastError
      })
    }

    function setScreensaver(seconds: int): bool { return root.setScreensaver(seconds) }
    function setSleep(seconds: int): bool { return root.setSleep(seconds) }
    function refresh(): void { root.refresh() }
  }
}
