-- Static icon-skin painters and compilers. Full design: docs/ICON_SKINS.md.
local addonName, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Auras3/IconSkins")
local BusRegister = MSUF.Require("MSUF_EventBus_Register", "Auras3/IconSkins")
local BusUnregister = MSUF.Require("MSUF_EventBus_Unregister", "Auras3/IconSkins")
local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local math_floor, math_max, math_min = math.floor, math.max, math.min
local A3 = assert(MSUF.MSUF_Auras3)
local Shape = assert(A3.IconShape)
local Skins = {}
A3.IconSkins = Skins

local CUSTOM, DEFAULT = "CUSTOM", "DEFAULT"
Skins.CUSTOM, Skins.DEFAULT = CUSTOM, DEFAULT
-- The combat snapshot keeps the default under this product key.
local DEFAULT_KIND = "iconSkinDefault"
Skins.DEFAULT_KIND = DEFAULT_KIND
Skins.MEDIA_ROOT = Shape.MEDIA_ROOT .. "\\Media\\Skins\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local LINE_EDGES = 4 -- top, bottom, left, right
local BLACK = { 0, 0, 0, 1 }
local DEFAULT_GLOSS = { 1, 1, 1, 0.12 }

local registry, order = {}, {}
-- Whether IconShape's painter takes the skin path yet (Shape.MarkSkinsLive).
local skinsLive = false

