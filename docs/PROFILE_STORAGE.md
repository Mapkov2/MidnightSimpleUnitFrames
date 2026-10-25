# Profile defaults and persistence

Runtime profiles remain ordinary materialised tables. `MSUF_DB` normally aliases
the active `MSUF_GlobalDB.profiles` entry. Rejected storage envelopes use a
detached session copy instead (see below). Sparse storage runs only at terminal logout;
readers, history, variants, sync, copy/reset and import/export retain their
runtime values and existing table identities. This reduces serialized storage,
not the runtime profile memory. Absent optional fields remain absent.

## V1, frozen V2 and inherited V3

`tools/fixtures/defaults/schema.lua` is the typed source used by
`tools/defaults_schema_generate.lua`. V1 remains a separate legacy decoder.
The frozen V2 dictionary retains all 3,595 positions, 120 owner paths and 971
pooled key/value pairs. Its 899-character hexadecimal presence mask is still
stored as `_msufSparseDefaultsV2`; neither its values nor bit order changed.
`--check` verifies that frozen block.

New saves additionally carry `_msufSparseDefaultsV3`: a 1,656-character mask
covering 6,622 exact paths across 180 owners (6,595 scalar leaves and 27 empty
tables). The 1,649 pooled pairs reuse matching V2 data; shared ordered ID runs expand once at load.
Generate/check this block
with `--sparse-v3` / `--sparse-v3 --check`. The generator rejects additions,
removals, reordering and list-policy changes to existing V3 slots: those require
a new codec version and the previous decoder. Values intentionally follow the
current canonical defaults. A formerly default-equal value therefore follows a
future default change, as requested by the owner; an explicit stored override
still wins. V3 fills selected nil leaves before the frozen V2 nil-only decoder.
Old V1/V2-only profiles retain their historical decoding semantics.

V3 certifies factory defaults shared by all five supported clients, including
factory-only fields whose repair default is nil, `false`, `0`, empty strings,
nested settings, and exact numeric paths in generated lists and aura/spell
settings. Presence bits distinguish a stored default from original absence.
Only source-certified paths are edited. Arbitrary list members, spell IDs,
custom record fields and unknown keys are retained. Client-dependent defaults
remain explicit. An unexpected numeric key on a named owner/ancestor protects
that subtree; numeric traversal is permitted only where the generated schema
certifies a list. Empty leaves are removed only with a unique reference.

## Exact reconstruction, rollback and allocation

The lifecycle restores/cancels variants and flushes sync before the native
terminal handler invokes the codec and clears the standalone `MSUF_DB` alias.
WoW does not guarantee a globally last logout handler; that timing boundary is
unchanged. A single whole-store traversal checks secrets, unsupported types,
non-finite numbers, metatables, cycles and depth, and counts shared references.
The profiles pool, candidate profile and every edited ancestor must be unique.
Unsafe roots stay full; unsafe profiles are skipped. Unknown revisions and
profiles too small to pay for both masks stay full.

Reusable scratch captures every known original field, including absence and
empty-table identity. The real decoder restores the elided fields in place;
all captured types and values must match before a second elision commits the
save. Any removal-count or reconstruction mismatch rolls back every field and
format stamp. Terminal verification reuses the captured empty tables. Serialized
login reconstruction creates independent empty tables; it never shares one
mutable default table across profiles. Existing owners are not replaced.

Scratch maps, presence buffers and pooled data are prepared/reused. The C11
steady-state test measured **0 logout allocation bytes**, including repeated
full encodes and their internal real-decoder verification. Initial scratch
capacity, changed-mask strings and normal login reconstruction may allocate;
this is a steady-state contract, not a claim that initialization allocates
nothing. Both original fast-check allocation contracts remain required.

## Compatibility and downgrade boundaries

