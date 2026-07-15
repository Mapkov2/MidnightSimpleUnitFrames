# MSUF Full Feature Code Audit

Date: 2026-07-15
Repository: `C:\MSUF Beta Branch\MidnightSimpleUnitFrames`
Branch: `6.0-beta-branch`
Audited commit: `f8f6258b782944bccf53771c8621c50386bc6d5d` (`v6.0-beta17`)

## Remediation recheck

Rechecked and remediated on 2026-07-15 in the working tree based on the audited commit. All ten confirmed findings and the release-assurance finding now have code fixes plus focused regression coverage.

| Finding | Resolution |
|---|---|
| F-01 | Replaced `loadstring` import execution with a bounded, non-executing table-literal parser; validation and staging complete before live profile mutation. |
| F-02 | Factory name migrations now preserve divergent SavedVariables and persist only completion markers unless the complete old non-modern signature matches. |
| F-03 | Spell-indicator native filters now use an exact token allowlist, alias normalization, and safe negation rules. |
| F-04 | Added encoded, decoded, string, depth, node, finite-number, cycle, and shared-table limits to all import paths. |
| F-05 | Profile deletion now removes deleted names from every character specialization map. |
| F-06 | Profile lifecycle APIs return explicit success/failure; Menu2 switches only after `success == true`. |
| F-07 | Version comparison now orders `alpha < beta < rc < stable` and compares bounded numeric prerelease revisions. |
| F-08 | Crosshair camera anchoring now reacts to secure zoom hooks and the camera-distance CVar without adding an `OnUpdate`. |
| F-09 | Forced spell-indicator repair now retains pending state and recreates the native container at a safe lifecycle boundary. |
| F-10 | Peer messages are channel-restricted, length-limited, fully parsed, and rendered from a normalized version rather than raw input. |
| QA-01 | Repaired the stale core smokes, added focused regressions, created an explicit 76-test manifest, and made it mandatory on push, pull request, and before publishing. |

Remediation verification:

- Core Lua 5.1 smoke manifest: **76 passed, 0 failed**.
- Repository static checks: **568 Lua files passed**.
- Repository Lua 5.1 loadability: **573 files passed**, 0 BOMs stripped.
- Focused Assistant parser and Unit/Group/Aura catalog audits: **passed**.
- `git diff --check`: **passed**.

The full Assistant schema/menu-guide gates remain outside this core audit boundary and currently stop on pre-existing companion-contract drift: five Advanced Colors navigation buttons lack command metadata, and the native guided-tour stage audit expects 25 stages while current collection reports 40. Those failures were isolated during remediation recheck; they are not caused by F-01 through F-10 and are not treated as green here.

## 5.5 profile migration follow-up

Rechecked on 2026-07-15 against `C:\MSUF Beta Branch\MSUF-5.5-main` and the supplied 5.5 profiles. Eight additional conversion/runtime defects were reproduced and fixed:

| Migration defect | Resolution |
|---|---|
| Aura lane position | Aura2 positioned the first icon from a small origin frame, while Aura3 positioned a full-capacity host. Geometry v3 now translates the first icon rectangle for every RIGHT/LEFT/UP/DOWN and UP/DOWN-wrap combination. |
| Shared Aura geometry | Aura2 scopes without an existing `perUnit` table inherited shared geometry, but one converted Y value cannot fit frames with different heights. Migration now materializes player, target, focus, and boss1-5 layouts before translating them. |
| Aura versus text z-order | Aura2 used `MEDIUM` strata and frame level 50. Legacy lanes now retain `MEDIUM` strata and a level-30 lane offset; Aura3 unit lanes now compile per-lane strata instead of silently ignoring it. The original name/health/power text layer values remain unchanged. |
| Detached power position | 5.5 interpreted detached X/Y from `TOPLEFT/BOTTOMLEFT`; 6.0 interpreted them from centered `TOP/BOTTOM`. Legacy profiles now persist `LEGACY_TOPLEFT`, consumed consistently by runtime and both previews. Native 6.0 profiles remain centered. |
| Frame outline strata | Native 5.5 migrations now force `barOutlineStrata = "BACKGROUND"` globally and for every existing unit/group scope override. `AUTO` is deliberately not preserved, while native 6.0 profiles remain untouched. |
| Legacy status symbols | The supplied profile stores the combat indicator as `DEFAULT` at size 30 and X=104, matching the white square in the screenshot. 6.0 attempted to assign the combat atlas whenever `SetAtlas` existed, even when that atlas was unavailable; the pre-seeded white texture then remained visible. Runtime and preview now verify atlas availability and otherwise restore the 5.5 `UI-StateIcon` texture/coordinates. All 25 native 5.5 combat/resting/resurrection symbol IDs are explicitly accepted; unknown IDs safely fall back instead of synthesizing a missing texture path. |
| Castbar position | The second supplied profile stores player `0/-38`, target `0/-58`, focus `1/-58`, and boss `1/-49`. Profile translation retained these numbers, but the 6.0 player/target/focus live anchor path added `0.5` before calling a helper that already rounds, turning X=0 into 1 and focus X=1 into 2. The extra adjustment is removed; attached and detached runtime anchors now consume the exact migrated values and match their previews. Boss already used the single-rounding 5.5 contract. |
| Power Text visibility | 5.56 stored the Power Text toggle as `showPower`; 6.0 split it into `showPowerText` and filled missing values from new per-unit defaults before runtime compilation. In the supplied profile this changed Player and Target from OFF to ON, while other units only appeared correct when their new default happened to match. Native 5.5 imports now copy the old state for player, target, focus, target-of-target, focus-target, pet, and boss. Already-migrated SavedVariables are repaired once when the stored value still matches the incorrectly seeded 6.0 default; a value that already differs from that auto-seeded default is preserved as a later 6.0 choice. Native 6.0 profiles remain untouched. |

