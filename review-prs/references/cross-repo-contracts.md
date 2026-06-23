# Cross-Repo Contract Drift (.NET `degreed/Degreed`)

`py-impact-analyzer` can trace consumers **within** this repo, but Maestro's highest-risk break is a Python Pydantic model drifting from its .NET DTO counterpart in the separate `degreed/Degreed` repo. That repo is **readable today via `gh`** — no clone, no new infra.

## Recipes (verified)

```bash
# Locate a DTO class
gh search code "class CoachConnectRequest" --repo degreed/Degreed

# Read raw C# source
gh api repos/degreed/Degreed/contents/<path>.cs -H "Accept: application/vnd.github.raw"

# Grep property names + JSON attributes in a fetched file
#   public <Type> <Name> { get; set; }
#   [JsonPropertyName("...")]  /  [JsonProperty("...")]
```

Known anchor: `CoachConnectRequest` lives at
`trunk/Degreed.Common.Standard/Models/CoachConnectParameters.cs` with PascalCase
props (`SessionId`, `CoachId`, `TimeZone`, `PreviewLanguage`, `ConversationId`…)
that ASP.NET serializes to camelCase JSON — which is exactly what this repo's
`BaseSessionRequestModel` aliases must match.

## Algorithm (when a PR touches a request/response Pydantic model)

1. Map the Pydantic model to its .NET counterpart via the pair table below.
2. `gh search code "class <Dto>" --repo degreed/Degreed`, then read it raw.
3. Grep C# `public <Type> <Name> { get; set; }` **and** any `[JsonPropertyName("…")]` / `[JsonProperty("…")]` overrides.
4. Apply the serializer's casing transform (default System.Text.Json = camelCase; verify Newtonsoft vs System.Text.Json).
5. Diff the .NET serialized names against the Python serialized names (Pydantic `alias=` / `alias_generator`).
6. **Flag** added / removed / renamed fields that now mismatch → cross-repo contract drift (High if a required field; Medium otherwise).

## DTO pair table (extend as discovered)

| Python model (`request_and_response/`) | .NET DTO (`degreed/Degreed`) |
|---|---|
| `BaseSessionRequestModel` / `ConnectRequestModel` | `CoachConnectParameters.cs :: CoachConnectRequest` |
| `MaestroTranslationRequest` | `MaestroStudioController` translate DTOs |
| translation callback payload | `MaestroStudioController.AddTranslations` request body |
| _add rows as you resolve them_ | |

## Gotchas / honest limits

- Casing depends on `JsonSerializerOptions` — grep for `[JsonPropertyName]` overrides; don't assume camelCase blindly.
- Nested DTOs require recursive reads (one level at a time; log deeper refs as unresolved).
- The pair table rots — treat a missing/renamed .NET file as **"could not verify"**, not as "no break."
- **Graceful degradation:** if `gh` can't reach `degreed/Degreed` (auth/network), emit a single WARN finding ("cross-repo contract unverifiable — manual check needed") and do NOT block the verdict on it. Never fabricate a .NET field name.
