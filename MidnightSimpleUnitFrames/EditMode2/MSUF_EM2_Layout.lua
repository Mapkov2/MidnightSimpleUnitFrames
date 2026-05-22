-- MSUF_EM2_Layout.lua — Grid + Snap + Anchors + Nudge + Ticker (consolidated)

-- MSUF_EM2_Grid.lua

-- MSUF_EM2_Grid.lua
-- Edit Mode 2 grid overlay.
-- Midnight-styled background, pooled grid lines, accent-colored crosshair.
-- Zero overhead when hidden (no OnUpdate, no timers).
local addonName, ns = ...

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Grid = {}
EM2.Grid = Grid

local floor = math.floor
local max   = math.max
local min   = math.min

local function RefreshUFPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "EM2_LAYOUT") end
end
local function ApplySettingsForKeySafe(key)
    local fn = _G.MSUF_ApplySettingsForKey
    if type(fn) == "function" then fn(key); return true end
    return false
end
local function ApplyAllSettingsSafe()
    local fn = _G.MSUF_ApplyAllSettings
    if type(fn) == "function" then fn(); return true end
    return false
end

local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then return true end
    return (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end

local function BlockConfigCombatLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if IsConfigCombatLocked() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        end
        return true
    end
    return false
end

-- Theme (read from MSUF_THEME, fall back to Midnight defaults)
local function T()
    return _G.MSUF_THEME or {
        bgR = 0.08, bgG = 0.09, bgB = 0.10, bgA = 0.94,
        edgeR = 0.20, edgeG = 0.30, edgeB = 0.50,
        titleR = 1.00, titleG = 0.82, titleB = 0.00,
    }
end

-- DB helpers (always live)
local function GetBgAlpha()
    local db = _G.MSUF_DB
    if db and db.general and type(db.general.editModeBgAlpha) == "number" then
        return db.general.editModeBgAlpha
    end
    return 0.75
end

local function SetBgAlpha(v)
    local db = _G.MSUF_DB
    if db then
        db.general = db.general or {}
        db.general.editModeBgAlpha = v
    end
end

local function GetGridStep()
    local db = _G.MSUF_DB
    if db and db.general and type(db.general.editModeGridStep) == "number" then
        return db.general.editModeGridStep
    end
    return 32
end

local function SetGridStep(v)
    local db = _G.MSUF_DB
    if db then
        db.general = db.general or {}
        db.general.editModeGridStep = v
    end
end

local function GetGridEnabled()
    local db = _G.MSUF_DB
    if db and db.general and db.general.editModeGridEnabled == false then
        return false
    end
    return true
end

local function SetGridEnabled(v)
    local db = _G.MSUF_DB
    if db then
        db.general = db.general or {}
        db.general.editModeGridEnabled = v and true or false
    end
end

-- Frame + texture pools
local gridFrame
local bgTex
local crossV, crossH, pipV, pipH
local crossVShadow, crossHShadow, pipVShadow, pipHShadow
local lines     = {}
local lineShadows = {}
local lineCount = 0
local RebuildLines

local function GetCanvasSize()
    local w = UIParent and UIParent.GetWidth and (UIParent:GetWidth() or 0) or 0
    local h = UIParent and UIParent.GetHeight and (UIParent:GetHeight() or 0) or 0

    if w <= 0 and type(GetScreenWidth) == "function" then
        w = GetScreenWidth() or 0
    end
    if h <= 0 and type(GetScreenHeight) == "function" then
        h = GetScreenHeight() or 0
    end

    return w, h
end

local function GetGridStyle()
    local th = T()
    local bg = max(0, min(1, GetBgAlpha()))
    local boost = max(0, min(1, (0.60 - bg) / 0.60))
    local r = (th.edgeR or 0.20) + (0.72 - (th.edgeR or 0.20)) * boost
    local g = (th.edgeG or 0.30) + (0.88 - (th.edgeG or 0.30)) * boost
    local b = (th.edgeB or 0.50) + (1.00 - (th.edgeB or 0.50)) * boost
    local lineAlpha = 0.16 + 0.64 * boost
    local crossAlpha = 0.40 + 0.35 * boost
    local pipAlpha = 0.55 + 0.30 * boost
    local shadowAlpha = 0.10 + 0.42 * boost
    return r, g, b, lineAlpha, crossAlpha, pipAlpha, shadowAlpha
end

local function ApplyGridVisibility()
    local r, g, b, _, crossAlpha, pipAlpha, shadowAlpha = GetGridStyle()
    if crossVShadow then crossVShadow:SetColorTexture(0, 0, 0, shadowAlpha) end
    if crossHShadow then crossHShadow:SetColorTexture(0, 0, 0, shadowAlpha) end
    if pipVShadow then pipVShadow:SetColorTexture(0, 0, 0, shadowAlpha + 0.10) end
    if pipHShadow then pipHShadow:SetColorTexture(0, 0, 0, shadowAlpha + 0.10) end
    if crossV then crossV:SetColorTexture(r, g, b, crossAlpha) end
    if crossH then crossH:SetColorTexture(r, g, b, crossAlpha) end
    if pipV then pipV:SetColorTexture(1, 1, 1, pipAlpha) end
    if pipH then pipH:SetColorTexture(1, 1, 1, pipAlpha) end
end

local function SetCenterGridShown(shown)
    local method = shown and "Show" or "Hide"
    if crossVShadow then crossVShadow[method](crossVShadow) end
    if crossHShadow then crossHShadow[method](crossHShadow) end
    if pipVShadow then pipVShadow[method](pipVShadow) end
    if pipHShadow then pipHShadow[method](pipHShadow) end
    if crossV then crossV[method](crossV) end
    if crossH then crossH[method](crossH) end
    if pipV then pipV[method](pipV) end
    if pipH then pipH[method](pipH) end
end

local function EnsureGridFrame()
    if gridFrame then return gridFrame end

    gridFrame = CreateFrame("Frame", "MSUF_EM2_Grid", UIParent)
    gridFrame:SetFrameStrata("LOW")
    gridFrame:SetFrameLevel(0)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:Hide()
    gridFrame:SetScript("OnSizeChanged", function()
        if gridFrame:IsShown() and RebuildLines then RebuildLines() end
    end)

    -- Background overlay
    bgTex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.02, 0.03, 0.04, GetBgAlpha())

    -- Center crosshair (accent colored, full screen length)
    crossVShadow = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
    crossVShadow:SetWidth(3)
    crossVShadow:SetPoint("TOP", UIParent, "TOP", 0, 0)
    crossVShadow:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

    crossV = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
    crossV:SetWidth(1)
    crossV:SetPoint("TOP", UIParent, "TOP", 0, 0)
    crossV:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

    crossHShadow = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
    crossHShadow:SetHeight(3)
    crossHShadow:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    crossHShadow:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)

    crossH = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
    crossH:SetHeight(1)
    crossH:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    crossH:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)

    -- Short white pip at dead center
    pipVShadow = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
    pipVShadow:SetWidth(3)
    pipVShadow:SetHeight(24)
    pipVShadow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    pipV = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
    pipV:SetWidth(1)
    pipV:SetHeight(20)
    pipV:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    pipHShadow = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
    pipHShadow:SetHeight(3)
    pipHShadow:SetWidth(24)
    pipHShadow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    pipH = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
    pipH:SetHeight(1)
    pipH:SetWidth(20)
    pipH:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ApplyGridVisibility()

    -- Keep legacy global alive (Style scanner etc.)
    _G.MSUF_GridFrame = gridFrame

    return gridFrame
