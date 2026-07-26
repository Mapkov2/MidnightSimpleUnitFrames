--- Group frame preview zoom/pan helpers.

local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Specs = M.GroupPreviewSpecs or {}
local ZoomPan = M.GroupPreviewZoomPan or {}
M.GroupPreviewZoomPan = ZoomPan
local H = M.PreviewHelpers or {}
if H.InstallZoomPan then
    H.InstallZoomPan(ZoomPan, {
        minZoom = Specs.ZOOM_MIN or 0.35,
        maxZoom = Specs.ZOOM_MAX or 4.0,
        steps = Specs.ZOOM_STEPS,
        readoutField = "_zoomReadout",
        fitButtonTextPath = { "_zoomFitButton", "_fs" },
        translateFitText = true,
        panMode = "topLeft",
        panPrefix = "_msufGFPreview",
        hintField = "_hint",
        updateHintKey = "UpdateHint",
        defaultReason = "GROUP_PREVIEW_ZOOM",
        stepReason = "GROUP_PREVIEW_ZOOM_STEP",
        themeButton = true,
        buttonTextureKey = "WHITE8X8",
        buttonFontField = "_fs",
    })
end
