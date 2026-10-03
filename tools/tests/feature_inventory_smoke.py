"""Self-test of tools/feature_inventory.py on synthetic trees.

Usage: python tools/tests/feature_inventory_smoke.py [repo root]

Proves each extractor reads what it claims (comments never count), that a removal in any
category fails, that an allowlisted removal passes, that additions never fail, and that
--freeze, --baseline-rev and --provenance work against a real (temporary) git history.
"""

import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("feature_inventory", TOOLS / "feature_inventory.py")
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)

MAIN = "MidnightSimpleUnitFrames/"
OPTIONS = "MidnightSimpleUnitFrames_Options/"
INDEX = OPTIONS + "Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
INDEX_CLASSIC = OPTIONS + "Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua"


def index_text(rows):
    body = "\n".join("\t".join(row) for row in rows)
    return "Search.StaticIndexBlob = [==[\n" + body + "\n]==]\n"


def row(page, label, kind="toggle", setting="", action="", hint="Section > Part", route=None):
    # Column 8 is the search identity: "id", page and route joined by the unit separator, with the
    # route's dots percent-encoded, as the index generator writes it.
    route = route or label.lower().replace(" ", "-")
    identity = "id\x1f%s\x1fmenu2%%2E%s%%2E%s" % (page, page, route.replace(".", "%2E"))
    return [page, label, kind, setting, action, hint, label.lower(), identity, "sec", "", "", "hay"]


def tree():
    return {
        MAIN + "Locales/enUS.lua": 'L["Hello"] = "Hello"\nL["Say %s"] = "Say %s"\n-- L["Commented"] = "x"\n',
        MAIN + "Locales/deDE.lua": 'L["Only German"] = "x"\n',
        MAIN + "Runtime/Slash.lua": (
            '_G.SLASH_MSUFTEST1 = "/msuftest"\n'
            'SLASH_MSUFTWO1 = "/msuftwo"\nSLASH_MSUFTWO2 = "/mt"\n'
            '-- SLASH_MSUFGHOST1 = "/ghost"\n'
            '_G.SlashCmdList["MSUFTEST"] = function() end\n'
            'FULL_SLASH_MAX = "CURMAX"\nFULL_SLASH_BOGUS1 = "/bogus"\n'
            'Commands.Register({\n    name = "reset",\n    aliases = { "default", "factory" },\n    run = function() end,\n})\n'
            'Commands.RegisterExternal({ usage = "/rl", help = "Reload." })\n'),
        MAIN + "Bindings.xml": '<Bindings><Binding name="MSUF_TOGGLE" header="MSUF"/><!-- x --></Bindings>\n',
        MAIN + "Shell/Binding.lua": 'BINDING_HEADER_MSUF = "MSUF"\nBINDING_NAME_MSUF_TOGGLE = "Toggle"\n',
        MAIN + "Kernel/Exports.lua": 'ExportPublic("MSUF_One", One)\nExport("MSUF_Two", Two)\nPublishCompat("MSUF_Three", 3)\n'
                                     '-- ExportPublic("MSUF_Ghost", 0)\n',
        MAIN + "State/MSUF_Defaults.lua": ('if g.alpha == nil then g.alpha = 1 end\ng.beta = 2\n'
                                           'local t = { gamma = 3, delta = 4 }\n-- g.epsilon = 5\n'),
        MAIN + "State/MSUF_Profiles.lua": "if g.notADefault == nil then g.notADefault = 1 end\n",
        MAIN + "Libs/Vendor.lua": 'ExportPublic("MSUF_Vendor", 1)\n',
        INDEX: index_text([row("auras", "Border", setting="auras.border"), row("auras", "Reset", "button", action="auras_reset"),
                           row("bars", "Height", "slider", "bars.height"),
                           row("bars", "Delimiter", "dropdown", "bars.sep", hint="Hp > Text", route="hp.sep"),
                           row("bars", "Delimiter", "dropdown", "bars.sep", hint="Power > Text", route="power.sep")]),
        INDEX_CLASSIC: index_text([row("bars", "Height", "slider", "bars.height")]),
    }


def write_tree(root, files):
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")


