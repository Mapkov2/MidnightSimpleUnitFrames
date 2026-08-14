--- Class Resources preview module.
--- Menu-only composition for ClassPower, detached Player Power, and the
--- optional Class Resources Player HP bar. Runtime refresh remains outside the
--- drag loop; drag writes saved offsets and repaints only this preview.
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local Preview = M.ClassPowerStackPreview or {}
M.ClassPowerStackPreview = Preview
local function ClassPowerSurfaceShown(box)
    if not (box and box.IsShown and box:IsShown()) then return false end
    local hostShown = box._msufCPPreviewHostShown
    return type(hostShown) ~= "function" or hostShown(box) == true
end
local function ActivateClassPowerSurface(box)
    if box and not ClassPowerSurfaceShown(box) then box = nil end
    Preview.active = box
    return Preview.active
end
local W = M.Widgets
local T = M.Theme
local CPPreview = M.ClassPowerPreview or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local PreviewCore = MSUF.UFPreviewCore or {}
local Helpers = M.PreviewHelpers or {}
local ZoomPan = Preview.ZoomPan or {}
Preview.ZoomPan = ZoomPan
-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- animation driver's OnUpdate disabled.
local ONUPDATE_MODE_DISABLED = (_G.Enum and _G.Enum.OnUpdateMode and _G.Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (_G.Enum and _G.Enum.OnUpdateMode and _G.Enum.OnUpdateMode.RunWhenVisible) or 1
local function NormalizeControlPath(value)
    local path = tostring(value or "")
    path = path:gsub("([%l%d])([%u])", "%1_%2"):lower()
    path = path:gsub("[^%w]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return path
end
local function PreviewControlMeta(ctx, semanticPath, classification, exact)
    local pageKey = NormalizeControlPath((ctx and ctx.key) or M._msuf2SearchBuildKey or M.activeKey or "classpower")
    if pageKey == "" then pageKey = "classpower" end
    local path = NormalizeControlPath(semanticPath)
    local identity = pageKey .. ".class-power-preview." .. path
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = pageKey,
        classification = classification or "ephemeral",
    }
    if meta.classification == "ephemeral" then meta.ephemeral = true end
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    return meta
end
local function RegisterPreviewControl(ctx, widget, semanticPath, label, kind, classification, exact)
    if not (widget and type(M.RegisterSearchWidget) == "function") then return widget end
    local payload = PreviewControlMeta(ctx, semanticPath, classification, exact)
    payload.label = label
    payload.kind = kind
    M.RegisterSearchWidget(widget, payload)
    return widget
end
local floor = math.floor
local max = math.max
local min = math.min
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local PREVIEW_BORDER_COLOR = { 1.00, 0.02, 0.02, 1.00 }
local CP_PREVIEW_REFRESH_DELAY = 0.05
local CP_PREVIEW_ANIMATION_INTERVAL = 0.05
local CP_SHAPES, POWER_SHAPES = CPPreview.CLASS_SHAPES, CPPreview.POWER_SHAPES
local NormalizeClassShape, ResolvePowerShape = CPPreview.NormalizeClassShape, CPPreview.ResolvePowerShape
local CP_OUTLINE_OPTS = {
    linesKey = "_msufCPPreviewEdges",
    maxEdgeSize = 8,
    texture = WHITE8,
    color = function() return PREVIEW_BORDER_COLOR[1], PREVIEW_BORDER_COLOR[2], PREVIEW_BORDER_COLOR[3], PREVIEW_BORDER_COLOR[4] end,
}
local HP_TEXT_REVERSE = { CURMAX = "MAXCUR", MAXCUR = "CURMAX", CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT", CURMAXPERCENT = "PERCENTCURMAX", PERCENTCURMAX = "CURMAXPERCENT", PERCENTMAXCUR = "CURMAXPERCENT" }
local DELIMITERS = { [""] = " ", ["-"] = " - ", ["/"] = " / ", ["\\"] = " \\ ", ["|"] = " | ", ["<"] = " < ", [">"] = " > ", ["~"] = " ~ ", [":"] = " : " }
local function TR(text)
    return (M.Tr and M.Tr(text)) or text
end
local function RequestClassPowerPreviewRefresh(box, reason)
    if not (box and box.Refresh) then return end
    box._msufCPRefreshReason = reason or box._msufCPRefreshReason
    if box._msufCPRefreshQueued then return end
    box._msufCPRefreshQueued = true
    box._msufCPRefreshSerial = (tonumber(box._msufCPRefreshSerial) or 0) + 1
    local serial = box._msufCPRefreshSerial
    local function Run()
        if not box or serial ~= box._msufCPRefreshSerial then return end
        local refreshReason = box._msufCPRefreshReason
        box._msufCPRefreshReason = nil
        box._msufCPRefreshQueued = nil
        if box.IsShown and not box:IsShown() then return end
        if box._msufCPPreviewHostShown and not box:_msufCPPreviewHostShown() then return end
        box:Refresh(refreshReason or "CLASSPOWER_PREVIEW_REFRESH")
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(CP_PREVIEW_REFRESH_DELAY, Run)
    else
        Run()
    end
end
local function SetPreviewSummary(box, classFrame, powerFrame, hpFrame)
    if not (box and box.summary and box.summary.SetText) then return end
    local parts = {}
    if classFrame then parts[#parts + 1] = "Class Resource" end
    if powerFrame then parts[#parts + 1] = "Player Power" end
    if hpFrame then parts[#parts + 1] = "Second HP" end
    if #parts == 0 then
        box.summary:SetText(TR("Shown here: Player frame reference only"))
    else
        box.summary:SetText(TR("Shown here: ") .. table.concat(parts, " + "))
    end
end
if Helpers.InstallZoomPan and not ZoomPan._msufCPPreviewInstalled then
    ZoomPan._msufCPPreviewInstalled = true
    Helpers.InstallZoomPan(ZoomPan, {
        configureTableOnly = true,
        readoutField = "zoomReadout",
        fitButtonTextPath = { "zoomFitButton", "fs" },
        panPrefix = "_msufCPPreview",
        hintField = "hint",
        updateHintKey = "UpdateHandleHint",
        defaultReason = "CLASSPOWER_PREVIEW_ZOOM",
        stepReason = "CLASSPOWER_PREVIEW_ZOOM_STEP",
        themeButton = true,
        buttonTextureKey = "WHITE8",
        buttonFontField = "fs",
        refresh = function(box, reason)
            if box and box.Refresh then box:Refresh(reason or "CLASSPOWER_PREVIEW_ZOOM") end
        end,
    })
end
local CP_PREVIEW_LAYERS = {
    { key = "guides", label = "Guides", color = { 0.42, 0.72, 1.00 }, tooltip = "Mover handles and selected borders." },
    { key = "border", label = "Border", color = PREVIEW_BORDER_COLOR, tooltip = "Actual HP, Power and Class Resource outlines." },
    { key = "reference", label = "Reference", color = { 0.60, 0.66, 0.78 }, tooltip = "Player frame reference used for relative layout." },
    { key = "class", label = "Resource", color = { 0.30, 0.78, 0.55 }, tooltip = "Class resource bar or pips." },
    { key = "classText", label = "Res Text", color = { 0.30, 0.78, 0.55 }, tooltip = "Class resource numeric text." },
    { key = "power", label = "Power Bar", color = { 0.95, 0.72, 0.18 }, tooltip = "Detached player power bar bound to Class Resources." },
    { key = "powerText", label = "Power Txt", color = { 0.95, 0.72, 0.18 }, tooltip = "Detached player power text." },
    { key = "hp", label = "HP Bar", color = { 0.25, 0.90, 0.42 }, tooltip = "Extra player HP bar in Class Resources." },
    { key = "hpText", label = "HP Text", color = { 0.25, 0.90, 0.42 }, tooltip = "Extra player HP text." },
    { key = "bounds", label = "Bounds", color = { 1.00, 0.22, 0.12 }, tooltip = "Preview-only bounds around visible elements." },
}
local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end
local function Clamp(value, fallback, minValue, maxValue)
    value = tonumber(value) or fallback
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local function ClassTextLevel(owner, bars)
    local layer = bars and bars.classPowerTextLayer
    if Layers.TextLevel then return Layers.TextLevel(owner, layer, 5) end
    if Layers.ElementLevel then return Layers.ElementLevel(layer, 5, 8) end
    return 100 + Clamp(layer, 5, 0, 30) * 32 + 8
end
local function ApplyClassTextOwnerLevel(owner, bars)
    if owner and owner.SetFrameLevel then owner:SetFrameLevel(ClassTextLevel(owner, bars)) end
end
local function Alpha(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value == nil then value = 1 end
    if value > 1 then value = value / 100 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function EnsureDB()
    if type(M.EnsureDB) == "function" then return M.EnsureDB() end
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    return _G.MSUF_DB
end
local function Bars()
    local db = EnsureDB()
    db.bars = db.bars or {}
    return db.bars
end
local function Player()
    local db = EnsureDB()
    db.player = db.player or {}
    return db.player
end
local function General()
    local db = EnsureDB()
    db.general = db.general or {}
    return db.general
end
local function SetShownSafe(region, shown)
    if not region then return end
    if region.SetShown then
        region:SetShown(shown == true)
    elseif shown then
        region:Show()
    else
        region:Hide()
    end
end
local function PreviewParent(preview)
    return preview and (preview.stage or preview.canvas)
end
local function PreviewGuidesEnabled()
    local general = General()
    if general.classPowerPreviewGuidesEnabled ~= nil then return general.classPowerPreviewGuidesEnabled ~= false end
    return true
end
local function SetPreviewGuidesEnabled(enabled)
    General().classPowerPreviewGuidesEnabled = enabled ~= false
end
local function LayerOn(preview, key)
    if not preview then return false end
    local available = preview.layerAvailable
    if available and available[key] == false then return false end
    local visible = preview.layerVisibility
    if visible and visible[key] == false then return false end
    return true
end
local function GuidesOn(preview)
    return LayerOn(preview, "guides")
end
local function RefreshLayerButtons(preview)
    local buttons = preview and preview.layerButtons
    if not buttons then return end
    for i = 1, #buttons do
        if buttons[i].Refresh then buttons[i]:Refresh() end
    end
end
local function NormalizeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end
local function ResolveHPShape(bars, player)
    local value = tostring(bars and bars.playerHPBarShape or "BAR"):upper()
    if value ~= "FOLLOW_POWER" then return ResolvePowerShape(value, bars and bars.classPowerShape) end
    if not (player and player.powerBarDetached == true) then return "BAR" end
    return ResolvePowerShape(player.detachedPowerBarShape or "BAR", bars and bars.classPowerShape)
end
local function ShapeOutlineAlpha(value)
    value = tonumber(value) or 0
    if value <= 0 then return 0 end
    if value >= 8 then return 1 end
    return 0.49 + (value * 0.065)
end
local function AutoFitPips(segCount, height, gap)
    segCount = floor(tonumber(segCount) or 1)
    if segCount < 1 then segCount = 1 elseif segCount > 10 then segCount = 10 end
    height = floor(tonumber(height) or 1)
    if height < 1 then height = 1 end
    gap = floor(tonumber(gap) or 0)
    if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
    return (segCount * height) + ((segCount - 1) * gap)
end
local function AnimationEnabled(preview)
    return preview and preview._animationEnabled == true
end
local function PreviewAnimationInCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true) and true or false
end
local function PreviewElapsed(preview)
    return tonumber(preview and preview._animationElapsed) or 0
end
local function AnimatedMeterFraction(preview, fallback, speed, low, high)
    if not AnimationEnabled(preview) then return fallback end
    speed = tonumber(speed) or 0.42
    low = tonumber(low) or 0.08
    high = tonumber(high) or 0.96
    local phase = (PreviewElapsed(preview) * speed) % 2
    local wave = phase <= 1 and phase or (2 - phase)
    return low + (wave * (high - low))
end
local function PreviewOutline(preview, value, fallback)
    if not LayerOn(preview, "border") then return 0 end
    return Clamp(value, fallback or 0, 0, 8)
end
local function ResolveTexture(key, fallback)
    if CPPreview.ResolveTexture then return CPPreview.ResolveTexture(key, fallback) end
    if key and key ~= "" and type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        local path = _G.MSUF_ResolveStatusbarTextureKey(key)
        if path and path ~= "" then return path end
    end
    if fallback and fallback ~= "" then return fallback end
    if type(_G.MSUF_GetBarTexture) == "function" then
        local path = _G.MSUF_GetBarTexture()
        if path and path ~= "" then return path end
    end
    return WHITE8
end
local PREVIEW_CLASS_BY_PREFIX = { deathknight = "DEATHKNIGHT", demonhunter = "DEMONHUNTER", druid = "DRUID", evoker = "EVOKER", hunter = "HUNTER", mage = "MAGE", monk = "MONK", paladin = "PALADIN", priest = "PRIEST", rogue = "ROGUE", shaman = "SHAMAN", warlock = "WARLOCK", warrior = "WARRIOR" }
local function PreviewClassToken(spec)
    if spec and spec.classToken then return tostring(spec.classToken):upper() end
    if spec and spec.class then return tostring(spec.class):upper() end
    if type(M.GetClassPowerPreviewClassToken) == "function" then
        local class = M.GetClassPowerPreviewClassToken()
        if class then return tostring(class):upper() end
    end
    local key = tostring((spec and spec.key) or "")
    local prefix = key:match("^([^_]+)")
    return prefix and PREVIEW_CLASS_BY_PREFIX[prefix] or nil
end
local function ClassColor(dr, dg, db, spec)
    local class = PreviewClassToken(spec)
    if not class and UnitClass then
        local _
        _, class = UnitClass("player")
    end
    if type(_G.MSUF_UFCore_GetClassBarColorFast) == "function" then
        local r, g, b = _G.MSUF_UFCore_GetClassBarColorFast(class)
        if r then return r, g, b end
    end
    local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return dr or 0.95, dg or 0.82, db or 0.10
end
local function PowerColor()
    local pbc = _G.PowerBarColor
    local c = pbc and (pbc.ENERGY or pbc.MANA)
    if c then return c.r or c[1] or 1, c.g or c[2] or 0.82, c.b or c[3] or 0.10 end
    return 1.00, 0.86, 0.12
end
local function CPToken(spec, value)
    if CPPreview.TokenForValue then return CPPreview.TokenForValue(spec, value) end
    return spec and spec.token
end
local function CPBaseColor(spec, bars, fallbackR, fallbackG, fallbackB)
    if CPPreview.ResolveBaseColor then return CPPreview.ResolveBaseColor(spec, bars, fallbackR, fallbackG, fallbackB) end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end
local function CPColor(token, fallbackR, fallbackG, fallbackB)
    if CPPreview.ResolveColor then return CPPreview.ResolveColor(token, fallbackR, fallbackG, fallbackB) end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end
local function CPTextColor(fallbackR, fallbackG, fallbackB)
    if CPPreview.ResolveTextColor then return CPPreview.ResolveTextColor(fallbackR, fallbackG, fallbackB) end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end
local function CPTextAlpha()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local alpha = tonumber(g and g.fontTextAlpha) or 1
    if alpha < 0.7 then alpha = 0.7 elseif alpha > 1 then alpha = 1 end
    return alpha
end
local function CPBgColor(token)
    if CPPreview.ColorOverride then return CPPreview.ColorOverride("classPowerBgColorOverrides", token) end
    return nil
end
local function HPColor(bars, spec)
    local mode = tostring(bars and bars.playerHPBarColorMode or "GLOBAL"):upper()
    if mode == "DARK" then
        local cache = type(_G.MSUF_UFCore_GetSettingsCache) == "function" and _G.MSUF_UFCore_GetSettingsCache() or nil
        return (cache and cache.darkBarR) or 0.07, (cache and cache.darkBarG) or 0.07, (cache and cache.darkBarB) or 0.08
    end
    if mode == "GRADIENT" then
        local pct = 0.74
        local r = pct > 0.5 and (1 - (pct - 0.5) * 2) or 1
        local g = pct > 0.5 and 1 or (pct * 2)
        return r, g, 0
    end
    return ClassColor(0.20, 0.78, 0.26, spec)
end
local function ShortValue(value)
    value = tonumber(value) or 0
    local abbrev = _G.AbbreviateShortNumber or _G.AbbreviateLargeNumbers
    if type(abbrev) == "function" then
        local NumberFormat = MSUF.NumberFormat
        local text = abbrev(value, NumberFormat and NumberFormat.GetOptions and NumberFormat.GetOptions() or nil)
        if text ~= nil then return text end
    end
    local absValue = value < 0 and -value or value
    local sign = value < 0 and "-" or ""
    if absValue >= 1000000 then
        local n = floor((absValue / 100000) + 0.5) / 10
        return sign .. (n >= 10 and tostring(floor(n + 0.5)) or string.format("%.1f", n)) .. "M"
    elseif absValue >= 1000 then
        local n = floor((absValue / 100) + 0.5) / 10
        return sign .. (n >= 10 and tostring(floor(n + 0.5)) or string.format("%.1f", n)) .. "K"
    end
    return tostring(floor(value + 0.5))
end
local function ModeText(mode, current, maxValue, delimiter, hidePercentSymbol)
    mode = tostring(mode or "NONE"):upper()
    if mode == "NONE" then return "" end
    current = tonumber(current) or 0
    maxValue = tonumber(maxValue) or 1
    if maxValue < 1 then maxValue = 1 end
    delimiter = DELIMITERS[delimiter] or delimiter or " "
    local pct = floor((current / maxValue) * 100 + 0.5)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    local curText, maxText, pctText = ShortValue(current), ShortValue(maxValue), tostring(pct)
    if hidePercentSymbol ~= true then pctText = pctText .. "%" end
    if mode == "CURRENT" then return curText end
    if mode == "MAX" then return maxText end
    if mode == "DEFICIT" then
        local missing = maxValue - current
        return missing > 0 and ("-" .. ShortValue(missing)) or ""
    end
    if mode == "PERCENT" then return pctText end
    if mode == "CURMAX" then return curText .. delimiter .. maxText end
    if mode == "MAXCUR" then return maxText .. delimiter .. curText end
    if mode == "CURPERCENT" then return curText .. delimiter .. pctText end
    if mode == "PERCENTCUR" then return pctText .. delimiter .. curText end
    if mode == "MAXPERCENT" then return maxText .. delimiter .. pctText end
    if mode == "PERCENTMAX" then return pctText .. delimiter .. maxText end
    if mode == "CURMAXPERCENT" then return curText .. delimiter .. maxText .. delimiter .. pctText end
    if mode == "PERCENTCURMAX" then return pctText .. delimiter .. curText .. delimiter .. maxText end
    if mode == "PERCENTMAXCUR" then return pctText .. delimiter .. maxText .. delimiter .. curText end
    return curText
end
local function GlobalHidePercentSymbol()
    local db = M.EnsureDB and M.EnsureDB()
    local g = db and db.general
    return g and g.hidePercentSymbol == true
end
local function HidePercentValue(source, key)
    if source and source[key] ~= nil then return source[key] == true end
    return GlobalHidePercentSymbol()
end
local function ApplyFont(region, size)
    if not (region and region.SetFont) then return end
    size = Clamp(size, 12, 6, 48)
    local fontPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or _G.STANDARD_TEXT_FONT
    local fontFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
    if not fontPath or fontPath == "" then fontPath = "Fonts\\FRIZQT__.TTF" end
    if not fontFlags or fontFlags == "" then fontFlags = "OUTLINE" end
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        fontPath = resolveSafe(fontPath, size, fontFlags, g and g.fontKey)
    end
    local ok = pcall(region.SetFont, region, fontPath, size, fontFlags)
    if not ok then
        pcall(region.SetFont, region, "Fonts\\FRIZQT__.TTF", size, fontFlags)
    end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then
        local _, _, _, _, _, _, enabled = _G.MSUF_GetGlobalFontSettings()
        useShadow = enabled
    end
    if useShadow == nil then useShadow = not (g and g.textBackdrop == false) end
    if useShadow then
        local shadowAlpha, shadowX, shadowY = 1, 1, -1
        if type(_G.MSUF_ResolveFontShadowMetrics) == "function" then
            shadowAlpha, shadowX, shadowY = _G.MSUF_ResolveFontShadowMetrics(
                g and g.fontShadowOpacity, g and g.fontShadowDistance, g and g.fontShadowStrength)
        end
        if region.SetShadowColor then region:SetShadowColor(0, 0, 0, shadowAlpha) end
        if region.SetShadowOffset then region:SetShadowOffset(shadowX, shadowY) end
    elseif region.SetShadowOffset then
        region:SetShadowOffset(0, 0)
    end
end
local function HideTableRegions(t)
    if not t then return end
    for i = 1, #t do
        if t[i] and t[i].Hide then t[i]:Hide() end
    end
end
local function EnsureOutlineHost(frame)
    local parent = frame and frame:GetParent()
    if not parent then return nil end
    local host = frame._msufCPPreviewOutlineHost
    if not host then
        host = CreateFrame("Frame", nil, parent)
        host:EnableMouse(false)
        frame._msufCPPreviewOutlineHost = host
    end
    if host:GetParent() ~= parent then host:SetParent(parent) end
    return host
end
local function ApplyBarOutline(frame, outline)
    local host = EnsureOutlineHost(frame)
    if not (host and Helpers.LayoutEdgeLines) then return end
    outline = floor((tonumber(outline) or 0) + 0.5)
    if outline <= 0 then
        if Helpers.SetEdgeLinesShown then Helpers.SetEdgeLinesShown(host, false, CP_OUTLINE_OPTS) end
        if host then host:Hide() end
        return
    end
    if outline > 8 then outline = 8 end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", -outline, outline)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outline, -outline)
    local parent = host:GetParent()
    host:SetFrameLevel(((parent and parent.GetFrameLevel and parent:GetFrameLevel()) or 0) + 74)
    host:Show()
    Helpers.LayoutEdgeLines(host, outline, CP_OUTLINE_OPTS)
end
local function HideBarOutline(frame)
    local host = frame and frame._msufCPPreviewOutlineHost
    if host and Helpers.SetEdgeLinesShown then Helpers.SetEdgeLinesShown(host, false, CP_OUTLINE_OPTS) end
    if host then host:Hide() end
end
local CP_POWER_ROUNDED_OPTS = {
    bgKey = "_msufCPRoundedBg",
    edgeKey = "_msufCPRoundedEdge",
    stackKey = "_msufCPRoundedEdgeStack",
    countKey = "_msufCPRoundedEdgeCount",
    whiteTexture = WHITE8,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    snapOff = Helpers.SnapOff,
    baseEdgeColor = function()
        local db = _G.MSUF_DB or {}
        local player = db.units and db.units.player or {}
        local general = db.general or {}
        return tonumber(player.barOutlineColorR) or tonumber(general.barBorderR) or 0,
            tonumber(player.barOutlineColorG) or tonumber(general.barBorderG) or 0,
            tonumber(player.barOutlineColorB) or tonumber(general.barBorderB) or 0,
            tonumber(player.barOutlineColorA) or tonumber(general.barBorderA) or 1
    end,
}
local CP_CLASS_ROUNDED_OPTS = {
    bgKey = "_msufCPClassRoundedBg",
    edgeKey = "_msufCPClassRoundedEdge",
    stackKey = "_msufCPClassRoundedEdgeStack",
    countKey = "_msufCPClassRoundedEdgeCount",
    maskStoreKey = "_msufCPClassRoundedMasks",
    maskedKey = "_msufCPClassRoundedMasked",
    whiteTexture = WHITE8,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    maxEdgeSize = 8,
    snapOff = Helpers.SnapOff,
    baseEdgeColor = function() return 0, 0, 0, 1 end,
}
local function RoundedClassResourcesPreviewEnabled(bars)
    return bars and bars.roundedFramesEnabled == true
        and bars.roundedClassResources == true
end
local function RoundedPowerPreviewEnabled()
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    return bars and bars.roundedFramesEnabled == true
        and bars.roundedUnitFrames ~= false
        and bars.roundedPowerBars ~= false
end
local function SetRoundedPowerPreview(frame, enabled, outline)
    if not frame then return false end
    if not enabled or not RoundedPowerPreviewEnabled()
        or not (Helpers.ResolveRoundedMedia and Helpers.EnsureRoundedMask and Helpers.SetMask and Helpers.EnsureRoundedVisuals) then
        if Helpers.ClearMasks then Helpers.ClearMasks(frame, "_msufCPRoundedMasked") end
        if Helpers.SetRoundedEdgeStackShown then Helpers.SetRoundedEdgeStackShown(frame, false, CP_POWER_ROUNDED_OPTS) end
        if frame._msufCPRoundedBg then frame._msufCPRoundedBg:Hide() end
        return false
    end
    local maskPath, edgePath, strength = Helpers.ResolveRoundedMedia()
    CP_POWER_ROUNDED_OPTS.edgeTexture = edgePath
    CP_POWER_ROUNDED_OPTS.mediaStrength = strength
    local bgMask = Helpers.EnsureRoundedMask(frame, "background", frame, frame.bg,
        "_msufCPRoundedMasks", maskPath, Helpers.SnapOff)
    local fillMask = Helpers.EnsureRoundedMask(frame, "fill", frame, frame.fill,
        "_msufCPRoundedMasks", maskPath, Helpers.SnapOff)
    if not (bgMask and fillMask and Helpers.EnsureRoundedVisuals(frame, CP_POWER_ROUNDED_OPTS)) then return false end
    Helpers.SetMask(frame, frame.bg, bgMask, "_msufCPRoundedMasked")
    Helpers.SetMask(frame, frame.fill, fillMask, "_msufCPRoundedMasked")
    HideBarOutline(frame)
    outline = floor((tonumber(outline) or 0) + 0.5)
    if outline > 8 then outline = 8 end
    if outline > 0 and Helpers.ApplyRoundedEdgeStack then
        Helpers.ApplyRoundedEdgeStack(frame, outline, CP_POWER_ROUNDED_OPTS)
    elseif Helpers.SetRoundedEdgeStackShown then
        Helpers.SetRoundedEdgeStackShown(frame, false, CP_POWER_ROUNDED_OPTS)
    end
    if frame._msufCPRoundedBg then frame._msufCPRoundedBg:Hide() end
    return true
end
local function CallApply(handle, reason)
    local kind = handle and handle._applyKind
    local moveOnly = reason == "CLASSPOWER_PREVIEW_MOVE" and kind ~= "powerText"
    if not moveOnly then
        if kind == "class" or kind == "classText" then
            if type(_G.MSUF_ClassPower_Apply) == "function" then
                _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, playerHP = true, syncNow = false })
            elseif type(_G.MSUF_ClassPower_Refresh) == "function" then
                _G.MSUF_ClassPower_Refresh()
                if type(_G.MSUF_ClassPower_PlayerHP_Refresh) == "function" then _G.MSUF_ClassPower_PlayerHP_Refresh() end
            end
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true) end
        elseif kind == "power" or kind == "powerText" then
            if kind == "powerText" and type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then _G.MSUF_ForceTextLayoutForUnitKey("player") end
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true) end
            if type(_G.MSUF_ClassPower_Apply) == "function" then
                _G.MSUF_ClassPower_Apply({ playerHP = true })
            elseif type(_G.MSUF_ClassPower_PlayerHP_Refresh) == "function" then
                _G.MSUF_ClassPower_PlayerHP_Refresh()
            end
        elseif kind == "hp" or kind == "hpText" then
            if type(_G.MSUF_ClassPower_Apply) == "function" then
                _G.MSUF_ClassPower_Apply({ playerHP = true })
            elseif type(_G.MSUF_ClassPower_PlayerHP_Refresh) == "function" then
                _G.MSUF_ClassPower_PlayerHP_Refresh()
            end
        end
    end
    local applyReason = reason or "MSUF2_CLASSPOWER_PREVIEW_MOVE"
    local previewQueued = false
    if type(M.RequestGeneralApply) == "function" then
        previewQueued = M.RequestGeneralApply(applyReason, {
            preview = true,
            applyAll = false,
            notify = false,
            history = false,
        }) ~= false
    end
    if not previewQueued and type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason or "CLASSPOWER_PREVIEW_MOVE")
    end
