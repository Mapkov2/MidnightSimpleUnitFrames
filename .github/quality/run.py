"""Portable MSUF contracts: Python 3 and Lua 5.1, no local toolbelt required."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default=os.environ.get("MSUF_LUA51") or shutil.which("lua5.1") or shutil.which("lua51") or shutil.which("lua"))
    args = parser.parse_args()
    if not args.lua:
        parser.error("Lua 5.1 is required; pass --lua PATH or set MSUF_LUA51")
    version = subprocess.run([args.lua, "-v"], capture_output=True, text=True, check=True)
    if "Lua 5.1" not in version.stdout + version.stderr:
        parser.error("Use Lua 5.1 to enforce WoW's compiler limits")
    environment = dict(os.environ)
    environment.pop("MSUF_AURAS3_TEST_SOURCE_ROOT", None)
    # Compile current sources, including new untracked files and the Options addon.
    files = sorted(p.relative_to(ROOT).as_posix() for addon in ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options") for p in (ROOT / addon).rglob("*.lua"))
    with tempfile.TemporaryDirectory(prefix="msuf-quality-") as temp:
        compile_script = Path(temp) / "compile.lua"
        # Relative repository paths contain no Lua delimiters in this checkout.
        if any("]]" in p for p in files):
            raise ValueError("Unsupported path delimiter")
        compile_script.write_text("\n".join("assert(loadfile([[" + p + "]]))" for p in files), encoding="utf-8")
        subprocess.run([args.lua, str(compile_script)], cwd=ROOT, env=environment, check=True)
    print(f"PASS Lua 5.1 compiler: {len(files)} Core/Options files", flush=True)
    subprocess.run([os.sys.executable, str(HERE / "export_contracts.py")], cwd=ROOT, check=True)
    subprocess.run([os.sys.executable, str(HERE / "error_paths.py")], cwd=ROOT, check=True)
    tests = sorted(HERE.glob("*_smoke.lua"))
    for test in tests:
        subprocess.run([args.lua, ".github/scripts/auras3_test_driver.lua", test.relative_to(ROOT).as_posix()], cwd=ROOT, env=environment, check=True)
    integrations = sorted(HERE.glob("*_integration.lua"))
    for test in integrations:
        subprocess.run([args.lua, test.relative_to(ROOT).as_posix()], cwd=ROOT, env=environment, check=True)
    print(f"PASS portable quality contracts: {len(tests)} behavior tests + {len(integrations)} native-load integration tests", flush=True)


if __name__ == "__main__":
    main()
