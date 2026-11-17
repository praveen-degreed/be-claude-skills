#!/usr/bin/env bash
# Fetch a PR once into a temp dir so agents read local files instead of re-calling gh. Read-only.
# Usage: fetch-pr.sh <PR_NUMBER_OR_URL> [--repo owner/name] [--worktree DIR]   (first stdout line = temp dir)
# --worktree DIR: copy the changed files from the PR worktree (pinned to the PR head) instead of calling the GitHub API per file.
set -u

die() { echo "fetch-pr: $*" >&2; exit 1; }

pr="" repo="" wt=""
while [ $# -gt 0 ]; do
  case $1 in
    --repo) repo=${2:-}; shift ;;
    --worktree) wt=${2:-}; shift ;;
    *) pr=$1 ;;
  esac
  shift
done
[ -n "$pr" ] || die "usage: fetch-pr.sh <PR_NUMBER_OR_URL> [--repo owner/name] [--worktree DIR]"

command -v gh >/dev/null || die "gh CLI not found; install it from https://cli.github.com"
command -v jq >/dev/null || die "jq not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"

case $pr in
  http*://*/pull/*)
    repo=$(printf %s "$pr" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')
    pr=$(printf %s "$pr" | sed -E 's#.*/pull/([0-9]+).*#\1#')
    ;;
esac
case $pr in *[!0-9]*) die "invalid PR: $pr" ;; esac
[ -n "$repo" ] || repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || die "cannot determine repo; pass --repo owner/name"

dir=$(mktemp -d "${TMPDIR:-/tmp/}review-pr-$pr.XXXXXX") || die "mktemp failed"
echo "$dir"

gh pr view "$pr" --repo "$repo" --json title,body,additions,deletions,changedFiles,headRefName,headRefOid,baseRefName >"$dir/meta.json" || die "cannot read PR $repo#$pr"
gh pr diff "$pr" --repo "$repo" >"$dir/pr.diff" || die "cannot fetch diff"
gh pr diff "$pr" --repo "$repo" --name-only >"$dir/files.txt" || die "cannot fetch file list"
awk 'function flush() { if (f != "") print f "\t+" a "\t-" d "\toffset " s }
  /^diff --git / { flush(); f = $4; sub(/^b\//, "", f); a = 0; d = 0; s = NR; inh = 0; next }
  /^@@/ { if (!inh) { s = NR; inh = 1 }; next }
  inh && /^\+/ { a++ } inh && /^-/ { d++ }
  END { flush() }' "$dir/pr.diff" >"$dir/stats.txt"
gh pr checks "$pr" --repo "$repo" 2>/dev/null | awk -F'\t' '$2 == "fail"' >"$dir/checks.txt"

ref=$(jq -r .headRefName "$dir/meta.json")
: >"$dir/skipped.txt"
mkdir -p "$dir/head"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case $f in *.png | *.jpg | *.jpeg | *.gif | *.ico | *.woff | *.woff2 | *.ttf | *.lock) echo "$f (binary/lock)" >>"$dir/skipped.txt"; continue ;; esac
  if [ -n "$wt" ]; then
    [ -f "$wt/$f" ] && [ "$(wc -c <"$wt/$f")" -le 204800 ] || { echo "$f (deleted, unreadable or too large)" >>"$dir/skipped.txt"; continue; }
    mkdir -p "$dir/head/$(dirname "$f")" && cp "$wt/$f" "$dir/head/$f" || { echo "$f (copy failed)" >>"$dir/skipped.txt"; }
    continue
  fi
  json=$(gh api "repos/$repo/contents/$f?ref=$ref" 2>/dev/null) || { echo "$f (deleted or unreadable)" >>"$dir/skipped.txt"; continue; }
  size=$(printf %s "$json" | jq -r '.size // 0')
  if [ "$size" -gt 204800 ]; then echo "$f (${size} bytes, too large)" >>"$dir/skipped.txt"; continue; fi
  mkdir -p "$dir/head/$(dirname "$f")"
  printf %s "$json" | jq -r '.content | gsub("\n"; "") | @base64d' >"$dir/head/$f" || { rm -f "$dir/head/$f"; echo "$f (decode failed)" >>"$dir/skipped.txt"; }
done <"$dir/files.txt"
