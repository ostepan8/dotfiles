#!/usr/bin/env python3
"""Unit tests for json-merge.py.  python3 tests/test_json_merge.py"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER = os.path.join(HERE, "..", "scripts", "json-merge.py")
spec = importlib.util.spec_from_file_location("json_merge", DRIVER)
assert spec is not None and spec.loader is not None
jm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jm)


class MergeTests(unittest.TestCase):
    def m(self, base, ours, theirs, prefer_theirs=False):
        return jm.merge(base, ours, theirs, prefer_theirs)

    def test_keys_added_on_both_sides_are_kept(self):
        self.assertEqual(self.m({"a": 1}, {"a": 1, "b": 2}, {"a": 1, "c": 3}), {"a": 1, "b": 2, "c": 3})

    def test_one_sided_scalar_change_wins(self):
        self.assertEqual(self.m({"a": 1}, {"a": 1}, {"a": 2}), {"a": 2})
        self.assertEqual(self.m({"a": 1}, {"a": 5}, {"a": 1}), {"a": 5})

    def test_deletion_on_one_side_is_kept(self):
        self.assertEqual(self.m({"a": 1, "b": 2}, {"a": 1}, {"a": 1, "b": 2, "c": 3}), {"a": 1, "c": 3})

    def test_arrays_union_additions_and_honor_removals(self):
        base = {"allow": ["x", "y"]}
        ours = {"allow": ["x", "y", "ours"]}
        theirs = {"allow": ["x", "theirs"]}  # removed y, added theirs
        self.assertEqual(self.m(base, ours, theirs), {"allow": ["x", "ours", "theirs"]})

    def test_hooks_added_under_different_events_merge(self):
        hook = lambda cmd: [{"matcher": "", "hooks": [{"type": "command", "command": cmd}]}]
        base = {"hooks": {"Stop": hook("a")}}
        ours = {"hooks": {"Stop": hook("a"), "PreToolUse": hook("b")}}
        theirs = {"hooks": {"Stop": hook("a"), "SessionStart": hook("c")}}
        merged = self.m(base, ours, theirs)
        self.assertEqual(set(merged["hooks"]), {"Stop", "PreToolUse", "SessionStart"})

    def test_same_scalar_changed_differently_is_a_conflict(self):
        with self.assertRaises(jm.Conflict):
            self.m({"model": "a"}, {"model": "b"}, {"model": "c"})

    def test_delete_versus_edit_is_a_conflict(self):
        with self.assertRaises(jm.Conflict):
            self.m({"a": 1}, {}, {"a": 2})

    def test_prefer_theirs_resolves_scalar_conflicts(self):
        self.assertEqual(self.m({"p": {"commit": "a"}}, {"p": {"commit": "b"}}, {"p": {"commit": "c"}}, True),
                         {"p": {"commit": "c"}})

    def test_inputs_are_not_mutated(self):
        base, ours, theirs = {"a": [1]}, {"a": [1, 2]}, {"a": [1, 3]}
        snapshot = json.dumps([base, ours, theirs])
        self.m(base, ours, theirs)
        self.assertEqual(json.dumps([base, ours, theirs]), snapshot)


class FormatTests(unittest.TestCase):
    def test_lazy_lock_layout_matches_lazy_nvim(self):
        text = ('{\n  "LuaSnip": { "branch": "master", "commit": "1" },\n'
                '  "blink.cmp": { "branch": "main", "commit": "2" }\n}\n')
        self.assertEqual(jm.dump(json.loads(text), "base/nvim/lazy-lock.json"), text)

    def test_settings_layout_is_two_space_ascii(self):
        self.assertEqual(jm.dump({"a": "\u2014"}, "settings.json"), '{\n  "a": "\\u2014"\n}\n')


class DriverTests(unittest.TestCase):
    def run_driver(self, base, ours, theirs, name="settings.json"):
        with tempfile.TemporaryDirectory() as d:
            paths = []
            for label, value in (("O", base), ("A", ours), ("B", theirs)):
                p = os.path.join(d, label)
                with open(p, "w") as f:
                    f.write(value if isinstance(value, str) else json.dumps(value, indent=2) + "\n")
                paths.append(p)
            code = subprocess.run([sys.executable, DRIVER, *paths, name], capture_output=True).returncode
            with open(paths[1]) as f:
                return code, f.read()

    def test_clean_merge_writes_result_and_exits_zero(self):
        code, out = self.run_driver({"a": 1}, {"a": 1, "b": 2}, {"a": 1, "c": 3})
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {"a": 1, "b": 2, "c": 3})

    def test_conflict_leaves_markers_and_exits_nonzero(self):
        code, out = self.run_driver({"m": "a"}, {"m": "b"}, {"m": "c"})
        self.assertNotEqual(code, 0)
        self.assertIn("<<<<<<<", out)

    def test_unparseable_input_falls_back_to_text_merge(self):
        code, out = self.run_driver('{"a": 1}\n', '{"a": 1,,}\n', '{"a": 2}\n')
        self.assertNotEqual(code, 0)
        self.assertIn("<<<<<<<", out)


if __name__ == "__main__":
    unittest.main()
