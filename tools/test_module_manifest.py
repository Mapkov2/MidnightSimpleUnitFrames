#!/usr/bin/env python3
"""Static red/green probes for module registration and locale work generation."""

import contextlib
import copy
import io
import json
import tempfile
import unittest
from pathlib import Path

import generate_module_manifest as g


FLAGS = ["Mainline", "Forever", "Vanilla", "Mists", "TBC"]


class ModuleManifestTest(unittest.TestCase):
    def setUp(self):
        scratch = Path("C:/tmp/m7")
        self.temp = tempfile.TemporaryDirectory(prefix="c9-static-", dir=scratch if scratch.is_dir() else None)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        matrix = "Suffix\tIsClassic\nMainline\tfalse\nVanilla\ttrue\nMists\ttrue\nTBC\ttrue\n"
        self.put("tools/classic-client-matrix.tsv", matrix.encode())
        self.base = g.CORE + "/Game/Shared/Initialize.lua"
        self.xml = g.CORE + "/Shared.xml"
        self.nested = g.CORE + "/Nested.lua"
        documents, loads = {}, []
        for addon in g.ADDONS:
            for flavor in ("Mainline", "Vanilla", "Mists", "TBC"):
                document = addon + "/" + addon + "_" + flavor + ".toc"
                scaffold = [[1, "## Title: Fixture\n"], [2, "\n"]]
                documents[document] = {"bom": flavor == "Mainline", "newline": "\r\n", "scaffold": scaffold}
                if addon == g.CORE:
                    loads.append({"document": document, "order": 3, "line": "{file}\n"})
        documents[self.xml] = {"bom": False, "newline": "\r\n", "scaffold": [[1, "<Ui>\n"], [3, "</Ui>\n"]]}
        self.manifest = {
            "version": 1, "documents": documents,
            "modules": [
                {"path": self.base, "clients": FLAGS[:], "loads": loads},
                {"path": self.xml, "clients": FLAGS[:], "loads": [
                    {"document": load["document"], "order": 4, "line": "{file}\n"} for load in loads]},
                {"path": self.nested, "clients": FLAGS[:], "loads": [
                    {"document": self.xml, "order": 2, "line": '  <Script file="{file}"/>\n'}]},
            ],
            "reviewed_lists": {path: {"bom": False, "newline": "\r\n", "text": "# reviewed fixture\n"}
                               for path in g.REVIEW_LISTS},
            "formats": {path: {"bom": False, "newline": "\r\n"} for path in (g.EXCLUSIONS, g.UNLOADED, g.LOCK)},
        }
        for module in self.manifest["modules"]:
            if module["path"].endswith(".lua"):
                self.put(module["path"], b"-- fixture\r\n")
        self.put(g.LOCALE_DIR + "/enUS.lua", b'L["Hello"] = "Hello"\r\n')
        self.put(g.LOCALE_DIR + "/deDE.lua", b'L["Hello"] = "Hallo"\r\n')
        # Locale packs are shipped source files too, even if this tiny graph retains them.
        for locale in ("enUS", "deDE"):
            self.manifest["modules"].append({"path": g.LOCALE_DIR + "/" + locale + ".lua", "clients": [],
                                              "retained": {"kind": "fixture", "reason": "Not loaded by this static fixture"}})

    def put(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def outputs(self):
        return g.generate(self.root, self.manifest)

    def add(self, clients, after=None, name="New.lua"):
        path = g.CORE + "/" + name
        module = {"path": path, "clients": clients, "after": after or self.base,
                  "reason": "Fixture selects only the explicitly requested clients"}
        self.manifest["modules"].append(module)
        self.put(path, b"-- new module\r\n")
        return path

    def test_shared_module_one_record_updates_four_tocs_xml_and_lock(self):
        before = self.outputs()
        path = self.add(FLAGS[:], self.nested)
        after = self.outputs()
        self.assertIn(b'<Script file="New.lua"/>', after[self.xml])
        self.assertEqual(sum(path.encode() in line for line in after[g.LOCK].splitlines()), 5)
        self.assertEqual(before[g.EXCLUSIONS], after[g.EXCLUSIONS])
        for document in before:
            if document.endswith(".toc"):
                self.assertEqual(before[document], after[document])

    def test_new_direct_module_updates_each_toc_and_preserves_bom_crlf(self):
        self.add(FLAGS[:])
        after = self.outputs()
        for flavor in ("Mainline", "Vanilla", "Mists", "TBC"):
            document = g.CORE + "/" + g.CORE + "_" + flavor + ".toc"
            data = after[document]
            self.assertIn(b"Game\\Shared\\Initialize.lua\r\nNew.lua\r\nShared.xml", data)
            self.assertEqual(data.startswith(b"\xef\xbb\xbf"), flavor == "Mainline")
            self.assertNotIn(b"\n", data.replace(b"\r\n", b""))

    def test_mainline_and_forever_flags_select_game_type(self):
        self.add(["Mainline"])
        self.add(["Forever"], name="Forever.lua")
        after = self.outputs()
        toc = after[g.CORE + "/" + g.CORE + "_Mainline.toc"]
        self.assertIn(b"New.lua [ExcludeLoadGameType camelot]", toc)
        self.assertIn(b"Forever.lua [AllowLoadGameType camelot]", toc)
        self.assertIn(b"Fixture selects only", after[g.EXCLUSIONS])
        docs = {p: raw.decode("utf-8-sig") for p, raw in after.items() if p.endswith((".toc", ".xml"))}
        mainline = g.walk(docs, ("Mainline", "Mainline", "standard", False), g.CORE)[0]
        forever = g.walk(docs, ("Forever", "Mainline", "camelot", False), g.CORE)[0]
        self.assertIn(g.CORE + "/New.lua", mainline)
        self.assertNotIn(g.CORE + "/New.lua", forever)
        self.assertIn(g.CORE + "/Forever.lua", forever)

    def test_insertion_after_final_line_without_newline_is_separated(self):
        for load in self.manifest["modules"][1]["loads"]:
            load["line"] = "{file}"
        self.add(FLAGS[:], self.xml)
        after = self.outputs()
        toc = after[g.CORE + "/" + g.CORE + "_Mainline.toc"]
        self.assertIn(b"Shared.xml\r\nNew.lua\r\n", toc)

    def test_client_subset_in_shared_xml_fails_instead_of_changing_other_clients(self):
        self.add(["Vanilla"], self.nested)
        with self.assertRaisesRegex(ValueError, "partial client selection in shared XML"):
            self.outputs()

    def test_bad_anchor_cycle_unregistered_file_and_flags_are_red(self):
        for mutation, message in (
            (lambda: self.add(FLAGS[:], "missing.lua"), "unknown placement anchor"),
            (lambda: self.add(["Typo"]), "invalid client flags"),
            (lambda: self.put(g.CORE + "/Unregistered.lua", b""), "Lua files missing"),
            (lambda: self.manifest["modules"][0].update(clients=[]), "client flags disagree"),
        ):
            with self.subTest(message=message):
                original = copy.deepcopy(self.manifest)
                mutation()
                with self.assertRaisesRegex(ValueError, message):
                    self.outputs()
                self.manifest = original
                for name in ("New.lua", "Unregistered.lua"):
                    (self.root / g.CORE / name).unlink(missing_ok=True)
        path = self.add(FLAGS[:])
        self.manifest["modules"][-1]["after"] = path
        with self.assertRaisesRegex(ValueError, "placement anchor cycle"):
            self.outputs()

    def test_english_only_text_produces_stubs_without_locale_mutations(self):
        before = (self.root / g.LOCALE_DIR / "deDE.lua").read_bytes()
        self.put(g.LOCALE_DIR + "/enUS.lua", b'L["Hello"] = "Hello"\r\nL["New %s"] = "New %s"\r\n')
        output = self.outputs()
        report = json.loads(output[g.LOCALE_REPORT])
        self.assertEqual(report["locales"]["deDE"], [{"key": "New %s", "stub": 'L["New %s"] = "New %s"'}])
        self.assertEqual(before, (self.root / g.LOCALE_DIR / "deDE.lua").read_bytes())
        self.assertNotIn(g.LOCALE_DIR + "/deDE.lua", output)

    def test_locale_lexer_accepts_lua_literals_and_ignores_comments(self):
        source = '''-- L["false"] = "bad"
--[=[ ["false2"] = "bad" ]=]
local extra = { ['single'] = 'fine', ["line\\nkey"] = [=[long
value]=], ["decimal"] = "\\065" }
L["quoted"] = "a\\\"b"
'''
        self.assertEqual(g.locale_entries(source), {"single": "fine", "line\nkey": "long\nvalue", "decimal": "A", "quoted": 'a"b'})

    def test_check_is_red_when_stale_read_only_then_green_after_write(self):
        self.put(g.MANIFEST, json.dumps(self.manifest).encode())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(g.main(["--root", str(self.root), "--check"]), 1)
            self.assertFalse((self.root / g.LOCK).exists())
            self.assertEqual(g.main(["--root", str(self.root), "--write"]), 0)
            self.assertEqual(g.main(["--root", str(self.root), "--check"]), 0)
            toc = self.root / g.CORE / (g.CORE + "_Mainline.toc")
            original = toc.read_bytes()
            toc.write_bytes(original + b"# stale\r\n")
            self.assertEqual(g.main(["--root", str(self.root), "--check"]), 1)
            self.assertEqual(toc.read_bytes(), original + b"# stale\r\n")
            self.assertEqual(g.main(["--root", str(self.root), "--write"]), 0)
            self.assertEqual(toc.read_bytes(), original)
            self.assertEqual(g.main(["--root", str(self.root), "--check"]), 0)


if __name__ == "__main__":
    unittest.main()
