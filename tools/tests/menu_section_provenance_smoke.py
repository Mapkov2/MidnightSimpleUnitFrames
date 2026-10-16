"""Receipt provenance and source inventory must remain tied to authentic old replay."""
import os
import subprocess
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import PARENT, REVIEWED, archive, clean_env, git, materialize, interpreters
from menu_section_capture import AREAS, BASE, CLIENTS, ORIGINAL, SUPPORT, PRODUCT, closure, source_support, validate_source, digest, manifest_sha, sha


# Immutable reviewed evidence identities, independent of mutable receipt metadata.
HISTORICAL_CORPUS_MANIFEST = "329b435c1ba7c3396ca12534b50c752647ca4eb6d73828d2f81ea87433726e11"
HISTORICAL_OBSERVER_MANIFEST = "46034bd8255d8f5ef130ba2e46ba95c8618b79fa9adb50700d27130f03068d94"
PARENT_RECEIPTS_MANIFEST = "2bd9246a71268bde5f158653b9494b5f570f62964179a4b0afcb2cf677169513"
HISTORICAL_CAPTURE_IDENTITY = "2bcecf9d87332703fd9151b02278816197eed09d0440bc8991c93caf8f114548"


def historical_observer(root, corpus, output=None):
    metadata = json.loads((corpus / "provenance.json").read_text(encoding="utf-8"))
    actual = {p.relative_to(corpus).as_posix(): sha(p.read_bytes()) for p in corpus.rglob("*") if p.is_file()}
    assert manifest_sha(actual) == HISTORICAL_CORPUS_MANIFEST, "historical evidence differs from immutable anchor manifest"
    observer = root / "tools/fixtures/menu-section-historical-observer"
    identity = json.loads((observer / "identity.json").read_text(encoding="utf-8"))
    assert identity["historical_observer_ref"] == REVIEWED, "historical observer identity changed"
    assert identity["hash_newlines"] == "LF", "historical observer normalization changed"
    paths, edges = closure(lambda p: (observer / (p + ".fixture")).read_bytes(),
        ["tools/tests/menu_" + area + "_inventory_smoke.lua" for area in AREAS] + ["tools/tests/menu_section_capture.py"])
    files = {p: sha((observer / (p + ".fixture")).read_bytes()) for p in paths}
    assert manifest_sha(files) == identity["observer_manifest_sha256"] == HISTORICAL_OBSERVER_MANIFEST, "historical observer differs from independent immutable identity"
    assert files == identity["files_sha256"] == metadata["harness_sha256"], "historical observer bytes differ"
    assert paths == identity["inputs"] == metadata["harness_inputs"], "historical observer closure incomplete"
    assert edges == identity["edges"] == metadata["harness_edges"], "historical observer edges changed"
    assert {p.relative_to(observer).as_posix() for p in observer.rglob("*") if p.is_file()} == {p + ".fixture" for p in paths} | {"identity.json"}, "untracked historical observer input"
    for path, value in identity["git_blob_sha1"].items():
        content = (observer / (path + ".fixture")).read_bytes().replace(b"\r\n", b"\n")
        import hashlib
        blob = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
        assert blob == value, "historical Git blob identity differs: " + path
    assert set(identity["git_blob_sha1"]) == set(paths), "historical Git blob identity closure incomplete"
    if output is not None:
        output.mkdir(parents=True, exist_ok=False)
        for path in paths:
            target = output / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((observer / (path + ".fixture")).read_bytes())
        return output
    return observer

