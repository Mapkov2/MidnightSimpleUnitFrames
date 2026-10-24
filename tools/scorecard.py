"""PLAN-10 scorecard, source-only: no Lua execution, compiler or git writes.

Reuses quality_ratchet's file selection, source metrics, wrapper rules and clone
hashes. Function spans are parsed statically instead of invoking luac. Hot-path
functions require the exact PLAN-10 comment immediately above their header.
Clone exceptions additionally require tools/scorecard_clones.tsv rows with
file, start, end, reason (inclusive source lines); every exempt occurrence must
be wholly inside an annotated hot function. Missing/invalid data fails closed.
Dynamic ExportPublic families are bounded by the closed generated keep policy.
Native Nudge and Forever container names use gen_global_keep source domains.
Other finite dynamic global families require reviewed tools/scorecard_global_families.tsv
rows: file, line, prefix, suffix, source_sha256 (normalized LF source), names
(a JSON array of exact names), reason. Source/family changes invalidate the row.

settingKey coverage requires current generated menu indexes and schema provenance
from tools/menu_schema_coverage.json (version 1). Its indexes object maps relative
index paths to sourceSha256, blobSha256, records, unindexedRecords,
allSettingsCaptured=true and settingControlCount. Each setting identity has
exactly one record: identity, controlId, settingKey, schemaId, schemaSettingPath,
schemaKind, scope, applyDomain. Capture all setting controls before search
filtering; unindexedRecords holds those omitted from the search blob. The
projection must inspect actual widget schema declarations; search metadata
alone cannot establish schema coverage. No in-game rendering proof is claimed.
"""

import argparse
import bisect
import collections
import csv
import hashlib
import json
import re
import time
from pathlib import Path

import gen_global_keep as keep
import public_globals_ledger as ledger
import quality_ratchet as ratchet

ROOT = Path(__file__).resolve().parents[1]
HOT = "-- hot path: kept whole (perf rule)"
BLOCKS = re.compile(r"\b(function|if|for|while|do|repeat|end|until)\b")
SETTING_KINDS = {"toggle", "checkbox", "slider", "dropdown", "segment", "color", "textinput", "editbox", "input"}


def source_functions(code):
    """Lua block/function spans in luac preorder, with the same Fn interface.

    Strings/comments have already been removed by quality_ratchet. 'do' belongs
    to its for/while block, whereas standalone do and repeat own their end.
    No estimates of compiler locals/upvalues/slots are made here.
    """
    code = code.replace('"function"', '""')
    newlines = [match.start() for match in re.finditer("\n", code)]
    functions = [{"start": 0, "end": 0, "kids": 0}]
    stack, owners = [], [0]
    for match in BLOCKS.finditer(code):
        word = match.group(0)
        line = bisect.bisect_left(newlines, match.start()) + 1
        if word == "function":
            functions[owners[-1]]["kids"] += 1
            index = len(functions)
            functions.append({"start": line, "end": None, "kids": 0})
            owners.append(index)
            stack.append([word, index])
        elif word in ("if", "for", "while", "repeat"):
            stack.append([word, word in ("for", "while")])
        elif word == "do":
            if stack and stack[-1][0] in ("for", "while") and stack[-1][1]:
                stack[-1][1] = False
            else:
                stack.append([word, False])
        else:
            if not stack:
                raise ValueError("unmatched %s at line %d" % (word, line))
            kind, value = stack.pop()
            if (word == "until") != (kind == "repeat"):
                raise ValueError("mismatched %s at line %d" % (word, line))
            if kind == "function":
                functions[value]["end"] = line
                owners.pop()
    if stack:
        raise ValueError("unclosed Lua blocks")
    return [ratchet.Fn(fn["start"], fn["end"], 0, 0, 0, fn["kids"]) for fn in functions]


def hot_ranges(text, funcs):
    lines = text.splitlines()
    return [(fn.start, fn.end) for fn in funcs[1:]
            if fn.start > 1 and lines[fn.start - 2].strip() == HOT]


def clone_exceptions(root):
    path = root / "tools/scorecard_clones.tsv"
    if not path.exists():
        return {}
    found = collections.defaultdict(list)
    with path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            start, end = int(row["start"]), int(row["end"])
            if start < 1 or end < start or not row["reason"].strip():
                raise ValueError("invalid clone exception: " + repr(row))
            found[row["file"]].append((start, end))
    return found


