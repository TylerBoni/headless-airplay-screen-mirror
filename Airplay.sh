#!/bin/bash
set -e

# Discover devices, speak the list, then choose a numbered AirPlay target.

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEVICE_FILE="$HOME/.airplay_devices"
readonly connect_script="$script_dir/ConnectAirplay.sh"

error() {
    printf 'Error: %s\n' "$*" >&2
}

"$script_dir/ListAirplayDevices.sh" --list-only >/dev/null || exit $?

names=()
if [[ -f "$DEVICE_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        names+=("${line#*|}")
    done < "$DEVICE_FILE"
fi

if [[ ${#names[@]} -eq 0 ]]; then
    error "No devices in list."
    exit 1
fi

list_output=''
for i in "${!names[@]}"; do
    list_output+=$(printf '  %d) %s\n' "$((i + 1))" "${names[i]}")
done
list_output+=$'\n'

(
    last=$((${#names[@]} - 1))
    for i in "${!names[@]}"; do
        say "$((i + 1)), ${names[i]}."
        (( i < last )) && sleep 0.05 || true
    done
) &
say_job=$!

stop_speaking() {
    [[ -n "${say_job:-}" ]] || return
    kill -TERM "$say_job" 2>/dev/null || true
    pkill -P "$say_job" 2>/dev/null || true
    wait "$say_job" 2>/dev/null || true
}

trap stop_speaking EXIT

if (( ${#names[@]} < 10 )); then
    readonly selection_prompt="Choose device (1-${#names[@]}), press a number: "
    readonly selection_read_flags='-rsn1'
else
    readonly selection_prompt="Choose device (1-${#names[@]}), type number and press Enter: "
    readonly selection_read_flags='-rs'
fi

pick_and_connect() {
    printf '%s' "$list_output"
    read "$selection_read_flags" -p "$selection_prompt" choice </dev/tty || { stop_speaking; exit 1; }
    printf '\n'
    stop_speaking
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#names[@]} )); then
        error "Invalid choice '$choice'"
        exit 1
    fi
    exec "$connect_script" "$choice"
}

if [[ -t 0 ]]; then
    pick_and_connect
else
    printf -v inner_cmd 'clear; printf %%s %q; read %s -p %q choice </dev/tty || exit 1; printf "\\n"; if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= %d )); then exec %q "$choice"; fi; printf "Error: Invalid choice '\''%%s'\''\\n" "$choice" >&2; sleep 3; exit 1' \
        "$list_output" \
        "$selection_read_flags" \
        "$selection_prompt" \
        "${#names[@]}" \
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
