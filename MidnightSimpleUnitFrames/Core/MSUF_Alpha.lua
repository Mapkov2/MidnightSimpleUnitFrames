-- Core/MSUF_Alpha.lua  Unit frame alpha / layered transparency system
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber
local issecretvalue = _G.issecretvalue

local function _AlphaNormalizeLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" then
        return "background"
    end
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

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
        local mode = _AlphaNormalizeLayerMode(conf.alphaLayerMode)
        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        elseif mode == "health" then
            aIn  = tonumber(conf.alphaHPInCombat) or tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaHPOutOfCombat) or tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
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
            return _AlphaNormalizeLayerMode(conf.alphaLayerMode)
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

local function _AlphaShouldRangeFadePortrait()
    local db = MSUF_DB
    local g = db and db.general
    return (g and g.rangeFadePortrait == true) and true or false
end

local function _AlphaSetPortraitAlpha(frame, a)
    if not frame then return end
    a = tonumber(a) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    local p = frame.portrait
    if p and p.SetAlpha then p:SetAlpha(a) end
end

local function _SetBarTexAlpha(sb, a)
    if not sb then return end
    sb._msufAlphaTextureMul = a
    local overlayAlpha = sb._msufOverlayTextureAlpha
    if type(overlayAlpha) == "number" then
        a = a * overlayAlpha
    end
    local t = sb.GetStatusBarTexture and sb:GetStatusBarTexture()
    if t then t:SetAlpha(a) end
end

local MSUF_BETTER_BLIZZARD_TEXTURE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\BetterBlizzard.blp"
local MSUF_UNHALTED_BG_R, MSUF_UNHALTED_BG_G, MSUF_UNHALTED_BG_B = 34/255, 34/255, 34/255
local _alphaUnhaltedTextureChecked, _alphaUnhaltedTexture

local function _AlphaResolveUnhaltedTexture()
    if _alphaUnhaltedTextureChecked then return _alphaUnhaltedTexture end
    _alphaUnhaltedTextureChecked = true

    local LibStub = _G.LibStub
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(LSM.Fetch) == "function" then
        local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", "Better Blizzard", true)
        if ok and type(tex) == "string" and tex ~= "" then
            _alphaUnhaltedTexture = tex
            return _alphaUnhaltedTexture
        end
    end

    _alphaUnhaltedTexture = MSUF_BETTER_BLIZZARD_TEXTURE
    return _alphaUnhaltedTexture
end

_G.MSUF_Alpha_GetPreserveHPTexture = _AlphaResolveUnhaltedTexture

local function _AlphaApplyPreserveTexture(sb, preserve)
    if not sb or not sb.SetStatusBarTexture then return end
    local tex
    if preserve == true then
        tex = _AlphaResolveUnhaltedTexture()
        if not tex then return end
    else
        tex = (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or nil
        sb._msufAlphaPreserveTexture = nil
    end
    local fill = sb.GetStatusBarTexture and sb:GetStatusBarTexture()
    local cur = fill and fill.GetTexture and fill:GetTexture()
    if tex and cur ~= tex then
        sb:SetStatusBarTexture(tex)
        sb.MSUF_cachedStatusbarTexture = tex
        sb._msufAlphaPreserveTexture = (preserve == true) and tex or nil
    end
end

local function _AlphaPreserveTextureMatches(sb)
    local want = _AlphaResolveUnhaltedTexture()
    if not want or not sb then return true end
    local fill = sb.GetStatusBarTexture and sb:GetStatusBarTexture()
    local cur = fill and fill.GetTexture and fill:GetTexture()
    if cur ~= nil then return cur == want end
    return sb._msufAlphaPreserveTexture == want
end

local function _SetBarColorAlpha(sb, a, preserve)
    if not sb or not sb.GetStatusBarColor or not sb.SetStatusBarColor then return end
    if type(a) ~= "number" then a = 1 end
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    _AlphaApplyPreserveTexture(sb, preserve == true)
    local r, g, b = sb:GetStatusBarColor()
    sb:SetStatusBarColor(r, g, b, 1)

    local backing = sb._msufAlphaPreserveBacking
    if backing then
        backing:Hide()
        sb._msufAlphaBackingR, sb._msufAlphaBackingG, sb._msufAlphaBackingB, sb._msufAlphaBackingA = nil, nil, nil, nil
    end
    sb._msufAlphaPreserveApplied = (preserve == true) or nil
end

local function _AlphaHideMissingHPBackground(frame)
    local bg = frame and frame._msufAlphaMissingHPBg
    if bg then bg:Hide() end
end

local function _AlphaEnsureMissingHPBackground(frame)
    if not frame or not frame.hpBar then return nil end
    local bg = frame._msufAlphaMissingHPBg
    if not bg then
        if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
        local CreateFrame = _G.CreateFrame
        if type(CreateFrame) ~= "function" then return nil end
        bg = CreateFrame("StatusBar", nil, frame)
        bg:SetMinMaxValues(0, 1)
        bg:SetValue(0)
        bg:SetStatusBarColor(MSUF_UNHALTED_BG_R, MSUF_UNHALTED_BG_G, MSUF_UNHALTED_BG_B, 1)
        bg:Hide()
        frame._msufAlphaMissingHPBg = bg
    end

    bg:ClearAllPoints()
    bg:SetAllPoints(frame.hpBar)
    if bg.SetFrameLevel and frame.hpBar.GetFrameLevel then
        local lvl = (frame.hpBar:GetFrameLevel() or 1) - 1
        if lvl < 0 then lvl = 0 end
        bg:SetFrameLevel(lvl)
    end
    local tex = _AlphaResolveUnhaltedTexture()
        or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture())
        or "Interface\\Buttons\\WHITE8x8"
    if bg._msufMissingBgTex ~= tex then
        bg:SetStatusBarTexture(tex)
        bg._msufMissingBgTex = tex
    end
    bg:SetStatusBarColor(MSUF_UNHALTED_BG_R, MSUF_UNHALTED_BG_G, MSUF_UNHALTED_BG_B, 1)
    if bg.SetReverseFill and frame.hpBar.GetReverseFill then
        bg:SetReverseFill(not frame.hpBar:GetReverseFill())
    end
    return bg
