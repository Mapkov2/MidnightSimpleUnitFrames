-- MSUF_GF_AuraPreview.lua — Group Frames: Drag-to-Position Preview Box
-- Renders a live mock frame in the GF options panel with draggable handles
-- for aura groups (buff/debuff/externals), spell indicators, status icons,
-- and private auras. All colors, textures, fonts sync live from the active
-- config. Drag resolves nearest anchor + x/y offset, writes to DB.
-- Midnight 12.0, cold-path only, zero combat overhead.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
if not GF then return end

local CreateFrame   = _G.CreateFrame
local GetCursorPosition = _G.GetCursorPosition
local UnitExists    = _G.UnitExists
local pairs         = pairs
local ipairs        = ipairs
local type          = type
local tostring      = tostring
local floor         = math.floor
local max           = math.max
local min           = math.min

local L  = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local SI = GF.SpellIndicators or (_G.MSUF_GF_SpellIndicators)
local W8 = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------------
-- Anchor fraction table: x from left (0-1), y from bottom (0-1)
------------------------------------------------------------------------
local AF = {
    TOPLEFT     = { 0,   1   },
    TOP         = { 0.5, 1   },
    TOPRIGHT    = { 1,   1   },
    LEFT        = { 0,   0.5 },
    CENTER      = { 0.5, 0.5 },
    RIGHT       = { 1,   0.5 },
    BOTTOMLEFT  = { 0,   0   },
    BOTTOM      = { 0.5, 0   },
    BOTTOMRIGHT = { 1,   0   },
}

------------------------------------------------------------------------
-- Resolve nearest anchor from normalized position (0-1 from top-left)
------------------------------------------------------------------------
local function ResolveAnchor(rx, ry)
    local best, bestD = "CENTER", 1e9
    for pt, frac in pairs(AF) do
        local dx = rx - frac[1]
        local dy = ry - (1 - frac[2])
        local d  = dx * dx + dy * dy
        if d < bestD then best, bestD = pt, d end
    end
    return best
end

------------------------------------------------------------------------
-- Calculate x/y offset of handle's anchor-point vs mockFrame's anchor-point
------------------------------------------------------------------------
local function CalcOffset(handle, mockFrame, anchor)
    local frac = AF[anchor]
    if not frac then return 0, 0 end
    local mL = mockFrame:GetLeft()  or 0
    local mB = mockFrame:GetBottom() or 0
    local mW = max(1, mockFrame:GetWidth()  or 1)
    local mH = max(1, mockFrame:GetHeight() or 1)
    local aX = mL + frac[1] * mW
    local aY = mB + frac[2] * mH
    local hW = handle:GetWidth()  or 1
    local hH = handle:GetHeight() or 1
    local hAX = (handle:GetLeft() or 0) + frac[1] * hW
    local hAY = (handle:GetBottom() or 0) + frac[2] * hH
    return floor(hAX - aX + 0.5), floor(hAY - aY + 0.5)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local _box                 -- outer container
local _mockFrame           -- the visual mock group-frame
local _handles      = {}   -- [key] = handle frame
local _siHandles    = {}   -- [spellName] = handle frame (SI pool)
local _statusHandles = {}  -- [iconKey] = handle frame
local _selected            -- currently selected handle
local _getKind             -- fn() → "party" | "raid"
local _coordLabel          -- FontString for coord display
local _classIdx     = 1    -- class rotation index
local _onSectionOpen       -- callback(sectionKey)

local PREVIEW_CLASSES = {
    "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT",
    "SHAMAN","MAGE","WARLOCK","MONK","DRUID","DEMONHUNTER","EVOKER",
}
local PREVIEW_NAMES = {
    "Thrall","Jaina","Sylvanas","Anduin","Tyrande","Arthas",
    "Garrosh","Yrel","Vol'jin","Chen","Malfurion","Illidan","Alexstrasza",
}

local HANDLE_COLORS = {
    buff      = { 0.36, 0.79, 0.36 },
    debuff    = { 0.89, 0.29, 0.29 },
    externals = { 0.20, 0.67, 0.53 },
    si        = { 0.69, 0.50, 0.88 },
    status    = { 0.80, 0.67, 0.20 },
    private   = { 0.50, 0.50, 0.50 },
}

local STATUS_ICON_SPECS = {
    { key = "roleIcon",      label = "Role",        sizeKey = "roleIconSize",      anchorKey = "roleIconAnchor",   xKey = "roleIconX",   yKey = "roleIconY",   layerKey = "roleIconLayer",   defAnchor = "TOPLEFT",  defSize = 12 },
    { key = "leaderIcon",    label = "Leader",       sizeKey = "leaderIconSize",    anchorKey = "leaderIconAnchor", xKey = "leaderIconX", yKey = "leaderIconY", layerKey = "leaderIconLayer", defAnchor = "TOPRIGHT", defSize = 12 },
    { key = "assistIcon",    label = "Assist",       sizeKey = "assistIconSize",    anchorKey = "assistIconAnchor", xKey = "assistIconX", yKey = "assistIconY", layerKey = "assistIconLayer", defAnchor = "TOPRIGHT", defSize = 12 },
    { key = "raidMarker",    label = "Marker",       sizeKey = "raidMarkerSize",    anchorKey = "raidMarkerAnchor", xKey = "raidMarkerX", yKey = "raidMarkerY", layerKey = "raidMarkerLayer", defAnchor = "CENTER",   defSize = 14 },
    { key = "readyCheckIcon",label = "Ready",        sizeKey = "readyCheckSize",    anchorKey = "readyCheckAnchor", xKey = "readyCheckX", yKey = "readyCheckY", layerKey = "readyCheckLayer", defAnchor = "CENTER",   defSize = 16 },
    { key = "summonIcon",    label = "Summon",       sizeKey = "summonIconSize",    anchorKey = "summonAnchor",     xKey = "summonX",     yKey = "summonY",     layerKey = "summonLayer",     defAnchor = "CENTER",   defSize = 16 },
    { key = "resurrectIcon", label = "Rez",          sizeKey = "resurrectIconSize", anchorKey = "resurrectAnchor",  xKey = "resurrectX",  yKey = "resurrectY",  layerKey = "resurrectLayer",  defAnchor = "CENTER",   defSize = 16 },
    { key = "phaseIcon",     label = "Phase",        sizeKey = "phaseIconSize",     anchorKey = "phaseAnchor",      xKey = "phaseX",      yKey = "phaseY",      layerKey = "phaseLayer",      defAnchor = "TOPLEFT",  defSize = 14 },
}

------------------------------------------------------------------------
-- Selection
------------------------------------------------------------------------
local function UpdateCoordDisplay(key, anchor, offX, offY)
    if not _coordLabel then return end
    if not key then
        _coordLabel:SetText("Click a handle to select \194\183 drag to reposition")
    else
        _coordLabel:SetText((key or "?") .. "   anchor: " .. (anchor or "?") .. "   x: " .. (offX or 0) .. "   y: " .. (offY or 0))
    end
end

