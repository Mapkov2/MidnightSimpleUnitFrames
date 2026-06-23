# Core Addon Workflow

This repository contains World of Warcraft addon work, including MSUF and CDM. Treat this workflow as project-level operating procedure for every Codex chat in this repo.

## Repository Discovery

- Do not assume the current working directory is the repository root.
- First determine the root with `git rev-parse --show-toplevel`.
- In this local checkout, the root is expected to be `C:\MSUF Beta Branch\MidnightSimpleUnitFrames` when present.
- MSUF lives under `MidnightSimpleUnitFrames/`.
- CDM lives under `MidnightCooldownManager/` and `MidnightCooldownManager_Options/`.

## Blizzard UI Source First

- For addon work touching WoW APIs, FrameXML behavior, Blizzard templates, unit frames, auras, cooldowns, resource bars, secure frames, or client-version behavior, use a local clone of Blizzard's UI source mirror as the primary reference before relying on wiki pages or forum posts.
- Canonical source mirror: `https://github.com/Gethe/wow-ui-source`.
- Local reference path for this checkout: `_local_workflows/references/wow-ui-source`.
- Keep all relevant branches available locally, especially `live`, `ptr`, `ptr2`, and `beta`.
- Update the local mirror before source-sensitive work when it may be stale:

```powershell
powershell -ExecutionPolicy Bypass -File .\_local_workflows\scripts\update_wow_ui_source.ps1
```

## Source Usage Rules

- Prefer direct searches in the local WoW UI source with `rg` over web searches for Blizzard UI implementation details.
- Use branch-qualified references when behavior may differ by client version, for example `upstream/live` vs `upstream/beta`.
- Warcraft Wiki, AddOn Studio, forums, and other web docs are secondary references. They are useful for explanations, but local UI source wins for current behavior.
- If a change depends on Blizzard behavior, mention which local source branch/file informed it.
- If the local clone is missing or broken, re-clone `Gethe/wow-ui-source` before making source-sensitive assumptions.
- For CDM 12.1 PTR work, run `_local_workflows/scripts/report_cdm_12_1_impact.ps1` and use its latest report before changing CooldownViewer/cooldown/aura/spell/item behavior.

## Local-Only Artifacts

- `_local_workflows/` is intentionally ignored by Git and may contain local workflow docs, references, scripts, screenshots, and audits.
- Do not ship `_local_workflows/` content with addon releases.
