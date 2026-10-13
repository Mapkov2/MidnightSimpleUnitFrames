"""The release-line assertion follows VERSION instead of one hard-coded release line.

.github/scripts/assert-classic-release-line.ps1 runs in every gate and in the packager. It used to
throw for any version other than 6.5 alpha/beta and 6.50, so the next release line would have turned
every gate red until someone retargeted it. This smoke runs the real script against a fixture
repository whose VERSION, TOC versions, changelog section and generated changelog payloads are all
rewritten to the version under test: a stable release (two-digit minor) or an alpha/beta of any
release line passes, a malformed version or a file that disagrees with VERSION fails.

Usage: python tools/tests/release_line_version_smoke.py <repository root>
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
SCRIPT = root / ".github" / "scripts" / "assert-classic-release-line.ps1"
ADDONS = ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")
PAYLOADS = ("MidnightSimpleUnitFrames_Options/State/MSUF_Changelog.lua",
            "MidnightSimpleUnitFrames_Options/State/MSUF_ChangelogFull.lua")
failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def remove_tree(path):
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


script_text = SCRIPT.read_text(encoding="utf-8") if SCRIPT.is_file() else ""
check(bool(script_text), "the release-line assertion exists: %s" % SCRIPT.relative_to(root).as_posix())
check(re.search(r"6\.5", script_text) is None, "the assertion names no release line of its own")

matrix_lines = (root / "tools" / "classic-client-matrix.tsv").read_text(encoding="utf-8").splitlines()
suffixes = [line.split("\t")[0] for line in matrix_lines[1:] if line.strip()]
fragments = re.findall(r'"((?:MidnightSimpleUnitFrames)/[^"]+\.lua)"\s*=\s*"([^"]+)"', script_text)
check(len(fragments) >= 5, "the assertion lists the contract fragments it reads (%d)" % len(fragments))
VERSION_LINE = re.compile(r"^(## (?:Version|X-MSUF-Version-Forever): )\S+", re.M)


def build(base, case):
    """Writes one fixture repository: everything that carries the version is rewritten to the case's."""
    version = case["version"]
    toc_version = case.get("toc_version", version)
    target = base / case["id"]
    matrix = target / "tools" / "classic-client-matrix.tsv"
    matrix.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(str(root / "tools" / "classic-client-matrix.tsv"), str(matrix))
    # The assertion only looks for a fragment of each file, so a stub that holds it is enough.
    for relative, fragment in fragments:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text("-- %s\n" % fragment, encoding="utf-8", newline="")
    for addon in ADDONS:
        for suffix in suffixes:
            relative = "%s/%s_%s.toc" % (addon, addon, suffix)
            text = (root / relative).read_text(encoding="utf-8")
            use = case.get("stale_toc_version") if relative == case.get("stale_toc") else toc_version
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(VERSION_LINE.sub(lambda m: m.group(1) + use, text), encoding="utf-8", newline="")
    (target / "VERSION").write_text(case.get("version_file", version) + "\n", encoding="utf-8", newline="")
    section = case.get("changelog_section", version)
    changelog = "# Changelog\n\n## %s - fixture\n- change\n" % section
    (target / "CHANGELOG.md").write_text(changelog, encoding="utf-8", newline="")
    sha = hashlib.sha256(changelog.encode("utf-8")).hexdigest().upper()
    for relative in PAYLOADS:
        payload_version = case.get("payload_version", version)
        payload_sha = case.get("payload_sha", sha)
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text('return { currentVersion = "%s", sourceSha256 = "%s" }\n' % (payload_version, payload_sha),
                               encoding="utf-8", newline="")
    return target


def case(id_, name, version, expected, fragment="", **extra):
    entry = {"id": id_, "name": name, "version": version, "expected": expected, "fragment": fragment}
    entry.update(extra)
    return entry


