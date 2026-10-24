"""Exercise real gate listings, tier coverage, executable identity and timing output."""
from __future__ import annotations

import csv
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
gate = root / "tools/test-classic-prototype.ps1"
shell = shutil.which("pwsh") or shutil.which("powershell")
assert shell, "PowerShell is required"


def table(name):
    with (root / "tools" / name).open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def key(parts):
    command = Path(parts[0].replace("\\", "/")).name.removesuffix(".exe")
    arguments = [str(Path(part).resolve()) if Path(part).is_absolute() else part for part in parts[1:]]
    return (command, *(part.replace("\\", "/") for part in arguments))


def reference(skip=(), only=""):
    """Independent manifest expansion: compare coverage, not scheduler order."""
    clients = table("classic-client-matrix.tsv")
    out = set()
    for row in table("classic-gate-smokes.tsv"):
        if (row.get("Tier") or "push") in skip:
            continue
        matrix = row["Matrix"]
        if matrix == "-":
            contexts = [{}]
        elif matrix == "tokenclients":
            contexts = [dict(flavor=c["Suffix"], clientToken=c["ClientToken"]) for c in clients if c["ClientToken"]]
        else:
            match = re.fullmatch(r"(clients|classics)(?:\+([A-Za-z0-9,]+))?(\*codecs)?", matrix)
            assert match, matrix
            flavors = [c["Suffix"] for c in clients if match[1] == "clients" or c["IsClassic"] == "true"]
            flavors += match[2].split(",") if match[2] else []
            contexts = [dict(flavor=f) for f in flavors]
            if match[3]:
                contexts = [dict(c, codec=mode) for c in contexts for mode in ("raise", "nil")]
        for context in contexts:
            def expand(value):
                value = value.replace("{root/}", root.as_posix()).replace("{root}", str(root))
                for name, item in context.items():
                    value = value.replace("{" + name + "}", item)
                return re.sub(r"\{p/:([^}]+)\}", lambda m: (root / m[1]).as_posix(), value)
            if only and not (re.search(only, row["Smoke"]) or re.search(only, expand(row["Label"]))):
                continue
            parts = ["python" if row["Runner"] == "python" else "lua"]
            if row["Runner"] == "lua+driver":
                parts.append(str(root / ".github/scripts/auras3_test_driver.lua"))
            parts.append(str(root / row["Smoke"]))
            parts.extend(expand(arg) for arg in row["Arguments"].split())
            out.add(key(parts))
    return out


def listing(extra, timing_path):
    command = [shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(gate),
               "-SelfContained", "-ListSmokes", "-TimingsOut", str(timing_path), *extra]
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not timing_path.exists(), "Listing mode must not write timing observations"
    rows = [line.split(" | ", 1)[1] for line in result.stdout.splitlines() if line.startswith("LISTSMOKE ")]
    commands = [key(row.split(" :: ", 1)[0].split(" | ")) for row in rows]
    assert len(commands) == len(set(commands)), "Duplicate executable invocations remain in the selected gate plan"
    return set(commands)


