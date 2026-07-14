_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

local root = exists("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_AutoCoverage.lua") and "." or ".."
local assistantRoot = root .. "/MidnightSimpleUnitFrames_Assistant/Assistant"

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {
        regressionFractionDefault = 0.4,
        regressionZeroDefault = 0,
        regressionLargeDefault = 25,
        regressionBooleanDefault = true,
    },
    bars = {}, gameplay = {},
    player = {}, target = {}, targettarget = {}, focustarget = {},
    focus = {}, pet = {}, boss = {},
    gf_party = {}, gf_raid = {}, gf_mythicraid = {},
}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
local settings = {}
A.Registry = {
    RegisterSetting = function(_, spec)
        if settings[spec.key] then return settings[spec.key] end
        settings[spec.key] = spec
        return spec
    end,
    GetSetting = function(_, key) return settings[key] end,
}
A.CoverageAudit = {
    BuildCoveredSets = function() return {} end,
    IsCoveredKey = function(set, key) return set[key] ~= nil end,
    NormalizeCoverageKey = function(key) return key end,
    IsIgnored = function() return false end,
}

assert(loadfile(assistantRoot .. "/MSUF_AssistantRegistry_AutoCoverage_Manifest.lua"))(
    "MidnightSimpleUnitFrames_Assistant", MSUF)
local regressionManifest = assert(A.AutoCoverageManifest and A.AutoCoverageManifest.defaults
    and A.AutoCoverageManifest.defaults.general, "AutoCoverage general manifest missing")
regressionManifest.regressionFractionDefault = 0.4
regressionManifest.regressionZeroDefault = 0
regressionManifest.regressionLargeDefault = 25
regressionManifest.regressionBooleanDefault = true
assert(loadfile(assistantRoot .. "/MSUF_AssistantRegistry_AutoCoverage.lua"))(
    "MidnightSimpleUnitFrames_Assistant", MSUF)

local added = assert(A.AutoCoverage.Fill())
assert(added > 0, "AutoCoverage did not register generated settings")

local function assertUnreviewedNumber(key, expected)
    local setting = assert(settings[key], "missing generated number " .. key)
    assert(setting.generated == true and setting.type == "number", key .. " is not a generated number")
    assert(setting.get() == expected, key .. " current/default value changed")
    assert(setting.assistantMutationSafe == false, key .. " was incorrectly marked writable")
    assert(setting.generatedMutationSafety == "unreviewed-number-domain", key .. " has the wrong safety classification")
    assert(setting.min == nil and setting.max == nil and setting.percent == nil,
        key .. " inferred a domain from its default value")
    assert(type(setting.unsafeMutationReason) == "string" and setting.unsafeMutationReason ~= "",
        key .. " has no fail-closed explanation")
end

assertUnreviewedNumber("general.regressionFractionDefault", 0.4)
assertUnreviewedNumber("general.regressionZeroDefault", 0)
assertUnreviewedNumber("general.regressionLargeDefault", 25)

local boolean = assert(settings["general.regressionBooleanDefault"], "missing generated boolean")
assert(boolean.type == "boolean" and boolean.assistantMutationSafe == true,
    "boolean fallback should retain its proven two-value domain")

local focusTargetManifest = assert(settings["focustarget.raidMarkerSize"],
    "Focus Target manifest scope did not produce fallback settings")
local expectedFocusTargetDefault = assert(A.AutoCoverageManifest.defaults.focustarget.raidMarkerSize,
    "Focus Target manifest raid marker default missing")
assert(focusTargetManifest.manifestDefault == expectedFocusTargetDefault,
    "Focus Target generated setting diverged from the verified manifest")
assert(focusTargetManifest.assistantMutationSafe == false,
    "Focus Target generated number bypassed the fail-closed guard")

