import QtQuick
import Quickshell
import Quickshell.Io

// Lid handling is intentionally independent from Sandman's idle cycle. For a
// custom action, this service takes a low-level logind inhibitor and responds to
// lid state changes itself. Selecting "system" releases the inhibitor and puts
// logind back in charge.
//
// The inhibitor is NOT a child of the shell. It lives in a transient systemd user
// unit (sandman-lid-<flavour>-<expiry>.service), so restarting the shell, which
// kills every child process, cannot drop it. A lock that died with the shell left
// a window in which logind, seeing a lid that was already closed, suspended the
// machine the instant the shell restarted. Each unit expires on its own after
// leaseSeconds, and this service keeps renewing it while it runs, so a shell that
// is gone for good (plugin disabled or removed) releases the lock within
// leaseSeconds instead of holding it until logout.
Item {
  id: root

  property string action: "system"
  property bool hibernateAfterSleep: false
  property string helperPath: ""
  property bool present: false
  property bool closed: false
  property bool stateKnown: false
  property string hibernateCapability: "unknown"
  property string suspendThenHibernateCapability: "unknown"
  property string internalDisplay: ""
  property bool displayOff: false
  property bool displayWakePending: false
  property string pendingDisplayAction: ""
  property string powerAction: ""
  // Set by Service once sandman.json has been read. Until then `action` is only
  // the "system" default, which must not be mistaken for the user's choice.
  property bool actionKnown: false
  property bool presentKnown: false
  property bool inhibitorEnsureQueued: false
  readonly property int leaseSeconds: 150
  readonly property int renewBelowSeconds: 75

  readonly property bool managed: action !== "system"
  // Non-power lid actions must also block sleep. logind can emit
  // PrepareForSleep for a lid close before the lid action is blocked, and
  // Omarchy's sleep monitor responds by locking the session. Blocking sleep for
  // Do nothing / Display off prevents that false pre-suspend lock while still
  // allowing Sandman's Sleep / Hibernate actions to request power transitions.
  readonly property bool inhibitSleepForLid: action === "nothing" || action === "display"
  readonly property string inhibitorWhat: inhibitSleepForLid ? "handle-lid-switch:sleep" : "handle-lid-switch"
  readonly property string inhibitorFlavour: inhibitSleepForLid ? "sleep" : "lid"
  readonly property bool hibernateAvailable: hibernateCapability === "yes"
  readonly property bool suspendThenHibernateAvailable: suspendThenHibernateCapability === "yes"

  signal errorOccurred(string message)

  function scheduleStateQuery() {
    stateQueryDebounce.restart()
  }

  function applyState(value) {
    var next = Boolean(value)
    if (!root.stateKnown) {
      root.closed = next
      root.stateKnown = true
      // The config can finish loading before the first lid reading arrives
      // (onActionChanged then skips handleClosed because stateKnown is false).
      // Apply the display action for an already-closed lid; power actions stay
      // skipped so a shell start never suspends the computer.
      if (next && root.action === "display") turnDisplayOff()
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
    if (root.displayOff || displayOffProcess.running || activeDisplayProcess.running) return
    if (!root.internalDisplay) {
      root.errorOccurred("Could not find the laptop's internal display")
      return
    }
    root.displayOff = true
    root.displayWakePending = false
    queryActiveDisplay("off")
  }

  function turnDisplayOn() {
    if (!root.displayOff) return
    if (displayOffProcess.running || activeDisplayProcess.running) {
      root.displayWakePending = true
      return
    }
    root.displayOff = false
    root.displayWakePending = false
    if (!root.internalDisplay || displayOnProcess.running) return
    queryActiveDisplay("enable")
  }

  // hl.dsp.dpms falls back to every enabled monitor when its selector matches
  // nothing, which happens once Omarchy's clamshell handling has disabled the
  // internal output on the same lid close.
  function queryActiveDisplay(action) {
    root.pendingDisplayAction = action
    activeDisplayProcess.running = true
  }

  function dispatchDisplayAction(active) {
    var action = root.pendingDisplayAction
    root.pendingDisplayAction = ""
    if (action === "off") {
      if (active === false) {
        // Disabled elsewhere, so the lid open has nothing to restore.
        root.displayOff = false
        root.displayWakePending = false
        return
      }
      displayOffProcess.command = ["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"off\", monitor = \"" + root.internalDisplay + "\" })"]
      displayOffProcess.running = true
    } else if (action === "enable") {
      if (active === false) return
      displayOnProcess.command = ["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"enable\", monitor = \"" + root.internalDisplay + "\" })"]
      displayOnProcess.running = true
    }
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
    var effectiveAction = requestedAction === "suspend" && root.hibernateAfterSleep
      ? "suspend-then-hibernate" : requestedAction
    if (effectiveAction === "suspend-then-hibernate" && !root.suspendThenHibernateAvailable) {
      root.errorOccurred("Suspend then hibernate is not available on this computer")
      return
    }
    // The helper falls back to plain suspend while an eGPU is attached.
    powerProcess.command = effectiveAction === "suspend-then-hibernate"
      ? ["python3", root.helperPath, "sleep", "--hibernate-after"]
      : ["systemctl", effectiveAction]
    powerProcess.running = true
  }

  function ensureMonitorRunning() {
    if (root.managed && root.present) {
      if (!monitorProcess.running) monitorProcess.running = true
    } else if (monitorProcess.running) {
      monitorProcess.running = false
    }
  }

  // Holds (or renews, or releases) the lid inhibitor in its own systemd unit.
  // The new lock is taken before the old one is released, so a change of
  // flavour never leaves a gap either.
  function ensureInhibitor() {
    // Never act on a guess. At shell start the config and the lid state load
    // asynchronously; releasing on the defaults would drop the very lock this
    // service exists to carry across a restart.
    if (!root.actionKnown || !root.presentKnown) return
    if (inhibitorProcess.running) {
      root.inhibitorEnsureQueued = true
      return
    }
    root.inhibitorEnsureQueued = false
    if (root.managed && root.present) {
      inhibitorProcess.command = ["sh", "-c", inhibitorEnsureScript, "sandman-lid",
        root.inhibitorFlavour, root.inhibitorWhat, String(root.leaseSeconds), String(root.renewBelowSeconds)]
    } else {
      inhibitorProcess.command = ["sh", "-c", inhibitorReleaseScript, "sandman-lid"]
    }
    inhibitorProcess.running = true
  }

  readonly property string inhibitorEnsureScript:
    'flavour=$1; what=$2; lease=$3; renew=$4; now=$(date +%s); ok=0; '
    + 'for u in $(systemctl --user list-units --plain --no-legend --state=active "sandman-lid-$flavour-*.service" | cut -d" " -f1); do '
    + 'exp=${u#sandman-lid-$flavour-}; exp=${exp%.service}; '
    + '[ "$exp" -gt $((now + renew)) ] 2>/dev/null && ok=1; done; '
    + 'if [ "$ok" = 0 ]; then '
    + 'systemd-run --user --quiet --collect --unit="sandman-lid-$flavour-$((now + lease))" -p RuntimeMaxSec="$lease" '
    + '--description="Sandman lid inhibitor ($what)" '
    + 'systemd-inhibit --what="$what" --who=Sandman --why="Handle the configured lid-close action" --mode=block sleep infinity || exit 1; fi; '
    + 'for u in $(systemctl --user list-units --plain --no-legend --state=active "sandman-lid-*.service" | cut -d" " -f1); do '
    + 'case $u in "sandman-lid-$flavour-"*) ;; *) systemctl --user stop "$u" ;; esac; done; exit 0'

  readonly property string inhibitorReleaseScript:
    'for u in $(systemctl --user list-units --plain --no-legend --state=active "sandman-lid-*.service" | cut -d" " -f1); do '
    + 'systemctl --user stop "$u"; done; exit 0'

  onActionChanged: {
    if (root.displayOff && root.action !== "display") root.turnDisplayOn()
    root.scheduleStateQuery()
    if (root.stateKnown && root.closed) Qt.callLater(root.handleClosed)
  }

  // The internal display name resolves asynchronously too; if the lid was
  // already closed when it arrived empty, apply the display action now.
  onInternalDisplayChanged: {
    if (root.stateKnown && root.closed && root.action === "display"
        && !root.displayOff && root.internalDisplay !== "") turnDisplayOff()
  }

  onInhibitorWhatChanged: ensureInhibitor()
  onActionKnownChanged: ensureInhibitor()
  onManagedChanged: { ensureMonitorRunning(); ensureInhibitor() }
  onPresentChanged: { ensureMonitorRunning(); ensureInhibitor() }

  Process {
    id: capabilityProcess
    command: ["busctl", "get-property", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "LidIsPresent", "LidIsClosed"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = String(text).match(/b\s+(true|false)/g) || []
        root.present = values.length > 0 && values[0].indexOf("true") >= 0
        root.presentKnown = true
        root.ensureInhibitor()
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
    id: suspendThenHibernateCapabilityProcess
    command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanSuspendThenHibernate"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = String(text).match(/"([^"]+)"/)
        root.suspendThenHibernateCapability = match ? match[1] : "unknown"
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

  // Renews the lease well before it runs out, and brings the lock back if
  // something stopped it.
  Timer {
    interval: 20000
    repeat: true
    running: true
    onTriggered: root.ensureInhibitor()
  }

  Process {
    id: inhibitorProcess
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.managed && root.present)
        root.errorOccurred("Could not hold the lid inhibitor")
      if (root.inhibitorEnsureQueued) Qt.callLater(root.ensureInhibitor)
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.ensureMonitorRunning()
  }

  Process {
    id: monitorProcess
    command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("LidClosed") >= 0) root.scheduleStateQuery()
      }
    }
    onExited: function(exitCode) {
      if (root.managed && root.present && exitCode !== 0)
        root.errorOccurred("Could not monitor laptop lid events")
      Qt.callLater(root.ensureMonitorRunning)
    }
  }

  Process {
    id: activeDisplayProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Unparsable output stays null so the dispatch still reports failure.
        var active = null
        try {
          var monitors = JSON.parse(String(text))
          active = false
          for (var i = 0; i < monitors.length; i++) {
            if (String(monitors[i].name || "") === root.internalDisplay && monitors[i].disabled !== true) active = true
          }
        } catch (error) {
        }
        root.dispatchDisplayAction(active)
      }
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
          : root.hibernateAfterSleep
            ? "Could not suspend then hibernate the computer"
            : "Could not suspend the computer")
    }
  }
}
