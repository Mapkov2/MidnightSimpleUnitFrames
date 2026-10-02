"""Self-test of tools/quality_ratchet.py on synthetic files.

Usage: python <this file> [repo root]

Proves the metrics count what they claim (strings and comments never count,
a table `;` is no statement), that a regression fails, an improvement passes,
an allowlisted regression passes, and that new files meet the profile limits.
It needs the Lua 5.1 luac (MSUF_LUAC or MSUF_LUA51), like the tool itself.
"""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("quality_ratchet", TOOLS / "quality_ratchet.py")
ratchet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ratchet)

PROFILE = "suite" if (TOOLS.parent / "MSUF_Suite").is_dir() else "classic"
ADDON = ratchet.PROFILES[PROFILE]["marker"]
LUAC = ratchet.find_luac()

CRAFTED = '\n'.join([
    'local a = 1; local b = 2',                          # one statement-level semicolon line
    'local t = { x = 1; y = 2 }',                        # a table separator is not a statement
    'local s = "a; b -- c"',                             # a string is not code
    'local c = [[long; string type(x) == "function"]]',  # nor is a long string
    '-- comment; type(x) == "function" and _G.Hidden',   # nor a comment
    '--[[ block; _G.Hidden2 ]]',
    'local f = _G.Foo',                                  # g_reads 1
    '_G.Bar = 1',                                        # a write is not a read
    'local g = _G["Baz"]',                               # g_reads 2
    'local h = rawget(_G, "Qux")',                       # g_reads 3
    'local ok = type(f) == "function"',                  # type_guards 1
    'if type(g) ~= "function" then g = nil end',         # type_guards 2
    'local msg = \'type(x) == "function"\'',             # a string
    'local n = { go = function() a(); b() end }',        # a statement semicolon inside a table value
    'local long = "' + "x" * 170 + '"',                  # long_lines 1
    '',
])


def run_tool(root, *extra):
    out = io.StringIO()
    argv = ["--root", str(root), "--profile", PROFILE, "--luac", LUAC,
            "--baseline", str(root / "baseline.json"), "--allowlist", str(root / "allowlist.json")] + list(extra)
    with contextlib.redirect_stdout(out):
        code = ratchet.main(argv)
    return code, out.getvalue()


def write(root, rel, text):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def allowlist(root, entries, data_files=None):
    write(root, "allowlist.json", json.dumps({"data_files": data_files or {}, "allowed": entries}))


def entry(rel, metric, maximum, reason="measured trade", date="2026-10-02"):
    return {"file": rel, "metric": metric, "max": maximum, "reason": reason, "date": date}


