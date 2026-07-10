--- Runtime/MSUF_BarBackgroundRuntime.lua
--- Runtime bar background tint/texture handling.
--- Shared bar-background runtime helpers with stable exported globals.
---
--- This file applies background color/texture policy to existing health, power,
--- and detached bars. Texture/key resolution is shared with TextureRuntime and
--- callers should use the exported helpers instead of repainting backgrounds
--- directly.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Bars = MSUF.Bars or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local type, tonumber = type, tonumber
local UnitClass, UnitExists, UnitIsPlayer = _G.UnitClass, _G.UnitExists, _G.UnitIsPlayer
local issecretvalue = _G.issecretvalue

do
    --- Legacy compatibility anchor for profiles that referenced an older
    --- cooldown-viewer frame as an external anchor target.
    local LEGACY_CDM_ANCHOR = "EssentialCooldownViewer_MSA_Container"

    local function _CompatCharKey()
        local fn = _G.MSUF_GetCharKey
        if type(fn) == "function" then
            local key = fn()
            if type(key) == "string" and key ~= "" then return key end
        end
        local name = _G.UnitName and _G.UnitName("player")
        local realm = _G.GetRealmName and _G.GetRealmName()
        if type(name) == "string" and name ~= "" and type(realm) == "string" and realm ~= "" then
            return name .. "-" .. realm
        end
        return "global"
    end

    local function _CompatProfileKey()
        local active = _G.MSUF_ActiveProfile
        if type(active) == "string" and active ~= "" then return active end
        local gdb = _G.MSUF_GlobalDB
        local charKey = _CompatCharKey()
        local char = gdb and type(gdb.char) == "table" and gdb.char[charKey]
        active = char and char.activeProfile
        if type(active) == "string" and active ~= "" then return active end
        return "Default"
    end

    local function _CompatCache(rootKey)
        local gdb = _G.MSUF_GlobalDB
        local root = gdb and gdb[rootKey]
        if type(root) ~= "table" then return nil end
        local byChar = root[_CompatCharKey()] or root.global
        if type(byChar) ~= "table" then return nil end
        return byChar[_CompatProfileKey()]
    end

    local function _ApplyCompatAnchorCache(anchor)
        if not (anchor and _G.UIParent) then return false end
        local bucket = _CompatCache("externalAnchorCache")
        local cached = type(bucket) == "table"
            and (bucket[LEGACY_CDM_ANCHOR] or bucket.EssentialCooldownViewer)
            or nil
        if type(cached) ~= "table" then return false end
        local x, y = tonumber(cached.x), tonumber(cached.y)
        if not (x and y) then return false end
        local w = tonumber(cached.w) or 1
        local h = tonumber(cached.h) or 1
        if w < 1 then w = 1 end
        if h < 1 then h = 1 end
        anchor:ClearAllPoints()
        anchor:SetSize(w, h)
        anchor:SetPoint("CENTER", _G.UIParent, "CENTER", math.floor(x + 0.5), math.floor(y + 0.5))
        return true
    end

    local function EnsureLegacyCooldownViewerAnchor()
        local anchor = _G[LEGACY_CDM_ANCHOR]
        if not anchor then
            anchor = _G.CreateFrame("Frame", LEGACY_CDM_ANCHOR, _G.UIParent)
            _G[LEGACY_CDM_ANCHOR] = anchor
        end
        anchor._msufLegacyCooldownAnchor = true
        if anchor.EnableMouse then anchor:EnableMouse(false) end
        if anchor.SetAlpha then anchor:SetAlpha(0) end
        if not _ApplyCompatAnchorCache(anchor) then
            anchor:ClearAllPoints()
            anchor:SetSize(1, 1)
            anchor:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
        end
        if anchor.Show then anchor:Show() end
        return anchor
    end
    ExportPublic("MSUF_EnsureLegacyCooldownViewerAnchor", EnsureLegacyCooldownViewerAnchor)

    local function PositionLegacyCooldownViewerAnchor()
        local anchor = EnsureLegacyCooldownViewerAnchor()
        return _ApplyCompatAnchorCache(anchor)
    end
    ExportPublic("MSUF_PositionLegacyCooldownViewerAnchor", PositionLegacyCooldownViewerAnchor)

    EnsureLegacyCooldownViewerAnchor()
