"""The public-globals ledger checks out, and its check can fail.

tools/public-globals.tsv lists the exported globals other code reads by name, with the readers;
tools/public_globals_ledger.py checks it (and rebuilds it from the local external sources).
This smoke runs the committed check and then proves it has teeth:

  1. the committed ledger passes, still carries the names every wave must keep, and gives every
     row at least one consumer entry backing each evidence class it claims;
  2. the export scanner finds each mechanism MSUF publishes through, on fixture text (calls and
     aliases, _G writes, XML names and handler functions, run-time built names), and ignores
     comments, strings and table-constructor fields;
  3. the scan is complete on the real tree: every ExportPublic("NAME") literal and every global
     the compiler sees written (luac's SETGLOBAL) is in the inventory;
  4. the check fails on a fixture tree when a ledgered export or table field is renamed or removed
     (a leftover mention in a comment or a string does not vouch for it), and names the readers that
     would break; an export that merely moved to another file still passes;
  5. a malformed ledger (unknown kind, missing consumer, evidence nothing backs, duplicate or
     unsorted rows, wrong header) is refused;
  6. the runtime half, public_globals_smoke.lua (every ledgered name and field exists after login,
     per client), fails on a ledger that lists a name or field no client has or records the wrong
     kind, and names the reader that would break;
  7. the outside-reader scan sorts reads correctly on a fixture addon: a field read through the
     namespace is a field row and not a global read, `_G["X"]`, rawget(_G, "X"), getglobal("X") and
     quoted names count, locals that only might hold a table are not tables, and a name only a
     run-time export site can publish is attributed to that site.

Needs luac 5.1 from MSUF_LUAC or PATH for step 3, lua 5.1 from MSUF_LUA or PATH for step 6, and
nothing outside the repository.
"""
import contextlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOL = os.path.join(ROOT, "tools", "public_globals_ledger.py")

# Names the 7.0 waves must find in the ledger: the unit frames and registries other addons
# anchor to, the SavedVariables, the namespace and host API handles, and the client lookups.
KEEP = (
    "MSUF_player", "MSUF_target", "MSUF_focus", "MSUF_UnitFrames", "MSUF_DB", "MSUF_GlobalDB", "MSUF_NS",
    "MSUF_HostAPI", "MSUF2", "MSUF_EM2", "MSUF_EditModeAPI", "MSUF_SwitchProfile", "MSUF_FontApplyEpoch",
    "SLASH_MIDNIGHTSUF1", "BINDING_NAME_MSUF_TOGGLE_OPTIONS", "MSUF_Keybind_ToggleOptions",
    "MSUF_AddonCompartment_OnClick", "MSUF_GroupAdditionalUnitOnLoad",
)
# Table fields the Suite and other addons read; renaming one is as breaking as renaming a global.
KEEP_FIELDS = (
    "MSUF_NS.Client", "MSUF_NS.L", "MSUF_NS.MSUF_Auras3", "MSUF_NS.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT",
    "MSUF2.Undo", "MSUF2.Widgets", "MSUF_EM2.Undo", "MSUF_HostAPI.version", "MSUF_EditModeAPI.RegisterElement",
    "MSUF_UnitFrames.player",
)


def fail(message):
    print("public globals ledger smoke FAILED: " + message)
    raise SystemExit(1)


