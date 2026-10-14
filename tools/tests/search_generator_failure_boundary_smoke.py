"""Keep the selected Lua interpreter and reject failed complete child output."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    luac = shutil.which("luac") or os.environ.get("MSUF_LUAC")
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    require(lua and luac and powershell, "Failure-boundary smoke needs the gate's Lua, luac and PowerShell")
    generator = root / ".github/scripts/search_static_index_project.lua"
    wrapper = root / "tools/run-classic-gate.ps1"
    if len(sys.argv) > 2:
        generator = Path(sys.argv[2]) / ".github/scripts/search_static_index_project.lua"
        wrapper = Path(sys.argv[2]) / "tools/run-classic-gate.ps1"
    environment = os.environ.copy()
    environment["MSUF_SEARCH_SOURCE_SHA256"] = "A" * 64
    environment["PROBE"] = "expanded-path"
    with tempfile.TemporaryDirectory(prefix="search-boundary-!PROBE!-&-") as scratch:
        working = Path(scratch)
        shutil.copyfile(wrapper, working / "run-classic-gate.ps1")
        # Run the real preflight/forwarder, replacing only its expensive gate.
        def check_forward(interpreter):
            expected = os.path.abspath(interpreter).replace("'", "''")
            (working / "test-classic-prototype.ps1").write_text(
                "param([int]$Jobs)\n"
                + "if ([IO.Path]::GetFullPath($env:MSUF_LUA) -ne '" + expected
                + "') { throw 'child Lua selection is stale' }\n"
                + "Write-Output 'PASS explicit interpreter forwarded to child environment'\n", encoding="utf-8",
            )
            stale = environment.copy()
            stale["MSUF_LUA"] = str(working / "missing-stale-lua.exe")
            result = subprocess.run(
                [powershell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(working / "run-classic-gate.ps1"),
                 "-LuaPath", str(interpreter), "-LuacPath", luac, "-PythonPath", sys.executable],
                env=stale, capture_output=True,
            )
            require(result.returncode == 0, "Explicit Lua selection did not override the stale child environment: "
                    + (result.stdout + result.stderr).decode(errors="replace"))

        check_forward(lua)
        alias = working / "linked-lua"
        if os.name == "nt":
            command = 'cmd /d /v:off /c mklink /j "' + str(alias) + '" "' + str(Path(lua).absolute().parent) + '"'
            linked = subprocess.run(command, capture_output=True)
            require(linked.returncode == 0, "Could not create the isolated Lua junction")
        else:
            alias.symlink_to(Path(lua).absolute().parent, target_is_directory=True)
        check_forward(alias / Path(lua).name)

        source = generator.read_text(encoding="utf-8")
        begin = source.index("local function BuildFlavor(target)\n")
        end = source.index("--- Runs this script again", begin)
        # Keep the actual child process, terminator, close, renderer and check.
        source = source[:begin] + "local function BuildFlavor(target) return {} end\n\n" + source[end:]
        script = working / "generator.lua"
        script.write_text(source, encoding="utf-8")
        matrix = working / "tools/classic-client-matrix.tsv"
        matrix.parent.mkdir()
        shutil.copyfile(root / "tools/classic-client-matrix.tsv", matrix)
        output = working / "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
        output.parent.mkdir(parents=True)

        def run(*arguments, exit_shadow=None, interpreter=lua):
            selected = environment.copy()
            if exit_shadow is None:
                selected.pop("ERRORLEVEL", None)
            else:
                selected["ERRORLEVEL"] = exit_shadow
            return subprocess.run([str(interpreter), str(script), *arguments], cwd=working, env=selected, capture_output=True)

        generated = run("--stdout")
        require(generated.returncode == 0, "Healthy child processes did not finish: "
                + generated.stderr.decode(errors="replace"))
        expected_catalog = generated.stdout.replace(b"\r\n", b"\n")
        output.write_bytes(expected_catalog)
        for interpreter in (lua, alias / Path(lua).name):
            for shadow in (None, "0", "7"):
                require(run("--check", exit_shadow=shadow, interpreter=interpreter).returncode == 0,
                        "Healthy literal-path children were rejected with ERRORLEVEL=" + str(shadow))
        terminator = 'io.write(table.concat(BuildFlavor(FLAVOR), "\\n"), "\\n", ROWS_TERMINATOR, "\\n")'
        require(source.count(terminator) == 1, "Child-output boundary moved")
        for code in (7, -1):
            failed = source.replace(terminator, terminator + "\n    io.stdout:flush()\n    os.exit(" + str(code) + ")")
            script.write_text(failed, encoding="utf-8")
            for interpreter in (lua, alias / Path(lua).name):
                for shadow in (None, "0", "7"):
                    result = run("--check", exit_shadow=shadow, interpreter=interpreter)
                    require(result.returncode != 0,
                            "Complete output masked exit " + str(code) + " with ERRORLEVEL=" + str(shadow))
                    require(output.read_bytes() == expected_catalog, "Failed-child check changed the shipped catalog")
    print("PASS generator boundaries: explicit Lua/link precedence, literal bang/ampersand paths, healthy/failed children, shadowed status")


if __name__ == "__main__":
    main()
