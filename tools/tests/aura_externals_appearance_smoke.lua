-- Group External Defensives have their own Aura Appearance (border, shadow,
-- shape, skin). Each value follows the Buff Appearance until it is set for
-- Externals, so profiles saved before keep the look they had.
--
-- Real sources on stub dependencies:
--   1. Retail runtime (Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua):
--      unset Externals compile exactly the Buff style and shape, stored
--      Externals values win value by value, and a menu write waiting for its
--      apply keeps the Buff look (the combat snapshot of IconSkins);
--   2. Classic and Forever (Game/Classic/Auras/MSUF_Auras3_Visuals.lua): the
--      external group lane reads Externals with the same fallback, tracked
--      buffs stay on Buffs;
--   3. the menu model (Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua):
--      reads fall back to Buffs value by value and a write stores only the
--      edited value (the declared setting), so Buff edits keep reaching the
--      values Externals do not store.
-- Usage: lua tools/tests/aura_externals_appearance_smoke.lua <repoRoot>
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local function Shipped(path, declaration, name)
    return assert(loadstring(Slice.Function(Slice.Read(root .. "/" .. path), declaration, path)
        .. "\nreturn " .. name, name))()
end
local PROVIDERS = {
    MSUF_PixelLayoutRegion = function(region) return region end,
    MSUF_EventBus_Register = function() end,
    MSUF_EventBus_Unregister = function() end,
    MSUF_GetSharedMedia = function() return nil end,
    MSUF_IsKnownFileAsset = function() return nil end,
    MSUF_GetGeneralDB = Shipped("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua", "local function GetGeneralDB", "GetGeneralDB"),
    MSUF_NormalizeAuraDebuffTypeBorderMode = function(mode, fallback) return mode or fallback end,
}
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
local namespace = { MSUF_Auras3 = {} }
RequireFixture.InstallKernel(root, namespace)
function namespace.Require(name)
    return assert(PROVIDERS[name], "unexpected dependency " .. tostring(name))
end
local function Load(path)
    assert(loadfile(ADDON .. path))("MidnightSimpleUnitFrames", namespace)
end
InCombatLockdown = function() return false end
Load("Runtime/MSUF_BorderStyles.lua")
Load("Auras3/MSUF_Auras3_IconShape.lua")
Load("Auras3/MSUF_Auras3_IconSkins.lua")
local A3 = namespace.MSUF_Auras3
local Skins = assert(A3.IconSkins, "IconSkins did not load")

local failures = 0
local function Check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end

local db = { auras3 = { shared = {} } }
_G.MSUF_DB = db
A3.EnsureDB = function() return db.auras3, db.auras3.shared end
local function Profile()
    db.auras3.shared = {
        appearanceIconStyles = { buff = { styleBorderEnabled = true, styleBorderThickness = 3,
            styleBorderColor = { 1, 0, 0, 1 } } },
        appearanceIconShapes = { buff = "CIRCLE" },
    }
    return db.auras3.shared
end

-- 1. Retail runtime ------------------------------------------------------------------
A3.Runtime = { ConfigValues = {} }
A3.SpellIndicators = { NormalizeCandidateSpellIDs = function(ids) return ids end }
A3._runtimeConfigGen = 1
local Shape = A3.IconShape
local deps = {
    Appearance = { AURA_BORDER_OPTIONS = {}, Shape = Shape },
    Platform = {
        AURA_ICON_BASE_OFFSET = 0, UNIT_AURA_BASE_OFFSET = 0,
        MAX_CONFIGURABLE_DEBUFF_DURATION = 3600, MAX_FINITE_AURA_DURATION = 86400,
        Clamp01 = function(value, fallback)
            value = tonumber(value) or fallback
            return math.max(0, math.min(1, value))
        end,
        ClampNumber = function(value, fallback, low, high)
            value = tonumber(value) or fallback
            return math.max(low, math.min(high, value))
        end,
        Round = function(value) return math.floor(value + .5) end,
        issecretvalue = function() return false end,
    },
    Schema = {
        BOSS_FILTER_SCOPE_OWNER = {}, MANAGED_UNITS = {}, STYLE_SHARED_LAYOUT_KEYS = {}, UNIT_FLAG = {},
        DEFAULT_SHARED = { styleBorderThickness = 1, styleBorderColor = { 0, 0, 0, 1 }, styleShadowSize = 4,
            styleShadowColor = { 0, 0, 0, .8 } },
    },
    Signatures = { LaneShapeSignatures = function() end, LaneTrackingSignature = function() end },
}
Load("Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua")
local CV = namespace.Auras3RuntimeFactories.ConfigValues("MidnightSimpleUnitFrames", namespace, A3, {}, function() end, deps)
local function Compile(kind)
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    return CV.SharedIconStyle(kind)
end

