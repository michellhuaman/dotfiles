#!/usr/bin/env bash
#
# ddc-brightness.sh
# Query or set monitor brightness via ddcutil, using fuzzel or zenity as the UI
# (auto-detected, or forced via UI_BACKEND).
#
# Works both under Wayland tiling window managers (e.g. Sway, via fuzzel) and
# under GNOME (via zenity).
#
# Requirements:
#   - ddcutil
#   - notify-send (libnotify)
#   - fuzzel (for tiling WMs) and/or zenity (for GNOME) — at least one must be installed
#   - a monitor that supports VCP code 0x10
#
# Usage:
#   Sway / tiling WM: bind directly in your config, e.g.:
#     bindsym $mod+b exec ~/.local/bin/ddc-brightness.sh
#
#   GNOME: bind via Settings > Keyboard > View and Customize Shortcuts > Custom
#   Shortcuts, pointing the command at the full path, e.g.:
#     /home/youruser/.local/bin/ddc-brightness.sh
#
# UI backend selection:
#   By default the script auto-detects: if GNOME is the current desktop
#   ($XDG_CURRENT_DESKTOP contains "GNOME"), it uses zenity; otherwise it
#   prefers fuzzel if available, falling back to zenity.
#   Override auto-detection by setting UI_BACKEND=fuzzel or UI_BACKEND=zenity.
#
# If you have more than one DDC-capable display, set DDC_DISPLAY below
# (find the number via `ddcutil detect`).

set -euo pipefail

DDC_DISPLAY="${DDC_DISPLAY:-1}"
VCP_BRIGHTNESS="10"
UI_BACKEND="${UI_BACKEND:-}"

notify() {
  notify-send "Brightness" "$1"
}

# Decide which UI backend to use, unless already forced via UI_BACKEND.
detect_backend() {
  if [[ -n "$UI_BACKEND" ]]; then
    return
  fi

  if [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] && command -v zenity &>/dev/null; then
    UI_BACKEND="zenity"
  elif command -v fuzzel &>/dev/null; then
    UI_BACKEND="fuzzel"
  elif command -v zenity &>/dev/null; then
    UI_BACKEND="zenity"
  else
    notify "Neither fuzzel nor zenity is installed."
    exit 1
  fi
}

# Prompt for a brightness value using the selected backend.
# Echoes the user-entered value (possibly empty on cancel).
prompt_value() {
  local current="$1"
  case "$UI_BACKEND" in
  fuzzel)
    printf '%s' "$current" | fuzzel --dmenu --prompt "Brightness (current: ${current}): "
    ;;
  zenity)
    zenity --entry --title="Brightness" --text="Brightness (current: ${current}):" --entry-text="$current"
    ;;
  *)
    notify "Unknown UI backend: $UI_BACKEND"
    exit 1
    ;;
  esac
}

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

detect_backend

current="$(current_brightness)"

# fuzzel returns whatever was typed on Enter (matched or not);
# zenity returns empty (and exit 1) on cancel — both handled below.
value="$(prompt_value "$current")" || value=""

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
