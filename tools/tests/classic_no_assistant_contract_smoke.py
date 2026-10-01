"""Contracts the retirement of the in-game Assistant addon must keep.

1. tools/classic-addon-tombstones.txt is honoured from git's point of view, by
   both implementations of its rules: classic_tombstones.py (the Python tools)
   and Import/Assert-MsufAddonTombstones in ClassicGate.Common.psm1 (the gate).
   A folder that `git rm` leaves behind on Windows, empty or holding ignored
   files only, is not a failure; a tracked file below a retired addon, a TOC in
   its folder, or a retired path that is tracked or loaded is. Each fixture is
   a throwaway git repository checked by both implementations, which must agree.
2. The real tree: the manifest parses, nothing it retires is tracked, and no
   shipped TOC, the Menu2 manifest or the Support bridge names the Assistant.

Usage: python tools/tests/classic_no_assistant_contract_smoke.py <repository root>
"""
from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / ".github" / "scripts"))
import classic_tombstones  # noqa: E402

CORE = "MidnightSimpleUnitFrames"
OPTIONS = "MidnightSimpleUnitFrames_Options"
ASSISTANT = "MidnightSimpleUnitFrames_Assistant"
BRIDGE = OPTIONS + "/Shell/Menu2/MSUF_AssistantBridge.lua"
MANIFEST = classic_tombstones.MANIFEST
VALID = "# retired\n%s\n%s\t%s\n" % (ASSISTANT, ASSISTANT, BRIDGE)

failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def git(repo, *arguments):
    process = subprocess.run(["git", "-C", str(repo)] + list(arguments), stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)
    if process.returncode != 0:
        raise SystemExit("git %s failed: %s" % (" ".join(arguments), process.stderr.decode("utf-8", "replace")))
    return process.stdout.decode("utf-8")


def write(base, relative, text):
    target = base / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(text.encode("utf-8"))


def remove_tree(path):
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


# ---------------------------------------------------------------- 1. manifest rules
print("tombstone manifest rules (classic_tombstones.py)")
parsed = classic_tombstones.parse(VALID)
check(parsed.addons == [ASSISTANT] and parsed.paths == {BRIDGE: ASSISTANT},
      "an addon line retires the folder and a path line retires one file with it")
check(parsed.covers(BRIDGE) and parsed.covers(ASSISTANT + "/Assistant/x.lua") and not parsed.covers(CORE + "/x.lua"),
      "covers() answers for retired paths and everything below a retired folder only")
for text, fragment, why in (
    ("﻿" + ASSISTANT + "\n", "byte order mark", "a byte order mark"),
    (CORE + "\n", "retires a shipped addon", "a shipped addon line"),
    (ASSISTANT + "\t" + BRIDGE + "\textra\n", "without surrounding blanks", "three fields"),
    (" " + ASSISTANT + "\n", "without surrounding blanks", "a padded field"),
    (ASSISTANT + "\n" + ASSISTANT + "\tTools/x.lua\n", "below a shipped addon folder", "a path outside the shipped folders"),
    (ASSISTANT + "\n" + ASSISTANT + "\t" + CORE + "/../x.lua\n", "below a shipped addon folder", "a dot segment"),
    ("Other\n" + ASSISTANT + "\t" + BRIDGE + "\n", "no addon line retires", "a path tied to an addon no line retires"),
    (ASSISTANT + "\n" + ASSISTANT + "\n", "repeats the addon", "a repeated addon"),
):
    try:
        classic_tombstones.parse(text)
        check(False, "the parser refuses %s" % why)
    except classic_tombstones.TombstoneError as error:
        check(fragment in str(error), "the parser refuses %s (%s)" % (why, error))

# ---------------------------------------------------------------- 1. fixtures, both implementations
CASES = (
    # name, expected verdict, builder
    ("clean", True, "nothing retired is on disk"),
    ("empty-leftover", True, "an empty retired folder that git rm left behind"),
    ("ignored-leftover", True, "a retired folder holding an ignored file only"),
    ("leftover-toc", False, "an untracked TOC in a retired folder"),
    ("tracked-addon-file", False, "a tracked file below a retired folder"),
    ("tracked-retired-path", False, "a tracked retired path"),
    ("loaded-retired-path", False, "a retired path a shipped TOC still loads"),
    ("bad-manifest", False, "a manifest that retires a shipped addon"),
)


