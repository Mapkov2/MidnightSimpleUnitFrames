"""The frozen legacy corpus is complete and byte-identical after newline normalization."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
corpus = root / "tools/fixtures/preview-render-oracle"
metadata = json.loads((corpus / "provenance.json").read_text(encoding="utf-8"))
expected = json.loads((corpus / "fixture-sha256.json").read_text(encoding="utf-8"))
actual_paths = {p.relative_to(corpus).as_posix() for p in corpus.glob("*/*.lua")}
assert set(expected) == actual_paths, "frozen fixture inventory changed"
assert metadata["hash_newlines"] == "LF" and len(metadata["base"]) == 40, "invalid capture provenance"
assert set(metadata["clients"]) == {"Mainline", "Forever", "Vanilla", "TBC", "Mists"}, "incomplete client capture"
for relative, digest in expected.items():
    observed = hashlib.sha256((corpus / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    assert observed == digest, f"frozen fixture bytes changed: {relative}; explicit output review required"
for flavor in metadata["clients"]:
    assert any(p.startswith(flavor + "/unit-") for p in expected), "unit preview corpus missing"
    for surface in ("group", "castbar", "classpower"):
        assert any(p.startswith(flavor + "/" + surface + "-") for p in expected), f"{flavor}/{surface} corpus missing"
print(f"preview_oracle_corpus_smoke: ok ({len(expected)} frozen per-preview fixtures, base {metadata['base'][:8]})")
