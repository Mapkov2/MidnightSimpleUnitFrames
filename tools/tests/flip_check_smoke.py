"""Synthetic red/green proof; no shipped file is edited or source-pinned."""
import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luac", required=True)
    parser.add_argument("--lua")
    args = parser.parse_args()
    assert args.lua, "--lua is required"
    spec = importlib.util.spec_from_file_location("flip", Path(__file__).resolve().parents[1] / "flip_check.py")
    flip = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flip)
    with tempfile.TemporaryDirectory(prefix="msuf-flip-") as directory:
        repo = Path(directory)
        core = repo / "MidnightSimpleUnitFrames"
        (core / "Kernel").mkdir(parents=True)
        (repo / "MidnightSimpleUnitFrames_Options").mkdir()
        (core / "Kernel/MSUF_Bootstrap.lua").write_text(
            "-- BEGIN GENERATED GLOBAL KEEP\nlocal keep = { MSUF_Kept = true }\n-- END GENERATED GLOBAL KEEP\n",
            encoding="utf-8")
        path = core / "probe.lua"

        def audit():
            sources = [p for p in core.rglob('*.lua')]
            scanned = {p.relative_to(repo).as_posix(): flip.scan_lua(p, p.relative_to(repo).as_posix(), args.luac)
                       for p in sources}
            exports = set()
            for source in sources:
                script = "local env = { SomeNativeFrame = {}, MSUF = {} }; env._G = env; setmetatable(env, { __index = _G }); " + \
                    "local chunk = assert(loadfile(arg[1])); setfenv(chunk, env); " + \
                    "assert(pcall(chunk)); for k in pairs(env) do print(k) end"
                runner = repo / 'observe.lua'
                runner.write_text(script, encoding='utf-8')
                output = subprocess.run([args.lua, str(runner), str(source)],
                                        capture_output=True, text=True, check=True)
                exports.update(output.stdout.splitlines())
            return flip.audit_client('probe', {'core': list(scanned), 'Options': []},
                                     {'core': exports, 'Options': set()}, scanned)

        def check(source):
            path.write_text(source, encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                return audit()

        assert check("return MSUF_NewRead\n") > 0, "bare missing provider passed"
        assert check("MSUF_NewRead = 17\nreturn MSUF_NewRead\n") == 0, "bare provider failed"
        assert check("local G = _G\nreturn G.MSUF_AliasMissing\n") > 0, "alias read passed"
        assert check("local frame = _G.SomeNativeFrame\nreturn frame.MSUFSpec\n") == 0, "frame became a global alias"
        assert check("local MSUF = _G.MSUF\nreturn MSUF.MSUF_NamespaceField\n") == 0, "namespace became a global alias"
        assert check('return rawget(_G, "MSUF_RawMissing")\n') > 0, "raw read passed"
        assert check('local doc = "_G.MSUF_NewRead = true"\nreturn MSUF_NewRead\n') > 0, "string invented a provider"
        assert check('local s = "-- not a comment"\n_G["MSUF_Table"] = 1\nreturn _G.MSUF_Table\n') == 0
        assert check("-- return MSUF_Comment\nreturn MSUF_Kept\n") > 0, "keep name invented a provider"
        assert check("MSUF_Kept = 17\nreturn MSUF_Kept\n") == 0
        assert check("-- provider removed\nreturn MSUF_Kept\n") > 0, "removed provider passed"
        assert check('if false then _G.MSUF_Conditional = 1 end; return _G.MSUF_Conditional') > 0
        assert check('local ExportPublic = function() end; ExportPublic("MSUF_Removed", nil); return _G.MSUF_Removed') > 0
        assert check('local Publish = function() end; Publish("MSUF_Unrelated", 1); return MSUF_Unrelated') > 0
        delayed_path = 'MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Preview.lua'
        delayed = repo / delayed_path
        delayed.parent.mkdir(parents=True)
        (core / 'Kernel/MSUF_Bootstrap.lua').write_text(
            '-- BEGIN GENERATED GLOBAL KEEP\nlocal keep = { MSUF_UnitEditModeActive = true }\n-- END GENERATED GLOBAL KEEP\n', encoding='utf-8')
        delayed.write_text('local MIRRORS = { editMode = "MSUF_UnitEditModeActive" }\n'
                           'local name = MIRRORS[key]\nExportPublic(name, value)\n', encoding='utf-8')
        assert 'MSUF_UnitEditModeActive' in flip.delayed_providers(repo, {'core': [delayed_path]})['core']
        delayed.write_text(delayed.read_text().replace('ExportPublic(name, value)', '-- ExportPublic(name, value)'), encoding='utf-8')
        assert not flip.delayed_providers(repo, {'core': [delayed_path]})['core'], 'commented-out delayed provider passed'
        delayed.unlink()
        reader = ('reader.lua', 1, 'MSUF_PhaseProvider', 'GETGLOBAL')
        scanned = {'reader.lua': (set(), [reader]), 'provider.lua': ({'MSUF_PhaseProvider'}, [])}
        with contextlib.redirect_stdout(io.StringIO()):
            assert flip.audit_client('Mainline', {'core': ['reader.lua'], 'Options': ['provider.lua']},
                                     {'core': set(), 'Options': set()}, scanned) > 0, 'Options satisfied a core read'
            assert flip.audit_client('Vanilla', {'core': ['reader.lua'], 'Options': []},
                                     {'core': set(), 'Options': set()}, scanned) > 0, 'other client supplied a provider'
        cast = core / "Castbars/MSUF_CastbarPreviewEdit.lua"
        cast.parent.mkdir()
        path.unlink()
        cast.write_text("local a = MSUF_EditModeSizing\nreturn MSUF_EditModeSizing\n", encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            assert audit() == 0
        cast.write_text("local a = MSUF_EditModeSizing\nlocal b = MSUF_EditModeSizing\nreturn MSUF_EditModeSizing\n",
                        encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            assert audit() > 0, "third occurrence escaped six-read allowance"
        cast.write_text("local a = MSUF_EditModeSizing; local b = MSUF_EditModeSizing\nreturn MSUF_EditModeSizing\n",
                        encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            assert audit() > 0, "same-line occurrence escaped allowance"
        cast.write_text("function broken(", encoding="utf-8")
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                audit()
        except RuntimeError:
            pass
        else:
            raise AssertionError("compiler failure silently passed")
    print("flip mutation proof: missing providers and allowance overflow red; providers green")


if __name__ == "__main__":
    main()