def covered(start, end, ranges):
    return any(first <= start and end <= last for first, last in ranges)


def measure(root):
    profile = ratchet.PROFILES["classic"]
    allowlist = ratchet.load_json(root / "tools" / ratchet.ALLOWLIST_NAME, {})
    rels, _ = ratchet.product_files(root, profile, ratchet.declared_data(root, "classic", allowlist))
    totals, locations, hot = collections.Counter(), collections.defaultdict(list), {}
    function_ranges = {}
    details, unexcepted_long, long_total = [], 0, 0
    for rel in rels:
        text = keep.read(root / rel)
        code, plain = ratchet.strip_source(text)
        metrics = {
            "lines": text.count("\n") + (0 if text.endswith("\n") or not text else 1),
            "client_guards": len(ratchet.client_guard_offsets(code)),
            "fallback_lambdas": len(ratchet.fallback_lambda_offsets(code)),
            "semicolon_lines": ratchet.semicolon_lines(code),
            "long_lines": sum(len(line) > ratchet.LONG_LINE for line in text.split("\n")),
        }
        normalized = [(number, ratchet.WHITESPACE.sub(" ", line.strip()))
                      for number, line in enumerate(plain.split("\n"), 1)]
        normalized = [(number, line) for number, line in normalized
                      if len(line) > 3 and line not in ratchet.TRIVIAL]
        hashes = ratchet.window_hashes([line for _, line in normalized])
        totals.update(metrics)
        funcs = source_functions(code)
        _, wrappers, _ = ratchet.function_shape(funcs, code, metrics["lines"], profile["function_limit"])
        hot[rel] = hot_ranges(text, funcs)
        function_ranges[rel] = [(fn.start, fn.end) for fn in funcs[1:]]
        parents = ratchet.tree_parents(funcs)
        modules = {0}
        wrapper_indexes = ratchet.find_wrappers(funcs, parents, code, metrics["lines"])
        modules.update(wrapper_indexes)
        for index, fn in enumerate(funcs):
            if index in modules:
                continue
            if ratchet.span_of(fn) > profile["function_limit"]:
                long_total += 1
                if (fn.start, fn.end) not in hot[rel]:
                    unexcepted_long += 1
                    details.append("long function %s:%d-%d" % (rel, fn.start, fn.end))
        for start, end, _, _, _, own, _ in wrappers:
            if own > profile["function_limit"]:
                long_total += 1
                if (start, end) not in hot[rel]:
                    unexcepted_long += 1
                    details.append("long module body %s:%d-%d" % (rel, start, end))
        # Map the ratchet's normalized clone windows back to source lines.
        source_lines = [number for number, _ in normalized]
        for index, digest in enumerate(hashes):
            locations[digest].append((rel, source_lines[index], source_lines[index + ratchet.WINDOW - 1]))
    exceptions = clone_exceptions(root)
    clones = unexcepted_clones = 0
    used = set()
    for places in locations.values():
        if len(places) < 2:
            continue
        for rel, start, end in places:
            clones += 1
            containing = [(last - first, first, last) for first, last in function_ranges[rel]
                          if first <= start and end <= last]
            owner = min(containing)[1:] if containing else None
            if covered(start, end, exceptions.get(rel, ())) and owner in hot[rel]:
                used.add(rel)
            else:
                unexcepted_clones += 1
    for rel, ranges in exceptions.items():
        if rel not in hot or rel not in used or any(not covered(a, b, hot[rel]) for a, b in ranges):
            raise ValueError("unused or non-hot clone exception: " + rel)
    return totals, long_total, unexcepted_long, clones, unexcepted_clones, details


