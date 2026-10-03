"""Feature inventory gate (N1): no setting, label, slash command, binding or locale key disappears silently.

Usage (from the repo root; Python 3.12; git only for --freeze, --baseline-rev and --provenance):
  python tools/feature_inventory.py                    # check against the frozen baseline (default)
  python tools/feature_inventory.py --diff             # list every removed and added item
  python tools/feature_inventory.py --freeze [REV]     # rewrite the frozen baseline from a commit
  python tools/feature_inventory.py --baseline-rev REV # check against a commit instead of the snapshot
  python tools/feature_inventory.py --provenance       # name the commit that removed each removed item
  python tools/feature_inventory.py --verify-baseline  # the snapshot still equals a fresh extraction of its commit

What is extracted, from MidnightSimpleUnitFrames/ and MidnightSimpleUnitFrames_Options/ (Libs/ skipped):
  locale    the enUS keys, L["key"] = ...
  slash     SLASH_x1 = "/cmd" commands, SlashCmdList["x"] handlers, Commands.Register({name=, aliases=})
            sub-commands (as "/msuf name") and RegisterExternal({usage=}) command lines
  bindings  <Binding name=> in Bindings.xml and BINDING_NAME_x / BINDING_HEADER_x globals
  settings  the settingKey column of the generated Menu2 search index (one set per client index)
  rows      every row of that index as one stable identity: client, page, section path, label, control
            kind, setting key, action key and the route that names the control. Losing one control
            changes the inventory even when another row shares its label or key; identical rows
            count once each (#2, #3). A control that moves section or route is a removal plus an add.
  actions   the actionKey column of the same index (the menu buttons)
  defaults  the keys the defaults files seed: x.key == nil, x.key = v and { key = v } in
            State/MSUF_Defaults.lua, State/Defaults/ and State/MSUF_AuraDefaults.lua
  exports   Export("n"), ExportPublic("n") and PublishCompat("n") public global names
Lua and XML comments are removed before matching (a commented-out key, binding or assignment is a
removal); strings that contain "--" survive. Each category is a set of strings; nothing else is compared.

Check. The frozen baseline tools/feature_inventory_baseline.json (made from the commit named in it,
default 1908d740, the Classic state before the quality program) is compared with the current tree.
Every item the baseline has and the tree lacks is a removal; a removal fails the check unless
tools/feature_inventory_allowlist.json lists it. Items that only exist now are counted, never failed.
The check needs no git history, so shallow CI clones work; it always ends with one summary line.

Allowlist (tools/feature_inventory_allowlist.json), "removed" entries:
  {"category": "exports", "items": ["MSUF_X", "MSUF_Y"],      "item": "MSUF_Z" (one or "items", trailing * allowed)
   "basis": "migration" | "owner" | "dead" | "moved",
   "evidence": "where the proof lives: a commit, the migration's file, the owner decision",
   "reason": "one sentence", "date": "2026-10-02"}
  migration  the data moves through a migration or the defaults pass; evidence names it
  owner      Mapko decided to drop it; evidence names the decision
  dead       proven unreachable (zero callers in every addon, XML and string dispatch); evidence names the commit
  moved      the same feature lives on under another name; evidence names the new place
Evidence is free text for the reviewer (commit ids included); reading it never needs the history.
Entries that match no removal are counted as stale; --freeze prunes them.
"""

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parent
BASELINE_NAME = "feature_inventory_baseline.json"
ALLOWLIST_NAME = "feature_inventory_allowlist.json"
DEFAULT_REV = "1908d740"
EXTRACTOR_VERSION = 2
ADDONS = ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")
CATEGORIES = ("locale", "slash", "bindings", "settings", "rows", "actions", "defaults", "exports")
BASES = ("migration", "owner", "dead", "moved")
LOCALE_FILE = "MidnightSimpleUnitFrames/Locales/enUS.lua"
DEFAULTS_FILES = re.compile(r"^MidnightSimpleUnitFrames/State/(?:MSUF_Defaults\.lua|MSUF_AuraDefaults\.lua|Defaults/[^/]+\.lua)$")
INDEX_FILE = re.compile(r"/Search/MSUF_Menu2_Search_StaticIndex_Data(_Classic)?\.lua$")


# ------------------------------------------------------------------ reading a tree
def git(root, *args):
    run = subprocess.run(["git", "-C", str(root)] + list(args), capture_output=True)
    return run.returncode, run.stdout


