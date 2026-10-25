# Old-profile regression corpus

Owner rule for MSUF 7.0: old profiles keep working. Every 5.x and 6.x
SavedVariables file and every profile string that loads today must give the
same effective settings after a refactor. This corpus is that safety net: a
refactor package is accepted only while its golden files stay byte-identical.

Current release path (2026-10-25): `tools/release-check.ps1` executes
`tools/tests/profile_corpus_golden_smoke.lua <root> <flavor>` on Mainline,
Forever, Vanilla, TBC and Mists, plus `encoding_util_emulator_smoke.lua <root>`.
The executable rows live in `tools/release-test-inventory.json`; the frozen
prototype gate is not invoked. Historical expected files are read-only.
`profile_defaults_oracle_smoke.lua` additionally checks the recorded typed
factory/repair schema on all five clients and rejects deliberate provider
mutations. Roundtrip contracts remain additional checks.

The corpus excludes only the new account `_pre70ProfileBackup` from its
historical account-key view: it duplicates profiles and has its own exact-byte
and validation contracts (`profile_rollback_backup_smoke.lua` and
`profile_rollback_validation_smoke.lua`). Historical profile, archive, binding,
import and reset values remain compared with their committed goldens.

## Files

- `corpus.lua`: the entry list (id, kind, file, clients, login character,
  profile strings).
- `sv/*.lua`: anonymized SavedVariables files (`MSUF_GlobalDB`, `MSUF_DB`).
- `imports/*.txt`: profile strings, one per file, wrapped at 120 characters
  (the line breaks are not part of the string).
- `golden/*.golden`: the recorded effective settings, one file per entry.
- `build_corpus.lua`: builds one `sv/` file from a copy of a real
  SavedVariables file.
- `build_imports.lua`: writes `imports/` from this repository's history and
  the baseline exporter.
- `tools/profile_corpus_golden.lua`: the check (default) and the golden writer
  (`--write`).
- `tools/tests/profile_corpus_golden_smoke.lua`: the gate wrapper, the check for
  one client.
- `tools/tests/encoding_util_emulator.lua`: a pure Lua `C_EncodingUtil`;
  `tools/tests/encoding_util_emulator_smoke.lua` holds it to the documented
  contract with independent vectors (RFC 4648, RFC 8949 Appendix A, Python
  zlib and gzip output).

All of them are CRLF text, like the rest of the worktree.

## What one entry run does

For each client an entry lists, `profile_corpus_golden.lua` builds a fake
client with `tools/tests/client_world.lua` and does what the game does:

1. Loads the client's core TOC graph. The Options addon is load-on-demand and
   stays unloaded, as at a login.
2. Installs the SavedVariables globals (a deep copy of the fixture) and fires
   `ADDON_LOADED`: FirstLoad settles, pre-6 profiles go to the archive, the
   retired Assistant and profiler data are cleared.
3. Fires `PLAYER_LOGIN` to every registered handler and runs the one-frame
   `C_Timer` callbacks they queued (the legacy bar texture rename is one), each
   isolated the way the client's error handler isolates it. The profile binds
   lazily inside these handlers.
4. Runs `MSUF.ProfileIOEnsureCompleteProfileDB` on the bound profile, the pass
   export and variant recording run before they read a profile (defaults pass,
   unit alpha, group frame and aura fills).
5. Records what exists (every account key, archived profile and profile), the
   account table, the character bindings, and what a login of every stored
   character (and of a new one) would bind: `resolve[<char>] = "<profile> <-
   <source>"`, where `<source>` is the stored table a missing profile would be
   copied from.
6. Binds every profile of the pool with `MSUF_SwitchProfile` (the login profile
   first), completes it as in step 4 and records its effective settings.
7. Exports each profile (`MSUF_ExportSelectionToString("all")`), imports the
   string with `MSUF_ImportIntoNewProfile` and asserts the copy has the same
   effective settings (see "Round trip").

The `factory` entry starts from empty SavedVariables (a fresh install), creates
a profile (`Created`), resets a stored one (`Reset Stored`), imports every
string of `imports/` into a new profile (`Import <id>`), and last resets the
active Default (`resetActive`).

What is real and what is not:

- Real: every core file, State included, the codec, FirstLoad, migrations, the
  defaults passes, profile create/switch/reset/delete/import/export, and the
  runtime apply after a profile change (`MSUF.ProfileRuntime.Apply`) with its
  State steps: variant resolution, sync activation, cache invalidation, number
  format, locale.
