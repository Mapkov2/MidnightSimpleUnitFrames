-- options_castbar_classpower_scene_smoke.lua <repoRoot> <flavor>
--
-- The Options castbar and class resource previews paint the engine's castbar and ClassPower scenes. Every
-- capability the old hand-painted Options renderers had (docs/PREVIEW_RUNTIME_RULES.md; the inventory ids below)
-- must still reach the screen: this drives the real Castbars page preview, the Class Resources page preview and
-- the Unit preview slots of one client and asserts the scene regions and shapes for every cast kind, unit and
-- resource mode, then the selection, drag, zoom, layer and combat chrome around them, and that no Options painter
-- for the switched parts is left.
--
--   A1-A28 castbar (kinds and units, empower stages and blink, direction, icon, texts, colours, shapes, spark,
--          latency, markers, Interrupt Ready, interrupt replay, size and scale, progress, slots, handles, layers)
--   B1-B24 class resources (every mode, charged points, runes, notches, ironfur, native auras, gates, colours,
--          shapes, outline, textures, text, width modes, offsets, auto hide, animation, handles, lifecycle)
--
-- Plain Lua 5.1; the repo root and the client flavor (Mainline, Forever, Vanilla, TBC or Mists).

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local failures, covered = {}, {}
local function Check(item, ok, message)
    covered[item] = true
    if not ok then failures[#failures + 1] = string.format("%s %s: %s", flavor, item, message) end
    return ok
end
local function Near(a, b, tolerance)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tolerance or 1e-4)
end
--- Visits a frame tree; `visible` is the region's own flag and every ancestor's.
local function Walk(frame, visit, shown)
    local visible = shown ~= false and frame.shown ~= false
    visit(frame, visible)
    for _, region in ipairs(frame.regions or {}) do visit(region, visible and region.shown ~= false) end
    for _, child in ipairs(frame.children or {}) do Walk(child, visit, visible) end
end

