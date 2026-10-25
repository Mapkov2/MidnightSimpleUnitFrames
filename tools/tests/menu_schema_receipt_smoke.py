"""Compact schema evidence is source-bound and read without the full projection."""
import copy
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import menu_schema_coverage as coverage
import scorecard

coverage.source_hash = lambda root: 'A' * 64
index = {'sourceSha256': 'B' * 64, 'blobSha256': 'c' * 64, 'rowCount': 0, 'identities': []}
coverage.index_data = lambda root, name: (index, [])
control = {'controlId': 'width', 'schemaId': 'width', 'pageKey': 'uf_player', 'scope': 'player',
           'applyDomain': 'layout', 'kind': 'slider', 'schemaKind': 'slider', 'classification': 'setting',
           'setting': 'player.width', 'settingDeclarations': {'default': 'player.width'}}
client = {'allDeclarationsCaptured': True, 'controls': [control], 'initialControlIds': ['width'],
          'initialControls': [copy.deepcopy(control)]}
evidence = {'version': 2, 'sourceSha256': 'A' * 64,
            'clients': {flavor: copy.deepcopy(client) for flavor in ('Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever')},
            'indexes': {name: index for name in coverage.INDEXES}}
receipt = coverage.make_receipt(evidence, ROOT)
assert coverage.audit_receipt(receipt, ROOT) == (5, 5, []), 'valid receipt rejected'
assert coverage.audit_receipt([], ROOT)[2], 'malformed receipt passed'
for mutate in (
    lambda row: row.update(sourceSha256='D' * 64),
    lambda row: row.update(generatorVersion='outdated'),
    lambda row: row['clients'].pop('Forever'),
    lambda row: row['clients']['Mainline'].update(proven=0),
    lambda row: row['totals'].update(profileControls=6),
    lambda row: row.update(issueCount=1),
):
    broken = copy.deepcopy(receipt)
    mutate(broken)
    assert coverage.audit_receipt(broken, ROOT)[2], 'invalid receipt passed'
bad = copy.deepcopy(evidence)
bad['clients']['Mainline']['initialControls'][0]['observationIssues'] = {'unproven': True}
try:
    coverage.make_receipt(bad, ROOT)
except ValueError:
    pass
else:
    raise AssertionError('invalid projection produced a passing receipt')
with tempfile.TemporaryDirectory(prefix='schema-receipt-') as directory:
    root = Path(directory)
    (root / 'tools').mkdir()
    (root / 'tools/classic-client-matrix.tsv').write_bytes((ROOT / 'tools/classic-client-matrix.tsv').read_bytes())
    path = root / 'tools/menu_schema_coverage_receipt.json'
    path.write_text(json.dumps(receipt), encoding='utf-8')
    located = copy.deepcopy(evidence)
    located['clients']['Mainline']['controls'][0]['setter'] = '@' + ROOT.as_posix() + '/some/provider.lua:19'
    relocated = copy.deepcopy(evidence)
    relocated['clients']['Mainline']['controls'][0]['setter'] = '@' + root.as_posix() + '/some/provider.lua:19'
    assert coverage.make_receipt(located, ROOT) == coverage.make_receipt(relocated, root), 'receipt depends on checkout location'
    before = path.read_bytes()
    assert scorecard.menu_coverage(root) == (5, 5, [], 5, []), 'scorecard requires the large projection'
    assert path.read_bytes() == before, 'scorecard wrote evidence'
    coverage.source_hash = lambda root: 'E' * 64
    assert scorecard.menu_coverage(root)[4], 'stale source receipt passed scorecard'
print('schema receipt: projection-free read, five-client counts and stale/invalid mutations passed')
