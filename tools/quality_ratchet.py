"""Quality ratchet: per-file code metrics where defects may only shrink and size stays under its limit (N3).

Usage (from the repo root; Python 3.12 and the Lua 5.1 luac):
  python tools/quality_ratchet.py                 # check (the default)
  python tools/quality_ratchet.py --check
  python tools/quality_ratchet.py --update        # rebaseline (see below)
  python tools/quality_ratchet.py --report [--top N]

Product files measured. Suite: every MSUF_Suite*/ addon. Classic:
MidnightSimpleUnitFrames/ and MidnightSimpleUnitFrames_Options/. Skipped: vendor libraries under
Libs/ (only the folders a profile names in "own_libs", Classic: Libs/MSUFUnitFrames, are MSUF code
and are measured) and the data and generated files the allowlist JSON declares ("data_files":
glob -> reason; the Suite's size_exempt list counts too). A data file is measured for the four
compiler-limit metrics only (main_locals, max_locals, max_upvalues, max_slots) and must stay
within the profile limits (an allowlist entry can cover one). A file never leaves measurement by what it
says about itself: a header comment declares nothing, and a file the baseline measured that is
still on disk but no longer measured fails the check (and blocks --update) until the declaration
is removed or --accept-regressions says the move is deliberate. The repo profile is picked from
the folders under the root; --profile suite|classic forces it.

Metrics per file (lower is better for every one). Two kinds:

SIZE metrics measure how much a file holds. Ordinary work grows them, so they have headroom.
This tool is the only place that holds the Lua 5.1 compiler limits (the gate has no second rule):
  lines            line count
  max_function     longest function in lines (luac 5.1 listing; a factory wrapper is a module, see below)
  main_locals      locals of the module scope: the main chunk, or the factory wrapper that holds the
                   module body (Lua caps a function at 200 active locals)
  max_locals       most locals of any other function (same cap)
  max_upvalues     most upvalues of any function (Lua caps it at 60)
  max_slots        most stack slots (registers) of any function, the main chunk and wrappers included
                   (Lua caps it at 250: "function or expression too complex")
  A size metric with a profile limit (Suite: lines 810, max_function 72, main_locals 150;
  Classic: main_locals 160, max_locals 160, max_upvalues 45, max_slots 230, max_function 150)
  fails an existing file only when the new value is above max(baseline, limit): a file under its
  limit may grow up to it, a file already over its limit may not grow past its baseline. A size
  metric without a profile limit (Suite max_upvalues, max_locals and max_slots, Classic lines) is
  report-only: measured, printed and baselined, never a failure. The limits apply to every
  measured file. --report prints the headroom to the hard Lua limits.

Factory wrappers. Many modules are one function that the loader calls once:
  MSUF.Auras3RuntimeFactories.Identity = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
  function Factories.Containers(A3, Model, Schema, Common, Storage)
  return function(deps)
A top-level function in that registration form is a MODULE, not a function, when it covers at
least 80 percent of the file and holds at least 2 nested functions that make up a quarter of its
body. A module is not measured as one function: max_function and long_functions look at the
functions inside it, and its own locals count as main_locals, because Lua compiles the wrapper as
one function with its own 200-local and 60-upvalue caps. Its own body (its lines minus the lines
of the functions nested in it) is measured as a function of its own, so a long function cannot
hide behind a few closures. A `local function BuildPage(...)`, a registration function that is
mostly statements, or one that covers a smaller part of the file stays a function. `do ... end` scopes are no function in luac and need no rule.

DEFECT metrics count things that are always worth removing, so they stay strict ratchets: any
increase over the baseline fails, with the file, the counts before and after, the lines and the
remedy in the message (for the four located metrics the lines are the ones this working tree
added according to `git diff HEAD`, else the first ones).
  g_reads          `_G.name`, `_G[...]` and rawget(_G, ...) reads (writes are not counted)
  type_guards      `type(x) == "function"` and `~=` guards
  fallback_lambdas `local X = MSUF.Y or function(...)` headers: a lookup that falls back to an inline
                   stub (PixelLayoutRegion, ExportPublic, issecretvalue ...), also as a table field
  client_guards    nil guards on the client model that Game/Shared/Initialize.lua always builds first:
                   `MSUF.Client and ...`, `MSUF.Client ~= nil`, `not MSUF.Client`, `MSUF.Client or {}`,
                   `type(MSUF.Client) == "table"`, `if MSUF.Client then`
  semicolon_lines  lines holding a statement-level `;` (a table field `;` is not one)
  long_lines       lines longer than 160 characters
  long_functions   functions longer than the profile limit (Suite 72, Classic 150 lines)
  clone_windows    6-line windows of comment-free, whitespace-normalized code that
                   also occur elsewhere in the measured files
Strings and comments never count: code inside them is blanked before matching.

Check. A file fails when a defect metric is worse than tools/quality_ratchet_baseline.json or a
size metric is above max(baseline, limit) (see above), unless
tools/quality_ratchet_allowlist.json has an "allowed" entry for that file
and metric whose "max" covers the new value, with a "reason" and a "date". A file
the baseline does not know is measured against the limits of the repo profile
(Suite: 810 lines, 72-line functions, 150 locals; Classic: 160 locals,
45 upvalues, 150-line functions; both: no `;` statements, no line over 160
characters, no fallback lambda, no client guard, clone share at most 1 percent).
An entry covers a new file the same way.
Improvements pass and are counted: a defect metric that shrank, or a size metric that fell
below a baseline that was over its limit. Check exits 1 on any failure and always ends
with one summary line. A baseline without a column this tool measures fails with the order to
rebaseline; --update accepts it.

Update. Recomputes every metric and rewrites the baseline. It refuses while a
regression has no valid allowlist entry or a file left measurement (--accept-regressions
overrides that: the lead's explicit call after a merge) and always refuses
while an allowlist entry is malformed. It prunes the allowlist entries the new baseline
already covers. Run it after each merge, then commit both files.

Allowlist entry:
  {"file": "MSUF_Suite/X.lua", "metric": "g_reads", "max": 12,
   "reason": "why this cannot improve yet", "date": "2026-10-02"}

Environment: MSUF_LUAC (or MSUF_LUAC51, or the folder of MSUF_LUA51 / MSUF_LUA)
names the Lua 5.1 luac; the check never runs without one.
"""

