# MSUF2 Native Menu Handoff

Date: 2026-05-11
Workspace: `c:\MSUF Beta Branch\MidnightSimpleUnitFrames\MidnightSimpleUnitFrames`
Addon root: `MidnightSimpleUnitFrames\`

## User Goal

Build `MSUF2` as a native, high-performance rebuild of the existing MSUF options menu.

Hard requirement:
- It must look and behave 1:1 like the old MSUF menu.
- It must keep the same features, previews, controls, dropdowns, sliders, checkmarks, colors, fonts, and group/unit previews.
- It must not mirror, reparent, or directly reuse the old option panels as UI. This is a rebuild.
- It may reuse old style helpers and runtime apply functions where that avoids visual regression.
- Do not break old MSUF while MSUF2 is being built.

The user is testing in WoW and comparing screenshots side by side against the old menu.

## Current Git State

Known dirty/untracked state from latest check:

```text
 M MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Effects.lua
 M MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc
 M MidnightSimpleUnitFrames/Options/MSUF_Options_Player.lua
?? MidnightSimpleUnitFrames/Menu2/
```

Important:
- `MSUF_GF_Effects.lua` contains prior group-frame performance changes. Treat as existing work unless the user asks to revisit.
- `Options/MSUF_Options_Player.lua` was already modified before the latest indicator work. Be careful not to revert user/previous edits.
- `Menu2/` is currently untracked but loaded by the TOC.

## TOC Integration

`MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc` loads Menu2 at lines around 174-181:

```text
Menu2\MSUF_Menu2_Theme.lua
Menu2\MSUF_Menu2_Widgets.lua
Menu2\MSUF_Menu2_Bindings.lua
Menu2\MSUF_Menu2_Core.lua
Menu2\Pages\MSUF_Menu2_Unit.lua
Menu2\Pages\MSUF_Menu2_Global.lua
Menu2\Pages\MSUF_Menu2_Group.lua
Menu2\Pages\MSUF_Menu2_Advanced.lua
```

`/msuf2` opens the new native menu. Final migration to `/msuf` should wait until parity is actually good.

## Menu2 File Roles

- `Menu2/MSUF_Menu2_Theme.lua`
  - Theme colors, buttons, backdrop, nav icons, sliders, checkmarks.
  - Latest change: `T.StyleCheckmark` no longer depends on Blizzard checkbox visuals. It strips template textures and draws custom superellipse/rim/tick textures.

- `Menu2/MSUF_Menu2_Widgets.lua`
  - Shared widget constructors: page builder, collapsible sections, toggles, sliders, dropdowns, buttons, text inputs, color buttons.
  - All MSUF2 toggles go through `W.Toggle`, so style fixes should usually happen centrally here or in `T.StyleCheckmark`.

- `Menu2/MSUF_Menu2_Bindings.lua`
  - DB access and deferred apply batching for unit/general config.

- `Menu2/MSUF_Menu2_Core.lua`
  - Window, nav, dashboard, `/msuf2` slash.

- `Menu2/Pages/MSUF_Menu2_Unit.lua`
  - Native pages for Player, Target, ToT, Focus, Pet, Boss.
  - Latest relevant change: Unit Status Icons now use an indicator selector pattern.

- `Menu2/Pages/MSUF_Menu2_Group.lua`
  - Native group frame layout, health/text, buffs/debuffs, indicators.
  - Latest relevant change: Group indicators got status icon selector, spell indicator bindings, and corner indicator dropdowns.

- `Menu2/Pages/MSUF_Menu2_Global.lua`
  - Global style pages: bars, fonts, unit auras, castbar, colors, misc/gameplay.
  - Recent work expanded Misc, Bars/Fonts style parity still may be incomplete per user reports.

- `Menu2/Pages/MSUF_Menu2_Advanced.lua`
  - Class resources, profiles, style/module/advanced pages.
  - Recent work expanded Class Resources, but user says Misc and Class Resource still miss much.

## Latest User Complaints Before Handoff

The user reported:

- Indicators are broken everywhere.
- Dropdowns/options for indicators are missing.
- Checkmarks/toggles are still visually wrong.
- Many menus still differ from old MSUF, especially sliders, colors, fonts, bars, castbar, colors, misc, class resources.
- Group preview in old MSUF was reportedly broken earlier. Do not assume old MSUF is safe; verify any touched old-option file carefully.

## Latest Changes Implemented

### Unit Status Icons

File: `MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_Unit.lua`

New native selector-style section:
- Dropdown: `Indicator`
- Toggle: `Use Midnight style`
- Toggle: `Enabled`
- Dropdown: `Symbol` for combat/rested/res indicators
- Slider: `Size`
- Dropdown: `Anchor`
- Sliders: `X Offset`, `Y Offset`, `Layer`
- Button: `Reset selected`
- Buttons: `Preview current`, `Show all`
- Toggle: `Test mode`

New/expanded indicator specs include:
- Leader / Assist
- Raid Marker
- Level
- Elite / Rare
- Dead Text
- Combat
- Rested
- Incoming Rez

Runtime calls used:
- `MSUF_UFPreview_SelectStatusIcon`
- `MSUF_UFPreview_SetStatusPreviewMode`
- `MSUF_RequestStatusIconsRefreshForCurrent`
- `MSUF_RefreshStatusIndicators`
- indicator-specific refresh globals where available

Needs in-game verification:
- Symbol dropdown visibility/reposition in WoW.
- Preview current/show all actually updates preview.
- Per-unit allowed indicator list matches old menu.
- Check if `statusIconsUseMidnightStyle` should be global only or per-unit override.

### Group Indicators

File: `MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_Group.lua`

Status Icons section now has:
- `Icon style` dropdown backed by `GF.ICON_STYLE_ITEMS` when available.
- `Use Midnight Style`
- `Indicator` selector dropdown
- `Enabled`
- `Size`
- `Anchor`
- `X Offset`
- `Y Offset`
- `Layer`
- `Reset selected`
- `Preview current`
- `Show all`

Group status specs include:
- Role Icon
- Leader
- Assist
- Raid Marker
- Ready Check
- Summon
- Resurrect
- Phase
- Dead Text
- Ghost Text
- AFK / DND Text

Spell Indicators section was changed away from bad flat keys:
- Uses `conf.spellIndicators` via `SpellIndicators(kind)`.
- Adds `Spec` dropdown.
- Adds `Spell` dropdown from `GF.SpellIndicators.TrackableAuras`.
- Adds selected spell enabled, only-my-cast, indicator type, anchor, size, X/Y, bar width, growth, frame effect.

Corner Indicators section was changed away from bad flat aura keys:
- Uses real `ci*` fields from group config.
- Adds enable, icon size, alpha, slot dropdown, slot indicator dropdown, custom spell IDs, custom mode, custom filter, custom color.

Needs in-game verification:
- `SpellAuraValues()` depends on `GF.SpellIndicators.SpecInfo` and `TrackableAuras`. If the module is not loaded yet, dropdown may show "No spells for current spec".
- Spell indicator per-spell UI is still much simpler than old `MSUF_Options_GF_Auras.lua`. It is not full 1:1 yet.
- Corner custom editor is simpler than old UI. It has the core fields but not the exact tab layout.
- Status preview mode buttons should be verified against `GF.SetStatusPreviewMode` and `GF._PreviewSelectStatusIcon`.

### Checkmarks

File: `MidnightSimpleUnitFrames/Menu2/MSUF_Menu2_Theme.lua`

`T.StyleCheckmark(checkButton)` now:
- Calls old text style helper if present.
- Strips all Blizzard checkbox template textures.
- Draws a dark superellipse base with `Media\superellipse.tga`.
- Draws rim with `Media\msuf_check_superellipse_hole.tga`.
- Draws tick with `Media\msuf_check_tick_bold.tga`.
- Hooks `OnShow`, `OnClick`, hover, `SetChecked`, `SetEnabled`.

Needs in-game verification:
- Whether `.tga` rim/base matches old UI precisely.
- Whether the old menu uses `.png` in some places and `.tga` in others. Current Menu2 media list has `.tga` assets.
- Whether text color changes from old `MSUF_StyleToggleText` conflict with Menu2 colors.

## Validation Already Run

These passed after the latest indicator/checkmark changes:

```powershell
luac -p "MidnightSimpleUnitFrames/Menu2/MSUF_Menu2_Theme.lua" `
        "MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_Unit.lua" `
        "MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_Group.lua"

