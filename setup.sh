#!/usr/bin/env bash
# Set up a fresh Fedora Sway Atomic install (image-based Fedora with sway).
#
#   1. System:    Fedora's third-party repos, COPRs and vendor repos; makes the
#                 layered packages match lists/layered.txt; turns on
#                 automatic updates; Catppuccin login screen; polkit action
#                 for Bitwarden's unlock with system authentication (sudo).
#                 Nothing is removed from the base image.
#   2. Bitwarden: Flathub, Bitwarden and chezmoi, then waits while you turn on
#                 Bitwarden's SSH agent and checks that GitHub accepts the key
#   3. Dotfiles:  chezmoi clones the dotfiles over SSH and applies them; its
#                 scripts install the flatpaks, CLI tools, fonts and user
#                 services (no sudo)
#
# Run it from a terminal in your desktop session, as your normal user:
#   bash /path/to/workstation-bootstrap/setup.sh
#
# Safe to run again: the lists in lists/ are the whole state, so a rerun
# only changes what differs from them, and if the dotfiles are already cloned
# it runs `chezmoi update` (pull and apply) instead.
#
# Options:
#   --branch NAME   dotfiles branch to clone on the first run, e.g. a test branch
#   --user NAME     GitHub username (default: GITHUB_USER below)
#   --repo NAME     dotfiles repository name (default: dotfiles)
#   --no-system     skip step 1, e.g. when re-running after a dotfiles fix

set -euo pipefail

GITHUB_USER="michellhuaman"
repo="dotfiles"
branch=""
do_system=true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
bw_app="com.bitwarden.desktop"
bw_sock="$HOME/.var/app/$bw_app/data/.bitwarden-ssh-agent.sock"

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
repo_url="git@github.com:$GITHUB_USER/$repo.git"

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
  || die "run this from a terminal inside your desktop session; Bitwarden needs a desktop"

# shellcheck disable=SC1091
. /etc/os-release
# Sway Atomic boots from an image (ostree) and has no dnf on the host.
[[ " ${ID:-} ${ID_LIKE:-} " == *" fedora "* && -e /run/ostree-booted && "${VARIANT_ID:-}" == sway-atomic ]] \
  || die "this repo sets up Fedora Sway Atomic; this is ${PRETTY_NAME:-${ID:-an unknown system}}"
lists="$script_dir/lists"
[[ -f "$lists/layered.txt" ]] || die "lists/layered.txt not found next to setup.sh"

info "Setting up ${PRETTY_NAME:-$ID} for $(id -un)"
fetch -I --max-time 10 https://github.com >/dev/null \
  || die "can't reach github.com; connect to the network and run this again"

# ---- 1. system ------------------------------------------------------------------

# Downloads the signing keys listed in $1 (<url> <file name> [fingerprint])
# into the directory $2. With a fingerprint, stops if the key doesn't match.
install_keys() {
  local list="$1" dest="$2" line url name fpr got tmp
  while read -r line; do
    read -r url name fpr <<<"$line"
    echo "Adding key $name"
    tmp="$(mktemp)"
    fetch "$url" -o "$tmp"
    if [[ -n "$fpr" ]]; then
      got="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
      [[ "$got" == "$fpr" ]] || { rm -f "$tmp"; die "key $name has fingerprint '$got', expected $fpr"; }
    fi
    sudo install -m 644 "$tmp" "$dest/$name"
    rm -f "$tmp"
  done < <(read_list "$list")
}

# Prints one list field (e.g. requested-packages) of the newest deployment,
# one entry per line. The newest is the staged one if an update is waiting
# for a reboot, so changes made earlier in this run are counted.
ostree_list() {
  rpm-ostree status --json | python3 -c '
import json, sys
deps = json.load(sys.stdin).get("deployments", [])
print("\n".join(deps[0].get(sys.argv[1], [])) if deps else "")' "$1" | sed '/^$/d'
}

# Prints the lines of $1 that aren't lines of $2 (both newline-separated).
missing_from() {
  grep -vxF -f <(printf '%s\n' "$2") <<<"$1" | sed '/^$/d' || true
}

