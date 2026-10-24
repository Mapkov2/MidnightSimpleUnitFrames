"""Generate live Menu2 schema coverage (run inside the shared Lua slot).

  python tools/menu_schema_coverage.py --write --lua <lua51>
  python tools/menu_schema_coverage.py --check

Generation runs the existing search commands, Classic first, with a tool-only
capture hook. Thus search and coverage use the same actual page builds and finite
workspace states. Capture includes widgetless controls and declarations omitted
from search. It does not execute setters or prove in-game rendering.
"""
import argparse
import csv
import hashlib
from functools import lru_cache
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
INDEXES = ("Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua",
           "Search/MSUF_Menu2_Search_StaticIndex_Data.lua")
SETTING_KINDS = {"toggle", "checkbox", "slider", "dropdown", "segment", "color", "textinput", "editbox", "input"}


def read(path):
    return path.read_bytes().decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def menu_hash(root, classic):
    digest = hashlib.sha256()
    excluded = set(INDEXES if classic else INDEXES[1:])
    menu = root / MENU
    for path in sorted(menu.rglob("*"), key=lambda item: item.relative_to(menu).as_posix()):
        if path.suffix.lower() in {".lua", ".xml"}:
            rel = path.relative_to(menu).as_posix()
            if rel not in excluded:
                digest.update(rel.encode() + b"\0" + read(path).encode() + b"\0")
    return digest.hexdigest().upper()


def lua_references(text):
    # Find the literal suffix first instead of retrying an unbounded identifier
    # expression at every byte of large generated spell catalogs.
    names = []
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"
    for match in re.finditer(r"\.lua\b", text):
        start = match.start()
        while start and text[start - 1] in alphabet:
            start -= 1
        first = re.compile(r"\b[A-Za-z0-9_]").search(text, start, match.start())
        if first:
            names.append(text[first.start():match.end()])
    return names


def source_hash(root, include_indexes=True):
    paths = set()
    for directory in ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options", ".github"):
        paths.update(p for p in (root / directory).rglob("*") if p.suffix.lower() in {".lua", ".xml", ".toc"})
    paths.update(root / name for name in (
        "tools/menu_schema_coverage.py", "tools/menu_schema_project.lua", "tools/menu_schema_harness.lua",
        "tools/menu_schema_capture.lua", "tools/search_catalog_harness.lua",
        "tools/classic-client-matrix.tsv", "tools/load-graph.lock"))
    # Follow the generation harness' actual Lua helper references. Deleting an
    # unrelated frozen smoke cannot stale a declaration projection.
    helpers = {p.name: p for p in (root / 'tools').rglob('*.lua')}
    pending = list(paths)
    seen = set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        text = read(path)
        names = lua_references(text)
        names += [name + '.lua' for name in re.findall(r'require\(["\']([\w_]+)["\']\)', text)]
        for name in names:
            helper = helpers.get(name)
            if helper and helper not in paths:
                paths.add(helper)
                pending.append(helper)
    digest = hashlib.sha256()
    for path in sorted(paths):
        if not include_indexes and path.as_posix().endswith(tuple(INDEXES)):
            continue
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + read(path).encode() + b"\0")
    return digest.hexdigest().upper()


def index_data(root, name, current=True):
    text = read(root / MENU / name)
    blob = re.search(r"StaticIndexBlob = \[==\[\n(.*?)\]==\]", text, re.S)
    count = re.search(r"StaticIndexRecordCount = (\d+)", text)
    stamp = re.search(r'StaticIndexSourceSha256 = "([A-F0-9]{64})"', text)
    if not blob or not count or not stamp:
        raise ValueError("malformed search inventory: " + name)
    rows = [line.split("\t") for line in blob[1].splitlines()]
    if len(rows) != int(count[1]) or any(len(row) != 12 for row in rows):
        raise ValueError("incomplete search inventory: " + name)
    if current and stamp[1] != menu_hash(root, name == INDEXES[0]):
        raise ValueError("stale search inventory: " + name)
    return {"sourceSha256": stamp[1], "blobSha256": hashlib.sha256(blob[1].encode()).hexdigest(),
            "rowCount": len(rows), "identities": sorted(row[7] for row in rows)}, rows


@lru_cache(maxsize=32768)
def physical_path(value):
    normalized = value.replace("%.", ".").replace("%_", "_").lstrip("^")
    return not re.match(r"(?:barScope|fontScope|menu|uf_[a-z]+)\.|profiles\.specAutoSwitch|auras3\.(?:player|target|focus|pet|boss|arena)(?:\.|[0-9])", normalized)


