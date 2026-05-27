--- Core/MSUF_TextureRuntime.lua
--- Runtime bar texture refresh and deferred texture apply wrappers.
--- Shared texture runtime helpers with stable exported globals.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF
MSUF.Textures = MSUF.Textures or {}

local type, tonumber = type, tonumber
local pairs = pairs

local function Export(key, fn, aliasKey, forceAlias)
    if MSUF then MSUF[key] = fn end
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
    if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
        (_G.MSUF_EnsureDB)()
    end
end

local function ForEachUnitFrame(fn)
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame then fn(frame) end
    end
end

local function ScheduleApplyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", function() commit(UF) end)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function() commit(UF) end)
    else
        commit(UF)
    end
end

local _iterState = {}
local PREDICTION_REFRESH_ELEMENTS = { "Prediction" }

local function RefreshPredictionElements(reason)
    local refreshed = false
    local UF = MSUF and MSUF.UF
    if UF and type(UF.RefreshElements) == "function" then
        refreshed = UF.RefreshElements(nil, PREDICTION_REFRESH_ELEMENTS, reason or "MSUF2_ABSORB_TEXTURE") or refreshed
    end
    local GF = MSUF and MSUF.GF
    if GF and type(GF.RefreshVisuals) == "function" then
        refreshed = GF.RefreshVisuals(nil, GF.DIRTY_VISUAL) or refreshed
    end
    return refreshed
end

local function _ApplyTexCached(sb, tex)
    if not sb or not tex then return end
    if sb.MSUF_cachedStatusbarTexture ~= tex then
        sb:SetStatusBarTexture(tex)
        sb.MSUF_cachedStatusbarTexture = tex
        sb._msufTexture = tex
        local applyAlpha = (MSUF.Bars and MSUF.Bars._ApplyOverlayTextureAlpha) or _G.MSUF_ApplyOverlayTextureAlpha
        if type(applyAlpha) == "function" then
            applyAlpha(sb)
        end
    end
end

local function _Iter_ApplyAllBarTex(f)
    local S = _iterState
    _ApplyTexCached(f.hpBar, S.texHP)
    if S.applyBg then S.applyBg(f) end

    local pbTex = S.texHP
    if f._msufPowerBarDetached and S.texDPB then
        pbTex = S.texDPB
    end
    _ApplyTexCached(f.targetPowerBar, pbTex)
end

local function UpdateAllBarTextures()
    local getBarTexture = _G.MSUF_GetBarTexture
    if type(getBarTexture) ~= "function" then return end
    local texHP = getBarTexture()
    if not texHP then return end

    local dpb = MSUF.Bars and MSUF.Bars._DetachedPowerBarTextures

    _iterState.texHP = texHP
    _iterState.texDPB = (dpb and dpb.ResolveFg and dpb.ResolveFg()) or texHP
    _iterState.applyBg = _G.MSUF_ApplyBarBackgroundVisual

    ForEachUnitFrame(_Iter_ApplyAllBarTex)
    RefreshPredictionElements("MSUF2_BAR_TEXTURE")
    if _G.MSUF_RoundedUF_Active == true then
        local applyRounded = _G.MSUF_RoundedUF_OnApplyAll
        if type(applyRounded) == "function" then
            applyRounded()
        end
    end

    if _G.MSUF_UpdateCastbarTextures_Immediate then
        _G.MSUF_UpdateCastbarTextures_Immediate()
    elseif type(_G.MSUF_UpdateCastbarTextures) == "function" then
        _G.MSUF_UpdateCastbarTextures()
    end
end

local function UpdateAbsorbBarTextures()
    local refreshed = RefreshPredictionElements("MSUF2_ABSORB_TEXTURE")
    if _G.MSUF_RoundedUF_Active == true then
        local applyRounded = _G.MSUF_RoundedUF_OnApplyAll
        if type(applyRounded) == "function" then
            applyRounded()
        end
    end
    return refreshed
end

Export("MSUF_UpdateAbsorbBarTextures", UpdateAbsorbBarTextures)
Export("MSUF_UpdateAllBarTextures", UpdateAllBarTextures, "UpdateAllBarTextures", true)

function _G.MSUF_DetachedPowerBar_RefreshTextures()
    local dpb = MSUF.Bars and MSUF.Bars._DetachedPowerBarTextures
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
    _G.UpdateAllBarTextures = _G.UpdateAllBarTextures or _G.MSUF_UpdateAllBarTextures
end

if MSUF then
    MSUF.MSUF_UpdateAllBarTextures = UpdateAllBarTextures
end

local function MSUF_UpdateAbsorbDisplayMode(mode)
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not g then return end
    mode = tonumber(mode or g.absorbTextMode) or 2
    if mode == 1 or mode == 4 then
        g.absorbTextMode = 1
        g.enableAbsorbBar = false
    else
        g.absorbTextMode = 2
        g.enableAbsorbBar = true
    end
    g.showTotalAbsorbAmount = false
end

Export("MSUF_UpdateAbsorbDisplayMode", MSUF_UpdateAbsorbDisplayMode, "MSUF_UpdateAbsorbDisplayMode")

MSUF.Textures.UpdateAllBarTextures = UpdateAllBarTextures
MSUF.Textures.UpdateAbsorbBarTextures = UpdateAbsorbBarTextures
