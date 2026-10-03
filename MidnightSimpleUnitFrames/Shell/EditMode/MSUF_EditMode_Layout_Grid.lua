--- EditMode/MSUF_EditMode_Layout_Grid.lua - Edit Mode grid overlay
--- Midnight-styled background, pooled grid lines, accent-colored crosshair.
--- Zero overhead when hidden (no OnUpdate, no timers).
--- The layout family loads from MSUF_EditMode.xml right after Core, whose
--- Util it reads at load: Grid, Snap, Nudge, then the drag ticker
--- (MSUF_EditMode_Layout.lua).
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local _, MSUF = ...
local ExportPublic = (MSUF or _G.MSUF_NS or {}).ExportPublic

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Grid = {}
EM2.Grid = Grid

local floor = math.floor
local max   = math.max
local min   = math.min
local ThemeColor = (EM2.Util or {}).ThemeColor

local function T()
    local legacy = _G.MSUF_THEME or {}
    local bg = ThemeColor("bg", { legacy.bgR or 0.08, legacy.bgG or 0.09, legacy.bgB or 0.10, legacy.bgA or 0.94 })
    local edge = ThemeColor("borderSoft", { legacy.edgeR or 0.20, legacy.edgeG or 0.30, legacy.edgeB or 0.50, 1 })
    local accent = ThemeColor("accent", { legacy.titleR or 1.00, legacy.titleG or 0.82, legacy.titleB or 0.00, 1 })
    return {
        bgR = bg[1], bgG = bg[2], bgB = bg[3], bgA = bg[4] or 0.94,
        edgeR = edge[1], edgeG = edge[2], edgeB = edge[3],
        titleR = accent[1], titleG = accent[2], titleB = accent[3],
    }
end

--- DB helpers (always live)
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

--- Frame + texture pools
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

local function CreateCenterLine(vertical, thickness, subLevel)
    local tex = PixelLayoutRegion(gridFrame:CreateTexture(nil, "BACKGROUND", nil, subLevel))
    if vertical then
        tex:SetWidth(thickness)
        tex:SetPoint("TOP", UIParent, "TOP", 0, 0)
        tex:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    else
        tex:SetHeight(thickness)
        tex:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
        tex:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
    end
    return tex
end

local function CreateCenterPip(vertical, thickness, length, subLevel)
    local tex = PixelLayoutRegion(gridFrame:CreateTexture(nil, "BACKGROUND", nil, subLevel))
    if vertical then
        tex:SetWidth(thickness)
        tex:SetHeight(length)
    else
        tex:SetHeight(thickness)
        tex:SetWidth(length)
    end
    tex:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    return tex
end

local function EnsureGridFrame()
    if gridFrame then return gridFrame end

    gridFrame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_Grid", UIParent))
    gridFrame:SetFrameStrata("LOW")
    gridFrame:SetFrameLevel(0)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:Hide()
    gridFrame:SetScript("OnSizeChanged", function()
        if gridFrame:IsShown() and RebuildLines then RebuildLines() end
    end)

    --- Background overlay
    bgTex = PixelLayoutRegion(gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8))
    bgTex:SetAllPoints()
    local th = T()
    bgTex:SetColorTexture(th.bgR, th.bgG, th.bgB, GetBgAlpha())

    --- Center crosshair (accent colored, full screen length)
    crossVShadow = CreateCenterLine(true, 3, -6)
    crossV = CreateCenterLine(true, 1, -5)
    crossHShadow = CreateCenterLine(false, 3, -6)
    crossH = CreateCenterLine(false, 1, -5)

    --- Short white pip at dead center
    pipVShadow = CreateCenterPip(true, 3, 24, -5)
    pipV = CreateCenterPip(true, 1, 20, -4)
    pipHShadow = CreateCenterPip(false, 3, 24, -5)
    pipH = CreateCenterPip(false, 1, 20, -4)
    ApplyGridVisibility()

    --- Keep legacy global alive (Style scanner etc.)
    ExportPublic("MSUF_GridFrame", gridFrame)

    return gridFrame
end

--- Grid line rebuild (pooled textures, no GC)
local function GetLine(idx)
    local tex = lines[idx]
    if not tex then
        tex = PixelLayoutRegion(gridFrame:CreateTexture(nil, "BACKGROUND", nil, -5))
        lines[idx] = tex
    end
    return tex
end

local function GetLineShadow(idx)
    local tex = lineShadows[idx]
    if not tex then
        tex = PixelLayoutRegion(gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6))
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

local function DrawGridLine(idx, vertical, pos, lineR, lineG, lineB, lineAlpha, shadowAlpha)
    local shadow = GetLineShadow(idx)
    shadow:ClearAllPoints()
    shadow:SetColorTexture(0, 0, 0, shadowAlpha)

    local tex = GetLine(idx)
    tex:ClearAllPoints()
    tex:SetColorTexture(lineR, lineG, lineB, lineAlpha)

    if vertical then
        shadow:SetWidth(3)
        shadow:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", pos - 1, 0)
        shadow:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", pos - 1, 0)
        tex:SetWidth(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", pos, 0)
        tex:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", pos, 0)
    else
        shadow:SetHeight(3)
        shadow:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -pos + 1)
        shadow:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -pos + 1)
        tex:SetHeight(1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -pos)
        tex:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -pos)
    end

    shadow:Show()
    tex:Show()
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

    local function AddLine(vertical, pos)
        idx = idx + 1
        DrawGridLine(idx, vertical, pos, lineR, lineG, lineB, lineAlpha, shadowAlpha)
    end

    --- Vertical lines from center outward
    local x = cx - step
    while x > 0 do
        AddLine(true, x)
        x = x - step
    end
    x = cx + step
    while x < w do
        AddLine(true, x)
        x = x + step
    end

    --- Horizontal lines from center outward
    local y = cy - step
    while y > 0 do
        AddLine(false, y)
        y = y - step
    end
    y = cy + step
    while y < h do
        AddLine(false, y)
        y = y + step
    end

    lineCount = idx
end

--- Public API
function Grid.Show()
    EnsureGridFrame()
    local th = T()
    bgTex:SetColorTexture(th.bgR, th.bgG, th.bgB, GetBgAlpha())
    RebuildLines()
    gridFrame:Show()
    C_Timer.After(0, function()
        if gridFrame and gridFrame:IsShown() then RebuildLines() end
    end)
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
    if bgTex then
        local th = T()
        bgTex:SetColorTexture(th.bgR, th.bgG, th.bgB, v)
    end
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