end

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
        (_G.MSUF_EnsureDB)()
    end
end

local function MSUF_Clamp01(v)
    v = tonumber(v)
    if not v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function MSUF_IsSecretValue(value)
    local fn = issecretvalue
    if type(fn) ~= "function" then
        fn = _G.issecretvalue
        if type(fn) == "function" then issecretvalue = fn end
    end
    return type(fn) == "function" and fn(value) == true
end

MSUF.Bars._DarkTint = function(g, r, gg, b)
    if g and g.darkMode and not g.darkBgCustomColor then
        local br = MSUF_Clamp01(g.darkBgBrightness)
        return r * br, gg * br, b * br
    end
    return r, gg, b
end

local function MSUF_GetBarBackgroundTintRGBA()
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local r, gg, b = MSUF.Bars._DarkTint(g, MSUF_Clamp01(g.classBarBgR), MSUF_Clamp01(g.classBarBgG), MSUF_Clamp01(g.classBarBgB))
    return r, gg, b, 0.9
end
ExportPublic("MSUF_GetBarBackgroundTintRGBA", MSUF_GetBarBackgroundTintRGBA)

local function MSUF_GetPowerBarBackgroundTintRGBA()
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local ar, ag, ab = g.powerBarBgColorR, g.powerBarBgColorG, g.powerBarBgColorB
    if type(ar) ~= "number" or type(ag) ~= "number" or type(ab) ~= "number" then
        return MSUF_GetBarBackgroundTintRGBA()
    end
    local r, gg, b = MSUF.Bars._DarkTint(g, MSUF_Clamp01(ar), MSUF_Clamp01(ag), MSUF_Clamp01(ab))
    return r, gg, b, 0.9
end
ExportPublic("MSUF_GetPowerBarBackgroundTintRGBA", MSUF_GetPowerBarBackgroundTintRGBA)

--- Detached power bar texture resolvers (cache + DB read).
local _DPB = MSUF.Bars._DetachedPowerBarTextures or {}
_DPB.fgK = _DPB.fgK or false
_DPB.bgK = _DPB.bgK or false
_DPB.CDM = _DPB.CDM or {
}

local BLIZZARD_COOLDOWN_VIEWER_FRAMES = {
    EssentialCooldownViewer = true,
    UtilityCooldownViewer = true,
    BuffIconCooldownViewer = true,
}

local function MSUF_IsBlizzardCooldownViewerFrameName(frameName)
    return BLIZZARD_COOLDOWN_VIEWER_FRAMES[frameName] == true
end
ExportPublic("MSUF_IsBlizzardCooldownViewerFrameName", MSUF_IsBlizzardCooldownViewerFrameName)

local function MSUF_GetEffectiveCooldownFrame(frameName)
    if frameName == "EssentialCooldownViewer" then
        local getSkironProxy = _G.MSUF_GetSkironCooldownAnchorProxy
        local skironProxy = type(getSkironProxy) == "function" and getSkironProxy() or nil
        if skironProxy then
            return skironProxy
        end
    end
    if MSUF_IsBlizzardCooldownViewerFrameName(frameName) then
        return nil
    end
    return frameName and _G[frameName] or nil
end
ExportPublic("MSUF_GetEffectiveCooldownFrame", MSUF_GetEffectiveCooldownFrame)

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

MSUF.Bars._DetachedPowerBarTextures = _DPB

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