end

-- Grid line rebuild (pooled textures, no GC)
local function GetLine(idx)
    local tex = lines[idx]
    if not tex then
        tex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
        lines[idx] = tex
    end
    return tex
end

local function GetLineShadow(idx)
    local tex = lineShadows[idx]
    if not tex then
        tex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        lineShadows[idx] = tex
    end
    return tex
end

local function HideGridLines()
    for i = 1, lineCount do
        if lines[i] then lines[i]:Hide() end
        if lineShadows[i] then lineShadows[i]:Hide() end
    end
end

function RebuildLines()
    if not gridFrame then return end

    local step = max(8, min(64, floor(GetGridStep())))
    local w, h = GetCanvasSize()
    local lineR, lineG, lineB, lineAlpha, _, _, shadowAlpha = GetGridStyle()

    if not GetGridEnabled() then
        HideGridLines()
        SetCenterGridShown(false)
        lineCount = 0
        return
    end

    ApplyGridVisibility()
    SetCenterGridShown(true)
    HideGridLines()

    if w <= 0 or h <= 0 then
        lineCount = 0
        return
    end

    local idx = 0
    local cx = floor(w / 2)
    local cy = floor(h / 2)

    -- Vertical lines from center outward
    local x = cx - step
    while x > 0 do
        idx = idx + 1
        local shadow = GetLineShadow(idx)
        shadow:ClearAllPoints()
        shadow:SetColorTexture(0, 0, 0, shadowAlpha)
        shadow:SetWidth(3)
        shadow:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x - 1, 0)
        shadow:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", x - 1, 0)
        shadow:Show()

        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(lineR, lineG, lineB, lineAlpha)
        tex:SetWidth(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, 0)
        tex:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", x, 0)
        tex:Show()
        x = x - step
    end
    x = cx + step
    while x < w do
        idx = idx + 1
        local shadow = GetLineShadow(idx)
        shadow:ClearAllPoints()
        shadow:SetColorTexture(0, 0, 0, shadowAlpha)
        shadow:SetWidth(3)
        shadow:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x - 1, 0)
        shadow:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", x - 1, 0)
        shadow:Show()

        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(lineR, lineG, lineB, lineAlpha)
        tex:SetWidth(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, 0)
        tex:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", x, 0)
        tex:Show()
        x = x + step
    end

    -- Horizontal lines from center outward
    local y = cy - step
    while y > 0 do
        idx = idx + 1
        local shadow = GetLineShadow(idx)
        shadow:ClearAllPoints()
        shadow:SetColorTexture(0, 0, 0, shadowAlpha)
        shadow:SetHeight(3)
        shadow:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y + 1)
        shadow:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -y + 1)
        shadow:Show()

        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(lineR, lineG, lineB, lineAlpha)
        tex:SetHeight(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y)
        tex:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -y)
        tex:Show()
        y = y - step
    end
    y = cy + step
    while y < h do
        idx = idx + 1
        local shadow = GetLineShadow(idx)
        shadow:ClearAllPoints()
        shadow:SetColorTexture(0, 0, 0, shadowAlpha)
        shadow:SetHeight(3)
        shadow:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y + 1)
        shadow:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -y + 1)
        shadow:Show()

        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(lineR, lineG, lineB, lineAlpha)
        tex:SetHeight(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y)
        tex:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -y)
        tex:Show()
        y = y + step
    end

    lineCount = idx
