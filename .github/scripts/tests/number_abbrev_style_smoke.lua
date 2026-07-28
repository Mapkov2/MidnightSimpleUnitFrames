-- Regression for the global number-abbreviation style (Misc > Language).
--
-- Covers three contracts:
--   1. The COMPACT breakpoint table is well-formed and reproduces the exact
--      output the feature request asked for (no space, English letters, three
--      significant digits).
--   2. Runtime resolution: GAME yields nil options, COMPACT yields a table, a
--      client that ignores or mangles the options falls back to GAME.
--   3. Every abbreviating call site forwards the options argument, and no
--      BreakUpLargeNumbers call site does.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function ReadSource(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "missing source: " .. relative)
    local body = handle:read("*a")
    handle:close()
    -- The editor saves CRLF locally and LF in CI; normalize before matching.
    return (body:gsub("\r\n", "\n"))
end

--==========================================================================--
-- Fake client
--==========================================================================--

-- The API only allows fraction divisors that are powers of ten; anything else
-- is rejected with AbbreviationDataError.NotMultipleOfTen.
local FRACTION_DIGITS = { [1] = 0, [10] = 1, [100] = 2 }

-- Mirrors the documented NumberAbbreviationBreakpoint semantics closely enough
-- to prove the shipped table produces the intended strings.
local function FormatWithBreakpoints(value, data)
    for i = 1, #data do
        local row = data[i]
        if value >= row.breakpoint then
            local digits = FRACTION_DIGITS[row.fractionDivisor]
            Check(digits ~= nil, "unsupported fractionDivisor: " .. tostring(row.fractionDivisor))
            local significand = math.floor(value / row.significandDivisor)
            local text
            if digits > 0 then
                text = string.format("%." .. digits .. "f", significand / row.fractionDivisor)
            else
                text = string.format("%d", significand)
            end
            return text .. row.abbreviation
        end
    end
    return string.format("%d", value)
end

-- Default client behavior stands in for a locale that inserts a space, which is
-- exactly what the request wants to be able to override.
local function SpacedAbbreviator(value, options)
    if type(options) == "table" then
        local data = options.breakpointData or (options.config and options.config.data)
        if data then return FormatWithBreakpoints(value, data) end
    end
    if value >= 1000000 then return string.format("%d M", math.floor(value / 1000000)) end
    if value >= 1000 then return string.format("%d K", math.floor(value / 1000)) end
    return tostring(value)
end

local function StubFrame()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function() end,
    }
end

local MODULE = root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_NumberFormat.lua"

-- Each load gets a clean chunk so the module's one-shot capability probe reruns.
local function LoadModule(abbreviator, createConfig, style, addon)
    _G.MSUF_DB = { general = { numberAbbrevStyle = style } }
    _G.AbbreviateNumbers = abbreviator
    _G.AbbreviateLargeNumbers = abbreviator
    _G.CreateAbbreviateConfig = createConfig
    _G.CreateFrame = function() return StubFrame() end
    addon = addon or {}
    assert(loadfile(MODULE))("MidnightSimpleUnitFrames", addon)
    return addon.NumberFormat
end

--==========================================================================--
-- 1. Breakpoint table shape and output
--==========================================================================--

local NF = LoadModule(SpacedAbbreviator, nil, nil)
Check(type(NF) == "table", "module did not expose MSUF.NumberFormat")