def load_tool():
    spec = importlib.util.spec_from_file_location("public_globals_ledger", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_check(tool, root):
    """(passed, output) of the check on a root; the tool reports through print and SystemExit."""
    buffer = io.StringIO()
    passed = True
    with contextlib.redirect_stdout(buffer):
        try:
            tool.check(root)
        except SystemExit:
            passed = False
    return passed, buffer.getvalue()


def expect(condition, message):
    if not condition:
        fail(message)


# --------------------------------------------------------------------------------------
# 1. The committed ledger
# --------------------------------------------------------------------------------------

def committed_ledger(tool):
    passed, output = run_check(tool, ROOT)
    expect(passed, "the committed ledger does not check out:\n" + output)
    rows, problems = tool.parse_ledger(os.path.join(ROOT, "tools", "public-globals.tsv"))
    expect(not problems, "malformed ledger: " + "; ".join(problems))
    names = {row["name"] for row in rows}
    missing = [name for name in KEEP + KEEP_FIELDS if name not in names]
    expect(not missing, "the ledger lost names every wave must keep: " + ", ".join(missing))
    classes = {evidence for row in rows for evidence in row["evidence"]}
    expect(classes == set(tool.EVIDENCE), "the ledger carries evidence classes %s, expected all of %s" % (
        sorted(classes), ", ".join(tool.EVIDENCE)))
    for row in rows:
        expect(row["consumers"] and row["evidence"], "%s has no consumer or evidence" % row["name"])
    return rows


# --------------------------------------------------------------------------------------
# 2. The scanner on fixture text
# --------------------------------------------------------------------------------------

FIXTURE = '''
local _, MSUF = ...
local ExportPublic = MSUF.ExportPublic
local Export = MSUF.ExportPublic or function(name, value) _G[name] = value return value end
local G = _G
local function PublishCompat(name, value)
    _G[name] = value
    return value
end
ExportPublic("MSUF_FromExportPublic", function() end)
MSUF.ExportPublic("MSUF_FromQualifiedCall", {})
Export("MSUF_FromLocalAlias", 1)
PublishCompat("MSUF_FromPublishCompat", {})
_G.MSUF_FromGField = 1
_G["MSUF_FromGIndex"] = 2
G.MSUF_FromGAlias = 3
rawset(_G, "MSUF_FromRawset", 4)
function _G.MSUF_FromQualifiedFunction() end
function MSUF_FromBareFunction() end
MSUF_FromBareAssignment = 5
SLASH_MSUFFIXTURE1 = "/fixture"
BINDING_NAME_MSUF_FIXTURE = "Fixture"
CreateFrame("Frame", "MSUF_FromCreateFrame")
CreateFrame("Frame", "MSUF_NotAnExport_" .. index)
StaticPopupDialogs["MSUF_FIXTURE_POPUP"] = {}
tinsert(UISpecialFrames, "MSUF_FromSpecialFrames")
MSUF.MSUF_FromNamespaceField = 6
local table_ = {
    MSUF_InsideConstructor = 7,
}
local MSUF_LocalOnly = 8
MSUF_LocalOnly = 9
-- ExportPublic("MSUF_InComment", nil)
--[[ _G.MSUF_InBlockComment = 1 ]]
local text = "-- ExportPublic('MSUF_InString')"
local BUTTON_NAME = "MSUF_FixtureButton"
CreateFrame("Button", BUTTON_NAME, UIParent)
local function AnchorName(key)
    if key == "a" then return "MSUF_FixtureAnchorA" end
    return "MSUF_FixtureAnchorB"
end
CreateFrame("Frame", AnchorName(key), UIParent)
local nudge = "MSUF_FixtureNudge" .. dir
CreateFrame("Button", nudge, UIParent)
CreateFrame("Frame", "MSUF_FixtureDyn_" .. kind, UIParent)
ExportPublic("MSUF_FixtureExp" .. n, 1)
'''

EXPECTED = {
    "MSUF_FromExportPublic": "function", "MSUF_FromQualifiedCall": "table", "MSUF_FromLocalAlias": "value",
    "MSUF_FromPublishCompat": "table", "MSUF_FromGField": "value", "MSUF_FromGIndex": "value",
    "MSUF_FromGAlias": "value", "MSUF_FromRawset": "value", "MSUF_FromQualifiedFunction": "function",
    "MSUF_FromBareFunction": "function", "MSUF_FromBareAssignment": "value", "SLASH_MSUFFIXTURE1": "value",
    "BINDING_NAME_MSUF_FIXTURE": "value", "MSUF_FromCreateFrame": "frame", "MSUF_FIXTURE_POPUP": "popup",
    "MSUF_FromSpecialFrames": "frame", "MSUF_FromNamespaceField": "value",
    "MSUF_FixtureButton": "frame", "MSUF_FixtureAnchorA": "frame", "MSUF_FixtureAnchorB": "frame",
}
# Names a run-time site builds from a literal part: (prefix, suffix) of each family the scanner must list.
FAMILIES = (("MSUF_FixtureNudge", ""), ("MSUF_FixtureDyn_", ""), ("MSUF_FixtureExp", ""), ("MSUF_NotAnExport_", ""))
ABSENT = ("MSUF_InsideConstructor", "MSUF_LocalOnly", "MSUF_InComment", "MSUF_InBlockComment", "MSUF_InString",
          "MSUF_NotAnExport_")


def scanner_mechanisms(tool):
    exports, dynamic = {}, {}
    tool.scan_lua("MidnightSimpleUnitFrames/Fixture.lua", FIXTURE, exports, dynamic)
    for name, kind in EXPECTED.items():
        expect(name in exports, "the scanner missed the export %s" % name)
        entry = exports[name]
        expect(entry.sites, "%s has no site" % name)
        expect(kind in entry.kinds or not entry.kinds and kind == "value", "%s scanned as %s, expected %s" % (
            name, sorted(entry.kinds), kind))
    for name in ABSENT:
        expect(name not in exports, "the scanner invented the export %s" % name)
    expect(exports["MSUF_FromNamespaceField"].namespace_only(), "a MSUF.MSUF_X field is not a global")
    expect(not exports["MSUF_FromGField"].namespace_only(), "a _G write is a global")
    listed = [(f.prefix, f.suffix) for f in dynamic.get("MidnightSimpleUnitFrames/Fixture.lua", []) if not f.passthrough]
    for shape in FAMILIES:
        expect(shape in listed, "the run-time export site %s went unlisted (listed: %s)" % (shape, listed))
    xml ='<Ui><Button name="MSUF_FixtureTemplate" virtual="true"/>\n<Bindings>\n<Binding name="MSUF_FIXTURE_TOGGLE">\n' \
          'MSUF_FixtureAction()\n</Binding>\n<Binding name="CLICK MSUF_FixtureClickTarget:LeftButton"></Binding>\n</Bindings>\n' \
          '<Frame name="MSUF_FixtureHost" mixin="MSUF_FixtureMixin, MSUF_FixtureMixin2" secureMixin="MSUF_FixtureSecure">\n' \
          '<Scripts><OnLoad function="MSUF_FixtureOnLoad"/></Scripts></Frame>\n<!-- <OnClick function="MSUF_InXmlComment"/> --></Ui>'
    xml_exports = {}
    tool.scan_xml("MidnightSimpleUnitFrames/Fixture.xml", xml, xml_exports)
    for name in ("MSUF_FixtureTemplate", "MSUF_FIXTURE_TOGGLE", "MSUF_FixtureAction", "MSUF_FixtureClickTarget",
                 "MSUF_FixtureHost", "MSUF_FixtureMixin", "MSUF_FixtureMixin2", "MSUF_FixtureSecure", "MSUF_FixtureOnLoad"):
        expect(name in xml_exports and xml_exports[name].contract, "the XML scan missed %s" % name)
    expect("function" in xml_exports["MSUF_FixtureOnLoad"].kinds, "an XML function= handler is a function")
    expect("table" in xml_exports["MSUF_FixtureMixin"].kinds, "an XML mixin= names a table")
    expect("MSUF_InXmlComment" not in xml_exports, "the XML scan read a commented-out handler")
    toc = "## SavedVariables: MSUF_FixtureDB, MSUF_FixtureGlobal\n## AddonCompartmentFunc: MSUF_FixtureClick\n"
    toc_exports = {}
    tool.scan_toc("MidnightSimpleUnitFrames/Fixture_Mainline.toc", toc, toc_exports)
    for name in ("MSUF_FixtureDB", "MSUF_FixtureGlobal", "MSUF_FixtureClick"):
        expect(name in toc_exports and toc_exports[name].contract, "the TOC scan missed %s" % name)


# --------------------------------------------------------------------------------------
# 3. The scan on the real tree
# --------------------------------------------------------------------------------------

EXPORT_LITERAL = re.compile(r"\bExportPublic\([ \t]*[\"']([A-Za-z_][A-Za-z0-9_]*)[\"']")
SETGLOBAL = re.compile(rb"(?m)^\t\d+\t\[\d+\]\tSETGLOBAL\t[^\t]*\t; (\S+)\r?$")


def find_luac():
    candidate = os.environ.get("MSUF_LUAC") or shutil.which("luac")
    if not candidate or not os.path.exists(candidate):
        fail("no luac on PATH and MSUF_LUAC is unset; the Classic gate resolves both")
    banner = subprocess.run([candidate, "-v"], capture_output=True, text=True, errors="replace")
    if not ((banner.stdout or "") + (banner.stderr or "")).strip().startswith("Lua 5.1"):
        fail("luac must be Lua 5.1: " + candidate)
    return candidate


def complete_scan(tool):
    exports, _dynamic = tool.static_inventory(ROOT)
    tool.finish_contracts(exports)
    listed = []
    literals = set()
    for rel in tool.addon_files(ROOT):
        if not rel.endswith(".lua") or tool.vendored(rel):
            continue
        listed.append(os.path.join(ROOT, rel))
        literals.update(EXPORT_LITERAL.findall(tool.strip_comments(tool.read_text(os.path.join(ROOT, rel)))))
    expect({"MSUF_DB", "MSUF_ApplyAllCastbarsAndSync", "MSUF_GetFontPath"}.issubset(literals),
           "the scan root lost its profile, castbar and font export anchors")
    lost = sorted(name for name in literals if name not in exports and name not in tool.FOREIGN_GLOBALS)
    expect(not lost, "the inventory misses %d ExportPublic names: %s" % (len(lost), ", ".join(lost[:12])))
    luac = find_luac()
    written, batches = set(), [[]]
    for path in listed:
        if batches[-1] and sum(len(item) + 3 for item in batches[-1]) + len(path) > 24000:
            batches.append([])
        batches[-1].append(path)
    for batch in batches:
        run = subprocess.run([luac, "-l", "-p"] + batch, capture_output=True)
        expect(run.returncode == 0, "luac rejected a batch starting at %s" % batch[0])
        written.update(m.decode("utf-8") for m in SETGLOBAL.findall(run.stdout))
    expect(written, "luac printed no SETGLOBAL line; its listing format changed")
    lost = sorted(name for name in written if name not in exports and name not in tool.FOREIGN_GLOBALS)
    expect(not lost, "the inventory misses %d globals the compiler sees written: %s" % (len(lost), ", ".join(lost)))
    return len(literals), len(written), len(exports)


# --------------------------------------------------------------------------------------
# 4 and 5. The check on fixture trees
# --------------------------------------------------------------------------------------

HEADER = "\t".join(("name", "kind", "exporter", "consumers", "readers", "addons", "evidence", "clients", "note"))


def row(name, kind="function", exporter="MidnightSimpleUnitFrames/A.lua:1", consumers="MSUF_Suite:Core/X.lua:3",
        readers="1", addons="1", evidence="suite", clients="all", note=""):
    return "\t".join((name, kind, exporter, consumers, readers, addons, evidence, clients, note))


def build_tree(files, ledger_rows):
    root = tempfile.mkdtemp(prefix="msuf_ledger_")
    os.makedirs(os.path.join(root, "tools"))
    os.makedirs(os.path.join(root, "MidnightSimpleUnitFrames_Options"))
    for rel, text in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
    with open(os.path.join(root, "tools", "public-globals.tsv"), "w", encoding="utf-8", newline="") as handle:
        handle.write("\n".join(["# fixture", HEADER] + ledger_rows) + "\n")
    return root


def check_on_fixtures(tool):
    base = {"MidnightSimpleUnitFrames/A.lua": 'local ExportPublic = MSUF.ExportPublic\nExportPublic("MSUF_Kept", function() end)\n'}
    cases = []
    try:
        # A ledgered export that is still there passes.
        root = build_tree(base, [row("MSUF_Kept")])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "a ledger whose export exists was refused:\n" + output)

        # Renamed: fails and names the reader that would break.
        renamed = {"MidnightSimpleUnitFrames/A.lua": base["MidnightSimpleUnitFrames/A.lua"].replace("MSUF_Kept", "MSUF_Renamed")}
        root = build_tree(renamed, [row("MSUF_Kept", consumers="MapkoSkin:Core/SuiteProfiles.lua:38", evidence="external")])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(not passed, "a renamed export was not caught")
        expect("MSUF_Kept" in output and "MapkoSkin:Core/SuiteProfiles.lua:38" in output,
               "the failure must name the export and the reader that would break:\n" + output)

        # Removed outright.
        root = build_tree({"MidnightSimpleUnitFrames/A.lua": "local x = 1\n"}, [row("MSUF_Kept")])
        cases.append(root)
        passed, _output = run_check(tool, root)
        expect(not passed, "a removed export was not caught")

        # Moved to another file: still exported, so the check passes.
        moved = {"MidnightSimpleUnitFrames/A.lua": "local x = 1\n",
                 "MidnightSimpleUnitFrames/B.lua": base["MidnightSimpleUnitFrames/A.lua"]}
        root = build_tree(moved, [row("MSUF_Kept")])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "an export that moved to another file was refused:\n" + output)

        # A global that became a namespace field only is gone for the reader.
        field = {"MidnightSimpleUnitFrames/A.lua": "MSUF.MSUF_Kept = function() end\n"}
        root = build_tree(field, [row("MSUF_Kept")])
        cases.append(root)
        passed, _output = run_check(tool, root)
        expect(not passed, "a name that left _G for the namespace was not caught")

        # A renamed export whose old name is left in a comment or in a string is still gone.
        for label, leftover in (("a comment", '-- ExportPublic("MSUF_Kept", old)\n'),
                                ("a block comment", '--[[ ExportPublic("MSUF_Kept", old) ]]\n'),
                                ("a string", 'local note = "MSUF_Kept"\n'),
                                ("a string of code", "local code = 'ExportPublic(\"MSUF_Kept\", 1)'\n")):
            left = {"MidnightSimpleUnitFrames/A.lua": renamed["MidnightSimpleUnitFrames/A.lua"] + leftover}
            root = build_tree(left, [row("MSUF_Kept", consumers="MapkoSkin:Core/SuiteProfiles.lua:38", evidence="external")])
            cases.append(root)
            passed, output = run_check(tool, root)
            expect(not passed, "a renamed export stayed green with its old name left in " + label)
            expect("MapkoSkin:Core/SuiteProfiles.lua:38" in output, "the failure must name the reader:\n" + output)

        # A table-driven export (a literal in a list, no export call) is `listed`; only code vouches for it.
        table_driven = {"MidnightSimpleUnitFrames/A.lua": 'local NAMES = { "MSUF_Kept" }\nfor _, n in ipairs(NAMES) do X(n) end\n'}
        root = build_tree(table_driven, [row("MSUF_Kept", note="listed")])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "a listed export was refused:\n" + output)
        gone = {"MidnightSimpleUnitFrames/A.lua": "-- NAMES = { \"MSUF_Kept\" }\nlocal x = 1\n"}
        root = build_tree(gone, [row("MSUF_Kept", note="listed")])
        cases.append(root)
        passed, _output = run_check(tool, root)
        expect(not passed, "a listed export mentioned only in a comment stayed green")

        # An XML handler function: gone from the Lua side, the client can no longer resolve it.
        handler_xml = '<Ui><Button name="MSUF_T" virtual="true"><Scripts><OnLoad function="MSUF_OnLoadFn"/></Scripts></Button></Ui>'
        handler_row = row("MSUF_OnLoadFn", exporter="MidnightSimpleUnitFrames/H.lua:2", consumers="blizzard:H.xml:1", readers="0",
                          addons="0", evidence="blizzard-contract", clients="static")
        kept = {"MidnightSimpleUnitFrames/H.xml": handler_xml,
                "MidnightSimpleUnitFrames/H.lua": 'local ExportPublic = MSUF.ExportPublic\nExportPublic("MSUF_OnLoadFn", function() end)\n'}
        root = build_tree(kept, [handler_row])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "an XML handler row was refused:\n" + output)
        lost = dict(kept)
        lost["MidnightSimpleUnitFrames/H.lua"] = kept["MidnightSimpleUnitFrames/H.lua"].replace("MSUF_OnLoadFn", "MSUF_Other")
        root = build_tree(lost, [handler_row])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(not passed and "MSUF_OnLoadFn" in output, "a renamed XML handler stayed green:\n" + output)

        # Table fields: a nsfield row is guarded by a source line that writes the field.
        owner = 'local _, MSUF = ...\n_G.MSUF_NS = MSUF\n'
        table_row = row("MSUF_NS", kind="table", exporter="MidnightSimpleUnitFrames/A.lua:2")
        field_row = row("MSUF_NS.L", kind="nsfield", exporter="MidnightSimpleUnitFrames/A.lua:3",
                        consumers="MSUF_Suite:Locales/deDE.lua:6")
        root = build_tree({"MidnightSimpleUnitFrames/A.lua": owner + "MSUF.L = {}\n"}, [table_row, field_row])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "a ledgered table field was refused:\n" + output)
        for label, text in (("renamed", owner + "MSUF.Loc = {}\n"), ("renamed with a comment", owner + "MSUF.Loc = {}\n-- MSUF.L = {}\n"),
                            ("set to a string", owner + "local doc = 'MSUF.L = {}'\n"), ("removed", owner)):
            root = build_tree({"MidnightSimpleUnitFrames/A.lua": text}, [table_row, field_row])
            cases.append(root)
            passed, output = run_check(tool, root)
            expect(not passed, "a table field was %s and the check stayed green" % label)
            expect("MSUF_NS.L" in output and "MSUF_Suite:Locales/deDE.lua:6" in output,
                   "the failure for a field %s must name it and its reader:\n%s" % (label, output))
        moved_field = {"MidnightSimpleUnitFrames/A.lua": owner, "MidnightSimpleUnitFrames/B.lua":
                       "local _, ns = ...\nns.L = {}\n"}
        root = build_tree(moved_field, [table_row, field_row])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "a field that moved to another file was refused:\n" + output)
        root = build_tree({"MidnightSimpleUnitFrames/A.lua": "local _, MSUF = ...\nMSUF.L = {}\n"}, [table_row, field_row])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(not passed and "MSUF_NS" in output, "a table that left _G stayed green:\n" + output)

        # A binding or template declared in XML counts as exported by that file.
        xml = {"MidnightSimpleUnitFrames/Bindings.xml": '<Bindings><Binding name="MSUF_TOGGLE_X">MSUF_Act()</Binding></Bindings>'}
        root = build_tree(xml, [row("MSUF_TOGGLE_X", kind="binding", exporter="MidnightSimpleUnitFrames/Bindings.xml:1",
                                    consumers="blizzard:Bindings.xml:1", readers="0", addons="0",
                                    evidence="blizzard-contract", clients="static")])
        cases.append(root)
        passed, output = run_check(tool, root)
        expect(passed, "an XML binding row was refused:\n" + output)
    finally:
        for case in cases:
            shutil.rmtree(case, ignore_errors=True)


