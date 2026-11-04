#!/usr/bin/env bash
# Set a random GNOME wallpaper for each mode: one from ~/Pictures/wallpapers/light
# for light mode (picture-uri) and one from ~/Pictures/wallpapers/dark for dark
# mode (picture-uri-dark). GNOME shows the matching one when the color scheme
# changes, so theme-toggle.sh needs to do nothing.
#
# If light/ or dark/ has no images, that mode picks from the whole folder.
# Never picks the wallpaper a mode already has (when there's another choice).
set -euo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
SCHEMA=org.gnome.desktop.background

# Fills the array named $1 with the images under folder $2.
list_images() {
  local -n out="$1"
  out=()
  [[ -d "$2" ]] || return 0
  mapfile -d '' out < <(find "$2" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
}

# Sets gsettings key $1 to a random image from folder $2 (or all of $DIR).
set_random() {
  local key="$1" images current choice
  list_images images "$2"
  (( ${#images[@]} )) || list_images images "$DIR"
  if (( ${#images[@]} == 0 )); then
    echo "No images found in $DIR" >&2
    exit 1
  fi

  current=$(gsettings get "$SCHEMA" "$key" | tr -d "'")
  choice="${images[RANDOM % ${#images[@]}]}"
  if (( ${#images[@]} > 1 )); then
    while [[ "file://$choice" == "$current" ]]; do
      choice="${images[RANDOM % ${#images[@]}]}"
    done
  fi

  gsettings set "$SCHEMA" "$key" "file://$choice"
  echo "$key set to $choice"
}

set_random picture-uri      "$DIR/light"
set_random picture-uri-dark "$DIR/dark"
gsettings set "$SCHEMA" picture-options 'zoom'