end

-- Public API
function Grid.Show()
    EnsureGridFrame()
    bgTex:SetColorTexture(0.02, 0.03, 0.04, GetBgAlpha())
    RebuildLines()
    gridFrame:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if gridFrame and gridFrame:IsShown() then RebuildLines() end
        end)
    end
end

function Grid.Hide()
    if gridFrame then gridFrame:Hide() end
end

function Grid.IsShown()
    return gridFrame and gridFrame:IsShown() or false
end

function Grid.SetBgAlpha(v)
    v = max(0.05, min(0.85, v))
    SetBgAlpha(v)
    if bgTex then bgTex:SetColorTexture(0.02, 0.03, 0.04, v) end
    ApplyGridVisibility()
    if gridFrame and gridFrame:IsShown() then RebuildLines() end
end

function Grid.SetGridStep(v)
    v = max(8, min(64, floor(v)))
    SetGridStep(v)
    if gridFrame and gridFrame:IsShown() then RebuildLines() end
end

function Grid.GetBgAlpha()    return GetBgAlpha() end
function Grid.GetGridStep()   return GetGridStep() end
function Grid.GetEnabled()    return GetGridEnabled() end
function Grid.SetEnabled(v)
    SetGridEnabled(v)
    if gridFrame then RebuildLines() end
end
function Grid.ToggleEnabled()
    local enabled = not GetGridEnabled()
    Grid.SetEnabled(enabled)
    return enabled
end
function Grid.Rebuild()       RebuildLines() end

-- MSUF_EM2_Snap.lua

-- MSUF_EM2_Snap.lua — Phase 3: Full 9+9 edge-pair snap + alignment guides
-- For each axis: 3 edges (min, center, max) × 3 edges on target = 9 pairs.
-- Snaps independently per axis. Shows 1px guide lines at snap points.
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

-- MSUF_EM2_Anchors.lua

-- MSUF_EM2_Anchors.lua — Phase 4: Anchor chain system
-- When element A moves, all elements anchored to A follow with same delta.
-- Chains propagate recursively (A→B→C: moving A moves B and C).
-- Width/height binding: child.width can track parent.width.
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Anchors = {}
EM2.Anchors = Anchors

local floor = math.floor

-- chains[childKey] = { parent = parentKey, bindWidth = bool, bindHeight = bool }
local chains = {}

-- ── Registration ────────────────────────────────────────────────────────────
function Anchors.Link(childKey, parentKey, opts)
    if not childKey or not parentKey then return end
    opts = opts or {}
    chains[childKey] = {
        parent     = parentKey,
        bindWidth  = opts.bindWidth or false,
        bindHeight = opts.bindHeight or false,
    }
end

function Anchors.Unlink(childKey)
    chains[childKey] = nil
end

function Anchors.GetParent(childKey)
    local c = chains[childKey]
    return c and c.parent
end

