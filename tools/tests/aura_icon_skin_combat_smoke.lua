-- Aura icon skins look the same in and out of combat.
--
-- A skin is painted when a button is created, and Blizzard creates aura
-- buttons in combat too (a pool grows in batches of ten). So:
--   1. the painter draws a skin while InCombatLockdown() is true, with no
--      deferral, and the native initializeFrame stage reaches it unguarded;
--   2. a lane compiled before the next apply (a target or roster change
--      recompiles lanes) keeps the look the runtime last applied, on the
--      Retail compiler and the Classic one (IconSkins.CommittedSource): a
--      setting changed in combat, and a slider write whose delayed apply lands
--      in combat, wait for the apply at combat end. The menu writes through
--      the real model writer, which freezes the applied look before its first
--      change (IconSkins.BeforeWrite);
--   3. the apply at combat end shows the new setting everywhere, also to a
--      product first compiled in a later fight;
--   5. a profile switch, reset or import in combat (applied to auras at combat
--      end) leaves every lane compiled in that fight on the old profile's look,
--      also for products only the new profile styles;
--   4. with nothing frozen the snapshot copies nothing and allocates nothing.
-- Applies and combat edges follow the runtime: out of combat an apply bumps
-- A3._runtimeConfigGen; in combat the aura runtime or the menu's apply service
-- only queues it, and the queued apply bumps the generation at combat end. The
-- combat edges reach the snapshot through the MSUF event bus (a recording stub
-- here), subscribed only while something is frozen.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

local Region = {}
Region.__index = Region
local function Noop() end
for _, name in ipairs({ "SetTexture", "SetTexCoord", "SetDrawLayer", "ClearAllPoints", "SetPoint", "SetAllPoints",
    "SetSize", "SetWidth", "SetHeight", "SetBlendMode", "EnableMouse", "SetFrameLevel" }) do
    Region[name] = Noop
end
function Region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:GetFrameLevel() return 10 end
function Region:CreateTexture(_, layer, _, sublevel)
    local texture = setmetatable({ layer = layer, sublevel = sublevel }, Region)
    self.children = self.children or {}
    self.children[#self.children + 1] = texture
    return texture
end
_G.CreateFrame = function() return setmetatable({}, Region) end

-- The skin files bind MSUF_PixelLayoutRegion and the MSUF event bus through
-- MSUF.Require (Kernel/MSUF_Require.lua); this bus records its subscriptions.
local busHandlers = {}
-- Owners the Classic visuals and the lane config bind at load: the shipped functions, cut out
-- of their own files by the shared source slicer (no copy of their rules).
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local function Shipped(path, declaration, name)
    return assert(loadstring(Slice.Function(Slice.Read(root .. "/" .. path), declaration, path)
        .. "\nreturn " .. name, name))()
end
local PROVIDERS = {
    MSUF_PixelLayoutRegion = function(region) return region end,
    MSUF_EventBus_Register = function(event, key, fn)
        busHandlers[event] = busHandlers[event] or {}
        busHandlers[event][key] = fn
    end,
    MSUF_EventBus_Unregister = function(event, key)
        if busHandlers[event] then busHandlers[event][key] = nil end
    end,
    -- Runtime/MSUF_BorderStyles.lua binds the shared-media and file-asset owners at load.
    -- This harness has no LibSharedMedia and no file-asset API: no library, and a file
    -- the client cannot vouch for stays unknown (not invalid).
    MSUF_GetSharedMedia = function() return nil end,
    MSUF_IsKnownFileAsset = function() return nil end,
    -- The lane config and the Classic visuals bind these at load.
    MSUF_NormalizeAuraDebuffTypeBorderMode = Shipped("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
        "local function NormalizeDebuffTypeBorderMode", "NormalizeDebuffTypeBorderMode"),
    MSUF_GetGeneralDB = Shipped("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua", "local function GetGeneralDB", "GetGeneralDB"),
}
-- The shipped namespace API (ExportPublic with the keep policy, the registries); the strict
-- Require below replaces the shipped one so only the listed providers resolve.
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
local namespace = { MSUF_Auras3 = {} }
RequireFixture.InstallKernel(root, namespace)
function namespace.Require(name)
    return assert(PROVIDERS[name], "unexpected dependency " .. tostring(name))
end
local function Fire(event)
    for _, fn in pairs(busHandlers[event] or {}) do fn(event) end
end
local function Subscriptions()
    local count = 0
    for _, handlers in pairs(busHandlers) do
        for _ in pairs(handlers) do count = count + 1 end
    end
    return count
end
local function Load(path)
    return assert(loadfile(ADDON .. path))("MidnightSimpleUnitFrames", namespace)
end
Load("Runtime/MSUF_BorderStyles.lua")
Load("Auras3/MSUF_Auras3_IconShape.lua")
Load("Auras3/MSUF_Auras3_IconSkins.lua")
Load("Auras3/MSUF_Auras3_IconSkins_Catalog.lua")
local A3 = namespace.MSUF_Auras3

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local shared = { appearanceIconStyles = {
    buff = { styleSkin = "SHADOW1" },
    debuff = { styleSkin = "CUSTOM" },
} }
A3.EnsureDB = function() return { shared = shared }, shared end
A3._runtimeConfigGen = 1
-- The menu's writer: MenuModel/MSUF_Auras3_Menu_Appearance.lua.
Load("Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua")
local Model = { EnsureDB = A3.EnsureDB }
namespace.Auras3MenuModelFactories.Appearance(A3, Model, {}, {}, {})
-- The Icon Skins page's writer for the default skin and look (the engine's).
local function WriteDefault(key, value)
    Check(A3.IconSkins.WriteDefault(key, value) == true, "the engine did not write the default " .. key)
