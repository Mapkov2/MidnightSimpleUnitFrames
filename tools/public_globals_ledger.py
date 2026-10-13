"""Public-globals ledger: which of MSUF's exported global names and table fields other code actually reads.

Later 7.0 waves move most of MSUF's exported globals into the addon namespace and rename fields of its
tables. A name that something outside the core and Options addons looks up by string or by bare name, or
a field it reads off an exported table, breaks the day it changes, so this tool records the proof first:
tools/public-globals.tsv lists every exported name and table field with at least one reader outside the
two addons (or a lookup by the client itself), and who that reader is.

Modes (run from anywhere; the repository root is found from this file):

  python tools/public_globals_ledger.py            check (the default; needs nothing outside the repo)
  python tools/public_globals_ledger.py --write    rebuild the ledger from the local external sources
  python tools/public_globals_ledger.py --refresh-exporters
                                                   keep readers and evidence, re-read exporter, kind
                                                   and clients from the source and a booted client
  python tools/public_globals_ledger.py --inventory
                                                   print every name the source text exports, ledgered
                                                   or not, and the run-time export sites (--write adds
                                                   the names only a booted client shows)

Check mode verifies that the ledger is well formed and that every ledgered name still has an exporter in
MidnightSimpleUnitFrames or MidnightSimpleUnitFrames_Options, and every ledgered field a source line that
writes it. Only code vouches for a name: one left behind in a comment or a string does not. A failure names
the readers that would break. The runtime half is tools/tests/public_globals_smoke.lua: every ledgered
name and field exists after login, per client.

What counts as an export (a comment-stripped scan of the tracked addon files, vendored libraries aside, with
string contents masked so code that only appears inside a string is never an export): ExportPublic /
ExportGlobal / ExportCompat / PublishCompat calls with a literal name and their per-file aliases,
`_G.NAME =`, `_G["NAME"] =`, `rawset(_G, "NAME", ...)`, bare global assignments and `function NAME()`
definitions, CreateFrame names, XML names and the handler functions and mixins XML attributes name,
SLASH_* and BINDING_* strings, StaticPopupDialogs keys, Bindings.xml actions, TOC SavedVariables and
AddonCompartment functions. A name built at run time (`"MSUF_Nudge" .. dir`) is a run-time export site:
a name variable or naming function that resolves to MSUF literals yields exact names, any other site is
listed by --write and --inventory, and an outside reader of a name only such a site can build is ledgered
against that site. Names found only by booting each client (public_globals_smoke.lua --inventory) are added
too, which is also where the `clients` column comes from.

What counts as a reader (--write only; everything is read-only): in the Suite, MapkoSkin and
MidnightCooldownManager repositories and in every other addon installed under the WoW client folders, a
bare global read (the compiler's GETGLOBAL, so a local of the same name is not one), `_G.NAME`,
`_G["NAME"]`, rawget(_G, "NAME"), getglobal("NAME"), or a quoted string equal to an MSUF-looking name. A
quoted prefix that can build an exported name becomes a `dynamic` row. A field read off a local that holds
an exported table (`local host = _G.MSUF_NS ... host.MSUF_Auras3`, `local menu = assert(_G.MSUF2)`, an
accessor function returning one) is a `nsfield` row, `MSUF_NS.MSUF_Auras3`; it is never a read of a global of
that name. A field counts only when a source line writes it or a booted client holds it.

Ledger columns: name, kind, exporter, consumers, readers, addons, evidence, clients, note.
  kind       function table frame value savedvar slash popup binding dynamic nsfield
  exporter   path:line of the first exporter (for a nsfield, the first line that writes it)
  consumers  up to three addon:file:line readers separated by "|", one per reading file
  readers    reading files in total; addons: distinct reading addons
  evidence   external suite integration sv blizzard-contract (comma separated when several hold)
  clients    "all", a comma list of Mainline Vanilla TBC Mists Forever the booted client had the
             name on, or "static" (not reachable offline; the exporter text is the proof)
  note       dynamic (built at run time), listed (a table-driven export), prefix (a dynamic row), or empty
"""
import argparse
import bisect
import collections
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")
LEDGER = os.path.join(ROOT, "tools", "public-globals.tsv")
COLUMNS = ("name", "kind", "exporter", "consumers", "readers", "addons", "evidence", "clients", "note")
KINDS = frozenset("function table frame value savedvar slash popup binding dynamic nsfield".split())
EVIDENCE = ("blizzard-contract", "sv", "suite", "external", "integration")
FLAVORS = ("Mainline", "Vanilla", "TBC", "Mists", "Forever")
SHOWN = 3
RUNTIME_SMOKE = "tools/tests/public_globals_smoke.lua"

# Globals the addon writes that belong to the wider addon ecosystem, not to MSUF.
FOREIGN_GLOBALS = frozenset(("LibStub", "ClickCastFrames", "SlashCmdList"))

DEFAULT_SUITE_REPO = r"C:\MSUF Beta Branch\MSUF-Suite"
DEFAULT_REPOS = (
    r"C:\MSUF Beta Branch\MapkoSkin",
    r"C:\MSUF Beta Branch\MidnightCooldownManager",
)
DEFAULT_WOW_ROOT = r"E:\World of Warcraft"
DEFAULT_LUA = r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe"
# Client folders in the order whose copy of a file wins when several have it.
CLIENT_FOLDERS = ("_retail_", "_ptr_", "_xptr_", "_beta_", "_classic_", "_classic_beta_",
                  "_classic_ptr_", "_classic_era_", "_classic_era_ptr_", "_anniversary_")
# Installed addons that are copies of a repository scanned directly, or MSUF's own.
SKIPPED_INSTALLED = re.compile(
    r"^(?:MidnightSimpleUnitFrames|MSUF_Suite|MapkoSkin|MidnightSkin|MidnightCooldownManager)")

LUA_STDLIB = frozenset("""
_G _VERSION assert collectgarbage dofile error getfenv getmetatable ipairs load
loadfile loadstring module next pairs pcall print rawequal rawget rawset require
select setfenv setmetatable tonumber tostring type unpack xpcall
coroutine debug io math os package string table
""".split())


class LedgerError(Exception):
    pass


def fail(message):
    print("public globals ledger FAILED: " + message)
    raise SystemExit(1)


# --------------------------------------------------------------------------------------
# Text helpers
# --------------------------------------------------------------------------------------

def read_text(path):
    with io.open(path, "r", encoding="utf-8", errors="replace", newline="") as handle:
        return handle.read().replace("\r\n", "\n")


# One pass that keeps strings and drops comments. A long comment is tried before a line
# comment, and strings are consumed whole, so a "--" inside one is never taken for a comment.
LUA_SCAN = re.compile(
    r"--\[(?P<ce>=*)\[.*?\](?P=ce)\]"
    r"|--[^\n]*"
    r"|\[(?P<se>=*)\[.*?\](?P=se)\]"
    r"|\"(?:\\[\s\S]|[^\\\"\n])*\""
    r"|'(?:\\[\s\S]|[^\\'\n])*'",
    re.S)


def strip_comments(text):
    """The text with every comment blanked and its line breaks kept."""
    return strip_and_mask(text)[0]


def fill(piece, char):
    """The piece with every character but its line breaks replaced."""
    return "\n".join([char * len(part) for part in piece.split("\n")])


def strip_and_mask(text):
    """(stripped, masked): comments blanked, and for masked also every string's contents replaced by filler.

    Both keep the offsets and line breaks of the text, so a position in one is the position in the other.
    Matching on the masked text means code that only appears inside a string is never taken for code;
    the literal a match names is read back from the stripped text.
    """
    stripped, masked, position = [], [], 0
    for match in LUA_SCAN.finditer(text):
        start, end = match.span()
        if start > position:
            plain = text[position:start]
            stripped.append(plain)
            masked.append(plain)
        piece = text[start:end]
        multiline = "\n" in piece
        if piece[0] == "-":
            blank = fill(piece, " ") if multiline else " " * (end - start)
            stripped.append(blank)
            masked.append(blank)
        else:
            stripped.append(piece)
            filler = fill(piece[1:-1], "x") if multiline else "x" * (end - start - 2)
            masked.append(piece[0] + filler + piece[-1])
        position = end
    tail = text[position:]
    stripped.append(tail)
    masked.append(tail)
    return "".join(stripped), "".join(masked)


def brace_depths(masked):
    """Table-constructor depth at every offset of a masked text."""
    depth, out = 0, []
    for char in masked:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        out.append(depth)
    return out


class Lines:
    """Offset -> line number for one text."""

    def __init__(self, text):
        self.starts = [0] + [m.end() for m in re.finditer("\n", text)]

    def of(self, offset):
        return bisect.bisect_right(self.starts, offset)


# --------------------------------------------------------------------------------------
# Source inventory
# --------------------------------------------------------------------------------------

NAME = r"[A-Za-z_][A-Za-z0-9_]*"
NAME_ONLY = re.compile(r"^%s$" % NAME)
NAME_START = re.compile(NAME)
QUOTED = r"(?P<q>[\"'])(?P<s>%s)(?P=q)" % NAME
# Functions that publish a global by name. A per-file alias or wrapper is found next to its
# definition (`local Export = MSUF.ExportPublic`, `local function Publish(name, value) _G[name] = ...`).
EXPORT_FUNCTIONS = ("ExportPublic", "ExportGlobal", "ExportCompat", "MSUF_ExportPublic",
                    "MSUF_ExportCompat", "HostExportPublic", "PublishCompat")
# Every pattern below starts with a literal, so the regex engine finds candidates with a fast search
# instead of trying each position; a boundary that a lookbehind would check is checked in Python.
ALIAS_DEF = re.compile(
    r"local[ \t]+(?:function[ \t]+)?(%s)[ \t]*(?:=|\()[^\n]*?"
    r"\b(?:ExportPublic|ExportGlobal|ExportCompat|MSUF_ExportPublic|MSUF_ExportCompat)\b" % NAME)
