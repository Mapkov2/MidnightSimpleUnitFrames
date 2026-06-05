# Assistant Capability Audit

Generated from the current implementation after the Assistant registry split and the latest UI-control matrix pass.

## A. Executive Summary

What works now:

- The Assistant registry split is in place. `MSUF_AssistantRegistry.lua` is a small loader/manifest, and no Assistant registry file is a 300 KB monolith.
- The Assistant parser split is in place. `MSUF_AssistantParser.lua` now only owns the final parse pipeline and `A.Parse`, while parser domains live in focused files such as `MSUF_AssistantParser_Core.lua`, `MSUF_AssistantParser_Profiles.lua`, `MSUF_AssistantParser_Actions.lua`, `MSUF_AssistantParser_Registry.lua`, `MSUF_AssistantParser_Features.lua`, `MSUF_AssistantParser_Geometry.lua`, and `MSUF_AssistantParser_Followups.lua`.
- `Shell/Menu2/MSUF_Menu2.xml` loads the Assistant loader, core registry, domain registry files, parser/runtime, and dashboard in order.
- The Dashboard Assistant input callback crash is fixed; the input field can call the parser path without nil callback errors.
- The offline registry harness loads `2584` settings and `117` actions.
- The strict UI matrix now reports `704` UI rows: `603` registered, `2` partial, `54` documented TODO, and `45` unmapped.
- In the current matrix there are no non-aura rows left with status `unmapped`, `partial`, or `todo`; the remaining matrix gaps are Aura/Group Aura rows that are intentionally out of scope for this pass.
- Recent parity passes closed `AdvancedGameplay`, `GlobalFonts`, `GlobalBars`, non-aura `AdvancedColors` persistent settings/actions plus token selectors, `GroupLayout` including custom-anchor picker/direct frame-name control, GroupBars text tab/slot/move-together selectors, UnitText and UnitStatus selectors, GroupIndicators settings plus status/spell/corner selectors, profile staging fields, Group Copy category staging, NavRail section/search-intro state, profile action surface, and profile/class-resource/dashboard setup diagnostics.
- Unitframe and castbar registry coverage remains broad: frame basics, anchoring, portrait, power, detailed text, transparency, range fade, load conditions, status icons, unit castbars, global castbar controls, previews/resets where shared helpers exist, copy/reset/preset flows, profiles, diagnostics, setup, navigation, undo/redo, and Edit Mode lifecycle controls.
- Parser smoke coverage now includes left-nav page shortcuts for Pet and Target of Target, NavRail section/search-intro actions, group-frame class color mode routing for `raidframe` and generic `group frames`, root castbar toggles, unit castbar detail toggles, and Menu2 selector-state commands including text move-together mode.
- Dashboard-path context now resolves short page-local and follow-up commands through the same Assistant input route the user uses in-game. Examples covered by smoke tests include `turn off name` on the Player page, `turn off name` on Group Health & Text with the current `gfScope`, and `turn off frame` after the Assistant has established a Player or Raid context.
- Search, FAQ, and help data are reachable through the Assistant Knowledge path. Explicit Search/Find/Where/FAQ/Explain queries now go to Knowledge before page-open parsing, query verbs are stripped before scoring, and no-match search/help requests return a deterministic Assistant no-match response instead of a fake setting failure. Public Search result openings now submit to the Assistant first, leaving the native Search page as an internal/fallback result renderer instead of a second user-facing command system.
- Menu2 shell controls are now counted by the UI matrix and mapped through shared helpers for close, minimize, maximize/restore, and minimized-bar restore. Dashboard disclosure headers, NavRail disclosure/search-intro state, and Assistant-opened page back navigation are counted and mapped through shared Assistant navigation actions.
- The legacy Dashboard command-center fallback is no longer counted as an open non-aura gap: normal XML load order builds `MSUF.Assistant.BuildDashboardCard`, and the Dashboard-path smoke tests cover the real `A.Submit` input/result route.

Partial or missing:

- Full UI-row parity is not complete because Auras are intentionally out of scope. The remaining `unmapped`, `partial`, and `todo` matrix rows are Aura and Group Aura rows only.
- Aura whitelist-style operations and several aura style/placement/filter helper rows are still not fully mapped.
- Assistant-opened Dashboard page back navigation is registered and covered by Dashboard-path smoke tests. Native menu-history undo/redo/session reset is registered through the same helpers as the NavRail history buttons. Native page history outside the Assistant page stack remains dependent on future shared Menu2 helpers.
- Short parser aliases for `help`, scoped `help for ...`, `copy profile NAME`, and `rename profile OLD to NEW` are covered by smoke tests. Explicit source-profile copy flow, unit copy, Unit Copy category staging, Group Copy category staging, and Dashboard-path `A.Submit` routing are also covered by focused smoke tests.

