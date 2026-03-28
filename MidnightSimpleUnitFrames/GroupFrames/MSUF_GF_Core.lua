-- MSUF_GF_Core.lua — Group Frames core: factory, layout, preview, hiding
-- Phase 1: Party + Raid frame creation with EQoL-pattern hierarchy
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF or {}
ns.GF = GF

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local IsInRaid = _G.IsInRaid
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetNumSubgroupMembers = _G.GetNumSubgroupMembers
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local UnitClass = _G.UnitClass
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitPowerType = _G.UnitPowerType
local UnitName = _G.UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local GetRaidRosterInfo = _G.GetRaidRosterInfo
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local hooksecurefunc = _G.hooksecurefunc
local C_Timer = _G.C_Timer
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local PowerBarColor = _G.PowerBarColor
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local pairs = pairs
local type = type
local tostring = tostring
local select = select

------------------------------------------------------------------------
-- Hidden parent for Blizzard frame hiding
------------------------------------------------------------------------
local _hiddenParent
local function GetHiddenParent()
    if not _hiddenParent then
        _hiddenParent = CreateFrame("Frame", nil, UIParent)
        _hiddenParent:SetAllPoints(UIParent)
        _hiddenParent:Hide()
    end
    return _hiddenParent
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
GF.headers     = GF.headers or {}     -- party/raid SecureGroupHeaders
GF.anchors     = GF.anchors or {}     -- anchor frames
GF.frames      = GF.frames or {}      -- all built unit buttons

-- Cross-system frame registry (A2, EM2, etc. resolve unit→frame via this table)
if type(_G.MSUF_UnitFrames) ~= "table" then _G.MSUF_UnitFrames = {} end
GF._eventFrame = GF._eventFrame or nil
GF._previewActive = GF._previewActive or {}

------------------------------------------------------------------------
-- Forward declarations (Phase 2+ stubs)
------------------------------------------------------------------------
local function noop() end
GF.RegisterUnitEvents = GF.RegisterUnitEvents or noop
GF.UnregisterUnitEvents = GF.UnregisterUnitEvents or noop

