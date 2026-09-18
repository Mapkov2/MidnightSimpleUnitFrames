-- Forever SavedVariables bind after ADDON_LOADED.
--
--   lua tools/tests/forever_savedvariables_bind_smoke.lua <repo root>
--
-- Forever can execute addon Lua before SavedVariables exist. FirstLoad must
-- not create empty MSUF_GlobalDB in that window. When ADDON_LOADED fires with
-- the restored tables, bind once from those roots.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local watcher
function CreateFrame()
    watcher = {}
    function watcher:RegisterEvent() end
    function watcher:UnregisterEvent() end
    function watcher:UnregisterAllEvents() end
    function watcher:SetScript(_, fn)
        watcher._OnEvent = fn
    end
    return watcher
end

local ns = {
    Client = { IsRetail = true, IsForever = true, Family = "Mainline", Flavor = "Mainline" },
    Compat = {},
    Public = {},
}
ns.ExportPublic = function(name, value)
    _G[name] = value
    ns[name] = value
    return value
end
_G.MSUF_NS = ns
_G.MSUF = ns
_G.MSUF_DB = nil
_G.MSUF_GlobalDB = nil

assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", ns)

Check(_G.MSUF_GlobalDB == nil, "FirstLoad created MSUF_GlobalDB before SavedVariables existed")
Check(_G.MSUF_DB == nil, "FirstLoad created MSUF_DB before SavedVariables existed")
Check(ns.FirstLoad6.savedVariablesBound ~= true, "FirstLoad bound before SavedVariables existed")
Check(type(watcher) == "table" and type(watcher._OnEvent) == "function",
    "FirstLoad did not wait for ADDON_LOADED")

local saved = {
    _msufProfileSchema = 600,
    general = { marker = "restored" },
    player = { enabled = true },
}
_G.MSUF_GlobalDB = {
    profiles = { Custom = saved },
    char = { ["Tester-Realm"] = { activeProfile = "Custom" } },
    global = {},
}
_G.MSUF_DB = saved
watcher:_OnEvent("ADDON_LOADED", "MidnightSimpleUnitFrames")

Check(ns.FirstLoad6.savedVariablesBound == true, "ADDON_LOADED did not bind restored SavedVariables")
Check(_G.MSUF_GlobalDB.profiles.Custom == saved, "restored Custom profile was replaced")
Check(_G.MSUF_GlobalDB.profiles.Custom.general.marker == "restored", "restored profile contents were lost")
print("PASS Forever SavedVariables bind: empty globals wait for ADDON_LOADED restore")
