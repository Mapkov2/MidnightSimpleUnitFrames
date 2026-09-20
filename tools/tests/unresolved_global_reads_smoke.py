"""No shipped Lua chunk reads a global that resolves to nothing.

Lua 5.1 makes an undefined name a silent nil read: `CoreFrame(unit)` compiles,
ships, and only raises when that line finally runs. Eight of the bugs this file
exists for lived in shipped code for weeks because the line was rare (a preview
re-check, a fail-closed guard) or because its result was only tested for truth
(`ok ~= false`, `DetectDirection and DetectDirection(...)`), so nothing ever
raised at all.

The rule: compile every Lua file of the three addons with `luac -l -p` and read
the GETGLOBAL instructions out of the bytecode listing - the compiler's own
answer to "which names are read from the global table", with no regex guessing
about scope. A read is resolved when it is

  * a Lua 5.1 standard-library name, or
  * a global this source tree defines: a SETGLOBAL anywhere in it, an assignment
    to `_G.Name` (or to a `local G = _G` alias), or an ExportPublic/ExportGlobal/
    ExportCompat registration that publishes the name, or
  * a reviewed row in tools/lua-global-reads.tsv - Blizzard APIs, Blizzard UI
    frames and constants, third-party addon globals, and the few known defects
    that are deliberately left in place, each with a reason.

Anything else fails, and so does a reviewed row nothing uses any more, the same
way tools/client-boot-globals.tsv keeps its own allowlist honest.

The same listing answers the other half of the question. A SETGLOBAL is a global
this addon writes, and the only globals it may write are its own: MSUF_*, its
BINDING_* keybinding strings and its SLASH_* commands. An accidental one -
`canonical, _, retiredLabel = ...` with no `local _` - leaks a name into every
other addon's environment, so an unowned write fails here too, and is reviewed in
the same file with Kind `write`.

Runs on Windows and on Linux CI: it needs `luac` (5.1) from MSUF_LUAC or PATH and
nothing else. Run it from anywhere; it finds the repository root from its own
path.
"""
import io
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDONS = (
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options",
    "MidnightSimpleUnitFrames_Assistant",
)
ALLOWLIST = os.path.join(ROOT, "tools", "lua-global-reads.tsv")
KINDS = frozenset("api namespace frame constant table unit luaenv thirdparty defect "
                  "vestigial write".split())

# Lua 5.1's own global names. Every other global belongs to Blizzard, to a third
# party, or to this addon, and is resolved by a definition or a reviewed row.
LUA_STDLIB = frozenset("""
_G _VERSION assert collectgarbage dofile error getfenv getmetatable ipairs load
loadfile loadstring module next pairs pcall print rawequal rawget rawset require
select setfenv setmetatable tonumber tostring type unpack xpcall
coroutine debug io math os package string table
""".split())

# One pass over the listing. luac -l prints a header per compiled function, both
# forms carrying that function's source file, then one tab-separated line per
# instruction; the global's name is the comment at the end of the line. Matching
# headers and GETGLOBAL/SETGLOBAL lines with a single ordered scan over the raw
# bytes keeps a 130 MB listing well inside the gate's time budget.
LISTING = re.compile(
    rb"(?m)^(?:main|function) <([^>]+):\d+,\d+>"
    rb"|^\t\d+\t\[(\d+)\]\t([GS])ETGLOBAL\t[^\t]*\t; (\S+)\r?$")

# The globals this addon is allowed to write: its own namespace, its keybinding
# header/name strings and its slash commands. Blizzard reads the last two by
# name, so they cannot carry the MSUF_ prefix.
OWNED_WRITE = re.compile(
    r"^(?:MSUF_|BINDING_HEADER_MSUF_|BINDING_NAME_MSUF_|SLASH_MSUF|SLASH_MIDNIGHTSUF)")

# Definitions the bytecode cannot show, because they write through a table.
G_FIELD = re.compile(r"(?<![\w.])(?:_G|%s)\.([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)")
G_INDEX = re.compile(r"(?<![\w.])(?:_G|%s)\[\s*[\"']([A-Za-z_][A-Za-z0-9_]*)[\"']\s*\]\s*=(?!=)")
G_ALIAS = re.compile(r"^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*_G\s*$", re.M)
EXPORT = re.compile(
    r"\bExport(?:Public|Global|Compat)\s*\(\s*[\"']([A-Za-z_][A-Za-z0-9_]*)[\"']\s*(,[^)]*)?\)")


