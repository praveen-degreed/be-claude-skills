#!/usr/bin/env bash
# Read WHY the failing CI checks failed, so a review never says "CI red" without a cause. No model. Read-only.
#
# Usage: ci-failures.sh <fetch-dir> [--repo owner/name]
#        ci-failures.sh <fetch-dir> --log <file> [--check <name>]     (parse a saved log; used by the evals)
# Reads <fetch-dir>/checks.txt (fetch-pr.sh: failing checks only, tab separated: name, state, duration, url) and, for
# each GitHub Actions check, the failed-step log (gh run view --log-failed). Writes <fetch-dir>/ci-failures.txt and prints it:
#   CHECK       the failing check
#   RUN         the run's head sha against the PR head (current | STALE | unknown)
#   FAILING-SPEC  a failing test file, marked IN-PR when the PR changes it
#   FAILING-TEST  a failing test name
#   EXCERPT     the first failure block (about 25 lines): the assertion and what was received
#   ERROR       ruff or other lint/type error lines
#   NOTE        the log ended in a cancel or timeout, or no structured failure was found
# A check outside GitHub Actions (for example Azure) is listed as not readable here. Always exits 0.
set -u
die() { echo "ci-failures: $*" >&2; exit 2; }

dir="" repo="" logf="" only=""
while [ $# -gt 0 ]; do
  case $1 in
    --repo) repo=${2:-}; shift ;;
    --log) logf=${2:-}; shift ;;
    --check) only=${2:-}; shift ;;
    *) dir=$1 ;;
  esac
  shift
done
[ -n "$dir" ] && [ -f "$dir/checks.txt" ] || die "usage: ci-failures.sh <fetch-dir> [--repo owner/name] [--log FILE --check NAME]"

out="$dir/ci-failures.txt"
: >"$out"
emit() { printf '%s\n' "$*" >>"$out"; }

if [ ! -s "$dir/checks.txt" ]; then
  emit "CI: no failing checks (checks.txt is empty)"
  cat "$out"; exit 0
fi

prsha=$(jq -r '.headRefOid // empty' "$dir/meta.json" 2>/dev/null)
esc=$(printf '\033')
tmp="$dir/.ci.tmp"

while IFS=$'\t' read -r name state dur url; do
  [ -z "$name" ] && continue
  emit "CHECK $name | ${state:-fail} ${dur:-} | ${url:-no url}"
  [ -n "$only" ] && [ "$only" != "$name" ] && { emit "  (skipped: --check $only)"; continue; }

  raw=""
  if [ -n "$logf" ]; then
    raw=$logf
  else
    case $url in
      https://github.com/*/actions/runs/*)
        r=${repo:-$(printf '%s' "$url" | sed -E 's#https://github.com/([^/]+/[^/]+)/actions/.*#\1#')}
        run=$(printf '%s' "$url" | sed -E 's#.*/runs/([0-9]+).*#\1#')
        sha=$(gh run view "$run" --repo "$r" --json headSha --jq .headSha 2>/dev/null || true)
        if [ -n "$sha" ] && [ -n "$prsha" ]; then
          if [ "$sha" = "$prsha" ]; then emit "RUN head ${sha:0:12} (PR head ${prsha:0:12}: current)"; else emit "RUN head ${sha:0:12} (PR head ${prsha:0:12}: STALE, a newer commit exists; the failure may already be fixed)"; fi
        else
          emit "RUN head ${sha:0:12} (PR head ${prsha:0:12}: unknown)"
        fi
        raw="$dir/.ci-raw.tmp"
        if ! gh run view "$run" --repo "$r" --log-failed >"$raw" 2>"$dir/.ci-err.tmp"; then
          emit "NOTE log unavailable: $(head -1 "$dir/.ci-err.tmp" | cut -c1-140). Open $url"
          rm -f "$raw" "$dir/.ci-err.tmp"; continue
        fi
        ;;
      *)
        emit "NOTE not readable here (this check does not run on GitHub Actions): open $url"
        continue
        ;;
    esac
  fi

  # strip colour codes (real ESC bytes, or the literal "^[" text some logs carry) and the "<job><TAB><step><TAB><timestamp>Z " prefix gh puts on every line
  LC_ALL=C sed -E "s/(${esc}|\^\[)\[[0-9;]*m//g" "$raw" | LC_ALL=C sed -E 's/^[^	]*	[^	]*	[0-9T:.-]+Z //' >"$tmp"

  found=0
  specs=$(grep -E '^[[:space:]]*(FAILED|ERROR)[[:space:]]+[^[:space:]:]+\.py' "$tmp" | sed -E 's/^[[:space:]]*(FAILED|ERROR)[[:space:]]+//; s/(::| ).*//' | awk '!s[$0]++' | head -10)
  for s in $specs; do
    found=1
    if grep -qxF -- "$s" "$dir/files.txt" 2>/dev/null; then emit "FAILING-SPEC $s IN-PR"; else emit "FAILING-SPEC $s (not in this PR's files)"; fi
  done
  grep -E '^[[:space:]]*FAILED[[:space:]]+[^[:space:]]+::' "$tmp" | sed -E 's/^[[:space:]]*FAILED[[:space:]]+//' | cut -c1-200 | awk '!s[$0]++' | head -8 | while IFS= read -r t; do emit "FAILING-TEST $t"; done
  n=$(grep -n -E '^_{3,} .+ _{3,}$' "$tmp" | head -1 | cut -d: -f1)
  if [ -n "$n" ]; then
    found=1
    emit "EXCERPT"
    sed -n "${n},$((n + 24))p" "$tmp" | awk 'NR > 1 && /^_{3,} .+ _{3,}$/ { exit } { print }' | cut -c1-200 | sed 's/^/  /' >>"$out"
  fi
  errs=$(grep -E '^[^[:space:]]+\.py:[0-9]+:[0-9]+: [A-Z]+[0-9]+|^Found [0-9]+ errors?|error: .*\[[a-z-]+\]$' "$tmp" | cut -c1-200 | head -6)
  if [ -n "$errs" ]; then found=1; printf '%s\n' "$errs" | while IFS= read -r e; do emit "ERROR $e"; done; fi
  grep -E '^=+ .*(passed|failed|error).* =+$' "$tmp" | head -2 | while IFS= read -r l; do emit "NOTE $l"; done
  grep -q 'The operation was canceled' "$tmp" && emit "NOTE the log ends with 'The operation was canceled' (a timeout or a cancel): a failure above may be real, or the job may have been cut off"
  [ "$found" = 0 ] && emit "NOTE no failing test, lint error or pytest summary in the failed-step log: open $url"
done <"$dir/checks.txt"

rm -f "$tmp" "$dir/.ci-raw.tmp" "$dir/.ci-err.tmp"
cat "$out"
exit 0
