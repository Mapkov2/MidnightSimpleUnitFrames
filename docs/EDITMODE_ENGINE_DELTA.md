# Edit Mode engine corrections

The shared drag driver dispatches each owner through the client's
`secureexecuterange`. An exception reaches the native error handler and the
remaining owners still run. The non-client fixture fallback uses the existing
host boundary. Subscription copies and tombstones retain the original running
tick's order; removal, replacement, clear and reentry do not revive old records.
Visible ticks retain one visibility read per owner and make no new frame writes.
An invisible owner checks for remaining visible owners before parking the driver,
including parent hides that do not deliver an owner OnHide.

Internal EventBus publications carry a revision belonging to that event record.
A nested publication invalidates remaining delivery of the earlier revision.
This prevents an observer receiving closed then stale open, and also handles
recursive close/reopen, observer removal/replacement and raising callbacks.
State still publishes after synchronous lifecycle work and mirror updates. No
apply-depth flag crosses foreign code. Native OnEvent delivery and its single
subscriber fast path are unchanged.

Aura strategies bind the existing aura engine's BeginAuraGroupDrag and
EndAuraGroupDrag. Apply uses the real group's hosted drag callback; popup and
history retain aura lane/unit ownership. Gameplay keeps its existing native
StartMoving engine, centered-offset conversion and history helpers. Strategy
commit invokes the real frame's installed OnDragStop, including rounding,
re-anchoring, applied caches, sliders, selection and history completion.
Gameplay has no Edit Mode popup: its existing router dispatch remains harmless,
and Options supplies the Gameplay sliders and history when loaded. No provider
method or placeholder drag context was invented to complete the tests.

The engine lifecycle smoke creates actual unit, stacked, castbar, detached Power,
group, aura, group-pet external-provider and gameplay frames through the shipped
graph. It executes begin/apply/commit, popup routing, undo/redo, Cancel All and
combat/regen with Options absent and present. Unit/group/castbar/resource offsets,
GCD/CP selection and rounding contracts remain in their original smokes.

## Held native Gameplay drag teardown

The combat timer and combat-state text register their real native frame at
OnDragStart. Session teardown drains those owners before profile restoration,
clears the drag flag, invalidates the applied position cache, stops native
movement once and cancels the open Gameplay
history transaction. It never persists the held screen rect. OnDragStop consumes
only a still-active drag; a late release after Cancel All, combat or session close
cannot overwrite restored settings, update caches/sliders, or create history.
The existing timer-anchor and combat-state position owners run in the session
restore fanout, synchronously
after Cancel and after the deferred close/combat boundary. This re-anchors
invalidated caches using the restored profile rather than the held screen rect.
This calls the shipped position APIs and does not rebuild Gameplay features,
register unrelated events or acquire a Blizzard TotemFrame.
A normal release still performs the existing rounding, anchor, cache, slider,
selection and history sequence. No ticker, per-tick work or new frame is added.
The native owner set is replaced before teardown, so later session reentry can
register fresh owners independently of the drained set.

The lifecycle smoke calls the shipped frames' installed OnDragStart and
OnDragStop scripts with Options absent/present on all five clients. Held Cancel,
combat, close and subscriber-driven reopen check native start/stop counts,
restored (0, -200), late release at (63, -27), history counts, cache/anchor state,
slider calls, the native stop leaving the held rect anchored, and a fresh reopened drag's exact commit/undo/redo behavior. The
previous strategy lifecycle assertions remain intact. This corrects the earlier
claim of complete Gameplay cancellation coverage: that probe committed before
teardown and did not exercise a held native drag.

## Allocation measurement

Skipping the second collection retained workload strings and missed temporary
and repeated-string allocations. Both samples again fully collect, then measure
with the original collector-stop/count/restart sequence, unchanged limits and
minimum-of-two policy. There is no cost subtraction or workload string warmup.

The capacity fixture is 192 persistent false values passed as unrelated live
arguments to the sampler. It reserves VM stack space before collection; it
contains no strings, tables per sample, closures per tick or workload data.
Lua 5.1 collection can shrink the running stack based on its live argument area;
its previous load-graph high-water mark otherwise moves stack regrowth into a
sample. Retaining 1,024 through 16,384 unrelated strings did not fix the original
10.6 KB failure, so this correction does not claim string-table regrowth caused
that particular failure. A separate heap-object-free numeric recursion probe
also demonstrates collected VM stack regrowth independently of addon allocations.
An archive was hash-checked against 1,716 pinned package product files after
CRLF normalization; its original sampler passed at 7.7 KB. The initial worktree
original sampler failed at 10.6 KB. The independent review also reproduced that
difference between identical checkouts. No production allocation optimization
was inferred from this capacity difference.

