"""Fail on new unresolved MSUF globals after the namespace migration.

Bytecode and literal table accesses supply readers on each client's real graph.
The executed core/login and Options boundaries supply actual global providers;
namespace-only registry entries and keep names never supply a global provider.
Reviewed deferred flags/frames require their real publishers on that graph.
The six legacy read occurrences below remain bounded per client and phase.
"""
import argparse
import hashlib
import json
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
        string = value[0] in "\"'" or (value[0] == "[" and len(value) > 1)
        # MSUF provider names are ASCII identifiers, so escaped/long strings
        # need no interpretation: none can be mistaken for executable tokens.
        literal = value[1:-1] if value[0] in "\"'" else ""
        result.append((value if not string else "<string>", literal, line))
    return result


# Process-local only: source bytes, never mtimes, own the reusable facts. Every
# client and both readiness phases consume the same parse/bytecode inventory.
_SOURCE_CACHE = {}
_FRAGMENT_CACHE = {}


def source_facts(path):
    data = path.read_bytes()
    digest = hashlib.sha256(data).digest()
    if digest not in _SOURCE_CACHE:
        source = data.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
        code = tokens(source)
        spans = []
        for block in re.finditer(r'^(?P<indent>[ \t]*)if MSUF\.Client\.(?P<cap>\w+) then[ \t]*\n.*?^(?P=indent)end\b', source, re.M | re.S):
            if not re.search(r'^\s*(else|elseif)\b', block[0], re.M):
                spans.append((block['cap'], source.count('\n', 0, block.start()) + 1,
                              source.count('\n', 0, block.end()) + 1))
        _SOURCE_CACHE[digest] = {"source": source, "code": code, "values": [token[0] for token in code],
                                 "pairs": [(value, literal) for value, literal, _ in code],
                                 "spans": spans, "compiled": {}, "listings": {}}
    return _SOURCE_CACHE[digest]


def scan_lua(path, relative, luac):
    facts = source_facts(path)
    if luac not in facts["compiled"]:
        facts["compiled"][luac] = scan_facts(path, luac, facts)
    writers, readers = facts["compiled"][luac]
    return writers, [(relative, *row) for row in readers]


def prime_compiler(paths, luac):
    """Amortize compiler startup; luac -p never writes a combined output file."""
    pending, seen = [], set()
    for path in paths:
        facts = source_facts(path)
        if id(facts) not in seen and luac not in facts["compiled"] and luac not in facts["listings"]:
            pending.append((path, facts))
            seen.add(id(facts))
    for offset in range(0, len(pending), 16):
        batch = pending[offset:offset + 16]
        run = subprocess.run([luac, "-p", "-l", *(str(path) for path, _ in batch)],
                             capture_output=True, text=True, errors="replace")
        if run.returncode:
            raise RuntimeError(f"compiler batch failed: {run.stderr.strip()}")
        headers = list(re.finditer(r"^main <(.*):0,0>.*$", run.stdout, re.M))
        listings = {}
        for index, header in enumerate(headers):
            if header[1] == "(luac)":
                continue
            end = headers[index + 1].start() if index + 1 < len(headers) else len(run.stdout)
            listings[Path(header[1]).resolve()] = run.stdout[header.start():end]
        for path, facts in batch:
            if path.resolve() not in listings:
                raise RuntimeError(f"{path}: compiler batch omitted source listing")
            facts["listings"][luac] = listings[path.resolve()]


