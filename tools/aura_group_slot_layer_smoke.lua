-- Regression for GitHub #85: fixed one-icon Group Aura lanes share one native
-- owner, but each AuraSlot must retain its own configured 0..30 Layer.
--
-- This executes the production BuildGroupLaneSlotOptions initializer in a
-- deliberately small frame model. Blizzard seals the AuraButton immediately
-- after initializeFrame, so level/strata must already be final when styling
-- creates the cooldown and text children. No later update may mutate them.

_G = _G or _ENV

local function ResolvePath(relative)
    local candidates = {
        "MidnightSimpleUnitFrames/" .. relative,
        relative,
    }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "rb")
        if handle then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate " .. relative)
end

local function Read(relative)
    local handle = assert(io.open(ResolvePath(relative), "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local MSUF = { UF = {} }
assert(loadfile(ResolvePath("Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")))(
    "MidnightSimpleUnitFrames", MSUF)
local Layers = assert(MSUF.UF.Layers)

local runtimeSource = Read("Auras3/MSUF_Auras3_UnitFrames.lua")
local initializerStart = assert(runtimeSource:find(
    "local function BuildGroupLaneSlotOptions", 1, true))
local initializerEnd = assert(runtimeSource:find(
    "\nlocal function UpdateGroupLaneSlot", initializerStart, true))
local initializerSource = runtimeSource:sub(initializerStart, initializerEnd - 1)

local prepared = {}
local environment = setmetatable({
    AuraSortEnums = function() return "DEFAULT", "NORMAL" end,
    ManagedLaneFrameLevel = function(_, lane)
        return Layers.ElementLevel(lane and lane.layer, 1, 0)
    end,
    ResolveFrameStrata = function(parentFrame)
        return parentFrame:GetFrameStrata()
    end,
    SyncFrameStrata = function(frame, strata)
        frame:SetFrameStrata(strata)
    end,
    PrepareAuraButton = function(button, lane, index)
        prepared[button] = {
            frameLevel = button:GetFrameLevel(),
            frameStrata = button:GetFrameStrata(),
            lane = lane,
            index = index,
        }
    end,
}, { __index = _G })

local chunk = assert(loadstring(initializerSource .. "\nreturn BuildGroupLaneSlotOptions",
    "@BuildGroupLaneSlotOptions"))
setfenv(chunk, environment)
local BuildGroupLaneSlotOptions = assert(chunk())

local parent = { frameLevel = 17, frameStrata = "MEDIUM" }
function parent:GetFrameLevel() return self.frameLevel end
function parent:GetFrameStrata() return self.frameStrata end

local function NewButton()
    local button = { frameLevel = 18, frameStrata = "LOW" }
    function button:SetFrameLevel(level) self.frameLevel = level end
    function button:GetFrameLevel() return self.frameLevel end
    function button:SetFrameStrata(strata) self.frameStrata = strata end
    function button:GetFrameStrata() return self.frameStrata end
    function button:ClearAllPoints() self.point = nil end
    function button:SetPoint(...) self.point = { ... } end
    function button:SetAlpha(alpha) self.alpha = alpha end
    return button
end

local function Lane(kind, layer)
    return {
        kind = kind,
        layer = layer,
        strata = "AUTO",
        anchor = "TOPLEFT",
        x = layer,
        y = -layer,
        alpha = 1,
        nativeFilter = kind == "debuff" and "HARMFUL" or "HELPFUL",
    }
end

-- Model one shared native owner containing explicit Spell/Dispel buttons, a
-- flowing lane on Layer 4, and three fixed AuraSlots on unrelated Layers.
local spellLevel = Layers.ElementLevel(9, 9, 1)
local dispelLevel = Layers.ElementLevel(0, 0, 12)
local flowLevel = Layers.ElementLevel(4, 1, 0)
local container = {
    frameLevel = flowLevel,
    [1] = { frameLevel = spellLevel },
    [2] = { frameLevel = dispelLevel },
}
local lanes = {
    Lane("buff", 2),
    Lane("debuff", 30),
    Lane("external", 7),
}

for i = 1, #lanes do
    local lane = lanes[i]
    local buttonIndex = i + 2
    local button = NewButton()
    local options = BuildGroupLaneSlotOptions(container, lane, parent, buttonIndex)
    options.initializeFrame(button)

    Equal(container[buttonIndex], button, lane.kind .. " slot was not retained")
    Equal(button.frameLevel, Layers.ElementLevel(lane.layer, 1, 0) + 1,
        lane.kind .. " slot ignored its independent Layer")
    Equal(button.frameStrata, parent.frameStrata,
        lane.kind .. " slot did not resolve the GroupFrame strata")
    Equal(prepared[button].frameLevel, button.frameLevel,
        lane.kind .. " level was not final before PrepareAuraButton")
    Equal(prepared[button].frameStrata, button.frameStrata,
        lane.kind .. " strata was not final before PrepareAuraButton")
end

Equal(container.frameLevel, flowLevel,
    "fixed AuraSlot Layer changed the flowing AuraGroup container Layer")
Equal(container[1].frameLevel, spellLevel,
    "fixed AuraSlot Layer changed the Spell Indicator Layer")
Equal(container[2].frameLevel, dispelLevel,
    "fixed AuraSlot Layer changed the Dispel sensor Layer")

local updateSource = runtimeSource:sub(initializerEnd,
    assert(runtimeSource:find("\nlocal function UpdateGroupFlowLane", initializerEnd, true)) - 1)
assert(not updateSource:find("SetFrameLevel", 1, true)
    and not updateSource:find("SetFrameStrata", 1, true),
    "sealed Group AuraSlot buttons are mutated by the update path")

print("aura_group_slot_layer_smoke: ok (Layers 2/30/7 + mixed Spell/Dispel/flow owner)")