import argparse
import collections
import concurrent.futures
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parent
DEFAULT_LUAC = r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\luac.exe"
BASELINE_NAME = "quality_ratchet_baseline.json"
ALLOWLIST_NAME = "quality_ratchet_allowlist.json"
SUITE_STRUCTURE_ALLOWLIST = "tools/tests/suite_structure_allowlist.json"
LONG_LINE = 160
WINDOW = 6
CLONE_SHARE_NEW_FILE = 0.01
WRAPPER_SHARE = 0.8
WRAPPER_MIN_FUNCTIONS = 2
WRAPPER_FUNCTION_SHARE = 0.25
METRICS = ("lines", "max_function", "main_locals", "max_locals", "max_upvalues", "max_slots", "g_reads",
           "type_guards", "fallback_lambdas", "client_guards", "semicolon_lines", "long_lines",
           "long_functions", "clone_windows")
SIZE_METRICS = ("lines", "max_function", "main_locals", "max_locals", "max_upvalues", "max_slots")
DEFECT_METRICS = tuple(metric for metric in METRICS if metric not in SIZE_METRICS)
# What the Lua 5.1 compiler refuses (LUAI_MAXVARS, LUAI_MAXUPVALUES, MAXSTACK); the profile limits sit below.
HARD_LIMITS = {"main_locals": 200, "max_locals": 200, "max_upvalues": 60, "max_slots": 250}
LIMIT_METRICS = tuple(HARD_LIMITS)
PROFILES = {
    "suite": {
        "marker": "MSUF_Suite",
        "addon": lambda name: name.startswith("MSUF_Suite"),
        "function_limit": 72,
        "limits": {"lines": 810, "max_function": 72, "main_locals": 150, "semicolon_lines": 0,
                   "long_lines": 0, "long_functions": 0, "fallback_lambdas": 0, "client_guards": 0},
        "own_libs": (),
    },
    "classic": {
        "marker": "MidnightSimpleUnitFrames",
        "addon": lambda name: name in ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options"),
        "function_limit": 150,
        "limits": {"main_locals": 160, "max_locals": 160, "max_upvalues": 45, "max_slots": 230,
                   "max_function": 150, "semicolon_lines": 0, "long_lines": 0, "long_functions": 0,
                   "fallback_lambdas": 0, "client_guards": 0},
        "own_libs": ("MSUFUnitFrames",),
    },
}
DATA_NOTE = "data_files"
REMEDIES = {
    "max_function": "split the function; a factory wrapper counts its own body (its lines outside the nested functions) and each function inside it",
    "main_locals": "Lua caps a function at 200 locals; group related locals in one table or split the module",
    "max_locals": "Lua caps a function at 200 locals; group related locals in one table or split the function",
    "max_upvalues": "Lua caps a function at 60 upvalues; pass shared state in one table or split the function",
    "max_slots": "Lua caps a function at 250 stack slots; split the widest call, table constructor or function",
    "g_reads": "resolve the dependency once at load with MSUF.Require(name, file) (hard) or MSUF.Optional(name), "
               "or use the module table; do not read _G",
    "type_guards": "bind a function that must exist with MSUF.Require at load; keep a type check for "
                   "values the caller supplies",
    "fallback_lambdas": "bind the provider with local X = MSUF.Require(\"MSUF_X\", \"<this file>\") (it fails loudly "
                        "when the provider is missing) or MSUF.Optional for a truly optional one; an inline stub "
                        "hides a broken load order and drifts from the real function",
    "client_guards": "MSUF.Client is built by Game/Shared/Initialize.lua before any other file in every TOC: read "
                     "MSUF.Client.<fact> directly without a nil check, and let test fixtures load the real bootstrap",
    "semicolon_lines": "write one statement per line",
    "long_lines": "wrap the line below %d characters" % LONG_LINE,
    "long_functions": "split the function; a factory wrapper counts its own body (its lines outside the nested functions) and each function inside it",
    "clone_windows": "reuse the existing code instead of copying it",
}
LOCATED = ("g_reads", "type_guards", "fallback_lambdas", "client_guards")
SHOWN_LINES = 6


# ------------------------------------------------------------------ luac
def find_luac(explicit=None):
    candidates = [explicit, os.environ.get("MSUF_LUAC"), os.environ.get("MSUF_LUAC51")]
    for variable in ("MSUF_LUA51", "MSUF_LUA"):
        lua = os.environ.get(variable)
        if lua:
            folder = Path(lua).resolve().parent
            candidates.append(str(folder / ("luac.exe" if os.name == "nt" else "luac")))
    candidates.append(shutil.which("luac"))
    candidates.append(DEFAULT_LUAC)
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            run = subprocess.run([candidate, "-v"], capture_output=True, text=True, errors="replace")
            if run.returncode == 0 and re.match(r"Lua 5\.1", (run.stdout + run.stderr).strip()):
                return candidate
    raise SystemExit("FAIL Lua 5.1 luac not found (set MSUF_LUAC or put the portable 5.1 on PATH); "
                     "the ratchet never skips")


HEADER = re.compile(r"^(main|function) <(.+):(\d+),(\d+)> \(")
INFO = re.compile(r"^(\d+)\+? params?, (\d+) slots?, (\d+) upvalues?, (\d+) locals?, (\d+) constants?, "
                  r"(\d+) functions?")
CHUNK_CHARS = 24000
LUAC_WORKERS = 4
Fn = collections.namedtuple("Fn", "start end slots upvalues locals kids")