WRAPPER_WRITE = re.compile(r"_G\[[ \t]*name[ \t]*\][ \t]*=(?!=)")
WRAPPER_HEAD = re.compile(r"local[ \t]+function[ \t]+(%s)[ \t]*\([ \t]*name[ \t]*,[^)]*\)" % NAME)
G_ALIAS = re.compile(r"local[ \t]+(%s)[ \t]*=[ \t]*_G[ \t]*(?:\n|;|$)" % NAME)
# Prefixes a bare global assignment may carry. Anything else assigned without `local` would be
# an accidental leak, which tools/tests/unresolved_global_reads_smoke.py already rejects.
BARE_NAME = r"(?:_?_?MSUF|SLASH_|BINDING_)[A-Za-z0-9_]*"
BARE_NAME_ONLY = re.compile(r"^%s$" % BARE_NAME)
GLOBAL_FUNCTION = re.compile(r"function[ \t]+(%s)[ \t]*\(" % BARE_NAME)
GLOBAL_ASSIGN = tuple(re.compile(r"(%s[A-Za-z0-9_]*)[ \t]*=(?!=)" % lead) for lead in ("MSUF", "SLASH_", "BINDING_"))
CREATE_FRAME = re.compile(r"CreateFrame\([ \t]*[\"']\w+[\"'][ \t]*,[ \t]*" + QUOTED + r"(?![ \t]*\.\.)")
POPUP_INDEX = re.compile(r"StaticPopupDialogs\[[ \t]*" + QUOTED + r"[ \t]*\][ \t]*=(?!=)")
POPUP_FIELD = re.compile(r"StaticPopupDialogs\.(%s)[ \t]*=(?!=)" % NAME)
# Fields of the addon namespace that carry a global-style name: the Suite reads them as host.MSUF_X.
NS_BASES = ("MSUF", "ns", "NS")
NS_FIELD = {base: re.compile(base + r"\.(MSUF_[A-Za-z0-9_]*)[ \t]*=(?!=)") for base in NS_BASES}
NS_FUNCTION = {base: re.compile(r"function[ \t]+" + base + r"\.(MSUF_[A-Za-z0-9_]*)[ \t]*\(") for base in NS_BASES}
SPECIAL_FRAME = tuple(re.compile(head + r"\([ \t]*UISpecialFrames[ \t]*,[ \t]*" + QUOTED)
                      for head in (r"tinsert", r"table\.insert"))
FUNCTION_DEF = re.compile(r"function[ \t]+(%s)[ \t]*\(" % NAME)
TABLE_LOCAL = re.compile(r"local[ \t]+(%s)[ \t]*=[ \t]*\{" % NAME)
# Sites that publish a name built at run time (`PFX .. unit .. SFX`): the source cannot spell the name,
# but it vouches for every name of that shape. Matched on the masked text, where a string is `"xxxx"`.
PREFIXED = r"(?P<q>[\"'])(?P<p>x*)(?P=q)[ \t]*\.\.[ \t]*(?P<rest>[^,)\n]*)"
PREFIXED_KEY = PREFIXED.replace(r"[^,)\n]*", r"[^\]\n]*")
TRAILING_LITERAL = re.compile(r"\.\.[ \t]*(?P<q>[\"'])(?P<s>x*)(?P=q)[ \t]*$")


class Family:
    """A run-time export site: the name is a literal prefix and suffix around an expression."""

    def __init__(self, line, via, prefix, suffix, expr):
        self.line, self.via, self.prefix, self.suffix, self.expr = line, via, prefix, suffix, expr
        # `ExportPublic(name, value)` inside a wrapper passes a caller's name through; it names nothing.
        self.passthrough = not (prefix or suffix) and bool(NAME_ONLY.match(expr))

    def matches(self, name):
        """A family with neither literal part could be any name, so it vouches for none."""
        return bool(self.prefix or self.suffix) and "MSUF" in name and name.startswith(self.prefix) \
            and name.endswith(self.suffix) and len(name) > len(self.prefix) + len(self.suffix) \
            and bool(NAME_ONLY.match(name))

    def describe(self):
        return "%s%s%s" % ('"%s" .. ' % self.prefix if self.prefix else "", self.expr or "?",
                           ' .. "%s"' % self.suffix if self.suffix else "")

# Site preference: a real export call beats a fallback write beats a frame or XML name.
RANK = {"export": 0, "function": 1, "assign": 2, "global": 3, "frame": 4, "builder": 4, "xml": 5,
        "popup": 6, "special": 6, "toc": 7, "runtime": 8, "nsfield": 9}


class Entry:
    """One exported global: every place that writes it, and what the client says about it."""

    def __init__(self, name):
        self.name = name
        self.sites = []              # (rank, path, line, via)
        self.kinds = set()           # static kind hints: function table frame popup savedvar binding
        self.runtime = {}            # flavor -> final type, for a global of a booted client
        self.ns_runtime = {}         # flavor -> final type, for a field of the addon namespace
        self.frame = False           # a widget in a booted client
        self.special = False         # looked up by name through UISpecialFrames
        self.contract = []           # (pseudo file, line, path): where the client itself looks the name up
        self.dynamic = False         # the exporter builds the name at run time
        self.listed = False          # no export call spells the name, but the exporter file lists it as a literal

    def add(self, rank, path, line, via, kind=None):
        self.sites.append((rank, path, line, via))
        if kind:
            self.kinds.add(kind)

    def primary(self):
        return sorted(self.sites)[0] if self.sites else None

    def primary_global(self):
        sites = sorted(site for site in self.sites if site[3] != "nsfield")
        return sites[0] if sites else None

    def namespace_only(self):
        """Published as a field of the addon namespace (`MSUF.MSUF_X = ...`) and never as a global."""
        if self.runtime:
            return False
        if self.sites:
            return all(site[3] == "nsfield" for site in self.sites)
        return bool(self.ns_runtime)


