#!/bin/bash

# MacOS 15.7.4 Sequoia - Discover AirPlay devices and speak the list
# Saves device mapping to ~/.airplay_devices for ConnectAirplay.sh

readonly DEVICE_FILE="$HOME/.airplay_devices"
readonly bonjour_tmp=$(mktemp)
readonly uuid_tmp=$(mktemp)
readonly DISCOVERY_MAX_SECONDS=30
readonly DNS_SD_SECONDS=4

info() {
    printf '%s\n' "$*"
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

error() {
    printf 'Error: %s\n' "$*" >&2
}

cleanup() {
    pkill -P "${chime_pid:-}" 2>/dev/null || true
    kill "${chime_pid:-}" 2>/dev/null || true
    wait "${chime_pid:-}" 2>/dev/null || true
    rm -f "${bonjour_tmp:-}" "${uuid_tmp:-}"
}
trap cleanup EXIT

(while true; do afplay /System/Library/Sounds/Blow.aiff; sleep 0.3; done) &
chime_pid=$!

run_discovery_scan() {
    : > "$bonjour_tmp"
    : > "$uuid_tmp"

    dns-sd -Z _airplay._tcp local. > "$bonjour_tmp" 2>/dev/null &
    local dns_pid=$!
    (sleep "$DNS_SD_SECONDS"; kill "$dns_pid" 2>/dev/null) &
    local sleep_pid=$!

    osascript -e '
tell application "System Events" to tell process "Control Center"
    if not (exists window "Control Center") then
        repeat with menuBarItem in every menu bar item of menu bar 1
            if description of menuBarItem as text is "Screen Mirroring" then
                click menuBarItem
                exit repeat
            end if
        end repeat
        delay 3
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
    set output to ""
    try
        repeat with cb in every checkbox of sa
            set axId to value of attribute "AXIdentifier" of cb as text
            if axId contains "screen-mirroring-device-" then
                if output is not "" then set output to output & linefeed
                set output to output & axId
            end if
        end repeat
    end try
    repeat with g in every group of sa
        try
            repeat with cb in every checkbox of g
                set axId to value of attribute "AXIdentifier" of cb as text
                if axId contains "screen-mirroring-device-" then
                    if output is not "" then set output to output & linefeed
                    set output to output & axId
                end if
            end repeat
        end try
    end repeat
    click (first menu bar item of menu bar 1 whose description is "Screen Mirroring")
    return output
end tell
' > "$uuid_tmp" 2>&1 &
    local uuid_pid=$!

    wait "$dns_pid" 2>/dev/null
    wait "$sleep_pid" 2>/dev/null
    wait "$uuid_pid"
}

# AirPlay AX ids use MAC (e.g. 26:71:...). Bonjour psi is often a UUID whose tail encodes
# the MAC, while deviceid is the same MAC — match on normalized 12 hex digits.
add_bonjour_keys() {
    local name="$1" dev="$2" psi="$3" n
    if [[ -n "$dev" ]]; then
        n=$(printf '%s' "$dev" | tr -d ':' | tr '[:upper:]' '[:lower:]')
        if [[ ${#n} -eq 12 ]]; then
            bonjour_psis+=("$name|$n")
        fi
    fi
    if [[ -n "$psi" ]]; then
        n=$(printf '%s' "$psi" | tr -d ':' | tr -d '-' | tr '[:upper:]' '[:lower:]')
        if [[ ${#n} -ge 12 ]]; then
            bonjour_psis+=("$name|${n: -12}")
        fi
    fi
}

parse_bonjour_file() {
    bonjour_psis=()
    local current_name=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^_airplay._tcp[[:space:]]+PTR[[:space:]]+(.*)\._airplay\._tcp$ ]]; then
            current_name="${BASH_REMATCH[1]}"
            current_name="${current_name//\\032/ }"
            current_name="${current_name//\\039/\'}"
        elif [[ -n "$current_name" && "$line" =~ [[:space:]]TXT[[:space:]] ]]; then
            local dev="" psi=""
            [[ "$line" =~ \"deviceid=([^\"]+)\" ]] && dev="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"psi=([^\"]+)\" ]] && psi="${BASH_REMATCH[1]}"
            if [[ -n "$dev" || -n "$psi" ]]; then
                add_bonjour_keys "$current_name" "$dev" "$psi"
            fi
            current_name=""
        fi
    done < "$bonjour_tmp"
}

nudge_bonjour() {
    # Refreshes multicast DNS cache when permitted (often needs admin once in Privacy settings).
    killall -HUP mDNSResponder 2>/dev/null || true
}

start=$SECONDS
attempt=0
bonjour_psis=()
device_uuids=""

while (( SECONDS - start < DISCOVERY_MAX_SECONDS )); do
    attempt=$((attempt + 1))
    if (( attempt > 1 )); then
        nudge_bonjour
        warn "Still searching for AirPlay devices... (${attempt}, $((SECONDS - start))s / ${DISCOVERY_MAX_SECONDS}s)"
        sleep 2
    fi

    run_discovery_scan
    parse_bonjour_file
    device_uuids=$(<"$uuid_tmp")
    device_uuids="${device_uuids//$'\r'/}"
    device_uuids=$(printf '%s\n' "$device_uuids" | grep -E 'screen-mirroring-device-.*AirPlay:' | awk '!seen[$0]++')

    if grep -qE 'screen-mirroring-device-' <<< "$device_uuids"; then
        break
    fi
done

if ! grep -qE 'screen-mirroring-device-' <<< "$device_uuids"; then
    error "No screen mirroring devices available (after ${DISCOVERY_MAX_SECONDS}s)."
    exit 1
fi

if [[ ${#bonjour_psis[@]} -eq 0 ]]; then
    warn "Bonjour did not list devices yet; names may show as Unknown."
fi

lookup_name() {
    local ax_norm
    ax_norm=$(printf '%s' "$1" | tr -d ':' | tr -d '-' | tr '[:upper:]' '[:lower:]')
    [[ ${#ax_norm} -gt 12 ]] && ax_norm="${ax_norm: -12}"
    for entry in "${bonjour_psis[@]}"; do
        local name="${entry%%|*}"
        local key="${entry##*|}"
        if [[ "$ax_norm" == "$key" ]]; then
            info "$name"
            return
        fi
    done
    info "Unknown ($1)"
}

# Build device list and save to file
> "$DEVICE_FILE"
display_names=()

while IFS= read -r axid || [[ -n "$axid" ]]; do
    [[ -z "$axid" ]] && continue
    uuid="${axid##*AirPlay:}"
    name=$(lookup_name "$uuid")
    display_names+=("$name")
    printf '%s|%s\n' "$axid" "$name" >> "$DEVICE_FILE"
done <<< "$device_uuids"

pkill -P "${chime_pid:-}" 2>/dev/null || true
kill "${chime_pid:-}" 2>/dev/null || true
wait "${chime_pid:-}" 2>/dev/null || true

if [[ "${1:-}" == "--list-only" ]]; then
    for i in "${!display_names[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${display_names[$i]}"
    done
    printf '\n'
    exit 0
fi

speech=""
for i in "${!display_names[@]}"; do
    speech+="$((i + 1)), ${display_names[$i]}. "
done
say "$speech"

info "$speech"

script_dir=$(cd "$(dirname "$0")" && pwd)
connect_script="$script_dir/ConnectAirplay.sh"
if (( ${#display_names[@]} < 10 )); then
    readonly selection_prompt="Choose device (1-${#display_names[@]}), press a number: "
    readonly selection_read_flags='-rsn1'
else
    readonly selection_prompt="Choose device (1-${#display_names[@]}), type number and press Enter: "
    readonly selection_read_flags='-rs'
fi
terminal_output=''
for i in "${!display_names[@]}"; do
    terminal_output+=$(printf '  %d) %s\n' "$((i + 1))" "${display_names[$i]}")
done
terminal_output+=$'\n'

if [[ -t 0 ]]; then
    read "$selection_read_flags" -p "$selection_prompt" selection </dev/tty || exit 1
    printf '\n'
else
    printf -v inner_cmd 'clear; printf %%s %q; read %s -p %q selection </dev/tty || exit 1; printf "\\n"; if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= %d )); then %q "$selection"; ec=$?; osascript -e '"'"'tell application "Terminal" to close (selected tab of front window)'"'"' >/dev/null 2>&1; exit $ec; fi; printf "Error: Invalid choice: %%s\\n" "$selection" >&2; sleep 2; osascript -e '"'"'tell application "Terminal" to close (selected tab of front window)'"'"' >/dev/null 2>&1; exit 1' \
        "$terminal_output" \
        "$selection_read_flags" \
        "$selection_prompt" \
        "${#display_names[@]}" \
        "$connect_script"
    printf -v terminal_cmd 'bash -lc %q' "$inner_cmd"
    osascript - "$terminal_cmd" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv)
    end tell
end run
APPLESCRIPT
    exit 0
fi

if [[ -n "${selection:-}" ]]; then
    exec "$(dirname "$0")/ConnectAirplay.sh" "$selection"
fi
