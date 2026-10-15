--- Unit preview runtime readers.
---
--- The runtime compiles and applies the live specs. Preview reads only the
--- published tables, including while an apply is pending. Config.GetSpec can
--- recompile dirty or missing specs in place without applying them, replacing
--- sub-tables the live frames compare by identity. Missing specs keep using the
--- renderer's existing fallbacks until the runtime publishes them.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local Runtime = MSUF.UFPreviewRuntime or {}
MSUF.UFPreviewRuntime = Runtime
local CoreFrame = MSUF.UF.GetFrame
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
local LiveCastbarFrame = MSUF.UFPreviewCastbar.RuntimeFrame
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
-- A unit the client has no frames for (focus/boss/arena on Classic Era, arena
-- on WoW Forever) never gets a compiled spec, and Config.GetSpec recompiles the
-- whole unit config on every miss. Client facts, memoized once per unit.
local previewUnitSupported = {}
local function PreviewUnitSupported(runtimeUnit)
    local supported = previewUnitSupported[runtimeUnit]
    if supported == nil then
        local client = MSUF.Client
        supported = not (client and type(client.SupportsUnit) == "function") or client.SupportsUnit(runtimeUnit) == true
        previewUnitSupported[runtimeUnit] = supported
    end
    return supported
end
function Runtime.SpecForPreviewKey(key)
    local uf = MSUF and MSUF.UF
    local config = uf and uf.Config
    local runtimeUnit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
    if not runtimeUnit or not PreviewUnitSupported(runtimeUnit) then return nil end
    local specs = config and config.specs
    return type(specs) == "table" and specs[runtimeUnit] or nil
end
function Runtime.AppliedPortraitSizeForPreviewKey(key)
    local runtimeUnit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
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
    local runtimeUnit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
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
    local runtimeUnit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
    local unitFrame = CoreFrame(runtimeUnit) or (runtimeUnit and _G["MSUF_" .. runtimeUnit])
    local castbar = LiveCastbarFrame(key)
    local unitX, unitY = ScaledCenter(unitFrame)
    local castX, castY = ScaledCenter(castbar)
    local unitScale = unitFrame and unitFrame.GetEffectiveScale and tonumber(unitFrame:GetEffectiveScale())
    if not (unitX and unitY and castX and castY and unitScale and unitScale > 0) then return nil end
    return (castX - unitX) / unitScale, (castY - unitY) / unitScale
end
