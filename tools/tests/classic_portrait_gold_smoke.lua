-- Contract for the BLIZZARD portrait shape: the stock player-frame dressing.
--
-- The shape must render with Blizzard's own assets -- the circular portrait
-- mask atlas plus the gold ring cropped out of the stock player-frame atlas --
-- untinted, with every MSUF border renderer parked. The crop geometry mirrors
-- Blizzard_UnitFrame/Mainline/PlayerFrame.xml (232x100 frame, 60x60 portrait
-- at TOPLEFT 24,-19, atlas centered); those constants are load-bearing, so
-- this smoke recomputes them against a stubbed C_Texture.GetAtlasInfo and
-- fails if either side drifts.
_G = _G or _ENV

local function ResolvePath(primary, fallback)
    local handle = io.open(primary, "r")
    if handle then
        handle:close()
        return primary
    end
    return fallback
end

local commonPath = ResolvePath(
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua",
    "UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua"
)
local portraitPath = ResolvePath(
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua",
    "UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"
)

local function ReadSource(primary, fallback)
    local path = ResolvePath(primary, fallback)
    local handle = assert(io.open(path, "rb"), "missing file: " .. tostring(path))
    local text = handle:read("*a") or ""
    handle:close()
    return (text:gsub("\r\n", "\n")), path
end

local function NewRegion(parent)
    local region = { parent = parent, shown = true, frameLevel = 1 }
    function region:GetParent() return self.parent end
    function region:EnableMouse(value) self.mouseEnabled = value end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(value) self.shown = value == true end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function region:SetAllPoints(value) self.allPoints = value or true end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    function region:GetWidth() return self.width or 100 end
    function region:GetHeight() return self.height or 40 end
    function region:SetFrameLevel(level) self.frameLevel = level end
    function region:GetFrameLevel() return self.frameLevel end
    function region:SetTexture(value) self.texture = value; self.atlas = nil end
    function region:GetTexture() return self.texture end
    function region:SetAtlas(value) self.atlas = value; self.texture = nil end
    function region:SetTexCoord(...) self.texCoord = { ... } end
    function region:SetVertexColor(...) self.vertexColor = { ... } end
    function region:SetAlpha(value) self.alpha = value end
    function region:GetAlpha() return self.alpha or 1 end
    function region:CreateTexture(_, layer, _, sublevel)
        local texture = NewRegion(self)
        texture.layer, texture.sublevel = layer, sublevel
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function region:CreateMaskTexture()
        local mask = NewRegion(self)
        mask.isMask = true
        return mask
    end
    function region:AddMaskTexture(mask)
        self.masks = self.masks or {}
        self.masks[#self.masks + 1] = mask
    end
    function region:HookScript(script, callback)
        self.hooks = self.hooks or {}
        self.hooks[script] = callback
    end
    return region
end

local function CreateFrame(_, _, parent)
    return NewRegion(parent)
end

_G.CreateFrame = CreateFrame
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitIsVisible = function() return true end
_G.UnitGUID = function() return "Player-1" end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.UnitReaction = function() return 5 end
_G.InCombatLockdown = function() return false end
_G.GetTime = function() return 1 end
_G.issecretvalue = function() return false end
local portraitCalls, lastPortraitMaskArg = 0, "unset"
_G.SetPortraitTexture = function(texture, unit, disableMasking)
    portraitCalls = portraitCalls + 1
    lastPortraitMaskArg = disableMasking
    texture:SetTexture("portrait:" .. tostring(unit) .. (disableMasking and ":unmasked" or ""))
end
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

-- Stub atlas sheet: the frame atlas element occupies a sub-rect of a larger
-- texture file, so the crop math has to compose with non-trivial base coords.
local FRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn"
local MASK_ATLAS = "UI-HUD-UnitFrame-Player-Portrait-Mask"
local CORNER_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment"
local atlasInfo = {
    [FRAME_ATLAS] = {
        width = 198, height = 71,
        leftTexCoord = 0.25, rightTexCoord = 0.5,
        topTexCoord = 0, bottomTexCoord = 0.75,
        file = 131234,
    },
    [MASK_ATLAS] = { width = 64, height = 64, file = 131235 },
    [CORNER_ATLAS] = { width = 23, height = 23, file = 131234 },
}
_G.C_Texture = { GetAtlasInfo = function(atlas) return atlasInfo[atlas] end }

local function LoadElement()
    local registered
    local UF = {
        Layers = { PORTRAIT_OFFSET = 6, PORTRAIT_BORDER_OFFSET = 7 },
        RegisterElement = function(name, element)
            assert(name == "Portrait", "unexpected element registration")
            registered = element
        end,
    }
    local MSUF = {
        UF = UF,
        Secrets = {
            IsNil = function(value) return value == nil end,
            NotSecret = function() return true end,
        },
    }
    _G.MSUF_NS = MSUF
    local commonChunk, commonError = loadfile(commonPath)
    assert(commonChunk, commonError)
    commonChunk("MidnightSimpleUnitFrames", MSUF)
    local portraitChunk, portraitError = loadfile(portraitPath)
    assert(portraitChunk, portraitError)
    portraitChunk("MidnightSimpleUnitFrames", MSUF)
    return assert(registered, "Portrait element was not registered")
end

local function NewFrame(shape, borderStyle)
    local frame = NewRegion(nil)
    frame.MSUFUnitKey = "player"
    frame.Health = NewRegion(frame)
    frame.MSUFSpec = {
        height = 64,
        portrait = {
            enabled = true,
            render = "2D",
            shape = shape,
            side = "LEFT",
            size = 60,
            texL = 0, texR = 1, texT = 0, texB = 1,
            border = { style = borderStyle or "NONE", thickness = 2 },
            bg = { enabled = false },
        },
    }
    return frame
end

local function Near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-9,
        label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local Portrait = LoadElement()

-- 1) BLIZZARD shape renders Blizzard's mask atlas plus the untinted ring crop.
local frame = NewFrame("BLIZZARD")
Portrait.Create(frame)
Portrait.Apply(frame, frame.MSUFSpec)
local holder = assert(frame.MSUFPortraitHolder, "portrait holder missing")
assert(holder.mask and holder.mask.atlas == MASK_ATLAS,
    "BLIZZARD shape must mask the portrait with Blizzard's portrait mask atlas")