$files = rg --files "MidnightSimpleUnitFrames/Menu2" | Where-Object { $_ -like "*.lua" }
luac -p $files

git diff --check -- `
  "MidnightSimpleUnitFrames/Menu2/MSUF_Menu2_Theme.lua" `
  "MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_Unit.lua" `
  "MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_Group.lua"
```

Also checked:

```powershell
rg -n "spellIndicatorsEnabled|spellIndicatorSize|cornerIndicatorsEnabled|cornerIndicatorSize|cornerIndicatorInset|cornerIndicatorSpacing" "MidnightSimpleUnitFrames/Menu2"
```

No matches after patch, which is good because those were wrong flat keys.

## Critical Next Steps

1. Start with the user's next screenshot comparison, not assumptions.
2. If checkmarks still look wrong, compare Menu2 `T.StyleCheckmark` with old `MSUF_ApplyMenuCheckboxStyle` in `Options/MSUF_Options_Auras.lua` and/or `StyleCheckmark` in `Options/MSUF_Options_Toolkit.lua`.
3. Verify MSUF2 Indicator pages in WoW:
   - Unit page: Player/Target/Focus/ToT/Pet/Boss status icons.
   - Group page: Layout/Health/Text/Buffs/Indicators status icons.
   - Confirm dropdowns are present and save to the right DB keys.