end
local function Write(kind, key, value)
    Check(Model.WriteSharedAppearanceValue(kind, key, value) == true, "the menu model did not write " .. key)
end

local function Clamp(value, fallback, low, high)
    return math.max(low, math.min(high, tonumber(value) or fallback))
end
A3.Runtime = { ConfigValues = {} }
-- ConfigValues binds NormalizeCandidateSpellIDs from the spell-indicator config owner at load
-- (the TOC initializes it first). The skin checks never normalize a spell list, so this
-- harness does not load that owner: a call is a harness error, not a silent answer.
A3.SpellIndicators = { NormalizeCandidateSpellIDs = function()
    error("fixture: the spell-indicator config owner is not loaded by this harness", 2)
end }
Load("Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua")
local native = namespace.Auras3RuntimeFactories.ConfigValues("MidnightSimpleUnitFrames", namespace, A3, {}, nil, {
    Appearance = { Shape = A3.IconShape, AURA_BORDER_OPTIONS = {} },
    Platform = {
        ClampNumber = Clamp,
        Clamp01 = function(value, fallback) return Clamp(value, fallback, 0, 1) end,
        Round = function(value) return math.floor(value + 0.5) end,
    },
    Schema = { DEFAULT_SHARED = { styleBorderColor = { 0, 0, 0, 1 }, styleShadowColor = { 0, 0, 0, 0.8 },
        styleBorderThickness = 1, styleShadowSize = 4 } },
    Signatures = {},
})
-- The Classic backend loads only on Classic-family clients.
namespace.Client = { IsClassic = true }
Load("Game/Classic/Auras/MSUF_Auras3_Visuals.lua")
local Classic = assert(A3.ClassicVisuals, "Classic visuals did not load")

local function Shapes(kind)
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    local lane = Classic.EnrichUnitLane({ unit = "player", size = 32, rows = 1, spacing = 0, padding = 0 }, {}, {}, shared, kind)
    return A3.IconShape.SharedValue(shared, kind), lane.iconShape
end

-- Retail caches its compile per runtime generation, so a Retail recompile
-- needs a generation bump; during combat one stands for an unrelated rebuild
-- (a tracked spell changing). Classic compiles every lane it enriches.
local function Compile(kind)
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    return native.SharedIconStyle(kind), Classic.SharedIconStyle(shared, "player", kind)
end
local function CompileClassic(kind)
    return Classic.SharedIconStyle(shared, "player", kind)
end
-- The menu's apply after a write, and the combat edges. PLAYER_REGEN_DISABLED
-- arrives before the lockdown starts; the queued apply runs after
-- PLAYER_REGEN_ENABLED.
local queued = false
local function Apply()
    if inCombat then queued = true else A3._runtimeConfigGen = A3._runtimeConfigGen + 1 end
end
local function StartCombat()
    Fire("PLAYER_REGEN_DISABLED")
    inCombat = true
end
local function EndCombat()
    inCombat = false
    Fire("PLAYER_REGEN_ENABLED")
    if queued then
        queued = false
        A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    end
