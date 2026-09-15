local flavor = assert(arg[1], "client flavor required")
local repo = assert(arg[2], "repo root required")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_MISTS_CLASSIC = 19
issecretvalue = function() return false end
-- Blizzard_ArenaUI is LoadOnDemand, so MAX_ARENA_ENEMIES is nil at every login.
MAX_ARENA_ENEMIES = nil
MSUF_MAX_ARENA_FRAMES = nil

-- toc names the shipped TOC whose load graph is used; expect is the flavor the
-- client detection must report for that TOC, project ID and X-MSUF-Client tag.
local specs = {
    Mainline = { toc = "Mainline", expect = "Mainline", project = WOW_PROJECT_MAINLINE, interface = 120105, classic = false, arena = 3 },
    Vanilla = { toc = "Vanilla", expect = "Vanilla", project = WOW_PROJECT_CLASSIC, interface = 11509, tag = "Vanilla", classic = true, arena = 0 },
    Mists = { toc = "Mists", expect = "Mists", project = WOW_PROJECT_MISTS_CLASSIC, interface = 50504, tag = "Mists", classic = true, arena = 5 },
    TBC = { toc = "TBC", expect = "TBC", project = WOW_PROJECT_BURNING_CRUSADE_CLASSIC, interface = 20506, tag = "TBC", classic = true, arena = 5 },
    -- A future Vanilla build under a new project ID is placed by its TOC tag.
    FutureTaggedVanilla = { toc = "Vanilla", expect = "Vanilla", project = 99, interface = 199999, tag = "Vanilla", classic = true, arena = 0 },
    -- A future Vanilla interface under the known project ID needs no tag.
    FutureProjectVanilla = { toc = "Vanilla", expect = "Vanilla", project = WOW_PROJECT_CLASSIC, interface = 199999, classic = true, arena = 0 },
    -- An untagged TOC under an unknown project ID activates no flavor.
    UnknownUntagged = { toc = "Mainline", expect = "Unknown", project = 99, interface = 120105, classic = false, arena = 0 },
}
-- TagOnly<Flavor> places a Classic flavor by its X-MSUF-Client tag alone: an
-- unknown project ID, that flavor's TOC and interface, and the tag in arg[3].
-- The gate builds one such spec per client matrix token and passes the token.
local tagOnlyFlavor = flavor:match("^TagOnly(%u%w*)$")
if tagOnlyFlavor then
    local base = assert(specs[tagOnlyFlavor], "tag-only spec names no known flavor: " .. flavor)
    assert(base.classic, "tag-only spec needs a Classic flavor: " .. flavor)
    specs[flavor] = { toc = base.toc, expect = base.expect, project = 99, interface = base.interface,
        tag = assert(arg[3], "tag-only spec needs the X-MSUF-Client token in arg[3]"), classic = true, arena = base.arena }
end
local spec = assert(specs[flavor], "unknown flavor: " .. tostring(flavor))
WOW_PROJECT_ID = spec.project

C_AddOns = {
    GetAddOnMetadata = function(_, key)
        if key == "X-MSUF-Client" then return spec.tag end
        return nil
    end,
}
local originalAddOns = C_AddOns
local originalMetadata = C_AddOns.GetAddOnMetadata
C_Spell = nil
C_SpellBook = nil
function GetBuildInfo()
    return "test", "test", "test", spec.interface
end

local addonName = "MidnightSimpleUnitFrames"
local namespace = {}
local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, spec.toc, namespace, providers)

local expect = spec.expect
assert(MSUF == namespace, "client bootstrap did not publish MSUF")
assert(namespace.Client.Flavor == expect, "wrong flavor")
assert(namespace.Client.IsClassic == spec.classic, "wrong Classic flag")
assert(namespace.Client.IsVanilla == (expect == "Vanilla"), "wrong Vanilla flag")
assert(namespace.Client.IsEra == (expect == "Vanilla"), "wrong Era flag")
assert(namespace.Client.IsMists == (expect == "Mists"), "wrong Mists flag")
assert(namespace.Client.IsTBC == (expect == "TBC"), "wrong TBC flag")
assert(namespace.Client.IsRetail == (expect == "Mainline"), "wrong Retail flag")
assert(namespace.Client.SupportsPetHappiness == (expect == "Vanilla" or expect == "TBC"),
    "wrong Pet Happiness capability")
assert(namespace.Client.MaxArenaOpponents == spec.arena,
    "wrong arena opponent slots: " .. tostring(namespace.Client.MaxArenaOpponents))
assert(MSUF_MAX_ARENA_FRAMES == spec.arena, "MSUF_MAX_ARENA_FRAMES differs from the client arena slots")
assert(MAX_ARENA_ENEMIES == nil, "client bootstrap defined Blizzard MAX_ARENA_ENEMIES")
local flavorKnown = expect ~= "Unknown"
local projectKnown = spec.project == WOW_PROJECT_MAINLINE or spec.project == WOW_PROJECT_CLASSIC
    or spec.project == WOW_PROJECT_MISTS_CLASSIC or spec.project == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
assert(namespace.Client.IsSupported == flavorKnown, "wrong supported-client flag")
assert(namespace.Client.ProjectIDRecognized == projectKnown, "wrong project-ID recognition")
assert(namespace.Client.HasSecretValueAPI == true, "secret-value API not detected")
assert(namespace.Client.IsForever == false, "IsForever must stay false until a real Forever client fact exists")
if flavorKnown and projectKnown then
    assert(namespace.Client.Diagnostic == nil, "known client built a diagnostic")
