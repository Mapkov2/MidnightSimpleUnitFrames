-- Icon-skin host v1 for external cold style consumers.
-- Full contract: docs/ICON_SKINS.md, External host interface.
-- Compile/WithGlossStrength return immutable looks; cache variants at style compile.
-- Paint/shape state stays in weak side tables, never on consumer-owned frames.
-- Notifications are out of combat; no events, hooks, timers or scripts here.
local _, MSUF = ...
local type, select = type, select
local A3 = assert(MSUF.MSUF_Auras3)
local Skins = assert(A3.IconSkins)
-- Kernel/MSUF_Boundary.lua: a raising listener is reported and the next runs.
local RunHostAPIStep = assert(MSUF.RunHostAPIStep)
local Shape = A3.IconShape
local RECTANGLE = Shape.RECTANGLE
local CUSTOM = Skins.CUSTOM
local WHITE = "Interface\\Buttons\\WHITE8X8"
local tostring, concat = tostring, table.concat

-- The source a compile reads its skin id from; one table, refilled per call.
local SOURCE = {}

local function Compile(choice, shape)
    if choice == CUSTOM then return nil end
    shape = shape or RECTANGLE
    local _, shared = A3.EnsureDB()
    SOURCE.styleSkin = choice
    local look = Skins.AttachPreview({}, SOURCE, Skins.CommittedDefault(shared))
    SOURCE.styleSkin = nil
    local skin = look.skin
    if not skin or skin.def.shape ~= shape then return nil end
    look.signature = skin.signature
    return look
end

-- A consumer's explicit gloss strength enables the existing material. Opacity,
-- frame and shadow stay owned by the original look and native alpha writers.
local function WithGlossStrength(look, strength)
    if not (look and look.skin) then return nil end
    strength = tonumber(strength) or 1
    if strength ~= strength then strength = 1 end
    strength = math.max(0, math.min(1, strength))
    local adjusted, skin = {}, {}
    for key, value in pairs(look) do adjusted[key] = value end
    for key, value in pairs(look.skin) do skin[key] = value end
    skin.gr, skin.gg, skin.gb = skin.gr * strength, skin.gg * strength, skin.gb * strength
    skin.gloss = skin.def.gloss ~= nil and strength > 0
    local suffix = ":glossStrength:" .. tostring(strength)
    skin.signature, adjusted.signature = skin.signature .. suffix, look.signature .. suffix
    adjusted.skin = skin
    return adjusted
end

-- The already-shipped horizontal reflection; no new texture installation.
local function GlossTexture()
    return "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Skins\\msuf_skin_gloss_top.tga"
end

-- Only textures take masks; a cooldown's regions include its countdown
-- FontString, which has no AddMaskTexture.
local maskOn = setmetatable({}, { __mode = "k" })    -- region -> the mask on it
local function MaskRegion(region, mask)
    if not (region and region.AddMaskTexture) then return end
    local current = maskOn[region]
    if current == mask then return end
    if current then region:RemoveMaskTexture(current) end
    if mask then region:AddMaskTexture(mask) end
    maskOn[region] = mask
end