def luac_chunks(rels):
    """The files split for parallel luac runs: at least LUAC_WORKERS chunks (when there are files enough) and
    never a command line beyond CHUNK_CHARS. Files are dealt round-robin so that the big ones spread out."""
    total = sum(len(rel) + 1 for rel in rels)
    count = max(-(-total // CHUNK_CHARS), min(LUAC_WORKERS, len(rels)), 1)
    return [rels[index::count] for index in range(count)]


def luac_run(luac, root, chunk):
    """(listing facts, error text, exit status) of one luac -l -p run over a chunk of files."""
    with subprocess.Popen([luac, "-l", "-p"] + chunk, cwd=str(root), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, bufsize=1 << 20) as process:
        found = parse_listing(process.stdout.read())
        error = process.stderr.read().decode("utf-8", "replace").strip()
        return found, error, process.wait()


def luac_facts(luac, root, rels):
    """{rel: [Fn]} from luac -l -p: every function of the file in luac's order (the main chunk first,
    then each function before the functions nested in it). Files are passed in chunks that run side by
    side; luac then lists every file's main chunk by name."""
    facts = {}
    chunks = luac_chunks(rels)
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(chunks)) as pool:
        runs = list(pool.map(lambda chunk: luac_run(luac, root, chunk), chunks))
    for chunk, (found, error, status) in zip(chunks, runs):
        if status != 0:
            for rel in chunk:
                run = subprocess.run([luac, "-p", rel], cwd=str(root), capture_output=True, text=True,
                                     errors="replace")
                if run.returncode != 0:
                    raise SystemExit("FAIL %s does not compile under Lua 5.1: %s" % (rel, run.stderr.strip()))
            raise SystemExit("FAIL luac failed on a batch that no single file reproduces: " + error)
        facts.update(found)
    missing = [rel for rel in rels if rel not in facts]
    if missing:
        raise SystemExit("FAIL luac listing has no main chunk for %s" % missing[0])
    return facts


LISTING_LINE = re.compile(rb"^(?:(?:main|function) <[^\r\n]*|\d+\+? params?, [^\r\n]*)", re.M)


def parse_listing(data):
    """{file: [Fn]} of one luac listing (bytes). A header line is followed by the instructions
    (tab-indented, never matched here) and then the line with the slot, upvalue, local and
    nested-function counts. One regex pass picks those two kinds of line out of megabytes of code."""
    facts, current, pending = {}, None, None
    for found in LISTING_LINE.finditer(data):
        line = found.group(0).decode("utf-8", "replace")
        header = HEADER.match(line)
        if header:
            pending = None
            if header.group(1) == "main":
                name = header.group(2)
                current = None if name.startswith("=(luac)") or name == "(luac)" else name.replace("\\", "/")
                if current is not None:
                    facts[current] = []
            if current is not None:
                pending = (int(header.group(3)), int(header.group(4)))
            continue
        if pending is None:
            continue
        info = INFO.match(line)
        if info:
            facts[current].append(Fn(pending[0], pending[1], int(info.group(2)), int(info.group(3)),
                                     int(info.group(4)), int(info.group(6))))
            pending = None
    return facts


# ------------------------------------------------------------------ function shape
WRAPPER_FORM = re.compile(r"^\s*(?:function\s+[A-Za-z_]\w*(?:\s*[.:]\s*[A-Za-z_]\w*)+\s*\("
                          r"|return\s+function\s*\("
                          r"|[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*|\s*\[[^\]\n]*\])+\s*=\s*function\s*\()")


def tree_parents(funcs):
    """Index of each function's parent. luac lists a function before the functions nested in it and
    states how many it nests, which is the whole tree."""
    parents, stack = [None] * len(funcs), []
    for index, fn in enumerate(funcs):
        while stack and stack[-1][1] == 0:
            stack.pop()
        if stack:
            parents[index] = stack[-1][0]
            stack[-1][1] -= 1
        stack.append([index, fn.kids])
    return parents


def span_of(fn):
    return fn.end - fn.start + 1


def find_wrappers(funcs, parents, code, lines):
    """Indexes of the factory wrappers (see the module docstring)."""
    candidates = [index for index in range(1, len(funcs))
                  if parents[index] == 0 and span_of(funcs[index]) >= WRAPPER_SHARE * lines]
    if not candidates:
        return []
    code_lines = code.split("\n")
    found = []
    for index in candidates:
        fn = funcs[index]
        if not 1 <= fn.start <= len(code_lines) or not WRAPPER_FORM.match(code_lines[fn.start - 1]):
            continue
        nested = [span_of(other) for position, other in enumerate(funcs) if parents[position] == index]
        if len(nested) >= WRAPPER_MIN_FUNCTIONS and sum(nested) >= WRAPPER_FUNCTION_SHARE * span_of(fn):
            found.append(index)
    return found


def function_shape(funcs, code, lines, function_limit):
    """({metric: value}, [wrapper facts], [longest functions]) of one file from its luac functions."""
    parents = tree_parents(funcs)
    wrappers = find_wrappers(funcs, parents, code, lines)
    modules = {0, *wrappers}
    spans = [(span_of(fn), fn.start, fn.end) for index, fn in enumerate(funcs) if index not in modules]
    wrapper_facts = []
    for index in wrappers:
        fn = funcs[index]
        nested = [span_of(other) for position, other in enumerate(funcs) if parents[position] == index]
        own = max(span_of(fn) - sum(nested), 0)
        spans.append((own, fn.start, fn.end))
        wrapper_facts.append((fn.start, fn.end, span_of(fn), fn.locals, fn.slots, own, max(nested)))
    spans.sort(reverse=True)
    shape = {
        "max_function": spans[0][0] if spans else 0,
        "long_functions": sum(1 for span, _, _ in spans if span > function_limit),
        "main_locals": max(funcs[index].locals for index in modules),
        "max_locals": max((fn.locals for index, fn in enumerate(funcs) if index not in modules), default=0),
        "max_upvalues": max(fn.upvalues for fn in funcs),
        "max_slots": max(fn.slots for fn in funcs),
    }
    return shape, wrapper_facts, spans[:3]


def limit_shape(funcs):
    """The four compiler-limit metrics of a file that is measured for nothing else (a data file)."""
    return {
        "main_locals": funcs[0].locals,
        "max_locals": max((fn.locals for fn in funcs[1:]), default=0),
        "max_upvalues": max(fn.upvalues for fn in funcs),
        "max_slots": max(fn.slots for fn in funcs),
    }


# ------------------------------------------------------------------ source scan
SCAN = re.compile(r"--\[(=*)\[|--[^\n]*|\[(=*)\[|\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'", re.S)
G_NAME = re.compile(r"(?<![\w.])_G\s*\.\s*[A-Za-z_]\w*(\s*=(?!=))?")
G_INDEX = re.compile(r"(?<![\w.])_G\s*\[[^\]\n]*\](\s*=(?!=))?")
G_RAWGET = re.compile(r"\brawget\s*\(\s*_G\b")
TYPE_GUARD = re.compile(r"\btype\s*\([^\n]{0,200}?\)\s*[=~]=\s*\"function\"|\"function\"\s*[=~]=\s*type\s*\(")
LOOKUP = r"[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*|\s*\[[^\]\n]*\])*"
OR_FUNCTION = re.compile(r"\bor\s+function\s*\(")
FALLBACK_HEAD = re.compile(
    r"(?:\blocal\s+|[{,]\s*)[A-Za-z_]\w*\s*=\s*\(?\s*(?:type\s*\([^()\n]*\)\s*[=~]=\s*\"function\"\s+and\s+)?"
    + LOOKUP + r"\s+$")
FALLBACK_REACH = 240
CLIENT_WORD = re.compile(r"(?<!\w)Client\b(?!\s*[.\[(:])")
SELECT_TAIL = re.compile(r"select\s*\(\s*2\s*,\s*\.\.\.\s*\)$")
CLIENT_AFTER_NIL = re.compile(r"\s+(?:and|or)\b|\s*[=~]=\s*nil\b")
CLIENT_BEFORE_NOT = re.compile(r"\bnot\s+\(?\s*$")
CLIENT_BEFORE_TYPE = re.compile(r"\btype\s*\(\s*$")
CLIENT_BEFORE_IF = re.compile(r"\b(?:if|elseif)\s+\(?\s*$")
STRUCTURE = re.compile(r"\b(?:function|if|do|repeat|end|until)\b|[{};]")
TRIVIAL = {"end", "else", "end)", "end,", "}", "},", "})", "return", "do", "then", "))", "),", ")", "{"}
WHITESPACE = re.compile(r"\s+")


def strip_source(text):
    """(code, plain): code has comments removed and string contents emptied
    (a "function" string survives for the type-guard match); plain has only the
    comments removed. Both keep every line break."""
    code, plain, position = [], [], 0
    for match in SCAN.finditer(text):
        start, end = match.span()
        if start < position:
            continue
        gap = text[position:start]
        code.append(gap)
        plain.append(gap)
        token = match.group(0)
        if token.startswith("--"):
            if match.group(1) is not None:
                close = text.find("]" + match.group(1) + "]", end)
                end = len(text) if close < 0 else close + len(match.group(1)) + 2
                breaks = "\n" * text.count("\n", start, end)
                code.append(breaks)
                plain.append(breaks)
            position = end
            continue
        if match.group(2) is not None:
            close = text.find("]" + match.group(2) + "]", end)
            end = len(text) if close < 0 else close + len(match.group(2)) + 2
            body = text[start:end]
            code.append('""' + "\n" * body.count("\n"))
            plain.append(body)
            position = end
            continue
        code.append('"function"' if token[1:-1] == "function" else '""')
        plain.append(token)
        position = end
    gap = text[position:]
    code.append(gap)
    plain.append(gap)
    return "".join(code), "".join(plain)


def semicolon_lines(code):
    """Lines holding a `;` that separates statements. A `;` directly inside a
    table constructor separates fields and does not count."""
    if ";" not in code:
        return 0
    stack, lines = [], set()
    for match in STRUCTURE.finditer(code):
        token = match.group(0)
        if token == ";":
            if not stack or stack[-1] != "{":
                lines.add(code.count("\n", 0, match.start()))
        elif token == "{":
            stack.append("{")
        elif token == "}":
            if stack and stack[-1] == "{":
                stack.pop()
        elif token in ("end", "until"):
            if stack and stack[-1] != "{":
                stack.pop()
        else:
            stack.append(token)
    return len(lines)


def g_read_offsets(code):
    offsets = [match.start() for pattern in (G_NAME, G_INDEX) for match in pattern.finditer(code)
               if match.group(1) is None]
    return offsets + [match.start() for match in G_RAWGET.finditer(code)]


def type_guard_offsets(code):
    return [match.start() for match in TYPE_GUARD.finditer(code)]


def fallback_lambda_offsets(code):
    """Offsets of the `or function(` of every `local X = lookup or function(` (also `X = lookup or function(` as
    a table field): the head is checked only in front of each `or function(`, which keeps the scan cheap."""
    return [match.start() for match in OR_FUNCTION.finditer(code)
            if FALLBACK_HEAD.search(code, max(0, match.start() - FALLBACK_REACH), match.start())]


def client_reference_start(code, position):
    """Where the reference that ends in `Client` at `position` begins (`Client`, `MSUF.Client`, `a.b.Client`,
    `select(2, ...).Client`), or None when it hangs off anything else (`f().Client`)."""
    start = position
    while start > 0 and code[start - 1] == ".":
        end = start - 1
        begin = end
        while begin > 0 and (code[begin - 1].isalnum() or code[begin - 1] == "_"):
            begin -= 1
        if begin < end:
            start = begin
            continue
        select = SELECT_TAIL.search(code, max(0, end - 40), end)
        return select.start() if select else None
    return start


def client_guard_offsets(code):
    """Offsets of every use of the client table as a value that may be nil: the reference is followed by
    and/or or a comparison with nil, or preceded by `not`, `type(`, `if` or `elseif`. A read of a member
    (`MSUF.Client.IsForever`) is no guard."""
    offsets = []
    if "Client" not in code:
        return offsets
    for match in CLIENT_WORD.finditer(code):
        start = client_reference_start(code, match.start())
        if start is None:
            continue
        after = code[match.end():match.end() + 24]
        before = code[max(0, start - 24):start]
        if (CLIENT_AFTER_NIL.match(after) or CLIENT_BEFORE_NOT.search(before)
                or (CLIENT_BEFORE_TYPE.search(before) and re.match(r"\s*\)", after))
                or (CLIENT_BEFORE_IF.search(before) and re.match(r"\s*\)?\s*then\b", after))):
            offsets.append(start)
    return offsets


OFFSETS = {"g_reads": g_read_offsets, "type_guards": type_guard_offsets,
           "fallback_lambdas": fallback_lambda_offsets, "client_guards": client_guard_offsets}


# PLAN-10 C5 (2026-10-24): cross-file module preludes are dependency wiring,
# not copied feature logic. Exclude only a consecutive file prefix made of
# namespace unpacking, simple aliases/constants, Require imports, and early
# capability guards. A named MSUF.Auras3RuntimeFactories.<module> assignment
# introduces a module body: skip its header and consecutive import aliases too.
# Stop at any other function, nonempty table, or other call.
# Both this ratchet and scorecard use this rule; no arbitrary line cutoff.
PRELUDE_ATOM = r'(?:\(?[\w.]+\)?|\.\.\.|"[^"\n]*"|\{\})'
PRELUDE_VALUE = PRELUDE_ATOM + r'(?:\s+(?:or|and)\s+' + PRELUDE_ATOM + r')*'
PRELUDE_LINE = re.compile(
    r'^(?:local\s+[\w, ]+\s*=\s*(?:' + PRELUDE_VALUE + r'(?:,\s*' + PRELUDE_VALUE + r')*'
    + r'|select\(2,\s*\.\.\.\)|[\w.]+\.Require\([^\n]*\))'
    + r'|[\w.]+\s*=\s*' + PRELUDE_VALUE
    + r'|if\s+(?:not\s+)?[\w.]+\s+then\s+return\s+end)$')


# Cold dependency declarations only: assert(dotted.namespace, literal message)
# or assert(MSUF.Require(literal, literal).Identifier). No arbitrary nested
# call, fallback, indexing, arithmetic or dynamic argument is an import.
PRELUDE_IMPORT_LITERAL = r"(?:\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')"
PRELUDE_IMPORT_ASSERT = re.compile(
    r"^local\s+[A-Za-z_]\w*\s*=\s*assert\s*\(\s*(?:"
    r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+\s*,\s*" + PRELUDE_IMPORT_LITERAL
    + r"|MSUF\.Require\s*\(\s*" + PRELUDE_IMPORT_LITERAL + r"\s*,\s*"
    + PRELUDE_IMPORT_LITERAL + r"\s*\)\.[A-Za-z_]\w*)\s*\)$")


def clone_source_lines(plain):
    kept, prelude = [], True
    for number, line in enumerate(plain.split("\n"), 1):
        text = " ".join(line.split())
        if not text:
            continue
        if prelude and (PRELUDE_LINE.fullmatch(text) or PRELUDE_IMPORT_ASSERT.fullmatch(text) or re.fullmatch(
                r'MSUF\.Auras3RuntimeFactories\.\w+ = function\([\w, ]*\)', text)):
            continue
        prelude = False
        if len(text) > 3 and text not in TRIVIAL:
            kept.append((number, text))
    return kept


def normalized_lines(plain):
    return [line for _, line in clone_source_lines(plain)]


def window_hashes(kept):
    return [hashlib.md5("\n".join(kept[i:i + WINDOW]).encode("utf-8", "replace")).digest()[:8]
            for i in range(len(kept) - WINDOW + 1)]


def scan_source(text):
    """Metrics that need only the source: ({metric: value}, window hashes, code)."""
    text = text.replace("\r\n", "\n").lstrip("\ufeff")
    code, plain = strip_source(text)
    raw_lines = text.split("\n")
    metrics = {
        "lines": text.count("\n") + (0 if text.endswith("\n") or not text else 1),
        "g_reads": len(g_read_offsets(code)),
        "type_guards": len(type_guard_offsets(code)),
        "fallback_lambdas": len(fallback_lambda_offsets(code)),
        "client_guards": len(client_guard_offsets(code)),
        "semicolon_lines": semicolon_lines(code),
        "long_lines": sum(1 for line in raw_lines if len(line) > LONG_LINE),
    }
    return metrics, window_hashes(normalized_lines(plain)), code


def analyze_source(text):
    """Metrics that need only the source: ({metric: value}, window hashes)."""
    metrics, hashes, _ = scan_source(text)
    return metrics, hashes


def locate(root, rel, metric):
    """1-based line numbers of the occurrences a located defect metric counts in a file."""
    text = (root / rel).read_bytes().decode("utf-8", "replace").replace("\r\n", "\n").lstrip("\ufeff")
    code, _ = strip_source(text)
    return sorted({code.count("\n", 0, offset) + 1 for offset in OFFSETS[metric](code)})


def added_lines(root, rel):
    """Line numbers this working tree added to a file (git diff against HEAD), or None when git cannot say."""
    try:
        run = subprocess.run(["git", "diff", "--no-color", "--unified=0", "HEAD", "--", rel], cwd=str(root),
                             capture_output=True, text=True, errors="replace")
    except OSError:
        return None
    if run.returncode != 0:
        return None
    lines = set()
    for hunk in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", run.stdout, re.M):
        start, count = int(hunk.group(1)), int(hunk.group(2) or 1)
        lines.update(range(start, start + count))
    return lines


def format_lines(found, fresh):
    """The lines of a failure: the ones this working tree added when git knows them, else the first ones."""
    shown, label = (fresh, "added at line") if fresh else (found, "at line")
    if not shown:
        return ""
    return "; %s%s %s%s" % (label, "s" if len(shown) > 1 else "", ", ".join(str(n) for n in shown[:SHOWN_LINES]),
                            " and %d more" % (len(shown) - SHOWN_LINES) if len(shown) > SHOWN_LINES else "")


def make_locator(root):
    """where(rel, metric) for evaluate(): the lines of a located defect metric, called for a failure only."""
    added = {}

    def where(rel, metric):
        found = locate(root, rel, metric)
        if rel not in added:
            added[rel] = added_lines(root, rel) or set()
        return format_lines(found, [number for number in found if number in added[rel]])

    return where


# ------------------------------------------------------------------ file selection
def load_json(path, default):
    if not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def declared_data(root, profile_name, allowlist):
    patterns = dict(allowlist.get(DATA_NOTE, {}))
    if profile_name == "suite":
        structure = load_json(root / SUITE_STRUCTURE_ALLOWLIST, {})
        for rel, reason in structure.get("size_exempt", {}).items():
            patterns[rel] = reason
    return patterns


def product_files(root, profile, data_patterns):
    """(measured rel paths, excluded {rel: reason}) of the profile's addons."""
    measured, excluded = [], {}
    own_libs = set(profile.get("own_libs", ()))
    for addon in sorted(os.listdir(root)):
        folder = root / addon
        if not profile["addon"](addon) or not folder.is_dir():
            continue
        for dirpath, dirs, names in os.walk(folder):
            if os.path.basename(dirpath) == "Libs":
                # Vendor libraries are not measured; the folders the profile owns are MSUF code.
                dirs[:] = sorted(d for d in dirs if d in own_libs)
                continue
            dirs[:] = sorted(dirs)
            for name in sorted(names):
                if not name.endswith(".lua"):
                    continue
                path = Path(dirpath) / name
                rel = path.relative_to(root).as_posix()
                reason = next((why for pattern, why in sorted(data_patterns.items())
                               if fnmatch.fnmatchcase(rel, pattern)), None)
                if reason is None:
                    measured.append(rel)
                else:
                    excluded[rel] = reason
    return measured, excluded


def detect_profile(root):
    for name, profile in PROFILES.items():
        if (root / profile["marker"]).is_dir():
            return name
    raise SystemExit("FAIL no Suite or Classic addon folder under %s" % root)


def measure(root, profile_name, allowlist, luac):
    """(results, window counts, excluded, clone locations, details, data limits) of the profile's files.
    The data limits are the compiler-limit metrics of the declared data files."""
    profile = PROFILES[profile_name]
    rels, excluded = product_files(root, profile, declared_data(root, profile_name, allowlist))
    results, window_counts, locations, details, scanned = {}, {}, {}, {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        # luac runs in other processes while this one reads and scans the sources.
        listing = pool.submit(luac_facts, luac, root, rels + sorted(excluded))
        for rel in rels:
            scanned[rel] = scan_source((root / rel).read_bytes().decode("utf-8", "replace"))
        facts = listing.result()
    for rel in rels:
        metrics, hashes, code = scanned[rel]
        shape, wrappers, longest = function_shape(facts[rel], code, metrics["lines"], profile["function_limit"])
        metrics.update(shape)
        results[rel] = metrics
        details[rel] = {"wrappers": wrappers, "longest": longest}
        window_counts[rel] = len(hashes)
        for index, digest in enumerate(hashes):
            locations.setdefault(digest, []).append((rel, index))
    for rel in rels:
        results[rel]["clone_windows"] = 0
    for places in locations.values():
        if len(places) > 1:
            for rel, _ in places:
                results[rel]["clone_windows"] += 1
    data_limits = {rel: limit_shape(facts[rel]) for rel in sorted(excluded)}
    return results, window_counts, excluded, locations, details, data_limits


def clone_partners(locations, rel, count=3):
    """The files that hold the other copies of this file's cloned windows, most shared first."""
    shared = {}
    for places in locations.values():
        if len(places) > 1 and any(name == rel for name, _ in places):
            for name, _ in places:
                if name != rel:
                    shared[name] = shared.get(name, 0) + 1
    ranked = sorted(shared.items(), key=lambda item: (-item[1], item[0]))[:count]
    return ", ".join("%s (%d)" % pair for pair in ranked) or "other places in the same file"


# ------------------------------------------------------------------ baseline and allowlist
def baseline_from(results, profile_name):
    return {"about": "Generated by tools/quality_ratchet.py --update; do not edit by hand. Per file, "
                     "in the order of 'metrics'; a file may only get better (see the tool docstring).",
            "profile": profile_name, "metrics": list(METRICS),
            "files": {rel: [values[m] for m in METRICS] for rel, values in sorted(results.items())}}


def write_baseline(path, baseline):
    lines = ["{", ' "about": %s,' % json.dumps(baseline["about"]),
             ' "profile": %s,' % json.dumps(baseline["profile"]),
             ' "metrics": %s,' % json.dumps(baseline["metrics"]), ' "files": {']
    items = sorted(baseline["files"].items())
    for index, (rel, values) in enumerate(items):
        lines.append("  %s: %s%s" % (json.dumps(rel), json.dumps(values), "," if index < len(items) - 1 else ""))
    lines += [" }", "}"]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def read_baseline(path):
    """({file: {metric: value}}, metrics this tool measures that the baseline has no column for)."""
    if not path.is_file():
        return None, []
    data = json.loads(path.read_text(encoding="utf-8"))
    names = data["metrics"]
    return ({rel: dict(zip(names, values)) for rel, values in data["files"].items()},
            [metric for metric in METRICS if metric not in names])


def allowlist_state(allowlist, known_files):
    """(valid entries, malformed-entry problems, orphan problems). Only a valid entry covers a
    regression: one without a reason, a date, an integer max, a known metric or a unique
    file/metric pair covers nothing and blocks --update."""
    entries = allowlist.get("allowed", [])
    counts = {}
    for entry in entries:
        key = (entry.get("file"), entry.get("metric"))
        counts[key] = counts.get(key, 0) + 1
    valid, malformed, orphans, reported = [], [], [], set()
    for entry in entries:
        key = (entry.get("file"), entry.get("metric"))
        label = "allowlist entry %s %s" % key
        problems = []
        if counts[key] > 1 and key not in reported:
            problems.append("%s is listed twice" % label)
        reported.add(key)
        if entry.get("metric") not in METRICS:
            problems.append("%s names an unknown metric (known: %s)" % (label, ", ".join(METRICS)))
        if not isinstance(entry.get("max"), int) or isinstance(entry.get("max"), bool):
            problems.append("%s needs an integer max" % label)
        if not str(entry.get("reason", "")).strip():
            problems.append("%s needs a reason" % label)
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(entry.get("date", ""))):
            problems.append("%s needs a date (YYYY-MM-DD)" % label)
        if problems or counts[key] > 1:
            malformed.extend(problems)
        elif entry.get("file") not in known_files:
            orphans.append("%s names a file the ratchet does not measure; remove it" % label)
        else:
            valid.append(entry)
    return valid, malformed, orphans


def vanished_files(root, baseline, results, excluded):
    """Files the baseline measured that are still on disk but no longer measured. A file that
    was deleted or renamed is gone from disk and is no failure."""
    return ["%s: measured by the baseline but no longer measured (%s); remove the declaration or rebaseline "
            "with --update --accept-regressions" % (rel, excluded.get(rel, "outside the measured addons"))
            for rel in sorted(baseline) if rel not in results and (root / rel).is_file()]


def size_limit(profile, metric):
    """The profile limit of a size metric, or None when the metric is report-only (or a defect metric)."""
    return profile["limits"].get(metric) if metric in SIZE_METRICS else None


def evaluate(results, window_counts, baseline, allowlist, profile, locations=None, where=None,
             data_limits=None):
    """(failures, improved files, new files, stale entries) of one check. `where(rel, metric)` names the
    lines of a located defect metric; it is only called for a failure. A data file has no baseline: it
    stays within the profile limits of the compiler-limit metrics."""
    allowed = {(e["file"], e["metric"]): e["max"] for e in allowlist.get("allowed", [])
               if isinstance(e.get("max"), int)}
    failures, improved, new, used = [], [], [], set()

    def partners(rel):
        return "; shares windows with " + clone_partners(locations, rel) if locations else ""

    def lines_of(rel, metric):
        return where(rel, metric) if where is not None and metric in LOCATED else ""

    def remedy(metric):
        return ". Remedy: " + REMEDIES[metric] if metric in REMEDIES else ""

    def covered(rel, metric, value):
        ceiling = allowed.get((rel, metric))
        if ceiling is not None and value <= ceiling:
            used.add((rel, metric))
            return True
        return False

    for rel in sorted(results):
        values = results[rel]
        before = baseline.get(rel)
        if before is None:
            new.append(rel)
            for metric, limit in profile["limits"].items():
                if values[metric] > limit and not covered(rel, metric, values[metric]):
                    failures.append("%s: new file has %s %d (limit %d)%s%s"
                                    % (rel, metric, values[metric], limit, lines_of(rel, metric), remedy(metric)))
            share = values["clone_windows"] - int(window_counts[rel] * CLONE_SHARE_NEW_FILE)
            if share > 0 and not covered(rel, "clone_windows", values["clone_windows"]):
                failures.append("%s: new file has %d clone windows of %d (limit %d percent)%s%s"
                                % (rel, values["clone_windows"], window_counts[rel],
                                   int(CLONE_SHARE_NEW_FILE * 100), partners(rel), remedy("clone_windows")))
            continue
        better = False
        for metric in METRICS:
            if metric not in before:
                continue
            limit = size_limit(profile, metric)
            if metric in SIZE_METRICS:
                # A size metric may grow up to its limit; it fails above max(baseline, limit). One
                # without a limit is report-only. It counts as better only when it left an over-limit
                # baseline behind.
                if limit is None:
                    continue
                if values[metric] > max(before[metric], limit):
                    if not covered(rel, metric, values[metric]):
                        failures.append("%s: %s %d is worse than the baseline %d (+%d) and above the limit %d%s"
                                        % (rel, metric, values[metric], before[metric],
                                           values[metric] - before[metric], limit, remedy(metric)))
                elif values[metric] < before[metric] and before[metric] > limit:
                    better = True
            elif values[metric] > before[metric]:
                if not covered(rel, metric, values[metric]):
                    failures.append("%s: %s %d is worse than the baseline %d (+%d)%s%s%s"
                                    % (rel, metric, values[metric], before[metric], values[metric] - before[metric],
                                       partners(rel) if metric == "clone_windows" else "", lines_of(rel, metric),
                                       remedy(metric)))
            elif values[metric] < before[metric]:
                better = True
        if better:
            improved.append(rel)
    for rel in sorted(data_limits or {}):
        for metric in LIMIT_METRICS:
            limit, value = profile["limits"].get(metric), data_limits[rel][metric]
            if limit is not None and value > limit and not covered(rel, metric, value):
                failures.append("%s: data file has %s %d (limit %d)%s" % (rel, metric, value, limit, remedy(metric)))
    stale = sorted(set(allowed) - used)
    return failures, improved, new, stale


# ------------------------------------------------------------------ report
def totals(results):
    return {metric: sum(values[metric] for values in results.values()) for metric in METRICS}


def worst(results, metric, count):
    ranked = sorted(results.items(), key=lambda item: (-item[1][metric], item[0]))
    return [(rel, values[metric]) for rel, values in ranked[:count] if values[metric] > 0]


def area_of(rel):
    """The part of the product a file belongs to, for the per-area summary."""
    parts = rel.split("/")
    if parts[0] == "MidnightSimpleUnitFrames_Options":
        return "Menu2" if parts[1:3] == ["Shell", "Menu2"] else "Options"
    if parts[0] == "MidnightSimpleUnitFrames":
        return parts[1] if len(parts) > 2 else "(addon root)"
    return parts[0]


def print_headroom(results, data_limits=None):
    print("headroom to the hard Lua 5.1 limits (hard limit minus the value; the profile limit keeps a margin;"
          " %d data files included):" % len(data_limits or {}))
    measured = {**results, **(data_limits or {})}
    for metric, hard in HARD_LIMITS.items():
        ranked = sorted(measured.items(), key=lambda item: (-item[1][metric], item[0]))[:3]
        text = ", ".join("%d %s" % (hard - values[metric], rel.rsplit("/", 1)[-1]) for rel, values in ranked)
        print("  %-13s hard %-3d tightest: %s" % (metric, hard, text))


def print_areas(results, details, function_limit):
    print("per area (files, longest function, functions above the limit, factory wrappers):")
    areas = {}
    for rel, values in results.items():
        area = areas.setdefault(area_of(rel), {"files": 0, "long": 0, "wrappers": 0, "max": (0, "")})
        area["files"] += 1
        area["long"] += values["long_functions"]
        area["wrappers"] += len(details[rel]["wrappers"])
        area["max"] = max(area["max"], (values["max_function"], rel))
    ordered = sorted(areas.items(), key=lambda item: (-item[1]["max"][0], item[0]))
    for name, area in ordered:
        print("  %-14s %4d files  longest %4d  >%d: %3d  wrappers %2d  %s"
              % (name, area["files"], area["max"][0], function_limit, area["long"], area["wrappers"],
                 area["max"][1].rsplit("/", 1)[-1] if area["max"][0] else ""))


def print_report(results, excluded, top, profile, details=None, data_limits=None):
    print("files measured: %d (excluded as data or generated: %d)" % (len(results), len(excluded)))
    summed = totals(results)
    print("totals: " + ", ".join("%s=%d" % (metric, summed[metric]) for metric in METRICS
                                 if metric not in SIZE_METRICS or metric == "lines"))
    report_only = [metric for metric in SIZE_METRICS if metric not in profile["limits"]]
    print("report-only size metrics (measured and baselined, never a failure): %s" % (", ".join(report_only) or "none"))
    if details is not None:
        wrappers = [(rel, wrapper) for rel in sorted(details) for wrapper in details[rel]["wrappers"]]
        print("factory wrappers measured as modules, not as functions: %d (their inner functions count)" % len(wrappers))
        for rel, (start, end, span, wrapper_locals, slots, own, inner) in sorted(
                wrappers, key=lambda item: -item[1][2])[:top]:
            print("  %5d lines, %3d locals, %3d slots  %s:%d  (own body %d lines, longest function inside %d)"
                  % (span, wrapper_locals, slots, rel, start, own, inner))
        heavy = [(rel, wrapper[5]) for rel, wrapper in wrappers if wrapper[5] > profile["function_limit"]]
        print("wrappers whose own body is above the function limit: %d%s"
              % (len(heavy), "".join("\n  %5d  %s" % (own, rel) for rel, own in sorted(heavy, key=lambda i: -i[1]))))
    print("files above the limits:")
    for metric, limit in profile["limits"].items():
        over = sorted(rel for rel, values in results.items() if values[metric] > limit)
        print("  %-16s > %-4d %3d files" % (metric, limit, len(over)))
    print_headroom(results, data_limits)
    if details is not None:
        longest = sorted(((span, rel, start, end) for rel in details for span, start, end in details[rel]["longest"]),
                         reverse=True)[:top]
        print("longest functions:")
        for span, rel, start, end in longest:
            print("  %6d  %s:%d-%d" % (span, rel, start, end))
        print_areas(results, details, profile["function_limit"])
    for metric in METRICS:
        print("worst %s:" % metric)
        for rel, value in worst(results, metric, top):
            print("  %6d  %s" % (value, rel))


# ------------------------------------------------------------------ main
def summary(profile_name, results, failures, improved, new, stale, entries):
    return ("quality ratchet (%s): %d files, %d problems, %d improved, %d new, allowlist %d entries (%d stale)%s"
            % (profile_name, len(results), len(failures), len(improved), len(new), entries, len(stale),
               "" if not improved else "; run --update to lock the improvements in"))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Per-file quality ratchet (see the module docstring).")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail on any regression (default)")
    mode.add_argument("--update", action="store_true", help="rewrite the baseline")
    mode.add_argument("--report", action="store_true", help="print totals and the worst files per metric")
    parser.add_argument("--root", default=str(DEFAULT_ROOT))
    parser.add_argument("--profile", choices=sorted(PROFILES))
    parser.add_argument("--baseline", default=None)
    parser.add_argument("--allowlist", default=None)
    parser.add_argument("--luac", default=None)
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--accept-regressions", action="store_true",
                        help="--update only: absorb regressions that have no allowlist entry")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    profile_name = args.profile or detect_profile(root)
    profile = PROFILES[profile_name]
    baseline_path = Path(args.baseline) if args.baseline else root / "tools" / BASELINE_NAME
    allowlist_path = Path(args.allowlist) if args.allowlist else root / "tools" / ALLOWLIST_NAME
    allowlist = load_json(allowlist_path, {})
    results, window_counts, excluded, locations, details, data_limits = measure(
        root, profile_name, allowlist, find_luac(args.luac))

    if args.report:
        print_report(results, excluded, args.top, profile, details, data_limits)

    baseline, missing_columns = read_baseline(baseline_path)
    valid, malformed, orphans = allowlist_state(allowlist, set(results) | set(data_limits))
    entries = len(allowlist.get("allowed", []))
    if baseline is None:
        if not args.update:
            print("FAIL no baseline at %s; create it with --update" % baseline_path)
            return 1
        baseline = {}
    if missing_columns and not args.update:
        print("FAIL the baseline has no column for %s; this tool measures more than the baseline records. "
              "Rebaseline deliberately with --update" % ", ".join(missing_columns))
        return 1

    failures, improved, new, stale = evaluate(results, window_counts, baseline, {"allowed": valid}, profile,
                                              locations, make_locator(root), data_limits)
    failures = failures + vanished_files(root, baseline, results, excluded)
    if args.update:
        if malformed:
            for problem in malformed:
                print("FAIL " + problem)
            print("quality ratchet (%s): update refused, %d malformed allowlist entries; fix them first"
                  % (profile_name, len(malformed)))
            return 1
        regressions = [f for f in failures if "new file" not in f]
        blocked = failures if not args.accept_regressions else []
        if blocked and baseline:
            for failure in blocked:
                print("FAIL " + failure)
            print("quality ratchet (%s): update refused, %d problems; add allowlist entries or pass "
                  "--accept-regressions" % (profile_name, len(blocked)))
            return 1
        write_baseline(baseline_path, baseline_from(results, profile_name))
        # The new baseline holds every value, so no entry is needed any more; the reasons
        # stay in the git history and are printed here for the commit message.
        pruned = allowlist.get("allowed", [])
        for entry in pruned:
            print("pruned: %s %s <= %s (%s, %s)" % (entry.get("file"), entry.get("metric"), entry.get("max"),
                                                    entry.get("reason"), entry.get("date")))
        if pruned:
            allowlist["allowed"] = []
            allowlist_path.write_text(json.dumps(allowlist, indent=1, ensure_ascii=False) + "\n",
                                      encoding="utf-8", newline="\n")
        print("quality ratchet (%s): baseline written for %d files (%d regressions absorbed, "
              "%d allowlist entries pruned)" % (profile_name, len(results), len(regressions), len(pruned)))
        return 0

    problems = malformed + orphans
    for problem in problems:
        print("FAIL " + problem)
    for failure in failures:
        print("FAIL " + failure)
    print(summary(profile_name, results, failures + problems, improved, new, stale, entries))
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main())
