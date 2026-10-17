# Cross-Repo Contract Drift (`<org>/<dotnet-repo>` and `<org>/<frontend-repo>`)

Owned by `py-contract-checker`. The highest-risk break is a Python model, enum or SSE event drifting from its consumer in a separately deployed repo: the .NET platform (`<org>/<dotnet-repo>`) or the frontend (`<org>/<frontend-repo>`). Both are readable via `gh`, no clone needed.

## Always read latest main, pinned per run

Local clones (`<local .NET clone>`, `<local frontend clone>`) are usually on feature branches. NEVER read them.

```bash
# Phase 0.5: resolve once per review, pass as CONTRACT_REFS to every agent
for REPO in <dotnet-repo> <frontend-repo>; do
  BR=$(gh repo view degreed/$REPO --json defaultBranchRef --jq .defaultBranchRef.name)
  SHA=$(gh api repos/degreed/$REPO/commits/$BR --jq .sha)
  echo "degreed/$REPO $BR $SHA"
done

# Locate a symbol
gh search code "class <DtoName>" --repo <org>/<dotnet-repo>

# Read raw source at the pinned SHA
gh api "repos/degreed/<repo>/contents/<path>?ref=<SHA>" -H "Accept: application/vnd.github.raw"
```

Every finding cites `<repo>@<sha7>:<path>:<line>` with the quoted line. Print the SHAs in the review footer ("verified against <dotnet-repo>@abc1234, <frontend-repo>@def5678"). If a SHA cannot be resolved, say so in the footer and emit the "unverifiable" WARN.

## .NET direction (Python <-> `<org>/<dotnet-repo>`)

Example: a request DTO with PascalCase properties that ASP.NET serializes to camelCase JSON must match the Python model's `alias=` names.

1. Map the Pydantic model to its .NET counterpart via the pair table below.
2. `gh search code "class <Dto>" --repo <org>/<dotnet-repo>`, then read it raw at the pinned SHA.
3. Grep `public <Type> <Name> { get; set; }` and any `[JsonPropertyName("...")]` / `[JsonProperty("...")]` overrides.
4. Apply the serializer's casing transform (default System.Text.Json = camelCase; verify Newtonsoft vs System.Text.Json).
5. Diff the .NET serialized names against the Python serialized names (Pydantic `alias=` / `alias_generator`).
6. **Enums:** every enum value Python sends or accepts must exist in the C# enum with the same serialized name (check `[JsonConverter(typeof(JsonStringEnumConverter))]` vs numeric). An unknown value is High: it can silently drop data.
7. Flag added / removed / renamed / retyped fields and changed required-ness or defaults (High if required, Medium otherwise).

## Frontend direction (Python <-> `<org>/<frontend-repo>`)

Search `<frontend app dirs that consume this API>`, plus `gh search code` for the endpoint path or SSE event name.

1. Endpoint paths and methods under the API prefix that the frontend calls.
2. TS interfaces for request bodies and responses: field names, optionality, union/enum values.
3. SSE event type names and the payload fields the frontend reads.
4. Flag a removed/renamed/retyped field or event a consumer still reads (High if required or on a main path, Medium otherwise), and a new required request field the frontend does not send.

## Coordinated deploys

```bash
gh pr list --repo degreed/<repo> --state open --search "<DtoOrComponent> in:file"
```

An open counterpart PR touching the same contract is a Medium "rollout order" finding naming the PR. Not a blocker.

## DTO / consumer pair table (extend as discovered)

| Python model | Counterpart |
|---|---|
| _add rows as you resolve them_ | |

## Gotchas / honest limits

- Casing depends on `JsonSerializerOptions`: grep for `[JsonPropertyName]` overrides, don't assume camelCase.
- Nested DTOs need recursive reads (one level at a time; log deeper refs as unresolved).
- The pair table rots: a missing or renamed counterpart file means **"could not verify"**, not "no break."
- **Graceful degradation:** if `gh` cannot reach a repo (auth/network) or the counterpart cannot be located, emit a single `Low` finding "contract unverifiable - manual check needed" and do NOT block the verdict on it. Never fabricate a field name, and never report "no break" for something you could not check.
