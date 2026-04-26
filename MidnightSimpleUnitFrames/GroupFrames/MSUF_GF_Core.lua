-- MSUF_GF_Core.lua — Group Frames core: factory, layout, preview, hiding
-- Phase 1: Party + Raid frame creation with EQoL-pattern hierarchy
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

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
local GetTime = _G.GetTime

------------------------------------------------------------------------
-- Hidden parent for Blizzard frame hiding
------------------------------------------------------------------------
local _hiddenParent
local RegisterTrackedFrame, UnregisterTrackedFrame
local function GetHiddenParent()
    if not _hiddenParent then
        _hiddenParent = CreateFrame("Frame", nil, UIParent)
        _hiddenParent:SetAllPoints(UIParent)
        _hiddenParent:Hide()
    end
    return _hiddenParent
end

------------------------------------------------------------------------
-- RetireHeader: aggressively clean up an old header + children.
-- Reparents everything to hidden parent → zero render/CPU cost.
-- WoW never GCs frames, but this removes them from the render pipeline.
------------------------------------------------------------------------
local function RetireHeader(header)
    if not header then return end
    header:Hide()
    local hp = GetHiddenParent()
    local kids = { header:GetChildren() }
    for i = 1, #kids do
        local ch = kids[i]
        if ch then
            -- Deregister from GF tracking
            UnregisterTrackedFrame(ch)
            if ch.unit and _G.MSUF_UnitFrames then
                _G.MSUF_UnitFrames[ch.unit] = nil
            end
            -- Strip event handlers (zero combat overhead)
            ch:UnregisterAllEvents()
            if ch.SetScript then
                ch:SetScript("OnEvent", nil)
                ch:SetScript("OnUpdate", nil)
            end
            -- Hide all sub-frames
            if ch.barGroup then ch.barGroup:Hide() end
            if ch.health then ch.health:Hide() end
            if ch.power then ch.power:Hide() end
            if ch._msufGFBorderFrame then ch._msufGFBorderFrame:Hide() end
            if ch._msufGFHighlightBorder then ch._msufGFHighlightBorder:Hide() end
            if ch._msufGFNameText then ch._msufGFNameText:Hide() end
            if ch._msufGFStatusText then ch._msufGFStatusText:Hide() end
            -- Minimize + hide + reparent to hidden frame
            ch:Hide()
            ch:ClearAllPoints()
            ch:SetSize(0.001, 0.001)
            ch:SetParent(hp)
            -- Clear references to allow Lua-side GC of tables
            ch._c = nil
            ch._msufGFBuilt = nil
            ch._msufGFRegisteredUnit = nil
            ch._msufGFKind = nil
        end
    end
    -- Reparent header itself to hidden frame
    header:ClearAllPoints()
    header:SetSize(0.001, 0.001)
    header:SetParent(hp)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
GF.headers     = GF.headers or {}     -- party/raid SecureGroupHeaders
GF.anchors     = GF.anchors or {}     -- anchor frames
GF.frames      = GF.frames or {}      -- all built unit buttons
GF.frameList   = GF.frameList or {}   -- compact live-frame iteration order

-- Cross-system frame registry (A2, EM2, etc. resolve unit→frame via this table)
if type(_G.MSUF_UnitFrames) ~= "table" then _G.MSUF_UnitFrames = {} end
GF._eventFrame = GF._eventFrame or nil
GF._previewActive = GF._previewActive or {}

RegisterTrackedFrame = function(f, kind)
    if not f then return end
    GF.frames[f] = kind
    if f._msufGFFrameListIndex then return end
    local list = GF.frameList
    local idx = #list + 1
    list[idx] = f
    f._msufGFFrameListIndex = idx
end

UnregisterTrackedFrame = function(f)
    if not f then return end
    GF.frames[f] = nil

    local idx = f._msufGFFrameListIndex
    if not idx then return end

    local list = GF.frameList
    local lastIndex = #list
    local last = list[lastIndex]

    list[lastIndex] = nil
    if idx < lastIndex and last then
        list[idx] = last
        last._msufGFFrameListIndex = idx
    end

    f._msufGFFrameListIndex = nil
end

function GF.ForEachFrame(fn)
    if type(fn) ~= "function" then return end
    local list = GF.frameList
    for i = 1, #list do
        local f = list[i]
        if f then
            fn(f, f._msufGFKind or GF.frames[f])
        end
    end
end

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

    -- Clear any inherited backdrop from SecureUnitButtonTemplate
    if f.SetBackdrop then f:SetBackdrop(nil) end
    if f.SetClipsChildren then f:SetClipsChildren(false) end

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
    if barGroup.SetClipsChildren then barGroup:SetClipsChildren(false) end
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

    -- Cutaway health bar (shows health loss as red fadeout, behind health bar)
    local cutaway = CreateFrame("StatusBar", nil, barGroup)
    cutaway:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    cutaway:SetMinMaxValues(0, 1)
    cutaway:SetValue(1)
    cutaway:SetAllPoints(health)
    cutaway:SetFrameLevel(health:GetFrameLevel())
    cutaway:SetStatusBarColor(
        conf.cutawayColorR or 0.70, conf.cutawayColorG or 0.10,
        conf.cutawayColorB or 0.10, conf.cutawayColorA or 0.75)
    cutaway:Hide()
    f._msufCutaway = cutaway
    -- Health bar draws ON TOP of cutaway (raise its draw layer)
    health:SetFrameLevel(health:GetFrameLevel() + 1)

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

    -- Dispel overlay (color wash on health bar — above absorb, below text)
    local dispelOv = CreateFrame("StatusBar", nil, barGroup)
    dispelOv:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    dispelOv:SetMinMaxValues(0, 1)
    dispelOv:SetValue(1)
    dispelOv:SetAllPoints(health)
    dispelOv:SetFrameLevel(hLvl + 4)
    dispelOv:SetStatusBarColor(0, 0, 0, 0)
    dispelOv:Hide()
    f._msufGFDispelOverlay = dispelOv

    -- Debuff stripe (thin edge indicator for any debuff — above dispel overlay, below text)
    local debuffStripe = CreateFrame("StatusBar", nil, barGroup)
    debuffStripe:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    debuffStripe:SetMinMaxValues(0, 1)
    debuffStripe:SetValue(1)
    debuffStripe:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    debuffStripe:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    debuffStripe:SetHeight(3)
    debuffStripe:SetFrameLevel(hLvl + 5)
    debuffStripe:SetStatusBarColor(0.8, 0.2, 0.2, 0.6)
    debuffStripe:Hide()
    f._msufGFDebuffStripe = debuffStripe

    -- Health text layer (above all overlays)
    local healthTextLayer = CreateFrame("Frame", nil, health)
    healthTextLayer:SetAllPoints(health)
    healthTextLayer:SetFrameLevel(hLvl + 6)
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
    if statusIconLayer.SetClipsChildren then statusIconLayer:SetClipsChildren(false) end
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

------------------------------------------------------------------------
-- Melee/Ranged spec classification (EQoL pattern)
------------------------------------------------------------------------
local MELEE_SPECS = {
    [250]=true,[251]=true,[252]=true,  -- DK
    [577]=true,[581]=true,             -- DH
    [103]=true,[104]=true,             -- Druid Feral/Guardian
    [1473]=true,                       -- Evoker Aug
    [255]=true,                        -- Hunter Survival
    [268]=true,[269]=true,             -- Monk BM/WW
    [66]=true,[70]=true,               -- Paladin Prot/Ret
    [259]=true,[260]=true,[261]=true,  -- Rogue
    [263]=true,                        -- Shaman Enh
    [71]=true,[72]=true,[73]=true,     -- Warrior
}
local MELEE_CLASSES = {
    WARRIOR=true, ROGUE=true, DEATHKNIGHT=true,
    DEMONHUNTER=true, MONK=true, PALADIN=true,
}

