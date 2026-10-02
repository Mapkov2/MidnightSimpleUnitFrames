-- group_text_secret_percent_smoke.lua <repoRoot>
--
-- GF.FormatHealthText / GF.FormatPowerText (MSUF_GroupFrames_DB_Text.lua) take
-- possibly secret values: UnitHealthPercent and UnitHealthMissing are
-- SecretReturns, UnitPowerPercent SecretWhenUnitPowerRestricted
-- (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua). The formatter
-- compared those results with nil (`pct ~= nil`, `missingVal == nil`) and
-- truth-tested the secret percent text before issecretvalue. A secret may be
-- concatenated, never compared or truth-tested, so:
--   * behaviour: plain previews format exactly as before, and secret inputs flow
--     through the C formatters only;
--   * source order: in every helper issecretvalue runs before the nil test,
--     and the percent text is never truth-tested (a plain hasPct flag is).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Secret stand-ins: concatenating one yields another (as the client does);
-- arithmetic, ordering, indexing and length raise.
local secrets = setmetatable({}, { __mode = "k" })
local SecretMeta = {}
local function Secret(label)
    local value = setmetatable({ label = label }, SecretMeta)
    secrets[value] = true
    return value
end
local function Raise() error("attempt to use a secret value", 2) end
SecretMeta.__concat = function(a, b)
    local function Text(v) return secrets[v] and rawget(v, "label") or tostring(v) end
    return Secret(Text(a) .. Text(b))
end
SecretMeta.__lt, SecretMeta.__le, SecretMeta.__len, SecretMeta.__call = Raise, Raise, Raise, Raise
SecretMeta.__add, SecretMeta.__sub, SecretMeta.__mul, SecretMeta.__div = Raise, Raise, Raise, Raise
local function Label(value) return secrets[value] and rawget(value, "label") or value end

local units = {}
_G.issecretvalue = function(value) return secrets[value] == true end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.AbbreviateNumbers = function(value)
    if secrets[value] then return Secret("abbr(" .. Label(value) .. ")") end
    return tostring(value)
end
_G.BreakUpLargeNumbers = _G.AbbreviateNumbers
_G.C_StringUtil = { RoundToNearestString = function(value)
    if secrets[value] then return Secret("round(" .. Label(value) .. ")") end
    return tostring(math.floor(value + 0.5))
end }
_G.CurveConstants = { ScaleTo100 = {} }
_G.UnitHealthPercent = function(unit) return units[unit] and units[unit].hpPct end
_G.UnitPowerPercent = function(unit) return units[unit] and units[unit].ppPct end
_G.UnitHealthMissing = function(unit) return units[unit] and units[unit].missing end
_G.UnitPowerType = function() return 0 end
local ns = { ExportPublic = function() end }
for _, part in ipairs({ "", "_Geometry", "_Text", "_Textures" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB" .. part .. ".lua"))("MSUF", ns)
end
local GF = ns.GF
GF.GetConf = function() return {} end

-- Plain preview values (unit nil): unchanged output.
local H = GF.FormatHealthText
Check(H("PERCENT", 750, 1000, " / ", false, nil, false, true) == "75%", "plain percent changed")
Check(H("CURMAXPERCENT", 750, 1000, " / ", false, nil, false, true) == "750 / 1000 / 75%", "plain cur/max/percent changed")
Check(H("DEFICIT", 750, 1000, " / ", false, nil, false, true) == "-250", "plain deficit changed")
Check(H("DEFICIT", 1000, 1000, " / ", false, nil, false, true) == "", "a full bar must show no deficit")
Check(H("CURPERCENT", 750, 0, " / ", false, nil, false, true) == "750", "a missing percent must fall back to current")
Check(GF.FormatPowerText("PERCENT", 30, 120, " / ") == "25%", "plain power percent changed")

-- Live secret values: only the C formatters touch them.
units.party1 = { hpPct = Secret("hp%"), ppPct = Secret("pp%"), missing = Secret("miss") }
local hp, hpMax = Secret("hp"), Secret("max")
Check(Label(H("PERCENT", hp, hpMax, " / ", false, "party1", false, true)) == "round(hp%)%", "secret health percent")
Check(Label(H("CURPERCENT", hp, hpMax, " / ", false, "party1", false, true)) == "abbr(hp) / round(hp%)%",
    "secret current and percent")
Check(Label(H("DEFICIT", hp, hpMax, " / ", false, "party1", false, true)) == "-abbr(miss)", "secret deficit")
Check(Label(GF.FormatPowerText("PERCENT", Secret("pw"), Secret("pwMax"), " / ", "party1")) == "round(pp%)%",
    "secret power percent")

-- Source order: issecretvalue before every nil test, no truth test of the text.
local path = root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Text.lua"
local source = Slice.Read(path)
local function Before(body, guard, use, label)
    local g, u = body:find(guard, 1, true), body:find(use, 1, true)
    Check(g ~= nil and (u == nil or g < u), label .. ": '" .. use .. "' runs before '" .. guard .. "'")
end
local abbrev = Slice.Function(source, "local function _GF_Abbrev", path)
Before(abbrev, "iss(val)", "val == nil", "_GF_Abbrev")
for _, name in ipairs({ "_GF_HealthPercent", "_GF_PowerPercent" }) do
    Before(Slice.Function(source, "local function " .. name, path), "_GF_issecretvalue(pct)", "pct ~= nil", name)
end
local formatPct = Slice.Function(source, "local function _GF_FormatPct", path)
Before(formatPct, "iss(pctVal)", "pctVal ==", "_GF_FormatPct")
local byMode = Slice.Function(source, "local function _GF_FormatByMode", path)
Check(not byMode:find("pctStr or", 1, true) and not byMode:find("not pctStr", 1, true),
    "_GF_FormatByMode truth-tests the possibly secret percent text")
Before(byMode, "iss(missingVal)", "missingVal == nil", "_GF_FormatByMode")
Before(Slice.Function(source, "function GF.FormatHealthText", path), "iss(missingVal)", "missingVal == nil",
    "GF.FormatHealthText")

print("group_text_secret_percent_smoke: ok (plain previews unchanged, secret percent/deficit via C formatters)")