4. Bring `Spell Indicators` closer to old `Options/MSUF_Options_GF_Auras.lua`:
   - Old UI has spec dropdown, multi-spec, tile grid, per-spell config panels, placed indicator and frame effect config.
   - Current MSUF2 has a simplified selector/control model.
5. Bring `Corner Indicators` closer to old UI:
   - Old UI has 5 slot dropdowns visible, size/alpha, tabbed custom spell editor.
   - Current MSUF2 has slot selector plus selected-slot editor.
6. Continue parity for Misc and Class Resources:
   - User explicitly said Misc and Class Resource still miss much.
7. Keep old MSUF intact.

## Useful Old Source References

Unit indicator old menu:
- `MidnightSimpleUnitFrames/Options/MSUF_Options_Player.lua`
  - Indicator specs around the top, including `INDICATOR_SPECS`, `STATUS_ICON_DEFS`.
  - Status Icons selector UI around the section starting near old line ~2180.
  - Handler logic near old line ~3620.

Group status icons old menu:
- `MidnightSimpleUnitFrames/Options/MSUF_Options_GF.lua`
  - Status icon selector section around old line ~3240.
  - Uses `GF.ICON_STYLE_ITEMS`, `GF.SetStatusPreviewMode`, `GF._PreviewSelectStatusIcon`.

Group spell/corner indicators old menu:
- `MidnightSimpleUnitFrames/Options/MSUF_Options_GF_Auras.lua`
  - Spell Indicators section around old line ~1500.
  - Corner Indicators section around old line ~2950.

Group runtime:
- `MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_DB.lua`
  - GF defaults, `ICON_STYLE_ITEMS`, `GetDefault`.
- `MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Render.lua`
  - Real status icon layout/render keys.
- `MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_SpellIndicators.lua`
  - Runtime expects `conf.spellIndicators`.
- `MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_CornerIndicators.lua`
  - Runtime expects `ciEnabled`, `ciSize`, `ciAlpha`, `ciSlotTL/TR/BL/BR/C`, `ciCustom*`.

## Known Risk Areas

- `Menu2/` is untracked. `git diff` will not show it unless files are added or inspected directly.
- Dynamic dropdown value functions are used in Menu2. If a runtime module is not loaded when Menu2 builds, some dropdowns may have fallback values.
- WoW `MenuUtil.CreateContextMenu` uses `item.value` or `item.key`; current widgets support both.
- Some old option helpers use `{ key=..., label=... }`; Menu2 dropdown supports these but verify display text.
- `T.StyleCheckmark` currently strips the default checked texture. If another style helper later re-adds it, the hook should resync, but visually verify.
- Do not use destructive git commands. There are existing modifications not all made in the latest turn.

## Recommended First Prompt For Next Chat

```text
Read MSUF2_HANDOFF.md first. Continue the native MSUF2 menu parity work. Do not mirror old panels. Current priority: verify/fix indicators and checkmark/toggle visual parity against old MSUF, then Misc and Class Resources missing options.
```