def build_case(base, name):
    repo = base / name
    repo.mkdir(parents=True)
    git(repo, "init", "-q")
    git(repo, "config", "core.autocrlf", "false")
    write(repo, MANIFEST, CORE + "\n" if name == "bad-manifest" else VALID)
    write(repo, CORE + "/" + CORE + "_Mainline.toc", "## Title: Core\nCore.lua\n")
    write(repo, CORE + "/Core.lua", "-- core\n")
    write(repo, ".gitignore", "luac.out\n")
    loaded = [CORE + "/" + CORE + "_Mainline.toc", CORE + "/Core.lua"]
    if name == "empty-leftover":
        (repo / ASSISTANT / "Assistant").mkdir(parents=True)
    elif name == "ignored-leftover":
        write(repo, ASSISTANT + "/Assistant/luac.out", "x")
    elif name == "leftover-toc":
        write(repo, ASSISTANT + "/" + ASSISTANT + "_Mainline.toc", "## Title: Assistant\n")
    elif name == "tracked-addon-file":
        write(repo, ASSISTANT + "/Assistant/Kept.lua", "-- kept\n")
    elif name == "tracked-retired-path":
        write(repo, BRIDGE, "-- bridge\n")
    elif name == "loaded-retired-path":
        write(repo, BRIDGE, "-- bridge, untracked\n")
        loaded.append(BRIDGE)
    git(repo, "add", "-A")
    if name == "loaded-retired-path":
        git(repo, "rm", "-q", "--cached", BRIDGE)
    write(repo, "loaded.txt", "\n".join(loaded) + "\n")
    return repo


def python_verdict(repo):
    try:
        tombstones = classic_tombstones.read(repo)
    except classic_tombstones.TombstoneError as error:
        return False, str(error)
    loaded = (repo / "loaded.txt").read_text(encoding="utf-8").split()
    problems = classic_tombstones.check_tree(repo, tombstones, loaded)
    return not problems, "; ".join(problems)


POWERSHELL_RUNNER = r"""
param([string]$ModulePath, [string]$CasesPath)
$ErrorActionPreference = "Stop"
Import-Module $ModulePath -Force
foreach ($line in [IO.File]::ReadAllLines($CasesPath)) {
    $name, $caseRoot = $line.Split([char]9)
    try {
        $tombstones = Import-MsufAddonTombstones -Path (Join-Path $caseRoot "tools/classic-addon-tombstones.txt") `
            -ShippedAddons @("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")
        $loaded = [string[]]@([IO.File]::ReadAllLines((Join-Path $caseRoot "loaded.txt")) |
            Where-Object { $_ } | ForEach-Object { Join-Path $caseRoot $_ })
        Assert-MsufAddonTombstones -Root $caseRoot -Tombstones $tombstones -LoadedPaths $loaded
        [Console]::Out.WriteLine("CASE`t$name`tPASS")
    } catch {
        [Console]::Out.WriteLine("CASE`t$name`tFAIL`t" + ($_.Exception.Message -replace '\s+', ' '))
    }
}
"""


def powershell_verdicts(cases_root, names):
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if shell is None:
        check(False, "PowerShell (pwsh or powershell) is on PATH: the gate's own tombstone reader is checked here")
        return {}
    runner = cases_root / "runner.ps1"
    runner.write_text(POWERSHELL_RUNNER, encoding="utf-8")
    listing = cases_root / "cases.tsv"
    listing.write_text("".join("%s\t%s\n" % (name, cases_root / name) for name in names), encoding="utf-8")
    module = root / ".github" / "scripts" / "ClassicGate.Common.psm1"
    process = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                              str(runner), "-ModulePath", str(module), "-CasesPath", str(listing)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    verdicts = {}
    for line in process.stdout.decode("utf-8", "replace").splitlines():
        fields = line.split("\t")
        if len(fields) >= 3 and fields[0] == "CASE":
            verdicts[fields[1]] = (fields[2] == "PASS", fields[3] if len(fields) > 3 else "")
    if len(verdicts) != len(names):
        check(False, "the PowerShell reader answered every fixture (exit %d): %s" % (
            process.returncode, process.stderr.decode("utf-8", "replace").strip()[:400]))
    return verdicts


print("tombstone fixtures (Python and PowerShell readers)")
scratch = Path(tempfile.mkdtemp(prefix="msuf-tombstone-smoke-")).resolve()
try:
    for name, _, _ in CASES:
        build_case(scratch, name)
    ps = powershell_verdicts(scratch, [name for name, _, _ in CASES])
    for name, expected, why in CASES:
        passed, detail = python_verdict(scratch / name)
        check(passed == expected, "Python: %s %s%s" % (why, "passes" if expected else "fails",
                                                        "" if passed == expected else " (%s)" % detail))
        if name in ps:
            check(ps[name][0] == expected, "PowerShell: %s %s%s" % (why, "passes" if expected else "fails",
                                                                   "" if ps[name][0] == expected else " (%s)" % ps[name][1]))
finally:
    remove_tree(scratch)

# ---------------------------------------------------------------- 2. the real tree
print("the real tree")
try:
    tombstones = classic_tombstones.read(root)
except classic_tombstones.TombstoneError as error:
    tombstones = classic_tombstones.Tombstones()
    check(False, "the tombstone manifest parses (%s)" % error)
