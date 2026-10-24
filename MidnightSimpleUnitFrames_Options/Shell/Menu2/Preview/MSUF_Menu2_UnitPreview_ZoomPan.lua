--- Unit preview zoom and canvas pan helpers.

local MSUF = _G.MSUF
local ZoomPan = MSUF.UFPreviewZoomPan or {}
MSUF.UFPreviewZoomPan = ZoomPan
local H = MSUF.MSUF2.PreviewHelpers
if H and H.InstallZoomPan then
    H.InstallZoomPan(ZoomPan, {
        configureTableOnly = true,
        readoutField = "zoomReadout",
        fitButtonTextPath = { "zoomFitButton", "fs" },
        panPrefix = "_msufPreview",
        hintField = "hint",
        updateHintKey = "UpdateHandleHint",
        defaultReason = "UNIT_PREVIEW_ZOOM",
        stepReason = "UNIT_PREVIEW_ZOOM_STEP",
        themeButton = true,
        buttonTextureKey = "TEX_W8",
        buttonFontField = "fs",
        refresh = function(box, reason, deps)
            local preview = deps.Preview or MSUF.UFPreview
            if preview and type(preview.Refresh) == "function" then preview.Refresh(box, reason) end
        end,
    })
end
