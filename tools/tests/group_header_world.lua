-- group_header_world.lua -- the real group runtime on an emulated SecureGroupHeader.
--
-- Boots one flavor's whole load graph through tools/tests/client_world.lua and
-- replaces the one Blizzard piece the group runtime stands on: the secure group
-- header. The emulator follows Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua
-- (live and classic_era are identical here):
--   * OnAttributeChanged / OnShow / GROUP_ROSTER_UPDATE run SecureGroupHeader_Update
--     while the header is visible; an attribute write inside an "_ignore" window
--     does not;
--   * configureChildren births missing buttons with CreateFrame(templateType,
--     name.."UnitButton"..i, header, template), creates the AuraContainer from
--     "auraContainerTemplate", runs "initialConfigFunction" as a restricted
--     snippet (self is the child's handle; GetParent answers the protected header
--     in combat too; CallMethod runs the named header method insecurely), then
--     writes each displayed child's unit and shows it, and clears the rest.
--
-- Protection model (the client's, reduced to what matters for group frames):
-- the header, every child it births and every ancestor of a protected frame
-- (anchors) are protected. A protected method called from insecure code while
-- InCombatLockdown() is true is recorded in h.violations with a traceback;
-- Blizzard's own header code runs "secure" and is exempt. RegisterUnitWatch and
-- friends are treated the same way.
--
-- Usage:
--   local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
--   local h = Harness.New(root, flavor)   -- booted, ADDON_LOADED + PLAYER_LOGIN delivered
--   h:SetRoster({ "player", "party1" })   -- party roster (or h:SetRaid(n))
--   h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
--   h:EnterCombat() / h:LeaveCombat()      -- REGEN_DISABLED before lockdown, as in the client
--
-- Plain Lua 5.1 (loadstring/setfenv/unpack).

local Harness = {}

local PROTECTED_METHODS = {
    "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
    "Show", "Hide", "SetShown", "SetParent", "EnableMouse", "SetMouseClickEnabled",
    "SetMouseMotionEnabled", "RegisterForClicks", "SetFrameLevel", "SetFrameStrata",
    "SetScale", "SetHitRectInsets", "SetID", "SetAttribute", "ClearAttribute",
    "SetClampedToScreen", "SetToplevel", "Raise", "Lower", "SetIgnoreParentScale",
    "SetPropagateMouseClicks", "SetPropagateMouseMotion",
    "SetRoundLayoutToNearestPixel",
}
local PROTECTED_GLOBALS = {
    "RegisterUnitWatch", "UnregisterUnitWatch", "RegisterStateDriver",
    "UnregisterStateDriver", "RegisterAttributeDriver", "UnregisterAttributeDriver",
}
-- RestrictedFrames.lua scrub(): only plain values cross into CallMethod.
local SCRUB_TYPES = { string = true, number = true, boolean = true }

local function SourceIsGroupRuntime(fn)
    local info = debug.getinfo(fn, "S")
    local source = info and info.source or ""
    return source:find("Engine/Group/", 1, true) ~= nil or source:find("GroupFrames/", 1, true) ~= nil
end

local Methods = {}
Methods.__index = Methods

function Harness.New(root, flavor, options)
    options = options or {}
    root = root:gsub("\\", "/"):gsub("/$", "")
    local World = dofile(root .. "/tools/tests/client_world.lua")
    local world = World.New(root, flavor)
    local env, widgets = world.env, world.widgets
    local M = widgets.Methods
    local h = setmetatable({
        root = root, flavor = flavor, world = world, env = env, widgets = widgets,
        units = { "player" }, secure = 0, violations = {}, headers = {}, born = {},
        callMethodErrors = {}, eventErrors = {},
    }, Methods)
    h.roundLayoutSupported = not world.client.isClassic

    -- Group roster -------------------------------------------------------
    local function HasUnit(unit)
        for index = 1, #h.units do if h.units[index] == unit then return true end end
        return false
    end
    env.IsInGroup = function() return #h.units > 1 end
    env.IsInRaid = function() return h.raid == true end
    env.GetNumGroupMembers = function() return #h.units > 1 and #h.units or 0 end
    env.GetNumSubgroupMembers = function() return h.raid and 0 or math.max(0, #h.units - 1) end
    env.UnitExists = function(unit) return HasUnit(unit) end
    env.UnitIsConnected = function(unit) return HasUnit(unit) end
    env.UnitGUID = function(unit) return HasUnit(unit) and ("Player-" .. unit) or nil end
    env.UnitName = function(unit) return HasUnit(unit) and ("Name-" .. unit) or nil, nil end
    env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    env.UnitGroupRolesAssigned = function() return "DAMAGER" end
    env.GetRaidRosterInfo = function(index)
        local unit = h.units[index]
        if not unit then return nil end
        return "Name-" .. unit, 0, math.floor((index - 1) / 5) + 1, 60, "Warrior", "WARRIOR", nil, true
    end
    env.IsLoggedIn = function() return true end
    env.ClickCastFrames = {}

    -- Security -----------------------------------------------------------
    local function Violation(frame, name)
        if env.InCombatLockdown() and h.secure == 0 then
            h.violations[#h.violations + 1] = tostring(frame and (frame.frameName or frame.objectType) or "?")
                .. ":" .. name .. debug.traceback("", 3)
        end
    end
    h.Violation = Violation

    local function RunAs(level, fn, ...)
        local saved = h.secure
        h.secure = level
        local results = { pcall(fn, ...) }
        h.secure = saved
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2, table.maxn(results))
    end
    local function RunSecure(fn, ...) return RunAs(h.secure + 1, fn, ...) end
    local function RunInsecure(fn, ...) return RunAs(0, fn, ...) end
    h.RunSecure, h.RunInsecure = RunSecure, RunInsecure

    local function Protect(frame)
        if not frame or frame == widgets.UIParent or frame.protected then return end
        frame.protected = true
        frame.IsProtected = function() return true, true end
        for _, name in ipairs(PROTECTED_METHODS) do
            local own = rawget(frame, name)
            local original = own or M[name]
            if original then
                frame[name] = function(self, ...)
                    Violation(self, name)
                    return original(self, ...)
                end
            end
        end
        -- The client fires OnAttributeChanged for every attribute write.
        local storeAttribute = frame.SetAttribute
        frame.SetAttribute = function(self, key, value)
            storeAttribute(self, key, value)
            local handler = self.scripts and self.scripts.OnAttributeChanged
            if handler then RunAs(0, handler, self, key, value) end
        end
        -- A protected child makes its parent chain protected as well.
        Protect(frame.parent)
    end
    h.Protect = Protect

    for _, name in ipairs(PROTECTED_GLOBALS) do
        env[name] = function(frame) Violation(frame, name) end
    end

    -- Script dispatch: hooks set by addon code run insecurely.
    local function FireScript(frame, script, ...)
        local handler = frame.scripts and frame.scripts[script]
        if handler then RunInsecure(handler, frame, ...) end
    end

    -- Restricted handles -------------------------------------------------
    local handles = setmetatable({}, { __mode = "k" })
    local HandleFor
    local function NewHandle(frame)
        local handle = {}
        function handle:GetName() return frame.frameName end
        function handle:GetParent()
            local parent = frame.parent
            if not parent then return nil end
            -- RestrictedFrames.lua HANDLE:GetParent: in lockdown only protected frames.
            if env.InCombatLockdown() and not parent.protected then return nil end
            return HandleFor(parent)
        end
        function handle:GetAttribute(key) return frame.attributes[key] end
        function handle:SetAttribute(key, value)
            M.SetAttribute(frame, key, value)
            FireScript(frame, "OnAttributeChanged", key, value)
        end
        function handle:SetWidth(value) M.SetWidth(frame, value) end
        function handle:SetHeight(value) M.SetHeight(frame, value) end
        function handle:ClearAllPoints() M.ClearAllPoints(frame) end
        function handle:CallMethod(name, ...)
            local method = frame[name]
            if type(method) ~= "function" then error("Invalid method '" .. tostring(name) .. "'", 2) end
            local args, count = { ... }, select("#", ...)
            for index = 1, count do
                if not SCRUB_TYPES[type(args[index])] then args[index] = nil end
            end
            local ok, err = pcall(RunInsecure, method, frame, unpack(args, 1, count))
            if not ok then h.callMethodErrors[#h.callMethodErrors + 1] = tostring(err) end
        end
        return handle
    end
    HandleFor = function(frame)
        local handle = handles[frame]
        if not handle then
            handle = NewHandle(frame)
            handles[frame] = handle
        end
        return handle
    end

    local function RunSnippet(code, owner)
        if type(code) ~= "string" then return end
        local chunk = assert(loadstring(code, "=initialConfigFunction"))
        setfenv(chunk, { self = HandleFor(owner), table = table, string = string, math = math })
        chunk()
    end

    -- SecureGroupHeader ----------------------------------------------------
    local function HeaderVisible(header)
        local frame = header
        while frame do
            if not frame.shown then return false end
            frame = frame.parent
        end
        return true
    end

    local function HeaderUnits(header)
        local attributes, out = header.attributes, {}
        if h.raid then
            if not attributes.showRaid then return out end
            for index = 1, #h.units do out[#out + 1] = h.units[index] end
            return out
        end
        local grouped = #h.units > 1
        if grouped and not attributes.showParty then return out end
        if not grouped and not attributes.showSolo then return out end
        for index = 1, #h.units do
            local unit = h.units[index]
            if unit ~= "player" or attributes.showPlayer or attributes.showSolo then out[#out + 1] = unit end
        end
        return out
    end

    local function UpdateHeader(header)
        if not HeaderVisible(header) then return end
        h.headerUpdates = (h.headerUpdates or 0) + 1
        RunSecure(function()
            local attributes = header.attributes
            local units = HeaderUnits(header)
            local displayed = #units
            local perColumn = attributes.unitsPerColumn
            if perColumn and displayed > perColumn then
                displayed = math.min(displayed, perColumn * (attributes.maxColumns or 1))
            end
            local name = header.frameName
            for index = 1, math.max(1, displayed) do
                if not attributes["child" .. index] then
                    local childName = name and (name .. "UnitButton" .. index) or nil
                    local child = widgets:CreateFrame(attributes.templateType or "Button", childName, header,
                        attributes.template)
                    -- CreateFrame returns a shown frame: SecureUnitButtonTemplate and
                    -- SecureFrameTemplate carry no hidden="true" (SecureTemplates.xml,
                    -- SecureTemplatesBase.xml), and configureChildren writes the unit
                    -- before its Show() call, so the first unit write meets a shown child.
                    child.shown = true
                    -- Region:SetRoundLayoutToNearestPixel exists on the Mainline-family
                    -- 12.1.5 engine only; Protect() below makes it a protected method.
                    if h.roundLayoutSupported then
                        child.SetRoundLayoutToNearestPixel = function(self, enabled) self.roundLayout = enabled end
                    end
                    if childName then env[childName] = child end
                    Protect(child)
                    header[index] = child
                    if attributes.auraContainerTemplate then
                        child.AuraContainer = widgets:CreateFrame("AuraContainer", nil, child, attributes.auraContainerTemplate)
                    end
                    RunSnippet(attributes.initialConfigFunction, child)
                    local copy = attributes._initialAttributeNames
                    if type(copy) == "string" then
                        for attribute in copy:gmatch("[^,]+") do
                            child:SetAttribute(attribute, attributes["_initialAttribute-" .. attribute])
                        end
                    end
                    attributes["child" .. index] = child
                    attributes["frameref-child" .. index] = child
                    h.born[#h.born + 1] = { child = child, header = header, combat = env.InCombatLockdown() == true }
                end
            end
            for index = 1, displayed do
                local child = attributes["child" .. index]
                child:SetAttribute("unit", units[index])
                M.Show(child)
            end
            local index = displayed
            repeat
                index = index + 1
                local child = attributes["child" .. index]
                if child then
                    M.Hide(child)
                    child:SetAttribute("unit", nil)
                end
            until not child
        end)
    end
    h.UpdateHeader = UpdateHeader

    local function NewHeader(frameType, name, parent, template)
        local header = widgets:CreateFrame(frameType, name, parent, template)
        header.shown = false
        if name then env[name] = header end
        h.headers[#h.headers + 1] = header
        header._harnessHeader = true
        -- SecureGroupHeader_OnLoad
        header.events.GROUP_ROSTER_UPDATE = true
        header.events.UNIT_NAME_UPDATE = true
        header.scripts.OnEvent = function(self, event)
            if (event == "GROUP_ROSTER_UPDATE" or event == "UNIT_NAME_UPDATE") then UpdateHeader(self) end
        end
        Protect(header)
        local setAttribute = header.SetAttribute
        header.SetAttribute = function(self, key, value)
            setAttribute(self, key, value)
            -- SecureGroupHeader_OnAttributeChanged
            if key == "_ignore" or self.attributes._ignore then return end
            if type(key) == "string" and (key:find("^child%d") or key:find("^frameref%-")) then return end
            UpdateHeader(self)
        end
        local show = header.Show
        header.Show = function(self)
            local was = self.shown
            show(self)
            if not was then UpdateHeader(self) end
        end
        return header
    end

    local createFrame = env.CreateFrame
    env.CreateFrame = function(frameType, name, parent, template)
        if type(template) == "string" and template:find("SecureGroupHeaderTemplate", 1, true) then
            return NewHeader(frameType, name, parent, template)
        end
        if type(template) == "string" and template:find("Secure", 1, true) then
            local frame = createFrame(frameType, name, parent, template)
            Protect(frame)
            return frame
        end
        return createFrame(frameType, name, parent, template)
    end

    if options.beforeBoot then options.beforeBoot(h) end
    world:Boot()
    local failure = world:FirstFailure()
    if failure then
        error(flavor .. " did not boot: " .. tostring(failure.file) .. " " .. tostring(failure.message), 0)
    end
    h.GF, h.UF, h.core = world.core.GF, world.core.UF, world.core
    h:Event("ADDON_LOADED", "MidnightSimpleUnitFrames")
    h:Event("PLAYER_LOGIN")
    return h
end

-- Deliver an event to every frame registered for it. Group runtime handlers
-- must not raise; other modules may trip over the offline stubs and are
-- isolated (their errors are collected, never fatal).
function Methods:Event(event, ...)
    local frames = self.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local handler = frame.events and (frame.events[event] or frame.events["*"]) and frame.scripts
            and frame.scripts.OnEvent
        if handler then
            if frame._harnessHeader then
                handler(frame, event, ...)
            elseif SourceIsGroupRuntime(handler) then
                self.RunInsecure(handler, frame, event, ...)
            else
                local ok, err = pcall(self.RunInsecure, handler, frame, event, ...)
                if not ok then self.eventErrors[#self.eventErrors + 1] = event .. ": " .. tostring(err) end
            end
        end
    end
end

-- Run queued C_Timer callbacks in FIFO order (callbacks may queue more). Group
-- runtime callbacks must not raise; the others are isolated like events.
function Methods:RunTimers()
    local timers = self.widgets.timers
    local ran = 0
    while #timers > 0 and ran < 1000 do
        local entry = table.remove(timers, 1)
        ran = ran + 1
        local callback = entry.callback
        if not entry.cancelled and type(callback) == "function" then
            if SourceIsGroupRuntime(callback) then
                self.RunInsecure(callback)
            else
                local ok, err = pcall(self.RunInsecure, callback)
                if not ok then self.eventErrors[#self.eventErrors + 1] = "timer: " .. tostring(err) end
            end
        end
    end
    return ran
end

function Methods:SetRoster(units)
    self.raid = false
    self.units = units
end

function Methods:SetRaid(count)
    self.raid = true
    local units = {}
    for index = 1, count do units[index] = "raid" .. index end
    self.units = units
end

-- PLAYER_REGEN_DISABLED fires before InCombatLockdown() turns true.
function Methods:EnterCombat(beforeLockdown)
    self:Event("PLAYER_REGEN_DISABLED")
    if beforeLockdown then beforeLockdown(self) end
    self.widgets:SetCombat(true)
end

function Methods:LeaveCombat()
    self.widgets:SetCombat(false)
    self:Event("PLAYER_REGEN_ENABLED")
end

-- Every child of `header`, in child-attribute order.
function Methods:Children(header)
    local out = {}
    for index = 1, 80 do
        local child = header and header.attributes["child" .. index]
        if not child then break end
        out[#out + 1] = child
    end
    return out
end

function Harness.SourceIsGroupRuntime(fn) return SourceIsGroupRuntime(fn) end

return Harness
