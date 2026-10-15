# Unit-frame preview requests

`UF.Preview` owns seven independent activation inputs: `editMode`, `all`,
`boss`, `arena`, `bossPage`, `arenaPage`, and `unitPage`. Use the corresponding
named setter; it returns true only when the input changes, including
nil-to-false transitions. Cached forcing is derived from inputs; a currently
inactive family retains its request. Named writers validate secret/type inputs and commit through one owner.
`Bind(key, literal)` resolves a fixed nil/boolean operation once at module load;
that operation accepts no runtime request data. Generic callers still validate
dynamic keys and values. Derived forcing caches start unforced (false; an idle
arena slot holds "prep", so only arena slots read the live arena-prep facts and every
other unit is classified by one table read) without publishing or changing any of
the seven nil inputs. A changed request updates only the
forcing maps that depend on it. Family wrappers skip a setter only when its canonical request already
matches the trusted nil/boolean value; frame cleanup and repaint still run.

The existing public flags retain their exact names and nil/false startup
values. They are compatibility output from this provider. Internal code must
never assign them, read them back into request state, or intercept global
writes. Castbar boot calls `InitializeBoss`, which seeds false only when the
canonical boss request is nil.

The early `MSUF_UF_Preview.xml` prelude loads the existing Secrets owner and the
request provider before Edit Mode. The UF library subsequently reuses the same
UF namespace. Its previous Secrets manifest entry was removed, so every client
loads the provider once. Required consumers validate the complete provider at
load and retain their named setters.

`MSUF_UF_PreviewFamilies.lua` captures a family and its distinct painter once.
Boss keeps NPC color, `??` level, absorb/prediction and target-marker behavior.
Arena keeps deterministic class identity, client level and trinkets. Both use
the same readiness, full/light apply, combat cleanup, range handoff, alpha,
aura, castbar and mover ordering. Applied/cleanup bookkeeping is resolved
lifecycle state, not activation input. The fixed arena slot count is captured
from the sole publisher in `Game/Shared/Initialize.lua` before elements load. Unsupported zero-slot arena graphs retain their forward
trinket and alpha collaborators while avoiding empty frame loops.

LoadConditions owns visibility and the native health curve. Native arena prep
visibility/count are live facts outside the request service. Edit Mode, boss
request and actually forced arena frames retain their distinct health-gate
rules. Existing frame attachment/registry ownership is unchanged.

PreviewAnimation remains in core: HUD and Group Preview consume its animation
API before Options, and Auras3 Edit Mode consumes its builders. Core-only entry
and suspension/resume must not depend on opening Options.

The regression suite boots cold/warm real graphs, exhausts request/visibility
rules, checks strict secret inputs and named dependency errors, and compares
real family sequences/costs against the frozen original LoadConditions fixture.
Whole-operation guards include public and UF exports, Options coordinators,
actual combat/nested dispatch, delayed restore, suspension/reentry, absent and
unsupported slots, native arena prep and identity handoff. Each cost case starts
fresh in both orders and keeps the minimum of two allocation samples. VM,
all native/query calls (including typed guards and secret predicates), and
hook-free allocation execute in separate processes. Edit Mode copies the whole
profile through a cycle map that inserts and deletes table identities, so its
hash capacity, and the bytes it allocates, vary with process addresses even for
identical source. Allocation samples give both graphs one identity-free copy of
that snapshot; the preview and Edit Mode code run unchanged, and the VM and
native samples keep the real copier. The Options history diff keeps the same
kind of visited set, so a heap regression needs both orders of the same case: a
real one allocates the same extra bytes whichever graph runs first, while that
address-dependent noise lands in one order of a pair. VM and native counts stay
strict in every case. Public cleanup controls and Edit Mode transition controls
reject real table, closure, and string allocation mutants. The
compiled fixture shares only immutable bytecode; every execution gets fresh
state and frames. Its offline native AuraContainer absence is counted equally
in both worlds, while all other handler errors fail the test.
The fixture is source from committed `4a4db557`, byte-identical after line-ending
normalization to the complete `8c16d514` parent; it must never be regenerated
from the candidate. Whole-parent comparison passes its separately frozen full
core and Options graph as the old source root, rather than loading only the
old family implementation in the current graph.

The cost smokes run the same Edit Mode code on both sides, so `editmode_preview_frozen_trace_smoke.lua`
compares 33 open, suspend, resume, combat, cancel and page steps per client with the mirrors and frame
state recorded from the parent (`tools/fixtures/preview/EditModeTrace.<Client>.tsv`, never regenerated
from the candidate).

Heap rule: a case fails when the package allocates more bytes than the original
in BOTH orders of the same fresh graph pair (the family parity smoke: in both
measurement rounds). Unchanged identity-keyed visited sets (the snapshot cycle
map in `State/MSUF_ProfileFields.lua`, the Options history diff) add
address-dependent bytes to one order only. VM and native counts have no
tolerance, and no budget was raised.
Offline tests do not establish in-game visuals, secure combat transitions,
taint, or native performance.
