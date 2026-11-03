#!/usr/bin/env bash
#
# powermenu.sh — a simple power menu, as a zenity --list dialog.
#
# Usage:
#   ./powermenu.sh
#
# The dotfiles' GNOME settings bind it to Super+Shift+E.
#
set -euo pipefail

notify() {
  notify-send "Power menu" "$1" 2>/dev/null || true
}

command -v zenity &>/dev/null || { notify "zenity is not installed."; exit 1; }

# Entries shown in the menu. Add/remove/reorder as you like.
entries="Suspend\nLogout\nLock\nReboot\nShutdown"

# Echoes the chosen entry (empty on cancel/escape).
choice=$(zenity --list --title="Power menu" --text="Choose an action:" \
  --column="Action" $(printf "%b" "$entries" | tr '\n' ' ')) || choice=""

# If the user hit Escape (empty choice), just exit quietly.
[ -z "${choice:-}" ] && exit 0

case "$choice" in
Lock)
  loginctl lock-session
  ;;
Logout)
  gnome-session-quit --logout --no-prompt
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
