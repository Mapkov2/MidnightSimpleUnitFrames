-- The legacy UI bridge and core settings signal share one real preview painter.
-- Settings notifications use the real shipped providers and visible preview ownership.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local mutation = arg[3]
if mutation then
    local load = world.LoadFile
    world.LoadFile = function(self, path, addon, namespace)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local before, after
        if mutation == "bridge-signal" and path:find("MSUF_Menu2_ApplyService.lua", 1, true) then
            before = 'return MSUF.Require("MSUF_UFPreview_RequestRefresh", "Shell/Menu2/MSUF_Menu2_ApplyService.lua")(...)'
            after = 'return MSUF.EventBus:Publish("CONFIG_APPLIED", ...)'
        elseif mutation == "idle-unsubscribe" and path:find("MSUF_Menu2_UnitPreview_API.lua", 1, true) then
            before, after = 'if not subscribed then return end', 'do end'
        end
        if not before then return load(self, path, addon, namespace) end
        local first, last = source:find(before, 1, true)
        assert(first, "missing causal mutation target")
        local chunk = assert(loadstring(source:sub(1, first - 1) .. after .. source:sub(last + 1), "@" .. path))
        setfenv(chunk, self.env)
        return pcall(chunk, addon, namespace)
    end
end
local timerWidgets = world.widgets
for _, name in ipairs({ "After", "NewTimer" }) do
    local native = world.env.C_Timer[name]
    world.env.C_Timer[name] = function(delay, callback)
        local result = native(delay, callback)
        local entry = timerWidgets.timers[#timerWidgets.timers]
        if entry then entry.due = timerWidgets:GetTime() + delay end
        return result
    end
end
local function Advance(delta)
    local target, ran = timerWidgets:GetTime() + delta, 0
    while true do
        local selected, due
        for index, entry in ipairs(timerWidgets.timers) do
            if entry.due <= target and (not due or entry.due < due) then selected, due = index, entry.due end
        end
        if not selected then break end
        local entry = table.remove(timerWidgets.timers, selected)
        timerWidgets:SetTime(due)
        if not entry.cancelled and not (entry.timer and entry.timer.cancelled) then entry.callback() end
        ran = ran + 1
        assert(ran < 2000, "test timer loop did not settle")
    end
    timerWidgets:SetTime(target)
end
world.env.MAX_BOSS_FRAMES = 5
world.env.UnitExists = function() return false end
world.env.UnitName = function() return "Player" end
for name, value in pairs({ UnitHealth = 500000, UnitHealthMax = 1000000, UnitPower = 100, UnitPowerMax = 100,
    UnitPowerType = 0, UnitHealthPercent = 50, UnitPowerPercent = 100, UnitGetTotalAbsorbs = 0,
    UnitGetIncomingHeals = 0, UnitGetTotalHealAbsorbs = 0, UnitEffectiveLevel = 90, GetMaxPlayerLevel = 90,
    GetMaxLevelForPlayerExpansion = 90 }) do world.env[name] = function() return value end end
world.env.AbbreviateNumbers, world.env.AbbreviateLargeNumbers = tostring, tostring
world.env.C_StringUtil = { AbbreviateNumbers = tostring, AbbreviateLargeNumbers = tostring }
world:Boot()
local failure = world:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env, ns, widgets = world.env, world.core, world.widgets
-- Unknown frame globals in the boot harness use a truthy sentinel. Native
-- missing named frames are nil; false permits the real factory to create them.
for _, unit in ipairs(ns.UF.unitOrder) do env[ns.UF.FrameName(unit)] = false end
env.MSUF_EnsureDB(true)
local Preview, M, bus = ns.UFPreview, ns.MSUF2, ns.EventBus
local methods = widgets.Methods
for _, key in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetAutoFocus", "SetMaxLetters",
    "EnableKeyboard", "SetNumeric", "SetTextInsets", "ClearFocus", "SetCursorPosition", "HighlightText",
    "SetPropagateKeyboardInput", "SetPropagateMouseWheel", "SetValueStep", "SetObeyStepOnDrag" }) do
    if not methods[key] then methods[key] = function() end end
