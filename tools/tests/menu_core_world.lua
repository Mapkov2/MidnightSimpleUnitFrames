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
local function InstallClientScriptBindings(Methods)
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
    Methods.Click = function(self, button) return FireScript(self, "OnClick", button or "LeftButton") end
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
    if options.clientScriptBindings == true then InstallClientScriptBindings(Methods) end
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
