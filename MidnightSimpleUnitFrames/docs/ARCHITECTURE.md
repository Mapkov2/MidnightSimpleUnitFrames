# MSUF Architecture

This addon is organized like a small operating system: a tiny kernel boots the
namespace and shared services, state owns persisted data, runtime services expose
cross-cutting visual behavior, shell code owns configuration UI, and gameplay
subsystems own the frames players see.

## Folder Map

- `Libs/`: vendored third-party libraries only.
- `Kernel/`: boot, library adapters, utility globals, event bus, scheduler,
  module lifecycle, and Blizzard frame ownership gates.
- `State/`: defaults, migrations, profiles, import/export, changelog data.
- `Runtime/`: shared visual/runtime services used by multiple subsystems:
  colors, fonts, textures, icon layout, portraits, bar backgrounds, chat, and
  tooltip behavior.
- `Shell/`: user-facing shell and launcher UI. `Shell/EditMode` and
  `Shell/Menu2` are the primary configuration surfaces; `Shell/UI` is the
  shared UI kit used by both.
- `UnitFrames/`: the unit-frame subsystem. `UnitFrames/Engine` is the new
  frame engine; `Elements` are per-frame capabilities; `Group` is the party and
  raid engine; `Effects` contains optional visual add-ons such as rounded frames.
- `Castbars/`: all castbar ownership, rendering, previews, kick readiness, and
  focus-kick behavior.
- `ClassPower/`: class-resource bars and supporting class-power runtime.
- `Auras3/`: aura runtime and aura configuration.
- `Features/`: optional gameplay or cold-path product features, grouped by
  purpose (`Gameplay`, `Telemetry`, `Versioning`, `Diagnostics`).
- `Integrations/`: adapters for other addons or external frame anchors.
- `Locales/`, `Media/`, `Icons/`: assets and localization data.

## Load Order Contract

The `.toc` is the source of truth. Keep new files in the owning folder above and
load them where their dependencies are already available.

1. Vendor libs and `Kernel/MSUF_Bootstrap.lua`.
2. Locales.
3. Kernel, state, and shared shell UI primitives.
4. Shell edit mode loader.
5. Pre-engine runtime services and the unit-frame engine.
6. Auras, gameplay features, and unit-frame elements/factory.
7. Castbars, class power, group frames, Menu2, and optional visual/castbar
   features.

## Cuts Applied

- Removed empty XML loaders:
  - `Borders/MSUF_Borders.xml`
  - `UnitFrames/MSUF_UnitFrameCore_PostMain.xml`
  - `UnitFrames/MSUF_UnitFrameCore_Visuals.xml`
  - `UnitFrames/MSUF_UnitFrameCore_AfterBorders.xml`
- Removed the empty class-power bridge:
  - `Core/MSUF_ClassPower.lua`
- Removed the redundant root namespace file:
  - `MidnightSimpleUnitFrames.lua`
- Removed empty legacy buckets after moving their owned files:
  - `Foundation/`, `Core/`, `Modules/`, `Borders/`, `UI/`

## Keep For Now

- `Kernel/MSUF_Modules.lua`: still used by VersionCheck, Castbars, Gameplay, and
  ClassPower registration paths.
- `Kernel/MSUF_BlizzardFrames.lua`: still owns Blizzard frame/castbar handoff.
- `State/MSUF_ProfileIO.lua`: still exposes `MSUF_SerializeDB` and compatibility
  profile import/export proxies.
- `Features/Diagnostics/MSUF_Feature_DebugPosition.lua`: dev-only behavior, but
  loaded cold and dormant unless toggled.
- `MSUF_GroupFrames.xml` plus `GroupFrames/`: still required as the group-frame
  DB/data loader before `UnitFrames/Engine/Group`.

## Future Cut Candidates

- Split `State/MSUF_Defaults.lua` into defaults, migrations, and embedded
  factory-profile payload. It is the largest state file and mixes concerns.
- Split `State/MSUF_Profiles.lua` into profile lifecycle, compact-string IO,
  import/export, and post-import apply hooks.
- Move `GroupFrames/` data under `UnitFrames/Group/Data` once group-frame naming
  is settled.
- Keep reducing globals in old compatibility surfaces, but do that only after
  Menu2/EditMode callers are migrated to namespace APIs.