Sparse storage still uses `_msufDefaultsRevision = 17.5`, returning it to `17`
after successful restoration and before normal migrations. Historical full
profiles and the frozen V1 numeric/string markers continue to load. Export
representation and wire schema 600 are unchanged.

Migration/version/revision/marker paths, private keys and `positionMode` remain
explicit. Broad marker retention also protects visual markers conservatively.
This preserves the verified 6.50 absorb-colour cleanup, unit-dispel ownership,
group-aura repair and geometry-conversion boundaries. Existing V2 masks can still
restore formerly elided markers; new encodings retain them.

Both masks and every referenced owner are validated before restoration writes.
A malformed current mask fails closed without partial writes. A string mask
owned by a newer revision remains unchanged, including an orphan V3 string.
A profile materialised by an older loader at an older revision has its stale
V2/V3 masks discarded without inventing leaves or changing that revision.
V3 without its V2 envelope at revision 17.5 is rejected. V2-only decoding does
not validate unrelated V3-only owners; old legal alias arrangements still load.

New V3 saves require a V3-capable loader. Neither unchanged 6.50 nor a V2-only
loader is guaranteed to reconstruct them. Stale-mask cleanup cannot recover
values already lost by an earlier loader. Use the explicit full-save path below
before returning to unchanged 6.50x; copying an ordinary sparse save is unsafe.

### Returning to unchanged 6.50x (E5, 2026-10-24)

Run `/msuf compatsave`, then log out or `/reload` **before** replacing 7.0 with
6.50x. The command prints what it arms. The terminal save first restores variants
and flushes sync as usual, then persists **every** profile, including inactive
profiles, as a full revision-17 table. V2/V3 masks are consumed, all elided leaves
are reconstructed, and migration markers, unknown keys, explicit `false`/`0`/empty
strings and originally absent optional fields retain their values. Historical
profiles receive the ordinary defaults normalization when necessary. No 6.50x
source change, decoder backport or special loader is required for this full
representation. An unknown/corrupt envelope refuses compatibility saving and
prints an error instead of falsely stamping it revision 17.

`MSUF_GlobalDB._compatSave` is `"armed"` until a successful terminal full save
marks it `"saved"`. Repeated terminal saves in that session stay full. A later
7.0 login checks the original on-disk profiles **before** decoding: a completed
full revision-17 save disarms the mode and the following logout saves sparse
again. Sparse/incomplete data cannot consume the request. `/msuf compatsave off`
cancels it explicitly. These account metadata fields are outside the profile
pool and unchanged 6.50x ignores them.

As of 2026-10-25, `profile_rollback_full_graph_smoke.lua <root> <client>`
reads an immutable **v6.503** source snapshot, pinned by
`tools/tests/historical_6503_source.py` to commit
`d8af82416ec07e8755c89e35c83bcd2320868a10` and tree
`ded900e72626f1ad37b4915f5dc05e92c8e5f401`. The default location is
`dist/historical/6.503-d8af824`; `MSUF_HISTORICAL_6503_DIR` selects another
prepared source directory. Prepare the ignored local archive with
`python tools/tests/historical_6503_source.py --materialize-from <repository-containing-the-pinned-commit>`.
CI checks out the pinned commit separately. The verifier reconstructs its Git
tree from file bytes; missing, changed or extra files fail verification. The
owner's live production worktree is neither a test input nor required on CI.

The current `client_world` harness and `client_manifest.lua` reader resolve the
historical core TOC and XML manifests and load every listed Lua chunk. Options
remains unloaded, matching an ordinary login. The corpus graph cache includes
the source root, so a 7.0 graph cannot stand in for the historical graph in the
same process. The test selects `standard` on Mainline and `camelot` on Forever
explicitly; it omits the corpus's extra export/materialization pass on every
login. Both TOC-declared SavedVariables globals are serialized as independent
Lua assignments and evaluated into a fresh sandbox at every handoff:

