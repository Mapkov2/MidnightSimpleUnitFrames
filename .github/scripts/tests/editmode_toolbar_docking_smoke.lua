-- Runtime smoke for the compact Edit Mode toolbar and taskbar-style docking.
local root = arg and arg[1] or "."
local advanced = arg and arg[2] == "advanced"
local hudPath = root .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_HUD.lua"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function AnchorFraction(point)
    if point == "TOPLEFT" then return 0, 1 end
    if point == "TOP" then return 0.5, 1 end
    if point == "TOPRIGHT" then return 1, 1 end
    if point == "LEFT" then return 0, 0.5 end
    if point == "RIGHT" then return 1, 0.5 end
    if point == "BOTTOMLEFT" then return 0, 0 end
    if point == "BOTTOM" then return 0.5, 0 end
    if point == "BOTTOMRIGHT" then return 1, 0 end
    return 0.5, 0.5
end

local function Animation()
    local a = {}
    function a:SetFromAlpha() end
    function a:SetToAlpha() end
    function a:SetDuration() end
    function a:SetOrder() end
    function a:SetSmoothing() end
    return a
end

local function AnimationGroup()
    local group = {}
    function group:CreateAnimation() return Animation() end
    function group:SetLooping() end
    function group:Play() self.playing = true end
    function group:Stop() self.playing = false end
    return group
end

local function Widget(name, parent)
    local widget = {
        name = name,
        parent = parent,
        width = 1,
        height = 1,
        left = 0,
        bottom = 0,
        shown = true,
        alpha = 1,
        scale = 1,
        scripts = {},
        events = {},
    }
    function widget:SetParent(value) self.parent = value end
    function widget:GetParent() return self.parent end
    function widget:SetSize(width, height) self.width, self.height = width, height end
    function widget:SetWidth(width) self.width = width end
    function widget:SetHeight(height) self.height = height end
    function widget:GetWidth() return self.width end
    function widget:GetHeight() return self.height end
    function widget:GetLeft() return self.left end
    function widget:GetRight() return self.left + self.width * self.scale end
    function widget:GetBottom() return self.bottom end
    function widget:GetTop() return self.bottom + self.height * self.scale end
    function widget:GetCenter() return self.left + self.width * self.scale * 0.5, self.bottom + self.height * self.scale * 0.5 end
    function widget:ClearAllPoints() self.point = nil end
    function widget:SetPoint(point, relative, relativePoint, x, y)
        if type(relative) ~= "table" then
            y = relativePoint
            x = relative
            relative = self.parent or _G.UIParent
            relativePoint = point
        end
        relative = relative or self.parent or _G.UIParent
        relativePoint = relativePoint or point
        x, y = tonumber(x) or 0, tonumber(y) or 0
        local rfx, rfy = AnchorFraction(relativePoint)
        local fx, fy = AnchorFraction(point)
        local rx = (relative:GetLeft() or 0) + (relative:GetWidth() or 0) * rfx
        local ry = (relative:GetBottom() or 0) + (relative:GetHeight() or 0) * rfy
        self.left = rx + x - self.width * self.scale * fx
        self.bottom = ry + y - self.height * self.scale * fy
        self.point = { point, relative, relativePoint, x, y }
    end
    function widget:SetAllPoints(relative)
        relative = relative or self.parent or _G.UIParent
        self:SetSize(relative:GetWidth(), relative:GetHeight())
        self.left, self.bottom = relative:GetLeft(), relative:GetBottom()
    end
    function widget:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function widget:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function widget:IsShown() return self.shown == true end
    function widget:SetShown(value) if value then self:Show() else self:Hide() end end
    function widget:SetAlpha(value) self.alpha = value; self.alphaWrites = (self.alphaWrites or 0) + 1 end
    function widget:GetAlpha() return self.alpha end
    function widget:SetScale(value) self.scale = value end
    function widget:GetScale() return self.scale end
    function widget:SetText(value) self.text = value; self.textWrites = (self.textWrites or 0) + 1 end
    function widget:GetText() return self.text end
    function widget:SetTextColor() self.textColorWrites = (self.textColorWrites or 0) + 1 end
    function widget:SetJustifyH() end
    function widget:SetJustifyV() end
    function widget:SetFont() end
    function widget:SetShadowOffset() end
    function widget:SetShadowColor() end
    function widget:SetTexture() end
    function widget:SetColorTexture() end
    function widget:SetVertexColor() end
    function widget:SetBlendMode() end
    function widget:SetRotation() end
    function widget:SetSnapToPixelGrid() end
    function widget:SetTexelSnappingBias() end
    function widget:SetBackdrop() end
    function widget:SetBackdropColor() end
    function widget:SetBackdropBorderColor() end
    function widget:SetFrameStrata() end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel or 1 end
    function widget:SetMovable() end
    function widget:SetClampedToScreen() end
    function widget:EnableMouse() end
    function widget:EnableMouseWheel() end
    function widget:EnableKeyboard() end
    function widget:SetPropagateKeyboardInput() end
    function widget:RegisterForDrag() end
    function widget:RegisterForClicks() end
    function widget:SetHitRectInsets() end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:IsMouseOver() return false end
    function widget:CreateTexture() return Widget(nil, self) end
    function widget:CreateFontString() return Widget(nil, self) end
    function widget:CreateAnimationGroup() return AnimationGroup() end
    function widget:SetScript(kind, callback) self.scripts[kind] = callback end
    function widget:HookScript(kind, callback)
        local previous = self.scripts[kind]
        if previous then
            self.scripts[kind] = function(...)
                previous(...)
                callback(...)
            end
        else
            self.scripts[kind] = callback
        end
    end
    function widget:RegisterEvent(event) self.events[event] = true end
    function widget:UnregisterEvent(event) self.events[event] = nil end
    return widget
