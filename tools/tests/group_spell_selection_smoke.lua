local root = assert(arg[1], "repository root argument missing")
local base = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return source
end
local function Nop() end
local scope, playerSpec = "party", "HolyPaladin"
local configs = {}
local registry = {
    SpecInfo = { HolyPaladin = {}, DisciplinePriest = {} },
    TrackableAuras = {
        HolyPaladin = { { name = "BeaconOfLight" }, { name = "BlessingOfProtection" } },
        DisciplinePriest = { { name = "PowerWordShield" }, { name = "PainSuppression" } },
    },
    GetPlayerSpec = function() return playerSpec end,
}
local M = {
    Widgets = {}, Theme = {}, WordList = function() return {} end,
    Assign = function(target, values) for key, value in pairs(values) do target[key] = value end end,
    GroupPage = {
        GF = function() return { SpellIndicators = registry } end,
        Conf = function(kind)
            if not configs[kind] then configs[kind] = { spellIndicators = { enabled = true } } end
            return configs[kind]
        end,
        CurrentScope = function() return scope end,
        QueueGF = Nop, RefreshGFPreview = Nop,
    },
}
local namespace = { MSUF2 = M }
assert(loadfile(base .. "MSUF_Menu2_Group_SpellModel.lua"))("MidnightSimpleUnitFrames", namespace)
local GP = M.GroupPage
M.Refresh = function() GP.CurrentSpellAura(scope) end

-- Execute the real page imports and the two selection callbacks without building frames.
-- Loading the model alone would miss a page-local override of its setters.
local page = Read(base .. "MSUF_Menu2_GroupIndicators.lua")
local prefixEnd = assert(page:find("local function IconPackValues(", 1, true))
local clickStart = assert(page:find("function SpellTileGrid:OnMouseUp(", 1, true))
local clickEnd = assert(page:find("local function SpellTileOnEnter(", clickStart, true))
local dropdownStart = assert(page:find("local auraDrop = W.Dropdown(", 1, true))
local setterStart = assert(page:find("function(value)", dropdownStart, true))
local setterEnd = assert(page:find("\n        end,", setterStart, true)) + #"\n        end" - 1
local callbacks = page:sub(1, prefixEnd - 1)
    .. "\nlocal SpellTileGrid = {}\n" .. page:sub(clickStart, clickEnd - 1)
    .. "\nlocal RefreshSpellIndicatorState = M.Refresh\nlocal RequestSpellControlRefresh = function() end\n"
    .. "local dropdownSelect = " .. page:sub(setterStart, setterEnd)
    .. "\nreturn SpellTileGrid.OnMouseUp, dropdownSelect, ClearCurrentSpellAura\n"
local click, dropdown, clear = assert(loadstring(callbacks, "@group_spell_selection_callbacks"))(
    "MidnightSimpleUnitFrames", namespace)

for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
    scope, playerSpec = kind, "HolyPaladin"
    assert(GP.CurrentSpellAura(scope) == "BeaconOfLight", kind .. ": initial selection")
    click({ refreshPage = M.Refresh }, { _auraName = "BlessingOfProtection" }, "LeftButton")
    assert(GP.CurrentSpellAura(scope) == "BlessingOfProtection", kind .. ": tile selection lost on refresh")
    local selected, spec, name = GP.CurrentSpellConfig(scope, true)
    assert(spec == playerSpec and name == "BlessingOfProtection" and selected,
        kind .. ": editor targets the wrong spell after clicking a tile")

    dropdown("BeaconOfLight")
    assert(GP.CurrentSpellAura(scope) == "BeaconOfLight", kind .. ": dropdown cannot select first spell")
    dropdown("BlessingOfProtection")
    assert(GP.CurrentSpellAura(scope) == "BlessingOfProtection", kind .. ": dropdown selection lost on refresh")

    playerSpec = "DisciplinePriest"
    assert(GP.CurrentSpellAura(scope) == "PowerWordShield", kind .. ": selection leaked across specs")
    dropdown("PainSuppression")
    assert(GP.CurrentSpellAura(scope) == "PainSuppression", kind .. ": second spec selection failed")
    playerSpec = "HolyPaladin"
    assert(GP.CurrentSpellAura(scope) == "BlessingOfProtection", kind .. ": first spec selection not retained")

    clear(scope, "DisciplinePriest")
    assert(GP.CurrentSpellAura(scope) == "BlessingOfProtection", kind .. ": clearing another spec changed this spec")
    playerSpec = "DisciplinePriest"
    assert(GP.CurrentSpellAura(scope) == "PowerWordShield", kind .. ": explicit spec selection was not cleared")
    playerSpec = "HolyPaladin"
    clear(scope)
    assert(GP.CurrentSpellAura(scope) == "BeaconOfLight", kind .. ": current spec selection was not cleared")
    dropdown("BlessingOfProtection")
end

scope, playerSpec = "party", "HolyPaladin"
clear(scope)
for _, kind in ipairs({ "raid", "mythicraid" }) do
    assert(GP.CurrentSpellAura(kind) == "BlessingOfProtection", "clearing party changed " .. kind)
end
print("PASS group spell selection: real tile/dropdown callbacks, editor target, scope/spec isolation and clearing")
