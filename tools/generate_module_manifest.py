#!/usr/bin/env python3
"""Render shipped load lists and locale work from module-manifest.json, without Lua.

--write updates derived files; --check compares bytes and never writes anything.
The manifest is the only registration edit for a new module. See
docs/module-manifest.md for placement, client flags and reviewed API boundaries.
"""

import argparse
import csv
import hashlib
import io
import json
import posixpath
import re
import sys
from pathlib import Path

MANIFEST = "tools/module-manifest.json"
CORE = "MidnightSimpleUnitFrames"
ADDONS = (CORE, CORE + "_Options", CORE + "_Locales")
LOCALE_DIR = CORE + "/Locales"
EXCLUSIONS = "tools/classic-flavor-load-exclusions.tsv"
UNLOADED = "tools/classic-unloaded-addon-lua.tsv"
LOCK = "tools/load-graph.lock"
LOCALE_REPORT = "docs/locale-missing-keys.json"
REVIEW_LISTS = {
    "tools/client-boot-globals.tsv", "tools/lua-global-reads.tsv",
    "tools/optional-globals.tsv", "tools/global-links-ledger.tsv",
    "tools/public-globals.tsv", "tools/classic-toc-identity.tsv",
}
REFERENCE = re.compile(r'<(?:\w+:)?(?:Script|Include)\s+file="([^"]+)"')
CONDITION = re.compile(r"^(.*?)\s+\[(\w+)\s+([^\]]+)\]\s*$")
LONG_OPEN = re.compile(r"\[(=*)\[")
LUA_NAME = re.compile(r"\w+")
LUA_NUMBER_ESCAPE = re.compile(r"\d{1,3}")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def clean_path(path):
    require(isinstance(path, str) and "\\" not in path, "use relative forward-slash paths")
    require(path == posixpath.normpath(path) and not path.startswith(("/", "../"))
            and ":" not in path, "unsafe manifest path: " + path)
    return path


def encoded(text, spec):
    return (b"\xef\xbb\xbf" if spec.get("bom") else b"") + text.replace("\n", spec["newline"]).encode("utf-8")


def toc_reference(line, game_type):
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    condition = CONDITION.fullmatch(line)
    if not condition:
        require("[" not in line, "invalid TOC condition: " + line)
        return line
    path, kind, values = condition.groups()
    require("[" not in path, "stacked TOC conditions: " + line)
    require(kind in ("AllowLoadTextLocale", "AllowLoadGameType", "ExcludeLoadGameType"),
            "unsupported TOC condition: " + kind)
    # Inventory every text-locale branch, exactly as tools/load-graph.lua does.
    selected = game_type in re.findall(r"\w+", values)
    if kind == "AllowLoadGameType" and game_type is not None and not selected:
        return None
    if kind == "ExcludeLoadGameType" and game_type is not None and selected:
        return None
    return path


def client_matrix(root):
    rows = list(csv.DictReader((root / "tools/classic-client-matrix.tsv").read_text(encoding="utf-8-sig").splitlines(),
                               delimiter="\t"))
    clients = []
    for row in rows:
        suffix = row["Suffix"]
        if row["IsClassic"] == "true":
            clients.append((suffix, suffix, None, True))
        else:
            clients.extend(((suffix, suffix, "standard", False), ("Forever", suffix, "camelot", False)))
    require(len({c[0] for c in clients}) == len(clients), "duplicate client in matrix")
    return clients


def walk(documents, client, addon, tolerate_repeats=False):
    view, suffix, game_type, classic = client
    paths, xmls, active, seen = [], [], set(), set()

    def visit(path):
        clean_path(path)
        require(path not in active, "load cycle: " + path)
        if path.endswith(".lua"):
            require(path not in seen or tolerate_repeats, view + ": duplicate Lua load " + path)
            if path not in seen:
                paths.append(path)
                seen.add(path)
            return
        require(path in documents, "unregistered load manifest: " + path)
        active.add(path)
        directory = posixpath.dirname(path)
        if path.endswith(".xml"):
            xmls.append(path)
            text = re.sub(r"<!--.*?-->", "", documents[path], flags=re.S)
            references = REFERENCE.findall(text)
        else:
            references = [toc_reference(line, game_type) for line in documents[path].splitlines()]
        for reference in references:
            if reference:
                visit(posixpath.normpath(directory + "/" + reference.replace("\\", "/")))
        active.remove(path)

    visit(addon + "/" + addon + "_" + suffix + ".toc")
    return paths, xmls


