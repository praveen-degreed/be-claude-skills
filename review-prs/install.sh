#!/usr/bin/env bash
# install.sh -- Install the review-prs skill for degreed-coach-builder
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/praveen-degreed/be-claude-skills/main/review-prs/install.sh | bash
#   -- OR --
#   gh api repos/praveen-degreed/be-claude-skills/contents/review-prs/install.sh -q '.content' | base64 -d | bash
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - Claude Code installed

set -euo pipefail

REPO="praveen-degreed/be-claude-skills"
SKILL_DIR="$HOME/.claude/skills/review-prs-be"   # global; review-prs is the frontend skill
AGENTS_DIR="$HOME/.claude/agents"
BRANCH="main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check prerequisites
command -v gh >/dev/null 2>&1 || error "GitHub CLI (gh) is required. Install: https://cli.github.com/"
gh auth status >/dev/null 2>&1 || error "GitHub CLI not authenticated. Run: gh auth login"

info "Installing review-prs skill for degreed-coach-builder..."

# Create skill directory
mkdir -p "$SKILL_DIR/references" "$AGENTS_DIR"

# Files to fetch
FILES=(
    "review-prs/SKILL.md:$SKILL_DIR/SKILL.md"
    "review-prs/references/agent-prompts.md:$SKILL_DIR/references/agent-prompts.md"
    "review-prs/references/decision-rules.md:$SKILL_DIR/references/decision-rules.md"
    "review-prs/references/review-template.md:$SKILL_DIR/references/review-template.md"
    "review-prs/references/deep-mode.md:$SKILL_DIR/references/deep-mode.md"
    "review-prs/references/codebase-patterns.md:$SKILL_DIR/references/codebase-patterns.md"
    "review-prs/references/python-patterns.md:$SKILL_DIR/references/python-patterns.md"
    "review-prs/references/llm-security-checks.md:$SKILL_DIR/references/llm-security-checks.md"
    "review-prs/references/cross-repo-contracts.md:$SKILL_DIR/references/cross-repo-contracts.md"
    "review-prs/references/fairness-checks.md:$SKILL_DIR/references/fairness-checks.md"
    "review-prs/references/voice-checks.md:$SKILL_DIR/references/voice-checks.md"
    "review-prs/references/agent-graph-checks.md:$SKILL_DIR/references/agent-graph-checks.md"
    "review-prs/references/vector-checks.md:$SKILL_DIR/references/vector-checks.md"
    "review-prs/references/astdup.py:$SKILL_DIR/references/astdup.py"
    "review-prs/agents/py-code-reviewer.md:$AGENTS_DIR/py-code-reviewer.md"
    "review-prs/agents/py-logic-reviewer.md:$AGENTS_DIR/py-logic-reviewer.md"
    "review-prs/agents/py-test-analyzer.md:$AGENTS_DIR/py-test-analyzer.md"
    "review-prs/agents/py-simplifier.md:$AGENTS_DIR/py-simplifier.md"
    "review-prs/agents/py-architecture-reviewer.md:$AGENTS_DIR/py-architecture-reviewer.md"
    "review-prs/agents/py-impact-analyzer.md:$AGENTS_DIR/py-impact-analyzer.md"
    "review-prs/agents/py-fairness-reviewer.md:$AGENTS_DIR/py-fairness-reviewer.md"
    "review-prs/agents/py-voice-reviewer.md:$AGENTS_DIR/py-voice-reviewer.md"
    "review-prs/agents/py-agent-graph-reviewer.md:$AGENTS_DIR/py-agent-graph-reviewer.md"
    "review-prs/agents/py-contract-checker.md:$AGENTS_DIR/py-contract-checker.md"
    "review-prs/agents/py-judge.md:$AGENTS_DIR/py-judge.md"
    "review-prs/agents/py-judge-escalation.md:$AGENTS_DIR/py-judge-escalation.md"
    "review-prs/REVIEW.md.example:$SKILL_DIR/REVIEW.md.example"
)

# Fetch each file
for entry in "${FILES[@]}"; do
    SRC="${entry%%:*}"
    DST="${entry##*:}"

    info "Fetching $SRC..."
    CONTENT=$(gh api "repos/$REPO/contents/$SRC?ref=$BRANCH" -q '.content' 2>/dev/null) || {
        warn "Failed to fetch $SRC -- skipping"
        continue
    }

    echo "$CONTENT" | base64 -d > "$DST" 2>/dev/null || {
        # macOS base64 doesn't need -d flag sometimes
        echo "$CONTENT" | base64 --decode > "$DST" 2>/dev/null || {
            warn "Failed to decode $SRC -- skipping"
            continue
        }
    }
done

# Verify installation
INSTALLED=0
for entry in "${FILES[@]}"; do
    DST="${entry##*:}"
    [ -f "$DST" ] && INSTALLED=$((INSTALLED + 1))
done

TOTAL=${#FILES[@]}

if [ "$INSTALLED" -eq "$TOTAL" ]; then
    info "Successfully installed $INSTALLED/$TOTAL files"
else
    warn "Installed $INSTALLED/$TOTAL files (some may have failed)"
fi

echo ""
info "Installation complete!"
echo ""
echo "  Skill location:  $SKILL_DIR/"
echo "  Agents location: $AGENTS_DIR/ (restart Claude Code to load them)"
echo ""
echo "  Usage:"
echo "    /review-prs-be <PR_URL>"
echo "    \"review PR #123\""
echo "    \"review this PR --deep\""
echo ""
echo "  Optional: copy $SKILL_DIR/REVIEW.md.example to REVIEW.md on your default branch."
echo ""
echo "  To update, re-run this script."
