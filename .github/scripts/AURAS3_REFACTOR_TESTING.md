# Auras3 refactor checks

Run from the repository root with Lua 5.1 available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/run_auras3_refactor_tests.ps1
```

This runner needs only versioned files. It checks the authoritative XML module
groups, compiles every factory and entry, verifies that registering factories
performs no runtime work, and exercises the actual native backend with a bounded
frame mock. The retained scenarios cover square/rounded Dispel and Purge border
thickness, per-visual Friendly/Enemy/Both gates, owner retirement/reuse, intrinsic
Blizzard event ownership, and Menu apply ordering/coalescing. It also runs the
filter ownership, scoped-cache and preview read-context regression tests.
Group indicator tests also check list identity/order and skipped empty-owner work.

For a frozen Auras3 source snapshot with the original relative paths:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/run_auras3_refactor_tests.ps1 -BaselineSourceRoot _local_workflows/auras3-cpu-20260906/baseline
```

The same fixture executes against both sources. The runner compares actual
per-visual selection, alpha, layer, shape, geometry and native input contracts;
96 mixed Dispel configurations plus eight Unit lane cases produce 872 observations.
Owner and selection-slot counts must not increase, and feature counts must remain
equal. Ordered native calls are retained for diagnosis, but are deliberately not
required to match: sharing removes owners and changes cold recreation work.
Candidate-only checks additionally exercise Edit Mode forwarding/restore through
the current public native group enumeration API. Traces live under the ignored
`_local_workflows/auras3-refactor` directory. These are deterministic mock calls,
not WoW CPU measurements or Perfy captures.

For a frozen post-split source tree, `-BaselineSourceRoot` also compares complete
schema values and shared-reference topology. Earlier filter, scope-cache and
indicator optimizations have a separate denominator: pass
`-OptimizationBaselineSourceRoot _local_workflows/auras3-optimization/baseline`
only when comparing those earlier changes. Do not attribute their savings to a
later owner-sharing change. Baseline-free runs retain fixed semantic/ownership
assertions and the preview comparison through public getters.

`auras3_alias_catalog_smoke.lua` checks real localized and hotfixed spell groups,
large groups, static aliases and exact-ID behavior for uncatalogued spells. Aura
reads, event creation and protected calls fail the fixture. Cached hits and misses
must not repeat catalog searches. `auras3_alias_native_smoke.lua` exercises the
actual compiler, native priority groups, reminder slots and click bindings, DoT
eligibility, defensive overrides and disabled lanes. The runner executes both.
The removed resolver's query/VM fixture is not a denominator for this different
architecture. See `../AURAS3_ALIAS_CATALOG.md` for full CSV-oracle validation and
the distinction between cold desktop measurements and live combat performance.

The cache test covers in-place edits, party/raid/mythic aliases, unknown group
kinds, equal-generation pooled frame reuse, shared previews, interleaved global
changes and visual invalidation. Preview cases include legacy/revision-1/revision-2
profiles, missing/partial/full runtime metrics, unavailable storage and profile
replacement during compilation. Filter tests preserve mutable per-lane ownership,
compiled aliases, legacy ID forms and explicitly versioned static catalog sharing.

Operation counts and garbage-stopped stock-Lua allocation samples describe only
the bounded fixture. They are not addon-wide CPU, memory, FPS or Perfy measurements.

The broader existing local Core suite can use the same compatibility driver:

```powershell
lua .github/scripts/auras3_test_driver.lua .github/scripts/tests/aura_growth_anchor_smoke.lua .
```

That broader fixture and its Core runner are currently ignored local tools; they
are additional coverage and are not prerequisites for the versioned runner.
`auras3_test_loader.lua` reads each contiguous factory group from the production
XML before loading its legacy entry point. Its source reader includes all files
in that group for legacy static contracts. Private Edit Mode helper probes are
injected only into test-created source strings, inside their owning factories.
No loader, instrumentation, or testing exports are added to the addon runtime.

Stock Lua cannot reproduce engine-level secret values, taint, combat protection,
or the game's rendered output. Live WoW acceptance remains a separate check.
