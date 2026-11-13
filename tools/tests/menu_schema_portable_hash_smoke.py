"""Both native traversal orders must produce the same relative-POSIX source hash."""
import hashlib
import importlib.util
import tempfile
from pathlib import Path, PurePosixPath, PureWindowsPath
from unittest.mock import patch

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("coverage", root / "tools/menu_schema_coverage.py")
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)
with tempfile.TemporaryDirectory(prefix="schema-order-") as directory:
    fixture = Path(directory)
    for name in ("MidnightSimpleUnitFrames/A.lua", "MidnightSimpleUnitFrames/a/b.lua",
                 "MidnightSimpleUnitFrames_Options/Z.lua", ".github/check.lua",
                 "tools/menu_schema_coverage.py", "tools/menu_schema_project.lua", "tools/menu_schema_harness.lua",
                 "tools/menu_schema_capture.lua", "tools/search_catalog_harness.lua", "tools/search_static_format.py",
                 "tools/classic-client-matrix.tsv", "tools/load-graph.lock",
                 "tools/fixtures/a/provenance.lua", "tools/fixtures/b/provenance.lua"):
        path = fixture / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((name + "\r\n").encode())
    (fixture / "tools/menu_schema_harness.lua").write_bytes(b'loadfile("provenance.lua")\r\n')
    files = list(fixture.rglob("*"))
    files = [path for path in files if path.is_file()]
    windows = sorted(files, key=lambda p: PureWindowsPath(p.relative_to(fixture).as_posix()))
    posix = sorted(files, key=lambda p: PurePosixPath(p.relative_to(fixture).as_posix()))
    assert windows != posix, "fixture does not distinguish platform ordering"
    expected = hashlib.sha256()
    for path in sorted(files, key=lambda p: p.relative_to(fixture).as_posix()):
        expected.update(path.relative_to(fixture).as_posix().encode() + b"\0" + coverage.read(path).encode() + b"\0")
    hashes = []
    original_glob = Path.rglob
    for native in (PureWindowsPath, PurePosixPath):
        def platform_sort(paths, *, key=None):
            paths = sorted(paths, key=lambda p: native(p.relative_to(fixture).as_posix()))
            return sorted(paths, key=key) if key is not None else paths
        def platform_glob(path, pattern):
            found = list(original_glob(path, pattern))
            return iter(reversed(found) if native is PureWindowsPath else found)
        with patch.object(coverage, "sorted", platform_sort, create=True), patch.object(Path, "rglob", platform_glob):
            hashes.append(coverage.source_hash(fixture))
    assert hashes[0] == hashes[1] == expected.hexdigest().upper(), "platform-dependent source hash: " + repr(hashes)
print("PASS coverage hash: Windows/POSIX input order and independent digest agree")
