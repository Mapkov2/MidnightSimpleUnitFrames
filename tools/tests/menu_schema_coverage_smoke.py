"""Actual-core evidence must remain checked when IDs also exist headlessly."""
import copy
import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('coverage', root / 'tools/menu_schema_coverage.py')
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)
coverage.source_hash = lambda root: 'source'
index = {'sourceSha256': 'index', 'blobSha256': 'blob', 'rowCount': 0, 'identities': []}
coverage.index_data = lambda root, name: (index, [])
control = {'controlId': 'width', 'schemaId': 'width', 'pageKey': 'uf_player', 'scope': 'player',
           'applyDomain': 'layout', 'kind': 'slider', 'schemaKind': 'slider', 'classification': 'setting',
           'setting': 'player.width', 'settingDeclarations': {'default': 'player.width'}}
client = {'allDeclarationsCaptured': True, 'controls': [control], 'initialControlIds': ['width'],
          'initialControls': [copy.deepcopy(control)]}
evidence = {'version': 2, 'sourceSha256': 'source',
            'clients': {flavor: copy.deepcopy(client) for flavor in ('Mainline', 'Vanilla', 'TBC', 'Mists', 'Forever')},
            'indexes': {name: index for name in coverage.INDEXES}}
assert coverage.audit(evidence, root)[2] == [], 'valid shared-ID declaration failed'
evidence['clients']['Mainline']['initialControls'][0]['observationIssues'] = {'missing schema in a live build': True}
issues = coverage.audit(evidence, root)[2]
assert any('missing schema in a live build' in issue for issue in issues), 'headless row hid an actual-core defect'
print('schema coverage: actual-core shared-ID defect rejected; valid declaration accepted')

# Disk page boundaries must reproduce the in-memory accumulator exactly.
import json
import tempfile
import sys
with tempfile.TemporaryDirectory(prefix='schema-fold-') as directory:
    path = Path(directory) / 'rows.ndjson'
    first = {'controlId': 'width', 'label': 'original', 'scope': 'first', '_schemaAssigned': True,
             'ephemeralReason': 'old', 'schemaSettingPath': 'old',
             'resolvedPaths': {'player.width': True}, 'observationIssues': {'first': True},
             'settingDeclarations': {'one': 'player.width'}}
    second = {'controlId': 'width', 'label': 'later', 'scope': 'second', '_schemaAssigned': True,
              'resolvedPaths': {'target.width': True}, 'observationIssues': {'second': True},
              'settingDeclarations': {'two': 'target.width'}}
    path.write_text(json.dumps(first) + '\n' + json.dumps(second) + '\n', encoding='utf-8')
    row = coverage.load_stream(path)['width']
    assert row['label'] == 'original' and row['scope'] == 'second'
    assert not any(key in row for key in ('ephemeralReason', 'schemaSettingPath', '_schemaAssigned')), 'stream failed to clear absent fields'
    for key in ('resolvedPaths', 'observationIssues', 'settingDeclarations'):
        assert row[key] == dict(first[key], **second[key]), key + ': stream lost union evidence'
    sys.path.insert(0, str(root / 'tools'))
    import scorecard
    original = scorecard.ratchet.strip_source
    scan = scorecard.ratchet.SCAN
    calls = []
    class CountingScan:
        def finditer(self, text):
            calls.append(text)
            return scan.finditer(text)
    scorecard.ratchet.SCAN = CountingScan()
    try:
        with scorecard.run_cache():
            path.write_text('local value = 1\n', encoding='utf-8')
            a = scorecard.keep.read(path)
            scorecard.ratchet.strip_source(a)
            scorecard.ratchet.strip_source(scorecard.keep.read(path))
            scorecard.ledger.strip_and_mask(a)
            assert len(calls) == 1, 'unchanged source was rescanned'
            path.write_text('local value = 2\n', encoding='utf-8')
            b = scorecard.keep.read(path)
            scorecard.ratchet.strip_source(b)
            assert a != b and len(calls) == 2, 'cache reused changed source'
        assert scorecard.ratchet.strip_source is original, 'cache patches leaked outside run'
        path.write_bytes(b'\xff')
        with scorecard.run_cache():
            for read in (scorecard.keep.read, scorecard.schema_coverage.read):
                try:
                    read(path)
                except UnicodeDecodeError:
                    pass
                else:
                    raise AssertionError('strict source reader accepted malformed UTF-8')
            assert scorecard.ledger.read_text(path) == '\ufffd', 'ledger replacement semantics changed'
    finally:
        scorecard.ratchet.SCAN = scan
    for text in ("-- comment\nlocal x = 'function'", '--[[long\ncomment]]\nreturn [=[text\nbody]=]',
                 '--[[unterminated\nlocal y = 2', 'local text = "escaped\\\"value"'):
        expected_source = scorecard.ratchet.strip_source(text)
        expected_exports = scorecard.ledger.strip_and_mask(text)
        with scorecard.run_cache():
            assert scorecard.ratchet.strip_source(text) == expected_source
            assert scorecard.ledger.strip_and_mask(text) == expected_exports
print('schema coverage: page fold is exact; source cache reuses facts and invalidates by content')

import re
for text in ('a.lua foo-bar.lua path/file.test.lua', '?foo.bar.lua ?foo.lua', '.hidden.lua --dash.lua',
             'x.lua_suffix require("helper") .lua .a.lua'):
    expected = re.findall(r'\b[A-Za-z0-9_][A-Za-z0-9_.-]*\.lua\b', text)
    assert coverage.lua_references(text) == expected, 'helper dependency scanner changed token boundaries'

# Reviewed preview counts cannot survive omitted files, source drift or nonzero residue.
proof_path = root / "tools/preview_render_census.json"
proof = json.loads(proof_path.read_text(encoding="utf-8-sig"))
assert scorecard.preview_render_census(root)["remaining_code"] == 0
with tempfile.TemporaryDirectory(prefix="preview-census-") as directory:
    fixture = Path(directory)
    (fixture / "tools").mkdir()
    for row in proof["files"]:
        path = fixture / coverage.MENU / row["file"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((root / coverage.MENU / row["file"]).read_bytes())
        for support in row.get("support_sources", []):
            path = fixture / coverage.MENU / support["file"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((root / coverage.MENU / support["file"]).read_bytes())
    census = fixture / "tools/preview_render_census.json"
    def WriteProof(value):
        census.write_text(json.dumps(value), encoding="utf-8")
    WriteProof(proof)
    assert scorecard.preview_render_census(fixture)["before_code"] == proof["before_code"]
    def Reject():
        try:
            scorecard.preview_render_census(fixture)
        except ValueError:
            return
        raise AssertionError("preview scorecard accepted stale/incomplete evidence")
    changed = fixture / coverage.MENU / proof["files"][0]["file"]
    original_bytes = changed.read_bytes()
    changed.write_bytes(original_bytes + b"\nlocal unrelated = true\n")
    Reject()
    changed.write_bytes(original_bytes)
    for mutate in (lambda value: value["files"].pop(),
                   lambda value: value["files"][0].update(remaining_code=1),
                   lambda value: value.update(before_physical=0)):
        invalid = copy.deepcopy(proof)
        mutate(invalid)
        WriteProof(invalid)
        Reject()
print("preview census: current review accepted; source drift, omitted scope, residue and invalid totals rejected")
