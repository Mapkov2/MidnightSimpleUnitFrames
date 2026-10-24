"""Generate the staged Kernel global keep policy; never change the active policy.

Uses the existing public-globals inventory and reviewed integration ledger. Suite
sources are scanned read-only. --write installs generated data in Bootstrap;
--consumers PATH records compiler-proven bare reads that block the later flip.
No addon code is executed and no git state is written.
"""

import argparse
import collections
import csv
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import public_globals_ledger as ledger
import quality_ratchet as ratchet

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = "MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"
BEGIN = "-- BEGIN GENERATED GLOBAL KEEP: tools/gen_global_keep.py"
END = "-- END GENERATED GLOBAL KEEP"
RUN_COMMANDS = ("MSUF_ShowWelcomeMessage", "MSUF_ShowClientVersionWarning")
# These are live variables, not callable exports: PLAN-10 requires bare reads.
RUNTIME_FLAGS = ("MSUF_InCombat",)


def read(path):
    return Path(path).read_text(encoding="utf-8-sig")


def policy(root=ROOT):
    text = read(root / BOOTSTRAP)
    block = text.split("local GlobalExports = {", 1)[1].split("\n}", 1)[0]
    names = dict((name, value == "true") for name, value in
                 re.findall(r'\["([^"\n]+)"\]\s*=\s*(true|false)', block))
    block = text.split("local GlobalExportPrefixes = {", 1)[1].split("\n}", 1)[0]
    return names, tuple(re.findall(r'"([^"\n]+)"', block))


def allowed(name, names, prefixes):
    return names.get(name, name.startswith(prefixes))


def active_exports(exports, names, prefixes):
    """Direct writes/named frames bypass ExportPublic's compatibility policy."""
    direct = {"assign", "function", "global", "frame", "toc", "native"}
    return {name for name, entry in exports.items()
            if any(site[3] in direct or (site[3] == "export" and allowed(name, names, prefixes))
                   for site in entry.sites)}


def augment_inventory(root, exports, dynamic):
    """Include other-client TOCs and reviewed finite native/dynamic names."""
    rows, problems = ledger.parse_ledger(str(root / "tools/public-globals.tsv"))
    if problems:
        raise ValueError("; ".join(problems))
    for rel in ledger.addon_files(str(root)):
        if rel.endswith(".toc"):
            ledger.scan_toc(rel, read(root / rel), exports)
    for row in rows:
        name = row["name"]
        if row["kind"] in ("nsfield", "dynamic"):
            continue
        native = name.startswith(("BINDING_", "SLASH_")) or row["kind"] == "savedvar"
        if native:
            entry = exports.setdefault(name, ledger.Entry(name))
            entry.add(8, row["exporter"], 0, "native", row["kind"])
        for rel, families in dynamic.items():
            for family in families:
                if family.via in ("assign", "frame", "export") and family.matches(name):
                    entry = exports.setdefault(name, ledger.Entry(name))
                    entry.add(8, rel, family.line, family.via, row["kind"])
    return rows


def shipped_lua(root=ROOT):
    """Every client's expanded graph, plus auto-discovered XML/Bindings files."""
    names, sections, current, expected_count, count = set(), set(), None, 0, 0
    for line in read(root / "tools/load-graph.lock").splitlines() + ["@ END"]:
        if line.startswith("@ "):
            if current is not None and count != expected_count:
                raise ValueError("incomplete load graph section: " + repr(current))
            if line == "@ END":
                break
            match = re.fullmatch(r"@ (\w+) (\w+) \((\d+) files\)", line)
            if not match:
                raise ValueError("invalid load graph section: " + line)
            current = match.group(1), match.group(2)
            if current in sections:
                raise ValueError("duplicate load graph section: " + repr(current))
            sections.add(current)
            expected_count, count = int(match.group(3)), 0
        elif line.startswith(("MidnightSimpleUnitFrames/", "MidnightSimpleUnitFrames_Options/")):
            if current is None or not (root / line).is_file():
                raise ValueError("unplaced/missing shipped file: " + line)
            names.add(line)
            count += 1
    with (root / "tools/classic-client-matrix.tsv").open(encoding="utf-8-sig", newline="") as handle:
        clients = {row["Suffix"] for row in csv.DictReader(handle, delimiter="\t")}
    # Locales are a pseudo-addon section expanded separately by load-graph.lua.
    addons = (*ledger.ADDONS, "MidnightSimpleUnitFrames_Locales")
    expected = {(client, addon) for client in clients | {"Forever"} for addon in addons}
    if sections != expected or not names:
        raise ValueError("incomplete client/addon load graph")
    return sorted(name for name in names if name.endswith(".lua"))