end
local function StoreForHandle(handle)
    if not handle then return nil end
    if handle._store == "player" then return Player() end
    return Bars()
end
local function ReadHandle(handle)
    local store = StoreForHandle(handle)
    local x = store and tonumber(store[handle._xKey]) or nil
    local y = store and tonumber(store[handle._yKey]) or nil
    if x == nil then x = tonumber(handle._defaultX) or 0 end
    if y == nil then y = tonumber(handle._defaultY) or 0 end
    return x, y
end

--- Handle writes update the same SavedVariables offsets used by runtime
--- ClassPower, but only repaint this preview unless the caller asks to apply.
local function WriteHandle(handle, x, y, skipApply)
    local store = StoreForHandle(handle)
    if not (store and handle and handle._xKey and handle._yKey) then return end
    store[handle._xKey] = Round(x)
    store[handle._yKey] = Round(y)
    if handle._applyKind == "powerText" and type(M.SyncDirectTextOffsets) == "function" then
        M.SyncDirectTextOffsets(store, handle._xKey)
        M.SyncDirectTextOffsets(store, handle._yKey)
    end
    if type(M.RefreshVisibleSliders) == "function" then M.RefreshVisibleSliders("CLASSPOWER_PREVIEW_MOVE") end
    RequestClassPowerPreviewRefresh(handle._preview, "CLASSPOWER_PREVIEW_DRAG")
    if not skipApply then CallApply(handle, "CLASSPOWER_PREVIEW_MOVE") end
end
local function ClassPowerRouteForHandle(handle)
    local kind = handle and (handle._applyKind or handle._layerKey or handle._key) or "class"
    local section, state, tab = "classpower_display"
    if kind == "classText" then section, state, tab = "classpower_visuals", "classPowerStyleTab", "text"
    elseif kind == "power" or kind == "powerText" then section, state, tab = "classpower_detached_power", "classPowerDetachedPowerTab", kind == "power" and "layout" or "text"
    elseif kind == "hp" or kind == "hpText" then section, state, tab = "classpower_player_hp", "classPowerPlayerHPTab", kind == "hp" and "layout" or "text" end
    if state then
        if type(M.SetMenuStateValue) == "function" then M.SetMenuStateValue(state, tab) else M[state] = tab end
    end
    return section
