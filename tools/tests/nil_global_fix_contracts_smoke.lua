-- nil_global_fix_contracts_smoke.lua <repoRoot>
--
-- Seven shipped code paths read a name that no file defines. Lua 5.1 answers nil
-- for such a read, so each one either raised the first time its line ran or, worse,
-- quietly turned a branch off for good. tools/tests/unresolved_global_reads_smoke.py
-- now fails on the reads themselves; this smoke pins what the fixed code does,
-- because a read can be "resolved" by any name and still route somewhere wrong.
--
--   Group Highlights   BuildFailClosedResult indexed a nil constant, so the
--                      fail-closed branch raised "table index is nil" instead of
--                      closing. Section 1 makes the curated list fail its own
--                      count check and requires a nonempty, zero-count result.
--   Geometry router    OM.RootDetailBlocked compared against an empty extracted
--                      phrase list, so it never blocked. Section 2 restores the
--                      rule it had until the phrase extraction: a frame-root
--                      offset row is out when the sentence names a detail its own
--                      label does not.
--   Class resource     ParseClassResourceFillFastShortcut read DetectDirection as
--                      a global, so "left"/"right"/"up"/"down" never chose an
--                      axis. Section 3 routes each direction.
--   Assistant apply    ApplyCastbar read the apply service as a global, so its
--                      fast path was dead and every castbar change took the
--                      global-call fallback. Section 4 pins the service route.
--   Color picker       The Advanced card's HEX input got a nil commit handler,
--                      so Enter did nothing. Section 5 pins the shared handler
--                      and both inputs that carry it.
--   Class resource     Preview.NudgeHandle, the Assistant's nudge entry point,
--   preview            called a nil StoreForHandle and raised. Section 6 pins the
--                      exported store reader and the preview's binding of it.
--   Font registry      MSUF_GetFontPreviewObject called SetFontChecked, which is
--                      published as MSUF_SetFontChecked. Section 7 pins the call.
--
-- Run with plain Lua 5.1 and the repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local CORE = root .. "/MidnightSimpleUnitFrames/"
local OPTIONS = root .. "/MidnightSimpleUnitFrames_Options/"
local ASSISTANT = root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

--- Compiles one sliced function with an explicit prologue that binds every name
--- it closes over, so the slice runs as itself instead of against globals.
local function Compile(prologue, body, ret, name)
    local chunk = assert(loadstring(prologue .. "\n" .. body .. "\nreturn " .. ret, "@" .. name))
    return chunk
end

---------------------------------------------------------------------------
-- 1. Auras3 Group Highlights: the fail-closed guard must close, not raise.
---------------------------------------------------------------------------
local highlightsPath = CORE .. "Auras3/MSUF_Auras3_GroupHighlightsData.lua"
local highlightsSource = Slice.Read(highlightsPath)

local function LoadHighlights(source, label)
    local ns = {}
    local chunk = assert(loadstring(source, "@MSUF_Auras3_GroupHighlightsData.lua"), label)
    chunk("MidnightSimpleUnitFrames", ns)
    local A3 = ns.MSUF_Auras3
    Check(type(A3) == "table" and type(A3.GetGroupHighlightsSpellIDHash) == "function",
        label .. ": the group highlights data file published no hash reader")
    return A3
end

local healthy = LoadHighlights(highlightsSource, "pristine")
local hash, signature, count = healthy.GetGroupHighlightsSpellIDHash()
Check(type(hash) == "table" and count == healthy.GroupHighlightsDataCount and count > 0,
    "the curated group highlights list no longer answers its own count: " .. tostring(count))
Check(signature:find(tostring(count), 1, true) ~= nil,
    "the healthy signature must name the count it published: " .. tostring(signature))

-- Force the guard: the curated list keeps every ID, the expected count does not
-- match it any more. This is exactly the state BuildFailClosedResult exists for.
local brokenSource, replaced = highlightsSource:gsub("local EXPECTED_COUNT = (%d+)",
    function(value) return "local EXPECTED_COUNT = " .. (tonumber(value) + 1) end, 1)