def wanted_path(path):
    return (path.startswith(tuple(a + "/" for a in ADDONS)) and path.endswith((".lua", ".xml"))
            and "/Libs/" not in path)


def read_working_tree(root):
    files = {}
    for addon in ADDONS:
        folder = root / addon
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob("*")):
            rel = path.relative_to(root).as_posix()
            if path.is_file() and wanted_path(rel):
                files[rel] = path.read_bytes().decode("utf-8", "replace").replace("\r\n", "\n")
    return files


def rev_exists(root, rev):
    code, _ = git(root, "cat-file", "-e", rev + "^{commit}")
    return code == 0


def read_revision(root, rev):
    code, listing = git(root, "ls-tree", "-r", "--name-only", rev, "--", *ADDONS)
    if code != 0:
        raise SystemExit("FAIL git cannot list %s: is the commit in this clone?" % rev)
    paths = [p for p in listing.decode("utf-8", "replace").splitlines() if wanted_path(p)]
    process = subprocess.Popen(["git", "-C", str(root), "cat-file", "--batch"], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE)
    files = {}
    with process:
        for path in paths:
            process.stdin.write(("%s:%s\n" % (rev, path)).encode("utf-8"))
            process.stdin.flush()
            header = process.stdout.readline().decode("utf-8", "replace").split()
            if len(header) < 3 or header[1] == "missing":
                continue
            data = process.stdout.read(int(header[2]))
            process.stdout.read(1)
            files[path] = data.decode("utf-8", "replace").replace("\r\n", "\n")
        process.stdin.close()
    return files


# ------------------------------------------------------------------ extraction
LUA_TOKEN = re.compile(r"--\[(=*)\[|--[^\n]*|\[(=*)\[|\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'", re.S)
XML_COMMENT = re.compile(r"<!--.*?-->", re.S)
LOCALE_KEY = re.compile(r'^[ \t]*L\[\s*"((?:[^"\\\n]|\\.)*)"\s*\]\s*=', re.M)
SLASH_COMMAND = re.compile(r'(?<![A-Za-z_])SLASH_(\w*?)\d+\s*=\s*"(/[^"]*)"')
SLASH_HANDLER = re.compile(r'SlashCmdList\[\s*"(\w+)"\s*\]\s*=')
SLASH_REGISTER = re.compile(r'Commands\.Register\(\{\s*name\s*=\s*"(\w+)"(.*?)\brun\s*=', re.S)
SLASH_ALIASES = re.compile(r"aliases\s*=\s*\{([^}]*)\}")
SLASH_EXTERNAL = re.compile(r'RegisterExternal\(\{[^}]*?usage\s*=\s*"([^"]+)"', re.S)
BINDING_XML = re.compile(r'<Binding\s+name\s*=\s*"([^"]+)"', re.I)
BINDING_LUA = re.compile(r"(?<![\w.])(BINDING_(?:NAME|HEADER)_\w+)\s*=")
EXPORT = re.compile(r'\b(?:Export|ExportPublic|PublishCompat)\(\s*"([^"]+)"')
DEFAULT_SEED = re.compile(r"\.([A-Za-z_]\w*)\s*==\s*nil")
DEFAULT_ASSIGN = re.compile(r"\.([A-Za-z_]\w*)\s*=(?!=)")
DEFAULT_TABLE = re.compile(r"[{,]\s*([A-Za-z_]\w*)\s*=(?!=)")
INDEX_BLOB = re.compile(r"StaticIndexBlob\s*=\s*\[(=*)\[\n(.*?)\]\1\]", re.S)


def strip_comments(text):
    """Lua source without comments. Strings are skipped as tokens, so a "--" inside one is kept;
    every line break is kept too, so line-anchored patterns still work."""
    out, position = [], 0
    for match in LUA_TOKEN.finditer(text):
        start, end = match.span()
        if start < position:
            continue
        out.append(text[position:start])
        token = match.group(0)
        if token.startswith("--"):
            if match.group(1) is not None:
                close = text.find("]" + match.group(1) + "]", end)
                end = len(text) if close < 0 else close + len(match.group(1)) + 2
                out.append("\n" * text.count("\n", start, end))
            position = end
            continue
        if match.group(2) is not None:
            close = text.find("]" + match.group(2) + "]", end)
            end = len(text) if close < 0 else close + len(match.group(2)) + 2
            out.append(text[start:end])
            position = end
            continue
        out.append(token)
        position = end
    out.append(text[position:])
    return "".join(out)


