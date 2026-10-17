# be-claude-skills

Backend PR review skill for [Claude Code](https://claude.com/claude-code), built for a Python 3.12 / FastAPI / Azure OpenAI / Redis / LiveKit backend.

## Skills

### review-prs-be `v3`

High-signal pull-request review against project conventions, OWASP LLM Top 10, async/memory performance, LLM-output fairness, voice/agent safety, Redis patterns, cross-repo (.NET and frontend) contract drift, and blast radius. Every finding is confirmed from source by a validation sub-agent and then decided by a final judge before it is reported.

The skill is named `review-prs-be` so it can sit next to a frontend `review-prs` skill without colliding.

**Design principle:** *only high-signal findings in the final review.* Reviewers report everything they can evidence (conservative prompts suppress real findings); validation, filtering and the judge decide what survives. Every finding must quote a verified source line.

**Agents (up to 10, each with its own model, effort and read-only tools):**

| Agent | Model | Focus |
|-------|-------|-------|
| py-code-reviewer | sonnet | Endpoint patterns, typing, dead code, memory patterns |
| py-logic-reviewer | opus | Logic, async correctness, OWASP LLM01-10, prompt injection, edge cases |
| py-test-analyzer | sonnet | Test quality, coverage, fixtures, what the auto-mocks hide |
| py-simplifier | sonnet | Pythonic idioms, reuse, performance (NON-BLOCKING) |
| py-architecture-reviewer | opus | SOLID, data layer, utility reuse + AST duplicate detection, LLM trust boundary |
| py-impact-analyzer | opus | In-repo contract chains, prompt chains, blast radius |
| py-fairness-reviewer *(conditional)* | sonnet | LLM-output fairness and language parity |
| py-voice-reviewer *(conditional)* | sonnet | LiveKit/realtime turn/interruption/budget, voice DTO breakage |
| py-agent-graph-reviewer *(conditional)* | opus | LangGraph state/reducer, lock TTL vs budget, checkpointer I/O, circuit breakers, vector distance-vs-similarity |
| py-contract-checker *(conditional)* | opus | Python models, enums and SSE events vs the .NET and frontend repos, at pinned latest-main SHAs |

Plus `py-judge` (opus) and `py-judge-escalation` (fable, only for uncertain High/Critical findings in high-risk paths, capped per review). The model map is a starting hypothesis; tune it with the eval described in `SKILL.md`.

**Pipeline:** pre-flight gate, pin to live PR head SHA, `REVIEW.md` from the base branch, pinned contract refs, complexity-score auto-deep, parallel agents, dedup, adversarial validation, confidence/precedents filter, judge (+ capped escalation), confirm-before-post. A Budget & Limits section caps agents, validators, escalations and fix loops.

## Installation

Installs globally (skill to `~/.claude/skills/review-prs-be/`, agents to `~/.claude/agents/`), so nothing lands in your repo:

```bash
curl -sSL https://raw.githubusercontent.com/praveen-degreed/be-claude-skills/main/review-prs/install.sh | bash
```

Or via GitHub CLI:

```bash
gh api repos/praveen-degreed/be-claude-skills/contents/review-prs/install.sh -q '.content' | base64 -d | bash
```

Restart Claude Code afterwards so it loads the new agents.

## Usage

```
/review-prs-be <PR_URL>
review PR #123
review this PR --deep
```

Copy `REVIEW.md.example` to `REVIEW.md` on your default branch to add repo-specific rules. The skill reads it from the PR's base branch, never from the PR itself.

### Contract checks

`py-contract-checker` resolves the default-branch tip SHA of your .NET and frontend repos once per review and reads them only through `gh api ...?ref=<sha>`, never from local clones. Configure the counterpart repos and pair table in `references/cross-repo-contracts.md`.

### Deep Mode

Auto-triggered by a complexity score (>20 files, >500 LOC, or touching auth/prompt/Redis/realtime paths), or forced with `--deep`. Uses two independent reviewers (one adversarial), consensus, a single impact-analyzer pass and a self-critique. Judge and caps still apply.

## Prerequisites

- [GitHub CLI (gh)](https://cli.github.com/) installed and authenticated
- [Claude Code](https://claude.com/claude-code) installed

## Structure

```
review-prs/
  SKILL.md                  # Orchestrator: phases, budget, tuning
  install.sh                # Global installer
  REVIEW.md.example         # Repo-level review rules template
  agents/                   # 10 reviewers + py-judge + py-judge-escalation (model/effort/tools frontmatter)
  references/
    agent-prompts.md        # Shared context template, security/reuse addendum, validator prompt
    decision-rules.md       # Precedents, confidence cutoff, severity levers, approve/reject
    review-template.md      # GitHub review template
    codebase-patterns.md    # Project-specific correct/wrong patterns
    python-patterns.md      # Python/FastAPI/async anti-pattern reference
    deep-mode.md            # Adversarial 2-reviewer consensus + judge/caps
    llm-security-checks.md  # OWASP LLM taxonomy, per-tool abuse, agentic/voice threat model
    cross-repo-contracts.md # Pinned latest-main contract checks (.NET + frontend)
    fairness-checks.md      # LLM-output fairness and language parity
    voice-checks.md         # LiveKit/realtime review checks
    agent-graph-checks.md   # LangGraph state, locks, checkpointer, circuit breakers
    vector-checks.md        # Distance vs similarity, threshold parity, embedding dims
    astdup.py               # Stdlib AST duplicate/near-dup detector
```
