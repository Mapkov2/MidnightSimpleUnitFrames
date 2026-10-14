"""Regenerate both client-family catalogs without changing the shipped files."""
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys


def main():
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    if not lua:
        raise SystemExit("Search generator check requires Lua 5.1 (MSUF_LUA or PATH)")
    version = subprocess.run([lua, "-e", "io.write(_VERSION)"], capture_output=True, text=True, check=True)
    if version.stdout != "Lua 5.1":
        raise SystemExit("Search generator check requires Lua 5.1, got " + version.stdout)

    # Use the existing source-hash contract's exact exclusions and newline rules.
    hashes = runpy.run_path(str(root / ".github/scripts/menu2_search_index_hash_smoke.py"))
    mainline = hashes["MAINLINE_INDEX"]
    classic = hashes["CLASSIC_INDEX"]
    for flavor, excluded in (
        ("Vanilla", {mainline.lower(), classic.lower()}),
        ("Mainline", {mainline.lower()}),
    ):
        environment = os.environ.copy()
        environment["MSUF_SEARCH_SOURCE_SHA256"] = hashes["source_sha256"](excluded)[0]
        subprocess.run(
            [lua, ".github/scripts/search_static_index_project.lua", "--flavor", flavor, "--check"],
            cwd=root, env=environment, check=True,
        )
    print("PASS generated search indexes: both family catalogs reproduce their shipped rows")


if __name__ == "__main__":
    main()
