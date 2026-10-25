"""Check the single executable release inventory against tracked and pending tests."""
import argparse
import json
from pathlib import Path
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]
PHASES = {'fast', 'generated', 'profiles', 'runtime', 'menu', 'apply', 'namespace', 'group preview', 'edit', 'setters'}
def test_path(name):
    p = Path(name)
    return p.suffix in {'.lua', '.py', '.ps1'} and (name.startswith(('tools/tests/', 'tools/MenuTest/', '.github/scripts/tests/'))
        or re.search(r'(?:^test[_-]|[_-](?:smoke|test|contract|budget)(?:[._-]|$))', p.stem) is not None)

def discover(root):
    tracked = subprocess.check_output(['git', '-c', 'core.excludesFile=', '-C', str(root), 'ls-files'], text=True)
    names = {name for name in tracked.splitlines() if test_path(name)}
    # Pending tests are checked too; no staging/git writes are needed by a lane.
    for directory in ('tools/tests', 'tools/MenuTest', '.github/scripts/tests'):
        names.update(p.relative_to(root).as_posix() for p in (root / directory).rglob('*')
                     if p.is_file() and p.suffix in {'.lua', '.py'} and '__pycache__' not in p.parts)
    return names

def check(root, inventory=None, tests=None):
    data = inventory if inventory is not None else json.loads((root / 'tools/release-test-inventory.json').read_text())
    problems, run = [], set()
    if data.get('version') != 1: problems.append('invalid inventory version')
    for row in data.get('runs', []):
        path = row.get('test', '')
        if not test_path(path) or not (root / path).is_file(): problems.append('missing/invalid executable test: ' + path)
        if row.get('phase') not in PHASES: problems.append('unknown execution phase: ' + path)
        if any(c not in {'Mainline','Vanilla','TBC','Mists','Forever'} for c in row.get('clients', [])):
            problems.append('unknown client: ' + path)
        run.add(path)
    excluded = data.get('excluded', {})
    for path, reason in excluded.items():
        if not isinstance(reason, str) or len(reason.strip()) < 20: problems.append('exclusion needs a specific reason: ' + path)
        if not (root / path).is_file(): problems.append('stale excluded helper: ' + path)
        if path in run: problems.append('executed test also excluded: ' + path)
    names = discover(root) if tests is None else tests
    for path in sorted(names - run - excluded.keys()): problems.append('test neither executed nor explicitly excluded: ' + path)
    for path in sorted((run | excluded.keys()) - names): problems.append('inventory path outside test discovery: ' + path)
    return problems, len(run), len(excluded)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true', required=True)
    args = parser.parse_args()
    problems, run, excluded = check(args.root)
    for problem in problems: print('FAIL ' + problem)
    print(f'Test inventory: {run} executed scripts, {excluded} excluded helpers/contracts, {len(problems)} failures')
    return bool(problems)
if __name__ == '__main__': raise SystemExit(main())
