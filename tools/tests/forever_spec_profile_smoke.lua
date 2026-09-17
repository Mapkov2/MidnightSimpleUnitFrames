-- WoW Forever specialization consumers smoke.
--
--   lua tools/tests/forever_spec_profile_smoke.lua <repo root> <Mainline|Vanilla|TBC|Mists|Forever>
--
-- WoW Forever does not load Blizzard_DeprecatedSpecialization (AllowLoadGameType
-- classic, standard), so the global GetSpecialization, GetSpecializationInfo and
-- GetNumSpecializations it provides are nil there. Every class has a single
-- specialization, and players switch between two talent groups instead
-- (Camelot Blizzard_ClassTalentsFrame: C_SpecializationInfo.GetActiveSpecGroup,
-- DUAL_SPEC_PRIMARY/DUAL_SPEC_SECONDARY tabs, ACTIVE_TALENT_GROUP_CHANGED).
--
-- Forever (real detection: Game/Shared/Initialize.lua with the Camelot marker):
--   * State/MSUF_Profiles.lua keys spec profiles by the active talent group and
--     switches on ACTIVE_TALENT_GROUP_CHANGED, deferring past combat.
--   * The Menu2 profiles page lists the two talent groups under Blizzard's labels,
--     and falls back to its empty state without them.
--   * The gameplay spec helper reads the C_SpecializationInfo pair.
-- Every other flavor keeps the global-only behaviour byte for byte: a spec ID
-- from the globals when they exist, nil otherwise, even with C_SpecializationInfo
-- present.
local repo = assert(arg[1], "repository root is required")
local flavor = assert(arg[2], "flavor required (Mainline|Vanilla|TBC|Mists|Forever)")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_MISTS_CLASSIC = 19

local specs = {
    Mainline = { project = WOW_PROJECT_MAINLINE, interface = 120105, toc = "Mainline" },
    Vanilla = { project = WOW_PROJECT_CLASSIC, interface = 11509, tag = "Vanilla", toc = "Vanilla", classic = true },
    TBC = { project = WOW_PROJECT_BURNING_CRUSADE_CLASSIC, interface = 20506, tag = "TBC", toc = "TBC", classic = true },
    Mists = { project = WOW_PROJECT_MISTS_CLASSIC, interface = 50504, tag = "Mists", toc = "Mists", classic = true },
    Forever = { project = WOW_PROJECT_MAINLINE, interface = 16001, toc = "Mainline", forever = true },
}
local spec = assert(specs[flavor], "unknown flavor: " .. tostring(flavor))
local IS_FOREVER_RUN = spec.forever == true

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

WOW_PROJECT_ID = spec.project
C_AddOns = {
    GetAddOnMetadata = function(_, key)
        if key == "X-MSUF-Client" then return spec.tag end
        return nil
    end,
}
function GetBuildInfo() return "test", "test", "test", spec.interface end
issecretvalue = function() return false end
Enum = {}
if IS_FOREVER_RUN then
    GameEvent = { RegisterCamelotEvents = function() error("the Forever marker must never be called") end }
end
function UnitName(unit)
    Check(unit == "player", "character key asked for a unit other than the player")
    return "Tester"
end
function GetRealmName() return "Realm" end
function UnitSex() return 2 end
print = function() end

-- Frames: record registered events and the OnEvent handler.
local function Noop() end
local function NewFrame()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(kind, fn) if kind == "OnEvent" then self.onEvent = fn end end
    return setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Noop end
        return nil
    end })
end
CreateFrame = function() return NewFrame() end
local inCombat = false
InCombatLockdown = function() return inCombat end

-- Blizzard specialization API. C_SpecializationInfo exists on every client in
-- this smoke; the deprecated globals exist only where a test installs them.
local activeGroup = 1
local cSpecIndex, cSpecID = 1, 1486 -- ChrSpecialization 1.60.1.69876: 1486 Paladin
C_SpecializationInfo = {
    GetActiveSpecGroup = function() return activeGroup end,
    GetSpecialization = function() return cSpecIndex end,
    GetSpecializationInfo = function(index)
        if index == 1 then return cSpecID, "Paladin" end
        return 0
    end,
}
local RETAIL_SPECS = { { 65, "Holy" }, { 66, "Protection" }, { 70, "Retribution" } }
local function InstallDeprecatedGlobals()
    GetNumSpecializations = function() return #RETAIL_SPECS end
    GetSpecialization = function() return 2 end
    GetSpecializationInfo = function(index)
        local row = RETAIL_SPECS[index]
        if not row then return 0 end
        return row[1], row[2]
    end