end

-- Out of combat: both compilers see the profile.
local retail, classic = Compile("buff")
Check(retail.skin and retail.skin.id == "SHADOW1", "Retail did not compile the skin out of combat")
Check(classic.skin and classic.skin.id == "SHADOW1", "Classic did not compile the skin out of combat")
local before = retail.signature
shared.appearanceIconShapes = { buff = "RECTANGLE" }
local retailShape, classicShape = Shapes("buff")
Check(retailShape == "RECTANGLE" and classicShape == "RECTANGLE", "the shape did not compile out of combat")
-- Dots on Target has no appearance table yet: it compiles to the user's look.
local dotsRetail, dotsClassic = Compile("targetDots")
Check(dotsRetail.skin == nil and dotsClassic.skin == nil, "a product without an appearance table compiled a skin")

-- 4. Out of combat the snapshot is a reference: compiles allocate nothing.
collectgarbage("collect")
collectgarbage("stop")
local kbBefore = collectgarbage("count")
local skins = A3.IconSkins
for _ = 1, 2000 do
    skins.CommittedSource("buff", shared.appearanceIconStyles.buff)
    skins.CommittedShape("buff", shared.appearanceIconShapes.buff)
end
local grown = collectgarbage("count") - kbBefore
collectgarbage("restart")
Check(grown == 0, string.format("the out-of-combat snapshot allocated %.2f KB over 2000 compiles", grown))
Check(Subscriptions() == 0, "the snapshot subscribed to combat edges with nothing frozen")

-- 1. Painting in combat: a pool that grows mid-fight draws the skin at once.
StartCombat()
local button = setmetatable({}, Region)
A3.ApplyIconStylePreview(button, retail, 32, "RECTANGLE")
local shownSkin = 0
for _, child in ipairs(button.children or {}) do
    if child.layer == "ARTWORK" and child.sublevel == 6 and child.shown then shownSkin = shownSkin + 1 end
end
Check(shownSkin == 8, "a button created in combat did not get its skin (" .. shownSkin .. " band pieces)")