end
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
for name, method in pairs({
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"), SetStepsPerPage = Store("stepsPerPage"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, SetFocus = function() end, GetCursorPosition = function() return 0 end,
    SetTimerDuration = function() end,
    SetScrollChild = Store("scrollChild"), GetScrollChild = Fetch("scrollChild"), SetVerticalScroll = Store("verticalScroll"),
    GetVerticalScroll = function(self) return self.verticalScroll or 0 end, GetVerticalScrollRange = function() return 0 end,
}) do
    if methods[name] == nil then methods[name] = method end
end
-- The stub keeps geometry in plain fields; regions that carry a child named
-- "left" or "bottom" (bar outline pieces) are not a position.
local function Coord(self, field)
    local value = rawget(self, field)
    return type(value) == "number" and value or 0
end
methods.GetCenter = function(self)
    return Coord(self, "left") + Coord(self, "width") / 2, Coord(self, "bottom") + Coord(self, "height") / 2
end
-- A native slider starts at its minimum; the stub leaves the value unset.
local StubGetValue = methods.GetValue
methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end
env.C_Texture = { GetAtlasInfo = function() return nil end }

local Apply = ns.ApplyService
local bridge
local attach = Apply.AttachUI
Apply.AttachUI = function(callback)
    bridge = callback
    return attach(callback)
end
local ok, message = world:LoadFile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ApplyService.lua",
    "MidnightSimpleUnitFrames_Options", ns)
assert(ok, tostring(message))
Apply.AttachUI = attach
local function Pack(...) return { n = select("#", ...), ... } end
local calls = {}
local public = env.MSUF_UFPreview_RequestRefresh
local marker = {}
env.MSUF_UFPreview_RequestRefresh = function(reason, ...)
    calls[#calls + 1] = { reason = reason, args = Pack(...) }
    if reason == "bridge-return" then return nil, marker, false end
    return public(reason, ...)
end
local result = Pack(bridge("RefreshUnitPreview", "bridge-return", 17))
assert(#calls == 1 and calls[1].reason == "bridge-return" and calls[1].args.n == 1 and calls[1].args[1] == 17,
    "UI bridge bypassed or altered the legacy public refresh invocation")
assert(result.n == 3 and result[1] == nil and result[2] == marker and result[3] == false,
    "UI bridge changed public refresh return arity or values")
M.frame = env.CreateFrame("Frame", nil, env.UIParent)
M.frame:Show()
M.activeKey = "unit-test"
local function Box()
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "target" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box._msuf2PinnedPreviewPageKey = "unit-test"
    box.canvas:SetSize(400, 200)
    -- The shared widget kit stores visibility only. Deliver the actual native
    -- Show/Hide callbacks on these two real preview boxes, without fake owners.
    local show, hide = box.Show, box.Hide
    box.Show = function(self)
        local changed = not self:IsShown()
        show(self)
        if changed then self:GetScript("OnShow")(self) end
    end
    box.Hide = function(self)
        local changed = self:IsShown()
        hide(self)
        if changed then self:GetScript("OnHide")(self) end
    end
    box:Show()
    return box
end
local paints, depth, lastBox = 0, 0
local painter = Preview.Refresh
Preview.Refresh = function(box, reason)
    depth = depth + 1
    assert(depth == 1, "settings delivery reentered the real painter")
    paints = paints + 1
    lastBox = box
    local value = painter(box, reason)
    depth = depth - 1
    assert(box._msufPreviewScene and box._msufPreviewScene.complete, "real preview scene did not finish")
    assert(box.mock.healthBar and box.mock.healthBar:GetValue() ~= nil, "real health painter reached no native sink")
    return value
end
local box = Box()
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.1)
local signals = 0
bus:Register("CONFIG_APPLIED", "test.bridge", function() signals = signals + 1 end)
local before, requests, count = paints, #calls, signals
assert(Apply.RequestUnitDomains("target", "MSUF2_BRIDGE_TYPED", { notify = false, text = true }))
Advance(0.039)
assert(paints == before, "typed UI bridge shortened the existing apply delay")
Advance(0.061)
assert(signals > count, "real core apply stopped publishing its independent settings signal")
assert(#calls == requests + 1 and calls[#calls].reason == "MSUF2_BRIDGE_TYPED", "typed apply lost its one public call")
assert(paints == before + 1 and lastBox == box and box._msufPreviewScene.reason == "MSUF2_BRIDGE_TYPED",
    "core publication plus public bridge duplicated or lost the real paint")
Advance(0.3)
assert(paints == before + 1, "typed bridge did not settle after one paint")
bridge("RefreshUnitPreview", "hidden-pending")
box:Hide()
Preview.UninstallRefreshHooks()
before = paints
Advance(0.1)
assert(paints == before, "hidden owner ran its queued real paint")
local unregisters = 0
local unregister = bus.Unregister
bus.Unregister = function(self, ...)
    unregisters = unregisters + 1
    return unregister(self, ...)
end
for _ = 1, 3 do bridge("RefreshUnitPreview", "idle") end
assert(unregisters == 0, "inactive preview attempted an empty EventBus unsubscribe")
bus.Unregister = unregister
box:Show()
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.1)
local replacement = Box()
Preview.RequestRefreshForBox(replacement, "SHOW")
box:Hide()
Preview.UninstallRefreshHooks()
Advance(0.1)
before = paints
bus:Publish("CONFIG_APPLIED", "replacement")
bridge("RefreshUnitPreview", "replacement-bridge")
Advance(0.1)
assert(paints == before + 1 and lastBox == replacement and Preview.active == replacement,
    "old owner disconnected or duplicated its replacement's real paint")