Check(replaced == 1, "MSUF_Auras3_GroupHighlightsData.lua no longer declares EXPECTED_COUNT")
local broken = LoadHighlights(brokenSource, "count mismatch")
local ok, failHash, failSignature, failCount = pcall(broken.GetGroupHighlightsSpellIDHash)
Check(ok, "the fail-closed guard raised instead of closing: " .. tostring(failHash))
Check(type(failHash) == "table", "the fail-closed guard returned no hash")
Check(next(failHash) ~= nil,
    "the fail-closed hash must stay nonempty so a generic normalizer cannot reduce it to nil")
for key in pairs(failHash) do
    Check(type(key) == "number" and key < 0,
        "the fail-closed hash key " .. tostring(key) .. " could match a real aura spell ID")
end
Check(failCount == 0, "the fail-closed count must be 0, was " .. tostring(failCount))
Check(tostring(failSignature):find("invalid", 1, true) ~= nil,
    "the fail-closed signature must say invalid: " .. tostring(failSignature))

---------------------------------------------------------------------------
-- 2. Geometry router: a frame-root offset row is out when the sentence names a
--    detail the row's own label does not.
---------------------------------------------------------------------------
local geometryPath = ASSISTANT .. "MSUF_AssistantParser_Geometry.lua"
local geometrySource = Slice.Read(geometryPath)
-- Trim and Normalize stand in for the parser core's own pair: this section only
-- needs lowercasing and whitespace folding, which is all OM.Clean asks of them.
local geometryPrologue = [[
local OM = { cleanCache = {}, cleanCacheOrder = {} }
local function Trim(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function Normalize(text) return (tostring(text or ""):lower():gsub("%s+", " ")) end
local function HasPhrase(text, phrase)
    text, phrase = Normalize(text), Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end
]]
local RootDetailBlocked = Compile(geometryPrologue,
    Slice.Function(geometrySource, "function OM.Clean", geometryPath) .. "\n"
        .. Slice.Function(geometrySource, "function OM.RootDetailBlocked", geometryPath),
    "OM.RootDetailBlocked", "OM.RootDetailBlocked")()

local GEOMETRY_CASES = {
    -- attribute, label, sentence, blocked
    { "offsetX", "X Offset", "move the player name 5 to the left", true },
    { "offsetX", "Name X Offset", "move the player name 5 to the left", false },
    { "offsetY", "Y Offset", "move the target health text down 3", true },
    { "offsetY", "Health Text Y Offset", "move the target health text down 3", false },
    { "offsetX", "X Offset", "move the player frame 5 to the left", false },
    -- Only frame-root offsets are judged; every other attribute is none of its business.
    { "width", "Width", "make the player name wider", false },
}
for _, case in ipairs(GEOMETRY_CASES) do
    local blocked = RootDetailBlocked({ attribute = case[1], label = case[2] }, case[3])
    Check(blocked == case[4], "RootDetailBlocked(" .. case[1] .. "/" .. case[2] .. ", \"" .. case[3]
        .. "\") answered " .. tostring(blocked) .. ", expected " .. tostring(case[4]))
end
-- The extracted phrase row the guard used to read is gone, not merely unused.
local geometryData = {}
assert(loadfile(ASSISTANT .. "MSUF_AssistantParser_Geometry_Data.lua"))(
    "MidnightSimpleUnitFrames_Assistant", geometryData)
local phrases = geometryData.Assistant.ParserData.GEOMETRY_PARSER.PHRASES
Check(phrases[37] == nil,
    "GeometryPhrases[37] is back; it held a variable name the extractor inlined, never a phrase")

---------------------------------------------------------------------------
-- 3. Class resource fill shortcut: a named direction chooses the axis.
---------------------------------------------------------------------------
local parserPath = ASSISTANT .. "MSUF_AssistantParser.lua"
local parserSource = Slice.Read(parserPath)
local rootData = {}
assert(loadfile(ASSISTANT .. "MSUF_AssistantParser_Data.lua"))(
    "MidnightSimpleUnitFrames_Assistant", rootData)
local settings = {
    ["bars.classPowerOffsetX"] = { key = "bars.classPowerOffsetX", label = "X Offset" },
    ["bars.classPowerOffsetY"] = { key = "bars.classPowerOffsetY", label = "Y Offset" },
    ["bars.classPowerFrameLevelOffset"] = { key = "bars.classPowerFrameLevelOffset", label = "Layer" },
}
local parserPrologue = [[
local function HasPhrase(text, phrase)
    return (" " .. tostring(text):lower() .. " "):find(" " .. tostring(phrase):lower() .. " ", 1, true) ~= nil
end
local function ContainsAny(text, words)
    for i = 1, #(words or {}) do if HasPhrase(text, words[i]) then return true end end
    return false
end
local function FirstNumber(text) return tonumber(tostring(text):match("%-?%d+")) end
local P = { RootPhrases = PHRASES, DetectDirection = function(text)
    ASKED[#ASKED + 1] = text
    return DIRECTION
end }
local A = { Registry = { GetSetting = function(_, key) return SETTINGS[key] end } }
]]
local shortcutChunk = Compile("local PHRASES, SETTINGS, DIRECTION, ASKED = ...\n" .. parserPrologue,
    Slice.Function(parserSource, "local function ParseClassResourceFillFastShortcut", parserPath),
    "ParseClassResourceFillFastShortcut", "ParseClassResourceFillFastShortcut")
local rootPhrases = rootData.Assistant.ParserData.ROOT_PARSER.PHRASES
local function Shortcut(direction, text)
    local asked = {}
    local parse = shortcutChunk(rootPhrases, settings, direction, asked)
    return parse(text), asked
end

local DIRECTION_CASES = {
    { "left", "bars.classPowerOffsetX" },
    { "right", "bars.classPowerOffsetX" },
    { "up", "bars.classPowerOffsetY" },
    { "down", "bars.classPowerOffsetY" },
}
for _, case in ipairs(DIRECTION_CASES) do
    local text = "move the class resource bar 10 " .. case[1]
    local plan, asked = Shortcut(case[1], text)
    Check(#asked > 0, "the class resource shortcut never asked P.DetectDirection for \"" .. text .. "\"")
    Check(type(plan) == "table" and plan.changes and plan.changes[1]
        and plan.changes[1].setting.key == case[2],
        "\"" .. text .. "\" routed to "
            .. tostring(plan and plan.changes and plan.changes[1] and plan.changes[1].setting.key)
            .. ", expected " .. case[2])
end
-- The explicit phrases keep working with no direction at all.
local explicit = Shortcut(nil, "move the class resource x offset to 10")
Check(type(explicit) == "table" and explicit.changes[1].setting.key == "bars.classPowerOffsetX",
    "an explicit axis phrase must still route without a direction word")

---------------------------------------------------------------------------
-- 4. Assistant castbar apply: the apply service is read per call.
---------------------------------------------------------------------------
local domainsPath = ASSISTANT .. "MSUF_AssistantRegistry_Core_Apply_Domains.lua"
local domainsSource = Slice.Read(domainsPath)
local serviceCalls, globalCalls = {}, {}
local applyPrologue = [[
local function CurrentApplyService() return SERVICE end
local function CallGlobal(name) GLOBALS[#GLOBALS + 1] = name; return false end
local function ApplyGeneral() GLOBALS[#GLOBALS + 1] = "ApplyGeneral"; return true end
]]
local applyChunk = Compile("local GLOBALS, SERVICE = ...\n" .. applyPrologue,
    Slice.Function(domainsSource, "local function ApplyCastbar", domainsPath),
    "ApplyCastbar", "ApplyCastbar")
local ApplyCastbar = applyChunk(globalCalls, {
    RequestCastbars = function(reason, source, unit)
        serviceCalls[#serviceCalls + 1] = tostring(reason) .. "/" .. tostring(source) .. "/" .. tostring(unit)
        return true
    end,
})
ApplyCastbar("MSUF_TEST", "target")
Check(#serviceCalls == 1 and serviceCalls[1] == "MSUF_TEST/assistant/target",
    "the castbar apply must take the service route, called " .. table.concat(serviceCalls, ", "))
Check(#globalCalls == 0, "the service route must not also run the global fallback: "
    .. table.concat(globalCalls, ", "))

-- Without a service the fallback still runs, so the fix added a route, not a gate.
serviceCalls, globalCalls = {}, {}
local Fallback = applyChunk(globalCalls, nil)
Fallback("MSUF_TEST", "target")
Check(#globalCalls > 0, "without an apply service the castbar apply must still call the globals")

---------------------------------------------------------------------------
-- 5. Context color picker: one HEX commit handler, both inputs.
---------------------------------------------------------------------------
local pickerPath = OPTIONS .. "Shell/Menu2/MSUF_Menu2_ContextColorPicker.lua"
local pickerSource = Slice.Read(pickerPath):gsub("\r\n", "\n")
local pickerPrologue = [[
local function FromHex(text)
    local r, g, b = tostring(text):match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end
]]
local HexCommitter = Compile(pickerPrologue,
    Slice.Function(pickerSource, "local function HexCommitter", pickerPath),
    "HexCommitter", "HexCommitter")()
local applied, refreshed = {}, 0
local panel = {
    Apply = function(_, r, g, b) applied[#applied + 1] = string.format("%.2f,%.2f,%.2f", r, g, b) end,
    Refresh = function() refreshed = refreshed + 1 end,
}
local commit = HexCommitter(panel)
Check(type(commit) == "function", "HexCommitter must return the input's commit handler")
commit({ GetText = function() return "#20C040" end })
Check(#applied == 1 and applied[1] == "0.13,0.75,0.25",
    "a valid HEX must be applied, applied " .. table.concat(applied, " "))
commit({ GetText = function() return "not a color" end })
Check(#applied == 1 and refreshed == 1, "an invalid HEX must repaint the panel, not apply anything")
for _, assignment in ipairs({ "local CommitHex = HexCommitter(panel)", "hex._commit = HexCommitter(panel)" }) do
    Check(pickerSource:find(assignment, 1, true) ~= nil,
        "MSUF_Menu2_ContextColorPicker.lua no longer wires " .. assignment
            .. "; the Advanced card's HEX input silently did nothing while it read a nil upvalue")
end

---------------------------------------------------------------------------
-- 6. Class resource preview: the handle's store reader is exported and bound.
---------------------------------------------------------------------------
local interactionNS = { MSUF2 = {
    ClassPowerStackPreview = { RequestRefresh = function() end },
    EnsureDB = function() return { player = { tag = "player" }, bars = { tag = "bars" } } end,
} }
assert(loadfile(OPTIONS .. "Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview_Interaction.lua"))(
    "MidnightSimpleUnitFrames_Options", interactionNS)
local Interaction = interactionNS.MSUF2.ClassPowerPreviewInteraction
Check(type(Interaction) == "table" and type(Interaction.Store) == "function",
    "the class resource preview interaction module exports no handle store reader")
Check(Interaction.Store({ _store = "player" }).tag == "player"
    and Interaction.Store({ _store = "bars" }).tag == "bars"
    and Interaction.Store(nil) == nil,
    "the exported store reader does not answer the handle's own store")
local previewSource = Slice.Read(OPTIONS .. "Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua")
    :gsub("\r\n", "\n")
Check(previewSource:find("local StoreForHandle = Interaction.Store", 1, true) ~= nil,
    "MSUF_Menu2_ClassPowerPreview.lua must bind StoreForHandle from the interaction module; "
        .. "it used to read a nil global and Preview.NudgeHandle raised on every call")
Check(previewSource:find("local store = StoreForHandle(handle)", 1, true) ~= nil,
    "Preview.NudgeHandle no longer reads the handle's store before it moves anything")

---------------------------------------------------------------------------
-- 7. Font registry: the preview font object uses the published helper.
---------------------------------------------------------------------------
local registrySource = Slice.Read(CORE .. "Runtime/MSUF_FontRegistry.lua"):gsub("\r\n", "\n")
Check(registrySource:find("G.MSUF_SetFontChecked(obj, path, 14, \"\")", 1, true) ~= nil,
    "MSUF_FontRegistry.lua must call the published MSUF_SetFontChecked; a bare SetFontChecked "
        .. "is defined nowhere and raised on every font preview object")

print("nil_global_fix_contracts_smoke: ok (7 sections, "
    .. #GEOMETRY_CASES .. " geometry cases, " .. #DIRECTION_CASES .. " direction cases)")
