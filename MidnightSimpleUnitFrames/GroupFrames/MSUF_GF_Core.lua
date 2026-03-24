--[[
MSUF_GF_Core.lua  v6
GroupFrames: frame factory, layout, roster, Blizzard hiding, preview system.

Preview system (v6):
  - _G.MSUF_GF_PreviewActive: toggled by HUD "GF" button
  - When active + Edit Mode + solo: shows 4 party frames with fake HP/name data
  - Fake data applied directly here (not via UpdateSimpleUnitFrame) so frames
    render even without a real unit attached
  - Preview off → frames hidden when solo

Drag fix (v6): getConf returns actual DB table, not virtual transient.
]]

local addonName, ns = ...
ns = ns or {}

local _G               = _G
local type             = type
local pairs            = pairs
local select           = select
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid         = IsInRaid
local IsInGroup        = IsInGroup
local hooksecurefunc   = hooksecurefunc
local math_floor       = math.floor
local math_random      = math.random

local GF = ns.GF or {}
ns.GF = GF

-- ═══════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════
local _partyFrames    = {}
local _partyCreated   = false
local _raidHeader     = nil
local _raidCreated    = false
local _currentMode    = "solo"
local _layoutDeferred = false
local _initialized    = false
local _eventsActive   = false
local _blizzHidden    = false

-- Preview fake data (20 units for raid, first 4 for party)
local PREVIEW = {
    { name = "Thrällbringer",    hp = 0.85, pwr = 0.70, cls = "SHAMAN",      pType = "MANA",   effect = nil,            hpDir = -1 },
    { name = "Jaina Proudmoore", hp = 0.38, pwr = 0.45, cls = "MAGE",        pType = "MANA",   effect = "dispel_Magic", hpDir = 1 },
    { name = "Anduin Wrynn",     hp = 0.93, pwr = 0.88, cls = "PRIEST",      pType = "MANA",   effect = nil,            hpDir = -1 },
    { name = "Sylvanas",         hp = 0.17, pwr = 0.33, cls = "HUNTER",      pType = "FOCUS",  effect = "aggro",        hpDir = 1 },
    { name = "Tirion",           hp = 0.72, pwr = 0.60, cls = "PALADIN",     pType = "MANA",   effect = nil,            hpDir = -1 },
    { name = "Garrosh",          hp = 0.55, pwr = 0.80, cls = "WARRIOR",     pType = "RAGE",   effect = nil,            hpDir = 1 },
    { name = "Valeera",          hp = 0.44, pwr = 0.90, cls = "ROGUE",       pType = "ENERGY", effect = nil,            hpDir = -1 },
    { name = "Malfurion",        hp = 0.68, pwr = 0.55, cls = "DRUID",       pType = "MANA",   effect = nil,            hpDir = 1 },
    { name = "Khadgar",          hp = 0.81, pwr = 0.30, cls = "MAGE",        pType = "MANA",   effect = nil,            hpDir = -1 },
    { name = "Uther",            hp = 0.60, pwr = 0.75, cls = "PALADIN",     pType = "MANA",   effect = "dispel_Curse", hpDir = 1 },
    { name = "Vol'jin",          hp = 0.33, pwr = 0.40, cls = "SHAMAN",      pType = "MANA",   effect = nil,            hpDir = 1 },
    { name = "Illidan",          hp = 0.50, pwr = 0.65, cls = "DEMONHUNTER", pType = "FURY",   effect = nil,            hpDir = -1 },
    { name = "Tyrande",          hp = 0.77, pwr = 0.50, cls = "PRIEST",      pType = "MANA",   effect = nil,            hpDir = 1 },
    { name = "Chen Stormstout",  hp = 0.88, pwr = 0.85, cls = "MONK",        pType = "ENERGY", effect = nil,            hpDir = -1 },
    { name = "Gul'dan",          hp = 0.25, pwr = 0.95, cls = "WARLOCK",     pType = "MANA",   effect = "aggro",        hpDir = 1 },
    { name = "Rexxar",           hp = 0.62, pwr = 0.20, cls = "HUNTER",      pType = "FOCUS",  effect = nil,            hpDir = -1 },
    { name = "Aggra",            hp = 0.90, pwr = 0.70, cls = "SHAMAN",      pType = "MANA",   effect = nil,            hpDir = 1 },
    { name = "Chromie",          hp = 0.45, pwr = 0.60, cls = "MAGE",        pType = "MANA",   effect = nil,            hpDir = -1 },
    { name = "Lothraxion",       hp = 0.70, pwr = 0.80, cls = "PALADIN",     pType = "MANA",   effect = "dispel_Poison",hpDir = 1 },
    { name = "Saurfang",         hp = 0.15, pwr = 0.50, cls = "WARRIOR",     pType = "RAGE",   effect = "aggro",        hpDir = 1 },
}
local PREVIEW_CLASS_COLORS = {
    SHAMAN      = { 0.00, 0.44, 0.87 }, MAGE    = { 0.25, 0.78, 0.92 },
    PRIEST      = { 1.00, 1.00, 1.00 }, HUNTER  = { 0.67, 0.83, 0.45 },
    WARRIOR     = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
    ROGUE       = { 1.00, 0.96, 0.41 }, DRUID   = { 1.00, 0.49, 0.04 },
    WARLOCK     = { 0.53, 0.53, 0.93 }, MONK    = { 0.00, 1.00, 0.60 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    EVOKER      = { 0.20, 0.58, 0.50 },
}
local PREVIEW_POWER_COLORS = {
    MANA = { 0.00, 0.44, 0.87 }, RAGE   = { 0.77, 0.12, 0.23 },
    ENERGY = { 1.00, 1.00, 0.00 }, FOCUS = { 0.71, 0.43, 0.27 },
    FURY = { 0.64, 0.19, 0.79 },
}
local PREVIEW_DISPEL_COLORS = {
    dispel_Magic   = { 0.20, 0.60, 1.00 }, dispel_Curse   = { 0.60, 0.00, 1.00 },
    dispel_Disease = { 0.60, 0.40, 0.00 }, dispel_Poison  = { 0.00, 0.60, 0.00 },
}

-- PERF: Hoisted backdrop spec (no table alloc in preview border creation)
local GF_BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 }

