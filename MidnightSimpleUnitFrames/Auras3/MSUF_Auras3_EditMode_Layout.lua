--- Auras3/EditMode_Layout: shared anchor/grid geometry used by both dragging and preview rendering.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.EditModeModules = A3.EditModeModules or {}
A3.EditModeModules.Layout = function(config)
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_min, math_max, math_ceil = math.min, math.max, math.ceil
local UIParent = _G.UIParent
local Clamp = config.Clamp
local Round = config.Round
local function GetFrame(unit)
    if not unit then return nil end
    local uf = MSUF and MSUF.UF
    return (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
        or (uf and type(uf.GetFrame) == "function" and uf.GetFrame(unit))
        or (uf and uf.frames and uf.frames[unit])
        or _G["MSUF_" .. unit]
end

local function FrameScaleRelativeToUIParent(frame)
    local frameScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    frameScale = tonumber(frameScale) or 1
    uiScale = tonumber(uiScale) or 1
    if frameScale <= 0 then frameScale = 1 end
    if uiScale <= 0 then uiScale = 1 end
    local scale = frameScale / uiScale
    if scale <= 0 then return 1 end
    return scale
end

local function ApplyGroupScaleForFrame(group, frame)
    local scale = FrameScaleRelativeToUIParent(frame)
    if group and group.SetScale and group._msufA3FrameScale ~= scale then
        group:SetScale(scale)
        group._msufA3FrameScale = scale
    end
    return scale
end

local AnchorOffset = _G.MSUF_AuraAnchorOffset

local function AnchorBase(anchor, frame)
    local w = frame and frame.GetWidth and frame:GetWidth() or 0
    local h = frame and frame.GetHeight and frame:GetHeight() or 0
    return AnchorOffset(anchor, w, h)
end



local ButtonAnchor = _G.MSUF_AuraButtonAnchor

local function GrowthParts(growth, rowWrap)
    if growth == "LEFTUP" then return -1, 1, false, "BOTTOMRIGHT" end
    if growth == "LEFTDOWN" then return -1, -1, false, "TOPRIGHT" end
    if growth == "RIGHTUP" then return 1, 1, false, "BOTTOMLEFT" end
    if growth == "RIGHTDOWN" then return 1, -1, false, "TOPLEFT" end
    if growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    if rowWrap ~= "UP" then rowWrap = "DOWN" end
    local xSign = growth == "LEFT" and -1 or 1
    local ySign = rowWrap == "UP" and 1 or -1
    if growth == "UP" or growth == "DOWN" then
        xSign = 1
        ySign = growth == "UP" and 1 or -1
        return xSign, ySign, true, ButtonAnchor(xSign, ySign)
    end
    return xSign, ySign, false, ButtonAnchor(xSign, ySign)
end

local function GridDimensions(maxN, perRow, size, spacing, vertical)
    local count = math_max(Round(maxN), 1)
    local per = math_max(Round(perRow), 1)
    local cols, rows
    if vertical == true then
        rows = count
        cols = 1
    else
        cols = math_min(count, per)
        rows = math_ceil(count / per)
    end
    size = Clamp(size, 26, 1, 128)
    spacing = Clamp(spacing, 2, 0, 64)
    return math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        cols,
        rows
end

local function IconGridCoord(index, perRow, vertical)
    local per = math_max(Round(perRow), 1)
    local idx = index - 1
    if vertical == true then
        return 0, idx
    end
    local col = idx % per
    return col, (idx - col) / per
end

--- Inward offset from the lane's initial corner for the shared style padding,
--- mirroring the runtime container's SetFlowLayoutPadding inset.
local PaddingInset = _G.MSUF_AuraPaddingInset

--- Shared icon style for a previewed lane: the compiled runtime style when the
--- lane metrics carry one, otherwise the scope-resolved preview style. Bar-only
--- lanes pass nil downstream, matching the runtime's chrome-off rendering.
local function LaneIconStyle(metrics, _, kind)
    if metrics and metrics.iconStyle then return metrics.iconStyle end
    if type(A3.IconStylePreviewForKind) == "function" then
        return A3.IconStylePreviewForKind((metrics and metrics.appearanceKind) or kind)
    end
    return nil
end

local function PositionPreviewGroup(group, frame, anchor, x, y, laneW, laneH)
    if not (group and frame) then return end
    local baseX, baseY = AnchorBase(anchor, frame)
    local localX, localY = AnchorOffset(anchor, laneW, laneH)
    group:ClearAllPoints()
    group:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", baseX + (tonumber(x) or 0) - localX, baseY + (tonumber(y) or 0) - localY)
end

local function FallbackMetrics(cfg)
    local xSign, ySign, vertical, initialAnchor = GrowthParts(cfg and cfg.growth, cfg and cfg.rowWrap)
    local laneW, laneH = GridDimensions(cfg and cfg.max, cfg and cfg.perRow, cfg and cfg.size, cfg and cfg.spacing, vertical)
    local padding = Clamp(cfg and cfg.padding, 0, 0, 16)
    return {
        enabled = cfg and cfg.show == true,
        num = cfg and Round(cfg.max) or 0,
        size = cfg and cfg.size or 26,
        iconZoom = cfg and cfg.iconZoom or 100,
        iconShape = cfg and cfg.iconShape or "RECTANGLE",
        spacing = cfg and cfg.spacing or 2,
        step = ((cfg and cfg.size) or 26) + ((cfg and cfg.spacing) or 2),
        perRow = cfg and cfg.perRow or 12,
        padding = padding,
        width = laneW + 2 * padding,
        height = laneH + 2 * padding,
        growthX = xSign,
        growthY = ySign,
        verticalGrowth = vertical == true,
        initialAnchor = initialAnchor,
        x = cfg and cfg.x or 0,
        y = cfg and cfg.y or 0,
        anchor = cfg and cfg.anchor or "TOPLEFT",
    }
end


return {
    GetFrame = GetFrame,
    FrameScaleRelativeToUIParent = FrameScaleRelativeToUIParent,
    ApplyGroupScaleForFrame = ApplyGroupScaleForFrame,
    IconGridCoord = IconGridCoord,
    PaddingInset = PaddingInset,
    LaneIconStyle = LaneIconStyle,
    PositionPreviewGroup = PositionPreviewGroup,
    FallbackMetrics = FallbackMetrics,
}
end
