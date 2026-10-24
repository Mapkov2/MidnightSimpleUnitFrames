-- V2 retention at the real 6.50 migration boundaries, not a full downgrade promise.
-- Frozen sources below come from the read-only 6.50 checkout, 2026-10-24.
-- Optional arg2 verifies every excerpt against that checkout before executing it.
local root, legacyRoot = assert(arg[1]), arg[2]
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end

-- MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Bars.lua SHA256 4a6bad8c7570ce63604f5ed2ffd88c66fb4c51e3473073f51bc78dc2ca67fe16
local barsSource = [=[
    if g.absorbBarColorMigrationV2 ~= true then
        g.absorbBarColorMigrationV2 = true
        g.absorbColorR,        g.absorbColorG,        g.absorbColorB,        g.absorbColorA        = nil, nil, nil, nil
        g.healAbsorbColorR,    g.healAbsorbColorG,    g.healAbsorbColorB,    g.healAbsorbColorA    = nil, nil, nil, nil
        g.absorbBarColorR,     g.absorbBarColorG,     g.absorbBarColorB,     g.absorbBarColorA     = nil, nil, nil, nil
        g.healAbsorbBarColorR, g.healAbsorbBarColorG, g.healAbsorbBarColorB, g.healAbsorbBarColorA = nil, nil, nil, nil
    end
]=]

-- MidnightSimpleUnitFrames/State/MSUF_Defaults.lua SHA256 13552fda55b7bde054bb252d071d531600d4cd3793bf26cb156c42a769d41f81
local dispelSource = [=[
local MSUF_DEFAULTS_UNIT_DISPEL_KEYS = {
    "unitDispelOverlayEnabled", "unitDispelOverlayStyle", "unitDispelOverlayOnHealth",
    "unitDispelOverlayAlpha", "unitDispelOverlayTrigger",
    "unitDispelSymbolEnabled", "unitDispelSymbolStyle", "unitDispelSymbolMode",
    "unitDispelSymbolTrigger", "unitDispelSymbolSize", "unitDispelSymbolSpacing",
    "unitDispelSymbolGrowth", "unitDispelSymbolAnchor", "unitDispelSymbolX",
    "unitDispelSymbolY", "unitDispelSymbolAlpha", "unitDispelSymbolLayer",
    "unitDispelSymbolStrata",
}

local function MSUF_Defaults_MigrateUnitDispelOwnership(db)
    if type(db) ~= "table" then return end
    local general = type(db.general) == "table" and db.general or {}
    if (tonumber(general.unitDispelOwnershipVersion) or 0) >= 1 then return end
    for _, unitKey in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local conf = type(db[unitKey]) == "table" and db[unitKey] or {}
        db[unitKey] = conf
        local usedUnitBars = conf.hlOverride == true
        for _, key in ipairs(MSUF_DEFAULTS_UNIT_DISPEL_KEYS) do
            -- Snapshot the value the old Bars-scoped compiler actually used.
            -- This deliberately replaces stale unit values hidden behind a
            -- disabled Bars override, preserving appearance during the split.
            local value
            if usedUnitBars then value = conf[key] end
            if value == nil then value = general[key] end
            if value ~= nil then conf[key] = value end
        end
    end
    -- This is intentionally a portable profile field, not a private _msuf key:
    -- exports strip private metadata, and replaying this flattening after an
    -- import would overwrite the independent per-unit choices it just created.
    general.unitDispelOwnershipVersion = 1
end
]=]

-- MidnightSimpleUnitFrames/State/MSUF_Defaults.lua SHA256 13552fda55b7bde054bb252d071d531600d4cd3793bf26cb156c42a769d41f81
local guardSource = [=[
local function MSUF_Defaults_IsCurrentProfileDB(db)
    if type(db) ~= "table"
        or tonumber(db._msufProfileSchema) ~= MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
        or tonumber(db._msufDefaultsRevision) ~= MSUF_DEFAULTS_CURRENT_REVISION then
        return false
    end
    --- Keep the fast path safe for truncated/malformed SavedVariables. Nested
    --- value validation belongs to imports (which force EnsureDB), while these
    --- root tables are the minimum runtime contract for a stored profile.
    for i = 1, #MSUF_DEFAULTS_ROOT_TABLE_KEYS do
        if type(db[MSUF_DEFAULTS_ROOT_TABLE_KEYS[i]]) ~= "table" then
            return false
        end
    end
    --- A stamped profile saved by an import that failed half way can still
    --- carry a scalar aura root or owner; the heavy pass repairs both.
    local auras = db.auras3
    if type(auras) ~= "table" then return false end
    if type(auras.perUnit) == "table" then
        for _, owner in pairs(auras.perUnit) do
            if type(owner) ~= "table" then return false end
        end
    end
    local g = db.general
    if type(g.fontKey) ~= "string" or g.fontKey == ""
        or db.shortenNames == nil
        or db.bars.barBackgroundAlpha == nil
        or db.gameplay.enableCombatTimer == nil
        or (g.barBgFillMode ~= "full" and g.barBgFillMode ~= "missing")
        or (g.barBgColorMode ~= "custom" and g.barBgColorMode ~= "match_health"
            and g.barBgColorMode ~= "class" and g.barBgColorMode ~= "health_gradient") then
        return false
    end
    return true
end
]=]

