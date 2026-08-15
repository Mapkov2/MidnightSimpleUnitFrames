local root = assert(arg[1], "repo root missing")

local registeredName, element, registeredTraits
local refreshedUnit, refreshedElements
local happiness = 3
local hunterPet = true

GetPetHappiness = function() return happiness, happiness == 1 and 75 or happiness == 2 and 100 or 125, 0 end
HasPetUI = function() return true, hunterPet end

local function Texture(parent)
    local tex = { parent = parent, shown = false }
    function tex:GetParent() return self.parent end
    function tex:SetParent(value) self.parent = value end
    function tex:SetTexture(value) self.texture = value end
    function tex:SetTexCoord(l, r, t, b) self.coords = { l, r, t, b } end
    function tex:SetSize(w, h) self.width, self.height = w, h end
    function tex:ClearAllPoints() self.cleared = true end
    function tex:SetPoint(...) self.point = { ... } end
    function tex:SetAlpha(value) self.alpha = value end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    return tex
end

CreateFrame = function(_, _, parent)
    local holder = { parent = parent }
    function holder:SetAllPoints(value) self.allPoints = value end
    function holder:EnableMouse(value) self.mouse = value end
    function holder:SetClipsChildren(value) self.clips = value end
    function holder:SetFrameLevel(value) self.level = value end
    function holder:CreateTexture() self.texture = Texture(self); return self.texture end
    return holder
end

local namespace = {
    UF = {
        Layers = { StatusLevel = function(_, layer) return 40 + layer end },
        RegisterElement = function(name, value, traits)
            registeredName, element, registeredTraits = name, value, traits
        end,
        RefreshElements = function(unit, elements)
            refreshedUnit, refreshedElements = unit, elements
            return true
        end,
    },
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UF_PetHappiness.lua"))(
    "MidnightSimpleUnitFrames", namespace)
assert(registeredName == "PetHappinessIndicator" and type(element) == "table", "Happiness element was not registered")
assert(element.UpdateOnApply == true, "Happiness must seed on apply")
assert(registeredTraits and registeredTraits.apply == true and registeredTraits.events == true
    and registeredTraits.defaultApply == true and registeredTraits.forceUpdate == true,
    "Happiness element is missing UF core apply/event traits")

local status = {
    enabled = true,
    alpha = 0.8,
    testMode = false,
    petHappiness = { enabled = true, size = 24, anchor = "RIGHT", x = -7, y = -4, layer = 7 },
}
local frame = {
    MSUFUnitKey = "pet",
    MSUFSpec = { status = status },
    Health = { GetFrameLevel = function() return 10 end },
}

assert(element.IsEnabled(frame, frame.MSUFSpec) == true, "Pet Happiness should be enabled on the Pet frame")
element.Create(frame, frame.MSUFSpec)
element.Apply(frame, frame.MSUFSpec)
assert(frame.petHappinessIndicatorIcon, "Happiness texture was not created")
assert(frame.petHappinessIndicatorIcon.texture == "Interface\\PetPaperDollFrame\\UI-PetHappiness", "wrong Happiness texture")
assert(frame.petHappinessIndicatorIcon.width == 24 and frame.petHappinessIndicatorIcon.height == 24, "wrong default size")
assert(frame.petHappinessIndicatorIcon.point[1] == "RIGHT" and frame.petHappinessIndicatorIcon.point[4] == -7 and frame.petHappinessIndicatorIcon.point[5] == -4, "wrong default right-side placement")
assert(frame.petHappinessIndicatorIcon.alpha == 0.8, "status alpha was not applied")

local expected = {
    [1] = { 0.375, 0.5625, 0, 0.359375 },
    [2] = { 0.1875, 0.375, 0, 0.359375 },
    [3] = { 0, 0.1875, 0, 0.359375 },
}
for state = 1, 3 do
    happiness = state
    element.Update(frame)
    assert(frame.petHappinessIndicatorIcon.shown == true, "Happiness state " .. state .. " did not show")
    for i = 1, 4 do
        assert(frame.petHappinessIndicatorIcon.coords[i] == expected[state][i], "wrong texcoord for Happiness state " .. state)
    end
end

