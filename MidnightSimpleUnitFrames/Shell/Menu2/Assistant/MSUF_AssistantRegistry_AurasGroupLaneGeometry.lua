-- Assistant group aura lane geometry settings.
-- Loaded before MSUF_AssistantRegistry_AurasGroupLaneSettings.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
A.AurasRegistry = A.AurasRegistry or {}

local ANCHOR_VALUE_ALIASES = {
    center = "CENTER",
    middle = "CENTER",
    topleft = "TOPLEFT",
    top_left = "TOPLEFT",
    top = "TOPLEFT",
    topright = "TOPRIGHT",
    top_right = "TOPRIGHT",
    bottomleft = "BOTTOMLEFT",
    bottom_left = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
    bottom_right = "BOTTOMRIGHT",
}

local GROWTH_VALUE_ALIASES = {
    rightdown = "RIGHTDOWN",
    right = "RIGHTDOWN",
    down = "RIGHTDOWN",
    leftdown = "LEFTDOWN",
    left = "LEFTDOWN",
    rightup = "RIGHTUP",
    up = "RIGHTUP",
    leftup = "LEFTUP",
}

local function AddStrictAliases(aliases, AddGFAuraStrictAliases, scope, lane, nouns)
    for i = 1, #nouns do
        AddGFAuraStrictAliases(aliases, scope, lane, nouns[i])
    end
end

local function AddDirectionalAliases(aliases, lane, negativeWord, positiveWord)
    aliases[#aliases + 1] = "all group aura " .. negativeWord
    aliases[#aliases + 1] = "all group auras " .. negativeWord
    aliases[#aliases + 1] = "all group aura " .. positiveWord
    aliases[#aliases + 1] = "all group auras " .. positiveWord
    aliases[#aliases + 1] = "all aura " .. negativeWord
    aliases[#aliases + 1] = "all auras " .. negativeWord
    aliases[#aliases + 1] = "all aura " .. positiveWord
    aliases[#aliases + 1] = "all auras " .. positiveWord
    aliases[#aliases + 1] = "all group frame auras " .. negativeWord
    aliases[#aliases + 1] = "all group frame auras " .. positiveWord
    aliases[#aliases + 1] = lane == "buff" and "all group buffs " .. negativeWord or "all group debuffs " .. negativeWord
    aliases[#aliases + 1] = lane == "buff" and "all group buffs " .. positiveWord or "all group debuffs " .. positiveWord
    aliases[#aliases + 1] = lane == "buff" and "all buffs " .. negativeWord or "all debuffs " .. negativeWord
    aliases[#aliases + 1] = lane == "buff" and "all buffs " .. positiveWord or "all debuffs " .. positiveWord
end

function A.AurasRegistry.RegisterGroupAuraLaneGeometrySettings(ctx, scope, lane, laneInfo)
    if type(ctx) ~= "table" then return end
    if type(scope) ~= "string" or type(lane) ~= "string" or type(laneInfo) ~= "table" then return end

    local Assistant = ctx.A or A
    local AddGFAuraAliases = ctx.AddGFAuraAliases
    local AddGFAuraStrictAliases = ctx.AddGFAuraStrictAliases
    local RegisterGFAuraNumber = ctx.RegisterGFAuraNumber
    local RegisterGFAuraEnum = ctx.RegisterGFAuraEnum
    local GF_AURA_ANCHORS = ctx.GF_AURA_ANCHORS or {}
    local GF_AURA_GROWTH = ctx.GF_AURA_GROWTH or {}

    if type(AddGFAuraAliases) ~= "function" or type(AddGFAuraStrictAliases) ~= "function" then return end
    if type(RegisterGFAuraNumber) ~= "function" or type(RegisterGFAuraEnum) ~= "function" then return end

    local anchorDefault = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
    local growthDefault = lane == "buff" and "LEFTUP" or "RIGHTDOWN"

    local aliases = {}
    AddStrictAliases(aliases, AddGFAuraStrictAliases, scope, lane, { "x", "x offset", "left", "right", "links", "rechts" })
    Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "x", "x offset", "left", "right", "links", "rechts" })
    AddDirectionalAliases(aliases, lane, "left", "right")
    RegisterGFAuraNumber(scope, lane, "OffsetX", "x", laneInfo.label .. " X Offset", 0, -160, 160, aliases, "geometry", { moveAxis = "x", moveStep = 10 })

    aliases = {}
    AddStrictAliases(aliases, AddGFAuraStrictAliases, scope, lane, { "y", "y offset", "up", "down", "hoch", "runter" })
    Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "y", "y offset", "up", "down", "hoch", "runter" })
    AddDirectionalAliases(aliases, lane, "up", "down")
    RegisterGFAuraNumber(scope, lane, "OffsetY", "y", laneInfo.label .. " Y Offset", 0, -160, 160, aliases, "geometry", { moveAxis = "y", moveStep = 10 })

    aliases = {}
    AddGFAuraAliases(aliases, scope, lane, "anchor")
    Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "anchor", "anchor point", "position anchor" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "anchor", "anchor point", "position anchor" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "anchor", "anchor point", "position anchor" })
    RegisterGFAuraEnum(scope, lane, "Anchor", "anchor", laneInfo.label .. " Anchor", GF_AURA_ANCHORS, ANCHOR_VALUE_ALIASES, anchorDefault, aliases, "geometry")

    aliases = {}
    AddGFAuraAliases(aliases, scope, lane, "growth")
    AddGFAuraAliases(aliases, scope, lane, "growth direction")
    AddGFAuraAliases(aliases, scope, lane, "grow")
    AddGFAuraAliases(aliases, scope, lane, "grow direction")
    Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "growth", "grow", "growth direction", "grow direction" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "growth", "grow", "growth direction", "grow direction" })
    Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "growth", "grow", "growth direction", "grow direction" })
    RegisterGFAuraEnum(scope, lane, "Growth", "growth", laneInfo.label .. " Growth", GF_AURA_GROWTH, GROWTH_VALUE_ALIASES, growthDefault, aliases, "geometry")

    aliases = {}
    AddGFAuraAliases(aliases, scope, lane, "cooldown anchor")
    AddGFAuraAliases(aliases, scope, lane, "timer anchor")
    RegisterGFAuraEnum(scope, lane, "CooldownAnchor", "cooldownAnchor", laneInfo.label .. " Cooldown Anchor", GF_AURA_ANCHORS, ANCHOR_VALUE_ALIASES, "CENTER", aliases, "geometry")
end
