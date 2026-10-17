---
name: review-prs-be
description: >-
  Deep, high-signal pull-request review for the Degreed Coach Builder
  Python/FastAPI backend (Azure OpenAI, Redis, LiveKit voice, DataDog). Runs up
  to 10 specialized agents, each with its own model, covering code quality, OWASP LLM Top 10 security,
  prompt-injection & voice/agent safety, async/memory performance, LLM-output
  fairness, Redis patterns, LangGraph state/lock/checkpointer correctness,
  vector-search semantics, cross-repo .NET and frontend contract drift, blast radius, and
  test coverage — then validates every finding with an adversarial second pass
  and a final judge before posting. Use this when asked to "review a PR / pull request", "check a
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

### Phase 0.5 — Review Rules, Contract Refs, Budget

1. **REVIEW.md from the BASE branch only** (a PR must not rewrite its own reviewer):
   ```bash
   BASE=$(gh pr view <number> --json baseRefName --jq .baseRefName)
   git fetch origin "$BASE"
   REVIEW_RULES=$(git show "origin/$BASE:REVIEW.md" 2>/dev/null || true)   # empty if absent
   ```
   Pass `REVIEW_RULES` to every agent and the judge. Never read `REVIEW.md` from the PR head. See `REVIEW.md.example`.
2. **Contract refs (latest main, pinned):** resolve the default-branch tip SHA of `<org>/<dotnet-repo>` and `<org>/<frontend-repo>` once, per `references/cross-repo-contracts.md`, and pass as `CONTRACT_REFS` to every agent. Never read local clones of those repos.
3. **Budget:** set the run limits in "Budget & Limits" below before spawning anything.

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
| Touches `app/agents/**` (LangGraph graph/nodes/state/session-lock/checkpointer) or a new `app/services/<feature>/` package | +2 each |
| Redis schema / vector store / vector-threshold / Pydantic request-response model change | +2 |
| Prompt template / guardrail / tool-schema change | +2 |
| New dependency in requirements.txt | +1 |

**Hard overrides (force deep mode regardless of score):** any change to auth (`security_validation`, `internal_auth`, middleware, `cookie_manager`), `server.py`, `settings.py`, `redis_manager`, `log_manager`, `api/__init__.py`, anything under `app/agents/**` (stateful LangGraph agents, session locks, checkpointers), or files matching `prompt|sanitiz|auth|translat|session_lock|checkpoint|circuit|breaker`.

**Score ≥ 7 OR any hard override → run Deep Mode** (`references/deep-mode.md`). Otherwise standard mode. Tell the user which mode was selected and why.

