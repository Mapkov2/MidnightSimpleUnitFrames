-- ============================================================================
-- MSUF_CP_Runtime.lua — hot-path runtime/light-refresh handlers for the CP core
-- Loaded before Core/MSUF_ClassPower.lua and exposes lightweight runtime builders.
-- ============================================================================
local builders = _G.MSUF_CP_FEATURE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_FEATURE_BUILDERS = builders
end

builders.RUNTIME = function(env)
    local CP = env.CP
    local AM = env.AM
    local CPK = env.CPK
    local PT = env.PT
    local TIP = env.TIP
    local WW = env.WW
    local CPConst = env.CPConst
    local POWER_TYPE_TOKENS = env.POWER_TYPE_TOKENS
    local PLAYER_CLASS = env.PLAYER_CLASS
    local UnitPowerMax = env.UnitPowerMax
    local NotSecret = env.NotSecret
    local C_Spell = env.C_Spell
    local tonumber = env.tonumber
    local math_floor = env.math_floor
    local C_Timer = env.C_Timer

    local GetPlayerFrame = env.GetPlayerFrame
    local CP_EnsureBars = env.CP_EnsureBars
    local CP_Layout = env.CP_Layout
    local RefreshChargedPoints = env.RefreshChargedPoints
    local RunActiveUpdate = env.RunActiveUpdate
    local RunAuraSegmentedUpdate = env.RunAuraSegmentedUpdate
    local AM_UpdateValue = env.AM_UpdateValue
    local CP_ComputeStructuralSignature = env.CP_ComputeStructuralSignature
    local CP_RefreshEventBindings = env.CP_RefreshEventBindings
    local ThrottledFullRefresh = env.ThrottledFullRefresh
    local FullRefresh = env.FullRefresh
    local SetTimerBarOnUpdate = env.SetTimerBarOnUpdate
    local CP_SyncRuntimeOnUpdates = env.CP_SyncRuntimeOnUpdates
    local CP_ShouldUseLiteBindings = env.CP_ShouldUseLiteBindings
    local CP_UpdateValues_TimerBar = env.CP_UpdateValues_TimerBar
    local CP_UpdateValues_Stagger = env.CP_UpdateValues_Stagger
    local OnWarlockCastStart = env.OnWarlockCastStart
    local OnWarlockCastEnd = env.OnWarlockCastEnd
    local OnTipOfTheSpearSpellCast = env.OnTipOfTheSpearSpellCast
    local OnSpellTrackerReset = env.OnSpellTrackerReset

    local function GetResolvedVisibleMax()
        if not CP.visible or not CP.powerType then return CP.currentMax end
        local mode = CP.renderMode
        local powerType = CP.powerType
        local maxP = CP.currentMax or 1

        if mode == CPK.MODE.RUNE_CD then
            maxP = 6
        elseif mode == CPK.MODE.AURA_SINGLE or mode == CPK.MODE.CONTINUOUS or mode == CPK.MODE.STAGGER or mode == CPK.MODE.TIMER_BAR then
            maxP = 1
        elseif mode == CPK.MODE.AURA_SEGMENTED then
            if powerType == "MAELSTROM_WEAPON" then
                maxP = 10
                if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                    local spellMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.MAELSTROM_WEAPON)
                    if type(spellMax) == "number" and spellMax > 0 then maxP = spellMax end
                end
            elseif powerType == "SOUL_FRAGMENTS_VENG" then
                maxP = 6
            elseif powerType == "WHIRLWIND" then
                maxP = WW.MAX_STACKS
            elseif powerType == "TIP_OF_THE_SPEAR" then
                maxP = TIP.MAX_STACKS
            else
                maxP = 10
            end
        elseif mode == CPK.MODE.SEGMENTED or mode == CPK.MODE.FRACTIONAL then
            maxP = UnitPowerMax("player", powerType)
            if not NotSecret(maxP) or maxP == nil then
                if powerType == PT.Runes then maxP = 6
                elseif powerType == PT.ComboPoints then maxP = 7
                else maxP = CP.currentMax or 5 end
            end
        end

        maxP = math_floor(tonumber(maxP) or 0)
        if maxP < 1 then maxP = 1 end
        if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end
        return maxP
    end

    local function RefreshVisibleModeLight(newMax)
        if not CP.visible or not CP.powerType then return end
        local maxP = tonumber(newMax) or tonumber(CP.currentMax) or 1
        if maxP < 1 then maxP = 1 end

        if maxP ~= CP.currentMax then
            local pf = CP._pf or GetPlayerFrame()
            if pf then
                CP_EnsureBars(pf, maxP)
                CP_Layout(pf, maxP, CP._layoutH or ((env._cpDB.bars and env._cpDB.bars.classPowerHeight) or 4))
            else
                CP.currentMax = maxP
            end
        end

        if CP.renderMode == CPK.MODE.SEGMENTED then
            RefreshChargedPoints()
        end

        RunActiveUpdate(CP.powerType, CP.currentMax)
    end

    local function OnManaUpdate(powerToken)
        if not AM.visible then return end
        if powerToken ~= nil and powerToken ~= "MANA" then return end
        AM_UpdateValue()
    end

    local function HandleMaxPowerEvent(powerToken)
        OnManaUpdate(powerToken)

        if not CP.visible or not CP.powerType then return end
        local mode = CP.renderMode
        if mode ~= CPK.MODE.SEGMENTED and mode ~= CPK.MODE.FRACTIONAL then return end

        local expectedToken = CP.powerToken or POWER_TYPE_TOKENS[CP.powerType]
        if powerToken and expectedToken and powerToken ~= expectedToken then
            return
        end

        RefreshVisibleModeLight(GetResolvedVisibleMax())
    end

    local function HandleDisplayPowerEvent()
        local newSig = CP_ComputeStructuralSignature()
        if newSig ~= CP.structuralSig then
            ThrottledFullRefresh()
            return
        end

        if AM.visible then
            AM_UpdateValue()
        end
        if CP.visible then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
    end

    local function HandleRareStructuralEvent(useTimer)
        if CP_ShouldUseLiteBindings() then
            local newSig = CP_ComputeStructuralSignature()
            if newSig ~= CP.structuralSig then
                if useTimer and C_Timer and C_Timer.After then
                    C_Timer.After(0.1, FullRefresh)
                else
                    ThrottledFullRefresh()
                end
                return
            end

            CP_RefreshEventBindings()
            if AM.visible then
                AM_UpdateValue()
            end
            if CP.visible then
                RefreshVisibleModeLight(GetResolvedVisibleMax())
            end
            return
        end

        if useTimer and C_Timer and C_Timer.After then
            C_Timer.After(0.1, FullRefresh)
        else
            FullRefresh()
        end
    end

    local function OnPowerUpdate(powerToken)
        if not CP.visible or not CP.powerType then return end
        if CP.isAuraPower then return end
        if CP.renderMode == CPK.MODE.RUNE_CD then return end
        if CP.renderMode == CPK.MODE.TIMER_BAR then return end
        if CP.renderMode == CPK.MODE.STAGGER then return end

        local expectedToken = CP.powerToken or POWER_TYPE_TOKENS[CP.powerType]
        if powerToken and expectedToken and powerToken ~= expectedToken then
            return
        end

        RunActiveUpdate(CP.powerType, CP.currentMax)
    end

    local function OnAuraUpdate(unit)
        if CP.visible and CP.isAuraPower then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
        if CP.visible and CP.renderMode == CPK.MODE.TIMER_BAR then
            CP.tbCachedQ = -1
            local timerActive = CP_UpdateValues_TimerBar and CP_UpdateValues_TimerBar(CP.powerType, CP.currentMax)
            CP_SyncRuntimeOnUpdates(timerActive)
        end
        if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
            CP_UpdateValues_Stagger(CP.powerType, CP.currentMax)
        end
    end

    local function OnRuneUpdate(runeID, energize)
        if not CP.visible or CP.renderMode ~= CPK.MODE.RUNE_CD then return end
        if env.CP_UpdateValues_RuneCD then env.CP_UpdateValues_RuneCD(CP.powerType, CP.currentMax) end
    end

    local function OnSpellcastStart(spellID)
        if not CP.visible then return end
        if PLAYER_CLASS == "WARLOCK" and (CP.renderMode == CPK.MODE.SEGMENTED or CP.renderMode == CPK.MODE.FRACTIONAL) then
            OnWarlockCastStart(spellID)
        end
    end

    local function OnSpellcastEnd()
        if not CP.visible then return end
        if CP.wlPredDelta ~= 0 then
            OnWarlockCastEnd()
        end
    end

    return {
        GetResolvedVisibleMax = GetResolvedVisibleMax,
        RefreshVisibleModeLight = RefreshVisibleModeLight,
        OnManaUpdate = OnManaUpdate,
        HandleMaxPowerEvent = HandleMaxPowerEvent,
        HandleDisplayPowerEvent = HandleDisplayPowerEvent,
        HandleRareStructuralEvent = HandleRareStructuralEvent,
        OnPowerUpdate = OnPowerUpdate,
        OnAuraUpdate = OnAuraUpdate,
        OnRuneUpdate = OnRuneUpdate,
        OnSpellcastStart = OnSpellcastStart,
        OnSpellcastEnd = OnSpellcastEnd,
    }
end