end
local function OpenClassPowerHandleSettings(handle)
    if not (M and type(M.SelectPage) == "function") then return false end
    _G.MSUF_EM2_MenuFocusRequest = {
        pageKey = "classpower",
        sectionId = ClassPowerRouteForHandle(handle),
        component = handle and handle._key,
        source = "classpower-preview",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    return M.SelectPage("classpower") ~= false
end
local function RefreshHandleVisuals(preview)
    if not (preview and preview.handles) then return end
    local guidesOn = GuidesOn(preview)
    for i = 1, #preview.handles do
        local h = preview.handles[i]
        if h and h._msufPlaced ~= true then
            h:Hide()
        elseif h then
            SetShownSafe(h, guidesOn and LayerOn(preview, h._layerKey or h._key))
        end
        local active = h == preview.selectedHandle or h._hovering == true
        local c = h._color or { 1, 1, 1 }
        if h.SetBackdropColor then h:SetBackdropColor(c[1], c[2], c[3], active and 0.16 or 0.035) end
        if h.SetBackdropBorderColor then h:SetBackdropBorderColor(c[1], c[2], c[3], active and 0.95 or 0.44) end
        if h._msuf2SettingsGear then h._msuf2SettingsGear:SetShown(guidesOn and h == preview.selectedHandle and h._msufPlaced == true) end
    end
    local selected = preview.selectedHandle
    if selected and selected._msufPlaced == true and guidesOn and Helpers.EnsurePreviewHandleGear then
        Helpers.EnsurePreviewHandleGear(selected, {
            T = T,
            Tr = TR,
            shown = true,
            openSettings = OpenClassPowerHandleSettings,
        })
    end
    if preview.hint then
        if selected and selected._msufPlaced == true then
            local x, y = ReadHandle(selected)
            preview.hint:SetText(string.format("%s   x: %d   y: %d",
                TR(selected._label or selected._key or "Element"), Round(x or 0), Round(y or 0)))
        else
            preview.hint:SetText(TR("Drag handles to move."))
        end
    end
end
-- Shared preview-keyboard helpers keep ClassPower and Unit preview nudging in
-- lockstep while the DB write/apply behavior remains local to this module.
local IsTextInputFocused = Helpers.IsTextInputFocused or function() return false end
local NudgeStep = Helpers.NudgeStep or function() return 1 end
local function CanNudgeHandle(handle)
    local preview = handle and handle._preview
    return handle ~= nil
        and preview ~= nil
        and handle._msufPlaced == true
        and LayerOn(preview, handle._layerKey or handle._key)
end
local function ShouldSkipDuplicateNudge(preview, dx, dy)
    return Helpers.ShouldSkipDuplicateNudge and Helpers.ShouldSkipDuplicateNudge(preview, dx, dy, {
        sigKey = "_msufCPPreviewLastNudgeSig",
        atKey = "_msufCPPreviewLastNudgeAt",
    }) or false
end
local function NudgeSelectedHandle(preview, dx, dy)
    local handle = preview and preview.selectedHandle
    if not CanNudgeHandle(handle) or IsTextInputFocused() then return false end
    local step = NudgeStep()
    local ndx, ndy = (tonumber(dx) or 0) * step, (tonumber(dy) or 0) * step
    if ShouldSkipDuplicateNudge(preview, ndx, ndy) then return true end
    local x, y = ReadHandle(handle)
    WriteHandle(handle, x + ndx, y + ndy, false)
    return true
end
local function FocusPreviewKeyboardTarget(preview, handle, defer)
    if Helpers.FocusKeyboardTarget then return Helpers.FocusKeyboardTarget(preview, handle, defer, { selectedField = "selectedHandle" }) end
end
local function OnCPPreviewArrowNudge(active, dx, dy)
    if NudgeSelectedHandle(active, dx, dy) then FocusPreviewKeyboardTarget(active, active and active.selectedHandle, true) end
end
local CP_PREVIEW_ARROW_BINDINGS = { ownerName = "MSUF_CPPreview_NudgeOwner", activeName = "MSUF_CPPreview_ActiveNudgeBox", buttonPrefix = "MSUF_CPPreview_Nudge", onClick = OnCPPreviewArrowNudge }
local function SetArrowBindings(preview, enabled)
    return M.SetPreviewArrowBindings(preview, enabled, CP_PREVIEW_ARROW_BINDINGS)
end
local function RegisterPreviewNudgeTarget(preview)
    if Helpers.RegisterEditModeNudgeTarget then
        Helpers.RegisterEditModeNudgeTarget(preview, {
            targetField = "_msufCPPreviewNudgeTarget",
            selectedField = "selectedHandle",
            canNudge = CanNudgeHandle,
            nudgeDelta = function(active, dx, dy)
                local handle = active and active.selectedHandle
                if not CanNudgeHandle(handle) then return false end
                local ndx, ndy = tonumber(dx) or 0, tonumber(dy) or 0
                if ShouldSkipDuplicateNudge(active, ndx, ndy) then return true end
                local x, y = ReadHandle(handle)
                WriteHandle(handle, x + ndx, y + ndy, false)
                return true
            end,
        })
    end
end
local function SelectHandle(handle)
    local preview = handle and handle._preview
    if not preview then return end
    preview.selectedHandle = handle
    FocusPreviewKeyboardTarget(preview, handle, true)
    SetArrowBindings(preview, true)
    RegisterPreviewNudgeTarget(preview)
    RefreshHandleVisuals(preview)
end
local function ExactPreviewDelta(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
local function FindClassPowerPreviewHandle(preview, handleKey)
    if not (preview and type(handleKey) == "string" and handleKey ~= "") then return nil end
    for i = 1, #(preview.handles or {}) do
        local handle = preview.handles[i]
        if handle and handle._key == handleKey then return handle end
    end
    return nil
end
local function RestoreClassPowerPreviewSelection(preview, previous)
    if previous and previous._preview == preview then
        SelectHandle(previous)
        return
    end
    preview.selectedHandle = nil
    SetArrowBindings(preview, false)
    FocusPreviewKeyboardTarget(preview, nil, false)
    RefreshHandleVisuals(preview)
end

--- Move one explicitly named handle on the visible Class Resources preview.
--- Exact DB readback is mandatory and a mismatch is rolled back. This API does
--- not inspect Edit Mode's selected mover or its shared preview nudge target.
function Preview.NudgeHandle(handleKey, dx, dy)
    if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false, "combat-locked" end
    if type(handleKey) ~= "string" or handleKey == "" then return false, "handle-required" end
    dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
    if dx == nil or dy == nil then return false, "invalid-delta" end
    local preview = Preview.active
    if not (preview and preview.IsShown and preview:IsShown() and (not preview.IsVisible or preview:IsVisible())) then return false, "preview-not-visible" end
    local handle = FindClassPowerPreviewHandle(preview, handleKey)
    if not handle then return false, "unknown-handle" end
    if handle._dragging == true or (preview.dragFrame and preview.dragFrame._handle) then return false, "handle-busy" end
    if not CanNudgeHandle(handle) or (handle.IsShown and not handle:IsShown()) then return false, "handle-not-visible" end
    local store = StoreForHandle(handle)
    if not (store and handle._xKey and handle._yKey) then return false, "handle-not-readable" end
    local beforeX, beforeY = ReadHandle(handle)
    if tonumber(beforeX) == nil or tonumber(beforeY) == nil then return false, "handle-not-readable" end
    beforeX, beforeY = tonumber(beforeX), tonumber(beforeY)
    local expectedX, expectedY = Round(beforeX + dx), Round(beforeY + dy)
    local previous = preview.selectedHandle
    SelectHandle(handle)
    if preview.selectedHandle ~= handle then
        RestoreClassPowerPreviewSelection(preview, previous)
        return false, "selection-failed"
    end
    if expectedX == beforeX and expectedY == beforeY then return true, beforeX, beforeY, beforeX, beforeY end

    local outcome
    local function Mutate()
        WriteHandle(handle, expectedX, expectedY, false)
        local afterX, afterY = ReadHandle(handle)
        afterX, afterY = tonumber(afterX), tonumber(afterY)
        if afterX == expectedX and afterY == expectedY then
            outcome = { true, beforeX, beforeY, afterX, afterY }
            return true
        end
        WriteHandle(handle, beforeX, beforeY, false)
        local restoredX, restoredY = ReadHandle(handle)
        local rolledBack = tonumber(restoredX) == beforeX and tonumber(restoredY) == beforeY
        local reason = not rolledBack and "rollback-failed" or "readback-mismatch"
        outcome = { false, reason }
        return false
    end
    local capturing = type(M.IsHistoryCapturing) == "function" and M.IsHistoryCapturing()
    if type(M.CaptureHistory) == "function" and not capturing then
        M.CaptureHistory("Nudge: " .. tostring(handle._label or handleKey),
            "classPowerPreview:" .. handleKey .. ":exact-nudge", Mutate)
    else
        Mutate()
        if outcome and outcome[1] and type(M.CheckpointHistory) == "function" then
            M.CheckpointHistory("Nudge: " .. tostring(handle._label or handleKey),
                "classPowerPreview:" .. handleKey .. ":exact-nudge")
        end
    end
    if not (outcome and outcome[1]) then RestoreClassPowerPreviewSelection(preview, previous) end
    if outcome and outcome[1] then return true, outcome[2], outcome[3], outcome[4], outcome[5] end
    return false, (outcome and outcome[2]) or "write-failed"
end
function Preview.Pan(dx, dy)
    if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false, "combat-locked" end
    dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
    if dx == nil or dy == nil then return false, "invalid-delta" end
    local preview = Preview.active
    if not (preview and preview.IsShown and preview:IsShown() and (not preview.IsVisible or preview:IsVisible())) then return false, "preview-not-visible" end
    if (preview.canvas and preview.canvas._msufCPPreviewPanning) or (preview.dragFrame and preview.dragFrame._handle) then return false, "preview-busy" end
    if type(ZoomPan.NudgePan) ~= "function" then return false, "pan-api-unavailable" end
    return ZoomPan.NudgePan(preview, dx, dy)
end
ExportPublic("MSUF_ClassPowerPreview_NudgeHandle", function(handleKey, dx, dy)
    return Preview.NudgeHandle(handleKey, dx, dy)
end)
ExportPublic("MSUF_ClassPowerPreview_Pan", function(dx, dy)
    return Preview.Pan(dx, dy)
end)
local function HandleKeyDown(handle, key)
    if Helpers.ArrowKeyDown then
        return Helpers.ArrowKeyDown(handle, key, {
            selectedField = "selectedHandle",
            nudge = NudgeSelectedHandle,
        })
    end
end
local function BeginHistory(handle)
    if M.BeginHistoryTransaction then return M.BeginHistoryTransaction("Move: " .. tostring(handle and handle._label or "Class Resources preview"), "classPowerPreview:" .. tostring(handle and handle._key or "handle")) end
    return false
end
local function CommitHistory(handle)
    if handle and handle._historyTx and M.CommitHistoryTransaction then
        handle._historyTx = nil
        return M.CommitHistoryTransaction()
    end
    if handle then handle._historyTx = nil end
    return false
end
local function StopHandleDrag(handle, button, skipApply, allowOpenSettings)
    if button and button ~= "LeftButton" then return end
    if not (handle and handle._dragging) then return end
    local preview = handle._preview
    local didMove = handle._didDragMove == true
    if didMove and Helpers.NotePreviewElementMoved then Helpers.NotePreviewElementMoved() end
    local openSettingsOnRelease = allowOpenSettings == true
        and button == "LeftButton"
        and not didMove
    handle._dragging = nil
    handle._didDragMove = nil
    if preview then
        preview._dragFrozenScale = nil
        preview._dragFrozenBaseOffsetX = nil
        preview._dragFrozenBaseOffsetY = nil
    end
    if preview and preview.dragFrame and preview.dragFrame._handle == handle then
        preview.dragFrame:SetScript("OnUpdate", nil)
        preview.dragFrame._handle = nil
        preview.dragFrame:Hide()
    end
    RequestClassPowerPreviewRefresh(preview, "CLASSPOWER_PREVIEW_DRAG_END")
    if not skipApply then CallApply(handle, "CLASSPOWER_PREVIEW_DRAG_END") end
    CommitHistory(handle)
    RefreshHandleVisuals(preview)
    FocusPreviewKeyboardTarget(preview, handle, true)
    if openSettingsOnRelease then OpenClassPowerHandleSettings(handle) end
end

--- Drag handles are preview controls, not runtime frames. They carry the DB
--- keys they edit so drag/nudge/history code can stay generic.
local function MakeHandle(preview, key, store, xKey, yKey, defaultX, defaultY, label, color, applyKind, layerKey, interactionPriority)
    local h = CreateFrame("Button", nil, PreviewParent(preview), "BackdropTemplate")
    h:SetSize(24, 20)
    h:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    -- Class Resource text can live on any absolute element layer. Keep every
    -- mouse catcher above that visual stack, and keep the smaller text handles
    -- deterministically above their broad bar handles.
    interactionPriority = tonumber(interactionPriority) or 0
    h:SetFrameLevel((PreviewCore.InteractionFrameLevel
        and PreviewCore.InteractionFrameLevel(PreviewParent(preview), interactionPriority))
        or ((preview.canvas:GetFrameLevel() or 0) + 140 + interactionPriority))
    h:EnableMouse(true)
    if Helpers.BindPreviewWheel then Helpers.BindPreviewWheel(h, preview) end
    h:EnableKeyboard(true)
    if h.SetPropagateKeyboardInput then h:SetPropagateKeyboardInput(true) end
    if h.RegisterForClicks then h:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp") end
    if h.RegisterForDrag then h:RegisterForDrag("LeftButton") end
    h._preview, h._key, h._store = preview, key, store
    h._xKey, h._yKey = xKey, yKey
    h._defaultX, h._defaultY = defaultX, defaultY
    h._label, h._color, h._applyKind = label, color, applyKind
    h._layerKey = layerKey or key
    h:SetScript("OnEnter", function(self)
        self._hovering = true
        RefreshHandleVisuals(preview)
        local showTooltip = GameTooltip and (not Helpers.ShouldShowPreviewHandleTooltip
            or Helpers.ShouldShowPreviewHandleTooltip(preview))
        if showTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR(label), 1, 1, 1)
            GameTooltip:AddLine(TR("Drag to move. Arrow keys nudge."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
            GameTooltip:Show()
        end
    end)
    h:SetScript("OnLeave", function(self)
        self._hovering = nil
        RefreshHandleVisuals(preview)
        if GameTooltip then GameTooltip:Hide() end
    end)
    h:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            SelectHandle(self)
            if Helpers.ShowPreviewHandleContext then
                Helpers.ShowPreviewHandleContext(self, {
                    M = M,
                    T = T,
                    Tr = TR,
                    title = self._label or self._key,
                    openSettings = OpenClassPowerHandleSettings,
                })
            end
            return
        end
        SelectHandle(self)
    end)
    h:SetScript("OnKeyDown", HandleKeyDown)
    h:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if self._dragging then return end
        SelectHandle(self)
        if Helpers.ShowPreviewMoveCue then Helpers.ShowPreviewMoveCue(preview, self) end
        self._didDragMove = nil
        self._dragging = true
        self._startX, self._startY = ReadHandle(self)
        self._lastX, self._lastY = nil, nil
        self._cursorX, self._cursorY = GetCursorPosition()
        preview._dragFrozenScale = tonumber(preview._mockScale) or tonumber(preview._mockAutoScale) or 1
        preview._dragFrozenBaseOffsetX = tonumber(preview._mockBaseOffsetX) or 0
        preview._dragFrozenBaseOffsetY = tonumber(preview._mockBaseOffsetY) or 0
        self._historyTx = BeginHistory(self)
        preview.dragFrame._handle = self
        preview.dragFrame:SetScript("OnUpdate", preview.dragUpdate)
        preview.dragFrame:Show()
    end)
    h:SetScript("OnMouseUp", function(self, button) StopHandleDrag(self, button, false, true) end)
    h:SetScript("OnDragStart", function(self) self:GetScript("OnMouseDown")(self, "LeftButton") end)
    h:SetScript("OnDragStop", function(self) StopHandleDrag(self, "LeftButton", false, false) end)
    h:SetScript("OnHide", function(self)
        StopHandleDrag(self, nil, true, false)
    end)
    h._msuf2CommandAction = {
        kind = "button",
        historyMode = "none",
        interaction = "preview.handle.select",
        previewSurface = "class-power",
        previewHandleKey = key,
        set = function()
            if h._msufPlaced ~= true then return false end
            if h.IsShown and not h:IsShown() then return false end
            SelectHandle(h)
            return preview.selectedHandle == h
        end,
    }
    RegisterPreviewControl(preview._catalogCtx, h, "handle." .. tostring(key), label or key, "button", "ephemeral", {
        help = "Moves this Class Resources preview element and opens its quick actions.",
    })
    if Helpers.EnsurePreviewHandleGear then
        local gear = Helpers.EnsurePreviewHandleGear(h, {
            T = T,
            Tr = TR,
            shown = false,
            openSettings = OpenClassPowerHandleSettings,
        })
        gear._msuf2ClassPowerOpenCommand = gear._msuf2ClassPowerOpenCommand or {
            kind = "button",
            historyMode = "none",
            canExecute = function() return h ~= nil end,
            set = function() return OpenClassPowerHandleSettings(h) end,
        }
        RegisterPreviewControl(preview._catalogCtx, gear, "handle." .. tostring(key) .. ".open_settings",
            "Open " .. tostring(label or key) .. " settings", "button", "action", {
                historyMode = "none",
                help = "Opens the settings section for this preview element.",
                command = gear._msuf2ClassPowerOpenCommand,
            })
    end
    preview.handles[#preview.handles + 1] = h
    h:Hide()
    return h
end
local function PlaceHandle(handle, region, pad)
    if not (handle and region and region.IsShown and region:IsShown()) then
        if handle then
            handle._msufPlaced = false
            handle:Hide()
        end
        return false
    end
    pad = tonumber(pad) or 4
    handle:ClearAllPoints()
    handle:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
    handle:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    handle._msufPlaced = true
    handle:Show()
    return true
end
local function PlaceTextHandle(handle, parent, regions)
    if Helpers.PlaceHandleAroundRegions and Helpers.PlaceHandleAroundRegions(handle, parent, regions, 4, { fitText = true }) then
        handle._msufPlaced = true
        return true
    end
    for i = 1, #(regions or {}) do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() then
            handle:ClearAllPoints()
            handle:SetSize(max(24, (region.GetStringWidth and region:GetStringWidth() or 20) + 10), max(18, (region.GetStringHeight and region:GetStringHeight() or 12) + 6))
            handle:SetPoint("CENTER", region, "CENTER", 0, 0)
            handle._msufPlaced = true
            handle:Show()
            return true
        end
    end
    handle._msufPlaced = false
    handle:Hide()
    return false
end
local function MakeText(parent, layer, justify, subLevel)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlightSmall", subLevel)
    fs:SetJustifyH(justify or "CENTER")
    if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    return fs
end
local function MakeTexture(parent, layer, subLevel, allPoints, hidden)
    local tex = parent:CreateTexture(nil, layer, nil, subLevel)
    tex:SetTexture(WHITE8)
    if allPoints then tex:SetAllPoints() end
    if hidden then tex:Hide() end
    return tex
end
local function EnsureClassPower(preview)
    if preview.classPower then return preview.classPower end
    local frame = CreateFrame("Frame", nil, PreviewParent(preview), "BackdropTemplate")
    frame:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    frame.textOwner = CreateFrame("Frame", nil, frame)
    frame.textOwner:SetAllPoints(frame)
    if frame.textOwner.EnableMouse then frame.textOwner:EnableMouse(false) end
    frame.segments, frame.bgs, frame.edges, frame.runeTexts, frame.hashes = {}, {}, {}, {}, {}
    for i = 1, 10 do
        frame.bgs[i] = MakeTexture(frame, "BACKGROUND", nil, nil, true)
        frame.segments[i] = MakeTexture(frame, "ARTWORK", nil, nil, true)
        frame.edges[i] = MakeTexture(frame, "OVERLAY", 5, nil, true)
        local runeText = MakeText(frame.textOwner, "OVERLAY", "CENTER", 9)
        runeText:Hide()
        frame.runeTexts[i] = runeText
        frame.hashes[i] = MakeTexture(frame, "OVERLAY", 7, nil, true)
    end
    frame.text = MakeText(frame.textOwner, "OVERLAY", "CENTER", 9)
    frame.text:Hide()
    preview.classPower = frame
    return frame
end
local function EnsureMeter(preview, name, separateTextOwner)
    if preview[name] then return preview[name] end
    local frame = CreateFrame("Frame", nil, PreviewParent(preview), "BackdropTemplate")
    frame:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    frame.bg = MakeTexture(frame, "BACKGROUND", nil, true)
    frame.fill = MakeTexture(frame, "ARTWORK")
    frame.edge = MakeTexture(frame, "OVERLAY", 7, true, true)
    local textOwner = frame
    if separateTextOwner then
        textOwner = CreateFrame("Frame", nil, frame)
        textOwner:SetAllPoints(frame)
        if textOwner.EnableMouse then textOwner:EnableMouse(false) end
        frame.textOwner = textOwner
    end
    frame.left = MakeText(textOwner, "OVERLAY", "LEFT")
    frame.center = MakeText(textOwner, "OVERLAY", "CENTER")
    frame.right = MakeText(textOwner, "OVERLAY", "RIGHT")
    preview[name] = frame
    return frame
end
local function RenderMeter(frame, shapeInfo, opts)
    opts = opts or {}
    local w = max(1, floor(tonumber(opts.width) or 1))
    local h = max(1, floor(tonumber(opts.height) or 1))
    local frac = tonumber(opts.fraction) or 1
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    frame._msufCPPreviewW = w
    frame._msufCPPreviewH = h
    frame._msufCPPreviewShapeAxis = shapeInfo and shapeInfo.axis or nil
    frame._msufCPPreviewHasShape = shapeInfo ~= nil
    frame:SetSize(w, h)
    frame.bg:ClearAllPoints()
    frame.bg:SetAllPoints(frame)
    frame.fill:ClearAllPoints()
    if shapeInfo then
        HideBarOutline(frame)
        frame.bg:SetTexture(shapeInfo.bg)
        frame.bg:SetVertexColor(opts.bgR or opts.r or 1, opts.bgG or opts.g or 1, opts.bgB or opts.b or 1, opts.bgA or 0.28)
        frame.fill:SetTexture(shapeInfo.fill)
        frame.fill:SetVertexColor(opts.r or 1, opts.g or 1, opts.b or 1, frac > 0 and 1 or 0)
        if shapeInfo.axis == "VERTICAL" then
            local fillH = frac > 0 and max(1, floor(h * frac + 0.5)) or 0
            frame.fill:SetTexCoord(0, 1, frac > 0 and (1 - frac) or 1, 1)
            frame.fill:SetSize(w, max(1, fillH))
            frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        else
            local fillW = frac > 0 and max(1, floor(w * frac + 0.5)) or 0
            frame.fill:SetTexCoord(0, frac, 0, 1)
            frame.fill:SetSize(max(1, fillW), h)
            frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        end
        if frac > 0 then frame.fill:Show() else frame.fill:Hide() end
        if frame.edge then
            local outline = floor((tonumber(opts.outline) or 0) + 0.5)
            if outline > 0 then
                frame.edge:SetTexture(shapeInfo.edge)
                frame.edge:SetVertexColor(PREVIEW_BORDER_COLOR[1], PREVIEW_BORDER_COLOR[2], PREVIEW_BORDER_COLOR[3], ShapeOutlineAlpha(outline))
                frame.edge:SetAllPoints(frame)
                frame.edge:Show()
            else
                frame.edge:Hide()
            end
        end
    else
        if frame.edge then frame.edge:Hide() end
        ApplyBarOutline(frame, opts.outline or 0)
        frame.bg:SetTexture(opts.bgTexture or WHITE8)
        frame.bg:SetVertexColor(opts.bgR or 0, opts.bgG or 0, opts.bgB or 0, opts.bgA or 0.35)
        frame.fill:SetTexture(opts.texture or WHITE8)
        frame.fill:SetVertexColor(opts.r or 1, opts.g or 1, opts.b or 1, 1)
        frame.fill:SetTexCoord(0, 1, 0, 1)
        frame.fill:SetSize(frac > 0 and max(1, floor(w * frac + 0.5)) or 1, h)
        frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        if frac > 0 then frame.fill:Show() else frame.fill:Hide() end
    end
end
local function UpdateMeterFill(frame, fraction)
    if not (frame and frame.fill) then return false end
    local w = max(1, floor(tonumber(frame._msufCPPreviewW) or (frame.GetWidth and frame:GetWidth()) or 1))
    local h = max(1, floor(tonumber(frame._msufCPPreviewH) or (frame.GetHeight and frame:GetHeight()) or 1))
    local frac = tonumber(fraction) or 0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local axis = frame._msufCPPreviewShapeAxis
    if axis == "VERTICAL" then
        local fillH = frac > 0 and max(1, floor(h * frac + 0.5)) or 0
        frame.fill:SetTexCoord(0, 1, frac > 0 and (1 - frac) or 1, 1)
        frame.fill:SetHeight(max(1, fillH))
    else
        local fillW = frac > 0 and max(1, floor(w * frac + 0.5)) or 0
        frame.fill:SetTexCoord(0, frame._msufCPPreviewHasShape and frac or 1, 0, 1)
        frame.fill:SetWidth(max(1, fillW))
    end
    if frac > 0 then frame.fill:Show() else frame.fill:Hide() end
    return true
end
local function ClassPowerWidth(bars, frameW, height, segCount, maxWidth)
    local shape = CP_SHAPES[NormalizeClassShape(bars and bars.classPowerShape)]
    local widthMode = bars and bars.classPowerWidthMode or "player"
    local cdmFrames = _G.MSUF_CP_CONST and _G.MSUF_CP_CONST.CDM_FRAMES
    local width
    if shape and widthMode == "auto_pips" then
        width = AutoFitPips(segCount, height, bars.classPowerGap)
    elseif cdmFrames and cdmFrames[widthMode] then
        local frameName = cdmFrames[widthMode]
        local source = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(frameName)) or _G[frameName]
        local scaleWidth = _G.MSUF_CDM_GetScaledWidth
        width = source and source.IsShown and source:IsShown() and type(scaleWidth) == "function" and scaleWidth(source, _G.MSUF_ClassPowerContainer)
        if not width then width = (tonumber(frameW) or 275) - 4 end
    elseif widthMode == "custom" then
        width = tonumber(bars.classPowerWidth)
    else
        width = (tonumber(frameW) or 275) - 4
    end
    width = tonumber(width) or 275
    if width < 20 then width = 20 elseif width > 800 then width = 800 end
    if maxWidth and width > maxWidth then width = maxWidth end
    return floor(width + 0.5)
end
local function SegmentCount(spec)
    local count = floor(tonumber(spec and spec.segments) or 5)
    if count < 1 then count = 1 elseif count > 10 then count = 10 end
    return count
end

local function IsAugCompositePreviewSpec(spec)
    return spec and spec.key == "evoker_augmentation_ebon"
        and type(spec.secondaryTimer) == "table"
end

--- Mirrors the invisible Player Power carrier used by the Augmentation
--- runtime. Normal Mana visibility is intentionally not part of this contract:
--- disabled Power still contributes its embed/detach geometry.
local function ResolveAugCompositeCarrier(preview, bars, player, spec)
    if not (IsAugCompositePreviewSpec(spec) and bars.showEbonMight ~= false) then
        return false
    end
    player = player or {}
    local essenceHeight = Clamp(bars.classPowerHeight, 4, 2, 30)
    local ebonHeight = Clamp(player.powerBarHeight or bars.powerBarHeight, 3, 1, 30)
    local totalHeight = essenceHeight + 2 + ebonHeight
    local detached = player.powerBarDetached == true
    local embedded = not detached and (
        player.embedPowerBarIntoHealth == true
        or (player.embedPowerBarIntoHealth == nil and bars.embedPowerBarIntoHealth ~= false)
    ) or false
    local width = tonumber(preview and preview.playerW) or 275
    if detached then
        local resolveWidth = CPPreview.ResolveDetachedPowerWidth
        if type(resolveWidth) == "function" then
            width = resolveWidth({
                -- Replacement geometry ignores ORB size and ClassPower width
                -- sync because this carrier is the owner ClassPower follows.
                shape = "BAR",
                syncClass = false,
                widthMode = bars.detachedPowerBarWidthMode,
                manualWidth = player.detachedPowerBarWidth,
                explicitWidth = player.detachedPowerBarWidth,
                frameWidth = width,
            })
        else
            width = Clamp(player.detachedPowerBarWidth, width, 20, 800)
        end
    end
    return true, detached, embedded, width, totalHeight,
        floor((tonumber(player.detachedPowerBarOffsetX) or 0) + 0.5),
        floor((tonumber(player.detachedPowerBarOffsetY) or -4) + 0.5),
        tostring(player.detachedPowerBarAnchorMode or "CENTER"):upper()
end

local function ClassPowerPreviewState(bars, spec)
    if bars and bars.showClassPower == false then return false, "settings" end
    if not spec or spec.enabled == false or spec.mode == "none" then return false, "resource" end
    return true
end

--- Compose the class-resource row/pips from profile values and the preview spec.
--- Runtime values are simulated here; the live controller remains authoritative.
local function RenderClassPower(preview, bars, player, spec)
    local frame = EnsureClassPower(preview)
    ApplyClassTextOwnerLevel(frame.textOwner, bars)
    local enabled, disabledReason = ClassPowerPreviewState(bars, spec)
    if not enabled then
        if Helpers.ApplyRoundedClassPowerSurface then
            Helpers.ApplyRoundedClassPowerSurface(frame, false, frame.segments, frame.bgs, 0, 0, CP_CLASS_ROUNDED_OPTS)
        end
        frame:Hide()
        HideBarOutline(frame)
        HideTableRegions(frame.segments)
        HideTableRegions(frame.bgs)
        HideTableRegions(frame.edges)
        HideTableRegions(frame.runeTexts)
        frame.text:Hide()
        preview.handleClass:Hide()
        preview.handleClassText:Hide()
        return nil, disabledReason
    end
    local h = Clamp(bars.classPowerHeight, 4, 2, 30)
    local count = SegmentCount(spec)
    local composite, detached, embedded, carrierW, totalHeight, carrierX, carrierY, anchorMode =
        ResolveAugCompositeCarrier(preview, bars, player, spec)
    local w = composite and carrierW
        or ClassPowerWidth(bars, preview.playerW, h, count, preview.canvasW - 72)
    local x = 2 + (tonumber(bars.classPowerOffsetX) or 0)
    local y = 4 + (tonumber(bars.classPowerOffsetY) or 0)
    frame:SetSize(w, h)
    frame:ClearAllPoints()
    if composite then
        if detached then
            if anchorMode == "LEGACY_TOPLEFT" then
                frame:SetPoint("TOPLEFT", preview.playerRef, "BOTTOMLEFT", carrierX, carrierY)
            else
                frame:SetPoint("TOP", preview.playerRef, "BOTTOM", carrierX, carrierY)
            end
        elseif embedded then
            frame:SetPoint("TOPLEFT", preview.playerRef, "BOTTOMLEFT", 0, totalHeight)
        else
            frame:SetPoint("TOPLEFT", preview.playerRef, "BOTTOMLEFT", 0, -1)
        end
    else
        frame:SetPoint("BOTTOMLEFT", preview.playerRef, "TOPLEFT", x, y)
    end
    frame:Show()
    local shape = NormalizeClassShape(bars.classPowerShape)
    local shapeInfo = CP_SHAPES[shape]
    local roundClassResources = shapeInfo == nil and RoundedClassResourcesPreviewEnabled(bars)
    local token = CPToken(spec)
    local r, g, b = CPBaseColor(spec, bars, 1, 1, 1)
    local bgr, bgg, bgb = CPBgColor(token)
    local bgA = Alpha(bars.classPowerBgAlpha, 0.30)
    local filledA = Alpha(bars.classPowerFilledAlpha, 1)
    local emptyA = Alpha(bars.classPowerEmptyAlpha, 0.30)
    local outline = PreviewOutline(preview, bars.classPowerOutline, shapeInfo and 0 or 1)
    local fgTex = ResolveTexture(bars.classPowerTexture)
    local bgTex = ResolveTexture(bars.classPowerBgTexture, fgTex)
    local gap = shapeInfo and Clamp(bars.classPowerGap, 0, 0, 8) or (Clamp(bars.classPowerTickWidth, 1, 0, 4) + Clamp(bars.classPowerGap, 0, 0, 8))
    if count > 1 then
        local maxGap = floor((w - count) / (count - 1))
        if maxGap < 0 then maxGap = 0 end
        if gap > maxGap then gap = maxGap end
    end
    local slot, startX, rowW
    if shapeInfo then
        slot = min(h, max(1, floor((w - ((count - 1) * gap)) / count)))
        rowW = (slot * count) + ((count - 1) * gap)
        local align = NormalizeAlign(bars.classPowerShapeAlign)
        if align == "LEFT" then startX = 0
        elseif align == "RIGHT" then startX = max(0, floor(w - rowW + 0.5))
        else startX = max(0, floor((w - rowW) * 0.5 + 0.5)) end
        HideBarOutline(frame)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        frame:SetBackdropColor(0, 0, 0, 0)
    else
        local barSpace = max(count, w - ((count - 1) * gap))
        slot = nil
        startX = 0
        rowW = barSpace
        if roundClassResources then HideBarOutline(frame) else ApplyBarOutline(frame, outline) end
    end
    local xPos, prevBoundary = 0, 0
    local elapsed = PreviewElapsed(preview)
    local animated = AnimationEnabled(preview)
    local animatedValue = animated and CPPreview.AnimatedValue and CPPreview.AnimatedValue(spec, elapsed) or nil
    local isFull = CPPreview.IsFull and CPPreview.IsFull(spec, animatedValue) or false
    local fullR, fullG, fullB = r, g, b
    if CPPreview.ResolveFullColor then
        local _, fr, fg, fb = CPPreview.ResolveFullColor(bars, token, r, g, b)
        fullR, fullG, fullB = fr, fg, fb
    end
    local runeOrder = spec.mode == "rune" and CPPreview.BuildRuneOrder and CPPreview.BuildRuneOrder({}, bars, spec, elapsed, animated) or nil
    local textColorR, textColorG, textColorB = CPTextColor(1, 1, 1)
    local textAlpha = CPTextAlpha()
    local textOffsetX = tonumber(bars.classPowerTextOffsetX) or 0
    local textOffsetY = tonumber(bars.classPowerTextOffsetY) or 0
    for i = 1, #frame.segments do
        local fill = frame.segments[i]
        local bg = frame.bgs[i]
        local edge = frame.edges[i]
        local runeText = frame.runeTexts[i]
        if i <= count then
            local segW, boundary
            if shapeInfo then
                segW = slot
                boundary = i * slot
            else
                boundary = floor((rowW * i) / count)
                segW = max(1, boundary - prevBoundary)
            end
            local rune = runeOrder and runeOrder[i]
            local frac = rune and ((rune.elapsed or 0) / (rune.total or 1)) or (CPPreview.FillForSegment and CPPreview.FillForSegment(spec, i, animatedValue) or (i <= floor(tonumber(animatedValue or spec.value) or 0) and 1 or 0))
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            local sx = startX + xPos
            if bars.classPowerFillReverse == true then sx = w - sx - segW end
            sx = max(0, sx)
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, 0)
            bg:SetSize(segW, h)
            bg:SetTexture(shapeInfo and shapeInfo.bg or bgTex)
            bg:SetVertexColor(bgr or 0, bgg or 0, bgb or 0, bgA)
            bg:Show()
            local sr, sg, sb = r, g, b
            if isFull then
                sr, sg, sb = fullR, fullG, fullB
            elseif CPPreview.IsCharged and CPPreview.IsCharged(spec, bars, i) then
                sr, sg, sb = CPColor("CHARGED", 0.60, 0.20, 0.80)
            elseif CPPreview.ResolveSlotColor then
                sr, sg, sb = CPPreview.ResolveSlotColor(bars, token, i, r, g, b)
            end
            if spec.threshold and frac > 0 and i > spec.threshold and CPPreview.ResolveColor then sr, sg, sb = CPColor(spec.thresholdToken, sr, sg, sb) end
            fill:ClearAllPoints()
            fill:SetTexture(shapeInfo and shapeInfo.fill or fgTex)
            fill:SetVertexColor(sr, sg, sb, rune and filledA or (frac > 0 and filledA or emptyA))
            local drawW = frac > 0 and max(1, floor(segW * frac + 0.5)) or 0
            if bars.classPowerFillReverse == true then
                fill:SetPoint("TOPRIGHT", frame, "TOPLEFT", sx + segW, 0)
                fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", sx + segW, 0)
                fill:SetTexCoord(shapeInfo and (1 - frac) or 0, 1, 0, 1)
            else
                fill:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, 0)
                fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", sx, 0)
                fill:SetTexCoord(0, shapeInfo and frac or 1, 0, 1)
            end
            fill:SetWidth(max(1, drawW))
            fill._msufCPPreviewSegW = segW
            fill._msufCPPreviewShape = shapeInfo ~= nil
            fill._msufCPPreviewReverse = bars.classPowerFillReverse == true
            if drawW > 0 then fill:Show() else fill:Hide() end
            if shapeInfo and outline > 0 then
                edge:ClearAllPoints()
                edge:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, 0)
                edge:SetSize(segW, h)
                edge:SetTexture(shapeInfo.edge)
                edge:SetVertexColor(PREVIEW_BORDER_COLOR[1], PREVIEW_BORDER_COLOR[2], PREVIEW_BORDER_COLOR[3], ShapeOutlineAlpha(outline))
                edge:Show()
            else
                edge:Hide()
            end
            if runeText then
                if rune and bars.runeShowTime ~= false and not rune.ready then
                    local txt = CPPreview.FormatSeconds and CPPreview.FormatSeconds(rune.remaining) or ""
                    ApplyFont(runeText, Clamp((tonumber(bars.classPowerFontSize) or 16) - 2, 12, 6, 48))
                    runeText:SetText(txt)
                    runeText:SetTextColor(textColorR, textColorG, textColorB, textAlpha)
                    runeText:ClearAllPoints()
                    runeText:SetPoint("CENTER", frame, "TOPLEFT",
                        sx + floor(segW * 0.5 + 0.5) + textOffsetX,
                        -floor(h * 0.5 + 0.5) + textOffsetY)
                    if txt ~= "" then runeText:Show() else runeText:Hide() end
                else
                    runeText:Hide()
                end
            end
            xPos = xPos + segW + gap
            prevBoundary = boundary
        else
            fill:Hide()
            bg:Hide()
            edge:Hide()
            if runeText then runeText:Hide() end
        end
    end
    if Helpers.ApplyRoundedClassPowerSurface then
        local roundedApplied = Helpers.ApplyRoundedClassPowerSurface(frame, roundClassResources,
            frame.segments, frame.bgs, count, outline, CP_CLASS_ROUNDED_OPTS)
        if not shapeInfo and not roundedApplied then ApplyBarOutline(frame, outline) end
    end
    if spec.mode == "ironfur" and bars.guardianIronfurShowHashLines ~= false then
        local fractions = { 0.82, 0.51, 0.24 }
        for i = 1, #frame.hashes do
            local hash = frame.hashes[i]
            local fraction = fractions[i]
            if fraction then
                hash:ClearAllPoints()
                hash:SetColorTexture(1, 1, 1, 0.9)
                hash:SetSize(2, h)
                hash:SetPoint("TOPLEFT", frame, "TOPLEFT", max(0, floor((w - 2) * fraction)), 0)
                hash:Show()
            else
                hash:Hide()
            end
        end
    else
        HideTableRegions(frame.hashes)
    end
    frame._msufCPPreviewAnim = {
        bars = bars,
        spec = spec,
        count = count,
        token = token,
        r = r,
        g = g,
        b = b,
        fullR = fullR,
        fullG = fullG,
        fullB = fullB,
        filledA = filledA,
        emptyA = emptyA,
        textColorR = textColorR,
        textColorG = textColorG,
        textColorB = textColorB,
        textAlpha = textAlpha,
    }
    if bars.classPowerShowText == true or spec.nativeDurationText == true then
        local textSize = Clamp(bars.classPowerFontSize, 16, 6, 48)
        ApplyFont(frame.text, textSize)
        frame.text:SetText(CPPreview.TextForValue and CPPreview.TextForValue(spec, animatedValue) or tostring(spec.previewText or "3"))
        frame.text:SetTextColor(textColorR, textColorG, textColorB, textAlpha)
        frame.text:ClearAllPoints()
        frame.text:SetPoint("CENTER", frame, "CENTER", tonumber(bars.classPowerTextOffsetX) or 0, tonumber(bars.classPowerTextOffsetY) or 0)
        frame.text:Show()
        PlaceTextHandle(preview.handleClassText, PreviewParent(preview), { frame.text })
    else
        frame.text:Hide()
        preview.handleClassText:Hide()
    end
    PlaceHandle(preview.handleClass, frame, 5)
    return frame
