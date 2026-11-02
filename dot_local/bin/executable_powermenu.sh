#!/usr/bin/env bash
#
# powermenu.sh — a simple power menu built on rofi or zenity.
#
# Works both under Wayland tiling window managers (e.g. Sway, via rofi) and
# under GNOME (via zenity's --list dialog).
#
# Usage:
#   ./powermenu.sh
#
# Suggested Sway keybind (in ~/.config/sway/config):
#   bindsym $mod+Shift+e exec ~/.local/bin/powermenu.sh
#
# Suggested GNOME keybind: Settings > Keyboard > View and Customize Shortcuts
# > Custom Shortcuts, pointing the command at the full path, e.g.:
#   /home/youruser/.local/bin/powermenu.sh
#
# UI backend selection:
#   By default the script auto-detects: if GNOME is the current desktop
#   ($XDG_CURRENT_DESKTOP contains "GNOME"), it uses zenity; otherwise it
#   uses rofi (Fedora's sway ships it), falling back to zenity.
#   Override auto-detection by setting UI_BACKEND=rofi or zenity.
#
set -euo pipefail

UI_BACKEND="${UI_BACKEND:-}"

notify() {
  notify-send "Power menu" "$1" 2>/dev/null || true
}

# Decide which UI backend to use, unless already forced via UI_BACKEND.
detect_backend() {
  if [[ -n "$UI_BACKEND" ]]; then
    return
  fi

  if [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] && command -v zenity &>/dev/null; then
    UI_BACKEND="zenity"
  elif command -v rofi &>/dev/null; then
    UI_BACKEND="rofi"
  elif command -v zenity &>/dev/null; then
    UI_BACKEND="zenity"
  else
    notify "Neither rofi nor zenity is installed."
    exit 1
  fi
}

# Entries shown in the menu. Add/remove/reorder as you like.
entries="Suspend\nLogout\nLock\nReboot\nShutdown"

# Prompt for a choice using the selected backend.
# Echoes the chosen entry (possibly empty on cancel/escape).
prompt_choice() {
  case "$UI_BACKEND" in
  rofi)
    printf "%b" "$entries" | rofi -dmenu -i -p "Power"
    ;;
  zenity)
    zenity --list --title="Power menu" --text="Choose an action:" \
      --column="Action" $(printf "%b" "$entries" | tr '\n' ' ')
    ;;
  *)
    notify "Unknown UI backend: $UI_BACKEND"
    exit 1
    ;;
  esac
}

# Lock and logout differ between GNOME and tiling WMs (e.g. Sway).
do_lock() {
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]]; then
    loginctl lock-session
  else
    swaylock
  fi
}

do_logout() {
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]]; then
    gnome-session-quit --logout --no-prompt
  else
    swaymsg exit
  fi
}

detect_backend

choice=$(prompt_choice) || choice=""

# If the user hit Escape (empty choice), just exit quietly.
[ -z "${choice:-}" ] && exit 0

case "$choice" in
Lock)
  do_lock
  ;;
Logout)
  do_logout
  ;;
Suspend)
  systemctl suspend
  ;;
Reboot)
  systemctl reboot
  ;;
Shutdown)
  systemctl poweroff
  ;;
*)
  # Shouldn't happen, but fail safely.
  notify "Unknown option: $choice"
  exit 1
  ;;
esac
