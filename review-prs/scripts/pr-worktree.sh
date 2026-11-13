#!/usr/bin/env bash
# Temp worktree of a PR's head commit, so a review never touches the user's own checkout.
# Usage (run inside the repo's git checkout):
#   pr-worktree.sh create <PR_NUMBER_OR_URL>   prints two lines: the worktree dir, then the head sha
#   pr-worktree.sh cleanup <worktree dir>      removes a dir made by 'create'; refuses anything else
set -u

die() { echo "pr-worktree: $*" >&2; exit 1; }

# The dir must be what 'create' makes (review-wt-<number>.<random>) and sit directly in the temp dir.
check_dir() {
  local dir=$1 parent tmp slash_tmp
  [ -n "$dir" ] || die "missing worktree dir"
  [ -d "$dir" ] && [ ! -L "$dir" ] || die "not a plain directory: $dir"
  case "$(basename "$dir")" in
    review-wt-[0-9]*.*) ;;
    *) die "refusing, not a review worktree: $dir" ;;
  esac
  parent=$(cd "$(dirname "$dir")" && pwd -P) || die "cannot resolve parent of $dir"
  tmp=$(cd "${TMPDIR:-/tmp}" && pwd -P) || die "cannot resolve TMPDIR"
  slash_tmp=$(cd /tmp && pwd -P)
  [ "$parent" = "$tmp" ] || [ "$parent" = "$slash_tmp" ] || die "refusing, $dir is not directly in the temp dir"
}

cmd=${1:-}
[ $# -gt 0 ] && shift

case $cmd in
  create)
    pr=${1:-}
    [ -n "$pr" ] || die "usage: pr-worktree.sh create <PR_NUMBER_OR_URL>"
    case $pr in
      http*://*/pull/*) pr=$(printf %s "$pr" | sed -E 's#.*/pull/([0-9]+).*#\1#') ;;
    esac
    case $pr in *[!0-9]*) die "invalid PR: $pr" ;; esac
    git rev-parse --git-dir >/dev/null 2>&1 || die "run this inside the repo's git checkout"

    # Fetch the live PR head, then pin to exactly that commit.
    git fetch -q origin "pull/$pr/head" || die "cannot fetch pull/$pr/head from origin"
    sha=$(git rev-parse --verify "FETCH_HEAD^{commit}") || die "no commit fetched"
    dir=$(mktemp -d "${TMPDIR:-/tmp}/review-wt-$pr.XXXXXX") || die "mktemp failed"
    if ! git worktree add -q --detach "$dir" "$sha" 2>/dev/null; then
      rmdir "$dir" 2>/dev/null
      die "git worktree add failed"
    fi
    echo "$dir"
    echo "$sha"
    ;;
  cleanup)
    dir=${1:-}
    check_dir "$dir"
    # Find the main repo from inside the worktree, so this also works when run from anywhere.
    common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) && common=$(cd "$dir" && cd "$common" && pwd -P)
    if [ -n "${common:-}" ] && git --git-dir="$common" worktree remove --force "$dir" 2>/dev/null; then
      :
    else
      rm -rf -- "${dir:?}"
    fi
    [ -n "${common:-}" ] && git --git-dir="$common" worktree prune 2>/dev/null
    echo "pr-worktree: removed $dir"
    ;;
  *)
    die "usage: pr-worktree.sh create <PR> | cleanup <dir>"
    ;;
esac
