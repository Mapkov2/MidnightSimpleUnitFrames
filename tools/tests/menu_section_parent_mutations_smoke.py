"""New parent storage/reset/fallback observations must reject actual causal owner mutations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import clean_env, interpreters
from menu_section_test_runtime import lua_literal, proof_sources


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
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert lua, "Lua 5.1 required"
    runtime_before = interpreters(lua)
    inputs_before = proof_sources(root, __file__)
    world = (root / "tools/tests/menu_section_parity_world.lua").read_text()
    gap = (root / "tools/tests/menu_section_parent_semantics.lua").read_text()
    product_path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitDispel.lua"
    product = (root / product_path).read_text()
    marker = "local calls = {}"
    late_gap = gap.replace("local function Probe(page, _, wanted, check)",
        "local function Probe(page, _, wanted, check)\n        env._sectionGapProbe = true")
    fallback = """local bind = M.BindNumberWidget
    M.BindNumberWidget = function(ctx, widget, get, set, value, opts)
        return bind(ctx, widget, get, set, 99, opts)
    end"""
    reset = """local factory = M.UnitSectionsShared.FactoryProfile
    M.UnitSectionsShared.FactoryProfile = function(...)
        local profile = factory(...)
        if env._sectionGapProbe then
            profile = core.ProfileFields.CopySnapshot(profile)
            profile.player.unitDispelOverlayAlpha = 0.99
        end
        return profile
    end"""
    return_default = "if value == nil then return defaultValue end"
    assert product.count(return_default) == 1
    mutations = [
        ("absent-storage", "dispel_overlay", product.replace(return_default,
            'if _G._sectionGapProbe and key == "unitDispelOverlayAlpha" and value == nil then return 99 end\n    ' + return_default), None),
        ("legacy-fallback", "dispel_overlay", product.replace("value = general and general[key]",
            'value = general and general[key]\n        if _G._sectionGapProbe then value = nil end'), None),
        ("explicit-false-zero", "dispel_overlay", product.replace(return_default,
            'if _G._sectionGapProbe and (value == false or value == 0) then return defaultValue end\n    ' + return_default), None),
        ("dispel-reset", "dispel_overlay", None, reset),
        ("overlay-numeric-fallback", "dispel_overlay", None, fallback),
        ("symbol-numeric-fallback", "dispel_symbol", None, fallback),
        ("layout-numeric-fallback", "boss_arena_layout", None, fallback),
    ]
    with tempfile.TemporaryDirectory(prefix="section-parent-mutants-") as directory:
        folder = Path(directory)
        for area in sorted({case[1] for case in mutations}):
            script = root / ("tools/tests/menu_" + area + "_inventory_smoke.lua")
            run = subprocess.run([str(lua), str(script), str(root), "Mainline"], cwd=root, env=clean_env(), capture_output=True, text=True)
            assert run.returncode == 0, run.stdout + run.stderr
            print("BASELINE " + area + " native0")
        for name, area, changed_product, hook in mutations:
            case = folder / name
            case.mkdir()
            diagnostics = case / "diagnostics"
            diagnostic_name = area + "-Mainline-gaps-actual.tsv"
            diagnostic_io = diagnostic_redirect(root, diagnostics, [diagnostic_name])
            redirects = {}
            helper = case / "gaps.lua"
            helper.write_text(late_gap)
            redirects[(root / "tools/tests/menu_section_parent_semantics.lua").as_posix()] = helper.as_posix()
            if changed_product:
                path = case / "product.lua"
                path.write_text(changed_product)
                redirects[(root / product_path).as_posix()] = path.as_posix()
            if hook:
                path = case / "world.lua"
                path.write_text(world.replace(marker, hook + "\n    " + marker))
                redirects[(root / "tools/tests/menu_section_parity_world.lua").as_posix()] = path.as_posix()
            runner = case / "run.lua"
            mappings = ",\n".join("[" + lua_literal(k) + "]=" + lua_literal(v) for k, v in redirects.items())
            script = (root / ("tools/tests/menu_" + area + "_inventory_smoke.lua")).as_posix()
            runner.write_text("local redirects={" + mappings + "}\nlocal load,open=loadfile,io.open\n"
                "loadfile=function(p) return load(redirects[p:gsub('\\\\','/')] or p) end\n"
                "io.open=function(p,mode) return open(redirects[p:gsub('\\\\','/')] or p,mode) end\n"
                + diagnostic_io + "arg={" + lua_literal(root.as_posix()) + ",'Mainline'}\nassert(load(" + lua_literal(script) + "))()\n")
            run = subprocess.run([str(lua), str(runner)], cwd=root, env=clean_env(), capture_output=True, text=True)
            assert run.returncode != 0 and "parent storage/fallback/reset observations drifted" in run.stderr, (name, run.stdout, run.stderr)
            assert (diagnostics / diagnostic_name).is_file(), "parent drift diagnostic missing"
            print("REJECT " + name + " native" + str(run.returncode))
    assert proof_sources(root, __file__) == inputs_before, "parent mutation proof inputs changed"
    assert interpreters(lua) == runtime_before, "current mutation replay interpreter identity changed"
    print("menu_section_parent_mutations_smoke: 3 baselines native0; 7 new storage/reset/numeric owner mutations rejected")


if __name__ == "__main__":
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit(subprocess.call(
            [sys.executable, "-I", "-S", str(Path(__file__).resolve()), *sys.argv[1:]], env=clean_env()))
    main()