local data = NF.COMPACT_BREAKPOINTS
Check(type(data) == "table" and #data > 0, "missing COMPACT breakpoint data")

local NAMED_ORDER = { [1e3] = "K", [1e6] = "M", [1e9] = "B", [1e12] = "T" }
for i = 1, #data do
    local row = data[i]
    Check(row.abbreviationIsGlobal == false,
        "row " .. i .. ": abbreviationIsGlobal must be false or the letter gets localized")
    if i > 1 then
        Check(row.breakpoint < data[i - 1].breakpoint,
            "row " .. i .. ": breakpoints must be ordered largest to smallest")
    end
    -- significandDivisor * fractionDivisor must land on the named order the
    -- letter claims, otherwise the digits and the suffix disagree.
    local order = row.significandDivisor * row.fractionDivisor
    Check(NAMED_ORDER[order] == row.abbreviation,
        "row " .. i .. ": " .. tostring(row.abbreviation) .. " does not match order " .. tostring(order))
end

-- The exact ladder from the feature request, plus the trillion tier MSUF adds
-- so the table does not fall off a cliff above 100B.
local EXPECTED = {
    { 123, "123" },
    { 1234, "1234" },
    { 12345, "12.3K" },
    { 123456, "123K" },
    { 1234567, "1.23M" },
    { 12345678, "12.3M" },
    { 123456789, "123M" },
    { 1234567890, "1.23B" },
    { 12345678901, "12.3B" },
    { 123456789012, "123B" },
    { 1234567890123, "1.23T" },
}
for i = 1, #EXPECTED do
    local value, want = EXPECTED[i][1], EXPECTED[i][2]
    local got = FormatWithBreakpoints(value, data)
    Check(got == want, "compact format for " .. value .. ": expected " .. want .. ", got " .. tostring(got))
    Check(not got:find("%s"), "compact format for " .. value .. " must not contain a space")
end

--==========================================================================--
-- 2. Runtime resolution and sinks
--==========================================================================--

Check(NF.GetStyle() == "GAME", "default style must be GAME")
Check(NF.GetOptions() == nil, "GAME must pass nil options so the client decides")

-- Sinks legitimately receive nil for GAME, so record a sentinel to keep the
-- push log countable.
local NIL_PUSH = {}
local pushes = {}
NF.Register(function(options) pushes[#pushes + 1] = options or NIL_PUSH end)
Check(#pushes == 1 and pushes[1] == NIL_PUSH, "Register must immediately seed the sink with the current options")

_G.MSUF_DB.general.numberAbbrevStyle = "COMPACT"
Check(NF.Refresh() == "COMPACT", "Refresh did not adopt COMPACT from the DB")
Check(type(NF.GetOptions()) == "table", "COMPACT must produce an options table")
Check(#pushes == 2 and type(pushes[2]) == "table", "style change did not reach the registered sink")

-- Re-resolving the same style must not churn consumers.
Check(NF.Refresh() == "COMPACT", "repeat Refresh changed the style")
Check(#pushes == 2, "repeat Refresh pushed a redundant update")

_G.MSUF_DB.general.numberAbbrevStyle = "GAME"
Check(NF.Refresh() == "GAME", "Refresh did not return to GAME")
Check(NF.GetOptions() == nil, "returning to GAME must clear the options")
Check(#pushes == 3 and pushes[3] == NIL_PUSH, "return to GAME did not reach the sink")

-- An explicit style argument must not read the DB.
Check(NF.Refresh("COMPACT") == "COMPACT", "explicit style argument was ignored")
Check(NF.NormalizeStyle("nonsense") == "GAME", "unknown styles must normalize to GAME")

--==========================================================================--
-- 3. Client capability fallback
--==========================================================================--

-- A client that silently ignores the options table still returns spaced text.
-- MSUF must notice and stay on GAME rather than advertise a dead setting.
local function IgnoresOptions(value)
    return string.format("%d K", math.floor(value / 1000))
end
local stubborn = LoadModule(IgnoresOptions, nil, "COMPACT")
Check(stubborn.Refresh() == "GAME", "a client that ignores options must fall back to GAME")
Check(stubborn.GetOptions() == nil, "rejected options must not be handed to consumers")
Check(stubborn.IsCompactSupported() == false, "IsCompactSupported must report the rejection")

-- CreateAbbreviateConfig is preferred when the client offers it.
local configCalls = 0
local function CreateConfig(rows)
    configCalls = configCalls + 1
    return { data = rows }
end
local cached = LoadModule(SpacedAbbreviator, CreateConfig, "COMPACT")
Check(cached.Refresh() == "COMPACT", "config-backed client did not reach COMPACT")
Check(configCalls == 1, "CreateAbbreviateConfig must be called exactly once")
Check(cached.GetOptions().config ~= nil, "the cached config object must be used when available")

-- A hard error behind the restricted-breakpoints precondition must degrade to
-- the raw breakpointData form instead of breaking text.
local function ExplodingConfig() error("restricted") end
local degraded = LoadModule(SpacedAbbreviator, ExplodingConfig, "COMPACT")
Check(degraded.Refresh() == "COMPACT", "a failing CreateAbbreviateConfig must not disable COMPACT")
Check(degraded.GetOptions().breakpointData ~= nil, "fallback must pass raw breakpointData")

-- No abbreviator at all (very old client) must not error.
local bare = LoadModule(nil, nil, "COMPACT")
Check(bare.Refresh() == "GAME", "a client without an abbreviator must stay on GAME")

--==========================================================================--
-- 4. End-to-end through the unitframe text engine
--==========================================================================--

-- The sink registration depends on Text_Format receiving the same namespace
-- table the runtime module wrote to. A namespace or load-order mistake there
-- fails silently (every frame just keeps the client format), so drive the real
-- writer instead of trusting the wiring.
_G.wipe = _G.wipe or function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

local TextStub = {
    UnitPowerType = function() return 0 end,
    AbbreviateNumbers = SpacedAbbreviator,
    AbbreviateLargeNumbers = SpacedAbbreviator,
    BreakUpLargeNumbers = function(value) return "FULL:" .. tostring(value) end,
    tonumber = tonumber,
    type = type,
    format = string.format,
    floor = math.floor,
    max = math.max,
    REVERSE_HEALTH_MODE = {},
}
local engineAddon = { UFText = TextStub, Apply = {} }
-- Mirrors the TOC order: the runtime module loads before any text consumer.
local engineNF = LoadModule(SpacedAbbreviator, nil, nil, engineAddon)
TextStub.BreakUpLargeNumbers = function(value) return "FULL:" .. tostring(value) end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua"))(
    "MidnightSimpleUnitFrames", engineAddon)

local fontString = {
    shown = true,
    IsShown = function(self) return self.shown end,
    SetText = function(self, value) self.text = value end,
    SetFormattedText = function(self, pattern, ...) self.text = string.format(pattern, ...) end,
}
local frame = { unit = "player", hpTextRight = fontString }
local spec = { key = "player", showName = false, showHealthText = true, showPowerText = false }
local textConfig = {
    healthLeft = "NONE",
    healthCenter = "NONE",
    healthRight = "CURRENT",
    healthDelimiter = " / ",
    healthShortNumbers = true,
    powerLeft = "NONE",
    powerCenter = "NONE",
    powerRight = "NONE",
}
local runtime = TextStub.CompileTextRuntime(frame, spec, textConfig)
local slot = runtime.healthSlots[1]
Check(slot ~= nil, "text engine did not compile a health slot")

local function WriteHealth()
    fontString.text = nil
    slot.plainWriter(slot, 12345, 1000000, 2, true, {})
    return fontString.text
end

Check(WriteHealth() == "12 K", "GAME style must produce the unmodified client output")
Check(engineNF.Refresh("COMPACT") == "COMPACT", "engine namespace did not accept COMPACT")
Check(WriteHealth() == "12.3K",
    "COMPACT did not reach the compiled text slot: " .. tostring(fontString.text))
Check(engineNF.Refresh("GAME") == "GAME", "engine namespace did not return to GAME")
Check(WriteHealth() == "12 K", "switching back to GAME did not restore the client output")

--==========================================================================--
-- 5. Call-site contract
--==========================================================================--

local format = ReadSource("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua")
local ABBREV_CALLS = {
    "AbbreviateSecretNumber(value, NUM_OPTS)",
    "AbbreviateShortNumber(value, NUM_OPTS)",
    "AbbreviateShortNumber(value or 0, NUM_OPTS)",
    "AbbreviateSecretNumber(value, NUM_OPTS), \"%s\"",
}
for i = 1, #ABBREV_CALLS do
    Check(format:find(ABBREV_CALLS[i], 1, true),
        "Text_Format lost the options argument at: " .. ABBREV_CALLS[i])
end
Check(format:find("NumberFormat.Register(function(options) NUM_OPTS = options end)", 1, true),
    "Text_Format no longer subscribes to the abbreviation style")
-- BreakUpLargeNumbers takes no abbreviation options; handing it one is a bug.
Check(not format:find("BreakUpLargeNumbers(value, NUM_OPTS)", 1, true),
    "BreakUpLargeNumbers must never receive abbreviation options")
Check(format:find("local opts = abbreviates and NUM_OPTS or nil", 1, true),
    "the compiled secret writer must gate the options on the short slot")

local groupDB = ReadSource("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
Check(groupDB:find("fn(val, useShort and _GF_NUM_OPTS or nil)", 1, true),
    "group frames lost the options argument on the secret path")
Check(groupDB:find("fn(n, useShort and _GF_NUM_OPTS or nil)", 1, true),
    "group frames lost the options argument on the non-secret path")

local defaults = ReadSource("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
Check(defaults:find('g.numberAbbrevStyle ~= "COMPACT"', 1, true),
    "the DB default for numberAbbrevStyle is gone")
Check(defaults:find('g.numberAbbrevStyle = "GAME"', 1, true),
    "numberAbbrevStyle must default to GAME so CJK clients keep their own abbreviations")

local misc = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua")
Check(misc:find('b:CollapsibleSection("misc_language"', 1, true),
    "the Misc language section id changed")
Check(misc:find('W.Segment(language, "Number abbreviation", ABBREV_STYLES', 1, true),
    "the Number abbreviation control left the Misc language section")
Check(misc:find('SetG("numberAbbrevStyle"', 1, true),
    "the Misc control no longer writes numberAbbrevStyle")

local profiles = ReadSource("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
Check(profiles:find('MSUF_ProfileIO_RunProtected("MSUF.NumberFormat.Refresh", numberFormat.Refresh)', 1, true),
    "profile switches must re-resolve the abbreviation style")

print("Number abbreviation style smoke passed ("
    .. #data .. " breakpoints, " .. #EXPECTED .. " formatted samples, 4 client variants, "
    .. "live text-engine round trip)")
