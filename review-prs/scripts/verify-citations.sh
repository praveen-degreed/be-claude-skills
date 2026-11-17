#!/usr/bin/env bash
# Check finding citations against the PR head before they are posted. No model, no gh. Read-only.
#
# Usage:
#   verify-citations.sh [--checkout DIR] <fetch-dir> <cite> [<cite> ...]   (cites also read from stdin, one per line)
#   verify-citations.sh --find <fetch-dir> <path> <token>                  (lines of head/<path> containing <token>)
#
# <cite> is  path:line  |  path:start-end  |  path:line=token
# With =token, the token (a code identifier the finding relies on) must appear within +-VERIFY_WINDOW (5)
# lines of the cited line. A line that exists but is about something else fails the check.
# Paths resolve against <fetch-dir>/head/<path>; a path that is a unique suffix of a changed file also resolves.
# A path that is not a changed file is looked up in --checkout DIR (the PR worktree) when given.
#
# Per cite prints one of:
#   OK <cite>  <the line, trimmed>
#   BAD <cite>  <reason>              missing file, line out of range, bad syntax
#   MISMATCH <cite>  <reason>         token not near the cited line (hint lists nearby real lines)
#   UNVERIFIABLE <cite>  <reason>     file was skipped by fetch-pr.sh (binary, too large, deleted)
#   UNCHECKED <cite>  <reason>        not a changed file and no checkout: must be labelled "local checkout"
# Exit 1 if any BAD, MISMATCH or UNVERIFIABLE; otherwise 0. Last line is a summary.
set -u
die() { echo "verify-citations: $*" >&2; exit 2; }

W=${VERIFY_WINDOW:-5}
case $W in '' | *[!0-9]*) die "VERIFY_WINDOW must be a number" ;; esac

checkout="" mode=verify rest=""
while [ $# -gt 0 ]; do
  case $1 in
    --checkout) checkout=${2:-}; shift ;;
    --find) mode=find ;;
    *) rest="$rest$1"$'\n' ;;
  esac
  shift
done

dir=$(printf '%s' "$rest" | sed -n 1p)
[ -n "$dir" ] && [ -d "$dir/head" ] && [ -f "$dir/files.txt" ] || die "usage: verify-citations.sh [--checkout DIR] <fetch-dir> <cite>... | --find <fetch-dir> <path> <token>"

# Resolve a cited path to a file: prints "<file>\t<resolved path>"; returns 1 (unchanged file), 2 (skipped), 3 (ambiguous).
resolve() {
  local p=$1 hits n
  if [ -f "$dir/head/$p" ]; then printf '%s\t%s\n' "$dir/head/$p" "$p"; return 0; fi
  if grep -qxF -- "$p" "$dir/files.txt" 2>/dev/null; then
    [ -f "$dir/skipped.txt" ] && grep -qF -- "$p " "$dir/skipped.txt" && { printf '%s\t%s\n' "" "$(grep -F -- "$p " "$dir/skipped.txt" | head -1)"; return 2; }
    return 1
  fi
  hits=$(grep -F -- "/$p" "$dir/files.txt" 2>/dev/null | awk -v p="/$p" 'length($0) >= length(p) && substr($0, length($0) - length(p) + 1) == p')
  n=$(printf '%s' "$hits" | grep -c . || true)
  if [ "$n" = 1 ]; then
    [ -f "$dir/head/$hits" ] && { printf '%s\t%s\n' "$dir/head/$hits" "$hits"; return 0; }
    printf '%s\t%s\n' "" "$(grep -F -- "$hits " "$dir/skipped.txt" 2>/dev/null | head -1)"; return 2
  fi
  [ "$n" -gt 1 ] && { printf '%s\t%s\n' "" "$(printf '%s' "$hits" | head -3 | tr '\n' ' ')"; return 3; }
  return 1
}

if [ "$mode" = find ]; then
  p=$(printf '%s' "$rest" | sed -n 2p); tok=$(printf '%s' "$rest" | sed -n 3p)
  [ -n "$p" ] && [ -n "$tok" ] || die "usage: verify-citations.sh --find <fetch-dir> <path> <token>"
  r=$(resolve "$p") || die "not a readable changed file: $p"
  f=${r%%$'\t'*}; rp=${r#*$'\t'}
  grep -nF -- "$tok" "$f" | head -5 | sed "s#^#$rp:#"
  exit 0
fi

cites=$(printf '%s' "$rest" | sed 1d)
if [ -z "$cites" ] && [ ! -t 0 ]; then cites=$(cat); fi
[ -n "$cites" ] || die "no citations given"

ok=0 problems=0 unchecked=0
while IFS= read -r raw; do
  [ -z "$raw" ] && continue
  cite=$raw token=""
  case $cite in *=*) token=${cite#*=}; cite=${cite%%=*} ;; esac
  path=${cite%:*} rng=${cite##*:}
  s=${rng%%-*} e=${rng##*-}
  case $cite in *:*) ;; *) echo "BAD $raw  no :line"; problems=$((problems + 1)); continue ;; esac
  case $s$e in '' | *[!0-9]*) echo "BAD $raw  line is not a number or range"; problems=$((problems + 1)); continue ;; esac
  [ "$s" -ge 1 ] && [ "$e" -ge "$s" ] || { echo "BAD $raw  bad line range"; problems=$((problems + 1)); continue; }

  r=$(resolve "$path"); rc=$?
  file="" rp=$path via=""
  case $rc in
    0) file=${r%%$'\t'*}; rp=${r#*$'\t'}; [ "$rp" != "$path" ] && via=" (resolved to $rp)" ;;
    2) echo "UNVERIFIABLE $raw  skipped by fetch-pr.sh: ${r#*$'\t'}"; problems=$((problems + 1)); continue ;;
    3) echo "BAD $raw  ambiguous short path, matches: ${r#*$'\t'}"; problems=$((problems + 1)); continue ;;
    *)
      if [ -n "$checkout" ] && [ -f "$checkout/$path" ]; then file="$checkout/$path"; via=" (local checkout)"
      else echo "UNCHECKED $raw  not a changed file; label it \"local checkout\" or open it"; unchecked=$((unchecked + 1)); continue; fi ;;
  esac

  n=$(awk 'END { print NR }' "$file")
  if [ "$s" -gt "$n" ] || [ "$e" -gt "$n" ]; then
    echo "BAD $raw  $rp has only $n lines$via"; problems=$((problems + 1)); continue
  fi
  text=$(awk -v s="$s" 'NR == s { sub(/^[ \t]+/, ""); print substr($0, 1, 110); exit }' "$file")
  if [ -n "$token" ]; then
    lo=$((s - W)); [ "$lo" -lt 1 ] && lo=1; hi=$((e + W))
    if ! awk -v lo="$lo" -v hi="$hi" -v t="$token" 'NR >= lo && NR <= hi && index($0, t) { f = 1 } END { exit !f }' "$file"; then
      hint=$(grep -nF -- "$token" "$file" | head -3 | cut -d: -f1 | tr '\n' ' ')
      echo "MISMATCH $raw  '$token' not within $W lines${via}; line $s is: $text${hint:+; '$token' is at line(s): $hint}"
      problems=$((problems + 1)); continue
    fi
  fi
  echo "OK $raw$via  $text"
  ok=$((ok + 1))
done <<EOF
$cites
EOF

echo "verify-citations: $ok ok, $problems problem(s), $unchecked unchecked"
[ "$problems" -eq 0 ]
