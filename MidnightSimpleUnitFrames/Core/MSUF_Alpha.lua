-- Core/MSUF_Alpha.lua  Unit frame alpha / layered transparency system
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber

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
local function MSUF_Alpha_SetTextureAlpha(tex, a)
    if tex and tex.SetAlpha and type(a) == "number" then
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        tex:SetAlpha(a)
    end
 end
local function MSUF_Alpha_SetStatusTextureAlpha(sb, a)
    if not sb or not sb.GetStatusBarTexture then  return end
    local t = sb:GetStatusBarTexture()
    MSUF_Alpha_SetTextureAlpha(t, a)
 end
local function MSUF_Alpha_SetGradientAlphaArray(grads, a)
    if not grads or type(grads) ~= "table" then  return end
    for i = 1, #grads do
        MSUF_Alpha_SetTextureAlpha(grads[i], a)
    end
 end
local function MSUF_Alpha_SetTextAlpha(fs, a)
    if fs and fs.SetAlpha then
        MSUF_Alpha_SetTextureAlpha(fs, a)
    end
 end
local function MSUF_Alpha_ResetLayered(frame)
    if not frame or not frame._msufAlphaLayeredMode then
         return
    end
    local unitAlpha = frame._msufAlphaUnitAlpha or 1
    frame._msufAlphaLayeredMode = nil
    frame._msufAlphaLayerMode = nil
    frame._msufAlphaUnitAlpha = nil
    if frame.SetAlpha then
        frame:SetAlpha(unitAlpha)
    end
    local one = 1
    MSUF_Alpha_SetStatusTextureAlpha(frame.hpBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.targetPowerBar or frame.powerBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.absorbBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.healAbsorbBar, one)
    MSUF_Alpha_SetTextureAlpha(frame.hpBarBG, one)
    MSUF_Alpha_SetTextureAlpha(frame.powerBarBG, one)
    MSUF_Alpha_SetTextureAlpha(frame.bg, one)
    MSUF_Alpha_SetGradientAlphaArray(frame.hpGradients, one)
    MSUF_Alpha_SetGradientAlphaArray(frame.powerGradients, one)
    MSUF_Alpha_SetTextureAlpha(frame.portrait, one)
    MSUF_Alpha_SetTextAlpha(frame.nameText, one)
    MSUF_Alpha_SetTextAlpha(frame.hpText, one)
    MSUF_Alpha_SetTextAlpha(frame.powerText, one)
 end
local function MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, mode)
    if not frame then  return end
    if mode == true or mode == 1 or mode == "background" then
        mode = "background"
    else
        mode = "foreground"
    end
    frame._msufAlphaLayeredMode = true
    frame._msufAlphaLayerMode = mode
    frame._msufAlphaUnitAlphaFG = alphaFG
    frame._msufAlphaUnitAlphaBG = alphaBG
    if frame.SetAlpha then
        frame:SetAlpha(1)
    end
    local fg = type(alphaFG) == "number" and alphaFG or 1
    local bg = type(alphaBG) == "number" and alphaBG or 1
    if fg < 0 then fg = 0 elseif fg > 1 then fg = 1 end
    if bg < 0 then bg = 0 elseif bg > 1 then bg = 1 end
    MSUF_Alpha_SetTextureAlpha(frame.hpBarBG, bg)
    MSUF_Alpha_SetTextureAlpha(frame.powerBarBG, bg)
    MSUF_Alpha_SetTextureAlpha(frame.bg, bg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.hpBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.targetPowerBar or frame.powerBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.absorbBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.healAbsorbBar, fg)
    MSUF_Alpha_SetGradientAlphaArray(frame.hpGradients, fg)
    MSUF_Alpha_SetGradientAlphaArray(frame.powerGradients, fg)
    local one = 1
    MSUF_Alpha_SetTextureAlpha(frame.portrait, one)
    MSUF_Alpha_SetTextAlpha(frame.nameText, one)
    MSUF_Alpha_SetTextAlpha(frame.hpText, one)
    MSUF_Alpha_SetTextAlpha(frame.powerText, one)
 end
