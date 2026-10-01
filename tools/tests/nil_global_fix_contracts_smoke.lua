-- nil_global_fix_contracts_smoke.lua <repoRoot>
--
-- Four shipped code paths read a name that no file defines. Lua 5.1 answers nil
-- for such a read, so each one either raised the first time its line ran or, worse,
-- quietly turned a branch off for good. tools/tests/unresolved_global_reads_smoke.py
-- now fails on the reads themselves; this smoke pins what the fixed code does,
-- because a read can be "resolved" by any name and still route somewhere wrong.
--
--   Group Highlights   BuildFailClosedResult indexed a nil constant, so the
--                      fail-closed branch raised "table index is nil" instead of
--                      closing. Section 1 makes the curated list fail its own
--                      count check and requires a nonempty, zero-count result.
--   Color picker       The Advanced card's HEX input got a nil commit handler,
--                      so Enter did nothing. Section 2 pins the shared handler
--                      and both inputs that carry it.
--   Font registry      MSUF_GetFontPreviewObject called SetFontChecked, which is
--                      published as MSUF_SetFontChecked. Section 4 pins the call.
--
-- Run with plain Lua 5.1 and the repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local CORE = root .. "/MidnightSimpleUnitFrames/"
local OPTIONS = root .. "/MidnightSimpleUnitFrames_Options/"

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
-- 2. Context color picker: one HEX commit handler, both inputs.
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
-- 3. Class resource preview: the handle's store reader is exported and bound.
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
Check(previewSource:find("local ReadHandle = Interaction.Read", 1, true) ~= nil,
    "Class Resources preview must bind its offset reader from the interaction module")
Check(Interaction.Write == nil and Interaction.Apply == nil,
    "the display-only preview must not publish its retired movement writers")

---------------------------------------------------------------------------
-- 4. Font registry: the preview font object uses the published helper.
---------------------------------------------------------------------------
local registrySource = Slice.Read(CORE .. "Runtime/MSUF_FontRegistry.lua"):gsub("\r\n", "\n")
Check(registrySource:find("G.MSUF_SetFontChecked(obj, path, 14, \"\")", 1, true) ~= nil,
    "MSUF_FontRegistry.lua must call the published MSUF_SetFontChecked; a bare SetFontChecked "
        .. "is defined nowhere and raised on every font preview object")

print("nil_global_fix_contracts_smoke: ok (4 core sections)")