The profile normalization revision is now 4. Profiles already stored with the earlier Aura geometry-v2 marker are deliberately re-entered and upgraded to v3. Geometry-v3 profiles created before the fixed-outline rule also re-enter once and receive `barOutlineStrata = "BACKGROUND"` globally and on existing scope overrides; `AUTO` is never retained for native 5.5 migrations. Legacy profiles normalized before the Power Text fix also re-enter once and receive the old `showPower` visibility wherever 6.0 had merely inserted its opposite per-unit default. The focused profile regression uses the supplied profile's target `242/80/116/2` detached-power geometry and its player/target/boss Aura layouts, checks all eight growth/wrap branches, checks Power Text visibility in both directions for all seven unit scopes, verifies idempotence, and confirms that native 6.0 profiles are not changed. A separate status-symbol regression renders every native 5.5 symbol identifier and checks the unavailable-atlas plus invalid-symbol fallbacks.

## Original executive verdict for the audited commit

The shipped core addon contains **10 confirmed defects or concrete edge-case failures** in **7 feature families**:

- **2 high severity**: legacy profile import can execute unbounded Lua computation, and factory-profile migrations can overwrite user-customized name settings.
- **7 medium severity**: invalid spell-indicator filters can reach a Blizzard assertion, compact imports have no size bounds, two profile lifecycle paths are inconsistent, beta versions compare as identical, camera-follow crosshair placement becomes stale after zoom, and spell-indicator geometry repair does not repair initialized buttons.
- **1 low severity**: version-check messages echo an untrusted peer-supplied suffix into chat.
- **1 separate release-assurance gap**: the broad core smoke set is not CI/release-gated and currently has 6 failures out of 70.

No critical defect was found. No runtime source was changed during this audit.

## Scope and line coverage

The audit target was the shipped `MidnightSimpleUnitFrames/` core addon, matching the requested roughly 200k-line scope.

| Tracked code/load artifact | Count | Coverage |
|---|---:|---|
| Lua files | 240 | 197,423 physical lines |
| XML load manifests | 17 | All include/load edges checked |
| TOC | 1 | Full load order and metadata checked |
| Total | 258 | Every tracked Lua/XML/TOC line included |

First-party Lua was reviewed semantically by feature, caller, state transition, and disabled lifecycle. Vendored libraries and locale tables were included through syntax/loadability, API-boundary, duplicate/load-order, and fallback checks; their addon-facing glue was reviewed semantically. XML and the TOC were checked for complete and correctly ordered loading.

The separate `MidnightSimpleUnitFrames_Assistant/` companion, sibling addons, generated release packages, binary media, ignored local helpers, and historical tool sandboxes are outside the 197,423-line shipped-core count. Core-to-Assistant metadata and bridge code inside `MidnightSimpleUnitFrames/` was included. Repository tests and release gates were reviewed as assurance evidence even though they are not shipped runtime code.

## Method and recheck standard

The review combined:

