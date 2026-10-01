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

local ExportPublic = MSUF.ExportPublic



local EnsureDBSafe = MSUF.Util.EnsureDBSafe

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


local ScheduleApplyCommit = _G.MSUF_UF_ScheduleApplyCommit

local _iterState = {}
local PREDICTION_REFRESH_ELEMENTS = { "Prediction", "Alpha" }

local function RefreshPredictionElements(reason, scope, skipUnitFrames)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.RefreshPredictionBars) == "function" then
        return UF.RefreshPredictionBars(scope, reason or "MSUF2_ABSORB_TEXTURE", skipUnitFrames) or false
    end
    local kindA = GroupKindsForScope(scope)
    if skipUnitFrames ~= true and not kindA and UF and type(UF.RefreshElements) == "function" then
        return UF.RefreshElements(NormalizeScope(scope), PREDICTION_REFRESH_ELEMENTS, reason or "MSUF2_ABSORB_TEXTURE") or false
    end
    return false
end

local function RefreshGroupBarVisuals(scope)
    local kindA, kindB = GroupKindsForScope(scope)
    local normalized = NormalizeScope(scope)
    local GF = MSUF and MSUF.GF
    if not (GF and type(GF.RefreshVisuals) == "function") then return false end
    local refreshed = false
    if kindA then
        refreshed = GF.RefreshVisuals(kindA, GF.DIRTY_VISUAL) or refreshed
        if kindB then refreshed = GF.RefreshVisuals(kindB, GF.DIRTY_VISUAL) or refreshed end
    elseif not normalized then
        refreshed = GF.RefreshVisuals(nil, GF.DIRTY_VISUAL) or refreshed
    end
    return refreshed
end

local function _ApplyTexCached(sb, tex)
    if not sb or not tex then return false end
    if sb.MSUF_cachedStatusbarTexture ~= tex then
        sb:SetStatusBarTexture(tex)
        sb.MSUF_cachedStatusbarTexture = tex
        sb._msufTexture = tex
        sb._msufAlphaStatusTextureObject = nil
        sb._msufGFStatusBarTextureWidget = nil
        return true
    end
    return false
end

local function _Iter_ApplyAllBarTex(f)
    local S = _iterState
    local spec = f and f.MSUFSpec
    local hpTex = (spec and spec.health and spec.health.texture) or (spec and spec.texture) or S.texHP
    local healthTextureChanged = _ApplyTexCached(f.hpBar, hpTex)
    if S.applyBg then S.applyBg(f) end

    -- The compiler owns the full power-texture precedence (global bars value ->
    -- Class Resources detached art -> per-unit override), so the finished spec
    -- value is authoritative for every unit. This pass therefore needs no
    -- detached/Player special case and no second texture-key resolve.
    local pbTex = (spec and spec.power and spec.power.texture) or (spec and spec.texture) or hpTex
    -- ROUND/CRYSTAL/ORB use fixed fill art owned by the Power element. A global
    -- statusbar refresh must not replace that art with the rectangular bar media.
    local powerTextureChanged = false
    if not (f.targetPowerBar and f.targetPowerBar._msufPowerShapeActive == true) then
        powerTextureChanged = _ApplyTexCached(f.targetPowerBar, pbTex)
    end
    -- A swapped fill drops the Alpha element's cached texture object above;
    -- re-run the frame's alpha so the new fill gets its opacity now.
    if healthTextureChanged or powerTextureChanged then
        local UF = MSUF and MSUF.UF
        if UF and type(UF.ApplyAlphaFrame) == "function" then
            UF.ApplyAlphaFrame(f, "MSUF_FORCE_UPDATE")
        end
    end
end