def addon_files(root=ROOT):
    """Tracked Lua/XML/TOC files of both addons, sorted (the files on disk when root is not a git checkout)."""
    suffixes = (".lua", ".xml", ".toc")
    listed = subprocess.run(["git", "-C", root, "ls-files", "-z", "--"] + list(ADDONS),
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    found = []
    if listed.returncode == 0:
        found = [rel for rel in listed.stdout.decode("utf-8").split("\0") if rel.lower().endswith(suffixes)]
    if not found:
        for addon in ADDONS:
            for current, dirs, files in os.walk(os.path.join(root, addon)):
                dirs[:] = [d for d in dirs if d != ".git"]
                for name in files:
                    if name.lower().endswith(suffixes):
                        found.append(os.path.relpath(os.path.join(current, name), root).replace("\\", "/"))
    if not found:
        raise LedgerError("no addon files found under " + root)
    found.sort()
    return found


def vendored(rel):
    """Third-party libraries (LibStub, LibSharedMedia, CallbackHandler) are not MSUF's exports."""
    parts = rel.split("/")
    return len(parts) > 2 and parts[1] == "Libs" and parts[2] != "MSUFUnitFrames"


def word_before(text, start):
    """Is the character before start part of a name?"""
    return start > 0 and (text[start - 1].isalnum() or text[start - 1] == "_")


def field_before(text, start):
    """Is the match the field of something (`x.NAME`) or the tail of a longer name?"""
    return start > 0 and (text[start - 1].isalnum() or text[start - 1] in "_.")


def at_line_start(text, start):
    """Only blanks between the start of the line and the match."""
    return not text[text.rfind("\n", 0, start) + 1:start].strip(" \t")


def guess_kind(masked, offset, facts):
    """function / table / value for the expression after an export call or assignment."""
    tail = masked[offset:offset + 400].lstrip(" \t),")
    if tail.startswith("function") and not tail[8:9].isalnum():
        return "function"
    if tail.startswith("{"):
        return "table"
    if tail[:1] in ("\"", "'") or re.match(r"true\b|false\b|nil\b|-?\d", tail):
        return "value"
    ident = re.match(NAME, tail)
    if ident:
        if ident.group(0) in facts.functions():
            return "function"
        if ident.group(0) in facts.tables():
            return "table"
    return None


class Facts:
    """Names a file defines as functions or as table locals, found on first use."""

    def __init__(self, masked):
        self.masked = masked
        self.found = {}

    def functions(self):
        if "functions" not in self.found:
            self.found["functions"] = set(FUNCTION_DEF.findall(self.masked))
        return self.found["functions"]

    def tables(self):
        if "tables" not in self.found:
            self.found["tables"] = set(TABLE_LOCAL.findall(self.masked))
        return self.found["tables"]


def scan_lua(rel, text, exports, dynamic):
    stripped, masked = strip_and_mask(text)
    facts = Facts(masked)

    def line_of(offset):
        return masked.count("\n", 0, offset) + 1

    def record(name, offset, via, kind=None, tail=None):
        if name in FOREIGN_GLOBALS or not NAME_ONLY.match(name):
            return
        entry = exports.get(name)
        if entry is None:
            entry = exports[name] = Entry(name)
        entry.add(RANK[via], rel, line_of(offset), via, kind or (guess_kind(masked, tail, facts) if tail else None))

    def quoted(match):
        """The string a QUOTED group matched, from the text with its contents intact."""
        return stripped[match.start("s"):match.end("s")]

    def literal_parts(match, base=0):
        """(prefix, suffix, exact) of a literal, or a literal concatenated with more; `base` shifts into the text."""
        text = stripped[base + match.start("p"):base + match.end("p")]
        if match.groupdict().get("rest") is None:
            return "", "", text
        suffix = ""
        tail = TRAILING_LITERAL.search(match.group("rest"))
        if tail:
            suffix = stripped[base + match.start("rest") + tail.start("s"):base + match.start("rest") + tail.end("s")]
        return text, suffix, None

    def resolve(expr):
        """The literal names a name variable or a naming function can carry: ([exact names], [(prefix, suffix)])."""
        ident = NAME_START.match(expr)
        if not ident:
            return [], []
        name, exacts, shapes = re.escape(ident.group(0)), [], []
        assigned = r"(?P<q>[\"'])(?P<p>x*)(?P=q)(?:[ \t]*\.\.[ \t]*(?P<rest>[^\n]*))?"
        found = [(m, 0) for m in re.finditer(r"(?<![\w.])" + name + r"[ \t]*=(?!=)[ \t]*" + assigned, masked)]
        for head in re.finditer(r"function[ \t]+" + name + r"[ \t]*\(", masked):
            body = masked[head.end():head.end() + 1500]
            cut = re.search(r"(?m)^end\b", body)
            body = body[:cut.start()] if cut else body
            found.extend((m, head.end()) for m in re.finditer(r"\breturn[ \t]+" + assigned, body))
        for match, base in found:
            prefix, suffix, exact = literal_parts(match, base)
            # A variable called `name` is assigned many unrelated strings; only MSUF's own names count.
            if exact is not None and BARE_NAME_ONLY.match(exact):
                exacts.append(exact)
            elif exact is None and "MSUF" in prefix + suffix:
                shapes.append((prefix, suffix))
        return exacts, shapes

    def family(match, via):
        """Note a name built at run time; `match` carries p/rest (a literal prefix) or expr (no literal at all)."""
        if match.groupdict().get("p") is not None:
            prefix, suffix, _exact = literal_parts(match)
            expr = stripped[match.start("rest"):match.end("rest")].strip()
            if via == "builder" and not ("MSUF" in prefix + suffix and re.match(r"^\w*$", prefix + suffix)):
                return
        else:
            prefix = suffix = ""
            expr = stripped[match.start("expr"):match.end("expr")].strip()
            exacts, shapes = resolve(expr)
            for exact in exacts:
                record(exact, match.start(), via, "frame" if via == "frame" else None)
            for pfx, sfx in shapes:
                dynamic.setdefault(rel, []).append(Family(line_of(match.start()), via, pfx, sfx, expr))
            if exacts or shapes:
                return
        dynamic.setdefault(rel, []).append(Family(line_of(match.start()), via, prefix, suffix, expr))

    # Every pattern runs on the masked text, where string contents are filler: code that only appears
    # inside a string is never an export.
    aliases = set(EXPORT_FUNCTIONS)
    if "Export" in masked:
        aliases.update(ALIAS_DEF.findall(masked))
    if "_G[" in masked:
        for write in WRAPPER_WRITE.finditer(masked):
            heads = WRAPPER_HEAD.findall(masked[max(0, write.start() - 400):write.start()])
            if heads:
                aliases.add(heads[-1])
    present = sorted(a for a in aliases if a in masked)
    for alias in present:
        head = re.escape(alias) + r"[ \t]*\([ \t]*"
        for match in re.finditer(head + QUOTED + r"(?![ \t]*\.\.)", masked):
            if not word_before(masked, match.start()):
                record(quoted(match), match.start(), "export", tail=match.end())
        for match in re.finditer(head + PREFIXED, masked):
            if not word_before(masked, match.start()):
                family(match, "export")
        for match in re.finditer(head + r"(?![\"'])(?P<expr>[A-Za-z_][^,)\n]*)", masked):
            if not word_before(masked, match.start()):
                family(match, "export")
    if "_G" in masked:
        g_aliases = {"_G"} | set(G_ALIAS.findall(masked))
        for alias in sorted(g_aliases):
            head = re.escape(alias)
            for match in re.finditer(head + r"\.(%s)[ \t]*=(?!=)" % NAME, masked):
                if not field_before(masked, match.start()):
                    record(match.group(1), match.start(), "assign", tail=match.end())
            for match in re.finditer(head + r"\[[ \t]*%s[ \t]*\][ \t]*=(?!=)" % QUOTED, masked):
                if not field_before(masked, match.start()):
                    record(quoted(match), match.start(), "assign", tail=match.end())
            for match in re.finditer(r"function[ \t]+" + head + r"\.(%s)[ \t]*\(" % NAME, masked):
                record(match.group(1), match.start(), "function", "function")
            for match in re.finditer(head + r"\[[ \t]*" + PREFIXED_KEY + r"\][ \t]*=(?!=)", masked):
                if not field_before(masked, match.start()):
                    family(match, "assign")
            for match in re.finditer(head + r"\[[ \t]*(?![\"'])(?P<expr>[A-Za-z_][^\]\n]*)\][ \t]*=(?!=)", masked):
                if not field_before(masked, match.start()):
                    family(match, "assign")
            if "rawset" in masked:
                tail = r"rawset\([ \t]*" + head + r"[ \t]*,[ \t]*"
                for match in re.finditer(tail + QUOTED + r"(?![ \t]*\.\.)", masked):
                    record(quoted(match), match.start(), "assign", tail=match.end())
                for match in re.finditer(tail + PREFIXED, masked):
                    family(match, "assign")
                for match in re.finditer(tail + r"(?![\"'])(?P<expr>[A-Za-z_][^,)\n]*)", masked):
                    family(match, "assign")
    if "MSUF" in masked:
        # A function that returns, or a variable that is set to, `"MSUF_..." .. x` builds a name somewhere else.
        for match in re.finditer(r"\breturn[ \t]+" + PREFIXED, masked):
            family(match, "builder")
        for match in re.finditer(r"(?<![\w.])%s[ \t]*=(?!=)[ \t]*" % NAME + PREFIXED, masked):
            family(match, "builder")
    if "MSUF_" in masked:
        for base in NS_BASES:
            for match in NS_FIELD[base].finditer(masked):
                if not field_before(masked, match.start()):
                    record(match.group(1), match.start(), "nsfield", tail=match.end())
            for match in NS_FUNCTION[base].finditer(masked):
                record(match.group(1), match.start(), "nsfield", "function")
    if "CreateFrame" in masked:
        for match in CREATE_FRAME.finditer(masked):
            if not word_before(masked, match.start()):
                record(quoted(match), match.start(), "frame", "frame")
        for match in re.finditer(r"CreateFrame\([^,()\n]+,[ \t]*" + PREFIXED, masked):
            if not word_before(masked, match.start()):
                family(match, "frame")
        for match in re.finditer(r"CreateFrame\([^,()\n]+,[ \t]*(?!nil\b|[\"'])(?P<expr>[A-Za-z_][^,)\n]*)", masked):
            if not word_before(masked, match.start()):
                family(match, "frame")
    if "StaticPopupDialogs" in masked:
        for match in POPUP_INDEX.finditer(masked):
            record(quoted(match), match.start(), "popup", "popup")
        for match in POPUP_FIELD.finditer(masked):
            record(match.group(1), match.start(), "popup", "popup")
    if "UISpecialFrames" in masked:
        for pattern in SPECIAL_FRAME:
            for match in pattern.finditer(masked):
                name = quoted(match)
                if NAME_ONLY.match(name):
                    entry = exports.setdefault(name, Entry(name))
                    entry.special = True
                    entry.add(RANK["special"], rel, line_of(match.start()), "special", "frame")
                    entry.contract.append(("UISpecialFrames", line_of(match.start()), rel))

    def declared_local(name):
        return re.search(r"local[ \t]+(?:function[ \t]+)?(?:%s[ \t]*,[ \t]*)*%s\b" % (NAME, re.escape(name)),
                         masked) is not None

    for match in GLOBAL_FUNCTION.finditer(masked):
        if at_line_start(masked, match.start()) and not declared_local(match.group(1)):
            record(match.group(1), match.start(), "function", "function")
    assigned = []
    for pattern in GLOBAL_ASSIGN:
        for match in pattern.finditer(masked):
            start = match.start(1)
            # `__MSUF_X` and `_MSUF_X` carry up to two leading underscores.
            while start > 0 and masked[start - 1] == "_" and match.start(1) - start < 2:
                start -= 1
            name = masked[start:match.end(1)]
            if at_line_start(masked, start) and BARE_NAME_ONLY.match(name) and not declared_local(name):
                assigned.append((start, match.end(), name))
    if assigned:
        depths = brace_depths(masked)
        for start, end, name in assigned:
            if depths[start] == 0:
                record(name, start, "global", tail=end)


XML_ELEMENT = re.compile(r"<(?P<tag>[A-Za-z]+)\b(?P<attrs>[^>]*?)\bname=\"(?P<name>[^\"]+)\"(?P<rest>[^>]*)>", re.S)
XML_BINDING = re.compile(r"<Binding\b[^>]*\bname=\"(?P<name>[^\"]+)\"[^>]*>(?P<body>.*?)</Binding>", re.S)
IDENTIFIER_CALL = re.compile(r"\b(%s)[ \t]*\(" % NAME)


XML_COMMENT = re.compile(r"<!--.*?-->", re.S)
# Script handlers and mixins name globals the client resolves when it loads the XML: <OnLoad function="X"/>,
# <Frame mixin="A, B" secureMixin="C">.
XML_REFERENCE = re.compile(r"\b(?P<attr>function|mixin|secureMixin)=\"(?P<value>[^\"]+)\"")


def scan_xml(rel, text, exports):
    text = XML_COMMENT.sub(lambda m: fill(m.group(0), " "), text)
    lines = Lines(text)
    for match in XML_REFERENCE.finditer(text):
        for name in re.findall(NAME, match.group("value")):
            entry = exports.setdefault(name, Entry(name))
            entry.kinds.add("function" if match.group("attr") == "function" else "table")
            entry.contract.append((os.path.basename(rel), lines.of(match.start()), rel))
    for match in XML_ELEMENT.finditer(text):
        name = match.group("name")
        tag = match.group("tag")
        if tag == "Binding" or name.startswith("$parent") or not re.match(r"^%s$" % NAME, name):
            continue
        entry = exports.setdefault(name, Entry(name))
        entry.add(RANK["xml"], rel, lines.of(match.start()), "xml", "frame")
        entry.contract.append((os.path.basename(rel), lines.of(match.start()), rel))
    for match in XML_BINDING.finditer(text):
        line = lines.of(match.start())
        name = match.group("name")
        click = re.match(r"^CLICK (%s):\w+$" % NAME, name)
        if click:
            target = exports.setdefault(click.group(1), Entry(click.group(1)))
            target.contract.append((os.path.basename(rel), line, rel))
            target.kinds.add("frame")
        else:
            entry = exports.setdefault(name, Entry(name))
            entry.add(RANK["xml"], rel, line, "xml", "binding")
            entry.contract.append((os.path.basename(rel), line, rel))
        for call in IDENTIFIER_CALL.findall(match.group("body")):
            action = exports.setdefault(call, Entry(call))
            action.kinds.add("function")
            action.contract.append((os.path.basename(rel), line, rel))


def scan_toc(rel, text, exports):
    lines = Lines(text)
    for match in re.finditer(r"^##[ \t]*SavedVariables(?:PerCharacter)?:[ \t]*(.*)$", text, re.M):
        for name in re.findall(NAME, match.group(1)):
            entry = exports.setdefault(name, Entry(name))
            entry.add(RANK["toc"], rel, lines.of(match.start()), "toc", "savedvar")
            entry.contract.append(("SavedVariables", lines.of(match.start()), rel))
    for match in re.finditer(r"^##[ \t]*AddonCompartmentFunc(?:OnEnter|OnLeave)?:[ \t]*(%s)" % NAME, text, re.M):
        entry = exports.setdefault(match.group(1), Entry(match.group(1)))
        entry.kinds.add("function")
        entry.contract.append(("AddonCompartment", lines.of(match.start()), rel))


def finish_contracts(exports):
    """SLASH_* and BINDING_* strings are looked up by the client under exactly these names."""
    for name, entry in exports.items():
        if name.startswith(("SLASH_", "BINDING_")) and not any(c[0] in ("SlashCmdList", "Bindings") for c in entry.contract):
            site = entry.primary()
            entry.contract.append(("SlashCmdList" if name.startswith("SLASH_") else "Bindings",
                                   site[2] if site else 0, site[1] if site else ""))


def static_inventory(root=ROOT):
    """(name -> Entry for every name the source writes into _G, file -> lines of dynamic sites)."""
    exports, dynamic = {}, {}
    for rel in addon_files(root):
        if vendored(rel):
            continue
        text = read_text(os.path.join(root, rel))
        if rel.endswith(".lua"):
            scan_lua(rel, text, exports, dynamic)
        elif rel.endswith(".xml"):
            scan_xml(rel, text, exports)
        elif rel.endswith(".toc"):
            # Every client's TOC lists the same SavedVariables; the Mainline one is the record.
            if "_Mainline" in rel:
                scan_toc(rel, text, exports)
    finish_contracts(exports)
    return exports, dynamic


# --------------------------------------------------------------------------------------
# Runtime inventory (a booted client)
# --------------------------------------------------------------------------------------

def resolve_lua():
    candidate = os.environ.get("MSUF_LUA") or shutil.which("lua") or DEFAULT_LUA
    if not candidate or not os.path.exists(candidate):
        raise LedgerError("no Lua 5.1 found: set MSUF_LUA or put one first on PATH")
    probe = subprocess.run([candidate, "-v"], capture_output=True, text=True, errors="replace")
    banner = ((probe.stdout or "") + (probe.stderr or "")).strip()
    if not banner.startswith("Lua 5.1"):
        if candidate != DEFAULT_LUA and os.path.exists(DEFAULT_LUA):
            return DEFAULT_LUA
        raise LedgerError("Lua 5.1 required: %s reports %r" % (candidate, banner))
    return candidate


def runtime_inventory(root=ROOT, lua=None):
    """flavor -> {name: (type, phase, site, frame)} from booting each client, the UISpecialFrames names,
    and flavor -> {name: type} for MSUF_* fields of the addon namespace."""
    lua = lua or resolve_lua()
    result, namespace, special = {}, {}, set()
    for flavor in FLAVORS:
        run = subprocess.run([lua, os.path.join(root, RUNTIME_SMOKE), root.replace("\\", "/"), flavor, "--inventory"],
                             cwd=root, capture_output=True)
        if run.returncode != 0:
            raise LedgerError("%s --inventory failed for %s:\n%s" % (
                RUNTIME_SMOKE, flavor, (run.stderr or run.stdout).decode("utf-8", "replace").strip()))
        names, fields = {}, {}
        for line in run.stdout.decode("utf-8").splitlines():
            parts = line.rstrip("\r").split("\t")
            if parts[0] == "#special" and len(parts) > 1:
                special.add(parts[1])
            elif parts[0] == "#ns" and len(parts) > 2:
                fields[parts[1]] = parts[2]
            elif len(parts) >= 5:
                names[parts[0]] = (parts[1], parts[2], parts[3], parts[4] == "frame")
        if not names:
            raise LedgerError("%s printed no inventory for %s" % (RUNTIME_SMOKE, flavor))
        result[flavor], namespace[flavor] = names, fields
    return result, namespace, special


def merge_runtime(root, exports, runtime, namespace, special):
    """Fold the booted clients into the static inventory, keeping the static exporter where there is one."""
    for flavor, names in runtime.items():
        for name, (kind, _phase, site, frame) in names.items():
            if name in FOREIGN_GLOBALS:
                continue
            entry = exports.get(name)
            if entry is None:
                entry = exports[name] = Entry(name)
            if entry.primary_global() is None:
                path, _, line = site.rpartition(":")
                if path:
                    entry.add(RANK["runtime"], path, int(line) if line.isdigit() else 0, "runtime")
            entry.runtime[flavor] = kind
            entry.frame = entry.frame or frame
    for flavor, fields in namespace.items():
        for name, kind in fields.items():
            if name in exports:
                exports[name].ns_runtime[flavor] = kind
    for name in special:
        entry = exports.get(name)
        if entry is not None and not entry.special:
            entry.special = True
            site = entry.primary()
            entry.contract.append(("UISpecialFrames", site[2] if site else 0, site[1] if site else ""))
    texts = {}
    for entry in exports.values():
        site = entry.primary()
        if site is None or site[3] != "runtime":
            continue
        # A runtime-only name is either listed as a literal in its exporter file (a table-driven export) or
        # built at run time.
        text = texts.get(site[1])
        if text is None:
            path = os.path.join(root, site[1])
            text = texts[site[1]] = strip_comments(read_text(path)) if os.path.isfile(path) else ""
        if re.search(r"[\"']%s[\"']" % re.escape(entry.name), text):
            entry.listed = True
        else:
            entry.dynamic = True


def entry_kind(entry):
    name = entry.name
    if name.startswith("SLASH_"):
        return "slash"
    if name.startswith("BINDING_") or "binding" in entry.kinds:
        return "binding"
    if "savedvar" in entry.kinds:
        return "savedvar"
    if "popup" in entry.kinds and not entry.runtime:
        return "popup"
    if entry.frame or ("frame" in entry.kinds and not entry.runtime):
        return "frame"
    # What a booted client holds is better evidence than what the source text suggests.
    types = set(entry.runtime.values()) | set(entry.ns_runtime.values())
    types.discard("nil")
    if not types:
        types = set(entry.kinds) & {"function", "table"}
    if "function" in types:
        return "function"
    if "table" in types:
        return "table"
    return "value"


def entry_clients(entry):
    seen = entry.ns_runtime if entry.namespace_only() else entry.runtime
    flavors = [flavor for flavor in FLAVORS if flavor in seen]
    if not flavors:
        return "static"
    return "all" if len(flavors) == len(FLAVORS) else ",".join(flavors)


def entry_note(entry):
    notes = []
    if entry.dynamic:
        notes.append("dynamic")
    if entry.listed:
        notes.append("listed")
    return ",".join(notes)


# --------------------------------------------------------------------------------------
# Readers outside the two addons
# --------------------------------------------------------------------------------------

class Source:
    """One addon directory that may read MSUF's globals."""

    def __init__(self, addon, path):
        self.addon = addon
        self.path = path
        self.suite = addon.startswith("MSUF_Suite")


SKIP_DIRS = re.compile(r"^(?:_.*|\..*|tests?|spec|node_modules)$", re.I)


def repo_sources(repo_root):
    """Addon folders of a repository: the directories that carry a TOC of their own."""
    found = []
    for name in sorted(os.listdir(repo_root)):
        path = os.path.join(repo_root, name)
        if not os.path.isdir(path) or SKIP_DIRS.match(name):
            continue
        if any(entry.lower().endswith(".toc") for entry in os.listdir(path)):
            found.append(Source(name, path))
    return found


def installed_sources(wow_root):
    """Every other addon installed under a client folder; the first client folder that has one wins a file."""
    found = []
    folders = [f for f in CLIENT_FOLDERS if os.path.isdir(os.path.join(wow_root, f, "Interface", "AddOns"))]
    for folder in folders:
        base = os.path.join(wow_root, folder, "Interface", "AddOns")
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name)
            if not os.path.isdir(path) or SKIP_DIRS.match(name) or SKIPPED_INSTALLED.match(name):
                continue
            found.append(Source(name, path))
    return found