local function SelectHandle(handle)
    if _selected and _selected ~= handle and _selected._selBorder then
        _selected._selBorder:Hide()
    end
    _selected = handle
    if handle then
        if handle._selBorder then handle._selBorder:Show() end
        if handle._sectionKey and _onSectionOpen then
            _onSectionOpen(handle._sectionKey)
        end
    end
end

------------------------------------------------------------------------
-- Drag system (OnMouseDown/Up/OnUpdate — no StartMoving, scroll-safe)
------------------------------------------------------------------------
do
    local _dragging      = false
    local _dragHandle    = nil
    local _dragOffX      = 0
    local _dragOffY      = 0
    local _dragOrigStrata = "MEDIUM"

    local function DragUpdate(self)
        if not _dragging or self ~= _dragHandle then return end
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        if s == 0 then s = 1 end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT",
            cx / s + _dragOffX, cy / s + _dragOffY)
    end

    local function DragStart(self, btn)
        if btn ~= "LeftButton" then return end
        SelectHandle(self)
        _dragging     = true
        _dragHandle   = self
        _dragOrigStrata = self:GetFrameStrata() or "MEDIUM"
        local cx, cy  = GetCursorPosition()
        local s       = self:GetEffectiveScale()
        if s == 0 then s = 1 end
        _dragOffX = (self:GetLeft() or 0) - cx / s
        _dragOffY = (self:GetTop()  or 0) - cy / s
        self:SetFrameStrata("TOOLTIP")
    end

    local function DragStop(self, btn)
        if btn ~= "LeftButton" or not _dragging or self ~= _dragHandle then return end
        _dragging   = false
        _dragHandle = nil
        self:SetFrameStrata(_dragOrigStrata)
        if not _mockFrame then return end

        local mL = _mockFrame:GetLeft()  or 0
        local mT = _mockFrame:GetTop()   or 0
        local mW = max(1, _mockFrame:GetWidth()  or 1)
        local mH = max(1, _mockFrame:GetHeight() or 1)
        local hCX = ((self:GetLeft() or 0) + (self:GetRight()  or 0)) / 2
        local hCY = ((self:GetTop()  or 0) + (self:GetBottom() or 0)) / 2

        local rx = max(0, min(1, (hCX - mL) / mW))
        local ry = max(0, min(1, (mT - hCY) / mH))

        -- If handle has a fixed anchor from config, keep it; otherwise resolve from position
        local anchor
        if self._getCurrentAnchor then
            anchor = self._getCurrentAnchor()
        end
        if not anchor then
            anchor = ResolveAnchor(rx, ry)
        end
        local offX, offY = CalcOffset(self, _mockFrame, anchor)

        self:ClearAllPoints()
        self:SetPoint(anchor, _mockFrame, anchor, offX, offY)

        UpdateCoordDisplay(self._cfgKey, anchor, offX, offY)

        if self._onDragFinish then
            self._onDragFinish(anchor, offX, offY)
        end
    end

    function GF._PreviewMakeDraggable(handle)
        handle:EnableMouse(true)
        handle:SetScript("OnMouseDown", DragStart)
        handle:SetScript("OnMouseUp",   DragStop)
        handle:SetScript("OnUpdate",    DragUpdate)
    end
end

------------------------------------------------------------------------
-- Handle factory
------------------------------------------------------------------------
local function CreateHandle(parent, key, sectionKey, w, h, colorKey)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(max(6, w), max(6, h))
    f:SetFrameLevel(parent:GetFrameLevel() + 20)
    f._cfgKey     = key
    f._sectionKey = sectionKey

    local sel = f:CreateTexture(nil, "OVERLAY", nil, 7)
    sel:SetPoint("TOPLEFT",     f, "TOPLEFT",     -2, 2)
    sel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  2, -2)
    sel:SetColorTexture(0.27, 0.53, 0.80, 0.45)
    sel:Hide()
    f._selBorder = sel

    local c = HANDLE_COLORS[colorKey or key] or HANDLE_COLORS.status
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
    lbl:SetText(key)
    lbl:SetTextColor(c[1], c[2], c[3], 0.9)
    f._label = lbl

    GF._PreviewMakeDraggable(f)
    return f
end

