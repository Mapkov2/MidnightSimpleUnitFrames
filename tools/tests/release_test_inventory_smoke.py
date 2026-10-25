"""Inventory probes: new tracked tests, fake exclusions and missing files fail."""
import copy
from pathlib import Path
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_test_inventory as inventory
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / 'tools/tests').mkdir(parents=True)
    one, two = 'tools/tests/one.lua', 'tools/tests/two.lua'
    for name in (one, two): (root / name).write_text('return true')
    data = {'version':1, 'runs':[{'test':one,'phase':'runtime'}], 'excluded':{two:'Shared fixture, loaded by the primary runtime test.'}}
    assert not inventory.check(root, data, {one,two})[0]
    assert inventory.check(root, data, {one,two,'tools/tests/new_tracked.lua'})[0], 'unregistered tracked test accepted'
    outside = '.github/quality/outside_smoke.lua'
    assert inventory.test_path(outside) and inventory.check(root, data, {one,two,outside})[0], 'out-of-directory tracked test escaped'
    assert inventory.test_path('.github/scripts/external_contract.lua'), 'out-of-directory contract escaped'
    bad = copy.deepcopy(data)
    bad['excluded'][two] = ''
    assert inventory.check(root, bad, {one,two})[0], 'unreasoned exclusion accepted'
    bad = copy.deepcopy(data)
    bad['excluded'][one] = 'Cannot both execute and exclude the same test.'
    assert inventory.check(root, bad, {one,two})[0], 'overlapping inventory accepted'
    (root / one).unlink()
    assert inventory.check(root, data, {one,two})[0], 'missing executable accepted'
print('PASS test inventory rejects omissions, invalid exclusions and missing files')
