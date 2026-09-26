pragma Singleton
import QtQuick

// Engine-wide rendezvous between Sandman's service and its bar widget, for
// bar hosts that cannot resolve plugin services themselves. Under the
// first-party Omarchy bar, each widget's `bar.shell` facade is scoped to
// the widget's own plugin, so `bar.shell.serviceFor("lgse.sandman")`
// reaches the live service. Replacement bars (e.g. ruixen.bar) are handed
// a facade whose serviceFor() is a deliberate null stub -- Omarchy never
// exposes service resolution to them -- and there is nothing the bar can
// do about it from its side. So the widget falls back to this singleton:
// the service registers itself here on completion, and any widget that
// cannot reach its host picks it up. The host-provided path stays
// primary, so behaviour under the stock shell is unchanged.
QtObject {
  // The live Service.qml instance once it has initialized, or null.
  property var service: null
}