end

local function _AlphaSyncMissingHPBackground(frame, maxHP, hp, alpha)
    if not frame then return end
    if frame._msufAlphaPreserveHPColor ~= true then
        _AlphaHideMissingHPBackground(frame)
        return
    end
    local bg = _AlphaEnsureMissingHPBackground(frame)
    if not bg then return end

    alpha = tonumber(alpha)
    if alpha == nil then alpha = tonumber(frame._msufAlphaMissingHPAlpha) or 1 end
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    frame._msufAlphaMissingHPAlpha = alpha

    local unit = frame.unit
    if maxHP == nil and unit and _G.UnitHealthMax then
        maxHP = _G.UnitHealthMax(unit)
    end
    if maxHP == nil and frame.hpBar and frame.hpBar.GetMinMaxValues then
        local _, mx = frame.hpBar:GetMinMaxValues()
        maxHP = mx
    end

    local missing
    if unit and _G.UnitHealthMissing then
        missing = _G.UnitHealthMissing(unit, true)
    end
    if missing == nil then
        if hp == nil and unit and _G.UnitHealth then hp = _G.UnitHealth(unit) end
        if type(maxHP) == "number" and type(hp) == "number" then
            missing = maxHP - hp
            if missing < 0 then missing = 0 end
        end
    end

    bg:SetMinMaxValues(0, maxHP or 1)
    bg:SetValue(missing or 0)
    if bg.SetAlpha then bg:SetAlpha(alpha) end
    bg:SetStatusBarColor(MSUF_UNHALTED_BG_R, MSUF_UNHALTED_BG_G, MSUF_UNHALTED_BG_B, 1)
    bg:Show()
end
_G.MSUF_Alpha_UpdatePreserveMissingHP = _AlphaSyncMissingHPBackground

local function _SetGradArrayAlpha(grads, a)
    if not grads then return end
    if grads.left then grads.left:SetAlpha(a) end
    if grads.right then grads.right:SetAlpha(a) end
    if grads.up then grads.up:SetAlpha(a) end
    if grads.down then grads.down:SetAlpha(a) end
    if #grads > 0 then
        for i = 1, #grads do
            local g = grads[i]
            if g then g:SetAlpha(a) end
        end
    end
end

local function _AlphaClamp01(a)
    if type(a) ~= "number" then return 1 end
    if a < 0 then return 0 end
    if a > 1 then return 1 end
    return a
end

