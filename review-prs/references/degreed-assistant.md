# Repo profile: degreed/degreed-assistant

Used when the PR's base repo is `degreed/degreed-assistant` (Phase 0.5, step 1b). The orchestrator appends this file to
`REVIEW_RULES` for every agent and the judge. **Where it conflicts with the Coach Builder conventions inside an agent
prompt (`app/...` paths, `app.log_manager`, `app/request_and_response/`, LangGraph, LiveKit), this file wins.** Do not
report a Coach Builder rule as a finding on this repo. Facts below come from the repo's `CLAUDE.md` and the code on
`main`. The roles of `action_guard`, `gates`, `identity`, `session_baggage`, `run_liveness`, `tool_budget`,
`registry_client` and `stream_queue` are inferred from their names and docstrings: read the source before you flag
anything, and drop a finding you cannot back with a quoted line.

## 1. What it is

Python 3.12 / FastAPI backend of the Degreed learning assistant, root path `/dgassistant`. Azure OpenAI, LangChain
(legacy chat in `backend/genai`) and pydantic-ai (Maestro agents in `backend/dg_maestro`), Redis sessions and chat
history, WebSocket (`/dgassistant/ws`), Datadog APM, Kubernetes (several pods). Tests: `pytest tests/`, style: `ruff`.

## 2. Layout and conventions (these replace the Coach Builder ones)

- Hexagonal: `backend/api/*` adapters, `backend/genai/*` domain (intent classifier, response builder, tools/chains),
  `backend/storage/*` ports (Redis), `backend/sockets/*`, `backend/config/*`, `backend/dg_maestro/*` (Maestro agent runtime).
- Endpoints: `async def`, `@tracer.wrap(name=..., service="degreed-assistant")`, Pydantic request models, routes under
  `/dgassistant`. A sync endpoint, a missing tracer or an unvalidated body is a finding.
- Logging: `from backend.config.log_config import get_logger, log_info, log_error, log_debug, log_warn`. `print()` is a
  finding. (`app.log_manager` does not exist here.)
- Config: environment variables via `backend/config/app_config.py` / `azure_config.py`; a hardcoded key or URL is a finding.
- Redis: the shared client from `backend.config.app_config`, never a new connection per request.

## 3. The Maestro agent surface (`backend/dg_maestro/**`) is what this repo is risky about

Agents are delegated to through `delegate_to_<agent>` tools (`ai.degreed/a2a`) that stream over SSE from the Web.vNext
relay, can pause for approval/question/confirmation, and resume on a later `/chat`. Review these as stateful,
multi-pod, client-round-tripped code. The bugs are silent.

**Pause and resume (`agent_pause.py`, `mrtr.py`, `conversation_toolcalls.py`)**
- The pause "stash" (kind, agent `sessionId`, question ids/labels) round-trips through the client in
  `callProviderMetadata["ai.degreed"]["deferred"]`. The client can edit it. FLAG any use of stash content that is not
  re-validated on the server: the `sessionId` must belong to the current user, org and agent, the kind must match the
  pending pause, and `override_args` must not be able to change which tool or agent is re-run.
- Approval replay: an approval answered twice, answered after withdrawal, or answered for another run must not
  re-execute the action. Check the withdrawn-approval and two-approval paths and their tests.
- An approval card must show what will happen in words (names, not ids). A change that drops detail from the card, or
  numbers items twice, is a user-visible regression (the tests in `test_dg_maestro_agent_approvals.py` pin this).

**Streaming (`agent_stream_tool.py`, `stream_queue.py`, `streamed_calls.py`)**
- Frames come from an external, unbounded producer. FLAG unbounded accumulation (text, steps, reasoning, artifacts),
  work that is quadratic in the number of frames (the cumulative step payload is re-sent on every notification), and a
  missing cap where `_MAX_STEPS` is shared by both delegate paths.
- A stream that ends without a `done` frame must end in the documented error or interrupted envelope, never hang or
  return partial data as success. Unknown frame types and keepalives must stay ignored (forward compatible).
- The tool definition (name, description, JSON schema) must stay identical to the MCP-dispatched one: the model and the
  Redis tool cache must see no difference. FLAG a change that alters it on one path only.
- The SSE connection, queue and per-call state must be released on cancel, timeout and error.

**Steps and correlation (`agent_steps.py`)**
- Progress is matched to a tool call by the application-level `ai.degreed/toolCallId`, not by the MCP progress token
  (fastmcp overwrites it). FLAG correlation by `progress_token`.

**Scope and identity (`identity.py`, `session_baggage.py`, `action_guard.py`, `gates/`, `registry_client.py`)**
- A run scoped to one agent (`RunDeps.agent_name`, scoped instructions) must only expose and call that agent.
- Every Redis key, conversation and tool-cache entry carries org and user (or session); a key without them can leak
  across tenants. The tool cache must not serve one org's result to another.
- Actions that change data go through `action_guard` / `gates`. FLAG a new write path that bypasses them.

**Liveness and failure (`run_liveness.py`, `conversation_store.py`, `tool_budget.py`)**
- Several pods share state. FLAG a run that no pod can close (lost pod), a completion call to the monolith that is
  dropped instead of retried while it is down, and a reply that is lost without telling the user it was not saved.
- Tool budgets and retries need an upper bound. FLAG a retry loop with no cap or backoff.

## 4. Contracts (check against pinned latest `main`, per `cross-repo-contracts.md`)

- `models.py`, `protocol.py`, the SSE frames and the AI SDK (Vercel AI) stream parts are consumed by the frontend
  (`degreed/fe-workspace`); the delegate envelope, MCP tools and `notifications/progress` `_meta` keys are produced by
  the .NET Web.vNext (`degreed/Degreed`, `DgMaestro`). A renamed field, changed enum or new required key with no
  matching change on the other side is a High.

## 5. Not findings here

- Missing LangGraph reducers, `app/agents/**` rules and LiveKit rules (not used in this repo).
- `from __future__ import annotations` and the long module docstrings in `dg_maestro` (the house style).
