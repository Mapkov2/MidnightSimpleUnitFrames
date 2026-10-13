# MSUF codebase history

Dated facts about how this repository reached its current shape. This file
records what happened; it gives no instructions. The current state and the
rules that apply today are in `CLASSIC_PROTOTYPE.md` and in the local agent
procedure.

## Two repositories until 2026-10-13

Until the cutover MSUF lived in two repositories. The Retail repository (branch
`main`, the 6.x line) was the source of Retail changes. This repository began as
the Classic repository (branch `classic`), created from Retail `main` commit
`7cf4e711`, and kept itself close to Retail by syncing it in. Each sync commit
named the Retail commit it ported in a `Retail-Source:` trailer; the last one
was `72c50ac4`.

The gate enforced that closeness with ownership manifests:

- `tools/classic-owned-addon-paths.txt` listed the Classic-owned addon files,
  which were free to edit.
- `tools/classic-retail-overrides.tsv` listed reviewed edits of Retail files as
  `path<TAB>Retail base blob`. Every other addon path had to be a byte-identical
  Retail copy, so each edit of a shared file needed a new override row, and
  every row added work to the next sync.
- `tools/classic-owned-shadows.tsv` listed whole-file Classic copies of Retail
  files, with report-only drift. There were fourteen. Thirteen were collapsed
  into small `MSUF.Client`-gated hunks of their Retail-named files on
  2026-09-19 and the last one, the Classic Defaults file, on 2026-09-20.
- `tools/rebase-classic-overrides.py` did the three-way rebase of override rows
  and shadows against a new Retail commit.
- The full gate needed `-RetailReferenceRoot`, a clean Retail clone, and the CI
  full-gate job resolved the Retail commit this tree mirrored.

On 2026-09-15 the owner decided that this repository becomes the single
long-term codebase for every client, with Retail Midnight getting 6.5 from here.

## The cutover, 2026-10-13

This checkout became the sole active MSUF source for all supported clients, on
`main`. The Retail line was retired at
`84a1241710c26d0970436a02beb4e32f3a626f39` and kept as the unpublished backup
labelled `6.22`, now frozen under `C:/MSUF Beta Branch/_repo_backups/6.22`.
Retail-to-Classic mirroring and the release-review automation were retired. The
`classic-v<version>` tag format stayed.

The 6.50 baseline is commit `905ae65c` on top of `880e3611`. The release tags
before it include `classic-v6.5-alpha18` and `classic-v6.5-beta2` (WoW Forever
support).

## The 7.0 repository, 2026-10-13

The 7.0 line is a separate repository (private origin
`Mapkov2/MidnightSimpleUnitFrames-7.0`, branch `main`), copied byte for byte
from the prepared 6.50 tree; `a97896f5` configured it. `VERSION` stayed 6.50.
The foundation passed the full gate before the copy.

Gate changes since then:

- `a745186c` made `tools/quality_ratchet.py` the only authority for Lua's
  compiler limits. The gate's own block (fail above 190 locals per function, 230 main-chunk slots or 56 upvalues, with four named exceptions) was removed.
- `8c62f17e` removed the ownership, override and shadow manifests, the Retail
  source resolver, the rebase tool and every Retail-reference gate step, and
  added the generated `tools/load-graph.lock`. The four parity smokes now
  compare with golden files recorded from the retired Retail commit. The
  `-RetailReferenceRoot` parameter is still accepted and ignored; the gate
  prints a `DEPRECATED` line. A self-contained run used to print three
  `SKIPPED:` lines (the UI source audit and two Retail comparison steps); it now
  prints one. A gate run took about 40 seconds in the mirror era; it takes
  minutes now.
- `4b2bd51f` gave the wave-1 bug fixes one bounded raise of the startup source
  tripwire.

## Other changes that shaped the code

- 2026-09-16 to 2026-09-18: WoW Forever support (marker detection, interface
  16001, no arena, Party and Raid frames only, pet happiness). Build numbers
  seen: 69876 (mirror), 69913 (verified in game), 70009 (data validation
  2026-09-25), 70170 (declares `WOW_PROJECT_CAMELOT`).
- 2026-09-18: two Forever profile-persistence workarounds were reverted after
  they split `MSUF_DB` and `profiles[active]` into two tables and caused two
  reproduced data-loss bugs (another character's profile overwritten at login,
  edits lost on a profile switch). The missing persistence on the Forever beta
  was a Blizzard bug that affected every addon.
- 2026-09-19: the gate became table-driven (`tools/classic-gate-smokes.tsv`),
  gained `tools/run-classic-gate.ps1` and collect-all failures, and the client
  model lost its dead aliases.
- 2026-10-01 to 2026-10-03: the quality program (waves 1 to 4) added the ratchet,
  the feature inventory and the require/optional dependency rules.
- 2026-10-09: one version number on every client from 6.50 on.
- The in-game Assistant addon was retired in 6.5; `tools/classic-addon-tombstones.txt`
  keeps it from returning.
