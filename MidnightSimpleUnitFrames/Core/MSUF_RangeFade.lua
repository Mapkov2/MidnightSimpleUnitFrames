-- ============================================================================
-- MSUF RangeFade (12.0 / Midnight) - extracted from MidnightSimpleUnitFrames.lua
-- No behavior change; this file exists to reduce main file size.
--
-- Owns:
--   - _G.MSUF_RangeFadeMul + _G.MSUF_GetRangeFadeMul
--   - R41z0r-style event-driven RangeFade engine (Target)
--   - Focus/Boss (boss1-5) RangeFade module (event-driven, no ticker)
--   - _G.MSUF_RangeFade_InitPostLogin(): call once after unitframes exist
-- ============================================================================

_G.MSUF_RangeFadeMul = _G.MSUF_RangeFadeMul or {}

-- Return a multiplier for layered/non-layered alpha paths.
-- Signature supports legacy callers: (key, unit, frame).
function _G.MSUF_GetRangeFadeMul(key, unit, frame)
    local t = _G.MSUF_RangeFadeMul
    if not t then return 1 end
    local v = t[key]
    if type(v) == "number" then
        return v
    end
    if unit then
        v = t[unit]
        if type(v) == "number" then
            return v
        end
    end
    return 1
end

-- ============================================================================
-- R41z0r-style RangeFade Engine (event-driven, no polling, OFF = 0 overhead)
-- Public API:
--   MSUF_RangeFade_Register(getConfigFn, applyAlphaFn [, opts])
--   MSUF_RangeFade_OnEvent_SpellRangeUpdate(spellIdentifier, isInRange, checksRange)
--   MSUF_RangeFade_RebuildSpells()
--   MSUF_RangeFade_ApplyCurrent(force)
--   MSUF_RangeFade_Reset()
--   MSUF_RangeFade_Shutdown()
-- ============================================================================

