#!/usr/bin/env bash
#
# ddc-brightness.sh
# Query or set monitor brightness via ddcutil, with a zenity dialog.
#
# Requirements:
#   - ddcutil
#   - notify-send (libnotify)
#   - zenity
#   - a monitor that supports VCP code 0x10
#
# Usage: the dotfiles' GNOME settings bind it to Super+Shift+B.
#
# If you have more than one DDC-capable display, set DDC_DISPLAY below
# (find the number via `ddcutil detect`).

set -euo pipefail

DDC_DISPLAY="${DDC_DISPLAY:-1}"
VCP_BRIGHTNESS="10"

notify() {
  notify-send "Brightness" "$1"
}

command -v zenity &>/dev/null || { notify "zenity is not installed."; exit 1; }

# Read current brightness. Exits the whole script on failure.
current_brightness() {
  local output current
  output="$(ddcutil --display "$DDC_DISPLAY" getvcp "$VCP_BRIGHTNESS" 2>&1)" || {
    notify "Failed to read brightness:\n$output"
    exit 1
  }
  # Typical ddcutil output:
  # VCP code 0x10 (Brightness): current value = 60, max value = 100
  current="$(echo "$output" | grep -oP 'current value\s*=\s*\K[0-9]+')"
  echo "$current"
}

current="$(current_brightness)"

# zenity returns empty (and exits 1) on cancel — handled below.
value="$(zenity --entry --title="Brightness" --text="Brightness (current: ${current}):" --entry-text="$current")" || value=""

if [[ -z "$value" || "$value" == "$current" ]]; then
  exit 0
fi

if ! [[ "$value" =~ ^[0-9]+$ ]] || ((value < 0 || value > 100)); then
  notify "Invalid value: '$value'. Enter an integer between 0 and 100."
  exit 1
fi

if ! ddcutil --display "$DDC_DISPLAY" setvcp "$VCP_BRIGHTNESS" "$value"; then
  notify "Failed to set brightness to $value"
  exit 1
fi

notify "Brightness set to $value"