READER = '''
local function HostNamespace()
    return _G.MSUF_NS
end
local host = HostNamespace()
local auras = host.MSUF_Auras3
local ns = assert(_G.MSUF_NS, "MSUF is required")
local client = ns.Client
local menu = _G.MSUF2
local undo = menu.Undo
local opener = _G["MSUF2_Open"]
local whole = rawget(_G, "MSUF2")
local window = "MSUF2_Window"
local fonts = getglobal("MSUF_GetFontPath")
local rec = {}
local label = rec.label
local mixed = ns or rec.label
local other = mixed.Mixed
local registry = _G and _G.MSUF_UnitFrames
local player = registry.player
local both = host.MSUF2 and host.RegisterLocale
local groups = HostNamespace().GF
local rebuilt = _G["MSUF_" .. unit]
ns.Written = 1
-- local ignored = _G.MSUF_InAComment
'''


def external_reads(tool):
    """The outside-reader scan on a fixture addon: what counts as a global, a field, a prefix or nothing."""
    luac = find_luac()
    base = tempfile.mkdtemp(prefix="msuf_reader_")
    try:
        addon = os.path.join(base, "ProbeAddon")
        os.makedirs(addon)
        with open(os.path.join(addon, "ProbeAddon.toc"), "w", encoding="utf-8", newline="") as handle:
            handle.write("## Title: Probe\nReader.lua\n")
        with open(os.path.join(addon, "Reader.lua"), "w", encoding="utf-8", newline="") as handle:
            handle.write(READER)
        names = {"MSUF_Auras3", "MSUF2", "MSUF2_Open", "MSUF2_Window", "MSUF_GetFontPath", "MSUF_NS", "MSUF_UnitFrames"}
        tables = {"MSUF_NS", "MSUF", "MSUF2", "MSUF_UnitFrames"}
        scan = tool.scan_external(tool.repo_sources(base), names, tables, luac)
        read = set(scan.readers)
        for name in ("MSUF2", "MSUF2_Open", "MSUF2_Window", "MSUF_GetFontPath", "MSUF_NS", "MSUF_UnitFrames"):
            expect(name in read, "the scan missed a read of %s (read: %s)" % (name, sorted(read)))
        expect("MSUF_Auras3" not in read, "host.MSUF_Auras3 is a field of the namespace, not a read of the global")
        fields = set(scan.fields)
        for key in (("MSUF_NS", "MSUF_Auras3"), ("MSUF_NS", "Client"), ("MSUF2", "Undo"), ("MSUF_NS", "MSUF2"),
                    ("MSUF_NS", "RegisterLocale"), ("MSUF_NS", "GF"), ("MSUF_UnitFrames", "player")):
            expect(key in fields, "the scan missed the field read %s.%s (read: %s)" % (key + (sorted(fields),)))
        for key in (("MSUF_NS", "label"), ("MSUF_NS", "Mixed"), ("MSUF_NS", "Written"), ("MSUF2", "label")):
            expect(key not in fields, "the scan took %s.%s for a field read" % key)
        expect("MSUF_" in scan.prefixes, "the scan missed the quoted prefix of _G[\"MSUF_\" .. unit]")
        expect("MSUF_InAComment" not in scan.stray, "a name in a comment was read")
    finally:
        shutil.rmtree(base, ignore_errors=True)


