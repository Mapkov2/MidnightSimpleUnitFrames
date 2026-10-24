# Compact release check

Run from this checkout with Windows PowerShell:

    powershell -NoProfile -File tools/release-check.ps1

The runner calls the PLAN-10 fast check and then acquires the shared Lua slot
for the behaviour contracts. It logs all child output, prints one result per
contract, and returns nonzero for a failing contract or a combined slot time of
300 seconds or more. Queue wait time is printed separately as elapsed time
(the existing fast check includes its own queue wait in its reported duration,
so the combined slot figure is conservative when that queue is occupied).

| Contract | Clients and observations |
| --- | --- |
| Generated lists | Static Python check of module-manifest.json: exact TOC/XML bytes, ordered client graph, exclusions, retained files, reviewed API lists and English-derived translation stubs. Fails before acquiring a Lua slot. |
| Profiles | Entire SavedVariables corpus on Mainline and Vanilla; sparse save/restore and reload against a full control. CRUD, active table identity, native spec event and combat deferral on Mainline/Mists, talent groups on Forever, and no spec on Vanilla. Fast check supplies all-client sparse transfer. |
| Apply | Mainline and Vanilla: schema-bound setters, real dispatcher, native unit/group health, power, castbar, aura config, fonts and colors; border test activation/retirement; history restores painted state. |
| Menu | All matrix clients plus Forever: shipped core/Options graph, every registered page and its lazy sections, existing schema projection capture, a real search query and exact visible target navigation. |
| Namespace | Whole addon trees: bytecode bare globals plus literal global table reads/providers; six documented legacy read occurrences only. Synthetic red/green probes cover providers, aliases, raw reads, strings, extra occurrences and compiler failure. |
| Group preview | Mainline/Vanilla/Forever: existing scene lifecycle plus engine element ownership, supported party/raid/mythic scenes, combat suspension/recovery, retained frame visibility after close, independent owner isolation. Existing combat restore smoke checks live secure headers. |
| Edit Mode | Mainline/Vanilla: real engine unit/group frames, unlock, strategy move, nudge, native point and profile restoration on undo, lock; existing core history smoke also checks late Options loading. |

Tests do not pin addon source text or rewrite shipped code. The namespace audit
is deliberately static. Literal providers and the generated keep policy are a
cross-file contract, not proof that a provider exists on every runtime path;
real graph boot and behaviour tests supply that separate check.

The offline client models native frames/APIs. Results do not establish live
WoW appearance, combat taint, controller behaviour or measured CPU performance.
Local dependencies (fast-check, slot, interpreters and log directory) are
explicit runner parameters. No publication, install or git write is performed.
