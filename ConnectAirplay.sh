#!/bin/bash
set -eo pipefail

# MacOS 15.7.4 Sequoia - Connect to an AirPlay device by number
# Reads device mapping from ~/.airplay_devices (written by ListAirplayDevices.sh)

readonly DEVICE_FILE="$HOME/.airplay_devices"
readonly choice="${1:-}"

error() {
    printf 'Error: %s\n' "$*" >&2
}

if [[ -z "$choice" ]]; then
    printf 'Usage: ConnectAirplay.sh <number>\n' >&2
    exit 1
fi

if [[ ! -f "$DEVICE_FILE" ]]; then
    error "No device list found. Run ListAirplayDevices.sh first."
    exit 1
fi

devices=()
names=()
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    devices+=("${line%%|*}")
    names+=("${line#*|}")
done < "$DEVICE_FILE"

if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#devices[@]} )); then
    error "Invalid choice '$choice' (1-${#devices[@]})"
    exit 1
fi

readonly chosen_id="${devices[$((choice - 1))]}"
readonly chosen_name="${names[$((choice - 1))]}"

say "Connecting to $chosen_name" &

# Must match ListAirplayDevices.sh: scroll, then every checkbox of sa + every checkbox of each group.
# Only checking checkbox 1 of each group misses devices listed as other checkboxes in the same group.
script_tmp=$(mktemp)
trap 'rm -f "$script_tmp"' EXIT
cat > "$script_tmp" <<'APPLESCRIPT'
on run argv
    if (count of argv) is 0 then error "missing AX id"
    set chosenId to item 1 of argv as text
    tell application "System Events" to tell process "Control Center"
        if not (exists window "Control Center") then
            repeat with menuBarItem in every menu bar item of menu bar 1
                if description of menuBarItem as text is "Screen Mirroring" then
                    click menuBarItem
                    exit repeat
                end if
            end repeat
            delay 1.5
        end if
        set sa to scroll area 1 of group 1 of window "Control Center"
        try
            repeat with sb in every scroll bar of sa
                set value of sb to minimum value of sb
            end repeat
        end try
        delay 0.2
        try
            repeat with sb in every scroll bar of sa
                set value of sb to maximum value of sb
            end repeat
        end try
        delay 0.5
        try
            repeat with cb in every checkbox of sa
                try
                    set axId to value of attribute "AXIdentifier" of cb as text
                    if axId is equal to chosenId then
                        click cb
                        delay 0.3
                        click (first menu bar item of menu bar 1 whose description is "Screen Mirroring")
                        return
                    end if
                end try
            end repeat
        end try
        repeat with g in every group of sa
            repeat with cb in every checkbox of g
                try
                    set axId to value of attribute "AXIdentifier" of cb as text
                    if axId is equal to chosenId then
                        click cb
                        delay 0.3
                        click (first menu bar item of menu bar 1 whose description is "Screen Mirroring")
                        return
                    end if
                end try
            end repeat
        end repeat
        error "no checkbox matched id"
    end tell
end run
APPLESCRIPT

if ! osascript "$script_tmp" "$chosen_id" >/dev/null 2>&1; then
    error "Could not find that device in Screen Mirroring (list may be stale). Run ListAirplayDevices.sh again."
    exit 1
fi
