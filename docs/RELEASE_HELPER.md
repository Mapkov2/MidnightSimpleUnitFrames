# MSUF Publish

Windows launcher:

```text
tools\MSUF-Publish.cmd
```

This is the only user-facing release launcher. The other PowerShell scripts in
`tools` are backend scripts used by MSUF Publish.

## Quick Flow

Start **MSUF Publish**, check the release data at the top, then use the
numbered buttons:

1. **Scan Changelog** collects commits, patch text, and working-tree changes,
   writes the selected `CHANGELOG.md` release section, and reloads the Markdown
   into the window.
2. Edit the large Markdown box manually if needed. This is the release text
   that the next buttons use.
3. **Dashboard** writes the shown Markdown into `CHANGELOG.md` and regenerates
   `MidnightSimpleUnitFrames\Foundation\MSUF_Changelog.lua`.
4. **Build ZIP** updates local release files and creates the package in `dist`.
5. **Publish** commits, tags, pushes, and lets GitHub Actions publish.
6. **Git Status** shows the current worktree changes.

By default, **Auto-scan before Build/Publish** is off. That keeps your edited
Markdown stable after button 1. Turn it on only when you intentionally want
**Build ZIP** or **Publish** to rescan the repository right before running.

Keep **Release line scan** enabled for normal releases and betas. It scans from
the previous stable tag for the selected version line, for example `v5.1` to
`5.2 Beta 4`, so early beta commits are not missed. Set **Since hours** only
when you intentionally want a time window; doing that disables release-line
mode.

Pick **Full release** for a stable release. Pick **Beta / prerelease** for
alpha, beta, RC, or test releases. Prereleases must use a tag containing
`alpha`, `beta`, `rc`, or `pre`; full releases must use a stable tag without
those words.

Use **VERSION** to reload the tag from the repository `VERSION` file.
**Version / tag** is the package tag, for example `5.2-beta1`.
If you accidentally enter a friendly title such as `5.2 Beta 4`, MSUF Publish
normalizes it to a Git-safe tag such as `5.2-beta4` before publishing.
Patch-style prerelease tags are supported too. These forms all resolve to the
same release key: `v5.2Beta4.2`, `5.02 beta 4.2`, `5.2-beta4.2`, and
`5.2 Beta 4.2`. If an exact `5.2 Beta 4.2` changelog section does not exist,
release publishing can fall back to the base `5.2 Beta 4` section.
**Changelog title** is the heading written to `CHANGELOG.md`, for example
`5.2 Beta 1`.
**Release name** is the public upload/release display name, for example
`MSUF 5.2 Beta 1`.

Use **Scan** next to **Release branch** to read branches from `origin`, then
select the branch you want to release from. Publish only continues when the
current checkout is on that selected branch.

The detailed action checkboxes are hidden by default. Use **Advanced actions**
only when you need to change whether Publish builds, commits, tags, pushes, or
queues the workflow.

## Buttons

**Load Notes** reads the matching release section from `CHANGELOG.md` and puts
it into the Markdown box.

**Preview Notes** prints the Markdown release notes into the log area.

**Map Markdown** re-fills the structured text boxes from the Markdown box.

**Scan Changelog** is the normal changelog generator. It reads commits, changed
files, patch text, and working-tree changes, filters junk commits, and creates
user-facing release notes instead of raw commit lists.
Changes to `tools`, `.github`, `docs`, `.pkgmeta`, `CHANGELOG.md`, generated
dashboard changelog data, and TOC metadata are hard-filtered out and never land
in the main MSUF addon changelog.

**Dashboard** is the direct sync button for the in-game dashboard changelog.
Use it after editing the Markdown box when you want exactly that text in
`MSUF_Changelog.lua`.

**Build ZIP** updates `CHANGELOG.md`, regenerates the dashboard changelog, and
builds the local zip. It does not push.

**Publish** runs the release confirmation and then commits, tags, pushes, and
publishes through GitHub Actions according to the advanced checkboxes.

## GitHub Release

The GitHub workflow builds the zip again from the pushed tag, creates or updates
the GitHub release, uploads the zip, then publishes to Wago and CurseForge.
Tags containing `alpha`, `beta`, `rc`, or `pre` are marked as GitHub
pre-releases and are not promoted as the latest stable GitHub release.

Before uploading, the workflow extracts only the matching `CHANGELOG.md`
release section into `dist/RELEASE_NOTES.md`, so GitHub and Wago receive the
current version notes instead of the complete changelog file. It also writes
`dist/RELEASE_NOTES_CF.html` for CurseForge, because CurseForge handles uploaded
changelogs more reliably as explicit HTML than as raw Markdown in its WYSIWYG
editor.

The workflow requires the repository secrets:

- `WAGO_API_TOKEN`
- `CF_API_KEY` or `CURSEFORGE`
