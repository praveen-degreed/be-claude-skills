# Decision Rules

The goal is **high-signal review**. A false positive costs more than a missed theoretical issue. These rules turn raw agent findings into a trustworthy verdict.

---

## 0. Precedents List (apply FIRST — hard drop)

These are known-intentional patterns in this codebase. **Drop any finding that matches** (record in dropped section). Injected into every agent and the filter.

| Pattern | Why it's intentional |
|---------|----------------------|
| CORS wide open (`*`) | Intentional for the current architecture (CLAUDE.md) |
| Fire-and-forget `asyncio.create_task()` in `sse.py` | Known accepted pattern in streaming paths — only flag if a NEW task drops its reference AND its result is needed |
| `verify=False` on internal httpx client (`client_session.py`) | Internal service-to-service call, accepted |
| Optional field defaulting to `None` to gate a feature across the .NET→Python boundary (e.g. `canReferenceTeamData`) | Expected rollout pattern — the feature being silently off IS correct |
| Pydantic V1 deprecation warnings | Suppressed intentionally in conftest/server |
| Health-check traces dropped by `SkipHealthFilter` | By design |
| `/dgcb` root path on all routes | Correct, not a bug |
| Line number exceeds source file length | You reported a DIFF offset — recompute from the `@@` header or drop |

When the project's `MEMORY.md` or `CLAUDE.md` documents a pattern as intentional, treat it as a precedent and do not flag it.

---

## 1. Validation Pass — Verdict & Confidence

Every finding is re-derived from source by an independent validation sub-agent (Phase 4), which assigns:

**Verdict taxonomy:**
- `TRUE_POSITIVE` — confirmed from source, clearly an issue
- `LIKELY_TP` — probably real (when torn between LIKELY_TP and LIKELY_FP, **prefer LIKELY_TP**)
- `LIKELY_FP` — probably not real
- `FALSE_POSITIVE` — disproven (e.g. misread, line-offset error, code is actually correct)
- `OUT_OF_SCOPE` — pre-existing / not in this diff / matches a precedent
- `ACTIVELY_HARMFUL` — the *suggested fix* would introduce a new bug → **veto the fix**, keep only the problem statement if real

**Confidence 1–10:**
- `9–10`: will fail to compile/parse, or will definitely produce wrong results regardless of inputs, or quotes an exact CLAUDE.md rule being broken
- `8`: high-confidence real issue with a clear reachable path
- `0.7–0.8 → 7–8`: suspicious pattern requiring specific conditions
- `< 7`: too speculative — **do not report**

**Hard cutoff:** drop confidence **< 8** (standard mode), **< 7** (deep mode). Drop `FALSE_POSITIVE` and `OUT_OF_SCOPE` regardless of confidence.

---

## 2. Severity is Threat-Model-Relative (±1 levers)

Severity is **not absolute** — adjust from the base rating:

| Adjustment | Lever |
|------------|-------|
| **−1 level** | Requires winning a race condition |
| **−1 level** | Requires specific non-default configuration |
| **−1 level** | Only reachable by a trusted internal caller (e.g. .NET via internal key) with no user-reachable path |
| **+1 level** | Affects authentication, authorization, or crypto |
| **+1 level** | On a widely-reachable entry point (every request, every session) |
| **+1 level** | Prompt-injection with a demonstrated path from untrusted input to instruction context |

A config weakness (e.g. CORS, `verify=False`) with **no demonstrated reachable exploit** → Info/Low, never High.

---

## 3. Four-Axis Practical Filter

After verdict + severity, weigh four axes (not just two):

1. **Probability** — High (normal flow) / Medium (plausible) / Low (edge) / Extremely Rare (theoretical)
2. **Impact** — Critical (data loss, breach, outage, injection succeeds) / Moderate (broken feature, wrong behavior) / Minor / Cosmetic
3. **Cost-of-fix** — trivial fixes stay even at lower probability; expensive fixes need higher probability×impact to keep
4. **Verifiability** — can the reviewer point to the exact line and reproduce the reasoning? Unverifiable → downgrade or convert to a question

