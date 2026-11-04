#!/usr/bin/env bash
# Moves the wallpaper on screen to the Trash and shows a new one from the
# same folder. "On screen" is the current mode's: picture-uri-dark in dark
# mode, picture-uri in light mode. Only removes files under
# ~/Pictures/wallpapers, never a system background.
#
# The dotfiles' GNOME settings bind it to Super+Shift+W. A file trashed by
# mistake can be put back from the Trash in Files (Restore).
set -euo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
SCHEMA=org.gnome.desktop.background

notify() { notify-send -i preferences-desktop-wallpaper "Wallpaper" "$1" 2>/dev/null || true; }

if [[ "$(gsettings get org.gnome.desktop.interface color-scheme)" == "'prefer-dark'" ]]; then
  mode=dark key=picture-uri-dark
else
  mode=light key=picture-uri
fi

uri=$(gsettings get "$SCHEMA" "$key" | tr -d "'")
file=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$uri")

dir_real=$(realpath -- "$DIR")
file_real=$(realpath -m -- "$file")
if [[ -f "$file_real" && "$file_real" == "$dir_real"/* ]]; then
  if ! err=$(gio trash -- "$file_real" 2>&1); then
    notify "Couldn't move ${file_real##*/} to the Trash: $err"
    echo "$err" >&2
    exit 1
  fi
  msg="Moved ${file_real##*/} to the Trash"
else
  msg="Kept $file (not in $DIR)"
fi

"$HOME/.local/bin/random-wallpaper.sh" "$mode" >/dev/null
notify "$msg"
echo "$msg"