-- Blizzard's player frame resolves the portrait with disablePortraitMask
-- (UnitFrame.lua: SetPortraitTexture(portrait, unit, disablePortraitMask)),
-- the modern unmasked bust render. The shape must request the same render.
assert(portraitCalls == 1 and lastPortraitMaskArg == true,
    "BLIZZARD shape must resolve the portrait with disablePortraitMask")

local ring = assert(holder.blizzRing, "Blizzard ring texture missing")
assert(ring.shown == true, "Blizzard ring must be shown")
assert(ring.parent == holder.border, "Blizzard ring must render on the border frame above the art")
assert(ring.texture == 131234, "Blizzard ring must draw the frame atlas file")

-- The shipped ring art opens into the bar housing past one o'clock, so the
-- element draws the clean LEFT half of the fitted ring circle (center 36,
-- 34.25, clip radius 34) twice: straight, then mirrored across the axis.
-- Element fractions compose with the element's own base coords in the sheet.
local du = 0.5 - 0.25
local dv = 0.75 - 0
local cl = 0.25 + (2 / 198) * du
local cr = 0.25 + (36 / 198) * du
local ct = 0 + (0.25 / 71) * dv
local cb = 0 + (68.25 / 71) * dv
Near(ring.texCoord[1], cl, "ring left coord")
Near(ring.texCoord[2], cr, "ring right coord")
Near(ring.texCoord[3], ct, "ring top coord")
Near(ring.texCoord[4], cb, "ring bottom coord")
local mirror = assert(holder.blizzRingMirror, "mirrored ring half missing")
assert(mirror.shown == true, "mirrored ring half must be shown")
assert(mirror.texture == 131234, "mirrored half must draw the same atlas file")
Near(mirror.texCoord[1], cr, "mirror left coord (flipped)")
Near(mirror.texCoord[2], cl, "mirror right coord (flipped)")
Near(mirror.texCoord[3], ct, "mirror top coord")
Near(mirror.texCoord[4], cb, "mirror bottom coord")

