"""Compute the retained check closure; deletion needs a release receipt and owner authority.

No git writes. Paths under tools are considered for pruning, except operational
artwork/maintenance tools, generated projection data and the module manifest.
Literal references, local Python/Lua imports and dynamic fixture directories are
conservative dependency edges. Every budget smoke is an explicit protected root.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ENTRY_POINTS = (
    'tools/fast-check.ps1', 'tools/release-check.ps1',
    '.github/scripts/search_static_index_project.lua',
    'tools/defaults_schema_generate.lua', 'tools/generate_module_manifest.py',
    'tools/scorecard.py', 'tools/quality_ratchet.py',
    'tools/module-manifest.json', 'tools/prune_frozen_tests.py',
)
OPERATIONAL = (
    'tools/artwork/', 'tools/build-classic-menu-art.py', 'tools/build-portrait-contour.py',
    'tools/generate_aura_icon_skins.py', 'tools/update-addon-changelog.ps1',
    'tools/release-check.md',
)
RETIRED = {'tools/run-classic-gate.ps1', 'tools/test-classic-prototype.ps1',
           'tools/classic-gate-smokes.tsv', 'tools/classic-gate-weights.tsv',
           '.github/workflows/classic-full-gate.yml'}


def closure(root, frozen_dirty=(), start_files=None):
    files = {p.relative_to(root).as_posix(): p for directory in ('tools', '.github', 'MidnightSimpleUnitFrames', 'MidnightSimpleUnitFrames_Options')
             for p in (root / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts}
    by_name = {}
    for name in files:
        by_name.setdefault(Path(name).name, set()).add(name)
    roots = set(ENTRY_POINTS)
    roots.update(name for name in files if name.startswith('tools/menu_schema_'))
    roots.update(name for name in files if name.startswith('tools/tests/') and 'budget' in Path(name).name)
    roots.update(name for name in files if name.startswith('.github/workflows/') and name not in RETIRED)
    roots.update(name for name in files if any(name == pattern or pattern.endswith('/') and name.startswith(pattern) for pattern in OPERATIONAL))
    # A parallel lane's open work is never deletion material, including new tests.
    dirty = subprocess.check_output(['git', '-c', 'core.excludesFile=', '-C', str(root), 'diff', '--name-only', '--', 'tools'], text=True)
    roots.update(name for name in dirty.splitlines() if name not in RETIRED and name not in frozen_dirty)
    tracked = tracked_files(root)
    roots.update(name for name in files if name.startswith('tools/') and name not in tracked)
    if start_files is not None:
        # New files and edits made by another lane after this run began are roots.
        roots.update(name for name, path in files.items() if name.startswith('tools/')
                     and (name not in start_files or hashlib.sha256(path.read_bytes()).hexdigest()
                          != start_files[name]['sha256']))
    reasons = {name: 'entry/protected' for name in roots if name in files}
    pending = list(reasons)
    while pending:
        current = pending.pop()
        path = files[current]
        # Reviewed row lists and binary/golden data do not execute referenced tests.
        if path.suffix not in {'.lua', '.py', '.ps1', '.psm1', '.yml', '.xml', '.toc', '.json'}:
            continue
        text = path.read_text(encoding='utf-8-sig', errors='replace')
        dependencies = {name for token in re.findall(r'\b[A-Za-z0-9_][A-Za-z0-9_.-]*\.[A-Za-z0-9_-]+\b', text)
                        for name in by_name.get(token, ())}
        if path.suffix == '.py':
            tree = ast.parse(text)
            imports = [alias.name for node in ast.walk(tree) if isinstance(node, ast.Import) for alias in node.names]
            imports += [node.module for node in ast.walk(tree) if isinstance(node, ast.ImportFrom) and node.module]
            dependencies.update(name for module in imports for name in by_name.get(module.replace('.', '/') + '.py', ()))
        for module in re.findall(r'require\(["\']([\w_]+)["\']\)', text):
            dependencies.update(by_name.get(module + '.lua', ()))
        for fixture in re.findall(r'tools/fixtures/([\w-]+)', text):
            dependencies.update(name for name in files if name.startswith('tools/fixtures/' + fixture + '/'))
        for dependency in dependencies - reasons.keys():
            # Mentions of the retired runner are historical documentation, never
            # a reason to resurrect its inventory. Any active call is checked below.
            if dependency in RETIRED:
                if current != 'tools/prune_frozen_tests.py':
                    raise ValueError('kept entry still references retired inventory: ' + current + ' -> ' + dependency)
                continue
            reasons[dependency] = current
            pending.append(dependency)
    candidates = sorted(name for name in files if (name.startswith('tools/') or name == '.github/workflows/classic-full-gate.yml')
                        and name not in reasons and name != 'tools/module-manifest.json')
    return files, reasons, candidates


def tracked_files(root):
    return set(subprocess.check_output(['git', '-c', 'core.excludesFile=', '-C', str(root), 'ls-files', '--', 'tools'], text=True).splitlines())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--delete', action='store_true')
    parser.add_argument('--frozen-dirty', type=Path,
                        help='owner-designated frozen test edits; budgets/dependencies remain protected')
    parser.add_argument('--release-log', type=Path)
    parser.add_argument('--owner-approved', action='store_true',
                        help='explicit owner instruction permits pruning after a completed failing release run')
    parser.add_argument('--start-snapshot', type=Path, help='file hashes captured before parallel lane work')
    args = parser.parse_args()
    root = args.root.resolve()
    frozen_dirty = set(args.frozen_dirty.read_text(encoding='utf-8-sig').splitlines()) if args.frozen_dirty else set()
    tracked = tracked_files(root)
    if any(not name.startswith('tools/tests/') or name not in tracked for name in frozen_dirty):
        parser.error('frozen-dirty entries must be tracked tests in tools/tests')
    start_files = json.loads(args.start_snapshot.read_text(encoding='utf-8'))['files'] if args.start_snapshot else None
    if args.delete and start_files is None:
        parser.error('delete requires a start snapshot to protect concurrent lane work')
    files, reasons, candidates = closure(root, frozen_dirty, start_files)
    report = {'kept': reasons, 'delete': {name: hashlib.sha256(files[name].read_bytes()).hexdigest() for name in candidates}}
    args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'closure: {len(reasons)} retained, {len(candidates)} deletion candidates')
    if args.delete:
        receipt = args.release_log.read_text(encoding='utf-8-sig') if args.release_log else ''
        complete = re.search(r'^release-check: \d+ failed; .*contract slots;.*elapsed;', receipt, re.M)
        contracts = ('generated lists', 'schema projection', 'scorecard', 'fast-check', 'profiles',
                     'runtime robustness', 'menu', 'apply path', 'namespace', 'group preview', 'Edit Mode', 'final freshness')
        if not complete or any(not re.search(r'^(?:PASS|FAIL) ' + re.escape(name) + (r': [1-9]\d* runs,' if name != 'fast-check' else r': [0-9.,]+ s'), receipt, re.M) for name in contracts):
            parser.error('delete requires a completed compact release-check receipt for every retained contract')
        if not args.owner_approved and not re.search(r'^release-check: 0 failed;', receipt, re.M):
            parser.error('delete requires a successful compact release-check log or explicit owner instruction')
        revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
        if 'commit ' + revision + ';' not in receipt.splitlines()[0]:
            parser.error('release receipt does not match the current commit')
        from menu_schema_coverage import source_hash
        if not args.owner_approved and 'projection sourceSha256: ' + source_hash(root) not in receipt:
            parser.error('release receipt does not match the current source projection')
        report['receiptSha256'] = hashlib.sha256(args.release_log.read_bytes()).hexdigest()
        report['ownerApproved'] = args.owner_approved
        args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        for name in candidates:
            target = files[name].resolve()
            if not target.is_relative_to(root) or name == 'tools/module-manifest.json':
                raise ValueError('unsafe deletion: ' + name)
        for name in candidates:
            if hashlib.sha256(files[name].read_bytes()).hexdigest() != report['delete'][name]:
                raise ValueError('candidate changed during deletion preparation: ' + name)
        for name in candidates:
            # Recheck immediately before each unlink, after the complete preflight.
            if hashlib.sha256(files[name].read_bytes()).hexdigest() != report['delete'][name]:
                raise ValueError('candidate changed during deletion: ' + name)
            files[name].unlink()
        args.report.with_name('E4-deleted.txt').write_text('\n'.join(candidates) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
