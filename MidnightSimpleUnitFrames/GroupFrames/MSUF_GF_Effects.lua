-- MSUF_GF_Effects.lua — Group Frames Phase 2: Events + Effects
-- Per-frame RegisterUnitEvent, range fade (Grid2 pattern), aggro/dispel/target
-- borders, status icons, AFK/DND text, UNIT_AURA coalescing
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local UnitIsUnit = _G.UnitIsUnit
local UnitIsPlayer = _G.UnitIsPlayer
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
local UnitThreatSituation = _G.UnitThreatSituation
local UnitPhaseReason = _G.UnitPhaseReason
local UnitHasIncomingResurrection = _G.UnitHasIncomingResurrection
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local GetReadyCheckStatus = _G.GetReadyCheckStatus
local C_IncomingSummon = _G.C_IncomingSummon
local C_Timer = _G.C_Timer
local AuraUtil = _G.AuraUtil
local CreateFrame = _G.CreateFrame
local IsSpellInRange = _G.C_Spell and _G.C_Spell.IsSpellInRange
local CheckInteractDistance = _G.CheckInteractDistance
local IsPlayerSpell = _G.IsPlayerSpell
local PowerBarColor = _G.PowerBarColor
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local UnitGetTotalAbsorbs     = _G.UnitGetTotalAbsorbs
local UnitGetIncomingHeals    = _G.UnitGetIncomingHeals
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local math_floor = math.floor
local math_max   = math.max
local pairs = pairs
local type = type
local IsAltKeyDown     = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown   = _G.IsShiftKeyDown
local UnitInRaid       = _G.UnitInRaid
local GetRaidRosterInfo = _G.GetRaidRosterInfo
local strmatch         = string.match

------------------------------------------------------------------------
-- Highlight value resolver: Bars hl* keys → old GF conf key fallback
-- Bars system uses hlAggroEnabled, hlAggroColorR, etc.
-- Old GF DB uses aggroEnabled, aggroR, etc.
-- GetHighlightVal checks conf.hlOverride → general. If nil, we fall
-- back to the old GF per-kind conf keys so existing configs still work.
------------------------------------------------------------------------
local _HL_FALLBACK = {
    hlAggroEnabled  = "aggroEnabled",
    hlAggroColorR   = "aggroR",
    hlAggroColorG   = "aggroG",
    hlAggroColorB   = "aggroB",
    hlAggroMode     = "aggroMode",
    hlDispelEnabled = "dispelEnabled",
    hlTargetEnabled = "targetIndicator",
    hlTargetColorR  = "targetR",
    hlTargetColorG  = "targetG",
    hlTargetColorB  = "targetB",
}

local function HLVal(kind, key)
    local v = GF.GetHighlightVal(kind, key)
    if v ~= nil then return v end
    local fallback = _HL_FALLBACK[key]
    if fallback then
        local conf = GF.GetConf(kind)
        if conf[fallback] ~= nil then return conf[fallback] end
    end
    return nil
end

------------------------------------------------------------------------
-- Range check spells (Grid2 pattern — IsSpellInRange, NOT secret)
------------------------------------------------------------------------
local _playerClass = select(2, UnitClass("player"))
local _rangeFriendlySpell
local _rangeNeedsTicker = false

do
    local function IVS(id) return IsPlayerSpell and IsPlayerSpell(id) and id end
    local spells = {
        DRUID       = function() return 8936 end,       -- Regrowth
        PRIEST      = function() return 2061 end,       -- Flash Heal
        SHAMAN      = function() return 8004 end,       -- Healing Surge
        PALADIN     = function() return 19750 end,      -- Flash of Light
        MONK        = function() return 116670 end,     -- Vivify
        EVOKER      = function() return 355913 end,     -- Emerald Blossom
        WARLOCK     = function() return 20707 end,      -- Soulstone
        MAGE        = function() return 1459 end,       -- Arcane Intellect
        HUNTER      = function() return nil end,
        ROGUE       = function() return IVS(36554) or IVS(57934) end, -- Shadowstep / Tricks
        DEATHKNIGHT = function() return IVS(47541) end, -- Death Coil
        WARRIOR     = function() return nil end,
        DEMONHUNTER = function() return nil end,
    }
    local getter = spells[_playerClass]
    if getter then _rangeFriendlySpell = getter() end
    _rangeNeedsTicker = (_rangeFriendlySpell == nil)
end

------------------------------------------------------------------------
-- Dispel type colors (fallback for pre-Midnight clients)
------------------------------------------------------------------------
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Bleed   = { 0.80, 0.10, 0.10 },
}

local function GetDispelColor(dispelName)
    local c = DISPEL_COLORS[dispelName]
    if c then return c[1], c[2], c[3] end
    -- Blizzard color objects
    local obj = _G["DEBUFF_TYPE_" .. (dispelName or ""):upper() .. "_COLOR"]
    if obj then
        if obj.GetRGB then return obj:GetRGB() end
        if obj.r then return obj.r, obj.g, obj.b end
    end
    return nil
end

------------------------------------------------------------------------
-- Status icon textures
------------------------------------------------------------------------
local ICON_TEX = {
    ready      = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notReady   = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting    = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    resurrect  = "Interface\\RaidFrame\\Raid-Icon-Rez",
    phase      = "Interface\\TargetingFrame\\UI-PhasingIcon",
}
local SUMMON_PENDING  = 1
local SUMMON_ACCEPTED = 2
local SUMMON_DECLINED = 3
local SUMMON_TEX = {
    [1] = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    [2] = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    [3] = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}

