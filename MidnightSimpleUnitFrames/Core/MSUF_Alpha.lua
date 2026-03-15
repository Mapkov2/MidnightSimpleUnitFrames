-- Core/MSUF_Alpha.lua  Unit frame alpha / layered transparency system
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber
local issecretvalue = _G.issecretvalue

function _G.MSUF_GetDesiredUnitAlpha(key)
    if not MSUF_DB then EnsureDB() end
    local conf = key and MSUF_DB and MSUF_DB[key]
    if not conf then
         return 1
    end
    local aInLegacy  = tonumber(conf.alphaInCombat) or 1
    local aOutLegacy = tonumber(conf.alphaOutOfCombat) or 1
    local aIn, aOut = aInLegacy, aOutLegacy
    if conf.alphaExcludeTextPortrait == true then
        local mode = conf.alphaLayerMode
        if mode == true or mode == 1 or mode == "background" then
            mode = "background"
        else
            mode = "foreground"
    end
        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        else
            aIn  = tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
    end
    end
    local sync = conf.alphaSyncBoth
    if sync == nil then
        sync = conf.alphaSync
    end
    if sync then
        aOut = aIn
    end
    local inCombat = _G.MSUF_InCombat
    if inCombat == nil then
        inCombat = (F.InCombatLockdown and F.InCombatLockdown()) or false
    end
    local a = inCombat and aIn or aOut
    if a < 0 then
        a = 0
    elseif a > 1 then
        a = 1
    end
     return a
