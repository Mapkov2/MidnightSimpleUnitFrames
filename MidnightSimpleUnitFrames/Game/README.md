# MSUF client layout

This directory is the client boundary for MSUF, following ElvUI's
`Game/Shared`, `Game/Mainline`, `Game/Mists`, `Game/TBC` layout.

- `Shared` contains bootstrap code that must behave identically everywhere.
- `Classic` contains implementations shared by more than one Classic client.
- `Mainline`, `Mists`, and `TBC` contain the loader and adapters selected only
  by that client's suffixed TOC.

Client-only code belongs here instead of adding flavor checks to shared event
or rendering hot paths. Mists and TBC may include an implementation from
`Classic`, but they keep separate loader manifests so their contracts can
diverge without copying the backend.

The local Blizzard UI source branches used for these contracts are:

- `upstream/ptr`: Mainline 12.1
- `upstream/classic`: Mists Classic
- `upstream/classic_anniversary`: TBC Classic
