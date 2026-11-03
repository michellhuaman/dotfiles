#!/usr/bin/env bash
#
# theme-toggle.sh
# Toggles GNOME/GTK color-scheme, GTK theme, and icon theme between
# light and dark.
#
# Bind it via Settings > Keyboard > View and Customize Shortcuts > Custom
# Shortcuts, pointing the command at the full path, e.g.:
#   /home/youruser/.local/bin/theme-toggle.sh
# (The dotfiles bind it to Super+Shift+T.)
#
# It also switches the Catppuccin flavor (Latte for light, Mocha for dark):
# - Alacritty, btop and bat read a "current" link that points at the
#   flavor's file; this script repoints the links (see theme_links);
# - starship has no way to include a file, so the palette line in
#   ~/.config/starship.toml is edited in place.
#
#   theme-toggle.sh         toggle light/dark
#   theme-toggle.sh links   only point the links at the current mode's flavor
#                           (chezmoi runs this on apply, for a new machine)
#
# Note on bat: switching its config link does NOT require rebuilding bat's
# cache. Run `bat cache --build` (or `batcat cache --build` on Ubuntu/Debian)
# only when you add, remove, or update theme files in
# "$(bat --config-dir)/themes".

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

# Points each "current" link at the file for flavor $1. chezmoi tracks the
# theme files but not the links, so toggling never shows up as a change. A
# link is only made where its target exists, and a real file in its place is
# left alone.
theme_links() {
  local f="$1"
  link() { # $1 = link, $2 = target, relative to the link's folder
    local dir
    dir="$(dirname "$1")"
    [[ -e "$dir/$2" ]] || return 0
    if [[ -e "$1" && ! -L "$1" ]]; then
      echo "theme-toggle: $1 is a real file, not changing it" >&2
      return 0
    fi
    ln -sfn "$2" "$1"
  }
  # btop reads its theme when it starts, and bat its config on every run.
  link "$CONFIG_DIR/alacritty/themes/catppuccin-current.toml" "catppuccin-$f.toml"
  link "$CONFIG_DIR/btop/themes/catppuccin_current.theme" "catppuccin_$f.theme"
  link "$CONFIG_DIR/bat/config" "config-$f"
  # Open Alacritty windows reload when alacritty.toml changes, but don't
  # notice the imported link changing when its path goes through a link
  # (/home is one, to /var/home, on Fedora's atomic desktops). Touching
  # alacritty.toml makes them reload, and re-read the link; its contents
  # don't change, so chezmoi sees no difference.
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

apply_sed "s#palette = \"catppuccin_[a-z]*\"#palette = \"catppuccin_${flavor}\"#" \
  "$CONFIG_DIR/starship.toml"

theme_links "$flavor"

notify-send "Theme" "Switched to ${mode}" 2>/dev/null || true