end

_G.UIParent = Widget("UIParent")
_G.UIParent:SetSize(1920, 1080)
_G.UIParent.left, _G.UIParent.bottom = 0, 0
_G.CreateFrame = function(_, name, parent)
    local frame = Widget(name, parent or _G.UIParent)
    if name then _G[name] = frame end
    return frame
end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = { SetOwner = function() end, SetText = function() end, Show = function() end, Hide = function() end }
_G.C_Timer = { After = function() end }
_G.GetTime = function() return 0 end
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
local unitNameQueries, realmNameQueries = 0, 0
_G.UnitName = function() unitNameQueries = unitNameQueries + 1; return "DockTester" end
_G.GetRealmName = function() realmNameQueries = realmNameQueries + 1; return "TestRealm" end
_G.MSUF_GlobalDB = {}
-- Grid/background are core Edit Mode controls and must remain available even
-- when the addon's advanced menu controls are hidden.
_G.MSUF_DB = {
    general = { hideAdvancedMenu = not advanced },
    gf_raid = { offsetX = 15, offsetY = 0, width = 220, height = 44 },
}

local MSUF = { LocaleRegistry = { enUS = {} } }
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local undoQueries, redoQueries = 0, 0
local EM2 = {
    Util = {
        SharedUI = function() return nil end,
        ApplyAllSettingsSafe = function() return true end,
        ApplySettingsForKeySafe = function() return true end,
    },
    State = {
        GetUnitKey = function() return "gf_raid" end,
        Exit = function() end,
        CancelAll = function() end,
    },
    Focus = {
        GetSelection = function() return "gf_raid", "layout" end,
        SetSelection = function() end,
        OpenFullSettings = function() return true end,
    },
    Snap = {
        enabled = true,
        IsEnabled = function() return _G.MSUF_EM2.Snap.enabled end,
        SetEnabled = function(value) _G.MSUF_EM2.Snap.enabled = value end,
    },
    Grid = {
        bgAlpha = 0.75,
        step = 32,
        enabled = true,
        GetBgAlpha = function() return _G.MSUF_EM2.Grid.bgAlpha end,
        SetBgAlpha = function(value) _G.MSUF_EM2.Grid.bgAlpha = value end,
        GetGridStep = function() return _G.MSUF_EM2.Grid.step end,
        SetGridStep = function(value) _G.MSUF_EM2.Grid.step = value end,
        GetEnabled = function() return _G.MSUF_EM2.Grid.enabled end,
        ToggleEnabled = function() _G.MSUF_EM2.Grid.enabled = not _G.MSUF_EM2.Grid.enabled end,
    },
    Undo = {
        CanUndo = function() undoQueries = undoQueries + 1; return false end,
        CanRedo = function() redoQueries = redoQueries + 1; return false end,
    },
    Popups = { IsAnyOpen = function() return false end },
    Movers = { SyncAll = function() end },
}
_G.MSUF_EM2 = EM2

local chunk, loadError = loadfile(hudPath)
Check(chunk ~= nil, loadError)
chunk("MidnightSimpleUnitFrames", MSUF)
Check(type(_G.MSUF_InstallEditModeHUD) == "function", "HUD installer was not exported")
_G.MSUF_InstallEditModeHUD("MidnightSimpleUnitFrames", MSUF)
Check(EM2.HUD and type(EM2.HUD.Show) == "function", "HUD API was not installed")
EM2.HUD.RefreshControls()
Equal(undoQueries + redoQueries, 0, "closed HUD performed history work before first show")

