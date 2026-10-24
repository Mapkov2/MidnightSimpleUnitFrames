# Profile defaults and persistence

Runtime profiles remain ordinary materialised tables. `MSUF_DB` is the active
`MSUF_GlobalDB.profiles` entry. Sparse storage runs only at terminal logout;
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
values already lost by an earlier loader. The backward-migration smoke tests
pinned 6.50 source excerpts; it establishes only those migration boundaries,
not complete native downgrade compatibility.

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
