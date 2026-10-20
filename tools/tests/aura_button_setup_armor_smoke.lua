-- Native aura runtime (Midnight and WoW Forever): the AuraButton setup in
-- initializeFrame follows the EllesmereUI AuraKit order and armor
-- (Auras3/Runtime/MSUF_Auras3_Runtime_ButtonVisuals.lua PrepareAuraButton,
-- Kernel/MSUF_Boundary.lua RunNativeAuraRegistration).
--
-- Blizzard runs initializeFrame through securecallfunction while it builds a
-- frame batch, then calls UpdateAuraDisplay outside that boundary
-- (Blizzard_AuraContainerFrameProviders.lua). Every Set*/Add* registration also
-- runs UpdateAuraDisplay at once, which writes into each registered FontString.
-- A registration that raises halfway leaves a button the next display update
-- can trip over inside the container's update pass, and one aborted pass
-- freezes the container until /reload (target buffs missing while Blizzard and
-- EllesmereUI frames show them, 2026-10-20). The real factory must create and
-- style every region before the first registration, give each FontString a
-- font, survive a failing registration with a fallback or a cleared element,
-- report the failure once, and leave a button whose display update succeeds.
-- Arguments: repository root, then optionally a ButtonVisuals path (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local buttonVisualsPath = arg[2]
    or (root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_ButtonVisuals.lua")

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local reports = {}
function geterrorhandler() return function(message) reports[#reports + 1] = tostring(message) end end
_G.geterrorhandler = geterrorhandler

local fontStrings = {}
local Region = {}
Region.__index = Region
for _, name in ipairs({
    "SetAlpha", "ClearAllPoints", "SetPoint", "SetAllPoints", "SetSize", "EnableMouse", "SetDrawLayer",
    "SetTexture", "SetTexCoord", "SetJustifyH", "SetJustifyV", "SetMouseClickEnabled", "SetCancelAuraButtons",
    "SetMouseMotionEnabled", "SetTooltipAnchorPoint", "SetHideTooltipInCombat", "SetStatusBarTexture",
    "SetMinMaxValues", "SetValue", "SetStatusBarColor", "SetReverseFill", "SetDrawSwipe", "SetSwipeColor",
    "SetHideCountdownNumbers", "SetDrawBling", "SetDrawEdge", "SetReverse", "AddMaskTexture", "SetShown",
}) do Region[name] = function() end end
local function NewRegion(kind, parent)
    local region = setmetatable({ kind = kind, parent = parent, shown = true, level = (parent and parent.level or 0) + 1 }, Region)
    if kind == "FontString" then fontStrings[#fontStrings + 1] = region end
    return region
end
function Region:GetParent() return self.parent end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:GetFrameLevel() return self.level end
function Region:SetFrameLevel(level) self.level = level end
function Region:CreateTexture() return NewRegion("Texture", self) end
function Region:CreateFontString() return NewRegion("FontString", self) end
function Region:SetFont(path, size, flags)
    if path == "MISSING" then return false end
    self.font, self.fontSize, self.fontFlags = path, size, flags
    return true
end
function Region:GetFont() return self.font, self.fontSize, self.fontFlags end
function Region:SetText(text)
    if not self.font then error("FontString:SetText(): Font not set", 2) end
    self.text = text
end

local failNext = {}
local function NativeButton()
    local button = NewRegion("AuraButton")
    button.registered = {}
    button.calls = {}
    function button:UpdateAuraDisplay()
        for _, region in pairs(self.registered) do
            if type(region) == "table" and region.poison then error("display update failed on a registered texture", 2) end
            if type(region) == "table" and region.kind == "FontString" then region:SetText("") end
        end
    end
    local function Registration(name, slot)
        button[name] = function(self, region, options)
            self.calls[#self.calls + 1] = name
            if not self.firstRegistration then
                local unstyled = 0
                for i = 1, #fontStrings do
                    if not fontStrings[i].font then unstyled = unstyled + 1 end
                end
                self.firstRegistration = { fontStrings = #fontStrings, unstyled = unstyled }
            end
            local fail = failNext[name]
            if fail and fail(options, region) then
                failNext[name] = nil
                self.registered[slot] = region
                error(name .. " rejected its options", 2)
            end
            self.registered[slot] = region
            self:UpdateAuraDisplay()
        end
    end
    local function Clear(name, slot)
        button[name] = function(self)
            self.calls[#self.calls + 1] = name
            self.registered[slot] = nil
        end
    end
    Registration("SetIcon", "icon"); Clear("ClearIcon", "icon")
    Registration("SetDurationCooldown", "cooldown"); Clear("ClearDurationCooldown", "cooldown")
    Registration("SetDurationBar", "bar"); Clear("ClearDurationBar", "bar")
    Registration("SetDurationText", "duration"); Clear("ClearDurationText", "duration")
    Registration("SetApplicationCount", "count"); Clear("ClearApplicationCount", "count")
    Registration("SetDispelTypeText", "symbol"); Clear("ClearDispelTypeText", "symbol")
    local dispelTextures = 0
    function button:AddDispelTypeTexture(texture, options)
        self.calls[#self.calls + 1] = "AddDispelTypeTexture"
        local fail = failNext.AddDispelTypeTexture
        if fail and fail(options, texture) then
            failNext.AddDispelTypeTexture = nil
            texture.poison = true
        end
        dispelTextures = dispelTextures + 1
        self.registered["dispel" .. dispelTextures] = texture
        self:UpdateAuraDisplay()
    end
    function button:ClearDispelTypeTextures()
        for i = 1, dispelTextures do self.registered["dispel" .. i] = nil end
        dispelTextures = 0
    end
    return button
end

local MSUF = { Auras3RuntimeFactories = {}, ExportPublic = function() end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MidnightSimpleUnitFrames", MSUF)
Check(type(MSUF.RunNativeAuraRegistration) == "function", "MSUF_Boundary exports no RunNativeAuraRegistration")

local applyFontFails = false
local function Stubs(fields)
    return setmetatable(fields or {}, { __index = function() return function() end end })
end
local function ClampNumber(value, fallback, minValue, maxValue)
    value = tonumber(value) or fallback
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end
local dependencies = setmetatable({
    Platform = Stubs({
        Clamp01 = function(value, fallback) return ClampNumber(value, fallback or 1, 0, 1) end,
        ClampNumber = ClampNumber,
        CreateFrame = function(kind, _, parent) return NewRegion(kind or "Frame", parent) end,
        FrameLayers = {},
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
    }),
    DurationText = Stubs({
        ApplyFont = function(fs, size) if not applyFontFails then fs:SetFont("Fonts\\ARIALN.TTF", size, "OUTLINE") end end,
        BuildAuraDurationStyle = function() return { formatter = "formatter", binding = "binding", updateInterval = 0.1 } end,
    }),
    Schema = { DEFAULT_SHARED = { iconSize = 24, stackTextSize = 12, spacing = 2 } },
    Appearance = { DS = { defaultColors = {} }, Shape = Stubs({ RECTANGLE = "RECTANGLE" }) },
    ConfigValues = Stubs({ GetAuraBorderOptions = function() return { border = true } end }),
    NativeContract = Stubs(),
    CustomConfig = Stubs({ ResolveLaneParentFrame = function(parentFrame) return parentFrame end }),
}, { __index = function(t, group)
    local stub = Stubs()
    rawset(t, group, stub)
    return stub
end })
local A3 = Stubs({
    SpellIndicators = Stubs(),
    NativeAuraDispelBorderPadding = function() return 1 end,
    GetStealableTextureOptions = function() return { stealable = true } end,
    BindPandemicRegion = function() return false end,
})
assert(loadfile(buttonVisualsPath))("MidnightSimpleUnitFrames", MSUF)
local visuals = MSUF.Auras3RuntimeFactories.ButtonVisuals("MidnightSimpleUnitFrames", MSUF, A3, {}, function() end, dependencies)
local PrepareAuraButton = assert(visuals.PrepareAuraButton, "ButtonVisuals exports no PrepareAuraButton")

local function Lane()
    return {
        kind = "buff", unit = "target", size = 24, perRow = 8,
        showCooldownSwipe = true, showCooldownText = true, showStacks = true,
        showAuraBorder = true, showAuraSymbol = true, showStealableMarker = true, showTooltip = true,
        cooldownSize = 12, stackSize = 12,
    }
end
local function Prepare(lane)
    fontStrings = {}
    local container = NewRegion("AuraContainer")
    local button = NativeButton()
    button.parent = container
    local ok, err = pcall(PrepareAuraButton, button, lane or Lane(), 11)
    return button, ok, err
end
local function DisplayUpdates(button)
    return pcall(button.UpdateAuraDisplay, button)
end

-- 1. Order: every region exists and has a font before the first registration.
local button, ok, err = Prepare()
Check(ok, "a clean setup raised: " .. tostring(err))
Check(button.firstRegistration and button.firstRegistration.fontStrings == 3 and button.firstRegistration.unstyled == 0,
    "a registration ran before every FontString existed with a font (EllesmereUI order)")
Check(button.registered.icon and button.registered.cooldown and button.registered.duration and button.registered.count
    and button.registered.symbol and button.registered.dispel1 and button.registered.dispel2,
    "the clean setup did not register every enabled element")
Check(DisplayUpdates(button), "the clean button cannot run its display update")
Check(#reports == 0, "a clean setup reported an error")

-- 2. A font that cannot be applied falls back to the standard font before registering.
applyFontFails = true
button, ok, err = Prepare()
applyFontFails = false
Check(ok and DisplayUpdates(button), "a FontString without an applied font broke the setup: " .. tostring(err))
Check(button.registered.duration and button.registered.duration.font == "Fonts\\FRIZQT__.TTF",
    "the duration text was registered without the standard font fallback")

-- 3. SetDurationText rejecting the binding falls back to the plain options and reports once.
failNext.SetDurationText = function(options) return options and options.binding ~= nil end
button, ok, err = Prepare()
Check(ok, "a rejected SetDurationText escaped the setup: " .. tostring(err))
Check(button.registered.duration and DisplayUpdates(button), "the duration text fallback left the button inconsistent")
Check(reports[#reports] and reports[#reports]:find("SetDurationText", 1, true), "the rejected SetDurationText was not reported")
local reported = #reports
failNext.SetDurationText = function(options) return options and options.binding ~= nil end
Prepare()
Check(#reports == reported, "the same registration failure was reported twice")

-- 4. Blizzard inserts a dispel texture before its display update runs. A border
-- whose update fails must leave the button again; the marker stays.
failNext.AddDispelTypeTexture = function(options) return options and options.border == true end
button, ok, err = Prepare()
Check(ok and DisplayUpdates(button), "a failing border texture stayed registered: " .. tostring(err))
Check(button.registered.symbol == nil, "the dispel symbol stayed registered without its border")
Check(button.registered.dispel1 and not button.registered.dispel1.poison and button.registered.dispel2 == nil,
    "the stealable marker was not re-registered alone after the border failed")
failNext.AddDispelTypeTexture = function(options) return options and options.stealable == true end
button, ok, err = Prepare()
Check(ok and DisplayUpdates(button), "a failing marker texture stayed registered: " .. tostring(err))
Check(button.registered.dispel1 and button.registered.dispel1.poison == nil and button.registered.symbol,
    "the border was not re-registered with its symbol after the marker failed")

-- 5. Any registration that raises leaves a consistent button: the element is cleared.
for _, name in ipairs({ "SetIcon", "SetDurationCooldown", "SetApplicationCount", "SetDispelTypeText" }) do
    failNext[name] = function() return true end
    button, ok, err = Prepare()
    Check(ok, name .. " raising escaped the setup: " .. tostring(err))
    Check(DisplayUpdates(button), name .. " raising left a button whose display update fails")
end

print("aura button setup armor smoke: OK (" .. #reports .. " reported registration failures)")
