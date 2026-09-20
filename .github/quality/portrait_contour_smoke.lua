-- Contract for the BLIZZARD portrait shape: a complete freestanding round rim.
--
-- The standalone contour must keep its lower-right extension while the
-- portrait mask ends under one continuous gold rim. Runtime and preview use
-- the same assets and bounds; neither depends on the full player-frame atlas.
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
    function region:SetRoundLayoutToNearestPixel(value) self.roundLayout = value end
    function region:SetSnapToPixelGrid(value) self.snapToPixelGrid = value end
    function region:SetTexelSnappingBias(value) self.texelSnappingBias = value end
    function region:SetVertexColor(...) self.vertexColor = { ... } end
    function region:SetAlpha(value) self.alpha = value end
    function region:GetAlpha() return self.alpha == nil and 1 or self.alpha end
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
    function region:SetScript(script, callback)
        self.scripts = self.scripts or {}; self.scripts[script] = callback
    end
    function region:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function region:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function region:HookScript(script, callback)
        self.hooks = self.hooks or {}
        self.hooks[script] = callback
    end
    return region
end

local lastCreatedFrame
local function CreateFrame(_, _, parent)
    lastCreatedFrame = NewRegion(parent)
    return lastCreatedFrame
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
    texture:SetTexCoord(0, 1, 0, 1) -- native portrait binding may reset the crop
    texture:SetTexture("portrait:" .. tostring(unit) .. (disableMasking and ":unmasked" or ""))
end
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

-- Stub atlas sheet: the frame atlas element occupies a sub-rect of a larger
-- texture file, so the crop math has to compose with non-trivial base coords.
local FRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn"
local MASK_ATLAS = "UI-HUD-UnitFrame-Player-Portrait-Mask"
local MASK_FILE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\portrait_blizzard_mask.tga"
local RING_FILE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_portrait_ring_blizzard.tga"
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

local function LoadElement(client)
    local registered = {}
    local UF = {
        Layers = { PORTRAIT_OFFSET = 6, PORTRAIT_BORDER_OFFSET = 7 },
        RegisterElement = function(name, element)
            registered[name] = element
        end,
    }
    -- Game/Shared/Initialize.lua loads before this element on every TOC, so the
    -- legacy Era portrait gate reads MSUF.Client and never the raw project ID.
    local MSUF = {
        Client = client,
        ExportPublic = function(name, value) _G[name] = value end,
        UF = UF,
        Secrets = {
            IsNil = function(value) return value == nil end,
            NotSecret = function() return true end,
        },
    }
    _G.MSUF_NS = MSUF
    assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua"))("Core", MSUF)
    assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))("Core", MSUF)
    assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"))("Core", MSUF)
    local commonChunk, commonError = loadfile(commonPath)
    assert(commonChunk, commonError)
    commonChunk("MidnightSimpleUnitFrames", MSUF)
    local portraitChunk, portraitError = loadfile(portraitPath)
    assert(portraitChunk, portraitError)
    portraitChunk("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua"))("Core", MSUF)
    return assert(registered.Portrait, "Portrait element was not registered"), MSUF, registered.Alpha
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

-- 1) Paired assets render the standalone contour with a continuous gold rim.
local frame = NewFrame("BLIZZARD")
Portrait.Create(frame)
Portrait.Apply(frame, frame.MSUFSpec)
local holder = assert(frame.MSUFPortraitHolder, "portrait holder missing")
assert(holder.mask and holder.mask.texture == MASK_FILE,
    "BLIZZARD shape must use the mask paired with its standalone rim")
-- Blizzard's player frame resolves the portrait with disablePortraitMask
-- (UnitFrame.lua: SetPortraitTexture(portrait, unit, disablePortraitMask)),
-- the modern unmasked bust render. The shape must request the same render.
assert(portraitCalls == 1 and lastPortraitMaskArg == true,
    "BLIZZARD shape must resolve the portrait with disablePortraitMask")

