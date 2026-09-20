-- Threat percentage text smoke.
--
--   lua tools/tests/threat_text_smoke.lua <repo root>
--
-- The target, focus and boss frames show how much of the aggro threshold the
-- player holds: the scaled percentage of UnitDetailedThreatSituation("player",
-- unit), 100% = aggro. Offered on Classic Era, TBC and WoW Forever (owner
-- decision 2026-09-19); Mists and Midnight stay unchanged. One shared module
-- (Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua) and the client fact
-- SupportsThreatText decide everything. WoW Forever returns secret values for a
-- boss: they are formatted by C_StringUtil and never compared.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local core = root .. "/MidnightSimpleUnitFrames/"
local options = root .. "/MidnightSimpleUnitFrames_Options/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

-- One set of defaults for the runtime compile, the menu control and the preview row.
local DEFAULTS = { show = true, size = 11, anchor = "BOTTOMLEFT", x = 6, y = 2, layer = 7 }
local KEYS = {
    show = "showThreatIndicator", size = "threatIndicatorSize", anchor = "threatIndicatorAnchor",
    x = "threatIndicatorOffsetX", y = "threatIndicatorOffsetY", layer = "threatIndicatorLayer",
}
local REFRESH = "MSUF_RequestThreatIndicatorRefresh"
local MODULE = "Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua"