-- ── Query: all direct children of a parent ──────────────────────────────────
function Anchors.GetChildren(parentKey)
    local result = {}
    for child, info in pairs(chains) do
        if info.parent == parentKey then
            result[#result + 1] = child
        end
    end
    return result
end

-- ── Recursive children (full chain) ─────────────────────────────────────────
function Anchors.GetAllDescendants(parentKey, visited)
    visited = visited or {}
    if visited[parentKey] then return {} end
    visited[parentKey] = true
    local result = {}
    for child, info in pairs(chains) do
        if info.parent == parentKey and not visited[child] then
            result[#result + 1] = child
            local sub = Anchors.GetAllDescendants(child, visited)
            for _, s in ipairs(sub) do result[#result + 1] = s end
        end
    end
    return result
end

-- ── Propagate movement delta to all descendants ─────────────────────────────
-- Called after dragging parentKey by (dx, dy) in screen space.
-- Moves child movers and their underlying frames.
function Anchors.PropagateMove(parentKey, dx, dy)
    if dx == 0 and dy == 0 then return end
    local children = Anchors.GetAllDescendants(parentKey)
    if #children == 0 then return end

    local movers = EM2.Movers and EM2.Movers.All()
    if not movers then return end

    for _, childKey in ipairs(children) do
        local mover = movers[childKey]
        if mover and mover:IsShown() then
            local l = (mover:GetLeft() or 0) + dx
            local b = (mover:GetBottom() or 0) + dy
            mover:ClearAllPoints()
            mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)

            -- Move underlying frame
            local cfg = EM2.Registry and EM2.Registry.Get(childKey)
            if cfg then
                local frame = cfg.getFrame and cfg.getFrame()
                if frame then
                    local fS = frame:GetEffectiveScale()
                    local uiS = UIParent:GetEffectiveScale()
                    local ratio = uiS / fS
                    pcall(function()
                        frame:ClearAllPoints()
                        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
                    end)
                end

                -- Save to DB
                if cfg.getConf then
                    local conf = cfg.getConf()
                    if conf then
                        local w = mover:GetWidth() or 50
                        local h = mover:GetHeight() or 20
                        local uiW = UIParent:GetWidth() or 1
                        local uiH = UIParent:GetHeight() or 1
                        conf.offsetX = floor((l + w * 0.5) - uiW * 0.5 + 0.5)
                        conf.offsetY = floor((b + h * 0.5) - uiH * 0.5 + 0.5)
                    end
                end
            end
        end
    end
end

-- ── Width/height binding sync ───────────────────────────────────────────────
-- Call after any resize to propagate to bound children.
function Anchors.SyncDimensions(parentKey)
    local parentMover = EM2.Movers and EM2.Movers.Get(parentKey)
    if not parentMover then return end
    local pw = parentMover:GetWidth() or 0
    local ph = parentMover:GetHeight() or 0

    for childKey, info in pairs(chains) do
        if info.parent == parentKey and (info.bindWidth or info.bindHeight) then
            local cfg = EM2.Registry and EM2.Registry.Get(childKey)
            if cfg and cfg.getConf then
                local conf = cfg.getConf()
                if conf then
                    if info.bindWidth  then conf.width  = floor(pw + 0.5) end
                    if info.bindHeight then conf.height = floor(ph + 0.5) end
                end
            end
        end
    end
end

-- ── Clear all chains (on exit edit mode) ────────────────────────────────────
function Anchors.Clear()
    for k in pairs(chains) do chains[k] = nil end
end

-- MSUF_EM2_Nudge.lua

-- MSUF_EM2_Nudge.lua
-- Arrow key nudge system. Override bindings for UP/DOWN/LEFT/RIGHT.
-- Shift=5px, Ctrl=10px, Alt=grid step. Targets open popup or current unit.
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Nudge = {}
EM2.Nudge = Nudge

local floor = math.floor
local owner

local function GetPreviewNudgeTarget()
    local target = _G.MSUF_EM2_ActivePreviewNudgeTarget
    if type(target) ~= "table" or type(target.Nudge) ~= "function" then return nil end
    if type(target.IsActive) == "function" and not target:IsActive() then return nil end
    local frame = target.frame
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    return target
end

function _G.MSUF_EM2_SetPreviewNudgeTarget(target)
    if target == nil or type(target) == "table" then
        _G.MSUF_EM2_ActivePreviewNudgeTarget = target
    end
end

local function GetStep()
    local step = 1
    if IsAltKeyDown and IsAltKeyDown() then
        step = (EM2.Grid and EM2.Grid.GetGridStep()) or 20
    elseif IsControlKeyDown and IsControlKeyDown() then
        step = 10
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        step = 5
    end
    return step
end

local function GetCastbarOffsetKeys(unit)
    if not unit then return nil, nil end
    if unit == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY" end
    local fn = _G.MSUF_GetCastbarPrefix
    if type(fn) ~= "function" then return nil, nil end
    local prefix = fn(unit)
    if not prefix or prefix == "" then return nil, nil end
    return prefix .. "OffsetX", prefix .. "OffsetY"
end

local function NudgeTarget(dx, dy)
    if not EM2.State or not EM2.State.IsActive() then return end
    if BlockConfigCombatLocked() then return end
    local db = _G.MSUF_DB
    if not db then return end
    local s = GetStep()
    local ndx, ndy = dx * s, dy * s

    -- Priority 0: selected custom preview frame.
    -- Some previews are not normal EM2 movers but still write normal position
    -- keys. They register here on click/drag so arrow keys move what the user
    -- just selected.
    local previewTarget = GetPreviewNudgeTarget()
    if previewTarget then
        previewTarget:Nudge(ndx, ndy)
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return
    end

    -- Priority 1: open castbar popup
    if EM2.CastPopup and EM2.CastPopup.IsOpen() then
        db.general = db.general or {}
        local g = db.general
        local castPF = _G.MSUF_EM2_CastPopup
        local unit = castPF and castPF.unit
        if unit then
            local xKey, yKey = GetCastbarOffsetKeys(unit)
            if xKey and yKey then
                if _G.MSUF_EM_UndoBeforeChange then
                    _G.MSUF_EM_UndoBeforeChange("castbar", unit, true)
                end
                g[xKey] = floor(((tonumber(g[xKey]) or 0) + ndx) + 0.5)
                g[yKey] = floor(((tonumber(g[yKey]) or 0) + ndy) + 0.5)
                -- Arrow-key movement must use the same unit-aware apply path as
                -- popup fields: it reanchors target/focus/player bars, updates
                -- boss previews, refreshes visuals, and syncs the position popup.
                -- A plain visual refresh leaves the live target castbar at the
                -- previous anchor until the user clicks it again.
                if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
                    _G.MSUF_ApplyCastbarUnitAndSync(unit)
                elseif _G.MSUF_UpdateCastbarVisuals then
                    _G.MSUF_UpdateCastbarVisuals()
                    EM2.CastPopup.Sync()
                end
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        RefreshUFPreview("EM2_CASTBAR_NUDGE", unit)
        return
    end

    -- Priority 2: aura sub-group (individual buff/debuff/private)
    local auraGroup = _G.MSUF_EM2_ActiveAuraGroup
    local auraPopupOpen = EM2.AuraPopup and EM2.AuraPopup.IsOpen()
    local a2PopupOpen = false
    do local ap = _G.MSUF_Auras2PositionPopup; a2PopupOpen = ap and ap.IsShown and ap:IsShown() or false end
    if auraGroup and (auraPopupOpen or a2PopupOpen) then
        local unitKey = _G.MSUF_EM2_ActiveAuraUnit
        if not unitKey then
            local auraPF = _G.MSUF_EM2_AuraPopup
            unitKey = auraPF and auraPF.unit
        end
        if unitKey then
            local a2 = db.auras2
            if a2 then
                a2.perUnit = a2.perUnit or {}
                if _G.MSUF_EM_UndoBeforeChange then
                    _G.MSUF_EM_UndoBeforeChange("aura", unitKey, true)
                end
                local isBoss = type(unitKey) == "string" and unitKey:match("^boss%d+$")
                local applyKeys
                if isBoss and a2.shared and a2.shared.bossEditTogether ~= false then
                    applyKeys = { "boss1","boss2","boss3","boss4","boss5" }
                else
                    applyKeys = { unitKey }
                end
                local GROUP_KEYS = {
                    buff    = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
                    debuff  = { "debuffGroupOffsetX", "debuffGroupOffsetY" },
                    private = { "privateOffsetX",     "privateOffsetY"     },
                }
                local pair = GROUP_KEYS[auraGroup]
                if pair then
                    local kx, ky = pair[1], pair[2]
                    local shared = a2.shared or {}
                    for _, k in ipairs(applyKeys) do
                        a2.perUnit[k] = a2.perUnit[k] or {}
                        local uc = a2.perUnit[k]
                        uc.layout = uc.layout or {}
                        uc.overrideLayout = true
                        local lay = uc.layout
                        local cx = (lay[kx] ~= nil) and lay[kx] or (shared[kx] or 0)
                        local cy = (lay[ky] ~= nil) and lay[ky] or (shared[ky] or 0)
                        lay[kx] = floor(((tonumber(cx) or 0) + ndx) + 0.5)
                        lay[ky] = floor(((tonumber(cy) or 0) + ndy) + 0.5)
                    end
                end
                if type(_G.MSUF_Auras2_RefreshUnit) == "function" then
                    for _, k in ipairs(applyKeys) do _G.MSUF_Auras2_RefreshUnit(k) end
                elseif _G.MSUF_Auras2_RefreshAll then
                    _G.MSUF_Auras2_RefreshAll()
                end
                if auraPopupOpen and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
                local syncFn = _G.MSUF_SyncAuras2PositionPopup
                if type(syncFn) == "function" then syncFn(unitKey) end
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return
    end

    -- Priority 3: current unit frame
    local key = EM2.State.GetUnitKey() or "player"
    if (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid")
        and type(_G.MSUF_GF_EM2_NudgePreview) == "function"
        and _G.MSUF_GF_EM2_NudgePreview(key, ndx, ndy)
    then
        return
    end

    local conf = db[key]
    if not conf then return end
    if _G.MSUF_EM_UndoBeforeChange then
        _G.MSUF_EM_UndoBeforeChange("unit", key, true)
    end
    conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + ndx) + 0.5)
    conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + ndy) + 0.5)
    if not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
    if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_UNIT_NUDGE", key)
