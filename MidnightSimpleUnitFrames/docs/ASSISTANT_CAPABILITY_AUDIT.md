# Assistant Capability Audit

Generated from the current implementation after the Assistant registry split and the latest UI-control matrix pass.

## A. Executive Summary

What works now:

- The Assistant registry split is in place. `MSUF_AssistantRegistry.lua` is a small loader/manifest, and no Assistant registry file is a 300 KB monolith.
- `Shell/Menu2/MSUF_Menu2.xml` loads the Assistant loader, core registry, domain registry files, parser/runtime, and dashboard in order.
- The Dashboard Assistant input callback crash is fixed; the input field can call the parser path without nil callback errors.
- The offline registry harness loads `2544` settings and `96` actions.
- The strict UI matrix now reports `704` UI rows: `579` registered, `10` partial, `70` documented TODO, and `45` unmapped.
- In the current matrix there are no non-aura rows left with status `unmapped`; non-aura leftovers are documented as `partial` or `todo` with an exact reason.
- Recent parity passes closed `AdvancedGameplay`, `GlobalFonts`, `GlobalBars`, non-aura `AdvancedColors` persistent settings/actions, `GroupLayout` except the interactive picker, `GroupBars` except UI-only text selectors, `GroupIndicators` except UI-only selected-item selectors, and the profile action surface except staging fields.
- Unitframe and castbar registry coverage remains broad: frame basics, anchoring, portrait, power, detailed text, transparency, range fade, load conditions, status icons, unit castbars, global castbar controls, previews/resets where shared helpers exist, copy/reset/preset flows, profiles, diagnostics, setup, navigation, undo/redo, and Edit Mode lifecycle controls.
- Parser smoke coverage now includes left-nav page shortcuts for Pet and Target of Target, root castbar toggles, and unit castbar detail toggles for spell name/text, icon, time, and interrupt visibility.
- Menu2 shell controls are now counted by the UI matrix and mapped through shared helpers for close, minimize, maximize/restore, and minimized-bar restore. Dashboard disclosure headers are counted and mapped through the shared panel-state action.

Partial or missing:

- Full UI-row parity is not complete. The remaining `unmapped` rows are now Aura and Group Aura rows only. Non-aura gaps are documented as staging fields or UI-only selectors.
- Aura whitelist-style operations and several aura style/placement/filter helper rows are still not fully mapped.
- Profile rename remains blocked because no shared public rename helper/action is exposed.
- Browser-style Menu2 back/history navigation is not registered as an Assistant workflow unless shared helpers are added. Window close/minimize/maximize/restore controls are registered.
- Short parser aliases for `help`, scoped `help for ...`, and `copy profile NAME` are covered by smoke tests. Unit and group copy category scopes are also covered by focused smoke tests.

## B. Current Numbers

| Metric | Count |
| --- | ---: |
| Registered settings | 2544 |
| Registered actions | 96 |
| Registered diagnostic actions | 7 |
| Registered navigation actions | 8 |
| Verified visible left-nav targets | 24 |
| UI matrix rows | 704 |
| UI matrix registered rows | 579 |
| UI matrix partial rows | 10 |
| UI matrix TODO rows | 70 |
| UI matrix unmapped rows | 45 |
| Non-aura unmapped rows | 0 |

Setting type counts: `{'boolean': 744, 'number': 1005, 'enum': 523, 'string': 90, 'color': 182}`

Action type counts: `{'reset': 13, 'preview': 3, 'copy': 2, 'preset': 2, 'auras': 6, 'configure': 3, 'classPower': 1, 'gameplay': 3, 'globalBars': 5, 'fonts': 2, 'color': 16, 'setup': 7, 'navigation': 8, 'history': 2, 'profile': 14, 'diagnostic': 7, 'support': 2}`

Full matrix: `MidnightSimpleUnitFrames/docs/ASSISTANT_REGISTRY_MATRIX.tsv`

## C. Current Matrix Remainders