The execution controls inject allocations immediately before the KB reading,
as in the independent review, and check BOTH collected samples individually.
Before correction: production 10.41/6.56 KB falsely passed; temporary strings
21.61/6.56 KB and repeated strings 22.34/6.56 KB also falsely passed.
After correction: production 7.65/7.66 KB; tables 15.65/15.66 KB; temporary
strings 18.84/18.89 KB; unique and repeated strings 19.57/19.58 KB.
All four mutants fail the unchanged 8 KB assertion in both samples. The numbers
are 32-bit Lua 5.1 fixture measurements, not a live WoW allocation measurement.

## Live verification still required

Check drag, click/popup, typed coordinates, scale, snap, undo/redo and Cancel All
for every supported kind/client, both resolutions and UI scales. Check combat
entry, deferred restore, keyboard/nudge release, Ellesmere opt-out/suspend/resume,
SaveLayouts round trips and staged Micro Menu settings. Offline execution does
not establish live rendering, native client performance, combat taint or input
behavior. Profile corpus and parity goldens must remain byte-identical.

## Combined namespace boot

The shared castbar key schema loads before the castbar public API. Publication
must reuse its namespace, preserving UNIT_CASTBAR identity while initializing
the runtime providers. Replacing the namespace erased the schema and stopped
CastbarPreviews at boot. The full-graph schema regression fails before this
correction and passes on all five clients, with real Config and Frames owners.

## Suspended and reentered Gameplay owners

External preview suspension now stops the shared ticker before invoking the
shipped Ellesmere suspension bridge. Its existing kind cleanup drains both
native Gameplay owners, cancels their held history transaction, invalidates
the applied position caches and makes a late native release inert. Suspension
keeps the active session, provider and snapshot; resume applies the current
profile's anchors only after the configuration combat lock allows it. Existing
resume generation guards still reject work queued for a replaced session.

Opening a new session reconciles Gameplay anchors before taking its snapshot.
A synchronous EDITMODE_STATE subscriber can Close and Open before the old
exit timer runs; that new generation deliberately invalidates the old timer.
The new entry therefore owns reconciliation, reading current settings rather
than carrying old profile coordinates into the replacement session. Normal
Close/Cancel and successful release retain their history behavior.

The real-engine regression holds actual timer and combat-state OnDragStart
callbacks across Close, Cancel, nested subscriber reopen, combat, manual and
combat suspension, opt-out and profile replacement. Replacement goes through
ProfileRuntime.BeforeMutation and binds the replacement into profile storage;
the old identity is rejected. Tests check native stop counts, late releases,
caches, visible anchors, sliders, exact history counts and a fresh successful
drag on every client with Options absent and present.

On the frozen pre-fix ready source, the isolated Close/reopen control reports
20 cache and 20 native-anchor failures (two owners, five clients, both Options
states). The combat-suspension control reports 20 moving owners and 20 late
coordinate overwrites. The production fixes preserve the assertions; only
additional lifecycle scenarios and current-profile expected values were added.
The native EventBus instruction counts also match base 3216587d exactly for
one, two, three and eight subscribers on both global and unit events.

## Partial castbar fixture publication

The public namespace must retain the shared UNIT_CASTBAR schema at real boot.
Its publication also initializes new submodule tables. The partial fixture's
old `existing = ns.Castbars` alias consequently saw the new empty modules and
could not restore its original inputs, including Driver.ShowState. The fixture
now snapshots module references before publication, then restores those same
references. It adds no runtime provider, fallback or private Config call.
The original arena position/stamp assertions and fixture inputs stay intact:
the unchanged arena quality contract fails with missing ShowState before the
snapshot correction and passes all five contracts afterwards. The separate
real-graph namespace/schema red control and five-client boot regression remain.

The first combined full gate also exposed 15 incomplete profile-fixture cases
(6.0-only policy, cross-flavor import and transactional import). The shared
schema makes Castbars exist before those partial fixtures load a runtime owner;
profile mutation therefore reached a missing Config. Those three fixtures now
load the real PublicAPI, Backend and Config providers in their setup, with no
replacement Config method and no production guard. All existing import, profile
identity, codec, rollback and position assertions remain unchanged.
