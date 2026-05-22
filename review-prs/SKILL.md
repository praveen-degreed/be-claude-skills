---
name: review-prs
description: >
  Review pull requests for the Degreed Coach Builder Python/FastAPI backend.
  Checks code quality, OWASP LLM Top 10 security, async/memory performance,
  prompt injection, contract impact, and test coverage using 6 parallel agents.
trigger:
  - review
  - review PR
  - review pull request
  - check PR
  - review this PR
  - is this PR ready
  - can you review
input:
  - pr_url: The GitHub pull request URL to review
flags:
  - name: deep
    description: Enable deep mode with 2 independent reviewers and consensus logic
---

# review-prs

Review pull requests for the **Degreed Coach Builder** (Python 3.12 / FastAPI / Azure OpenAI / Redis / LiveKit) backend against project conventions, OWASP LLM Top 10 security standards, async/memory performance patterns, and industry best practices.

## Execution Flow

### Phase 0 -- Setup

Parse the PR URL to extract owner, repo, and PR number.

```
INPUT: <pr_url> or bare URL from user message
PARSE: Extract OWNER, REPO, PR_NUMBER from URL
SET: WORKTREE_PATH = current working directory
SET: LOCAL_ACCESS = true
```

If the user provides just a number, assume the current repo:
```bash
gh pr view <number> --json url --jq '.url'
```

### Phase 1 -- Fetch Context

Gather all PR metadata and the full diff.

```bash
# PR metadata
gh pr view $PR_NUMBER --json title,body,files,additions,deletions,baseRefName,headRefName,state,author,labels,reviewRequests,commits

# Full diff
gh pr diff $PR_NUMBER

# Changed file list with stats
gh pr diff $PR_NUMBER --stat
```

**Assess PR Health:**
- **Large PR** if: >600 lines added/deleted, >20 files changed, or >4 directories touched
- **Scope**: Single-feature, multi-feature, refactor, config-only, test-only, docs-only
- Flag large PRs with recommendation to split

### Phase 1.5 -- Review History

Fetch prior reviews to avoid re-raising fixed issues.

```bash
# Prior reviews
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews

# Commits since last review
gh pr view $PR_NUMBER --json commits
```

Build a context map for each prior issue:
- **FIXED**: Issue no longer present in current diff
- **STILL OPEN**: Issue still present
- **PARTIALLY FIXED**: Related code changed but issue pattern remains

Pass this map to all agents so they do NOT re-raise FIXED issues.

### Phase 2-4 -- Agent Reviews (Parallel)

Launch 6 specialized review agents IN PARALLEL using the Agent tool. Each agent receives:
1. The full PR diff
2. The review history context map
3. The worktree path for local file access
4. Their specialized system prompt from `references/agent-prompts.md`

```
Agent 1: py-code-reviewer      -- Implementation quality, typing, dead code, endpoint patterns
Agent 2: py-logic-reviewer      -- Logic, async, OWASP LLM Top 10, prompt injection, edge cases
Agent 3: py-test-analyzer       -- Test quality, coverage, fixture usage, eval tests
Agent 4: py-simplifier          -- Pythonic idioms, performance patterns (NON-BLOCKING)
Agent 5: py-architecture-reviewer -- Architecture, data layer, deps, docs, observability
Agent 6: py-impact-analyzer     -- Contract chains, prompt chains, blast radius, settings impact
```

Each agent returns findings in this format:
```
FINDING:
  category: <one of the 18 categories>
  severity: Critical | High | Medium | Low | Cosmetic
  file: <path>
  line: <number or range>
  title: <short description>
  detail: <explanation with correct vs incorrect code>
  owasp: <LLM01-LLM10 if applicable, or N/A>
```

### Phase 4.5 -- Practical Filter

Apply the probability x impact matrix from `references/decision-rules.md` to remove theoretical, hyperbolic, or cosmetic findings.

For each finding:
1. Assess **probability** (High / Medium / Low / Extremely Rare)
2. Assess **impact** (Critical / Moderate / Minor / Cosmetic)
3. Apply the filter matrix to Keep, Downgrade, or Drop

Record all dropped/downgraded findings with reasoning for the review template.

### Phase 5 -- Post Review

1. Load the review template from `references/review-template.md`
2. Apply APPROVE or REQUEST CHANGES criteria from `references/decision-rules.md`
3. Format findings into the 18-category template
4. Post to GitHub:

```bash
# If APPROVE
gh pr review $PR_NUMBER --approve --body "$(cat <<'EOF'
<formatted review>
EOF
)"

# If REQUEST CHANGES
gh pr review $PR_NUMBER --request-changes --body "$(cat <<'EOF'
<formatted review>
EOF
)"
```

**Safety Guardrail**: If `gh` commands fail, the diff is incomplete, or agents error out: post review with available findings, mark as "Review Incomplete - Manual Decision Required", and do NOT post `--approve` or `--request-changes`.

### Phase 6 -- Cleanup

Report completion to user. If deep mode was used, clean up the team.

---

## Deep Mode

Activated with `--deep` flag. See `references/deep-mode.md` for full protocol.

Recommended for:
- Authentication/authorization changes
- LLM prompt or strategy changes
- >600 LOC additions
- Multiple modules touched
- Shared service/utility changes
- Redis schema or vector store changes

---

## References

All reference files are loaded progressively as needed:

| File | Purpose | When Loaded |
|------|---------|-------------|
| `references/agent-prompts.md` | System prompts for all 6 agents | Phase 2 |
| `references/decision-rules.md` | Approve/reject criteria, practical filter | Phase 4.5, 5 |
| `references/review-template.md` | GitHub comment template | Phase 5 |
| `references/deep-mode.md` | 2-reviewer consensus protocol | Phase 2 (deep mode only) |
| `references/codebase-patterns.md` | Project-specific correct/wrong patterns | Phase 2 (all agents) |
| `references/python-patterns.md` | Python/FastAPI/async anti-pattern reference | Phase 2 (agents 1,2,4) |