local shared = Profile()
local buff, externals = Compile("buff"), CV.SharedIconStyle("externals")
Check(externals.borderEnabled == true and externals.borderThickness == 3 and externals.borderR == 1,
    "unset Externals did not compile the Buff border")
Check(externals.signature == buff.signature, "unset Externals compiled a look different from Buffs")
Check(Shape.SharedValue(shared, "externals") == "CIRCLE", "unset Externals did not take the Buff shape")
Check(CV.SharedIconStyle("trackedBuff") == CV.SharedIconStyle("buff"), "unknown kinds no longer resolve to Buffs")
shared.appearanceIconStyles.externals = { styleBorderThickness = 5 }
shared.appearanceIconShapes.externals = "RECTANGLE"
externals = Compile("externals")
Check(externals.borderThickness == 5, "a stored Externals value did not win over Buffs")
Check(externals.borderEnabled == true and externals.borderR == 1, "Externals lost the Buff values they do not store")
Check(CV.SharedIconStyle("buff").borderThickness == 3, "an Externals style changed Buffs")
Check(Shape.SharedValue(shared, "externals") == "RECTANGLE", "a stored Externals shape lost to Buffs")
-- A write that waits for its apply: the snapshot records Externals as unset.
shared = Profile()
A3._runtimeConfigGen = A3._runtimeConfigGen + 1
Skins.BeforeWrite("externals", nil)
Skins.BeforeWrite("externals", nil, true)
shared.appearanceIconStyles.externals = { styleBorderEnabled = true, styleBorderThickness = 7 }
shared.appearanceIconShapes.externals = "RECTANGLE"
externals = CV.SharedIconStyle("externals")
Check(Skins.frozen and externals.borderThickness == 3, "an Externals write showed before its apply")
Check(Shape.SharedValue(shared, "externals") == "CIRCLE", "an Externals shape write showed before its apply")
externals = Compile("externals")
Check(not Skins.frozen and externals.borderThickness == 7, "the apply did not show the Externals write")

-- 2. Classic and Forever --------------------------------------------------------------
namespace.Client = { IsClassic = true }
Load("Game/Classic/Auras/MSUF_Auras3_Visuals.lua")
local Classic = assert(A3.ClassicVisuals, "Classic visuals did not load")
local function GroupLane(kind)
    return Classic.EnrichGroupLane({ unit = "party1", size = 24, spacing = 1, rows = 1, padding = 0 }, {}, kind, nil, "party")
end
shared = Profile()
local lane = GroupLane("external")
Check(lane.iconStyle.borderEnabled and lane.iconStyle.borderThickness == 3 and lane.iconShape == "CIRCLE",
    "the Classic external lane did not follow the Buff Appearance")
shared.appearanceIconStyles.externals = { styleBorderThickness = 6 }
shared.appearanceIconShapes.externals = "RECTANGLE"
lane = GroupLane("external")
Check(lane.iconStyle.borderThickness == 6 and lane.iconShape == "RECTANGLE",
    "the Classic external lane ignored the Externals Appearance")
Check(lane.iconStyle.borderEnabled and lane.iconStyle.borderR == 1,
    "the Classic external lane lost the Buff values Externals do not store")
