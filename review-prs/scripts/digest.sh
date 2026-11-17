#!/usr/bin/env bash
# Build the shared facts of a PR ONCE so reviewers do not each re-derive them. No model. Read-only.
# Usage: digest.sh <fetch-dir> [--root <repo or worktree dir>]
# Needs <fetch-dir>/pr.diff, files.txt, stats.txt (fetch-pr.sh). Writes, inside the fetch dir:
#   diffs/<path with / as __>.diff   one diff per changed file, so an agent reads only the files it reviews, not all of pr.diff
#   diffs/INDEX.txt                  path <TAB> +added <TAB> -deleted <TAB> diff file
#   digest.txt                       per changed file: size, the symbols the diff adds/changes/removes, and who uses each
#                                    symbol elsewhere in <root> (first hits, so callers are not searched again by every agent)
# Agents: read digest.txt once, read diffs/<file>.diff for the files you review, open head/<path> only to quote a line.
set -u
die() { echo "digest: $*" >&2; exit 2; }
dir="" root=""
while [ $# -gt 0 ]; do
  case $1 in
    --root) root=${2:-}; shift ;;
    *) dir=$1 ;;
  esac
  shift
done
[ -n "$dir" ] && [ -f "$dir/pr.diff" ] && [ -f "$dir/files.txt" ] || die "usage: digest.sh <fetch-dir> [--root DIR]"
[ -z "$root" ] || [ -d "$root" ] || die "--root is not a directory: $root"

mkdir -p "$dir/diffs"
rm -f "$dir/diffs/"*.diff "$dir/diffs/INDEX.txt"
awk -v out="$dir/diffs" '
  /^diff --git / { if (fh != "") close(fh); f = $4; sub(/^b\//, "", f); n = f; gsub(/\//, "__", n); fh = out "/" n ".diff"; idx = out "/INDEX.txt"; print f "\t" fh >> idx }
  fh != "" { print >> fh }
' "$dir/pr.diff"
# fold the +/- counts from stats.txt into the index
if [ -f "$dir/stats.txt" ] && [ -f "$dir/diffs/INDEX.txt" ]; then
  awk -F'\t' 'NR==FNR { a[$1]=$2; d[$1]=$3; next } { print $1 "\t" (a[$1] ? a[$1] : "+0") "\t" (d[$1] ? d[$1] : "-0") "\t" $2 }' "$dir/stats.txt" "$dir/diffs/INDEX.txt" >"$dir/diffs/INDEX.tmp" && mv "$dir/diffs/INDEX.tmp" "$dir/diffs/INDEX.txt"
fi

out="$dir/digest.txt"; : >"$out"
{
  echo "DIGEST (built once by digest.sh; read this first, then diffs/<file>.diff for your files)"
  [ -n "$root" ] && echo "usage search root: $root" || echo "usage search root: none (callers not searched)"
  echo
} >>"$out"

symbols() { # definitions the diff adds/removes, plus the function or class each hunk sits in (git puts it after the @@ header)
  { sed -nE 's/^@@ [^@]*@@ ?(.+)$/\1/p' "$1"; grep -E '^([+ ]|-[^-])' "$1" | sed -E 's/^[-+ ]//'; } | awk '
    match($0, /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)                 { s = substr($0, RSTART, RLENGTH); sub(/^.*def[[:space:]]+/, "", s); print s; next }
    match($0, /^[[:space:]]*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)                                  { s = substr($0, RSTART, RLENGTH); sub(/^.*class[[:space:]]+/, "", s); print s; next }
    match($0, /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(abstract[[:space:]]+)?(async[[:space:]]+)?(function|class|interface|enum|type)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*/) { s = substr($0, RSTART, RLENGTH); sub(/^.*(function|class|interface|enum|type)[[:space:]]+/, "", s); print s; next }
    match($0, /^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(:[^=]*)?=[[:space:]]*(async[[:space:]]*)?(\(|[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=>)/) { s = substr($0, RSTART, RLENGTH); sub(/^.*const[[:space:]]+/, "", s); sub(/[^A-Za-z0-9_$].*$/, "", s); print s; next }
    match($0, /^[[:space:]]*((public|private|protected|static|readonly|async|override)[[:space:]]+)*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\([^)]*\)[[:space:]]*(:[^{]*)?\{/) { s = substr($0, RSTART, RLENGTH); sub(/[[:space:]]*\(.*$/, "", s); sub(/^.*[[:space:]]/, "", s); if (s !~ /^(if|for|while|switch|catch|return|function|constructor)$/) print s }
  ' | awk 'length($0) >= 4 && !seen[$0]++' | head -12
}

while IFS=$'\t' read -r path add del dfile; do
  [ -z "$path" ] && continue
  echo "FILE $path  ($add $del)" >>"$out"
  syms=$(symbols "$dfile")
  if [ -z "$syms" ]; then echo "  symbols: none detected (config, template, style, test data or comment-only change)" >>"$out"; echo >>"$out"; continue; fi
  echo "  symbols touched: $(printf '%s' "$syms" | paste -sd, -)" >>"$out"
  if [ -n "$root" ]; then
    printf '%s\n' "$syms" | while IFS= read -r sym; do
      hits=$(grep -rnw --binary-files=without-match --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=__pycache__ --exclude-dir=.venv -e "$sym" "$root" 2>/dev/null | grep -v -F "$path:" | head -4 | sed -E "s#^$root/##" | cut -c1-150)
      if [ -n "$hits" ]; then echo "  used: $sym" >>"$out"; printf '%s\n' "$hits" | sed 's/^/    /' >>"$out"; else echo "  used: $sym -> no use found outside this file" >>"$out"; fi
    done
  fi
  echo >>"$out"
done <"$dir/diffs/INDEX.txt"
echo "$out"
