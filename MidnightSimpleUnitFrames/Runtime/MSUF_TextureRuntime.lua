--- Runtime/MSUF_TextureRuntime.lua
--- Runtime bar texture refresh and deferred texture apply wrappers.
--- Shared texture runtime helpers with stable exported globals.
---
--- Texture selection/resolution happens elsewhere; this file applies the chosen
--- textures to existing unit frames, prediction bars, detached power bars, and
--- castbars, then schedules a UF apply commit when needed.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Textures = MSUF.Textures or {}

local type, tonumber = type, tonumber
local pairs = pairs

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function Export(key, fn, aliasKey, forceAlias)
    if MSUF then MSUF[key] = fn end
    ExportPublic(key, fn)
    if aliasKey then
        if forceAlias then
            ExportPublic(aliasKey, fn)
        else
            ExportPublic(aliasKey, _G[aliasKey] or fn)
        end
    end
    return fn
end

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
        (_G.MSUF_EnsureDB)()
    end
end

local function NormalizeScope(scope)
    scope = tostring(scope or ""):lower()
    if scope == "" or scope == "*" or scope == "shared" or scope == "global" or scope == "all" then return nil end
    if scope == "tot" or scope == "targetoftarget" then return "targettarget" end
    if scope == "focus_target" or scope == "focustargettarget" then return "focustarget" end
    if scope:match("^boss%d+$") then return scope end
    return scope
end

local function GroupKindsForScope(scope)
    scope = NormalizeScope(scope)
    if scope == "gf_party" or scope == "party" then return "party" end
    if scope == "gf_raid" or scope == "raid" then return "raid", "mythicraid" end
    if scope == "gf_mythicraid" or scope == "mythicraid" then return "mythicraid" end
    return nil
end

local function UnitFrameInScope(frame, scope)
    scope = NormalizeScope(scope)
    if not scope then return true end
    if GroupKindsForScope(scope) then return false end
    local unit = frame and (frame.MSUFUnitKey or frame.unit)
    if unit == scope then return true end
    local UF = MSUF and MSUF.UF
    local units = UF and type(UF.UnitsForConfigKey) == "function" and UF.UnitsForConfigKey(scope) or nil
    for i = 1, #(units or {}) do
        if units[i] == unit then return true end
    end
    return false
end

local function ForEachUnitFrame(fn, scope)
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame and UnitFrameInScope(frame, scope) then fn(frame) end
    end
end

--- Profile/menu texture changes can arrive in bursts. Defer the final UF dirty
--- apply so multiple setters collapse into one engine commit.
local function ApplyDirtyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) == "function" then commit(UF) end
end

local function ScheduleApplyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", ApplyDirtyCommit)
    else
        _G.C_Timer.After(0, ApplyDirtyCommit)
    end
end

local _iterState = {}
local PREDICTION_REFRESH_ELEMENTS = { "Prediction" }

local function RefreshPredictionElements(reason, scope, skipUnitFrames)
    local refreshed = false
    local kindA, kindB = GroupKindsForScope(scope)
    local normalized = NormalizeScope(scope)
    local UF = MSUF and MSUF.UF
    if skipUnitFrames ~= true and not kindA and UF and type(UF.RefreshElements) == "function" then
        refreshed = UF.RefreshElements(normalized, PREDICTION_REFRESH_ELEMENTS, reason or "MSUF2_ABSORB_TEXTURE") or refreshed
    end
    local GF = MSUF and MSUF.GF
    if GF and type(GF.RefreshVisuals) == "function" then
        if kindA then
            refreshed = GF.RefreshVisuals(kindA, GF.DIRTY_VISUAL) or refreshed
            if kindB then refreshed = GF.RefreshVisuals(kindB, GF.DIRTY_VISUAL) or refreshed end
        elseif not normalized then
            refreshed = GF.RefreshVisuals(nil, GF.DIRTY_VISUAL) or refreshed
        end
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
    local spec = f and f.MSUFSpec
    local hpTex = (spec and spec.health and spec.health.texture) or (spec and spec.texture) or S.texHP
    _ApplyTexCached(f.hpBar, hpTex)
    if S.applyBg then S.applyBg(f) end

    -- The compiler owns the full power-texture precedence (global bars value ->
    -- Class Resources detached art -> per-unit override), so the finished spec
    -- value is authoritative for every unit. This pass therefore needs no
    -- detached/Player special case and no second texture-key resolve.
    local pbTex = (spec and spec.power and spec.power.texture) or (spec and spec.texture) or hpTex
    -- ROUND/CRYSTAL/ORB use fixed fill art owned by the Power element. A global
    -- statusbar refresh must not replace that art with the rectangular bar media.
    if not (f.targetPowerBar and f.targetPowerBar._msufPowerShapeActive == true) then
        _ApplyTexCached(f.targetPowerBar, pbTex)
    end
