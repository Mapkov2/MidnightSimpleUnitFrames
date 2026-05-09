-- Core/MSUF_BarBackgroundRuntime.lua
-- Runtime bar background tint/texture handling.
-- Extracted from MidnightSimpleUnitFrames.lua; keep exported globals stable.

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns
ns.Bars = ns.Bars or {}

local type, tonumber = type, tonumber

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
end

local function MSUF_Clamp01(v)
    v = tonumber(v)
    if not v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

ns.Bars._DarkTint = function(g, r, gg, b)
    if g and g.darkMode and not g.darkBgCustomColor then
        local br = MSUF_Clamp01(g.darkBgBrightness)
        return r * br, gg * br, b * br
    end
    return r, gg, b
end

local function MSUF_GetBarBackgroundTintRGBA()
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local r, gg, b = ns.Bars._DarkTint(g, MSUF_Clamp01(g.classBarBgR), MSUF_Clamp01(g.classBarBgG), MSUF_Clamp01(g.classBarBgB))
    return r, gg, b, 0.9
end
_G.MSUF_GetBarBackgroundTintRGBA = MSUF_GetBarBackgroundTintRGBA

local function MSUF_GetPowerBarBackgroundTintRGBA()
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local ar, ag, ab = g.powerBarBgColorR, g.powerBarBgColorG, g.powerBarBgColorB
    if type(ar) ~= "number" or type(ag) ~= "number" or type(ab) ~= "number" then
        return MSUF_GetBarBackgroundTintRGBA()
    end
    local r, gg, b = ns.Bars._DarkTint(g, MSUF_Clamp01(ar), MSUF_Clamp01(ag), MSUF_Clamp01(ab))
    return r, gg, b, 0.9
end
_G.MSUF_GetPowerBarBackgroundTintRGBA = MSUF_GetPowerBarBackgroundTintRGBA

-- Detached power bar texture resolvers (cache + DB read).
local _DPB = ns.Bars._DetachedPowerBarTextures or {}
_DPB.fgK = _DPB.fgK or false
_DPB.bgK = _DPB.bgK or false
_DPB.CDM = _DPB.CDM or {
    cooldown      = "EssentialCooldownViewer",
    utility       = "UtilityCooldownViewer",
    tracked_buffs = "BuffIconCooldownViewer",
}

function _DPB.UseMSAEssentialBridge()
    local g = _G.MSUF_DB and _G.MSUF_DB.general or nil
    return not (g and g.disableMSAEssentialBridge == true)
end

function _G.MSUF_GetEffectiveCooldownFrame(frameName)
    if frameName == "EssentialCooldownViewer" and _DPB.UseMSAEssentialBridge() then
        local getter = _G.MSWA_GetEssentialBridgeFrame
        if type(getter) == "function" then
            local bridge = getter()
            if bridge and bridge ~= _G.UIParent and bridge ~= _G.WorldFrame and (not bridge.IsForbidden or not bridge:IsForbidden()) then
                return bridge
            end
        end
    end
    return frameName and _G[frameName] or nil
end

function _DPB.ResolveFg()
    local b = _G.MSUF_DB and _G.MSUF_DB.bars or {}
    local key = b.detachedPowerBarTexture
    if not key or key == "" then return nil end
    if key == _DPB.fgK and _DPB.fgC then return _DPB.fgC end
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local path = (type(resolve) == "function" and resolve(key)) or nil
    _DPB.fgK = key
    _DPB.fgC = path
    return path
end

function _DPB.ResolveBg()
    local b = _G.MSUF_DB and _G.MSUF_DB.bars or {}
    local key = b.detachedPowerBarBgTexture
    if not key or key == "" then return nil end
    if key == _DPB.bgK and _DPB.bgC then return _DPB.bgC end
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local path = (type(resolve) == "function" and resolve(key)) or nil
    _DPB.bgK = key
    _DPB.bgC = path
    return path
end

ns.Bars._DetachedPowerBarTextures = _DPB

local _MSUF_BgKeyCache = {}
local function _MSUF_GetBgKeys(prefix)
    local k = _MSUF_BgKeyCache[prefix]
    if k then return k end
    k = {
        tex = "_msuf" .. prefix .. "BgTex",
        r   = "_msuf" .. prefix .. "BgR",
        g   = "_msuf" .. prefix .. "BgG",
        b   = "_msuf" .. prefix .. "BgB",
        a   = "_msuf" .. prefix .. "BgA",
    }
    _MSUF_BgKeyCache[prefix] = k
    return k
end

-- Pre-warm the known prefixes so the runtime path does not allocate keys.
_MSUF_GetBgKeys("HP")
_MSUF_GetBgKeys("Power")
_MSUF_GetBgKeys("Frame")