1. A real 7.0 terminal V3 sparse save and new login.
2. The real `/msuf compatsave` command, terminal save and serialized full data.
3. The complete pinned v6.503 login (`ADDON_LOADED`, `PLAYER_LOGIN`, queued
   timers), real `MSUF_EnsureDB`, terminal logout and serialized data.
4. A fresh 7.0 login; the complete canonical profile-pool bytes must equal the
   original materialized profiles, including unknown values and absent fields.

The historical login, explicit EnsureDB and logout must match the original
profiles with only the historical normalization stamp substituted. On
2026-10-25, current 7.0 uses 21 and pinned v6.503 uses 22. The intermediate
stamp changes and is restored on return; no fields are excluded from the final
byte comparison. Raw bytes of every historical Lua chunk, XML manifest, TOC
and reader input are checked unchanged after the test. Missing source files,
chunk-load failures, unexpected caught or reported errors and changed return
values fail the test; an unavailable snapshot is never silently skipped.

Factory and applicable SavedVariables corpus cases run on Mainline, Vanilla,
TBC, Mists and Forever. The corpus harness checks isolated exceptions and
Boundary error-handler reports against `Corpus.HARNESS_ERRORS`; each allowed
failure names the precise frame-only stub artifact. The historical graph has
additional explicit frame-only exceptions in the rollback smoke, including its
health painter's unmodelled text-runtime numeric field at
`MSUF_UF_Elements_Health.lua:951` and deferred Highlight frame scale at
`MSUF_UF_Highlight.lua:220`. State errors remain fatal. This is full-graph
offline profile proof; native WoW serialization, live rendering/combat/taint
and an in-game downgrade remain untested.

Historical correction (2026-10-25): the earlier documentation described a
Forever alias-catalog abort using a first-condition-only TOC interpretation.
The current reader evaluates **all stacked conditions together**. On the
pinned v6.503 alias line, `AllowLoadTextLocale enUS` does not override
`ExcludeLoadGameType camelot`; Forever excludes both the alias data and its
Common provider. That obsolete harness interpretation is no longer a reason
to abort the Forever rollback test. Current addon TOCs retain the separate
lint rule requiring one condition per line.

`profile_rollback_compat_smoke.lua` retains focused arm/off/interrupted-save,
corrupt-profile and allocation checks, including its pinned historical
current-profile guard. That excerpt is not the full downgrade proof. The
separate backward-migration smoke pins the older migration boundaries.

### One-time account safety copy

Before the first sparse save, `_pre70ProfileBackup` retains one independent,
full account snapshot: `{ version = 1, source, profiles, char, legacy? }`.
The capture happens at SavedVariables settlement, before profile migrations,
retirement or pre-6 archival. A fresh account captures its initial materialized
profile after binding. Character bindings and any standalone legacy profile are
included so recovery retains the original account selection evidence. It never
copies unrelated account history, never includes itself, never grows with later
profile edits/creation, and is never overwritten, compacted or consumed by
restore. Full pre-7.0 inputs remain byte-identical. For an account already saved
sparse before this build, only the currently reconstructable full data can be
retained; `source = "reconstructed"` explicitly records that limitation.

