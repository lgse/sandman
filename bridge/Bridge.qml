pragma Singleton
import QtQuick

// Omarchy gives replacement bars (e.g. ruixen.bar) a widget facade whose
// serviceFor() always returns null, so Service.qml publishes itself here for
// BarWidget.qml to fall back on.
QtObject {
  property var service: null
}