- Isolated: the frame steps of that apply and the repaints the import calls
  after its commit (`FRAME_STEPS` in `profile_corpus_golden.lua`). They run for
  real, lazy defaults included, but the harness models no real frames, so some
  fail part way; each failure is caught like a failing frame script and must
  match `Corpus.HARNESS_ERRORS` (see "Errors").
- Emulated: `C_EncodingUtil`. It reads genuine in-game strings (the embedded
  factory strings inflate to the same bytes as Python's zlib gives, Adler-32
  checked) and writes real Deflate (zlib reads it) and CBOR.
- Fixed: the clock (`time()` = 1790000000), the locale (enUS), a 1920x1080
  screen, the character name and realm of the entry's login character.
- Bounded: an entry gets 60 s of CPU; product code that loops on a harness
  stub fails the smoke instead of hanging the gate.

The harness hooks name product code: `State/MSUF_ProfileRuntime.lua` and
`MSUF.ProfileRuntime.Apply`, the functions in `FRAME_STEPS`, and
`MSUF.ProfileIOEnsureCompleteProfileDB`. A package that moves one of them
updates the hook in the same change (the run stops with a message when the
first or the last is missing).

## Effective settings

`Corpus.Effective(profile, defaults)` in `profile_corpus_golden.lua` is the one
definition. Today State materializes every default into the stored profile
when it binds, so the effective view is the stored table and `defaults` is nil.
When profiles become sparse, only that function (and the `Defaults` helper
beside it) changes to return the defaults overlaid with the stored values.

## Golden files

A golden file lists, per recorded subtree, only the paths whose value differs
from that subtree's reference, one `path = value` per line. `nil` means the path
is absent. Paths are canonical: `.key` for identifiers, `["text"]` and `[n]`
otherwise; keys sorted (numbers, then strings); numbers in the shortest form
that reads back as the same double; an empty table is `{}`. `[common]` lists the
lines every client of the entry shares, `[<client>]` the rest for that client.

References:

- `exists`, `login`, `resolve`, `import`, `importPayload`, `roundtrip`: none,
  every value is listed.
- `global`, `char`, `account.<key>`, `archive[...]`: the entry's input, the
  fixture's table of the same name (an archived profile is compared with the
  profile it was). `account.<key>` exists for every key of the input or the
  output, so a table the login drops lists every value it lost.
- `profile[...]` of a SavedVariables entry: its stored table, or, after an
  `@overlay profile[...]` line, its stored values over the values a fresh
  install of the same client has (`profile["Default"]` of `factory.golden`).
  The writer picks the one that lists fewer lines.
- `profile[...]` of the factory entry: the first-login `profile["Default"]` of
  the same run, or, after `@overlay`, the imported string's own profile table
  over it. That table is decoded by the corpus itself (the emulator's raw
  codecs), never by the addon's codec, and `importPayload[<id>]` pins it by
  path count and Adler-32: a codec change moves the result and not the
  reference, an edited fixture changes the pin. `profile["Default"]` itself has
  no reference: it is the full fresh-install profile.

Volatile fields, excluded on both sides (`Corpus.VOLATILE`): FirstLoad and
guided tour timestamps, the first-seen addon version, the per-release What's
New tracking, and `global.bindings` (an observational copy of the client's live
key bindings that every login re-reads).

On a failure the smoke prints the first 40 differing paths of each entry as
`<path>: expected <golden value>, got <recorded value>`.

### Round trip

`roundtrip[<profile>] = "identical"`, or one line per difference the baseline
shows on purpose, with its rule, its direction and both values:
`roundtrip[<profile>].excepted["<path>"] = "<rule> <added|dropped|changed>:
<before> -> <after>"`. A difference no rule of `Corpus.ROUNDTRIP_EXCEPTIONS`
names fails the corpus, and the writer refuses to write it. The rules:

- `editModeOptIn`: `general.blizzardEditModeSnapshot` travels only while the
  Profiles page switch is on; it is off by default.
- `suiteOwned`: `suiteModules` belongs to the MSUF Suite
  (`State/MSUF_ProfileExternal.lua`); MSUF strings never carry it.
- `screenReference`: export stamps `screenPositionMode`/`screenPositionHeight`
  on positioned frames.
- `filledOnImport`: keys the import's forced normalization adds that the stored
  profile lacks (see "What the baseline shows").

### Errors

