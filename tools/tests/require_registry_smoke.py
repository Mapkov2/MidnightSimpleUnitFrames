"""Deferred Require readers must not disappear behind unexecuted commands."""
import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--luac', required=True)
parser.add_argument('--lua', required=True)
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flip', ROOT / 'tools/flip_check.py')
flip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flip)
with tempfile.TemporaryDirectory(prefix='require-registry-') as directory:
    path = Path(directory) / 'reader.lua'
    path.write_text('local MSUF = ...\nlocal Require = MSUF.Require\n'
                    'local function Command()\n return Require("MSUF_Deferred", "command")()\nend\n', encoding='utf-8')
    readers = flip.scan_lua(path, 'reader.lua', args.luac)[1]
    assert any(row[2:4] == ('MSUF_Deferred', 'Require/deferred') for row in readers), 'deferred reader was not inventoried'
    paired = Path(directory) / 'paired.lua'
    paired.write_text('local MSUF = ...\nlocal Optional, Need = MSUF.Optional, MSUF.Require\n'
                      'return function() return Need("MSUF_Paired", "later")() end\n', encoding='utf-8')
    paired_reads = flip.scan_lua(paired, 'paired.lua', args.luac)[1]
    assert any(row[2:4] == ('MSUF_Paired', 'Require/deferred') for row in paired_reads), 'paired Require alias escaped discovery'
    phases = {'core': ['reader.lua'], 'Options': []}
    providers = {'core': {'MSUF_Deferred': {'type': 'function', 'file': 'provider.lua', 'phase': 'core'}}, 'Options': {}}
    with contextlib.redirect_stdout(io.StringIO()):
        assert flip.audit_required('Mainline', phases, providers, {'reader.lua': (set(), readers)})[0] == 0
        providers['core'].clear()
        assert flip.audit_required('Mainline', phases, providers, {'reader.lua': (set(), readers)})[0] > 0, 'removed deferred provider passed'
        providers['core']['MSUF_Deferred'] = {'type': 'boolean', 'file': 'provider.lua', 'phase': 'core'}
        assert flip.audit_required('Mainline', phases, providers, {'reader.lua': (set(), readers)})[0] > 0, 'wrong provider type passed'
        providers['core']['MSUF_Deferred']['type'] = 'table'
        assert flip.audit_required('Mainline', phases, providers, {'reader.lua': (set(), readers)})[0] > 0, 'table accepted for a deferred call'
        providers['core'].clear()
        providers['Options']['MSUF_Deferred'] = {'type': 'function', 'file': 'options.lua', 'phase': 'Options'}
        assert flip.audit_required('Mainline', phases, providers, {'reader.lua': (set(), readers)})[0] == 0, 'deferred LOD provider failed'
        path.write_text('local MSUF = ...\nlocal f = MSUF.Require("MSUF_Deferred", "boot")\n', encoding='utf-8')
        boot = flip.scan_lua(path, 'reader.lua', args.luac)
        assert flip.audit_required('Mainline', phases, providers, {'reader.lua': boot})[0] > 0, 'Options provider satisfied boot dependency'
# Cache correctness is part of the contract: equal bytes share one source
# parse/compiler invocation; edits (even equal-size edits) invalidate both.
with tempfile.TemporaryDirectory(prefix='require-cache-') as directory:
    path = Path(directory) / 'cached.lua'
    twin = Path(directory) / 'twin.lua'
    path.write_text('local MSUF = ...\nreturn MSUF.Require("MSUF_CacheA", "cache")()\n', encoding='utf-8')
    twin.write_bytes(path.read_bytes())
    calls = {'parse': 0, 'compile': 0}
    original_tokens, original_run = flip.tokens, flip.subprocess.run
    def counted_tokens(source):
        calls['parse'] += 1
        return original_tokens(source)
    def counted_run(*positional, **keywords):
        calls['compile'] += 1
        return original_run(*positional, **keywords)
    flip.tokens, flip.subprocess.run = counted_tokens, counted_run
    try:
        first = flip.scan_lua(path, 'cached.lua', args.luac)
        for _ in range(10):
            assert flip.scan_lua(path, 'cached.lua', args.luac) == first
            assert flip.scan_lua(twin, 'twin.lua', args.luac)[1][0][0] == 'twin.lua'
        assert calls == {'parse': 1, 'compile': 1}, calls
        path.write_text(path.read_text().replace('MSUF_CacheA', 'MSUF_CacheB'), encoding='utf-8')
        changed = flip.scan_lua(path, 'cached.lua', args.luac)
        assert changed[1][0][2] == 'MSUF_CacheB' and calls == {'parse': 2, 'compile': 2}, (changed, calls)
        # Batched listings must produce exactly the standalone reader inventory,
        # including function spans used for deferred/load readiness decisions.
        for file in (path, twin):
            flip.source_facts(file)['compiled'].clear()
        flip.prime_compiler([path, twin], args.luac)
        assert flip.scan_lua(path, 'cached.lua', args.luac) == changed
        assert flip.scan_lua(twin, 'cached.lua', args.luac) == first
        assert calls == {'parse': 2, 'compile': 3}, calls
        path.write_text('function broken(', encoding='utf-8')
        try:
            flip.scan_lua(path, 'cached.lua', args.luac)
        except RuntimeError:
            pass
        else:
            raise AssertionError('cached result hid a compiler failure')
    finally:
        flip.tokens, flip.subprocess.run = original_tokens, original_run
recovery = 'MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Recovery.lua'
readers = flip.scan_lua(ROOT / recovery, recovery, args.luac)[1]
required = {row[2] for row in readers if row[3].startswith('Require/')}
assert {'MSUF_GetCharKey', 'MSUF_EnsureOptionsLoaded', 'MSUF_ShowCopyLink', 'MSUF_NormalizeProfileDefaults'} <= required
# Observe the real graph with its provider removed; the deferred command itself
# never runs. Existing raw-global checks alone used to miss this exact hole.
for removed in (None, 'MSUF_ShowCopyLink'):
    phases, exports, capabilities, registry = flip.observe(ROOT, args.lua, 'Mainline', removed)
    scanned = {path: (set(), []) for paths in phases.values() for path in paths}
    scanned[recovery] = flip.scan_lua(ROOT / recovery, recovery, args.luac)
    with contextlib.redirect_stdout(io.StringIO()):
        errors, rows = flip.audit_required('Mainline', phases, registry, scanned)
    assert (errors > 0) == bool(removed), 'real deferred provider deletion was not detected'
try:
    flip.observe(ROOT, args.lua, 'Mainline', 'before-login:MSUF_InitProfiles')
except RuntimeError as error:
    assert 'required-provider failure' in str(error), str(error)
else:
    raise AssertionError('isolated core-login Require borrowed a later provider')
trailing = subprocess.run([args.lua, str(ROOT / 'tools/tests/flip_check_exports.lua'), str(ROOT) + '/', 'Mainline'],
                          capture_output=True, text=True, check=True)
assert 'FILE\tcore\tMidnightSimpleUnitFrames/' in trailing.stdout, 'trailing root damaged provider file paths'
assert 'FILE\tcore\tidnightSimpleUnitFrames/' not in trailing.stdout
print('Require registry: recovery readers inventoried; deferred removal, wrong type and wrong phase rejected')
