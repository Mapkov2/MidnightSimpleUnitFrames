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
local GetTime = _G.GetTime
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
local tonumber = tonumber
local tostring = tostring
local IsAltKeyDown     = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown   = _G.IsShiftKeyDown
local UnitInRaid       = _G.UnitInRaid
local UnitInRange      = _G.UnitInRange
local UnitIsGhost      = _G.UnitIsGhost
local GetRaidRosterInfo = _G.GetRaidRosterInfo
local strmatch         = string.match

------------------------------------------------------------------------
-- Highlight value resolver: Bars hl* keys → old GF conf key fallback
-- Bars system uses hlAggroEnabled, hlAggroColorR, etc.
-- Old GF DB uses aggroEnabled, aggroR, etc.
-- Single-pass resolution: conf.hlOverride → general → conf[fallback]
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
    local conf = GF.GetConf(kind)
    -- Priority 1: GF-local override
    if conf.hlOverride and conf[key] ~= nil then return conf[key] end
    -- Priority 2: global general (always fresh — 2 table lookups)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    -- Priority 3: legacy GF conf fallback
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then return conf[fb] end
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
-- Forward declaration (defined later in file)
local _GF_RefreshBorder

------------------------------------------------------------------------
-- UNIT_AURA: inline per-frame dispatch (no coalescing)
------------------------------------------------------------------------
local function SpellIndicatorsNeedRefresh(f, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    local added = updateInfo.addedAuras
    if added and #added > 0 then return true end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    return false
end

local function dispatchAura(f, unit, updateInfo)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local auras = conf and conf.auras
    local aurasOn = auras and auras.enabled ~= false
    local siCfg = conf and conf.spellIndicators
    local siOn = siCfg and siCfg.enabled == true
    local siRefresh = siOn and SpellIndicatorsNeedRefresh(f, updateInfo) or false

    if not aurasOn then
        if conf.dispelEnabled ~= false and GF._playerCanDispel then
            if not updateInfo or updateInfo.isFullUpdate
               or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
               or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0) then
                GF._UpdateDispel(f, unit)
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        return
    end

    -- Check if ANY sub-group is actually enabled (avoid full pipeline when all off)
    local anyGroupOn = (auras.debuff and auras.debuff.enabled ~= false)
                    or (auras.buff and auras.buff.enabled ~= false)
                    or (auras.externals and auras.externals and auras.externals.enabled)
    if not anyGroupOn then
        -- Master ON but all sub-groups OFF: only standalone dispel if needed
        if conf.dispelEnabled ~= false and GF._playerCanDispel then
            if not updateInfo or updateInfo.isFullUpdate
               or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
               or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0) then
                GF._UpdateDispel(f, unit)
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        return
    end

    -- Full rescan required
    if not updateInfo or updateInfo.isFullUpdate then
        -- Throttle fullUpdate when out of combat (Blizzard fires these periodically)
        if updateInfo and updateInfo.isFullUpdate and not InCombatLockdown() then
            local now = GetTime()
            local last = f._msufGFLastFullAura
            if last and (now - last) < 0.5 then
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
            f._msufGFLastFullAura = now
        end
        -- fall through to full pipeline below
    else
        local added   = updateInfo.addedAuras
        local removed = updateInfo.removedAuraInstanceIDs
        local updated = updateInfo.updatedAuraInstanceIDs
        local hasAdd = added and #added > 0
        local hasRem = removed and #removed > 0
        local hasUpd = updated and #updated > 0

        -- Nothing relevant at all
        if not hasAdd and not hasRem and not hasUpd then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end

        local displayed = f._msufDisplayedAuraIDs

        -- Update-only: direct icon refresh (16µs vs 115µs)
        if not hasAdd and not hasRem and hasUpd then
            if displayed and GF.RefreshAuraIcon then
                for ui = 1, #updated do
                    local icon = displayed[updated[ui]]
                    if icon then
                        GF.RefreshAuraIcon(icon, unit, updated[ui])
                    end
                end
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
        end

        -- Remove-only: skip if none of the removed auras were displayed
        if hasRem and not hasAdd then
            if displayed then
                local anyDisplayed = false
                for ri = 1, #removed do
                    if displayed[removed[ri]] then anyDisplayed = true; break end
                end
                if not anyDisplayed then
                    -- Removed auras weren't visible — also handle updates if present
                    if hasUpd and GF.RefreshAuraIcon then
                        for ui = 1, #updated do
                            local icon = displayed[updated[ui]]
                            if icon then GF.RefreshAuraIcon(icon, unit, updated[ui]) end
                        end
                    end
                    if siRefresh and GF.UpdateSpellIndicators then
                        GF.UpdateSpellIndicators(f, unit)
                    end
                    return
                end
            end
        end

        -- Add or displayed-remove: fall through to full pipeline
    end

    -- Out-of-combat rate limit: max 2 full rescans/s per frame (idle optimization)
    -- In combat: unlimited (instant debuff detection)
    if not InCombatLockdown() then
        local now = GetTime()
        if f._msufGFLastFullAura and (now - f._msufGFLastFullAura) < 0.5 then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end
        f._msufGFLastFullAura = now
    end

    -- Full aura processing (add/remove/fullUpdate)
    if GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
        local mergedDispel = f._msufGFMergedDispel
        local prevDispel = f._msufGFDispelType
        if mergedDispel ~= prevDispel then
            f._msufGFDispelType = mergedDispel
            _GF_RefreshBorder(f, unit)
        end
    else
        GF._UpdateDispel(f, unit)
    end
    if siOn and GF.UpdateSpellIndicators then
        GF.UpdateSpellIndicators(f, unit)
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
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
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
    if CheckInteractDistance and not InCombatLockdown() then
        local ok = CheckInteractDistance(unit, 4)
        if issecretvalue and ok ~= nil and issecretvalue(ok) then
            return f._msufGFLastRange -- secret: keep previous
        end
        ok = NormalizeRangeResult(ok)
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