Every error a run catches counts: a `PLAYER_LOGIN` handler, a timer, a frame
step, the completion pass, or a profile operation (an error or a refusal of a
create, switch, reset or delete). Only the rows of `Corpus.HARNESS_ERRORS` are
allowed: the frame code of the fake client failing where the harness answers a
frame size, scale or count read with a stub table. A row names where the error
was caught, the file, the message without its line number (lines move with
any edit) and the clients. A full run of a client also fails on a row that no
longer occurs there. Profile operations and the completion pass have no rows.

## Entries

SavedVariables files were copied out of `E:\World of Warcraft\<client>\WTF`
read-only (account names below are placeholders), anonymized and reduced with
`build_corpus.lua`. Revision means `_msufDefaultsRevision` (current: 17); pre-6
files have no `_msufProfileSchema`. A SavedVariables file belongs to its client
family; profile strings carry settings across families.

- `factory`: empty SavedVariables; all five clients. The fresh-install anchor:
  new and reset profiles and all 19 strings on every client, Retail strings on
  Classic and back.
- `sv_retail_rev16_17`: `_retail_`, account A, saved 2026-10-13; 2 of 4
  profiles (revisions 16 and 17), 8 of 26 characters, layout caches; Mainline,
  Forever. The live account: newest revisions, a Priority Frames pin of another
  player, `defaultProfileForNewChars` naming a profile that is not kept.
- `sv_ptr_rev13`: `_ptr_`, account A #3, 2026-08-11; Default of 8 profiles, 9
  characters; Mainline, Forever. Revision 13; three characters bound to
  profiles that are not kept; retired Assistant data in the account table.
- `sv_ptr_rev6`: `_ptr_`, account A #4, 2026-07-30; 1 of 2 profiles, no Default;
  Mainline, Forever. Revision 6, the oldest 6.x stamp.
- `sv_xptr_rev15`: `_xptr_`, account A #3, 2026-09-16; 1 of 2 profiles;
  Mainline, Forever. Revision 15 on Retail; retired Assistant history.
- `sv_pre6_feb`: `_retail_/WTF - Kopie`, account B, 2026-02-01; all (5.x, 1
  profile); Mainline, Forever. An untouched 5.x install: archive, rebind,
  FirstLoad upgrade.
- `sv_pre6_mar`: `_beta_`, account A #3, 2026-03-06; all 4 profiles (5.x), 8 of
  18 characters; Mainline, Forever. 5.x with several profiles and bindings.
- `sv_forever_beta_rev17`: `_classic_beta_` (WoW Forever beta), account A #3,
  2026-10-10; 1 of 3 profiles; Forever, Mainline. A Forever-authored profile
  with Suite module data.
- `sv_mists_rev15`: `_classic_` (Mists Classic), account A, 2026-09-19; all (1
  profile); Vanilla, TBC, Mists. Mists-authored, revision 15.
- `sv_era_rev15`: `_classic_era_`, account A, 2026-09-16; 1 of 2 profiles, 3
  characters; Vanilla, TBC, Mists. Era-authored, revision 15; retired
  Assistant history.
- `sv_tbcptr_rev14`: `_classic_era_ptr_` (Anniversary PTR realm), account A #3,
  2026-09-09; all (1 profile); Vanilla, TBC, Mists. Revision 14.
- `sv_anniversary_rev17`: `_anniversary_`, account A, 2026-10-13; 1 of 3
  profiles; Vanilla, TBC, Mists. Revision 17 on Classic.

Checked and left out: the second `WTF - Kopie` account file (5.x, five profiles,
same era and shape as `sv_pre6_mar`), `_beta_` account A #2 (5.x, one profile,
same shape as `sv_pre6_feb`), the remaining profiles of the files above (same
revision as a kept one), and every `.bak` sibling (an identical copy or a few
minutes older save of the same file).

### Profile strings (`imports/`, all imported on every client)

Genuine strings from this repository's history (`<commit>:<path>`):

- `hist_2026-01-18_msuf2_preset`: `22225cf81:MSUF_Presets.lua`, first preset.
  MSUF2 base64(deflate(CBOR)), portable schema 1 (a 5.x preset). Imported.
- `hist_2026-05-04_msuf3_corrupt`:
  `9eae6d59f:MidnightSimpleUnitFrames/Foundation/MSUF_Defaults.lua`. MSUF3 whose
  Deflate stream is broken as committed (zlib agrees). Refused, no profile
  created.
