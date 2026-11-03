#!/usr/bin/env bash
# Set up a fresh Ubuntu (stock GNOME desktop) install.
#
#   1. System:    vendor repos (Brave, VS Code, mise, Claude Desktop; keys
#                 checked by fingerprint); makes sure the packages in lists/apt.txt are
#                 installed (and removes ones this script installed that
#                 were dropped from the list); adds you to the groups in
#                 lists/groups.txt; libvirt's default VM network; keeps
#                 automatic security updates on;
#                 polkit action for Bitwarden's unlock with system
#                 authentication (sudo). Nothing that came with Ubuntu is
#                 removed.
#   2. chezmoi:   the pinned release, and GitHub's SSH host keys
#   3. Dotfiles:  chezmoi clones the dotfiles (public, over HTTPS) and applies
#                 them, with pushes going over SSH (Bitwarden's agent); its
#                 scripts install the flatpaks, CLI tools, fonts, GNOME
#                 settings and user services
#                 (no sudo)
#
# Run it from a terminal in your GNOME session, as your normal user:
#   bash /path/to/workstation-bootstrap/setup.sh
#
# Nothing waits on Bitwarden: it's only needed later, to push.
#
# Safe to run again: lists/apt.txt is the whole set of packages this script
# manages, so a rerun only changes what differs from it, and if the dotfiles
# are already cloned it runs `chezmoi update` (pull and apply) instead.
#
# Options:
#   --branch NAME   dotfiles branch to clone on the first run (default: main)
#   --user NAME     GitHub username (default: GITHUB_USER below)
#   --repo NAME     dotfiles repository name (default: dotfiles)
#   --no-system     skip step 1, e.g. when re-running after a dotfiles fix

set -euo pipefail

GITHUB_USER="michellhuaman"
repo="dotfiles"
branch=""
# chezmoi release to install (update-pins.sh bumps it).
chezmoi_version="v2.74.0"
do_system=true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
# Packages this script installed (as opposed to ones Ubuntu came with), so a
# package dropped from lists/apt.txt can be removed without ever touching
# Ubuntu's own.
apt_state=/var/lib/workstation-bootstrap/apt-installed.txt

die()  { echo "error: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }
warn() { echo "!! $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)    branch="${2:?--branch needs a name}"; shift 2 ;;
    --user)      GITHUB_USER="${2:?--user needs a name}"; shift 2 ;;
    --repo)      repo="${2:?--repo needs a name}"; shift 2 ;;
    --no-system) do_system=false; shift ;;
    -h|--help)   awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)           die "unknown option: $1 (try --help)" ;;
  esac
done
# Pulls over HTTPS (public, no key needed); pushes over SSH (Bitwarden).
repo_url="https://github.com/$GITHUB_USER/$repo.git"
push_url="git@github.com:$GITHUB_USER/$repo.git"

