local root = assert(arg[1])
local mw = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open(root, arg[2] or "Mainline", { page = "home" })
local M = mw.M
assert(M.OpenSeeNewFeatures())
mw:RunTimers()
local frames, entry = mw:Frames(), M.cache.changelog
local counts = {}
for i = 1, 3 do
    M.SelectPage("home")
    assert(M.OpenSeeNewFeatures())
    mw:RunTimers()
    counts[i] = mw:Frames() - frames
end
print("changelog reopen frames: " .. table.concat(counts, ","))
assert(mw:Frames() == frames and M.cache.changelog == entry, "unchanged changelog rebuilt its frame tree")

local countdown = {
    text = "PvP countdown",
    link = {
        pageKey = "uf_player", sectionId = "status_icons", controlId = "menu2.uf_player.unit.status.pvp.countdown",
        settingKey = "player.pvpIndicatorCountdownEnabled", prepareKind = "unitStatus", prepareValue = "statusPvp",
        query = "show pvp countdown", label = "Show PvP countdown",
    },
}
local isForever = mw.core.Client.IsForever == true
if not isForever then
    local bridge = M.SearchBridge
    local original = bridge.OpenSearchTarget
    local attempted = false
    bridge.OpenSearchTarget = function()
        attempted = true
        return false
    end
    assert(not M.OpenChangelogMenuLink(countdown.link) and not attempted, "changelog routed an unavailable countdown control")
    bridge.OpenSearchTarget = original
end
local text, link = M.GetChangelogBullet(countdown)
assert(text == countdown.text and (link ~= nil) == isForever, "countdown link visibility differs from its menu control")
if isForever then
    assert(M.OpenChangelogMenuLink(link), "countdown link did not open the Forever setting")
end