- `hist_2026-05-27_msuf3_portable`:
  `7a13b8437:MidnightSimpleUnitFrames/Foundation/MSUF_Defaults.lua`. MSUF3,
  portable schema 1 without a native section. Imported.
- `hist_2026-07-14_msuf3_raw_profile`:
  `d9786ae5a:MidnightSimpleUnitFrames/State/MSUF_Defaults.lua`. MSUF3, a bare
  schema-600 profile table. Imported.
- `hist_2026-08-06_msuf3_full_schema1`:
  `157c8c53a:MidnightSimpleUnitFrames/State/MSUF_Defaults.lua`. MSUF3, portable
  envelope whose native section is schema 1 (6.0 beta era). Accepted through
  validated full-profile migration; the native table has real player/target
  geometry. Invalid embedded beta payloads remain refused.
- `hist_2026-08-15_classic_factory`:
  `3413e0a8f:MidnightSimpleUnitFrames/Game/Classic/State/MSUF_Defaults.lua`.
  MSUF3, portable envelope with a schema-600 native section, Classic-authored.
  Imported.

The 6.50 baseline (a97896f5):

- `base_factory`, `base_forever_factory`: the embedded factory strings of
  `State/Defaults/MSUF_Defaults_Shell.lua` and `MSUF_Defaults_ForeverFactory.lua`.
- `base_modern_dark`: `MidnightSimpleUnitFrames_Options/State/MSUF_Defaults_ModernDark.lua`,
  the Suite's Modern Dark (an MSUF3 schema-600 snapshot).
- `base_msuf4_<kind>`: the baseline exporter's MSUF4 strings of kind unitframe,
  castbar, colors, gameplay, groupframe and unitselection (player, target),
  from profile `Profile01` of `sv/sv_xptr_rev15.lua` on Mainline. Partial kinds
  merge into a new profile's factory base.

Older transports, rebuilt from a baseline string:

- `synth_msuf2_printsafe_castbar`: MSUF2 in LibDeflate's print-safe alphabet
  (Wago style).
- `synth_msuf3_uncompressed_colors`: MSUF3, base64(CBOR) without compression.
- `synth_text_gameplay`: the plain-text table literal.
- `synth_msuf3_pre6_profile`: profile `Default` of `sv/sv_pre6_feb.lua`, a 5.x
  profile without a schema stamp. Refused: "MSUF 6.x profile required (schema
  600)".

Every `hist_*` string and the three embedded `base_*` strings are byte for byte
the shipped ones; `base_msuf4_*` and `synth_*` were encoded by the emulator,
through the baseline exporter where one exists. `build_imports.lua` would
rewrite a string whose retired Assistant data names the exporting character
(reduce that data, which every import drops, to three leaves, replace the name,
encode again); the kept strings needed none. Left out: `hist_2026-07-05`
(portable envelope) and `hist_2026-07-15` (schema-600 snapshot), same shape and
era as a kept string and both carrying such a greeting, and the March MSUF3
preset (same preset family as the January one).

## Anonymization

`build_corpus.lua` derives every name from the file itself and writes no real
name anywhere (the mapping goes to stdout for the operator only):

- Character keys (`Name-Realm`), as keys or whole values anywhere, become
  `CharNN-RealmMM`; the numbers follow the byte order of the original names, so
  a rebuild is identical. Values that end in a realm of the account count as
  characters too (other players in Priority Frames pins).
- Player GUIDs become `Player-0-000000NN`.
- Profile names become `ProfileNN` wherever the profile store keeps them
  (profiles, archive, bindings, spec maps, new-character default, sync groups,
  the per-profile layout caches). Names the addon itself creates stay:
  `Default`, `None`, `Modern Dark[ n]`, `MSUF Suite Forever[ n]`.
- Character and realm names inside free text become their placeholders.
- Reductions that keep the load path: only the selected profiles (the one
  `MSUF_DB` repeats is always kept, and `MSUF_DB` stays a separate copy of it),
  at most N characters (bound ones first), retired Assistant data and each Suite
  module cut to three leaves (both are only deleted or passed through).

Structure, types, numbers and setting values are unchanged otherwise.

## Regenerating

Golden files change only for a deliberate, reviewed behaviour change. Run the
check first and read the differences; then:

    lua tools/profile_corpus_golden.lua <repo root> all --write

`--entry <id>` rewrites one entry (the factory entry first: the others read its
Default). The writer refuses while a run shows a round-trip difference no rule
names or an error no `Corpus.HARNESS_ERRORS` row allows. Commit the golden diff
with the change that caused it and say why each changed line is intended.