def run_time_names(tool):
    """A name only a run-time export site can publish is attributed to that site; others are not."""
    scan = tool.ExternalScan()
    scan.loose["MSUF_GroupAdditional_party"][("Reader", "a.lua")] = tool.Reader("Reader", "a.lua", 3, False)
    scan.stray["MSUF_FixtureNudgeUp"][("Reader", "b.lua")] = tool.Reader("Reader", "b.lua", 4, False)
    scan.stray["BINDING_NAME_DETAILS_BOOKMARK1"][("Reader", "c.lua")] = tool.Reader("Reader", "c.lua", 5, False)
    scan.stray["MSUF_NoSuchFamily"][("Reader", "d.lua")] = tool.Reader("Reader", "d.lua", 6, False)
    families = {
        "MidnightSimpleUnitFrames/GroupFrames/X.lua": [tool.Family(214, "frame", "MSUF_GroupAdditional_", "", "key")],
        "MidnightSimpleUnitFrames/Shell/Y.lua": [tool.Family(456, "frame", "MSUF_FixtureNudge", "", "dir")],
        "MidnightSimpleUnitFrames/Kernel/K.lua": [tool.Family(58, "assign", "BINDING_NAME_", "", "binding"),
                                                  tool.Family(9, "export", "", "", "name")],
    }
    exports, names = {}, set()
    promoted = tool.promote_families(exports, names, scan, families)
    expect(sorted(promoted) == ["MSUF_FixtureNudgeUp", "MSUF_GroupAdditional_party"],
           "the run-time sites should publish exactly the MSUF-shaped names they can build, got %s" % promoted)
    expect(exports["MSUF_GroupAdditional_party"].primary()[1] == "MidnightSimpleUnitFrames/GroupFrames/X.lua"
           and exports["MSUF_GroupAdditional_party"].dynamic, "a promoted name points at its run-time export site")
    expect(("Reader", "a.lua") in scan.readers["MSUF_GroupAdditional_party"], "the readers of a promoted name move with it")
    expect("BINDING_NAME_DETAILS_BOOKMARK1" in scan.stray and "MSUF_NoSuchFamily" in scan.stray,
           "a name no run-time site can build stays unattributed")


