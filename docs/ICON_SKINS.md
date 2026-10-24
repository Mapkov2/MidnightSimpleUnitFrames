# Icon skin runtime contracts

Detailed contracts retained from the core painter. The runtime keeps concise references to this document.

## Contract 1

```lua
-- Aura icon skins: layered icon looks (shadow bands, vignettes, frames, metal,
-- rings, gloss) drawn from static textures on the icon owner. Both aura
-- backends reach the painter through A3.ApplyIconStylePreview once a runtime
-- compile produced a skin; every aura preview through A3.ApplyIconStyleSkinned.
--
-- Cold path only. A skin is painted when a button is created (the native
-- initializeFrame, which also runs in combat when a pool grows) and when a
-- preview repaints. It registers no events, hooks, timers or scripts, and no
-- aura update ever reaches it: the regions it creates are static, so a skin
-- looks the same in and out of combat.
--
-- One default skin and look (shared.iconSkinDefault, edited on the Icon Skins
-- page) applies to every product whose appearance table keeps styleSkin at
-- DEFAULT; a product may instead name its own skin or CUSTOM (no skin: the
-- user's border and shadow). Combat parity: see the combat snapshot below.
```

## Contract 2

```lua
--- Adds the compiled skin to an icon style built by a backend from `source`
--- (the product's appearance table) and `defaults` (shared.iconSkinDefault):
--- the product's skin, or the default's for DEFAULT, drawn with the default's
--- look. CUSTOM leaves the style and its signature byte-identical, so profiles
--- without a skin never rebuild a container. styleSkinColor's alpha always
--- scales the skin; its colour replaces the skin's own colours only with
--- styleSkinColorOverride. Menu, gallery and Edit Mode previews compile here
--- and paint with A3.ApplyIconStyleSkinned.
```

## Contract 3

```lua
--- Paints the style's skin on `owner`, the frame the icon fills: `width` (or
--- `size`) wide and `height` tall. A caller that sized `owner` first (the
--- Classic layout) passes no height, and the owner's own size is read. A skin
--- draws only on the icon shape it was made for and only while its lane shows
--- the icon. Returns owned, unchanged:
---   owned     true when a skin now draws the look (the caller hides its own
---             border and shadow), false for no skin or another icon shape;
---   unchanged true when nothing was written because `owner` already shows
---             exactly this (callers that repaint on updates skip all work).
```

## Contract 4

```lua
--- How far a skin's frame reaches past an icon `width` x `height` (height
--- defaults to width) on each side, in pixels: what something lined up with a
--- row of skinned icons has to clear, such as a resource bar matched to a
--- cooldown row's width. Soft shadows are not part of the frame. `skin` is an
--- id, a definition or a compiled skin. The rounding is the painters', so the
--- result lands on their pixels. Returns x, y (0, 0 for no skin).
```

## Optional external icon anchor

```lua
--- Paints the style's skin on `owner`, the frame the icon fills: `width` (or
--- `size`) wide and `height` tall. A caller that sized `owner` first (the
--- Classic layout) passes no height, and the owner's own size is read. A skin
--- draws only on the icon shape it was made for and only while its lane shows
--- the icon. `anchor` (optional) is the region the icon fills when that is not
--- `owner` itself: an icon texture or a region placed like it. The layers stay
--- textures of `owner` and are laid out around `anchor`, so an icon that sits
--- inside a wider owner (a bar row, a bordered slot) keeps its owner's draw
--- order. Returns owned, unchanged:
---   owned     true when a skin now draws the look (the caller hides its own
---             border and shadow), false for no skin or another icon shape;
---   unchanged true when nothing was written because `owner` already shows
---             exactly this (callers that repaint on updates skip all work).
```

### Client scope of shape search rows

The shared static search catalog is a client union. Icon Skins castbar shape rows follow the focus, boss and arena scopes; the Focus interrupt tracker follows focus and the PvP trinket follows arena. Their runtime control identity and section must remain the same as their static exact target.

The adjacent query capability rows continue to cover the unit Threat % Color by threat toggles and the three Threat colors on Colors > Status Text Colors, Group Frames > Status & Indicators Color by threat, and the dark Background plate on the unit and group cards.

## External host interface

