#!/bin/sh
# Brave (the apt package, from workstation-bootstrap) as the default browser for links and web pages; without
# this, the distro's own mimeapps.list (Fedora's, or Ubuntu's) picks Firefox.
# xdg-settings/xdg-mime only change these lines of ~/.config/mimeapps.list,
# so entries other programs add there (e.g. Claude Code's claude-cli) stay.
# Edit this file to run it again.
set -eu

browser=brave-browser.desktop
xdg-settings set default-web-browser "$browser"
xdg-mime default "$browser" \
    x-scheme-handler/http x-scheme-handler/https \
    text/html application/xhtml+xml