def global_counts(root):
    names, prefixes = keep.policy(root)
    text = keep.read(root / keep.BOOTSTRAP)
    if keep.BEGIN not in text or keep.END not in text:
        raise ValueError("generated Kernel keep data missing; run tools/gen_global_keep.py --write")
    target = keep.generated_names(text)
    pending = keep.pending_page_names(text)
    native_families = keep.native_dynamic_names(root)
    exports, dynamic = ledger.static_inventory(str(root))
    keep.augment_inventory(root, exports, dynamic)
    active = keep.active_exports(exports, names, prefixes)
    # A static scan cannot enumerate arbitrary runtime suffixes. Never present
    # these as an exact count or let an unresolved publication family pass.
    reviewed = {}
    path = root / "tools/scorecard_global_families.tsv"
    if path.exists():
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle, delimiter="\t"):
                key = row["file"], int(row["line"]), row["prefix"], row["suffix"]
                values = json.loads(row["names"])
                digest = hashlib.sha256(keep.read(root / row["file"]).encode("utf-8")).hexdigest()
                if (key in reviewed or not row["reason"].strip() or row["source_sha256"] != digest
                        or not isinstance(values, list) or not values
                        or any(not isinstance(name, str) or not name or "*" in name for name in values)
                        or len(set(values)) != len(values)
                        or any(not name.startswith(row["prefix"]) or not name.endswith(row["suffix"]) for name in values)):
                    raise ValueError("invalid/stale dynamic global family: " + repr(key))
                reviewed[key] = values
    unresolved, used = [], set()
    for rel, families in dynamic.items():
        for family in families:
            if (family.passthrough or family.via not in ("assign", "frame", "export")
                    or not (family.prefix or family.suffix)):
                continue
            if family.via == "export" and not prefixes:
                # A dynamic ExportPublic call is bounded by the exact generated
                # allowlist. Namespace-only families publish zero global names.
                active.update(name for name, allowed in names.items() if allowed and family.matches(name))
                continue
            native = native_families.get((rel, family.prefix, family.expr))
            if native and family.via == "frame" and not family.suffix:
                active.update(native[0])
                continue
            key = rel, family.line, family.prefix, family.suffix
            if key not in reviewed:
                unresolved.append((rel, family.line, family.describe()))
            else:
                used.add(key)
                active.update(name for name in reviewed[key]
                              if family.via != "export" or keep.allowed(name, names, prefixes))
    if set(reviewed) != used:
        raise ValueError("unused dynamic global family review")
    return len(active), len(target), len(pending), sorted(active - target - pending), unresolved


