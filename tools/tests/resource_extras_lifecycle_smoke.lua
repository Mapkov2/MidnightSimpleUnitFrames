-- resource_extras_lifecycle_smoke.lua <repoRoot> <flavor>
--
-- The optional resource helpers (ClassPower/MSUF_CP_ResourceExtras.lua) keep
-- themselves current without the class power refresh:
-- (a) a shapeshift in combat hides the Mana helpers on a bar that no longer
--     shows Mana, without geometry changes, and rebuilds them at combat end;
-- (b) a spec, form or displayed-power change rebuilds them out of combat, also
--     with Class Resources off (the class power refresh does not run then);
-- (c) a resized host rebuilds them;
-- (d) disabling in combat parks an aura helper that could not park yet once
--     combat ends instead of leaving it active with no events;
-- and the class power controller and its config ask the one shared predicate.
--
-- Plain Lua 5.1: repo root and flavor (Mainline, Forever, Vanilla, TBC, Mists).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local combat = false
local function Geometry() Check(not combat, "frame or region geometry changed in combat") end
local frames, deferred, sensors = {}, {}, {}
local M = {}
M.__index = M
local function NewObject(kind, parent)
    local object = setmetatable({ kind = kind, parent = parent, events = {}, scripts = {}, hooks = {},
        shown = kind ~= "Texture", level = 2 }, M)
    frames[#frames + 1] = object
    return object
end
function M:SetScript(name, callback) self.scripts[name] = callback end
function M:HookScript(name, callback) self.hooks[name] = callback end
function M:RegisterEvent(event) self.events[event] = true end
function M:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
function M:UnregisterEvent(event) self.events[event] = nil end
function M:UnregisterAllEvents() self.events = {} end
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetWidth", "SetHeight", "SetSize", "SetFrameLevel",
    "SetParent", "SetOrientation", "SetReverseFill", "SetStatusBarTexture", "SetDrawLayer", "AddMaskTexture",
    "RemoveMaskTexture" }) do
    M[name] = function(self, ...) Geometry(); self["last" .. name] = { ... } end
end
function M:SetStatusBarTexture() Geometry(); self.fill = self.fill or NewObject("Texture", self) end
function M:GetStatusBarTexture() return self.fill end
function M:SetParent(parent) Geometry(); self.parent = parent end
function M:GetFrameLevel() return self.level end
function M:GetWidth() return self.w or 200 end
function M:GetHeight() return self.h or 10 end
function M:GetOrientation() return "HORIZONTAL" end
function M:GetReverseFill() return false end
function M:GetNumMaskTextures() return 0 end
function M:GetMaskTexture() return nil end
function M:IsForbidden() return false end
function M:CreateTexture() return NewObject("Texture", self) end
function M:CreateMaskTexture() return NewObject("MaskTexture", self) end
function M:CreateFontString() return NewObject("FontString", self) end
function M:SetColorTexture() end
function M:SetTexture() end
function M:SetVertexColor() end
function M:SetFont() end
function M:SetMinMaxValues() end
function M:SetValue() end
function M:SetTimerDuration() end
function M:SetDurationBar() end
function M:SetDurationText() end
function M:EnableMouse() end
function M:Show() self.shown = true end
function M:Hide() self.shown = false end
function M:SetShown(value) self.shown = value and true or false end
function M:IsShown() return self.shown end
function M:SetStatusBarColor(r, g, b, a) self.color = { r, g, b, a }; if self.colorHook then self.colorHook(self, r, g, b, a) end end
function M:GetStatusBarColor() return .2, .3, .4, 1 end
CreateFrame = function(kind, _, parent) return NewObject(kind, parent) end
hooksecurefunc = function(object, method, callback) assert(method == "SetStatusBarColor"); object.colorHook = callback end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
InCombatLockdown = function() return combat end
GetTime = function() return 10 end
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end,
    NewTimer = function() return { Cancel = function() end } end }