def strip_xml_comments(text):
    return XML_COMMENT.sub("", text)


def index_rows(text):
    match = INDEX_BLOB.search(text)
    if not match:
        return []
    rows = []
    for line in match.group(2).split("\n"):
        columns = line.split("\t")
        if len(columns) >= 8:
            rows.append(columns)
    return rows


def row_route(columns):
    """The route that names a control: column 7 is "id", the page and "menu2.<page>.<route>" joined by
    the unit separator, with the dots percent-encoded. The fixed prefix is dropped, the rest decoded."""
    identity = unquote(columns[7]).replace("\x1f", "/")
    prefix = "id/%s/menu2.%s." % (columns[0], columns[0])
    return identity[len(prefix):] if identity.startswith(prefix) else identity


def row_items(tag, rows):
    """One stable identity per index row; a row seen twice gets #2, #3 so losing one is visible."""
    items, seen = [], {}
    for columns in rows:
        page, label, kind, setting, action, hint = columns[:6]
        key = " ".join(part for part in (setting, "action " + action if action else "") if part) or "no key"
        item = "%s: %s | %s | %s | %s | %s | %s" % (tag, page, hint, label, kind, key, row_route(columns))
        seen[item] = seen.get(item, 0) + 1
        items.append(item if seen[item] == 1 else "%s #%d" % (item, seen[item]))
    return items


def extract(files):
    """{category: set of strings} of one tree ({repo path: text})."""
    items = {name: set() for name in CATEGORIES}
    for path, text in files.items():
        if not wanted_path(path):
            continue
        if path.endswith(".xml"):
            items["bindings"].update("binding " + name for name in BINDING_XML.findall(strip_xml_comments(text)))
            continue
        if path == LOCALE_FILE:
            items["locale"].update(LOCALE_KEY.findall(strip_comments(text)))
        index = INDEX_FILE.search(path)
        if index:
            tag = "classic" if index.group(1) else "main"
            rows = index_rows(text)
            items["rows"].update(row_items(tag, rows))
            for columns in rows:
                if columns[3]:
                    items["settings"].add("%s: %s" % (tag, columns[3]))
                if columns[4]:
                    items["actions"].add("%s: %s" % (tag, columns[4]))
            continue
        if "/Locales/" in path:
            continue
        code = strip_comments(text)
        items["slash"].update(match.group(2) for match in SLASH_COMMAND.finditer(code))
        items["slash"].update("handler " + name for name in SLASH_HANDLER.findall(code))
        for match in SLASH_REGISTER.finditer(code):
            items["slash"].add("/msuf " + match.group(1))
            aliases = SLASH_ALIASES.search(match.group(2))
            if aliases:
                items["slash"].update("/msuf " + alias for alias in re.findall(r'"(\w+)"', aliases.group(1)))
        items["slash"].update(SLASH_EXTERNAL.findall(code))
        items["bindings"].update(BINDING_LUA.findall(code))
        items["exports"].update(EXPORT.findall(code))
        if DEFAULTS_FILES.match(path):
            for pattern in (DEFAULT_SEED, DEFAULT_ASSIGN, DEFAULT_TABLE):
                items["defaults"].update(pattern.findall(code))
    return items


# ------------------------------------------------------------------ baseline
def snapshot_from(items, rev, commit):
    return {"about": "Frozen feature inventory (tools/feature_inventory.py --freeze); do not edit by hand.",
            "rev": rev, "commit": commit, "extractor": EXTRACTOR_VERSION,
            "items": {name: sorted(items[name]) for name in CATEGORIES}}


def write_snapshot(path, snapshot):
    lines = ["{", ' "about": %s,' % json.dumps(snapshot["about"]), ' "rev": %s,' % json.dumps(snapshot["rev"]),
             ' "commit": %s,' % json.dumps(snapshot["commit"]),
             ' "extractor": %d,' % snapshot["extractor"], ' "items": {']
    for number, name in enumerate(CATEGORIES):
        entries = snapshot["items"][name]
        lines.append('  %s: [' % json.dumps(name))
        lines.extend("   %s%s" % (json.dumps(item, ensure_ascii=False), "," if index < len(entries) - 1 else "")
                     for index, item in enumerate(entries))
        lines.append("  ]%s" % ("," if number < len(CATEGORIES) - 1 else ""))
    lines += [" }", "}"]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def read_snapshot(path):
    if not path.is_file():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    data["sets"] = {name: set(data["items"].get(name, [])) for name in CATEGORIES}
    return data