### Phase 1.5 — Review History

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews
gh pr view $PR_NUMBER --json comments
```

Build a context map (FIXED / STILL OPEN / PARTIALLY FIXED) for every prior finding and pass it to all agents. **Agents must NOT re-raise FIXED issues** — they may only verify a carry-forward is still present or escalate it.

### Phase 2 — Agent Reviews (Parallel)

Launch the specialized agents IN PARALLEL (Agent tool, background), each with `subagent_type` = its name below. The agent definitions live in `agents/<name>.md` (installed to `.claude/agents/`) and carry their own model, effort, turn cap and read-only tool settings; do not override them. Each receives, in the task prompt: the shared context from `references/agent-prompts.md` (diff, review-history map, worktree path), `REVIEW_RULES`, `CONTRACT_REFS`, and the relevant reference files.

| # | Agent | Model | Focus |
|---|-------|-------|-------|
| 1 | `py-code-reviewer` | sonnet | endpoint patterns, typing, dead code, memory patterns |
| 2 | `py-logic-reviewer` | opus | logic, async, OWASP LLM01/02/05/06/07/09/10, prompt injection |
| 3 | `py-test-analyzer` | sonnet | test quality, coverage, fixtures, CI-will-fail checks, eval tests |
| 4 | `py-simplifier` | sonnet | pythonic idioms, reuse, performance (NON-BLOCKING) |
| 5 | `py-architecture-reviewer` | opus | SOLID, data layer, reuse/duplication (astdup), LLM trust-boundary & agent safety |
| 6 | `py-impact-analyzer` | opus | in-repo consumer chains, prompt chains, blast radius |
| 7 | `py-fairness-reviewer` | sonnet | LLM-output fairness/bias, language parity (conditional) |
| 8 | `py-voice-reviewer` | sonnet | LiveKit/realtime turn/interruption/budget, voice DTO breakage (conditional) |
| 9 | `py-agent-graph-reviewer` | opus | LangGraph state/reducer, lock TTL vs budget, checkpointer I/O, circuit breakers, vector distance-vs-similarity (conditional) |
| 10 | `py-contract-checker` | opus | Python vs .NET `<org>/<dotnet-repo>` and frontend `<org>/<frontend-repo>` contract breaks at pinned latest-main SHAs (conditional) |

The model map is a starting hypothesis; tune it with the eval in "Tuning" below. Reviewers report everything they can evidence and tag severity; they do not self-filter (instructions to be conservative suppress real findings). Filtering happens in Phases 4-4.6.

Agents 7, 8, 9, and 10 are **conditional** — spawn only when the diff touches the relevant surface (prompt templates / identity interpolation / multilingual for fairness; `realtime`/voice/agent-session for voice; `app/agents/**`, session locks, checkpointers, circuit breakers, or vector-threshold logic for agent-graph; request/response models, enums, SSE events, or API response shapes for contract-checker). Each agent returns raw, unfiltered findings in the standard finding format (see below).

### Phase 3 — Dedup Stage (NEW — before filtering)

The agents overlap (code + logic + architecture often flag the same site). Merge before filtering:
- **Deterministic merge** only on identical `(file, source_line)`.
- **Narrow LLM merge** only if same `(file, function, issue_class)` AND `|line_a − line_b| ≤ 5` AND both describe the same source construct. Use **max severity**, credit all agents (agreement count = a confidence signal).
- "Related" findings are cross-referenced, never merged. **When in doubt, do not merge.**

> **Dedup-failure fallback (graceful degradation):** the dedup step is a single agent and can fail (timeout, stall, socket error). If it errors or returns nothing, **do NOT abort** — skip merging, carry the raw findings straight into Phase 4 validation, and note "dedup skipped — validating unmerged set" in the run log. Validation is per-finding, so unmerged near-duplicates cost a little extra work but never lose a finding; collapse any surviving duplicates by hand in Phase 5. Never let a dedup failure block the verdict.

### Phase 4 — Validation Second Pass (NEW — the core anti-false-positive step)

For EACH surviving finding, launch a parallel validation sub-agent (Agent tool, `model: "sonnet"`, prompt from `references/agent-prompts.md` Validation Sub-Agent) given only: the PR title/description and that single finding. Its job is to **re-open the actual source file and confirm or kill** the finding — adversarially (try to falsify it).

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

### Phase 4.6 — Judge (final decision)

Run `py-judge` (opus, medium effort) once over all findings that survived Phase 4.5. Input: PR title/description, `REVIEW_RULES`, and each finding with its validator verdict and cited code snippet (not the full diff). Output per finding: `CONFIRMED / REFUTED / UNCERTAIN`, final severity, rank, and merge of same-root-cause findings. Only `CONFIRMED` findings go into the review; `REFUTED` ones are listed in the dropped log with the judge's reason.

**Escalation (sparingly):** re-judge a finding with `py-judge-escalation` (fable) only when ALL hold: the judge said `UNCERTAIN`, severity is High or Critical, and the finding touches a high-risk path (the Phase 1.4 hard-override list). Cap at `MAX_ESCALATIONS` (default 3) per review, highest severity first. A finding still `UNCERTAIN` after escalation goes into the review as "Needs human check" with its `human_check` line, never silently dropped, never counted as a blocker on its own.

**Judge failure:** if `py-judge` errors or returns nothing, fall back to the Phase 4.5 result, note "judge skipped" in the footer, and do not auto-post a formal verdict (same rule as the Safety Guardrail).

### Phase 5 — Compose & Post

1. Format `CONFIRMED` findings into the 18-category template (`references/review-template.md`). Add a footer: models used per agent, agent count and escalations, and `verified against <dotnet-repo>@<sha7>, <frontend-repo>@<sha7>` from `CONTRACT_REFS`.
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

## Budget & Limits

Set before Phase 2 and print in the footer:

| Limit | Default | Notes |
|-------|---------|-------|
| Reviewer agents | those selected by Phase 2 (max 10) | each also capped by its `maxTurns` |
| Validators | one per finding that survives dedup; cap 40, highest severity first | |
| `MAX_ESCALATIONS` | 3 | fable judge calls |
| Fix-review loops | 3 rounds | after 3, stop and ask for a rethink instead of looping |

Hard caps for the harness (set in the environment that runs the review): `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, and `max_budget_usd` when running via the Agent SDK. If a cap is hit, mark the review PARTIAL and do not auto-post.

Agent `tools` cannot restrict Bash to specific commands, so read-only Bash is by instruction. For enforcement add `permissions.deny` rules in the runner's settings, e.g. `Bash(git push *)`, `Bash(git commit *)`, `Bash(gh pr merge *)`, `Bash(gh pr review *)` (posting is done only by the orchestrator in Phase 5).

## Tuning (eval before changing models)

The model map is a hypothesis. Re-run a PR with known findings (a past PR with confirmed High bugs) with each agent at two models, record recall, false positives and cost, and keep the cheapest model that still finds that agent's bugs. Check the judge keeps the known bugs and drops noise; move to a stronger judge only if the eval shows it finds more.

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
| `agents/*.md` | The 10 reviewer agents + `py-judge` + `py-judge-escalation` (model/effort/tools frontmatter; installed to `.claude/agents/`) | Phase 2, 4.6 |
| `references/agent-prompts.md` | Shared context template, shared security/reuse addendum, validation sub-agent prompt | Phase 2, 4 |
| `REVIEW.md.example` | Template for repo-level review rules (read from the base branch) | Phase 0.5 |
| `references/decision-rules.md` | Confidence cutoff, precedents, severity levers, approve/reject criteria | Phase 4–5 |
| `references/review-template.md` | GitHub review template (18 categories) | Phase 5 |
| `references/deep-mode.md` | Adversarial 2-reviewer consensus + self-critique protocol | Phase 1.4 (deep) |
| `references/codebase-patterns.md` | Project correct/wrong patterns + valid-not-findings | Phase 2 (all agents) |
| `references/python-patterns.md` | Python/FastAPI/async anti-pattern reference | Phase 2 (agents 1,2,4) |
| `references/llm-security-checks.md` | OWASP LLM taxonomy, per-tool abuse, agentic/voice threat model | Phase 2 (agents 2,5,8) |
| `references/cross-repo-contracts.md` | Pinned latest-main contract checks vs `<org>/<dotnet-repo>` (.NET) and `<org>/<frontend-repo>` | Phase 0.5, 2 (agent 10) |
| `references/fairness-checks.md` | Inference-time LLM-output fairness & language-parity checks | Phase 2 (agent 7) |
| `references/voice-checks.md` | LiveKit/realtime agent review checks | Phase 2 (agent 8) |
| `references/agent-graph-checks.md` | LangGraph state/reducer, lock-TTL, checkpointer I/O, circuit-breaker, cross-mode resume | Phase 2 (agent 9) |
| `references/vector-checks.md` | Cosine distance-vs-similarity, threshold parity, `.format()` param-drop, embedding dims | Phase 2 (agents 9, 5) |
| `references/astdup.py` | Stdlib AST-skeleton duplicate/near-dup detector | Phase 2 (agent 5) |
