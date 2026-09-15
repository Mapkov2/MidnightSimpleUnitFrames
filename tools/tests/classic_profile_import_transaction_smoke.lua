-- Profile import transaction smoke.
--
-- Runs once per client flavor and native codec mode through the aura test driver:
--   lua .github/scripts/auras3_test_driver.lua tools/tests/classic_profile_import_transaction_smoke.lua <Mainline|Vanilla|Mists|TBC> <raise|nil> <repo root>
--
-- Every import entry point (MSUF_ImportFromString, MSUF_ImportIntoNewProfile,
-- MSUF_ImportExternal and the Menu2 profiles page import controls) must decode,
-- validate and stage a string before it creates, switches or writes a profile.
-- A rejected string leaves MSUF_GlobalDB byte-identical. The C_EncodingUtil stubs
-- reject malformed input by returning nil in "nil" mode and by raising in "raise"
-- mode; a raise may surface as a Lua error, but never after a write.
local flavor = assert(arg[1], "client flavor required (Mainline|Vanilla|Mists|TBC)")
local codecMode = assert(arg[2], "codec mode required (raise|nil)")
local repo = assert(arg[3], "repository root is required")
assert(codecMode == "raise" or codecMode == "nil", "unknown codec mode: " .. tostring(codecMode))

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_MISTS_CLASSIC = 19

local specs = {
    Mainline = { project = WOW_PROJECT_MAINLINE, interface = 120105, classic = false },
    Vanilla = { project = WOW_PROJECT_CLASSIC, interface = 11509, tag = "Vanilla", classic = true },
    Mists = { project = WOW_PROJECT_MISTS_CLASSIC, interface = 50504, tag = "Mists", classic = true },
    TBC = { project = WOW_PROJECT_BURNING_CRUSADE_CLASSIC, interface = 20506, tag = "TBC", classic = true },
}
local spec = assert(specs[flavor], "unknown flavor: " .. tostring(flavor))
WOW_PROJECT_ID = spec.project

C_AddOns = {
    GetAddOnMetadata = function(_, key)
        if key == "X-MSUF-Client" then return spec.tag end
        return nil
    end,
}
function GetBuildInfo()
    return "test", "test", "test", spec.interface
end

issecretvalue = function() return false end
Enum = {
    EditModeSystem = { ActionBar = 0, CastBar = 1, Minimap = 2 },
    CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 },
    CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
}
function UnitName(unit)
    assert(unit == "player", "character key asked for a unit other than the player")
    return "Tester"
end
function GetRealmName()
    return "Realm"
end