## B. Current Numbers

| Metric | Count |
| --- | ---: |
| Registered settings | 2584 |
| Registered actions | 117 |
| Registered diagnostic actions | 12 |
| Registered navigation actions | 16 |
| Verified visible left-nav targets | 24 |
| UI matrix rows | 704 |
| UI matrix registered rows | 603 |
| UI matrix partial rows | 2 |
| UI matrix TODO rows | 54 |
| UI matrix unmapped rows | 45 |
| Non-aura unmapped rows | 0 |

Setting type counts: `{'boolean': 744, 'number': 1046, 'enum': 523, 'string': 90, 'color': 182}`

Action type counts: `{'auras': 6, 'classPower': 1, 'color': 16, 'configure': 3, 'copy': 2, 'diagnostic': 12, 'fonts': 2, 'gameplay': 3, 'globalBars': 5, 'history': 5, 'navigation': 16, 'preset': 2, 'preview': 3, 'profile': 18, 'reset': 13, 'setup': 8, 'support': 2}`

Full matrix: `MidnightSimpleUnitFrames/docs/ASSISTANT_REGISTRY_MATRIX.tsv`

## C. Current Matrix Remainders

| UI file | Non-registered rows | Main reason |
| --- | ---: | --- |
| `MSUF_Menu2_Advanced.lua` | 45 | Aura setup controls; intentionally documented TODO for this non-aura pass. |
| `MSUF_Menu2_Auras.lua` | 37 | Aura style, placement, text, color sample, blacklist/preset, and filter helper rows still need explicit mapping or safe actions. |
| `MSUF_Menu2_AdvancedColors.lua` | 9 | Aura-color controls; non-aura persistent color settings/actions and token selectors are registered. |
| `MSUF_Menu2_GroupAuras.lua` | 10 | Group aura placement controls; aura feature work is intentionally out of scope for this non-aura pass. |

Partial rows are Aura-only in this non-aura pass:

- Aura text/style rows with multiple possible aura scope matches.

## D. Coverage By Area

| Area | Current status |
| --- | --- |
| Frames | Broad setting/action coverage for visible unit pages, including basics, anchoring, portrait, power, detailed text, text/status selector state, alpha, range, status, load conditions, copy/reset, custom anchor start/clear/direct frame-name control, and unit castbars. |
| Group Frames | Layout, Health/Text, Bars, Indicators, selector state, text move-together editor state, custom anchor start/clear/direct frame-name control, and group copy-to have broad party/raid/mythic raid registry coverage. Remaining rows are ambiguous helper rows or staging. |
| Auras | Shared/player/target/focus/boss and group aura registries exist, but this remains the largest matrix gap. Style/placement/filter/blacklist helper rows need the next focused pass. |
| Appearance / Bars | Global Bars matrix rows are currently closed, including persistent settings, scoped override settings, ONLY-style scoped override parsing, and preview/test actions. |
| Appearance / Castbars | Global Castbars rows are currently closed, including preview unit/type/interrupt buttons through the shared castbar preview action. Unit castbar controls and Focus Kick controls are covered. |
| Appearance / Colors | Broad non-aura color registry coverage exists, including class colors, power-token colors and selectors, class-resource token colors/backgrounds and selectors, portrait colors, NPC reactions/types, dispel colors, bar colors, castbar colors, and reset actions. Remaining rows are aura-color controls. |
| Appearance / Fonts | Global Fonts matrix rows are currently closed, including shared/scoped font overrides, outlines, name colors, NPC/boss name colors, name-shortening controls, and ONLY-style scoped override parsing. |
| Appearance / Class Resources | Registry coverage exists for class resource settings; current class-power page rows are registered, including natural movement, width-mode, opacity, prediction, Alternative Mana, quick setup, and diagnostics. |
| Appearance / Gameplay | AdvancedGameplay matrix rows are currently closed, including Combat Timer, Combat Enter/Leave text, TotemFrame preview/reset/layout, First Dance, Crosshair size/thickness/range-color/spell input, and MSUF Edit Mode button. |
| Profiles | Profile create, copy, rename, switch, reset, delete, export/import, legacy import, spec auto-switch, spec mapping, Wago link, dropdown style, and profile staging fields are registered. |
| Dashboard / Navigation | Page-open navigation, Assistant page-stack back navigation, dashboard panel open/close/toggle, NavRail section disclosure/search-intro state, scaling settings, visible page-label shortcuts, Menu2 shell close/minimize/maximize/restore, Assistant Undo/Redo, and native MSUF menu history undo/redo/session-reset helpers are registered. Native UI-only page history outside the Assistant page stack still needs shared Menu2 helpers before it can be controlled safely. |
| Diagnostics / Setup | Unitframe, group-frame, castbar, profile, class-resource, dashboard/setup, Assistant status/help, scoped help, Edit Mode status, guided setup, factory reset staging, and support flows are registered. Aura-specific and deeper branch-specific troubleshooters remain TODO. |

