-- Frozen pre-extraction formulas; changes need an explicit position-behavior decision.
local Legacy = {}
local function RoundOffset(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end
Legacy.RoundOffset = RoundOffset
local function FrameRectToUI(frame)
  if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
    return nil
  end
  if frame.IsShown and not frame:IsShown() then return nil end
  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (l and r and t and b) then return nil end
  local fS = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local uiS = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if not fS or fS == 0 then fS = 1 end
  if not uiS or uiS == 0 then uiS = 1 end
  local ratio = fS / uiS
  return l * ratio, r * ratio, t * ratio, b * ratio
end
Legacy.VisibleRect = FrameRectToUI
local function FrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
    if not frameScale or frameScale == 0 then frameScale = 1 end
    if not uiScale or uiScale == 0 then uiScale = 1 end
    local ratio = frameScale / uiScale
    return left * ratio, right * ratio, top * ratio, bottom * ratio
end
Legacy.ExternalRect = FrameRectToUI
local function GetFrameEdgesUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
        return nil
    end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local uiScale = UIParent:GetEffectiveScale() or 1
    if uiScale == 0 then uiScale = 1 end
    local frameScale = frame.GetEffectiveScale and (frame:GetEffectiveScale() or uiScale) or uiScale
    local ratio = frameScale / uiScale
    l, r, t, b = l * ratio, r * ratio, t * ratio, b * ratio
    return l, (l + r) * 0.5, r, b, (b + t) * 0.5, t
end
Legacy.Edges = GetFrameEdgesUI
local function FrameScaleToUIParent(frame)
    local frameScale = frame and frame.GetEffectiveScale and (frame:GetEffectiveScale() or 1) or 1
    local uiScale = UIParent and UIParent.GetEffectiveScale and (UIParent:GetEffectiveScale() or 1) or 1
    if frameScale <= 0 then frameScale = 1 end
    if uiScale <= 0 then uiScale = 1 end
    local ratio = frameScale / uiScale
    return ratio > 0 and ratio or 1
end
local function FrameRectToUIParent(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local ratio = FrameScaleToUIParent(frame)
    return l * ratio, r * ratio, t * ratio, b * ratio
end
Legacy.PopupRect = FrameRectToUIParent
local function Round(value)
    value = tonumber(value)
    if not value then return nil end
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end
Legacy.RoundOptional = Round
function Legacy.RoundEven(n)
    return n + (2^52 + 2^51) - (2^52 + 2^51)
end
function Legacy.InspectorRect(frame)
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or uiScale
    local ratio = uiScale ~= 0 and frameScale / uiScale or 1
    return left * ratio, right * ratio, top * ratio, bottom * ratio, (top - bottom) * ratio
end
local Util = {}
local function EditFrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local frameScale = frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale()) or 1
    local uiScale = UIParent and UIParent.GetEffectiveScale and tonumber(UIParent:GetEffectiveScale()) or 1
    if not frameScale or frameScale <= 0 then frameScale = 1 end
    if not uiScale or uiScale <= 0 then uiScale = 1 end
    local ratio = frameScale / uiScale
    return left * ratio, right * ratio, top * ratio, bottom * ratio, frameScale, uiScale
end

local function EditScreenCenter()
    local left, right, top, bottom = EditFrameRectToUI(UIParent)
    if left then return (left + right) * 0.5, (bottom + top) * 0.5 end
    return ((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0) * 0.5,
        ((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0) * 0.5
end

local EditRound = RoundOffset

local function EditHorizontalPosition(left, right, centerX)
    if right <= centerX then return right - centerX end
    if left >= centerX then return left - centerX end
    return 0
end

function Util.FramePositionValues(frame)
    local left, right, top, bottom = EditFrameRectToUI(frame)
    if not left then return nil end
    local centerX, centerY = EditScreenCenter()
    return EditRound(EditHorizontalPosition(left, right, centerX)), EditRound(top - centerY),
        EditRound(right - left), EditRound(top - bottom)
end

-- Match the nudge offset limit; the geometry conversion can amplify a typed
-- visual delta on scaled frames, so bound both the input and changed offset.
local function EditPositionNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge or value >= math.huge then return nil end
    return value
end

local function EditPositionClamp(value)
    return math.max(-4096, math.min(4096, value))
end

function Util.TranslateFramePosition(frame, currentOffsetX, currentOffsetY, displayX, displayY)
    local savedX = EditPositionNumber(currentOffsetX) or 0
    local savedY = EditPositionNumber(currentOffsetY) or 0
    local requestedX = EditPositionNumber(displayX)
    local requestedY = EditPositionNumber(displayY)
    local left, right, top, _, frameScale, uiScale = EditFrameRectToUI(frame)
    if not left then return savedX, savedY, false end
    local centerX, centerY = EditScreenCenter()
    local currentX, currentY = EditHorizontalPosition(left, right, centerX), top - centerY
    local scaleRatio = uiScale / frameScale
    local nextX, nextY = savedX, savedY
    --- The edit boxes show rounded geometry. Treat that same rounded value as
    --- unchanged so editing width/height or another field cannot introduce a
    --- sub-pixel position drift. After a resize, the rounded reference edge
    --- changes and the old field value deliberately restores it.
    if requestedX ~= nil and requestedX ~= EditRound(currentX) then
        requestedX = EditPositionClamp(requestedX)
        local currentEdgeX
        if requestedX < 0 then
            currentEdgeX = right - centerX
        elseif requestedX > 0 then
            currentEdgeX = left - centerX
        elseif right <= centerX then
            currentEdgeX = right - centerX
        elseif left >= centerX then
            currentEdgeX = left - centerX
        end
        if currentEdgeX ~= nil then
            nextX = EditPositionClamp(EditRound(savedX + (requestedX - currentEdgeX) * scaleRatio))
        end
    end
    if requestedY ~= nil and requestedY ~= EditRound(currentY) then
        requestedY = EditPositionClamp(requestedY)
        nextY = EditPositionClamp(EditRound(savedY + (requestedY - currentY) * scaleRatio))
    end
    return nextX, nextY, nextX ~= savedX or nextY ~= savedY
end

Legacy.EditRect = EditFrameRectToUI
Legacy.Util = Util
return Legacy
