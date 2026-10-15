# Profile defaults schema

`schema.lua` is the canonical typed factory/repair catalog on Mainline, Forever, Vanilla, TBC and Mists. Its 7,293 baseline paths record native path, owning root, type and presence. It also owns 54 literal seed stages (287 scalar fills) and observed lazy factory/runtime contexts. Unknown and dynamic dictionary keys have no invented default and retain their representation.

The baseline and lazy snapshots are source-built factory profiles from `34a8673c79dd0c56c1d403da0122252282021f15`, not account data. On current main `096d5e0e0ffc2c386189932cecb946435db09bc3`, the real runtime Reset also materialises `_msufFactoryPlayerDefensivesEnabled_v1=true` on Vanilla, TBC and Mists. Those three reset-context values are pinned explicitly; all other catalog values remain unchanged. A before/candidate comparison proves reset parity on every client. Client rows override the Mainline context only where values or presence differ. Empty tables, false, zero and absence are distinct. The parity smoke checks every declared field, rejects undeclared provider defaults, verifies generated stages and checks the real factory runtime reset. Do not regenerate the catalog to hide a regression.

Only true `general.showGameMenuButton` and `general.previewDragHintAnimationEnabled` have portable persistence certificates. Both current and 6.50 refill them for every stored profile despite revision shortcuts. All explicit non-default values remain stored. Every other field, empty owner, array, migration stamp and sentinel retains its representation.

The rejected factory-pruning design forced destination default repair and changed source-client opacity/stamp absence when profiles moved between clients. Same-client factory equality does not establish portability. No runtime repair trigger or source-client omission certificate remains. Cross-client declared-SavedVariables regressions cover every supported current destination; isolated evidence also runs frozen 6.50 and current return.

Generate and verify the runtime literal-data fragment with Lua 5.1:

```
lua tools/defaults_schema_generate.lua . .checks/defaults-runtime-data.lua
```

Adding an omission requires proof across every supported destination client and 6.50 path, including nils, legacy overrides, declared-variable serialization, source pins and unchanged budgets.
