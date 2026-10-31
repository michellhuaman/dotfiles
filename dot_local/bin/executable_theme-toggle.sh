#!/usr/bin/env bash
#
# theme-toggle.sh
# Toggles GNOME/GTK color-scheme, GTK theme, and icon theme between
# light and dark.
#
# Bind it via Settings > Keyboard > View and Customize Shortcuts > Custom
# Shortcuts, pointing the command at the full path, e.g.:
#   /home/youruser/.local/bin/theme-toggle.sh
#
# Note on bat: this script only switches which theme bat's config points to,
# which does NOT require rebuilding bat's cache. Run `bat cache --build`
# (or `batcat cache --build` on Ubuntu/Debian) manually only when you add,
# remove, or update theme files in "$(bat --config-dir)/themes", e.g. after
# first installing the Catppuccin themes.

set -uo pipefail

CONFIG_DIR="$HOME/.config"

# Pick GTK and icon themes based on the running distro.
# Ubuntu ships Yaru; everything else (Fedora included) gets GNOME's
# upstream default, Adwaita. Adwaita has no separate dark icon theme,
# so the icons stay "Adwaita" in both modes.
distro_id="$(. /etc/os-release 2>/dev/null && echo "${ID:-}")"

case "$distro_id" in
ubuntu)
  GTK_THEME_LIGHT="Yaru"
  GTK_THEME_DARK="Yaru-dark"
  ICON_THEME_LIGHT="Yaru"
  ICON_THEME_DARK="Yaru-dark"
  ;;
*)
  GTK_THEME_LIGHT="Adwaita"
  GTK_THEME_DARK="Adwaita-dark" # only affects GTK3 apps
  ICON_THEME_LIGHT="Adwaita"
  ICON_THEME_DARK="Adwaita"
  ;;
esac

# Apply a sed substitution to a config file only if that file exists,
# so a missing app config never aborts the rest of the toggle.
apply_sed() {
  local pattern="$1"
  local file="$2"
  if [[ -f "$file" ]]; then
    sed -i "$pattern" "$file"
  fi
}

current="$(gsettings get org.gnome.desktop.interface color-scheme)"

# Decide the target mode, then apply it once below.
if [[ "$current" == "'prefer-dark'" ]]; then
  mode="light"
  scheme="default"
  gtk_theme="$GTK_THEME_LIGHT"
  icon_theme="$ICON_THEME_LIGHT"
  flavor="latte" # lowercase, used in file names
  label="Latte"  # capitalized, used in bat's theme name
else
  mode="dark"
  scheme="prefer-dark"
  gtk_theme="$GTK_THEME_DARK"
  icon_theme="$ICON_THEME_DARK"
  flavor="mocha"
  label="Mocha"
fi

gsettings set org.gnome.desktop.interface color-scheme "$scheme"
gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"

apply_sed "s#themes/catppuccin-[a-z]*\.toml#themes/catppuccin-${flavor}.toml#" \
  "$CONFIG_DIR/alacritty/alacritty.toml"

apply_sed "s#palette = \"catppuccin_[a-z]*\"#palette = \"catppuccin_${flavor}\"#" \
  "$CONFIG_DIR/starship.toml"

apply_sed "s#themes/catppuccin_[a-z]*\.theme#themes/catppuccin_${flavor}.theme#" \
  "$CONFIG_DIR/btop/btop.conf"

apply_sed "s#--theme[= ].*#--theme=\"Catppuccin ${label}\"#" \
  "$CONFIG_DIR/bat/config"

notify-send "Theme" "Switched to ${mode}" 2>/dev/null || true