do
    -- Fast locals
    local tonumber = tonumber
    local pairs   = pairs
    local wipe    = wipe
    local type    = type

    -- Feature detection (hard gate)
    local hasCSpell = (type(C_Spell) == "table")
    local EnableSpellRangeCheck         = hasCSpell and C_Spell.EnableSpellRangeCheck or nil
    local SpellHasRange                 = hasCSpell and C_Spell.SpellHasRange or nil
    local GetSpellIDForSpellIdentifier  = hasCSpell and C_Spell.GetSpellIDForSpellIdentifier or nil

    local hasCSpellBook = (type(C_SpellBook) == "table")
    local GetNumSkillLines           = hasCSpellBook and C_SpellBook.GetNumSpellBookSkillLines or nil
    local GetSkillLineInfo           = hasCSpellBook and C_SpellBook.GetSpellBookSkillLineInfo or nil
    local GetSpellBookItemInfo       = hasCSpellBook and C_SpellBook.GetSpellBookItemInfo or nil
    local GetSpellBookItemSpellInfo  = hasCSpellBook and C_SpellBook.GetSpellBookItemSpellInfo or nil
    local GetSpellBookItemType       = hasCSpellBook and C_SpellBook.GetSpellBookItemType or nil

    -- SpellBook bank: prefer enum, fallback to the common string.
    local SPELLBOOK_BOOKTYPE_SPELL =
      (type(Enum) == "table" and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "player"

    local RF = {
        getConfigFn  = nil,
        applyAlphaFn = nil,

        ignoreSpellIDs = nil,
        maxTracked = 512,

        enabled = false,
        alpha = 0.5,
        ignoreUnlimited = true,

        activeSpells = {}, -- [spellID] = true
        spellState   = {}, -- [spellID] = 1/0/nil
        activeCount  = 0,

        inRangeAny = true,
        lastAppliedAlpha = -1,
    }

    local DEFAULT_IGNORES = { [2096] = true } -- Mind Vision

    local function RF_ComputeDesiredAlpha()
        if RF.inRangeAny then
            return 1
        end
        return RF.alpha
    end

    local function RF_ApplyAlphaIfChanged(force)
        local a = RF_ComputeDesiredAlpha()
        if (not force) and (a == RF.lastAppliedAlpha) then
            return
        end
        RF.lastAppliedAlpha = a
        local fn = RF.applyAlphaFn
        if fn then
            fn(a, RF.enabled)
        end
    end

    local function RF_RecomputeInRangeAny()
        local anyKnown = false
        local anyTrue = false
        for _, v in pairs(RF.spellState) do
            if v ~= nil then
                anyKnown = true
                if v == 1 then
                    anyTrue = true
                    break
                end
            end
        end
        RF.inRangeAny = (not anyKnown) or anyTrue
    end

    local function RF_ResolveSpellID(spellIdentifier)
        local id = tonumber(spellIdentifier)
        if id then return id end
        if GetSpellIDForSpellIdentifier then
            local okId = GetSpellIDForSpellIdentifier(spellIdentifier)
            if okId then return okId end
        end
        return nil
    end

    local function RF_EnableSpell(spellID)
        if RF.activeSpells[spellID] then return end
        if RF.activeCount >= RF.maxTracked then return end
        RF.activeSpells[spellID] = true
        RF.activeCount = RF.activeCount + 1
        EnableSpellRangeCheck(spellID, true)
    end

    local function RF_DisableSpell(spellID)
        if not RF.activeSpells[spellID] then return end
        RF.activeSpells[spellID] = nil
        RF.activeCount = RF.activeCount - 1
        EnableSpellRangeCheck(spellID, false)
        RF.spellState[spellID] = nil
    end

    local function RF_DisableAllSpells()
        for spellID in pairs(RF.activeSpells) do
            EnableSpellRangeCheck(spellID, false)
        end
        wipe(RF.activeSpells)
        wipe(RF.spellState)
        RF.activeCount = 0
        RF.inRangeAny = true
    end

    local function RF_ShouldTrackSpell(spellID)
        if not spellID then return false end
        if RF.ignoreSpellIDs and RF.ignoreSpellIDs[spellID] then return false end
        if (RF.ignoreUnlimited == true) and SpellHasRange then
            local hasRange = SpellHasRange(spellID)
            if hasRange ~= true then
                return false
            end
        end
        return true
    end

    local function RF_BuildWantedSpellSet(outWanted)
        wipe(outWanted)

        if (not hasCSpellBook) or (not GetNumSkillLines) or (not GetSkillLineInfo) or (not GetSpellBookItemInfo) then
            return outWanted
        end

        local numLines = GetNumSkillLines()
        if (not numLines) or (numLines <= 0) then
            return outWanted
        end

        local tracked = 0
        for lineIndex = 1, numLines do
            local info = GetSkillLineInfo(lineIndex)
            if info then
                local offset =
                    info.itemIndexOffset or info.itemIndexOffsetFromStart or info.itemIndexOffsetFromStartIndex
                local numItems =
                    info.numSpellBookItems or info.numSpellBookItemSlots or info.numSpellBookItemsInLine

                if offset and numItems and numItems > 0 then
                    local first = offset + 1
                    local last  = offset + numItems

                    for slot = first, last do
                        local itemInfo = GetSpellBookItemInfo(slot, SPELLBOOK_BOOKTYPE_SPELL)
                        if itemInfo then
                            local isPassive = (itemInfo.isPassive == true)

                            local itemType = itemInfo.itemType
                            if GetSpellBookItemType and (itemType == nil) then
                                itemType = GetSpellBookItemType(slot, SPELLBOOK_BOOKTYPE_SPELL)
                            end

                            local isSpellType = true
                            if type(itemType) == "string" then
                                if (itemType ~= "SPELL") and (itemType ~= "Spell") then
                                    isSpellType = false
                                end
                            elseif (type(itemType) == "number")
                                and (type(Enum) == "table")
                                and Enum.SpellBookItemType
                                and Enum.SpellBookItemType.Spell
                            then
                                isSpellType = (itemType == Enum.SpellBookItemType.Spell)
                            end

                            if (isSpellType == true) and (isPassive ~= true) then
                                local spellID = itemInfo.spellID

                                if (not spellID) and GetSpellBookItemSpellInfo then
                                    local sp = GetSpellBookItemSpellInfo(slot, SPELLBOOK_BOOKTYPE_SPELL)
                                    if sp then
                                        spellID = sp.spellID or sp.actionID
                                    end
                                end

                                if not spellID then
                                    spellID = itemInfo.actionID
                                end

                                if spellID and RF_ShouldTrackSpell(spellID) then
                                    if not outWanted[spellID] then
                                        outWanted[spellID] = true
                                        tracked = tracked + 1
                                        if tracked >= RF.maxTracked then
                                            return outWanted
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return outWanted
    end

    local _wanted = {}

    local function RF_SyncActiveToWanted()
        for spellID in pairs(RF.activeSpells) do
            if not _wanted[spellID] then
                RF_DisableSpell(spellID)
            end
        end
        for spellID in pairs(_wanted) do
            if not RF.activeSpells[spellID] then
                RF_EnableSpell(spellID)
            end
        end
        RF_RecomputeInRangeAny()
    end

    function _G.MSUF_RangeFade_RebuildSpells()
        if not EnableSpellRangeCheck then
            RF.enabled = false
            RF_DisableAllSpells()
            RF_ApplyAlphaIfChanged(true)
            return
        end
        local cfgFn = RF.getConfigFn
        if not cfgFn then
            RF.enabled = false
            RF_DisableAllSpells()
            RF_ApplyAlphaIfChanged(true)
            return
        end

        local enabled, alpha, ignoreUnlimited = cfgFn()
        RF.enabled = (enabled == true)
        if type(alpha) == "number" then
            RF.alpha = alpha
        end
        RF.ignoreUnlimited = (ignoreUnlimited == true)

        if RF.ignoreSpellIDs == nil then
            RF.ignoreSpellIDs = DEFAULT_IGNORES
        end

        if RF.enabled ~= true then
            RF_DisableAllSpells()
            RF_ApplyAlphaIfChanged(true)
            return
        end

        RF_BuildWantedSpellSet(_wanted)
        RF_SyncActiveToWanted()
        RF_ApplyAlphaIfChanged(true)
    end

    function _G.MSUF_RangeFade_OnEvent_SpellRangeUpdate(spellIdentifier, isInRange, checksRange)
        if RF.enabled ~= true then return end

        local spellID = RF_ResolveSpellID(spellIdentifier)
        if not spellID then return end
        if not RF.activeSpells[spellID] then return end
        if RF.ignoreSpellIDs and RF.ignoreSpellIDs[spellID] then return end

        if checksRange == true then
            local v = ((isInRange == true) or (isInRange == 1)) and 1 or 0
            RF.spellState[spellID] = v
        else
            RF.spellState[spellID] = nil
        end

        RF_RecomputeInRangeAny()
        RF_ApplyAlphaIfChanged(false)
    end

    function _G.MSUF_RangeFade_ApplyCurrent(force)
        if RF.enabled ~= true then
            RF.lastAppliedAlpha = -1
            RF_ApplyAlphaIfChanged(true)
            return
        end
        RF_ApplyAlphaIfChanged(force == true)
    end

    function _G.MSUF_RangeFade_Reset()
        wipe(RF.spellState)
        RF.inRangeAny = true
        RF.lastAppliedAlpha = -1
        RF_ApplyAlphaIfChanged(true)
    end

    function _G.MSUF_RangeFade_Shutdown()
        RF.enabled = false
        RF.getConfigFn = nil
        RF.applyAlphaFn = nil
        RF_DisableAllSpells()
        RF.lastAppliedAlpha = -1
        RF_ApplyAlphaIfChanged(true)
    end

    function _G.MSUF_RangeFade_Register(getConfigFn, applyAlphaFn, opts)
        RF.getConfigFn  = getConfigFn
        RF.applyAlphaFn = applyAlphaFn

        if type(opts) == "table" then
            if type(opts.maxTracked) == "number" and opts.maxTracked > 0 then
                RF.maxTracked = opts.maxTracked
            end
            if type(opts.ignoreSpellIDs) == "table" then
                opts.ignoreSpellIDs[2096] = true
                RF.ignoreSpellIDs = opts.ignoreSpellIDs
            end
        end
        if RF.ignoreSpellIDs == nil then
            RF.ignoreSpellIDs = DEFAULT_IGNORES
        end
    end

    function _G.MSUF_RangeFade_GetState()
        return RF.enabled, RF.inRangeAny, RF.alpha, RF.activeCount
    end
end


-- ============================================================================
-- Phase 2: Event Wiring (minimal & clean)
-- Uses MSUF_EventBus (no extra OnUpdate / no polling). Target-only integration
-- happens during PLAYER_LOGIN after target frame creation.
-- ============================================================================

do
    local wired = false
    function _G.MSUF_RangeFade_WireEvents()
        if wired then return end
        wired = true

        local reg = _G.MSUF_EventBus_Register
        if type(reg) ~= "function" then
            return
        end

        -- Hot path: fires only on range state changes (Blizzard-driven).
        reg("SPELL_RANGE_CHECK_UPDATE", "MSUF_RANGEFADE", function(event, spellIdentifier, isInRange, checksRange)
            local fn = _G.MSUF_RangeFade_OnEvent_SpellRangeUpdate
            if fn then
                fn(spellIdentifier, isInRange, checksRange)
            end
        end)

        local function Rebuild()
            local fn = _G.MSUF_RangeFade_RebuildSpells
            if fn then
                fn()
            end
        end

        -- Rare rebuild triggers (spellbook/spec/talent updates).
        reg("PLAYER_ENTERING_WORLD", "MSUF_RANGEFADE", Rebuild)
        reg("SPELLS_CHANGED", "MSUF_RANGEFADE", Rebuild)
        reg("PLAYER_TALENT_UPDATE", "MSUF_RANGEFADE", Rebuild)
        reg("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "MSUF_RANGEFADE", Rebuild)
        reg("TRAIT_CONFIG_UPDATED", "MSUF_RANGEFADE", Rebuild)

        -- Target swap: clear stale in-range state (fail-safe to in-range until updates arrive).
        -- Phase 1: migrated from EventBus to UFCore hook (eliminates EventBus dispatch overhead).
        local Hook = _G.MSUF_UFCore_Hook
        if Hook then
            Hook("PLAYER_TARGET_CHANGED", "MSUF_RANGEFADE", function()
                local reset = _G.MSUF_RangeFade_Reset
                if reset then reset() end
            end)
        else
            -- Fallback: EventBus registration (UFCore not loaded yet  shouldn't happen with TOC order)
            reg("PLAYER_TARGET_CHANGED", "MSUF_RANGEFADE", function()
                local reset = _G.MSUF_RangeFade_Reset
                if reset then reset() end
            end)
        end
    end
end


-- Backwards/compat helpers (some older callers expect these symbols)
function _G.MSUF_RangeFade_Rebuild()
    if type(_G.MSUF_RangeFade_RebuildSpells) == "function" then
        _G.MSUF_RangeFade_RebuildSpells()
    end
end

function _G.MSUF_RangeFade_ApplyFromDB()
    -- RangeFade has no direct DB->apply; consumer reads MSUF_DB live.
    if type(_G.MSUF_RangeFade_ApplyCurrent) == "function" then
        _G.MSUF_RangeFade_ApplyCurrent(true)
    end
end

function _G.MSUF_RangeFade_ApplyNow()
    if type(_G.MSUF_RangeFade_ApplyCurrent) == "function" then
        _G.MSUF_RangeFade_ApplyCurrent(true)
    end
end


function _G.MSUF_RangeFade_InitPostLogin()
	-- RangeFade (target-only): defer init until AFTER all secure unitframes/headers exist.
	-- This avoids "forbidden table" taint where frames created after RangeFade become restricted.
	do
	    local function _MSUF_RF_RegisterTargetConsumerOnce()
	        if not (_G.MSUF_RangeFade_Register and _G.MSUF_RangeFade_RebuildSpells) then
	            return
	        end
	        if _G.__MSUF_RangeFadeConsumer_Target == true then
	            return
	        end
	        _G.__MSUF_RangeFadeConsumer_Target = true

	        _G.MSUF_RangeFadeMul = _G.MSUF_RangeFadeMul or {}
	        local mulT = _G.MSUF_RangeFadeMul

	        local function GetConfig()
	            local db = _G.MSUF_DB
	            local t = db and db.target
	            if not t or t.rangeFadeEnabled ~= true then
	                return false, 0.5, true
	            end
	            if _G.MSUF_UnitEditModeActive == true then
	                return false, 0.5, true
	            end
	            local a = t.rangeFadeAlpha
	            if type(a) ~= "number" then a = 0.5 end
	            if a < 0 then a = 0 elseif a > 1 then a = 1 end
	            local ignoreUnlimited = (t.rangeFadeIgnoreUnlimited ~= false)
	            return true, a, ignoreUnlimited
	        end

	        local function ApplyAlpha(desiredAlpha)
	            local cur = mulT.target
	            if type(cur) ~= "number" then cur = 1 end
	            if type(desiredAlpha) ~= "number" then desiredAlpha = 1 end
	            if cur == desiredAlpha then
	                return
	            end
	            mulT.target = desiredAlpha

	            local f = _G.MSUF_target
	            if f and f.IsForbidden and f:IsForbidden() then
	                return
	            end
	            local apply = _G.MSUF_ApplyUnitAlpha
	            if f and type(apply) == "function" then
	                apply(f, "target")
	            end
	        end

	        _G.MSUF_RangeFade_Register(GetConfig, ApplyAlpha, nil)
	    end

	    _MSUF_RF_RegisterTargetConsumerOnce()

	    if _G.MSUF_RangeFade_WireEvents then
	        _G.MSUF_RangeFade_WireEvents()
	    end

	    local function _MSUF_RF_RebuildNow()
	        if _G.MSUF_RangeFade_RebuildSpells then
	            _G.MSUF_RangeFade_RebuildSpells()
	        end
	    end

	    if C_Timer and C_Timer.After then
	        C_Timer.After(0, _MSUF_RF_RebuildNow)
	    else
	        _MSUF_RF_RebuildNow()
	    end


	-- RangeFade (Focus/Boss 1-5): Unhalted-style spell checks (FRIENDLY/RES/ENEMY), event-driven, no ticker.
	-- IMPORTANT: Target RangeFade remains handled by the R41z0r engine above and is left untouched.
	-- This module updates on cooldown / focus / encounter events (like Unhalted) to avoid polling.
	-- Secret-safe: never boolean-test secret values; only branch on NotSecretValue() outputs.
	do
	    if _G.__MSUF_RangeFadeFBInited ~= true then
	        _G.__MSUF_RangeFadeFBInited = true

	        local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
	        local issecretvalue = _G.issecretvalue
	        -- Resolve secret-value checker once (called thousands of times per second).
	        local _nsv_fn = (type(_G.NotSecretValue) == "function" and _G.NotSecretValue)
	            or (type(issecretvalue) == "function" and function(v) return issecretvalue(v) == false end)
	            or nil

	        local function NotSecretValue(v)
	            if _nsv_fn then return _nsv_fn(v) end
	            return true
	        end

	        local wipe = _G.wipe or (table and table.wipe)
	        if type(wipe) ~= "function" then
	            wipe = nil
	        end

	        local C_SpellBook = _G.C_SpellBook
	        local C_Spell = _G.C_Spell
	        local IsSpellInSpellBook = (C_SpellBook and C_SpellBook.IsSpellInSpellBook) or nil
	        local IsSpellInRange = (C_Spell and C_Spell.IsSpellInRange) or nil

	        local UnitExists = _G.UnitExists
	        local UnitInRange = _G.UnitInRange
	        local UnitPhaseReason = _G.UnitPhaseReason
	        local UnitIsPlayer = _G.UnitIsPlayer
	        local UnitCanAttack = _G.UnitCanAttack
	        local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
	        local UnitIsUnit = _G.UnitIsUnit
	        local UnitIsConnected = _G.UnitIsConnected
	        local CheckInteractDistance = _G.CheckInteractDistance
	        local InCombatLockdown = _G.InCombatLockdown

	        local playerClass = select(2, _G.UnitClass("player"))

	        -- Range spell data derived from LibRangeCheck-3.0 (MIT) via Unhalted UnitFrames.
	        -- We only use it for Focus/Boss range fades (no ticker; event-driven).
	        local RangeSpells = {
	            ENEMY = {
	                DEATHKNIGHT = { 49576, 47541 },
	                DEMONHUNTER = { 185123, 183752, 204021 },
	                DRUID = { 8921, 5176, 339, 6795, 33786, 22568 },
	                EVOKER = { 362969 },
	                HUNTER = { 75, 466930 },
	                MAGE = { 116, 133, 44425, 44614, 118, 5019 },
	                MONK = { 117952, 115546, 115078, 100780 },
	                PALADIN = { 20473, 20271, 62124, 183218, 853, 35395 },
	                PRIEST = { 585, 8092, 589, 5019 },
	                ROGUE = { 185565, 36554, 185763, 2094, 921 },
	                SHAMAN = { 188196, 8042, 117014, 370, 73899 },
	                WARLOCK = { 686, 232670, 234153, 198590, 5782, 5019 },
	                WARRIOR = { 355, 100, 5246 },
	            },
	            FRIENDLY = {
	                DEATHKNIGHT = { 47541 },
	                DEMONHUNTER = {},
	                DRUID = { 8936, 774, 88423, 2782 },
	                EVOKER = { 361469, 355913, 360823 },
	                HUNTER = {},
	                MAGE = { 1459, 475 },
	                MONK = { 116670, 115450 },
	                PALADIN = { 19750, 85673, 4987, 213644 },
	                PRIEST = { 2061, 17, 21562, 527 },
	                ROGUE = { 57934, 36554, 921 },
	                SHAMAN = { 8004, 188070, 546 },
	                WARRIOR = { 3411 },
	                WARLOCK = { 20707, 5697 },
	            },
	            RESURRECT = {
	                DEATHKNIGHT = { 61999 },
	                DEMONHUNTER = {},
	                DRUID = { 50769, 20484 },
	                EVOKER = { 361227 },
	                HUNTER = {},
	                MAGE = {},
	                MONK = { 115178 },
	                PALADIN = { 7328, 391054 },
	                PRIEST = { 2006, 212036 },
	                ROGUE = {},
	                SHAMAN = { 2008 },
	                WARRIOR = {},
	                WARLOCK = { 20707 },
	            },
	            PET = {
	                DEATHKNIGHT = { 47541 },
	                DEMONHUNTER = {},
	                DRUID = {},
	                EVOKER = {},
	                HUNTER = { 136 },
	                MAGE = {},
	                MONK = {},
	                PALADIN = {},
	                PRIEST = {},
	                ROGUE = {},
	                SHAMAN = {},
	                WARRIOR = {},
	                WARLOCK = { 755 },
	            },
	        }

	        local activeSpells = {
	            enemy = {},
	            friendly = {},
	            resurrect = {},
	            pet = {},
	        }

	        local function WipeTable(t)
	            if not t then return end
	            if type(wipe) == "function" then
	                wipe(t)
	                return
	            end
	            for k in pairs(t) do
	                t[k] = nil
	            end
	        end

	        local function UpdateActiveSpells()
	            if not IsSpellInSpellBook or not playerClass then
	                return
	            end

	            local function BuildList(dst, spellList)
	                WipeTable(dst)
	                if not spellList then return end
	                for i = 1, #spellList do
	                    local spellID = spellList[i]
	                    if spellID and IsSpellInSpellBook(spellID, nil, true) then
	                        dst[spellID] = true
	                    end
	                end
	            end

	            BuildList(activeSpells.enemy, RangeSpells.ENEMY[playerClass])
	            BuildList(activeSpells.friendly, RangeSpells.FRIENDLY[playerClass])
	            BuildList(activeSpells.resurrect, RangeSpells.RESURRECT[playerClass])
	            BuildList(activeSpells.pet, RangeSpells.PET[playerClass])
	        end

	        local function AnySpellInList(t)
	            if not t then return false end
	            return (next(t) ~= nil)
	        end

	        -- Secret-safe boolean helpers: never branch on secret values.
	        local function BoolIsTrue(v)
	            if NotSecretValue(v) then
	                return (v == true or v == 1)
	            end
	            return nil
	        end

	        local function BoolIsFalse(v)
	            if NotSecretValue(v) then
	                return (v == false or v == 0)
	            end
	            return nil
	        end

	        local function UnitExistsNS(unit)
	            if not UnitExists then return true end
	            local r = UnitExists(unit)
	            if _nsv_fn then
	                if _nsv_fn(r) then return (r == true) end
	                return true
	            end
	            return (r == true)
	        end

	        local function AllowInteractCheck()
	            if not InCombatLockdown then return false end
	            local ic = InCombatLockdown()
	            if NotSecretValue(ic) then
	                return (ic ~= true)
	            end
	            return false
	        end

	        local function UnitSpellRange(unit, spells)
	            if not IsSpellInRange or not unit or not spells then
	                return nil
	            end

	            local anyChecked = false
	            local anyOut = false
	            local nsv = _nsv_fn  -- hoist for hot loop

	            for spellID in pairs(spells) do
	                local r = IsSpellInRange(spellID, unit)
	                if not nsv or nsv(r) then
	                    anyChecked = true
	                    if r == true or r == 1 then
	                        return true
	                    end
	                    if r ~= nil then
	                        anyOut = true
	                    end
	                end
	            end

	            if anyOut then
	                return false
	            end

	            if anyChecked then
	                return nil
	            end

	            return nil
	        end

	        local function UnitInSpellsRange(unit, category)
	            local spells = activeSpells[category]
	            local inRange

	            if AnySpellInList(spells) then
	                inRange = UnitSpellRange(unit, spells)
	            end

	            -- Fallback to interact distance out of combat (helps when the player has no valid spells).
	            if (inRange ~= true) and AllowInteractCheck() and CheckInteractDistance then
	                local interact = CheckInteractDistance(unit, 4)
	                if NotSecretValue(interact) then
	                    return interact
	                end
	            end

	            return inRange
	        end

	        local function FriendlyIsInRange(unit)
	            if isRetail and UnitIsPlayer and UnitPhaseReason then
	                local isp = UnitIsPlayer(unit)
	                if BoolIsTrue(isp) == true then
	                    local pr = UnitPhaseReason(unit)
	                    if NotSecretValue(pr) and pr then
	                        return false
	                    end
	                end
	            end

	            if isRetail and UnitInRange then
	                local inR, checked = UnitInRange(unit)
	                if BoolIsTrue(checked) == true then
	                    if BoolIsFalse(inR) == true then
	                        return false
	                    end
	                end
	            end

	            return UnitInSpellsRange(unit, "friendly")
	        end

	        local function ComputeInRange_Generic(unit)
	            if not unit then return nil end
	            if not UnitExistsNS(unit) then return nil end

	            if UnitIsDeadOrGhost then
	                local d = UnitIsDeadOrGhost(unit)
	                if BoolIsTrue(d) == true then
	                    return UnitInSpellsRange(unit, "resurrect")
	                end
	            end

	            if UnitCanAttack then
	                local ca = UnitCanAttack("player", unit)
	                if BoolIsTrue(ca) == true then
	                    return UnitInSpellsRange(unit, "enemy")
	                end
	            end

	            if UnitIsUnit then
	                local isPet = UnitIsUnit(unit, "pet")
	                if BoolIsTrue(isPet) == true then
	                    return UnitInSpellsRange(unit, "pet")
	                end
	            end

	            if UnitIsConnected then
	                local conn = UnitIsConnected(unit)
	                if BoolIsTrue(conn) == true then
	                    return FriendlyIsInRange(unit)
	                end
	                if BoolIsFalse(conn) == true then
	                    return false
	                end
	            end

	            -- Unknown/secret -> treat as in-range.
	            return nil
	        end

	        local function ComputeInRange_Enemy(unit)
	            if not unit then return nil end
	            if not UnitExistsNS(unit) then return nil end

	            if UnitIsDeadOrGhost then
	                local d = UnitIsDeadOrGhost(unit)
	                if BoolIsTrue(d) == true then
	                    return UnitInSpellsRange(unit, "resurrect")
	                end
	            end

	            return UnitInSpellsRange(unit, "enemy")
	        end

	        local function ClampAlpha(a)

	            if type(a) ~= "number" then a = 0.5 end
	            if a < 0 then a = 0 elseif a > 1 then a = 1 end
	            return a
	        end

	        local function IsEnabled(conf)
	            if not conf or conf.rangeFadeEnabled ~= true then
	                return false
	            end
	            if _G.MSUF_UnitEditModeActive == true then
	                return false
	            end
	            return true
	        end

	        local function ApplyUnitRangeFade(unit, confKey, conf, computeFn)
	            local mulT = _G.MSUF_RangeFadeMul
	            if type(mulT) ~= "table" then
	                mulT = {}
	                _G.MSUF_RangeFadeMul = mulT
	            end

	            local outAlpha = ClampAlpha(conf and conf.rangeFadeAlpha)

	            local fnCompute = computeFn or ComputeInRange_Generic
	            local inRange = fnCompute(unit)
	            -- Treat unknown/uncheckable as in-range (same spirit as ignoreUnlimited).
	            local desired = (inRange == false) and outAlpha or 1

	            local cur = mulT[unit]
	            if cur == desired then
	                return
	            end

	            mulT[unit] = desired

	            local frames = _G.MSUF_UnitFrames
	            local f = frames and frames[unit]
	            if not f then
	                return
	            end
	            if f.IsForbidden and f:IsForbidden() then
	                return
	            end
	            if f.IsShown and (not f:IsShown()) then
	                return
	            end

	            local apply = _G.MSUF_ApplyUnitAlpha
	            if type(apply) == "function" then
	                apply(f, confKey)
	            end
	        end

	        local function ClearUnitMul(unit, confKey)
	            local mulT = _G.MSUF_RangeFadeMul
	            if type(mulT) ~= "table" then return end
	            if mulT[unit] == nil or mulT[unit] == 1 then
	                return
	            end
	            mulT[unit] = 1

	            local frames = _G.MSUF_UnitFrames
	            local f = frames and frames[unit]
	            if not f or (f.IsForbidden and f:IsForbidden()) then
	                return
	            end
	            local apply = _G.MSUF_ApplyUnitAlpha
	            if type(apply) == "function" then
	                apply(f, confKey)
	            end
	        end

	        local function UpdateFocus()
	            local db = _G.MSUF_DB
	            local conf = db and db.focus

	            if not IsEnabled(conf) then
	                ClearUnitMul("focus", "focus")
	                return
	            end

	            ApplyUnitRangeFade("focus", "focus", conf, ComputeInRange_Generic)
	        end

	        -- Pre-cached boss unit strings (avoid "boss"..i concat in hot loop)
	        local _bossUnits = { "boss1", "boss2", "boss3", "boss4", "boss5" }
	        local _nBossUnits = #_bossUnits

	        local function UpdateBosses()
	            local db = _G.MSUF_DB
	            local conf = db and db.boss

	            if not IsEnabled(conf) then
	                for i = 1, _nBossUnits do
	                    ClearUnitMul(_bossUnits[i], "boss")
	                end
	                return
	            end

	            local frames = _G.MSUF_UnitFrames
	            for i = 1, _nBossUnits do
	                local unit = _bossUnits[i]
	                -- Avoid extra work if unit/frame isn't up.
	                local f = frames and frames[unit]
	                if f and f.IsShown and f:IsShown() and UnitExistsNS(unit) then
	                    ApplyUnitRangeFade(unit, "boss", conf, ComputeInRange_Enemy)
	                else
	                    -- ensure we don't keep a stale out-of-range mul when the boss frame disappears
	                    local mulT = _G.MSUF_RangeFadeMul
	                    if type(mulT) == "table" and mulT[unit] and mulT[unit] ~= 1 then
	                        mulT[unit] = 1
	                    end
	                end
	            end
	        end

	        function _G.MSUF_RangeFadeFB_RebuildSpells()
	            UpdateActiveSpells()
	        end

	        function _G.MSUF_RangeFadeFB_Reset()
	            local mulT = _G.MSUF_RangeFadeMul
	            if type(mulT) ~= "table" then return end
	            mulT.focus = 1
	            for i = 1, _nBossUnits do
	                mulT[_bossUnits[i]] = 1
	            end
	        end

	        function _G.MSUF_RangeFadeFB_ApplyCurrent(force)
	            -- force kept for API symmetry; not needed for this module.
	            UpdateFocus()
	            UpdateBosses()
	        end

	        -- Initial spell selection
	        UpdateActiveSpells()

	        -- Event driver (no ticker)
	        local ef = CreateFrame("Frame")
	        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
	        ef:RegisterEvent("SPELLS_CHANGED")
	        ef:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
	        ef:RegisterEvent("PLAYER_TALENT_UPDATE")
	        ef:RegisterEvent("TRAIT_CONFIG_UPDATED")

	        ef:RegisterEvent("PLAYER_FOCUS_CHANGED")
	        ef:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")

	        -- Frequent-but-event-only updates (Unhalted-style)
	        ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	        ef:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")

	        -- Throttle: cooldown events fire 27-48x/sec in combat but range changes slowly.
	        -- Limit range checks to max 5/sec (0.2s interval) for cooldown events.
	        local _rfThrottleAt = 0
	        local _RF_THROTTLE_INTERVAL = 0.2

	        ef:SetScript("OnEvent", function(_, event)
	            if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
	                UpdateActiveSpells()
	            end

	            -- Cooldown events: throttle to avoid 27-48 range checks/sec
	            if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
	                local now = GetTime()
	                if now < _rfThrottleAt then return end
	                _rfThrottleAt = now + _RF_THROTTLE_INTERVAL
	            end

	            -- Apply (if disabled, this will clear multipliers)
	            UpdateFocus()
	            UpdateBosses()
	        end)
	    end
	end
	end
end