end

local function HideSecondaryClassTimer(preview)
    local frame = preview and preview.ebonTimer
    if not frame then return nil end
    frame._msufCPPreviewActive = false
    frame._msufCPPreviewTimerAnim = nil
    frame:Hide()
    HideBarOutline(frame)
    frame.left:Hide()
    frame.center:Hide()
    frame.right:Hide()
    return nil
end

--- Augmentation keeps the normal Essence pips and adds Ebon Might beneath
--- them. This child row has no independent drag owner, matching runtime where
--- the Player Power carrier owns the complete composite footprint.
local function RenderSecondaryClassTimer(preview, bars, player, spec, classFrame)
    local timerSpec = spec and spec.secondaryTimer
    if not (classFrame and type(timerSpec) == "table" and bars.showEbonMight ~= false) then
        return HideSecondaryClassTimer(preview)
    end

    local frame = EnsureMeter(preview, "ebonTimer", true)
    ApplyClassTextOwnerLevel(frame.textOwner, bars)
    local width = max(1, floor(tonumber(classFrame:GetWidth()) or 1))
    local height = tonumber(player and player.powerBarHeight) or tonumber(bars.powerBarHeight) or 3
    if height < 1 then height = 1 elseif height > 30 then height = 30 end
    local animatedValue = AnimationEnabled(preview) and CPPreview.AnimatedValue
        and CPPreview.AnimatedValue(timerSpec, PreviewElapsed(preview)) or nil
    local fraction = tonumber(animatedValue)
    if fraction == nil then fraction = tonumber(timerSpec.value) or 0.6 end
    if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end

    local r, g, b = CPBaseColor(timerSpec, bars, 0.40, 0.80, 0.60)
    local bgR, bgG, bgB = CPBgColor(CPToken(timerSpec))
    local filledAlpha = Alpha(bars.classPowerFilledAlpha, 1)
    local fgTex = ResolveTexture(bars.classPowerTexture)
    local bgTex = ResolveTexture(bars.classPowerBgTexture, fgTex)
    RenderMeter(frame, nil, {
        width = width,
        height = height,
        fraction = fraction,
        outline = 0,
        texture = fgTex,
        bgTexture = bgTex,
        r = r, g = g, b = b,
        bgR = bgR, bgG = bgG, bgB = bgB,
        bgA = Alpha(bars.classPowerBgAlpha, 0.30),
    })
    frame.fill:SetVertexColor(r, g, b, filledAlpha)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", classFrame, "BOTTOMLEFT", 0, -2)

    frame.left:Hide()
    frame.right:Hide()
    local showText = timerSpec.nativeDurationText == true or bars.classPowerShowText == true
    if showText then
        local textR, textG, textB = CPTextColor(1, 1, 1)
        ApplyFont(frame.center, Clamp(bars.classPowerFontSize, 16, 6, 48))
        frame.center:SetText(CPPreview.TextForValue
            and CPPreview.TextForValue(timerSpec, animatedValue)
            or tostring(timerSpec.previewText or "12.0"))
        frame.center:SetTextColor(textR, textG, textB, CPTextAlpha())
        frame.center:ClearAllPoints()
        frame.center:SetPoint("CENTER", frame, "CENTER",
            tonumber(bars.classPowerTextOffsetX) or 0,
            tonumber(bars.classPowerTextOffsetY) or 0)
        frame.center:Show()
    else
        frame.center:Hide()
    end

    frame._msufCPPreviewActive = true
    frame._msufCPPreviewTimerAnim = {
        spec = timerSpec,
        showText = showText,
    }
    frame:Show()
    return frame
