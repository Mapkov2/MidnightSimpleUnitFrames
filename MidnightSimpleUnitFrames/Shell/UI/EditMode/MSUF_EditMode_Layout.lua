--- EditMode/MSUF_EditMode_Layout.lua - Edit Mode layout, snap, and anchor helpers

--- MSUF_EM2_Grid.lua

--- MSUF_EM2_Grid.lua
--- Edit Mode 2 grid overlay.
--- Midnight-styled background, pooled grid lines, accent-colored crosshair.
--- Zero overhead when hidden (no OnUpdate, no timers).
local _, MSUFRoot = ...
MSUFRoot = MSUFRoot or _G.MSUF_NS or {}
local ExportPublic = MSUFRoot.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function InstallEditLayoutUI(...)
local addonName, MSUF = ...

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Grid = {}
EM2.Grid = Grid

local floor = math.floor
local max   = math.max
local min   = math.min
local abs   = math.abs
local U     = EM2.Util or {}
local round = U.Round

local RefreshUFPreview       = U.RefreshUFPreview
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local ApplyAllSettingsSafe   = U.ApplyAllSettingsSafe
local IsConfigCombatLocked   = U.IsConfigCombatLocked
local BlockConfigCombatLocked = U.BlockConfigCombatLocked
local ThemeColor             = U.ThemeColor

local function ReportEditModeBoundaryError(err)
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if type(handler) == "function" then pcall(handler, err) end
end

local function InvokeEditModeBoundary(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r1, r2 = pcall(fn, ...)
    if not ok then ReportEditModeBoundaryError(r1); return false, r1 end
    return true, r1, r2
end

local function NotifyGuidedEditModeMoved(key)
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    if menu and type(menu.NotifyGuidedEditModeMoved) == "function" then
        return menu.NotifyGuidedEditModeMoved(key)
    end
    local tour = MSUF and MSUF.GuidedTour6 or _G.MSUF_GuidedTour6
    if tour and type(tour.MarkEditModePlacementComplete) == "function" then
        return tour:MarkEditModePlacementComplete(key)
    end
    return false
end

local function GroupGeometryMask(gf)
    return (gf and (gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)) or nil
end

local function RequestGroupGeometryApply(kind, reason)
    if not kind then return false end
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local apply = (menu and menu.ApplyService) or _G.MSUF_Menu2_ApplyService
    if not (apply and type(apply.RequestGroup) == "function") then return false end
    apply.RequestGroup(kind, "geometry", reason or "EM2_GROUP_GEOMETRY")
    if type(apply.Flush) == "function" then apply.Flush() end
    return true
end

local function RefreshGroupGeometryScoped(kind)
    if not kind then return false end
    if RequestGroupGeometryApply(kind, "EM2_LAYOUT_GROUP_GEOMETRY") then
        return true
    end
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshGeometry) == "function" then
        gf.RefreshGeometry(kind)
        return true
    end
    if type(_G.MSUF_GF_RefreshGeometry) == "function" then
        _G.MSUF_GF_RefreshGeometry(kind)
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then
            _G.MSUF_GF_RefreshUnitBindings(kind)
        end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then
            _G.MSUF_GF_RefreshVisuals(kind, GroupGeometryMask(gf))
        end
        return true
    end
    if gf and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, GroupGeometryMask(gf))
        return true
    end
    if type(_G.MSUF_GF_RefreshVisuals) == "function" then
        _G.MSUF_GF_RefreshVisuals(kind)
        return true
    end
    if type(_G.MSUF_GF_RefreshAll) == "function" then
        _G.MSUF_GF_RefreshAll()
        return true
    end
    if type(_G.MSUF_GF_Refresh) == "function" then
        _G.MSUF_GF_Refresh()
        return true
    end
    return false
end

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
    local tex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, subLevel)
    if vertical then
        tex:SetWidth(thickness); tex:SetPoint("TOP", UIParent, "TOP", 0, 0); tex:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    else
        tex:SetHeight(thickness); tex:SetPoint("LEFT", UIParent, "LEFT", 0, 0); tex:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
    end
    return tex
end

local function CreateCenterPip(vertical, thickness, length, subLevel)
    local tex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, subLevel)
    if vertical then
        tex:SetWidth(thickness); tex:SetHeight(length)
    else
        tex:SetHeight(thickness); tex:SetWidth(length)
    end
    tex:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    return tex
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

    --- Background overlay
    bgTex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
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

--- MSUF_EM2_Snap.lua

--- MSUF_EM2_Snap.lua ? Phase 3: Full 9+9 edge-pair snap + alignment guides
--- For each axis: 3 edges (min, center, max) ? 3 edges on target = 9 pairs.
--- Snaps independently per axis. Shows 1px guide lines at snap points.

local Snap = {}
EM2.Snap = Snap

local W8 = "Interface/Buttons/WHITE8X8"

local enabled = false
local THRESH  = 8

--- Snap persists per profile via general.editModeSnapEnabled; the session
--- local only covers reads before SavedVariables exist.
local function SnapGeneral()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

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
    end
    local th = T()
    g:SetColorTexture(th.titleR, th.titleG, th.titleB, 0.72)
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
    guideFadeFrame = CreateFrame("Frame", "MSUF_EM2_SnapGuideFade", UIParent)
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

    --- Check all other movers
    for key, mover in pairs(movers) do
        if key ~= dragKey and mover:IsShown() then
            local tL, tCX, tR, tB, tCY, tT = GetFrameEdgesUI(mover)

            --- 3?3 X edge pairs
            if tL then
                local targetXEdges = { tL, tCX, tR }
                local targetYEdges = { tB, tCY, tT }
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

--- MSUF_EM2_Anchors.lua

--- MSUF_EM2_Anchors.lua ? Phase 4: Anchor chain system
--- When element A moves, all elements anchored to A follow with same delta.
--- Chains propagate recursively (A?B?C: moving A moves B and C).
--- Width/height binding: child.width can track parent.width.
local Anchors = {}
EM2.Anchors = Anchors

--- chains[childKey] = { parent = parentKey, bindWidth = bool, bindHeight = bool }
local chains = {}

--- --- Registration ---
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

