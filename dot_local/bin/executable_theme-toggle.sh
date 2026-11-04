#!/usr/bin/env bash
#
# theme-toggle.sh
# Toggles GNOME/GTK color-scheme, GTK theme, and icon theme between
# light and dark.
#
# The dotfiles' GNOME settings bind it to Super+Shift+T.
#
# It also switches Alacritty between Catppuccin Latte (light) and Mocha
# (dark), by pointing its "current" theme link at the flavor's file.
# starship and bat use the terminal's ANSI colors, so they follow.
#
#   theme-toggle.sh         toggle light/dark
#   theme-toggle.sh links   only point the link at the current mode's flavor
#                           (chezmoi runs this on apply, for a new machine)

set -uo pipefail

CONFIG_DIR="$HOME/.config"

# Ubuntu's GTK and icon themes (Yaru) in each mode.
GTK_THEME_LIGHT="Yaru"
GTK_THEME_DARK="Yaru-dark"
ICON_THEME_LIGHT="Yaru"
ICON_THEME_DARK="Yaru-dark"

# Points Alacritty's "current" theme link at the file for flavor $1. chezmoi
# tracks the theme files but not the link, so toggling never shows up as a
# change.
theme_links() {
  local dir="$CONFIG_DIR/alacritty/themes"
  [[ -e "$dir/catppuccin-$1.toml" ]] || return 0
  ln -sfn "catppuccin-$1.toml" "$dir/catppuccin-current.toml"
  # Open Alacritty windows reload when alacritty.toml changes, but don't
  # always notice the imported link changing. Touching alacritty.toml makes
  # them reload, and re-read the link; its contents don't change, so
  # chezmoi sees no difference.
  [[ -f "$CONFIG_DIR/alacritty/alacritty.toml" ]] && touch "$CONFIG_DIR/alacritty/alacritty.toml"
}

current="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"

if [[ "${1:-}" == links ]]; then
  # Light only if the desktop says so; dark (the default theme) otherwise.
  if [[ "$current" == "'default'" ]]; then theme_links latte; else theme_links mocha; fi
  exit 0
fi

# Decide the target mode, then apply it once below.
if [[ "$current" == "'prefer-dark'" ]]; then
  mode="light"
  scheme="default"
  gtk_theme="$GTK_THEME_LIGHT"
  icon_theme="$ICON_THEME_LIGHT"
  flavor="latte" # used in file names
else
  mode="dark"
  scheme="prefer-dark"
  gtk_theme="$GTK_THEME_DARK"
  icon_theme="$ICON_THEME_DARK"
  flavor="mocha"
fi

gsettings set org.gnome.desktop.interface color-scheme "$scheme"
gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"

theme_links "$flavor"

notify-send "Theme" "Switched to ${mode}" 2>/dev/null || true
