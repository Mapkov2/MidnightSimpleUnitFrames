local root = assert(arg[1])
local badgeTemplate
local mw = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open(root, arg[2] or "Mainline", {
    page = "home",
    beforeOptions = function(world)
        world.env.NewFeatureLabelMixin = {}
        local CreateFrame = world.env.CreateFrame
        world.env.CreateFrame = function(kind, name, parent, template, ...)
            local frame = CreateFrame(kind, name, parent, template, ...)
            if template == "NewFeatureLabelTemplate" or template == "NewFeatureLabelNoAnimateTemplate" then
                badgeTemplate = template
                frame.Glow = frame:CreateTexture()
                function frame:GetTextWidth() return 30 end
            end
            return frame
        end
    end,
})
local M = mw.M
local button = assert(mw.win.status.seeNewFeaturesButton)
local badge = assert(button._msuf2NewBadge)
local label = button._msuf2Label
local unreadWidth = button:GetWidth()
assert(M.HasUnseenChangelog() and button._msuf2Active, "unread release does not emphasize the whole toolbar button")
assert(badge:IsShown() and badgeTemplate == "NewFeatureLabelNoAnimateTemplate", "unread release badge is missing or pulsing")
assert(not badge.Glow:IsShown(), "badge glow spills past the button")
local point, relative, relativePoint, x, y = badge:GetPoint()
assert(point == "CENTER" and relative == label and relativePoint == "RIGHT" and x > 15 and y == 0,
    "NEW badge should follow the label on the same line")
local labelPoint, labelRelative, labelRelativePoint, labelX = label:GetPoint()
assert(labelPoint == "CENTER" and labelRelative == button and labelRelativePoint == "CENTER", "label is not anchored to button center")
local labelHalfWidth = label:GetStringWidth() * 0.5
local left = labelX - labelHalfWidth
local right = labelX + labelHalfWidth + x + badge:GetTextWidth() * 0.5
assert(math.abs(left + right) < 0.01, "label and NEW badge are not centered as a group")
assert(right <= unreadWidth * 0.5 - 12, "label and NEW badge do not fit inside the button")
button:Click()
mw:RunTimers()
assert(M.activeKey == "changelog" and not M.HasUnseenChangelog(), "toolbar click did not acknowledge the open release")
assert(not button._msuf2Active and not badge:IsShown(), "read release kept the unread style")
assert(button:GetWidth() == unreadWidth, "click moved the toolbar hit targets")
local _, _, _, centeredX = label:GetPoint()
assert(centeredX == 0, "read button label did not return to center")
mw.win:RefreshStatus()
assert(not button._msuf2Active and not badge:IsShown(), "refresh resurrected a read release")
local data = mw.world.options.MSUF_FullChangelog
local version = data.currentVersion
data.currentVersion = "next-test-update"
mw.win:RefreshStatus()
assert(button._msuf2Active and badge:IsShown() and button._msuf2NewBadge == badge, "next release did not reuse the unread style")
data.currentVersion = version
mw.win:RefreshStatus()
assert(not button._msuf2Active and not badge:IsShown(), "restoring the read version kept the unread style")
local scroll = assert(M.scrollFrame)
scroll:SetVerticalScroll(120)
assert(scroll:GetVerticalScroll() > 0, "changelog fixture did not scroll")
button:Click()
mw:RunTimers()
assert(scroll:GetVerticalScroll() == 0, "toolbar did not return to the latest notes at the top of the changelog")
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

local function FindButton(entry, matches)
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame:GetParent() == entry.wrapper and frame:GetScript("OnClick") and matches(frame) then return frame end
    end
end

button:Click()
mw:RunTimers()
local current = assert(M.cache.changelog)
local olderVersion = data.entries[2].version
local function IsVersion(header, expected)
    local headerLabel = header._msuf2Label
    return headerLabel and headerLabel:GetText():find(expected .. "  -  ", 1, true) == 1
end
local function Older(header) return IsVersion(header, olderVersion) end
local older = assert(FindButton(current, Older), "older release button is missing")
local _, _, _, _, oldY = older:GetPoint()
scroll:SetVerticalScroll(-oldY - 8)
older:Click()
mw:RunTimers()
local selected = assert(FindButton(M.cache.changelog, Older), "older release disappeared after selection")
local _, _, _, _, selectedY = selected:GetPoint()
assert(M.changelogSelectedVersion == olderVersion and scroll:GetVerticalScroll() == -selectedY - 8,
    "selecting older notes scrolled past their heading")
button:Click()
assert(M.cache.changelog == current and scroll:GetVerticalScroll() == 0, "toolbar did not restore the latest cached release")

local function FindHighlight(prefix)
    return FindButton(M.cache.changelog, function(frame)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetText and (region:GetText() or ""):find(prefix, 1, true) == 1 then return true end
        end
    end)