1. Complete tracked-file and line inventory.
2. TOC/XML load-order reconstruction and dependency mapping.
3. Feature-by-feature semantic review of initialization, event ownership, timers, secure/combat deferral, configuration writes, profile transitions, rendering, teardown, and failure paths.
4. Mechanical Lua 5.1 loadability and repository static checks.
5. A 70-test core smoke sweep, followed by source-level classification of every failure.
6. Reproduction of deterministic parser/version defects with Lua 5.1.
7. Recheck of source-sensitive Aura behavior against the refreshed local Blizzard PTR source at `upstream/ptr`, commit `3ea5134b14c626b09de1dcb1b0acf8f665460a53` (`12.1.0 (68675)`).

This was a static and mocked-runtime audit. It did not launch the WoW client, so secure-frame and secret-value findings are described as code-proven edge paths rather than claimed in-client crash captures.

## Confirmed findings

### F-01 — High — Legacy profile import accepts executable Lua inside a “table literal”

**Feature:** Profiles / import / external profile API

**Evidence:**

- `State/MSUF_Profiles.lua:26-65` accepts any trimmed string whose payload starts with `{` and ends with `}`, compiles it with `loadstring`, and executes it with an empty environment.
- The table-expression grammar still permits immediately invoked functions, loops, recursion, and large allocations. An empty environment prevents access to addon globals, but it does not limit CPU time or memory.
- Execution occurs under `pcall` at `State/MSUF_Profiles.lua:5378-5387`, `5463-5473`, and `5747-5752`; `pcall` catches errors but cannot interrupt an infinite loop.
- Reproduction under the repository's Lua 5.1 runtime: `return {value=(function() local x=40; return x+2 end)()}` executes successfully and produces `value=42`, proving the gate is not a literal-only parser.
- A cyclic table can also be constructed without globals. Later copying is recursive (`State/MSUF_Profiles.lua:1146-1159`) and the active-profile apply wipes the live profile before copying (`5264-5288`).

**Impact:** A pasted legacy profile can freeze the client, exhaust memory, or fail during recursive copy. The path is especially risky because profile strings are commonly shared between users.

**Required correction:** Remove executable decoding from user input. Use a non-executing legacy table parser with depth/node/byte limits, validate the complete decoded schema before touching `MSUF_DB`, and build a validated replacement copy before the active profile is wiped.

### F-02 — High — Factory-profile migrations overwrite customized name presentation

**Feature:** Defaults / upgrades / factory profile

**Evidence:**

- `State/MSUF_Defaults.lua:989-1040` identifies a profile only by factory markers and then unconditionally writes shared and per-scope name-shortening settings.
- `State/MSUF_Defaults.lua:1101-1143` similarly overwrites shortening, maximum characters, clip side, ellipsis behavior, and front-mask values across player, target, target-of-target, focus, pet, boss, party, raid, and mythic-raid scopes.
- Both repairs run in the heavy defaults pass at `State/MSUF_Defaults.lua:1440-1442`.
- The safer migration beside them, `MSUF_Defaults_RepairModernFactoryPlayerStack` at `1075-1098`, changes geometry only when the complete old factory signature still matches. The name migrations have no equivalent old-value guard.
- The older non-modern branch at `1042-1072` can also disable scoped shortening based on broad “looks like factory” detection rather than proving the setting is untouched.

**Impact:** A user who started from a factory profile and customized name display before the relevant one-shot marker was introduced can lose those choices during upgrade. This is persistent SavedVariables mutation, not merely a visual refresh issue.

**Required correction:** Migrate only values that still equal the exact previous factory defaults, or store provenance per setting. Preserve any divergent user value and set the migration marker after the guarded pass.

### F-03 — Medium — Spell indicators preserve unknown native Aura filter tokens

**Feature:** Auras / spell indicators / imported profiles

**Evidence:**

- `Auras3/MSUF_Auras3_SpellIndicators.lua:101-131` normalizes aliases but does not validate tokens against Blizzard's allowed filter set.
- `CompileSlot` reads `nativeFilter` or `customFilter` and passes the unvalidated result into the native slot at `Auras3/MSUF_Auras3_SpellIndicators.lua:244-284`.
- The same addon already has the correct pattern for regular unit-frame Auras: `Auras3/MSUF_Auras3_UnitFrames.lua:821-847` rejects tokens not present in `VALID_NATIVE_FILTER_TOKENS`.
- Deterministic recheck produced `HELPFUL|BOGUS|!PLAYER` from a malformed imported filter.
- Refreshed PTR source `Blizzard_FrameXMLUtil/AuraUtil.lua:294+` rejects unknown components in `AuraUtil.IsValidFilterString`; `Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua:310` asserts that the filter is valid.

