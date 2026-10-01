"""The packager's staged load-graph proof reads every TOC line the way WoW does.

build_classic_release_package.ps1 proves, before it zips, that every Lua and
XML file a staged TOC reaches exists in the stage (Assert-MsufStagedLoadGraph,
ClassicGate.Common.psm1). Its own walker used to strip only the last [...]
condition of a TOC line, so the alias catalog lines, which carry a locale and a
game-type condition, were neither reached nor reported missing.

1. Fixture stages, run through the real module function: a complete stage
   passes with the exact reach count; a missing file named on a line with two
   conditions, a missing XML child and a missing plain entry fail by name; a
   reference inside an XML comment is no load; a tooling-named file nothing
   loads fails.
2. The real core Mainline TOC: Get-MsufLoadGraph -RequireFiles reaches every
   entry the TOC lists, the stacked-condition alias catalog lines included.
3. The packager calls the shared function and keeps no walker of its own.

Usage: python tools/tests/staged_load_graph_smoke.py <repository root>
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
MODULE = root / ".github" / "scripts" / "ClassicGate.Common.psm1"
PACKAGER = root / ".github" / "scripts" / "build_classic_release_package.ps1"
CORE_TOC = root / "MidnightSimpleUnitFrames" / "MidnightSimpleUnitFrames_Mainline.toc"

failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def write(base, relative, text):
    target = base / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def remove_tree(path):
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


STAGE_FILES = {
    "Core/Core_Mainline.toc": (
        "## Interface: 120100\n"
        "## Title: Core\n"
        "# Init.lua listed in a comment is no load\n"
        "Init.lua\n"
        "Data\\Alias_enUS.lua [AllowLoadTextLocale enUS, enGB] [ExcludeLoadGameType camelot]\n"
        "Manifest.xml\n"),
    "Core/Init.lua": "-- init\n",
    "Core/Data/Alias_enUS.lua": "-- alias data\n",
    "Core/Manifest.xml": (
        "<Ui>\n"
        "  <Script file=\"A.lua\"/>\n"
        "  <!-- <Script file=\"Gone.lua\"/> -->\n"
        "  <Include file=\"Sub\\Inner.xml\"/>\n"
        "</Ui>\n"),
    "Core/A.lua": "-- a\n",
    "Core/Sub/Inner.xml": "<Ui>\n  <Script file=\"B.lua\"/>\n</Ui>\n",
    "Core/Sub/B.lua": "-- b\n",
    "Core/Unloaded.lua": "-- payload nothing loads; an ordinary name ships\n",
    "Options/Options_Mainline.toc": "## Interface: 120100\n## LoadOnDemand: 1\nPage.lua\n",
    "Options/Page.lua": "-- page\n",
}
# Init, Alias_enUS, Manifest, A, Inner, B, Page.
COMPLETE_REACH = 7

CASES = (
    # name, files to delete, files to add, expected pass, fragment the failure must name
    ("complete", (), {}, True, ""),
    ("missing-stacked-conditions", ("Core/Data/Alias_enUS.lua",), {}, False, "Alias_enUS.lua"),
    ("missing-xml-child", ("Core/Sub/B.lua",), {}, False, "B.lua"),
    ("missing-plain-entry", ("Core/Init.lua",), {}, False, "Init.lua"),
    ("unreached-tooling", (), {"Core/Thing_smoke.lua": "-- stray\n"}, False, "Thing_smoke.lua"),
)

RUNNER = r"""
param([string]$ModulePath, [string]$CasesPath, [string]$CoreToc)
$ErrorActionPreference = "Stop"
Import-Module $ModulePath -Force
foreach ($line in [IO.File]::ReadAllLines($CasesPath)) {
    $name, $stage = $line.Split([char]9)
    try {
        $graph = Assert-MsufStagedLoadGraph -StageRoot $stage
        [Console]::Out.WriteLine("CASE`t$name`tPASS`t$($graph.Tocs)`t$($graph.Reached)")
    } catch {
        [Console]::Out.WriteLine("CASE`t$name`tFAIL`t" + ($_.Exception.Message -replace '\s+', ' '))
    }
}
foreach ($path in (Get-MsufLoadGraph -Path $CoreToc -Duplicates Skip -RequireFiles).AllPaths) {
    [Console]::Out.WriteLine("REACHED`t" + $path)
}
"""


def run_powershell(scratch, names):
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if shell is None:
        check(False, "PowerShell (pwsh or powershell) is on PATH: the packager's own module is checked here")
        return {}, set()
    runner = scratch / "runner.ps1"
    runner.write_text(RUNNER, encoding="utf-8")
    listing = scratch / "cases.tsv"
    listing.write_text("".join("%s\t%s\n" % (name, scratch / name) for name in names), encoding="utf-8")
    process = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                              str(runner), "-ModulePath", str(MODULE), "-CasesPath", str(listing),
                              "-CoreToc", str(CORE_TOC)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    verdicts, reached = {}, set()
    for line in process.stdout.decode("utf-8", "replace").splitlines():
        fields = line.split("\t")
        if fields[0] == "CASE" and len(fields) >= 3:
            verdicts[fields[1]] = fields[2:]
        elif fields[0] == "REACHED" and len(fields) == 2:
            reached.add(os.path.normcase(os.path.normpath(fields[1].replace("\\", "/"))))
    if len(verdicts) != len(names) or not reached:
        check(False, "PowerShell answered every fixture and walked the core TOC (exit %d): %s" % (
            process.returncode, process.stderr.decode("utf-8", "replace").strip()[:600]))
    return verdicts, reached


print("staged load graph fixtures (Assert-MsufStagedLoadGraph)")
scratch = Path(tempfile.mkdtemp(prefix="msuf-staged-graph-smoke-")).resolve()
try:
    for name, deleted, added, _, _ in CASES:
        stage = scratch / name
        for relative, text in STAGE_FILES.items():
            if relative not in deleted:
                write(stage, relative, text)
        for relative, text in added.items():
            write(stage, relative, text)
    verdicts, reached = run_powershell(scratch, [case[0] for case in CASES])
    for name, _, _, expected, fragment in CASES:
        verdict = verdicts.get(name)
        if verdict is None:
            continue
        if expected:
            check(verdict[0] == "PASS" and verdict[1:] == ["2", str(COMPLETE_REACH)],
                  "%s: passes, 2 TOCs reach exactly %d Lua/XML files (got %s)" % (name, COMPLETE_REACH, verdict))
        else:
            check(verdict[0] == "FAIL" and fragment in " ".join(verdict[1:]),
                  "%s: fails and names %s (got %s)" % (name, fragment, verdict))
finally:
    remove_tree(scratch)

print("the real core Mainline TOC")
listed = []
for line in CORE_TOC.read_text(encoding="utf-8").splitlines():
    entry = line.strip()
    if not entry or entry.startswith("#"):
        continue
    while entry.endswith("]") and "[" in entry:
        entry = entry[:entry.rindex("[")].rstrip()
    listed.append(entry)
stacked = [line for line in CORE_TOC.read_text(encoding="utf-8").splitlines()
           if line.count("[") >= 2 and not line.startswith("#")]
check(len(stacked) >= 10, "the core Mainline TOC still carries its stacked-condition alias catalog lines (%d)" % len(stacked))
unreached = [entry for entry in listed
             if os.path.normcase(os.path.normpath(str(CORE_TOC.parent / entry.replace("\\", "/")))) not in reached]
check(reached and not unreached, "the shared walker reaches every entry the core Mainline TOC lists%s" % (
    "" if not unreached else ": missing " + ", ".join(unreached[:5])))

print("the packager")
packager = PACKAGER.read_text(encoding="utf-8")
check("Assert-MsufStagedLoadGraph -StageRoot" in packager,
      "build_classic_release_package.ps1 proves the stage with the shared Assert-MsufStagedLoadGraph")
check("-replace '\\s*\\[[^\\]]*\\]\\s*$'" not in packager and "<(?:Script|Include)" not in packager,
      "build_classic_release_package.ps1 keeps no TOC or XML walker of its own")

print()
if failures:
    print("staged load graph smoke: %d FAILED" % len(failures))
    for message in failures:
        print("  " + message)
    sys.exit(1)
print("staged load graph smoke: ok")