def expand_loads(manifest, clients):
    """Existing formatting is explicit; new modules inherit their anchor's sites."""
    modules = {module["path"]: module for module in manifest["modules"]}
    require(len(modules) == len(manifest["modules"]), "duplicate module path")
    valid_clients = {client[0] for client in clients}
    loads, pending = {}, set()

    def expand(path):
        if path in loads:
            return loads[path]
        require(path in modules, "unknown placement anchor: " + path)
        require(path not in pending, "placement anchor cycle: " + path)
        pending.add(path)
        module = modules[path]
        clean_path(path)
        flags = module["clients"]
        require(len(flags) == len(set(flags)) and set(flags) <= valid_clients, "invalid client flags: " + path)
        result = []
        for load in module.get("loads", []):
            require(load["document"] in manifest["documents"], "unknown document for " + path)
            result.append(dict(load, path=path))
        if "after" in module:
            require(not result, "use loads or after, not both: " + path)
            for anchor in expand(module["after"]):
                result.append({"document": anchor["document"], "after": module["after"], "path": path})
        loads[path] = result
        pending.remove(path)
        return result

    for path in modules:
        expand(path)
    return modules, loads


def render_documents(manifest, clients):
    modules, loads = expand_loads(manifest, clients)
    specs = manifest["documents"]
    # First walk the captured sites to establish which clients share each XML.
    original = {}
    for document, spec in specs.items():
        rows = list(spec["scaffold"])
        for path, entries in loads.items():
            for entry in entries:
                if entry["document"] == document and "order" in entry:
                    relative = posixpath.relpath(path, posixpath.dirname(document)).replace("/", "\\")
                    rows.append([entry["order"], entry["line"].replace("{file}", relative)])
        original[document] = "".join(line for _, line in sorted(rows))
    site_clients = {path: set() for path in specs}
    for client in clients:
        for addon in ADDONS:
            _, xmls = walk(original, client, addon)
            toc = addon + "/" + addon + "_" + client[1] + ".toc"
            for document in [toc] + xmls:
                site_clients[document].add(client[0])

    result = {}
    for document, spec in specs.items():
        base, children = [], {}
        for path, entries in loads.items():
            for entry in entries:
                if entry["document"] != document:
                    continue
                if "order" in entry:
                    base.append((entry["order"], path, entry))
                    continue
                selected = set(modules[path]["clients"]) & site_clients[document]
                if not selected:
                    continue
                require(document.endswith(".toc") or selected == site_clients[document],
                        path + ": partial client selection in shared XML " + document + "; choose a client-specific TOC anchor")
                children.setdefault(entry["after"], []).append((path, selected))
        rows = [(order, None, {"line": text}) for order, text in spec["scaffold"]] + base
        require(len({row[0] for row in rows}) == len(rows), "duplicate document order: " + document)
        emitted = set()

        def emit(path, entry):
            line = entry["line"]
            if path is None:
                return line
            emitted.add(path)
            relative = posixpath.relpath(path, posixpath.dirname(document)).replace("/", "\\")
            line = line.replace("{file}", relative)
            if children.get(path) and not line.endswith("\n"):
                line += "\n"
            for child, selected in children.get(path, []):
                require(child not in emitted, "duplicate placement: " + child)
                if document.endswith(".toc"):
                    condition = ""
                    if selected == {"Forever"}:
                        condition = " [AllowLoadGameType camelot]"
                    elif selected == {"Mainline"}:
                        condition = " [ExcludeLoadGameType camelot]"
                    template = "{file}" + condition + "\n"
                else:
                    indent = re.match(r"\s*", entry["line"]).group().replace("\n", "")
                    template = indent + '<Script file="{file}"/>\n'
                    if child.endswith(".xml"):
                        template = template.replace("<Script ", "<Include ")
                line += emit(child, {"line": template})
            return line

        result[document] = "".join(emit(path, entry) for _, path, entry in sorted(rows))
        for anchor in children:
            require(anchor in emitted, "placement anchor absent from " + document + ": " + anchor)
    return result, modules