happiness = nil
element.Update(frame)
assert(frame.petHappinessIndicatorIcon.shown == false, "nil Happiness should hide")
happiness, hunterPet = 3, false
element.Update(frame)
assert(frame.petHappinessIndicatorIcon.shown == false, "non-Hunter pets should hide")
hunterPet, status.testMode = true, true
element.Update(frame)
assert(frame.petHappinessIndicatorIcon.shown == true and frame.petHappinessIndicatorIcon.coords[1] == 0, "test mode should preview Happy")

status.testMode = false
local events = element.GetEvents(frame, frame.MSUFSpec)
assert(#events == 1 and events[1] == "UNIT_PET", "wrong unit-filtered Happiness event route")
local lifecycle = element.GetUnitlessEvents(frame, frame.MSUFSpec)
assert(#lifecycle == 3 and lifecycle[1] == "UNIT_HAPPINESS" and lifecycle[2] == "PET_UI_UPDATE"
    and lifecycle[3] == "PLAYER_ENTERING_WORLD", "wrong unitless Happiness lifecycle route")

assert(MSUF_RequestPetHappinessIndicatorRefresh("pet") == true, "Happiness refresh bridge failed")
assert(refreshedUnit == "pet" and refreshedElements[1] == "PetHappinessIndicator", "Happiness refresh target drifted")

local function LoadAssistant(client)
    local ns = { Client = client, MSUF2 = {}, Assistant = { UnitframeRegistryData = {} } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Unitframes_StatusData_Classic.lua"))(
        "MidnightSimpleUnitFrames_Assistant", ns)
    for _, spec in ipairs(ns.Assistant.UnitframeRegistryData.STATUS_CONTROL_SPECS or {}) do
        if spec.value == "statusPetHappiness" then return spec end
    end
end

local vanillaSpec = LoadAssistant({ IsVanilla = true })
assert(vanillaSpec and vanillaSpec.units.pet == true, "Vanilla Assistant Happiness setting missing")
assert(vanillaSpec.size == "petHappinessIndicatorSize" and vanillaSpec.refresh == "MSUF_RequestPetHappinessIndicatorRefresh", "Assistant Happiness contract drifted")
assert(LoadAssistant({ IsMists = true }) == nil, "Mists must not expose a Happiness Assistant setting")

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local vanillaManifest = Read("MidnightSimpleUnitFrames/Game/Vanilla/UnitFrames.xml")
local tbcManifest = Read("MidnightSimpleUnitFrames/Game/TBC/UnitFrames.xml")
local mistsManifest = Read("MidnightSimpleUnitFrames/Game/Mists/UnitFrames.xml")
assert(vanillaManifest:find("MSUF_UF_PetHappiness.lua", 1, true), "Vanilla must load Happiness runtime")
assert(tbcManifest:find("MSUF_UF_PetHappiness.lua", 1, true), "TBC must load Happiness runtime")
assert(not mistsManifest:find("MSUF_UF_PetHappiness.lua", 1, true), "Mists must not load Happiness runtime")

local function WithOptionsFlavor(flavor, callback)
    local oldCAddOns, oldMetadata = _G.C_AddOns, _G.GetAddOnMetadata
    _G.C_AddOns = { GetAddOnMetadata = function(addon, field)
        assert(addon == "MidnightSimpleUnitFrames_Options" and field == "X-MSUF-Client",
            "Options gate queried the wrong addon metadata")
        return flavor
    end }
    _G.GetAddOnMetadata = nil
    local ok, result = pcall(callback)
    _G.C_AddOns, _G.GetAddOnMetadata = oldCAddOns, oldMetadata
    if not ok then error(result, 0) end
    return result
end

local function PipeRows(rows)
    local out = {}
    for line in rows:gmatch("[^\r\n]+") do
        local columns = {}
        for value in (line .. "|"):gmatch("(.-)|") do columns[#columns + 1] = value end
        out[#out + 1] = columns
    end
    return out
end

local function PreviewHappinessAllowed(flavor, unit, client)
    return WithOptionsFlavor(flavor, function()
        local main = { Client = client, MSUF2 = { PipeRows = PipeRows } }
        assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs_Classic.lua"))(
            "MidnightSimpleUnitFrames_Options", main)
        for _, spec in ipairs(main.UFPreviewSpecs.StatusPreview or {}) do
            if spec.id == "statusPetHappiness" then return spec.allowed and spec.allowed(unit) or false end
        end
        error("Pet Happiness preview spec missing")
    end)
end
assert(PreviewHappinessAllowed("Vanilla", "pet") == true,
    "Vanilla Pet preview must expose Pet Happiness without MSUF.Client")
assert(PreviewHappinessAllowed("TBC", "pet") == true,
    "TBC Pet preview must expose Pet Happiness without MSUF.Client")
assert(PreviewHappinessAllowed("  tbc  ", "pet") == true,
    "TBC Pet preview must normalize Options TOC metadata")
assert(PreviewHappinessAllowed("Vanilla", "player") == false,
    "Pet Happiness preview leaked onto Player")
assert(PreviewHappinessAllowed("Mists", "pet", { IsVanilla = true }) == false,
    "Mists Pet preview must override a stale Vanilla client flag")

local options = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit_Classic.lua")
local previewSpecs = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs_Classic.lua")
local previewStatus = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status_Classic.lua")
local searchKeywords = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords_Classic.lua")
assert(options:find('StatusControl("statusPetHappiness"', 1, true), "Pet page Happiness selector missing")
assert(options:find('unit == "pet" and PetHappinessSupported()', 1, true), "Happiness selector is not Pet-only/capability-gated")
assert(options:find('getMetadata(addonName, "X-MSUF-Client")', 1, true),
    "Pet page does not use the Options TOC capability")
assert(options:find("statusPetHappiness", 1, true) and options:find("COPY_STATUSICON_FIELDS", 1, true), "Happiness copy ownership missing")
assert(previewSpecs:find("statusPetHappiness|showPetHappinessIndicator", 1, true), "Happiness preview spec missing")
assert(previewStatus:find('spec.id == "statusPetHappiness"', 1, true), "Happiness preview texture path missing")
assert(searchKeywords:find("PET_HAPPINESS", 1, true), "Pet Happiness search capability gate missing")
assert(searchKeywords:find("haustier zufriedenheit", 1, true), "German Pet Happiness search aliases missing")

local function LoadPetSearchKeywords(client)
    local ns = { Client = client, MSUF2 = {} }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords_Classic.lua"))(
        "MidnightSimpleUnitFrames_Options", ns)
    return ns.MSUF2.SearchData.KEYWORDS.uf_pet
end
assert(LoadPetSearchKeywords({ IsVanilla = true }):find("pet happiness", 1, true),
    "Vanilla search must expose Pet Happiness")
assert(not LoadPetSearchKeywords({ IsMists = true }):find("pet happiness", 1, true),
    "Mists search must not expose Pet Happiness")

local function LoadPetSearchFromOptionsFlavor(flavor)
    return WithOptionsFlavor(flavor, function()
        local main = { MSUF2 = {} }
        assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords_Classic.lua"))(
            "MidnightSimpleUnitFrames_Options", main)
        return main.MSUF2.SearchData.KEYWORDS.uf_pet
    end)
end
assert(LoadPetSearchFromOptionsFlavor("Vanilla"):find("pet happiness", 1, true),
    "Vanilla Options TOC gate must expose Pet Happiness search")
assert(LoadPetSearchFromOptionsFlavor("TBC"):find("pet happiness", 1, true),
    "TBC Options TOC gate must expose Pet Happiness search")
assert(LoadPetSearchFromOptionsFlavor("  tbc  "):find("pet happiness", 1, true),
    "TBC Options TOC search gate must normalize metadata")
assert(not LoadPetSearchFromOptionsFlavor("Mists"):find("pet happiness", 1, true),
    "Mists Options TOC gate must hide Pet Happiness search")

local runtimeSource = Read("MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UF_PetHappiness.lua")
assert(not runtimeSource:find("OnUpdate", 1, true), "Happiness runtime must not poll")
assert(not runtimeSource:find("NewTicker", 1, true), "Happiness runtime must not use a ticker")

print("Classic Pet Happiness runtime, support matrix, preview, copy, and Assistant smoke passed")
