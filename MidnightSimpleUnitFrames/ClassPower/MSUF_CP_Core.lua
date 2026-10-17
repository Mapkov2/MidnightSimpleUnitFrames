--- ClassPower/MSUF_CP_Core.lua
--- Shared visual helpers and live event routing for the ClassPower controller.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "ClassPower/MSUF_CP_Core.lua")
local ExportPublic = MSUF.ExportPublic

--- Classic flavors (Vanilla, TBC, Mists) load this file too; read once.
local IS_CLASSIC = (MSUF.Client and MSUF.Client.IsClassic) == true

--- Perf locals: the RUNTIME handlers and the warm font/text refresh below
--- run per event, so the Lua standard functions they touch are bound once.
--- InCombatLockdown stays a global read on purpose: the layout gate is cold
--- and the combat harnesses swap that function at runtime.
local type, tostring, tonumber = type, tostring, tonumber
local OverrideRGB = _G.MSUF_CP_CONST.OverrideRGB
local math_floor, math_max, math_abs = math.floor, math.max, math.abs

--- Single owner of the player-frame resolver for the whole ClassPower module.
--- This file loads before the controller and its Surface sibling (TOC order),
--- which bind the exported function instead of carrying their own copy.
local CoreUnitFrame = MSUF.UF.GetFrame
ExportPublic("MSUF_CP_CoreUnitFrame", CoreUnitFrame)

--- Cross-file collaborators. Every provider loads before ClassPower in each
--- client TOC (Kernel, Runtime, the unit-frame runtime, Castbars), so a missing
--- one is a load-order break and fails loudly here.
local FILE = "ClassPower/MSUF_CP_Core.lua"
local Require = MSUF.Require
local GetProfileScopedCache = Require("MSUF_GetProfileScopedCache", FILE)
local GetEffectiveCooldownFrame = Require("MSUF_GetEffectiveCooldownFrame", FILE)
local ApplyCachedScreenPosition = Require("MSUF_ApplyCachedUnitFrameScreenPosition", FILE)
local CacheScreenPosition = Require("MSUF_CacheUnitFrameScreenPosition", FILE)
local ApplyPowerBarEmbedLayout = Require("MSUF_ApplyPowerBarEmbedLayout", FILE)
local FontPathEquals = Require("MSUF_FontPathEquals", FILE)
local MarkFontApplyFailed = Require("MSUF_MarkFontApplyFailed", FILE)
local GetGlobalFontSettings = Require("MSUF_GetGlobalFontSettings", FILE)

local function CP_IsUsableCooldownAnchorFrame(frame)
    local getSize = _G.MSUF_GetUsableCooldownAnchorSize
    return type(getSize) == "function" and getSize(frame, true) ~= nil
end

-- Retail anchors the complete resource stack to Essential's top edge. Older
-- quick setup profiles measured Y from the viewer bottom; convert that stored
-- distance once so a fresh or existing layout has the same small visible gap.
local function CP_AboveCooldownGap(frame, container, bars, classHeight)
    local gap = 4
    classHeight = tonumber(classHeight) or 4
    local player = _G.MSUF_DB and _G.MSUF_DB.player
    if type(player) == "table" and player.showPowerBar ~= false
        and player.powerBarDetached == true and player.detachedPowerBarAnchorToClassPower == true then
        local powerHeight = tostring(player.detachedPowerBarShape or ""):upper() == "ORB"
            and (tonumber(player.detachedPowerOrbSize) or 54)
            or (tonumber(player.detachedPowerBarHeight) or 6)
        -- Reserve the default attached-power footprint. Its editable Y offset
        -- must move the power bar relative to Class Resources, not move the
        -- Class Resource anchor in the opposite direction.
        gap = gap + math_max(0, powerHeight + 4)
    end

    local offsetY = tonumber(bars.classPowerOffsetY) or 0
    if bars.classPowerCooldownTopAnchor == true then return gap + offsetY end

    local getSize = _G.MSUF_GetUsableCooldownAnchorSize
    local viewerHeight
    if type(getSize) == "function" then viewerHeight = select(2, getSize(frame, true)) end
    local viewerScale = frame.GetEffectiveScale and frame:GetEffectiveScale()
    local classScale = container.GetEffectiveScale and container:GetEffectiveScale()
    local isSecret = _G.issecretvalue
    if isSecret and (isSecret(viewerScale) or isSecret(classScale)) then return gap end
    if type(viewerHeight) ~= "number" or type(viewerScale) ~= "number"
        or type(classScale) ~= "number" or viewerScale <= 0 or classScale <= 0 then return gap end
    local extra = math_max(0, offsetY - viewerHeight * viewerScale / classScale - classHeight - gap)
    bars.classPowerOffsetY = extra
    bars.classPowerCooldownTopAnchor = true
    return gap + extra
