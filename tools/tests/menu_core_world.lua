-- menu_core_world.lua: shared harness for the Menu2 core smokes.
--
-- Boots one client's real core and Options graph through client_world.lua,
-- gives the page builders the widget surface they use (the shared stubs leave
-- part of it out), and opens the real menu window once. Show/Hide fire
-- OnShow/OnHide like the client does, so the window's lifecycle (history
-- session, quiesce on hide) runs for real.
--
--   local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
--   local mw = MenuWorld.Open(root, flavor, { locale = "enUS" })
--   mw.M, mw.env, mw.core, mw.world, mw.win, mw:Frames(), mw:Fire(event)
--
-- Plain Lua 5.1. Not a smoke itself.

local MenuWorld = {}

local Handle = {}
Handle.__index = Handle

-- Client script bindings (opt-in, options.clientScriptBindings): HookScript
-- adds a separate post-call binding that a later SetScript keeps, and
-- GetScript returns only the base handler. The shared stubs fold hooks into
-- the base handler instead, so a SetScript after a HookScript drops the hook.
local function FireScript(frame, name, ...)
    local base = frame.scripts and frame.scripts[name]
    local result
    if base then result = base(frame, ...) end
    local hooks = frame._clientHooks and frame._clientHooks[name]
    if hooks then
        for i = 1, #hooks do hooks[i](frame, ...) end
    end
    return result
end
local function Pack(...) return { n = select("#", ...), ... } end
local function FireButtonScript(frame, name, ...)
    local base = frame.scripts and frame.scripts[name]
    local result
    if base then result = Pack(base(frame, ...)) end
    local hooks = frame._clientHooks and frame._clientHooks[name]
    if hooks then
        for i = 1, #hooks do hooks[i](frame, ...) end
    end
    if result then return unpack(result, 1, result.n) end
end
MenuWorld.FireScript = FireScript

local function FireVisibilityScripts(frame)
    if not frame or frame._menuCoreWorldVisibility then return end
    frame._menuCoreWorldVisibility = true
    local show, hide = frame.Show, frame.Hide
    function frame:Show()
        local wasShown = self:IsShown()
        show(self)
        if not wasShown then FireScript(self, "OnShow") end
    end
    function frame:Hide()
        local wasShown = self:IsShown()
        hide(self)
        if wasShown then FireScript(self, "OnHide") end
    end
    function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
end
MenuWorld.FireVisibilityScripts = FireVisibilityScripts
local function InstallClientScriptBindings(Methods, nativeButtons)
    Methods.SetScript = function(self, name, handler) self.scripts[name] = handler end
    Methods.GetScript = function(self, name) return self.scripts[name] end
    Methods.HasScript = function(self, name)
        return self.scripts[name] ~= nil or (self._clientHooks and self._clientHooks[name] ~= nil)
    end
    Methods.HookScript = function(self, name, handler)
        self._clientHooks = self._clientHooks or {}
        local hooks = self._clientHooks[name]
        if not hooks then
            hooks = {}
            self._clientHooks[name] = hooks
        end
        hooks[#hooks + 1] = handler
        return true
    end
    if not nativeButtons then
        Methods.Click = function(self, button) return FireScript(self, "OnClick", button or "LeftButton") end
        return
    end
    Methods.Click = function(self, button, down)
        if self.IsEnabled and not self:IsEnabled() then return end
        button, down = button or "LeftButton", down == true
        FireButtonScript(self, "PreClick", button, down)
        local result = Pack(FireButtonScript(self, "OnClick", button, down))
        FireButtonScript(self, "PostClick", button, down)
        return unpack(result, 1, result.n)
    end
end

-- Pinned historical page sources (the "immutable parent" replays) were written
-- when the MSUF_* exports were real globals; the product now keeps most of them
-- in the namespace registry only. LegacyEnv is the global table such a source
-- ran against: the world's globals first (so a hook or override a test installs
-- later is still seen), then the namespace's published exports. Writes reach the
-- world's globals. Only the pinned source is given this view; the current
-- builders keep the real (namespace-only) lookup.
function MenuWorld.LegacyEnv(world)
    if world.legacyEnv then return world.legacyEnv end
    local env = world.env
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            local value = rawget(env, key)
            if value == nil and type(key) == "string" then
                local owned = world.core and world.core.PublicGlobals
                value = owned and owned[key]
            end
            if value == nil then value = env[key] end
            return value
        end,
        __newindex = function(_, key, value) env[key] = value end,
    })
    rawset(proxy, "_G", proxy)
    world.legacyEnv = proxy
    return proxy
end

