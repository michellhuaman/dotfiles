#!/usr/bin/env bash
# Bump every pinned version in this repo and the dotfiles to the latest
# stable release, on a new branch in each repo, one commit per bump, so a
# bump that breaks something in the test VM can be dropped on its own.
#
#   dotfiles:  mise itself (version and checksums), the Nerd Font, the CLI
#              tools in mise's config, the Neovim plugins (lazy-lock.json),
#              and the Fedora release of the distrobox container
#   checked only: Bitwarden's polkit action (system/) against upstream;
#              a difference is shown for review, never copied in
#
# The branches are made in worktrees next to this repo
# (../workstation-bootstrap-<branch>, ../dotfiles-<branch>), so neither
# main nor the live dotfiles (chezmoi's source) change. A repo where
# nothing changed gets no branch. Nothing is pushed.
#
#   bash update-pins.sh
#
# Then test the branches in a VM, merge and push: see "Updating the pinned
# versions" in the README.
#
# Options:
#   --branch NAME    branch name in both repos (default: pins-YYYY-MM-DD)
#   --dotfiles DIR   the dotfiles repo (default: chezmoi's source)
#
# GitHub allows 60 anonymous API calls an hour; if that runs out, set
# GITHUB_TOKEN (any token, no scopes needed) and run it again.

set -euo pipefail

branch="pins-$(date +%F)"
dot_repo=""

die()  { echo "error: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }
warn() { echo "!! $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)   branch="${2:?--branch needs a name}"; shift 2 ;;
    --dotfiles) dot_repo="${2:?--dotfiles needs a folder}"; shift 2 ;;
    -h|--help)  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
done

for cmd in git curl python3 sha256sum unzip chezmoi tar; do
  command -v "$cmd" >/dev/null || die "$cmd is missing"
done
mise_bin="$(command -v mise || echo "$HOME/.local/bin/mise")"
[[ -x "$mise_bin" ]] || die "mise is missing; run chezmoi apply first"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
boot_repo="$(git -C "$script_dir" rev-parse --show-toplevel)"
[[ -n "$dot_repo" ]] || dot_repo="$(chezmoi source-path 2>/dev/null)" \
  || die "can't find the dotfiles; pass --dotfiles DIR"
dot_repo="$(git -C "$dot_repo" rev-parse --show-toplevel)" || die "$dot_repo is not a git repo"

work_root="$(dirname "$boot_repo")"
boot_wt="$work_root/workstation-bootstrap-$branch"
dot_wt="$work_root/dotfiles-$branch"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
summary="$tmp/summary"   # one line per result, printed at the end
review="$tmp/review"     # things to look at by hand
: >"$summary"; : >"$review"
note() { echo "$*"; echo "$*" >>"$summary"; }

# curl for downloads, retried while the network settles.
fetch() {
  curl -fsSL --connect-timeout 10 --retry 4 --retry-delay 5 --retry-all-errors "$@"
}

# GitHub's API; GITHUB_TOKEN, if set, lifts the anonymous rate limit.
gh_api() {
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fetch -H "Accept: application/vnd.github+json" "${auth[@]}" "https://api.github.com$1"
}

# Tag of a GitHub repo's latest release. "Latest" on GitHub is never a
# pre-release or a draft.
latest_release() {
  gh_api "/repos/$1/releases/latest" | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
}

# set_value FILE REGEX VALUE: the regex must match exactly one line, and its
# named group "v" is replaced with VALUE. Stops if it matches 0 or 2+ times,
# so a file whose layout changed is never half-edited.
set_value() {
  python3 - "$@" <<'EOF'
import re, sys
path, pattern, value = sys.argv[1:4]
text = open(path).read()
matches = list(re.finditer(pattern, text, re.M))
if len(matches) != 1:
    sys.exit(f"{path}: expected 1 line matching {pattern!r}, found {len(matches)}")
m = matches[0]
open(path, "w").write(text[:m.start("v")] + value + text[m.end("v"):])
EOF
}

# commit WORKTREE MESSAGE: commits the changes there, if any.
commit() {
  if git -C "$1" diff --quiet; then return 0; fi
  git -C "$1" commit -q -a -m "$2"
  note "  committed: $2"
}

# ---- branches -------------------------------------------------------------------
info "Branch $branch in both repos"
for repo in "$boot_repo" "$dot_repo"; do
  name="$(basename "$repo")"
  git -C "$repo" rev-parse --verify -q main >/dev/null || die "$name has no main branch"
  ! git -C "$repo" rev-parse --verify -q "refs/heads/$branch" >/dev/null \
    || die "$name already has a branch $branch; delete it or pass --branch"
  # Start from main as it is on GitHub. Fetching needs Bitwarden unlocked.
  if git -C "$repo" fetch -q origin main 2>/dev/null; then
    behind="$(git -C "$repo" rev-list --count main..origin/main)"
    ahead="$(git -C "$repo" rev-list --count origin/main..main)"
    (( behind == 0 )) || die "$name's main is $behind commits behind GitHub; pull first"
    (( ahead == 0 )) || warn "$name's main has $ahead commits not on GitHub yet; the branch includes them"
  else
    warn "couldn't fetch $name (is Bitwarden unlocked?); starting from the local main"
  fi