------------------------------------------------------------------------
-- Frame hierarchy builder (EQoL pattern)
------------------------------------------------------------------------
local function BuildFrameHierarchy(f, kind)
    if f._msufGFBuilt then return end
    f._msufGFBuilt = true

    local conf = GF.GetConf(kind)
    local w = conf.width  or 120
    local h = conf.height or 40
    local powerH = conf.powerHeight or 6
    local inset  = ((conf.borderEnabled == true) and math_max(1, conf.borderSize or 1)) or 1

    -- barGroup — visual container (bgFile-only, EQoL pattern)
    -- Edge tiling on SetAllPoints frames causes TexCoord crash during
    -- SecureGroupHeader reposition (0-dimension transient). Border on separate frame.
    local barGroup = CreateFrame("Frame", nil, f, "BackdropTemplate")
    barGroup:SetAllPoints(f)
    barGroup:EnableMouse(false)
    f.barGroup = barGroup

    barGroup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    barGroup:SetBackdropColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)

    -- Separate border frame (2-point anchored, never SetAllPoints)
    local borderFrame = CreateFrame("Frame", nil, barGroup, "BackdropTemplate")
    borderFrame:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, 0)
    borderFrame:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", 0, 0)
    borderFrame:SetFrameLevel(barGroup:GetFrameLevel() + 1)
    borderFrame:EnableMouse(false)
    f._msufGFBorderFrame = borderFrame
    if conf.borderEnabled then
        local edgeSz = math_max(1, conf.borderSize or 1)
        borderFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = edgeSz })
        borderFrame:SetBackdropColor(0, 0, 0, 0)
        borderFrame:SetBackdropBorderColor(conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1)
    else
        borderFrame:SetBackdrop(nil)
        borderFrame:Hide()
    end

    -- Health StatusBar
    local health = CreateFrame("StatusBar", nil, barGroup)
    health:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)
    health:SetPoint("TOPLEFT", barGroup, "TOPLEFT", inset, -inset)
    health:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", -inset, powerH > 0 and (powerH + inset) or inset)
    f.health = health

    -- Health bar background
    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    healthBg:SetTexture(GF.ResolveBarBgTexture(kind))
    healthBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f.healthBg = healthBg

    -- Health prediction overlays (children of health, below text layer)
    local hLvl = health:GetFrameLevel()

    local incomingHealBar = CreateFrame("StatusBar", nil, health)
    incomingHealBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    incomingHealBar:SetMinMaxValues(0, 1)
    incomingHealBar:SetValue(0)
    incomingHealBar:SetAllPoints(health)
    incomingHealBar:SetFrameLevel(hLvl + 1)
    incomingHealBar:Hide()
    f.incomingHealBar = incomingHealBar

    local absorbBar = CreateFrame("StatusBar", nil, health)
    absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:SetAllPoints(health)
    absorbBar:SetFrameLevel(hLvl + 2)
    absorbBar:Hide()
    f.absorbBar = absorbBar

    local healAbsorbBar = CreateFrame("StatusBar", nil, health)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:SetAllPoints(health)
    healAbsorbBar:SetFrameLevel(hLvl + 3)
    healAbsorbBar:Hide()
    f.healAbsorbBar = healAbsorbBar

    -- Health text layer (above all overlays)
    local healthTextLayer = CreateFrame("Frame", nil, health)
    healthTextLayer:SetAllPoints(health)
    healthTextLayer:SetFrameLevel(hLvl + 5)
    f.healthTextLayer = healthTextLayer

    -- Name text
    local nameText = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetJustifyH("LEFT")
    f.nameText = nameText
    f.name = nameText

    -- 3-slot health text: left / center / right
    local textLeftFS = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textLeftFS:SetJustifyH("LEFT")
    textLeftFS:SetText("")
    f.textLeftFS = textLeftFS

    local textCenterFS = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textCenterFS:SetJustifyH("CENTER")
    textCenterFS:SetText("")
    f.textCenterFS = textCenterFS

    local textRightFS = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textRightFS:SetJustifyH("RIGHT")
    textRightFS:SetText("")
    f.textRightFS = textRightFS
    f.hpText = textRightFS  -- backward compat alias

    -- Status text (OFFLINE / DEAD / GHOST — white; AFK / DND — red via GF pipeline)
    local statusText = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetJustifyH("CENTER")
    statusText:SetTextColor(1, 1, 1, 1)
    statusText:SetText("")
    statusText:Hide()
    f.statusIndicatorText = statusText -- bridge to main MSUF status pipeline
    f._msufGFStatusText = statusText   -- GF-owned reference

    -- Group number text (raid subgroup)
    local groupNumText = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupNumText:SetJustifyH("RIGHT")
    groupNumText:SetText("")
    groupNumText:Hide()
    f.groupNumberText = groupNumText

    -- Power StatusBar
    local power = CreateFrame("StatusBar", nil, barGroup)
    power:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    power:SetMinMaxValues(0, 1)
    power:SetValue(1)
    if powerH > 0 then
        power:SetPoint("BOTTOMLEFT", barGroup, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(powerH)
        power:Show()
    else
        power:SetPoint("BOTTOMLEFT", barGroup, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(0.001)
        power:Hide()
    end
    f.power = power

    -- Power bar background
    local powerBg = power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(power)
    powerBg:SetTexture(GF.ResolveBarBgTexture(kind))
    powerBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f.powerBg = powerBg

    -- Power text layer
    local powerTextLayer = CreateFrame("Frame", nil, power)
    powerTextLayer:SetAllPoints(power)
    powerTextLayer:SetFrameLevel(power:GetFrameLevel() + 2)
    f.powerTextLayer = powerTextLayer

    -- 3-slot power text: left / center / right
    local powerTextLeftFS = powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerTextLeftFS:SetJustifyH("LEFT")
    powerTextLeftFS:SetText("")
    f.powerTextLeftFS = powerTextLeftFS

    local powerTextCenterFS = powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerTextCenterFS:SetJustifyH("CENTER")
    powerTextCenterFS:SetText("")
    f.powerTextCenterFS = powerTextCenterFS

    local powerTextRightFS = powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerTextRightFS:SetJustifyH("RIGHT")
    powerTextRightFS:SetText("")
    f.powerTextRightFS = powerTextRightFS
    f.powerText = powerTextCenterFS  -- backward compat alias

    -- Status icon layer (OVERLAY sublevel 7)
    local statusIconLayer = CreateFrame("Frame", nil, barGroup)
    statusIconLayer:SetAllPoints(barGroup)
    statusIconLayer:SetFrameLevel(barGroup:GetFrameLevel() + 5)
    statusIconLayer:EnableMouse(false)
    f.statusIconLayer = statusIconLayer

    -- Role icon
    local roleIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    roleIcon:SetSize(conf.roleIconSize or 12, conf.roleIconSize or 12)
    roleIcon:Hide()
    f.roleIcon = roleIcon

    -- Raid target icon
    local raidIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:SetSize(conf.raidMarkerSize or 14, conf.raidMarkerSize or 14)
    raidIcon:Hide()
    f.raidIcon = raidIcon

    -- Leader icon
    local leaderIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    leaderIcon:SetSize(conf.leaderIconSize or 12, conf.leaderIconSize or 12)
    leaderIcon:Hide()
    f.leaderIcon = leaderIcon

    -- Assist icon
    local assistIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    assistIcon:SetSize(conf.assistIconSize or 12, conf.assistIconSize or 12)
    assistIcon:Hide()
    f.assistIcon = assistIcon

    -- Ready check icon
    local readyCheckIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
    readyCheckIcon:SetSize(conf.readyCheckSize or 16, conf.readyCheckSize or 16)
    readyCheckIcon:Hide()
    f.readyCheckIcon = readyCheckIcon

    -- Summon icon
    local summonIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    summonIcon:SetSize(conf.summonIconSize or 16, conf.summonIconSize or 16)
    summonIcon:Hide()
    f.summonIcon = summonIcon

    -- Resurrect icon
    local resurrectIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    resurrectIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    resurrectIcon:SetSize(conf.resurrectIconSize or 16, conf.resurrectIconSize or 16)
    resurrectIcon:Hide()
    f.resurrectIcon = resurrectIcon

    -- Phase icon
    local phaseIcon = statusIconLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    phaseIcon:SetSize(conf.phaseIconSize or 14, conf.phaseIconSize or 14)
    phaseIcon:Hide()
    f.phaseIcon = phaseIcon

    -- Unified highlight border (aggro/dispel/target — priority pipeline like main UF)
    local hlBorder = CreateFrame("Frame", nil, barGroup, "BackdropTemplate")
    hlBorder:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, 0)
    hlBorder:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", 0, 0)
    hlBorder:SetFrameLevel(barGroup:GetFrameLevel() + 3)
    hlBorder:EnableMouse(false)
    hlBorder:Hide()
    f._msufGFHighlightBorder = hlBorder

    -- ClickCast integration
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    _G.ClickCastFrames[f] = true

    -- Unit menu
    f.menu = function(btn)
        if btn.unit and UnitExists(btn.unit) then
            local which = "PARTY"
            if _G.IsInRaid and _G.IsInRaid() then which = "RAID_PLAYER" end
            if UnitPopup_ShowMenu then
                UnitPopup_ShowMenu(btn, which, btn.unit, UnitName(btn.unit))
            end
        end
    end
end

------------------------------------------------------------------------
-- Apply fonts to a GF frame
------------------------------------------------------------------------
local function ApplyFonts(f, kind)
    local conf = GF.GetConf(kind)
    local fontPath  = GF.ResolveFontPath(kind)
    local fontFlags = GF.ResolveFontFlags(kind)
    local fr, fg, fb = GF.ResolveFontColor(kind)
    local nameSize  = conf.nameFontSize or 12
    local hpSize    = conf.hpFontSize or 10
    local powSize   = conf.powerFontSize or 9

    if f.nameText then
        f.nameText:SetFont(fontPath, nameSize, fontFlags)
        -- Name color applied dynamically per-unit in dispatchName/UpdateButton
        f.nameText:SetTextColor(fr, fg, fb, 1)
    end
    if f.textLeftFS then
        f.textLeftFS:SetFont(fontPath, hpSize, fontFlags)
        f.textLeftFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.textCenterFS then
        f.textCenterFS:SetFont(fontPath, hpSize, fontFlags)
        f.textCenterFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.textRightFS then
        f.textRightFS:SetFont(fontPath, hpSize, fontFlags)
        f.textRightFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.statusIndicatorText then
        f.statusIndicatorText:SetFont(fontPath, nameSize + 2, fontFlags)
    end
    if f.powerTextLeftFS then
        f.powerTextLeftFS:SetFont(fontPath, powSize, fontFlags)
        f.powerTextLeftFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.powerTextCenterFS then
        f.powerTextCenterFS:SetFont(fontPath, powSize, fontFlags)
        f.powerTextCenterFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.powerTextRightFS then
        f.powerTextRightFS:SetFont(fontPath, powSize, fontFlags)
        f.powerTextRightFS:SetTextColor(fr, fg, fb, 0.9)
    end
end

------------------------------------------------------------------------
-- Layout text elements within a GF frame
------------------------------------------------------------------------
local function LayoutText(f, kind)
    local conf = GF.GetConf(kind)
    if f.nameText then
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("LEFT", f.health, "LEFT", 3, 0)
        f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -3, 0)
        f.nameText:SetWordWrap(false)
        if conf.showName ~= false then f.nameText:Show() else f.nameText:Hide() end
    end
    -- 3-slot health text
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"
    if f.textLeftFS then
        f.textLeftFS:ClearAllPoints()
        f.textLeftFS:SetPoint("LEFT", f.health, "LEFT", 3, 0)
        if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
    end
    if f.textCenterFS then
        f.textCenterFS:ClearAllPoints()
        f.textCenterFS:SetPoint("CENTER", f.health, "CENTER", 0, 0)
        if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
    end
    if f.textRightFS then
        f.textRightFS:ClearAllPoints()
        f.textRightFS:SetPoint("RIGHT", f.health, "RIGHT", -3, 0)
        if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:Hide() end
    end
    if f.statusIndicatorText then
        f.statusIndicatorText:ClearAllPoints()
        f.statusIndicatorText:SetPoint("CENTER", f.health, "CENTER", 0, 0)
    end
    if f.powerTextLeftFS then
        f.powerTextLeftFS:ClearAllPoints()
        f.powerTextLeftFS:SetPoint("LEFT", f.power, "LEFT", 2, 0)
    end
    if f.powerTextCenterFS then
        f.powerTextCenterFS:ClearAllPoints()
        f.powerTextCenterFS:SetPoint("CENTER", f.power, "CENTER", 0, 0)
    end
    if f.powerTextRightFS then
        f.powerTextRightFS:ClearAllPoints()
        f.powerTextRightFS:SetPoint("RIGHT", f.power, "RIGHT", -2, 0)
    end
    do
        local showPow = conf.showPower and (conf.powerHeight or 6) > 0
        local ptl = showPow and (conf.powerTextLeft   or "NONE") or "NONE"
        local ptc = showPow and (conf.powerTextCenter  or "NONE") or "NONE"
        local ptr = showPow and (conf.powerTextRight   or "NONE") or "NONE"
        if f.powerTextLeftFS  then if ptl ~= "NONE" then f.powerTextLeftFS:Show()  else f.powerTextLeftFS:Hide()  end end
        if f.powerTextCenterFS then if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end end
        if f.powerTextRightFS then if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end end
    end