local function AddMockIcon(handle, size, r, g, b, isCircle)
    local t = handle:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetColorTexture(r or 0.3, g or 0.3, b or 0.3, 1)
    if not handle._icons then handle._icons = {} end
    handle._icons[#handle._icons + 1] = t
    return t
end

local function LayoutMockIcons(handle, size, spacing, perRow, anchor)
    local icons = handle._icons
    if not icons then return end
    local n = #icons
    if n == 0 then return end
    local cols = min(perRow or n, n)
    local rows = floor((n - 1) / cols) + 1
    local totalW = cols * size + max(0, cols - 1) * spacing
    local totalH = rows * size + max(0, rows - 1) * spacing
    handle:SetSize(max(6, totalW), max(6, totalH))
    for i = 1, n do
        local ic = icons[i]
        local col = (i - 1) % cols
        local row = floor((i - 1) / cols)
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        ic:SetPoint("TOPLEFT", handle, "TOPLEFT",
            col * (size + spacing), -(row * (size + spacing)))
    end
end

------------------------------------------------------------------------
-- Build mock group-frame (real StatusBar + BackdropTemplate)
------------------------------------------------------------------------
local PREVIEW_MIN_W = 380
local PREVIEW_MIN_H = 130

local function BuildMockFrame(parent)
    local kind = _getKind and _getKind() or "party"
    local conf = GF.GetConf(kind)
    local rawW = conf.width or 120
    local rawH = conf.height or 40
    local scale = max(1.4, min(2.8, PREVIEW_MIN_W / max(1, rawW)))
    local w = max(PREVIEW_MIN_W, floor(rawW * scale + 0.5))
    local h = max(PREVIEW_MIN_H, floor(rawH * scale + 0.5))
    local powerH = floor((conf.powerHeight or 6) * scale + 0.5)
    local inset = 1

    local f = CreateFrame("Frame", "MSUF_GFPreviewMock", parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    f:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = inset,
        insets = { left = inset, right = inset, top = inset, bottom = inset } })
    f:SetBackdropColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f:SetBackdropBorderColor(conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1)

    local health = CreateFrame("StatusBar", nil, f)
    health:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    health:SetMinMaxValues(0, 1)
    health:SetValue(0.72)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset,
        powerH > 0 and (powerH + inset) or inset)
    f._health = health

    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    healthBg:SetTexture(GF.ResolveBarBgTexture and GF.ResolveBarBgTexture(kind) or W8)
    healthBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f._healthBg = healthBg

    -- Heal prediction overlay
    local healPred = CreateFrame("StatusBar", nil, f)
    healPred:SetStatusBarTexture(W8)
    healPred:SetStatusBarColor(0, 1, 0.4, 0.45)
    healPred:SetMinMaxValues(0, 1)
    healPred:SetValue(0.12)
    healPred:SetPoint("TOPLEFT", health, "TOPRIGHT", -1, 0)
    healPred:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
    healPred:SetWidth(max(1, w * 0.12))
    f._healPred = healPred

    -- Absorb overlay
    local absorb = CreateFrame("StatusBar", nil, f)
    absorb:SetStatusBarTexture(W8)
    absorb:SetStatusBarColor(0.55, 0.70, 1.0, 0.5)
    absorb:SetMinMaxValues(0, 1)
    absorb:SetValue(1)
    absorb:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    absorb:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
    absorb:SetWidth(max(1, w * 0.08))
    f._absorb = absorb

    -- Power bar
    if powerH > 0 then
        local power = CreateFrame("StatusBar", nil, f)
        power:SetStatusBarTexture(GF.ResolveBarTexture(kind))
        power:SetMinMaxValues(0, 1)
        power:SetValue(1)
        power:SetStatusBarColor(0.13, 0.27, 0.67, 1)
        power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(powerH)
        f._power = power

        local powerBg = power:CreateTexture(nil, "BACKGROUND")
        powerBg:SetAllPoints(power)
        powerBg:SetTexture(W8)
        powerBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
        f._powerBg = powerBg
    end

    -- Text overlay layer (above health/absorb bars so text is visible)
    local textLayer = CreateFrame("Frame", nil, f)
    textLayer:SetAllPoints(health)
    textLayer:SetFrameLevel(health:GetFrameLevel() + 5)
    f._textLayer = textLayer

    -- Name text
    local nameFS = textLayer:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(GF.ResolveFontPath(kind), conf.nameFontSize or 12, GF.ResolveFontFlags(kind))
    nameFS:SetPoint("LEFT", health, "LEFT", 6, 0)
    nameFS:SetText(PREVIEW_NAMES[_classIdx] or "Thrall")
    nameFS:SetShadowColor(0, 0, 0, 1)
    nameFS:SetShadowOffset(1, -1)
    f._nameFS = nameFS

    -- HP text
    local hpFS = textLayer:CreateFontString(nil, "OVERLAY")
    hpFS:SetFont(GF.ResolveFontPath(kind), conf.hpFontSize or 10, GF.ResolveFontFlags(kind))
    hpFS:SetPoint("RIGHT", health, "RIGHT", -6, 0)
    hpFS:SetText("72%")
    hpFS:SetShadowColor(0, 0, 0, 1)
    hpFS:SetShadowOffset(1, -1)
    f._hpFS = hpFS

    -- Power text
    if powerH > 0 and f._power then
        local powLayer = CreateFrame("Frame", nil, f)
        powLayer:SetAllPoints(f._power)
        powLayer:SetFrameLevel(f._power:GetFrameLevel() + 2)
        f._powerTextLayer = powLayer
        local powFS = powLayer:CreateFontString(nil, "OVERLAY")
        powFS:SetFont(GF.ResolveFontPath(kind), conf.powerFontSize or 9, GF.ResolveFontFlags(kind))
        powFS:SetPoint("CENTER", f._power, "CENTER", 0, 0)
        powFS:SetText("3,240")
        powFS:SetShadowColor(0, 0, 0, 1)
        powFS:SetShadowOffset(1, -1)
        local fr, fg, fb = GF.ResolveFontColor(kind)
        powFS:SetTextColor(fr, fg, fb, 0.9)
        f._powerFS = powFS
    end

    _mockFrame = f
    f._previewScale = scale
    return f
end

