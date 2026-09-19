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
assert(namespace.Client.IsMists == (expect == "Mists"), "wrong Mists flag")
assert(namespace.Client.IsTBC == (expect == "TBC"), "wrong TBC flag")
assert(namespace.Client.IsRetail == (expect == "Mainline"), "wrong Retail flag")
assert(namespace.Client.Family == (expect == "Mainline" and "Mainline" or spec.classic and "Classic" or "Unknown"),
    "wrong code family: " .. tostring(namespace.Client.Family))
-- Classic Era scans dispellable debuffs with HARMFUL|RAID; every other client
-- with RAID_PLAYER_DISPELLABLE.
assert(namespace.Client.DispellableDebuffFilter
        == (expect == "Vanilla" and "HARMFUL|RAID" or "HARMFUL|RAID_PLAYER_DISPELLABLE"),
    "wrong dispellable debuff filter: " .. tostring(namespace.Client.DispellableDebuffFilter))
-- The harness defines no C_GameRules, like every client before game modes: Standard.
assert(namespace.Client.IsStandardGameMode == true and namespace.Client.GameModeRecognized == true,
    "a client without C_GameRules must count as the Standard game mode")
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
    -- On Mainline nothing creates MSUF.Compat before the kernel does, so an
    -- absent table is the expected state here.
    local compat = namespace.Compat or {}
    assert(compat.AddOns == nil and compat.Spell == nil and compat.SpellBook == nil,
        "Mainline loaded Classic compatibility adapters")
end

local bootstrapChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"))
bootstrapChunk(addonName, namespace)
assert(MSUF == namespace and MSUF_NS == namespace, "kernel replaced client namespace")
-- MSUF.Client is the single client surface: the kernel must not shadow or
-- replace it, and the dead MSUF.Compat.Client bridge must not come back.
assert(namespace.Client ~= nil and namespace.Compat.Client == nil,
    "the client model was replaced, or the dead Compat.Client bridge is back")
assert(namespace.Core.BootstrapLoaded == true, "kernel bootstrap did not finish")
assert(MSUF_MAX_ARENA_FRAMES == spec.arena, "kernel bootstrap changed MSUF_MAX_ARENA_FRAMES")

-- The old-client warning is a Midnight popup for builds below 12.1. It carries
-- no Classic guard and every Classic interface is below 120100, so a Classic TOC
-- must not load it at all (tools/classic-flavor-load-exclusions.tsv has the row).
local loadedWarnings = {}
for _, path in ipairs(manifest.Paths(repo, spec.toc)) do
    if path:find("ClientVersionWarning", 1, true) then loadedWarnings[#loadedWarnings + 1] = path end
end
if spec.toc == "Mainline" then
    assert(#loadedWarnings == 1
        and loadedWarnings[1]:find("/MidnightSimpleUnitFrames/Features/Versioning/MSUF_ClientVersionWarning.lua", 1, true),
        "the Mainline TOC must load exactly the Retail old-client warning")
else
    assert(#loadedWarnings == 0, spec.toc .. " TOC loads the Retail old-client warning: " .. tostring(loadedWarnings[1]))
end

-- Auras3 is the only reader of the warning and asks through a nil-safe lookup:
-- a client that never loads it answers like one whose warning reports a current
-- build. The code family decides, never the raw project ID.
do
    local file = assert(io.open(repo .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua", "rb"))
    local aurasCore = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local body = assert(aurasCore:match("local function NativeAuraRuntimeExpected%(%)(.-)\nend"),
        "Auras3 no longer decides the native aura runtime expectation in one function")
    local function NativeAuraRuntimeExpected(warning)
        return assert(loadstring("local MSUF = ...; return function() " .. body .. "\nend"))(
            { Client = namespace.Client, ClientVersionWarning = warning })()
    end
    local withoutWarning = NativeAuraRuntimeExpected(nil)
    assert(withoutWarning == (spec.project == WOW_PROJECT_MAINLINE),
        "native aura runtime expectation without the old-client warning for " .. flavor)
    assert(NativeAuraRuntimeExpected({ IsLegacyClient = function() return false end }) == withoutWarning,
        "a missing old-client warning must answer like a current-build warning for " .. flavor)
    assert(NativeAuraRuntimeExpected({ IsLegacyClient = function() return true end }) == false,
        "a legacy client must not expect the native aura runtime")
end

-- The Mainline TOC loads the Retail warning. WoW Forever reports a 1.x
-- interface number but runs the 12.1 aura runtime, so it never warns, and
-- neither does any client with Blizzard_AuraContainer loaded. The EventBus stub
-- only counts calls, so a legacy classification needs no frame.
function CreateFrame()
    error("client version warning created a frame for " .. flavor)
end
local detectedGetBuildInfo = GetBuildInfo
local MIN_INTERFACE = 120100
if expect == "Mainline" then
    local mainlineWarningChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Features/Versioning/MSUF_ClientVersionWarning.lua"))
    -- The interface number comes from Client.Interface, which
    -- Game/Shared/Initialize.lua reads once; the warning never calls
    -- GetBuildInfo itself. The stub stays installed so a re-read would show up
    -- as a wrong classification instead of passing silently.
    local function MainlineWarningIsLegacy(client, interface, auraContainerLoaded)
        local savedAddOns = C_AddOns
        C_AddOns = { IsAddOnLoaded = function(name) return auraContainerLoaded == true and name == "Blizzard_AuraContainer" end }
        GetBuildInfo = function() return "test", "test", "test", interface end
        local wired = 0
        if client ~= nil then client.Interface = interface end
        local warningNamespace = { Client = client, ExportPublic = function() end,
            MSUF_EventBus = { Register = function() wired = wired + 1 end } }
        mainlineWarningChunk(addonName, warningNamespace)
        C_AddOns, GetBuildInfo = savedAddOns, detectedGetBuildInfo
        local legacy = warningNamespace.ClientVersionWarning.IsLegacyClient()
        assert(wired == (legacy and 1 or 0), "Mainline old-client warning wiring does not match its classification")
        return legacy
    end
    assert(MainlineWarningIsLegacy({ IsForever = false }, 120001, false) == true, "Mainline 12.0 stopped warning")
    -- Without the client model there is no interface number, and this file's
    -- own rule is that an unreadable build never warns.
    assert(MainlineWarningIsLegacy(nil, 120001, false) == false,
        "the warning read a build the client model did not publish")
    assert(MainlineWarningIsLegacy({ IsForever = false }, MIN_INTERFACE, false) == false, "Mainline 12.1 warned")
    assert(MainlineWarningIsLegacy({ IsForever = true }, 16001, false) == false, "WoW Forever got the 12.1 warning")
    assert(MainlineWarningIsLegacy({ IsForever = false }, 16001, true) == false,
        "a client with Blizzard_AuraContainer loaded got the 12.1 warning")
    -- Mutation guard: the real model's interface must reach the warning.
    assert(MainlineWarningIsLegacy({ IsForever = false }, namespace.Client.Interface, false)
        == (namespace.Client.Interface < MIN_INTERFACE),
        "the warning ignored Client.Interface")
end

print("client bootstrap smoke passed: " .. flavor)