def source_files(source):
    for current, dirs, files in os.walk(source.path):
        dirs[:] = sorted(d for d in dirs if not SKIP_DIRS.match(d))
        for name in sorted(files):
            if name.lower().endswith(".lua"):
                yield os.path.join(current, name)


GETGLOBAL = re.compile(rb"(?m)^(?:main|function) <([^>]+):\d+,\d+>|^\t\d+\t\[(\d+)\]\tGETGLOBAL\t[^\t]*\t; (\S+)\r?$")


def resolve_luac(lua):
    candidates = [os.environ.get("MSUF_LUAC"), shutil.which("luac"),
                  os.path.join(os.path.dirname(lua), "luac.exe"), os.path.join(os.path.dirname(lua), "luac")]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            probe = subprocess.run([candidate, "-v"], capture_output=True, text=True, errors="replace")
            if ((probe.stdout or "") + (probe.stderr or "")).strip().startswith("Lua 5.1"):
                return candidate
    raise LedgerError("no luac 5.1 found: set MSUF_LUAC or put one first on PATH")


def global_reads(luac, paths):
    """path -> [(name, line)] of every bare global read the compiler sees; None for a file it rejects."""
    reads = {}
    pending = list(paths)
    while pending:
        batch, length = [], 0
        while pending and length < 20000:
            batch.append(pending.pop())
            length += len(batch[-1]) + 3
        run = subprocess.run([luac, "-l", "-p"] + batch, capture_output=True)
        if run.returncode == 0:
            parsed = parse_listing(run.stdout, batch)
            for path in batch:
                reads[path] = parsed.get(path, [])
        elif len(batch) == 1:
            reads[batch[0]] = None
        else:
            # One file the compiler rejects fails the whole batch; find it by compiling them apart.
            pending.extend(path for path in batch)
            pending.sort()
            for path in batch:
                single = subprocess.run([luac, "-l", "-p", path], capture_output=True)
                pending.remove(path)
                reads[path] = parse_listing(single.stdout, [path]).get(path, []) if single.returncode == 0 else None
    return reads


def parse_listing(output, wanted):
    """path -> [(name, line)] for the GETGLOBAL lines of one luac listing, attributed by source file."""
    index = {os.path.normcase(os.path.abspath(p)): p for p in wanted}
    reads, current = {}, None
    for match in GETGLOBAL.finditer(output):
        if match.group(1) is not None:
            candidate = match.group(1).decode("utf-8", "replace")
            current = index.get(os.path.normcase(os.path.abspath(candidate))) if candidate != "(luac)" else None
            continue
        if current is not None:
            reads.setdefault(current, []).append((match.group(3).decode("utf-8", "replace"), int(match.group(2))))
    return reads


class Reader:
    """First read of one name in one file of one addon."""

    def __init__(self, addon, rel, line, suite):
        self.addon, self.rel, self.line, self.suite = addon, rel, line, suite


