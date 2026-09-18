-- WoW Forever pet happiness smoke.
--
--   lua tools/tests/forever_pet_happiness_smoke.lua <repo root>
--
-- Forever brought hunter pet happiness back on the Mainline engine: Blizzard's
-- Forever pet frame shows it through C_PetInfo.GetPetHappiness and
-- UNIT_HAPPINESS. Midnight has none. The indicator is one shared module
-- (Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua) that Classic Era and TBC
-- drive through the global GetPetHappiness and Forever through the namespaced
-- function. On the Mainline build the client fact SupportsPetHappiness decides
-- everything: the runtime element, the seeded defaults and the compiled status
-- entry exist on Forever and stay absent or disabled on Midnight.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local core = root .. "/MidnightSimpleUnitFrames/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

---------------------------------------------------------------------------
-- Client fact
---------------------------------------------------------------------------
local function LoadClient(isForever, namespace)
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_ID = 1, 1
    _G.C_AddOns = { GetAddOnMetadata = function() return nil end }
    _G.GetBuildInfo = function() return "test", "test", "test", isForever and 16001 or 120105 end
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.GameEvent = isForever and { RegisterCamelotEvents = function() end } or nil
    _G.MSUF, _G.MSUF_NS = nil, nil
    namespace = namespace or {}
    assert(loadfile(core .. "Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", namespace)
    return namespace.Client, namespace
end

Check(LoadClient(true).SupportsPetHappiness == true, "Forever must support pet happiness")
Check(LoadClient(false).SupportsPetHappiness == false, "Midnight must not support pet happiness")

---------------------------------------------------------------------------
-- Runtime element: namespaced API on Forever, global on Classic, inert on Midnight
---------------------------------------------------------------------------
local function Texture(parent)
    local tex = { parent = parent, shown = false, writes = 0 }
    function tex:GetParent() return self.parent end
    function tex:SetParent(value) self.parent = value end
    function tex:SetTexture(value) self.texture = value; self.writes = self.writes + 1 end
    function tex:SetTexCoord(l, r, t, b) self.coords = { l, r, t, b }; self.writes = self.writes + 1 end
    function tex:SetSize(w, h) self.width, self.height = w, h end
    function tex:ClearAllPoints() end
    function tex:SetPoint(...) self.point = { ... } end
    function tex:SetAlpha(value) self.alpha = value end
    function tex:Show() self.shown = true; self.writes = self.writes + 1 end
    function tex:Hide() self.shown = false; self.writes = self.writes + 1 end
    return tex
end

local function LoadElement(client)
    local registered
    _G.CreateFrame = function(_, _, parent)
        local holder = { parent = parent }
        function holder:SetAllPoints() end
        function holder:EnableMouse() end
        function holder:SetClipsChildren() end
        function holder:SetFrameLevel() end
        function holder:CreateTexture() return Texture(self) end
        return holder
    end
    _G.MSUF_RequestPetHappinessIndicatorRefresh = nil
    local namespace = {
        Client = client,
        UF = {
            RegisterElement = function(name, value) registered = { name = name, element = value } end,
            RefreshElements = function() return true end,
        },
    }
    assert(loadfile(core .. "Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua"))("MidnightSimpleUnitFrames", namespace)
    return registered and registered.element, registered and registered.name
end

local function PetFrame()
    return {
        MSUFUnitKey = "pet",
        MSUFSpec = { status = { alpha = 1, testMode = false,
            petHappiness = { enabled = true, size = 24, anchor = "RIGHT", x = -7, y = -4, layer = 7 } } },
        Health = { GetFrameLevel = function() return 10 end },
    }
end

local COORDS = { [1] = 0.375, [2] = 0.1875, [3] = 0 }

do
    -- Forever: only C_PetInfo.GetPetHappiness exists.
    local happiness, hunterPet = 3, true
    _G.GetPetHappiness = nil
    _G.C_PetInfo = { GetPetHappiness = function()
        if happiness == nil then return end
        return happiness, 100, 0
    end }
    _G.HasPetUI = function() return true, hunterPet end
    local element, name = LoadElement(LoadClient(true))
    Check(name == "PetHappinessIndicator" and type(element) == "table", "Forever: the happiness element was not registered")
    Check(type(_G.MSUF_RequestPetHappinessIndicatorRefresh) == "function", "Forever: the menu refresh bridge is missing")

    local frame = PetFrame()
    Check(element.IsEnabled(frame, frame.MSUFSpec) == true, "Forever: the indicator must be enabled on the pet frame")
    element.Create(frame, frame.MSUFSpec)
    element.Apply(frame, frame.MSUFSpec)
    local tex = Check(frame.petHappinessIndicatorIcon, "Forever: the happiness texture was not created")
    Check(tex.width == 24 and tex.point[1] == "RIGHT" and tex.point[4] == -7 and tex.point[5] == -4,
        "Forever: the indicator lost its size or placement")
    for state = 1, 3 do
        happiness = state
        element.Update(frame)
        Check(tex.shown == true and tex.coords[1] == COORDS[state],
            "Forever: happiness state " .. state .. " read through C_PetInfo drew the wrong icon")
    end
    happiness = nil
    element.Update(frame)
    Check(tex.shown == false, "Forever: no happiness value (no hunter pet) must hide the icon")
    happiness = { secret = true }
    element.Update(frame)
    Check(tex.shown == false, "Forever: a secret happiness value must hide the icon instead of being compared")
    happiness, hunterPet = 3, false
    element.Update(frame)
    Check(tex.shown == false, "Forever: a non-hunter pet must hide the icon")

    -- Cost contract: happiness events repeat the same state, so only a change may
    -- touch the texture, and a missing pet asks one API, not two.
    local petUICalls = 0
    _G.HasPetUI = function() petUICalls = petUICalls + 1; return true, hunterPet end
    element = LoadElement(LoadClient(true))
    frame = PetFrame()
    element.Create(frame, frame.MSUFSpec)
    tex = frame.petHappinessIndicatorIcon
    Check(tex.texture == "Interface\\PetPaperDollFrame\\UI-PetHappiness", "the icon texture must be set when it is created")
    happiness, hunterPet = 2, true
    element.Update(frame)
    local afterFirst = tex.writes
    for _ = 1, 20 do element.Update(frame) end
    Check(tex.writes == afterFirst and tex.shown == true and tex.coords[1] == COORDS[2],
        "an unchanged happiness state must not write to the texture again")
    happiness = 3
    element.Update(frame)
    Check(tex.writes == afterFirst + 1 and tex.coords[1] == COORDS[3], "a new state must cost exactly one coordinate write")
    happiness = nil
    element.Update(frame)
    local afterHide, callsBefore = tex.writes, petUICalls
    for _ = 1, 20 do element.Update(frame) end
    Check(tex.writes == afterHide and tex.shown == false, "a hidden icon must not be hidden again")
    Check(petUICalls == callsBefore, "without a happiness value HasPetUI must not be asked")
    happiness = 3
    element.Update(frame)
    Check(tex.shown == true and tex.writes == afterHide + 1, "the same state after a hide must cost only the Show")
    element.Disable(frame)
    Check(tex.shown == false, "Disable must hide the icon")
    element.Update(frame)
    Check(tex.shown == true, "the icon must come back after Disable")
    local playerFrame = PetFrame()
    playerFrame.MSUFUnitKey = "player"
    Check(element.IsEnabled(playerFrame, playerFrame.MSUFSpec) ~= true, "Forever: the indicator belongs to the pet frame only")
    local lifecycle = element.GetUnitlessEvents(frame, frame.MSUFSpec)
    Check(lifecycle[1] == "UNIT_HAPPINESS", "Forever: UNIT_HAPPINESS must stay on the unitless route")
end

do
    -- Classic Era and TBC: only the global exists.
    _G.C_PetInfo = nil
    _G.GetPetHappiness = function() return 2, 100, 0 end
    _G.HasPetUI = function() return true, true end
    local element = LoadElement({ SupportsPetHappiness = true, IsClassic = true })
    local frame = PetFrame()
    element.Create(frame, frame.MSUFSpec)
    element.Update(frame)
    Check(frame.petHappinessIndicatorIcon.shown == true and frame.petHappinessIndicatorIcon.coords[1] == COORDS[2],
        "Classic: the global GetPetHappiness is no longer read")
end

do
    -- Midnight shares the Mainline manifest with Forever: the file must stay inert.
    _G.C_PetInfo = { GetPetHappiness = function() error("Midnight must never read pet happiness") end }
    local element = LoadElement(LoadClient(false))
    Check(element == nil, "Midnight: the happiness element was registered")
    Check(_G.MSUF_RequestPetHappinessIndicatorRefresh == nil, "Midnight: the refresh bridge was published")
end

---------------------------------------------------------------------------
-- Mainline defaults: seeded on Forever only, user choices kept
---------------------------------------------------------------------------
local function LoadDefaults(isForever, petConf)
    local _, namespace = LoadClient(isForever)
    namespace.ExportPublic = function(name, value) _G[name] = value end
    _G.GetLocale = function() return "enUS" end
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "TestRealm" end
    _G.InCombatLockdown = function() return false end
    local function load(path) assert(loadfile(core .. path))("MidnightSimpleUnitFrames", namespace) end
    load("State/MSUF_StateHelpers.lua")
    load("State/MSUF_ProfileCodec.lua")
    local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    manifest.LoadSelected(root, "Mainline", namespace, {
        "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua",
        "State/Defaults/MSUF_Defaults_Bars.lua", "State/Defaults/MSUF_Defaults_Units.lua",
        "State/MSUF_Defaults.lua",
    })
    _G.MSUF_DB = { _msufProfileSchema = 600, general = {}, pet = petConf or {} }
    _G.MSUF_EnsureDB(true)
    return _G.MSUF_DB.pet
end

do
    local pet = LoadDefaults(true)
    Check(pet.showPetHappinessIndicator == true and pet.petHappinessIndicatorSize == 24
        and pet.petHappinessIndicatorAnchor == "RIGHT" and pet.petHappinessIndicatorOffsetX == -7
        and pet.petHappinessIndicatorOffsetY == -4 and pet.petHappinessIndicatorLayer == 7,
        "Forever: the pet happiness defaults were not seeded like on Classic Era and TBC")
    pet = LoadDefaults(true, { showPetHappinessIndicator = false, petHappinessIndicatorSize = 40 })
    Check(pet.showPetHappinessIndicator == false and pet.petHappinessIndicatorSize == 40,
        "Forever: seeding overwrote the player's own pet happiness settings")
    pet = LoadDefaults(false)
    Check(pet.showPetHappinessIndicator == nil and pet.petHappinessIndicatorSize == nil,
        "Midnight: dead pet happiness fields were added to the profile")
end

---------------------------------------------------------------------------
-- Mainline config compiler: the status entry follows the client fact
---------------------------------------------------------------------------
local function CompilePetStatus(isForever)
    local _, namespace = LoadClient(isForever)
    namespace.ExportPublic = function(name, value) _G[name] = value; return value end
    _G.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.MSUF_UF_OutlineModeEnabled = function() return false end
    _G.MSUF_UF_NormalizeClassPowerShape = function(value) return value end
    _G.MSUF_ComposeFontFlags = function() return "" end
    _G.MSUF_ResolveFontShadowMetrics = function() return 0, 0, 0 end
    _G.MSUF_CooldownAnchorSupported = function() return false end
    _G.MSUF_GlobalCooldownAnchorEnabled = function() return false end
    local function load(path) assert(loadfile(core .. path))("MidnightSimpleUnitFrames", namespace) end
    load("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
    load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
    load("UnitFrames/Engine/MSUF_UF_Shared.lua")
    load("UnitFrames/Engine/MSUF_UF_Config.lua")
    local seeded = { showPetHappinessIndicator = true, petHappinessIndicatorSize = 24, petHappinessIndicatorAnchor = "RIGHT",
        petHappinessIndicatorOffsetX = -7, petHappinessIndicatorOffsetY = -4, petHappinessIndicatorLayer = 7 }
    _G.MSUF_DB = { general = {}, pet = seeded, player = {} }
    _G.MSUF_EnsureDB = function() return _G.MSUF_DB end
    local config = namespace.UF.Config
    return config.GetSpec("pet").status.petHappiness, config.GetSpec("player").status.petHappiness
end

do
    local pet, player = CompilePetStatus(true)
    Check(type(pet) == "table" and pet.enabled == true and pet.size == 24 and pet.anchor == "RIGHT"
        and pet.x == -7 and pet.y == -4 and pet.layer == 7,
        "Forever: the Mainline config did not compile the pet happiness entry")
    Check(not (player and player.enabled == true), "Forever: pet happiness was enabled on the player frame")
    pet = CompilePetStatus(false)
    Check(pet == nil, "Midnight: the Mainline config must compile no pet happiness entry at all")
end

---------------------------------------------------------------------------
-- Manifests
---------------------------------------------------------------------------
do
    local module = "MSUF_UF_PetHappiness.lua"
    -- The gate compares the Classic shared element manifest with the Mainline manifest up to the
    -- Auras3 icon definitions, so the module loads right behind that prefix, as on Vanilla and TBC.
    Check(Read("MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml")
        :find('Auras3\\MSUF_Auras3_IconShape.lua"/>\n  <Script file="..\\..\\..\\Game\\Shared\\UnitFrames\\' .. module, 1, true),
        "the Mainline manifest must load the shared happiness module right after the Auras3 icon definitions")
    for _, flavor in ipairs({ "Vanilla", "TBC" }) do
        Check(Read("MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames.xml")
            :find("..\\Shared\\UnitFrames\\" .. module, 1, true), flavor .. " must load the shared happiness module")
    end
    Check(not Read("MidnightSimpleUnitFrames/Game/Mists/UnitFrames.xml"):find(module, 1, true),
        "Mists must not load the happiness module")
end

---------------------------------------------------------------------------
-- Mainline menu: the preview and control spec exists on Forever only
---------------------------------------------------------------------------
do
    local function PipeRows(rows)
        local out = {}
        for line in rows:gmatch("[^\r\n]+") do
            local columns = {}
            for value in (line .. "|"):gmatch("(.-)|") do columns[#columns + 1] = value end
            out[#out + 1] = columns
        end
        return out
    end
    local function HappinessSpec(isForever)
        local main = { Client = LoadClient(isForever), MSUF2 = { PipeRows = PipeRows } }
        assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua"))(
            "MidnightSimpleUnitFrames_Options", main)
        local rows = main.UFPreviewSpecs.StatusPreview
        for index, spec in ipairs(rows) do
            if spec.id == "statusPetHappiness" then return spec, index, #rows, rows[#rows].id end
        end
        return nil, nil, #rows, rows[#rows].id
    end

    local spec, index, count, lastID = HappinessSpec(true)
    Check(spec, "Forever: the Mainline preview specs have no pet happiness row")
    Check(spec.show == "showPetHappinessIndicator" and spec.size == "petHappinessIndicatorSize"
        and spec.defaultSize == 24 and spec.defaultAnchor == "RIGHT" and spec.defaultX == -7 and spec.defaultY == -4
        and spec.defaultLayer == 7 and spec.refresh == "MSUF_RequestPetHappinessIndicatorRefresh",
        "Forever: the pet happiness preview spec drifted from the runtime defaults")
    Check(spec.allowed("pet") == true and spec.allowed("player") == false, "Forever: pet happiness must be pet-only")
    Check(index == count - 1 and lastID == "stance", "Forever: pet happiness must sit before the stance row")

    local midnightSpec, _, midnightCount = HappinessSpec(false)
    Check(midnightSpec == nil and midnightCount == count - 1, "Midnight: the preview specs gained a pet happiness row")

    local unitPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua")
    Check(unitPage:find('if MSUF.Client ~= nil and MSUF.Client.SupportsPetHappiness == true then\n'
        .. '    STATUS_CONTROLS[#STATUS_CONTROLS + 1] = StatusControl("statusPetHappiness", "Pet Happiness"', 1, true),
        "the Mainline unit page must add the pet happiness control only where the client supports it")
end

---------------------------------------------------------------------------
-- Mainline menu search: the pet page answers "pet happiness" on Forever only
---------------------------------------------------------------------------
do
    local function Keywords(isForever)
        local main = { Client = LoadClient(isForever), MSUF2 = {} }
        assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords.lua"))(
            "MidnightSimpleUnitFrames_Options", main)
        return main.MSUF2.SearchData.KEYWORDS
    end

    local forever, midnight = Keywords(true), Keywords(false)
    Check(forever.uf_pet:find(" pet happiness ", 1, true) and forever.uf_pet:find(" hunter pet ", 1, true),
        "Forever: the pet page search keywords lack pet happiness")
    Check(not midnight.uf_pet:find("happiness", 1, true), "Midnight: the pet page search keywords gained pet happiness")
    Check(forever.uf_pet:sub(1, #midnight.uf_pet) == midnight.uf_pet,
        "Forever: the pet page keywords must only append to the Midnight text")
    for key, text in pairs(midnight) do
        -- opt_fonts carries the Forever character name words (forever_character_names_smoke).
        if key ~= "uf_pet" and key ~= "opt_fonts" then
            Check(forever[key] == text, "Forever: search keywords changed for " .. key)
        end
    end
end

print("forever_pet_happiness_smoke: ok")