done
[[ ! -e "$boot_wt" ]] || die "$boot_wt already exists"
[[ ! -e "$dot_wt" ]] || die "$dot_wt already exists"
git -C "$boot_repo" worktree add -q -b "$branch" "$boot_wt" main
git -C "$dot_repo" worktree add -q -b "$branch" "$dot_wt" main
echo "Worktrees: $boot_wt"
echo "           $dot_wt"

# ---- the bumps --------------------------------------------------------------------
# Each runs in a subshell with set -e on its own, so one that fails (a
# download, a changed file layout) is reported and the rest still run.

polkit_action() {
  local f="$boot_wt/system/com.bitwarden.Bitwarden.policy"
  fetch -o "$tmp/upstream.policy" \
    https://raw.githubusercontent.com/bitwarden/clients/main/apps/desktop/resources/com.bitwarden.desktop.policy
  if cmp -s "$f" "$tmp/upstream.policy"; then
    note "Bitwarden polkit action: same as upstream"
  else
    note "Bitwarden polkit action: CHANGED upstream (not copied; see below)"
    touch "$tmp/keep-bootstrap"   # keep the branch to copy it into
    {
      echo "Bitwarden's polkit action changed upstream. Review it, and if it's fine, copy"
      echo "it over system/com.bitwarden.Bitwarden.policy in $boot_wt and commit:"
      echo "  https://github.com/bitwarden/clients/commits/main/apps/desktop/resources/com.bitwarden.desktop.policy"
      diff -u --label "system/com.bitwarden.Bitwarden.policy" --label "upstream" \
        "$f" "$tmp/upstream.policy" | sed 's/^/    /' || true
    } >>"$review"
  fi
}

mise_itself() {
  local f="$dot_wt/.chezmoidata/packages.yaml" cur new arch asset sum
  cur="$(sed -n 's/^  version: *\(v[^ #]*\).*/\1/p' "$f")"
  new="$(latest_release jdx/mise)"
  if [[ "$cur" == "$new" ]]; then note "mise: $cur is the latest"; return 0; fi
  # Checksums from the release's own list (which mise also signs:
  # SHASUMS256.txt.minisig, SHASUMS256.asc).
  fetch -o "$tmp/SHASUMS256.txt" "https://github.com/jdx/mise/releases/download/$new/SHASUMS256.txt"
  for arch in amd64:x64 arm64:arm64; do
    asset="mise-$new-linux-${arch#*:}"
    sum="$(awk -v a="$asset" '$2 == a || $2 == "./" a { print $1 }' "$tmp/SHASUMS256.txt")"
    [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || { echo "no checksum for $asset in SHASUMS256.txt" >&2; return 1; }
    set_value "$f" "^\s*${arch%%:*}: (?P<v>[0-9a-f]{64})" "$sum"
  done
  set_value "$f" '^  version: (?P<v>v[^\s#]+)' "$new"
  commit "$dot_wt" "Bump mise from $cur to $new"
}

nerd_font() {
  local f="$dot_wt/.chezmoidata/packages.yaml" cur new
  cur="$(sed -n 's/^ *nerd_fonts: *\(v[^ #]*\).*/\1/p' "$f")"
  new="$(latest_release ryanoasis/nerd-fonts)"
  if [[ "$cur" == "$new" ]]; then note "Nerd Font: $cur is the latest"; return 0; fi
  set_value "$f" '^\s*nerd_fonts: (?P<v>v[^\s#]+)' "$new"
  commit "$dot_wt" "Bump the Nerd Font from $cur to $new"
}

cli_tools() {
  local f="$dot_wt/dot_config/mise/config.toml" json name req new n=0
  # mise reads only the worktree's config (run from an empty folder, so no
  # project config joins in) and lists each tool's newest stable release.
  mkdir -p "$tmp/empty"
  json="$(cd "$tmp/empty" && MISE_GLOBAL_CONFIG_FILE="$f" "$mise_bin" outdated --bump --json)"
  while IFS=$'\t' read -r name req new; do
    [[ -n "$name" ]] || continue
    set_value "$f" "^\s*\"?$(python3 -c 'import re, sys; print(re.escape(sys.argv[1]))' "$name")\"?\s*=\s*\"(?P<v>[^\"]*)\"" "$new"
    commit "$dot_wt" "mise: bump $name from $req to $new"
    n=$((n + 1))
  done < <(python3 - "$f" "$json" <<'EOF'
import json, os, sys
path, data = os.path.realpath(sys.argv[1]), json.loads(sys.argv[2] or "{}")
for name, t in sorted(data.items()):
    src = os.path.realpath((t.get("source") or {}).get("path", ""))
    if src == path and t.get("bump") and t["bump"] != t.get("requested"):
        print(f'{name}\t{t["requested"]}\t{t["bump"]}')
EOF
)
  (( n )) || note "CLI tools: all at the latest release"
}

nvim_plugins() {
  local lock="$dot_wt/dot_config/nvim/lazy-lock.json" home="$tmp/nvim" nvim_bin changed
  nvim_bin="$("$mise_bin" which nvim)"
  # The worktree's Neovim config, run in throwaway folders: the live config,
  # plugins and lockfile are left alone. mise's own folders stay the real
  # ones, so its shims (tree-sitter, for the parsers) keep working.
  mkdir -p "$home/home"
  chezmoi --source "$dot_wt" archive --format tar "$HOME/.config/nvim" | tar -xm -C "$home/home"
  echo "Updating Neovim plugins in a scratch folder (takes a minute)"
  if ! XDG_CONFIG_HOME="$home/home/.config" XDG_DATA_HOME="$home/data" \
       XDG_STATE_HOME="$home/state" XDG_CACHE_HOME="$home/cache" \
       MISE_CONFIG_DIR="$HOME/.config/mise" MISE_DATA_DIR="$HOME/.local/share/mise" \
       MISE_STATE_DIR="$HOME/.local/state/mise" MISE_CACHE_DIR="$HOME/.cache/mise" \
       timeout 900 "$nvim_bin" --headless "+Lazy! sync" +qa >"$tmp/nvim.log" 2>&1; then
    tail -20 "$tmp/nvim.log" >&2
    return 1
  fi
  changed="$(python3 - "$lock" "$home/home/.config/nvim/lazy-lock.json" <<'EOF'
import json, sys
old, new = (json.load(open(p)) for p in sys.argv[1:3])
names = sorted(set(old) | set(new))
print(sum(1 for n in names if old.get(n, {}).get("commit") != new.get(n, {}).get("commit")))
EOF
)"
  if (( changed == 0 )); then note "Neovim plugins: all at the latest commit"; return 0; fi
  cp "$home/home/.config/nvim/lazy-lock.json" "$lock"
  commit "$dot_wt" "Update Neovim plugins ($changed changed, lazy-lock.json)"
}