-- A clipped paint: one mask of the owner over the anchor on every layer the
-- painter made (Skins.EachLayer), in the shape of the icon the look is drawn
-- on (IconShape's mask; a square look: WHITE8X8, clamped to black outside);
-- new layers of a repaint join it.
local clipOwned = setmetatable({}, { __mode = "k" })  -- owner -> its clip mask
local clipTarget = setmetatable({}, { __mode = "k" }) -- owner -> the region its layers are clipped to
local clipShape = setmetatable({}, { __mode = "k" })  -- owner -> the shape its clip mask shows
local clipping -- the mask ClipLayer puts on (nil: takes it off)
local function ClipLayer(texture) MaskRegion(texture, clipping) end
local CLAMP = "CLAMPTOBLACKADDITIVE"
local function ClipArt(mask, shape)
    local media = shape ~= RECTANGLE and Shape.MEDIA[shape] or nil
    if media and media.maskAtlas and Shape.AtlasKnown(media.maskAtlas) then
        mask:SetAtlas(media.maskAtlas)
    else
        mask:SetTexture(media and (media.mask or media.swipe) or WHITE, CLAMP, CLAMP)
    end
end

local function Paint(owner, look, width, height, anchor, clip)
    if not owner then return false end
    local skin = type(look) == "table" and look.skin or nil
    local shape = skin and skin.def.shape or RECTANGLE
    local owned, unchanged = Skins.Paint(owner, look, width, shape, height, width, anchor)
    if owned then
        local target = clip and (anchor or owner) or nil
        local art = target and shape or nil
        if target ~= clipTarget[owner] or art ~= clipShape[owner] or (target and not unchanged) then
            local mask = clipOwned[owner]
            if target and not mask then
                mask = owner:CreateMaskTexture(nil, "BACKGROUND")
                clipOwned[owner] = mask
            end
            if target and art ~= clipShape[owner] then ClipArt(mask, art) end
            if target and target ~= clipTarget[owner] then
                mask:ClearAllPoints()
                mask:SetAllPoints(target)
            end
            clipping = target and mask or nil
            Skins.EachLayer(owner, ClipLayer)
            clipping = nil
            clipTarget[owner], clipShape[owner] = target, art
        end
    end
    return owned == true
end

local function Outset(look, width, height)
    local skin = type(look) == "table" and look.skin or nil
    if not skin then return 0, 0 end
    return Skins.Outset(skin, width, height)
end

local function ShapeOf(choice)
    if choice == nil or choice == Skins.DEFAULT then choice = Skins.Normalize(Skins.ReadDefault("styleSkin", CUSTOM)) end
    if choice == CUSTOM then return nil end
    return Skins.ShapeOf(choice), choice
end

local SHAPES = { RECTANGLE, "CIRCLE", "ROUNDED", "DIAMOND", "HEXAGON", "STAR", "BLIZZARD" }
local DRAWN = {}
for i = 1, #SHAPES do DRAWN[SHAPES[i]] = true end
local maskOwned = setmetatable({}, { __mode = "k" }) -- owner -> its shape mask
local shapeOf = setmetatable({}, { __mode = "k" })   -- owner -> the shape it shows (nil: RECTANGLE)
local anchorOf = setmetatable({}, { __mode = "k" })  -- owner -> the region its mask lies over
local swipeOf = setmetatable({}, { __mode = "k" })   -- cooldown -> the shape of its swipe and masks

local function OwnerMask(owner, media, anchor)
    local mask = maskOwned[owner]
    if not mask then
        mask = owner:CreateMaskTexture(nil, "BACKGROUND")
        maskOwned[owner] = mask
    end
    if media.maskAtlas and Shape.AtlasKnown(media.maskAtlas) then
        mask:SetAtlas(media.maskAtlas)
    else
        mask:SetTexture(media.mask or media.swipe)
    end
    mask:ClearAllPoints()
    mask:SetAllPoints(anchor or owner)
    mask:Show()
    anchorOf[owner] = anchor or owner
    return mask
end

local function ApplyShape(owner, shape, anchor, cooldowns, ...)
    if not owner then return RECTANGLE end
    shape = Shape.Normalize(shape)
    if not DRAWN[shape] then shape = RECTANGLE end
    if shape == RECTANGLE and not shapeOf[owner] then return RECTANGLE end
    local media = shape ~= RECTANGLE and Shape.MEDIA[shape] or nil
    local mask
    if media then
        mask = maskOwned[owner]
        -- The same shape over the same anchor: the mask is in place already.
        if not mask or shapeOf[owner] ~= shape or anchorOf[owner] ~= (anchor or owner) then
            mask = OwnerMask(owner, media, anchor)
        end
    elseif maskOwned[owner] then
        maskOwned[owner]:Hide()
    end
    for i = 1, select("#", ...) do MaskRegion((select(i, ...)), mask) end
    for i = 1, cooldowns and #cooldowns or 0 do
        local cooldown = cooldowns[i]
        if swipeOf[cooldown] ~= shape then
            swipeOf[cooldown] = shape
            cooldown:SetSwipeTexture(media and (media.swipe or media.mask) or WHITE)
            for index = 1, cooldown:GetNumRegions() do MaskRegion((select(index, cooldown:GetRegions())), mask) end
        end
    end
    shapeOf[owner] = media and shape or nil
    return shape
end

local function ShapeArt(shape)
    shape = Shape.Normalize(shape)
    local media = DRAWN[shape] and shape ~= RECTANGLE and Shape.MEDIA[shape] or nil
    if not media then return nil end
    return media.border, media.swipe or media.mask, media.borderOuterOnly == true, media.desaturate == true
end

-- Listeners by key, called in the order their keys were first subscribed.
local listeners, keys = {}, {}

local function Subscribe(key, fn)
    if key == nil or type(fn) ~= "function" then return false end
    if listeners[key] == nil then keys[#keys + 1] = key end
    listeners[key] = fn
    return true
end

-- The key keeps its place (false) so a listener that unsubscribes while the
-- others are told moves no one.
local function Unsubscribe(key)
    if not listeners[key] then return false end
    listeners[key] = false
    return true
end

-- The committed default as the listeners last heard of it: its skin id and
-- every look field Compile reads (a skin of the consumer's own uses the look).
local told
local PARTS, NO_DEFAULT = {}, {}
local CHANNEL_KEYS, CHANNELS = { "r", "g", "b", "a" }, 4
-- A colour as AttachPreview reads it: by index, else by name.
local function Channels(color, first)
    color = type(color) == "table" and color or NO_DEFAULT
    for i = 1, CHANNELS do PARTS[first + i] = tostring(color[i] or color[CHANNEL_KEYS[i]]) end
end

local function DefaultSignature()
    local _, shared = A3.EnsureDB()
    local default = Skins.CommittedDefault(shared) or NO_DEFAULT
    PARTS[1] = tostring(default.styleSkin)
    PARTS[2] = tostring(default.styleSkinColorOverride)
    PARTS[3] = tostring(default.styleSkinGloss)
    Channels(default.styleSkinColor, 3)
    Channels(default.styleSkinGlossColor, 7)
    return concat(PARTS, ":", 1, 11)
end

function Skins.NotifyChanged(reason)
    -- Reading the committed default releases a freeze whose edits applied.
    local signature = #keys > 0 and DefaultSignature() or nil
    if Skins.TakeProfileSwitch() then reason = "profile" end
    if #keys == 0 or signature == told then return end
    told = signature
    for i = 1, #keys do
        local fn = listeners[keys[i]]
        if fn then RunHostAPIStep("icon skin listener", fn, reason) end
    end
end

Skins.Host = {
    version = 1,
    DEFAULT = Skins.DEFAULT,
    CUSTOM = CUSTOM,
    Compile = Compile,
    WithGlossStrength = WithGlossStrength,
    GlossTexture = GlossTexture,
    Paint = Paint,
    ShapeOf = ShapeOf,
    Outset = Outset,
    SHAPES = SHAPES,
    ApplyShape = ApplyShape,
    ShapeArt = ShapeArt,
    Subscribe = Subscribe,
    Unsubscribe = Unsubscribe,
}