-- Quads anchor through Blizzard's portrait rect (7,4.5 size 60): at a 60px
-- portrait the left half spans -5..29 from the holder's left edge, the
-- mirrored half 29..(width+3), 4.25px above and 3.75px below the rim; the
-- circular clip mask spans both halves.
assert(ring.points and #ring.points == 2, "ring must anchor with two points")
Near(ring.points[1][4], -5, "ring TOPLEFT x offset")
Near(ring.points[1][5], 4.25, "ring TOPLEFT y offset")
assert(ring.points[2][3] == "BOTTOMLEFT", "left half must end on the mirror axis")
Near(ring.points[2][4], 29, "ring axis x offset")
Near(ring.points[2][5], -3.75, "ring BOTTOMRIGHT y offset")
assert(mirror.points and #mirror.points == 2, "mirror must anchor with two points")
Near(mirror.points[1][4], 29, "mirror TOPLEFT x offset (axis)")
Near(mirror.points[2][4], 3, "mirror BOTTOMRIGHT x offset")
local clip = assert(holder.blizzRingMask, "ring clip mask missing")
assert(ring.masks and ring.masks[1] == clip, "ring must be clipped by the circle mask")
assert(mirror.masks and mirror.masks[1] == clip, "mirrored half must share the circle mask")
assert(type(clip.texture) == "string" and clip.texture:find("circle_mask", 1, true),
    "ring clip mask must use the circle mask file")
assert(clip.points and #clip.points == 2, "ring clip mask must anchor with two points")
Near(clip.points[1][4], -5, "clip TOPLEFT x offset")
Near(clip.points[2][4], 3, "clip BOTTOMRIGHT x offset")
local color = ring.vertexColor
assert(color and color[1] == 1 and color[2] == 1 and color[3] == 1 and color[4] == 1,
    "Blizzard ring must stay untinted")
local mcolor = mirror.vertexColor
assert(mcolor and mcolor[1] == 1 and mcolor[2] == 1 and mcolor[3] == 1 and mcolor[4] == 1,
    "mirrored half must stay untinted")

-- The corner embellishment fills the notch the ring art leaves at its lower
-- right, exactly where PlayerFrame.xml anchors it: portrait-relative 34.5
-- offset, 23px quad at a 60px portrait.
local corner = assert(holder.blizzCorner, "corner embellishment texture missing")
assert(corner.shown == true, "corner embellishment must be shown")
assert(corner.atlas == CORNER_ATLAS, "corner embellishment must draw Blizzard's atlas")
assert(corner.sublevel == 3, "corner embellishment must draw above the ring")
Near(corner.points[1][4], 34.5, "corner x offset")
Near(corner.points[1][5], -34.5, "corner y offset")
Near(corner.width, 23, "corner width")
Near(corner.height, 23, "corner height")

-- 2) Border settings are inert: a dynamic border colour neither tints the ring
-- nor re-enables any MSUF border renderer, and the border stays event-free.
frame.MSUFSpec.portrait.border.style = "CLASS_COLOR"
Portrait.Apply(frame, frame.MSUFSpec)
assert(holder.blizzRing.shown == true, "ring must survive border style changes")
color = holder.blizzRing.vertexColor
assert(color and color[1] == 1 and color[2] == 1 and color[3] == 1 and color[4] == 1,
    "border colour must not tint the Blizzard ring")
if holder.edges then
    for i = 1, 4 do
        assert(holder.edges[i].shown ~= true, "edge renderer must stay parked for BLIZZARD shape")
    end
end
assert(Portrait.BorderNeedsUpdate("UNIT_PORTRAIT_UPDATE", frame.MSUFSpec.portrait) == false,
    "BLIZZARD shape must not request border updates from gameplay events")
assert(Portrait.BorderNeedsUpdate("MSUF_APPLY", frame.MSUFSpec.portrait) == true,
    "config applies must still lay the ring out")

-- 3) Leaving the shape hides the Blizzard ring and hands back the MSUF border.
frame.MSUFSpec.portrait.shape = "CIRCLE"
frame.MSUFSpec.portrait.border.style = "SOLID"
Portrait.Apply(frame, frame.MSUFSpec)
assert(holder.blizzRing.shown == false, "Blizzard ring must hide when the shape changes")
assert(holder.blizzRingMirror.shown == false, "mirrored ring half must hide when the shape changes")
assert(holder.blizzCorner.shown == false, "corner embellishment must hide when the shape changes")
assert(portraitCalls == 2 and lastPortraitMaskArg == nil,
    "leaving the shape must re-resolve with the legacy masked portrait render")
assert(holder.mask.texture and tostring(holder.mask.texture):find("circle_mask", 1, true),
    "CIRCLE shape must restore the file-based mask")
assert(holder.ring and holder.ring.shown == true, "solid ring renderer must take over for CIRCLE")

-- 4) Without atlas data (fresh load, no C_Texture) the shape degrades to the
-- circle mask and a visible gold relief ring without a modern HUD atlas.
_G.C_Texture = nil
local PortraitFallback = LoadElement()
local fallbackFrame = NewFrame("BLIZZARD")
PortraitFallback.Create(fallbackFrame)
PortraitFallback.Apply(fallbackFrame, fallbackFrame.MSUFSpec)
local fallbackHolder = assert(fallbackFrame.MSUFPortraitHolder, "fallback holder missing")
assert(fallbackHolder.mask.texture and tostring(fallbackHolder.mask.texture):find("circle_mask", 1, true),
    "atlas-less client must fall back to the circle mask file")