local function Source(path)
    local file = assert(io.open(ADDON .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local visuals = Source("Auras3/Runtime/MSUF_Auras3_Runtime_ButtonVisuals.lua")
local stage = visuals:match("local function ApplyIconStyleSkinned%(.-\nend")
Check(stage and stage:find("A3.ApplyIconStylePreview(", 1, true)
    and visuals:find("local function UseSkinnedIconStyle() PrepareStage.ApplyIconStyle = ApplyIconStyleSkinned end", 1, true)
    and visuals:find("Shape.OnSkinsLive(UseSkinnedIconStyle)", 1, true),
    "once a compile produced a skin, PrepareStage.ApplyIconStyle must paint through A3.ApplyIconStylePreview")
-- The live button is laid out at its lane's width and height (a wide portrait).
Check(stage:find("lane.buttonHeight or lane.size,", 1, true) and stage:find("lane.buttonWidth or lane.size)", 1, true),
    "the Retail skin stage must pass the button's width and height")
-- SetHideTooltipInCombat is a tooltip option, not a combat check.
Check(not visuals:find("[^%w_]InCombat%(") and not visuals:find("InCombatLockdown", 1, true),
    "initializeFrame visuals must not defer on combat")
local skins = Source("Auras3/MSUF_Auras3_IconSkins.lua")
local paint = skins:match("function Skins%.Paint%(.-\nend")
Check(paint and not paint:find("InCombat", 1, true), "Skins.Paint must not defer on combat")

-- 2. A setting changed in combat, then a lane recompiled in that combat.
Write("buff", "styleSkin", "DARK2")
WriteDefault("styleSkinColor", { 1, 0, 0, 1 })
Check(Subscriptions() == 2, "a frozen edit did not subscribe to both combat edges")
Apply()
retail, classic = Compile("buff")
Check(retail.skin.id == "SHADOW1" and retail.signature == before,
    "a lane compiled in combat picked up a setting changed in that combat (Retail)")
Check(classic.skin.id == "SHADOW1" and classic.skin.r == 0,
    "a lane compiled in combat picked up a setting changed in that combat (Classic)")
-- Selecting a round skin writes the icon shape too; a lane compiled in the
-- same combat keeps the pre-combat shape, like the skin.
Check(Model.WriteSharedAppearanceIconShape("buff", "CIRCLE") == true, "the menu model did not write the shape")
Apply()
retailShape, classicShape = Shapes("buff")
Check(retailShape == "RECTANGLE", "a shape set in combat reached a lane compiled in that combat (Retail)")
Check(classicShape == "RECTANGLE", "a shape set in combat reached a lane compiled in that combat (Classic)")
-- The menu creates a missing appearance table on its first write; a lane
-- compiled in the same combat must still see "no table" (the user's look).
Write("targetDots", "styleSkin", "DARK1")
Apply()
dotsRetail, dotsClassic = Compile("targetDots")
Check(dotsRetail.skin == nil, "a table created in combat reached a lane compiled in that combat (Retail)")
Check(dotsClassic.skin == nil, "a table created in combat reached a lane compiled in that combat (Classic)")

-- 3. Combat ends: the deferred apply recompiles every lane with the new look.
EndCombat()
retail, classic = Compile("buff")
Check(retail.skin.id == "DARK2" and retail.skin.r == 1, "the new skin did not apply after combat (Retail)")
Check(classic.skin.id == "DARK2" and classic.skin.r == 1, "the new skin did not apply after combat (Classic)")
retailShape, classicShape = Shapes("buff")
Check(retailShape == "CIRCLE" and classicShape == "CIRCLE", "the shape set in combat did not apply after combat")
dotsRetail, dotsClassic = Compile("targetDots")
Check(dotsRetail.skin and dotsRetail.skin.id == "DARK1", "the table created in combat did not apply after combat (Retail)")
Check(dotsClassic.skin and dotsClassic.skin.id == "DARK1", "the table created in combat did not apply after combat (Classic)")
Check(Subscriptions() == 0, "the combat-edge subscription outlived the thaw")

-- A product frozen in one fight whose apply at combat end compiled nothing
-- (no lane showed it) shows its new look when a later fight first compiles it.
StartCombat()
Write("debuff", "styleSkin", "DARK3")
Apply()
Check(CompileClassic("debuff").skin == nil, "a skin set in combat reached a lane compiled in that combat (debuff)")
EndCombat()
StartCombat()
local laterFight = CompileClassic("debuff")
Check(laterFight.skin and laterFight.skin.id == "DARK3", "a product stayed frozen into the next fight (Classic)")
Check(Compile("debuff").skin.id == "DARK3", "a product stayed frozen into the next fight (Retail)")
EndCombat()
Write("debuff", "styleSkin", "CUSTOM")
Apply()

-- A slider writes at once and applies after a short delay. Combat that starts
-- in between keeps the applied look until the apply lands at combat end: the
-- lanes compiled before, during and after the delayed apply all agree.
WriteDefault("styleSkinColor", { 1, 0, 0, 0.35 })
Check(CompileClassic("buff").skin.a == 1, "a lane compiled before the slider's apply took the unapplied alpha")
StartCombat()
Check(CompileClassic("buff").skin.a == 1, "combat started before the slider's apply: a new lane took the unapplied alpha")
Apply()
retail, classic = Compile("buff")
Check(retail.skin.a == 1 and classic.skin.a == 1, "the slider's apply queued in combat reached a lane compiled in that combat")
EndCombat()
retail, classic = Compile("buff")
Check(retail.skin.a == 0.35 and classic.skin.a == 0.35, "the slider's alpha did not apply after combat")

-- The event-derived helper wins when the core provides it (combat edge: the
-- lockdown starts after PLAYER_REGEN_DISABLED).
namespace.Util = { InCombat = function() return true end }
Write("buff", "styleSkin", "SHADOW4")
retail = Compile("buff")
Check(retail.skin.id == "DARK2", "MSUF.Util.InCombat was not honoured at the combat edge")
namespace.Util = nil
EndCombat()
Check(Compile("buff").skin.id == "SHADOW4", "the write at the combat edge did not apply after combat")

-- The menu's apply service queues a combat apply without any runtime flag, and
-- a generation bump in the same fight (a profile switch, a tracked spell
-- rebuild; Compile bumps it here) must not show the queued edit.
StartCombat()
Write("buff", "styleSkin", "DARK4")
Apply()
retail, classic = Compile("buff")
Check(retail.skin.id == "SHADOW4" and classic.skin.id == "SHADOW4",
    "a generation bump during combat showed an edit whose apply still waits")
EndCombat()
retail, classic = Compile("buff")
Check(retail.skin.id == "DARK4" and classic.skin.id == "DARK4", "the queued edit did not apply after combat")

-- An edit applied out of combat while no lane compiled it thaws at combat
-- start, so a lane first compiled in the fight shows it.
Write("debuff", "styleSkin", "DARK5")
Apply()
StartCombat()
Check(CompileClassic("debuff").skin.id == "DARK5", "an edit applied before combat stayed frozen into the fight")
EndCombat()
Write("debuff", "styleSkin", "CUSTOM")
Apply()

-- 5. A profile change in combat. Profile storage replaces the profile at once
-- and auras apply it at combat end (State/MSUF_ProfileRuntime.lua); right before
-- the change it freezes the current icon look. Out of combat nothing freezes
-- (the compile first thaws the edit applied above).
Compile("debuff")
A3.IconSkins.FreezeProfile()
Check(Subscriptions() == 0, "a profile change out of combat froze the icon look")
local oldProfile = shared
StartCombat()
Write("buff", "styleSkinColor", { 0, 1, 0, 1 })
A3.IconSkins.FreezeProfile()
shared = {
    appearanceIconStyles = { buff = { styleSkin = "RING" }, playerDefensives = { styleSkin = "DARK1" },
        debuff = { styleSkin = "CUSTOM" } },
    appearanceIconShapes = { buff = "ROUNDED", playerDefensives = "CIRCLE" },
}
Apply()
retail, classic = Compile("buff")
Check(retail.skin.id == "DARK4" and classic.skin.id == "DARK4" and classic.skin.g == 0,
    "a lane compiled after a profile change in combat took the new profile's skin")
retailShape, classicShape = Shapes("buff")
Check(retailShape == oldProfile.appearanceIconShapes.buff and classicShape == retailShape,
    "a lane compiled after a profile change in combat took the new profile's icon shape")
retail, classic = Compile("playerDefensives")
Check(retail.skin == nil and classic.skin == nil, "a product only the new profile styles took its skin in combat")
retailShape = Shapes("playerDefensives")
Check(retailShape == "FOLLOW_PORTRAIT", "a product only the new profile shapes took its shape in combat")
-- The menu edits the new profile meanwhile; that waits too.
Write("buff", "styleSkin", "SHADOW2")
Apply()
Check(Compile("buff").skin.id == "DARK4", "a menu edit after a profile change in combat reached a lane in that combat")
EndCombat()
retail, classic = Compile("buff")
Check(retail.skin.id == "SHADOW2" and classic.skin.id == "SHADOW2", "the new profile did not apply after combat")
Check(Compile("playerDefensives").skin.id == "DARK1", "the new profile's product did not apply after combat")
Check(Shapes("buff") == "ROUNDED", "the new profile's icon shape did not apply after combat")
Check(Subscriptions() == 0, "the profile freeze outlived combat")
shared = oldProfile
Apply()
local profileRuntime = Source("State/MSUF_ProfileRuntime.lua"):gsub("\r\n", "\n")
local mutation = profileRuntime:match("local function MSUF_ProfileIO_BeforeActiveProfileMutation%(.-\nend")
Check(mutation and mutation:find("auras.IconSkins.FreezeProfile()", 1, true)
    and mutation:find("FreezeProfile", 1, true) < mutation:find("BumpRuntimeConfig", 1, true),
    "profile storage must freeze the icon look before it changes the active profile")

-- Like default: an aura type that follows the default skin keeps the default
-- the runtime last applied when the Icon Skins page changes it in combat, and
-- takes the new default after combat.
Write("targetDots", "styleSkin", "DEFAULT")
WriteDefault("styleSkin", "GLASS")
Apply()
retail, classic = Compile("targetDots")
Check(retail.skin.id == "GLASS" and classic.skin.id == "GLASS", "an aura type did not follow the default skin")
StartCombat()
WriteDefault("styleSkin", "PIXEL")
Apply()
retail, classic = Compile("targetDots")
Check(retail.skin.id == "GLASS" and classic.skin.id == "GLASS",
    "a default skin changed in combat reached a lane compiled in that combat")
EndCombat()
retail, classic = Compile("targetDots")
Check(retail.skin.id == "PIXEL" and classic.skin.id == "PIXEL", "the new default skin did not apply after combat")
WriteDefault("styleSkin", "CUSTOM")
Apply()
Check(CompileClassic("targetDots").skin == nil and CompileClassic("buff").skin.id == "DARK4",
    "No skin as the default changed an aura type that names its own skin")
-- A profile change in combat also keeps the default skin the runtime last
-- applied (IconSkins.FreezeProfile freezes it with the products).
WriteDefault("styleSkin", "GLASS")
Apply()
local applied = shared
StartCombat()
A3.IconSkins.FreezeProfile()
shared = { appearanceIconStyles = { targetDots = { styleSkin = "DEFAULT" } }, iconSkinDefault = { styleSkin = "PIXEL" } }
Apply()
retail, classic = Compile("targetDots")
Check(retail.skin and retail.skin.id == "GLASS" and classic.skin and classic.skin.id == "GLASS",
    "a lane compiled after a profile change in combat took the new profile's default skin")
EndCombat()
retail, classic = Compile("targetDots")
Check(retail.skin.id == "PIXEL" and classic.skin.id == "PIXEL", "the new profile's default skin did not apply after combat")
shared = applied
WriteDefault("styleSkin", "CUSTOM")
Apply()


-- The model writers are the only places that change an appearance table in
-- place or set an icon shape. Defaults run at load; the page reset, undo and
-- redo are blocked in combat (M.BlockCombatAction).
local SHAPE_WRITERS = {
    ["MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua"] = true,
    ["MidnightSimpleUnitFrames/State/MSUF_Defaults.lua"] = true,
    ["MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings_Reset.lua"] = true,
}
local writers = {}
for _, path in ipairs({ "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options" }) do
    local list = io.popen('git -C "' .. root .. '" ls-files "' .. path .. '/*.lua"')
    for file in list:lines() do
        local handle = assert(io.open(root .. "/" .. file, "rb"))
        local text = handle:read("*a")
        handle:close()
        if text:find("appearanceIconStyles%[[^%]]+%]%s*%[") or text:find("appearanceIconStyles%.[%w_]+%.[%w_]+%s*=")
            or (text:find("iconSkinDefault%[") or text:find("iconSkinDefault%.[%w_]+%s*="))
            and not SHAPE_WRITERS[file]
            or text:find("appearanceIconStyles%[[^%]]+%]%.[%w_]+%s*=")
            or (text:find("appearanceIconShapes%[[^%]]+%]%s*=") or text:find("appearanceIconShapes%.[%w_]+%s*="))
            and not SHAPE_WRITERS[file] then
            writers[#writers + 1] = file
        end
    end
    list:close()
end
Check(#writers == 0, "an appearance table is changed in place outside the model writer: " .. table.concat(writers, ", "))
local defaultWriter = Source("Auras3/MSUF_Auras3_IconSkins.lua"):match("function Skins%.WriteDefault%(.-\nend")
Check(defaultWriter and defaultWriter:find("Skins.BeforeWrite(DEFAULT_KIND, defaults)", 1, true)
    and defaultWriter:find("BeforeWrite", 1, true) < defaultWriter:find("defaults[key] = value", 1, true),
    "Skins.WriteDefault must freeze the combat look before it writes")
local writer = Source("Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua")
    :match("function Model%.WriteSharedAppearanceValue%(.-\n    end")
Check(writer and writer:find("A3.IconSkins.BeforeWrite(kind, style)", 1, true)
    and writer:find("BeforeWrite", 1, true) < writer:find("style[key] = value", 1, true),
    "Model.WriteSharedAppearanceValue must freeze the combat look before it writes")
local shapeWriter = Source("Auras3/MenuModel/MSUF_Auras3_Menu_Appearance.lua")
    :match("function Model%.WriteSharedAppearanceIconShape%(.-\n    end")
Check(shapeWriter and shapeWriter:find("A3.IconSkins.BeforeWrite(kind, shared.appearanceIconShapes[kind], true)", 1, true)
    and shapeWriter:find("BeforeWrite", 1, true) < shapeWriter:find("appearanceIconShapes[kind] = value", 1, true),
    "Model.WriteSharedAppearanceIconShape must freeze the combat shape before it writes")

-- CUSTOM profiles are untouched in and out of combat.
local custom = Compile("debuff")
Check(custom.skin == nil and not custom.signature:find(":K:", 1, true), "CUSTOM gained a skin signature")

print("aura_icon_skin_combat_smoke: OK (in-combat paint, combat snapshot on Retail and Classic through the menu writer,"
    .. " post-combat apply, profile change in combat, allocation-free snapshot)")