end

local function DetachedPowerShown(player)
    return player.powerBarDetached == true and player.detachedPowerBarAnchorToClassPower == true
end
local function DetachedPowerWidth(preview, bars, player, classFrame)
    local shape = ResolvePowerShape(player.detachedPowerBarShape or "BAR", bars.classPowerShape)
    local resolveWidth = CPPreview.ResolveDetachedPowerWidth
    if type(resolveWidth) == "function" then
        return resolveWidth({
            shape = shape,
            orbSize = player.detachedPowerOrbSize,
            syncClass = player.detachedPowerBarSyncClassPower ~= false,
            classWidth = classFrame and classFrame.GetWidth and classFrame:GetWidth() or nil,
            classFallbackWidth = (tonumber(preview.playerW) or 275) - 4,
            widthMode = bars.detachedPowerBarWidthMode,
            manualWidth = player.detachedPowerBarWidth,
            frameWidth = preview.playerW,
        }), shape
    end
    if shape == "ORB" then return Clamp(player.detachedPowerOrbSize, 54, 20, 160), shape end
    if player.detachedPowerBarSyncClassPower ~= false and classFrame and classFrame.GetWidth then return max(20, floor(classFrame:GetWidth() + 0.5)), shape end
    return Clamp(player.detachedPowerBarWidth, preview.playerW, 20, 800), shape
end
local function ApplyMeterText(frame, size, x, y, leftText, centerText, rightText, layout)
    ApplyFont(frame.left, size)
    ApplyFont(frame.center, size)
    ApplyFont(frame.right, size)
    frame.left:SetText(leftText or "")
    frame.center:SetText(centerText or "")
    frame.right:SetText(rightText or "")
    frame.left:SetTextColor(1, 1, 1, 1)
    frame.center:SetTextColor(1, 1, 1, 1)
    frame.right:SetTextColor(1, 1, 1, 1)
    x, y = x or 0, y or 0
    local lx, ly = layout and layout.leftX or x, layout and layout.leftY or y
    local cx, cy = layout and layout.centerX or x, layout and layout.centerY or y
    local rx, ry = layout and layout.rightX or x, layout and layout.rightY or y
    local h = frame:GetHeight() or 8
    local textH = max(14, h + 8)
    frame.left:ClearAllPoints()
    frame.left:SetPoint("LEFT", frame, "LEFT", 4 + lx, ly)
    frame.left:SetSize(max(20, (frame:GetWidth() or 100) * 0.34), textH)
    frame.center:ClearAllPoints()
    frame.center:SetPoint("CENTER", frame, "CENTER", cx, cy)
    frame.center:SetSize(max(20, frame:GetWidth() or 100), textH)
    frame.right:ClearAllPoints()
    frame.right:SetPoint("RIGHT", frame, "RIGHT", -4 + rx, ry)
    frame.right:SetSize(max(20, (frame:GetWidth() or 100) * 0.34), textH)
    if (leftText or "") ~= "" then frame.left:Show() else frame.left:Hide() end
    if (centerText or "") ~= "" then frame.center:Show() else frame.center:Hide() end
    if (rightText or "") ~= "" then frame.right:Show() else frame.right:Hide() end
end

local function ResolvePlayerPowerTextLayout(player)
    player = player or {}
    local general = General()
    local baseX = tonumber(player.powerOffsetX or player.powerTextOffsetX or general.powerOffsetX or general.powerTextOffsetX) or -4
    local baseY = tonumber(player.powerOffsetY or player.powerTextOffsetY or general.powerOffsetY or general.powerTextOffsetY) or 4
    local baseline = tonumber((player.fontOverride == true and player.fontBaselineOffset) or general.fontBaselineOffset) or 0
    if baseline < -4 then baseline = -4 elseif baseline > 4 then baseline = 4 end
    local function Side(side, axis)
        local key, legacy = "powerText" .. side .. "Offset" .. axis, "power" .. side .. "Offset" .. axis
        return tonumber(player[key] or player[legacy] or general[key] or general[legacy]) or 0
    end
    baseY = baseY + baseline
    return {
        leftX = baseX + Side("Left", "X"), leftY = baseY + Side("Left", "Y"),
        centerX = baseX + Side("Center", "X"), centerY = baseY + Side("Center", "Y"),
        rightX = baseX + Side("Right", "X"), rightY = baseY + Side("Right", "Y"),
    }
end

local function PlayerPowerTextShown(player)
    player = player or {}
    if player.showPowerText ~= nil then return player.showPowerText ~= false end
    return player.showPower ~= false
end

