"""Compile the shipped union and check load order on each real client graph."""
import argparse
import re
import subprocess
from pathlib import Path
import generate_module_manifest as manifest


def graphs(root):
    documents = {p.relative_to(root).as_posix(): p.read_text(encoding='utf-8-sig')
                 for addon in manifest.ADDONS[:2] for p in (root / addon).rglob('*')
                 if p.suffix in {'.toc', '.xml'}}
    for client in manifest.client_matrix(root):
        phases = []
        for addon in manifest.ADDONS[:2]:
            phases.append(manifest.walk(documents, client, addon)[0])
        yield client[0], phases


def compile_files(root, luac, files):
    """Parse every chunk, batching process starts; failures retain per-file diagnostics."""
    failed = 0
    for start in range(0, len(files), 32):
        paths = [str(root / path) for path in files[start:start + 32]]
        run = subprocess.run([luac, '-p', *paths], capture_output=True, text=True)
        if not run.returncode:
            continue
        if len(paths) == 1:
            failed += 1
            print(run.stderr.strip())
            continue
        bad = 0
        for path in paths:
            single = subprocess.run([luac, '-p', path], capture_output=True, text=True)
            if single.returncode:
                bad += 1
                print(single.stderr.strip())
        # A failing batch must never turn green just because a tool failure is
        # transient or cannot be reproduced with a single file.
        if not bad:
            bad = 1
            print('compiler batch failed without a per-file reproduction: ' + run.stderr.strip())
        failed += bad
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--luac', required=True)
    args = parser.parse_args()
    # The manifest generator already provides the canonical graph/condition parser.
    inventory = list(graphs(args.root))
    files = sorted({p for _, phases in inventory for phase in phases for p in phase})
    failed = compile_files(args.root, args.luac, files)
    print(f'compile: {len(files)} shipped files, {failed} with syntax errors')
    # Actual boot additionally executes Require in TOC order, including factories.
    for flavor, phases in inventory:
        print(f'{flavor}: {len(phases[0])} core + {len(phases[1])} Options files')
    return int(failed != 0)


if __name__ == '__main__':
    raise SystemExit(main())
