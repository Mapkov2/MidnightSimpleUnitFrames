-- Shared offline WoW client stubs for the MSUF smoke suite.
--
-- Around 175 smokes used to hand-roll the same CreateFrame/UIParent/C_Timer
-- boilerplate, and every copy drifted a little. This module owns one faithful
-- minimal environment instead. The method surface below is the union of what
-- those hand-rolled copies actually installed, and each method keeps the
-- observable semantics the majority of them relied on: setters store, getters
-- return what was stored.
--
-- Usage (tools/*_smoke.lua run with cwd = repo root, .github/** smokes get the
-- repo root as arg[1]):
--
--     local Stubs = assert(loadfile((arg and arg[1] or ".")
--         .. "/.github/scripts/msuf_test_stubs.lua"))()
--     local env = Stubs.New({ timer = "queue" })
--     env:InstallGlobals()
--
-- Deliberate defaults, because the hand-rolled copies disagreed:
--   * new frames start hidden (shown = false) -- pass shown = true to flip it,
--   * C_Timer.After runs its callback immediately ("immediate", the majority);
--     "queue" collects them for env:RunTimers(), "noop" drops them,
--   * CreateFrame's name argument is not published into _G unless the caller
--     passes registerGlobalNames = true.
--
-- Nothing here is loaded by the addon; it exists only for offline tests.

local Stubs = {}

local unpack = unpack or table.unpack

local function Noop() end

local function Copy(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

--------------------------------------------------------------------------
-- Widget method surface
--------------------------------------------------------------------------
-- One table for every object type, exactly like the hand-rolled stubs: they
-- never distinguished Frame from StatusBar from Texture either, and several
-- smokes rely on being able to call bar methods on a plain frame.

local Methods = {}

-- Identity -------------------------------------------------------------
function Methods:GetObjectType() return self.objectType or "Frame" end
function Methods:IsObjectType(kind) return (self.objectType or "Frame") == kind end
function Methods:GetName() return self.frameName end
function Methods:GetDebugName() return self.frameName end
function Methods:SetID(id) self.id = id end
function Methods:GetID() return self.id or 0 end

-- Hierarchy ------------------------------------------------------------
function Methods:GetParent() return self.parent end
function Methods:SetParent(parent) self.parent = parent end
function Methods:GetChildren() return unpack(self.children) end
function Methods:GetNumChildren() return #self.children end
function Methods:GetRegions() return unpack(self.regions) end
function Methods:GetNumRegions() return #self.regions end

-- Visibility -----------------------------------------------------------
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetShown(shown) self.shown = shown and true or false end
function Methods:IsShown() return self.shown end
-- The hand-rolled copies overwhelmingly aliased IsVisible to the widget's own
-- shown flag rather than walking the parent chain, so that is what this is.
function Methods:IsVisible() return self.shown end
function Methods:SetAlpha(alpha) self.alpha = alpha end
function Methods:GetAlpha() return self.alpha end
function Methods:SetIgnoreParentAlpha(ignore) self.ignoreParentAlpha = ignore end
function Methods:IsIgnoringParentAlpha() return self.ignoreParentAlpha end
function Methods:SetIgnoreParentScale(ignore) self.ignoreParentScale = ignore end

-- Geometry -------------------------------------------------------------
function Methods:SetWidth(width) self.width = width end
function Methods:SetHeight(height) self.height = height end
function Methods:SetSize(width, height) self.width, self.height = width, height end
function Methods:GetWidth() return self.width end
function Methods:GetHeight() return self.height end
function Methods:GetSize() return self.width, self.height end
function Methods:SetScale(scale) self.scale = scale end
function Methods:GetScale() return self.scale end
function Methods:GetEffectiveScale()
    local scale, parent = self.scale or 1, self.parent
    while parent do
        scale = scale * (parent.scale or 1)
        parent = parent.parent
    end
    return scale
end

function Methods:SetPoint(point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "string" or type(relativeTo) == "number" then
        -- SetPoint("CENTER", x, y) -- the short form anchors to the parent.
        relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
    end
    self.points[#self.points + 1] = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint or point,
        x = x or 0,
        y = y or 0,
    }
end
function Methods:SetAllPoints(relativeTo)
    self.allPoints = relativeTo or self.parent or true
end
function Methods:ClearAllPoints()
    for index = #self.points, 1, -1 do self.points[index] = nil end
    self.allPoints = nil
end
function Methods:GetNumPoints() return #self.points end
function Methods:GetPoint(index)
    local entry = self.points[index or 1]
    if not entry then return nil end
    return entry.point, entry.relativeTo, entry.relativePoint, entry.x, entry.y
end
function Methods:GetPointByName(name)
    for index = 1, #self.points do
        if self.points[index].point == name then return self:GetPoint(index) end
    end
    return nil
end

function Methods:GetLeft() return self.left end
function Methods:GetRight() return (self.left or 0) + (self.width or 0) end
function Methods:GetBottom() return self.bottom end
function Methods:GetTop() return (self.bottom or 0) + (self.height or 0) end
function Methods:GetCenter()
    return (self.left or 0) + (self.width or 0) / 2, (self.bottom or 0) + (self.height or 0) / 2
end
function Methods:GetRect()
    return self.left, self.bottom, self.width, self.height
end
function Methods:SetHitRectInsets(left, right, top, bottom)
    self.hitRectInsets = { left = left, right = right, top = top, bottom = bottom }
end
function Methods:SetClampedToScreen(clamped) self.clampedToScreen = clamped end
function Methods:SetClampRectInsets() end
function Methods:SetClipsChildren(clips) self.clipsChildren = clips end

-- Layering -------------------------------------------------------------
function Methods:SetFrameLevel(level) self.frameLevel = level end
function Methods:GetFrameLevel() return self.frameLevel end
function Methods:SetFrameStrata(strata) self.frameStrata = strata end
function Methods:GetFrameStrata() return self.frameStrata end
function Methods:SetToplevel(toplevel) self.toplevel = toplevel end
function Methods:Raise() self.raised = (self.raised or 0) + 1 end
function Methods:Lower() self.raised = (self.raised or 0) - 1 end
function Methods:SetDrawLayer(layer, sublevel)
    self.drawLayer, self.drawSublevel = layer, sublevel
end
function Methods:GetDrawLayer() return self.drawLayer, self.drawSublevel end

-- Scripts and events ---------------------------------------------------
function Methods:SetScript(script, handler) self.scripts[script] = handler end
function Methods:GetScript(script) return self.scripts[script] end
function Methods:HasScript(script) return self.scripts[script] ~= nil end
function Methods:HookScript(script, handler)
    local previous = self.scripts[script]
    if previous then
        self.scripts[script] = function(...)
            previous(...)
            return handler(...)
        end
    else
        self.scripts[script] = handler
    end
end
function Methods:RegisterEvent(event) self.events[event] = true end
function Methods:RegisterUnitEvent(event) self.events[event] = true end
function Methods:RegisterAllEvents() self.events["*"] = true end
function Methods:UnregisterEvent(event) self.events[event] = nil end
function Methods:UnregisterAllEvents()
    for event in pairs(self.events) do self.events[event] = nil end
end
function Methods:IsEventRegistered(event) return self.events[event] == true end
function Methods:SetAttribute(key, value) self.attributes[key] = value end
function Methods:GetAttribute(key) return self.attributes[key] end

-- Mouse ----------------------------------------------------------------
function Methods:EnableMouse(enabled) self.mouseEnabled = enabled end
function Methods:IsMouseEnabled() return self.mouseEnabled end
function Methods:EnableMouseWheel(enabled) self.mouseWheelEnabled = enabled end
function Methods:SetMouseClickEnabled(enabled) self.mouseClickEnabled = enabled end
function Methods:SetMouseMotionEnabled(enabled) self.mouseMotionEnabled = enabled end
function Methods:SetPropagateMouseClicks(propagate) self.propagateMouseClicks = propagate end
function Methods:SetPropagateMouseMotion(propagate) self.propagateMouseMotion = propagate end
function Methods:RegisterForClicks(...) self.forClicks = { ... } end
function Methods:RegisterForDrag(...) self.forDrag = { ... } end
function Methods:IsMouseOver() return self.mouseOver == true end
function Methods:SetMovable(movable) self.movable = movable end
function Methods:IsMovable() return self.movable end
function Methods:SetResizable(resizable) self.resizable = resizable end
function Methods:SetUserPlaced(placed) self.userPlaced = placed end
function Methods:IsUserPlaced() return self.userPlaced end
function Methods:SetDontSavePosition() end
function Methods:StartMoving() self.moving = true end
function Methods:StopMovingOrSizing() self.moving = false end
function Methods:IsDragging() return self.moving == true end
function Methods:SetEnabled(enabled) self.enabled = enabled and true or false end
function Methods:Enable() self.enabled = true end
function Methods:Disable() self.enabled = false end
function Methods:IsEnabled() return self.enabled ~= false end

-- StatusBar ------------------------------------------------------------
function Methods:SetMinMaxValues(minimum, maximum)
    self.minimum, self.maximum = minimum, maximum
end
function Methods:GetMinMaxValues() return self.minimum, self.maximum end
function Methods:SetValue(value) self.value = value end
function Methods:GetValue() return self.value end
function Methods:SetStatusBarTexture(texture)
    if type(texture) == "table" then
        self.statusBarTexture = texture
    else
        self.statusBarTexturePath = texture
        self.statusBarTexture = self.statusBarTexture or self.__env:Region("Texture", self)
        self.statusBarTexture.texture = texture
    end
end
function Methods:GetStatusBarTexture()
    self.statusBarTexture = self.statusBarTexture or self.__env:Region("Texture", self)
    return self.statusBarTexture
end
function Methods:SetStatusBarColor(r, g, b, a) self.color = { r, g, b, a } end
function Methods:GetStatusBarColor()
    local color = self.color or {}
    return color[1], color[2], color[3], color[4]
end
function Methods:SetOrientation(orientation) self.orientation = orientation end
function Methods:GetOrientation() return self.orientation end
function Methods:SetReverseFill(reverse) self.reverseFill = reverse end
function Methods:GetReverseFill() return self.reverseFill end
function Methods:SetFillStyle(style) self.fillStyle = style end
function Methods:SetRotatesTexture(rotates) self.rotatesTexture = rotates end

-- Texture --------------------------------------------------------------
function Methods:SetTexture(texture) self.texture = texture end
function Methods:GetTexture() return self.texture end
function Methods:SetColorTexture(r, g, b, a)
    self.texture = nil
    self.colorTexture = { r, g, b, a }
    self.vertexColor = { r, g, b, a }
end
function Methods:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
function Methods:GetVertexColor()
    local color = self.vertexColor or {}
    return color[1], color[2], color[3], color[4]
end
function Methods:SetTexCoord(...) self.texCoord = { ... } end
function Methods:GetTexCoord() return unpack(self.texCoord or {}) end
function Methods:SetBlendMode(mode) self.blendMode = mode end
function Methods:GetBlendMode() return self.blendMode end
function Methods:SetDesaturated(desaturated) self.desaturated = desaturated end
function Methods:SetDesaturation(amount) self.desaturation = amount end
function Methods:SetRotation(rotation) self.rotation = rotation end
function Methods:SetAtlas(atlas) self.atlas = atlas end
function Methods:GetAtlas() return self.atlas end
function Methods:SetGradient(orientation, from, to)
    self.gradient = { orientation = orientation, from = from, to = to }
end
function Methods:SetMask(mask) self.mask = mask end
function Methods:AddMaskTexture(mask) self.masks[#self.masks + 1] = mask end
function Methods:RemoveMaskTexture(mask)
    for index = #self.masks, 1, -1 do
        if self.masks[index] == mask then table.remove(self.masks, index) end
    end
end
function Methods:GetNumMaskTextures() return #self.masks end
function Methods:GetMaskTexture(index) return self.masks[index] end
function Methods:SetHorizTile(tile) self.horizTile = tile end
function Methods:SetVertTile(tile) self.vertTile = tile end
function Methods:SetSnapToPixelGrid(snap) self.snapToPixelGrid = snap end
function Methods:SetTexelSnappingBias(bias) self.texelSnappingBias = bias end

-- FontString -----------------------------------------------------------
function Methods:SetText(text) self.text = text end
function Methods:GetText() return self.text end
function Methods:SetFormattedText(format, ...)
    self.text = string.format(format, ...)
end
function Methods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function Methods:GetTextColor()
    local color = self.textColor or {}
    return color[1], color[2], color[3], color[4]
end
function Methods:SetFont(path, size, flags)
    self.fontPath, self.fontSize, self.fontFlags = path, size, flags
    return true
end
function Methods:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
function Methods:SetFontObject(object) self.fontObject = object end
function Methods:GetFontObject() return self.fontObject end
function Methods:SetJustifyH(justify) self.justifyH = justify end
function Methods:GetJustifyH() return self.justifyH end
function Methods:SetJustifyV(justify) self.justifyV = justify end
function Methods:GetJustifyV() return self.justifyV end
function Methods:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
function Methods:GetShadowColor()
    local color = self.shadowColor or {}
    return color[1], color[2], color[3], color[4]
end
function Methods:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
function Methods:GetShadowOffset()
    local offset = self.shadowOffset or {}
    return offset[1], offset[2]
end
function Methods:SetWordWrap(wrap) self.wordWrap = wrap end
function Methods:SetNonSpaceWrap(wrap) self.nonSpaceWrap = wrap end
function Methods:SetMaxLines(lines) self.maxLines = lines end
function Methods:SetSpacing(spacing) self.spacing = spacing end
function Methods:GetStringWidth()
    return self.stringWidth or (#tostring(self.text or "") * 6)
end
function Methods:GetStringHeight() return self.stringHeight or (self.fontSize or 12) end
function Methods:GetNumLines() return self.numLines or 1 end
function Methods:SetFontString(fontString) self.fontString = fontString end
function Methods:GetFontString() return self.fontString end

-- Backdrop -------------------------------------------------------------
function Methods:SetBackdrop(backdrop) self.backdrop = backdrop end
function Methods:GetBackdrop() return self.backdrop end
function Methods:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function Methods:GetBackdropColor()
    local color = self.backdropColor or {}
    return color[1], color[2], color[3], color[4]
end
function Methods:SetBackdropBorderColor(r, g, b, a)
    self.backdropBorderColor = { r, g, b, a }
end

-- Cooldown -------------------------------------------------------------
function Methods:SetCooldown(start, duration)
    self.cooldownStart, self.cooldownDuration = start, duration
end
function Methods:GetCooldownTimes()
    return (self.cooldownStart or 0) * 1000, (self.cooldownDuration or 0) * 1000
end
function Methods:GetCooldownDuration() return (self.cooldownDuration or 0) * 1000 end
function Methods:Clear() self.cooldownStart, self.cooldownDuration = nil, nil end
function Methods:SetDrawEdge(draw) self.drawEdge = draw end
function Methods:SetDrawSwipe(draw) self.drawSwipe = draw end
function Methods:SetSwipeColor(r, g, b, a) self.swipeColor = { r, g, b, a } end
function Methods:SetSwipeTexture(texture) self.swipeTexture = texture end
function Methods:SetReverse(reverse) self.reverse = reverse end
function Methods:SetHideCountdownNumbers(hide) self.hideCountdownNumbers = hide end
function Methods:SetCountdownFont(font) self.countdownFont = font end
function Methods:SetUseCircularEdge(use) self.circularEdge = use end

-- Child object factories -----------------------------------------------
function Methods:CreateTexture(name, layer, template, sublevel)
    local texture = self.__env:Region("Texture", self)
    texture.frameName, texture.drawLayer, texture.drawSublevel = name, layer, sublevel
    self.regions[#self.regions + 1] = texture
    return texture
end
function Methods:CreateMaskTexture(name, layer)
    local texture = self.__env:Region("MaskTexture", self)
    texture.frameName, texture.drawLayer = name, layer
    self.regions[#self.regions + 1] = texture
    return texture
end
function Methods:CreateFontString(name, layer, template)
    local fontString = self.__env:Region("FontString", self)
    fontString.frameName, fontString.drawLayer, fontString.template = name, layer, template
    self.regions[#self.regions + 1] = fontString
    return fontString
end
function Methods:CreateLine(name, layer)
    local line = self.__env:Region("Line", self)
    line.frameName, line.drawLayer = name, layer
    self.regions[#self.regions + 1] = line
    return line
end
function Methods:CreateAnimationGroup(name)
    local group = self.__env:Region("AnimationGroup", self)
    group.frameName = name
    group.animations = {}
    return group
end
function Methods:CreateAnimation(kind, name)
    local animation = self.__env:Region(kind or "Animation", self)
    animation.frameName = name
    self.animations = self.animations or {}
    self.animations[#self.animations + 1] = animation
    return animation
end

-- Animations -----------------------------------------------------------
function Methods:Play() self.playing = true end
function Methods:Stop() self.playing = false end
function Methods:Finish() self.playing = false end
function Methods:IsPlaying() return self.playing == true end
function Methods:SetLooping(looping) self.looping = looping end
function Methods:SetDuration(duration) self.duration = duration end
function Methods:GetDuration() return self.duration end
function Methods:SetSmoothing(smoothing) self.smoothing = smoothing end
function Methods:SetOrder(order) self.order = order end
function Methods:SetStartDelay(delay) self.startDelay = delay end
function Methods:SetFromAlpha(alpha) self.fromAlpha = alpha end
function Methods:SetToAlpha(alpha) self.toAlpha = alpha end
function Methods:SetOffset(x, y) self.offset = { x, y } end

--------------------------------------------------------------------------
-- Environment
--------------------------------------------------------------------------

-- Recurring widget surfaces. Eleven harnesses hand-rolled the plain event
-- driver and four the drop-everything variant; naming them here keeps the
-- shape in one place instead of in every copy.
local Presets = {
    eventDriver = { "SetScript", "RegisterEvent", "UnregisterEvent" },
    eventDriverAll = { "SetScript", "RegisterEvent", "UnregisterAllEvents" },
}

local Environment = {}
Environment.__index = Environment

-- Create a bare widget of any object type. Regions and frames share the
-- method table, exactly like the hand-rolled stubs did.
function Environment:Region(objectType, parent)
    local widget = {
        objectType = objectType or "Frame",
        parent = parent,
        shown = self.defaultShown,
        alpha = 1,
        scale = 1,
        width = self.defaultWidth,
        height = self.defaultHeight,
        frameLevel = self.defaultFrameLevel,
        frameStrata = self.defaultStrata,
        left = 0,
        bottom = 0,
        points = {},
        children = {},
        regions = {},
        masks = {},
        scripts = {},
        events = {},
        attributes = {},
        __env = self,
    }
    setmetatable(widget, self.frameMeta)
    if self.initialize then self.initialize(widget) end
    return widget
end

function Environment:CreateFrame(frameType, name, parent, template)
    local frame = self:Region(frameType or "Frame", parent)
    frame.frameName = name
    frame.template = template
    if parent and type(parent) == "table" and parent.children then
        parent.children[#parent.children + 1] = frame
    end
    self.frames[#self.frames + 1] = frame
    if name and self.registerGlobalNames then _G[name] = frame end
    return frame
end

function Environment:SetCombat(inCombat) self.inCombat = inCombat and true or false end
function Environment:IsInCombat() return self.inCombat end

function Environment:SetTime(now) self.now = now end
function Environment:AdvanceTime(delta) self.now = self.now + delta end
function Environment:GetTime() return self.now end

-- Run every queued C_Timer callback in FIFO order, including callbacks that
-- queue further work, and report how many ran.
function Environment:RunTimers(limit)
    local ran = 0
    limit = limit or 1000
    while #self.timers > 0 and ran < limit do
        local entry = table.remove(self.timers, 1)
        ran = ran + 1
        if not entry.cancelled then entry.callback() end
    end
    return ran
end

function Environment:ClearTimers()
    for index = #self.timers, 1, -1 do self.timers[index] = nil end
end

local function MakeTicker(env, delay, callback, iterations)
    local ticker = {
        delay = delay,
        callback = callback,
        iterations = iterations,
        cancelled = false,
    }
    function ticker:Cancel() self.cancelled = true end
    function ticker:IsCancelled() return self.cancelled end
    env.tickers[#env.tickers + 1] = ticker
    return ticker
end

function Environment:BuildTimerLibrary()
    local env = self
    local mode = self.timerMode
    local full = {
        After = function(delay, callback)
            if type(delay) == "table" then delay, callback = callback, delay end
            env.afterCount = env.afterCount + 1
            if mode == "immediate" then
                if type(callback) == "function" then callback() end
            elseif mode == "queue" then
                env.timers[#env.timers + 1] = { delay = delay, callback = callback }
            end
            return nil
        end,
        NewTimer = function(delay, callback)
            env.newTimerCount = env.newTimerCount + 1
            local timer = MakeTicker(env, delay, callback, 1)
            if mode == "immediate" then
                if type(callback) == "function" then callback() end
            elseif mode == "queue" then
                env.timers[#env.timers + 1] = { delay = delay, callback = callback, timer = timer }
            end
            return timer
        end,
        NewTicker = function(delay, callback, iterations)
            env.newTickerCount = env.newTickerCount + 1
            return MakeTicker(env, delay, callback, iterations)
        end,
    }
    if not self.timerApi then return full end
    -- A harness whose own C_Timer only had After must keep only After: code
    -- that probes `if C_Timer.NewTimer then` has to see the same answer.
    local restricted = {}
    for index = 1, #self.timerApi do
        local name = self.timerApi[index]
        if full[name] == nil then
            error("msuf_test_stubs: unknown C_Timer entry " .. tostring(name), 2)
        end
        restricted[name] = full[name]
    end
    return restricted
end

-- Publish the environment as WoW globals. The set is explicit on purpose: a
-- migrated smoke must publish exactly the globals its hand-rolled stub did, so
-- that introducing a global the original left nil can never change a code path.
--
-- Default set: CreateFrame, UIParent, C_Timer, InCombatLockdown -- the four
-- that the hand-rolled copies install most often. Pass a spec table to add
-- worldFrame / time / secretValue, or to switch one of the defaults off.
local DEFAULT_GLOBALS = {
    createFrame = true,
    uiParent = true,
    timer = true,
    combat = true,
    worldFrame = false,
    time = false,
    secretValue = false,
}

function Environment:InstallGlobals(spec)
    local env = self
    local function Wanted(key)
        if spec and spec[key] ~= nil then return spec[key] and true or false end
        return DEFAULT_GLOBALS[key]
    end
    if Wanted("createFrame") then
        _G.CreateFrame = function(frameType, name, parent, template)
            return env:CreateFrame(frameType, name, parent, template)
        end
    end
    if Wanted("uiParent") then _G.UIParent = self.UIParent end
    if Wanted("worldFrame") then _G.WorldFrame = self.WorldFrame end
    if Wanted("timer") then _G.C_Timer = self:BuildTimerLibrary() end
    if Wanted("combat") then
        _G.InCombatLockdown = function() return env.inCombat end
    end
    if Wanted("time") then _G.GetTime = function() return env.now end end
    if Wanted("secretValue") then
        _G.issecretvalue = function(value)
            return type(value) == "table" and value.__secret == true
        end
    end
    return self
end

--------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------

-- options:
--   shown              default visibility of new widgets (default false)
--   width / height     default widget size (default 100 / 20)
--   frameLevel         default frame level (default 1)
--   strata             default frame strata (default "MEDIUM")
--   screenWidth/Height UIParent size (default 1920 / 1080)
--   uiScale            UIParent scale (default 1)
--   timer              "immediate" (default) | "queue" | "noop"
--   timerApi           array of C_Timer entries to expose (default all three:
--                      After, NewTimer, NewTicker)
--   combat             initial InCombatLockdown result (default false)
--   time               initial GetTime result (default 0)
--   registerGlobalNames publish CreateFrame's name argument into _G
--   methods            array of method names: restrict the widget surface to
--                      exactly these. Migrating a smoke that used a sparse
--                      hand-rolled stub passes its exact list, so "method is
--                      absent" keeps meaning what it meant before -- addon code
--                      that probes `if widget.Foo then` sees the same answer.
--   preset             name of a recurring surface in Stubs.Presets, used
--                      instead of spelling that list out again.
--   pin                map of method name -> constant (or function) that the
--                      widget must return regardless of what was stored, for
--                      harnesses that froze a getter (a fixed bar width, say).
--   initialize         function(widget) run on every freshly built widget, for
--                      harnesses that expect a bookkeeping field to be present.
function Stubs.New(options)
    options = options or {}
    local env = setmetatable({
        defaultShown = options.shown and true or false,
        defaultWidth = options.width or 100,
        defaultHeight = options.height or 20,
        defaultFrameLevel = options.frameLevel or 1,
        defaultStrata = options.strata or "MEDIUM",
        registerGlobalNames = options.registerGlobalNames and true or false,
        initialize = options.initialize,
        timerMode = options.timer or "immediate",
        timerApi = options.timerApi,
        inCombat = options.combat and true or false,
        now = options.time or 0,
        frames = {},
        timers = {},
        tickers = {},
        afterCount = 0,
        newTimerCount = 0,
        newTickerCount = 0,
    }, Environment)

    -- Each environment gets its own copy of the method table so a smoke can
    -- override a single method for all of its frames without leaking that
    -- override into another environment built in the same process.
    local methods = options.methods
    if options.preset then
        methods = Presets[options.preset]
        if methods == nil then
            error("msuf_test_stubs: unknown preset " .. tostring(options.preset), 2)
        end
    end
    if methods then
        env.Methods = {}
        for index = 1, #methods do
            local name = methods[index]
            local implementation = Methods[name]
            if implementation == nil then
                error("msuf_test_stubs: no shared implementation for " .. tostring(name), 2)
            end
            env.Methods[name] = implementation
        end
    else
        env.Methods = Copy(Methods)
    end
    if options.pin then
        for name, value in pairs(options.pin) do
            if type(value) == "function" then
                env.Methods[name] = value
            else
                env.Methods[name] = function() return value end
            end
        end
    end
    env.frameMeta = { __index = env.Methods }

    env.UIParent = env:Region("Frame")
    env.UIParent.frameName = "UIParent"
    env.UIParent.shown = true
    env.UIParent.width = options.screenWidth or 1920
    env.UIParent.height = options.screenHeight or 1080
    env.UIParent.scale = options.uiScale or 1
    env.UIParent.frameStrata = "MEDIUM"

    env.WorldFrame = env:Region("Frame")
    env.WorldFrame.frameName = "WorldFrame"
    env.WorldFrame.shown = true
    env.WorldFrame.width = env.UIParent.width
    env.WorldFrame.height = env.UIParent.height

    return env
end

-- Convenience for the common "install and forget" case.
function Stubs.Install(options)
    return Stubs.New(options):InstallGlobals()
end

Stubs.Methods = Methods
Stubs.Presets = Presets
Stubs.Noop = Noop

return Stubs