class Tree(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.rel = ADDON + "/A.lua"
        write(self.root, self.rel, "local x = 1\nlocal function f()\n    return type(x) == \"function\"\nend\n")
        write(self.root, ADDON + "/B.lua", "local y = 2\n")
        allowlist(self.root, [])
        code, text = run_tool(self.root, "--update")
        self.assertEqual(code, 0, text)

    def tearDown(self):
        self.temp.cleanup()

    def regress(self):
        write(self.root, self.rel, "local x = 1\nlocal function f()\n    return type(x) == \"function\""
                                   " and type(x) ~= \"function\"\nend\n")


class Metrics(unittest.TestCase):
    def test_crafted_counts(self):
        metrics, _ = ratchet.analyze_source(CRAFTED)
        self.assertEqual(metrics["semicolon_lines"], 2)
        self.assertEqual(metrics["g_reads"], 3)
        self.assertEqual(metrics["type_guards"], 2)
        self.assertEqual(metrics["long_lines"], 1)
        self.assertEqual(metrics["lines"], 15)

    def test_line_endings_do_not_change_the_numbers(self):
        self.assertEqual(ratchet.analyze_source(CRAFTED)[0], ratchet.analyze_source(CRAFTED.replace("\n", "\r\n"))[0])

    def test_clone_windows(self):
        shared = "\n".join("local value%d = Compute(%d)" % (i, i) for i in range(8)) + "\n"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            write(root, ADDON + "/One.lua", "-- one\n" + shared.replace("\n", " -- a\n"))
            write(root, ADDON + "/Two.lua", "-- two, longer\n" + shared.replace("local", "local  ").replace("\n", "   -- bb\n"))
            write(root, ADDON + "/Three.lua", "\n".join("local other%d = Other(%d)" % (i, i) for i in range(8)) + "\n")
            allowlist(root, [])
            results = ratchet.measure(root, PROFILE, {}, LUAC)[0]
        self.assertEqual(results[ADDON + "/One.lua"]["clone_windows"], 3)
        self.assertEqual(results[ADDON + "/Two.lua"]["clone_windows"], 3)
        self.assertEqual(results[ADDON + "/Three.lua"]["clone_windows"], 0)

    def test_luac_numbers(self):
        body = "\n".join("    local v%d = %d" % (i, i) for i in range(10))
        source = "local up = 1\nlocal function long()\n%s\n    return up\nend\nreturn long\n" % body
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            write(root, ADDON + "/L.lua", source)
            results = ratchet.measure(root, PROFILE, {}, LUAC)[0]
        values = results[ADDON + "/L.lua"]
        self.assertEqual(values["max_function"], 13)
        self.assertEqual(values["main_locals"], 2)
        self.assertEqual(values["max_upvalues"], 1)


class Check(Tree):
    def test_clean_tree_passes_and_ends_with_the_summary_line(self):
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)
        last = text.strip().splitlines()[-1]
        self.assertTrue(last.startswith("quality ratchet (%s): 2 files, 0 problems" % PROFILE), last)

    def test_regression_fails(self):
        self.regress()
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        self.assertIn("A.lua: type_guards 2 is worse than the baseline 1", text)

    def test_improvement_passes(self):
        write(self.root, self.rel, "local x = 1\nlocal function f()\n    return x\nend\n")
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)
        self.assertIn("1 improved", text)

    def test_allowlisted_regression_passes(self):
        self.regress()
        allowlist(self.root, [entry(self.rel, "type_guards", 2)])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)

    def test_allowlist_ceiling_is_a_ceiling(self):
        self.regress()
        allowlist(self.root, [entry(self.rel, "type_guards", 1)])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)

    def test_allowlist_entries_need_reason_date_metric_and_a_real_file(self):
        self.regress()
        allowlist(self.root, [entry(self.rel, "type_guards", 2, reason=" "),
                              entry(self.rel, "lines", 9, date="soon"),
                              entry(self.rel, "bogus", 1),
                              entry(ADDON + "/Gone.lua", "lines", 1)])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        for needle in ("needs a reason", "needs a date", "unknown metric", "does not measure"):
            self.assertIn(needle, text)

    def test_stale_entry_is_counted_not_failed(self):
        allowlist(self.root, [entry(self.rel, "lines", 99)])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)
        self.assertIn("(1 stale)", text)

    def test_missing_baseline_fails(self):
        (self.root / "baseline.json").unlink()
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)

    def test_new_file_meets_the_limits(self):
        write(self.root, ADDON + "/New.lua", "local a = 1; local b = 2\n")
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        self.assertIn("New.lua: new file has semicolon_lines 1 (limit 0)", text)
        write(self.root, ADDON + "/New.lua", "local a = 1\nlocal b = 2\n")
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)
        self.assertIn("1 new", text)

    def test_new_file_function_limit(self):
        body = "\n".join("    local v%d = %d" % (i, i) for i in range(160))
        write(self.root, ADDON + "/Big.lua", "local function big()\n%s\nend\nreturn big\n" % body)
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        self.assertIn("Big.lua: new file has max_function", text)

    def test_new_file_allowlist_entry_covers_it(self):
        write(self.root, ADDON + "/New.lua", "local a = 1; local b = 2\n")
        allowlist(self.root, [entry(ADDON + "/New.lua", "semicolon_lines", 1)])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)

    def test_new_file_clone_share(self):
        shared = "\n".join("local value%d = Compute(%d)" % (i, i) for i in range(12)) + "\n"
        write(self.root, ADDON + "/Copy.lua", shared)
        write(self.root, ADDON + "/Copy2.lua", shared)
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        self.assertIn("clone windows", text)

    def test_report_lists_totals_limits_and_the_worst_files(self):
        code, text = run_tool(self.root, "--report", "--top", "2")
        self.assertEqual(code, 0, text)
        for needle in ("files measured: 2", "totals: lines=", "files above the new-file limits", "worst lines:",
                       self.rel):
            self.assertIn(needle, text)

    @unittest.skipUnless(PROFILE == "classic", "the owned-file list is a Classic contract")
    def test_new_file_limits_apply_to_owned_files_only(self):
        write(self.root, "tools/classic-owned-addon-paths.txt", ADDON + "/Owned.lua\n")
        write(self.root, ADDON + "/Owned.lua", "local a = 1; local b = 2\n")
        write(self.root, ADDON + "/Mirror.lua", "local a = 1; local b = 2\n")
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        self.assertIn("Owned.lua: new file has semicolon_lines", text)
        self.assertNotIn("Mirror.lua: new file", text)

    def test_copying_code_names_the_partner_file(self):
        shared = "\n".join("local value%d = Compute(%d)" % (i, i) for i in range(8)) + "\n"
        write(self.root, ADDON + "/B.lua", shared)
        self.assertEqual(run_tool(self.root, "--update", "--accept-regressions")[0], 0)
        write(self.root, ADDON + "/C.lua", shared)
        allowlist(self.root, [entry(ADDON + "/C.lua", "clone_windows", 3)])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)
        self.assertIn("B.lua: clone_windows 3 is worse than the baseline 0 (+3); shares windows with %s/C.lua (3)" % ADDON, text)

    def test_data_and_generated_files_are_not_measured(self):
        write(self.root, ADDON + "/Data/Strings.lua", "local a = 1; local b = 2\n")
        write(self.root, ADDON + "/Gen.lua", "-- Generated by tools/make.lua. Do not edit by hand.\nlocal a = 1; local b = 2\n")
        write(self.root, ADDON + "/Libs/Vendor.lua", "local a = 1; local b = 2\n")
        allowlist(self.root, [], {ADDON + "/Data/*.lua": "data"})
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)
        self.assertIn("2 files", text)


