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

do
    local shared = M.UnitSectionsShared
    local conf = assert(mw.env.MSUF_DB.player)
    local factory = { player = M.DeepCopy(conf) }
    factory.player.smoothFill = false
    conf.smoothFill = true
    factory.player.unitDispelSymbolSize = 16
    conf.unitDispelSymbolSize = 18
    local reads, scans = 0, 0
    local getFactory, fieldKeys = shared.FactoryProfile, shared.SectionFieldKeys
    shared.FactoryProfile = function()
        reads = reads + 1
        return factory
    end
    shared.SectionFieldKeys = function(spec, source, defaults)
        if source == conf or defaults == conf then scans = scans + 1 end
        return fieldKeys(spec, source, defaults)
    end
    local link = {
        pageKey = "uf_player", sectionId = "text", controlId = "menu2.uf_player.unit.text.power.full_value_short",
        settingKey = "player.powerFullValueShort", prepareKind = "menuTab", prepareValue = "power",
        query = "power text short numbers", label = "Short numbers",
    }
    assert(not M.cache.uf_player, "cold changelog test prebuilt Player")
    assert(M.OpenChangelogMenuLink(link), "cold changelog link did not focus the exact Power Text control")
    assert(reads == 0 and scans == 0, "cold changelog navigation walked profile fields for section badges")
    local playerPage = assert(M.cache.uf_player)
    local basics = playerPage.sections.frame_basics._msuf2CollapsibleEntry
    M.SelectPage("changelog")
    mw:RunTimers()
    assert(reads == 0 and not basics._msuf2CustomBadgeWanted, "a deferred badge ran for a page the reader left")
    assert(M.OpenChangelogMenuLink(link), "cached changelog link did not focus the exact Power Text control")
    mw:RunTimers()
    assert(reads == 1 and scans == 0, "section badges did not reuse factory keys after navigation")
    assert(basics._msuf2CustomBadgeWanted, "deferred badge missed the changed Player setting")
    local symbol = playerPage.sections.unit_dispel_symbol._msuf2CollapsibleEntry
    assert(symbol._msuf2CustomBadgeWanted, "deferred badge missed the changed prefixed setting")
    conf.smoothFill = false
    conf.unitDispelSymbolSize = 16
    M.RunEntryRefreshers(playerPage, { force = true })
    assert(basics._msuf2CustomBadgeWanted == false, "warm refresh kept a badge after restoring the default setting")
    assert(symbol._msuf2CustomBadgeWanted == false, "warm refresh kept a badge after restoring a prefixed default")
    shared.FactoryProfile, shared.SectionFieldKeys = getFactory, fieldKeys
end

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
