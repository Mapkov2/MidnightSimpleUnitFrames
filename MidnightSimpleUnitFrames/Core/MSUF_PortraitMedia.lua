local addonName, ns = ...

ns.PortraitMedia = ns.PortraitMedia or {}
local PM = ns.PortraitMedia

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
    BLIZZARD = { id = "BLIZZARD", text = "Blizzard Class Icon" },
    RONDO_COLOR = { id = "RONDO_COLOR", text = "Rondo Colored Border", base = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Portraits\\Rondo\\class_colored_border\\64x64\\" },
    RONDO_WOW = { id = "RONDO_WOW", text = "Rondo WoW Icon Border", base = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Portraits\\Rondo\\wow_icon_border\\64x64\\" },
}

local ORDER = { "BLIZZARD", "RONDO_COLOR", "RONDO_WOW" }
local OPTIONS = {}
for i = 1, #ORDER do
    local id = ORDER[i]
    local pack = PACKS[id]
    OPTIONS[#OPTIONS + 1] = { value = id, text = pack.text }
end
PM.Packs = PACKS
PM.PackOrder = ORDER
PM.PackOptions = OPTIONS
PM.ClassFile = CLASS_FILE

function PM.GetPackOptions()
    return OPTIONS
end

function PM.GetPackText(id)
    local pack = PACKS[id or "BLIZZARD"] or PACKS.BLIZZARD
    return pack.text or "Blizzard Class Icon"
end

function PM.NormalizeClassPack(id)
    if type(id) ~= "string" or not PACKS[id] then
        return "BLIZZARD"
    end
    return id
end

function PM.ResolveClassPortrait(classToken, packId)
    packId = PM.NormalizeClassPack(packId)
    if packId == "BLIZZARD" then
        local coords = (classToken and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classToken]) or nil
        if not coords then return nil end
        return {
            texture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
            left = coords[1] or 0,
            right = coords[2] or 1,
            top = coords[3] or 0,
            bottom = coords[4] or 1,
            isAtlas = false,
        }
    end

    local pack = PACKS[packId]
    local file = classToken and CLASS_FILE[classToken]
    if not pack or not file then
        return PM.ResolveClassPortrait(classToken, "BLIZZARD")
    end

    return {
        texture = pack.base .. file .. "_64.tga",
        left = 0,
        right = 1,
        top = 0,
        bottom = 1,
        isAtlas = false,
    }
end
