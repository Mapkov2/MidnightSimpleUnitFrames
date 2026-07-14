-- Read-only desktop audit for persisted nested state and ordered-list controls
-- that the scalar AutoCoverage manifest intentionally does not publish.
--
-- Usage:
--   lua tools/assistant_nested_persisted_state_audit.lua
--   lua tools/assistant_nested_persisted_state_audit.lua --require-complete

_G = _G or _ENV
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path

require("wow_stubs")
local Loader = require("assistant_runtime_manifest_loader")
local MSUF = assert(_G.MSUF_NS, "WoW stubs did not create MSUF_NS")

local function LoadProduct(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
    assert(ok, path .. ": " .. tostring(result))
end

LoadProduct("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
assert(type(_G.MSUF_EnsureDB) == "function", "MSUF defaults did not export MSUF_EnsureDB")
assert(type(_G.MSUF_EnsureDB(true)) == "table", "MSUF defaults did not seed a profile")
LoadProduct("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
assert(MSUF.GF and type(MSUF.GF.EnsureDB) == "function", "Group Frame defaults did not load")
local groupOK, groupError = pcall(MSUF.GF.EnsureDB)
assert(groupOK, groupError)

Loader.LoadAssistantRuntime(MSUF, {
    root = ".",
    includeDashboard = true,
    includeDialogLocale = true,
    useCompanionPrivate = true,
})
local A = assert(MSUF.Assistant, "Assistant runtime did not load")
local Registry = assert(A.Registry, "Assistant Registry did not load")
assert(A.AutoCoverage and type(A.AutoCoverage.Fill) == "function", "AutoCoverage did not load")
A.AutoCoverage.Fill()
LoadProduct("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarChannelTicks.lua")

local function SplitPath(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^.]+") do parts[#parts + 1] = part end
    return parts
end

local function PathValue(path)
    local parts = SplitPath(path)
    local value = _G.MSUF_DB
    for i = 1, #parts do
        if type(value) ~= "table" then return nil, false end
        value = value[parts[i]]
        if value == nil then return nil, false end
    end
    return value, true
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do if not Equal(value, right[key], seen) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function SettingDeclaredTargets(setting)
    local targets, seen = {}, {}
    local function Add(scope, dbKey)
        scope, dbKey = tostring(scope or ""), tostring(dbKey or "")
        local path = scope ~= "" and dbKey ~= "" and (scope .. "." .. dbKey) or ""
        if path ~= "" and not seen[path] then seen[path], targets[#targets + 1] = true, path end
    end
    local key = tostring(setting and setting.key or "")
    local scope, dbKey = key:match("^([^.]+)%.(.+)$")
    if scope and dbKey then Add(scope, dbKey) end
    for i = 1, #(type(setting and setting.dbScopes) == "table" and setting.dbScopes or {}) do
        local row = setting.dbScopes[i]
        Add(type(row) == "table" and (row.scope or row[1]),
            type(row) == "table" and (row.dbKey or row.key or row[2]))
    end
    return targets
end

local ownersByPath = {}
for _, setting in ipairs(Registry:AllSettings() or {}) do
    local targets = SettingDeclaredTargets(setting)
    for i = 1, #targets do
        local path = targets[i]
        local owners = ownersByPath[path]
        if not owners then owners = {}; ownersByPath[path] = owners end
        owners[#owners + 1] = setting
    end
end

local targets = {
    { path = "general.minimapIconDB.hide", class = "mirror", expected = "boolean" },
    { path = "general.minimapIconDB.minimapPos", class = "public", expected = "number" },
    { path = "general.minimapIconDB.radius", class = "dependency", expected = "number" },
    { path = "general.UIScale.Scale", class = "public", expected = "number" },
    { path = "general.UIScale.Enabled", class = "public", expected = "boolean" },
    { path = "player.castbar.channelTickUseCustom", class = "public", expected = "boolean" },
    { path = "player.castbar.channelTickCount", class = "public", expected = "number" },
    { path = "player.castbar.channelTickPosPct", class = "public_order", expected = "table" },
    { path = "player.castbar.channelTickPreviewDuration", class = "retired", expected = "number" },
    { path = "player.castbar.channelTickPreviewLoop", class = "retired", expected = "boolean" },
    { path = "gf_party.roleOrder", class = "public_order", expected = "string" },
    { path = "gf_raid.roleOrder", class = "public_order", expected = "string" },
    { path = "gf_mythicraid.roleOrder", class = "public_order", expected = "string" },
}

local highlightScopes = {
    "general", "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
    "gf_party", "gf_raid", "gf_mythicraid",
}
for i = 1, #highlightScopes do
    targets[#targets + 1] = {
        path = highlightScopes[i] .. ".hlPrioOrder",
        class = "public_order",
        expected = "table",
        optional = true,
    }
end
targets[#targets + 1] = {
    path = "general.highlightPrioOrder",
    class = "legacy_mirror",
    expected = "table",
    optional = true,
}

local blockers, blockerSet = {}, {}
local function Block(code, path, detail)
    local id = tostring(code) .. "|" .. tostring(path)
    if blockerSet[id] then return end
    blockerSet[id] = true
    blockers[#blockers + 1] = { code = code, path = path, detail = detail }
end

for i = 1, #targets do
    local target = targets[i]
    local value, exists = PathValue(target.path)
    if exists then
        assert(type(value) == target.expected,
            target.path .. " changed type from " .. target.expected .. " to " .. type(value))
    elseif not target.optional and target.class ~= "retired" then
        error(target.path .. " is no longer persisted by the current defaults")
    end
    local owners = ownersByPath[target.path] or {}
    local ownerKeys = {}
    for j = 1, #owners do ownerKeys[#ownerKeys + 1] = tostring(owners[j].key or "") end
    table.sort(ownerKeys)
    print(table.concat({
        "PATH", target.path, "class=" .. target.class, "persisted=" .. tostring(exists),
        "type=" .. (exists and type(value) or "implicit"),
        "owners=" .. (#ownerKeys > 0 and table.concat(ownerKeys, ",") or "none"),
    }, "\t"))

    if target.class == "public" or target.class == "public_order" or target.class == "mirror" then
        if #owners == 0 then Block("missing_owner", target.path, "no Registry setting declares this physical target") end
    elseif target.class == "legacy_mirror" then
        if #owners == 0 then Block("missing_mirror_owner", target.path, "legacy runtime fallback is not claimed by a canonical owner") end
    elseif target.class == "retired" and exists then
        Block("retired_state_still_seeded", target.path, "field has no runtime consumer but remains in every profile")
    end
end

-- Prove that the visible minimap setting owns behavior but does not declare its
-- nested mirror, while ordinary value-based undo restores both physical fields.
do
    local setting = assert(Registry:GetSetting("general.showMinimapIcon"), "minimap setting missing")
    local general = _G.MSUF_DB.general
    general.showMinimapIcon, general.minimapIconDB.hide = true, false
    setting.set(false)
    assert(general.showMinimapIcon == false and general.minimapIconDB.hide == true,
        "minimap setting stopped synchronizing its hide mirror")
    setting.set(true)
    assert(general.showMinimapIcon == true and general.minimapIconDB.hide == false,
        "minimap setting value undo no longer restores its hide mirror")
end

local function ScaleSnapshot()
    local general = _G.MSUF_DB.general
    return Copy({
        UIScale = general.UIScale,
        preset = general.globalUiScalePreset,
        value = general.globalUiScaleValue,
    })
end

-- UI-scale settings own a four-field workflow. Prove their explicit
-- transaction snapshots restore the exact pre-write state rather than merely
-- writing get() back and losing the preset identity.
do
    local setting = assert(Registry:GetSetting("general.globalUiScale"), "global scale setting missing")
    assert(type(setting.captureTransactionState) == "function"
        and type(setting.restoreTransactionState) == "function",
        "global scale setting lacks compound transaction hooks")
    local general = _G.MSUF_DB.general
    general.UIScale = { Enabled = false, Scale = 0.9 }
    general.globalUiScalePreset, general.globalUiScaleValue = "auto", nil
    local transaction = setting.captureTransactionState()
    local before = ScaleSnapshot()
    setting.set(0.75)
    local restored = setting.restoreTransactionState(transaction, "AUDIT")
    if restored ~= true or not Equal(before, ScaleSnapshot()) then
        Block("incomplete_transaction_snapshot", setting.key,
            "compound undo did not restore UIScale and preset mirrors exactly")
    end
end

do
    local setting = assert(Registry:GetSetting("general.globalUiScaleEnabled"), "global scale enabled setting missing")
    assert(type(setting.captureTransactionState) == "function"
        and type(setting.restoreTransactionState) == "function",
        "global scale enabled setting lacks compound transaction hooks")
    local general = _G.MSUF_DB.general
    general.UIScale = { Enabled = true, Scale = 768 / 1440 }
    general.globalUiScalePreset, general.globalUiScaleValue = "1440p", 768 / 1440
    local transaction = setting.captureTransactionState()
    local before = ScaleSnapshot()
    setting.set(false)
    local restored = setting.restoreTransactionState(transaction, "AUDIT")
    if restored ~= true or not Equal(before, ScaleSnapshot()) then
        Block("incomplete_transaction_snapshot", setting.key,
            "compound undo did not restore UIScale and preset mirrors exactly")
    end
end

-- Role ordering is the positive control: six closed permutations, one setting
-- per physical Group Frame scope, and lossless typed read/write behavior.
for _, scope in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
    local key = scope .. ".roleOrder"
    local setting = assert(Registry:GetSetting(key), key .. " setting missing")
    assert(setting.type == "enum" and #(setting.values or {}) == 6, key .. " domain is not six closed permutations")
    local before = setting.get()
    setting.set("DAMAGER,TANK,HEALER")
    assert(setting.get() == "DAMAGER,TANK,HEALER" and _G.MSUF_DB[scope].roleOrder == "DAMAGER,TANK,HEALER",
        key .. " did not round-trip through its typed owner")
    setting.set(before)
    assert(setting.get() == before, key .. " value undo did not restore the prior order")
end

-- Highlight priority is a four-item closed permutation with one logical owner
-- per visible Bars scope. Raid deliberately owns both raid physical tables.
local highlightOwnerScopes = {
    "shared", "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
    "gf_party", "gf_raid",
}
local function HighlightPhysicalScopes(scope)
    if scope == "shared" then return { "general" } end
    if scope == "gf_raid" then return { "gf_raid", "gf_mythicraid" } end
    return { scope }
end
for i = 1, #highlightOwnerScopes do
    local scope = highlightOwnerScopes[i]
    local key = "barScope." .. scope .. ".hlPrioOrder"
    local setting = assert(Registry:GetSetting(key), key .. " setting missing")
    assert(setting.type == "enum" and #(setting.values or {}) == 24,
        key .. " domain is not all 24 closed permutations")
    assert(type(setting.captureTransactionState) == "function"
        and type(setting.restoreTransactionState) == "function",
        key .. " lacks ordered-state transaction hooks")
    local beforeValue = setting.get()
    local transaction = setting.captureTransactionState()
    local nextValue = beforeValue == setting.values[1] and setting.values[2] or setting.values[1]
    setting.set(nextValue)
    assert(setting.get() == nextValue, key .. " did not round-trip its canonical order")
    local expected = {}
    for token in nextValue:gmatch("[^,]+") do expected[#expected + 1] = token end
    local physical = HighlightPhysicalScopes(scope)
    for j = 1, #physical do
        local owner = assert(_G.MSUF_DB[physical[j]], key .. " physical scope missing")
        assert(Equal(owner.hlPrioOrder, expected), key .. " did not write " .. physical[j])
    end
    if scope == "shared" then
        assert(Equal(_G.MSUF_DB.general.highlightPrioOrder, expected),
            key .. " did not synchronize its legacy mirror")
    end
    assert(setting.restoreTransactionState(transaction, "AUDIT") == true,
        key .. " transaction restore failed")
    assert(setting.get() == beforeValue, key .. " transaction restore changed its effective value")
end

do
    local preset = Registry:GetSetting("general.globalUiScalePreset")
    if preset and preset.generated == true then
        Block("dependency_exposed_as_generated", preset.key,
            "preset is a mirror of the curated scale workflow, not an independent public setting")
    end
    local legacy = Registry:GetSetting("general.disableScaling")
    if legacy and legacy.generated == true and legacy.assistantMutationSafe == true then
        Block("retired_flag_mutable", legacy.key,
            "migration-only compatibility flag is exposed as a writable generated boolean")
    end
end

-- The visible/global tick toggle is not authoritative when the hidden custom
-- switch is true. Prove the current semantic mismatch: a successful "off"
-- write can leave runtime tick lines enabled.
do
    local setting = assert(Registry:GetSetting("general.castbarShowChannelTicks"),
        "global channel tick setting missing")
    local general, castbar = _G.MSUF_DB.general, _G.MSUF_DB.player.castbar
    general.castbarShowChannelTicks = true
    castbar.channelTickUseCustom, castbar.channelTickCount = true, 3
    setting.set(false)
    local effective = type(_G.MSUF_IsChannelTickLinesEnabled) == "function"
        and _G.MSUF_IsChannelTickLinesEnabled()
    if effective == true then
        Block("shadowed_public_setting", setting.key,
            "setting reports off while hidden player.castbar.channelTickUseCustom keeps runtime ticks on")
    end
    castbar.channelTickUseCustom = false
end

table.sort(blockers, function(left, right)
    if left.path == right.path then return left.code < right.code end
    return left.path < right.path
end)
for i = 1, #blockers do
    local row = blockers[i]
    print(table.concat({ "BLOCKER", row.code, row.path, row.detail }, "\t"))
end
print(string.format("SUMMARY\tpaths=%d\tblockers=%d\troleOrderOwners=3\tmode=read-only",
    #targets, #blockers))

local requireComplete = false
for i = 1, #(arg or {}) do if arg[i] == "--require-complete" then requireComplete = true end end
if requireComplete and #blockers > 0 then os.exit(2) end
