--- Unit preview runtime readers.
---
--- These helpers are read-only for regular page switches. Profile swaps/reset
--- replace MSUF_DB, so the preview must invalidate stale cached specs before
--- it reads them.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local Runtime = MSUF.UFPreviewRuntime or {}
MSUF.UFPreviewRuntime = Runtime
local lastDBRef, lastProfileName
local function CoreFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end
local function ClampRuntimeVisualScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return 1 end
    if scale < 0.25 then return 0.25 end
    if scale > 2.0 then return 2.0 end
    return scale
end
local function ClampEffectiveScaleRatio(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return 1 end
    if scale < 0.05 then return 0.05 end
    if scale > 8 then return 8 end
    return scale
end
local function LiveCastbarFrame(key)
    if key == "boss" then
        local bars = _G.MSUF_BossCastbars
        return (type(bars) == "table" and bars[1])
            or _G.MSUF_BossCastbar1
            or _G.MSUF_boss1CastBar
            or _G.MSUF_BossCastbarPreview
            or _G.MSUF_BossCastbarPreview1
    elseif key == "player" then
        return _G.MSUF_PlayerCastbar or _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbarPreview
    elseif key == "target" then
        return _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar or _G.MSUF_TargetCastbarPreview
    elseif key == "focus" then
        return _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbarPreview
    end
end
local function ScaledCenter(frame)
    if not (frame and frame.GetCenter and frame.GetEffectiveScale) then return nil end
    local x, y = frame:GetCenter()
    local scale = tonumber(frame:GetEffectiveScale())
    if type(x) ~= "number" or type(y) ~= "number" or not scale or scale <= 0 then return nil end
    return x * scale, y * scale
end
local function EffectiveScaleRatio(frame, targetFrame)
    local sourceEffective = frame and frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale())
    local targetEffective = targetFrame and targetFrame.GetEffectiveScale and tonumber(targetFrame:GetEffectiveScale())
    if sourceEffective and sourceEffective > 0 and targetEffective and targetEffective > 0 then
        return ClampEffectiveScaleRatio(sourceEffective / targetEffective)
    end
end
function Runtime.SpecForPreviewKey(key)
    local uf = MSUF and MSUF.UF
    local config = uf and uf.Config
    local runtimeUnit = key == "boss" and "boss1" or key
    if not runtimeUnit then return nil end
    local dbRef, profileName = _G.MSUF_DB, _G.MSUF_ActiveProfile
    if config and (dbRef ~= lastDBRef or profileName ~= lastProfileName) then
        lastDBRef, lastProfileName = dbRef, profileName
        if type(config.Refresh) == "function" and not (_G.InCombatLockdown and _G.InCombatLockdown()) then
            config.Refresh()
        else
            config.dirty = true
        end
    end
    local specs = config and config.specs
    local spec = type(specs) == "table" and specs[runtimeUnit] or nil
    if spec and config and config.dirty ~= true then return spec end
    if config and type(config.GetSpec) == "function" then return config.GetSpec(runtimeUnit) end
    return spec
end
function Runtime.AppliedPortraitSizeForPreviewKey(key)
    local runtimeUnit = key == "boss" and "boss1" or key
    local frame = CoreFrame(runtimeUnit) or (runtimeUnit and _G["MSUF_" .. runtimeUnit])
    local portrait = frame and frame.MSUFSpec and frame.MSUFSpec.portrait
    local holder = frame and frame.MSUFPortraitHolder
    -- Edit Mode displays this applied holder. Only trust it after Portrait.Apply
    -- has consumed the same spec; otherwise a just-switched profile could expose
    -- the previous profile's cached holder size for one preview refresh.
    if not (portrait and portrait.enabled == true and holder
        and frame._msufPortraitRuntimeCfg == portrait) then
        return nil
    end
    local width = tonumber(holder._msufLayoutWidth) or tonumber(holder._msufWidth)
    local height = tonumber(holder._msufLayoutHeight) or tonumber(holder._msufHeight)
    if (not width or width <= 0) and holder.GetWidth then width = tonumber(holder:GetWidth()) end
    if (not height or height <= 0) and holder.GetHeight then height = tonumber(holder:GetHeight()) end
    if not (width and width > 0 and height and height > 0) then return nil end
    return width, height
end
function Runtime.VisualScaleForPreviewKey(key, targetFrame)
    local runtimeUnit = key == "boss" and "boss1" or key
    local frame = CoreFrame(runtimeUnit) or (runtimeUnit and _G["MSUF_" .. runtimeUnit])
    local runtimeEffective = frame and frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale())
    local targetEffective = targetFrame and targetFrame.GetEffectiveScale and tonumber(targetFrame:GetEffectiveScale())
    if runtimeEffective and runtimeEffective > 0 and targetEffective and targetEffective > 0 then
        return ClampEffectiveScaleRatio(runtimeEffective / targetEffective)
    end
    local scale = frame and frame.GetScale and tonumber(frame:GetScale())
    if scale and scale > 0 and targetEffective and targetEffective > 0 then
        local uiEffective = _G.UIParent and _G.UIParent.GetEffectiveScale and tonumber(_G.UIParent:GetEffectiveScale())
        if uiEffective and uiEffective > 0 then
            return ClampEffectiveScaleRatio((scale * uiEffective) / targetEffective)
        end
    end
    if scale then return ClampRuntimeVisualScale(scale) end
    local db = _G.MSUF_DB
    local g = db and db.general
    scale = ClampRuntimeVisualScale(g and (g.msufUiScale or g.uiScale) or 1)
    if targetEffective and targetEffective > 0 then
        local uiEffective = _G.UIParent and _G.UIParent.GetEffectiveScale and tonumber(_G.UIParent:GetEffectiveScale())
        if uiEffective and uiEffective > 0 then
            return ClampEffectiveScaleRatio((scale * uiEffective) / targetEffective)
        end
    end
    return scale
end
function Runtime.CastbarVisualScaleForPreviewKey(key, targetFrame)
    -- Menu2 draws the unit and its castbar inside one canvas, but live castbars
    -- are independent UIParent frames. Read the live castbar's own effective
    -- scale so its castbar-local desired width is rendered at the same screen
    -- size as runtime instead of inheriting the unit-frame scale.
    return EffectiveScaleRatio(LiveCastbarFrame(key) or _G.UIParent, targetFrame) or 1
end
function Runtime.DetachedCastbarOffsetForPreviewKey(key)
    -- Detached castbar offsets are UIParent-relative SavedVariables, while the
    -- Unit Preview canvas is unit-frame-relative. Project the already-applied
    -- live geometry into unit-frame coordinates so the preview mirrors the
    -- real relationship without rewriting the user's absolute position.
    local runtimeUnit = key == "boss" and "boss1" or key
    local unitFrame = CoreFrame(runtimeUnit) or (runtimeUnit and _G["MSUF_" .. runtimeUnit])
    local castbar = LiveCastbarFrame(key)
    local unitX, unitY = ScaledCenter(unitFrame)
    local castX, castY = ScaledCenter(castbar)
    local unitScale = unitFrame and unitFrame.GetEffectiveScale and tonumber(unitFrame:GetEffectiveScale())
    if not (unitX and unitY and castX and castY and unitScale and unitScale > 0) then return nil end
    return (castX - unitX) / unitScale, (castY - unitY) / unitScale
end