-- Run an already compiled pinned historical chunk the way World:LoadFile runs a
-- shipped one, against the legacy global view. Returns ok, message.
function MenuWorld.RunHistorical(world, chunk, path, addonName, namespace)
    setfenv(chunk, MenuWorld.LegacyEnv(world))
    world.loading = path
    local ok, runError = pcall(chunk, addonName, namespace)
    world.loading = nil
    if ok then return true end
    return false, tostring(runError)
end

function MenuWorld.LoadHistorical(world, path, addonName, namespace)
    local chunk, compileError = loadfile(path)
    if chunk == nil then return false, "does not compile: " .. tostring(compileError) end
    return MenuWorld.RunHistorical(world, chunk, path, addonName, namespace)
end

-- For a smoke that loads single shipped files into world.core instead of booting
-- the whole TOC graph: the real Kernel namespace API (Bootstrap with the shipped
-- global keep policy, then Require) and the pixel layout provider chain the shell
-- and Menu2 files require at load (Edit Mode Geometry, then Util), in core TOC
-- order. Exports then land where the client puts them: namespace-only names are
-- read from world.core.PublicGlobals. sourceRoot selects an alternate source tree.
function MenuWorld.InstallPartialCore(world, sourceRoot)
    sourceRoot = sourceRoot or world.root
    local RequireFixture = assert(loadfile(world.root .. "/tools/tests/require_fixture.lua"))()
    RequireFixture.InstallKernel(sourceRoot, world.core, world.env, loadfile, true)
    for _, path in ipairs({ "Shell/EditMode/MSUF_EditMode_Geometry.lua", "Kernel/MSUF_Util.lua" }) do
        local ok, message = world:LoadFile(sourceRoot .. "/MidnightSimpleUnitFrames/" .. path, "MidnightSimpleUnitFrames", world.core)
        assert(ok, "menu_core_world partial core: " .. path .. ": " .. tostring(message))
    end
    return world.core
end

-- For the standalone Menu2 theme smokes (a bare namespace in plain _G, no world):
-- the real core providers the theme and shell files require at load, in core TOC
-- order (Kernel API, Libs, Fonts, Edit Mode Geometry, Util, then the shared UI
-- primitives the Menu2 theme binds to). A provider this list leaves out is
-- deferred by RequireFixture.LoadShipped and raises if a painter uses it. The
-- caller defines its stubs and ns.Client first, and loads the Options files after.
-- Returns the RequireFixture, whose LoadShipped loads those Options files.
local function BareFrameStubs()
    -- The providers create their event frames at load: a probe with no widget surface of its own
    -- gets a bare event frame (a probe that defined CreateFrame keeps it).
    if rawget(_G, "CreateFrame") == nil then
        _G.CreateFrame = function()
            local frame = { events = {} }
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:UnregisterEvent(event) self.events[event] = nil end
            function frame:UnregisterAllEvents() self.events = {} end
            function frame:SetScript(name, handler) self[name] = handler end
            return frame
        end
    end
    if rawget(_G, "InCombatLockdown") == nil then _G.InCombatLockdown = function() return false end end
end

-- Lighter variant for a probe whose files only need the pixel layout provider:
-- the real Kernel API, Edit Mode Geometry and Util (core TOC order). Returns the RequireFixture.
function MenuWorld.LoadPixelLayoutProvider(root, ns)
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    BareFrameStubs()
    local function load(path) assert(loadfile(root .. "/" .. path))("MidnightSimpleUnitFrames", ns) end
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua")
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua")
    load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Geometry.lua")
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
    return RequireFixture
end