Adding or rebuilding inputs (Lua 5.1, repository root as the first argument):

    lua tools/fixtures/profiles/build_corpus.lua <repo root> <entry id> <copy of the SavedVariables file>
    lua tools/fixtures/profiles/build_imports.lua <repo root>

Both are deterministic: the same source gives byte-identical output. New
entries also need a row in `corpus.lua`, a selection in `build_corpus.lua` and
a line in the lists above.

## What the baseline shows

Historical 6.50 baseline findings (a97896f5), followed by the current migration
contract. The original inputs remain immutable.

- Export then import is not identical. Besides the documented opt-ins (Blizzard
  Edit Mode layout, Suite modules) and the screen reference stamp, the import
  adds keys the stored profile lacks (`filledOnImport`):
  - Profiles stamped with defaults revision 17 before newer defaults were added
    under the same revision take the persisted fast path and never get them:
    `portraitDragon*`, `portraitFlip`, `portraitInnerShadow`,
    `portraitBlizzardDirection` on unit frames, `general.gcdBarCombatOnly`,
    `gcdBarIdle`, `gcdBarOpacity`, `general.kickReadyTimeMarker`, the arena
    `trinket*` keys; on Forever also the pet happiness keys and the one-time
    `_msufForeverMutedHealth_v1` migration. A revision bump would repair them.
  - The export's group frame normalization writes
    `gf_*.auras.buff.trackedStrata = "AUTO"` into the string; the stored profile
    never has it, fresh installs included (Mainline, Vanilla, TBC, Mists; the
    Forever factory profile carries it).
- The unit frame config rescales stored offsets when a profile carries another
  `screenPositionHeight` (`AdaptScreenPosition`, a write into the profile): the
  Forever factory string, stamped at 1440, comes out of an import on Mainline,
  TBC and Mists rescaled to the 1080 harness screen. Whether that frame step
  gets so far depends on the harness (on Forever it does not), so these values
  follow the fake client's frame path.
- A new or reset profile lacks `bars.classPowerSyncPlayerPowerOOC`, which the
  first-login Default has: the class power config writes it lazily on the
  login path, and the runtime apply after a profile change does not.
- Pre-6 files: every profile is archived unchanged (`ignoredPre6Profiles`), the
  logging-in character gets a new `Default` identical to a fresh install, every
  other character loses its binding, FirstLoad records an upgrade and shows the
  welcome scene.
- A character bound to a missing profile resolves to that name, and its next
  login creates the profile as a copy of `Default`, or of the alphabetically
  first profile when there is no Default (`"Modern Dark <- Profile01"` in
  `sv_retail_rev16_17`). A `defaultProfileForNewChars` naming a missing profile
  sends new characters to `Default`, created the same way.
- Genuine factory strings shipped between 2026-08-01 and 2026-08-06 (native
  section schema 1) are refused as "MSUF 6.x profile required (schema 600)", as
  is any 5.x profile string; 5.x-era portable strings (schema 1 without a
  native section) still import.
- A current-revision profile keeps every stored value at login; on Forever a
  Retail-authored one gains the Forever-only group threat text keys. Binding
  the login profile again gives the same settings (`rebindChangedPaths = 0`
  everywhere).

## State schema 700

The ordered ledger in `State/MSUF_Defaults.lua` records `_msufStateSchema = 700`
after factory seeding, while keeping schema-600 storage and native exports for
downgrade compatibility. Newly missing revision-17 fields now store their existing
runtime fallbacks; explicit values are preserved. Tracked buff strata now store
the existing inherited value (legacy frame strata, spell-indicator strata or AUTO).
The August beta native full snapshot is accepted after profile shape and generic
value validation; invalid beta data is refused transactionally. Other historical
refusals are unchanged. The relevant `filledOnImport` exceptions remain guards
for historical holes outside this narrow migration scope; this change does not
accept any new round-trip exception.

The migration package compares the complete effective output of all 31 cases with
its immutable parent before writing goldens. Every changed path, including the
new beta profile and sorted-pool shift, is listed with before/after and justification
in the package's local `.checks/golden-path-changes.md`. Its audit refuses any
changed pre-existing setting or unclassified delta. The 6.50 downgrade proof uses
the frozen source and serialized scratch fixtures, with cold-load controls; it
never writes real SavedVariables.
