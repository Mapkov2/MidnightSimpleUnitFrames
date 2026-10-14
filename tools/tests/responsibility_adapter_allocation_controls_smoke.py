"""Keep both fresh heap samples sensitive to real transient allocations."""
from pathlib import Path
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get('MSUF_LUA') or shutil.which('lua')
assert lua, 'Lua 5.1 required (MSUF_LUA)'
source = (root / 'tools/tests/responsibility_route_heap_smoke.lua').read_text()
assert 'debug.sethook' not in source
source = source.replace('responsibility_route_paths.lua', 'responsibility_adapter_paths.lua')
source = source.replace('responsibility_route_costs.tsv', 'responsibility_adapter_costs.tsv')
source = source.replace('local errors = {}', 'local errors = {}\nlocal sequence = 0')
needle = 'for i = 1, case.iterations do case.run() end'
assert source.count(needle) == 1
controls = {
    'production': '',
    'tables': 'local temporary = {}; temporary.value = i',
    'closures': 'local temporary = function() return i end; assert(temporary() == i)',
    'transient-strings': 'sequence = sequence + 1; local temporary = string.format("allocation/%d/%d", sequence, i)',
}


def run(job):
    client, name = job
    body = 'for i = 1, case.iterations do case.run()'
    if controls[name]:
        body += '\nif case.name == "name-adapter:resolver" then ' + controls[name] + ' end'
    body += '\nend'
    result = subprocess.run([lua, '-', str(root), client, str(root)],
                            input=source.replace(needle, body), text=True, capture_output=True)
    samples = re.findall(client + r'\s+name-adapter:resolver\s+10\s+heap\s+([\d.]+)\s+([\d.]+)', result.stdout)
    assert len(samples) == 1, (client, name, result.stdout, result.stderr)
    first, second = map(float, samples[0])
    if name == 'production':
        assert result.returncode == 0 and first == second == 0, (client, name, samples, result.stderr)
    else:
        assert result.returncode != 0 and first > 0 and second > 0, (client, name, samples, result.stderr)
        assert 'name-adapter:resolver:' in result.stderr, result.stderr
    return f'{client} {name}: heap samples {first}/{second} KiB; native exit {result.returncode}'


tasks = [(client, name) for client in ['Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever'] for name in controls]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for receipt in pool.map(run, tasks):
        print(receipt, flush=True)
print('PASS adapter heap controls: all clients; both samples detect tables, closures and transient strings')
