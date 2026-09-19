#!/usr/bin/env python3
"""Self-test of tools/rebase-classic-overrides.py.

Builds a tiny Retail repository (three commits) and a tiny Classic repository
in a temporary directory and drives the real command line against them. It
needs git and Python 3 only, no Retail checkout and no network, and touches
nothing outside its temporary directory. The Classic gate runs it in full and
self-contained mode (its row in tools/classic-gate-smokes.tsv); by hand:

    python tools/tests/rebase_classic_overrides_smoke.py

Exit code 0 when every check passes. Pass --keep to keep the temporary
repositories for a look around.
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "rebase-classic-overrides.py"

CORE = "MidnightSimpleUnitFrames"
OPTIONS = "MidnightSimpleUnitFrames_Options"
ASSISTANT = "MidnightSimpleUnitFrames_Assistant"
OVERRIDES = "tools/classic-retail-overrides.tsv"
SHADOWS = "tools/classic-owned-shadows.tsv"
OWNED = "tools/classic-owned-addon-paths.txt"

CLEAN = CORE + "/Kernel/Clean.lua"
CONFLICT = CORE + "/Kernel/Conflict.lua"
UPSTREAMED = CORE + "/Kernel/Upstreamed.lua"
CARRIED = CORE + "/Kernel/Carried.lua"
STILL = CORE + "/Kernel/Still.lua"
UNIX = CORE + "/Kernel/UnixStyle.lua"
ZETA = CORE + "/Kernel/Zeta.lua"
ALPHA = CORE + "/Kernel/alpha.lua"
MIRROR = CORE + "/Kernel/Mirror.lua"
GONE = CORE + "/Kernel/Gone.lua"
TANGLE = CORE + "/Kernel/Tangle.lua"
GENERATED = CORE + "/State/MSUF_Changelog.lua"
RETAIL_TOC = CORE + "/" + CORE + ".toc"
CLASSIC_TOC = CORE + "/" + CORE + "_Mainline.toc"
MENU = OPTIONS + "/Shell/Menu.lua"
PAGE = OPTIONS + "/Shell/Page.lua"
PAGE_SHADOW = OPTIONS + "/Shell/Page_Classic.lua"
TANGLE_SHADOW = CORE + "/Game/Classic/Tangle.lua"

# Ordinal (UTF-16 code unit) order, written out by hand: "Zeta" sorts before
# "alpha", and "MidnightSimpleUnitFrames/" before "MidnightSimpleUnitFrames_".
OVERRIDE_ORDER = [CARRIED, CLEAN, CONFLICT, STILL, UNIX, UPSTREAMED, ZETA, ALPHA, CLASSIC_TOC, GENERATED, MENU]

failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def lua(name, **changes):
    """A ten-line Lua file; keyword arguments replace single lines (A..H)."""
    values = {letter: "local %s = %d" % (letter, index) for index, letter in enumerate("ABCDEFGH", 1)}
    values.update(changes)
    lines = ["-- " + name] + [values[letter] for letter in "ABCDEFGH"] + ["return A"]
    return "\n".join(lines) + "\n"


def toc(version, *extra):
    lines = ["## Interface: 120001", "## Title: Core", "## Version: " + version, "## SavedVariables: MSUF_DB",
             "", "Kernel/Clean.lua", "Kernel/Conflict.lua", "Kernel/Mirror.lua", "Kernel/Still.lua"]
    return "\n".join(lines + list(extra)) + "\n"


def git(repo, *arguments):
    environment = dict(os.environ, GIT_AUTHOR_NAME="selftest", GIT_AUTHOR_EMAIL="selftest@example.invalid",
                       GIT_COMMITTER_NAME="selftest", GIT_COMMITTER_EMAIL="selftest@example.invalid")
    process = subprocess.run(["git", "-C", str(repo)] + list(arguments), stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=environment)
    if process.returncode != 0:
        raise SystemExit("git %s failed:\n%s" % (" ".join(arguments), process.stderr.decode("utf-8", "replace")))
    return process.stdout.decode("utf-8").strip()


def write(root, relative, text, crlf=False):
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    data = text.encode("utf-8")
    target.write_bytes(data.replace(b"\n", b"\r\n") if crlf else data)


def commit_all(repo, message):
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def new_repository(path, autocrlf):
    path.mkdir(parents=True)
    git(path, "init", "-q")
    for key, value in (("core.autocrlf", autocrlf), ("core.safecrlf", "false"), ("commit.gpgsign", "false")):
        git(path, "config", key, value)
    return path


def build_retail(path):
    """Three commits: the recorded base, the revision to rebase onto, and a deletion."""
    retail = new_repository(path, "false")
    for name in (CLEAN, CONFLICT, UPSTREAMED, CARRIED, STILL, UNIX, ZETA, ALPHA, MIRROR, GONE, TANGLE, MENU, PAGE):
        write(retail, name, lua(name))
    write(retail, GENERATED, "-- generated\nrecords = 1\n")
    write(retail, RETAIL_TOC, toc("6.20"))
    write(retail, OPTIONS + "/" + OPTIONS + ".toc", "## Title: Options\n")
    write(retail, ASSISTANT + "/" + ASSISTANT + ".toc", "## Title: Assistant\n")
    base = commit_all(retail, "base")

    for name in (CLEAN, UNIX, ZETA, MENU, PAGE, MIRROR):
        write(retail, name, lua(name, A="local A = 100"))
    write(retail, CONFLICT, lua(CONFLICT, C="local C = 30"))
    write(retail, TANGLE, lua(TANGLE, C="local C = 30"))
    write(retail, UPSTREAMED, lua(UPSTREAMED, B="local B = 22"))
    write(retail, CARRIED, lua(CARRIED, B="local B = 22"))
    write(retail, GENERATED, "-- generated\nrecords = 2\n")
    write(retail, RETAIL_TOC, toc("6.21"))
    (retail / GONE).unlink()
    head = commit_all(retail, "new")

    (retail / STILL).unlink()
    deletion = commit_all(retail, "delete an overridden file")
    return retail, base, head, deletion


def build_classic(path, retail, base, head):
    """A CRLF checkout (core.autocrlf=true) whose overrides are recorded at `base`."""
    classic = new_repository(path, "true")

    def blob(revision, name):
        return git(retail, "rev-parse", "%s:%s" % (revision, name))

    edit = dict(G="local G = 700 -- Classic")
    for name in (CLEAN, ZETA, MENU, ALPHA, STILL):
        write(classic, name, lua(name, **edit), crlf=True)
    write(classic, UNIX, lua(UNIX, **edit), crlf=False)
    write(classic, CONFLICT, lua(CONFLICT, C="local C = 33 -- Classic"), crlf=True)
    write(classic, UPSTREAMED, lua(UPSTREAMED, B="local B = 22"), crlf=True)
    write(classic, CARRIED, lua(CARRIED, B="local B = 22", F="local F = 66 -- Classic"), crlf=True)
    write(classic, GENERATED, "-- generated\nrecords = 1\nclassic = true\n", crlf=True)
    write(classic, CLASSIC_TOC, toc("6.20", "Game/Shared/Initialize.lua"), crlf=True)
    # Mirrors: level with `head`, except Mirror.lua and the file Retail deleted.
    write(classic, MIRROR, lua(MIRROR), crlf=True)
    write(classic, GONE, lua(GONE), crlf=True)
    write(classic, TANGLE, lua(TANGLE, C="local C = 30"), crlf=True)
    write(classic, PAGE, lua(PAGE, A="local A = 100"), crlf=True)
    write(classic, OPTIONS + "/" + OPTIONS + "_Mainline.toc", "## Title: Options\n", crlf=True)
    write(classic, ASSISTANT + "/" + ASSISTANT + "_Mainline.toc", "## Title: Assistant\n", crlf=True)
    # Owned shadows: one takes Retail's change cleanly, one conflicts with it.
    write(classic, PAGE_SHADOW, lua(PAGE, **edit), crlf=True)
    write(classic, TANGLE_SHADOW, lua(TANGLE, C="local C = 33 -- Classic"), crlf=True)

    rows = ["%s\t%s" % (name, blob(base, RETAIL_TOC if name == CLASSIC_TOC else name)) for name in OVERRIDE_ORDER]
    write(classic, OVERRIDES, "\n".join(rows) + "\n", crlf=True)
    write(classic, SHADOWS, "%s\t%s\t%s\n%s\t%s\t%s\n" % (
        TANGLE_SHADOW, TANGLE, blob(base, TANGLE), PAGE_SHADOW, PAGE, blob(base, PAGE)), crlf=True)
    write(classic, OWNED, "%s\n%s\n" % (TANGLE_SHADOW, PAGE_SHADOW), crlf=True)
    commit_all(classic, "classic")
    return classic


def remove_tree(path):
    """rmtree that also clears the read-only bit git sets on its objects (Windows)."""
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


def snapshot(root):
    state = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and ".git" not in path.relative_to(root).parts:
            state[path.relative_to(root).as_posix()] = path.read_bytes()
    return state


def run_tool(classic, retail, revision, *extra):
    command = [sys.executable, str(TOOL), "--classic", str(classic), "--retail", str(retail),
               "--retail-rev", revision] + list(extra)
    process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = process.stdout.decode("utf-8", "replace").replace("\r\n", "\n")
    errors = process.stderr.decode("utf-8", "replace").replace("\r\n", "\n")
    return process.returncode, output, errors


def manifest_rows(classic, relative):
    """(raw bytes, rows). Parsing accepts either line ending; the CRLF checks look at the bytes."""
    data = (classic / relative).read_bytes()
    lines = data.replace(b"\r\n", b"\n").split(b"\n")
    return data, [tuple(line.decode("utf-8").split("\t")) for line in lines if line]


def override_rows(classic):
    return manifest_rows(classic, OVERRIDES)


def status_line(output, path):
    """The status word the report prints in front of a path."""
    for line in output.split("\n"):
        words = line.split()
        if len(words) == 2 and words[1] == path:
            return words[0]
    return ""


def main():
    keep = "--keep" in sys.argv[1:]
    root = Path(tempfile.mkdtemp(prefix="msuf-rebase-selftest-")).resolve()
    try:
        retail, base, head, deletion = build_retail(root / "retail")
        classic = build_classic(root / "classic", retail, base, head)
        conflicts = root / "conflicts"

        def retail_blob(name, revision=head):
            return git(retail, "rev-parse", "%s:%s" % (revision, name))

        print("dry run (the default)")
        before = snapshot(classic)
        code, output, errors = run_tool(classic, retail, head)
        check(code == 2, "exit code 2 while a conflict and a generated file remain (got %d) %s" % (code, errors))
        check(snapshot(classic) == before and git(classic, "status", "--porcelain") == "",
              "a dry run writes nothing into the Classic checkout")
        check(not conflicts.exists(), "a dry run without --conflict-dir creates no directory")
        expected = {CLEAN: "merged", UNIX: "merged", ZETA: "merged", MENU: "merged", CLASSIC_TOC: "merged",
                    CARRIED: "carried", UPSTREAMED: "no-op", CONFLICT: "CONFLICT", GENERATED: "REGENERATE",
                    PAGE_SHADOW: "merged", TANGLE_SHADOW: "CONFLICT", STILL: "", ALPHA: ""}
        for name, status in sorted(expected.items()):
            check(status_line(output, name) == status, "plan: %s is %s" % (name, status or "current (not listed)"))
        check(output.rstrip("\n").split("\n")[-1] == "Retail-Source: " + head,
              "the last output line is the trailer with the full Retail commit")
        check("2 mirrored paths above are not at Retail" in output and MIRROR in output and GONE in output,
              "a mirrored file that is behind and one Retail deleted are reported next to the trailer")

        print("--write --conflict-dir")
        code, output, errors = run_tool(classic, retail, head, "--write", "--conflict-dir", str(conflicts))
        after = snapshot(classic)
        check(code == 2, "exit code 2: the conflict and the generated file are still open (got %d) %s" % (code, errors))
        merged = lua(CLEAN, A="local A = 100", G="local G = 700 -- Classic").encode("utf-8")
        check(after[CLEAN] == merged.replace(b"\n", b"\r\n"),
              "clean merge: Retail's and Classic's edits are both in the file, CRLF kept")
        check(after[UNIX] == lua(UNIX, A="local A = 100", G="local G = 700 -- Classic").encode("utf-8"),
              "clean merge of an LF working file stays LF")
        check(after[CONFLICT] == before[CONFLICT], "conflict: the working file is untouched")
        preview = (conflicts / CONFLICT).read_bytes() if (conflicts / CONFLICT).is_file() else b""
        check(all(marker in preview for marker in (b"<<<<<<< ", b"||||||| ", b"=======", b">>>>>>> "))
              and b"local C = 33 -- Classic\r\n" in preview and b"local C = 30\r\n" in preview,
              "conflict: --conflict-dir holds the diff3 result in the file's line ending style")
        check(after[UPSTREAMED] == before[UPSTREAMED] and after[CARRIED] == before[CARRIED]
              and after[GENERATED] == before[GENERATED] and after[STILL] == before[STILL],
              "no-op, carried, generated and unmoved files are untouched")
        check(after[CLASSIC_TOC] == toc("6.21", "Game/Shared/Initialize.lua").encode("utf-8").replace(b"\n", b"\r\n"),
              "TOC mapping: _Mainline.toc merges against Retail's unsuffixed TOC and keeps every line")
        check(after[SHADOWS] == before[SHADOWS] and after[PAGE_SHADOW] == before[PAGE_SHADOW]
              and after[TANGLE_SHADOW] == before[TANGLE_SHADOW], "shadows are report-only without --write-shadows")

        data, rows = override_rows(classic)
        recorded = dict(rows)
        check(data.endswith(b"\r\n") and data.count(b"\n") == data.count(b"\r\n") == len(rows),
              "overrides manifest keeps CRLF on every line")
        check([row[0] for row in rows] == [name for name in OVERRIDE_ORDER if name != UPSTREAMED],
              "overrides manifest stays in ordinal order and the no-op row is gone")
        for name in (CLEAN, UNIX, ZETA, MENU, CARRIED):
            check(recorded.get(name) == retail_blob(name), "row advanced to the new Retail blob: " + name)
        check(recorded.get(CLASSIC_TOC) == retail_blob(RETAIL_TOC),
              "TOC row records the blob of Retail's unsuffixed TOC")
        for name in (CONFLICT, GENERATED, STILL, ALPHA):
            check(recorded.get(name) == retail_blob(RETAIL_TOC if name == CLASSIC_TOC else name, base),
                  "row keeps its recorded base: " + name)

        print("--resolved")
        write(classic, CONFLICT, preview.decode("utf-8").replace("\r\n", "\n"), crlf=True)
        code, output, errors = run_tool(classic, retail, head, "--write", "--resolved", CONFLICT)
        check(code == 2 and dict(override_rows(classic)[1]).get(CONFLICT) == retail_blob(CONFLICT, base),
              "--resolved is refused while the file still holds conflict markers")
        write(classic, CONFLICT, lua(CONFLICT, C="local C = 330 -- Classic on Retail 30"), crlf=True)
        write(classic, GENERATED, "-- generated\nrecords = 2\nclassic = true\n", crlf=True)
        settled = snapshot(classic)
        code, output, errors = run_tool(classic, retail, head, "--write", "--resolved", CONFLICT,
                                        "--resolved", GENERATED.replace("/", "\\"))
        recorded = dict(override_rows(classic)[1])
        check(code == 0, "exit code 0 once every override is settled; shadow drift alone stays report-only "
              "(got %d) %s" % (code, errors))
        check(recorded.get(CONFLICT) == retail_blob(CONFLICT) and recorded.get(GENERATED) == retail_blob(GENERATED),
              "--resolved records the new Retail blob (backslashes in the path are accepted)")
        now = snapshot(classic)
        check(all(now[name] == settled[name] for name in settled if name != OVERRIDES),
              "--resolved touches no file but the manifest")

        print("mirrors level with Retail")
        write(classic, MIRROR, lua(MIRROR, A="local A = 100"), crlf=True)
        git(classic, "rm", "-q", "--cached", GONE)
        (classic / GONE).unlink()
        code, output, errors = run_tool(classic, retail, head)
        check(code == 0 and "Every mirrored path equals Retail" in output
              and output.rstrip("\n").split("\n")[-1] == "Retail-Source: " + head,
              "with every mirror level the trailer is offered for the rebase commit")
        check(status_line(output, CLEAN) == "" and "10 rows, 10 current" in output,
              "a second run finds every override current")

        print("--write-shadows")
        code, output, errors = run_tool(classic, retail, head, "--write-shadows")
        now = snapshot(classic)
        shadow_rows = [list(row) for row in manifest_rows(classic, SHADOWS)[1]]
        check(code == 2, "exit code 2: with --write-shadows the conflicting shadow counts (got %d) %s" % (code, errors))
        check(now[PAGE_SHADOW] == lua(PAGE, A="local A = 100", G="local G = 700 -- Classic").encode("utf-8")
              .replace(b"\n", b"\r\n"), "clean shadow merge is written")
        check(now[TANGLE_SHADOW] == before[TANGLE_SHADOW], "conflicting shadow is untouched")
        check(shadow_rows == [[TANGLE_SHADOW, TANGLE, retail_blob(TANGLE, base)], [PAGE_SHADOW, PAGE, retail_blob(PAGE)]]
              and now[SHADOWS].count(b"\n") == now[SHADOWS].count(b"\r\n") == 2,
              "shadows manifest: clean row advanced, conflicting row kept, order and CRLF kept")

        print("errors and removals")
        code, output, errors = run_tool(classic, retail, deletion)
        check(code == 2 and status_line(output, STILL) == "REMOVED",
              "an override Retail deleted is reported as REMOVED and left for a human")
        code, output, errors = run_tool(classic, retail, "no-such-revision")
        check(code == 1 and "names no commit" in errors, "an unknown Retail revision is exit code 1")
        code, output, errors = run_tool(classic, classic, "HEAD")
        check(code == 1 and "is not a Retail tree" in errors,
              "a Classic commit passed as the Retail revision is refused (suffixed TOCs only)")
        code, output, errors = run_tool(classic, retail, head, "--resolved", CORE + "/Kernel/Nowhere.lua")
        check(code == 1 and "names no override or shadow row" in errors, "--resolved with an unknown path is exit code 1")
        code, output, errors = run_tool(classic, retail, head, "--dry-run", "--write")
        check(code == 1, "--dry-run with --write is a usage error with exit code 1")
        code, output, errors = run_tool(classic, retail, head, "--conflict-dir", str(classic / "dist"))
        check(code == 1 and "outside the Classic checkout" in errors, "--conflict-dir inside the checkout is refused")
    finally:
        if keep:
            print("kept: %s" % root)
        else:
            remove_tree(root)

    print()
    if failures:
        print("rebase-classic-overrides self-test: %d FAILED" % len(failures))
        for message in failures:
            print("  " + message)
        return 1
    print("rebase-classic-overrides self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
