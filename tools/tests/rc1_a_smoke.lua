-- rc1_a_smoke.lua <repoRoot>
--
-- rc1 package A: MSUF code that hands Blizzard-owned frames back or changes
-- them must not leave MSUF taint in fields Blizzard reads later. Every case
-- loads the real product files; the Blizzard objects are modelled after the
-- exported client source (C:\tmp\rc1\ui\<client>, cited per case), and a
-- Blizzard mixin method called from MSUF counts as a field write, because the
-- mixin writes its fields with the caller's taint.
--
--   LB-1  Releasing the player castbar to Blizzard (provider "Blizzard", a
--         profile switch or import) registered the bar's cast events again
--         through CastingBarMixin:SetUnit(nil) / SetUnit(unit). SetUnit writes
--         unit, spellID, casting and friends (Blizzard_UIPanels_Game/Shared/
--         CastingBarFrame.lua:224-253 on ptr2 and forever); every later cast
--         read them tainted and laid out the bottom managed container. The
--         release now registers SetUnit's exact events through the frame's
--         own widget API and calls no mixin method.
--   LB-4  MSUF Edit Mode applied Damage Meter settings through DamageMeterMixin
--         setters (SetBarHeight, SetBarSpacing, SetWindowTransparency, ...;
--         Blizzard_DamageMeter/DamageMeter.lua:505-605 on ptr2). They store
--         plain fields the session windows read while painting secret combat
--         data, so the fields stayed tainted. MSUF now only saves those
--         settings (Blizzard's system mixin applies the layout at the next
--         load) and says a reload is needed; width and height still apply
--         live through SetSize, the frame's widget method.
--   FV-1  WoW Forever Gamepad UI: "Hide Blizzard Buff Frame" only reparented
--         BuffFrame below a hidden frame, so BuffFrame:IsShown() stayed true
--         and the pad's buff view (ui\forever Blizzard_BuffFrame/BuffFrame.lua
--         :473-477, GamepadRadial.lua:610-611, ShortcutsActionBar.lua:41,99)
--         focused an invisible buff list. On Forever the suppressed frame is
--         also hidden, and stays hidden when Blizzard's UpdateShownState shows
--         it again, without any script firing in MSUF code and without a field
--         write; the release gives the pad its buff view back. Midnight keeps
--         the reparent alone.
--   RP-1  Retail cee4a145f: an external Edit Mode element that registers with
--         centerPopup = true (the Suite's DataTexts movers) opens its popup
--         centred on UIParent and keeps it there through the popup's own
--         OnShow placement, the scale grip and its position save. Pinned on
--         the real Mainline boot (tools/tests/client_world.lua).
--
-- Plain Lua 5.1, repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Load(relative, namespace)
    local chunk = assert(loadfile(root .. "/" .. relative))
    chunk("MidnightSimpleUnitFrames", namespace)
end

---------------------------------------------------------------------------
-- LB-1: player castbar hand-back
---------------------------------------------------------------------------

-- CastingBarMixin:SetUnit's registrations (CastingBarFrame.lua:238-251 on
-- ptr2; the same list on live, forever, classic, classic_anniversary and
-- classic_era).
local SETUNIT_UNIT_EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
}
local CASTBAR_MIXIN_METHODS = {
    "SetUnit", "OnEvent", "OnShow", "UpdateShownState", "UpdateIsShown", "SetAndUpdateShowCastbar",
    "FinishSpell", "StopAnims", "HandleCastStart", "HandleCastStop",
}

