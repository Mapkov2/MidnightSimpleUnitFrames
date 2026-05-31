--- Unit preview runtime readers.
---
--- These helpers are intentionally read-only. The preview must not rebuild live
--- unit specs while the user is just switching Menu2 pages.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local Runtime = MSUF.UFPreviewRuntime or {}
MSUF.UFPreviewRuntime = Runtime

local function ClampRuntimeVisualScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return 1 end
    if scale < 0.25 then return 0.25 end
    if scale > 1.5 then return 1.5 end
    return scale
end

function Runtime.SpecForPreviewKey(key)
    local uf = MSUF and MSUF.UF
    local config = uf and uf.Config
    local runtimeUnit = key == "boss" and "boss1" or key
    if not runtimeUnit then return nil end
    local specs = config and config.specs
    local spec = type(specs) == "table" and specs[runtimeUnit] or nil
    if spec and config and config.dirty ~= true then return spec end
    if config and type(config.GetSpec) == "function" then
        return config.GetSpec(runtimeUnit)
    end
    return spec
end

function Runtime.VisualScaleForPreviewKey(key)
    local runtimeUnit = key == "boss" and "boss1" or key
    local frames = _G.MSUF_UnitFrames
    local frame = runtimeUnit and ((frames and frames[runtimeUnit]) or _G["MSUF_" .. runtimeUnit])
    local scale = frame and frame.GetScale and frame:GetScale()
    if scale then return ClampRuntimeVisualScale(scale) end

    local db = _G.MSUF_DB
    local g = db and db.general
    return ClampRuntimeVisualScale(g and (g.msufUiScale or g.uiScale) or 1)
end