### Probability × Impact matrix

| Probability \ Impact | Critical | Moderate | Minor | Cosmetic |
|---|---|---|---|---|
| **High** | KEEP | KEEP | KEEP | Drop |
| **Medium** | KEEP | KEEP | Downgrade | Drop |
| **Low** | KEEP | Downgrade | Drop | Drop |
| **Extremely Rare** | Downgrade | Drop | Drop | Drop |

---

## 4. Evidence-or-Drop

No finding survives without a **citable source line**. "No vague language (probably / might / seems to)." If an agent cannot quote `file:line` from the actual source, the finding is dropped. Findings that can only be sourced to training knowledge (not the project) are surfaced as questions, never as blocking comments.

For cross-repo / cross-process claims that **cannot be resolved** (e.g. a .NET DTO not reachable via `gh`), emit an explicit **"could not verify"** WARN row — never guess and never block on it.

---

## APPROVE Criteria

ALL must hold (after the filter):
1. No actionable Critical or High findings
2. FastAPI patterns followed (async, `@tracer.wrap` with correct service/resource, Pydantic models, `session_id` logging)
3. No OWASP LLM Top 10 violations with a reachable path
4. Tests present and meaningful for new code (or N/A) AND no test that will deterministically fail CI
5. No blocking async anti-patterns (time.sleep, missing await, fire-and-forget needing its result)
6. No memory leaks (unbounded collections, string concat in stream loop)
7. No breaking contract change (in-repo or cross-repo .NET) without a migration plan
8. No LLM-output fairness regression on identity/language-sensitive paths (if applicable)

## REQUEST CHANGES Criteria

### Critical (immediate reject)
1. Missing await on coroutine · 2. `time.sleep()` in async · 3. fire-and-forget task whose result is required (3.12 GC) · 4. user input in LLM system prompt without mitigation (LLM01) · 5. LLM output to user with no validation (LLM05) · 6. **LLM output / parsed field into `eval`/`exec`/`subprocess`/shell (LLM05)** · 7. missing `@tracer.wrap()` or wrong service/resource on new endpoint · 8. missing auth on user-facing endpoint · 9. hardcoded secret · 10. no tests for new endpoint · 11. **a test that deterministically fails CI** · 12. agent/tool can self-modify its prompt/skill/memory (LLM06)

### High (reject unless justified)
`print()` instead of logging · hardcoded config · RAG/voice-transcript/file-metadata content in prompt without delimiters or scan (LLM01) · no `max_tokens` (LLM10) · re-mocking auto-use fixtures · raw-string parse of LLM output · direct Redis client · breaking API contract w/o migration · bare except swallowing · new Redis key w/o TTL · circular import · SQL for new feature · reimplementing an existing utility · sync blocking I/O in async · tool args without schema validation / no allowlist / SSRF / DB-write w/o WHERE (LLM06) · string concat in stream loop · `await file.read()` without size cap · unbounded growth per request · RAG retrieval without coach/org/tenant scope (LLM02/04) · NameError/undefined name on any path

### Medium (flag as concern)
Sequential awaits on 3+ independent ops · Redis loop w/o pipeline (>5) · large Pydantic model w/o slots · no history limit · new dep w/o justification · missing error handling on external call · test only checks status_code · stale docs contradicting code · duplicate logic within the PR (per `astdup.py`) · language-parity gap on multilingual prompts

---

## Special PR Types (relaxed criteria)

- **Config-only** (settings/.env/helm/yaml): focus on settings impact, env coverage, backward compat; skip style/tests.
- **Docs-only** (*.md/comments/docstrings): accuracy & completeness only.
- **Test-only** (test_*/conftest/pytest.ini): fixture usage, mock patterns, CI health.
- **CI-only** (.github/workflows/Dockerfile/devops): CI/CD impact, Docker security, **deploy-var correctness** (e.g. hardcoded vs templated PR-env namespacing), deployment safety.
- **Dependency-only** (requirements.txt): supply chain (LLM03), pinning, duplicate pins, compatibility, Docker size.
