"""The gate's dead-Lua rule, on fixtures: Assert-MsufUnloadedAddonLua.

The gate fails on any versioned addon Lua file that no shipped TOC loads,
unless tools/classic-unloaded-addon-lua.tsv lists it: an unchanged Retail
mirror Retail never loads ('mirror'), or a Classic-owned file the owner keeps
unloaded on purpose ('retained', whose reason must cite the owner decision).
An unlisted owned or overridden unloaded file must fail, an overridden file can
never be listed, and a row whose file a TOC loads is stale. Every case runs the
real module function in one PowerShell process and must give its verdict.

Usage: python tools/tests/unloaded_addon_lua_smoke.py <repository root>
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
MODULE = root / ".github" / "scripts" / "ClassicGate.Common.psm1"
HEADER = "Path\tKind\tReason\n"
OWNED = "MidnightSimpleUnitFrames/Runtime/Theme.lua"
MIRROR = "MidnightSimpleUnitFrames/Features/Debug.lua"
OVERRIDE = "MidnightSimpleUnitFrames/Kernel/Patched.lua"
LOADED = "MidnightSimpleUnitFrames/Core.lua"
DECISION = "kept on purpose by owner decision"

failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def case(name, rows, versionable, expected, fragment="", owned=(OWNED,), overrides=(OVERRIDE,)):
    return {
        "name": name,
        "manifest": HEADER + "".join("\t".join(row) + "\n" for row in rows),
        "versionable": list(versionable),
        "loaded": [LOADED],
        "owned": list(owned),
        "overrides": list(overrides),
        "tracked": sorted({OWNED, MIRROR, OVERRIDE, LOADED}),
        "expected": expected,
        "fragment": fragment,
    }


ALL = (LOADED, OWNED, MIRROR, OVERRIDE)
CASES = [
    case("retained owned file listed with the decision", [(OWNED, "retained", DECISION)], (LOADED, OWNED), "PASS 0 1"),
    case("mirror listed", [(MIRROR, "mirror", "Retail never loads it")], (LOADED, MIRROR), "PASS 1 0"),
    case("both kinds together", [(MIRROR, "mirror", "Retail never loads it"), (OWNED, "retained", DECISION)],
         (LOADED, OWNED, MIRROR), "PASS 1 1"),
    case("unlisted owned file", [], (LOADED, OWNED), "FAIL", "dead payload"),
    case("unlisted overridden file", [], (LOADED, OVERRIDE), "FAIL", "dead payload"),
    case("unlisted mirror", [], (LOADED, MIRROR), "FAIL", "dead payload"),
    case("retained without the decision", [(OWNED, "retained", "still useful")], (LOADED, OWNED), "FAIL",
         "without citing the owner decision"),
    case("retained file that is not owned", [(MIRROR, "retained", DECISION)], (LOADED, MIRROR), "FAIL",
         "not Classic-owned"),
    case("owned file listed as a mirror", [(OWNED, "mirror", "Retail never loads it")], (LOADED, OWNED), "FAIL",
         "as a Retail mirror"),
    case("overridden file listed as retained", [(OVERRIDE, "retained", DECISION)], (LOADED, OVERRIDE), "FAIL",
         "dead Classic edit"),
    case("overridden file listed as a mirror", [(OVERRIDE, "mirror", "Retail never loads it")], (LOADED, OVERRIDE),
         "FAIL", "dead Classic edit"),
    case("row for a loaded file", [(LOADED, "mirror", "Retail never loads it")], (LOADED,), "FAIL", "Stale"),
    case("unknown kind", [(MIRROR, "kept", "Retail never loads it")], (LOADED, MIRROR), "FAIL", "unknown kind"),
    case("empty reason", [(MIRROR, "mirror", "")], (LOADED, MIRROR), "FAIL", "without empty or padded fields"),
    case("unsorted rows", [(OWNED, "retained", DECISION), (MIRROR, "mirror", "Retail never loads it")],
         (LOADED, OWNED, MIRROR), "FAIL", "ordinal"),
]

RUNNER = r"""
param([string]$ModulePath, [string]$CasesPath, [string]$CaseRoot)
$ErrorActionPreference = "Stop"
Import-Module $ModulePath -Force
$cases = [IO.File]::ReadAllText($CasesPath) | ConvertFrom-Json
$index = 0
foreach ($case in $cases) {
    $index++
    $manifest = Join-Path $CaseRoot ("case{0}.tsv" -f $index)
    [IO.File]::WriteAllText($manifest, $case.manifest, [Text.UTF8Encoding]::new($false))
    try {
        $result = Assert-MsufUnloadedAddonLua -Root $CaseRoot -ManifestPath $manifest `
            -VersionableLua ([string[]]@($case.versionable)) `
            -LoadedPaths ([string[]]@($case.loaded | ForEach-Object { Join-Path $CaseRoot $_ })) `
            -OwnedPaths ([string[]]@($case.owned)) -OverridePaths ([string[]]@($case.overrides)) `
            -TrackedPaths ([string[]]@($case.tracked))
        [Console]::Out.WriteLine("CASE`t$index`tPASS $($result.Mirrors) $($result.Retained)")
    } catch {
        [Console]::Out.WriteLine("CASE`t$index`tFAIL`t" + ($_.Exception.Message -replace '\s+', ' '))
    }
}
"""


def remove_tree(path):
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


print("unloaded addon Lua rule (Assert-MsufUnloadedAddonLua)")
shell = shutil.which("pwsh") or shutil.which("powershell")
scratch = Path(tempfile.mkdtemp(prefix="msuf-unloaded-lua-smoke-")).resolve()
try:
    if shell is None:
        check(False, "PowerShell (pwsh or powershell) is on PATH: the gate's own rule is checked here")
    else:
        (scratch / "runner.ps1").write_text(RUNNER, encoding="utf-8")
        (scratch / "cases.json").write_text(json.dumps(CASES), encoding="utf-8")
        process = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                                  str(scratch / "runner.ps1"), "-ModulePath", str(MODULE),
                                  "-CasesPath", str(scratch / "cases.json"), "-CaseRoot", str(scratch)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        verdicts = {}
        for line in process.stdout.decode("utf-8", "replace").splitlines():
            fields = line.split("\t")
            if len(fields) >= 3 and fields[0] == "CASE":
                verdicts[int(fields[1])] = fields[2:]
        check(len(verdicts) == len(CASES), "PowerShell answered every case (exit %d): %s" % (
            process.returncode, process.stderr.decode("utf-8", "replace").strip()[:400]))
        for index, item in enumerate(CASES, 1):
            verdict = verdicts.get(index)
            if verdict is None:
                continue
            if item["expected"].startswith("PASS"):
                check(verdict[0] == item["expected"], "%s passes (%s)" % (item["name"], " ".join(verdict)))
            else:
                detail = " ".join(verdict[1:])
                check(verdict[0] == "FAIL" and item["fragment"] in detail,
                      "%s fails: %s (%s)" % (item["name"], item["fragment"], detail[:160]))
finally:
    remove_tree(scratch)

print()
if failures:
    print("unloaded addon Lua smoke: %d FAILED" % len(failures))
    for message in failures:
        print("  " + message)
    sys.exit(1)
print("unloaded addon Lua smoke: ok")
