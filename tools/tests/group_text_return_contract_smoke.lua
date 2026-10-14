-- Return-value preview formatting and engine name shortening keep their public contracts.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
local world = World.New(root, "Mainline")
local env = world.env
env.issecretvalue = Secrets.IsSecret
local labels = {}
local function Secret(label, kind)
    local value = Secrets.New(kind)
    labels[value] = label
    setmetatable(value, { __concat = function(a, b)
        return Secret((labels[a] or tostring(a)) .. (labels[b] or tostring(b)), "string")
    end })
    return value
end
local function Label(value) return labels[value] or value end
env.AbbreviateNumbers = function(value) return Secret("short", "string") end
env.BreakUpLargeNumbers = function(value) return Secret("long", "string") end
env.C_StringUtil = {
    RoundToNearestString = function() return Secret("round", "string") end,
    TruncateWhenZero = function() return Secret("absorb", "string") end,
    WrapString = function(value, prefix, suffix) return prefix .. value .. suffix end,
}
env.UnitHealthPercent = function() return Secret("percent") end
env.UnitPowerPercent = env.UnitHealthPercent
env.UnitHealthMissing = function() return Secret("missing") end
world:Boot()
assert(not world:FirstFailure(), "client graph failed to boot")
local GF, Text = world.core.GF, world.core.UFText
local path = root .. "/MidnightSimpleUnitFrames/"
local stop = Secrets.Watch({ path .. "GroupFrames/MSUF_GroupFrames_DB_Text.lua",
    path .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua",
    path .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua" }, { strict = true })
local secret = Secret("name", "string")
assert(GF.TruncateName(secret, 3) == secret, "secret name must pass through")
assert(GF.TruncateName("Aé中😀BC", 3.49, false, "RIGHT") == "Aé中..", "right UTF-8 rounding/dots")
assert(GF.TruncateName("Aé中😀BC", 3.5, true, "LEFT") == "中😀BC", "left UTF-8 rounding/no dots")
local current, maximum = Secret("current"), Secret("max")
assert(Label(GF.FormatHealthText("CURMAXPERCENT", current, maximum, "/", false, "party1", false, true))
    == "short / short / round%", "opaque current/max/percent")
assert(Label(GF.FormatHealthText("DEFICIT", current, maximum, nil, false, "party1", false, false))
    == "-long", "opaque deficit")
assert(Label(GF.FormatHealthText("CURRENTABSORB", current, maximum, nil, false, "party1", false, true,
    Secret("absorb"), true)) == "short + |TInterface\\Icons\\INV_Shield_06:0|t absorb", "opaque absorb wrapping")
assert(Label(GF.FormatPowerText("PERCENT", current, maximum, nil, "party1", true)) == "round", "power secret percent")
local secretProbes = 0
for _, row in ipairs(GF.HEALTH_TEXT_MODES) do
    for _, pair in ipairs({ { current, maximum }, { current, 1000 }, { 750, maximum } }) do
        for _, short in ipairs({ false, true }) do
            GF.FormatHealthText(row.key, pair[1], pair[2], "|", true, "party1", false, short, Secret("absorb"), true, 1)
            GF.FormatPowerText(row.key, pair[1], pair[2], "/", "party1", false)
            secretProbes = secretProbes + 2
        end
    end
end
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
assert(type(Text.FormatHealthString) == "function" and type(Text.FormatPowerString) == "function",
    "group return formatting must have an engine owner")
assert(Text.TruncateName("Aé中😀BC", 3.49, true, "RIGHT") == GF.TruncateName("Aé中😀BC", 3.49, false, "RIGHT"),
    "group and engine use the actual same name truncator")
local plain = World.New(root, "Mainline")
plain.env.AbbreviateNumbers = function(value) return "short:" .. tostring(value) end
plain.env.BreakUpLargeNumbers = function(value) return "long:" .. tostring(value) end
plain:Boot()
assert(not plain:FirstFailure(), "plain client graph failed to boot")
GF = plain.core.GF
local H = GF.FormatHealthText
assert(H("FULLVALUE", 12345, 50000, nil, false, nil, false, true) == "short:12345", "GROUP FULLVALUE follows short")
assert(H("CURMAXPERCENT", 750, 0, nil, false, nil, false, true) == "short:750", "missing percent is current only")
assert(H("CURRENTMAX", 750, 1000, nil, false, nil, false, true) == "short:750", "engine aliases remain unknown in GROUP")
assert(H("PERCENT", 49.5, 100, nil, false, nil, false, true) == "50%", "GROUP percent rounds rather than truncates")
assert(H("PERCENT", 49.95, 100, nil, false, nil, true, true, nil, false, 1) == "50.0", "one-decimal rounding")
assert(H("PERCENT", 1e12, 100, nil, false, nil, false, true) == "1000000000000%", "unbounded GROUP percent concatenation")
assert(H("PERCENT", math.huge, 100, nil, false, nil, false, true) == tostring(math.floor(math.huge)) .. "%",
    "GROUP infinite public preview")
assert(H("CURMAX", 750, 1000, "|", true, nil, false, false) == "long:1000 | long:750", "reverse and delimiter")
assert(H("ABSORB", 750, 1000, nil, false, nil, false, true, 0, true) == "", "zero absorb stays empty")
assert(H("CURRENTABSORB", 750, 1000, nil, false, nil, false, true, 100, false) == "short:750 + short:100",
    "public absorb uses native short with combined prefix")
assert(GF.FormatPowerText("FULLVALUE", 12345, 50000) == "short:12345", "power FULLVALUE follows defaults")
local uncompiled = plain.env.CreateFrame("Frame", nil, plain.env.UIParent)
uncompiled.MSUFUnitKey = "party1"
uncompiled.nameText = uncompiled:CreateFontString(nil, "OVERLAY")
plain.core.UFText.UpdateName(uncompiled, "UNIT_NAME_UPDATE", "party1")
assert(uncompiled.nameText:GetText() == "Tester", "a name without a compiled runtime must still paint")
print("group_text_return_contract_smoke: ok (" .. secretProbes .. " strict secret mode probes, UTF-8, return-value engine owner)")
