-- build_imports.lua -- writes the profile-string fixtures of the old-profile
-- regression corpus (tools/fixtures/profiles/imports/*.txt).
--
--   lua tools/fixtures/profiles/build_imports.lua <repo root>
--
-- Three groups (provenance in tools/fixtures/profiles/README.md):
--   hist_*  genuine strings the addon shipped, read from this repository's
--           history with `git show <commit>:<path>`;
--   base_*  strings of the 6.50 baseline (a97896f5): the three embedded
--           factory strings and exports the baseline exporter wrote from the
--           anonymized fixture sv/sv_xptr_rev15.lua, one per export kind;
--   synth_* the older transport variants the importer still reads, built from
--           a base_* string: LibDeflate print-safe MSUF2, uncompressed MSUF3,
--           the plain-text table literal, and a pre-6 profile.
-- Once written the files are frozen inputs: the corpus never regenerates them.
--
-- Plain Lua 5.1. Development tool only; the gate never runs it.

local root = assert(arg[1], "usage: build_imports.lua <repo root>"):gsub("\\", "/"):gsub("/$", "")
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local Emulator = assert(loadfile(root .. "/tools/tests/encoding_util_emulator.lua"))()
local OUT = root .. "/tools/fixtures/profiles/imports/"

-- One string a file, wrapped at 120 characters with CRLF (the corpus reads the
-- file without its line breaks; no string here contains one).
local function Write(name, text)
    assert(not text:find("[\r\n]"), name .. " contains a line break")
    local lines = {}
    for first = 1, #text, 120 do lines[#lines + 1] = text:sub(first, first + 119) end
    local handle = assert(io.open(OUT .. name .. ".txt", "wb"))
    handle:write(table.concat(lines, "\r\n"), "\r\n")
    handle:close()
    print(string.format("  %-44s %7d chars", name, #text))
end

local function GitShow(revision, path)
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. revision .. ":" .. path))
    local text = pipe:read("*a")
    pipe:close()
    assert(#text > 0, "git show " .. revision .. ":" .. path .. " returned nothing")
    return text
end

-- The index-th compact string literal of a file; "[[...]] .. [[...]]" pieces
-- of one literal are joined.
local function CompactLiteral(text, index)
    local joined = text:gsub("%]%]%s*%)?%s*%.%.%s*%(?%s*%[%[", "")
    local found = 0
    for literal in joined:gmatch("%[%[(MSUF[234]:[^%]]+)%]%]") do
        found = found + 1
        if found == index then return (literal:gsub("%s+", "")) end
    end
    error("no compact literal #" .. index)
end

---------------------------------------------------------------------------
-- Genuine strings from the history and the baseline
---------------------------------------------------------------------------
local HISTORY = {
    { "hist_2026-01-18_msuf2_preset", "22225cf81", "MSUF_Presets.lua", 1 },
    { "hist_2026-05-04_msuf3_corrupt", "9eae6d59f", "MidnightSimpleUnitFrames/Foundation/MSUF_Defaults.lua", 1 },
    { "hist_2026-05-27_msuf3_portable", "7a13b8437", "MidnightSimpleUnitFrames/Foundation/MSUF_Defaults.lua", 1 },
    { "hist_2026-07-14_msuf3_raw_profile", "d9786ae5a", "MidnightSimpleUnitFrames/State/MSUF_Defaults.lua", 1 },
    { "hist_2026-08-06_msuf3_full_schema1", "157c8c53a", "MidnightSimpleUnitFrames/State/MSUF_Defaults.lua", 1 },
    { "hist_2026-08-15_classic_factory", "3413e0a8f", "MidnightSimpleUnitFrames/Game/Classic/State/MSUF_Defaults.lua", 1 },
    { "base_factory", "a97896f5", "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua", 1 },
    { "base_forever_factory", "a97896f5", "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_ForeverFactory.lua", 1 },
    { "base_modern_dark", "a97896f5", "MidnightSimpleUnitFrames_Options/State/MSUF_Defaults_ModernDark.lua", 1 },
}
-- Some shipped factory strings (two July ones the corpus leaves out) carry
-- retired Assistant data whose greeting names the character that exported
-- them. The importer drops that data (payload.assistant); a string that has it
-- would shrink it to three leaves, get a placeholder name and be encoded
-- again. A string without it stays byte for byte as it shipped.
local api = Emulator.New()
local function KeepFirstLeaves(value, budget)
    if type(value) ~= "table" then return value, budget - 1 end
    local out = {}
    for _, key in ipairs(Corpus.SortedKeys(value)) do
        if budget <= 0 then break end
        out[key], budget = KeepFirstLeaves(value[key], budget)
    end
    return out, budget
end
local function Anonymized(text)
    local prefix, b64 = text:match("^(MSUF%d):(.*)$")
    local blob = api.DecodeBase64(b64)
    local plain = blob and api.DecompressString(blob, Emulator.CompressionMethod.Deflate)
    if not plain then return text end
    local snapshot = api.DeserializeCBOR(plain)
    local changed = false
    local function Clean(payload)
        if type(payload) ~= "table" or type(payload.assistant) ~= "table" then return end
        local function Rename(value)
            if type(value) == "string" then
                return (value:gsub("^(Good %a+, )[^%.]+(%. I am ready to help with MSUF%.)$", "%1Char01%2"))
            end
            if type(value) ~= "table" then return value end
            local out = {}
            for key, inner in pairs(value) do out[key] = Rename(inner) end
            return out
        end
        payload.assistant = (KeepFirstLeaves(Rename(payload.assistant), 3))
        changed = true
    end
    Clean(snapshot.payload)
    Clean(type(snapshot.msuf6) == "table" and snapshot.msuf6.payload or nil)
    if not changed then return text end
    return prefix .. ":" .. api.EncodeBase64(api.CompressString(api.SerializeCBOR(snapshot),
        Emulator.CompressionMethod.Deflate))
end
for _, item in ipairs(HISTORY) do
    Write(item[1], Anonymized(CompactLiteral(GitShow(item[2], item[3]), item[4])))
end

---------------------------------------------------------------------------
-- Baseline exports, one per kind, from an anonymized stored profile
---------------------------------------------------------------------------
local world = Corpus.NewWorld(root, "Mainline", "Char01-Realm01")
Corpus.Login(world, Corpus.LoadSavedVariablesFixture(root, "tools/fixtures/profiles/sv/sv_xptr_rev15.lua"))
local env = world.env
assert(env.MSUF_ActiveProfile == "Profile01", "the export source profile did not bind")
local exports = {}
for _, kind in ipairs({ "unitframe", "castbar", "colors", "gameplay", "groupframe" }) do
    exports[kind] = assert(env.MSUF_ExportSelectionToString(kind), kind .. " export failed")
    Write("base_msuf4_" .. kind, exports[kind])
end
exports.unitselection = assert(env.MSUF_ExportSelectionToString("unitselection", { player = true, target = true }))
Write("base_msuf4_unitselection", exports.unitselection)

---------------------------------------------------------------------------
-- Older transports, rebuilt from a baseline export
---------------------------------------------------------------------------
local function DecodeCompact(text)
    local blob = assert(api.DecodeBase64(text:match("^MSUF%d:(.*)$")))
    return assert(api.DecompressString(blob, Emulator.CompressionMethod.Deflate))
end

-- LibDeflate:EncodeForPrint, the Wago/WeakAuras print-safe alphabet (6 bits a
-- character, least significant first).
local PRINT = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()"
local function EncodeForPrint(bytes)
    local out, accumulator, bits = {}, 0, 0
    for index = 1, #bytes do
        accumulator = accumulator + bytes:byte(index) * 2 ^ bits
        bits = bits + 8
        while bits >= 6 do
            local sextet = accumulator % 64
            out[#out + 1] = PRINT:sub(sextet + 1, sextet + 1)
            accumulator = (accumulator - sextet) / 64
            bits = bits - 6
        end
    end
    if bits > 0 then out[#out + 1] = PRINT:sub(accumulator + 1, accumulator + 1) end
    return table.concat(out)
end
Write("synth_msuf2_printsafe_castbar", "MSUF2:" .. EncodeForPrint(api.CompressString(DecodeCompact(exports.castbar),
    Emulator.CompressionMethod.Deflate)))
Write("synth_msuf3_uncompressed_colors", "MSUF3:" .. api.EncodeBase64(DecodeCompact(exports.colors)))

-- The text export: a plain Lua table literal (State/MSUF_ProfileCodec.lua parses it).
local function Literal(value)
    if type(value) ~= "table" then return Corpus.FormatScalar(value) end
    local parts = {}
    for _, key in ipairs(Corpus.SortedKeys(value)) do
        local name = type(key) == "string" and key:match("^[%a_][%w_]*$") and key or "[" .. Corpus.FormatScalar(key) .. "]"
        parts[#parts + 1] = name .. "=" .. Literal(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
Write("synth_text_gameplay", Literal(api.DeserializeCBOR(DecodeCompact(exports.gameplay))))

-- A pre-6 profile (no schema stamp) as a compact string: the importer refuses it.
local pre6 = Corpus.LoadSavedVariablesFixture(root, "tools/fixtures/profiles/sv/sv_pre6_feb.lua")
Write("synth_msuf3_pre6_profile", "MSUF3:" .. api.EncodeBase64(api.CompressString(
    api.SerializeCBOR(pre6.MSUF_GlobalDB.profiles.Default), Emulator.CompressionMethod.Deflate)))
