# Profile defaults and persistence

Runtime profiles remain ordinary materialised tables. `MSUF_DB` is the active
`MSUF_GlobalDB.profiles` entry. Readers, history, variants, sync, copy/reset and
import/export keep their full runtime values and table identities. Sparse storage
is applied only at terminal logout; it does not reduce runtime profile memory or
eagerly fill absent optional fields.

## Frozen V2 dictionary and presence

`tools/fixtures/defaults/schema.lua` owns typed factory, repair, literal-seed and
lazy-factory observations. `tools/defaults_schema_generate.lua --sparse-v2`
selects named scalar paths whose factory and repair defaults agree in both type
and value on Mainline, Vanilla, TBC, Mists and Forever. Eligible defaults are
`true`, nonzero numbers and nonempty strings. Internal and numeric path keys are
excluded. The generated data lives in
`State/Defaults/MSUF_Defaults_Schema.lua`: 3,595 field positions across 120 owner
paths, sharing 971 key/value pairs. It covers general and group settings plus
unit frames, castbars, auras, class power, fonts, colours and other certified
families; the original three `PersistenceEntries` are not the bulk codec.

The saved `_msufSparseDefaultsV2` value is an 899-character hexadecimal presence
mask. A bit is set only when that exact default was present and is removed.
Absent or lazy fields therefore stay absent after decoding. The field values,
owner paths and bit order are a frozen wire dictionary: future changes require
a new version and must retain the previous decoder. Regenerating it from changed
defaults must never silently redefine already stored V2 masks.

V2 uses `_msufDefaultsRevision = 17.5` together with its distinct mask key.
Successful restoration removes the mask and returns the revision to `17` before
normal migrations and persisted-profile fast paths. The mask and every referenced
owner are validated before any restoration write; only nil fields selected by
the mask are filled, so an existing explicit value wins.

## Saving, exact reconstruction and fallback

The lifecycle first restores/cancels variants and flushes profile sync. The final
native logout handler invokes the codec, then clears the standalone `MSUF_DB`
alias so the profile pool is serialized once. WoW does not guarantee a globally
last logout handler; the existing alias timing boundary is unchanged.

One traversal of the entire SavedVariables root checks for secrets, unsupported
types, non-finite numbers, metatables, cycles and excessive depth. It also records
shared references and numeric-keyed lists. The profiles container, each candidate
profile and every ancestor of an edited owner must have a single reference.
Unsafe roots remain full; unsafe profiles are skipped. Lists and their descendants,
unknown keys, spell/user entries, empty tables, explicit `false`, `0` and empty
strings are preserved. Only present, schema-known, exactly matching scalar
defaults can be removed. Short profiles stay full when the estimated saving does
not cover the fixed mask overhead; old unnormalised revisions are not encoded.

For each candidate, reusable scratch storage captures every known original
field, including absence. After elision, the real decoder restores the fields
in place and compares their types and values exactly. Only those known fields
and the two format markers can change; other keys and table identities are
untouched. A mismatch or removal-count discrepancy restores all original fields
and markers. Only a successful reconstruction is elided again for serialization.
There are no full-profile copies at logout. The store traversal allocates metadata
maps and each encoded profile creates a bounded mask string; this is not a
zero-allocation codec.

## Compatibility

Historical full profiles continue through the existing migration pipeline. The
frozen V1 decoder still accepts numeric `17.5` without a V2 mask and the older
`MSUF_SPARSE_DEFAULTS_1` string marker. V1 defaults are kept separate from V2 so
new dictionary entries cannot alter the meaning of an older sparse profile.
Import/export representation and wire schema 600 are unchanged.

New encodings retain fields whose path contains `migration`, `version`,
`revision` or `marker` (case insensitive), plus the legacy geometry discriminator
`positionMode`. The broad marker rule also conservatively retains visual marker
settings. Generated `retain = true` metadata suppresses capture only: all 3,595
existing field positions, values and owner ordering stay unchanged, and old masks
still restore the formerly elided markers. This prevents the verified 6.50 absorb
colour cleanup, unit-dispel ownership migration, group-aura repair and pinned-count
position conversion from replaying merely because those fields were elided.

After checking both format stamps for secrets, a V2 mask attached to a revision
other than `17.5` is discarded without filling V2 defaults or changing that revision.
The ordinary V1 string decoder still applies to its own revision. A materialised
revision-17 profile can then compact again; unknown revisions still stay full.
A corrupt mask at revision `17.5` remains unchanged and fails closed. Clearing a
stale mask cannot recover settings already lost during an older downgrade.

New V2 storage requires a V2-capable loader. An unchanged 6.50 installation is
not guaranteed to reconstruct it, even though the numeric revision remains
17.5. The focused backward-migration smoke executes pinned, exact 6.50 migration
source excerpts (optionally checked against a read-only legacy checkout); it proves
only the listed migration boundaries. Previously saved V2 masks should first be
loaded and saved by the corrected V2 loader before an older loader sees them.
Support for old full and V1 profiles in the new loader is not a downgrade
compatibility guarantee.

## Recorded offline evidence and limits

The 2026-10-24 V2 fixture run restored all 15 profiles from 11 SavedVariables
fixtures exactly, plus 30 legacy-marker cases, five client factory snapshots and
20 encode/malformed-decode countercases. A separate synthetic persistence run
using 36 copies of the largest fixture-derived profile took 0.345 seconds with
exact reconstruction. These are recorded offline measurements, not a new run
against every later workspace change or a live logout measurement. In particular,
these size/time figures predate the migration-marker retention correction.

For the largest raw fixture (`sv_retail_rev16_17.lua`, `Profile15`), `RoughBytes`
fell from 207,935 to 141,265: **32.06% less**. The fixture literal serializer fell
from 235,435 to 158,608 bytes. Neither figure is a measured native WoW file size.
The 80-90% reduction target was not reached. Even removing all nonzero/nonempty
scalars outside lists, including otherwise protected unknown/user/nondefault
values, leaves at least 40.6% in that fixture; safety rules must not be weakened
to meet the target.

The focused source-to-destination-and-back transfer smokes recorded 25 passing
client pairs. Some ran alongside unrelated source edits, so they do not establish
a frozen whole-build pass. The persistence smoke still stops in the shared
Golden harness's ApplyModules/PublicGlobals isolation before completing its
functional and allocation checks. Its existing allocation budgets remain
unfulfilled; the fixture benchmarks do not replace them. Full-gate, native WoW,
live downgrade and performance validation remain separate evidence requirements.