local function GetDpsRangeRole(unit, classToken)
    local specId
    if GetInspectSpecialization and UnitIsUnit and UnitIsUnit(unit, "player") then
        specId = GetSpecialization and GetSpecialization()
        if specId then
            local id = GetSpecializationInfo and GetSpecializationInfo(specId)
            specId = id
        end
    end
    if specId and MELEE_SPECS[specId] then return "MELEE" end
    if specId and specId > 0 then return "RANGED" end
    if classToken and MELEE_CLASSES[classToken] then return "MELEE" end
    return "RANGED"
end

------------------------------------------------------------------------
-- NAMELIST sort builder: role → playerFirst → class → name
-- Used when separateMeleeRanged=true (native groupBy can't split DPS).
-- PERF: Pre-allocated entry pool (max 40 raid members) — zero GC per call.
------------------------------------------------------------------------
local _sortEntryPool = {}
for i = 1, 40 do _sortEntryPool[i] = { name = "", sortRole = "", class = "", isPlayer = false } end
local _sortNames = {}
local _sortSeen  = {}

local function BuildSortNameList(kind)
    local conf = GF.GetConf(kind)
    if not conf.sortByRole then return nil end

    local separate = conf.separateMeleeRanged == true
    local playerFirst = conf.playerFirstInRole == true

    -- Parse role order string → priority map
    local roleStr = conf.roleOrder or "TANK,HEALER,DAMAGER"
    local rolePrio = {}
    local idx = 0
    for tok in roleStr:gmatch("[^,]+") do
        idx = idx + 1
        rolePrio[tok] = idx
        -- Expand DAMAGER → MELEE + RANGED if separate and token is DAMAGER
        if separate and tok == "DAMAGER" then
            rolePrio["MELEE"] = idx
            rolePrio["RANGED"] = idx + 0.5
        end
    end
    if separate and not rolePrio["MELEE"] then rolePrio["MELEE"] = 90 end
    if separate and not rolePrio["RANGED"] then rolePrio["RANGED"] = 91 end

    -- Gather group members into pre-allocated pool
    local entryCount = 0
    local function addUnit(unit)
        if not (unit and UnitExists(unit)) then return end
        local name, realm = UnitName(unit)
        if not name or name == "" then return end
        if realm and realm ~= "" then name = name .. "-" .. realm end
        local _, classToken = UnitClass(unit)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "DAMAGER"
        if role == "NONE" then role = "DAMAGER" end
        local sortRole = role
        if separate and role == "DAMAGER" then
            sortRole = GetDpsRangeRole(unit, classToken)
        end
        entryCount = entryCount + 1
        local e = _sortEntryPool[entryCount]
        if not e then e = {}; _sortEntryPool[entryCount] = e end
        e.name = name
        e.sortRole = sortRole
        e.class = classToken or ""
        e.isPlayer = UnitIsUnit(unit, "player")
    end

    if kind == "party" then
        if conf.showPlayer then addUnit("player") end
        for i = 1, 4 do addUnit("party" .. i) end
    else
        local num = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, num do addUnit("raid" .. i) end
    end

    -- Sort only the active portion of the pool
    -- table.sort needs a contiguous array — sort _sortEntryPool[1..entryCount]
    -- We use a temporary view: since pool IS contiguous, sort in-place works.
    local entries = _sortEntryPool
    local ec = entryCount
    table.sort(entries, function(a, b)
        -- Only compare within active range (sort may access beyond, but pool entries exist)
        local rA = rolePrio[a.sortRole] or 999
        local rB = rolePrio[b.sortRole] or 999
        if rA ~= rB then return rA < rB end
        if playerFirst and a.isPlayer ~= b.isPlayer then return a.isPlayer == true end
        if a.class ~= b.class then return a.class < b.class end
        return a.name < b.name
    end)

    -- Build name list (reuse tables)
    local nameCount = 0
    for k in pairs(_sortSeen) do _sortSeen[k] = nil end
    for i = 1, ec do
        local n = entries[i].name
        if not _sortSeen[n] then
            _sortSeen[n] = true
            nameCount = nameCount + 1
            _sortNames[nameCount] = n
        end
    end
    -- Trim excess from previous call
    for i = nameCount + 1, #_sortNames do _sortNames[i] = nil end
    return nameCount > 0 and table.concat(_sortNames, ",") or nil
end

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
    f.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")

    -- RegisterForClicks MUST happen here, NOT in initialConfigFunction
    if f.RegisterForClicks then
        f:RegisterForClicks("AnyUp")
    end

    BuildFrameHierarchy(f, kind)
    ApplyFonts(f, kind)
    LayoutText(f, kind)
    LayoutIcons(f, kind)
    if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(f, kind) end

    -- Size hook
    if not f._msufGFSizeHooked then
        f._msufGFSizeHooked = true
        f:HookScript("OnSizeChanged", function(btn)
            LayoutText(btn, btn._msufGFKind or "party")
            LayoutIcons(btn, btn._msufGFKind or "party")
            if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(btn, btn._msufGFKind or "party") end
        end)
    end

    f:SetClampedToScreen(true)

    -- Track in the live-frame registry used by refresh/effect sweeps.
    RegisterTrackedFrame(f, kind)
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
        f._msufGFCachedHpMax = hpMax
    end

    ApplyHealthColor(f, kind, unit)

    -- 3-slot health text (secret-safe: unit passed for UnitHealthPercent)
    do
        local hp    = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        local delim = conf.textDelimiter or " / "
        local rev = conf.hpTextReverse
        local tl = conf.textLeft  or "NONE"
        local tc = conf.textCenter or "NONE"
        local tr = conf.textRight or "NONE"
        if f.textLeftFS then
            local txt = GF.FormatHealthText(tl, hp, hpMax, delim, rev, unit)
            f.textLeftFS:SetText(txt)
            if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
        end
        if f.textCenterFS then
            local txt = GF.FormatHealthText(tc, hp, hpMax, delim, rev, unit)
            f.textCenterFS:SetText(txt)
            if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
        end
        if f.textRightFS then
            local txt = GF.FormatHealthText(tr, hp, hpMax, delim, rev, unit)
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
            f._msufGFCachedPwMax = pwMax
            -- Cache role visibility for power lean path
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if role then
                f._msufGFPowRoleHidden = (role == "TANK" and conf.powerShowTank == false)
                    or (role == "HEALER" and conf.powerShowHealer == false)
                    or (role == "DAMAGER" and conf.powerShowDamager == false) or false
            else
                f._msufGFPowRoleHidden = false
            end
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
                    f.powerTextLeftFS:SetText(GF.FormatPowerText(ptl, pw, pwMax, pDelim, unit))
                    if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
                end
                if f.powerTextCenterFS then
                    f.powerTextCenterFS:SetText(GF.FormatPowerText(ptc, pw, pwMax, pDelim, unit))
                    if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
                end
                if f.powerTextRightFS then
                    f.powerTextRightFS:SetText(GF.FormatPowerText(ptr, pw, pwMax, pDelim, unit))
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
    if f.roleIcon then
        if conf.roleIcon ~= false then
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
        else
            f.roleIcon:Hide()
        end
    end

    -- Raid target marker
    if f.raidIcon then
        if conf.raidMarker ~= false then
            local idx = GetRaidTargetIndex(unit)
            if idx then
                SetRaidTargetIconTexture(f.raidIcon, idx)
                f.raidIcon:Show()
            else
                f.raidIcon:Hide()
            end
        else
            f.raidIcon:Hide()
        end
    end

    -- Leader icon (crown only, no assist)
    if f.leaderIcon then
        if conf.leaderIcon ~= false then
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isLeader then
                local tex, l, r, t, b = GF.GetLeaderTexture(kind)
                f.leaderIcon:SetTexture(tex)
                f.leaderIcon:SetTexCoord(l, r, t, b)
                f.leaderIcon:Show()
            else
                f.leaderIcon:Hide()
            end
        else
            f.leaderIcon:Hide()
        end
    end

    -- Assist icon (separate, shield only)
    if f.assistIcon then
        if conf.assistIcon ~= false then
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
    -- Throttle: skip if scanned very recently (GROUP_ROSTER_UPDATE bursts)
    local now = GetTime()
    if header._msufGFLastScan and (now - header._msufGFLastScan) < 0.05 then return end
    header._msufGFLastScan = now

    -- Protected frames: cannot call SetSize/SetPoint in combat
    local inCombat = InCombatLockdown()
    local conf = GF.GetConf(kind)
    local w = conf.width  or (IsRaidLikeKind(kind) and 80 or 120)
    local h = conf.height or (IsRaidLikeKind(kind) and 32 or 40)

    -- GetChildren() is more reliable than GetAttribute("child"..i) for SecureGroupHeader
    local children = { header:GetChildren() }
    local firstMeasured = false
    for ci = 1, #children do
        local child = children[ci]
        -- Skip non-button children (anchor frames, etc.)
        if child and child.GetAttribute and child:GetAttribute("unit") ~= nil then
            if not child._msufGFBuilt then
                if inCombat then
                    GF._pendingRebuild = true
                    break
                end
                GF_InitButton(child, kind)
            end
            child._msufGFKind = kind
            child.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. tostring(kind))
            -- Force size on every scan (no diff-gate).
            -- Use SetWidth + SetHeight separately (SetSize can be ignored when
            -- SecureGroupHeader has set conflicting anchor points on children).
            if not inCombat then
                child:SetWidth(w)
                child:SetHeight(h)

                -- Clear any backdrop on child frame itself
                -- (SecureUnitButtonTemplate may inherit BackdropTemplate in WoW 12.0)
                if child.SetBackdrop then
                    child:SetBackdrop(nil)
                end

                -- Re-anchor barGroup + force backdrop re-render
                if child.barGroup then
                    child.barGroup:ClearAllPoints()
                    child.barGroup:SetAllPoints(child)
                end

                -- borderFrame
                if child._msufGFBorderFrame then
                    child._msufGFBorderFrame:ClearAllPoints()
                    child._msufGFBorderFrame:SetPoint("TOPLEFT", child.barGroup or child, "TOPLEFT", 0, 0)
                    child._msufGFBorderFrame:SetPoint("BOTTOMRIGHT", child.barGroup or child, "BOTTOMRIGHT", 0, 0)
                end

                -- highlightBorder
                if child._msufGFHighlightBorder then
                    local hofs = child._msufGFHighlightBorder._msufHLOfs or 0
                    child._msufGFHighlightBorder:ClearAllPoints()
                    child._msufGFHighlightBorder:SetPoint("TOPLEFT", child.barGroup or child, "TOPLEFT", -hofs, hofs)
                    child._msufGFHighlightBorder:SetPoint("BOTTOMRIGHT", child.barGroup or child, "BOTTOMRIGHT", hofs, -hofs)
                end

                -- health bar
                local conf = GF.GetConf(kind)
                local inset = ((conf.borderEnabled == true) and math_max(1, conf.borderSize or 1)) or 1
                local powerH = conf.powerHeight or 6
                if child.health then
                    child.health:ClearAllPoints()
                    child.health:SetPoint("TOPLEFT", child.barGroup or child, "TOPLEFT", inset, -inset)
                    child.health:SetPoint("BOTTOMRIGHT", child.barGroup or child, "BOTTOMRIGHT", -inset, powerH > 0 and (powerH + inset) or inset)
                end

                -- power bar
                if child.power then
                    child.power:ClearAllPoints()
                    child.power:SetPoint("BOTTOMLEFT", child.barGroup or child, "BOTTOMLEFT", inset, inset)
                    child.power:SetPoint("BOTTOMRIGHT", child.barGroup or child, "BOTTOMRIGHT", -inset, inset)
                    child.power:SetHeight(powerH)
                end
            end

            if not firstMeasured and header.GetCenter and child.GetCenter then
                firstMeasured = true
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
                if child._msufGFRegisteredUnit ~= unit then
                    child._msufGFRegisteredUnit = unit
                    GF.UpdateButton(child, unit)
                    GF.RegisterUnitEvents(child, unit)
                end
            end
        end
    end
    -- After measuring delta, reposition header
    if not inCombat and GF.SyncHeaderPosition then
        GF.SyncHeaderPosition(kind, nil, header)
    end
