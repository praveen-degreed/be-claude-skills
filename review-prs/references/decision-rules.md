# Decision Rules

## Practical Validation Filter

Before including a finding in the review, assess its real-world probability and impact.

### Probability x Impact Matrix

| Probability \ Impact | Critical | Moderate | Minor | Cosmetic |
|---|---|---|---|---|
| **High** (likely in normal use) | KEEP | KEEP | KEEP | Drop |
| **Medium** (plausible scenario) | KEEP | KEEP | Downgrade | Drop |
| **Low** (edge case, rare) | KEEP | Downgrade | Drop | Drop |
| **Extremely Rare** (theoretical) | Downgrade | Drop | Drop | Drop |

**Keep**: Include in review at current severity
**Downgrade**: Include but reduce severity by one level
**Drop**: Exclude from review (record in dropped findings section)

### How to Assess Probability

- **High**: Happens in normal user flow. Example: missing await on a coroutine called every request.
- **Medium**: Happens in plausible scenarios. Example: file upload with injection payload.
- **Low**: Requires unusual conditions. Example: Redis connection failure during token refresh.
- **Extremely Rare**: Theoretical only. Example: hash collision in UUID generation.

### How to Assess Impact

- **Critical**: Data loss, security breach, service outage, prompt injection succeeds.
- **Moderate**: Feature broken, wrong behavior for subset of users, performance degradation.
- **Minor**: Cosmetic issue in logs, non-blocking inefficiency, minor inconsistency.
- **Cosmetic**: Style preference, naming suggestion, optional improvement.

---

## APPROVE Criteria

ALL of the following must be true:

1. No actionable Critical or High findings after practical filter
2. FastAPI endpoint patterns followed (async, tracer, Pydantic models)
3. No OWASP LLM Top 10 violations (prompt injection, output validation, etc.)
4. Tests present and meaningful for new code (or N/A for config/docs)
5. No blocking async anti-patterns (time.sleep, missing await)
6. No memory leaks (fire-and-forget tasks, unbounded collections)
7. No breaking contract changes without migration plan
8. Logging uses get_logger + log functions with session_id

## REQUEST CHANGES Criteria

ANY ONE of these triggers rejection:

### Critical (Immediate Reject)
1. Missing await on coroutine (silent bug)
2. time.sleep() in async function
3. asyncio.create_task() without strong reference (Python 3.12 GC risk)
4. User input directly in LLM system prompt without mitigation (LLM01)
5. LLM output returned to user without any validation (LLM05)
6. Missing @tracer.wrap() on new endpoint
7. Wrong service/resource values in tracer.wrap()
8. Missing SecurityValidation on user-facing endpoint
9. Hardcoded secrets or API keys in code
10. No tests for new endpoint

### High (Reject Unless Justified)
11. print() instead of logging
12. Hardcoded config values (must use settings.py)
13. RAG content in system prompt without delimiters (LLM01)
14. No max_tokens on LLM API call (LLM10)
15. Re-mocking auto-mocked conftest fixtures
16. Raw string parsing of LLM output (no Pydantic model)
17. Direct Redis client instantiation (not redis_manager)
18. Breaking API contract without migration plan
19. Bare except: that swallows errors silently
20. New Redis key without TTL
21. Circular imports introduced
22. SQL/SQLAlchemy for new features (Redis is primary)
23. Reimplementing existing utility function
24. Synchronous blocking I/O in async endpoint
25. Tool arguments parsed without schema validation (LLM06)
26. String concatenation in streaming loop
27. await file.read() without size limit on user upload
28. Unbounded list/dict growth per request with no cleanup

### Medium (Flag as Concern)
29. Sequential awaits on 3+ independent operations (use gather)
30. Redis get/set in loop without pipeline (>5 iterations)
31. Large Pydantic model without slots=True
32. No conversation history limit/compaction
33. New dependency without justification
34. Missing error handling on external calls
35. Test only checks status_code without body validation

---

## Special PR Types (Relaxed Criteria)

### Config-Only PRs
Changes only to: settings.py, .env.example, deployment.yaml, Helm charts
- Skip: test quality, code style, simplification
- Focus: settings impact, environment coverage, backward compatibility

### Docs-Only PRs
Changes only to: *.md files, comments, docstrings
- Skip: all code quality checks
- Focus: accuracy, completeness

### Test-Only PRs
Changes only to: test_*.py, conftest.py, pytest.ini
- Skip: architecture, contracts, security
- Focus: test quality, fixture usage, mock patterns

### CI-Only PRs
Changes only to: .github/workflows/, Dockerfile, devops/
- Skip: code quality, tests
- Focus: CI/CD impact, Docker security (hadolint/checkov patterns), deployment safety

### Dependency-Only PRs
Changes only to: requirements.txt
- Skip: code quality, tests
- Focus: supply chain security (LLM03), version pinning, compatibility, Docker size impact