# ------------------------------------------------------------------ allowlist
def allowlist_entries(allowlist):
    """[(category, pattern, entry)] with one row per listed item."""
    rows = []
    for entry in allowlist.get("removed", []):
        names = list(entry.get("items", []))
        if "item" in entry:
            names.append(entry["item"])
        rows.extend((entry.get("category"), name, entry) for name in names)
    return rows


def allowlist_problems(allowlist):
    problems = []
    for index, entry in enumerate(allowlist.get("removed", [])):
        label = "allowlist entry %d (%s %s)" % (index + 1, entry.get("category"), entry.get("item") or "list")
        if entry.get("category") not in CATEGORIES:
            problems.append("%s names an unknown category (known: %s)" % (label, ", ".join(CATEGORIES)))
        if not (entry.get("item") or entry.get("items")):
            problems.append("%s names no item" % label)
        if entry.get("basis") not in BASES:
            problems.append("%s needs a basis (%s)" % (label, ", ".join(BASES)))
        for field in ("evidence", "reason"):
            if not str(entry.get(field, "")).strip():
                problems.append("%s needs %s" % (label, field))
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(entry.get("date", ""))):
            problems.append("%s needs a date (YYYY-MM-DD)" % label)
    return problems


def compare(baseline_sets, current, allowlist):
    """(removed {category: [(item, entry or None)]}, added {category: [items]}, used entries)."""
    rows = allowlist_entries(allowlist)
    removed, added, used = {}, {}, set()
    for name in CATEGORIES:
        gone, listed = sorted(baseline_sets[name] - current[name]), []
        for item in gone:
            match = None
            for category, pattern, entry in rows:
                if category == name and (pattern == item or ("*" in pattern and fnmatch.fnmatchcase(item, pattern))):
                    match = entry
                    used.add((category, pattern))
                    break
            listed.append((item, match))
        removed[name] = listed
        added[name] = sorted(current[name] - baseline_sets[name])
    return removed, added, used


# ------------------------------------------------------------------ provenance
def provenance(root, rev, removed_items):
    """{(category, item): [commit subjects]}: commits after rev whose removed lines carry the item's text."""
    code, log = git(root, "log", "-p", "--no-color", "--format=@@@%h %s", "-U0", rev + "..HEAD", "--",
                    "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options",
                    ":(exclude)*StaticIndex_Data*", ":(exclude)*Libs/*")
    if code != 0:
        raise SystemExit("FAIL git log failed; is %s in this clone?" % rev)
    needles = {}
    for category, item in removed_items:
        if category == "rows":
            needle = item.split(" | ")[2]
        elif category in ("settings", "actions"):
            needle = item.split(": ", 1)[1]
        elif category == "slash":
            needle = item.split(" ")[-1]
        elif category == "bindings":
            needle = item.split(" ")[-1]
        else:
            needle = item
        needles[(category, item)] = needle
    found = {key: [] for key in needles}
    commit = None
    removed_text, added_text = [], []

    def flush():
        if commit is None:
            return
        gone, came = "\n".join(removed_text), "\n".join(added_text)
        for key, needle in needles.items():
            if needle in gone and gone.count(needle) > came.count(needle) and commit not in found[key]:
                found[key].append(commit)

    for line in log.decode("utf-8", "replace").split("\n"):
        if line.startswith("@@@"):
            flush()
            commit, removed_text, added_text = line[3:], [], []
        elif line.startswith("-") and not line.startswith("---"):
            removed_text.append(line[1:])
        elif line.startswith("+") and not line.startswith("+++"):
            added_text.append(line[1:])
    flush()
    return found


# ------------------------------------------------------------------ main
def load_json(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}