local ring = assert(holder.blizzRing, "Blizzard ring texture missing")
assert(ring.shown == true, "Blizzard ring must be shown")
assert(ring.parent == holder.border, "Blizzard ring must render on the border frame above the art")
assert(ring.texture == RING_FILE, "Blizzard ring must use the standalone contour art")
assert(ring.roundLayout == false and ring.snapToPixelGrid == false and ring.texelSnappingBias == 0,
    "ring must retain fractional atlas geometry instead of snapping through the mask")

Near(ring.texCoord[1], 0, "ring left coord")
Near(ring.texCoord[2], 1, "ring right coord")
Near(ring.texCoord[3], 0, "ring top coord")
Near(ring.texCoord[4], 1, "ring bottom coord")
assert(holder.blizzRingMirror == nil, "the contour must be one continuous texture")
assert(holder.blizzRingMask == nil and not ring.masks, "circle clipping would cut away the lower-right corner")
assert(ring.allPoints == holder and holder.mask.allPoints == holder,
    "mask and rim must share bounds to prevent portrait bleed or clipping")
local color = ring.vertexColor
assert(color and color[1] == 1 and color[2] == 1 and color[3] == 1 and color[4] == 1,
    "Blizzard ring must stay untinted")
-- Retired overlays must not paint across the original contour on reused holders.
holder.blizzRingMirror = NewRegion(holder.border)
holder.blizzCorner = NewRegion(holder.border)
Portrait.Apply(frame, frame.MSUFSpec)
assert(not holder.blizzRingMirror.shown and not holder.blizzCorner.shown, "obsolete overlays must stay hidden")

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

-- 4) Preview uses the same bounds even at fractional sizes.
do
    local ns = { MSUF2 = { PreviewHelpers = {} }, Client = { IsRetail = true, IsForever = true } }
    ns.MSUF2.PickFallbackTable = function(deps, defaults)
        return setmetatable({}, { __index = function(_, key) return deps[key] or defaults[key] end })
    end
    assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"))("Options", ns)
    local preview = {}
    ns.UFPreviewRender.Install(preview, {})
    local render = preview.RefreshDeps._RenderState
    local portrait = NewRegion()
    portrait.tex, portrait.bg = NewRegion(portrait), NewRegion(portrait)
    render.ApplyPreviewPortraitShapeMask(portrait, "BLIZZARD", 0)
    assert(portrait._msufPreviewShapeMask.texture == MASK_FILE, "preview must use the matching player mask")
    render.LayoutPreviewBlizzardPortrait(portrait, true, 58, 58)
    assert(portrait._msufPreviewBlizzCorner == nil, "native branch must not receive a second joint overlay")
    portrait._msufPreviewBlizzCorner = NewRegion(portrait)
    for _, size in ipairs({ 36, 58, 73.5 }) do
        render.LayoutPreviewBlizzardPortrait(portrait, true, size, size)
        local art = assert(portrait._msufPreviewBlizzRing)
        assert(art.roundLayout == false and art.snapToPixelGrid == false and art.texelSnappingBias == 0,
            "native art must retain fractional atlas geometry")
        assert(not portrait._msufPreviewBlizzCorner.shown, "preview must hide a reused overlay")
        assert(not portrait._msufPreviewBlizzMirror and not portrait._msufPreviewBlizzClip and not art.masks,
            "preview must preserve the native branch without mirroring or clipping")
        Near(art.texCoord[1], 0, "preview contour left")
        Near(art.texCoord[2], 1, "preview contour right")
        assert(art.allPoints == portrait and portrait._msufPreviewShapeMask.allPoints == portrait,
            "preview must anchor the mask and border to identical bounds")
    end
end
_G.C_Texture = nil
local noAtlas = LoadElement()
local noAtlasFrame = NewFrame("BLIZZARD")
noAtlas.Create(noAtlasFrame)
noAtlas.Apply(noAtlasFrame, noAtlasFrame.MSUFSpec)
assert(noAtlasFrame.MSUFPortraitHolder.blizzRing.texture == RING_FILE,
    "standalone art must not depend on client atlas availability")
