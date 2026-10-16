-- Runtime rules must be called by the real menu painters, including after a
-- rule changes. A matching copy cannot satisfy the call identity assertions.
local root = assert(arg[1], "root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", beforeCore = function(world)
    world.env.RAID_CLASS_COLORS = { MAGE = { r = .2, g = .5, b = .8 } }
end })
local core, env, M = mw.core, mw.env, mw.M
local UF, Config = core.UF, core.UF.Config
local Portrait, Colors, Castbars = UF.elements.Portrait, core.ClassPowerColors, core.Castbars.Visuals
-- IsShown only describes the region itself; native visibility also inherits
-- every owner's shown state. Exercise the real constructors and cached paths.
local function ActualVisible(region)
    if not region then return false end
    while region do
        if not region:IsShown() then return false end
        region = region:GetParent()
    end
    return true
end
local function CheckPortraitDecorationVisibility()
    local failures = {}
    local function Check(ok, label)
        if not ok then failures[#failures + 1] = label end
    end
    local previousAtlasInfo = env.C_Texture.GetAtlasInfo
    env.C_Texture.GetAtlasInfo = function()
        return { width = 80, height = 90, leftTexCoord = .1, rightTexCoord = .8, topTexCoord = .2, bottomTexCoord = .9 }
    end
    local function Decoration(region, label, sublevel)
        if not region then return end
        Check(region:GetObjectType() == "Texture", label .. " is not an owned texture")
        local layer, sub = region:GetDrawLayer()
        Check(layer == "OVERLAY" and sub == sublevel, label .. " draw layer changed")
    end
    local Preview = core.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show()
    box.canvas:SetSize(600, 260)
    local conf = env.MSUF_DB.player
    local saved = {}
    for key, value in pairs(conf) do saved[key] = value end
    conf.portraitMode, conf.portraitRender = "LEFT", "CLASS"
    conf.portraitWidth, conf.portraitHeight, conf.portraitSizeMode = 73, 47, "SEPARATE"
    conf.portraitBorderStyle, conf.portraitBorderThickness = "CUSTOM", 3
    conf.portraitBlizzardCorner = true
    local function Paint(shape, art, enabled)
        conf.portraitShape, conf.portraitBorderArt = shape, art
        conf.portraitBorderStyle = enabled and "CUSTOM" or "NONE"
        Config.Refresh()
        Preview.Refresh(box, "DECORATION_VISIBILITY")
        return box.mock.portrait
    end
    local portrait = Paint("SQUARE", "SOLID", true)
    local border, edges = portrait.border, portrait.border.edges
    local edgeKey = edges[1] and 1 or "top"
    local first = assert(edges[edgeKey], "square edges missing")
    local handleParent = box.handlePortrait:GetParent()
    Check(ActualVisible(first), "square edge inherits a hidden owner")
    Paint("SQUARE", "SOLID", false)
    Check(not border:IsShown() and not ActualVisible(first), "NONE left straight edges visible")
    local relief, ring, mask, stock, corner
    for pass = 1, 2 do
        for _, shape in ipairs({ "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND" }) do
            Paint(shape, "RELIEF", true)
            local art = portrait._msufPreviewArtBorder
            Check(not border:IsShown(), shape .. " relief showed the straight host")
            Check(ActualVisible(art), shape .. " relief inherits a hidden owner")
            Check(art and art:GetParent() == portrait, shape .. " relief owner is not the portrait")
            if relief then Check(art == relief, "relief transition recreated its texture") end
            relief = art
            Decoration(art, "relief", 2)
            Check(art and select(2, art:GetPoint(1)) == portrait, "relief anchor owner changed")
            Paint(shape, "RELIEF", false)
            Check(not ActualVisible(art), shape .. " NONE left relief visible")
            if shape ~= "SQUARE" then
                Paint(shape, "SOLID", true)
                local currentRing = portrait._msufPreviewShapeRing
                local currentMask = portrait._msufPreviewShapeRingMask
                Check(not border:IsShown() and ActualVisible(currentRing), shape .. " solid ring visibility")
                Check(ActualVisible(currentMask), shape .. " mask inherits a hidden owner")
                if ring then Check(currentRing == ring and currentMask == mask, "shape transition recreated ring/mask") end
                ring, mask = currentRing, currentMask
            end
        end
        Paint("BLIZZARD", "SOLID", true)
        local legacy = core.Client.IsVanilla == true
        local currentStock = legacy and portrait._msufPreviewBlizzFallback or portrait._msufPreviewBlizzRing
        local currentCorner = portrait._msufPreviewBlizzCorner
        Check(not border:IsShown(), "stock dressing showed the straight host")
        Check(ActualVisible(currentStock), "stock " .. (legacy and "fallback" or "ring") .. " inherits a hidden owner")
        Check(currentStock and currentStock:GetParent() == portrait, "stock owner is not the portrait")
        if legacy then
            Check(not ActualVisible(currentCorner), "Classic stock created a native corner")
            Check(not ActualVisible(portrait._msufPreviewBlizzRing), "Classic stock created a native ring")
        else
            Check(ActualVisible(currentCorner), "stock corner inherits a hidden owner")
            Check(currentCorner and currentCorner:GetParent() == portrait, "stock corner owner is not the portrait")
        end
        if stock then Check(currentStock == stock and currentCorner == corner, "stock transition recreated decoration") end
        stock, corner = currentStock, currentCorner
        Decoration(stock, "stock", 2)
        Decoration(corner, "corner", 3)
        if corner then Check(select(2, corner:GetPoint(1)) == portrait, "corner anchor owner changed") end
        portrait:Hide()
        Check(not ActualVisible(currentStock) and not ActualVisible(currentCorner), "hidden portrait leaked decoration")
        portrait:Show()
        Check(ActualVisible(currentStock), "showing portrait did not restore stock dressing")
        Paint("SQUARE", "SOLID", false)
        Check(not border:IsShown() and not ActualVisible(stock) and not ActualVisible(corner), "NONE left stock visible")
        Paint("SQUARE", "SOLID", true)
        Check(ActualVisible(first) and border:IsShown(), "same-key square border did not restore")
        Check(portrait.border == border and border.edges == edges and edges[edgeKey] == first, "square transition recreated edges")
        Check(not ActualVisible(relief) and not ActualVisible(ring), "square left another renderer visible")
        Check(box.handlePortrait:GetParent() == handleParent, "portrait controls changed owner")
    end
    for key in pairs(conf) do conf[key] = nil end
    for key, value in pairs(saved) do conf[key] = value end
    Config.Refresh()
    box:Hide()
    env.C_Texture.GetAtlasInfo = previousAtlasInfo
    assert(#failures == 0, "portrait ancestor visibility: " .. table.concat(failures, "; "))
    print("portrait ancestor visibility: ok (" .. flavor .. "; relief, stock, masks, NONE and cached restoration)")
end
CheckPortraitDecorationVisibility()
if arg[3] == "visibility" then return end

assert(type(Portrait.PaintBorder) == "function", "runtime portrait border painter is not exported")
assert(type(Portrait.PaintBlizzardBorder) == "function", "runtime stock portrait painter is not exported")
assert(type(Portrait.RingInflation) == "function", "runtime relief geometry is not exported")
assert(type(Config.DarkTint) == "function", "runtime dark tint is not exported")
assert(type(Config.ClassColor) == "function", "runtime class colour is not exported")
assert(Colors and type(Colors.ResolveSlotColor) == "function", "runtime slot colour is not exported")
assert(type(Colors.ResolveFullColor) == "function", "runtime full colour is not exported")
assert(type(Castbars.ApplyIconZoom) == "function", "runtime castbar zoom is not exported")
assert(type(Castbars.PaintIconBorder) == "function", "runtime castbar icon border is not exported")
assert(type(Castbars.DetailNum) == "function" and type(Castbars.DetailString) == "function", "runtime details are not exported")
local defaultX, defaultY = core.UFPreviewRender.PreviewPortraitRingInflation(nil)
assert(defaultX == 3 and defaultY == 3, "optional portrait relief inputs changed")

local function Near(a, b, label)
    assert(type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-7,
        label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function Calls(fn, run, label)
    local calls = 0
    debug.sethook(function()
        if debug.getinfo(2, "f").func == fn then calls = calls + 1 end
    end, "c")
    run()
    debug.sethook()
    assert(calls > 0, label .. " bypassed the runtime function")
    return calls
end
local Preview = core.UFPreview
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return "player" end
local box = Preview._BuildPreview(parent, panel, 900, 400)
box:Show()
box.canvas:SetSize(600, 260)
do
    Preview.Refresh(box, "INITIAL_BORDER_LIFECYCLE")
    local initial = box.mock.portrait
    assert(not initial.border:IsShown() and #initial.border.edges == 0,
        "initial menu border must stay hidden and lazy: shown=" .. tostring(initial.border:IsShown())
            .. ", edges=" .. #initial.border.edges)
    local render = Preview.RefreshDeps._RenderState
    local function Surface(shape, art)
        local portrait = env.CreateFrame("Frame", nil, env.UIParent)
        portrait:SetSize(73, 47)
        portrait.border = env.CreateFrame("Frame", nil, portrait)
        portrait.border:SetAllPoints(portrait)
        portrait.border.edges = {}
        portrait._msufPreviewBorderShape, portrait._msufPreviewBorderArt = shape, art
        return portrait
    end
    for _, shape in ipairs({ "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND", "BLIZZARD" }) do
        for _, art in ipairs({ "SOLID", "RELIEF" }) do
            local portrait = Surface(shape, art)
            render.LayoutPreviewBlizzardPortrait(portrait, shape == "BLIZZARD", 73, 47)
            render.LayoutPreviewPortraitBorder(portrait, 3, false)
            assert(not portrait.border:IsShown() and #portrait.border.edges == 0, shape .. " disabled border allocated edges")
            render.LayoutPreviewPortraitBorder(portrait, 3, false, .2, .4, .6, .7)
            local straight = shape == "SQUARE" and art == "SOLID"
            assert(portrait.border:IsShown() == straight, shape .. " border host ownership")
            assert(#portrait.border.edges == (straight and 4 or 0), shape .. " unused border edges")
            assert(portrait.edges == portrait.border.edges, "preview edge alias lost")
        end
    end
    local portrait = Surface("SQUARE", "SOLID")
    local function Paint(shape, art, enabled)
        portrait._msufPreviewBorderShape, portrait._msufPreviewBorderArt = shape, art
        render.LayoutPreviewBlizzardPortrait(portrait, shape == "BLIZZARD", 73, 47)
        render.LayoutPreviewPortraitBorder(portrait, 3, false, enabled and .2 or nil, .4, .6, .7)
    end
    Paint("SQUARE", "SOLID", true)
    local edges = portrait.edges
    local first = edges[1]
    Paint("CIRCLE", "SOLID", true)
    assert(not portrait.border:IsShown() and portrait.ring:IsShown(), "shaped ring must own visibility")
    assert(portrait._msufPreviewShapeRing == portrait.ring, "preview ring alias lost")
    Paint("SQUARE", "RELIEF", true)
    assert(not portrait.border:IsShown() and portrait.artBorder:IsShown(), "relief must own visibility")
    assert(portrait._msufPreviewArtBorder == portrait.artBorder, "preview relief alias lost")
    Paint("SQUARE", "SOLID", false)
    assert(not portrait.border:IsShown() and not portrait.artBorder:IsShown(), "disabled border host stayed visible")
    Paint("SQUARE", "SOLID", true)
    assert(portrait.border:IsShown() and first:IsShown(), "cached straight border did not restore")
    assert(portrait.edges == edges and edges[1] == first and #edges == 4, "shape switch recreated edges")
    assert(not portrait.ring:IsShown() and not portrait.artBorder:IsShown(), "old border renderer stayed shown")
    portrait._msufPreviewBorderShape = "BLIZZARD"
    render.LayoutPreviewBlizzardPortrait(portrait, true, 60, 60)
    assert(portrait._msufLayoutWidth == 60 and portrait._msufLayoutHeight == 60, "explicit stock dimensions were ignored")
    assert(not portrait.border:IsShown() and not first:IsShown(), "stock border left the straight host visible")
    Paint("SQUARE", "SOLID", true)
    assert(portrait.border:IsShown() and first:IsShown() and edges[1] == first, "stock switch did not restore cached edges")
end
local conf = env.MSUF_DB.player
conf.portraitMode, conf.portraitRender, conf.portraitShape = "LEFT", "CLASS", "ROUNDED"
conf.portraitBorderStyle, conf.portraitBorderArt = "CUSTOM", "RELIEF"
conf.portraitWidth, conf.portraitHeight, conf.portraitSizeMode = 73, 47, "SEPARATE"
Config.Refresh()
Calls(Portrait.PaintBorder, function() Preview.Refresh(box, "SHARED_RULES") end, "unit portrait")
local art = assert(box.mock.portrait.artBorder, "shared unit relief texture missing")
assert(art:IsShown(), "unit relief was not painted")
assert(art.texture == core.UFVisuals.PORTRAIT_RING_ART.ROUNDED, "unit used another relief asset")
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame:SetSize(275, 40)
frame.MSUFUnitKey = "player"
frame.Health = env.CreateFrame("StatusBar", nil, frame)
frame.Health:SetSize(275, 40)
frame.hpBar = frame.Health
frame.MSUFSpec = Config.GetSpec("player")
Calls(Portrait.PaintBorder, function() Portrait.Apply(frame, frame.MSUFSpec) end, "live portrait")
assert(frame.MSUFPortraitHolder.artBorder.texture == art.texture, "live and menu relief differ")

-- A changed shared asset must reach both consumers without recompiling code.
local assets = core.UFVisuals.PORTRAIT_RING_ART
local prior = assets.ROUNDED
assets.ROUNDED = "shared-relief-test"
conf.portraitBorderDirection = "RIGHT"
Config.Refresh()
frame.MSUFSpec = Config.GetSpec("player")
Portrait.Apply(frame, frame.MSUFSpec)
Preview.Refresh(box, "SHARED_ASSET_CHANGE")
assert(frame.MSUFPortraitHolder.artBorder.texture == "shared-relief-test", "live ignored changed rule")
assert(box.mock.portrait.artBorder.texture == "shared-relief-test", "preview kept a relief copy")
assets.ROUNDED = prior

-- Group portraits adapt only scale and sample identity. They call the same
-- painter as live portraits, including cached shape/style transitions.
local party = env.MSUF_DB.gf_party
party.portraitMode, party.portraitShape, party.portraitRender = "LEFT", "ROUNDED", "CLASS"
party.portraitBorderStyle, party.portraitBorderArt = "CLASS_COLOR", "RELIEF"
core.GF.InvalidateCompiledSpecs("party")
local groupSpec = core.GF.CompileSpec("party", nil, "party1")
local groupMock = env.CreateFrame("Frame", nil, env.UIParent)
groupMock:SetSize(180, 48)
local groupScene = { kind = "party", mock = groupMock, runtimeSpec = groupSpec,
    layerAvailable = {}, layerVisible = {}, previewScale = .75, liveData = { class = "MAGE" }, box = {}, MSUF = core,
    S = { Layers = UF.Layers, ScaleValue = function(v, scale) return math.floor(v * scale + .5) end } }
Calls(Portrait.PaintBorder, function() M.GroupPreviewRender.PaintGroupPreviewPortrait(groupScene) end, "group portrait")
assert(groupMock._msufGroupPortrait.artBorder:IsShown(), "group relief hidden")
assert(groupMock._msufGroupPortrait.artBorder.texture == prior, "group relief asset differs")
groupSpec.portrait.enabled = false
M.GroupPreviewRender.PaintGroupPreviewPortrait(groupScene)
assert(not groupMock._msufGroupPortrait.artBorder:IsShown(), "disabled group relief stayed shown")
groupSpec.portrait.enabled = true
M.GroupPreviewRender.PaintGroupPreviewPortrait(groupScene)
assert(groupMock._msufGroupPortrait.artBorder:IsShown(), "group relief did not restore after disabling the portrait")

-- Pin the real painter's geometry independently of either consumer. Every
-- mode is followed by a repeat and a transition, so stale regions also fail.
local holder = frame.MSUFPortraitHolder
local p = { shape = "SQUARE", border = { thickness = 3, fill = false } }
holder._msufLayoutWidth, holder._msufLayoutHeight = 73, 47
for _, shape in ipairs({ "SQUARE", "CIRCLE", "ROUNDED", "DIAMOND" }) do
    for _, relief in ipairs({ false, true }) do
        for _, fill in ipairs({ false, true }) do
            p.shape, p.border.art, p.border.fill = shape, relief and "RELIEF" or "SOLID", fill
            p.border.direction = "LEFT"
            for repeatPaint = 1, 2 do
                Portrait.PaintBorder(holder, p, .2, .4, .6, .7)
                if relief then
                    assert(holder.artBorder:IsShown() and not holder.edges[1]:IsShown(), "relief transition")
                    Near(select(4, holder.artBorder:GetPoint(1)), -10, "73px relief X")
                    Near(select(5, holder.artBorder:GetPoint(1)), 7, "47px relief Y")
                elseif shape ~= "SQUARE" then
                    assert(holder.ring:IsShown() and not holder.artBorder:IsShown(), "shape transition")
                    assert(holder.ringMask.texture == core.UFVisuals.PORTRAIT_MASKS[shape], "shape mask")
                else
                    assert(holder.edges[1]:IsShown() and not holder.artBorder:IsShown(), "edge transition")
                    Near(select(4, holder.edges[1]:GetPoint(1)), fill and 0 or -3, "edge pad")
                end
            end
            Portrait.PaintBorder(holder, p)
            assert(not holder.edges[1]:IsShown() and not holder.artBorder:IsShown(), "hidden border transition")
            assert(not holder.ring or not holder.ring:IsShown(), "hidden ring transition")
        end
    end
end

local cp = M.ClassPowerPreview
local bars, general = env.MSUF_DB.bars, env.MSUF_DB.general
bars.classPowerSlotColorModes = { COMBO_POINTS = "custom", HOLY_POWER = "custom" }
general.classPowerColorOverrides = { COMBO_POINTS_2 = { .1, .3, .7 }, HOLY_POWER_FULL = { .4, .6, .8 } }
local config = { slotColorModes = bars.classPowerSlotColorModes, colorOverrides = general.classPowerColorOverrides }
local cr, cg, cb = cp.ResolveSlotColor(bars, "COMBO_POINTS", 2, .2, .4, .6)
Near(cr, .1, "custom slot R")
Near(cg, .3, "custom slot G")
Near(cb, .7, "custom slot B")
local legacyRamp = { classPowerComboPointColorMode = "ramp" }
local rr, rg, rb = cp.ResolveSlotColor(legacyRamp, "COMBO_POINTS", 1, .2, .4, .6)
Near(rr, 0, "legacy ramp R")
Near(rg, .95, "legacy ramp G")
Near(rb, 1, "legacy ramp B")
assert(Colors.ResolveSlotColor("COMBO_POINTS", 1, .2, .4, .6, {}) == nil, "runtime default mode contract changed")
local malformed = { classPowerSlotColorModes = 5, classPowerFullColorEnabled = 5 }
local mr, mg, mb = cp.ResolveSlotColor(malformed, "COMBO_POINTS", 2, .2, .4, .6)
Near(mr, .2, "invalid slot map R")
Near(mg, .4, "invalid slot map G")
Near(mb, .6, "invalid slot map B")
assert(cp.ResolveFullColor(malformed, "COMBO_POINTS", .2, .4, .6) == false, "invalid full map enabled colour")
for _, token in ipairs({ "COMBO_POINTS", "HOLY_POWER" }) do
    for slot = 1, 10 do
        local r, g, b = Colors.ResolveSlotColor(token, slot, .2, .4, .6, config)
        local pr, pg, pb
        Calls(Colors.ResolveSlotColor, function() pr, pg, pb = cp.ResolveSlotColor(bars, token, slot, .2, .4, .6) end, "slot preview")
        Near(pr, r, "slot R")
        Near(pg, g, "slot G")
        Near(pb, b, "slot B")
    end
end
bars.classPowerFullColorEnabled = { HOLY_POWER = true }
local full, r, g, b
Calls(Colors.ResolveFullColor, function() full, r, g, b = cp.ResolveFullColor(bars, "HOLY_POWER", 1, 1, 1) end, "full preview")
assert(full, "full colour lost")
Near(r, .4, "full R")
Near(g, .6, "full G")
Near(b, .8, "full B")

general.darkMode, general.darkBgCustomColor, general.darkBgBrightness = true, false, .4
Config.Refresh()
local dr, dg, db = Config.DarkTint(general, .2, .4, .6)
Near(dr, .08, "tint R")
Near(dg, .16, "tint G")
Near(db, .24, "tint B")
Calls(Config.ClassColor, function() Preview.Model.ClassColor("MAGE") end, "unit class colour")

-- Mock detail/zoom resolution must never query a unit or a live frame.
local detail = { castbarPlayerIconZoom = 150, castbarIconSize = 28 }
Near(core.UFPreviewCastbar.ReadNumber(detail, "player", "IconSize", nil, 18), 28, "global detail fallback")
Calls(Castbars.DetailNum, function() core.UFPreviewCastbar.ReadNumber(detail, "player", "IconZoom", nil, 100) end, "detail preview")
local tex = env.CreateFrame("Frame", nil, env.UIParent):CreateTexture()
Castbars.ApplyIconZoom(tex, 150)
Near(tex.texCoord[1], 1 / 6, "zoom left")
Near(tex.texCoord[2], 5 / 6, "zoom right")

general.enablePlayerCastbar, general.castbarPlayerShowIcon = true, true
general.castbarPlayerIconZoom, general.castbarPlayerIconBorderStyle = 150, "CASTBAR"
general.castbarPlayerIconBorderThickness = 3
general.castbarBorderR, general.castbarBorderG, general.castbarBorderB, general.castbarBorderA = .2, .4, .6, .8
Config.Refresh()
Calls(Castbars.ApplyIconZoom, function() Preview.Refresh(box, "SHARED_CAST_ZOOM") end, "unit cast zoom")
Calls(Castbars.PaintIconBorder, function() Preview.Refresh(box, "SHARED_CAST_BORDER") end, "unit cast border")
general.castbarPlayerIconBorderStyle = "NONE"
Preview.Refresh(box, "SHARED_CAST_NO_BORDER")
assert(box.mock.cast.icon:IsShown(), "disabling the icon border hid the preview icon")
general.castbarPlayerShowIcon = false
Preview.Refresh(box, "SHARED_CAST_NO_ICON")
assert(not box.mock.cast.icon:IsShown(), "disabled preview icon stayed visible")
general.castbarPlayerShowIcon, general.castbarPlayerIconBorderStyle = true, "CASTBAR"
mw:Select("opt_castbar")
local castPage = assert(M._msuf2CastbarPreview, "castbar page preview missing")
Calls(Castbars.PaintIconBorder, function() castPage:Refresh() end, "castbar page border")
Calls(Castbars.AnchorText, function() castPage:Refresh() end, "castbar page text")

local liveCast = env.CreateFrame("Frame", nil, env.UIParent)
liveCast:SetSize(250, 18)
liveCast.statusBar = env.CreateFrame("StatusBar", nil, liveCast)
liveCast.statusBar:SetSize(250, 18)
liveCast.icon = liveCast:CreateTexture()
liveCast._msufIsPreview = true
Calls(Castbars.ApplyIconZoom, function() Castbars.ApplyDetailLayout(liveCast, "player", general) end, "live cast zoom")
general.castbarPlayerIconBorderThickness = 4
Calls(Castbars.PaintIconBorder, function() Castbars.ApplyDetailLayout(liveCast, "player", general) end, "live cast border")
local border = assert(liveCast._msufDetailIconBorder)
assert(border:IsShown() and border.backdrop, "live icon border missing")
Near(border.backdropBorderColor[1], .2, "cast border R")
general.castbarPlayerIconBorderStyle = "NONE"
Castbars.ApplyDetailLayout(liveCast, "player", general)
assert(not border:IsShown(), "live icon border did not hide")
general.castbarPlayerIconBorderStyle = "CASTBAR"
Castbars.ApplyDetailLayout(liveCast, "player", general)
assert(border:IsShown() and border.backdrop, "same-key live border did not restore")
local supplied = env.CreateFrame("Frame", nil, env.UIParent, "BackdropTemplate")
supplied:Show()
local mockHost = { GetEffectiveScale = function() error("mock border queried a frame for scale") end }
Castbars.PaintIconBorder(supplied, mockHost, "CASTBAR", 4, general, 4, true)
Near(supplied.backdrop.edgeSize, 4, "supplied mock pixel edge")
Castbars.PaintIconBorder(supplied, mockHost, "NONE", 0, general, 0, true)
assert(supplied:IsShown(), "border painter changed preview-owned visibility")

-- Fractional mock scaling applies after the runtime's text padding. Rounding
-- the padding and coordinates separately would move this by one pixel.
local fs = liveCast:CreateFontString()
Calls(Castbars.AnchorText, function()
    core.UFPreviewCastbar.AnchorText(fs, liveCast, "LEFT", 1, 1, "LEFT", function(v) return math.floor(v * .5 + .5) end)
end, "scaled text")
Near(select(4, fs:GetPoint(1)), 2, "scaled padded text X")

local layout = UF.elements.Health.LayoutBackgroundFill
assert(type(layout) == "function", "runtime health background geometry missing")
for _, vertical in ipairs({ false, true }) do
    for _, reverse in ipairs({ false, true }) do
        for _, missing in ipairs({ false, true }) do
            conf.verticalFillBars, conf.reverseFillBars = vertical, reverse
            general.barBgFillMode = missing and "missing" or "full"
            Config.Refresh()
            Calls(layout, function() Preview.Refresh(box, "SHARED_HEALTH_FILL") end, "unit health background")
            local bg = box.mock.healthBackgroundBar
            local pct = box._msufPreviewScene.data.hp
            Near(bg.value, missing and (1 - pct) or 1, "background sample")
            assert(bg.orientation == (vertical and "VERTICAL" or "HORIZONTAL"), "background orientation")
            assert(bg.reverseFill == (missing and not reverse or not missing and reverse), "background direction")
        end
    end
end

-- The controller must use the exported resolver too; comparing two menu
-- wrappers alone would miss a new copy in the live visual compiler.
local CPWorld = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))()
local t = CPWorld.Start(root, flavor == "Forever" and "Mainline" or flavor, "ROGUE", 1, CPWorld.PT.ENERGY,
    { classPowerSlotColorModes = { COMBO_POINTS = "ramp" }, classPowerFullColorEnabled = { COMBO_POINTS = true } })
local liveColors = _G.MSUF_NS.ClassPowerColors
Calls(liveColors.ResolveSlotColor, _G.MSUF_ClassPower_Refresh, "live slot compiler")
Calls(liveColors.ResolveFullColor, _G.MSUF_ClassPower_Refresh, "live full compiler")
print("runtime_preview_shared_rules_smoke: ok (" .. flavor .. "; runtime/menu call identity, changed rule, portrait, CP, tint, details)")
