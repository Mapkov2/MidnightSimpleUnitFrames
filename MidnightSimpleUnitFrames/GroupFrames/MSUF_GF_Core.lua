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

-- Preview fake data
local PREVIEW_NAMES  = { "Thrall", "Jaina", "Anduin", "Sylvanas" }
local PREVIEW_HP     = { 0.85, 0.62, 0.93, 0.41 }
local PREVIEW_POWER  = { 0.70, 0.45, 0.88, 0.33 }
local PREVIEW_CLASS  = { "SHAMAN", "MAGE", "PRIEST", "HUNTER" }
local PREVIEW_COLORS = {
    SHAMAN  = { 0.00, 0.44, 0.87 },
    MAGE    = { 0.25, 0.78, 0.92 },
    PRIEST  = { 1.00, 1.00, 1.00 },
    HUNTER  = { 0.67, 0.83, 0.45 },
}

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
    local i = ((index - 1) % 4) + 1

    local name = PREVIEW_NAMES[i] or ("Party" .. i)
    local hp   = PREVIEW_HP[i] or 0.75
    local pwr  = PREVIEW_POWER[i] or 0.50
    local cls  = PREVIEW_CLASS[i] or "WARRIOR"
    local clr  = PREVIEW_COLORS[cls] or { 0.8, 0.8, 0.8 }

    -- HP bar
    if f.hpBar then
        f.hpBar:SetMinMaxValues(0, 1)
        f.hpBar:SetValue(hp)
        f.hpBar.MSUF_lastValue = hp
        f.hpBar:SetStatusBarColor(clr[1], clr[2], clr[3], 1)
    end

    -- Power bar
    if f.targetPowerBar then
        local conf = GF.GetPartyConf()
        if conf and conf.showPower ~= false then
            f.targetPowerBar:SetMinMaxValues(0, 1)
            f.targetPowerBar:SetValue(pwr)
            f.targetPowerBar.MSUF_lastValue = pwr
            f.targetPowerBar:SetStatusBarColor(0.0, 0.44, 0.87, 1)
            f.targetPowerBar:Show()
        else
            f.targetPowerBar:Hide()
        end
    end

    -- Name text
    if f.nameText then
        f.nameText:SetText(name)
        f.nameText:SetTextColor(clr[1], clr[2], clr[3], 1)
        local conf = GF.GetPartyConf()
        if conf and conf.showName ~= false then
            f.nameText:Show()
        else
            f.nameText:Hide()
        end
    end

    -- HP text
    if f.hpText then
        local conf = GF.GetPartyConf()
        if conf and conf.showHP ~= false then
            f.hpText:SetText(math_floor(hp * 100 + 0.5) .. "%")
            f.hpText:SetTextColor(1, 1, 1, 0.9)
            f.hpText:Show()
        else
            f.hpText:SetText("")
            f.hpText:Hide()
        end
    end

    -- Background
    if f.bg then
        f.bg:SetVertexColor(0.08, 0.08, 0.12, 0.9)
    end

    f._msufGFPreviewActive = true
end

GF_ClearPreviewData = function(f)
    if not f or not f._msufGFPreviewActive then return end
    f._msufGFPreviewActive = nil
    if f.hpBar then
        f.hpBar:SetValue(0)
        f.hpBar.MSUF_lastValue = 0
    end
    if f.targetPowerBar then
        f.targetPowerBar:SetValue(0)
        f.targetPowerBar:Hide()
    end
    if f.nameText then f.nameText:SetText("") end
    if f.hpText then f.hpText:SetText("") end
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

    local showCount = isPreview and 4 or (numMembers - 1)
    for i = 1, 4 do
        local f = frames[i]
        if not f then break end
        if i <= showCount then
            f.cachedConfig = nil
            f:Show()
            if isPreview then
                GF_ApplyPreviewData(f, i)
            else
                GF_ClearPreviewData(f)
                GF_MarkFrameDirty(f)
            end
        else
            GF_ClearPreviewData(f)
            f:Hide()
        end
    end
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

    -- Preview: toggled by HUD "GF" button (MSUF_GF_PreviewActive)
    -- Only when Edit Mode is also active
    local editActive = (type(_G.MSUF_IsMSUFEditModeActive) == "function"
        and _G.MSUF_IsMSUFEditModeActive())
    local previewWanted = editActive and (_G.MSUF_GF_PreviewActive == true)

    -- Blizzard frames
    if GF.ShouldHideBlizzardFrames() then
        GF_HideBlizzardFrames()
    else
        GF_RestoreBlizzardFrames()
    end

    if newMode == "party" then
        GF_HideRaidFrames()
        GF_ShowPartyFrames(numMembers, false)
    elseif newMode == "raid" then
        GF_HidePartyFrames()
        GF_ShowRaidFrames()
    else
        -- Solo
        if previewWanted and GF.IsEnabled() then
            GF_HideRaidFrames()
            if GF.IsPartyEnabled() then
                GF_ShowPartyFrames(5, true)  -- preview mode: 4 frames with fake data
            end
        else
            GF_HidePartyFrames()
            GF_HideRaidFrames()
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
    GF_InjectDBConfigs()
    GF_InvalidateGFFrameCaches()
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
    -- Re-dirty visible frames
    for i = 1, 4 do
        local f = _partyFrames[i]
        if f and f:IsShown() then
            if f._msufGFPreviewActive then
                GF_ApplyPreviewData(f, i)
            else
                GF_MarkFrameDirty(f)
            end
        end
    end
end

_G.MSUF_GF = GF
_G.MSUF_GF_Refresh  = GF.Refresh
_G.MSUF_GF_Relayout = GF.Relayout
