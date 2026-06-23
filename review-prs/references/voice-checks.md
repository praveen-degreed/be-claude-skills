# Voice / Realtime Agent Review Checks (LiveKit)

For `py-voice-reviewer`. Load when the diff touches `app/realtime/`, `realtime.py`, `agent_session*`, voice tool calling, STT/TTS, or the agent-session contract. Voice findings also overlap `py-logic-reviewer` (LLM06) and `py-impact-analyzer` (worker contract).

## Session safety & bounds

- `FLAG`: voice/realtime session has **no max duration and no max-steps / tool-call budget** — pairs with LLM06 unbounded-loop and LLM10 consumption.
- `CHECK`: turn-detection configured (semantic/VAD), not left default; interruption + resume params set (`resume_false_interruption`, `false_interruption_timeout`) where the SDK supports them.
- `FLAG`: STT transcript flows into the LLM prompt without the untrusted-data delimiting + injection scan applied to text input (see `llm-security-checks.md` LLM01 voice).
- `FLAG`: voice agent tools run under a broad service identity instead of the requesting user's scope (confused-deputy — see LLM06).

## Contract breakage (LiveKit workers are a SEPARATE deployment/process)

A voice DTO change breaks workers **silently**. Verify against the agent-session contract:
- `SaveChatMessageRequest`: `messageText, senderType, conversationId, coachId, profileKey, mode, isRoleplay`
- `RagSearchRequest`: `queries, collectionName, conversationId, coachId, topK`
- `FLAG`: any field removed/renamed in `agent_session_models.py` or the session model the worker reads → silent voice failure. Cross-check `realtime/config.py` `parse_base_config` and how `full_session.language.model_dump()` is round-tripped.

## Model/vendor regression

- `FLAG`: a PR that changes the realtime model, STT, or TTS vendor **without an accompanying regression eval** — voice agents silently degrade when a vendor bumps a model.

## Useful review thresholds (cite as targets, don't enforce in static review)

P90 end-to-end latency < 3.5s, P99 < 5s, WER < 5%, task completion > 90%. If the PR claims to improve/measure these, check a regression eval backs the claim.

## Honest note

LiveKit's built-in test framework is **text-only** (validates logic, not real audio). Real audio-native eval (Hamming/Coval) is an external harness the author adds — the reviewer flags its absence on risky voice PRs; it does not run it.