MALFORMED = (
    ("a nsfield of a table that is not ledgered", [row("MSUF_Z.field", kind="nsfield")], "not a ledgered global"),
    ("a nsfield row not named Table.field", [row("MSUF_Z", kind="nsfield")], "Table.field"),
    ("an unknown kind", [row("MSUF_Kept", kind="gizmo")], "unknown kind"),
    ("no consumer", [row("MSUF_Kept", consumers="")], "consumers"),
    ("a malformed consumer", [row("MSUF_Kept", consumers="no-line-number")], "consumers"),
    ("no evidence", [row("MSUF_Kept", evidence="")], "evidence"),
    ("an unknown evidence class", [row("MSUF_Kept", evidence="rumour")], "evidence"),
    ("suite evidence with no Suite reader", [row("MSUF_Kept", consumers="MapkoSkin:Core/X.lua:3")], "suite evidence"),
    ("external evidence with only a Suite reader", [row("MSUF_Kept", evidence="external")], "external evidence"),
    ("sv evidence with no SavedVariables entry", [row("MSUF_Kept", evidence="suite,sv")], "sv evidence"),
    ("an unknown client", [row("MSUF_Kept", clients="Mainline,Gizmo")], "clients"),
    ("a duplicate row", [row("MSUF_Kept"), row("MSUF_Kept")], "duplicate"),
    ("unsorted rows", [row("MSUF_Z"), row("MSUF_A")], "sorted"),
    ("an exporter without a line", [row("MSUF_Kept", exporter="MidnightSimpleUnitFrames/A.lua")], "exporter"),
    ("more listed readers than counted", [row("MSUF_Kept", readers="0")], "readers"),
)