# Login screen (SDDM): Catppuccin's theme in Latte and Mocha, from a pinned
# release, checked against its checksums. The image's theme folder is
# read-only, so the themes go to /usr/local/share/sddm/themes (which is under
# /var), and /etc/sddm.conf.d/10-catppuccin.conf points SDDM at the
# catppuccin-current link there. The image's other SDDM settings (sway runs
# the login screen) stay as they are.
# sddm-flavor (system/) repoints the link; a sudoers rule lets you run it
# without a password, so the dotfiles' theme-toggle.sh can switch the login
# screen along with everything else. Everything stays root-owned: a theme is
# code the login screen runs.
sddm_version="v1.1.2"
sddm_accent="lavender" # also in system/sddm-flavor
declare -A sddm_sha256=(
  [latte]=c5f0dffa27faae35b1b940f84c6f6f6fb1301e11a6017a51b6d33bc881867f4b
  [mocha]=08b5a99524bff09b3beedd292c5897433308a914a639236f04b15be60cef0829
)

sddm_theme() {
  local themes=/usr/local/share/sddm/themes flavor name tmp
  sudo mkdir -p "$themes"
  # Replaced on every run, so a new pinned version (or a damaged copy) is
  # picked up; the catppuccin-current link is kept.
  for flavor in latte mocha; do
    name="catppuccin-$flavor-$sddm_accent"
    echo "Installing login screen theme $name ($sddm_version)"
    tmp="$(mktemp -d)"
    fetch -o "$tmp/$name.zip" \
      "https://github.com/catppuccin/sddm/releases/download/$sddm_version/$name-sddm.zip" \
      || { rm -rf "$tmp"; die "couldn't download $name-sddm.zip"; }
    sha256sum -c --quiet <<<"${sddm_sha256[$flavor]}  $tmp/$name.zip" \
      || { rm -rf "$tmp"; die "$name-sddm.zip doesn't match its checksum"; }
    unzip -q "$tmp/$name.zip" -d "$tmp"
    [[ -f "$tmp/$name/metadata.desktop" ]] \
      || { rm -rf "$tmp"; die "$name-sddm.zip has no $name/metadata.desktop"; }
    sudo rm -rf "${themes:?}/$name"
    sudo cp -r "$tmp/$name" "$themes/"
    rm -rf "$tmp"
  done
  sudo chmod -R u=rwX,go=rX "$themes"
  # Dark by default; theme-toggle.sh (run by chezmoi apply) sets the real one.
  [[ -L "$themes/catppuccin-current" ]] \
    || sudo ln -s "catppuccin-mocha-$sddm_accent" "$themes/catppuccin-current"

  sudo install -m 755 -o root -g root "$script_dir/system/sddm-flavor" /usr/local/bin/sddm-flavor

  tmp="$(mktemp)"
  printf '%s ALL=(root) NOPASSWD: /usr/local/bin/sddm-flavor latte, /usr/local/bin/sddm-flavor mocha\n' \
    "$(id -un)" >"$tmp"
  sudo visudo -cqf "$tmp" || { rm -f "$tmp"; die "the sudoers rule for sddm-flavor doesn't parse"; }
  sudo install -m 440 -o root -g root "$tmp" /etc/sudoers.d/sddm-flavor
  rm -f "$tmp"

  tmp="$(mktemp)"
  printf '[Theme]\nThemeDir=%s\nCurrent=catppuccin-current\n' "$themes" >"$tmp"
  sudo mkdir -p /etc/sddm.conf.d
  sudo install -m 644 -o root -g root "$tmp" /etc/sddm.conf.d/10-catppuccin.conf
  rm -f "$tmp"
}