def valid_setting(value):
    if isinstance(value, str):
        return bool(value.strip()) and not any(char in value for char in "{}") and physical_path(value)
    if not isinstance(value, dict):
        return False
    keys, patterns = value.get("keys") or [], value.get("patterns") or []
    if not isinstance(keys, list) or not isinstance(patterns, list) or not (keys or patterns):
        return False
    return (all(isinstance(key, str) and key.strip() and "{" not in key and physical_path(key) for key in keys)
            and all(isinstance(pattern, str) and pattern.startswith("^") and pattern.endswith("$") and physical_path(pattern) for pattern in patterns))


def profile_control(row):
    return bool(row.get("setting")) or row.get("classification") == "setting" and not row.get("ephemeralReason")


def declared(row):
    schema_id = row.get("schemaId")
    identity = row.get("controlId", "")
    return (schema_id and (schema_id == identity or identity == "schema:" + row.get("pageKey", "") + ":" + schema_id)
            and row.get("scope") and row.get("applyDomain")
            and ({"editbox": "textinput", "input": "textinput", "checkbox": "toggle"}.get(row.get("kind"), row.get("kind"))
                 == row.get("schemaKind")))


def audit(evidence, root):
    physical_path.cache_clear()
    issues, total, proven = [], 0, 0
    if evidence.get("version") != 2 or evidence.get("sourceSha256") != source_hash(root):
        issues.append("missing/stale live schema projection")
    clients = evidence.get("clients", {})
    required = {row["Suffix"] for row in csv.DictReader(read(root / "tools/classic-client-matrix.tsv").splitlines(), delimiter="\t")}
    required.add("Forever")
    if set(clients) != required:
        issues.append("client projection inventory differs")
    for flavor, client in clients.items():
        rows = client.get("controls", [])
        initial = client.get('initialControlIds', [])
        if not initial or len(set(initial)) != len(initial) or not set(initial) <= {row['controlId'] for row in rows}:
            issues.append('incomplete initial declaration inventory: ' + flavor)
        initial_rows = client.get('initialControls', [])
        if len(initial_rows) != len(initial) or {row['controlId'] for row in initial_rows} != set(initial):
            issues.append('missing actual-core declaration evidence: ' + flavor)
        if not rows or len({row["controlId"] for row in rows}) != len(rows) or client.get("allDeclarationsCaptured") is not True:
            issues.append("incomplete declaration inventory: " + flavor)
        for index, row in enumerate(rows + initial_rows):
            counted = index < len(rows)
            for problem in row.get("observationIssues", {}):
                issues.append(flavor + ":" + row["controlId"] + ":" + problem)
            if profile_control(row):
                total += counted
                variants = row.get("settingDeclarations", {})
                if declared(row) and valid_setting(row.get("setting")) and variants and all(valid_setting(v) for v in variants.values()):
                    proven += counted
                else:
                    issues.append("unproven profile control: " + flavor + ":" + row["controlId"])
            elif (row.get("kind") in SETTING_KINDS or row.get("classification") == "action"
                  or row.get("controlId", "").startswith("schema:") and row.get("kind") == "button"):
                if not declared(row) or not row.get("ephemeralReason"):
                    issues.append("unexplained non-profile control: " + flavor + ":" + row["controlId"])
    indexes = evidence.get("indexes", {})
    for name in INDEXES:
        current, search_rows = index_data(root, name)
        if indexes.get(name) != current:
            issues.append("search crosswalk differs: " + name)
        family = {row["Suffix"] for row in csv.DictReader(read(root / "tools/classic-client-matrix.tsv").splitlines(), delimiter="\t")
                  if (row["IsClassic"] == "true") == (name == INDEXES[0])}
        if name == INDEXES[1]:
            family.add("Forever")
        built = {row["controlId"] for flavor, client in clients.items() if flavor in family for row in client.get("controls", [])}
        for row in search_rows:
            if row[2] not in SETTING_KINDS:
                continue
            parts = row[7].split("\x1f")
            if len(parts) != 3 or parts[0] != "id" or unquote(parts[2]) not in built:
                issues.append("indexed setting absent from live declarations: " + name + ":" + row[7])
    return proven, total, issues