fedora_release() {
  local f="$dot_wt/dot_config/distrobox/assemble.ini" cur latest
  # Fedora's own list of releases; "45 Beta" and the like don't count. The
  # container follows Fedora's latest stable release.
  latest="$(fetch https://fedoraproject.org/releases.json | python3 -c '
import json, sys
vers = [int(r["version"]) for r in json.load(sys.stdin)
        if r.get("variant") == "Workstation" and r.get("arch") == "x86_64"
        and r.get("version", "").isdigit()]
print(max(vers))')"
  note "Fedora: $latest is the latest stable release"
  cur="$(sed -n 's|^image=registry.fedoraproject.org/fedora-toolbox:\([0-9]*\)$|\1|p' "$f")"
  if [[ "$cur" -ge "$latest" ]]; then note "distrobox container: fedora-toolbox:$cur"; return 0; fi
  fetch -o /dev/null -I "https://registry.fedoraproject.org/v2/fedora-toolbox/manifests/$latest" \
    || { echo "registry.fedoraproject.org has no fedora-toolbox:$latest yet" >&2; return 1; }
  set_value "$f" '^image=registry\.fedoraproject\.org/fedora-toolbox:(?P<v>[0-9]+)$' "$latest"
  commit "$dot_wt" "distrobox: fedora-toolbox $cur to $latest"
}

failed=()
run() {
  local rc
  info "$1"
  set +e
  ( set -e; "$2" )
  rc=$?
  set -e
  if (( rc )); then
    warn "$1: failed (left as it was)"
    echo "$1: FAILED (left as it was; see the output above)" >>"$summary"
    failed+=("$1")
  fi
}

run "Bitwarden polkit action" polkit_action
run "mise" mise_itself
run "Nerd Font" nerd_font
run "CLI tools (mise)" cli_tools
run "Neovim plugins" nvim_plugins
run "Fedora release (distrobox)" fedora_release

# ---- results --------------------------------------------------------------------
info "Summary"
cat "$summary"

kept=()
for pair in "workstation-bootstrap:$boot_repo:$boot_wt" "dotfiles:$dot_repo:$dot_wt"; do
  IFS=: read -r label repo wt <<<"$pair"
  keep=false
  [[ "$wt" == "$boot_wt" && -e "$tmp/keep-bootstrap" ]] && keep=true
  if ! $keep && [[ -z "$(git -C "$wt" status --porcelain)" && "$(git -C "$wt" rev-list --count "main..$branch")" == 0 ]]; then
    git -C "$repo" worktree remove "$wt"
    git -C "$repo" branch -q -D "$branch"
    echo "$label: nothing to bump, no branch"
  else
    kept+=("$wt")
    echo
    echo "$label ($wt):"
    git -C "$wt" log --oneline "main..$branch" | sed 's/^/  /'
    $keep && echo "  (kept for the polkit action under \"To review\")"
  fi
done

if [[ -s "$review" ]]; then
  info "To review"
  cat "$review"
fi

if (( ${#kept[@]} )); then
  info "Next"
  echo "Test the $branch branches in a VM, then merge and push them:"
  echo "README, \"Updating the pinned versions\", steps 2-5."
else
  info "Everything is at the latest release; nothing to test."
fi
(( ${#failed[@]} == 0 )) || { warn "failed: ${failed[*]}"; exit 1; }
