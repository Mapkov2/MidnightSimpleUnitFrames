-- menu_page_reset_scope_smoke.lua <repoRoot> <flavor>
--
-- A page's "Reset to defaults" must restore what that page owns and nothing
-- else. Boots the real core and Options graph of one client (client_world.lua)
-- and calls the real M.ResetPageToDefaults.
--
-- 1. Reset Colors (C7-2): the colour-channel rule counted any key whose LAST
--    LETTER was r/g/b/a (case-insensitive) as a channel, so Reset Colors also
--    wiped fontSlug, fontTextAlpha, enable*Castbar, castbar icon spacing and
--    other non-colour settings, and the Castbar reset skipped the castbar ones.
--    Every general and gameplay default key plus every key a Colors-page
--    control writes is dirtied; after the reset, the touched set must equal the
--    pre-fix set minus exactly the NON_COLOUR inventory below, so no colour key
--    or colour channel leaves the Colors reset and only those keys do.
--
-- Plain Lua 5.1, repo root as arg 1 and the client flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_page_reset_scope_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end
local function Words(text)
    local list, set = {}, {}
    for word in text:gmatch("%S+") do list[#list + 1] = word; set[word] = true end
    return list, set
end

local world = World.New(root, flavor)
-- Harness gap only: every client defines MAX_BOSS_FRAMES = 5 in Blizzard_UnitFrame.
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local env, core = world.env, world.core
local M = Check(core.MSUF2, "Menu2 did not load")
local F = Check(core.ProfileFields, "ProfileFields did not load")
-- The queued runtime apply after a reset is outside this contract.
Check(M.ApplyService, "apply service missing").Flush = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end

-- The harness cannot decode the embedded factory string, so the booted profile
-- is the factory baseline every reset returns to.
local factory = Check(F.CopySnapshot(M.EnsureDB()), "booted profile is not snapshot-safe")
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
local function Restore()
    local live = M.EnsureDB()
    for key in pairs(live) do live[key] = nil end
    for key, value in pairs(F.CopySnapshot(factory)) do live[key] = value end
    return live
end
local function Reset(pageKey)
    local ok, result = pcall(M.ResetPageToDefaults, pageKey)
    Check(ok and result == true, "resetting " .. pageKey .. " failed: " .. tostring(result))
    return M.EnsureDB()
end
local SENTINEL = "__menu_page_reset_scope_smoke__"

---------------------------------------------------------------------------
-- 1. Reset Colors resets colours only (C7-2)
---------------------------------------------------------------------------
-- The general keys the pre-fix rule wrongly took for a colour channel, with the
-- page that owns each. None is a colour; Reset Colors must keep all of them.
local NON_COLOUR_LIST, NON_COLOUR = Words [[
    castbarPlayerIconSpacing castbarTargetIconSpacing castbarFocusIconSpacing
    enablePlayerCastbar enableTargetCastbar enableFocusCastbar enableBossCastbar enableArenaCastbar
    castbarSpellNameShortening focusKickShowCastbar
    dispelBorderTrigger useBarBorder
    fontSlug fontTextAlpha
    portraitFillBorder
    editModeBgAlpha
]]
-- Owners: unit pages (icon spacing, castbar on/off), Castbar page (spell-name
-- shortening, focus kick), Bars page (dispel trigger), Fonts page (font slug,
-- text alpha), the legacy bar-border switch, the portrait "fill border into
-- frame gap" toggle and the Edit Mode grid backdrop opacity.

-- Every general/gameplay key a Colors-page control writes on any client
-- (recorded by driving each control's real setter and diffing the profile).
local COLOUR_PAGE_WRITES = Words [[
    gameplay.combatStateColorSync gameplay.combatStateEnterColor gameplay.combatStateLeaveColor
    gameplay.combatTimerColor gameplay.crosshairInRangeColor gameplay.crosshairOutRangeColor
    general.aurasCooldownTextSafeColor general.aurasCooldownTextSafeSeconds general.aurasCooldownTextUrgentColor
    general.aurasCooldownTextUrgentSeconds general.aurasCooldownTextUseBuckets general.aurasCooldownTextWarningColor
    general.aurasCooldownTextWarningSeconds general.barBgColorMode general.barBgFillMode general.barBgMatchHPColor
    general.barMode general.barOutlineColorA general.barOutlineColorB general.barOutlineColorG
    general.barOutlineColorR general.bossTargetHighlightColor general.castbarBgA general.castbarBgB general.castbarBgG
    general.castbarBgR general.castbarBorderA general.castbarBorderB general.castbarBorderG general.castbarBorderR
    general.classBarBgB general.classBarBgG general.classBarBgR general.classPowerBgColorOverrides
    general.classPowerColorOverrides general.colorHealthTextByHealth general.colorPowerTextByType general.darkBarGray
    general.darkBarTone general.darkBgCustomColor general.darkMode general.dispelTypeColorOverrides
    general.enableHealthGradient general.gradientStrength general.healPredictionColorB general.healPredictionColorG
    general.healPredictionColorR general.healthBarGradientColorB general.healthBarGradientColorG
    general.healthBarGradientColorR general.healthGradientHighB general.healthGradientHighG
    general.healthGradientHighR general.healthGradientLowB general.healthGradientLowG general.healthGradientLowR
    general.healthGradientMidB general.healthGradientMidG general.healthGradientMidR general.healthLossColorB
    general.healthLossColorG general.healthLossColorR general.highlightColor general.hlPurgeColorB
    general.hlPurgeColorG general.hlPurgeColorR general.kickNotReadyColor general.kickReadyColor
    general.levelColorEasyB general.levelColorEasyG general.levelColorEasyR general.levelColorImpossibleB
    general.levelColorImpossibleG general.levelColorImpossibleR general.levelColorStandardB
    general.levelColorStandardG general.levelColorStandardR general.levelColorTrivialB general.levelColorTrivialG
    general.levelColorTrivialR general.levelColorVeryDifficultB general.levelColorVeryDifficultG
    general.levelColorVeryDifficultR general.nameClassColor general.nameColorB general.nameColorG
    general.nameColorMode general.nameColorR general.npcClassColorBar general.npcColorMode general.npcNameRed
    general.npcTypeBoss general.npcTypeColorBar general.npcTypeColorText general.npcTypeFocus general.npcTypeTarget
    general.npcTypeToT general.petFrameUsePlayerClassColor general.playerCastbarOverrideEnabled
    general.playerCastbarOverrideMode general.portraitBgColorB general.portraitBgColorG general.portraitBgColorR
    general.portraitBorderColorB general.portraitBorderColorG general.portraitBorderColorR
    general.powerBarBgMatchBarColor general.powerBarGradientColorB general.powerBarGradientColorG
    general.powerBarGradientColorR general.powerColorMode general.powerColorOverrides general.powerLossColorB
    general.powerLossColorG general.powerLossColorR general.purgeBorderColorB general.purgeBorderColorG
    general.purgeBorderColorR general.tapDeniedGray general.texLayer2ColorB general.texLayer2ColorG
    general.texLayer2ColorR general.texLayer2Gradient2B general.texLayer2Gradient2G general.texLayer2Gradient2R
    general.texLayer3ColorB general.texLayer3ColorG general.texLayer3ColorR general.texLayer3Gradient2B
    general.texLayer3Gradient2G general.texLayer3Gradient2R general.texLayerColorB general.texLayerColorG
    general.texLayerColorR general.texLayerGradient2B general.texLayerGradient2G general.texLayerGradient2R
    general.threatColorHighB general.threatColorHighG general.threatColorHighR general.threatColorLowB
    general.threatColorLowG general.threatColorLowR general.threatColorMidB general.threatColorMidG
    general.threatColorMidR general.unifiedBarB general.unifiedBarG general.unifiedBarR general.useClassColors
]]

-- The pre-fix rule, frozen here only to state "before": the touched set after
-- the fix must equal this set minus NON_COLOUR, nothing more and nothing less.
local _, PRE_FIX_KEYS = Words [[playerCastbarOverrideEnabled playerCastbarOverrideMode npcClassColorBar
    npcTypeTarget npcTypeFocus npcTypeBoss npcTypeToT]]
local _, PRE_FIX_LOWER = Words [[barmode darkmode darkbartone darkbgbrightness useclasscolors enablehealthgradient
    gradientstrength fontcolor highlightcolor usecustomfontcolor nameclasscolor npcnamered]]
local function PreFixColourKey(rootKey, key)
    if rootKey == "gameplay" and key == "combatStateColorSync" then return true end
    local lower = key:lower()
    if PRE_FIX_KEYS[key] or PRE_FIX_LOWER[lower] or lower:find("color", 1, true) then return true end
    local last = lower:sub(-1)
    if not (last == "r" or last == "g" or last == "b" or last == "a") then return false end
    for _, stem in ipairs({ "font", "bg", "border", "outline", "gradient", "castbar" }) do
        if lower:find(stem, 1, true) then return true end
    end
    return false
end

-- Inventory: every default key of both roots, every Colors-page write, every
-- NON_COLOUR key (some exist only once a control wrote them).
local inventory = { general = {}, gameplay = {} }
for rootKey, keys in pairs(inventory) do
    for key in pairs(type(factory[rootKey]) == "table" and factory[rootKey] or {}) do keys[key] = true end
end
for i = 1, #COLOUR_PAGE_WRITES do
    local rootKey, key = COLOUR_PAGE_WRITES[i]:match("^(%w+)%.(.+)$")
    inventory[rootKey][key] = true
end
for i = 1, #NON_COLOUR_LIST do inventory.general[NON_COLOUR_LIST[i]] = true end

local db = Restore()
for rootKey, keys in pairs(inventory) do
    db[rootKey] = type(db[rootKey]) == "table" and db[rootKey] or {}
    for key in pairs(keys) do db[rootKey][key] = SENTINEL end
end
db = Reset("opt_colors")
local wrong, colourReset, total = {}, 0, 0
for rootKey, keys in pairs(inventory) do
    for key in pairs(keys) do
        total = total + 1
        local touched = db[rootKey][key] ~= SENTINEL
        local expected = PreFixColourKey(rootKey, key) and not (rootKey == "general" and NON_COLOUR[key])
        if touched ~= expected then
            wrong[#wrong + 1] = rootKey .. "." .. key .. (touched and " (wiped)" or " (kept)")
        end
        if touched then colourReset = colourReset + 1 end
    end
end
table.sort(wrong)
-- A "(wiped)" entry is a non-colour setting the reset destroyed; a "(kept)"
-- entry is a colour key or channel (a Colors-page control's among them) that
-- left the Colors reset.
Check(#wrong == 0, "Reset Colors must reset exactly the colour keys; wrong: " .. table.concat(wrong, ", "))

-- The same rule kept castbar settings out of Reset Castbar, which resets every
-- castbar key by pattern (the backends beside these on/off switches included);
-- the castbar keys it freed now go back to factory with the rest.
local CASTBAR_FREED = Words [[castbarSpellNameShortening castbarPlayerIconSpacing castbarTargetIconSpacing
    castbarFocusIconSpacing enablePlayerCastbar enableTargetCastbar enableFocusCastbar enableBossCastbar enableArenaCastbar]]
db = Restore()
for i = 1, #CASTBAR_FREED do db.general[CASTBAR_FREED[i]] = SENTINEL end
db = Reset("opt_castbar")
for i = 1, #CASTBAR_FREED do
    local key = CASTBAR_FREED[i]
    Check(db.general[key] == factory.general[key], "Reset Castbar left general." .. key .. " at the user value")
end

print(string.format("menu_page_reset_scope_smoke: %s ok (Reset Colors: %d keys inventoried, %d colour keys reset,"
    .. " %d non-colour keys kept; Reset Castbar restores %d freed castbar keys)",
    flavor, total, colourReset, #NON_COLOUR_LIST, #CASTBAR_FREED))
