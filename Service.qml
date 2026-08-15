import QtQuick
import Quickshell
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

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/sandman.json"
  readonly property int screensaverSeconds: Model.normalizedSeconds(configState.screensaver, 150, false)
  readonly property int sleepSeconds: Model.normalizedSeconds(configState.sleep, 0, true)
  readonly property bool sleepEnabled: sleepSeconds > 0
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

  function requestSuspend() {
    if (!root.sleepEnabled || suspendProcess.running) return
    root.suspendPending = true
    root.lastError = ""
    suspendProcess.running = true
  }

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
    timeout: Math.max(1, root.sleepSeconds)
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) root.requestSuspend()
  }

  Process {
    id: suspendProcess
    command: ["systemctl", "suspend"]
    onExited: function(exitCode) {
      root.suspendPending = false
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