------------------------------------------------------------------------
-- Unified highlight border refresh (single border, priority pipeline)
-- Priority: Dispel > Aggro > Target
-- Each per-feature update stores its state on the frame then calls this.
------------------------------------------------------------------------
------------------------------------------------------------------------
-- HLColor: read highlight COLORS always from MSUF_DB.general first
-- (same source as main UF — Colors panel writes there).
-- hlOverride only gates geometry (size/offset/layer) and enable flags,
-- NOT colors — prevents stale-seeded color copies in gf_party/gf_raid.
------------------------------------------------------------------------
local function HLColor(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

_GF_RefreshBorder = function(f, unit)
    local border = f._msufGFHighlightBorder
    if not border then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    -- Priority 1: Dispel
    local dispelType = f._msufGFDispelType
    if dispelType and HLVal(kind, "hlDispelEnabled") ~= false then
        local resolve = _G.MSUF_ResolveDispelColor
        local r, g, b
        if type(resolve) == "function" then
            r, g, b = resolve(dispelType)
        else
            r, g, b = GetDispelColor(dispelType)
        end
        if r then
            local sz  = HLVal(kind, "hlAggroSize") or 2
            local ofs = HLVal(kind, "hlAggroOffset") or 0
            local tex = HLVal(kind, "hlAggroTexture")
            local lay = HLVal(kind, "hlAggroLayer") or "DEFAULT"
            _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, r, g, b, 1)
            border:Show()
            return
        end
    end

    -- Priority 2: Aggro — colors from general (tied to Colors panel)
    local aggroLevel = f._msufGFAggroLevel
    if aggroLevel and aggroLevel >= 1 and HLVal(kind, "hlAggroEnabled") ~= false then
        local sz  = HLVal(kind, "hlAggroSize") or 2
        local ofs = HLVal(kind, "hlAggroOffset") or 0
        local tex = HLVal(kind, "hlAggroTexture")
        local lay = HLVal(kind, "hlAggroLayer") or "DEFAULT"
        local ar = HLColor("hlAggroColorR", 1)
        local ag = HLColor("hlAggroColorG", 0.55)
        local ab = HLColor("hlAggroColorB", 0)
        _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, ar, ag, ab, 1)
        border:Show()
        return
    end

    -- Priority 3: Target — colors from general (tied to Colors panel)
    if f._msufGFIsTarget and HLVal(kind, "hlTargetEnabled") ~= false then
        local sz  = HLVal(kind, "hlTargetSize") or 2
        local ofs = HLVal(kind, "hlTargetOffset") or 0
        local tex = HLVal(kind, "hlTargetTexture")
        local lay = HLVal(kind, "hlTargetLayer") or "DEFAULT"
        _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay,
            HLColor("hlTargetColorR", 1),
            HLColor("hlTargetColorG", 1),
            HLColor("hlTargetColorB", 1), 1)
        border:Show()
        return
    end

    border:Hide()