def check(corpus, observer=None):
    metadata = json.loads((corpus / "provenance.json").read_text(encoding="utf-8"))
    provenance = (corpus / "provenance.lua").read_text(encoding="utf-8")
    assert metadata["base"] == BASE and f'base = "{BASE}"' in provenance, "incorrect original-source base"
    assert metadata["clients"] == CLIENTS and metadata["areas"] == AREAS, "incomplete original replay matrix"
    assert metadata["hash_newlines"] == "LF", "unsupported capture hash normalization"
    for key, field in (("source_sha256", "sourceManifest"), ("fixture_sha256", "fixtureManifest")):
        value = manifest_sha(metadata[key])
        assert metadata[key.replace("_sha256", "_manifest_sha256")] == value, "invalid provenance manifest"
        assert f'{field} = "{value}"' in provenance, "provenance pin differs from manifest"
    expected = {f"{area}-{client}.tsv" for area in AREAS for client in CLIENTS}
    expected |= {"semantics/" + name for name in expected}
    assert set(metadata["fixture_sha256"]) == expected, "incomplete receipt matrix"
    actual = {p.relative_to(corpus).as_posix() for p in corpus.rglob("*.tsv")}
    assert actual == expected, "receipt paths changed"
    for relative, value in metadata["fixture_sha256"].items():
        content = (corpus / relative).read_bytes()
        assert sha(content) == value, "receipt hash differs: " + relative
        assert f'["{relative}"] = "{digest(content)}"' in provenance, "Lua receipt pin differs: " + relative
    sources = metadata["source_sha256"]
    assert set(SUPPORT) <= set(sources), "original graph support input is not pinned"
    assert set(metadata["source_support_inputs"]) == set(SUPPORT), "incomplete historical loader/read closure"
    assert metadata["input_roots"] == {"source_sha256": "historical_committed_root", "harness_sha256": "observer_root"}
    assert metadata["original_loader"] == {"root": "source", "path": "tools/tests/menu_core_world.lua"}
    assert set(metadata["harness_inputs"]) == set(metadata["harness_sha256"]), "unhashed executed observer input"
    assert set(metadata["harness_edges"]) == set(metadata["harness_inputs"]), "observer closure missing"
    assert set(metadata["source_support_edges"]) == set(SUPPORT), "historical closure missing"
    for nodes, edges in ((set(SUPPORT), metadata["source_support_edges"]),
                         (set(metadata["harness_inputs"]), metadata["harness_edges"])):
        assert all(set(children) <= nodes for children in edges.values()), "unhashed loader/read dependency"
    for entries, edges, nodes in (
        (["tools/tests/menu_core_world.lua"], metadata["source_support_edges"], set(SUPPORT)),
        (["tools/tests/menu_" + area + "_inventory_smoke.lua" for area in AREAS] + ["tools/tests/menu_section_capture.py"],
         metadata["harness_edges"], set(metadata["harness_inputs"])),
    ):
        pending, reached = list(entries), set()
        while pending:
            node = pending.pop()
            if node not in reached:
                reached.add(node)
                pending.extend(edges[node])
        assert reached == nodes, "loader/read dependency closure is disconnected"
    assert observer, "authentic historical Git repository required"
    historical_observer(observer, corpus)
    authenticate_sources(observer, metadata)
    for prefix in ("MidnightSimpleUnitFrames/", "MidnightSimpleUnitFrames_Options/", "MidnightSimpleUnitFrames_Locales/"):
        assert any(p.startswith(prefix) for p in sources), "product source inventory missing"
    assert all(re.fullmatch("[0-9a-f]{64}", value) for value in sources.values()), "invalid source hash"
    comparison = json.loads((corpus / "source-comparison.json").read_text(encoding="utf-8"))
    assert comparison["original_base"] == ORIGINAL and comparison["parent_base"] == BASE, "legacy origin relabelled"
    legacy = {p: h for p, h in metadata["fixture_sha256"].items() if not p.startswith("semantics/")}
    assert comparison["original_receipts"] == legacy == comparison["parent_receipts"], "old receipt fields changed"
    assert comparison["parent_source_manifest"] == metadata["source_manifest_sha256"], "parent source evidence differs"
    require_ancestry(observer, ORIGINAL)
    original_support, _ = source_support(observer, ORIGINAL)
    original = {p: sha(data) for p, data in archive(observer, ORIGINAL, PRODUCT + original_support).items()}
    assert comparison["original_source_manifest"] == manifest_sha(original), "original Git source manifest differs"
    differences = {p: {"original": original.get(p), "parent": sources.get(p)} for p in set(original) | set(sources)
                   if original.get(p) != sources.get(p) and any(p.startswith(prefix + "/") for prefix in PRODUCT)}
    assert comparison["product_differences"] == differences, "historical Git source differences are incomplete"
    assert comparison["product_differences"], "source differences must be accounted for"
    for path, pair in comparison["product_differences"].items():
        assert pair["parent"] == sources[path] and pair["original"] != pair["parent"], "invalid source delta: " + path
    return len(expected)


def require_ancestry(root, baseline):
    assert git(root, "rev-parse", "--is-shallow-repository").decode().strip() == "false", "authentic ancestry requires complete reachable Git history (fetch-depth: 0)"
    resolved = git(root, "rev-parse", "--verify", baseline + "^{commit}").decode().strip()
    assert resolved == baseline, "historical baseline must be an exact commit"
    run = subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", baseline, "HEAD"],
                         env=clean_env(), capture_output=True, text=True)
    assert run.returncode != 1, "historical baseline is not a reachable ancestor of HEAD: " + baseline
    assert run.returncode == 0, "authentic Git ancestry query failed: " + run.stderr


