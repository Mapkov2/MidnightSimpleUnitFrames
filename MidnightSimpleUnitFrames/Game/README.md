# MSUF client layout

This directory is the client boundary for MSUF, following ElvUI's layout:
`Game/Shared` plus one folder per Classic client family or flavor.

- `Shared` contains bootstrap code that must behave identically everywhere,
  plus the modules that Classic clients and the Mainline build both load
  (`Shared/UnitFrames/MSUF_UF_PetHappiness.lua` and
  `Shared/UnitFrames/MSUF_UF_ThreatText.lua`: Classic Era, TBC and WoW
  Forever). Such a module checks its `MSUF.Client` fact first and returns at
  once where the client has no such feature.
- `Classic` contains implementations shared by Vanilla, TBC, and Mists.
- `Vanilla`, `TBC`, and `Mists` contain the loader manifests, adapters and data
  selected only by that client's suffixed TOC.
- `Forever` contains what only WoW Forever needs inside the Mainline build: the
  curated aura datasets, the spell name catalog for rank broadening, and the
  character names option (first name, surname or both). Every file returns at
  once on any other client.
- Mainline has no folder here. `MidnightSimpleUnitFrames_Mainline.toc` loads
  the Retail tree plus `Shared` and `Forever`, and never loads `Classic`,
  `Vanilla`, `TBC`, or `Mists`.

Client-only code belongs here instead of adding flavor checks to shared event
or rendering hot paths. Vanilla, TBC, and Mists include implementations from
`Classic`, but they keep separate loader manifests so their contracts can
diverge without copying the backend.

`tools/classic-client-matrix.tsv` maps each client to the branch of the local
Blizzard UI source mirror (`_local_workflows/references/wow-ui-source`) that
its contracts are checked against:

- `upstream/classic_era`: Vanilla (Classic Era)
- `upstream/classic_anniversary`: TBC Classic
- `upstream/classic`: Mists Classic
- `upstream/live`: Mainline

The ptr branches (`upstream/ptr`, `upstream/ptr2`, `upstream/classic_ptr`,
`upstream/classic_era_ptr`) are drift sentinels only. The source audit checks
their aura API contracts when they exist; no client is packaged from them.

Warning: `Blizzard_APIDocumentationGenerated` is nearly identical across the
Classic branches, so it proves nothing about whether one flavor has an API.
Look for a call site in a file that the flavor's TOC actually loads, checking
its `AllowLoadGameType` tags the way `tools/audit-classic-ui-source.ps1` does,
or follow the client gates ElvUI applies.

Game modes (`MSUF.Client.GameMode`, such as Standard or Plunderstorm) get no
folder here. A Mainline game mode shares the Mainline build, and a folder is
only warranted once its data really diverges. WoW Forever is that case: it
runs the Mainline build with a Classic Era spell database, so its aura data
lives in `Forever` while its code stays in the Retail tree. Code branches on
`MSUF.Client` facts and capabilities, never on client names.
