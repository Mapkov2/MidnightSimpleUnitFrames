local localeRegistrations = 0
local root = {
    LOCALE = "enUS",
    RegisterLocale = function(locale)
        localeRegistrations = localeRegistrations + 1
        return { MSUF2_SEARCH_TEST = locale .. " translation" }
    end,
    MSUF2 = { SearchData = {} },
}
local M = root.MSUF2

function M.PickDefaults()
    return {}, {
        ["\195\169"] = "e",
    }, {
        "\226\128\148",
    }
end

assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Text.lua"))(
    "MidnightSimpleUnitFrames", root)

local normalize = assert(M.Search and M.Search.Text and M.Search.Text.NormalizeSearchText,
    "search normalization helper missing")
local oldGsub = string.gsub
local gsubCalls = 0
string.gsub = function(...)
    gsubCalls = gsubCalls + 1
    return oldGsub(...)
end

local input = "|cff40ff40Arger / Test|r"
local first = normalize(input)
local callsAfterFirst = gsubCalls
local second = normalize(input)

assert(first == "arger test", "search normalization behavior changed")
assert(second == first, "cached search normalization changed its result")
assert(callsAfterFirst > 0 and gsubCalls == callsAfterFirst,
    "repeated search normalization did not use the hotpath cache")

local longInput = string.rep("Unique long search haystack ", 12)
normalize(longInput)
local callsAfterLong = gsubCalls
normalize(longInput)
assert(gsubCalls > callsAfterLong,
    "one-shot long haystack polluted the bounded normalization cache")

assert(normalize("ASCII / PUNCTUATION") == "ascii punctuation",
    "ASCII normalization fastpath changed search text")
assert(normalize("|cff40ff40\195\132rger\226\128\148caf\195\169 \240\159\152\128|r") == "aerger cafe",
    "UTF normalization fastpath changed folded or punctuated search text")

local display = assert(M.Search.Text.DisplaySearchText, "search display helper missing")
local displayInput = "|cff40ff40  Visible\nLabel  |r"
local firstDisplay = display(displayInput)
local callsAfterFirstDisplay = gsubCalls
local secondDisplay = display(displayInput)
assert(firstDisplay == "Visible Label" and secondDisplay == firstDisplay,
    "search display cache changed visible text")
assert(gsubCalls == callsAfterFirstDisplay,
    "repeated search display formatting did not use the hotpath cache")

local longDisplayInput = string.rep("Unique visible label ", 16)
display(longDisplayInput)
local callsAfterLongDisplay = gsubCalls
display(longDisplayInput)
assert(gsubCalls > callsAfterLongDisplay,
    "one-shot long display text polluted the bounded cache")
string.gsub = oldGsub

assert(M.Search.Text.IsSearchLocaleKey("MSUF2_SEARCH_TEST") == true
        and M.Search.Text.IsSearchLocaleKey("XMSUF2_SEARCH_TEST") == false,
    "search locale-key prefix fastpath changed matching behavior")

local addSearchText = assert(M.Search.Text.AddSearchText, "search text collector missing")
local firstParts, secondParts = {}, {}
addSearchText(firstParts, "MSUF2_SEARCH_TEST")
addSearchText(secondParts, "MSUF2_SEARCH_TEST")
assert(#firstParts == 1 and firstParts[1] == "enUS translation"
        and #secondParts == 1 and secondParts[1] == firstParts[1],
    "reusable search-text deduplication state leaked across calls")

local translations = M.Search.Text.SearchLocaleTranslations
local firstLocale = translations("MSUF2_SEARCH_TEST")
local secondLocale = translations("MSUF2_SEARCH_TEST")
assert(firstLocale[1] == "enUS translation" and secondLocale == firstLocale,
    "locale translation cache changed the visible translation")
assert(localeRegistrations == 1, "locale translation cache repeated registry work")
root.LOCALE = "deDE"
M.Search.Text.ClearLocaleCaches()
local changedLocale = translations("MSUF2_SEARCH_TEST")
assert(changedLocale[1] == "deDE translation" and localeRegistrations == 2,
    "locale cache clear did not preserve locale-change behavior")

local variantParts, variantSeen = {}, {}
M.Search.Text.AddSearchTextVariants(variantParts, variantSeen, "|cff40ff40  Raw\nLabel  |r")
assert(#variantParts == 1 and variantParts[1] == "Raw Label",
    "search text variants lost raw display cleanup")

io.write("menu2_search_normalization_cache_smoke: ok\n")
