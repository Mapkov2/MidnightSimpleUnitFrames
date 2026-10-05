-- menu_history_setter_only_smoke.lua <repoRoot> <flavor>
--
-- Some general settings act only through their setter: the MSUF frame scale
-- (Dashboard Apply calls MSUF_ApplyMsufScale), the minimap icon, the game
-- menu button, target sounds, version check, NSRT nicknames, the resource
-- ping, number abbreviation, the menu font and the external Edit Mode
-- integrations. No apply owner reads them again, so Undo, Redo, the guided
-- setup restore and "Reset Miscellaneous" put the saved value back while the
-- runtime kept the old state until /reload (bh2 H-C7-02). A restore or reset
-- now calls the setter of each such setting whose value changed, and only of
-- those: an unrelated undo step calls none of them.
--
-- Boots the real core and Options graph of one client (client_world.lua).
-- Plain Lua 5.1, repo root as arg 1 and the client flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_history_setter_only_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor)
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local env, core = world.env, world.core
local M = Check(core.MSUF2, "Menu2 did not load")
local F = Check(core.ProfileFields, "ProfileFields did not load")
Check(M.ApplyService, "apply service missing").Flush = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end

local db = Check(M.EnsureDB(), "profile DB missing")
local factory = Check(F.CopySnapshot(db), "booted profile is not snapshot-safe")
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end

-- The setters, recorded: each published one must exist on this client first.
local calls = {}
local function Record(name)
    Check(type(env[name]) == "function", name .. " is not published on this client")
    env[name] = function(...) calls[#calls + 1] = { name = name, value = (...) } end
end
for _, name in ipairs({ "MSUF_ApplyMsufScale", "MSUF_SetMinimapIconEnabled", "MSUF_SetGameMenuButtonEnabled",
    "MSUF_TargetSoundDriver_ApplySetting", "MSUF_RefreshPlayerResourcePing", "MSUF_ApplyModules",
    "MSUF_NSRTNicknames_ApplySetting", "MSUF_Grid2EditMode_SetEnabled", "MSUF_DetailsEditMode_SetEnabled",
    "MSUF_DominosEditMode_SetEnabled", "MSUF_DandersEditMode_SetEnabled" }) do Record(name) end
local numberRefreshes = 0
local refreshNumbers = core.NumberFormat.Refresh
core.NumberFormat.Refresh = function(...) numberRefreshes = numberRefreshes + 1; return refreshNumbers(...) end
-- The first argument of each call to one setter; nil arguments count as false.
local function Calls(name)
    local list = {}
    for i = 1, #calls do
        if calls[i].name == name then
            local value = calls[i].value
            if value == nil then value = false end
            list[#list + 1] = value
        end
    end
    return list
end
local function Begin()
    for i = #calls, 1, -1 do calls[i] = nil end
    numberRefreshes = 0
end

Check(M.StartHistorySession("menu"), "the menu history session did not start")
local g = db.general
g.msufUiScale, g.showMinimapIcon, g.grid2EditModeIntegration, g.numberAbbrevStyle = 1, true, true, "GAME"

-- A. Dashboard > Scaling > MSUF Frame Scale 150% > Apply, then Undo and Redo.
g.msufUiScale = 1.5
M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false, notify = false })
Begin()
Check(M.Undo(), "Undo of the frame scale was refused")
Check(M.EnsureDB().general.msufUiScale == 1, "Undo did not restore the saved frame scale")
local scale = Calls("MSUF_ApplyMsufScale")
Check(#scale == 1 and scale[1] == 1, "Undo left the MSUF frames at the undone scale")
Begin()
Check(M.Redo(), "Redo of the frame scale was refused")
scale = Calls("MSUF_ApplyMsufScale")
Check(#scale == 1 and scale[1] == 1.5, "Redo did not scale the MSUF frames again")

-- B. Miscellaneous toggles (source opt_misc:toggle:<label>), then Undo.
for _, row in ipairs({
    { "showMinimapIcon", false, "MSUF_SetMinimapIconEnabled", true },
    { "grid2EditModeIntegration", false, "MSUF_Grid2EditMode_SetEnabled", true },
}) do
    local key, value, setter, restored = row[1], row[2], row[3], row[4]
    M.CaptureHistory(key, "opt_misc:toggle:" .. key, function()
        M.EnsureDB().general[key] = value
        return true
    end)
    Begin()
    Check(M.Undo(), "Undo of " .. key .. " was refused")
    local list = Calls(setter)
    Check(#list == 1 and list[1] == restored, "Undo of " .. key .. " did not call " .. setter .. " with the restored value")
end
M.CaptureHistory("numberAbbrevStyle", "opt_misc:segment:numberAbbrevStyle", function()
    M.EnsureDB().general.numberAbbrevStyle = "COMPACT"
    return true
end)
Begin()
Check(M.Undo() and numberRefreshes == 1, "Undo of the number abbreviation did not refresh the number format")

-- C. An unrelated undo step calls none of the setter-only appliers.
M.CaptureHistory("Player width", "unit:player:width", function()
    local player = M.EnsureDB().player
    player.width = (tonumber(player.width) or 200) + 10
    return true
end)
Begin()
Check(M.Undo(), "Undo of the player width was refused")
Check(#calls == 0 and numberRefreshes == 0, "an unrelated undo called " .. tostring(calls[1] and calls[1].name or "the number format"))

-- D. Reset Miscellaneous with the minimap icon and target sounds changed.
db = M.EnsureDB()
db.general.showMinimapIcon = false
db.general.playTargetSelectLostSounds = not (factory.general.playTargetSelectLostSounds == true)
Begin()
Check(M.ResetPageToDefaults("opt_misc"), "Reset Miscellaneous failed")
local icon = Calls("MSUF_SetMinimapIconEnabled")
Check(#icon == 1 and icon[1] == (factory.general.showMinimapIcon ~= false), "Reset Miscellaneous left the minimap icon hidden")
Check(#Calls("MSUF_TargetSoundDriver_ApplySetting") == 1, "Reset Miscellaneous did not apply the target sounds")
Check(#Calls("MSUF_ApplyMsufScale") == 0 and #Calls("MSUF_Grid2EditMode_SetEnabled") == 0,
    "Reset Miscellaneous called a setter whose value did not change")

print("menu_history_setter_only_smoke: " .. flavor .. " ok (Undo, Redo and Reset Miscellaneous call the setter-only appliers"
    .. " that changed; an unrelated undo calls none)")