end

------------------------------------------------------------------------
-- Layout status icons
------------------------------------------------------------------------
local ROLE_TEXTURES = {
    TANK    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    HEALER  = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    DAMAGER = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
}
local ROLE_COORDS = {
    TANK    = { 0,    19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

local function LayoutIcons(f, kind)
    local conf = GF.GetConf(kind)
    local anchor = f.statusIconLayer or f.barGroup or f

    local function lay(icon, sizeKey, defSz, anchorKey, defPt, xKey, yKey)
        if not icon then return end
        icon:ClearAllPoints()
        local sz = conf[sizeKey] or defSz
        icon:SetSize(sz, sz)
        local pt = conf[anchorKey] or defPt
        icon:SetPoint(pt, anchor, pt, conf[xKey] or 0, conf[yKey] or 0)
    end

    lay(f.roleIcon,       "roleIconSize",      12, "roleIconAnchor",   "TOPLEFT",  "roleIconX",   "roleIconY")
    lay(f.leaderIcon,     "leaderIconSize",     12, "leaderIconAnchor", "TOPRIGHT", "leaderIconX", "leaderIconY")
    lay(f.assistIcon,     "assistIconSize",     12, "assistIconAnchor", "TOPRIGHT", "assistIconX", "assistIconY")
    lay(f.raidIcon,       "raidMarkerSize",     14, "raidMarkerAnchor", "CENTER",   "raidMarkerX", "raidMarkerY")
    lay(f.readyCheckIcon, "readyCheckSize",     16, "readyCheckAnchor", "CENTER",   "readyCheckX", "readyCheckY")
    lay(f.summonIcon,     "summonIconSize",     16, "summonAnchor",     "CENTER",   "summonX",     "summonY")
    lay(f.resurrectIcon,  "resurrectIconSize",  16, "resurrectAnchor",  "CENTER",   "resurrectX",  "resurrectY")
    lay(f.phaseIcon,      "phaseIconSize",      14, "phaseAnchor",      "TOPLEFT",  "phaseX",      "phaseY")
end

------------------------------------------------------------------------
-- Init a single unit button (post-creation, NOT in initialConfigFunction)
------------------------------------------------------------------------
local function GF_InitButton(f, kind)
    f._msufIsGroupFrame = true
    f._msufGFKind = kind
    f.msufConfigKey = (kind == "raid") and "gf_raid" or "gf_party"

    -- RegisterForClicks MUST happen here, NOT in initialConfigFunction
    if f.RegisterForClicks then
        f:RegisterForClicks("AnyUp")
    end

    BuildFrameHierarchy(f, kind)
    ApplyFonts(f, kind)
    LayoutText(f, kind)
    LayoutIcons(f, kind)

    -- Size hook
    if not f._msufGFSizeHooked then
        f._msufGFSizeHooked = true
        f:HookScript("OnSizeChanged", function(btn)
            LayoutText(btn, btn._msufGFKind or "party")
            LayoutIcons(btn, btn._msufGFKind or "party")
        end)
    end

    f:SetClampedToScreen(true)

    -- Track in frames list
    GF.frames[f] = kind
end

------------------------------------------------------------------------
-- Update health color for a GF frame
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit)
    if not f.health then return end
    -- Delegate to Render pipeline if available (respects global barMode)
    if GF.ApplyVisuals then
        GF.ApplyVisuals(f, 0x08) -- DIRTY_COLOR
        return
    end
    -- Fallback: basic class color
    local conf = GF.GetConf(kind)
    if unit then
        local _, cls = UnitClass(unit)
        local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if cc then
            f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
            return
        end
    end
    f.health:SetStatusBarColor(
        conf.healthCustomR or 0.2,
        conf.healthCustomG or 0.8,
        conf.healthCustomB or 0.2, 1)
end

------------------------------------------------------------------------
-- Update power color
------------------------------------------------------------------------
local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local pType, pToken = UnitPowerType(unit)
    -- pType can be secret in 12.0 — but pToken is a string, safe
    if pToken and PowerBarColor and PowerBarColor[pToken] then
        local c = PowerBarColor[pToken]
        f.power:SetStatusBarColor(c.r or 0.5, c.g or 0.5, c.b or 0.5, 1)
    else
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
    end
end

------------------------------------------------------------------------
-- Update all visuals for a unit (called on roster change + events)
------------------------------------------------------------------------
function GF.UpdateButton(f, unit)
    if not f or not unit then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    if not UnitExists(unit) then
        if f.nameText then f.nameText:SetText("") end
        if f.textLeftFS then f.textLeftFS:SetText("") end
        if f.textCenterFS then f.textCenterFS:SetText("") end
        if f.textRightFS then f.textRightFS:SetText("") end
        if f.health then f.health:SetValue(0) end
        if f.power then f.power:SetValue(0) end
        if f.powerTextLeftFS then f.powerTextLeftFS:SetText("") end
        if f.powerTextCenterFS then f.powerTextCenterFS:SetText("") end
        if f.powerTextRightFS then f.powerTextRightFS:SetText("") end
        if f.roleIcon then f.roleIcon:Hide() end
        if f.raidIcon then f.raidIcon:Hide() end
        if f.leaderIcon then f.leaderIcon:Hide() end
        if f.assistIcon then f.assistIcon:Hide() end
        if f.readyCheckIcon then f.readyCheckIcon:Hide() end
        if f.summonIcon then f.summonIcon:Hide() end
        if f.resurrectIcon then f.resurrectIcon:Hide() end
        if f.phaseIcon then f.phaseIcon:Hide() end
        if f.statusIndicatorText then f.statusIndicatorText:SetText(""); f.statusIndicatorText:Hide() end
        return
    end

    -- Name (with color mode + truncation)
    if f.nameText and conf.showName ~= false then
        local name = UnitName(unit) or ""
        local maxC = conf.nameMaxChars or 0
        if maxC > 0 then
            name = GF.TruncateName(name, maxC, conf.nameNoEllipsis)
        end
        f.nameText:SetText(name)
        f.nameText:Show()
        -- Apply name color
        local _, classToken = UnitClass(unit)
        local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
        f.nameText:SetTextColor(nr, ng, nb, 1)
    end

    -- Health (secret-safe: pass raw values to C-side SetValue/SetMinMaxValues)
    if f.health then
        local hp    = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        f.health:SetMinMaxValues(0, hpMax)
        f.health:SetValue(hp)
    end

    ApplyHealthColor(f, kind, unit)

    -- 3-slot health text (secret-safe)
    do
        local hp    = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        local delim = conf.textDelimiter or " / "
        local rev = conf.hpTextReverse
        local tl = conf.textLeft  or "NONE"
        local tc = conf.textCenter or "NONE"
        local tr = conf.textRight or "NONE"
        if f.textLeftFS then
            local txt = GF.FormatHealthText(tl, hp, hpMax, delim, rev)
            f.textLeftFS:SetText(txt)
            if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
        end
        if f.textCenterFS then
            local txt = GF.FormatHealthText(tc, hp, hpMax, delim, rev)
            f.textCenterFS:SetText(txt)
            if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
        end
        if f.textRightFS then
            local txt = GF.FormatHealthText(tr, hp, hpMax, delim, rev)
            f.textRightFS:SetText(txt)
            if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:Hide() end
        end
    end

    -- Power (secret-safe: raw values to C-side) + per-role visibility
    if f.power then
        local powerH = conf.powerHeight or 6
        local showPow = powerH > 0
        if showPow then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if role == "TANK" and conf.powerShowTank == false then showPow = false
            elseif role == "HEALER" and conf.powerShowHealer == false then showPow = false
            elseif role == "DAMAGER" and conf.powerShowDamager == false then showPow = false
            end
        end
        if showPow then
            local pw    = UnitPower(unit)
            local pwMax = UnitPowerMax(unit)
            f.power:SetMinMaxValues(0, pwMax)
            if conf.powerSmoothFill then
                local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
                if interp then f.power:SetValue(pw, interp) else f.power:SetValue(pw) end
            else
                f.power:SetValue(pw)
            end
            f.power:Show()
            ApplyPowerColor(f, unit)
            -- 3-slot power text
            if conf.showPower then
                local pDelim = conf.powerTextDelimiter or " / "
                local ptl = conf.powerTextLeft   or "NONE"
                local ptc = conf.powerTextCenter  or "NONE"
                local ptr = conf.powerTextRight   or "NONE"
                if f.powerTextLeftFS then
                    f.powerTextLeftFS:SetText(GF.FormatPowerText(ptl, pw, pwMax, pDelim))
                    if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
                end
                if f.powerTextCenterFS then
                    f.powerTextCenterFS:SetText(GF.FormatPowerText(ptc, pw, pwMax, pDelim))
                    if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
                end
                if f.powerTextRightFS then
                    f.powerTextRightFS:SetText(GF.FormatPowerText(ptr, pw, pwMax, pDelim))
                    if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end
                end
            end
        else
            f.power:Hide()
            if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
            if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
            if f.powerTextRightFS then f.powerTextRightFS:Hide() end
        end
    end

    -- Role icon
    if f.roleIcon and conf.roleIcon ~= false then
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
        if role and role ~= "NONE" then
            local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
            if tex then
                f.roleIcon:SetTexture(tex)
                f.roleIcon:SetTexCoord(l, r, t, b)
                f.roleIcon:Show()
            else
                f.roleIcon:Hide()
            end
        else
            f.roleIcon:Hide()
        end
    end

    -- Raid target marker
    if f.raidIcon and conf.raidMarker ~= false then
        local idx = GetRaidTargetIndex(unit)
        if idx then
            SetRaidTargetIconTexture(f.raidIcon, idx)
            f.raidIcon:Show()
        else
            f.raidIcon:Hide()
        end
    end

    -- Leader icon (crown only, no assist)
    if f.leaderIcon and conf.leaderIcon ~= false then
        local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
        if isLeader then
            local tex, l, r, t, b = GF.GetLeaderTexture(kind)
            f.leaderIcon:SetTexture(tex)
            f.leaderIcon:SetTexCoord(l, r, t, b)
            f.leaderIcon:Show()
        else
            f.leaderIcon:Hide()
        end
    end

    -- Assist icon (separate, shield only)
    if f.assistIcon and conf.assistIcon ~= false then
        local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
        local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
        if isAssist and not isLeader then
            local tex, l, r, t, b = GF.GetAssistTexture(kind)
            f.assistIcon:SetTexture(tex)
            f.assistIcon:SetTexCoord(l, r, t, b)
            f.assistIcon:Show()
        else
            f.assistIcon:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Scan header children and init them
------------------------------------------------------------------------
local function ScanHeaderChildren(header, kind)
    if not header then return end
    local conf = GF.GetConf(kind)
    local w = conf.width  or (kind == "raid" and 80 or 120)
    local h = conf.height or (kind == "raid" and 32 or 40)
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        if not child._msufGFBuilt then
            GF_InitButton(child, kind)
        end
        -- Resize to current config (initialConfigFunction only ran once at creation)
        child:SetSize(w, h)
        if child.barGroup then child.barGroup:SetSize(w, h) end

        if i == 1 and header.GetCenter and child.GetCenter then
            local hx, hy = header:GetCenter()
            local cx, cy = child:GetCenter()
            if hx and hy and cx and cy then
                local hs = (header.GetEffectiveScale and header:GetEffectiveScale()) or 1
                local cs = (child.GetEffectiveScale and child:GetEffectiveScale()) or 1
                if hs == 0 then hs = 1 end
                if cs == 0 then cs = 1 end
                GF._measuredFirstCenterDelta = GF._measuredFirstCenterDelta or {}
                GF._measuredFirstCenterDelta[kind] = {
                    x = (cx * cs - hx * hs) / hs,
                    y = (cy * cs - hy * hs) / hs,
                }
            end
        end

        local unit = child:GetAttribute("unit") or child.unit
        if unit then
            child.unit = unit
            local p = unit:sub(1, 5)
            if p == "party" or unit:sub(1, 4) == "raid" then
                _G.MSUF_UnitFrames[unit] = child
            end
            GF.UpdateButton(child, unit)
            GF.RegisterUnitEvents(child, unit)
        end
        i = i + 1
    end
end

------------------------------------------------------------------------
-- Grid-center positioning helpers
------------------------------------------------------------------------
GF._previewAnchorFrame = GF._previewAnchorFrame or {}

local function GetDefaultCenter(kind)
    return (kind == "raid") and -500 or -400, 0
end

local function GetLiveCount(kind)
    local conf = GF.GetConf(kind)
    if kind == "raid" then
        local n = (type(GetNumGroupMembers) == "function") and (GetNumGroupMembers() or 0) or 0
        if (type(IsInRaid) == "function" and IsInRaid()) and n > 0 then
            return n
        end
        return 10
    end

    local n = (type(GetNumSubgroupMembers) == "function") and (GetNumSubgroupMembers() or 0) or 0
    if n > 0 then
        if conf.showPlayer ~= false then n = n + 1 end
        return n
    end
    if conf.showSolo and conf.showPlayer ~= false then
        return 1
    end
    return 4
end

local function GetPreviewShownCount(kind)
    local frames = GF._previewFrames and GF._previewFrames[kind]
    if not frames then return 0 end
    local n = 0
    for i = 1, #frames do
        local f = frames[i]
        if f and f:IsShown() then n = n + 1 end
    end
    return n
end

local function PositionHeaderFromGridCenter(kind, header, countOverride)
    if not header then return end
    local conf = GF.GetConf(kind)
    local count = countOverride or GetLiveCount(kind)
    local dx, dy = GF.GetGridMetrics(kind, count)
    local cx, cy = conf.offsetX, conf.offsetY
    if cx == nil or cy == nil then
        cx, cy = GetDefaultCenter(kind)
    end
    header:ClearAllPoints()
    header:SetPoint(conf.point or "CENTER", UIParent, conf.point or "CENTER", cx - dx, cy - dy)
end

function GF.SyncHeaderPosition(kind, countOverride)
    if InCombatLockdown() then return end
    local header = GF.headers and GF.headers[kind]
    if not header then return end
    PositionHeaderFromGridCenter(kind, header, countOverride)
end

------------------------------------------------------------------------
-- Party header setup
------------------------------------------------------------------------
local function SetupPartyHeader()
    if InCombatLockdown() then
        GF._pendingPartyRefresh = true
        return
    end

    local conf = GF.GetConf("party")
    if not conf.enabled then return end

    local parent = _G.PetBattleFrameHider or UIParent
    local header = GF.headers.party

    if not header then
        header = CreateFrame("Frame", "MSUF_GFPartyHeader", parent, "SecureGroupHeaderTemplate")
        header._msufGFKind = "party"
        header:SetClampedToScreen(true)
        GF.headers.party = header
    end

    -- Attributes (combat-lockdown safe: we checked above)
    local w = conf.width  or 120
    local h = conf.height or 40
    local spacing = conf.spacing or 1
    local growth = conf.growth or "DOWN"

    header:SetAttribute("showParty", true)
    header:SetAttribute("showRaid", false)
    header:SetAttribute("showPlayer", conf.showPlayer and true or false)
    header:SetAttribute("showSolo", conf.showSolo and true or false)
    header:SetAttribute("maxColumns", conf.maxColumns or 1)
    header:SetAttribute("unitsPerColumn", conf.unitsPerColumn or 5)
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("sortMethod", "INDEX")
    header:SetAttribute("sortDir", "ASC")

    -- Growth direction → point/xOffset/yOffset
    -- SecureGroupHeader already accounts for child width/height; offsets are spacing only.
    if growth == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", -spacing)
        header:SetAttribute("columnAnchorPoint", "LEFT")
        header:SetAttribute("columnSpacing", spacing)
    elseif growth == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", spacing)
        header:SetAttribute("columnAnchorPoint", "LEFT")
        header:SetAttribute("columnSpacing", spacing)
    elseif growth == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
        header:SetAttribute("yOffset", 0)
        header:SetAttribute("columnAnchorPoint", "TOP")
        header:SetAttribute("columnSpacing", spacing)
    elseif growth == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
        header:SetAttribute("yOffset", 0)
        header:SetAttribute("columnAnchorPoint", "TOP")
        header:SetAttribute("columnSpacing", spacing)
    end

    -- initialConfigFunction: size + attributes ONLY (no RegisterForClicks!)
    local wStr = ("%.1f"):format(w)
    local hStr = ("%.1f"):format(h)
    header:SetAttribute("initialConfigFunction", ([[
        self:SetWidth(%s)
        self:SetHeight(%s)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
    ]]):format(wStr, hStr))

    -- Position (stored offset = grid center)
    PositionHeaderFromGridCenter("party", header)

    -- OnShow hook for deferred child scan
    if not header._msufGFShowHooked then
        header._msufGFShowHooked = true
        header:HookScript("OnShow", function(self)
            C_Timer.After(0, function()
                ScanHeaderChildren(self, "party")
            end)
        end)
    end

    -- Attribute change hook for unit assignment
    if not header._msufGFAttrHooked then
        header._msufGFAttrHooked = true
        hooksecurefunc(header, "SetAttribute", function(self, attr, val)
            -- Detect child unit assignment via header internals
        end)
    end

    header:Show()

    -- Deferred child scan (children created async after Show)
    C_Timer.After(0, function()
        ScanHeaderChildren(header, "party")
    end)
end

------------------------------------------------------------------------
-- Raid header setup
------------------------------------------------------------------------
local function SetupRaidHeader()
    if InCombatLockdown() then
        GF._pendingRaidRefresh = true
        return
    end

    local conf = GF.GetConf("raid")
    if not conf.enabled then return end

    local parent = _G.PetBattleFrameHider or UIParent
    local header = GF.headers.raid

    if not header then
        header = CreateFrame("Frame", "MSUF_GFRaidHeader", parent, "SecureGroupHeaderTemplate")
        header._msufGFKind = "raid"
        header:SetClampedToScreen(true)
        GF.headers.raid = header
    end

    local w = conf.width  or 80
    local h = conf.height or 32
    local spacing = conf.spacing or 1
    local growth = conf.growth or "DOWN"
    local unitsPerColumn = conf.unitsPerColumn or 5
    local maxColumns = conf.maxColumns or 8

    header:SetAttribute("showParty", false)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showSolo", false)
    header:SetAttribute("maxColumns", maxColumns)
    header:SetAttribute("unitsPerColumn", unitsPerColumn)
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("sortMethod", "INDEX")
    header:SetAttribute("sortDir", "ASC")
    -- No groupBy — pure grid: wraps at unitsPerColumn, fills up to maxColumns

    -- Growth
    local colGrowth = "DOWN"
    if growth == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", -spacing)
        header:SetAttribute("columnAnchorPoint", "LEFT")
        header:SetAttribute("columnSpacing", spacing)
    elseif growth == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", spacing)
        header:SetAttribute("columnAnchorPoint", "LEFT")
        header:SetAttribute("columnSpacing", spacing)
    elseif growth == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
        header:SetAttribute("yOffset", 0)
        header:SetAttribute("columnAnchorPoint", "TOP")
        header:SetAttribute("columnSpacing", spacing)
    elseif growth == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
        header:SetAttribute("yOffset", 0)
        header:SetAttribute("columnAnchorPoint", "TOP")
        header:SetAttribute("columnSpacing", spacing)
    end

    local wStr = ("%.1f"):format(w)
    local hStr = ("%.1f"):format(h)
    header:SetAttribute("initialConfigFunction", ([[
        self:SetWidth(%s)
        self:SetHeight(%s)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
    ]]):format(wStr, hStr))

    PositionHeaderFromGridCenter("raid", header)

    if not header._msufGFShowHooked then
        header._msufGFShowHooked = true
        header:HookScript("OnShow", function(self)
            C_Timer.After(0, function()
                ScanHeaderChildren(self, "raid")
            end)
        end)
    end

    header:Show()

    C_Timer.After(0, function()
        ScanHeaderChildren(header, "raid")
    end)
end

------------------------------------------------------------------------
-- Blizzard frame hiding
------------------------------------------------------------------------
local function HideFrameLocked(frame)
    if not frame then return end
    if frame._msufGFHidden then return end
    frame._msufGFHidden = true
    local hp = GetHiddenParent()
    if frame.SetParent then pcall(frame.SetParent, frame, hp) end
    if not frame._msufGFHideHooked then
        frame._msufGFHideHooked = true
        if frame.Show then
            hooksecurefunc(frame, "Show", function(f)
                if f._msufGFHidden then
                    pcall(f.SetParent, f, hp)
                end
            end)
        end
    end
end

function GF.DisableBlizzardFrames()
    if InCombatLockdown() then
        GF._pendingBlizzardDisable = true
        return
    end
    local partyConf = GF.GetConf("party")
    local raidConf  = GF.GetConf("raid")
    if partyConf.enabled then
        HideFrameLocked(_G.PartyFrame)
        HideFrameLocked(_G.CompactPartyFrame)
        HideFrameLocked(_G.CompactPartyFrameTitle)
    end
    if raidConf.enabled then
        HideFrameLocked(_G.CompactRaidFrameContainer)
        if _G.CompactRaidFrameManager_SetSetting then
            pcall(_G.CompactRaidFrameManager_SetSetting, "IsShown", "0")
        end
    end
end

function GF.RestoreBlizzardFrames()
    -- Undo reparenting
    for _, name in pairs({ "PartyFrame", "CompactPartyFrame", "CompactPartyFrameTitle", "CompactRaidFrameContainer" }) do
        local f = _G[name]
        if f and f._msufGFHidden then
            f._msufGFHidden = nil
            if f.SetParent then pcall(f.SetParent, f, UIParent) end
        end
    end
end

------------------------------------------------------------------------
-- Preview system (fake data for Edit Mode / Options)
------------------------------------------------------------------------
local PREVIEW_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER",
    "EVOKER" }