function _G.MSUF_ApplyUnitAlpha(frame, key)
    if not MSUF_DB then EnsureDB() end
    if not frame or not frame.SetAlpha then  return end
    local conf = (MSUF_DB and key) and MSUF_DB[key] or nil
    if ns and ns.UF and ns.UF.IsDisabled and ns.UF.IsDisabled(conf) then  return end
    local unit = frame.unit or key
    if not unit then  return end
    -- Do not fade the local player by range; also keep existing "dead/disconnected" behavior.
    if unit ~= "player" and (not UnitExists(unit)) then
        frame:SetAlpha(1)
         return
    end
    if unit ~= "player" and UnitIsDeadOrGhost(unit) then
        frame:SetAlpha(0.5)
         return
    end
    if unit ~= "player" and UnitIsConnected and (UnitIsConnected(unit) == false) then
        frame:SetAlpha(0.5)
         return
    end
    -- Layered alpha mode: foreground/background alphas (e.g. bars dim) without dimming text/portrait.
    local layered = _G.MSUF_Alpha_IsLayeredModeEnabled and _G.MSUF_Alpha_IsLayeredModeEnabled(key)
    if layered and frame._msufAlphaSupportsLayered then
        local layerMode = _G.MSUF_Alpha_GetLayerMode and _G.MSUF_Alpha_GetLayerMode(key) or "fgbg"
        local inCombat = (_G.MSUF_InCombat == true)
        local fgIn  = _G.MSUF_Alpha_GetAlphaInCombat and _G.MSUF_Alpha_GetAlphaInCombat(key) or 1
        local fgOut = _G.MSUF_Alpha_GetAlphaOOC and _G.MSUF_Alpha_GetAlphaOOC(key) or 1
        local bgIn  = _G.MSUF_Alpha_GetBgAlphaInCombat and _G.MSUF_Alpha_GetBgAlphaInCombat(key) or 1
        local bgOut = _G.MSUF_Alpha_GetBgAlphaOOC and _G.MSUF_Alpha_GetBgAlphaOOC(key) or 1
        local alphaFG = inCombat and fgIn or fgOut
        local alphaBG = inCombat and bgIn or bgOut
        -- Range-fade multiplier (Target/Focus). Defaults to 1.
        local rm = _G.MSUF_GetRangeFadeMul
        if type(rm) == "function" then
            local m = rm(key, unit, frame)
            if type(m) == "number" then
                if m < 0 then m = 0 elseif m > 1 then m = 1 end
                alphaFG = alphaFG * m
                alphaBG = alphaBG * m
            end
        end
        MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, layerMode)
         return
    end
    -- Non-layered alpha mode: apply one alpha to the frame.
    local a = _G.MSUF_GetDesiredUnitAlpha and _G.MSUF_GetDesiredUnitAlpha(key) or 1
    if type(a) ~= "number" then a = 1 end
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    -- Range-fade multiplier (Target/Focus). Defaults to 1.
    local rm = _G.MSUF_GetRangeFadeMul
    if type(rm) == "function" then
        local m = rm(key, unit, frame)
        if type(m) == "number" then
            if m < 0 then m = 0 elseif m > 1 then m = 1 end
            a = a * m
        end
    end
    if frame._msufAlphaLayeredMode then
        MSUF_Alpha_ResetLayered(frame)
    end
    if frame.GetAlpha then
        local cur = frame:GetAlpha() or 1
        if math.abs(cur - a) > 0.001 then
            frame:SetAlpha(a)
        end
    else
        frame:SetAlpha(a)
    end
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
local function MSUF_DoAlphaRefresh()
    if _G.MSUF_RefreshAllUnitAlphas then
        _G.MSUF_RefreshAllUnitAlphas()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if _G.MSUF_RefreshAllUnitAlphas then
                    _G.MSUF_RefreshAllUnitAlphas()
                end
             end)
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
        MSUF_DoAlphaRefresh()
     end)
end