end
if version ~= "7.0.4" then
    local release = assert(FindButton(current, function(header) return IsVersion(header, "7.0.4") end))
    release:Click()
end
local castbarLink = assert(FindHighlight("Player castbar Force Off"), "7.0.4 has no clickable castbar highlight")
castbarLink:Click()
assert(M.activeKey == "uf_player" and M.cache.uf_player.sections.castbar._msuf2CollapsibleEntry.open,
    "rendered castbar highlight did not open its real settings section")

assert(M.SelectPage("changelog"))
local auraBarsLink = FindHighlight("Aura Lanes and Bars")
assert((auraBarsLink ~= nil) == (mw.core.Client.IsRetail == true), "aura highlight link visibility differs from the Bars tab")
if auraBarsLink then
    auraBarsLink:Click()
    local auraBars = M.RuntimeControlCatalog.Get("menu2.uf_player.auras.unit-workspace.lane.buff.layout.show-as-bars")
    assert(M.activeKey == "uf_player" and auraBars and auraBars.widget:IsVisible(),
        "aura highlight did not open the Player Buffs Bars toggle")
end

assert(M.SelectPage("changelog"))
local outlineLink = assert(FindHighlight("Outline Settings gear"), "outline highlight has no direct link")
outlineLink:Click()
local outline = M.RuntimeControlCatalog.Get("menu2.opt.bars.global.outline.thickness")
assert(M.activeKey == "opt_bars" and outline and outline.widget:IsVisible(),
    "outline highlight did not open the Frame Outline thickness slider")

do
    local CreatePopup, popup = M.CreateMenuPopupPanel
    M.CreateMenuPopupPanel = function(...)
        popup = CreatePopup(...)
        return popup
    end
    local function CheckGear(widget, id)
        local gear = assert(widget._msuf2OutlineGear, "missing outline gear for " .. id)
        assert(gear:IsVisible() and not M.RuntimeControlCatalog.GetForWidget(gear), "invalid outline gear")
        gear:Click()
        assert(popup and popup:IsShown() and popup.select:GetValue() == id, "the gear selected the wrong outline")
        gear:Click()
        assert(not popup:IsShown(), "clicking the outline gear again did not close it")
    end
    CheckGear(outline.widget, "core.frame.shared")
    assert(M.SelectPage("opt_castbar"))
    local castbar = assert(M.cache.opt_castbar.sections.castbar_textures)
    M.Widgets.FocusCollapsibleSection(castbar, { persist = true })
    mw:RunTimers()
    local _, castOutline = M.RuntimeControlCatalog.FindBySettingKey("general.castbarOutlineThickness", "opt_castbar")
    CheckGear(assert(castOutline), "core.castbar.outline")
    assert(M.SelectPage("gf_indicators"))
    local groupOutline
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if record.pageKey == "gf_indicators" and record.controlId:lower():gsub("[^%w]", ""):match("groupbordersize$") then
            groupOutline = M.RuntimeControlCatalog.Get(record.controlId).widget
            break
        end
    end
    CheckGear(assert(groupOutline), "core.group.border.party")
    assert(popup.rows["core.group.border.raid"].getColor, "group border color is absent from the overview")
    M.SetMenuStateValue("gfScope", "raid")
    CheckGear(groupOutline, "core.group.border.raid")
    M.SetMenuStateValue("gfScope", "party")
    M.CreateMenuPopupPanel = CreatePopup
end

local arenaLink = { pageKey = "uf_arena", sectionId = "arena", controlId = "test.arena" }
local _, visibleArenaLink = M.GetChangelogBullet({ text = "Arena", link = arenaLink })
assert((visibleArenaLink ~= nil) == mw.core.Client.SupportsUnit("arena"), "unavailable arena highlight stayed clickable")

mw.core.SuiteLink.GetChangelog = function()
    return { entries = { { version = "Suite latest" }, { version = "Suite older" } } }
end
M.changelogSource = nil
M.InvalidatePage("changelog")
assert(M.SelectPage("changelog"))
local function SourceTab(label)
    return assert(FindButton(M.cache.changelog, function(frame)
        return frame._msuf2Label and frame._msuf2Label:GetText() == label
    end))
end
local coreEntry = M.cache.changelog
SourceTab("MSUF"):Click()
assert(M.cache.changelog == coreEntry, "clicking the active source discarded its cached entries")
SourceTab("MSUF Suite"):Click()
assert(M.suiteChangelogSelectedVersion == "Suite latest" and not M.HasUnseenChangelog(), "Suite notes did not open and clear their badge")
M.suiteChangelogSelectedVersion = "Suite older"
assert(M.SelectPage("changelog"))
button:Click()
assert(M.suiteChangelogSelectedVersion == "Suite latest", "toolbar did not reopen the newest Suite notes without currentVersion")
