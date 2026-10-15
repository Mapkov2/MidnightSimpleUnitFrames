# Profile defaults and persistence

Runtime profiles remain ordinary materialised tables. `MSUF_DB` is the active `MSUF_GlobalDB.profiles` entry. Existing readers, history, variants, sync, copy/reset and exports retain full runtime values and identities.

`tools/fixtures/defaults/schema.lua` owns type/scope/presence for factory, repair, literal-seed and lazy factory contexts. Existing providers are verified against it. Independent scalar nil-fill blocks are generated as schema stages; the same canonical source owns the portable persistence entries. The catalog never eagerly fills optional fields merely because it declares a default.

Terminal logout first restores/cancels variants and flushes sync. Its final native handler validates all profile/general owners, removes certified defaults in place, then clears the existing standalone alias. The terminal passes allocate no tables or yield. Invalid owners or secret menu values retain the full pool. WoW does not guarantee a globally last handler; the existing alias timing boundary remains unchanged.

Only true menu defaults `general.showGameMenuButton` and `general.previewDragHintAnimationEnabled` are omitted. Both current and 6.50 restore them for every stored profile on every client. Explicit false/zero/empty values remain stored. All other fields, arrays, empty tables, nil-sensitive values, stamps and shortcut sentinels retain their native representation. The State700 step supplies the same menu fills after factory seeding; wire schema600 stays unchanged.

Forcing heavy repair in another client can overwrite existing opacity values and introduce a migration stamp. Consequently no factory-wide pruning or private factory cache is used. A future certificate must prove both loaders across all supported destination clients, beyond matching fresh factory values or same-client exports.

The measured saving is conservative; the large storage target and native WoW/live downgrade checks remain open. Hot readers are unchanged. There is no claimed login RAM saving or architecture impossibility.