# A global name by itself is evidence only in a global-access form; a quoted string equal to a
# name counts when the name is unmistakably MSUF's (it carries "MSUF_" or "MSUF2_", or is a binding/slash name).
LOOSE_STRING_NAME = re.compile(r"^(?:_?_?MSUF[0-9]*_|SLASH_|BINDING_)")
ANY_QUOTED = re.compile(r"(?P<q>[\"'])(?P<s>%s)(?P=q)(?![ \t]*\.\.)" % NAME)
QUOTED_PREFIX = re.compile(r"(?P<q>[\"'])(?P<p>(?:_?_?MSUF|SLASH_MSUF|BINDING_[A-Z]+_MSUF)[A-Za-z0-9_]*)(?P=q)[ \t]*\.\.")
# A quoted prefix that ends in "_" on its own ("MSUF_GF_"): a tool that walks frame or global names by prefix.
PREFIX_STRING = re.compile(r"(?P<q>[\"'])(?P<p>(?:_?_?MSUF)[A-Za-z0-9_]*_)(?P=q)")
FIELD_READ = re.compile(r"(?<!\w)(?P<base>[A-Za-z_]\w*)[ \t]*\.[ \t]*(?P<name>%s)" % NAME)
# `_G["X"]`, rawget(_G, "X") and getglobal("X"): a global looked up by a literal name.
STRICT_STRING = re.compile(
    r"(?:(?<![\w.])(?P<base>[A-Za-z_]\w*)[ \t]*\[[ \t]*|\b(?P<fn>rawget[ \t]*\([ \t]*_G[ \t]*,|getglobal[ \t]*\())[ \t]*"
    r"(?P<q>[\"'])(?P<s>%s)(?P=q)(?![ \t]*\.\.)" % NAME)
# Names that look like MSUF's but belong to the Suite, which defines them in its own sources.
MSUF_ISH = re.compile(r"^(?!MSUF_?Suite|MSUF_?SUITE|BINDING_[A-Z]+_MSUFSUITE)(?:_?_?MSUF|SLASH_MSUF|BINDING_[A-Z]+_MSUF)")

# Fields of the tables MSUF exports. `MSUF` and `MSUF_NS` are one table. A reader gets a table through
# `_G.T`, `_G["T"]`, rawget(_G, "T") or a bare global read, usually into a local (`local host = _G.MSUF_NS`)
# or through a small accessor function (`local function HostNamespace() return _G.MSUF_NS end`).
CANON_TABLE = {"MSUF": "MSUF_NS"}
# One whole operand that is a table reference: `_G.T`, `_G["T"]`, rawget(_G, "T"), `MSUF.T` (the namespace
# holds MSUF2, MSUF_EM2 and friends), a bare name, `Func()` or `MSUF.Accessor()`.
OPERAND = re.compile(
    r"^(?:_G[ \t]*\.[ \t]*(?P<a>{n})"
    r"|_G[ \t]*\[[ \t]*[\"'](?P<b>{n})[\"'][ \t]*\]"
    r"|(?:rawget[ \t]*\([ \t]*_G[ \t]*,|getglobal[ \t]*\()[ \t]*[\"'](?P<c>{n})[\"'][ \t]*\)"
    r"|(?:MSUF|ns|NS)[ \t]*\.[ \t]*(?P<e>{n})(?P<ecall>[ \t]*\([ \t]*\))?"
    r"|(?P<d>{n})(?P<dcall>[ \t]*\([ \t]*\))?)$".format(n=NAME))
OPERAND_SPLIT = re.compile(r"\b(?:and|or)\b")
# `assert(_G.MSUF_NS, "message")` hands out its first argument.
ASSERT_CALL = re.compile(r"\bassert[ \t]*\(([^,()]*)(?:,[^()]*)?\)")
# Accessor functions that hand out a tracked table (MSUF.GetMenu2Namespace() returns MSUF2).
ACCESSORS = {"GetMenu2Namespace": "MSUF2"}
ASSIGNMENT = re.compile(r"(?m)^[ \t]*(?:local[ \t]+)?(%s)[ \t]*=(?!=)[ \t]*(.+)$" % NAME)
FUNCTION_START = re.compile(r"(?m)^[ \t]*(?:local[ \t]+)?function[ \t]+(%s)[ \t]*\(" % NAME)
RETURN_VALUE = re.compile(r"\breturn[ \t]+([^\n]*)")
END_LINE = re.compile(r"(?m)^[ \t]*end\b")
# Only a statement at the start of a line is the file's own `...`; an indented one is some function's.
VARARGS = re.compile(r"(?m)^local[ \t]+%s[ \t]*,[ \t]*(%s)[ \t]*=[ \t]*\.\.\." % (NAME, NAME))
NAMESPACE_SELECT = re.compile(r"(?m)^local[ \t]+(%s)[ \t]*=[ \t]*select\(2,[ \t]*\.\.\.\)" % NAME)
WRITE_AFTER = re.compile(r"[ \t]*=(?!=)")


def canonical(table):
    return CANON_TABLE.get(table, table)


def named_tables(text, tables, funcs, aliases):
    """The tracked tables an expression yields, or none when any operand of it is something else.

    `_G.T or _G.T2`, `type(_G.T) == "table" and _G.T or nil` and `_G.T or {}` yield tables; `HostNamespace()`
    yields what that function returns; `ns or rec.label` mixes in some other value and yields nothing, so a
    local that may hold anything is not taken for a table.
    """
    found = set()
    text = ASSERT_CALL.sub(r"\1", re.sub(r"[ \t]+end\b.*$", "", text))
    for operand in OPERAND_SPLIT.split(text):
        operand = operand.strip()
        while operand.startswith("(") and operand.endswith(")"):
            operand = operand[1:-1].strip()
        if not operand or operand in ("nil", "false", "true", "{}", "_G") or "==" in operand or "~=" in operand:
            continue
        match = OPERAND.match(operand)
        if not match:
            return set()
        name = match.group("a") or match.group("b") or match.group("c") or match.group("d") or match.group("e")
        if match.group("d") and match.group("dcall"):
            got = funcs.get(name, set())
        elif match.group("e") and match.group("ecall"):
            got = {ACCESSORS[name]} if name in ACCESSORS else set()
        elif match.group("d") and name not in tables:
            got = aliases.get(name, set())
        elif name in tables:
            got = {canonical(name)}
        else:
            got = set()
        if not got:
            return set()
        found |= got
    return found


def table_aliases(stripped, tables):
    """(variable -> tables, function -> tables) for every assignment or return that names a tracked table."""
    present = {t for t in tables if t in stripped}
    if not present:
        return {}, {}
    aliases, funcs = {}, {}
    assigns = ASSIGNMENT.findall(stripped)
    functions = []
    for match in FUNCTION_START.finditer(stripped):
        body = stripped[match.end():match.end() + 800]
        cut = END_LINE.search(body)
        functions.append((match.group(1), RETURN_VALUE.findall(body[:cut.start()] if cut else body)))
    for _ in range(3):
        for var, rhs in assigns:
            found = named_tables(rhs, present, funcs, aliases)
            if found:
                aliases.setdefault(var, set()).update(found)
        for name, returns in functions:
            for rhs in returns:
                found = named_tables(rhs, present, funcs, aliases)
                if found:
                    funcs.setdefault(name, set()).update(found)
    return aliases, funcs


def field_accesses(stripped, masked, aliases, funcs, tables, bare):
    """[(table, field, offset, 'read' or 'write')] for fields of aliased variables, `_G.T.f` and bare `T.f`.

    Matched on the masked text, so a sentence inside a string never reads as a field access; the name of a
    `v["field"]` access is read back from the stripped text.
    """
    found = []

    def classify(match, end):
        before = masked[:match.start()].rstrip()
        if before.endswith("function") or WRITE_AFTER.match(masked, end):
            return "write"
        return "read"

    def field_of(match):
        if match.group("f"):
            return match.group("f")
        name = stripped[match.start("g"):match.end("g")]
        return name if NAME_ONLY.match(name) else None

    variables = sorted(aliases, key=len, reverse=True)
    if variables:
        pattern = re.compile(r"(?<![\w.])(?P<v>%s)(?:[ \t]*[.:][ \t]*(?P<f>%s)|\[[ \t]*[\"'](?P<g>x+)[\"'][ \t]*\])" % (
            "|".join(re.escape(v) for v in variables), NAME))
        for match in pattern.finditer(masked):
            field = field_of(match)
            for table in aliases[match.group("v")] if field else ():
                found.append((table, field, match.start(), classify(match, match.end())))
    calls = dict(funcs)
    for accessor, table in ACCESSORS.items():
        calls.setdefault(accessor, set()).add(table)
    if calls:
        # `HostNamespace().GF`: a field of what an accessor function returns.
        pattern = re.compile(r"(?<![\w])(?P<c>%s)[ \t]*\([ \t]*\)[ \t]*[.:][ \t]*(?P<f>%s)" % (
            "|".join(re.escape(c) for c in sorted(calls, key=len, reverse=True)), NAME))
        for match in pattern.finditer(masked):
            for table in calls[match.group("c")]:
                found.append((table, match.group("f"), match.start(), classify(match, match.end())))
    present = sorted(t for t in tables if t in masked)
    if present:
        pattern = re.compile(r"(?:_G[ \t]*\.[ \t]*|(?<![\w.:]))(?P<t>%s)[ \t]*[.:][ \t]*(?P<f>%s)" % (
            "|".join(re.escape(t) for t in present), NAME))
        for match in pattern.finditer(masked):
            if match.group(0).startswith("_G") or match.group("t") in bare:
                found.append((canonical(match.group("t")), match.group("f"), match.start(), classify(match, match.end())))
    return found


class ExternalScan:
    """What the outside sources read: globals, prefixes, table fields, and names nothing here exports."""

    def __init__(self):
        self.readers = collections.defaultdict(dict)   # exported name -> {(addon, rel): Reader}
        self.prefixes = collections.defaultdict(dict)  # quoted prefix -> {(addon, rel): Reader}
        self.fields = collections.defaultdict(dict)    # (table, field) -> {(addon, rel): Reader}
        self.stray = collections.defaultdict(dict)     # MSUF-looking global read that nothing exports
        self.loose = collections.defaultdict(dict)     # MSUF-looking quoted string that nothing exports
        self.defined = set()                           # names the scanned sources define themselves
        self.unparsed = []                             # files luac rejected


