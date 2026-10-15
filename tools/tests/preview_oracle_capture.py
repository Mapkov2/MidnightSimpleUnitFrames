"""Capture candidates from an explicit, unchanged addon revision into a NEW directory."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--lua", type=Path, required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if head != args.base:
        parser.error(f"actual HEAD {head} differs from requested baseline {args.base}")
    product = ["MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options", "MidnightSimpleUnitFrames_Locales"]
    dirty = subprocess.check_output(["git", "diff", "HEAD", "--", *product], cwd=root)
    if dirty:
        parser.error("capture requires byte-unchanged addon source at the stated revision")
    if output.exists():
        parser.error("output must not exist; capture never overwrites a frozen or candidate corpus")
    output.mkdir(parents=True)
    files = subprocess.check_output(["git", "ls-files", "--", *product], cwd=root, text=True).splitlines()
    harness = ["tools/tests/menu_core_world.lua", "tools/tests/client_world.lua", ".github/scripts/msuf_test_stubs.lua",
               "tools/tests/preview_oracle_regions.lua", "tools/tests/preview_oracle_cases.lua",
               "tools/tests/preview_oracle_world.lua", "tools/tests/preview_render_oracle_smoke.lua"]
    hashes = {p: hashlib.sha256((root / p).read_bytes().replace(b"\r\n", b"\n")).hexdigest() for p in sorted(files + harness)}
    flavors = ["Mainline", "Forever", "Vanilla", "TBC", "Mists"]
    command = 'python tools/tests/preview_oracle_capture.py --root "$ROOT" --lua "$LUA51" --base ' + head
    command += ' --output "$NEW_CANDIDATE_DIRECTORY"'
    metadata = {"schema": 1, "base": head, "clients": flavors, "locale": "enUS", "time": 100, "hash_newlines": "LF",
                "random_seed": 1701, "command": command, "source_sha256": hashes}
    (output / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    with (output / "capture.log").open("w", encoding="utf-8") as log:
        for flavor in flavors:
            destination = output / flavor
            destination.mkdir()
            run = subprocess.run([str(args.lua), "tools/tests/preview_render_oracle_smoke.lua", str(root), flavor,
                                  "--capture", str(destination)], cwd=root, capture_output=True, text=True)
            log.write(run.stdout + run.stderr)
            log.flush()
            print(run.stdout + run.stderr, end="", flush=True)
            if run.returncode:
                raise SystemExit(run.returncode)
    fixture_hashes = {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
                      for p in sorted(output.glob("*/*.lua"))}
    (output / "fixture-sha256.json").write_text(json.dumps(fixture_hashes, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
