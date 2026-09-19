#!/usr/bin/env python3
"""Rebase Classic's overrides of Retail files onto a Retail revision.

tools/classic-retail-overrides.tsv lists every Retail file that Classic edits,
next to the Retail blob those edits were last reconciled with. Retail's sync
script (.github/scripts/Sync-ClassicRetail.ps1 in the Retail repo) refuses to
run as soon as Retail changes one of those files. This tool redoes the
reconciliation for every row whose Retail blob moved:

    base   = the recorded Retail blob
    ours   = the Classic working file
    theirs = the Retail blob at --retail-rev

A clean `git merge-file` result is written back and the row moves to the new
blob. A conflict leaves the file and the row alone and is reported. Generated
files are never merged. A row whose file equals Retail's blob no longer
overrides anything and is dropped. tools/classic-owned-shadows.tsv gets the same
merge, report-only unless --write-shadows is passed.

Retail is read through its object database only (rev-parse, ls-tree, cat-file,
log), never through a working tree, so a Retail checkout with edits in flight
is safe to point at. Nothing is written into the Classic checkout without
--write or --write-shadows.

A clean merge is a textual result, not a review: read `git diff` and run the
full Classic gate before committing. The tool never stages or commits.

Typical run, from the Classic repo root:

    python tools/rebase-classic-overrides.py --retail <retail repo>
    python tools/rebase-classic-overrides.py --retail <retail repo> --write --conflict-dir <scratch dir>
    ... merge the reported conflicts by hand, regenerate the generated files ...
    python tools/rebase-classic-overrides.py --retail <retail repo> --write --resolved <path> [--resolved <path> ...]

Exit code: 0 nothing is left to do by hand, 2 conflicts or generated files
remain, 1 usage, manifest or git error. Shadow results count only with
--write-shadows. The last output line is the commit trailer to use.

Self-test: python tools/tests/rebase_classic_overrides_smoke.py (the Classic gate runs it)
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

OVERRIDES_MANIFEST = "tools/classic-retail-overrides.tsv"
SHADOWS_MANIFEST = "tools/classic-owned-shadows.tsv"
OWNED_MANIFEST = "tools/classic-owned-addon-paths.txt"

# (Folder, Base) of the three addons, exactly as $targets in Retail's
# Sync-ClassicRetail.ps1 and in tools/test-classic-prototype.ps1. Retail ships
# one unsuffixed TOC per addon; Classic keeps that file as <Base>_Mainline.toc.
ADDON_TARGETS = (
    ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames"),
    ("MidnightSimpleUnitFrames_Options", "MidnightSimpleUnitFrames_Options"),
    ("MidnightSimpleUnitFrames_Assistant", "MidnightSimpleUnitFrames_Assistant"),
)
ADDON_FOLDERS = tuple(folder for folder, _ in ADDON_TARGETS)

# Generated files. Both sides rewrite them wholesale (counters, hashes, release
# history), so a line merge conflicts by construction or, worse, merges into a
# payload no generator would produce. They are reported as "regenerate" and
# never merged. Add a path here when another generated file becomes an override
# or a shadow.
GENERATED_PATHS = frozenset((
    # The two changelog payloads (tools/update-addon-changelog.ps1).
    "MidnightSimpleUnitFrames/State/MSUF_Changelog.lua",
    "MidnightSimpleUnitFrames_Options/State/MSUF_ChangelogFull.lua",
    # Menu2 search index (.github/scripts/search_static_index_project.lua).
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua",
    # Assistant control schema (tools/generate_assistant_control_schema.ps1).
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data.lua",
    # Assistant auto-coverage manifest (external coverage harness).
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_AutoCoverage_Manifest.lua",
))

BLOB_ID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
RETAIL_SOURCE_TRAILER = re.compile(r"(?im)^Retail-Source:\s*([0-9a-f]{40})\s*$")
CONFLICT_MARKER = {
    "open": re.compile(rb"(?m)^<{7}(?: |$)"),
    "close": re.compile(rb"(?m)^>{7}(?: |$)"),
}

# Row outcomes. The first group is applied by --write / --write-shadows, the
# second group is what stays for a human.
MERGED = "merged"          # clean merge, the file changes
CARRIED = "carried"        # clean merge, the file already holds Retail's change
RESOLVED = "resolved"      # merged by hand, confirmed with --resolved
NOOP = "no-op"             # the file equals Retail's blob: the row is dropped
CONFLICT = "CONFLICT"
REGENERATE = "REGENERATE"
REMOVED = "REMOVED"        # Retail no longer has the file
BINARY = "BINARY"
AUTOMATIC = (MERGED, CARRIED, RESOLVED, NOOP)
BY_HAND = (CONFLICT, REGENERATE, REMOVED, BINARY)


class ToolError(Exception):
    """Usage, manifest or git failure: exit code 1."""


class UsageParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, "%s: error: %s\n" % (self.prog, message))


@dataclass
class RetailEntry:
    source: str  # path inside the Retail tree
    blob: str


@dataclass
class Manifest:
    relative: str
    path: Path
    original: bytes
    eol: str
    final_newline: bool
    rows: list


@dataclass
class Outcome:
    path: str            # Classic path: the override, or the owned shadow
    retail_key: str      # Retail counterpart in Classic's path space
    recorded: str
    status: str
    current: str = ""    # Retail blob at the revision, "" when Retail removed the file
    source: str = ""     # Retail's own path of the counterpart
    detail: str = ""
    content: bytes = b""          # what a write puts into the file (MERGED only)
    conflict_text: bytes = b""    # merge result with diff3 markers (CONFLICT only)


# --------------------------------------------------------------------------
# git and file helpers


def run_git(arguments, repo=None, cwd=None, stdin=None, accept=(0,)):
    command = ["git"]
    if repo is not None:
        command += ["-C", str(repo)]
    command += list(arguments)
    try:
        process = subprocess.run(command, input=stdin, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, cwd=cwd)
    except FileNotFoundError:
        raise ToolError("git was not found on PATH")
    if process.returncode not in accept:
        raise ToolError("%s failed with exit code %d:\n%s" % (
            " ".join(command), process.returncode,
            process.stderr.decode("utf-8", "replace").strip()))
    return process


def ordinal_key(text):
    """Sort key equal to .NET's StringComparer.Ordinal (UTF-16 code units).

    Retail's sync script and the Classic gate both reject a manifest that is
    not in that order. The sync script sorts whole lines and the gate sorts
    the first column; the two agree because a TAB sorts below every character
    check_addon_path allows in a path.
    """
    return text.encode("utf-16-be")


def to_lf(data):
    return data.replace(b"\r\n", b"\n")


def uses_crlf(data):
    """(file is CRLF, file mixes both styles) for a working file."""
    crlf = data.count(b"\r\n")
    lf = data.count(b"\n") - crlf
    return crlf > lf, crlf > 0 and lf > 0


def in_style_of(lf_data, working):
    crlf, _ = uses_crlf(working)
    return lf_data.replace(b"\n", b"\r\n") if crlf else lf_data


def check_addon_path(path, label):
    """Assert-NormalizedAddonPath of the sync script, plus no control characters."""
    if (not path or path != path.strip() or "\\" in path or path.startswith("/") or path.endswith("/")
            or "//" in path or any(part in (".", "..") for part in path.split("/"))
            or any(ord(character) < 32 for character in path)
            or not any(path.startswith(folder + "/") for folder in ADDON_FOLDERS)):
        raise ToolError("%s is not a normalized file path below an addon folder: %r" % (label, path))


def is_inside(child, parent):
    try:
        return os.path.commonpath([str(parent), str(child)]) == str(parent)
    except ValueError:  # different drives
        return False


def working_file(root, relative):
    full = (root / relative).resolve()
    if not is_inside(full, root):
        raise ToolError("path escapes the Classic root: %s" % relative)
    return full


def write_atomic(target, data):
    """Replace target in one step, so an interrupted run never leaves half a file."""
    handle, temporary = tempfile.mkstemp(prefix=target.name + ".", suffix=".tmp", dir=str(target.parent))
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(data)
        shutil.copymode(str(target), temporary)
        os.replace(temporary, str(target))
    except BaseException:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise


# --------------------------------------------------------------------------
# Retail side: object database only


def resolve_retail_commit(retail, revision):
    process = run_git(["rev-parse", "--verify", "--quiet", revision + "^{commit}"], repo=retail, accept=(0, 1, 128))
    commit = process.stdout.decode("ascii", "replace").strip()
    if process.returncode != 0 or not BLOB_ID.match(commit):
        raise ToolError("'%s' names no commit in the Retail repository %s" % (revision, retail))
    return commit


def read_retail_tree(retail, commit):
    """Retail's addon files at the commit, keyed by their Classic path.

    The key is Convert-RetailPath of the sync script: <Folder>/<Base>.toc is
    <Folder>/<Base>_Mainline.toc in Classic, every other path is unchanged.
    Looking a Classic TOC up under its own name would find nothing, and a
    merge against an empty "theirs" guts the file.
    """
    unsuffixed = {"%s/%s.toc" % target: "%s/%s_Mainline.toc" % target for target in ADDON_TARGETS}
    output = run_git(["ls-tree", "-r", "-z", commit, "--"] + list(ADDON_FOLDERS), repo=retail).stdout
    tree = {}
    tocs = set()
    for record in output.split(b"\0"):
        if not record:
            continue
        meta, _, raw_path = record.partition(b"\t")
        _, kind, blob = meta.decode("ascii").split()
        if kind != "blob":
            continue
        source = raw_path.decode("utf-8")
        key = unsuffixed.get(source, source)
        if key in tree:
            raise ToolError("Retail paths %s and %s both map to %s" % (tree[key].source, source, key))
        tree[key] = RetailEntry(source, blob)
        if source.lower().endswith(".toc"):
            tocs.add(source)
    if tocs != set(unsuffixed):
        raise ToolError(
            "%s is not a Retail tree: expected exactly the unsuffixed TOCs %s, found %s. "
            "Pass the Retail commit with --retail-rev." % (
                commit[:8], ", ".join(sorted(unsuffixed)), ", ".join(sorted(tocs)) or "none"))
    return tree


def read_blob(retail, blob, purpose):
    process = run_git(["cat-file", "blob", blob], repo=retail, accept=(0, 1, 128))
    if process.returncode != 0:
        raise ToolError("%s: blob %s is not in the Retail repository %s" % (purpose, blob, retail))
    return process.stdout


# --------------------------------------------------------------------------
# Classic side


def read_manifest(root, relative, columns):
    path = root / relative
    if not path.is_file():
        raise ToolError("%s is missing below %s" % (relative, root))
    original = path.read_bytes()
    if original.startswith(b"\xef\xbb\xbf"):
        raise ToolError("%s starts with a byte order mark" % relative)
    try:
        text = original.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ToolError("%s is not UTF-8: %s" % (relative, error))
    eol = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    final_newline = lines[-1] == ""
    if final_newline:
        lines.pop()
    rows = []
    seen = {}
    for number, line in enumerate(lines, 1):
        fields = tuple(line.split("\t"))
        where = "%s:%d" % (relative, number)
        if len(fields) != columns:
            raise ToolError("%s: expected %d TAB-separated fields" % (where, columns))
        for field in fields[:-1]:
            check_addon_path(field, where)
        if not BLOB_ID.match(fields[-1]):
            raise ToolError("%s: the last field must be a lower-case Git blob id" % where)
        folded = fields[0].casefold()
        if folded in seen:
            raise ToolError("%s: duplicate or case-colliding path %s (line %d)" % (where, fields[0], seen[folded]))
        seen[folded] = number
        rows.append(fields)
    return Manifest(relative, path, original, eol, final_newline, rows)


def render_manifest(manifest, rows):
    ordered = sorted(rows, key=lambda row: ordinal_key(row[0]))
    text = manifest.eol.join("\t".join(row) for row in ordered)
    if ordered and manifest.final_newline:
        text += manifest.eol
    return text.encode("utf-8")


def hash_as_blobs(root, contents):
    """`git hash-object` ids of byte strings, one git call, no filters."""
    if not contents:
        return []
    with tempfile.TemporaryDirectory(prefix="msuf-rebase-hash-") as scratch:
        names = []
        for index, content in enumerate(contents):
            name = Path(scratch) / ("%05d" % index)
            name.write_bytes(content)
            names.append(name.as_posix())
        output = run_git(["hash-object", "--no-filters", "--stdin-paths"], repo=root,
                         stdin=("\n".join(names) + "\n").encode("utf-8")).stdout
    hashes = output.decode("ascii").split()
    if len(hashes) != len(contents):
        raise ToolError("git hash-object returned %d ids for %d files" % (len(hashes), len(contents)))
    return hashes


def three_way_merge(ours, base, theirs, labels):
    """git merge-file -p --diff3 on LF temp copies: (conflict count, merged bytes)."""
    with tempfile.TemporaryDirectory(prefix="msuf-rebase-merge-") as scratch:
        for name, content in (("ours", ours), ("base", base), ("theirs", theirs)):
            (Path(scratch) / name).write_bytes(content)
        process = run_git(
            ["merge-file", "-p", "--diff3", "-L", labels[0], "-L", labels[1], "-L", labels[2],
             "ours", "base", "theirs"],
            cwd=scratch, accept=tuple(range(128)))
    return process.returncode, process.stdout


def has_conflict_markers(data):
    return bool(CONFLICT_MARKER["open"].search(data) and CONFLICT_MARKER["close"].search(data))


# --------------------------------------------------------------------------
# Planning


class Planner:
    def __init__(self, classic, retail, commit, tree, resolved):
        self.classic = classic
        self.retail = retail
        self.commit = commit
        self.tree = tree
        self.resolved = resolved
        self.used_resolved = set()

    def removed(self, path, retail_key, recorded, advice):
        """Retail deleted the counterpart: what happens to the Classic file is a
        decision, so its row is edited by hand."""
        detail = "Retail no longer has %s: %s" % (retail_key, advice)
        if path in self.resolved:
            self.used_resolved.add(path)
            detail += "; --resolved cannot settle a removal"
        return Outcome(path, retail_key, recorded, REMOVED, detail=detail)

    def reconcile(self, path, retail_key, recorded, working):
        """Outcome for a file whose Retail counterpart moved away from `recorded`."""
        entry = self.tree[retail_key]
        outcome = Outcome(path, retail_key, recorded, CONFLICT, entry.blob, entry.source)
        if path in self.resolved:
            self.used_resolved.add(path)
            if has_conflict_markers(to_lf(working)):
                outcome.detail = "--resolved refused: the file still holds conflict markers"
            else:
                outcome.status = RESOLVED
            return outcome
        if path in GENERATED_PATHS or retail_key in GENERATED_PATHS:
            outcome.status = REGENERATE
            outcome.detail = "generated file: regenerate it (or port Retail's delta), then pass --resolved"
            return outcome
        base = read_blob(self.retail, recorded, "%s (recorded base)" % path)
        theirs = read_blob(self.retail, entry.blob, "%s (Retail %s)" % (path, self.commit[:8]))
        if b"\0" in working or b"\0" in base or b"\0" in theirs:
            outcome.status = BINARY
            outcome.detail = "binary content cannot be line merged"
            return outcome
        labels = ("Classic: " + path, "Retail base " + recorded[:8],
                  "Retail %s: %s" % (self.commit[:8], entry.source))
        conflicts, merged = three_way_merge(to_lf(working), to_lf(base), to_lf(theirs), labels)
        if conflicts:
            outcome.detail = "%d conflict%s" % (conflicts, "" if conflicts == 1 else "s")
            outcome.conflict_text = in_style_of(merged, working)
        elif merged == to_lf(working):
            outcome.status = CARRIED
        else:
            outcome.status = MERGED
            outcome.content = in_style_of(merged, working)
            if uses_crlf(working)[1]:
                outcome.detail = "the file mixed LF and CRLF; written with its dominant style"
        return outcome

    def plan_overrides(self, manifest):
        workings = [working_file(self.classic, row[0]) for row in manifest.rows]
        for row, full in zip(manifest.rows, workings):
            if not full.is_file():
                raise ToolError("%s lists %s, which is missing from the Classic working tree" % (
                    manifest.relative, row[0]))
        contents = [full.read_bytes() for full in workings]
        # LF-normalized like the blob git would store; binary content is hashed as it is.
        hashes = hash_as_blobs(self.classic, [content if b"\0" in content else to_lf(content)
                                              for content in contents])
        outcomes = []
        for (path, recorded), working, blob in zip(manifest.rows, contents, hashes):
            entry = self.tree.get(path)
            if entry is None:
                outcomes.append(self.removed(
                    path, path, recorded,
                    "delete the file with its row, or keep the file and declare it in %s instead" % OWNED_MANIFEST))
            elif blob == entry.blob:
                outcomes.append(Outcome(path, path, recorded, NOOP, entry.blob, entry.source))
            elif entry.blob != recorded:
                outcomes.append(self.reconcile(path, path, recorded, working))
        return outcomes

    def plan_shadows(self, manifest):
        outcomes = []
        for path, retail_key, recorded in manifest.rows:
            entry = self.tree.get(retail_key)
            if entry is None:
                outcomes.append(self.removed(
                    path, retail_key, recorded,
                    "decide whether the shadow is still needed, then update or remove its row"))
            elif entry.blob != recorded:
                full = working_file(self.classic, path)
                if not full.is_file():
                    raise ToolError("%s lists %s, which is missing from the Classic working tree" % (
                        manifest.relative, path))
                outcomes.append(self.reconcile(path, retail_key, recorded, full.read_bytes()))
        return outcomes


def planned_rows(manifest, outcomes):
    """The manifest rows after every automatic outcome is applied."""
    by_path = {outcome.path: outcome for outcome in outcomes}
    rows = []
    for row in manifest.rows:
        outcome = by_path.get(row[0])
        if outcome is None or outcome.status in BY_HAND:
            rows.append(row)
        elif outcome.status != NOOP:
            rows.append(row[:-1] + (outcome.current,))
    return rows


def mirror_state(classic, tree, override_paths):
    """Mirrored paths that are not at the Retail revision yet.

    Hashed the way the Classic gate hashes them (`git hash-object` with the
    checkout's own filters), so the answer matches what the gate will say.
    """
    mirrored = sorted(key for key in tree if key not in override_paths)
    present = [key for key in mirrored if working_file(classic, key).is_file()]
    differing = []
    if present:
        output = run_git(["hash-object", "--stdin-paths"], repo=classic,
                         stdin=("\n".join(present) + "\n").encode("utf-8")).stdout
        hashes = output.decode("ascii").split()
        if len(hashes) != len(present):
            raise ToolError("git hash-object returned %d ids for %d mirrored files" % (len(hashes), len(present)))
        differing = [key for key, blob in zip(present, hashes) if blob != tree[key].blob]
    missing = sorted(set(mirrored) - set(present))
    stale = []
    owned_manifest = classic / OWNED_MANIFEST
    if owned_manifest.is_file():
        owned = set(owned_manifest.read_text(encoding="utf-8").splitlines())
        tracked = run_git(["ls-files", "-z", "--"] + list(ADDON_FOLDERS), repo=classic).stdout
        for raw in tracked.split(b"\0"):
            path = raw.decode("utf-8")
            # An override Retail removed is already reported as REMOVED.
            if path and path not in tree and path not in owned and path not in override_paths:
                stale.append(path)
    return len(mirrored), differing, missing, sorted(stale)


def newest_recorded_source(classic):
    process = run_git(["log", "-100", "--format=%B%x00"], repo=classic, accept=(0, 128))
    match = RETAIL_SOURCE_TRAILER.search(process.stdout.decode("utf-8", "replace"))
    return match.group(1).lower() if match else ""


# --------------------------------------------------------------------------
# Reporting and writing


def describe(outcome):
    move = "%s -> %s" % (outcome.recorded[:8], outcome.current[:8] if outcome.current else "gone")
    if outcome.status == MERGED:
        text = "merged clean (%s)" % move
    elif outcome.status == CARRIED:
        text = "merged clean, file unchanged: Classic already carries Retail's change (%s)" % move
    elif outcome.status == RESOLVED:
        text = "recorded as merged by hand (%s)" % move
    elif outcome.status == NOOP:
        text = "equals Retail %s: the row overrides nothing and is dropped" % outcome.current[:8]
    else:
        text = move
    if outcome.detail:
        text += "; " + outcome.detail
    return "  %-10s %s\n             %s" % (outcome.status, outcome.path, text)


def report(title, manifest, outcomes):
    counts = {}
    for outcome in outcomes:
        counts[outcome.status] = counts.get(outcome.status, 0) + 1
    current = len(manifest.rows) - len(outcomes)
    summary = ", ".join("%d %s" % (counts[status], status) for status in AUTOMATIC + BY_HAND if status in counts)
    print("%s (%s): %d rows, %d current%s" % (title, manifest.relative, len(manifest.rows), current,
                                             ", " + summary if summary else ""))
    for outcome in outcomes:
        print(describe(outcome))


def write_conflicts(directory, outcomes):
    written = 0
    for outcome in outcomes:
        if outcome.status == CONFLICT and outcome.conflict_text:
            target = directory / outcome.path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(outcome.conflict_text)
            written += 1
    return written


def apply_plan(classic, manifest, outcomes):
    """Files first, the manifest last: an interrupted run stays safe to repeat."""
    files = 0
    for outcome in outcomes:
        if outcome.status == MERGED:
            write_atomic(working_file(classic, outcome.path), outcome.content)
            files += 1
    rendered = render_manifest(manifest, planned_rows(manifest, outcomes))
    rewritten = rendered != manifest.original
    if rewritten:
        write_atomic(manifest.path, rendered)
    return files, rewritten


def parse_arguments(argv):
    parser = UsageParser(
        description="Rebase Classic's Retail overrides (and owned shadows) onto a Retail revision.",
        epilog="Exit code: 0 nothing left to do by hand, 2 conflicts or generated files remain, 1 usage or git error.")
    parser.add_argument("--classic", default=str(Path(__file__).resolve().parents[1]),
                        help="Classic repository root (default: the repository this script lives in)")
    parser.add_argument("--retail", required=True,
                        help="a Retail repository or clone; only its object database is read")
    parser.add_argument("--retail-rev", default="HEAD", help="Retail revision to rebase onto (default: HEAD)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true",
                      help="print the plan and write nothing into the Classic checkout (default)")
    mode.add_argument("--write", action="store_true",
                      help="write clean override merges and %s" % OVERRIDES_MANIFEST)
    parser.add_argument("--write-shadows", action="store_true",
                        help="also write clean shadow merges and %s (shadows are report-only otherwise)"
                        % SHADOWS_MANIFEST)
    parser.add_argument("--resolved", action="append", default=[], metavar="PATH",
                        help="override or shadow path that was merged or regenerated by hand: record the new "
                             "Retail blob without touching the file (repeatable)")
    parser.add_argument("--conflict-dir", metavar="DIR",
                        help="directory outside the Classic checkout that receives every conflicting merge "
                             "result with diff3 markers, also in a dry run")
    arguments = parser.parse_args(argv)
    if arguments.dry_run and arguments.write_shadows:
        parser.error("--dry-run and --write-shadows contradict each other")
    return arguments


def plural(count):
    return "" if count == 1 else "s"


def print_header(retail, classic, commit):
    subject = run_git(["log", "-1", "--format=%h %ad %s", "--date=short", commit], repo=retail).stdout
    print("Retail revision: %s" % subject.decode("utf-8", "replace").strip())
    print("Retail repository: %s (object database only)" % retail)
    print("Classic checkout: %s" % classic)
    print("Newest Retail-Source trailer in Classic history: %s" % (
        newest_recorded_source(classic) or "none in the last 100 commits"))
    print()
    sys.stdout.flush()


def print_mirror_state(commit, state):
    mirrored, differing, missing, stale = state
    print("Mirrored paths: %d; %d differ from Retail %s, %d missing, %d no longer in Retail" % (
        mirrored, len(differing), commit[:8], len(missing), len(stale)))
    for label, paths in (("differs", differing), ("missing", missing), ("not in Retail", stale)):
        for path in paths[:10]:
            print("  %-13s %s" % (label, path))
        if len(paths) > 10:
            print("  %-13s ... and %d more" % (label, len(paths) - 10))
    print()


def settle(classic, manifest, outcomes, write, title, switch):
    """Apply the automatic outcomes of one manifest, or say what the switch would apply."""
    pending = sum(1 for outcome in outcomes if outcome.status in AUTOMATIC)
    normalizes = render_manifest(manifest, manifest.rows) != manifest.original
    if write:
        files, rewritten = apply_plan(classic, manifest, outcomes)
        print("%s: wrote %d file%s; %s %s" % (title, files, plural(files), manifest.relative,
                                             "rewritten" if rewritten else "unchanged"))
    elif pending or normalizes:
        print("%s: nothing written; %s applies %d row%s%s" % (
            title, switch, pending, plural(pending), " and re-sorts the manifest" if normalizes else ""))
    else:
        print("%s: nothing to write" % title)


def print_by_hand(retail, by_hand, shadow_drift):
    if by_hand:
        print()
        print("Left to do by hand (%d):" % len(by_hand))
        for outcome in by_hand:
            print("  %-10s %s" % (outcome.status, outcome.path))
            if outcome.current:
                print("             base   git -C \"%s\" cat-file blob %s" % (retail, outcome.recorded))
                print("             theirs git -C \"%s\" cat-file blob %s   (%s)" % (
                    retail, outcome.current, outcome.source))
        print("  Settle each file, then record it with --resolved <path> "
              "(plus --write for an override, --write-shadows for a shadow).")
    if shadow_drift:
        print()
        print("Shadow drift left for a manual port: %d (report only; it counts for the exit code "
              "only with --write-shadows)" % shadow_drift)


def print_trailer(commit, behind, by_hand_count):
    print()
    if behind:
        print("%d mirrored path%s above %s not at Retail %s yet. Retail's Sync-ClassicRetail.ps1 takes the newest"
              % (behind, plural(behind), "is" if behind == 1 else "are", commit[:8]))
        print("trailer as the state of every mirrored file and refuses to run when one differs, so the trailer")
        print("belongs on the commit that mirrors them as well: this rebase commit if it does, else the sync commit")
        print("(then commit the rebase without it).")
    else:
        print("Every mirrored path equals Retail %s. Trailer for the commit that records this rebase%s:" % (
            commit[:8], ", once the %d item%s above %s settled" % (
                by_hand_count, plural(by_hand_count), "is" if by_hand_count == 1 else "are") if by_hand_count else ""))
    print("Retail-Source: %s" % commit)


def run(arguments):
    classic = Path(arguments.classic).resolve()
    if not classic.is_dir():
        raise ToolError("Classic root is not a directory: %s" % classic)
    retail = Path(arguments.retail).resolve()
    if not retail.is_dir():
        raise ToolError("Retail repository is not a directory: %s" % retail)
    conflict_dir = Path(arguments.conflict_dir).resolve() if arguments.conflict_dir else None
    if conflict_dir is not None and is_inside(conflict_dir, classic):
        raise ToolError("--conflict-dir must lie outside the Classic checkout: %s" % conflict_dir)

    commit = resolve_retail_commit(retail, arguments.retail_rev)
    tree = read_retail_tree(retail, commit)
    overrides = read_manifest(classic, OVERRIDES_MANIFEST, 2)
    shadows = read_manifest(classic, SHADOWS_MANIFEST, 3)
    resolved = {path.replace("\\", "/") for path in arguments.resolved}
    unknown = sorted(resolved - {row[0] for row in overrides.rows} - {row[0] for row in shadows.rows})
    if unknown:
        raise ToolError("--resolved names no override or shadow row: %s" % ", ".join(unknown))

    print_header(retail, classic, commit)
    planner = Planner(classic, retail, commit, tree, resolved)
    override_outcomes = planner.plan_overrides(overrides)
    shadow_outcomes = planner.plan_shadows(shadows)
    report("Overrides", overrides, override_outcomes)
    print()
    report("Owned shadows", shadows, shadow_outcomes)
    for path in sorted(resolved - planner.used_resolved):
        print("  note: --resolved %s records nothing: its Retail blob did not move, or the row is a no-op" % path)
    print()

    kept_overrides = {row[0] for row in planned_rows(overrides, override_outcomes)}
    state = mirror_state(classic, tree, kept_overrides)
    print_mirror_state(commit, state)

    if conflict_dir is not None:
        written = write_conflicts(conflict_dir, override_outcomes + shadow_outcomes)
        print("Conflict previews: %d file%s below %s" % (written, plural(written), conflict_dir))
    settle(classic, overrides, override_outcomes, arguments.write, "Overrides", "--write")
    settle(classic, shadows, shadow_outcomes, arguments.write_shadows, "Owned shadows", "--write-shadows")

    by_hand = [outcome for outcome in override_outcomes if outcome.status in BY_HAND]
    shadow_by_hand = [outcome for outcome in shadow_outcomes if outcome.status in BY_HAND]
    if arguments.write_shadows:
        by_hand += shadow_by_hand
        shadow_by_hand = []
    print_by_hand(retail, by_hand, len(shadow_by_hand))
    print_trailer(commit, len(state[1]) + len(state[2]) + len(state[3]), len(by_hand))
    return 2 if by_hand else 0


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    arguments = parse_arguments(argv)
    try:
        return run(arguments)
    except (ToolError, OSError) as error:  # OSError: a file the tool could not read or replace
        sys.stdout.flush()
        print("error: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
