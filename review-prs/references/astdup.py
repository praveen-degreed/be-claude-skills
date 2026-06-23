#!/usr/bin/env python3
"""Identifier-agnostic duplicate / near-duplicate function detector (stdlib only).

Used by py-architecture-reviewer to ground reuse/DRY findings deterministically.
Catches Type-1/2 (exact + renamed) clones that token-based tools (jscpd) miss,
plus Type-3 (near-dup) via difflib. Type-4 semantic equivalence is left to the LLM.

Usage:
    # Intra-PR: compare the changed files against themselves + against existing code
    python astdup.py <file_or_dir> [<file_or_dir> ...]
    python astdup.py --threshold 0.85 backend/app/services/translation/

Exit 0 always (advisory). Prints clone clusters as text for the agent to read.
"""
from __future__ import annotations

import argparse
import ast
import sys
from difflib import SequenceMatcher
from pathlib import Path

MIN_NODES = 12  # ignore trivial functions (getters, one-liners)


def _skeleton(fn: ast.AST) -> tuple[str, ...]:
    """Identifier-agnostic structure: the sequence of AST node types."""
    return tuple(type(n).__name__ for n in ast.walk(fn))


def _functions(path: Path):
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (SyntaxError, UnicodeDecodeError):
        return
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            skel = _skeleton(node)
            if len(skel) >= MIN_NODES:
                yield path, node.name, node.lineno, skel


def _iter_py(targets: list[str]):
    for t in targets:
        p = Path(t)
        if p.is_dir():
            yield from p.rglob("*.py")
        elif p.suffix == ".py":
            yield p


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="+")
    ap.add_argument("--threshold", type=float, default=0.85,
                    help="near-dup ratio cutoff (0-1) for Type-3 clones")
    args = ap.parse_args()

    fns = [f for path in _iter_py(args.targets) for f in _functions(path)]

    exact: list[tuple] = []
    near: list[tuple] = []
    for i in range(len(fns)):
        pi, ni, li, si = fns[i]
        for j in range(i + 1, len(fns)):
            pj, nj, lj, sj = fns[j]
            if pi == pj and li == lj:
                continue
            if si == sj:
                exact.append((pi, ni, li, pj, nj, lj))
            else:
                ratio = SequenceMatcher(None, si, sj).ratio()
                if ratio >= args.threshold:
                    near.append((round(ratio, 3), pi, ni, li, pj, nj, lj))

    if exact:
        print("== EXACT / RENAMED clones (Type-1/2) ==")
        for pi, ni, li, pj, nj, lj in exact:
            print(f"  {ni} ({pi}:{li})  ==  {nj} ({pj}:{lj})")
    if near:
        print("\n== NEAR-duplicate functions (Type-3) ==")
        for r, pi, ni, li, pj, nj, lj in sorted(near, reverse=True):
            print(f"  {r:.0%}  {ni} ({pi}:{li})  ~~  {nj} ({pj}:{lj})")
    if not exact and not near:
        print("No exact or near-duplicate functions found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