There is **one snapshot per account**, with an **8 MiB conservative serialized
payload budget**. The size walker charges four bytes per string byte (maximum
Lua escaping), 32 bytes per non-string scalar, plus key/table syntax, counting aliases as
repeated serialized content. Both input and fully reconstructed output must fit.
This is a bound on the snapshot payload estimate, not a measurement of native
WoW file formatting or Lua heap use. No profiles are truncated to fit. Unsafe,
cyclic, undecodable or oversize input leaves no partial copy; sparse saving is
disabled for that live account and a logout message explains that it stays
full. A failed original capture cannot be replaced with post-migration data in
that session. Existing snapshot data is retained even when invalid. Capture validates
bounded table content and required compatibility shape: a nonempty named profile
pool, character-binding shape, a nonempty general font key and positive player and
target dimensions, with no sparse envelopes. The snapshot's `validation` stamp
stores generator revision 1, the conservative payload size, an anchor profile name
and an envelope consistency key. Later logins check those scalar facts and the
anchor compatibility shape in constant time. A missing/inconsistent stamp triggers
full validation before it can be replaced; invalid payloads remain refused.
These persisted facts are login hints only. Before the first sparse persist of
each session (terminal logout/reload), a full content preflight validates the
snapshot again, including inactive profiles. The result is cached only in a
session-local weak table keyed by snapshot identity. The old account
`_pre70SparseValidated` field is cleared at session start and grants no approval.
A failed preflight removes no defaults and explains once that the account stays
full. Explicit restore always revalidates the full payload.
`profile_rollback_session_validation_smoke.lua` covers damage after a previous
sparse save and serialized login; `profile_rollback_validation_smoke.lua` pins
malformed payloads, stamp upgrades, preflight and strict secret handling across
all five clients. Fresh full capture reuses its source safety/size walk;
reconstructed snapshots are checked again after expansion.

In the corpus, maximum uncompressed `profile_state_harness.Literal` snapshot
sizes are **699,910 bytes** on Mainline/Forever and **447,590 bytes** on
Vanilla/TBC/Mists. The extra full copy is a deliberate one-time storage/memory
cost; later sparse saves do not create another snapshot. Full-save and sparse
terminal persistence retain their **zero-byte steady-state allocation** contracts;
first capture, decoding and explicit recovery may allocate.

`/msuf restorebackup` prints that **all account profiles and character profile
bindings will be replaced**, losing later edits and profiles. Only a subsequent
`/msuf restorebackup confirm` performs it; `cancel` discards the pending request,
and combat refuses it. Restore copies the snapshot, rebinds the profile through
the normal migration/runtime path, and arms compatibility saving for the next
logout/reload. The immutable snapshot remains available. This is an account
profile restore, not an import, rolling history or restore of other addons.

`profile_rollback_backup_smoke.lua <root> <client>` verifies exact pre-login
corpus bytes, snapshot independence across edits/logout/reload/restore,
confirmation/cancel/combat, the size bound, and reconstructed-input provenance.
The rollback compatibility and backup tests are registered for all five client
tokens in `tools/release-test-inventory.json` and run through
`tools/release-check.ps1`; they add no shipped module or TOC entry.

### Decoder rejection and quarantine (E2, 2026-10-24)

`DefaultsSchema.RestorePersistence(profile)` returns the historical change
boolean plus an explicit outcome: `not-sparse`, `restored`, or `rejected`.
An invalid V2/V3 mask, missing referenced owner, unsupported envelope owner or
orphan V3 envelope is rejected before any reconstruction writes. Both public
normalizers stop immediately on that outcome; migrations and inactive-profile
menu filling also skip quarantined data.

The stored profile remains untouched in `MSUF_GlobalDB.profiles`. An independent
snapshot is retained under `_rejectedProfileBackups[profileName]`, using the
bounded recovery format below. The session binds a cached independent copy:
missing values are filled from a fresh normalized factory profile, invalid
owner types receive safe tables, explicit scalar values are retained, and storage masks are removed only from this working copy.
For example, `bars.bossCastbarOffsetY = 0` and `general.fontSlug = true` survive
rejection unchanged in both stored and session data. Later normalizer calls
recognize the working copy and do not replay migrations against it.

Switching away and back preserves session edits to that copy. Sync writes to a
quarantined target use its session copy. Logout never writes this copy over the
original; its session edits are intentionally temporary until the owner repairs
or explicitly replaces the profile. Reload retries the original envelope with
the current decoder. Private normalization candidates return a detached copy
without changing the supplied input; callers must use the returned table.

### Newer revision recovery (C13/E2, 2026-10-24)

