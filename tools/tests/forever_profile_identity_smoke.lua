-- Profile ownership and locale donors must distinguish Forever surnames.
local root = assert(arg[1], "repository root required")
local product = arg[2] or root
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local first, surname = "Mapko", "Main"
UnitName = function() return first, surname end
GetRealmName = function() return "Realm" end
GetLocale = function() return "enUS" end
issecretvalue = function() return false end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
local ns = { Client = { HasCharacterSurnames = true }, PublicGlobals = {} }
ns.ExportPublic = function(name, value) ns.PublicGlobals[name] = value end
assert(loadfile(product .. "/MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))("MidnightSimpleUnitFrames", ns)
-- Run the real character-key entry point without the unrelated runtime graph.
local profiles = Read(product .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
local method = assert(profiles:match("function MSUF%.PublicGlobals%.MSUF_GetCharKey%(%).-\nend"))
assert(loadstring("local MSUF = ...\n" .. method))(ns)
local Key = ns.PublicGlobals.MSUF_GetCharKey
local mainKey = Key()
surname = "Alt"
local altKey = Key()
Check(mainKey ~= altKey, "different surnames share a profile binding")
Check(mainKey == "Mapko Main-Realm" and altKey == "Mapko Alt-Realm", "full-name identity differs from native naming")
local main = { general = { menuLocale = "deDE" } }
local default = { general = { menuLocale = "enUS" } }
local store = { profiles = { Main = main, Default = default }, global = {}, char = {
    ["Mapko-Realm"] = { activeProfile = "Main" }, [mainKey] = { activeProfile = "Main" } } }
local name, profile = ns.ResolveStartupProfile(store, main, altKey)
Check(name == "Default" and profile == default, "alt inherited the main or ambiguous old binding")
name, profile = ns.ResolveStartupProfile(store, main, mainKey)
Check(name == "Main" and profile == main, "main lost its own full-name binding")
MSUF_GlobalDB = store
surname = "Main"
ns.RegisterLocaleLoader("deDE", function() end)
Check(ns.FinalizeLocale() == "deDE", "locale lookup used another character binding")
store.char[altKey] = { activeProfile = "Default" }
name = ns.ResolveStartupProfile(store, main, altKey)
Check(name == "Default", "returning alt did not retain its own binding")
Check(store.char["Mapko-Realm"].activeProfile == "Main", "legacy binding was discarded")
store.global.defaultProfileForNewChars = "Main"
name = ns.ResolveStartupProfile(store, main, "Mapko Newalt-Realm")
Check(name == "Main", "explicit global alt preference stopped working")
first, surname = "Mapko Merged", nil
Check(Key() == "Mapko Merged-Realm", "already merged names changed")
local secret = {}
issecretvalue = function(value) return value == secret end
surname = secret
Check(Key() == nil, "secret surname became a profile key")
ns.Client.HasCharacterSurnames = false
first, surname = "Tester", "ForeignRealm"
Check(Key() == "Tester-Realm", "ordinary client treated realm as surname")
surname = secret
Check(Key() == "Tester-Realm", "unused secret realm return blocked ordinary identity")
GetRealmName = function() return nil end
Check(Key() == "Tester-", "missing realm changed ordinary key semantics")
print("Forever profile identity: " .. checks .. " focused checks passed")