def fail(message):
    print("unresolved global reads smoke FAILED: " + message)
    raise SystemExit(1)


def read_text(path):
    with io.open(path, "r", encoding="utf-8", errors="replace", newline="") as handle:
        return handle.read().replace("\r\n", "\n")


def lua_files():
    # Only files git tracks ship, so only those are scanned. Walking the disk
    # would also pick up scratch scripts a working tree happens to hold, which
    # run under lua.exe rather than in the client and answer to no client rule.
    listed = subprocess.run(["git", "-C", ROOT, "ls-files", "-z", "--"] + list(ADDONS),
                            stdout=subprocess.PIPE)
    if listed.returncode != 0:
        fail("git ls-files failed for the addon folders")
    found = []
    for rel in listed.stdout.decode("utf-8").split("\0"):
        if not rel.lower().endswith(".lua"):
            continue
        path = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.isfile(path):
            fail("tracked Lua file is missing from the working tree: " + rel)
        found.append(path)
    if not found:
        fail("no tracked Lua files found in the addon folders")
    found.sort()
    return found


def resolve_luac():
    candidate = os.environ.get("MSUF_LUAC") or shutil.which("luac")
    if not candidate or not os.path.exists(candidate):
        fail("no luac on PATH and MSUF_LUAC is unset; the Classic gate resolves both")
    probe = subprocess.run([candidate, "-v"], capture_output=True, text=True, errors="replace")
    banner = ((probe.stdout or "") + (probe.stderr or "")).strip()
    if not banner.startswith("Lua 5.1"):
        fail("luac must be Lua 5.1: %s reports %r" % (candidate, banner))
    return candidate


def batches(paths, limit=24000):
    """Group files into command lines luac and every shell can still take."""
    batch, length = [], 0
    for path in paths:
        if batch and length + len(path) + 3 > limit:
            yield batch
            batch, length = [], 0
        batch.append(path)
        length += len(path) + 3
    if batch:
        yield batch


def listing(luac, paths):
    """GETGLOBAL reads and SETGLOBAL writes of every file, attributed by source."""
    reads, writes = {}, set()
    for batch in batches(paths):
        run = subprocess.run([luac, "-l", "-p"] + batch, capture_output=True)
        if run.returncode != 0:
            fail("luac could not compile a batch starting at %s:\n%s"
                 % (os.path.relpath(batch[0], ROOT), (run.stderr or b"").decode("utf-8", "replace").strip()))
        source, matched = None, 0
        for entry in LISTING.finditer(run.stdout):
            header = entry.group(1)
            if header is not None:
                candidate = header.decode("utf-8", "replace")
                # luac wraps several files in a synthetic "(luac)" chunk of its own.
                source = None if candidate == "(luac)" else (
                    os.path.relpath(candidate, ROOT).replace("\\", "/"))
                continue
            matched += 1
            if source is None:
                continue
            name = entry.group(4).decode("utf-8", "replace")
            if entry.group(3) == b"S":
                writes.add(name)
            else:
                reads.setdefault(name, []).append(
                    source + ":" + entry.group(2).decode("ascii"))
        if matched == 0:
            fail("luac printed no GETGLOBAL or SETGLOBAL line for a batch of %d files; its "
                 "listing format changed and this smoke would silently pass" % len(batch))
    return reads, writes


# ExportPublic(name, value, false) deliberately publishes no global.
UNPUBLISHED = re.compile(r"^\s*,[^,]*,\s*false\s*$")


def table_definitions(paths):
    """Globals published through a table write, which SETGLOBAL never shows.

    The `_G` alias set is read per file, so one file's `local G = _G` can never
    resolve another file's unrelated `G`; the compiled pair is cached per alias
    set, because in practice there are only a handful of them.
    """
    defined, compiled = set(), {}
    for path in paths:
        text = read_text(path)
        aliases = tuple(sorted(set(G_ALIAS.findall(text))))
        pair = compiled.get(aliases)
        if pair is None:
            alternation = "|".join(re.escape(alias) for alias in aliases) or r"\0"
            pair = (re.compile(G_FIELD.pattern % alternation),
                    re.compile(G_INDEX.pattern % alternation))
            compiled[aliases] = pair
        for pattern in pair:
            defined.update(pattern.findall(text))
        for name, rest in EXPORT.findall(text):
            if not UNPUBLISHED.match(rest or ""):
                defined.add(name)
    return defined


