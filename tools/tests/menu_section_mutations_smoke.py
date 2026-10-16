"""Real owner mutations must fail the added old-source observations, with baseline green."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import clean_env, interpreters
from menu_section_capture import digest, manifest_sha, sha
import json
from menu_section_test_runtime import lua_literal, proof_sources



def comparison_override(root, lua, source, hook, folder):
    """Known-red owner output must never choose its own comparison expectations."""
    folder.mkdir()
    diagnostics = folder / "negative-control-diagnostics"
    diagnostics.mkdir()
    observed = "local gapResult = gaps.Result()"
    assert source.count(observed) == 1, "negative-control observation point changed"
    collector = source.replace(observed, observed + '\n'
        '    Write(root .. "/.checks/FORGED-gap.tsv", gapResult)\n'
        '    Write(root .. "/.checks/FORGED-semantics.tsv", semanticResult)')
    script = root / "tools/tests/menu_pvp_trinket_inventory_smoke.lua"
    marker = "local calls = {}"
    assert source.count(marker) == 1, "owner mutation point changed"
    def run(name, observer, output=None):
        helper = folder / (name + "-world.lua")
        helper.write_text(observer.replace(marker, hook + "\n    " + marker), encoding="utf-8")
        runner = folder / (name + "-run.lua")
        runner.write_text("local originalLoad, originalOpen = loadfile, io.open\n"
            "io.open = function(path, mode)\n"
            "    if mode and mode:find('[wa]') then\n"
            "        local prefix = " + lua_literal(root.as_posix() + "/.checks/") + "\n"
            "        assert(path:sub(1, #prefix) == prefix, 'unexpected diagnostic write')\n"
            "        return originalOpen(" + lua_literal(diagnostics.as_posix() + "/") + " .. path:sub(#prefix + 1), mode)\n"
            "    end\n    return originalOpen(path, mode)\nend\n"
            "loadfile = function(path)\n"
            "    if path:match('/menu_section_parity_world%.lua$') then return originalLoad(" + lua_literal(helper.as_posix()) + ") end\n"
            "    return originalLoad(path)\nend\n"
            "arg = {" + lua_literal(root.as_posix()) + ",'Mainline'}\n"
            "assert(originalLoad(" + lua_literal(script.as_posix()) + "))()\n", encoding="utf-8")
        env = clean_env()
        env.pop("MSUF_SECTION_CAPTURE_OUTPUT", None)
        if output is not None:
            env["MSUF_SECTION_CAPTURE_OUTPUT"] = str(output)
        return subprocess.run([str(lua), str(runner)], cwd=root, env=env, capture_output=True, text=True)

    # Observe real mutant outputs into labelled scratch before the canonical comparison fails.
    canonical_red = run("canonical-known-red", collector)
    assert canonical_red.returncode != 0 and "parent storage/fallback/reset observations drifted" in canonical_red.stderr, canonical_red.stderr
    corpus = root / "tools/fixtures/menu-section-parent"
    forged = folder / "FORGED-NEGATIVE-CONTROL-RECEIPTS"
    shutil.copytree(corpus, forged)
    metadata = json.loads((forged / "provenance.json").read_text())
    pins = (forged / "provenance.lua").read_text()
    for prefix, observed_name in (("gaps/", "FORGED-gap.tsv"), ("semantics/", "FORGED-semantics.tsv")):
        name = prefix + "pvp_trinket-Mainline.tsv"
        target = forged / name
        old, actual = target.read_bytes(), (diagnostics / observed_name).read_bytes()
        assert old != actual and b"99" in actual, "existing owner mutant did not change actual observations"
        pins = pins.replace(f'["{name}"] = "{digest(old)}"', f'["{name}"] = "{digest(actual)}"')
        target.write_bytes(actual)
        metadata["fixture_sha256"][name] = sha(actual)
    previous = metadata["fixture_manifest_sha256"]
    metadata["fixture_manifest_sha256"] = manifest_sha(metadata["fixture_sha256"])
    pins = pins.replace(previous, metadata["fixture_manifest_sha256"])
    (forged / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (forged / "provenance.lua").write_text(pins)
    # No interception/collector is present in this comparison; only the original known-red hook.
    for name, output in (("forged-known-red", forged), ("canonical-copy-override", corpus), ("empty-override", "")):
        rejected = run(name, source, output)
        assert rejected.returncode != 0 and "comparison must use canonical repository receipts" in rejected.stderr, (
            name, rejected.returncode, rejected.stdout, rejected.stderr)
        print("REJECT compare expectation override: " + name)
    print("menu_section_mutations_smoke: known-red owner cannot self-certify with forged alternate expectations")


def diagnostic_redirect(root, directory, names):
    """Only the concrete observer diagnostics may write into this case's scratch."""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
    assert names and len(names) == len(set(names)), "diagnostic names must be unique"
    assert all(name not in (".", "..") and name and all(c in allowed for c in name) for name in names), "unsafe diagnostic name"
    directory.mkdir()
    paths = ",\n".join("[" + lua_literal(root.as_posix() + "/.checks/" + name) + "]="
        + lua_literal((directory / name).as_posix()) for name in names)
    return ("local diagnosticPaths={" + paths + "}\nlocal diagnosticOpen=io.open\n"
        "io.open=function(path,mode)\n"
        "    if mode and mode:find('[wa+]') then\n"
        "        local target=diagnosticPaths[path]\n"
        "        assert(target and mode == 'wb', 'unexpected diagnostic write: ' .. tostring(path))\n"
        "        return diagnosticOpen(target,mode)\n"
        "    end\n    return diagnosticOpen(path,mode)\nend\n")