-- ═══════════════════════════════════════════════════════════════
-- Animation State (file-scope, single ticker for all preview frames)
-- ═══════════════════════════════════════════════════════════════
local _animFrames = {}   -- { frame, dataIndex } pairs
local _animTicker = nil
local _animAcc    = 0
local ANIM_RATE   = 0.05  -- 20 fps for smooth bars
local ANIM_SPEED  = 0.08  -- HP change per tick

local function AnimTick(_, elapsed)
    _animAcc = _animAcc + elapsed
    if _animAcc < ANIM_RATE then return end
    _animAcc = 0

    for k = 1, #_animFrames do
        local entry = _animFrames[k]
        local f = entry[1]
        local di = entry[2]
        if f and f:IsShown() and f._msufGFPreviewActive then
            local data = PREVIEW[di]
            if data then
                -- Animate HP
                local cur = f._msufGFAnimHP or data.hp
                cur = cur + data.hpDir * ANIM_SPEED
                if cur > 0.95 then cur = 0.95; data.hpDir = -1 end
                if cur < 0.10 then cur = 0.10; data.hpDir = 1 end
                f._msufGFAnimHP = cur

                if f.hpBar then
                    f.hpBar:SetValue(cur)
                end
                if f.hpText and f.hpText:IsShown() then
                    f.hpText:SetText(math_floor(cur * 100 + 0.5) .. "%")
                end
            end
        end
    end
end

local function StartAnim()
    if _animTicker then return end
    _animTicker = CreateFrame("Frame")
    _animAcc = 0
    _animTicker:SetScript("OnUpdate", AnimTick)
end

local function StopAnim()
    if _animTicker then
        _animTicker:SetScript("OnUpdate", nil)
        _animTicker = nil
    end
    for k = 1, #_animFrames do _animFrames[k] = nil end
end

