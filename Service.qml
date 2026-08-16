import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var configState: ({ screensaver: 150, display: 0, lock: 300, sleep: 0 })
  property bool saving: false
  property string lastError: ""
  property bool suspendPending: false
  property bool displaysOff: false
  property bool idleCycleRunning: false
  property var screensaverWindows: ({})
  property int screensaverWindowCount: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/sandman.json"
  readonly property string screensaverClass: "org.omarchy.screensaver"
  readonly property int screensaverSeconds: Model.normalizedSeconds(configState.screensaver, 150, true)
  readonly property int displaySeconds: Model.normalizedSeconds(configState.display, 0, true)
  readonly property int lockSeconds: Model.normalizedSeconds(configState.lock, 300, true)
  readonly property int sleepSeconds: Model.normalizedSeconds(configState.sleep, 0, true)
  readonly property bool displayEnabled: displaySeconds > 0
  readonly property bool sleepEnabled: sleepSeconds > 0
  // The screensaver, display-off, and sleep stages are all self-observed here so
  // the cycle can survive the screensaver's brief activity blip (see below). The
  // shared monitor fires at the earliest of the enabled stage boundaries.
  readonly property bool cycleEnabled: displayEnabled || sleepEnabled
  readonly property int firstIdleSeconds: {
    if (!cycleEnabled) return 1
    var candidates = []
    if (screensaverSeconds > 0) candidates.push(screensaverSeconds)
    if (displayEnabled) candidates.push(displaySeconds)
    if (sleepEnabled) candidates.push(sleepSeconds)
    return Math.min.apply(Math, candidates)
  }
  readonly property int displayDelaySeconds: displayEnabled ? Math.max(0, displaySeconds - firstIdleSeconds) : 0
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

  function setLock(seconds) {
    return runHelper(["set-lock", String(seconds)])
  }

  function setDisplay(seconds) {
    return runHelper(["set-display", String(seconds)])
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
    if (!root.cycleEnabled || root.idleCycleRunning) return
    root.idleCycleRunning = true
    resetScreensaverWindows()

    // Omarchy starts the screensaver at this same idle boundary. It briefly
    // reports compositor activity while opening, so allow its window event
    // to arrive before deciding that the user really returned.
    if (root.screensaverSeconds > 0 && root.firstIdleSeconds === root.screensaverSeconds)
      screensaverGrace.restart()

    if (root.displayEnabled) {
      if (root.displayDelaySeconds === 0) turnDisplaysOff()
      else displayTimer.restart()
    }

    if (root.sleepEnabled) {
      if (root.sleepDelaySeconds === 0) requestSuspend()
      else sleepTimer.restart()
    }
  }

  function cancelIdleCycle() {
    displayTimer.stop()
    sleepTimer.stop()
    screensaverGrace.stop()
    root.idleCycleRunning = false
    resetScreensaverWindows()
    if (root.displaysOff) turnDisplaysOn()
  }

  function handleIdleChanged() {
    if (idleMonitor.isIdle) startIdleCycle()
    else if (root.idleCycleRunning
             && root.screensaverWindowCount === 0
             && !screensaverGrace.running) cancelIdleCycle()
  }

  function turnDisplaysOff() {
    if (!root.displayEnabled || displayOffProcess.running) return
    root.displaysOff = true
    root.lastError = ""
    displayOffProcess.running = true
  }

  function turnDisplaysOn() {
    root.displaysOff = false
    if (displayOnProcess.running) return
    displayOnProcess.running = true
  }

  function requestSuspend() {
    if (!root.sleepEnabled || suspendProcess.running) return
    root.suspendPending = true
    root.lastError = ""
    suspendProcess.running = true
  }

  onScreensaverSecondsChanged: cancelIdleCycle()
  onDisplaySecondsChanged: cancelIdleCycle()
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
    id: idleMonitor
    enabled: root.cycleEnabled
    timeout: root.firstIdleSeconds
    respectInhibitors: true
    onIsIdleChanged: root.handleIdleChanged()
  }

  Timer {
    id: displayTimer
    interval: root.displayDelaySeconds * 1000
    repeat: false
    onTriggered: root.turnDisplaysOff()
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
    onTriggered: if (root.idleCycleRunning && !idleMonitor.isIdle
                     && root.screensaverWindowCount === 0) root.cancelIdleCycle()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  // Hyprland's Lua config parses `hyprctl dispatch` args as Lua, so the classic
  // `dpms off` form is a syntax error there; use the `hl.dsp` shorthand and fall
  // back to the classic form for older Hyprland, mirroring omarchy-launch-screensaver.
  Process {
    id: displayOffProcess
    command: ["bash", "-lc", "hyprctl dispatch 'hl.dsp.dpms(\"off\")' || hyprctl dispatch dpms off"]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.displaysOff = false
        root.lastError = "Could not turn the displays off"
      }
    }
  }

  Process {
    id: displayOnProcess
    command: ["bash", "-lc", "hyprctl dispatch 'hl.dsp.dpms(\"on\")' || hyprctl dispatch dpms on"]
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
        display: root.displaySeconds,
        lock: root.lockSeconds,
        sleep: root.sleepSeconds,
        idle: idleMonitor.isIdle,
        idleCycleRunning: root.idleCycleRunning,
        displayDelay: root.displayDelaySeconds,
        displaysOff: root.displaysOff,
        sleepDelay: root.sleepDelaySeconds,
        screensaverWindows: root.screensaverWindowCount,
        saving: root.saving,
        suspendPending: root.suspendPending,
        error: root.lastError
      })
    }

    function setScreensaver(seconds: int): bool { return root.setScreensaver(seconds) }
    function setDisplay(seconds: int): bool { return root.setDisplay(seconds) }
    function setLock(seconds: int): bool { return root.setLock(seconds) }
    function setSleep(seconds: int): bool { return root.setSleep(seconds) }
    function refresh(): void { root.refresh() }
  }
}