end

--- Immediate refresh path used by the deferred wrapper and direct callers. Keep
--- this frame-iteration-only; it should not normalize profile texture keys.
local function UpdateAllBarTextures(scope, skipUnitFrames, skipCastbars)
    local kindA = GroupKindsForScope(scope)
    if kindA then
        RefreshPredictionElements("MSUF2_BAR_TEXTURE", scope)
        return
    end

    -- Refresh the scoped specs before reading frame.MSUFSpec below. Prediction
    -- owns the same Health/Power config dependency, so doing it first gives the
    -- direct texture pass current data without a second deferred full apply.
    RefreshPredictionElements("MSUF2_BAR_TEXTURE", scope, skipUnitFrames)

    if skipUnitFrames ~= true then
        local getBarTexture = _G.MSUF_GetBarTexture
        if type(getBarTexture) ~= "function" then return end
        local texHP = getBarTexture()
        if not texHP then return end

        _iterState.texHP = texHP
        _iterState.applyBg = _G.MSUF_ApplyBarBackgroundVisual

        ForEachUnitFrame(_Iter_ApplyAllBarTex, scope)
    end
    if not NormalizeScope(scope) and _G.MSUF_RoundedUF_Active == true then
        local applyRounded = _G.MSUF_RoundedUF_OnApplyAll
        if type(applyRounded) == "function" then
            applyRounded()
        end
    end

    if skipCastbars ~= true and not NormalizeScope(scope) and _G.MSUF_UpdateCastbarTextures_Immediate then
        _G.MSUF_UpdateCastbarTextures_Immediate()
    elseif skipCastbars ~= true and not NormalizeScope(scope) and type(_G.MSUF_UpdateCastbarTextures) == "function" then
        _G.MSUF_UpdateCastbarTextures()
    end
end

local function UpdateAbsorbBarTextures(scope)
    local refreshed = RefreshPredictionElements("MSUF2_ABSORB_TEXTURE", scope)
    if not NormalizeScope(scope) and _G.MSUF_RoundedUF_Active == true then
        local applyRounded = _G.MSUF_RoundedUF_OnApplyAll
        if type(applyRounded) == "function" then
            applyRounded()
        end
    end
    return refreshed
end

Export("MSUF_UpdateAbsorbBarTextures", UpdateAbsorbBarTextures)
Export("MSUF_UpdateAllBarTextures", UpdateAllBarTextures, "UpdateAllBarTextures", true)

local function DetachedPowerBarRefreshTextures()
    -- The detached Player bar has no dedicated texture keys anymore; the
    -- compiled spec owns the full power-texture precedence, so a plain
    -- player-scoped refresh repaints everything.
    UpdateAllBarTextures("player")
end
Export("MSUF_DetachedPowerBar_RefreshTextures", DetachedPowerBarRefreshTextures)

if not _G.MSUF_UpdateAllBarTextures_Immediate then
    ExportPublic("MSUF_UpdateAllBarTextures_Immediate", _G.MSUF_UpdateAllBarTextures)
    ExportPublic("MSUF_UpdateAllBarTextures", function(scope)
        local st = _G.MSUF_ApplyCommitState
        if st then st.bars = true end
        local UF = MSUF and MSUF.UF
        local normalized = NormalizeScope(scope)
        if normalized and not GroupKindsForScope(normalized) and UF and type(UF.MarkDirty) == "function" then
            UF.MarkDirty(normalized)
        end
        ScheduleApplyCommit()
    end)
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