------------------------------------------------------------------------
-- Refresh mock frame visuals from config (colors, textures, fonts, size)
------------------------------------------------------------------------
function GF.RefreshPreviewBox()
    if not _mockFrame or not _getKind then return end
    local kind = _getKind()
    local conf = GF.GetConf(kind)
    local m    = _mockFrame

    -- Size (scaled for preview visibility)
    local rawW = conf.width or 120
    local rawH = conf.height or 40
    local scale = max(1.4, min(2.8, PREVIEW_MIN_W / max(1, rawW)))
    local w = max(PREVIEW_MIN_W, floor(rawW * scale + 0.5))
    local h = max(PREVIEW_MIN_H, floor(rawH * scale + 0.5))
    m:SetSize(w, h)
    m._previewScale = scale

    -- Background
    m:SetBackdropColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    m:SetBackdropBorderColor(conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1)
    if m._healthBg then
        m._healthBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    end

    -- Bar textures
    local barTex = GF.ResolveBarTexture(kind)
    if m._health then m._health:SetStatusBarTexture(barTex) end
    if m._power  then m._power:SetStatusBarTexture(barTex) end
    if m._healthBg then
        local bgTex = (GF.ResolveBarBgTexture and GF.ResolveBarBgTexture(kind)) or W8
        m._healthBg:SetTexture(bgTex)
    end

    -- Power bar geometry
    local powerH = floor((conf.powerHeight or 6) * scale + 0.5)
    local inset = 1
    if m._health then
        m._health:ClearAllPoints()
        m._health:SetPoint("TOPLEFT", m, "TOPLEFT", inset, -inset)
        m._health:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -inset,
            powerH > 0 and (powerH + inset) or inset)
    end
    if m._power then
        if powerH > 0 then
            m._power:SetHeight(powerH)
            m._power:Show()
        else
            m._power:Hide()
        end
    end

    -- Health color (same resolve chain as GF_Render)
    do
        local cls = PREVIEW_CLASSES[_classIdx] or "WARRIOR"
        local getCache = _G.MSUF_UFCore_GetSettingsCache
        local cache = type(getCache) == "function" and getCache() or nil
        local gm = cache and cache.barMode
        if gm == "dark" then
            m._health:SetStatusBarColor(
                cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0, 1)
        elseif gm == "unified" then
            m._health:SetStatusBarColor(
                cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60,
                cache.unifiedBarB or 0.90, 1)
        else
            local mode = conf.healthColorMode or "CLASS"
            if mode == "CLASS" then
                local fastC = _G.MSUF_UFCore_GetClassBarColorFast
                local r, g, b
                if type(fastC) == "function" then r, g, b = fastC(nil, cls) end
                if not r then
                    local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[cls]
                    if cc then r, g, b = cc.r, cc.g, cc.b end
                end
                m._health:SetStatusBarColor(r or 0.2, g or 0.8, b or 0.2, 1)
            elseif mode == "GRADIENT" then
                m._health:SetStatusBarColor(0.65, 0.90, 0.15, 1) -- preview at 72%
            else
                m._health:SetStatusBarColor(
                    conf.healthCustomR or 0.2, conf.healthCustomG or 0.8,
                    conf.healthCustomB or 0.2, 1)
            end
        end
    end

    -- Overlay colors + visibility from config (mirrors _GF_IsAbsorbEnabled)
    do
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        local gfDbKey = (kind == "raid") and "gf_raid" or "gf_party"
        local gfDb = _G.MSUF_DB and _G.MSUF_DB[gfDbKey]
        local function resolve(key)
            if gfDb and gfDb.hlOverride and gfDb[key] ~= nil then return gfDb[key] end
            return gen and gen[key]
        end

        -- Heal prediction
        if m._healPred then
            local hpEn = conf.healPredEnabled
            if hpEn == nil then hpEn = not gen or gen.enableHealPrediction ~= false end
            if hpEn ~= false then
                local r, g, b = 0, 1, 0.4
                if gen then
                    if type(gen.healPredColorR) == "number" then r = gen.healPredColorR end
                    if type(gen.healPredColorG) == "number" then g = gen.healPredColorG end
                    if type(gen.healPredColorB) == "number" then b = gen.healPredColorB end
                end
                m._healPred:SetStatusBarColor(r, g, b, 0.45)
                m._healPred:SetWidth(max(1, w * 0.12))
                m._healPred:Show()
            else
                m._healPred:Hide()
            end
        end

        -- Absorb
        if m._absorb then
            local absOn = true
            local atm = tonumber(resolve("absorbTextMode"))
            if atm then absOn = (atm == 2 or atm == 3)
            else
                local eab = resolve("enableAbsorbBar")
                if eab ~= nil then absOn = (eab ~= false) end
            end
            if absOn then
                local r, g, b = 0.55, 0.70, 1.0
                if gen then
                    if type(gen.absorbBarColorR) == "number" then r = gen.absorbBarColorR end
                    if type(gen.absorbBarColorG) == "number" then g = gen.absorbBarColorG end
                    if type(gen.absorbBarColorB) == "number" then b = gen.absorbBarColorB end
                end
                local a = tonumber(resolve("absorbBarOpacity")) or 0.5
                m._absorb:SetStatusBarColor(r, g, b, a)
                m._absorb:SetWidth(max(1, w * 0.08))
                m._absorb:Show()
            else
                m._absorb:Hide()
            end
        end
    end

    -- Font + text colors + positioning (mirrors ApplyTextLayout, scaled)
    do
        local fp    = GF.ResolveFontPath(kind)
        local ff    = GF.ResolveFontFlags(kind)
        local fr, fg, fb = GF.ResolveFontColor(kind)
        local cls   = PREVIEW_CLASSES[_classIdx] or "WARRIOR"
        local nr, ng, nb = GF.ResolveNameColor(kind, cls)
        local sc = m._previewScale or 1.6

        -- Update text layer level from config
        if m._textLayer and m._health then
            local tl2 = conf.textLayer or 5
            m._textLayer:SetFrameLevel(m._health:GetFrameLevel() + tl2)
        end

        if m._nameFS then
            m._nameFS:SetFont(fp, floor((conf.nameFontSize or 12) * sc + 0.5), ff)
            m._nameFS:SetTextColor(nr or fr, ng or fg, nb or fb, 1)
            m._nameFS:SetText(PREVIEW_NAMES[_classIdx] or "Thrall")
            -- Position from config (anchor + offset, scaled)
            m._nameFS:ClearAllPoints()
            local nAnch = conf.nameAnchor or "LEFT"
            local nox = floor((conf.nameOffsetX or 0) * sc + 0.5)
            local noy = floor((conf.nameOffsetY or 0) * sc + 0.5)
            local pad = floor(3 * sc + 0.5)
            if nAnch == "CENTER" then
                m._nameFS:SetPoint("LEFT", m._health, "LEFT", pad + nox, noy)
                m._nameFS:SetPoint("RIGHT", m._health, "RIGHT", -pad + nox, noy)
                m._nameFS:SetJustifyH("CENTER")
            elseif nAnch == "RIGHT" then
                m._nameFS:SetPoint("LEFT", m._health, "LEFT", pad + nox, noy)
                m._nameFS:SetPoint("RIGHT", m._health, "RIGHT", -pad + nox, noy)
                m._nameFS:SetJustifyH("RIGHT")
            else
                m._nameFS:SetPoint("LEFT", m._health, "LEFT", pad + nox, noy)
                m._nameFS:SetJustifyH("LEFT")
            end
            m._nameFS:SetShown(conf.showName ~= false)
        end
        if m._hpFS then
            -- Show HP text only when at least one slot is active
            local tl = conf.textLeft or "NONE"
            local tc = conf.textCenter or "NONE"
            local tr = conf.textRight or "NONE"
            local hpActive = (tl ~= "NONE" or tc ~= "NONE" or tr ~= "NONE")
            if hpActive then
                m._hpFS:SetFont(fp, floor((conf.hpFontSize or 10) * sc + 0.5), ff)
                m._hpFS:SetTextColor(fr, fg, fb, 0.9)
                m._hpFS:SetShadowColor(0, 0, 0, 1); m._hpFS:SetShadowOffset(1, -1)
                m._hpFS:ClearAllPoints()
                local hox = floor((conf.hpOffsetX or 0) * sc + 0.5)
                local hoy = floor((conf.hpOffsetY or 0) * sc + 0.5)
                local hPad = floor(6 * sc + 0.5)
                -- Position based on which slot is active (prefer center, then right, then left)
                if tc ~= "NONE" then
                    m._hpFS:SetPoint("CENTER", m._health, "CENTER", hox, hoy)
                    m._hpFS:SetJustifyH("CENTER")
                elseif tr ~= "NONE" then
                    m._hpFS:SetPoint("RIGHT", m._health, "RIGHT", -hPad + hox, hoy)
                    m._hpFS:SetJustifyH("RIGHT")
                else
                    m._hpFS:SetPoint("LEFT", m._health, "LEFT", hPad + hox, hoy)
                    m._hpFS:SetJustifyH("LEFT")
                end
                m._hpFS:Show()
            else
                m._hpFS:Hide()
            end
        end
        -- Power text: create on demand if power bar appeared
        if m._power and powerH > 0 then
            if not m._powerTextLayer then
                local ptl = CreateFrame("Frame", nil, m)
                ptl:SetAllPoints(m._power)
                ptl:SetFrameLevel(m._power:GetFrameLevel() + 2)
                m._powerTextLayer = ptl
            end
            if not m._powerFS then
                m._powerFS = m._powerTextLayer:CreateFontString(nil, "OVERLAY")
                m._powerFS:SetText("3,240")
            end
            local ptl2 = conf.powerTextLayer or 2
            m._powerTextLayer:SetFrameLevel(m._power:GetFrameLevel() + ptl2)
            m._powerFS:SetFont(fp, floor((conf.powerFontSize or 9) * sc + 0.5), ff)
            m._powerFS:SetTextColor(fr, fg, fb, 0.9)
            m._powerFS:ClearAllPoints()
            local pox = floor((conf.powerOffsetX or 0) * sc + 0.5)
            local poy = floor((conf.powerOffsetY or 0) * sc + 0.5)
            m._powerFS:SetPoint("CENTER", m._power, "CENTER", pox, poy)
            m._powerFS:SetShown(conf.showPower and true or false)
        elseif m._powerFS then
            m._powerFS:Hide()
        end
    end

    -- Refresh handle positions from config
    GF.RefreshPreviewHandles()
end

