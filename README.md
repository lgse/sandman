# Sandman

Set when your screen rests and your computer sleeps from the Omarchy Quattro bar.

Sandman provides two simple controls:

- **Screen saver** — updates Omarchy's `idle.screensaver` timeout or turns the screen saver off. Sandman preserves the existing lock schedule while off and restores the delay between screen saver and lock when turned back on.
- **Sleep** — suspends the computer after the selected period of inactivity while respecting idle inhibitors. Sleep is off until you enable it.

## Install

```sh
omarchy plugin add https://github.com/lgse/sandman.git --enable
```

If needed, add it to the bar explicitly:

```sh
omarchy bar plugin add lgse.sandman --section right
```

## Usage

Click the moon in the bar and choose a timeout for each stage. Presets apply immediately; Custom accepts hours and minutes and applies on confirmation for both screen saver and sleep. Existing values that do not match a preset—including Omarchy's 2½-minute screen-saver default—open as Custom. Changes survive shell reloads and reboots.

Sandman stores its state in `~/.config/omarchy/sandman.json`. The screen-saver and lock values remain in Omarchy's standard `~/.config/omarchy/shell.json`.

## How sleep works

Sandman uses Quickshell's idle monitor with inhibitor support and requests suspend through `systemctl suspend`. Applications holding an idle inhibitor can prevent the timer from firing, and system-level sleep inhibitors can reject the suspend request.

## Requirements

- Omarchy Quattro
- Python 3
- systemd

## Validate

```sh
npm test
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml
```

## Remove

```sh
omarchy plugin remove lgse.sandman
rm -f ~/.config/omarchy/sandman.json
```

Removing Sandman does not revert the screen-saver and lock timeouts already written to `shell.json`.

## License

MIT
