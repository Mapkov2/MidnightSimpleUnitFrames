-- ============================================================================
-- MSUF_EM2_Grid.lua
-- Edit Mode 2 grid overlay.
-- Midnight-styled background, pooled grid lines, accent-colored crosshair.
-- Zero overhead when hidden (no OnUpdate, no timers).
-- ============================================================================
local addonName, ns = ...

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Grid = {}
EM2.Grid = Grid

local floor = math.floor
local max   = math.max
local min   = math.min

-- ---------------------------------------------------------------------------
-- Theme (read from MSUF_THEME, fall back to Midnight defaults)
-- ---------------------------------------------------------------------------
local function T()
    return _G.MSUF_THEME or {
        bgR = 0.08, bgG = 0.09, bgB = 0.10, bgA = 0.94,
        edgeR = 0.20, edgeG = 0.30, edgeB = 0.50,
        titleR = 1.00, titleG = 0.82, titleB = 0.00,
    }
end

-- ---------------------------------------------------------------------------
-- DB helpers (always live)
-- ---------------------------------------------------------------------------
local function GetBgAlpha()
    local db = _G.MSUF_DB
    if db and db.general and type(db.general.editModeBgAlpha) == "number" then
        return db.general.editModeBgAlpha
    end
    return 0.50
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

-- ---------------------------------------------------------------------------
-- Frame + texture pools
-- ---------------------------------------------------------------------------
local gridFrame
local bgTex
local crossV, crossH, pipV, pipH
local lines     = {}
local lineCount = 0

local function EnsureGridFrame()
    if gridFrame then return gridFrame end

    gridFrame = CreateFrame("Frame", "MSUF_EM2_Grid", UIParent)
    gridFrame:SetFrameStrata("BACKGROUND")
    gridFrame:SetFrameLevel(0)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:Hide()

    -- Background overlay
    bgTex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.02, 0.03, 0.04, GetBgAlpha())

    -- Center crosshair (accent colored, full screen length)
    local th = T()
    crossV = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
    crossV:SetColorTexture(th.edgeR, th.edgeG, th.edgeB, 0.35)
    crossV:SetWidth(1)
    crossV:SetPoint("TOP", UIParent, "TOP", 0, 0)
    crossV:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

    crossH = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
    crossH:SetColorTexture(th.edgeR, th.edgeG, th.edgeB, 0.35)
    crossH:SetHeight(1)
    crossH:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    crossH:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)

    -- Short white pip at dead center
    pipV = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
    pipV:SetColorTexture(1, 1, 1, 0.50)
    pipV:SetWidth(1)
    pipV:SetHeight(20)
    pipV:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    pipH = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
    pipH:SetColorTexture(1, 1, 1, 0.50)
    pipH:SetHeight(1)
    pipH:SetWidth(20)
    pipH:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Keep legacy global alive (Style scanner etc.)
    _G.MSUF_GridFrame = gridFrame

    return gridFrame
end

-- ---------------------------------------------------------------------------
-- Grid line rebuild (pooled textures, no GC)
-- ---------------------------------------------------------------------------
local function GetLine(idx)
    local tex = lines[idx]
    if not tex then
        tex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        lines[idx] = tex
    end
    return tex
end

local function RebuildLines()
    if not gridFrame then return end

    local step = max(8, min(64, floor(GetGridStep())))
    local w = UIParent:GetWidth() or 0
    local h = UIParent:GetHeight() or 0
    local th = T()
    local lineAlpha = 0.12

    -- Hide all existing lines
    for i = 1, lineCount do
        lines[i]:Hide()
    end

    local idx = 0
    local cx = floor(w / 2)
    local cy = floor(h / 2)

    -- Vertical lines from center outward
    local x = cx - step
    while x > 0 do
        idx = idx + 1
        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(th.edgeR, th.edgeG, th.edgeB, lineAlpha)
        tex:SetWidth(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, 0)
        tex:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", x, 0)
        tex:Show()
        x = x - step
    end
    x = cx + step
    while x < w do
        idx = idx + 1
        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(th.edgeR, th.edgeG, th.edgeB, lineAlpha)
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
        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(th.edgeR, th.edgeG, th.edgeB, lineAlpha)
        tex:SetHeight(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y)
        tex:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -y)
        tex:Show()
        y = y - step
    end
    y = cy + step
    while y < h do
        idx = idx + 1
        local tex = GetLine(idx)
        tex:ClearAllPoints()
        tex:SetColorTexture(th.edgeR, th.edgeG, th.edgeB, lineAlpha)
        tex:SetHeight(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y)
        tex:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -y)
        tex:Show()
        y = y + step
    end

    lineCount = idx
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function Grid.Show()
    EnsureGridFrame()
    bgTex:SetColorTexture(0.02, 0.03, 0.04, GetBgAlpha())
    RebuildLines()
    gridFrame:Show()
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
end

function Grid.SetGridStep(v)
    v = max(8, min(64, floor(v)))
    SetGridStep(v)
    if gridFrame and gridFrame:IsShown() then RebuildLines() end
end

function Grid.GetBgAlpha()    return GetBgAlpha() end
function Grid.GetGridStep()   return GetGridStep() end
function Grid.Rebuild()       RebuildLines() end
