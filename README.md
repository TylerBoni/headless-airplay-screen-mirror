# Halfbook Pro AirPlay Helper

This project helps a Mac start screen mirroring when the built-in display is broken, unreadable, or hidden. It is built for a "halfbook pro" setup: the Mac boots, plays a sound when the desktop is ready, then lets you press one keyboard shortcut to pick an AirPlay display.

The scripts open the macOS Screen Mirroring menu, find available AirPlay targets, read the list aloud, and connect to the device number you choose.

Currently tested on macOS Sequoia.

Video demo:<br>
[![How it Works Video](https://img.youtube.com/vi/9cStYCcJYCw/0.jpg)](https://www.youtube.com/shorts/9cStYCcJYCw)

## Prerequisites

- macOS with AirPlay screen mirroring support
- An AirPlay receiver on the same network
- AeroSpace installed and allowed to start at login
- The Screen Mirroring menu bar item enabled in macOS
- Terminal, AeroSpace, and System Events allowed in Privacy & Security when macOS asks for permissions
- Bash and standard macOS tools available: `osascript`, `dns-sd`, `say`, and `afplay`

## Setup

1. Clone or copy this repo to a stable location.
2. Make sure the scripts are executable:

```sh
chmod +x Airplay.sh ListAirplayDevices.sh ConnectAirplay.sh
```

3. Copy the AeroSpace config:

```sh
cp .aerospace.toml ~/.aerospace.toml
```

4. Edit `~/.aerospace.toml` and update the `alt-f1` command so it points to this checkout's `Airplay.sh`.

Example:

```toml
alt-f1 = '''exec-and-forget /bin/bash -lc "$HOME/source/repos/airplay/Airplay.sh"'''
```

If you move the repo later, update this path again.

## How It Works

1. AeroSpace starts when you log in.
2. AeroSpace plays a startup chime so you know the desktop is ready.
3. Press `option-f1`.
4. The AirPlay picker scans for devices and speaks the numbered list.
5. Choose the target:
   - For one to nine devices, press the number key directly.
   - For ten or more devices, type the full number and press Enter.

## Files

- `Airplay.sh`: main launcher for the headless AirPlay flow
- `ListAirplayDevices.sh`: scans available AirPlay targets and saves a temporary device map
- `ConnectAirplay.sh`: connects to the selected AirPlay target
- `.aerospace.toml`: minimal AeroSpace config with startup chime and `option-f1` binding

## Troubleshooting

- If nothing happens after pressing `option-f1`, check that AeroSpace is running and that `~/.aerospace.toml` points to the correct script path.
- If macOS blocks automation, open System Settings > Privacy & Security and allow the requested Terminal, AeroSpace, Accessibility, or Automation permissions.
- If no devices are found, confirm the AirPlay receiver is awake, on the same network, and visible from the normal Screen Mirroring menu.
- If device names show as `Unknown`, wait a few seconds and try again. Bonjour discovery can lag behind the Screen Mirroring UI.

## Intended Use

This is meant for cases where:

- the laptop panel is dead or unreadable
- you need an audio signal that login completed
- you want to start AirPlay without seeing or navigating the Mac display

[![Buy Me a Coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=tylerboni&button_colour=FFDD00&font_colour=000000&outline_colour=000000&coffee_colour=ffffff)](https://www.buymeacoffee.com/tylerboni)
