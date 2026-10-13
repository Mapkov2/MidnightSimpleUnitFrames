"""The gate's TOC identity pin and addon path rules, on fixtures and on the real TOCs.

tools/classic-toc-identity.tsv pins the TOC metadata lines that carry profile and release identity
(SavedVariables, the Wago and Curse IDs), that code reads back at runtime (X-MSUF-UnitFrames*,
AddonCompartmentFunc*) or that make the Options addon load on demand. The gate compares the clients'
TOCs with each other, so only the pin notices a field that disappears from every client at once.
Assert-MsufAddonPaths rejects a malformed file path below the addon folders and two paths that differ
only by case. Every case runs the real module function in one PowerShell process.

Usage: python tools/tests/gate_manifest_rules_smoke.py <repository root>
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
CORE = "MidnightSimpleUnitFrames"
OPTIONS = "MidnightSimpleUnitFrames_Options"
HEADER = "Addon\tRule\tLine\n"
failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


PIN = HEADER + "".join("\t".join(row) + "\n" for row in (
    (CORE, "line", "## SavedVariables: MSUF_DB, MSUF_GlobalDB"),
    (CORE, "line", "## X-Wago-ID: ABC123"),
    (CORE, "line", "## AddonCompartmentFunc: MSUF_OnClick"),
    (OPTIONS, "line", "## LoadOnDemand: 1"),
    (OPTIONS, "line", "## Dependencies: MidnightSimpleUnitFrames"),
    (OPTIONS, "absent", "## SavedVariables:"),
))
CORE_TOC = ["## Interface: 1", "## Title: Core", "## SavedVariables: MSUF_DB, MSUF_GlobalDB", "## X-Wago-ID: ABC123",
            "## AddonCompartmentFunc: MSUF_OnClick", "Kernel\\Boot.lua"]
OPTIONS_TOC = ["## Interface: 1", "## Title: Options", "## LoadOnDemand: 1", "## Dependencies: MidnightSimpleUnitFrames",
               "Menu\\Menu.lua"]


def without(lines, prefix):
    return [line for line in lines if not line.startswith(prefix)]


def identity(name, addon, toc, expected, fragment="", pin=PIN):
    return {"kind": "identity", "name": name, "addon": addon, "toc": toc, "pin": pin, "expected": expected,
            "fragment": fragment}


def paths(name, listed, expected, fragment=""):
    return {"kind": "paths", "name": name, "paths": listed, "expected": expected, "fragment": fragment}


A = CORE + "/Kernel/"
CASES = [
    identity("a complete core TOC passes", CORE, CORE_TOC, "PASS"),
    identity("a complete Options TOC passes", OPTIONS, OPTIONS_TOC, "PASS"),
    identity("a core TOC without SavedVariables", CORE, without(CORE_TOC, "## SavedVariables:"), "FAIL",
             "## SavedVariables: MSUF_DB, MSUF_GlobalDB"),
    identity("a core TOC with a renamed saved variable", CORE,
             [l.replace("MSUF_GlobalDB", "MSUF_Global") for l in CORE_TOC], "FAIL", "found 0"),
    identity("a core TOC without the Wago ID", CORE, without(CORE_TOC, "## X-Wago-ID:"), "FAIL", "X-Wago-ID"),
    identity("a core TOC with another Wago ID", CORE, [l.replace("ABC123", "ZZZ999") for l in CORE_TOC], "FAIL", "X-Wago-ID"),
    identity("a core TOC without the compartment function", CORE, without(CORE_TOC, "## AddonCompartmentFunc:"), "FAIL",
             "AddonCompartmentFunc"),
    identity("a core TOC that repeats a pinned line", CORE, CORE_TOC + ["## X-Wago-ID: ABC123"], "FAIL", "found 2"),
    identity("an Options TOC that is not load on demand", OPTIONS, without(OPTIONS_TOC, "## LoadOnDemand:"), "FAIL",
             "LoadOnDemand"),
    identity("an Options TOC without its dependency", OPTIONS, without(OPTIONS_TOC, "## Dependencies:"), "FAIL", "Dependencies"),
    identity("an Options TOC that declares saved variables", OPTIONS, OPTIONS_TOC + ["## SavedVariables: MSUF_DB"], "FAIL",
             "## SavedVariables:"),
    identity("a pin without its header", CORE, CORE_TOC, "FAIL", "must start with the header", pin=PIN.replace(HEADER, "")),
    identity("a pin with an unknown rule", CORE, CORE_TOC, "FAIL", "unknown rule",
             pin=PIN + CORE + "\tmust\t## Title: Core\n"),
    identity("a pin for an addon that is not shipped", CORE, CORE_TOC, "FAIL", "not shipped",
             pin=PIN + "Elsewhere\tline\t## Title: Core\n"),
    identity("a pin line that is not TOC metadata", CORE, CORE_TOC, "FAIL", "starting with '## '",
             pin=PIN + CORE + "\tline\tKernel\\Boot.lua\n"),
    identity("a pin that repeats a row", CORE, CORE_TOC, "FAIL", "repeats a row",
             pin=PIN + CORE + "\tline\t## X-Wago-ID: ABC123\n"),
    identity("a pin that leaves an addon unpinned", CORE, CORE_TOC, "FAIL", "pins nothing for",
             pin="\n".join(l for l in PIN.splitlines() if not l.startswith(OPTIONS)) + "\n"),
    paths("normalized paths pass", [A + "Boot.lua", A + "boot_two.lua", OPTIONS + "/Menu/Menu.lua"], "PASS"),
    paths("two paths that differ only by case", [A + "Foo.lua", A + "foo.lua"], "FAIL", "Case-colliding"),
    paths("the same path twice is no collision", [A + "Foo.lua", A + "Foo.lua"], "PASS"),
    paths("a path with a backslash", [CORE + "\\Kernel\\Boot.lua"], "FAIL", "not a normalized path"),
    paths("a path with a dot segment", [CORE + "/Kernel/../Boot.lua"], "FAIL", "not a normalized path"),
    paths("a path with an empty segment", [CORE + "//Kernel/Boot.lua"], "FAIL", "not a normalized path"),
    paths("a path with a trailing space", [A + "Boot.lua "], "FAIL", "not a normalized path"),
    paths("a path with a control character", [A + "Bo\u0007ot.lua"], "FAIL", "not a normalized path"),
    paths("a path outside the addon folders", ["tools/Boot.lua"], "FAIL", "not a normalized path"),
]

RUNNER = r"""
param([string]$ModulePath, [string]$CasesPath, [string]$CaseRoot, [string]$RepoRoot)
$ErrorActionPreference = "Stop"
Import-Module $ModulePath -Force
$folders = [string[]]@("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")
function Report([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        [Console]::Out.WriteLine("CASE`t$Name`tPASS`t")
    } catch {
        [Console]::Out.WriteLine("CASE`t$Name`tFAIL`t" + ($_.Exception.Message -replace '\s+', ' '))
    }
}
$cases = [IO.File]::ReadAllText($CasesPath) | ConvertFrom-Json
$index = 0
foreach ($case in $cases) {
    $index++
    if ($case.kind -eq "identity") {
        $pinPath = Join-Path $CaseRoot ("pin{0}.tsv" -f $index)
        [IO.File]::WriteAllText($pinPath, $case.pin, [Text.UTF8Encoding]::new($false))
        Report $case.name {
            $rows = Import-MsufTocIdentity -Path $pinPath -Addons $folders
            Assert-MsufTocIdentity -TocName "fixture.toc" -Addon $case.addon -Content ([string[]]@($case.toc)) -Rows $rows
        }
    } else {
        Report $case.name { Assert-MsufAddonPaths -Paths ([string[]]@($case.paths)) -AddonFolders $folders }
    }
}
# The real pin against the real TOCs: it holds, and removing any pinned line from any client fails.
$rows = Import-MsufTocIdentity -Path (Join-Path $RepoRoot "tools/classic-toc-identity.tsv") -Addons $folders
$matrix = @(Import-MsufClientMatrix -Path (Join-Path $RepoRoot "tools/classic-client-matrix.tsv"))
foreach ($client in $matrix) {
    foreach ($addon in $folders) {
        $tocPath = Join-Path $RepoRoot "$addon/$($addon)_$($client.Suffix).toc"
        $content = [string[]]@(Get-Content -LiteralPath $tocPath)
        Report "real $addon $($client.Suffix) passes the pin" { Assert-MsufTocIdentity -TocName $tocPath -Addon $addon -Content $content -Rows $rows }
        foreach ($row in @($rows | Where-Object { $_.Addon -ceq $addon -and $_.Rule -ceq "line" })) {
            $mutated = [string[]]@($content | Where-Object { $_.TrimEnd() -cne $row.Line })
            Report "real $addon $($client.Suffix) without [$($row.Line)]" { Assert-MsufTocIdentity -TocName $tocPath -Addon $addon -Content $mutated -Rows $rows }
        }
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


print("TOC identity pin and addon path rules (ClassicGate.Common.psm1)")
shell = shutil.which("pwsh") or shutil.which("powershell")
scratch = Path(tempfile.mkdtemp(prefix="msuf-gate-rules-smoke-")).resolve()
try:
    if shell is None:
        check(False, "PowerShell (pwsh or powershell) is on PATH: the gate's own rules are checked here")
    else:
        (scratch / "runner.ps1").write_text(RUNNER, encoding="utf-8")
        (scratch / "cases.json").write_text(json.dumps(CASES), encoding="utf-8")
        process = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                                  str(scratch / "runner.ps1"), "-ModulePath", str(MODULE),
                                  "-CasesPath", str(scratch / "cases.json"), "-CaseRoot", str(scratch),
                                  "-RepoRoot", str(root)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        results = []
        for line in process.stdout.decode("utf-8", "replace").splitlines():
            fields = line.split("\t")
            if len(fields) == 4 and fields[0] == "CASE":
                results.append(fields[1:])
        check(len(results) >= len(CASES) + 8, "PowerShell answered every case (%d answers, exit %d): %s" % (
            len(results), process.returncode, process.stderr.decode("utf-8", "replace").strip()[:400]))
        for item, answer in zip(CASES, results):
            name, verdict, detail = answer
            if item["expected"] == "PASS":
                check(name == item["name"] and verdict == "PASS", "%s (%s)" % (item["name"], detail[:140]))
            else:
                check(name == item["name"] and verdict == "FAIL" and item["fragment"] in detail,
                      "%s fails: %s (%s)" % (item["name"], item["fragment"], detail[:140]))
        real = results[len(CASES):]
        passing = [r for r in real if r[0].endswith("passes the pin")]
        removed = [r for r in real if " without [" in r[0]]
        check(len(passing) == 8 and all(r[1] == "PASS" for r in passing),
              "the real pin holds for the core and Options TOC of all four clients (%d checked)" % len(passing))
        check(len(removed) >= 8 * 3 and all(r[1] == "FAIL" and "tools/classic-toc-identity.tsv pins it" in r[2] for r in removed),
              "removing any pinned line from any real TOC fails (%d removals checked)" % len(removed))
finally:
    remove_tree(scratch)

print()
if failures:
    print("gate manifest rules smoke: %d FAILED" % len(failures))
    for message in failures:
        print("  " + message)
    sys.exit(1)
print("gate manifest rules smoke: ok")
