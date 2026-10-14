-- Whole group-domain reset through the real menu, factory and normalization.
-- The Python driver supplies the decoded current factory, never a saved profile.
local root, flavor = assert(arg[1]), assert(arg[2])
local compact, decoded = dofile(assert(arg[3]))
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end
local mw = MenuWorld.Open(root, flavor, { page = "home", beforeOptions = function(world)
    local original = world.env.MSUF_TryDecodeCompactString
    world.env.MSUF_TryDecodeCompactString = function(text)
        if text == compact then return Copy(decoded) end
        return original(text)
    end
    -- The client fixture has no learned Classic specialization; model a known
    -- current spec so runtime seeding and the menu resolve the same defaults.
    local indicators = world.core.GF.SpellIndicators
    local specs = {}
    for key in pairs(indicators.SpecInfo) do specs[#specs + 1] = key end
    table.sort(specs)
    local spec = indicators.SpecMap and indicators.SpecMap.WARRIOR_1 or specs[1]
    indicators.GetPlayerSpec = function() return spec end
end })
local M, GF, env = mw.M, mw.core.GF, mw.env
local widgets = {}
local register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, meta, ...)
    if meta and meta.controlId then widgets[meta.controlId] = widget end
    return register(widget, meta, ...)
end
local function Check(value, message)
    assert(value, flavor .. ": " .. message)
end
local function Equal(a, b, path)
    Check(type(a) == type(b), path .. " type differs")
    if type(a) ~= "table" then Check(a == b, path .. " differs: " .. tostring(a) .. " / " .. tostring(b)); return end
    for key, value in pairs(a) do Equal(value, b[key], path .. "." .. tostring(key)) end
    for key in pairs(b) do Check(a[key] ~= nil, path .. "." .. tostring(key) .. " missing") end
