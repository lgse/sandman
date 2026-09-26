import QtQuick
import Quickshell
import qs.Ui
import "Model.js" as Model
import "bridge" as SandmanBridge

BarWidget {
  id: root
  moduleName: "lgse.sandman"

  // Primary path: the bar host's scoped facade (service-capable under the
  // first-party bar). Fallback: the engine-wide bridge singleton -- under
  // replacement bars the facade's serviceFor() is a deliberate null stub,
  // so widgets they host would otherwise never see the service. The
  // binding re-evaluates on its own when the service publishes (or is torn
  // down). See bridge/Bridge.qml.
  readonly property var sandmanService: {
    var viaHost = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("lgse.sandman") : null
    return viaHost || SandmanBridge.Bridge.service
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.sandmanService = root.sandmanService
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSandmanServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒲"
    tooltipText: root.sandmanService
      ? Model.statusSummary(root.sandmanService.screensaverSeconds, root.sandmanService.displaySeconds, root.sandmanService.lockSeconds, root.sandmanService.sleepSeconds)
      : "Sandman"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
