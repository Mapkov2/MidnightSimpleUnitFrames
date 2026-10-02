--- EditMode/MSUF_EditMode_Layout_Snap.lua - Edit Mode snapping and alignment guides
--- Full 9+9 edge-pair snap: for each axis, 3 edges (min, center, max) against
--- 3 edges on the target = 9 pairs. Snaps independently per axis and shows
--- 1px guide lines at snap points.
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local floor = math.floor
local max   = math.max
local min   = math.min
local abs   = math.abs
local ThemeColor = (EM2.Util or {}).ThemeColor

local Snap = {}
EM2.Snap = Snap

local enabled = false
local THRESH  = 8

--- Snap persists per profile via general.editModeSnapEnabled; the session
--- local only covers reads before SavedVariables exist.
local SnapGeneral = _G.MSUF_GetGeneralDB

function Snap.IsEnabled()
    local g = SnapGeneral()
    if g and g.editModeSnapEnabled ~= nil then return g.editModeSnapEnabled == true end
    return enabled
end
function Snap.SetEnabled(v)
    enabled = v and true or false
    local g = SnapGeneral()
    if g then g.editModeSnapEnabled = enabled end
end
function Snap.GetThreshold() return THRESH end
function Snap.SetThreshold(v) THRESH = max(2, min(20, tonumber(v) or 8)) end

--- --- Guide line pool ---
local guidePool = {}
local activeGuides = {}
local fadingGuides = {}
local guideParent
local guideFadeFrame

--- Snap.Apply runs every drag frame: the guide colour reuses one fallback
--- table and the edge lists below are scratch arrays refilled per call.
local guideAccentFallback = { 1.00, 0.82, 0.00, 1 }
local snapDragX, snapDragY, snapTargetX, snapTargetY = {}, {}, {}, {}

local function GuideAccent()
    local legacy = _G.MSUF_THEME
    guideAccentFallback[1] = legacy and legacy.titleR or 1.00
    guideAccentFallback[2] = legacy and legacy.titleG or 0.82
    guideAccentFallback[3] = legacy and legacy.titleB or 0.00
    return ThemeColor("accent", guideAccentFallback)
end