end

------------------------------------------------------------------------
-- Grid-center positioning helpers
------------------------------------------------------------------------
GF._previewAnchorFrame = GF._previewAnchorFrame or {}

local function IsRaidLikeKind(kind)
    return kind == "raid" or kind == "mythicraid"
end

local function GetLiveRaidKind()
    return (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
end

local function GetDefaultCenter(kind)
    return IsRaidLikeKind(kind) and -500 or -400, 0
end

local function GetLiveCount(kind)
    local conf = GF.GetConf(kind)
    if IsRaidLikeKind(kind) then
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
    return 5
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

--- Fixed reference count for positioning: deterministic regardless of live party size.
function GF.GetPositionCount(kind)
    local conf = GF.GetConf(kind)
    local upc = conf.unitsPerColumn or 5
    if IsRaidLikeKind(kind) then
        return upc * (conf.maxColumns or 8)
    end
    return upc
end

------------------------------------------------------------------------
-- Anchor frame resolution (same pattern as UF MSUF_ResolveConfiguredAnchorFrame)
------------------------------------------------------------------------
function GF.ResolveAnchorFrame(kind)
    local conf = GF.GetConf(kind)
    local atv = conf.anchorToFrame
    if type(atv) == "string" and atv ~= "" and atv ~= "FREE" then
        -- Unit frame anchoring
        local uf = _G.MSUF_UnitFrames or _G.UnitFrames
        local rel = uf and uf[atv]
        if not rel then rel = _G["MSUF_" .. atv] end
        if rel and rel ~= UIParent and rel ~= WorldFrame and (not rel.IsForbidden or not rel:IsForbidden()) then
            return rel
        end
        -- Custom frame name
        local custom = _G[atv]
        if custom and custom ~= UIParent and custom ~= WorldFrame and (not custom.IsForbidden or not custom:IsForbidden()) then
            return custom
        end
    end
    return UIParent
end

local function PositionHeaderFromGridCenter(kind, header, countOverride)
    if not header then return end
    local conf = GF.GetConf(kind)
    local count = countOverride or GF.GetPositionCount(kind)
    local dx, dy = GF.GetGridMetrics(kind, count)
    local cx, cy = conf.offsetX, conf.offsetY
    if cx == nil or cy == nil then
        cx, cy = GetDefaultCenter(kind)
    end
    local anchorFrame = GF.ResolveAnchorFrame(kind)
    local pt = conf.anchorPoint or conf.point or "CENTER"
    header:ClearAllPoints()
    header:SetPoint(pt, anchorFrame, pt, cx - dx, cy - dy)
end

function GF.SyncHeaderPosition(kind, countOverride, headerOverride)
    if InCombatLockdown() then return end
    local header = headerOverride or (GF.headers and GF.headers[kind])
    if not header then return end
    PositionHeaderFromGridCenter(kind, header, countOverride)
end

------------------------------------------------------------------------
-- SetAttribute diff-cache: skip SetAttribute when value unchanged.
-- SecureGroupHeader re-creates internal child layout on SetAttribute;
-- skipping identical values avoids expensive reflows.
------------------------------------------------------------------------
local _NIL_TOKEN = {} -- sentinel for nil values in cache
local function _GF_SetAttrIfChanged(header, key, value)
    local cache = header._msufAttrCache
    if not cache then cache = {}; header._msufAttrCache = cache end
    local norm = (value == nil) and _NIL_TOKEN or value
    if cache[key] == norm then return false end
    header:SetAttribute(key, value)
    cache[key] = norm
    return true
end

-- Invalidate cache: forces ALL attributes to be re-applied on next setup.
-- Called after zone change when SecureGroupHeader may have lost internal state.
local function _GF_InvalidateAttrCache(header)
    if header then header._msufAttrCache = nil end
end

------------------------------------------------------------------------
-- Party header setup
------------------------------------------------------------------------
local _initCfgNonce = 0
local function SetupPartyHeader()
    if InCombatLockdown() then
        GF._pendingPartyRefresh = true
        return
    end

    local conf = GF.GetConf("party")
    if not conf.enabled then return end

    local parent = _G.PetBattleFrameHider or UIParent
    local header = GF.headers.party

    -- Fresh header on zone-change (fixes C-side layout bug).
    -- Normal rebuilds (settings, roster, /reload) reuse existing header.
    if header and GF._forceRecreateHeaders then
        RetireHeader(header)
        header = nil
        GF.headers.party = nil
    end

    if not header then
        GF._partyHeaderSerial = (GF._partyHeaderSerial or 0) + 1
        local headerName = "MSUF_GFPartyHeader" .. GF._partyHeaderSerial
        header = CreateFrame("Frame", headerName, parent, "SecureGroupHeaderTemplate")
        header._msufGFKind = "party"
        header:SetClampedToScreen(true)
        if header.SetClipsChildren then header:SetClipsChildren(false) end
        header:Hide()
        header:HookScript("OnShow", function(self)
            if not InCombatLockdown() then
                local n = (self:GetAttribute("_msufLayoutNonce") or 0) + 1
                self:SetAttribute("_msufLayoutNonce", n)
            end
        end)
        GF.headers.party = header
    end

    -- CRITICAL: Hide header BEFORE setting attributes.
    -- Each SetAttribute triggers SecureGroupHeader's internal re-layout.
    -- If the header is visible, intermediate layouts render with wrong
    -- child sizes/positions that can persist visually (zone-change bug).
    -- Setting all attributes while hidden ensures ONE clean layout on Show().
    header:Hide()

    -- Attributes (combat-lockdown safe: we checked above)
    local w = conf.width  or 120
    local h = conf.height or 40
    local spacing = conf.spacing or 1
    local growth = conf.growth or "DOWN"

    -- Frame scaling (scales entire frame proportionally)
    if GF.ApplyFrameScale then GF.ApplyFrameScale("party") end
    local fScale = conf._resolvedFrameScale or 1
    if fScale ~= 1 then
        w = math_floor(w * fScale + 0.5)
        h = math_floor(h * fScale + 0.5)
        spacing = math_max(1, math_floor(spacing * fScale + 0.5))
    end

    _GF_SetAttrIfChanged(header, "showParty", true)
    _GF_SetAttrIfChanged(header, "showRaid", false)
    _GF_SetAttrIfChanged(header, "showPlayer", conf.showPlayer and true or false)
    _GF_SetAttrIfChanged(header, "showSolo", conf.showSolo and true or false)
    _GF_SetAttrIfChanged(header, "maxColumns", conf.maxColumns or 1)
    _GF_SetAttrIfChanged(header, "unitsPerColumn", conf.unitsPerColumn or 5)
    _GF_SetAttrIfChanged(header, "template", "SecureUnitButtonTemplate")
    _GF_SetAttrIfChanged(header, "sortDir", "ASC")

    -- Role sort
    if conf.sortByRole then
        if conf.separateMeleeRanged then
            -- NAMELIST: full control (melee/ranged split, playerFirst, class order)
            local nameList = BuildSortNameList("party")
            _GF_SetAttrIfChanged(header, "sortMethod", "NAMELIST")
            _GF_SetAttrIfChanged(header, "nameList", nameList)
            _GF_SetAttrIfChanged(header, "groupBy", nil)
            _GF_SetAttrIfChanged(header, "groupingOrder", nil)
        else
            -- Native ASSIGNEDROLE (most performant, no nameList rebuild)
            _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
            _GF_SetAttrIfChanged(header, "nameList", nil)
            _GF_SetAttrIfChanged(header, "groupBy", "ASSIGNEDROLE")
            _GF_SetAttrIfChanged(header, "groupingOrder", conf.roleOrder or "TANK,HEALER,DAMAGER")
        end
    else
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "nameList", nil)
        _GF_SetAttrIfChanged(header, "groupBy", nil)
        _GF_SetAttrIfChanged(header, "groupingOrder", nil)
    end

    -- Growth direction → point/xOffset/yOffset
    -- SecureGroupHeader already accounts for child width/height; offsets are spacing only.
    if growth == "DOWN" then
        _GF_SetAttrIfChanged(header, "point", "TOP")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", -spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "UP" then
        _GF_SetAttrIfChanged(header, "point", "BOTTOM")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "RIGHT" then
        _GF_SetAttrIfChanged(header, "point", "LEFT")
        _GF_SetAttrIfChanged(header, "xOffset", spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "LEFT" then
        _GF_SetAttrIfChanged(header, "point", "RIGHT")
        _GF_SetAttrIfChanged(header, "xOffset", -spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    end

    -- initialConfigFunction: bake size VALUES into string (EQoL pattern).
    -- When size changes, the string changes → SecureGroupHeader re-runs on all children.
    -- Nonce forces SecureGroupHeader to re-run initialConfigFunction on ALL
    -- existing children (not just new ones). Fixes zone-change size bug.
    _initCfgNonce = _initCfgNonce + 1
    local initCfg = string.format([[
        self:ClearAllPoints()
        self:SetWidth(%.3f)
        self:SetHeight(%.3f)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
        -- nonce %d
    ]], w, h, _initCfgNonce)
    header:SetAttribute("initialConfigFunction", initCfg)

    -- Position (stored offset = grid center)
    PositionHeaderFromGridCenter("party", header)

    header:Show()

    -- EQoL pattern: nudge SecureGroupHeader's internal layout engine
    -- by setting a dummy attribute. Forces complete child re-positioning
    -- even when real attributes haven't changed (zone-change fix).
    local nonce = (header:GetAttribute("_msufLayoutNonce") or 0) + 1
    header:SetAttribute("_msufLayoutNonce", nonce)

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

    local kind = GetLiveRaidKind()
    local conf = GF.GetConf(kind)
    if not conf.enabled then return end

    local parent = _G.PetBattleFrameHider or UIParent
    local header = GF.headers.raid

    if header and GF._forceRecreateHeaders then
        RetireHeader(header)
        header = nil
        GF.headers.raid = nil
    end

    if not header then
        GF._raidHeaderSerial = (GF._raidHeaderSerial or 0) + 1
        local headerName = "MSUF_GFRaidHeader" .. GF._raidHeaderSerial
        header = CreateFrame("Frame", headerName, parent, "SecureGroupHeaderTemplate")
        header._msufGFKind = kind
        header:SetClampedToScreen(true)
        if header.SetClipsChildren then header:SetClipsChildren(false) end
        header:Hide()
        header:HookScript("OnShow", function(self)
            if not InCombatLockdown() then
                local n = (self:GetAttribute("_msufLayoutNonce") or 0) + 1
                self:SetAttribute("_msufLayoutNonce", n)
            end
        end)
        GF.headers.raid = header
    end
    header._msufGFKind = kind

    local w = conf.width  or 80
    local h = conf.height or 32
    local spacing = conf.spacing or 1
    local growth = conf.growth or "DOWN"
    local unitsPerColumn = conf.unitsPerColumn or 5
    local maxColumns = conf.maxColumns or 8

    -- Frame scaling (scales entire frame proportionally)
    if GF.ApplyFrameScale then GF.ApplyFrameScale(kind) end
    local fScale = conf._resolvedFrameScale or 1
    if fScale ~= 1 then
        w = math_floor(w * fScale + 0.5)
        h = math_floor(h * fScale + 0.5)
        spacing = math_max(1, math_floor(spacing * fScale + 0.5))
    end

    -- CRITICAL: Hide before attributes (see SetupPartyHeader comment)
    header:Hide()

    _GF_SetAttrIfChanged(header, "showParty", false)
    _GF_SetAttrIfChanged(header, "showRaid", true)
    _GF_SetAttrIfChanged(header, "showPlayer", true)
    _GF_SetAttrIfChanged(header, "showSolo", false)
    _GF_SetAttrIfChanged(header, "maxColumns", maxColumns)
    _GF_SetAttrIfChanged(header, "unitsPerColumn", unitsPerColumn)
    _GF_SetAttrIfChanged(header, "template", "SecureUnitButtonTemplate")
    _GF_SetAttrIfChanged(header, "sortDir", "ASC")
    -- Group filter: which raid groups to display (1-8)
    local gf = conf.groupFilter
    if type(gf) == "string" and gf ~= "" then
        _GF_SetAttrIfChanged(header, "groupFilter", gf)
    elseif type(gf) == "table" then
        local parts = {}
        for i = 1, 8 do
            if gf[i] ~= false then parts[#parts + 1] = tostring(i) end
        end
        if #parts > 0 and #parts < 8 then
            _GF_SetAttrIfChanged(header, "groupFilter", table.concat(parts, ","))
        else
            _GF_SetAttrIfChanged(header, "groupFilter", nil)
        end
    else
        _GF_SetAttrIfChanged(header, "groupFilter", nil)
    end
    -- Sort mode: INDEX / ROLE / GROUP / GROUP_ROLE / NAME
    -- Migration: sortByRole boolean → sortMode string
    local sortMode = conf.sortMode
    if not sortMode then
        sortMode = conf.sortByRole and "ROLE" or "INDEX"
    end

    if sortMode == "ROLE" then
        if conf.separateMeleeRanged then
            local nameList = BuildSortNameList("raid")
            _GF_SetAttrIfChanged(header, "sortMethod", "NAMELIST")
            _GF_SetAttrIfChanged(header, "nameList", nameList)
            _GF_SetAttrIfChanged(header, "groupBy", nil)
            _GF_SetAttrIfChanged(header, "groupingOrder", nil)
        else
            _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
            _GF_SetAttrIfChanged(header, "nameList", nil)
            _GF_SetAttrIfChanged(header, "groupBy", "ASSIGNEDROLE")
            _GF_SetAttrIfChanged(header, "groupingOrder", conf.roleOrder or "TANK,HEALER,DAMAGER")
        end
    elseif sortMode == "GROUP" then
        -- Group by raid group number (1-8), index within each
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "nameList", nil)
        _GF_SetAttrIfChanged(header, "groupBy", "GROUP")
        _GF_SetAttrIfChanged(header, "groupingOrder", "1,2,3,4,5,6,7,8")
    elseif sortMode == "GROUP_ROLE" then
        -- Group by raid group, then by role within each group
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "nameList", nil)
        _GF_SetAttrIfChanged(header, "groupBy", "GROUP")
        _GF_SetAttrIfChanged(header, "groupingOrder", "1,2,3,4,5,6,7,8")
        -- Note: within-group role sorting requires Blizzard's native prioritization
        -- which sorts TANK > HEALER > DAMAGER within each group automatically
    elseif sortMode == "NAME" then
        _GF_SetAttrIfChanged(header, "sortMethod", "NAME")
        _GF_SetAttrIfChanged(header, "nameList", nil)
        _GF_SetAttrIfChanged(header, "groupBy", nil)
        _GF_SetAttrIfChanged(header, "groupingOrder", nil)
    else
        -- INDEX (default): flat, no grouping
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "nameList", nil)
        _GF_SetAttrIfChanged(header, "groupBy", nil)
        _GF_SetAttrIfChanged(header, "groupingOrder", nil)
    end

    -- Growth
    local colGrowth = "DOWN"
    if growth == "DOWN" then
        _GF_SetAttrIfChanged(header, "point", "TOP")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", -spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "UP" then
        _GF_SetAttrIfChanged(header, "point", "BOTTOM")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "RIGHT" then
        _GF_SetAttrIfChanged(header, "point", "LEFT")
        _GF_SetAttrIfChanged(header, "xOffset", spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "LEFT" then
        _GF_SetAttrIfChanged(header, "point", "RIGHT")
        _GF_SetAttrIfChanged(header, "xOffset", -spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    end

    -- Nonce forces SecureGroupHeader to re-run initialConfigFunction on ALL
    -- existing children (not just new ones). Fixes zone-change size bug.
    _initCfgNonce = _initCfgNonce + 1
    local initCfg = string.format([[
        self:ClearAllPoints()
        self:SetWidth(%.3f)
        self:SetHeight(%.3f)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
        -- nonce %d
    ]], w, h, _initCfgNonce)
    header:SetAttribute("initialConfigFunction", initCfg)

    PositionHeaderFromGridCenter(kind, header)

    header:Show()

    -- EQoL pattern: nudge layout (see SetupPartyHeader comment)
    local nonce = (header:GetAttribute("_msufLayoutNonce") or 0) + 1
    header:SetAttribute("_msufLayoutNonce", nonce)

    C_Timer.After(0, function()
        ScanHeaderChildren(header, kind)
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
    if frame.SetParent then frame:SetParent(hp) end
    if not frame._msufGFHideHooked then
        frame._msufGFHideHooked = true
        if frame.Show then
            hooksecurefunc(frame, "Show", function(f)
                if f._msufGFHidden then
                    if InCombatLockdown() then
                        GF._pendingBlizzardDisable = true
                        return
                    end
                    if f.SetParent then f:SetParent(hp) end
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
    local raidConf  = GF.GetConf(GetLiveRaidKind())
    if partyConf.enabled then
        HideFrameLocked(_G.PartyFrame)
        HideFrameLocked(_G.CompactPartyFrame)
        HideFrameLocked(_G.CompactPartyFrameTitle)
    end
    if raidConf.enabled then
        HideFrameLocked(_G.CompactRaidFrameContainer)
        if _G.CompactRaidFrameManager_SetSetting then
            _G.CompactRaidFrameManager_SetSetting("IsShown", "0")
        end
    end
end

function GF.RestoreBlizzardFrames()
    -- Undo reparenting
    for _, name in pairs({ "PartyFrame", "CompactPartyFrame", "CompactPartyFrameTitle", "CompactRaidFrameContainer" }) do
        local f = _G[name]
        if f and f._msufGFHidden then
            f._msufGFHidden = nil
            if f.SetParent and not InCombatLockdown() then f:SetParent(UIParent) end
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

    -- Health bar value + color (respects GF-independent barMode)
    if f.health then
        f.health:SetMinMaxValues(0, 100)
        f.health:SetValue(math_floor(hpPct * 100))
        local gfMode = conf.gfBarMode
        local mode
        if gfMode and gfMode ~= "GLOBAL" then
            mode = gfMode
        else
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            local gm = cache and cache.barMode
            if gm == "dark" or gm == "unified" then mode = gm
            else mode = conf.healthColorMode or "CLASS" end
        end
        if mode == "dark" then
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            f.health:SetStatusBarColor(conf.gfDarkR or (cache and cache.darkBarR) or 0, conf.gfDarkG or (cache and cache.darkBarG) or 0, conf.gfDarkB or (cache and cache.darkBarB) or 0, 1)
        elseif mode == "unified" then
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            f.health:SetStatusBarColor(conf.gfUnifiedR or (cache and cache.unifiedBarR) or 0.10, conf.gfUnifiedG or (cache and cache.unifiedBarG) or 0.60, conf.gfUnifiedB or (cache and cache.unifiedBarB) or 0.90, 1)
        elseif mode == "GRADIENT" then
            local r = hpPct > 0.5 and (1 - (hpPct - 0.5) * 2) or 1
            local g = hpPct > 0.5 and 1 or (hpPct * 2)
            f.health:SetStatusBarColor(r, g, 0, 1)
        elseif mode == "CUSTOM" then
            f.health:SetStatusBarColor(conf.healthCustomR or 0.2, conf.healthCustomG or 0.8, conf.healthCustomB or 0.2, 1)
        else
            local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
            if type(fastClass) == "function" then
                local cr, cg, cb = fastClass(cls)
                if cr then f.health:SetStatusBarColor(cr, cg, cb, 1)
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
    -- Per-GF absorb setting resolver (mirrors _GF_GetAbsorbSetting in Effects)
    local gfKind = f._msufGFKind or "party"
    local gfDbKey = GF.GetConfigDBKey and GF.GetConfigDBKey(gfKind) or ((gfKind == "raid") and "gf_raid" or "gf_party")
    local gfDb = _G.MSUF_DB and _G.MSUF_DB[gfDbKey]
    local gfHasOvr = gfDb and gfDb.hlOverride
    local function _pResolve(key)
        if gfHasOvr and gfDb[key] ~= nil then return gfDb[key] end
        return gen and gen[key]
    end
    if f.incomingHealBar then
        local hpEnabled = conf.healPredEnabled
        if hpEnabled == nil then hpEnabled = not gen or gen.enableHealPrediction ~= false end
        if hpEnabled ~= false then
            f.incomingHealBar:SetMinMaxValues(0, 100)
            f.incomingHealBar:SetValue(math_min(hpVal + 20, 100))
            local r, g, b = 0.0, 1.0, 0.4
            if gen then
                if type(gen.healPredColorR) == "number" then r = gen.healPredColorR end
                if type(gen.healPredColorG) == "number" then g = gen.healPredColorG end
                if type(gen.healPredColorB) == "number" then b = gen.healPredColorB end
            end
            f.incomingHealBar:SetStatusBarColor(r, g, b, 0.45)
            f.incomingHealBar:Show()
        else
            f.incomingHealBar:Hide()
        end
    end
    -- Absorb enabled: mirrors _GF_IsAbsorbEnabled — hlOverride-aware
    local absorbBarVisible
    do
        local atm = tonumber(_pResolve("absorbTextMode"))
        if atm then
            absorbBarVisible = (atm == 2 or atm == 3)
        else
            local eab = _pResolve("enableAbsorbBar")
            if eab ~= nil then absorbBarVisible = (eab ~= false) else absorbBarVisible = true end
        end
    end
    -- Absorb anchoring: SetReverseFill from absorbAnchorMode (per-GF → general)
    if absorbBarVisible or (f.healAbsorbBar and conf.healAbsorbEnabled ~= false) then
        local anchorMode = tonumber(_pResolve("absorbAnchorMode")) or 2
        local absorbReverse, healReverse
        if anchorMode == 1 then
            absorbReverse = false; healReverse = true
        elseif anchorMode == 5 then
            local hpReverse = f.health and f.health.GetReverseFill and f.health:GetReverseFill()
            absorbReverse = not hpReverse; healReverse = hpReverse and true or false
        else
            absorbReverse = true; healReverse = false
        end
        if f.absorbBar and f.absorbBar.SetReverseFill then f.absorbBar:SetReverseFill(absorbReverse and true or false) end
        if f.healAbsorbBar and f.healAbsorbBar.SetReverseFill then f.healAbsorbBar:SetReverseFill(healReverse and true or false) end
        if f.incomingHealBar and f.incomingHealBar.SetReverseFill then f.incomingHealBar:SetReverseFill(false) end
    end
    if f.absorbBar and absorbBarVisible then
        f.absorbBar:SetMinMaxValues(0, 100)
        f.absorbBar:SetValue(15 + index * 5)
        local r, g, b = 0.8, 0.9, 1.0
        if gen then
            if type(gen.absorbBarColorR) == "number" then r = gen.absorbBarColorR end
            if type(gen.absorbBarColorG) == "number" then g = gen.absorbBarColorG end
            if type(gen.absorbBarColorB) == "number" then b = gen.absorbBarColorB end
        end
        local a = tonumber(_pResolve("absorbBarOpacity")) or 0.6
        f.absorbBar:SetStatusBarColor(r, g, b, a)
        f.absorbBar:Show()
    elseif f.absorbBar then
        f.absorbBar:Hide()
    end
    -- Heal absorb: independent enabled check (NOT gated on absorb bar)
    local healAbsorbVisible = conf.healAbsorbEnabled ~= false
    if f.healAbsorbBar and healAbsorbVisible then
        f.healAbsorbBar:SetMinMaxValues(0, 100)
        f.healAbsorbBar:SetValue(math_min(8, hpVal))
        local r, g, b = 1.0, 0.4, 0.4
        if gen then
            if type(gen.healAbsorbBarColorR) == "number" then r = gen.healAbsorbBarColorR end
            if type(gen.healAbsorbBarColorG) == "number" then g = gen.healAbsorbBarColorG end
            if type(gen.healAbsorbBarColorB) == "number" then b = gen.healAbsorbBarColorB end
        end
        local a = tonumber(_pResolve("healAbsorbBarOpacity")) or 0.7
        f.healAbsorbBar:SetStatusBarColor(r, g, b, a)
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
    if f.roleIcon then
        if conf.roleIcon ~= false then
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
    count = count or ((kind == "raid" or kind == "mythicraid") and 20 or 5)
    local conf = GF.GetConf(kind)
    local _, _, totalW, totalH, w, h, spacing, growth, upc = GF.GetGridMetrics(kind, count)
    local key = kind

    GF._previewActive[key] = true

    if not GF._previewFrames[key] then GF._previewFrames[key] = {} end
    local frames = GF._previewFrames[key]

    -- Container at same position as real header
    local anchorParent = GF._previewAnchorFrame and GF._previewAnchorFrame[key]
    local parent = anchorParent or UIParent

    if not GF._previewContainer then GF._previewContainer = {} end
    local container = GF._previewContainer[key]
    if not container then
        container = CreateFrame("Frame", "MSUF_GFPreviewContainer_" .. key, parent)
        container:EnableMouse(false)
        GF._previewContainer[key] = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end

    -- Position container identically to PositionHeaderFromGridCenter
    -- Use GetPositionCount (not preview count) for consistent positioning
    local posCount = GF.GetPositionCount(kind)
    local _, _, posTotalW, posTotalH = GF.GetGridMetrics(kind, posCount)
    local cx, cy = conf.offsetX, conf.offsetY
    if cx == nil or cy == nil then cx, cy = GetDefaultCenter(kind) end
    container:SetSize(math_max(posTotalW, 1), math_max(posTotalH, 1))
    container:ClearAllPoints()
    if anchorParent then
        container:SetPoint("CENTER", parent, "CENTER", 0, 0)
    else
        local af = GF.ResolveAnchorFrame(kind)
        -- (cx, cy) is grid center → anchor container CENTER there directly
        container:SetPoint("CENTER", af, "CENTER", cx, cy)
    end
    container:Show()

    -- Resolve anchor point + offsets (same as SetupPartyHeader / SetupRaidHeader)
    local anchorPt, xOff, yOff, colAnchor
    if growth == "DOWN" then
        anchorPt = "TOP"; xOff = 0; yOff = -spacing; colAnchor = "LEFT"
    elseif growth == "UP" then
        anchorPt = "BOTTOM"; xOff = 0; yOff = spacing; colAnchor = "LEFT"
    elseif growth == "RIGHT" then
        anchorPt = "LEFT"; xOff = spacing; yOff = 0; colAnchor = "TOP"
    elseif growth == "LEFT" then
        anchorPt = "RIGHT"; xOff = -spacing; yOff = 0; colAnchor = "TOP"
    else
        anchorPt = "TOP"; xOff = 0; yOff = -spacing; colAnchor = "LEFT"
    end

    for i = 1, count do
        local f = frames[i]
        if not f then
            f = CreateFrame("Button", "MSUF_GFPreview_" .. key .. "_" .. i, container, "BackdropTemplate")
            f:SetSize(w, h)
            f._msufGFKind = kind
            f._msufIsGroupFrame = true
            f._msufGFIsPreviewFrame = true
            f.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
            BuildFrameHierarchy(f, kind)
            ApplyFonts(f, kind)
            LayoutText(f, kind)
            LayoutIcons(f, kind)
            if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(f, kind) end
            frames[i] = f
        end
        if f:GetParent() ~= container then f:SetParent(container) end

        f:SetSize(w, h)
        f:ClearAllPoints()

        -- Replicate SecureGroupHeader child layout (corner-anchored)
        local row = (i - 1) % upc
        local col = math_floor((i - 1) / upc)

        if growth == "DOWN" then
            f:SetPoint("TOPLEFT", container, "TOPLEFT", col * (w + spacing), -row * (h + spacing))
        elseif growth == "UP" then
            f:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", col * (w + spacing), row * (h + spacing))
        elseif growth == "RIGHT" then
            f:SetPoint("TOPLEFT", container, "TOPLEFT", row * (w + spacing), -col * (h + spacing))
        elseif growth == "LEFT" then
            f:SetPoint("TOPRIGHT", container, "TOPRIGHT", -row * (w + spacing), -col * (h + spacing))
        end

        GF.ApplyPreviewData(f, i, kind)
    end

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
    if frames then
        for i = 1, #frames do
            if frames[i] then
                GF.ClearPreviewData(frames[i])
                frames[i]:Hide()
            end
        end
    end
    local container = GF._previewContainer and GF._previewContainer[kind]
    if container then container:Hide() end
end

local function GF_PreviewsAllowed()
    if _G.MSUF_UnitEditModeActive == true then
        return true
    end
    local panel = _G.MSUF_GFOptionsPanel
    if panel and panel.IsShown and panel:IsShown() then
        return true
    end
    return false
end

function GF.HideOrphanedPreviews()
    if GF_PreviewsAllowed() then return false end
    local hidden = false
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        local active = GF._previewActive and GF._previewActive[kind]
        local container = GF._previewContainer and GF._previewContainer[kind]
        if active or (container and container.IsShown and container:IsShown()) then
            GF.HidePreview(kind)
            hidden = true
        end
    end
    return hidden
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
    local _, _, totalW, totalH, w, h, spacing, growth, upc = GF.GetGridMetrics(kind, count)

    -- Update container position (grid center = stored offset)
    local container = GF._previewContainer and GF._previewContainer[kind]
    if container then
        local posCount = GF.GetPositionCount(kind)
        local _, _, posTotalW, posTotalH = GF.GetGridMetrics(kind, posCount)
        local cx, cy = conf.offsetX, conf.offsetY
        if cx == nil or cy == nil then cx, cy = GetDefaultCenter(kind) end
        local anchorParent = GF._previewAnchorFrame and GF._previewAnchorFrame[kind]
        container:SetSize(math_max(posTotalW, 1), math_max(posTotalH, 1))
        container:ClearAllPoints()
        if anchorParent then
            container:SetPoint("CENTER", anchorParent, "CENTER", 0, 0)
        else
            local af = GF.ResolveAnchorFrame(kind)
            container:SetPoint("CENTER", af, "CENTER", cx, cy)
        end
    end

    for i = 1, #frames do
        local f = frames[i]
        if f and f:IsShown() then
            if container and f:GetParent() ~= container then f:SetParent(container) end
            f:SetSize(w, h)
            if f.barGroup then f.barGroup:SetSize(w, h) end
            f:ClearAllPoints()
            local row = (i - 1) % upc
            local col = math_floor((i - 1) / upc)
            local c = container or UIParent
            if growth == "DOWN" then
                f:SetPoint("TOPLEFT", c, "TOPLEFT", col * (w + spacing), -row * (h + spacing))
            elseif growth == "UP" then
                f:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", col * (w + spacing), row * (h + spacing))
            elseif growth == "RIGHT" then
                f:SetPoint("TOPLEFT", c, "TOPLEFT", row * (w + spacing), -col * (h + spacing))
            elseif growth == "LEFT" then
                f:SetPoint("TOPRIGHT", c, "TOPRIGHT", -row * (w + spacing), -col * (h + spacing))
            end
        end
    end
end

------------------------------------------------------------------------
-- Refresh all GF frames
------------------------------------------------------------------------
function GF.RefreshAll()
    GF.ForEachFrame(function(f)
        local unit = f.unit
        if unit and UnitExists(unit) then
            GF.UpdateButton(f, unit)
        end
    end)
end

function GF.RebuildAll()
    if InCombatLockdown() then
        GF._pendingRebuild = true
        return
    end
    GF.HideOrphanedPreviews()
    local partyConf = GF.GetConf("party")
    local raidKind = GetLiveRaidKind()
    local raidConf  = GF.GetConf(raidKind)

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
    GF.RefreshPreviewLayout("mythicraid")
    -- Deferred: after SecureGroupHeader repositions children, re-apply visuals (geometry, bars, text)
    C_Timer.After(0.05, function()
        -- Force event re-registration (picks up aura/dispel toggle changes)
        for _, kind in pairs({"party"}) do
            local hdr = GF.headers[kind]
            if hdr then
                local kids = { hdr:GetChildren() }
                for ci = 1, #kids do
                    local ch = kids[ci]
                    if ch and ch._msufGFBuilt then
                        ch._msufGFRegisteredUnit = nil
                    end
                end
                ScanHeaderChildren(hdr, kind)
            end
        end
        local hdr = GF.headers.raid
        if hdr then
            local kids = { hdr:GetChildren() }
            for ci = 1, #kids do
                local ch = kids[ci]
                if ch and ch._msufGFBuilt then
                    ch._msufGFRegisteredUnit = nil
                end
            end
            ScanHeaderChildren(hdr, GetLiveRaidKind())
        end
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
    local raidKind = GetLiveRaidKind()
    local raidConf  = GF.GetConf(raidKind)

    -- Party header
    if GF.headers.party then
        if partyConf.enabled and not inRaid then
            GF.SyncHeaderPosition("party")
            GF.headers.party:Show()
            C_Timer.After(0, function()
                if GF.headers.party then ScanHeaderChildren(GF.headers.party, "party") end
            end)
            C_Timer.After(0.5, function()
                if GF.headers.party and not InCombatLockdown() then
                    ScanHeaderChildren(GF.headers.party, "party")
                end
            end)
        else
            GF.headers.party:Hide()
        end
    end

    -- Raid header
    if GF.headers.raid then
        if raidConf.enabled and inRaid then
            GF.SyncHeaderPosition(raidKind, nil, GF.headers.raid)
            GF.headers.raid:Show()
            C_Timer.After(0, function()
                if GF.headers.raid then ScanHeaderChildren(GF.headers.raid, GetLiveRaidKind()) end
            end)
            C_Timer.After(0.5, function()
                if GF.headers.raid and not InCombatLockdown() then
                    ScanHeaderChildren(GF.headers.raid, GetLiveRaidKind())
                end
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
        local raidConf  = GF.GetConf(GetLiveRaidKind())
        if partyConf.enabled or raidConf.enabled then
            GF.RebuildAll()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Switch party/raid visibility + rescan children
        GF.UpdateGroupVisibility()

        -- Refresh sort order when role-sorting with NAMELIST is active
        -- (SecureGroupHeader auto-sorts for native groupBy modes,
        -- but NAMELIST sort needs manual refresh on roster changes)
        local needSortRefresh = false
        local partyConf = GF.GetConf("party")
        local raidConf  = GF.GetConf(GetLiveRaidKind())
        if partyConf.separateMeleeRanged and partyConf.sortByRole then
            needSortRefresh = true
        end
        local raidSort = raidConf.sortMode or (raidConf.sortByRole and "ROLE" or "INDEX")
        if raidConf.separateMeleeRanged and raidSort == "ROLE" then
            needSortRefresh = true
        end
        if needSortRefresh then
            if InCombatLockdown() then
                GF._pendingRebuild = true
            else
                C_Timer.After(0.2, function()
                    if not InCombatLockdown() then
                        GF.RebuildAll()
                    else
                        GF._pendingRebuild = true
                    end
                end)
            end
        end

        -- Invalidate group size cache (dynamic aura scale)
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end

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
        -- Force rebuild if headers don't exist (mid-combat /reload recovery)
        local needRebuild = GF._pendingRebuild
        if not GF.headers.party and not GF.headers.raid then needRebuild = true end
        if needRebuild then
            GF._pendingRebuild = nil
            GF.RebuildAll()
        end
        if GF._pendingVisibilityUpdate then
            GF._pendingVisibilityUpdate = nil
            GF.UpdateGroupVisibility()
        end

        -- EQoL pattern: refresh range fade on combat end.
        -- UNIT_IN_RANGE_UPDATE fires less frequently OOC;
        -- sweep all frames to ensure correct alpha after combat.
        C_Timer.After(0.1, function()
            local updateRange = _G.MSUF_GF_UpdateRange
            if not updateRange then return end
            GF.ForEachFrame(function(f)
                if f.unit and f:IsVisible() then
                    updateRange(f, f.unit)
                end
            end)
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        GF.EnsureDB()
        local partyConf = GF.GetConf("party")
        local raidConf  = GF.GetConf(GetLiveRaidKind())
        if partyConf.enabled or raidConf.enabled then
            -- Only recreate headers on actual zone transitions (not /reload).
            -- /reload creates everything fresh anyway, no C-side state bug.
            if not isLogin and not isReload then
                GF._forceRecreateHeaders = true
            end
            if GF._zoneFixTicker then
                GF._zoneFixTicker:Cancel()
                GF._zoneFixTicker = nil
            end
            C_Timer.After(0.3, function()
                if not InCombatLockdown() then
                    -- Auto-switch raid layout per situation (Mythic/Normal/OpenWorld)
                    if GF.AutoSwitchRaidLayout then
                        GF.AutoSwitchRaidLayout()
                    end
                    GF.RebuildAll()
                    GF._forceRecreateHeaders = nil
                end
            end)
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED" then
        if InCombatLockdown() then
            GF._pendingRebuild = true
            GF._pendingVisibilityUpdate = true
        else
            if GF.AutoSwitchRaidLayout then
                GF.AutoSwitchRaidLayout()
            end
            GF.RebuildAll()
            GF.UpdateGroupVisibility()
        end
    end
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("GROUP_ROSTER_UPDATE")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
ef:SetScript("OnEvent", OnEvent)
GF._eventFrame = ef

------------------------------------------------------------------------
-- Global exports
------------------------------------------------------------------------
--- Convenience refresh (called by EM2 popup Apply — syncs text/font/layout)
function GF.Refresh()
    if GF.MarkAllDirty then GF.MarkAllDirty(0x3F) end -- DIRTY_ALL
    if GF.RefreshVisuals then GF.RefreshVisuals() end
end

_G.MSUF_GF_ShowPreview      = GF.ShowPreview
_G.MSUF_GF_HidePreview      = GF.HidePreview
_G.MSUF_GF_RebuildAll        = GF.RebuildAll
_G.MSUF_GF_RefreshAll        = GF.RefreshAll
_G.MSUF_GF_Refresh           = GF.Refresh
_G.MSUF_GF_RefreshPreviewLayout = GF.RefreshPreviewLayout
_G.MSUF_GF_DisableBlizzard   = GF.DisableBlizzardFrames
_G.MSUF_GF_RestoreBlizzard   = GF.RestoreBlizzardFrames
_G.MSUF_GF_UpdateButton      = GF.UpdateButton
_G.MSUF_GF_InitButton        = GF_InitButton
_G.MSUF_GF_UpdateGroupVisibility = GF.UpdateGroupVisibility

-- Perfy idle-diagnosis exports
_G.MSUF_GF_ScanHeaderChildren = ScanHeaderChildren
_G.MSUF_GF_CoreEventFrame     = ef

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
                if GF.InvalidateConfCache then GF.InvalidateConfCache() end
                C_Timer.After(0.1, function()
                    GF.RebuildAll()
                end)
            end
        end
    end)
end

-- Debug: /run MSUF_GF_DebugSizes()
function _G.MSUF_GF_DebugSizes()
    local GF = _G.MSUF_NS and _G.MSUF_NS.GF or {}
    local header = GF.headers and GF.headers["party"]
    if not header then print("No party header"); return end
    local children = { header:GetChildren() }
    for ci = 1, #children do
        local child = children[ci]
        if child and child.GetAttribute and child:GetAttribute("unit") then
            local unit = child:GetAttribute("unit") or "?"
            local cw, ch = child:GetSize()
            -- Enumerate ALL child frames and regions
            local subFrames = { child:GetChildren() }
            local subRegions = { child:GetRegions() }
            print(("[%d] %s sz=%.0fx%.0f children=%d regions=%d"):format(ci, unit, cw, ch, #subFrames, #subRegions))
            for si, sf in ipairs(subFrames) do
                local sw, sh = sf:GetSize()
                local shown = sf:IsShown()
                local np = sf:GetNumPoints()
                local name = sf:GetName() or sf:GetObjectType()
                -- check if it extends beyond parent
                local sl, st, sb, sr = sf:GetLeft(), sf:GetTop(), sf:GetBottom(), sf:GetRight()
                local cl, ct, cb, cr = child:GetLeft(), child:GetTop(), child:GetBottom(), child:GetRight()
                local extends = ""
                if sl and cl and sr and cr and st and ct and sb and cb then
                    if sl < cl - 1 or sr > cr + 1 or st > ct + 1 or sb < cb - 1 then
                        extends = " *** EXTENDS OUTSIDE ***"
                    end
                end
                if shown then
                    print(("  F[%d] %s sz=%.0fx%.0f pts=%d%s"):format(si, name, sw, sh, np, extends))
                end
            end
            for si, sr in ipairs(subRegions) do
                local sw, sh = 0, 0
                if sr.GetSize then sw, sh = sr:GetSize() end
                local shown = sr:IsShown()
                local ot = sr:GetObjectType()
                local sl, st, sb, sright = sr:GetLeft(), sr:GetTop(), sr:GetBottom(), sr:GetRight()
                local cl, ct, cb, cr = child:GetLeft(), child:GetTop(), child:GetBottom(), child:GetRight()
                local extends = ""
                if sl and cl and sright and cr and st and ct and sb and cb then
                    if sl < cl - 1 or sright > cr + 1 or st > ct + 1 or sb < cb - 1 then
                        extends = " *** EXTENDS ***"
                    end
                end
                if shown and extends ~= "" then
                    print(("  R[%d] %s sz=%.0fx%.0f%s"):format(si, ot, sw, sh, extends))
                end
            end
        end
    end
end