checks = root / ".checks"
checks.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="gate-plan-contract-", dir=checks) as work_name:
    work = Path(work_name).resolve()
    assert work.is_relative_to(checks.resolve())
    for skip in ((), ("nightly",), ("push",)):
        args = ["-SkipTier", skip[0]] if skip else []
        actual = listing(args, work / "listing.tsv")
        expected = reference(skip)
        assert actual == expected, (skip, "Selected tier coverage differs", list(expected - actual)[:3], list(actual - expected)[:3])
        print("gate plan coverage:", "+".join(skip) or "all", len(actual))
    label = "Forever Midnight appearance preset smoke failed"
    assert listing(["-Only", label], work / "listing.tsv") == reference(only=label), "Label filtering must precede deduplication"

    child = work / "probe_smoke.py"
    counter = work / "calls.txt"
    child.write_text("import pathlib, sys\np=pathlib.Path(sys.argv[1])\nwith p.open('a') as f: f.write(sys.argv[2]+'\\n')\nsys.exit(int(sys.argv[3]))\n", encoding="utf-8")
    driver = work / "exercise.ps1"
    driver.write_text(r'''
param($Gate, $Root, $Python, $Child, $Counter, $TimingsOut)
$ErrorActionPreference = "Stop"
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Gate, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Gate parse error: $errors" }
foreach ($name in @("Select-UniqueGateSmokePlan", "Invoke-GateSmoke", "Invoke-GateSmokePhase", "Complete-GateRun")) {
    $function = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name}, $false))
    if ($function.Count -ne 1) { throw "Missing actual gate function: $name" }
    . ([scriptblock]::Create($function[0].Extent.Text))
}
$assignment = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$gateSmokeScript'}, $false))
$gateSmokeScript = & ([scriptblock]::Create($assignment[0].Right.Extent.Text))
function Item($Command, [string[]]$Arguments, $Label) {
    [pscustomobject]@{ Command=$Command; Arguments=$Arguments; Label=$Label; Name=$Label }
}
$special = @(
    (Item 'Lua' @('same', 'a b', 'c') 'first'),
    (Item 'Lua' @('same', 'a b', 'c') 'second'),
    (Item 'lua' @('same', 'a b', 'c') 'command case'),
    (Item 'Lua' @('same', 'a', 'b c') 'argument boundary'),
    (Item 'Lua' @('same', 'A b', 'c') 'argument case'),
    (Item 'Lua' @('other/root', 'a b', 'c') 'different source')
)
$unique = @(Select-UniqueGateSmokePlan -Plan $special)
if ($unique.Count -ne 5 -or $unique[0].Label -notmatch 'first' -or $unique[0].Label -notmatch 'second') {
    throw "Executable identity or diagnostic labels lost"
}
if (@(Select-UniqueGateSmokePlan -Plan @()).Count -ne 0) { throw "Empty plan changed" }
$root = $Root; $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$lua = $true; $ListSmokes = $false; $FailFast = $false; $RequireNoSkippedSteps = $false
$gateSmokeJobs = 1; $smokeFilePattern = '(?:_smoke\.(?:lua|py)|_contract\.lua)$'
$ranSmokes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$deferredSmokes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$gateSmokeFailures = [Collections.Generic.List[object]]::new()
$gateSmokeTimings = [Collections.Generic.List[object]]::new()
$skippedSteps = [Collections.Generic.List[string]]::new()
$good = Item $Python @($Child, $Counter, 'good', '0') 'good'
$again = Item $Python @($Child, $Counter, 'good', '0') 'also good'
$bad = Item $Python @($Child, $Counter, 'bad', '7') 'bad'
$smokePlan = @(Select-UniqueGateSmokePlan -Plan @($good, $again, $bad))
Invoke-GateSmokePhase
$calls = @(Get-Content -LiteralPath $Counter)
if (($calls -join ',') -cne 'good,bad') { throw "Actual process launch count/arguments changed: $calls" }
if ($ranSmokes.Count -ne 1 -or $gateSmokeFailures.Count -ne 1 -or $gateSmokeFailures[0].ExitCode -ne 7) {
    throw "Inventory or failing invocation was lost"
}
$timings = @(Import-Csv -LiteralPath $TimingsOut -Delimiter "`t")
if ($timings.Count -ne 1 -or $timings[0].Name -cne 'good' -or [double]$timings[0].Seconds -le 0) {
    throw "Only successful measured timings may become scheduling observations"
}
Push-Location -LiteralPath $Root
$failed = $false
try { Complete-GateRun } catch {
    if ($_.Exception.Message -notlike 'Classic gate smokes failed:*') { throw }
    $failed = $true
}
if (-not $failed) { throw "Real gate failure was swallowed" }
Write-Host "gate process/timing behavior: ok"
''', encoding="utf-8")
    result = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(driver),
                             str(gate), str(root), sys.executable, str(child), str(counter), str(work / "nested/timings.tsv")],
                            cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "gate process/timing behavior: ok" in result.stdout
print("gate plan contract smoke: ok")
