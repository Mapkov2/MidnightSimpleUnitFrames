"""Synthetic red/green proof; no shipped file is edited or source-pinned."""
import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luac", required=True)
    args = parser.parse_args()
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

        def check(source):
            path.write_text(source, encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                return flip.audit(repo, args.luac)

        assert check("return MSUF_NewRead\n") > 0, "bare missing provider passed"
        assert check("MSUF_NewRead = 17\nreturn MSUF_NewRead\n") == 0, "bare provider failed"
        assert check("local G = _G\nreturn G.MSUF_AliasMissing\n") > 0, "alias read passed"
        assert check("local frame = _G.SomeNativeFrame\nreturn frame.MSUFSpec\n") == 0, "frame became a global alias"
        assert check("local MSUF = _G.MSUF\nreturn MSUF.MSUF_NamespaceField\n") == 0, "namespace became a global alias"
        assert check('return rawget(_G, "MSUF_RawMissing")\n') > 0, "raw read passed"
        assert check('local doc = "_G.MSUF_NewRead = true"\nreturn MSUF_NewRead\n') > 0, "string invented a provider"
        assert check('local s = "-- not a comment"\n_G["MSUF_Table"] = 1\nreturn _G.MSUF_Table\n') == 0
        assert check("-- return MSUF_Comment\nreturn MSUF_Kept\n") == 0
        cast = core / "Castbars/MSUF_CastbarPreviewEdit.lua"
        cast.parent.mkdir()
        path.unlink()
        cast.write_text("local a = MSUF_EditModeSizing\nreturn MSUF_EditModeSizing\n", encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            assert flip.audit(repo, args.luac) == 0
        cast.write_text("local a = MSUF_EditModeSizing\nlocal b = MSUF_EditModeSizing\nreturn MSUF_EditModeSizing\n",
                        encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            assert flip.audit(repo, args.luac) > 0, "third occurrence escaped six-read allowance"
        cast.write_text("local a = MSUF_EditModeSizing; local b = MSUF_EditModeSizing\nreturn MSUF_EditModeSizing\n",
                        encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            assert flip.audit(repo, args.luac) > 0, "same-line occurrence escaped allowance"
        cast.write_text("function broken(", encoding="utf-8")
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                flip.audit(repo, args.luac)
        except RuntimeError:
            pass
        else:
            raise AssertionError("compiler failure silently passed")
    print("flip mutation proof: missing providers and allowance overflow red; providers green")


if __name__ == "__main__":
    main()
