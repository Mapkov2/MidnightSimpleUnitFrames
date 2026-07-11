-- Assistant ClassPower placement text helpers for anchoring commands.
-- Loaded before MSUF_AssistantRegistry_ClassPower_Anchoring.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

local CLASS_POWER_PLACEMENT_TERMS = {
    "under", "below", "beneath", "bottom of", "underneath", "unter", "darunter",
    "above", "over", "top of", "ueber", "darueber",
    "on player", "on the player", "inside player", "inside the player",
}

local function ClassPowerPlacementForText(text)
    text = tostring(text or ""):lower()
    local hay = " " .. text:gsub("[^%w]+", " ") .. " "
    if hay:find(" under ", 1, true)
        or hay:find(" below ", 1, true)
        or hay:find(" beneath ", 1, true)
        or hay:find(" bottom of ", 1, true)
        or hay:find(" underneath ", 1, true)
        or hay:find(" unter ", 1, true)
        or hay:find(" darunter ", 1, true)
    then
        return "below"
    end
    if hay:find(" above ", 1, true)
        or hay:find(" over ", 1, true)
        or hay:find(" top of ", 1, true)
        or hay:find(" ueber ", 1, true)
        or hay:find(" darueber ", 1, true)
    then
        return "above"
    end
    if hay:find(" on player ", 1, true)
        or hay:find(" on the player ", 1, true)
        or hay:find(" inside player ", 1, true)
        or hay:find(" inside the player ", 1, true)
    then
        return "top"
    end
    return nil
end

local function ClassPowerPlacementOffsetsForText(text)
    local db = _G.MSUF_DB or {}
    local player = type(db.player) == "table" and db.player or {}
    local bars = type(db.bars) == "table" and db.bars or {}
    local playerH = tonumber(player.height) or 40
    local cpH = tonumber(bars.classPowerHeight) or 4
    local placement = ClassPowerPlacementForText(text)
    if placement == "below" then return 0, -math.floor(playerH + cpH + 6 + 0.5) end
    if placement == "above" then return 0, math.floor(cpH + 6 + 0.5) end
    if placement == "top" then return 0, 0 end
    return nil, nil
end

local function ClassPowerPlacementXValue(_, _, text)
    local x = ClassPowerPlacementOffsetsForText(text)
    return x
end

local function ClassPowerPlacementYValue(_, _, text)
    local _, y = ClassPowerPlacementOffsetsForText(text)
    return y
end

A.ClassPowerRegistry.CLASS_POWER_PLACEMENT_TERMS = CLASS_POWER_PLACEMENT_TERMS
A.ClassPowerRegistry.ClassPowerPlacementXValue = ClassPowerPlacementXValue
A.ClassPowerRegistry.ClassPowerPlacementYValue = ClassPowerPlacementYValue
