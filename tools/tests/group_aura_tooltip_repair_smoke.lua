-- group_aura_tooltip_repair_smoke.lua <repoRoot> <flavor> [repairSource]
-- Real cold repair, compiled lane readers, invalidation and History providers.
-- The optional source is only a private red-before/green-after load override.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local target = "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Migrations.lua"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local loaded = 0
local mw = MenuWorld.Open(root, flavor, { keepFlush = true, beforeCore = function(world)
    local load = world.LoadFile
    world.LoadFile = function(self, path, addon, namespace)
        if path:gsub("\\", "/") == root .. "/" .. target then
            loaded = loaded + 1
            if arg[3] and arg[3] ~= "-" then path = arg[3] end
        end
        return load(self, path, addon, namespace)
    end
end })
assert(loaded == 1, "exact real Group DB repair source was not loaded once")
local M, env, core = mw.M, mw.env, mw.core
local GF, A3, F = core.GF, core.MSUF_Auras3, core.ProfileFields
local Model = A3.MenuModel
local scopes = { "party", "raid", "mythicraid" }
local lanes = { { "buff", "buff" }, { "debuff", "debuff" }, { "externals", "external" } }
local factory = assert(core.MSUF_CreateCanonicalGroupAuraState)
local function Copy(value) return assert(F.CopySnapshot(value)) end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Restore(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            Restore(dst[key], value)
        else dst[key] = value end
    end
end
local originalFactory = factory(true)
local factorySnapshot = Copy(originalFactory)
local secondFactory = factory(true)
local factoryLanes = {}
assert(originalFactory ~= secondFactory, "canonical factory reused its root table")
for _, scope in ipairs(scopes) do
    local key = "gf_" .. scope
    assert(originalFactory[key] ~= secondFactory[key]
        and originalFactory[key].auras ~= secondFactory[key].auras, "canonical factory reused a scope")
    for _, lane in ipairs(lanes) do
        assert(not factoryLanes[originalFactory[key].auras[lane[1]]], "canonical factory shared two lane tables")
        factoryLanes[originalFactory[key].auras[lane[1]]] = true
        assert(originalFactory[key].auras[lane[1]] ~= secondFactory[key].auras[lane[1]],
            "canonical factory reused a lane table")
        assert(originalFactory[key].auras[lane[1]].showTooltip == true,
            "fresh canonical factory tooltip default changed")
    end
end
local function FactoryUnchanged()
    assert(Same(originalFactory, factorySnapshot), "repair polluted a previously returned factory state")
    assert(Same(factory(true), factorySnapshot), "repair polluted later canonical factory defaults")
end
-- Complete unrelated cold providers before constructing each sparse test case.
A3.EnsureDB()
GF.EnsureDB()
mw:RunTimers()
local db = env.MSUF_DB
local pristine = Copy(db)
local cases, styleCases, historyCases = 0, 0, 0
local function CheckRaw(scope, expectedRoot, expectedLane, tag)
    local auras = db["gf_" .. scope].auras
    assert(rawget(auras, "showTooltip") == expectedRoot, tag .. ": raw root tooltip changed")
    for _, lane in ipairs(lanes) do
        assert(rawget(auras[lane[1]], "showTooltip") == expectedLane,
            tag .. ": raw lane tooltip changed: " .. lane[1])
    end
end
local function CheckReaders(scope, expectedRoot, expectedLane, tag)
    GF.InvalidateCompiledSpecs(scope)
    local spec = GF.CompileSpec(scope)
    assert(spec.auras.showTooltip == (expectedRoot ~= false), tag .. ": compiled root tooltip changed")
    local frame = env.CreateFrame("Frame", nil, env.UIParent)
    frame._msufIsGroupFrame, frame._msufGFIsPreviewFrame = true, true
    frame._msufGFKind, frame.MSUFUnitKey, frame.MSUFSpec = scope, "party1", spec
    local compiled = assert(A3.ResolveAuraPreviewConfig(frame, "party1", spec))
    for _, lane in ipairs(lanes) do
        local expectedOverride
        if expectedLane ~= nil then expectedOverride = expectedLane == true end
        assert(spec.auras[lane[2] .. "ShowTooltip"] == expectedOverride,
            tag .. ": compiled lane override/absence changed: " .. lane[1])
        local effective = expectedRoot ~= false
        if expectedLane ~= nil then effective = expectedLane == true end
        assert(compiled.lanes[lane[2]].showTooltip == effective,
            tag .. ": real runtime inherited tooltip changed: " .. lane[1])
    end
    CheckRaw(scope, expectedRoot, expectedLane, tag .. ":after-read")
end
for _, scope in ipairs(scopes) do
    for _, rootCase in ipairs({ { "false", false }, { "true", true }, { "absent" } }) do
        for _, laneCase in ipairs({ { "absent" }, { "true", true }, { "false", false }, { "zero", 0 } }) do
            Restore(db, pristine)
            local auras = db["gf_" .. scope].auras
            auras.showTooltip = rootCase[2]
            for _, lane in ipairs(lanes) do auras[lane[1]].showTooltip = laneCase[2] end
            local expected = Copy(db)
            local expectedRoot = rootCase[2]
            if expectedRoot == nil then expectedRoot = true end
            local expectedLane = laneCase[2]
            if expectedLane == nil and rootCase[2] ~= false then expectedLane = true end
            expected["gf_" .. scope].auras.showTooltip = expectedRoot
            for _, lane in ipairs(lanes) do expected["gf_" .. scope].auras[lane[1]].showTooltip = expectedLane end
            local tag = flavor .. ":" .. scope .. ":root-" .. rootCase[1] .. ":lane-" .. laneCase[1]
            GF.RepairGroupDB(db)
            CheckRaw(scope, expectedRoot, expectedLane, tag .. ":cold")
            assert(Same(expected, db), tag .. ": cold repair changed another profile field")
            GF.InvalidateConfCache()
            GF.EnsureDB()
            CheckRaw(scope, expectedRoot, expectedLane, tag .. ":invalidated")
            assert(Same(expected, db), tag .. ": invalidated repair changed another profile field")
            CheckReaders(scope, expectedRoot, expectedLane, tag)
            assert(Same(expected, db), tag .. ": real readers changed the raw profile")
            GF.InvalidateConfCache()
            GF.EnsureDB()
            assert(Same(expected, db), tag .. ": repeated repair was not idempotent")
            FactoryUnchanged()
            cases = cases + 1
        end
    end
end
-- A missing Spell Indicator tooltip is derived from the existing buff/root
-- inheritance reader; stored true/false must not be rewritten.
for _, scope in ipairs(scopes) do
    for _, styleCase in ipairs({ { "missing-table" }, { "missing-field" }, { "true", true }, { "false", false } }) do
        local conf = factory(true)["gf_" .. scope]
        conf.auras.showTooltip = false
        for _, lane in ipairs(lanes) do conf.auras[lane[1]].showTooltip = nil end
        if styleCase[1] ~= "missing-table" then conf.spellIndicators.style = { showTooltip = styleCase[2] } end
        local expected = styleCase[2]
        if expected == nil then expected = false end
        GF.MigrateAuraConfig(conf, scope ~= "party")
        assert(conf.spellIndicators.style.showTooltip == expected,
            "missing SI tooltip did not inherit root false or stored SI override changed: " .. styleCase[1])
        for _, lane in ipairs(lanes) do
            assert(rawget(conf.auras[lane[1]], "showTooltip") == nil, "SI repair filled inherited raw lane tooltip")
        end
        local style = Copy(conf.spellIndicators.style)
        GF.MigrateAuraConfig(conf, scope ~= "party")
        assert(Same(style, conf.spellIndicators.style), "repeated repair changed the derived/stored SI style")
        FactoryUnchanged()
        styleCases = styleCases + 1
    end
end
-- Actual group History + blacklist model boundary; native Add/Click and all159 page
-- oracles stay in the separate unchanged Group Aura Style parity smoke.
for _, scope in ipairs(scopes) do
    for _, lane in ipairs({ "buff", "debuff" }) do
        Restore(db, pristine)
        GF.InvalidateConfCache()
        GF.EnsureDB()
        local auras = db["gf_" .. scope].auras
        auras.showTooltip = false
        for _, inherited in ipairs(lanes) do auras[inherited[1]].showTooltip = nil end
        assert(rawget(auras[lane].blacklist.spells, "1459") == nil, "history fixture already blocked spell1459")
        M.ClearHistory()
        local before = Copy(db)
        assert(M.CaptureHistory("Group Aura Tooltip Repair", "group:" .. scope .. ":tooltip-repair", function()
            return Model.AddGroupBlacklistSpell(scope, lane, "1459")
        end) == true, "real blacklist model/history input was refused")
        M.ApplyService.RequestGroup(scope, "visual", "GROUP_AURA_TOOLTIP_REPAIR")
        mw:RunTimers()
        local after = Copy(db)
        assert(auras[lane].blacklist.spells["1459"] == true, "real blacklist model did not add spell1459")
        assert(not Same(before, after), "real blacklist history case did not mutate the profile")
        local entry = M.historyUndo[#M.historyUndo]
        assert(entry and #M.historyRedo == 0, "real blacklist edit did not create Undo")
        assert(M.Undo() == true, "real blacklist Undo was refused")
        mw:RunTimers()
        CheckRaw(scope, false, nil, "history-undo")
        assert(Same(before, db), "whole profile Undo changed inherited raw nil tooltip or another field")
        assert(#M.historyUndo == 0 and #M.historyRedo == 1 and M.historyRedo[1] == entry,
            "real Undo did not preserve the pending Redo entry")
        CheckReaders(scope, false, nil, "history-undo")
        assert(Same(before, db), "Undo readback mutated the raw profile")
        assert(M.Redo() == true, "real blacklist Redo was refused")
        mw:RunTimers()
        CheckRaw(scope, false, nil, "history-redo")
        assert(Same(after, db), "whole profile Redo changed inherited raw nil tooltip or another field")
        assert(#M.historyRedo == 0 and #M.historyUndo == 1 and M.historyUndo[1] == entry,
            "real Redo did not restore the same history entry")
        CheckReaders(scope, false, nil, "history-redo")
        assert(Same(after, db), "Redo readback mutated the raw profile")
        FactoryUnchanged()
        historyCases = historyCases + 1
    end
end
assert(cases == 36 and styleCases == 12 and historyCases == 6, "tooltip repair case census changed")
print("group aura tooltip repair smoke passed: " .. flavor .. " / " .. cases .. " policy cases / " .. styleCases .. " SI cases / " .. historyCases .. " history cases")
