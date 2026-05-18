# Midnight Simple UnitFrames (MSUF)

Lightweight, minimal **unitframes + castbars + auras** for World of Warcraft, with a strong focus on **clean visuals**, **high configurability**, and **performance-friendly, event-driven updates**.

---

## Highlights

### Unitframes
- Player / Target / Focus / Pet / Target-of-Target / Boss frames
- Per-frame sizing & positioning
- Flexible text modes (name / HP / power), font sizing, outlines
- Color systems (class colors, reaction colors, custom overrides)
- Optional indicators (e.g. leader/assist, raid marker, status text like AFK/DND/DEAD)

### Castbars
- Player / Target / Focus / Boss castbars
- Interruptibility visuals, outlines, text settings
- Edit-mode previews + live positioning
- Designed to be **secret-safe** and compatible with modern Blizzard timing APIs

### Auras 2.0
- Target / Focus / Boss auras
- Filters (mine-only, boss auras, dispellable/stealable highlighting, etc.)
- Configurable layouts (rows, growth, stacking/splitting, spacing)
- Optional cooldown text styling (bucket colors / warning thresholds)

### Profiles & Import / Export
- Profile system for quickly switching setups
- Import/Export via copy-paste strings (supports **legacy** formats and newer formats)

## Packaging

The checked-in TOC files intentionally keep the packager token `## Version: @project-version@`.
Release packages patch the copied TOC files only, so local packaging and CurseForge/Wago releases get the concrete release version without changing the working tree.

Create a local release ZIP with:

```powershell
.\tools\package-release.ps1 -Version 5.021
```

If Windows blocks local scripts, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1 -Version 5.021
```

If `-Version` is omitted, the script uses `VERSION`. GitHub Actions uses the pushed tag name and strips a leading `v` for the TOC version.
