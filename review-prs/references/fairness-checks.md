# LLM-Output Fairness Checks (inference-time)

For `py-fairness-reviewer`. This is **not** dataset/training-time fairness — it is response-level fairness for a coaching app: does coaching tone, quality, safety, or recommendation differ unfairly across user identity or language?

The reviewer is a **static review check**: it flags risk in the diff and, for high-risk changes, **requires the PR author to add an eval** (Giskard / promptfoo / DeepEval). The reviewer does NOT run evals.

## When to load this agent

The diff touches any of: prompt templates, persona/tone/style instructions, the masking/PII path, name or user-profile interpolation into prompts, guardrail definitions, recommendation ranking, or the **multilingual / language-selection** path.

## Counterfactual review heuristics (apply to the diff)

- `FLAG`: a coaching response, recommendation, or tone branches on **user name, gender, age, ethnicity, or geography** without a documented fairness rationale. Ask: would swapping "Jamal" → "Brad" (everything else equal) change the response?
- `FLAG`: identity signals (name, profile, demographics) interpolated into a prompt with **no fairness control** and no eval covering them.
- `FLAG` (**language parity** — directly relevant to multilingual work): the system prompt / guardrail / safety instruction / output-validation is **weaker, missing, or different** on a non-English language path than on English. All languages must get equivalent guardrails, refusal behavior, and quality.
- `FLAG`: a secondary/fallback language path silently drops content, truncates, or degrades to English without parity of safety handling.
- `CHECK`: does masking/PII handling run identically across languages and locales?

## Required-eval gate (for high-risk PRs)

When the above FLAGs fire on a shipping path, the review should **require** one of:
- **promptfoo** `bias:gender|race|age|disability` plugins or a custom **counterfactual name-swap** test set (held language constant), wired into the existing `pytest_llm_eval` / `prcheck.yml` LLM-eval CI.
- **Giskard LLM scan** sycophancy + stereotype detectors against the deployed model.
- **DeepEval** bias metric in the eval suite.

Phrase the finding as: *"Identity/language-sensitive prompt path changed with no accompanying fairness eval — add a counterfactual eval before merge."* Severity Medium (Low if behind a flag / not yet shipping).

## Honest note

No off-the-shelf Claude skill exists for this; the checks above are the deployable-today static layer. True counterfactual coverage requires the author to add eval cases — the reviewer's job is to make that non-optional on sensitive paths.
