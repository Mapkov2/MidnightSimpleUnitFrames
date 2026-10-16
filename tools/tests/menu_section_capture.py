"""Replay original section builders from one of two declared committed sources."""
import sys
if __name__ == "__main__" and (not sys.flags.isolated or not sys.flags.no_site):
    raise SystemExit("section capture requires an isolated interpreter: python -I -S menu_section_capture.py")

import argparse
import hashlib
import io
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tarfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import PARENT, archive, clean_env, git, interpreters

BASE = "3feb8c771f6d2f32d3fd8a475a0134faf40beb4f"
ORIGINAL = "32ee2629aa5216687992130b904d6def80a357b3"
PRODUCT = ["MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options", "MidnightSimpleUnitFrames_Locales"]
CLIENTS = ["Mainline", "Forever", "Vanilla", "TBC", "Mists"]
AREAS = ["pvp_trinket", "dispel_overlay", "dispel_symbol", "unit_visibility", "boss_arena_layout", "boss_target_highlight"]
SUPPORT = ["tools/tests/menu_core_world.lua", "tools/tests/client_world.lua", "tools/tests/client_manifest.lua", "tools/classic-client-matrix.tsv",
           ".github/scripts/msuf_test_stubs.lua", "tools/client-boot-globals.tsv", "tools/tests/runtime_media_fixture.lua"]


def sha(data):
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def manifest_sha(values):
    return sha(json.dumps(values, sort_keys=True, separators=(",", ":")).encode())


def digest(data):
    a, b = 5381, 52711
    for byte in data.replace(b"\r\n", b"\n"):
        a, b = (a * 33 + byte) % 4294967296, (b * 31 + byte) % 4294967296
    return f"{a:08x}{b:08x}"


def dependencies(content):
    # The two frozen source graphs use literal root paths; dynamic TOC/XML paths
    # are covered by the complete product inventories. Comments are not reads.
    source = re.sub(r"--[^\n]*", "", content.decode("utf-8-sig"))
    pattern = r'''\b(?:root|repo)(?::gsub\([^)]*\))?\s*\.\.\s*["'](/[^"']+)["']'''
    return sorted({path.lstrip("/") for path in re.findall(pattern, source)
                   if re.search(r"\.(?:lua|tsv)$", path)})


def closure(read, entries):
    pending, seen, edges = list(entries), set(), {}
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        children = dependencies(read(path)) if path.endswith(".lua") else []
        edges[path] = children
        pending.extend(children)
    return sorted(seen), edges


def source_support(root, base):
    return closure(lambda path: git(root, "show", base + ":" + path), ["tools/tests/menu_core_world.lua"])


def validate_source(root, base):
    assert base in (BASE, ORIGINAL, PARENT), "capture requires a declared genuine pre-schema revision"
    assert git(root, "rev-parse", "HEAD").decode().strip() == base, "capture HEAD differs from declared pre-schema base"
    support, _ = source_support(root, base)
    assert set(SUPPORT) <= set(support), "historical loader/read dependency closure incomplete"
    assert not git(root, "status", "--porcelain", "--untracked-files=all", "--", *PRODUCT, *support), "capture product/support inputs dirty"
    hashes = {}
    for name, committed in archive(root, base, PRODUCT + support).items():
        actual = (root / name).read_bytes()
        assert sha(actual) == sha(committed), "capture source bytes differ: " + name
        hashes[name] = sha(committed)
    assert all(any(p.startswith(prefix + "/") for p in hashes) for prefix in PRODUCT), "incomplete product inventory"
    return hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--check-source", action="store_true")
    parser.add_argument("--harness", type=Path)
    parser.add_argument("--lua", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--client", action="append", choices=CLIENTS)
    parser.add_argument("--area", action="append", choices=AREAS)
    args = parser.parse_args()
    source = args.source.resolve()
    hashes = validate_source(source, args.base)
    if args.check_source:
        print("AUTHENTIC_PRE_SCHEMA:" + args.base)
        return
    assert args.harness and args.lua and args.output, "harness, lua and output required"
    harness, output = args.harness.resolve(), args.output.resolve()
    identity = interpreters(args.lua)
    clients, areas = args.client or CLIENTS, args.area or AREAS
    output.mkdir(parents=True, exist_ok=False)
    (output / "semantics").mkdir()
    (output / "layouts").mkdir()
    (output / "gaps").mkdir()
    entries = ["tools/tests/menu_" + area + "_inventory_smoke.lua" for area in AREAS]
    entries += ["tools/tests/menu_section_capture.py", "tools/tests/menu_section_auth.py"]
    paths, harness_edges = closure(lambda path: (harness / path).read_bytes(), entries)
    harness_hashes = {p: sha((harness / p).read_bytes()) for p in paths}
    support, source_edges = source_support(source, args.base)
    env = clean_env({"MSUF_SECTION_SOURCE_ROOT": str(source), "MSUF_SECTION_CAPTURE_OUTPUT": str(output),
                     "MSUF_SECTION_CAPTURE_BASE": args.base, "MSUF_SECTION_CAPTURE_PYTHON": sys.executable})
    with (output / "capture.log").open("x", encoding="utf-8") as log:
        for flavor in clients:
            for area in areas:
                run = subprocess.run([str(args.lua), str(harness / f"tools/tests/menu_{area}_inventory_smoke.lua"),
                                      str(harness), flavor, "--capture"], env=env, cwd=harness, capture_output=True, text=True)
                log.write(run.stdout + run.stderr)
                log.flush()
                print(run.stdout + run.stderr, end="", flush=True)
                assert run.returncode == 0, f"original builder replay failed: {area}/{flavor}"
    assert validate_source(source, args.base) == hashes, "source changed during replay"
    final_paths, final_edges = closure(lambda path: (harness / path).read_bytes(), entries)
    assert final_paths == paths and final_edges == harness_edges, "executed harness dependency closure changed during replay"
    assert {p: sha((harness / p).read_bytes()) for p in paths} == harness_hashes, "capture harness changed during replay"
    fixtures = {p.relative_to(output).as_posix(): sha(p.read_bytes()) for p in sorted(output.rglob("*.tsv"))
                if p.parent.name != "layouts"}
    metadata = {"schema": 1, "base": args.base, "hash_newlines": "LF", "clients": clients, "areas": areas, "interpreters": identity,
                "source_sha256": hashes, "source_manifest_sha256": manifest_sha(hashes), "harness_sha256": harness_hashes,
                "input_roots": {"source_sha256": "historical_committed_root", "harness_sha256": "observer_root"},
                "original_loader": {"root": "source", "path": "tools/tests/menu_core_world.lua"},
                "source_support_inputs": support, "source_support_edges": source_edges,
                "harness_inputs": paths, "harness_edges": harness_edges,
                "fixture_sha256": fixtures, "fixture_manifest_sha256": manifest_sha(fixtures),
                "command": "menu_section_capture.py --source ORIGINAL_COMMITTED_ROOT --base " + args.base +
                " --harness TEST_ROOT --lua LUA51 --output NEW_DIRECTORY"}
    (output / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    lines = ["-- Captured only by replaying the declared committed original builders.", "return {",
             f'    base = "{args.base}",', f'    sourceManifest = "{manifest_sha(hashes)}",',
             f'    fixtureManifest = "{manifest_sha(fixtures)}",', "    receipts = {"]
    for path in sorted(fixtures):
        lines.append(f'        ["{path}"] = "{digest((output / path).read_bytes())}",')
    lines += ["    },", "}"]
    (output / "provenance.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