end

local function UpdateAggro(f, unit)
    local kind = f._msufGFKind or "party"
    local prevLevel = f._msufGFAggroLevel

    local testMode = _G.MSUF_AggroBorderTestMode
    if (HLVal(kind, "hlAggroEnabled") == false or not unit) and not testMode then
        if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
        return
    end

    if not testMode then
        if not UnitExists(unit) then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        local aggroMode = HLVal(kind, "hlAggroMode") or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
                return
            end
            if aggroMode == "TANK_ONLY" and role ~= "TANK" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
                return
            end
        end
        local status = UnitThreatSituation and UnitThreatSituation(unit)
        if issecretvalue and issecretvalue(status) then
            -- Secret: can't diff-gate, but only refresh if we had aggro before
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        local s = tonumber(status)
        if not s or s < 1 then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        -- Diff-gate: only refresh border when threat level actually changes
        if s == prevLevel then return end
        f._msufGFAggroLevel = s
    else
        if prevLevel == 3 then return end -- test mode: already at max
        f._msufGFAggroLevel = 3
    end
    _GF_RefreshBorder(f, unit)
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

    local testMode = _G.MSUF_DispelBorderTestMode

    if (HLVal(kind, "hlDispelEnabled") == false or not unit) and not testMode then
        f._msufGFDispelType = nil
        _GF_RefreshBorder(f, unit)
        return
    end

    local topDispel = nil
    if not testMode then
        if not UnitExists(unit) then
            f._msufGFDispelType = nil
            _GF_RefreshBorder(f, unit)
            return
        end
        _scanTopDispel = nil
        if AuraUtil and AuraUtil.ForEachAura then
            AuraUtil.ForEachAura(unit, "HARMFUL|RAID", nil, _DispelScanCallback, true)
        end
        topDispel = _scanTopDispel
    else
        topDispel = _G.MSUF_DispelBorderTestType or "Magic"
    end

    local prevDispel = f._msufGFDispelType
    f._msufGFDispelType = topDispel

    if topDispel == prevDispel and not testMode then return end

    _GF_RefreshBorder(f, unit)
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
-- Status text helpers (module-level — zero closure allocation)
------------------------------------------------------------------------
local function _GF_HideHealthText(f)
    if f.textLeftFS then f.textLeftFS:Hide() end
    if f.textCenterFS then f.textCenterFS:Hide() end
    if f.textRightFS then f.textRightFS:Hide() end
    if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:Hide() end
end

local function _GF_RestoreHealthText(f, conf)
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

