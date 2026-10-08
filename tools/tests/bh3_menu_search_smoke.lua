local root, flavor, mode = assert(arg[1]), arg[2] or "Mainline", arg[3] or "identity"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { locale = mode == "profile" and "deDE" or "enUS", beforeOptions = function(w) w.core.FinalizeLocale() end })
local M, env = mw.M, mw.env
local api, routing = M.Search._CoreAPI, M.Search._RoutingAPI
if mode == "identity" then
    M.SelectPage("opt_castbar"); mw:RunTimers()
    local section = assert(M.cache.opt_castbar.sections.castbar_interrupt_ready)
    section._msuf2CollapsibleEntry.SetOpenImmediate(true); mw:RunTimers()
    local count = 0
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.key == "opt_castbar" and rec.label == "Show on Target castbar" then
            count = count + 1
            assert(rec.exactTarget and rec.exactTarget.controlId, "bound row lost exact identity")
        elseif rec.label == "Show on enemy nameplates (MSUF Suite)" then
            assert(M.CastbarSuiteNameplatesSupported(), "hidden unsupported nameplate setting leaked into warm search")
        end
    end
    assert(count == 1, "cold/live copies must merge into one canonical row; count=" .. count)
elseif mode == "scope" then
    local route = routing.SearchRouteForTarget("gf_auras", "mythic raid buffs", "")
    routing.ApplySearchRoute("gf_auras", route)
    assert(M.gfScope ~= "mythicraid" or flavor == "Mainline", "query persisted unsupported Mythic Raid")
    local oldScope = M.gfScope
    local result = routing.OpenSearchTarget("gf_auras", "", "", nil, nil,
        { prepareKind = "groupAuraWorkspace", prepareValue = "mythicraid_buff_filters" })
    if flavor ~= "Mainline" then assert(result == false and M.gfScope == oldScope, "unsupported exact scope must fail before mutation") end
    for _, rec in ipairs(api.GetSearchRecords()) do
        local target = rec.exactTarget
        if target and target.prepareKind == "groupAuraWorkspace" and target.prepareValue:match("^mythicraid_") then
            assert(flavor == "Mainline", "unsupported scope leaked into search")
        end
    end
    local target = { controlId = "menu2.gf_layout.group.field.targetsenabled",
        settingKey = "gf_party.targetsEnabled", sectionId = "party_targets",
        prepareKind = "groupScope", prepareValue = "party" }
    local partyEntry
    for i = 1, 2 do
        M.SetMenuStateValue("gfScope", "raid")
        M.SelectPage("gf_layout")
        mw:RunTimers()
        assert(not M.cache.gf_layout.sections.party_targets, "party section leaked into raid view")
        local selected, reached, exact = routing.OpenSearchTarget("gf_layout", "unrelated", "", nil,
            { accordion = { ["gf_layout:party_targets"] = true } }, target)
        mw:RunTimers()
        assert(selected and reached and exact and M.gfScope == "party", "deep link did not select its declared group view")
        if partyEntry then assert(M.cache.gf_layout == partyEntry, "declared party view was unnecessarily rebuilt") end
        partyEntry = M.cache.gf_layout
    end
elseif mode == "aura" then
    M.SetMenuStateValue("gfScope", "party")
    M.gfAuraLaneSelection = { party = "buff" }
    M.gfAuraToolSelection = { party = { buff = "filters" } }
    M.SelectPage("gf_auras"); mw:RunTimers()
    local row
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.key == "gf_auras" and rec.label == "Big Defensive" then row = rec; break end
    end
    assert(row and row.exactTarget, "filter row missing")
    assert(row.exactTarget.prepareKind == "groupAuraWorkspace" and row.exactTarget.prepareValue == "party_buff_filters", "aura row lost its view")
    M.gfAuraToolSelection.party.buff = "layout"
    M.SelectPage("gf_auras"); mw:RunTimers()
    local selected, reached, exact = routing.OpenSearchTarget(row.key, "unrelated words", "", nil, nil, row.exactTarget)
    mw:RunTimers()
    assert(selected and reached and exact, "aura exact row did not reach control independent of query")
elseif mode == "alpha" then
    M.SelectPage("uf_target"); mw:RunTimers()
    local section = M.cache.uf_target.sections.transparency
    section._msuf2CollapsibleEntry.SetOpenImmediate(true); mw:RunTimers()
    local row
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.key == "uf_target" and rec.exactTarget and rec.exactTarget.settingKey == "target.oocFadeAlpha" then row = rec; break end
    end
    assert(row and row.exactTarget.prepareKind == "unitAlphaTab" and row.exactTarget.prepareValue == "ooc", "OOC row must declare exact tab")
    local selected, reached, exact = routing.OpenSearchTarget(row.key, "irrelevant words", "", nil, nil, row.exactTarget)
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget(row.key, row.exactTarget)
    assert(selected and reached and exact and widget and widget:IsVisible(), "OOC exact navigation must reveal its control")
elseif mode == "profile" then
    env.MSUF_GlobalDB.global.profileSyncGroups = { { name = "Regression", members = { Default = true }, modules = { unitframes = true }, exclude = {} } }
    local found = {}
    for _, row in ipairs(M.ProfileSearch.Collect()) do
        if row.controlId and row.controlId:find("sync.module.", 1, true) then found[row.label] = true end
    end
    assert(found[M.Tr("Unitframes")] and found[M.Tr("Class Resources")], "sync search labels differ from page labels")
    assert(not found.unitframes and not found.resources, "raw module IDs leaked into translated search")
else error(mode) end
print("search regression " .. mode .. ": PASS")
