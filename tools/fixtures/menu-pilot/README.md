These are immutable built-control receipts from base
`9c29a35a48d661912c64535bb221eec39da0d522`, captured before the five pilot
pages were rewritten. No declarations stand in for a runtime control.

Each tab-separated row records state, control ID, kind, label, setting key,
control path, setting aliases/patterns, action key, classification, minimum,
maximum, step, dropdown values, getter value and exact-search preparation.
The real client/core/Options graph builds and expands the lazy sections.
Cases include cold/warm pages, narrow/enabled Gameplay, empty/percent/absolute
resource marks, every supported unit scope, alpha/range gates and Swing hands.

Counts: Mainline 717, Forever 1134, Vanilla 452, TBC 620, Mists 680.
`menu_pilot_inventory_smoke.lua` compares current builds without writing fixtures.
`.checks/before-receipt.json` pins their SHA256 values and the original page
sources; individual `.checks/rewrite-before-*.json` receipts precede each rewrite.
The original generator stdout catalogs and the final zero-row-change comparison
are under `.checks`. Original fixture hashes remain unchanged after mutations.

The inventory pins all controls built by both alpha tabs. A separate behavior
smoke drives exact cold/warm navigation and checks visibility; an inventory alone
does not prove which tab the player sees or establish live layout/taint safety.
