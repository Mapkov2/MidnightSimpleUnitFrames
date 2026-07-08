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
function Runtime.VisualScaleForPreviewKey(key)
    local runtimeUnit = key == "boss" and "boss1" or key
    local frame = CoreFrame(runtimeUnit) or (runtimeUnit and _G["MSUF_" .. runtimeUnit])
    local scale = frame and frame.GetScale and frame:GetScale()
    if scale then return ClampRuntimeVisualScale(scale) end
    local db = _G.MSUF_DB
    local g = db and db.general
    return ClampRuntimeVisualScale(g and (g.msufUiScale or g.uiScale) or 1)
end