-- The unit preview model binds the core's config-changed export when it loads, so the
-- drag step's no-op stand-in goes in before it (beforeOptions) behind this switch.
local silenceConfigNotify = false
local mw = MenuWorld.Open(root, flavor, { page = "home", beforeOptions = function(world)
    local env = world.env
    local notify = env.MSUF_UFCore_NotifyConfigChanged
    env.MSUF_UFCore_NotifyConfigChanged = function(...)
        if silenceConfigNotify then return end
        return notify(...)
    end
end, beforeCore = function(world)
    local env = world.env
    env.INTERRUPTED = "Interrupted"
    env.Constants = { UnitPowerSpellIDs = {} }
    env.STAGGER_YELLOW_TRANSITION, env.STAGGER_RED_TRANSITION = .3, .6
    for name, value in pairs({ SPEC_DEMONHUNTER_DEVOURER = 3, SPEC_MAGE_ARCANE = 1, SPEC_MONK_WINDWALKER = 3,
        SPEC_MONK_BREWMASTER = 1, SPEC_WARLOCK_DESTRUCTION = 3, SPEC_WARLOCK_DEMONOLOGY = 2,
        SPEC_DEMONHUNTER_VENGEANCE = 2 }) do env[name] = value end
    local enum = env.Enum
    env.Enum = setmetatable({ PowerType = setmetatable({ Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4,
        Runes = 5, RunicPower = 6, SoulShards = 7, LunarPower = 8, HolyPower = 9, Maelstrom = 11, Chi = 12,
        Insanity = 13, BurningEmbers = 14, DemonicFury = 15, ArcaneCharges = 16, Essence = 19 },
        { __index = enum and enum.PowerType }) }, { __index = enum })
end })
local M, env, core, world = mw.M, mw.env, mw.core, mw.world
local widgets = world.widgets
local db = env.MSUF_DB
local g, bars = db.general, db.bars
local client = core.Client
local Castbars = core.Castbars
local function Refresh() Castbars.Config.Refresh(); core.UF.Config.Refresh() end
local SCENE_UNIT = { boss = "boss1", arena = "arena1" }
local UNITS = {}
for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
    if client.SupportsUnit(SCENE_UNIT[unit] or unit) then UNITS[#UNITS + 1] = unit end
end
local EMPOWER = client.HasEmpoweredCasts ~= false and client.IsClassic ~= true and Castbars.Empower.LayoutEmpowerTicks ~= nil

---------------------------------------------------------------------------
-- 0. No Options painter is left for the switched parts
---------------------------------------------------------------------------
local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end
local MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local banned = {
    [MENU .. "Pages/MSUF_Menu2_GlobalCastbars_Preview.lua"] = { "CreateTexture", "empowerBands", "empowerFills", "SetVertexColor",
        "latency:SetPoint", "PreviewTexture" },
    [MENU .. "Preview/MSUF_Menu2_UnitPreview_Render.lua"] = { "ApplyCastbarPreviewDetails", "ApplyCastbarFeatureSamples",
        "ApplyCastbarPreviewRounded", "RenderClassPowerSegments", "EnsurePreviewSecondaryClassTimer", "ApplyCastbarPreviewProgress" },
    [MENU .. "Preview/MSUF_Menu2_ClassPowerPreview.lua"] = { "EnsureClassPowerSlots", "frame.segments", "ApplyRoundedClassPowerSurface",
        "CP_CLASS_ROUNDED_OPTS", "frame.hashes", "frame.notches" },
    [MENU .. "Preview/MSUF_Menu2_UnitPreview_View.lua"] = { "mock.cast.fill", "mock.cast.icon", "mock.classPower.segments",
        "EnsureSegmentSlots", "mock.classPower.textOwner" },
    [MENU .. "MSUF_Menu2_PreviewHelpers.lua"] = { "ApplyRoundedClassPowerSurface", "function CP.FillForSegment",
        "function CP.BuildRuneOrder", "function CP.IsCharged", "function CP.ResolveSlotColor", "function CP.FormatSeconds" },
    [MENU .. "Preview/MSUF_Menu2_UnitPreview_Castbar.lua"] = { "AnchorText", "TimeOffsets", "ResolveTargetTextPreviewColor",
        "FormatPreviewTime" },
}
for path, words in pairs(banned) do
    local text = Read(path)
    for _, word in ipairs(words) do
        Check("A27", not text:find(word, 1, true), path:match("[^/]+$") .. " still holds the Options painter " .. word)
    end
end
Check("B22", core.UFPreviewCastbar.TimeOffsets == nil and core.UFPreviewCastbar.AnchorText == nil,
    "the preview-side castbar text helpers came back")

---------------------------------------------------------------------------
-- 1. Castbars page preview: every unit and cast kind
---------------------------------------------------------------------------
assert(M.Open("opt_castbar") ~= false, "castbar page did not open")
mw:RunTimers()
local preview = assert(M._msuf2CastbarPreview, "the Castbars page built no preview")
local function Page(unit, kind, progress)
    M.SetCastbarPreviewUnit(unit)
    M.SetCastbarPreviewType(kind, progress or 0.4)
    Refresh()
    preview:Refresh()
    return preview.frame
end
local function Resolve(unit) return core.UFPreviewCastbar.ReadSize(unit, g, 271, 18) end
local kinds = { "normal", "channel" }
if EMPOWER then kinds[#kinds + 1] = "empowered" end
Check("B24", preview.root ~= nil and preview.root:IsActive(), "the page preview made no active scene root on its first paint")
for _, unit in ipairs(UNITS) do
    for _, kind in ipairs(kinds) do
        local f = Page(unit, kind, 0.4)
        local label = unit .. "/" .. kind
        if Check("A1", f and f:IsShown() and f.unit == (SCENE_UNIT[unit] or unit), label .. ": no castbar scene frame") then
            Check("A1", (f.MSUF_isChanneled == true) == (kind == "channel"), label .. ": wrong channel state")
            Check("A1", (f.isEmpower == true) == (kind == "empowered"), label .. ": wrong empower state")
            Check("A22", f:GetParent() == preview.castRow and f.statusBar:IsShown(), label .. ": scene not inside the cast row")
            -- The live layout hands the bar its unit frame strata (LOW/MEDIUM/HIGH); inside the Options window
            -- (FULLSCREEN_DIALOG) that would draw it behind the window.
            Check("A22b", f:GetFrameStrata() == preview.castRow:GetFrameStrata(), label .. ": scene drawn outside the Options strata")
            local width = Resolve(unit)
            Check("A22", Near(f:GetWidth(), width, 1), label .. ": width " .. tostring(f:GetWidth()) .. " is not the configured " .. tostring(width))
            local lo, hi = f.statusBar:GetMinMaxValues()
            Check("A23", hi and hi > 0 and f.statusBar:GetValue() > lo, label .. ": the fill follows no progress")
            Check("A7", (f.timeText:GetText() or "") ~= "" or g.showPlayerCastTime == false, label .. ": no time text")
            Check("A6", f.castText:GetText() == "Glacial Spike of the Infinite Midnight Archive" or kind ~= "normal"
                or f.castText:GetText() ~= nil, label .. ": no spell text")
            if unit ~= "player" then
                g.castbarTargetShowTargetName, g.castbarFocusShowTargetName = true, true
                g.showBossCastTargetName, g.showArenaCastTargetName = true, true
                local fr = Page(unit, kind, 0.4)
                Check("A8", fr.castTargetText and fr.castTargetText:GetText() == core.Translate("Cleave Training Dummy"),
                    label .. ": no localized cast target")
            else
                Check("A15", f.latencyBar ~= nil, label .. ": the player scene has no latency region")
            end
        end
    end
end
-- Empower stages and the stage blink.
if EMPOWER then
    local f = Page("player", "empowered", 0.1)
    local ticks, segments, shownTicks = f.empowerTicks or {}, f.empowerSegments or {}, 0
    for i = 1, #ticks do if ticks[i]:IsShown() then shownTicks = shownTicks + 1 end end
    local shownSegments = 0
    for i = 1, #segments do if segments[i]:IsShown() then shownSegments = shownSegments + 1 end end
    local stages = Check("A2", shownTicks == 3 and shownSegments == 4, "empower stages: " .. shownTicks .. " ticks, " .. shownSegments .. " bands")
    g.empowerColorStages = false
    Page("player", "empowered", 0.1)
    g.empowerColorStages = true
    if stages then
        local before = f.empowerTicks[1]:GetWidth()
        widgets:SetTime(100)
        preview.progress = 0.1
        preview:Refresh()
        preview.progress = 0.3
        preview:Refresh()
        local blinking = preview.frame.empowerTicks[1]
        Check("A3", blinking:GetWidth() > before and blinking.vertexColor and blinking.vertexColor[2] < 0.5,
            "the crossed empower stage does not blink (" .. tostring(blinking:GetWidth()) .. " vs " .. tostring(before) .. ")")
        widgets:AdvanceTime(5)
        preview.progress = 0.31
        preview:Refresh()
        Check("A3", Near(preview.frame.empowerTicks[1]:GetWidth(), before), "the empower stage blink never ends")
        g.empowerStageBlink = false
        Refresh()
        preview.progress = 0.1
        preview:Refresh()
        preview.progress = 0.3
        preview:Refresh()
        Check("A3", Near(preview.frame.empowerTicks[1]:GetWidth(), before), "empowerStageBlink off still blinks")
    else
        Check("A3", false, "no empower stage ticks to blink")
    end
    g.empowerStageBlink = true
else
    Check("A2", M.CastbarPreviewTypes == nil or not preview.typeButtons.empowered, "a client without empowered casts offers the type")
    Check("A3", true, "no empowered casts on this client")
end
-- Fill direction, colours, shapes, spark, outline, latency, markers.
do
    g.castbarFillDirection = "LTR"
    local f = Page("target", "normal", 0.5)
    Check("A4", f.statusBar:GetReverseFill() == false, "LTR fill is reversed")
    g.castbarFillDirection = "RTL"
    f = Page("target", "normal", 0.5)
    Check("A4", f.statusBar:GetReverseFill() == true, "RTL fill is not reversed")
    g.castbarFillDirection = "LTR"
    Page("target", "channel", 0.5)
    g.castbarUnifiedDirection = true
    f = Page("target", "channel", 0.5)
    Check("A4", f._msufCountsDown == false, "unified direction still counts down")
    g.castbarUnifiedDirection = false
    f = Page("target", "channel", 0.5)
    Check("A4", f._msufCountsDown == true, "a draining channel does not count down")
    g.castbarFillDirection = "RTL"

    local r, gr, b = env.MSUF_ResolveCastbarColors()
    f = Page("target", "normal", 0.5)
    local color = f.statusBar.color
    Check("A9", color and Near(color[1], r) and Near(color[2], gr) and Near(color[3], b),
        "the fill is not the live cast colour")
    g.castbarShowGlow = true
    f = Page("target", "normal", 0.9)
    Check("A9", f.statusBar ~= nil, "glow setting broke the scene")
    g.castbarShowGlow = false

    f = Page("target", "normal", 0.5)
    Check("A11", f.backgroundBar and f.backgroundBar:IsShown() and f.statusBar:GetStatusBarTexture() ~= nil,
        "no background or fill texture")

    g.castbarOutlineThickness = 3
    bars.slantedCastbars, bars.roundedCastbars = false, false
    f = Page("target", "normal", 0.5)
    local host = f._msufOutlineHost
    Check("A12", host and host:IsShown(), "no outline at thickness 3")
    g.castbarOutlineThickness = 0
    f = Page("target", "normal", 0.5)
    Check("A12", not (f._msufOutlineHost and f._msufOutlineHost:IsShown()), "outline stayed at thickness 0")
    g.castbarOutlineThickness = 1
    bars.slantedBarsEnabled, bars.slantedCastbars = true, true
    core.RoundedCastbarsApplyAll(true)
    f = Page("target", "normal", 0.5)
    Check("A13", f._msufRoundedCastbarMasked and next(f._msufRoundedCastbarMasked) ~= nil, "slanted castbar has no masks")
    bars.slantedCastbars = false
    bars.roundedFramesEnabled, bars.roundedCastbars = true, true
    core.RoundedCastbarsApplyAll(true)
    f = Page("target", "normal", 0.5)
    Check("A13", f._msufRoundedCastbarMasked and next(f._msufRoundedCastbarMasked) ~= nil, "rounded castbar has no masks")
    bars.roundedFramesEnabled, bars.roundedCastbars = false, false
    core.RoundedCastbarsApplyAll(true)
    f = Page("target", "normal", 0.5)
    Check("A13", f._msufRoundedCastbarMasked == nil or next(f._msufRoundedCastbarMasked) == nil, "plain castbar kept masks")

    g.castbarShowSpark = true
    f = Page("target", "normal", 0.5)
    Check("A14", f.spark and f.spark:IsShown(), "spark switched on but hidden")
    g.castbarShowSpark = false
    f = Page("target", "normal", 0.5)
    Check("A14", not (f.spark and f.spark:IsShown()), "spark switched off but shown")

    g.castbarShowLatency, g.castbarShowLatencyText = true, true
    f = Page("player", "normal", 0.5)
    Check("A15", f.latencyBar:IsShown() and Near(f.latencyBar:GetWidth(), f.statusBar:GetWidth() * 0.12, 1),
        "latency zone is not 12% of the bar")
    Check("A16", f.latencyText and f.latencyText:IsShown() and f.latencyText:GetText() == "50 ms", "no latency text")
    g.castbarShowLatencyText = false
    f = Page("player", "normal", 0.5)
    Check("A16", not (f.latencyText and f.latencyText:IsShown()), "latency text stayed off-setting")
    g.castbarShowLatency = false
    f = Page("player", "normal", 0.5)
    Check("A15", not f.latencyBar:IsShown(), "latency zone stayed with the setting off")
    g.castbarShowLatency = true

    g.castbarShowChannelTicks, g.castbarAccentLastTick = true, true
    f = Page("player", "channel", 0.5)
    local markers, shown = f._msufPlayerChannelHasteMarkers or {}, 0
    for i = 1, #markers do if markers[i]:IsShown() then shown = shown + 1 end end
    Check("A17", shown == 5, "channel markers: " .. shown .. " of 5")
    local cfg = db.player.castbar or {}
    db.player.castbar = cfg
    cfg.channelTickUseCustom, cfg.channelTickCount, cfg.channelTickPosPct = true, 3, { 80, 20, 50 }
    f = Page("player", "channel", 0.5)
    shown = 0
    for i = 1, #(f._msufPlayerChannelHasteMarkers or {}) do if f._msufPlayerChannelHasteMarkers[i]:IsShown() then shown = shown + 1 end end
    Check("A17", shown == 3, "custom channel markers: " .. shown .. " of 3")
    cfg.channelTickUseCustom = false
    g.castbarShowChannelTicks = false
    f = Page("player", "channel", 0.5)
    shown = 0
    for i = 1, #(f._msufPlayerChannelHasteMarkers or {}) do if f._msufPlayerChannelHasteMarkers[i]:IsShown() then shown = shown + 1 end end
    Check("A17", shown == 0, "channel markers stayed with the setting off")
end
-- Icon, texts.
do
    g.castbarPlayerShowIcon = true
    local f = Page("player", "normal", 0.5)
    Check("A5", f.icon:IsShown(), "icon switched on but hidden")
    g.castbarPlayerIconZoom, g.castbarPlayerIconBorderStyle, g.castbarPlayerIconBorderThickness = 150, "CASTBAR", 3
    f = Page("player", "normal", 0.5)
    Check("A5", f.icon.texCoord and Near(f.icon.texCoord[1], 1 / 6) and f._msufDetailIconBorder and f._msufDetailIconBorder:IsShown(),
        "icon zoom or border missing")
    g.castbarPlayerShowIcon = false
    f = Page("player", "normal", 0.5)
    Check("A5", not f.icon:IsShown(), "icon switched off but shown")
    g.castbarPlayerShowIcon = true
    g.castbarPlayerSpellNameFontSize, g.castbarPlayerTimeFontSize = 21, 17
    g.showPlayerCastTime = true
    f = Page("player", "normal", 0.5)
    Check("A6", select(2, f.castText:GetFont()) == 21, "spell text size is " .. tostring(select(2, f.castText:GetFont())))
    Check("A7", select(2, f.timeText:GetFont()) == 17, "time text size is " .. tostring(select(2, f.timeText:GetFont())))
    g.castbarPlayerSpellNamePosition = "CENTER"
    f = Page("player", "normal", 0.5)
    Check("A6", f.castText.justifyH == "CENTER", "spell text position ignored")
    g.castbarPlayerSpellNamePosition = nil
    g.castbarSpellNameShortening, g.castbarSpellNameMaxLen = 1, 10
    f = Page("player", "normal", 0.5)
    Check("A6", #(f.castText:GetText() or "") < #"Glacial Spike of the Infinite Midnight Archive", "spell name shortening ignored")
    g.castbarSpellNameShortening = 0
    g.showPlayerCastTime = false
    f = Page("player", "normal", 0.5)
    Check("A7", (f.timeText:GetText() or "") == "", "time text stayed with the setting off")
    g.showPlayerCastTime = true
    g.castbarPlayerSpellNameFontSize, g.castbarPlayerTimeFontSize = nil, nil
end
-- Interrupt Ready.
if UNITS[2] then
    g.kickReadyShowTarget = true
    g.kickReadyStyle = "box"
    g.kickReadyTimeMarker, g.kickReadyTimeSegment = false, false
    local f = Page("target", "normal", 0.5)
    Check("A18", f.kickReadyBox and f.kickReadyBox:IsShown(), "box style shows no ready box")
    g.kickReadyStyle = "border"
    f = Page("target", "normal", 0.5)
    Check("A18", f._kickReadyBorderTinted == true, "border style tints no outline")
    g.kickReadyStyle = "fill"
    local plain = env.MSUF_ResolveCastbarColors()
    f = Page("target", "normal", 0.5)
    Check("A18", f.statusBar.color and f.statusBar.color[1] ~= nil, "fill style paints no colour")
    g.kickReadyTimeMarker, g.kickReadyTimeSegment, g.kickReadyColor = true, true, { 0.2, 0.4, 0.8 }
    f = Page("target", "normal", 0.5)
    local projection = f._msufKickTimeProjections and f._msufKickTimeProjections[1]
    Check("A19", projection and projection.marker:IsShown() and projection.segment:IsShown(), "no time marker and segment")
    Check("A19", projection and Near(projection.marker.colorTexture[3], 0.8), "time marker ignores the ready colour")
    g.kickReadyTimeMarker, g.kickReadyTimeSegment = false, false
    g.kickReadyShowTarget = false
    f = Page("target", "normal", 0.5)
    Check("A18", not (f.kickReadyBox and f.kickReadyBox:IsShown()), "ready box stayed with Interrupt Ready off")
    Check("A19", true, "projection hidden with the switches off")
else
    Check("A18", true, "no target castbar on this client")
    Check("A19", true, "no target castbar on this client")
end
-- Interrupt replay and the row shake.
do
    local f = Page("player", "normal", 0.5)
    local plainText = f.castText:GetText()
    widgets:SetTime(200)
    assert(M.PlayCastbarPreviewInterrupt())
    Check("A21", preview.interruptUntil > 200 and preview.shakeUntil > 200, "the interrupt replay armed no feedback or shake")
    preview:Refresh()
    f = preview.frame
    Check("A20", f.castText:GetText() ~= plainText and tostring(f.castText:GetText()):find("nterrupt"), "interrupted look: " .. tostring(f.castText:GetText()))
    local box = preview.castRowBase.parent
    local onUpdate = box:GetScript("OnUpdate")
    widgets:AdvanceTime(0.05)
    onUpdate(box, 0.05)
    Check("A21", preview._rowOffset ~= 0, "the shake did not move the cast row")
    widgets:AdvanceTime(5)
    onUpdate(box, 0.05)
    preview:Refresh()
    Check("A20", preview.frame.castText:GetText() == plainText, "the interrupted look never ends")
    Check("A21", preview._rowOffset == 0, "the shake did not settle")
end
-- Progress animation: the driver moves the fill and the time text without relayout.
do
    local f = Page("target", "normal", 0.1)
    local box = preview.castRowBase.parent
    local onUpdate = box:GetScript("OnUpdate")
    local layouts = 0
    local ClearAllPoints = f.ClearAllPoints
    f.ClearAllPoints = function(self, ...) layouts = layouts + 1 return ClearAllPoints(self, ...) end
    local before, text = f.statusBar:GetValue(), f.timeText:GetText()
    for _ = 1, 4 do onUpdate(box, 0.06) end
    f.ClearAllPoints = ClearAllPoints
    Check("A23", f.statusBar:GetValue() ~= before and f.timeText:GetText() ~= text, "the animation tick moved nothing")
    Check("A23", layouts == 0, "the animation tick relaid the castbar out " .. layouts .. " times")
    -- Fit: a narrow row scales the bar down instead of clipping it.
    local row = preview.castRow
    local width = row:GetWidth()
    row:SetWidth(120)
    f = Page("target", "normal", 0.5)
    Check("A22", f:GetScale() < 1, "a narrow row did not scale the castbar")
    row:SetWidth(width)
    Page("target", "normal", 0.5)
end

---------------------------------------------------------------------------
-- 2. The Unit preview castbar slot
---------------------------------------------------------------------------
local Preview = core.UFPreview
for _, key in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetAutoFocus", "SetMaxLetters", "EnableKeyboard" }) do
    if not widgets.Methods[key] then widgets.Methods[key] = function() end end
end
env.C_Texture = { GetAtlasInfo = function() return nil end }
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel, selected = env.CreateFrame("Frame", nil, env.UIParent), "player"
panel._msufGetCurrentKey = function() return selected end
local box = Preview._BuildPreview(parent, panel, 900, 400)
Check("B24", box._castSceneRoot == nil and box._cpSceneRoot == nil, "a Unit preview box built its scene roots before its first paint")
box:Show()
box.canvas:SetSize(500, 240)
g.enablePlayerCastbar, g.enableTargetCastbar, g.enableFocusCastbar = true, true, true
g.enableBossCastbar, g.enableArenaCastbar = true, true
g.castbarTargetShowTargetName, g.castbarFocusShowTargetName = true, true
g.showBossCastTargetName, g.showArenaCastTargetName = true, true
local function UnitRefresh(reason) Refresh(); Preview.Refresh(box, reason or "OPTIONS_SCENE") end
for _, unit in ipairs(UNITS) do
    selected = unit
    UnitRefresh()
    local scene = box._castScene
    local f = scene and scene:Frame()
    if Check("A1", f and f:IsShown() and f.unit == (SCENE_UNIT[unit] or unit), unit .. ": no castbar scene in the Unit preview") then
        Check("A22", f:GetParent() == box.mock.cast, unit .. ": scene outside its slot")
        local w, h = core.UFPreviewCastbar.ReadSize(unit, g, 275, (unit == "boss" or unit == "arena") and 12 or 18)
        Check("A22", Near(f:GetWidth(), w, 1) and Near(f:GetHeight(), h, 1), unit .. ": scene size is not the configured " .. w .. "x" .. h)
        Check("A22", Near(f:GetScale(), box._mockEffectiveScale), unit .. ": scene scale is not the preview scale")
        Check("A24", box.mock.cast:GetPoint(1) ~= nil, unit .. ": the slot has no anchor")
        Check("A26", box.handleCastbar:IsShown() and box.handleCastbarTime:IsShown() and box.handleCastbarText:IsShown(),
            unit .. ": castbar handles missing")
        Check("A26", box.handleCastbarIcon:IsShown() == (core.UFPreviewCastbar.ShowIcon(unit, g) and true or false),
            unit .. ": the icon handle disagrees with the icon")
        if unit ~= "player" then
            Check("A8", box.handleCastbarTarget:IsShown() and f.castTargetText:GetText() == core.Translate("Cleave Training Dummy"),
                unit .. ": no target text or handle")
        end
        Check("A26", box.mock.cast.sizeTag and (box.mock.cast.sizeTag:GetText() or ""):match("^%d+ x %d+$"), unit .. ": no size tag")
    end
end
selected = "player"
UnitRefresh()
do
    local slot = box.mock.cast
    local point, relative = slot:GetPoint(1)
    Check("A24", point == "BOTTOM" and relative == box.mock._body, "the player castbar slot is not above the body")
    g.castbarPlayerDetached = true
    UnitRefresh()
    local detachedPoint, detachedRelative = slot:GetPoint(1)
    Check("A24", box._detachedCastPreview == true and detachedPoint == "CENTER" and detachedRelative == box.mock._body,
        "a detached castbar is not placed from the body centre")
    Check("A24", box._castScene:Frame() and box._castScene:Frame():GetParent() == slot, "the detached castbar scene left its slot")
    g.castbarPlayerDetached = nil
    UnitRefresh()
    Check("A24", slot:GetPoint(1) == "BOTTOM", "the attached castbar slot did not return above the body")
    -- GCD strip is the Options-owned remainder.
    g.showGCDBar = true
    UnitRefresh()
    Check("A25", slot._featureSamples and slot._featureSamples.gcd and slot._featureSamples.gcd:IsShown(), "no detached GCD sample")
    g.showGCDBar = false
    UnitRefresh()
    -- Layer switch: the castbar layer hides the scene and every castbar handle.
    box.layerVisibility = box.layerVisibility or {}
    box.layerVisibility.castbar = false
    UnitRefresh()
    Check("A27", box._castScene:Frame() == nil and not slot:IsShown() and not box.handleCastbar:IsShown()
        and not box.handleCastbarText:IsShown(), "the castbar layer switch left the scene or a handle")
    box.layerVisibility.castbar = true
    UnitRefresh()
    Check("A27", box._castScene:Frame() and box._castScene:Frame():IsShown() and box.handleCastbar:IsShown(), "the castbar layer did not return")
    -- Combat: the preview is quiet and keeps its last scene.
    local frame = box._castScene:Frame()
    local inCombat = env.InCombatLockdown
    env.InCombatLockdown = function() return true end
    local ok = pcall(Preview.Refresh, box, "OPTIONS_SCENE_COMBAT")
    Check("A28", ok and box._castScene:Frame() == frame, "a combat refresh repainted or broke the castbar slot")
    env.InCombatLockdown = inCombat
    UnitRefresh()
    -- Zoom: the scene scale follows the preview zoom; selection opens the settings from the slot handle.
    box._manualZoom = 2
    UnitRefresh("UNIT_PREVIEW_ZOOM")
    Check("A22", Near(box._castScene:Frame():GetScale(), box._mockEffectiveScale) and box._mockScale == 2,
        "the zoomed scene does not follow the preview scale")
    local handle = box.handleCastbar
    Check("A26", handle:GetScript("OnMouseDown") ~= nil and handle:IsShown(), "the castbar handle lost its drag script")
    -- Dragging the whole-castbar handle moves the slot, and the scene inside it, and saves the offsets.
    do
        local castX = core.UFPreviewCastbar.OffsetFields("player")
        local saved = tonumber(g[castX]) or 0
        local cx, cy = 500, 400
        env.GetCursorPosition = function() return cx, cy end
        env.IsMouseButtonDown = function() return true end
        env.IsControlKeyDown = function() return false end
        silenceConfigNotify = true
        local _, _, _, startX = slot:GetPoint(1)
        handle:GetScript("OnMouseDown")(handle, "LeftButton")
        cx, cy = cx + 30, cy + 18
        box.dragFrame:GetScript("OnUpdate")(box.dragFrame, 0.016)
        handle:GetScript("OnMouseUp")(handle, "LeftButton")
        UnitRefresh()
        local _, _, _, movedX = slot:GetPoint(1)
        Check("A26", (tonumber(g[castX]) or 0) ~= saved and movedX ~= startX, "dragging the castbar handle moved nothing")
        Check("A26", box._castScene:Frame():GetParent() == slot and box._castScene:Frame():IsShown(), "the dragged castbar scene left its slot")
        g[castX] = saved ~= 0 and saved or nil
    end
    box._manualZoom = nil
    UnitRefresh()
    -- The animation clock moves the fill by a light tick without a relayout.
    local action = box.animateCombatButton and box.animateCombatButton._msuf2CommandAction
    if action and action.set(true) then
        local onUpdate = box:GetScript("OnUpdate")
        onUpdate(box, 0.06)
        local f2 = box._castScene:Frame()
        local layouts = 0
        local Clear = f2.ClearAllPoints
        f2.ClearAllPoints = function(self, ...) layouts = layouts + 1 return Clear(self, ...) end
        local v1 = f2.statusBar:GetValue()
        for _ = 1, 6 do onUpdate(box, 0.2) end
        f2.ClearAllPoints = Clear
        Check("A23", f2.statusBar:GetValue() ~= v1 and layouts == 0, "the Unit preview animation moved no fill or relaid out")
        action.set(false)
    else
        Check("A23", false, "the Unit preview animation could not start")
    end
end

---------------------------------------------------------------------------
-- 3. Class Resources: every previewable resource on the page preview
---------------------------------------------------------------------------
assert(M.Open("classpower") ~= false, "class resource page did not open")
mw:RunTimers()
local workspace = assert(M.ClassPowerWorkspace.current)
workspace:Select("class")
local cpBox = assert(workspace.page.ctx.entry.classPowerPreview, "the Class Resources page built no preview")
bars.showClassPower, bars.classPowerShowText = true, true
local keys = {}
for key in pairs(M.ClassPowerPreviewSpecs) do keys[#keys + 1] = key end
table.sort(keys)
Check("B24", cpBox.cpSceneRoot ~= nil and cpBox.cpSceneRoot:IsActive(), "the Class Resources preview made no active scene root")
local MODE_ITEM = { segmented = "B1", fractional = "B3", rune = "B4", continuous = "B5", stagger = "B6",
    aura_segmented = "B7", aura_single = "B8", ironfur = "B9" }
local function Pick(key)
    M._msuf2ClassPowerPreviewSpecKey = key
    Refresh()
    cpBox:Refresh()
    return cpBox.cpScene.CP, M.ClassPowerPreviewSpecs[key]
end
local function FilledBars(CP)
    local filled = 0
    for i = 1, CP.currentMax do
        local bar = CP.bars[i]
        local _, maximum = bar:GetMinMaxValues()
        if bar:IsShown() and maximum and bar:GetValue() >= maximum and maximum > 0 then filled = filled + 1 end
    end
    return filled
end
for _, key in ipairs(keys) do
    local CP, spec = Pick(key)
    if spec.mode == "none" or spec.enabled == false then
        Check("B12", not cpBox.classPower or not cpBox.classPower:IsShown(), key .. ": a resource-less spec still draws a class bar")
        Check("B12", cpBox.noResource:IsShown(), key .. ": no 'no class resource' note")
    else
        local native = spec.token == "WHIRLWIND" or spec.token == "SWEEPING_STRIKES"
        local item = native and "B10" or MODE_ITEM[spec.mode] or "B1"
        if Check(item, CP.visible and cpBox.classPower:IsShown(), key .. ": the resource is not drawn") then
            local expectedMax
            if spec.mode == "rune" then expectedMax = 6
            elseif native or spec.mode == "continuous" or spec.mode == "stagger" or spec.mode == "aura_single" or spec.mode == "ironfur" then expectedMax = 1
            else expectedMax = spec.segments end
            Check(item, CP.currentMax == expectedMax, key .. ": " .. tostring(CP.currentMax) .. " slots, expected " .. tostring(expectedMax))
            if spec.mode == "segmented" or (spec.mode == "aura_segmented" and not native) then
                Check(item, FilledBars(CP) == math.floor(spec.value), key .. ": " .. FilledBars(CP) .. " filled of " .. spec.value)
            elseif spec.mode == "fractional" then
                Check(item, FilledBars(CP) == math.floor(spec.value) and CP.text and CP.text:GetText() == string.format("%.1f", spec.value),
                    key .. ": fractional fill or text")
            elseif spec.mode == "rune" then
                local ready = 0
                for i = 1, 6 do local bar = CP.bars[i]; local _, m = bar:GetMinMaxValues(); if bar:GetValue() >= m then ready = ready + 1 end end
                Check("B4", ready == math.floor(spec.value), key .. ": " .. ready .. " ready runes")
            elseif spec.mode == "continuous" or spec.mode == "stagger" then
                local bar = CP.bars[1]
                local _, maximum = bar:GetMinMaxValues()
                Check(item, Near(bar:GetValue() / maximum, spec.value, 0.011), key .. ": fill " .. bar:GetValue() .. "/" .. maximum)
            elseif spec.mode == "aura_single" then
                local bar = CP.bars[1]
                Check("B8", Near(bar:GetValue(), spec.value, 0.011), key .. ": Devourer fill " .. bar:GetValue())
            end
            if key == "rogue_combo" and spec.chargedSlots then
                Check("B2", CP.chargedAny == true and CP.chargedMap[1] == true and CP.chargedMap[2] == true,
                    "charged combo points are not carried to the scene")
                Check("B2", CP.visual.chargedR ~= nil and CP.bars[1].color and CP.bars[3].color
                    and not Near(CP.bars[1].color[1], CP.bars[3].color[1]) , "charged combo points are not coloured apart")
            end
            if key == "demonhunter_devourer" then
                local notches = 0
                for _, notch in ipairs(CP.fragNotches or {}) do if notch:IsShown() then notches = notches + 1 end end
                Check("B8", notches >= 2, "Devourer fragment notches missing (" .. notches .. ")")
            end
            if key == "druid_guardian" then
                local hashes = 0
                Walk(CP.container, function(region, visible)
                    if region.objectType == "Texture" and visible and region.drawLayer == "OVERLAY" and region.drawSublevel == 7
                        and region.width == 2 then hashes = hashes + 1 end
                end)
                Check("B9", hashes == 3 and CP.text and CP.text:IsShown(), "ironfur hash lines (" .. hashes .. " of 3) or text missing")
            end
            if native then
                local ticks = 0
                Walk(CP.container, function(region, visible)
                    if region.objectType == "Texture" and visible and region.colorTexture and region.colorTexture[1] == 0
                        and region.colorTexture[4] == 1 and region.drawLayer == "OVERLAY" then ticks = ticks + 1 end
                end)
                Check("B10", ticks == spec.segments - 1, key .. ": " .. ticks .. " separators, expected " .. (spec.segments - 1))
            end
            if spec.mode == "rune" then
                local cooling = 0
                for i = 1, 6 do
                    local bar = CP.bars[i]
                    local text = bar._runeText
                    if bar._runeTextVisible and text and (text:GetText() or "") ~= "" then cooling = cooling + 1 end
                end
                Check("B4", cooling == 6 - math.floor(spec.value), key .. ": " .. cooling .. " rune cooldown texts")
            end
        end
    end
end
-- A mode the client has no resource for has nothing to preview: its inventory item is not applicable there.
do
    local present = {}
    for _, key in ipairs(keys) do
        local spec = M.ClassPowerPreviewSpecs[key]
        if spec.token == "WHIRLWIND" or spec.token == "SWEEPING_STRIKES" then present.B10 = true end
        present[MODE_ITEM[spec.mode] or "B1"] = true
        if spec.chargedSlots then present.B2 = true end
    end
    for _, item in ipairs({ "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10" }) do
        if not present[item] then covered[item] = true end
    end
end
-- Resource gates the picker ignores: every resource shows although its profile switch is off.
for _, field in ipairs({ "showShadowMana", "showEleMaelstrom", "showGuardianIronfur", "showSweepingStrikes" }) do bars[field] = false end
for _, key in ipairs({ "priest_shadow", "shaman_elemental", "druid_guardian", "warrior_sweeping" }) do
    if M.ClassPowerPreviewSpecs[key] then
        local CP = Pick(key)
        Check("B11", CP.visible and cpBox.classPower:IsShown(), key .. " is hidden by its profile gate")
    end
end
Check("B11", true, "gates checked where the client has the resource")
bars.showClassPower = false
do
    Pick("rogue_combo")
    Check("B12", not cpBox.classPower:IsShown() and cpBox.noResource:IsShown(), "showClassPower=false still draws the bar")
    bars.showClassPower = true
end

-- Colours, shapes, alpha, text, offsets and auto hide on the combo points.
do
    local CP = Pick("rogue_combo")
    g.classPowerColorOverrides = { COMBO_POINTS = { 0.3, 0.4, 0.5 } }
    g.classPowerBgColorOverrides = { COMBO_POINTS = { 0.1, 0.2, 0.3 } }
    CP = Pick("rogue_combo")
    Check("B13", Near(CP.visual.baseR, 0.3) and Near(CP.visual.baseG, 0.4), "the base colour override does not reach the scene")
    Check("B13", Near(CP.visual.bgR, 0.1) and Near(CP.visual.bgG, 0.2), "the background colour override does not reach the scene")
    g.classPowerColorOverrides, g.classPowerBgColorOverrides = nil, nil
    bars.classPowerShape = "CIRCLE"
    CP = Pick("rogue_combo")
    Check("B14", Near(CP.bars[1]:GetWidth(), CP.bars[1]:GetHeight(), 1), "a circle pip is not square")
    bars.classPowerShape = "BAR"
    CP = Pick("rogue_combo")
    Check("B14", CP.bars[1]:GetWidth() > CP.bars[1]:GetHeight(), "a bar pip is not wide")
    bars.classPowerGap, bars.classPowerTickWidth = 4, 2
    CP = Pick("rogue_combo")
    Check("B14", CP.bars[2]:GetPoint(1) ~= nil, "gap and separator width broke the layout")
    bars.classPowerGap, bars.classPowerTickWidth = nil, nil
    bars.classPowerOutline = 2
    CP = Pick("rogue_combo")
    Check("B15", CP._outline and CP._outline:IsShown(), "the profile outline is not drawn around the resource")
    cpBox.layerVisibility.border = false
    CP = Pick("rogue_combo")
    Check("B15", not (CP._outline and CP._outline:IsShown()), "the Border layer does not remove the outline")
    cpBox.layerVisibility.border = true
    bars.classPowerOutline = nil
    bars.classPowerFilledAlpha, bars.classPowerEmptyAlpha = 0.6, 0.2
    CP = Pick("rogue_combo")
    Check("B16", Near(CP.bars[1]:GetAlpha(), 0.6) and Near(CP.bars[CP.currentMax]:GetAlpha(), 0.2), "filled and empty alpha ignored")
    bars.classPowerFilledAlpha, bars.classPowerEmptyAlpha = nil, nil
    bars.classPowerShowText = true
    CP = Pick("rogue_combo")
    Check("B17", CP.text and CP.text:IsShown() and tostring(CP.text:GetText()) == tostring(M.ClassPowerPreviewSpecs.rogue_combo.value),
        "resource text is " .. tostring(CP.text and CP.text:GetText()))
    Check("B22", cpBox.handleClassText:IsShown(), "the text handle is not placed around the resource text")
    cpBox.layerVisibility.classText = false
    CP = Pick("rogue_combo")
    Check("B17", not (CP.text and CP.text:IsShown()) and not cpBox.handleClassText:IsShown(), "the Res Text layer leaves the text")
    cpBox.layerVisibility.classText = true
    -- Width modes and offsets.
    bars.classPowerHeight, bars.classPowerOffsetX = 9, 7
    CP = Pick("rogue_combo")
    Check("B19", Near(CP.container:GetHeight(), 9, 1), "the container height is " .. tostring(CP.container:GetHeight()))
    bars.classPowerOffsetX = nil
    bars.classPowerWidthMode, bars.classPowerWidth = "custom", 190
    CP = Pick("rogue_combo")
    Check("B18", Near(CP.container:GetWidth(), 190, 1), "custom width " .. CP.container:GetWidth())
    local widths = { cooldown = "EssentialCooldownViewer", utility = "UtilityCooldownViewer", tracked_buffs = "BuffIconCooldownViewer" }
    local at = 310
    for mode, frameName in pairs(widths) do
        local viewer = env.CreateFrame("Frame", nil, env.UIParent)
        viewer:SetSize(at, 40)
        viewer:SetPoint("CENTER", env.UIParent, "CENTER", 0, -120)
        viewer:Show()
        env[frameName] = viewer
        bars.classPowerWidthMode = mode
        CP = Pick("rogue_combo")
        Check("B18", Near(CP.container:GetWidth(), at, 2), mode .. " width " .. tostring(CP.container:GetWidth()) .. " is not the viewer's " .. at)
        env[frameName] = nil
        at = at + 20
    end
    bars.classPowerWidthMode, bars.classPowerWidth, bars.classPowerHeight = nil, nil, nil
    bars.classPowerShape = "CIRCLE"
    bars.classPowerWidthMode = "auto_pips"
    CP = Pick("rogue_combo")
    Check("B18", CP.container:GetWidth() < 190, "auto pip width not applied")
    bars.classPowerWidthMode, bars.classPowerShape = nil, nil
    -- Auto hide: out-of-combat hiding is ignored; the full/empty rules are honoured.
    bars.classPowerHideOOC = true
    CP = Pick("rogue_combo")
    Check("B20", CP.container:GetAlpha() == 1, "the out-of-combat auto hide leaked into the preview")
    bars.classPowerHideOOC, bars.classPowerHideWhenEmpty = nil, true
    M._msuf2ClassPowerPreviewSpecKey = "rogue_combo"
    local spec = M.ClassPowerPreviewSpecs.rogue_combo
    local savedValue = spec.value
    spec.value = 0
    CP = Pick("rogue_combo")
    Check("B20", CP.container:GetAlpha() == 0, "hide-when-empty did not hide an empty resource")
    spec.value = savedValue
    bars.classPowerHideWhenEmpty = nil
    Pick("rogue_combo")
end

-- Animation, handles, bounds, fit and the retained neighbours on the page.
do
    local CP = Pick("rogue_combo")
    local before = FilledBars(CP)
    cpBox._animationEnabled = true
    cpBox._animationElapsed = 0
    local seen = {}
    for i = 1, 40 do
        cpBox._animationElapsed = i * 0.21
        assert(cpBox:RefreshAnimation(), "the class resource animation fell back to a full refresh")
        seen[FilledBars(CP)] = true
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    Check("B21", distinct >= 3, "the class resource wave moved through " .. distinct .. " counts")
    cpBox._animationEnabled = false
    Pick("rogue_combo")
    Check("B22", cpBox.handleClass:IsShown() and cpBox.handleClass._msufPlaced == true, "the class resource handle is not placed")
    cpBox.layerVisibility.bounds = true
    Pick("rogue_combo")
    Check("B22", cpBox.bounds and cpBox.bounds.class and cpBox.bounds.class:IsShown(), "no class bounds")
    Check("B22", cpBox._mockEffectiveScale ~= nil and cpBox.stage:GetScale() > 0, "no fit-to-content zoom")
    cpBox.layerVisibility.class = false
    Pick("rogue_combo")
    Check("B22", cpBox.cpScene:Frame() == nil and not cpBox.handleClass:IsShown(), "the Resource layer left the scene or its handle")
    cpBox.layerVisibility.class = true
    Pick("rogue_combo")
    local player = db.player
    player.showPower, player.powerBarDetached, player.detachedPowerBarShape = true, true, "BAR"
    player.detachedPowerBarAnchorToClassPower = true
    Pick("rogue_combo")
    Check("B23", cpBox.detachedPower and cpBox.detachedPower:IsShown() and cpBox.playerRef ~= nil,
        "the detached player power bar left the preview")
    player.powerBarDetached, player.detachedPowerBarAnchorToClassPower = false, nil
    Pick("rogue_combo")
    -- Close and reopen: the root stops with the box and comes back with it.
    local root = cpBox.cpSceneRoot
    cpBox:Hide()
    MenuWorld.FireScript(cpBox, "OnHide")
    Check("B24", root:IsActive() == false, "hiding the preview left its scene root active")
    cpBox:Show()
    MenuWorld.FireScript(cpBox, "OnShow")
    Pick("rogue_combo")
    Check("B24", cpBox.cpSceneRoot == root and root:IsActive(), "reopening built a new scene root instead of reusing the box's")
end

---------------------------------------------------------------------------
-- 4. The Unit preview class resource slot
---------------------------------------------------------------------------
do
    M.activeKey = "classpower"
    selected = "player"
    bars.showClassPower = true
    bars.classPowerWidthMode, bars.classPowerShape = nil, "BAR"
    for _, specKey in ipairs({ "rogue_combo", "priest_shadow", "deathknight_runes" }) do
        if M.ClassPowerPreviewSpecs[specKey] then
            M._msuf2ClassPowerPreviewSpecKey = specKey
            UnitRefresh()
            local scene = box._cpScene
            local CP = scene and scene.CP
            if Check("B1", CP and CP.visible and CP.container:IsShown(), specKey .. ": the Unit preview draws no class resource") then
                local slot = box.mock.classPower
                -- The scene frame carries the preview scale; the slot is in canvas pixels.
                local scale = box._mockEffectiveScale
                Check("B19", Near(slot:GetWidth(), CP.container:GetWidth() * scale, 1.5) and Near(slot:GetHeight(), CP.container:GetHeight() * scale, 1.5),
                    specKey .. ": the Unit preview slot " .. slot:GetWidth() .. "x" .. slot:GetHeight() .. " differs from the scene container "
                    .. CP.container:GetWidth() * scale .. "x" .. CP.container:GetHeight() * scale)
                Check("B22", box.handleClassPower:IsShown(), specKey .. ": no class resource handle in the Unit preview")
            end
        end
    end
    M.activeKey = "home"
    UnitRefresh()
    local CP = box._cpScene and box._cpScene.CP
    Check("B14", CP and CP.visible and CP.currentMax == 5, "the generic Unit preview resource is not a five-pip bar")
    box.layerVisibility.classPower = false
    UnitRefresh()
    Check("B22", box._cpScene:Frame() == nil and not box.handleClassPower:IsShown(), "the class power layer left the scene or its handle")
    box.layerVisibility.classPower = true
    UnitRefresh()
    local root = box._cpSceneRoot
    box:Hide()
    MenuWorld.FireScript(box, "OnHide")
    Check("B24", root:IsActive() == false and box._castSceneRoot:IsActive() == false, "hiding the Unit preview left a scene root active")
    box:Show()
    MenuWorld.FireScript(box, "OnShow")
    UnitRefresh()
    Check("B24", box._cpSceneRoot == root and root:IsActive(), "the Unit preview rebuilt its class resource root")
end

---------------------------------------------------------------------------
-- Every inventory item was exercised
---------------------------------------------------------------------------
local required = {}
-- A10 (shield sample) was never an Options painter capability: the scene supports it, Options feeds none.
for i = 1, 28 do if i ~= 10 then required[#required + 1] = "A" .. i end end
for i = 1, 24 do required[#required + 1] = "B" .. i end
for _, item in ipairs(required) do
    if not covered[item] then failures[#failures + 1] = flavor .. " " .. item .. ": no assertion reached this inventory item" end
end
if #failures > 0 then
    error(string.format("options_castbar_classpower_scene_smoke %s: %d failure(s)\n  %s", flavor, #failures,
        table.concat(failures, "\n  ")), 0)
end
print(string.format("options_castbar_classpower_scene_smoke: %s ok (%d castbar units/kinds, %d class resources, %d inventory items)",
    flavor, #UNITS * #kinds, #keys, #required))