atomic_system() {
  local repo want have add drop

  # Fedora's third-party repos (RPM Fusion's NVIDIA driver and Steam, and
  # PyCharm). Turned on here, rather than by a first-boot switch,
  # so every machine has them. Safe to run again.
  # Done first, so rpm-ostree can resolve packages from them below.
  if command -v fedora-third-party >/dev/null; then
    echo "Enabling Fedora's third-party repositories"
    sudo fedora-third-party enable
  else
    warn "fedora-third-party not found; third-party repositories not enabled"
  fi

  # COPR repos: the repo file each project publishes, saved under the name
  # `dnf copr enable` uses. It names its key by https:// URL and uses
  # $releasever, so it keeps working after a Fedora upgrade. Fetched every
  # run, so a fixed-up file reaches the machine too.
  local copr owner project fver tmp
  fver="$(rpm -E %fedora)"
  while read -r copr; do
    owner="${copr%%/*}" project="${copr#*/}"
    echo "Adding COPR $copr"
    tmp="$(mktemp)"
    fetch -o "$tmp" \
      "https://copr.fedorainfracloud.org/coprs/$owner/$project/repo/fedora-$fver/$owner-$project-fedora-$fver.repo" \
      || { rm -f "$tmp"; die "couldn't download the repo file for COPR $copr"; }
    sudo install -m 644 "$tmp" "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:$owner:$project.repo"
    rm -f "$tmp"
  done < <(read_list "$lists/copr.txt")

  # Vendor repos: every file in lists/repos/ goes to /etc/yum.repos.d/.
  # Keys in keys.txt (optional, for a fingerprint check) go to /etc/pki/rpm-gpg/.
  install_keys "$lists/keys.txt" /etc/pki/rpm-gpg
  for repo in "$lists"/repos/*.repo; do
    [[ -e "$repo" ]] || continue
    echo "Adding repo $(basename "$repo")"
    sudo install -m 644 "$repo" /etc/yum.repos.d/
  done

  # Layered packages: the list is the whole set. --allow-inactive accepts a
  # package the base image already has, so the requested set always matches
  # the list.
  want="$(read_list "$lists/layered.txt")"
  have="$(ostree_list requested-packages)"
  mapfile -t add  < <(missing_from "$want" "$have")
  mapfile -t drop < <(missing_from "$have" "$want")
  if (( ${#add[@]} )); then
    echo "Layering ${#add[@]} packages: ${add[*]}"
    sudo rpm-ostree install --idempotent --allow-inactive "${add[@]}"
  else
    echo "All packages in layered.txt are already layered"
  fi
  if (( ${#drop[@]} )); then
    echo "Uninstalling layered packages no longer in layered.txt: ${drop[*]}"
    sudo rpm-ostree uninstall "${drop[@]}"
  fi

  # Automatic updates: download and stage new images in the background; they
  # take effect at the next reboot.
  local conf=/etc/rpm-ostreed.conf
  if ! grep -q '^AutomaticUpdatePolicy=stage' "$conf" 2>/dev/null; then
    echo "Turning on automatic (staged) OS updates"
    if grep -q '^#\{0,1\}AutomaticUpdatePolicy=' "$conf" 2>/dev/null; then
      sudo sed -i 's/^#\{0,1\}AutomaticUpdatePolicy=.*/AutomaticUpdatePolicy=stage/' "$conf"
    else
      printf '[Daemon]\nAutomaticUpdatePolicy=stage\n' | sudo tee -a "$conf" >/dev/null
    fi
    sudo rpm-ostree reload
  fi
  sudo systemctl enable --now rpm-ostreed-automatic.timer

  sddm_theme

  # Bitwarden "unlock with system authentication" (its Linux biometrics): the
  # Flatpak asks polkit, which needs Bitwarden's action. Bitwarden's guide
  # puts it in /usr/share/polkit-1/actions, read-only here; polkit reads
  # /etc/polkit-1/actions too. The file is a copy of Bitwarden's
  # apps/desktop/resources/com.bitwarden.desktop.policy (bitwarden/clients,
  # unchanged since 92a620dd9c06), kept here so nothing unpinned is
  # installed as root. restorecon gives it the label of the rest of /etc.
  echo "Installing Bitwarden's polkit action (unlock with system authentication)"
  sudo install -D -m 644 -o root -g root "$script_dir/system/com.bitwarden.Bitwarden.policy" \
    /etc/polkit-1/actions/com.bitwarden.Bitwarden.policy
  sudo restorecon -R /etc/polkit-1/actions
}

if $do_system; then
  info "Step 1/3: system packages (sudo)"
  sudo -v || die "your user needs sudo rights"
  # Package installs can outlast sudo's timeout; keep it fresh so you're only
  # asked once.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
  sudo_keepalive=$!
  trap 'kill "$sudo_keepalive" 2>/dev/null || true' EXIT

  atomic_system

  kill "$sudo_keepalive" 2>/dev/null || true
  trap - EXIT
  sudo -k   # nothing below needs root
else
  info "Step 1/3: skipped (--no-system)"
fi

for cmd in git ssh curl flatpak; do
  command -v "$cmd" >/dev/null || die "$cmd is missing; run setup.sh without --no-system"
done

# ---- 2. Bitwarden and chezmoi ---------------------------------------------------
info "Step 2/3: Bitwarden and chezmoi"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if flatpak info "$bw_app" >/dev/null 2>&1; then
  echo "Bitwarden already installed"
else
  flatpak install --user -y --noninteractive flathub "$bw_app"
fi