-- A Blizzard castbar as the client builds it: PlayerCastingBarMixin:OnLoad ran
-- SetUnit("player", true, false), so the cast events are registered for the
-- player. Every field write and every mixin call MSUF makes is recorded.
local function NativeCastbar(name, managed)
    local fields = { unit = "player", showTradeSkills = true, showShield = false, isManagedFrame = managed or nil }
    local state = { name = name, events = {}, writes = {}, mixinCalls = {}, hooks = {},
        shown = false, alpha = 1, mouse = false }
    for index = 1, #SETUNIT_UNIT_EVENTS do state.events[SETUNIT_UNIT_EVENTS[index]] = "player" end
    state.events.PLAYER_ENTERING_WORLD = "all"
    local methods = {}
    function methods:RegisterEvent(event) state.events[event] = "all" end
    function methods:RegisterUnitEvent(event, unit) state.events[event] = unit or "all" end
    function methods:UnregisterEvent(event) state.events[event] = nil end
    function methods:UnregisterAllEvents() for event in pairs(state.events) do state.events[event] = nil end end
    function methods:HookScript(script, fn) state.hooks[script] = fn end
    function methods:IsShown() return state.shown end
    function methods:Show()
        state.shown = true
        if state.hooks.OnShow then state.hooks.OnShow(self) end
    end
    function methods:Hide()
        -- A shown managed bar runs the bottom container layout on OnHide.
        if managed and state.shown then error("MSUF hid the shown managed " .. name, 2) end
        state.shown = false
    end
    function methods:GetAlpha() return state.alpha end
    function methods:SetAlpha(alpha) state.alpha = alpha end
    function methods:IsMouseEnabled() return state.mouse end
    function methods:EnableMouse(enabled) state.mouse = enabled == true end
    for index = 1, #CASTBAR_MIXIN_METHODS do
        local method = CASTBAR_MIXIN_METHODS[index]
        methods[method] = function() state.mixinCalls[#state.mixinCalls + 1] = method end
    end
    local bar = setmetatable({}, {
        __index = function(_, key)
            if fields[key] ~= nil then return fields[key] end
            return methods[key]
        end,
        __newindex = function(_, key, value)
            state.writes[#state.writes + 1] = tostring(key)
            fields[key] = value
        end,
    })
    return bar, state
end

local function EventsAsSetUnitLeftThem(state)
    local count = 0
    for event, unit in pairs(state.events) do
        count = count + 1
        if event == "PLAYER_ENTERING_WORLD" then
            if unit ~= "all" then return false, event .. " registered for a unit" end
        elseif unit ~= "player" then
            return false, event .. " registered for " .. tostring(unit)
        end
    end
    for index = 1, #SETUNIT_UNIT_EVENTS do
        if state.events[SETUNIT_UNIT_EVENTS[index]] == nil then return false, SETUNIT_UNIT_EVENTS[index] .. " missing" end
    end
    if state.events.PLAYER_ENTERING_WORLD == nil then return false, "PLAYER_ENTERING_WORLD missing" end
    if count ~= #SETUNIT_UNIT_EVENTS + 1 then return false, count .. " events instead of " .. (#SETUNIT_UNIT_EVENTS + 1) end
    return true
end

local function RunCastbarHandBack(label, withGamepad, releaseInCombat)
    local backend = "MSUF"
    local inCombat = false
    local eventFrame
    _G.InCombatLockdown = function() return inCombat end
    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(_, fn) self.onEvent = fn end
        eventFrame = eventFrame or frame
        return frame
    end
    for _, name in ipairs({ "MSUF_IsCastbarEnabledForUnit", "MSUF_IsCastTimeEnabled", "MSUF_AreAnyCastbarsEnabled",
        "MSUF_Castbars_ForceHideAll", "MSUF_Castbars_OnSettingsChanged", "MSUF_Castbars_RunNextFrame",
        "MSUF_RegisterModule", "MSUF_EnsureDB", "CastingBarFrame", "GamepadPlayerCastingBarFrame" }) do
        _G[name] = nil
    end
    _G.MSUF_DB = { general = {} }
    local player, playerState = NativeCastbar("PlayerCastingBarFrame", true)
    local pad, padState
    _G.PlayerCastingBarFrame = player
    if withGamepad then
        -- ui\forever Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml:483:
        -- the gamepad bar inherits no managed template.
        pad, padState = NativeCastbar("GamepadPlayerCastingBarFrame", false)
        _G.GamepadPlayerCastingBarFrame = pad
    end
    local ns = {
        ExportPublic = function(name, value) _G[name] = value; return value end,
        MSUF_CastbarBackend = { Resolve = function() return backend end },
    }
    Load("MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Bridge.lua", ns)
    Check(eventFrame and eventFrame.onEvent, label .. ": the Bridge built no ownership event frame")
    if not (eventFrame and eventFrame.onEvent) then return end

    -- Login with the default profile: MSUF owns the player castbar.
    eventFrame.onEvent(eventFrame, "PLAYER_LOGIN")
    Check(next(playerState.events) == nil and playerState.alpha == 1,
        label .. ": the login takeover did not detach PlayerCastingBarFrame's cast events")

    -- The player picks Blizzard as the player castbar (menu, profile switch or import).
    backend = "BLIZZARD"
    if releaseInCombat then
        inCombat = true
        Check(_G.MSUF_ApplyBlizzardCastbarOwnership() == false, label .. ": a combat release did not defer")
        Check(next(playerState.events) == nil, label .. ": a combat release touched the bar before combat ended")
        inCombat = false
        Check(eventFrame.events.PLAYER_REGEN_ENABLED == true, label .. ": the deferred release waits for no combat end")
        eventFrame.onEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    else
        _G.MSUF_ApplyBlizzardCastbarOwnership()
    end

    local states = { playerState, padState }
    for index = 1, #states do
        local state = states[index]
        if state then
            Check(#state.mixinCalls == 0, label .. ": the release called CastingBarMixin:"
                .. table.concat(state.mixinCalls, ", ") .. " on " .. state.name .. " from MSUF code")
            Check(#state.writes == 0, label .. ": MSUF wrote " .. table.concat(state.writes, ", ")
                .. " on " .. state.name)
            local ok, why = EventsAsSetUnitLeftThem(state)
            Check(ok, label .. ": " .. state.name .. " did not get SetUnit's cast events back: " .. tostring(why))
        end
    end
    _G.PlayerCastingBarFrame, _G.GamepadPlayerCastingBarFrame, _G.CreateFrame = nil, nil, nil
end

RunCastbarHandBack("LB-1 Midnight", false, false)
RunCastbarHandBack("LB-1 Forever", true, false)
RunCastbarHandBack("LB-1 combat-deferred release", true, true)

---------------------------------------------------------------------------
-- LB-4: Damage Meter settings from MSUF Edit Mode
---------------------------------------------------------------------------

-- Enum values from ptr2 EditModeManagerConstantsDocumentation.lua.
local SYSTEM = { Minimap = 2, ChatFrame = 8, HudTooltip = 11, MicroMenu = 13, Bags = 14, DamageMeter = 23 }
local METER = {
    FrameWidth = 3, FrameHeight = 4, Padding = 5, Transparency = 6,
    ShowSpecIcon = 8, ShowClassColor = 9, BarHeight = 10, TextSize = 11, BackgroundTransparency = 12,
}
-- DamageMeterMixin and EditModeDamageMeterSystemMixin methods that store
-- fields (ptr2 DamageMeter.lua:505-605, EditModeSystemTemplates.lua:3489-3542).
local METER_MIXIN_SETTERS = {
    "SetBarHeight", "SetBarSpacing", "SetWindowTransparency", "SetWindowAlpha", "SetBackgroundTransparency",
    "SetBackgroundAlpha", "SetTextSize", "SetTextScale", "SetShowBarIcons", "SetUseClassColor", "SetStyle",
    "SetNumberDisplayType", "UpdateSystemSetting", "UpdateSystemSettingBarHeight", "RefreshLayout",
}

local function DamageMeterFrame()
    local fields = { system = SYSTEM.DamageMeter }
    local state = { writes = {}, mixinCalls = {}, width = 300, height = 200 }
    local methods = {}
    function methods:GetScale() return 1 end
    function methods:ClearAllPoints() end
    function methods:SetPoint() end
    function methods:SetSize(width, height) state.width, state.height = width, height end
    function methods:GetWidth() return state.width end
    function methods:GetHeight() return state.height end
    for index = 1, #METER_MIXIN_SETTERS do
        local method = METER_MIXIN_SETTERS[index]
        methods[method] = function() state.mixinCalls[#state.mixinCalls + 1] = method end
    end
    local frame = setmetatable({}, {
        __index = function(_, key)
            if fields[key] ~= nil then return fields[key] end
            return methods[key]
        end,
        __newindex = function(_, key, value)
            state.writes[#state.writes + 1] = tostring(key)
            fields[key] = value
        end,
    })
    return frame, state
end

local function RunDamageMeterSettings()
    local label = "LB-4"
    _G.Enum = {
        EditModeSystem = SYSTEM,
        EditModePresetLayoutsMeta = { NumValues = 2 },
        EditModeMinimapSetting = { HeaderUnderneath = 0, RotateMinimap = 1, Size = 2 },
        EditModeChatFrameSetting = { WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 },
        EditModeMicroMenuSetting = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 },
        EditModeBagsSetting = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 },
        EditModeDamageMeterSetting = METER,
        EditModeLayoutType = { Account = 1, Character = 2 },
        MicroMenuOrientation = { Horizontal = 0, Vertical = 1 },
        MicroMenuOrder = { Default = 0, Reverse = 1 },
        BagsOrientation = { Horizontal = 0, Vertical = 1 },
    }
    local created = {}
    local function PlainFrame(systemId)
        local frame = { system = systemId, events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, fn) self.onEvent = fn end
        function frame:GetScale() return 1 end
        function frame:ClearAllPoints() end
        function frame:SetPoint() end
        return frame
    end
    _G.CreateFrame = function()
        local frame = PlainFrame(nil)
        created[#created + 1] = frame
        return frame
    end
    _G.UIParent = PlainFrame(nil)
    local meter, meterState = DamageMeterFrame()
    _G.EditModeManagerFrame = { registeredSystemFrames = { PlainFrame(SYSTEM.Minimap), meter } }
    _G.InCombatLockdown = function() return false end
    local function Row(setting, value) return { setting = setting, value = value } end
    local meterEntry = {
        system = SYSTEM.DamageMeter,
        anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
        settings = { Row(METER.FrameWidth, 100), Row(METER.FrameHeight, 80), Row(METER.BarHeight, 5),
            Row(METER.Padding, 2), Row(METER.Transparency, 50), Row(METER.BackgroundTransparency, 80),
            Row(METER.TextSize, 5), Row(METER.ShowSpecIcon, 1), Row(METER.ShowClassColor, 1) },
    }
    local layoutInfo = { activeLayout = 3, layouts = { { layoutName = "Mine", layoutType = 1, systems = { meterEntry } } } }
    local saves = 0
    _G.C_EditMode = {
        GetLayouts = function() return layoutInfo end,
        SaveLayouts = function(info)
            Check(info == layoutInfo, label .. ": the adapter saved a detached layout table")
            saves = saves + 1
        end,
        SetActiveLayout = function(index) layoutInfo.activeLayout = index end,
    }
    local registered = {}
    _G.MSUF_EditModeAPI = {
        RegisterElement = function(_, element) registered[element.id] = element; return true end,
        UnregisterOwner = function() return true end,
        RegisterSessionListener = function() return true end,
        RefreshOwner = function() return true end,
    }
    local general
    _G.MSUF_GetGeneralDB = function() return general end
    _G.MSUF_EM2 = { Registry = {} }
    local statuses = {}
    _G.MSUF_EM2_SetHUDStatus = function(text) statuses[#statuses + 1] = text end
    local ns = {
        ExportPublic = function(name, value) _G[name] = value; return value end,
        Client = { IsForever = false, SupportsEvent = function() return true end },
    }
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    RequireFixture.Install(root, ns)
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", ns)
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua", ns)
    general = { blizzardEditModeIntegration = true, blizzardEditModeSnapshot = {} }
    for _, frame in ipairs(created) do
        if frame.events.PLAYER_LOGIN and frame.onEvent then frame.onEvent(frame, "PLAYER_LOGIN") end
    end
    local element = registered.damagemeter
    Check(element ~= nil, label .. ": the Damage Meter element was not registered")
    if not element then return end
    local function Control(id)
        for _, control in ipairs(element.extraControls or {}) do
            if control.id == id then return control end
        end
        error(label .. ": missing Damage Meter control " .. id)
    end
    local function Stored(setting)
        for _, row in ipairs(meterEntry.settings) do
            if row.setting == setting then return row.value end
        end
    end
    local function CheckUntouched(context)
        Check(#meterState.mixinCalls == 0, label .. " " .. context .. ": MSUF called DamageMeter "
            .. table.concat(meterState.mixinCalls, ", ") .. " from addon code")
        Check(#meterState.writes == 0, label .. " " .. context .. ": MSUF wrote " .. table.concat(meterState.writes, ", ")
            .. " on DamageMeter")
        meterState.mixinCalls, meterState.writes = {}, {}
    end

    -- Each deferred setting: saved in the layout, nothing called on the meter,
    -- one reload hint per real change and none for an unchanged value.
    local appliedAtLoad = {}
    for _, row in ipairs(meterEntry.settings) do appliedAtLoad[row.setting] = row.value end
    local cases = {
        { id = "barheight", value = 30, setting = METER.BarHeight, raw = 15 },
        { id = "padding", value = 8, setting = METER.Padding, raw = 6 },
        { id = "transparency", value = 80, setting = METER.Transparency, raw = 30 },
        { id = "bgtransparency", value = 40, setting = METER.BackgroundTransparency, raw = 40 },
        { id = "textsize", value = 120, setting = METER.TextSize, raw = 7 },
        { id = "specicon", value = false, setting = METER.ShowSpecIcon, raw = 0 },
        { id = "classcolor", value = false, setting = METER.ShowClassColor, raw = 0 },
    }
    for _, case in ipairs(cases) do
        local before = #statuses
        Check(Control(case.id).set(case.value) == true, label .. ": " .. case.id .. " did not commit")
        Check(Stored(case.setting) == case.raw, label .. ": " .. case.id .. " saved raw "
            .. tostring(Stored(case.setting)) .. ", expected " .. case.raw)
        CheckUntouched(case.id)
        Check(#statuses == before + 1 and statuses[#statuses] == "Requires a UI reload.",
            label .. ": " .. case.id .. " did not say the change needs a UI reload")
        local afterChange = #statuses
        Control(case.id).set(case.value)
        Check(#statuses == afterChange, label .. ": an unchanged " .. case.id .. " still asked for a reload")
    end

    -- Undo back to what the meter applied at load: saved, and no reload hint
    -- (the meter never showed the undone values).
    local undoState = element.captureState()
    undoState.settings = undoState.settings or {}
    for _, case in ipairs(cases) do undoState.settings[case.setting] = appliedAtLoad[case.setting] end
    local beforeUndo = #statuses
    Check(element.restoreState(undoState) == true, label .. ": the undo to the applied settings did not commit")
    Check(Stored(METER.BarHeight) == appliedAtLoad[METER.BarHeight], label .. ": the undo did not save the applied bar height")
    Check(#statuses == beforeUndo, label .. ": undoing to the applied Damage Meter settings still asked for a reload")
    CheckUntouched("undo to applied")

    -- Width and height stay live through the widget method, without a hint.
    local before = #statuses
    Check(Control("width").set(350) == true and Control("height").set(260) == true,
        label .. ": width or height did not commit")
    Check(meterState.width == 350 and meterState.height == 260, label .. ": the size did not apply live ("
        .. tostring(meterState.width) .. " x " .. tostring(meterState.height) .. ")")
    Check(#statuses == before, label .. ": a size change asked for a reload")
    CheckUntouched("size")

    -- Undo (restoreState with settings) and an imported profile snapshot.
    local captured = element.captureState()
    captured.settings = captured.settings or {}
    captured.settings[METER.BarHeight] = 3
    Check(element.restoreState(captured) == true, label .. ": restoreState did not commit")
    Check(Stored(METER.BarHeight) == 3, label .. ": restoreState did not save the bar height")
    CheckUntouched("restoreState")
    general.blizzardEditModeSnapshot.damagemeter = {
        point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 10, y = 20,
        settings = { [METER.BarHeight] = 9, [METER.Padding] = 1, [METER.ShowClassColor] = 1 },
    }
    Check(_G.MSUF_BlizzardEditMode_ApplyProfileSnapshot() == true, label .. ": the profile snapshot did not apply")
    Check(Stored(METER.BarHeight) == 9 and Stored(METER.ShowClassColor) == 1,
        label .. ": the profile snapshot did not save the Damage Meter settings")
    CheckUntouched("profile snapshot")
    Check(saves > 0, label .. ": nothing was saved")
end

RunDamageMeterSettings()

---------------------------------------------------------------------------
-- FV-1: Forever Gamepad UI and the suppressed BuffFrame
---------------------------------------------------------------------------

-- Widgets with the client's visibility rules: IsShown is the frame's own flag,
-- IsVisible walks the parents, and OnShow/OnHide fire only when the visibility
-- actually changes (a Show below a hidden parent fires nothing).
local function NewWidgetWorld()
    local world = { state = {}, dispatches = {} }
    local state = world.state
    local methods = {}
    local function Visible(frame)
        while frame do
            local s = state[frame]
            if not s.shown then return false end
            frame = s.parent
        end
        return true
    end
    local function Collect(frame, list)
        list[#list + 1] = frame
        for _, child in ipairs(state[frame].children) do Collect(child, list) end
        return list
    end
    local function Change(frame, mutate)
        local subtree = Collect(frame, {})
        local before = {}
        for index = 1, #subtree do before[index] = Visible(subtree[index]) end
        mutate(state[frame])
        for index = 1, #subtree do
            local node, now = subtree[index], Visible(subtree[index])
            if now ~= before[index] then
                local script = now and "OnShow" or "OnHide"
                if state[node].name == "BuffFrame" then world.dispatches[#world.dispatches + 1] = script end
                for _, handler in ipairs(state[node].scripts[script] or {}) do handler(node) end
            end
        end
    end
    function methods:Show() Change(self, function(s) s.shown = true end) end
    function methods:Hide() Change(self, function(s) s.shown = false end) end
    function methods:SetShown(shown) Change(self, function(s) s.shown = shown and true or false end) end
    function methods:IsShown() return state[self].shown end
    function methods:IsVisible() return Visible(self) end
    function methods:GetParent() return state[self].parent end
    function methods:SetParent(parent)
        Change(self, function(s)
            local old = s.parent
            if old then
                local siblings = state[old].children
                for index = #siblings, 1, -1 do
                    if siblings[index] == self then table.remove(siblings, index) end
                end
            end
            s.parent = parent
            if parent then table.insert(state[parent].children, self) end
        end)
    end
    function methods:IsProtected() return false end
    function methods:IsForbidden() return false end
    function methods:SetAllPoints() end
    function methods:SetScript(script, handler) state[self].scripts[script] = { handler } end
    function methods:HookScript(script, handler)
        local list = state[self].scripts[script] or {}
        list[#list + 1] = handler
        state[self].scripts[script] = list
    end
    function methods:RegisterEvent() end
    function methods:UnregisterEvent() end
    function methods:UnregisterAllEvents() end
    function world.Widget(name, parent, fields, writes)
        fields = fields or {}
        local frame = setmetatable({}, {
            __index = function(_, key)
                if fields[key] ~= nil then return fields[key] end
                return methods[key]
            end,
            __newindex = function(_, key, value)
                if writes then writes[#writes + 1] = tostring(key) end
                fields[key] = value
            end,
        })
        state[frame] = { name = name, shown = true, parent = nil, children = {}, scripts = {} }
        if parent then frame:SetParent(parent) end
        world.dispatches = {}
        return frame, fields
    end
    return world
end

local function RunForeverBuffFrame(label, isForever)
    local world = NewWidgetWorld()
    local uiParent = world.Widget("UIParent", nil)
    _G.UIParent = uiParent
    _G.CreateFrame = function(_, _, parent) return (world.Widget("MSUFHiddenParent", parent)) end
    _G.InCombatLockdown = function() return false end
    local setShownHooks = 0
    _G.hooksecurefunc = function(target, method, hook)
        if type(target) == "string" then return end
        if method == "SetShown" then setShownHooks = setShownHooks + 1 end
        local original = target[method]
        rawset(target, method, function(...)
            original(...)
            hook(...)
        end)
    end
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    local focused = {}
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function(_, frame) focused[#focused + 1] = frame end } }

    -- Blizzard's BuffFrame (ui\forever Blizzard_BuffFrame/BuffFrame.lua):
    -- HasActiveAura :311-313, ShouldBeShown :380-400, UpdateShownState
    -- :402-410, BaseAuraFrameMixin:SetGamepadFocus :473-478.
    local msufWrites = {}
    local buffFrame, buffFields = world.Widget("BuffFrame", uiParent, {}, msufWrites)
    buffFields.auraInfo = { { name = "Power Word: Fortitude" } }
    buffFields.visibleSetting = "Always"
    buffFields.updates = 0
    function buffFields:HasActiveAura() return #self.auraInfo >= 1 end
    function buffFields:IsEditing() return self.isInEditMode end
    function buffFields:ShouldBeShown()
        if self:IsEditing() then return true end
        if self.visibleSetting == "Hidden" then return false end
        return true
    end
    function buffFields:Update() buffFields.updates = buffFields.updates + 1 end
    function buffFields:UpdateShownState()
        local shouldBeShown = self:ShouldBeShown()
        if shouldBeShown ~= self:IsShown() then
            self:SetShown(shouldBeShown)
            if shouldBeShown then self:Update() end
        end
    end
    function buffFields:SetGamepadFocus()
        if InputUtil.IsGamepadUIEnabled() and self:IsShown() and self:HasActiveAura() then
            GamepadMode.FrameControlsManager:FrameShown(self)
            return true
        end
    end
    local debuffFrame, debuffFields = world.Widget("DebuffFrame", uiParent)
    debuffFields.auraInfo = {}
    debuffFields.HasActiveAura, debuffFields.SetGamepadFocus = buffFields.HasActiveAura, buffFields.SetGamepadFocus
    debuffFields.AuraContainer = world.Widget("DebuffFrame.AuraContainer", debuffFrame)
    _G.BuffFrame, _G.DebuffFrame = buffFrame, debuffFrame
    world.dispatches = {}

    -- The pad's two ways into the buff view.
    local function ShortcutsButtonEnabled() -- ShortcutsActionBar.lua:41
        return (_G.BuffFrame and _G.BuffFrame:IsShown() and _G.BuffFrame:HasActiveAura()) and true or false
    end
    local function RadialBuffs() -- GamepadRadial.lua:610-611
        focused = {}
        if _G.BuffFrame:HasActiveAura() or _G.DebuffFrame:HasActiveAura() then
            if not _G.BuffFrame:SetGamepadFocus() then _G.DebuffFrame:SetGamepadFocus() end
        end
        return focused[1]
    end

    _G.MSUF_DB = { general = {}, auras3 = { shared = { hideBlizzardBuffFrame = true } } }
    _G.MSUF_GetGeneralDB = function() return _G.MSUF_DB.general end
    local ns = { Client = { IsForever = isForever } }
    Load("MidnightSimpleUnitFrames/Kernel/MSUF_BlizzardFrames.lua", ns)
    local apply = ns.UF.ApplyBlizzardAuraVisibility

    apply()
    Check(buffFrame:GetParent() ~= uiParent and not buffFrame:IsVisible(),
        label .. ": the buff frame is no longer suppressed below the hidden parent")
    if not isForever then
        Check(buffFrame:IsShown() and setShownHooks == 0,
            label .. ": Midnight changed more than the reparent (shown " .. tostring(buffFrame:IsShown())
            .. ", SetShown hooks " .. setShownHooks .. ")")
        return
    end
    Check(not buffFrame:IsShown(), label .. ": the suppressed BuffFrame still reports shown to the Gamepad UI")
    Check(not ShortcutsButtonEnabled(), label .. ": the shortcuts bar still offers the invisible buff view")
    Check(RadialBuffs() ~= buffFrame, label .. ": the radial Buffs segment focused the invisible BuffFrame")
    Check(table.concat(world.dispatches, ",") == "OnHide",
        label .. ": the takeover fired BuffFrame " .. table.concat(world.dispatches, ",") .. " (only the reparent's OnHide is expected)")

    -- Blizzard shows it again on a combat change (PLAYER_IN_COMBAT_CHANGED).
    world.dispatches = {}
    buffFrame:UpdateShownState()
    Check(not buffFrame:IsShown(), label .. ": Blizzard's UpdateShownState put the suppressed BuffFrame back on the pad")
    Check(buffFields.updates == 1, label .. ": Blizzard's UpdateShownState did not run its own update after the SetShown")
    Check(#world.dispatches == 0, label .. ": hiding it again fired BuffFrame " .. table.concat(world.dispatches, ","))
    Check(not ShortcutsButtonEnabled() and RadialBuffs() ~= buffFrame,
        label .. ": after a combat change the pad reaches the invisible BuffFrame")

    -- Profile applies repeat the pass; the secure hook is installed once.
    apply()
    apply()
    Check(setShownHooks == 1, label .. ": BuffFrame:SetShown was hooked " .. setShownHooks .. " times")

    -- Turning the option off hands the pad its buff view back.
    _G.MSUF_DB.auras3.shared.hideBlizzardBuffFrame = false
    apply()
    Check(buffFrame:GetParent() == uiParent and buffFrame:IsShown() and buffFrame:IsVisible(),
        label .. ": the release did not give the buff frame back")
    Check(ShortcutsButtonEnabled() and RadialBuffs() == buffFrame, label .. ": the released BuffFrame is not on the pad")

    -- Blizzard's own visibility rule says hidden while MSUF owns the frame.
    _G.MSUF_DB.auras3.shared.hideBlizzardBuffFrame = true
    apply()
    buffFields.visibleSetting = "Hidden"
    buffFrame:UpdateShownState()
    _G.MSUF_DB.auras3.shared.hideBlizzardBuffFrame = false
    apply()
    Check(not buffFrame:IsShown(), label .. ": the release showed a BuffFrame Blizzard's visibility rule hides")
    Check(#msufWrites == 0, label .. ": MSUF wrote " .. table.concat(msufWrites, ", ") .. " on BuffFrame")
end

RunForeverBuffFrame("FV-1 Forever", true)
RunForeverBuffFrame("FV-1 Midnight", false)
_G.BuffFrame, _G.DebuffFrame, _G.InputUtil, _G.GamepadMode, _G.hooksecurefunc = nil, nil, nil, nil, nil

---------------------------------------------------------------------------
-- RP-1: centred external Edit Mode popup
---------------------------------------------------------------------------

local function RunCenteredExternalPopup()
    local label = "RP-1"
    local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
    local world = World.New(root, "Mainline"):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, label .. ": boot failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    if failure then return end
    local env = world.env
    -- The popup shell's edit boxes (MSUF_EditPopupUI.lua) need the EditBox surface.
    for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetNumeric",
        "SetMaxLetters", "SetCursorPosition", "HighlightText", "SetTextInsets", "SetMultiLine",
        "SetCountInvisibleLetters", "SetDisabledTexture", "SetCheckedTexture", "ClearFocus", "SetFocus", "HasFocus" }) do
        if world.widgets.Methods[name] == nil then world.widgets.Methods[name] = function() end end
    end
    env.MSUF_InitProfiles()
    local EM2 = env.MSUF_EM2
    local API = env.MSUF_EditModeAPI
    local function Register(id, centerPopup)
        local target = env.CreateFrame("Frame", "Smoke" .. id, env.UIParent)
        target.left, target.bottom, target.width, target.height = 400, 300, 120, 40
        local ok, reason = API.RegisterElement("Smoke.DataTexts", {
            id = id, label = "Smoke " .. id, centerPopup = centerPopup,
            getFrame = function() return target end,
            getPosition = function() return 10, 20 end,
            setPosition = function() return true end,
        })
        Check(ok, label .. ": RegisterElement refused " .. id .. ": " .. tostring(reason))
        return "external:smoke.datatexts:" .. id
    end
    local centredKey = Register("clock", true)
    local plainKey = Register("gold", nil)
    Check(EM2.State.Enter("player") == true, label .. ": Edit Mode did not open")
    world.widgets:RunTimers()

    local function Popup()
        for _, frame in ipairs(world.widgets.frames) do
            if frame.frameName == "MSUF_EM2_ExternalPopup" then return frame end
        end
    end
    local function Centred(frame)
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        return frame:GetNumPoints() == 1 and point == "CENTER" and relativeTo == env.UIParent
            and relativePoint == "CENTER" and x == 0 and y == 0
    end
    local function ShowAndPlace(frame)
        -- The stub widgets fire no OnShow; the client does, and the scale
        -- grip's OnShow hook places the popup one frame later.
        if frame.scripts.OnShow then frame.scripts.OnShow(frame) end
        world.widgets:RunTimers()
    end

    Check(EM2.ExternalPopup.Open(centredKey) == true, label .. ": the centred element's popup did not open")
    local popup = Popup()
    Check(popup ~= nil, label .. ": no external popup frame")
    if not popup then return end
    Check(Centred(popup), label .. ": a centerPopup element's popup did not open centred on UIParent")
    ShowAndPlace(popup)
    Check(Centred(popup), label .. ": the popup's OnShow placement moved a centerPopup popup off the centre")
    local grip = popup._msufEM2ScaleGrip
    Check(grip ~= nil and grip.scripts.OnMouseDown ~= nil, label .. ": the external popup has no scale grip")
    if grip and grip.scripts.OnMouseDown then
        popup.left, popup.bottom, popup.width, popup.height = 100, 100, 420, 224
        grip.scripts.OnMouseDown(grip, "RightButton")
        Check(Centred(popup), label .. ": the scale grip's reset moved a centerPopup popup off the centre")
    end
    local general = env.MSUF_DB.general
    if popup.scripts.OnHide then popup.scripts.OnHide(popup) end
    local saved = type(general.editModePopupPos) == "table" and general.editModePopupPos.MSUF_EM2_ExternalPopup
    Check(not saved, label .. ": closing a centerPopup popup saved its position")

    -- An element without the flag keeps the saved-position placement.
    Check(EM2.ExternalPopup.Open(plainKey) == true, label .. ": the plain element's popup did not open")
    ShowAndPlace(popup)
    Check(popup:GetPoint(1) == "TOPLEFT", label .. ": a popup without centerPopup lost its saved-position placement")
    if popup.scripts.OnHide then popup.scripts.OnHide(popup) end
    saved = type(general.editModePopupPos) == "table" and general.editModePopupPos.MSUF_EM2_ExternalPopup
    Check(type(saved) == "table", label .. ": a popup without centerPopup no longer saves its position")
end

RunCenteredExternalPopup()

if #failures > 0 then
    error("rc1_a_smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("rc1_a_smoke: ok")
