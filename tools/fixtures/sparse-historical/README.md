# Historical sparse wire oracle

Captured once from commit `ce4767d344bdafc01685ef5299bca2e26735539d`.
`provenance.json` pins the commit/tree, all six historical Lua inputs and output.
The source was extracted with `git -c core.autocrlf=false archive` into the ignored
`dist/historical/sparse-ce4767d34` cache; every input blob was verified with Git.

Capture command, inside the shared Lua slot:

```
lua5.1 tools/fixtures/sparse-historical/generate.lua dist/historical/sparse-ce4767d34 tools/fixtures/sparse-historical/profiles.lua
```

`generate.lua` is a capture tool, never a test-time generator. Do not regenerate
this oracle from current code. It builds masks from the historical wire layout,
then calls the actual historical decoder and freezes both encoded and decoded
profiles. There are 581 single-bit cases (each owner's first and last position)
and 25 binary mixed masks (12 V2, 13 V3), giving every one of the 3595 V2
and 6622 V3 positions a unique nonzero selection signature. This detects
swaps even between interior slots that share the same residue.

The current test compares whole profiles, including absence, explicit false,
zero, empty strings, list keys and unknown data. V2 paths and values are frozen.
V3 bit-to-path identities are frozen; V3 inherited default values may evolve.
Current V3 values are looked up by the frozen physical path, never bit position.
The mutation modes reject V2/V3 path swaps; the default-change mode remains green.