end
local function RemoveDeprecatedGlobals()
    GetNumSpecializations, GetSpecialization, GetSpecializationInfo = nil, nil, nil
end
RemoveDeprecatedGlobals()

-- Load order: real client detection, then the State providers from the TOC.
local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local namespace = {}
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, spec.toc, namespace, providers)
Check(type(namespace.Client) == "table", "client detection did not run")
Check(namespace.Client.IsForever == IS_FOREVER_RUN, "IsForever is " .. tostring(namespace.Client.IsForever))

function namespace.ExportPublic(name, value)
    _G[name] = value
    namespace.Public = namespace.Public or {}
    namespace.Public[name] = value
    return value
end
manifest.LoadSelected(repo, spec.toc, namespace, {
    "State/MSUF_FirstLoad.lua",
    "Kernel/MSUF_Require.lua",
    "State/MSUF_StateHelpers.lua",
    "State/MSUF_ProfileCodec.lua",
})
function MSUF_EnsureDB() end
function MSUF_CreateFactoryDefaultProfile() return { _msufProfileSchema = 600, general = {} } end
namespace.ProfileRuntime = { Apply = Noop }
MSUF_GF_InvalidateConfCache = Noop

MSUF_GlobalDB = {
    profiles = {
        Default = { _msufProfileSchema = 600, general = {} },
        Solo = { _msufProfileSchema = 600, general = {} },
        Raid = { _msufProfileSchema = 600, general = {} },
    },
    char = { ["Tester-Realm"] = { activeProfile = "Default" } },
    global = {},
}
MSUF_DB = MSUF_GlobalDB.profiles.Default
MSUF_ActiveProfile = "Default"

-- Profiles -----------------------------------------------------------------------
manifest.LoadSelected(repo, spec.toc, namespace, { "State/MSUF_Profiles.lua" })
Check(type(MSUF_GetPlayerSpecID) == "function", "MSUF_GetPlayerSpecID missing")
local eventFrame = MSUF_SpecProfileEventFrame
Check(type(eventFrame) == "table" and type(eventFrame.onEvent) == "function", "spec profile event frame missing")
Check(eventFrame.events.ACTIVE_TALENT_GROUP_CHANGED == true, "ACTIVE_TALENT_GROUP_CHANGED is not registered")