**Impact:** A malformed, legacy, or externally imported spell-indicator filter can produce a Lua assertion while the native Aura container is built.

**Required correction:** Share the validated token normalizer used by regular Auras, including valid negation rules, and fall back to a known-safe filter if all requested tokens are discarded.

### F-04 — Medium — Compact MSUF2/MSUF3/MSUF4 imports have no byte or inflation limits

**Feature:** Profiles / compact import

**Evidence:**

- `State/MSUF_Profiles.lua:627-685` trims and decodes arbitrary-length compact strings, then tries Blizzard and LibDeflate decompression and deserialization without an encoded-size or decompressed-size ceiling.
- `TryBlizzardDecompress` and `TryDeserializeMaybeCompressed` at `State/MSUF_Profiles.lua:469-515` can allocate the complete inflated payload before any schema validation.
- The UUF importer demonstrates the intended defensive boundary at `State/MSUF_Profiles.lua:3509-3523`: 8 MiB encoded and 32 MiB decompressed limits.

**Impact:** A very large or compression-bomb-style profile string can cause a long UI stall or excessive memory consumption before the import can fail.

**Required correction:** Enforce a small encoded-input limit before normalization/decoding, a decompressed output limit during or immediately after inflate, and table depth/node/string budgets before profile translation.

### F-05 — Medium — Deleting a profile leaves specialization mappings pointing to it

**Feature:** Profiles / automatic spec switching

**Evidence:**

- `MSUF_DeleteProfile` updates each character's `activeProfile` at `State/MSUF_Profiles.lua:846-875`, but never removes matching entries from `char.specProfileMap`.
- `MSUF_RenameProfile` correctly updates both active-profile and spec-profile references at `State/MSUF_Profiles.lua:938-950`, confirming that mappings are expected to follow lifecycle changes.
- On a later spec change, `MSUF_ApplySpecProfileIfEnabled` reads the stale name and silently returns when the profile is absent at `State/MSUF_Profiles.lua:1074-1084`.

**Impact:** Auto-switch silently stops working for the affected specialization, while the stored/UI mapping can continue to name a profile that no longer exists.

**Required correction:** During deletion, remove every `specProfileMap[specID]` whose value equals the deleted profile, for every character record. Refresh the profiles page after cleanup.

### F-06 — Medium — “Create profile” switches to an already-existing profile after creation fails

**Feature:** Profiles / Menu2 lifecycle actions

**Evidence:**

- `MSUF_CreateProfile` prints “already exists” and returns no explicit failure value at `State/MSUF_Profiles.lua:774-790`.
- Menu2's `CallMSUF` wrapper returns `pcall`'s first result first (`Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua:96-99`). A function that ran successfully but declined the operation therefore appears truthy.
- The Create button uses `if CallMSUF("MSUF_CreateProfile", name) then` and immediately switches to that name at `Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua:324-333`.

**Impact:** Entering an existing profile name and pressing Create emits an error but still changes the active profile to the existing one and clears menu history. The visible result contradicts the failed operation.

**Required correction:** Give all profile lifecycle APIs a consistent `(success, reason)` contract. Only switch after `success == true`; also precheck `ProfileExists(name)` in the direct click path.

### F-07 — Medium — Peer version checking cannot distinguish beta releases

**Feature:** Version check / update notification

**Evidence:**

- `Features/Versioning/MSUF_VersionCheck.lua:37-44` parses only `major.minor.patch` and ignores suffixes.
- The shipped TOC version is `6.0-beta17`.
- Lua 5.1 recheck: `6.0-beta16`, `6.0-beta17`, and stable `6.0` all convert to `60000`; only `6.0.1` differs.

**Impact:** The current beta channel cannot notify beta16 users about beta17, cannot distinguish a later beta, and considers the eventual stable `6.0` equal to every `6.0-betaN` build.

**Required correction:** Parse and compare a structured version tuple containing prerelease channel and numeric prerelease revision. Define ordering explicitly, for example `alpha < beta < rc < stable`.

### F-08 — Medium — Camera-follow combat crosshair uses a stale zoom-derived offset

**Feature:** Gameplay / combat crosshair

**Evidence:**