end

--- The MSUF Suite stacks its Utility row directly under its Essential row, so
--- the class resource bar sits on top of that Essential row instead of below
--- it. Only when the frame being anchored to is the Suite's own; every other
--- provider keeps the bar under the anchor. Cold layout path only.
local function CP_CooldownAnchorStacksAbove(anchorFrame)
    local getProvider = _G.MSUF_GetActiveCooldownAnchorProvider
    if type(getProvider) ~= "function" then return false end
    local provider, source = getProvider()
    return provider == "MSUF_Suite_CooldownManager" and source == anchorFrame
end

local coreBuilders = _G.MSUF_CP_CONST.BuilderRegistry("MSUF_CP_CORE_BUILDERS")

--- Layout can be blocked while unit frames are protected. Queue the shared
--- unit-frame reanchor instead of attempting to move ClassPower immediately.
local function RequestUFReanchorAfterCombat()
    local MSUF = _G.MSUF_NS
    local UF = MSUF and MSUF.UF
    if UF and UF.RequestReanchorAfterCombat then
        UF.RequestReanchorAfterCombat()
    end
end

local CP_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
local CP_SHAPE_TEXTURES = {
    CIRCLE = {
        fill = CP_SHAPE_MEDIA .. "pip_circle_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_circle_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_circle_edge.tga",
    },
    DIAMOND = {
        fill = CP_SHAPE_MEDIA .. "pip_diamond_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_diamond_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_diamond_edge.tga",
    },
    HEX = {
        fill = CP_SHAPE_MEDIA .. "pip_hex_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_hex_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_hex_edge.tga",
    },
}

local CP_NormalizeShape = _G.MSUF_UF_NormalizeClassPowerShape

local CP_NormalizeShapeAlign = _G.MSUF_UF_NormalizeShapeAlign

local function CP_ShapeTextures(shape)
    return CP_SHAPE_TEXTURES[CP_NormalizeShape(shape)]
end

local function CP_UseNativeShapeFill(bar, reverse)
    if bar and bar.SetReverseFill then
        bar:SetReverseFill(reverse == true)
    end
end

local function ClearShapeEdge(bar)
    if bar and bar._shapeEdge then
        bar._shapeEdge:Hide()
    end
end

--- Layout paints the pip backgrounds and the pip/separator visibility
--- directly. The mode painters (MSUF_CP_Modes.lua) skip the same writes when
--- the widget's _msufCP* stamp already holds the value, so every direct write
--- here records what it wrote: a charged pip's dimmed background or a pip a
--- single-bar mode hid is repainted by the next update after a relayout.
local function CP_LayoutBackground(bg, r, g, b, a)
    bg:SetVertexColor(r, g, b, a)
    bg._msufCPR, bg._msufCPG, bg._msufCPB, bg._msufCPA = r, g, b, a
end

local function CP_LayoutShown(region, shown)
    if shown then region:Show() else region:Hide() end
    region._msufCPShown = shown
end

local function CP_ResolveTextLayerLevel(frame, bars)
    local textLayer = tonumber(bars and bars.classPowerTextLayer) or 5
    if textLayer < 0 then textLayer = 0 elseif textLayer > 30 then textLayer = 30 end
    textLayer = math_floor(textLayer + 0.5)
    local layers = MSUF.UF and MSUF.UF.Layers
    if layers and type(layers.TextLevel) == "function" then
        return layers.TextLevel(frame, textLayer, 5)
    end
    if layers and type(layers.ElementLevel) == "function" then
        return layers.ElementLevel(textLayer, 5, 8)
    end
    local baseLevel = frame and frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or 0
    return baseLevel + 10
