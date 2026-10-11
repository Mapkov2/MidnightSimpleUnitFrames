"""An explicit beta hotfix can reuse notes without relaxing other releases."""
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
resolver = root / ".github/scripts/resolve-classic-changelog-version.ps1"
pwsh = shutil.which("pwsh") or shutil.which("powershell")
assert pwsh, "PowerShell required"

with tempfile.TemporaryDirectory(prefix="msuf-changelog-reuse-") as directory:
    fixture = pathlib.Path(directory)
    (fixture / "tools").mkdir()
    changelog = fixture / "CHANGELOG.md"
    changelog.write_text("## 6.5-beta20 - 2026-10-10\n", encoding="utf-8")
    mapping = fixture / "tools/classic-changelog-reuse.tsv"

    def resolve(version, expected=None):
        run = subprocess.run(
            [pwsh, "-NoProfile", "-File", str(resolver), "-RepositoryRoot", str(fixture),
             "-ReleaseVersion", version], capture_output=True, text=True,
        )
        if expected is None:
            assert run.returncode != 0, f"invalid mapping accepted: {version}"
        else:
            assert run.returncode == 0, run.stderr
            assert run.stdout.strip() == expected, run.stdout

    resolve("6.5-beta21", "6.5-beta21")
    mapping.write_text("ReleaseVersion\tChangelogVersion\n6.5-beta21\t6.5-beta20\n", encoding="utf-8")
    resolve("6.5-beta21", "6.5-beta20")
    resolve("6.5-beta22", "6.5-beta22")
    resolve("6.50", "6.50")
    changelog.write_text("## 6.5-beta21 - 2026-10-11\n", encoding="utf-8")
    resolve("6.5-beta21")
    changelog.write_text("## 6.5-beta20 - 2026-10-10\n", encoding="utf-8")
    for target in ("6.5-beta21", "6.5-beta22", "6.6-beta20", "6.50"):
        mapping.write_text(f"ReleaseVersion\tChangelogVersion\n6.5-beta21\t{target}\n", encoding="utf-8")
        resolve("6.5-beta21")
    mapping.write_text(
        "ReleaseVersion\tChangelogVersion\n6.5-beta21\t6.5-beta20\n6.5-beta21\t6.5-beta19\n",
        encoding="utf-8",
    )
    resolve("6.5-beta21")

print("PASS Classic changelog reuse: 10 cases")
