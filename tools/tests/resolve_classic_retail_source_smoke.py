#!/usr/bin/env python3
"""Smoke for .github/scripts/resolve_classic_retail_source.py.

Builds a tiny Retail history (with a side branch and a merge) and a tiny
Classic repository holding one commit per mirrored state in a temporary
directory, and drives the real command line against them. Each matching rule
of the resolver has a state where that rule alone decides the answer:

- where a rule can separate two commits, the state resolves to the right
  Retail commit and the rule alone rejects a newer neighbour;
- the TOC count and the folder-level ownership collisions cannot: any state
  that mirrors the offending path mirrors it from every commit it could match.
  Their states match nothing, and the rule is the one mismatch the diagnostic
  names for the nearest commit.

Both repositories are written by `git fast-import`, never through a working
tree, so the history can hold an executable file and case-variant paths that a
Windows checkout could not. Needs git and Python 3 only, no network, and
touches nothing outside its temporary directory:

    python tools/tests/resolve_classic_retail_source_smoke.py [repository root]
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
TOOL = ROOT / ".github" / "scripts" / "resolve_classic_retail_source.py"

CORE = "MidnightSimpleUnitFrames"
OPTIONS = "MidnightSimpleUnitFrames_Options"
ASSISTANT = "MidnightSimpleUnitFrames_Assistant"
CORE_TOC = CORE + "/" + CORE + ".toc"
OPTIONS_TOC = OPTIONS + "/" + OPTIONS + ".toc"
ASSISTANT_TOC = ASSISTANT + "/" + ASSISTANT + ".toc"
MIRRORED = CORE + "/Kernel/Mirrored.lua"
PATCHED = CORE + "/Kernel/Patched.lua"
DELETED = CORE + "/Kernel/Deleted.lua"
ADDED = CORE + "/Kernel/Added.lua"
PAGE = OPTIONS + "/Shell/Page.lua"
OWNED = CORE + "/Game/Classic/Owned.lua"
OWNED_TEXT = "-- Classic owned\n"
# A Retail file named like a folder of the owned path, and a Retail file below
# a folder named like the owned path. Both differ from the owned path in case
# only, so a Classic tree can hold them beside it; the gate compares ownership
# case-insensitively.
FOLDER_OF_OWNED = CORE + "/Game/classic"
BELOW_OWNED = CORE + "/Game/Classic/owned.lua/Inner.lua"
EXTRA_TOC = CORE + "/Extra.toc"

TOC_ONE = "## Title: Options\n"
TOC_SIX = "## Title: Options\n## Notes: six\n"

failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def git(repo, *arguments, stdin=None):
    process = subprocess.run(["git", "-C", str(repo)] + list(arguments), input=stdin, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)
    if process.returncode != 0:
        raise SystemExit("git %s failed:\n%s" % (" ".join(arguments), process.stderr.decode("utf-8", "replace")))
    return process.stdout.decode("utf-8").strip()


def new_repository(path):
    path.mkdir(parents=True)
    git(path, "init", "-q")
    # fast-import folds case-variant paths into one under core.ignorecase,
    # which git init turns on for a Windows temporary directory.
    for key, value in (("core.autocrlf", "false"), ("core.ignorecase", "false"), ("uploadpack.allowFilter", "true")):
        git(path, "config", key, value)
    git(path, "symbolic-ref", "HEAD", "refs/heads/main")
    return path


def blob_id(text):
    data = text.encode("utf-8")
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


class Stream:
    """Commits for one `git fast-import` run; each commit holds exactly its `files`."""

    def __init__(self):
        self.parts = []
        self.marks = {}

    def commit(self, name, files, parents=(), ref="refs/heads/main"):
        mark = len(self.marks) + 1
        self.marks[name] = mark
        # Distinct, rising timestamps keep --date-order deterministic.
        stamp = "smoke <smoke@example.invalid> %d +0000" % (1767225600 + 60 * mark)
        message = name.encode("ascii")
        chunk = [b"commit %s\nmark :%d\nauthor %s\ncommitter %s\ndata %d\n%s\n" % (
            ref.encode("ascii"), mark, stamp.encode("ascii"), stamp.encode("ascii"), len(message), message)]
        for index, parent in enumerate(parents):
            chunk.append(b"%s :%d\n" % (b"from" if index == 0 else b"merge", self.marks[parent]))
        chunk.append(b"deleteall\n")
        for path in sorted(files):
            mode, text = files[path] if isinstance(files[path], tuple) else ("100644", files[path])
            data = text.encode("utf-8")
            chunk.append(b"M %s inline %s\ndata %d\n%s\n" % (
                mode.encode("ascii"), path.encode("utf-8"), len(data), data))
        self.parts.append(b"".join(chunk) + b"\n")

    def write(self, repo):
        marks_file = repo / ".git" / "smoke-marks"
        git(repo, "fast-import", "--quiet", "--export-marks=" + str(marks_file), stdin=b"".join(self.parts))
        by_mark = {}
        for line in marks_file.read_text(encoding="ascii").splitlines():
            mark, commit = line.split()
            by_mark[int(mark[1:])] = commit
        return {name: by_mark[mark] for name, mark in self.marks.items()}


def remove_tree(path):
    """rmtree that also clears the read-only bit git sets on its objects (Windows)."""
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


def build_retail(path):
    """Main r1..r16 with a side branch s1 from r6 that r8 merges; returns (repo, {name: commit})."""
    stream = Stream()
    files = {
        CORE_TOC: "## Version: 1\nKernel\\Mirrored.lua\n",
        OPTIONS_TOC: TOC_ONE,
        ASSISTANT_TOC: "## Title: Assistant\n",
        MIRRORED: "a1\n", PATCHED: "p1\n", DELETED: "d1\n", PAGE: "o1\n",
        "README.md": "r1\n",
    }
    stream.commit("r1", files)
    previous = "r1"

    def step(name, change, parents=None, ref="refs/heads/main", base=None):
        nonlocal previous
        tree = dict(files if base is None else base)
        for relative, value in change.items():
            if value is None:
                del tree[relative]
            else:
                tree[relative] = value
        stream.commit(name, tree, parents or (previous,), ref)
        if ref == "refs/heads/main":
            files.clear()
            files.update(tree)
            previous = name
        return tree

    step("r2", {MIRRORED: "a2\n"})
    step("r3", {"README.md": "r3\n"})                 # nothing below the addon folders
    step("r4", {PATCHED: "p2\n"})                     # moves the override's Retail base
    step("r5", {DELETED: None})
    step("r6", {OPTIONS_TOC: TOC_SIX})
    side = step("s1", {MIRRORED: "a3\n"}, parents=("r6",), ref="refs/heads/side")
    step("r7", {PAGE: "o7\n"})
    step("r8", {MIRRORED: side[MIRRORED]}, parents=("r7", "s1"))
    step("r9", {OWNED: OWNED_TEXT})                    # exact collision with the owned path
    step("r10", {OWNED: None, PAGE: "o10\n"})
    step("r11", {ADDED: "n11\n"})                      # a file the r10 mirror lacks
    step("r12", {MIRRORED: ("100755", "a3\n")})        # mode only: an executable file
    step("r13", {MIRRORED: "a3\n", PATCHED: None})     # deletes the override's path
    step("r14", {PATCHED: "p2\n", PAGE: "oA\n", FOLDER_OF_OWNED: "fa\n"})
    step("r15", {FOLDER_OF_OWNED: None, PAGE: "oB\n", BELOW_OWNED: "fb\n"})
    step("r16", {BELOW_OWNED: None, PAGE: "oT\n", EXTRA_TOC: "## Title: Extra\n"})

    retail = new_repository(path)
    commits = stream.write(retail)
    git(retail, "update-ref", "refs/heads/side", commits["s1"])
    return retail, commits


def build_classic(path):
    """One Classic commit per mirrored state; returns (repo, {state: commit})."""
    stream = Stream()
    previous = []

    def state(name, mirrored, patched, page, options_toc=TOC_SIX, extra=None):
        files = {
            # The core TOC is an override: Classic's own copy, pinned to Retail's (never changing) blob.
            CORE + "/" + CORE + "_Mainline.toc": "## Version: 1\nKernel\\Mirrored.lua\nGame\\Classic\\Owned.lua\n",
            OPTIONS + "/" + OPTIONS + "_Mainline.toc": options_toc,
            ASSISTANT + "/" + ASSISTANT + "_Mainline.toc": "## Title: Assistant\n",
            MIRRORED: mirrored, PATCHED: "p Classic\n", PAGE: page, OWNED: OWNED_TEXT,
            # CRLF, as a Windows checkout writes the manifests.
            "tools/classic-retail-overrides.tsv": "%s\t%s\r\n%s\t%s\r\n" % (
                CORE + "/" + CORE + "_Mainline.toc", blob_id("## Version: 1\nKernel\\Mirrored.lua\n"),
                PATCHED, blob_id(patched)),
            "tools/classic-owned-addon-paths.txt": OWNED + "\r\n",
        }
        files.update(extra or {})
        stream.commit(name, files, tuple(previous[-1:]))
        previous.append(name)

    state("k3", "a2\n", "p1\n", "o1\n", TOC_ONE, {DELETED: "d1\n"})
    state("k4", "a2\n", "p2\n", "o1\n", TOC_ONE, {DELETED: "d1\n"})
    state("ks1", "a3\n", "p2\n", "o1\n")
    state("k8", "a3\n", "p2\n", "o7\n")
    state("knone", "a3\n", "p2\n", "o-local\n")
    state("k10", "a3\n", "p2\n", "o10\n")
    state("k11", "a3\n", "p2\n", "o10\n", extra={ADDED: "n11\n"})
    state("kfolder", "a3\n", "p2\n", "oA\n", extra={ADDED: "n11\n", FOLDER_OF_OWNED: "fa\n"})
    state("kbelow", "a3\n", "p2\n", "oB\n", extra={ADDED: "n11\n", BELOW_OWNED: "fb\n"})
    state("ktoc", "a3\n", "p2\n", "oT\n", extra={ADDED: "n11\n", EXTRA_TOC: "## Title: Extra\n"})

    classic = new_repository(path)
    return classic, stream.write(classic)


def resolve(classic, retail, classic_rev, *extra, retail_rev="main"):
    command = [sys.executable, str(TOOL), "--classic", str(classic), "--retail", str(retail),
               "--retail-rev", retail_rev, "--classic-rev", classic_rev] + list(extra)
    process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return process.returncode, process.stdout, process.stderr.decode("utf-8", "replace").replace("\r\n", "\n")


def main():
    if not TOOL.is_file():
        print("resolver is missing: %s" % TOOL)
        return 1
    root = Path(tempfile.mkdtemp(prefix="msuf-resolver-smoke-")).resolve()
    try:
        retail, commits = build_retail(root / "retail")
        classic, states = build_classic(root / "classic")
        name_of = {sha: name for name, sha in commits.items()}

        print("fixture")
        check(git(retail, "ls-tree", "--format=%(objectmode)", commits["r12"], "--", MIRRORED) == "100755"
              and git(classic, "ls-tree", "--name-only", states["kbelow"], "--", CORE + "/Game/Classic/").split("\n")
              == [OWNED, CORE + "/Game/Classic/owned.lua"],
              "the fixture holds the executable file and the case-variant paths")

        def named(output):
            return name_of.get(output.decode("ascii", "replace").strip(), output[:60])

        def expect(state, wanted, why):
            code, output, errors = resolve(classic, retail, states[state])
            found = named(output)
            check(code == 0 and found == wanted, "%s resolves to %s: %s (got exit %d, %s)%s" % (
                state, wanted, why, code, found, "" if code == 0 else "\n" + errors))
            return code, output

        def expect_none(state, nearest, kind, path, why):
            code, output, errors = resolve(classic, retail, states[state])
            listed = re.search(r"^  %s +%s \(" % (re.escape(kind), re.escape(path)), errors, re.M) is not None
            check(code == 2 and output == b"" and ("Nearest: %s " % commits[nearest][:7]) in errors
                  and ", 1 mismatching path:" in errors and listed,
                  "%s matches no commit: %s; the nearest is %s with the one mismatch '%s %s' (got exit %d, %s)%s" % (
                      state, why, nearest, kind, path, code, named(output), "" if code == 2 else "\n" + errors))

        print("newest matching commit, one rule at a time")
        code, output = expect("k3", "r3", "r3 only touches README.md, so it shares r2's addon tree and is newer; "
                                          "r4 differs from k3 only in the override's recorded base")
        check(re.match(rb"^[0-9a-f]{40}\n$", output) is not None,
              "stdout is exactly the full commit id and one LF, nothing else")
        expect("k4", "r4", "r5 deleted a file k4 still mirrors (the Classic half of the inventory rule)")
        expect("ks1", "s1", "s1 is reachable only through the merge's second parent")
        expect("k8", "r8", "r9 adds a path k8 owns (the ownership collision rule); the Options TOC matches "
                           "only through the _Mainline.toc mapping")
        expect("k10", "r10", "r11 adds a file k10 does not have (the Retail half of the inventory rule)")
        expect("k11", "r11", "r12 only makes a mirrored file executable (the file mode rule), and r13 only "
                             "deletes the path of an override row (the override path rule)")

        print("rules no state can pass")
        expect_none("kfolder", "r14", "owned", FOLDER_OF_OWNED,
                    "Retail's file is named like a folder of the owned path")
        expect_none("kbelow", "r15", "owned", BELOW_OWNED,
                    "Retail's file lies below a folder named like the owned path")
        expect_none("ktoc", "r16", "TOCs", "(tree)", "Retail carries a fourth TOC")

        print("no match")
        code, output, errors = resolve(classic, retail, states["knone"])
        check(code == 2 and output == b"", "a mirrored file that no commit has is exit code 2 with empty stdout "
              "(got %d)" % code)
        check(("Nearest: %s " % commits["r10"][:7]) in errors and PAGE in errors and "differs" in errors,
              "the diagnostic names the nearest commit, r10 (newest of r8 and r10 with one mismatch), and "
              "the differing path")
        code, output, errors = resolve(classic, retail, states["k3"], "--max-commits", "3")
        check(code == 2 and "none of the newest 3 commits" in errors,
              "--max-commits bounds the search (got %d)" % code)

        print("errors")
        code, output, errors = resolve(classic, retail, "no-such-revision")
        check(code == 1 and "names no commit" in errors, "an unknown Classic revision is exit code 1")
        code, output, errors = resolve(classic, retail, "HEAD", retail_rev="no-such-branch")
        check(code == 1 and "names no commit" in errors, "an unknown Retail revision is exit code 1")

        print("object database only")
        partial = root / "retail-partial"
        url = "file://" + retail.as_posix() if retail.as_posix().startswith("/") else "file:///" + retail.as_posix()
        git(root, "clone", "-q", "--filter=blob:none", "--no-checkout", "--branch", "main", url, str(partial))
        # Without the promisor remote a blob read cannot be fetched and fails.
        git(partial, "remote", "remove", "origin")
        code, output, errors = resolve(classic, partial, states["k8"], retail_rev="HEAD")
        check(code == 0 and output.decode("ascii", "replace").strip() == commits["r8"],
              "a blob-less clone is enough: no blob is read (got %d)%s" % (code, "" if code == 0 else "\n" + errors))
    finally:
        remove_tree(root)

    print()
    if failures:
        print("resolve_classic_retail_source smoke: %d FAILED" % len(failures))
        for message in failures:
            print("  " + message)
        return 1
    print("resolve_classic_retail_source smoke: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