- `Features/Gameplay/MSUF_Feature_GameplayRuntime.lua:620-656` derives the personal-nameplate offset from `GetCameraZoom()` and caches the resulting anchor.
- The event handler refreshes anchoring on login/world entry, display size, player-nameplate removal, and `nameplateShowSelf` CVar changes at `696-717`.
- Registered events at `1050-1061` include no camera-zoom update, and the generic `CVAR_UPDATE` branch ignores camera-distance variables.

**Impact:** If the user zooms the camera after the crosshair is anchored, the calculated compensation stays at the old zoom until an unrelated re-anchor event occurs. The “follow camera” position can visibly drift during normal play.

**Required correction:** Re-anchor on the smallest reliable zoom-change signal available on the target client, with change detection and throttling. Do not add an unconditional high-frequency `OnUpdate`.

### F-09 — Medium — Spell-indicator “forced geometry repair” clears its flag without repairing live buttons

**Feature:** Auras / spell indicators / world-transition recovery

**Evidence:**

- `Auras3/MSUF_Auras3_SpellIndicators.lua:372-389` advertises and sets a flag that should bypass per-button anchor caches.
- World-transition routing deliberately requests that repair in `Auras3/MSUF_Auras3_UnitFrames.lua:3008-3045` and `3108-3134`.
- `Runtime.SyncGeometry` at `Auras3/MSUF_Auras3_SpellIndicators.lua:989-1022` reads the force flag, updates only the container and addon-owned missing/effect frames, performs no operation on initialized native buttons, and then clears the flag.
- The regression smoke `spell_indicator_position_lifecycle_smoke.lua` fails with `initial live geometry has no anchor`.
- The PTR restriction noted in source is real: touching restricted AuraButtons is unsafe while Aura data is secret. The defect is the unsupported recovery contract, not a recommendation to restore forbidden mutations.

**Impact:** If an initialized native spell-indicator button loses or retains stale geometry across a world transition, the requested repair reports success but cannot recover it. It remains stale until a safe structural recreation happens.

**Required correction:** Replace the false repair contract with a safe container-recreation strategy at an allowed lifecycle boundary, or retain the pending repair until recreation is possible. Align comments, return values, and the regression test with the actual secure-frame ownership model.

### F-10 — Low — Version messages echo an untrusted peer-supplied suffix into chat

**Feature:** Version check / addon messaging

**Evidence:**

- `Features/Versioning/MSUF_VersionCheck.lua:116-130` accepts `V:(.+)`, parses only the numeric prefix, ignores channel and sender, and stores the entire original string as `highestSeenStr`.
- `PrintUpdateMessage` inserts that raw string into a formatted chat message at `77-82`.
- The numeric parser is not end-anchored, so a message such as `V:999.0<arbitrary suffix>` passes comparison and the suffix is retained for display.

**Impact:** Another addon using the same prefix, or a group/guild peer sending a crafted payload, can force the one-shot update notice and inject misleading formatting/control text into the displayed version field.

**Required correction:** Accept only a fully anchored, length-limited version grammar; render a reconstructed normalized version rather than the raw payload; optionally restrict valid channels and rate-limit malformed messages.

## Release-assurance finding

### QA-01 — Medium — Core smoke coverage is not enforced and is currently red

The audited checkout produced:

- `tools/test-wow-lua51-loadability.ps1`: **pass**, 245 physical Lua files, 0 BOMs. This includes five ignored local helper files in addition to the 240 tracked shipped Lua files.
- `.github/scripts/msuf_static_checks.py`: **pass**, 568 repository Lua files across core and companion areas.
- Core smoke sweep: **64 passed, 6 failed, 70 total**.

The six failures were rechecked individually:

| Test | Classification after source recheck |
|---|---|
| `.github/scripts/tests/spell_indicator_position_lifecycle_smoke.lua` | Product/recovery defect; corresponds to F-09 |
| `tools/advanced_colors_page_contract_smoke.lua` | Stale assertion: expects page version 6 while the page is version 11 |
| `tools/global_bars_page_smoke.lua` | Stale mock/registration-count contract after shared control-registration refactor |
| `tools/profile_apply_smoke.lua` | Stale mock: returns `nil` from notify while current production contract treats only explicit `true` as handled |
| `tools/value_source_hotpath_smoke.lua` | Stale setting names after the split to `healthShortNumbers` and current health-source configuration |
| `tools/window_build_contract_smoke.lua` | Test file itself does not parse in Lua 5.1 because a newline creates ambiguous call syntax |

`.github/workflows/msuf-static-checks.yml` is manual-only (`workflow_dispatch`) and runs only the Python static checker. The release workflow does not run this 70-test core set. The Assistant release gate names many Assistant tests and Lua loadability explicitly, but it also omits these core runtime smokes.

