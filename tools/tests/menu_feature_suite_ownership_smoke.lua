local root, suiteRoot = assert(arg[1]), assert(arg[2])
local flavor = arg[3] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end })
local env, M, core = mw.env, mw.M, mw.core
local methods = getmetatable(env.UIParent).__index
for _, key in ipairs({ "SetDrawBling", "SetSwipeColor", "SetSwipeTexture", "SetReverse", "SetEdgeScale", "SetMotionScriptsWhileDisabled" }) do
    methods[key] = methods[key] or function() end
end
methods.GetUnboundedStringWidth = methods.GetUnboundedStringWidth or function(self) return self:GetStringWidth() end
methods.GetCountdownFontString = methods.GetCountdownFontString or function(self)
    if not self.countdownFont then self.countdownFont = self:CreateFontString(nil, "OVERLAY") end
    return self.countdownFont
end
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
local disabled = {}
local Support = assert(loadfile(suiteRoot .. "/tools/tests/suite_test_support.lua"))()
env.C_SpecializationInfo.GetNumSpecializationsForClassID = function() return 0 end
env.C_SpecializationInfo.GetSpecialization = env.C_SpecializationInfo.GetSpecialization or function() return nil end
local getCVar = env.C_CVar.GetCVar
env.C_CVar.GetCVar = function(key) if key == "combinedBags" then return "1" end return getCVar(key) end
env.C_AddOns = {
    GetAddOnMetadata = function() end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function() return true end,
    GetAddOnEnableState = function(name) return disabled[name] and 0 or 2 end,
    LoadAddOn = function(name)
        if Support.LoadLocaleAddon(suiteRoot, name, env) then loaded[name] = true; return true end
        return false, "MISSING"
    end,
    GetNumAddOns = function() return 0 end,
}
local function Load(addon, ns)
    for _, file in ipairs(Support.TocFiles(suiteRoot, addon, "Mainline")) do
        if file:match("%.lua$") then
            local ok, why = mw.world:LoadFile(suiteRoot .. "/" .. addon .. "/" .. file, addon, ns)
            assert(ok, file .. ": " .. tostring(why))
        end
    end
    loaded[addon] = true
