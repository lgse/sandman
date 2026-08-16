import QtQuick
import QtQuick.Controls
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
  readonly property int displaySeconds: sandmanService ? sandmanService.displaySeconds : 0
  readonly property int lockSeconds: sandmanService ? sandmanService.lockSeconds : 300
  readonly property int sleepSeconds: sandmanService ? sandmanService.sleepSeconds : 0
  readonly property string lidAction: sandmanService ? sandmanService.lidAction : "system"
  readonly property bool lidPresent: sandmanService ? sandmanService.lidPresent : false
  readonly property bool hibernateAvailable: sandmanService ? sandmanService.hibernateAvailable : false
  readonly property bool saving: sandmanService ? sandmanService.saving : false
  readonly property bool screensaverUsesPreset: Model.isPreset(screensaverSeconds, Model.screensaverPresets)
  readonly property bool displayUsesPreset: Model.isPreset(displaySeconds, Model.displayPresets)
  readonly property bool lockUsesPreset: Model.isPreset(lockSeconds, Model.lockPresets)
  readonly property bool sleepUsesPreset: Model.isPreset(sleepSeconds, Model.sleepPresets)
  property bool customEditorOpen: false
  property int customHours: 0
  property int customMinutes: 1
  property bool customDisplayEditorOpen: false
  property int customDisplayHours: 0
  property int customDisplayMinutes: 5
  property bool customLockEditorOpen: false
  property int customLockHours: 0
  property int customLockMinutes: 5
  property bool customSleepEditorOpen: false
  property int customSleepHours: 0
  property int customSleepMinutes: 15
  readonly property int customTimeoutSeconds: Model.customSeconds(customHours, customMinutes)
  readonly property int customDisplayTimeoutSeconds: Model.customSeconds(customDisplayHours, customDisplayMinutes)
  readonly property int customLockTimeoutSeconds: Model.customSeconds(customLockHours, customLockMinutes)
  readonly property int customSleepTimeoutSeconds: Model.customSeconds(customSleepHours, customSleepMinutes)

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function scrollPanel(delta) {
    panelFlick.contentY = Math.max(0, Math.min(
      panelFlick.contentY + delta,
      Math.max(0, panelFlick.contentHeight - panelFlick.height)))
  }

  function setScreensaver(value) {
    if (root.sandmanService) root.sandmanService.setScreensaver(value)
  }

  function selectScreensaverPreset(value) {
    root.customEditorOpen = false
    root.setScreensaver(value)
  }

  function loadCustomTimeout() {
    var parts = Model.customParts(root.screensaverSeconds)
    root.customHours = parts.hours
    root.customMinutes = parts.minutes
  }

  function openCustomEditor() {
    root.loadCustomTimeout()
    root.customEditorOpen = true
  }

  function applyCustomTimeout() {
    if (root.customTimeoutSeconds > 0) root.setScreensaver(root.customTimeoutSeconds)
  }

  function setDisplay(value) {
    if (root.sandmanService) root.sandmanService.setDisplay(value)
  }

  function selectDisplayPreset(value) {
    root.customDisplayEditorOpen = false
    root.setDisplay(value)
  }

  function loadCustomDisplayTimeout() {
    var parts = Model.customParts(root.displaySeconds > 0 ? root.displaySeconds : 300)
    root.customDisplayHours = parts.hours
    root.customDisplayMinutes = parts.minutes
  }

  function openCustomDisplayEditor() {
    root.loadCustomDisplayTimeout()
    root.customDisplayEditorOpen = true
  }

  function applyCustomDisplayTimeout() {
    if (root.customDisplayTimeoutSeconds > 0) root.setDisplay(root.customDisplayTimeoutSeconds)
  }

  function setLock(value) {
    if (root.sandmanService) root.sandmanService.setLock(value)
  }

  function selectLockPreset(value) {
    root.customLockEditorOpen = false
    root.setLock(value)
  }

  function loadCustomLockTimeout() {
    var parts = Model.customParts(root.lockSeconds > 0 ? root.lockSeconds : 300)
    root.customLockHours = parts.hours
    root.customLockMinutes = parts.minutes
  }

  function openCustomLockEditor() {
    root.loadCustomLockTimeout()
    root.customLockEditorOpen = true
  }

  function applyCustomLockTimeout() {
    if (root.customLockTimeoutSeconds > 0) root.setLock(root.customLockTimeoutSeconds)
  }

  function setSleep(value) {
    if (root.sandmanService) root.sandmanService.setSleep(value)
  }

  function setLid(action) {
    if (root.sandmanService) root.sandmanService.setLid(action)
  }

  function selectSleepPreset(value) {
    root.customSleepEditorOpen = false
    root.setSleep(value)
  }

  function loadCustomSleepTimeout() {
    var parts = Model.customParts(root.sleepSeconds > 0 ? root.sleepSeconds : 900)
    root.customSleepHours = parts.hours
    root.customSleepMinutes = parts.minutes
  }

  function openCustomSleepEditor() {
    root.loadCustomSleepTimeout()
    root.customSleepEditorOpen = true
  }

  function applyCustomSleepTimeout() {
    if (root.customSleepTimeoutSeconds > 0) root.setSleep(root.customSleepTimeoutSeconds)
  }

  onOpenedChanged: {
    if (!opened) return
    root.customEditorOpen = !root.screensaverUsesPreset
    root.customDisplayEditorOpen = !root.displayUsesPreset
    root.customLockEditorOpen = !root.lockUsesPreset
    root.customSleepEditorOpen = !root.sleepUsesPreset
    if (root.customEditorOpen) root.loadCustomTimeout()
    if (root.customDisplayEditorOpen) root.loadCustomDisplayTimeout()
    if (root.customLockEditorOpen) root.loadCustomLockTimeout()
    if (root.customSleepEditorOpen) root.loadCustomSleepTimeout()
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
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.scrollPanel(dy * Style.space(56))
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        WheelHandler {
          onWheel: function(event) {
            if (event.angleDelta.y === 0) return
            root.scrollPanel(event.angleDelta.y > 0 ? -Style.space(56) : Style.space(56))
            event.accepted = true
          }
        }

        Column {
          id: content
          width: panelFlick.width
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
              text: Model.statusSummary(root.screensaverSeconds, root.displaySeconds, root.lockSeconds, root.sleepSeconds)
              color: Util.alpha(root.contentForeground, 0.64)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { width: parent.width }

        Column {
          visible: root.lidPresent
          width: parent.width
          spacing: Style.space(7)

          PanelSectionHeader {
            width: parent.width
            text: "LID CLOSE"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            width: parent.width
            text: "Choose what happens when the laptop lid closes"
            color: Util.alpha(root.contentForeground, 0.64)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Grid {
            id: lidGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            Repeater {
              model: Model.lidActions

              Button {
                required property var modelData
                width: (lidGrid.width - lidGrid.columnSpacing * 2) / 3
                text: Model.lidActionLabel(modelData)
                selected: root.lidAction === String(modelData)
                enabled: !root.saving
                  && (String(modelData) !== "hibernate" || root.hibernateAvailable)
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.setLid(String(modelData))
              }
            }
          }
        }

        PanelSeparator {
          visible: root.lidPresent
          width: parent.width
        }

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
                selected: !root.customEditorOpen
                  && root.screensaverSeconds === Number(modelData)
                enabled: !root.saving
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.selectScreensaverPreset(Number(modelData))
              }
            }

            Button {
              width: (screensaverGrid.width - screensaverGrid.columnSpacing * 2) / 3
              text: "Custom"
              selected: root.customEditorOpen || !root.screensaverUsesPreset
              enabled: !root.saving
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.openCustomEditor()
            }
          }

          Row {
            visible: root.customEditorOpen
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              label: "Hours"
              value: root.customHours
              from: 0
              to: 24
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customHours = value }
            }

            NumberField {
              label: "Minutes"
              value: root.customMinutes
              from: 0
              to: 59
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customMinutes = value }
            }

            Button {
              anchors.bottom: parent.bottom
              width: parent.width - x
              text: "Apply"
              enabled: !root.saving && root.customTimeoutSeconds > 0
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.applyCustomTimeout()
            }
          }

          Text {
            visible: root.screensaverSeconds > 0
              && root.lockSeconds > 0
              && root.lockSeconds <= root.screensaverSeconds
            width: parent.width
            text: "Auto-lock is set before the screen saver can appear."
            color: Color.urgent
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
            text: "DISPLAYS OFF"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            width: parent.width
            text: "Turn off the displays after inactivity"
            color: Util.alpha(root.contentForeground, 0.64)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Grid {
            id: displayGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            Repeater {
              model: Model.displayPresets

              Button {
                required property var modelData
                width: (displayGrid.width - displayGrid.columnSpacing * 2) / 3
                text: Model.formatDuration(modelData)
                selected: !root.customDisplayEditorOpen
                  && root.displaySeconds === Number(modelData)
                enabled: !root.saving
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.selectDisplayPreset(Number(modelData))
              }
            }

            Button {
              width: (displayGrid.width - displayGrid.columnSpacing * 2) / 3
              text: "Custom"
              selected: root.customDisplayEditorOpen || !root.displayUsesPreset
              enabled: !root.saving
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.openCustomDisplayEditor()
            }
          }

          Row {
            visible: root.customDisplayEditorOpen
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              label: "Hours"
              value: root.customDisplayHours
              from: 0
              to: 24
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customDisplayHours = value }
            }

            NumberField {
              label: "Minutes"
              value: root.customDisplayMinutes
              from: 0
              to: 59
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customDisplayMinutes = value }
            }

            Button {
              anchors.bottom: parent.bottom
              width: parent.width - x
              text: "Apply"
              enabled: !root.saving && root.customDisplayTimeoutSeconds > 0
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.applyCustomDisplayTimeout()
            }
          }

          Text {
            visible: root.screensaverSeconds > 0
              && root.displaySeconds > 0
              && root.displaySeconds <= root.screensaverSeconds
            width: parent.width
            text: "Displays turn off before the screen saver can appear."
            color: Color.urgent
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
            text: "AUTO-LOCK"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            width: parent.width
            text: "Lock the session after inactivity"
            color: Util.alpha(root.contentForeground, 0.64)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Grid {
            id: lockGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            Repeater {
              model: Model.lockPresets

              Button {
                required property var modelData
                width: (lockGrid.width - lockGrid.columnSpacing * 2) / 3
                text: Model.formatDuration(modelData)
                selected: !root.customLockEditorOpen
                  && root.lockSeconds === Number(modelData)
                enabled: !root.saving
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.selectLockPreset(Number(modelData))
              }
            }

            Button {
              width: (lockGrid.width - lockGrid.columnSpacing * 2) / 3
              text: "Custom"
              selected: root.customLockEditorOpen || !root.lockUsesPreset
              enabled: !root.saving
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.openCustomLockEditor()
            }
          }

          Row {
            visible: root.customLockEditorOpen
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              label: "Hours"
              value: root.customLockHours
              from: 0
              to: 24
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customLockHours = value }
            }

            NumberField {
              label: "Minutes"
              value: root.customLockMinutes
              from: 0
              to: 59
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customLockMinutes = value }
            }

            Button {
              anchors.bottom: parent.bottom
              width: parent.width - x
              text: "Apply"
              enabled: !root.saving && root.customLockTimeoutSeconds > 0
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.applyCustomLockTimeout()
            }
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
                selected: !root.customSleepEditorOpen
                  && root.sleepSeconds === Number(modelData)
                enabled: !root.saving
                focusable: true
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.selectSleepPreset(Number(modelData))
              }
            }

            Button {
              width: (sleepGrid.width - sleepGrid.columnSpacing * 2) / 3
              text: "Custom"
              selected: root.customSleepEditorOpen || !root.sleepUsesPreset
              enabled: !root.saving
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.openCustomSleepEditor()
            }
          }

          Row {
            visible: root.customSleepEditorOpen
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              label: "Hours"
              value: root.customSleepHours
              from: 0
              to: 24
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customSleepHours = value }
            }

            NumberField {
              label: "Minutes"
              value: root.customSleepMinutes
              from: 0
              to: 59
              fieldWidth: Style.space(104)
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(value) { root.customSleepMinutes = value }
            }

            Button {
              anchors.bottom: parent.bottom
              width: parent.width - x
              text: "Apply"
              enabled: !root.saving && root.customSleepTimeoutSeconds > 0
              focusable: true
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.applyCustomSleepTimeout()
            }
          }

          Text {
            visible: root.screensaverSeconds > 0
              && root.sleepSeconds > 0
              && root.sleepSeconds <= root.screensaverSeconds
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
}
