# Unit-frame return-value text contract

Group preview callers keep the signatures of `GF.FormatHealthText`,
`GF.FormatPowerText`, and `GF.TruncateName`. Their implementation belongs to
`UFText`: the number and percent primitives and return-value mode composition
live in `MSUF_UF_Text_Format.lua`; shared ratio/deficit arithmetic and the
actual UTF-8 truncator live in `MSUF_UF_Text_Runtime.lua`. These are internal
namespace fields, with no new global or external-addon contract.

| Internal field | Caller contract |
| --- | --- |
| `UFText.FormatHealthString` | Explicit final `"GROUP"` policy; current, max, delimiter, unit, hide symbol, short, absorb, icon, decimal arguments. GF resolves its reverse map and inherited settings first. |
| `UFText.FormatPowerString` | Explicit final `"GROUP"` policy; current, max, delimiter, unit, hide symbol and resolved short arguments. Absorb-suffixed power modes remain unknown. |
| `UFText.FormatValue` | Existing first three arguments retain engine behavior; optional `"GROUP"` policy preserves the native provider fallback order, nil-to-zero and unbounded public input behavior. |
| `UFText.FormatPercentValue` | Existing first four arguments retain engine behavior; optional `"GROUP"` policy rounds whole percentages, accepts exactly numeric `1` for decimal output, and returns a separate plain availability boolean. Secret percentages use the native round helper. |
| `UFText.PercentFromValues` | The live Runtime ratio owner. GROUP callers normalize nonsecret inputs with `tonumber(value) or 0` and pass final `"GROUP"` to retain unbounded/nonfinite preview arithmetic. Engine calls keep the finite fast guard. |
| `UFText.MissingHealthFromValues` | The live Runtime deficit owner. GROUP has the same normalized numeric boundary and retains nonfinite subtraction; finite deficits clamp at zero. GF still reads native unit missing health before arithmetic; Runtime retains arithmetic-first priority. |
| `UFText.TruncateName` | Name, maximum characters, plain boolean show dots, clip side. Rounds the cap half upward, counts UTF-8 characters, and passes secret names through before inspecting them. Runtime and GF call the same implementation. |

GROUP deliberately keeps unknown aliases as current-value output, `FULLVALUE`
following the short-number option, missing-percent combinations falling back
to current only, the group default delimiter `" / "`, and the existing absorb
prefix/icon/native zero-suppression behavior. GF option caches still invalidate
at the existing general/profile apply boundary. NumberFormat remains the sole
owner of GAME/COMPACT options.

Group DB text resolves the existing public `MSUF_NS` owner through
`MSUF.Require(name, file)`, then validates its `UFText` table and all seven
required scalar/format/name/math fields at load. Missing fields raise with their
`UFText.<field>` name and the consumer path. Every client loads Text Format and
Runtime before Group DB text. Format's forward math dependencies resolve at
use after Runtime has published the actual owners; no global UFText is created.
Narrow group, factory-profile and catalog fixtures share `group_text_fixture.lua`
to load the complete real provider graph instead of placeholder UFText fields. `group_text_required_helpers_smoke.lua` checks all five real
client load orders and named table/field omissions;
`group_text_math_owner_smoke.lua` checks Runtime closure identities, GF owner
calls, retained native priority and baseline instruction ceilings on rejected
inputs. The shared owners inline the same finite guards so the GROUP policy
adds no work to ordinary engine calls.

`UFText.SetModeText` and compiled live text writers continue to paint native
FontStrings. Return-value callers never emulate a FontString to capture secret
formatted arguments. Secret results remain opaque, and availability is carried
by plain flags; there is no per-event table or closure allocation.

The behavior smoke `group_text_return_contract_smoke.lua` covers these deliberate
differences and strict secret/name guards. `group_text_secret_percent_smoke.lua`
keeps every original output and guard expectation, with source-order pins moved
to their engine owner. `group_text_format_cache_apply_smoke.lua` is unchanged.
Offline provider and budget checks establish source/runtime contracts, not live
WoW rendering, native abbreviation implementation, combat or taint evidence.

The source pins in `uf_elements_quality_contracts_smoke.lua` and
`secret_guard_order_smoke.lua` follow the renamed scalar truncator. Their
UTF-8, closure-allocation and zero-predicate/secret-pass-through expectations
are unchanged. Runtime name updates retain the original nil-runtime path.