------------------------------------------------------------------------
-- Status text: AFK / DND (red, GF-owned pipeline)
-- Status state encoding: 0=normal, 1=offline, 2=dead, 3=ghost, 4=afk, 5=dnd
------------------------------------------------------------------------
local function UpdateStatusText(f, unit)
    local st = f._msufGFStatusText or f.statusIndicatorText
    if not st then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    if not unit or not UnitExists(unit) then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
            st:SetText("")
            st:Hide()
            _GF_RestoreHealthText(f, conf)
            if f.nameText then f.nameText:Show() end
        end
        return
    end

    -- Determine new status state
    local newState = 0
    local connected = UnitIsConnected(unit)
    if issecretvalue and issecretvalue(connected) then connected = true end

    if connected == false then
        newState = 1
    elseif UnitIsDeadOrGhost(unit) then
        local ghost = UnitIsGhost and UnitIsGhost(unit)
        if issecretvalue and ghost and issecretvalue(ghost) then ghost = false end
        newState = ghost and 3 or 2
    else
        if UnitIsAFK then
            local afk = UnitIsAFK(unit)
            if not (issecretvalue and issecretvalue(afk)) and afk == true then
                newState = 4
            end
        end
        if newState == 0 and UnitIsDND then
            local dnd = UnitIsDND(unit)
            if not (issecretvalue and issecretvalue(dnd)) and dnd == true then
                newState = 5
            end
        end
    end

    -- Diff-gate: only update visuals when state actually changes
    if newState == f._msufGFStatusState then return end
    f._msufGFStatusState = newState

    if newState == 0 then
        st:SetText("")
        st:Hide()
        _GF_RestoreHealthText(f, conf)
    elseif newState == 1 then
        st:SetText("OFFLINE")
        st:SetTextColor(0.6, 0.6, 0.6, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 2 then
        st:SetText("DEAD")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 3 then
        st:SetText("GHOST")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 4 then
        st:SetText("AFK")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 5 then
        st:SetText("DND")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    end
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
    -- Spell Indicator health color override: full bar recolor, skips all normal logic
    if f._msufSIHealthColorR then
        f.health:SetStatusBarColor(f._msufSIHealthColorR, f._msufSIHealthColorG, f._msufSIHealthColorB, 1)
        f._msufGFHCStamp = nil
        return
    end
    -- Global barMode override (same as Render.ApplyHealthColor)
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = type(getCache) == "function" and getCache() or nil
    local globalMode = cache and cache.barMode
    if globalMode == "dark" then
        local r, g, b = cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0
        local stamp = "dark"
        if f._msufGFHCStamp ~= stamp then
            f._msufGFHCStamp = stamp
            f.health:SetStatusBarColor(r, g, b, 1)
        end
        return
    end
    if globalMode == "unified" then
        local r, g, b = cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90
        local stamp = "unified"
        if f._msufGFHCStamp ~= stamp then
            f._msufGFHCStamp = stamp
            f.health:SetStatusBarColor(r, g, b, 1)
        end
        return
    end
    local conf = GF.GetConf(kind)
    local mode = conf.healthColorMode or "CLASS"
    if mode == "CLASS" and unit then
        local _, cls = UnitClass(unit)
        if cls then
            -- Diff-gate: class token unchanged → skip SetStatusBarColor
            if f._msufGFHCStamp == cls then return end
            f._msufGFHCStamp = cls
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
        f._msufGFHCStamp = nil -- gradient changes every tick
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
    local stamp = "custom"
    if f._msufGFHCStamp ~= stamp then
        f._msufGFHCStamp = stamp
        f.health:SetStatusBarColor(
            conf.healthCustomR or 0.2,
            conf.healthCustomG or 0.8,
            conf.healthCustomB or 0.2, 1)
    end
end

------------------------------------------------------------------------
-- Power color (secret-safe pToken)
------------------------------------------------------------------------
local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local _, pToken = UnitPowerType(unit)
    -- Secret-safe: pToken may be secret in 12.0
    if issecretvalue and pToken and issecretvalue(pToken) then
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
        return
    end
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
    -- Auras: only full pipeline when auras enabled; otherwise standalone dispel
    local _kind = f._msufGFKind or "party"
    local _conf = GF.GetConf(_kind)
    local _auras = _conf and _conf.auras
    local _aurasOn = _auras and _auras.enabled ~= false

    local _siCfg = _conf and _conf.spellIndicators
    local _siOn = _siCfg and _siCfg.enabled == true

    if _aurasOn and GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
        local mergedDispel = f._msufGFMergedDispel
        local prevDispel = f._msufGFDispelType
        if mergedDispel ~= prevDispel then
            f._msufGFDispelType = mergedDispel
            _GF_RefreshBorder(f, unit)
        end
    else
        -- Auras disabled: hide pools once, standalone dispel only
        if GF.UpdateFrameAuras then GF.UpdateFrameAuras(f, unit) end -- cached HidePool
        GF._UpdateDispel(f, unit)
    end
    if GF.UpdateSpellIndicators then
        if _siOn then GF.UpdateSpellIndicators(f, unit) else GF.HideSpellIndicators(f) end
    end
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
    -- 3-slot health text (secret-safe: unit for UnitHealthPercent)
    -- Diff-gate: only call SetText when formatted string actually changes
    -- Secret-safe: secret strings cannot be compared with ~= in 12.0
    local delim = conf.textDelimiter or " / "
    local rev = conf.hpTextReverse
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"
    local iss = issecretvalue
    if f.textLeftFS and tl ~= "NONE" then
        local s = GF.FormatHealthText(tl, hp, hpMax, delim, rev, unit)
        local c = f._msufGFCachedTL
        if (iss and (iss(s) or (c ~= nil and iss(c)))) or c ~= s then
            f._msufGFCachedTL = (iss and iss(s)) and nil or s
            f.textLeftFS:SetText(s)
        end
    end
    if f.textCenterFS and tc ~= "NONE" then
        local s = GF.FormatHealthText(tc, hp, hpMax, delim, rev, unit)
        local c = f._msufGFCachedTC
        if (iss and (iss(s) or (c ~= nil and iss(c)))) or c ~= s then
            f._msufGFCachedTC = (iss and iss(s)) and nil or s
            f.textCenterFS:SetText(s)
        end
    end
    if f.textRightFS and tr ~= "NONE" then
        local s = GF.FormatHealthText(tr, hp, hpMax, delim, rev, unit)
        local c = f._msufGFCachedTR
        if (iss and (iss(s) or (c ~= nil and iss(c)))) or c ~= s then
            f._msufGFCachedTR = (iss and iss(s)) and nil or s
            f.textRightFS:SetText(s)
        end
    end
    -- Status: always check (internal diff-gate returns immediately if state unchanged)
    UpdateStatusText(f, unit)
    -- Heal prediction clips to missing HP — must sync when HP changes
    dispatchIncomingHeal(f, unit)
end

------------------------------------------------------------------------
-- Health prediction overlays (absorb + incoming heal + heal absorb)
-- All 12.0 secret-safe: raw API values passed to C-side SetValue/SetMinMaxValues.
-- Show/hide: issecretvalue(val) → secret = Show (non-nil means has value).
-- Colors read from global MSUF_DB.general (same keys as main UF overlays).
--
-- Absorb enable: read from MSUF_DB.general (tied to Bars menu).
-- Heal prediction enable: read from GF conf (tied to GF Options menu).
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Absorb settings resolver: reads from gf_party/gf_raid (if hlOverride),
-- falls through to MSUF_DB.general (tied to Bars menu).
------------------------------------------------------------------------
local function _GF_GetAbsorbSetting(kind, key)
    local dbKey = (kind == "raid") and "gf_raid" or "gf_party"
    local db = _G.MSUF_DB and _G.MSUF_DB[dbKey]
    if db and db.hlOverride and db[key] ~= nil then return db[key] end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return nil
end

local function _GF_IsAbsorbEnabled(kind)
    -- Check GF-local setting first (absorbEnabled in gf_party/gf_raid)
    local conf = GF.GetConf(kind)
    if conf.absorbEnabled ~= nil then return conf.absorbEnabled ~= false end
    -- Fall through to general bar settings
    local mode = _GF_GetAbsorbSetting(kind, "absorbTextMode")
    if mode then
        mode = tonumber(mode)
        if mode then return (mode == 2 or mode == 3) end
    end
    local v = _GF_GetAbsorbSetting(kind, "enableAbsorbBar")
    if v ~= nil then return (v ~= false) end
    return true
end

------------------------------------------------------------------------
-- Absorb anchoring: apply SetReverseFill based on general.absorbAnchorMode
-- Mode 1: left anchor (fill L→R)   absorbReverse=false
-- Mode 2: right anchor (fill R→L)  absorbReverse=true  (DEFAULT)
-- Mode 5: reverse from max         absorbReverse=true (normal HP bar)
-- Mode 3/4: follow HP edge — simplified to mode 2 for GF
------------------------------------------------------------------------
local function _GF_ApplyAbsorbAnchor(f)
    if not f or not f.health then return end
    local kind = f._msufGFKind or "party"
    local mode = tonumber(_GF_GetAbsorbSetting(kind, "absorbAnchorMode")) or 2

    local absorbReverse, healReverse
    if mode == 1 then
        absorbReverse = false
        healReverse   = true
    elseif mode == 5 then
        -- Reverse from max: absorb fills from HP max-edge backwards
        local hpReverse = f.health.GetReverseFill and f.health:GetReverseFill()
        absorbReverse = not hpReverse
        healReverse   = hpReverse and true or false
    else
        -- Mode 2/3/4 → right anchor (default)
        absorbReverse = true
        healReverse   = false
    end

    if f.absorbBar and f.absorbBar.SetReverseFill then
        f.absorbBar:SetReverseFill(absorbReverse and true or false)
    end
    if f.healAbsorbBar and f.healAbsorbBar.SetReverseFill then
        f.healAbsorbBar:SetReverseFill(healReverse and true or false)
    end
    if f.incomingHealBar and f.incomingHealBar.SetReverseFill then
        -- Incoming heal fills same direction as health bar
        f.incomingHealBar:SetReverseFill(false)
    end
    f._msufGFAbsorbAnchorStamp = mode
end
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
    -- Test mode: fixed values (same as main UF preview)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(20)
        bar:Show()
        return
    end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local hpEnabled = conf.healPredEnabled
    if hpEnabled == nil then
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        hpEnabled = not gen or gen.enableHealPrediction ~= false
    end
    if hpEnabled == false then bar:Hide(); return end
    if not UnitGetIncomingHeals then bar:Hide(); return end
    if not unit or not UnitExists(unit) then bar:Hide(); return end
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
    -- Test mode: fixed values, no unit/secret dependency (same as main UF)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(25)
        bar:Show()
        return
    end
    local kind = f._msufGFKind or "party"
    if not _GF_IsAbsorbEnabled(kind) then bar:Hide(); return end
    if not UnitGetTotalAbsorbs then bar:Hide(); return end
    if not unit or not UnitExists(unit) then bar:Hide(); return end
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
    -- Test mode: fixed values (same as main UF)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(15)
        bar:Show()
        return
    end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.healAbsorbEnabled == false then bar:Hide(); return end
    if not UnitGetTotalHealAbsorbs then bar:Hide(); return end
    if not unit or not UnitExists(unit) then bar:Hide(); return end
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
    -- 3-slot power text (secret-safe: unit for UnitPowerPercent)
    -- Diff-gate: only SetText when formatted string changes
    -- Secret-safe: secret strings cannot be compared with ~= in 12.0
    if conf.showPower then
        local pDelim = conf.powerTextDelimiter or " / "
        local ptl = conf.powerTextLeft   or "NONE"
        local ptc = conf.powerTextCenter  or "NONE"
        local ptr = conf.powerTextRight   or "NONE"
        local iss = issecretvalue
        if f.powerTextLeftFS and ptl ~= "NONE" then
            local s = GF.FormatPowerText(ptl, pw, pwMax, pDelim, unit)
            local c = f._msufGFCachedPTL
            if (iss and (iss(s) or (c ~= nil and iss(c)))) or c ~= s then
                f._msufGFCachedPTL = (iss and iss(s)) and nil or s
                f.powerTextLeftFS:SetText(s)
            end
        end
        if f.powerTextCenterFS and ptc ~= "NONE" then
            local s = GF.FormatPowerText(ptc, pw, pwMax, pDelim, unit)
            local c = f._msufGFCachedPTC
            if (iss and (iss(s) or (c ~= nil and iss(c)))) or c ~= s then
                f._msufGFCachedPTC = (iss and iss(s)) and nil or s
                f.powerTextCenterFS:SetText(s)
            end
        end
        if f.powerTextRightFS and ptr ~= "NONE" then
            local s = GF.FormatPowerText(ptr, pw, pwMax, pDelim, unit)
            local c = f._msufGFCachedPTR
            if (iss and (iss(s) or (c ~= nil and iss(c)))) or c ~= s then
                f._msufGFCachedPTR = (iss and iss(s)) and nil or s
                f.powerTextRightFS:SetText(s)
            end
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
    UNIT_AURA                         = function(f, u, updateInfo)
        dispatchAura(f, u, updateInfo)
    end,
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

    -- Auras/Dispel: only register UNIT_AURA when at least one consumer needs it
    local _auCfg = conf.auras
    local needAura = (_auCfg and _auCfg.enabled ~= false)
                  or (conf.dispelEnabled ~= false and GF._playerCanDispel)
                  or (conf.spellIndicators and conf.spellIndicators.enabled)
    if needAura then
        reg("UNIT_AURA")
    end

    -- Threat: always register — UpdateAggro checks hlAggroEnabled internally
    reg("UNIT_THREAT_SITUATION_UPDATE")
    reg("UNIT_THREAT_LIST_UPDATE")

    -- Status icons
    reg("INCOMING_SUMMON_CHANGED")
    reg("INCOMING_RESURRECT_CHANGED")
    reg("UNIT_PHASE")

    -- Health prediction overlays: always register — handlers gate on enabled
    -- state internally. Absorb reads from general (Bars), heal pred from GF conf.
    if UnitGetIncomingHeals then
        reg("UNIT_HEAL_PREDICTION")
    end
    if UnitGetTotalAbsorbs then
        reg("UNIT_ABSORB_AMOUNT_CHANGED")
    end
    if UnitGetTotalHealAbsorbs then
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

-- Track current target frame for O(1) TARGET_CHANGED updates
local _gfTargetFrame = nil -- the frame whose unit was last "target"

-- PLAYER_TARGET_CHANGED: update target indicator on old + new target only
-- READY_CHECK / READY_CHECK_FINISHED: update ready check icons
-- RAID_TARGET_UPDATE: update raid markers
local function OnGlobalEvent(self, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        -- Clear old target frame
        local oldTarget = _gfTargetFrame
        _gfTargetFrame = nil
        if oldTarget and oldTarget.unit then
            oldTarget._msufGFIsTarget = nil
            UpdateTargetIndicator(oldTarget, oldTarget.unit)
            _GF_RefreshBorder(oldTarget, oldTarget.unit)
        end
        -- Find new target frame (iterate once)
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) and UnitIsUnit(f.unit, "target") then
                f._msufGFIsTarget = true
                _gfTargetFrame = f
                UpdateTargetIndicator(f, f.unit)
                _GF_RefreshBorder(f, f.unit)
                break
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
        -- Lightweight refresh: only update roster-dependent data
        -- (name, role, leader, markers, status, health color, group number)
        -- Range/aura/threat/overlays arrive via their own unit events
        _gfTargetFrame = nil -- invalidate target cache (units may swap)
        for f in pairs(GF.frames) do
            local u = f.unit
            if u and UnitExists(u) then
                dispatchName(f, u)
                ApplyHealthColor(f, f._msufGFKind or "party", u)
                ApplyPowerColor(f, u)
                UpdateStatusText(f, u)
                UpdateRoleIcon(f, u)
                UpdateRaidMarker(f, u)
                UpdateLeaderIcon(f, u)
                UpdateGroupNumber(f, u)
                if UnitIsUnit(u, "target") then
                    f._msufGFIsTarget = true
                    _gfTargetFrame = f
                end
                UpdateTargetIndicator(f, u)
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
-- AFK / DND / Status OOC poll
-- UNIT_FLAGS may miss AFK transitions on distant raid members.
-- Low-frequency OOC ticker catches any missed status changes.
-- Skipped entirely in combat (AFK can't start in combat).
------------------------------------------------------------------------
do
    local _statusFrame = CreateFrame("Frame")
    local _statusElapsed = 0
    local _statusInCombat = false
    _statusFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _statusFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _statusFrame:SetScript("OnEvent", function(self, event)
        _statusInCombat = (event == "PLAYER_REGEN_DISABLED")
    end)
    _statusFrame:SetScript("OnUpdate", function(self, dt)
        if _statusInCombat then return end
        _statusElapsed = _statusElapsed + dt
        if _statusElapsed < 3 then return end
        _statusElapsed = 0
        local hasWork = false
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then
                hasWork = true
                UpdateStatusText(f, f.unit)
            end
        end
        if not hasWork then self:Hide() end
    end)
    -- Wake ticker when frames appear
    local _origRegUEStatus = GF.RegisterUnitEvents
    GF.RegisterUnitEvents = function(f, unit)
        _origRegUEStatus(f, unit)
        _statusFrame:Show()
    end
end

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

        local _rangeFrameList = {}
        local _rangeIdx = 0
        local _rangeListDirty = true -- rebuild on next tick

        -- Hook frame registry changes to mark list dirty
        local _origRegUE = GF.RegisterUnitEvents
        GF.RegisterUnitEvents = function(f, unit)
            _origRegUE(f, unit)
            _rangeListDirty = true
            _tickerFrame:Show()
        end
        local _origUnregUE = GF.UnregisterUnitEvents
        GF.UnregisterUnitEvents = function(f)
            _origUnregUE(f)
            _rangeListDirty = true
        end

        _tickerFrame:SetScript("OnUpdate", function(self, dt)
            _elapsed = _elapsed + dt
            local interval = _inCombat and 0.25 or 1
            if _elapsed < interval then return end
            _elapsed = 0

            -- Rebuild frame list only when dirty
            if _rangeListDirty then
                _rangeListDirty = false
                local idx = 0
                for f in pairs(GF.frames) do idx = idx + 1; _rangeFrameList[idx] = f end
                for i = idx + 1, #_rangeFrameList do _rangeFrameList[i] = nil end
            end

            local n = #_rangeFrameList
            if n == 0 then self:Hide(); return end

            -- Stagger: max 10 frames per tick, round-robin
            local batch = n <= 10 and n or 10
            for _ = 1, batch do
                _rangeIdx = _rangeIdx + 1
                if _rangeIdx > n then _rangeIdx = 1 end
                local f = _rangeFrameList[_rangeIdx]
                if f and f.unit and UnitExists(f.unit) then
                    ApplyRangeFade(f, f.unit)
                end
            end
        end)
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
local _tooltipPending -- C_Timer handle for deferred tooltip
local _tooltipTarget  -- frame awaiting tooltip

local function OnEnter(f)
    -- Mouseover highlight
    local hb = EnsureMouseoverHighlight(f)
    if hb then hb:Show() end
    -- Cancel any pending tooltip for a different frame
    if _tooltipPending then _tooltipPending:Cancel(); _tooltipPending = nil end
    _tooltipTarget = f
    -- Tooltip (throttled 150ms)
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
    _tooltipPending = C_Timer.NewTimer(0.15, function()
        _tooltipPending = nil
        if _tooltipTarget ~= f then return end
        if not f.unit or not UnitExists(f.unit) then return end
        if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
            _G.GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            _G.GameTooltip:SetUnit(f.unit)
            _G.GameTooltip:Show()
        end
    end)
end

local function OnLeave(f)
    -- Cancel pending tooltip
    if _tooltipPending then _tooltipPending:Cancel(); _tooltipPending = nil end
    _tooltipTarget = nil
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
--- Combined highlight refresh (aggro + dispel + target) — called by
--- Borders.lua test mode buttons via _G.MSUF_GF_UpdateHighlight
local function UpdateHighlight(f, unit)
    unit = unit or f.unit
    if not unit then return end
    UpdateAggro(f, unit)
    GF._UpdateDispel(f, unit)
    UpdateTargetIndicator(f, unit)
end

_G.MSUF_GF_UpdateAll     = UpdateAll
_G.MSUF_GF_UpdateAggro   = UpdateAggro
_G.MSUF_GF_UpdateDispel   = GF._UpdateDispel
_G.MSUF_GF_UpdateHighlight = UpdateHighlight
_G.MSUF_GF_UpdateRange    = ApplyRangeFade
_G.MSUF_GF_UpdateTarget   = UpdateTargetIndicator
_G.MSUF_GF_UpdateStatus   = UpdateStatusText
_G.MSUF_GF_UpdateGroupNum = UpdateGroupNumber

--- Refresh overlay bars (absorb + heal absorb + incoming heal) on all GF frames.
--- Called from Bars options when test mode or absorb settings change.
_G.MSUF_GF_RefreshOverlays = function()
    if not GF.frames then return end
    local testMode = _G.MSUF_AbsorbTextureTestMode
    for f in pairs(GF.frames) do
        if f._msufIsGroupFrame then
            _GF_ApplyAbsorbAnchor(f)
            local u = f.unit
            if u then
                dispatchOverlays(f, u)
            elseif testMode then
                dispatchIncomingHeal(f, nil)
                dispatchAbsorb(f, nil)
                dispatchHealAbsorb(f, nil)
            end
        end
    end
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local pf = list[i]
                if pf then
                    _GF_ApplyAbsorbAnchor(pf)
                    local u = pf.unit or pf._msufGFPreviewUnit
                    if u then
                        dispatchOverlays(pf, u)
                    elseif testMode then
                        dispatchIncomingHeal(pf, nil)
                        dispatchAbsorb(pf, nil)
                        dispatchHealAbsorb(pf, nil)
                    end
                end
            end
        end
    end
end
GF._ApplyHealthColor      = ApplyHealthColor
GF._ApplyAbsorbAnchor     = _GF_ApplyAbsorbAnchor
GF._ReadOverlayColor      = _GF_ReadOverlayColor
