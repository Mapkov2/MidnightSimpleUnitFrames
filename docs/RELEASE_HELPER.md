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

The release tag can be tag-friendly, for example:

```text
5.1-beta4
```

The changelog title can be user-friendly, for example:

```text
5.1 Beta 4
```
