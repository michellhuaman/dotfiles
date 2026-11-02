#!/usr/bin/env bash
# Set up a fresh Fedora Workstation, Fedora Silverblue or Ubuntu desktop install.
#
#   1. System:    removes unwanted preinstalled apps, then native packages,
#                 COPR or universe, snaps, groups (sudo). On Silverblue:
#                 makes the layered packages and base-image removals match
#                 the lists in silverblue/, and turns on automatic updates
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
# Fedora Atomic (Silverblue) boots from an image and has no dnf on the host.
[[ $distro == fedora && -e /run/ostree-booted ]] && distro=silverblue
main_list="packages.txt"
[[ $distro == silverblue ]] && main_list="layered.txt"
[[ -f "$script_dir/$distro/$main_list" ]] || die "$distro/$main_list not found next to setup.sh"

info "Setting up ${PRETTY_NAME:-$ID} for $(id -un)"
command -v curl >/dev/null && { curl -fsSI --max-time 10 https://github.com >/dev/null \
  || die "can't reach github.com; connect to the network and run this again"; }

# ---- 1. system ------------------------------------------------------------------

# Downloads the signing keys listed in $1 (<url> <file name> [fingerprint])
# into the directory $2. With a fingerprint, stops if the key doesn't match.
# apt reads a key by its extension: .gpg must be binary, .asc must be text.
# So a key published as text is converted only when its name ends in .gpg.
install_keys() {
  local list="$1" dest="$2" line url name fpr got tmp
  while read -r line; do
    read -r url name fpr <<<"$line"
    echo "Adding key $name"
    tmp="$(mktemp)"
    curl -fsSL "$url" -o "$tmp"
    if [[ -n "$fpr" ]]; then
      got="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
      [[ "$got" == "$fpr" ]] || { rm -f "$tmp"; die "key $name has fingerprint '$got', expected $fpr"; }
    fi
    if [[ "$name" == *.gpg ]] && grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$tmp"; then
      gpg --dearmor <"$tmp" >"$tmp.gpg" && mv "$tmp.gpg" "$tmp"
    fi
    sudo install -m 644 "$tmp" "$dest/$name"
    rm -f "$tmp"
  done < <(read_list "$list")
}

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

  # Vendor repos: every file in fedora/repos/ is copied to /etc/yum.repos.d/.
  # dnf imports the signing key named in each file (gpgkey=) on first install.
  local repo
  for repo in "$script_dir"/fedora/repos/*.repo; do
    [[ -e "$repo" ]] || continue
    echo "Adding repo $(basename "$repo")"
    sudo install -m 644 "$repo" /etc/yum.repos.d/
  done

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

  # Vendor repos: the signing keys in ubuntu/keys.txt go to /usr/share/keyrings/,
  # then every .sources or .list file in ubuntu/repos/ is copied to
  # /etc/apt/sources.list.d/. Each repo file names its key there.
  if [[ -n "$(read_list "$script_dir/ubuntu/keys.txt")" ]] \
     && ! { command -v curl && command -v gpg; } >/dev/null; then
    "${apt[@]}" update
    "${apt[@]}" install -y curl gpg     # curl isn't on a fresh Ubuntu desktop
  fi
  install_keys "$script_dir/ubuntu/keys.txt" /usr/share/keyrings
  local repo
  for repo in "$script_dir"/ubuntu/repos/*.sources "$script_dir"/ubuntu/repos/*.list; do
    [[ -e "$repo" ]] || continue
    echo "Adding repo $(basename "$repo")"
    sudo install -m 644 "$repo" /etc/apt/sources.list.d/
  done

  # Answers for packages that would otherwise ask a question while installing.
  read_list "$script_dir/ubuntu/debconf.txt" | sudo debconf-set-selections

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

silverblue_system() {
  local repo want have add drop app

  # Fedora's third-party repos (on Silverblue: RPM Fusion's NVIDIA driver and
  # Steam, and PyCharm). Turned on here, rather than by the first-boot switch,
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
    curl -fsSL -o "$tmp" \
      "https://copr.fedorainfracloud.org/coprs/$owner/$project/repo/fedora-$fver/$owner-$project-fedora-$fver.repo" \
      || { rm -f "$tmp"; die "couldn't download the repo file for COPR $copr"; }
    sudo install -m 644 "$tmp" "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:$owner:$project.repo"
    rm -f "$tmp"
  done < <(read_list "$script_dir/silverblue/copr.txt")

  # Vendor repos: every file in silverblue/repos/ goes to /etc/yum.repos.d/.
  # Keys in keys.txt (optional, for a fingerprint check) go to /etc/pki/rpm-gpg/.
  install_keys "$script_dir/silverblue/keys.txt" /etc/pki/rpm-gpg
  for repo in "$script_dir"/silverblue/repos/*.repo; do
    [[ -e "$repo" ]] || continue
    echo "Adding repo $(basename "$repo")"
    sudo install -m 644 "$repo" /etc/yum.repos.d/
  done

  # Base-image removals: the list is the whole set, so removals that are no
  # longer listed are undone. Entries that aren't in the image are skipped.
  want="$(read_list "$script_dir/silverblue/override-remove.txt")"
  have="$(ostree_list requested-base-removals)"
  add=() drop=()
  while read -r app; do
    [[ -n "$app" ]] || continue
    if rpm -q "$app" >/dev/null 2>&1; then add+=("$app"); else echo "$app isn't in the base image, skipping"; fi
  done <<<"$(missing_from "$want" "$have")"
  mapfile -t drop < <(missing_from "$have" "$want")
  if (( ${#add[@]} )); then
    echo "Removing from the base image: ${add[*]}"
    sudo rpm-ostree override remove "${add[@]}"
  fi
  if (( ${#drop[@]} )); then
    echo "Restoring to the base image (no longer in override-remove.txt): ${drop[*]}"
    sudo rpm-ostree override reset "${drop[@]}"
  fi

  # Layered packages: the list is the whole set. --allow-inactive accepts a
  # package the base image already has, so the requested set always matches
  # the list.
  want="$(read_list "$script_dir/silverblue/layered.txt")"
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

  # Preinstalled system Flatpaks (Fedora's remote), in one call so flatpak's
  # note about root's search path prints once.
  add=()
  while read -r app; do
    flatpak info --system "$app" >/dev/null 2>&1 && add+=("$app")
  done < <(read_list "$script_dir/silverblue/flatpak-remove.txt")
  if (( ${#add[@]} )); then
    echo "Removing ${#add[@]} flatpaks: ${add[*]}"
    sudo flatpak uninstall --system -y --noninteractive "${add[@]}"
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
}

# Adds you to group $1 if it exists (effective at the next login).
add_to_group() {
  local g="$1"
  getent group "$g" >/dev/null || return 1
  # On Silverblue, system groups can live in /usr/lib/group, which usermod
  # doesn't edit; copy the group into /etc/group first.
  if ! grep -q "^$g:" /etc/group && [[ -f /usr/lib/group ]] && grep -q "^$g:" /usr/lib/group; then
    grep "^$g:" /usr/lib/group | sudo tee -a /etc/group >/dev/null
  fi
  sudo usermod -aG "$g" "$USER"
}

join_groups() {
  # Groups from <distro>/groups.txt, for apps that need device access. Groups
  # that don't exist are skipped. Takes effect at the next login.
  local g
  while read -r g; do
    add_to_group "$g" || warn "group $g doesn't exist, skipping"
  done < <(read_list "$script_dir/$distro/groups.txt")
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
  join_groups

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
Next: reboot, then log into GNOME as usual.
  Flatpak apps only show up in the app grid after a fresh login, and group
  changes (groups.txt) take effect then too.

    systemctl reboot
EOF
if [[ $distro == silverblue ]] && [[ "$(rpm-ostree status --json | python3 -c '
import json, sys
deps = json.load(sys.stdin).get("deployments", [])
print(bool(deps and deps[0].get("staged")))')" == True ]]; then
  echo "  A new deployment is staged: layered packages and removals apply after the reboot."
fi
cat <<EOF

If anything failed, fix it in the matching repo, push, and run this again:
  bash $script_dir/setup.sh          (add --no-system if only the dotfiles failed)
EOF
