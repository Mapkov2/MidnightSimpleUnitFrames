"""PLAN-10 scorecard, source-only: no Lua execution, compiler or git writes.

Reuses quality_ratchet's file selection, source metrics, wrapper rules and clone
hashes. Function spans are parsed statically instead of invoking luac. Hot-path
functions require the exact PLAN-10 comment immediately above their header.
Clone exceptions additionally require tools/scorecard_clones.tsv rows with
file, start, end, reason (inclusive source lines); every exempt occurrence must
be wholly inside an annotated hot function. Missing/invalid data fails closed.
Dynamic ExportPublic families are bounded by the closed generated keep policy.
Native Nudge and Forever container names use gen_global_keep source domains.
PLAN-10 C5 refinements (2026-10-24): named CreateFrame/XML objects are native
WoW registrations, not optional function/value exports. Count and explain them
separately; they cannot be suppressed by ExportPublic's policy. Only the exact
Game/Classic `local IsSecret = issecretvalue or function() return false end`
idiom is an accepted fallback: these clients can lack the native secret API.
It is a safety dependency, not a missing provider silently replaced by a lambda.
All other fallback lambdas retain the zero target.
Cross-file module-prelude wiring is excluded using ratchet.clone_source_lines:
only the consecutive alias/Require/namespace prefix, never feature logic.
Named MSUF.Auras3RuntimeFactories.<module> factory headers introduce a module
body and use the same consecutive import-alias prefix rule inside that body.
The six-line clone hash is also a candidate detector, not a semantic proof:
it can join the tail of one function to the head of a different function, or
match part of independently versioned client spell-ID catalogs. C5 therefore
reports exact reviewed non-code candidates separately in
tools/scorecard_clone_noncode.tsv (inclusive lines, normalized source SHA256,
category, reason). A splice must cross innermost function boundaries; a catalog
window must be inside a known spell catalog constructor and contain no calls
or control flow. Defaults/configuration tables and executable cold logic are
never covered by this rule. Changed or unused reviews fail closed. Remaining
executable clone occurrences retain the target: only listed hot-path copies.
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
CLASSIC_SECRET_FALLBACK = re.compile(r"^local IsSecret = issecretvalue or function\(\) return false end$")


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


def literal_catalog(text):
    """Recognize Lua literal tables, including nested records and literal keys.

    Identifiers are allowed as field names only. No variable value, operator,
    function call or control flow is accepted anywhere in the complete table.
    Input has already had strings/comments masked by ratchet.strip_source.
    """
    number = r"(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)"
    tokens = re.findall(r'"[^"\n]*"|' + number + r"|[A-Za-z_]\w*|\S", text)

    def value(index):
        if index >= len(tokens):
            raise ValueError("missing literal")
        token = tokens[index]
        if token == "{":
            index += 1
            while tokens[index] != "}":
                if tokens[index] == "[":
                    index = value(index + 1)
                    if tokens[index:index + 2] != ["]", "="]:
                        raise ValueError("nonliteral key")
                    index += 2
                elif (re.fullmatch(r"[A-Za-z_]\w*", tokens[index])
                      and tokens[index + 1] == "="):
                    index += 2
                index = value(index)
                if tokens[index] in (",", ";"):
                    index += 1
                elif tokens[index] != "}":
                    raise ValueError("nonliteral expression")
            return index + 1
        if token == "-":
            if not re.fullmatch(number, tokens[index + 1]):
                raise ValueError("nonliteral minus")
            return index + 2
        if token.startswith('"') or token in ("true", "false", "nil") or re.fullmatch(number, token):
            return index + 1
        raise ValueError("nonliteral value")

    try:
        return value(0) == len(tokens)
    except (ValueError, IndexError):
        return False


def noncode_clone_reviews(root, sources):
    path = root / "tools/scorecard_clone_noncode.tsv"
    reviews = {}
    if not path.exists():
        return reviews
    catalog = re.compile(r"\b(?:A3\.(?:TargetDotData|PlayerDefensiveData)|groupHighlightSpellIDs|INTERRUPT_SPELLS)\s*=\s*\{")
    for row in csv.DictReader(path.open(encoding="utf-8-sig", newline=""), delimiter="\t"):
        rel, start, end = row["file"], int(row["start"]), int(row["end"])
        key = rel, start, end
        text, code, plain, funcs = sources[rel]
        normalized = [(n, line) for n, line in ratchet.clone_source_lines(plain) if start <= n <= end]
        digest = hashlib.sha256("\n".join(line for _, line in normalized).encode("utf-8")).hexdigest()
        if (key in reviews or len(normalized) != ratchet.WINDOW or not row["reason"].strip()
                or digest != row["source_sha256"]):
            raise ValueError("invalid/stale non-code clone review: " + repr(key))
        if row["category"] == "splice":
            owners = set()
            for number, _ in normalized:
                owners.add(min(((fn.end - fn.start, fn.start, fn.end) for fn in funcs[1:]
                                if fn.start <= number <= fn.end), default=(0, 0, 0))[1:])
            if len(owners) < 2:
                raise ValueError("clone splice does not cross function boundaries: " + repr(key))
        elif row["category"] == "catalog":
            # The complete table, not just its repeated rows, must be literal.
            # This cannot exempt the Placed/Frame/Aura default factories.
            valid = False
            for match in catalog.finditer(code):
                depth = 1
                for offset in range(match.end(), len(code)):
                    if code[offset] == "{":
                        depth += 1
                    elif code[offset] == "}":
                        depth -= 1
                        if depth == 0:
                            first, last = code.count("\n", 0, match.start()) + 1, code.count("\n", 0, offset) + 1
                            body = code[match.end() - 1:offset + 1]
                            if first <= start <= end <= last and literal_catalog(body):
                                valid = True
                            break
            if not valid:
                raise ValueError("clone catalog review is not literal spell data: " + repr(key))
        else:
            raise ValueError("unknown non-code clone category: " + repr(key))
        reviews[key] = row["category"], row["reason"]
    return reviews


def measure(root):
    profile = ratchet.PROFILES["classic"]
    allowlist = ratchet.load_json(root / "tools" / ratchet.ALLOWLIST_NAME, {})
    rels, _ = ratchet.product_files(root, profile, ratchet.declared_data(root, "classic", allowlist))
    totals, locations, hot = collections.Counter(), collections.defaultdict(list), {}
    function_ranges, sources = {}, {}
    details, unexcepted_long, long_total = [], 0, 0
    for rel in rels:
        text = keep.read(root / rel)
        code, plain = ratchet.strip_source(text)
        lines = text.splitlines()
        fallbacks = ratchet.fallback_lambda_offsets(code)
        mandatory = [offset for offset in fallbacks
                     if rel.startswith("MidnightSimpleUnitFrames/Game/Classic/")
                     and CLASSIC_SECRET_FALLBACK.fullmatch(lines[code.count("\n", 0, offset)])]
        details.extend("mandatory Classic secret fallback %s:%d: native API can be absent" %
                       (rel, code.count("\n", 0, offset) + 1) for offset in mandatory)
        metrics = {
            "lines": text.count("\n") + (0 if text.endswith("\n") or not text else 1),
            "client_guards": len(ratchet.client_guard_offsets(code)),
            "fallback_lambdas": len(fallbacks) - len(mandatory),
            "mandatory_secret_fallbacks": len(mandatory),
            "semicolon_lines": ratchet.semicolon_lines(code),
            "long_lines": sum(len(line) > ratchet.LONG_LINE for line in text.split("\n")),
        }
        normalized = ratchet.clone_source_lines(plain)
        hashes = ratchet.window_hashes([line for _, line in normalized])
        totals.update(metrics)
        funcs = source_functions(code)
        sources[rel] = text, code, plain, funcs
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
    reviews = noncode_clone_reviews(root, sources)
    clones = unexcepted_clones = noncode = 0
    used, used_reviews = set(), set()
    for places in locations.values():
        if len(places) < 2:
            continue
        for rel, start, end in places:
            key = rel, start, end
            if key in reviews:
                used_reviews.add(key)
                noncode += 1
                details.append("reviewed clone %s %s:%d-%d: %s" % (reviews[key][0], rel, start, end, reviews[key][1]))
                continue
            clones += 1
            containing = [(last - first, first, last) for first, last in function_ranges[rel]
                          if first <= start and end <= last]
            owner = min(containing)[1:] if containing else None
            if covered(start, end, exceptions.get(rel, ())) and owner in hot[rel]:
                used.update((rel, a, b) for a, b in exceptions[rel] if a <= start <= end <= b)
            else:
                unexcepted_clones += 1
                details.append("unlisted clone %s:%d-%d" % (rel, start, end))
    for rel, ranges in exceptions.items():
        if rel not in hot or any((rel, a, b) not in used or not covered(a, b, hot[rel]) for a, b in ranges):
            raise ValueError("unused or non-hot clone exception: " + rel)
    if set(reviews) != used_reviews:
        raise ValueError("unused non-code clone review")
    totals["noncode_clone_candidates"] = noncode
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
    native_frames = {name for name, entry in exports.items()
                     if any(site[3] == "frame" or (site[3] == "xml" and "frame" in entry.kinds)
                            for site in entry.sites)}
    frame_reasons = []
    for name in sorted(native_frames):
        sites = exports[name].sites
        frame_reasons.append("native named frame %s: %s" % (name, "; ".join(
            "%s:%d (%s registration)" % (path, line, via) for _, path, line, via in sorted(sites)
            if via in ("frame", "xml"))))
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
                native_frames.update(native[0])
                frame_reasons.append("native named frame family %s: %s" % (family.prefix, native[1]))
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
    return (len(active - native_frames), len(target - native_frames), len(pending),
            sorted(active - target - pending - native_frames), unresolved,
            len(active & native_frames), frame_reasons)


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
        active, keep_count, pending_count, extra, dynamic, frames, frame_reasons = global_counts(args.root)
        rows.append(("global export names in _G", "%d known; %d dynamic sites unenumerated" % (active, len(dynamic)),
                     "%d generated keep + %d pending page names; complete inventory" % (keep_count, pending_count),
                     not extra and not dynamic))
        rows.append(("native named frames in _G", str(frames), "CreateFrame/XML registrations, separately explained", True))
        rows.append(("functions > 150 lines", "%d (%d unexcepted)" % (long_total, long_open), "0 unexcepted", long_open == 0))
        for metric in ("client_guards", "fallback_lambdas", "semicolon_lines", "long_lines"):
            current = str(totals[metric])
            if metric == "fallback_lambdas":
                current += " unexcepted; %d mandatory Classic secret fallbacks" % totals["mandatory_secret_fallbacks"]
            rows.append((metric, current, "0 unexcepted" if metric == "fallback_lambdas" else "0", totals[metric] == 0))
        rows.append(("clone_windows", "%d (%d unlisted); %d reviewed non-code candidates" %
                     (clones, clones_open, totals["noncode_clone_candidates"]),
                     "only listed hot-path copies", clones_open == 0))
        count, total, stale, declared, issues = menu_coverage(args.root)
        rows.append(("schema settingKey coverage of menu controls", "%d/%d proven; %d keyed (%.2f%%)%s" %
                     (declared, total, count, 100 * count / total, "; stale inventory" if stale else ""),
                     "100%, current schema projection", declared == total and not stale and not issues))
        details.extend("global outside generated keep: " + name for name in extra)
        details.extend(frame_reasons)
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