------------------------------------------------------------------------
-- Build aura group handles (buff / debuff / externals)
------------------------------------------------------------------------
local AURA_GRP_COLORS = {
    buff      = { {0.23,0.42,0.23}, {0.23,0.35,0.29}, {0.29,0.48,0.23}, {0.20,0.40,0.20}, {0.25,0.45,0.25}, {0.22,0.38,0.22} },
    debuff    = { {0.42,0.13,0.13}, {0.48,0.17,0.17}, {0.38,0.10,0.10}, {0.45,0.15,0.15}, {0.40,0.12,0.12}, {0.50,0.18,0.18} },
    externals = { {0.10,0.35,0.23}, {0.17,0.42,0.29}, {0.12,0.38,0.25}, {0.15,0.40,0.27} },
}

local function BuildAuraGroupHandles(mockFrame)
    local GROUPS = {
        { key = "buff",      section = "buffs",   defAnchor = "BOTTOMLEFT", defSize = 16 },
        { key = "debuff",    section = "debuffs",  defAnchor = "TOPRIGHT",   defSize = 16 },
        { key = "externals", section = "ext",      defAnchor = "CENTER",     defSize = 22 },
    }
    for _, grp in ipairs(GROUPS) do
        local handle = CreateHandle(mockFrame, grp.key, grp.section,
            grp.defSize, grp.defSize, grp.key)
        handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        handle._label:SetText(grp.key:sub(1,1):upper() .. grp.key:sub(2))
        handle._grpKey = grp.key
        handle._defAnchor = grp.defAnchor
        handle._grpIcons = {}
        handle._onDragFinish = function(anchor, offX, offY)
            local sc = _mockFrame and _mockFrame._previewScale or 1
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            if not conf.auras then conf.auras = {} end
            if not conf.auras[grp.key] then conf.auras[grp.key] = {} end
            conf.auras[grp.key].anchor = anchor
            conf.auras[grp.key].x = floor(offX / sc + 0.5)
            conf.auras[grp.key].y = floor(offY / sc + 0.5)
            GF.RefreshVisuals()
        end
        handle._getCurrentAnchor = function()
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            local ac = conf.auras and conf.auras[grp.key]
            return ac and ac.anchor or grp.defAnchor
        end
        _handles[grp.key] = handle
    end
end

------------------------------------------------------------------------
-- Build status icon handles
------------------------------------------------------------------------
local function BuildStatusIconHandles(mockFrame)
    for _, spec in ipairs(STATUS_ICON_SPECS) do
        local handle = CreateHandle(mockFrame, spec.key, "sicons",
            spec.defSize, spec.defSize, "status")
        handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        handle._label:SetText(spec.label)
        local t = handle:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(handle)
        handle._statusTex = t
        handle._statusSpec = spec
        handle._onDragFinish = function(anchor, offX, offY)
            local sc = _mockFrame and _mockFrame._previewScale or 1
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            conf[spec.anchorKey] = anchor
            conf[spec.xKey] = floor(offX / sc + 0.5)
            conf[spec.yKey] = floor(offY / sc + 0.5)
            GF.RefreshVisuals()
        end
        handle._getCurrentAnchor = function()
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            return conf[spec.anchorKey] or spec.defAnchor
        end
        _statusHandles[spec.key] = handle
    end
end

------------------------------------------------------------------------
-- Build spell indicator handles (dynamic per spec)
------------------------------------------------------------------------
function GF.RebuildSIHandles()
    if not _mockFrame or not _getKind then return end
    if not SI then SI = GF.SpellIndicators or _G.MSUF_GF_SpellIndicators end
    -- Hide existing
    for _, h in pairs(_siHandles) do
        h:Hide()
    end
    local kind   = _getKind()
    local conf   = GF.GetConf(kind)
    local siCfg  = conf.spellIndicators
    if not siCfg or siCfg.enabled == false then return end
    if not SI or not SI.SpecDefaults then return end

    local specKey = siCfg.spec or "auto"
    if specKey == "auto" then
        specKey = (SI.ResolveSpec and SI.ResolveSpec(siCfg)) or "RestorationDruid"
    end
    if specKey == "multi" then specKey = "RestorationDruid" end

    local defaults = SI.SpecDefaults[specKey]
    if not defaults then return end

    local specData = siCfg.specs and siCfg.specs[specKey]

    for spellName, defCfg in pairs(defaults) do
        local placed = defCfg.placed
        if not placed then
            -- frame-only effects, no visual handle
        else
            -- Check user override
            local userPlaced
            if specData and specData[spellName] and specData[spellName].placed then
                userPlaced = specData[spellName].placed
            end
            local cfg = userPlaced or placed

            local h = _siHandles[spellName]
            if not h then
                h = CreateHandle(_mockFrame, spellName, "si",
                    cfg.size or 18, cfg.size or 18, "si")
                h._label:SetPoint("BOTTOM", h, "TOP", 0, 1)
                _siHandles[spellName] = h
            end

            local sz = cfg.size or 18
            h:SetSize(max(6, sz), max(6, sz))
            h._label:SetText(spellName:sub(1, 8))
            h._cfgKey = spellName

            -- Visual: icon texture or colored square
            if not h._siTex then
                h._siTex = h:CreateTexture(nil, "ARTWORK")
            end
            h._siTex:SetSize(sz, sz)
            h._siTex:ClearAllPoints()
            h._siTex:SetPoint("CENTER", h, "CENTER", 0, 0)

            local itype = cfg.type or "icon"
            if itype == "icon" and SI.GetAuraIcon then
                h._siTex:SetTexture(SI.GetAuraIcon(specKey, spellName))
                h._siTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif itype == "square" or itype == "bar" then
                local clr = (defCfg.placed and defCfg.placed.color)
                    or (defCfg.frame and defCfg.frame.color) or {0.5, 0.8, 0.5}
                h._siTex:SetColorTexture(clr[1] or 0.5, clr[2] or 0.8, clr[3] or 0.5, 1)
                h._siTex:SetTexCoord(0, 1, 0, 1)
            else
                h._siTex:SetColorTexture(0.35, 0.55, 0.35, 1)
                h._siTex:SetTexCoord(0, 1, 0, 1)
            end
            h._siTex:Show()

            -- Position from config (scaled for preview)
            local psc = _mockFrame._previewScale or 1.6
            local anchor = cfg.anchor or "TOPLEFT"
            local offX   = floor(((cfg.x) or 0) * psc + 0.5)
            local offY   = floor(((cfg.y) or 0) * psc + 0.5)
            local ssz    = floor(sz * psc + 0.5)
            h:SetSize(max(6, ssz), max(6, ssz))
            h._siTex:SetSize(ssz, ssz)
            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(_mockFrame:GetFrameLevel() + (siCfg.layer or 9))
            h:Show()

            -- Drag writes to per-spell config (unscaled)
            local capturedSpec = specKey
            local capturedSpell = spellName
            h._onDragFinish = function(anc, ox, oy)
                local dsc = _mockFrame and _mockFrame._previewScale or 1
                local k = _getKind and _getKind() or "party"
                local c = GF.GetConf(k)
                if not c.spellIndicators then c.spellIndicators = { enabled = true, spec = "auto", specs = {} } end
                local si = c.spellIndicators
                if not si.specs then si.specs = {} end
                if not si.specs[capturedSpec] then si.specs[capturedSpec] = {} end
                if not si.specs[capturedSpec][capturedSpell] then
                    si.specs[capturedSpec][capturedSpell] = {}
                end
                local entry = si.specs[capturedSpec][capturedSpell]
                if not entry.placed then
                    entry.placed = {}
                    local def = defaults[capturedSpell] and defaults[capturedSpell].placed
                    if def then
                        for dk, dv in pairs(def) do entry.placed[dk] = dv end
                    end
                end
                entry.placed.anchor = anc
                entry.placed.x = floor(ox / dsc + 0.5)
                entry.placed.y = floor(oy / dsc + 0.5)
                GF.RefreshVisuals()
            end
            h._getCurrentAnchor = function()
                local k = _getKind and _getKind() or "party"
                local c = GF.GetConf(k)
                local si = c.spellIndicators
                local sp = si and si.specs and si.specs[capturedSpec]
                local e = sp and sp[capturedSpell]
                local p = e and e.placed
                return p and p.anchor
            end
        end
    end
