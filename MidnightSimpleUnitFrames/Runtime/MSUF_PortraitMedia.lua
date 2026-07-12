--- Runtime/MSUF_PortraitMedia.lua
--- Declarative class portrait media catalogue.
---
--- Runtime portrait code asks this module for pack options and class-token
--- visuals. Keep this file data-focused: it should not create frames or apply
--- portrait layout.

local addonName, MSUF = ...

MSUF.PortraitMedia = MSUF.PortraitMedia or {}
local PM = MSUF.PortraitMedia

local base = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Portraits\\Rondo\\"
local BLIZZARD_CLASS_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_ICON_TCOORDS = _G.CLASS_ICON_TCOORDS

local CLASS_FILE = {
    DEATHKNIGHT = "Death Knight",
    DEMONHUNTER = "Demon Hunter",
    DRUID = "Druid",
    EVOKER = "Evoker",
    HUNTER = "Hunter",
    MAGE = "Mage",
    MONK = "Monk",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
}

local PACKS = {
    BLIZZARD = { text = "Blizzard Class Icon" },
    RONDO_COLOR = { text = "Rondo Colored Border", base = base .. "class_colored_border\\64x64\\" },
    RONDO_WOW = { text = "Rondo WoW Icon Border", base = base .. "wow_icon_border\\64x64\\" },
}

local VISUALS = {
    BLIZZARD = {},
    RONDO_COLOR = {},
    RONDO_WOW = {},
}

local ORDER = { "BLIZZARD", "RONDO_COLOR", "RONDO_WOW" }
local OPTIONS = {}
for i = 1, #ORDER do
    local id = ORDER[i]
    OPTIONS[i] = { value = id, text = PACKS[id].text }
end

-- Blizzard may expose non-playable/pseudo class tokens in this table (for
-- example TRAVELER on 12.1). They have no bundled Rondo asset, but they still
-- need a valid Blizzard-class fallback instead of a missing-media placeholder.
for classToken, coords in pairs(CLASS_ICON_TCOORDS or {}) do
    VISUALS.BLIZZARD[classToken] = {
        atlas = "classicon-" .. classToken,
        texture = BLIZZARD_CLASS_TEXTURE,
        left = coords[1] or 0,
        right = coords[2] or 1,
        top = coords[3] or 0,
        bottom = coords[4] or 1,
    }
end

-- Custom packs intentionally contain only real playable-class artwork.
for classToken, file in pairs(CLASS_FILE) do
    VISUALS.RONDO_COLOR[classToken] = {
        texture = PACKS.RONDO_COLOR.base .. file .. "_64.tga",
        left = 0,
        right = 1,
        top = 0,
        bottom = 1,
    }
    VISUALS.RONDO_WOW[classToken] = {
        texture = PACKS.RONDO_WOW.base .. file .. "_64.tga",
        left = 0,
        right = 1,
        top = 0,
        bottom = 1,
    }
end

PM.Packs = PACKS
PM.PackOrder = ORDER
PM.PackOptions = OPTIONS
PM.ClassFile = CLASS_FILE
PM.ClassPortraitVisuals = VISUALS

function PM.GetPackOptions()
    return OPTIONS
end

function PM.NormalizeClassPack(id)
    if type(id) == "string" and PACKS[id] then
        return id
    end
    return "BLIZZARD"
end

function PM.ResolveClassPortrait(classToken, packId)
    packId = PM.NormalizeClassPack(packId)
    local visual = classToken and VISUALS[packId] and VISUALS[packId][classToken]
    if visual then
        return visual
    end
    return packId ~= "BLIZZARD" and classToken and VISUALS.BLIZZARD[classToken] or nil
end
