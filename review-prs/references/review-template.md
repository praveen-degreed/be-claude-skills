# Review Template

Format the review as a GitHub PR comment using this template. Replace placeholders with actual findings.

---

```markdown
## PR Review: {pr_title}

**Verdict**: {APPROVE | REQUEST CHANGES}
**Confidence**: {HIGH | MEDIUM | LOW}
**Review Mode**: {Standard | Deep}
**Review Round**: {1 | 2 | 3}
**OWASP LLM Coverage**: {X}/{Y} applicable items checked

---

{IF review_history}
### Prior Review Issues

| # | Issue | Status | Notes |
|---|-------|--------|-------|
{for each prior issue}
| {n} | {issue_title} | {FIXED | STILL OPEN | PARTIALLY FIXED} | {notes} |
{end for}

---
{END IF}

### Core Code Quality

#### 1. FastAPI/Endpoint Patterns — {PASS | CONCERN | FAIL}
{findings or "All endpoints follow required patterns."}

#### 2. Python Typing & Idioms — {PASS | CONCERN | FAIL}
{findings or "Types and idioms are consistent."}

#### 3. SOLID & Code Organization — {PASS | CONCERN | FAIL}
{findings or "Code organization follows project conventions."}

---

### LLM Application Security

#### 4. Prompt Injection Defense (LLM01) — {PASS | CONCERN | FAIL}
{findings or "No prompt injection vectors introduced." or "N/A - no LLM code changed"}

#### 5. Information Disclosure (LLM02) — {PASS | CONCERN | FAIL}
{findings or "No sensitive information exposure." or "N/A"}

#### 6. Output Validation (LLM05) — {PASS | CONCERN | FAIL}
{findings or "All LLM outputs properly validated." or "N/A"}

#### 7. Agent/Tool Safety (LLM06) — {PASS | CONCERN | FAIL}
{findings or "Tool calls properly bounded." or "N/A"}

#### 8. Token & Cost Control (LLM10) — {PASS | CONCERN | FAIL}
{findings or "Token limits and cost controls in place." or "N/A"}

---

### Data & RAG Security

#### 9. RAG Pipeline Security (LLM04/08) — {PASS | CONCERN | FAIL}
{findings or "RAG pipeline follows security patterns." or "N/A - no RAG code changed"}

#### 10. Redis & Data Patterns — {PASS | CONCERN | FAIL}
{findings or "Redis patterns followed correctly."}

---

### Performance & Reliability

#### 11. Async & Memory Performance — {PASS | CONCERN | FAIL}
{findings or "No blocking I/O, memory patterns are safe."}

#### 12. LLM Reliability — {PASS | CONCERN | FAIL}
{findings or "Retry logic, error handling, and fallbacks in place." or "N/A"}

#### 13. Context Management — {PASS | CONCERN | FAIL}
{findings or "Context window properly managed." or "N/A"}

---

### Architecture & Impact

#### 14. Observability (Tracing/Logging) — {PASS | CONCERN | FAIL}
{findings or "All operations properly traced and logged."}

#### 15. Contract & Consumer Impact — {PASS | CONCERN | FAIL}
{findings or "No breaking contract changes detected."}

#### 16. Dependency & Docs Compliance — {PASS | CONCERN | FAIL}
{findings or "Dependencies appropriate and usage matches docs." or "N/A - no deps changed"}

---

### Quality

#### 17. Test Quality — {PASS | CONCERN | FAIL}
{findings or "Tests are meaningful and follow project patterns."}

#### 18. Simplification Opportunities — NON-BLOCKING
{suggestions or "No simplification opportunities identified."}

---

### PR Health

- **Scope**: {single-feature | multi-feature | refactor | config | test | docs}
- **Size**: {lines added}/{lines deleted} across {file count} files
- **Breaking Changes**: {Yes — list | No}
{IF large_pr}
- **Large PR**: This PR exceeds 600 LOC. Consider splitting for easier review.
{END IF}
{IF deep_recommended}
- **Deep Review Recommended**: {reason}
{END IF}

---

{IF request_changes}
### Action Required

The following must be addressed before this PR can be approved:

{numbered list of blocking findings with file:line references}

{END IF}

---

<details>
<summary>Dropped/Downgraded Findings ({count})</summary>

| # | Finding | Original Severity | Action | Reason |
|---|---------|------------------|--------|--------|
{for each dropped/downgraded}
| {n} | {title} | {severity} | {Dropped | Downgraded to X} | {reason} |
{end for}

</details>

---

*Reviewed by PR Review Skill v1.0 | [Report Issue](https://github.com/degreed/degreed-coach-builder/issues)*
```
