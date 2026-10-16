"""Pinned native test execution, Lua 5.1 literals and the actual POSIX shell."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
from menu_section_auth import clean_env, git
from menu_section_capture import AREAS, PRODUCT, closure, sha


def lua_literal(value):
    parts = []
    for byte in str(value).encode("utf-8"):
        if byte in (34, 92):
            parts.append("\\" + chr(byte))
        elif byte < 32 or byte >= 127:
            parts.append("\\%03d" % byte)
        else:
            parts.append(chr(byte))
    return '"' + "".join(parts) + '"'


def bash_path():
    if os.name == "nt":
        found = shutil.which("git")
        roots = list(Path(found).resolve().parents)[:3] if found else []
        candidates = [p / "usr/bin/bash.exe" for p in roots]
        candidates.append(Path("C:/Program Files/Git/usr/bin/bash.exe"))
    else:
        found = shutil.which("bash")
        candidates = [Path(found)] if found else []
    for path in candidates:
        if path.is_file():
            native = path.resolve(strict=True)
            version = subprocess.run([str(native), "--version"], env=clean_env(), capture_output=True, text=True)
            probe = subprocess.run([str(native), "--noprofile", "--norc", "-c", "printf MSUF_NATIVE_BASH"],
                                   env=clean_env(), capture_output=True, text=True)
            assert version.returncode == 0 and version.stdout.startswith("GNU bash, version "), "actual GNU Bash required"
            assert probe.returncode == 0 and probe.stdout == "MSUF_NATIVE_BASH", "native Bash execution unavailable"
            return native
    raise AssertionError("actual POSIX Bash unavailable; Windows requires the Git-associated Bash, never a WSL launcher")


def proof_sources(root, entry):
    entries = ["tools/tests/menu_" + area + "_inventory_smoke.lua" for area in AREAS]
    entries += ["tools/tests/menu_section_capture.py", "tools/tests/menu_section_auth.py", "tools/tests/menu_core_world.lua",
                "tools/tests/menu_section_test_runtime.py", "tools/tests/menu_section_provenance_smoke.py",
                Path(entry).resolve().relative_to(root).as_posix()]
    paths, edges = closure(lambda p: (root / p).read_bytes(), entries)
    paths = set(paths) | set(git(root, "ls-files", "--", *PRODUCT).decode().splitlines())
    for name in ("menu-section-parent", "menu-section-parity", "menu-section-historical-observer"):
        paths.update(p.relative_to(root).as_posix() for p in (root / "tools/fixtures" / name).rglob("*") if p.is_file())
    return edges, {p: sha((root / p).read_bytes()) for p in sorted(paths)}