def summary(rev, snapshot_total, removed, added, used, rows, problems):
    gone = sum(len(entries) for entries in removed.values())
    open_removals = sum(1 for entries in removed.values() for _, entry in entries if entry is None)
    stale = len({(c, p) for c, p, _ in rows} - used)
    per = ", ".join("%s -%d" % (name, len(removed[name])) for name in CATEGORIES if removed[name])
    return ("feature inventory (baseline %s, %d items): %d removed (%d allowlisted, %d open)%s, %d added, "
            "%d stale allowlist items, %d problems"
            % (rev, snapshot_total, gone, gone - open_removals, open_removals, " [%s]" % per if per else "",
               sum(len(items) for items in added.values()), stale, problems))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Feature inventory gate (see the module docstring).")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail on an unlisted removal (default)")
    mode.add_argument("--diff", action="store_true", help="list every removed and added item")
    mode.add_argument("--freeze", nargs="?", const=DEFAULT_REV, metavar="REV", help="rewrite the frozen baseline")
    mode.add_argument("--provenance", action="store_true", help="name the commit that removed each item")
    mode.add_argument("--verify-baseline", action="store_true", help="snapshot equals a fresh extraction of its commit")
    parser.add_argument("--root", default=str(DEFAULT_ROOT))
    parser.add_argument("--baseline-rev", default=None, help="compare with this commit instead of the snapshot")
    parser.add_argument("--baseline", default=None, help="snapshot path")
    parser.add_argument("--allowlist", default=None, help="allowlist path")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    snapshot_path = Path(args.baseline) if args.baseline else root / "tools" / BASELINE_NAME
    allowlist_path = Path(args.allowlist) if args.allowlist else root / "tools" / ALLOWLIST_NAME
    allowlist = load_json(allowlist_path)

    if args.freeze is not None:
        files = read_revision(root, args.freeze)
        code, commit = git(root, "rev-parse", args.freeze + "^{commit}")
        items = extract(files)
        write_snapshot(snapshot_path, snapshot_from(items, args.freeze, commit.decode().strip()))
        print("feature inventory: baseline frozen from %s (%d items in %d categories)"
              % (args.freeze, sum(len(v) for v in items.values()), len(CATEGORIES)))
        return 0

    snapshot = read_snapshot(snapshot_path)
    if args.verify_baseline:
        if snapshot is None:
            print("FAIL no baseline at %s" % snapshot_path)
            return 1
        if not rev_exists(root, snapshot["commit"]):
            print("feature inventory: baseline commit %s is not in this clone; the snapshot is used as frozen"
                  % snapshot["rev"])
            return 0
        fresh = extract(read_revision(root, snapshot["commit"]))
        drift = [name for name in CATEGORIES if fresh[name] != snapshot["sets"][name]]
        if snapshot["extractor"] != EXTRACTOR_VERSION or drift:
            print("FAIL the baseline snapshot differs from a fresh extraction of %s (%s); run --freeze %s"
                  % (snapshot["rev"], ", ".join(drift) or "extractor version", snapshot["rev"]))
            return 1
        print("feature inventory: baseline snapshot equals a fresh extraction of %s" % snapshot["rev"])
        return 0

    if args.baseline_rev:
        sets, rev = extract(read_revision(root, args.baseline_rev)), args.baseline_rev
    else:
        if snapshot is None:
            print("FAIL no baseline at %s; create it with --freeze" % snapshot_path)
            return 1
        if snapshot["extractor"] != EXTRACTOR_VERSION:
            print("FAIL the baseline was frozen by extractor %s, this tool is %d; run --freeze"
                  % (snapshot["extractor"], EXTRACTOR_VERSION))
            return 1
        sets, rev = snapshot["sets"], snapshot["rev"]
    current = extract(read_working_tree(root))
    removed, added, used = compare(sets, current, allowlist)
    rows = allowlist_entries(allowlist)
    problems = allowlist_problems(allowlist)

    if args.provenance:
        keys = [(name, item) for name in CATEGORIES for item, _ in removed[name]]
        found = provenance(root, args.baseline_rev or snapshot["commit"], keys)
        for name, item in keys:
            print("%s | %s | %s" % (name, item, "; ".join(found[(name, item)]) or "no commit found"))
        return 0
    if args.diff:
        for name in CATEGORIES:
            for item, entry in removed[name]:
                print("- %s | %s%s" % (name, item, "" if entry is None else "   [allowlisted: %s]" % entry["basis"]))
            for item in added[name]:
                print("+ %s | %s" % (name, item))

    for problem in problems:
        print("FAIL " + problem)
    open_items = [(name, item) for name in CATEGORIES for item, entry in removed[name] if entry is None]
    for name, item in open_items:
        print("FAIL removed %s: %s" % (name, item))
    total = sum(len(v) for v in sets.values())
    print(summary(rev, total, removed, added, used, rows, len(problems)))
    return 1 if open_items or problems else 0


if __name__ == "__main__":
    sys.exit(main())