local PREVIEW_NAMES = { "Thrall", "Jaina", "Sylvanas", "Anduin", "Tyrande" }
local PREVIEW_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "HEALER" }

function GF.ApplyPreviewData(f, index, kind)
    if not f then return end
    f._msufGFPreviewActive = true
    f._msufGFPreviewIndex = index
    f._msufGFPreviewClass = PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
    local conf = GF.GetConf(kind or "party")
    local cls = f._msufGFPreviewClass
    local name = PREVIEW_NAMES[((index - 1) % #PREVIEW_NAMES) + 1]
    local role = PREVIEW_ROLES[((index - 1) % #PREVIEW_ROLES) + 1]
    local hpPct = 0.3 + (index * 0.15) % 0.7

    -- Name (with color + truncation)
    if f.nameText and conf.showName ~= false then
        local displayName = name
        local maxC = conf.nameMaxChars or 0
        if maxC > 0 then
            displayName = GF.TruncateName(displayName, maxC, conf.nameNoEllipsis)
        end
        f.nameText:SetText(displayName)
        f.nameText:Show()
        local nr, ng, nb = GF.ResolveNameColor(kind or "party", cls)
        f.nameText:SetTextColor(nr, ng, nb, 1)
    end

    -- Health bar value + color (self-contained, respects global barMode)
    if f.health then
        f.health:SetMinMaxValues(0, 100)
        f.health:SetValue(math_floor(hpPct * 100))
        -- Resolve health color: global barMode takes priority
        local getCache = _G.MSUF_UFCore_GetSettingsCache
        local cache = type(getCache) == "function" and getCache() or nil
        local gm = cache and cache.barMode
        if gm == "dark" then
            f.health:SetStatusBarColor(cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0, 1)
        elseif gm == "unified" then
            f.health:SetStatusBarColor(cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90, 1)
        else
            local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
            if type(fastClass) == "function" then
                local cr, cg, cb = fastClass(cls)
                if cr then
                    f.health:SetStatusBarColor(cr, cg, cb, 1)
                else
                    local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                    if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
                    else f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1) end
                end
            else
                local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
                else f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1) end
            end
        end
    end

    -- 3-slot health text (preview with fake values)
    do
        local fakeHP = math_floor(hpPct * 100)
        local fakeMax = 100
        local delim = conf.textDelimiter or " / "
        local rev = conf.hpTextReverse
        local tl = conf.textLeft  or "NONE"
        local tc = conf.textCenter or "NONE"
        local tr = conf.textRight or "NONE"
        if f.textLeftFS then
            f.textLeftFS:SetText(GF.FormatHealthText(tl, fakeHP, fakeMax, delim, rev))
            if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
        end
        if f.textCenterFS then
            f.textCenterFS:SetText(GF.FormatHealthText(tc, fakeHP, fakeMax, delim, rev))
            if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
        end
        if f.textRightFS then
            f.textRightFS:SetText(GF.FormatHealthText(tr, fakeHP, fakeMax, delim, rev))
            if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:Hide() end
        end
    end

    -- Health prediction overlays (preview with fake values + global colors)
    local hpVal = math_floor(hpPct * 100)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if f.incomingHealBar and conf.healPredEnabled ~= false then
        f.incomingHealBar:SetMinMaxValues(0, 100)
        f.incomingHealBar:SetValue(math_min(hpVal + 20, 100))
        local r, g, b = 0.0, 1.0, 0.4
        if gen then
            r = gen.healPredColorR or r; g = gen.healPredColorG or g; b = gen.healPredColorB or b
        end
        f.incomingHealBar:SetStatusBarColor(r, g, b, 0.45)
        f.incomingHealBar:Show()
    elseif f.incomingHealBar then
        f.incomingHealBar:Hide()
    end
    if f.absorbBar and conf.absorbEnabled ~= false then
        f.absorbBar:SetMinMaxValues(0, 100)
        f.absorbBar:SetValue(15 + index * 5)
        local r, g, b = 0.8, 0.9, 1.0
        if gen then
            r = gen.absorbBarColorR or r; g = gen.absorbBarColorG or g; b = gen.absorbBarColorB or b
        end
        f.absorbBar:SetStatusBarColor(r, g, b, 0.6)
        f.absorbBar:Show()
    elseif f.absorbBar then
        f.absorbBar:Hide()
    end
    if f.healAbsorbBar and conf.healAbsorbEnabled ~= false then
        f.healAbsorbBar:SetMinMaxValues(0, 100)
        f.healAbsorbBar:SetValue(math_min(8, hpVal))
        local r, g, b = 1.0, 0.4, 0.4
        if gen then
            r = gen.healAbsorbBarColorR or r; g = gen.healAbsorbBarColorG or g; b = gen.healAbsorbBarColorB or b
        end
        f.healAbsorbBar:SetStatusBarColor(r, g, b, 0.7)
        f.healAbsorbBar:Show()
    elseif f.healAbsorbBar then
        f.healAbsorbBar:Hide()
    end

    -- Power bar
    if f.power and (conf.powerHeight or 6) > 0 then
        local fakePow = 50 + index * 10
        local fakePowMax = 100
        f.power:SetMinMaxValues(0, fakePowMax)
        f.power:SetValue(fakePow)
        f.power:SetStatusBarColor(0.2, 0.2, 0.8, 1)
        f.power:Show()
        -- 3-slot power text (preview)
        if conf.showPower then
            local pDelim = conf.powerTextDelimiter or " / "
            local ptl = conf.powerTextLeft   or "NONE"
            local ptc = conf.powerTextCenter  or "NONE"
            local ptr = conf.powerTextRight   or "NONE"
            if f.powerTextLeftFS then
                f.powerTextLeftFS:SetText(GF.FormatPowerText(ptl, fakePow, fakePowMax, pDelim))
                if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
            end
            if f.powerTextCenterFS then
                f.powerTextCenterFS:SetText(GF.FormatPowerText(ptc, fakePow, fakePowMax, pDelim))
                if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
            end
            if f.powerTextRightFS then
                f.powerTextRightFS:SetText(GF.FormatPowerText(ptr, fakePow, fakePowMax, pDelim))
                if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end
            end
        end
    end

    -- Role icon
    if f.roleIcon and conf.roleIcon ~= false then
        local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
        if tex then
            f.roleIcon:SetTexture(tex)
            f.roleIcon:SetTexCoord(l, r, t, b)
            f.roleIcon:Show()
        end
    end

    -- Leader icon (preview: show for index 1)
    if f.leaderIcon and conf.leaderIcon ~= false and index == 1 then
        local tex, l, r, t, b = GF.GetLeaderTexture(kind)
        f.leaderIcon:SetTexture(tex)
        f.leaderIcon:SetTexCoord(l, r, t, b)
        f.leaderIcon:Show()
    elseif f.leaderIcon then
        f.leaderIcon:Hide()
    end

    -- Assist icon (preview: show for index 2)
    if f.assistIcon and conf.assistIcon ~= false and index == 2 then
        local tex, l, r, t, b = GF.GetAssistTexture(kind)
        f.assistIcon:SetTexture(tex)
        f.assistIcon:SetTexCoord(l, r, t, b)
        f.assistIcon:Show()
    elseif f.assistIcon then
        f.assistIcon:Hide()
    end

    -- Raid marker (preview: show for index 1)
    if f.raidIcon and conf.raidMarker ~= false and index == 1 then
        f.raidIcon:SetTexCoord(0, 0.25, 0, 0.25)  -- star
        f.raidIcon:Show()
    elseif f.raidIcon then
        f.raidIcon:Hide()
    end

    -- Event icons in preview (show on specific frames for visual reference)
    if f.readyCheckIcon and conf.readyCheckIcon ~= false then
        if index == 1 or index == 3 then
            f.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            f.readyCheckIcon:Show()
        else
            f.readyCheckIcon:Hide()
        end
    elseif f.readyCheckIcon then f.readyCheckIcon:Hide() end

    if f.summonIcon and conf.summonIcon ~= false then
        if index == 2 then
            f.summonIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-SummonPending")
            f.summonIcon:Show()
        else
            f.summonIcon:Hide()
        end
    elseif f.summonIcon then f.summonIcon:Hide() end

    if f.resurrectIcon and conf.resurrectIcon ~= false then
        if index == 3 then
            f.resurrectIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            f.resurrectIcon:Show()
        else
            f.resurrectIcon:Hide()
        end
    elseif f.resurrectIcon then f.resurrectIcon:Hide() end

    if f.phaseIcon and conf.phaseIcon ~= false then
        if index == 4 or index == 2 then
            f.phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
            f.phaseIcon:Show()
        else
            f.phaseIcon:Hide()
        end
    elseif f.phaseIcon then f.phaseIcon:Hide() end

    -- Private auras: hide real container (no unit), show mock preview
    if f._gfPrivContainer then f._gfPrivContainer:Hide() end
    if GF.PreviewPrivateAuras then
        GF.PreviewPrivateAuras(f, kind)
    end

    -- Spell indicators preview (placed icons + frame effects with mock data)
    if GF.PreviewSpellIndicators then
        GF.PreviewSpellIndicators(f, kind, nil, nil)
    end

    -- Aura group preview (mock buff/debuff/external icons)
    if GF.PreviewFrameAuras then
        GF.PreviewFrameAuras(f, kind, index)
    end

    -- Status text hidden in preview
    if f.statusIndicatorText then
        f.statusIndicatorText:SetText("")
        f.statusIndicatorText:Hide()
    end

    -- Group number (preview: fake subgroup)
    if f.groupNumberText and conf.showGroupNumber then
        f.groupNumberText:SetText(tostring(((index - 1) % 5) + 1))
        f.groupNumberText:Show()
    elseif f.groupNumberText then
        f.groupNumberText:Hide()
    end

    -- Reverse fill
    if f.health and f.health.SetReverseFill then
        f.health:SetReverseFill(conf.reverseFill and true or false)
    end

    -- Show the frame
    f:Show()
end

function GF.ClearPreviewData(f)
    if not f then return end
    f._msufGFPreviewActive = nil
    f._msufGFPreviewIndex = nil
    if f.nameText then f.nameText:SetText("") end
    if f.textLeftFS then f.textLeftFS:SetText("") end
    if f.textCenterFS then f.textCenterFS:SetText("") end
    if f.textRightFS then f.textRightFS:SetText("") end
    if f.health then f.health:SetValue(0) end
    if f.incomingHealBar then f.incomingHealBar:SetValue(0); f.incomingHealBar:Hide() end
    if f.absorbBar then f.absorbBar:SetValue(0); f.absorbBar:Hide() end
    if f.healAbsorbBar then f.healAbsorbBar:SetValue(0); f.healAbsorbBar:Hide() end
    if f.power then f.power:SetValue(0) end
    if f.powerTextLeftFS then f.powerTextLeftFS:SetText(""); f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:SetText(""); f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:SetText(""); f.powerTextRightFS:Hide() end
    if f.roleIcon then f.roleIcon:Hide() end
    if f.raidIcon then f.raidIcon:Hide() end
    if f.leaderIcon then f.leaderIcon:Hide() end
    if f.assistIcon then f.assistIcon:Hide() end
    if f.readyCheckIcon then f.readyCheckIcon:Hide() end
    if f.summonIcon then f.summonIcon:Hide() end
    if f.resurrectIcon then f.resurrectIcon:Hide() end
    if f.phaseIcon then f.phaseIcon:Hide() end
    if f.groupNumberText then f.groupNumberText:SetText(""); f.groupNumberText:Hide() end
    if f.statusIndicatorText then f.statusIndicatorText:SetText(""); f.statusIndicatorText:Hide() end
    if f._gfPrivContainer then f._gfPrivContainer:Hide() end
    if GF.HidePreviewPrivateAuras then GF.HidePreviewPrivateAuras(f) end
    if GF.HideSpellIndicators then GF.HideSpellIndicators(f) end
    if GF.HideFrameAuras then GF.HideFrameAuras(f) end
end

------------------------------------------------------------------------
-- Preview frames (standalone, not tied to SecureGroupHeader)
------------------------------------------------------------------------
GF._previewFrames = GF._previewFrames or {}

function GF.SetPreviewAnchor(kind, parent)
    GF._previewAnchorFrame[kind] = parent
end

------------------------------------------------------------------------
-- Grid position helper (used by ShowPreview + RefreshPreviewLayout)
------------------------------------------------------------------------
local function GridPosition(baseX, baseY, i, w, h, spacing, growth, upc)
    upc = upc or 40
    local col = math.floor((i - 1) / upc)
    local row = (i - 1) % upc
    if growth == "DOWN" then
        return baseX + col * (w + spacing), baseY - row * (h + spacing)
    elseif growth == "UP" then
        return baseX + col * (w + spacing), baseY + row * (h + spacing)
    elseif growth == "RIGHT" then
        return baseX + row * (w + spacing), baseY - col * (h + spacing)
    elseif growth == "LEFT" then
        return baseX - row * (w + spacing), baseY - col * (h + spacing)
    end
    return baseX, baseY
end

function GF.ShowPreview(kind, count)
    kind = kind or "party"
    count = count or (kind == "raid" and 20 or 4)
    local conf = GF.GetConf(kind)
    local dx, dy, _, _, w, h, spacing, growth, upc, _, firstDX, firstDY = GF.GetGridMetrics(kind, count)
    local key = kind

    GF._previewActive[key] = true

    -- Ensure preview frames
    if not GF._previewFrames[key] then GF._previewFrames[key] = {} end
    local frames = GF._previewFrames[key]

    local centerX = conf.offsetX
    local centerY = conf.offsetY
    if centerX == nil or centerY == nil then
        centerX, centerY = GetDefaultCenter(kind)
    end
    local originX = centerX - dx
    local originY = centerY - dy
    local baseX = originX + firstDX
    local baseY = originY + firstDY
    local anchorParent = GF._previewAnchorFrame and GF._previewAnchorFrame[key]
    local parent = anchorParent or UIParent

    for i = 1, count do
        local f = frames[i]
        if not f then
            f = CreateFrame("Button", "MSUF_GFPreview_" .. key .. "_" .. i, parent, "BackdropTemplate")
            f:SetSize(w, h)
            f._msufGFKind = kind
            f._msufIsGroupFrame = true
            f.msufConfigKey = (kind == "raid") and "gf_raid" or "gf_party"
            BuildFrameHierarchy(f, kind)
            ApplyFonts(f, kind)
            LayoutText(f, kind)
            LayoutIcons(f, kind)
            frames[i] = f
        elseif f:GetParent() ~= parent then
            f:SetParent(parent)
        end

        f:SetSize(w, h)
        f:ClearAllPoints()
        local px, py = GridPosition(baseX, baseY, i, w, h, spacing, growth, upc)
        if anchorParent then
            f:SetPoint("CENTER", parent, "CENTER", px - centerX, py - centerY)
        else
            f:SetPoint("CENTER", parent, "CENTER", px, py)
        end
        GF.ApplyPreviewData(f, i, kind)
    end

    -- Hide excess frames
    for i = count + 1, #frames do
        if frames[i] then
            GF.ClearPreviewData(frames[i])
            frames[i]:Hide()
        end
    end
end

function GF.HidePreview(kind)
    kind = kind or "party"
    GF._previewActive[kind] = nil
    local frames = GF._previewFrames[kind]
    if not frames then return end
    for i = 1, #frames do
        if frames[i] then
            GF.ClearPreviewData(frames[i])
            frames[i]:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Refresh preview layout (sizes + positions from current config)
-- Called by Options sliders when width/height/spacing/growth change.
------------------------------------------------------------------------
function GF.RefreshPreviewLayout(kind)
    kind = kind or "party"
    if not GF._previewActive or not GF._previewActive[kind] then return end
    local frames = GF._previewFrames and GF._previewFrames[kind]
    if not frames then return end
    local count = GetPreviewShownCount(kind)
    local conf = GF.GetConf(kind)
    local dx, dy, _, _, w, h, spacing, growth, upc, _, firstDX, firstDY = GF.GetGridMetrics(kind, count)
    local centerX = conf.offsetX
    local centerY = conf.offsetY
    if centerX == nil or centerY == nil then
        centerX, centerY = GetDefaultCenter(kind)
    end
    local originX = centerX - dx
    local originY = centerY - dy
    local baseX = originX + firstDX
    local baseY = originY + firstDY
    local anchorParent = GF._previewAnchorFrame and GF._previewAnchorFrame[kind]
    local parent = anchorParent or UIParent

    for i = 1, #frames do
        local f = frames[i]
        if f and f:IsShown() then
            if f:GetParent() ~= parent then
                f:SetParent(parent)
            end
            f:SetSize(w, h)
            if f.barGroup then f.barGroup:SetSize(w, h) end
            f:ClearAllPoints()
            local px, py = GridPosition(baseX, baseY, i, w, h, spacing, growth, upc)
            if anchorParent then
                f:SetPoint("CENTER", parent, "CENTER", px - centerX, py - centerY)
            else
                f:SetPoint("CENTER", parent, "CENTER", px, py)
            end
        end
    end
end

------------------------------------------------------------------------
-- Refresh all GF frames
------------------------------------------------------------------------
function GF.RefreshAll()
    for f, kind in pairs(GF.frames) do
        local unit = f.unit
        if unit and UnitExists(unit) then
            GF.UpdateButton(f, unit)
        end
    end
end

function GF.RebuildAll()
    if InCombatLockdown() then
        GF._pendingRebuild = true
        return
    end
    local partyConf = GF.GetConf("party")
    local raidConf  = GF.GetConf("raid")

    local inRaid = IsInRaid and IsInRaid() or false

    -- Party: build once, show only outside raid
    if partyConf.enabled then
        SetupPartyHeader()
        if inRaid and GF.headers.party then
            GF.headers.party:Hide()
        end
    elseif GF.headers.party then
        GF.headers.party:Hide()
    end

    -- Raid: build once, show only in raid
    if raidConf.enabled then
        SetupRaidHeader()
        if not inRaid and GF.headers.raid then
            GF.headers.raid:Hide()
        end
    elseif GF.headers.raid then
        GF.headers.raid:Hide()
    end

    GF.DisableBlizzardFrames()
    GF.RefreshPreviewLayout("party")
    GF.RefreshPreviewLayout("raid")
    -- Deferred: after SecureGroupHeader repositions children, re-apply visuals (geometry, bars, text)
    C_Timer.After(0.05, function()
        GF.MarkAllDirty(GF.DIRTY_ALL)
    end)
end

------------------------------------------------------------------------
-- Toggle headers when group type changes (party ↔ raid)
------------------------------------------------------------------------
function GF.UpdateGroupVisibility()
    if InCombatLockdown() then
        GF._pendingVisibilityUpdate = true
        return
    end
    local inRaid = IsInRaid and IsInRaid() or false
    local partyConf = GF.GetConf("party")
    local raidConf  = GF.GetConf("raid")

    -- Party header
    if GF.headers.party then
        if partyConf.enabled and not inRaid then
            GF.SyncHeaderPosition("party")
            GF.headers.party:Show()
            C_Timer.After(0, function()
                if GF.headers.party then ScanHeaderChildren(GF.headers.party, "party") end
            end)
        else
            GF.headers.party:Hide()
        end
    end

    -- Raid header
    if GF.headers.raid then
        if raidConf.enabled and inRaid then
            GF.SyncHeaderPosition("raid")
            GF.headers.raid:Show()
            C_Timer.After(0, function()
                if GF.headers.raid then ScanHeaderChildren(GF.headers.raid, "raid") end
            end)
        else
            GF.headers.raid:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        GF.EnsureDB()
        local partyConf = GF.GetConf("party")
        local raidConf  = GF.GetConf("raid")
        if partyConf.enabled or raidConf.enabled then
            GF.RebuildAll()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Switch party/raid visibility + rescan children
        GF.UpdateGroupVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if GF._pendingPartyRefresh then
            GF._pendingPartyRefresh = nil
            SetupPartyHeader()
        end
        if GF._pendingRaidRefresh then
            GF._pendingRaidRefresh = nil
            SetupRaidHeader()
        end
        if GF._pendingBlizzardDisable then
            GF._pendingBlizzardDisable = nil
            GF.DisableBlizzardFrames()
        end
        if GF._pendingRebuild then
            GF._pendingRebuild = nil
            GF.RebuildAll()
        end
        if GF._pendingVisibilityUpdate then
            GF._pendingVisibilityUpdate = nil
            GF.UpdateGroupVisibility()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        GF.EnsureDB()
        local partyConf = GF.GetConf("party")
        local raidConf  = GF.GetConf("raid")
        if partyConf.enabled or raidConf.enabled then
            C_Timer.After(0.5, function() GF.RebuildAll() end)
        end
    end
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("GROUP_ROSTER_UPDATE")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", OnEvent)
GF._eventFrame = ef

------------------------------------------------------------------------
-- Global exports
------------------------------------------------------------------------
_G.MSUF_GF_ShowPreview      = GF.ShowPreview
_G.MSUF_GF_HidePreview      = GF.HidePreview
_G.MSUF_GF_RebuildAll        = GF.RebuildAll
_G.MSUF_GF_RefreshAll        = GF.RefreshAll
_G.MSUF_GF_RefreshPreviewLayout = GF.RefreshPreviewLayout
_G.MSUF_GF_DisableBlizzard   = GF.DisableBlizzardFrames
_G.MSUF_GF_RestoreBlizzard   = GF.RestoreBlizzardFrames
_G.MSUF_GF_UpdateButton      = GF.UpdateButton
_G.MSUF_GF_InitButton        = GF_InitButton
_G.MSUF_GF_UpdateGroupVisibility = GF.UpdateGroupVisibility

------------------------------------------------------------------------
-- Profile-swap re-init: hook MSUF_SwitchProfile → EnsureDB + RebuildAll
------------------------------------------------------------------------
do
    C_Timer.After(0.2, function()
        local origSwitch = _G.MSUF_SwitchProfile
        if type(origSwitch) == "function" then
            _G.MSUF_SwitchProfile = function(...)
                origSwitch(...)
                GF.EnsureDB()
                C_Timer.After(0.1, function()
                    GF.RebuildAll()
                end)
            end
        end
    end)
end