```lua
-- Icon skins for painters outside MSUF's aura runtime: the interface
-- MSUF_HostAPI.GetIconSkins() hands out (version 1). The MSUF Suite draws
-- MSUF's skins on its cooldown manager and action bar icons with it; the
-- contract is the 2026-10-17 icon skin addendum of HOST_API_SPEC.md.
--
--   Compile(choice, shape) -> look | nil
--       choice: "DEFAULT" (or nil) for the default skin of the Icon Skins page,
--       "CUSTOM" for no skin, or a skin id. shape: the icon shape the caller
--       draws ("RECTANGLE" when nil, or "CIRCLE" for an icon it masks round).
--       Reads the default the aura runtime compiles from
--       (Skins.CommittedDefault): a default edited in combat reaches these
--       icons when it reaches MSUF's auras, at combat end. nil when no skin
--       draws: CUSTOM, an unknown or unavailable id, or a skin made for
--       another icon shape. look.signature is a string; two looks with the
--       same signature paint the same pixels at the same size.
--   WithGlossStrength(look, strength) -> look | nil
--       Optional additive capability: a new immutable look with reflected RGB
--       scaled by strength (0..1); frame, shadow and base opacity are retained.
--       Positive strength enables the skin's gloss material independently of
--       the global aura gloss switch; zero disables it. The original look is
--       unchanged. Call/keep it at style compile time.
--   GlossTexture() -> path
--       Optional additive capability: bundled horizontal alpha artwork for a
--       consumer's own bar reflection. The consumer owns geometry and opacity.
--   Paint(owner, look, width, height, anchor, clip) -> owned
--       Draws the look's layers (for the shape it was compiled for; masking
--       the icon stays the caller's) as textures of `owner`, a frame the caller
--       draws on, laid out around `anchor` (default `owner`): the region the
--       icon fills, `width` x `height`. The layers sit on ARTWORK 5-7 and the
--       gloss on OVERLAY -1: above BACKGROUND and ARTWORK icon art, below the
--       owner's OVERLAY text and below its child frames (the cooldown swipe).
--       A nil look hides what an earlier look drew. owned: a skin now draws
--       the look (the caller hides its own border). A repaint of the same look
--       at the same size writes nothing. clip: true clips every layer to the
--       icon, the shape the look was compiled for over `anchor` (its mask;
--       a square look: the rectangle), with one mask of `owner`. For a look
--       drawn over an icon that shows the same look at the same place (an
--       overlay, a button over a stand-in icon): the icon below draws what
--       lies outside, once. State lives in weak side tables, never in fields of `owner` or
--       `anchor`. Cold path: call it when an icon is made or restyled, never
--       per update.
--   Outset(look, width, height) -> x, y
--       How far the look's frame reaches past an icon `width` x `height` on
--       each side, in the painters' rounding (Skins.Outset: soft shadows are
--       not part of the frame); 0, 0 for no look. For what lines up with a row
--       of skinned icons, such as a resource bar matched to a cooldown row.
--   ShapeOf(choice) -> shape | nil, skinId
--       The icon shape the skin `choice` is made for, as the Icon Skins page
--       matches a shape when a skin is picked, and the skin id it resolved:
--       DEFAULT (or nil) is the default skin as the page shows it; nil for no
--       skin (CUSTOM, or a DEFAULT that is no skin).
--   SHAPES, ApplyShape(owner, shape, anchor, cooldowns, ...) -> shape
--       MSUF's aura icon shapes (Auras3/MSUF_Auras3_IconShape.lua: its media,
--       Shape.Normalize and the atlas probe) on icons a consumer draws.
--       SHAPES lists them in menu order (RECTANGLE, CIRCLE, ROUNDED, DIAMOND,
--       HEXAGON, STAR, BLIZZARD); FOLLOW_PORTRAIT and unknown values draw
--       RECTANGLE. One mask texture of `owner`, laid over `anchor` (default
--       `owner`), masks every texture in `...` (nil entries are skipped), and
--       each cooldown frame in the list `cooldowns` takes the shape's swipe
--       texture with its own regions masked (only textures take masks: a
--       cooldown's countdown text is left alone). RECTANGLE takes the masks
--       off and gives the swipes WHITE8X8 back; on an owner never shaped it
--       writes nothing. Repeating a shape over the same anchor writes only for
--       textures and cooldowns not shaped yet (a press flash or a charge swipe
--       made later). Unlike IconShape (which marks MSUF's own buttons), the
--       state lives in weak side tables, so the owner, the textures and the
--       cooldowns may be Blizzard's. Cold path: when an icon is made or
--       restyled, or when such a texture or cooldown is made.
--       Returns the shape drawn.
--   ShapeArt(shape) -> ring, fill, outerOnly, desaturate
--       Texture paths for the consumer's own shaped art: the shape's border
--       ring and its filled silhouette; outerOnly: the ring is a silhouette
--       that only works behind the icon (STAR); desaturate: tint it only after
--       SetDesaturated(true). nil for RECTANGLE.
--   Subscribe(key, fn) -> ok, Unsubscribe(key) -> ok
--       fn(reason) runs after the default skin or its look changed for
--       Compile: "apply" (a shared aura apply out of combat: an Icon Skins
--       page edit, its undo or redo, a page reset), "combat" (the combat end
--       that releases a default edited in combat) or "profile" (a profile
--       apply; also the first report after a profile switched in a fight is
--       released, whatever released it: Skins.TakeProfileSwitch). Out of
--       combat only. One listener per key; subscribing again
--       replaces it. Each runs through MSUF's boundary: one that raises is
--       reported and the others still run.
--
-- No events, hooks, timers or scripts: calls come in only from consumers and
-- from those three notifications, and a notification that leaves the default
-- as the listeners last saw it (any other aura setting) calls nobody.
```