--- Immediate refresh path used by the deferred wrapper and direct callers. Keep
--- this frame-iteration-only; it should not normalize profile texture keys.
local function UpdateAllBarTextures(scope, skipUnitFrames, skipCastbars)
    local kindA = GroupKindsForScope(scope)
    if kindA then
        -- GroupVisuals owns group health/power/bar media. A bar-texture apply
        -- therefore keeps the full visual mask; the narrow Prediction+Alpha
        -- follower is only sufficient for prediction/absorb-only refreshes.
        RefreshGroupBarVisuals(scope)
        return
    end

    -- Refresh the scoped specs before reading frame.MSUFSpec below. Prediction
    -- owns the same Health/Power config dependency, so doing it first gives the
    -- direct texture pass current data without a second deferred full apply.
    if not NormalizeScope(scope) then
        local UF = MSUF and MSUF.UF
        if skipUnitFrames ~= true and UF and type(UF.RefreshElements) == "function" then
            UF.RefreshElements(nil, PREDICTION_REFRESH_ELEMENTS, "MSUF2_BAR_TEXTURE")
        end
        RefreshGroupBarVisuals(nil)
    else
        RefreshPredictionElements("MSUF2_BAR_TEXTURE", scope, skipUnitFrames)
    end

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

MSUF.MSUF_UpdateAbsorbBarTextures = UpdateAbsorbBarTextures
ExportPublic("MSUF_UpdateAbsorbBarTextures", UpdateAbsorbBarTextures)
MSUF.MSUF_UpdateAllBarTextures = UpdateAllBarTextures
ExportPublic("MSUF_UpdateAllBarTextures", UpdateAllBarTextures)
--- Deprecated compatibility alias: the unprefixed global predates the MSUF_
--- prefix and may still be called by user scripts. MSUF itself never reads it;
--- it is only claimed while no other addon owns that name.
if rawget(_G, "UpdateAllBarTextures") == nil then
    ExportPublic("UpdateAllBarTextures", UpdateAllBarTextures)
end
MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
MSUF.Compat.DeprecatedAliases.UpdateAllBarTextures = "MSUF_UpdateAllBarTextures_Immediate"

local function DetachedPowerBarRefreshTextures()
    -- The detached Player bar has no dedicated texture keys anymore; the
    -- compiled spec owns the full power-texture precedence, so a plain
    -- player-scoped refresh repaints everything.
    UpdateAllBarTextures("player")
end
MSUF.MSUF_DetachedPowerBar_RefreshTextures = DetachedPowerBarRefreshTextures
ExportPublic("MSUF_DetachedPowerBar_RefreshTextures", DetachedPowerBarRefreshTextures)

if not _G.MSUF_UpdateAllBarTextures_Immediate then
    ExportPublic("MSUF_UpdateAllBarTextures_Immediate", UpdateAllBarTextures)
    --- A unit scope marks its frames dirty for the next UF apply commit. A
    --- global or group scope has no dirty-frame route, so it repaints on the
    --- next frame instead; a burst of calls collapses into one pass, and a
    --- global request covers every scoped one.
    local deferredAll, deferredScopes = false, {}
    local function FlushDeferredBarTextures()
        if deferredAll then
            deferredAll = false
            for scope in pairs(deferredScopes) do deferredScopes[scope] = nil end
            UpdateAllBarTextures(nil)
            return
        end
        for scope in pairs(deferredScopes) do
            deferredScopes[scope] = nil
            UpdateAllBarTextures(scope)
        end
    end
    local ScheduleOnce = MSUF.Scheduler.ScheduleOnce
    ExportPublic("MSUF_UpdateAllBarTextures", function(scope)
        local UF = MSUF and MSUF.UF
        local normalized = NormalizeScope(scope)
        if normalized and not GroupKindsForScope(normalized) and UF and type(UF.MarkDirty) == "function" then
            UF.MarkDirty(normalized)
            ScheduleApplyCommit()
            return
        end
        if normalized then deferredScopes[normalized] = true else deferredAll = true end
        ScheduleOnce("MSUF_BAR_TEXTURES_DEFERRED", FlushDeferredBarTextures)
    end)
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

MSUF.MSUF_UpdateAbsorbDisplayMode = MSUF_UpdateAbsorbDisplayMode
ExportPublic("MSUF_UpdateAbsorbDisplayMode", MSUF_UpdateAbsorbDisplayMode)

MSUF.Textures.UpdateAllBarTextures = UpdateAllBarTextures
MSUF.Textures.UpdateAbsorbBarTextures = UpdateAbsorbBarTextures
