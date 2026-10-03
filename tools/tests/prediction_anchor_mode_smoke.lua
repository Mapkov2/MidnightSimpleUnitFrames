-- prediction_anchor_mode_smoke.lua <repoRoot>
--
-- The overlay anchor modes of the heal, absorb and heal-absorb bars are saved
-- numbers (general.absorbAnchorMode, healAbsorbAnchorMode, healPredAnchorMode):
-- 1 left, 2 right, 3 follow the HP bar, 4 follow it with overflow, 5 reverse
-- from max. UF.Shared.ABSORB_ANCHOR names them and the Prediction element reads
-- the names (NormalizeAnchorMode, AnchorModeReverse, ReverseForMode). This pins
-- the names to the saved numbers and the three functions to the answers they gave
-- when the numbers were written out, for every mode, fallback and HP direction.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local registered
_G.CreateFrame = function() error("unexpected top-level prediction frame creation") end
_G.issecretvalue = function() return false end
local namespace = {
    ExportPublic = function() end,
    UF = {
        Layers = {},
        RegisterElement = function(name, element)
            Check(name == "Prediction", "unexpected element name " .. tostring(name))
            registered = element
        end,
    },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"))("MidnightSimpleUnitFrames", namespace)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
    "MidnightSimpleUnitFrames", namespace)
Check(registered, "the prediction element did not register")

-- 1. The names are the saved numbers.
local ANCHOR = namespace.UF.Shared.ABSORB_ANCHOR
Check(ANCHOR.LEFT == 1 and ANCHOR.RIGHT == 2 and ANCHOR.FOLLOW_HP == 3 and ANCHOR.FOLLOW_HP_OVERFLOW == 4
    and ANCHOR.REVERSE_FROM_MAX == 5, "UF.Shared.ABSORB_ANCHOR no longer names the saved anchor modes 1-5")

local function Upvalue(fn, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing prediction upvalue: " .. wanted)
end
local compile = Upvalue(registered.Apply, "CompilePredictionRuntime")
local NormalizeAnchorMode = Upvalue(compile, "NormalizeAnchorMode")
local ReverseForMode = Upvalue(compile, "ReverseForMode")

-- 2. The answers, with the numbers written out as they were before the names.
local function ReferenceNormalize(mode, fallback)
    mode = tonumber(mode) or fallback or 2
    if mode < 1 or mode > 5 then return fallback or 2 end
    return mode
end
local function ReferenceReverse(mode, hpReverse)
    if mode == 3 or mode == 4 then return hpReverse == true end
    if mode == 1 then return false end
    if mode == 5 then return hpReverse ~= true end
    return true
end

local MODES = { 1, 2, 3, 4, 5, 0, 6, -1, 2.5, 3.5, "1", "3", "5", "x", "", true, false }
local FALLBACKS = { 1, 2, 3, 4, 5, 0, 9 }
local HP_REVERSE = { true, false, 1 }
local cases = 0
local function CheckNormalize(mode, fallback)
    local want, got = ReferenceNormalize(mode, fallback), NormalizeAnchorMode(mode, fallback)
    Check(got == want, string.format("NormalizeAnchorMode(%s, %s) = %s, was %s", tostring(mode),
        tostring(fallback), tostring(got), tostring(want)))
    cases = cases + 1
end
for _, fallback in ipairs(FALLBACKS) do
    CheckNormalize(nil, fallback)
    for _, mode in ipairs(MODES) do CheckNormalize(mode, fallback) end
end
CheckNormalize(nil, nil)
for _, mode in ipairs(MODES) do CheckNormalize(mode, nil) end
for mode = -1, 7 do
    for _, hpReverse in ipairs(HP_REVERSE) do
        local want, got = ReferenceReverse(mode, hpReverse), ReverseForMode(mode, hpReverse)
        Check(got == want, string.format("ReverseForMode(%d, %s) = %s, was %s", mode, tostring(hpReverse),
            tostring(got), tostring(want)))
        cases = cases + 1
    end
    local want, got = ReferenceReverse(mode, nil), ReverseForMode(mode, nil)
    Check(got == want, string.format("ReverseForMode(%d, nil) = %s, was %s", mode, tostring(got), tostring(want)))
    cases = cases + 1
end
print("prediction_anchor_mode_smoke: ok (" .. cases .. " cases)")