--- Registers a skin. `def.layers` is drawn bottom to top on distinct ARTWORK
--- sublevels ending at7, below gloss and text; sizes are in u,
--- 1/32 of the icon side:
---   { kind = "band", file, outer = u, inner = u }   edgeFile band (8 pieces)
---   { kind = "line", width = u | px = n, place = "inside"|"outside" }
---   { kind = "dim", alpha = 0..1 }                  full-icon tint
---   { kind = "quad", file | path, extent = u, blend }   one texture
---   { kind = "atlas", atlas, extent | extentX + extentY } Blizzard art
--- Every layer may carry `color` (else def.color, else black) and `tint =
--- false` to keep its colour when the user picks their own skin colour.
--- `def.shape` (CIRCLE, ROUNDED, HEXAGON) is the icon shape the skin is drawn
--- for (default RECTANGLE); `def.gloss = { file | path, enabled }` adds an
--- additive highlight (enabled is its default). A skin needing a Blizzard
--- atlas names it in `def.atlas` and is offered only where the client has it.
function Skins.Register(id, def)
    if type(id) ~= "string" or id == "" or id == Skins.CUSTOM then return false end
    if type(def) ~= "table" or type(def.layers) ~= "table" then return false end
    if not registry[id] then order[#order + 1] = id end
    def.id = id
    def.shape = def.shape or Shape.RECTANGLE
    registry[id] = def
    return true
end

local function Available(def)
    return def ~= nil and (def.atlas == nil or Shape.AtlasKnown(def.atlas))
end

function Skins.Get(id)
    local def = registry[id]
    return Available(def) and def or nil
end

function Skins.Normalize(id)
    if type(id) == "string" and Available(registry[id]) then return id end
    return Skins.CUSTOM
end

--- Gallery families by id prefix (the catalog's table; the first match wins).
function Skins.AssignFamilies(families)
    for i = 1, #order do
        local def = registry[order[i]]
        for j = 1, #families do
            local prefix = families[j][1]
            if def.id:sub(1, #prefix) == prefix then
                def.family = families[j][2]
                break
            end
        end
    end
end

--- The icon shape a skin is drawn for (RECTANGLE for CUSTOM and unknown ids).
function Skins.ShapeOf(id)
    local def = Skins.Get(id)
    return def and def.shape or Shape.RECTANGLE
end

--- Dropdown items: no skin (the user's own border and shadow) first, then the
--- skins in catalog order (grouped by family there, def.family names it).
--- Unavailable skins are left out. Skin names are menu text, translated by
--- every locale pack.
function Skins.List()
    local items = { { value = Skins.CUSTOM, text = "No skin (your border and shadow)" } }
    for i = 1, #order do
        local def = registry[order[i]]
        if Available(def) then
            items[#items + 1] = { value = def.id, text = def.text or def.id, family = def.family }
        end
    end
    return items
end

local function InCombatNow()
    local util = MSUF.Util
    if util and util.InCombat then return util.InCombat() == true end
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

-- The combat snapshot keeps every compile on the look the runtime last
-- applied, so a lane compiled during combat (a target or roster change) never
-- differs from the lanes around it. The first menu write after an apply, in or
-- out of combat, freezes the product's appearance table (or icon shape) as it
-- was before that write, and compiles read the frozen state until the frozen
-- edits are applied:
--   * out of combat, once an apply bumped the runtime generation
--     (A3.BumpRuntimeConfig) past the freeze;
--   * at combat start, when such an apply already ran (a slider whose delayed
--     apply lands in combat keeps the applied look through the fight);
--   * at combat end, where every apply queued in combat runs (by the aura
--     runtime or the menu's apply service). Nothing thaws during combat, so a
--     generation bump in a fight (a profile switch, a tracked spell rebuild)
--     cannot show an edit that is still waiting.
-- The combat edges come from the MSUF event bus, subscribed only while
-- something is frozen. Compiles never copy and never allocate: with nothing
-- frozen they return the live value after one upvalue test. Skins.frozen
-- mirrors that state for callers that skip the snapshot calls while nothing is
-- frozen (the Classic lane compiler runs once per lane).
local frozen, frozenShapes, anyFrozen, frozenGen, frozenWhole = {}, {}, false, nil, false
Skins.frozen = false
local BUS_KEY = "MSUF_AURA_ICON_SKIN_SNAPSHOT"

local function Thaw()
    for kind in pairs(frozen) do frozen[kind] = nil end
    for kind in pairs(frozenShapes) do frozenShapes[kind] = nil end
    anyFrozen, frozenGen, frozenWhole = false, nil, false
    Skins.frozen = false
    BusUnregister("PLAYER_REGEN_DISABLED", BUS_KEY)
    BusUnregister("PLAYER_REGEN_ENABLED", BUS_KEY)
end

--- Tells painters outside the aura runtime that the default skin or its look
--- may have changed for them; MSUF_Auras3_IconSkins_Host.lua replaces this
--- with the listener fan-out of MSUF_HostAPI.GetIconSkins().
function Skins.NotifyChanged() end

local function OnCombatEdge(event)
    if event == "PLAYER_REGEN_ENABLED" then
        Thaw()
        -- The default frozen through the fight is the live one again.
        Skins.NotifyChanged("combat")
    elseif A3._runtimeConfigGen ~= frozenGen then
        Thaw()
    end
end

local function ThawIfApplied()
    if A3._runtimeConfigGen ~= frozenGen and not InCombatNow() then Thaw() end
end

local function Committed(store, kind, live)
    if not anyFrozen then return live end
    ThawIfApplied()
    local snapshot = store[kind or ""]
    if snapshot == nil then
        if frozenWhole then return nil end
        return live
    end
    return snapshot or nil
end

--- The appearance table the runtime compiles from (a table or nil): the live
--- table, or the table as it was before the menu's first write since the last
--- apply. A product whose table the menu creates during combat stays without
--- one until combat ends. Menu previews read the live table and show edits at
--- once.
function Skins.CommittedSource(kind, live)
    if type(live) ~= "table" then live = nil end
    return Committed(frozen, kind, live)
end

--- The default skin and look the runtime compiles from: shared.iconSkinDefault,
--- or its snapshot while a write to it waits for its apply.
function Skins.CommittedDefault(shared)
    local live = type(shared) == "table" and shared.iconSkinDefault or nil
    if type(live) ~= "table" then live = nil end
    if not anyFrozen then return live end
    return Committed(frozen, DEFAULT_KIND, live)
end

--- The same for a product's icon shape (a string or nil): selecting a round
--- skin writes the shape and the skin together, and a lane must not take one
--- without the other.
function Skins.CommittedShape(kind, live)
    if type(live) ~= "string" then live = nil end
    return Committed(frozenShapes, kind, live)
end

--- Every writer of an appearance table or icon shape calls this first, with
--- the value it is about to change (Model.WriteSharedAppearanceValue and
--- Model.WriteSharedAppearanceIconShape). The first call per product since the
--- last apply keeps a copy of it, colour tables included.
local function StartFreeze()
    anyFrozen, frozenGen = true, A3._runtimeConfigGen
    Skins.frozen = true
    BusRegister("PLAYER_REGEN_DISABLED", BUS_KEY, OnCombatEdge)
    BusRegister("PLAYER_REGEN_ENABLED", BUS_KEY, OnCombatEdge)
end

function Skins.BeforeWrite(kind, current, shape)
    if anyFrozen then ThawIfApplied() end
    -- After a profile change in combat every product is frozen already.
    if frozenWhole then return end
    kind = kind or ""
    local store = shape and frozenShapes or frozen
    if store[kind] ~= nil then return end
    if not anyFrozen then StartFreeze() end
    if shape then
        store[kind] = type(current) == "string" and current or false
        return
    end
    if type(current) ~= "table" then
        store[kind] = false
        return
    end
    local copy = {}
    for key, value in pairs(current) do
        if type(value) == "table" then
            local entries = {}
            for index, entry in pairs(value) do entries[index] = entry end
            value = entries
        end
        copy[key] = value
    end
    store[kind] = copy
end

--- The skin a product shows: its own id, or the default's for DEFAULT and nil
--- (CUSTOM when neither names an available skin).
function Skins.EffectiveId(source, defaults)
    local id = type(source) == "table" and source.styleSkin or nil
    if id == nil or id == DEFAULT then id = type(defaults) == "table" and defaults.styleSkin or nil end
    return Skins.Normalize(id)
end

--- The default skin and look every product inherits. The Icon Skins page reads
--- and writes it here; a write freezes the combat snapshot first.
local function DefaultTable()
    local _, shared = A3.EnsureDB()
    if type(shared) ~= "table" then return nil, nil end
    local defaults = shared.iconSkinDefault
    return type(defaults) == "table" and defaults or nil, shared
end

--- The live default table (menu previews show edits at once), or nil.
function Skins.LiveDefault()
    return (DefaultTable())
end

function Skins.ReadDefault(key, fallback)
    local defaults = DefaultTable()
    local value = defaults and defaults[key]
    if value == nil then return fallback end
    return value
end

function Skins.WriteDefault(key, value)
    local defaults, shared = DefaultTable()
    if not shared then return false end
    if defaults and defaults[key] == value then return false end
    Skins.BeforeWrite(DEFAULT_KIND, defaults)
    if not defaults then
        defaults = {}
        shared.iconSkinDefault = defaults
    end
    defaults[key] = value
    return true
end

--- Profile storage calls this right before it switches, resets or imports
--- into the active profile (MSUF_ProfileIO_BeforeActiveProfileMutation, while
--- A3.EnsureDB still returns it). In combat the runtime applies the new
--- profile at combat end, so every product's appearance table and icon shape
--- and the default skin freeze as they are now, and a lane compiled in the
--- fight keeps the look of the lanes around it; a product this profile does
--- not style reads as unstyled. Out of combat the apply follows at once and
--- nothing freezes.
-- A profile switched in a fight: the first report once the freeze is
-- released, by whichever path releases it (the combat end, an apply queued
-- in the fight, the deferred profile apply), is a profile change, not a pick
-- of a default (Skins.TakeProfileSwitch, the host interface's reports).
local profileSwitched = false
function Skins.TakeProfileSwitch()
    if not profileSwitched or anyFrozen then return false end
    profileSwitched = false
    return true
end

function Skins.FreezeProfile()
    if frozenWhole or not InCombatNow() then return end
    profileSwitched = true
    local _, shared = A3.EnsureDB()
    shared = type(shared) == "table" and shared or {}
    for kind, style in pairs(type(shared.appearanceIconStyles) == "table" and shared.appearanceIconStyles or {}) do
        Skins.BeforeWrite(kind, style)
    end
    for kind, shape in pairs(type(shared.appearanceIconShapes) == "table" and shared.appearanceIconShapes or {}) do
        Skins.BeforeWrite(kind, shape, true)
    end
    Skins.BeforeWrite(DEFAULT_KIND, shared.iconSkinDefault)
    frozenWhole = true
end

local function Channel(color, index, key, fallback)
    local value = type(color) == "table" and (color[index] or color[key]) or nil
    value = tonumber(value)
    if not value then return fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

--- Compile the preview skin; full contract: docs/ICON_SKINS.md.
local NO_LOOK = {}
function Skins.AttachPreview(style, source, defaults)
    if type(style) ~= "table" then return style end
    if type(defaults) ~= "table" then defaults = nil end
    -- Every compile passes here; a profile without a skin leaves at once.
    local id = type(source) == "table" and source.styleSkin or nil
    if id == nil or id == DEFAULT then id = defaults and defaults.styleSkin end
    local def = id and id ~= CUSTOM and registry[id] or nil
    if not (def and Available(def)) then
        style.skin = nil
        return style
    end
    local look = defaults or NO_LOOK
    local user = look.styleSkinColor or BLACK
    local gloss = look.styleSkinGlossColor or DEFAULT_GLOSS
    local glossOn = look.styleSkinGloss
    if glossOn == nil then glossOn = def.gloss ~= nil and def.gloss.enabled == true end
    local skin = {
        id = id, def = def, override = look.styleSkinColorOverride == true,
        r = Channel(user, 1, "r", 0), g = Channel(user, 2, "g", 0),
        b = Channel(user, 3, "b", 0), a = Channel(user, 4, "a", 1),
        gloss = glossOn == true and def.gloss ~= nil,
        gr = Channel(gloss, 1, "r", 1), gg = Channel(gloss, 2, "g", 1),
        gb = Channel(gloss, 3, "b", 1), ga = Channel(gloss, 4, "a", 0.12),
    }
    skin.signature = table.concat({ "K", id, skin.override and "O" or "o", skin.r, skin.g, skin.b, skin.a,
        skin.gloss and "G" or "g", skin.gr, skin.gg, skin.gb, skin.ga }, ":")
    style.skin = skin
    if style.signature then style.signature = style.signature .. ":" .. skin.signature end
    return style
end

--- The runtime compilers' entry (Retail SharedIconStyle, Classic
--- V.SharedIconStyle): the first skin they produce switches the live painters
--- to the skin-aware ones (Shape.MarkSkinsLive). Until then, and for a profile
--- without skins, live buttons run exactly the painters they ran before skins
--- existed; opening a menu or a preview never changes that.
function Skins.Attach(style, source, defaults)
    style = Skins.AttachPreview(style, source, defaults)
    if not skinsLive and type(style) == "table" and style.skin then
        skinsLive = true
        Shape.MarkSkinsLive()
    end
    return style
end

-------------------------------------------------------------------------------
--  Painter
-------------------------------------------------------------------------------

local states = setmetatable({}, { __mode = "k" })
-- Read by the skin-aware painter's fast path (Auras3/MSUF_Auras3_IconShape.lua).
Skins.states = states

local function Px(size, u)
    if not u or u <= 0 then return 0 end
    return math_max(1, math_floor(size * u / 32 + 0.5))
end

--- A layer's colour: its own (or the skin's) design colour, the user's colour
--- instead when they override it on a tintable layer, scaled by the user alpha.
local function LayerColor(skin, layer)
    local base = layer.color or skin.def.color or BLACK
    local a = (base[4] or 1) * skin.a
    if skin.override and layer.tint ~= false then return skin.r, skin.g, skin.b, a end
    return base[1] or 0, base[2] or 0, base[3] or 0, a
end

local function MediaPath(layer)
    return layer.path or (Skins.MEDIA_ROOT .. layer.file .. ".tga")
end

local function HideState(state)
    local BorderStyles = MSUF.BorderStyles
    for i = 1, #state.bands do
        if BorderStyles then BorderStyles.Hide(state.bands[i]) end
    end
    for i = 1, #state.quads do state.quads[i]:Hide() end
    for i = 1, #state.lines do
        for edge = 1, LINE_EDGES do state.lines[i][edge]:Hide() end
    end
    if state.dim then state.dim:Hide() end
    if state.gloss then state.gloss:Hide() end
    state.signature, state.skin = nil, nil
    state.hidden = true
end

--- A Classic lane that hides its icon draws no skin: bar-only duration bars
--- and spell indicators shown as a square, a bar, a number or nothing. The
--- lane's final settings decide it (a group Spell Icon style applies after the
--- lane compiled its icon style). Unit debuff lanes keep a dispel-frame table
--- in `visual`, which is an icon.
local function IconHidden(lane)
    if not lane then return false end
    local visual = lane.visual
    if type(visual) == "string" and visual ~= "icon" then return true end
    return lane.showDurationBar == true and lane.durationBarDisplay == "BAR_ONLY"
end

--- `inside` caps how far a band or line may reach into the icon: half its
--- shorter side, so a flat icon (height below 100%) keeps its bands inside.
--- Every layer is a texture of `owner` laid out around `state.target`, the
--- region the icon fills (the owner itself unless Paint got an anchor).
local function PaintBand(owner, state, index, layer, size, height, inside, skin, sublevel)
    local BorderStyles = MSUF.BorderStyles
    if not BorderStyles then return end
    local path = MediaPath(layer)
    local pieces = state.bands[index]
    if not pieces then
        pieces = BorderStyles.Create(owner, "ARTWORK", sublevel, path)
        pieces.skinSublevel = sublevel
        state.bands[index] = pieces
    else
        BorderStyles.SetTexture(pieces, path)
        if pieces.skinSublevel ~= sublevel then
            for i = 1, #pieces do pieces[i]:SetDrawLayer("ARTWORK", sublevel) end
            pieces.skinSublevel = sublevel
        end
    end
    local out = Px(size, layer.outer)
    local edge = out + math_min(Px(size, layer.inner), inside)
    local r, g, b, a = LayerColor(skin, layer)
    BorderStyles.Apply(pieces, state.target, edge, size, height, r, g, b, a, edge * 0.5 - out)
end

--- A quad covers the icon plus its extent, scaled per axis so a ring follows a
--- mask stretched over a non-square icon; an atlas quad shows Blizzard art and
--- stays hidden where the client lacks the atlas.
local function PaintQuad(owner, state, index, layer, size, height, skin, sublevel)
    local texture = state.quads[index]
    if not texture then
        texture = PixelLayoutRegion(owner:CreateTexture(nil, "ARTWORK", nil, sublevel))
        state.quads[index] = texture
    end
    texture:SetDrawLayer("ARTWORK", sublevel)
    if layer.atlas then
        if not Shape.AtlasKnown(layer.atlas) then
            texture:Hide()
            return
        end
        texture:SetAtlas(layer.atlas)
    else
        texture:SetTexture(MediaPath(layer))
        texture:SetTexCoord(0, 1, 0, 1)
    end
    texture:SetBlendMode(layer.blend or "BLEND")
    local ex = Px(size, layer.extentX or layer.extent)
    local ey = Px(height, layer.extentY or layer.extent)
    texture:ClearAllPoints()
    local target = state.target
    texture:SetPoint("TOPLEFT", target, "TOPLEFT", -ex, ey)
    texture:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", ex, -ey)
    texture:SetVertexColor(LayerColor(skin, layer))
    texture:Show()
end

local function PaintLine(owner, state, index, layer, size, inside, skin, sublevel)
    local lines = state.lines[index]
    if not lines then
        lines = {}
        for i = 1, LINE_EDGES do
            lines[i] = PixelLayoutRegion(owner:CreateTexture(nil, "ARTWORK", nil, sublevel))
            lines[i]:SetTexture(WHITE)
        end
        lines.skinSublevel = sublevel
        state.lines[index] = lines
    elseif lines.skinSublevel ~= sublevel then
        for i = 1, LINE_EDGES do lines[i]:SetDrawLayer("ARTWORK", sublevel) end
        lines.skinSublevel = sublevel
    end
    local width = math_max(1, math_min(layer.px or Px(size, layer.width or 1), inside))
    local o = layer.place == "outside" and width or 0
    local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
    local target = state.target
    for i = 1, LINE_EDGES do lines[i]:ClearAllPoints() end
    top:SetPoint("TOPLEFT", target, "TOPLEFT", -o, o)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", o, o)
    top:SetHeight(width)
    bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -o, -o)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", o, -o)
    bottom:SetHeight(width)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
    left:SetWidth(width)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    right:SetWidth(width)
    local r, g, b, a = LayerColor(skin, layer)
    for i = 1, LINE_EDGES do
        lines[i]:SetVertexColor(r, g, b, a)
        lines[i]:Show()
    end
end

local function PaintDim(owner, state, layer, skin, sublevel)
    local dim = state.dim
    if not dim then
        dim = PixelLayoutRegion(owner:CreateTexture(nil, "ARTWORK", nil, sublevel))
        dim:SetTexture(WHITE)
        dim:SetAllPoints(state.target)
        state.dim = dim
    end
    dim:SetDrawLayer("ARTWORK", sublevel)
    local r, g, b, a = LayerColor(skin, layer)
    dim:SetVertexColor(r, g, b, a * (layer.alpha or 0))
    dim:Show()
end

--- Gloss is a texture on the owner, on OVERLAY(-1): above the icon art and the
--- skin layers, below the owner's own text and dispel border. A cooldown swipe
--- or text on child frames draws over it, live and in every preview alike.
local function PaintGloss(owner, state, skin)
    local gloss = state.gloss
    if not gloss then
        gloss = PixelLayoutRegion(owner:CreateTexture(nil, "OVERLAY", nil, -1))
        gloss:SetBlendMode("ADD")
        gloss:SetAllPoints(state.target)
        state.gloss = gloss
    end
    gloss:SetTexture(MediaPath(skin.def.gloss))
    gloss:SetVertexColor(skin.gr, skin.gg, skin.gb, skin.ga)
    gloss:Show()
end

--- Draws every layer of `skin`; returns how many bands, quads and lines it
--- used and whether it drew a dim, so Paint can hide what an earlier skin
--- left behind.
local function PaintLayers(owner, state, skin, size, height, inside)
    local bands, quads, lines, dim = 0, 0, 0, false
    local layers = skin.def.layers
    for i = 1, #layers do
        local layer = layers[i]
        local kind = layer.kind
        local sublevel = 7 - #layers + i
        if kind == "band" then
            bands = bands + 1
            PaintBand(owner, state, bands, layer, size, height, inside, skin, sublevel)
        elseif kind == "quad" or kind == "atlas" then
            quads = quads + 1
            PaintQuad(owner, state, quads, layer, size, height, skin, sublevel)
        elseif kind == "line" then
            lines = lines + 1
            PaintLine(owner, state, lines, layer, size, inside, skin, sublevel)
        elseif kind == "dim" then
            dim = true
            PaintDim(owner, state, layer, skin, sublevel)
        end
    end
    return bands, quads, lines, dim
end

--- Paint once per changed skin/geometry/anchor; full contract: docs/ICON_SKINS.md.
function Skins.Paint(owner, style, size, shape, height, width, anchor)
    local skin = type(style) == "table" and style.skin or nil
    local state = states[owner]
    if not (owner and skin and shape == skin.def.shape) or IconHidden(skin.lane) then
        if not state or state.hidden then return false, true end
        HideState(state)
        return false, false
    end
    local target = anchor or owner
    -- A layout repaint of the same compiled skin at the same request (a Classic
    -- cooldown that appeared) reads and writes nothing.
    if state and state.skin == skin and state.target == target and state.request == size
        and state.requestHeight == height and state.requestWidth == width then
        return true, true
    end
    local request, requestHeight, requestWidth = size, height, width
    if not height and target.GetHeight then
        local w, h = target:GetWidth(), target:GetHeight()
        if w and w > 0 and h and h > 0 then width, height = w, h end
    end
    size = tonumber(width or size) or 0
    height = tonumber(height) or size
    if state and state.target == target and state.signature == skin.signature and state.size == size
        and state.height == height then
        state.skin, state.request, state.requestHeight, state.requestWidth = skin, request, requestHeight, requestWidth
        return true, true
    end
    if not state then
        state = { bands = {}, quads = {}, lines = {}, target = target }
        states[owner] = state
    elseif state.target ~= target then
        -- Dim and gloss follow a new anchor here; every other layer is laid
        -- out around it below.
        state.target = target
        if state.dim then
            state.dim:ClearAllPoints()
            state.dim:SetAllPoints(target)
        end
        if state.gloss then
            state.gloss:ClearAllPoints()
            state.gloss:SetAllPoints(target)
        end
    end
    local inside = math_max(1, math_floor(math_min(size, height) / 2))
    local bands, quads, lines, dim = PaintLayers(owner, state, skin, size, height, inside)
    local BorderStyles = MSUF.BorderStyles
    for i = bands + 1, #state.bands do
        if BorderStyles then BorderStyles.Hide(state.bands[i]) end
    end
    for i = quads + 1, #state.quads do state.quads[i]:Hide() end
    for i = lines + 1, #state.lines do
        for edge = 1, LINE_EDGES do state.lines[i][edge]:Hide() end
    end
    if not dim and state.dim then state.dim:Hide() end
    if skin.gloss then
        PaintGloss(owner, state, skin)
    elseif state.gloss then
        state.gloss:Hide()
    end
    state.signature, state.size, state.height, state.hidden = skin.signature, size, height, false
    state.skin, state.request, state.requestHeight, state.requestWidth = skin, request, requestHeight, requestWidth
    return true, false
end

--- Calls fn(texture) for every layer texture Paint made on `owner`, shown or
--- not (the host interface clips them: Auras3/MSUF_Auras3_IconSkins_Host.lua).
function Skins.EachLayer(owner, fn)
    local state = owner and states[owner]
    if not state then return end
    for i = 1, #state.bands do
        local pieces = state.bands[i]
        for p = 1, #pieces do fn(pieces[p]) end
    end
    for i = 1, #state.quads do fn(state.quads[i]) end
    for i = 1, #state.lines do
        for edge = 1, LINE_EDGES do fn(state.lines[i][edge]) end
    end
    if state.dim then fn(state.dim) end
    if state.gloss then fn(state.gloss) end
end

-- Soft shadow art (the generator's msuf_skin_shadow_* profiles) fades out and
-- is not part of a skin's frame.
local SHADOW_MEDIA = "^msuf_skin_shadow"

--- Frame outset in pixels, x/y; full contract: docs/ICON_SKINS.md.
function Skins.Outset(skin, width, height)
    if type(skin) == "string" then skin = Skins.Get(skin) end
    local def = type(skin) == "table" and (skin.def or skin) or nil
    width = tonumber(width) or 0
    height = tonumber(height) or width
    if not (def and type(def.layers) == "table") or width <= 0 or height <= 0 then return 0, 0 end
    local inside = math_max(1, math_floor(math_min(width, height) / 2))
    local x, y = 0, 0
    for i = 1, #def.layers do
        local layer = def.layers[i]
        local kind, ox, oy = layer.kind, 0, 0
        if type(layer.file) == "string" and layer.file:find(SHADOW_MEDIA) then
            kind = nil
        elseif layer.atlas and not Shape.AtlasKnown(layer.atlas) then
            kind = nil
        end
        if kind == "band" then
            ox = Px(width, layer.outer)
            oy = ox
        elseif kind == "quad" or kind == "atlas" then
            ox, oy = Px(width, layer.extentX or layer.extent), Px(height, layer.extentY or layer.extent)
        elseif kind == "line" and layer.place == "outside" then
            ox = math_max(1, math_min(layer.px or Px(width, layer.width or 1), inside))
            oy = ox
        end
        if ox > x then x = ox end
        if oy > y then y = oy end
    end
    return x, y
end