def scan_external(sources, names, tables, luac):
    """Read every Lua file of every source that mentions MSUF, once, and sort what it reads."""
    odd = sorted(n for n in names if not re.search(r"MSUF|MIDNIGHTSUF|MidnightSimpleUnitFrames", n))
    prefilter = re.compile(("MSUF|MIDNIGHTSUF|MidnightSimpleUnitFrames" + "".join("|" + re.escape(n) for n in odd)).encode())
    scan = ExternalScan()
    candidates, seen = [], set()
    for source in sources:
        for path in source_files(source):
            rel = os.path.relpath(path, source.path).replace("\\", "/")
            key = (source.addon, rel)
            if key in seen:
                continue
            with open(path, "rb") as handle:
                raw = handle.read()
            if prefilter.search(raw):
                seen.add(key)
                candidates.append((source, rel, path, raw))
    compiled = global_reads(luac, [c[2] for c in candidates]) if candidates else {}
    for source, rel, path, raw in candidates:
        text = raw.decode("utf-8", "replace").replace("\r\n", "\n")
        stripped, masked = strip_and_mask(text)
        lines = Lines(stripped)
        key = (source.addon, rel)

        def add(table, name, offset):
            slot = table[name]
            if key not in slot:
                slot[key] = Reader(source.addon, rel, lines.of(offset), source.suite)

        local_exports, _families = {}, {}
        scan_lua(rel, text, local_exports, _families)
        scan.defined.update(local_exports)
        g_aliases = frozenset({"_G"} | set(G_ALIAS.findall(stripped)))
        bare = compiled.get(path)
        if bare is None:
            scan.unparsed.append(key)
            bare = [(m.group(1), lines.of(m.start(1))) for m in re.finditer(r"(?<![\w.:])(%s)\b" % NAME, stripped)
                    if m.group(1) in names or MSUF_ISH.match(m.group(1))]
        for name, line in bare:
            reader = Reader(source.addon, rel, line, source.suite)
            if name in names:
                scan.readers[name].setdefault(key, reader)
            elif MSUF_ISH.match(name):
                scan.stray[name].setdefault(key, reader)
        for match in FIELD_READ.finditer(stripped):
            base, name = match.group("base"), match.group("name")
            if base in g_aliases and name in names:
                add(scan.readers, name, match.start())
            elif base in g_aliases and MSUF_ISH.match(name):
                add(scan.stray, name, match.start())
        for match in STRICT_STRING.finditer(stripped):
            name = match.group("s")
            if match.group("base") in g_aliases or match.group("fn"):
                if name in names:
                    add(scan.readers, name, match.start())
                elif MSUF_ISH.match(name):
                    add(scan.stray, name, match.start())
        for match in ANY_QUOTED.finditer(stripped):
            name = match.group("s")
            if LOOSE_STRING_NAME.match(name):
                add(scan.readers if name in names else scan.loose, name, match.start())
        for pattern in (QUOTED_PREFIX, PREFIX_STRING):
            for match in pattern.finditer(stripped):
                add(scan.prefixes, match.group("p"), match.start())
        aliases, funcs = table_aliases(stripped, tables)
        for table, field, offset, kind in field_accesses(stripped, masked, aliases, funcs, tables, {n for n, _l in bare}):
            if kind == "read":
                add(scan.fields, (table, field), offset)
    return scan


# --------------------------------------------------------------------------------------
# Ledger rows
# --------------------------------------------------------------------------------------

def site_text(entry):
    site = entry.primary()
    if "savedvar" in entry.kinds:
        # The TOC line is what makes the client persist it.
        site = next((s for s in sorted(entry.sites) if s[3] == "toc"), site)
    return "%s:%d" % (site[1], site[2]) if site else "-"


def pick_consumers(by_file):
    """Up to SHOWN reading files: the first Suite and the first other addon, then one addon after another."""
    per_addon = collections.defaultdict(list)
    for reader in by_file.values():
        per_addon[reader.addon].append(reader)
    for addon in per_addon:
        per_addon[addon].sort(key=lambda r: ("Locales/" in r.rel, r.rel, r.line))
    order = sorted(per_addon, key=lambda a: (not per_addon[a][0].suite, a.lower()))
    chosen, taken = [], set()
    # Every evidence class the row carries gets a reader in the cell.
    for suite in (True, False):
        first = next((a for a in order if per_addon[a][0].suite == suite), None)
        if first is not None:
            chosen.append(per_addon[first][0])
            taken.add((first, 0))
    depth = 0
    while len(chosen) < SHOWN and any(len(per_addon[a]) > depth for a in order):
        for addon in order:
            if len(per_addon[addon]) > depth and (addon, depth) not in taken and len(chosen) < SHOWN:
                chosen.append(per_addon[addon][depth])
        depth += 1
    return ["%s:%s:%d" % (r.addon, r.rel, r.line) for r in chosen]


def synthetic_consumers(entry):
    """Lookups the client itself makes, and the bridges that publish a name for other addons; one per source file."""
    shown, seen = [], set()
    for pseudo, line, _path in entry.contract:
        if pseudo not in seen:
            seen.add(pseudo)
            shown.append("blizzard:%s:%d" % (pseudo, line))
    site = entry.primary()
    if site and "/Integrations/" in site[1]:
        shown.append("integration:%s:%d" % (os.path.basename(site[1]), site[2]))
    return shown


def evidence_of(entry, by_file):
    found = set()
    for reader in by_file.values():
        found.add("suite" if reader.suite else "external")
    if any(c[0] == "SavedVariables" for c in entry.contract):
        found.add("sv")
    if any(c[0] != "SavedVariables" for c in entry.contract):
        found.add("blizzard-contract")
    site = entry.primary()
    if site and "/Integrations/" in site[1]:
        found.add("integration")
    return [e for e in EVIDENCE if e in found]


def make_row(entry, by_file):
    real = pick_consumers(by_file)
    shown = real + synthetic_consumers(entry)
    return {
        "name": entry.name, "kind": entry_kind(entry), "exporter": site_text(entry),
        "consumers": shown, "readers": len(by_file), "addons": len({r.addon for r in by_file.values()}),
        "evidence": evidence_of(entry, by_file), "clients": entry_clients(entry),
        "note": entry_note(entry),
    }


def prefix_rows(prefixes, names):
    rows = []
    for prefix, by_file in sorted(prefixes.items()):
        matched = [n for n in names if n.startswith(prefix) and n != prefix]
        if not matched:
            continue
        shown = pick_consumers(by_file)
        found = {"suite" if r.suite else "external" for r in by_file.values()}
        rows.append({
            "name": prefix + "*", "kind": "dynamic", "exporter": "-", "consumers": shown, "readers": len(by_file),
            "addons": len({r.addon for r in by_file.values()}), "evidence": [e for e in EVIDENCE if e in found],
            "clients": "static", "note": "prefix" + (",wildcard" if len(matched) > 100 else ""),
        })
    return rows


def table_spellings(table):
    """A table's names in source text: `MSUF` and `MSUF_NS` are one table."""
    return {table} | {alias for alias, canon in CANON_TABLE.items() if canon == table}


def writes_in_file(rel, text, tables):
    """[(table, field, line)] for every field of a tracked table that one source file writes."""
    stripped, masked = strip_and_mask(text)
    aliases, funcs = table_aliases(stripped, tables)
    # The second value every file of either addon receives is the addon namespace; the Options addon's
    # forwards its reads and writes to MSUF_NS (MSUF_OptionsLOD_Bootstrap.lua).
    for var in VARARGS.findall(stripped) + NAMESPACE_SELECT.findall(stripped):
        aliases.setdefault(var, set()).add("MSUF_NS")
    lines, found = None, []
    for table, field, offset, kind in field_accesses(stripped, masked, aliases, funcs, tables, tables):
        if kind != "write":
            continue
        lines = lines or Lines(stripped)
        found.append((table, field, lines.of(offset)))
    return found


def field_writers(root, tables):
    """(table, field) -> (path, line): the first source line that writes a field of a tracked table."""
    index = {}
    for rel in addon_files(root):
        if not rel.endswith(".lua") or vendored(rel):
            continue
        for table, field, line in writes_in_file(rel, read_text(os.path.join(root, rel)), tables):
            if (table, field) not in index or (rel, line) < index[(table, field)]:
                index[(table, field)] = (rel, line)
    return index


def probe_fields(root, lua, keys):
    """{(table, field): {flavor: type}} for the fields a booted client of each flavor holds."""
    handle = tempfile.NamedTemporaryFile("w", suffix=".txt", prefix="msuf_fields_", delete=False,
                                         encoding="utf-8", newline="")
    try:
        handle.write("".join("%s\t%s\n" % key for key in keys))
        handle.close()
        found = collections.defaultdict(dict)
        for flavor in FLAVORS:
            run = subprocess.run([lua, os.path.join(root, RUNTIME_SMOKE), root.replace("\\", "/"), flavor,
                                  "--probe", handle.name], cwd=root, capture_output=True)
            if run.returncode != 0:
                raise LedgerError("%s --probe failed for %s:\n%s" % (
                    RUNTIME_SMOKE, flavor, (run.stderr or run.stdout).decode("utf-8", "replace").strip()))
            for line in run.stdout.decode("utf-8").splitlines():
                parts = line.rstrip("\r").split("\t")
                if parts[0] == "#field" and len(parts) == 4:
                    found[(parts[1], parts[2])][flavor] = parts[3]
    finally:
        os.unlink(handle.name)
    return found


def field_rows(root, exports, scan, lua, tables):
    """(rows, unmatched): one nsfield row per field of an exported table that an outside source reads.

    A read counts only for a field MSUF really has: a source line writes it, or a booted client holds it.
    """
    writers = field_writers(root, tables)
    keys = sorted(scan.fields)
    seen = probe_fields(root, lua, keys) if keys else {}
    rows, unmatched = [], []
    for key in keys:
        table, field = key
        flavors = [flavor for flavor in FLAVORS if flavor in seen.get(key, {})]
        writer = writers.get(key)
        if not flavors and writer is None:
            unmatched.append(key)
            continue
        by_file = scan.fields[key]
        exporter = "%s:%d" % writer if writer else site_text(exports[table])
        rows.append({
            "name": "%s.%s" % key, "kind": "nsfield", "exporter": exporter, "consumers": pick_consumers(by_file),
            "readers": len(by_file), "addons": len({r.addon for r in by_file.values()}),
            "evidence": evidence_of(Entry("-"), by_file),
            "clients": "static" if not flavors else "all" if len(flavors) == len(FLAVORS) else ",".join(flavors),
            "note": "" if writer else "dynamic",
        })
    return rows, unmatched


def promote_families(exports, names, scan, families):
    """Names an outside source reads that only a run-time export site can publish become exports of that site."""
    shapes = [(rel, family) for rel, listed in sorted(families.items()) for family in listed if not family.passthrough]
    promoted = []
    for pool in (scan.stray, scan.loose):
        for name in sorted(pool):
            if name in names:
                continue
            hit = next(((rel, family) for rel, family in shapes if family.matches(name)), None)
            if hit is None:
                continue
            rel, family = hit
            entry = exports.setdefault(name, Entry(name))
            entry.add(RANK[family.via], rel, family.line, family.via, "frame" if family.via == "frame" else None)
            entry.dynamic = True
            names.add(name)
            promoted.append(name)
            for key, reader in pool[name].items():
                scan.readers[name].setdefault(key, reader)
    for pool in (scan.stray, scan.loose):
        for name in promoted:
            pool.pop(name, None)
    return promoted


