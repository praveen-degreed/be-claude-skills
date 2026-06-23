# Vector-Search & Embedding Semantics Checks

For `py-agent-graph-reviewer` and `py-architecture-reviewer`. Load when the diff touches vector similarity search, topic/tag clustering, embedding thresholds, or `.format()`-templated endpoint URLs. These numeric-semantics bugs are invisible to a reviewer not told the direction convention.

---

## 1. Distance vs similarity — the direction trap (HIGH-value)

A vector store's `similarity_search_with_score` (LangChain / redisvl over Redis with `distance_metric COSINE`) returns a **cosine DISTANCE**, not a similarity:
- distance range `0..2`, where `0` = identical, larger = less similar.
- results are sorted **ascending** by distance (nearest first).

So the correct "is this a match" test against a *similarity* threshold is `distance <= (1.0 - similarity_threshold)`, i.e. **`if score > (1.0 - threshold): reject`**.

- **FLAG**: `if score > threshold: reject` (or `if score < threshold: accept`) used directly with a *similarity* threshold — this treats a distance as a similarity and matches far too loosely. Example: a `0.7` similarity threshold compared as `if distance > 0.7: skip` actually accepts everything with similarity ≥ 0.3.
- **FLAG (parity)**: the SAME threshold constant used as a **distance** bound at one call site (live nearest-match) and as a **similarity** bound at another (`if sim >= threshold`, e.g. reclustering using a raw cosine `dot/(‖a‖‖b‖)`). The two sites then disagree by construction — matching is loose while reclustering is strict, so mis-attributions are never corrected.
  - Verify by finding the sibling that does it right: a nearby module often has `if score > (1.0 - THRESHOLD)` WITH a comment like "search returns distance so the comparison is flipped" — that proves the intended convention and pinpoints the module missing the `1.0 -`.
- **CHECK**: whenever a raw `_cosine()` helper (returns true similarity) and a store `*_with_score` (returns distance) are both used against one threshold, they MUST be normalized to the same metric first.

## 2. `str.format()` silently drops params absent from the template (HIGH-value)

`"/api/x/{a}".format(a=1, b=2)` returns `/api/x/1` — the extra `b` is **silently discarded**, no error.

- **FLAG**: an endpoint/URL builder passing a path- or query-param key that has **no corresponding `{placeholder}`** in the template AND is not added to the query string. The param never reaches the server; the call returns the wrong, unfiltered result set and still gets a 200. Cross-check the route template string for the placeholder, and the query-string assembly for the key.
- This is distinct from DTO field drift (`cross-repo-contracts.md`) — it is request *assembly* correctness, and it fails silently.

## 3. Embedding dimension / model mismatch

- **FLAG**: a new embedding call whose model/dimension differs from the index it writes to or queries (index built at one dim, query at another → runtime error or garbage scores).
- **CHECK**: a reused vector index name shared across features that embed with different models — cross-contamination of the vector space.

---

## Output format — same as the loading agent's block. Evidence-or-drop: quote the `*_with_score` call, the comparison line, and the threshold definition; or the route template vs the passed param key.