end

------------------------------------------------------------------------
-- Build private aura handle
------------------------------------------------------------------------
local function BuildPrivateAuraHandle(mockFrame)
    local handle = CreateHandle(mockFrame, "private", "priv", 16, 16, "private")
    handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
    handle._label:SetText("Private")
    handle._onDragFinish = function(anchor, offX, offY)
        local sc = _mockFrame and _mockFrame._previewScale or 1
        local kind = _getKind and _getKind() or "party"
        local conf = GF.GetConf(kind)
        if not conf.privateAuras then conf.privateAuras = {} end
        conf.privateAuras.anchor = anchor
        conf.privateAuras.x = floor(offX / sc + 0.5)
        conf.privateAuras.y = floor(offY / sc + 0.5)
        GF.RefreshVisuals()
    end
    handle._getCurrentAnchor = function()
        local kind = _getKind and _getKind() or "party"
        local conf = GF.GetConf(kind)
        local pa = conf.privateAuras
        return pa and pa.anchor or "BOTTOM"
    end
    _handles.private = handle
end

------------------------------------------------------------------------
-- Refresh all handle positions from config
------------------------------------------------------------------------
function GF.RefreshPreviewHandles()
    if not _mockFrame or not _getKind then return end
    local kind = _getKind()
    local conf = GF.GetConf(kind)
    local sc   = _mockFrame._previewScale or 1.6
    -- Dynamic content scale: simulates icon shrink for large raids (mirrors live GetDynamicScale)
    local dynScale = GF.GetPreviewDynamicScale and GF.GetPreviewDynamicScale(conf, kind) or 1

    -- Aura groups (dynamic icon count from config max)
    for _, grpKey in ipairs({"buff", "debuff", "externals"}) do
        local h = _handles[grpKey]
        if h then
            local ac = conf.auras and conf.auras[grpKey]
            local anchor  = (ac and ac.anchor) or h._defAnchor or "BOTTOMLEFT"
            local offX    = floor(((ac and ac.x) or 0) * sc + 0.5)
            local offY    = floor(((ac and ac.y) or 0) * sc + 0.5)
            local rawSz   = (ac and ac.size) or (grpKey == "externals" and 22 or 16)
            if dynScale ~= 1 then rawSz = max(8, floor(rawSz * dynScale + 0.5)) end
            local sz      = floor(rawSz * sc + 0.5)
            local perRow  = (ac and ac.perRow) or (grpKey == "externals" and 6 or 4)
            local rawSpc  = (ac and ac.spacing) or 1
            local spacing = floor(rawSpc * sc + 0.5)
            local maxIcons = (ac and ac.max) or (grpKey == "externals" and 2 or 6)
            local en = not ac or ac.enabled ~= false

            -- Ensure icon pool
            local pool = h._grpIcons or {}
            h._grpIcons = pool
            local colors = AURA_GRP_COLORS[grpKey] or AURA_GRP_COLORS.buff

            for i = 1, maxIcons do
                local ic = pool[i]
                if not ic then
                    ic = h:CreateTexture(nil, "ARTWORK")
                    pool[i] = ic
                end
                local c = colors[((i - 1) % #colors) + 1]
                ic:SetColorTexture(c[1], c[2], c[3], 1)
                ic:SetSize(sz, sz)
                ic:Show()
            end
            for i = maxIcons + 1, #pool do
                pool[i]:Hide()
            end

            -- Layout grid
            local cols = min(perRow, maxIcons)
            local rows = max(1, floor((maxIcons - 1) / cols) + 1)
            local totalW = cols * sz + max(0, cols - 1) * spacing
            local totalH = rows * sz + max(0, rows - 1) * spacing
            h:SetSize(max(6, totalW), max(6, totalH))
            for i = 1, maxIcons do
                local ic = pool[i]
                local col = (i - 1) % cols
                local row = floor((i - 1) / cols)
                ic:ClearAllPoints()
                ic:SetPoint("TOPLEFT", h, "TOPLEFT",
                    col * (sz + spacing), -(row * (sz + spacing)))
            end

            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(_mockFrame:GetFrameLevel() + (ac and ac.layer or (grpKey == "buff" and 5 or (grpKey == "debuff" and 6 or 7))))
            h:SetShown(en)
            UpdateCoordDisplay(nil)
        end
    end

    -- Status icons (real textures from icon style, layer = z-order)
    local baseLvl = _mockFrame:GetFrameLevel() + 1
    for _, spec in ipairs(STATUS_ICON_SPECS) do
        local h = _statusHandles[spec.key]
        if h then
            local anchor = conf[spec.anchorKey] or spec.defAnchor
            local offX   = floor(((conf[spec.xKey]) or 0) * sc + 0.5)
            local offY   = floor(((conf[spec.yKey]) or 0) * sc + 0.5)
            local sz     = floor(((conf[spec.sizeKey]) or spec.defSize) * sc + 0.5)
            local layer  = (conf[spec.layerKey]) or 1
            h:SetSize(max(6, sz), max(6, sz))
            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(baseLvl + layer)
            local en = conf[spec.key] ~= false
            h:SetShown(en)

            -- Apply real texture
            local tex = h._statusTex
            if tex then
                local sKey = spec.key
                local l, r, t, b = 0, 1, 0, 1
                local path
                if sKey == "roleIcon" and GF.GetRoleTexture then
                    path, l, r, t, b = GF.GetRoleTexture(kind, "HEALER")
                elseif sKey == "leaderIcon" and GF.GetLeaderTexture then
                    path, l, r, t, b = GF.GetLeaderTexture(kind)
                elseif sKey == "assistIcon" and GF.GetAssistTexture then
                    path, l, r, t, b = GF.GetAssistTexture(kind)
                elseif sKey == "raidMarker" then
                    path = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
                    l, r, t, b = 0, 0.25, 0, 0.25 -- star marker
                elseif sKey == "readyCheckIcon" then
                    path = "Interface\\RaidFrame\\ReadyCheck-Ready"
                elseif sKey == "summonIcon" then
                    path = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
                elseif sKey == "resurrectIcon" then
                    path = "Interface\\RaidFrame\\Raid-Icon-Rez"
                elseif sKey == "phaseIcon" then
                    path = "Interface\\TargetingFrame\\UI-PhasingIcon"
                end
                if path then
                    tex:SetTexture(path)
                    tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                    tex:SetVertexColor(1, 1, 1, 1)
                end
            end
        end
    end

    -- Private auras
    do
        local h = _handles.private
        if h then
            local pa = conf.privateAuras or {}
            local anchor = pa.anchor or "BOTTOM"
            local offX = floor(((pa.x) or 0) * sc + 0.5)
            local offY = floor(((pa.y) or 0) * sc + 0.5)
            local paSz = floor(((pa.size) or 16) * sc + 0.5)
            local paMax = (pa.max) or 3
            local totalW = max(6, paSz * paMax + (paMax - 1) * 2)
            h:SetSize(totalW, max(6, paSz))
            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(_mockFrame:GetFrameLevel() + (pa.layer or 8))
            if not h._paIcons then
                h._paIcons = {}
            end
            for pi = 1, paMax do
                local pic = h._paIcons[pi]
                if not pic then
                    pic = h:CreateTexture(nil, "ARTWORK")
                    h._paIcons[pi] = pic
                end
                pic:SetSize(paSz, paSz)
                pic:ClearAllPoints()
                pic:SetPoint("TOPLEFT", h, "TOPLEFT", (pi - 1) * (paSz + 2), 0)
                pic:SetColorTexture(0.20, 0.20, 0.25, 1)
                pic:Show()
            end
            for pi = paMax + 1, #h._paIcons do
                h._paIcons[pi]:Hide()
            end
            h:SetShown(pa.enabled ~= false)
        end
    end

    -- SI handles
    GF.RebuildSIHandles()

    -- Corner Indicator preview dots
    -- All 5 slots always visible: active = filled color, inactive = dim outline
    do
        local CI_SPECS = {
            { key = "TL", anchor = "TOPLEFT",     ox =  2, oy = -2 },
            { key = "TR", anchor = "TOPRIGHT",    ox = -2, oy = -2 },
            { key = "BL", anchor = "BOTTOMLEFT",  ox =  2, oy =  2 },
            { key = "BR", anchor = "BOTTOMRIGHT", ox = -2, oy =  2 },
            { key = "C",  anchor = "CENTER",      ox =  0, oy =  0 },
        }
        local CI_CAT_COLORS = {
            dispel  = { 0.25, 0.75, 1.00 },
            boss    = { 1.00, 0.15, 0.15 },
            missing = { 0.80, 0.80, 0.80 },
        }
        local CI_CAT_LABELS = {
            dispel  = "D",
            boss    = "B",
            missing = "M",
        }

        if not _mockFrame._ciDots then _mockFrame._ciDots = {} end
        local dots = _mockFrame._ciDots
        local ciRawSz = conf.ciSize or 8
        local ciSz = max(8, floor(ciRawSz * sc + 0.5))
        local ciEnabled = conf.ciEnabled ~= false
        local bdTbl = { bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

        for _, spec in ipairs(CI_SPECS) do
            -- Lazy-create as Frame with backdrop (not just a texture)
            local dot = dots[spec.key]
            if not dot then
                dot = CreateFrame("Frame", nil, _mockFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
                dot:EnableMouse(false)
                dots[spec.key] = dot

                -- Fill texture
                dot._ciFill = dot:CreateTexture(nil, "ARTWORK")
                dot._ciFill:SetAllPoints(dot)

                -- Label (slot initial or category letter)
                dot._ciLabel = dot:CreateFontString(nil, "OVERLAY")
                dot._ciLabel:SetPoint("CENTER", dot, "CENTER", 0, 0)
                dot._ciLabel:SetShadowColor(0, 0, 0, 1)
                dot._ciLabel:SetShadowOffset(1, -1)
            end

            local dbKey = "ciSlot" .. spec.key
            local cat = conf[dbKey] or "none"
            local c = CI_CAT_COLORS[cat]
            local isActive = ciEnabled and cat ~= "none" and c

            -- Size + position
            dot:SetSize(ciSz, ciSz)
            dot:ClearAllPoints()
            dot:SetPoint(spec.anchor, _mockFrame, spec.anchor,
                floor(spec.ox * sc + 0.5), floor(spec.oy * sc + 0.5))
            dot:SetFrameLevel(_mockFrame:GetFrameLevel() + 10)

            -- Backdrop border
            if dot.SetBackdrop then
                dot:SetBackdrop(bdTbl)
            end

            -- Font size scales with dot
            local fSz = max(6, floor(ciSz * 0.65 + 0.5))
            local fp = GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
            dot._ciLabel:SetFont(fp, fSz, "OUTLINE")

            if isActive then
                -- Active: filled with category color + bright border
                dot._ciFill:SetColorTexture(c[1], c[2], c[3], conf.ciAlpha or 1.0)
                dot._ciFill:Show()
                if dot.SetBackdropColor then
                    dot:SetBackdropColor(c[1], c[2], c[3], conf.ciAlpha or 1.0)
                end
                if dot.SetBackdropBorderColor then
                    dot:SetBackdropBorderColor(0, 0, 0, 1)
                end
                dot._ciLabel:SetText(CI_CAT_LABELS[cat] or "")
                dot._ciLabel:SetTextColor(1, 1, 1, 0.95)
                dot._ciLabel:Show()
                dot:Show()
            elseif ciEnabled then
                -- Inactive: dim outline placeholder showing slot position
                dot._ciFill:SetColorTexture(0.15, 0.15, 0.18, 0.5)
                dot._ciFill:Show()
                if dot.SetBackdropColor then
                    dot:SetBackdropColor(0.15, 0.15, 0.18, 0.5)
                end
                if dot.SetBackdropBorderColor then
                    dot:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.6)
                end
                dot._ciLabel:SetText(spec.key)
                dot._ciLabel:SetTextColor(0.5, 0.5, 0.55, 0.7)
                dot._ciLabel:Show()
                dot:Show()
            else
                -- CI disabled entirely
                dot:Hide()
            end
        end
    end

    -- Section-aware focus: dim/hide elements not relevant to the active Options section
    local focus = GF._previewFocus
    local showText   = not focus or focus == "text" or focus == "overlay"
    local showAuras  = not focus or focus == "indicators" or focus == "sicons"
    local showSIcons = not focus or focus == "sicons"
    local showSI     = not focus or focus == "indicators"
    local showPriv   = not focus or focus == "indicators"
    local showCI     = not focus or focus == "ci"

    -- Text layer visibility
    if _mockFrame._textLayer then _mockFrame._textLayer:SetShown(showText) end
    if _mockFrame._powerTextLayer then _mockFrame._powerTextLayer:SetShown(showText) end

    -- Aura group handles
    for _, grpKey in ipairs({"buff", "debuff", "externals"}) do
        local h = _handles[grpKey]
        if h and h:IsShown() then
            h:SetAlpha(showAuras and 1 or 0.15)
        end
    end

    -- Status icon handles
    for _, spec in ipairs(STATUS_ICON_SPECS) do
        local h = _statusHandles[spec.key]
        if h and h:IsShown() then
            h:SetAlpha(showSIcons and 1 or 0.15)
        end
    end

    -- SI handles
    if _siHandles then
        for _, h in pairs(_siHandles) do
            if h and h:IsShown() then
                h:SetAlpha(showSI and 1 or 0.15)
            end
        end
    end

    -- Private aura handle
    local privH = _handles.private
    if privH and privH:IsShown() then
        privH:SetAlpha(showPriv and 1 or 0.15)
    end

    -- Corner Indicator preview dots
    if _mockFrame._ciDots then
        for _, dot in pairs(_mockFrame._ciDots) do
            if dot and type(dot.IsShown) == "function" and dot:IsShown() then
                dot:SetAlpha(showCI and 1 or 0.10)
            end
        end
    end
end

------------------------------------------------------------------------
-- Section-aware preview focus
-- Called by Options panel when accordion sections expand/collapse.
-- focus = sectionKey ("text", "sicons", "indicators", "overlay", etc.) or nil (show all)
------------------------------------------------------------------------
function GF.SetPreviewFocus(focus)
    GF._previewFocus = focus
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
end

------------------------------------------------------------------------
-- Main API: Create the full preview box
-- parent: scrollChild frame to embed into
-- getKindFn: function returning "party" or "raid"
-- onSectionOpenFn: function(sectionKey) to auto-open accordion
-- Returns: the container frame (for anchoring sections below)
------------------------------------------------------------------------
function GF.CreatePreviewBox(parent, getKindFn, onSectionOpenFn)
    if _box then return _box end
    _getKind       = getKindFn
    _onSectionOpen = onSectionOpenFn

    -- Outer container
    local container = CreateFrame("Frame", "MSUF_GFPreviewContainer", parent, "BackdropTemplate")
    container:SetSize(680, 260)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    container:SetBackdropColor(0.06, 0.06, 0.08, 1)
    container:SetBackdropBorderColor(0.18, 0.18, 0.22, 1)
    _box = container

    -- Header
    local hdr = container:CreateFontString(nil, "OVERLAY")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    hdr:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -6)
    hdr:SetText("FRAME PREVIEW \194\183 click element to configure \194\183 drag to reposition")
    hdr:SetTextColor(0.45, 0.45, 0.55, 1)

    -- Class rotate button
    local classBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
    classBtn:SetSize(60, 16)
    classBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -70, -4)
    classBtn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    classBtn:SetBackdropColor(0.12, 0.12, 0.16, 1)
    classBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    do
        local cfs = classBtn:CreateFontString(nil, "OVERLAY")
        cfs:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        cfs:SetPoint("CENTER", classBtn, "CENTER", 0, 0)
        cfs:SetText("\226\134\187 Class")
        cfs:SetTextColor(0.7, 0.7, 0.7, 1)
    end
    classBtn:SetScript("OnClick", function()
        _classIdx = (_classIdx % #PREVIEW_CLASSES) + 1
        GF.RefreshPreviewBox()
    end)
    classBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    end)
    classBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    end)

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
    resetBtn:SetSize(46, 16)
    resetBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -4)
    resetBtn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    resetBtn:SetBackdropColor(0.12, 0.12, 0.16, 1)
    resetBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    do
        local rfs = resetBtn:CreateFontString(nil, "OVERLAY")
        rfs:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        rfs:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
        rfs:SetText("Reset")
        rfs:SetTextColor(0.7, 0.7, 0.7, 1)
    end
    resetBtn:SetScript("OnClick", function()
        GF.RefreshPreviewHandles()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    end)

    -- Preview area (black background)
    local area = CreateFrame("Frame", nil, container, "BackdropTemplate")
    area:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -24)
    area:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -24)
    area:SetHeight(210)
    area:SetBackdrop({ bgFile = W8 })
    area:SetBackdropColor(0.02, 0.02, 0.04, 1)
    container._area = area

    -- Build mock frame inside area
    BuildMockFrame(area)

    -- Click on frame background opens General section
    _mockFrame:EnableMouse(true)
    _mockFrame:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        SelectHandle(nil)
        UpdateCoordDisplay("general", nil, nil, nil)
        if _onSectionOpen then _onSectionOpen("general") end
    end)

    -- Build all handles
    BuildAuraGroupHandles(_mockFrame)
    BuildStatusIconHandles(_mockFrame)
    BuildPrivateAuraHandle(_mockFrame)

    -- Coord display
    local coord = container:CreateFontString(nil, "OVERLAY")
    coord:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    coord:SetPoint("BOTTOM", container, "BOTTOM", 0, 4)
    coord:SetTextColor(0.45, 0.45, 0.55, 1)
    coord:SetText("Click a handle to select \194\183 drag to reposition")
    _coordLabel = coord

    -- Initial refresh
    GF.RefreshPreviewBox()

    return container