end
-- ---------------------------------------------------------------------------
-- Layered Alpha helpers ("Keep text + portrait visible")
-- These are referenced by MSUF_ApplyUnitAlpha(). They may be missing after refactors.
-- Keep them tiny + fast; only DB reads + numeric clamps.
-- ---------------------------------------------------------------------------
do
    local function _Alpha_GetConf(key)
        local db = MSUF_DB
        if not db then
            EnsureDB()
            db = MSUF_DB
        end
        return (db and key) and db[key] or nil
    end
    local function _Clamp01(a)
        if type(a) ~= "number" then  return 1 end
        if a < 0 then  return 0 end
        if a > 1 then  return 1 end
         return a
    end
    if not _G.MSUF_Alpha_IsLayeredModeEnabled then
        function _G.MSUF_Alpha_IsLayeredModeEnabled(key)
            local conf = _Alpha_GetConf(key)
            return (conf and conf.alphaExcludeTextPortrait == true) or false
        end
    end
    if not _G.MSUF_Alpha_GetLayerMode then
        function _G.MSUF_Alpha_GetLayerMode(key)
            local conf = _Alpha_GetConf(key)
            if not conf then  return "foreground" end
            local mode = conf.alphaLayerMode
            if mode == true or mode == 1 or mode == "background" then
                 return "background"
            end
             return "foreground"
        end
    end
    if not _G.MSUF_Alpha_GetAlphaInCombat then
        function _G.MSUF_Alpha_GetAlphaInCombat(key)
            local conf = _Alpha_GetConf(key)
            if not conf then  return 1 end
            local a = tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1
            return _Clamp01(a)
        end
    end
    if not _G.MSUF_Alpha_GetAlphaOOC then
        function _G.MSUF_Alpha_GetAlphaOOC(key)
            local conf = _Alpha_GetConf(key)
            if not conf then  return 1 end
            local sync = conf.alphaSyncBoth
            if sync == nil then sync = conf.alphaSync end
            if sync then
                local a = tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1
                return _Clamp01(a)
            end
            local a = tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1
            return _Clamp01(a)
        end
    end
    if not _G.MSUF_Alpha_GetBgAlphaInCombat then
        function _G.MSUF_Alpha_GetBgAlphaInCombat(key)
            local conf = _Alpha_GetConf(key)
            if not conf then  return 1 end
            local a = tonumber(conf.alphaBGInCombat) or tonumber(conf.alphaInCombat) or 1
            return _Clamp01(a)
        end
    end
    if not _G.MSUF_Alpha_GetBgAlphaOOC then
        function _G.MSUF_Alpha_GetBgAlphaOOC(key)
            local conf = _Alpha_GetConf(key)
            if not conf then  return 1 end
            local sync = conf.alphaSyncBoth
            if sync == nil then sync = conf.alphaSync end
            if sync then
                local a = tonumber(conf.alphaBGInCombat) or tonumber(conf.alphaInCombat) or 1
                return _Clamp01(a)
            end
            local a = tonumber(conf.alphaBGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1
            return _Clamp01(a)
        end
    end
end
-- ---------------------------------------------------------------------------
-- Layered alpha helpers — public API stays intact, hot path is optimized below.
-- ---------------------------------------------------------------------------
local function _SetTexAlpha(tex, a)
    if tex then tex:SetAlpha(a) end
end

local function _SetBarTexAlpha(sb, a)
    if not sb then return end
    local t = sb.GetStatusBarTexture and sb:GetStatusBarTexture()
    if t then t:SetAlpha(a) end
end

local function _SetGradArrayAlpha(grads, a)
    if not grads then return end
    for i = 1, #grads do
        local g = grads[i]
        if g then g:SetAlpha(a) end
    end
end

local function _AlphaClamp01(a)
    if type(a) ~= "number" then return 1 end
    if a < 0 then return 0 end
    if a > 1 then return 1 end
    return a
end

local function MSUF_Alpha_UseLiteRuntime()
    local db = MSUF_DB
    local general = db and db.general
    if general and general.perfLiteAlpha == false then
        return false
    end
    return true
end

local function MSUF_Alpha_SetFlat(frame, a)
    local cur = frame.GetAlpha and (frame:GetAlpha() or 1) or nil
    if cur == nil then
        frame:SetAlpha(a)
    else
        local d = cur - a
        if d < 0 then d = -d end
        if d > 0.001 then
            frame:SetAlpha(a)
        end
    end
end

local function MSUF_Alpha_GetStaticMode(frame, conf)
    if not conf or conf.loadCondActive == true then return nil end
    if conf.rangeFadeEnabled == true then return nil end

    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end

    if conf.alphaExcludeTextPortrait == true and frame._msufAlphaSupportsLayered then
        local fgIn  = _AlphaClamp01(tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1)
        local fgOut = sync and fgIn or _AlphaClamp01(tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        local bgIn  = _AlphaClamp01(tonumber(conf.alphaBGInCombat) or tonumber(conf.alphaInCombat) or 1)
        local bgOut = sync and bgIn or _AlphaClamp01(tonumber(conf.alphaBGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        if fgIn == fgOut and bgIn == bgOut then
            return "layered", fgIn, bgIn, conf.alphaLayerMode
        end
        return nil
    end

    local aIn = _AlphaClamp01(tonumber(conf.alphaInCombat) or 1)
    local aOut = sync and aIn or _AlphaClamp01(tonumber(conf.alphaOutOfCombat) or 1)
    if aIn == aOut then
        return "flat", aIn
    end
    return nil
end

local function MSUF_Alpha_ClearBaseCache(frame)
    if not frame then return end
    frame._msufAlphaBaseMode = nil
    frame._msufAlphaBaseKey = nil
    frame._msufAlphaBaseA = nil
    frame._msufAlphaBaseFG = nil
    frame._msufAlphaBaseBG = nil
    frame._msufAlphaBaseLayerMode = nil
    frame._msufAlphaRangeMul = nil
end

local function MSUF_Alpha_ResetLayered(frame)
    if not frame or not frame._msufAlphaLayeredMode then
         return
    end
    local unitAlpha = frame._msufAlphaUnitAlpha or 1
    frame._msufAlphaLayeredMode = nil
    frame._msufAlphaLayerMode = nil
    frame._msufAlphaUnitAlpha = nil
    frame._msufAlphaUnitAlphaFG = nil
    frame._msufAlphaUnitAlphaBG = nil
    frame._msufAlphaLastFG = nil
    frame._msufAlphaLastBG = nil
    if frame.SetAlpha then
        frame:SetAlpha(unitAlpha)
    end
    _SetBarTexAlpha(frame.hpBar, 1)
    _SetBarTexAlpha(frame.targetPowerBar or frame.powerBar, 1)
    _SetBarTexAlpha(frame.absorbBar, 1)
    _SetBarTexAlpha(frame.healAbsorbBar, 1)
    _SetTexAlpha(frame.hpBarBG, 1)
    _SetTexAlpha(frame.powerBarBG, 1)
    _SetTexAlpha(frame.bg, 1)
    _SetGradArrayAlpha(frame.hpGradients, 1)
    _SetGradArrayAlpha(frame.powerGradients, 1)
    _SetTexAlpha(frame.portrait, 1)
    local nt = frame.nameText;  if nt then nt:SetAlpha(1) end
    local ht = frame.hpText;    if ht then ht:SetAlpha(1) end
    local pt = frame.powerText; if pt then pt:SetAlpha(1) end
end

local function MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, mode)
    if not frame then return end
    if mode == true or mode == 1 or mode == "background" then
        mode = "background"
    else
        mode = "foreground"
    end

    local fg = type(alphaFG) == "number" and alphaFG or 1
    local bg = type(alphaBG) == "number" and alphaBG or 1
    if fg < 0 then fg = 0 elseif fg > 1 then fg = 1 end
    if bg < 0 then bg = 0 elseif bg > 1 then bg = 1 end

    if frame._msufAlphaLayeredMode and frame._msufAlphaLayerMode == mode then
        local lastFG = frame._msufAlphaLastFG or 1
        local lastBG = frame._msufAlphaLastBG or 1
        local dfg = lastFG - fg; if dfg < 0 then dfg = -dfg end
        local dbg = lastBG - bg; if dbg < 0 then dbg = -dbg end
        if dfg <= 0.001 and dbg <= 0.001 then
            return
        end
    end

    frame._msufAlphaLayeredMode = true
    frame._msufAlphaLayerMode = mode
    frame._msufAlphaUnitAlphaFG = fg
    frame._msufAlphaUnitAlphaBG = bg
    frame._msufAlphaLastFG = fg
    frame._msufAlphaLastBG = bg

    if frame.SetAlpha then
        local cur = frame.GetAlpha and (frame:GetAlpha() or 1) or nil
        if cur == nil then
            frame:SetAlpha(1)
        else
            local d = cur - 1
            if d < 0 then d = -d end
            if d > 0.001 then
                frame:SetAlpha(1)
            end
        end
    end

    _SetTexAlpha(frame.hpBarBG, bg)
    _SetTexAlpha(frame.powerBarBG, bg)
    _SetTexAlpha(frame.bg, bg)
    _SetBarTexAlpha(frame.hpBar, fg)
    _SetBarTexAlpha(frame.targetPowerBar or frame.powerBar, fg)
    _SetBarTexAlpha(frame.absorbBar, fg)
    _SetBarTexAlpha(frame.healAbsorbBar, fg)
    _SetGradArrayAlpha(frame.hpGradients, fg)
    _SetGradArrayAlpha(frame.powerGradients, fg)
    _SetTexAlpha(frame.portrait, 1)
    local nt = frame.nameText;  if nt then nt:SetAlpha(1) end
    local ht = frame.hpText;    if ht then ht:SetAlpha(1) end
    local pt = frame.powerText; if pt then pt:SetAlpha(1) end
end

local _rfMulTable = _G.MSUF_RangeFadeMul

function _G.MSUF_ApplyUnitAlpha(frame, key)
    local db = MSUF_DB
    if not db then EnsureDB(); db = MSUF_DB end
    if not frame or not frame.SetAlpha then return end
    if not _rfMulTable then _rfMulTable = _G.MSUF_RangeFadeMul end

    local conf = key and db[key] or nil
    if ns and ns.UF and ns.UF.IsDisabled and ns.UF.IsDisabled(conf) then return end

    local isEditMode = (_G.MSUF_UnitEditModeActive == true)
    local isCombatLocked = (F.InCombatLockdown and F.InCombatLockdown()) and true or false

    if conf and conf.loadCondActive and (not isEditMode) then
        local _lcShouldHide = _G.MSUF_LoadCond_ShouldHide
        if type(_lcShouldHide) == "function" and _lcShouldHide(key) then
            if not frame._msufLoadCondHidden then
                frame._msufLoadCondHidden = true
                MSUF_Alpha_ClearBaseCache(frame)
                frame:SetAlpha(0)
                if frame.EnableMouse and (not isCombatLocked) then
                    frame:EnableMouse(false)
                end
            end
            return
        end
    end

    if frame._msufLoadCondHidden then
        frame._msufLoadCondHidden = nil
        if frame.EnableMouse and (not isCombatLocked) then
            frame:EnableMouse(true)
        end
    end

    local unit = frame.unit or key
    if not unit then return end

    if unit ~= "player" then
        if not UnitExists(unit) then
            MSUF_Alpha_ClearBaseCache(frame)
            if frame._msufAlphaLayeredMode then
                MSUF_Alpha_ResetLayered(frame)
            end
            MSUF_Alpha_SetFlat(frame, 1)
            return
        end

        if UnitIsDeadOrGhost(unit) then
            MSUF_Alpha_ClearBaseCache(frame)
            if frame._msufAlphaLayeredMode then
                MSUF_Alpha_ResetLayered(frame)
            end
            MSUF_Alpha_SetFlat(frame, 0.5)
            return
        end

        if UnitIsConnected then
            local conn = UnitIsConnected(unit)
            if not (issecretvalue and issecretvalue(conn)) and conn == false then
                MSUF_Alpha_ClearBaseCache(frame)
                if frame._msufAlphaLayeredMode then
                    MSUF_Alpha_ResetLayered(frame)
                end
                MSUF_Alpha_SetFlat(frame, 0.5)
                return
            end
        end
    end

    if not conf then
        MSUF_Alpha_ClearBaseCache(frame)
        if frame._msufAlphaLayeredMode then
            MSUF_Alpha_ResetLayered(frame)
        end
        MSUF_Alpha_SetFlat(frame, 1)
        return
    end

    if MSUF_Alpha_UseLiteRuntime() then
        local staticMode, staticA, staticB, staticLayerMode = MSUF_Alpha_GetStaticMode(frame, conf)
        if staticMode == "flat" then
            frame._msufAlphaBaseMode = "flat"
            frame._msufAlphaBaseKey = key
            frame._msufAlphaBaseA = staticA
            frame._msufAlphaBaseFG = nil
            frame._msufAlphaBaseBG = nil
            frame._msufAlphaBaseLayerMode = nil
            frame._msufAlphaRangeMul = 1
            if frame._msufAlphaLayeredMode then
                MSUF_Alpha_ResetLayered(frame)
            end
            local applyA = staticA
            if isEditMode and applyA < 0.35 then applyA = 0.35 end
            MSUF_Alpha_SetFlat(frame, applyA)
            return
        elseif staticMode == "layered" then
            frame._msufAlphaBaseMode = "layered"
            frame._msufAlphaBaseKey = key
            frame._msufAlphaBaseA = nil
            frame._msufAlphaBaseFG = staticA
            frame._msufAlphaBaseBG = staticB
            frame._msufAlphaBaseLayerMode = staticLayerMode
            frame._msufAlphaRangeMul = 1
            MSUF_Alpha_ApplyLayered(frame, staticA, staticB, staticLayerMode)
            if isEditMode and (frame:GetAlpha() or 0) < 0.35 then
                frame:SetAlpha(0.35)
            end
            return
        end
    end

    if conf.alphaExcludeTextPortrait == true and frame._msufAlphaSupportsLayered then
        local inCombat = (_G.MSUF_InCombat == true)
        local sync = conf.alphaSyncBoth
        if sync == nil then sync = conf.alphaSync end

        local fgIn  = tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1
        local fgOut = sync and fgIn or (tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        local bgIn  = tonumber(conf.alphaBGInCombat) or tonumber(conf.alphaInCombat) or 1
        local bgOut = sync and bgIn or (tonumber(conf.alphaBGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        local alphaFG = inCombat and fgIn or fgOut
        local alphaBG = inCombat and bgIn or bgOut

        frame._msufAlphaBaseMode = "layered"
        frame._msufAlphaBaseKey = key
        frame._msufAlphaBaseA = nil
        frame._msufAlphaBaseFG = alphaFG
        frame._msufAlphaBaseBG = alphaBG
        frame._msufAlphaBaseLayerMode = conf.alphaLayerMode
        frame._msufAlphaRangeMul = 1

        local rfT = _rfMulTable
        if rfT then
            local m = rfT[key] or rfT[unit]
            if m and m < 1 then
                if m < 0 then m = 0 end
                frame._msufAlphaRangeMul = m
                alphaFG = alphaFG * m
                alphaBG = alphaBG * m
            end
        end

        MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, conf.alphaLayerMode)
        if isEditMode and (frame:GetAlpha() or 0) < 0.35 then
            frame:SetAlpha(0.35)
        end
        return
    end

    local aIn = tonumber(conf.alphaInCombat) or 1
    local aOut = tonumber(conf.alphaOutOfCombat) or 1
    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end
    if sync then aOut = aIn end
    local a = (_G.MSUF_InCombat == true) and aIn or aOut
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    frame._msufAlphaBaseMode = "flat"
    frame._msufAlphaBaseKey = key
    frame._msufAlphaBaseA = a
    frame._msufAlphaBaseFG = nil
    frame._msufAlphaBaseBG = nil
    frame._msufAlphaBaseLayerMode = nil
    frame._msufAlphaRangeMul = 1

    local rfT = _rfMulTable
    if rfT then
        local m = rfT[key] or rfT[unit]
        if m and m < 1 then
            if m < 0 then m = 0 end
            frame._msufAlphaRangeMul = m
            a = a * m
        end
    end

    if frame._msufAlphaLayeredMode then
        MSUF_Alpha_ResetLayered(frame)
    end

    MSUF_Alpha_SetFlat(frame, a)

    if isEditMode and a < 0.35 then
        frame:SetAlpha(0.35)
    end
end

function _G.MSUF_ApplyRangeFadeAlphaFast(frame, key, mul)
    if not frame or not frame.SetAlpha then return false end
    if not MSUF_DB then EnsureDB() end
    local conf = (MSUF_DB and key) and MSUF_DB[key] or nil
    if ns and ns.UF and ns.UF.IsDisabled and ns.UF.IsDisabled(conf) then return false end
    if _G.MSUF_UnitEditModeActive == true then return false end
    local unit = frame.unit or key
    if not unit then return false end

    if conf and conf.loadCondActive then
        local _lcShouldHide = _G.MSUF_LoadCond_ShouldHide
        if type(_lcShouldHide) == "function" and _lcShouldHide(key) then
            return false
        end
    end

    if unit ~= "player" then
        if not UnitExists(unit) then return false end
        if UnitIsDeadOrGhost(unit) then return false end
        if UnitIsConnected then
            local conn = UnitIsConnected(unit)
            if not (issecretvalue and issecretvalue(conn)) and conn == false then
                return false
            end
        end
    end

    if frame._msufAlphaBaseKey ~= key then return false end

    local m = tonumber(mul)
    if type(m) ~= "number" then m = 1 end
    if m < 0 then m = 0 elseif m > 1 then m = 1 end
    frame._msufAlphaRangeMul = m

    if frame._msufAlphaBaseMode == "layered" and frame._msufAlphaSupportsLayered then
        local fg = frame._msufAlphaBaseFG
        local bg = frame._msufAlphaBaseBG
        local mode = frame._msufAlphaBaseLayerMode
        if type(fg) ~= "number" or type(bg) ~= "number" or mode == nil then
            return false
        end
        MSUF_Alpha_ApplyLayered(frame, fg * m, bg * m, mode)
        return true
    end

    if frame._msufAlphaBaseMode == "flat" then
        local a = frame._msufAlphaBaseA
        if type(a) ~= "number" then return false end
        a = a * m
        if frame._msufAlphaLayeredMode then
            MSUF_Alpha_ResetLayered(frame)
        end
        MSUF_Alpha_SetFlat(frame, a)
        return true
    end

    return false
end
function _G.MSUF_RefreshAllUnitAlphas()
    EnsureDB()
    local UnitFrames = _G.MSUF_UnitFrames
    if not UnitFrames then  return end
    local ApplyUnitAlpha = _G.MSUF_ApplyUnitAlpha
    if type(ApplyUnitAlpha) ~= "function" then  return end
    for unitKey, f in pairs(UnitFrames) do
        if f and f.SetAlpha then
            -- Use the canonical config key (boss frames share key "boss").
            -- Important: MSUF_ApplyUnitAlpha expects a *config key*, not a conf table.
            local cfgKey = f.msufConfigKey
                or (GetConfigKeyForUnit and GetConfigKeyForUnit(f.unit or unitKey))
                or unitKey
            if cfgKey then
                -- Cache for future calls (small perf win; behavior-neutral).
                if not f.msufConfigKey then f.msufConfigKey = cfgKey end
                ApplyUnitAlpha(f, cfgKey)
            end
        end
    end
 end
local function _MSUF_ConfWantsCombatAlphaSwap(conf)
    if not conf then return false end
    local aInLegacy  = tonumber(conf.alphaInCombat) or 1
    local aOutLegacy = tonumber(conf.alphaOutOfCombat) or 1
    local aIn, aOut = aInLegacy, aOutLegacy

    if conf.alphaExcludeTextPortrait == true then
        local mode = conf.alphaLayerMode
        if mode == true or mode == 1 or mode == "background" then
            mode = "background"
        else
            mode = "foreground"
        end
        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        else
            aIn  = tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
        end
    end

    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end
    if sync then
        aOut = aIn
    end

    if aIn < 0 then aIn = 0 elseif aIn > 1 then aIn = 1 end
    if aOut < 0 then aOut = 0 elseif aOut > 1 then aOut = 1 end
    return (aIn ~= aOut)
end

-- Fast combat-only alpha refresh:
-- On combat toggles, only refresh frames whose configured alpha differs in/out-of-combat.
function _G.MSUF_RefreshCombatUnitAlphas()
    EnsureDB()
    local UnitFrames = _G.MSUF_UnitFrames
    if not UnitFrames then return false end
    local ApplyUnitAlpha = _G.MSUF_ApplyUnitAlpha
    if type(ApplyUnitAlpha) ~= "function" then return false end

    local didAny = false
    for unitKey, f in pairs(UnitFrames) do
        local conf = (MSUF_DB and unitKey) and MSUF_DB[unitKey] or nil
        if conf and _MSUF_ConfWantsCombatAlphaSwap(conf) then
            didAny = true
            if f and f.SetAlpha then
                if not f.msufConfigKey then f.msufConfigKey = unitKey end
                ApplyUnitAlpha(f, unitKey)
            end
        end
    end
    return didAny
end

-- Coalesced alpha refresh (max perf): dedupe to once per frame. Supports "combat-only" flush.
do
    local pending = false
    local pendingCombatOnly = false

    local function _Flush()
        pending = false
        local combatOnly = pendingCombatOnly
        pendingCombatOnly = false

        if combatOnly and _G.MSUF_RefreshCombatUnitAlphas then
            local didAny = _G.MSUF_RefreshCombatUnitAlphas()
            if didAny then return end
            -- If nothing actually swaps alpha on combat, skip the global refresh completely.
            return
        end

        if _G.MSUF_RefreshAllUnitAlphas then
            _G.MSUF_RefreshAllUnitAlphas()
        end
    end

    function _G.MSUF_RequestAlphaRefresh(combatOnly)
        if combatOnly then
            pendingCombatOnly = true
        end
        if pending then return end
        pending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, _Flush)
        else
            _Flush()
        end
    end
end

if not _G.MSUF_AlphaEventFrame then
    _G.MSUF_AlphaEventFrame = CreateFrame("Frame")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _G.MSUF_AlphaEventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.MSUF_InCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            _G.MSUF_InCombat = false
        end
        _G.MSUF_RequestAlphaRefresh(true)
     end)
end

