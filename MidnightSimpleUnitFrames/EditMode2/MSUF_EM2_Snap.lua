-- ============================================================================
-- MSUF_EM2_Snap.lua — Phase 3: Full 9+9 edge-pair snap + alignment guides
-- For each axis: 3 edges (min, center, max) × 3 edges on target = 9 pairs.
-- Snaps independently per axis. Shows 1px guide lines at snap points.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Snap = {}
EM2.Snap = Snap

local floor = math.floor
local abs = math.abs
local max, min = math.max, math.min
local W8 = "Interface/Buttons/WHITE8X8"

local enabled = false
local THRESH  = 8

function Snap.IsEnabled()    return enabled end
function Snap.SetEnabled(v)  enabled = v and true or false end
function Snap.GetThreshold() return THRESH end
function Snap.SetThreshold(v) THRESH = max(2, min(20, tonumber(v) or 8)) end

-- ── Guide line pool ─────────────────────────────────────────────────────────
local guidePool = {}
local activeGuides = {}
local guideParent

local function GetGuide()
    if not guideParent then
        guideParent = CreateFrame("Frame", "MSUF_EM2_SnapGuides", UIParent)
        guideParent:SetAllPoints(UIParent)
        guideParent:SetFrameStrata("FULLSCREEN")
        guideParent:SetFrameLevel(500)
    end
    local g = table.remove(guidePool)
    if not g then
        g = guideParent:CreateTexture(nil, "OVERLAY")
        g:SetColorTexture(1.00, 0.55, 0.12, 0.50)
    end
    g:Show()
    activeGuides[#activeGuides + 1] = g
    return g
end

function Snap.HideGuides()
    for i = #activeGuides, 1, -1 do
        local g = activeGuides[i]
        g:Hide(); g:ClearAllPoints()
        guidePool[#guidePool + 1] = g
        activeGuides[i] = nil
    end
end

local function ShowVGuide(x)
    local g = GetGuide()
    g:SetSize(1, UIParent:GetHeight())
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, 0)
end

local function ShowHGuide(y)
    local g = GetGuide()
    g:SetSize(UIParent:GetWidth(), 1)
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, y)
end

-- ── Edge computation ────────────────────────────────────────────────────────
-- Returns { left, centerX, right, bottom, centerY, top } from screen coords
local function GetEdges(l, b, w, h)
    return l, l + w * 0.5, l + w, b, b + h * 0.5, b + h
end

-- ── Core snap logic ─────────────────────────────────────────────────────────
-- cx, cy = center of dragged mover (screen space)
-- hw, hh = half width/height of dragged mover
-- dragKey = registry key of dragged element (excluded from targets)
function Snap.Apply(cx, cy, hw, hh, dragKey)
    if not enabled then return cx, cy end

    Snap.HideGuides()

    local movers = EM2.Movers and EM2.Movers.All()
    if not movers then return cx, cy end

    -- Dragged mover edges
    local dL = cx - hw
    local dR = cx + hw
    local dB = cy - hh
    local dT = cy + hh
    local dCX = cx
    local dCY = cy

    local bestDX, bestDistX = nil, THRESH + 1
    local bestDY, bestDistY = nil, THRESH + 1
    local snapEdgeX, snapEdgeY

    -- Also snap to screen center
    local uiW = UIParent:GetWidth() or 1
    local uiH = UIParent:GetHeight() or 1
    local screenCX = uiW * 0.5
    local screenCY = uiH * 0.5

    -- Check screen center
    local dxEdges = { dL, dCX, dR }
    local dyEdges = { dB, dCY, dT }
    for _, de in ipairs(dxEdges) do
        local d = abs(de - screenCX)
        if d < bestDistX then bestDistX = d; bestDX = screenCX - de; snapEdgeX = screenCX end
    end
    for _, de in ipairs(dyEdges) do
        local d = abs(de - screenCY)
        if d < bestDistY then bestDistY = d; bestDY = screenCY - de; snapEdgeY = screenCY end
    end

    -- Check all other movers
    for key, mover in pairs(movers) do
        if key ~= dragKey and mover:IsShown() then
            local tL = mover:GetLeft() or 0
            local tB = mover:GetBottom() or 0
            local tW = mover:GetWidth() or 1
            local tH = mover:GetHeight() or 1
            local tR = tL + tW
            local tT = tB + tH
            local tCX = tL + tW * 0.5
            local tCY = tB + tH * 0.5

            local targetXEdges = { tL, tCX, tR }
            local targetYEdges = { tB, tCY, tT }

            -- 3×3 X edge pairs
            for _, de in ipairs(dxEdges) do
                for _, te in ipairs(targetXEdges) do
                    local d = abs(de - te)
                    if d < bestDistX then
                        bestDistX = d; bestDX = te - de; snapEdgeX = te
                    end
                end
            end

            -- 3×3 Y edge pairs
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

    -- Apply snaps
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