local switches = {}
MSUF_SwitchProfile = function(name)
    switches[#switches + 1] = name
    MSUF_ActiveProfile = name
end
local function LastSwitch() return switches[#switches] end

if IS_FOREVER_RUN then
    Check(MSUF_GetPlayerSpecID() == 1, "Forever did not key spec profiles by the primary talent group")
    activeGroup = 2
    Check(MSUF_GetPlayerSpecID() == 2, "Forever did not key spec profiles by the secondary talent group")
    activeGroup = 1

    MSUF_SetSpecProfile(1, "Solo")
    MSUF_SetSpecProfile(2, "Raid")
    Check(MSUF_GetSpecProfile(1) == "Solo" and MSUF_GetSpecProfile(2) == "Raid", "talent group bindings were not stored")
    MSUF_SetSpecAutoSwitchEnabled(true)
    Check(#switches == 1 and LastSwitch() == "Solo", "enabling auto-switch did not load the primary group profile")

    activeGroup = 2
    eventFrame.onEvent(eventFrame, "ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
    Check(#switches == 2 and LastSwitch() == "Raid", "a talent group change did not switch the profile")

    -- A change in combat waits for PLAYER_REGEN_ENABLED.
    inCombat = true
    activeGroup = 1
    eventFrame.onEvent(eventFrame, "ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
    Check(#switches == 2, "a talent group change switched profiles in combat")
    local deferFrame = MSUF_SpecProfileDeferFrame
    Check(type(deferFrame) == "table" and deferFrame.events.PLAYER_REGEN_ENABLED == true, "combat switch was not deferred")
    inCombat = false
    deferFrame.onEvent(deferFrame, "PLAYER_REGEN_ENABLED")
    Check(#switches == 3 and LastSwitch() == "Solo", "the deferred switch did not run after combat")

    -- An unbound group keeps the current profile.
    MSUF_SetSpecProfile(2, nil)
    activeGroup = 2
    eventFrame.onEvent(eventFrame, "ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
    Check(#switches == 3 and MSUF_ActiveProfile == "Solo", "an unbound talent group switched profiles")

    -- Without the group API there is no key and no switch.
    local getActiveGroup = C_SpecializationInfo.GetActiveSpecGroup
    C_SpecializationInfo.GetActiveSpecGroup = nil
    Check(MSUF_GetPlayerSpecID() == nil, "a missing GetActiveSpecGroup produced a key")
    C_SpecializationInfo.GetActiveSpecGroup = getActiveGroup
    activeGroup = 0
    Check(MSUF_GetPlayerSpecID() == nil, "talent group 0 produced a key")
    activeGroup = 1
    MSUF_SetSpecAutoSwitchEnabled(false)
else
    Check(MSUF_GetPlayerSpecID() == nil, "the C_SpecializationInfo group API leaked into a non-Forever client")
    InstallDeprecatedGlobals()
    Check(MSUF_GetPlayerSpecID() == 66, "the global spec ID path changed")
    MSUF_SetSpecProfile(66, "Raid")
    MSUF_SetSpecAutoSwitchEnabled(true)
    Check(#switches == 1 and LastSwitch() == "Raid", "spec auto-switch changed on a non-Forever client")
    MSUF_SetSpecAutoSwitchEnabled(false)
    RemoveDeprecatedGlobals()
end

-- Gameplay spec helper -------------------------------------------------------------
local function LoadGameplayHelpers()
    manifest.LoadSelected(repo, spec.toc, namespace, { "Features/Gameplay/MSUF_Feature_GameplayHelpers.lua" })
    Check(type(namespace.Gameplay) == "table" and type(namespace.Gameplay.GetPlayerSpecID) == "function",
        "gameplay spec helper missing")
    Check(namespace.MSUF_GetPlayerSpecID == namespace.Gameplay.GetPlayerSpecID, "gameplay spec helper export changed")
    return namespace.Gameplay.GetPlayerSpecID
end
local gameplaySpecID = LoadGameplayHelpers()
if IS_FOREVER_RUN then
    Check(gameplaySpecID() == 1486, "Forever gameplay spec helper did not read C_SpecializationInfo")
    cSpecIndex = 0
    Check(gameplaySpecID() == nil, "Forever gameplay spec helper accepted spec index 0")
    cSpecIndex = 2
    Check(gameplaySpecID() == nil, "Forever gameplay spec helper accepted spec ID 0")
    cSpecIndex = 1
else
    Check(gameplaySpecID() == nil, "C_SpecializationInfo leaked into the non-Forever gameplay spec helper")
    InstallDeprecatedGlobals()
    gameplaySpecID = LoadGameplayHelpers()
    Check(gameplaySpecID() == 66, "the global gameplay spec path changed")
    RemoveDeprecatedGlobals()
end

-- Menu2 profiles page ----------------------------------------------------------------
local function Stub(fields)
    return setmetatable(fields or {}, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Noop end
        return nil
    end })
end
local cards, dropdowns, refreshes = {}, {}, {}
local W = Stub({
    ControlCard = function(_, title)
        cards[#cards + 1] = title
        return Stub()
    end,
    SwitchAt = function() return Stub() end,
    Text = function() return Stub() end,
    Dropdown = function() return Stub() end,
})
local colors = setmetatable({}, { __index = function() return { 0, 0, 0, 1 } end })
local M = {
    Widgets = W,
    Theme = Stub({ colors = colors }),
    AdvancedPage = { RegisterControl = Noop, ControlMeta = function() return {} end },
    Tr = function(text) return text end,
    Format = function(fmt, ...) return string.format(fmt, ...) end,
    BindBoolWidget = Noop,
    BindDropdownWidget = function(_, _, getter, setter)
        dropdowns[#dropdowns + 1] = { get = getter, set = setter }
    end,
    TrackCollapsibleRefresh = function(_, _, fn) refreshes[#refreshes + 1] = fn end,
    RegisterPage = Noop,
}
-- The Options addon namespace reads through to the core namespace
-- (MSUF_OptionsLOD_Bootstrap.lua), which is where MSUF.Client lives.
local optionsNamespace = setmetatable({ MSUF2 = M }, { __index = namespace })
local pagePath = repo .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua"
local pageFile = assert(io.open(pagePath, "rb"))
local pageSource = pageFile:read("*a")
pageFile:close()
Check(pageSource:find("function ProfilesPage.Specializations(state)", 1, true) ~= nil,
    "profiles page no longer defines ProfilesPage.Specializations(state)")
local ProfilesPage = assert(loadstring(pageSource .. "\nreturn ProfilesPage", "@" .. pagePath))(
    "MidnightSimpleUnitFrames_Options", optionsNamespace)

local builder = Stub({ CollapsibleSection = function() return Stub() end })
local function BuildSpecializations()
    cards, dropdowns, refreshes = {}, {}, {}
    ProfilesPage.Specializations({ ctx = {}, b = builder, contentW = 1000 })
    for i = 1, #refreshes do refreshes[i]() end
end
local function HasCard(title)
    for i = 1, #cards do if cards[i] == title then return true end end
    return false
end

if IS_FOREVER_RUN then
    DUAL_SPEC_PRIMARY, DUAL_SPEC_SECONDARY = "Primary", "Secondary"
    BuildSpecializations()
    Check(HasCard("Primary") and HasCard("Secondary"), "Forever page did not list both talent groups")
    Check(not HasCard("No specialization data"), "Forever page showed the empty state next to talent groups")
    Check(#dropdowns == 2, "Forever page built " .. #dropdowns .. " profile pickers")
    dropdowns[2].set("Raid")
    Check(MSUF_GetSpecProfile(2) == "Raid" and dropdowns[2].get() == "Raid", "secondary talent group picker did not bind group 2")
    dropdowns[1].set("None")
    Check(MSUF_GetSpecProfile(1) == nil and dropdowns[1].get() == "None", "primary talent group picker did not clear group 1")

    DUAL_SPEC_PRIMARY, DUAL_SPEC_SECONDARY = nil, nil
    BuildSpecializations()
    Check(HasCard("No specialization data") and #dropdowns == 0, "Forever page without Blizzard labels skipped its empty state")
    DUAL_SPEC_PRIMARY, DUAL_SPEC_SECONDARY = "Primary", "Secondary"
    local getActiveGroup = C_SpecializationInfo.GetActiveSpecGroup
    C_SpecializationInfo.GetActiveSpecGroup = nil
    BuildSpecializations()
    Check(HasCard("No specialization data") and #dropdowns == 0, "Forever page without the group API skipped its empty state")
    C_SpecializationInfo.GetActiveSpecGroup = getActiveGroup
else
    DUAL_SPEC_PRIMARY, DUAL_SPEC_SECONDARY = "Primary", "Secondary"
    BuildSpecializations()
    Check(HasCard("No specialization data") and #dropdowns == 0, "non-Forever page without spec globals changed")
    Check(not HasCard("Primary"), "talent groups leaked into a non-Forever page")
    InstallDeprecatedGlobals()
    BuildSpecializations()
    Check(HasCard("Holy") and HasCard("Protection") and HasCard("Retribution") and #dropdowns == 3,
        "non-Forever page no longer lists specializations from the globals")
    dropdowns[3].set("Solo")
    Check(MSUF_GetSpecProfile(70) == "Solo", "non-Forever spec picker did not bind the spec ID")
    RemoveDeprecatedGlobals()
end

io.write("forever_spec_profile_smoke: ok (" .. flavor .. ")\n")