function MenuWorld.LoadThemeProviders(root, ns)
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    BareFrameStubs()
    local function load(path) assert(loadfile(root .. "/" .. path))("MidnightSimpleUnitFrames", ns) end
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua")
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua")
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua")
    load("MidnightSimpleUnitFrames/Runtime/MSUF_Fonts.lua")
    load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Geometry.lua")
    load("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
    RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/Shell/UI/MSUF_Style.lua", ns)
    RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/Shell/UI/MSUF_Widgets.lua", ns)
    return RequireFixture
end

-- The client serves a TOC's own X-* header fields through GetAddOnMetadata. client_world answers only
-- X-MSUF-Client, so the unit-frame framework would fall back to the addon name for its frame prefix
-- (X-MSUF-UnitFrames-Prefix: MSUF) and name its frames "MidnightSimpleUnitFrames_<unit>", a global the
-- world then answers with an opaque stub. A world that spawns real unit frames opts in before it boots;
-- it answers the framework's own TOC field (a field the world already answers keeps its value). Other
-- X-MSUF-* fields (the version) stay unanswered: answering them would change unrelated menu paths.
local FRAMEWORK_TOC_FIELDS = { ["X-MSUF-UnitFrames-Prefix"] = true }
function MenuWorld.ApplyCoreTocMetadata(world)
    local env = world.env
    local fields = {}
    local suffix = world.client.tocSuffix or world.flavor
    local handle = io.open(world.root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. suffix .. ".toc", "rb")
    if handle then
        for line in handle:lines() do
            local key, value = line:match("^##%s*(X%-MSUF%-[%w%-]+):%s*(.-)%s*$")
            if key and FRAMEWORK_TOC_FIELDS[key] then fields[key] = value end
        end
        handle:close()
    end
    local previous = env.C_AddOns.GetAddOnMetadata
    local function GetMetadata(addon, field)
        local value = previous(addon, field)
        if value == nil and addon == "MidnightSimpleUnitFrames" then value = fields[field] end
        return value
    end
    env.C_AddOns.GetAddOnMetadata, env.GetAddOnMetadata = GetMetadata, GetMetadata
end

-- A world that spawns real unit frames reads native inputs client_world leaves opaque: the idle Warrior's
-- power API, the numeric formatters the text writers capture at load, the class colours and the totem
-- frame. These are the same inputs the schema smokes give their worlds (menu_portrait_schema_smoke.lua);
-- call this from beforeCore. The formatters accept finite numbers only, like the native ones.
function MenuWorld.InstallNativeUnitInputs(world)
    local env = world.env
    local power = assert(loadfile(world.root .. "/tools/tests/classpower_world.lua"))().PT
    local enum = env.Enum
    env.Enum = setmetatable({ PowerType = { Mana = power.MANA, Rage = power.RAGE, Focus = 2,
        Energy = power.ENERGY, ComboPoints = power.COMBO } }, { __index = enum })
    local function PowerType(value)
        assert(value == nil or type(value) == "number", "native power-type argument must be numeric or nil")
    end
    env.UnitPowerType = function() return power.RAGE, "RAGE" end
    env.UnitPower = function(_, value) PowerType(value) return 0 end
    env.UnitPowerMax = function(_, value)
        PowerType(value) return (value == nil or value == power.RAGE) and 100 or 5
    end
    env.UnitPowerDisplayMod = function(value) PowerType(value) return 1 end
    env.UnitHasVehicleUI = function() return false end
    env.PlayerVehicleHasComboPoints = function() return false end
    env.GetShapeshiftFormID = function() return nil end
    local function Number(value)
        assert(type(value) == "number" and value == value and value - value == 0,
            "native numeric formatter requires a finite number")
        return value
    end
    local function Abbreviate(value)
        value = Number(value)
        if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
        if value >= 1000 then return string.format("%.1fK", value / 1000) end
        return string.format("%d", value)
    end
    env.AbbreviateNumbers, env.AbbreviateLargeNumbers = Abbreviate, Abbreviate
    env.BreakUpLargeNumbers = function(value) return string.format("%d", math.floor(Number(value))) end
    if rawget(env, "RAID_CLASS_COLORS") == nil then
        env.RAID_CLASS_COLORS = {}
        for index, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
            "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
            env.RAID_CLASS_COLORS[class] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
        end
    end
    env.TotemFrame = env.CreateFrame("Frame", nil, env.UIParent)
end

function Handle:Frames() return #self.world.widgets.frames end
function Handle:RunTimers(limit) return self.world.widgets:RunTimers(limit) end

-- Dispatch an event to the Options addon's own listeners only.
function Handle:Fire(event, ...)
    local fired = 0
    for _, frame in ipairs(self.world.widgets.frames) do
        local handler = frame.events and (frame.events[event] or frame.events["*"]) and frame:GetScript("OnEvent")
        local source = handler and debug.getinfo(handler, "S").source or ""
        if source:find("MidnightSimpleUnitFrames_Options", 1, true) then
            handler(frame, event, ...)
            fired = fired + 1
        end
    end
    return fired
end

function Handle:Select(key)
    local ok = self.M.SelectPage(key)
    self.world.widgets:RunTimers()
    return ok
end

function MenuWorld.Open(root, flavor, options)
    options = options or {}
    local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
    local world = World.New(root, flavor, { locale = options.locale or "enUS" })
    -- Opt-in (options.tocMetadata = true): a world whose smoke spawns real unit frames names them from the core
    -- TOC's X-MSUF-UnitFrames-Prefix (see ApplyCoreTocMetadata). It is off by default because every other menu
    -- world then keeps the units unspawned, which several smokes (bars_outline_override_smoke) count on.
    if options.tocMetadata == true then MenuWorld.ApplyCoreTocMetadata(world) end
    -- The parity world's shared-parent replay writes the authentic pre-schema section to
    -- .checks/shared-parent-*.lua and loads it through LoadFile (menu_section_parity_world.lua is hash-pinned,
    -- so it cannot choose the environment itself). That pinned source predates namespace-only exports, so it
    -- runs against the legacy global view; every other file loads as shipped.
    local loadFile = world.LoadFile
    function world:LoadFile(path, addonName, namespace)
        if type(path) == "string" and path:gsub("\\", "/"):find("/%.checks/shared%-parent%-") then
            return MenuWorld.LoadHistorical(self, path, addonName, namespace)
        end
        return loadFile(self, path, addonName, namespace)
    end
    -- Runs before anything loads, e.g. to take a client capability away.
    if type(options.beforeCore) == "function" then options.beforeCore(world) end
    local Methods = world.widgets.Methods
    local function Store(field) return function(self, value) self[field] = value end end
    local function Fetch(field) return function(self) return self[field] end end
    for _, name in ipairs({ "Normal", "Highlight", "Pushed", "Disabled", "Checked" }) do
        Methods["Set" .. name .. "Texture"] = function(self, path)
            local texture = self["fixture" .. name] or self:CreateTexture()
            texture:SetTexture(path)
            self["fixture" .. name] = texture
        end
        Methods["Get" .. name .. "Texture"] = function(self) return self["fixture" .. name] end
    end
    for name, method in pairs({
        SetChecked = Store("checked"), GetChecked = Fetch("checked"),
        SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
        SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"),
        SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
        SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
        SetPropagateMouseWheel = Store("propagateMouseWheel"),
        SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
        HasFocus = function() return false end, ClearFocus = function() end, SetFocus = function() end,
        HighlightText = function() end, SetCursorPosition = function() end, GetCursorPosition = function() return 0 end,
        SetTextInsets = function() end, SetTimerDuration = function() end,
        EnableKeyboard = function() end, SetPropagateKeyboardInput = function() end,
        SetScrollChild = Store("scrollChild"), GetScrollChild = Fetch("scrollChild"), SetVerticalScroll = Store("verticalScroll"),
        GetVerticalScroll = function(self) return self.verticalScroll or 0 end, GetVerticalScrollRange = function() return 0 end,
        Click = function(self, button)
            local handler = self:GetScript("OnClick")
            if handler then return handler(self, button or "LeftButton") end
        end,
    }) do
        if Methods[name] == nil then Methods[name] = method end
    end
    local StubGetValue = Methods.GetValue
    Methods.GetValue = function(self)
        local value = StubGetValue(self)
        if value == nil then value = self.minimum or 0 end
        return value
    end
    if options.clientScriptBindings == true then InstallClientScriptBindings(Methods, options.nativeButtonLifecycle) end
    -- Harness gap only: every client defines it, and the core reads it at load.
    world.env.MAX_BOSS_FRAMES = 5
    if type(options.beforeOptions) == "function" then
        -- Boot by hand so the caller can wrap core APIs the Options files
        -- capture as upvalues while they load.
        local suffix = world.client.tocSuffix or flavor
        local gameType = world.client.isForever and "camelot" or nil
        world.corePaths = World.Graph(world.root, World.CoreTOC(suffix), world.env.GetLocale(), gameType)
        world.optionsPaths = World.Graph(world.root, World.OptionsTOC(suffix), world.env.GetLocale(), gameType)
        world:LoadGraph("MidnightSimpleUnitFrames", world.corePaths, world.core)
        options.beforeOptions(world)
        world:LoadGraph("MidnightSimpleUnitFrames_Options", world.optionsPaths, world.options)
    else
        world:Boot()
    end
    local failure = world:FirstFailure()
    if failure then error("menu_core_world " .. flavor .. ": boot failed in " .. tostring(failure.file) .. ": " .. tostring(failure.message), 2) end
    local env, core = world.env, world.core
    assert(loadfile(root .. "/tools/tests/unit_scene_region_fixture.lua"))().Install(core)
    local M = assert(core.MSUF2, "menu_core_world: Menu2 did not load")
    env.MSUF_EnsureDB(true)
    -- The queued unit-frame runtime apply reads APIs the harness only stubs.
    if options.keepFlush ~= true then M.ApplyService.Flush = function() return true end end
    local handle = setmetatable({ world = world, env = env, core = core, M = M }, Handle)
    if options.open == false then return handle end
    assert(M.Open(options.page or "home") ~= false, "menu_core_world: the menu did not open")
    world.widgets:RunTimers()
    local win = assert(M.frame, "menu_core_world: the menu window was not built")
    FireVisibilityScripts(win)
    if M.minimizedBar then FireVisibilityScripts(M.minimizedBar) end
    -- Reopen through the real show path so the window's OnShow lifecycle runs.
    M.HideSlashMenuAndMinibar(win)
    world.widgets:RunTimers()
    assert(M.Open(options.page or "home") ~= false, "menu_core_world: the menu did not reopen")
    world.widgets:RunTimers()
    handle.win = win
    return handle
end

return MenuWorld