def collect(root, suite_repo, repos, wow_root):
    """Everything --write needs: the merged inventory, the ledger rows and the side reports."""
    lua = resolve_lua()
    luac = resolve_luac(lua)
    exports, families = static_inventory(root)
    runtime, namespace, special = runtime_inventory(root, lua)
    merge_runtime(root, exports, runtime, namespace, special)
    finish_contracts(exports)
    names = {n for n in exports if n not in FOREIGN_GLOBALS}
    tables = {n for n in names if entry_kind(exports[n]) == "table"} | set(CANON_TABLE)
    sources = repo_sources(suite_repo)
    for repo in repos:
        sources.extend(repo_sources(repo))
    sources.extend(installed_sources(wow_root))
    scan = scan_external(sources, names, tables, luac)
    promoted = promote_families(exports, names, scan, families)
    rows, unexported = [], []
    for name in sorted(names):
        entry = exports[name]
        if entry.primary() is None:
            unexported.append(name)
            continue
        by_file = scan.readers.get(name, {})
        row = make_row(entry, by_file)
        if by_file or row["evidence"]:
            rows.append(row)
    rows.extend(prefix_rows(scan.prefixes, names))
    field_list, unmatched = field_rows(root, exports, scan, lua, tables)
    rows.extend(field_list)
    rows.sort(key=lambda r: r["name"])
    dangling = {n: v for n, v in scan.stray.items() if n not in scan.defined and n not in LUA_STDLIB}
    return {"exports": exports, "rows": rows, "dangling": dangling, "unparsed": scan.unparsed, "sources": len(sources),
            "families": families, "promoted": promoted, "unmatched_fields": unmatched, "unexported": unexported}


# --------------------------------------------------------------------------------------
# The ledger file
# --------------------------------------------------------------------------------------

HEADER_COMMENT = (
    "# Public-globals ledger (7.0 package W0-5): every global MSUF exports that something outside the core and",
    "# Options addons looks up by name. Maintained by tools/public_globals_ledger.py (--write rebuilds it from the",
    "# Suite, MapkoSkin, MidnightCooldownManager and the installed addons; the default mode checks it offline).",
    "# Proved at run time per client by tools/tests/public_globals_smoke.lua. Evidence classes: external (a third-party",
    "# or Mapko addon reads it), suite (the MSUF Suite reads it), integration (published by an Integrations/ bridge for",
    "# other addons), sv (a SavedVariables the client persists), blizzard-contract (the client looks it up: SLASH_*,",
    "# BINDING_*, Bindings.xml actions, XML names, UISpecialFrames, AddonCompartment). consumers: addon:file:line, one",
    "# reading file each, three shown; readers counts the reading files and addons the reading addons. clients: all,",
    "# a flavor list, or static (only the exporter text proves it). A dynamic row is a quoted prefix some addon",
    "# concatenates (\"MSUF_boss\" .. i) and so can reach every exported name that starts with it.",
)


def row_fields(row):
    return [row["name"], row["kind"], row["exporter"], "|".join(row["consumers"]), str(row["readers"]),
            str(row["addons"]), ",".join(row["evidence"]), row["clients"], row["note"]]


def write_ledger(rows, path=LEDGER):
    eol = "\r\n"
    if os.path.isfile(path):
        with open(path, "rb") as handle:
            eol = "\r\n" if b"\r\n" in handle.read(4096) else "\n"
    lines = list(HEADER_COMMENT) + ["\t".join(COLUMNS)] + ["\t".join(row_fields(row)) for row in rows]
    with io.open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(eol.join(lines) + eol)


