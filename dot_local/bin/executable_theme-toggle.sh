#!/usr/bin/env bash
#
# theme-toggle.sh
# Toggles GNOME/GTK color-scheme, GTK theme, and icon theme between
# light and dark.
#
# Bind this to a key in your sway config, e.g.:
#   bindsym $mod+shift+t exec ~/.local/bin/theme-toggle.sh

set -euo pipefail

CONFIG_DIR="$HOME/.config"

GTK_THEME_LIGHT="Yaru"
GTK_THEME_DARK="Yaru-dark"

ICON_THEME_LIGHT="Yaru"
ICON_THEME_DARK="Yaru-dark"

current="$(gsettings get org.gnome.desktop.interface color-scheme)"

if [[ "$current" == "'prefer-dark'" ]]; then
  # Switch to light
  gsettings set org.gnome.desktop.interface color-scheme 'default'
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_LIGHT"
  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_LIGHT"
  
  # Alacritty
  sed -i "s#themes/catppuccin-[a-z]*\.toml#themes/catppuccin-latte.toml#" \
  "$CONFIG_DIR/alacritty/alacritty.toml"

  # Starship Prompt
  sed -i "s#palette = \"catppuccin_[a-z]*\"#palette = \"catppuccin_latte\"#" \
  "$CONFIG_DIR/starship.toml"

  # Btop
  sed -i "s#themes/catppuccin_[a-z]*\.theme#themes/catppuccin_latte.theme#" \
  "$CONFIG_DIR/btop/btop.conf"

  # Bat
  sed -i "s#--theme[= ].*#--theme=\"Catppuccin Latte\"#" \
  "$CONFIG_DIR/bat/config"
  batcat cache --build
 
  notify-send "Theme" "Switched to light" 2>/dev/null || true
else
  # Switch to dark
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_DARK"
  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_DARK"
  
  # Alacritty
  sed -i "s#themes/catppuccin-[a-z]*\.toml#themes/catppuccin-mocha.toml#" \
  "$CONFIG_DIR/alacritty/alacritty.toml"

  # Starship Prompt
  sed -i "s#palette = \"catppuccin_[a-z]*\"#palette = \"catppuccin_mocha\"#" \
  "$CONFIG_DIR/starship.toml"

  # Btop
  sed -i "s#themes/catppuccin_[a-z]*\.theme#themes/catppuccin_mocha.theme#" \
  "$CONFIG_DIR/btop/btop.conf"

  # Bat
  sed -i "s#--theme[= ].*#--theme=\"Catppuccin Mocha\"#" \
  "$CONFIG_DIR/bat/config"
  batcat cache --build

  notify-send "Theme" "Switched to dark" 2>/dev/null || true
fi