| UI file | Non-registered rows | Main reason |
| --- | ---: | --- |
| `MSUF_Menu2_Advanced.lua` | 45 | Aura setup controls; intentionally documented TODO for this non-aura pass. |
| `MSUF_Menu2_Auras.lua` | 37 | Aura style, placement, text, color sample, blacklist/preset, and filter helper rows still need explicit mapping or safe actions. |
| `MSUF_Menu2_AdvancedColors.lua` | 11 | Runtime token selectors and aura-color controls; non-aura persistent color settings/actions are registered. |
| `MSUF_Menu2_GroupAuras.lua` | 10 | Group aura section helper rows are not yet statically mapped. |
| `MSUF_Menu2_AdvancedProfiles.lua` | 5 | Profile staging fields; Assistant actions already accept the staged values directly. |
| `MSUF_Menu2_GroupIndicators.lua` | 5 | Runtime selected indicator/spell/spec/slot selectors; Assistant targets concrete items by phrase. |
| `MSUF_Menu2_GroupBars.lua` | 3 | Runtime text-area/slot editor selectors; concrete group text settings are registered. |
| `MSUF_Menu2_UnitText.lua` | 2 | Runtime text-area/slot selectors; concrete unit text settings are registered. |
| `MSUF_Menu2_Dashboard.lua` | 1 | Transient parser-result buttons; concrete actions/settings are registered elsewhere. |
| `MSUF_Menu2_UnitStatusSection.lua` | 2 | Runtime selected status tab/indicator selectors; concrete status fields are registered. |
| `MSUF_Menu2_NavRail.lua` | 1 | UI-only section/search intro state. Page navigation and Undo/Redo are registered. |
| Other non-aura files | 3 | Copy-category staging and anchor picker overlays. |

Partial rows are intentional where the UI row is a staging input or runtime selector rather than the persistent operation itself:

- Profile name, export kind, profile string, import-new toggle, and new-profile name staging fields.
- Aura text anchor rows with multiple possible aura scope matches.
- Group copy category staging.
- Group and unit custom-anchor picker buttons.

## D. Coverage By Area

| Area | Current status |
| --- | --- |
| Frames | Broad setting/action coverage for visible unit pages, including basics, anchoring, portrait, power, detailed text, alpha, range, status, load conditions, copy/reset, custom anchor clear, and unit castbars. Remaining strict gaps are runtime text/status selectors and custom anchor pickers, documented as TODO/partial. |
| Group Frames | Layout, Health/Text, Bars, Indicators, and group copy-to have broad party/raid/mythic raid registry coverage. Remaining rows are UI-only selectors or the interactive anchor picker. |
| Auras | Shared/player/target/focus/boss and group aura registries exist, but this remains the largest matrix gap. Style/placement/filter/blacklist helper rows need the next focused pass. |
| Appearance / Bars | Global Bars matrix rows are currently closed, including persistent settings, scoped override settings, ONLY-style scoped override parsing, and preview/test actions. |
| Appearance / Castbars | Global Castbars rows are currently closed, including preview unit/type/interrupt buttons through the shared castbar preview action. Unit castbar controls and Focus Kick controls are covered. |
| Appearance / Colors | Broad non-aura color registry coverage exists, including class colors, power-token colors, class-resource token colors/backgrounds, portrait colors, NPC reactions/types, dispel colors, bar colors, castbar colors, and reset actions. Remaining rows are runtime token selectors or aura-color controls. |
| Appearance / Fonts | Global Fonts matrix rows are currently closed, including shared/scoped font overrides, outlines, name colors, NPC/boss name colors, name-shortening controls, and ONLY-style scoped override parsing. |
| Appearance / Class Resources | Registry coverage exists for class resource settings; current class-power page rows are registered. |
| Appearance / Gameplay | AdvancedGameplay matrix rows are currently closed, including Combat Enter/Leave text, TotemFrame preview/reset, Crosshair spell input, and MSUF Edit Mode button. |
| Profiles | Profile create, copy, switch, reset, delete, export/import, legacy import, spec auto-switch, spec mapping, Wago link, and dropdown style are registered. Five staging fields remain partial by design. |
| Dashboard / Navigation | Page-open navigation, dashboard panel open/close/toggle, scaling settings, visible page-label shortcuts, Menu2 shell close/minimize/maximize/restore, and Undo/Redo are registered. Browser-style back/history-stack navigation remains UI-only until shared helpers exist. |
| Diagnostics / Setup | Unitframe, group-frame, castbar, Assistant status/help, scoped help, Edit Mode status, guided setup, factory reset staging, and support flows are registered. Deeper page-specific troubleshooters remain TODO. |

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
- Numeric commands such as `set player width to 300` and `set class resource height to 12`.
- Relative movement/size commands such as `move player frame right 10` and `make player frame wider`.
- Enum, string, and color routing through registered setting aliases.
- Relative numeric registry commands such as `increase player width by 5`, `decrease player name font size by 2`, `increase player alpha by 5`, and `decrease castbar outline thickness by 1`.
- Detail pixel movement for unitframe elements such as `move player portrait 5 right` and `move player name text 5 right`.
- Generic unit opacity shortcuts such as `set player alpha to 50`, which apply the existing in-combat and out-of-combat opacity settings together.
- Left-nav page navigation through explicit open phrases, `... settings` shortcuts, and bare visible page labels when the phrase has no setting-change intent.
- Unit castbar root/detail routing: `turn off target castbar` targets the castbar itself, while `turn off target castbar name/icon/time/interrupt/channel ticks/glow/spark/latency/unified direction` targets the specific detail setting.
- Natural aliases for scoped bar border/outline colors and SharedMedia texture strings, such as `set player border color to red` and `set bars texture to Smooth`.
- Bars/Fonts `only` phrasing is treated as scoped override intent. Examples: `only player bars on` toggles `barScope.player.override`; `set only party bars dispel border off` enables `barScope.gf_party.override` and changes the party scoped dispel-border setting; `set target font outline only to THICKOUTLINE` enables `fontScope.target.override` and changes the scoped font outline.
- Reset, copy, preset, profile, support, diagnostic, setup, dashboard, navigation, undo/redo, and Edit Mode actions, including natural reset phrases for unit positions/pages, scoped Bars/Fonts overrides, unit and group category-scoped copy, TotemFrame layout, group status icons, and concrete group spell-indicator aura reset requests.
- Profile commands for summary, export, import, create, switch, delete, copy, short `copy profile NAME`, spec auto-switch, and spec mapping where parser phrasing matches.
- Group health color, group status icon preview/reset, dispel border test type, Global Fonts name shortening, and AdvancedGameplay commands from the latest passes.

