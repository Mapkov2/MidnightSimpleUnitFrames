-- Core/MSUF_TextureRuntime.lua
-- Runtime bar texture refresh and deferred texture apply wrappers.
-- Extracted from MidnightSimpleUnitFrames.lua; keep exported globals stable.

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns
ns.Textures = ns.Textures or {}

local type, tonumber = type, tonumber
local pairs = pairs

local function Export(key, fn, aliasKey, forceAlias)
    if ns then ns[key] = fn end
    _G[key] = fn
    if aliasKey then
        if forceAlias then
            _G[aliasKey] = fn
        else
            _G[aliasKey] = _G[aliasKey] or fn
        end
    end
    return fn
end

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
end

local function ForEachUnitFrame(fn)
    local forEach = _G.MSUF_ForEachUnitFrame
    if type(forEach) == "function" then
        return forEach(fn)
    end
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame then fn(frame) end
    end
end

local function ScheduleApplyCommit()
    local schedule = _G.MSUF_ScheduleApplyCommit
    if type(schedule) == "function" then
        schedule()
        return
    end
    local commit = _G.MSUF_CommitApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", commit)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, commit)
    else
        commit()
    end
end

local _iterState = {}

local function _ApplyTexCached(sb, tex)
    if not sb or not tex then return end
    if sb.MSUF_cachedStatusbarTexture ~= tex then
        sb:SetStatusBarTexture(tex)
        sb.MSUF_cachedStatusbarTexture = tex
        local applyAlpha = (ns.Bars and ns.Bars._ApplyOverlayTextureAlpha) or _G.MSUF_ApplyOverlayTextureAlpha
        if type(applyAlpha) == "function" then
            applyAlpha(sb)
        end
    end
end

local function _Iter_ApplyAllBarTex(f)
    local S = _iterState
    _ApplyTexCached(f.hpBar, S.texHP)
    _ApplyTexCached(f.absorbBar, S.texAbs)
    _ApplyTexCached(f.healAbsorbBar, S.texHeal)
    _ApplyTexCached(f.incomingHealBar or f.selfHealPredBar, S.texHP)
    if S.applyBg then S.applyBg(f) end

    local pbTex = S.texHP
    if f._msufPowerBarDetached and S.texDPB then
        pbTex = S.texDPB
    end
    _ApplyTexCached(f.targetPowerBar, pbTex)
end

local function _Iter_ApplyAbsorbTex(f)
    local S = _iterState
    _ApplyTexCached(f.absorbBar, S.texAbs)
    _ApplyTexCached(f.healAbsorbBar, S.texHeal)
end

local function UpdateAllBarTextures()
    local getBarTexture = _G.MSUF_GetBarTexture
    if type(getBarTexture) ~= "function" then return end
    local texHP = getBarTexture()
    if not texHP then return end

    local getAbsorbTexture = _G.MSUF_GetAbsorbBarTexture
    local getHealAbsorbTexture = _G.MSUF_GetHealAbsorbBarTexture
    local texAbs = type(getAbsorbTexture) == "function" and getAbsorbTexture() or nil
    local texHeal = type(getHealAbsorbTexture) == "function" and getHealAbsorbTexture() or nil
    local dpb = ns.Bars and ns.Bars._DetachedPowerBarTextures

    _iterState.texHP = texHP
    _iterState.texAbs = texAbs or texHP
    _iterState.texHeal = texHeal or texHP
    _iterState.texDPB = (dpb and dpb.ResolveFg and dpb.ResolveFg()) or texHP
    _iterState.applyBg = _G.MSUF_ApplyBarBackgroundVisual

    ForEachUnitFrame(_Iter_ApplyAllBarTex)

    if _G.MSUF_UpdateCastbarTextures_Immediate then
        _G.MSUF_UpdateCastbarTextures_Immediate()
    elseif type(_G.MSUF_UpdateCastbarTextures) == "function" then
        _G.MSUF_UpdateCastbarTextures()
    end
end

local function UpdateAbsorbBarTextures()
    local getAbsorbTexture = _G.MSUF_GetAbsorbBarTexture
    local getHealAbsorbTexture = _G.MSUF_GetHealAbsorbBarTexture
    local texAbs = type(getAbsorbTexture) == "function" and getAbsorbTexture() or nil
    local texHeal = type(getHealAbsorbTexture) == "function" and getHealAbsorbTexture() or nil

    if not texAbs or not texHeal then
        local getBarTexture = _G.MSUF_GetBarTexture
        local texHP = type(getBarTexture) == "function" and getBarTexture() or nil
        texAbs = texAbs or texHP
        texHeal = texHeal or texHP
        if not texAbs or not texHeal then return end
    end

    _iterState.texAbs = texAbs
    _iterState.texHeal = texHeal
    ForEachUnitFrame(_Iter_ApplyAbsorbTex)
end

Export("MSUF_UpdateAbsorbBarTextures", UpdateAbsorbBarTextures)
Export("MSUF_UpdateAllBarTextures", UpdateAllBarTextures, "UpdateAllBarTextures", true)

function _G.MSUF_DetachedPowerBar_RefreshTextures()
    local dpb = ns.Bars and ns.Bars._DetachedPowerBarTextures
    if dpb then
        dpb.fgK = false
        dpb.fgC = nil
        dpb.bgK = false
        dpb.bgC = nil
    end
    UpdateAllBarTextures()
end

if not _G.MSUF_UpdateAllBarTextures_Immediate then
    _G.MSUF_UpdateAllBarTextures_Immediate = _G.MSUF_UpdateAllBarTextures
    _G.MSUF_UpdateAllBarTextures = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.bars = true end
        ScheduleApplyCommit()
    end
    _G.UpdateAllBarTextures = _G.MSUF_UpdateAllBarTextures
end

if ns then
    ns.MSUF_UpdateAllBarTextures = UpdateAllBarTextures
end

local function MSUF_UpdateAbsorbTextMode()
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not g then return end
    local mode = tonumber(g.absorbTextMode)
    if not mode then return end
    if mode == 1 then
        g.enableAbsorbBar = false
        g.showTotalAbsorbAmount = false
    elseif mode == 2 then
        g.enableAbsorbBar = true
        g.showTotalAbsorbAmount = false
    elseif mode == 3 then
        g.enableAbsorbBar = true
        g.showTotalAbsorbAmount = true
    elseif mode == 4 then
        g.enableAbsorbBar = false
        g.showTotalAbsorbAmount = true
    end
end

Export("MSUF_UpdateAbsorbTextMode", MSUF_UpdateAbsorbTextMode, "MSUF_UpdateAbsorbTextMode")

ns.Textures.UpdateAllBarTextures = UpdateAllBarTextures
ns.Textures.UpdateAbsorbBarTextures = UpdateAbsorbBarTextures