mkdir -p "$bin_dir"
case ":$PATH:" in *":$bin_dir:"*) ;; *) export PATH="$bin_dir:$PATH" ;; esac
if command -v chezmoi >/dev/null; then
  echo "chezmoi already installed"
else
  echo "Installing chezmoi to $bin_dir"
  sh -c "$(fetch https://get.chezmoi.io)" -- -b "$bin_dir"
fi
chezmoi --version

# Trust GitHub's published host keys (fetched over HTTPS) instead of
# whatever answers the first time.
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
ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o IdentityAgent="$bw_sock")

agent_ready() {
  [[ -S "$bw_sock" ]] && SSH_AUTH_SOCK="$bw_sock" ssh-add -l >/dev/null 2>&1
}

github_ok() {
  local out
  out="$(SSH_AUTH_SOCK="$bw_sock" ssh "${ssh_opts[@]}" -T git@github.com 2>&1 || true)"
  grep -q "successfully authenticated" <<<"$out" && return 0
  gh_error="$out"
  return 1
}

if ! agent_ready; then
  pgrep -f "$bw_app" >/dev/null || setsid -f flatpak run "$bw_app" >/dev/null 2>&1
  cat <<EOF

Bitwarden is opening. In it:
  1. Log in (master password and two-step login).
  2. File > Settings > App settings (all accounts): turn on "Enable SSH agent".
Leave Bitwarden open and unlocked, then come back here.
EOF
  until agent_ready; do
    read -rp "Press Enter when the SSH agent is on (Ctrl+C to stop) " _
    agent_ready || warn "The agent isn't answering yet, or has no keys. Is Bitwarden unlocked?"
  done
fi
echo "Bitwarden's SSH agent has these keys:"
SSH_AUTH_SOCK="$bw_sock" ssh-add -l | sed 's/^/   /'

# True if ssh's error in $1 means the network isn't up yet (e.g. right after
# boot), rather than a problem with the key.
network_error() {
  grep -qiE 'could not resolve hostname|temporary failure in name resolution|network is unreachable|no route to host|connection timed out|connection refused' <<<"$1"
}

echo "Checking GitHub (approve the request in Bitwarden if it asks)"
gh_error=""
net_tries=0
until github_ok; do
  # Network errors retry on their own for up to a minute, then ask like any
  # other error.
  if network_error "$gh_error" && (( net_tries < 12 )); then
    net_tries=$((net_tries + 1))
    warn "Network not ready ($(head -1 <<<"$gh_error")); retrying in 5 seconds ($net_tries/12)"
    sleep 5
    continue
  fi
  if network_error "$gh_error"; then
    warn "Still can't reach GitHub: $gh_error"
    read -rp "Check the network connection, then press Enter to try again (Ctrl+C to stop) " _
  else
    warn "GitHub didn't accept a key: $gh_error"
    read -rp "Check Bitwarden, then press Enter to try again (Ctrl+C to stop) " _
  fi
  net_tries=0
done
echo "GitHub accepts your key."

# ---- 3. dotfiles ----------------------------------------------------------------
info "Step 3/3: dotfiles"
export SSH_AUTH_SOCK="$bw_sock"
source_dir="$(chezmoi source-path 2>/dev/null || echo "${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi")"
if [[ -d "$source_dir/.git" ]]; then
  echo "Dotfiles already in $source_dir; pulling and applying"
  chezmoi update --verbose
else
  init_args=(init --apply --verbose)
  [[ -n "$branch" ]] && init_args+=(--branch "$branch")
  chezmoi "${init_args[@]}" "$repo_url"
fi

# ---- done -----------------------------------------------------------------------
info "Done."
cat <<EOF
Next: reboot, then log into sway as usual.
  Flatpak apps only show up in the launcher (rofi) after a fresh login.
  After the reboot, run `chezmoi apply` once: it builds the distrobox
  container (VS Code, htop, btop), which needs the layered distrobox.

    systemctl reboot

  In Bitwarden, unlock with your login password instead of the master
  password (or a fingerprint, if the machine has a reader): after logging
  in, File > Settings > Security > "Unlock with system authentication".
EOF
if [[ "$(rpm-ostree status --json | python3 -c '
import json, sys
deps = json.load(sys.stdin).get("deployments", [])
print(bool(deps and deps[0].get("staged")))')" == True ]]; then
  echo "  A new deployment is staged: layered packages apply after the reboot."
fi
cat <<EOF

If anything failed, fix it in the matching repo, push, and run this again:
  bash $script_dir/setup.sh          (add --no-system if only the dotfiles failed)
EOF
