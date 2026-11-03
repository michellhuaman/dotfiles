#!/bin/bash
# Gives the virt-manager Flatpak the host's libvirt (qemu:///system,
# installed by workstation-bootstrap) as its connection, connected at start.
# virt-manager only finds it by itself by looking for /usr/bin/qemu-system-*,
# and in the sandbox /usr is the Flatpak runtime, so on its own it says
# "Could not detect a default hypervisor".
#
# Only sets the list while it's empty, so connections added or removed in
# virt-manager later stay as they are. Edit this file to run it again.
set -euo pipefail

app=org.virt_manager.virt-manager
schema=org.virt-manager.virt-manager.connections

if ! flatpak info --user "$app" >/dev/null 2>&1; then
  echo "!! $app isn't installed; skipping its connection" >&2
  exit 0
fi

gs() { flatpak run --command=gsettings "$app" "$@"; }
if [[ "$(gs get "$schema" uris)" == "@as []" ]]; then
  echo "==> virt-manager: connection qemu:///system"
  gs set "$schema" uris "['qemu:///system']"
  gs set "$schema" autoconnect "['qemu:///system']"
fi
