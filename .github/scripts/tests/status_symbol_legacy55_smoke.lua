-- Regression coverage for every native MSUF 5.5 unit-frame status symbol and
-- for the DEFAULT combat fallback that previously rendered as a white square.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.issecretvalue = function() return false end
_G.C_Texture = { GetAtlasInfo = function() return nil end }
_G.UnitAffectingCombat = function() return true end
_G.UnitHasIncomingResurrection = function() return true end
_G.UnitIsPlayer = function() return true end
_G.IsResting = function() return true end

local elements = {}
local UF = {
    Layers = {},
    RegisterElement = function(name, element) elements[name] = element end,
    UnitExistsSafe = function() return true end,
    FreshUnitState = function() return nil end,
    ReadConnectedCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
}

local MSUF = {
    UF = UF,
    Apply = {
        Shown = function(region, shown) region.shown = shown == true end,
        Texture = function(region, texture) region.texture = texture end,
        Text = function(region, value) region.text = value end,
    },
}
_G.MSUF_NS = MSUF

local function NewTexture()
    local texture = {}
    function texture:SetShown(shown) self.shown = shown == true end
    function texture:SetTexture(value) self.texture = value end
    function texture:SetAtlas(value) self.atlas = value end
    function texture:SetTexCoord(l, r, t, b) self.texCoord = { l, r, t, b } end
    return texture
end

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local Runtime = assert(MSUF.UFStatusRuntime, "status runtime missing")
local STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local SYMBOL_BASE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\"

local function Render(kind, symbol, useMidnight)
    local field = kind == "combat" and "combatStateIndicatorIcon"
        or kind == "resting" and "restingIndicatorIcon"
        or "incomingResIndicatorIcon"
    local frame = { unit = "player", [field] = NewTexture() }
    local status = { testMode = true, useMidnight = useMidnight == true, [kind] = { enabled = true, symbol = symbol } }
    if kind == "combat" then
        Runtime.UpdateCombat(frame, status)
    elseif kind == "resting" then
        Runtime.UpdateResting(frame, status)
    else
        Runtime.UpdateIncomingRes(frame, status)
    end
    return frame[field]
end

local defaultCombat = Render("combat", "DEFAULT")
Check(defaultCombat.texture == STATE_TEXTURE, "DEFAULT combat did not use the safe 5.5 texture fallback")
Check(defaultCombat.atlas == nil, "DEFAULT combat assigned an unavailable atlas")
Check(defaultCombat.texCoord and defaultCombat.texCoord[1] == 0.5 and defaultCombat.texCoord[2] == 1
    and defaultCombat.texCoord[3] == 0 and defaultCombat.texCoord[4] == 0.5,
    "DEFAULT combat fallback lost its 5.5 texture coordinates")

local families = {
    combat = {
        folder = "Combat", classicSuffix = "_classic_128_clean.tga", midnightSuffix = "_midnight_128_clean.tga",
        symbols = {
            "weapon_axes_crossed", "weapon_bows_crossed", "weapon_crossbows_crossed",
            "weapon_daggers_crossed", "weapon_fishing_poles_crossed", "weapon_fist_crossed",
            "weapon_guns_crossed", "weapon_maces_crossed", "weapon_polearms_crossed",
            "weapon_shuriken", "weapon_staves_crossed", "weapon_swords_crossed",
            "weapon_thrown_crossed", "weapon_wands_crossed", "weapon_warglaives_crossed",
        },
    },
    resting = {
        folder = "Rested", classicSuffix = "_classic_64.tga", midnightSuffix = "_midnight_64.tga",
        symbols = {
            "rested_moonzzz", "rested_moonzzzz", "rested_sleep_zzzz",
            "rested_zzz_compact", "rested_zzz_diag", "rested_zzz_stack",
        },
    },
    incomingRes = {
        folder = "Ress", classicSuffix = "_classic_64.tga", midnightSuffix = "_midnight_64.tga",
        symbols = {
            "resurrection_ankh", "resurrection_cross", "resurrection_soul", "resurrection_wings",
        },
    },
}

for kind, family in pairs(families) do
    for i = 1, #family.symbols do
        local symbol = family.symbols[i]
        for _, style in ipairs({
            { midnight = false, suffix = family.classicSuffix, label = "classic" },
            { midnight = true, suffix = family.midnightSuffix, label = "midnight" },
        }) do
            local tex = Render(kind, symbol, style.midnight)
            local expected = SYMBOL_BASE .. family.folder .. "\\" .. symbol .. style.suffix
            Check(tex.texture == expected,
                kind .. " legacy " .. style.label .. " symbol did not survive: " .. symbol)
            Check(tex.shown == true,
                kind .. " legacy " .. style.label .. " symbol was hidden: " .. symbol)
        end
    end
end

local invalidCombat = Render("combat", "COMBAT_DOES_NOT_EXIST")
Check(invalidCombat.texture == STATE_TEXTURE, "unknown legacy combat value generated a missing texture path")

print("PASS legacy 5.5 status symbols: all native IDs resolve and invalid/default combat falls back safely")