def keep_inventory(root=ROOT, suite=Path(ledger.DEFAULT_SUITE_REPO)):
    exports, dynamic = ledger.static_inventory(str(root))
    rows = augment_inventory(root, exports, dynamic)
    reasons = collections.defaultdict(set)

    def keep(name, reason):
        reasons[name].add(reason)

    # Every TOC matters, including a client-only SavedVariables declaration.
    contracts = {}
    for rel in ledger.addon_files(str(root)):
        if rel.endswith(".toc"):
            ledger.scan_toc(rel, read(root / rel), contracts)
        elif rel.endswith(".xml"):
            ledger.scan_xml(rel, read(root / rel), contracts)
            # XML attributes may use either quote and arbitrary whitespace;
            # script bodies can read globals without a function= attribute.
            tree = ET.fromstring(read(root / rel))
            for element in tree.iter():
                for attr in ("function", "mixin", "secureMixin", "parent", "relativeTo", "inherits"):
                    for name in re.findall(ledger.NAME, element.get(attr, "")):
                        if name in exports:
                            keep(name, "XML reference")
                if element.tag.rsplit("}", 1)[-1] in ("Binding",) or element.tag.rsplit("}", 1)[-1].startswith("On"):
                    code, _ = ratchet.strip_source(element.text or "")
                    for name in set(re.findall(r"(?<![\w.:])([A-Za-z_]\w*)", code)) & set(exports):
                        keep(name, "XML script")
    for name, entry in contracts.items():
        # Binding action IDs are not Lua globals. Their handler calls are.
        if entry.kinds == {"binding"}:
            continue
        if "savedvar" in entry.kinds or entry.contract:
            keep(name, "SavedVariables" if "savedvar" in entry.kinds else "XML/TOC contract")
    for name in exports:
        if name.startswith(("SLASH_", "BINDING_")):
            keep(name, "native slash/binding")

    # Preserve exact documented contracts. A diagnostic wildcard (MSUF_*) is
    # not an API name and must not retain every private export by accident.
    for row in rows:
        if row["kind"] in ("nsfield", "dynamic"):
            continue
        if row["kind"] == "binding" and not row["name"].startswith("BINDING_"):
            continue
        keep(row["name"], "reviewed " + ",".join(row["evidence"]))

    if not suite.is_dir():
        raise ValueError("Suite source missing: " + str(suite))
    # Existing scanner handles bare GETGLOBAL, _G aliases, rawget/getglobal,
    # quoted dispatch names and dynamic prefixes, without confusing nsfields.
    sources = list(ledger.repo_sources(str(suite)))
    if not sources or not any(source.addon == "MSUF_Suite" for source in sources):
        raise ValueError("Suite addon sources missing: " + str(suite))
    scan = ledger.scan_external(sources, set(exports), set(), ratchet.find_luac())
    if scan.unparsed:
        raise ValueError("Suite files did not compile: " + repr(scan.unparsed))
    for name in scan.readers:
        if name in exports:
            keep(name, "Suite reader")
    for prefix in scan.prefixes:
        # Bare MSUF_ strings are frequently labels, not an addressable family.
        if prefix in ("MSUF_", "MSUF", "MSUF_GF_"):
            continue
        for name in exports:
            if name.startswith(prefix):
                keep(name, "Suite dynamic " + prefix)
    for name in RUN_COMMANDS:
        keep(name, "documented /run")
    for name in RUNTIME_FLAGS:
        keep(name, "bare runtime flag")
    return dict(sorted(reasons.items())), exports, dynamic


def generated_block(reasons):
    lines = [BEGIN, "-- Staged data only: the director switches GlobalExports after consumers move.",
             "MSUF.Compat.GlobalKeep = {"]
    for name, why in reasons.items():
        for reason in sorted(why):
            lines.append("    -- " + reason)
        field = name if re.fullmatch(ledger.NAME, name) else "[%s]" % json.dumps(name)
        lines.append("    %s = true," % field)
    lines += ["}", END]
    return "\n".join(lines)


def write_policy(root, block):
    path = root / BOOTSTRAP
    data = path.read_bytes()
    text = data.decode("utf-8").replace("\r\n", "\n")
    if BEGIN in text:
        start, end = text.index(BEGIN), text.index(END) + len(END)
        text = text[:start] + block + text[end:]
    else:
        anchor = "-- Global compatibility names used by shipped readers and integrations."
        if text.count(anchor) != 1:
            raise ValueError("Kernel policy insertion point missing")
        text = text.replace(anchor, block + "\n\n" + anchor)
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def lane(rel):
    parts = rel.split("/")
    if parts[0].endswith("_Options"):
        if "Preview" in parts:
            return "C2"
        if "Pages" in parts:
            return "P1-P3"
        return "S5"
    if "State" in parts:
        return "C1"
    if "GroupFrames" in parts or "Preview" in parts:
        return "C2"
    if "Auras3" in parts or "Game" in parts:
        return "S2"
    if "UnitFrames" in parts or "Libs" in parts:
        return "S1"
    if any(part in parts for part in ("Castbars", "ClassPower", "Runtime")):
        return "S3"
    return "S4"


def consumers(root, keep, exports, output):
    names, prefixes = policy(root)
    leaving = active_exports(exports, names, prefixes) - set(keep)
    paths = [str(root / rel) for rel in shipped_lua(root)]
    reads = ledger.global_reads(ratchet.find_luac(), paths)
    records = set()
    for path, found in reads.items():
        if found is None:
            raise ValueError("Cannot inventory bare global reads: " + path)
        rel = Path(path).relative_to(root).as_posix()
        records.update((rel, line, name, lane(rel)) for name, line in found if name in leaving)
    output.parent.mkdir(parents=True, exist_ok=True)
    text = "file\tline\tname\towning lane\n" + "".join(
        "%s\t%d\t%s\t%s\n" % row for row in sorted(records))
    output.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
    return len(leaving), len(records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--suite", type=Path, default=Path(ledger.DEFAULT_SUITE_REPO))
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--consumers", type=Path)
    args = parser.parse_args()
    args.root = args.root.resolve()
    try:
        reasons, exports, _ = keep_inventory(args.root, args.suite)
        block = generated_block(reasons)
        if args.write:
            write_policy(args.root, block)
        else:
            print(block)
        print("Generated keep: %d names; active policy unchanged" % len(reasons))
        if args.consumers:
            leaving, reads = consumers(args.root, reasons, exports, args.consumers)
            print("Pending global removal: %d names; %d bare reader locations -> %s" %
                  (leaving, reads, args.consumers))
    except (ValueError, OSError, ET.ParseError, ledger.LedgerError) as error:
        parser.exit(1, "global keep FAILED: %s\n" % error)


if __name__ == "__main__":
    main()
