"""Capture must isolate Python startup and sanitize the actual Lua child environment."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import PARENT, clean_env, materialize, interpreters
from menu_section_capture import PRODUCT, source_support


def main():
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert lua, "Lua 5.1 required"
    runtime_before = interpreters(lua)
    with tempfile.TemporaryDirectory(prefix="section-startup-") as directory:
        folder = Path(directory)
        marker = folder / "python-startup-executed"
        (folder / "sitecustomize.py").write_text("from pathlib import Path\nPath(" + repr(str(marker)) + ").write_text('startup')\n")
        env = dict(os.environ, LUA_INIT="error('section startup contamination executed')", LUA_PATH="untrusted/?.lua",
                   LUA_CPATH="untrusted/?.dll", PYTHONPATH=str(folder), PYTHONHOME=str(folder), PYTHONSTARTUP=str(folder / "sitecustomize.py"))
        raw = subprocess.run([str(lua), "-e", "io.write(_VERSION)"], env=env, capture_output=True, text=True)
        assert raw.returncode != 0 and "startup contamination executed" in raw.stderr, "Lua startup red counterexample did not execute"
        print("RED unsanitized Lua startup native" + str(raw.returncode))
        denied = subprocess.run([sys.executable, "-I", str(root / "tools/tests/menu_section_capture.py"), "--help"],
                                env=clean_env(), capture_output=True, text=True)
        assert denied.returncode != 0 and "python -I -S" in denied.stderr, "nonisolated capture accepted"
        print("REJECT Python without -S native" + str(denied.returncode))
        support, _ = source_support(root, PARENT)
        source = folder / "source"
        materialize(root, PARENT, source, PRODUCT + support)
        output = folder / "capture"
        run = subprocess.run([sys.executable, "-I", "-S", str(root / "tools/tests/menu_section_capture.py"),
            "--source", str(source), "--base", PARENT, "--harness", str(root), "--lua", str(lua),
            "--output", str(output), "--client", "Mainline", "--area", "pvp_trinket"], env=env, cwd=root, capture_output=True, text=True)
        assert run.returncode == 0, run.stdout + run.stderr
        assert not marker.exists(), "Python startup contamination executed during isolated capture"
        metadata = json.loads((output / "provenance.json").read_text())
        removed = metadata["interpreters"]["removed_startup_variables"]
        assert all(name in removed for name in ("LUA_INIT", "LUA_PATH", "LUA_CPATH", "PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP")), "capture did not record startup sanitization"
        assert metadata["interpreters"]["python"]["isolated"], "actual capture interpreter was not isolated"
        for language in ("python", "lua"):
            assert metadata["interpreters"][language] == runtime_before[language], "actual capture interpreter identity differs"
        for prefix in ("", "semantics/", "gaps/"):
            name = prefix + "pvp_trinket-Mainline.tsv"
            expected = root / "tools/fixtures/menu-section-parent" / name
            assert (output / name).read_bytes().replace(b"\r\n", b"\n") == expected.read_bytes().replace(b"\r\n", b"\n"), "contaminated environment changed authentic capture: " + name
        print("GREEN actual contaminated-environment capture native0; three authentic receipts unchanged")
    assert interpreters(lua) == runtime_before, "current startup replay interpreter identity changed"
    print("menu_section_capture_environment_smoke: startup red, strict Python isolation and sanitized actual Lua replay OK")


if __name__ == "__main__":
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit(subprocess.call(
            [sys.executable, "-I", "-S", str(Path(__file__).resolve()), *sys.argv[1:]], env=clean_env()))
    main()