def run_tool(root, *extra):
    out = io.StringIO()
    argv = ["--root", str(root), "--baseline", str(root / "baseline.json"),
            "--allowlist", str(root / "allowlist.json")] + list(extra)
    with contextlib.redirect_stdout(out):
        code = inventory.main(argv)
    return code, out.getvalue()


def git(root, *args):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                           "-c", "core.autocrlf=false", "-C", str(root)] + list(args),
                          capture_output=True, text=True, check=True).stdout.strip()


class Extractors(unittest.TestCase):
    def setUp(self):
        self.items = inventory.extract(tree())

    def test_locale_reads_enUS_only_and_skips_comments(self):
        self.assertEqual(self.items["locale"], {"Hello", "Say %s"})

    def test_slash(self):
        self.assertEqual(self.items["slash"], {"/msuftest", "/msuftwo", "/mt", "handler MSUFTEST", "/msuf reset",
                                               "/msuf default", "/msuf factory", "/rl"})

    def test_bindings(self):
        self.assertEqual(self.items["bindings"], {"binding MSUF_TOGGLE", "BINDING_HEADER_MSUF", "BINDING_NAME_MSUF_TOGGLE"})

    def test_exports_skip_comments_and_libs(self):
        self.assertEqual(self.items["exports"], {"MSUF_One", "MSUF_Two", "MSUF_Three"})

    def test_defaults_only_from_the_defaults_files(self):
        self.assertEqual(self.items["defaults"], {"alpha", "beta", "gamma", "delta"})

    def test_index_rows_per_client(self):
        self.assertEqual(self.items["settings"], {"main: auras.border", "main: bars.height", "main: bars.sep",
                                                  "classic: bars.height"})
        self.assertEqual(self.items["actions"], {"main: auras_reset"})
        self.assertEqual(self.items["rows"], {
            "main: auras | Section > Part | Border | toggle | auras.border | border",
            "main: auras | Section > Part | Reset | button | action auras_reset | reset",
            "main: bars | Section > Part | Height | slider | bars.height | height",
            "main: bars | Hp > Text | Delimiter | dropdown | bars.sep | hp.sep",
            "main: bars | Power > Text | Delimiter | dropdown | bars.sep | power.sep",
            "classic: bars | Section > Part | Height | slider | bars.height | height"})

    def test_identical_rows_keep_their_multiplicity(self):
        twin = row("bars", "Twin", "toggle", "bars.twin")
        items = inventory.extract({INDEX: index_text([twin, twin])})
        self.assertEqual(len(items["rows"]), 2)

    def test_locale_keys_with_dashes_and_commented_out_ones(self):
        files = {MAIN + "Locales/enUS.lua": 'L["Dash -- inside"] = "x"\n--[[\nL["Blocked"] = "y"\n]]\n--[==[ L["Long"] = "z" ]==]\n'
                                            '-- L["Line"] = "w"\nL["After"] = "v"\n'}
        self.assertEqual(inventory.extract(files)["locale"], {"Dash -- inside", "After"})

    def test_xml_comments_hide_bindings(self):
        files = {MAIN + "Bindings.xml": '<Bindings>\n<!-- <Binding name="MSUF_OLD"/> -->\n<Binding name="MSUF_NEW"/>\n'
                                        '<!--\n<Binding name="MSUF_BLOCK"/>\n-->\n</Bindings>\n'}
        self.assertEqual(inventory.extract(files)["bindings"], {"binding MSUF_NEW"})

    def test_line_endings_do_not_matter(self):
        crlf = {path: text.replace("\n", "\r\n") for path, text in tree().items()}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for rel, text in crlf.items():
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(text.encode("utf-8"))
            self.assertEqual(inventory.extract(inventory.read_working_tree(root)), self.items)