## E. Workflow Lifecycle Coverage

| Workflow | Start/enter | Confirm/apply | Cancel | Exit/stop | Toggle | Status/diagnostic | Current status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MSUF Edit Mode | yes | yes | yes | yes | yes | yes | Complete when shared helpers are available. |
| Profile Import | yes | yes | yes | n/a | n/a | yes | Works for active, new, and legacy import helpers. |
| Profile Export | yes | n/a | n/a | n/a | n/a | yes | Works if `MSUF_ExportSelectionToString` exists. |
| Profile Switch | yes | yes | n/a | n/a | n/a | yes | Works if the profile exists and the switch helper exists. |
| Profile Copy | yes | yes | yes | n/a | n/a | yes | Works with confirmation and profile snapshot support. |
| Profile Delete | yes | yes | yes | n/a | n/a | yes | Works with confirmation and profile snapshot support. |
| Profile Reset | yes | yes | yes | n/a | n/a | yes | Works through the shared profiles reset path. |
| Factory Reset | yes | yes | yes | n/a | n/a | status/TODO | Stages reset through `M.StageFactoryReset`. |
| Copy-To | yes | yes | yes/implicit | n/a | n/a | action response | Unit and group category-scoped copy phrases are covered. |
| Guided Setup | yes | n/a | yes | finish/stop | n/a | yes | Start, next, back, skip, show, finish, and cancel work. |
| Dashboard Recovery/Wago Backup | yes | yes | n/a | n/a | n/a | status/support summary | Open recovery/scaling/changelog and Wago backup confirm/clear work. |

## F. Parser Capability And Known Gaps

Currently understood:

- Boolean commands such as `turn on player name`, `hide target frame`, and `turn off combat timer`.
- Numeric commands such as `set player width to 300`, `set class resource height to 12`, `move class resource down 5`, page-local Class Resource commands such as `set background opacity to 40`, and Gameplay commands such as `move combat timer down 10`, `set crosshair size to 44`, and `make crosshair thicker by 2`.
- Relative movement/size commands such as `move player frame right 10` and `make player frame wider`.
- Enum, string, and color routing through registered setting aliases.
- Relative numeric registry commands such as `increase player width by 5`, `decrease player name font size by 2`, `increase player alpha by 5`, and `decrease castbar outline thickness by 1`.
- Detail pixel movement for unitframe elements such as `move player portrait 5 right`, `move player name text 5 right`, and natural label wording like `move player unit name label up 2`.
- Generic unit and group opacity shortcuts such as `set player alpha to 50`, `set raid alpha to 50`, and page-local `set alpha to 60`, which apply the existing in-combat and out-of-combat opacity settings together for the selected unit or group scope.
- Left-nav page navigation through explicit open phrases, `... settings` shortcuts, and bare visible page labels when the phrase has no setting-change intent.
- Current-page and conversation context for short local commands. Unit pages can resolve bare unit text commands such as `turn off name`, relative text movement such as `move health down 4`, exact text-offset slider values such as `set hp y offset to -8`, left/center/right HP/Power text-slot dropdown values and offsets such as `set left hp text to current` and `move left hp text down 3`, page-local text-size and text-layer slider values such as `set hp text size to 18` and `set hp text layer to 8`, and HP/Power text-anchor/alignment phrasing as slot selection such as `set player hp text anchor to right` or `align player hp text left`; Group Frame pages first use the current `M.gfScope` before falling back to broader group choices, including text movement such as `move hp down 4`, exact phrases such as `move party frame name down`, plural/possessive wording such as `move the party frames name down` and `move party names up 2`, exact offset values such as `set hp y offset to -8`, left/center/right HP/Power text-slot dropdown values and offsets such as `set center hp text to percent`, `set center hp text x offset to 5`, `move party hp left text down 3`, and `move raid right power label up 2`, page-local group text-size and text-layer values such as `set hp text size to 13` and `set hp text layer to 7`, and group HP/Power text-anchor/put-on-left-right slot aliases; follow-ups such as `turn off frame` can reuse the last Assistant unit/group context when no new target is named. Last-change replay also handles natural phrases such as `same for target`, `same for raid`, `do that for focus`, and scoped Appearance follow-ups like `same for party`.
- Unit castbar root/detail routing: `turn off target castbar` targets the castbar itself, while `turn off target castbar name/icon/time/interrupt/channel ticks/glow/spark/latency/unified direction` targets the specific detail setting.
- Natural aliases for scoped bar border/outline colors and SharedMedia texture strings, such as `set player border color to red`, exact RGB/hex color picker values such as `set player border color to rgb 255 128 0` and `set castbar text color to #336699`, color follow-ups such as `same for target`, and `set bars texture to Smooth`.
- Bars/Fonts `only` phrasing is treated as scoped override intent. Examples: `only player bars on` toggles `barScope.player.override`; `set only party bars dispel border off` enables `barScope.gf_party.override` and changes the party scoped dispel-border setting; `set target font outline only to THICKOUTLINE` enables `fontScope.target.override` and changes the scoped font outline.
- Reset, copy, preset, profile, support, diagnostic, setup, dashboard, navigation, undo/redo, and Edit Mode actions, including natural reset phrases for unit positions/pages, scoped Bars/Fonts overrides, unit and group category-scoped copy, TotemFrame layout, group status icons, and concrete group spell-indicator aura reset requests.
- Profile commands for summary, export, import, create, switch, delete, copy, short `copy profile NAME`, spec auto-switch, and spec mapping where parser phrasing matches.
- Group health color, group-frame class color mode for Raid/Party/Mythic Raid, Group Layout anchor target, growth direction, frame scaling/manual scale/breakpoint scale, and specific backdrop/HP opacity sliders, group status icon preview/reset, group text/status/spell/corner selector state, individual group name/HP/power text movement plus exact X/Y offset, left/center/right text-slot dropdown/offset, text-layer slider values, and group/unit text move-together editor state including natural `individual text units` wording, Group Copy category staging, Profile staging fields, custom anchor direct frame-name control, color token selector state, dispel border test type, Global Fonts name shortening, and AdvancedGameplay commands from the latest passes.
- Gameplay page context and natural aliases for Combat Timer, Combat Enter/Leave, TotemFrame, First Dance, and Combat Crosshair. Covered examples include `turn on timer` on the Gameplay page, `move timer down 5`, `set timer anchor to target`, `set combat enter text to Pulling`, `move totem frame right 6`, `set totem frame to anchor to bottom left`, `turn off first dance ready`, `set crosshair size to 44`, `make crosshair thicker by 2`, `turn on crosshair range color`, and `set crosshair spell to 12345`.

Parser examples and remaining incomplete commands:

- `help`: parsed through general Assistant help.
- `help for player frame`: parsed through scoped Assistant help.
- `copy profile Test`: parsed as copy-current-profile-to-name.
- `copy from profile Test`: starts the source-profile copy workflow and asks for the destination name.
- `set profile name field to Raid Draft`: stages the Profiles create/copy name input.
- `select profile export kind group frames`: stages the Profiles export-kind dropdown.
- `set profile string field to MSUF5:...`: stages the Profiles profile-string input without importing.
- `clear player copy categories`: clears the Unit Copy popup category state and opens the Player page.
- `select only unit copy text and castbar categories`: sets the Unit Copy popup category state to only Text and Castbar.
- `clear group copy categories`: clears the Group Frames copy-popup category state.
- `copy player text and castbar to target`: parsed as unit copy with only Text and Castbar scopes enabled.
- `copy party health and text to raid`: parsed as group-frame copy with only Health and Text scopes enabled.
- `rename profile Test to New`: parsed as a confirmed profile rename through `MSUF_RenameProfile`.
- `set target castbar text x offset to 3`: parsed as the registered target castbar spell-text X offset setting.
- `set combat timer alpha to 50`: not routed because the Combat Timer UI has no alpha slider; its colors are configured through Colors > Gameplay.
- `move crosshair down 5`: intentionally reports that Crosshair position is not exposed by the current MSUF UI/DB; registered Crosshair controls are enable, range-color mode, melee spell, per-class/per-spec storage, thickness, size, and Colors > Gameplay swatches.