------------------------------------------------------------------------
-- Role icon coords
------------------------------------------------------------------------
local ROLE_TEXTURES = {
    TANK    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    HEALER  = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    DAMAGER = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
}
local ROLE_COORDS = {
    TANK    = { 0,     19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

------------------------------------------------------------------------
-- UNIT_AURA coalescing
------------------------------------------------------------------------
local _auraDirty = {} -- [frame] = true
local _auraFlushScheduled = false

local function FlushAuraDirty()
    _auraFlushScheduled = false
    for f in pairs(_auraDirty) do
        _auraDirty[f] = nil
        if f._msufIsGroupFrame and f.unit and UnitExists(f.unit) then
            GF._UpdateDispel(f, f.unit)
            if GF.UpdateSpellIndicators then GF.UpdateSpellIndicators(f, f.unit) end
            if GF.UpdateFrameAuras then GF.UpdateFrameAuras(f, f.unit) end
        end
    end
end

local function MarkAuraDirty(f)
    _auraDirty[f] = true
    if not _auraFlushScheduled then
        _auraFlushScheduled = true
        C_Timer.After(0, FlushAuraDirty)
    end
end

------------------------------------------------------------------------
-- Range check (IsSpellInRange primary, Grid2 chain)
------------------------------------------------------------------------
local _rfMul = _G.MSUF_RangeFadeMul
local MaybeWakeRangeRecoveryTicker

local function NormalizeRangeResult(v)
    if v == nil then return nil end
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return v and true or false
end

local function CheckRange(f, unit)
    if not unit then return nil end
    if UnitIsUnit(unit, "player") then return true end
    if UnitPhaseReason and UnitPhaseReason(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return true end -- show dead at full alpha

    -- Primary: IsSpellInRange (NOT secret, 1 C-call)
    -- WoW can return 1/0 here, not only true/false.
    if _rangeFriendlySpell and IsSpellInRange then
        local result = NormalizeRangeResult(IsSpellInRange(_rangeFriendlySpell, unit))
        if result ~= nil then return result end
    end

    -- Fallback: UnitInRange (can return secret in 12.0, guard it)
    if _G.UnitInRange then
        local inRange, checked = _G.UnitInRange(unit)
        if issecretvalue and (issecretvalue(inRange) or issecretvalue(checked)) then
            -- keep previous state
            return f._msufGFLastRange
        end
        if checked ~= nil then
            checked = NormalizeRangeResult(checked)
            if checked == true then
                return NormalizeRangeResult(inRange)
            end
        end
        if inRange ~= nil then return NormalizeRangeResult(inRange) end
    end

    -- Last resort: CheckInteractDistance 28yd (Warrior/DH)
    if CheckInteractDistance then
        local ok = NormalizeRangeResult(CheckInteractDistance(unit, 4))
        if ok ~= nil then return ok end
    end

    return f._msufGFLastRange -- keep previous if all fail
end

local function ApplyRangeFade(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.rangeFadeEnabled == false then
        f._msufGFLastRange = true
        if f.SetAlpha then f:SetAlpha(1) end
        if MaybeWakeRangeRecoveryTicker then MaybeWakeRangeRecoveryTicker() end
        return
    end

    -- Offline check (secret-safe)
    local connected = UnitIsConnected(unit)
    if issecretvalue and issecretvalue(connected) then
        connected = true -- assume connected if secret
    end
    if connected == false then
        local offA = conf.offlineAlpha or 0.5
        f._msufGFLastRange = false
        if not _rfMul then _rfMul = _G.MSUF_RangeFadeMul end
        if _rfMul then _rfMul[unit] = offA end
        -- Try MSUF alpha pipeline
        local fast = _G.MSUF_ApplyRangeFadeAlphaFast
        if type(fast) == "function" and fast(f, f.msufConfigKey, offA) then
            if MaybeWakeRangeRecoveryTicker then MaybeWakeRangeRecoveryTicker() end
            return
        end
        if f.SetAlpha then f:SetAlpha(offA) end
        if MaybeWakeRangeRecoveryTicker then MaybeWakeRangeRecoveryTicker() end
        return
    end

    local inRange = CheckRange(f, unit)
    if inRange == nil then return end -- no change possible

    local prev = f._msufGFLastRange
    f._msufGFLastRange = inRange

    local mul = inRange and 1 or (conf.rangeFadeAlpha or 0.4)
    if not _rfMul then _rfMul = _G.MSUF_RangeFadeMul end
    if _rfMul then _rfMul[unit] = mul end

    if MaybeWakeRangeRecoveryTicker then MaybeWakeRangeRecoveryTicker() end

    -- Only update visual if state changed
    if inRange == prev then return end

    local fast = _G.MSUF_ApplyRangeFadeAlphaFast
    if type(fast) == "function" and fast(f, f.msufConfigKey, mul) then return end
    if f.SetAlpha then f:SetAlpha(mul) end
end

------------------------------------------------------------------------
-- Aggro border (secret-safe UnitThreatSituation)
------------------------------------------------------------------------
local _hlBdInsets = { left = 0, right = 0, top = 0, bottom = 0 }
local _hlBdTable  = { edgeFile = nil, edgeSize = 1, insets = _hlBdInsets }
local function _applyHighlightBorderStyle(border, conf, edgeSz, ofs, texKey, layer, r, g, b, a)
    edgeSz = math_max(1, edgeSz or 2)
    ofs = tonumber(ofs) or 0
    _hlBdTable.edgeFile = GF.ResolveHighlightTexture(texKey)
    _hlBdTable.edgeSize = edgeSz
    border:SetBackdrop(_hlBdTable)
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", -ofs, ofs)
    border:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    -- Layer: ABOVE_BORDER = higher FrameLevel
    local anchor = border:GetParent()
    if anchor then
        local baseLvl = anchor:GetFrameLevel()
        if layer == "ABOVE_BORDER" then
            border:SetFrameLevel(baseLvl + 8)
        else
            border:SetFrameLevel(baseLvl + 3)
        end
    end
end

local function UpdateAggro(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local border = f._msufGFAggroBorder
    if not border then return end

    local testMode = _G.MSUF_AggroBorderTestMode
    if (HLVal(kind, "hlAggroEnabled") == false or not unit) and not testMode then
        border:Hide(); return
    end

    local s -- threat level (nil/0-3)
    if not testMode then
        if not UnitExists(unit) then border:Hide(); return end
        local aggroMode = HLVal(kind, "hlAggroMode") or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then border:Hide(); return end
            if aggroMode == "TANK_ONLY"   and role ~= "TANK"   then border:Hide(); return end
        end
        local status = UnitThreatSituation and UnitThreatSituation(unit)
        if issecretvalue and issecretvalue(status) then border:Hide(); return end
        s = tonumber(status)
        if not s or s < 1 then border:Hide(); return end
    end

    local sz  = HLVal(kind, "hlAggroSize") or 2
    local ofs = HLVal(kind, "hlAggroOffset") or 0
    local tex = HLVal(kind, "hlAggroTexture")
    local lay = HLVal(kind, "hlAggroLayer") or "DEFAULT"
    local ar, ag, ab
    if testMode or (s and s >= 3) then
        ar, ag, ab = 1, 0, 0
    else
        ar = HLVal(kind, "hlAggroColorR") or 1
        ag = HLVal(kind, "hlAggroColorG") or 0.55
        ab = HLVal(kind, "hlAggroColorB") or 0
    end
    _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, ar, ag, ab, 1)
    border:Show()
end

------------------------------------------------------------------------
-- Dispel border (AuraUtil.ForEachAura "HARMFUL|RAID")
------------------------------------------------------------------------
local _scanTopDispel
local function _DispelScanCallback(auraData)
    if not auraData then return true end
    local dispelName = auraData.dispelName
    if issecretvalue and issecretvalue(dispelName) then return false end
    if dispelName and dispelName ~= "" then
        _scanTopDispel = dispelName
        return true
    end
    if auraData.isRaid then
        _scanTopDispel = "Bleed"
        return true
    end
    return false
end

function GF._UpdateDispel(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local border = f._msufGFAggroBorder

    local testMode = _G.MSUF_DispelBorderTestMode

    if (HLVal(kind, "hlDispelEnabled") == false or not unit) and not testMode then
        f._msufGFDispelType = nil
        return
    end

    local topDispel = nil
    if not testMode then
        if not UnitExists(unit) then
            f._msufGFDispelType = nil
            return
        end
        -- Scan for dispellable debuffs (hoisted callback, zero closure alloc)
        _scanTopDispel = nil
        if AuraUtil and AuraUtil.ForEachAura then
            AuraUtil.ForEachAura(unit, "HARMFUL|RAID", nil, _DispelScanCallback, true)
        end
        topDispel = _scanTopDispel
    else
        -- Test mode: inject synthetic dispel type to preview the border
        topDispel = _G.MSUF_DispelBorderTestType or "Magic"
    end

    local prevDispel = f._msufGFDispelType
    f._msufGFDispelType = topDispel

    if topDispel == prevDispel and not testMode then return end

    if topDispel then
        local resolve = _G.MSUF_ResolveDispelColor
        local r, g, b
        if type(resolve) == "function" then
            r, g, b = resolve(topDispel)
        else
            r, g, b = GetDispelColor(topDispel)
        end
        if r and border then
            local sz  = HLVal(kind, "hlAggroSize") or 2
            local ofs = HLVal(kind, "hlAggroOffset") or 0
            local tex = HLVal(kind, "hlAggroTexture")
            local lay = HLVal(kind, "hlAggroLayer") or "DEFAULT"
            _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, r, g, b, 1)
            border:Show()
        end
    else
        UpdateAggro(f, unit)
    end
end

------------------------------------------------------------------------
-- Target indicator border
------------------------------------------------------------------------
local function UpdateTargetIndicator(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local border = f._msufGFTargetBorder
    if not border then return end

    if HLVal(kind, "hlTargetEnabled") == false or not unit then
        border:Hide()
        return
    end

    local isTarget = UnitIsUnit and UnitIsUnit(unit, "target")
    if isTarget then
        local edgeSz = HLVal(kind, "hlTargetSize") or 2
        local ofs    = HLVal(kind, "hlTargetOffset") or 0
        local tex    = HLVal(kind, "hlTargetTexture")
        local lay    = HLVal(kind, "hlTargetLayer") or "DEFAULT"
        _applyHighlightBorderStyle(border, conf, edgeSz, ofs, tex, lay,
            HLVal(kind, "hlTargetColorR") or 1,
            HLVal(kind, "hlTargetColorG") or 1,
            HLVal(kind, "hlTargetColorB") or 1, 1)
        border:Show()
    else
        border:Hide()
    end
end

------------------------------------------------------------------------
-- Status text: AFK / DND (red, GF-owned pipeline)
------------------------------------------------------------------------
local function UpdateStatusText(f, unit)
    local st = f._msufGFStatusText or f.statusIndicatorText
    if not st then return end

    local function hideHealthText()
        if f.textLeftFS then f.textLeftFS:Hide() end
        if f.textCenterFS then f.textCenterFS:Hide() end
        if f.textRightFS then f.textRightFS:Hide() end
        if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
        if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
        if f.powerTextRightFS then f.powerTextRightFS:Hide() end
    end

    local function restoreHealthText()
        local kind = f._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        local tl = conf.textLeft  or "NONE"
        local tc = conf.textCenter or "NONE"
        local tr = conf.textRight or "NONE"
        if f.textLeftFS  and tl ~= "NONE" then f.textLeftFS:Show() end
        if f.textCenterFS and tc ~= "NONE" then f.textCenterFS:Show() end
        if f.textRightFS and tr ~= "NONE" then f.textRightFS:Show() end
        if conf.showPower and (conf.powerHeight or 6) > 0 then
            local ptl = conf.powerTextLeft   or "NONE"
            local ptc = conf.powerTextCenter  or "NONE"
            local ptr = conf.powerTextRight   or "NONE"
            if f.powerTextLeftFS  and ptl ~= "NONE" then f.powerTextLeftFS:Show() end
            if f.powerTextCenterFS and ptc ~= "NONE" then f.powerTextCenterFS:Show() end
            if f.powerTextRightFS and ptr ~= "NONE" then f.powerTextRightFS:Show() end
        end
    end

    if not unit or not UnitExists(unit) then
        st:SetText("")
        st:Hide()
        restoreHealthText()
        if f.nameText then f.nameText:Show() end
        return
    end

    local connected = UnitIsConnected(unit)
    if issecretvalue and issecretvalue(connected) then connected = true end

    if connected == false then
        st:SetText("OFFLINE")
        st:SetTextColor(0.6, 0.6, 0.6, 1)
        st:Show()
        hideHealthText()
        return
    end

    if UnitIsDeadOrGhost(unit) then
        local ghost = _G.UnitIsGhost and _G.UnitIsGhost(unit)
        if issecretvalue and ghost and issecretvalue(ghost) then ghost = false end
        st:SetText(ghost and "GHOST" or "DEAD")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        hideHealthText()
        return
    end

    -- AFK / DND — secret-safe in 12.0
    local showAFK = false
    local showDND = false

    if UnitIsAFK then
        local afk = UnitIsAFK(unit)
        if issecretvalue and issecretvalue(afk) then
            showAFK = false
        else
            showAFK = (afk == true)
        end
    end

    if not showAFK and UnitIsDND then
        local dnd = UnitIsDND(unit)
        if issecretvalue and issecretvalue(dnd) then
            showDND = false
        else
            showDND = (dnd == true)
        end
    end

    if showAFK then
        st:SetText("AFK")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        hideHealthText()
        return
    end

    if showDND then
        st:SetText("DND")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        hideHealthText()
        return
    end

    st:SetText("")
    st:Hide()
    restoreHealthText()
end

------------------------------------------------------------------------
-- Role icon update
------------------------------------------------------------------------
local function UpdateRoleIcon(f, unit)
    if not f.roleIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.roleIcon == false or not unit or not UnitExists(unit) then
        f.roleIcon:Hide()
        return
    end
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

------------------------------------------------------------------------
-- Raid target marker update
------------------------------------------------------------------------
local function UpdateRaidMarker(f, unit)
    if not f.raidIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.raidMarker == false or not unit or not UnitExists(unit) then
        f.raidIcon:Hide()
        return
    end
    local idx = GetRaidTargetIndex(unit)
    if idx then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Leader / Assistant icon update
------------------------------------------------------------------------
local function UpdateLeaderIcon(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    -- Leader icon
    if f.leaderIcon then
        if conf.leaderIcon == false or not unit or not UnitExists(unit) then
            f.leaderIcon:Hide()
        else
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
    end
    -- Assist icon (separate from leader)
    if f.assistIcon then
        if conf.assistIcon == false or not unit or not UnitExists(unit) then
            f.assistIcon:Hide()
        else
            local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
            -- Only show assist if not also leader (avoid double-icon)
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
end

------------------------------------------------------------------------
-- Ready check icon
------------------------------------------------------------------------
local _readyCheckTimers = {} -- [frame] = timer handle

local function UpdateReadyCheck(f, unit, event)
    if not f.readyCheckIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.readyCheckIcon == false or not unit then
        f.readyCheckIcon:Hide()
        if _readyCheckTimers[f] then _readyCheckTimers[f]:Cancel(); _readyCheckTimers[f] = nil end
        return
    end

    local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if status == "ready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.ready)
        f.readyCheckIcon:Show()
    elseif status == "notready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.notReady)
        f.readyCheckIcon:Show()
    elseif status == "waiting" then
        f.readyCheckIcon:SetTexture(ICON_TEX.waiting)
        f.readyCheckIcon:Show()
    else
        if event == "READY_CHECK_FINISHED" and f.readyCheckIcon:IsShown() then
            -- Fade out after 6 seconds
            if _readyCheckTimers[f] then _readyCheckTimers[f]:Cancel() end
            _readyCheckTimers[f] = C_Timer.NewTimer(6, function()
                _readyCheckTimers[f] = nil
                f.readyCheckIcon:Hide()
            end)
        else
            f.readyCheckIcon:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Summon icon
------------------------------------------------------------------------
local function UpdateSummonIcon(f, unit)
    if not f.summonIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.summonIcon == false or not unit then
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
        return
    end
    local status
    if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        status = C_IncomingSummon.IncomingSummonStatus(unit)
    end
    local tex = status and SUMMON_TEX[status]
    if tex then
        f.summonIcon:SetTexture(tex)
        f.summonIcon:Show()
        f._msufGFSummonActive = true
    else
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
    end
end

------------------------------------------------------------------------
-- Resurrect icon
------------------------------------------------------------------------
local function UpdateResurrectIcon(f, unit)
    if not f.resurrectIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.resurrectIcon == false or not unit then
        f.resurrectIcon:Hide()
        return
    end
    -- Suppress if summon is active
    if f._msufGFSummonActive then
        f.resurrectIcon:Hide()
        return
    end
    local show = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
    if show then
        f.resurrectIcon:SetTexture(ICON_TEX.resurrect)
        f.resurrectIcon:Show()
    else
        f.resurrectIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Phase icon
------------------------------------------------------------------------
local function UpdatePhaseIcon(f, unit)
    if not f.phaseIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.phaseIcon == false or not unit then
        f.phaseIcon:Hide()
        return
    end
    local reason
    if UnitIsPlayer and UnitIsPlayer(unit) and UnitPhaseReason then
        local conn = UnitIsConnected(unit)
        if issecretvalue and issecretvalue(conn) then conn = true end
        if conn then reason = UnitPhaseReason(unit) end
    end
    if reason then
        f.phaseIcon:SetTexture(ICON_TEX.phase)
        f.phaseIcon:Show()
    else
        f.phaseIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Health color (respects global barMode: dark/unified/class)
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit)
    if not f.health then return end
    -- Global barMode override (same as Render.ApplyHealthColor)
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = type(getCache) == "function" and getCache() or nil
    local globalMode = cache and cache.barMode
    if globalMode == "dark" then
        f.health:SetStatusBarColor(cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0, 1)
        return
    end
    if globalMode == "unified" then
        f.health:SetStatusBarColor(cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90, 1)
        return
    end
    local conf = GF.GetConf(kind)
    local mode = conf.healthColorMode or "CLASS"
    if mode == "CLASS" and unit then
        local _, cls = UnitClass(unit)
        if cls then
            local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
            if type(fastClass) == "function" then
                local r, g, b = fastClass(cls)
                if r then f.health:SetStatusBarColor(r, g, b, 1); return end
            end
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1); return end
        end
    end
    if mode == "GRADIENT" and unit then
        local hp = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        if issecretvalue and (issecretvalue(hp) or issecretvalue(hpMax)) then
            f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            return
        end
        local hpN, hpMaxN = tonumber(hp), tonumber(hpMax)
        if hpN and hpMaxN and hpMaxN > 0 then
            local pct = hpN / hpMaxN
            local r = pct > 0.5 and (1 - (pct - 0.5) * 2) or 1
            local g = pct > 0.5 and 1 or (pct * 2)
            f.health:SetStatusBarColor(r, g, 0, 1)
        else
            f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        end
        return
    end
    f.health:SetStatusBarColor(
        conf.healthCustomR or 0.2,
        conf.healthCustomG or 0.8,
        conf.healthCustomB or 0.2, 1)
end

------------------------------------------------------------------------
-- Power color (secret-safe pToken)
------------------------------------------------------------------------
local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local _, pToken = UnitPowerType(unit)
    if pToken and PowerBarColor and PowerBarColor[pToken] then
        local c = PowerBarColor[pToken]
        f.power:SetStatusBarColor(c.r or 0.5, c.g or 0.5, c.b or 0.5, 1)
    else
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
    end
end

------------------------------------------------------------------------
-- Group number (raid subgroup) — secret-safe
------------------------------------------------------------------------
local function UpdateGroupNumber(f, unit)
    if not f.groupNumberText then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if not conf.showGroupNumber then f.groupNumberText:Hide(); return end
    if not unit or not GetRaidRosterInfo then f.groupNumberText:Hide(); return end
    local idx = strmatch(unit, "^raid(%d+)$")
    if not idx then f.groupNumberText:Hide(); return end
    local raidIdx = tonumber(idx)
    if not raidIdx then f.groupNumberText:Hide(); return end
    local _, _, subgroup = GetRaidRosterInfo(raidIdx)
    if issecretvalue and issecretvalue(subgroup) then
        f.groupNumberText:SetText("")
        f.groupNumberText:Hide()
        return
    end
    local sg = tonumber(subgroup)
    if sg and sg >= 1 and sg <= 8 then
        f.groupNumberText:SetText(tostring(sg))
        f.groupNumberText:Show()
    else
        f.groupNumberText:Hide()
    end
end

------------------------------------------------------------------------
-- Full update for a single frame (called on unit assignment + events)
------------------------------------------------------------------------
local dispatchOverlays, dispatchIncomingHeal, dispatchAbsorb, dispatchHealAbsorb
local function UpdateAll(f, unit)
    if not f or not unit then return end
    GF.UpdateButton(f, unit)       -- name, HP, power, role, marker, leader (Phase 1)
    ApplyRangeFade(f, unit)
    UpdateAggro(f, unit)
    GF._UpdateDispel(f, unit)
    if GF.UpdateSpellIndicators then GF.UpdateSpellIndicators(f, unit) end
    if GF.UpdateFrameAuras then GF.UpdateFrameAuras(f, unit) end
    UpdateTargetIndicator(f, unit)
    UpdateStatusText(f, unit)
    dispatchOverlays(f, unit)
    UpdateRoleIcon(f, unit)
    UpdateRaidMarker(f, unit)
    UpdateLeaderIcon(f, unit)
    UpdateSummonIcon(f, unit)
    UpdateResurrectIcon(f, unit)
    UpdatePhaseIcon(f, unit)
    UpdateGroupNumber(f, unit)
    if GF.ApplyPrivateAuras then GF.ApplyPrivateAuras(f, unit) end
end

------------------------------------------------------------------------
-- Per-frame event dispatch table
------------------------------------------------------------------------
local function dispatchHealth(f, unit)
    if not f.health then return end
    local hp    = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    f.health:SetMinMaxValues(0, hpMax)
    -- Smooth fill (conditional: conf.smoothFill controls it)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.smoothFill ~= false then
        local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
        if interpolation then
            f.health:SetValue(hp, interpolation)
        else
            f.health:SetValue(hp)
        end
    else
        f.health:SetValue(hp)
    end
    ApplyHealthColor(f, kind, unit)
    -- 3-slot health text
    local delim = conf.textDelimiter or " / "
    local rev = conf.hpTextReverse
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"
    if f.textLeftFS then
        f.textLeftFS:SetText(GF.FormatHealthText(tl, hp, hpMax, delim, rev))
    end
    if f.textCenterFS then
        f.textCenterFS:SetText(GF.FormatHealthText(tc, hp, hpMax, delim, rev))
    end
    if f.textRightFS then
        f.textRightFS:SetText(GF.FormatHealthText(tr, hp, hpMax, delim, rev))
    end
    UpdateStatusText(f, unit)
    dispatchOverlays(f, unit)
end

------------------------------------------------------------------------
-- Health prediction overlays (absorb + incoming heal + heal absorb)
-- All 12.0 secret-safe: raw API values passed to C-side SetValue/SetMinMaxValues.
-- Show/hide: issecretvalue(val) → secret = Show (non-nil means has value).
-- Colors read from global MSUF_DB.general (same keys as main UF overlays).
------------------------------------------------------------------------
local function _GF_ReadOverlayColor(keyR, keyG, keyB, defR, defG, defB, defA)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local r, g, b = gen[keyR], gen[keyG], gen[keyB]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, defA
        end
    end
    return defR, defG, defB, defA
end

dispatchIncomingHeal = function(f, unit)
    local bar = f.incomingHealBar
    if not bar then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if conf.healPredEnabled == false then bar:Hide(); return end
    if not UnitGetIncomingHeals then bar:Hide(); return end
    local hpMax = UnitHealthMax(unit)
    local val   = UnitGetIncomingHeals(unit)
    if val == nil then bar:Hide(); return end
    local valSecret = issecretvalue and issecretvalue(val)
    if not valSecret then
        local n = tonumber(val) or 0
        if n <= 0 then bar:Hide(); return end
        local hpMaxSecret = issecretvalue and issecretvalue(hpMax)
        if not hpMaxSecret then
            local hp = UnitHealth(unit)
            local hpSecret = issecretvalue and issecretvalue(hp)
            if not hpSecret then
                local missing = (tonumber(hpMax) or 0) - (tonumber(hp) or 0)
                if missing < 0 then missing = 0 end
                if n > missing then val = missing end
            end
        end
    end
    bar:SetMinMaxValues(0, hpMax)
    bar:SetValue(val)
    bar:Show()
end

dispatchAbsorb = function(f, unit)
    local bar = f.absorbBar
    if not bar then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if conf.absorbEnabled == false then bar:Hide(); return end
    if not UnitGetTotalAbsorbs then bar:Hide(); return end
    local hpMax = UnitHealthMax(unit)
    local val   = UnitGetTotalAbsorbs(unit)
    if val == nil then bar:Hide(); return end
    bar:SetMinMaxValues(0, hpMax)
    bar:SetValue(val)
    if issecretvalue and issecretvalue(val) then
        bar:Show()
    else
        if (tonumber(val) or 0) > 0 then bar:Show() else bar:Hide() end
    end
end

dispatchHealAbsorb = function(f, unit)
    local bar = f.healAbsorbBar
    if not bar then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if conf.healAbsorbEnabled == false then bar:Hide(); return end
    if not UnitGetTotalHealAbsorbs then bar:Hide(); return end
    local hpMax = UnitHealthMax(unit)
    local val   = UnitGetTotalHealAbsorbs(unit)
    if val == nil then bar:Hide(); return end
    bar:SetMinMaxValues(0, hpMax)
    bar:SetValue(val)
    if issecretvalue and issecretvalue(val) then
        bar:Show()
    else
        if (tonumber(val) or 0) > 0 then bar:Show() else bar:Hide() end
    end
end

dispatchOverlays = function(f, unit)
    dispatchIncomingHeal(f, unit)
    dispatchAbsorb(f, unit)
    dispatchHealAbsorb(f, unit)
end

local function dispatchPower(f, unit)
    if not f.power then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if (conf.powerHeight or 6) <= 0 then return end
    -- Per-role visibility
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role == "TANK" and conf.powerShowTank == false then
        f.power:Hide(); return
    elseif role == "HEALER" and conf.powerShowHealer == false then
        f.power:Hide(); return
    elseif role == "DAMAGER" and conf.powerShowDamager == false then
        f.power:Hide(); return
    end
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
    -- 3-slot power text
    if conf.showPower then
        local pDelim = conf.powerTextDelimiter or " / "
        local ptl = conf.powerTextLeft   or "NONE"
        local ptc = conf.powerTextCenter  or "NONE"
        local ptr = conf.powerTextRight   or "NONE"
        if f.powerTextLeftFS then
            f.powerTextLeftFS:SetText(GF.FormatPowerText(ptl, pw, pwMax, pDelim))
        end
        if f.powerTextCenterFS then
            f.powerTextCenterFS:SetText(GF.FormatPowerText(ptc, pw, pwMax, pDelim))
        end
        if f.powerTextRightFS then
            f.powerTextRightFS:SetText(GF.FormatPowerText(ptr, pw, pwMax, pDelim))
        end
    end
end

local function dispatchDisplayPower(f, unit)
    ApplyPowerColor(f, unit)
    dispatchPower(f, unit)
end

local function dispatchName(f, unit)
    if f.nameText then
        local kind = f._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        if conf.showName ~= false then
            local name = UnitName(unit) or ""
            local maxC = conf.nameMaxChars or 0
            if maxC > 0 then
                name = GF.TruncateName(name, maxC, conf.nameNoEllipsis)
            end
            f.nameText:SetText(name)
            -- Apply name color
            local _, classToken = UnitClass(unit)
            local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
            f.nameText:SetTextColor(nr, ng, nb, 1)
        end
    end
end

local UNIT_DISPATCH = {
    UNIT_HEALTH                       = dispatchHealth,
    UNIT_MAXHEALTH                    = dispatchHealth,
    UNIT_HEAL_PREDICTION              = function(f, u) dispatchIncomingHeal(f, u) end,
    UNIT_ABSORB_AMOUNT_CHANGED        = function(f, u) dispatchAbsorb(f, u) end,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED   = function(f, u) dispatchHealAbsorb(f, u) end,
    UNIT_POWER_UPDATE                 = dispatchPower,
    UNIT_MAXPOWER                     = dispatchPower,
    UNIT_DISPLAYPOWER                 = dispatchDisplayPower,
    UNIT_NAME_UPDATE                  = dispatchName,
    UNIT_CONNECTION                   = function(f, u) UpdateStatusText(f, u); ApplyRangeFade(f, u) end,
    UNIT_FLAGS                        = function(f, u) UpdateStatusText(f, u); UpdateRoleIcon(f, u); UpdateLeaderIcon(f, u) end,
    UNIT_IN_RANGE_UPDATE              = function(f, u) ApplyRangeFade(f, u) end,
    UNIT_AURA                         = function(f, u) MarkAuraDirty(f) end,
    UNIT_THREAT_SITUATION_UPDATE      = function(f, u) UpdateAggro(f, u) end,
    UNIT_THREAT_LIST_UPDATE           = function(f, u) UpdateAggro(f, u) end,
    INCOMING_SUMMON_CHANGED           = function(f, u) UpdateSummonIcon(f, u); UpdateResurrectIcon(f, u) end,
    INCOMING_RESURRECT_CHANGED        = function(f, u) UpdateResurrectIcon(f, u) end,
    UNIT_PHASE                        = function(f, u) UpdatePhaseIcon(f, u) end,
}

------------------------------------------------------------------------
-- Per-frame OnEvent handler
------------------------------------------------------------------------
local function GF_OnEvent(self, event, unit, ...)
    local u = self.unit
    if not u then return end
    if unit and unit ~= u then return end

    local fn = UNIT_DISPATCH[event]
    if fn then fn(self, u, ...) end
end

------------------------------------------------------------------------
-- RegisterUnitEvents / UnregisterUnitEvents (replaces Phase 1 stubs)
------------------------------------------------------------------------
function GF.RegisterUnitEvents(f, unit)
    if not (f and unit) then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    -- Clear previous registrations
    if f._msufGFRegEv then
        for ev in pairs(f._msufGFRegEv) do
            if f.UnregisterEvent then f:UnregisterEvent(ev) end
        end
    end
    f._msufGFRegEv = {}

    local function reg(ev)
        f:RegisterUnitEvent(ev, unit)
        f._msufGFRegEv[ev] = true
    end

    -- Core events
    reg("UNIT_HEALTH")
    reg("UNIT_MAXHEALTH")
    reg("UNIT_CONNECTION")
    reg("UNIT_NAME_UPDATE")
    reg("UNIT_FLAGS")

    -- Power
    if (conf.powerHeight or 6) > 0 then
        reg("UNIT_POWER_UPDATE")
        reg("UNIT_MAXPOWER")
        reg("UNIT_DISPLAYPOWER")
    end

    -- Range
    if conf.rangeFadeEnabled ~= false then
        reg("UNIT_IN_RANGE_UPDATE")
    end

    -- Auras (dispel detection)
    if HLVal(kind, "hlDispelEnabled") ~= false then
        reg("UNIT_AURA")
    end

    -- Threat
    if HLVal(kind, "hlAggroEnabled") ~= false then
        reg("UNIT_THREAT_SITUATION_UPDATE")
        reg("UNIT_THREAT_LIST_UPDATE")
    end

    -- Status icons
    reg("INCOMING_SUMMON_CHANGED")
    reg("INCOMING_RESURRECT_CHANGED")
    reg("UNIT_PHASE")

    -- Health prediction overlays
    if conf.healPredEnabled ~= false and UnitGetIncomingHeals then
        reg("UNIT_HEAL_PREDICTION")
    end
    if conf.absorbEnabled ~= false and UnitGetTotalAbsorbs then
        reg("UNIT_ABSORB_AMOUNT_CHANGED")
    end
    if conf.healAbsorbEnabled ~= false and UnitGetTotalHealAbsorbs then
        reg("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    end

    -- Set OnEvent handler
    f:SetScript("OnEvent", GF_OnEvent)
end

function GF.UnregisterUnitEvents(f)
    if not f then return end
    if f._msufGFRegEv then
        for ev in pairs(f._msufGFRegEv) do
            if f.UnregisterEvent then f:UnregisterEvent(ev) end
        end
        f._msufGFRegEv = nil
    end
    f:SetScript("OnEvent", nil)
    if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
end

------------------------------------------------------------------------
-- Global events (not per-unit)
------------------------------------------------------------------------
local _globalFrame = CreateFrame("Frame")

-- PLAYER_TARGET_CHANGED: update target indicator on all GF frames
-- READY_CHECK / READY_CHECK_FINISHED: update ready check icons
-- RAID_TARGET_UPDATE: update raid markers
local function OnGlobalEvent(self, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        for f, kind in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then
                UpdateTargetIndicator(f, f.unit)
            end
        end

    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
        for f in pairs(GF.frames) do
            if f.unit then UpdateReadyCheck(f, f.unit, event) end
        end

    elseif event == "READY_CHECK_FINISHED" then
        for f in pairs(GF.frames) do
            if f.unit then UpdateReadyCheck(f, f.unit, "READY_CHECK_FINISHED") end
        end

    elseif event == "RAID_TARGET_UPDATE" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then UpdateRaidMarker(f, f.unit) end
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then UpdateLeaderIcon(f, f.unit) end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then
                UpdateAll(f, f.unit)
            end
        end
    elseif event == "BARBER_SHOP_OPEN" then
        -- hideInClientScene: hide all GF headers when entering barber/dressing room
        for _, scope in ipairs({"party", "raid"}) do
            local conf = GF.GetConf(scope)
            if conf.hideInClientScene ~= false then
                local header = GF.headers and GF.headers[scope]
                if header and not InCombatLockdown() then
                    header._msufGF_clientSceneHidden = true
                    header:SetAlpha(0)
                end
            end
        end
    elseif event == "BARBER_SHOP_CLOSE" then
        for _, scope in ipairs({"party", "raid"}) do
            local header = GF.headers and GF.headers[scope]
            if header and header._msufGF_clientSceneHidden then
                header._msufGF_clientSceneHidden = nil
                header:SetAlpha(1)
            end
        end
    end
end

_globalFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
_globalFrame:RegisterEvent("READY_CHECK")
_globalFrame:RegisterEvent("READY_CHECK_CONFIRM")
_globalFrame:RegisterEvent("READY_CHECK_FINISHED")
_globalFrame:RegisterEvent("RAID_TARGET_UPDATE")
_globalFrame:RegisterEvent("PARTY_LEADER_CHANGED")
_globalFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
_globalFrame:RegisterEvent("BARBER_SHOP_OPEN")
_globalFrame:RegisterEvent("BARBER_SHOP_CLOSE")
_globalFrame:SetScript("OnEvent", OnGlobalEvent)

------------------------------------------------------------------------
-- OOR recovery ticker
-- UNIT_IN_RANGE_UPDATE can miss the "back in range" transition on some
-- clients/setups for party/raid units. To stay accurate without broad
-- polling, only units currently marked OOR are revalidated on a tiny
-- shared ticker. This keeps the hot path event-driven and wakes polling
-- only when there is actually something to recover.
------------------------------------------------------------------------
do
    local _recoveryFrame
    local _elapsed = 0
    local _inCombat = false

    local function FrameNeedsRecoveryPoll(f)
        if not (f and f.unit and f._msufGFLastRange == false) then return false end
        if not UnitExists(f.unit) then return false end

        local conf = GF.GetConf(f._msufGFKind or "party")
        if not conf or conf.rangeFadeEnabled == false then return false end

        local connected = UnitIsConnected(f.unit)
        if issecretvalue and issecretvalue(connected) then connected = true end
        if connected == false then return false end

        if UnitPhaseReason and UnitPhaseReason(f.unit) then return false end
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(f.unit) then return false end
        return true
    end

    local function HasRecoveryWork()
        for f in pairs(GF.frames) do
            if FrameNeedsRecoveryPoll(f) then
                return true
            end
        end
        return false
    end

    local function EnsureRecoveryFrame()
        if _rangeNeedsTicker then return nil end
        if _recoveryFrame then return _recoveryFrame end
        _recoveryFrame = CreateFrame("Frame")
        _recoveryFrame:Hide()
        _recoveryFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        _recoveryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        _recoveryFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_DISABLED" then
                _inCombat = true
            else
                _inCombat = false
            end
        end)
        _recoveryFrame:SetScript("OnUpdate", function(self, dt)
            _elapsed = _elapsed + dt
            local interval = _inCombat and 0.20 or 0.50
            if _elapsed < interval then return end
            _elapsed = 0

            local hasWork = false
            for f in pairs(GF.frames) do
                if FrameNeedsRecoveryPoll(f) then
                    hasWork = true
                    ApplyRangeFade(f, f.unit)
                end
            end

            if not hasWork then
                self:Hide()
            end
        end)
        return _recoveryFrame
    end

    MaybeWakeRangeRecoveryTicker = function()
        if _rangeNeedsTicker then return end
        local frame = EnsureRecoveryFrame()
        if not frame then return end
        if HasRecoveryWork() then
            _elapsed = 0
            frame:Show()
        else
            frame:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Range ticker (for classes without friendly spell: Warrior, DH, Hunter)
-- 1s combat, 3s OOC — only runs when GF frames exist
------------------------------------------------------------------------
do
    if _rangeNeedsTicker then
        local _tickerFrame = CreateFrame("Frame")
        local _elapsed = 0
        local _inCombat = false

        _tickerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        _tickerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        _tickerFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_DISABLED" then
                _inCombat = true
            else
                _inCombat = false
            end
        end)

        _tickerFrame:SetScript("OnUpdate", function(self, dt)
            _elapsed = _elapsed + dt
            local interval = _inCombat and 1 or 3
            if _elapsed < interval then return end
            _elapsed = 0

            local hasAny = false
            for f in pairs(GF.frames) do
                if f.unit and UnitExists(f.unit) then
                    hasAny = true
                    ApplyRangeFade(f, f.unit)
                end
            end
            if not hasAny then self:Hide() end -- sleep when no frames
        end)

        -- Wake ticker when frames appear
        local origRegister = GF.RegisterUnitEvents
        GF.RegisterUnitEvents = function(f, unit)
            origRegister(f, unit)
            if _rangeNeedsTicker and _tickerFrame then
                _tickerFrame:Show()
            end
        end
    end
end

------------------------------------------------------------------------
-- Mouseover highlight
------------------------------------------------------------------------
local function _GF_GetHighlightColor()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local c = gen.highlightColor
        if type(c) == "table" and c[1] then return c[1], c[2] or 1, c[3] or 1 end
        if type(c) == "string" then
            local colors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
            if type(colors) == "table" and colors[c] then
                local cc = colors[c]
                return cc[1], cc[2], cc[3]
            end
        end
    end
    return 1, 1, 1
end

local function _GF_IsHighlightEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen.highlightEnabled == false then return false end
    return true
end

local function EnsureMouseoverHighlight(f)
    if not _GF_IsHighlightEnabled() then return nil end
    local kind = f._msufGFKind or "party"
    local sz = math_max(1, tonumber(HLVal(kind, "hlHoverSize")) or 1)
    local ofs = tonumber(HLVal(kind, "hlHoverOffset")) or 0
    local r, g, b = _GF_GetHighlightColor()
    if f._msufGFHoverBorder then
        local hb = f._msufGFHoverBorder
        hb:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = sz })
        hb:SetBackdropBorderColor(r, g, b, 0.7)
        hb:SetBackdropColor(0, 0, 0, 0)
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", -ofs, ofs)
        hb:SetPoint("BOTTOMRIGHT", ofs, -ofs)
        return hb
    end
    local anchor = f.barGroup or f
    local hb = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    hb:SetPoint("TOPLEFT", -ofs, ofs)
    hb:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    hb:SetFrameLevel(anchor:GetFrameLevel() + 6)
    hb:EnableMouse(false)
    hb:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = sz })
    hb:SetBackdropBorderColor(r, g, b, 0.7)
    hb:SetBackdropColor(0, 0, 0, 0)
    hb:Hide()
    f._msufGFHoverBorder = hb
    return hb