class Check(unittest.TestCase):
    def setUp(self):
        self.temp = None
        self.fresh()

    def fresh(self):
        if self.temp is not None:
            self.temp.cleanup()
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.files = tree()
        write_tree(self.root, self.files)
        inventory.write_snapshot(self.root / "baseline.json",
                                 inventory.snapshot_from(inventory.extract(self.files), "base", "0" * 40))

    def tearDown(self):
        self.temp.cleanup()

    def change(self, rel, old, new):
        path = self.root / rel
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")

    def allow(self, entries):
        (self.root / "allowlist.json").write_text(json.dumps({"removed": entries}), encoding="utf-8")

    def test_unchanged_tree_passes_with_one_summary_line(self):
        code, text = run_tool(self.root)
        self.assertEqual(code, 0, text)
        last = text.strip().splitlines()[-1]
        self.assertTrue(last.startswith("feature inventory (baseline base,"), last)
        self.assertIn("0 removed", last)

    def test_every_category_fails_on_a_removal(self):
        cases = [("locale", MAIN + "Locales/enUS.lua", 'L["Hello"] = "Hello"\n', ""),
                 ("slash", MAIN + "Runtime/Slash.lua", 'SLASH_MSUFTWO2 = "/mt"\n', ""),
                 ("bindings", MAIN + "Bindings.xml", '<Binding name="MSUF_TOGGLE" header="MSUF"/>', ""),
                 ("exports", MAIN + "Kernel/Exports.lua", 'Export("MSUF_Two", Two)\n', ""),
                 ("defaults", MAIN + "State/MSUF_Defaults.lua", "g.beta = 2\n", ""),
                 ("settings", INDEX, "\tauras.border\t", "\t\t"),
                 ("rows", INDEX, "auras\tReset\t", "auras\tReset again\t"),
                 ("actions", INDEX, "\tauras_reset\t", "\t\t")]
        for category, rel, old, new in cases:
            with self.subTest(category):
                self.fresh()
                self.change(rel, old, new)
                code, text = run_tool(self.root)
                self.assertEqual(code, 1, text)
                self.assertIn("FAIL removed %s:" % category, text)

    def drop_line(self, rel, needle):
        path = self.root / rel
        lines = path.read_text(encoding="utf-8").split("\n")
        kept = [line for line in lines if needle not in line]
        self.assertEqual(len(kept), len(lines) - 1, needle)
        path.write_text("\n".join(kept), encoding="utf-8", newline="\n")

    def test_losing_one_route_row_is_detected_although_label_and_key_survive(self):
        # Two rows share page, label and setting key and differ in route only: the old independent
        # sets (label, key, action) stayed unchanged when one of them went.
        self.drop_line(INDEX, "power%2Esep")
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        self.assertIn("FAIL removed rows: main: bars | Power > Text | Delimiter | dropdown | bars.sep | power.sep", text)
        self.assertNotIn("FAIL removed settings", text)

    def test_a_control_that_moves_route_or_section_is_a_removal(self):
        self.change(INDEX, "Hp > Text", "Hp > Layout")
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        self.assertIn("FAIL removed rows: main: bars | Hp > Text | Delimiter", text)

    def test_losing_one_of_two_identical_rows_is_detected(self):
        twin = row("bars", "Twin", "toggle", "bars.twin")
        files = dict(tree(), **{INDEX: index_text([twin, twin])})
        write_tree(self.root, files)
        inventory.write_snapshot(self.root / "baseline.json",
                                 inventory.snapshot_from(inventory.extract(files), "base", "0" * 40))
        write_tree(self.root, {INDEX: index_text([twin])})
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        self.assertIn("FAIL removed rows:", text)

    def test_commenting_out_a_binding_or_a_locale_assignment_is_a_removal(self):
        self.change(MAIN + "Bindings.xml", '<Binding name="MSUF_TOGGLE" header="MSUF"/>',
                    '<!-- <Binding name="MSUF_TOGGLE" header="MSUF"/> -->')
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        self.assertIn("FAIL removed bindings: binding MSUF_TOGGLE", text)
        self.fresh()
        self.change(MAIN + "Locales/enUS.lua", 'L["Hello"] = "Hello"\n', '--[[ L["Hello"] = "Hello" ]]\n')
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        self.assertIn("FAIL removed locale: Hello", text)

    def test_additions_never_fail(self):
        self.change(MAIN + "Locales/enUS.lua", 'L["Hello"]', 'L["Brand new"] = "x"\nL["Hello"]')
        code, text = run_tool(self.root)
        self.assertEqual(code, 0, text)
        self.assertIn("1 added", text)

    def test_allowlisted_removal_passes(self):
        self.change(MAIN + "Locales/enUS.lua", 'L["Hello"] = "Hello"\n', "")
        self.allow([{"category": "locale", "item": "Hello", "basis": "owner", "evidence": "owner call 2026-10-02",
                     "reason": "dropped on purpose", "date": "2026-10-02"}])
        code, text = run_tool(self.root)
        self.assertEqual(code, 0, text)
        self.assertIn("1 removed (1 allowlisted, 0 open)", text)

    def test_wildcard_and_list_entries(self):
        self.change(MAIN + "Kernel/Exports.lua", 'ExportPublic("MSUF_One", One)\nExport("MSUF_Two", Two)\n', "")
        self.allow([{"category": "exports", "items": ["MSUF_O*", "MSUF_Two"], "basis": "dead",
                     "evidence": "abc1234", "reason": "no callers", "date": "2026-10-02"}])
        code, text = run_tool(self.root)
        self.assertEqual(code, 0, text)

    def test_entry_in_the_wrong_category_does_not_cover(self):
        self.change(MAIN + "Locales/enUS.lua", 'L["Hello"] = "Hello"\n', "")
        self.allow([{"category": "exports", "item": "Hello", "basis": "owner", "evidence": "x", "reason": "y",
                     "date": "2026-10-02"}])
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)

    def test_entries_need_basis_evidence_reason_date_and_a_category(self):
        self.allow([{"category": "bogus", "item": "x", "basis": "whim", "evidence": " ", "reason": "", "date": "soon"}])
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        for needle in ("unknown category", "needs a basis", "needs evidence", "needs reason", "needs a date"):
            self.assertIn(needle, text)

    def test_stale_entries_are_counted_not_failed(self):
        self.allow([{"category": "locale", "item": "Hello", "basis": "owner", "evidence": "x", "reason": "y",
                     "date": "2026-10-02"}])
        code, text = run_tool(self.root)
        self.assertEqual(code, 0, text)
        self.assertIn("1 stale allowlist items", text)

    def test_missing_baseline_and_extractor_drift_fail(self):
        (self.root / "baseline.json").unlink()
        self.assertEqual(run_tool(self.root)[0], 1)
        inventory.write_snapshot(self.root / "baseline.json",
                                 dict(inventory.snapshot_from(inventory.extract(self.files), "base", "0" * 40), extractor=0))
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        self.assertIn("extractor", text)

    def test_diff_lists_removed_and_added(self):
        self.change(MAIN + "Locales/enUS.lua", 'L["Hello"] = "Hello"\n', 'L["Newer"] = "x"\n')
        code, text = run_tool(self.root, "--diff")
        self.assertEqual(code, 1, text)
        self.assertIn("- locale | Hello", text)
        self.assertIn("+ locale | Newer", text)


