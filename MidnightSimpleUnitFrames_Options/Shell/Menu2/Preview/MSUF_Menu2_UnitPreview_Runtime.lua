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
    if scale > 1.5 then return 1.5 end
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