def main():
    ROOT = Path(sys.argv[1]).resolve()
    LUA = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert LUA, "Lua 5.1 required"
    runtime_before = interpreters(LUA)
    inputs_before = proof_sources(ROOT, __file__)
    source = (ROOT / "tools/tests/menu_section_parity_world.lua").read_text(encoding="utf-8")
    marker = "local calls = {}"
    assert source.count(marker) == 1, "mutation insertion point changed"
    hooks = {
        "default": '''local read = M.UnitPage.ReadNumber
        M.UnitPage.ReadNumber = function(unit, key, fallback)
            if key == "trinketSize" and env.MSUF_DB[unit][key] == nil then return 99 end
            return read(unit, key, fallback)
        end''',
        "reset": '''local factory = M.UnitSectionsShared.FactoryProfile
        M.UnitSectionsShared.FactoryProfile = function(...)
            local profile = factory(...)
            if env.MSUF_DB.arena and env.MSUF_DB.arena.trinketSize == nil then
                profile = core.ProfileFields.CopySnapshot(profile)
                profile.arena.trinketSize = 99
            end
            return profile
        end''',
        "alignment": '''local move = M.Widgets.MoveWidget
        M.Widgets.MoveWidget = function(widget, parent, x, y, width, align)
            if widget._msuf2ControlKind == "dropdown" then align = "RIGHT" end
            return move(widget, parent, x, y, width, align)
        end''',
        "binding-fallback": '''local bind = M.BindNumberWidget
        M.BindNumberWidget = function(ctx, widget, get, set, fallback, opts)
            if opts and tostring(opts.settingKey):match("trinketSize$") then fallback = 99 end
            return bind(ctx, widget, get, set, fallback, opts)
        end''',
    }
    script = ROOT / "tools/tests/menu_pvp_trinket_inventory_smoke.lua"
    with tempfile.TemporaryDirectory(prefix="section-owner-mutations-") as directory:
        folder = Path(directory)
        for flavor in ("Mainline", "TBC", "Mists"):
            baseline = subprocess.run([LUA, str(script), str(ROOT), flavor], cwd=ROOT, env=clean_env(), capture_output=True, text=True)
            assert baseline.returncode == 0, baseline.stdout + baseline.stderr
            for name, hook in hooks.items():
                case = folder / (flavor + "-" + name)
                case.mkdir()
                diagnostics = case / "diagnostics"
                names = ["pvp_trinket-" + flavor + "-" + kind + "-actual.tsv" for kind in ("gaps", "semantics")]
                redirect = diagnostic_redirect(ROOT, diagnostics, names)
                helper = case / "mutated.lua"
                helper.write_text(source.replace(marker, hook + "\n    " + marker), encoding="utf-8")
                runner = case / "run.lua"
                runner.write_text(redirect + "local original = loadfile\nloadfile = function(path)\n"
                    "    if path:match('/menu_section_parity_world%.lua$') then return original(" + lua_literal(helper.as_posix()) + ") end\n"
                    "    return original(path)\nend\narg = {" + lua_literal(ROOT.as_posix()) + "," + lua_literal(flavor) + "}\n"
                    "assert(original(" + lua_literal(script.as_posix()) + "))()\n", encoding="utf-8")
                run = subprocess.run([LUA, str(runner)], cwd=ROOT, env=clean_env(), capture_output=True, text=True)
                assert run.returncode != 0 and ("defaults/reset/alignment drifted" in run.stderr or "parent storage/fallback/reset observations drifted" in run.stderr), (name, flavor, run.stdout, run.stderr)
                assert any((diagnostics / filename).is_file() for filename in names), "semantic drift diagnostic missing"
                print(f"REJECT {flavor}/{name}")
        comparison_override(ROOT, LUA, source, hooks["default"], folder / "compare-expectations")
    print("menu_section_mutations_smoke: 3 native baselines green, 12 causal owner mutations rejected")

    assert proof_sources(ROOT, __file__) == inputs_before, "owner mutation proof source/observer inputs changed"
    assert interpreters(LUA) == runtime_before, "owner mutation proof current interpreter identity changed"


if __name__ == "__main__":
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit(subprocess.call([sys.executable, "-I", "-S", str(Path(__file__).resolve()), *sys.argv[1:]], env=clean_env()))
    main()
