#!/usr/bin/env bash
# Set a random GNOME wallpaper from ~/Pictures/wallpapers.
# Avoids picking the wallpaper that is currently set (when there's more than one).
set -euo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"

mapfile -d '' images < <(find "$DIR" -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

if (( ${#images[@]} == 0 )); then
  echo "No images found in $DIR" >&2
  exit 1
fi

current=$(gsettings get org.gnome.desktop.background picture-uri | tr -d "'")

pick() { printf '%s' "${images[RANDOM % ${#images[@]}]}"; }

choice=$(pick)
if (( ${#images[@]} > 1 )); then
  while [[ "file://$choice" == "$current" ]]; do choice=$(pick); done
fi

uri="file://$choice"
gsettings set org.gnome.desktop.background picture-uri "$uri"
gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
gsettings set org.gnome.desktop.background picture-options 'zoom'

echo "Wallpaper set to $choice"