--- --- Query: all direct children of a parent ---
function Anchors.GetChildren(parentKey)
    local result = {}
    for child, info in pairs(chains) do
        if info.parent == parentKey then
            result[#result + 1] = child
        end
    end
    return result
end

--- --- Recursive children (full chain) ---
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

--- --- Propagate movement delta to all descendants ---
--- Called after dragging parentKey by (dx, dy) in screen space.
--- Moves child movers and their underlying frames.
function Anchors.PropagateMove(parentKey, dx, dy)
    if (IsConfigCombatLocked and IsConfigCombatLocked())
        or (InCombatLockdown and InCombatLockdown()) then return false end
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

            --- Move underlying frame
            local cfg = EM2.Registry and EM2.Registry.Get(childKey)
            if cfg then
                local frame = cfg.getFrame and cfg.getFrame()
                if frame then
                    local fS = frame:GetEffectiveScale()
                    local uiS = UIParent:GetEffectiveScale()
                    local ratio = uiS / fS
                    frame:ClearAllPoints()
                    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
                end

                --- Save to DB
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

--- --- Width/height binding sync ---
--- Call after any resize to propagate to bound children.
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

--- --- Clear all chains (on exit edit mode) ---
function Anchors.Clear()
    for k in pairs(chains) do chains[k] = nil end
end

local Nudge = {}
EM2.Nudge = Nudge

local owner

local function GetPreviewNudgeTarget()
    local target = _G.MSUF_EM2_ActivePreviewNudgeTarget
    if type(target) ~= "table" or type(target.Nudge) ~= "function" then return nil end
    if type(target.IsActive) == "function" and not target:IsActive() then return nil end
    local frame = target.frame
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    return target
end

local function MSUF_EM2_SetPreviewNudgeTarget(target)
    if target == nil or type(target) == "table" then
        ExportPublic("MSUF_EM2_ActivePreviewNudgeTarget", target)
    end
end
ExportPublic("MSUF_EM2_SetPreviewNudgeTarget", MSUF_EM2_SetPreviewNudgeTarget)

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

local CASTBAR_NUDGE_UNITS = {
    castbar_player = "player",
    castbar_target = "target",
    castbar_focus  = "focus",
    castbar_boss   = "boss",
}

local CASTBAR_NUDGE_DEFAULTS = {
    player = { 0, 5 },
    target = { 65, -15 },
    focus  = { 65, -15 },
    boss   = { 0, 0 },
}

local function IsFiniteNudgeNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function RoundNudgeOffset(value)
    if type(round) == "function" then return round(value) end
    return value >= 0 and floor(value + 0.5) or -floor(-value + 0.5)
end

local function NudgeCastbarDefaultOffsets(unit)
    local defaults = _G.MSUF_GetCastbarDefaultOffsets
    if type(defaults) == "function" then
        local x, y = defaults(unit)
        x, y = tonumber(x), tonumber(y)
        if IsFiniteNudgeNumber(x) and IsFiniteNudgeNumber(y) then return x, y end
        return nil, nil
    end
    local fallback = CASTBAR_NUDGE_DEFAULTS[unit]
    return fallback and fallback[1] or nil, fallback and fallback[2] or nil
end

local function ReadCastbarOffset(general, key, fallbackKey, defaultValue)
    local raw = general[key]
    if raw == nil and fallbackKey then raw = general[fallbackKey] end
    if raw == nil then raw = defaultValue end
    local value = tonumber(raw)
    if not IsFiniteNudgeNumber(value) then return nil end
    return value
end

local function CallCastbarNudgeSync(fn, ...)
    if type(fn) ~= "function" then return true end
    return InvokeEditModeBoundary(fn, ...)
end

local function SyncCastbarNudge(unit)
    local ok = CallCastbarNudgeSync(_G.MSUF_SyncCastbarPositionPopup, unit)
    if type(_G.MSUF_SyncCastbarPositionPopup) ~= "function" and EM2.CastPopup and EM2.CastPopup.IsOpen then
        local checked, popupOpen = InvokeEditModeBoundary(EM2.CastPopup.IsOpen)
        ok = checked and ok
        if checked and popupOpen then ok = CallCastbarNudgeSync(EM2.CastPopup.Sync) and ok end
    end
    if EM2.Movers then ok = CallCastbarNudgeSync(EM2.Movers.SyncAll) and ok end
    if EM2.Focus then ok = CallCastbarNudgeSync(EM2.Focus.NotifyPositionChanged, "castbar_" .. unit, true) and ok end
    ok = CallCastbarNudgeSync(RefreshUFPreview, "EM2_CASTBAR_NUDGE", unit) and ok
    return ok
end

local function ApplyCastbarNudge(unit)
    if type(ApplySettingsForKeySafe) ~= "function" then return false end
    local called, applied = InvokeEditModeBoundary(ApplySettingsForKeySafe, "castbar_" .. unit)
    return called and applied == true
end

local function RestoreCastbarNudge(general, xKey, yKey, previousX, previousY, unit)
    general[xKey], general[yKey] = previousX, previousY
    ApplyCastbarNudge(unit)
    SyncCastbarNudge(unit)
end

local function NudgeCastbar(unit, ndx, ndy)
    if not CASTBAR_NUDGE_DEFAULTS[unit] then return false end
    local isActive = EM2.State and EM2.State.IsActive
    if type(isActive) ~= "function" then return false end
    if not isActive() then return false end
    if type(BlockConfigCombatLocked) ~= "function" then return false end
    if BlockConfigCombatLocked() then return false end
    if not IsFiniteNudgeNumber(ndx) or not IsFiniteNudgeNumber(ndy) then return false end

    local db = _G.MSUF_DB
    local general = db and db.general
    if type(general) ~= "table" then return false end

    local xKey, yKey = GetCastbarOffsetKeys(unit)
    if type(xKey) ~= "string" or xKey == "" or type(yKey) ~= "string" or yKey == "" then return false end
    local defaultX, defaultY = NudgeCastbarDefaultOffsets(unit)
    if not IsFiniteNudgeNumber(defaultX) or not IsFiniteNudgeNumber(defaultY) then return false end

    local fallbackX = unit == "focus" and "castbarTargetOffsetX" or nil
    local fallbackY = unit == "focus" and "castbarTargetOffsetY" or nil
    local currentX = ReadCastbarOffset(general, xKey, fallbackX, defaultX)
    local currentY = ReadCastbarOffset(general, yKey, fallbackY, defaultY)
    if not currentX or not currentY then return false end

    local nextX = RoundNudgeOffset(currentX + ndx)
    local nextY = RoundNudgeOffset(currentY + ndy)
    if not IsFiniteNudgeNumber(nextX) or not IsFiniteNudgeNumber(nextY)
        or abs(nextX) > 4096 or abs(nextY) > 4096
    then
        return false
    end
    if nextX == currentX and nextY == currentY then return false end

    local undo = EM2.Undo
    if type(ApplySettingsForKeySafe) ~= "function" then return false end
    if not (undo and type(undo.PrepareChange) == "function" and type(undo.CommitPrepared) == "function") then return false end

    local snapshotOK, snapshot = InvokeEditModeBoundary(undo.PrepareChange, "castbar", unit)
    if not snapshotOK or type(snapshot) ~= "table" then return false end

    local previousX, previousY = general[xKey], general[yKey]
    general[xKey], general[yKey] = nextX, nextY

    if not ApplyCastbarNudge(unit)
        or tonumber(general[xKey]) ~= nextX
        or tonumber(general[yKey]) ~= nextY
        or not SyncCastbarNudge(unit)
    then
        RestoreCastbarNudge(general, xKey, yKey, previousX, previousY, unit)
        return false
    end
    local committedOK, committed = InvokeEditModeBoundary(undo.CommitPrepared, snapshot)
    if not committedOK or committed ~= true then
        RestoreCastbarNudge(general, xKey, yKey, previousX, previousY, unit)
        return false
    end
    return true
end

local function NudgeTarget(dx, dy, exactDelta)
    if not EM2.State or not EM2.State.IsActive() then return false end
    if BlockConfigCombatLocked() then return false end
    local db = _G.MSUF_DB
    if not db then return false end
    local s = exactDelta and 1 or GetStep()
    local ndx, ndy = dx * s, dy * s

    local selectedKey = EM2.State.GetUnitKey and EM2.State.GetUnitKey() or nil
    local selectedCfg = selectedKey and EM2.Registry and EM2.Registry.Get(selectedKey) or nil
    if selectedCfg and selectedCfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        return external and type(external.Nudge) == "function"
            and external.Nudge(selectedKey, ndx, ndy) == true or false
    end

    local previewTarget = GetPreviewNudgeTarget()
    if previewTarget then
        previewTarget:Nudge(ndx, ndy)
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(nil, true) end
        return true
    end

    if EM2.CastPopup and EM2.CastPopup.IsOpen() then
        local castPF = _G.MSUF_EM2_CastPopup
        local unit = (EM2.CastPopup.GetUnit and EM2.CastPopup.GetUnit()) or (castPF and castPF.unit)
        return NudgeCastbar(unit, ndx, ndy)
    end

    local auraGroup = _G.MSUF_EM2_ActiveAuraGroup
    local auraPopupOpen = EM2.AuraPopup and EM2.AuraPopup.IsOpen()
    local a2PopupOpen = false
    do local ap = _G.MSUF_EM2_AuraPopup; a2PopupOpen = ap and ap.IsShown and ap:IsShown() or false end
    if auraGroup and (auraPopupOpen or a2PopupOpen) then
        local unitKey = _G.MSUF_EM2_ActiveAuraUnit
        if not unitKey then
            local auraPF = _G.MSUF_EM2_AuraPopup
            unitKey = auraPF and auraPF.unit
        end
        if unitKey then
            local a2 = db.auras3
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
                local CUSTOM_GROUP_INDEX = { custom1 = 1, custom2 = 2, custom3 = 3, custom4 = 4 }
                local pair = GROUP_KEYS[auraGroup]
                local customIndex = CUSTOM_GROUP_INDEX[auraGroup]
                if pair then
                    local kx, ky = pair[1], pair[2]
                    local shared = a2.shared or {}
                    for _, k in ipairs(applyKeys) do
                        a2.perUnit[k] = a2.perUnit[k] or {}
                        local uc = a2.perUnit[k]
                        --- Match Aura Menu/drag ownership: a Shared-layout
                        --- scope's local table is dormant and must not revive
                        --- stale fields on the first keyboard nudge.
                        if uc.overrideLayout ~= true then uc.layout = {} end
                        uc.layout = uc.layout or {}
                        uc.overrideLayout = true
                        local lay = uc.layout
                        local cx = (lay[kx] ~= nil) and lay[kx] or (shared[kx] or 0)
                        local cy = (lay[ky] ~= nil) and lay[ky] or (shared[ky] or 0)
                        lay[kx] = floor(((tonumber(cx) or 0) + ndx) + 0.5)
                        lay[ky] = floor(((tonumber(cy) or 0) + ndy) + 0.5)
                    end
                elseif customIndex then
                    --- Custom containers persist position as placed.x/y on the
                    --- menu-model item, and the model collapses boss1-5 into a
                    --- single "boss" record - dedupe by item so a together-edit
                    --- does not add the delta once per boss key.
                    local model = MSUF and MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
                    if model and type(model.CustomContainer) == "function" then
                        local seen = {}
                        for _, k in ipairs(applyKeys) do
                            local item = model.CustomContainer(k, customIndex, true)
                            if item and not seen[item] then
                                seen[item] = true
                                if type(item.placed) ~= "table" then item.placed = {} end
                                local placed = item.placed
                                placed.x = floor(((tonumber(placed.x) or 0) + ndx) + 0.5)
                                placed.y = floor(((tonumber(placed.y) or 0) + ndy) + 0.5)
                            end
                        end
                    end
                end
                local a3 = MSUF and MSUF.MSUF_Auras3
                if a3 and type(a3.RequestScope) == "function" then
                    for _, k in ipairs(applyKeys) do a3.RequestScope(k, "AURAS3_EDITMODE_NUDGE") end
                elseif a3 and type(a3.RefreshUnit) == "function" then
                    for _, k in ipairs(applyKeys) do a3.RefreshUnit(k) end
                elseif a3 and type(a3.RefreshAll) == "function" then
                    a3.RefreshAll()
                end
                if a3 and type(a3.RefreshEditPreview) == "function" then
                    a3.RefreshEditPreview(unitKey)
                end
                if auraPopupOpen and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
                local syncFn = _G.MSUF_SyncAuras3PositionPopup
                if type(syncFn) == "function" then syncFn(unitKey) end
                if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
                    _G.MSUF_UFPreview_RequestRefresh("AURAS3_EDITMODE_NUDGE")
                end
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return unitKey ~= nil
    end

    if EM2.Focus and EM2.Focus.NudgeSelection and EM2.Focus.NudgeSelection(ndx, ndy) then
        return true
    end

    local key = EM2.State.GetUnitKey() or "player"
    if (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority")
        and type(_G.MSUF_GF_EM2_NudgePreview) == "function"
        and _G.MSUF_GF_EM2_NudgePreview(key, ndx, ndy)
    then
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
        return true
    end

    local conf = db[key]
    if not conf then return false end
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
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    RefreshUFPreview("EM2_UNIT_NUDGE", key)
    return true
end

-- Public, state-preserving movement route for non-visual controllers.  This is
-- intentionally the same function used by keyboard buttons so unit, castbar,
-- aura, group, and selected inline-preview moves retain their exact undo/apply
-- behavior without simulating a hidden secure click.
function Nudge.Move(dx, dy, targetKey)
    dx, dy = tonumber(dx), tonumber(dy)
    if not IsFiniteNudgeNumber(dx) or not IsFiniteNudgeNumber(dy) then return false end
    if dx == 0 and dy == 0 then return false end
    local castbarUnit = type(targetKey) == "string" and CASTBAR_NUDGE_UNITS[targetKey] or nil
    if type(targetKey) == "string" and targetKey:sub(1, 8) == "castbar_" and not castbarUnit then return false end
    if castbarUnit then
        local isActive = EM2.State and EM2.State.IsActive
        if type(isActive) ~= "function" then return false end
        if not isActive() then return false end
        if type(IsConfigCombatLocked) ~= "function" then return false end
        if IsConfigCombatLocked() then return false end
    end
    if type(targetKey) == "string" and targetKey ~= "" then
        local clearPreview = _G.MSUF_EM2_SetPreviewNudgeTarget
        if type(clearPreview) == "function" then clearPreview(nil) end
        local setUnitKey = EM2.State and EM2.State.SetUnitKey
        if type(setUnitKey) ~= "function" then return false end
        if setUnitKey(targetKey) == false then return false end
        if castbarUnit then
            local getUnitKey = EM2.State and EM2.State.GetUnitKey
            if type(getUnitKey) ~= "function" then return false end
            if getUnitKey() ~= targetKey then return false end
        end
    end
    if castbarUnit then return NudgeCastbar(castbarUnit, dx, dy) end
    return NudgeTarget(dx, dy, true) == true
end

local NUDGE_DIRS = { { "UP", 0, 1 }, { "DOWN", 0, -1 }, { "LEFT", -1, 0 }, { "RIGHT", 1, 0 } }
local function NudgeButtonClick(self)
    NudgeTarget(self._msufDx or 0, self._msufDy or 0)
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

        for i = 1, #NUDGE_DIRS do
            local dir = NUDGE_DIRS[i]
            local btnName = "MSUF_EM2_Nudge" .. dir[1]
            local btn = CreateFrame("Button", btnName, UIParent, "SecureActionButtonTemplate")
            btn._msufDx, btn._msufDy = dir[2], dir[3]
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", NudgeButtonClick)
        end
    end

    if IsConfigCombatLocked() then
        owner.__msufPendingClear = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if ClearOverrideBindings then ClearOverrideBindings(owner) end
    for i = 1, #NUDGE_DIRS do
        local dir = NUDGE_DIRS[i][1]
        SetOverrideBindingClick(owner, false, dir, "MSUF_EM2_Nudge" .. dir)
    end
end

function Nudge.Disable()
    if type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
    if not owner then return end
    if IsConfigCombatLocked() then
        owner.__msufPendingClear = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(owner)
end

local function MSUF_EnableArrowKeyNudge(enable)
    if enable then Nudge.Enable() else Nudge.Disable() end
end
ExportPublic("MSUF_EnableArrowKeyNudge", MSUF_EnableArrowKeyNudge)

local Ticker = {}
EM2.Ticker = Ticker

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

local function PointOffsetFromCenter(point, width, height)
    local x, y = 0, 0
    width = width or 0
    height = height or 0
    if point and point:find("LEFT", 1, true) then
        x = width * -0.5
    elseif point and point:find("RIGHT", 1, true) then
        x = width * 0.5
    end
    if point and point:find("TOP", 1, true) then
        y = height * 0.5
    elseif point and point:find("BOTTOM", 1, true) then
        y = height * -0.5
    end
    return x, y
end

local function ClampCenterAxis(center, halfSize, screenSize)
    center = tonumber(center) or 0
    halfSize = max(0, tonumber(halfSize) or 0)
    screenSize = max(0, tonumber(screenSize) or 0)
    if screenSize <= 0 then return center end
    local minCenter = halfSize
    local maxCenter = screenSize - halfSize
    if minCenter > maxCenter then
        minCenter, maxCenter = maxCenter, minCenter
    end
    return max(minCenter, min(maxCenter, center))
end

local VALID_UNIT_POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function UnitFramePoint(conf)
    local point = conf and conf.point or "CENTER"
    if not VALID_UNIT_POINTS[point] then point = "CENTER" end
    return point
end

local function UnitFrameRelativePoint(conf, point)
    local relativePoint = conf and conf.relativePoint or point or "CENTER"
    if not VALID_UNIT_POINTS[relativePoint] then relativePoint = point or "CENTER" end
    return relativePoint
end

local EDIT_COOLDOWN_ANCHORS = {
    EssentialCooldownViewer = true,
    UtilityCooldownViewer = true,
    BuffIconCooldownViewer = true,
}

local function ResolveNamedEditAnchor(name)
    if type(name) ~= "string" or name == "" then return nil end
    if EDIT_COOLDOWN_ANCHORS[name] then
        local cooldownFrame = type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(name) or nil
        return cooldownFrame or _G[name]
    end
    local UF = MSUF and MSUF.UF
    if UF and type(UF.GetFrame) == "function" then
        local frame = UF.GetFrame(name)
        if frame then return frame end
    end
    local uf = UF and UF.frames
    if uf and uf[name] then return uf[name] end
    return _G[name] or _G["MSUF_" .. name]
end

local function UnitCooldownAnchorName(conf)
    local cn = conf and conf.anchorFrameName
    if EDIT_COOLDOWN_ANCHORS[cn] then return cn end
    if type(cn) == "string" and cn ~= "" then return nil end

    local atv = conf and conf.anchorToUnitframe
    if EDIT_COOLDOWN_ANCHORS[atv] then return atv end
    if type(atv) == "string" and atv ~= "" and atv ~= "GLOBAL" and atv ~= "global" and atv ~= "FREE" then return nil end

    local db = _G.MSUF_DB
    local general = db and db.general
    local isCooldownAnchorEnabled = _G.MSUF_IsCooldownAnchorEnabled
    local cooldownAnchorEnabled = type(isCooldownAnchorEnabled) == "function"
        and isCooldownAnchorEnabled(general) == true
        or general and general.anchorToCooldown == true
    if cooldownAnchorEnabled then return "EssentialCooldownViewer" end
    local globalAnchor = general and general.anchorName
    if EDIT_COOLDOWN_ANCHORS[globalAnchor] then return globalAnchor end
    return nil
end

local function ResolveAnchor(key, conf)
    local anchorFn = _G.MSUF_GetAnchorFrame
    local anchor = (type(anchorFn) == "function" and anchorFn()) or UIParent
    if not conf then return anchor end
    local cn = conf.anchorFrameName
    if type(cn) == "string" and cn ~= "" then
        local cf = ResolveNamedEditAnchor(cn)
        if cf and cf ~= UIParent and cf ~= WorldFrame then return cf end
    end
    local atv = conf.anchorToUnitframe
    if type(atv) == "string" and atv ~= "" and atv ~= "GLOBAL" and atv ~= "FREE" and atv ~= "global" then
        local rel = ResolveNamedEditAnchor(atv)
        if rel and rel ~= UIParent and rel ~= WorldFrame then return rel end
    end
    local cooldownAnchorName = UnitCooldownAnchorName(conf)
    if cooldownAnchorName then
        local cooldownAnchor = ResolveNamedEditAnchor(cooldownAnchorName)
        if cooldownAnchor and cooldownAnchor ~= UIParent and cooldownAnchor ~= WorldFrame then return cooldownAnchor end
    end
    return anchor
end

local function ApplyFramePoint(frame, point, anchor, relativePoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, anchor, relativePoint, x, y)
end

local function ReadEditAnchorOwnedMarker(anchor)
    return anchor._msufOwnedAnchorRoot
end

local function IsExternalEditAnchor(anchor)
    if anchor == nil or anchor == UIParent or anchor == WorldFrame then return false end
    local ok, owned = pcall(ReadEditAnchorOwnedMarker, anchor)
    return not (ok and owned == true)
end

local function CaptureFramePoints(frame)
    if not (frame and frame.GetPoint) then return nil end
    local count = 1
    if frame.GetNumPoints then
        local ok, value = pcall(frame.GetNumPoints, frame)
        if ok then count = tonumber(value) or 0 end
    end
    local points = {}
    for i = 1, count do
        local result = { pcall(frame.GetPoint, frame, i) }
        if result[1] and result[2] then
            points[#points + 1] = {
                point = result[2],
                anchor = result[3],
                relativePoint = result[4],
                x = result[5],
                y = result[6],
            }
        end
    end
    return #points > 0 and points or nil
end

local function RestoreFramePoints(frame, points)
    if not (frame and points) then return false end
    local cleared = pcall(frame.ClearAllPoints, frame)
    if not cleared then return false end
    for i = 1, #points do
        local p = points[i]
        if not pcall(frame.SetPoint, frame, p.point, p.anchor, p.relativePoint, p.x, p.y) then
            pcall(frame.ClearAllPoints, frame)
            return false
        end
    end
    return true
end

local function TryApplyFramePoint(frame, point, anchor, relativePoint, x, y)
    if not (frame and anchor) then return false end
    -- A drag tick must never straddle combat with a protected frame mutation.
    -- The edit-mode driver stops on PLAYER_REGEN_DISABLED as well, but this
    -- guard closes the event/ticker boundary itself.
    if InCombatLockdown and InCombatLockdown() then return false end

    -- External anchors stay live out of combat so the frame follows provider
    -- movement; the Factory combat-edge freeze severs the link for combat.
    -- Positioning onto one is still transactional: keep the previous points so
    -- an unresolvable provider chain can be rolled back atomically.
    local externalAnchor = IsExternalEditAnchor(anchor)
    local rollbackPoints
    if externalAnchor then
        rollbackPoints = CaptureFramePoints(frame)
        if not rollbackPoints then return false end
    end

    local applied = pcall(ApplyFramePoint, frame, point, anchor, relativePoint, x, y)
    if not applied then
        -- ApplyFramePoint clears before it sets; a mid-apply error must not
        -- leave the frame pointless.
        if rollbackPoints then RestoreFramePoints(frame, rollbackPoints) end
        return false
    end
    if not externalAnchor then return true end

    -- Accept the live link only when the provider chain resolves to a real
    -- screen rect; a rectless chain would render the frame nowhere.
    if frame.GetCenter and frame:GetCenter() ~= nil then return true end
    RestoreFramePoints(frame, rollbackPoints)
    return false
end

local function SetBossPreviewPosition(point, anchor, relativePoint, x, y, conf, rollbackX, rollbackY)
    local layoutDelta = _G.MSUF_GetBossLayoutDelta
    if type(layoutDelta) ~= "function" then return false end
    local uf = MSUF and MSUF.UF
    local frames = uf and uf.frames
    local moved = false
    for i = 1, 5 do
        local unit = "boss" .. i
        local frame = (frames and frames[unit]) or _G["MSUF_" .. unit]
        if frame then
            local dx, dy = layoutDelta(i, conf)
            frame._msufDragActive = true
            if not TryApplyFramePoint(frame, point, anchor, relativePoint, x + (dx or 0), y + (dy or 0)) then
                if rollbackX ~= nil and rollbackY ~= nil then
                    for restoreIndex = 1, 5 do
                        local restoreUnit = "boss" .. restoreIndex
                        local restoreFrame = (frames and frames[restoreUnit]) or _G["MSUF_" .. restoreUnit]
                        if restoreFrame then
                            local restoreDX, restoreDY = layoutDelta(restoreIndex, conf)
                            TryApplyFramePoint(restoreFrame, point, anchor, relativePoint,
                                rollbackX + (restoreDX or 0), rollbackY + (restoreDY or 0))
                            if type(_G.MSUF_ApplyBossPhysicalBarGeometry) == "function" then
                                _G.MSUF_ApplyBossPhysicalBarGeometry(restoreFrame)
                            end
                        end
                    end
                end
                return false
            end
            if type(_G.MSUF_ApplyBossPhysicalBarGeometry) == "function" then
                _G.MSUF_ApplyBossPhysicalBarGeometry(frame)
            end
            moved = true
        end
    end
    return moved
end

local function ApplyUnitDragPosition(d, centerX, centerY, uiScale)
    if not (d and d.bar and d.conf and d.anchor) then return false end
    local frameScale = d.bar.GetEffectiveScale and (d.bar:GetEffectiveScale() or 1) or 1
    if frameScale <= 0 then frameScale = 1 end
    uiScale = tonumber(uiScale) or 1
    if uiScale <= 0 then uiScale = 1 end

    local currentCX = tonumber(centerX) or d.startCX or 0
    local currentCY = tonumber(centerY) or d.startCY or 0
    local nextX = (d.unitStartX or 0) + round((currentCX - (d.startCX or currentCX)) * uiScale / frameScale)
    local nextY = (d.unitStartY or 0) + round((currentCY - (d.startCY or currentCY)) * uiScale / frameScale)
    if d.lastUnitX == nextX and d.lastUnitY == nextY then return true end

    local previousX = d.lastUnitX
    local previousY = d.lastUnitY
    if previousX == nil then previousX = d.unitStartX or 0 end
    if previousY == nil then previousY = d.unitStartY or 0 end

    local positioned
    if d.usesECV and d.ecvFrame and d.ecvRule then
        local point, relativePoint = d.ecvRule[1], d.ecvRule[2]
        local baseX, extraY = d.ecvRule[3] or 0, d.ecvRule[4] or 0
        positioned = TryApplyFramePoint(d.bar, point, d.ecvFrame, relativePoint,
            baseX + nextX, nextY + extraY)
    elseif d.isBossLayout then
        positioned = SetBossPreviewPosition(d.point, d.anchor, d.relativePoint,
            nextX, nextY, d.conf, previousX, previousY)
    else
        positioned = TryApplyFramePoint(d.bar, d.point, d.anchor, d.relativePoint, nextX, nextY)
    end
    if not positioned then
        if d.usesECV and d.ecvFrame and d.ecvRule then
            local point, relativePoint = d.ecvRule[1], d.ecvRule[2]
            local baseX, extraY = d.ecvRule[3] or 0, d.ecvRule[4] or 0
            TryApplyFramePoint(d.bar, point, d.ecvFrame, relativePoint,
                baseX + previousX, previousY + extraY)
        elseif not d.isBossLayout then
            TryApplyFramePoint(d.bar, d.point, d.anchor, d.relativePoint, previousX, previousY)
        end
        return false
    end

    d.conf.offsetX = nextX
    d.conf.offsetY = nextY
    d.lastUnitX = nextX
    d.lastUnitY = nextY
    return true
end

local GROUP_VALID_POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function ResolveGroupAnchor(conf, owner)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.ResolveAnchorFrame) == "function" then
        return gf.ResolveAnchorFrame(conf, owner)
    end
    return UIParent
end

local function GroupAnchorPoint(conf)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.GetAnchorPoint) == "function" then return gf.GetAnchorPoint(conf) end
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not GROUP_VALID_POINTS[point] then point = "CENTER" end
    return point