def load_stream(path):
    """Fold page observations in order, preserving the former exact row union."""
    rows = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            previous = rows.setdefault(row["controlId"], {})
            if row.pop("_schemaAssigned", False):
                for key in ("schemaId", "schemaKind", "scope", "applyDomain", "schemaSettingPath", "ephemeralReason"):
                    previous.pop(key, None)
            for key, value in row.items():
                if key in {"observationIssues", "resolvedPaths", "settingDeclarations"}:
                    previous.setdefault(key, {}).update(value)
                elif key in {"controlId", "pageKey", "kind", "label", "classification", "settingKey", "controlPath", "actionKey"}:
                    previous.setdefault(key, value)
                else:
                    previous[key] = value
    return rows


def generate(root, lua):
    before = source_hash(root, include_indexes=False)
    matrix = list(csv.DictReader(read(root / "tools/classic-client-matrix.tsv").splitlines(), delimiter="\t"))
    baseline = {name: index_data(root, name)[0] for name in INDEXES}
    evidence = {"version": 2, "clients": {}, "indexes": {}}
    with tempfile.TemporaryDirectory(prefix="menu-schema-") as directory:
        env = dict(os.environ, LUA_INIT="@tools/menu_schema_harness.lua", MSUF_SCHEMA_CAPTURE_DIR=directory)
        env.pop("MSUF_SCHEMA_CATALOG_SOURCE", None)
        for classic, name in zip((True, False), INDEXES):
            env["MSUF_SEARCH_SOURCE_SHA256"] = menu_hash(root, classic)
            command = [lua, ".github/scripts/search_static_index_project.lua"]
            if classic:
                command.extend(("--flavor", "Vanilla"))
            command.append("--check")
            print(" ".join(command), flush=True)
            subprocess.run(command, cwd=root, env=env, check=True)
            current, _ = index_data(root, name)
            lost = sorted(set(baseline[name]["identities"]) - set(current["identities"]))
            evidence["indexes"][name] = current
            print("%s: %d -> %d rows; %d lost" % (name, baseline[name]["rowCount"], current["rowCount"], len(lost)), flush=True)
            if lost:
                raise ValueError("search rows lost: " + repr(lost))
        for flavor in [row["Suffix"] for row in matrix] + ["Forever"]:
            controls = list(load_stream(Path(directory) / (flavor + ".ndjson")).values())
            initial_env = dict(os.environ)
            initial_env.pop('LUA_INIT', None)
            initial_env['MSUF_SCHEMA_INITIAL_CAPTURE_DIR'] = directory
            initial = subprocess.run([lua, 'tools/menu_schema_project.lua', '--release-menu', str(root), flavor],
                                     cwd=root, env=initial_env, capture_output=True, text=True)
            if initial.returncode:
                raise ValueError(flavor + ': initial schema projection failed: ' + initial.stderr)
            initial_controls = load_stream(Path(directory) / (flavor + "-initial.ndjson"))
            known = {row['controlId'] for row in controls}
            controls.extend(row for key, row in initial_controls.items() if key not in known)
            controls.sort(key=lambda row: row["controlId"])
            evidence["clients"][flavor] = {"allDeclarationsCaptured": True, "controls": controls}
            # Keep the all-workspace inventory and the default-page inventory
            # distinct. release_menu builds the latter in the real core world.
            evidence["clients"][flavor]["initialControlIds"] = sorted(initial_controls)
            evidence["clients"][flavor]["initialControls"] = [initial_controls[key] for key in sorted(initial_controls)]
            print(flavor + ": " + str(len(controls)) + " live declarations", flush=True)
    if before != source_hash(root, include_indexes=False):
        raise ValueError("sources changed during page builds; regenerate the projection")
    evidence["sourceSha256"] = source_hash(root)
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default="lua")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--ensure", action="store_true", help="verify current projection, regenerate when missing or stale")
    args = parser.parse_args()
    path = ROOT / "tools/menu_schema_coverage.json"
    evidence = json.loads(read(path)) if path.exists() and not args.write else {}
    regenerate = args.write
    if args.ensure:
        try:
            regenerate = bool(audit(evidence, ROOT)[2])
        except (ValueError, KeyError, OSError):
            regenerate = True
    if regenerate:
        evidence = generate(ROOT, args.lua)
    proven, total, issues = audit(evidence, ROOT)
    if regenerate:
        path.write_bytes((json.dumps(evidence, ensure_ascii=False, indent=2) + "\n").replace("\n", "\r\n").encode())
        counts = {flavor: len(client["initialControlIds"]) for flavor, client in evidence["clients"].items()}
        print("initial declaration counts: " + json.dumps(counts, sort_keys=True))
    for issue in issues:
        print(issue)
    print("menu schema: %d/%d proven; %d issues" % (proven, total, len(issues)))
    print('projection sourceSha256: ' + str(evidence.get('sourceSha256', 'missing')))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