check(ASSISTANT in tombstones.addons and tombstones.paths.get(BRIDGE) == ASSISTANT,
      "the manifest retires the Assistant addon and its Options bridge")
problems = classic_tombstones.check_tree(root, tombstones)
check(not problems, "nothing the manifest retires is tracked or carries a TOC%s" % (
    "" if not problems else ": " + "; ".join(problems)))
tocs = sorted((root / CORE).glob("*.toc")) + sorted((root / OPTIONS).glob("*.toc"))
check(len(tocs) == 8, "both shipped addons carry their four client TOCs (found %d)" % len(tocs))
for toc in tocs:
    text = toc.read_text(encoding="utf-8")
    check(re.search(r"Assistant|assistant", text) is None, "no Assistant reference in %s" % toc.relative_to(root).as_posix())
menu_xml = (root / OPTIONS / "Shell/Menu2/MSUF_Menu2.xml").read_text(encoding="utf-8")
check("MSUF_AssistantBridge" not in menu_xml and ASSISTANT not in menu_xml,
      "the Menu2 manifest loads no Assistant bridge")
support = (root / OPTIONS / "Shell/Menu2/MSUF_Menu2_Support.lua").read_text(encoding="utf-8")
check(re.search(r"Assistant\.(?:Resume|Quiesce)|MSUF_Assistant", support) is None,
      "the Menu2 support layer no longer resumes or quiesces the Assistant")
# Shipped text must not point players at a feature that no longer exists. The
# changelog payloads are release history and may name it.
ADVERT = re.compile(r"(?i)\bin-game assistant\b|\bthe assistant (?:can|will|helps)\b|\bmsuf assistant\b")
HISTORY = {CORE + "/State/MSUF_Changelog.lua", OPTIONS + "/State/MSUF_ChangelogFull.lua"}
listed = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", CORE, OPTIONS], stdout=subprocess.PIPE)
adverts = []
for relative in sorted(name for name in listed.stdout.decode("utf-8").split("\0") if name.endswith(".lua")):
    path = root / relative
    if relative in HISTORY or not path.is_file():
        continue
    for number, line in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
        if ADVERT.search(line) and not line.lstrip().startswith("--"):
            adverts.append("%s:%d" % (relative, number))
check(listed.returncode == 0 and not adverts,
      "no shipped text outside the changelog history advertises the retired Assistant%s" % (
          "" if not adverts else ": " + ", ".join(adverts[:5])))

# ---------------------------------------------------------------- 3. honest generator claims
# Moved here from the Assistant control schema smoke, which the removal deleted
# with the schema it guarded. A file this repository writes may only claim a
# generator this repository tracks, or nobody can reproduce or check it. Byte-
# identical Retail mirrors are exempt: their header describes Retail's tooling
# and their bytes must stay Retail's. Owned and overridden addon files and
# everything outside the addon folders are this repository's own.
print("generator claims")
CLAIM = re.compile(r"(?i)\bgenerated\b(?:\s+from\s+\S+)?\s+by\s+([^\s,;]+)")
tracked = [name for name in subprocess.run(["git", "-C", str(root), "ls-files", "-z"], stdout=subprocess.PIPE)
           .stdout.decode("utf-8").split("\0") if name]
tracked_set = set(tracked)
owned = {line.strip() for line in (root / "tools/classic-owned-addon-paths.txt").read_text(encoding="utf-8").splitlines()
         if line.strip()}
overridden = {line.split("\t", 1)[0] for line in
              (root / "tools/classic-retail-overrides.tsv").read_text(encoding="utf-8").splitlines() if line}
claims, scanned, unbacked = 0, 0, []
for relative in tracked:
    if relative.startswith((CORE + "/", OPTIONS + "/")) and relative not in owned and relative not in overridden:
        continue
    if not relative.endswith((".lua", ".py", ".ps1", ".psm1", ".tsv", ".txt")) or not (root / relative).is_file():
        continue
    scanned += 1
    head = "\n".join((root / relative).read_text(encoding="utf-8-sig", errors="replace").splitlines()[:6])
    claim = CLAIM.search(head)
    if not claim:
        continue
    claims += 1
    generator = claim.group(1).replace("\\", "/").rstrip(".")
    if generator not in tracked_set:
        unbacked.append("%s claims %s" % (relative, generator))
check(claims > 0 and not unbacked,
      "%d of %d files this repository writes claim a generator, and each claimed generator is tracked%s" % (
          claims, scanned, "" if not unbacked else ": " + "; ".join(unbacked[:5])))

print()
if failures:
    print("Classic Assistant retirement contract: %d FAILED" % len(failures))
    for message in failures:
        print("  " + message)
    sys.exit(1)
print("Classic Assistant retirement contract: ok")
