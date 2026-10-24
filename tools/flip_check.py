"""Fail on new unresolved MSUF globals after the namespace migration.

Bytecode and literal table accesses supply readers on each client's real graph.
The executed core/login and Options boundaries supply actual global providers;
namespace-only registry entries and keep names never supply a global provider.
Reviewed deferred flags/frames require their real publishers on that graph.
The six legacy read occurrences below remain bounded per client and phase.
"""
import argparse
from collections import Counter
import os
from pathlib import Path
import re
import shutil
import subprocess


KNOWN = {
    ("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarPreviewEdit.lua", "MSUF_EditModeSizing", "GETGLOBAL"):
        (2, "Legacy optional sizing flag; neither reader has an exact global writer."),
    ("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua", "MSUF_BossCastbar1", "GETGLOBAL"):
        (1, "Legacy fallback; boss frames are registered dynamically by their pool."),
    ("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua", "MSUF_ArenaCastbar1", "GETGLOBAL"):
        (1, "Legacy fallback; arena frames are registered dynamically by their pool."),
    ("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua", "MSUF_ArenaCastbarPreview1", "GETGLOBAL"):
        (1, "Legacy fallback; arena preview names are constructed by their pool."),
    ("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua", "MSUF_UFPreview_ActiveNudgeBox", "GETGLOBAL"):
        (1, "Legacy optional nudge-box mirror; the namespace preview owner is the fallback."),
}

# These belong to the optional, separately shipped Suite addon. SuiteLink
# deliberately probes their absence; they are not MSUF-owned missing exports.
EXTERNAL_PROVIDERS = {
    "MSUFSuite": "Optional Suite API table, queried with rawget by SuiteLink.",
    "MSUFSuite_ApplyFontsFromMSUF": "Optional legacy Suite font integration.",
}