EM2.HUD.Show()
local toolbar = _G.MSUF_EM2_HUD
Check(toolbar and toolbar:IsShown(), "compact toolbar was not created")
Equal(toolbar:GetWidth(), advanced and 1480 or 1280, "top toolbar width")
Equal(toolbar:GetHeight(), 68, "top toolbar height")
Equal(toolbar:GetTop(), 1068, "top toolbar edge offset")
Check(toolbar.scripts.OnUpdate == nil, "toolbar added an idle OnUpdate")
local layoutEvents = _G.MSUF_EM2_HUD_LayoutEvents
Check(layoutEvents and layoutEvents.events.DISPLAY_SIZE_CHANGED and layoutEvents.events.UI_SCALE_CHANGED,
    "visible HUD did not register its layout events")

if advanced then
    local primary = _G.MSUF_EM2_HUD_PreviewAddonSlot:GetParent():GetParent()
    local discardLeft = toolbar:GetRight() - 192
    Check(primary:GetRight() <= discardLeft - 7.9, "advanced controls overlap Discard at full width")
    Equal(primary:GetScale(), 1, "advanced controls were unnecessarily scaled at full width")

    _G.UIParent:SetWidth(1280)
    layoutEvents.scripts.OnEvent(layoutEvents, "DISPLAY_SIZE_CHANGED")
    Equal(toolbar:GetWidth(), 1248, "narrow toolbar did not fit the screen")
    discardLeft = toolbar:GetRight() - 192
    Check(primary:GetScale() < 1, "narrow advanced controls did not reflow")
    Check(primary:GetRight() <= discardLeft - 7.9, "narrow advanced controls overlap Discard")

    _G.UIParent:SetWidth(1920)
    layoutEvents.scripts.OnEvent(layoutEvents, "DISPLAY_SIZE_CHANGED")
    Equal(primary:GetScale(), 1, "advanced controls did not restore full scale")
end

local saved = _G.MSUF_GlobalDB.char["DockTester-TestRealm"].editModeHUDState
saved.dock, saved.freeX, saved.freeY = "FREE", 80, -40
layoutEvents.scripts.OnEvent(layoutEvents, "DISPLAY_SIZE_CHANGED")
local freeX, freeY = toolbar:GetCenter()
Equal(freeX, 1040, "dragged toolbar horizontal position")
Equal(freeY, 500, "dragged toolbar vertical position")
if advanced then
    local primary = _G.MSUF_EM2_HUD_PreviewAddonSlot:GetParent():GetParent()
    Check(primary:GetRight() <= toolbar:GetRight() - 199.9, "dragged advanced controls overlap Discard")
end
saved.dock = "TOP"
layoutEvents.scripts.OnEvent(layoutEvents, "DISPLAY_SIZE_CHANGED")

