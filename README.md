# be-claude-skills

Backend PR review skill for [Claude Code](https://claude.com/claude-code) — designed for the **Degreed Coach Builder** (Python 3.12 / FastAPI / Azure OpenAI / Redis / LiveKit) backend.

## Skills

### review-prs `v2`

High-signal pull-request review against project conventions, OWASP LLM Top 10, async/memory performance, LLM-output fairness, voice/agent safety, Redis patterns, cross-repo .NET contract drift, and blast radius — with an **adversarial validation pass** that confirms every finding from source before it's reported.

**Design principle:** *only high-signal findings.* A false positive erodes trust. Every finding must quote a verified source line, carry a 1–10 confidence, and survive an independent validation sub-agent. Findings below the confidence cutoff are dropped.

**Agents (up to 8 — last two are conditional):**

| Agent | Focus |
|-------|-------|
| py-code-reviewer | Endpoint patterns, typing, dead code, memory patterns |
| py-logic-reviewer | Logic, async correctness, OWASP LLM01–10, prompt injection, edge cases |
| py-test-analyzer | Test quality, coverage, fixtures, deterministic-CI-failure checks |
| py-simplifier | Pythonic idioms, reuse/duplication, performance (NON-BLOCKING) |
| py-architecture-reviewer | SOLID, data layer, utility reuse + AST duplicate detection, LLM trust-boundary & agent safety |
| py-impact-analyzer | In-repo + **cross-repo .NET** contract chains, prompt chains, blast radius |
| py-fairness-reviewer *(conditional)* | Inference-time LLM-output fairness & language parity |
| py-voice-reviewer *(conditional)* | LiveKit/realtime turn/interruption/budget, voice DTO breakage |

**20 review categories** mapped to OWASP LLM Top 10 (LLM01–LLM10).

**Pipeline:** pre-flight gate → **pin to live PR head SHA** → complexity-score auto-deep → parallel agents → **dedup** → **adversarial validation pass** → confidence/precedents filter → confirm-before-post.

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

In Claude Code:

```
review <PR_URL>
review PR #123
review this PR --deep
```

### Deep Mode

Auto-triggered by a complexity score (>20 files, >500 LOC, or touching auth/prompt/Redis/realtime paths), or forced with `--deep`. Uses two independent reviewers — one an **adversarial challenger** — plus consensus, a single impact-analyzer pass, and a Stage-2 self-critique.

## Prerequisites

- [GitHub CLI (gh)](https://cli.github.com/) installed and authenticated
- [Claude Code](https://claude.com/claude-code) installed

## Structure

```
review-prs/
  SKILL.md                          # Entry point — pinned-head, validated, high-signal flow
  install.sh                        # One-line installer
  references/
    agent-prompts.md                # System prompts for all 8 agents + the validation sub-agent
    decision-rules.md               # Precedents, confidence cutoff, severity levers, approve/reject
    review-template.md              # GitHub review template (20 categories)
    codebase-patterns.md            # Project-specific correct/wrong patterns
    python-patterns.md              # Python/FastAPI/async anti-pattern reference
    deep-mode.md                    # Adversarial 2-reviewer consensus + self-critique
    llm-security-checks.md          # OWASP LLM taxonomy, per-tool abuse, agentic/voice threat model
    cross-repo-contracts.md         # Reading & diffing the .NET degreed/Degreed DTOs
    fairness-checks.md              # Inference-time LLM-output fairness & language parity
    voice-checks.md                 # LiveKit/realtime agent review checks
    astdup.py                       # Stdlib AST duplicate/near-dup detector
```