-- MidnightSimpleUnitFrames/State/MSUF_Defaults.lua SHA256 13552fda55b7bde054bb252d071d531600d4cd3793bf26cb156c42a769d41f81
local rootsSource = [=[
local MSUF_DEFAULTS_ROOT_TABLE_KEYS = {
    "general",
    "classColors",
    "npcColors",
    "bars",
    "gameplay",
    "player",
    "target",
    "targettarget",
    "focustarget",
    "focus",
    "pet",
    "pettarget",
    "boss",
    "arena",
}
]=]

-- MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Migrations.lua SHA256 896e0436ebc96485d35717aa18a5dfa78e9e0e8eec1793d0fb9c542571ec9688
local aurasSource = [=[
local function RepairAuraV2(conf)
    if type(conf.auras) == "table"
        and tonumber(conf.auras.profileModelRevision) ~= GF_AURA_PROFILE_MODEL_REVISION
        and not conf._auraMigV2 then
        conf._auraMigV2 = true
        if conf.auras.enabled == false or conf.auras.enabled == nil then
            conf.auras.enabled = true
        end
        local ext = conf.auras.externals
        if type(ext) == "table" and not ext.enabled then
            ext.enabled = true
        end
    end
end
]=]

-- MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Geometry.lua SHA256 deb560425c7febbf76be33b47c0d6aeca802b63e8b9660416b3fd2b2e154d5a6
local positionSource = [=[
function GF.EnsureStableGridPosition(kind, count, conf, preservedGroupCount)
    conf = conf or (GF.GetConf and GF.GetConf(kind))
    if type(conf) ~= "table" then return false end
    if conf.positionMode == STABLE_GRID_POSITION_MODE then return false end
    if conf.positionMode ~= LEGACY_GRID_POSITION_MODE then return false end

    -- Undo exactly the delta the legacy stamp added. Whoever converts first
    -- (live header, Edit Mode, preview) otherwise supplies a different count
    -- than the migration did, and the difference is written to disk for good.
    local pinnedCount = tonumber(conf.positionMigrationCount)
    local dx, dy = conf.positionMigrationDX, conf.positionMigrationDY
    if type(dx) ~= "number" or type(dy) ~= "number" then
        dx, dy = GF.GetGridMetrics(kind, pinnedCount or count, preservedGroupCount)
    end
    local fallbackX = IsRaidLikeKind(kind) and -500 or -400
    conf.offsetX = (tonumber(conf.offsetX) or fallbackX) - (tonumber(dx) or 0)
    conf.offsetY = (tonumber(conf.offsetY) or 0) - (tonumber(dy) or 0)
    conf.positionMode = STABLE_GRID_POSITION_MODE
    conf.positionMigrationCount = nil
    conf.positionMigrationDX, conf.positionMigrationDY = nil, nil
    return true
end
]=]