Parser examples and remaining incomplete commands:

- `help`: parsed through general Assistant help.
- `help for player frame`: parsed through scoped Assistant help.
- `copy profile Test`: parsed as copy-current-profile-to-name.
- `copy player text and castbar to target`: parsed as unit copy with only Text and Castbar scopes enabled.
- `copy party health and text to raid`: parsed as group-frame copy with only Health and Text scopes enabled.
- `rename profile Test to New`: blocked by missing shared rename helper.
- `set target castbar text x offset to 3`: not routed because the current Global Castbars UI has no castbar text-offset control. The guard prevents accidental Class Resource text-offset changes.
- `set combat timer alpha to 50`: not routed because the Combat Timer UI has no alpha slider; its colors are configured through Colors > Gameplay.

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
| Rename profile | Blocked | none found | n/a | n/a |
| Reset profile | Works if helper exists | `M.ResetPageToDefaults("profiles")` | yes | snapshot/profile snapshot |
| Factory reset | Works/stages reset if helper exists | `M.StageFactoryReset` | yes | profile snapshot requested |

## H. Validation Results

- Python syntax: `python -m py_compile tools\assistant_ui_inventory.py` passed.
- Lua syntax: `luac -p` over all Assistant Lua files passed.
- Inventory regeneration: `python tools\assistant_ui_inventory.py` passed and regenerated `ASSISTANT_REGISTRY_MATRIX.tsv`.
- Offline parser smoke: passed for group health color, group status icon preview, dispel border test type, castbar preview, profile export, shared global font, shared name shortening, combat enter text, TotemFrame preview, Crosshair melee spell, Undo/Redo action registration, Power Bar token reset action registration, UnitText slot/delimiter/slot-offset commands, Tooltip Modifier, Detached Power Bar width mode, and MSUF Frame Scale.
- Focused parser smoke: `lua tools\assistant_parser_smoke.lua` passed for Pet/Target of Target page navigation, page-label shortcuts, Dashboard panel open/close/toggle actions, Menu2 shell close/minimize/maximize/restore actions, general/scoped help aliases, short profile-copy aliases, unit and group copy category scopes, global UI scale presets, guided setup start/step/cancel, support links, Wago backup confirmation, Edit Mode lifecycle/status, diagnostics, factory reset staging, natural reset phrases, Bars/Fonts ONLY scoped override routing, scoped bar border color/texture aliases, relative numeric registry changes, unit detail pixel moves, unit opacity shortcuts, root castbar toggle, castbar spell-name/text/icon/time/interrupt/channel-tick/glow/spark/latency/unified-direction detail toggles, castbar text color, and Pet frame movement.
- XML parse: `Shell/Menu2/MSUF_Menu2.xml` parsed successfully. The addon TOC references it at line 157.
- Assistant registry load order: `MSUF_Menu2.xml` loads loader, core, Unitframes, Castbars, Auras, GroupFrames, Boss, ClassPower, Gameplay, Global, Dashboard, Profiles, EditMode, and Diagnostics registry files in order.
- Safety scan over `Shell/Menu2/Assistant` for `C_Timer.NewTicker`, `SlashCmdList`, and `http` returned no hits.

## I. Next Implementation Phases

1. Close the remaining Auras and Group Auras matrix rows first; they are the only remaining `unmapped` block.
2. Improve the inventory scanner so helper callsites such as `CH.ButtonAt`, `ValueDropdownAt`, and similar wrappers are counted as concrete UI controls without also counting representative factory rows.
3. Add deeper page-specific diagnostics for auras, profiles, class resources, and dashboard/setup failures.
4. Add Dashboard back/nav-history and profile rename only after safe shared helpers exist.
5. Extend parser aliases for common short phrases once semantics are agreed.