Before either login normalizer changes a stored profile with a newer numeric
`_msufDefaultsRevision` (above 17, excluding the supported 17.5 sparse token),
the shared decoder saves an independent deep copy. Active, inactive, standalone
and startup donor profiles use the same boundary. Ordinary revisions create no
backup state. A supported full newer profile retains its previous normalization
behaviour only after that backup succeeds; an undecodable sparse envelope
uses quarantine instead.

As of 2026-10-25, refused capture of a newer full profile also uses quarantine.
Unsafe, oversized or malformed recovery data cannot authorize lossy
normalization: the stored original stays untouched, the session uses a detached
working copy, and one translated notice explains that session edits will not
be saved. The refusal propagates from `BackupNewerRevision` through
`RestorePersistence` to the normalizer. `profile_backup_refusal_smoke.lua`
checks this on all five clients.

`MSUF_GlobalDB._newerRevisionBackups[profileName]` is now a bucket with a persisted
`identity`, an ordered list `order`, and `entries[key]`. A key contains profile
identity, original revision and a deterministic 64-bit content fingerprint.
Canonical serialization covers every supported field, including unknown fields
and both masks. Hash collisions are resolved by comparing complete canonical
content and adding a suffix, never by replacing an entry. Identical bytes do
not create another entry. A bucket retains its last three distinct snapshots;
adding a fourth removes only the oldest entry. Existing single-entry backups
are imported into this history before adding a new snapshot.

Each entry contains `{ revision, hash, data }`; existing entries are never edited.
The bucket's `revision` and `data` fields provide a compatibility view of the
latest snapshot. Quarantine uses the same format under `_rejectedProfileBackups`.
Both stores live outside the profiles pool and logout compaction leaves them
unchanged. Profile rename moves recovery identity and history with the profile.
Deletion archives its buckets under `_profileRecoveryArchive`; reusing the name
gets a new identity. Archived snapshots remain restorable by their original key.
Newer snapshots retain the existing translated chat notice.

`MSUF.DefaultsSchema.RestoreProfileBackup(profileName, key, kind)` explicitly
replaces that stored profile with an independent copy of the selected entry.
The default kind selects newer-revision history; `"rejected"` selects quarantine.
Omitting the key selects the latest snapshot and also upgrades legacy buckets.
It returns the restored table, or `nil, reason` for an unknown key/store. It
neither binds nor normalizes the result, and it never edits the backup. Malformed
persistence envelopes are refused transactionally on import; a valid replacement
of a quarantined profile adopts the new data and retires its stale session flag.
Recovery
should be performed before binding with a loader that understands the saved
revision; calling it does not add support for an unknown format.

### Shared alias ownership

`StateHelpers.AliasMigrations` owns the alias revision, unit owner aliases and
context definitions. `NormalizePositionAliases` and `NormalizeProfileTextAliases`
are the common migration entry points. The narrow `defaults` boot context keeps
empty strings, rejects non-boolean inverse sources, uses the historical scope
set and clamps offsets to 10000. The `profileio` context drops empty strings,
coerces inverse sources, covers import-only scopes, infers scoped font ownership
and clamps offsets to 4096. Metadata trust remains explicit at the translator
boundary. The Defaults revision still owns broad default filling, separately
from the shared alias ledger.

`profile_alias_corpus_bytes_smoke.lua` compares complete corpus subtree dumps
with a supplied baseline directory (argument 3); `--capture` at argument 4 writes
the baseline there. Without a baseline directory it compares both shared alias contexts against
independent pre-refactor rules on the raw corpus, factory and adversarial data. E2 captured all 31 client/fixture runs before the alias refactor, across
Mainline, Vanilla, TBC, Mists and Forever; the before/after check requires exact
serialized bytes and does not regenerate goldens. New executable contracts are
`profile_decoder_quarantine_smoke.lua` and `profile_backup_history_smoke.lua`.
`profile_ensure_recovery_budget_smoke.lua` measures the cached public runtime
guard: 10 to 9 VM instructions per call on all five clients, one native type
check per call unchanged, and zero allocation bytes over 1000 calls (minimum of
two allocation runs). Recovery work stays after this cached fast path.

