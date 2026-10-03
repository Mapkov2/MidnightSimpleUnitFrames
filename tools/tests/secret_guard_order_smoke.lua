-- secret_guard_order_smoke.lua <repoRoot>
--
-- issecretvalue comes first, before any compare (AGENTS.md 4a). A `v == nil`
-- or `v ~= nil` ahead of the predicate raises on the client when v is secret.
-- Each guard below runs on secret input under the strict secrets helper
-- (tools/tests/classpower_secrets.lua Watch, strict), which records every
-- executed line that compares, negates or boolean-tests a secret local before
-- a predicate short-circuits it:
--   1. UnitFrames/Effects/MSUF_UF_TextureLayer.lua SetHolderAlpha: the
--      UnitHealthPercent curve result (a secret alpha) is applied, never
--      compared with nil first; ResolveHealthRGB hands secret health values to
--      the gradient helper without a nil compare;
--   2. UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua
--      Text.RefreshNameCenterClipFit: a secret name keeps the centered slice;
--   3. Libs/MSUFUnitFrames/MSUF_UF_Core.lua: the OnShow identity follow-up
--      ignores a secret GUID when it marks and when it consumes;
--   4. UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua
--      TruncateLegacyGroupName: a secret name is returned untouched, and the
--      common path (no legacy truncation) still asks no native predicate;
--      UpdateHealthRuntime (plain health text): secret health values from the
--      dispatch, from the health bar cache or from UnitHealth reach the secret
--      text path uncompared, and the dispatch path (UNIT_HEALTH with both
--      values) asks issecretvalue exactly as often as before (3 times).
-- The functions are compiled from the shipped files at their own lines, so the
-- line hook reads the real source.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function SourceLines(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing " .. rel)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

-- Compiles one top-level function of a shipped file at its own line numbers
-- (the chunk is padded with empty lines), in an environment of stubs over the
-- strict globals. Returns the function.
local function Slice(rel, declaration, env)
    local lines = SourceLines(rel)
    local first
    for index, line in ipairs(lines) do
        if line == declaration then first = index break end
    end
    assert(first, rel .. ": declaration not found: " .. declaration)
    local last
    for index = first + 1, #lines do
        if lines[index] == "end" then last = index break end
    end
    assert(last, rel .. ": no end for " .. declaration)
    local body = table.concat(lines, "\n", first, last)
    local name = declaration:match("^local function ([%w_]+)%(") or declaration:match("^function ([%w_%.]+)%(")
    local source = string.rep("\n", first - 1) .. body .. "\nreturn " .. name
    local chunk = assert(loadstring(source, "@" .. root .. "/" .. rel))
    setfenv(chunk, setmetatable(env or {}, { __index = _G }))
    return chunk()
end

local TEXTURE = "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_TextureLayer.lua"
local LAYOUT = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"
local CORE = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local RUNTIME = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"

local predicateCalls = 0
local strictPredicate = issecretvalue
local function CountingPredicate(value)
    predicateCalls = predicateCalls + 1
    return strictPredicate(value)
end

-- 1. Texture layer --------------------------------------------------------------
local SetHolderAlpha = Slice(TEXTURE, "local function SetHolderAlpha(holder, alpha)")
local ResolveHealthRGB = Slice(TEXTURE, "local function ResolveHealthRGB(holder, frame, conf, keys, unit, hp, maxHP, r, g, b)", {
    HealthGradientColorFromValues = function(_, hp, maxHP)
        if issecretvalue(hp) or issecretvalue(maxHP) or hp == nil or maxHP == nil then return nil end
        return 1, 0, 0
    end,
    GradientColor = function() return 0.2, 0.3, 0.4 end,
})
-- 2. Name clip --------------------------------------------------------------------
local Text = {}
Slice(LAYOUT, "function Text.RefreshNameCenterClipFit(frame)", {
    Text = Text,
    NameCenterClipAnchor = function() return "CENTER", "CENTER" end,
    AnchorNameToClip = function() end,
})
-- 3. Identity follow-up -------------------------------------------------------------
local secretGuid = Secrets.New("string")
local coreEnv = {
    OnShowIdentityFollowupEvent = function() return "PLAYER_TARGET_CHANGED" end,
    UnitGUID = function() return secretGuid end,
    GetTime = function() return 7 end,
}
local MarkOnShowIdentityFollowup = Slice(CORE, "local function MarkOnShowIdentityFollowup(frame)", coreEnv)
local ConsumeOnShowIdentityFollowup = Slice(CORE, "local function ConsumeOnShowIdentityFollowup(frame, event, unit)", coreEnv)
-- 4. Legacy name truncation ---------------------------------------------------------
local TruncateLegacyGroupName = Slice(RUNTIME, "local function TruncateLegacyGroupName(name, rt)", {
    floor = math.floor,
    NextUtf8Byte = function(_, pos) return pos + 1 end,
    issecretvalue = CountingPredicate,
})

local healthSink, cachedHP, cachedMax, unitHealthValue
local healthEnv = {
    issecretvalue = CountingPredicate,
    nativeSecrets = true,
    SeedCachedHealthMax = function() end,
    ReadHealthValuesCached = function() return cachedHP, cachedMax end,
    UnitHealth = function() return unitHealthValue end,
    ReadHealthMaxCached = function() return cachedMax end,
    UpdateTextSlotsSecret = function(_, _, hp, hpMax) healthSink = { hp = hp, hpMax = hpMax } end,
    UpdateTextSlotsPlain = function() healthSink = "plain" end,
}
local UpdateHealthRuntime = Slice(RUNTIME, "local function UpdateHealthRuntime(frame, event, unit, hp, hpMax)", healthEnv)

local stop = Secrets.Watch({ root .. "/" .. TEXTURE, root .. "/" .. LAYOUT, root .. "/" .. CORE, root .. "/" .. RUNTIME },
    { strict = true })

local alpha = Secrets.New("number")
local holder = { SetAlpha = function(self, value) self.alpha = value end }
SetHolderAlpha(holder, alpha)
Check(holder.alpha == alpha and holder._msufTexLayerOwnAlpha == nil,
    "the texture layer did not apply a secret curve alpha, or cached it")

local r, g, b = ResolveHealthRGB({}, {}, { mode = "GRADIENT" }, { HealthAboveMode = "mode" }, "target",
    Secrets.New("number"), Secrets.New("number"))
Check(r == 0.2 and g == 0.3 and b == 0.4, "secret health did not fall back to the gradient colour")

local nameText = {
    GetText = function() return Secrets.New("string") end,
    GetStringWidth = function() error("a secret name was measured") end,
}
local clipFrame = { nameText = nameText, _msufNameInlineClip = {}, _msufNameInlineClipWidth = 100,
    _msufNameCenterClipOverflow = true }
Text.RefreshNameCenterClipFit(clipFrame)
Check(clipFrame._msufNameCenterClipOverflow == false, "a secret name did not keep the centered slice")

local identityFrame = { MSUFUnitKey = "target" }
MarkOnShowIdentityFollowup(identityFrame)
Check(identityFrame._msufCoreOnShowFollowupEvent == nil, "a secret GUID was remembered for the OnShow follow-up")
identityFrame._msufCoreOnShowFollowupEvent = "PLAYER_TARGET_CHANGED"
identityFrame._msufCoreOnShowFollowupGUID = "Player-1-0001"
identityFrame._msufCoreOnShowFollowupTime = 7
Check(ConsumeOnShowIdentityFollowup(identityFrame, "PLAYER_TARGET_CHANGED", "target") == false,
    "a secret GUID matched the remembered OnShow follow-up")

local secretName = Secrets.New("string")
Check(TruncateLegacyGroupName(secretName, { nameLegacyTruncation = true, nameLegacyShortenMax = 10 }) == secretName,
    "a secret name was not returned untouched")
predicateCalls = 0
local plainName = "Plain"
Check(TruncateLegacyGroupName(plainName, {}) == plainName and predicateCalls == 0,
    "the name path without legacy truncation asked " .. predicateCalls .. " native predicate(s)")

local function HealthRuntime(event, hp, hpMax)
    healthSink = nil
    local rt = { healthSlotCount = 1, healthPlain = true, healthNeedsCurrent = true, healthNeedsMax = true }
    UpdateHealthRuntime({ MSUFUnitKey = "target", _msufTextRuntime = rt }, event, "target", hp, hpMax)
    return healthSink
end
local dispatchHP, dispatchMax = Secrets.New("number"), Secrets.New("number")
predicateCalls = 0
local sink = HealthRuntime("UNIT_HEALTH", dispatchHP, dispatchMax)
Check(type(sink) == "table" and sink.hp == dispatchHP and sink.hpMax == dispatchMax,
    "secret dispatch health did not reach the secret text path")
Check(predicateCalls == 3, "the UNIT_HEALTH dispatch path asked issecretvalue " .. predicateCalls
    .. " times (budget: 3)")
cachedHP, cachedMax = Secrets.New("number"), Secrets.New("number")
sink = HealthRuntime("UNIT_MAXHEALTH", nil, nil)
Check(type(sink) == "table" and sink.hp == cachedHP and sink.hpMax == cachedMax,
    "secret cached health did not reach the secret text path")
cachedHP, cachedMax, unitHealthValue = nil, Secrets.New("number"), Secrets.New("number")
sink = HealthRuntime("UNIT_MAXHEALTH", nil, nil)
Check(type(sink) == "table" and sink.hp == unitHealthValue, "a secret UnitHealth did not reach the secret text path")

local violations = stop()
Check(#violations == 0, "secret values compared before issecretvalue:\n    " .. table.concat(violations, "\n    "))

if #failures > 0 then
    error("secret_guard_order_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("secret_guard_order_smoke: ok (texture layer alpha and health colour, name clip, identity follow-up,"
    .. " legacy name truncation, plain health text)")
