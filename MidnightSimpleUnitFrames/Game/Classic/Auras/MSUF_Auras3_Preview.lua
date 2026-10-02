--- Game/Classic/Auras/MSUF_Auras3_Preview.lua
--- The Menu2 dispel overlay and dispel symbol previews of the Classic aura
--- backend: the preview modes and scopes the menu pages set, the per-frame
--- preview render through the Classic visuals, and the symbol drag handler.
--- Every entry point is a cold path; UNIT_AURA never reaches this file.
---
--- Game/<Flavor>/Auras.xml loads it after the unit-frame aura backend
--- (Requests.lua last). It imports the compiler at load time and installs only
--- when that backend loaded, as Requests.lua's installer call used to.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
local Backend = type(A3) == "table" and A3._ClassicBackend
if not (Backend and Backend.Requests) or Backend.Preview then return end
local Compile, Visuals = A3._ClassicCompile, A3.ClassicVisuals
local Preview = {}

local UF = MSUF.UF
local ExportPublic = MSUF.ExportPublic
local type, tostring, pairs = type, tostring, pairs

local CompileFrameAuraVisual = Compile.CompileFrameAuraVisual
local CombatBlocked = Compile.AuraRuntimeCombatBlocked

local function NormalizePreviewScope(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" or scope == "all" or scope == "global" then return "shared" end
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

local function PreviewApplies(frame, scope, includeGroup)
    if not frame then return false end
    local wanted = NormalizePreviewScope(scope)
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

--- Live unit frames, live group frames and the group preview frames. The group
--- frame modules load after this file, before any preview can be switched on.
local function ForEachPreviewFrame(fn)
    UF.ForEachFrame(fn)
    local gf = MSUF.GF
    gf.ForEachFrame(fn, true)
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

local function ApplyOverlayPreview(frame)
    local active = _G.MSUF_DispelOverlayPreviewMode == true
        and PreviewApplies(frame, _G.MSUF_DispelOverlayPreviewScope, true)
    local visual = active and frame and frame.MSUFSpec and CompileFrameAuraVisual(frame.MSUFSpec) or nil
    active = active and visual and visual.overlayEnabled == true or false
    return Visuals.UpdateDispelOverlayPreview(frame, visual, active)
end

function A3.RefreshDispelOverlayPreview()
    ForEachPreviewFrame(ApplyOverlayPreview)
    return true
end

function A3.SetDispelOverlayPreview(active, scope)
    active = active == true
    if active and CombatBlocked() then active = false end
    ExportPublic("MSUF_DispelOverlayPreviewMode", active)
    ExportPublic("MSUF_DispelOverlayPreviewScope",
        active and NormalizePreviewScope(scope) or nil)
    A3.RefreshDispelOverlayPreview()
    return active
end

local function ApplySymbolPreview(frame)
    local active = _G.MSUF_DispelSymbolPreviewMode == true
        and PreviewApplies(frame, _G.MSUF_DispelSymbolPreviewScope, false)
    local visual = active and frame and frame.MSUFSpec and CompileFrameAuraVisual(frame.MSUFSpec) or nil
    active = active and visual and visual.symbol and visual.symbol.enabled == true or false
    return Visuals.UpdateDispelSymbolPreview(frame, visual, active)
end

function A3.RefreshDispelSymbolPreview()
    ForEachPreviewFrame(ApplySymbolPreview)
    return true
end

function A3.SetDispelSymbolPreview(active, scope)
    active = active == true
    if active and CombatBlocked() then active = false end
    ExportPublic("MSUF_DispelSymbolPreviewMode", active)
    ExportPublic("MSUF_DispelSymbolPreviewScope",
        active and NormalizePreviewScope(scope) or nil)
    A3.RefreshDispelSymbolPreview()
    return active
end

function A3.SetDispelSymbolPreviewMoveHandler(handler)
    A3.DispelSymbolPreviewMoveHandler = type(handler) == "function" and handler or nil
    return true
end

ExportPublic("MSUF_SetDispelOverlayPreview", A3.SetDispelOverlayPreview)
ExportPublic("MSUF_RefreshDispelOverlayPreview", A3.RefreshDispelOverlayPreview)
ExportPublic("MSUF_ApplyDispelOverlayPreviewToFrame", ApplyOverlayPreview)
ExportPublic("MSUF_SetDispelSymbolPreview", A3.SetDispelSymbolPreview)
ExportPublic("MSUF_RefreshDispelSymbolPreview", A3.RefreshDispelSymbolPreview)
ExportPublic("MSUF_ApplyDispelSymbolPreviewToFrame", ApplySymbolPreview)
ExportPublic("MSUF_SetDispelSymbolPreviewMoveHandler", A3.SetDispelSymbolPreviewMoveHandler)

Backend.Preview = Preview
