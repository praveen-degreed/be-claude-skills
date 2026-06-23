---
name: review-prs
description: >-
  Deep, high-signal pull-request review for the Degreed Coach Builder
  Python/FastAPI backend (Azure OpenAI, Redis, LiveKit voice, DataDog). Runs up
  to 8 specialized agents covering code quality, OWASP LLM Top 10 security,
  prompt-injection & voice/agent safety, async/memory performance, LLM-output
  fairness, Redis patterns, cross-repo .NET contract drift, blast radius, and
  test coverage — then validates every finding with an adversarial second pass
  before posting. Use this when asked to "review a PR / pull request", "check a
  PR", "is this PR ready", or "review this PR --deep". Pass --deep for two
  independent reviewers + consensus on high-risk PRs.
---

# review-prs

High-signal PR review for the **Degreed Coach Builder** (Python 3.12 / FastAPI / Azure OpenAI / Redis primary data store / LiveKit voice / DataDog) against project conventions, OWASP LLM Top 10, async/memory patterns, LLM-output fairness, and cross-repo contracts.

**Design principle (read first):** *We only want HIGH-SIGNAL findings.* A false positive erodes trust and wastes a senior engineer's time. Every finding must be backed by a verified source line and survive an independent validation pass. When uncertain whether an issue is real, **do not report it.** Better to miss a theoretical issue than to flood the review with noise.

---

## Execution Flow

### Phase 0 — Setup & Pre-flight Gate

Parse the PR URL/number to extract OWNER, REPO, PR_NUMBER. Default repo = `degreed/degreed-coach-builder`.

```bash
gh pr view <number_or_url> --json url,state,isDraft,author,reviews
```

**Pre-flight skip conditions** (stop early, do not spawn agents) — report why and exit:
- PR is `CLOSED` or `MERGED`
- PR is a **draft** (unless the user explicitly asks to review a draft)
- PR author is a bot (dependabot, renovate)
- This skill already posted a review on the current HEAD SHA (avoid duplicate reviews)
- PR head is an **untrusted fork** — review the diff but NEVER run with write credentials or auto-post

**ALWAYS pin to the live PR head SHA — never trust an existing local checkout (it goes stale while the PR keeps moving):**

```bash
HEAD_SHA=$(gh pr view <number> --json headRefOid --jq .headRefOid)
git fetch origin "pull/<number>/head"          # fetch the exact PR head
git checkout "$HEAD_SHA"                         # detached HEAD at the live head
test "$(git rev-parse HEAD)" = "$HEAD_SHA" || abort "checkout != live head"
```

Record `HEAD_SHA` and the starting branch (to restore in Phase 6). Every agent and every validation grep MUST run against `$HEAD_SHA`. If `gh pr diff` and the local tree disagree, the local tree is stale — re-fetch. Set `WORKTREE_PATH = current working directory`, `LOCAL_ACCESS = true`.

> Why this is mandatory: a review run against a stale checkout will "confirm" blockers that were already fixed upstream and post a wrong verdict. Pin the SHA, and key the duplicate-review skip below off that exact SHA.

### Phase 1 — Fetch Context

```bash
gh pr view $PR_NUMBER --json title,body,files,additions,deletions,baseRefName,headRefName,state,author,labels,commits
gh pr diff $PR_NUMBER
gh pr diff $PR_NUMBER --stat
```

For a very large diff, do NOT inline it into agents. Check out the branch (Phase 0) and have each agent run `gh pr diff` + read source files from the worktree.

### Phase 1.4 — Complexity Score → Auto Deep Mode

Compute a score to decide depth automatically (no manual flag needed):

| Signal | Points |
|--------|--------|
| >20 files changed | +5 |
| >500 lines added/deleted | +3 |
| Touches `app/api/`, `app/llm/`, `app/db/redis_*`, `app/realtime/`, `app/services/validation` | +2 each |
| Redis schema / vector store / Pydantic request-response model change | +2 |
| Prompt template / guardrail / tool-schema change | +2 |
| New dependency in requirements.txt | +1 |

**Hard overrides (force deep mode regardless of score):** any change to auth (`security_validation`, `internal_auth`, middleware, `cookie_manager`), `server.py`, `settings.py`, `redis_manager`, `log_manager`, `api/__init__.py`, or files matching `prompt|sanitiz|auth|translat`.

**Score ≥ 7 OR any hard override → run Deep Mode** (`references/deep-mode.md`). Otherwise standard mode. Tell the user which mode was selected and why.

