local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
-- InstallClassicAuraPreview: isolated ownership, bound once during addon initialization.
local _, MSUF = ...
MSUF.InstallClassicAuraPreview = function(dependencies)
local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local A3 = dependencies.A3
local ApplyConfig = dependencies.ApplyConfig
local CompileFrameAuraVisual = dependencies.CompileFrameAuraVisual
local ExportPublic = dependencies.ExportPublic
local HideState = dependencies.HideState
local ResolveGroupFrameConfig = dependencies.ResolveGroupFrameConfig
local UF = dependencies.UF
local UpdateAuras = dependencies.UpdateAuras
function A3._NormalizeClassicDispelPreviewScope(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" or scope == "all" or scope == "global" then return "shared" end
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

function A3._ClassicDispelPreviewApplies(frame, scope, includeGroup)
    if not frame then return false end
    local wanted = A3._NormalizeClassicDispelPreviewScope(scope)
    local spec = frame.MSUFSpec
    local groupKind = frame._msufGFKind or (spec and spec.groupKind)
    local isGroup = groupKind ~= nil or (spec and spec.scope == "group")
    if isGroup and includeGroup ~= true then return false end
    if wanted == "shared" then return true end
    if isGroup then
        if wanted == "raid" then return groupKind == "raid" or groupKind == "mythicraid" end
        return groupKind == wanted
    end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

function A3._ForEachClassicDispelPreviewFrame(fn)
    if UF and type(UF.ForEachFrame) == "function" then UF.ForEachFrame(fn) end
    local gf = MSUF and MSUF.GF
    if not gf then return end
    if type(gf.ForEachFrame) == "function" then gf.ForEachFrame(fn, true) end
    local previews = gf._previewFrames
    if type(previews) ~= "table" then return end
    for _, frames in pairs(previews) do
        if type(frames) == "table" then
            for _, frame in pairs(frames) do
                if type(frame) == "table" then fn(frame) end
            end
        end
    end
end

function A3._ApplyClassicDispelOverlayPreview(frame)
    local renderer = A3.ClassicVisuals
    if not (renderer and type(renderer.UpdateDispelOverlayPreview) == "function") then return false end
    local active = _G.MSUF_DispelOverlayPreviewMode == true
        and A3._ClassicDispelPreviewApplies(frame, _G.MSUF_DispelOverlayPreviewScope, true)
    local visual = active and frame and frame.MSUFSpec and CompileFrameAuraVisual(frame.MSUFSpec) or nil
    active = active and visual and visual.overlayEnabled == true or false
    return renderer.UpdateDispelOverlayPreview(frame, visual, active)
end

function A3.RefreshDispelOverlayPreview()
    A3._ForEachClassicDispelPreviewFrame(A3._ApplyClassicDispelOverlayPreview)
    return true
end

function A3.SetDispelOverlayPreview(active, scope)
    active = active == true
    if active and A3._ClassicAuraRuntimeCombatBlocked() then active = false end
    ExportPublic("MSUF_DispelOverlayPreviewMode", active)
    ExportPublic("MSUF_DispelOverlayPreviewScope",
        active and A3._NormalizeClassicDispelPreviewScope(scope) or nil)
    A3.RefreshDispelOverlayPreview()
    return active
end

function A3._ApplyClassicDispelSymbolPreview(frame)
    local renderer = A3.ClassicVisuals
    if not (renderer and type(renderer.UpdateDispelSymbolPreview) == "function") then return false end
    local active = _G.MSUF_DispelSymbolPreviewMode == true
        and A3._ClassicDispelPreviewApplies(frame, _G.MSUF_DispelSymbolPreviewScope, false)
    local visual = active and frame and frame.MSUFSpec and CompileFrameAuraVisual(frame.MSUFSpec) or nil
    active = active and visual and visual.symbol and visual.symbol.enabled == true or false
    return renderer.UpdateDispelSymbolPreview(frame, visual, active)
end

function A3.RefreshDispelSymbolPreview()
    A3._ForEachClassicDispelPreviewFrame(A3._ApplyClassicDispelSymbolPreview)
    return true
end

function A3.SetDispelSymbolPreview(active, scope)
    active = active == true
    if active and A3._ClassicAuraRuntimeCombatBlocked() then active = false end
    ExportPublic("MSUF_DispelSymbolPreviewMode", active)
    ExportPublic("MSUF_DispelSymbolPreviewScope",
        active and A3._NormalizeClassicDispelPreviewScope(scope) or nil)
    A3.RefreshDispelSymbolPreview()
    return active
end

function A3.SetDispelSymbolPreviewMoveHandler(handler)
    A3.DispelSymbolPreviewMoveHandler = type(handler) == "function" and handler or nil
    return true
end

ExportPublic("MSUF_SetDispelOverlayPreview", A3.SetDispelOverlayPreview)
ExportPublic("MSUF_RefreshDispelOverlayPreview", A3.RefreshDispelOverlayPreview)
ExportPublic("MSUF_ApplyDispelOverlayPreviewToFrame", A3._ApplyClassicDispelOverlayPreview)
ExportPublic("MSUF_SetDispelSymbolPreview", A3.SetDispelSymbolPreview)
ExportPublic("MSUF_RefreshDispelSymbolPreview", A3.RefreshDispelSymbolPreview)
ExportPublic("MSUF_ApplyDispelSymbolPreviewToFrame", A3._ApplyClassicDispelSymbolPreview)
ExportPublic("MSUF_SetDispelSymbolPreviewMoveHandler", A3.SetDispelSymbolPreviewMoveHandler)

function A3._ClassicMenuPreviewSourceLane(scope, laneKind)

    local unit, cfg
    scope = tostring(scope or "shared"):lower()
    if scope == "party" or scope == "raid" then
        local gf = A3._GroupAPI()
        local frames = gf and gf.frameList
        for i = 1, type(frames) == "table" and #frames or 0 do
            local frame = frames[i]
            local kind = frame and frame._msufGFKind
            if (scope == "party" and kind == "party")
                or (scope == "raid" and (kind == "raid" or kind == "mythicraid")) then
                unit = frame.MSUFUnitKey
                cfg = ResolveGroupFrameConfig(frame, unit)
                if unit and cfg then break end
            end
        end
    else
        unit = scope == "boss" and "boss1" or (scope == "shared" and "player" or scope)
        cfg = A3.ResolveUnitFrameConfig(unit, nil)
    end
    return cfg and cfg.lanes and cfg.lanes[laneKind], unit
end

function A3.UpdateMenuAuraPreview(host, scope, laneKind, width, height)
    if not host or A3._ClassicAuraRuntimeCombatBlocked() then return false, "combat" end
    local source, unit = A3._ClassicMenuPreviewSourceLane(scope, laneKind)
    local preview = host._msufA3ClassicMenuPreviewFrame
    if not (source and source.enabled == true and unit) then
        if preview then HideState(preview) end
        return false, (scope == "party" or scope == "raid") and "no-group-frame" or "not-configured"
    end
    if not preview then
        preview = PixelLayoutRegion(CreateFrame("Frame", nil, host))
        preview:SetAllPoints(host)
        host._msufA3ClassicMenuPreviewFrame = preview
        if host.HookScript then
            host:HookScript("OnHide", function() HideState(preview) end)
        end
    end
    local lane = {}
    for key, value in pairs(source) do lane[key] = value end
    lane.unit, lane.anchor, lane.x, lane.y, lane.layer = unit, "TOPLEFT", 10, -34, 2
    lane.strata, lane.alpha = "AUTO", 1
    local size = math_max(1, tonumber(lane.size) or 24)
    local spacing = math_max(0, tonumber(lane.spacing) or 0)
    local contentWidth = math_max(1, (tonumber(width) or 300) - 20)
    local contentHeight = math_max(1, (tonumber(height) or 120) - 42)
    local maxCols = math_max(1, math_floor((contentWidth + spacing) / math_max(1, size + spacing)))
    local maxRows = math_max(1, math_floor((contentHeight + spacing) / math_max(1, size + spacing)))
    lane.perRow = math_min(math_max(1, tonumber(lane.perRow) or 1), lane.verticalGrowth == true and maxRows or maxCols)
    lane.max = math_min(math_max(0, tonumber(lane.max) or 0), lane.perRow * (lane.verticalGrowth == true and maxCols or maxRows), 20)
    if lane.max <= 0 then HideState(preview); return false, "empty" end
    lane.cols = lane.verticalGrowth == true and math_ceil(lane.max / lane.perRow) or math_min(lane.max, lane.perRow)
    lane.rows = lane.verticalGrowth == true and math_min(lane.max, lane.perRow) or math_ceil(lane.max / lane.perRow)
    lane.width = math_max(1, lane.cols * (lane.buttonWidth or size) + math_max(lane.cols - 1, 0) * spacing)
    lane.height = math_max(1, lane.rows * (lane.buttonHeight or size) + math_max(lane.rows - 1, 0) * spacing)
    ApplyConfig(preview, { enabled = true, unit = unit, lanes = { [laneKind] = lane }, laneOrder = { laneKind } })
    UpdateAuras(preview, "ForceUpdate", unit, nil, true)
    preview:Show()
    return true, "live"
end


end
