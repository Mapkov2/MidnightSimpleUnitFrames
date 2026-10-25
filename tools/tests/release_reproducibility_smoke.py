"""Exercise the CI downloader with corrupted PowerShell bytes before extraction."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parents[2]
workflow = (root / '.github/workflows/release-check.yml').read_text(encoding='utf-8')
code = workflow.split("python - <<'PY'", 1)[1].split('          PY', 1)[0]
code = '\n'.join(line[10:] for line in code.splitlines())
pins = json.loads((root / 'tools/check-pins.json').read_text())
assert pins['powershellLinuxX64Sha256'] == '6f6015203c47806c5cc444c19d8ed019695e610fbd948154264bf9ca8e157561'
with tempfile.TemporaryDirectory() as tmp:
    def download(url, destination):
        Path(destination).write_bytes(b'lua fixture' if 'lua.org' in url else b'corrupt PowerShell')
    real = hashlib.sha256
    class LuaHash:
        def hexdigest(self): return pins['luaSourceSha256']
    def checksum(data): return LuaHash() if data == b'lua fixture' else real(data)
    with patch.dict(os.environ, {'RUNNER_TEMP': tmp}), patch('urllib.request.urlretrieve', download), patch('hashlib.sha256', checksum):
        try:
            exec(compile(code, '<CI downloader>', 'exec'), {})
        except AssertionError:
            pass
        else:
            raise AssertionError('CI accepted corrupted PowerShell archive')
print('PASS CI rejects corrupted PowerShell before extraction')

# Exercise real worker serialization and fail-closed completion receipts without
# running the aggregate runner or occupying a Lua lane.
import shutil
import subprocess
import sys
def run_powershell(arguments, **options):
    powershell = os.environ.get('MSUF_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell')
    assert powershell, 'PowerShell required: set MSUF_POWERSHELL to the active host path'
    return subprocess.run([powershell, *arguments], **options)


# The release runner passes its own host, which may be absent from PATH or
# differ from the first installed shell. Exercise the actual child launcher.
for name in ('powershell', 'pwsh'):
    inherited = str(Path(tempfile.gettempdir()) / 'shell with spaces' / name)
    for discovered in (None, str(Path(tempfile.gettempdir()) / 'different host' / name)):
        with patch.dict(os.environ, {'MSUF_POWERSHELL': inherited}), \
                patch.object(shutil, 'which', return_value=discovered) as lookup, \
                patch.object(subprocess, 'run') as launch:
            run_powershell(['-NoProfile', '-File', 'probe.ps1'], check=True)
            launch.assert_called_once_with([inherited, '-NoProfile', '-File', 'probe.ps1'], check=True)
            lookup.assert_not_called()
print('PASS inherited PowerShell host wins over missing/different PATH hosts')
script = r'''param($root, $python, $runner)
$ErrorActionPreference = 'Stop'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
foreach ($symbol in @('Start-ContractWorker', 'Get-MenuControlCounts', 'Order-ContractRuns')) {
    $function = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $symbol
    }, $true)
    if (-not $function) { throw "runner helper missing: $symbol" }
    Invoke-Expression $function.Extent.Text
}
$ordered = @(Order-ContractRuns @(
    @{ Id = 4; Phase = 'profiles'; Label = 'fixture' }, @{ Id = 9; Phase = 'namespace'; Label = 'flip' },
    @{ Id = 2; Phase = 'setter parity'; Label = 'second' }, @{ Id = 0; Phase = 'setter parity'; Label = 'first' }
))
if ((($ordered | ForEach-Object { $_.Id }) -join ',') -ne '0,2,9,4') { throw ("long-job order dropped or reordered inventory IDs: " + (($ordered | ForEach-Object { $_.Id }) -join ",")) }
$originalRoot = $root
$root = Join-Path $PSScriptRoot 'counts'
[void][IO.Directory]::CreateDirectory((Join-Path $root 'tools'))
$projection = Join-Path $root 'tools/menu_schema_coverage.json'
try {
    [IO.File]::WriteAllText($projection, '{"clients":{"Mainline":{"initialControlIds":["a","b"]},"Vanilla":{"initialControlIds":["v"]}}}')
    $script:MenuControlCounts = $null
    $one, $two = (Get-MenuControlCounts), (Get-MenuControlCounts)
    if ($one.Mainline -ne 2 -or $one.Vanilla -ne 1 -or -not [object]::ReferenceEquals($one, $two)) {
        throw 'projection counts changed or were decoded more than once'
    }
    foreach ($invalid in @('[]', '"string"', 'null')) {
        [IO.File]::WriteAllText($projection, ('{"clients":{"Mainline":{"initialControlIds":' + $invalid + '}}}'))
        $script:MenuControlCounts = $null
        $rejected = $false
        try { Get-MenuControlCounts | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'invalid/empty initial control IDs accepted' }
    }
} finally { $root = $originalRoot; $script:MenuControlCounts = $null }
$Slot, $Owner = '', 'worker-probe'
$good = "print('PASS schema setters Mainline: fixture'); print('PASS compound/temporary write contracts Mainline: fixture')"
$runs = @(
    @{ Id = 0; Phase = 'setter parity'; Label = 'complete'; Client = 'Mainline'; Exe = $python; Args = @('-c', $good) },
    @{ Id = 1; Phase = 'setter parity'; Label = 'missing writes'; Client = 'Mainline'; Exe = $python;
        Args = @('-c', "print('PASS schema setters Mainline: fixture')") },
    @{ Id = 2; Phase = 'runtime'; Label = 'nonzero'; Exe = $python; Args = @('-c', 'raise SystemExit(3)') }
)
$worker = Start-ContractWorker 'probe' $runs
try {
    $result = @($worker.Job | Wait-Job | Receive-Job | Where-Object { $_.PSObject.Properties['Receipts'] })
    if ($result.Count -ne 1 -or $result[0].Name -ne 'probe') { throw 'worker lost its identity' }
    $items = @($result[0].Receipts)
    if ($items.Count -ne 3 -or -not $items[0].Ok -or $items[1].Ok -or $items[2].Ok -or $items[2].Code -ne 3) {
        throw 'worker accepted incomplete success text, lost an exit code or omitted a run'
    }
    for ($i = 0; $i -lt 3; $i++) { if ($items[$i].Id -ne $i) { throw 'worker reordered its inventory' } }
} finally { $worker.Job | Remove-Job -Force }
$queue = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($queue, '0')
$workers = @()
try {
    $workers += (Start-ContractWorker 'queue-a' $runs $queue)
    $workers += (Start-ContractWorker 'queue-b' $runs $queue)
    $items = @()
    foreach ($entry in $workers) {
        $result = @($entry.Job | Wait-Job | Receive-Job | Where-Object { $_.PSObject.Properties['Receipts'] })
        if ($result.Count -ne 1 -or $result[0].Name -ne $entry.Name) { throw 'queued worker lost identity' }
        $items += @($result[0].Receipts)
    }
    $ids = @($items | ForEach-Object { $_.Id } | Sort-Object)
    if ($items.Count -ne 3 -or ($ids -join ',') -ne '0,1,2' -or [IO.File]::ReadAllText($queue) -ne '3') {
        throw 'shared queue lost, duplicated or skipped a contract'
    }
} finally {
    foreach ($entry in $workers) { $entry.Job | Remove-Job -Force }
    Remove-Item -LiteralPath $queue -Force
}
'''
with tempfile.TemporaryDirectory() as tmp:
    probe = Path(tmp) / 'worker-probe.ps1'
    probe.write_text(script, encoding='utf-8')
    result = run_powershell(['-NoProfile', '-File', str(probe), str(root), sys.executable,
                             str(root / 'tools/release-check.ps1')], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
print('PASS bounded contract worker preserves all runs and rejects incomplete/failed receipts')