end

function Nudge.Enable()
    if not owner then
        owner = CreateFrame("Frame", "MSUF_EM2_NudgeOwner", UIParent)
        owner:Hide()
        owner.__msufPendingClear = false
        owner:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_ENABLED" and self.__msufPendingClear then
                self.__msufPendingClear = false
                if ClearOverrideBindings then ClearOverrideBindings(self) end
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end)

        for _, dir in ipairs({"UP","DOWN","LEFT","RIGHT"}) do
            local btnName = "MSUF_EM2_Nudge" .. dir
            local btn = CreateFrame("Button", btnName, UIParent, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", function()
                if dir == "UP"    then NudgeTarget(0, 1)
                elseif dir == "DOWN"  then NudgeTarget(0, -1)
                elseif dir == "LEFT"  then NudgeTarget(-1, 0)
                elseif dir == "RIGHT" then NudgeTarget(1, 0) end
            end)
        end
    end

    if IsConfigCombatLocked() then
        owner.__msufPendingClear = false
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, dir in ipairs({"UP","DOWN","LEFT","RIGHT"}) do
        SetOverrideBindingClick(owner, false, dir, "MSUF_EM2_Nudge" .. dir)
    end
end

function Nudge.Disable()
    if not owner then return end
    if IsConfigCombatLocked() then
        owner.__msufPendingClear = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(owner)
