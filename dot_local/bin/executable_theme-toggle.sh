#!/usr/bin/env bash
#
# theme-toggle.sh
# Toggles GNOME/GTK color-scheme, GTK theme, and icon theme between
# light and dark.
#
# Bind this to a key in your sway config, e.g.:
#   bindsym $mod+shift+t exec ~/.local/bin/theme-toggle.sh

set -euo pipefail

GTK_THEME_LIGHT="Yaru-blue"
GTK_THEME_DARK="Yaru-blue-dark"

ICON_THEME_LIGHT="Yaru-blue"
ICON_THEME_DARK="Yaru-blue-dark"

current="$(gsettings get org.gnome.desktop.interface color-scheme)"

if [[ "$current" == "'prefer-dark'" ]]; then
  # Switch to light
  gsettings set org.gnome.desktop.interface color-scheme 'default'
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_LIGHT"
  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_LIGHT"
  notify-send "Theme" "Switched to light" 2>/dev/null || true
else
  # Switch to dark
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_DARK"
  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_DARK"
  notify-send "Theme" "Switched to dark" 2>/dev/null || true
fi
