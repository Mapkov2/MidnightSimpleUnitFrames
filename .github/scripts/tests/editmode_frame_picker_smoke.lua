-- Runtime smoke for the Edit Mode toolbar frame picker.
--
-- Clicking a mover is the only other way to select an element, so a frame that sits
-- underneath another one is unreachable without this list. The picker therefore has
-- to stay independent of mover hit-testing: it must offer every placeable element,
-- and selecting one must open that element's popup anchored to its own mover.
local root = arg and arg[1] or "."
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

local created = {}

local function Widget(name, parent)
    local widget = {
        name = name, parent = parent,
        width = 1, height = 1, left = 0, bottom = 0,
        shown = true, alpha = 1, scale = 1,
        scripts = {}, events = {},
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
    function widget:GetCenter()
        return self.left + self.width * self.scale * 0.5, self.bottom + self.height * self.scale * 0.5
    end
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
    function widget:SetAlpha(value) self.alpha = value end
    function widget:GetAlpha() return self.alpha end
    function widget:SetScale(value) self.scale = value end
    function widget:GetScale() return self.scale end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
    function widget:SetJustifyH() end
    function widget:SetJustifyV() end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:SetFont() end
    function widget:SetShadowOffset() end
    function widget:SetShadowColor() end
    function widget:SetTexture() end
    function widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function widget:SetVertexColor() end
    function widget:SetBlendMode() end
    function widget:SetRotation() end
    function widget:SetSnapToPixelGrid() end
    function widget:SetTexelSnappingBias() end
    function widget:SetBackdrop() end
    function widget:SetBackdropColor() end
    function widget:SetBackdropBorderColor() end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel or 1 end
    function widget:SetMovable() end
    function widget:SetClampedToScreen(value) self.clamped = value end
    function widget:EnableMouse() end
    function widget:EnableMouseWheel() end
    function widget:EnableKeyboard() end
    function widget:SetPropagateKeyboardInput() end
    function widget:RegisterForDrag() end
    function widget:RegisterForClicks() end
    function widget:SetHitRectInsets() end
    function widget:StartMoving() end
    function widget:StopMovingOrSizing() end
    function widget:IsMouseOver() return false end
    function widget:CreateTexture() return Widget(nil, self) end
    function widget:CreateFontString() return Widget(nil, self) end
    function widget:CreateAnimationGroup() return AnimationGroup() end
    function widget:SetScript(kind, callback) self.scripts[kind] = callback end
    function widget:HookScript(kind, callback)
        local previous = self.scripts[kind]
        if previous then
            self.scripts[kind] = function(...) previous(...); callback(...) end
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
    created[#created + 1] = frame
    if name then _G[name] = frame end
    return frame
end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = { SetOwner = function() end, SetText = function() end, Show = function() end, Hide = function() end }
_G.C_Timer = { After = function() end }
_G.GetTime = function() return 0 end
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.UnitName = function() return "PickerTester" end
_G.GetRealmName = function() return "TestRealm" end
_G.MSUF_GlobalDB = {}
_G.MSUF_DB = {
    general = {},
    player = { offsetX = -256, offsetY = -180, width = 275, height = 40 },
    target = { offsetX = -256, offsetY = -180, width = 275, height = 40 },
    pet = { offsetX = 40, offsetY = 0, width = 180, height = 30 },
    gf_raid = { offsetX = 15, offsetY = 0, width = 220, height = 44 },
}
_G.MSUF_BlockConfigCombatLocked = function() return inCombat end

local MSUF = { LocaleRegistry = { enUS = {} } }
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

--- The toolbar builds its buttons through MSUF.UI, which in game hands them to the
--- Menu2 theme. That theme replaces SetScript and routes OnClick through a proxy
--- with its own combat gate, so a toolbar button only works if it survives that
--- indirection - test the real path, not a bare CreateFrame button.
local uiButtons = {}
MSUF.UI = {
    Button = function(parent, text, width, height, opts)
        opts = opts or {}
        local btn = _G.CreateFrame("Button", nil, parent)
        btn:SetSize(width or 120, height or 24)
        btn._msuf2Label = btn:CreateFontString()
        btn._msuf2Label:SetText(text)
        btn._msuf2RawSetScript = btn.SetScript
        btn.SetScript = function(self, scriptType, handler)
            if scriptType == "OnClick" then
                self._msuf2OnClickHandler = type(handler) == "function" and handler or nil
                return self._msuf2RawSetScript(self, scriptType, function(frame, ...)
                    if _G.MSUF_BlockConfigCombatLocked() then return end
                    local stored = frame._msuf2OnClickHandler
                    if stored then return stored(frame, ...) end
                end)
            end
            return self._msuf2RawSetScript(self, scriptType, handler)
        end
        if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
        uiButtons[text] = btn
        return btn
    end,
}

--- The registry stands in for the live Edit Mode elements. "target" deliberately
--- sits exactly on top of "player" (same offsets) - the situation the picker exists
--- for. "focus" has no live frame and "pet" is disabled, so neither may be listed.
local frames = {
    player = Widget("PlayerFrameStub"),
    target = Widget("TargetFrameStub"),
    pet = Widget("PetFrameStub"),
    gf_raid = Widget("RaidContainerStub"),
}
local movers = {
    player = Widget("PlayerMover"),
    target = Widget("TargetMover"),
    gf_raid = Widget("RaidMover"),
}
local registry = {
    player = { key = "player", label = "Player", order = 10, getFrame = function() return frames.player end },
    target = { key = "target", label = "Target", order = 20, getFrame = function() return frames.target end },
    focus = { key = "focus", label = "Focus", order = 30, getFrame = function() return nil end },
    pet = { key = "pet", label = "Pet", order = 50, getFrame = function() return frames.pet end,
            isEnabled = function() return false end },
    gf_raid = { key = "gf_raid", label = "Raid Frames", order = 70, getFrame = function() return frames.gf_raid end },
}

local selection = { key = "player" }
local opened = {}
local pulses = {}
local settingsOpened = {}
local EM2 = {
    Util = {
        SharedUI = function() return nil end,
        ApplyAllSettingsSafe = function() return true end,
        ApplySettingsForKeySafe = function() return true end,
    },
    State = {
        GetUnitKey = function() return selection.key end,
        SetUnitKey = function(key) selection.stateKey = key end,
        Exit = function() end,
        CancelAll = function() end,
    },
    Focus = {
        GetSelection = function() return selection.key end,
        SetSelection = function(key, _, _, opts)
            selection.key = key
            selection.source = opts and opts.source
            selection.openSettings = opts and opts.openSettings
            return true
        end,
        OpenFullSettings = function()
            settingsOpened[#settingsOpened + 1] = selection.key
            return true
        end,
        Pulse = function(key) pulses[#pulses + 1] = key end,
    },
    Registry = {
        Get = function(key) return registry[key] end,
        Order = function()
            local keys = {}
            for key in pairs(registry) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return registry[a].order < registry[b].order end)
            return keys
        end,
    },
    Movers = {
        Get = function(key) return movers[key] end,
        SyncAll = function() end,
    },
    Popups = {
        IsAnyOpen = function() return false end,
        Open = function(key, anchor) opened[#opened + 1] = { key = key, anchor = anchor } end,
    },
    Snap = { IsEnabled = function() return true end, SetEnabled = function() end },
    Grid = {
        GetBgAlpha = function() return 0.75 end, SetBgAlpha = function() end,
        GetGridStep = function() return 32 end, SetGridStep = function() end,
        GetEnabled = function() return true end, ToggleEnabled = function() end,
    },
    Undo = { CanUndo = function() return false end, CanRedo = function() return false end },
}
_G.MSUF_EM2 = EM2

local chunk, loadError = loadfile(hudPath)
Check(chunk ~= nil, loadError)
chunk("MidnightSimpleUnitFrames", MSUF)
Check(type(_G.MSUF_InstallEditModeHUD) == "function", "HUD installer was not exported")
_G.MSUF_InstallEditModeHUD("MidnightSimpleUnitFrames", MSUF)

local HUD = EM2.HUD
Check(HUD and type(HUD.ToggleFramePicker) == "function", "frame picker API was not installed")
HUD.Show()

local function PickerRows()
    local rows = {}
    for i = 1, #created do
        local frame = created[i]
        if frame._msufKey and frame:IsShown() then rows[#rows + 1] = frame end
    end
    return rows
end

-- The picker is closed until asked for: no rows exist before the first open.
Equal(#PickerRows(), 0, "frame picker built rows before it was opened")

--- Open it the way a user does: through the toolbar button's own click handler.
local contextBtn = uiButtons["Groups"]
Check(contextBtn, "toolbar context button was not built through MSUF.UI")
local contextClick = contextBtn.scripts.OnClick
Check(type(contextClick) == "function", "toolbar context button has no click handler")
contextClick(contextBtn, "LeftButton")

local rows = PickerRows()
Check(#rows > 0, "clicking the toolbar button did not open the frame picker")
local picker = rows[1].parent
Check(picker and picker:IsShown(), "frame picker frame is not shown")
Check(picker.clamped == true, "frame picker is not clamped to the screen")

local listed, order = {}, {}
for i = 1, #rows do
    listed[rows[i]._msufKey] = rows[i]
    order[#order + 1] = rows[i]._msufKey
end
Check(listed.player and listed.target, "picker omitted a placeable unit frame")
Check(listed.gf_raid, "picker omitted the group frame")
Check(not listed.focus, "picker listed an element without a live frame")
Check(not listed.pet, "picker listed a disabled element")
Equal(order[1], "player", "picker rows ignore the registry order")
Equal(order[#order], "gf_raid", "picker rows ignore the registry order")

-- The selected row is the one currently being edited.
local playerRowTint = listed.player._bg and listed.player._bg.colorTexture
local targetRowTint = listed.target._bg and listed.target._bg.colorTexture
Check(playerRowTint and playerRowTint[4] and playerRowTint[4] > 0, "current selection is not highlighted")
Check(targetRowTint and targetRowTint[4] == 0, "an unselected row was highlighted")

-- The point of the whole feature: reach the frame stacked underneath another one.
Equal(frames.target.left, frames.player.left, "test setup no longer stacks the frames")
listed.target.scripts.OnClick(listed.target)
Equal(selection.key, "target", "picking a row did not change the selection")
Equal(selection.source, "hud-picker", "selection did not record the picker as its source")
Equal(selection.stateKey, "target", "picking a row did not update the edit-mode state key")
Equal(#opened, 1, "picking a row did not open exactly one popup")
Equal(opened[1].key, "target", "picking a row opened the wrong popup")
Equal(opened[1].anchor, movers.target, "popup was not anchored to the picked element's mover")
Equal(pulses[#pulses], "target", "picked element was not pulsed")
Check(not picker:IsShown(), "frame picker stayed open after a pick")

-- Reopening follows the new selection.
HUD.ToggleFramePicker()
rows = PickerRows()
listed = {}
for i = 1, #rows do listed[rows[i]._msufKey] = rows[i] end
local newTint = listed.target._bg and listed.target._bg.colorTexture
Check(newTint and newTint[4] and newTint[4] > 0, "reopened picker did not follow the new selection")

-- Toggling closes it again, and hiding the HUD must not leave it floating.
HUD.ToggleFramePicker()
Check(not picker:IsShown(), "toggling did not close the frame picker")
HUD.ToggleFramePicker()
Check(picker:IsShown(), "toggling did not reopen the frame picker")
HUD.Hide()
Check(not picker:IsShown(), "frame picker survived the HUD being hidden")

-- The inspector row runs the same list with a different action: pure menu
-- navigation. It must not drag the mover popup along.
HUD.Show()
Check(type(HUD.ToggleMenuPicker) == "function", "inspector menu picker API is missing")
HUD.ToggleMenuPicker()
rows = PickerRows()
Check(#rows > 0, "inspector menu picker opened without any rows")
listed = {}
for i = 1, #rows do listed[rows[i]._msufKey] = rows[i] end
local popupsBefore = #opened
local pulsesBefore = #pulses
listed.gf_raid.scripts.OnClick(listed.gf_raid)
Equal(selection.key, "gf_raid", "menu pick did not change the selection")
Equal(selection.source, "hud-menu-picker", "menu pick did not record its own source")
Check(selection.openSettings == true, "menu pick did not request the settings page")
Equal(#settingsOpened, 1, "menu pick did not open exactly one settings page")
Equal(settingsOpened[1], "gf_raid", "menu pick opened the wrong settings page")
Equal(#opened, popupsBefore, "menu pick also opened a mover popup")
Equal(#pulses, pulsesBefore, "menu pick pulsed a frame instead of only navigating")
Check(not picker:IsShown(), "menu picker stayed open after a pick")

-- Both dropdowns share one list frame, so opening the other one hands it over
-- instead of leaving a stale owner behind.
HUD.ToggleFramePicker()
Check(picker:IsShown(), "toolbar picker did not take the shared list over")
HUD.ToggleMenuPicker()
Check(picker:IsShown(), "inspector picker did not take the shared list over")
HUD.ToggleMenuPicker()
Check(not picker:IsShown(), "clicking the owning button again did not close the list")

-- Combat is a hard stop: the list may open, but it must not move config around.
inCombat = true
HUD.ToggleFramePicker()
rows = PickerRows()
listed = {}
for i = 1, #rows do listed[rows[i]._msufKey] = rows[i] end
local openedBefore = #opened
local settingsBefore = #settingsOpened
listed.player.scripts.OnClick(listed.player)
Equal(#opened, openedBefore, "combat-locked pick opened a popup")
Equal(selection.key, "gf_raid", "combat-locked pick changed the selection")
HUD.ToggleMenuPicker()
rows = PickerRows()
listed = {}
for i = 1, #rows do listed[rows[i]._msufKey] = rows[i] end
listed.player.scripts.OnClick(listed.player)
Equal(#settingsOpened, settingsBefore, "combat-locked menu pick opened a settings page")
inCombat = false

-- The inspector row must actually be wired to the menu picker, not to the old
-- "open whatever is selected" action.
local hudHandle = assert(io.open(hudPath, "rb"))
local hudSource = hudHandle:read("*a")
hudHandle:close()
Check(hudSource:find('inspectorSelection:SetScript("OnClick", function() HUD.ToggleMenuPicker() end)', 1, true),
    "inspector row is no longer wired to the menu picker")

print("PASS Edit Mode frame picker: lists placeable elements only, reaches stacked frames, "
    .. "anchors to the picked mover, inspector row navigates settings only, shared list handover, "
    .. "follows selection, closes with the HUD, combat fail-closed")