def inventory(root, documents, modules, clients):
    sections, loaded, actual = [], {}, {path: set() for path in modules}
    retail_aura = {CORE + "/Auras3/" + name for name in (
        "MSUF_Auras3_DotData.lua", "MSUF_Auras3_DefensiveData.lua", "MSUF_Auras3_AuraNameResolver.lua",
        "MSUF_Auras3_SpellIndicators.lua", "MSUF_Auras3_UnitFrames.lua")}
    classic_trees = ["/Game/Classic/"] + ["/Game/" + c[0] + "/" for c in clients if c[3]]
    for client in clients:
        view, suffix, game_type, classic = client
        loaded[view] = set()
        for addon in ADDONS:
            paths, xmls = walk(documents, client, addon)
            sections.append((view, addon, paths))
            for path in paths + xmls:
                require(path in modules, "loaded path absent from module source: " + path)
                actual[path].add(view)
                if not classic:
                    require(not any(tree in path for tree in classic_trees)
                            and not re.search(r"_Classic\.(lua|xml)$", path), view + " loads Classic-only " + path)
                else:
                    require(path not in retail_aura, view + " loads Retail aura runtime " + path)
            for path in paths:
                shared_pack = addon == CORE + "_Locales" and path.startswith(LOCALE_DIR + "/")
                require(path not in loaded[view] or shared_pack, view + ": duplicate addon load " + path)
                loaded[view].add(path)
        if not classic:
            # Inventory inactive game-type branches too, matching the existing lock invariant.
            union_client = (view, suffix, None, classic)
            for addon in ADDONS:
                paths, xmls = walk(documents, union_client, addon, tolerate_repeats=True)
                for path in paths + xmls:
                    require(not any(tree in path for tree in classic_trees)
                            and not re.search(r"_Classic\.(lua|xml)$", path), "Mainline branch loads Classic-only " + path)
    for path, module in modules.items():
        require(set(module["clients"]) == actual[path], "client flags disagree with load graph for " + path
                + ": declared " + str(module["clients"]) + ", loaded " + str(sorted(actual[path])))
        if path.endswith(".lua"):
            require((root / path).is_file(), "module source does not exist: " + path)
    disk_lua = {p.relative_to(root).as_posix() for addon in ADDONS for p in (root / addon).rglob("*.lua")}
    require(disk_lua <= modules.keys(), "Lua files missing from module source: " + ", ".join(sorted(disk_lua - modules.keys())))
    return sections, loaded


def render_lock(sections):
    lines = [
        "# tools/load-graph.lock: the ordered Lua files each client loads (TOC order, XML manifests expanded,",
        "# every text locale). Generated by tools/load-graph.lua; never edit it by hand.",
        "# After a TOC or XML manifest change: lua tools/load-graph.lua --write",
        "# Clients: the rows of tools/classic-client-matrix.tsv and Forever (the Mainline TOCs, game type camelot).",
    ]
    for view, addon, paths in sections:
        lines.append("@ %s %s (%d files)" % (view, addon, len(paths)))
        lines.extend(paths)
    return "\n".join(lines) + "\n"


def render_exclusions(modules, loaded, clients):
    lines = ["MainlinePath\tFlavors\tReason"]
    classic = [c[0] for c in clients if c[3]]
    mainline = loaded["Mainline"] | loaded["Forever"]
    for path in sorted(mainline):
        missing = {flavor for flavor in classic if path not in loaded[flavor]}
        if not missing:
            continue
        module = modules[path]
        rows = module.get("exclusions", [])
        if not rows:
            require(module.get("reason"), "excluded module needs a reason in its record: " + path)
            rows = [{"flavors": "*" if missing == set(classic) else ",".join(c for c in classic if c in missing),
                     "reason": module["reason"]}]
        covered = set()
        for row in rows:
            flags = set(classic) if row["flavors"] == "*" else set(row["flavors"].split(","))
            require(flags <= missing and not flags & covered, "stale/duplicate exclusion: " + path)
            require(len(row["reason"]) >= 20, "exclusion reason needs evidence: " + path)
            covered.update(flags)
            lines.append("\t".join((path, row["flavors"], row["reason"])))
        require(covered == missing, "incomplete exclusions: " + path)
    return "\n".join(lines) + "\n"


def lua_tokens(source):
    """Only lexical analysis: strings/comments never become false locale keys."""
    index = 0
    while index < len(source):
        char = source[index]
        if char.isspace():
            index += 1
            continue
        comment = source.startswith("--", index)
        start = index + 2 if comment else index
        bracket = LONG_OPEN.match(source, start)
        if bracket:
            begin = start + len(bracket.group())
            end = source.find("]" + bracket[1] + "]", begin)
            require(end >= 0, "unclosed Lua long string/comment")
            if not comment:
                yield "string", source[begin:end].removeprefix("\n")
            index = end + len(bracket[1]) + 2
        elif comment:
            end = source.find("\n", start)
            index = len(source) if end < 0 else end
        elif char in "\"'":
            quote, value = char, []
            index += 1
            while index < len(source) and source[index] != quote:
                char = source[index]
                index += 1
                if char == "\\":
                    require(index < len(source), "unclosed Lua string escape")
                    number = LUA_NUMBER_ESCAPE.match(source, index)
                    if number:
                        value.append(chr(int(number.group())))
                        index += len(number.group())
                        continue
                    char = source[index]
                    char = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}.get(char, char)
                    index += 1
                value.append(char)
            require(index < len(source), "unclosed Lua quoted string")
            index += 1
            yield "string", "".join(value)
        elif char.isalpha() or char == "_":
            name = LUA_NAME.match(source, index).group()
            index += len(name)
            yield "name", name
        else:
            index += 1
            yield char, char


