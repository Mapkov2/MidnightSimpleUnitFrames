-- prediction_anchor_mode_smoke.lua <repoRoot>
--
-- The overlay anchor modes of the heal, absorb and heal-absorb bars are saved
-- numbers (general.absorbAnchorMode, healAbsorbAnchorMode, healPredAnchorMode):
-- 1 left, 2 right, 3 follow the HP bar, 4 follow it with overflow, 5 reverse
-- from max. UF.Shared.ABSORB_ANCHOR names them and the Prediction element reads
-- the names, on its configuration, layout, clip and update paths alike. This pins
-- the names to the saved numbers, the normalization and reversal functions to the
-- answers they gave when the numbers were written out (every mode, fallback and HP
-- direction), and the layout and clipping decisions of the three bars to what the
-- literal-number code decided: which bars anchor to the HP texture, which hang
-- under the overflow clip, whether the HP bar clips its children, and the fill
-- direction, for every mode and HP direction, with equal and mixed modes, after the
-- update events that lay the bars out again.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local registered

-- Frames recorded where the layout decisions show: points, parent, reverse fill, clipping.
local nextId, loading = 0, true
local Method = {}
local function Region(kind, parent)
    nextId = nextId + 1
    return setmetatable({ id = kind .. nextId, parent = parent, width = 100, height = 24, level = 1, shown = true,
        scripts = {}, hooks = {}, points = {} }, { __index = Method })
end
for _, name in ipairs({ "SetAlpha", "SetStatusBarColor", "SetVertexColor", "SetTexture", "SetColorTexture", "SetBlendMode",
    "SetAllPoints", "EnableMouse", "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "UnregisterAllEvents",
    "SetOrientation" }) do
    Method[name] = function() end
