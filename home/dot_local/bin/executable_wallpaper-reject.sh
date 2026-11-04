#!/usr/bin/env bash
# Asks, in a zenity dialog, what to do with the wallpaper on screen:
#   Move to Trash   trash it and show another one
#   Move to light   file it under ~/Pictures/wallpapers/light
#   Move to dark    file it under ~/Pictures/wallpapers/dark
# "On screen" is the current mode's: picture-uri-dark in dark mode,
# picture-uri in light mode. When the wallpaper leaves the current mode's
# folder (trashed, or moved to the other mode's), the mode gets a new one;
# moved into the current mode's folder, it stays on screen.
# Only touches files under ~/Pictures/wallpapers, never a system background.
#
# The dotfiles' GNOME settings bind it to Super+Shift+W. A file trashed by
# mistake can be put back from the Trash in Files (Restore).
set -euo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
SCHEMA=org.gnome.desktop.background

notify() { notify-send -i preferences-desktop-wallpaper "Wallpaper" "$1" 2>/dev/null || true; }
fail() { notify "$1"; echo "$1" >&2; exit 1; }

command -v zenity &>/dev/null || fail "zenity is not installed."

if [[ "$(gsettings get org.gnome.desktop.interface color-scheme)" == "'prefer-dark'" ]]; then
  mode=dark key=picture-uri-dark
else
  mode=light key=picture-uri
fi

uri=$(gsettings get "$SCHEMA" "$key" | tr -d "'")
file=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$uri")

dir_real=$(realpath -- "$DIR")
file_real=$(realpath -m -- "$file")
name=${file_real##*/}
if [[ ! -f "$file_real" || "$file_real" != "$dir_real"/* ]]; then
  notify "The wallpaper on screen isn't in $DIR, so there's nothing to sort: $file"
  exit 0
fi

case "${file_real%/*}" in
  "$dir_real/light") folder=light ;;
  "$dir_real/dark")  folder=dark ;;
  *)                 folder="" ;;
esac

# zenity's --text is Pango markup.
esc() { local s=${1//&/&amp;}; s=${s//</&lt;}; printf '%s' "${s//>/&gt;}"; }
choice=$(zenity --list --title="Wallpaper" \
  --text="$(esc "$name")${folder:+ (in $folder/)}" \
  --column="Action" --hide-header --height=240 \
  "Move to Trash" "Move to light" "Move to dark") || exit 0
[[ -n "$choice" ]] || exit 0

case "$choice" in
  "Move to Trash")
    err=$(gio trash -- "$file_real" 2>&1) || fail "Couldn't move $name to the Trash: $err"
    "$HOME/.local/bin/random-wallpaper.sh" "$mode" >/dev/null
    notify "Moved $name to the Trash"
    ;;
  "Move to light" | "Move to dark")
    target=${choice#Move to }
    if [[ "$folder" == "$target" ]]; then
      notify "$name is already in $target/"
      exit 0
    fi
    dest="$dir_real/$target/$name"
    [[ -e "$dest" ]] && fail "Not moved: $target/ already has a file named $name"
    mkdir -p "$dir_real/$target"
    mv -n -- "$file_real" "$dest"
    if [[ "$target" == "$mode" ]]; then
      gsettings set "$SCHEMA" "$key" "file://$dest"   # still on screen, at its new path
    else
      "$HOME/.local/bin/random-wallpaper.sh" "$mode" >/dev/null
    fi
    notify "Moved $name to $target/"
    ;;
esac
