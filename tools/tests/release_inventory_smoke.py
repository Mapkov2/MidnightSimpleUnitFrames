"""Inventory regression: real discovery, fresh checkout, missing and stale rows."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('inventory', ROOT / 'tools/release_test_inventory.py')
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)

with tempfile.TemporaryDirectory(prefix='release-inventory-') as directory:
    root = Path(directory)
    subprocess.run(['git', 'init', '-q', str(root)], check=True)
    for name in ('tools/release_test_inventory.py', 'tools/tests/example_smoke.py', 'tools/tests/helper.lua'):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('# fixture\n', encoding='utf-8')
    subprocess.run(['git', '-c', 'core.excludesFile=', '-C', str(root), 'add', '.'], check=True)
    data = {'version': 1, 'runs': [{'test': 'tools/tests/example_smoke.py', 'phase': 'generated'}],
            'excluded': {'tools/release_test_inventory.py': 'Executed explicitly by release-check generated lists.',
                         'tools/tests/helper.lua': 'Shared fixture without an executable test entry point.'}}
    assert not inventory.check(root, data)[0], 'valid fresh checkout inventory failed'
    del data['excluded']['tools/release_test_inventory.py']
    assert any('release_test_inventory.py' in p for p in inventory.check(root, data)[0]), 'checker escaped discovery'
    data['excluded']['tools/release_test_inventory.py'] = 'Executed explicitly by release-check generated lists.'
    pending = root / 'tools/tests/pending_smoke.ps1'
    pending.write_text('exit 0\n', encoding='utf-8')
    assert any('pending_smoke.ps1' in p for p in inventory.check(root, data)[0]), 'pending PowerShell test escaped discovery'
    pending.unlink()
    data['runs'][0]['phase'] = 'typo'
    assert any('unknown execution phase' in p for p in inventory.check(root, data)[0])
    data['runs'][0]['phase'] = 'generated'
    (root / 'tools/tests/helper.lua').unlink()
    assert any('stale excluded helper' in p for p in inventory.check(root, data)[0])

data = json.loads((ROOT / 'tools/release-test-inventory.json').read_text())
checker = 'tools/release_test_inventory.py'
assert checker in data['excluded'], 'release inventory checker lacks an explicit classification'
assert any(row['test'] == 'tools/tests/release_inventory_smoke.py' for row in data['runs'])
clients = {'Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever'}
for oracle in ('profile_corpus_golden_smoke.lua', 'profile_defaults_oracle_smoke.lua'):
    rows = [row for row in data['runs'] if row['test'] == 'tools/tests/' + oracle]
    assert len(rows) == 1 and rows[0]['phase'] == 'profiles' and set(rows[0]['clients']) == clients, oracle + ' missing five-client release oracle'
print('release inventory: fresh checkout and unregistered/stale/invalid mutations passed')

# Execute the real queue/worker functions against isolated leaf commands. A
# successful exit without the fast-check completion receipt must still fail.
with tempfile.TemporaryDirectory(prefix='release-scheduling-') as directory:
    root = Path(directory)
    (root / 'tools').mkdir()
    (root / 'tools/check-common.ps1').write_bytes((ROOT / 'tools/check-common.ps1').read_bytes())
    (root / 'leaf.ps1').write_text(r"""param($Phase, $Bad, $Events)
$lock = New-Object Threading.Mutex($false, ('MSUF-Scheduling-Probe-' + [IO.Path]::GetFileName($Events)))
function Note($action) {
    [void]$lock.WaitOne()
    try { [IO.File]::AppendAllText($Events, "$action $PID`n") } finally { $lock.ReleaseMutex() }
}
Note 'start'
try {
    Start-Sleep -Milliseconds 700
    if ($Phase -eq 'setter parity') {
        Write-Output 'PASS schema setters Mainline: complete'
        Write-Output 'PASS compound/temporary write contracts Mainline: complete'
    } elseif ($Bad -eq 'no') { Write-Output 'fast-check: 0 failed, 1 s, probe' }
} finally { Note 'finish'; $lock.Dispose() }
exit 0
""", encoding='utf-8')
    probe = r"""param($Repository, $Fixture)
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'tools/release-check.ps1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw $errors[0] }
foreach ($name in @('Order-ContractRuns', 'Start-ContractWorker')) {
    $node = $ast.Find({ param($item) $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name }, $true)
    if (-not $node) { throw "Missing worker function $name" }
    Invoke-Expression $node.Extent.Text
}
$root = $Fixture; $Slot = ''; $Owner = 'scheduling-probe'
$PowerShell = (Get-Process -Id $PID).Path
$queue = Join-Path $Fixture 'probe.queue'; $events = Join-Path $Fixture 'events.log'
[IO.File]::WriteAllText($queue, '0')
$runs = @()
foreach ($id in 0..7) {
    $phase = if ($id -lt 5) { 'setter parity' } elseif ($id -eq 6) { 'namespace' } else { 'fast-check' }
    $bad = if ($id -eq 7) { 'yes' } else { 'no' }
    $runs += @{ Id = $id; Phase = $phase; Client = 'Mainline'; Label = "probe-$id"; Exe = $PowerShell;
        Args = @('-NoProfile', '-File', (Join-Path $Fixture 'leaf.ps1'), $phase, $bad, $events) }
}
$runs = @(Order-ContractRuns $runs)
if (($runs[0..5].Id -join ',') -ne '0,1,2,3,4,5') { throw 'Fast-check did not share the first six slots' }
$workers = @(); $receipts = @()
try {
    foreach ($number in 1..6) { $workers += Start-ContractWorker "probe-$number" $runs $queue }
    foreach ($worker in $workers) {
        $result = @($worker.Job | Wait-Job | Receive-Job | Where-Object { $_.PSObject.Properties['Receipts'] })
        if ($result.Count -ne 1) { throw 'Incomplete scheduling receipt' }
        $receipts += @($result[0].Receipts)
    }
    $receipts | ConvertTo-Json -Depth 5 -Compress | Write-Output
} finally {
    foreach ($worker in $workers) { $worker.Job | Remove-Job -Force -ErrorAction SilentlyContinue }
}
"""
    (root / 'probe.ps1').write_text(probe, encoding='utf-8')
    result = subprocess.run(['powershell', '-NoProfile', '-File', str(root / 'probe.ps1'), str(ROOT), str(root)],
                            capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    rows = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('[{')))
    assert sorted(row['Id'] for row in rows) == list(range(8)), rows
    assert all(row['Ok'] == (row['Id'] != 7) for row in rows), rows
    live, peak = set(), 0
    for line in (root / 'events.log').read_text().splitlines():
        action, pid = line.split()
        if action == 'start':
            assert pid not in live
            live.add(pid)
            peak = max(peak, len(live))
        else:
            live.remove(pid)
    assert not live and 2 <= peak <= 6, (live, peak)
print('release scheduling: shared six-worker queue; exact inventory; false fast-check completion rejected')