---------------------------------------------------------------------------
-- 1. Client fact: Classic Era, TBC and WoW Forever; not Mists or Midnight
---------------------------------------------------------------------------
local function LoadMainlineClient(isForever)
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_ID = 1, 1
    _G.C_AddOns = { GetAddOnMetadata = function() return nil end }
    _G.GetBuildInfo = function() return "test", "test", "test", isForever and 16001 or 120105 end
    _G.GameEvent = isForever and { RegisterCamelotEvents = function() end } or nil
    _G.MSUF, _G.MSUF_NS = nil, nil
    local namespace = {}
    assert(loadfile(core .. "Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", namespace)
    _G.MSUF, _G.MSUF_NS = nil, nil
    return namespace.Client, namespace
end

local CLASSIC_PROJECT_IDS = { Vanilla = 2, TBC = 5, Mists = 19 }
local function LoadClassicClient(flavor)
    local oldCreateFrame = _G.CreateFrame
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
    _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
    _G.WOW_PROJECT_ID = CLASSIC_PROJECT_IDS[flavor]
    _G.C_AddOns = { GetAddOnMetadata = function(_, field) return field == "X-MSUF-Client" and flavor or nil end }
    _G.GetBuildInfo = function() return "test", "test", "test", 11509 end
    -- No frame factory: a client placed by its tag alone builds a login diagnostic.
    _G.GetAddOnMetadata, _G.CreateFrame, _G.GameEvent, _G.MSUF, _G.MSUF_NS = nil, nil, nil, nil, nil
    local namespace = {}
    local ok, err = pcall(assert(loadfile(core .. "Game/Shared/Initialize.lua")), "MidnightSimpleUnitFrames", namespace)
    _G.CreateFrame, _G.MSUF, _G.MSUF_NS = oldCreateFrame, nil, nil
    if not ok then error(err, 0) end
    return namespace.Client, namespace
end

Check(LoadMainlineClient(true).SupportsThreatText == true, "WoW Forever must offer the threat text")
Check(LoadMainlineClient(false).SupportsThreatText == false, "Midnight must not offer the threat text")
Check(LoadClassicClient("Vanilla").SupportsThreatText == true, "Classic Era must offer the threat text")
Check(LoadClassicClient("TBC").SupportsThreatText == true, "TBC must offer the threat text")
Check(LoadClassicClient("Mists").SupportsThreatText == false, "Mists must not offer the threat text")

---------------------------------------------------------------------------
-- 2. Runtime element
---------------------------------------------------------------------------
local function FontString(parent)
    local fs = { parent = parent, shown = false, textWrites = 0, visibilityWrites = 0 }
    function fs:SetText(value) self.text = value; self.textWrites = self.textWrites + 1 end
    function fs:Show() self.shown = true; self.visibilityWrites = self.visibilityWrites + 1 end
    function fs:Hide() self.shown = false; self.visibilityWrites = self.visibilityWrites + 1 end
    function fs:SetJustifyH(value) self.justify = value end
    function fs:SetDrawLayer(layer, sublevel) self.drawLayer, self.sublevel = layer, sublevel end
    function fs:SetAlpha(value) self.alpha = value end
    function fs:SetTextColor(r, g, b, a)
        self.color = { r, g, b, a }
        self.colorWrites = (self.colorWrites or 0) + 1
    end
    function fs:SetShadowOffset(x, y) self.shadow = { x, y } end
    function fs:SetShadowColor() end
    function fs:SetFont(font, size, flags) self.font = { font, size, flags }; return true end
    function fs:GetFont() if self.font then return self.font[1], self.font[2], self.font[3] end end
    function fs:ClearAllPoints() self.point = nil end
    function fs:SetPoint(...) self.point = { ... } end
    return fs
end

local function Texture(parent, layer)
    local tex = { parent = parent, layer = layer, shown = true, points = {} }
    function tex:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function tex:ClearAllPoints() self.points = {} end
    function tex:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    function tex:SetAlpha(value) self.alpha = value end
    return tex
end

local createdFrames = {}
local function InstallFrameFactory()
    createdFrames = {}
    _G.CreateFrame = function(_, _, parent)
        local frame = { parent = parent, events = {}, unitEvents = {}, scripts = {} }
        function frame:SetAllPoints() end
        function frame:EnableMouse(value) self.mouse = value end
        function frame:SetClipsChildren() end
        function frame:SetFrameLevel(value) self.level = value end
        function frame:CreateFontString() return FontString(self) end
        function frame:CreateTexture(_, layer) return Texture(self, layer) end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
        function frame:UnregisterAllEvents() self.events, self.unitEvents = {}, {} end
        function frame:SetScript(name, handler) self.scripts[name] = handler end
        createdFrames[#createdFrames + 1] = frame
        return frame
    end
end

local fontRequests = {}
local function LoadElement(client, extra)
    local registered = {}
    InstallFrameFactory()
    _G[REFRESH] = nil
    local namespace = {
        Client = client,
        UF = {
            Layers = { StatusLevel = function(_, layer) return 40 + layer end },
            Shared = {
                ClampFontSize = function(size, default) return tonumber(size) or default end,
                ApplyFontChecked = function(fs, font, size, flags)
                    fontRequests[#fontRequests + 1] = { fs = fs, font = font, size = size, flags = flags }
                    fs:SetFont(font, size, flags)
                    return true
                end,
            },
            IsBossUnit = function(unit)
                return unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5"
            end,
            RegisterElement = function(name, element, traits)
                registered.name, registered.element, registered.traits = name, element, traits
            end,
            RefreshElements = function(unit, names, reason)
                registered.refresh = { unit = unit, names = names, reason = reason }
                return true
            end,
        },
    }
    for key, value in pairs(extra or {}) do namespace[key] = value end
    assert(loadfile(core .. MODULE))("MidnightSimpleUnitFrames", namespace)
    return registered.element, registered, namespace
end

local function Frame(unit, status)
    return {
        MSUFUnitKey = unit,
        MSUFSpec = {
            font = "Fonts\\FRIZQT__.TTF", fontFlags = "OUTLINE", fontShadow = false,
            textColor = { r = 1, g = 1, b = 1, a = 1 },
            status = status or { alpha = 0.9, testMode = false,
                threat = { enabled = true, size = DEFAULTS.size, anchor = DEFAULTS.anchor, x = DEFAULTS.x,
                    y = DEFAULTS.y, layer = DEFAULTS.layer } },
        },
        Health = { GetFrameLevel = function() return 10 end },
    }
end

-- A secret number: any comparison, arithmetic or concatenation raises, so the
-- module can only pass it to the C formatters.
local SECRET_MT = {}
for _, event in ipairs({ "__eq", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__concat", "__len" }) do
    SECRET_MT[event] = function() error("a secret threat value was used in Lua (" .. event .. ")", 2) end
end
local function Secret() return setmetatable({ secret = true }, SECRET_MT) end
_G.issecretvalue = function(value) return type(value) == "table" and rawget(value, "secret") == true end

local threatCalls, threatValue = {}, nil
_G.UnitDetailedThreatSituation = function(unit, mob)
    threatCalls[#threatCalls + 1] = { unit, mob }
    if threatValue == nil then return end
    return false, 1, threatValue, threatValue, 12345
end
local truncateCalls, wrapCalls = 0, 0
local function InstallStringUtil()
    _G.C_StringUtil = {
        TruncateWhenZero = function(value)
            truncateCalls = truncateCalls + 1
            return { secretText = true, from = value }
        end,
        WrapString = function(infix, prefix, suffix)
            wrapCalls = wrapCalls + 1
            return { secretText = true, infix = infix, prefix = prefix, suffix = suffix }
        end,
    }
end
InstallStringUtil()

do
    -- Midnight shares the Mainline manifest with Forever: the file stays inert.
    local element = LoadElement(LoadMainlineClient(false))
    Check(element == nil, "Midnight: the threat element was registered")
    Check(_G[REFRESH] == nil, "Midnight: the threat refresh bridge was published")
    element = LoadElement({ SupportsThreatText = false, IsMists = true, IsClassic = true })
    Check(element == nil, "Mists: the threat element was registered")
end

do
    local element, registered = LoadElement(LoadMainlineClient(true))
    Check(registered.name == "ThreatIndicator" and type(element) == "table", "Forever: the threat element was not registered")
    Check(element.UpdateOnApply == true, "the threat text must seed on apply")
    local traits = registered.traits or {}
    Check(traits.apply == true and traits.events == true and traits.defaultApply == true and traits.identity == true,
        "the threat element lost its apply, event or identity traits")
    Check(type(_G[REFRESH]) == "function", "the menu refresh bridge is missing")
    Check(_G[REFRESH]("boss") == true and registered.refresh.unit == "boss"
        and registered.refresh.names[1] == "ThreatIndicator", "the refresh bridge no longer targets the threat element")

    -- Only the frames that have a hostile mob to hold threat on.
    for _, unit in ipairs({ "target", "focus", "boss1", "boss5" }) do
        local frame = Frame(unit)
        Check(element.IsEnabled(frame, frame.MSUFSpec) == true, "the threat text must be enabled on " .. unit)
    end
    for _, unit in ipairs({ "player", "pet", "targettarget", "focustarget", "party1", "arena1" }) do
        local frame = Frame(unit)
        Check(element.IsEnabled(frame, frame.MSUFSpec) ~= true, "the threat text must stay off on " .. unit)
    end
    local off = Frame("target")
    off.MSUFSpec.status.threat.enabled = false
    Check(element.IsEnabled(off, off.MSUFSpec) ~= true, "a disabled threat entry must not enable the element")

    -- Layout: bottom-left corner, left-justified, shared status alpha, own layer.
    local frame = Frame("target")
    element.Apply(frame, frame.MSUFSpec)
    local fs = Check(frame.threatIndicatorText, "Apply did not create the threat text")
    Check(fs.parent == frame.threatIndicatorHolder and frame.threatIndicatorHolder.parent == frame,
        "the threat text must live on its own holder under the unit frame")
    Check(frame.threatIndicatorHolder.level == 40 + DEFAULTS.layer, "the holder must take the status layer frame level")
    Check(fs.point and fs.point[1] == "BOTTOMLEFT" and fs.point[2] == frame and fs.point[3] == "BOTTOMLEFT"
        and fs.point[4] == DEFAULTS.x and fs.point[5] == DEFAULTS.y, "the threat text left its bottom-left corner")
    Check(fs.justify == "LEFT" and fs.alpha == 0.9 and fs.drawLayer == "OVERLAY" and fs.sublevel == DEFAULTS.layer - 1,
        "the threat text lost its justify, alpha or draw layer")
    local request = fontRequests[#fontRequests]
    Check(request and request.fs == fs and request.size == DEFAULTS.size and request.font == "Fonts\\FRIZQT__.TTF"
        and request.flags == "OUTLINE", "the threat text must use the frame font at its own size")
    Check(fs.color[1] == 1 and fs.color[2] == 1 and fs.color[3] == 1, "without its own color the text follows the font color")
    local fontCount = #fontRequests
    element.Apply(frame, frame.MSUFSpec)
    Check(#fontRequests == fontCount, "an unchanged layout must not set the font again")
    frame.MSUFSpec.status.threat.colorR, frame.MSUFSpec.status.threat.colorG, frame.MSUFSpec.status.threat.colorB = 1, 0.5, 0
    frame.MSUFSpec.status.threat.anchor = "TOPRIGHT"
    element.Apply(frame, frame.MSUFSpec)
    Check(fs.color[1] == 1 and fs.color[2] == 0.5 and fs.color[3] == 0, "the indicator color was not applied")
    Check(fs.point[1] == "TOPRIGHT" and fs.justify == "RIGHT", "a right anchor must right-justify the text")
    frame.MSUFSpec.status.threat.anchor = "NAMERIGHT"
    element.Apply(frame, frame.MSUFSpec)
    Check(fs.point[1] == "BOTTOMLEFT" and fs.justify == "LEFT", "an unknown anchor must fall back to the bottom-left corner")

    -- Plain values: scaled percentage, rounded down, hidden without threat.
    frame = Frame("target")
    element.Apply(frame, frame.MSUFSpec)
    fs = frame.threatIndicatorText
    threatCalls, threatValue = {}, 87.6
    element.Update(frame)
    Check(threatCalls[1] and threatCalls[1][1] == "player" and threatCalls[1][2] == "target",
        "the threat must be read for the player against the frame's unit")
    Check(fs.shown == true and fs.text == "87%", "87.6% threat must read 87% (got " .. tostring(fs.text) .. ")")
    local textWrites, visibilityWrites = fs.textWrites, fs.visibilityWrites
    for _ = 1, 20 do element.Update(frame) end
    threatValue = 87.9
    element.Update(frame)
    Check(fs.textWrites == textWrites and fs.visibilityWrites == visibilityWrites,
        "an unchanged percentage must not write to the text again")
    threatValue = 100
    element.Update(frame)
    Check(fs.text == "100%" and fs.textWrites == textWrites + 1, "a new percentage must cost exactly one text write")
    threatValue = 0.4
    element.Update(frame)
    Check(fs.shown == false, "less than 1% threat must hide the text")
    threatValue = nil
    element.Update(frame)
    Check(fs.shown == false, "no threat entry must hide the text")
    visibilityWrites = fs.visibilityWrites
    for _ = 1, 20 do element.Update(frame) end
    Check(fs.visibilityWrites == visibilityWrites, "a hidden text must not be hidden again")

    -- WoW Forever boss: a secret value goes to the C formatters on every event.
    frame = Frame("boss1")
    element.Apply(frame, frame.MSUFSpec)
    fs = frame.threatIndicatorText
    truncateCalls, wrapCalls = 0, 0
    threatValue = Secret()
    element.Update(frame)
    Check(fs.shown == true and type(fs.text) == "table" and fs.text.suffix == "%" and fs.text.prefix == nil
        and type(fs.text.infix) == "table" and fs.text.infix.from == threatValue,
        "a secret value must be shown as WrapString(TruncateWhenZero(value), nil, \"%\")")
    element.Update(frame)
    Check(truncateCalls == 2 and wrapCalls == 2, "a secret value cannot be cached and must be formatted per event")
    threatValue = 42
    element.Update(frame)
    Check(fs.text == "42%", "a plain value after a secret one must write again")
    _G.C_StringUtil = nil
    local plain = LoadElement(LoadMainlineClient(true))
    frame = Frame("boss2")
    plain.Apply(frame, frame.MSUFSpec)
    threatValue = Secret()
    plain.Update(frame)
    Check(frame.threatIndicatorText.shown == false, "without the C formatters a secret value must hide the text")
    InstallStringUtil()

    -- Test mode shows a sample and listens to nothing.
    frame = Frame("focus")
    element.Apply(frame, frame.MSUFSpec)
    frame.MSUFSpec.status.testMode = true
    threatCalls = {}
    element.Update(frame)
    Check(frame.threatIndicatorText.text == "85%" and frame.threatIndicatorText.shown == true and #threatCalls == 0,
        "test mode must show the 85% sample without reading threat")
    Check(#element.GetEvents(frame, frame.MSUFSpec) == 0 and #element.GetUnitlessEvents(frame, frame.MSUFSpec) == 0,
        "test mode must not listen to threat events")
    frame.MSUFSpec.status.testMode = false
    local events = element.GetEvents(frame, frame.MSUFSpec)
    Check(#events == 1 and events[1] == "UNIT_THREAT_LIST_UPDATE", "the unit route must be UNIT_THREAT_LIST_UPDATE only")
    local lifecycle = element.GetUnitlessEvents(frame, frame.MSUFSpec)
    Check(#lifecycle == 1 and lifecycle[1] == "PLAYER_REGEN_ENABLED", "the unitless route must be PLAYER_REGEN_ENABLED only")

    element.Disable(frame)
    Check(frame.threatIndicatorText.shown == false, "Disable must hide the text")

    -- Classic Era and TBC run the same element on plain numbers.
    local classic = LoadElement({ SupportsThreatText = true, IsClassic = true, IsVanilla = true })
    frame = Frame("target")
    classic.Apply(frame, frame.MSUFSpec)
    threatValue = 55.5
    classic.Update(frame)
    Check(frame.threatIndicatorText.text == "55%" and frame.threatIndicatorText.shown == true,
        "Classic: the threat text did not show the scaled percentage")
end

---------------------------------------------------------------------------
-- 2b. Color curve: low -> medium -> high, a table read per event
---------------------------------------------------------------------------
-- High is light pink, not red: red digits vanish on red enemy bars (owner, 2026-09-19).
local LOW, MID, HIGH = { 0.30, 0.85, 0.30 }, { 1.00, 0.82, 0.10 }, { 1.00, 0.60, 0.60 }
local function Near(a, b) return math.abs(a - b) < 1e-9 end
local function ColorIs(fs, r, g, b, a)
    local c = fs.color
    return c and Near(c[1], r) and Near(c[2], g) and Near(c[3], b) and (a == nil or Near(c[4], a))
end
local threatState = 0
_G.UnitThreatSituation = function() return threatState end

do
    _G.MSUF_DB = { general = {} }
    local element = LoadElement(LoadMainlineClient(true))
    local frame = Frame("target")
    local cfg = frame.MSUFSpec.status.threat
    cfg.colorCurve = true
    frame.MSUFSpec.textColor.a = 0.8
    element.Apply(frame, frame.MSUFSpec)
    local fs = frame.threatIndicatorText

    local function At(value) threatValue = value; element.Update(frame) end
    At(50)
    Check(ColorIs(fs, MID[1], MID[2], MID[3], 0.8), "50% threat must be the medium color with the shared text alpha")
    At(100)
    Check(ColorIs(fs, HIGH[1], HIGH[2], HIGH[3]), "100% threat must be the high color")
    At(25)
    Check(ColorIs(fs, 0.65, 0.835, 0.20), "25% must blend halfway from low to medium")
    At(75.9)
    Check(ColorIs(fs, (MID[1] + HIGH[1]) / 2, (MID[2] + HIGH[2]) / 2, (MID[3] + HIGH[3]) / 2),
        "75% must blend halfway from medium to high")
    local writes = fs.colorWrites
    for _ = 1, 20 do element.Update(frame) end
    At(75.2)
    Check(fs.colorWrites == writes, "an unchanged percentage must not recolor the text")
    At(1)
    Check(ColorIs(fs, LOW[1] + 0.7 * 0.02, LOW[2] - 0.03 * 0.02, LOW[3] - 0.2 * 0.02), "1% must sit next to the low color")

    -- A palette edit re-applies the element; the next paint uses the new curve.
    _G.MSUF_DB.general.threatColorHighR, _G.MSUF_DB.general.threatColorHighG = 0, 0
    element.Apply(frame, frame.MSUFSpec)
    Check(ColorIs(fs, LOW[1] + 0.7 * 0.02, LOW[2] - 0.03 * 0.02, LOW[3] - 0.2 * 0.02),
        "an incomplete stored color triple must keep the default stop")
    _G.MSUF_DB.general.threatColorHighB = 1
    element.Apply(frame, frame.MSUFSpec)
    At(100)
    Check(ColorIs(fs, 0, 0, 1), "a complete stored high color must replace the default")
    _G.MSUF_DB.general = {}

    -- Static, curve, static again on one text: every switch repaints, so a static
    -- color cached before the curve took over cannot swallow the way back.
    local swap = Frame("focus")
    swap.MSUFSpec.textColor.a = 0.8
    local swapCfg = swap.MSUFSpec.status.threat
    swapCfg.colorCurve = false
    element.Apply(swap, swap.MSUFSpec)
    threatValue = 100
    element.Update(swap)
    Check(ColorIs(swap.threatIndicatorText, 1, 1, 1, 0.8), "with the curve off the text must use the font color")
    swapCfg.colorCurve = true
    element.Apply(swap, swap.MSUFSpec)
    element.Update(swap)
    Check(ColorIs(swap.threatIndicatorText, HIGH[1], HIGH[2], HIGH[3]), "switching the curve on must repaint the curve color")
    swapCfg.colorCurve = false
    element.Apply(swap, swap.MSUFSpec)
    element.Update(swap)
    Check(ColorIs(swap.threatIndicatorText, 1, 1, 1, 0.8), "switching the curve off again must restore the font color")
    swapCfg.colorCurve = true
    element.Apply(swap, swap.MSUFSpec)
    element.Update(swap)
    Check(ColorIs(swap.threatIndicatorText, HIGH[1], HIGH[2], HIGH[3]), "switching the curve back on must repaint again")

    -- WoW Forever boss: the value is secret, so the color follows the threat state.
    local boss = Frame("boss1")
    boss.MSUFSpec.status.threat.colorCurve = true
    element.Apply(boss, boss.MSUFSpec)
    threatValue = Secret()
    for state, color in pairs({ [0] = LOW, [1] = MID, [2] = HIGH, [3] = HIGH }) do
        threatState = state
        element.Update(boss)
        Check(ColorIs(boss.threatIndicatorText, color[1], color[2], color[3]),
            "a secret boss value with threat state " .. state .. " painted the wrong color")
    end
    threatState = Secret()
    element.Update(boss)
    Check(ColorIs(boss.threatIndicatorText, LOW[1], LOW[2], LOW[3]), "a secret threat state must fall back to the low color")
    threatState = 0

    -- Test mode paints the sample's curve color.
    frame.MSUFSpec.status.testMode = true
    element.Update(frame)
    Check(fs.text == "85%" and ColorIs(fs, 1.00, MID[2] + (HIGH[2] - MID[2]) * 0.7, MID[3] + (HIGH[3] - MID[3]) * 0.7),
        "test mode must show the 85% sample in its curve color")
    frame.MSUFSpec.status.testMode = false

    -- The menu reads keys, defaults and sample colors from the module.
    local namespace = {
        Client = LoadMainlineClient(true),
        UF = {
            Layers = {}, Shared = {}, IsBossUnit = function() return false end,
            RegisterElement = function() end, RefreshElements = function() return true end,
        },
    }
    assert(loadfile(core .. MODULE))("MidnightSimpleUnitFrames", namespace)
    local exported = Check(namespace.UFThreatText, "the module no longer exports its curve for the menu")
    local stops = exported.CURVE_STOPS
    Check(#stops == 3 and stops[1][1] == "threatColorLow" and stops[2][1] == "threatColorMid"
        and stops[3][1] == "threatColorHigh", "the curve stop keys changed")
    for i, color in ipairs({ LOW, MID, HIGH }) do
        Check(Near(stops[i][2], color[1]) and Near(stops[i][3], color[2]) and Near(stops[i][4], color[3]),
            "curve stop " .. i .. " has a different default color")
    end
    local r, g, b = exported.CurveColorAt({}, 50)
    Check(Near(r, MID[1]) and Near(g, MID[2]) and Near(b, MID[3]), "CurveColorAt(50) must return the medium color")
    r, g, b = exported.CurveColorAt({}, 250)
    Check(Near(r, HIGH[1]) and Near(g, HIGH[2]) and Near(b, HIGH[3]), "CurveColorAt must clamp above 100%")
    _G.MSUF_DB = nil
end

---------------------------------------------------------------------------
-- 2c. Group frames: each member's threat on the target, one throttled driver
---------------------------------------------------------------------------
do
    local now, timers = 100, {}
    _G.GetTime = function() return now end
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
    local function RunDueTimers()
        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            if timer.at <= now + 1e-9 then timer.fn() else timers[#timers + 1] = timer end
        end
    end
    local memberThreat, reads, stateReads = {}, {}, {}
    _G.UnitDetailedThreatSituation = function(unit, mob)
        reads[#reads + 1] = tostring(unit) .. ">" .. tostring(mob)
        local value = memberThreat[unit]
        if value == nil then return end
        return false, 1, value, value, 1
    end
    _G.UnitThreatSituation = function(unit, mob)
        stateReads[#stateReads + 1] = tostring(unit) .. ">" .. tostring(mob)
        return 1
    end
    local gf = {}
    local element = LoadElement(LoadMainlineClient(true), { GF = gf })
    local loader
    for _, frame in ipairs(createdFrames) do
        if frame.events.ADDON_LOADED then loader = frame end
    end

    local function GroupFrame(unit, kind)
        local frame = Frame(unit, { alpha = 1, group = true, kind = kind or "party",
            threat = { enabled = true, size = 9, anchor = "TOP", x = 0, y = -1, layer = 7, colorCurve = false } })
        frame.visible = true
        function frame:IsVisible() return self.visible end
        return frame
    end
    local function ReadSet()
        local set = {}
        for _, read in ipairs(reads) do set[read] = true end
        return set
    end
    local party1, party2, raider = GroupFrame("party1"), GroupFrame("party2"), GroupFrame("raid12", "raid")
    for _, frame in ipairs({ party1, party2, raider }) do
        Check(element.IsEnabled(frame, frame.MSUFSpec) == true, "a group frame with the threat text must enable the element")
        Check(#element.GetEvents(frame, frame.MSUFSpec) == 0 and #element.GetUnitlessEvents(frame, frame.MSUFSpec) == 0,
            "a group frame must not register threat events of its own; the shared driver owns them")
    end
    local disabled = GroupFrame("party3")
    disabled.MSUFSpec.status.threat.enabled = false
    Check(element.IsEnabled(disabled, disabled.MSUFSpec) ~= true, "a disabled group entry must not enable the element")

    local before = #createdFrames
    element.Apply(party1, party1.MSUFSpec)
    local driver
    for i = before + 1, #createdFrames do
        if createdFrames[i].unitEvents.UNIT_THREAT_LIST_UPDATE then driver = createdFrames[i] end
    end
    Check(driver and driver.unitEvents.UNIT_THREAT_LIST_UPDATE == "target" and driver.events.PLAYER_TARGET_CHANGED
        and driver.events.PLAYER_REGEN_ENABLED, "the first group frame must start the driver on the target's threat list")
    element.Apply(party2, party2.MSUFSpec)
    element.Apply(raider, raider.MSUFSpec)
    Check(party1.threatIndicatorText.point[1] == "TOP" and party1.threatIndicatorText.justify == "CENTER",
        "a group threat text must sit at its configured top centre")

    -- A burst of threat events: the first repaints at once, the rest collapse into
    -- one trailing pass half a second later.
    memberThreat.party1, memberThreat.party2, memberThreat.raid12 = 40.5, 99.9, 12
    reads = {}
    driver.scripts.OnEvent(driver, "UNIT_THREAT_LIST_UPDATE", "target")
    Check(party1.threatIndicatorText.text == "40%" and party2.threatIndicatorText.text == "99%"
        and raider.threatIndicatorText.text == "12%", "the first threat event must repaint every group text at once")
    local seen = ReadSet()
    Check(#reads == 3 and seen["party1>target"] and seen["party2>target"] and seen["raid12>target"],
        "each member's threat must be read once per pass, on the player's target")
    now = 100.1
    driver.scripts.OnEvent(driver, "UNIT_THREAT_LIST_UPDATE", "target")
    now = 100.2
    driver.scripts.OnEvent(driver, "PLAYER_TARGET_CHANGED")
    Check(#reads == 3 and #timers == 1, "events inside the half second must schedule one trailing pass, not repaint")
    memberThreat.party1 = 55
    now = 100.5
    RunDueTimers()
    Check(#reads == 6 and party1.threatIndicatorText.text == "55%", "the trailing pass must repaint every group text")

    -- A hidden frame is skipped; its member is not read.
    party2.visible = false
    now = 101.2
    reads = {}
    driver.scripts.OnEvent(driver, "UNIT_THREAT_LIST_UPDATE", "target")
    Check(#reads == 2 and not ReadSet()["party2>target"], "a hidden group frame must not be read")
    party2.visible = true

    -- Turning the option off detaches each frame; the last one stops the driver.
    for _, frame in ipairs({ party1, party2, raider }) do
        frame.MSUFSpec.status.threat.enabled = false
        element.Apply(frame, frame.MSUFSpec)
    end
    Check(next(driver.events) == nil and next(driver.unitEvents) == nil,
        "turning the group threat text off must stop the driver once no frame shows it")
    for _, frame in ipairs({ party1, party2, raider }) do
        frame.MSUFSpec.status.threat.enabled = true
        element.Apply(frame, frame.MSUFSpec)
    end
    Check(driver.unitEvents.UNIT_THREAT_LIST_UPDATE == "target", "turning the group threat text on must restart the driver")

    -- A group test frame (Edit Mode, the group preview; the engine marks it) shows
    -- the sample without reading threat and never joins the driver. Live frames of
    -- the same kind keep their real value meanwhile.
    local testFrame = GroupFrame("player")
    testFrame._msufGFIsPreviewFrame = true
    reads = {}
    element.Apply(testFrame, testFrame.MSUFSpec)
    element.Update(testFrame)
    Check(testFrame.threatIndicatorText.text == "85%" and #reads == 0,
        "a group test frame must show the sample without reading threat")
    element.Update(party1)
    Check(party1.threatIndicatorText.text == "55%" and reads[1] == "party1>target",
        "a live party frame must keep its real threat while party test frames show the sample")

    -- A secret boss value is formatted and colored by the member's threat state on
    -- the target.
    _G.MSUF_DB = { general = {} }
    party1.MSUFSpec.status.threat.colorCurve = true
    element.Apply(party1, party1.MSUFSpec)
    memberThreat.party1 = Secret()
    stateReads = {}
    element.Update(party1)
    Check(type(party1.threatIndicatorText.text) == "table" and stateReads[1] == "party1>target"
        and ColorIs(party1.threatIndicatorText, MID[1], MID[2], MID[3]),
        "a secret member value must be formatted and colored by the member's state on the target")
    _G.MSUF_DB = nil

    -- The driver listens only while a group frame shows the text.
    for _, frame in ipairs({ party1, party2, raider }) do element.Disable(frame) end
    Check(next(driver.events) == nil and next(driver.unitEvents) == nil,
        "the driver must stop listening once no group frame shows the text")
    element.Apply(testFrame, testFrame.MSUFSpec)
    Check(next(driver.events) == nil and next(driver.unitEvents) == nil, "a group test frame must not start the driver")
    Check(party1.threatIndicatorText.shown == false, "Disable must hide a group threat text")
    element.Apply(party1, party1.MSUFSpec)
    Check(driver.unitEvents.UNIT_THREAT_LIST_UPDATE == "target", "a new group frame must restart the driver")
    element.Disable(party1)

    -- MSUF_UF_Group_Metadata.lua builds its masks after this module loaded, so the
    -- element joins them on the addon's own ADDON_LOADED, once.
    Check(loader and loader.events.ADDON_LOADED, "the module must wait for ADDON_LOADED to join the group refresh masks")
    gf.Metadata = { MASK_FONT = {}, MASK_COLOR = {}, MASK_VISUAL = {}, MASK_RUNTIME = {}, MASK_AURAS = {} }
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "SomeOtherAddon")
    Check(gf.Metadata.MASK_FONT.ThreatIndicator == nil and loader.events.ADDON_LOADED,
        "another addon's load must not trigger the mask join")
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "MidnightSimpleUnitFrames")
    for _, mask in ipairs({ "MASK_FONT", "MASK_COLOR", "MASK_VISUAL", "MASK_RUNTIME" }) do
        Check(gf.Metadata[mask].ThreatIndicator == true, "the threat element did not join " .. mask)
    end
    Check(gf.Metadata.MASK_AURAS.ThreatIndicator == nil, "the threat element joined an unrelated mask")
    Check(loader.events.ADDON_LOADED == nil, "the mask join must stop listening after it ran")
    _G.GetTime, _G.C_Timer = nil, nil
end

---------------------------------------------------------------------------
-- 2d. Background plate: dark, as wide as "100%", the number centred on it
---------------------------------------------------------------------------
do
    -- Section 2c left its member stub installed; read the shared value again.
    _G.UnitDetailedThreatSituation = function()
        if threatValue == nil then return end
        return false, 1, threatValue, threatValue, 12345
    end
    local element = LoadElement(LoadMainlineClient(true))
    local frame = Frame("target")
    local cfg = frame.MSUFSpec.status.threat
    cfg.background = true
    element.Apply(frame, frame.MSUFSpec)
    local fs, plate = frame.threatIndicatorText, frame.threatIndicatorPlate
    Check(plate, "Background on must build the plate")
    local sample = plate._msufThreatSample
    Check(sample and sample.text == "100%" and sample.alpha == 0, "the plate must be sized by an invisible 100% sample")
    Check(sample.point and sample.point[1] == DEFAULTS.anchor and sample.point[2] == frame
        and sample.point[3] == DEFAULTS.anchor and sample.point[4] == DEFAULTS.x and sample.point[5] == DEFAULTS.y,
        "the sample must take the number's configured spot")
    Check(fs.point and fs.point[1] == "CENTER" and fs.point[2] == sample and fs.point[3] == "CENTER"
        and fs.justify == "CENTER", "the number must be centred on the plate")
    local p1, p2 = plate.points[1], plate.points[2]
    Check(#plate.points == 2 and p1[1] == "TOPLEFT" and p1[2] == sample and p1[3] == "TOPLEFT" and p1[4] == -2 and p1[5] == 1
        and p2[1] == "BOTTOMRIGHT" and p2[2] == sample and p2[3] == "BOTTOMRIGHT" and p2[4] == 2 and p2[5] == -1,
        "the plate must wrap the sample with 2 px at the sides and 1 px above and below")
    Check(plate.layer == "ARTWORK" and fs.drawLayer == "OVERLAY" and plate.parent == sample.parent
        and fs.parent == sample.parent, "the plate must draw below the number in the same holder")
    local c = plate.colorTexture
    Check(c and c[1] == 0 and c[2] == 0 and c[3] == 0 and Near(c[4], 0.75), "the plate must be black at 75%")
    Check(plate.alpha == 0.9, "the plate must follow the status text alpha")
    Check(sample.font and sample.font[1] == "Fonts\\FRIZQT__.TTF" and sample.font[2] == DEFAULTS.size
        and sample.font[3] == "OUTLINE", "the sample must use the number's font")
    Check(plate.shown == false, "no value yet: the plate must stay hidden")

    threatValue = 42
    element.Update(frame)
    Check(fs.shown and plate.shown, "a shown number must show its plate")
    threatValue = nil
    element.Update(frame)
    Check(not fs.shown and not plate.shown, "a hidden number must hide its plate")
    threatValue = Secret()
    element.Update(frame)
    Check(fs.shown and plate.shown, "a secret number must show its plate; nothing is measured")
    threatValue = 42
    element.Update(frame)

    -- Off: the number goes back to its corner and the plate stays out of the way.
    cfg.background = false
    element.Apply(frame, frame.MSUFSpec)
    Check(fs.shown and not plate.shown, "Background off must hide the plate and keep the number")
    Check(fs.point[1] == DEFAULTS.anchor and fs.point[2] == frame and fs.point[4] == DEFAULTS.x
        and fs.point[5] == DEFAULTS.y and fs.justify == "LEFT", "Background off must put the number back on its corner")
    threatValue = nil
    element.Update(frame)
    threatValue = 42
    element.Update(frame)
    Check(fs.shown and not plate.shown, "a plate that is off must stay hidden while the number comes and goes")

    -- On again while the number shows; font and offset changes carry the plate along.
    cfg.background = true
    element.Apply(frame, frame.MSUFSpec)
    Check(plate.shown and fs.point[2] == sample, "Background on again must show the plate under the shown number")
    frame.MSUFSpec.font = "Fonts\\ARIALN.TTF"
    element.Apply(frame, frame.MSUFSpec)
    Check(sample.font[1] == "Fonts\\ARIALN.TTF", "the sample must follow a font change")
    cfg.x, cfg.y = 10, 5
    element.Apply(frame, frame.MSUFSpec)
    Check(sample.point[4] == 10 and sample.point[5] == 5 and fs.point[2] == sample,
        "a new offset must move the plate with the number on it")
    element.Disable(frame)
    Check(not fs.shown and not plate.shown, "Disable must hide the plate with the number")
    threatValue = nil

    -- A group test frame shows its sample on the plate at the top centre.
    local party = Frame("player", { alpha = 1, group = true, kind = "party",
        threat = { enabled = true, size = 9, anchor = "TOP", x = 0, y = -1, layer = 7, colorCurve = true, background = true } })
    party._msufGFIsPreviewFrame = true
    element.Apply(party, party.MSUFSpec)
    element.Update(party)
    local groupPlate = party.threatIndicatorPlate
    Check(groupPlate and groupPlate.shown and party.threatIndicatorText.text == "85%"
        and groupPlate._msufThreatSample.point[1] == "TOP", "a group test frame must show the sample on its plate at the top centre")
end

---------------------------------------------------------------------------
-- 2e. Hot path: a burst folds into one trailing paint; the group reads nothing
--     while its target cannot hold it on a threat list
---------------------------------------------------------------------------
do
    local now, timers = 100, {}
    _G.GetTime = function() return now end
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
    local function RunDueTimers()
        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            if timer.at <= now + 1e-9 then timer.fn() else timers[#timers + 1] = timer end
        end
    end
    local values, reads = { player = 40 }, 0
    _G.UnitDetailedThreatSituation = function(unit)
        reads = reads + 1
        local value = values[unit]
        if value == nil then return end
        return false, 1, value, value, 1
    end
    local targetExists, targetAttackable = true, true
    _G.UnitExists = function() return targetExists end
    _G.UnitCanAttack = function() return targetAttackable end
    local element = LoadElement(LoadMainlineClient(true), { GF = {} })

    -- Unit frame: the first threat-list event paints at once, the rest of the
    -- burst waits for one shared trailing paint.
    local frame = Frame("target")
    element.Apply(frame, frame.MSUFSpec)
    local fs = frame.threatIndicatorText
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    Check(reads == 1 and fs.text == "40%", "the first threat-list event must paint at once")
    values.player = 60
    now = 100.05
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    now = 100.1
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    Check(reads == 1 and #timers == 1 and fs.text == "40%", "a burst inside the window must wait for one trailing paint")
    now = 100.2
    RunDueTimers()
    Check(reads == 2 and fs.text == "60%" and #timers == 0, "the trailing paint must show the latest value, once")
    -- Anything but a threat-list event paints at once, inside the window too.
    values.player = 70
    now = 100.25
    element.Update(frame, "PLAYER_TARGET_CHANGED")
    Check(reads == 3 and fs.text == "70%", "a new target must paint at once")
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    Check(reads == 3 and #timers == 1, "an event right after the trailing paint must wait for the next window")
    now = 100.4
    RunDueTimers()
    Check(reads == 4, "the next window must paint the waiting frame")
    now = 101
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    Check(reads == 5 and #timers == 0, "an event after a quiet spell must paint at once")

    -- A secret boss value is formatted on every paint, so a burst of ten events
    -- costs one immediate and one trailing SetText.
    local boss = Frame("boss1")
    element.Apply(boss, boss.MSUFSpec)
    values.player = Secret()
    local writes = boss.threatIndicatorText.textWrites
    for step = 0, 9 do
        now = 102 + step * 0.01
        element.Update(boss, "UNIT_THREAT_LIST_UPDATE")
    end
    Check(boss.threatIndicatorText.textWrites == writes + 1, "a burst of secret boss values must write the text once")
    now = 102.2
    RunDueTimers()
    Check(boss.threatIndicatorText.textWrites == writes + 2, "the trailing paint must write the secret text once more")

    -- Target and focus waiting in the same burst share one trailing timer.
    local focus = Frame("focus")
    element.Apply(focus, focus.MSUFSpec)
    values.player = 50
    now = 103
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    element.Update(focus, "UNIT_THREAT_LIST_UPDATE")
    now = 103.05
    element.Update(frame, "UNIT_THREAT_LIST_UPDATE")
    element.Update(focus, "UNIT_THREAT_LIST_UPDATE")
    Check(#timers == 1, "frames waiting in one burst must share one trailing timer")
    now = 103.2
    RunDueTimers()
    Check(#timers == 0 and fs.text == "50%" and focus.threatIndicatorText.text == "50%",
        "the shared trailing paint must repaint every waiting frame")

    -- Group: only an attackable target is read; no target or a friendly one (a
    -- healer clicking the party) clears the texts without a single read.
    local party = Frame("party1", { alpha = 1, group = true, kind = "party",
        threat = { enabled = true, size = 9, anchor = "TOP", x = 0, y = -1, layer = 7 } })
    function party:IsVisible() return true end
    values.party1 = 30
    element.Apply(party, party.MSUFSpec)
    local driver
    for _, created in ipairs(createdFrames) do
        if created.unitEvents.UNIT_THREAT_LIST_UPDATE then driver = created end
    end
    Check(driver, "the group driver did not start")
    now, reads = 110, 0
    driver.scripts.OnEvent(driver, "PLAYER_TARGET_CHANGED")
    Check(reads == 1 and party.threatIndicatorText.text == "30%", "an attackable target must be read")
    targetAttackable = false
    now = 111
    driver.scripts.OnEvent(driver, "PLAYER_TARGET_CHANGED")
    Check(reads == 1 and party.threatIndicatorText.shown == false, "a friendly target must clear the group texts without a read")
    targetExists, targetAttackable = false, true
    now = 112
    driver.scripts.OnEvent(driver, "PLAYER_TARGET_CHANGED")
    Check(reads == 1 and party.threatIndicatorText.shown == false, "no target must clear the group texts without a read")
    targetExists, targetAttackable = true, Secret()
    now = 113
    driver.scripts.OnEvent(driver, "PLAYER_TARGET_CHANGED")
    Check(reads == 2 and party.threatIndicatorText.shown == true, "a secret answer must still read the group")
    element.Disable(party)
    _G.GetTime, _G.C_Timer, _G.UnitExists, _G.UnitCanAttack = nil, nil, nil, nil
end

---------------------------------------------------------------------------
-- 3. Config compile: Mainline (Forever, Midnight) and the Classic clients
---------------------------------------------------------------------------
local function CompileStatus(configRelative, namespace, db)
    namespace.ExportPublic = function(name, value) _G[name] = value; return value end
    _G.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.MSUF_UF_OutlineModeEnabled = function() return false end
    _G.MSUF_UF_NormalizeClassPowerShape = function(value) return value end
    _G.MSUF_ComposeFontFlags = function() return "" end
    _G.MSUF_ResolveFontShadowMetrics = function() return 0, 0, 0 end
    _G.MSUF_CooldownAnchorSupported = function() return false end
    _G.MSUF_GlobalCooldownAnchorEnabled = function() return false end
    local function load(path) assert(loadfile(core .. path))("MidnightSimpleUnitFrames", namespace) end
    load("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
    load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
    load("UnitFrames/Engine/MSUF_UF_Shared.lua")
    load(configRelative)
    _G.MSUF_DB = db or { general = {}, player = {}, target = {}, focus = {}, boss = {}, pet = {}, targettarget = {} }
    _G.MSUF_EnsureDB = function() return _G.MSUF_DB end
    return namespace.UF.Config
end

local function CheckDefaultEntry(entry, label)
    Check(type(entry) == "table" and entry.enabled == DEFAULTS.show and entry.size == DEFAULTS.size
        and entry.anchor == DEFAULTS.anchor and entry.x == DEFAULTS.x and entry.y == DEFAULTS.y
        and entry.layer == DEFAULTS.layer and entry.colorR == nil and entry.background == true,
        label .. ": the compiled threat entry drifted from the defaults")
end

do
    local _, namespace = LoadMainlineClient(true)
    local config = CompileStatus("UnitFrames/Engine/MSUF_UF_Config.lua", namespace)
    for _, unit in ipairs({ "target", "focus", "boss1" }) do
        CheckDefaultEntry(config.GetSpec(unit).status.threat, "Forever " .. unit)
    end
    for _, unit in ipairs({ "player", "pet", "targettarget" }) do
        local entry = config.GetSpec(unit).status.threat
        Check(not (entry and entry.enabled == true), "Forever: the threat text was enabled on " .. unit)
    end

    local custom = { general = {}, target = { showThreatIndicator = false }, focus = { threatIndicatorSize = 15,
        threatIndicatorAnchor = "TOPRIGHT", threatIndicatorOffsetX = -3, threatIndicatorColorR = 1,
        threatIndicatorColorG = 0.25, threatIndicatorColorB = 0, threatIndicatorBackground = false },
        boss = {}, player = {} }
    _, namespace = LoadMainlineClient(true)
    config = CompileStatus("UnitFrames/Engine/MSUF_UF_Config.lua", namespace, custom)
    Check(config.GetSpec("target").status.threat.enabled == false, "Forever: the threat toggle was ignored")
    local focus = config.GetSpec("focus").status.threat
    Check(focus.size == 15 and focus.anchor == "TOPRIGHT" and focus.x == -3 and focus.y == DEFAULTS.y
        and focus.colorR == 1 and focus.colorG == 0.25 and focus.colorB == 0,
        "Forever: saved threat size, anchor, offset or color were not compiled")
    Check(focus.background == false and config.GetSpec("target").status.threat.background == true,
        "Forever: a saved Background off was ignored, or leaked to another frame")

    _, namespace = LoadMainlineClient(false)
    config = CompileStatus("UnitFrames/Engine/MSUF_UF_Config.lua", namespace)
    Check(config.GetSpec("target").status.threat == nil, "Midnight: the Mainline config must compile no threat entry")

    -- Color curve: on by default, off while the frame carries its own threat color
    -- and the toggle is unset, and an explicit toggle always wins.
    _, namespace = LoadMainlineClient(true)
    config = CompileStatus("UnitFrames/Engine/MSUF_UF_Config.lua", namespace, { general = {}, player = {},
        target = { threatIndicatorColorCurve = true, threatIndicatorColorR = 1, threatIndicatorColorG = 1,
            threatIndicatorColorB = 1 },
        focus = { threatIndicatorColorR = 1, threatIndicatorColorG = 0, threatIndicatorColorB = 0 },
        boss = { threatIndicatorColorCurve = false } })
    Check(config.GetSpec("target").status.threat.colorCurve == true, "an explicit Color by threat must win over a custom color")
    Check(config.GetSpec("focus").status.threat.colorCurve == false,
        "a frame with its own threat color must keep it while Color by threat is unset")
    Check(config.GetSpec("boss1").status.threat.colorCurve == false, "Color by threat off was ignored")
    _, namespace = LoadMainlineClient(true)
    config = CompileStatus("UnitFrames/Engine/MSUF_UF_Config.lua", namespace)
    Check(config.GetSpec("target").status.threat.colorCurve == true, "Color by threat must default on")
end

do
    -- Classic Era, TBC and Mists compile through the same Retail-named config as
    -- WoW Forever: the entry exists only where SupportsThreatText is true.
    for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
        local _, namespace = LoadClassicClient(flavor)
        local config = CompileStatus("UnitFrames/Engine/MSUF_UF_Config.lua", namespace)
        local entry = config.GetSpec("target").status.threat
        if flavor == "Mists" then
            Check(entry == nil, "Mists: the unit config compiled a threat entry")
        else
            CheckDefaultEntry(entry, flavor .. " target")
            Check(entry.colorCurve == true, flavor .. ": Color by threat must default on")
            Check(config.GetSpec("player").status.threat.enabled == false, flavor .. ": the threat text was enabled on player")
        end
    end
end

---------------------------------------------------------------------------
-- 3b. Group defaults and compile: Party on, Raid off, top centre, curve on
---------------------------------------------------------------------------
do
    local dbSource = Read("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
    local block = Check(dbSource:match("\n(if MSUF%.Client and MSUF%.Client%.SupportsThreatText == true then\n"
        .. "    for _, defaults in ipairs%({ PARTY_DEFAULTS, RAID_DEFAULTS, MYTHIC_RAID_DEFAULTS }%) do\n.-\nend)\n"),
        "GroupFrames_DB lost its gated threat defaults")
    Check(dbSource:find(block, 1, true) > dbSource:find("\nlocal MYTHIC_RAID_DEFAULTS = {}\ndo\n", 1, true),
        "the threat defaults must follow the Raid and Mythic clone blocks, or Party's own value leaks into them")
    local function Defaults(client)
        local party, raid, mythic = {}, {}, {}
        assert(loadstring("local MSUF, PARTY_DEFAULTS, RAID_DEFAULTS, MYTHIC_RAID_DEFAULTS = ...\n" .. block))(
            { Client = client }, party, raid, mythic)
        return party, raid, mythic
    end
    local party, raid, mythic = Defaults({ SupportsThreatText = true })
    Check(party.threatText == true and raid.threatText == false and mythic.threatText == false,
        "the group threat text must default on for Party and off for Raid")
    Check(party.threatTextBackground == true and raid.threatTextBackground == false
        and mythic.threatTextBackground == false, "the threat plate must default on for Party and off for Raid")
    for _, defaults in ipairs({ party, raid, mythic }) do
        Check(defaults.threatTextColorCurve == true and defaults.threatTextSize == 9 and defaults.threatTextAnchor == "TOP"
            and defaults.threatTextX == 0 and defaults.threatTextY == -1 and defaults.threatTextLayer == 7,
            "a group threat default drifted")
    end
    local bare = Defaults({ SupportsThreatText = false })
    Check(bare.threatText == nil and bare.threatTextSize == nil, "Midnight and Mists must get no group threat keys")

    local config = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
    local regionFn = Check(config:match("\n(local function StatusRegion%(.-\nend)\n"), "Group_Config lost StatusRegion")
    local regions = Check(config:match("\n(local GROUP_STATUS_REGIONS = %b{})\n"), "Group_Config lost GROUP_STATUS_REGIONS")
    local defFn = Check(config:match("\n(local function StatusRegionDef%(.-\nend)\n"), "Group_Config lost StatusRegionDef")
    local threatBlock = Check(config:match("\n  (local threat\n  if MSUF%.Client and MSUF%.Client%.SupportsThreatText == true then\n.-\n  end)\n"),
        "Group_Config lost its gated threat compile")
    local compile = assert(loadstring("local MSUF, conf = ...\n"
        .. "local function Num(value, fallback) return tonumber(value) or fallback end\n"
        .. "local function Layer(value, fallback) return tonumber(value) or fallback end\n"
        .. regionFn .. "\n" .. regions .. "\n" .. defFn .. "\n" .. threatBlock .. "\nreturn threat"))
    local supported = { Client = { SupportsThreatText = true } }
    local entry = compile(supported, party)
    Check(entry and entry.enabled == true and entry.size == 9 and entry.anchor == "TOP" and entry.x == 0
        and entry.y == -1 and entry.layer == 7 and entry.colorCurve == true and entry.background == true,
        "the Party threat entry compiled wrong")
    Check(compile(supported, raid).enabled == false, "the Raid threat entry must compile off by default")
    Check(compile(supported, raid).background == false, "the Raid threat plate must compile off by default")
    entry = compile(supported, {})
    Check(entry.enabled == false and entry.size == 9 and entry.anchor == "TOP" and entry.y == -1 and entry.layer == 7,
        "an empty group scope must fall back to the region defaults, which match the DB defaults")
    Check(entry.colorCurve == true, "an unset group Color by threat must compile on, like its DB default")
    Check(entry.background == false, "an unset group Background must compile off; Party's on comes from its DB default")
    entry = compile(supported, { threatText = true, threatTextColorCurve = false, threatTextSize = 12 })
    Check(entry.enabled == true and entry.colorCurve == false and entry.size == 12, "saved group threat settings were ignored")
    Check(compile({ Client = { SupportsThreatText = false } }, party) == nil, "Midnight and Mists must compile no group threat entry")
    for _, contract in ipairs({
        "\n    threat = threat,\n  }\nend",
        "\n  local threatText = base.status and base.status.threat\n  if threatText then threatText.size = Num(conf.threatTextSize, 9) end\n",
    }) do
        Check(config:find(contract, 1, true), "Group_Config lost a threat contract: " .. contract:gsub("\n", " "))
    end
end

---------------------------------------------------------------------------
-- 4. Menu: the status control on the unit page, Copy To, the preview row
---------------------------------------------------------------------------
local function LoadUnitPage(pageFile, client)
    local namespace = {
        Client = client,
        -- The page binds the engine's frame reader at load, the way every
        -- other Menu2 file does; in game MSUF.UF is published long before
        -- the LoadOnDemand Options addon loads this page.
        UF = { GetFrame = function() return nil end },
        ExportPublic = function() end,
        Translate = function(text) return text end,
        MSUF2 = { Widgets = {} },
    }
    assert(loadfile(options .. "Shell/Menu2/MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", namespace)
    assert(loadfile(options .. "Shell/Menu2/Pages/" .. pageFile))("MidnightSimpleUnitFrames_Options", namespace)
    local page = assert(namespace.MSUF2.UnitPage, pageFile .. " did not publish M.UnitPage")
    for _, spec in ipairs(page.STATUS_CONTROLS) do
        if spec.value == "statusThreat" then return spec, page, namespace.MSUF2 end
    end
    return nil, page, namespace.MSUF2
end

local function CheckControl(spec, label)
    Check(spec, label .. ": the unit page has no Threat % status control")
    Check(spec.text == "Threat %" and spec.refresh == REFRESH and spec.colorPrefix == "threatIndicator",
        label .. ": the control lost its label, refresh bridge or color family")
    Check(spec.statusTextState ~= nil and spec.textIndicator == nil and spec.statusRuntime == true,
        label .. ": the control must use the status text path (own size default, test toggle)")
    for field, key in pairs(KEYS) do
        Check(spec[field] == key, label .. ": the control's " .. field .. " key drifted")
    end
    Check(spec.defaultShow == DEFAULTS.show and spec.defaultSize == DEFAULTS.size and spec.defaultAnchor == DEFAULTS.anchor
        and spec.defaultX == DEFAULTS.x and spec.defaultY == DEFAULTS.y and spec.defaultLayer == DEFAULTS.layer,
        label .. ": the control defaults drifted from the runtime compile")
    for _, unit in ipairs({ "target", "focus", "boss" }) do
        Check(spec.allowed(unit) == true, label .. ": the control must be offered on the " .. unit .. " page")
    end
    for _, unit in ipairs({ "player", "pet", "targettarget", "focustarget", "party", "arena" }) do
        Check(spec.allowed(unit) ~= true, label .. ": the control must not be offered on the " .. unit .. " page")
    end
end

do
    CheckControl(LoadUnitPage("MSUF_Menu2_Unit.lua", LoadMainlineClient(true)), "Forever")
    Check(LoadUnitPage("MSUF_Menu2_Unit.lua", LoadMainlineClient(false)) == nil, "Midnight: the unit page gained the control")
    -- The Classic clients load the same page, so the fact alone decides there too.
    CheckControl(LoadUnitPage("MSUF_Menu2_Unit.lua", (LoadClassicClient("Vanilla"))), "Classic Era")
    CheckControl(LoadUnitPage("MSUF_Menu2_Unit.lua", (LoadClassicClient("TBC"))), "TBC")
    Check(LoadUnitPage("MSUF_Menu2_Unit.lua", (LoadClassicClient("Mists"))) == nil, "Mists: the unit page offered the threat text")
    Check(LoadUnitPage("MSUF_Menu2_Unit.lua", nil) == nil, "without MSUF.Client the threat text must stay off")

    -- Copy To (status scope) carries placement, visibility, color, Color by threat and Background.
    for _, case in ipairs({ { "Forever", (LoadMainlineClient(true)) }, { "Classic Era", (LoadClassicClient("Vanilla")) },
        { "TBC", (LoadClassicClient("TBC")) } }) do
        local pageFile = case[1]
        local _, page, menu = LoadUnitPage("MSUF_Menu2_Unit.lua", case[2])
        local source = { showThreatIndicator = false, threatIndicatorSize = 13, threatIndicatorAnchor = "TOP",
            threatIndicatorOffsetX = 1, threatIndicatorOffsetY = -1, threatIndicatorLayer = 9,
            threatIndicatorColorR = 0.1, threatIndicatorColorG = 0.2, threatIndicatorColorB = 0.3,
            threatIndicatorColorCurve = false, threatIndicatorBackground = false }
        local destination = {}
        local db = { general = {}, target = source, focus = destination }
        menu.EnsureDB = function() return db end
        menu.RequestUnitApply = function() end
        local statusRefreshes = 0
        _G.MSUF_RefreshStatusIndicators = function() statusRefreshes = statusRefreshes + 1 end
        local applied = page.CopyUnitSettings("target", "focus", { status = true })
        Check(statusRefreshes == 1, pageFile .. ": a status copy must refresh the status indicators once")
        _G.MSUF_RefreshStatusIndicators = nil
        Check(applied == true, pageFile .. ": Copy To refused a status copy")
        for key, value in pairs(source) do
            Check(destination[key] == value, pageFile .. ": Copy To (status) does not copy " .. key)
        end
    end
end

do
    local function PipeRows(rows)
        local out = {}
        for line in rows:gmatch("[^\r\n]+") do
            local columns = {}
            for value in (line .. "|"):gmatch("(.-)|") do columns[#columns + 1] = value end
            out[#out + 1] = columns
        end
        return out
    end
    local function PreviewRows(client)
        local main = { Client = client, MSUF2 = { PipeRows = PipeRows } }
        assert(loadfile(options .. "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua"))(
            "MidnightSimpleUnitFrames_Options", main)
        local rows = main.UFPreviewSpecs.StatusPreview
        for index, spec in ipairs(rows) do
            if spec.id == "statusThreat" then return spec, index, rows end
        end
        return nil, nil, rows
    end
    for _, case in ipairs({ { "Forever", LoadMainlineClient(true) }, { "Vanilla", LoadClassicClient("Vanilla") },
        { "TBC", LoadClassicClient("TBC") } }) do
        local spec, index, rows = PreviewRows(case[2])
        Check(spec, case[1] .. ": the preview specs have no threat row")
        Check(spec.show == KEYS.show and spec.size == KEYS.size and spec.anchor == KEYS.anchor and spec.x == KEYS.x
            and spec.y == KEYS.y and spec.layer == KEYS.layer and spec.refresh == REFRESH, case[1] .. ": preview keys drifted")
        Check(spec.defaultShow == nil and spec.defaultSize == DEFAULTS.size and spec.defaultAnchor == DEFAULTS.anchor
            and spec.defaultX == DEFAULTS.x and spec.defaultY == DEFAULTS.y and spec.defaultLayer == DEFAULTS.layer,
            case[1] .. ": the preview row drifted from the runtime defaults")
        Check(spec.allowed("target") and spec.allowed("focus") and spec.allowed("boss") and not spec.allowed("player"),
            case[1] .. ": the preview row must cover target, focus and boss only")
        Check(rows[#rows].id == "stance" and rows[#rows - 1].id == "statusPetHappiness" and index == #rows - 2,
            case[1] .. ": the threat row must sit before Pet Happiness and the stance row")
    end
    Check(PreviewRows(LoadMainlineClient(false)) == nil, "Midnight: the preview specs gained a threat row")
    Check(PreviewRows(LoadClassicClient("Mists")) == nil, "Mists: the preview specs gained a threat row")

    -- Every client loads these Retail-named files: the Classic menu manifests name
    -- them too (the Classic copies were collapsed into them).
    local MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
    for manifest, script in pairs({
        ["Preview/MSUF_Menu2_UnitPreview_Classic.xml"] = { "MSUF_Menu2_UnitPreview_Status.lua", "MSUF_Menu2_UnitPreview_Render.lua" },
        ["MSUF_Menu2_AfterUnitPreview_Classic.xml"] = { "Pages\\MSUF_Menu2_UnitStatusSection.lua" },
        ["MSUF_Menu2_AfterSearch_Classic.xml"] = { "Pages\\MSUF_Menu2_Unit.lua" },
    }) do
        local xml = Read(MENU .. manifest)
        for _, file in ipairs(script) do
            Check(xml:find('<Script file="' .. file .. '"/>', 1, true), manifest .. " does not load " .. file)
        end
    end
    do
        local status = Read(MENU .. "Preview/MSUF_Menu2_UnitPreview_Status.lua")
        Check(status:find('\n    statusThreat = "85%",\n}', 1, true),
            "UnitPreview_Status: the threat row must render as status text with the 85% sample")
        local render = Read(MENU .. "Preview/MSUF_Menu2_UnitPreview_Render.lua")
        Check(render:find('statusPetHappiness = "petHappiness", statusThreat = "threat",', 1, true),
            "UnitPreview_Render: the preview must read the compiled threat entry")
        Check(render:find('                textW = R.PreviewStatus.ThreatPlate and R.PreviewStatus.ThreatPlate(icon, spec, conf, g, S(2), S(1)) or textW\n',
            1, true),
            "UnitPreview_Render: the Threat % preview no longer lays out on its plate")
        local section = Read(MENU .. "Pages/MSUF_Menu2_UnitStatusSection.lua")
        Check(section:find('\n    local threat = FindStatusSpec(unit, "statusThreat")\n'
            .. '    if threat and threat.value == "statusThreat" and type(M.RegisterVirtualRuntimeControl) == "function" then\n'
            .. '        local meta = ControlMeta(ctx, "status.indicator.threat", "setting")\n', 1, true),
            "UnitStatusSection: the threat search control must exist only where the status spec does")
        -- Color by threat: built only where the Threat % control exists, same default
        -- as the compile, ::: lists the three curve colors while it is on, and
        -- Reset selected returns it to that default.
        for _, contract in ipairs({
            '        return ReadStatusBool(unit, "threatIndicatorColorCurve", customR == nil)\n',
            '    if threatSpec and threatSpec.value == "statusThreat" then\n'
                .. '        local threatColorCurve = W.ToggleAt(selectedCard, "Color by threat", 16, -106, selectedControlW)\n',
            'SetBool(unit, "threatIndicatorColorCurve", value, "MSUF2_STATUS_THREAT_COLOR_CURVE", { preview = true })',
            '"status.threat.color_curve", nil, { settingKey = tostring(unit) .. ".threatIndicatorColorCurve" })',
            '                    if spec and spec.value == "statusThreat" and state.ThreatColorCurveEnabled\n'
                .. '                        and state.ThreatColorCurveEnabled() and M._threatCurveColorReferences\n'
                .. '                        and #M._threatCurveColorReferences > 0 then\n'
                .. '                        return M._threatCurveColorReferences\n',
            '            ShowControl(threatColorCurve, spec and spec.value == "statusThreat")\n',
            '            if spec.value == "statusThreat" then\n'
                .. '                conf.threatIndicatorColorCurve, conf.threatIndicatorBackground = nil, nil\n',
            '        local threatBackground = W.ToggleAt(selectedCard, "Background", 16, -136, selectedControlW)\n'
                .. '        M.BindBoolWidget(ctx, threatBackground, function() return ReadStatusBool(unit, "threatIndicatorBackground", true) end,\n',
            'SetBool(unit, "threatIndicatorBackground", value, "MSUF2_STATUS_THREAT_BACKGROUND", { preview = true })',
            '"status.threat.background", nil, { settingKey = tostring(unit) .. ".threatIndicatorBackground" })',
            '    local threatBackground = state.threatBackground\n',
            '            ShowControl(threatBackground, spec and spec.value == "statusThreat")\n'
                .. '            SetControlEnabled(threatBackground, spec and spec.value == "statusThreat" and isEnabled)\n',
            'yellow at half, pink at 100% when you have aggro.',
        }) do
            Check(section:find(contract, 1, true),
                "UnitStatusSection: Color by threat lost a contract: " .. contract:gsub("\n", " "):sub(1, 90))
        end
        Check(not section:find("red at 100%", 1, true), "UnitStatusSection: the curve help still says red")
    end

    -- Preview: the sample shows its curve color, with the compile's default rule.
    local function LoadPreviewStatus(client)
        local addon = { Client = client,
            UFPreview = { Model = { MakeFS = function() end, FontColor = function() return 1, 1, 1 end } } }
        assert(loadfile(options .. "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua"))(
            "MidnightSimpleUnitFrames_Options", addon)
        return addon.UFPreviewStatus
    end
    local function ThreatNamespace(client)
        local ns = {
            Client = client,
            UF = { Layers = {}, Shared = {}, RegisterElement = function() end, RefreshElements = function() return true end },
        }
        assert(loadfile(core .. MODULE))("MidnightSimpleUnitFrames", ns)
        return ns
    end
    local namespace = ThreatNamespace((LoadMainlineClient(true)))
    local previewCases = { { "Forever", namespace }, { "Classic Era", ThreatNamespace((LoadClassicClient("Vanilla"))) },
        { "TBC", ThreatNamespace((LoadClassicClient("TBC"))) } }
    -- Mists loads the preview file too, but no threat module: its sample keeps the text color.
    local mistsNS = ThreatNamespace((LoadClassicClient("Mists")))
    Check(mistsNS.UFThreatText == nil, "Mists: the threat module published itself")
    local oldNS = _G.MSUF_NS
    _G.MSUF_NS = mistsNS
    Check(LoadPreviewStatus(mistsNS.Client).ThreatCurveColor({}, {}) == nil, "Mists: the preview drew a threat curve color without the module")
    local function PreviewIcon(text)
        local bg = { points = {} }
        function bg:ClearAllPoints() self.points = {}; self.allPoints = nil end
        function bg:SetAllPoints() self.allPoints = true end
        function bg:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function bg:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
        local txt = { text = text }
        function txt:SetText(value) self.text = value end
        function txt:GetText() return self.text end
        function txt:GetStringWidth() return #self.text * 5 end
        return { bg = bg, txt = txt }
    end
    -- Every client loads the same Retail-named preview file; the curve comes from
    -- that client's own core module.
    for _, case in ipairs(previewCases) do
        local label = "UnitPreview_Status (" .. case[1] .. ")"
        _G.MSUF_NS = case[2]
        local preview = LoadPreviewStatus(case[2].Client)
        local spec = { id = "statusThreat", size = "threatIndicatorSize" }
        local r, g, b = preview.TextIndicatorColor(spec, {}, {}, {})
        local er, eg, eb = case[2].UFThreatText.CurveColorAt({}, 85)
        Check(r == er and g == eg and b == eb, label .. ": the sample must show its 85% curve color")
        r, g, b = preview.TextIndicatorColor(spec, { threatIndicatorColorR = 0, threatIndicatorColorG = 0.5,
            threatIndicatorColorB = 1 }, {}, {})
        Check(r == 0 and g == 0.5 and b == 1, label .. ": a frame's own threat color must win while the curve is unset")
        r = preview.TextIndicatorColor(spec, { threatIndicatorColorCurve = true, threatIndicatorColorR = 0,
            threatIndicatorColorG = 0.5, threatIndicatorColorB = 1 }, {}, {})
        Check(r == er, label .. ": an explicit Color by threat must win in the preview")
        -- The plate: on unless turned off, as wide as "100%", padded around the icon.
        Check(preview.ThreatBackgroundEnabled({}, {}) == true
            and preview.ThreatBackgroundEnabled({ threatIndicatorBackground = false }, {}) == false
            and preview.ThreatBackgroundEnabled({}, { threatIndicatorBackground = false }) == false
            and preview.ThreatBackgroundEnabled({ threatIndicatorBackground = true }, { threatIndicatorBackground = false }) == true,
            label .. ": the plate default drifted from the compile")
        local icon = PreviewIcon("85%")
        local bg = icon.bg
        Check(preview.ThreatPlate(icon, spec, {}, {}, 4, 2) == 20 and icon.txt.text == "85%",
            label .. ": the plate must measure 100% and keep the 85% sample")
        Check(#bg.points == 2 and bg.points[1][1] == "TOPLEFT" and bg.points[1][2] == icon and bg.points[1][4] == -4
            and bg.points[1][5] == 2 and bg.points[2][1] == "BOTTOMRIGHT" and bg.points[2][2] == icon
            and bg.points[2][4] == 4 and bg.points[2][5] == -2 and bg.colorTexture[1] == 0 and bg.colorTexture[4] == 0.75,
            label .. ": the preview plate must be the runtime's dark plate")
        Check(preview.ThreatPlate(icon, spec, { threatIndicatorBackground = false }, {}, 4, 2) == nil and bg.allPoints
            and bg.colorTexture[4] == 0, label .. ": Background off must clear the preview plate")
        Check(preview.ThreatPlate(PreviewIcon("80"), { id = "level" }, {}, {}, 4, 2) == nil,
            label .. ": only Threat % gets a plate")
    end
    _G.MSUF_NS = oldNS

    -- Colors page: the curve rows run for real in a sandbox. Their keys and defaults
    -- are literals (the offline search index generator never loads the runtime
    -- module), so they are pinned to the module's CURVE_STOPS here; the static color
    -- joins the indicator list; a swatch edit refreshes the threat element.
    local colors = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua")
    local block = Check(colors:match("\n(if MSUF%.Client and MSUF%.Client%.SupportsThreatText == true then\n    M%._threatCurveColor = .-\nend)\n"),
        "Colors page lost its gated threat curve rows")
    local function Rows(client)
        local M = {}
        assert(loadstring("local MSUF, M = ...\n" .. block))({ Client = client }, M)
        return M._threatCurveColor
    end
    for i, stop in ipairs(namespace.UFThreatText.CURVE_STOPS) do
        local row = (Rows({ SupportsThreatText = true }) or {})[i]
        Check(row and row[1] == stop[1] and Near(row[3], stop[2]) and Near(row[4], stop[3]) and Near(row[5], stop[4]),
            "Colors page threat row " .. i .. " differs from the module's curve stop")
    end
    Check(Rows({ SupportsThreatText = false }) == nil, "Colors page built threat curve rows without the client fact")
    local rows = Check(Rows({ SupportsThreatText = true }), "Colors page built no threat curve rows")
    local EXPECTED = {
        { "threatColorLow", "Low threat", LOW, "threat.curve.low" },
        { "threatColorMid", "Medium threat", MID, "threat.curve.mid" },
        { "threatColorHigh", "High threat", HIGH, "threat.curve.high" },
    }
    for i, want in ipairs(EXPECTED) do
        local row = rows[i]
        Check(row and row[1] == want[1] and row[2] == want[2] and Near(row[3], want[3][1]) and Near(row[4], want[3][2])
            and Near(row[5], want[3][3]) and row[6] == want[4], "Colors page threat row " .. i .. " drifted")
    end
    for _, contract in ipairs({
        'indicators[#indicators + 1] = { value = "threatIndicator", text = "Threat %" }',
        'b:CollapsibleSection("colors_status_text", "Status Text Colors", M._threatCurveColor and 550 or 410, false)',
        'LabelAt(statusText, "Threat % Colors", 12, -410,',
        '                    SetGeneralRGB(row[1], r, g, bcol)\n                    M._ApplyThreatCurveColors()\n',
        'function M._ApplyThreatCurveColors()\n    ApplyColors()\n    local refresh = _G.MSUF_RequestThreatIndicatorRefresh\n',
    }) do
        Check(colors:find(contract, 1, true), "Colors page lost a threat curve contract: " .. contract:gsub("\n", " "):sub(1, 90))
    end
    local context = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Context.lua")
    Check(context:find("ContextGeneral(row[6], row[2], row[1], row[3], row[4], row[5], M._ApplyThreatCurveColors)", 1, true)
        and context:find("M._threatCurveColorReferences = threatReferences", 1, true),
        "the ::: context no longer builds the threat curve targets")
    local meta = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Meta.lua")
    for _, want in ipairs(EXPECTED) do
        Check(meta:find('["' .. want[4] .. '"] = PrefixedSettingKeys("general.' .. want[1] .. '", "R G B"),', 1, true),
            "the Colors meta no longer maps " .. want[4] .. " to general." .. want[1])
    end
end

---------------------------------------------------------------------------
-- 4b. Group menu: the Threat % indicator on the group Status & Indicators page
---------------------------------------------------------------------------
do
    local function GroupSpecs(client)
        local namespace = { Client = client, ExportPublic = function() end, Translate = function(text) return text end,
            MSUF2 = { Widgets = {} } }
        assert(loadfile(options .. "Shell/Menu2/MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", namespace)
        assert(loadfile(options .. "Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua"))("MidnightSimpleUnitFrames_Options", namespace)
        local specs = namespace.MSUF2.GroupSpecs
        local found, listed
        for _, spec in ipairs(specs.GF_STATUS_ICON_SPECS) do
            if spec.value == "threatText" then found = spec end
        end
        for _, value in ipairs(specs.GF_STATUS_ICON_VALUES) do
            if value.value == "threatText" then listed = value end
        end
        return found, listed
    end
    local spec, listed = GroupSpecs({ SupportsThreatText = true })
    Check(spec and listed and listed.text == "Threat %", "the group status page lists no Threat % indicator")
    Check(spec.text == "Threat %" and spec.enabled == "threatText" and spec.size == "threatTextSize"
        and spec.anchor == "threatTextAnchor" and spec.x == "threatTextX" and spec.y == "threatTextY"
        and spec.layer == "threatTextLayer" and spec.defaultSize == 9 and spec.defaultAnchor == "TOP"
        and spec.defaultLayer == 7 and spec.iconStyle == nil and spec.customIcon == nil and spec.isText == true,
        "the group Threat % indicator row drifted from the compiled region")
    Check(GroupSpecs({ SupportsThreatText = false }) == nil, "Midnight and Mists must not list the group Threat % indicator")

    local page = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
    for _, contract in ipairs({
        '            or value == "levelText" or value == "threatText"\n',
        '                    if spec and spec.value == "threatText" and Bool(CurrentScope(), "threatTextColorCurve", true)\n'
            .. '                        and M._threatCurveColorReferences and #M._threatCurveColorReferences > 0 then\n'
            .. '                        return M._threatCurveColorReferences\n',
        '    if MSUF.Client and MSUF.Client.SupportsThreatText == true then\n'
            .. '        threatColorCurve = BindScopeToggle(ctx, W.ToggleAt(selectedCard, "Color by threat", 16, -106, siconLeftW - 32), "threatTextColorCurve", true, "visual")\n',
        '            conf.threatTextColorCurve = gf and gf.GetDefault and gf.GetDefault(kind, "threatTextColorCurve") or nil\n',
        '                W.SetControlShown(threatColorCurve, isThreatText)\n',
        '        threatBackground = BindScopeToggle(ctx, W.ToggleAt(selectedCard, "Background", 16, -136, siconLeftW - 32), "threatTextBackground", false, "visual")\n',
        '            conf.threatTextBackground = gf and gf.GetDefault and gf.GetDefault(kind, "threatTextBackground")\n',
        '                W.SetControlShown(threatBackground, isThreatText)\n',
        '            SetOptionEnabled(threatBackground, isThreatText and enabled)\n',
        'yellow at half, pink at 100% when you have aggro.',
    }) do
        Check(page:find(contract, 1, true), "Group Status & Indicators lost a threat contract: " .. contract:gsub("\n", " "):sub(1, 90))
    end
    Check(Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
        :find(" levelTextDifficultyColor threatTextColorCurve threatTextBackground]]", 1, true),
        "group Copy To no longer carries Color by threat and Background")
    local groupPreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
    Check(groupPreview:find('\nGF_STATUS_RUNTIME_KEYS.threatText = "threat"\n', 1, true)
        and groupPreview:find('    if value == "threatText" then return "85%" end\n', 1, true),
        "the group preview no longer shows the Threat % sample from the compiled entry")
end

---------------------------------------------------------------------------
-- 5. Font refresh, search ties, manifests, locales
---------------------------------------------------------------------------
do
    local fonts = Read("MidnightSimpleUnitFrames/Runtime/MSUF_FontRuntime.lua")
    Check(fonts:find('if MSUF.Client and MSUF.Client.SupportsThreatText == true then\n'
        .. '    UNITFRAME_FONT_ELEMENTS[#UNITFRAME_FONT_ELEMENTS + 1] = "ThreatIndicator"\nend', 1, true),
        "a font change must refresh the threat text where the client offers it, and nowhere else")

    local query = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua")
    for _, page in ipairs({ "target", "focus", "boss" }) do
        Check(query:find('["id\\031uf_' .. page .. '\\031menu2%2Euf_' .. page .. '%2Eunit%2Estatus%2Eindicator%2Ethreat"]'
            .. ' = "SupportsThreatText",', 1, true), "the " .. page .. " threat search row is not tied to SupportsThreatText")
        Check(query:find('["id\\031uf_' .. page .. '\\031menu2%2Euf_' .. page .. '%2Eunit%2Estatus%2Ethreat%2Ebackground"]'
            .. ' = "SupportsThreatText",', 1, true), "the " .. page .. " Background search row is not tied to SupportsThreatText")
    end
    Check(query:find('["id\\031gf_indicators\\031menu2%2Egf_indicators%2Egroup%2Efield%2Ethreattextbackground"]'
        .. ' = "SupportsThreatText",', 1, true), "the group Background search row is not tied to SupportsThreatText")

    Check(Read("MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml")
        :find('MSUF_UF_PetHappiness.lua"/>\n  <Script file="..\\..\\..\\Game\\Shared\\UnitFrames\\MSUF_UF_ThreatText.lua"/>', 1, true),
        "the Mainline manifest must load the threat module behind the shared element prefix")
    for _, flavor in ipairs({ "Vanilla", "TBC" }) do
        Check(Read("MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames.xml")
            :find("..\\Shared\\UnitFrames\\MSUF_UF_ThreatText.lua", 1, true), flavor .. " must load the threat module")
    end
    Check(not Read("MidnightSimpleUnitFrames/Game/Mists/UnitFrames.xml"):find("MSUF_UF_ThreatText", 1, true),
        "Mists must not load the threat module")

    local LABELS = {
        "Threat %", "Color by threat", "Threat % Colors", "Low threat", "Medium threat", "High threat",
        "Green at low threat, yellow at half, pink at 100% when you have aggro. Turn off to use the status text color instead.",
        "Blended from low to high threat on every frame that colors its threat text by threat.",
        "Threat % Background",
        "A dark plate behind the number keeps it readable on any bar color, red enemy bars included.",
    }
    for _, locale in ipairs({ "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local text = Read("MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua")
        for _, label in ipairs(LABELS) do
            Check(text:find('\nL["' .. label .. '"] = "', 1, true), locale .. " has no label for: " .. label)
        end
        Check(not text:find("red at 100% when you have aggro", 1, true), locale .. " still carries the red curve tooltip")
    end
end

---------------------------------------------------------------------------
-- 6. Real boot: a party frame applies the element through the adapter's mask
---------------------------------------------------------------------------
do
    -- A group frame applies only the elements the group adapter's base mask names,
    -- and that file loads after the module, so no test of the element alone can see
    -- a missing entry (a party frame then shows nothing while target works). Boot
    -- each client, deliver the addon's own ADDON_LOADED, and apply a party spec
    -- through the real UF core with the adapter's own mask.
    local World = dofile(root .. "/tools/tests/client_world.lua")
    for _, case in ipairs({ { "Forever", true }, { "Vanilla", true }, { "TBC", true }, { "Mainline", false }, { "Mists", false } }) do
        local flavor, supported = case[1], case[2]
        local world = World.New(root, flavor):Boot()
        local failure = world:FirstFailure()
        Check(failure == nil, flavor .. " did not boot: " .. tostring(failure and failure.file) .. " "
            .. tostring(failure and failure.message))
        -- Other modules' handlers may trip over the offline stubs; only the join matters here.
        for _, listener in ipairs(world.widgets.frames) do
            local handler = listener.events and listener.events.ADDON_LOADED and listener.scripts and listener.scripts.OnEvent
            if handler then pcall(handler, listener, "ADDON_LOADED", "MidnightSimpleUnitFrames") end
        end
        local mask = world.core.GF and world.core.GF.GROUP_APPLY_MASK
        Check(type(mask) == "table", flavor .. ": the group adapter no longer publishes GF.GROUP_APPLY_MASK")
        Check((mask.ThreatIndicator == true) == supported,
            flavor .. ": the group apply mask " .. (supported and "lacks" or "gained") .. " the threat element")
        local frame = world.env.CreateFrame("Button", nil, world.env.UIParent)
        frame.MSUFUnitKey = "party1"
        world.core.UF.ApplySpec(frame, {
            scope = "group", font = "Fonts\\FRIZQT__.TTF", fontFlags = "OUTLINE", textColor = { r = 1, g = 1, b = 1, a = 1 },
            status = { group = true, kind = "party", alpha = 1, threat = { enabled = true, size = 9, anchor = "TOP",
                x = 0, y = -1, layer = 7, colorCurve = true, background = true } },
        }, nil, mask)
        local built = frame.threatIndicatorText ~= nil and frame.threatIndicatorPlate ~= nil
            and frame._msufActiveElements and frame._msufActiveElements.ThreatIndicator == true
        Check((built == true) == supported, flavor .. ": a party frame " .. (supported and "did not build" or "built")
            .. " the threat text through the real group apply")
    end
end

print("threat_text_smoke: ok")