lane = GroupLane("trackedBuff")
Check(lane.iconStyle.borderThickness == 3 and lane.iconShape == "CIRCLE", "Classic tracked buffs left the Buff Appearance")
A3._runtimeConfigGen = A3._runtimeConfigGen + 1
shared.appearanceIconStyles.externals, shared.appearanceIconShapes.externals = nil, nil
Skins.BeforeWrite("externals", nil)
shared.appearanceIconStyles.externals = { styleBorderEnabled = true, styleBorderThickness = 8 }
lane = GroupLane("external")
Check(lane.iconStyle.borderThickness == 3, "a waiting Classic Externals write showed before its apply")
A3._runtimeConfigGen = A3._runtimeConfigGen + 1
lane = GroupLane("external")
Check(lane.iconStyle.borderThickness == 8, "the Classic external lane kept the snapshot after the apply")

-- 3. The menu model -------------------------------------------------------------------
namespace.Auras3MenuModelFactories = {}
Load("Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua")
local Model = { EnsureDB = A3.EnsureDB }
namespace.Auras3MenuModelFactories.Appearance(A3, Model, {}, {
    ClampNumber = deps.Platform.ClampNumber,
    Round = deps.Platform.Round,
}, {})
shared = Profile()
Check(Model.ReadSharedAppearanceBool("externals", "styleBorderEnabled", false) == true
    and Model.ReadSharedAppearanceNumber("externals", "styleBorderThickness", 1, 1, 8) == 3,
    "the menu did not show the Buff values for unset Externals")
Check(Model.ReadSharedAppearanceIconShape("externals") == "CIRCLE", "the menu did not show the Buff shape for Externals")
Check(Model.WriteSharedAppearanceNumber("externals", "styleBorderThickness", 6, 1, 8) == true,
    "an Externals write reported no change")
local own = shared.appearanceIconStyles.externals
local stored = 0
for _ in pairs(own or {}) do stored = stored + 1 end
Check(type(own) == "table" and own.styleBorderThickness == 6 and stored == 1
    and shared.appearanceIconShapes.externals == nil, "an Externals write stored more than the edited value")
Check(shared.appearanceIconStyles.buff.styleBorderThickness == 3, "an Externals write changed Buffs")
Check(Model.ReadSharedAppearanceBool("externals", "styleBorderEnabled", false) == true
    and Model.ReadSharedAppearanceValue("externals", "styleBorderColor", nil) == shared.appearanceIconStyles.buff.styleBorderColor,
    "Externals lost the Buff values they do not store")
Model.WriteSharedAppearanceNumber("buff", "styleBorderThickness", 2, 1, 8)
Model.WriteSharedAppearanceBool("buff", "styleBorderEnabled", false)
Check(Model.ReadSharedAppearanceNumber("externals", "styleBorderThickness", 1, 1, 8) == 6,
    "a Buff edit reached a value Externals store")
Check(Model.ReadSharedAppearanceBool("externals", "styleBorderEnabled", true) == false,
    "a Buff edit did not reach a value Externals follow")
shared = Profile()
Check(Model.WriteSharedAppearanceIconShape("externals", "RECTANGLE") == true
    and shared.appearanceIconShapes.externals == "RECTANGLE" and shared.appearanceIconStyles.externals == nil
    and Model.ReadSharedAppearanceIconShape("buff") == "CIRCLE",
    "an Externals shape write stored more than the shape or changed Buffs")
Check(Model.ReadSharedAppearanceBool("playerDefensives", "styleBorderEnabled", false) == false,
    "another Aura type started to follow Buffs")

-- 4. Wiring: the Retail group lane and the menu entry points name Externals. ------------
local function Source(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
Check(Source("MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_LaneConfig.lua")
    :find('kind == "external" and "externals"', 1, true) ~= nil,
    "the Retail external group lane does not compile the Externals Appearance")
Check(Source("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
    :find("externals=External Defensives", 1, true) ~= nil,
    "Aura Appearance does not offer External Defensives")
Check(Source("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua")
    :find('lane == "externals" and "externals"', 1, true) ~= nil,
    "the External Defensives workspace does not open their Appearance")

if failures > 0 then
    io.stderr:write(("aura_externals_appearance_smoke: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("aura_externals_appearance_smoke: runtime, Classic and menu fallback to Buffs and own Externals passed")