end

--- RUNTIME exposes hot-path event handlers back to the controller. These
--- handlers should update values or request a throttled structural refresh; they
--- should not allocate frames or perform full option normalization.
local builders = _G.MSUF_CP_CONST.BuilderRegistry("MSUF_CP_FEATURE_BUILDERS")

do
    --- Bound once by RUNTIME at controller load: the controller's state, its
    --- class facts and the entry points the handlers call back into.
    --- AcceptPowerToken: WoW Forever and the Classic flavors pass it
    --- (target-owned combo points); nil on Midnight.
    local CP, AM, CPK, PT, POWER_TYPE_TOKENS, PLAYER_CLASS
    local UnitPower, NotSecret, tonumber, C_Timer
    local GetPlayerFrame, CP_EnsureBars, CP_Layout, RefreshChargedPoints, CP_CompileVisual
    local RunActiveUpdate, RunAuraSegmentedUpdate, ResolveMaxPower, AM_UpdateValue
    local CP_ComputeStructuralSignature, CP_RefreshEventBindings
    local ThrottledFullRefresh, FullRefresh, CP_SyncRuntimeOnUpdates, CP_ShouldUseLiteBindings
    local OnWarlockCastStart, OnWarlockCastEnd, OnTipOfTheSpearSpellCast, OnSpellTrackerReset
    local AcceptPowerToken
    --- The whole env, for the two values the handlers read late.
    local runtimeEnv

    --- The visible segment count for the active render mode comes from the
    --- controller's one resolver (Refresh.ResolveMaxPower); it is separate
    --- from layout so rare max-power changes skip a full ClassPower rebuild.
    --- A secret or missing maximum keeps the current count here.
    local function GetResolvedVisibleMax()
        if not CP.visible or not CP.powerType then return CP.currentMax end
        return ResolveMaxPower(CP.powerType, CP.renderMode, CP.currentMax or 5)
    end

    --- Lightweight refresh for cases where the mode is still valid but the
    --- visible max or displayed values changed.
    local function RefreshVisibleModeLight(newMax)
        if not CP.visible or not CP.powerType then return end
        local maxP = tonumber(newMax) or tonumber(CP.currentMax) or 1
        if maxP < 1 then maxP = 1 end

        if maxP ~= CP.currentMax then
            local pf = CP._pf or GetPlayerFrame()
            if pf then
                CP_EnsureBars(pf, maxP)
                CP_Layout(pf, maxP, CP._layoutH or ((runtimeEnv._cpDB.bars and runtimeEnv._cpDB.bars.classPowerHeight) or 4),
                    CP.powerType)
            else
                CP.currentMax = maxP
            end
            --- The compiled visual knows the slots of the old maximum only: per-slot
            --- colours (ramp, custom) would leave the new pips white.
            CP_CompileVisual(CP.powerType, CP.renderMode, maxP)
        end

        if PLAYER_CLASS == "ROGUE"
            and CP.renderMode == CPK.MODE.SEGMENTED
            and CP.powerType == PT.ComboPoints
            and CP.visual and CP.visual.showCharged == true
        then
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
            if not (AcceptPowerToken and AcceptPowerToken(CP.powerType, powerToken, expectedToken)) then return end
        end

        RefreshVisibleModeLight(GetResolvedVisibleMax())
    end

    local function HandleDisplayPowerEvent()
        local flags, powerType, renderMode = CP_ComputeStructuralSignature()
        if flags ~= CP.structuralFlags
            or powerType ~= CP.structuralPowerType
            or renderMode ~= CP.structuralRenderMode then
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

    --- Classic only: a form change delivers UPDATE_SHAPESHIFT_FORM and
    --- UNIT_DISPLAYPOWER together and the display-power path usually rebuilds
    --- first, so the deferred rebuild re-checks the signature instead of
    --- rebuilding twice. Mainline defers FullRefresh itself.
    --- The Classic clients refresh a deferred structural change only when the
    --- structural signature really moved; Midnight always refreshes.
    local DeferredStructuralRefresh
    local function ClassicDeferredStructuralRefresh()
        local flags, powerType, renderMode = CP_ComputeStructuralSignature()
        if flags ~= CP.structuralFlags
            or powerType ~= CP.structuralPowerType
            or renderMode ~= CP.structuralRenderMode then
            FullRefresh()
        end
    end

    local structuralRefreshPending = false
    local structuralRefreshWork
    local function RunDeferredStructuralRefresh()
        local refresh = structuralRefreshWork
        structuralRefreshPending = false
        structuralRefreshWork = nil
        refresh()
    end

    --- Spec swaps emit several structural events together. One delayed key
    --- keeps the existing settle window and the client's signature re-check.
    local function ScheduleStructuralRefresh(refresh)
        structuralRefreshWork = refresh
        if structuralRefreshPending then return end
        structuralRefreshPending = true
        local scheduler = MSUF.Scheduler
        if scheduler then
            scheduler.ScheduleAfter("MSUF_CP_STRUCTURAL_REFRESH", 0.1, RunDeferredStructuralRefresh)
        else
            C_Timer.After(0.1, RunDeferredStructuralRefresh)
        end
    end

    --- Talent/spec/display events can invalidate render mode. Compare the
    --- structural signature first; only fall back to FullRefresh when the shape
    --- of the resource display actually changed.
    local function HandleRareStructuralEvent(useTimer)
        if CP_ShouldUseLiteBindings() then
            local flags, powerType, renderMode = CP_ComputeStructuralSignature()
            if flags ~= CP.structuralFlags
                or powerType ~= CP.structuralPowerType
                or renderMode ~= CP.structuralRenderMode then
                if useTimer then
                    ScheduleStructuralRefresh(DeferredStructuralRefresh)
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

        if useTimer then
            ScheduleStructuralRefresh(FullRefresh)
        else
            FullRefresh()
        end
    end

    --- Frequent UNIT_POWER path. Filter by token and render mode before calling
    --- RunActiveUpdate so aura/timer/stagger modes do not do duplicate work.
    local function OnPowerUpdate(powerToken)
        if not CP.visible or not CP.powerType then return end
        if CP.isAuraPower then return end
        if not CP.modeDescriptor.powerUpdate then return end

        local expectedToken = CP.powerToken or POWER_TYPE_TOKENS[CP.powerType]
        if powerToken and expectedToken and powerToken ~= expectedToken then
            if not (AcceptPowerToken and AcceptPowerToken(CP.powerType, powerToken, expectedToken)) then return end
            --- A borrowed token (Energy for target-owned combo points) ticks
            --- several times a second: repaint only when the points the bar
            --- shows really moved. The renderer records what it painted.
            local painted = CP.paintedComboPoints
            if painted ~= nil and UnitPower and CP.powerType == PT.ComboPoints then
                local points = UnitPower("player", PT.ComboPoints)
                if NotSecret(points) and points == painted then return end
            end
        end

        RunActiveUpdate(CP.powerType, CP.currentMax)
    end

    --- Aura-backed class resources keep their own player-only UNIT_AURA traffic.
    --- Ebon Might is native AuraContainer-owned in 12.1 and never enters this
    --- path; only segmented aura resources and Stagger update here.
    local function OnAuraUpdate(unit)
        if CP.visible and (CP.isAuraPower or CP.renderMode == CPK.MODE.SIGNED_CONTINUOUS) then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
        if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
    end

    local function OnRuneUpdate(runeID, energize)
        if not CP.visible or CP.renderMode ~= CPK.MODE.RUNE_CD then return end
        if RunActiveUpdate then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        elseif runtimeEnv.CP_UpdateValues_RuneCD then
            runtimeEnv.CP_UpdateValues_RuneCD(CP.powerType, CP.currentMax)
            if CP_SyncRuntimeOnUpdates then CP_SyncRuntimeOnUpdates(false) end
        end
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

    local API = {
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

    builders.RUNTIME = function(env)
        CP, AM, CPK, PT = env.CP, env.AM, env.CPK, env.PT
        POWER_TYPE_TOKENS, PLAYER_CLASS = env.POWER_TYPE_TOKENS, env.PLAYER_CLASS
        UnitPower, NotSecret, tonumber, C_Timer = env.UnitPower, env.NotSecret, env.tonumber, env.C_Timer
        GetPlayerFrame, CP_EnsureBars, CP_Layout = env.GetPlayerFrame, env.CP_EnsureBars, env.CP_Layout
        CP_CompileVisual = env.CP_CompileVisual
        RefreshChargedPoints, RunActiveUpdate = env.RefreshChargedPoints, env.RunActiveUpdate
        RunAuraSegmentedUpdate, ResolveMaxPower = env.RunAuraSegmentedUpdate, env.ResolveMaxPower
        AM_UpdateValue, CP_ComputeStructuralSignature = env.AM_UpdateValue, env.CP_ComputeStructuralSignature
        CP_RefreshEventBindings, ThrottledFullRefresh = env.CP_RefreshEventBindings, env.ThrottledFullRefresh
        FullRefresh, CP_SyncRuntimeOnUpdates = env.FullRefresh, env.CP_SyncRuntimeOnUpdates
        CP_ShouldUseLiteBindings = env.CP_ShouldUseLiteBindings
        OnWarlockCastStart, OnWarlockCastEnd = env.OnWarlockCastStart, env.OnWarlockCastEnd
        OnTipOfTheSpearSpellCast, OnSpellTrackerReset = env.OnTipOfTheSpearSpellCast, env.OnSpellTrackerReset
        AcceptPowerToken = env.AcceptPowerToken
        runtimeEnv = env
        DeferredStructuralRefresh = IS_CLASSIC and ClassicDeferredStructuralRefresh or FullRefresh
        return API
    end
end

--- SPECIALS contains class-specific prediction/state that is not a generic
--- power-token event. Keeping these rules isolated prevents RUNTIME from turning
--- into a spec-by-spec rules table.
do
    --- Bound once by SPECIALS at controller load.
    local CP, _cpDB, CPConst, TIP, PLAYER_CLASS, GetSpec, GetTime, math_min
    local C_SpellBook, C_Timer, RunActiveUpdate, RunAuraSegmentedUpdate

    --- Warlock shard prediction is speculative UI only; it is cleared on cast
    --- end and never writes profile/runtime structure.
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

    local function ResetTipState(render)
        CP.spStacks = 0
        CP.spExpires = nil
        if render and CP.visible and CP.powerType == "TIP_OF_THE_SPEAR" then
            RunAuraSegmentedUpdate()
        end
    end

    --- One callback serves every scheduled expiry, so a cast allocates no
    --- closure. A timer from an earlier cast finds the later expiry still ahead,
    --- or the stacks already reset (spExpires nil), and does nothing.
    local function OnTipExpiry()
        if CP.spExpires and GetTime() >= CP.spExpires then
            ResetTipState(true)
        end
    end

    local function ScheduleTipExpiry()
        if not (C_Timer and type(C_Timer.After) == "function") then return end
        C_Timer.After(TIP.DURATION + 0.05, OnTipExpiry)
    end

    local function NormalizeExpiredTipState()
        if CP.spExpires and GetTime() >= CP.spExpires then
            ResetTipState(false)
        end
    end

    --- Secret-safe contract: Tip is derived exclusively from successful
    --- player casts. No aura lookup, UNIT_AURA parsing, polling, or OnUpdate.
    local function OnTipOfTheSpearSpellCast(spellID)
        local isRelevant = spellID == TIP.KILL_COMMAND
            or spellID == TIP.TAKEDOWN
            or TIP.SPENDERS[spellID] == true
        if not isRelevant then return end
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        if not known then return end
        if not known(TIP.TALENT_ID) then return end
        NormalizeExpiredTipState()
        if spellID == TIP.KILL_COMMAND then
            local gain = known(TIP.PRIMAL_SURGE) and 2 or 1
            CP.spStacks = math_min(TIP.MAX_STACKS, CP.spStacks + gain)
            CP.spExpires = GetTime() + TIP.DURATION
            ScheduleTipExpiry()
            RunAuraSegmentedUpdate()
            return
        end
        if spellID == TIP.TAKEDOWN and known(TIP.TWIN_FANG) then
            --- Twin Fangs grants three, then its impact spends one. Resolve the
            --- net result here so same-frame event ordering cannot leave +1.
            CP.spStacks = math_min(TIP.MAX_STACKS,
                CP.spStacks + (TIP.TWIN_FANG_GAIN or 3)) - 1
            CP.spExpires = GetTime() + TIP.DURATION
            ScheduleTipExpiry()
            RunAuraSegmentedUpdate()
            return
        end
        if TIP.SPENDERS[spellID] and CP.spStacks > 0 then
            if spellID == TIP.TAKEDOWN_HIT and known(TIP.TWIN_FANG) then return end
            CP.spStacks = CP.spStacks - 1
            if CP.spStacks == 0 then
                CP.spExpires = nil
            end
            RunAuraSegmentedUpdate()
        end
    end

    local function OnSpellTrackerReset()
        ResetTipState(false)
    end

    local API = {
        OnWarlockCastStart = OnWarlockCastStart,
        OnWarlockCastEnd = OnWarlockCastEnd,
        OnTipOfTheSpearSpellCast = OnTipOfTheSpearSpellCast,
        OnSpellTrackerReset = OnSpellTrackerReset,
    }

    builders.SPECIALS = function(env)
        CP, _cpDB, CPConst, TIP = env.CP, env._cpDB, env.CPConst, env.TIP
        PLAYER_CLASS, GetSpec, GetTime = env.PLAYER_CLASS, env.GetSpec, env.GetTime
        math_min, C_SpellBook, C_Timer = env.math_min, env.C_SpellBook, env.C_Timer
        RunActiveUpdate, RunAuraSegmentedUpdate = env.RunActiveUpdate, env.RunAuraSegmentedUpdate
        return API
    end
end

MSUF.CPFactoryShared = MSUF.CPFactoryShared or {}
MSUF.CPFactoryShared.Core = {
    ApplyCachedScreenPosition = ApplyCachedScreenPosition,
    ApplyPowerBarEmbedLayout = ApplyPowerBarEmbedLayout,
    CP_AboveCooldownGap = CP_AboveCooldownGap,
    CP_CooldownAnchorStacksAbove = CP_CooldownAnchorStacksAbove,
    CP_IsUsableCooldownAnchorFrame = CP_IsUsableCooldownAnchorFrame,
    CP_LayoutBackground = CP_LayoutBackground,
    CP_LayoutShown = CP_LayoutShown,
    CP_NormalizeShape = CP_NormalizeShape,
    CP_NormalizeShapeAlign = CP_NormalizeShapeAlign,
    CP_ResolveTextLayerLevel = CP_ResolveTextLayerLevel,
    CP_ShapeTextures = CP_ShapeTextures,
    CP_UseNativeShapeFill = CP_UseNativeShapeFill,
    CacheScreenPosition = CacheScreenPosition,
    ClearShapeEdge = ClearShapeEdge,
    CoreUnitFrame = CoreUnitFrame,
    FontPathEquals = FontPathEquals,
    GetEffectiveCooldownFrame = GetEffectiveCooldownFrame,
    GetGlobalFontSettings = GetGlobalFontSettings,
    GetProfileScopedCache = GetProfileScopedCache,
    IS_CLASSIC = IS_CLASSIC,
    MarkFontApplyFailed = MarkFontApplyFailed,
    OverrideRGB = OverrideRGB,
    PixelLayoutRegion = PixelLayoutRegion,
    RequestUFReanchorAfterCombat = RequestUFReanchorAfterCombat,
    builders = coreBuilders,
    math_abs = math_abs,
    math_floor = math_floor,
    math_max = math_max,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
}