class GitBaseline(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        git(self.root, "init", "-q")
        write_tree(self.root, tree())
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "baseline")
        self.base = git(self.root, "rev-parse", "HEAD")

    def tearDown(self):
        self.temp.cleanup()

    def test_freeze_then_check_and_provenance(self):
        code, text = run_tool(self.root, "--freeze", self.base)
        self.assertEqual(code, 0, text)
        self.assertEqual(run_tool(self.root)[0], 0)
        path = self.root / (MAIN + "Locales/enUS.lua")
        path.write_text(path.read_text(encoding="utf-8").replace('L["Hello"] = "Hello"\n', ""), encoding="utf-8", newline="\n")
        git(self.root, "commit", "-q", "-am", "drop the greeting")
        code, text = run_tool(self.root)
        self.assertEqual(code, 1, text)
        code, text = run_tool(self.root, "--baseline-rev", self.base)
        self.assertEqual(code, 1, text)
        self.assertIn("FAIL removed locale: Hello", text)
        code, text = run_tool(self.root, "--provenance")
        self.assertIn("locale | Hello | ", text)
        self.assertIn("drop the greeting", text)

    def test_verify_baseline_catches_a_stale_snapshot(self):
        self.assertEqual(run_tool(self.root, "--freeze", self.base)[0], 0)
        self.assertEqual(run_tool(self.root, "--verify-baseline")[0], 0)
        data = json.loads((self.root / "baseline.json").read_text(encoding="utf-8"))
        data["items"]["locale"].append("Invented")
        (self.root / "baseline.json").write_text(json.dumps(data), encoding="utf-8")
        code, text = run_tool(self.root, "--verify-baseline")
        self.assertEqual(code, 1, text)
        self.assertIn("locale", text)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=0)