class Update(Tree):
    def test_update_refuses_a_regression_without_an_entry(self):
        self.regress()
        code, text = run_tool(self.root, "--update")
        self.assertEqual(code, 1, text)
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)

    def test_update_absorbs_an_allowlisted_regression_and_prunes_the_entry(self):
        self.regress()
        allowlist(self.root, [entry(self.rel, "type_guards", 2)])
        code, text = run_tool(self.root, "--update")
        self.assertEqual(code, 0, text)
        self.assertIn("pruned: " + self.rel + " type_guards <= 2", text)
        self.assertEqual(json.loads((self.root / "allowlist.json").read_text())["allowed"], [])
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)

    def test_update_can_accept_regressions_on_purpose(self):
        self.regress()
        code, text = run_tool(self.root, "--update", "--accept-regressions")
        self.assertEqual(code, 0, text)
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 0, text)

    def test_update_locks_an_improvement_in(self):
        write(self.root, self.rel, "local x = 1\nlocal function f()\n    return x\nend\n")
        self.assertEqual(run_tool(self.root, "--update")[0], 0)
        self.regress()
        code, text = run_tool(self.root, "--check")
        self.assertEqual(code, 1, text)

    def test_baseline_is_deterministic(self):
        first = (self.root / "baseline.json").read_bytes()
        self.assertEqual(run_tool(self.root, "--update")[0], 0)
        self.assertEqual((self.root / "baseline.json").read_bytes(), first)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=0)
