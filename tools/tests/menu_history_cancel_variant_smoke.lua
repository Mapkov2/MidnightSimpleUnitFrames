-- menu_history_cancel_variant_smoke.lua <repoRoot> <flavor>
--
-- MSUF Edit Mode "Cancel All" restores the history surface marker
-- (Bindings_History CancelHistorySurface). The marker holds the variant-free
-- base profile (ProfileVariants.BaseSnapshot). It must be put back the way
-- Undo does it: overlays stripped first, add-on roots restored and kept out
-- of MSUF_DB, overlays re-resolved after. A bare replace left the base values
-- live while the variant journal still called its overlay applied, so the
-- next capture (logout, the next edit or context change) wrote the base
-- values into the variant and it stopped doing anything (bh2 H-C7-01).
--
-- Boots the real core and Options graph of one client (client_world.lua).
-- Plain Lua 5.1, repo root as arg 1 and the client flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_history_cancel_variant_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor)
-- Harness gap only: every client defines MAX_BOSS_FRAMES = 5 in Blizzard_UnitFrame.
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local env, core = world.env, world.core
local M = Check(core.MSUF2, "Menu2 did not load")
local F = Check(core.ProfileFields, "ProfileFields did not load")
local V = Check(core.ProfileVariants, "ProfileVariants did not load")
Check(M.ApplyService, "apply service missing").Flush = function() return true end
-- An add-on profile root (the Suite's) travels in snapshots only.
local suiteStore = { smoke = 1 }
F.RegisterExternal("suiteModules", {
    Resolve = function() return suiteStore end,
    Restore = function(target, copy)
        for key in pairs(target) do target[key] = nil end
        for key, value in pairs(copy) do target[key] = value end
        return true
    end,
})

local db = Check(M.EnsureDB(), "profile DB missing")
env.MSUF_ActiveProfile = env.MSUF_ActiveProfile or "Default"
-- The full-profile apply a variant edit asks for is outside this contract.
core.ProfileRuntime.Apply = function() V.ResolveCurrent() end
local base = tonumber(db.player.offsetX) or 0
local overlay = base + 100
Check(V.Replace(db, { version = 1, entries = { { name = "Smoke", conditions = {},
    patch = { { path = { "player", "offsetX" }, value = overlay } } } } }), "the smoke variant was refused")
Check(db.player.offsetX == overlay, "the smoke variant overlay is not live")

-- Edit Mode entry, a drag, a Suite change, then Cancel All.
Check(M.StartHistorySession("edit_mode"), "the Edit Mode history session did not start")
Check(M.CaptureHistory("Move Player", "edit_mode:unit:player", function()
    db.player.offsetX = overlay + 50
    suiteStore.smoke = 2
    return true
end) == true, "the Edit Mode drag was refused")
Check(M.CancelHistorySurface("edit_mode", true) == true, "Cancel All did not restore the history surface")
db = M.EnsureDB()
Check(db.player.offsetX == overlay, "Cancel All left the base value " .. tostring(db.player.offsetX)
    .. " live instead of the active variant's " .. overlay)
Check(db.suiteModules == nil, "Cancel All wrote the snapshot-only add-on root into MSUF_DB")
Check(suiteStore.smoke == 1, "Cancel All did not restore the add-on profile root")
M.EndHistorySession("edit_mode")

-- Logout (PLAYER_LOGOUT runs Variants.Restore) captures live overlay edits.
V.Restore()
local patch = db.profileVariants.entries[1].patch[1]
Check(patch.value == overlay, "the variant's stored value became " .. tostring(patch.value) .. " after Cancel All")
Check(db.player.offsetX == base, "the base value became " .. tostring(db.player.offsetX))

print("menu_history_cancel_variant_smoke: " .. flavor .. " ok (Cancel All keeps the variant overlay and the add-on root)")