end

-- Legacy global
function _G.MSUF_EnableArrowKeyNudge(enable)
    if enable then Nudge.Enable() else Nudge.Disable() end
end

-- MSUF_EM2_Ticker.lua

-- MSUF_EM2_Ticker.lua — v5 CENTER-native
-- During drag: computes DB offset from cursor, then positions bar with the
-- EXACT same SetPoint("CENTER", anchor, "CENTER", ...) that PositionUnitFrame
-- uses. Zero TOPLEFT. Zero conversion error. One positioning code path.
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Ticker = {}
EM2.Ticker = Ticker

local round = function(n) return n + (2^52 + 2^51) - (2^52 + 2^51) end
local abs   = math.abs
local max, min = math.max, math.min
local format = string.format

local ECV_ANCHORS = {
    player       = { "RIGHT", "LEFT",  -20,   0 },
    target       = { "LEFT",  "RIGHT",  20,   0 },
    focus        = { "TOP",   "LEFT",    0,   0 },
    targettarget = { "TOP",   "RIGHT",   0, -40 },
    focustarget  = { "TOP",   "RIGHT",   0,  40 },
}

local function PointXY(fr, p)
    if not fr or not p then return nil, nil end
    if p == "CENTER" then return fr:GetCenter() end
    local l, r, t, b = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
    if not (l and r and t and b) then return nil, nil end
    local cx, cy = (l + r) * 0.5, (t + b) * 0.5
    if p == "TOPLEFT" then return l, t end
    if p == "TOP" then return cx, t end
    if p == "TOPRIGHT" then return r, t end
    if p == "LEFT" then return l, cy end
    if p == "RIGHT" then return r, cy end
    if p == "BOTTOMLEFT" then return l, b end
    if p == "BOTTOM" then return cx, b end
    if p == "BOTTOMRIGHT" then return r, b end
    return fr:GetCenter()
end

local function ResolveAnchor(key, conf)
    local anchorFn = _G.MSUF_GetAnchorFrame
    local anchor = (type(anchorFn) == "function" and anchorFn()) or UIParent
    if not conf then return anchor end
    local cn = conf.anchorFrameName
    if type(cn) == "string" and cn ~= "" then
        local ecvFn = _G.MSUF_GetEffectiveCooldownFrame
        local cf = (type(ecvFn) == "function" and cn == "EssentialCooldownViewer") and ecvFn(cn) or _G[cn]
        if cf and cf ~= UIParent and cf ~= WorldFrame then return cf end
    end
    local atv = conf.anchorToUnitframe
    if type(atv) == "string" and atv ~= "" and atv ~= "GLOBAL" and atv ~= "FREE" and atv ~= "global" then
        local uf = _G.MSUF_UnitFrames or _G.UnitFrames
        local rel = uf and uf[atv] or _G["MSUF_" .. atv]
        if rel and rel ~= UIParent and rel ~= WorldFrame then return rel end
    end
    return anchor
end

local tickerFrame
local activeDrag
local idleSyncAcc = 0

