-- Vanilla, TBC and Mists load Pages/MSUF_Menu2_Unit_Classic.lua and
-- Preview/MSUF_Menu2_UnitPreview_View_Classic.lua in place of the Retail-named
-- files. Both are owned copies that no sync rewrites, so this smoke drives them
-- against the runtime and the shared menu files those flavors load.
local root = assert(arg[1], "repo root missing")

local MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"), "missing file: " .. relativePath)
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

-- The real Support helpers parse the page's KLR/WL literals, as they do in game.
local function LoadUnitPage(client)
    local namespace = {
        Client = client,
        ExportPublic = function() end,
        Translate = function(text) return text end,
        MSUF2 = { Widgets = {} },
    }
    assert(loadfile(root .. "/" .. MENU .. "MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", namespace)
    assert(loadfile(root .. "/" .. MENU .. "Pages/MSUF_Menu2_Unit_Classic.lua"))("MidnightSimpleUnitFrames_Options", namespace)
    return namespace.MSUF2, assert(namespace.MSUF2.UnitPage, "Classic Unit page did not publish M.UnitPage")
end

local function WordSet(words)
    local set = {}
    for word in tostring(words or ""):gmatch("%S+") do set[word] = true end
    return set
end

-- 1. Load conditions: one control per rule the Classic runtime compiles.
local menu, unitPage = LoadUnitPage({ SupportsPetHappiness = true })
local EXPECTED_LOAD_CONDITIONS = {
    { "loadCondHideInHousing", "Housing" },
    { "loadCondHideInCombat", "In combat" },
    { "loadCondHideInGroup", "In group" },
    { "loadCondHideInInstance", "In instance" },
    { "loadCondHideInVehicle", "In vehicle" },
    { "loadCondHideMounted", "Mounted" },
    { "loadCondHideNoTarget", "No target" },
    { "loadCondHideOutOfCombat", "Out of combat" },
    { "loadCondHideOutOfCombatNoTarget", "Out of combat and no target" },
    { "loadCondHideResting", "Resting" },
    { "loadCondHideSolo", "Solo" },
    { "loadCondHideStealthed", "Stealthed" },
}
local loadRows = assert(unitPage.LOAD_CONDITIONS, "Classic Unit page does not publish LOAD_CONDITIONS")
assert(#loadRows == #EXPECTED_LOAD_CONDITIONS,
    "Classic Load Conditions builds " .. #loadRows .. " controls, expected " .. #EXPECTED_LOAD_CONDITIONS)
local menuLoadKeys = {}
for index, expected in ipairs(EXPECTED_LOAD_CONDITIONS) do
    local row = loadRows[index]
    assert(row.key == expected[1] and row.label == expected[2],
        "Classic Load Conditions row " .. index .. " is " .. tostring(row.key) .. "=" .. tostring(row.label)
            .. ", expected " .. expected[1] .. "=" .. expected[2])
    menuLoadKeys[row.key] = true
end

local classicConfig = Read("MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UF_Config.lua")
local runtimeBlock = assert(classicConfig:match("\nlocal LOAD_CONDITION_KEYS = {\n(.-)\n}\n"),
    "Classic MSUF_UF_Config.lua lost its LOAD_CONDITION_KEYS table")
-- A compiled rule only works when the element the Classic manifest loads reads it.
assert(Read("MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UFCore_Elements.xml")
    :find("Engine\\Elements\\MSUF_UF_Elements_LoadConditions.lua", 1, true),
    "Classic element manifest no longer loads MSUF_UF_Elements_LoadConditions.lua")
local loadElement = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
local runtimeLoadKeys, runtimeLoadCount = {}, 0
for field, suffix in runtimeBlock:gmatch('{ "([%w_]+)", "([%w_]+)" }') do
    assert(loadElement:find("load." .. field .. " == true", 1, true),
        "Classic runtime compiles load." .. field .. ", but the load-condition element never reads it")
    runtimeLoadKeys["loadCond" .. suffix] = true
    runtimeLoadCount = runtimeLoadCount + 1
end
assert(runtimeLoadCount > 0 and classicConfig:find('conf["loadCond" .. def[2]]', 1, true),
    "Classic MSUF_UF_Config.lua no longer compiles load conditions from LOAD_CONDITION_KEYS")
for key in pairs(runtimeLoadKeys) do
    assert(menuLoadKeys[key], "Classic runtime compiles " .. key .. ", but the Classic Unit page builds no control for it")
end
for key in pairs(menuLoadKeys) do
    assert(runtimeLoadKeys[key], "Classic Unit page builds a control for " .. key .. ", which the Classic runtime never compiles")
end

-- Copy To and "Reset section" both read SectionFields.
local sectionFields = assert(unitPage.SectionFields, "Classic Unit page does not publish SectionFields")
local loadFields = WordSet(sectionFields.load_conditions)
for key in pairs(menuLoadKeys) do
    assert(loadFields[key], "Classic Load Conditions copy and reset skip " .. key)
end
assert(loadFields.loadCondShowWhenInjured and loadFields.loadCondActive,
    "Classic Load Conditions copy and reset skip loadCondShowWhenInjured or loadCondActive")

-- 2. Copy To: every key below has a control on a page the Classic manifests
-- load and is compiled by the Classic MSUF_UF_Config.lua.
local MOUSEOVER_KEYS = {
    "nameTextMouseover", "hpTextMouseover", "powerTextMouseover",
    "nameTextMouseoverFadeIn", "nameTextMouseoverFadeOut",
    "hpTextMouseoverFadeIn", "hpTextMouseoverFadeOut",
    "powerTextMouseoverFadeIn", "powerTextMouseoverFadeOut",
}
local COPY_CONTRACT = {
    basics = { "chunkedFill" },
    text = MOUSEOVER_KEYS,
    portrait = { "portraitClickable" },
    load = { "loadCondHideNoTarget", "loadCondHideOutOfCombatNoTarget" },
    transparency = { "alphaExcludePredictionBars" },
}
for _, keys in pairs(COPY_CONTRACT) do
    for _, key in ipairs(keys) do
        assert(runtimeLoadKeys[key] or classicConfig:find("conf%." .. key .. "[^%w_]"),
            "Classic MSUF_UF_Config.lua does not compile " .. key .. "; drop it from the Classic Copy To contract")
    end
end
local SECTION_FOR_SCOPE = { text = "text", portrait = "portrait", load = "load_conditions", transparency = "transparency" }
for scope, section in pairs(SECTION_FOR_SCOPE) do
    local published = WordSet(sectionFields[section])
    for _, key in ipairs(COPY_CONTRACT[scope]) do
        assert(published[key], "Classic SectionFields." .. section .. " skips " .. key .. ", so Reset section leaves it behind")
    end
end

local applyRequests = 0
menu.RequestUnitApply = function() applyRequests = applyRequests + 1 end
for scope in pairs(COPY_CONTRACT) do
    local source, destination = {}, {}
    for _, keys in pairs(COPY_CONTRACT) do
        for _, key in ipairs(keys) do source[key] = key:find("Fade", 1, true) and 0.35 or true end
    end
    local db = { general = {}, player = source, target = destination }
    menu.EnsureDB = function() return db end
    local applied, result = unitPage.CopyUnitSettings("player", "target", { [scope] = true })
    assert(applied == true and type(result) == "table" and result.applied == true,
        "Classic Copy To refused a " .. scope .. " copy from Player to Target")
    for otherScope, keys in pairs(COPY_CONTRACT) do
        for _, key in ipairs(keys) do
            if otherScope == scope then
                assert(destination[key] == source[key], "Classic Copy To (" .. scope .. ") does not copy " .. key)
            else
                assert(destination[key] == nil, "Classic Copy To (" .. scope .. ") leaked " .. key .. " from " .. otherScope)
            end
        end
    end
end
assert(applyRequests == 5, "Classic Copy To must request one unit apply per copy")

-- 3. Pet Happiness follows MSUF.Client.SupportsPetHappiness and nothing else.
local clientTagReads = 0
local function ReadMetadata(_, field)
    if field == "X-MSUF-Client" then clientTagReads = clientTagReads + 1 end
    return "Vanilla"
end
local function PetHappinessControl(client)
    local oldCAddOns, oldMetadata = _G.C_AddOns, _G.GetAddOnMetadata
    _G.C_AddOns, _G.GetAddOnMetadata = { GetAddOnMetadata = ReadMetadata }, ReadMetadata
    local _, page = LoadUnitPage(client)
    local found
    for _, spec in ipairs(page.STATUS_CONTROLS) do
        if spec.value == "statusPetHappiness" then found = spec end
    end
    assert(found and type(found.allowed) == "function", "Classic Unit page lost the Pet Happiness status control")
    local onPet, onPlayer = found.allowed("pet"), found.allowed("player")
    _G.C_AddOns, _G.GetAddOnMetadata = oldCAddOns, oldMetadata
    return found, onPet, onPlayer
end
local happiness, onPet, onPlayer = PetHappinessControl({ SupportsPetHappiness = true })
assert(onPet == true and onPlayer == false, "Pet Happiness must be offered on the Pet page only")
assert(happiness.text == "Pet Happiness", "Pet Happiness control label drifted from the Retail-named page")
assert(happiness.show == "showPetHappinessIndicator" and happiness.refresh == "MSUF_RequestPetHappinessIndicatorRefresh",
    "Pet Happiness control lost its setting or refresh bridge")
local _, staleFlavor = PetHappinessControl({ SupportsPetHappiness = false, IsVanilla = true, IsTBC = true })
assert(staleFlavor == false, "Pet Happiness re-derives the flavor instead of reading MSUF.Client.SupportsPetHappiness")
local _, flagsOnly = PetHappinessControl({ IsVanilla = true, IsTBC = true })
assert(flagsOnly == false, "Pet Happiness must stay off until Game/Shared/Initialize.lua grants the capability")
local _, noClient = PetHappinessControl(nil)
assert(noClient == false, "Pet Happiness must stay off without MSUF.Client")
assert(clientTagReads == 0, "Classic Unit page still parses the X-MSUF-Client TOC tag")

-- 4. Compact preview: the layer rail is a popover under the "Layers" button and
-- keeps its chips inside the panel when the render pass re-flows it.
local chrome = Read(MENU .. "Preview/MSUF_Menu2_UnitPreview_View_Chrome.lua")
assert(chrome:find("box._msuf2LayerPopoverWidth = popoverWidth", 1, true),
    "Unit preview chrome no longer publishes the popover width the Classic view reads")

local helperSource = Read(MENU .. "MSUF_Menu2_PreviewHelpers.lua")
local function HelperBody(name)
    local start = assert(helperSource:find("\nfunction H." .. name .. "(", 1, true), "PreviewHelpers lost H." .. name)
    local _, finish = assert(helperSource:find("\nend\n", start, true))
    return helperSource:sub(start, finish)
end
local helpers = assert(loadstring("local H = {}\nlocal min = math.min\n" .. HelperBody("FlowLayerChips")
    .. HelperBody("FlowLayerPopover") .. "\nreturn H", "@preview_layer_flow"))()

local view = Read(MENU .. "Preview/MSUF_Menu2_UnitPreview_View_Classic.lua")
local railStart = assert(view:find("\n    box.LayoutLayerRail = function(self, railWidth)\n", 1, true),
    "Classic unit preview lost box.LayoutLayerRail")
local _, railFinish = assert(view:find("\n    end\n", railStart, true))
local LayoutLayerRail = assert(loadstring("local PreviewHelpers = ...\nlocal box = {}" .. view:sub(railStart, railFinish)
    .. "return box.LayoutLayerRail", "@classic_layout_layer_rail"))(helpers)

local function Rail(width)
    local rail = { width = width }
    function rail:GetWidth() return self.width end
    function rail:SetWidth(value) self.width = value end
    function rail:SetHeight(value) self.height = value end
    return rail
end
local function Chips(count, width)
    local chips = {}
    for index = 1, count do
        local chip = {}
        function chip:GetWidth() return width end
        function chip:IsShown() return true end
        function chip:ClearAllPoints() self.x, self.y = nil, nil end
        function chip:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
        chips[index] = chip
    end
    return chips
end
local function PreviewBox(boxWidth, boxHeight, popoverWidth)
    return {
        sidebar = Rail(popoverWidth or (boxWidth - 24)),
        layerButtons = Chips(14, 70),
        _msuf2LayerPopoverWidth = popoverWidth,
        GetWidth = function() return boxWidth end,
        GetHeight = function() return boxHeight end,
    }
end
local function AssertChipsInsideRail(box, label)
    local rows = {}
    for index, chip in ipairs(box.layerButtons) do
        assert(chip.x and chip.x >= 0 and chip.x + chip:GetWidth() <= box.sidebar.width,
            label .. ": layer chip " .. index .. " ends at " .. tostring(chip.x and chip.x + chip:GetWidth())
                .. " px, outside the " .. tostring(box.sidebar.width) .. " px rail")
        rows[chip.y] = true
    end
    local count = 0
    for _ in pairs(rows) do count = count + 1 end
    return count
end

-- The render pass re-flows with the box width, not the popover width.
local compact = PreviewBox(900, 400, 268)
local compactHeight = LayoutLayerRail(compact, 900 - 24)
assert(compact.sidebar.width <= 268, "Compact layer popover grew past its authored 268 px column without need")
assert(AssertChipsInsideRail(compact, "compact preview") == 5 and compactHeight == compact.sidebar.height,
    "Compact layer popover must wrap 14 chips into 5 rows of the 268 px column")

-- A short preview widens the popover, but never past the box or its bottom edge.
local short = PreviewBox(900, 100, 268)
local shortHeight = LayoutLayerRail(short, 900 - 24)
assert(shortHeight <= 100 - 44, "Compact layer popover hangs below a 100 px preview box: " .. tostring(shortHeight) .. " px")
assert(short.sidebar.width > 268 and short.sidebar.width <= 900 - 24,
    "Compact layer popover must widen inside the preview box, got " .. tostring(short.sidebar.width) .. " px")
AssertChipsInsideRail(short, "short compact preview")

-- Docked and floating previews keep the full-width strip.
local docked = PreviewBox(900, 400, nil)
LayoutLayerRail(docked, 900 - 24)
assert(docked.sidebar.width == 900 - 24, "Docked layer rail must keep the width its anchors give it")
assert(AssertChipsInsideRail(docked, "docked preview") == 2, "Docked layer rail must flow 14 chips across the full strip")

print("Classic unit menu runtime parity smoke passed")