end

--- Both sides of a group anchor come from the single visible Anchor Point; see
--- GF.ResolveAnchorPoint (MSUF_GroupFrames_DB.lua) for the legacy pair it retires.
local function GroupAnchorPoints(kind, conf, parent)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.ResolveAnchorPoint) == "function" then
        return gf.ResolveAnchorPoint(kind, conf, parent)
    end
    local point = GroupAnchorPoint(conf)
    return point, point
end

local function GroupOffsetFromCenter(bar, conf, centerX, centerY, gridDX, gridDY)
    local owner = bar and (bar._msufGFLiveAnchor or bar._msufGFLogicalAnchor or bar) or nil
    local anchor = ResolveGroupAnchor(conf, owner)
    local point, relativePoint = GroupAnchorPoints(bar and bar._msufGFKind, conf, anchor)
    local ax, ay = PointXY(anchor, relativePoint)
    if not (ax and ay) then
        ax = ((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0) * 0.5
        ay = ((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0) * 0.5
    end

    local bw = tonumber(bar and bar._msufGFGridWidth) or (bar and bar.GetWidth and bar:GetWidth()) or 0
    local bh = tonumber(bar and bar._msufGFGridHeight) or (bar and bar.GetHeight and bar:GetHeight()) or 0
    local pointDX, pointDY = PointOffsetFromCenter(point, bw, bh)
    local targetX = (centerX or 0) + pointDX + (tonumber(gridDX) or 0)
    local targetY = (centerY or 0) + pointDY + (tonumber(gridDY) or 0)
    return round(targetX - ax), round(targetY - ay)
end

local tickerFrame
local tickerActive = false
local activeDrag
local idleMoverDirty = false
local idleHUDDirty = false
local C_Timer = _G.C_Timer
local dirtyFlushScheduled = false
local dirtyFlushGeneration = 0

local function SyncUnitPopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc >= 0.05 then
        d.popupSyncAcc = 0
        if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    end
end

local function SyncGFPopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc >= 0.05 then
        d.popupSyncAcc = 0
        if type(_G.MSUF_EM2_SyncGFPopups) == "function" then
            _G.MSUF_EM2_SyncGFPopups()
        end
    end
end

local function CastbarDefaultOffsets(unit)
    local fn = _G.MSUF_GetCastbarDefaultOffsets
    if type(fn) == "function" then
        local x, y = fn(unit)
        return tonumber(x) or 0, tonumber(y) or 0
    end
    if unit == "target" or unit == "focus" then return 65, -15 end
    return 0, 0
end

local function ApplyCastbarDragPosition(d, centerX, centerY)
    if not (d and d.conf and d.castbarXKey and d.castbarYKey) then return false end
    local g = d.conf
    local dx = (centerX or d.startCX or 0) - (d.startCX or 0)
    local dy = (centerY or d.startCY or 0) - (d.startCY or 0)
    local nextX = round((d.castbarStartX or 0) + dx)
    local nextY = round((d.castbarStartY or 0) + dy)

    if d.castbarUnit == "boss" then
        local sx = _G.MSUF_CastbarBossXOffsetSlider
        local sy = _G.MSUF_CastbarBossYOffsetSlider
        local clamp = _G.MSUF_ClampToSlider
        if sx and type(clamp) == "function" then nextX = clamp(sx, nextX) end
        if sy and type(clamp) == "function" then nextY = clamp(sy, nextY) end
    end

    if g[d.castbarXKey] == nextX and g[d.castbarYKey] == nextY then
        return true
    end

    g[d.castbarXKey] = nextX
    g[d.castbarYKey] = nextY

    local positioned = false
    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then
        positioned = _G.MSUF_PositionCastbarPreviewUnit(d.castbarUnit) and true or false
    end
    if not positioned then
        local rfName = d.castbarReanchorFunc
        local rf = rfName and _G[rfName] or nil
        if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
            _G.MSUF_ApplyCastbarUnitAndSync(d.castbarUnit)
        else
            if type(rf) == "function" then
                rf()
            end
            if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
                _G.MSUF_ApplyCastbarVisualsForUnit(d.castbarUnit)
            elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                _G.MSUF_UpdateCastbarVisuals(d.castbarUnit)
            end
        end
    end

    return true
end

local function ApplyGroupDragPosition(d, centerX, centerY)
    if not (d and d.conf and d.bar) then return false end
    if IsConfigCombatLocked() then return false end
    local bar = d.bar
    local gridDX = tonumber(bar._msufGFDragCenterToGridX) or 0
    local gridDY = tonumber(bar._msufGFDragCenterToGridY) or 0
    local targetCX = (centerX or d.startCX or 0) + (d.barCenterDX or 0)
    local targetCY = (centerY or d.startCY or 0) + (d.barCenterDY or 0)
    local anchorCX = targetCX + gridDX
    local anchorCY = targetCY + gridDY
    local nextX, nextY = GroupOffsetFromCenter(bar, d.conf, targetCX, targetCY, gridDX, gridDY)
    local changed = d.conf.offsetX ~= nextX or d.conf.offsetY ~= nextY
    local positionChanged = (d.lastGroupTargetCX == nil)
        or abs(targetCX - d.lastGroupTargetCX) > 0.001
        or abs(targetCY - d.lastGroupTargetCY) > 0.001
        or abs(anchorCX - d.lastGroupAnchorCX) > 0.001
        or abs(anchorCY - d.lastGroupAnchorCY) > 0.001
    if changed or positionChanged then
        local liveAnchor = bar._msufGFLiveAnchor
        local logicalAnchor = bar._msufGFLogicalAnchor
        local anchor = liveAnchor or logicalAnchor
        local _, oldBarCX, _, _, oldBarCY = GetFrameEdgesUI(bar)
        oldBarCX = oldBarCX or d.lastGroupTargetCX or ((d.startCX or targetCX) + (d.barCenterDX or 0))
        oldBarCY = oldBarCY or d.lastGroupTargetCY or ((d.startCY or targetCY) + (d.barCenterDY or 0))
        local oldAnchorCX, oldAnchorCY
        if anchor and anchor ~= bar then
            local _, anchorCenterX, _, _, anchorCenterY = GetFrameEdgesUI(anchor)
            oldAnchorCX = anchorCenterX or d.lastGroupAnchorCX or (oldBarCX + gridDX)
            oldAnchorCY = anchorCenterY or d.lastGroupAnchorCY or (oldBarCY + gridDY)
        end

        if not TryApplyFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", targetCX, targetCY) then
            TryApplyFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", oldBarCX, oldBarCY)
            return false
        end
        if anchor and anchor ~= bar and anchor.ClearAllPoints and anchor.SetPoint then
            if not TryApplyFramePoint(anchor, "CENTER", UIParent, "BOTTOMLEFT", anchorCX, anchorCY) then
                TryApplyFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", oldBarCX, oldBarCY)
                TryApplyFramePoint(anchor, "CENTER", UIParent, "BOTTOMLEFT", oldAnchorCX, oldAnchorCY)
                return false
            end
        end
        d.lastGroupTargetCX = targetCX
        d.lastGroupTargetCY = targetCY
        d.lastGroupAnchorCX = anchorCX
        d.lastGroupAnchorCY = anchorCY
    end
    if changed then
        d.conf.offsetX = nextX
        d.conf.offsetY = nextY
    end
    d.conf.positionMode = "GRID_BOUNDS_V2"
    return true
end

local function ApplyPublicExternalDragPosition(d, centerX, centerY, phase)
    if not (d and d.externalPublicElement and d.externalStartState) then return false end
    local external = EM2.ExternalElements
    if not (external and type(external.ApplyMove) == "function") then return false end
    return external.ApplyMove(
        d.key,
        d.externalStartState,
        (centerX or d.startCX or 0) - (d.startCX or 0),
        (centerY or d.startCY or 0) - (d.startCY or 0),
        centerX,
        centerY,
        phase or "preview"
    ) == true
end

local function SyncCastbarPopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc < 0.05 then return end
    d.popupSyncAcc = 0
    if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
        _G.MSUF_SyncCastbarPositionPopup(d.castbarUnit)
    elseif EM2.CastPopup and EM2.CastPopup.IsOpen and EM2.CastPopup.IsOpen() and EM2.CastPopup.Sync then
        EM2.CastPopup.Sync()
    end
end

local function NotifyFocusDuringDrag(d, elapsed)
    if not (d and EM2.Focus and EM2.Focus.NotifyPositionChanged) then return end
    d.focusNotifyAcc = (d.focusNotifyAcc or 0) + (elapsed or 0)
    if d.focusNotifyAcc < 0.05 then return end
    d.focusNotifyAcc = 0
    EM2.Focus.NotifyPositionChanged(d.key, false)
end

local function FlushDirty()
    if not tickerActive or activeDrag or (IsConfigCombatLocked and IsConfigCombatLocked()) then return end
    local syncMovers, syncHUD = idleMoverDirty, idleHUDDirty
    idleMoverDirty, idleHUDDirty = false, false
    if syncMovers then
        if EM2.Movers and EM2.Movers.SyncAll and (not EM2.Movers.IsShown or EM2.Movers.IsShown()) then EM2.Movers.SyncAll() end
    end
    if syncHUD then
        if EM2.HUD and EM2.HUD.RefreshControls and (not EM2.HUD.IsShown or EM2.HUD.IsShown()) then EM2.HUD.RefreshControls() end
    end
end

local function ScheduleDirtyFlush(delay)
    if not tickerActive or dirtyFlushScheduled or activeDrag then return end
    if IsConfigCombatLocked and IsConfigCombatLocked() then return end
    if not (C_Timer and C_Timer.After) then
        FlushDirty()
        return
    end
    dirtyFlushScheduled = true
    local generation = dirtyFlushGeneration
    C_Timer.After(delay or 0, function()
        dirtyFlushScheduled = false
        if generation ~= dirtyFlushGeneration then return end
        FlushDirty()
    end)
end

local function SetActiveDragFlags(d, active)
    if not d then return end
    active = active == true
    if d.bar then d.bar._msufDragActive = active end
    if d.isBossLayout then
        local frames = MSUF and MSUF.UF and MSUF.UF.frames
        for i = 1, 5 do
            local frame = (frames and frames["boss" .. i]) or _G["MSUF_boss" .. i]
            if frame then frame._msufDragActive = active end
        end
    end
    if d.bar and d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = active end
    if d.bar and d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = active end
    if not active and d.mover and d.mover._msufGFEM2DragSourceFrame then
        d.mover._msufGFEM2DragSourceFrame._msufGFEM2Dragging = nil
        d.mover._msufGFEM2DragSourceFrame = nil
    end
end

local function OnUpdate(self, elapsed)
    if activeDrag then
        local d = activeDrag

        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            local mover = d.mover
            local sourceFrame = mover and mover._msufGFEM2DragSourceFrame
            local moved
            if mover and type(mover._msufEM2EndDrag) == "function" then
                moved = mover:_msufEM2EndDrag("LeftButton") == true
            else
                moved = Ticker.EndDrag()
                if mover then
                    if moved then mover._suppressNextClick = true end
                    if mover._dragging ~= nil then mover._dragging = false end
                    if mover._coordFS then mover._coordFS:Hide() end
                    if mover.UpdateLabelVisibility then mover:UpdateLabelVisibility() end
                end
            end
            if moved and sourceFrame then sourceFrame._msufGFEM2LastDragEnd = GetTime and GetTime() or 0 end
            return
        end

        if IsConfigCombatLocked and IsConfigCombatLocked() then return end

        local sc = UIParent:GetEffectiveScale() or d.uiScale or 1
        if sc <= 0 then sc = 1 end
        local mx, my = GetCursorPosition()
        if type(mx) ~= "number" or type(my) ~= "number" then return end

        local rawCX = (mx + (d.offPX or 0)) / sc
        local rawCY = (my + (d.offPY or 0)) / sc

        local snapCX, snapCY = rawCX, rawCY
        if d.snapEnabled and EM2.Snap then
            local nextCX, nextCY = EM2.Snap.Apply(rawCX, rawCY, d.halfW, d.halfH, d.key)
            if type(nextCX) == "number" then snapCX = nextCX end
            if type(nextCY) == "number" then snapCY = nextCY end
        end

        local screenW = UIParent:GetWidth() or d.screenW or 0
        local screenH = UIParent:GetHeight() or d.screenH or 0
        snapCX = ClampCenterAxis(snapCX, d.halfW, screenW)
        snapCY = ClampCenterAxis(snapCY, d.halfH, screenH)

        local positioned
        if d.externalPublicElement then
            positioned = ApplyPublicExternalDragPosition(d, snapCX, snapCY, "preview")
        elseif d.isCastbar then
            positioned = ApplyCastbarDragPosition(d, snapCX, snapCY)
        elseif d.isGroupFrame then
            positioned = ApplyGroupDragPosition(d, snapCX, snapCY)
        else
            positioned = ApplyUnitDragPosition(d, snapCX, snapCY, sc)
        end
        --- The mover is only feedback. Never let it outrun the real preview or
        --- leave a detached overlay behind when a protected/runtime move fails.
        if not positioned then return end

        local moverX = snapCX - d.halfW
        local moverY = snapCY + d.halfH - screenH
        local moverMoved = (d.lastMoverX == nil)
            or abs(moverX - d.lastMoverX) > 0.001
            or abs(moverY - d.lastMoverY) > 0.001

        if moverMoved then
            d.lastMoverX = moverX
            d.lastMoverY = moverY
            d.mover:ClearAllPoints()
            d.mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", moverX, moverY)

            if d.mover._coordFS then
                local displayX, displayY
                if type(U.FramePositionValues) == "function" then
                    displayX, displayY = U.FramePositionValues(d.bar)
                end
                local fallbackX
                if not displayX then
                    local left = snapCX - d.halfW
                    local right = snapCX + d.halfW
                    local centerX = screenW * 0.5
                    if right <= centerX then
                        fallbackX = right - centerX
                    elseif left >= centerX then
                        fallbackX = left - centerX
                    else
                        fallbackX = 0
                    end
                end
                d.mover._coordFS:SetText(format("%.0f, %.0f",
                    displayX or round(fallbackX),
                    displayY or round(snapCY + d.halfH - screenH * 0.5)))
            end
        end

        if d.externalPublicElement then
            NotifyFocusDuringDrag(d, elapsed)
            return
        elseif d.isCastbar then
            SyncCastbarPopupDuringDrag(d, elapsed)
            NotifyFocusDuringDrag(d, elapsed)
            return
        end

        if d.isGroupFrame then
            SyncGFPopupDuringDrag(d, elapsed)
        else
            SyncUnitPopupDuringDrag(d, elapsed)
        end
        NotifyFocusDuringDrag(d, elapsed)
    else
        self:SetScript("OnUpdate", nil)
        self:Hide()
        ScheduleDirtyFlush(0)
    end
end

local function BuildDrag(mover, key, cfg, start)
    if not mover or type(cfg) ~= "table" then return nil end
    local bar = type(start) == "table" and start.bar or (cfg.getFrame and cfg.getFrame())
    if not bar then return false end
    local externalPublicElement = cfg.externalPublicElement == true
    local conf = cfg.getConf and cfg.getConf()
    local isCastbar = (cfg.popupType == "castbar") or (type(key) == "string" and key:sub(1, 8) == "castbar_")
    local castbarUnit = cfg.castbarUnit
    if isCastbar and (not castbarUnit or castbarUnit == "") then
        castbarUnit = key:sub(9)
    end
    if isCastbar then conf = conf or ((_G.MSUF_DB and _G.MSUF_DB.general) or nil) end
    if not externalPublicElement and type(conf) ~= "table" then return false end

    local uiScale = UIParent:GetEffectiveScale() or 1
    if uiScale <= 0 then uiScale = 1 end
    local cursorPX, cursorPY = GetCursorPosition()
    if type(cursorPX) ~= "number" or type(cursorPY) ~= "number" then return false end

    local mL, mCX, mR, mB, mCY, mT = GetFrameEdgesUI(mover)
    if not mL and mover.GetLeft and mover.GetRight and mover.GetTop and mover.GetBottom then
        mL, mR, mT, mB = mover:GetLeft(), mover:GetRight(), mover:GetTop(), mover:GetBottom()
        if mL and mR and mT and mB then
            mCX = (mL + mR) * 0.5
            mCY = (mT + mB) * 0.5
        end
    end
    if not (mL and mCX and mR and mB and mCY and mT) then return false end

    if externalPublicElement then
        local external = EM2.ExternalElements
        local externalStartState = external and type(external.CaptureState) == "function"
            and external.CaptureState(key) or nil
        if externalStartState == nil then return false end
        return {
            mover = mover,
            key = key,
            cfg = cfg,
            bar = bar,
            offPX = mCX * uiScale - cursorPX,
            offPY = mCY * uiScale - cursorPY,
            startCX = mCX,
            startCY = mCY,
            startCenterPX = mCX * uiScale,
            startCenterPY = mCY * uiScale,
            halfW = (mR - mL) * 0.5,
            halfH = (mT - mB) * 0.5,
            screenW = UIParent:GetWidth(),
            screenH = UIParent:GetHeight(),
            focusNotifyAcc = 0.05,
            snapEnabled = EM2.Snap and EM2.Snap.IsEnabled and EM2.Snap.IsEnabled() or false,
            uiScale = uiScale,
            externalPublicElement = true,
            externalStartState = externalStartState,
        }
    end

    local isGroupFrame = (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority") or (bar and bar._msufIsGroupFrame == true) or false
    local groupKind = (key == "gf_party" and "party")
        or (key == "gf_raid" and "raid")
        or (key == "gf_mythicraid" and "mythicraid")
        or (key == "gf_priority" and "priority")
        or (bar and bar._msufGFKind)
    local groupOwner = isGroupFrame and bar and (bar._msufGFLiveAnchor or bar._msufGFLogicalAnchor or bar) or nil
    local anchor = isCastbar and UIParent or (isGroupFrame and ResolveGroupAnchor(conf, groupOwner)) or ResolveAnchor(key, conf)
    local point = UnitFramePoint(conf)
    local relativePoint = UnitFrameRelativePoint(conf, point)
    local factory = MSUF and MSUF.UF and MSUF.UF.Factory
    if not isCastbar and not isGroupFrame and (anchor == bar
        or (factory and type(factory.AnchorWouldCreateCycle) == "function"
            and factory.AnchorWouldCreateCycle(bar, anchor))) then
        anchor = UIParent
        relativePoint = point
    end

    local barCenterDX, barCenterDY = 0, 0
    if isGroupFrame then
        local _, bCX, _, _, bCY = GetFrameEdgesUI(bar)
        if bCX and bCY then
            barCenterDX = bCX - mCX
            barCenterDY = bCY - mCY
        end
    end

    local ecvRule = ECV_ANCHORS[key]
    local usesECV = false
    local ecvFrame
    if (not isCastbar) and ecvRule and conf then
        local cooldownAnchorName = UnitCooldownAnchorName(conf)
        -- Utility/Buff viewer offsets from 5.77 are CENTER-to-CENTER. Mirror
        -- the runtime compiler and reserve these edge rules for Essential.
        local ecv = cooldownAnchorName == "EssentialCooldownViewer"
            and (ResolveNamedEditAnchor(cooldownAnchorName) or anchor) or nil
        if ecv and anchor == ecv then
            usesECV = true
            ecvFrame = ecv
        end
    end

    local castbarXKey, castbarYKey
    local castbarStartX, castbarStartY
    local castbarReanchorFunc
    if isCastbar then
        castbarXKey, castbarYKey = GetCastbarOffsetKeys(castbarUnit)
        if not (castbarXKey and castbarYKey) then return false end
        local defX, defY = CastbarDefaultOffsets(castbarUnit)
        castbarStartX = tonumber(conf[castbarXKey]) or defX
        castbarStartY = tonumber(conf[castbarYKey]) or defY
        if castbarUnit == "player" then
            castbarReanchorFunc = "MSUF_ReanchorPlayerCastBar"
        elseif castbarUnit == "target" then
            castbarReanchorFunc = "MSUF_ReanchorTargetCastBar"
        elseif castbarUnit == "focus" then
            castbarReanchorFunc = "MSUF_ReanchorFocusCastBar"
        elseif castbarUnit == "boss" then
            castbarReanchorFunc = "MSUF_ReanchorBossCastBar"
        end
    end

    local isBossLayout = not isCastbar and key == "boss"

    local drag = {
        mover        = mover,
        key          = key,
        cfg          = cfg,
        bar          = bar,
        conf         = conf,
        anchor       = anchor,
        ecvRule      = ecvRule,
        offPX        = mCX * uiScale - cursorPX,
        offPY        = mCY * uiScale - cursorPY,
        startCX      = mCX,
        startCY      = mCY,
        startCenterPX = mCX * uiScale,
        startCenterPY = mCY * uiScale,
        halfW        = (mR - mL) * 0.5,
        halfH        = (mT - mB) * 0.5,
        screenW      = UIParent:GetWidth(),
        screenH      = UIParent:GetHeight(),
        popupSyncAcc = 0.05,
        focusNotifyAcc = 0.05,
        isGroupFrame = isGroupFrame,
        isBossLayout = isBossLayout,
        groupKind    = groupKind,
        isCastbar    = isCastbar,
        castbarUnit  = castbarUnit,
        castbarXKey  = castbarXKey,
        castbarYKey  = castbarYKey,
        castbarStartX = castbarStartX,
        castbarStartY = castbarStartY,
        castbarReanchorFunc = castbarReanchorFunc,
        snapEnabled  = EM2.Snap and EM2.Snap.IsEnabled and EM2.Snap.IsEnabled() or false,
        uiScale      = uiScale,
        point        = point,
        relativePoint = relativePoint,
        unitStartX   = tonumber(conf and conf.offsetX) or 0,
        unitStartY   = tonumber(conf and conf.offsetY) or 0,
        barCenterDX  = barCenterDX,
        barCenterDY  = barCenterDY,
        usesECV      = usesECV,
        ecvFrame     = ecvFrame,
    }
    if type(start) == "table" then
        local centerX = tonumber(start.centerX)
        local centerY = tonumber(start.centerY)
        if centerX then
            drag.startCX = centerX
            drag.startCenterPX = centerX * uiScale
        end
        if centerY then
            drag.startCY = centerY
            drag.startCenterPY = centerY * uiScale
        end
        drag.unitStartX = tonumber(start.offsetX) or drag.unitStartX
        drag.unitStartY = tonumber(start.offsetY) or drag.unitStartY
        drag.castbarStartX = tonumber(start.castbarX) or drag.castbarStartX
        drag.castbarStartY = tonumber(start.castbarY) or drag.castbarStartY
    end
    return drag
end

function Ticker.BeginDrag(mover, key, cfg)
    if not tickerActive or activeDrag or not tickerFrame then return false end
    local drag = BuildDrag(mover, key, cfg)
    if not drag then return false end
    activeDrag = drag
    SetActiveDragFlags(drag, true)
    tickerFrame:SetScript("OnUpdate", OnUpdate)
    tickerFrame:Show()
    return true
end

--- External Edit Mode shells own their own cursor loop. These three cold-path
--- methods reuse the exact native MSUF anchor math without starting a second
--- OnUpdate or exposing its private drag state.
function Ticker.BeginExternalDrag(mover, key, cfg, start)
    local drag = BuildDrag(mover, key, cfg, start)
    if not drag then return nil end
    SetActiveDragFlags(drag, true)
    return drag
end

function Ticker.ApplyExternalDrag(drag)
    if not drag or (IsConfigCombatLocked and IsConfigCombatLocked()) then return false end
    local _, centerX, _, _, centerY = GetFrameEdgesUI(drag.mover)
    if centerX == nil or centerY == nil then return false end
    if drag.externalPublicElement then
        return ApplyPublicExternalDragPosition(drag, centerX, centerY, "preview")
    elseif drag.isCastbar then
        return ApplyCastbarDragPosition(drag, centerX, centerY)
    elseif drag.isGroupFrame then
        return ApplyGroupDragPosition(drag, centerX, centerY)
    end
    return ApplyUnitDragPosition(drag, centerX, centerY, UIParent:GetEffectiveScale() or drag.uiScale or 1)
end

function Ticker.EndExternalDrag(drag, applyFinal)
    if not drag then return false end
    local moved = applyFinal ~= false and Ticker.ApplyExternalDrag(drag) or false
    SetActiveDragFlags(drag, false)
    return moved
end

function Ticker.EndDrag()
    if not activeDrag then return false end
    local d = activeDrag
    activeDrag = nil
    SetActiveDragFlags(d, false)
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

    local mover = d.mover
    local mL, cx, mR, mB, cy, mT = GetFrameEdgesUI(mover)
    if not mL then
        mL = mover:GetLeft() or 0; mR = mover:GetRight() or 0
        mT = mover:GetTop() or 0; mB = mover:GetBottom() or 0
        cx = (mL + mR) * 0.5; cy = (mT + mB) * 0.5
    end
    local uiScale = UIParent:GetEffectiveScale() or d.uiScale or 1
    if uiScale <= 0 then uiScale = 1 end
    local moved = abs(cx * uiScale - (d.startCenterPX or cx * uiScale)) > 0.5
        or abs(cy * uiScale - (d.startCenterPY or cy * uiScale)) > 0.5

    if moved then
        if d.externalPublicElement then
            if not ApplyPublicExternalDragPosition(d, cx, cy, "commit") then
                local external = EM2.ExternalElements
                if external and type(external.RestoreHistoryState) == "function" then
                    external.RestoreHistoryState({ key = d.key, data = d.externalStartState })
                end
                moved = false
            end
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            if EM2.Focus and EM2.Focus.NotifyPositionChanged then
                EM2.Focus.NotifyPositionChanged(d.key, true)
            end
        elseif d.isGroupFrame and d.conf then
            ApplyGroupDragPosition(d, cx, cy)
            if d.bar and not IsConfigCombatLocked() then
                d.bar._msufDragActive = false
                if d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = false end
                if d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = false end
            end
        end
        --- Offsets already written by OnUpdate. Just finalize pipeline.
        if d.externalPublicElement then
            -- The provider callback already applied and persisted the final
            -- position. It remains the sole owner of its frame and saved data.
        elseif d.isCastbar then
            local centralized = false
            if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
                _G.MSUF_ApplyCastbarUnitAndSync(d.castbarUnit)
                centralized = true
            else
                ApplyCastbarDragPosition(d, cx, cy)
            end
            C_Timer.After(0.06, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
            if not centralized and type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                _G.MSUF_SyncCastbarPositionPopup(d.castbarUnit)
            end
            if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
            RefreshUFPreview("EM2_CASTBAR_DRAG_END", d.castbarUnit)
        elseif d.isGroupFrame then
            if not IsConfigCombatLocked() then
                RefreshGroupGeometryScoped(d.groupKind)
            end
            C_Timer.After(0.06, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
            if type(_G.MSUF_EM2_SyncGFPopups) == "function" then
                _G.MSUF_EM2_SyncGFPopups()
            end
            if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
        else
            ApplySettingsForKeySafe(d.key)
            C_Timer.After(0.06, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
            if _G.MSUF_SyncUnitPositionPopup then _G.MSUF_SyncUnitPositionPopup() end
            if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
            if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
            RefreshUFPreview("EM2_UNIT_DRAG_END", d.key)
        end
        if moved then NotifyGuidedEditModeMoved(d.key) end
    end

    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", nil)
        tickerFrame:Hide()
    end
    ScheduleDirtyFlush(0)
    return moved
end

function Ticker.IsDragging() return activeDrag ~= nil end

function Ticker.RequestIdleSync(kind)
    if kind == "mover" then
        idleMoverDirty = true
        ScheduleDirtyFlush(0)
        return
    elseif kind == "hud" then
        idleHUDDirty = true
        ScheduleDirtyFlush(0)
        return
    end
    idleMoverDirty = true
    idleHUDDirty = true
    ScheduleDirtyFlush(0)
end

function Ticker.Start()
    if activeDrag then SetActiveDragFlags(activeDrag, false) end
    if not tickerFrame then
        tickerFrame = CreateFrame("Frame", "MSUF_EM2_TickerFrame", UIParent)
        tickerFrame:Hide()
    end
    tickerActive = true
    activeDrag = nil
    idleMoverDirty = true; idleHUDDirty = true
    dirtyFlushGeneration = dirtyFlushGeneration + 1
    tickerFrame:SetScript("OnUpdate", nil)
    tickerFrame:Hide()
    ScheduleDirtyFlush(0)
end

function Ticker.Stop()
    tickerActive = false
    if activeDrag then SetActiveDragFlags(activeDrag, false) end
    activeDrag = nil
    idleMoverDirty = false; idleHUDDirty = false
    dirtyFlushScheduled = false
    dirtyFlushGeneration = dirtyFlushGeneration + 1
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides(true) end
    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", nil)
        tickerFrame:Hide()
    end
end

end

ExportPublic("MSUF_InstallEditLayoutUI", InstallEditLayoutUI)