end

------------------------------------------------------------------------
-- Scope switch hook: full refresh on party/raid toggle
------------------------------------------------------------------------
function GF.PreviewScopeChanged()
    _classIdx = 1
    GF.RefreshPreviewBox()
end

------------------------------------------------------------------------
-- Select a status icon handle by key (called from Options dropdown)
-- Does NOT open section — assumes sicons is already open
------------------------------------------------------------------------
function GF._PreviewSelectStatusIcon(iconKey)
    if not iconKey then return end
    local h = _statusHandles[iconKey]
    if not h then return end
    -- Select without triggering section open
    if _selected and _selected ~= h and _selected._selBorder then
        _selected._selBorder:Hide()
    end
    _selected = h
    if h._selBorder then h._selBorder:Show() end
    UpdateCoordDisplay("sicons", iconKey, nil, nil)
end

------------------------------------------------------------------------
-- Resize container height dynamically based on mock frame
------------------------------------------------------------------------
function GF.ResizePreviewContainer()
    if not _box or not _mockFrame then return end
    local mH = _mockFrame:GetHeight() or 130
    local totalH = mH + 90  -- header(24) + padding(40) + coord(16) + margin(10)
    totalH = max(200, totalH)
    _box:SetHeight(totalH)
    if _box._area then
        _box._area:SetHeight(mH + 50)
    end
end

------------------------------------------------------------------------
-- Hook into GF.RefreshVisuals to keep preview in sync
------------------------------------------------------------------------
do
    local _origRefresh = GF.RefreshVisuals
    if type(_origRefresh) == "function" then
        GF.RefreshVisuals = function(...)
            _origRefresh(...)
            if _box and _box:IsShown() then
                GF.RefreshPreviewBox()
                GF.ResizePreviewContainer()
                if GF._RefreshOptionWidgets then GF._RefreshOptionWidgets() end
            end
        end
    end
end

------------------------------------------------------------------------
_G.MSUF_GF_CreatePreviewBox = GF.CreatePreviewBox
_G.MSUF_GF_RefreshPreviewBox = GF.RefreshPreviewBox