def allowlist():
    if not os.path.isfile(ALLOWLIST):
        fail("missing the reviewed allowlist: tools/lua-global-reads.tsv")
    rows, order = {}, []
    for number, line in enumerate(read_text(ALLOWLIST).splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if fields[0] == "Global":
            continue
        if len(fields) != 3 or not all(field.strip() for field in fields):
            fail("tools/lua-global-reads.tsv line %d needs Global<TAB>Kind<TAB>Reason: %r"
                 % (number, line))
        name, kind, reason = (field.strip() for field in fields)
        if kind not in KINDS:
            fail("tools/lua-global-reads.tsv line %d has Kind %r; use one of %s"
                 % (number, kind, ", ".join(sorted(KINDS))))
        if name in rows:
            fail("tools/lua-global-reads.tsv lists %s twice (line %d)" % (name, number))
        rows[name] = (kind, reason)
        order.append(name)
    if order != sorted(order):
        fail("tools/lua-global-reads.tsv must stay sorted by Global; "
             "first out of order: " + next(a for a, b in zip(order, sorted(order)) if a != b))
    return rows


def main():
    started = time.time()
    luac = resolve_luac()
    paths = lua_files()
    if len(paths) < 500:
        fail("only %d Lua files found under %s; the scan must cover all three addons"
             % (len(paths), ROOT))
    reads, writes = listing(luac, paths)
    defined = writes | table_definitions(paths)
    reviewed = allowlist()

    unresolved = sorted(name for name in reads
                        if name not in LUA_STDLIB and name not in defined and name not in reviewed)
    if unresolved:
        lines = []
        for name in unresolved:
            sites = reads[name]
            shown = ", ".join(sites[:3]) + ("" if len(sites) <= 3 else ", +%d more" % (len(sites) - 3))
            lines.append("  %s  (%d read%s) %s" % (name, len(sites), "" if len(sites) == 1 else "s", shown))
        fail("%d global name%s resolve%s to nothing: not Lua 5.1, not defined by this tree, not "
             "reviewed in tools/lua-global-reads.tsv.\n%s\nFix the read, or add a reviewed row "
             "with a reason if the name is a Blizzard, third-party or deliberately unfixed one."
             % (len(unresolved), "" if len(unresolved) == 1 else "s",
                "s" if len(unresolved) == 1 else "", "\n".join(lines)))

    unowned = sorted(name for name in writes
                     if not OWNED_WRITE.match(name) and reviewed.get(name, ("", ""))[0] != "write")
    if unowned:
        fail("%d global name%s written by this tree %s not MSUF-owned and not reviewed with "
             "Kind write: %s.\nA bare assignment with no `local` is the usual cause; declare the "
             "local, or add a reviewed row if the write is deliberate."
             % (len(unowned), "" if len(unowned) == 1 else "s",
                "is" if len(unowned) == 1 else "are", ", ".join(unowned)))

    stale = sorted(name for name in reviewed if name not in reads and name not in writes)
    if stale:
        fail("tools/lua-global-reads.tsv reviews %d global%s nothing reads or writes any more; "
             "drop the row%s: %s" % (len(stale), "" if len(stale) == 1 else "s",
                                     "" if len(stale) == 1 else "s", ", ".join(stale)))

    redundant = sorted(name for name, (kind, _reason) in reviewed.items()
                       if kind != "write" and (name in defined or name in LUA_STDLIB))
    if redundant:
        fail("tools/lua-global-reads.tsv reviews %d global%s this tree already defines; drop the "
             "row%s: %s" % (len(redundant), "" if len(redundant) == 1 else "s",
                            "" if len(redundant) == 1 else "s", ", ".join(redundant)))

    total = sum(len(sites) for sites in reads.values())
    print("unresolved global reads smoke: ok (%d Lua files, %d global reads of %d names, "
          "%d defined here, %d MSUF-owned global writes, %d reviewed rows, %.1fs)"
          % (len(paths), total, len(reads), len(defined), len(writes), len(reviewed),
             time.time() - started))


if __name__ == "__main__":
    main()
