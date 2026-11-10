local root = assert(arg[1], "repository root required")
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
Secrets.GUARD_NAMES.falsy.Number = true
local now, combat = 100, false
local pending, objects, mirrorData, mirrorValues = {}, {}, {}, {}
local function noop() end
local methods = {}
for _, key in ipairs({ "SetMovable", "SetClampedToScreen", "RegisterForDrag", "ClearAllPoints", "SetFrameStrata" }) do
    methods[key] = noop
end
function methods:SetScript(key, value) self.scripts[key] = value end
function methods:GetScript(key) return self.scripts[key] end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterAllEvents() for key in pairs(self.events) do self.events[key] = nil end end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:IsForbidden() return false end
function methods:IsProtected() return false end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(value) self.scale = value end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:SetFrameStrata(value) self.strata = value end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetParent() return self.parent end
function methods:SetPoint(point, parent, relativePoint, x, y) self.x, self.y = x, y end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetMinMaxValues(low, high) self.low, self.high = low, high end
function methods:GetMinMaxValues() return self.low, self.high end
function methods:SetReverseFill(value) self.reverse = value end
function methods:SetValue(value) self.value = value end
function methods:SetText(text) self.text = text end
function methods:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function methods:SetStatusBarColor(r, g, b) self.r, self.g, self.b = r, g, b end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetCenter() return self.centerX or 500, self.centerY or 400 end
local function object(parent)
    local frame = setmetatable({ scripts = {}, events = {}, parent = parent, alpha = 1, width = 250, height = 18 }, { __index = methods })
    objects[#objects + 1] = frame
    return frame
end
_G.CreateFrame = function() return object(_G.UIParent) end
_G.UIParent = object()
_G.GetTime = function() return now end
_G.C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
_G.Enum = { StartTimerType = { PvPBeginTimer = 1, PlayerCountdown = 3 } }
_G.GetMirrorTimerInfo = function(index)
    if mirrorData[index] then return unpack(mirrorData[index]) end
    return "UNKNOWN"
end
_G.GetMirrorTimerProgress = function(timer) return mirrorValues[timer] end
local saved = { general = {} }
local editChanged, module, driver
local ns = { Util = { InCombat = function() return combat end }, EventBus = { listeners = {} }, Castbars = {} }
function ns.EventBus:Register(event, key, callback) self.listeners[key] = callback end
function ns.EventBus:Unregister(event, key) self.listeners[key] = nil end
function ns.Require(name)
    if name == "MSUF_RegisterAnyEditModeListener" then return function(callback) editChanged = callback end end
    if name == "MSUF_PixelLayoutRegion" then return function(frame) return frame end end
    error("unexpected dependency: " .. name)
end
ns.Translate = function(value) return value end
ns.MSUF_RegisterModule = function(_, definition) module = definition end
ns.Castbars.Config = { Source = function() return saved end }
ns.Castbars.Anchors = { GetCastbarDesiredSize = function() return 271, 22 end }
ns.Castbars.Utils = { GetReverseFillSafe = function() return false end }
ns.Castbars.Core = { ApplyCastbarFrameLayer = noop, ApplyCastbarSparkVisual = noop }
ns.Castbars.Visuals = { RefreshCastbarFrame = function(frame) frame.paintedStyle = true end }
ns.Castbars.Frames = { CreateCastbarPreviewFrame = function(_, _, opts)
    local frame = object(opts.parent or UIParent)
    frame.statusBar, frame.castText, frame.timeText = object(frame), object(frame), object(frame)
    frame.backgroundBar = object(frame)
    return frame
end }
local function flush()
    local callbacks = pending
    pending = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local function fire(event, ...)
    if driver.events[event] then driver.scripts.OnEvent(driver, event, ...) end
    flush()
end
local function tick(seconds)
    now = now + seconds
    if driver.scripts.OnUpdate then driver.scripts.OnUpdate(driver, seconds) end
end
if arg[2] ~= "without-feature" then
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_TimerBars.lua"))("MSUF", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_TimerBarVisuals.lua"))("MSUF", ns)
end
local Bars = assert(ns.TimerBars, "timer bars must be provided by the core")
driver = objects[2]
local countBefore = #objects
assert(not Bars.GetEnabled() and next(saved.general) == nil, "disabled reads must not seed a profile")
fire("PLAYER_ENTERING_WORLD")
assert(next(driver.events) == nil and not driver.scripts.OnUpdate and #objects == countBefore, "disabled module stays idle")
assert(Bars.Set("breath", "enabled", true))
local breath = Bars.States.breath
assert(breath.frame.paintedStyle and breath.frame.width == 271 and breath.frame.height == 22)
assert(not breath.frame.shown and not driver.scripts.OnUpdate)
_G.MirrorTimer1 = object()
MirrorTimer1.timer, MirrorTimer1.alpha = "BREATH", 0.8
mirrorValues.BREATH = 65000
fire("MIRROR_TIMER_START", "BREATH", 65000, 180000, -1, 0, "Breathing")
assert(breath.frame.shown and breath.frame.timeText.text == "1:05")
assert(MirrorTimer1.alpha == 0 and driver.scripts.OnUpdate)
Bars.Set("breath", "lowWarning", true)
fire("MIRROR_TIMER_START", "BREATH", 15000, 180000, -1, 0, "Breathing")
assert(breath.frame.statusBar.r == 1 and breath.frame.statusBar.g == 0.1)
mirrorValues.BREATH = 25000
tick(0.05)
assert(breath.rising and breath.frame.statusBar.g == 0.65 and breath.frame.alpha == 1, "refilling never warns")
fire("MIRROR_TIMER_PAUSE", "BREATH", true)
assert(not driver.scripts.OnUpdate and breath.frame.shown, "paused timer costs no ticks")
fire("MIRROR_TIMER_PAUSE", "BREATH", false)
assert(driver.scripts.OnUpdate)
assert(Bars.Set("fatigue", "enabled", true))
mirrorValues.EXHAUSTION = 20000
fire("MIRROR_TIMER_START", "EXHAUSTION", 20000, 60000, -1, 0, "Fatigue")
fire("MIRROR_TIMER_STOP", "BREATH")
assert(not breath.frame.shown and Bars.States.fatigue.frame.shown and driver.scripts.OnUpdate)
assert(MirrorTimer1.alpha == 0.8, "restore exact native alpha")
fire("MIRROR_TIMER_STOP", "EXHAUSTION")
assert(not driver.scripts.OnUpdate)
Bars.Set("feign", "enabled", true)
mirrorValues.DEATH = 90000
fire("MIRROR_TIMER_START", "DEATH", 90000, 360000, -1, false, "Feign Death")
assert(Bars.States.feign.frame.shown)
fire("MIRROR_TIMER_STOP", "FEIGNDEATH")
assert(Bars.States.feign.frame.shown, "a different mirror key cannot stop this timer")
fire("MIRROR_TIMER_PAUSE", "FEIGNDEATH", true)
assert(not Bars.States.feign.paused, "a different mirror key cannot pause this timer")
fire("MIRROR_TIMER_STOP", "DEATH")
Bars.Set("countdown", "enabled", true)
local nativeBar = object()
nativeBar:Show()
local nativeTimer = { type = 3, bar = nativeBar, barShowing = true }
_G.TimerTracker = { timerList = { nativeTimer } }
fire("START_PLAYER_COUNTDOWN", "guid", 40, 40)
local countdown = Bars.States.countdown
assert(countdown.frame.shown)
assert(not nativeBar:IsShown(), "native countdown bar is hidden independently of its parent")
nativeBar:SetAlpha(1)
assert(not nativeBar:IsShown(), "native fade completion cannot expose the suppressed child")
tick(10)
assert(not countdown.frame.shown and countdown.active, "golden numbers own the last thirty seconds by default")
Bars.Set("countdown", "showUnderNumbers", true)
assert(countdown.frame.shown)
fire("START_PLAYER_COUNTDOWN", "guid", 5, 5)
assert(countdown.deadline == now + 5, "replacement countdown uses its new deadline")
tick(5)
assert(not countdown.active and not driver.scripts.OnUpdate, "expired countdown stops ticking immediately")
fire("START_PLAYER_COUNTDOWN", "guid", 7, 7)
fire("CANCEL_PLAYER_COUNTDOWN")
assert(not countdown.active)
assert(nativeBar:IsShown() and nativeBar.alpha == 1, "native child visibility restores on cancellation")
Bars.Set("battle", "enabled", true)
fire("START_TIMER", 1, 15, 60)
assert(Bars.States.battle.frame.shown)
tick(5)
assert(not Bars.States.battle.frame.shown)
fire("PLAYER_ENTERING_WORLD")
assert(not Bars.States.battle.active, "zoning clears the battleground timer")
mirrorData[1] = { "BREATH", 120000, 180000, -1, 0, "Breathing" }
mirrorValues.BREATH = 120000
fire("PLAYER_ENTERING_WORLD")
assert(breath.frame.shown and breath.value == 120000, "reload recovers a running mirror timer")
editChanged(true)
assert(breath.frame.mouse and Bars.States.battle.frame.shown)
fire("MIRROR_TIMER_STOP", "BREATH")
assert(breath.frame.shown and breath.frame.mouse, "stopping a live timer retains its edit sample")
fire("START_PLAYER_COUNTDOWN", "guid", 1, 1)
tick(1)
assert(countdown.frame.shown, "countdown expiry retains its edit sample")
breath.frame.centerX, breath.frame.centerY = 623, 355
breath.frame.scripts.OnDragStart(breath.frame)
assert(breath.frame.moving)
breath.frame.scripts.OnDragStop(breath.frame)
assert(saved.general.castbarTimers.breath.x == 123 and saved.general.castbarTimers.breath.y == -45)
combat = true
fire("PLAYER_REGEN_DISABLED")
assert(not breath.frame.mouse and not Bars.IsPreview())
assert(not Bars.Set("breath", "width", 400) and not Bars.SavePosition("breath", 1, 2))
combat = false
Bars.Set("breath", "ownSize", true)
Bars.Set("breath", "width", 333)
Bars.Set("breath", "height", 33)
assert(breath.frame.width == 333 and breath.frame.height == 33)
local snapshot = saved.general.castbarTimers.breath.width
local sample = Bars.CreateMenuPreview(UIParent, "breath")
Bars.RefreshMenuPreview(sample, "breath")
Bars.Paint(sample, now, false)
assert(sample.frame ~= breath.frame and sample.frame.parent == UIParent and sample.frame.width == 333)
assert(saved.general.castbarTimers.breath.width == snapshot, "menu preview never edits its live profile")
local stopWatching = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_TimerBars.lua", { strict = true })
local secret = Secrets.New("number")
fire("MIRROR_TIMER_START", secret, 1, 2, -1, false, "private")
fire("MIRROR_TIMER_START", "BREATH", secret, 2, -1, false, "private")
fire("MIRROR_TIMER_PAUSE", "BREATH", secret)
fire("START_TIMER", secret, 1, 2)
fire("START_PLAYER_COUNTDOWN", "guid", secret, 2)
fire("STOP_TIMER_OF_TYPE", secret)
local violations = stopWatching()
assert(#violations == 0, "timer events must check secrets before inspecting their values")
for _, id in ipairs(Bars.Order) do Bars.Set(id, "enabled", false) end
assert(not driver.scripts.OnUpdate and next(driver.events) == nil and next(ns.EventBus.listeners) == nil)
assert(MirrorTimer1.alpha == 0.8)
saved = { general = {} }
Bars.Apply()
assert(next(saved.general) == nil, "profile switch does not manufacture timer overrides")
print("timer bars: runtime, refill, pause, countdowns, native restore, preview, drag and combat checks passed")