def tokens(source):
    """Strings are atomic values: their contents cannot invent code/providers."""
    pattern = re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\[(=*)\[.*?\]\2\]|[A-Za-z_]\w*|==|[^\s]''', re.S)
    result = []
    line, previous = 1, 0
    for match in pattern.finditer(source):
        line += source.count("\n", previous, match.start())
        previous = match.start()
        value = match[0]
        if value.startswith("--"):
            continue
        string = value[0] in "\"'" or re.match(r"\[(=*)\[", value)
        # MSUF provider names are ASCII identifiers, so escaped/long strings
        # need no interpretation: none can be mistaken for executable tokens.
        literal = value[1:-1] if value[0] in "\"'" else ""
        result.append((value if not string else "<string>", literal, line))
    return result


def scan_lua(path, relative, luac):
    source = path.read_text(encoding="utf-8-sig")
    code = tokens(source)
    writers, readers = set(), []
    aliases = {"_G"}
    # The addon also uses local G = _G for public table access.
    values = [token[0] for token in code]
    for index in range(len(code) - 3):
        if (values[index] == "local" and values[index + 2:index + 4] == ["=", "_G"]
                and (index + 4 == len(values) or values[index + 4] not in (".", "[", "and", "or", "("))):
            aliases.add(values[index + 1])
    for index, (value, _, line) in enumerate(code):
        tail = values[index:index + 5]
        name, end = "", 0
        if value in aliases:
            if len(tail) >= 3 and tail[1] == ".":
                name, end = tail[2], index + 3
            elif len(tail) >= 4 and tail[1:4] == ["[", "<string>", "]"]:
                name, end = code[index + 2][1], index + 4
        if name.startswith("MSUF"):
            if end < len(values) and values[end] == "=":
                writers.add(name)
            else:
                readers.append((relative, line, name, "_G-read"))
        if value in ("rawset", "rawget") and len(tail) >= 5 and tail[1] == "(" and tail[2] in aliases and tail[3:5] == [",", "<string>"]:
            name = code[index + 4][1]
            if name.startswith("MSUF"):
                if value == "rawset":
                    writers.add(name)
                else:
                    readers.append((relative, line, name, "rawget"))
        if value == "CreateFrame" and len(tail) >= 5 and tail[1:5] == ["(", "<string>", ",", "<string>"]:
            name = code[index + 4][1]
            if name.startswith("MSUF"):
                writers.add(name)
    result = subprocess.run([luac, "-p", "-l", str(path)], capture_output=True, text=True, errors="replace")
    if result.returncode:
        raise RuntimeError(f"{relative}: compiler failed: {result.stderr.strip()}")
    for line in result.stdout.splitlines():
        match = re.search(r"\[(\d+)\]\s+(GETGLOBAL|SETGLOBAL)\s.*;\s*(MSUF\w*)\s*$", line)
        if match:
            if match[2] == "SETGLOBAL":
                writers.add(match[3])
            else:
                readers.append((relative, int(match[1]), match[3], "GETGLOBAL"))
    return writers, readers


def observe(repo, lua, flavor):
    run = subprocess.run([lua, str(repo / "tools/tests/flip_check_exports.lua"), str(repo), flavor],
                         capture_output=True, text=True, errors="replace")
    if run.returncode:
        raise RuntimeError(f"{flavor}: export observation failed: {run.stderr.strip()}")
    phases = {phase: [] for phase in ("core", "Options")}
    exports = {phase: set() for phase in phases}
    capabilities = {}
    for line in run.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) == 3 and fields[0] == "FILE":
            phases[fields[1]].append(fields[2])
        elif len(fields) == 3 and fields[0] == "PROVIDER":
            exports[fields[1]].add(fields[2])
        elif len(fields) == 3 and fields[0] == "CAP":
            capabilities[fields[1]] = fields[2] == 'true'
    if any(not paths for paths in phases.values()):
        raise RuntimeError(f"{flavor}: incomplete export observation")
    return phases, exports, capabilities


def delayed_providers(repo, phases):
    """Reviewed delayed exports: require executable owners AND publication policy.

    These flags are nil until changed by Edit Mode / border-test commands, and
    named unit frames are created at login. No keep name alone is a provider.
    Source fragments pin the actual declaration-to-writer relationship; removing
    an owning module or the publisher invalidates the contract on that client.
    """
    rules = [
        ({"MSUF_ClassPowerContainer"}, {
            "ClassPower/MSUF_CP_Build.lua": ['CreateFrame("Frame", "MSUF_ClassPowerContainer",']}),
        ({"MSUF_UnitEditModeActive"}, {
            "UnitFrames/Engine/MSUF_UF_Preview.lua": [
                'editMode = "MSUF_UnitEditModeActive"', 'local name = MIRRORS[key]', 'ExportPublic(name, value)']}),
        ({"MSUF_InCombat"}, {
            "UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua": ['ExportPublic("MSUF_InCombat", inCombat)']}),
        ({"MSUF_player"}, {
            "UnitFrames/Engine/MSUF_UF_Factory_Spawn.lua": ['ExportPublic(UF.FrameName(unit), frame)'],
            "Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua": ['function UF.FrameName(unit)', 'local prefix = UF.frameNamePrefix or "MSUF"',
                'tostring(prefix) .. "_" .. tostring(unit or "unknown")', '"player", "target"']}),
    ]
    border = "UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"
    for flag in ("Aggro", "Dispel", "Purge"):
        names = {f"MSUF_{flag}BorderTestMode", f"MSUF_{flag}BorderTestScope"}
        rules.append((names, {border: ['ExportPublic(flag, active == true)',
            'ExportPublic(scopeFlag, scope or "shared")',
            f'SetBorderTestMode("MSUF_{flag}BorderTestMode", "MSUF_{flag}BorderTestScope", active, scope)']}))
    rules.append(({"MSUF_BossTargetBorderTestMode"}, {border: [
        'ExportPublic(flag, active == true)', 'SetBorderTestMode("MSUF_BossTargetBorderTestMode", nil, active, "boss")']}))
    bootstrap = (repo / 'MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua').read_text(encoding='utf-8-sig')
    policy = bootstrap.split('BEGIN GENERATED GLOBAL KEEP', 1)[1].split('END GENERATED GLOBAL KEEP', 1)[0]
    policy_names = {a or b for a, b in re.findall(r'\[\s*"([^"\n]+)"\s*\]\s*=\s*true|(\w+)\s*=\s*true', policy)}
    result = {}
    def contains_code(path, fragment):
        source_tokens = [(value, literal) for value, literal, _ in tokens(path.read_text(encoding='utf-8-sig'))]
        required = [(value, literal) for value, literal, _ in tokens(fragment)]
        return any(source_tokens[i:i + len(required)] == required for i in range(len(source_tokens) - len(required) + 1))
    for phase, paths in phases.items():
        result[phase] = set()
        for names, owners in rules:
            if all('MidnightSimpleUnitFrames/' + path in paths and
                   all(contains_code(repo / 'MidnightSimpleUnitFrames' / path, fragment) for fragment in fragments)
                   for path, fragments in owners.items()):
                result[phase].update(names if names == {"MSUF_ClassPowerContainer"} else names & policy_names)
    return result


def audit_client(flavor, phases, exports, scanned, saved=None, delayed=None, unreachable=None):
    """Core readers cannot borrow an Options provider or another client's file."""
    providers = set(EXTERNAL_PROVIDERS) | {"MSUF"}
    failures = 0
    for phase, paths in phases.items():
        providers.update(exports[phase])
        providers.update((saved or {}).get(phase, ()))
        providers.update((delayed or {}).get(phase, ()))
        counts = Counter()
        unresolved = []
        for path in paths:
            for read in scanned[path][1]:
                if (read[0], read[1]) in (unreachable or set()):
                    continue
                if read[2] not in providers:
                    unresolved.append(read)
        for file, line, name, kind in sorted(unresolved):
            key = file, name, kind
            counts[key] += 1
            allowed, reason = KNOWN.get(key, (0, "new unresolved read"))
            known = counts[key] <= allowed
            failures += not known
            print(f"{'KNOWN' if known else 'NEW'} {flavor}/{phase} {file}:{line}: {name} ({kind}) - {reason}")
        print(f"namespace {flavor}/{phase}: {len(providers)} actual providers, {len(unresolved)} unresolved")
    return failures


def audit(repo, luac, lua):
    scanned, failures = {}, 0
    for flavor in ("Mainline", "Vanilla", "TBC", "Mists", "Forever"):
        phases, exports, capabilities = observe(repo, lua, flavor)
        suffix = "Mainline" if flavor == "Forever" else flavor
        saved = {}
        for phase, paths in phases.items():
            addon = "MidnightSimpleUnitFrames" + ("_Options" if phase == "Options" else "")
            text = (repo / addon / f"{addon}_{suffix}.toc").read_text(encoding="utf-8-sig")
            saved[phase] = {name for line in text.splitlines() if line.startswith("## SavedVariables")
                            for name in re.findall(r"\w+", line.split(":", 1)[1])}
            for path in paths:
                if path not in scanned:
                    scanned[path] = scan_lua(repo / path, path, luac)
        delayed = delayed_providers(repo, phases)
        unreachable = set()
        # A literal boolean capability guard can make a reader unreachable on
        # this client. The actual client facts, not a flavor-name guess, decide.
        for paths in phases.values():
            for path in paths:
                source = (repo / path).read_text(encoding='utf-8-sig')
                for block in re.finditer(r'^(?P<indent>[ \t]*)if MSUF\.Client\.(?P<cap>\w+) then[ \t]*\n.*?^(?P=indent)end\b', source, re.M | re.S):
                    if capabilities.get(block['cap']) is False and not re.search(r'^\s*(else|elseif)\b', block[0], re.M):
                        first = source.count('\n', 0, block.start()) + 1
                        last = source.count('\n', 0, block.end()) + 1
                        unreachable.update((path, line) for line in range(first, last + 1))
        failures += audit_client(flavor, phases, exports, scanned, saved, delayed, unreachable)
    print(f"namespace: five clients / core + Options, {failures} new unresolved reads")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--luac", default=os.environ.get("MSUF_LUAC") or shutil.which("luac5.1") or shutil.which("luac"))
    parser.add_argument("--lua", default=os.environ.get("MSUF_LUA") or shutil.which("lua5.1") or shutil.which("lua"))
    args = parser.parse_args()
    if not args.luac or not args.lua:
        parser.error("Lua 5.1 tools required: pass --lua/--luac or set MSUF_LUA/MSUF_LUAC")
    return int(audit(args.repo.resolve(), args.luac, args.lua) != 0)


if __name__ == "__main__":
    raise SystemExit(main())
