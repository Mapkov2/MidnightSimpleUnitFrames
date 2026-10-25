"""Read-only verification of the immutable 6.503 rollback source.

Local preparation (never checks out or writes the production repository):
  python tools/tests/historical_6503_source.py --materialize-from <production>
The archive cache is ignored; CI supplies an actions/checkout of the same commit.
"""
import argparse
import hashlib
import io
import os
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile

COMMIT = "d8af82416ec07e8755c89e35c83bcd2320868a10"
TREE = "ded900e72626f1ad37b4915f5dc05e92c8e5f401"
ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "dist/historical/6.503-d8af824"


def object_id(kind, payload):
    return hashlib.sha1(kind.encode() + b" " + str(len(payload)).encode() + b"\0" + payload).digest()


def tree_id(root):
    """Rebuild Git's tree from file bytes; no index, git metadata or trusted stamp.

    This pinned tree has only 100644 files and directories (no executable modes).
    A CI checkout's .git metadata is excluded only at the root. Unexpected files,
    missing files, symlinks and byte changes all change the resulting tree ID.
    """
    def walk(directory):
        entries = []
        for path in directory.iterdir():
            if directory == root and path.name == ".git":
                continue
            name = path.name.encode("utf-8")
            if path.is_symlink():
                mode, oid, order = b"120000", object_id("blob", os.readlink(path).encode()), name
            elif path.is_dir():
                mode, oid, order = b"40000", walk(path), name + b"/"
            elif path.is_file():
                mode, oid, order = b"100644", object_id("blob", path.read_bytes()), name
            else:
                raise ValueError("unsupported historical source entry: " + str(path))
            entries.append((order, mode + b" " + name + b"\0" + oid))
        return object_id("tree", b"".join(value for _, value in sorted(entries)))
    return walk(root).hex()


def verify(source):
    if not source.is_dir():
        raise ValueError("historical 6.503 source missing: " + str(source)
                         + "; materialize the pinned archive or set MSUF_HISTORICAL_6503_DIR")
    actual = tree_id(source)
    if actual != TREE:
        raise ValueError("historical 6.503 tree mismatch: expected " + TREE + ", got " + actual + " at " + str(source))
    if (source / "VERSION").read_bytes().strip() != b"6.503":
        raise ValueError("historical 6.503 VERSION mismatch")
    return actual


def materialize(production, destination):
    def git(*args):
        return subprocess.check_output(["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf", "-C", str(production), *args])
    actual = git("rev-parse", COMMIT + "^{tree}").decode().strip()
    if actual != TREE:
        raise ValueError("historical commit tree differs from pin: " + actual)
    if destination.exists():
        verify(destination)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    archive = git("archive", "--format=tar", COMMIT)
    with tempfile.TemporaryDirectory(prefix="6.503-", dir=destination.parent) as temporary:
        staged = Path(temporary) / "source"
        staged.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(staged, filter="data")
        verify(staged)
        staged.rename(destination)
    for path in destination.rglob("*"):
        if path.is_file():
            path.chmod(stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path,
                        default=Path(os.environ.get("MSUF_HISTORICAL_6503_DIR", str(CACHE))))
    parser.add_argument("--materialize-from", type=Path)
    args = parser.parse_args()
    try:
        if args.materialize_from:
            materialize(args.materialize_from, args.source)
        verify(args.source)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("FAIL " + str(error))
        return 1
    print("PASS historical 6.503 " + COMMIT + " tree " + TREE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