def malformed_ledgers(tool):
    base = {"MidnightSimpleUnitFrames/A.lua": 'local ExportPublic = MSUF.ExportPublic\nExportPublic("MSUF_Kept", 1)\n'
            'ExportPublic("MSUF_Z", 1)\nExportPublic("MSUF_A", 1)\n'}
    for label, rows, needle in MALFORMED:
        root = build_tree(base, rows)
        try:
            passed, output = run_check(tool, root)
        finally:
            shutil.rmtree(root, ignore_errors=True)
        expect(not passed, "the check accepted a ledger with " + label)
        expect(needle in output, "the refusal for %s does not say %r:\n%s" % (label, needle, output))
    root = build_tree(base, [row("MSUF_Kept")])
    try:
        path = os.path.join(root, "tools", "public-globals.tsv")
        text = read(path).replace(HEADER, HEADER.replace("clients", "client"))
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        passed, output = run_check(tool, root)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    expect(not passed and "header" in output, "the check accepted a wrong header:\n" + output)


def read(path):
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return handle.read()


def find_lua():
    candidate = os.environ.get("MSUF_LUA") or shutil.which("lua")
    if not candidate or not os.path.exists(candidate):
        fail("no lua on PATH and MSUF_LUA is unset; the Classic gate resolves both")
    banner = subprocess.run([candidate, "-v"], capture_output=True, text=True, errors="replace")
    if not ((banner.stdout or "") + (banner.stderr or "")).strip().startswith("Lua 5.1"):
        fail("lua must be 5.1: " + candidate)
    return candidate