**Impact:** A release can be published while the core regression suite is red. Stale failures also train developers to ignore signal, which can hide the one failure that currently corresponds to real product behavior.

**Required correction:** Repair or replace the five stale/broken tests, keep F-09 red until the behavior is resolved, create an explicit core-smoke manifest, and run it on pull requests plus before release publishing.

## Feature-by-feature coverage matrix

“No confirmed defect” means the full shipped implementation was reviewed but no code-proven bug or concrete edge failure survived recheck; it is not a claim that live-client testing can never find one.

| Feature family | Included behavior | Verdict |
|---|---|---|
| Bootstrap, module registry, event bus, scheduler | Namespace/export setup, module enable/disable, dispatch-safe unregister, keyed next-frame work | No confirmed defect |
| Defaults and upgrades | Fresh install, factory seed, schema repair, one-shot migrations | **F-02** |
| Profiles and import/export | CRUD, switch/reset/copy/rename, spec bindings, snapshots, compact strings, legacy Lua, Wago API, UUF conversion | **F-01, F-04, F-05, F-06** |
| Unit frames | Player, target, target-target, focus, focus-target, pet, boss; creation, visibility, anchors, health/power/text, status elements, portraits, prediction, absorbs, threat, tap, range | No confirmed defect |
| Group frames | Party/raid/mythic raid, secure headers, roster/sort/growth, role/status icons, dispel overlay, debuff stripe, targeted spells, range fade, previews | No confirmed defect |
| Regular Auras | Buff/debuff lanes, native containers, filters, dispel logic, identity updates, growth/anchors, group integration | No confirmed defect |
| Spell indicators | Candidate spell filters, native filter construction, placement, effects, missing-state frames, world-transition repair | **F-03, F-09** |
| Cast bars | Player/target/focus/boss, cast/channel/empower, latency, ticks, interrupt state, previews, anchors, driver/failsafe lifecycle | No confirmed defect |
| Class resources | Modes, alternate mana, player HP mode, Balance Druid state, smooth updates, spec/aura refresh, controller lifecycle | No confirmed defect |
| Menu2 and search | Navigation, pages, widgets, binding/apply service, previews, history, guided tour, scale, control metadata, Assistant bridge | Profile page affected by **F-06**; otherwise no confirmed defect |
| Edit Mode | Movers, HUD, focus, layout persistence, group/castbar/unit previews, popup scaling | No confirmed defect |
| Visual runtimes | Colors, Color Painter, fonts, textures, media, bar backgrounds, icon layout, rounded frames | No confirmed defect |
| Gameplay extras | Combat timer, combat-state text, combat crosshair, target sound, totems, click-through/nudge/range integration | **F-08** |
| Blizzard ownership and integrations | Blizzard frame suppression/restore, third-party anchors, NSRT nicknames, compartment/minimap/game menu | No confirmed defect |
| Versioning and changelog | Peer version messaging, update notice, changelog popup/state | **F-07, F-10** |
| Telemetry | Wago Analytics shim, opt state, deferred loading, module teardown | No confirmed defect |
| Localization | Locale selection, English fallback, 12 locale tables, reload behavior | No confirmed defect |
| Vendored libraries | LibStub, CallbackHandler, AceSerializer, LibDeflate, LibSharedMedia, analytics shim integration | No addon-facing defect found; upstream library internals were mechanically validated |

## Priority order

1. Replace executable legacy import and add complete import resource/schema limits (**F-01, F-04**).
2. Stop destructive factory migrations from overwriting divergent user values (**F-02**).
3. Validate spell-indicator native filters before Blizzard receives them (**F-03**).
4. Fix profile lifecycle contracts and stale spec mappings (**F-05, F-06**).
5. Resolve or redefine safe spell-indicator recovery, then restore a green core smoke suite (**F-09, QA-01**).
6. Correct prerelease version ordering and sanitize peer messages (**F-07, F-10**).
7. Add an event-driven/throttled camera-zoom re-anchor path (**F-08**).

## Final audit boundary

This report intentionally lists only findings that survived a second source/caller/test check. Potential concerns that were disproved by current code or Blizzard behavior were excluded. In particular, target-sound enemy direction matches Blizzard's own target-frame semantics; disabled gameplay timers/events have explicit teardown; and the failing profile/value/color/global-bars smokes listed above do not independently prove runtime regressions after their contracts changed.