## C11 byte measurements (2026-10-24)

All sizes below use `profile_state_harness.Literal`, with the same serializer
before and after, against baseline `c5fe4e3cb`. They are uncompressed Lua literal
bytes, **not native WoW SavedVariables file sizes**. The former 158,608-byte V2
figure preceded marker retention; the current V2 baseline is 159,845 bytes.

The new diagnostic `tools/tests/profile_sparse_size_smoke.lua` exercises exact
raw/login/factory roundtrips, V2-only loading, default inheritance, rollback
fault injection, malformed masks, secrets, list/unknown data, shared empty
leaves and steady-state allocation. Pass an optional baseline schema file as
argument 2 to reproduce the V2 column. No golden files were rewritten.

### Raw corpus fixtures

Historical revisions deliberately remain full until the ordinary login pipeline
normalizes them. This is why most raw rows do not shrink directly.

| Fixture/profile | Full | Current V2 | V3 | V3/full |
|---|---:|---:|---:|---:|
| sv_retail_rev16_17/Profile01 | 172,682 | 172,682 | 172,682 | 100.0% |
| sv_retail_rev16_17/Profile15 | 235,435 | 159,845 | 107,212 | 45.5% |
| sv_ptr_rev13/Default | 175,022 | 175,022 | 175,022 | 100.0% |
| sv_ptr_rev6/Profile01 | 215,274 | 215,274 | 215,274 | 100.0% |
| sv_xptr_rev15/Profile01 | 214,289 | 214,289 | 214,289 | 100.0% |
| sv_pre6_feb/Default | 20,277 | 20,277 | 20,277 | 100.0% |
| sv_pre6_mar/Default | 30,571 | 30,571 | 30,571 | 100.0% |
| sv_pre6_mar/Profile01 | 30,225 | 30,225 | 30,225 | 100.0% |
| sv_pre6_mar/Profile02 | 23,590 | 23,590 | 23,590 | 100.0% |
| sv_pre6_mar/Profile03 | 24,413 | 24,413 | 24,413 | 100.0% |
| sv_forever_beta_rev17/Profile01 | 195,243 | 100,224 | 23,959 | 12.3% |
| sv_mists_rev15/Default | 183,158 | 183,158 | 183,158 | 100.0% |
| sv_era_rev15/Profile01 | 220,412 | 220,412 | 220,412 | 100.0% |
| sv_tbcptr_rev14/Default | 198,438 | 198,438 | 198,438 | 100.0% |
| sv_anniversary_rev17/Profile01 | 207,401 | 119,812 | 60,472 | 29.2% |

### Same fixtures after the real login/bind pipeline

Pre-6 profiles are archived by that existing pipeline; these two login rows
measure its replacement Default, not deletion or compaction of the archive.
No archived data is removed by this change.

| Fixture/profile | Materialised | Current V2 | V3 | V3/full |
|---|---:|---:|---:|---:|
| sv_retail_rev16_17/Profile01 | 189,579 | 93,993 | 17,196 | 9.1% |
| sv_retail_rev16_17/Profile15 | 237,582 | 160,831 | 107,267 | 45.1% |
| sv_ptr_rev13/Default | 237,677 | 154,522 | 88,335 | 37.2% |
| sv_ptr_rev6/Profile01 | 216,870 | 131,800 | 66,690 | 30.8% |
| sv_xptr_rev15/Profile01 | 234,831 | 157,215 | 102,810 | 43.8% |
| sv_pre6_feb/Default | 185,328 | 89,665 | 12,351 | 6.7% |
| sv_pre6_mar/Default | 185,328 | 89,665 | 12,351 | 6.7% |
| sv_forever_beta_rev17/Profile01 | 195,663 | 100,558 | 23,984 | 12.3% |
| sv_mists_rev15/Default | 201,667 | 106,038 | 29,259 | 14.5% |
| sv_era_rev15/Profile01 | 239,531 | 161,924 | 106,817 | 44.6% |
| sv_tbcptr_rev14/Default | 227,487 | 149,432 | 86,391 | 38.0% |
| sv_anniversary_rev17/Profile01 | 207,426 | 119,837 | 60,497 | 29.2% |