else
    assert(type(namespace.Client.Diagnostic) == "string", "unplaced client built no diagnostic")
end
if tagOnlyFlavor then
    assert(namespace.Client.IsSupported == true and namespace.Client.ProjectIDRecognized == false,
        "tag-only client must be supported without a recognized project ID")
    assert(namespace.Client.TOCFlavor == spec.tag:lower(), "tag-only client lost its normalized tag")
    assert(namespace.Client.Diagnostic:find("using the " .. expect .. " TOC build", 1, true),
        "tag-only diagnostic does not name the flavor its tag selected")
end
assert(namespace.Client.SupportsEvent("PVP_MATCH_STATE_CHANGED") == (not spec.classic),
    "live-only PvP match event capability mismatch")
assert(namespace.Client.Interface == spec.interface, "wrong interface")
assert(namespace.Client.SupportsEvent("PLAYER_ENTERING_WORLD") == true, "known event was rejected")
assert(namespace.Client.SupportsEvent("UNIT_POWER_POINT_CHARGE") == (not spec.classic), "point-charge event capability mismatch")
assert(namespace.Client.SupportsEvent("WAR_MODE_STATUS_UPDATE") == (not spec.classic), "war-mode event capability mismatch")
assert(C_AddOns == originalAddOns and C_AddOns.GetAddOnMetadata == originalMetadata,
    "client bootstrap replaced or rewrote Blizzard C_AddOns")
assert(C_AddOns.IsAddOnLoaded == nil and C_AddOns.LoadAddOn == nil,
    "client bootstrap added fields to Blizzard C_AddOns")
assert(C_Spell == nil and C_SpellBook == nil,
    "client bootstrap created Blizzard C_Spell/C_SpellBook namespaces")
if spec.classic then
    assert(type(namespace.Compat.AddOns) == "table"
        and namespace.Compat.AddOns.GetAddOnMetadata == originalMetadata,
        "Classic local AddOns compatibility adapter missing")
    assert(type(namespace.Compat.Spell) == "table" and type(namespace.Compat.Spell.GetSpellName) == "function",
        "Classic local spell compatibility adapter missing")
    assert(type(namespace.Compat.SpellBook) == "table",
        "Classic local spellbook compatibility adapter missing")
else
    assert(namespace.Compat.AddOns == nil and namespace.Compat.Spell == nil and namespace.Compat.SpellBook == nil,
        "Mainline loaded Classic compatibility adapters")
end

local bootstrapChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"))
bootstrapChunk(addonName, namespace)
assert(MSUF == namespace and MSUF_NS == namespace, "kernel replaced client namespace")
assert(namespace.Compat.Client == namespace.Client, "client compat bridge was lost")
assert(namespace.Core.BootstrapLoaded == true, "kernel bootstrap did not finish")
assert(MSUF_MAX_ARENA_FRAMES == spec.arena, "kernel bootstrap changed MSUF_MAX_ARENA_FRAMES")

-- A Classic interface is intentionally below 120100 but must not arm the
-- Retail-only old-client popup or create its fallback event frame.
function CreateFrame()
    error("client version warning created a frame for " .. flavor)
end
local warningChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/Features/MSUF_ClientVersionWarning.lua"))
warningChunk(addonName, namespace)
assert(namespace.ClientVersionWarning.IsLegacyClient() == false, "Classic was classified as legacy Retail")

-- Old-client warning matrix. Each case reloads the warning into a private
-- namespace whose EventBus and module registry only count calls, so a legacy
-- classification is observable without a frame (CreateFrame still raises).
-- Only Mainline, or a namespace without a client table, warns below 120100.
-- Classic flavors never warn, and neither does an unrecognized client:
-- Game/Shared/Initialize.lua already prints its diagnostic.
local detectedGetBuildInfo = GetBuildInfo
local function WarningIsLegacy(client, interface)
    local wired = 0
    local warningNamespace = {
        Client = client,
        ExportPublic = function() end,
        MSUF_EventBus = { Register = function() wired = wired + 1 end },
        MSUF_RegisterModule = function() wired = wired + 1 end,
    }
    if interface == nil then
        GetBuildInfo = nil
    else
        GetBuildInfo = function() return "test", "test", "test", interface end
    end
    warningChunk(addonName, warningNamespace)
    GetBuildInfo = detectedGetBuildInfo
    local legacy = warningNamespace.ClientVersionWarning.IsLegacyClient()
    assert(wired == (legacy and 2 or 0), "old-client warning wiring does not match its classification")
    return legacy
end
local MIN_INTERFACE = 120100
for _, interface in ipairs({ 11600, 50504, 120001, MIN_INTERFACE, spec.interface }) do
    assert(WarningIsLegacy(namespace.Client, interface) == (expect == "Mainline" and interface < MIN_INTERFACE),
        "old-client warning classification for " .. flavor .. " at interface " .. interface)
end
assert(WarningIsLegacy(nil, 120001) == true, "a namespace without a client table stopped warning below 12.1")
assert(WarningIsLegacy(nil, MIN_INTERFACE) == false, "a namespace without a client table warned on 12.1")
assert(WarningIsLegacy(nil, nil) == false, "an unreadable build warned")
assert(WarningIsLegacy({ IsClassic = false }, 120001) == true,
    "only Client.IsSupported == false may silence the warning")
assert(WarningIsLegacy({ IsClassic = false, IsSupported = false }, 11600) == false,
    "an unrecognized client got the old Retail client warning")

print("client bootstrap smoke passed: " .. flavor)
