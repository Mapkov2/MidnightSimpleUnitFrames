# Custom aura alias catalog

`MSUF_Auras3_AuraAliases.lua` replaces the live spell-name resolver. Custom
configuration expands each selected action/talent ID to all IDs with the same
nonempty, case-sensitive localized SpellName. Blizzard's native candidate filters
then select auras. This preserves action-ID convenience without reading aura
payloads, calling `GetAuraDataBySpellName`, catching restricted-read errors, or
subscribing an extra MSUF owner to `UNIT_AURA`/`OnUpdate`.

Original IDs and curated cross-name aliases remain valid. Aliases supplement the
native membership hash; they do not create extra custom-priority groups, reminder
placeholders, self-castability checks or click bindings. Target DoT eligibility is
applied before expansion. Disabled containers do no alias work, and curated
defensive defaults are not automatically broadened to all same-name IDs.

## Native contract

Checked against local `wow-ui-source` branch `upstream/live`, commit
`8ea15b61e45c0ed4eba01439c90757f86eb78d34`. `AuraContainerUtil` compares
`includeSpellIDs[auraData.spellId]`; `Blizzard_CustomAuraContainer.lua` exposes
ID-based candidates and no equivalent spell-name filter. `UnitAuraDocumentation`
marks `GetAuraDataBySpellName` as requiring a non-secret aura. The new path never
calls that API or bypasses native identity/secret restrictions.

## Representation and cost

The generated `AliasData` directory contains IDs only. Groups that are exactly
equal in all eleven locales share one blob; each locale adds its own groups.
Only Common plus the active locale's strings survive loading. `enGB` selects
`enUS`; `ptPT` selects `ptBR`. There is no cross-language alias union.

IDs are fixed-width base36 tokens with a unique prefix; newlines delimit groups.
The first request for a configured ID uses native C `string.find` over these
compact strings, then decodes only that group. Hits and misses are memoized;
same-name IDs share the decoded group. Explicit cross-name aliases merge into
a private table. This trades a small, bounded cold search for avoiding hundreds
of thousands of permanent Lua reverse-index entries. The catalog owns no frame,
event handler, timer, aura callback or configuration refresh.

Generated data is larger on disk than the removed resolver. The selected locale
uses approximately 1.4 MB of raw strings, plus tables for actually used groups.
All eleven locales occupy about 11.2 MB of Lua source. Startup parsing and first
configuration are real costs; eliminating event-driven alias work does not mean
all aura rendering or all addon CPU costs disappear.

## Provenance and update boundary

`.github/auras3-alias-catalog.json` records CSV/DB2/generated-source SHA-256 hashes,
row/group counts and locale hotfix status. Current data targets Retail
**12.1.0.69587**, SpellName FileDataID **1990283**:

* Build config: `c9fa1a64b0170829cc5c5c98c71025c3`.
* CDN config: `3aa83893a3ce9b722a5f51328ad9a552`.
* Eleven base locale exports contain 413,875 records each.
* The available same-build enUS DBCache snapshot adds ten IDs (413,885 total).
  Other locales have base-build data; no translations of enUS hotfix names are
  invented. Hotfix caches are locale-specific and can be incomplete.

This is a versioned data contract, not runtime discovery. An unknown/new ID
still selects its exact native spell ID and any explicit curated aliases.
New or renamed aliases introduced by a later patch or server hotfix require
regenerating the relevant catalog. Neither unchanged client build numbers nor
the current local cache prove that every future server hotfix is represented.
Do not claim timeless equivalence to live name discovery or silently reuse a
different client branch's data. Update and validate this catalog with Retail
client data before distributing it for another client build.

## Reproduce

Use upstream [TACTSharp](https://github.com/wowdev/TACTSharp) to extract the
pinned SpellName DB2 for each locale, [DBC2CSV](https://github.com/Marlamin/DBC2CSV)
to decode it, and [WoWDBDefs](https://github.com/wowdev/WoWDBDefs) for SpellName's
schema. These are local developer tools and are not shipped with the addon.
Extraction reads game files or the corresponding pinned Blizzard CDN hashes;
it never modifies the installation. Keep tools, caches, DB2/CSV exports and
hotfix snapshots under ignored `_local_workflows/`.

The captured tool releases were TACTSharp `0.2.0-alpha1` (Windows x64 ZIP SHA-256
`3bcb6bfd29d5f9a56f9e6ceaa97009894ab0dbba9451bf24ba915226eb27ddd9`)
and DBC2CSV `v1.0.9` (`7ffac6bf624fbbdce64af61695758b7f4e898280775cf32a51eb52a19f8a72b3`).
SpellName.dbd was refreshed from WoWDBDefs before decoding WDC5 data.

```powershell
# Run from the tool's ignored directory; repeat -l/-o for every supported locale.
.\TACTTool.exe -b c9fa1a64b0170829cc5c5c98c71025c3 -c 3aa83893a3ce9b722a5f51328ad9a552 -p wow -r eu -l enUS -d 'E:\World of Warcraft' -m fdid -i 1990283 -o '<exports>\enUS\SpellName.db2'
# DBC2CSV writes SpellName.csv beside the DB2. For a hotfixed view, first copy
# the DB2 into <locale>-hotfix, then pass the same-build locale's DBCache snapshot.
dotnet --roll-forward Major .\DBC2CSV.dll '<exports>\enUS-hotfix\SpellName.db2' '<exports>\DBCache.bin'

# From the repository root:
python .github/scripts/generate_aura_alias_catalog.py --input '<exports>' --output MidnightSimpleUnitFrames/Auras3/AliasData --build 12.1.0.69587 --manifest .github/auras3-alias-catalog.json
python .github/scripts/test_aura_alias_exports.py --exports '<exports>' --lua '<lua51.exe>'
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/run_auras3_refactor_tests.ps1 -LuaCommand '<lua51.exe>'
```

The generator requires every locale, rejects malformed/duplicate/out-of-range
IDs and undersized Retail exports, and checks lossless partition/encoding. No
player-spell heuristic or group-size cap is permitted. The CSV oracle independently
compares every group and member with every original export, then exercises
sampled first/middle/last IDs and the largest groups through the real Lua decoder.

Desktop Lua fixtures verify configuration, native input and lifecycle contracts.
They cannot establish live WoW taint/visual parity or a combat CPU percentage.
Perfy packages and captures remain explicit-only; ordinary source validation
does not create or request one.