def authenticate_sources(root, metadata):
    ref = metadata["base"]
    require_ancestry(root, ref)
    support, edges = source_support(root, ref)
    authentic = {p: sha(data) for p, data in archive(root, ref, PRODUCT + support).items()}
    assert authentic == metadata["source_sha256"], "source inventory differs from authentic Git objects: " + ref
    assert support == metadata["source_support_inputs"] and edges == metadata["source_support_edges"], "authentic source loader closure differs"
    return authentic



def capture_identity(metadata):
    identity = metadata["interpreters"]
    assert manifest_sha(identity) == HISTORICAL_CAPTURE_IDENTITY, "historical capture interpreter facts changed"
    assert identity["python"]["isolated"] and identity["lua"]["version"] == "Lua 5.1", "unisolated historical capture"
    return identity


def current_identity(lua, expected=None):
    assert sys.flags.isolated and sys.flags.no_site, "current replay must use Python -I -S"
    identity = interpreters(lua)
    identity["python"]["path"] = str(Path(sys.executable).resolve(strict=True))
    if expected is not None:
        assert identity == expected, "current replay interpreter identity changed"
    return identity

def check_parent(root, corpus):
    metadata = json.loads((corpus / "provenance.json").read_text(encoding="utf-8"))
    assert metadata["base"] == PARENT, "parity does not pin the captured pre-schema baseline"
    assert metadata["fixture_manifest_sha256"] == PARENT_RECEIPTS_MANIFEST, "actual-parent receipts differ from authenticated fixed manifest"
    authentic = authenticate_sources(root, metadata)
    assert metadata["clients"] == CLIENTS and metadata["areas"] == AREAS, "incomplete actual-parent matrix"
    expected = {prefix + area + "-" + client + ".tsv" for prefix in ("", "semantics/", "gaps/") for area in AREAS for client in CLIENTS}
    assert set(metadata["fixture_sha256"]) == expected, "incomplete parent observations"
    assert {p.relative_to(corpus).as_posix() for p in corpus.rglob("*.tsv")} == expected, "parent receipt paths differ"
    pins = (corpus / "provenance.lua").read_text(encoding="utf-8")
    assert f'base = "{PARENT}"' in pins, "Lua actual-parent pin differs"
    for key, field in (("source_sha256", "sourceManifest"), ("fixture_sha256", "fixtureManifest")):
        value = manifest_sha(metadata[key])
        assert metadata[key.replace("_sha256", "_manifest_sha256")] == value, "invalid parent manifest"
        assert f'{field} = "{value}"' in pins, "parent Lua manifest differs"
    for name, value in metadata["fixture_sha256"].items():
        content = (corpus / name).read_bytes()
        assert sha(content) == value and f'["{name}"] = "{digest(content)}"' in pins, "parent receipt digest differs: " + name
    paths, edges = closure(lambda p: (root / p).read_bytes(),
        ["tools/tests/menu_" + area + "_inventory_smoke.lua" for area in AREAS] +
        ["tools/tests/menu_section_capture.py", "tools/tests/menu_section_auth.py"])
    assert paths == metadata["harness_inputs"] and edges == metadata["harness_edges"], "parent observer closure differs"
    assert {p: sha((root / p).read_bytes()) for p in paths} == metadata["harness_sha256"], "parent executed observer changed"
    capture_identity(metadata)
    comparison = json.loads((corpus / "source-comparison.json").read_text(encoding="utf-8"))
    old = json.loads((root / "tools/fixtures/menu-section-parity/provenance.json").read_text(encoding="utf-8"))
    assert comparison["historical_base"] == BASE and comparison["actual_parent"] == PARENT, "actual-parent comparison relabelled"
    differences = {p: {"historical": old["source_sha256"].get(p), "actual_parent": authentic.get(p)}
        for p in set(old["source_sha256"]) | set(authentic) if old["source_sha256"].get(p) != authentic.get(p)}
    assert comparison["source_differences"] == differences, "actual-parent source differences are incomplete"
    for name, value in old["fixture_sha256"].items():
        assert comparison["historical_receipts"][name] == value, "historical receipts relabelled"
        assert comparison["actual_parent_receipts"][name] == metadata["fixture_sha256"][name], "actual parent receipts relabelled"
    assert comparison["receipt_differences"] == {name: {"historical": value, "actual_parent": metadata["fixture_sha256"][name]}
        for name, value in old["fixture_sha256"].items() if value != metadata["fixture_sha256"][name]}, "actual receipt differences not accounted for"
    return metadata


