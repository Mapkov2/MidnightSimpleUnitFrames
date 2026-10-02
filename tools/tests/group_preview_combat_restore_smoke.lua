-- group_preview_combat_restore_smoke.lua <repoRoot> <flavor>
--
-- While the options Group page shows a preview of a scope, the runtime retires
-- that scope's live secure header (Runtime PreviewSuppressesHeader). Combat is a
-- hard ownership boundary for previews: PLAYER_REGEN_DISABLED hides every one
-- (Preview.lua GF.HidePreviewsForCombat), but nothing handed the block back to
-- the live header. A group that formed while the preview was up therefore had
-- no frames for the whole fight, and after it until some later roster event.
-- REGEN_DISABLED fires before InCombatLockdown() is true, so the live header is
-- set up again right there.
-- Contract on the real load graph (SecureGroupHeader emulator): the live header
-- is shown and styled when lockdown begins, with no protected write in lockdown.
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

-- Blizzard constant the Additional-blocks preview reads (UnitFrame.lua); the
-- sandbox answers unknown globals with a stub table.
local h = Harness.New(root, flavor, { beforeBoot = function(harness) harness.env.MAX_BOSS_FRAMES = 5 end })
local GF, env = h.GF, h.env
GF.EnsureDB()
local party = GF.GetConf("party")
party.enabled, party.showPlayer, party.showSolo = true, true, false
GF.RefreshHeaderLayout()
h:RunTimers()

-- The Group page opens a preview while the player is solo (no live frames).
env.MSUF2_GFPagePreviewActive = true
Check(GF.ShowPreview("party", 5) ~= false and GF._previewActive.party == true, "the party preview did not open")

-- A party forms while the preview is up: the runtime keeps the header retired.
h:SetRoster({ "player", "party1", "party2" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local header = GF.headers.party
Check(header == nil or not header.shown, "the preview no longer suppresses the live header (fixture premise)")

-- Combat starts with the menu still open.
h:EnterCombat()
h:RunTimers()
Check(GF._previewActive.party ~= true, "combat did not hide the preview")
header = GF.headers.party
Check(header ~= nil and header.shown == true, "the live party header stayed retired into the fight")
for index, child in ipairs(h:Children(header)) do
    if child.attributes.unit then
        Check(child.MSUFSpec ~= nil and GF.frames[child] == true, "live child " .. index .. " is not styled in combat")
    end
end
Check(#h.violations == 0, "protected write in lockdown:\n" .. tostring(h.violations[1]))
h:LeaveCombat()
env.MSUF2_GFPagePreviewActive = nil

print(string.format("group_preview_combat_restore_smoke: ok (%s: live header back at REGEN_DISABLED)", flavor))
