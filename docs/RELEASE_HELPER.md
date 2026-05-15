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
section into the helper UI.

The auto changelog ignores `CHANGELOG.md`, the generated in-game changelog, docs,
workflow files, and release helper/tooling changes by default, so user-facing
release notes stay focused on addon behavior. For a background watcher, run:

```text
tools\MSUF-AutoChangelog.cmd
```

The release tag can be tag-friendly, for example:

```text
5.1-beta4
```

The changelog title can be user-friendly, for example:

```text
5.1 Beta 4
```