local generatedNumbers = 0
for key, setting in pairs(settings) do
    if setting.generated == true and setting.type == "number" then
        generatedNumbers = generatedNumbers + 1
        assert(setting.assistantMutationSafe == false, key .. " is an unreviewed writable number")
        assert(setting.min == nil and setting.max == nil, key .. " inferred numeric bounds")
    end
end
assert(generatedNumbers > 0, "no generated numbers were audited")

-- Exercise the real execution boundary as well as the generated metadata. The
-- dashboard fixture loads the complete LoD Assistant and a normalized mock DB.
dofile(root .. "/tools/assistant_dashboard_smoke.lua")
local runtimeA = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "runtime Assistant missing")
local runtimeRegistry = assert(runtimeA.Registry, "runtime Assistant registry missing")

assert(runtimeRegistry:GetSetting("player.showSelfHealPrediction") == nil,
    "legacy Player self-heal mirror was exposed as a generated control")
assert(runtimeRegistry:GetSetting("gf_party.showSelfHealPrediction") == nil,
    "legacy Party self-heal mirror was exposed as a generated control")
assert(runtimeRegistry:GetSetting("general.colorHealthTextByHealth") == nil,
    "shared health-text storage mirror was exposed as a generated control")
assert(runtimeRegistry:GetSetting("general.showSelfHealPrediction"),
    "canonical self-heal prediction control is missing")
assert(runtimeRegistry:GetSetting("barScope.gf_party.healPredEnabled"),
    "canonical Party heal-prediction controller is missing")
assert(runtimeRegistry:GetSetting("fontScope.shared.colorHealthTextByHealth"),
    "canonical health-text color controller is missing")
assert(runtimeRegistry:GetSetting("gf_mythicraid.absorbBarOpacity") == nil,
    "aggregate Mythic Raid absorb opacity was exposed as a raw duplicate")
assert(runtimeRegistry:GetSetting("gf_mythicraid.absorbBarTexture") == nil,
    "aggregate Mythic Raid absorb texture was exposed as a raw duplicate")
assert(runtimeRegistry:GetSetting("gf_mythicraid.fontOutline") == nil,
    "aggregate Mythic Raid font outline was exposed as a raw duplicate")
for _, key in ipairs({
    "gf_party.showSelfHealPrediction",
    "gf_party.groupGrowth",
    "gf_raid.groupGrowth",
    "gf_mythicraid.groupGrowth",
    "gf_party.groupBorderR",
    "gf_party.groupBorderG",
    "gf_party.groupBorderB",
    "bars.highlightBorderThickness",
    "player.fontOverride",
    "gf_mythicraid.fontOverride",
}) do
    assert(runtimeRegistry:GetSetting(key) == nil,
        key .. " was exposed as a duplicate/non-public raw AutoCoverage control")
end

local covered = assert(runtimeA.CoverageAudit and runtimeA.CoverageAudit.BuildCoveredSets)()
local function assertCuratedOwner(scope, dbKey, expectedKey)
    local owner = covered[scope] and covered[scope][dbKey]
    assert(type(owner) == "table", scope .. "." .. dbKey .. " has no declared owner")
    assert(owner.generated ~= true, scope .. "." .. dbKey .. " is still owned by AutoCoverage")
    assert(owner.key == expectedKey,
        scope .. "." .. dbKey .. " owner mismatch: " .. tostring(owner.key) .. " ~= " .. expectedKey)
end
assertCuratedOwner("gf_party", "groupBorderR", "gf_party.groupBorderColor")
assertCuratedOwner("gf_party", "groupBorderG", "gf_party.groupBorderColor")
assertCuratedOwner("gf_party", "groupBorderB", "gf_party.groupBorderColor")
assertCuratedOwner("gf_mythicraid", "absorbBarOpacity", "barScope.gf_raid.absorbBarOpacity")
assertCuratedOwner("gf_mythicraid", "absorbBarTexture", "barScope.gf_raid.absorbBarTexture")
assertCuratedOwner("gf_mythicraid", "fontOutline", "fontScope.gf_raid.outline")
assertCuratedOwner("general", "colorHealthTextByHealth", "fontScope.shared.colorHealthTextByHealth")
assertCuratedOwner("player", "fontOverride", "fontScope.player.override")
assertCuratedOwner("gf_mythicraid", "fontOverride", "fontScope.gf_raid.override")