### Phase 1.5 — Review History

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews
gh pr view $PR_NUMBER --json comments
```

Build a context map (FIXED / STILL OPEN / PARTIALLY FIXED) for every prior finding and pass it to all agents. **Agents must NOT re-raise FIXED issues** — they may only verify a carry-forward is still present or escalate it.

### Phase 2 — Agent Reviews (Parallel)

Launch the specialized agents IN PARALLEL (Agent tool, background). Each receives: the diff, the review-history map, the worktree path, the relevant reference files, and its system prompt from `references/agent-prompts.md`.

```
Agent 1: py-code-reviewer        — endpoint patterns, typing, dead code, memory patterns
Agent 2: py-logic-reviewer       — logic, async, OWASP LLM01/02/05/06/07/09/10, prompt injection
Agent 3: py-test-analyzer        — test quality, coverage, fixtures, CI-will-fail checks, eval tests
Agent 4: py-simplifier           — pythonic idioms, reuse, performance (NON-BLOCKING)
Agent 5: py-architecture-reviewer— SOLID, data layer, reuse/duplication (astdup), LLM trust-boundary & agent safety
Agent 6: py-impact-analyzer      — in-repo + cross-repo .NET contract chains, prompt chains, blast radius
Agent 7: py-fairness-reviewer    — LLM-output fairness/bias, language parity (load if prompts/identity/multilingual touched)
Agent 8: py-voice-reviewer       — LiveKit/realtime turn/interruption/budget, voice DTO breakage (load if realtime touched)
```

Agents 7 and 8 are **conditional** — spawn only when the diff touches the relevant surface (prompt templates / identity interpolation / multilingual for fairness; `realtime`/voice/agent-session for voice). Each agent returns raw, unfiltered findings in the standard finding format (see below).

### Phase 3 — Dedup Stage (NEW — before filtering)

The agents overlap (code + logic + architecture often flag the same site). Merge before filtering:
- **Deterministic merge** only on identical `(file, source_line)`.
- **Narrow LLM merge** only if same `(file, function, issue_class)` AND `|line_a − line_b| ≤ 5` AND both describe the same source construct. Use **max severity**, credit all agents (agreement count = a confidence signal).
- "Related" findings are cross-referenced, never merged. **When in doubt, do not merge.**

### Phase 4 — Validation Second Pass (NEW — the core anti-false-positive step)

For EACH surviving finding, launch a parallel validation sub-agent given only: the PR title/description and that single finding. Its job is to **re-open the actual source file and confirm or kill** the finding — adversarially (try to falsify it).

- It must quote the verified **source line** (not a diff offset). If it cannot point to a line, the finding is dropped.
- It assigns a **confidence 1–10** and a verdict: `TRUE_POSITIVE / LIKELY_TP / LIKELY_FP / FALSE_POSITIVE / OUT_OF_SCOPE`.
- It flags `ACTIVELY_HARMFUL` if the finding's suggested fix would introduce a new bug (veto).

This pass is what kills the diff-line-vs-source-line false positive and hallucinated findings.

### Phase 4.5 — Practical Filter

Apply `references/decision-rules.md`:
1. Drop anything matching the **Precedents list** (known-intentional patterns).
2. Hard-drop validation confidence **< 8** (standard) / **< 7** (deep mode).
3. Apply threat-model-relative severity (±1 levers).
4. Apply the 4-axis filter (probability × impact, tempered by cost-of-fix and verifiability).

Record every dropped/downgraded finding with its reason for the report.

### Phase 5 — Compose & Post

1. Format surviving findings into the 18-category template (`references/review-template.md`).
2. Apply APPROVE / REQUEST CHANGES criteria (`references/decision-rules.md`).
3. **Present the full review to the user and get explicit confirmation before posting.** Posting a formal review is an outward-facing, hard-to-reverse action on someone's PR.
4. On confirmation:

```bash
# APPROVE
gh pr review $PR_NUMBER --approve --body "$(cat <<'EOF'
<formatted review>
EOF
)"
# REQUEST CHANGES
gh pr review $PR_NUMBER --request-changes --body "$(cat <<'EOF'
<formatted review>
EOF
)"
```

Post **one comment per unique issue** (no duplicates). Only attach a committable suggestion when it fixes the issue *entirely*; for larger fixes, describe without a suggestion block.

**Safety Guardrail:** if `gh` fails, the diff is incomplete, an agent errors, or the PR is an untrusted fork — post nothing with `--approve`/`--request-changes`; surface findings as "Review Incomplete — Manual Decision Required."

### Phase 6 — Cleanup

Restore the user's original branch (`git checkout <starting-branch>`). If deep mode created a team, tear it down. Report completion.

---

## Standard Finding Format

```
FINDING:
  category:   <one of the 18 categories>
  severity:   Critical | High | Medium | Low | Cosmetic
  confidence: 1-10            (set by validation pass)
  verdict:    TRUE_POSITIVE | LIKELY_TP | LIKELY_FP | FALSE_POSITIVE | OUT_OF_SCOPE | ACTIVELY_HARMFUL
  file:       <path>
  line:       <SOURCE file line — verified by opening the file, NOT a diff offset>
  title:      <short>
  detail:     <correct vs incorrect, why it matters>
  owasp:      <LLM01-LLM10 or N/A>
  evidence:   <project-file: quoted line>   (no claim without a citable line)
```

---

## Deep Mode

Auto-triggered by Phase 1.4, or forced with `--deep`. Two independent reviewers (one **adversarial challenger**) + consensus + a single impact-analyzer run + a Stage-2 self-critique. See `references/deep-mode.md`.

---

## References

| File | Purpose | When Loaded |
|------|---------|-------------|
| `references/agent-prompts.md` | System prompts for all 8 agents + the validation sub-agent | Phase 2, 4 |
| `references/decision-rules.md` | Confidence cutoff, precedents, severity levers, approve/reject criteria | Phase 4–5 |
| `references/review-template.md` | GitHub review template (18 categories) | Phase 5 |
| `references/deep-mode.md` | Adversarial 2-reviewer consensus + self-critique protocol | Phase 1.4 (deep) |
| `references/codebase-patterns.md` | Project correct/wrong patterns + valid-not-findings | Phase 2 (all agents) |
| `references/python-patterns.md` | Python/FastAPI/async anti-pattern reference | Phase 2 (agents 1,2,4) |
| `references/llm-security-checks.md` | OWASP LLM taxonomy, per-tool abuse, agentic/voice threat model | Phase 2 (agents 2,5,8) |
| `references/cross-repo-contracts.md` | Reading & diffing the .NET `degreed/Degreed` DTOs | Phase 2 (agent 6) |
| `references/fairness-checks.md` | Inference-time LLM-output fairness & language-parity checks | Phase 2 (agent 7) |
| `references/voice-checks.md` | LiveKit/realtime agent review checks | Phase 2 (agent 8) |
| `references/astdup.py` | Stdlib AST-skeleton duplicate/near-dup detector | Phase 2 (agent 5) |