--- Detached power preview follows the same anchoring relationship as runtime:
--- it can attach to ClassPower, but no live player power events are involved.
local function RenderDetachedPower(preview, bars, player, classFrame, spec)
    local frame = EnsureMeter(preview, "detachedPower")
    if (IsAugCompositePreviewSpec(spec) and bars.showEbonMight ~= false)
        or not DetachedPowerShown(player) then
        SetRoundedPowerPreview(frame, false)
        frame:Hide()
        HideBarOutline(frame)
        preview.handlePower:Hide()
        preview.handlePowerText:Hide()
        return nil
    end
    local width, shape = DetachedPowerWidth(preview, bars, player, classFrame)
    local shapeInfo = POWER_SHAPES[shape]
    local height = shape == "ORB" and width or Clamp(player.detachedPowerBarHeight, 6, 2, 80)
    local x, y = tonumber(player.detachedPowerBarOffsetX) or 0, tonumber(player.detachedPowerBarOffsetY) or -4
    local pr, pg, pb = PowerColor()
    -- The detached bar follows the normal power-texture precedence (per-unit
    -- Player value -> shared bars value -> global bar texture); there is no
    -- separate Class Resources texture anymore (see UF config).
    local playerFg = player.powerBarTexture
    if type(playerFg) ~= "string" or playerFg == "" then playerFg = bars.powerBarTexture end
    local fgTex = ResolveTexture(playerFg)
    -- An unset background follows the global bar background, not the
    -- foreground, so detaching alone never repaints the bar.
    local playerBg = player.powerBarBgTexture
    if type(playerBg) ~= "string" or playerBg == "" then playerBg = bars.powerBarBgTexture end
    local bgTex = ResolveTexture(playerBg,
        type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture() or fgTex)
    -- Class Resources owns the detached Player outline for every shape,
    -- including the rectangular bar.
    local outline = PreviewOutline(preview, bars.detachedPowerBarOutline, 1)
    local fraction = AnimatedMeterFraction(preview, 0.72, 0.46, 0.08, 0.96)
    frame:ClearAllPoints()
    if classFrame and classFrame.IsShown and classFrame:IsShown() then
        frame:SetPoint("TOP", classFrame, "BOTTOM", x, y)
    elseif tostring(player.detachedPowerBarAnchorMode or ""):upper() == "LEGACY_TOPLEFT" then
        frame:SetPoint("TOPLEFT", preview.playerRef, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("TOP", preview.playerRef, "BOTTOM", x, y)
    end
    RenderMeter(frame, shapeInfo, {
        width = width,
        height = height,
        fraction = fraction,
        r = pr,
        g = pg,
        b = pb,
        bgR = pr,
        bgG = pg,
        bgB = pb,
        bgA = 0.28,
        texture = fgTex,
        bgTexture = bgTex,
        outline = outline,
    })
    SetRoundedPowerPreview(frame, shapeInfo == nil, outline)
    frame:Show()
    if PlayerPowerTextShown(player) and player.detachedPowerBarTextOnBar == true then
        local leftMode = tostring(player.powerTextLeft or "NONE"):upper()
        local centerMode = tostring(player.powerTextCenter or "NONE"):upper()
        local rightMode = tostring(player.powerTextRight or player.powerTextMode or "CURPERCENT"):upper()
        local delimiter = player.powerTextSeparator or player.hpTextSeparator or ""
        local current = floor((fraction * 100) + 0.5)
        local hideLeft = HidePercentValue(player, "powerTextLeftHidePercentSymbol")
        local hideCenter = HidePercentValue(player, "powerTextCenterHidePercentSymbol")
        local hideRight = HidePercentValue(player, "powerTextRightHidePercentSymbol")
        ApplyMeterText(frame, Clamp(player.powerFontSize, 14, 6, 48), nil, nil,
            ModeText(leftMode, current, 100, delimiter, hideLeft),
            ModeText(centerMode, current, 100, delimiter, hideCenter),
            ModeText(rightMode, current, 100, delimiter, hideRight),
            ResolvePlayerPowerTextLayout(player))
        PlaceTextHandle(preview.handlePowerText, PreviewParent(preview), { frame.left, frame.center, frame.right })
    else
        frame.left:Hide()
        frame.center:Hide()
        frame.right:Hide()
        preview.handlePowerText:Hide()
    end
    PlaceHandle(preview.handlePower, frame, 5)
    return frame
end
local function HPWidth(preview, bars, classFrame, powerFrame)
    local mode = tostring(bars.playerHPBarWidthMode or "class"):lower()
    local width
    if mode == "custom" then
        width = tonumber(bars.playerHPBarWidth)
    elseif mode == "power" then
        width = powerFrame and powerFrame.GetWidth and powerFrame:GetWidth()
    elseif mode == "player" then
        width = preview.playerW
    else
        width = classFrame and classFrame.GetWidth and classFrame:GetWidth()
    end
    width = tonumber(width) or preview.playerW
    if width < 20 then width = 20 elseif width > 1200 then width = 1200 end
    return floor(width + 0.5)
end
local function PlaceHP(frame, preview, bars, classFrame, powerFrame, classBottomFrame)
    local mode = tostring(bars.playerHPBarAnchor or "CLASS_TOP"):upper()
    local anchor = (mode == "POWER_TOP" or mode == "POWER_BOTTOM") and powerFrame or classFrame
    if mode == "CLASS_BOTTOM" and classBottomFrame then anchor = classBottomFrame end
    if not (anchor and anchor.IsShown and anchor:IsShown()) then
        anchor = ((mode == "CLASS_BOTTOM" or mode == "POWER_BOTTOM") and classBottomFrame)
            or classFrame or preview.playerRef
    end
    local x = tonumber(bars.playerHPBarOffsetX) or 0
    local y = tonumber(bars.playerHPBarOffsetY) or 0
    local gap = Clamp(bars.playerHPBarGap, 2, 0, 60)
    frame:ClearAllPoints()
    if mode == "CLASS_BOTTOM" or mode == "POWER_BOTTOM" then
        frame:SetPoint("TOP", anchor, "BOTTOM", x, y - gap)
    else
        frame:SetPoint("BOTTOM", anchor, "TOP", x, y + gap)
    end
end
local function HPTextConfig(bars, player)
    local left, center, right, delimiter, reverse, hideLeft, hideCenter, hideRight
    if bars.playerHPBarUsePlayerText ~= false then
        left = tostring(player.textLeft or "NONE"):upper()
        center = tostring(player.textCenter or "NONE"):upper()
        right = tostring(player.textRight or player.hpTextMode or "CURPERCENT"):upper()
        delimiter = player.hpTextSeparator or ""
        reverse = player.hpTextReverse == true
        hideLeft = HidePercentValue(player, "hpTextLeftHidePercentSymbol")
        hideCenter = HidePercentValue(player, "hpTextCenterHidePercentSymbol")
        hideRight = HidePercentValue(player, "hpTextRightHidePercentSymbol")
    else
        left = tostring(bars.playerHPBarTextLeft or "NONE"):upper()
        center = tostring(bars.playerHPBarTextCenter or "NONE"):upper()
        right = tostring(bars.playerHPBarTextRight or "CURPERCENT"):upper()
        delimiter = bars.playerHPBarTextSeparator or ""
        reverse = bars.playerHPBarTextReverse == true
        hideLeft = HidePercentValue(bars, "playerHPBarTextLeftHidePercentSymbol")
        hideCenter = HidePercentValue(bars, "playerHPBarTextCenterHidePercentSymbol")
        hideRight = HidePercentValue(bars, "playerHPBarTextRightHidePercentSymbol")
    end
    if reverse then
        left, right = HP_TEXT_REVERSE[right] or right, HP_TEXT_REVERSE[left] or left
        center = HP_TEXT_REVERSE[center] or center
        hideLeft, hideRight = hideRight, hideLeft
    end
    return left, center, right, delimiter, hideLeft, hideCenter, hideRight
end

--- Optional ClassPower-owned player HP preview. It mirrors runtime layout/text
--- rules without reading real UnitHealth.
local function RenderPlayerHP(preview, bars, player, classFrame, powerFrame, spec, classBottomFrame)
    local frame = EnsureMeter(preview, "playerHP")
    if bars.playerHPBarEnabled ~= true then
        frame:Hide()
        HideBarOutline(frame)
        preview.handleHP:Hide()
        preview.handleHPText:Hide()
        return nil
    end
    local shape = ResolveHPShape(bars, player)
    local shapeInfo = POWER_SHAPES[shape]
    local followPower = tostring(bars.playerHPBarShape or "BAR"):upper() == "FOLLOW_POWER"
    local orbSize = followPower and Clamp(player.detachedPowerOrbSize, 54, 20, 160) or Clamp(bars.playerHPBarOrbSize, 54, 20, 160)
    local width = shape == "ORB" and orbSize or HPWidth(preview, bars, classFrame, powerFrame)
    local height = shape == "ORB" and width or Clamp(bars.playerHPBarHeight, 6, 2, 80)
    local hr, hg, hb = HPColor(bars, spec)
    local fgTex = ResolveTexture(bars.playerHPBarTexture)
    local bgTex = ResolveTexture(bars.playerHPBarBgTexture, fgTex)
    local fraction = AnimatedMeterFraction(preview, 0.74, 0.34, 0.18, 1.00)
    PlaceHP(frame, preview, bars, classFrame, powerFrame, classBottomFrame)
    RenderMeter(frame, shapeInfo, {
        width = width,
        height = height,
        fraction = fraction,
        r = hr,
        g = hg,
        b = hb,
        bgR = 0,
        bgG = 0,
        bgB = 0,
        bgA = Alpha(bars.playerHPBarBgAlpha, 0.35),
        texture = fgTex,
        bgTexture = bgTex,
        outline = PreviewOutline(preview, bars.playerHPBarOutline, 1),
    })
    frame:Show()
    if bars.playerHPBarTextEnabled ~= false then
        local leftMode, centerMode, rightMode, delimiter, hideLeft, hideCenter, hideRight = HPTextConfig(bars, player)
        local maxValue = 1000000
        local current = floor((maxValue * fraction) + 0.5)
        ApplyMeterText(frame, Clamp(bars.playerHPBarUsePlayerText ~= false and player.hpFontSize or bars.playerHPBarTextSize, 14, 6, 48), tonumber(bars.playerHPBarTextOffsetX) or 0, tonumber(bars.playerHPBarTextOffsetY) or 0,
            ModeText(leftMode, current, maxValue, delimiter, hideLeft),
            ModeText(centerMode, current, maxValue, delimiter, hideCenter),
            ModeText(rightMode, current, maxValue, delimiter, hideRight))
        PlaceTextHandle(preview.handleHPText, PreviewParent(preview), { frame.left, frame.center, frame.right })
    else
        frame.left:Hide()
        frame.center:Hide()
        frame.right:Hide()
        preview.handleHPText:Hide()
    end
    PlaceHandle(preview.handleHP, frame, 5)
    return frame
end
local function UpdateClassPowerAnimation(preview, frame)
    local state = frame and frame._msufCPPreviewAnim
    local bars = state and state.bars
    local spec = state and state.spec
    if not (preview and frame and bars and spec) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    local elapsed = PreviewElapsed(preview)
    local animatedValue = CPPreview.AnimatedValue and CPPreview.AnimatedValue(spec, elapsed) or nil
    local isFull = CPPreview.IsFull and CPPreview.IsFull(spec, animatedValue) or false
    local runeOrder = spec.mode == "rune" and CPPreview.BuildRuneOrder and CPPreview.BuildRuneOrder({}, bars, spec, elapsed, true) or nil
    for i = 1, state.count or 0 do
        local fill = frame.segments and frame.segments[i]
        if fill then
            local rune = runeOrder and runeOrder[i]
            local frac = rune and ((rune.elapsed or 0) / (rune.total or 1))
                or (CPPreview.FillForSegment and CPPreview.FillForSegment(spec, i, animatedValue)
                    or (i <= floor(tonumber(animatedValue or spec.value) or 0) and 1 or 0))
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            local sr, sg, sb = state.r, state.g, state.b
            if isFull then
                sr, sg, sb = state.fullR, state.fullG, state.fullB
            elseif CPPreview.IsCharged and CPPreview.IsCharged(spec, bars, i) then
                sr, sg, sb = CPColor("CHARGED", 0.60, 0.20, 0.80)
            elseif CPPreview.ResolveSlotColor then
                sr, sg, sb = CPPreview.ResolveSlotColor(bars, state.token, i, sr, sg, sb)
            end
            if spec.threshold and frac > 0 and i > spec.threshold and CPPreview.ResolveColor then
                sr, sg, sb = CPColor(spec.thresholdToken, sr, sg, sb)
            end
            fill:SetVertexColor(sr, sg, sb, rune and state.filledA or (frac > 0 and state.filledA or state.emptyA))
            local segW = max(1, floor(tonumber(fill._msufCPPreviewSegW) or 1))
            local drawW = frac > 0 and max(1, floor(segW * frac + 0.5)) or 0
            if fill._msufCPPreviewReverse then
                fill:SetTexCoord(fill._msufCPPreviewShape and (1 - frac) or 0, 1, 0, 1)
            else
                fill:SetTexCoord(0, fill._msufCPPreviewShape and frac or 1, 0, 1)
            end
            fill:SetWidth(max(1, drawW))
            if drawW > 0 then fill:Show() else fill:Hide() end
            local runeText = frame.runeTexts and frame.runeTexts[i]
            if runeText then
                if rune and bars.runeShowTime ~= false and not rune.ready then
                    local txt = CPPreview.FormatSeconds and CPPreview.FormatSeconds(rune.remaining) or ""
                    runeText:SetText(txt)
                    if txt ~= "" then runeText:Show() else runeText:Hide() end
                else
                    runeText:Hide()
                end
            end
        end
    end
    if frame.text and (bars.classPowerShowText == true or spec.nativeDurationText == true) then
        frame.text:SetText(CPPreview.TextForValue and CPPreview.TextForValue(spec, animatedValue) or tostring(spec.previewText or "3"))
        if LayerOn(preview, "classText") then frame.text:Show() end
    end
    return true
end
local function UpdateSecondaryClassTimerAnimation(preview, frame)
    local state = frame and frame._msufCPPreviewTimerAnim
    local spec = state and state.spec
    if not (preview and frame and spec) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    local value = CPPreview.AnimatedValue and CPPreview.AnimatedValue(spec, PreviewElapsed(preview))
        or tonumber(spec.value) or 0.6
    UpdateMeterFill(frame, value)
    if state.showText and frame.center then
        frame.center:SetText(CPPreview.TextForValue
            and CPPreview.TextForValue(spec, value)
            or tostring(spec.previewText or "12.0"))
        if LayerOn(preview, "classText") then frame.center:Show() end
    end
    return true
end
local function UpdateDetachedPowerAnimation(preview, frame, bars, player)
    if not (preview and frame and bars and player) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    local fraction = AnimatedMeterFraction(preview, 0.72, 0.46, 0.08, 0.96)
    UpdateMeterFill(frame, fraction)
    if PlayerPowerTextShown(player) and player.detachedPowerBarTextOnBar == true then
        local leftMode = tostring(player.powerTextLeft or "NONE"):upper()
        local centerMode = tostring(player.powerTextCenter or "NONE"):upper()
        local rightMode = tostring(player.powerTextRight or player.powerTextMode or "CURPERCENT"):upper()
        local delimiter = player.powerTextSeparator or player.hpTextSeparator or ""
        local current = floor((fraction * 100) + 0.5)
        if frame.left then frame.left:SetText(ModeText(leftMode, current, 100, delimiter, HidePercentValue(player, "powerTextLeftHidePercentSymbol"))) end
        if frame.center then frame.center:SetText(ModeText(centerMode, current, 100, delimiter, HidePercentValue(player, "powerTextCenterHidePercentSymbol"))) end
        if frame.right then frame.right:SetText(ModeText(rightMode, current, 100, delimiter, HidePercentValue(player, "powerTextRightHidePercentSymbol"))) end
    end
    return true
end
local function UpdatePlayerHPAnimation(preview, frame, bars, player)
    if not (preview and frame and bars and player) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    local fraction = AnimatedMeterFraction(preview, 0.74, 0.34, 0.18, 1.00)
    UpdateMeterFill(frame, fraction)
    if bars.playerHPBarTextEnabled ~= false then
        local leftMode, centerMode, rightMode, delimiter, hideLeft, hideCenter, hideRight = HPTextConfig(bars, player)
        local maxValue = 1000000
        local current = floor((maxValue * fraction) + 0.5)
        if frame.left then frame.left:SetText(ModeText(leftMode, current, maxValue, delimiter, hideLeft)) end
        if frame.center then frame.center:SetText(ModeText(centerMode, current, maxValue, delimiter, hideCenter)) end
        if frame.right then frame.right:SetText(ModeText(rightMode, current, maxValue, delimiter, hideRight)) end
    end
    return true
end
local function RefreshClassPowerAnimation(preview)
    local state = preview and preview._msufCPPreviewAnim
    if not state then return false end
    if state.classFrame and not UpdateClassPowerAnimation(preview, state.classFrame) then return false end
    if state.ebonFrame and not UpdateSecondaryClassTimerAnimation(preview, state.ebonFrame) then return false end
    if state.powerFrame and not UpdateDetachedPowerAnimation(preview, state.powerFrame, state.bars, state.player) then return false end
    if state.hpFrame and not UpdatePlayerHPAnimation(preview, state.hpFrame, state.bars, state.player) then return false end
    return true
end
local function PaintPlayerReference(preview, spec, bars, playerDB)
    local player = preview.playerRef
    local parent = PreviewParent(preview)
    local pr, pg, pb = PowerColor()
    local hr, hg, hb = ClassColor(0.20, 0.78, 0.26, spec)
    local composite, _, embedded, _, totalHeight = ResolveAugCompositeCarrier(
        preview, bars, playerDB, spec)
    player:SetSize(preview.playerW, preview.playerH)
    player:ClearAllPoints()
    player:SetPoint("CENTER", parent, "CENTER", 0, -34)
    player.health:ClearAllPoints()
    player.health:SetPoint("TOPLEFT", player, "TOPLEFT", 0, 0)
    player.health:SetPoint("BOTTOMRIGHT", player, "BOTTOMRIGHT", 0,
        composite and embedded and totalHeight or (composite and 0 or 6))
    player.health:SetColorTexture(hr, hg, hb, 0.16)
    player.power:SetColorTexture(pr, pg, pb, 0.16)
    player.power:SetShown(not composite)
    player.outline:SetBackdropBorderColor(0.55, 0.62, 0.78, 0.34)
end
local function CreatePlayerReference(preview)
    local player = CreateFrame("Frame", nil, PreviewParent(preview))
    player.health = player:CreateTexture(nil, "BACKGROUND")
    player.health:SetPoint("TOPLEFT", player, "TOPLEFT", 0, 0)
    player.health:SetPoint("BOTTOMRIGHT", player, "BOTTOMRIGHT", 0, 6)
    player.power = player:CreateTexture(nil, "BACKGROUND")
    player.power:SetPoint("TOPLEFT", player.health, "BOTTOMLEFT", 0, 0)
    player.power:SetPoint("BOTTOMRIGHT", player, "BOTTOMRIGHT", 0, 0)
    player.outline = CreateFrame("Frame", nil, player, "BackdropTemplate")
    player.outline:SetAllPoints()
    player.outline:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    player.outline:SetBackdropColor(0, 0, 0, 0)
    player.name = MakeText(player, "OVERLAY", "LEFT")
    ApplyFont(player.name, 11)
    player.name:SetPoint("LEFT", player, "LEFT", 6, 0)
    player.name:SetText(TR("Player frame reference"))
    player.name:SetTextColor(0.60, 0.66, 0.78, 0.62)
    preview.playerRef = player
end
local function EnsureBound(preview, key, label, color)
    preview.bounds = preview.bounds or {}
    local frame = preview.bounds[key]
    if frame then return frame end
    frame = CreateFrame("Frame", nil, PreviewParent(preview), "BackdropTemplate")
    frame:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(color[1], color[2], color[3], 0.90)
    frame:EnableMouse(false)
    frame:SetFrameLevel(((PreviewParent(preview) and PreviewParent(preview).GetFrameLevel and PreviewParent(preview):GetFrameLevel()) or 0) + 70)
    frame.label = MakeText(frame, "OVERLAY", "LEFT")
    ApplyFont(frame.label, 9)
    frame.label:SetText(TR(label))
    frame.label:SetTextColor(color[1], color[2], color[3], 0.95)
    frame.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 1)
    frame._msufPlaced = false
    frame._layerKey = key
    frame:Hide()
    preview.bounds[key] = frame
    return frame
end
local function PlaceBound(preview, key, region, label, color, pad, layerKey)
    local bound = EnsureBound(preview, key, label, color)
    bound._layerKey = layerKey or key
    if not (region and region.IsShown and region:IsShown()) then
        bound._msufPlaced = false
        bound:Hide()
        return
    end
    pad = tonumber(pad) or 1
    bound:ClearAllPoints()
    bound:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
    bound:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    bound._msufPlaced = true
    bound:Show()