end
local NS = {}
Load("MSUF_Suite", NS)
assert(NS.Database.Initialize(nil))
local S, W = NS.Suite, core.ProfileWorkbench
local P = {}
Load("MSUF_Suite_Options", P)
local checks, failures = 0, {}
local function Check(ok, why)
    checks = checks + 1
    if not ok then failures[#failures + 1] = why end
end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function Select(page)
    Check(mw:Select(page) ~= false, "failed to open " .. page)
    Settle()
end
local api, called = M.Search._CoreAPI
local open = api.OpenSearchTarget
api.OpenSearchTarget = function(...)
    called = { open(...) }
    return unpack(called)
end
-- Saved targets are immutable records: navigation relocates a copy and never executes the target.
local function OpenTarget(record)
    local expected = {}
    for key, value in pairs(record) do expected[key] = value end
    Select("home")
    called = nil
    api.OpenSearchTarget(record.pageKey, record.label, nil, nil, nil, record)
    Settle()
    for key, value in pairs(expected) do Check(record[key] == value, record.controlId .. " mutated target " .. key) end
end
local owners = { inventoryArchive = "suite_bags", keywordAlerts = "suite_chat", keyAudit = "suite_actionbars" }
disabled.MSUF_Suite_Bags, disabled.MSUF_Suite_Chat, disabled.MSUF_Suite_ActionBars = true, true, true
local function SearchOwner(id, owner, stage)
    P.ForgetAvailability()
    P.InvalidateSearch()
    local query = P.Tr(P.catalog[id].title)
    api.RunSearchInputQuery(query, false)
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(1000)
    end
    local found
    for rank, row in ipairs(api.SearchPages(query)) do
        local exact = row.exactTarget
        if row.key == owner and exact and exact.settingKey == "msufsuite." .. id .. ".enabled" then
            found = rank
            break
        end
    end
    Check(found and found <= 6, stage .. " search missed owned helper switch: " .. id)
    if not found or found > 6 then
        local results = api.SearchPages(query)
        local first = results[1]
        if first then
            local selected, focused, exact = open(first.key, query, first.label, first.anchor, first.route, first.exactTarget)
            Settle()
            local section = M.cache[owner].sections[owner .. "_" .. id .. "_module"]
            print("FIRST_RESULT", selected, focused, exact, section and section.open)
        end
        for rank, row in ipairs(results) do
            if rank > 10 then break end
            print("SEARCH_DEBUG", stage, id, rank, row.key, row.label,
                row.exactTarget and row.exactTarget.settingKey, row.exactTarget and row.exactTarget.controlId)
        end
    end
    local action = P.Meta(owner, id, "action.open", "action").controlId
    local indexed
    for _, row in ipairs(P.SearchRows()) do if row.controlId == action and row.pageKey == owner then indexed = row end end
    Check(indexed ~= nil, stage .. " provider omitted owned helper action: " .. id)
end
for id, owner in pairs(owners) do
    P.ForgetAvailability()
    SearchOwner(id, owner, "cold")
    local record = { pageKey = "suite_qualityOfLife", label = P.catalog[id].title,
        controlId = P.Meta("suite_qualityOfLife", id, "action.open", "action").controlId,
        sectionId = "suite_qualityOfLife_" .. id .. "_" .. P.catalog[id].controls[2].section }
    for pass = 1, 2 do
        OpenTarget(record)
        Check(called and called[1] and called[2] and called[3], id .. " legacy action missed exact owner control pass" .. pass)
        Check(M.activeKey == owner, id .. " legacy action landed on " .. M.activeKey)
    end
    local key = id == "inventoryArchive" and "characters" or id == "keywordAlerts" and "cooldown" or "onlyIssues"
    record = { pageKey = "suite_qualityOfLife", label = P.catalog[id].rules[key].label,
        settingKey = "msufsuite." .. id .. "." .. key,
        controlId = P.Meta("suite_qualityOfLife", id, key, "setting").controlId }
    OpenTarget(record)
    Check(called and called[1] and called[2] and called[3], id .. " legacy setting missed exact owner control")
    Check(M.activeKey == owner, id .. " legacy setting landed on " .. M.activeKey)
    SearchOwner(id, owner, "warm")
end
disabled.MSUF_Suite_Bags, disabled.MSUF_Suite_Chat, disabled.MSUF_Suite_ActionBars = nil, nil, nil
P.ForgetAvailability()
local cdm = S.CDMInspectionRow("c2")
assert(cdm and cdm.target)
local ok, focused, exact = api.OpenSearchTarget(cdm.page, cdm.label, nil, nil, nil, cdm.target)
Settle()
Check(ok and focused and exact, "CDM per-slot provider target failed exact navigation")
Check(P.CDMPage.selected == "c2", "CDM provider did not select c2")
local widget
for _, candidate in ipairs(M.cache.suite_cooldownManager.searchWidgets or {}) do
    local record = candidate._msuf2RuntimeControlRecord
    if record and (record.controlId:lower():find("inspectvisibility", 1, true)
        or record.label == "Check visibility settings" or record.label == P.Tr("Check visibility settings")) then widget = candidate; break end
end
Check(widget ~= nil, "CDM inspection button not discoverable in runtime catalog")
if widget then
    local saved = { pageKey = cdm.page, label = cdm.label, controlId = widget._msuf2RuntimeControlRecord.controlId }
    for key, value in pairs(cdm.target) do saved[key] = value end
    Check(saved.prepareKind == "suiteCDMBar" and saved.prepareValue == "c2", "CDM provider target lost slot")
    P.CDMPage.Select("c1")
    OpenTarget(saved)
    Check(called and called[1] and called[2] and called[3], "CDM saved provider target failed exact opening")
    Check(P.CDMPage.selected == "c2", "CDM saved action selected last-visited slot")
end
local legacyInspection
for index, row in ipairs(W.Visibility()) do
    if row.slot == "c2" then
        legacyInspection = { pageKey = "profile_tools", label = row.label,
            controlId = "menu2.profile.tools.profiles.visibility." .. index }
        break
    end
end
Check(legacyInspection ~= nil, "workbench did not publish Suite CDM inspection")
if legacyInspection then
    P.CDMPage.Select("c1")
    OpenTarget(legacyInspection)
    Check(called and called[1] and called[2] and called[3], "old workbench CDM target failed nested resolver navigation")
    Check(P.CDMPage.selected == "c2", "old workbench CDM target lost provider slot")
end
for _, key in ipairs({ "action.openPlanner", "weekly" }) do
    local action = key == "action.openPlanner"
    local record = { pageKey = "suite_qualityOfLife", label = "Adventure planner",
        controlId = P.Meta("suite_qualityOfLife", "planningTools", key, action and "action" or "setting").controlId,
        settingKey = not action and "msufsuite.planningTools." .. key or nil }
    OpenTarget(record)
    Check(called and called[1] and called[2] and called[3], "old planner target failed exact opening: " .. key)
    Check(M.activeKey == "suite_planningTools", "old planner target missed owner: " .. key)
end
for _, why in ipairs(failures) do print("FAIL", why) end
assert(#failures == 0, #failures .. " cross-addon ownership checks failed")
print("cross_addon_probe: " .. flavor .. " passed " .. checks .. " checks")
