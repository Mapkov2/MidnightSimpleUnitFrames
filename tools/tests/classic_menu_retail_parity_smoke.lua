local root = assert(arg[1], "repo root missing")

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local auras = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Classic.lua")
for _, contract in ipairs({
    "labelHitWhenDisabled",
    "CUSTOM_DISPLAY_MODES",
    "reminderEnabled",
    "CLASSIC_AURA_FILTERS_REDUCED",
}) do
    assert(auras:find(contract, 1, true),
        "Classic Aura menu lost the current Retail contract: " .. contract)
end
assert(not auras:find("A3.PreviewDispelTypeForIndex", 1, true),
    "Classic Aura menu calls the Retail-only native dispel preview helper")

local unit = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit_Classic.lua")
for _, contract in ipairs({ "statusAFKTimer", "statusPetHappiness", "showStanceIndicator" }) do
    assert(unit:find(contract, 1, true),
        "Classic Unit menu lost a Retail/Classic status contract: " .. contract)
end

local status = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection_Classic.lua")
assert(status:find("identityRestrictionWarning", 1, true),
    "Classic status menu lost the current Retail identity warning")
assert(status:find("textColor", 1, true),
    "Classic status menu lost its Classic text-color control")

local specs = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs_Classic.lua")
assert(specs:find("statusPetHappiness", 1, true) and specs:find("stance|showStanceIndicator", 1, true),
    "Classic preview specs do not combine Pet Happiness with the current Retail stance preview")

local search = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua")
assert(search:find("exactTargetContracts, haystack", 1, true),
    "Classic search index is still on the legacy pre-Retail column format")
for _, contract in ipairs({
    "Custom Container > Reminder",
    "statusPetHappiness",
    "statusAFKTimer",
    "stance=player.showStanceIndicator",
}) do
    assert(search:find(contract, 1, true),
        "Classic search index is missing a current menu contract: " .. contract)
end

print("Classic Menu2 Retail parity smoke passed")