def scan_facts(path, luac, facts):
    code, values = facts["code"], facts["values"]
    writers, readers = set(), []
    aliases = {"_G"}
    # The addon also uses local G = _G for public table access.
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
                readers.append((line, name, "_G-read"))
        if value in ("rawset", "rawget") and len(tail) >= 5 and tail[1] == "(" and tail[2] in aliases and tail[3:5] == [",", "<string>"]:
            name = code[index + 4][1]
            if name.startswith("MSUF"):
                if value == "rawset":
                    writers.add(name)
                else:
                    readers.append((line, name, "rawget"))
        if value == "CreateFrame" and len(tail) >= 5 and tail[1:5] == ["(", "<string>", ",", "<string>"]:
            name = code[index + 4][1]
            if name.startswith("MSUF"):
                writers.add(name)
    listing = facts["listings"].get(luac)
    if listing is None:
        result = subprocess.run([luac, "-p", "-l", str(path)], capture_output=True, text=True, errors="replace")
        if result.returncode:
            raise RuntimeError(f"{path}: compiler failed: {result.stderr.strip()}")
        listing = result.stdout
    for line in listing.splitlines():
        match = re.search(r"\[(\d+)\]\s+(GETGLOBAL|SETGLOBAL)\s.*;\s*(MSUF\w*)\s*$", line)
        if match:
            if match[2] == "SETGLOBAL":
                writers.add(match[3])
            else:
                readers.append((int(match[1]), match[3], "GETGLOBAL"))
    # Literal registry dependencies are readers too, even when their command
    # never executes during login. Bytecode supplies the containing function
    # spans, so deferred readers are distinguished from chunk-time bindings.
    functions = [(int(a), int(b)) for a, b in re.findall(r"^function <.*:(\d+),(\d+)>", listing, re.M)]
    require_aliases = {"MSUF_Require"}
    assignments = re.compile(r"\blocal\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=\s*"
                             r"(MSUF\s*\.\s*[A-Za-z_]\w*(?:\s*,\s*MSUF\s*\.\s*[A-Za-z_]\w*)*)(?!\w|\s*[.(\[])")
    for assignment in assignments.finditer(" ".join(values)):
        names = [name.strip() for name in assignment[1].split(",")]
        for name, expression in zip(names, assignment[2].split(",")):
            if re.sub(r"\s+", "", expression) == "MSUF.Require":
                require_aliases.add(name)
    closing, stack = {}, []
    for index, value in enumerate(values):
        if value in ("(", "{", "["):
            stack.append(index)
        elif value in (")", "}", "]") and stack:
            closing[stack.pop()] = index
    for index, (value, _, line) in enumerate(code):
        direct = value == "Require" and values[max(0, index - 2):index] == ["MSUF", "."]
        if not (direct or value in require_aliases) or values[index + 1:index + 3] != ["(", "<string>"]:
            continue
        # Explicit third-argument namespaces have their own exact-key contract;
        # they must not borrow a provider from the default registry inventory.
        end = closing[index + 1]
        commas, position = 0, index + 2
        while position < end:
            token = values[position]
            if token == ",": commas += 1
            position = closing[position] + 1 if position in closing else position + 1
        if commas > 1:
            continue
        phase = "deferred" if any(first <= line <= last for first, last in functions) else "load"
        following = values[end + 1:end + 2]
        expected = "function" if following == ["("] else "table" if following in (["."], ["["]) else "function|table"
        readers.append((line, code[index + 2][1], "Require/" + phase, expected))
    return writers, readers


def observe(repo, lua, flavor, drop_provider=None):
    run = subprocess.run([lua, str(repo / "tools/tests/flip_check_exports.lua"), str(repo), flavor] + ([drop_provider] if drop_provider else []),
                         capture_output=True, text=True, errors="replace")
    if run.returncode:
        raise RuntimeError(f"{flavor}: export observation failed: {run.stderr.strip()}")
    phases = {phase: [] for phase in ("core", "Options")}
    exports = {phase: set() for phase in phases}
    capabilities = {}
    registry = {phase: {} for phase in phases}
    for line in run.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) == 3 and fields[0] == "FILE":
            phases[fields[1]].append(fields[2])
        elif len(fields) == 3 and fields[0] == "PROVIDER":
            exports[fields[1]].add(fields[2])
        elif len(fields) == 6 and fields[0] == "REGISTRY":
            registry[fields[1]][fields[2]] = {"type": fields[3], "file": fields[4], "phase": fields[5]}
        elif len(fields) == 3 and fields[0] == "CAP":
            capabilities[fields[1]] = fields[2] == 'true'
    if any(not paths for paths in phases.values()):
        raise RuntimeError(f"{flavor}: incomplete export observation")
    return phases, exports, capabilities, registry


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
    bootstrap = source_facts(repo / 'MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua')['source']
    policy = bootstrap.split('BEGIN GENERATED GLOBAL KEEP', 1)[1].split('END GENERATED GLOBAL KEEP', 1)[0]
    policy_names = {a or b for a, b in re.findall(r'\[\s*"([^"\n]+)"\s*\]\s*=\s*true|(\w+)\s*=\s*true', policy)}
    result = {}
    def contains_code(path, fragment):
        source_tokens = source_facts(path)["pairs"]
        if fragment not in _FRAGMENT_CACHE:
            _FRAGMENT_CACHE[fragment] = [(value, literal) for value, literal, _ in tokens(fragment)]
        required = _FRAGMENT_CACHE[fragment]
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
                if read[3].startswith("Require/") or (read[0], read[1]) in (unreachable or set()):
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


