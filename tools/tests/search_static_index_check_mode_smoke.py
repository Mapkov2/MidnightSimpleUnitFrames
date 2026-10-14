"""Exercise the real generator's check/write boundary with a bounded row provider."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    if not lua:
        raise SystemExit("Search check-mode smoke requires Lua 5.1")
    generator = Path(sys.argv[2]) if len(sys.argv) > 2 else root / ".github/scripts/search_static_index_project.lua"
    source = generator.read_text(encoding="utf-8")
    seam = "local rows = {}\nif ROWS_ONLY then"
    if source.count(seam) != 1:
        raise SystemExit("Search generator row-provider boundary moved")
    # The nightly integration smoke builds every real page. This probe replaces
    # only that costly provider, retaining the real renderer, parser and file IO.
    source = source.replace(seam, "BuildFlavorInChild = function() return {} end\n" + seam)
    environment = os.environ.copy()
    environment["MSUF_SEARCH_SOURCE_SHA256"] = "A" * 64
    with tempfile.TemporaryDirectory(prefix="search-check-") as scratch:
        working = Path(scratch)
        script = working / "generator.lua"
        script.write_text(source, encoding="utf-8")
        matrix = working / "tools/classic-client-matrix.tsv"
        matrix.parent.mkdir()
        shutil.copyfile(root / "tools/classic-client-matrix.tsv", matrix)
        output = working / "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
        output.parent.mkdir(parents=True)

        def run(*arguments):
            return subprocess.run([lua, str(script), *arguments], cwd=working, env=environment, capture_output=True)

        generated = run("--stdout")
        if generated.returncode != 0:
            raise SystemExit(generated.stderr.decode(errors="replace"))
        expected = generated.stdout.replace(b"\r\n", b"\n")
        for content in (expected, expected.replace(b"\n", b"\r\n")):
            output.write_bytes(content)
            result = run("--check")
            if result.returncode != 0 or output.read_bytes() != content:
                raise SystemExit("Check mode rejected or changed an unchanged catalog")
        stale = expected + b"-- stale row\n"
        output.write_bytes(stale)
        result = run("--check")
        if result.returncode == 0 or output.read_bytes() != stale:
            raise SystemExit("Check mode accepted or overwrote a stale catalog")
        output.unlink()
        if run("--check").returncode == 0 or output.exists():
            raise SystemExit("Check mode accepted or created a missing catalog")
        output.write_bytes(expected)
        if run("--check", "--stdout").returncode == 0 or output.read_bytes() != expected:
            raise SystemExit("Conflicting output modes were accepted or changed the catalog")
        script.write_text(source.replace("return {} end\n" + seam, 'error("row provider failed") end\n' + seam), encoding="utf-8")
        if run("--check").returncode == 0 or output.read_bytes() != expected:
            raise SystemExit("Check mode swallowed a row-provider error or changed the catalog")
    print("PASS search check mode: unchanged LF/CRLF, stale, missing, conflicting modes and provider failure")


if __name__ == "__main__":
    main()
