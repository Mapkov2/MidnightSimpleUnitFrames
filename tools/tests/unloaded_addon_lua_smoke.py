"""The gate's dead-Lua rule, on fixtures: Assert-MsufUnloadedAddonLua.

The gate fails on any versioned addon Lua file that no shipped TOC loads,
unless tools/classic-unloaded-addon-lua.tsv lists it: a developer diagnostic no
TOC loads ('diagnostic'), or a file the owner keeps unloaded on purpose
('retained', whose reason must cite the owner decision). An unlisted unloaded
file must fail, and a row whose file a TOC loads is stale. Every case runs the
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
RETAINED = "MidnightSimpleUnitFrames/Runtime/Theme.lua"
DIAGNOSTIC = "MidnightSimpleUnitFrames/Features/Debug.lua"
LOADED = "MidnightSimpleUnitFrames/Core.lua"
UNTRACKED = "MidnightSimpleUnitFrames/Runtime/Scratch.lua"
DECISION = "kept on purpose by owner decision"

failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def case(name, rows, versionable, expected, fragment=""):
    return {
        "name": name,
        "manifest": HEADER + "".join("\t".join(row) + "\n" for row in rows),
        "versionable": list(versionable),
        "loaded": [LOADED],
        "tracked": sorted({RETAINED, DIAGNOSTIC, LOADED}),
        "expected": expected,
        "fragment": fragment,
    }


CASES = [
    case("retained file listed with the decision", [(RETAINED, "retained", DECISION)], (LOADED, RETAINED), "PASS 0 1"),
    case("diagnostic listed", [(DIAGNOSTIC, "diagnostic", "no TOC loads it")], (LOADED, DIAGNOSTIC), "PASS 1 0"),
    case("both kinds together", [(DIAGNOSTIC, "diagnostic", "no TOC loads it"), (RETAINED, "retained", DECISION)],
         (LOADED, RETAINED, DIAGNOSTIC), "PASS 1 1"),
    case("unlisted retained-looking file", [], (LOADED, RETAINED), "FAIL", "dead payload"),
    case("unlisted diagnostic-looking file", [], (LOADED, DIAGNOSTIC), "FAIL", "dead payload"),
    case("retained without the decision", [(RETAINED, "retained", "still useful")], (LOADED, RETAINED), "FAIL",
         "without citing the owner decision"),
    case("row for a loaded file", [(LOADED, "diagnostic", "no TOC loads it")], (LOADED,), "FAIL", "Stale"),
    case("the retired mirror kind", [(DIAGNOSTIC, "mirror", "no TOC loads it")], (LOADED, DIAGNOSTIC), "FAIL",
         "unknown kind"),
    case("unknown kind", [(DIAGNOSTIC, "kept", "no TOC loads it")], (LOADED, DIAGNOSTIC), "FAIL", "unknown kind"),
    case("empty reason", [(DIAGNOSTIC, "diagnostic", "")], (LOADED, DIAGNOSTIC), "FAIL",
         "without empty or padded fields"),
    case("untracked file listed", [(UNTRACKED, "diagnostic", "no TOC loads it")], (LOADED,), "FAIL",
         "must name tracked addon Lua files"),
    case("unsorted rows", [(RETAINED, "retained", DECISION), (DIAGNOSTIC, "diagnostic", "no TOC loads it")],
         (LOADED, RETAINED, DIAGNOSTIC), "FAIL", "ordinal"),
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
            -TrackedPaths ([string[]]@($case.tracked))
        [Console]::Out.WriteLine("CASE`t$index`tPASS $($result.Diagnostics) $($result.Retained)")
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
