#!/bin/sh
#
# screenshot-menu.sh
# -------------------
# Presents a small fuzzel menu letting the user pick what kind of
# screenshot to take, then delegates the actual capture to grimshot.
#
# Requirements:
#   - fuzzel   (dmenu-style application launcher)
#   - grimshot (wrapper around grim/slurp for wlroots compositors)
#
# Behavior:
#   - "Area"   -> lets you drag-select a region of the screen
#   - "Window" -> captures the currently focused window
#   - "Output" -> captures a chosen monitor/output
#   - "Screen" -> captures the entire screen
#   - Anything else (menu dismissed / Esc) exits cleanly with status 0
#
# Screenshots are saved (and copied to the clipboard, via `savecopy`)
# into ~/Pictures/Screenshots. This script makes sure that directory
# exists before invoking grimshot, since grimshot will fail if the
# target directory is missing.

# Directory where screenshots should be stored.
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"

# Make sure the destination directory exists (no error if it already does).
mkdir -p "$SCREENSHOT_DIR"

# Show the selection menu via fuzzel and capture the user's choice.
choice=$(printf "Area\nWindow\nOutput\nScreen" | fuzzel --dmenu --prompt "Screenshot: ")

# Build a custom, timestamped filename so each capture gets a unique name
# and nothing gets silently overwritten.
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
filename="$SCREENSHOT_DIR/scrot-${timestamp}.png"

# Dispatch to the appropriate grimshot capture mode.
case "$choice" in
"Area")
  # Interactively select a rectangular area to capture.
  grimshot --notify savecopy area "$filename"
  ;;
"Window")
  # Capture the currently focused window.
  grimshot --notify savecopy window "$filename"
  ;;
"Output")
  # Capture a specific output/monitor (prompts if more than one).
  grimshot --notify savecopy output "$filename"
  ;;
"Screen")
  # Capture the entire screen (all outputs).
  grimshot --notify savecopy screen "$filename"
  ;;
*)
  # No selection was made (menu closed/cancelled) — exit quietly.
  exit 0
  ;;
esac