def parse_ledger(path=LEDGER):
    """(rows, problems) from the ledger file; a row is a dict keyed by COLUMNS with list fields split."""
    if not os.path.isfile(path):
        raise LedgerError("tools/public-globals.tsv is missing; run tools/public_globals_ledger.py --write")
    rows, problems, header = [], [], False
    for number, line in enumerate(read_text(path).split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if not header:
            if tuple(fields) != COLUMNS:
                problems.append("line %d: the header must be %s" % (number, "\t".join(COLUMNS)))
            header = True
            continue
        if len(fields) != len(COLUMNS):
            problems.append("line %d: %d columns, expected %d" % (number, len(fields), len(COLUMNS)))
            continue
        row = dict(zip(COLUMNS, fields))
        row["line"] = number
        row["consumers"] = [c for c in row["consumers"].split("|") if c]
        row["evidence"] = [e for e in row["evidence"].split(",") if e]
        rows.append(row)
    return rows, problems


CONSUMER = re.compile(r"^[^:|\t]+:.+:\d+$")


def evidence_problems(where, row, real):
    """Every evidence class a row carries has to be backed by a consumer entry of that class."""
    problems = []
    suite = [c for c in real if c.startswith("MSUF_Suite")]
    other = [c for c in real if not c.startswith("MSUF_Suite")]
    backing = {
        "suite": suite,
        "external": other,
        "sv": [c for c in row["consumers"] if c.startswith("blizzard:SavedVariables:")],
        "integration": [c for c in row["consumers"] if c.startswith("integration:")],
        "blizzard-contract": [c for c in row["consumers"]
                              if c.startswith("blizzard:") and not c.startswith("blizzard:SavedVariables:")],
    }
    for evidence in row["evidence"]:
        if evidence in backing and not backing[evidence]:
            problems.append("%s: %s evidence needs a %s consumer entry" % (where, evidence, evidence))
    return problems


def validate_rows(rows):
    problems, seen = [], set()
    names = [r["name"] for r in rows]
    if names != sorted(names):
        problems.append("rows must stay sorted by name")
    for row in rows:
        where = "%s (line %d)" % (row["name"], row["line"])
        if row["name"] in seen:
            problems.append("%s: duplicate row" % where)
        seen.add(row["name"])
        if row["kind"] not in KINDS:
            problems.append("%s: unknown kind %r" % (where, row["kind"]))
        if not row["evidence"] or any(e not in EVIDENCE for e in row["evidence"]):
            problems.append("%s: evidence must be a non-empty list of %s" % (where, ", ".join(EVIDENCE)))
        if not row["consumers"] or any(not CONSUMER.match(c) for c in row["consumers"]):
            problems.append("%s: consumers must list addon:file:line readers" % where)
        if not row["readers"].isdigit() or not row["addons"].isdigit():
            problems.append("%s: readers and addons must be numbers" % where)
        else:
            real = [c for c in row["consumers"] if not c.startswith(("blizzard:", "integration:"))]
            if len(real) > int(row["readers"]):
                problems.append("%s: lists %d readers but counts %d" % (where, len(real), int(row["readers"])))
            problems.extend(evidence_problems(where, row, real))
        if row["clients"] not in ("all", "static") and any(c not in FLAVORS for c in row["clients"].split(",")):
            problems.append("%s: clients must be all, static or a flavor list" % where)
        if row["kind"] == "dynamic":
            if not row["name"].endswith("*") or row["exporter"] != "-":
                problems.append("%s: a dynamic row names a prefix ending in * and has no exporter" % where)
        elif not re.match(r"^[^:\t]+:\d+$", row["exporter"]):
            problems.append("%s: exporter must be path:line" % where)
        if row["kind"] == "nsfield":
            table, _, field = row["name"].partition(".")
            if not (NAME_ONLY.match(table) and NAME_ONLY.match(field)):
                problems.append("%s: a nsfield row is named Table.field" % where)
            elif table not in names:
                problems.append("%s: the table %s is not a ledgered global; a field of it cannot outlive it" % (where, table))
    return problems


# --------------------------------------------------------------------------------------
# Check mode
# --------------------------------------------------------------------------------------

def broken_readers(row):
    shown = ", ".join(row["consumers"]) if row["consumers"] else "-"
    more = int(row["readers"]) - len([c for c in row["consumers"] if not c.startswith(("blizzard:", "integration:"))])
    return shown + (" (+%d more reading files)" % more if more > 0 else "")


def exported_by(entry):
    """Does this inventory entry still publish the name as a global?"""
    return entry is not None and entry.primary_global() is not None


class FileScan:
    """What one tracked file exports, read on demand and kept for the rows that name it."""

    def __init__(self, root):
        self.root = root
        self.cache = {}

    def get(self, rel):
        """(exports, has_dynamic_site, comment-free text) of a tracked file, or None when it is gone."""
        if rel not in self.cache:
            path = os.path.join(self.root, rel)
            if not os.path.isfile(path):
                self.cache[rel] = None
            else:
                text = read_text(path)
                exports, dynamic = {}, {}
                if rel.endswith(".lua"):
                    scan_lua(rel, text, exports, dynamic)
                    text = strip_comments(text)
                elif rel.endswith(".xml"):
                    scan_xml(rel, text, exports)
                    text = XML_COMMENT.sub(lambda m: fill(m.group(0), " "), text)
                elif rel.endswith(".toc"):
                    scan_toc(rel, text, exports)
                finish_contracts(exports)
                self.cache[rel] = (exports, bool(dynamic), text)
        return self.cache[rel]


def field_problem(row, scans, root, writers):
    """A nsfield row survives while some source line still writes the field (or the table builds it at run time)."""
    table, _, field = row["name"].partition(".")
    if "dynamic" in row["note"]:
        return None
    path = row["exporter"].rsplit(":", 1)[0]
    tables = table_spellings(table)
    info = scans.get(path) if path.endswith(".lua") else None
    if info is not None and any((t, f) == (table, field) for t, f, _line in writes_in_file(path, info[2], tables)):
        return None
    if writers[0] is None:
        writers[0] = field_writers(root, tables)
    if (table, field) in writers[0]:
        return None
    return "%s: no source line writes the field %s of %s any more (the ledger records %s)" % (
        row["name"], field, table, row["exporter"])


def exporter_problems(rows, root):
    """Rows whose name no source exports any more.

    Fast path: the exporter file the row records still exports the name. A `listed` row (a table-driven
    export) may instead spell the name as a literal there, and a `dynamic` row (built at run time) needs a
    run-time export site there; nothing else counts, so a name left behind in a comment or an unrelated
    string does not vouch for a renamed export. A row the recorded file no longer vouches for sends the
    check through the whole source: a name that only moved to another file passes, a renamed or removed
    one fails with its readers.
    """
    scans, full, problems = FileScan(root), None, []
    writers = [None]
    for row in rows:
        name = row["name"]
        if row["kind"] == "dynamic":
            continue
        if row["kind"] == "nsfield":
            reason = field_problem(row, scans, root, writers)
            if reason:
                problems.append("%s. Readers that would break: %s" % (reason, broken_readers(row)))
            continue
        path = row["exporter"].rsplit(":", 1)[0]
        info = scans.get(path)
        if info is not None:
            exports, has_dynamic, text = info
            if exported_by(exports.get(name)):
                continue
            if "listed" in row["note"] and re.search(r"[\"']%s[\"']" % re.escape(name), text):
                continue
            if "dynamic" in row["note"] and (has_dynamic or path.endswith((".xml", ".toc"))):
                continue
        if full is None:
            full, _dynamic = static_inventory(root)
            finish_contracts(full)
        if exported_by(full.get(name)):
            continue
        reason = ("exporter file %s is gone and no other file exports the name" % path if info is None
                  else "no source exports it any more (the ledger records %s)" % row["exporter"])
        problems.append("%s: %s. Readers that would break: %s" % (name, reason, broken_readers(row)))
    return problems


def prefix_problems(rows, root):
    """A dynamic row needs the quoted prefix to survive somewhere in the addon sources."""
    wanted = {row["name"][:-1]: row for row in rows if row["kind"] == "dynamic"}
    if not wanted:
        return []
    alive = set()
    for rel in addon_files(root):
        if vendored(rel) or not rel.endswith(".lua"):
            continue
        text = read_text(os.path.join(root, rel))
        alive.update(prefix for prefix in wanted if prefix not in alive and prefix in text)
        if len(alive) == len(wanted):
            break
    return ["%s: no addon source mentions the prefix %r any more. Readers that would break: %s"
            % (row["name"], prefix, broken_readers(row)) for prefix, row in sorted(wanted.items()) if prefix not in alive]


def check(root=ROOT):
    rows, problems = parse_ledger(os.path.join(root, "tools", "public-globals.tsv"))
    problems.extend(validate_rows(rows))
    problems.extend(exporter_problems(rows, root))
    problems.extend(prefix_problems(rows, root))
    if problems:
        fail("%d problem%s in tools/public-globals.tsv:\n  %s" % (
            len(problems), "" if len(problems) == 1 else "s", "\n  ".join(problems)))
    classes = collections.Counter(e for row in rows for e in row["evidence"])
    print("public globals ledger: ok (%d rows, every one with an exporter; %s)" % (
        len(rows), ", ".join("%s %d" % (e, classes[e]) for e in EVIDENCE if classes[e])))
    return rows


# --------------------------------------------------------------------------------------
# Reports
# --------------------------------------------------------------------------------------

def summary_lines(result):
    exports, rows = result["exports"], result["rows"]
    names = [n for n in exports if n not in FOREIGN_GLOBALS]
    spaces = [n for n in names if exports[n].namespace_only()]
    names = [n for n in names if not exports[n].namespace_only()]
    kinds = collections.Counter(entry_kind(exports[n]) for n in names)
    flat = [r for r in rows if r["kind"] not in ("dynamic", "nsfield")]
    fields = [r for r in rows if r["kind"] == "nsfield"]
    ledgered = collections.Counter(r["kind"] for r in flat)
    classes = collections.Counter(e for r in flat for e in r["evidence"])
    primary = collections.Counter(r["evidence"][0] for r in flat)
    per_table = collections.Counter(r["name"].partition(".")[0] for r in fields)
    out = ["exported globals: %d (static scan and booted clients); ledgered: %d; also %d namespace-field rows (%s) and "
           "%d dynamic prefix rows" % (len(names), len(flat), len(fields),
                                       ", ".join("%s %d" % item for item in sorted(per_table.items())) or "none",
                                       len([r for r in rows if r["kind"] == "dynamic"])),
           "MSUF_* fields of the addon namespace that no global shadows: %d" % len(spaces),
           "", "kind        exported  ledgered"]
    for kind in sorted(KINDS - {"dynamic", "nsfield"}):
        out.append("%-10s %9d %9d" % (kind, kinds[kind], ledgered[kind]))
    out += ["", "evidence class        rows (a row counts once per class it carries)"]
    for evidence in EVIDENCE:
        out.append("%-20s %5d   (first class of %d rows)" % (evidence, classes[evidence], primary[evidence]))
    vias = collections.Counter()
    for name in names:
        for via in {site[3] for site in exports[name].sites}:
            vias[via] += 1
    out += ["", "export mechanism (a global counts once per mechanism that writes it)"]
    for via in sorted(vias, key=lambda v: RANK[v]):
        out.append("%-10s %5d" % (via, vias[via]))
    out.append("%-10s %5d   (written only at run time; the source text never spells the name)" % (
        "dynamic", len([n for n in names if exports[n].dynamic])))
    return out


def family_lines(families):
    """The run-time export sites: where a name is built from a literal prefix, a suffix or a computed value."""
    out = []
    for rel in sorted(families):
        for family in sorted(families[rel], key=lambda f: f.line):
            if not family.passthrough:
                out.append("%s:%d  %s  %s" % (rel, family.line, family.via, family.describe()))
    return out


def top_lines(rows, count=20):
    real = [r for r in rows if r["kind"] != "dynamic" and int(r["readers"]) > 0]
    real.sort(key=lambda r: (-int(r["addons"]), -int(r["readers"]), r["name"]))
    return ["%2d. %-44s addons %-3s files %-4s %s" % (i, r["name"], r["addons"], r["readers"], ",".join(r["evidence"]))
            for i, r in enumerate(real[:count], 1)]


def dangling_lines(dangling):
    out = []
    for name in sorted(dangling):
        sites = sorted(dangling[name].values(), key=lambda r: (r.addon, r.rel))
        shown = ", ".join("%s:%s:%d" % (r.addon, r.rel, r.line) for r in sites[:3])
        out.append("%s  (%d reading file%s) %s" % (name, len(sites), "" if len(sites) == 1 else "s", shown))
    return out


def inventory_lines(exports):
    out = []
    for name in sorted(n for n in exports if n not in FOREIGN_GLOBALS):
        entry = exports[name]
        out.append("\t".join([name, entry_kind(entry), site_text(entry), entry_clients(entry),
                              entry_note(entry)]))
    return out


# --------------------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------------------

def refresh_exporters(root):
    """Keep readers and evidence; re-read exporter, kind, clients and the exported set from the source."""
    rows, problems = parse_ledger(os.path.join(root, "tools", "public-globals.tsv"))
    if problems:
        fail("cannot refresh a malformed ledger:\n  " + "\n  ".join(problems))
    lua = resolve_lua()
    exports, _families = static_inventory(root)
    runtime, namespace, special = runtime_inventory(root, lua)
    merge_runtime(root, exports, runtime, namespace, special)
    finish_contracts(exports)
    tables = {n for n in exports if entry_kind(exports[n]) == "table"} | set(CANON_TABLE)
    fields = [tuple(row["name"].split(".", 1)) for row in rows if row["kind"] == "nsfield"]
    writers = field_writers(root, tables) if fields else {}
    seen = probe_fields(root, lua, fields) if fields else {}
    dropped = []
    for row in rows:
        if row["kind"] == "dynamic":
            continue
        if row["kind"] == "nsfield":
            key = tuple(row["name"].split(".", 1))
            flavors = [flavor for flavor in FLAVORS if flavor in seen.get(key, {})]
            if key not in writers and not flavors:
                dropped.append(row["name"])
                continue
            row["exporter"] = "%s:%d" % writers[key] if key in writers else site_text(exports[key[0]])
            row["note"] = "" if key in writers else "dynamic"
            row["clients"] = "static" if not flavors else "all" if len(flavors) == len(FLAVORS) else ",".join(flavors)
            continue
        entry = exports.get(row["name"])
        if entry is None or entry.primary() is None:
            dropped.append(row["name"])
            continue
        row["kind"], row["exporter"], row["clients"] = entry_kind(entry), site_text(entry), entry_clients(entry)
        row["note"] = entry_note(entry)
    if dropped:
        fail("no exporter left for %d ledgered name%s (rename or removal), refusing to refresh: %s"
             % (len(dropped), "" if len(dropped) == 1 else "s", ", ".join(dropped)))
    for row in rows:
        row["readers"], row["addons"] = int(row["readers"]), int(row["addons"])
    write_ledger(rows, os.path.join(root, "tools", "public-globals.tsv"))
    print("public globals ledger: exporters refreshed for %d rows" % len(rows))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="rebuild the ledger from the local external sources")
    mode.add_argument("--refresh-exporters", action="store_true", help="re-read exporters and clients, keep readers")
    mode.add_argument("--inventory", action="store_true", help="print every exported name")
    parser.add_argument("--suite-repo", default=DEFAULT_SUITE_REPO)
    parser.add_argument("--repo", action="append", help="another repository of addons to scan (repeatable)")
    parser.add_argument("--wow-root", default=DEFAULT_WOW_ROOT)
    args = parser.parse_args(argv)
    try:
        if args.write:
            repos = args.repo if args.repo else list(DEFAULT_REPOS)
            for path in [args.suite_repo, args.wow_root] + repos:
                if not os.path.isdir(path):
                    fail("%s is missing; --write needs every external source. Pass --suite-repo, --repo or "
                         "--wow-root, or keep the committed ledger." % path)
            result = collect(ROOT, args.suite_repo, repos, args.wow_root)
            write_ledger(result["rows"])
            print("readers searched in %d addon folders" % result["sources"])
            print("\n".join(summary_lines(result)))
            print("\ntop consumed names:")
            print("\n".join(top_lines(result["rows"])))
            print("\nreads of MSUF-looking names nothing exports (%d):" % len(result["dangling"]))
            print("\n".join(dangling_lines(result["dangling"])))
            print("\nrun-time export sites, where a name is built when the code runs (%d); names an outside source "
                  "reads that one of them publishes: %s" % (len(family_lines(result["families"])),
                                                           ", ".join(result["promoted"]) or "none"))
            print("\n".join(family_lines(result["families"])))
            print("\nreads of table fields no source writes and no booted client holds (%d): %s" % (
                len(result["unmatched_fields"]), ", ".join("%s.%s" % key for key in result["unmatched_fields"])))
            if result["unexported"]:
                print("\nnames the client resolves that no source exports: " + ", ".join(result["unexported"]))
            if result["unparsed"]:
                print("\nfiles luac rejected (scanned by text only): %d" % len(result["unparsed"]))
            check(ROOT)
        elif args.refresh_exporters:
            refresh_exporters(ROOT)
            check(ROOT)
        elif args.inventory:
            exports, families = static_inventory(ROOT)
            finish_contracts(exports)
            print("\n".join(inventory_lines(exports)))
            print("\n# run-time export sites")
            print("\n".join("# " + line for line in family_lines(families)))
        else:
            check(ROOT)
    except LedgerError as error:
        fail(str(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