end
function Method:SetPoint(point, relativeTo) self.points[#self.points + 1] = { point = point, relativeTo = relativeTo } end
function Method:ClearAllPoints() self.points = {} end
function Method:SetReverseFill(value) self.reverse = value end
function Method:SetClipsChildren(value) self.clips = value end
function Method:SetScript(event, fn) self.scripts[event] = fn end
function Method:GetScript(event) return self.scripts[event] end
function Method:HookScript(event, fn) self.hooks[event] = fn end
function Method:SetMinMaxValues(low, high) self.low, self.high = low, high end
function Method:SetValue(value) self.value = value end
function Method:SetStatusBarTexture() self.texture = self.texture or Region("Texture", self) end
function Method:GetStatusBarTexture() self.texture = self.texture or Region("Texture", self); return self.texture end
function Method:SetShown(value) self.shown = value end
function Method:Show() self.shown = true end
function Method:Hide() self.shown = false end
function Method:IsShown() return self.shown end
function Method:IsVisible() return self.shown end
function Method:SetWidth(value) self.width = value end
function Method:SetHeight(value) self.height = value end
function Method:GetWidth() return self.width end
function Method:GetHeight() return self.height end
function Method:SetParent(value) self.parent = value end
function Method:GetParent() return self.parent end
function Method:SetFrameLevel(value) self.level = value end
function Method:GetFrameLevel() return self.level end
function Method:SetFrameStrata(value) self.strata = value end
function Method:GetFrameStrata() return self.strata or "MEDIUM" end

_G.CreateFrame = function(kind, _, parent)
    Check(not loading, "unexpected top-level prediction frame creation")
    return Region(kind, parent)
end
_G.issecretvalue = function() return false end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 600 end
_G.UnitHealthMax = function() return 1000 end
_G.UnitHealthPercent = function() return 0 end
_G.UnitGetIncomingHeals = function() return 120 end
_G.UnitGetTotalAbsorbs = function() return 150 end
_G.UnitGetTotalHealAbsorbs = function() return 25 end
_G.CreateUnitHealPredictionCalculator = function()
    return { SetDamageAbsorbClampMode = function() end, GetDamageAbsorbs = function() return 150 end }
end
_G.UnitGetDetailedHealPrediction = function() end
_G.Enum = { LuaCurveType = { Step = 1 }, UnitDamageAbsorbClampMode = { MissingHealthWithoutIncomingHeals = 1 } }
_G.C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
_G.InCombatLockdown = function() return false end
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

-- 3. Layout and clipping. Every line is what the bars did under the literal numbers.
loading = false
local function Anchors(bar, hp, texture)
    local toTexture, toHp = false, false
    for _, point in ipairs(bar.points) do
        if point.relativeTo == texture then toTexture = true end
        if point.relativeTo == hp then toHp = true end
    end
    return toTexture, toHp
end
local function NewFrame(cfg, reverse)
    local f = Region("Button")
    f.MSUFUnitKey = "raid1"
    f.hpBar = Region("StatusBar", f)
    f.Health = f.hpBar
    f.MSUFSpec = { scope = "group", width = 100, health = { reverse = reverse, vertical = false }, prediction = cfg }
    registered.Apply(f, f.MSUFSpec)
    registered.Update(f, "MSUF_UNIT_IDENTITY", "raid1")
    return f
end
local function Event(f, event) registered.SelectEventUpdate(f, f.MSUFSpec, event)(f, event, f.MSUFUnitKey) end

local LAYOUT = {
    "mode 1 hpReverse false | clips=nil | incomingHealBar texture=false hp=false parentHp=true reverse=false | absorbBar texture=false hp=false parentHp=true reverse=false | healAbsorbBar texture=false hp=false parentHp=true reverse=false",
    "mode 1 hpReverse true | clips=nil | incomingHealBar texture=false hp=false parentHp=true reverse=false | absorbBar texture=false hp=false parentHp=true reverse=false | healAbsorbBar texture=false hp=false parentHp=true reverse=false",
    "mode 2 hpReverse false | clips=nil | incomingHealBar texture=false hp=false parentHp=true reverse=true | absorbBar texture=false hp=false parentHp=true reverse=true | healAbsorbBar texture=false hp=false parentHp=true reverse=true",
    "mode 2 hpReverse true | clips=nil | incomingHealBar texture=false hp=false parentHp=true reverse=true | absorbBar texture=false hp=false parentHp=true reverse=true | healAbsorbBar texture=false hp=false parentHp=true reverse=true",
    "mode 3 hpReverse false | clips=true | incomingHealBar texture=true hp=false parentHp=true reverse=false | absorbBar texture=false hp=false parentHp=true reverse=false | healAbsorbBar texture=true hp=false parentHp=true reverse=true",
    "mode 3 hpReverse true | clips=true | incomingHealBar texture=true hp=false parentHp=true reverse=true | absorbBar texture=false hp=false parentHp=true reverse=true | healAbsorbBar texture=true hp=false parentHp=true reverse=false",
    "mode 4 hpReverse false | clips=nil | incomingHealBar texture=true hp=false parentHp=false reverse=false | absorbBar texture=false hp=false parentHp=false reverse=false | healAbsorbBar texture=true hp=false parentHp=false reverse=false",
    "mode 4 hpReverse true | clips=nil | incomingHealBar texture=true hp=false parentHp=false reverse=true | absorbBar texture=false hp=false parentHp=false reverse=true | healAbsorbBar texture=true hp=false parentHp=false reverse=true",
    "mode 5 hpReverse false | clips=nil | incomingHealBar texture=false hp=false parentHp=true reverse=true | absorbBar texture=false hp=false parentHp=true reverse=true | healAbsorbBar texture=false hp=false parentHp=true reverse=true",
    "mode 5 hpReverse true | clips=nil | incomingHealBar texture=false hp=false parentHp=true reverse=false | absorbBar texture=false hp=false parentHp=true reverse=false | healAbsorbBar texture=false hp=false parentHp=true reverse=false",
    "mixed heal 2 absorb 3 hpReverse false | clips=true | clamp=true | incomingHealBar texture=false parentHp=true reverse=true | absorbBar texture=false parentHp=true reverse=false",
    "mixed heal 2 absorb 3 hpReverse true | clips=true | clamp=true | incomingHealBar texture=false parentHp=true reverse=true | absorbBar texture=false parentHp=true reverse=true",
    "mixed heal 3 absorb 3 hpReverse false | clips=true | clamp=false | incomingHealBar texture=true parentHp=true reverse=false | absorbBar texture=false parentHp=true reverse=false",
    "mixed heal 3 absorb 3 hpReverse true | clips=true | clamp=false | incomingHealBar texture=true parentHp=true reverse=true | absorbBar texture=false parentHp=true reverse=true",
    "mixed heal 4 absorb 3 hpReverse false | clips=true | clamp=false | incomingHealBar texture=true parentHp=false reverse=false | absorbBar texture=false parentHp=true reverse=false",
    "mixed heal 4 absorb 3 hpReverse true | clips=true | clamp=false | incomingHealBar texture=true parentHp=false reverse=true | absorbBar texture=false parentHp=true reverse=true",
    "mixed heal 2 absorb 4 hpReverse false | clips=nil | clamp=false | incomingHealBar texture=false parentHp=true reverse=true | absorbBar texture=false parentHp=false reverse=false",
    "mixed heal 2 absorb 4 hpReverse true | clips=nil | clamp=false | incomingHealBar texture=false parentHp=true reverse=true | absorbBar texture=false parentHp=false reverse=true",
    "mixed heal 3 absorb 4 hpReverse false | clips=true | clamp=false | incomingHealBar texture=true parentHp=true reverse=false | absorbBar texture=false parentHp=false reverse=false",
    "mixed heal 3 absorb 4 hpReverse true | clips=true | clamp=false | incomingHealBar texture=true parentHp=true reverse=true | absorbBar texture=false parentHp=false reverse=true",
    "mixed heal 5 absorb 3 hpReverse false | clips=true | clamp=true | incomingHealBar texture=false parentHp=true reverse=true | absorbBar texture=false parentHp=true reverse=false",
    "mixed heal 5 absorb 3 hpReverse true | clips=true | clamp=true | incomingHealBar texture=false parentHp=true reverse=false | absorbBar texture=false parentHp=true reverse=true",
    "mixed heal 1 absorb 4 hpReverse false | clips=nil | clamp=false | incomingHealBar texture=false parentHp=true reverse=false | absorbBar texture=false parentHp=false reverse=false",
    "mixed heal 1 absorb 4 hpReverse true | clips=nil | clamp=false | incomingHealBar texture=false parentHp=true reverse=false | absorbBar texture=false parentHp=false reverse=true",
    "mixed heal 4 absorb 4 hpReverse false | clips=nil | clamp=false | incomingHealBar texture=true parentHp=false reverse=false | absorbBar texture=false parentHp=false reverse=false",
    "mixed heal 4 absorb 4 hpReverse true | clips=nil | clamp=false | incomingHealBar texture=true parentHp=false reverse=true | absorbBar texture=false parentHp=false reverse=true",
    "defaults hpReverse false | clips=true | incomingHealBar texture=true parentHp=true reverse=false | absorbBar texture=false parentHp=true reverse=true | healAbsorbBar texture=true parentHp=true reverse=true",
    "defaults hpReverse true | clips=true | incomingHealBar texture=true parentHp=true reverse=true | absorbBar texture=false parentHp=true reverse=true | healAbsorbBar texture=true parentHp=true reverse=false",
}
local produced = {}
for mode = 1, 5 do
    for _, reverse in ipairs({ false, true }) do
        local f = NewFrame({ enabled = true, heal = true, absorb = true, healAbsorb = true,
            healAnchorMode = mode, absorbAnchorMode = mode, healAbsorbAnchorMode = mode }, reverse)
        local texture = f.hpBar:GetStatusBarTexture()
        local parts = {}
        for _, name in ipairs({ "incomingHealBar", "absorbBar", "healAbsorbBar" }) do
            local bar = f[name]
            if bar then
                local toTexture, toHp = Anchors(bar, f.hpBar, texture)
                parts[#parts + 1] = string.format("%s texture=%s hp=%s parentHp=%s reverse=%s", name, tostring(toTexture),
                    tostring(toHp), tostring(bar.parent == f.hpBar), tostring(bar.reverse))
            else
                parts[#parts + 1] = name .. " none"
            end
        end
        produced[#produced + 1] = string.format("mode %d hpReverse %s | clips=%s | %s", mode, tostring(reverse),
            tostring(f.hpBar.clips), table.concat(parts, " | "))
    end
end
-- Heal and absorb following differently: the update events lay the absorb bar out again.
for _, pair in ipairs({ { 2, 3 }, { 3, 3 }, { 4, 3 }, { 2, 4 }, { 3, 4 }, { 5, 3 }, { 1, 4 }, { 4, 4 } }) do
    for _, reverse in ipairs({ false, true }) do
        local f = NewFrame({ enabled = true, heal = true, absorb = true, healAbsorb = false,
            healAnchorMode = pair[1], absorbAnchorMode = pair[2], healAbsorbAnchorMode = 3 }, reverse)
        for _, event in ipairs({ "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEALTH" }) do
            Event(f, event)
        end
        local texture = f.hpBar:GetStatusBarTexture()
        local parts = {}
        for _, name in ipairs({ "incomingHealBar", "absorbBar" }) do
            local bar = f[name]
            if bar then
                parts[#parts + 1] = string.format("%s texture=%s parentHp=%s reverse=%s", name,
                    tostring((Anchors(bar, f.hpBar, texture))), tostring(bar.parent == f.hpBar), tostring(bar.reverse))
            else
                parts[#parts + 1] = name .. " none"
            end
        end
        produced[#produced + 1] = string.format("mixed heal %d absorb %d hpReverse %s | clips=%s | clamp=%s | %s", pair[1],
            pair[2], tostring(reverse), tostring(f.hpBar.clips), tostring(f._msufPredictionMixedFollowClamp),
            table.concat(parts, " | "))
    end
end
-- No stored anchor modes: the fallbacks at the call sites decide.
for _, reverse in ipairs({ false, true }) do
    local f = NewFrame({ enabled = true, heal = true, absorb = true, healAbsorb = true }, reverse)
    local texture = f.hpBar:GetStatusBarTexture()
    local parts = {}
    for _, name in ipairs({ "incomingHealBar", "absorbBar", "healAbsorbBar" }) do
        local bar = f[name]
        if bar then
            parts[#parts + 1] = string.format("%s texture=%s parentHp=%s reverse=%s", name,
                tostring((Anchors(bar, f.hpBar, texture))), tostring(bar.parent == f.hpBar), tostring(bar.reverse))
        else
            parts[#parts + 1] = name .. " none"
        end
    end
    produced[#produced + 1] = string.format("defaults hpReverse %s | clips=%s | %s", tostring(reverse),
        tostring(f.hpBar.clips), table.concat(parts, " | "))
end
Check(#produced == #LAYOUT, "the layout fixture produced " .. #produced .. " lines, was " .. #LAYOUT)
for index, line in ipairs(LAYOUT) do
    Check(produced[index] == line, "layout decision changed:\n  now: " .. produced[index] .. "\n  was: " .. line)
    cases = cases + 1
end
print("prediction_anchor_mode_smoke: ok (" .. cases .. " cases)")
