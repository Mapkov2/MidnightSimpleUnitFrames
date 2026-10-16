"""Independent Git-object and interpreter boundary for section receipt replay."""
import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile

REVIEWED = "e5568415e8d164581e2df9f913520afa87d6c7b1"
PARENT = "096d5e0e0ffc2c386189932cecb946435db09bc3"

def clean_env(extra=None):
    env = {k: v for k, v in os.environ.items() if not contaminated(k)}
    if extra:
        env.update(extra)
    return env

def contaminated(key):
    name = key.upper()
    return name in ("LUA_INIT", "LUA_PATH", "LUA_CPATH") or name.startswith("PYTHON") or name.startswith("GIT_")

def git(root, *args):
    run = subprocess.run(["git", "-C", str(root), *args], env=clean_env(), capture_output=True)
    assert run.returncode == 0, "authentic Git history unavailable: " + " ".join(args[:2]) + ": " + run.stderr.decode(errors="replace")
    return run.stdout

def archive(root, ref, paths):
    resolved = git(root, "rev-parse", "--verify", ref + "^{commit}").decode().strip()
    assert resolved == ref, "source reference must be an exact commit"
    contents = {}
    with tarfile.open(fileobj=io.BytesIO(git(root, "archive", ref, "--", *paths))) as tree:
        for entry in tree:
            if entry.isfile():
                assert not entry.name.startswith("/") and ".." not in Path(entry.name).parts, "unsafe Git archive path"
                contents[entry.name] = tree.extractfile(entry).read()
    assert contents, "empty authentic Git archive"
    return contents

def materialize(root, ref, target, paths):
    contents = archive(root, ref, paths)
    target.mkdir(parents=True, exist_ok=False)
    for name, data in contents.items():
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    git(target, "init", "--quiet")
    common = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").decode().strip())
    (target / ".git/objects/info/alternates").write_bytes(((common / "objects").as_posix() + "\n").encode())
    (target / ".git/HEAD").write_bytes((ref + "\n").encode())
    git(target, "config", "core.autocrlf", "true")
    git(target, "read-tree", ref)
    return contents

def interpreters(lua):
    lua = Path(lua).resolve(strict=True)
    run = subprocess.run([str(lua), "-e", "io.write(_VERSION)"], env=clean_env(), capture_output=True, text=True)
    assert run.returncode == 0 and run.stdout == "Lua 5.1", "authentic replay requires Lua 5.1"
    return {"python": {"path": sys.executable, "version": sys.version, "isolated": bool(sys.flags.isolated),
                       "sha256": hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest()},
            "lua": {"path": str(lua), "version": run.stdout,
                    "sha256": hashlib.sha256(lua.read_bytes()).hexdigest()},
            "removed_startup_variables": sorted(k for k in os.environ if contaminated(k))}
