-- ============================================================================
-- MSUF_CP_Specials.lua — class/resource special handlers for the CP core
-- Loaded before Core/MSUF_ClassPower.lua and exposes lightweight feature builders.
-- ============================================================================
local builders = _G.MSUF_CP_FEATURE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_FEATURE_BUILDERS = builders
end

builders.SPECIALS = function(env)
    local CP = env.CP
    local _cpDB = env._cpDB
    local CPConst = env.CPConst
    local TIP = env.TIP
    local PLAYER_CLASS = env.PLAYER_CLASS
    local GetSpec = env.GetSpec
    local GetTime = env.GetTime
    local math_min = env.math_min
    local C_SpellBook = env.C_SpellBook
    local RunActiveUpdate = env.RunActiveUpdate
    local RunAuraSegmentedUpdate = env.RunAuraSegmentedUpdate

    local function OnWarlockCastStart(spellID)
        if PLAYER_CLASS ~= "WARLOCK" then return end
        if _cpDB.showPrediction == false then return end
        local spec = GetSpec and GetSpec()
        local deltaTable = spec and CPConst.WL_SHARD_DELTAS[spec]
        local delta = deltaTable and deltaTable[spellID]
        if delta then
            CP.wlPredDelta = delta
            RunActiveUpdate()
        end
    end

    local function OnWarlockCastEnd()
        if CP.wlPredDelta == 0 then return end
        CP.wlPredDelta = 0
        RunActiveUpdate()
    end

    local function OnTipOfTheSpearSpellCast(spellID)
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        if not known then return end
        if not known(TIP.TALENT_ID) then return end
        if spellID == TIP.KILL_COMMAND then
            local gain = known(TIP.PRIMAL_SURGE) and 2 or 1
            CP.spStacks = math_min(TIP.MAX_STACKS, CP.spStacks + gain)
            CP.spExpires = GetTime() + TIP.DURATION
            CP.spCachedQ = -1
            RunAuraSegmentedUpdate()
            return
        end
        if spellID == TIP.TAKEDOWN and known(TIP.TWIN_FANG) then
            CP.spStacks = math_min(TIP.MAX_STACKS, CP.spStacks + 2)
            CP.spExpires = GetTime() + TIP.DURATION
            CP.spCachedQ = -1
            RunAuraSegmentedUpdate()
            return
        end
        if TIP.SPENDERS[spellID] and CP.spStacks > 0 then
            CP.spStacks = CP.spStacks - 1
            if CP.spStacks == 0 then CP.spExpires = nil end
            CP.spCachedQ = -1
            RunAuraSegmentedUpdate()
        end
    end

    local function OnSpellTrackerReset()
        CP.spStacks = 0
        CP.spExpires = nil
        CP.spCachedQ = -1
    end

    return {
        OnWarlockCastStart = OnWarlockCastStart,
        OnWarlockCastEnd = OnWarlockCastEnd,
        OnTipOfTheSpearSpellCast = OnTipOfTheSpearSpellCast,
        OnSpellTrackerReset = OnSpellTrackerReset,
    }
end
