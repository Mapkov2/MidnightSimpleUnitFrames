# Shared runtime rules for menu previews

The core owns visual rules. Options adapts plain settings, sample identity and
resolved dimensions to those rules while retaining its own frames, handles,
selection chrome, layers, animation and combat lifecycle. No mock surface joins
the live unit registry or subscribes to unit events.

| Owner | Shared interface | Preview inputs |
| --- | --- | --- |
| `UF.elements.Portrait` | `PaintBorder`, `PaintBlizzardBorder`, `PaintMask`, `RingInflation` | Holder, compiled portrait fields, resolved width/height and scaled border thickness; class/reaction colours still use `BorderColor` |
| `UFVisuals` | `PORTRAIT_MASKS`, `PORTRAIT_SOFT_EDGE_MASKS`, `PORTRAIT_RING_ART`, `PORTRAIT_RING_ROTATION` | The same tables used by the live portrait painter |
| `ClassPowerColors` | `ResolveSlotColor`, `ResolveFullColor`, `OverrideRGB`, ramp tables | Optional final config argument with slot modes, legacy combo mode, overrides and full-colour enables |
| `UF.Config` | `DarkTint`, `ResolveDarkColor`, `ResolveBarBackgroundColorMode`, `ClassColor` | Plain configuration and explicit class token; portrait border colours keep their separate stock-colour rule |
| `UF.elements.Health` | `LayoutBackgroundFill` | Background bar, foreground bar, owner, missing/full, orientation, reverse and optional name-bar inset |
| `Castbars.Visuals` | `DetailNum`, `DetailString`, visibility rules, `ApplyIconZoom`, `AnchorText`, `PaintIconBorder` | Plain settings; optional text scaling; an already scaled pixel edge and preview-owned visibility for a border drawn on its icon host |

The live colour resolvers retain their cached-controller calling convention.
Previews reuse a scratch config and translate a default slot result of nil into
their base colour. They do not replace the controller's config or colour caches.
The portrait adapters reuse per-holder inputs and preserve existing preview region
aliases. Hiding a shared region goes through the same painter so its cached
visibility remains valid when the portrait is enabled again.
The unit preview owns its straight-edge host visibility and constructs edges
only for a visible square solid border. Shaped, relief, stock and disabled
borders can pass an empty edge table to the runtime painter. Explicit
stock portrait dimensions take priority over the mock frame's queried size.
New relief and stock ring/corner textures are adopted onto the visible portrait
once when their preview aliases are first synchronized. Straight edges keep
their separate host; the runtime's anchors, layers and cached paint state stay
intact. Warm painting performs no parent query or ownership change.

Health geometry is shared independently from value ownership. Live health keeps
its native inverse percentage, secret handling, interpolation and surface masks.
Mocks provide public sample fractions without unit API reads. Castbar padding is
scaled after the runtime resolves the anchor offset, preserving fractional zoom.

The unit/group body renderers, class-resource surface construction, castbar page
layout and preview aura painters remain scene-specific. Their region ownership,
rounding, animation and interactions need scene integration before their larger
render blocks can be deleted safely. Moving those blocks into another helper
would retain their independent rendering rules.

`runtime_preview_shared_rules_smoke.lua` boots the shipped graphs, checks live
and preview call identity, changed shared assets, fixed geometry/colour samples,
hide/restore transitions and mock inputs. Existing portrait, drift, repaint,
profile and per-event budget checks remain unchanged. These checks do not prove
game pixels, anchors, combat/taint behaviour or graphics-driver rendering.