def replay(root, ref, observer, cases, output, lua):
    runtime_before = current_identity(lua)
    launcher = root / "tools/tests/menu_section_replay_launcher.lua"
    launcher_before = sha(launcher.read_bytes())
    support, _ = source_support(root, ref)
    source = output.parent / (output.name + "-source")
    materialize(root, ref, source, PRODUCT + support)
    before = validate_source(source, ref)
    entries = ["tools/tests/menu_" + area + "_inventory_smoke.lua" for area, _ in cases]
    entries.append("tools/tests/menu_section_capture.py")
    paths, edges = closure(lambda p: (observer / p).read_bytes(), entries)
    observed = {p: sha((observer / p).read_bytes()) for p in paths}
    output.mkdir()
    for folder in ("semantics", "layouts", "gaps"):
        (output / folder).mkdir()
    env = clean_env({"MSUF_SECTION_SOURCE_ROOT": str(source), "MSUF_SECTION_CAPTURE_OUTPUT": str(output),
                     "MSUF_SECTION_CAPTURE_BASE": ref, "MSUF_SECTION_CAPTURE_PYTHON": sys.executable})
    for area, client in cases:
        script = observer / ("tools/tests/menu_" + area + "_inventory_smoke.lua")
        command = [str(lua), str(script), str(observer), client, "--capture"]
        if observer != root:
            print("HISTORICAL_ADAPTER_EXECUTION " + json.dumps({"path": str(launcher), "sha256": launcher_before,
                "immutable_observer_manifest": HISTORICAL_OBSERVER_MANIFEST, "match": "exact historical check-source command",
                "inserted_args": ["-I", "-S"], "removed_cmd_envelope": os.name != "nt",
                "actual_interpreters": runtime_before}, sort_keys=True))
            command.insert(1, str(launcher))
        run = subprocess.run(command, cwd=observer, env=env, capture_output=True, text=True)
        assert run.returncode == 0, "authentic historical replay failed: " + area + "/" + client + "\n" + run.stdout + run.stderr
    assert validate_source(source, ref) == before, "authentic source changed during independent replay"
    final_paths, final_edges = closure(lambda p: (observer / p).read_bytes(), entries)
    assert final_paths == paths and final_edges == edges, "independent observer closure changed"
    assert {p: sha((observer / p).read_bytes()) for p in paths} == observed, "independent observer bytes changed"
    assert sha(launcher.read_bytes()) == launcher_before, "historical execution adapter changed during replay"
    current_identity(lua, runtime_before)
    receipts = {p.relative_to(output).as_posix(): p.read_bytes().replace(b"\r\n", b"\n") for p in output.rglob("*.tsv") if p.parent.name != "layouts"}
    prefixes = ("", "semantics/", "gaps/") if observer == root else ("", "semantics/")
    assert set(receipts) == {prefix + area + "-" + client + ".tsv" for area, client in cases for prefix in prefixes}, "authenticated replay receipt coverage incomplete"
    return receipts


def compare_replay(corpus, receipts):
    for name, content in receipts.items():
        assert (corpus / name).read_bytes().replace(b"\r\n", b"\n") == content, "independently replayed receipt differs: " + name


