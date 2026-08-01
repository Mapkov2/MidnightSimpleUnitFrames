--- Runtime/MSUF_NumberFormat.lua
--- Global number-abbreviation style for every MSUF text surface.
---
--- Blizzard's AbbreviateNumbers/AbbreviateLargeNumbers take their breakpoints
--- and abbreviation letters from the client locale. That inserts a space on
--- some locales ("123 K"), uses longer words on others, and changes where the
--- decimal appears. The COMPACT style hands the C abbreviator an explicit
--- breakpoint set instead, so the output is locale-independent, never carries a
--- space, and stays at four glyphs (dot excluded).
---
--- GAME stays the default on purpose: CJK abbreviations are deliberately very
--- different from the western ones and must not be overwritten unasked.
---
--- Perf contract: the options table is built once per style change on the cold
--- path and pushed into every consumer as an upvalue. The hot path stays a
--- single direct C call with one extra, constant argument - no table
--- allocation, no DB read, no pcall, no branch per formatted number. Secret
--- values are unaffected: options are argument 2 of the same C function, so
--- formatting never moves to the Lua side.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local NF = MSUF.NumberFormat or {}
MSUF.NumberFormat = NF

local STYLE_GAME = "GAME"
local STYLE_COMPACT = "COMPACT"
NF.STYLE_GAME = STYLE_GAME
NF.STYLE_COMPACT = STYLE_COMPACT

--- Locale-independent breakpoints, ordered largest to smallest as the API
--- requires. Each named order gets three rows so the significand stays at three
--- digits: 1.23M / 12.3M / 123M. There is deliberately no 1e3 row - a raw
--- "1234" is already four glyphs, so abbreviating it would only lose precision.
--- abbreviationIsGlobal = false keeps the raw letter instead of resolving a
--- localized global string.
local COMPACT_BREAKPOINTS = {
    { breakpoint = 1e14, abbreviation = "T", significandDivisor = 1e12, fractionDivisor = 1,   abbreviationIsGlobal = false },
    { breakpoint = 1e13, abbreviation = "T", significandDivisor = 1e11, fractionDivisor = 10,  abbreviationIsGlobal = false },
    { breakpoint = 1e12, abbreviation = "T", significandDivisor = 1e10, fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1e11, abbreviation = "B", significandDivisor = 1e9,  fractionDivisor = 1,   abbreviationIsGlobal = false },
    { breakpoint = 1e10, abbreviation = "B", significandDivisor = 1e8,  fractionDivisor = 10,  abbreviationIsGlobal = false },
    { breakpoint = 1e9,  abbreviation = "B", significandDivisor = 1e7,  fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1e8,  abbreviation = "M", significandDivisor = 1e6,  fractionDivisor = 1,   abbreviationIsGlobal = false },
    { breakpoint = 1e7,  abbreviation = "M", significandDivisor = 1e5,  fractionDivisor = 10,  abbreviationIsGlobal = false },
    { breakpoint = 1e6,  abbreviation = "M", significandDivisor = 1e4,  fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1e5,  abbreviation = "K", significandDivisor = 1000, fractionDivisor = 1,   abbreviationIsGlobal = false },
    { breakpoint = 1e4,  abbreviation = "K", significandDivisor = 100,  fractionDivisor = 10,  abbreviationIsGlobal = false },
}
NF.COMPACT_BREAKPOINTS = COMPACT_BREAKPOINTS

--- The locale field only decides whether the client mixes in its own asian
--- abbreviation data and how it rounds when fractionDivisor > 0. Pinning enUS
--- is the whole point of the COMPACT style.
local COMPACT_LOCALE = "enUS"

--- Sample used to prove the client actually honors our options before any frame
--- text depends on them. 12345 must come out as "12.3K": three significant
--- digits, one letter, no whitespace.
local PROBE_VALUE = 12345

local sinks = NF.sinks or {}
NF.sinks = sinks

