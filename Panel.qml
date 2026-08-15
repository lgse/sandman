import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "lgse.sandman"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var sandmanService: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int screensaverSeconds: sandmanService ? sandmanService.screensaverSeconds : 150
  readonly property int sleepSeconds: sandmanService ? sandmanService.sleepSeconds : 0
  readonly property bool saving: sandmanService ? sandmanService.saving : false

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setScreensaver(value) {
    if (root.sandmanService) root.sandmanService.setScreensaver(value)
  }

  function setSleep(value) {
    if (root.sandmanService) root.sandmanService.setSleep(value)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(14)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰒲"
            color: Color.accent
            font.family: root.contentFontFamily
            font.pixelSize: Style.space(42)
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Sandman"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: Model.statusSummary(root.screensaverSeconds, root.sleepSeconds)
              color: Util.alpha(root.contentForeground, 0.64)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Style.space(7)

          PanelSectionHeader {
            width: parent.width
            text: "SCREEN SAVER"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            width: parent.width
            text: "Start after inactivity"
            color: Util.alpha(root.contentForeground, 0.64)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Grid {
            id: screensaverGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            Repeater {
              model: Model.screensaverPresets

              Button {
                required property var modelData
                width: (screensaverGrid.width - screensaverGrid.columnSpacing * 2) / 3
                text: Model.formatDuration(modelData)
                selected: root.screensaverSeconds === Number(modelData)
                enabled: !root.saving
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.setScreensaver(Number(modelData))
              }
            }
          }

          Text {
            width: parent.width
            text: "Your existing delay from screen saver to lock is preserved."
            color: Util.alpha(root.contentForeground, 0.48)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Style.space(7)

          PanelSectionHeader {
            width: parent.width
            text: "SLEEP"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            width: parent.width
            text: "Suspend the computer after inactivity"
            color: Util.alpha(root.contentForeground, 0.64)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Grid {
            id: sleepGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            Repeater {
              model: Model.sleepPresets

              Button {
                required property var modelData
                width: (sleepGrid.width - sleepGrid.columnSpacing * 2) / 3
                text: Model.formatDuration(modelData)
                selected: root.sleepSeconds === Number(modelData)
                enabled: !root.saving
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.setSleep(Number(modelData))
              }
            }
          }

          Text {
            visible: root.sleepSeconds > 0 && root.sleepSeconds <= root.screensaverSeconds
            width: parent.width
            text: "Sleep is set before the screen saver can appear."
            color: Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          visible: root.sandmanService && root.sandmanService.lastError !== ""
          width: parent.width
          text: root.sandmanService ? root.sandmanService.lastError : ""
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