local function OnUpdate(self, elapsed)
    if activeDrag then
        local d = activeDrag
        local sc = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx = mx / sc; my = my / sc

        -- Mover center = cursor + offset
        local rawCX = mx + d.offX
        local rawCY = my + d.offY

        -- Snap
        local snapCX, snapCY = rawCX, rawCY
        if EM2.Snap and EM2.Snap.IsEnabled() then
            snapCX, snapCY = EM2.Snap.Apply(rawCX, rawCY, d.halfW, d.halfH, d.key)
        end

        -- Clamp
        snapCX = max(d.halfW, min(d.screenW - d.halfW, snapCX))
        snapCY = max(d.halfH, min(d.screenH - d.halfH, snapCY))

        -- Position mover (TOPLEFT UIParent — mover only)
        d.mover:ClearAllPoints()
        d.mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            snapCX - d.halfW,
            snapCY + d.halfH - d.screenH)

        -- Coord display
        if d.mover._coordFS then
            d.mover._coordFS:SetText(format("%.0f, %.0f",
                round(snapCX - d.screenW * 0.5),
                round(snapCY - d.screenH * 0.5)))
        end

        -- ═══════════════════════════════════════════════════════════════
        -- Position bar with CENTER — same code path as PositionUnitFrame.
        -- Group Frames use a stricter UIParent-center path so mouse release
        -- matches the exact preview landing spot with no final snap drift.
        -- ═══════════════════════════════════════════════════════════════

        local bar = d.bar
        if bar and not IsConfigCombatLocked() then
            local anchor = d.anchor
            local conf = d.conf

            if d.isGroupFrame then
                local bw = bar:GetWidth() or 0
                local bh = bar:GetHeight() or 0
                if conf.positionMode == "TOPLEFT_V2" then
                    conf.offsetX = round(snapCX - d.screenW * 0.5 - bw * 0.5)
                    conf.offsetY = round(snapCY - d.screenH * 0.5 + bh * 0.5)
                    pcall(function()
                        bar._msufDragActive = false
                        bar:ClearAllPoints()
                        bar:SetPoint("TOPLEFT", UIParent, "CENTER", conf.offsetX, conf.offsetY)
                    end)
                else
                    conf.offsetX = round(snapCX - d.screenW * 0.5)
                    conf.offsetY = round(snapCY - d.screenH * 0.5)
                    pcall(function()
                        bar._msufDragActive = false
                        bar:ClearAllPoints()
                        bar:SetPoint("CENTER", UIParent, "CENTER", conf.offsetX, conf.offsetY)
                    end)
                end
                bar._msufDragActive = true
            else
                -- Compute where bar center IS in screen pixels after hypothetical move
                -- snapCX/snapCY are in UIParent coords.
                -- Bar center in screen pixels = snapCX * uiScale
                -- We need: offset = (barCenter * barScale - anchorCenter * anchorScale) / anchorScale
                -- Since we WANT barCenter at snapCX (UIParent coords), and UIParent coords = screen / uiScale:
                -- barCenter_local = snapCX * (uiScale / barScale)
                -- But simpler: just write offset then SetPoint with CENTER.

                local ax, ay = anchor:GetCenter()
                if ax and ay then
                    local as = anchor:GetEffectiveScale() or 1
                    local fs = bar:GetEffectiveScale() or 1
                    if as == 0 then as = 1 end; if fs == 0 then fs = 1 end

                    -- Desired bar center in absolute screen pixels
                    local barScreenCX = snapCX * sc  -- sc = UIParent:GetEffectiveScale()
                    local barScreenCY = snapCY * sc
                    -- Anchor center in absolute screen pixels
                    local ancScreenCX = ax * as
                    local ancScreenCY = ay * as
                    -- Offset in anchor's coord space
                    local offX = (barScreenCX - ancScreenCX) / as
                    local offY = (barScreenCY - ancScreenCY) / as

                    -- Boss spacing adjustment (applied to whichever axis the layout uses)
                    if d.bossAdjX then offX = offX - d.bossAdjX end
                    if d.bossAdjY then offY = offY - d.bossAdjY end

                    conf.offsetX = round(offX)
                    conf.offsetY = round(offY)

                    -- Check ECV path
                    local db = _G.MSUF_DB
                    local _g = db and db.general
                    local ecvFn = _G.MSUF_GetEffectiveCooldownFrame
                    local ecv = (type(ecvFn) == "function" and ecvFn("EssentialCooldownViewer"))
                        or _G["EssentialCooldownViewer"]
                    local ecvRule = d.ecvRule

                    if _g and _g.anchorToCooldown and ecv and anchor == ecv and ecvRule then
                        -- ECV path: PositionUnitFrame uses point-to-point
                        -- We wrote center-to-center offset above, need to convert for ECV
                        local point, relPoint, baseX, extraY = ecvRule[1], ecvRule[2], ecvRule[3] or 0, ecvRule[4] or 0
                        -- For ECV: gapY = offsetY, x = baseX + offsetX
                        -- PositionUnitFrame: MSUF_ApplyPoint(f, point, ecv, relPoint, baseX + offsetX, offsetY + extraY)
                        -- So we need to recompute offsetX/offsetY for ECV path
                        local ax2, ay2 = PointXY(ecv, relPoint)
                        -- Desired bar point position
                        local fx2, fy2 = PointXY(bar, point)
                        -- But bar hasn't moved yet... use target position instead
                        -- Actually, just temporarily position with CENTER, read PointXY, then fix
                        pcall(function()
                            bar._msufDragActive = false
                            bar:ClearAllPoints()
                            bar:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
                        end)
                        bar._msufDragActive = true
                        -- Now read the ECV offsets
                        fx2, fy2 = PointXY(bar, point)
                        if ax2 and ay2 and fx2 and fy2 then
                            conf.offsetX = round((fx2 * fs - ax2 * as) / as - baseX)
                            conf.offsetY = round((fy2 * fs - ay2 * as) / as - extraY)
                        end
                        pcall(function()
                            bar:ClearAllPoints()
                            bar:SetPoint(point, ecv, relPoint, baseX + conf.offsetX, conf.offsetY + extraY)
                        end)
                    else
                        -- Normal path: CENTER-to-CENTER (same as PositionUnitFrame line 2429)
                        pcall(function()
                            bar._msufDragActive = false
                            bar:ClearAllPoints()
                            bar:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
                        end)
                        bar._msufDragActive = true
                    end
                end
            end
        end

        if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    else
        idleSyncAcc = idleSyncAcc + elapsed
        if idleSyncAcc >= 0.2 then
            idleSyncAcc = 0
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            if EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
        end
    end
