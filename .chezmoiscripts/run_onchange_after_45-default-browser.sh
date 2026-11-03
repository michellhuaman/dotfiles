#!/bin/sh
# Brave (Flatpak) as the default browser for links and web pages; without
# this, Fedora's /usr/share/applications/mimeapps.list picks Firefox.
# xdg-settings/xdg-mime only change these lines of ~/.config/mimeapps.list,
# so entries other programs add there (e.g. Claude Code's claude-cli) stay.
# Edit this file to run it again.
set -eu

browser=com.brave.Browser.desktop
xdg-settings set default-web-browser "$browser"
xdg-mime default "$browser" \
    x-scheme-handler/http x-scheme-handler/https \
    text/html application/xhtml+xml