def runtime_smoke_can_fail(tool):
    """The Lua half goes red on a ledger that promises a name no booted client has, or the wrong kind."""
    lua = find_lua()
    ledger = read(os.path.join(ROOT, "tools", "public-globals.tsv")).rstrip("\n")
    ghost = row("MSUF_LedgerFixtureGhost", exporter="MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua:1",
                consumers="FixtureAddon:Core/Reader.lua:42", evidence="external", clients="Mainline")
    # A function ledgered as a table: the name is there but is not what the reader expects.
    wrong = ledger.replace("\nMSUF_SwitchProfile\tfunction\t", "\nMSUF_SwitchProfile\ttable\t", 1)
    expect(wrong != ledger, "the committed ledger no longer carries MSUF_SwitchProfile as a function")
    # The reader the failure has to name is whichever the ledger lists first for it (the readers move).
    first = [line.split("\t")[3].split("|")[0] for line in ledger.splitlines() if line.startswith("MSUF_SwitchProfile\t")][0]
    # A field of an exported table that no client has: the reader gets nil.
    ghost_field = row("MSUF_NS.LedgerFixtureGhostField", kind="nsfield",
                      exporter="MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua:1",
                      consumers="FixtureAddon:Core/Field.lua:7", evidence="external", clients="Mainline")
    cases = (
        ("a name no client exports", ledger + "\n" + ghost, "MSUF_LedgerFixtureGhost", "FixtureAddon:Core/Reader.lua:42"),
        ("a function ledgered as a table", wrong, "MSUF_SwitchProfile", first),
        ("a table field no client has", ledger + "\n" + ghost_field, "MSUF_NS.LedgerFixtureGhostField",
         "FixtureAddon:Core/Field.lua:7"),
    )
    smoke = os.path.join(ROOT, "tools", "tests", "public_globals_smoke.lua")
    for label, text, name, reader in cases:
        handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", prefix="msuf_ledger_", delete=False,
                                             encoding="utf-8", newline="")
        try:
            handle.write(text + "\n")
            handle.close()
            run = subprocess.run([lua, smoke, ROOT.replace("\\", "/"), "Mainline", "--ledger", handle.name],
                                 cwd=ROOT, capture_output=True, text=True, errors="replace")
        finally:
            os.unlink(handle.name)
        output = (run.stdout or "") + (run.stderr or "")
        expect(run.returncode != 0, "the runtime smoke accepted a ledger with " + label)
        expect(name in output and reader in output,
               "the runtime failure for %s must name %s and the reader %s:\n%s" % (label, name, reader, output))