-- Raid is the visible aggregate style scope and must write both underlying
-- Raid DB tables. This is controller behavior, not merely parser metadata.
local aggregateOpacity = assert(runtimeRegistry:GetSetting("barScope.gf_raid.absorbBarOpacity"),
    "aggregate Raid absorb opacity controller is missing")
aggregateOpacity.set(0.65)
assert(_G.MSUF_DB.gf_raid.absorbBarOpacity == 0.65
        and _G.MSUF_DB.gf_mythicraid.absorbBarOpacity == 0.65,
    "aggregate Raid absorb opacity did not fan out to Mythic Raid")
local aggregateOutline = assert(runtimeRegistry:GetSetting("fontScope.gf_raid.outline"),
    "aggregate Raid font outline controller is missing")
aggregateOutline.set("THICKOUTLINE")
assert(_G.MSUF_DB.gf_raid.fontOutline == "THICKOUTLINE"
        and _G.MSUF_DB.gf_mythicraid.fontOutline == "THICKOUTLINE",
    "aggregate Raid font outline did not fan out to Mythic Raid")

local candidates = {}
for _, setting in ipairs(assert(runtimeRegistry.settings)) do
    if setting.generated == true and setting.type == "number"
        and setting.assistantMutationSafe == false
        and type(setting.get) == "function" and type(setting.set) == "function"
    then
        candidates[#candidates + 1] = setting
    end
end
table.sort(candidates, function(left, right) return tostring(left.key) < tostring(right.key) end)
local runtimeNumber = assert(candidates[1], "complete runtime has no generated numeric fallback")
local before = assert(tonumber(runtimeNumber.get()), "runtime generated number has no numeric value")
local blocked = assert(runtimeA.ExecutePlan({
    kind = "changes",
    changes = { { setting = runtimeNumber, value = before + 1 } },
    summary = "AutoCoverage numeric safety regression",
}))
assert(blocked.status == "info" and tostring(blocked.text):find("not safe for automatic writes", 1, true),
    "real execution boundary did not explain the blocked generated number")
assert(runtimeNumber.get() == before, "real execution boundary wrote an unreviewed generated number")

-- Every setting classified read-only must be stopped at the common execution
-- boundary before its setter runs. This exhaustive loop prevents one safe
-- sample from masking a writable string/number fallback elsewhere.
local unsafeGuarded = 0
for _, setting in ipairs(runtimeRegistry.settings) do
    if setting.assistantMutationSafe == false and type(setting.set) == "function" then
        local originalSet = setting.set
        local writes = 0
        setting.set = function()
            writes = writes + 1
        end
        local result = assert(runtimeA.ExecutePlan({
            kind = "changes",
            changes = { { setting = setting, value = "__MSUF_UNSAFE_GUARD__" } },
            summary = "Exhaustive AutoCoverage mutation guard",
        }), "unsafe execution guard returned no result for " .. tostring(setting.key))
        setting.set = originalSet
        assert(writes == 0, "unsafe setting setter ran for " .. tostring(setting.key))
        assert(result.status == "info"
                and tostring(result.text):find("not safe for automatic writes", 1, true),
            "unsafe setting was not rejected clearly: " .. tostring(setting.key))
        unsafeGuarded = unsafeGuarded + 1
    end
end
assert(unsafeGuarded > 0, "complete runtime has no read-only settings to guard")

io.write(("assistant_autocoverage_safety_regression: ok added=%d generated_numbers=%d runtime_guard=%s unsafe_guarded=%d\n")
    :format(added, generatedNumbers, tostring(runtimeNumber.key), unsafeGuarded))