--- Pre-warm the known prefixes so the runtime path does not allocate keys.
_MSUF_GetBgKeys("HP")
_MSUF_GetBgKeys("Power")
_MSUF_GetBgKeys("Frame")

local function _MSUF_ApplyBgColor(frame, t, prefix, cr, cg, cb, ca)
    if not t then return end
    local k = _MSUF_GetBgKeys(prefix)
    if frame[k.r] ~= cr or frame[k.g] ~= cg or frame[k.b] ~= cb or frame[k.a] ~= ca then
        t:SetVertexColor(cr, cg, cb, ca)
        frame[k.r], frame[k.g], frame[k.b], frame[k.a] = cr, cg, cb, ca
    end
end

local function _MSUF_ApplyBgToTexture(frame, tex, t, prefix, cr, cg, cb, ca)
    if not t or not tex then return end
    local k = _MSUF_GetBgKeys(prefix)
    if frame[k.tex] ~= tex then
        t:SetTexture(tex)
        frame[k.tex] = tex
    end
    _MSUF_ApplyBgColor(frame, t, prefix, cr, cg, cb, ca)
end

MSUF.Bars._MatchHPColor = function(frame, gen, cache, defR, defG, defB)
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

MSUF.Bars._ClassBackgroundColor = function(frame, defR, defG, defB)
    if not frame then return defR, defG, defB end
    local unit = frame.unit
    if not unit or (UnitExists and not UnitExists(unit)) then
        frame._msufBarBgClassGuid = nil
        frame._msufBarBgClassToken = nil
        return defR, defG, defB
    end

    local classToken

    --- Midnight/Beta: UnitGUID can be a secret string. Do not cache or compare it
    --- in Lua; resolve the class directly instead.
    frame._msufBarBgClassGuid = nil
    if UnitIsPlayer then
        local isPlayer = UnitIsPlayer(unit)
        if MSUF_IsSecretValue(isPlayer) or not isPlayer then
            frame._msufBarBgClassToken = nil
            return defR, defG, defB
        end
    end
    if UnitClass then
        local _
        _, classToken = UnitClass(unit)
    end
    if MSUF_IsSecretValue(classToken) then
        classToken = nil
    end
    frame._msufBarBgClassToken = classToken
    if not classToken then return defR, defG, defB end

    local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
    if type(fastClass) == "function" then
        local r, g, b = fastClass(classToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return MSUF_Clamp01(r), MSUF_Clamp01(g), MSUF_Clamp01(b)
        end
    end

    local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if color then
        return MSUF_Clamp01(color.r), MSUF_Clamp01(color.g), MSUF_Clamp01(color.b)
    end
    return defR, defG, defB
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

local function _MSUF_BarBackgroundAlphaMul(cache, bars)
    local alphaMul = cache and cache.barBackgroundAlpha
    if type(alphaMul) ~= "number" then
        local alphaPct = 90
        if bars and type(bars.barBackgroundAlpha) == "number" then
            alphaPct = bars.barBackgroundAlpha
        end
        if alphaPct < 0 then alphaPct = 0 elseif alphaPct > 100 then alphaPct = 100 end
        alphaMul = alphaPct / 100
    end
    return alphaMul
end

local function _MSUF_ResolveHealthBackgroundRGBA(frame, cache, gen, bars)
    local r, gg, b, a
    if cache then
        r, gg, b, a = cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA
    else
        r, gg, b, a = MSUF_GetBarBackgroundTintRGBA()
    end

    if (cache and cache.barBgClassColor) or (gen and gen.barBgClassColor) then
        r, gg, b = MSUF.Bars._ClassBackgroundColor(frame, r, gg, b)
    elseif frame and (cache and cache.barBgMatchHPColor or (gen and gen.barBgMatchHPColor)) and frame.hpBar and frame.hpBar.GetStatusBarColor then
        r, gg, b = MSUF.Bars._MatchHPColor(frame, gen, cache, r, gg, b)
    end

    if type(a) == "number" then
        a = a * _MSUF_BarBackgroundAlphaMul(cache, bars)
    end
    return r, gg, b, a
end

local function MSUF_GetEffectiveHealthBarBackgroundTintRGBA(frame)
    EnsureDBSafe()
    local getCache = _MSUF_ResolveGetCache()
    local cache = getCache and getCache() or nil
    local gen = (cache and cache.generalRef) or (_G.MSUF_DB and _G.MSUF_DB.general)
    local bars = (cache and cache.barsRef) or (_G.MSUF_DB and _G.MSUF_DB.bars)
    return _MSUF_ResolveHealthBackgroundRGBA(frame, cache, gen, bars)
end
ExportPublic("MSUF_GetEffectiveHealthBarBackgroundTintRGBA", MSUF_GetEffectiveHealthBarBackgroundTintRGBA)

local function MSUF_ApplyBarBackgroundVisual(frame)
    if not frame then return end
    local spec = frame.MSUFSpec
    local hpTex = (spec and spec.health and spec.health.backgroundTexture) or (spec and spec.backgroundTexture)
    local powerTex = (spec and spec.power and spec.power.backgroundTexture) or (spec and spec.backgroundTexture) or hpTex
    if not hpTex or not powerTex then
        local getBgTexture = _G.MSUF_GetBarBackgroundTexture
        local tex = type(getBgTexture) == "function" and getBgTexture() or nil
        hpTex = hpTex or tex
        powerTex = powerTex or tex
    end
    if not hpTex then return end
    powerTex = powerTex or hpTex

    local getCache = _MSUF_ResolveGetCache()
    local cache = getCache and getCache() or nil

    local gen = (cache and cache.generalRef) or (_G.MSUF_DB and _G.MSUF_DB.general)
    local bars = (cache and cache.barsRef) or (_G.MSUF_DB and _G.MSUF_DB.bars)

    local r, gg, b, a = _MSUF_ResolveHealthBackgroundRGBA(frame, cache, gen, bars)
    local alphaMul = _MSUF_BarBackgroundAlphaMul(cache, bars)

    _MSUF_ApplyBgToTexture(frame, hpTex, frame.hpBarBG, "HP", r, gg, b, a)

    local pr, pg, pb, pa
    if cache then
        pr, pg, pb, pa = cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA
    else
        pr, pg, pb, pa = MSUF_GetPowerBarBackgroundTintRGBA()
    end
    if type(pa) == "number" then pa = pa * alphaMul end

    if (cache and cache.powerBarBgMatchHPColor or ((gen and gen.powerBarBgMatchHPColor) or (bars and bars.powerBarBgMatchBarColor))) and frame.hpBar and frame.hpBar.GetStatusBarColor then
        pr, pg, pb = MSUF.Bars._MatchHPColor(frame, gen, cache, pr, pg, pb)
    end

    local shapedPower = frame.targetPowerBar and frame.targetPowerBar._msufPowerShapeActive == true
    if shapedPower then
        -- Shape backgrounds are fixed media owned by the Power element. Refresh
        -- only their tint; replacing the texture turns the shape back into a bar.
        _MSUF_ApplyBgColor(frame, frame.powerBarBG, "Power", pr, pg, pb, pa)
    else
        _MSUF_ApplyBgToTexture(frame, powerTex, frame.powerBarBG, "Power", pr, pg, pb, pa)
    end

    if shapedPower then
        frame._msufDPBBgTexOverride = nil
    elseif frame._msufPowerBarDetached and frame.powerBarBG then
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
        _MSUF_ApplyBgToTexture(frame, hpTex, frame.bg, "Frame", r, gg, b, a)
    end
end

ExportPublic("MSUF_ApplyBarBackgroundVisual", MSUF_ApplyBarBackgroundVisual)
MSUF.Bars.ApplyBarBackgroundVisual = MSUF_ApplyBarBackgroundVisual