def menu_coverage(root):
    menu = root / "MidnightSimpleUnitFrames_Options/Shell/Menu2"
    index_names = ("Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua",
                   "Search/MSUF_Menu2_Search_StaticIndex_Data.lua")
    sources = {path.relative_to(menu).as_posix(): keep.read(path)
               for path in menu.rglob("*") if path.suffix.lower() in (".lua", ".xml")}
    covered_count = total = declared_count = 0
    stale, issues = [], []
    evidence_path = root / "tools/menu_schema_coverage.json"
    evidence = json.loads(keep.read(evidence_path)) if evidence_path.exists() else {}
    if evidence.get("version") != 1:
        issues.append("schema projection provenance missing/version invalid")
    for index, name in enumerate(index_names):
        text = sources[name]
        digest = hashlib.sha256()
        excluded = set(index_names) if index == 0 else {name}
        for rel in sorted(sources):
            if rel not in excluded:
                digest.update(rel.encode("utf-8") + b"\0" + sources[rel].encode("utf-8") + b"\0")
        recorded = re.search(r'StaticIndexSourceSha256 = "([A-F0-9]{64})"', text)
        if not recorded or recorded.group(1) != digest.hexdigest().upper():
            stale.append(name)
        blob = re.search(r"StaticIndexBlob = \[==\[\n(.*?)\]==\]", text, re.S)
        if not blob:
            raise ValueError("menu inventory missing: " + name)
        rows = [line.split("\t") for line in blob.group(1).splitlines()]
        expected = re.search(r"StaticIndexRecordCount = (\d+)", text)
        if not expected or len(rows) != int(expected.group(1)) or any(len(row) != 12 for row in rows):
            raise ValueError("menu inventory malformed: " + name)
        settings = [row for row in rows if row[2] in SETTING_KINDS]
        if not settings:
            raise ValueError("menu inventory contains no setting controls: " + name)
        total += len(settings)
        covered_count += sum(bool(row[3].strip()) for row in settings)
        projection = evidence.get("indexes", {}).get(name, {})
        if (projection.get("sourceSha256") != (recorded.group(1) if recorded else None)
                or projection.get("blobSha256") != hashlib.sha256(blob.group(1).encode("utf-8")).hexdigest()):
            issues.append("schema projection missing/stale: " + name)
            continue
        records = projection.get("records", [])
        by_identity = {record["identity"]: record for record in records}
        identities = {row[7] for row in settings}
        if len(by_identity) != len(records) or len(identities) != len(settings) or set(by_identity) != identities:
            issues.append("schema projection identities differ: " + name)
            continue
        unindexed = projection.get("unindexedRecords")
        if (projection.get("allSettingsCaptured") is not True or not isinstance(unindexed, list)
                or projection.get("settingControlCount") != len(settings) + len(unindexed)):
            issues.append("complete pre-search schema projection missing: " + name)
            continue
        extra_ids = [record.get("identity") for record in unindexed]
        if not all(extra_ids) or len(set(extra_ids)) != len(extra_ids) or identities.intersection(extra_ids):
            issues.append("unindexed schema projection identities differ: " + name)
            continue

        def declared(record, setting_key, kind):
            return (bool(setting_key.strip()) and record.get("settingKey") == setting_key
                    and record.get("schemaSettingPath") == setting_key
                    and record.get("schemaKind") == kind
                    and record.get("schemaId") == record.get("controlId")
                    and all(record.get(key) for key in ("schemaId", "scope", "applyDomain")))

        for row in settings:
            record = by_identity[row[7]]
            declared_count += bool(declared(record, row[3], row[2]))
        total += len(unindexed)
        for record in unindexed:
            key, kind = record.get("settingKey", ""), record.get("schemaKind")
            covered_count += bool(key.strip())
            declared_count += kind in SETTING_KINDS and bool(declared(record, key, kind))
    return covered_count, total, stale, declared_count, issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--details", action="store_true")
    args = parser.parse_args()
    started = time.perf_counter()
    rows, details = [], []
    try:
        totals, long_total, long_open, clones, clones_open, details = measure(args.root)
        active, keep_count, pending_count, extra, dynamic = global_counts(args.root)
        rows.append(("global export names in _G", "%d known; %d dynamic sites unenumerated" % (active, len(dynamic)),
                     "%d generated keep + %d pending page names; complete inventory" % (keep_count, pending_count),
                     not extra and not dynamic))
        rows.append(("functions > 150 lines", "%d (%d unexcepted)" % (long_total, long_open), "0 unexcepted", long_open == 0))
        for metric in ("client_guards", "fallback_lambdas", "semicolon_lines", "long_lines"):
            rows.append((metric, str(totals[metric]), "0", totals[metric] == 0))
        rows.append(("clone_windows", "%d (%d unlisted)" % (clones, clones_open), "only listed hot-path copies", clones_open == 0))
        count, total, stale, declared, issues = menu_coverage(args.root)
        rows.append(("schema settingKey coverage of menu controls", "%d/%d proven; %d keyed (%.2f%%)%s" %
                     (declared, total, count, 100 * count / total, "; stale inventory" if stale else ""),
                     "100%, current schema projection", declared == total and not stale and not issues))
        details.extend("global outside generated keep: " + name for name in extra)
        details.extend("dynamic global publication %s:%d: %s" % item for item in dynamic)
        details.extend("stale menu inventory: " + name for name in stale)
        details.extend(issues)
    except (ValueError, OSError, KeyError, ledger.LedgerError) as error:
        present = {row[0] for row in rows}
        required = ("global export names in _G", "functions > 150 lines", "client_guards", "fallback_lambdas",
                    "semicolon_lines", "long_lines", "clone_windows", "schema settingKey coverage of menu controls")
        rows.extend((name, "unavailable", "complete inventory", False) for name in required if name not in present)
        rows.append(("source inventory", str(error), "complete", False))
    print("metric\tcurrent\ttarget\tresult")
    for name, current, target, passed in rows:
        print("%s\t%s\t%s\t%s" % (name, current, target, "PASS" if passed else "FAIL"))
    elapsed = time.perf_counter() - started
    failed = sum(not row[3] for row in rows)
    if elapsed >= 10:
        failed += 1
        print("static runtime\t%.3f s\t< 10 s\tFAIL" % elapsed)
    print("scorecard: %d failed, %.3f s (static source only)" % (failed, elapsed))
    if args.details:
        for detail in details:
            print(detail)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
