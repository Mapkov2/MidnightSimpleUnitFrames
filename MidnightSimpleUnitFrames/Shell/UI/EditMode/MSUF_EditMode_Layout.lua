--- EditMode/MSUF_EditMode_Layout.lua - Edit Mode layout, snap, and anchor helpers

--- MSUF_EM2_Grid.lua

--- MSUF_EM2_Grid.lua
--- Edit Mode 2 grid overlay.
--- Midnight-styled background, pooled grid lines, accent-colored crosshair.
--- Zero overhead when hidden (no OnUpdate, no timers).
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
    _G.MSUF_GridFrame = gridFrame

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

function Snap.IsEnabled()    return enabled end
function Snap.SetEnabled(v)  enabled = v and true or false end
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

function Snap.HideGuides()
    ClearActiveGuides(true)
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
    if not enabled then return cx, cy end

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
                    pcall(function()
                        frame:ClearAllPoints()
                        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
                    end)
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

    local previewTarget = GetPreviewNudgeTarget()
    if previewTarget then
        previewTarget:Nudge(ndx, ndy)
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(nil, true) end
        return
    end

    if EM2.CastPopup and EM2.CastPopup.IsOpen() then
        db.general = db.general or {}
        local g = db.general
        local castPF = _G.MSUF_EM2_CastPopup
        local unit = (EM2.CastPopup.GetUnit and EM2.CastPopup.GetUnit()) or (castPF and castPF.unit)
        if unit then
            local xKey, yKey = GetCastbarOffsetKeys(unit)
            if xKey and yKey then
                if _G.MSUF_EM_UndoBeforeChange then
                    _G.MSUF_EM_UndoBeforeChange("castbar", unit, true)
                end
                g[xKey] = floor(((tonumber(g[xKey]) or 0) + ndx) + 0.5)
                g[yKey] = floor(((tonumber(g[yKey]) or 0) + ndy) + 0.5)
                if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
                    _G.MSUF_ApplyCastbarUnitAndSync(unit)
                elseif _G.MSUF_UpdateCastbarVisuals then
                    _G.MSUF_UpdateCastbarVisuals()
                    EM2.CastPopup.Sync()
                end
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged and unit then EM2.Focus.NotifyPositionChanged("castbar_" .. tostring(unit), true) end
        RefreshUFPreview("EM2_CASTBAR_NUDGE", unit)
        return
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
                if type(_G.MSUF_Auras3_RefreshUnit) == "function" then
                    for _, k in ipairs(applyKeys) do _G.MSUF_Auras3_RefreshUnit(k) end
                elseif _G.MSUF_Auras3_RefreshAll then
                    _G.MSUF_Auras3_RefreshAll()
                end
                if auraPopupOpen and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
                local syncFn = _G.MSUF_SyncAuras3PositionPopup
                if type(syncFn) == "function" then syncFn(unitKey) end
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return
    end

    if EM2.Focus and EM2.Focus.NudgeSelection and EM2.Focus.NudgeSelection(ndx, ndy) then
        return
    end

    local key = EM2.State.GetUnitKey() or "player"
    if (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid")
        and type(_G.MSUF_GF_EM2_NudgePreview) == "function"
        and _G.MSUF_GF_EM2_NudgePreview(key, ndx, ndy)
    then
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
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
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    RefreshUFPreview("EM2_UNIT_NUDGE", key)
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
        owner.__msufPendingClear = false
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for i = 1, #NUDGE_DIRS do
        local dir = NUDGE_DIRS[i][1]
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

function _G.MSUF_EnableArrowKeyNudge(enable)
    if enable then Nudge.Enable() else Nudge.Disable() end
end

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

local GROUP_VALID_POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function ResolveGroupAnchor(conf)
    local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
    if type(name) == "string" and name ~= "" and name ~= "FREE" and name ~= "UIParent" then
        local UF = MSUF and MSUF.UF
        if UF and UF.frames and UF.frames[name] then return UF.frames[name] end
        if _G[name] then return _G[name] end
    end
    return UIParent
end

local function GroupAnchorPoint(conf)
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not GROUP_VALID_POINTS[point] then point = "CENTER" end
    return point
end

local function GroupOffsetFromCenter(bar, conf, centerX, centerY, gridDX, gridDY)
    local point = GroupAnchorPoint(conf)
    local anchor = ResolveGroupAnchor(conf)
    local ax, ay = PointXY(anchor, point)
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
local activeDrag
local idleSyncAcc = 0

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
        return false
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
        if type(rf) == "function" then
            rf()
        elseif type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
            _G.MSUF_ApplyCastbarUnitAndSync(d.castbarUnit)
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            _G.MSUF_UpdateCastbarVisuals()
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
    if changed then
        d.conf.offsetX = nextX
        d.conf.offsetY = nextY
    end
    bar._msufDragActive = true
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", targetCX, targetCY)
    local liveAnchor = bar._msufGFLiveAnchor
    local logicalAnchor = bar._msufGFLogicalAnchor
    local anchor = liveAnchor or logicalAnchor
    if anchor and anchor ~= bar and anchor.ClearAllPoints and anchor.SetPoint then
        anchor._msufDragActive = true
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", anchorCX, anchorCY)
    end
    return changed
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

local function OnUpdate(self, elapsed)
    if activeDrag then
        local d = activeDrag

        local sc = d.uiScale or UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx = mx / sc; my = my / sc

        local rawCX = mx + d.offX
        local rawCY = my + d.offY

        local snapCX, snapCY = rawCX, rawCY
        if d.snapEnabled and EM2.Snap then
            snapCX, snapCY = EM2.Snap.Apply(rawCX, rawCY, d.halfW, d.halfH, d.key)
        end

        snapCX = max(d.halfW, min(d.screenW - d.halfW, snapCX))
        snapCY = max(d.halfH, min(d.screenH - d.halfH, snapCY))

        d.mover:ClearAllPoints()
        d.mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            snapCX - d.halfW,
            snapCY + d.halfH - d.screenH)

        if d.mover._coordFS then
            d.mover._coordFS:SetText(format("%.0f, %.0f",
                round(snapCX - d.screenW * 0.5),
                round(snapCY - d.screenH * 0.5)))
        end

        if d.isCastbar then
            ApplyCastbarDragPosition(d, snapCX, snapCY)
            SyncCastbarPopupDuringDrag(d, elapsed)
            if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, false) end
            return
        end

        local bar = d.bar
        if bar and not IsConfigCombatLocked() then
            bar._msufDragActive = true
            local conf = d.conf

            if d.isGroupFrame then
                ApplyGroupDragPosition(d, snapCX, snapCY)
                if d.mover._coordFS then
                    d.mover._coordFS:SetText(format("%.0f, %.0f", conf.offsetX or 0, conf.offsetY or 0))
                end
            else
                local anchor = d.anchor
                local ax, ay = d.anchorCX, d.anchorCY
                if not (ax and ay) then
                    ax, ay = anchor:GetCenter()
                    d.anchorCX, d.anchorCY = ax, ay
                end
                if ax and ay then
                    local as = d.anchorScale or anchor:GetEffectiveScale() or 1
                    local fs = d.frameScale or bar:GetEffectiveScale() or 1
                    if as == 0 then as = 1 end; if fs == 0 then fs = 1 end

                    local desiredBarCX = snapCX + (d.barCenterDX or 0)
                    local desiredBarCY = snapCY + (d.barCenterDY or 0)

                    local barScreenCX = desiredBarCX * sc  --- sc = UIParent:GetEffectiveScale()
                    local barScreenCY = desiredBarCY * sc
                    local ancScreenCX = ax * as
                    local ancScreenCY = ay * as
                    local offX = (barScreenCX - ancScreenCX) / as
                    local offY = (barScreenCY - ancScreenCY) / as

                    if d.bossAdjX then offX = offX - d.bossAdjX end
                    if d.bossAdjY then offY = offY - d.bossAdjY end

                    local nextX = round(offX)
                    local nextY = round(offY)

                    local ecvRule = d.ecvRule

                    if d.usesECV and d.ecvFrame and ecvRule then
                        local ecv = d.ecvFrame
                        local point, relPoint, baseX, extraY = ecvRule[1], ecvRule[2], ecvRule[3] or 0, ecvRule[4] or 0
                        local ax2, ay2 = d.ecvAnchorX, d.ecvAnchorY
                        if not (ax2 and ay2) then
                            ax2, ay2 = PointXY(ecv, relPoint)
                            d.ecvAnchorX, d.ecvAnchorY = ax2, ay2
                        end
                        if ax2 and ay2 then
                            local pointDX, pointDY = PointOffsetFromCenter(point, d.barW, d.barH)
                            local fx2 = barScreenCX + pointDX * fs
                            local fy2 = barScreenCY + pointDY * fs
                            nextX = round((fx2 - ax2 * as) / as - baseX)
                            nextY = round((fy2 - ay2 * as) / as - extraY)
                        end
                        if conf.offsetX ~= nextX or conf.offsetY ~= nextY then
                            conf.offsetX = nextX
                            conf.offsetY = nextY
                            bar:ClearAllPoints()
                            bar:SetPoint(point, ecv, relPoint, baseX + conf.offsetX, conf.offsetY + extraY)
                        end
                    else
                        --- Normal path: CENTER-to-CENTER (same as PositionUnitFrame line 2429)
                        if conf.offsetX ~= nextX or conf.offsetY ~= nextY then
                            conf.offsetX = nextX
                            conf.offsetY = nextY
                            bar:ClearAllPoints()
                            bar:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
                        end
                    end
                    bar._msufDragActive = true
                end
            end
        end

        if d.isGroupFrame then
            SyncGFPopupDuringDrag(d, elapsed)
        else
            SyncUnitPopupDuringDrag(d, elapsed)
        end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, false) end
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

    local mL, mCX, mR, mB, mCY, mT = GetFrameEdgesUI(mover)
    if not mL then
        mL = mover:GetLeft() or 0; mR = mover:GetRight() or 0
        mT = mover:GetTop() or 0; mB = mover:GetBottom() or 0
        mCX = (mL + mR) * 0.5
        mCY = (mT + mB) * 0.5
    end

    local isCastbar = (cfg.popupType == "castbar") or (type(key) == "string" and key:sub(1, 8) == "castbar_")
    local castbarUnit = cfg.castbarUnit
    if isCastbar and (not castbarUnit or castbarUnit == "") then
        castbarUnit = key:sub(9)
    end

    local isGroupFrame = (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid") or (bar and bar._msufIsGroupFrame == true) or false
    local anchor = isCastbar and UIParent or (isGroupFrame and ResolveGroupAnchor(conf)) or ResolveAnchor(key, conf)

    local bossAdjX, bossAdjY
    if bar and conf and key and key:sub(1,4) == "boss" and bar.unit then
        local gbi = _G.MSUF_GetBossIndexFromToken
        local idx = (type(gbi) == "function" and gbi(bar.unit)) or 1
        if type(_G.MSUF_GetBossLayoutDelta) == "function" then
            bossAdjX, bossAdjY = _G.MSUF_GetBossLayoutDelta(idx, conf)
        else
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
                bossAdjY = step * spacing
            end
        end
    end

    local snapEnabled = EM2.Snap and EM2.Snap.IsEnabled and EM2.Snap.IsEnabled() or false
    --- Native StartMoving regressed live profiles because the overlay/db sync
    --- cost more than the manual drag path. Keep one predictable path.
    local uiScale = UIParent:GetEffectiveScale() or 1
    local anchorCX, anchorCY
    if anchor and anchor.GetCenter then
        anchorCX, anchorCY = anchor:GetCenter()
    end
    local anchorScale = (anchor and anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local frameScale = (bar and bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
    local barW = (bar and bar.GetWidth and bar:GetWidth()) or (mR - mL)
    local barH = (bar and bar.GetHeight and bar:GetHeight()) or (mT - mB)
    local barCenterDX, barCenterDY = 0, 0
    if bar then
        local _, bCX, _, _, bCY = GetFrameEdgesUI(bar)
        if bCX and bCY then
            barCenterDX = bCX - mCX
            barCenterDY = bCY - mCY
        end
    end
    local ecvAnchorX, ecvAnchorY
    local ecvRule = ECV_ANCHORS[key]
    local usesECV = false
    local ecvFrame
    if (not isCastbar) and ecvRule and conf then
        local db = _G.MSUF_DB
        local general = db and db.general
        local ecvFn = _G.MSUF_GetEffectiveCooldownFrame
        local ecv = (type(ecvFn) == "function" and ecvFn("EssentialCooldownViewer"))
            or _G["EssentialCooldownViewer"]
        if general and general.anchorToCooldown and ecv and anchor == ecv then
            usesECV = true
            ecvFrame = ecv
            ecvAnchorX, ecvAnchorY = PointXY(ecv, ecvRule[2])
        end
    end

    local castbarXKey, castbarYKey
    local castbarStartX, castbarStartY
    local castbarReanchorFunc
    if isCastbar then
        castbarXKey, castbarYKey = GetCastbarOffsetKeys(castbarUnit)
        local defX, defY = CastbarDefaultOffsets(castbarUnit)
        conf = conf or ((_G.MSUF_DB and _G.MSUF_DB.general) or nil)
        if conf then
            castbarStartX = tonumber(conf[castbarXKey]) or defX
            castbarStartY = tonumber(conf[castbarYKey]) or defY
        else
            castbarStartX, castbarStartY = defX, defY
        end
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

    activeDrag = {
        mover        = mover,
        key          = key,
        cfg          = cfg,
        bar          = bar,
        conf         = conf,
        anchor       = anchor,
        ecvRule      = ecvRule,
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
        popupSyncAcc = 0.05,
        isGroupFrame = isGroupFrame,
        isCastbar    = isCastbar,
        castbarUnit  = castbarUnit,
        castbarXKey  = castbarXKey,
        castbarYKey  = castbarYKey,
        castbarStartX = castbarStartX,
        castbarStartY = castbarStartY,
        castbarReanchorFunc = castbarReanchorFunc,
        snapEnabled  = snapEnabled,
        uiScale      = uiScale,
        anchorCX     = anchorCX,
        anchorCY     = anchorCY,
        anchorScale  = anchorScale,
        frameScale   = frameScale,
        barW         = barW,
        barH         = barH,
        barCenterDX  = barCenterDX,
        barCenterDY  = barCenterDY,
        usesECV      = usesECV,
        ecvFrame     = ecvFrame,
        ecvAnchorX   = ecvAnchorX,
        ecvAnchorY   = ecvAnchorY,
    }
end

function Ticker.EndDrag()
    if not activeDrag then return false end
    local d = activeDrag
    activeDrag = nil

    if d.bar then d.bar._msufDragActive = false end
    if d.bar and d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = false end
    if d.bar and d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = false end
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

    local mover = d.mover
    local mL, cx, mR, mB, cy, mT = GetFrameEdgesUI(mover)
    if not mL then
        mL = mover:GetLeft() or 0; mR = mover:GetRight() or 0
        mT = mover:GetTop() or 0; mB = mover:GetBottom() or 0
        cx = (mL + mR) * 0.5; cy = (mT + mB) * 0.5
    end
    local moved = abs(cx - d.startCX) > 0.5 or abs(cy - d.startCY) > 0.5

    if moved then
        if type(MSUF_DB) == "table" then
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general.hasMovedFramesInEditMode = true
        end
        if type(_G.MSUF_EditState) == "table" then
            _G.MSUF_EditState.hasMovedFramesInEditMode = true
        end
        local menu = (type(MSUF) == "table" and MSUF.MSUF2) or _G.MSUF2
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
            ApplyGroupDragPosition(d, cx, cy)
            if d.bar and not IsConfigCombatLocked() then
                pcall(function()
                    d.bar._msufDragActive = false
                    if d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = false end
                    if d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = false end
                end)
                d.bar._msufDragActive = false
                if d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = false end
                if d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = false end
            end
        end
        --- Offsets already written by OnUpdate. Just finalize pipeline.
        if d.isCastbar then
            if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
                _G.MSUF_ApplyCastbarUnitAndSync(d.castbarUnit)
            else
                ApplyCastbarDragPosition(d, cx, cy)
            end
            C_Timer.After(0.06, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
            if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                _G.MSUF_SyncCastbarPositionPopup(d.castbarUnit)
            end
            if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
            RefreshUFPreview("EM2_CASTBAR_DRAG_END", d.castbarUnit)
        elseif d.isGroupFrame then
            if type(_G.MSUF_GF_RefreshAll) == "function" and not IsConfigCombatLocked() then
                _G.MSUF_GF_RefreshAll()
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

end

_G.MSUF_InstallEditLayoutUI = InstallEditLayoutUI
