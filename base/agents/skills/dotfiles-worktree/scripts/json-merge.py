#!/usr/bin/env python3
"""Three-way JSON merge driver for git.

    git config merge.dfjson.driver 'python3 <this> %O %A %B %P'
    .gitattributes:  base/claude/settings.json merge=dfjson

Merges structurally instead of by line, so two branches that each add a key,
a hook, or a permission to settings.json combine cleanly — the case plain text
merge turns into a conflict because both edits touch the same closing braces.

  objects   key by key; a key added on one side is kept, deleted on one
            (unchanged on the other) is dropped
  arrays    ours, minus elements the other side removed, plus elements it
            added (compared by value)
  scalars   one side changed it -> that side; both changed it differently
            -> a real conflict

A real conflict falls back to `git merge-file`, leaving ordinary conflict
markers in %A and exiting 1, so git reports the file as conflicted. The one
exception is nvim's lazy-lock.json: two different pinned commits for the same
plugin are both fine, so the other side (%B — during a rebase, the commit
being replayed) wins.
"""
import json
import os
import subprocess
import sys
from typing import Any

MISSING: Any = object()


class Conflict(Exception):
    pass


def merge(base: Any, ours: Any, theirs: Any, prefer_theirs: bool, path: str = "$") -> Any:
    if ours == theirs:
        return ours
    if base == ours:
        return theirs
    if base == theirs:
        return ours
    if isinstance(ours, dict) and isinstance(theirs, dict):
        return merge_objects(base if isinstance(base, dict) else {}, ours, theirs, prefer_theirs, path)
    if isinstance(ours, list) and isinstance(theirs, list):
        return merge_arrays(base if isinstance(base, list) else [], ours, theirs)
    if prefer_theirs:
        return theirs
    raise Conflict(path)


def merge_objects(base: dict, ours: dict, theirs: dict, prefer_theirs: bool, path: str) -> dict:
    keys = list(ours) + [k for k in theirs if k not in ours]
    result = {}
    for key in keys:
        b, o, t = base.get(key, MISSING), ours.get(key, MISSING), theirs.get(key, MISSING)
        merged = merge_value(b, o, t, prefer_theirs, f"{path}.{key}")
        if merged is not MISSING:
            result[key] = merged
    return result


def merge_value(b: Any, o: Any, t: Any, prefer_theirs: bool, path: str) -> Any:
    if o is MISSING and t is MISSING:
        return MISSING
    if o is MISSING:
        return t if b is MISSING else (MISSING if t == b else resolve_delete(t, prefer_theirs, path))
    if t is MISSING:
        return o if b is MISSING else (MISSING if o == b else resolve_delete(o, prefer_theirs, path))
    return merge(MISSING if b is MISSING else b, o, t, prefer_theirs, path)


def resolve_delete(survivor: Any, prefer_theirs: bool, path: str) -> Any:
    """One side deleted a key the other side edited."""
    if prefer_theirs:
        return survivor
    raise Conflict(path + " (deleted on one side, edited on the other)")


def merge_arrays(base: list, ours: list, theirs: list) -> list:
    def key(v: Any) -> str:
        return json.dumps(v, sort_keys=True)

    base_keys = {key(v) for v in base}
    theirs_keys = {key(v) for v in theirs}
    removed = base_keys - theirs_keys
    kept = [v for v in ours if key(v) not in removed]
    kept_keys = {key(v) for v in kept}
    added = [v for v in theirs if key(v) not in base_keys and key(v) not in kept_keys]
    return kept + added


def dump(value: Any, pathname: str) -> str:
    if os.path.basename(pathname) == "lazy-lock.json":
        return dump_lazy_lock(value)
    return json.dumps(value, indent=2) + "\n"


def dump_lazy_lock(value: dict) -> str:
    """lazy.nvim's own layout: sorted, one plugin per line."""
    lines = [
        f"  {json.dumps(name)}: {{ {', '.join(f'{json.dumps(k)}: {json.dumps(v)}' for k, v in spec.items())} }}"
        for name, spec in sorted(value.items())
    ]
    return "{\n" + ",\n".join(lines) + "\n}\n"


def load(path: str) -> Any:
    with open(path) as f:
        text = f.read()
    return json.loads(text) if text.strip() else {}


def text_merge(base_path: str, ours_path: str, theirs_path: str) -> int:
    subprocess.run(
        ["git", "merge-file", "-L", "ours", "-L", "base", "-L", "theirs", ours_path, base_path, theirs_path],
        check=False,
    )
    return 1


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: json-merge.py BASE OURS THEIRS PATHNAME", file=sys.stderr)
        return 2
    base_path, ours_path, theirs_path, pathname = argv[1:]
    try:
        base, ours, theirs = load(base_path), load(ours_path), load(theirs_path)
    except (OSError, ValueError) as err:
        print(f"json-merge: {pathname}: not parseable JSON ({err}); falling back to text merge", file=sys.stderr)
        return text_merge(base_path, ours_path, theirs_path)
    prefer_theirs = os.path.basename(pathname) == "lazy-lock.json"
    try:
        merged = merge(base, ours, theirs, prefer_theirs)
    except Conflict as conflict:
        print(f"json-merge: {pathname}: both sides changed {conflict} differently", file=sys.stderr)
        return text_merge(base_path, ours_path, theirs_path)
    with open(ours_path, "w") as f:
        f.write(dump(merged, pathname))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
