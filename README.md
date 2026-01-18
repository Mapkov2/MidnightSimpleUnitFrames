# Midnight Simple Unit Frames (MSUF)

**Midnight Simple Unit Frames** is a performance-focused unitframe addon for World of Warcraft (Midnight).  
It aims to stay lightweight, modular, and responsive under bursty gameplay (e.g. frequent target changes), while offering practical customization for raid/dungeon use.

## Scope
MSUF provides custom unitframes and related UI components. Feature areas are organized in modules (e.g. castbars, auras), with an emphasis on:
- event-driven updates where possible
- minimizing unnecessary work in hot paths
- avoiding regressions and maintaining stable behavior across builds

## Modules (high level)
- **Unitframes** (core frame building & layout)
- **Castbars** (including previews / edit positioning, module-dependent)
- **Auras** (Aura 2.0 pipeline, module-dependent)
- **Options/UI** (configuration + profiles)

> Exact feature availability depends on the included modules in this repository/build.

## Installation
1. Download the repository (ZIP) or a release build.
2. Extract into:
   `World of Warcraft/_retail_/Interface/AddOns/`  
   (or `_beta_`, `_ptr_` depending on your client)
3. Ensure folder names remain unchanged:
   - `MidnightSimpleUnitFrames`
   - `MidnightSimpleUnitFrames_Castbars` (if present)

Restart the game or run `/reload`.

## Configuration
Open the in-game settings panel for MSUF (or use the addon list entry).  
Profiles and export/import are available if included in the build.

## Development
This repo is intended to be edited locally and pushed via Git.  
If you contribute changes:
- keep patches cumulative (avoid removing prior fixes unless explicitly intended)
- prefer small, reviewable commits
- include reproduction steps for bugfixes

## Security
Please do **not** commit credentials, webhook URLs, tokens, or private keys.  
See `SECURITY.md` for reporting.

## Issues
Use GitHub Issues and include:
- expected vs actual behavior
- reproduction steps
- relevant errors/log snippets
- screenshots for UI problems
