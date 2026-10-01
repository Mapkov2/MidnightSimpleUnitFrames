-- InstallClassicAuraPreview: isolated ownership, bound once during addon initialization.
local _, MSUF = ...
MSUF.InstallClassicAuraPreview = function(dependencies)
local A3 = dependencies.A3
local CompileFrameAuraVisual = dependencies.CompileFrameAuraVisual
local ExportPublic = dependencies.ExportPublic
local UF = dependencies.UF
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
end