end
local ROOTS = { "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }
local PAGES = { "gf_layout", "gf_bars", "gf_auras", "gf_indicators", "gf_priority" }
GF.EnsureDB()
local db = env.MSUF_DB
local charKey = assert(next(env.MSUF_GlobalDB.char), "active character missing")
env.MSUF_GlobalDB.char[charKey].priorityFrames = {
    pins = { { guid = "Player-ResetTest", name = "Pinned member" } },
}
local characterPins = Copy(env.MSUF_GlobalDB.char[charKey].priorityFrames)
local expected = Copy(db)
local expectedApply = expected
Check(db.gf_raid.maxColumns == 8, "factory cannot display all raid groups")
local create = mw.core.MSUF_CreateFactoryDefaultProfile
M.UnitSectionsShared.FactoryProfile() -- Prime the independent, session-cached menu defaults.
local factoryCalls, earlyRefreshes, requests, notices = 0, 0, 0, 0
mw.core.MSUF_CreateFactoryDefaultProfile = function()
    factoryCalls = factoryCalls + 1
    return create()
end
GF.RefreshAll = function() earlyRefreshes = earlyRefreshes + 1; return true end
M.ApplyService.RequestGroupReset = function()
    requests = requests + 1
    if expectedApply then
        for _, key in ipairs(ROOTS) do Equal(db[key], expectedApply[key], "apply." .. key) end
    end
    return true
end
M.ShowStatusFeedback = function() notices = notices + 1 end
local function Poison(value)
    for key, child in pairs(value) do
        if type(child) == "table" then Poison(child)
        elseif type(child) == "boolean" then value[key] = not child
        elseif type(child) == "number" then value[key] = child + 7
        elseif type(child) == "string" then value[key] = "legacy:" .. child end
    end
    value._resetResidual = { nested = { stale = true } }
end
local function Dirty()
    for _, key in ipairs(ROOTS) do
        Poison(db[key])
        db[key].groupFilter = { true, true, true }
        db[key].raidLayouts = { mythic = { maxColumns = 1, offsetX = 10000 } }
        db[key]._activeRaidLayout = "mythic"
        db[key].anchorToFrame = "LegacyRaidAnchor"
    end
end
local function Verify()
    for _, key in ipairs(ROOTS) do Equal(db[key], expected[key], key) end
    for group = 1, 8 do Check(GF.GroupFilterAllowsSubgroup(db.gf_raid.groupFilter, group), "group remains filtered") end
    Check(GF.GetVisibleLayoutCount("raid", 40, GF.GetConf("raid")) == 40, "raid remains truncated")
    Check(GF.GetConf("raid") == db.gf_raid and GF.GetPriorityConf() == db.gf_priority, "stale config cache")
end
-- Every group Reset Page owns all four roots, independently of selected scope.
for index, page in ipairs(PAGES) do
    M.SetMenuStateValue("gfScope", index % 2 == 0 and "party" or "raid")
    -- Compare with a fresh factory in this same view, including lazy defaults.
    local baseline = create()
    for _, key in ipairs(ROOTS) do db[key] = Copy(baseline[key]) end
    GF.InvalidateConfCache()
    GF.EnsureDB()
    expectedApply = Copy(db)
    local renderer = db.gf_raid.auras.renderer
    mw:Select(page)
    Check(db.gf_raid.auras.renderer == renderer, page .. " changed renderer while reading defaults")
    expected = Copy(db)
    Dirty()
    local identities = {}
    for _, key in ipairs(ROOTS) do identities[key] = db[key] end
    db.player.resetUnrelated, db.general.resetUnrelated = 79, "keep"
    local before = Copy(db)
    local calls, refreshes, applies = factoryCalls, earlyRefreshes, requests
    Check(M.ResetPageToDefaults(page) == true, page .. " refused")
    Check(factoryCalls == calls + 1, page .. " decoded factory more than once")
    Check(earlyRefreshes == refreshes, page .. " refreshed before reset cache invalidation")
    Check(requests == applies + 1, page .. " did not request exactly one final apply")
    Verify()
    Equal(env.MSUF_GlobalDB.char[charKey].priorityFrames, characterPins, "character priority pins")
    for _, key in ipairs(ROOTS) do Check(db[key] == identities[key], key .. " root identity changed") end
    for key, value in pairs(before) do
        if not key:match("^gf_") then Equal(db[key], value, "unrelated." .. key) end
    end
    Check(M.ResetPageToDefaults(page) == true, page .. " repeated reset refused")
    Verify()
end
-- Real input callbacks must opt in before preview and discard pre-reset drags.
expectedApply = nil
M.SetMenuStateValue("gfScope", "raid")
M.SetMenuStateValue("gfAuraLaneSelection", { raid = "buff" })
M.SetMenuStateValue("gfAuraToolSelection", { raid = { buff = "layout" } })
mw:Select("gf_auras")
M.RebuildPageKeepingScroll("gf_auras")
local function Widget(suffix)
    for id, widget in pairs(widgets) do
        if id:sub(-#suffix) == suffix then return widget end
    end
    error("missing Aura control " .. suffix)
end
local slider = Widget("layout.size")
local command = assert(slider._msuf2CommandAction)
db.gf_raid.auras.renderer = "NATIVE_12_1"
slider._msuf2SliderActive = true
local applyBefore = requests
command.set(command.get() + 1)
Check(db.gf_raid.auras.renderer == "CUSTOM", "drag did not opt in before the deferred apply")
Check(requests == applyBefore, "drag applied live group frames before release")
Check(M.ResetPageToDefaults("gf_auras") == true, "reset during drag refused")
applyBefore = requests
local hide = slider:GetScript("OnHide")
if hide then hide(slider) end
local release = slider:GetScript("OnMouseUp")
if release then release(slider) end
mw:RunTimers()
Check(db.gf_raid.auras.renderer == "NATIVE_12_1", "old drag changed the renderer after reset")
Check(requests == applyBefore, "old drag requested another reset apply")
local dropdown = Widget("layout.anchor")
db.gf_raid.auras.renderer = "NATIVE_12_1"
local anchorCommand = dropdown._msuf2CommandAction
anchorCommand.set(anchorCommand.get() == "TOPLEFT" and "BOTTOMRIGHT" or "TOPLEFT")
Check(db.gf_raid.auras.renderer == "CUSTOM", "dropdown edit did not opt in")
Check(M.ResetPageToDefaults("gf_auras") == true, "reset after dropdown refused")
local model = mw.core.MSUF_Auras3.MenuModel
local legacy = M.AuraGroupSettings
db.gf_raid.auras.renderer, db.gf_mythicraid.auras.renderer = "NATIVE_12_1", "NATIVE_12_1"
legacy.GFReadRoot("raid")
legacy.GFReadGroup("raid", "buff")
model.ReadGroupBlacklistHidePermanent("raid", "buff")
Check(db.gf_raid.auras.renderer == "NATIVE_12_1" and db.gf_mythicraid.auras.renderer == "NATIVE_12_1",
    "legacy/blacklist getter changed renderer")
Check(model.WriteGroupBlacklistHidePermanent("raid", "buff", true), "blacklist edit refused")
Check(db.gf_raid.auras.renderer == "CUSTOM" and db.gf_mythicraid.auras.renderer == "CUSTOM",
    "blacklist edit did not activate both scoped owners")
Check(M.ResetPageToDefaults("gf_auras") == true, "reset after blacklist refused")
-- Reset must remain undoable and redo must restore factory settings again.
Check(M.CaptureHistory("Legacy raid layout", "smoke:raid-layout", function()
    db.gf_raid.groupFilter = { true, true, true }
    db.gf_raid.maxColumns = 3
    return true
end) == true, "layout edit refused")
Check(M.ResetPageToDefaults("gf_layout") == true, "history reset refused")
Check(M.Undo() == true, "reset cannot be undone")
db = env.MSUF_DB
Check(db.gf_raid.groupFilter and db.gf_raid.maxColumns == 3,
    "undo did not restore layout: " .. tostring(db.gf_raid.maxColumns) .. " / " .. tostring(db.gf_raid.groupFilter))
Check(M.Redo() == true, "reset cannot be redone")
db = env.MSUF_DB
Check(db.gf_raid.groupFilter == nil and db.gf_raid.maxColumns == 8, "redo did not restore factory layout")
-- A provider refusal must not turn into success, apply or an undo entry.
local reset = GF.ResetAllToDefaults
GF.ResetAllToDefaults = function() return false end
local before, applies, feedback, undo = Copy(db), requests, notices, M.GetHistoryState().undoCount
Check(M.ResetPageToDefaults("gf_layout") == false, "failed provider reported success")
Equal(db, before, "failed reset")
Check(requests == applies and notices == feedback and M.GetHistoryState().undoCount == undo,
    "failed reset applied, reported success or entered history")
GF.ResetAllToDefaults = reset
-- Lockdown must leave stored settings untouched and do no factory work.
mw.world.widgets:SetCombat(true)
before, applies, factoryCalls = Copy(db), requests, 0
Check(M.ResetPageToDefaults("gf_layout") == false, "combat reset accepted")
Equal(db, before, "combat reset")
Check(requests == applies and factoryCalls == 0, "combat reset did work")
mw.world.widgets:SetCombat(false)
-- The standalone API also repairs malformed roots and keeps its immediate apply.
db.gf_party, db.gf_raid, db.gf_mythicraid, db.gf_priority = false, 17, "legacy", false
local refreshes = earlyRefreshes
Check(GF.ResetAllToDefaults() == true, "standalone reset refused")
Check(earlyRefreshes == refreshes + 1, "standalone reset did not refresh once")
Check(db.gf_raid.groupFilter == nil and db.gf_raid.maxColumns == 8, "malformed layout was not reset")
-- All four scopes, including Priority, come from this same supplied snapshot.
local supplied = create()
supplied.gf_priority.attachGap = 17
Check(GF.ResetAllToDefaults(supplied, true) == true, "snapshot reset refused")
Check(db.gf_priority.attachGap == 17, "Priority ignored factory snapshot")
local originalSize = supplied.gf_party.auras.buff.size
db.gf_party.auras.buff.size = originalSize + 5
Check(supplied.gf_party.auras.buff.size == originalSize, "reset aliased nested factory data")
-- Reset discards group overrides across contexts and preserves unrelated fields.
local V = mw.core.ProfileVariants
-- Variant policy is real; unrelated native unit/gameplay application is outside this contract.
local applyRuntime = mw.core.ProfileRuntime.Apply
mw.core.ProfileRuntime.Apply = function() V.ResolveCurrent() end
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
Check(M.CaptureHistory("Stored base filter", "smoke:variant-base", function()
    db.gf_raid.groupFilter = { true, true, true }
    return true
end) == true,
    "base history capture refused")
Check(M.CaptureHistory("Group overrides", "smoke:variant-schema", function()
return V.Replace(db, { version = 1, entries = {
    { name = "ResetSolo", conditions = { context = "solo" }, patch = {
        { path = { "gf_raid", "groupFilter" }, value = { true, true, true } },
        { path = { "player", "width" }, value = 444 },
    } },
    { name = "UnrelatedParty", conditions = { context = "party" }, patch = {
        { path = { "player", "width" }, value = 555 },
        { path = { "gf_mythicraid", "groupFilter" }, value = { true, true } },
        { path = { "gf_priority", "attachGap" }, value = 23 },
    } },
} })
end) == true, "variant fixture refused")
Check(db.gf_raid.groupFilter ~= nil and db.player.width == 444, "solo variant not active")
Check(M.ResetPageToDefaults("gf_layout") == true, "variant reset refused")
Check(db.gf_raid.groupFilter == nil and db.player.width == 444, "reset retained filter or changed unrelated variant")
local baseAfterReset = assert(V.BaseSnapshot(db, true))
Check(baseAfterReset.gf_raid.groupFilter == nil, "remembered variant base survived reset")
Check(#V.Find(db, "ResetSolo").patch == 1 and #V.Find(db, "UnrelatedParty").patch == 1,
    "reset retained active or inactive group overrides: " .. #V.Find(db, "ResetSolo").patch .. "/" .. #V.Find(db, "UnrelatedParty").patch)
Check(M.Undo() == true, "variant reset cannot be undone")
db = env.MSUF_DB
Check(db.gf_raid.groupFilter and #V.Find(db, "UnrelatedParty").patch == 3,
    "undo did not restore base and inactive variant overrides")
Check(assert(V.BaseSnapshot(db, true)).gf_raid.groupFilter ~= nil, "undo did not restore remembered base filter")
Check(M.Redo() == true, "variant reset cannot be redone")
db = env.MSUF_DB
Check(db.gf_raid.groupFilter == nil and #V.Find(db, "UnrelatedParty").patch == 1,
    "redo revived base or inactive variant overrides")
env.IsInGroup = function() return true end
env.IsInInstance = function() return true, "party" end
V.ResolveCurrent()
Check(db.gf_raid.groupFilter == nil and db.gf_mythicraid.groupFilter == nil
    and db.gf_priority.attachGap ~= 23, "base or inactive variant settings returned after context change")
Check(V.Find(db, "UnrelatedParty") ~= nil and db.player.width == 555,
    "unrelated variant changed: " .. tostring(db.player.width))
env.IsInGroup = function() return false end
env.IsInInstance = function() return false, "none" end
V.ResolveCurrent()
Check(db.gf_raid.groupFilter == nil and db.player.width == 444, "returning to variant revived filter")
mw.core.ProfileRuntime.Apply = applyRuntime
print("group_page_reset: ok (" .. flavor .. ", five pages, complete defaults, single factory/apply, refusal/combat, nested isolation)")