# Prints the entries of a list file: comments, blank lines and trailing
# spaces removed, one entry per line.
read_list() {
  [[ -f "$1" ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' -e '/^$/d' "$1"
}

# curl for downloads. Right after boot (or a VM resume) the network can take a
# moment, so failures, including name resolution, are retried for about 30
# seconds before giving up.
fetch() {
  curl -fsSL --connect-timeout 10 --retry 6 --retry-delay 5 --retry-all-errors "$@"
}

# ---- checks ---------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "run this as your normal user; it uses sudo when needed"
[[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] \
  || die "run this from a terminal inside your desktop session; the dotfiles change its settings"

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] \
  || die "this script sets up Ubuntu; this is ${PRETTY_NAME:-${ID:-an unknown system}}"
lists="$script_dir/lists"
[[ -f "$lists/apt.txt" ]] || die "lists/apt.txt not found next to setup.sh"

info "Setting up ${PRETTY_NAME:-$ID} for $(id -un)"

# ---- 1. system ------------------------------------------------------------------

# Prints the lines of $1 that aren't lines of $2 (both newline-separated).
missing_from() {
  grep -vxF -f <(printf '%s\n' "$2") <<<"$1" | sed '/^$/d' || true
}

# True if package $1 is installed.
installed() {
  [[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" == installed ]]
}

# Downloads the signing keys listed in $1 (<url> <file name> <fingerprints,
# comma-separated>) into /etc/apt/keyrings, in the binary format apt reads.
# Stops if a file doesn't hold exactly the listed keys.
install_keys() {
  local line url name fprs got want tmp
  while read -r line; do
    read -r url name fprs <<<"$line"
    [[ -n "$fprs" ]] || die "apt-keys.txt: $name has no fingerprint"
    echo "Adding key $name"
    tmp="$(mktemp -d)"
    fetch "$url" -o "$tmp/key" || { rm -rf "$tmp"; die "couldn't download the key $name"; }
    # A throwaway GnuPG home, so nothing lands in ~/.gnupg.
    got="$(gpg --homedir "$tmp" --show-keys --with-colons "$tmp/key" 2>/dev/null \
           | awk -F: '/^pub:/ { getline; print $10 }' | sort | paste -sd,)"
    want="$(tr ',' '\n' <<<"$fprs" | sort | paste -sd,)"
    [[ "$got" == "$want" ]] \
      || { rm -rf "$tmp"; die "key $name has fingerprints '$got', expected $want"; }
    if head -c 5 "$tmp/key" | grep -q -- '-----'; then
      gpg --homedir "$tmp" --dearmor <"$tmp/key" >"$tmp/key.gpg"
    else
      cp "$tmp/key" "$tmp/key.gpg"
    fi
    sudo install -D -m 644 -o root -g root "$tmp/key.gpg" "/etc/apt/keyrings/$name"
    rm -rf "$tmp"
  done < <(read_list "$1")
}

ubuntu_system() {
  local want ours p add=() drop=()
  export DEBIAN_FRONTEND=noninteractive

  # Packages: install what's missing from apt.txt, and remember which ones
  # this script installed, right after each install, so a run that stops
  # halfway still knows them next time. Listed packages are marked as
  # manually installed, so autoremove never takes one away.
  want="$(read_list "$lists/apt.txt")"
  ours="$(cat "$apt_state" 2>/dev/null || true)"
  # Rewrites the state file as $ours: tee, not install /dev/stdin, because
  # sudo-rs doesn't pass a pipe through as a file.
  save_state() {
    ours="$(sed '/^$/d' <<<"$ours" | sort -u)"
    sudo mkdir -p "$(dirname "$apt_state")"
    sudo tee "$apt_state" <<<"$ours" >/dev/null
  }
  # Claude Desktop's package adds its own copy of its repo
  # (claude-desktop.list, with another key file) unless another source has
  # it, and so do Anthropic's manual install steps; apt refuses either next
  # to claude-desktop.sources (added below). A claude-desktop.list holding
  # only that repo goes, before the first update, which it would break.
  local cd_list=/etc/apt/sources.list.d/claude-desktop.list
  if [[ -f "$cd_list" ]] \
     && ! grep -v -e '^[[:space:]]*\(#.*\)\{0,1\}$' \
                  -e 'downloads\.claude\.ai/claude-desktop/' "$cd_list" | grep -q .; then
    echo "Removing $cd_list (claude-desktop.sources has the repo)"
    sudo rm -f "$cd_list"
  fi

  echo "Updating the package lists"
  sudo apt-get update -q

  # curl and gpg first: the vendor keys need them.
  local pre=()
  for p in curl gpg; do
    installed "$p" || pre+=("$p")
  done
  if (( ${#pre[@]} )); then
    echo "Installing ${pre[*]} (needed for the vendor keys)"
    sudo apt-get install -y -q "${pre[@]}"
    ours+=$'\n'"$(printf '%s\n' "${pre[@]}")"
    save_state
  fi

  # Vendor repos: keys from apt-keys.txt (checked by fingerprint) go to
  # /etc/apt/keyrings/, the files in apt-sources/ to /etc/apt/sources.list.d/.
  # Fetched every run, so a new key or repo file reaches the machine too.
  install_keys "$lists/apt-keys.txt"
  local src
  for src in "$lists"/apt-sources/*.sources; do
    [[ -e "$src" ]] || continue
    echo "Adding repo $(basename "$src")"
    sudo install -m 644 "$src" /etc/apt/sources.list.d/
  done
  # VS Code's package offers to add Microsoft's repo itself; it's already
  # here (vscode.sources), so tell it not to.
  echo "code code/add-microsoft-repo boolean false" | sudo debconf-set-selections
  sudo apt-get update -q

  while read -r p; do
    [[ -n "$p" ]] || continue
    installed "$p" || add+=("$p")
  done <<<"$want"
  if (( ${#add[@]} )); then
    echo "Installing ${#add[@]} packages: ${add[*]}"
    sudo apt-get install -y -q "${add[@]}"
    ours+=$'\n'"$(printf '%s\n' "${add[@]}")"
    save_state
  else
    echo "All packages in apt.txt are already installed"
  fi
  # shellcheck disable=SC2086
  sudo apt-mark manual $want >/dev/null

  # Packages this script installed earlier that are no longer listed. Ones
  # Ubuntu came with are never in the state file, so they always stay. No
  # autoremove: it would also take packages this script never touched
  # (`update` in .bashrc runs it, when you choose to).
  mapfile -t drop < <(missing_from "$ours" "$want")
  if (( ${#drop[@]} )); then
    echo "Removing packages no longer in apt.txt: ${drop[*]}"
    sudo apt-get remove -y -q "${drop[@]}"
    ours="$(missing_from "$ours" "$(printf '%s\n' "${drop[@]}")")"
    save_state
  fi

  # Groups from groups.txt, joined once (effective after a reboot). A
  # group whose package isn't installed doesn't exist yet: skipped, with a
  # warning.
  local g me
  me="$(id -un)"
  while read -r g; do
    if ! getent group "$g" >/dev/null; then
      warn "group $g doesn't exist (is its package installed?); not joining it"
    elif ! id -nG "$me" | tr ' ' '\n' | grep -qxF "$g"; then
      echo "Adding $me to the $g group (effective after a reboot)"
      sudo usermod -aG "$g" "$me"
    fi
  done < <(read_list "$lists/groups.txt")

  # libvirt's default network (NAT, 192.168.122.0/24) for VMs: the package
  # defines and autostarts it; this only makes sure it's there, starts at
  # boot, and runs now.
  if command -v virsh >/dev/null; then
    if ! sudo virsh -q net-info default >/dev/null 2>&1; then
      echo "Defining libvirt's default network"
      sudo virsh -q net-define /usr/share/libvirt/networks/default.xml
    fi
    sudo virsh -q net-autostart default >/dev/null
    # Read in full first: grep -q stops at the match, and sudo-rs, relaying
    # the rest, then fails with a broken pipe, which pipefail would take as
    # "not active".
    local net_info
    net_info="$(sudo virsh net-info default)"
    if ! grep -q '^Active: *yes' <<<"$net_info"; then
      echo "Starting libvirt's default network"
      sudo virsh -q net-start default
    fi
  fi

  # Automatic updates: Ubuntu installs security updates in the background
  # (unattended-upgrades). This only makes sure that stays on.
  local conf=/etc/apt/apt.conf.d/20auto-upgrades
  if ! grep -qs '^APT::Periodic::Unattended-Upgrade "1";' "$conf" \
     || ! grep -qs '^APT::Periodic::Update-Package-Lists "1";' "$conf"; then
    echo "Turning on automatic security updates"
    installed unattended-upgrades || sudo apt-get install -y -q unattended-upgrades
    printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
      | sudo tee "$conf" >/dev/null
  fi

  # Bitwarden "unlock with system authentication" (its Linux biometrics): the
  # Flatpak asks polkit, which needs Bitwarden's action. Bitwarden's guide
  # puts it in /usr/share/polkit-1/actions, which belongs to the packages;
  # polkit reads /etc/polkit-1/actions too, so it goes there. The file is a
  # copy of Bitwarden's apps/desktop/resources/com.bitwarden.desktop.policy
  # (bitwarden/clients, unchanged since 92a620dd9c06), kept here so nothing
  # unpinned is installed as root. polkitd only watches action folders that
  # existed when it started, and /etc/polkit-1/actions usually didn't; a
  # reload makes it read the file now without dropping the running
  # authentication agent (a restart could).
  echo "Installing Bitwarden's polkit action (unlock with system authentication)"
  sudo install -D -m 644 -o root -g root "$script_dir/system/com.bitwarden.Bitwarden.policy" \
    /etc/polkit-1/actions/com.bitwarden.Bitwarden.policy
  sudo systemctl reload polkit
}

if $do_system; then
  info "Step 1/3: system packages (sudo)"
  # `sudo true` rather than `sudo -v`: Ubuntu's sudo-rs always asks for a
  # password on -v, even where sudoers says NOPASSWD.
  sudo true || die "your user needs sudo rights"
  # Package installs can outlast sudo's timeout; keep it fresh so you're only
  # asked once.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
  sudo_keepalive=$!
  trap 'kill "$sudo_keepalive" 2>/dev/null || true' EXIT

  ubuntu_system

  kill "$sudo_keepalive" 2>/dev/null || true
  trap - EXIT
  sudo -k   # nothing below needs root
else
  info "Step 1/3: skipped (--no-system)"
fi

for cmd in git ssh-keygen curl flatpak; do
  command -v "$cmd" >/dev/null || die "$cmd is missing; run setup.sh without --no-system"
done
fetch -I --max-time 10 https://github.com >/dev/null \
  || die "can't reach github.com; connect to the network and run this again"

# ---- 2. chezmoi -----------------------------------------------------------------
# Bitwarden is one of the dotfiles' Flatpaks: nothing here needs it, since
# the dotfiles are cloned over HTTPS.
info "Step 2/3: chezmoi"
mkdir -p "$bin_dir"
case ":$PATH:" in *":$bin_dir:"*) ;; *) export PATH="$bin_dir:$PATH" ;; esac
# get.chezmoi.io checks the download against the release's checksums.
if [[ "$(chezmoi --version 2>/dev/null)" == "chezmoi version $chezmoi_version,"* ]]; then
  echo "chezmoi $chezmoi_version already installed"
else
  echo "Installing chezmoi $chezmoi_version to $bin_dir"
  sh -c "$(fetch https://get.chezmoi.io)" -- -b "$bin_dir" -t "$chezmoi_version"
fi
chezmoi --version

# Trust GitHub's published host keys (fetched over HTTPS) instead of
# whatever answers the first time, for the first push.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
known_hosts="$HOME/.ssh/known_hosts"
if ! ssh-keygen -F github.com -f "$known_hosts" >/dev/null 2>&1; then
  keys="$(fetch --max-time 10 https://api.github.com/meta | tr -d '\n' \
          | sed -n 's/.*"ssh_keys": *\[\([^]]*\)\].*/\1/p' | tr ',' '\n' \
          | sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/github.com \1/p' || true)"
  if [[ -n "$keys" ]]; then
    printf '%s\n' "$keys" >>"$known_hosts"
    chmod 644 "$known_hosts"
    echo "Added GitHub's host keys to ~/.ssh/known_hosts"
  else
    warn "Couldn't fetch GitHub's host keys; ssh will trust the first one it sees"
  fi
fi

# ---- 3. dotfiles ----------------------------------------------------------------
info "Step 3/3: dotfiles"
source_dir="$(chezmoi source-path 2>/dev/null || echo "${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi")"
if [[ -d "$source_dir/.git" ]]; then
  echo "Dotfiles already in $source_dir; pulling and applying"
  chezmoi git -- remote set-url origin "$repo_url"
  chezmoi git -- remote set-url --push origin "$push_url"
  chezmoi update --verbose
else
  init_args=(init --apply --verbose)
  [[ -n "$branch" ]] && init_args+=(--branch "$branch")
  chezmoi "${init_args[@]}" "$repo_url"
  chezmoi git -- remote set-url --push origin "$push_url"
fi

# ---- done -----------------------------------------------------------------------
info "Done."
cat <<EOF
Next: reboot (systemctl reboot) and log in again. Flatpak apps only show up
in the app grid after a fresh login, new groups (libvirt) only reach the
desktop after a reboot (logging out keeps the old ones: GNOME's apps run
under your systemd user manager, which outlives a logout), and ddcutil's
i2c module loads at boot.

  In Bitwarden, after logging in (master password and two-step login):
  - File > Settings > App settings (all accounts): turn on "Enable SSH
    agent", so git push works (check with: ssh -T git@github.com);
  - File > Settings > Security: "Unlock with system authentication", to
    unlock with your login password (or a fingerprint, if the machine has
    a reader) instead of the master password.
EOF
if [[ -f /var/run/reboot-required ]]; then
  echo "  Ubuntu also says an update needs a reboot."
fi
cat <<EOF

If anything failed, fix it in the matching repo, push, and run this again:
  bash $script_dir/setup.sh          (add --no-system if only the dotfiles failed)
EOF
