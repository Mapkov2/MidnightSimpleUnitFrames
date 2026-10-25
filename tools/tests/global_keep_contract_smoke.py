"""Pinned consumers and exact freshness fail closed without a Suite checkout."""
import copy
import json
from pathlib import Path
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gen_global_keep as g

contract = g.consumer_contract(g.ROOT / 'tools/global_keep_consumers.json')
assert contract['names'] and contract['commit'] and contract['snapshotSha256']
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    path = root / g.BOOTSTRAP
    path.parent.mkdir(parents=True)
    block = g.generated_block({'ContractName': {'Suite reader'}})
    path.write_text(block, encoding='utf-8')
    g.check_policy(root, block)
    path.write_text(block.replace('ContractName = true', 'ContractName = false'), encoding='utf-8')
    try:
        g.check_policy(root, block)
    except ValueError:
        pass
    else:
        raise AssertionError('stale generated policy accepted')
    for key, value in [('commit', 'main'), ('snapshotSha256', ''), ('names', ['duplicate', 'duplicate'])]:
        broken = copy.deepcopy(contract)
        broken[key] = value
        p = root / 'contract.json'
        p.write_text(json.dumps(broken), encoding='utf-8')
        try:
            g.consumer_contract(p)
        except ValueError:
            pass
        else:
            raise AssertionError('invalid pinned contract accepted: ' + key)
assert 'DEFAULT_SUITE_REPO' not in Path(g.__file__).read_text(encoding='utf-8')
print('PASS pinned Suite consumers; stale policy and malformed contract rejected')