end
local function RefreshBounds(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    PlaceBound(preview, "reference", preview.playerRef, "Reference", { 0.60, 0.66, 0.78 }, 1)
    PlaceBound(preview, "class", classFrame, "Class", { 0.30, 0.78, 0.55 }, 1)
    PlaceBound(preview, "ebon", ebonFrame, "Ebon Might", { 0.40, 0.80, 0.60 }, 1, "class")
    PlaceBound(preview, "power", powerFrame, "Power", { 0.95, 0.72, 0.18 }, 1)
    PlaceBound(preview, "hp", hpFrame, "HP", { 0.25, 0.90, 0.42 }, 1)
end
local function AddPreviewRegionBounds(preview, region, bounds)
    if not (preview and preview.stage and region and region.IsShown and region:IsShown()) then return end
    local stageX, stageY = preview.stage:GetCenter()
    local regionX, regionY = region:GetCenter()
    if not (stageX and stageY and regionX and regionY) then return end
    local halfW = max(0, (tonumber(region:GetWidth()) or 0) * 0.5)
    local halfH = max(0, (tonumber(region:GetHeight()) or 0) * 0.5)
    -- GetCenter values for regions in the same scaled hierarchy are already in
    -- their shared local coordinate space (see Blizzard_SharedXML/RegionUtil).
    local centerX = regionX - stageX
    local centerY = regionY - stageY
    bounds.minX = min(bounds.minX, centerX - halfW)
    bounds.maxX = max(bounds.maxX, centerX + halfW)
    bounds.minY = min(bounds.minY, centerY - halfH)
    bounds.maxY = max(bounds.maxY, centerY + halfH)
    bounds.found = true
end

local function ResolvePreviewFit(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    local bounds = { minX = math.huge, maxX = -math.huge, minY = math.huge, maxY = -math.huge }
    local visibility = preview and preview.layerVisibility
    local function Wanted(key) return not (visibility and visibility[key] == false) end
    -- layerAvailable still describes the preceding refresh at this point.  Fit
    -- the frames produced by this refresh and apply availability afterwards.
    if Wanted("reference") then AddPreviewRegionBounds(preview, preview.playerRef, bounds) end
    if Wanted("class") then AddPreviewRegionBounds(preview, classFrame, bounds) end
    if Wanted("class") then AddPreviewRegionBounds(preview, ebonFrame, bounds) end
    if Wanted("power") then AddPreviewRegionBounds(preview, powerFrame, bounds) end
    if Wanted("hp") then AddPreviewRegionBounds(preview, hpFrame, bounds) end
    if not bounds.found then return 1, 0, 0 end

    local pad = 20
    local contentW = max(1, (bounds.maxX - bounds.minX) + pad * 2)
    local contentH = max(1, (bounds.maxY - bounds.minY) + pad * 2)
    local canvasW = max(1, tonumber(preview.canvasW) or tonumber(preview.canvas:GetWidth()) or 1)
    local canvasH = max(1, tonumber(preview.canvasH) or tonumber(preview.canvas:GetHeight()) or 1)
    local autoScale = min(1, (canvasW - 24) / contentW, (canvasH - 24) / contentH)
    if autoScale < 0.05 then autoScale = 0.05 end
    local centerX = (bounds.minX + bounds.maxX) * 0.5
    local centerY = (bounds.minY + bounds.maxY) * 0.5
    return autoScale, -centerX, -centerY
end

local function ApplyPreviewZoom(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    if not (preview and preview.stage) then return end
    local autoScale, centerX, centerY = ResolvePreviewFit(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    if ZoomPan.ResolveDefaultLock then ZoomPan.ResolveDefaultLock(preview, autoScale) end
    local manualScale = tonumber(preview._manualZoom)
    local frozenScale = tonumber(preview._dragFrozenScale)
    local scale = manualScale or frozenScale or autoScale
    if (manualScale or frozenScale) and ZoomPan.Clamp then scale = ZoomPan.Clamp(scale) end
    preview._mockAutoScale = autoScale
    preview._mockScale = scale
    preview._mockEffectiveScale = scale
    if preview._dragFrozenBaseOffsetX ~= nil then
        preview._mockBaseOffsetX = preview._dragFrozenBaseOffsetX
        preview._mockBaseOffsetY = preview._dragFrozenBaseOffsetY
    else
        preview._mockBaseOffsetX = centerX * scale
        preview._mockBaseOffsetY = centerY * scale
    end
    if preview.stage.SetScale then preview.stage:SetScale(scale) end
    if ZoomPan.UpdateControls then ZoomPan.UpdateControls(preview) end
    if ZoomPan.ApplyPan then
        ZoomPan.ApplyPan(preview)
    else
        preview.stage:ClearAllPoints()
        preview.stage:SetPoint("CENTER", preview.canvas, "CENTER",
            (tonumber(preview._mockBaseOffsetX) or 0) + (tonumber(preview._zoomPanX) or 0),
            (tonumber(preview._mockBaseOffsetY) or 0) + (tonumber(preview._zoomPanY) or 0))
    end
end
local function ApplyPreviewBorder(preview)
    if not (preview and preview.canvas and preview.canvas.SetBackdropBorderColor) then return end
    local c = preview._canvasBorderColor or { 0.10, 0.13, 0.18, 0.65 }
    preview.canvas:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
end
local function HideMeterText(frame)
    if not frame then return end
    SetShownSafe(frame.left, false)
    SetShownSafe(frame.center, false)
    SetShownSafe(frame.right, false)
end
local function ApplyLayerVisibility(preview)
    if not preview then return end
    local classOn = LayerOn(preview, "class")
    local classTextOn = classOn and LayerOn(preview, "classText")
    local powerOn = LayerOn(preview, "power")
    local powerTextOn = powerOn and LayerOn(preview, "powerText")
    local hpOn = LayerOn(preview, "hp")
    local hpTextOn = hpOn and LayerOn(preview, "hpText")
    local boundsOn = LayerOn(preview, "bounds")
    local guidesOn = GuidesOn(preview)
    SetShownSafe(preview.playerRef, LayerOn(preview, "reference"))
    SetShownSafe(preview.classPower, classOn)
    if not classOn then HideBarOutline(preview.classPower) end
    local classTextActive = preview.classPower and preview.classPower._msufCPPreviewAnim
        and (preview.classPower._msufCPPreviewAnim.bars.classPowerShowText == true
            or preview.classPower._msufCPPreviewAnim.spec.nativeDurationText == true)
    if preview.classPower and preview.classPower.text then
        SetShownSafe(preview.classPower.text, classTextOn and classTextActive)
    end
    local ebonActive = preview.ebonTimer and preview.ebonTimer._msufCPPreviewActive == true
    SetShownSafe(preview.ebonTimer, classOn and ebonActive)
    if preview.ebonTimer then
        SetShownSafe(preview.ebonTimer.left, false)
        SetShownSafe(preview.ebonTimer.center, classTextOn and ebonActive
            and preview.ebonTimer._msufCPPreviewTimerAnim
            and preview.ebonTimer._msufCPPreviewTimerAnim.showText == true)
        SetShownSafe(preview.ebonTimer.right, false)
    end
    SetShownSafe(preview.detachedPower, powerOn)
    if not powerOn then HideBarOutline(preview.detachedPower) end
    if not powerTextOn then HideMeterText(preview.detachedPower) end
    SetShownSafe(preview.playerHP, hpOn)
    if not hpOn then HideBarOutline(preview.playerHP) end
    if not hpTextOn then HideMeterText(preview.playerHP) end
    if preview.bounds then
        for _, bound in pairs(preview.bounds) do
            SetShownSafe(bound, boundsOn and bound._msufPlaced == true and LayerOn(preview, bound._layerKey))
        end
    end
    for i = 1, #(preview.handles or {}) do
        local handle = preview.handles[i]
        SetShownSafe(handle, guidesOn and handle._msufPlaced == true and LayerOn(preview, handle._layerKey or handle._key))
    end
    if preview.selectedHandle and not CanNudgeHandle(preview.selectedHandle) then
        preview.selectedHandle = nil
        SetArrowBindings(preview, false)
        FocusPreviewKeyboardTarget(preview, nil, false)
    end
    ApplyPreviewBorder(preview)
end
local function LayerAvailable(preview, key)
    local available = preview and preview.layerAvailable
    return not (available and available[key] == false)
end
local CP_LAYER_BUTTON_OPTS = {
    Tr = TR,
    IsAvailable = LayerAvailable,
    IsOn = LayerOn,
    disabledLine = "This element is disabled in the current settings.",
    OnClick = function(self, preview)
        if not LayerAvailable(preview, self.key) then return end
        preview.layerVisibility[self.key] = preview.layerVisibility[self.key] == false
        if self.key == "guides" then SetPreviewGuidesEnabled(preview.layerVisibility[self.key] ~= false) end
        if preview and preview.Refresh then
            RequestClassPowerPreviewRefresh(preview, "CLASSPOWER_PREVIEW_LAYER")
        else
            ApplyLayerVisibility(preview)
            RefreshHandleVisuals(preview)
            RefreshLayerButtons(preview)
        end
    end,
}
local function CreateLayerSidebar(box, sideW)
    local sidebar = T.Panel(box, nil, { 0.025, 0.028, 0.04, 0.82 }, T.colors.borderSoft)
    if Helpers.ApplyPreviewChrome then Helpers.ApplyPreviewChrome(sidebar, "sidebar", T) end
    sidebar:SetPoint("TOPLEFT", box.canvas, "TOPRIGHT", 8, 0)
    sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    if sidebar.SetClipsChildren then sidebar:SetClipsChildren(true) end
    box.sidebar = sidebar
    local chrome = Helpers.PreviewChromePalette and Helpers.PreviewChromePalette(T) or {}
    local hdr = T.Font(sidebar, "GameFontDisableSmall", TR("LAYERS"), chrome.layerHeader or T.colors.muted)
    hdr:SetPoint("TOP", sidebar, "TOP", 0, -5)
    box.layerVisibility = {}
    box.layerButtons = {}
    for i = 1, #CP_PREVIEW_LAYERS do
        local def = CP_PREVIEW_LAYERS[i]
        box.layerVisibility[def.key] = (def.key == "guides") and PreviewGuidesEnabled() or true
        local btn = Helpers.CreateLayerButton(sidebar, box, def, i, sideW, CP_LAYER_BUTTON_OPTS)
        if def.key == "guides" then
            RegisterPreviewControl(box._catalogCtx, btn, "layer.guides",
                tostring(def.label or def.key) .. " preview layer", "toggle", "setting", {
                    settingKey = "general.classPowerPreviewGuidesEnabled",
                    help = def.tooltip,
                })
        else
            RegisterPreviewControl(box._catalogCtx, btn, "layer." .. tostring(def.key),
                tostring(def.label or def.key) .. " preview layer", "button", "ephemeral", {
                    help = def.tooltip,
                })
        end
        box.layerButtons[#box.layerButtons + 1] = btn
    end
end
local function RefreshAnimateButton(preview)
    local btn = preview and preview.animateButton
    if not btn then return end
    local active = AnimationEnabled(preview)
    if btn.fs then
        btn.fs:SetText(active and TR("Stop") or TR("Animate"))
        btn.fs:SetTextColor(active and 0.06 or 0.78, active and 0.95 or 0.84, active and 1.00 or 0.96, 1)
    end
    if btn.MSUF2RefreshPreviewPill then btn:MSUF2RefreshPreviewPill(active) end
    if btn.SetBackdropColor and not btn._msuf2PreviewPillFill then
        if active then
            btn:SetBackdropColor(0.020, 0.125, 0.155, 0.96)
            btn:SetBackdropBorderColor(0.10, 0.82, 0.95, 1)
        else
            btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
            btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
        end
    end
end
local function StopAnimationDriver(preview)
    local driver = preview and preview.animationDriver
    if not driver then return end
    driver:SetScript("OnUpdate", nil)
    if driver.SetOnUpdateMode then driver:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
    driver:Hide()
end
local function AnimationOnUpdate(driver, elapsed)
    local preview = driver and driver._preview
    if not (preview and preview._animationEnabled == true and preview.IsShown and preview:IsShown()) then
        StopAnimationDriver(preview)
        return
    end
    if PreviewAnimationInCombat() then
        preview._animationEnabled = false
        General().classPowerPreviewAnimate = false
        StopAnimationDriver(preview)
        RefreshAnimateButton(preview)
        return
    end
    elapsed = tonumber(elapsed) or 0
    preview._animationElapsed = (tonumber(preview._animationElapsed) or 0) + elapsed
    preview._animationAccum = (tonumber(preview._animationAccum) or 0) + elapsed
    if preview._animationAccum < CP_PREVIEW_ANIMATION_INTERVAL then return end
    preview._animationAccum = 0
    if preview.Refresh then
        local light = preview.RefreshAnimation and preview:RefreshAnimation("CLASSPOWER_PREVIEW_ANIMATE")
        if not light then preview:Refresh("CLASSPOWER_PREVIEW_ANIMATE") end
    end
end
local function StartAnimationDriver(preview)
    if not (preview and preview._animationEnabled == true) then return end
    if PreviewAnimationInCombat() then return end
    if not preview.animationDriver then
        preview.animationDriver = CreateFrame("Frame", nil, preview.canvas or preview)
        preview.animationDriver._preview = preview
    end
    preview.animationDriver._preview = preview
    if preview.animationDriver.SetOnUpdateMode then preview.animationDriver:SetOnUpdateMode(ONUPDATE_MODE_RUN_WHEN_VISIBLE) end
    preview.animationDriver:SetScript("OnUpdate", AnimationOnUpdate)
    preview.animationDriver:Show()
end
local function SetAnimationEnabled(preview, enabled)
    if not preview then return end
    enabled = enabled == true
    if enabled and PreviewAnimationInCombat() then
        preview._animationEnabled = false
        General().classPowerPreviewAnimate = false
        StopAnimationDriver(preview)
        RefreshAnimateButton(preview)
        return false
    end
    if enabled and preview._animationEnabled ~= true then
        preview._animationElapsed = 0
        preview._animationAccum = 0
    end
    preview._animationEnabled = enabled
    General().classPowerPreviewAnimate = enabled
    RefreshAnimateButton(preview)
    if enabled then
        StartAnimationDriver(preview)
    else
        StopAnimationDriver(preview)
    end
    if preview.Refresh then preview:Refresh("CLASSPOWER_PREVIEW_ANIMATE_TOGGLE") end
    return AnimationEnabled(preview) == enabled
end
local function CreateAnimateButton(preview)
    local btn = CreateFrame("Button", nil, preview.canvas, "BackdropTemplate")
    btn:SetSize(72, 22)
    btn:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    if preview.zoomBar then
        btn:SetPoint("RIGHT", preview.zoomBar, "LEFT", -6, 0)
    else
        btn:SetPoint("TOPRIGHT", preview.canvas, "TOPRIGHT", -174, -6)
    end
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("CENTER")
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or { 1, 1, 1, 1 }, 0) end
    if Helpers.StylePreviewPillButton then Helpers.StylePreviewPillButton(btn, T, { fontField = "fs" }) end
    btn:SetScript("OnClick", function(self)
        SetAnimationEnabled(self._preview, not AnimationEnabled(self._preview))
    end)
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return AnimationEnabled(preview) end,
        set = function(enabled) return SetAnimationEnabled(preview, enabled == true) end,
    }
    M.AddTooltip(btn, "Animate Preview", "Animates Class Resource, Player Power, and HP fill values in this preview only.", { hook = true })
    btn._preview = preview
    preview.animateButton = btn
    RegisterPreviewControl(preview._catalogCtx, btn, "animation.toggle", "Animate Preview", "button", "ephemeral", {
        help = "Starts or stops preview-only Class Resource, Player Power, and HP fill animation.",
    })
    RefreshAnimateButton(preview)
    return btn
end
local function DragUpdate(frame)
    local handle = frame and frame._handle
    if not (handle and handle._dragging) then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        StopHandleDrag(handle, "LeftButton", false, true)
        return
    end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return end
    local scale = handle.GetEffectiveScale and handle:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    local nextX = Round((handle._startX or 0) + ((cx - (handle._cursorX or cx)) / scale))
    local nextY = Round((handle._startY or 0) + ((cy - (handle._cursorY or cy)) / scale))
    if nextX ~= handle._startX or nextY ~= handle._startY then handle._didDragMove = true end
    if handle._lastX == nextX and handle._lastY == nextY then return end
    handle._lastX, handle._lastY = nextX, nextY
    WriteHandle(handle, nextX, nextY, true)
end

local function EnsureClassPowerLayersButton(box)
    if box._msuf2LayersButton then return box._msuf2LayersButton end
    local btn = T.Button(box, TR("Layers") .. " v", 76, 20)
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    btn:SetScript("OnClick", function()
        if box.sidebar then box.sidebar:SetShown(not box.sidebar:IsShown()) end
    end)
    M.AddTooltip(btn, "Layers", "Toggle the preview layer list.", { hook = true })
    RegisterPreviewControl(box._catalogCtx, btn, "layer.popover", "Class Resources Preview Layers", "button", "ephemeral")
    box._msuf2LayersButton = btn
    return btn
end
local function SetClassPowerPreviewToolsShown(box, shown)
    if not box then return end
    local controlsHint = box._msuf2PreviewControlsHint
    if not shown then
        if box._msuf2CompactToolsHidden ~= true then
            box._msuf2CompactControlsHintWasShown = controlsHint and controlsHint.IsShown and controlsHint:IsShown() or false
        end
        box._msuf2CompactToolsHidden = true
        if box.zoomBar then box.zoomBar:Hide() end
        if box.animateButton then box.animateButton:Hide() end
        if controlsHint then controlsHint:Hide() end
        return
    end
    box._msuf2CompactToolsHidden = nil
    if box.zoomBar then box.zoomBar:Show() end
    if box.animateButton then box.animateButton:Show() end
    if controlsHint and box._msuf2CompactControlsHintWasShown then controlsHint:Show() end
end
local function LayoutClassPowerHeaderControls(box, compact)
    if not box then return end
    local header = box._msuf2CompactHeader
    local expandBtn = box._msuf2CompactExpandButton
    local layersBtn = box._msuf2LayersButton
    if compact and header then
        if layersBtn then
            layersBtn:SetText(TR("Layers") .. " v")
            layersBtn:SetParent(header)
            layersBtn:ClearAllPoints()
            if expandBtn then layersBtn:SetPoint("RIGHT", expandBtn, "LEFT", -8, 0)
            else layersBtn:SetPoint("RIGHT", header, "RIGHT", -108, 0) end
            if layersBtn.SetFrameLevel and header.GetFrameLevel then layersBtn:SetFrameLevel((header:GetFrameLevel() or 1) + 3) end
        end
        return
    end
    if layersBtn then
        layersBtn:SetText(TR("Layers"))
        layersBtn:SetParent(box)
        layersBtn:ClearAllPoints()
        layersBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -5)
    end
end
local function ApplyClassPowerCompactPresentation(box, compact, sideW)
    if not box then return end
    compact = compact == true
    box._msuf2CompactPreview = compact
    if box._msuf2PinnedFloating == true then compact = false end
    local boxWidth = max(1, tonumber(box.GetWidth and box:GetWidth()) or 1)
    local resolvedSideW = min(104, max(72, boxWidth - 252))
    if Helpers.SwitchCompactZoomMode then Helpers.SwitchCompactZoomMode(box, compact, 1.50) end
    local canvas, sidebar = box.canvas, box.sidebar
    if compact then
        if box.title then box.title:Hide() end
        if box.hint then box.hint:Hide() end
        SetClassPowerPreviewToolsShown(box, false)
        if canvas then
            box.canvasW = max(1, (box.GetWidth and box:GetWidth() or 1) - 16)
            box.canvasH = max(1, (box.GetHeight and box:GetHeight() or 1) - 16)
            canvas:ClearAllPoints()
            canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
            canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
            if box.stage then box.stage:SetSize(box.canvasW, box.canvasH) end
        end
        local layersBtn = EnsureClassPowerLayersButton(box)
        if sidebar and canvas then
            local rows = #(box.layerButtons or {})
            sidebar:ClearAllPoints()
            if box._msuf2CompactHeader then sidebar:SetPoint("TOPRIGHT", layersBtn, "BOTTOMRIGHT", 0, -6)
            else sidebar:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -28) end
            sidebar:SetSize(resolvedSideW + 8, 32 + rows * 18 + 10)
            if sidebar.SetFrameLevel and canvas.GetFrameLevel then sidebar:SetFrameLevel((canvas:GetFrameLevel() or 1) + 90) end
            sidebar:Hide()
        end
        layersBtn:Show()
        LayoutClassPowerHeaderControls(box, true)
        return
    end
    if box.title then box.title:Show() end
    if box.hint then box.hint:Show() end
    SetClassPowerPreviewToolsShown(box, true)
    LayoutClassPowerHeaderControls(box, false)
    if canvas then
        box.canvasW = max(1, boxWidth - resolvedSideW - 32)
        box.canvasH = max(1, (tonumber(box.GetHeight and box:GetHeight()) or 330) - 42)
        box._msuf2ExpandedCanvasW, box._msuf2ExpandedCanvasH = box.canvasW, box.canvasH
        box.playerW = min(275, max(190, box.canvasW - 160))
        canvas:ClearAllPoints()
        canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
        canvas:SetSize(box.canvasW, box.canvasH)
        if box.stage then box.stage:SetSize(box.canvasW, box.canvasH) end
    end
    if sidebar and canvas then
        sidebar:ClearAllPoints()
        sidebar:SetPoint("TOPLEFT", canvas, "TOPRIGHT", 8, 0)
        sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
        if sidebar.SetFrameLevel and canvas.GetFrameLevel then sidebar:SetFrameLevel((canvas:GetFrameLevel() or 1) + 1) end
        sidebar:Show()
    end
    if box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
end

--- Build the fixed ClassPower preview section and install its refresh function.
--- The same surface switches between compact and expanded geometry in place.
local CP_PREVIEW_FIXED_HEIGHT = 180
local CP_PREVIEW_COMPACT_BOX_HEIGHT = 132
local CP_PREVIEW_EXPANDED_BOX_HEIGHT = 330
local CP_PREVIEW_BOX_Y = -40
function Preview.Create(ctx, builder)
    if not (W and W.FixedPreviewSection and T and builder) then return nil end
    local section, toolbar, fixedRecord = W.FixedPreviewSection(ctx, builder, {
        title = TR("Preview") .. " - " .. TR("Class Resources"),
        height = CP_PREVIEW_FIXED_HEIGHT,
        gap = 8,
    })
    if not section then return nil end
    -- The preview is fixed page chrome and uses the full page width instead of
    -- the narrower settings-form content width.
    local pageW = ctx.width or builder.width or section._msuf2Width or 720
    local innerW = max(1, pageW - 28)
    local sideW = min(104, max(72, innerW - 252))
    local function CreateClassPowerPreviewBox(parent, initialHeight)
    local box = T.Panel(parent, nil, { 0.018, 0.022, 0.044, 0.88 }, T.colors.borderSoft)
    box._msuf2PreviewSurfaceFamily = "classpower"
    local chrome = Helpers.ApplyPreviewChrome and Helpers.ApplyPreviewChrome(box, "outer", T)
        or { title = T.colors.title or T.colors.text, canvasBorder = T.colors.borderSoft }
    box._catalogCtx = ctx
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, CP_PREVIEW_BOX_Y)
    box:SetSize(innerW, initialHeight or CP_PREVIEW_COMPACT_BOX_HEIGHT)
    box.canvasW, box.canvasH = max(1, innerW - sideW - 32), 288
    box._msuf2ExpandedCanvasW, box._msuf2ExpandedCanvasH = box.canvasW, box.canvasH
    box.playerW, box.playerH = min(275, max(190, box.canvasW - 160)), 38
    box.handles = {}
    if box.EnableKeyboard then box:EnableKeyboard(true) end
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", HandleKeyDown)
    RegisterPreviewControl(ctx, box, "keyboard.nudge_surface", "Class Resources preview keyboard controls", "canvas", "ephemeral", {
        help = "Receives arrow-key nudges for the selected preview handle.",
    })
    local title = T.Font(box, "GameFontNormal", TR("Class Resources Preview"), chrome.title or T.colors.accent)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    box.title = title
    local hint = T.Font(box, "GameFontDisableSmall", TR("Drag handles to move."), T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    box.hint = hint
    box.canvas = T.Panel(box, nil, { 0, 0, 0, 1 }, T.colors.borderSoft)
    box.canvas._msuf2PreviewCanvasUnderlay = box
    if Helpers.ApplyPreviewChrome then Helpers.ApplyPreviewChrome(box.canvas, "canvas", T) end
    box.canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    box.canvas:SetSize(box.canvasW, box.canvasH)
    box._canvasBorderColor = chrome.canvasBorder or T.colors.borderSoft
    if box.canvas.SetClipsChildren then box.canvas:SetClipsChildren(true) end
    box.canvas:EnableMouse(true)
    box.canvas:EnableMouseWheel(true)
    if box.canvas.SetPropagateMouseWheel then box.canvas:SetPropagateMouseWheel(false) end
    box.stage = CreateFrame("Frame", nil, box.canvas)
    box.stage:SetSize(box.canvasW, box.canvasH)
    box.stage:SetPoint("CENTER", box.canvas, "CENTER", 0, 0)
    box.mock = box.stage
    if ZoomPan.Configure then ZoomPan.Configure({ T = T, TR = TR, WHITE8 = WHITE8 }) end
    if Helpers.BuildZoomBar then
        Helpers.BuildZoomBar(box, box.canvas, {
            texture = WHITE8,
            T = T,
            themeReadout = true,
            CreateZoomButton = ZoomPan.CreateButton,
            Tr = TR,
            StepZoom = ZoomPan.Step,
            SetZoom = ZoomPan.SetZoom,
            StartPan = ZoomPan.Start,
            StopPan = ZoomPan.Stop,
            fitReason = "CLASSPOWER_PREVIEW_ZOOM_FIT",
            oneReason = "CLASSPOWER_PREVIEW_ZOOM_1TO1",
            lockButton = true,
            defaultLocked = true,
            lockReason = "CLASSPOWER_PREVIEW_ZOOM_LOCK",
            unlockReason = "CLASSPOWER_PREVIEW_ZOOM_UNLOCK",
        })
        box._msuf2ZoomCommand = box._msuf2ZoomCommand
            or (Helpers.BuildZoomCommand and Helpers.BuildZoomCommand(box, ZoomPan, "CLASSPOWER_PREVIEW_ASSISTANT_ZOOM"))
        RegisterPreviewControl(ctx, box.zoomBar, "zoom.surface", "Class Resources Preview Zoom", "slider", "ephemeral", {
            help = "Sets the Class Resources preview zoom percentage; Fit and 1:1 remain available as exact actions.",
            command = box._msuf2ZoomCommand,
        })
        local zoomControls = {
            { "zoomOutButton", "zoom.out", "Zoom out" },
            { "zoomFitButton", "zoom.fit", "Fit preview" },
            { "zoomOneButton", "zoom.one_to_one", "Pixel preview" },
            { "zoomInButton", "zoom.in", "Zoom in" },
            { "zoomHelpButton", "zoom.help", "Preview controls help" },
            { "zoomLockButton", "zoom.lock", "Lock preview zoom" },
        }
        for i = 1, #zoomControls do
            local info = zoomControls[i]
            RegisterPreviewControl(ctx, box[info[1]], info[2], info[3], "button", "ephemeral")
        end
    end
    if Helpers.EnsurePreviewControlsHint then
        local controlsHint = Helpers.EnsurePreviewControlsHint(box, box.canvas, { M = M, T = T, Tr = TR })
        RegisterPreviewControl(ctx, controlsHint and controlsHint._close, "hint.dismiss", "Dismiss preview tip", "button", "ephemeral")
    end
    box._animationEnabled = General().classPowerPreviewAnimate == true
    CreateAnimateButton(box)
    box.canvas:SetScript("OnMouseDown", function(self, button)
        if ZoomPan.Start and ZoomPan.Start(self, box, button, true) then return end
        box.selectedHandle = nil
        SetArrowBindings(box, false)
        FocusPreviewKeyboardTarget(box, nil, false)
        RefreshHandleVisuals(box)
    end)
    box.canvas:SetScript("OnMouseUp", function(self)
        if ZoomPan.Stop then ZoomPan.Stop(self) end
    end)
    box._msuf2PanCommand = box._msuf2PanCommand or (Helpers.BuildPanCommand and Helpers.BuildPanCommand(
        box, ZoomPan,
        function(dx, dy) return Preview.Pan(dx, dy) end,
        { previewSurface = "class-power" }
    ))
    RegisterPreviewControl(ctx, box.canvas, "canvas", "Class Resources preview canvas", "canvas", "ephemeral", {
        help = "Selects preview handles and pans this exact canvas by an explicit X/Y delta.",
        command = box._msuf2PanCommand,
    })
    CreateLayerSidebar(box, sideW)
    box.noResource = T.Font(box.canvas, "GameFontDisableSmall", TR("Class resource is disabled for this preview resource."), T.colors.muted)
    box.noResource:SetPoint("CENTER", box.canvas, "CENTER", 0, 28)
    box.noResource:Hide()
    CreatePlayerReference(box)
    box.dragFrame = CreateFrame("Frame", nil, UIParent or box.canvas)
    box.dragFrame:SetAllPoints(UIParent or box.canvas)
    if box.dragFrame.SetFrameStrata then box.dragFrame:SetFrameStrata("TOOLTIP") end
    box.dragFrame:EnableMouse(true)
    if Helpers.BindPreviewWheel then Helpers.BindPreviewWheel(box.dragFrame, box) end
    box.dragFrame:SetScript("OnMouseUp", function(self, button)
        StopHandleDrag(self._handle, button, false, true)
    end)
    box.dragFrame:Hide()
    box.dragUpdate = DragUpdate
    box.handleClass = MakeHandle(box, "classPower", "bars", "classPowerOffsetX", "classPowerOffsetY", 0, 0, "Class resource bar", { 0.30, 0.78, 0.55 }, "class", "class", 0)
    box.handleClassText = MakeHandle(box, "classPowerText", "bars", "classPowerTextOffsetX", "classPowerTextOffsetY", 0, 0, "Class resource text", { 0.30, 0.78, 0.55 }, "classText", "classText", 2)
    box.handlePower = MakeHandle(box, "detachedPower", "player", "detachedPowerBarOffsetX", "detachedPowerBarOffsetY", 0, -4, "Player power bar", { 0.95, 0.72, 0.18 }, "power", "power", 0)
    box.handlePowerText = MakeHandle(box, "detachedPowerText", "player", "powerOffsetX", "powerOffsetY", -4, 4, "Player power text", { 0.95, 0.72, 0.18 }, "powerText", "powerText", 2)
    box.handleHP = MakeHandle(box, "playerHP", "bars", "playerHPBarOffsetX", "playerHPBarOffsetY", 0, 0, "Second player HP bar", { 0.25, 0.90, 0.42 }, "hp", "hp", 0)
    box.handleHPText = MakeHandle(box, "playerHPText", "bars", "playerHPBarTextOffsetX", "playerHPBarTextOffsetY", 0, 0, "Second player HP text", { 0.25, 0.90, 0.42 }, "hpText", "hpText", 2)
    function box:Refresh()
        --- Keep the persisted Guides choice authoritative across factory reset,
        --- profile switch and Assistant mutation even when this preview frame
        --- was already constructed under the previous profile table.
        if type(box.layerVisibility) == "table" then
            box.layerVisibility.guides = PreviewGuidesEnabled()
        end
        local bars = Bars()
        local player = Player()
        local spec = M.GetClassPowerPreviewSpec and M.GetClassPowerPreviewSpec() or nil
        PaintPlayerReference(box, spec, bars, player)
        local classFrame, classDisabledReason = RenderClassPower(box, bars, player, spec)
        local ebonFrame = RenderSecondaryClassTimer(box, bars, player, spec, classFrame)
        if classFrame and classFrame.IsShown and classFrame:IsShown() then
            box.noResource:Hide()
        else
            box.noResource:SetText(TR(classDisabledReason == "settings"
                and "Class resource is disabled in Class Resource settings."
                or "The selected preview resource has no class resource."))
            box.noResource:Show()
        end
        local powerFrame = RenderDetachedPower(box, bars, player, classFrame, spec)
        local hpFrame = RenderPlayerHP(box, bars, player, classFrame, powerFrame, spec, ebonFrame)
        box._msufCPPreviewAnim = {
            bars = bars,
            player = player,
            spec = spec,
            classFrame = classFrame,
            ebonFrame = ebonFrame,
            powerFrame = powerFrame,
            hpFrame = hpFrame,
        }
        SetPreviewSummary(box, classFrame, powerFrame, hpFrame)
        box.layerAvailable = {
            guides = true,
            border = true,
            reference = true,
            class = classFrame ~= nil,
            classText = classFrame ~= nil and (bars.classPowerShowText == true
                or (spec and spec.secondaryTimer and spec.secondaryTimer.nativeDurationText == true)),
            power = powerFrame ~= nil,
            powerText = powerFrame ~= nil and PlayerPowerTextShown(player) and player.detachedPowerBarTextOnBar == true,
            hp = hpFrame ~= nil,
            hpText = hpFrame ~= nil and bars.playerHPBarTextEnabled ~= false,
            bounds = true,
        }
        RefreshBounds(box, classFrame, ebonFrame, powerFrame, hpFrame)
        ApplyPreviewZoom(box, classFrame, ebonFrame, powerFrame, hpFrame)
        ApplyLayerVisibility(box)
        RefreshLayerButtons(box)
        RefreshHandleVisuals(box)
        RefreshAnimateButton(box)
        if box._animationEnabled == true then StartAnimationDriver(box) end
    end
    function box:RefreshAnimation()
        return RefreshClassPowerAnimation(box)
    end
    function box:_msufCPPreviewHostShown()
        if tostring(M.activeKey or "") ~= tostring(self._msufCPPreviewPageKey or "classpower") then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        local wrapper = self._msufCPPreviewWrapper
        if wrapper and wrapper.IsShown and not wrapper:IsShown() then return false end
        local ownerShown = self._msufCPPreviewOwnerShown
        return type(ownerShown) ~= "function" or ownerShown() == true
    end
    function box:ReleasePreviewInteraction()
        self.selectedHandle = nil
        SetArrowBindings(self, false)
        FocusPreviewKeyboardTarget(self, nil, false)
        RefreshHandleVisuals(self)
        if self._msufCPPreviewNudgeTarget
            and rawget(_G, "MSUF_EM2_ActivePreviewNudgeTarget") == self._msufCPPreviewNudgeTarget
            and type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function"
        then
            _G.MSUF_EM2_SetPreviewNudgeTarget(nil)
        end
        if Helpers.ReleaseKeyboardCapture then
            Helpers.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
        if self.dragFrame then
            self.dragFrame:SetScript("OnUpdate", nil)
            self.dragFrame._handle = nil
            self.dragFrame:Hide()
        end
    end
    local function ActivateVisiblePreview()
        if box.IsShown and box:IsShown() and box:_msufCPPreviewHostShown() then ActivateClassPowerSurface(box) end
    end
    box:HookScript("OnShow", function()
        ActivateVisiblePreview()
        RequestClassPowerPreviewRefresh(box, "CLASSPOWER_PREVIEW_SHOW")
        if box._animationEnabled == true then StartAnimationDriver(box) end
    end)
    box:HookScript("OnHide", function()
        box._msufCPRefreshSerial = (tonumber(box._msufCPRefreshSerial) or 0) + 1
        box._msufCPRefreshQueued = nil
        box._msufCPRefreshReason = nil
        StopAnimationDriver(box)
        SetArrowBindings(box, false)
        if box._msufCPPreviewNudgeTarget and rawget(_G, "MSUF_EM2_ActivePreviewNudgeTarget") == box._msufCPPreviewNudgeTarget and type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        if Helpers.ReleaseKeyboardCapture then
            Helpers.ReleaseKeyboardCapture(box)
        elseif box.SetPropagateKeyboardInput then
            box:SetPropagateKeyboardInput(true)
        end
        if box.dragFrame then
            box.dragFrame:SetScript("OnUpdate", nil)
            box.dragFrame._handle = nil
            box.dragFrame:Hide()
        end
        if Preview.active == box then Preview.active = nil end
        ActivateClassPowerSurface(nil)
    end)
    box._msuf2PreferredRestoreHeight = CP_PREVIEW_COMPACT_BOX_HEIGHT
    box._msuf2PreferredRestoreYOffset = CP_PREVIEW_BOX_Y
    box._msuf2CompactHeader = toolbar
    box.ApplyPinnedPreviewPresentation = function(self)
        ApplyClassPowerCompactPresentation(self, self._msuf2CompactPreview == true, sideW)
    end
    box.ApplyCompactPreviewPresentation = function(self, compact)
        ApplyClassPowerCompactPresentation(self, compact, sideW)
    end
    return box
    end

    local box = CreateClassPowerPreviewBox(section, CP_PREVIEW_COMPACT_BOX_HEIGHT)
    local title, hint = box.title, box.hint
    box._msufCPPreviewPageKey = ctx and ctx.key
    box._msufCPPreviewWrapper = ctx and ctx.wrapper
    box._msufCPPreviewOwnerShown = function()
        return not section.IsShown or section:IsShown()
    end
    M._msuf2ClassPowerInlinePreview = section
    if W.AttachPinnedPreview then
        W.AttachPinnedPreview(section, box, {
            stateKey = "classPowerPreview",
            title = title,
            hint = hint,
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
        })
    end
    local expander
    if W.AttachFixedPreviewExpander then
        expander = W.AttachFixedPreviewExpander(section, toolbar, box, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            compactHeight = CP_PREVIEW_COMPACT_BOX_HEIGHT,
            compactTop = CP_PREVIEW_BOX_Y,
            expandedHeight = CP_PREVIEW_EXPANDED_BOX_HEIGHT,
            refreshPreview = function(target, reason)
                RequestClassPowerPreviewRefresh(target, reason or "CLASSPOWER_PREVIEW_SIZE")
            end,
            onStateChanged = function(expanded, target)
                if target.ReleasePreviewInteraction then target:ReleasePreviewInteraction() end
                StopAnimationDriver(target)
                target._animationEnabled = General().classPowerPreviewAnimate == true
                ActivateClassPowerSurface(target)
                if target._animationEnabled == true
                    and target.IsShown and target:IsShown()
                    and target._msufCPPreviewHostShown and target:_msufCPPreviewHostShown()
                then
                    StartAnimationDriver(target)
                end
            end,
        })
    end
    box._msuf2CompactExpandButton = expander and expander.button or nil
    box._msuf2FixedPreviewExpanderRecord = expander
    if expander and expander.button then
        RegisterPreviewControl(ctx, expander.button, "height.toggle",
            "Expand Class Resources Preview", "button", "ephemeral")
    end
    box:ApplyCompactPreviewPresentation(true)
    ActivateClassPowerSurface(box)
    local function RefreshVisibleSurfaces(reason)
        RequestClassPowerPreviewRefresh(box, reason or (expander and expander.expanded
            and "CLASSPOWER_PREVIEW_EXPANDED" or "CLASSPOWER_PREVIEW_COMPACT"))
    end
    function section:Refresh(reason)
        RefreshVisibleSurfaces(reason or "CLASSPOWER_PREVIEW_SECTION_REFRESH")
    end
    function M.ResumeClassPowerPreview(reason, pageKey)
        pageKey = tostring(pageKey or M.activeKey or "classpower")
        if tostring(box._msufCPPreviewPageKey or "") ~= pageKey or not box:_msufCPPreviewHostShown() then return false end
        if box.IsShown and not box:IsShown() then box:Show() end
        RequestClassPowerPreviewRefresh(box, reason or "CLASSPOWER_PREVIEW_RESUME")
        ActivateClassPowerSurface(box)
        return true
    end
    M.TrackRefresh(ctx, function() RefreshVisibleSurfaces("CLASSPOWER_PREVIEW_PAGE_REFRESH") end)
    if fixedRecord then
        fixedRecord.onActivate = function()
            if expander and expander.expanded then expander:Relayout("CLASSPOWER_FIXED_HEADER")
            else box:ApplyCompactPreviewPresentation(true) end
            M.ResumeClassPowerPreview("CLASSPOWER_FIXED_HEADER", ctx and ctx.key)
            if box._animationEnabled == true then
                StartAnimationDriver(box)
            end
        end
    end
    return section
end
