# Sandman

Set when your screen rests and your computer sleeps from the Omarchy Quattro bar.

Sandman provides two simple controls:

- **Screen saver** — updates Omarchy's `idle.screensaver` timeout. Sandman preserves the existing delay between the screen saver and lock, so lock always remains the next stage.
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

Click the moon in the bar and choose a timeout for each stage. Changes take effect immediately and survive shell reloads and reboots.

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
