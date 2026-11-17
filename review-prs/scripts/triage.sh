#!/usr/bin/env bash
# Deterministic first look at a PR for the BE review: size, kind of change, and risk hints from paths and diff text. No model. Read-only.
# Usage: triage.sh <fetch-dir>      (fetch-dir from fetch-pr.sh: files.txt, stats.txt, pr.diff)
# Prints plan lines the orchestrator uses together with the CHANGE_BRIEF `risks:` (the brief wins where they differ):
#   SIZE   <small|medium|large> (<N> files, +<added> -<deleted>)   small <= 3 files, medium <= 10, large > 10
#   KIND   code | tests-only | docs-only | config-only
#   HINTS  comma list of risk categories the paths/diff suggest: security contract state tenancy llm-behavior voice library tests blast-radius
#   TIER   <small|medium|large>  SIZE raised one step when a hint in {security contract state llm-behavior library} fires, lowered one step (not below small) for tests/docs/config-only
#   BASELINE py-code-reviewer, py-judge (always)
set -u
die() { echo "triage: $*" >&2; exit 2; }
dir=${1:-}; [ -d "$dir" ] || die "usage: triage.sh <fetch-dir>"
files="$dir/files.txt"; diff="$dir/pr.diff"; stats="$dir/stats.txt"
[ -f "$files" ] && [ -f "$diff" ] || die "$dir is not a fetch dir (files.txt / pr.diff missing)"

n=$(grep -c . "$files")
add=$(awk -F'\t' '{gsub(/\+/,"",$2); s+=$2} END{print s+0}' "$stats" 2>/dev/null)
del=$(awk -F'\t' '{gsub(/-/,"",$3); s+=$3} END{print s+0}' "$stats" 2>/dev/null)
if [ "$n" -le 3 ]; then size=small; elif [ "$n" -le 10 ]; then size=medium; else size=large; fi

is_test()   { case $1 in */tests/*|tests/*|*/test_*.py|test_*.py|*_test.py|*conftest.py) return 0 ;; esac; return 1; }
is_doc()    { case $1 in *.md|*.rst|*.txt|docs/*|*/docs/*|*.puml|*.png|*.svg) return 0 ;; esac; return 1; }
is_config() { case $1 in *.yaml|*.yml|*.json|*.toml|*.ini|*.cfg|Dockerfile|*Dockerfile|Makefile|.github/*|devops/*|*.env.example) return 0 ;; esac; return 1; }

code=0 tests=0 docs=0 cfg=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if is_test "$f"; then tests=$((tests + 1))
  elif is_doc "$f"; then docs=$((docs + 1))
  elif is_config "$f"; then cfg=$((cfg + 1))
  else code=$((code + 1)); fi
done <"$files"
if [ "$code" -gt 0 ]; then kind=code
elif [ "$tests" -gt 0 ] && [ "$docs" -eq 0 ] && [ "$cfg" -eq 0 ]; then kind=tests-only
elif [ "$docs" -gt 0 ] && [ "$tests" -eq 0 ] && [ "$cfg" -eq 0 ]; then kind=docs-only
else kind=config-only; fi

hints=""
hint() { case ",$hints," in *",$1,"*) ;; *) hints="${hints:+$hints,}$1" ;; esac; }
path_has() { grep -E -i -q "$1" "$files"; }
diff_has() { grep -E '^\+' "$diff" | grep -E -v '^\+\+\+' | grep -E -i -q "$1"; }

path_has '(^|/)(auth|security|internal_auth|middleware|cookie|identity|permissions?)([^/]*\.py|/)|security_validation|(^|/)settings\.py|(^|/)server\.py' && hint security
diff_has 'password|secret|token|api[_-]?key|jwt|verify_signature|sanitize|escape\(' && hint security
path_has '(^|/)(models|protocol|schemas?|request_and_response)[^/]*(\.py|/)|enum' && hint contract
diff_has '^\+[[:space:]]*class [A-Za-z0-9_]+\((.*BaseModel|.*Enum|.*TypedDict)' && hint contract
path_has 'redis|session|lock|checkpoint|pause|approval|stream|gates|run_liveness|mrtr|action_guard' && hint state
diff_has 'redis_client|\.setex\(|\.set\(|\.hset\(|asyncio\.(Lock|Queue)|SSE|text/event-stream' && hint state
path_has 'conversation_store|session_baggage|tool_cache|identity' && hint tenancy
path_has 'prompt|persona|guardrail|system_prompt|masking' && hint llm-behavior
diff_has 'system_prompt|SystemMessage|few[_-]shot' && hint llm-behavior
path_has 'livekit|realtime|voice|agent_session|stt|tts' && hint voice
path_has '(^|/)requirements[^/]*\.txt$|pyproject\.toml' && hint library
[ "$kind" = code ] && [ "$tests" -eq 0 ] && hint tests
[ "$tests" -gt 0 ] && hint tests
path_has '(^|/)(utils?|common|shared|config)/|(^|/)__init__\.py$' && hint blast-radius

tier=$size
case "$hints" in *security*|*contract*|*state*|*llm-behavior*|*library*)
  case $tier in small) tier=medium ;; medium) tier=large ;; esac ;;
esac
case $kind in tests-only|docs-only|config-only)
  case $tier in large) tier=medium ;; medium) tier=small ;; esac ;;
esac

echo "SIZE $size ($n files, +$add -$del)"
echo "KIND $kind"
echo "HINTS ${hints:-none}"
echo "TIER $tier"
echo "BASELINE py-code-reviewer, py-judge"
