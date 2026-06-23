# Agent-Graph / Stateful-Agent Review Checks (LangGraph + Redis)

For `py-agent-graph-reviewer`. Load when the diff touches `app/agents/**` (LangGraph graphs, nodes, state, session locks, checkpointers) or any per-feature `app/services/<feature>/` package that holds a state machine, circuit breaker, or distributed lock.

These are bug classes the other agents are NOT primed for — silent wrong-results, dead safety backstops, and mid-turn lock races rather than crashes. Read the actual source; do not infer behavior from names.

---

## 1. LangGraph state channels — replacing vs accumulating (HIGH-value)

A `TypedDict`/state field is a **replacing channel by default**: whatever value is fed into `astream(input)` / `ainvoke(input)` OVERWRITES the checkpointer's stored value for that key on every invocation. Only fields wrapped in `Annotated[T, reducer]` (e.g. `add_messages`, `operator.add`) accumulate across turns.

- **FLAG**: cross-turn accounting (probe/retry counts, turn history, running tallies, seen-sets) read from a state field that has **no reducer**, when the graph is invoked once per user turn. The per-invocation input re-seeds the field (often to `[]` / `0`) and silently wipes the accumulated value → the counter/history is effectively always empty, and any backstop built on it is dead code.
  - Verify: open the state definition, check whether the field is `Annotated[..., <reducer>]` or a bare type. Then check the invocation site — is that key present in the input dict? If bare-type AND fed in the input, it is overwritten every turn.
  - Consumer check: find where the field is read, and confirm the value it needs to accumulate actually survives across invocations.
- **FLAG**: a load-bearing comment asserting "nothing mutates field X" — verify against the node/tool code. Graph nodes and shared tool helpers frequently `.append()` into state in place, contradicting the comment and any sync-back logic built on it.
- **CHECK**: the state sync-back loop (graph result → persisted session data) — does it include every field that a node mutated and that a later turn depends on? An omitted field is silent cross-turn data-loss.

## 2. Checkpointer Redis I/O (perf, compounds lock-hold time)

LangGraph checkpoint save/load runs on every graph step and often sits INSIDE the per-session lock.

- **FLAG**: a custom checkpoint saver issuing multiple **sequential** Redis commands per step (`set`+`expire`+`zadd`+`expire`+`hset`…) instead of one pipeline / `SET ... EX`. Each is a round-trip; on a remote/managed Redis they add up and lengthen the lock window (see §3).
- **FLAG**: redundant full-state reads per turn — e.g. two `aget_state(config)` calls when the state hasn't mutated between them. Reuse one result.

## 3. Distributed lock TTL vs critical-section budget (HIGH-value)

A Redis `SET NX EX <ttl>` lock protects a critical section. The invariant: **lock TTL must strictly exceed the worst-case duration of everything inside the lock**, or the lock expires mid-section and a concurrent acquirer races in.

- **FLAG**: `lock_ttl <= operation_timeout` where the operation (LLM call, chain of Redis I/O, downstream HTTP) runs while holding the lock. Classic form: the lock TTL and the LLM-call timeout are the SAME constant — the LLM alone can consume the whole TTL before the post-call write completes.
  - Quantify the section: Redis GET(s) + message assembly + LLM round-trip + checkpoint writes + Redis SET. Compare the sum's worst case against the TTL.
- **CHECK**: the release path — does it compare-and-delete (only DEL if the value is still ours) rather than a bare DEL that could clobber another acquirer's lock after our TTL lapsed? A self-documenting "could clobber" comment is a tell the author knows the TTL is too tight.
- **Fix pattern to recommend**: derive `lock_ttl = operation_timeout + headroom` from one setting, assert `lock_ttl > operation_timeout` at startup, and/or add a lock-renewal watchdog around the long call.

## 4. Resilience primitives — circuit breakers, retries, backoff

- **FLAG**: a circuit breaker that re-arms its open window with `if fails == THRESHOLD:` (exact equality). Once the counter passes the threshold — because it keeps incrementing, or because the open-window early-return skips the increment so it never advances — the `== THRESHOLD` guard is permanently false and the breaker never re-opens → stuck effectively-closed during a sustained outage. Recommend `>=`.
- **CHECK**: during the OPEN window the code early-returns BEFORE the protected call — confirm the failure-recording path is still reachable, or the breaker cannot refresh its own window.
- **FLAG**: a retry/backoff loop with no jitter and no cap under a lock, or one that retries on non-retryable errors.

## 5. Fire-and-forget background writes not drained on shutdown

- **FLAG**: a per-turn/per-item writeback fired as a detached `create_task` tracked only in a module-level set, with NO `await asyncio.gather(*tasks)` on session teardown / shutdown callback. On the FINAL turn the session/loop tears down immediately and cancels the in-flight write → the last item never persists. Compare against sibling agents that drain their task sets in an explicit cleanup callback.

## 6. Cross-mode / resume state symmetry

- **FLAG**: the same logical state (answered ids, cursor, resume blob) written on one path and read on another, where the two paths use **different id sources** — e.g. one persists a raw external/LLM-supplied id while the sibling coerces to the current canonical id. Divergence → resume reopens or skips an item.
- **CHECK**: the write and read of a resume blob use the same match key; a matcher that keys on a stale/raw id silently records nothing.

---

## Output format

```
  category: "Agent-Graph / Stateful-Agent"
  severity: Critical | High | Medium | Low
  confidence: 1-10
  file: <path>  line: <source line>
  title / detail / evidence
  owasp: LLM06 | LLM10 | N/A
```

Evidence-or-drop applies: quote the state field definition (with/without reducer), the invocation input dict, the TTL constant vs the timeout constant, or the `==` guard — a claim here without the exact line is dropped.