## G. Profile Operation Status

| Operation | Status | Helper used | Confirmation | Undo/backup support |
| --- | --- | --- | --- | --- |
| Profile summary | Works | internal `Profile.SummaryText` | no | n/a |
| Export current profile | Works if helper exists | `MSUF_ExportSelectionToString` | no | n/a |
| Import profile | Works if helper exists | `MSUF_ImportFromString` | yes | snapshot/profile snapshot |
| Import new profile | Works if helpers exist | `MSUF_CreateProfile`, `MSUF_SwitchProfile`, `MSUF_ImportFromString` | yes | snapshot/profile snapshot and rollback path |
| Legacy import | Works if helper exists | `MSUF_ImportLegacyFromString` | yes | snapshot/profile snapshot |
| Create profile | Works if helper exists | `MSUF_CreateProfile`, optional `MSUF_SwitchProfile` | no | snapshot/profile snapshot |
| Copy profile | Works if helper exists | `MSUF_CopyProfile`, optional `MSUF_SwitchProfile` | yes | snapshot/profile snapshot |
| Switch profile | Works if helper exists | `MSUF_SwitchProfile` | no | snapshot/profile snapshot |
| Spec auto-switch | Works | helper or DB fallback | no | setting undo |
| Spec-profile mapping | Works if spec data/helper/fallback is available | `MSUF_SetSpecProfile` or DB fallback | no | snapshot/profile snapshot |
| Delete profile | Works if helper exists | `MSUF_DeleteProfile` | yes | snapshot/profile snapshot |
| Rename profile | Works if helper exists | `MSUF_RenameProfile` | yes | snapshot/profile snapshot |
| Reset profile | Works if helper exists | `M.ResetPageToDefaults("profiles")` | yes | snapshot/profile snapshot |
| Factory reset | Works/stages reset if helper exists | `M.StageFactoryReset` | yes | profile snapshot requested |

## H. Validation Results