-- Actual asset pixels: the corner is filled, its outer tip is rounded, the
-- other quadrants stay circular, and the mask ends below the opaque stroke.
do
    local function AssetAlpha(path)
        local h = assert(io.open(path, "rb")); local data = h:read("*a"); h:close()
        assert(data:byte(3) == 2 and data:byte(17) == 32 and data:byte(18) == 40,
            "expected top-origin 32-bit TGA")
        local w = data:byte(13) + data:byte(14) * 256
        local hgt = data:byte(15) + data:byte(16) * 256
        assert(w == 256 and hgt == 256 and #data == 18 + w * hgt * 4)
        return function(x, y) return data:byte(18 + (y * w + x) * 4 + 4) end
    end
    local mask = AssetAlpha("MidnightSimpleUnitFrames/Media/Masks/portrait_blizzard_mask.tga")
    local rim = AssetAlpha("MidnightSimpleUnitFrames/Media/Borders/msuf_portrait_ring_blizzard.tga")
    assert(mask(234, 234) == 255, "portrait must fill its lower-right extension")
    assert(mask(21, 21) == 0 and mask(234, 21) == 0 and mask(21, 234) == 0,
        "other three quadrants must remain circular")
    assert(rim(248, 128) == 255 and rim(128, 248) == 255 and rim(247, 247) == 255,
        "right and bottom strokes must join around the corner")
    assert(mask(251, 251) == 0 and rim(251, 251) == 0, "outer tip must be rounded")
    assert(mask(247, 128) > 0 and rim(247, 128) == 255, "mask antialiasing must end under the opaque rim")
end
-- Settings compose on the same holder; native portrait refreshes retain the
-- configured crop, and panning never moves the contour or its click bounds.
do
    local portrait, ns, alpha = LoadElement()
    local shared, layers = ns.UF.Shared, ns.UF.Layers
    local test = NewFrame("BLIZZARD")
    test:SetFrameLevel(20)
    test.Health:SetFrameLevel(21)
    test.hpBar = test.Health
    test.MSUFSpec.alpha = { active = true, hpAlpha = .6, excludeTextPortrait = true }
    local p = test.MSUFSpec.portrait
    local function Apply()
        portrait.Apply(test, test.MSUFSpec)
        alpha.Apply(test, test.MSUFSpec)
    end
    for _, shape in ipairs({ "BLIZZARD", "CIRCLE", "SQUARE", "ROUNDED", "DIAMOND" }) do
        p.shape = shape
        for _, opacity in ipairs({ 1, .37, 0, 1 }) do
            p.alpha = opacity
            test.MSUFSpec.alpha.excludeTextPortrait = true
            Apply()
            Near(test.MSUFPortraitHolder:GetAlpha(), opacity, "own portrait opacity")
            test.MSUFSpec.alpha.excludeTextPortrait = false
            Apply()
            Near(test.MSUFPortraitHolder:GetAlpha(), opacity * .6, "composed opacity")
            portrait.Apply(test, test.MSUFSpec)
            Near(test.MSUFPortraitHolder:GetAlpha(), opacity * .6, "portrait-only reapply")
            alpha.Disable(test)
            Near(test.MSUFPortraitHolder:GetAlpha(), opacity, "alpha reset retains own opacity")
        end
        for _, level in ipairs({ 0, 1, 7, 30, 0 }) do
            p.levelOffset = level
            Apply()
            local h = test.MSUFPortraitHolder
            if level == 0 then
                assert(h:GetFrameLevel() < 21 and h.border:GetFrameLevel() < 21,
                    "layer 0 portrait and rim must be behind health")
            else Near(h:GetFrameLevel(), layers.ElementLevel(level, 7, 0), "foreground layer") end
        end
        for _, zoom in ipairs({ 100, 110, 150, 200 }) do
            for _, pan in ipairs({ -100, 0, 100 }) do
                shared.CompilePortraitTexCoords(p, zoom, 60, 60, pan, -pan)
                Apply()
                local h, tex = test.MSUFPortraitHolder, test.portrait
                if shape == "BLIZZARD" and zoom == 100 then
                    Near(tex._msufImageX, -pan / 100 * .08 * 60, "unzoomed pan X")
                    Near(tex._msufImageY, pan / 100 * .08 * 60, "unzoomed pan Y")
                end
                assert(p.texL >= -1e-12 and p.texR <= 1 + 1e-12
                    and p.texT >= -1e-12 and p.texB <= 1 + 1e-12, "bounded crop")
                if pan ~= 0 then
                    local imageX = (0.5 - p.texL) / (p.texR - p.texL) * 60 + tex._msufImageX
                    local imageY = -(0.5 - p.texT) / (p.texB - p.texT) * 60 + tex._msufImageY
                    assert((imageX - 30) * pan < 0 and (imageY + 30) * pan > 0,
                        "pan direction must stay consistent across zoom")
                end
                test._msufPortraitForceRefresh = true
                local before = portraitCalls
                portrait.Apply(test, test.MSUFSpec)
                assert(portraitCalls == before + 1, "forced native refresh")
                for i, expected in ipairs({ p.texL, p.texR, p.texT, p.texB }) do
                    Near(tex.texCoord[i], expected, "native refresh preserves crop")
                end
                portrait.Apply(test, test.MSUFSpec)
                assert(portraitCalls == before + 1, "unchanged apply must not resolve native portrait")
                assert(h.mask.allPoints == h, "mask must stay fixed when the image pans")
                if shape == "BLIZZARD" then assert(h.blizzRing.allPoints == h, "rim must stay fixed") end
            end
        end
    end
    p.shape = "BLIZZARD"
    shared.CompilePortraitTexCoords(p, 100, 60, 60, 100, 100)
    Apply()
    assert(test.portrait._msufImageX ~= 0 and test.portrait._msufImageY ~= 0)
    p.render = "CLASS"
    Apply()
    Near(test.portrait._msufImageX, 0, "class render resets pan X")
    Near(test.portrait._msufImageY, 0, "class render resets pan Y")

    -- Exercise the actual final transparency pass, which previously replaced
    -- the portrait renderer's alpha with the frame foreground alpha.
    ns.MSUF2 = { PreviewHelpers = {} }
    ns.UFPreview = { Model = { Clamp01 = ns.UF.Clamp01 } }
    assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua"))("Options", ns)
    local mock = NewRegion()
    mock.portrait = NewRegion(mock)
    local box = { mock = mock }
    for _, opacity in ipairs({ 0, 37, 100 }) do
        for _, exclude in ipairs({ false, true }) do
            ns.UFPreview.ApplyPreviewTransparency(box,
                { portraitAlpha = opacity, hpBarAlpha = .6, alphaExcludeTextPortrait = exclude },
                { portrait = { alpha = opacity / 100 }, alpha = { hpAlpha = .6, excludeTextPortrait = exclude } })
            Near(mock.portrait:GetAlpha(), opacity / 100 * (exclude and 1 or .6), "preview opacity composition")
        end
    end
end
-- Dragon overlay uses the same painter for live and preview, with no mask and
-- no classification reads/event registration while the opt-in is disabled.
do
    local gold = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"
    local silver = "ui-hud-unitframe-target-portraiton-boss-rare-silver"
    local winged = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged"
    local infos = {
        [gold] = { width = 80, height = 90 },
        [silver] = { width = 82, height = 92 },
        [winged] = { width = 112, height = 100 },
    }
    _G.C_Texture = { GetAtlasInfo = function(atlas) return infos[atlas] end }
    local classification, reads = "elite", 0
    _G.UnitClassification = function() reads = reads + 1; return classification end
    local portrait = LoadElement()
    local frame = NewFrame("BLIZZARD")
    frame.MSUFUnitKey = "target"
    local p = frame.MSUFSpec.portrait
    portrait.Apply(frame, frame.MSUFSpec)
    local holder = frame.MSUFPortraitHolder
    assert(not holder.blizzElite and reads == 0, "default must not allocate/query dragon")
    local function HasClassificationEvent()
        for _, event in ipairs(portrait.GetEvents(frame, frame.MSUFSpec)) do
            if event == "UNIT_CLASSIFICATION_CHANGED" then return true end
        end
    end
    assert(not HasClassificationEvent(), "disabled dragon must not register classification event")
    p.blizzardElite = true
    portrait.Apply(frame, frame.MSUFSpec)
    local dragon = assert(holder.blizzElite, "elite dragon missing")
    assert(HasClassificationEvent(), "classification changes must refresh dragon")
    assert(dragon.atlas == gold and dragon.shown and not dragon.masks, "unclipped gold dragon")
    assert(dragon.parent == holder.border and dragon.sublevel > holder.blizzRing.sublevel,
        "dragon must sit above rim and share portrait opacity/layer")
    Near(dragon.points[1][4], 15 * 60 / 58, "native dragon X")
    Near(dragon.points[1][5], 11 * 60 / 58, "native dragon Y")
    local before = portraitCalls
    for _, state in ipairs({ "rareelite", "rare", "worldboss", "normal", "minus", "elite" }) do
        classification = state
        portrait.Update(frame, "UNIT_CLASSIFICATION_CHANGED", "target")
        local expected = state == "worldboss" and winged or (state == "elite" and gold)
            or ((state == "rare" or state == "rareelite") and silver)
        assert(dragon.shown == not not expected, "classification visibility " .. state)
        if expected then
            assert(dragon.atlas == expected, "classification atlas " .. state)
            Near(dragon.width, infos[expected].width * 60 / 58, "atlas size switch")
        end
        assert(portraitCalls == before, "classification event must not re-render portrait")
    end
    classification = "normal"
    portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
    assert(not dragon.shown, "normal target switch must clear dragon")
    classification = "rareelite"
    portrait.Update(frame, "MSUF_UNIT_IDENTITY_VISUAL", "target")
    assert(dragon.shown and dragon.atlas == silver, "identity handoff must refresh dragon")
    -- Runtime preview paints the registered live frame, independent of its NPC.
    local runtime, runtimeNS = LoadElement()
    local focus = NewFrame("BLIZZARD")
    focus.MSUFUnitKey = "focus"; focus.MSUFSpec.portrait.blizzardElite = true
    runtime.Apply(focus, focus.MSUFSpec)
    runtimeNS.UF.ForEachFrame = function(fn) fn(frame); fn(focus) end
    classification = "normal"
    runtime.Apply(frame, frame.MSUFSpec); runtime.Apply(focus, focus.MSUFSpec)
    local beforePreview = portraitCalls
    for _, state in ipairs({ "elite", "rare", "rareelite", "worldboss" }) do
        assert(runtime.SetClassificationPreview("target", state))
        local expected = state == "elite" and gold or state == "worldboss" and winged or silver
        assert(dragon.shown and dragon.atlas == expected, "live runtime preview " .. state)
        assert(not focus.MSUFPortraitHolder.blizzElite.shown, "preview scope isolation")
        runtime.Update(frame, "UNIT_CLASSIFICATION_CHANGED", "target")
        assert(dragon.shown and dragon.atlas == expected, "real events retain selected preview")
    end
    assert(portraitCalls == beforePreview, "preview must not resolve the native portrait")
    local driver = lastCreatedFrame
    assert(driver.events.PLAYER_REGEN_DISABLED, "preview subscribes to combat stop")
    classification = "rareelite"
    runtime.SetClassificationPreview("focus", "elite")
    assert(dragon.atlas == silver and dragon.shown, "scope switch restores old frame")
    assert(focus.MSUFPortraitHolder.blizzElite.atlas == gold, "new scope uses preview")
    driver.scripts.OnEvent(driver, "PLAYER_REGEN_DISABLED")
    assert(not runtime.GetClassificationPreview("focus") and not driver.events.PLAYER_REGEN_DISABLED,
        "combat clears session and listener")
    assert(focus.MSUFPortraitHolder.blizzElite.atlas == silver, "combat restores real classification")
    _G.InCombatLockdown = function() return true end
    assert(not runtime.SetClassificationPreview("target", "elite"), "combat cannot start preview")
    _G.InCombatLockdown = function() return false end
    runtime.SetClassificationPreview("target", "elite")
    p.shape = "CIRCLE"; runtime.Apply(frame, frame.MSUFSpec)
    assert(not dragon.shown, "runtime preview respects selected shape")
    p.shape = "BLIZZARD"; p.blizzardElite = false; runtime.Apply(frame, frame.MSUFSpec)
    assert(not dragon.shown, "runtime preview respects opt-in")
    p.blizzardElite = true; runtime.Apply(frame, frame.MSUFSpec)
    runtime.SetClassificationPreview("target", "OFF")
    assert(dragon.atlas == silver and dragon.shown and not runtime.GetClassificationPreview("target"),
        "Off restores live classification")
    -- Existing boss test mode receives boss art even without a real boss token.
    focus.MSUFUnitKey = "boss1"; focus._msufBossPreviewForced = true
    _G.UnitExists = function(unit) return unit ~= "boss1" end
    local bossRuntime = LoadElement()
    bossRuntime.Apply(focus, focus.MSUFSpec)
    assert(focus.MSUFPortraitHolder.blizzElite.atlas == winged, "boss test-mode portrait decoration")
    focus._msufBossPreviewForced = nil
    bossRuntime.Update(focus, "UNIT_CLASSIFICATION_CHANGED", "boss1")
    assert(focus.MSUFPortraitHolder.blizzElite.atlas == silver, "boss preview off restores identity")
    _G.UnitExists = function() return true end
    local secret = {}
    _G.issecretvalue = function(v) return v == secret end
    -- Load another element so its native secret guard binds the fixture.
    local guarded = LoadElement()
    classification = secret
    guarded.Apply(frame, frame.MSUFSpec)
    assert(not dragon.shown, "restricted classification must hide without indexing")
    _G.issecretvalue = function() return false end
    classification = "elite"
    p.blizzardElite = false
    before = reads
    portrait.Apply(frame, frame.MSUFSpec)
    assert(not dragon.shown and reads == before, "toggle off must clear and stop sampling")
    p.blizzardElite = true; p.shape = "CIRCLE"
    portrait.Apply(frame, frame.MSUFSpec)
    assert(not dragon.shown and not HasClassificationEvent(), "other shapes must not inherit dragon")
    p.shape = "BLIZZARD"
    portrait.Apply(frame, frame.MSUFSpec)
    portrait.AcquirePositionAnchor(frame, p)
    assert(not dragon.shown, "invisible portrait anchor must clear dragon")
    portrait.Apply(frame, frame.MSUFSpec)
    portrait.Disable(frame)
    assert(not dragon.shown, "portrait disable must clear dragon")
    local preview = NewRegion()
    preview.border = NewRegion(preview)
    portrait.PaintClassification(preview, true, "rareelite", 116, 87, preview)
    assert(preview.blizzElite.atlas == silver and preview.blizzElite.shown, "preview silver dragon")
    assert(preview.blizzElite.parent == preview, "preview must avoid hidden geometric border")
    Near(preview.blizzElite.width, 82 * 2, "preview scaled width")
    Near(preview.blizzElite.height, 92 * 1.5, "preview scaled height")
    -- Missing client atlas: no error texture, no stale dragon and retryable.
    _G.C_Texture.GetAtlasInfo = function() return nil end
    local unavailable = LoadElement()
    unavailable.PaintClassification(preview, true, "elite", 60, 60)
    assert(not preview.blizzElite.shown, "missing atlas must hide stale decoration")
    _G.C_Texture.GetAtlasInfo = function(atlas) return infos[atlas] end
    unavailable.PaintClassification(preview, true, "elite", 60, 60)
    assert(preview.blizzElite.shown, "atlas availability must be retryable")
end
print("portrait_contour_smoke: OK (contour, settings, elite/rare dragons, events, preview)")
