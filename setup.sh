#!/usr/bin/env bash
# Set up a fresh Fedora Workstation or Ubuntu desktop install.
#
#   1. System:    removes unwanted preinstalled apps, then native packages,
#                 COPR or universe, snaps, i2c access (sudo)
#   2. Bitwarden: Flathub, Bitwarden and chezmoi, then waits while you turn on
#                 Bitwarden's SSH agent and checks that GitHub accepts the key
#   3. Dotfiles:  chezmoi clones the dotfiles over SSH and applies them; its
#                 scripts install the flatpaks, fonts and user services (no sudo)
#
# Run it from a terminal inside GNOME, as your normal user:
#   bash /path/to/workstation-bootstrap/setup.sh
#
# Safe to run again: installed packages are skipped, and if the dotfiles are
# already cloned it runs `chezmoi update` (pull and apply) instead.
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
    -h|--help)   sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ---- checks ---------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "run this as your normal user; it uses sudo when needed"
[[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] \
  || die "run this from a terminal inside your GNOME session; Bitwarden needs a desktop"

# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" fedora "*) distro=fedora ;;
  *" ubuntu "*) distro=ubuntu ;;
  *) die "unsupported distro '${ID:-unknown}'; this repo has lists for Fedora and Ubuntu" ;;
esac
[[ -f "$script_dir/$distro/packages.txt" ]] || die "$distro/packages.txt not found next to setup.sh"

info "Setting up ${PRETTY_NAME:-$ID} for $(id -un)"
command -v curl >/dev/null && { curl -fsSI --max-time 10 https://github.com >/dev/null \
  || die "can't reach github.com; connect to the network and run this again"; }

# ---- 1. system ------------------------------------------------------------------
fedora_remove() {
  local patterns installed
  mapfile -t patterns < <(read_list "$script_dir/fedora/remove.txt")
  (( ${#patterns[@]} )) || return 0
  # Entries may be globs (libreoffice*); keep only what is installed.
  mapfile -t installed < <(rpm -qa --qf '%{NAME}\n' "${patterns[@]}" 2>/dev/null | sort -u || true)
  if (( ${#installed[@]} )); then
    echo "Removing ${#installed[@]} packages: ${installed[*]}"
    sudo dnf remove -y "${installed[@]}"
  else
    echo "Nothing from fedora/remove.txt is installed"
  fi
}

fedora_system() {
  mapfile -t coprs < <(read_list "$script_dir/fedora/copr.txt")
  mapfile -t pkgs  < <(read_list "$script_dir/fedora/packages.txt")

  fedora_remove

  if (( ${#coprs[@]} )); then
    dnf copr --help >/dev/null 2>&1 || sudo dnf install -y 'dnf-command(copr)'
    for c in "${coprs[@]}"; do
      sudo dnf copr enable -y "$c"
    done
  fi
  echo "Installing ${#pkgs[@]} packages"
  sudo dnf install -y "${pkgs[@]}"
}

ubuntu_remove() {
  local p wanted=() installed=() extra=()
  mapfile -t wanted < <(read_list "$script_dir/ubuntu/remove.txt")
  for p in "${wanted[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' \
      && installed+=("$p")
  done
  if (( ! ${#installed[@]} )); then
    echo "Nothing from ubuntu/remove.txt is installed"
    return 0
  fi
  # Removing a package can also remove anything that depends on it, such as
  # Ubuntu's desktop metapackage. Only go ahead if apt would remove exactly
  # what was asked for.
  mapfile -t extra < <("${apt[@]}" -s purge "${installed[@]}" \
    | awk '/^Purg /{print $2}' | grep -vxF -f <(printf '%s\n' "${installed[@]}") || true)
  if (( ${#extra[@]} )); then
    warn "Not removing ${installed[*]}: apt would also remove ${extra[*]}"
    return 0
  fi
  echo "Removing ${#installed[@]} packages: ${installed[*]}"
  "${apt[@]}" purge -y "${installed[@]}"
}

ubuntu_remove_snaps() {
  local name names=()
  mapfile -t names < <(read_list "$script_dir/ubuntu/remove-snaps.txt")
  for name in "${names[@]}"; do
    if snap list "$name" >/dev/null 2>&1; then
      echo "Removing snap $name"
      sudo snap remove --purge "$name"
    fi
  done
}

ubuntu_system() {
  mapfile -t pkgs  < <(read_list "$script_dir/ubuntu/packages.txt")
  mapfile -t snaps < <(read_list "$script_dir/ubuntu/snaps.txt")
  # Right after installation Ubuntu updates itself in the background; wait for
  # its lock instead of failing.
  apt=(sudo apt-get -o DPkg::Lock::Timeout=900)

  ubuntu_remove

  if ! apt-cache policy | grep -q '/universe'; then
    echo "Enabling universe"
    "${apt[@]}" update
    "${apt[@]}" install -y software-properties-common
    sudo add-apt-repository -y universe
  fi
  "${apt[@]}" update
  echo "Installing ${#pkgs[@]} packages"
  "${apt[@]}" install -y "${pkgs[@]}"

  if command -v snap >/dev/null; then
    # The first snap command on a fresh install fails until snapd is seeded.
    sudo snap wait system seed.loaded
    ubuntu_remove_snaps
    local line name
    for line in "${snaps[@]}"; do
      read -ra args <<<"$line"
      name="${args[0]}"
      if snap list "$name" >/dev/null 2>&1; then
        echo "snap $name already installed"
      else
        sudo snap install "${args[@]}"
      fi
    done
  fi
}

i2c_access() {
  # ddcutil talks to external monitors through /dev/i2c-*.
  echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
  sudo modprobe i2c-dev || true
  if getent group i2c >/dev/null; then
    sudo usermod -aG i2c "$USER"
  fi
}

if $do_system; then
  info "Step 1/3: system packages (sudo)"
  sudo -v || die "your user needs sudo rights"
  # Package installs can outlast sudo's timeout; keep it fresh so you're only
  # asked once.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
  sudo_keepalive=$!
  trap 'kill "$sudo_keepalive" 2>/dev/null || true' EXIT

  "${distro}_system"
  i2c_access

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
  sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b "$bin_dir"
fi
chezmoi --version

# Trust GitHub's published host keys (fetched over HTTPS) instead of
# whatever answers the first time.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
known_hosts="$HOME/.ssh/known_hosts"
if ! ssh-keygen -F github.com -f "$known_hosts" >/dev/null 2>&1; then
  keys="$(curl -fsS --max-time 10 https://api.github.com/meta | tr -d '\n' \
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

echo "Checking GitHub (approve the request in Bitwarden if it asks)"
gh_error=""
until github_ok; do
  warn "GitHub didn't accept a key: $gh_error"
  read -rp "Check Bitwarden, then press Enter to try again (Ctrl+C to stop) " _
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
Next: reboot, then log into GNOME as usual.
  Flatpak apps only show up in the app grid after a fresh login, and the reboot
  also loads the i2c module and group that ddc-brightness.sh needs.

    systemctl reboot

If anything failed, fix it in the matching repo, push, and run this again:
  bash $script_dir/setup.sh          (add --no-system if only the dotfiles failed)
EOF
