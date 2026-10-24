# Compact release check

Run from any working directory:

    powershell -NoProfile -File <checkout>/tools/release-check.ps1

PowerShell 7 uses `pwsh` instead of `powershell`. Lua 5.1, luac 5.1 and
Python 3.12+ resolve from explicit `-Lua`/`-Luac`/`-Python` arguments, the
`MSUF_LUA`/`MSUF_LUAC`/`MSUF_PYTHON` environment variables, tools/lua51, or PATH.
A missing or wrong tool fails clearly. Helpers resolve from the runner's own
checkout. Every log identifies HEAD and whether tracked working-tree edits exist.
No git writes, installation or publication are performed.

The default named mutex serializes compact checks. For an existing external
scheduler, pass `-Slot <scheduler.ps1>` or set `MSUF_LUA_SLOT`; child fast-check
uses the same scheduler. Logs default to ignored dist/checks (`-LogDirectory`
overrides this). The fast runner remains usable by parallel development lanes.

One inventory runs locally and in push/nightly/release CI:

| Contract | Coverage |
| --- | --- |
| Generated lists | Module manifest exact outputs, without modifying them. |
| Freshness | Verify or regenerate ignored tools/menu_schema_coverage.json after verifying both current search indexes; never rewrite shipped indexes. Run the complete scorecard. |
| Fast check | Compile every shipped client graph; real core/Options boot and sparse persistence/transfer on Mainline, Vanilla, TBC, Mists, Forever; backward migration and ratchet. |
| Profiles and storage formats | Frozen V2 and V3 generator --check; exact sparse size, malformed inputs, rollback, inherited defaults and explicit overrides. Newer-revision backup, quarantine, immutable recovery history and corpus contracts on all five clients. |
| Apply/Edit Mode | All five clients, including CRUD, capability differences, dispatcher and painted state, move/nudge/undo/lock and late Options history. |
| Menu | All five clients, every registered page/lazy section, exact schema-projected initial declaration count, query and visible exact-target navigation. Reopen, scanner, crosshair and search-entrypoint regressions. Both search index families run decoder heap checks in all twelve locales. |
| Runtime robustness | Subscriber mutation, player-health maximum caching, class-resource builders, empower object reuse, module enablement boundaries, prediction/late-anchor/text writer recovery. Root-only harnesses run once; the builder harness covers all five clients internally. |
| Namespace | Actual exports per client at core/login and Options boundaries; source-backed delayed exports. Negative probes remove a provider, keep only policy, use inactive clients/nil exports, cross phases, comment out a delayed publisher and exceed bounded legacy allowances. |
| Group preview | Mainline/Vanilla/Forever lifecycle, engine ownership, supported scenes, combat suspend/restore and independent owners. |

A missing/stale coverage projection needs a complete workspace build. This
preparation has its own Lua slot and is timed explicitly. Capture writes changed
serializable records after each page, retains only the bounded declaration union,
and drops widget callbacks. Clients run in isolated children, flush/release their
capture state and collect before the parent advances to the next client. Python
folds the disk records with the same first-public/last-schema/set-union rules. The existing 300-second
budget applies to fast-check plus behaviour contracts, excluding queue wait and
projection preparation. All child output is retained; any failed contract fails
the runner. Freshness failures remain failures while independent contracts continue.
Profiles run in a separate serial worker alongside the other contracts; both
workers acquire their own external scheduler slot. Without an external scheduler,
the parent mutex excludes other compact runs and the profile worker uses a second
named mutex. At most two Lua processes belong to this release run. Capacity-one
schedulers run the worker after the parent releases its slot; they cannot deadlock.
Use `-ParallelContracts:$false` to force the fully serial mode. The 300-second
budget measures fast-check plus elapsed contract-suite work, including the join;
no test or time is omitted from the receipt.

`-Reproducible` additionally requires exact versions and immutable Blizzard refs
from tools/check-pins.json, then runs the source audit against those commits.
The reusable release-check workflow prepares them. The independent source-audit
job still follows upstream branch tips and reports drift separately. The frozen
Classic full gate is retired from CI.

Frozen suite cleanup uses `python tools/prune_frozen_tests.py --report <report.json>`.
Deletion additionally needs `--delete --release-log <successful-current-release.log>`
and `--start-snapshot <initial-file-hashes.json>`. New or changed files after that
snapshot are protected roots, as are all untracked tests. Every candidate is
hashed again before unlinking. When the owner explicitly requests the frozen
prune despite concurrent product failures, `--owner-approved` permits a completed
failing receipt for the same HEAD. It requires every contract summary and records
the receipt hash and override in the closure report; it never turns failures into
passes. The ordinary path still requires a current successful source projection.
An owner-designated list of abandoned dirty tests can be passed with
`--frozen-dirty <list.txt>`; retained dependencies and every budget smoke stay
protected even if listed. The closure validates every deletion path inside the
selected root and does not write git metadata.

The module manifest's optional `locale_work_sources` adds literal translation
calls and command help from named runtime sources to the missing-key report.
These generated English stubs are translation work, never loaded as translations.

Offline results establish these modelled contracts. Live WoW visuals, combat
taint, controller behaviour and measured CPU performance require their own proof.