def main():
    root = Path(sys.argv[1]).resolve()
    corpus = root / "tools/fixtures/menu-section-parity"
    count = check(corpus, root)
    parent = root / "tools/fixtures/menu-section-parent"
    metadata = check_parent(root, parent)
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert lua, "Lua 5.1 required for independent authentic replay"
    runtime_before = current_identity(lua)
    print("CURRENT_REPLAY_INTERPRETERS " + json.dumps(runtime_before, sort_keys=True))
    # Capture facts remain authenticated on hosts where their original binaries are unavailable.
    from unittest.mock import patch
    capture_paths = {str(Path(value["path"]).resolve()) for key, value in metadata["interpreters"].items()
                     if key in ("python", "lua")}
    original_read = Path.read_bytes
    captured_reads = []
    def unavailable_capture_path(path):
        if str(path.resolve()) in capture_paths:
            captured_reads.append(str(path))
            raise FileNotFoundError("historical capture host unavailable")
        return original_read(path)
    with patch.object(Path, "read_bytes", unavailable_capture_path):
        check_parent(root, parent)
    assert not captured_reads, "portable proof tried to open a historical capture binary"
    current_identity(lua, runtime_before)
    forged_capture = json.loads(json.dumps(metadata))
    forged_capture["interpreters"]["python"]["sha256"] = "0" * 64
    try:
        capture_identity(forged_capture)
    except AssertionError as error:
        assert "historical capture interpreter facts changed" in str(error)
    else:
        raise AssertionError("forged historical capture identity accepted")
    for language, key, value in (("lua", "sha256", "0" * 64), ("python", "path", "forged-python")):
        forged_runtime = json.loads(json.dumps(runtime_before))
        forged_runtime[language][key] = value
        try:
            current_identity(lua, forged_runtime)
        except AssertionError as error:
            assert "current replay interpreter identity changed" in str(error)
        else:
            raise AssertionError("forged current replay identity accepted")
    print("REJECT forged historical/current identities; portable unavailable-capture-path control passed")
    with tempfile.TemporaryDirectory(prefix="section-authentic-") as directory:
        folder = Path(directory)
        observer = historical_observer(root, corpus, folder / "historical-observer")
        forged_root = folder / "self-rehashed-observer"
        forged_observer = forged_root / "tools/fixtures/menu-section-historical-observer"
        shutil.copytree(root / "tools/fixtures/menu-section-historical-observer", forged_observer)
        observer_name = "tools/tests/menu_section_parity_semantics.lua"
        observer_file = forged_observer / (observer_name + ".fixture")
        observer_file.write_bytes(observer_file.read_bytes() + b"\n-- forged observer input\n")
        identity = json.loads((forged_observer / "identity.json").read_text())
        identity["files_sha256"][observer_name] = sha(observer_file.read_bytes())
        identity["observer_manifest_sha256"] = manifest_sha(identity["files_sha256"])
        content = observer_file.read_bytes().replace(b"\r\n", b"\n")
        import hashlib
        identity["git_blob_sha1"][observer_name] = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
        (forged_observer / "identity.json").write_text(json.dumps(identity))
        try:
            historical_observer(forged_root, corpus)
        except AssertionError as error:
            assert "independent immutable identity" in str(error), str(error)
        else:
            raise AssertionError("self-rehashed historical observer accepted")
        historical = replay(root, BASE, observer, [("pvp_trinket", "Mainline"), ("dispel_overlay", "Mainline")], folder / "historical", lua)
        compare_replay(corpus, historical)
        cases = [(area, "Mainline") for area in AREAS] + [("dispel_overlay", "TBC"), ("dispel_symbol", "Vanilla"),
            ("unit_visibility", "Forever"), ("boss_arena_layout", "Mists")]
        current = replay(root, PARENT, root, cases, folder / "parent", lua)
        compare_replay(parent, current)
        forged = folder / "forged"
        shutil.copytree(corpus, forged)
        name = "semantics/pvp_trinket-Mainline.tsv"
        (forged / name).write_bytes((forged / name).read_bytes() + b"forged\told-output\n")
        data = json.loads((forged / "provenance.json").read_text())
        previous = data["fixture_manifest_sha256"]
        original_digest = digest((corpus / name).read_bytes())
        data["fixture_sha256"][name] = sha((forged / name).read_bytes())
        data["fixture_manifest_sha256"] = manifest_sha(data["fixture_sha256"])
        (forged / "provenance.json").write_text(json.dumps(data))
        pins = (forged / "provenance.lua").read_text().replace(previous, data["fixture_manifest_sha256"])
        pins = pins.replace(f'["{name}"] = "{original_digest}"', f'["{name}"] = "{digest((forged / name).read_bytes())}"')
        (forged / "provenance.lua").write_text(pins)
        try:
            check(forged, root)
        except AssertionError as error:
            assert "immutable anchor" in str(error), str(error)
        else:
            raise AssertionError("self-rehashed historical forgery accepted")
        try:
            compare_replay(forged, historical)
        except AssertionError as error:
            assert "independently replayed receipt differs" in str(error)
        else:
            raise AssertionError("native replay accepted self-rehashed historical forgery")
        forged_source = dict(metadata)
        forged_source["source_sha256"] = dict(metadata["source_sha256"])
        forged_source["source_sha256"][next(iter(forged_source["source_sha256"]))] = "0" * 64
        try:
            authenticate_sources(root, forged_source)
        except AssertionError as error:
            assert "authentic Git objects" in str(error)
        else:
            raise AssertionError("self-declared source inventory accepted")
    current_identity(lua, runtime_before)
    print(f"menu_section_provenance_smoke: {count} immutable historical receipts; 90 actual-parent observations; authentic Git sources and 34 independently replayed receipts OK")


if __name__ == "__main__":
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit(subprocess.call(
            [sys.executable, "-I", "-S", str(Path(__file__).resolve()), *sys.argv[1:]], env=clean_env()))
    main()
