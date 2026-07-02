-- Assistant Gameplay totem/statue frame setting registry.
-- Loaded before MSUF_AssistantRegistry_Gameplay.lua; gameplay runtime remains feature-owned.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GameplayRegistry = A.GameplayRegistry or {}

local FRAME_ANCHOR_VALUES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local FRAME_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    ["oben links"] = "TOPLEFT",
    top = "TOP",
    oben = "TOP",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    ["oben rechts"] = "TOPRIGHT",
    left = "LEFT",
    links = "LEFT",
    center = "CENTER",
    centre = "CENTER",
    mitte = "CENTER",
    right = "RIGHT",
    rechts = "RIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    ["unten links"] = "BOTTOMLEFT",
    bottom = "BOTTOM",
    unten = "BOTTOM",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    ["unten rechts"] = "BOTTOMRIGHT",
}

function A.GameplayRegistry.RegisterPlayerTotemSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterGameplayBoolean = ctx.RegisterGameplayBoolean
    local RegisterGameplayNumber = ctx.RegisterGameplayNumber
    local RegisterGameplayEnum = ctx.RegisterGameplayEnum
    local GameplayAliases = ctx.GameplayAliases
    if type(RegisterGameplayBoolean) ~= "function" or type(RegisterGameplayNumber) ~= "function" then return end
    if type(RegisterGameplayEnum) ~= "function" or type(GameplayAliases) ~= "function" then return end

    RegisterGameplayBoolean("enablePlayerTotems", "enabled", "Blizzard Totem Frame", false, {
        "blizzard totem frame enabled", "player totem frame enabled", "totem frame enabled", "statue frame enabled",
        "totem rahmen", "totemrahmen", "totem rahmen anzeigen", "totemrahmen anzeigen",
        "statuen rahmen", "statuenrahmen", "statuen rahmen anzeigen", "statue rahmen anzeigen",
    }, {
        category = "Gameplay / Totem Frame",
        frameType = "playerTotems",
        reason = "MSUF_ASSISTANT_PLAYER_TOTEMS",
        matchLabel = false,
    })
    RegisterGameplayNumber("playerTotemsIconSize", "size", "Totem Frame Icon Size", 24, 8, 64, GameplayAliases("totem frame", "icon size", "blizzard totem frame icon size", "statue frame icon size", "totem rahmen", "symbol groesse", "totemrahmen symbol groesse", "statuenrahmen symbol groesse"), {
        category = "Gameplay / Totem Frame",
        frameType = "playerTotems",
        reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_SIZE",
    })
    RegisterGameplayNumber("playerTotemsOffsetX", "offsetX", "Totem Frame Offset X", 0, -200, 200, {
        "totem frame x", "totem frame x offset", "blizzard totem frame x", "statue frame x",
        "totem rahmen x", "totemrahmen x", "totem rahmen x versatz", "statuen rahmen x",
    }, {
        category = "Gameplay / Totem Frame",
        frameType = "playerTotems",
        reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_X",
    })
    RegisterGameplayNumber("playerTotemsOffsetY", "offsetY", "Totem Frame Offset Y", -6, -200, 200, {
        "totem frame y", "totem frame y offset", "blizzard totem frame y", "statue frame y",
        "totem rahmen y", "totemrahmen y", "totem rahmen y versatz", "statuen rahmen y",
    }, {
        category = "Gameplay / Totem Frame",
        frameType = "playerTotems",
        reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_Y",
    })
    RegisterGameplayEnum("playerTotemsAnchorFrom", "anchorFrom", "Totem Frame Anchor from", "TOPLEFT", FRAME_ANCHOR_VALUES, {
        "totem frame from point", "totem frame anchor from point", "blizzard totem frame from point",
        "totem frame anchor from", "totem frame from", "blizzard totem frame anchor from",
        "totem rahmen anker von", "totemrahmen anker von", "totem rahmen von punkt", "statuen rahmen anker von",
    }, {
        category = "Gameplay / Totem Frame",
        frameType = "playerTotems",
        reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_ANCHOR_FROM",
        valueAliases = FRAME_ANCHOR_ALIASES,
    })
    RegisterGameplayEnum("playerTotemsAnchorTo", "anchorTo", "Totem Frame Anchor to", "BOTTOMLEFT", FRAME_ANCHOR_VALUES, {
        "totem frame to point", "totem frame anchor to point", "totem frame attach point", "blizzard totem frame to point",
        "totem frame anchor to", "totem frame to", "blizzard totem frame anchor to",
        "totem rahmen anker zu", "totemrahmen anker zu", "totem rahmen zu punkt", "statuen rahmen anker zu",
    }, {
        category = "Gameplay / Totem Frame",
        frameType = "playerTotems",
        reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_ANCHOR_TO",
        valueAliases = FRAME_ANCHOR_ALIASES,
    })
end