def locale_entries(source):
    tokens = list(lua_tokens(source))
    entries = {}
    for i in range(len(tokens) - 4):
        if tokens[i][0] == "[" and tokens[i + 1][0] == "string" and tokens[i + 2][0] == "]" \
                and tokens[i + 3][0] == "=" and tokens[i + 4][0] == "string":
            entries[tokens[i + 1][1]] = tokens[i + 4][1]
    return entries


def render_locale_report(root):
    packs = {p.stem: locale_entries(p.read_text(encoding="utf-8-sig"))
             for p in sorted((root / LOCALE_DIR).glob("????.lua"))}
    require("enUS" in packs, "English locale source is missing")
    english = packs.pop("enUS")
    report = {"source": LOCALE_DIR + "/enUS.lua", "runtime_fallback": "key itself (existing localization metatable)",
              "note": "Generated translation work; stubs are suggestions, never loaded or counted as translations.", "locales": {}}
    for locale, entries in packs.items():
        missing = [{"key": key, "stub": "L[" + json.dumps(key, ensure_ascii=False) + "] = "
                    + json.dumps(value, ensure_ascii=False)} for key, value in sorted(english.items()) if key not in entries]
        report["locales"][locale] = missing
    return json.dumps(report, ensure_ascii=False, indent=2) + "\n"


def generate(root, manifest):
    require(manifest["version"] == 1, "unsupported module manifest version")
    clients = client_matrix(root)
    documents, modules = render_documents(manifest, clients)
    for module in modules.values():
        require(set(module.get("reviews", {})) <= REVIEW_LISTS, "unknown review list in " + module["path"])
    sections, loaded = inventory(root, documents, modules, clients)
    outputs = {path: encoded(text, manifest["documents"][path]) for path, text in documents.items()}
    lists = {LOCK: render_lock(sections), EXCLUSIONS: render_exclusions(modules, loaded, clients)}
    retained = ["Path\tKind\tReason"]
    for path, module in sorted(modules.items()):
        if path.endswith(".lua") and not module["clients"]:
            row = module.get("retained")
            require(row, "unloaded module needs retained evidence: " + path)
            retained.append("\t".join((path, row["kind"], row["reason"])))
    lists[UNLOADED] = "\n".join(retained) + "\n"
    for path, spec in manifest["reviewed_lists"].items():
        require(path in REVIEW_LISTS, "unknown review list: " + path)
        text = spec["text"]
        additions = [row for module in modules.values() for row in module.get("reviews", {}).get(path, [])]
        if additions:
            text = text.rstrip("\n") + "\n" + "\n".join(additions) + "\n"
        outputs[path] = encoded(text, spec)
    for path, text in lists.items():
        outputs[path] = encoded(text, manifest["formats"][path])
    outputs[LOCALE_REPORT] = render_locale_report(root).replace("\n", "\r\n").encode("utf-8")
    return outputs


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8-sig"))
        outputs = generate(root, manifest)
        stale = []
        for path, expected in outputs.items():
            target = root / clean_path(path)
            if not target.is_file() or target.read_bytes() != expected:
                stale.append(path)
        if args.check:
            for path in stale:
                print("STALE " + path)
            if stale:
                print("Run python tools/generate_module_manifest.py --write")
                return 1
        else:
            for path in stale:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(outputs[path])
        toc_count = sum(path.endswith(".toc") for path in outputs)
        toc_hash = hashlib.sha256(b"".join(outputs[p] for p in sorted(outputs) if p.endswith(".toc"))).hexdigest()
        print("module manifest: %d outputs, %d TOCs, %d %s; TOC SHA256 %s" % (
            len(outputs), toc_count, len(stale), "stale" if args.check else "updated", toc_hash))
        return 0
    except (ValueError, KeyError, OSError) as error:
        print("module manifest: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