local function _MSUF_ApplyBgToTexture(frame, tex, t, prefix, cr, cg, cb, ca)
    if not t or not tex then return end
    local k = _MSUF_GetBgKeys(prefix)
    if frame[k.tex] ~= tex then
        t:SetTexture(tex)
        frame[k.tex] = tex
    end
    if frame[k.r] ~= cr or frame[k.g] ~= cg or frame[k.b] ~= cb or frame[k.a] ~= ca then
        t:SetVertexColor(cr, cg, cb, ca)
        frame[k.r], frame[k.g], frame[k.b], frame[k.a] = cr, cg, cb, ca
    end
end

ns.Bars._MatchHPColor = function(frame, gen, cache, defR, defG, defB)
    local fr, fg, fb = frame.hpBar:GetStatusBarColor()
    if type(fr) ~= "number" or type(fg) ~= "number" or type(fb) ~= "number" then return defR, defG, defB end
    if gen and gen.darkMode and not gen.darkBgCustomColor then
        local br = (cache and cache.darkBgBrightness) or gen.darkBgBrightness
        if type(br) == "number" then
            if br < 0 then br = 0 elseif br > 1 then br = 1 end
            fr, fg, fb = fr * br, fg * br, fb * br
        end
    end
    return MSUF_Clamp01(fr), MSUF_Clamp01(fg), MSUF_Clamp01(fb)
end

local _CachedGetCache
local function _MSUF_ResolveGetCache()
    if _CachedGetCache then return _CachedGetCache end
    local fn = _G.MSUF_UFCore_GetSettingsCache
    if type(fn) == "function" then
        _CachedGetCache = fn
        return fn
    end
    return nil
end

local function MSUF_ApplyBarBackgroundVisual(frame)
    if not frame then return end
    local getBgTexture = _G.MSUF_GetBarBackgroundTexture
    local tex = type(getBgTexture) == "function" and getBgTexture() or nil
    if not tex then return end

    local getCache = _MSUF_ResolveGetCache()
    local cache = getCache and getCache() or nil

    local gen = (cache and cache.generalRef) or (_G.MSUF_DB and _G.MSUF_DB.general)
    local bars = (cache and cache.barsRef) or (_G.MSUF_DB and _G.MSUF_DB.bars)

    local r, gg, b, a
    if cache then
        r, gg, b, a = cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA
    else
        r, gg, b, a = MSUF_GetBarBackgroundTintRGBA()
    end

    if (cache and cache.barBgMatchHPColor or (gen and gen.barBgMatchHPColor)) and frame.hpBar and frame.hpBar.GetStatusBarColor then
        r, gg, b = ns.Bars._MatchHPColor(frame, gen, cache, r, gg, b)
    end

    local alphaMul = (cache and cache.barBackgroundAlpha)
    if type(alphaMul) ~= "number" then
        local alphaPct = 90
        if bars and type(bars.barBackgroundAlpha) == "number" then
            alphaPct = bars.barBackgroundAlpha
        end
        if alphaPct < 0 then alphaPct = 0 elseif alphaPct > 100 then alphaPct = 100 end
        alphaMul = alphaPct / 100
    end
    if type(a) == "number" then a = a * alphaMul end

    _MSUF_ApplyBgToTexture(frame, tex, frame.hpBarBG, "HP", r, gg, b, a)

    local pr, pg, pb, pa
    if cache then
        pr, pg, pb, pa = cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA
    else
        pr, pg, pb, pa = MSUF_GetPowerBarBackgroundTintRGBA()
    end
    if type(pa) == "number" then pa = pa * alphaMul end

    if (cache and cache.powerBarBgMatchHPColor or ((gen and gen.powerBarBgMatchHPColor) or (bars and bars.powerBarBgMatchBarColor))) and frame.hpBar and frame.hpBar.GetStatusBarColor then
        pr, pg, pb = ns.Bars._MatchHPColor(frame, gen, cache, pr, pg, pb)
    end

    _MSUF_ApplyBgToTexture(frame, tex, frame.powerBarBG, "Power", pr, pg, pb, pa)

    if frame._msufPowerBarDetached and frame.powerBarBG then
        local dpbBgTex = _DPB.ResolveBg()
        if not dpbBgTex then
            dpbBgTex = _DPB.ResolveFg()
        end
        if dpbBgTex then
            if frame._msufDPBBgTexOverride ~= dpbBgTex then
                frame.powerBarBG:SetTexture(dpbBgTex)
                frame._msufDPBBgTexOverride = dpbBgTex
            end
        else
            frame._msufDPBBgTexOverride = nil
        end
    elseif frame._msufDPBBgTexOverride then
        frame._msufDPBBgTexOverride = nil
    end

    if (not frame.hpBarBG) and (not frame.powerBarBG) and frame.bg then
        _MSUF_ApplyBgToTexture(frame, tex, frame.bg, "Frame", r, gg, b, a)
    end
end

_G.MSUF_ApplyBarBackgroundVisual = MSUF_ApplyBarBackgroundVisual
ns.Bars.ApplyBarBackgroundVisual = MSUF_ApplyBarBackgroundVisual