local function _AlphaNearlyEqual(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    local d = a - b
    if d < 0 then d = -d end
    return d <= 0.001
end

local function _GetBarTexture(sb)
    if not sb or not sb.GetStatusBarTexture then return nil end
    return sb:GetStatusBarTexture()
end

local function _AlphaObjectMatches(obj, target)
    if not obj then return true end
    if not obj.GetAlpha then return false end
    return _AlphaNearlyEqual(obj:GetAlpha() or 1, target)
end

local function _AlphaPortraitMatches(frame, target)
    if not frame then return true end
    return _AlphaObjectMatches(frame.portrait, target)
end

local function _AlphaBarColorMatches(sb, target)
    if not sb then return true end
    if not sb.GetStatusBarColor then return true end
    local _, _, _, a = sb:GetStatusBarColor()
    return _AlphaNearlyEqual(a, target)
end

local function _AlphaPreservedBarColorMatches(sb, targetAlpha)
    if not sb then return true end
    return sb._msufAlphaPreserveApplied == true
end

local function _AlphaMissingHPBackgroundMatches(frame, targetAlpha)
    if not frame or frame._msufAlphaPreserveHPColor ~= true then return true end
    local bg = frame._msufAlphaMissingHPBg
    if not bg or (bg.IsShown and not bg:IsShown()) then return false end
    if type(targetAlpha) ~= "number" then
        targetAlpha = tonumber(frame._msufAlphaMissingHPAlpha) or 1
    end
    return _AlphaObjectMatches(bg, targetAlpha)
end

local function _AlphaGradSetMatches(grads, target)
    if not grads then return true end
    if not _AlphaObjectMatches(grads.left, target) then return false end
    if not _AlphaObjectMatches(grads.right, target) then return false end
    if not _AlphaObjectMatches(grads.up, target) then return false end
    if not _AlphaObjectMatches(grads.down, target) then return false end
    if #grads > 0 then
        for i = 1, #grads do
            if not _AlphaObjectMatches(grads[i], target) then return false end
        end
    end
    return true
end

local function _AlphaLayeredStateMatches(frame, fg, bg, mode, preserveHPColor, portraitAlpha)
    if not frame then return false end
    mode = _AlphaNormalizeLayerMode(mode)
    preserveHPColor = (preserveHPColor == true)
    portraitAlpha = tonumber(portraitAlpha) or 1
    local hpTexAlpha = fg
    local hpColorAlpha = 1
    local hpBgAlpha = preserveHPColor and 0 or bg
    local powerAlpha = (mode == "health") and 1 or fg

    local hpTex = _GetBarTexture(frame.hpBar)
    if frame.hpBar and not hpTex then return false end

    local powerBar = frame.targetPowerBar or frame.powerBar
    local powerTex = _GetBarTexture(powerBar)
    if powerBar and not powerTex then return false end

    local absorbTex = _GetBarTexture(frame.absorbBar)
    if frame.absorbBar and not absorbTex then return false end

    local healAbsorbTex = _GetBarTexture(frame.healAbsorbBar)
    if frame.healAbsorbBar and not healAbsorbTex then return false end

    return _AlphaObjectMatches(hpTex, hpTexAlpha)
        and _AlphaBarColorMatches(frame.hpBar, hpColorAlpha)
        and ((not preserveHPColor) or _AlphaPreservedBarColorMatches(frame.hpBar, fg))
        and ((not preserveHPColor) or _AlphaPreserveTextureMatches(frame.hpBar))
        and ((not preserveHPColor) or _AlphaMissingHPBackgroundMatches(frame, fg))
        and _AlphaObjectMatches(powerTex, powerAlpha)
        and _AlphaObjectMatches(absorbTex, fg)
        and _AlphaObjectMatches(healAbsorbTex, fg)
        and _AlphaObjectMatches(frame.hpBarBG, hpBgAlpha)
        and _AlphaObjectMatches(frame.powerBarBG, bg)
        and _AlphaObjectMatches(frame.bg, bg)
        and _AlphaGradSetMatches(frame.hpGradients, fg)
        and _AlphaGradSetMatches(frame.powerGradients, powerAlpha)
        and _AlphaPortraitMatches(frame, portraitAlpha)
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

local function MSUF_Alpha_SetTextAlpha(frame, a)
    if not frame then return end
    a = tonumber(a) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    local o = frame.nameText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.levelText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.hpText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.hpTextPct; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.powerText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.powerTextPct; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.statusIndicatorText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame.statusIndicatorOverlayText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame._msufToTInlineText; if o and o.SetAlpha then o:SetAlpha(a) end
    o = frame._msufToTInlineSep; if o and o.SetAlpha then o:SetAlpha(a) end
end

local function MSUF_Alpha_GetStaticMode(frame, conf)
    if not conf or conf.loadCondActive == true then return nil end
    if conf.rangeFadeEnabled == true then return nil end

    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end

    if conf.alphaExcludeTextPortrait == true and frame._msufAlphaSupportsLayered then
        local mode = _AlphaNormalizeLayerMode(conf.alphaLayerMode)
        local fgIn  = _AlphaClamp01(tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1)
        local fgOut = sync and fgIn or _AlphaClamp01(tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        if mode == "health" then
            fgIn  = _AlphaClamp01(tonumber(conf.alphaHPInCombat) or tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1)
            fgOut = sync and fgIn or _AlphaClamp01(tonumber(conf.alphaHPOutOfCombat) or tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        end
        local bgIn  = _AlphaClamp01(tonumber(conf.alphaBGInCombat) or tonumber(conf.alphaInCombat) or 1)
        local bgOut = sync and bgIn or _AlphaClamp01(tonumber(conf.alphaBGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        if fgIn == fgOut and bgIn == bgOut then
            return "layered", fgIn, bgIn, mode, conf.alphaPreserveHPColor == true
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
    frame._msufAlphaBasePreserveHPColor = nil
    frame._msufAlphaLayeredFastValid = nil
    frame._msufAlphaLayeredFastHits = nil
end

local function MSUF_Alpha_ResetLayered(frame)
    if not frame or not frame._msufAlphaLayeredMode then
         return
    end
    local unitAlpha = frame._msufAlphaUnitAlpha or 1
    frame._msufAlphaLayeredMode = nil
    frame._msufAlphaLayerMode = nil
    frame._msufAlphaPreserveHPColor = nil
    frame._msufAlphaUnitAlpha = nil
    frame._msufAlphaLastFG = nil
    frame._msufAlphaLastBG = nil
    frame._msufAlphaLastPortrait = nil
    frame._msufAlphaLayeredFastValid = nil
    frame._msufAlphaLayeredFastHits = nil
    frame._msufAlphaMissingHPAlpha = nil
    if frame.SetAlpha then
        frame:SetAlpha(unitAlpha)
    end
    _SetBarColorAlpha(frame.hpBar, 1, false)
    _AlphaHideMissingHPBackground(frame)
    _SetBarTexAlpha(frame.hpBar, 1)
    _SetBarTexAlpha(frame.targetPowerBar or frame.powerBar, 1)
    _SetBarTexAlpha(frame.absorbBar, 1)
    _SetBarTexAlpha(frame.healAbsorbBar, 1)
    _SetTexAlpha(frame.hpBarBG, 1)
    _SetTexAlpha(frame.powerBarBG, 1)
    _SetTexAlpha(frame.bg, 1)
    _SetGradArrayAlpha(frame.hpGradients, 1)
    _SetGradArrayAlpha(frame.powerGradients, 1)
    _AlphaSetPortraitAlpha(frame, 1)
    MSUF_Alpha_SetTextAlpha(frame, 1)
end

local function MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, mode, preserveHPColor, portraitAlpha)
    if not frame then return end
    mode = _AlphaNormalizeLayerMode(mode)
    preserveHPColor = (preserveHPColor == true)
    portraitAlpha = tonumber(portraitAlpha) or 1

    local fg = type(alphaFG) == "number" and alphaFG or 1
    local bg = type(alphaBG) == "number" and alphaBG or 1
    if fg < 0 then fg = 0 elseif fg > 1 then fg = 1 end
    if bg < 0 then bg = 0 elseif bg > 1 then bg = 1 end
    if portraitAlpha < 0 then portraitAlpha = 0 elseif portraitAlpha > 1 then portraitAlpha = 1 end

    if frame._msufAlphaLayeredMode and frame._msufAlphaLayerMode == mode and frame._msufAlphaPreserveHPColor == preserveHPColor then
        local lastFG = frame._msufAlphaLastFG or 1
        local lastBG = frame._msufAlphaLastBG or 1
        local lastPortrait = frame._msufAlphaLastPortrait or 1
        local dfg = lastFG - fg; if dfg < 0 then dfg = -dfg end
        local dbg = lastBG - bg; if dbg < 0 then dbg = -dbg end
        local dp = lastPortrait - portraitAlpha; if dp < 0 then dp = -dp end
        if dfg <= 0.001 and dbg <= 0.001 and dp <= 0.001 then
            if frame._msufAlphaLayeredFastValid then
                local hits = (frame._msufAlphaLayeredFastHits or 0) + 1
                if hits < 16 then
                    frame._msufAlphaLayeredFastHits = hits
                    return
                end
                frame._msufAlphaLayeredFastHits = 0
            end
            if frame._msufAlphaLayeredFastValid then
                frame._msufAlphaLayeredFastValid = nil
            end
            if _AlphaLayeredStateMatches(frame, fg, bg, mode, preserveHPColor, portraitAlpha) then
                frame._msufAlphaLayeredFastValid = true
                return
            end
        end
    end

    frame._msufAlphaLayeredMode = true
    frame._msufAlphaLayerMode = mode
    frame._msufAlphaPreserveHPColor = preserveHPColor
    frame._msufAlphaLastFG = fg
    frame._msufAlphaLastBG = bg
    frame._msufAlphaLastPortrait = portraitAlpha
    frame._msufAlphaLayeredFastValid = nil
    frame._msufAlphaLayeredFastHits = nil

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

    _SetTexAlpha(frame.hpBarBG, preserveHPColor and 0 or bg)
    _SetTexAlpha(frame.powerBarBG, bg)
    _SetTexAlpha(frame.bg, bg)
    if preserveHPColor then
        -- Match Unhalted: transparent HP fill over the world, with only missing
        -- health rendered as a dark reverse-fill background.
        frame._msufAlphaMissingHPAlpha = fg
        _SetBarColorAlpha(frame.hpBar, fg, true)
        _SetBarTexAlpha(frame.hpBar, fg)
        _AlphaSyncMissingHPBackground(frame, nil, nil, fg)
    else
        frame._msufAlphaMissingHPAlpha = nil
        _SetBarColorAlpha(frame.hpBar, 1, false)
        _AlphaHideMissingHPBackground(frame)
        _SetBarTexAlpha(frame.hpBar, fg)
    end
    local powerAlpha = (mode == "health") and 1 or fg
    _SetBarTexAlpha(frame.targetPowerBar or frame.powerBar, powerAlpha)
    _SetBarTexAlpha(frame.absorbBar, fg)
    _SetBarTexAlpha(frame.healAbsorbBar, fg)
    _SetGradArrayAlpha(frame.hpGradients, fg)
    _SetGradArrayAlpha(frame.powerGradients, powerAlpha)
    _AlphaSetPortraitAlpha(frame, portraitAlpha)
    MSUF_Alpha_SetTextAlpha(frame, 1)
    frame._msufAlphaLayeredFastValid = true
end

local _rfMulTable = _G.MSUF_RangeFadeMul

function _G.MSUF_ApplyUnitAlpha(frame, key)
    local db = MSUF_DB
    if not db then EnsureDB(); db = MSUF_DB end
    if not frame or not frame.SetAlpha then return end
    -- GF frames handle alpha exclusively via SetAlphaFromBoolean (range fade).
    -- Calling SetAlpha here would override the secret-based range alpha.
    if frame._msufIsGroupFrame then return end
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
        local staticMode, staticA, staticB, staticLayerMode, staticPreserveHPColor = MSUF_Alpha_GetStaticMode(frame, conf)
        if staticMode == "flat" then
            frame._msufAlphaBaseMode = "flat"
            frame._msufAlphaBaseKey = key
            frame._msufAlphaBaseA = staticA
            frame._msufAlphaBaseFG = nil
            frame._msufAlphaBaseBG = nil
            frame._msufAlphaBaseLayerMode = nil
            frame._msufAlphaBasePreserveHPColor = nil
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
            frame._msufAlphaBasePreserveHPColor = staticPreserveHPColor == true
            MSUF_Alpha_ApplyLayered(frame, staticA, staticB, staticLayerMode, staticPreserveHPColor)
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
        local layerMode = _AlphaNormalizeLayerMode(conf.alphaLayerMode)
        local preserveHPColor = conf.alphaPreserveHPColor == true

        local fgIn  = tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1
        local fgOut = sync and fgIn or (tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        if layerMode == "health" then
            fgIn  = tonumber(conf.alphaHPInCombat) or tonumber(conf.alphaFGInCombat) or tonumber(conf.alphaInCombat) or 1
            fgOut = sync and fgIn or (tonumber(conf.alphaHPOutOfCombat) or tonumber(conf.alphaFGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        end
        local bgIn  = tonumber(conf.alphaBGInCombat) or tonumber(conf.alphaInCombat) or 1
        local bgOut = sync and bgIn or (tonumber(conf.alphaBGOutOfCombat) or tonumber(conf.alphaOutOfCombat) or 1)
        local alphaFG = inCombat and fgIn or fgOut
        local alphaBG = inCombat and bgIn or bgOut

        frame._msufAlphaBaseMode = "layered"
        frame._msufAlphaBaseKey = key
        frame._msufAlphaBaseA = nil
        frame._msufAlphaBaseFG = alphaFG
        frame._msufAlphaBaseBG = alphaBG
        frame._msufAlphaBaseLayerMode = layerMode
        frame._msufAlphaBasePreserveHPColor = preserveHPColor

        local rangeMul = 1
        local rfT = _rfMulTable
        if rfT then
            local m = rfT[key] or rfT[unit]
            if m and m < 1 then
                if m < 0 then m = 0 end
                if m > 1 then m = 1 end
                rangeMul = m
                alphaFG = alphaFG * m
                alphaBG = alphaBG * m
            end
        end

        MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, layerMode, preserveHPColor,
            _AlphaShouldRangeFadePortrait() and rangeMul or 1)
        MSUF_Alpha_SetTextAlpha(frame, rangeMul)
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
    frame._msufAlphaBasePreserveHPColor = nil

    local rfT = _rfMulTable
    if rfT then
        local m = rfT[key] or rfT[unit]
        if m and m < 1 then
            if m < 0 then m = 0 end
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

    if frame._msufAlphaBaseMode == "layered" and frame._msufAlphaSupportsLayered then
        local fg = frame._msufAlphaBaseFG
        local bg = frame._msufAlphaBaseBG
        local mode = frame._msufAlphaBaseLayerMode
        local preserveHPColor = frame._msufAlphaBasePreserveHPColor == true
        if type(fg) ~= "number" or type(bg) ~= "number" or mode == nil then
            return false
        end
        MSUF_Alpha_ApplyLayered(frame, fg * m, bg * m, mode, preserveHPColor,
            _AlphaShouldRangeFadePortrait() and m or 1)
        MSUF_Alpha_SetTextAlpha(frame, m)
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
        local mode = _AlphaNormalizeLayerMode(conf.alphaLayerMode)
        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        elseif mode == "health" then
            aIn  = tonumber(conf.alphaHPInCombat) or tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaHPOutOfCombat) or tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
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
        if _G.MSUF_ScheduleOnce then
            _G.MSUF_ScheduleOnce("ALPHA_FLUSH", _Flush)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, _Flush)
        else
            _Flush()
        end
    end
end

if not _G.MSUF_AlphaEventFrame then
    local function _MSUF_AlphaPostWorldRefresh()
        local fn = _G.MSUF_RequestAlphaRefresh
        if type(fn) == "function" then
            fn(false)
        end
    end

    local function _MSUF_AlphaPostWorldRefreshLate()
        local fn = _G.MSUF_RequestAlphaRefresh
        if type(fn) == "function" then
            fn(false)
        end
    end

    _G.MSUF_AlphaEventFrame = CreateFrame("Frame")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _G.MSUF_AlphaEventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.MSUF_InCombat = true
            _G.MSUF_RequestAlphaRefresh(true)
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            _G.MSUF_InCombat = false
            _G.MSUF_RequestAlphaRefresh(true)
            return
        end

        local inCombat = _G.MSUF_InCombat
        if inCombat == nil then
            inCombat = (F.InCombatLockdown and F.InCombatLockdown()) or false
            _G.MSUF_InCombat = inCombat and true or false
        end

        _G.MSUF_RequestAlphaRefresh(false)
        if _G.MSUF_ScheduleOnce then
            _G.MSUF_ScheduleOnce("ALPHA_WORLD_REFRESH", _MSUF_AlphaPostWorldRefresh)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, _MSUF_AlphaPostWorldRefresh)
        end
        if _G.MSUF_ScheduleDelayOnce then
            _G.MSUF_ScheduleDelayOnce("ALPHA_WORLD_REFRESH_LATE", 0.10, _MSUF_AlphaPostWorldRefreshLate)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.10, _MSUF_AlphaPostWorldRefreshLate)
        end
     end)
end