first_toc = "%s/%s_%s.toc" % (ADDONS[0], ADDONS[0], suffixes[0] if suffixes else "Mainline")
current = (root / "VERSION").read_text(encoding="utf-8").strip()
CASES = [
    case("current", "the version in VERSION passes (%s)" % current, current, "PASS"),
    case("stable", "a stable release of a later release line passes", "7.00", "PASS"),
    case("stable_ten", "a stable release with a minor ending in zero passes", "6.70", "PASS"),
    case("beta", "a beta of a later release line passes", "7.0-beta3", "PASS"),
    case("alpha", "an alpha of a later release line passes", "7.0-alpha1", "PASS"),
    case("old_beta", "a beta of the previous release line still passes", "6.5-beta20", "PASS"),
    case("one_digit", "a stable release with a one-digit minor fails", "7.1", "FAIL", "minor with two digits"),
    case("rc", "an unknown channel fails", "7.00-rc1", "FAIL", "Classic release must use"),
    case("leading_zero", "a prerelease number with a leading zero fails", "7.0-beta01", "FAIL", "Classic release must use"),
    case("bare_major", "a version without a minor fails", "7", "FAIL", "Classic release must use"),
    case("mismatch", "a VERSION file that disagrees with the release fails", "7.00", "FAIL", "does not match",
         version_file="7.01"),
    case("stale_toc", "a TOC left on another version fails", "7.00", "FAIL", "stale",
         stale_toc=first_toc, stale_toc_version="6.99"),
    case("no_section", "a changelog without the release section fails", "7.00", "FAIL", "no selected Classic release section",
         changelog_section="6.99"),
    case("stale_payload", "a changelog payload on another version fails", "7.00", "FAIL", "stale currentVersion",
         payload_version="6.99"),
    case("stale_hash", "a changelog payload that does not match CHANGELOG.md fails", "7.00", "FAIL", "does not match CHANGELOG.md",
         payload_sha="0" * 64),
]

RUNNER = r"""
param([string]$ScriptPath, [string]$CasesPath, [string]$BaseRoot)
$ErrorActionPreference = "Stop"
$cases = [IO.File]::ReadAllText($CasesPath) | ConvertFrom-Json
foreach ($case in $cases) {
    try {
        & $ScriptPath -RepositoryRoot (Join-Path $BaseRoot $case.id) -ReleaseVersion $case.version | Out-Null
        [Console]::Out.WriteLine("CASE`t$($case.name)`tPASS`t")
    } catch {
        [Console]::Out.WriteLine("CASE`t$($case.name)`tFAIL`t" + ($_.Exception.Message -replace '\s+', ' '))
    }
}
"""

print("Release-line assertion (assert-classic-release-line.ps1)")
shell = shutil.which("pwsh") or shutil.which("powershell")
scratch = Path(tempfile.mkdtemp(prefix="msuf-release-line-smoke-")).resolve()
try:
    if shell is None or not script_text:
        check(False, "PowerShell (pwsh or powershell) is on PATH and the assertion exists")
    else:
        for item in CASES:
            build(scratch, item)
        (scratch / "runner.ps1").write_text(RUNNER, encoding="utf-8")
        (scratch / "cases.json").write_text(json.dumps(CASES), encoding="utf-8")
        process = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                                  str(scratch / "runner.ps1"), "-ScriptPath", str(SCRIPT),
                                  "-CasesPath", str(scratch / "cases.json"), "-BaseRoot", str(scratch)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        results = []
        for line in process.stdout.decode("utf-8", "replace").splitlines():
            fields = line.split("\t")
            if len(fields) == 4 and fields[0] == "CASE":
                results.append(fields[1:])
        check(len(results) == len(CASES), "PowerShell answered every case (%d answers, exit %d): %s" % (
            len(results), process.returncode, process.stderr.decode("utf-8", "replace").strip()[:400]))
        for item, answer in zip(CASES, results):
            name, verdict, detail = answer
            if item["expected"] == "PASS":
                check(name == item["name"] and verdict == "PASS", "%s (%s)" % (item["name"], detail[:160]))
            else:
                check(name == item["name"] and verdict == "FAIL" and item["fragment"] in detail,
                      "%s: %s (%s)" % (item["name"], item["fragment"], detail[:160]))
finally:
    remove_tree(scratch)

print()
if failures:
    print("release line version smoke: %d FAILED" % len(failures))
    for message in failures:
        print("  - " + message)
    sys.exit(1)
print("release line version smoke: ok")