end

------------------------------------------------------------------------
-- Tooltip + Highlight hooks
------------------------------------------------------------------------
local function OnEnter(f)
    -- Mouseover highlight
    local hb = EnsureMouseoverHighlight(f)
    if hb then hb:Show() end
    -- Tooltip
    if not f.unit or not UnitExists(f.unit) then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local mode = conf.tooltipMode or "ALWAYS"
    if mode == "NEVER" then return end
    if mode == "OOC" and InCombatLockdown() then return end
    if mode == "MODIFIER" then
        local mod = conf.tooltipModifier or "ALT"
        if mod == "ALT"   and not IsAltKeyDown()     then return end
        if mod == "CTRL"  and not IsControlKeyDown()  then return end
        if mod == "SHIFT" and not IsShiftKeyDown()    then return end
    end
    if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
        _G.GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        _G.GameTooltip:SetUnit(f.unit)
        _G.GameTooltip:Show()
    end
end

local function OnLeave(f)
    -- Hide highlight
    if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
    -- Hide tooltip
    if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
        _G.GameTooltip:Hide()
    end
end

-- Hook into GF_InitButton from Phase 1
local _origInit = _G.MSUF_GF_InitButton
if type(_origInit) == "function" then
    _G.MSUF_GF_InitButton = function(f, kind)
        _origInit(f, kind)
        -- Add tooltip scripts
        f:SetScript("OnEnter", OnEnter)
        f:SetScript("OnLeave", OnLeave)
        -- Init alpha pipeline for range fade
        local applyAlpha = _G.MSUF_ApplyUnitAlpha
        if type(applyAlpha) == "function" then
            applyAlpha(f, f.msufConfigKey)
        end
    end
end

------------------------------------------------------------------------
-- Expose
------------------------------------------------------------------------
_G.MSUF_GF_UpdateAll     = UpdateAll
_G.MSUF_GF_UpdateAggro   = UpdateAggro
_G.MSUF_GF_UpdateDispel   = GF._UpdateDispel
_G.MSUF_GF_UpdateRange    = ApplyRangeFade
_G.MSUF_GF_UpdateTarget   = UpdateTargetIndicator
_G.MSUF_GF_UpdateStatus   = UpdateStatusText
_G.MSUF_GF_UpdateGroupNum = UpdateGroupNumber
GF._ReadOverlayColor      = _GF_ReadOverlayColor