local activeStyle = STYLE_GAME
local activeOptions = nil --- nil means "let the client decide" (GAME)
local compactOptions = nil
local compactChecked = false

local type = type
local pcall = pcall
local tostring = tostring

local function Abbreviator()
    local fn = _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers or _G.ShortenNumber
    return type(fn) == "function" and fn or nil
end

--- One real call decides: a candidate only wins after it produced a space-free
--- string for the probe value. Runs once per style change and is cached.
local function Accepts(fn, options)
    local ok, text = pcall(fn, PROBE_VALUE, options)
    if not ok then return false end
    if type(text) ~= "string" or text == "" then return false end
    if text:find("%s") then return false end
    return true
end

--- Builds the COMPACT options once. Only the raw breakpointData form is used:
--- it is validated purely by the value the formatter returns, unlike
--- CreateAbbreviateConfig, which hard-errors behind a restricted-breakpoints
--- precondition and was dropped for that reason. The options table is built
--- once and cached, so the config object's caching advantage is moot.
local function CompactOptions()
    if compactChecked then return compactOptions end
    compactChecked = true
    local fn = Abbreviator()
    if not fn then return nil end
    local candidates = {
        { breakpointData = COMPACT_BREAKPOINTS, locale = COMPACT_LOCALE },
        { breakpointData = COMPACT_BREAKPOINTS },
    }
    for i = 1, #candidates do
        if Accepts(fn, candidates[i]) then
            compactOptions = candidates[i]
            return compactOptions
        end
    end
    return nil
end

--- True when the running client accepts custom abbreviation data at all. Used
--- by the menu to keep a dead control out of the UI.
function NF.IsCompactSupported()
    return CompactOptions() ~= nil
end

function NF.NormalizeStyle(style)
    return style == STYLE_COMPACT and STYLE_COMPACT or STYLE_GAME
end

function NF.GetStyle()
    return activeStyle
end

function NF.GetOptions()
    return activeOptions
end

local function StyleFromDB()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    if type(general) ~= "table" then return STYLE_GAME end
    return general.numberAbbrevStyle == STYLE_COMPACT and STYLE_COMPACT or STYLE_GAME
end

--- Re-reads the style (or takes an explicit one) and pushes the resulting
--- options into every consumer. Cold path only: menu writes, profile switches
--- and login.
function NF.Refresh(style)
    style = NF.NormalizeStyle(style ~= nil and style or StyleFromDB())
    local options = nil
    if style == STYLE_COMPACT then
        options = CompactOptions()
        if options == nil then style = STYLE_GAME end
    end
    activeStyle = style
    if options == activeOptions then return activeStyle end
    activeOptions = options
    for i = 1, #sinks do
        sinks[i](activeOptions)
    end
    return activeStyle
end

--- Consumers register the setter that writes their local upvalue and get the
--- current options immediately, so load order between this module and its
--- consumers does not matter.
function NF.Register(sink)
    if type(sink) ~= "function" then return end
    sinks[#sinks + 1] = sink
    sink(activeOptions)
end

--- Cold-path formatter for menu previews: formats with an explicit style
--- without touching the active one.
function NF.FormatWith(value, style)
    local fn = Abbreviator()
    if not fn then return tostring(value) end
    local options = nil
    if NF.NormalizeStyle(style) == STYLE_COMPACT then
        options = CompactOptions()
    end
    -- Options here either passed the Accepts() probe or are nil (GAME style),
    -- so the C call cannot reject them.
    local text = fn(value, options)
    if type(text) == "string" and text ~= "" then return text end
    return tostring(value)
end

if MSUF.ExportPublic then
    MSUF.ExportPublic("MSUF_NumberFormat", NF)
else
    _G.MSUF_NumberFormat = NF
end

--- SavedVariables are not readable while this file executes, so the first
--- resolve waits for login. Everything before that runs on GAME, which is also
--- the default.
local loginFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if loginFrame then
    loginFrame:RegisterEvent("PLAYER_LOGIN")
    loginFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        NF.Refresh()
    end)
end
