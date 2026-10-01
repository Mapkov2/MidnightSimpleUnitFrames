-- Loading the defaults never writes into Blizzard's PowerBarColor (review F12:
-- the defaults recoloured Blizzard's own rune and soul shard bars and tainted
-- entries Blizzard code reads). MSUF's own rune and soul shard defaults come
-- from MSUF_GetDefaultPowerColor and the resolver's MSUF table instead. The
-- defaults also publish no generic global EnsureDB any more (any addon may own
-- that name); MSUF code calls MSUF_EnsureDB.
-- Usage: lua tools/tests/defaults_powerbarcolor_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
WOW_PROJECT_ID = 1
C_AddOns = { GetAddOnMetadata = function() return nil end }
function GetBuildInfo() return "test", "test", "test", 120100 end
issecretvalue = function() return false end
Enum = { CompressionMethod = { Deflate = 0 }, CompressionLevel = { Default = 0 } }
function GetLocale() return "enUS" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
function CopyTable(source)
    local out = {}
    for key, value in pairs(source) do out[key] = type(value) == "table" and CopyTable(value) or value end
    return out
end
local runes, shards, mana = { r = 0.5, g = 0.5, b = 0.5 }, { r = 0.5, g = 0.32, b = 0.55 }, { r = 0, g = 0, b = 1 }
local written = {}
local function Guard(name, entry)
    return setmetatable({}, {
        __index = entry,
        __newindex = function(_, key) written[#written + 1] = name .. "." .. tostring(key) end,
    })
end
PowerBarColor = setmetatable({ RUNES = Guard("RUNES", runes), SOUL_SHARDS = Guard("SOUL_SHARDS", shards), MANA = Guard("MANA", mana) },
    { __newindex = function(_, key) written[#written + 1] = tostring(key) end })
print = function() end

local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local ns = {}
manifest.LoadSelected(repo, "Mainline", ns, { "Game/Shared/Initialize.lua" })
function ns.ExportPublic(name, value) _G[name] = value; ns[name] = value; return value end
_G.MSUF_NS, _G.MSUF = ns, ns
manifest.LoadSelected(repo, "Mainline", ns, {
    "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "State/MSUF_StateHelpers.lua", "State/MSUF_ProfileCodec.lua",
    "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua", "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua", "State/MSUF_Defaults.lua",
})
assert(#written == 0, "loading the defaults wrote into PowerBarColor: " .. table.concat(written, ", "))
local r, g, b = MSUF_GetDefaultPowerColor("RUNES")
assert(math.abs(r - 128 / 255) < 1e-9 and g == 0 and math.abs(b - 17 / 255) < 1e-9, "MSUF's rune default is gone")
r, g, b = MSUF_GetDefaultPowerColor("SOUL_SHARDS")
assert(math.abs(r - 135 / 255) < 1e-9 and math.abs(g - 136 / 255) < 1e-9 and math.abs(b - 238 / 255) < 1e-9,
    "MSUF's soul shard default is gone")
r, g, b = MSUF_GetDefaultPowerColor("MANA")
assert(r == 0 and g == 0 and b == 1, "a token MSUF does not own lost Blizzard's default")
assert(ns._PBCSnap and ns._PBCSnap.RUNES, "the power color resolver lost MSUF's resource defaults")
assert(rawget(_G, "EnsureDB") == nil, "the defaults published the generic global EnsureDB")
assert(type(MSUF_EnsureDB) == "function", "MSUF_EnsureDB is not published")
io.write("defaults_powerbarcolor_smoke: OK\n")
