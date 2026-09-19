#!/usr/bin/env python3
"""Find the Retail commit that the Classic addon tree mirrors.

The full Classic gate (tools/test-classic-prototype.ps1 -RetailReferenceRoot)
compares the Classic addon folders with a clean checkout of exactly the Retail
commit they mirror. No tracked file records that commit: the Retail-Source
trailer of a sync commit goes stale as soon as a later rebase commit moves an
override. This script derives the commit from the trees instead. It walks the
history of a Retail revision newest first (--date-order, every parent, so a
commit that reached main through a merge counts) and prints the newest commit
whose addon tree matches the Classic tree under the gate's own rules:

- Retail's <Folder>/<Base>.toc is Classic's <Folder>/<Base>_Mainline.toc for
  the three addons (Convert-RetailPath in the gate); every other Retail path
  keeps its name;
- a row of tools/classic-retail-overrides.tsv matches when Retail's blob
  equals the recorded base blob; the Classic file itself may differ;
- every other mapped Retail path matches when Classic's blob equals Retail's;
- the Classic addon inventory is the mapped Retail paths plus the paths of
  tools/classic-owned-addon-paths.txt, and no Retail path collides with an
  owned one;
- the Retail tree holds exactly the three unsuffixed TOCs, and only regular,
  non-executable files.

Commits that change nothing below the addon folders share their addon tree
with their parent; the newest of them is printed, and the gate gives the same
answer for each of them.

Both sides are read through the object database only: Classic at --classic-rev
(default HEAD, so uncommitted edits do not count), Retail at every commit
reachable from --retail-rev. No blob is read, so a Retail clone made with
--filter=blob:none is enough.

Typical run, from the Classic repository root:

    python .github/scripts/resolve_classic_retail_source.py --retail <Retail clone> --retail-rev origin/main

On success the only line on stdout is the full commit id; progress goes to
stderr. Exit code: 0 found; 2 no commit among the newest --max-commits matches,
and stderr names the nearest commit with its mismatching paths; 1 usage,
manifest or git error.

Smoke: python tools/tests/resolve_classic_retail_source_smoke.py <repository root>
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

OVERRIDES_MANIFEST = "tools/classic-retail-overrides.tsv"
OWNED_MANIFEST = "tools/classic-owned-addon-paths.txt"

# (Folder, Base) of the three addons, exactly as $targets in
# tools/test-classic-prototype.ps1 and ADDON_TARGETS in
# tools/rebase-classic-overrides.py.
ADDON_TARGETS = (
    ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames"),
    ("MidnightSimpleUnitFrames_Options", "MidnightSimpleUnitFrames_Options"),
    ("MidnightSimpleUnitFrames_Assistant", "MidnightSimpleUnitFrames_Assistant"),
)
ADDON_FOLDERS = tuple(folder for folder, _ in ADDON_TARGETS)
RETAIL_TOCS = {"%s/%s.toc" % target: "%s/%s_Mainline.toc" % target for target in ADDON_TARGETS}

DEFAULT_MAX_COMMITS = 1000
REPORT_LIMIT = 25
OBJECT_ID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")


class ToolError(Exception):
    """Usage, manifest or git failure: exit code 1."""


class UsageParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, "%s: error: %s\n" % (self.prog, message))


def say(text=""):
    print(text, file=sys.stderr)


def run_git(repo, arguments, stdin=None, accept=(0,)):
    command = ["git", "-C", str(repo)] + list(arguments)
    try:
        process = subprocess.run(command, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        raise ToolError("git was not found on PATH")
    if process.returncode not in accept:
        raise ToolError("%s failed with exit code %d:\n%s" % (
            " ".join(command), process.returncode, process.stderr.decode("utf-8", "replace").strip()))
    return process


def resolve_commit(repo, revision, label):
    process = run_git(repo, ["rev-parse", "--verify", "--quiet", revision + "^{commit}"], accept=(0, 1, 128))
    commit = process.stdout.decode("ascii", "replace").strip()
    if process.returncode != 0 or not OBJECT_ID.match(commit):
        raise ToolError("%s '%s' names no commit in %s" % (label, revision, repo))
    return commit


def parse_tree_listing(output, prefix=""):
    """`git ls-tree -r -z` records as (mode, type, object, path)."""
    entries = []
    for record in output.split(b"\0"):
        if not record:
            continue
        meta, _, raw_path = record.partition(b"\t")
        mode, kind, object_id = meta.decode("ascii").split()
        entries.append((mode, kind, object_id, prefix + raw_path.decode("utf-8")))
    return entries


def read_manifest_lines(repo, revision, relative):
    process = run_git(repo, ["cat-file", "blob", "%s:%s" % (revision, relative)], accept=(0, 128))
    if process.returncode != 0:
        raise ToolError("%s is missing from the Classic commit %s" % (relative, revision))
    text = process.stdout.decode("utf-8")
    if text.startswith("\ufeff"):
        raise ToolError("%s starts with a byte order mark" % relative)
    return [line for line in text.replace("\r\n", "\n").split("\n") if line]


class ClassicTree:
    """The Classic side at one commit: addon blobs, override bases, owned paths."""

    def __init__(self, repo, revision):
        self.commit = resolve_commit(repo, revision, "Classic revision")
        listing = run_git(repo, ["ls-tree", "-r", "-z", self.commit, "--"] + list(ADDON_FOLDERS)).stdout
        self.blobs = {path: object_id for _, kind, object_id, path in parse_tree_listing(listing) if kind == "blob"}
        self.overrides = {}
        for line in read_manifest_lines(repo, self.commit, OVERRIDES_MANIFEST):
            fields = line.split("\t")
            if len(fields) != 2 or not OBJECT_ID.match(fields[1]):
                raise ToolError("%s: expected path<TAB>Retail-base-blob, got %r" % (OVERRIDES_MANIFEST, line))
            self.overrides[fields[0]] = fields[1]
        self.owned = set(read_manifest_lines(repo, self.commit, OWNED_MANIFEST))
        self.owned_folded = {path.casefold() for path in self.owned}
        self.owned_folders = {folder for path in self.owned_folded for folder in parent_folders(path)}


def parent_folders(path):
    parts = path.split("/")
    return ["/".join(parts[:index]) for index in range(1, len(parts))]


def evaluate(entries, classic):
    """Mismatches between one Retail addon tree and the Classic tree, as (kind, path, detail)."""
    problems = []
    mapped = {}
    tocs = set()
    for mode, kind, object_id, path in entries:
        if kind != "blob" or mode != "100644":
            problems.append(("file mode", path, "Retail has %s %s; the gate takes regular non-executable files only"
                             % (mode, kind)))
            continue
        if path.casefold().endswith(".toc"):
            tocs.add(path)
        mapped[RETAIL_TOCS.get(path, path)] = object_id
    if tocs != set(RETAIL_TOCS):
        problems.append(("TOCs", "(tree)", "Retail has %s; the gate needs exactly %s" % (
            ", ".join(sorted(tocs)) or "no TOC", ", ".join(sorted(RETAIL_TOCS)))))
    for path, base in sorted(classic.overrides.items()):
        retail_blob = mapped.get(path)
        if retail_blob is None:
            problems.append(("override", path, "the override row names a path Retail does not have"))
        elif retail_blob != base:
            problems.append(("override base", path, "recorded %s, Retail has %s" % (base[:10], retail_blob[:10])))
    for path in sorted(mapped):
        folded = path.casefold()
        if (folded in classic.owned_folded or folded in classic.owned_folders
                or any(folder in classic.owned_folded for folder in parent_folders(folded))):
            problems.append(("owned", path, "Retail has a path that collides with a Classic-owned path"))
        elif path in classic.overrides:
            continue
        elif path not in classic.blobs:
            problems.append(("missing", path, "Retail has it, the Classic tree does not"))
        elif classic.blobs[path] != mapped[path]:
            problems.append(("differs", path, "Classic %s, Retail %s" % (classic.blobs[path][:10], mapped[path][:10])))
    for path in sorted(classic.blobs):
        if path not in mapped and path not in classic.owned and path not in classic.overrides:
            problems.append(("not in Retail", path, "the Classic tree has it, but it is neither owned nor in Retail"))
    return problems


class RetailHistory:
    """Retail addon trees per commit, listed once per distinct folder tree."""

    def __init__(self, repo):
        self.repo = repo
        self.listings = {}

    def folder_trees(self, commits):
        """(Folder tree id or None) triple per commit, from one cat-file process."""
        requests = "".join("%s:%s\n" % (commit, folder) for commit in commits for folder in ADDON_FOLDERS)
        output = run_git(self.repo, ["cat-file", "--batch-check=%(objectname) %(objecttype)"],
                         stdin=requests.encode("utf-8")).stdout.decode("utf-8").split("\n")
        answers = [line for line in output if line]
        if len(answers) != len(commits) * len(ADDON_FOLDERS):
            raise ToolError("git cat-file answered %d of %d tree lookups" % (
                len(answers), len(commits) * len(ADDON_FOLDERS)))
        triples = []
        for index in range(len(commits)):
            triple = []
            for answer in answers[index * len(ADDON_FOLDERS):(index + 1) * len(ADDON_FOLDERS)]:
                words = answer.split()
                triple.append(words[0] if len(words) == 2 and words[1] == "tree" else None)
            triples.append(tuple(triple))
        return triples

    def entries(self, triple):
        result = []
        for folder, tree in zip(ADDON_FOLDERS, triple):
            if tree is None:
                continue
            if tree not in self.listings:
                listing = run_git(self.repo, ["ls-tree", "-r", "-z", tree]).stdout
                self.listings[tree] = parse_tree_listing(listing, folder + "/")
            result.extend(self.listings[tree])
        return result


def describe_commit(repo, commit):
    line = run_git(repo, ["log", "-1", "--format=%h %cd %s", "--date=short", commit]).stdout
    return line.decode("utf-8", "replace").strip()


def parse_arguments(argv):
    parser = UsageParser(
        description="Print the newest Retail commit whose addon tree the Classic tree mirrors.",
        epilog="Exit code: 0 found (stdout is the commit id), 2 nothing matched within --max-commits, "
               "1 usage or git error.")
    parser.add_argument("--retail", required=True,
                        help="a Retail clone with the history to search; only its object database is read")
    parser.add_argument("--retail-rev", default="HEAD",
                        help="Retail revision whose history is searched, newest first (default: HEAD)")
    parser.add_argument("--classic", default=str(Path(__file__).resolve().parents[2]),
                        help="Classic repository (default: the repository this script lives in)")
    parser.add_argument("--classic-rev", default="HEAD", help="Classic commit to match (default: HEAD)")
    parser.add_argument("--max-commits", type=int, default=DEFAULT_MAX_COMMITS,
                        help="how many Retail commits to search before giving up (default: %d)" % DEFAULT_MAX_COMMITS)
    arguments = parser.parse_args(argv)
    if arguments.max_commits < 1:
        parser.error("--max-commits must be at least 1")
    return arguments


def run(arguments):
    classic_repo = Path(arguments.classic).resolve()
    retail_repo = Path(arguments.retail).resolve()
    for label, path in (("Classic repository", classic_repo), ("Retail repository", retail_repo)):
        if not path.is_dir():
            raise ToolError("%s is not a directory: %s" % (label, path))

    classic = ClassicTree(classic_repo, arguments.classic_rev)
    say("Classic tree: %s at %s; %d addon paths, %d override rows, %d owned paths" % (
        arguments.classic_rev, classic.commit[:10], len(classic.blobs), len(classic.overrides), len(classic.owned)))

    head = resolve_commit(retail_repo, arguments.retail_rev, "Retail revision")
    commits = run_git(retail_repo, ["rev-list", "--date-order", "--max-count=%d" % arguments.max_commits,
                                    head]).stdout.decode("ascii").split()
    history = RetailHistory(retail_repo)
    triples = history.folder_trees(commits)
    say("Retail history: %s at %s; searching the newest %d commits" % (arguments.retail_rev, head[:10], len(commits)))

    verdicts = {}
    nearest = None
    for position, (commit, triple) in enumerate(zip(commits, triples)):
        if triple not in verdicts:
            verdicts[triple] = evaluate(history.entries(triple), classic)
        problems = verdicts[triple]
        if not problems:
            say("Retail source: %s" % describe_commit(retail_repo, commit))
            say("  %d newer commit%s of %s did not match; %d distinct addon trees compared" % (
                position, "" if position == 1 else "s", arguments.retail_rev, len(verdicts)))
            # Bytes, so the line ends in LF on every system and a shell capture
            # on Windows gets no trailing CR.
            sys.stdout.flush()
            sys.stdout.buffer.write((commit + "\n").encode("ascii"))
            sys.stdout.buffer.flush()
            return 0
        if nearest is None or len(problems) < len(nearest[1]):
            nearest = (commit, problems)

    commit, problems = nearest
    say("error: none of the newest %d commits of %s matches the Classic tree at %s under the gate's rules."
        % (len(commits), arguments.retail_rev, classic.commit[:10]))
    say("Nearest: %s, %d mismatching path%s:" % (
        describe_commit(retail_repo, commit), len(problems), "" if len(problems) == 1 else "s"))
    for kind, path, detail in problems[:REPORT_LIMIT]:
        say("  %-14s %s (%s)" % (kind, path, detail))
    if len(problems) > REPORT_LIMIT:
        say("  ... and %d more" % (len(problems) - REPORT_LIMIT))
    say("A mirrored file changed without an override row, an override records a base blob no searched commit has,")
    say("or the mirrored commit is older than the search window (raise --max-commits).")
    return 2


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    arguments = parse_arguments(argv)
    try:
        return run(arguments)
    except (ToolError, OSError, UnicodeDecodeError) as error:
        print("error: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