def audit_required(flavor, phases, registry, scanned, unreachable=None):
    """Type-checked required providers at the client/phase readiness boundary."""
    failures, inventory = 0, []
    for phase, paths in phases.items():
        for path in paths:
            for file, line, name, kind, *expected in scanned[path][1]:
                if not kind.startswith("Require/") or (file, line) in (unreachable or set()):
                    continue
                deferred = kind == "Require/deferred"
                ready = "Options" if deferred or phase == "Options" else "core"
                provider = registry.get(ready, {}).get(name) or registry.get("core", {}).get(name)
                types = (expected or ["function|table"])[0]
                valid = provider and provider["type"] in types.split("|")
                if not valid:
                    failures += 1
                    print(f"NEW {flavor}/{phase} {file}:{line}: {name} ({kind}) - missing/wrong-type registry provider at {ready}")
                inventory.append({"client": flavor, "reader": file, "line": line, "name": name,
                                  "readerPhase": phase, "binding": "deferred" if deferred else "load",
                                  "readiness": ready, "expectedType": types, "provider": provider})
    print(f"required registry {flavor}: {len(inventory)} readers, {failures} invalid providers")
    return failures, inventory


def audit(repo, luac, lua, inventory_path=None):
    scanned, failures, required_inventory = {}, 0, []
    observed = {flavor: observe(repo, lua, flavor) for flavor in ("Mainline", "Vanilla", "TBC", "Mists", "Forever")}
    paths = dict.fromkeys(path for phases, _, _, _ in observed.values() for paths in phases.values() for path in paths)
    prime_compiler([repo / path for path in paths], luac)
    for flavor, (phases, exports, capabilities, registry) in observed.items():
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
                for capability, first, last in source_facts(repo / path)["spans"]:
                    if capabilities.get(capability) is False:
                        unreachable.update((path, line) for line in range(first, last + 1))
        failures += audit_client(flavor, phases, exports, scanned, saved, delayed, unreachable)
        invalid, required = audit_required(flavor, phases, registry, scanned, unreachable)
        failures += invalid
        required_inventory.extend(required)
    if inventory_path:
        inventory_path.write_text(json.dumps({"version": 1, "readers": required_inventory}, indent=2) + "\n", encoding="utf-8")
    print(f"namespace: five clients / core + Options, {failures} new unresolved reads")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--luac", default=os.environ.get("MSUF_LUAC") or shutil.which("luac5.1") or shutil.which("luac"))
    parser.add_argument("--lua", default=os.environ.get("MSUF_LUA") or shutil.which("lua5.1") or shutil.which("lua"))
    parser.add_argument("--inventory", type=Path, help="write required registry providers by client, reader/readiness phase and type")
    args = parser.parse_args()
    if not args.luac or not args.lua:
        parser.error("Lua 5.1 tools required: pass --lua/--luac or set MSUF_LUA/MSUF_LUAC")
    return int(audit(args.repo.resolve(), args.luac, args.lua, args.inventory) != 0)


if __name__ == "__main__":
    raise SystemExit(main())