### Source-built factory snapshots

| Client | Full | Current V2 | V3 | V3/full |
|---|---:|---:|---:|---:|
| Mainline | 185,289 | 89,626 | 12,351 | 6.7% |
| Vanilla | 189,571 | 93,908 | 16,634 | 8.8% |
| TBC | 196,307 | 100,644 | 23,370 | 11.9% |
| Mists | 196,307 | 100,644 | 23,370 | 11.9% |
| Forever | 189,525 | 93,862 | 16,587 | 8.8% |

### Largest raw profile: complete remaining-byte ledger

Profile15 falls from **235,435 to 107,212 bytes** (54.46% less), or a further
32.93% below corrected V2. Its disjoint residual ledger is:

| Component | V2 bytes | V3 bytes |
|---|---:|---:|
| Known nondefault scalar payload | 5,832 | 5,832 |
| Opaque/uncertified user-data payload | 14,923 | 14,918 |
| Still default-equal scalar payload | 7,728 | 463 |
| Format masks and revision payload | 905 | 2,563 |
| All field names and key/assignment syntax | 123,236 | 78,364 |
| Table braces and entry separators | 7,221 | 5,072 |

Empty-table braces are a subset of structural syntax: 120 V2 bytes versus 176
V3 bytes (elision makes more retained owners empty). They are not added twice.
The following alternative attribution includes each default-equal leaf's own
key/assignment bytes, excludes inter-entry separators, and is **not additive**
with the disjoint ledger above:

| Default-equal leaf family | V2 bytes | V3 bytes |
|---|---:|---:|
| Retained marker/private/discriminator fields | 2,844 | 2,844 |
| Known aura/spell settings (including numeric descendants) | 13,195 | 197 |
| Other numeric-list entries | 83 | 0 |
| Other nested-table leaves | 44 | 0 |
| Other named scalar defaults | 38,966 | 264 |

Known deviations require **26,881 bytes** including their own keys; opaque
retained fields require **62,347 bytes**, before table braces or entry separators.
Thus **89,228 bytes (37.90% of the full profile)** must remain under the current
invariant that unknown/user fields are preserved. That already exceeds the
47,087-byte 20% target. Examples include legacy `groupFrames`/`groupframes`
records, user custom aura containers, per-spec spell indicators, blacklist IDs,
Edit Mode snapshots and custom colour records.

This proves that **certified-default elision alone cannot reach 10-20% for this
fixture under those invariants**. It does not prove every opaque field is a
genuine semantic deviation: some custom records may contain constructor defaults
that are not certified by the canonical schema. Removing them by resemblance
would not be safe. A future record-template codec or general compression is a
separate design, with new reconstruction and downgrade obligations. The factory
snapshots already reach 6.7-11.9% without dropping user data.

### Verification boundary

The focused C11 diagnostic passed its exact reconstruction, malformed-input,
rollback, inheritance, secrets and allocation checks. Generated V2 and V3 checks
passed. The independent read-only review reproduced and verified fixes for an
old-V2 alias regression and newer-revision orphan-mask preservation; no remaining
correctness findings were reported. Final `tools/release-check.ps1` ended with
**0 failed** (147 seconds inside Lua slots); its fast-check ended with **0 failed**
(99 seconds). All four profile contract runs, five-client sparse persistence and
transfer steps, and legacy-marker step passed. Offline checks do not establish native logout serialization,
live taint/combat behaviour or a full 6.50 downgrade guarantee.
