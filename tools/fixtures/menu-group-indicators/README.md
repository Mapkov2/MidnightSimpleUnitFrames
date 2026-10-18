Whole-page observation hashes from the pre-schema builders at 76eb2c69.
The executable replay covers both pages and supported group scopes, real input,
Undo/Redo, early combat refusal, tooltip show/hide, reset/copy, and every actual
status/spec choice. Widths: 720/1040; profiles: factory, sparse/general, false/zero.
Hash equality is offline behavior evidence, not live rendering or taint proof.

Widget creation ordinals are process-local identities: unrelated preview frame
creation can shift them without changing any observed structure. Before hashing
and counting each case, observation_receipt in the parity smoke replaces every
widget:<digits> token with widget:1, widget:2, ... in first-appearance order.
The identity map resets per case. Repeated references keep the same identity;
every row and every other field remains in the SHA-256 input, in original order.
The existing CRLF-to-LF normalization remains unchanged.

Canonical fixture regeneration (18 October 2026):
- Original source: C:/tmp/m7/w-gi76eb at
  76eb2c69ba22d15201df07eb863241666ed69b63; baseline metadata stays at this commit.
- Scratch source: C:/tmp/m7/giparity-baseline-76eb, copied from that worktree's
  tracked files. No product files were edited in either baseline tree.
- Added only tools/tests/menu_group_indicators_parity_world.lua from the current
  tree (SHA-256 c8cf288795672ddec9ab24d732724b8dd1965a90e4d02b56212e02399a9ab4f1).
  Its menu_core_world.lua, client_world.lua, client_manifest.lua and
  runtime_media_fixture.lua helpers already existed and matched current bytes.
- For each Mainline/Vanilla/TBC/Mists/Forever x 720/1040 x default/general/edge,
  ran Lua 5.1 at C:/Users/Marco/AppData/Local/Temp/msuf-lua51/portable/lua.exe,
  with arguments <scratch>/tools/tests/menu_group_indicators_parity_world.lua
  <scratch> <client> <width> <state>, and working directory <scratch>.
- Passed each complete stdout stream to observation_receipt, with a fresh map,
  and stored its sha256 and rows. The raw ordinals were also hashed
  before canonicalisation to check against every original fixture receipt.
- All 30 raw hashes and row counts matched the prior fixture before writing
  canonical hashes; the baseline metadata and all 2,256,156 rows are unchanged.
- Runs use the shared Lua slot, sequentially, at BelowNormal priority.

The full replay is registered only in the nightly tier. Its five-client 2-width /
3-profile matrix took 3,260 seconds at Jobs 1 in the 17 October lead review.
Normal push/focused runs use `-SkipTier nightly` and the existing typed input,
DB/apply/refresh, history/combat and section-inventory smokes. Full/nightly gates
retain every original case and row. Do not recapture fixtures to shorten the test.