local function RegisterAnimFrame(f, dataIndex)
    _animFrames[#_animFrames + 1] = { f, dataIndex }
end

-- ═══════════════════════════════════════════════════════════════
-- Forward declarations
-- ═══════════════════════════════════════════════════════════════
local GF_CreatePartyFrame, GF_InitRaidChildFrame
local GF_LayoutPartyFrames, GF_LayoutRaidFrames
local GF_ShowPartyFrames, GF_HidePartyFrames
local GF_ShowRaidFrames, GF_HideRaidFrames
local GF_DetermineMode, GF_OnRosterUpdate
local GF_InjectDBConfigs, GF_InvalidateGFFrameCaches, GF_MarkFrameDirty
local GF_HideBlizzardFrames, GF_RestoreBlizzardFrames
local GF_ApplyPreviewData, GF_ClearPreviewData

-- ═══════════════════════════════════════════════════════════════
-- Config Injection + Cache Invalidation
-- ═══════════════════════════════════════════════════════════════
GF_InjectDBConfigs = function()
    GF.RebuildVirtualConfigs()
    local db = _G.MSUF_DB
    if not db then return end
    db.gf_party = GF.GetVirtualPartyConf()
    db.gf_raid  = GF.GetVirtualRaidConf()
end

GF_InvalidateGFFrameCaches = function()
    for i = 1, 4 do
        local f = _partyFrames[i]
        if f then f.cachedConfig = nil end
    end
    if _raidHeader then
        local idx = 1
        while true do
            local cf = select(idx, _raidHeader:GetChildren())
            if not cf then break end
            if cf._msufIsGroupFrame then cf.cachedConfig = nil end
            idx = idx + 1
        end
    end
end

GF_MarkFrameDirty = function(f)
    if not f then return end
    local attachFn = _G.MSUF_UFCore_AttachFrame
    if type(attachFn) == "function" then
        attachFn(f)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Preview Data System
-- ═══════════════════════════════════════════════════════════════
GF_ApplyPreviewData = function(f, index)
    if not f then return end
    local i = ((index - 1) % #PREVIEW) + 1
    local data = PREVIEW[i]
    if not data then return end

    local conf = (f._msufGFMode == "raid") and GF.GetRaidConf() or GF.GetPartyConf()
    local clr  = PREVIEW_CLASS_COLORS[data.cls] or { 0.8, 0.8, 0.8 }
    local pClr = PREVIEW_POWER_COLORS[data.pType] or PREVIEW_POWER_COLORS.MANA

    -- Store preview class bar color for ApplyBarColor "class" mode restore
    f._msufGFPreviewBarR = clr[1]
    f._msufGFPreviewBarG = clr[2]
    f._msufGFPreviewBarB = clr[3]

    -- ── Bar Texture (from override resolution) ──────────────
    local barTex
    if type(GF.ApplyBarTexture) == "function" then
        GF.ApplyBarTexture(f)
    end

    -- ── HP Bar ──────────────────────────────────────────────
    if f.hpBar then
        f.hpBar:SetMinMaxValues(0, 1)
        f.hpBar:SetValue(data.hp)
        f.hpBar.MSUF_lastValue = data.hp
        -- Color: use class color (matches main UF "class" bar mode)
        f.hpBar:SetStatusBarColor(clr[1], clr[2], clr[3], 1)
    end

    -- ── HP Bar Background ───────────────────────────────────
    if type(GF.ApplyBarBackground) == "function" then
        GF.ApplyBarBackground(f)
    end

    -- ── Power Bar ───────────────────────────────────────────
    if f.targetPowerBar then
        if conf and conf.showPower ~= false then
            f.targetPowerBar:SetMinMaxValues(0, 1)
            f.targetPowerBar:SetValue(data.pwr)
            f.targetPowerBar.MSUF_lastValue = data.pwr
            f.targetPowerBar:SetStatusBarColor(pClr[1], pClr[2], pClr[3], 1)
            f.targetPowerBar:SetHeight(conf.powerBarHeight or 3)
            f.targetPowerBar:Show()
        else
            f.targetPowerBar:Hide()
        end
    end

    -- ── Font settings (from override resolution) ────────────
    -- ApplyFonts handles: font path, size, bold, outline, text backdrop,
    -- class coloring, shadow — all override-aware.
    -- But for preview we need to set name text AFTER ApplyFonts.
    if type(GF.ApplyFonts) == "function" then
        -- Temporarily mark as not-preview so ApplyFonts doesn't skip color
        f._msufGFPreviewActive = nil
        GF.ApplyFonts(f)
    end
    f._msufGFPreviewActive = true

    -- ── Name Text ───────────────────────────────────────────
    if f.nameText then
        local showName = (conf and conf.showName ~= false)
        if showName then
            f.nameText:SetText(data.name)
            -- Class color for preview names (if nameClassColor enabled)
            local nameClassColor = GF.ResolveFont(conf, "nameClassColor")
            if nameClassColor == nil then
                local db = _G.MSUF_DB
                local g = db and db.general
                nameClassColor = g and g.nameClassColor
            end
            if nameClassColor then
                f.nameText:SetTextColor(clr[1], clr[2], clr[3], 1)
            end
            f.nameText:Show()
        else
            f.nameText:SetText("")
            f.nameText:Hide()
        end
    end

    -- ── Name Shortening ─────────────────────────────────────
    -- Invalidate diff-gates so ClampNameWidth actually runs
    f._msufClampStamp = nil
    f._msufNameClipAnchorStamp = nil
    f._msufNameClipTextStamp = nil
    if type(MSUF_ClampNameWidth) == "function" then
        local virtualConf = _G.MSUF_DB and _G.MSUF_DB[f.msufConfigKey]
        MSUF_ClampNameWidth(f, virtualConf or conf)
    end

    -- ── HP Text ─────────────────────────────────────────────
    if f.hpText then
        local showHP = (conf and conf.showHP ~= false)
        if showHP then
            f.hpText:SetText(math_floor(data.hp * 100 + 0.5) .. "%")
            f.hpText:Show()
        else
            f.hpText:SetText("")
            f.hpText:Hide()
        end
    end

    -- ── Background ──────────────────────────────────────────
    if f.bg then
        f.bg:SetVertexColor(0.08, 0.08, 0.12, 0.9)
    end

    -- ── Effect Borders (aggro / dispel preview) ─────────────
    local effect = data.effect
    if effect then
        -- Reuse shared EnsureBorder from GF_Effects via GF namespace
        local brd
        if f._msufGFBorder then
            brd = f._msufGFBorder
        else
            brd = CreateFrame("Frame", nil, f, "BackdropTemplate")
            brd:SetAllPoints(f)
            brd:SetFrameLevel(f:GetFrameLevel() + 10)
            brd:SetBackdrop(GF_BORDER_BACKDROP)
            f._msufGFBorder = brd
        end

        if effect == "aggro" then
            brd:SetBackdropBorderColor(1.00, 0.40, 0.00, 0.90)
        elseif PREVIEW_DISPEL_COLORS[effect] then
            local dc = PREVIEW_DISPEL_COLORS[effect]
            brd:SetBackdropBorderColor(dc[1], dc[2], dc[3], 0.85)
        end
        brd:Show()
        f._msufGFEffectState = effect
    else
        -- Clear border if no effect
        if f._msufGFBorder then
            f._msufGFBorder:Hide()
        end
        f._msufGFEffectState = nil
    end
end

GF_ClearPreviewData = function(f)
    if not f or not f._msufGFPreviewActive then return end
    f._msufGFPreviewActive = nil

    -- Reset bars
    if f.hpBar then
        f.hpBar:SetValue(0)
        f.hpBar.MSUF_lastValue = 0
    end
    if f.targetPowerBar then
        f.targetPowerBar:SetValue(0)
        f.targetPowerBar:Hide()
    end

    -- Reset text
    if f.nameText then f.nameText:SetText("") end
    if f.hpText then f.hpText:SetText("") end

    -- Reset border
    if f._msufGFBorder then f._msufGFBorder:Hide() end
    f._msufGFEffectState = nil
    f._msufGFPreviewBarR = nil
    f._msufGFPreviewBarG = nil
    f._msufGFPreviewBarB = nil

    -- Reset clamp caches
    f._msufClampStamp = nil
    f._msufNameClipAnchorStamp = nil
    f._msufNameClipTextStamp = nil
end

-- ═══════════════════════════════════════════════════════════════
-- Blizzard Frame Hiding
-- ═══════════════════════════════════════════════════════════════
GF_HideBlizzardFrames = function()
    if _blizzHidden then return end
    if InCombatLockdown() then return end
    _blizzHidden = true

    local pf = _G.PartyFrame
    if pf then
        if pf.UnregisterAllEvents then pf:UnregisterAllEvents() end
        if pf.Hide then pf:Hide() end
        if _G.RegisterStateDriver then
            _G.RegisterStateDriver(pf, "visibility", "hide")
        end
    end

    local crf = _G.CompactRaidFrameContainer
    if crf then
        if crf.UnregisterAllEvents then crf:UnregisterAllEvents() end
        if crf.Hide then crf:Hide() end
        if _G.RegisterStateDriver and crf.IsObjectType
            and crf:IsObjectType("Frame") then
            _G.RegisterStateDriver(crf, "visibility", "hide")
        end
    end

    local crfm = _G.CompactRaidFrameManager
    if crfm then
        if crfm.UnregisterAllEvents then crfm:UnregisterAllEvents() end
        if crfm.Hide then crfm:Hide() end
        if _G.RegisterStateDriver then
            _G.RegisterStateDriver(crfm, "visibility", "hide")
        end
    end
end

GF_RestoreBlizzardFrames = function()
    if not _blizzHidden then return end
    if InCombatLockdown() then return end
    _blizzHidden = false

    local pf = _G.PartyFrame
    if pf and _G.UnregisterStateDriver then
        _G.UnregisterStateDriver(pf, "visibility")
        if pf.Show then pf:Show() end
    end
    local crf = _G.CompactRaidFrameContainer
    if crf and _G.UnregisterStateDriver then
        _G.UnregisterStateDriver(crf, "visibility")
    end
    local crfm = _G.CompactRaidFrameManager
    if crfm and _G.UnregisterStateDriver then
        _G.UnregisterStateDriver(crfm, "visibility")
        if crfm.Show then crfm:Show() end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Party Frame Factory
-- ═══════════════════════════════════════════════════════════════
GF_CreatePartyFrame = function(index)
    local unit = "party" .. index
    local name = "MSUF_GF_Party" .. index

    local f = CreateFrame("Button", name, UIParent,
        "BackdropTemplate,SecureUnitButtonTemplate")
    f.unit           = unit
    f.msufConfigKey  = "gf_party"
    f._msufIsGroupFrame = true
    f._msufGFMode    = "party"
    f._msufGFIndex   = index

    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetClampedToScreen(true)

    local conf = GF.GetPartyConf()
    f:SetSize(conf.width or 120, conf.height or 36)

    do
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
        f.bg = bg
    end

    do
        local barTex = (type(_G.MSUF_GetBarTexture) == "function"
            and _G.MSUF_GetBarTexture())
            or "Interface\\TargetingFrame\\UI-StatusBar"

        local hpBar = CreateFrame("StatusBar", nil, f)
        hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        hpBar:SetStatusBarTexture(barTex)
        hpBar:SetMinMaxValues(0, 1)
        hpBar:SetValue(0)
        hpBar.MSUF_lastValue = 0
        hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
        f.hpBar = hpBar

        local hpBG = hpBar:CreateTexture(nil, "BACKGROUND")
        hpBG:SetAllPoints(hpBar)
        hpBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        hpBG:SetVertexColor(0, 0, 0, 0.9)
        f.hpBarBG = hpBG

        local pBar = CreateFrame("StatusBar", nil, f)
        pBar:SetHeight(conf.powerBarHeight or 3)
        pBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetStatusBarTexture(barTex)
        pBar:SetMinMaxValues(0, 1)
        pBar:SetValue(0)
        pBar.MSUF_lastValue = 0
        pBar:SetFrameLevel(hpBar:GetFrameLevel())
        pBar:Hide()
        f.targetPowerBar = pBar

        local pBG = pBar:CreateTexture(nil, "BACKGROUND")
        pBG:SetAllPoints(pBar)
        pBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        pBG:SetVertexColor(0, 0, 0, 0.9)
        f.powerBarBG = pBG
    end

    do
        local textFrame = CreateFrame("Frame", nil, f)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(f.hpBar:GetFrameLevel() + 3)
        f.textFrame = textFrame

        local nameText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", textFrame, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        f.nameText = nameText

        local hpText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hpText:SetPoint("RIGHT", textFrame, "RIGHT", -4, 0)
        hpText:SetJustifyH("RIGHT")
        f.hpText = hpText
    end

    f._msufAlphaSupportsLayered = true
    if ClickCastFrames then ClickCastFrames[f] = true end
    f:Hide()
    return f
end

-- ═══════════════════════════════════════════════════════════════
-- Ensure Party Frames
-- ═══════════════════════════════════════════════════════════════
local function GF_EnsurePartyFrames()
    if _partyCreated then return _partyFrames end
    for i = 1, 4 do
        _partyFrames[i] = GF_CreatePartyFrame(i)
    end
    _partyCreated = true

    local attachFn = _G.MSUF_UFCore_AttachFrame
    if type(attachFn) == "function" then
        for i = 1, 4 do attachFn(_partyFrames[i]) end
    end
    return _partyFrames
end

-- ═══════════════════════════════════════════════════════════════
-- Raid Init + Header (unchanged from v5)
-- ═══════════════════════════════════════════════════════════════
GF_InitRaidChildFrame = function(f)
    if not f or f._msufGFInited then return end
    f._msufGFInited      = true
    f._msufIsGroupFrame  = true
    f._msufGFMode        = "raid"
    f.msufConfigKey      = "gf_raid"
    local conf = GF.GetRaidConf()
    f:SetSize(conf.width or 72, conf.height or 30)

    do
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
        f.bg = bg
    end
    do
        local barTex = (type(_G.MSUF_GetBarTexture) == "function"
            and _G.MSUF_GetBarTexture())
            or "Interface\\TargetingFrame\\UI-StatusBar"
        local hpBar = CreateFrame("StatusBar", nil, f)
        hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        hpBar:SetStatusBarTexture(barTex)
        hpBar:SetMinMaxValues(0, 1); hpBar:SetValue(0); hpBar.MSUF_lastValue = 0
        hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
        f.hpBar = hpBar
        local hpBG = hpBar:CreateTexture(nil, "BACKGROUND")
        hpBG:SetAllPoints(hpBar)
        hpBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        hpBG:SetVertexColor(0, 0, 0, 0.9)
        f.hpBarBG = hpBG
        local pBar = CreateFrame("StatusBar", nil, f)
        pBar:SetHeight(conf.powerBarHeight or 2)
        pBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetStatusBarTexture(barTex)
        pBar:SetMinMaxValues(0, 1); pBar:SetValue(0); pBar.MSUF_lastValue = 0
        pBar:SetFrameLevel(hpBar:GetFrameLevel()); pBar:Hide()
        f.targetPowerBar = pBar
        local pBG = pBar:CreateTexture(nil, "BACKGROUND")
        pBG:SetAllPoints(pBar)
        pBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        pBG:SetVertexColor(0, 0, 0, 0.9)
        f.powerBarBG = pBG
    end
    do
        local textFrame = CreateFrame("Frame", nil, f)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(f.hpBar:GetFrameLevel() + 3)
        f.textFrame = textFrame
        local nameText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
        nameText:SetJustifyH("CENTER"); nameText:SetWordWrap(false)
        f.nameText = nameText
        local hpText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hpText:SetPoint("BOTTOM", textFrame, "BOTTOM", 0, 2)
        hpText:SetJustifyH("CENTER")
        f.hpText = hpText
    end
    f._msufAlphaSupportsLayered = true
    if ClickCastFrames then ClickCastFrames[f] = true end
    GF_MarkFrameDirty(f)
end

local function GF_EnsureRaidHeader()
    if _raidCreated then return _raidHeader end
    local conf = GF.GetRaidConf()
    local header = CreateFrame("Frame", "MSUF_GF_RaidHeader", UIParent,
        "SecureGroupHeaderTemplate")
    header:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate")
    header:SetAttribute("showRaid", true); header:SetAttribute("showParty", false)
    header:SetAttribute("showSolo", false); header:SetAttribute("showPlayer", true)
    header:SetAttribute("point", "TOP"); header:SetAttribute("xOffset", 0)
    header:SetAttribute("yOffset", -(conf.spacing or 2))
    header:SetAttribute("maxColumns", conf.maxColumns or 8)
    header:SetAttribute("unitsPerColumn", conf.unitsPerColumn or 5)
    header:SetAttribute("columnSpacing", conf.groupSpacing or 4)
    header:SetAttribute("columnAnchorPoint", "LEFT")
    header:SetAttribute("initialConfigFunction", [[
        self:SetWidth(72) self:SetHeight(30)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        self:RegisterForClicks("AnyUp")
    ]])
    header:SetPoint("CENTER", UIParent, "CENTER",
        conf.offsetX or -300, conf.offsetY or 100)
    header:Hide()
    _raidHeader = header; _raidCreated = true
    hooksecurefunc(header, "Show", function(self)
        local idx = 1
        while true do
            local cf = select(idx, self:GetChildren())
            if not cf then break end
            local u = cf.unit or (cf.GetAttribute and cf:GetAttribute("unit"))
            if u then cf.unit = u; GF_InitRaidChildFrame(cf) end
            idx = idx + 1
        end
    end)
    return header
end

-- ═══════════════════════════════════════════════════════════════
-- Layout
-- ═══════════════════════════════════════════════════════════════
GF_LayoutPartyFrames = function()
    if InCombatLockdown() then _layoutDeferred = true; return end
    local conf    = GF.GetPartyConf()
    local frames  = GF_EnsurePartyFrames()
    local w       = conf.width or 120
    local h       = conf.height or 36
    local spacing = conf.spacing or 2
    local dir     = conf.growDirection or "DOWN"
    local ax      = conf.offsetX or -200
    local ay      = conf.offsetY or 100
    for i = 1, 4 do
        local f = frames[i]
        if not f then break end
        f:SetSize(w, h)
        f:ClearAllPoints()
        local idx = i - 1
        if dir == "DOWN" then
            f:SetPoint("CENTER", UIParent, "CENTER", ax, ay - idx * (h + spacing))
        elseif dir == "UP" then
            f:SetPoint("CENTER", UIParent, "CENTER", ax, ay + idx * (h + spacing))
        elseif dir == "RIGHT" then
            f:SetPoint("CENTER", UIParent, "CENTER", ax + idx * (w + spacing), ay)
        elseif dir == "LEFT" then
            f:SetPoint("CENTER", UIParent, "CENTER", ax - idx * (w + spacing), ay)
        end
        if f.targetPowerBar then
            f.targetPowerBar:SetHeight(conf.powerBarHeight or 3)
            if conf.showPower ~= false then f.targetPowerBar:Show()
            else f.targetPowerBar:Hide() end
        end
    end
end

GF_LayoutRaidFrames = function()
    if InCombatLockdown() then _layoutDeferred = true; return end
    local header = GF_EnsureRaidHeader()
    if not header then return end
    local conf = GF.GetRaidConf()
    header:ClearAllPoints()
    header:SetPoint("CENTER", UIParent, "CENTER",
        conf.offsetX or -300, conf.offsetY or 100)
    header:SetAttribute("yOffset", -(conf.spacing or 2))
    header:SetAttribute("maxColumns", conf.maxColumns or 8)
    header:SetAttribute("unitsPerColumn", conf.unitsPerColumn or 5)
    header:SetAttribute("columnSpacing", conf.groupSpacing or 4)
end

-- ═══════════════════════════════════════════════════════════════
-- Show / Hide (with preview data)
-- ═══════════════════════════════════════════════════════════════
GF_ShowPartyFrames = function(numMembers, isPreview)
    if InCombatLockdown() then _layoutDeferred = true; return end
    GF_InjectDBConfigs()
    local frames = GF_EnsurePartyFrames()
    GF_LayoutPartyFrames()

    if isPreview then
        -- Clear old anim entries and register new ones
        for k = 1, #_animFrames do _animFrames[k] = nil end
    end
    local showCount = isPreview and 4 or (numMembers - 1)
    for i = 1, 4 do
        local f = frames[i]
        if not f then break end
        if i <= showCount then
            f.cachedConfig = nil
            f:Show()
            if isPreview then
                if type(GF.ApplyBarTexture) == "function" then GF.ApplyBarTexture(f) end
                if type(GF.ApplyBarBackground) == "function" then GF.ApplyBarBackground(f) end
                GF_ApplyPreviewData(f, i)
                RegisterAnimFrame(f, i)
            else
                GF_ClearPreviewData(f)
                GF_MarkFrameDirty(f)
                if type(GF.ApplyFrameVisuals) == "function" then
                    GF.ApplyFrameVisuals(f)
                end
            end
        else
            GF_ClearPreviewData(f)
            f:Hide()
        end
    end
    if isPreview then StartAnim() end
end

GF_HidePartyFrames = function()
    if InCombatLockdown() then _layoutDeferred = true; return end
    for i = 1, 4 do
        local f = _partyFrames[i]
        if f then GF_ClearPreviewData(f); f:Hide() end
    end
end

GF_ShowRaidFrames = function()
    if InCombatLockdown() then _layoutDeferred = true; return end
    GF_InjectDBConfigs()
    local header = GF_EnsureRaidHeader()
    if not header then return end
    GF_LayoutRaidFrames()
    header:Show()
end

GF_HideRaidFrames = function()
    if InCombatLockdown() then _layoutDeferred = true; return end
    if _raidHeader then _raidHeader:Hide() end
end

-- ═══════════════════════════════════════════════════════════════
-- Raid Preview (20 manual frames — SecureGroupHeader requires real units)
-- ═══════════════════════════════════════════════════════════════
local _raidPreviewFrames = {}
local _raidPreviewCreated = false

local function GF_CreateRaidPreviewFrame(index)
    local name = "MSUF_GF_RaidPreview" .. index
    local f = CreateFrame("Button", name, UIParent, "BackdropTemplate")
    f._msufIsGroupFrame = true
    f._msufGFMode    = "raid"
    f._msufGFIndex   = index
    f.msufConfigKey  = "gf_raid"
    f:SetClampedToScreen(true)

    local conf = GF.GetRaidConf()
    f:SetSize(conf.width or 72, conf.height or 30)

    do
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.08, 0.08, 0.12, 0.9)
        f.bg = bg
    end
    do
        local barTex = (type(_G.MSUF_GetBarTexture) == "function"
            and _G.MSUF_GetBarTexture())
            or "Interface\\TargetingFrame\\UI-StatusBar"
        local hpBar = CreateFrame("StatusBar", nil, f)
        hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        hpBar:SetStatusBarTexture(barTex)
        hpBar:SetMinMaxValues(0, 1); hpBar:SetValue(0)
        hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
        f.hpBar = hpBar
        local hpBG = hpBar:CreateTexture(nil, "BACKGROUND")
        hpBG:SetAllPoints(hpBar)
        hpBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        hpBG:SetVertexColor(0, 0, 0, 0.9)
        f.hpBarBG = hpBG
        local pBar = CreateFrame("StatusBar", nil, f)
        pBar:SetHeight(conf.powerBarHeight or 2)
        pBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetStatusBarTexture(barTex)
        pBar:SetMinMaxValues(0, 1); pBar:SetValue(0)
        pBar:SetFrameLevel(hpBar:GetFrameLevel())
        pBar:Hide()
        f.targetPowerBar = pBar
        local pBG = pBar:CreateTexture(nil, "BACKGROUND")
        pBG:SetAllPoints(pBar)
        pBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        pBG:SetVertexColor(0, 0, 0, 0.9)
        f.powerBarBG = pBG
    end
    do
        local textFrame = CreateFrame("Frame", nil, f)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(f.hpBar:GetFrameLevel() + 3)
        f.textFrame = textFrame
        local nameText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("CENTER", textFrame, "CENTER", 0, 2)
        nameText:SetJustifyH("CENTER"); nameText:SetWordWrap(false)
        f.nameText = nameText
        local hpText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hpText:SetPoint("BOTTOM", textFrame, "BOTTOM", 0, 1)
        hpText:SetJustifyH("CENTER")
        f.hpText = hpText
    end
    f:Hide()
    return f
end

local function GF_EnsureRaidPreviewFrames()
    if _raidPreviewCreated then return _raidPreviewFrames end
    for i = 1, 20 do
        _raidPreviewFrames[i] = GF_CreateRaidPreviewFrame(i)
    end
    _raidPreviewCreated = true
    _G.MSUF_GF_RaidPreviewFrames = _raidPreviewFrames
    return _raidPreviewFrames
end

local function GF_ShowRaidPreview()
    if InCombatLockdown() then return end
    GF_InjectDBConfigs()
    local frames = GF_EnsureRaidPreviewFrames()
    local conf   = GF.GetRaidConf()
    local w      = conf.width or 72
    local h      = conf.height or 30
    local sp     = conf.spacing or 2
    local upc    = conf.unitsPerColumn or 5
    local mc     = conf.maxColumns or 8
    local gs     = conf.groupSpacing or 4
    local ax     = conf.offsetX or -300
    local ay     = conf.offsetY or 100

    StopAnim()
    for k = 1, #_animFrames do _animFrames[k] = nil end

    for i = 1, 20 do
        local f = frames[i]
        f:SetSize(w, h)
        f:ClearAllPoints()
        local col = math_floor((i - 1) / upc)
        local row = (i - 1) % upc
        if col < mc then
            local fx = ax + col * (w + gs)
            local fy = ay - row * (h + sp)
            f:SetPoint("CENTER", UIParent, "CENTER", fx, fy)
            f:Show()
            if type(GF.ApplyBarTexture) == "function" then GF.ApplyBarTexture(f) end
            if type(GF.ApplyBarBackground) == "function" then GF.ApplyBarBackground(f) end
            GF_ApplyPreviewData(f, i)
        else
            f:Hide()
        end
    end
    StartAnim()
end

local function GF_HideRaidPreview()
    for i = 1, #_raidPreviewFrames do
        local f = _raidPreviewFrames[i]
        if f then GF_ClearPreviewData(f); f:Hide() end
    end
    StopAnim()
end

-- ═══════════════════════════════════════════════════════════════
-- Mode + Roster
-- ═══════════════════════════════════════════════════════════════
GF_DetermineMode = function()
    if not GF.IsEnabled() then return "solo" end
    local inRaid  = IsInRaid and IsInRaid()
    local inGroup = IsInGroup and IsInGroup()
    if inRaid and GF.IsRaidEnabled() then return "raid" end
    if inGroup and GF.IsPartyEnabled() then return "party" end
    return "solo"
end

GF_OnRosterUpdate = function()
    local newMode = GF_DetermineMode()
    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0

    -- Preview: separate flags for party + raid
    local editState = _G.MSUF_EditState
    local editActive = (type(editState) == "table" and editState.active == true)
    local partyPreview = editActive and (_G.MSUF_GF_PreviewPartyActive == true)
    local raidPreview  = editActive and (_G.MSUF_GF_PreviewRaidActive == true)

    -- Blizzard frames
    if GF.ShouldHideBlizzardFrames() then
        GF_HideBlizzardFrames()
    else
        GF_RestoreBlizzardFrames()
    end

    if newMode == "party" then
        GF_HideRaidFrames()
        GF_HideRaidPreview()
        GF_ShowPartyFrames(numMembers, false)
    elseif newMode == "raid" then
        GF_HidePartyFrames()
        GF_HideRaidPreview()
        GF_ShowRaidFrames()
    else
        -- Solo: show preview frames if toggled in Edit Mode
        if GF.IsEnabled() then
            if partyPreview then
                GF_HideRaidFrames()
                GF_HideRaidPreview()
                GF_ShowPartyFrames(5, true)
                StartAnim()
            else
                GF_HidePartyFrames()
            end
            if raidPreview then
                GF_ShowRaidPreview()
            else
                GF_HideRaidPreview()
            end
            if not partyPreview and not raidPreview then
                GF_HidePartyFrames()
                GF_HideRaidFrames()
                GF_HideRaidPreview()
                StopAnim()
            end
        else
            GF_HidePartyFrames()
            GF_HideRaidFrames()
            GF_HideRaidPreview()
            StopAnim()
        end
    end

    _currentMode = newMode
end

-- ═══════════════════════════════════════════════════════════════
-- Events
-- ═══════════════════════════════════════════════════════════════
local _eventFrame = nil

local function GF_OnEvent(_, event)
    if event == "GROUP_ROSTER_UPDATE" then
        GF_OnRosterUpdate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if _layoutDeferred then
            _layoutDeferred = false
            GF_OnRosterUpdate()
        end
        if GF.ShouldHideBlizzardFrames() and not _blizzHidden then
            GF_HideBlizzardFrames()
        end
    end
end

local function GF_RegisterEvents()
    if _eventsActive then return end
    if not _eventFrame then
        _eventFrame = CreateFrame("Frame")
        _eventFrame:SetScript("OnEvent", GF_OnEvent)
    end
    _eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    _eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _eventsActive = true
end

-- ═══════════════════════════════════════════════════════════════
-- Bootstrap
-- ═══════════════════════════════════════════════════════════════
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        GF.EnsureDB()
        if not GF.IsEnabled() then return end
        GF_InjectDBConfigs()
        if GF.ShouldHideBlizzardFrames() then GF_HideBlizzardFrames() end
        GF_RegisterEvents()
        GF_OnRosterUpdate()
        _initialized = true
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Edit Mode Hook
-- ═══════════════════════════════════════════════════════════════
do
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            hooksecurefunc("MSUF_SetMSUFEditModeDirect", function()
                local st = _G.MSUF_EditState
                local entering = (type(st) == "table" and st.active == true)
                if not entering then
                    _G.MSUF_GF_PreviewPartyActive = nil
                    _G.MSUF_GF_PreviewRaidActive  = nil
                    StopAnim()
                end
                if not GF.IsEnabled() then return end
                GF_RegisterEvents()
                GF_OnRosterUpdate()
            end)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Public API
-- ═══════════════════════════════════════════════════════════════
function GF.Refresh()
    GF.EnsureDB()
    GF_InjectDBConfigs()
    GF_InvalidateGFFrameCaches()
    -- Ensure effect events are registered if GF was enabled after login
    if GF.IsEnabled() and type(GF.RegisterEffectEvents) == "function" then
        GF.RegisterEffectEvents()
    end
    GF_OnRosterUpdate()
end

function GF.GetMode()           return _currentMode end
function GF.GetPartyFrame(i)    return _partyFrames[i] end
function GF.GetPartyFrames()    return _partyFrames end
function GF.GetRaidHeader()     return _raidHeader end

function GF.Relayout()
    GF_InjectDBConfigs()
    GF_InvalidateGFFrameCaches()
    if _currentMode == "party" then GF_LayoutPartyFrames()
    elseif _currentMode == "raid" then GF_LayoutRaidFrames() end
    for i = 1, 4 do
        local f = _partyFrames[i]
        if f and f:IsShown() then
            if f._msufGFPreviewActive then
                GF_ApplyPreviewData(f, i)
            else
                GF_MarkFrameDirty(f)
            end
            if type(GF.ApplyFrameVisuals) == "function" then
                GF.ApplyFrameVisuals(f)
            end
        end
    end
end

_G.MSUF_GF = GF
_G.MSUF_GF_Refresh  = GF.Refresh
_G.MSUF_GF_Relayout = GF.Relayout
_G.MSUF_GF_ReapplyPreview = function(f, idx)
    if not f then return end
    local i = ((idx - 1) % #PREVIEW) + 1
    GF_ApplyPreviewData(f, i)
end
