"""Generate the active Kernel global keep policy from reviewed contracts.

Uses the existing public-globals inventory and reviewed integration ledger. Suite
reads come from a pinned consumer contract, never an external working checkout. --write installs generated data in Bootstrap;
--consumers PATH records compiler-proven bare reads outside the keep list.
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
# Reviewed owner-facing contracts that must remain addressable in _G.
REVIEWED_GLOBALS = {
    "MSUF_MAX_ARENA_FRAMES": "pre-Kernel client fact; Unit page bare reader",
    "MSUF_ExportExternal": "documented Wago profile API (State/MSUF_Profiles.lua)",
    "MSUF_ImportExternal": "documented Wago profile API (State/MSUF_Profiles.lua)",
}
# These are live variables, not callable exports: PLAN-10 requires bare reads.
RUNTIME_FLAGS = (
    "MSUF_InCombat",
    # Border test modes: ExportPublic writers, read bare by Borders.lua and the Global/GlobalBars pages.
    "MSUF_AggroBorderTestMode", "MSUF_AggroBorderTestScope",
    "MSUF_DispelBorderTestMode", "MSUF_DispelBorderTestScope",
    "MSUF_PurgeBorderTestMode", "MSUF_PurgeBorderTestScope",
    "MSUF_BossTargetBorderTestMode", "MSUF_BossTargetBorderTestScope",
)


def read(path):
    return Path(path).read_text(encoding="utf-8-sig")


def policy(root=ROOT):
    text = read(root / BOOTSTRAP)
    if "local GlobalExports = MSUF.Compat.GlobalKeep" in text:
        names = {name: True for name in generated_names(text)}
        names.update((name, True) for name in pending_page_names(text))
        return names, ()
    raise ValueError("Kernel publication policy is not the generated keep list")


def generated_names(text):
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    names = set(re.findall(r'\["([^"\n]+)"\]\s*=\s*true', block))
    names.update(re.findall(r"^\s*([A-Za-z_]\w*)\s*=\s*true", block, re.M))
    if not names:
        raise ValueError("generated Kernel keep data is empty")
    return names


def pending_page_names(text):
    """Temporary page globals awaiting their readers; none remain since 2026-10-24."""
    if "local PendingPageGlobals = {" not in text:
        return set()
    block = text.split("local PendingPageGlobals = {", 1)[1].split("\n}", 1)[0]
    return set(re.findall(r"^\s*([A-Za-z_]\w*)\s*=\s*true", block, re.M))


def native_dynamic_names(root):
    """Finite native frame names; validate the actual name domains, not line numbers."""
    nudge = "MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Layout_Nudge.lua"
    text = read(root / nudge)
    block = re.search(r"local NUDGE_DIRS = \{([^\n]+)\}", text)
    if not block or 'SetOverrideBindingClick(owner, false, dir, "MSUF_EM2_Nudge" .. dir)' not in text:
        raise ValueError("Nudge binding name contract changed")
    dirs = re.findall(r'\{\s*"([A-Z]+)"\s*,', block.group(1))
    if set(dirs) != {"UP", "DOWN", "LEFT", "RIGHT"} or len(dirs) != 4:
        raise ValueError("Nudge button name domain changed")
    group = "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua"
    pad = "MidnightSimpleUnitFrames/Game/Forever/PadEditMode.lua"
    text = read(root / group)
    block = text.split("local KIND_TO_KEY = {", 1)[1].split("\n}", 1)[0]
    kinds = set(re.findall(r'^\s*(\w+)\s*=\s*"gf_\w+"', block, re.M))
    pad_text = read(root / pad)
    pad_block = re.search(r"local GROUP_CONTAINERS = \{([^\n]+)\}", pad_text)
    if (not pad_block or kinds != set(re.findall(r'"(\w+)"', pad_block.group(1)))
            or '_G["MSUF_GF_Container_" .. GROUP_CONTAINERS[index]]' not in pad_text):
        raise ValueError("Forever gamepad container name domain changed")
    return {
        (nudge, "MSUF_EM2_Nudge", "btnName"): (
            {"MSUF_EM2_Nudge" + direction for direction in dirs}, "native SetOverrideBindingClick target"),
        (group, "MSUF_GF_Container_", "kind"): (
            {"MSUF_GF_Container_" + kind for kind in kinds}, "Forever gamepad named container reader"),
    }


def documented_run_names(root, exports):
    paths = [root / rel for rel in ledger.addon_files(str(root))]
    paths += list(root.glob("*.md")) + list((root / "docs").rglob("*.md"))
    names = set(RUN_COMMANDS)
    for path in paths:
        for line in read(path).splitlines():
            command = re.search(r"/run\s+(.+)", line)
            if command:
                names.update(set(re.findall(ledger.NAME, command.group(1))) & set(exports))
    return names


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


def consumer_contract(path):
    contract = json.loads(read(path))
    if (contract.get("version") != 1 or not re.fullmatch(r"[0-9a-f]{40}", contract.get("commit", ""))
            or not re.fullmatch(r"[0-9a-f]{64}", contract.get("snapshotSha256", ""))):
        raise ValueError("invalid pinned Suite revision/snapshot")
    for key in ("names", "prefixes"):
        values = contract.get(key)
        if (not isinstance(values, list) or values != sorted(set(values))
                or any(not isinstance(name, str) or not re.fullmatch(ledger.NAME, name) for name in values)):
            raise ValueError("invalid Suite consumer " + key)
    return contract


def check_policy(root, block):
    text = read(root / BOOTSTRAP)
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError("generated Kernel policy markers missing or duplicated")
    actual = text[text.index(BEGIN):text.index(END) + len(END)]
    if actual != block:
        raise ValueError("generated Kernel keep policy is stale; review contracts and regenerate")


def keep_inventory(root=ROOT, contract_path=None):
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

    contract = consumer_contract(contract_path or root / "tools/global_keep_consumers.json")
    for name in contract["names"]:
        if name in exports:
            keep(name, "Suite reader")
    for prefix in contract["prefixes"]:
        if prefix in ("MSUF_", "MSUF", "MSUF_GF_"):
            continue
        for name in exports:
            if name.startswith(prefix):
                keep(name, "Suite dynamic " + prefix)
    for name in documented_run_names(root, exports):
        keep(name, "documented /run")
    for names, reason in native_dynamic_names(root).values():
        for name in names:
            keep(name, reason)
    for name in RUNTIME_FLAGS:
        keep(name, "bare runtime flag")
    for name, reason in REVIEWED_GLOBALS.items():
        keep(name, reason)
    return dict(sorted(reasons.items())), exports, dynamic


def generated_block(reasons):
    lines = [BEGIN, "-- Active ExportPublic policy; regenerate from reviewed contracts.",
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
    leaving = set(exports) - set(keep)
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
    parser.add_argument("--consumer-contract", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    parser.add_argument("--consumers", type=Path)
    args = parser.parse_args()
    args.root = args.root.resolve()
    try:
        reasons, exports, _ = keep_inventory(args.root, args.consumer_contract)
        block = generated_block(reasons)
        if args.check:
            check_policy(args.root, block)
        elif args.write:
            write_policy(args.root, block)
        else:
            print(block)
        print("Generated keep: %d names; active ExportPublic policy" % len(reasons))
        if args.consumers:
            leaving, reads = consumers(args.root, reasons, exports, args.consumers)
            print("Non-keep exports: %d names; %d bare reader locations -> %s" %
                  (leaving, reads, args.consumers))
    except (ValueError, OSError, ET.ParseError, ledger.LedgerError) as error:
        parser.exit(1, "global keep FAILED: %s\n" % error)


if __name__ == "__main__":
    main()
