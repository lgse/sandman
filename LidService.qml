import QtQuick
import Quickshell
import Quickshell.Io

// Lid handling is intentionally independent from Sandman's idle cycle. For a
// custom action, this service takes a low-level logind inhibitor and responds to
// lid state changes itself. Selecting "system" releases the inhibitor and puts
// logind back in charge.
Item {
  id: root

  property string action: "system"
  property bool present: false
  property bool closed: false
  property bool stateKnown: false
  property string hibernateCapability: "unknown"
  property string internalDisplay: ""
  property bool displayOff: false
  property bool displayWakePending: false
  property string powerAction: ""

  readonly property bool managed: action !== "system"
  readonly property bool hibernateAvailable: hibernateCapability === "yes"

  signal errorOccurred(string message)

  function scheduleStateQuery() {
    stateQueryDebounce.restart()
  }

  function applyState(value) {
    var next = Boolean(value)
    if (!root.stateKnown) {
      root.closed = next
      root.stateKnown = true
      return
    }
    if (root.closed === next) return
    root.closed = next
    if (next) handleClosed()
    else handleOpened()
  }

  function handleClosed() {
    if (!root.managed) return
    if (root.action === "display") turnDisplayOff()
    else if (root.action === "sleep") requestPowerAction("suspend")
    else if (root.action === "hibernate") requestPowerAction("hibernate")
  }

  function handleOpened() {
    if (root.displayOff) turnDisplayOn()
  }

  function turnDisplayOff() {
    if (root.displayOff || displayOffProcess.running) return
    if (!root.internalDisplay) {
      root.errorOccurred("Could not find the laptop's internal display")
      return
    }
    root.displayOff = true
    root.displayWakePending = false
    displayOffProcess.command = ["hyprctl", "dispatch", "dpms", "off", root.internalDisplay]
    displayOffProcess.running = true
  }

  function turnDisplayOn() {
    if (!root.displayOff) return
    if (displayOffProcess.running) {
      root.displayWakePending = true
      return
    }
    root.displayOff = false
    root.displayWakePending = false
    if (!root.internalDisplay || displayOnProcess.running) return
    displayOnProcess.command = ["hyprctl", "dispatch", "dpms", "on", root.internalDisplay]
    displayOnProcess.running = true
  }

  function reapplyAfterGlobalDisplayOn() {
    if (!root.closed || !root.displayOff) return
    root.displayOff = false
    root.turnDisplayOff()
  }

  function requestPowerAction(requestedAction) {
    if (powerProcess.running) return
    if (requestedAction === "hibernate" && !root.hibernateAvailable) {
      root.errorOccurred("Hibernate is not available on this computer")
      return
    }
    root.powerAction = requestedAction
    powerProcess.command = ["systemctl", requestedAction]
    powerProcess.running = true
  }

  onActionChanged: {
    if (root.displayOff && root.action !== "display") root.turnDisplayOn()
    root.stateKnown = false
    root.scheduleStateQuery()
  }

  Process {
    id: capabilityProcess
    command: ["busctl", "get-property", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "LidIsPresent", "LidIsClosed"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = String(text).match(/b\s+(true|false)/g) || []
        root.present = values.length > 0 && values[0].indexOf("true") >= 0
        if (values.length > 1) root.applyState(values[1].indexOf("true") >= 0)
      }
    }
    Component.onCompleted: running = true
  }

  Process {
    id: hibernateCapabilityProcess
    command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = String(text).match(/"([^"]+)"/)
        root.hibernateCapability = match ? match[1] : "unknown"
      }
    }
    Component.onCompleted: running = true
  }

  Process {
    id: internalDisplayProcess
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var monitors = JSON.parse(String(text))
          for (var i = 0; i < monitors.length; i++) {
            var name = String(monitors[i].name || "")
            if (/^(eDP|LVDS|DSI)/i.test(name)) {
              root.internalDisplay = name
              break
            }
          }
        } catch (error) {
        }
      }
    }
    Component.onCompleted: running = true
  }

  Timer {
    id: stateQueryDebounce
    interval: 25
    repeat: false
    onTriggered: if (!stateQueryProcess.running) stateQueryProcess.running = true
  }

  Process {
    id: stateQueryProcess
    command: ["busctl", "get-property", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "LidClosed"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(/b\s+true/.test(String(text)))
    }
  }

  Process {
    id: monitorProcess
    running: root.managed && root.present
    command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=Sandman", "--why=Handle the configured lid-close action", "--mode=block", "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("LidClosed") >= 0) root.scheduleStateQuery()
      }
    }
    onExited: function(exitCode) {
      if (root.managed && root.present && exitCode !== 0)
        root.errorOccurred("Could not monitor laptop lid events")
    }
  }

  Process {
    id: displayOffProcess
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.displayOff = false
        root.errorOccurred("Could not turn the laptop display off")
      }
      if (root.displayWakePending) root.turnDisplayOn()
    }
  }

  Process { id: displayOnProcess }

  Process {
    id: powerProcess
    onExited: function(exitCode) {
      var completedAction = root.powerAction
      root.powerAction = ""
      if (exitCode !== 0)
        root.errorOccurred(completedAction === "hibernate"
          ? "Could not hibernate the computer"
          : "Could not suspend the computer")
    }
  }
}
