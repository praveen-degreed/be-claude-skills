# be-claude-skills

Backend PR review skill for [Claude Code](https://claude.com/claude-code) — designed for the **Degreed Coach Builder** (Python 3.12 / FastAPI / Azure OpenAI / Redis / LiveKit) backend.

## Skills

### review-prs

Reviews pull requests against project conventions, OWASP LLM Top 10 security standards, async/memory performance patterns, and industry best practices using 6 parallel review agents.

**Agents:**

| Agent | Focus |
|-------|-------|
| py-code-reviewer | Implementation quality, endpoint patterns, Python typing, dead code, memory patterns |
| py-logic-reviewer | Logic errors, async correctness, OWASP LLM Top 10, prompt injection, edge cases |
| py-test-analyzer | Test quality, coverage, fixture usage, LLM eval coverage |
| py-simplifier | Pythonic idioms, code simplification, performance patterns (NON-BLOCKING) |
| py-architecture-reviewer | Architecture, SOLID, data layer, observability, utility reuse |
| py-impact-analyzer | Contract chains, prompt chains, blast radius, settings impact |

**18 review categories** mapped to OWASP LLM Top 10 (LLM01-LLM10).

## Installation

Run from the root of your `degreed-coach-builder` checkout:

```bash
curl -sSL https://raw.githubusercontent.com/praveen-degreed/be-claude-skills/main/review-prs/install.sh | bash
```

Or via GitHub CLI:

```bash
gh api repos/praveen-degreed/be-claude-skills/contents/review-prs/install.sh -q '.content' | base64 -d | bash
```

This installs the skill to `.claude/skills/review-prs/`.

## Usage

In Claude Code, use any of these triggers:

```
review <PR_URL>
review PR #123
review this PR --deep
```

### Deep Mode

Add `--deep` for high-risk PRs (auth changes, prompt changes, >600 LOC, shared utilities). Deep mode uses 2 independent reviewers with consensus logic for higher confidence findings.

## Prerequisites

- [GitHub CLI (gh)](https://cli.github.com/) installed and authenticated
- [Claude Code](https://claude.com/claude-code) installed

## Structure

```
review-prs/
  SKILL.md                          # Entry point — 6-phase execution flow
  install.sh                        # One-line installer
  references/
    agent-prompts.md                # System prompts for all 6 agents
    decision-rules.md               # APPROVE/REJECT criteria, practical filter
    review-template.md              # GitHub PR comment template (18 categories)
    codebase-patterns.md            # Project-specific correct/wrong patterns
    python-patterns.md              # Python/FastAPI/async anti-pattern reference
    deep-mode.md                    # 2-reviewer consensus protocol
```
