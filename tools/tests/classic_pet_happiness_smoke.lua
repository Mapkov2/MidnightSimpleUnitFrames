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

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua"))(
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

-- The unit preview specs and the search keywords are the Retail-named files on
-- every client and follow MSUF.Client.SupportsPetHappiness. Each case therefore
-- builds the real client model from a project ID and an X-MSUF-Client tag.
local CLASSIC_PROJECT_IDS = { Vanilla = 2, TBC = 5, Mists = 19 }
local function LoadClient(flavor, tag, projectID)
    local oldCAddOns, oldMetadata, oldCreateFrame = _G.C_AddOns, _G.GetAddOnMetadata, _G.CreateFrame
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
    _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
    _G.WOW_PROJECT_ID = projectID or CLASSIC_PROJECT_IDS[flavor]
    _G.C_AddOns = { GetAddOnMetadata = function(_, field)
        return field == "X-MSUF-Client" and (tag or flavor) or nil
    end }
    -- No frame factory: a client placed by its tag alone builds a login diagnostic.
    _G.GetAddOnMetadata, _G.CreateFrame, _G.GameEvent, _G.MSUF, _G.MSUF_NS = nil, nil, nil, nil, nil
    local clientNamespace = {}
    local ok, err = pcall(assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua")),
        "MidnightSimpleUnitFrames", clientNamespace)
    _G.C_AddOns, _G.GetAddOnMetadata, _G.CreateFrame = oldCAddOns, oldMetadata, oldCreateFrame
    _G.MSUF, _G.MSUF_NS = nil, nil
    if not ok then error(err, 0) end
    return clientNamespace.Client
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

local function HappinessPreviewSpec(client)
    local main = { Client = client, MSUF2 = { PipeRows = PipeRows } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua"))(
        "MidnightSimpleUnitFrames_Options", main)
    local rows = main.UFPreviewSpecs.StatusPreview
    for index, spec in ipairs(rows) do
        if spec.id == "statusPetHappiness" then return spec, index, #rows, rows[#rows].id end
    end
    return nil, nil, #rows, rows[#rows].id
end
-- The third case is placed by its tag alone, so the tag is what gets normalized.
for _, case in ipairs({ { "Vanilla" }, { "TBC" }, { "TBC", "  tbc  ", 99 } }) do
    local label = case[1] .. (case[2] and " (tag only)" or "")
    local client = LoadClient(case[1], case[2], case[3])
    assert(client.SupportsPetHappiness == true, label .. " client model must support Pet Happiness")
    local spec, index, count, lastID = HappinessPreviewSpec(client)
    assert(spec and spec.allowed("pet") == true, label .. " Pet preview must expose Pet Happiness")
    assert(spec.allowed("player") == false, label .. " Pet Happiness preview leaked onto Player")
    assert(index == count - 1 and lastID == "stance", label .. " Pet Happiness must sit before the stance row")
    assert(spec.show == "showPetHappinessIndicator" and spec.size == "petHappinessIndicatorSize"
        and spec.defaultSize == 24 and spec.defaultAnchor == "RIGHT" and spec.defaultX == -7 and spec.defaultY == -4
        and spec.defaultLayer == 7 and spec.refresh == "MSUF_RequestPetHappinessIndicatorRefresh",
        label .. " Pet Happiness preview spec drifted from the runtime defaults")
end
do
    local client = LoadClient("Mists")
    assert(client.SupportsPetHappiness == false, "Mists client model must not support Pet Happiness")
    local spec, _, _, lastID = HappinessPreviewSpec(client)
    assert(spec == nil and lastID == "stance", "Mists Pet preview must not carry a Pet Happiness row")
end

-- The Classic manifests must load the files the cases above exercise.
local previewManifest = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Classic.xml")
local searchManifest = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Classic.xml")
assert(previewManifest:find('<Script file="MSUF_Menu2_UnitPreview_Specs.lua"/>', 1, true),
    "Classic unit preview manifest must load the shared preview specs")
assert(searchManifest:find('<Script file="MSUF_Menu2_Search_Keywords.lua"/>', 1, true),
    "Classic search manifest must load the shared search keywords")

local options = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit_Classic.lua")
local previewSpecs = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua")
local previewStatus = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status_Classic.lua")
local searchKeywords = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords.lua")
assert(options:find('StatusControl("statusPetHappiness"', 1, true), "Pet page Happiness selector missing")
assert(options:find('unit == "pet" and PetHappinessSupported()', 1, true), "Happiness selector is not Pet-only/capability-gated")
assert(options:find("client.SupportsPetHappiness == true", 1, true)
    and not options:find("GetAddOnMetadata", 1, true) and not options:find("X-MSUF-Client", 1, true),
    "Pet page must read MSUF.Client.SupportsPetHappiness instead of re-deriving the flavor from TOC metadata")
assert(options:find("statusPetHappiness", 1, true) and options:find("COPY_STATUSICON_FIELDS", 1, true), "Happiness copy ownership missing")
assert(previewSpecs:find("statusPetHappiness|showPetHappinessIndicator", 1, true), "Happiness preview spec missing")
assert(previewStatus:find('spec.id == "statusPetHappiness"', 1, true), "Happiness preview texture path missing")
assert(searchKeywords:find("PET_HAPPINESS", 1, true), "Pet Happiness search capability gate missing")
assert(searchKeywords:find("haustier zufriedenheit", 1, true), "German Pet Happiness search aliases missing")

local function LoadSearchKeywords(client)
    local ns = { Client = client, MSUF2 = {} }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords.lua"))(
        "MidnightSimpleUnitFrames_Options", ns)
    return ns.MSUF2.SearchData.KEYWORDS
end
local mistsKeywords = LoadSearchKeywords(LoadClient("Mists"))
assert(not mistsKeywords.uf_pet:find("happiness", 1, true), "Mists search must not expose Pet Happiness")
for _, case in ipairs({ { "Vanilla" }, { "TBC" }, { "TBC", "  tbc  ", 99 } }) do
    local label = case[1] .. (case[2] and " (tag only)" or "")
    local keywords = LoadSearchKeywords(LoadClient(case[1], case[2], case[3]))
    assert(keywords.uf_pet:find(" pet happiness ", 1, true), label .. " search must expose Pet Happiness")
    assert(keywords.uf_pet:sub(1, #mistsKeywords.uf_pet) == mistsKeywords.uf_pet,
        label .. " Pet Happiness must only append to the pet page keywords")
    -- Every other page answers the same words on every Classic client; the WoW
    -- Forever surname words on the Fonts page never reach one.
    for key, text in pairs(mistsKeywords) do
        if key ~= "uf_pet" then assert(keywords[key] == text, label .. " search keywords changed for " .. key) end
    end
    assert(not keywords.opt_fonts:find("surname", 1, true), label .. " Fonts page gained the WoW Forever name keywords")
end

local runtimeSource = Read("MidnightSimpleUnitFrames/Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua")
assert(not runtimeSource:find("OnUpdate", 1, true), "Happiness runtime must not poll")
assert(not runtimeSource:find("NewTicker", 1, true), "Happiness runtime must not use a ticker")

print("Classic Pet Happiness runtime, support matrix, preview, copy, and Assistant smoke passed")
