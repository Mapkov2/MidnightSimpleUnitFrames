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
MSUF.Assistant = {}
local A = MSUF.Assistant

local function newRegistry()
    local byKey, ordered = {}, {}
    return {
        settings = ordered,
        RegisterSetting = function(self, spec)
            if byKey[spec.key] then return byKey[spec.key] end
            byKey[spec.key] = spec
            ordered[#ordered + 1] = spec
            return spec
        end,
        GetSetting = function(self, key) return byKey[key] end,
    }
end

A.Registry = newRegistry()
A.CoverageAudit = {
    BuildCoveredSets = function() return {} end,
    IsCoveredKey = function(set, key) return set[key] ~= nil end,
    NormalizeCoverageKey = function(key)
        return tostring(key or ""):lower():gsub("[^%w]", "")
    end,
    IsIgnored = function() return false end,
}

assert(loadfile(assistantRoot .. "/MSUF_AssistantRegistry_AutoCoverage_Manifest.lua"))(
    "MidnightSimpleUnitFrames_Assistant", MSUF)
assert(loadfile(assistantRoot .. "/MSUF_AssistantRegistry_AutoCoverage.lua"))(
    "MidnightSimpleUnitFrames_Assistant", MSUF)

local manifest = assert(A.AutoCoverageManifest and A.AutoCoverageManifest.defaults,
    "AutoCoverage manifest defaults missing")
local IsGeneratedPathAllowed = assert(A.AutoCoverage.IsGeneratedPathAllowed,
    "AutoCoverage generated-path policy missing")
local scopes = {}
local expectedKeys = {}
local manifestKeyCount = 0
for scope, values in pairs(manifest) do
    if type(values) == "table" then
        scopes[#scopes + 1] = scope
        for key, value in pairs(values) do
            local valueType = type(value)
            assert(type(key) == "string" and not key:find(".", 1, true),
                "manifest identity is not top-level: " .. tostring(scope) .. "." .. tostring(key))
            assert(valueType == "boolean" or valueType == "number" or valueType == "string",
                "manifest value is not scalar: " .. tostring(scope) .. "." .. tostring(key))
            manifestKeyCount = manifestKeyCount + 1
            if IsGeneratedPathAllowed(scope, key) then
                expectedKeys[#expectedKeys + 1] = scope .. "." .. key
            end
        end
    end
end
table.sort(scopes)
table.sort(expectedKeys)
assert(manifestKeyCount == tonumber(A.AutoCoverageManifest.scalarCount),
    "manifest scalar declaration does not match its exact identity set")

local function freshDB(withProfileNoise)
    local db = {}
    for i = 1, #scopes do db[scopes[i]] = {} end
    if withProfileNoise then
        db.target.__unmanifestedScalar = true
        db.target.trainingNested = { display = { enabled = true, opacity = 0.45 } }
        db.target.portraitBgColorR = 0.123456
        db.general.minimapIconDB = { hide = false, minimapPos = 210, radius = 80 }
        db.general.UIScale = { Enabled = true, Scale = 0.95 }
        db.player.castbar = { channelTickCount = 7 }
        local targetDefaults = assert(manifest.target, "target manifest scope missing")
        for key, value in pairs(targetDefaults) do
            if type(value) == "boolean" then db.target[key] = not value; break end
            if type(value) == "number" then db.target[key] = value + 1; break end
            if type(value) == "string" then db.target[key] = value .. "_profile"; break end
        end
    end
    return db
end

local function fillAndCollect(db)
    _G.MSUF_DB = db
    A.Registry = newRegistry()
    A.AutoCoverage._fillComplete = nil
    local added = assert(A.AutoCoverage.Fill(), "AutoCoverage Fill returned nil")
    local actual = {}
    for i = 1, #A.Registry.settings do
        local setting = A.Registry.settings[i]
        actual[#actual + 1] = assert(setting.key)
        assert(setting.generated == true and setting.generatedNested == false,
            "generated identity was not classified top-level: " .. tostring(setting.key))
        assert(setting.manifestDefault ~= nil,
            "generated identity was not backed by a manifest default: " .. tostring(setting.key))
    end
    table.sort(actual)
    assert(added == #actual, "Fill count differs from registry growth")
    assert(#actual == #expectedKeys,
        ("generated identity count drift expected=%d actual=%d"):format(#expectedKeys, #actual))
    for i = 1, #expectedKeys do
        assert(actual[i] == expectedKeys[i],
            ("generated identity drift at %d expected=%s actual=%s")
                :format(i, tostring(expectedKeys[i]), tostring(actual[i])))
    end
    return table.concat(actual, "\n")
end

local cleanSet = fillAndCollect(freshDB(false))
local noisySet = fillAndCollect(freshDB(true))
assert(cleanSet == noisySet, "saved-profile shape changed the generated AutoCoverage identity set")
assert(A.Registry:GetSetting("target.__unmanifestedScalar") == nil,
    "unmanifested saved-profile scalar became a public Assistant setting")
assert(A.Registry:GetSetting("target.trainingNested.display.opacity") == nil,
    "nested saved-profile state became a public Assistant setting")
assert(A.Registry:GetSetting("general.minimapIconDB.hide") == nil,
    "nested minimap state became a public Assistant setting")

io.write(("assistant_autocoverage_identity_regression: ok exact_keys=%d scopes=%d profile_noise_ignored=true\n")
    :format(#expectedKeys, #scopes))