if legacyRoot then
    assert(Read(legacyRoot .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Bars.lua"):find(barsSource:gsub("\n$", ""), 1, true), "legacy source drift: barsSource")
    assert(Read(legacyRoot .. "/MidnightSimpleUnitFrames/State/MSUF_Defaults.lua"):find(dispelSource:gsub("\n$", ""), 1, true), "legacy source drift: dispelSource")
    assert(Read(legacyRoot .. "/MidnightSimpleUnitFrames/State/MSUF_Defaults.lua"):find(guardSource:gsub("\n$", ""), 1, true), "legacy source drift: guardSource")
    assert(Read(legacyRoot .. "/MidnightSimpleUnitFrames/State/MSUF_Defaults.lua"):find(rootsSource:gsub("\n$", ""), 1, true), "legacy source drift: rootsSource")
    assert(Read(legacyRoot .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Migrations.lua"):find(aurasSource:gsub("\n$", ""), 1, true), "legacy source drift: aurasSource")
    assert(Read(legacyRoot .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Geometry.lua"):find(positionSource:gsub("\n$", ""), 1, true), "legacy source drift: positionSource")
end

local Bars = assert(loadstring("return function(g)\n" .. barsSource .. "\nend"))()
local Dispel = assert(loadstring(dispelSource .. "\nreturn MSUF_Defaults_MigrateUnitDispelOwnership"))()
local Auras = assert(loadstring("local GF_AURA_PROFILE_MODEL_REVISION = 1\n" .. aurasSource .. "\nreturn RepairAuraV2"))()
local IsCurrent = assert(loadstring("local MSUF_DEFAULTS_CURRENT_REVISION, MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = 17, 600\n"
    .. rootsSource .. "\n" .. guardSource .. "\nreturn MSUF_Defaults_IsCurrentProfileDB"))()
local RootKeys = assert(loadstring(rootsSource .. "\nreturn MSUF_DEFAULTS_ROOT_TABLE_KEYS"))()
-- Only the geometry arithmetic service is modeled; the selection/migration function is the exact old source.
local Position = assert(loadstring([[local GF = { GetGridMetrics = function(_, count) return count, count * 2 end }
local LEGACY_GRID_POSITION_MODE, STABLE_GRID_POSITION_MODE = "GRID_CENTER_V1", "STABLE_TEST"
local function IsRaidLikeKind(kind) return kind == "raid" or kind == "mythicraid" end
]] .. positionSource .. "\nreturn GF.EnsureStableGridPosition"))()
local ns = { Util = { IsSecret = function() return false end } }
local schemaPath = root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Schema.lua"
local schemaDir = root .. "/MidnightSimpleUnitFrames/State/Defaults/"
for _, name in ipairs({
    "MSUF_Defaults_Schema.lua", "MSUF_Defaults_StorageData.lua", "MSUF_Defaults_StorageCommon.lua",
    "MSUF_Defaults_StorageV3.lua", "MSUF_Defaults_Storage.lua", "MSUF_Defaults_Recovery.lua",
}) do
    assert(loadfile(schemaDir .. name))("MidnightSimpleUnitFrames", ns)
end
local Schema = ns.DefaultsSchema
local data = assert(Read(schemaDir .. "MSUF_Defaults_StorageData.lua"):match("%-%- BEGIN FROZEN SPARSE V2 DATA(.-)%-%- END FROZEN SPARSE V2 DATA"))
local fields, owners = assert(loadstring(data .. "\nreturn sparseV2Fields, sparseV2Owners"))()
assert(#fields == 971 and #owners == 120, "V2 dictionary shape changed")
local total = 0
local function Full()
    local p = { _msufDefaultsRevision = 17, _msufProfileSchema = 600, shortenNames = false }
    for _, path in ipairs(RootKeys) do p[path] = {} end
    total = 0
    for _, spec in ipairs(owners) do
        local owner = p
        for _, key in ipairs(spec.path) do owner[key] = owner[key] or {}; owner = owner[key] end
        for _, id in ipairs(spec.fields) do
            owner[fields[id][1]] = fields[id][2]
            total = total + 1
        end
    end
    p.gameplay.enableCombatTimer = false
    return p
end
local function Sample()
    local p = Full()
    for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor" }) do
        p.general[prefix .. "R"], p.general[prefix .. "G"] = 0.27, 0.38
        p.general[prefix .. "B"], p.general[prefix .. "A"] = 0.49, 0.61
    end
    p.general.unitDispelSymbolEnabled, p.player.unitDispelSymbolEnabled, p.player.hlOverride = true, false, false
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        p[key].auras.enabled, p[key].auras.externals = false, { enabled = false }
        p[key]._auraMigV2 = nil
    end
    p.gf_mythicraid.offsetX, p.gf_mythicraid.offsetY = 317, 211
    p.gf_mythicraid.positionMigrationDX, p.gf_mythicraid.positionMigrationDY = nil, nil
    p.userData = { false, 0, "", spells = { [12345] = true } }
    return p
end
local function Encode(p)
    local ok, count = Schema.Persist({ profiles = { Test = p } })
    assert(ok and count > 0 and p._msufDefaultsRevision == 17.5, "no actual V2 encoding")
    assert(not IsCurrent(p), "6.50 revision guard unexpectedly accepts V2")
    return p
end
local failed = {}
local function Check(name, fn)
    local ok, why = pcall(fn)
    print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(why)))
    if not ok then failed[#failed + 1] = name end
end
Check("legacy absorb/dispel migration preserves choices", function()
    local original = Sample()
    local p = Encode(Copy(original))
    -- EnsureDB_Heavy invokes these stages after rejecting revision 17.5.
    Bars(p.general)
    Dispel(p)
    for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor" }) do
        for _, channel in ipairs({ "R", "G", "B", "A" }) do
            assert(p.general[prefix .. channel] == original.general[prefix .. channel], "custom colour was wiped")
        end
    end
    assert(p.player.unitDispelSymbolEnabled == false, "independent unit dispel choice overwritten")
end)
Check("legacy aura migration preserves disabled choices", function()
    local p = Encode(Sample())
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        Auras(p[key])
        assert(p[key].auras.enabled == false and p[key].auras.externals.enabled == false, "auras force-enabled")
    end
end)
Check("legacy position migration keeps pinned count", function()
    local full = Sample()
    local p = Encode(Copy(full))
    assert(Position("mythicraid", 31, full.gf_mythicraid))
    assert(Position("mythicraid", 31, p.gf_mythicraid), "position mode was lost")
    assert(p.gf_mythicraid.offsetX == full.gf_mythicraid.offsetX
        and p.gf_mythicraid.offsetY == full.gf_mythicraid.offsetY, "different migration count shifted position")
end)
Check("historical V2 bits including retained markers still decode", function()
    local full = Full()
    assert(total == 3595, "V2 bit count changed")
    local old = Copy(full)
    for _, spec in ipairs(owners) do
        local owner = old
        for _, key in ipairs(spec.path) do owner = owner[key] end
        for _, id in ipairs(spec.fields) do owner[fields[id][1]] = nil end
    end
    old._msufDefaultsRevision, old._msufSparseDefaultsV2 = 17.5, string.rep("f", 898) .. "7"
    assert(Schema.RestorePersistence(old))
    assert(H.Literal(old) == H.Literal(full), "old mask meaning changed")
end)
Check("new encoding exact roundtrip and retained fields", function()
    local full = Sample()
    local p = Encode(Copy(full))
    for _, spec in ipairs(owners) do
        local owner, original = p, full
        for _, key in ipairs(spec.path) do owner, original = owner[key], original[key] end
        for _, id in ipairs(spec.fields) do
            local key = fields[id][1]
            local lower = key:lower()
            if lower:find("migration", 1, true) or lower:find("version", 1, true)
                or lower:find("revision", 1, true) or lower:find("marker", 1, true) or key == "positionMode" then
                assert(owner[key] == original[key], "retention field omitted: " .. key)
            end
        end
    end
    assert(Schema.RestorePersistence(p) and H.Literal(p) == H.Literal(full), "new V2 exact roundtrip failed")
end)
Check("stale revision 17 mask clears and recompacts", function()
    local p = Sample()
    p.general.absorbBarColorMigrationV2 = nil
    local original = H.Literal(p)
    p._msufSparseDefaultsV2 = "stale"
    assert(Schema.RestorePersistence(p), "stale mask not reported changed")
    assert(H.Literal(p) == original, "stale cleanup fabricated fields or changed values")
    Encode(p)
    assert(Schema.RestorePersistence(p) and H.Literal(p) == original, "recompaction changed original data")
end)
Check("stale unknown revision preserves data and revision", function()
    local p = Sample()
    p._msufDefaultsRevision = 18
    local original = H.Literal(p)
    p._msufSparseDefaultsV2 = false
    assert(Schema.RestorePersistence(p) and H.Literal(p) == original)
    assert(select(2, Schema.Persist({ profiles = { Test = p } })) == 0, "unknown revision encoded")
end)
Check("secret stamps and current corrupt mask remain untouched", function()
    local secret = {}
    ns.Util.IsSecret = function(v) return v == secret end
    local p = { _msufDefaultsRevision = secret, _msufSparseDefaultsV2 = "stale" }
    assert(not Schema.RestorePersistence(p) and p._msufSparseDefaultsV2 == "stale")
    p = { _msufDefaultsRevision = 17, _msufSparseDefaultsV2 = secret }
    assert(not Schema.RestorePersistence(p) and p._msufSparseDefaultsV2 == secret)
    ns.Util.IsSecret = function() return false end
    p = { _msufDefaultsRevision = 17.5, _msufSparseDefaultsV2 = "corrupt", general = { unknown = false } }
    local original = H.Literal(p)
    assert(not Schema.RestorePersistence(p) and H.Literal(p) == original)
end)
Check("V1 numeric and string decoder retained", function()
    for _, stamp in ipairs({ 17.5, "MSUF_SPARSE_DEFAULTS_1" }) do
        local p = { _msufDefaultsRevision = stamp, general = { showGameMenuButton = false },
            gf_party = {}, gf_raid = {}, gf_mythicraid = {} }
        assert(Schema.RestorePersistence(p) and p._msufDefaultsRevision == 17)
        assert(p.general.showGameMenuButton == false and p.general.previewDragHintAnimationEnabled == true)
    end
end)
assert(#failed == 0, table.concat(failed, "; "))
print("profile_sparse_backward_migration_smoke: all focused migration/codec checks passed")
