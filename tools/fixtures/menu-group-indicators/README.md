Immutable whole-page observation hashes from the pre-schema builders at 76eb2c69.
The executable replay covers both pages and supported group scopes, real input,
Undo/Redo, early combat refusal, tooltip show/hide, reset/copy, and every actual
status/spec choice. Widths: 720/1040; profiles: factory, sparse/general, false/zero.
Hash equality is offline behavior evidence, not live rendering or taint proof.

The full replay is registered only in the nightly tier. Its five-client 2-width /
3-profile matrix took 3,260 seconds at Jobs 1 in the 17 October lead review.
Normal push/focused runs use `-SkipTier nightly` and the existing typed input,
DB/apply/refresh, history/combat and section-inventory smokes. Full/nightly gates
retain every original case and digest. Do not recapture fixtures to shorten the test.