assert(fallbackHolder.blizzRing == nil, "atlas-less client must not build a ring texture")


assert(fallbackHolder.artBorder and fallbackHolder.artBorder.shown, "Era must show the gold ring")
local art = fallbackHolder.artBorder
assert(art.texture:find("msuf_portrait_ring_circle", 1, true), "fallback must use bundled circular art")
assert(art.vertexColor[1] == 1 and art.vertexColor[2] == 0.82 and art.vertexColor[3] == 0.3, "fallback must be gold")
PortraitFallback.Apply(fallbackFrame, fallbackFrame.MSUFSpec)
assert(fallbackHolder.artBorder == art and art.shown, "reapply must reuse and show gold ring")
fallbackFrame.MSUFSpec.portrait.shape = "SQUARE"
PortraitFallback.Apply(fallbackFrame, fallbackFrame.MSUFSpec)
assert(not art.shown, "leaving Blizzard shape must hide fallback")

local ns = { MSUF2 = {} }
ns.MSUF2.PickFallbackTable = function(deps, defaults)
    return setmetatable({}, { __index = function(_, key) return deps[key] or defaults[key] end })
end
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render_Classic.lua"))("Options", ns)
local preview = {}
ns.UFPreviewRender.Install(preview, {})
local render = assert(preview.RefreshDeps._RenderState)
local portrait = NewRegion()
render.LayoutPreviewBlizzardPortrait(portrait, true, 60, 60)
local previewArt = assert(portrait._msufPreviewBlizzFallback)
assert(previewArt.shown and previewArt.vertexColor[2] == 0.82, "Era preview must show gold")
render.LayoutPreviewBlizzardPortrait(portrait, false, 60, 60)
assert(not previewArt.shown, "preview fallback must hide on shape switch")
print("classic_portrait_gold_smoke: OK")