C_DurationUtil = { CreateDuration = function() return { SetTimeFromStart = function() end } end }
C_StringUtil = { CreateNumericRuleFormatter = function() return { SetBreakpoints = function() end } end }
C_CurveUtil = { CreateColorCurve = function()
    return { SetType = function() end, ClearPoints = function() end, AddPoint = function() end,
        EvaluateUnpacked = function() return 1, 1, 1, 1 end }
end }
CreateColor = function(r, g, b, a) return { r, g, b, a, SetRGBA = function() end } end
Enum = { StatusBarInterpolation = { Immediate = 0 }, StatusBarTimerDirection = { RemainingTime = 1 },
    NumericRuleFormatRounding = { Nearest = 0, Down = 1 }, LuaCurveType = { Step = 1 },
    DurationTextBindingProperty = { RemainingDuration = 1 } }
STANDARD_TEXT_FONT = "font"
local powerType = 0
UnitPowerType = function() return powerType, powerType == 0 and "MANA" or "ENERGY" end
UnitPower = function() return 50 end
UnitPowerMax = function() return 100 end
UnitPowerPercent = nil
UnitSpellHaste = function() return 0 end
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
C_Spell = { GetSpellPowerCost = function() return { { type = 0, cost = 30 } } end,
    DoesSpellExist = function(id) return flavor == "Mainline" and id == 190456 end }
