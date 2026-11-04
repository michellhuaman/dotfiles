#!/usr/bin/env bash
# Bump the pinned Nerd Font in home/ to the latest stable release, on a new
# branch, so it can be tested in the VM before merging, and check
# Bitwarden's polkit action (system/) against upstream: a difference is
# shown for review, never copied in. (The CLI tools in mise's config aren't
# pinned: `update` upgrades them.)
#
# The branch is made in a worktree, ~/repos/workstation-<branch>, so main
# and the live dotfiles (chezmoi's clone) don't change. If nothing changed,
# no branch is kept. Nothing is pushed.
#
#   bash update-pins.sh
#
# Then test the branch in a VM, merge and push: see "Updating the pinned
# versions" in the README.
#
# Options:
#   --branch NAME    branch name (default: pins-YYYY-MM-DD)
#
# GitHub allows 60 anonymous API calls an hour; if that runs out, set
# GITHUB_TOKEN (any token, no scopes needed) and run it again.

set -euo pipefail

branch="pins-$(date +%F)"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }
warn() { echo "!! $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)   branch="${2:?--branch needs a name}"; shift 2 ;;
    -h|--help)  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
done

for cmd in git curl python3; do
  command -v "$cmd" >/dev/null || die "$cmd is missing"
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$script_dir" rev-parse --show-toplevel)"
wt="$HOME/repos/workstation-$branch"

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

# ---- branch ---------------------------------------------------------------------
info "Branch $branch"
git -C "$repo" rev-parse --verify -q main >/dev/null || die "no main branch"
! git -C "$repo" rev-parse --verify -q "refs/heads/$branch" >/dev/null \
  || die "a branch $branch already exists; delete it or pass --branch"
# Start from main as it is on GitHub.
if git -C "$repo" fetch -q origin main 2>/dev/null; then
  behind="$(git -C "$repo" rev-list --count main..origin/main)"
  ahead="$(git -C "$repo" rev-list --count origin/main..main)"
  (( behind == 0 )) || die "main is $behind commits behind GitHub; pull first"
  (( ahead == 0 )) || warn "main has $ahead commits not on GitHub yet; the branch includes them"
else
  warn "couldn't fetch from GitHub; starting from the local main"
fi
[[ ! -e "$wt" ]] || die "$wt already exists"
mkdir -p "$(dirname "$wt")"
git -C "$repo" worktree add -q -b "$branch" "$wt" main
echo "Worktree: $wt"

# ---- the bumps --------------------------------------------------------------------
# Each runs in a subshell with set -e on its own, so one that fails (a
# download, a changed file layout) is reported and the rest still run.

polkit_action() {
  local f="$wt/system/com.bitwarden.Bitwarden.policy"
  fetch -o "$tmp/upstream.policy" \
    https://raw.githubusercontent.com/bitwarden/clients/main/apps/desktop/resources/com.bitwarden.desktop.policy
  if cmp -s "$f" "$tmp/upstream.policy"; then
    note "Bitwarden polkit action: same as upstream"
  else
    note "Bitwarden polkit action: CHANGED upstream (not copied; see below)"
    touch "$tmp/keep"   # keep the branch to copy it into
    {
      echo "Bitwarden's polkit action changed upstream. Review it, and if it's fine, copy"
      echo "it over system/com.bitwarden.Bitwarden.policy in $wt and commit:"
      echo "  https://github.com/bitwarden/clients/commits/main/apps/desktop/resources/com.bitwarden.desktop.policy"
      diff -u --label "system/com.bitwarden.Bitwarden.policy" --label "upstream" \
        "$f" "$tmp/upstream.policy" | sed 's/^/    /' || true
    } >>"$review"
  fi
}

nerd_font() {
  local f="$wt/home/.chezmoidata/packages.yaml" cur new sha
  cur="$(sed -n 's/^ *nerd_fonts: *\(v[^ #]*\).*/\1/p' "$f")"
  new="$(latest_release ryanoasis/nerd-fonts)"
  if [[ "$cur" == "$new" ]]; then note "Nerd Font: $cur is the latest"; return 0; fi
  # The release's own checksum for the file the font script downloads,
  # pinned with the version, so the download is checked against it.
  sha="$(fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/$new/SHA-256.txt" \
         | awk '$2 == "JetBrainsMono.tar.xz" { print $1 }')"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "no checksum for JetBrainsMono.tar.xz in $new's SHA-256.txt" >&2; return 1; }
  set_value "$f" '^\s*nerd_fonts: (?P<v>v[^\s#]+)' "$new"
  set_value "$f" '^\s*nerd_fonts_sha256: (?P<v>[0-9a-f]+)' "$sha"
  commit "$wt" "Bump the Nerd Font from $cur to $new"
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
run "Nerd Font" nerd_font

# ---- results --------------------------------------------------------------------
info "Summary"
cat "$summary"

kept=false
if [[ ! -e "$tmp/keep" && -z "$(git -C "$wt" status --porcelain)" \
      && "$(git -C "$wt" rev-list --count "main..$branch")" == 0 ]]; then
  git -C "$repo" worktree remove "$wt"
  git -C "$repo" branch -q -D "$branch"
  echo "Nothing to bump, no branch"
else
  kept=true
  echo
  echo "$branch ($wt):"
  git -C "$wt" log --oneline "main..$branch" | sed 's/^/  /'
  [[ -e "$tmp/keep" ]] && echo "  (kept for the polkit action under \"To review\")"
fi

if [[ -s "$review" ]]; then
  info "To review"
  cat "$review"
fi

if $kept; then
  info "Next"
  echo "Test the $branch branch in a VM, then merge and push it:"
  echo "README, \"Updating the pinned versions\", steps 2-5."
else
  info "Everything is at the latest release; nothing to test."
fi
(( ${#failed[@]} == 0 )) || { warn "failed: ${failed[*]}"; exit 1; }