local function GetGuide()
    if not guideParent then
        guideParent = PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_SnapGuides", UIParent))
        guideParent:SetAllPoints(UIParent)
        guideParent:SetFrameStrata("FULLSCREEN")
        guideParent:SetFrameLevel(500)
    end
    local g = table.remove(guidePool)
    if not g then
        g = PixelLayoutRegion(guideParent:CreateTexture(nil, "OVERLAY"))
    end
    local accent = GuideAccent()
    g:SetColorTexture(accent[1], accent[2], accent[3], 0.72)
    g:SetAlpha(1)
    g._msufGuideFade = nil
    g:Show()
    activeGuides[#activeGuides + 1] = g
    return g
end

local function StartGuideFade()
    if guideFadeFrame then
        guideFadeFrame:Show()
        return
    end
    guideFadeFrame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_SnapGuideFade", UIParent))
    guideFadeFrame:SetScript("OnUpdate", function(self, elapsed)
        local alive = false
        for i = #fadingGuides, 1, -1 do
            local g = fadingGuides[i]
            if not g then
                table.remove(fadingGuides, i)
            else
                g._msufGuideFade = (g._msufGuideFade or 0.12) - (elapsed or 0)
                local a = max(0, min(1, g._msufGuideFade / 0.12))
                g:SetAlpha(a)
                if a <= 0 then
                    g:Hide()
                    g:ClearAllPoints()
                    g:SetAlpha(1)
                    g._msufGuideFade = nil
                    guidePool[#guidePool + 1] = g
                    table.remove(fadingGuides, i)
                else
                    alive = true
                end
            end
        end
        if not alive then self:Hide() end
    end)
end

local function ReleaseGuide(g, fade)
    if not g then return end
    if fade then
        g._msufGuideFade = 0.12
        fadingGuides[#fadingGuides + 1] = g
        StartGuideFade()
    else
        g:Hide()
        g:ClearAllPoints()
        g:SetAlpha(1)
        g._msufGuideFade = nil
        guidePool[#guidePool + 1] = g
    end
end

local function ClearActiveGuides(fade)
    for i = #activeGuides, 1, -1 do
        local g = activeGuides[i]
        ReleaseGuide(g, fade == true)
        activeGuides[i] = nil
    end
end

function Snap.HideGuides(immediate)
    ClearActiveGuides(immediate ~= true)
    if immediate then
        for i = #fadingGuides, 1, -1 do
            local guide = fadingGuides[i]
            fadingGuides[i] = nil
            ReleaseGuide(guide, false)
        end
        if guideFadeFrame then guideFadeFrame:Hide() end
    end
end

local function ShowVGuide(x)
    x = floor((tonumber(x) or 0) + 0.5)
    x = max(0, min(UIParent:GetWidth() or x, x))
    local g = GetGuide()
    g:ClearAllPoints()
    g:SetSize(1, UIParent:GetHeight())
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, 0)
end

local function ShowHGuide(y)
    y = floor((tonumber(y) or 0) + 0.5)
    y = max(0, min(UIParent:GetHeight() or y, y))
    local g = GetGuide()
    g:ClearAllPoints()
    g:SetSize(UIParent:GetWidth(), 1)
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, y)
end

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
--- The drag ticker measures movers with the same edges.
Snap.GetFrameEdgesUI = GetFrameEdgesUI

--- --- Core snap logic ---
--- cx, cy = center of dragged mover (screen space)
--- hw, hh = half width/height of dragged mover
--- dragKey = registry key of dragged element (excluded from targets)
function Snap.Apply(cx, cy, hw, hh, dragKey)
    if not Snap.IsEnabled() then return cx, cy end

    ClearActiveGuides(false)

    local movers = EM2.Movers and EM2.Movers.All()
    if not movers then return cx, cy end

    --- Dragged mover edges
    local dL = cx - hw
    local dR = cx + hw
    local dB = cy - hh
    local dT = cy + hh
    local dCX = cx
    local dCY = cy

    local bestDX, bestDistX = nil, THRESH + 1
    local bestDY, bestDistY = nil, THRESH + 1
    local snapEdgeX, snapEdgeY

    --- Also snap to screen center
    local uiW = UIParent:GetWidth() or 1
    local uiH = UIParent:GetHeight() or 1
    local screenCX = uiW * 0.5
    local screenCY = uiH * 0.5

    --- Check screen center
    local dxEdges, dyEdges = snapDragX, snapDragY
    dxEdges[1], dxEdges[2], dxEdges[3] = dL, dCX, dR
    dyEdges[1], dyEdges[2], dyEdges[3] = dB, dCY, dT
    for _, de in ipairs(dxEdges) do
        local d = abs(de - screenCX)
        if d < bestDistX then bestDistX = d; bestDX = screenCX - de; snapEdgeX = screenCX end
    end
    for _, de in ipairs(dyEdges) do
        local d = abs(de - screenCY)
        if d < bestDistY then bestDistY = d; bestDY = screenCY - de; snapEdgeY = screenCY end
    end

    --- Check all other movers
    for key, mover in pairs(movers) do
        if key ~= dragKey and mover:IsShown() then
            local tL, tCX, tR, tB, tCY, tT = GetFrameEdgesUI(mover)

            --- 3?3 X edge pairs
            if tL then
                local targetXEdges, targetYEdges = snapTargetX, snapTargetY
                targetXEdges[1], targetXEdges[2], targetXEdges[3] = tL, tCX, tR
                targetYEdges[1], targetYEdges[2], targetYEdges[3] = tB, tCY, tT
                for _, de in ipairs(dxEdges) do
                    for _, te in ipairs(targetXEdges) do
                        local d = abs(de - te)
                        if d < bestDistX then
                            bestDistX = d; bestDX = te - de; snapEdgeX = te
                        end
                    end
                end

                --- 3?3 Y edge pairs
                for _, de in ipairs(dyEdges) do
                    for _, te in ipairs(targetYEdges) do
                        local d = abs(de - te)
                        if d < bestDistY then
                            bestDistY = d; bestDY = te - de; snapEdgeY = te
                        end
                    end
                end
            end
        end
    end

    --- Apply snaps
    local snappedX = cx
    local snappedY = cy
    if bestDX and bestDistX <= THRESH then
        snappedX = cx + bestDX
        if snapEdgeX then ShowVGuide(snapEdgeX) end
    end
    if bestDY and bestDistY <= THRESH then
        snappedY = cy + bestDY
        if snapEdgeY then ShowHGuide(snapEdgeY) end
    end

    return snappedX, snappedY
end
