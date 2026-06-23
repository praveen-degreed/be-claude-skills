# Deep Mode Protocol

Auto-triggered by the Phase 1.4 complexity score (≥7 or any hard override), or forced with `--deep`. Two independent reviewers + consensus + one impact-analyzer + a Stage-2 self-critique, for higher confidence on high-risk PRs.

## When it fires (auto)

Score ≥ 7, OR any change to: auth (`security_validation`, `internal_auth`, middleware, `cookie_manager`), `server.py`, `settings.py`, `redis_manager`, `log_manager`, `api/__init__.py`, prompt/guardrail/tool-schema files, or files matching `prompt|sanitiz|auth|translat`.

## Workflow

### Step 1 — Two independent reviewers (one adversarial)

Spawn in parallel (background Agent calls — no team primitives required):

- **Reviewer-A** — full independent pass across all applicable dimensions (runs agents 1–5, +7/+8 if relevant).
- **Reviewer-B** — the **CHALLENGER**. Reframed adversarially: its job is to *falsify*, not confirm. It runs its own independent pass AND, where it can see Reviewer-A's territory, actively tries to disprove likely findings. Distinct framing beats a duplicate pass — asking an agent to mark its own homework finds nothing new.

Each returns ALL raw findings (unfiltered) with evidence lines.

> Efficiency note: the prescribed lean shape is **2 reviewers + 1 impact analyzer = 3 background agents** (each reviewer does a combined multi-dimension pass). Only fan out to the full 5-agents-per-reviewer team form for the very largest PRs.

### Step 2 — Impact analyzer once

Run `py-impact-analyzer` a single time (contract/prompt-chain analysis is deterministic; no value in duplicating it). Include the cross-repo .NET contract pass.

### Step 3 — Consensus merge

| Found by | Action |
|----------|--------|
| **BOTH reviewers** | High confidence. Keep; go straight to impact assessment (skip the probability gate). |
| **ONE reviewer only** | Standard validation pass + four-axis filter. |

Merge rules (from multi-reviewer best practice):
- Same location + same problem → **merge into one finding, credit all reviewers** (agreement count = confidence signal).
- Use **MAX severity**, not average (averaging hides Criticals).
- **Guardrail against over-escalation:** a finding may be labeled **Critical / blocking only with 2-of-2 reviewer agreement** OR an undisputed validation-pass confirmation. A lone reviewer's "Critical" with no corroboration is capped at High pending validation.
- Conflicting recommendations → include both with attribution.

### Step 4 — Validation pass

Run the Phase 4 validation sub-agent on every surviving finding (deep-mode confidence cutoff = **< 7** drop). Honor `ACTIVELY_HARMFUL` vetoes.

### Step 5 — Stage-2 self-critique (final sweep)

One sequential pass over the ACCEPTED findings only: *"Which of these would I retract under scrutiny? Did any fix suggestion introduce a regression or contradict another finding?"* Catches inconsistencies introduced by the review itself. Deduplicate by `(area, issue)`, keep higher confidence.

### Step 6 — Compose, confirm, post

Add the Deep Mode Analysis block (below) to the review. **Confirm with the user before posting** (Phase 5). Restore the original branch on cleanup.

## Partial-failure rule

If one reviewer or the impact analyzer dies (terminal error), **continue with the survivors** and mark the review **PARTIAL** in the header — do NOT abort and do NOT auto-post `--approve`/`--request-changes` on a partial run; present findings for a manual decision.

## Review template addition

```markdown
### Deep Mode Analysis
- **Review Mode**: Deep (2 independent reviewers, one adversarial challenger + consensus + self-critique)
- **Trigger**: {complexity score N | hard override: <file>}
- **Reviewer-A findings**: {n}   **Reviewer-B (challenger) findings**: {n}
- **Consensus (both)**: {n}   **Single-reviewer after filter**: {n}
- **Impact analyzer**: {n}   **Retracted in self-critique**: {n}
- **Status**: {Complete | PARTIAL — <which agent failed>}
```

## Cost note

Lean form ≈ 3 background agents + N validation sub-agents. Full team form ≈ 11+. Prefer the lean form; escalate only for the largest PRs.
