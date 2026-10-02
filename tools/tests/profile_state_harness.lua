-- profile_state_harness.lua -- the real profile pipeline without frames.
--
-- Loads the State files of one client's core TOC in TOC order (Initialize,
-- FirstLoad, Require, StateHelpers, ProfileCodec, the Defaults, ProfileFields,
-- ProfileNormalize, Profiles) into plain globals, with the live runtime apply
-- stubbed, and initializes a fresh profile store. Imports, exports, EnsureDB
-- and every migration run for real.
--
--   local Harness = dofile(root .. "/tools/tests/profile_state_harness.lua")
--   local h = Harness.Load(root, "Mainline")
--   h.Import("all", payload)            -- a plain-text snapshot import
--   h.Export("unitframe")                -- the snapshot table an export encodes
--
-- Plain Lua 5.1. Globals are reset on every Load.

local Harness = {}

local function Literal(value)
    local kind = type(value)
    if kind == "number" then return string.format("%.17g", value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "string" then return string.format("%q", value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        local name = type(key) == "string" and string.format("[%q]", key) or "[" .. Literal(key) .. "]"
        parts[#parts + 1] = name .. "=" .. Literal(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
Harness.Literal = Literal

function Harness.Load(root, flavor)
    local classic = flavor ~= "Mainline"
    WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
    WOW_PROJECT_ID = ({ Mainline = 1, Vanilla = 2, TBC = 5, Mists = 19 })[flavor]
    C_AddOns = { GetAddOnMetadata = function(_, field)
        if field == "X-MSUF-Client" and classic then return flavor end
    end }
    local interface = ({ Mainline = 120105, Vanilla = 11509, TBC = 20506, Mists = 50504 })[flavor]
    GetBuildInfo = function() return "test", "test", "test", interface end
    issecretvalue = function() return false end
    Enum = { CompressionMethod = { Deflate = 0 }, CompressionLevel = { Default = 0, OptimizeForSize = 2 } }
    GetLocale = function() return "enUS" end
    UnitClass = function() return "Hunter", "HUNTER" end
    UnitName = function() return "Tester" end
    GetRealmName = function() return "Realm" end
    InCombatLockdown = function() return false end
    CopyTable = function(source)
        local out = {}
        for key, value in pairs(source) do out[key] = type(value) == "table" and CopyTable(value) or value end
        return out
    end
    PowerBarColor = {}

    local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    local ns = {}
    local providers = { "Game/Shared/Initialize.lua" }
    if classic then providers[2] = "Game/Classic/Initialize.lua" end
    manifest.LoadSelected(root, flavor, ns, providers)
    function ns.ExportPublic(name, value) _G[name] = value; ns[name] = value; return value end
    _G.MSUF_NS, _G.MSUF = ns, ns
    manifest.LoadSelected(root, flavor, ns, {
        "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "State/MSUF_StateHelpers.lua",
        "State/MSUF_ProfileCodec.lua", "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua",
        "State/Defaults/MSUF_Defaults_Bars.lua", "State/Defaults/MSUF_Defaults_Units.lua", "State/MSUF_Defaults.lua",
        "State/MSUF_ProfileFields.lua",
    })
    ns.ProfileRuntime = { Apply = function() end, BeforeMutation = function() end }
    MSUF_GF_InvalidateConfCache = function() end
    MSUF_NormalizeFontKey = function(key) return key end
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileNormalize.lua"))("MidnightSimpleUnitFrames", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", ns)

    MSUF_DB, MSUF_GlobalDB, MSUF_ActiveProfile = nil, nil, nil
    local realPrint = print
    print = function() end
    MSUF_InitProfiles()
    print = realPrint

    local h = { ns = ns, flavor = flavor }
    -- A plain-text snapshot import; returns ok, why.
    function h.Import(kind, payload, profileName)
        local quiet = print
        print = function() end
        local ok, why = MSUF_ImportFromString(Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = kind,
            profile = profileName or "Friend", payload = payload }))
        print = quiet
        return ok, why
    end
    -- The snapshot table an export of `kind` hands the encoder.
    function h.Export(kind)
        local captured
        C_EncodingUtil = {
            SerializeCBOR = function(value) captured = value; return "cbor" end,
            CompressString = function(text) return text end,
            EncodeBase64 = function(text) return text end,
        }
        local text = MSUF_ExportSelectionToString(kind)
        C_EncodingUtil = nil
        if type(text) ~= "string" then return nil end
        return captured and (captured.payload and captured or captured.snapshot) or nil
    end
    return h
end

return Harness
