# MSUF Release Helper

Windows launcher:

```text
tools\MSUF-ReleaseHelper.cmd
```

The helper is a small WinForms release UI for the normal MSUF release flow.

## Quick Flow

Start the helper, check the release data at the top, then use the numbered
buttons:

1. **Auto Changelog** writes the selected changelog section from repo changes.
2. **Build ZIP** updates files and creates the local package in `dist`.
3. **Publish** updates files again, commits, tags, pushes, and lets GitHub
   Actions publish the release.

By default, **Auto Changelog before Build/Publish** is enabled. That means
**Build ZIP** and **Publish** refresh the auto changelog first, load that
section into the notes field, and use those shown notes as the release source.
Turn it off only when you intentionally want to release manually edited notes.

Pick **Full release** for a stable release. Pick **Beta / prerelease** for
alpha, beta, RC, or test releases. The publish confirmation shows the selected
release type, display name, and exact steps before anything is pushed.
Prereleases must use a tag containing `alpha`, `beta`, `rc`, or `pre`; full
releases must use a stable tag without those words.

Use **VERSION** to reload the tag from the repository `VERSION` file.
**Changelog title** is only the heading written to `CHANGELOG.md`, for example
`5.2 Beta 1`. **Release name** is the public upload/release display name used
for GitHub, Wago, and CurseForge, for example `MSUF 5.2 Beta 1`. Avoid `:` in
the release name because the CurseForge packager uses it as an internal
separator.
**Version / tag** is the tag/package version, for example `5.2-beta1`.

Use **Scan** next to **Release branch** to read branches from `origin`, then
select the branch you want to release from. Publish only continues when the
current checkout is on that selected branch, then pushes explicitly to
`origin/<branch>` and tags that commit.

The detailed action checkboxes are hidden by default. Use **Advanced actions**
only when you need to change whether Publish builds, commits, tags, pushes, or
queues the workflow.

## Local Prep

Use **Build ZIP** to:

- insert or replace the selected release section in `CHANGELOG.md`
- regenerate `MidnightSimpleUnitFrames\Foundation\MSUF_Changelog.lua`
- build a local release zip through `tools\package-release.ps1`

This does not push or publish anything.

## GitHub Release

Use **Publish** after checking the confirmation dialog. By default it runs the
normal release profile:

- **Commit all changes** runs `git add -A` and creates `Release <tag>`
- **Create tag** creates an annotated tag
- **Push** pushes `HEAD` to the selected `origin/<branch>` and pushes the tag
- **Run GitHub workflow** publishes through `.github/workflows/release.yml`;
  with **Push** enabled, the tag push starts it, otherwise the helper dispatches it

The GitHub workflow builds the zip again from the pushed tag, creates/updates
the GitHub release, uploads the zip, then publishes to Wago and CurseForge.
Tags containing `alpha`, `beta`, `rc`, or `pre` are marked as GitHub
pre-releases and are not promoted as the latest stable GitHub release.
Before uploading, the workflow extracts only the matching `CHANGELOG.md`
release section into `dist/RELEASE_NOTES.md`, so GitHub receives the current
version notes instead of the complete changelog file.

The workflow requires the repository secrets:

- `WAGO_API_TOKEN`
- `CF_API_KEY` or `CURSEFORGE`

## Changelog Input

Each text area accepts one bullet per line. Lines that already start with `- `
are kept as-is; all other non-empty lines are converted into markdown bullets.

Use **Load Notes** to read the matching release section from the repo.
The helper matches the release tag or changelog title, falls back to the latest
section, shows that full section as Markdown, and maps known headings into the
structured input fields.

Use **Since ref** plus **Draft from Git** to generate a changelog draft from
the commits after that ref up to `HEAD`. The helper reads each commit subject,
checks the changed files, assigns the entry to a changelog category, and includes
the short commit hash plus the most relevant files in the generated bullet.
For normal releases, prefer **Auto Changelog** because it uses the newer scanner
that reads commits, patch text, and working-tree changes into user-facing notes.

Keep **Use shown notes as release source** enabled when you want to preserve
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
  merges new entries into them; for prereleases such as `5.2 Beta 2` or
  `5.2 Alpha 2`, it also carries older auto bullets from the same version line
  and channel; leave it off to replace old generated bullets
- **Include prerelease logs**: for a final release such as `5.2`, carries
  managed auto bullets from matching `5.2 Alpha`, `5.2 Beta`, `5.2 RC`, or
  `5.2 Pre` sections into the final release notes, then adds the newly
  generated release changes
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

The auto generator scans the selected Git commit range, the changed files in
each commit, the actual patch text, and current working-tree changes. Generated
entries are deduplicated into user-facing release notes instead of plain commit
lists with hashes and file paths.

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
`-KeepExistingAutoEntries` only when you want to keep and merge them. For
numbered prereleases, the keep mode carries older same-channel auto entries,
for example from `5.2 Beta 1` into `5.2 Beta 2` or from `5.2 Alpha 1` into
`5.2 Alpha 2`.
Add `-IncludePrereleaseAutoEntries` for a final release section such as `5.2`
when the release notes should include all managed auto entries from matching
`5.2 Beta 1`, `5.2 Beta 2`, and other same-version prerelease sections plus the
new release changes from the selected Git range.
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
