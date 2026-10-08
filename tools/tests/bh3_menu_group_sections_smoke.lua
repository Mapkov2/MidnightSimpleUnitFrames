local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local testRoot = assert(debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])"))
local h = assert(loadfile(testRoot .. "bh3_menu_page_fixture.lua"))()
local M, GF, GP = h.M, h.MSUF.GF, h.M.GroupPage
local db = h.env.MSUF_DB
GF.EnsureDB()
GF.InvalidateConfCache(true)
local source, target = GF.GetConf("party"), GF.GetConf("raid")
source.groupNumberStyle, target.groupNumberStyle = "CIRCLE", "TEXT"
assert(GP.CopyGroupSettings("party", "raid", { indicators = true }))
assert(target.groupNumberStyle == "CIRCLE", "Status copy omitted group number style")
source.hlOverride, source.barTextureOverride = true, nil
source.barTexture, source.barBackgroundTexture = "source-health", "source-background"
target.hlOverride, target.hlFocusColorR = false, 0.17
assert(GP.CopyGroupSettings("party", "raid", { health = true }))
assert(target.barTextureOverride == true and target.barTexture == "source-health")
assert(target.hlOverride == false and target.hlFocusColorR == 0.17, "health copy changed unrelated highlights")
source.barTextureOverride = false
target.hlOverride = true
assert(GP.CopyGroupSettings("party", "raid", { health = true }))
assert(target.barTextureOverride == false and target.barTexture == nil and target.barBackgroundTexture == nil and target.barBgTexture == nil,
    "global texture inheritance was not copied")
assert(target.hlOverride == true and target.hlFocusColorR == 0.17)
GP.Set("raid", "barTexture", "later-user-choice", "visual")
assert(target.barTextureOverride == true and target.barTexture == "later-user-choice", "manual selection remained locked to inherited texture")
local function ResetSection(scope, page, id)
    M.SetMenuStateValue("gfScope", scope)
    local entry = h.BuildPage(page)
    h.RunRefreshers(entry)
    local section = assert(entry.sections[id], id)
    local more = assert(section._msuf2CollapsibleEntry._msuf2SectionActions)
    more:GetScript("OnClick")(more)
    local popup = assert(more._msuf2GetSectionPopup())
    assert(popup._msuf2ResetSection(), "section reset refused")
    h.world.widgets:RunTimers(2000)
end
source.enabled = true
source.hideInHousing, source.hideInClientScene = true, false
source.hideOfflineEnabled, source.hideOfflineInCombat, source.hideOfflineDelay = true, true, 30
ResetSection("party", "gf_layout", "general")
local profile = M.UnitSectionsShared.FactoryProfile()
local factory = profile and profile.gf_party
for _, key in ipairs({ "hideInHousing", "hideInClientScene", "hideOfflineEnabled", "hideOfflineInCombat", "hideOfflineDelay" }) do
    local expected = factory and factory[key]
    if expected == nil then expected = GF.GetDefault("party", key) end
    assert(source[key] == expected, "Basics reset omitted " .. key)
end
for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
    if db[key] then
        db[key].enabled = true
        db[key].debuffStripeColorR, db[key].debuffStripeColorG, db[key].debuffStripeColorB = 0.1, 0.4, 1
        db[key].debuffStripeAlpha, db[key].debuffStripeEnabled = 0.9, true
    end
end
ResetSection("raid", "gf_bars", "dstripe")
for _, key in ipairs({ "debuffStripeColorR", "debuffStripeColorG", "debuffStripeColorB", "debuffStripeAlpha" }) do
    assert(db.gf_party[key] == db.gf_raid[key], "shared color split after reset: " .. key)
end
print("group section reset and status copy: PASS")