end

function Ticker.BeginDrag(mover, key, cfg)
    local bar = cfg.getFrame and cfg.getFrame()
    if bar then bar._msufDragActive = true end

    local conf = cfg.getConf and cfg.getConf()

    local sc = UIParent:GetEffectiveScale()
    local curX, curY = GetCursorPosition()
    curX = curX / sc; curY = curY / sc

    local mL = mover:GetLeft() or 0; local mR = mover:GetRight() or 0
    local mT = mover:GetTop() or 0; local mB = mover:GetBottom() or 0
    local mCX = (mL + mR) * 0.5
    local mCY = (mT + mB) * 0.5

    local anchor = ResolveAnchor(key, conf)

    local bossAdjX, bossAdjY
    if bar and conf and key and key:sub(1,4) == "boss" and bar.unit then
        local gbi = _G.MSUF_GetBossIndexFromToken
        local idx = (type(gbi) == "function" and gbi(bar.unit)) or 1
        local step = idx - 1
        local spacing = conf.spacing or -36
        local mode = conf.bossLayoutMode
        if mode == "HORIZONTAL_RIGHT" then
            bossAdjX = step * -spacing
        elseif mode == "HORIZONTAL_LEFT" then
            bossAdjX = step * spacing
        elseif mode == "VERTICAL_UP" then
            bossAdjY = step * -spacing
        else
            -- VERTICAL_DOWN (default) + any legacy/unknown value
            bossAdjY = step * spacing
        end
    end

    activeDrag = {
        mover        = mover,
        key          = key,
        cfg          = cfg,
        bar          = bar,
        conf         = conf,
        anchor       = anchor,
        ecvRule      = ECV_ANCHORS[key],
        offX         = mCX - curX,
        offY         = mCY - curY,
        startCX      = mCX,
        startCY      = mCY,
        halfW        = (mR - mL) * 0.5,
        halfH        = (mT - mB) * 0.5,
        screenW      = UIParent:GetWidth(),
        screenH      = UIParent:GetHeight(),
        bossAdjX     = bossAdjX,
        bossAdjY     = bossAdjY,
        isGroupFrame = (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid") or (bar and bar._msufIsGroupFrame == true) or false,
    }
end

function Ticker.EndDrag()
    if not activeDrag then return false end
    local d = activeDrag
    activeDrag = nil

    if d.bar then d.bar._msufDragActive = false end
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

    local mover = d.mover
    local mL = mover:GetLeft() or 0; local mR = mover:GetRight() or 0
    local mT = mover:GetTop() or 0; local mB = mover:GetBottom() or 0
    local cx = (mL + mR) * 0.5; local cy = (mT + mB) * 0.5
    local moved = abs(cx - d.startCX) > 0.5 or abs(cy - d.startCY) > 0.5

    if moved then
        if type(MSUF_DB) == "table" then
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general.hasMovedFramesInEditMode = true
        end
        if type(_G.MSUF_EditState) == "table" then
            _G.MSUF_EditState.hasMovedFramesInEditMode = true
        end
        local menu = (type(ns) == "table" and ns.MSUF2) or _G.MSUF2
        if menu and menu.activeKey == "home" and menu.InvalidatePage and menu.SelectPage then
            local function RefreshHomeDashboard()
                if menu.frame and menu.frame.IsShown and menu.frame:IsShown() then
                    menu.InvalidatePage("home")
                    menu.SelectPage("home")
                end
            end
            if C_Timer and C_Timer.After then C_Timer.After(0.08, RefreshHomeDashboard) else RefreshHomeDashboard() end
        end
        if d.isGroupFrame and d.conf then
            d.conf.offsetX = round(cx - d.screenW * 0.5)
            d.conf.offsetY = round(cy - d.screenH * 0.5)
            if d.bar and not IsConfigCombatLocked() then
                pcall(function()
                    d.bar._msufDragActive = false
                    d.bar:ClearAllPoints()
                    d.bar:SetPoint("CENTER", UIParent, "CENTER", d.conf.offsetX, d.conf.offsetY)
                end)
                d.bar._msufDragActive = true
            end
        end
        -- Offsets already written by OnUpdate. Just finalize pipeline.
        ApplySettingsForKeySafe(d.key)
        C_Timer.After(0.06, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
        if _G.MSUF_SyncUnitPositionPopup then _G.MSUF_SyncUnitPositionPopup() end
        if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
        RefreshUFPreview("EM2_UNIT_DRAG_END", d.key)
    end

    return moved
end

function Ticker.IsDragging() return activeDrag ~= nil end

function Ticker.Start()
    if not tickerFrame then
        tickerFrame = CreateFrame("Frame", "MSUF_EM2_TickerFrame", UIParent)
        tickerFrame:Hide()
    end
    idleSyncAcc = 0; activeDrag = nil
    tickerFrame:SetScript("OnUpdate", OnUpdate)
    tickerFrame:Show()
end

function Ticker.Stop()
    activeDrag = nil
    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", nil)
        tickerFrame:Hide()
    end
end
