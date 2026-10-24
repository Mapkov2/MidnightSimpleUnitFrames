-- aura_menu_canonical_revision_smoke.lua <repoRoot> <flavor> [storageSource]
-- Real factory/core/menu storage and History; offline profile-contract evidence.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local target = "MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Storage.lua"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local loaded = 0
local mw = MenuWorld.Open(root, flavor, { open = false, keepFlush = true, beforeCore = function(world)
    local load = world.LoadFile
    world.LoadFile = function(self, path, addon, namespace)
        if path:gsub("\\", "/") == root .. "/" .. target then
            loaded = loaded + 1
            if arg[3] and arg[3] ~= "-" then path = arg[3] end
        end
        return load(self, path, addon, namespace)
    end
end })
assert(loaded == 1, "real Aura menu storage was not loaded exactly once")
-- Complete only work already queued while the real client graph booted.
-- Every factory tree under test is created after this startup boundary.
assert(mw:RunTimers() > 0 and #mw.world.widgets.timers == 0, "real world startup timers did not complete")
local M, env, core = mw.M, mw.env, mw.core
local A3, F = core.MSUF_Auras3, core.ProfileFields
local Model, factory = A3.MenuModel, assert(core.MSUF_CreateCanonicalUnitAuras)
local classic = core.Client.IsClassic == true
local function Copy(value) return assert(F.CopySnapshot(value)) end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function RawEqual(expected, label)
    assert(Same(expected, env.MSUF_DB), flavor .. ":" .. label .. ": canonical model read changed raw DB")
end
local fresh = factory()
assert(fresh.profileModelRevision == (classic and 1 or 2), "actual per-client canonical factory revision drift")
assert(fresh._msufA3UnitLaneOwners_v1 == true, "actual canonical lane owners missing")
local factoryBefore = Copy(fresh)
local revisions = {
    { "number1", 1 }, { "number2", 2 }, { "string1", "1" }, { "string2", "2" },
    { "string01", "01" }, { "false", false }, { "zero", 0 }, { "nil" }, { "invalid", "broken" },
}
local cases, canonicalCases, legacyCases, historyCases = 0, 0, 0, 0
for _, revision in ipairs(revisions) do
    for _, state in ipairs({ "plain", "false-zero-nil", "retired-visual" }) do
        local label = revision[1] .. ":" .. state
        local aura = factory()
        env.MSUF_DB.auras3 = aura
        aura.profileModelRevision = revision[2]
        -- The real canonical owner marker keeps these supplied raw revision controls
        -- available to the real core; no profile version or migration is faked.
        A3.EnsureDB()
        assert(Same(aura.profileModelRevision, revision[2]), "core changed supplied raw revision control: " .. label)
        local shared, owner = aura.shared, aura.perUnit.player
        shared.buffShowTooltip, shared.buffCooldownTextSize = nil, nil
        shared._msufA3_debuffTypeBorderModeMigrated_v1 = nil
        for _, unit in pairs(aura.perUnit) do unit._msufA3SparseVisualOverrides_v2 = nil end
        if state ~= "plain" then
            shared.buffShowTooltip, shared.buffCooldownTextSize = false, 0
            shared.buffOffsetX = nil
            owner.overrideStyle = false
            owner.layout.iconZoom, owner.layoutShared.showTooltip = 0, false
        end
        if state == "retired-visual" then
            shared.styleScopeDisabled, shared.iconShapeFollowSharedScopes = true, false
            shared.offsetX, owner.layout.offsetX = 0, 0
            owner.layout.iconSize = 26
            owner.overrideLayout, owner.overrideSharedLayout = true, true
            local keys = 0
            for key in pairs(A3.LaneKeySchema.LAYOUT_KEYS) do if owner.layout[key] ~= nil then keys = keys + 1 end end
            assert(keys >= 10 and owner.layout.buffGroupIconSize ~= nil and owner.layout.debuffGroupIconSize ~= nil,
                "actual visual control does not reach the original sparse-override normalizer")
        end
        shared.unknownCanonicalProbe = { enabled = false, amount = 0 }
        local before = Copy(env.MSUF_DB)
        local expected = Copy(before)
        -- Preserve the existing retirement policy, precisely these two old fields.
        expected.auras3.shared.styleScopeDisabled = nil
        expected.auras3.shared.iconShapeFollowSharedScopes = nil
        local revisionNumber = tonumber(revision[2])
        local canonical = revisionNumber == 2 or (classic and revisionNumber == 1)
        local actual, actualShared = Model.EnsureDB()
        assert(actual == aura and actualShared == shared, "storage replaced the real profile owner")
        assert(Same(aura.profileModelRevision, revision[2]), "menu storage rewrote raw revision: " .. label)
        assert(shared.styleScopeDisabled == nil and shared.iconShapeFollowSharedScopes == nil,
            "existing exact retired-field policy changed")
        if canonical then
            canonicalCases = canonicalCases + 1
            RawEqual(expected, label)
            assert(shared._msufA3_debuffTypeBorderModeMigrated_v1 == nil
                and owner._msufA3SparseVisualOverrides_v2 == nil, "canonical read seeded a legacy marker")
            Model.InvalidateDefaultSeedCache()
            Model.EnsureDB()
            RawEqual(expected, label .. ":invalidated")
            Model.EnsureDB()
            RawEqual(expected, label .. ":repeat")
            M.ClearHistory()
            local prior = Copy(env.MSUF_DB)
            M.CaptureHistory("Cold Aura menu storage", "button:canonical-aura-storage", function() Model.EnsureDB() end)
            mw:RunTimers()
            RawEqual(prior, label .. ":history-capture")
            local undo = M.Undo()
            mw:RunTimers()
            local redo = M.Redo()
            mw:RunTimers()
            assert(not undo and not redo and #M.historyUndo == 0 and #M.historyRedo == 0,
                "canonical model read entered real profile history")
            RawEqual(prior, label .. ":history-settled")
            historyCases = historyCases + 1
        else
            legacyCases = legacyCases + 1
            assert(shared._msufA3_debuffTypeBorderModeMigrated_v1 == true
                and owner._msufA3SparseVisualOverrides_v2 == true, "genuine legacy revision skipped existing migrations")
            assert(shared.buffShowTooltip == (state == "plain") and shared.buffCooldownTextSize == (state == "plain" and 14 or 0),
                "legacy default/explicit false-zero semantics changed")
            if state == "retired-visual" then
                assert(owner.layout.offsetX == nil and owner.overrideStyle == false,
                    "genuine legacy visual-override cleanup changed")
            end
            local settled = Copy(env.MSUF_DB)
            Model.InvalidateDefaultSeedCache()
            Model.EnsureDB()
            RawEqual(settled, label .. ":legacy-idempotent")
        end
        assert(shared.unknownCanonicalProbe.enabled == false and shared.unknownCanonicalProbe.amount == 0,
            "unknown false-zero extension changed")
        if state ~= "plain" then
            assert(owner.layout.iconZoom == 0 and owner.layoutShared.showTooltip == false
                and owner.overrideStyle == false, "explicit visual false-zero was lost")
        end
        cases = cases + 1
    end
end
assert(cases == 27 and canonicalCases == (classic and 15 or 6)
    and legacyCases == (classic and 12 or 21) and historyCases == canonicalCases, "revision/control census drift")
assert(Same(fresh, factoryBefore) and Same(factory(), factoryBefore), "menu repair polluted the canonical factory")
print("aura_menu_canonical_revision_smoke passed: " .. flavor .. " / 27 raw revision cases / " .. historyCases .. " real History controls")
