# Assistant Workflow Lifecycle Coverage

This matrix tracks stateful Assistant workflows beyond raw settings coverage.

| Workflow / action family | Start | Confirm/apply | Cancel | Exit/stop | Toggle | Status/diagnostic | Existing helper used | Blocked / TODO reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MSUF Edit Mode (`assistant.action.editMode.enter`) | yes | yes | yes | yes | yes | yes | `M.SetMSUFEditModeActive`, `M.CancelMSUFEditMode`, `M.ToggleMSUFEditMode`; backed by direct Edit Mode helpers when available | Complete for shared MSUF Edit Mode helpers. If helper exports are unavailable at runtime, Assistant reports the missing enter, exit, or cancel helper. |
| Profile import into active profile | yes | yes | yes | n/a | n/a | yes | `MSUF_ImportFromString`, Assistant confirmation queue, large text import panel | Complete for active-profile import. Cancel is handled by confirmation cancel or closing the import panel. |
| Profile import into new profile | yes | yes | yes | n/a | n/a | yes | `MSUF_CreateProfile`, `MSUF_SwitchProfile`, `MSUF_ImportFromString`, profile snapshot undo | Complete for create/import/rollback failure paths. |
| Profile create/copy/delete/switch | yes | yes for destructive/copy | yes for destructive/copy | n/a | n/a | yes | `MSUF_CreateProfile`, `MSUF_CopyProfile`, `MSUF_DeleteProfile`, `MSUF_SwitchProfile`, profile snapshot undo | Profile rename is still blocked because no shared UI/helper is exposed. |
| Profile export/Wago link | yes | n/a | n/a | n/a | n/a | yes | `MSUF_ExportSelectionToString`, Assistant copy/link panel, Wago profile link action | Complete when export helper exists. Export kind/string fields are staging UI and remain partial in the strict matrix. |
| Spec profile routing | yes | yes | n/a | n/a | enable/disable auto-switch | yes | Spec auto-switch helpers or DB fallback; `MSUF_SetSpecProfile` or DB fallback | Complete for assignment and clear actions when spec/profile data is available. |
| Factory reset all | yes | yes | yes | n/a | n/a | via status/TODO | `M.StageFactoryReset`, Assistant confirmation queue | Complete for start/confirm/cancel. Reload remains a user/system action after staging. |
| Unit copy-to | yes | yes | yes/implicit | n/a | n/a | via action response | `M.UnitPage.CopyUnitSettings`, Assistant confirmation queue | Single-command source/destination copy is covered, including multi-category scoped phrases. Popup checkbox state remains UI-only. |
| Group frame copy-to | yes | yes | yes/implicit | n/a | n/a | via action response | `M.GroupPage.CopyGroupSettings`, Assistant confirmation queue | Single-command Party/Raid/Mythic Raid copy is covered, including multi-category scoped phrases. Popup checkbox state remains UI-only. |
| Assistant history Undo/Redo | yes | yes | n/a | n/a | yes | via action response | `A.UndoLast`, `A.RedoLast`; parser special-cases `undo`/`redo` | Registered as history actions and mapped to NavRail history buttons. Shift-click reset-all remains a UI-only menu session operation. |
| Gameplay helpers | yes | yes | n/a | n/a | preview toggles where exposed | yes | Gameplay DB helpers, TotemFrame preview/reset, Crosshair spell helper, Edit Mode helper | AdvancedGameplay rows are currently closed. |
| Group frame helpers | yes | yes | n/a | n/a | preview toggles where exposed | yes | Group frame DB helpers, status icon preview/reset, custom anchor clear | Layout/Bars/Indicators are broadly covered; selected-item UI selectors and anchor picker remain partial/UI-only. |
| Global appearance helpers | yes | yes | n/a | n/a | preview/test toggles where exposed | yes | Global Bars/Fonts scoped settings, ONLY override parser, Global Castbars helpers, castbar preview helper, highlight/dispel test helpers, color reset helpers | Global Fonts, Global Bars, and Global Castbars rows are closed. |
| Guided setup | yes | n/a | yes | finish | n/a | yes | Assistant guided setup context (`A.guidedSetup`) | Start/next/back/skip/show/finish/cancel are covered. Deeper branch-specific diagnostics remain TODO. |
| Dashboard panels | yes | n/a | yes | n/a | toggle | yes | `M.PersistMenuStateValue`, `M.Open` / `M.SelectPage`, `A.Workflow.SetDashboardPanel` | Recovery, Scaling, and Changelog disclosure headers are counted in the matrix and controllable through the Assistant. |
| Dashboard navigation pages | yes | n/a | n/a | back via normal UI | n/a | yes | `M.SearchBridge.OpenSearchTarget`, `M.Open`, `M.SelectPage` | Page-open/search-target coverage is broad, including visible page-label shortcuts such as Pet and Target of Target. Conversational browser-style back stack is TODO if Menu2 exposes a shared history helper. |
| Menu2 window shell | yes | n/a | n/a | close | minimize/maximize/restore | via action response | `M.HideSlashMenuAndMinibar`, `M.MinimizeSlashMenuWindow`, `M.MaximizeSlashMenuWindow`, `M.RestoreSlashMenuWindow`, `M.RestoreMinimizedSlashMenu` | Complete for the visible window and minimized-bar shell buttons. |
| Diagnostics | yes | n/a | n/a | n/a | n/a | yes | Assistant diagnostic actions and shared status helpers | Unitframe, group-frame, castbar, status, scoped help, and Edit Mode status are covered. Deeper page-specific troubleshooters remain TODO. |

Coverage counters from the offline harness after this pass:

- Settings: 2544
- Actions: 96
- UI matrix rows: 704 (`579` registered, `10` partial, `70` documented TODO, `45` unmapped by strict static UI-to-registry mapping).
- Non-aura unmapped rows: 0
- Lifecycle-covered workflows: Edit Mode, profile import/export/profile ops, spec profile routing, factory reset, unit copy-to, group frame copy-to, Assistant history, gameplay helpers, group frame helpers, global appearance helpers, guided setup, Dashboard panels/navigation, Menu2 window shell controls, and diagnostics.
- Focused parser smoke: `lua tools\assistant_parser_smoke.lua` covers Pet/Target of Target page navigation, page-label shortcuts, Dashboard panel open/close/toggle actions, Menu2 shell close/minimize/maximize/restore actions, general/scoped help aliases, short profile-copy aliases, unit and group copy category scopes, global UI scale presets, guided setup start/step/cancel, support links, Wago backup confirmation, Edit Mode lifecycle/status, diagnostics, factory reset staging, natural reset phrases, Bars/Fonts ONLY scoped override routing, scoped bar border color/texture aliases, relative numeric registry changes, unit detail pixel moves, unit opacity shortcuts, root castbar toggle, unit castbar spell-name/text/icon/time/interrupt/channel-tick/glow/spark/latency/unified-direction toggles, castbar text color, and Pet frame movement.

Current largest workflow gaps:

- Auras and Group Auras need the next explicit mapping pass.
- Profile rename needs a shared helper before it can be safely controlled.
- Dashboard back/history-stack navigation needs shared Menu2 state helpers before conversational control should mutate it. Window shell close/minimize/maximize/restore and Assistant Undo/Redo are already registered.
- UI staging selectors should remain partial unless the Assistant needs to mirror UI state rather than directly execute the selected operation.
