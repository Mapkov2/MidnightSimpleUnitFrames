"""Fixed authentic baselines must survive descendant and merge checkout geometry."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from menu_section_auth import PARENT, clean_env, git, interpreters
from menu_section_capture import BASE, ORIGINAL, sha, digest, manifest_sha
from menu_section_provenance_smoke import check_parent, require_ancestry, PARENT_RECEIPTS_MANIFEST
from menu_section_test_runtime import bash_path, lua_literal, proof_sources


def native(root, *args, input=None):
    return subprocess.run(["git", "-C", str(root), *args], env=clean_env(), input=input, capture_output=True, text=True)


def reject(call, diagnostic):
    try:
        call()
    except AssertionError as error:
        assert diagnostic in str(error), str(error)
        print("REJECT " + diagnostic)
    else:
        raise AssertionError("proof accepted " + diagnostic)


def main():
    root = Path(sys.argv[1]).resolve()
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert lua, "Lua 5.1 required"
    before = interpreters(lua)
    inputs_before = proof_sources(root, __file__)
    for ref in (PARENT, BASE, ORIGINAL):
        require_ancestry(root, ref)
    with tempfile.TemporaryDirectory(prefix="section-graph-") as directory:
        folder = Path(directory)
        repo = folder / "geometry"
        repo.mkdir()
        assert native(repo, "init", "--quiet").returncode == 0
        assert native(repo, "config", "core.autocrlf", "false").returncode == 0
        common = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").decode().strip())
        (repo / ".git/objects/info/alternates").write_bytes(((common / "objects").as_posix() + "\n").encode())
        head = git(root, "rev-parse", "HEAD").decode().strip()
        run = native(repo, "checkout", "--quiet", "--detach", head)
        assert run.returncode == 0, run.stderr
        tree = git(repo, "rev-parse", "HEAD^{tree}").decode().strip()
        name = git(root, "show", "-s", "--format=%an", head).decode().strip()
        email = git(root, "show", "-s", "--format=%ae", head).decode().strip()
        def commit(tree, *parents):
            args = ["-c", "user.name=" + name, "-c", "user.email=" + email, "commit-tree", tree]
            for parent in parents:
                args += ["-p", parent]
            run = native(repo, *args, input="Native history geometry proof\n")
            assert run.returncode == 0, run.stderr
            return run.stdout.strip()
        descendant = commit(tree, head)
        side = commit(git(repo, "rev-parse", PARENT + "^{tree}").decode().strip(), PARENT)
        merge = commit(tree, side, head)
        nonancestor = commit(tree)
        for label, target in (("descendant", descendant), ("merge-ref", merge)):
            assert native(repo, "checkout", "--quiet", "--detach", target).returncode == 0
            assert git(repo, "rev-parse", "HEAD^{tree}").decode().strip() == tree
            assert git(repo, "rev-parse", "HEAD^").decode().strip() != PARENT
            check_parent(repo, repo / "tools/fixtures/menu-section-parent")
            for ref in (BASE, ORIGINAL):
                require_ancestry(repo, ref)
            print("GREEN native " + label + " fixed-baseline authentication")
        reject(lambda: require_ancestry(repo, nonancestor), "not a reachable ancestor")
        assert native(repo, "checkout", "--quiet", "--detach", nonancestor).returncode == 0
        assert all(native(repo, "cat-file", "-e", ref + "^{commit}").returncode == 0 for ref in (PARENT, BASE, ORIGINAL))
        reject(lambda: check_parent(repo, repo / "tools/fixtures/menu-section-parent"), "not a reachable ancestor")
        shallow = folder / "shallow"
        shallow.mkdir()
        assert native(shallow, "init", "--quiet").returncode == 0
        run = native(shallow, "fetch", "--no-tags", "--depth", "1", root.as_uri(), head)
        assert run.returncode == 0, run.stderr
        assert native(shallow, "checkout", "--quiet", "--detach", "FETCH_HEAD").returncode == 0
        reject(lambda: require_ancestry(shallow, PARENT), "complete reachable Git history")
        # A damaged partial object store must not claim completeness by dropping its marker.
        (shallow / ".git/shallow").unlink()
        assert native(shallow, "cat-file", "-e", PARENT + "^{commit}").returncode != 0
        reject(lambda: require_ancestry(shallow, PARENT), "authentic Git history unavailable")
        corpus = folder / "forged-parent"
        shutil.copytree(root / "tools/fixtures/menu-section-parent", corpus)
        relative = "gaps/dispel_overlay-Mists.tsv"
        original = (corpus / relative).read_bytes()
        (corpus / relative).write_bytes(original + b"forged\tunreplayed-gap\n")
        metadata = json.loads((corpus / "provenance.json").read_text())
        previous = metadata["fixture_manifest_sha256"]
        metadata["fixture_sha256"][relative] = sha((corpus / relative).read_bytes())
        metadata["fixture_manifest_sha256"] = manifest_sha(metadata["fixture_sha256"])
        assert metadata["fixture_manifest_sha256"] != PARENT_RECEIPTS_MANIFEST
        (corpus / "provenance.json").write_text(json.dumps(metadata))
        pins = (corpus / "provenance.lua").read_text().replace(previous, metadata["fixture_manifest_sha256"])
        pins = pins.replace('["' + relative + '"] = "' + digest(original) + '"',
                            '["' + relative + '"] = "' + digest((corpus / relative).read_bytes()) + '"')
        (corpus / "provenance.lua").write_text(pins)
        reject(lambda: check_parent(root, corpus), "authenticated fixed manifest")
        for value in ("C:/tmp/caf\u00e9-\u4e2d\u6587", 'quote" slash\\ newline\n nul\0x'):
            program = "local value=" + lua_literal(value) + "; for i=1,#value do io.write(string.format('%02x',value:byte(i))) end"
            run = subprocess.run([str(lua), "-e", program], env=clean_env(), capture_output=True)
            assert run.returncode == 0 and run.stdout == value.encode("utf-8").hex().encode(), "Lua 5.1 literal bytes differ"
        print("GREEN actual Lua 5.1 Unicode/control literal byte equality")
        selected = bash_path()
        if os.name == "nt":
            real_which = shutil.which
            requested = []
            def misleading(name):
                requested.append(name)
                return "C:/Windows/System32/bash.exe" if name == "bash" else real_which(name)
            with patch("menu_section_test_runtime.shutil.which", misleading):
                assert bash_path() == selected
            assert "bash" not in requested, "Windows selected the WSL-compatible PATH name"
        print("GREEN actual native Bash selection: " + str(selected))
    assert proof_sources(root, __file__) == inputs_before, "contract proof inputs changed"
    assert interpreters(lua) == before, "contract proof current interpreter identity changed"
    print("menu_section_proof_contract_smoke: descendant/merge valid; nonancestor/missing/shallow/forgery rejected; native runtime controls OK")


if __name__ == "__main__":
    if not sys.flags.isolated or not sys.flags.no_site:
        raise SystemExit(subprocess.call([sys.executable, "-I", "-S", str(Path(__file__).resolve()), *sys.argv[1:]], env=clean_env()))
    main()
