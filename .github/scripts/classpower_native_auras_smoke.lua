-- Executable lifecycle tests; the mock owns aura values, like Blizzard's slots.
local root = (...) or "."
local ns = {}
local combat, restricted, frames = false, false, 0
local sensors = {}
local function Widget(parent)
    frames = frames + 1
    local w = { parent = parent, level = 1, shown = true, width = 240 }
    function w:SetAllPoints() end
    function w:ClearAllPoints() self.points = {} end
    function w:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function w:SetHeight(v) self.height = v end
    function w:SetWidth(v) self.width = v end
    function w:GetWidth() return self.width end
    function w:SetFrameLevel(v) self.level = v end
    function w:GetFrameLevel() return self.level end
    function w:SetShown(v) self.shown = v end
    function w:Hide() self.shown = false end
    function w:Show() self.shown = true end
    function w:EnableMouse() end
    function w:SetColorTexture() end
    function w:SetTextColor() assert(not restricted, "restricted text mutation") end
    function w:SetFont() assert(not restricted, "restricted font mutation") end
    function w:SetStatusBarTexture() assert(not restricted, "restricted texture mutation") end
    function w:SetStatusBarColor(...) assert(not restricted, "restricted color mutation"); self.barColor = { ... } end
    function w:SetReverseFill() assert(not restricted, "restricted fill mutation") end
    function w:SetValue(v) self.value = v end
    function w:SetText(v) self.text = v end
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self) end
    function w:CanBeAccessedInContext() return not restricted end
    return w
end
CreateFrame = function(_, _, parent) return Widget(parent) end
InCombatLockdown = function() return combat end
C_Secrets = { ShouldAurasBeSecret = function() return restricted end }
issecretvalue = function(v) return type(v) == "table" and v.secret end
STANDARD_TEXT_FONT = "font"
Enum = { NumericRuleFormatRounding = { Nearest = 1 },
    StatusBarInterpolation = { Immediate = 0 }, StatusBarTimerDirection = { RemainingTime = 1 } }
C_StringUtil = { CreateNumericRuleFormatter = function()
    return { SetBreakpoints = function(self, rules) self.rules = rules end }
end }
C_Spell = { GetSpellMaxCumulativeAuraApplications = function() return 18 end }
C_DurationUtil = { CreateDurationTextBinding = function()
    local binding = {}
    function binding:SetUpdateInterval(v) self.interval = v end
    function binding:SetExpiredText(v) self.expired = v end
    function binding:SetZeroDurationText(v) self.zero = v end
    function binding:SetEnabled(v) self.enabled = v end
    return binding
end }
MSUF_Auras3 = { CreateClassPowerAuraSensor = function(parent, key, ids, initialize)
    local sensor, button = Widget(parent), Widget(parent)
    sensor.button, sensor.ids, sensor.key = button, ids, key
    function sensor:SetEnabled(v) self.enabled = v end
    function button:SetApplicationBar(bar, opts)
        self.bar, self.appOptions = bar, opts
    end
    function button:SetApplicationCount(text, opts) self.text, self.textOptions = text, opts end
    function button:ClearApplicationCount() self.text = nil end
    function button:SetDurationBar(bar, opts) self.bar, self.durationOptions = bar, opts end
    function button:SetDurationText(text, opts) self.text, self.durationTextOptions = text, opts end
    initialize(button)
    sensors[#sensors + 1] = sensor
    return sensor
end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_NativeAuras.lua"))("test", ns)
local cp = { visible = true, powerType = "WHIRLWIND", container = Widget(), maxBars = 1,
    bars = { Widget() }, text = Widget(), visual = { baseR = 1, baseG = .5, baseB = .2 } }
local db = { bars = { classPowerShowText = true } }
cp.bars[1]._msufCPValue = 1
local owner = ns.CPBuilders.NativeAuras({ CP = cp, db = db, Class = "WARRIOR",
    Spec = function() return 2 end, Texture = function() return "texture" end,
    TextLevel = function() return 10 end })
owner.Sync()
assert(cp.bars[1]._msufCPValue == nil, "invalidate legacy value before vehicle reuse")
assert(#sensors == 1 and sensors[1].ids[85739], "exact Whirlwind aura")
assert(sensors[1].button.appOptions.maxApplications == 4)
local count = frames
for i = 1, 20 do owner.Sync() end
assert(frames == count, "unchanged sync must reuse all frames")
-- Simulate Blizzard receiving a restricted count. Addon sync must not inspect it.
sensors[1].button.bar.value = setmetatable({ secret = true }, {
    __tostring = function() error("secret tostring") end,
    __lt = function() error("secret compare") end })
combat, restricted = true, true
db.bars.classPowerFontSize = 20
owner.Sync()
assert(cp.nativeAuraPending, "defer appearance while restricted")
assert(sensors[1].enabled and sensors[1].button.bar.value.secret)
combat, restricted = false, false
owner.Sync()
assert(not cp.nativeAuraPending, "apply appearance on restriction lift")
cp.powerType = "SWEEPING_STRIKES"
owner.Sync()
assert(not sensors[1].enabled and sensors[2].enabled, "park old spec")
assert(sensors[2].ids[260708] and sensors[2].button.appOptions.maxApplications == 18)
owner.Disable()
assert(not sensors[2].enabled)

-- Only Warrior routes into this module. A Mage-shaped power type must not
-- allocate anything, and the Controller must not even build the module.
local mageCP = { visible = true, powerType = 16, container = Widget(), visual = {} }
local mage = ns.CPBuilders.NativeAuras({ CP = mageCP, db = { bars = {} },
    Texture = function() return "texture" end, TextLevel = function() return 10 end })
count = frames
mage.Sync()
assert(frames == count and #sensors == 2, "a non-Warrior power type allocates no native slots")
assert(not mageCP.nativeAuraPending, "an inapplicable power type must not leave work pending")

local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Controller.lua", "rb"))
local source = file:read("*a")
file:close()
local first = assert(source:find("local function GetClassPowerType()", 1, true))
local last = assert(source:find("--- Stagger detection", first, true))
local route = assert(loadstring("return function(PLAYER_CLASS, GetSpec, _cpDB, CPK)\n"
    .. source:sub(first, last - 1) .. "\nreturn GetClassPowerType() end"))()
local modes = { MODE = { NATIVE_AURA = 11, NONE = 0, SEGMENTED = 1 } }
local warriorDB = { bars = {} }
local warriorSpec = 2
local function Spec() return warriorSpec end
local key, mode, aura = route("WARRIOR", Spec, warriorDB, modes)
assert(key == "WHIRLWIND" and mode == 11 and aura == false)
warriorSpec = 1
assert(route("WARRIOR", Spec, warriorDB, modes) == nil)
warriorDB.bars.showSweepingStrikes = true
key, mode, aura = route("WARRIOR", Spec, warriorDB, modes)
assert(key == "SWEEPING_STRIKES" and mode == 11 and aura == false)
warriorSpec = 3
assert(route("WARRIOR", Spec, warriorDB, modes) == nil)
-- Warrior is the only class with native class-resource aura trackers. Building
-- the module for anyone else allocates an AuraContainer that can never fill.
assert(source:find('if not CP.nativeAuras and PLAYER_CLASS == "WARRIOR" then', 1, true),
    "the native aura builder must stay Warrior-only")

print("native class aura lifecycle and spec routing smoke: ok")
