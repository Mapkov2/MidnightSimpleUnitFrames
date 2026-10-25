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

settingKey coverage reads the compact, committed menu_schema_coverage_receipt.json, generated
from actual declarations during live page builds on every supported client. The
projection captures declarations before search filtering, lists ephemeral reasons
and crosswalks the current indexes. Its source digest includes the page sources,
core providers, reused build harness and projection tools. Metadata proves declared
write targets only; no in-game rendering or setter-execution proof is claimed.
The preview row verifies the reviewed F1 render census against normalized source
hashes for all ten scoped files. Changed source requires a renewed review; this
is a source census, not proof of visual equivalence in the game.
"""

import argparse
import bisect
import collections
from contextlib import contextmanager
import csv
import hashlib
import json
import re
import time
from pathlib import Path

import gen_global_keep as keep
import public_globals_ledger as ledger
import quality_ratchet as ratchet
import menu_schema_coverage as schema_coverage

ROOT = Path(__file__).resolve().parents[1]
HOT = "-- hot path: kept whole (perf rule)"
BLOCKS = re.compile(r"\b(function|if|for|while|do|repeat|end|until)\b")
PREVIEW_FILES = {
    "MSUF_Menu2_Preview_ClassPower.lua", "Preview/MSUF_Menu2_ClassPowerPreview.lua",
    "Preview/MSUF_Menu2_GroupPreview_Render.lua", "Pages/MSUF_Menu2_Auras_Preview.lua",
    "Preview/MSUF_Menu2_UnitPreview_Render.lua", "Pages/MSUF_Menu2_UnitArenaTrinket.lua",
    "Pages/MSUF_Menu2_GlobalBars.lua", "Pages/MSUF_Menu2_AdvancedColors.lua",
    "Pages/MSUF_Menu2_ColorPainter.lua", "MSUF_Menu2_Dropdowns.lua",
}
SETTING_KINDS = {"toggle", "checkbox", "slider", "dropdown", "segment", "color", "textinput", "editbox", "input"}
CLASSIC_SECRET_FALLBACK = re.compile(r"^local IsSecret = issecretvalue or function\(\) return false end$")


@contextmanager
def run_cache():
    """One run, content-addressed source facts; never reuse stale disk metadata."""
    saved = keep.read, ledger.read_text, schema_coverage.read, ratchet.strip_source, ratchet.clone_source_lines, ledger.strip_and_mask
    texts, clones, views = {}, {}, {}

    def read(path, ledger_text=False):
        data = Path(path).read_bytes()
        key = data, ledger_text
        if key not in texts:
            text = data.decode("utf-8" if ledger_text else "utf-8-sig", errors="replace" if ledger_text else "strict")
            texts[key] = text.replace("\r\n", "\n") if ledger_text else text.replace("\r\n", "\n").replace("\r", "\n")
        return texts[key]

    def source_views(text):
        if text in views:
            return views[text]
        code, plain, exported, masked = [], [], [], []
        position = 0
        for match in ratchet.SCAN.finditer(text):
            start, end = match.span()
            if start < position:
                continue
            gap = text[position:start]
            for parts in (code, plain, exported, masked):
                parts.append(gap)
            token = match.group(0)
            long_comment = token.startswith("--") and match.group(1) is not None
            long_string = match.group(2) is not None
            if long_comment or long_string:
                equals = match.group(1) if long_comment else match.group(2)
                close = text.find("]" + equals + "]", end)
                if close < 0:
                    # Keep both original scanners' malformed-source semantics.
                    result = saved[3](text), saved[5](text)
                    views[text] = result
                    return result
                end = close + len(equals) + 2
                token = text[start:end]
            if token.startswith("--"):
                blank = ledger.fill(token, " ")
                exported.append(blank)
                masked.append(blank)
                if long_comment:
                    breaks = "\n" * token.count("\n")
                    code.append(breaks)
                    plain.append(breaks)
            else:
                plain.append(token)
                code.append(('""' + "\n" * token.count("\n")) if long_string else
                            ('"function"' if token[1:-1] == "function" else '""'))
                exported.append(token)
                masked.append(token[0] + ledger.fill(token[1:-1], "x") + token[-1])
            position = end
        for parts in (code, plain, exported, masked):
            parts.append(text[position:])
        result = ("".join(code), "".join(plain)), ("".join(exported), "".join(masked))
        views[text] = result
        return result

    def strip(text):
        return source_views(text)[0]


    def clone_lines(plain):
        key = plain
        if key not in clones:
            clones[key] = saved[4](plain)
        return clones[key]

    keep.read = schema_coverage.read = read
    ledger.read_text = lambda path: read(path, True)
    ratchet.strip_source, ratchet.clone_source_lines = strip, clone_lines
    ledger.strip_and_mask = lambda text: source_views(text)[1]
    try:
        yield
    finally:
        keep.read, ledger.read_text, schema_coverage.read, ratchet.strip_source, ratchet.clone_source_lines, ledger.strip_and_mask = saved


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
    # Namespace fields are not global publications. The ledger's default still
    # audits them; this scorecard needs the same global sites and dynamic families.
    exports, dynamic = ledger.static_inventory(str(root), include_namespace=False, classify_values=False)
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


def preview_pending_sites(evidence):
    count = 0
    for row in evidence.get("j4_review", {}).get("pending", []):
        if (not isinstance(row, dict) or not row.get("file") or not row.get("reason")
                or not isinstance(row.get("sites"), list) or not row["sites"]
                or not all(isinstance(site, str) and site for site in row["sites"])):
            raise ValueError("invalid supplemental preview finding")
        count += len(row["sites"])
    return count


def preview_render_census(root):
    """Fail closed if the reviewed scope, counts or exact product sources drift."""
    evidence = json.loads(keep.read(root / "tools/preview_render_census.json"))
    records = evidence["files"]
    if (evidence.get("version") != 1 or len(records) != len(PREVIEW_FILES)
            or {row["file"] for row in records} != PREVIEW_FILES):
        raise ValueError("incomplete preview render census")
    totals = collections.Counter()
    for row in records:
        path = root / schema_coverage.MENU / row["file"]
        digest = hashlib.sha256(keep.read(path).encode("utf-8")).hexdigest()
        if digest != row["source_sha256"] or not row["runtime_owner"].strip():
            raise ValueError("stale/unreviewed preview source: " + row["file"])
        for support in row.get("support_sources", []):
            path = root / schema_coverage.MENU / support["file"]
            digest = hashlib.sha256(keep.read(path).encode("utf-8")).hexdigest()
            if digest != support["source_sha256"]:
                raise ValueError("stale/unreviewed preview support source: " + support["file"])
        physical = {n for first, last in row["reviewed_ranges"] for n in range(first, last + 1)}
        if (len(physical) != row["before_physical"] or not physical or min(physical) < 1
                or max(physical) > row["baseline_line_count"]
                or not 0 < row["before_code"] <= row["before_physical"]
                or row["remaining_physical"] != 0 or row["remaining_code"] != 0):
            raise ValueError("unresolved/invalid preview render census: " + row["file"])
        totals.update({key: row[key] for key in ("before_physical", "before_code", "remaining_physical", "remaining_code")})
    if any(evidence[key] != value for key, value in totals.items()):
        raise ValueError("preview render census totals differ")
    totals["pending_sites"] = preview_pending_sites(evidence)
    return totals


def menu_coverage(root):
    path = root / schema_coverage.RECEIPT
    evidence = json.loads(keep.read(path)) if path.exists() else {}
    proven, total, issues = schema_coverage.audit_receipt(evidence, root)
    return proven, total, [], proven, issues


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--details", action="store_true")
    args = parser.parse_args()
    started = time.perf_counter()
    cpu_started = time.process_time()
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
        try:
            preview = preview_render_census(args.root)
            rows.append(("preview-only render code", "%d/%d physical; %d/%d code; %d reviewed files; %d pending scene sites" %
                         (preview["remaining_physical"], preview["before_physical"], preview["remaining_code"],
                          preview["before_code"], len(PREVIEW_FILES), preview["pending_sites"]),
                         "0 remaining in current reviewed census and scene findings", preview["pending_sites"] == 0))
        except (ValueError, OSError, KeyError) as error:
            rows.append(("preview-only render code", str(error), "current reviewed sources", False))
            details.append(str(error))
        count, total, stale, declared, issues = menu_coverage(args.root)
        rows.append(("schema settingKey coverage of menu controls", "%d/%d proven; %d keyed (%.2f%%)%s" %
                     (declared, total, count, 100 * count / total if total else 0, "; stale inventory" if stale else ""),
                     "100%, current schema projection", declared == total and not stale and not issues))
        details.extend("global outside generated keep: " + name for name in extra)
        details.extend(frame_reasons)
        details.extend("dynamic global publication %s:%d: %s" % item for item in dynamic)
        details.extend("stale menu inventory: " + name for name in stale)
        details.extend(issues)
    except (ValueError, OSError, KeyError, ledger.LedgerError) as error:
        present = {row[0] for row in rows}
        required = ("global export names in _G", "functions > 150 lines", "client_guards", "fallback_lambdas",
                    "semicolon_lines", "long_lines", "clone_windows", "preview-only render code", "schema settingKey coverage of menu controls")
        rows.extend((name, "unavailable", "complete inventory", False) for name in required if name not in present)
        rows.append(("source inventory", str(error), "complete", False))
    print("metric\tcurrent\ttarget\tresult")
    for name, current, target, passed in rows:
        print("%s\t%s\t%s\t%s" % (name, current, target, "PASS" if passed else "FAIL"))
    elapsed = time.perf_counter() - started
    cpu_elapsed = time.process_time() - cpu_started
    failed = sum(not row[3] for row in rows)
    runtime_passed = cpu_elapsed < 10
    failed += not runtime_passed
    print("static wall time\t%.3f s\tinformational\tINFO" % elapsed)
    print("static CPU time\t%.3f s\t< 10 s\t%s" % (cpu_elapsed, "PASS" if runtime_passed else "FAIL"))
    print("scorecard: %d failed, %.3f s (static source only)" % (failed, elapsed))
    if args.details:
        for detail in details:
            print(detail)
    return 1 if failed else 0


def main():
    with run_cache():
        return run()


if __name__ == "__main__":
    raise SystemExit(main())