widgets:SetCombat(true)
before = paints
bus:Publish("CONFIG_APPLIED", "combat-suppressed")
bridge("RefreshUnitPreview", "combat-explicit")
Advance(0.1)
assert(paints == before and replacement._refreshAfterCombatReason == "combat-explicit",
    "public bridge lost its explicit deferred combat request")
widgets:SetCombat(false)
world:FireEvent("PLAYER_REGEN_ENABLED")
Advance(0.1)
assert(paints == before + 1 and replacement._msufPreviewScene.reason == "combat-explicit",
    "combat exit did not paint the public bridge's deferred reason exactly once")
world:FireEvent("PLAYER_REGEN_ENABLED")
Advance(0.1)
assert(paints == before + 1, "combat retry did not settle")
M.activeKey = "other-page"
bridge("RefreshUnitPreview", "inactive-page")
Advance(0.1)
assert(Preview.active == nil and paints == before + 1, "inactive page retained a real-paint owner")
local subscribers = bus.handlers.CONFIG_APPLIED
assert(not (subscribers and subscribers.index["Menu2.UnitPreview.ConfigApplied"]), "inactive page retained subscription")
M.activeKey = "unit-test"
replacement._msuf2PinnedFloating = true
replacement._msuf2PinnedPreviewWrapper = { IsShown = function() return false end }
replacement:Show()
Preview.RequestRefreshForBox(replacement, "SHOW")
Advance(0.1)
before = paints
bridge("RefreshUnitPreview", "floating")
Advance(0.1)
assert(paints == before + 1 and Preview.active == replacement, "floating owner followed a hidden page wrapper")
replacement:Hide()
Preview.UninstallRefreshHooks()
bus:Unregister("CONFIG_APPLIED", "test.bridge")
assert(bus.handlers.CONFIG_APPLIED == nil, "real-paint lifecycle leaked its settings subscriber")
print("preview_config_apply_bridge_smoke: " .. flavor .. " legacy calls/returns, real paints, settle and owners passed")