- Python syntax: `python -m py_compile tools\assistant_ui_inventory.py` passed.
- Lua syntax: `luac -p` over all Assistant Lua files passed.
- Inventory regeneration: `python tools\assistant_ui_inventory.py` passed and regenerated `ASSISTANT_REGISTRY_MATRIX.tsv`.
- Offline parser smoke: passed for group health color, group status icon preview, dispel border test type, castbar preview, profile export, shared global font, shared name shortening, combat enter text, TotemFrame preview, Crosshair melee spell, Undo/Redo action registration, Power Bar token reset action registration, UnitText slot/delimiter/slot-offset commands, Tooltip Modifier, Detached Power Bar width mode, and MSUF Frame Scale.
- Focused parser smoke: `lua tools\assistant_parser_smoke.lua` passed for Pet/Target of Target page navigation, page-label shortcuts, Dashboard page-back actions, Dashboard panel open/close/toggle actions, NavRail section/search-intro actions, Menu2 shell close/minimize/maximize/restore actions, native MSUF menu history undo/redo/session-reset actions, general/scoped help aliases, short profile-copy aliases, explicit profile-copy workflow start, profile rename aliases, profile staging fields, Unit Copy and Group Copy category staging, unit and group copy category scopes, global UI scale presets, guided setup start/step/cancel, support links, Wago backup confirmation, Edit Mode lifecycle/status, diagnostics including profile/class-resource/dashboard setup diagnostics, last-change replay for Unit/Group/scoped Bars targets including color values, factory reset staging, natural reset phrases, Bars/Fonts ONLY scoped override routing, group-frame class color mode for `raidframe` and generic `group frames`, Group Layout anchor target, natural growth wording, manual frame scale, numbered breakpoint scale commands, and backdrop/HP opacity sliders, direct unit/group custom anchor frame-name commands, individual unit/group name/HP/power text movement including `health`/`hp`/`mana`, `party frame name`, plural names, and label shorthand, exact unit/group text X/Y offset slider values, left/center/right HP/Power text-slot dropdown and offset commands, Name/HP/Power text-size and text-layer slider commands with explicit and current-page scope, HP/Power text-anchor/alignment/put-on-left-right aliases mapped to the visible slot selector, exact RGB/hex values for registered color pickers, dark-mode bar-color slider phrasing such as `make unitframe dark mode a bit lighter`, `super dark`, `20 percent`, and `darker by 5`, Class Resource movement/width-mode/background-opacity/prediction/Alternative-Mana commands, Gameplay root toggles, page-local Combat Timer commands, Combat Enter/Leave text/size/duration/movement, TotemFrame enable/size/movement/anchors, First Dance enable/size/movement/ready toggle, Crosshair size/thickness/range-color/per-spec/spell commands and explicit Crosshair-position unknown handling, Menu2 selector-state actions including text move-together mode and `individual text units` phrasing, scoped bar border color/texture aliases, relative numeric registry changes, unit detail pixel moves, unit/group opacity shortcuts, root castbar toggle, castbar spell-name/text/icon/time/interrupt/channel-tick/glow/spark/latency/unified-direction detail toggles, castbar text color, castbar spell-text offset, and Pet frame movement.
- Dashboard-path smoke: `lua tools\assistant_dashboard_smoke.lua` passed through `A.Submit` for real setting mutation/apply callbacks, German/English natural requests such as `spieler name aus`, `spieler frame einschalten`, `verschiebe spieler lebensanzeige runter 4`, `verschiebe ziel energie hoch 2`, `setze spieler breite auf 222`, `ziel zauberleiste ausschalten`, and `oeffne spieler`, context follow-up such as `turn it back on` after disabling Player Frame, current-page bare-command routing for Player, Group Health & Text `gfScope`, and Gameplay page commands such as `turn on timer`, `move timer down 5`, and `set timer anchor to target`, current-page unit/group text movement such as `move health down 4`, `move hp down 4`, `move party frame name down`, and `move party hp left text down 3`, current-page exact text-offset values such as `set hp y offset to -8`, current-page left/center/right text-slot dropdown and offset mutation, current-page Name/HP/Power text-size and text-layer slider mutation, current-page group opacity mutation, Class Resources page-context mutation such as `set width mode to custom`, `set background opacity to 40`, and `turn off prediction`, Gameplay mutation for Combat Timer, Combat Enter/Leave, TotemFrame, First Dance, and Crosshair controls, conversation-context routing for bare `turn off frame` follow-ups on Player and Raid, last-change replay such as `same for target`, `same for raid`, `do that for focus`, and `same for party`, Assistant page-stack back navigation through `open player` -> `open target` -> `back`, native menu history undo/redo/session-reset helper calls, profile/class-resource/dashboard setup diagnostics, group-frame class color mode mutation, Group Layout anchor target, natural growth wording, manual frame scale, numbered breakpoint scale mutation, and backdrop/HP opacity slider mutation, direct custom anchor frame-name mutation, individual unit/group name/HP/power text movement and exact X/Y text-offset slider mutation, HP/Power text-anchor/alignment/put-on-left-right slot selector routing, Unit Copy and Group Copy category-state mutation, scoped bar color picker RGB mutation and color replay to another scope, dark-mode bar-color slider mutation including exact percent and relative darker/lighter commands, profile staging-field mutation, Menu2 selector-state mutation including text move-together mode and `individual text units` phrasing, confirmation cancel, NavRail section/search-intro state, confirmed profile rename through `MSUF_RenameProfile`, numbered/worded ambiguity resolution, public Search result openings routed back through `A.Submit`, Knowledge/Search/FAQ answers including German profile help and no-match search responses, help/current-page fallback, and Assistant history recording.
- XML parse: `Shell/Menu2/MSUF_Menu2.xml` parsed successfully. The addon TOC references it at line 157.
- Assistant load order: `MSUF_Menu2.xml` loads registry files first, then Assistant media resolution, parser domain modules, the final parser pipeline, Assistant runtime, Dashboard, Knowledge, Router, and Queue.
- Safety scan over `Shell/Menu2/Assistant` for `C_Timer.NewTicker`, `SlashCmdList`, and `http` returned no hits.

## I. Next Implementation Phases

1. Close the remaining Auras and Group Auras matrix rows first; they are the only remaining `unmapped` block.
2. Improve the inventory scanner so helper callsites such as `CH.ButtonAt`, `ValueDropdownAt`, and similar wrappers are counted as concrete UI controls without also counting representative factory rows.
3. Add aura-specific diagnostics and deeper branch-specific guided setup troubleshooters.
4. Add native Menu2 UI-history control only after safe shared helpers exist; Assistant-opened page back navigation is already covered.
5. Extend parser aliases for common short phrases once semantics are agreed.