canaccesstable = function() return true end
local spec = 1
MSUF_Auras3 = { CreateClassPowerAuraSensor = function(host, key, spells, initialize)
    local sensor = { host = host, spells = spells, SetEnabled = function(self, value) self.enabled = value end }
    sensor.button = NewObject("Frame", host); initialize(sensor.button); sensors[#sensors + 1] = sensor
    return sensor
end }

local ns = { Client = { IsRetail = flavor == "Mainline" or flavor == "Forever", IsForever = flavor == "Forever",
    IsClassic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists" }, CPBuilders = {} }
for _, name in ipairs({ "ExtraAuras", "ManaExtras", "ResourceMarks", "ResourceExtras" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_" .. name .. ".lua"))("MSUF", ns)
end
local player = NewObject("Frame")
local powerBar = NewObject("StatusBar", player)
powerBar:SetStatusBarTexture()
player.targetPowerBar = powerBar
local bars = {}
local E = { db = { bars = bars }, NotSecret = function() return true end, GetPlayerFrame = function() return player end,
    GetSpec = function() return spec end, PLAYER_CLASS = "WARRIOR", Texture = function() return "texture" end,
    CP = { bars = {}, visible = false }, AM = { visible = false } }
local firstFrame = #frames + 1
local extras = ns.CPBuilders.ResourceExtras(E)
local lifecycle = Check(frames[firstFrame], "the lifecycle owns no event frame")
local function Fire(event, unit)
    for _, object in ipairs(frames) do
        local handler = object.scripts.OnEvent
        if handler and object.events[event] then handler(object, event, unit or "player") end
    end
end
local function RunDeferred()
    local queue = deferred
    deferred = {}
    for _, callback in ipairs(queue) do callback() end
end
local function ManaStrips()
    local list = {}
    for _, object in ipairs(frames) do
        if object.kind == "StatusBar" and object.parent == powerBar then list[#list + 1] = object end
    end
    return list
end

-- One predicate for the controller, its config and the lifecycle.
Check(ns.CPBuilders.ResourceExtrasWanted({}) == false, "no switch must want a helper")
for _, key in ipairs({ "showIgnorePain", "showArcaneWindow", "manaUpcomingCost", "manaRegenPause", "manaGainPulse" }) do
    Check(ns.CPBuilders.ResourceExtrasWanted({ [key] = true }) == true, key .. " does not want a helper")
end
Check(ns.CPBuilders.ResourceExtrasWanted({ resourceMarks = { {} } }) == true, "resource marks do not want a helper")
for _, path in ipairs({ "MSUF_CP_Controller.lua", "MSUF_CP_Controller_Config.lua" }) do
    local f = assert(io.open(root .. "/MidnightSimpleUnitFrames/ClassPower/" .. path, "rb"))
    local source = f:read("*a"); f:close()
    Check(source:find("ResourceExtrasWanted", 1, true), path .. " keeps its own copy of the helper switches")
    Check(not source:find("manaGainPulse", 1, true) and not source:find("showIgnorePain", 1, true),
        path .. " still lists helper switches by hand")
end

-- (b) Class Resources off: a spec change alone enables Ignore Pain.
bars.showIgnorePain = true
extras.Refresh()
Check(#sensors == 0, "Arms has no Ignore Pain")
Check(lifecycle.events.PLAYER_SPECIALIZATION_CHANGED and lifecycle.events.UNIT_DISPLAYPOWER and lifecycle.events.UPDATE_SHAPESHIFT_FORM,
    "the helpers do not follow spec, form or displayed-power changes")
spec = 3
Fire("PLAYER_SPECIALIZATION_CHANGED")
Check(#sensors == 0, "the rebuild ran before MSUF's own handlers saw the event")
RunDeferred()
if flavor == "Mainline" then
    Check(#sensors == 1 and sensors[1].enabled, "Protection did not get Ignore Pain without a class power refresh")
else
    Check(#sensors == 0, "Ignore Pain helper on a client without it")
end
-- Two events in one frame rebuild once.
Fire("UNIT_DISPLAYPOWER"); Fire("UPDATE_SHAPESHIFT_FORM")
Check(#deferred == 1, "a burst of cold events queued several rebuilds")
RunDeferred()

-- (d) Disabling in combat parks the aura helper once combat ends.
if flavor == "Mainline" then
    combat = true
    extras.Disable()
    Check(sensors[1].enabled, "the sensor cannot be parked in combat")
    Check(lifecycle.events.PLAYER_REGEN_ENABLED, "a helper left pending in combat has no way to finish")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Check(not sensors[1].enabled, "the aura helper was never parked after a combat disable")
    Check(next(lifecycle.events) == nil, "a disabled lifecycle kept events")
end

-- (a) Shapeshift in combat with the Mana cost preview.
bars.showIgnorePain = false
bars.manaUpcomingCost = true
spec = 1
extras.Refresh()
Fire("UNIT_SPELLCAST_START")
local strips = ManaStrips()
Check(#strips >= 1, "no mana cost preview strip was built")
local prediction
for _, strip in ipairs(strips) do if strip.lastSetReverseFill then prediction = strip end end
Check(prediction, "cost preview strip missing")
for _, object in ipairs(frames) do
    if object.scripts.OnEvent and object.events.UNIT_SPELLCAST_START then object.scripts.OnEvent(object, "UNIT_SPELLCAST_START", "player", nil, 42) end
end
Check(prediction.shown, "the cost preview did not show for a mana spell")
combat = true
powerType = 3
Fire("UPDATE_SHAPESHIFT_FORM")
RunDeferred()
Check(not prediction.shown, "the cost preview stayed on the Energy bar")
for _, object in ipairs(frames) do
    if object.scripts.OnEvent and object.events.UNIT_SPELLCAST_START then object.scripts.OnEvent(object, "UNIT_SPELLCAST_START", "player", nil, 42) end
end
Check(not prediction.shown, "a suspended cost preview reappeared on the Energy bar")
powerType = 0
Fire("UPDATE_SHAPESHIFT_FORM")
RunDeferred()
for _, object in ipairs(frames) do
    if object.scripts.OnEvent and object.events.UNIT_SPELLCAST_START then object.scripts.OnEvent(object, "UNIT_SPELLCAST_START", "player", nil, 42) end
end
Check(prediction.shown, "the cost preview did not return in caster form")
combat = false
Check(lifecycle.events.PLAYER_REGEN_ENABLED, "a combat shapeshift does not rebuild at combat end")
Fire("PLAYER_REGEN_ENABLED")

-- (c) A resized power bar rebuilds the helpers.
local before = #deferred
Check(powerBar.hooks.OnSizeChanged, "the power bar resize is not observed")
powerBar.w = 260
powerBar.hooks.OnSizeChanged(powerBar)
Check(#deferred == before + 1, "a resized power bar did not request a rebuild")
RunDeferred()
Check(prediction.lastSetSize and prediction.lastSetSize[1] == 260, "the cost preview kept the old bar width")

print("resource_extras_lifecycle_smoke: " .. flavor .. " OK")
