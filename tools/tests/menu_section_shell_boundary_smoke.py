"""Actual shell authentication must execute the pinned checker across host boundaries."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import PARENT, clean_env, interpreters, materialize
from menu_section_capture import AREAS, BASE, PRODUCT, closure, source_support, validate_source, sha
from menu_section_provenance_smoke import historical_observer
from menu_section_test_runtime import bash_path, lua_literal, proof_sources


def literal(value):
    return lua_literal(str(value).replace("\\", "/"))


def case(root, folder, lua, bash, observer, source, base, name, posix, adapter):
    output = folder / name
    output.mkdir()
    for child in ("semantics", "layouts", "gaps"):
        (output / child).mkdir()
    command_file, exit_file = output / "command.txt", output / "shell-exit.txt"
    shell_file = output / "authenticate.sh"
    if os.name == "nt":
        shell_command = '""' + str(bash).replace("\\", "/") + '" --noprofile --norc "' + str(shell_file).replace("\\", "/") + '""'
    else:
        import shlex
        shell_command = shlex.join([str(bash), "--noprofile", "--norc", str(shell_file)])
    program = "local popen=io.popen\nio.popen=function(command, mode)\n"
    program += "local f=assert(io.open(" + literal(command_file) + ",'wb')); f:write(command); f:close()\n"
    if posix:
        suffix = "\nmsuf_auth_exit=$?\nprintf '%s' \"$msuf_auth_exit\" > '" + exit_file.as_posix() + "'\nexit \"$msuf_auth_exit\"\n"
        program += "local f=assert(io.open(" + literal(shell_file) + ",'wb')); f:write(command .. " + lua_literal(suffix) + "); f:close()\n"
        program += "return popen(" + literal(shell_command) + ",mode) end\n"
        program += "package.config='/' .. package.config:sub(2)\n"
    else:
        program += "return popen(command,mode) end\n"
    script = observer / "tools/tests/menu_pvp_trinket_inventory_smoke.lua"
    if adapter:
        program += "local launch=assert(loadfile(" + literal(root / "tools/tests/menu_section_replay_launcher.lua") + "))()\n"
        program += "launch.Run(" + literal(script) + "," + literal(observer) + ",'Mainline','--capture')\n"
    else:
        program += "arg={" + literal(observer) + ",'Mainline','--capture'}\nassert(loadfile(" + literal(script) + "))()\n"
    runner = output / "run.lua"
    runner.write_text(program, encoding="utf-8")
    env = clean_env({"MSUF_SECTION_SOURCE_ROOT": str(source), "MSUF_SECTION_CAPTURE_BASE": base,
        "MSUF_SECTION_CAPTURE_OUTPUT": str(output), "MSUF_SECTION_CAPTURE_PYTHON": Path(sys.executable).as_posix()})
    run = subprocess.run([str(lua), str(runner)], env=env, cwd=observer, capture_output=True, text=True)
    shell_exit = int(exit_file.read_text()) if posix else None
    return run, output, {"case": name, "lua_native_exit": run.returncode, "shell_native_exit": shell_exit,
        "auth_command": command_file.read_text(), "host": "POSIX Bash boundary on " + os.name if posix else "native Windows"}


def main():
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert lua, "Lua 5.1 required"
    bash = bash_path()
    bash_before = hashlib.sha256(bash.read_bytes()).hexdigest()
    inputs_before = proof_sources(root, __file__)
    before = interpreters(lua)
    launcher = root / "tools/tests/menu_section_replay_launcher.lua"
    adapter_hash = sha(launcher.read_bytes())
    entries = ["tools/tests/menu_" + area + "_inventory_smoke.lua" for area in AREAS] + ["tools/tests/menu_section_capture.py", "tools/tests/menu_section_auth.py"]
    paths, edges = closure(lambda p: (root / p).read_bytes(), entries)
    observer_before = {p: sha((root / p).read_bytes()) for p in paths}
    records = []
    with tempfile.TemporaryDirectory(prefix="section-shell-") as directory:
        folder = Path(directory)
        marker = folder / "python-startup-executed"
        (folder / "sitecustomize.py").write_text("from pathlib import Path\nPath(" + repr(str(marker)) + ").write_text('startup')\n")
        poison = {"LUA_INIT": "error('shell startup contamination executed')", "PYTHONHOME": str(folder),
            "PYTHONPATH": str(folder), "PYTHONSTARTUP": str(folder / "sitecustomize.py")}
        observer = historical_observer(root, root / "tools/fixtures/menu-section-parity", folder / "historical-observer")
        sources = {}
        for label, ref in (("parent", PARENT),):
            support, _ = source_support(root, ref)
            source = folder / (label + "-source-'$literal")
            materialize(root, ref, source, PRODUCT + support)
            sources[label] = (source, validate_source(source, ref))
        # Historical double-quoted paths are refused if they could expand shell syntax.
        historical_source = folder / "historical-source-safe"
        support, _ = source_support(root, BASE)
        materialize(root, BASE, historical_source, PRODUCT + support)
        historical_before = validate_source(historical_source, BASE)
        run, output, record = case(root, folder, lua, bash, observer, historical_source, BASE, "old-posix-red", True, False)
        assert run.returncode != 0 and record["shell_native_exit"] == 127 and "authentication failed" in run.stderr, run.stderr
        records.append(record)
        for name, current, posix in [("historical-posix-green", False, True), ("current-posix-green", True, True)] + (
                [("historical-windows-green", False, False), ("current-windows-green", True, False)] if os.name == "nt" else []):
            selected, source, ref = (root, sources["parent"][0], PARENT) if current else (observer, historical_source, BASE)
            with patch.dict(os.environ, poison):
                run, output, record = case(root, folder, lua, bash, selected, source, ref, name, posix, not current)
            assert not marker.exists(), "isolated nested Python executed startup contamination"
            record["contaminated_parent_environment_sanitized"] = sorted(poison)
            assert run.returncode == 0 and (not posix or record["shell_native_exit"] == 0), run.stdout + run.stderr
            assert " -I -S " in record["auth_command"], "actual nested checker did not use strict Python startup"
            corpus = root / ("tools/fixtures/menu-section-parent" if current else "tools/fixtures/menu-section-parity")
            for prefix in (("", "semantics/", "gaps/") if current else ("", "semantics/")):
                relative = prefix + "pvp_trinket-Mainline.tsv"
                assert (output / relative).read_bytes().replace(b"\r\n", b"\n") == (corpus / relative).read_bytes().replace(b"\r\n", b"\n"), relative
            records.append(record)
        expected = records[0]["auth_command"]
        controls = "local launch=assert(loadfile(" + literal(launcher) + "))()\nlocal calls=0\n"
        controls += "local delegate=function() calls=calls+1; error('unexpected shell execution') end\n"
        for windows in (True, False):
            controls += "local adapt=launch.Adapt(delegate," + literal(Path(sys.executable).as_posix()) + "," + literal(observer) + "," + literal(historical_source) + "," + literal(BASE) + "," + str(windows).lower() + ")\n"
            for command, mode in [(expected + " --extra", "r"), (expected.replace("--check-source", "--help"), "r"), (expected, "w")]:
                controls += "assert(not pcall(adapt," + literal(command) + "," + literal(mode) + "))\n"
        for value in ("$untrusted", "`untrusted`", "untrusted\\path"):
            controls += "assert(not pcall(launch.Adapt,delegate," + lua_literal(value) + "," + literal(observer) + "," + literal(historical_source) + "," + literal(BASE) + ",false))\n"
        controls += "assert(calls==0); print('REJECT unexpected commands, modes, extra args and POSIX shell expansion')\n"
        test = folder / "negative.lua"; test.write_text(controls)
        run = subprocess.run([str(lua), str(test)], env=clean_env(), capture_output=True, text=True)
        assert run.returncode == 0, run.stdout + run.stderr
        print(run.stdout.strip())
        poisoned = dict(os.environ, LUA_INIT="error('shell startup contamination executed')", PYTHONPATH=str(folder))
        raw = subprocess.run([str(lua), "-e", "io.write(_VERSION)"], env=poisoned, capture_output=True, text=True)
        assert raw.returncode != 0 and "shell startup contamination executed" in raw.stderr
        print("REJECT raw Lua startup contamination native" + str(raw.returncode))
        assert validate_source(historical_source, BASE) == historical_before
        for label, ref in (("parent", PARENT),):
            assert validate_source(sources[label][0], ref) == sources[label][1]
        historical_observer(root, root / "tools/fixtures/menu-section-parity")
    assert closure(lambda p: (root / p).read_bytes(), entries) == (paths, edges), "current observer closure changed"
    assert {p: sha((root / p).read_bytes()) for p in paths} == observer_before, "current observer bytes changed"
    assert proof_sources(root, __file__) == inputs_before, "shell proof source/observer inputs changed"
    assert hashlib.sha256(bash.read_bytes()).hexdigest() == bash_before, "actual Bash executable changed"
    assert sha(launcher.read_bytes()) == adapter_hash and interpreters(lua) == before
    for record in records:
        print(json.dumps(record, sort_keys=True))
    print("menu_section_shell_boundary_smoke: old POSIX native127; authentic isolated checker native0; exact adapter refusal and current identity/source pins OK")


if __name__ == "__main__":
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit(subprocess.call([sys.executable, "-I", "-S", str(Path(__file__).resolve()), *sys.argv[1:]], env=clean_env()))
    main()
