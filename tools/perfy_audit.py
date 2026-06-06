#!/usr/bin/env python3
"""
Offline Perfy SavedVariables analyzer for MSUF.

Reads !!!Perfy.lua, reconstructs matched Enter/Leave spans, filters non-MSUF
noise, and writes a plain-text performance report. No WoW runtime, Lua language
server, or third-party Python package is required.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime
import math
import os
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import DefaultDict, Dict, Iterable, List, Optional, Pattern, Tuple, Union


ACTION_NAMES = {
    "PerfyStart",
    "PerfyStop",
    "OnEvent",
    "Enter",
    "Leave",
    "CoroutineResume",
    "CoroutineYield",
}

DEFAULT_INCLUDE = (
    r"^(UFStatic:UnitFrames/|Element:|UF6:|FrameScript:.*MSUF|FrameScript:UFEventDriver)"
    r"|MidnightSimpleUnitFrames|\\UnitFrames\\|/UnitFrames/"
)
DEFAULT_EXCLUDE = r"^$"
DEFAULT_TRACE = (
    r"e:\World of Warcraft\_retail_\WTF\Account\1108323981#1"
    r"\SavedVariables\!!!Perfy.lua"
)

Number = Union[int, float]
Token = Union[str, float]


@dataclasses.dataclass
class FunctionStat:
    calls: int = 0
    self_time: float = 0.0
    inclusive_time: float = 0.0
    max_inclusive: float = 0.0
    max_self: float = 0.0
    extras: collections.Counter = dataclasses.field(default_factory=collections.Counter)

    def add(self, inclusive: float, self_time: float, extra: Optional[str]) -> None:
        self.calls += 1
        self.inclusive_time += inclusive
        self.self_time += self_time
        if inclusive > self.max_inclusive:
            self.max_inclusive = inclusive
        if self_time > self.max_self:
            self.max_self = self_time
        if extra:
            self.extras[extra] += 1


@dataclasses.dataclass
class StackFrame:
    label: str
    start: float
    child_time: float = 0.0
    extra: Optional[str] = None


@dataclasses.dataclass
class TraceData:
    name_to_id: Dict[str, int]
    id_to_names: DefaultDict[int, List[str]]
    event_name_to_id: Dict[str, int]
    id_to_events: Dict[int, str]
    trace_tokens: List[List[Token]]


@dataclasses.dataclass
class AnalysisResult:
    span_start: Optional[float]
    span_stop: Optional[float]
    stats: Dict[str, FunctionStat]
    foreign_stats: Dict[str, FunctionStat]
    event_counts: collections.Counter
    event_extras: DefaultDict[str, collections.Counter]
    action_counts: collections.Counter
    module_totals: Dict[str, FunctionStat]
    foreign_module_totals: Dict[str, FunctionStat]
    parent_child: DefaultDict[str, collections.Counter]
    parent_child_time: DefaultDict[str, collections.Counter]
    open_stack: int
    mismatches: int
    orphan_leaves: int
    resyncs: int
    enter_count: int
    leave_count: int
    included_enter_count: int
    included_leave_count: int
    total_records: int
    included_records: int
    foreign_records: int
    recorder_overhead: float
    memory_min: Optional[float]
    memory_max: Optional[float]
    allocation_total: float


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def lua_unescape(value: str) -> str:
    # Perfy labels are simple Lua strings. unicode_escape handles the common
    # backslash escapes well enough for labels and event extras.
    try:
        return value.encode("utf-8").decode("unicode_escape")
    except Exception:
        return value


def find_lua_table_block(text: str, key: str) -> str:
    marker = f'["{key}"]'
    pos = text.find(marker)
    if pos < 0:
        raise ValueError(f"missing table {key!r}")
    start = text.find("{", pos)
    if start < 0:
        raise ValueError(f"missing opening brace for {key!r}")
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise ValueError(f"unterminated table {key!r}")


def parse_name_id_table(text: str, key: str) -> Tuple[Dict[str, int], DefaultDict[int, List[str]]]:
    block = find_lua_table_block(text, key)
    name_to_id: Dict[str, int] = {}
    id_to_names: DefaultDict[int, List[str]] = collections.defaultdict(list)
    pattern = re.compile(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*(\d+)\s*,')
    for match in pattern.finditer(block):
        name = lua_unescape(match.group(1))
        ident = int(match.group(2))
        name_to_id[name] = ident
        id_to_names[ident].append(name)
    return name_to_id, id_to_names


def parse_optional_event_names(text: str) -> Tuple[Dict[str, int], Dict[int, str]]:
    try:
        name_to_id, id_to_names = parse_name_id_table(text, "EventNames")
    except ValueError:
        name_to_id, id_to_names = {}, collections.defaultdict(list)
    id_to_event = {}
    for ident, names in id_to_names.items():
        for name in names:
            if name in ACTION_NAMES:
                id_to_event[ident] = name
                break
    return name_to_id, id_to_event


def iter_record_bodies(trace_block: str) -> Iterable[str]:
    # Skip the outer Trace braces and yield each top-level record body.
    body = trace_block[1:-1]
    depth = 0
    start: Optional[int] = None
    in_string = False
    escape = False
    for i, ch in enumerate(body):
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            if depth == 0:
                start = i + 1
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                yield body[start:i]
                start = None


NUMBER_RE = re.compile(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def parse_lua_array_values(body: str) -> List[Token]:
    tokens: List[Token] = []
    i = 0
    n = len(body)
    while i < n:
        ch = body[i]
        if ch.isspace() or ch == ",":
            i += 1
            continue
        if ch == '"':
            i += 1
            out = []
            escape = False
            while i < n:
                ch = body[i]
                if escape:
                    out.append("\\" + ch)
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == '"':
                    i += 1
                    break
                else:
                    out.append(ch)
                i += 1
            tokens.append(lua_unescape("".join(out)))
            continue
        match = NUMBER_RE.match(body, i)
        if match:
            raw = match.group(0)
            value = float(raw)
            tokens.append(value)
            i = match.end()
            continue
        # Unknown token in a trace record; skip to the next comma.
        while i < n and body[i] != ",":
            i += 1
    return tokens


def parse_trace(text: str) -> TraceData:
    name_to_id, id_to_names = parse_name_id_table(text, "FunctionNames")
    event_name_to_id, id_to_events = parse_optional_event_names(text)
    trace_block = find_lua_table_block(text, "Trace")
    trace_tokens = [parse_lua_array_values(body) for body in iter_record_bodies(trace_block)]
    trace_tokens = [record for record in trace_tokens if len(record) >= 3]
    return TraceData(
        name_to_id=name_to_id,
        id_to_names=id_to_names,
        event_name_to_id=event_name_to_id,
        id_to_events=id_to_events,
        trace_tokens=trace_tokens,
    )


def numeric(value: Token) -> Optional[float]:
    return value if isinstance(value, float) and math.isfinite(value) else None


def int_id(value: Token) -> Optional[int]:
    if not isinstance(value, float):
        return None
    return int(value)


def action_lookup(data: TraceData) -> Dict[int, str]:
    out = dict(data.id_to_events)
    if out:
        return out
    for ident, names in data.id_to_names.items():
        for name in names:
            if name in ACTION_NAMES:
                out[ident] = name
                break
    return out


def function_lookup(id_to_names: Dict[int, List[str]], include_re: Pattern[str]) -> Dict[int, str]:
    out = {}
    for ident, names in id_to_names.items():
        candidates = [name for name in names if name not in ACTION_NAMES]
        if not candidates:
            continue
        preferred = [name for name in candidates if include_re.search(name)]
        out[ident] = (preferred or candidates)[0]
    return out


def record_extra(record: List[Token]) -> Optional[str]:
    for value in record[3:]:
        if isinstance(value, str):
            return value
    return None


def record_overhead(record: List[Token]) -> float:
    value = numeric(record[3]) if len(record) > 3 else None
    return value or 0.0


def record_memory(record: List[Token]) -> Optional[float]:
    return numeric(record[4]) if len(record) > 4 else None


def record_allocation(record: List[Token]) -> float:
    value = numeric(record[5]) if len(record) > 5 else None
    return value or 0.0


def classify_included(label: str, include_re: Pattern[str], exclude_re: Pattern[str]) -> bool:
    return bool(include_re.search(label)) and not bool(exclude_re.search(label))


def module_name(label: str) -> str:
    if label.startswith("UFStatic:"):
        rest = label[len("UFStatic:") :]
        if ".lua:" in rest:
            return rest.split(".lua:", 1)[0] + ".lua"
    if label.startswith("Element:"):
        return "Element"
    if label.startswith("UF6:"):
        return "UF6"
    if label.startswith("FrameScript:"):
        return "FrameScript"
    if ".lua:" in label:
        return label.split(".lua:", 1)[0] + ".lua"
    return label.split(":", 1)[0]


def add_module_stat(modules: Dict[str, FunctionStat], label: str, inclusive: float, self_time: float) -> None:
    module = module_name(label)
    stat = modules.setdefault(module, FunctionStat())
    stat.add(inclusive, self_time, None)


def analyze(data: TraceData, include_re: Pattern[str], exclude_re: Pattern[str]) -> AnalysisResult:
    actions = action_lookup(data)
    functions = function_lookup(data.id_to_names, include_re)

    stats: Dict[str, FunctionStat] = {}
    foreign_stats: Dict[str, FunctionStat] = {}
    module_totals: Dict[str, FunctionStat] = {}
    foreign_module_totals: Dict[str, FunctionStat] = {}
    event_counts: collections.Counter = collections.Counter()
    event_extras: DefaultDict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    action_counts: collections.Counter = collections.Counter()
    parent_child: DefaultDict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    parent_child_time: DefaultDict[str, collections.Counter] = collections.defaultdict(collections.Counter)

    stack: List[StackFrame] = []
    span_start: Optional[float] = None
    span_stop: Optional[float] = None
    mismatches = 0
    orphan_leaves = 0
    resyncs = 0
    enter_count = leave_count = 0
    included_enter_count = included_leave_count = 0
    included_records = foreign_records = 0
    recorder_overhead = 0.0
    memory_min: Optional[float] = None
    memory_max: Optional[float] = None
    allocation_total = 0.0

    for record in data.trace_tokens:
        timestamp = numeric(record[0])
        if timestamp is None:
            continue
        if span_start is None:
            span_start = timestamp
        span_stop = timestamp

        action_id = int_id(record[1])
        function_id = int_id(record[2])
        action = actions.get(action_id or -1)
        label = functions.get(function_id or -1)
        extra = record_extra(record)

        if action:
            action_counts[action] += 1
        recorder_overhead += record_overhead(record)
        mem = record_memory(record)
        if mem is not None:
            memory_min = mem if memory_min is None else min(memory_min, mem)
            memory_max = mem if memory_max is None else max(memory_max, mem)
        allocation_total += record_allocation(record)

        if not label:
            foreign_records += 1
            continue
        included = classify_included(label, include_re, exclude_re)
        if included:
            included_records += 1
        else:
            foreign_records += 1

        if action == "OnEvent":
            if stack:
                mismatches += len(stack)
                resyncs += 1
                stack = []
            event_counts[label] += 1
            if extra:
                event_extras[label][extra] += 1
            continue
        if action in ("CoroutineResume", "CoroutineYield", "PerfyStop") and stack:
            mismatches += len(stack)
            resyncs += 1
            stack = []
        if action == "Enter":
            enter_count += 1
            if included:
                included_enter_count += 1
            if stack:
                parent = stack[-1].label
                parent_child[parent][label] += 1
            stack.append(StackFrame(label=label, start=timestamp, extra=extra))
            continue
        if action == "Leave":
            leave_count += 1
            if included:
                included_leave_count += 1
            match_index = None
            for index in range(len(stack) - 1, -1, -1):
                if stack[index].label == label:
                    match_index = index
                    break
            if match_index is None:
                orphan_leaves += 1
                continue
            if match_index != len(stack) - 1:
                mismatches += len(stack) - 1 - match_index
                stack = stack[: match_index + 1]
            frame = stack.pop()
            inclusive = max(0.0, timestamp - frame.start)
            self_time = max(0.0, inclusive - frame.child_time)
            target = stats if classify_included(label, include_re, exclude_re) else foreign_stats
            target.setdefault(label, FunctionStat()).add(inclusive, self_time, frame.extra)
            add_module_stat(module_totals if target is stats else foreign_module_totals, label, inclusive, self_time)
            if stack:
                stack[-1].child_time += inclusive
                parent_child_time[stack[-1].label][label] += inclusive
            continue

    return AnalysisResult(
        span_start=span_start,
        span_stop=span_stop,
        stats=stats,
        foreign_stats=foreign_stats,
        event_counts=event_counts,
        event_extras=event_extras,
        action_counts=action_counts,
        module_totals=module_totals,
        foreign_module_totals=foreign_module_totals,
        parent_child=parent_child,
        parent_child_time=parent_child_time,
        open_stack=len(stack),
        mismatches=mismatches,
        orphan_leaves=orphan_leaves,
        resyncs=resyncs,
        enter_count=enter_count,
        leave_count=leave_count,
        included_enter_count=included_enter_count,
        included_leave_count=included_leave_count,
        total_records=len(data.trace_tokens),
        included_records=included_records,
        foreign_records=foreign_records,
        recorder_overhead=recorder_overhead,
        memory_min=memory_min,
        memory_max=memory_max,
        allocation_total=allocation_total,
    )


STATIC_LABEL_RE = re.compile(r"^UFStatic:(.*?\.lua):(\d+):(.+)$")
SOURCE_FUNCTION_RE = re.compile(
    r"^\s*(?:local\s+)?function\s+([A-Za-z_][\w\.:]*)\s*\(|"
    r"^\s*([A-Za-z_][\w\.:]*)\s*=\s*function\s*\("
)


def normalize_rel(path: Union[str, Path]) -> str:
    return str(path).replace("\\", "/")


def static_coverage(data: TraceData, source_root: Path, scope: str) -> Tuple[int, int, List[str]]:
    scope_path = source_root / scope
    if not scope_path.exists():
        return 0, 0, []

    covered = set()
    for name in data.name_to_id:
        match = STATIC_LABEL_RE.match(name)
        if match:
            covered.add((normalize_rel(match.group(1)), int(match.group(2))))

    source_functions = []
    for path in scope_path.rglob("*.lua"):
        if "\\Libs\\" in str(path) or "/Libs/" in normalize_rel(path):
            continue
        rel = normalize_rel(path.relative_to(source_root))
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            continue
        for lineno, line in enumerate(lines, start=1):
            match = SOURCE_FUNCTION_RE.search(line)
            if match:
                name = match.group(1) or match.group(2) or "anonymous"
                source_functions.append((rel, lineno, name))

    missing = [
        f"{rel}:{lineno}:{name}"
        for rel, lineno, name in source_functions
        if (rel, lineno) not in covered
    ]
    return len(source_functions), len(source_functions) - len(missing), missing


def fmt_ms(seconds: float) -> str:
    return f"{seconds * 1000.0:9.3f} ms"


def fmt_rate(value: float, duration: float) -> str:
    if duration <= 0:
        return "n/a"
    return f"{value / duration:.1f}/s"


def sorted_stats(stats: Dict[str, FunctionStat], key: str) -> List[Tuple[str, FunctionStat]]:
    attr = {
        "self": "self_time",
        "inclusive": "inclusive_time",
        "calls": "calls",
        "max": "max_inclusive",
    }[key]
    return sorted(stats.items(), key=lambda item: getattr(item[1], attr), reverse=True)


def hint_for(label: str) -> Optional[str]:
    checks = [
        ("DispatchFrameEvent", "Reduce event fanout before dispatch; check route tables and unit-specific RegisterUnitEvent."),
        ("PowerText", "Keep player urgent text safe; throttle only non-urgent/plain-safe paths."),
        ("Health.Update", "Split UNIT_HEALTH value work from color/status/max-health lanes."),
        ("Text_Format", "Reduce text calls or dirty-key plain paths; do not compare secret values."),
        ("Secrets", "Lower caller count; do not remove secret checks blindly."),
        ("Prediction", "Compile active lanes only: absorb/heal/heal-absorb/test."),
        ("GroupStatusRuntime", "Register only real status features: dead/ghost/AFK/DND/connection."),
        ("RangeFade", "Keep unit routes exact and avoid polling units covered by Blizzard range events."),
        ("GroupRangeFade", "Use only group range APIs and feature-gated events."),
        ("GroupVisuals", "Compile visual lanes by event: health, target, focus, threat, range."),
    ]
    for needle, hint in checks:
        if needle in label:
            return hint
    return None


def write_report(
    out,
    trace_path: Path,
    result: AnalysisResult,
    data: TraceData,
    source_root: Optional[Path],
    scope: str,
    top: int,
) -> None:
    duration = (
        (result.span_stop - result.span_start)
        if result.span_start is not None and result.span_stop is not None
        else 0.0
    )
    msuf_self = sum(stat.self_time for stat in result.stats.values())
    msuf_inclusive = sum(stat.inclusive_time for stat in result.stats.values())
    foreign_self = sum(stat.self_time for stat in result.foreign_stats.values())

    def line(text: str = "") -> None:
        out.write(text + "\n")

    line("MSUF Perfy Offline Audit")
    line("=" * 24)
    line(f"Trace: {trace_path}")
    line(f"Duration: {duration:.3f}s")
    line(f"Records: {result.total_records:,}")
    line(f"FunctionNames: {len(data.name_to_id):,}")
    line(
        "Enter/Leave: "
        f"{result.enter_count:,}/{result.leave_count:,} "
        f"(included {result.included_enter_count:,}/{result.included_leave_count:,})"
    )
    line(
        f"Integrity: mismatches={result.mismatches:,}, "
        f"orphanLeaves={result.orphan_leaves:,}, openStack={result.open_stack:,}, "
        f"resyncs={result.resyncs:,}"
    )
    line(f"Included records: {result.included_records:,}; filtered/noise records: {result.foreign_records:,}")
    line(f"MSUF matched self: {fmt_ms(msuf_self)}; inclusive sum: {fmt_ms(msuf_inclusive)}")
    line(f"Filtered foreign matched self: {fmt_ms(foreign_self)}")
    line(f"Perfy recorder overhead field sum: {fmt_ms(result.recorder_overhead)}")
    if result.memory_min is not None and result.memory_max is not None:
        line(f"Trace memory field min/max: {result.memory_min:,.0f} -> {result.memory_max:,.0f}")
    if result.allocation_total:
        line(f"Trace allocation field sum: {result.allocation_total:,.0f}")
    line()

    line("Action Counts")
    line("-" * 13)
    for name, count in result.action_counts.most_common():
        line(f"{name:18} {count:9,} {fmt_rate(count, duration)}")
    line()

    line(f"Top {top} Functions By Self Time")
    line("-" * 32)
    line(f"{'self':>12} {'incl':>12} {'calls':>8} {'avg self':>12}  label")
    for label, stat in sorted_stats(result.stats, "self")[:top]:
        avg = stat.self_time / stat.calls if stat.calls else 0.0
        line(f"{fmt_ms(stat.self_time)} {fmt_ms(stat.inclusive_time)} {stat.calls:8,} {fmt_ms(avg)}  {label}")
    line()

    line(f"Top {top} Functions By Inclusive Time")
    line("-" * 37)
    line(f"{'incl':>12} {'self':>12} {'calls':>8} {'max incl':>12}  label")
    for label, stat in sorted_stats(result.stats, "inclusive")[:top]:
        line(f"{fmt_ms(stat.inclusive_time)} {fmt_ms(stat.self_time)} {stat.calls:8,} {fmt_ms(stat.max_inclusive)}  {label}")
    line()

    line("Module Totals By Self Time")
    line("-" * 26)
    for label, stat in sorted_stats(result.module_totals, "self")[:top]:
        line(f"{fmt_ms(stat.self_time)} {fmt_ms(stat.inclusive_time)} {stat.calls:8,}  {label}")
    line()

    edges = []
    for parent, children in result.parent_child_time.items():
        for child, child_time in children.items():
            if parent in result.stats or child in result.stats:
                calls = result.parent_child[parent][child]
                edges.append((child_time, calls, parent, child))
    if edges:
        edges.sort(reverse=True)
        line(f"Top {top} Parent -> Child Edges")
        line("-" * 29)
        line(f"{'child incl':>12} {'calls':>8}  parent -> child")
        for child_time, calls, parent, child in edges[:top]:
            line(f"{fmt_ms(child_time)} {calls:8,}  {parent} -> {child}")
        line()

    if result.event_counts:
        line("Top Event Hooks")
        line("-" * 15)
        for label, count in result.event_counts.most_common(top):
            line(f"{count:8,} {fmt_rate(count, duration):>10}  {label}")
            for extra, extra_count in result.event_extras[label].most_common(8):
                line(f"           {extra_count:8,}  {extra}")
        line()

    line("Hotspot Hints")
    line("-" * 13)
    emitted = set()
    for label, stat in sorted_stats(result.stats, "self")[:top]:
        hint = hint_for(label)
        if hint and hint not in emitted:
            emitted.add(hint)
            line(f"- {label}: {hint}")
    if not emitted:
        line("- No rule-based hints matched; use top self/inclusive sections.")
    line()

    if source_root:
        source_count, covered_count, missing = static_coverage(data, source_root, scope)
        line("Observed Static Trace Coverage")
        line("-" * 30)
        if source_count:
            pct = (covered_count / source_count) * 100.0
            line(f"Source scope: {source_root / scope}")
            line(f"Lua source function candidates: {source_count:,}")
            line(f"Observed UFStatic labels in this trace: {covered_count:,} ({pct:.1f}%)")
            if missing:
                line("First source functions not observed in this trace:")
                for item in missing[: min(top, 40)]:
                    line(f"  {item}")
        else:
            line(f"No source functions found for scope: {source_root / scope}")
        line()

    line("Noise Policy")
    line("-" * 12)
    line("- Rankings include only labels matching the include regex and not the exclude regex.")
    line("- Coroutine/WoW/other-addon records remain counted as trace noise, not MSUF cost.")
    line("- The recorder overhead field is reported separately and is not assigned to MSUF functions.")
    line("- Secret checks are treated as real MSUF cost only when called by included MSUF labels.")


PERFY_HOOK = r'''local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

if not _G.Perfy_Trace then return end

local Perfy_Trace = _G.Perfy_Trace
local Perfy_GetTime = _G.Perfy_GetTime or _G.GetTimePreciseSec or _G.GetTime
local type = type
local tostring = tostring
local pairs = pairs
local unpack = unpack or table.unpack

local function Now()
    return Perfy_GetTime and Perfy_GetTime() or 0
end

local function Trace(kind, label, extra)
    if extra ~= nil then
        Perfy_Trace(Now(), kind, label, extra)
    else
        Perfy_Trace(Now(), kind, label)
    end
end

_G.MSUF_PerfyEnter = function(label, extra)
    Trace("Enter", label, extra)
end

_G.MSUF_PerfyLeave = function(label, extra)
    Trace("Leave", label, extra)
end

local wrapped = {}

local function ExtraEventUnit(_, event, unit)
    if event and unit then
        return tostring(event) .. ":" .. tostring(unit)
    end
    return event and tostring(event) or nil
end

local function WrapTableFunction(tbl, key, label, extraFn)
    if not (tbl and key and label) then return false end
    local fn = tbl[key]
    if type(fn) ~= "function" or wrapped[fn] then return false end
    local function wrapper(...)
        local extra = extraFn and extraFn(...)
        Trace("Enter", label, extra)
        local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
        Trace("Leave", label, extra)
        if not ok then error(a, 0) end
        return a, b, c, d, e, f, g, h
    end
    wrapped[fn] = true
    wrapped[wrapper] = true
    tbl[key] = wrapper
    return true
end

local function WrapFrameScript(frame, scriptName, label)
    if not (frame and frame.GetScript and frame.SetScript) then return false end
    local ok, fn = pcall(frame.GetScript, frame, scriptName)
    if not ok or type(fn) ~= "function" or wrapped[fn] then return false end
    local function wrapper(self, event, ...)
        local extra = event and tostring(event) or nil
        Trace("Enter", label, extra)
        local ok2, a, b, c, d, e, f, g, h = pcall(fn, self, event, ...)
        Trace("Leave", label, extra)
        if not ok2 then error(a, 0) end
        return a, b, c, d, e, f, g, h
    end
    wrapped[fn] = true
    wrapped[wrapper] = true
    frame:SetScript(scriptName, wrapper)
    return true
end

local function Install()
    local ns = _G.MSUF_NS or MSUF
    local UF = ns and ns.UF
    if not UF then return end

    WrapTableFunction(UF, "DispatchFrameEvent", "UF6:DispatchFrameEvent", ExtraEventUnit)
    WrapTableFunction(UF, "UpdateRuntime", "UF6:UpdateRuntime")
    WrapTableFunction(UF, "FrameRuntimeUpdate", "UF6:FrameRuntimeUpdate")
    WrapTableFunction(UF, "FrameForceUpdate", "UF6:FrameForceUpdate")
    WrapTableFunction(UF, "RefreshElements", "UF6:RefreshElements")
    WrapTableFunction(UF, "ApplySpec", "UF6:ApplySpec")

    if UF.elements then
        for name, element in pairs(UF.elements) do
            if type(element) == "table" then
                WrapTableFunction(element, "Update", "Element:" .. tostring(name) .. ".Update", ExtraEventUnit)
                WrapTableFunction(element, "Apply", "Element:" .. tostring(name) .. ".Apply")
            end
        end
    end

    WrapFrameScript(UF.eventDriver, "OnEvent", "FrameScript:UFEventDriver:OnEvent")
    WrapFrameScript(UF.driver, "OnEvent", "FrameScript:UFRuntimeDriver:OnEvent")
end

Install()

local f = _G.CreateFrame and _G.CreateFrame("Frame")
if f then
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_LOGIN" or name == addonName then
            Install()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, Install)
            end
        end
    end)
end
'''


@dataclasses.dataclass
class LuaToken:
    value: str
    start: int
    end: int
    line: int


@dataclasses.dataclass
class LuaBlock:
    kind: str
    label: Optional[str] = None
    top_return: bool = False


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def line_starts(text: str) -> List[int]:
    starts = [0]
    for match in re.finditer(r"\n", text):
        starts.append(match.end())
    return starts


def line_for(starts: List[int], pos: int) -> int:
    import bisect

    return bisect.bisect_right(starts, pos)


def line_indent(text: str, pos: int) -> str:
    start = text.rfind("\n", 0, pos) + 1
    end = start
    while end < len(text) and text[end] in (" ", "\t"):
        end += 1
    return text[start:end]


def long_bracket_end(text: str, pos: int) -> Optional[int]:
    if pos >= len(text) or text[pos] != "[":
        return None
    i = pos + 1
    while i < len(text) and text[i] == "=":
        i += 1
    if i >= len(text) or text[i] != "[":
        return None
    close = "]" + ("=" * (i - pos - 1)) + "]"
    end = text.find(close, i + 1)
    return len(text) if end < 0 else end + len(close)


def tokenize_lua(text: str) -> List[LuaToken]:
    starts = line_starts(text)
    tokens: List[LuaToken] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch.isspace():
            i += 1
            continue
        if text.startswith("--", i):
            lb_end = long_bracket_end(text, i + 2)
            if lb_end is not None:
                i = lb_end
            else:
                nl = text.find("\n", i)
                i = n if nl < 0 else nl + 1
            continue
        lb_end = long_bracket_end(text, i)
        if lb_end is not None:
            i = lb_end
            continue
        if ch == '"' or ch == "'":
            quote = ch
            i += 1
            escape = False
            while i < n:
                ch = text[i]
                i += 1
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == quote:
                    break
            continue
        if ch.isalpha() or ch == "_":
            start = i
            i += 1
            while i < n and (text[i].isalnum() or text[i] == "_"):
                i += 1
            tokens.append(LuaToken(text[start:i], start, i, line_for(starts, start)))
            continue
        tokens.append(LuaToken(ch, i, i + 1, line_for(starts, i)))
        i += 1
    return tokens


def token_value(tokens: List[LuaToken], index: int) -> Optional[str]:
    return tokens[index].value if 0 <= index < len(tokens) else None


def function_label(tokens: List[LuaToken], index: int) -> Optional[str]:
    ident_re = re.compile(r"^[A-Za-z_]\w*$")
    # function UF.Name(...)
    after = index + 1
    if token_value(tokens, after) and ident_re.match(tokens[after].value):
        parts = [tokens[after].value]
        j = after + 1
        while token_value(tokens, j) in (".", ":"):
            sep = tokens[j].value
            name = token_value(tokens, j + 1)
            if not name or not ident_re.match(name):
                break
            parts.append(sep + name)
            j += 2
        return "".join(parts)

    # name = function(...)
    if token_value(tokens, index - 1) == "=":
        j = index - 2
        if j >= 0 and ident_re.match(tokens[j].value):
            label = tokens[j].value
            j -= 1
            while j >= 1 and tokens[j].value in (".", ":") and ident_re.match(tokens[j - 1].value):
                label = tokens[j - 1].value + tokens[j].value + label
                j -= 2
            return label
    return None


def function_entry_pos(tokens: List[LuaToken], index: int) -> Optional[int]:
    j = index + 1
    while j < len(tokens) and tokens[j].value != "(":
        if tokens[j].value in ("do", "then", "end", "return"):
            return None
        j += 1
    if j >= len(tokens):
        return None
    depth = 0
    while j < len(tokens):
        value = tokens[j].value
        if value == "(":
            depth += 1
        elif value == ")":
            depth -= 1
            if depth == 0:
                return tokens[j].end
        j += 1
    return None


def nearest_function(stack: List[LuaBlock]) -> Optional[LuaBlock]:
    for block in reversed(stack):
        if block.kind == "function":
            return block
    return None


def instrument_lua_text(text: str, rel_path: str) -> Tuple[str, int, int]:
    tokens = tokenize_lua(text)
    inserts: List[Tuple[int, str]] = []
    stack: List[LuaBlock] = []
    instrumented_functions = 0
    instrumented_returns = 0

    for index, token in enumerate(tokens):
        value = token.value
        if value == "function":
            label = function_label(tokens, index)
            if label and "_msuf_probeNum" in label:
                label = None
            if label:
                entry = function_entry_pos(tokens, index)
                if entry is not None:
                    static_label = f"UFStatic:{rel_path}:{token.line}:{label}"
                    indent = line_indent(text, token.start)
                    inserts.append((
                        entry,
                        "\n" + indent + "if _G.MSUF_PerfyEnter then _G.MSUF_PerfyEnter("
                        + lua_quote(static_label) + ") end",
                    ))
                    label = static_label
                    instrumented_functions += 1
                else:
                    label = None
            stack.append(LuaBlock("function", label))
        elif value == "if":
            stack.append(LuaBlock("if"))
        elif value == "do":
            stack.append(LuaBlock("do"))
        elif value == "repeat":
            stack.append(LuaBlock("repeat"))
        elif value == "return":
            fn = nearest_function(stack)
            if fn and fn.label:
                indent = line_indent(text, token.start)
                inserts.append((
                    token.start,
                    indent + "if _G.MSUF_PerfyLeave then _G.MSUF_PerfyLeave("
                    + lua_quote(fn.label) + ") end\n",
                ))
                instrumented_returns += 1
            if stack and stack[-1] is fn:
                fn.top_return = True
        elif value == "until":
            while stack:
                block = stack.pop()
                if block.kind == "repeat":
                    break
        elif value == "end":
            if not stack:
                continue
            block = stack.pop()
            if block.kind == "function" and block.label and not block.top_return:
                indent = line_indent(text, token.start)
                inserts.append((
                    token.start,
                    indent + "if _G.MSUF_PerfyLeave then _G.MSUF_PerfyLeave("
                    + lua_quote(block.label) + ") end\n",
                ))

    for pos, snippet in sorted(inserts, key=lambda item: item[0], reverse=True):
        text = text[:pos] + snippet + text[pos:]
    return text, instrumented_functions, instrumented_returns


ENTER_LABEL_RE = re.compile(r"MSUF_PerfyEnter\(\"((?:[^\"\\]|\\.)*)\"")
LEAVE_LABEL_RE = re.compile(r"MSUF_PerfyLeave\(\"((?:[^\"\\]|\\.)*)\"")


def instrumentation_balance_warnings(text: str) -> List[str]:
    enters: collections.Counter = collections.Counter(lua_unescape(match.group(1)) for match in ENTER_LABEL_RE.finditer(text))
    leaves: collections.Counter = collections.Counter(lua_unescape(match.group(1)) for match in LEAVE_LABEL_RE.finditer(text))
    warnings = []
    for label, count in sorted(enters.items()):
        if leaves[label] <= 0:
            warnings.append(f"{label}: enter={count}, leave=0")
    return warnings


def patch_toc_for_perfy(toc_path: Path) -> None:
    text = toc_path.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()
    out = []
    hook_inserted = False
    optional_done = False
    for line in lines:
        if line.startswith("## OptionalDeps:"):
            deps = [part.strip() for part in line.split(":", 1)[1].split(",")]
            if "Perfy" not in deps:
                deps.append("Perfy")
            line = "## OptionalDeps: " + ", ".join(dep for dep in deps if dep)
            optional_done = True
        out.append(line)
        if not hook_inserted and line.startswith("## AddonCompartmentFuncOnLeave:"):
            out.append("MSUF_PerfyHook.lua")
            hook_inserted = True
    if not optional_done:
        out.insert(0, "## OptionalDeps: Perfy")
    if not hook_inserted:
        out.append("MSUF_PerfyHook.lua")
    toc_path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


def should_instrument(path: Path, addon_root: Path, scopes: List[str], instrument_all: bool) -> bool:
    if path.name == "MSUF_PerfyHook.lua":
        return False
    rel = normalize_rel(path.relative_to(addon_root))
    if rel.startswith("Libs/"):
        return False
    if instrument_all:
        return True
    return any(rel == scope or rel.startswith(scope.rstrip("/\\") + "/") for scope in scopes)


def validate_lua_files(build_addon_root: Path) -> Tuple[int, List[str]]:
    lua = shutil.which("luac") or shutil.which("luac5.1")
    if not lua:
        return 0, ["luac not found in PATH"]
    failed = []
    count = 0
    for path in build_addon_root.rglob("*.lua"):
        count += 1
        proc = subprocess_run([lua, "-p", str(path)])
        if proc != 0:
            failed.append(str(path))
    return count, failed


def subprocess_run(args: List[str]) -> int:
    import subprocess

    proc = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return proc.returncode


def zip_folder(folder: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in folder.rglob("*"):
            if path.is_file():
                zf.write(path, path.relative_to(folder.parent))


def copy_latest(zip_path: Path, output_dir: Path) -> Path:
    latest = output_dir / "MSUF_Perfy_Instrumented_latest.zip"
    shutil.copy2(zip_path, latest)
    return latest


def downloads_dir() -> Path:
    home = Path(os.environ.get("USERPROFILE") or str(Path.home()))
    return home / "Downloads"


def run_build(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    addon_source = (repo_root / args.addon_dir).resolve()
    if not addon_source.exists():
        raise SystemExit(f"addon source not found: {addon_source}")
    output_dir = Path(args.output_dir).resolve() if args.output_dir else downloads_dir()
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    scope_name = "all" if args.all else "_".join(scope.replace("\\", "_").replace("/", "_") for scope in args.scope)
    zip_name = args.name or f"MSUF_Perfy_Instrumented_{scope_name}_{timestamp}.zip"
    zip_path = output_dir / zip_name
    stage_root = Path(tempfile.mkdtemp(prefix=f"MSUF_PerfyBuild_{timestamp}_", dir=str(output_dir)))
    build_addon = stage_root / addon_source.name

    shutil.copytree(addon_source, build_addon, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    (build_addon / "MSUF_PerfyHook.lua").write_text(PERFY_HOOK, encoding="utf-8", newline="\n")
    patch_toc_for_perfy(build_addon / "MidnightSimpleUnitFrames.toc")

    instrumented_files = 0
    instrumented_functions = 0
    instrumented_returns = 0
    balance_warnings: List[str] = []
    if not args.no_static:
        for path in build_addon.rglob("*.lua"):
            if not should_instrument(path, build_addon, args.scope, args.all):
                continue
            rel = normalize_rel(path.relative_to(build_addon))
            text = path.read_text(encoding="utf-8", errors="ignore")
            new_text, funcs, returns = instrument_lua_text(text, rel)
            for warning in instrumentation_balance_warnings(new_text):
                balance_warnings.append(f"{rel}: {warning}")
            path.write_text(new_text, encoding="utf-8", newline="\n")
            instrumented_files += 1
            instrumented_functions += funcs
            instrumented_returns += returns

    if balance_warnings:
        print(f"staging kept for instrumentation balance failure: {stage_root}", file=sys.stderr)
        print("static instrumentation balance failed:", file=sys.stderr)
        for item in balance_warnings[:80]:
            print(f"  {item}", file=sys.stderr)
        return 1

    lua_count, failed = validate_lua_files(build_addon)
    if failed:
        if not args.keep_stage:
            print(f"staging kept for failed validation: {stage_root}", file=sys.stderr)
        print("luac validation failed:", file=sys.stderr)
        for item in failed[:50]:
            print(f"  {item}", file=sys.stderr)
        return 1

    zip_folder(build_addon, zip_path)
    latest = copy_latest(zip_path, output_dir) if args.latest else None

    print(f"zip={zip_path}")
    if latest:
        print(f"latest={latest}")
    print(f"stage={stage_root}")
    print(f"luaFiles={lua_count}")
    print(f"instrumentedFiles={instrumented_files}")
    print(f"instrumentedFunctions={instrumented_functions}")
    print(f"instrumentedReturns={instrumented_returns}")
    print("instrumentationBalanceWarnings=0")
    print("tocHasPerfyOptionalDep=True")
    print("tocLoadsHook=True")
    print("hasHook=True")

    if not args.keep_stage:
        shutil.rmtree(stage_root, ignore_errors=True)
    return 0


def add_analyze_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("trace", nargs="?", default=DEFAULT_TRACE, help="Path to !!!Perfy.lua")
    parser.add_argument("--out", help="Write report to this path instead of stdout")
    parser.add_argument("--source-root", default="MidnightSimpleUnitFrames", help="Addon source root for coverage scan")
    parser.add_argument("--scope", default="UnitFrames", help="Source subfolder for static coverage")
    parser.add_argument("--top", type=int, default=35, help="Number of top rows per section")
    parser.add_argument("--include", default=DEFAULT_INCLUDE, help="Regex for labels included as MSUF cost")
    parser.add_argument("--exclude", default=DEFAULT_EXCLUDE, help="Regex for labels excluded from MSUF cost")
    parser.add_argument("--no-coverage", action="store_true", help="Skip static source coverage scan")


def add_build_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--repo-root", default=".", help="Repository root")
    parser.add_argument("--addon-dir", default="MidnightSimpleUnitFrames", help="Addon folder under repo root")
    parser.add_argument(
        "--scope",
        action="append",
        default=None,
        help="Addon subfolder to statically instrument. Can be repeated. Default: UnitFrames",
    )
    parser.add_argument("--all", action="store_true", help="Instrument all first-party addon Lua files except Libs")
    parser.add_argument("--output-dir", default=None, help="Output folder. Default: %%USERPROFILE%%\\Downloads")
    parser.add_argument("--name", default=None, help="Zip file name. Default includes scope and timestamp")
    parser.add_argument("--latest", action="store_true", default=True, help="Also write MSUF_Perfy_Instrumented_latest.zip")
    parser.add_argument("--no-latest", dest="latest", action="store_false", help="Do not update latest zip")
    parser.add_argument("--no-static", action="store_true", help="Only add hook/TOC changes; do not static-instrument Lua")
    parser.add_argument("--keep-stage", action="store_true", help="Keep temporary staging folder after build")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="MSUF Perfy workflow tool: build instrumented zips and analyze !!!Perfy.lua traces."
    )
    subparsers = parser.add_subparsers(dest="command")
    analyze = subparsers.add_parser("analyze", help="Analyze a Perfy SavedVariables trace")
    add_analyze_args(analyze)
    build = subparsers.add_parser("build", help="Build a Perfy-instrumented MSUF zip")
    add_build_args(build)
    return parser


def run_analyze(args: argparse.Namespace) -> int:
    trace_path = Path(args.trace)
    if not trace_path.exists():
        raise SystemExit(f"trace file does not exist: {trace_path}")
    include_re = re.compile(args.include)
    exclude_re = re.compile(args.exclude)

    text = read_text(trace_path)
    data = parse_trace(text)
    result = analyze(data, include_re, exclude_re)
    source_root = None if args.no_coverage else Path(args.source_root)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8", newline="\n") as handle:
            write_report(handle, trace_path, result, data, source_root, args.scope, args.top)
        print(str(out_path))
    else:
        write_report(sys.stdout, trace_path, result, data, source_root, args.scope, args.top)
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)
    if raw and raw[0] in ("-h", "--help"):
        parser = build_arg_parser()
        parser.print_help()
        return 0
    if raw and raw[0] in ("build", "analyze"):
        parser = build_arg_parser()
        args = parser.parse_args(raw)
        if args.command == "build":
            if args.scope is None:
                args.scope = ["UnitFrames"]
            return run_build(args)
        return run_analyze(args)

    # Backward-compatible analyze mode:
    #   python tools/perfy_audit.py <!!!Perfy.lua> --out report.txt
    parser = argparse.ArgumentParser(
        description="Analyze Perfy !!!Perfy.lua traces and produce a text MSUF performance report."
    )
    add_analyze_args(parser)
    args = parser.parse_args(raw)
    return run_analyze(args)


if __name__ == "__main__":
    raise SystemExit(main())
