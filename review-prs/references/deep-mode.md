# Deep Mode Protocol

Activated with `--deep` flag. Uses 2 independent reviewers with consensus logic for higher confidence.

## When to Recommend Deep Mode

Recommend deep mode when ANY of these are true:
- Authentication/authorization changes (SecurityValidation, login_utils, cookie_manager)
- LLM prompt or strategy changes (prompt_strategies/, prompt.py, generate_prompt.py)
- >600 LOC additions/deletions
- >4 directories touched
- Shared service/utility changes (redis_manager, settings, log_manager, security_validation)
- Redis schema or vector store changes
- Tool definition changes (llm/tools/)
- Guardrail definition changes
- Agent session contract changes (affects LiveKit workers)

## Workflow

### Step 1: Create Team

```
TeamCreate with name "pr-review-{PR_NUMBER}"
```

### Step 2: Spawn 2 Independent Reviewers

Launch Reviewer-A and Reviewer-B in parallel. Each reviewer independently:
1. Receives the full PR diff and review history
2. Launches 5 of the 6 agents as Task agents in parallel (excludes py-impact-analyzer — too expensive to run twice)
3. Collects all unfiltered findings
4. Sends ALL findings back to the team lead via SendMessage

### Step 3: Run Impact Analyzer Once

The team lead runs py-impact-analyzer once (not duplicated) since contract/prompt chain analysis is deterministic.

### Step 4: Consensus Logic

Before applying the practical filter, apply consensus:

| Found By | Action |
|----------|--------|
| **BOTH reviewers** | High confidence. **KEEP** — skip probability check, go straight to impact assessment |
| **ONE reviewer only** | Apply standard probability x impact filter from decision-rules.md |

### Step 5: Merge and Post

1. Merge consensus findings with impact analyzer findings
2. Apply practical filter on single-reviewer findings
3. Format using review template
4. Add "Consensus Findings" section to review:

```markdown
### Consensus Findings (found by both reviewers)

| # | Finding | Severity | Confidence |
|---|---------|----------|------------|
| {n} | {title} | {severity} | HIGH (consensus) |
```

5. Post review via `gh pr review`

### Step 6: Cleanup

```
TeamDelete to shut down the team
```

## Deep Mode Review Template Addition

Add this section after "PR Health" and before "Action Required":

```markdown
### Deep Mode Analysis

- **Review Mode**: Deep (2 independent reviewers + consensus)
- **Reviewer-A findings**: {count}
- **Reviewer-B findings**: {count}
- **Consensus findings**: {count} (found by both)
- **Single-reviewer findings after filter**: {count}
- **Impact analyzer findings**: {count}
```

## Cost Consideration

Deep mode launches ~11 agents (5 per reviewer + 1 impact analyzer) instead of 6. Use only when the PR warrants the additional scrutiny. For routine PRs, standard mode is sufficient.
