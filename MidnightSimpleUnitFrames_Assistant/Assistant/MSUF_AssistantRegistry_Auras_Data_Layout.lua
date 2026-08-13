-- Assistant Auras layout and anchor static values.
-- Loaded after MSUF_AssistantRegistry_Auras_Data.lua; consumers read A.AurasRegistryData.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.AurasRegistryData or {}
A.AurasRegistryData = Data

Data.AURA_GROWTH_VALUES = { "RIGHT", "LEFT", "UP", "DOWN" }
Data.AURA_GROWTH_ALIASES = {
    right = "RIGHT",
    rechts = "RIGHT",
    left = "LEFT",
    links = "LEFT",
    up = "UP",
    hoch = "UP",
    down = "DOWN",
    runter = "DOWN",
}
Data.AURA_ROW_WRAP_VALUES = { "DOWN", "UP" }
Data.AURA_ROW_WRAP_ALIASES = {
    down = "DOWN",
    runter = "DOWN",
    below = "DOWN",
    up = "UP",
    hoch = "UP",
    above = "UP",
}
Data.AURA_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER" }
Data.AURA_ANCHOR_ALIASES = {
    center = "CENTER",
    middle = "CENTER",
    top = "TOPLEFT",
    lefttop = "TOPLEFT",
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    righttop = "TOPRIGHT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    bottom = "BOTTOMLEFT",
    leftbottom = "BOTTOMLEFT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    rightbottom = "BOTTOMRIGHT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
}
Data.AURA_LANE_GROWTH_VALUES = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP", "UP", "DOWN" }
Data.AURA_LANE_GROWTH_ALIASES = {
    right = "RIGHTDOWN",
    rightdown = "RIGHTDOWN",
    ["right down"] = "RIGHTDOWN",
    down = "DOWN",
    left = "LEFTDOWN",
    leftdown = "LEFTDOWN",
    ["left down"] = "LEFTDOWN",
    up = "UP",
    rightup = "RIGHTUP",
    ["right up"] = "RIGHTUP",
    leftup = "LEFTUP",
    ["left up"] = "LEFTUP",
}
Data.AURA_STACK_ANCHOR_VALUES = { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT" }
Data.AURA_STACK_ANCHOR_ALIASES = {
    top = "TOPRIGHT",
    right = "TOPRIGHT",
    topright = "TOPRIGHT",
    righttop = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    left = "TOPLEFT",
    topleft = "TOPLEFT",
    top_left = "TOPLEFT",
    lefttop = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    bottom = "BOTTOMRIGHT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
}