def working_tree_inventory(tool):
    """An unstaged deletion remains in ls-files; scan only the current source on disk."""
    with tempfile.TemporaryDirectory(prefix="msuf-ledger-worktree-") as root:
        addon = os.path.join(root, "MidnightSimpleUnitFrames")
        os.makedirs(addon)
        present, removed = "MidnightSimpleUnitFrames/Live.lua", "MidnightSimpleUnitFrames/Removed.lua"
        with open(os.path.join(root, present), "w", encoding="utf-8") as handle:
            handle.write('ExportPublic("MSUF_WorktreeExport", {})\n')
        listed = SimpleNamespace(returncode=0, stdout=(present + "\0" + removed + "\0").encode("utf-8"))
        with mock.patch.object(tool.subprocess, "run", return_value=listed):
            files = tool.addon_files(root)
            expect(files == [present], "the inventory must omit an unstaged deleted source, retaining existing tracked files")
            exports, _dynamic = tool.static_inventory(root)
        expect("MSUF_WorktreeExport" in exports, "filtering deleted paths lost an existing export")
        expect(len(exports) == 1, "the inventory fabricated exports for a deleted source")


def main():
    started = time.time()
    tool = load_tool()
    working_tree_inventory(tool)
    rows = committed_ledger(tool)
    scanner_mechanisms(tool)
    literals, written, exported = complete_scan(tool)
    check_on_fixtures(tool)
    malformed_ledgers(tool)
    external_reads(tool)
    run_time_names(tool)
    runtime_smoke_can_fail(tool)
    print("public globals ledger smoke: ok (%d ledger rows, %d ExportPublic names and %d compiler-written globals in a "
          "%d-name inventory, %d malformed ledgers refused, %.1fs)"
          % (len(rows), literals, written, exported, len(MALFORMED) + 1, time.time() - started))


if __name__ == "__main__":
    main()
