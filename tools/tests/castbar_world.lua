-- castbar_world.lua -- a fake client for castbar smokes.
--
-- Loads the real castbar stack (Kernel Require and scheduler, castbar utils, runtime,
-- engine, driver, manager; optionally the boss and arena pools) in the order
-- the flavor TOC lists them, into plain _G, and drives it with a fake clock:
-- every C_Timer.After callback, TimedSignalMap signal and shown OnUpdate script
-- runs in deadline order. Two delayed-scheduler backends:
--   * "timer":  C_Timer.After with one runner per key (every Classic client,
--               Midnight 12.1.0);
--   * "signal": TimerUtil.CreateTimedSignalCallbackMap (12.1.5).
--
-- Usage from a smoke (Lua 5.1, repo root as arg 1):
--   local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()
--   local world = World.New(root, "timer", { pools = true })

local World = {}
World.__index = World

local STEP = 1 / 120
World.STEP = STEP
World.FLAVOR = "Mists"

local function NoOp() end

local function WipeAddonGlobals()
    local names = {}
    for key in pairs(_G) do
        if type(key) == "string" and key:find("MSUF", 1, true) then names[#names + 1] = key end
    end
    for index = 1, #names do _G[names[index]] = nil end
end

-- The castbar stack every world loads, by file name; options.pools adds every
-- boss/arena pool file the TOC lists (live pools only, no previews).
local BASE_FILES = {
    ["MSUF_Require.lua"] = true,
    ["MSUF_Scheduler.lua"] = true,
    ["MSUF_CastbarUtils.lua"] = true,
    ["MSUF_CastbarRuntime.lua"] = true,
    ["MSUF_CastbarEngine.lua"] = true,
    ["MSUF_CastbarDriver.lua"] = true,
    ["MSUF_Castbars.lua"] = true,
}

local function IsPoolFile(name)
    if name:find("Preview", 1, true) then return false end
    return name == "MSUF_BossCastbars.lua" or name == "MSUF_ArenaCastbars.lua"
        or name:find("^MSUF_CastbarPool") ~= nil
end

-- options:
--   pools       also load the boss and arena castbar pools
--   flavor      client TOC (default Mists)
--   extra       further castbar file names to load, in TOC order
--   arenaSlots  MSUF_MAX_ARENA_FRAMES the client model publishes (default 3)
--   setup       function(ns, world) run before any file loads
--   richWidgets region factories (CreateTexture, CreateFontString, ...) and
--               GetStatusBarTexture return child widgets instead of nil, and
--               sizes are stored, for smokes that build full castbar frames
function World.New(root, backend, options)
    options = options or {}
    WipeAddonGlobals()
    local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    local world = setmetatable({
        root = root,
        backend = backend,
        clock = 100,
        timers = {},
        signals = {},
        frames = {},
        casting = {},
        channeling = {},
        dead = {},
        exists = { target = true, focus = true, boss1 = true, arena1 = true },
    }, World)

    -- Names the permissive widget answers with a no-op method. Rich widgets
    -- skip all-caps prefixes ("MSUFSpec") so data fields read as nil.
    local methodPattern = options.richWidgets and "^%u%l%a*$" or "^%u%a*$"
    local function NewWidget(kind, name)
        local widget = { kind = kind, name = name, scripts = {}, hooks = {}, shown = true, events = {} }
        setmetatable(widget, { __index = function(_, key)
            if type(key) == "string" and key:match(methodPattern)
                and key ~= "SetTimerDuration" and key ~= "ClearTimerDuration" then
                return NoOp
            end
            return nil
        end })
        function widget:SetScript(script, handler) self.scripts[script] = handler end
        function widget:GetScript(script) return self.scripts[script] end
        function widget:HookScript(script, handler)
            local list = self.hooks[script] or {}
            self.hooks[script] = list
            list[#list + 1] = handler
        end
        function widget:IsShown() return self.shown == true end
        function widget:IsVisible() return self.shown == true end
        function widget:Show() self.shown = true end
        function widget:Hide()
            if not self.shown then return end
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
            for _, handler in ipairs(self.hooks.OnHide or {}) do handler(self) end
        end
        function widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function widget:RegisterEvent(event) self.events[event] = true end
        function widget:RegisterUnitEvent(event) self.events[event] = true end
        function widget:UnregisterEvent(event) self.events[event] = nil end
        function widget:UnregisterAllEvents() self.events = {} end
        function widget:IsEventRegistered(event) return self.events[event] == true end
        function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
        function widget:GetMinMaxValues() return self.minValue or 0, self.maxValue or 1 end
        function widget:SetValue(value) self.value = value end
        function widget:GetValue() return self.value or 0 end
        function widget:GetStatusBarColor() return 1, 0.7, 0, 1 end
        function widget:SetText(text) self.text = text end
        function widget:SetFormattedText(format, ...) self.text = string.format(format, ...) end
        function widget:GetText() return self.text end
        function widget:GetWidth() return 200 end
        function widget:GetHeight() return 18 end
        function widget:GetEffectiveScale() return 1 end
        function widget:GetFrameLevel() return 1 end
        function widget:GetPoint() return nil end
        function widget:CreateAnimationGroup() return NewWidget("AnimationGroup") end
        function widget:CreateAnimation() return NewWidget("Animation") end
        if options.richWidgets then
            function widget:CreateTexture() return NewWidget("Texture") end
            function widget:CreateMaskTexture() return NewWidget("MaskTexture") end
            function widget:CreateFontString() return NewWidget("FontString") end
            function widget:CreateLine() return NewWidget("Line") end
            function widget:GetStatusBarTexture()
                self.statusBarTexture = self.statusBarTexture or NewWidget("Texture")
                return self.statusBarTexture
            end
            function widget:SetSize(width, height) self.width, self.height = width, height end
            function widget:SetWidth(width) self.width = width end
            function widget:SetHeight(height) self.height = height end
            function widget:GetWidth() return self.width or 200 end
            function widget:GetHeight() return self.height or 18 end
            function widget:GetSize() return self:GetWidth(), self:GetHeight() end
            function widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
            function widget:SetFont() return true end
            function widget:GetStringWidth() return 40 end
            function widget:GetFrameStrata() return self.strata or "MEDIUM" end
            function widget:SetFrameStrata(strata) self.strata = strata end
            function widget:GetFrameLevel() return self.level or 1 end
            function widget:SetFrameLevel(level) self.level = level end
            function widget:GetParent() return self.parent end
            function widget:SetParent(parent) self.parent = parent end
            function widget:GetName() return self.name end
        end
        world.frames[#world.frames + 1] = widget
        if type(name) == "string" then _G[name] = widget end
        return widget
    end
    world.NewWidget = NewWidget

    _G.GetTime = function() return world.clock end
    _G.GetTimePreciseSec = _G.GetTime
    _G.C_Timer = {
        After = function(delay, callback)
            world.timers[#world.timers + 1] = { due = world.clock + delay, fn = callback }
        end,
    }
    if backend == "signal" then
        _G.TimerUtil = {
            CreateTimedSignalCallbackMap = function()
                local map = { callbacks = {}, next = 0 }
                function map:RegisterCallback(fn)
                    self.next = self.next + 1
                    self.callbacks[self.next] = fn
                    return self.next
                end
                function map:SignalAfter(key, delay)
                    world.signals[key] = { due = world.clock + delay, fn = self.callbacks[key] }
                end
                function map:CancelSignal(key) world.signals[key] = nil end
                return map
            end,
        }
    else
        _G.TimerUtil = nil
    end
    _G.secureexecuterange = nil
    _G.issecretvalue = function() return false end
    _G.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
    _G.UnitExists = function(unit) return world.exists[unit] == true end
    _G.UnitIsDeadOrGhost = function(unit) return world.dead[unit] == true end
    _G.UnitIsUnconscious = function() return false end
    _G.UnitIsConnected = function() return true end
    _G.UnitHasVehicleUI = function() return false end
    _G.UnitCastingInfo = function(unit)
        local cast = world.casting[unit]
        if not cast then return nil end
        return cast.name, cast.name, 135812, cast.startMS, cast.endMS, cast.tradeskill == true, cast.guid, false,
            cast.spellID, cast.castBarID
    end
    _G.UnitChannelInfo = function(unit)
        local channel = world.channeling[unit]
        if not channel then return nil end
        return channel.name, channel.name, 136208, channel.startMS, channel.endMS, false, false, channel.spellID,
            channel.empowered == true, channel.empowered and 3 or 0, channel.castBarID
    end
    _G.UnitCastingDuration = nil
    _G.UnitChannelDuration = nil
    _G.C_DurationUtil = nil
    _G.GetCVar = function(name)
        if name == "SpellQueueWindow" then return "400" end
        return nil
    end
    _G.CreateFrame = function(kind, name) return NewWidget(kind, name) end
    _G.UIParent = NewWidget("Frame")
    _G.GameFontHighlight = NewWidget("Font")
    _G.MSUF_DB = { general = {}, target = {}, focus = {}, boss = {}, arena = {} }

    local ns = {
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
        Client = {
            IsClassic = true,
            IsMists = true,
            SupportsUnit = function() return true end,
            SupportsEvent = function() return true end,
        },
    }
    world.ns = ns
    -- Castbars/MSUF_CastbarFrames.lua is not loaded: World:Driver and
    -- World:PoolCastbar supply the regions its builder makes.
    _G.MSUF_BuildCastbarFrameElements = function() end
    if options.setup then options.setup(ns, world) end
    _G.MSUF_MAX_ARENA_FRAMES = options.arenaSlots or 3
    local extra = {}
    for index = 1, #(options.extra or {}) do extra[options.extra[index]] = true end
    local loaded = {}
    for _, path in ipairs(manifest.Paths(root, options.flavor or World.FLAVOR)) do
        local name = path:match("([^/]+)$")
        local inCastbars = path:find("/Castbars/", 1, true) or path:find("/Kernel/", 1, true)
        if inCastbars and (BASE_FILES[name] or extra[name] or (options.pools and IsPoolFile(name))) then
            assert(loadfile(path))("MidnightSimpleUnitFrames", ns)
            loaded[name] = true
        end
    end
    for name in pairs(BASE_FILES) do assert(loaded[name], "castbar world could not load " .. name) end
    world.loaded = loaded
    assert(type(_G.MSUF_ScheduleAfter) == "function", "Kernel scheduler did not load")
    assert((backend == "signal") == (ns.Scheduler.signalMap ~= false),
        "scheduler picked the wrong delayed backend for " .. backend)
    world:Advance(0)
    return world
end

-- Runs every timer and signal due at the current clock, earliest deadline
-- first, until nothing is due.
function World:RunDue()
    for _ = 1, 10000 do
        local bestKind, bestKey, bestDue
        for index = 1, #self.timers do
            local timer = self.timers[index]
            if timer.due <= self.clock + 1e-9 and (not bestDue or timer.due < bestDue) then
                bestKind, bestKey, bestDue = "timer", index, timer.due
            end
        end
        for key, signal in pairs(self.signals) do
            if signal.due <= self.clock + 1e-9 and (not bestDue or signal.due < bestDue) then
                bestKind, bestKey, bestDue = "signal", key, signal.due
            end
        end
        if not bestKind then return end
        if bestKind == "timer" then
            local timer = table.remove(self.timers, bestKey)
            timer.fn()
        else
            local signal = self.signals[bestKey]
            self.signals[bestKey] = nil
            signal.fn()
        end
    end
    error("timer storm: more than 10000 callbacks in one step")
end

-- One rendered frame: due callbacks, every shown OnUpdate, due callbacks.
function World:Frame()
    self:RunDue()
    for index = 1, #self.frames do
        local frame = self.frames[index]
        local onUpdate = frame.scripts.OnUpdate
        if onUpdate and frame.shown then onUpdate(frame, STEP) end
    end
    self:RunDue()
end

function World:Advance(seconds)
    local target = self.clock + seconds
    repeat
        self:Frame()
        if self.clock >= target - 1e-9 then break end
        self.clock = math.min(target, self.clock + STEP)
    until false
end

-- tradeskill marks a profession cast (UnitCastingInfo's isTradeskill).
function World:StartCast(unit, name, seconds, castBarID, tradeskill)
    local startMS = math.floor(self.clock * 1000)
    self.casting[unit] = { name = name, startMS = startMS, endMS = startMS + seconds * 1000,
        guid = name .. "-guid", spellID = 133, castBarID = castBarID, tradeskill = tradeskill }
end

function World:StartChannel(unit, name, seconds, castBarID, empowered)
    local startMS = math.floor(self.clock * 1000)
    self.channeling[unit] = { name = name, startMS = startMS, endMS = startMS + seconds * 1000,
        spellID = 15407, castBarID = castBarID, empowered = empowered }
end

-- A target or focus driver castbar with the regions
-- MSUF_BuildCastbarFrameElements would have built, and a completion log.
function World:Driver(unit)
    local frame = assert(_G.MSUF_CreateCastBar("MSUF_" .. unit .. "SmokeCastBar", unit), "driver castbar missing")
    frame.statusBar = self.NewWidget("StatusBar")
    frame.castText = self.NewWidget("FontString")
    frame.completedAt = {}
    local setSucceeded = frame.SetSucceeded
    frame.SetSucceeded = function(bar)
        bar.completedAt[#bar.completedAt + 1] = self.clock
        return setSucceeded(bar)
    end
    return frame
end

-- A pool castbar (boss1, arena1) built by its pool; the harness gives it the
-- regions MSUF_BuildCastbarFrameElements would have built.
function World:PoolCastbar(frame)
    assert(frame, "pool castbar missing")
    frame.statusBar = frame.statusBar or self.NewWidget("StatusBar")
    frame.castText = frame.castText or self.NewWidget("FontString")
    return frame
end

-- Delivers a unit event to a castbar's real OnEvent script and its hooks, the
-- way the client does: the script first, then every HookScript handler.
function World:Fire(frame, event, ...)
    frame.scripts.OnEvent(frame, event, frame.unit, ...)
    local hooks = frame.hooks.OnEvent
    if hooks then
        for index = 1, #hooks do hooks[index](frame, event, frame.unit, ...) end
    end
end

return World
