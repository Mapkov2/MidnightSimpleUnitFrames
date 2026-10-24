"""Fail on new unresolved MSUF globals after the namespace migration.

Derived from the local flip checker. This is a namespace audit, not a source
pin: bytecode supplies bare reads/writes; literal global table accesses, named
frames, XML names, SavedVariables and the generated export policy add providers.
Only the six reviewed legacy read occurrences below are exempt. Line numbers
are diagnostic only; an additional occurrence of an exempt name still fails.
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
DEFAULT_LUAC = r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\luac.exe"
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


def audit(repo, luac):
    roots = [repo / "MidnightSimpleUnitFrames", repo / "MidnightSimpleUnitFrames_Options"]
    boot = (roots[0] / "Kernel/MSUF_Bootstrap.lua").read_text(encoding="utf-8-sig")
    generated = boot.split("BEGIN GENERATED GLOBAL KEEP", 1)[1].split("END GENERATED GLOBAL KEEP", 1)[0]
    writers = set(EXTERNAL_PROVIDERS)
    writers.update(a or b for a, b in re.findall(r'\[\s*"([^"]+)"\s*\]\s*=\s*true|(\w+)\s*=\s*true', generated))
    readers = []
    for root in roots:
        for toc in sorted(root.glob("*.toc")):
            for line in toc.read_text(encoding="utf-8-sig").splitlines():
                if line.startswith("## SavedVariables"):
                    writers.update(re.findall(r"\w+", line.split(":", 1)[1]))
        for xml in sorted(root.rglob("*.xml")):
            writers.update(re.findall(r'name=[\"\'](MSUF\w*)[\"\']', xml.read_text(encoding="utf-8-sig")))
        for path in sorted(root.rglob("*.lua")):
            found, reads = scan_lua(path, path.relative_to(repo).as_posix(), luac)
            writers.update(found)
            readers.extend(reads)
    unresolved = sorted(read for read in readers if read[2] != "MSUF" and read[2] not in writers)
    counts, failures = Counter(), []
    for file, line, name, kind in unresolved:
        key = file, name, kind
        counts[key] += 1
        allowed, reason = KNOWN.get(key, (0, "new unresolved read"))
        if counts[key] > allowed:
            failures.append((file, line, name, kind))
        print(f"{'KNOWN' if counts[key] <= allowed else 'NEW'} {file}:{line}: {name} ({kind}) - {reason}")
    print(f"namespace: {len(writers)} providers, {len(readers)} reads, {len(unresolved)} unresolved, {len(failures)} new")
    return len(failures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--luac", default=os.environ.get("MSUF_LUAC") or shutil.which("luac") or DEFAULT_LUAC)
    args = parser.parse_args()
    return int(audit(args.repo.resolve(), args.luac) != 0)


if __name__ == "__main__":
    raise SystemExit(main())
