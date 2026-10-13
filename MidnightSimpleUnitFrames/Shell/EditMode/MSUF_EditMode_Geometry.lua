-- Shared geometry, loaded before Kernel Util and the Edit Mode controller.
-- Policies retain each consumer's historic visibility and scale fallbacks.
local _, MSUF = ...
local Geometry = {}
MSUF.Geometry = Geometry

function Geometry.RoundEven(value)
    return value + (2^52 + 2^51) - (2^52 + 2^51)
end

function Geometry.RoundAway(value)
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

function Geometry.RoundOffset(value)
    return Geometry.RoundAway(tonumber(value) or 0)
end

function Geometry.RoundOptional(value)
    value = tonumber(value)
    if value == nil then return nil end
    return Geometry.RoundAway(value)
end

local function Scales(frame, policy)
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local frameScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if policy == "snap" then
        if uiScale == 0 then uiScale = 1 end
        frameScale = frameScale or uiScale
    elseif policy == "inspector" then
        frameScale = frameScale or uiScale
        if uiScale == 0 then return 1, 1 end
    elseif policy == "edit" then
        frameScale, uiScale = tonumber(frameScale or 1), tonumber(uiScale)
        if not frameScale or frameScale <= 0 then frameScale = 1 end
        if not uiScale or uiScale <= 0 then uiScale = 1 end
    elseif policy == "popup" then
        frameScale = frameScale or 1
        if frameScale <= 0 then frameScale = 1 end
        if uiScale <= 0 then uiScale = 1 end
    else
        frameScale = frameScale or 1
        if frameScale == 0 then frameScale = 1 end
        if uiScale == 0 then uiScale = 1 end
    end
    return frameScale, uiScale
end

function Geometry.ScaleRatio(frame, policy)
    local frameScale, uiScale = Scales(frame, policy)
    local ratio = frameScale / uiScale
    if policy == "popup" and not (ratio > 0) then ratio = 1 end
    return ratio, frameScale, uiScale
end

function Geometry.Rect(frame, policy)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    if policy == "visible" and frame.IsShown and not frame:IsShown() then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local ratio, frameScale, uiScale = Geometry.ScaleRatio(frame, policy)
    if policy == "inspector" then
        return left * ratio, right * ratio, top * ratio, bottom * ratio, (top - bottom) * ratio
    end
    return left * ratio, right * ratio, top * ratio, bottom * ratio, frameScale, uiScale
end

function Geometry.VisibleRect(frame)
    local left, right, top, bottom = Geometry.Rect(frame, "visible")
    if not left then return nil end
    return left, right, top, bottom
end

function Geometry.EditRect(frame)
    return Geometry.Rect(frame, "edit")
end

function Geometry.ExternalRect(frame)
    local left, right, top, bottom = Geometry.Rect(frame, "external")
    if not left then return nil end
    return left, right, top, bottom
end

function Geometry.PopupRect(frame)
    local left, right, top, bottom = Geometry.Rect(frame, "popup")
    if not left then return nil end
    return left, right, top, bottom
end

function Geometry.Edges(frame)
    local left, right, top, bottom = Geometry.Rect(frame, "snap")
    if not left then return nil end
    return left, (left + right) * 0.5, right, bottom, (bottom + top) * 0.5, top
end
