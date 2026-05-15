# MSUF Release Helper

Windows launcher:

```text
tools\MSUF-ReleaseHelper.cmd
```

The helper is a small WinForms release UI for the normal MSUF release flow.

## Local Prep

Use **Update Files + Build** to:

- insert or replace the selected release section in `CHANGELOG.md`
- regenerate `MidnightSimpleUnitFrames\Foundation\MSUF_Changelog.lua`
- build a local release zip through `tools\package-release.ps1`

This does not push or publish anything.

## GitHub Release

Use **GitHub Release** only after reviewing the selected checkboxes:

- **Commit all changes** runs `git add -A` and creates `Release <tag>`
- **Create tag** creates an annotated tag
- **Push** pushes `HEAD` and the tag to `origin`
- **Run GitHub workflow** queues `.github/workflows/release.yml`

The GitHub workflow builds the zip again from the pushed tag, creates/updates
the GitHub release, uploads the zip, then publishes to Wago and CurseForge.

The workflow requires the repository secrets:

- `WAGO_API_TOKEN`
- `CF_API_KEY` or `CURSEFORGE`

## Changelog Input

Each text area accepts one bullet per line. Lines that already start with `- `
are kept as-is; all other non-empty lines are converted into markdown bullets.

Use **Load CHANGELOG.md** to read the matching release section from the repo.
The helper matches the release tag or changelog title, falls back to the latest
section, shows that full section as Markdown, and maps known headings into the
structured input fields.

Use **Since ref** plus **Load Git Commits** to generate a changelog draft from
the commits after that ref up to `HEAD`. The helper reads each commit subject,
checks the changed files, assigns the entry to a changelog category, and includes
the short commit hash plus the most relevant files in the generated bullet.

Keep **Use Markdown text as release source** enabled when you want to preserve
the loaded Markdown section exactly. Disable it when you want the helper to
build the section from the structured text areas instead.

Use **Map Markdown** after editing the Markdown field manually if you want to
re-fill the structured text areas from that Markdown.

Use **Auto Changelog** to update the selected release section directly from the
current repository state. It reads commits from **Since ref** to `HEAD`, adds
working-tree changes, writes managed auto blocks into `CHANGELOG.md`, regenerates
`MidnightSimpleUnitFrames\Foundation\MSUF_Changelog.lua`, then reloads the
section into the helper UI. If the selected version does not exist yet, it
creates a new release section using the selected date.

## Auto Changelog UI

The standalone auto changelog launcher opens a smaller UI:

```text
tools\MSUF-AutoChangelog.cmd
```

Use it to set:

- **Changelog title**: the exact `##` release heading to update
- **Date**: the date used when the release section has to be created
- **Source ref**: the previous tag or commit used as the Git range start;
  this is only the source for generated bullets, while **Changelog title**
  remains the only release section written
- **Create missing release**: inserts a new `## <version> - <date>` section
  below `# Changelog` when the selected title does not exist yet
- **Keep old auto entries**: keeps existing `MSUF-AUTO-CHANGELOG` bullets and
  merges new entries into them; leave it off to replace old generated bullets
- **Regenerate addon changelog**: updates the in-game changelog Lua file too;
  this is enabled by default in the standalone UI so the dashboard changelog
  follows `CHANGELOG.md`
- **Include tooling/docs**: includes release tooling, docs, and workflow changes
- **Poll seconds / Debounce seconds**: controls the background watcher timing

The UI provides helpers for the latest `CHANGELOG.md` section, the `VERSION`
file, the last Git tag, editable generated Markdown, one-shot updates, and a
managed watch mode.

Use **Generate Editor** to fill the Markdown editor from the current repository
changes. Edit the generated bullets there, then use **Write Edited** to write
exactly those managed auto blocks into the selected release section. Use
**Run Once** when you want to skip manual edits and write the generated entries
directly.

Use **Make Friendly** after generating entries when you want release-note text
for users instead of commit-style bullets. It removes hashes and file paths,
maps technical areas to addon-facing wording, and leaves the result in the
editor so you can still adjust it before **Write Edited**.

For a `5.2` changelog, set **Changelog title** to `5.2`. The source ref should
normally be the previous real Git tag, for example `v5.1`, not `v5.2`. If the
source ref accidentally matches the target version and does not exist as a Git
ref yet, the tool falls back to the latest existing tag and still writes only
the `5.2` section.

The auto changelog ignores `CHANGELOG.md`, the generated in-game changelog, docs,
workflow files, and release helper/tooling changes by default, so user-facing
release notes stay focused on addon behavior. For the old command-line watcher,
run:

```text
tools\MSUF-AutoChangelog.cmd -Watch -RegenerateAddonChangelog
```

Add `-CreateMissingRelease -DisplayVersion "5.2" -ReleaseDate "2026-05-15"`
when the command-line watcher should create a new release section automatically.
By default, old managed auto entries in that section are replaced. Add
`-KeepExistingAutoEntries` only when you want to keep and merge them.
Managed auto blocks in other release sections are cleaned up automatically, so
generating `5.2` does not leave stale generated `5.2` bullets under older
sections.

The release tag can be tag-friendly, for example:

```text
5.1-beta4
```

The changelog title can be user-friendly, for example:

```text
5.1 Beta 4
```