local realPrint = print
local printed = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end
local function Check(condition, message)
    if not condition then
        error(flavor .. "/" .. codecMode .. ": " .. message
            .. " (last chat line: " .. tostring(printed[#printed] or "<nothing printed>") .. ")", 2)
    end
end

-- Deterministic value helpers --------------------------------------------------

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function Literal(value, depth)
    depth = depth or 0
    -- Deeper than the import depth limit (64) so a too-deep fixture can be encoded.
    assert(depth < 256, "value too deep for the literal serializer")
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "boolean" or kind == "nil" then return tostring(value) end
    if kind == "number" then
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            return string.format("%d", value)
        end
        return string.format("%.17g", value)
    end
    assert(kind == "table", "literal serializer cannot serialize " .. kind)
    local parts = {}
    for _, key in ipairs(SortedKeys(value)) do
        parts[#parts + 1] = "[" .. Literal(key, depth + 1) .. "]=" .. Literal(value[key], depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not DeepEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- RFC 4648 base64 (Lua 5.1 arithmetic, no bit library) --------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function EncodeBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function DecodeBase64(text)
    if type(text) ~= "string" or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local pad = select(2, chunk:gsub("=", ""))
        if pad > 2 or (pad > 0 and i + 3 < #text) or chunk:find("=[^=]") then return nil end
        local n = 0
        for j = 1, 4 do
            local ch = chunk:sub(j, j)
            local v = ch == "=" and 0 or B64_INDEX[ch]
            if v == nil then return nil end
            n = n * 64 + v
        end
        local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end

assert(EncodeBase64("foobar") == "Zm9vYmFy" and DecodeBase64("Zm8=") == "fo",
    "base64 stub does not follow RFC 4648 test vectors")

-- C_EncodingUtil stub: reversible for valid data; malformed input is rejected
-- with nil ("nil" mode) or a raised error ("raise" mode).
local NATIVE_REJECT = "native decoder rejected input"
local nativeRejects = 0
local function Reject()
    nativeRejects = nativeRejects + 1
    if codecMode == "raise" then error(NATIVE_REJECT, 2) end
    return nil
end
local EncodingUtil = {
    SerializeCBOR = function(value)
        return "CBOR" .. Literal(value)
    end,
    DeserializeCBOR = function(blob)
        if type(blob) ~= "string" or blob:sub(1, 4) ~= "CBOR" then return Reject() end
        local chunk = loadstring("return " .. blob:sub(5), "=cbor-stub")
        if not chunk then return Reject() end
        setfenv(chunk, {})
        local ok, value = pcall(chunk)
        if not ok or type(value) ~= "table" then return Reject() end
        return value
    end,
    CompressString = function(plain, method, level)
        assert(method == Enum.CompressionMethod.Deflate, "profile export did not request Deflate")
        assert(level == Enum.CompressionLevel.OptimizeForSize, "profile export did not request OptimizeForSize")
        return "Z" .. plain
    end,
    DecompressString = function(compressed, method)
        assert(method == Enum.CompressionMethod.Deflate, "profile import did not request Deflate")
        if type(compressed) ~= "string" or compressed:sub(1, 1) ~= "Z" then return Reject() end
        return compressed:sub(2)
    end,
    EncodeBase64 = EncodeBase64,
    DecodeBase64 = function(text)
        local data = DecodeBase64(text)
        if data == nil then return Reject() end
        return data
    end,
}
C_EncodingUtil = EncodingUtil

-- SavedVariables -----------------------------------------------------------------

local function NewSavedVariables()
    local default = { _msufProfileSchema = 600, general = { marker = "local" } }
    MSUF_GlobalDB = {
        profiles = {
            Default = default,
            Other = { _msufProfileSchema = 600, general = { marker = "other" } },
        },
        char = { ["Tester-Realm"] = { activeProfile = "Default" } },
        global = {},
    }
    MSUF_DB = default
    MSUF_ActiveProfile = "Default"
end
NewSavedVariables()

-- Load order (the shipped TOC graph selects every provider) ---------------------

local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local namespace = {}
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, flavor, namespace, providers)
Check(namespace.Client.Flavor == flavor, "client detection reported " .. tostring(namespace.Client.Flavor))

-- Stub: the Kernel bootstrap owns ExportPublic; this smoke loads no Kernel UI.
function namespace.ExportPublic(name, value)
    _G[name] = value
    namespace.Public = namespace.Public or {}
    namespace.Public[name] = value
    return value
end

manifest.LoadSelected(repo, flavor, namespace, {
    "State/MSUF_FirstLoad.lua",
    "Kernel/MSUF_Require.lua",
    "State/MSUF_StateHelpers.lua",
    "State/MSUF_ProfileCodec.lua",
})

-- Stub: State/MSUF_Defaults.lua owns MSUF_EnsureDB and the factory profile.
function MSUF_EnsureDB() end
function MSUF_CreateFactoryDefaultProfile()
    return { _msufProfileSchema = 600, general = { marker = "factory" } }
end
-- Stub: ProfileRuntime.Apply fans out to live frames. Count the calls by reason.
local applies = {}
namespace.ProfileRuntime = {
    Apply = function(reason)
        applies[reason] = (applies[reason] or 0) + 1
    end,
}
local function Applies(reason) return applies[reason] or 0 end
-- Stub: group-frame config cache owner (UnitFrames engine) is not loaded.
MSUF_GF_InvalidateConfCache = function() end

local profilesPath = repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"
local profilesChunk = assert(loadstring(MSUF_Auras3TestLoader.ReadSource(profilesPath), "@" .. profilesPath))
profilesChunk("MidnightSimpleUnitFrames", namespace)

Check(type(MSUF_ImportFromString) == "function", "MSUF_ImportFromString missing")
Check(type(MSUF_ImportExternal) == "function", "MSUF_ImportExternal missing")
Check(type(MSUF_ImportIntoNewProfile) == "function", "MSUF_ImportIntoNewProfile missing")
Check(namespace.Public.MSUF_Profiles_ImportIntoNewProfile == MSUF_ImportIntoNewProfile
    and namespace.MSUF_ImportIntoNewProfile == MSUF_ImportIntoNewProfile,
    "MSUF_ImportIntoNewProfile is not exported like its siblings")

-- Spies: profile create/switch and ReloadUI.
local counts = { create = 0, switch = 0, reload = 0 }
local realCreate, realSwitch = MSUF_CreateProfile, MSUF_SwitchProfile
local createImpl, switchImpl = realCreate, realSwitch
MSUF_CreateProfile = function(...)
    counts.create = counts.create + 1
    return createImpl(...)
end
MSUF_SwitchProfile = function(...)
    counts.switch = counts.switch + 1
    return switchImpl(...)
end
ReloadUI = function() counts.reload = counts.reload + 1 end

-- Menu2 profiles page harness ----------------------------------------------------

local function Noop() end
-- Capitalized keys are widget methods (no-ops); everything else stays nil.
local function Stub(fields)
    return setmetatable(fields or {}, {
        __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return Noop end
            return nil
        end,
    })
end
local colors = setmetatable({}, { __index = function() return { 0, 0, 0, 1 } end })
local T = Stub({ colors = colors, Panel = function() return Stub() end })
local W = Stub({
    SwitchAt = function() return Stub() end,
    Text = function() return Stub() end,
})
local M = {
    Widgets = W,
    Theme = T,
    AdvancedPage = { RegisterControl = Noop, ControlMeta = function() return {} end },
    Tr = function(text) return text end,
    Format = function(fmt, ...) return string.format(fmt, ...) end,
    RequestRefresh = Noop,
    ClearHistory = Noop,
    BlockCombatAction = function() return false end,
    RequestGeneralApply = Noop,
    TrackRefresh = Noop,
    RegisterPage = Noop,
}
CreateFrame = function() return Stub() end

local pagePath = repo .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua"
local pageSource = MSUF_Auras3TestLoader.ReadSource(pagePath)
Check(pageSource:find("function ProfilesPage.ImportActions(state)", 1, true) ~= nil,
    "profiles page no longer defines ProfilesPage.ImportActions(state)")
local pageChunk = assert(loadstring(pageSource .. "\nreturn ProfilesPage", "@" .. pagePath))
local ProfilesPage = pageChunk("MidnightSimpleUnitFrames_Options", { MSUF2 = M })

local blobText, nameText = "", "Fresh"
local importClick, committed
local state = {
    ctx = {}, io = Stub(), ioWide = false, stringCard = Stub(), actionsCard = Stub(),
    stringCardW = 600, actionsCardW = 400, ioButtonW = 160,
    exportKind = Stub(), exportKindW = 200,
    blob = Stub({ GetText = function() return blobText end }),
    export = Stub(),
    import = Stub({
        SetScript = function(_, event, fn)
            if event == "OnClick" then importClick = fn end
        end,
    }),
    importCreateNew = Stub(),
    importProfileName = Stub({
        GetText = function() return nameText end,
        SetText = function(_, value) nameText = value end,
        SetOnValueCommitted = function(_, fn) committed = fn end,
        HasFocus = function() return false end,
    }),
    importNameW = 200,
    ProfileButton = function() return Stub() end,
    PlaceActionRow = Noop,
    AddProfileTooltip = Noop,
}
ProfilesPage.ImportActions(state)
Check(type(importClick) == "function", "page import button OnClick was not captured")
Check(type(committed) == "function", "page new-profile name commit handler was not captured")

local function PageImport(text, createNew, viaCommit)
    blobText = text
    M.profileImportCreateNew = createNew
    if viaCommit then return committed(nameText) end
    return importClick()
end

-- Fixture strings ------------------------------------------------------------------

local function Lcg(seed, alphabet, length)
    local out, value = {}, seed
    for i = 1, length do
        value = (value * 69069 + 1) % 4294967296
        local index = math.floor(value / 65536) % #alphabet + 1
        out[i] = alphabet:sub(index, index)
    end
    return table.concat(out)
end

MSUF_DB.general.marker = "exported-all"
local fullExport = MSUF_ExportSelectionToString("all")
MSUF_DB.general.highlightColor = { 0.25, 0.5, 0.75 }
MSUF_DB.classColors = { WARRIOR = { r = 1, g = 0.5, b = 0 } }
local colorsExport = MSUF_ExportSelectionToString("colors")
local fullTable = MSUF_EncodeCompactTable({ _msufProfileSchema = 600, general = { marker = "full-table" } })
NewSavedVariables()
Check(type(fullExport) == "string" and fullExport:match("^MSUF[34]:") ~= nil, "full export is not compact")
Check(type(colorsExport) == "string" and colorsExport:match("^MSUF[34]:") ~= nil, "colors export is not compact")

local unpadded = fullExport:gsub("=+$", "")
local flipIndex = #"MSUF4:" + 1
local flipped = unpadded:sub(1, flipIndex - 1)
    .. (unpadded:sub(flipIndex, flipIndex) == "A" and "B" or "A") .. unpadded:sub(flipIndex + 1)

local failures = {
    { "empty", "" },
    { "whitespace", "   " },
    { "bare MSUF4 prefix", "MSUF4:" },
    { "MSUF4 invalid base64", "MSUF4:@@@@" },
    { "MSUF4 garbage", "MSUF4:" .. Lcg(7, B64, 96) },
    { "MSUF3 garbage", "MSUF3:" .. Lcg(11, B64, 96) },
    { "MSUF2 print garbage", "MSUF2:" .. Lcg(13, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()", 96) },
    { "truncated to 8", unpadded:sub(1, 8) },
    { "truncated to half", unpadded:sub(1, math.floor(#unpadded / 2)) },
    { "truncated by 1", unpadded:sub(1, #unpadded - 1) },
    { "truncated by 2", unpadded:sub(1, #unpadded - 2) },
    { "flipped base64 char", flipped },
    { "broken literal", "{ broken" },
    { "unterminated return", "return {" },
    { "schema 577 profile", MSUF_EncodeCompactTable({ _msufProfileSchema = 577, general = { marker = "old" } }),
        "MSUF 6.x profile required (schema 600)" },
    { "bogus snapshot kind", MSUF_EncodeCompactTable({
        addon = "MSUF", fmt = 2, schema = 600, kind = "bogus", payload = { general = { marker = "bogus" } },
    }), "unknown kind" },
}

-- Transaction checks -------------------------------------------------------------

local function Capture()
    return {
        sv = Literal(MSUF_GlobalDB),
        db = MSUF_DB,
        active = MSUF_ActiveProfile,
        create = counts.create,
        switch = counts.switch,
        reload = counts.reload,
        import = Applies("PROFILE_IMPORT"),
        external = Applies("PROFILE_EXTERNAL_IMPORT"),
        switchApply = Applies("PROFILE_SWITCH"),
    }
end

local function ExpectUntouched(label, before, allowSwitches)
    Check(Literal(MSUF_GlobalDB) == before.sv, label .. ": MSUF_GlobalDB changed")
    Check(rawequal(MSUF_DB, before.db), label .. ": MSUF_DB was replaced")
    Check(MSUF_ActiveProfile == before.active, label .. ": MSUF_ActiveProfile changed")
    Check(Applies("PROFILE_IMPORT") == before.import and Applies("PROFILE_EXTERNAL_IMPORT") == before.external,
        label .. ": import runtime apply ran")
    Check(counts.reload == before.reload, label .. ": ReloadUI ran")
    if not allowSwitches then
        Check(counts.create == before.create, label .. ": a profile was created")
        Check(counts.switch == before.switch and Applies("PROFILE_SWITCH") == before.switchApply,
            label .. ": a profile was switched")
    end
end

local raised = 0
local function RunFailure(label, fn, expectReason)
    local before = Capture()
    local ok, result, reason = pcall(fn)
    if not ok then
        Check(codecMode == "raise", label .. ": raised in nil mode: " .. tostring(result))
        Check(tostring(result):find(NATIVE_REJECT, 1, true) ~= nil,
            label .. ": raised something other than the native decoder: " .. tostring(result))
        raised = raised + 1
    else
        Check(result ~= true, label .. ": import reported success")
        if expectReason == true then
            Check(type(reason) == "string" and reason ~= "", label .. ": no rejection reason returned")
        elseif type(expectReason) == "string" then
            Check(reason == expectReason, label .. ": reason " .. tostring(reason) .. ", expected " .. expectReason)
        end
    end
    ExpectUntouched(label, before)
end

local entryPoints = {
    { "MSUF_ImportFromString", function(s) return MSUF_ImportFromString(s) end, true },
    { "MSUF_ImportIntoNewProfile", function(s) return MSUF_ImportIntoNewProfile("Fresh", s) end, true },
    { "MSUF_ImportExternal Default", function(s) return MSUF_ImportExternal(s, "Default") end, true },
    { "MSUF_ImportExternal Other", function(s) return MSUF_ImportExternal(s, "Other") end, true },
    { "MSUF_ImportExternal Brand New", function(s) return MSUF_ImportExternal(s, "Brand New") end, true },
    { "page import (current profile)", function(s) return PageImport(s, false) end, false },
    { "page import (new profile)", function(s) nameText = "Fresh"; return PageImport(s, true) end, false },
    { "page name commit (new profile)", function(s) nameText = "Fresh"; return PageImport(s, true, true) end, false },
}

-- (1) Every rejected string through every entry point.
for _, failure in ipairs(failures) do
    for _, entry in ipairs(entryPoints) do
        NewSavedVariables()
        local expect = entry[3]
        if expect and failure[3] and entry[1] == "MSUF_ImportFromString" then expect = failure[3] end
        RunFailure(failure[1] .. " via " .. entry[1], function() return entry[2](failure[2]) end, expect)
    end
end
if codecMode == "raise" then
    Check(raised > 0, "raise mode never raised from a native decoder")
else
    Check(raised == 0, "nil mode raised")
end
Check(nativeRejects > 0, "no failure case reached a native decoder")

-- (1b) Rejection texts are the pre-transaction strings: the chat line printed by
-- MSUF_ImportFromString and MSUF_ImportIntoNewProfile, the returned reason, and
-- MSUF_ImportExternal's reason strings.
local RED = "|cffff0000MSUF:|r "
local function Nested(depth)
    local root = {}
    local node = root
    for _ = 1, depth do node.child = {}; node = node.child end
    return root
end
local brokenLiteral = "{ broken"
local _, brokenWhy = namespace.ProfileIOParseTableLiteral(brokenLiteral)
Check(type(brokenWhy) == "string", "literal parser gave no reason for a broken literal")
local SCHEMA = "MSUF 6.x profile required (schema 600)"
local deepProfile = MSUF_EncodeCompactTable({ _msufProfileSchema = 600, general = { marker = "deep" }, deep = Nested(70) })
local deepSnapshot = MSUF_EncodeCompactTable({ addon = "MSUF", fmt = 2, schema = 600, kind = "colors",
    payload = { general = { marker = "deep" }, deep = Nested(70) } })
Check(type(deepProfile) == "string" and type(deepSnapshot) == "string", "deep fixtures did not encode")
local messageCases = {
    { "empty", "", RED .. "Import failed (empty string).", "empty string", "empty profileString" },
    { "schema 577", failures[15][2], RED .. "Import failed: " .. SCHEMA .. ".", SCHEMA, SCHEMA },
    { "unknown kind", failures[16][2], RED .. "Import failed: unknown kind", "unknown kind",
        "external import requires a full profile snapshot" },
    { "literal parse error", brokenLiteral, RED .. "Import failed: " .. brokenWhy, brokenWhy, "invalid lua table string" },
    { "literal not a table", "return 5", RED .. "Import failed: profile import must contain a table",
        "profile import must contain a table", "invalid lua table string" },
    { "full-profile validation", deepProfile, RED .. "Profile import failed: profile is too deep",
        "profile is too deep", "profile is too deep" },
    { "snapshot validation", deepSnapshot, RED .. "Import failed: profile is too deep",
        "profile is too deep", "external import requires a full profile snapshot" },
}
if codecMode == "nil" then
    messageCases[#messageCases + 1] = { "compact decode", "MSUF4:@@@@",
        RED .. "Import failed: could not decode compact profile string (MSUF4).",
        "could not decode compact profile string (MSUF4)", "could not decode compact profile string (MSUF4)" }
end
Check(failures[15][1] == "schema 577 profile" and failures[16][1] == "bogus snapshot kind", "failure fixture order changed")
for _, case in ipairs(messageCases) do
    for _, entry in ipairs({
        { "MSUF_ImportFromString", function() return MSUF_ImportFromString(case[2]) end },
        { "MSUF_ImportIntoNewProfile", function() return MSUF_ImportIntoNewProfile("Fresh", case[2]) end },
    }) do
        NewSavedVariables()
        local before = #printed
        local ok, why = entry[2]()
        Check(ok == false, case[1] .. " via " .. entry[1] .. ": import reported success")
        Check(why == case[4], case[1] .. " via " .. entry[1] .. ": reason " .. tostring(why) .. ", expected " .. case[4])
        Check(#printed == before + 1 and printed[#printed] == case[3],
            case[1] .. " via " .. entry[1] .. ": chat line " .. tostring(printed[#printed]) .. ", expected " .. case[3])
    end
    NewSavedVariables()
    local ok, why = MSUF_ImportExternal(case[2], "Other")
    Check(ok == false and why == case[5],
        case[1] .. " via MSUF_ImportExternal: reason " .. tostring(why) .. ", expected " .. case[5])
end

-- (2) Accepted strings through every entry point.
local function ExpectContent(label, profile, fixture)
    Check(type(profile) == "table", label .. ": profile missing")
    if fixture.kind == "colors" then
        Check(type(profile.classColors) == "table" and DeepEqual(profile.classColors.WARRIOR, { r = 1, g = 0.5, b = 0 }),
            label .. ": class colors were not imported")
        Check(DeepEqual(profile.general.highlightColor, { 0.25, 0.5, 0.75 }), label .. ": color key was not imported")
    else
        Check(profile.general.marker == fixture.marker, label .. ": marker is " .. tostring(profile.general.marker))
    end
end

local successes = {
    { label = "full export", text = fullExport, kind = "all", marker = "exported-all" },
    { label = "colors snapshot", text = colorsExport, kind = "colors" },
    { label = "full table", text = fullTable, kind = "table", marker = "full-table" },
}
for _, fixture in ipairs(successes) do
    local label = fixture.label

    NewSavedVariables()
    local active, before = MSUF_DB, Capture()
    Check(MSUF_ImportFromString(fixture.text) == true, label .. ": MSUF_ImportFromString failed")
    Check(rawequal(MSUF_DB, active), label .. ": current-profile import replaced MSUF_DB")
    Check(Applies("PROFILE_IMPORT") == before.import + 1, label .. ": current-profile import did not apply once")
    ExpectContent(label .. " (current)", MSUF_DB, fixture)

    NewSavedVariables()
    before = Capture()
    Check(MSUF_ImportIntoNewProfile("Fresh", fixture.text) == true, label .. ": MSUF_ImportIntoNewProfile failed")
    Check(counts.create == before.create + 1 and counts.switch == before.switch + 1,
        label .. ": new-profile import did not create and switch once")
    Check(Applies("PROFILE_IMPORT") == before.import + 1, label .. ": new-profile import did not apply once")
    Check(MSUF_ActiveProfile == "Fresh" and rawequal(MSUF_GlobalDB.profiles.Fresh, MSUF_DB),
        label .. ": new profile is not active")
    Check(MSUF_GlobalDB.profiles.Default.general.marker == "local", label .. ": new-profile import changed Default")
    ExpectContent(label .. " (new)", MSUF_DB, fixture)

    for _, key in ipairs({ "Default", "Other", "Brand New" }) do
        NewSavedVariables()
        before = Capture()
        local ok, why = MSUF_ImportExternal(fixture.text, key)
        if fixture.kind == "colors" then
            Check(ok == false and why == "external import requires a full profile snapshot",
                label .. ": external import of a category snapshot into " .. key .. " returned " .. tostring(why))
            ExpectUntouched(label .. " external " .. key, before)
        else
            Check(ok == true, label .. ": external import into " .. key .. " failed: " .. tostring(why))
            ExpectContent(label .. " (external " .. key .. ")", MSUF_GlobalDB.profiles[key], fixture)
            Check(MSUF_ActiveProfile == "Default", label .. ": external import switched profiles")
        end
    end

    NewSavedVariables()
    before = Capture()
    Check(PageImport(fixture.text, false) == true, label .. ": page current-profile import failed")
    Check(counts.reload == before.reload and Applies("PROFILE_IMPORT") == before.import + 1,
        label .. ": page current-profile import reloaded or did not apply once")
    ExpectContent(label .. " (page current)", MSUF_DB, fixture)

    NewSavedVariables()
    nameText = "Fresh"
    before = Capture()
    Check(PageImport(fixture.text, true) == true, label .. ": page new-profile import failed")
    Check(counts.create == before.create + 1 and counts.switch == before.switch + 1,
        label .. ": page new-profile import did not create and switch once")
    Check(Applies("PROFILE_IMPORT") == before.import + 1, label .. ": page new-profile import did not apply once")
    Check(counts.reload == before.reload + 1, label .. ": page new-profile import did not reload once")
    Check(MSUF_ActiveProfile == "Fresh" and nameText == "", label .. ": page new-profile import did not settle")
    ExpectContent(label .. " (page new)", MSUF_DB, fixture)
end

-- (3) Create and switch failures roll back to an identical MSUF_GlobalDB.
do
    NewSavedVariables()
    createImpl = function() return false, "stub create failure" end
    local before = Capture()
    local ok, why, stage = MSUF_ImportIntoNewProfile("Fresh", fullExport)
    Check(ok == false and stage == "create" and why == "could not create profile",
        "create failure returned " .. tostring(why) .. "/" .. tostring(stage))
    ExpectUntouched("create failure", before, true)
    nameText = "Fresh"
    before = Capture()
    Check(PageImport(fullExport, true) == false, "page create failure reported success")
    ExpectUntouched("page create failure", before, true)
    createImpl = realCreate
end
do
    NewSavedVariables()
    -- Settle the stored profile once, so the rollback switch back is a no-op
    -- for its normalization markers.
    realSwitch("Default")
    switchImpl = function(name, ...)
        if name == "Fresh" then return false, "stub switch failure" end
        return realSwitch(name, ...)
    end
    local before = Capture()
    local ok, why, stage = MSUF_ImportIntoNewProfile("Fresh", fullExport)
    Check(ok == false and stage == "switch" and why == "could not switch profile",
        "switch failure returned " .. tostring(why) .. "/" .. tostring(stage))
    ExpectUntouched("switch failure", before, true)
    nameText = "Fresh"
    before = Capture()
    Check(PageImport(fullExport, true) == false, "page switch failure reported success")
    ExpectUntouched("page switch failure", before, true)
    switchImpl = realSwitch
end

-- (4) Name and existence guards write nothing.
do
    NewSavedVariables()
    local before = Capture()
    local ok, _, stage = MSUF_ImportIntoNewProfile("   ", fullExport)
    Check(ok == false and stage == "name", "blank new-profile name was not rejected")
    ok, _, stage = MSUF_ImportIntoNewProfile("Other", fullExport)
    Check(ok == false and stage == "exists", "existing new-profile name was not rejected")
    ExpectUntouched("name guards", before)
end

print = realPrint
print("profile import transaction smoke passed: " .. flavor .. " " .. codecMode)