local gridTools = _G.MSUF_EditModeGridTools
Check(gridTools and gridTools:IsShown(), "direct Grid/BG controls are missing from the toolbar")
Check(gridTools:GetParent() ~= _G.MSUF_EM2_HUD_Row2, "Grid/BG controls remained in the lower status row")
Equal(gridTools._clusterLabel and gridTools._clusterLabel:GetText(), "Layout", "Grid/BG controls left the Layout group")
Equal(#(gridTools._dockItems or {}), 4, "Layout group control count")
Equal(gridTools._dockItems[2], gridTools._gridWidget, "Grid is not between Snap and BG")
Equal(gridTools._dockItems[3], gridTools._bgWidget, "BG is not between Grid and Reset")
Equal(gridTools._stepFS and gridTools._stepFS:GetText(), "Grid 32px", "grid spacing label")
Equal(gridTools._alphaFS and gridTools._alphaFS:GetText(), "BG 75%", "background opacity label")
Check(gridTools.scripts.OnUpdate == nil, "Grid/BG controls added an idle OnUpdate")
Equal(_G.MSUF_EM2_HUD_Row2:GetHeight(), 40, "context status row height")
local inspector = _G.MSUF_EM2_HUD_Row2
Equal(inspector._inspectorSelection:GetWidth(), 176, "inspector selection width")
Equal(inspector._inspectorSelection:GetHeight(), 36, "inspector selection height")
Equal(inspector._inspectorSelectionFS:GetText(), "Raid Frames / Layout", "inspector selection label")
for i, expected in ipairs({ "X 15", "Y 0", "W 220", "H 44" }) do
    Equal(inspector._inspectorMetrics[i]._valueFS:GetText(), expected, "inspector metric " .. i)
end
local stepWrites, alphaWrites = gridTools._stepFS.textWrites, gridTools._alphaFS.textWrites
EM2.HUD.RefreshControls()
Equal(gridTools._stepFS.textWrites, stepWrites, "unchanged Grid value was rewritten")
Equal(gridTools._alphaFS.textWrites, alphaWrites, "unchanged BG value was rewritten")
gridTools._gridWidget.scripts.OnMouseWheel(gridTools._gridWidget, 1)
Equal(EM2.Grid.step, 36, "Grid mouse-wheel adjustment")
Equal(gridTools._stepFS:GetText(), "Grid 36px", "Grid label did not refresh after scrolling")
gridTools._gridWidget.scripts.OnMouseUp(gridTools._gridWidget, "LeftButton")
Equal(EM2.Grid.enabled, false, "Grid click did not toggle visibility")
gridTools._bgWidget.scripts.OnMouseWheel(gridTools._bgWidget, -1)
Equal(EM2.Grid.bgAlpha, 0.70, "BG mouse-wheel adjustment")
Equal(gridTools._alphaFS:GetText(), "BG 70%", "BG label did not refresh after scrolling")

local dock, snap, autoHide, offset = EM2.HUD.GetDockState()
Equal(dock, "TOP", "default dock")
Equal(snap, true, "default edge snapping")
Equal(autoHide, false, "default auto-hide")
Equal(offset, 12, "default edge offset")
Equal(unitNameQueries, 1, "dock character state was not cached")
Equal(realmNameQueries, 1, "dock realm state was not cached")

Check(EM2.HUD.SetDockPosition("BOTTOM") == true, "bottom dock was rejected")
Equal(toolbar:GetBottom(), 12, "bottom dock edge")
Check(EM2.HUD.SetDockPosition("LEFT") == true, "left dock was rejected")
Equal(toolbar:GetLeft(), 12, "left dock edge")
Equal(toolbar:GetWidth(), 82, "left dock width")
Equal(_G.MSUF_EM2_HUD_Row2:GetHeight(), 34, "vertical context status row height")
Check(EM2.HUD.SetDockPosition("RIGHT") == true, "right dock was rejected")
Equal(toolbar:GetRight(), 1908, "right dock edge")
Check(EM2.HUD.SetDockPosition("DIAGONAL") == false, "invalid dock was accepted")

Equal(EM2.HUD.SetDockEdgeOffset(24), 24, "edge offset setter")
Check(EM2.HUD.SetDockPosition("TOP") == true, "top redock failed")
Equal(toolbar:GetTop(), 1056, "updated top edge offset")
EM2.HUD.SetDockSnap(false)
EM2.HUD.SetDockAutoHide(true)
dock, snap, autoHide, offset = EM2.HUD.GetDockState()
Equal(snap, false, "snap preference did not persist")
Equal(autoHide, true, "auto-hide preference did not persist")

Check(EM2.HUD.ShowPositionSettings(true) == true, "position popup did not open")
local popup = _G.MSUF_EM2_HUD_PositionPopup
Check(popup and popup:IsShown(), "position popup frame is missing")
Equal(popup:GetHeight(), 326, "position popup height changed unexpectedly")
Check(popup.scripts.OnUpdate == nil, "position popup added an idle OnUpdate")
Check(EM2.HUD.ShowPositionSettings(false) == false, "position popup did not close")

Check(saved and saved.dock == "TOP" and saved.edgeOffset == 24 and saved.autoHide == true,
    "dock preferences were not persisted outside the active profile")

local sourceHandle = assert(io.open(hudPath, "rb"))
local source = sourceHandle:read("*a")
sourceHandle:close()
Check(not source:find('hudFrame:SetPoint("TOPLEFT", UIParent', 1, true),
    "legacy full-width top anchor returned")
Check(source:find('RegisterEvent("DISPLAY_SIZE_CHANGED")', 1, true)
    and source:find('RegisterEvent("UI_SCALE_CHANGED")', 1, true),
    "resolution/UI-scale reflow events are missing")

EM2.HUD.Hide()
Check(not layoutEvents.events.DISPLAY_SIZE_CHANGED and not layoutEvents.events.UI_SCALE_CHANGED,
    "hidden HUD retained layout event registrations")
local closedQueries = undoQueries + redoQueries
EM2.HUD.RefreshControls()
Equal(undoQueries + redoQueries, closedQueries, "hidden HUD performed history work")
inCombat = true
Check(EM2.HUD.Show() == false, "HUD opened during combat")
Check(not layoutEvents.events.DISPLAY_SIZE_CHANGED and not layoutEvents.events.UI_SCALE_CHANGED,
    "combat-blocked HUD registered layout events")
inCombat = false

print("PASS Edit Mode toolbar docking (" .. (advanced and "advanced" or "simple") .. "): responsive fit, four edges, event lifecycle, closed/combat zero-work, no idle OnUpdate")
