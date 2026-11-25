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
local first, surname, realm = "Mapko", "Main", "Realm"
UnitName = function() return first, surname end
GetRealmName = function() return realm end
GetLocale = function() return "enUS" end
InCombatLockdown = function() return false end
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
realm = ""
ns.RegisterLocaleLoader("deDE", function() end)
Check(ns.FinalizeLocale() == "deDE", "locale lookup lost the old realm-qualified binding")
realm = "Realm"
store.char[altKey] = { activeProfile = "Default" }
name = ns.ResolveStartupProfile(store, main, altKey)
Check(name == "Default", "returning alt did not retain its own binding")
Check(store.char["Mapko-Realm"].activeProfile == "Main", "legacy binding was discarded")
store.global.defaultProfileForNewChars = "Main"
name = ns.ResolveStartupProfile(store, main, "Mapko Newalt-Realm")
Check(name == "Main", "explicit global alt preference stopped working")
-- 6.5x stored "Mapko-Realm" for every surname. A character without a binding
-- of its own starts on that profile once; its own binding always wins.
surname = "Main"
Check(ns.GetLegacyCharacterProfileKey() == "Mapko-Realm", "6.5x key differs from the 6.5x key format")
local upgraded = { profiles = { Main = main, Default = default }, global = {},
    char = { ["Mapko-Realm"] = { activeProfile = "Main" } } }
name, profile = ns.ResolveStartupProfile(upgraded, nil, altKey, "Mapko-Realm")
Check(name == "Main" and profile == main, "6.5x binding was ignored on the first 7.0 login")
upgraded.char[altKey] = { activeProfile = "Default" }
name = ns.ResolveStartupProfile(upgraded, nil, altKey, "Mapko-Realm")
Check(name == "Default", "6.5x binding replaced the character's own binding")
first, surname = "Mapko Merged", nil
Check(Key() == "Mapko Merged-Realm", "already merged names changed")
Check(ns.GetLegacyCharacterProfileKey() == nil, "a name without surname reported a separate 6.5x key")
local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Copy(child) end
    return copy
end
CopyTable = Copy
assert(loadfile(product .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileBinding.lua"))("MidnightSimpleUnitFrames", ns)
local Adopt = ns.ProfileBinding.AdoptLegacyCharacter
first, surname, realm = "Mapko", "Main", ""
local old = { activeProfile = "Main", specAutoSwitch = true, specProfileMap = { [62] = "Arcane" } }
local other = { activeProfile = "Default" }
local current = Key()
local saved = { char = { [mainKey] = old, [altKey] = other, ["Mapko-Realm"] = other } }
Check(current == "Mapko Main-" and Adopt(saved, current), "missing realm lost the full-name binding")
local adopted = saved.char[current]
Check(adopted.activeProfile == "Main" and adopted.specAutoSwitch and adopted.specProfileMap[62] == "Arcane",
    "migration lost active profile or specialization assignments")
Check(saved.char[mainKey] == old and adopted ~= old and adopted.specProfileMap ~= old.specProfileMap,
    "migration removed or aliased the older binding")
adopted.activeProfile = "Default"
Check(not Adopt(saved, current) and adopted.activeProfile == "Default", "migration replaced a current binding")
saved.char[current], saved.char["Mapko Main-OtherRealm"], saved.char["Mapko-"] = nil, other, old
Check(not Adopt(saved, current) and saved.char[current] == nil, "migration guessed between realms")
saved = { char = { ["Mapko-Realm"] = old, [altKey] = other } }
Check(not Adopt(saved, current) and saved.char[current] == nil, "realm-free migration guessed from a qualified first name")
saved.char["Mapko-"] = old
Check(Adopt(saved, current) and saved.char[current].specProfileMap[62] == "Arcane",
    "the exact 6.5x key written with an empty realm lost its specialization binding")
realm = "Realm"
Check(Adopt(saved, mainKey) and saved.char[mainKey].activeProfile == "Main", "known realm lost its 6.5x binding")
realm = ""
first, surname = "Solo", nil
saved = { char = { ["Solo-Realm"] = old } }
Check(Adopt(saved, Key()) and saved.char[Key()].activeProfile == "Main", "surname-free character lost its realm binding")
first, surname, realm = "Mapko Merged", nil, "Realm"
local secret = {}
issecretvalue = function(value) return value == secret end
surname = secret
Check(Key() == nil, "secret surname became a profile key")
ns.Client.HasCharacterSurnames = false
first, surname = "Tester", "ForeignRealm"
Check(Key() == "Tester-Realm", "ordinary client treated realm as surname")
Check(ns.GetLegacyCharacterProfileKey() == nil, "ordinary client reported a separate 6.5x key")
surname = secret
Check(Key() == "Tester-Realm", "unused secret realm return blocked ordinary identity")
GetRealmName = function() return nil end
Check(Key() == "Tester-", "missing realm changed ordinary key semantics")
print("Forever profile identity: " .. checks .. " focused checks passed")
