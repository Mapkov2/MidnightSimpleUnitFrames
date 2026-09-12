local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 binding layer: page resets.
-- Owns the per-page "Reset to defaults" key tables, the reset handlers, the
-- runtime cache purge and apply fanout that follow a reset, and the confirm
-- popup. Split from MSUF_Menu2_Bindings.lua: it loads right after the History
-- sibling, picks the shared aliases from M and publishes the same M.* names
-- (M.PageHasReset, M.BuildPageResetWarning, M.ResetPageToDefaults,
-- M.ShowPageResetConfirm), so pages and the Assistant keep calling them.
-- The Assistant calls M.ResetPageToDefaults from the main addon, which can run
-- before the LoadOnDemand Options addon has installed M.Format (Theme.lua).
local Fmt = M.Format
local KS, KSW, WL = M.KeySet, M.KeySetFromWords, M.WordList
local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
if type(ApplyService) ~= "table" then error("MSUF Menu2 ApplyService missing") end


local DeepCopy = M.DeepCopy
local QueueMenuRefresh = M.QueueMenuRefresh
local COLOR_CLASSPOWER_RUNTIME, ApplyScopedFeatureRuntime, FlushApplyServiceNow =
    M.COLOR_CLASSPOWER_RUNTIME, M.ApplyScopedFeatureRuntime, M.FlushApplyServiceNow
local UNIT_PAGE_RESETS = { uf_player = { unit = "player", label = "Player" }, uf_target = { unit = "target", label = "Target" }, uf_targettarget = { unit = "targettarget", label = "Target of Target" }, uf_focustarget = { unit = "focustarget", label = "Focus Target" }, uf_focus = { unit = "focus", label = "Focus" }, uf_boss = { unit = "boss", label = "Boss Frames" }, uf_pet = { unit = "pet", label = "Pet" } }
local CASTBAR_SUFFIX_KEYS = WL "TimeFormat FrameLevelOffset IconPosition IconSize IconOffsetX IconOffsetY IconSpacing IconBorderThickness IconBorderStyle IconFrameLevelOffset SpellNamePosition SpellNameFontSize TextOffsetX TextOffsetY SpellNameMaxWidth SpellNameTruncate TimePosition TimeFontSize TimeOffsetX TimeOffsetY SpellNameColorR SpellNameColorG SpellNameColorB TimeColorR TimeColorG TimeColorB"
local CASTBAR_TARGET_NAME_SUFFIX_KEYS = WL "TargetNamePosition TargetNameFontSize TargetNameAlign TargetNameOffsetX TargetNameOffsetY TargetNameColorR TargetNameColorG TargetNameColorB"
local function BuildUnitCastbarResetKeys(spec)
    local keys = { spec.enable, spec.backend .. "Backend", spec.backend .. "BackendBeforeHide", spec.time, spec.icon, spec.name }
    if spec.targetName then
        keys[#keys + 1] = spec.targetName
        for i = 1, #CASTBAR_TARGET_NAME_SUFFIX_KEYS do keys[#keys + 1] = spec.base .. CASTBAR_TARGET_NAME_SUFFIX_KEYS[i] end
    end
    for i = 1, #CASTBAR_SUFFIX_KEYS do keys[#keys + 1] = spec.base .. CASTBAR_SUFFIX_KEYS[i] end
    return keys
end
local UNIT_CASTBAR_GENERAL_KEYS = {
    player = BuildUnitCastbarResetKeys({ base = "castbarPlayer", backend = "castbarPlayer", enable = "enablePlayerCastbar", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", name = "castbarPlayerShowSpellName" }),
    target = BuildUnitCastbarResetKeys({ base = "castbarTarget", backend = "castbarTarget", enable = "enableTargetCastbar", time = "showTargetCastTime", icon = "castbarTargetShowIcon", name = "castbarTargetShowSpellName", targetName = "castbarTargetShowTargetName" }),
    focus = BuildUnitCastbarResetKeys({ base = "castbarFocus", backend = "castbarFocus", enable = "enableFocusCastbar", time = "showFocusCastTime", icon = "castbarFocusShowIcon", name = "castbarFocusShowSpellName", targetName = "castbarFocusShowTargetName" }),
    boss = BuildUnitCastbarResetKeys({ base = "bossCast", backend = "bossCastbar", enable = "enableBossCastbar", time = "showBossCastTime", icon = "showBossCastIcon", name = "showBossCastName", targetName = "showBossCastTargetName" }),
}
local function ResetInfo(label, kind, summary)
    return { label = label, kind = kind, summary = summary }
end
local GROUP_RESET_INFO = ResetInfo("Group Frames", "group", "Party, Raid, Mythic Raid, and Priority Frame layout, bars, auras, indicators, scope overrides and positions; character-specific Priority pins are retained")
local PAGE_RESET_INFO = {
    gf_layout = GROUP_RESET_INFO,
    gf_bars = GROUP_RESET_INFO,
    gf_auras = GROUP_RESET_INFO,
    gf_indicators = GROUP_RESET_INFO,
    gf_priority = GROUP_RESET_INFO,
    opt_bars = ResetInfo("Bars", "bars", "shared bar textures, gradients, rounded frame corners, absorb display, outlines, highlight borders, power smoothing and all per-unit/group bar overrides"),
    opt_fonts = ResetInfo("Fonts", "fonts", "shared font family, text style, name/power text coloring, name shortening and all per-unit/group font overrides"),
    auras3_buffs = { label = "Buff Appearance", kind = "auraAppearance", appearanceKind = "buff", summary = "global Buff icon shape, border and shadow appearance" },
    auras3_debuffs = { label = "Debuff Appearance", kind = "auraAppearance", appearanceKind = "debuff", summary = "global Debuff icon shape, border and shadow appearance" },
    auras3_styling = ResetInfo("Aura Appearance", "auraAppearance", "the currently selected global Aura product appearance only"),
    opt_castbar = ResetInfo("Castbar", "castbar", "global castbar behavior, textures, boss castbar and interrupt indicator settings"),
    opt_colors = ResetInfo("Colors", "colors", "frame colors, group-frame colors, class/NPC colors, power colors, castbar colors, aura colors and gameplay color settings"),
    opt_misc = ResetInfo("Miscellaneous", "misc", "language/menu behavior, update pacing, tooltips, Blizzard-frame handling, minimap icon, sounds and range-fade settings"),
    classpower = ResetInfo("Class Resources", "classpower", "class-resource layout, behavior, style, auto-hide, detached power bar and alternative mana settings"),
    gameplay = ResetInfo("Gameplay", "gameplay", "gameplay enhancement settings such as combat text, crosshair and click-cast behavior"),
    modules = ResetInfo("Modules", "modules", "optional style/module settings such as MSUF Style and dropdown style"),
    profiles = ResetInfo("Profiles", "profile", "the entire active profile"),
}
for pageKey, info in pairs(UNIT_PAGE_RESETS) do
    PAGE_RESET_INFO[pageKey] = {
        label = info.label,
        kind = "unit",
        unit = info.unit,
        summaryFormat = "%s unit-frame settings, including layout, text, portrait, power, status icons, transparency, load conditions and this unit's castbar toggles",
    }
end
local BARS_GENERAL_KEYS = KSW [[
    barTexture barBackgroundTexture enableGradient enablePowerGradient gradientStrength gradientDirection
    gradientDirRight gradientDirLeft gradientDirUp gradientDirDown showSelfHealPrediction healPredEnabled healPredAnchorMode
    healPredictionBarHeight healPredictionBarOffsetY healPredictionBarOpacity healPredictionBarTexture
    enableAbsorbBar absorbTextMode absorbAnchorMode absorbBarHeight absorbBarOffsetY absorbBarOpacity
    healAbsorbEnabled healAbsorbAnchorMode healAbsorbBarHeight healAbsorbBarOffsetY healAbsorbBarOpacity
    overAbsorbOverlay fullHealthAbsorbStripe absorbBarTexture healAbsorbBarTexture dispelBorderTrigger dispelBorderShowOn bossTargetOutlineMode
    bossTargetHighlightEnabled hlPrioEnabled hlPrioOrder highlightPrioEnabled highlightPrioOrder roundedFramesEnabled roundedUnitFrames
    roundedGroupFrames roundedPowerBars roundedCastbars roundedClassResources roundedMouseover barOutlineColorR barOutlineColorG
    barOutlineColorB barOutlineColorA healthLossColorR healthLossColorG healthLossColorB powerLossColorR powerLossColorG powerLossColorB
]]
local BARS_SCOPE_KEYS = KSW [[
    hlOverride hpPowerTextOverride barTexture barBackgroundTexture barBgTexture enableAbsorbBar absorbTextMode absorbAnchorMode
    absorbBarHeight absorbBarOffsetY healAbsorbEnabled healAbsorbAnchorMode healAbsorbBarHeight healAbsorbBarOffsetY
    healPredEnabled healPredAnchorMode healPredictionBarHeight healPredictionBarOffsetY healPredictionBarOpacity healPredictionBarTexture
    overAbsorbOverlay fullHealthAbsorbStripe absorbBarOpacity healAbsorbBarOpacity barOutlineThickness barOutlineLayer barOutlineStrata barOutlineTexture highlightBorderThickness hlAggroSize
    aggroOutlineMode dispelOutlineMode dispelBorderTrigger dispelBorderShowOn
    purgeOutlineMode hlPrioEnabled hlPrioOrder enableGradient enablePowerGradient gradientStrength
    gradientDirection gradientDirRight gradientDirLeft gradientDirUp gradientDirDown powerSmoothFill powerChunkedFill
    barOutlineColorR barOutlineColorG barOutlineColorB barOutlineColorA
]]
local BARS_TABLE_KEYS = KSW [[
    barOutlineThickness barOutlineLayer barOutlineStrata barOutlineTexture smoothPowerBar chunkedPowerBar realtimePowerText roundedFramesEnabled roundedUnitFrames
    roundedGroupFrames roundedPowerBars roundedCastbars roundedClassResources roundedMouseover
]]
local FONT_GENERAL_KEYS = KSW "fontKey boldText noOutline textBackdrop fontMonochrome fontSlug fontShadowStrength fontShadowOpacity fontShadowDistance fontTextAlpha fontBaselineOffset nameClassColor npcNameRed nameNpcClassColor colorPowerTextByType colorHealthTextByHealth nameColorMode nameColorR nameColorG nameColorB"
local FONT_SCOPE_KEYS = KSW [[
    fontOverride fontKey boldText noOutline textBackdrop fontMonochrome fontSlug fontShadowStrength fontShadowOpacity fontShadowDistance fontTextAlpha fontBaselineOffset nameClassColor npcNameRed nameNpcClassColor colorPowerTextByType colorHealthTextByHealth
    fontOutline useGlobalFontColor fontR fontG fontB nameColorMode nameColorR nameColorG nameColorB nameShortenEnabled nameClipSide
    nameMaxChars nameNoEllipsis shortenNames shortenNameClipSide shortenNameMaxChars shortenNameShowDots
]]
local FONT_ROOT_KEYS = KS("shortenNames", "shortenNameClipSide", "shortenNameMaxChars", "shortenNameShowDots")
local UNIT_AND_GROUP_RESET_KEYS = WL [[player target targettarget focustarget focus pet boss gf_party gf_raid gf_mythicraid]]
local MISC_GENERAL_KEYS = KSW [[
    menuLocale slashMenuSnapEnabled hideAdvancedMenu showWelcomeMessage versionCheckEnabled disableUnitInfoTooltips
    unitInfoTooltipStyle unitTooltipProvider unitTooltipAnchor unitTooltipMode unitTooltipModifier tooltipShowAuraSpellIDs
    showMinimapIcon showNavigationIcons previewDragHintAnimationEnabled playTargetSelectLostSounds ellesmereEditModeIntegration
    nsrtNicknameIntegration
    highlightEnabled highlightStyle highlightThickness
]]
local MISC_UNIT_KEYS = {}
local MISC_UNIT_RESET_KEYS = WL [[target focus boss]]
local CASTBAR_GENERAL_KEYS = KSW [[
    empowerColorStages enableFocusKickIcon focusKickShowCastbar focusKickIconWidth focusKickIconHeight focusKickTextSize
    focusKickIconOffsetX focusKickIconOffsetY kickReadyShowTarget kickReadyShowFocus kickReadyShowBoss
    kickReadyStyle kickReadySize kickReadyAutoSize kickReadyAnchor kickReadyOffsetX kickReadyOffsetY
]]
local MODULES_GENERAL_KEYS = KS("styleEnabled")
local COLOR_GENERAL_KEYS = KSW "playerCastbarOverrideEnabled playerCastbarOverrideMode npcClassColorBar npcTypeTarget npcTypeFocus npcTypeBoss npcTypeToT"
local COLOR_GAMEPLAY_KEYS = KS("combatStateColorSync")
local COLOR_BARS_KEYS = KS("classPowerComboPointColorMode", "classPowerSlotColorModes", "classPowerFullColorEnabled")
local GROUP_COLOR_KEYS = KSW [[
    gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB
    gfUnifiedR gfUnifiedG gfUnifiedB barTexture barBgTexture bgR bgG bgB hpBarAlpha hpBgAlpha
    tempMaxHealthColorR tempMaxHealthColorG tempMaxHealthColorB
    alphaExcludeTextPortrait alphaExcludePredictionBars deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA
    debuffStripeAlpha debuffStripeColorR debuffStripeColorG debuffStripeColorB targetR targetG targetB
    hlFocusColorR hlFocusColorG hlFocusColorB groupBorderR groupBorderG groupBorderB groupBorderA
    ciAggroColorR ciAggroColorG ciAggroColorB
]]
local function StartsWith(value, prefix)
    return type(value) == "string" and type(prefix) == "string" and value:sub(1, #prefix) == prefix
end
local function ResetTableToDefaults(dst, src)
    if type(dst) ~= "table" then return end
    for key in pairs(dst) do
        dst[key] = nil
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        dst[key] = DeepCopy(value)
    end
end
local function ReplaceRootTable(db, defaults, key)
    if type(db) ~= "table" then return end
    db[key] = db[key] or {}
    ResetTableToDefaults(db[key], type(defaults) == "table" and defaults[key] or nil)
end
local function ResetKeySet(dst, src, keys)
    if type(dst) ~= "table" or type(keys) ~= "table" then return end
    for key in pairs(keys) do
        if type(src) == "table" and src[key] ~= nil then
            dst[key] = DeepCopy(src[key])
        else
            dst[key] = nil
        end
    end
end
local function ResetFilteredKeys(dst, src, filter)
    if type(dst) ~= "table" or type(filter) ~= "function" then return end
    for key in pairs(dst) do
        if filter(key) then dst[key] = nil end
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        if filter(key) then dst[key] = DeepCopy(value) end
    end
end
local function ResetRootFiltered(db, defaults, rootKey, filter)
    if type(db) ~= "table" then return end
    db[rootKey] = db[rootKey] or {}
    ResetFilteredKeys(db[rootKey], type(defaults) == "table" and defaults[rootKey] or nil, filter)
end
local function ResetUnitFiltered(db, defaults, unit, filter)
    if type(db) ~= "table" or type(unit) ~= "string" then return end
    db[unit] = db[unit] or {}
    ResetFilteredKeys(db[unit], type(defaults) == "table" and defaults[unit] or nil, filter)
end
local function RetireLegacyUnitAliases(db)
    if type(db) ~= "table" then return end
    db.tot = nil
    db.targetoftarget = nil
    db.target_of_target = nil
    db.focus_target = nil
    db.focustargettarget = nil
end
local function IsColorKey(key)
    if type(key) ~= "string" then return false end
    if COLOR_GENERAL_KEYS[key] == true then return true end
    local lower = string.lower(key)
    if lower:find("color", 1, true) then return true end
    if lower == "barmode" or lower == "darkmode" or lower == "darkbartone" or lower == "darkbgbrightness" then return true end
    if lower == "useclasscolors" or lower == "enablehealthgradient" or lower == "gradientstrength" then return true end
    if lower == "fontcolor" or lower == "highlightcolor" or lower == "usecustomfontcolor" then return true end
    if lower == "nameclasscolor" or lower == "npcnamered" then return true end
    local last = lower:sub(-1)
    if last == "r" or last == "g" or last == "b" or last == "a" then
        if lower:find("color", 1, true)
            or lower:find("font", 1, true)
            or lower:find("bg", 1, true)
            or lower:find("border", 1, true)
            or lower:find("outline", 1, true)
            or lower:find("gradient", 1, true)
            or lower:find("castbar", 1, true)
        then
            return true
        end
        if lower == "fontcolorcustomr" or lower == "fontcolorcustomg" or lower == "fontcolorcustomb" then return true end
    end
    return false
end
local function IsCastbarKey(key)
    if type(key) ~= "string" then return false end
    if CASTBAR_GENERAL_KEYS[key] == true then return true end
    local lower = string.lower(key)
    if lower:find("castbar", 1, true) then return true end
    if lower:find("bosscast", 1, true) then return true end
    if lower:find("empower", 1, true) then return true end
    if lower == "enableplayercastbar" or lower == "enabletargetcastbar" or lower == "enablefocuscastbar" then return true end
    if lower:find("spellnamefontsize", 1, true) or lower:find("timefontsize", 1, true) then return true end
    return false
end
local function IsClassPowerBarsKey(key)
    if type(key) ~= "string" then return false end
    return StartsWith(key, "classPower")
        or StartsWith(key, "detachedPowerBar")
        or StartsWith(key, "altMana")
        or key == "showClassPower"
        or key == "showChargedComboPoints"
        or key == "runeShowTime"
        or key == "showEleMaelstrom"
        or key == "showEbonMight"
        or key == "showShadowMana"
        or key == "showAltMana"
        or key == "classPowerComboPointColorMode"
end
local function FactoryDefaults()
    local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
    if type(create) ~= "function" then return nil end
    local defaults = create()
    if type(defaults) == "table" then return defaults end
    return nil
end
local function ResetUnitPage(db, defaults, unit)
    ReplaceRootTable(db, defaults, unit)
    RetireLegacyUnitAliases(db)
    local castbarKeys = UNIT_CASTBAR_GENERAL_KEYS[unit]
    if castbarKeys then
        db.general = db.general or {}
        local src = type(defaults) == "table" and defaults.general or nil
        for i = 1, #castbarKeys do
            local key = castbarKeys[i]
            db.general[key] = type(src) == "table" and DeepCopy(src[key]) or nil
        end
    end
end
local function ResetGroupFrames(db, defaults)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.ResetAllToDefaults) == "function" then
        local result = gf.ResetAllToDefaults()
        return result
    end
    ReplaceRootTable(db, defaults, "gf_party")
    ReplaceRootTable(db, defaults, "gf_raid")
    ReplaceRootTable(db, defaults, "gf_mythicraid")
    ReplaceRootTable(db, defaults, "gf_priority")
    return true
end
local function ResetBarsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return BARS_GENERAL_KEYS[key] == true or BARS_SCOPE_KEYS[key] == true end)
    ResetRootFiltered(db, defaults, "bars", function(key) return BARS_TABLE_KEYS[key] == true end)
    for _, key in ipairs(UNIT_AND_GROUP_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, function(scopeKey) return BARS_SCOPE_KEYS[scopeKey] == true end)
    end
    RetireLegacyUnitAliases(db)
end
local function ResetFontsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return FONT_GENERAL_KEYS[key] == true end)
    ResetKeySet(db, defaults, FONT_ROOT_KEYS)
    for _, key in ipairs(UNIT_AND_GROUP_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, function(scopeKey) return FONT_SCOPE_KEYS[scopeKey] == true end)
    end
    RetireLegacyUnitAliases(db)
end
local AURA_APPEARANCE_KINDS = {
    buff = true, debuff = true, playerDefensives = true, targetDots = true,
}
local function ActiveAuraAppearanceKind(info)
    local kind = info and info.appearanceKind or M.auraAppearanceContainer
    kind = tostring(kind or "buff")
    return AURA_APPEARANCE_KINDS[kind] and kind or "buff"
end
local AURA_APPEARANCE_LABELS = {
    buff = "Buff Appearance",
    debuff = "Debuff Appearance",
    playerDefensives = "Player Defensives Appearance",
    targetDots = "Dots on Target Appearance",
}
local function ResolvePageResetInfo(pageKey)
    local base = PAGE_RESET_INFO[pageKey or ""]
    if not base or base.kind ~= "auraAppearance" then return base end
    local info = {}
    for key, value in pairs(base) do info[key] = value end
    info.appearanceKind = ActiveAuraAppearanceKind(info)
    info.label = AURA_APPEARANCE_LABELS[info.appearanceKind] or info.label
    local blizzardAuraScope = (info.appearanceKind == "buff" or info.appearanceKind == "debuff")
        and ", plus the shared Blizzard Buff/Debuff visibility settings" or ""
    info.summary = "only the global " .. tostring(info.label)
        .. " icon shape, border and shadow settings" .. blizzardAuraScope
        .. "; other Aura types and all Unit/Group lane settings stay unchanged"
    return info
end
local function ResetAuraAppearancePage(db, defaults, info)
    db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
    db.auras3.shared = type(db.auras3.shared) == "table" and db.auras3.shared or {}
    local dst = db.auras3.shared
    local src = type(defaults) == "table" and type(defaults.auras3) == "table"
        and type(defaults.auras3.shared) == "table" and defaults.auras3.shared or {}
    local kind = ActiveAuraAppearanceKind(info)
    dst.appearanceIconShapes = type(dst.appearanceIconShapes) == "table" and dst.appearanceIconShapes or {}
    dst.appearanceIconStyles = type(dst.appearanceIconStyles) == "table" and dst.appearanceIconStyles or {}
    local srcShapes = type(src.appearanceIconShapes) == "table" and src.appearanceIconShapes or {}
    local srcStyles = type(src.appearanceIconStyles) == "table" and src.appearanceIconStyles or {}
    dst.appearanceIconShapes[kind] = DeepCopy(srcShapes[kind])
        or (kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE")
    dst.appearanceIconStyles[kind] = DeepCopy(srcStyles[kind]) or {}
    if kind == "buff" then dst.showWeaponEnchants = src.showWeaponEnchants == true end
    if kind == "buff" or kind == "debuff" then
        dst.hideBlizzardAuraFrames = nil
        dst.hideBlizzardBuffFrame = src.hideBlizzardBuffFrame == true
        dst.hideBlizzardDebuffFrame = src.hideBlizzardDebuffFrame == true
        local UF = MSUF and MSUF.UF
        if UF and type(UF.ApplyBlizzardAuraVisibility) == "function" then
            UF.ApplyBlizzardAuraVisibility()
        end
    end
end
local function ResetCastbarPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key)
        return CASTBAR_GENERAL_KEYS[key] == true or (IsCastbarKey(key) and not IsColorKey(key))
    end)
end
local function ResetColorsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", IsColorKey)
    ReplaceRootTable(db, defaults, "classColors")
    ReplaceRootTable(db, defaults, "npcColors")
    ResetRootFiltered(db, defaults, "gameplay", function(key) return COLOR_GAMEPLAY_KEYS[key] == true or IsColorKey(key) end)
    ResetRootFiltered(db, defaults, "bars", function(key) return COLOR_BARS_KEYS[key] == true end)
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        ResetUnitFiltered(db, defaults, key, function(scopeKey) return GROUP_COLOR_KEYS[scopeKey] == true end)
    end
end
local function ResetMiscPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return MISC_GENERAL_KEYS[key] == true end)
    for _, key in ipairs(MISC_UNIT_RESET_KEYS) do
        ResetUnitFiltered(db, defaults, key, function(unitKey) return MISC_UNIT_KEYS[unitKey] == true end)
    end
end
local function ResetClassPowerPage(db, defaults)
    ResetRootFiltered(db, defaults, "bars", IsClassPowerBarsKey)
    -- Player Power is exposed on both the Player Unit Frame and Class Resources
    -- pages, but it remains a Player setting. Reset only this shared key here so
    -- a Class Resources reset neither misses its visible control nor replaces
    -- unrelated Player-frame configuration.
    db.player = type(db.player) == "table" and db.player or {}
    local defaultPlayer = type(defaults) == "table" and type(defaults.player) == "table"
        and defaults.player or {}
    db.player.playerPowerSource = defaultPlayer.playerPowerSource
end
local function ResetGameplayPage(db, defaults)
    ReplaceRootTable(db, defaults, "gameplay")
end
local function ResetModulesPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return MODULES_GENERAL_KEYS[key] == true end)
end
local PAGE_RESET_HANDLERS = {
    unit = function(db, defaults, info) ResetUnitPage(db, defaults, info.unit) end,
    group = ResetGroupFrames,
    bars = ResetBarsPage,
    fonts = ResetFontsPage,
    auraAppearance = ResetAuraAppearancePage,
    castbar = ResetCastbarPage,
    colors = ResetColorsPage,
    misc = ResetMiscPage,
    classpower = ResetClassPowerPage,
    gameplay = ResetGameplayPage,
    modules = ResetModulesPage,
}
local function FinishPageResetApply(pageKey)
    M.SetFixedPreviewExpandedPreference(true)
    M.ApplyLocaleSelection(M.GetLocaleSelection and M.GetLocaleSelection() or "auto")
    if M.ApplyMenuFrameScale and M.frame then M.ApplyMenuFrameScale(M.frame) end
    if pageKey and M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(pageKey)
        M.activeKey = nil
        M.SelectPage(pageKey)
    else
        QueueMenuRefresh()
    end
end

local function ApplyGroupPageResetRuntime(reason)
    if ApplyService.RequestGroupReset then
        return ApplyService.RequestGroupReset(reason or "MSUF2_RESET_GROUP") ~= false
    end
    local gf = MSUF and MSUF.GF
    if not gf then return false end
    if type(gf.InvalidateConfCache) == "function" then gf.InvalidateConfCache() end
    if type(gf.RefreshAll) == "function" then
        gf.RefreshAll()
    elseif type(gf.RebuildAll) == "function" then
        gf.RebuildAll()
    elseif type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(nil, gf.DIRTY_ALL or gf.DIRTY_CONFIG or gf.DIRTY_VISUAL)
    end
    if type(gf.RequestAuraRefresh) == "function" then gf.RequestAuraRefresh() end
    if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout() end
    return true
end

local function ApplyAurasPageResetRuntime(reason, visuals)
    if visuals and ApplyService.RequestAuraFonts then
        return ApplyService.RequestAuraFonts("shared", reason or "MSUF2_RESET_AURA_VISUALS") ~= false
    end
    if ApplyService.RequestAuras then
        return ApplyService.RequestAuras("shared", reason or "MSUF2_RESET_AURAS", visuals and { visuals = true } or nil) ~= false
    end
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras and type(auras.RequestApply) == "function" then
        auras.RequestApply("shared", reason or "MSUF2_RESET_AURAS")
        return true
    end
    if auras and type(auras.RefreshAll) == "function" then
        auras.RefreshAll()
        return true
    end
    return false
end

local function ApplyDomainPageResetRuntime(info, reason)
    if not info then return false end
    local kind = info.kind
    if kind == "group" then
        return ApplyGroupPageResetRuntime(reason)
    end
    if kind == "bars" then
        if ApplyService.RequestBars then return ApplyService.RequestBars(reason) ~= false end
        if M.RequestGeneralApply then return M.RequestGeneralApply(reason, { preview = true, applyAll = false, bars = true }) ~= false end
        return false
    end
    if kind == "fonts" then
        if ApplyService.RequestFonts then return ApplyService.RequestFonts(reason) ~= false end
        if M.RequestGeneralApply then return M.RequestGeneralApply(reason, { preview = true, applyAll = false, fonts = true }) ~= false end
        return false
    end
    if kind == "colors" then
        local did = false
        if ApplyService.RequestColors then
            did = ApplyService.RequestColors(reason) ~= false or did
        elseif M.RequestGeneralApply then
            M.RequestGeneralApply(reason, { preview = true, applyAll = false, colors = true })
            did = true
        end
        did = ApplyAurasPageResetRuntime(reason, true) or did
        if ApplyService.RequestClassPower then
            ApplyService.RequestClassPower(reason or "MSUF2_RESET_COLORS", COLOR_CLASSPOWER_RUNTIME)
            did = true
        else
            _G.MSUF_ClassPower_InvalidateColors()
did = true
        end
        return did
    end
    if kind == "auraAppearance" then
        return ApplyAurasPageResetRuntime(reason)
    end
    return false
end

local function ApplyAfterPageReset(pageKey, info)
    local reason = "MSUF2_RESET_" .. tostring(pageKey or "PAGE")
    if info and info.kind == "unit" and info.unit then
        if info.unit == "player" then
            ApplyScopedFeatureRuntime("classpower", reason)
        end
        if M.RequestUnitApply then
            M.RequestUnitApply(info.unit, reason, {
                history = false, preview = true, power = true, castbar = true, auras = true,
                classpowerApplied = info.unit == "player",
            })
        end
        FinishPageResetApply(pageKey)
        return
    end
    if info and ApplyScopedFeatureRuntime(info.kind, reason) then
        FinishPageResetApply(pageKey)
        return
    end
    if ApplyDomainPageResetRuntime(info, reason) then
        FinishPageResetApply(pageKey)
        return
    end
    if M.RequestGeneralApply then M.RequestGeneralApply(reason, { preview = true, alpha = true, castbar = true, frames = true }) end
    if info and info.kind == "gameplay" then M.ApplyGameplay() end
    if info and info.kind == "misc" then
        local db = M.EnsureDB()
        local general = db and db.general
        _G.MSUF_NSRTNicknames_ApplySetting()
        _G.MSUF_EllesmereEditMode_SetEnabled(not (type(general) == "table" and general.ellesmereEditModeIntegration == false))
        _G.MSUF_Grid2EditMode_SetEnabled(not (type(general) == "table" and general.grid2EditModeIntegration == false))
        _G.MSUF_DetailsEditMode_SetEnabled(not (type(general) == "table" and general.detailsEditModeIntegration == false))
        _G.MSUF_DominosEditMode_SetEnabled(not (type(general) == "table" and general.dominosEditModeIntegration == false))
        _G.MSUF_DandersEditMode_SetEnabled(not (type(general) == "table" and general.dandersEditModeIntegration == false))
        _G.MSUF_BlizzardEditMode_SetEnabled(not (type(general) == "table" and general.blizzardEditModeIntegration == false))
    end
    -- Page reset fanout is intentionally keyed by page kind so a unit reset does not rebuild
    -- secure group headers or Auras3 lanes unnecessarily.
    if info and (info.kind == "auras" or info.kind == "colors") then
        ApplyAurasPageResetRuntime(reason, info.kind == "colors")
    end
    if info and (info.kind == "group" or info.kind == "bars" or info.kind == "fonts" or info.kind == "colors") then
        if info.kind == "group" then
            ApplyGroupPageResetRuntime(reason)
        elseif ApplyService.RequestGroupDirtyMask then
            local gf = MSUF and MSUF.GF
            local dirty = gf and ((info.kind == "fonts" and gf.DIRTY_FONT)
                or (info.kind == "colors" and gf.DIRTY_COLOR)
                or gf.DIRTY_VISUAL)
            if dirty then
                ApplyService.RequestGroupDirtyMask("group", dirty, reason)
            elseif ApplyService.RequestGroup then
                local mode = (info.kind == "fonts" and "fonts") or (info.kind == "colors" and "colors") or "visual"
                ApplyService.RequestGroup("group", mode, reason)
            end
        elseif ApplyService.RequestGroup then
            local mode = (info.kind == "fonts" and "fonts") or (info.kind == "colors" and "colors") or "visual"
            ApplyService.RequestGroup("group", mode, reason)
        else
            local gf = MSUF and MSUF.GF
            if gf then
                if type(gf.InvalidateConfCache) == "function" then gf.InvalidateConfCache() end
                if info.kind == "fonts" and type(gf.RefreshFonts) == "function" then
                    gf.RefreshFonts()
                elseif info.kind == "colors" and type(gf.RefreshColors) == "function" then
                    gf.RefreshColors()
                elseif type(gf.RefreshVisuals) == "function" then
                    gf.RefreshVisuals(nil, gf.DIRTY_VISUAL or 2)
                elseif type(gf.RebuildAll) == "function" then
                    gf.RebuildAll()
                end
                if type(gf.RequestAuraRefresh) == "function" then gf.RequestAuraRefresh() end
            end
        end
    end
    if info and info.kind == "modules" then _G.MSUF_ApplyModules() end
    FlushApplyServiceNow()
    FinishPageResetApply(pageKey)
end
local function ResetProfilePage()
    local name = _G.MSUF_ActiveProfile or "Default"
    if type(_G.MSUF_ResetProfile) ~= "function" then return false end
    _G.MSUF_ResetProfile(name)
    M.ClearHistory()
    ApplyAfterPageReset("profiles", PAGE_RESET_INFO.profiles)
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then _G.MSUF_ShowReloadRecommendedPopup("Profile reset") end
    return true
end
-- A deliberate "Reset to defaults" must leave no stale runtime cache behind, or
-- the user keeps seeing pre-reset geometry (aura lane offsets, spell-indicator
-- anchors, unit-frame positions) even though the saved values are already back
-- to factory. The normal apply path trusts these caches for speed, so the reset
-- drops them here before ApplyAfterPageReset re-reads the fresh defaults. Every
-- call below is cold-path only: generation bumps and flag sets, no layout pass.
local function PurgeRuntimeCachesForReset(info)
    -- The aura/SI/GF/castbar invalidations run for EVERY page kind, not just the
    -- page that was reset: bump the revision counters, flag geometry and wipe the
    -- small resolver tables so ApplyAfterPageReset below repopulates each cache
    -- from the fresh defaults. A reset is deliberate and rare, so invalidating a
    -- cache the page did not touch only costs one recompute and guarantees no
    -- scope keeps pre-reset values. Everything here is cold-path only.
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 then
        -- A global bump is intended here (unlike a single-control edit): a page
        -- reset means every scope's cached aura lane layout should recompute.
        a3.BumpRuntimeConfig()
        local siRuntime = a3.SpellIndicators
        siRuntime.RequestGeometryRepair()
    end
    local gf = MSUF and MSUF.GF
    if gf then
        gf.InvalidateConfCache()
        local si = gf.SpellIndicators
        si.InvalidateRuntimeCaches()
    end
    -- Castbars and bars keep their own resolver caches: the resolved statusbar
    -- texture table (shared by every bar and castbar) and the revision-keyed
    -- castbar style cache (texture, fill direction, reverse fill). Without
    -- dropping both, a reset frame keeps its old texture/style even though the
    -- saved values are already back to factory.
    _G.MSUF_ClearResolvedStatusbarTextureCache()
    _G.MSUF_BumpCastbarStyleRevision()
    -- Unit-frame screen positions sit in a per-frame anchor cache the hot apply
    -- path short-circuits against, so a reset frame would otherwise stay put.
    -- Only unit resets move a unit frame; drop the cache and force a re-anchor
    -- from the fresh defaults. (Group headers reposition through the GF reset.)
    if info and info.kind == "unit" then
        _G.MSUF_ForceReanchorAllUnitFrames_Once()
    end
end
local function ResetPageImpl(pageKey)
    local info = ResolvePageResetInfo(pageKey)
    if not info then return false end
    if info.kind == "profile" then return ResetProfilePage() end
    local defaults = FactoryDefaults()
    if type(defaults) ~= "table" then
        if M.ShowStatusFeedback then
            M.ShowStatusFeedback(M.Tr("Reset failed: defaults unavailable"), "danger", 1.8)
        elseif print then
            print("|cffff0000MSUF:|r Reset failed: factory defaults are not available yet.")
        end
        return false
    end
    local db = M.EnsureDB()
    local handler = PAGE_RESET_HANDLERS[info.kind]
    if not handler then return false end
    handler(db, defaults, info)
    RetireLegacyUnitAliases(db)
    PurgeRuntimeCachesForReset(info)
    ApplyAfterPageReset(pageKey, info)
    if M.ShowStatusFeedback then
        M.ShowStatusFeedback(Fmt("%s reset", tostring(info.label or pageKey)), "ok", 1.4)
    elseif print then
        print(Fmt("|cffffd700MSUF:|r %s reset to defaults.", tostring(info.label or pageKey)))
    end
    return true
end
function M.PageHasReset(pageKey)
    return PAGE_RESET_INFO[pageKey or ""] ~= nil
end
function M.BuildPageResetWarning(pageKey)
    local info = ResolvePageResetInfo(pageKey)
    if not info then return nil end
    local title = info.label or ((M.pages and M.pages[pageKey] and M.pages[pageKey].title) or pageKey or "this menu")
    title = M.Tr and M.Tr(title) or title
    if info.kind == "profile" then
        local profileName = _G.MSUF_ActiveProfile or "Default"
        return string.format(
            M.Tr("Reset %s to defaults?\n\nThis resets the entire active profile '%s' to the current MSUF factory defaults. Every menu in that profile will be affected."),
            tostring(title),
            tostring(profileName)
        )
    end
    return string.format(
        M.Tr("Reset %s to defaults?\n\nThis resets %s for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically."),
        tostring(title),
        tostring(info.summaryFormat and Fmt(info.summaryFormat, tostring(info.label or title))
            or (M.Tr and M.Tr(info.summary or title)) or info.summary or title)
    )
end
function M.ResetPageToDefaults(pageKey)
    if M.BlockCombatAction() then return false end
    local info = ResolvePageResetInfo(pageKey)
    if not info then return false end
    if info.kind == "profile" then return ResetPageImpl(pageKey) end
    return M.RunWithHistory("Reset " .. tostring(info.label or pageKey), "page:reset:" .. tostring(pageKey), function()
        return ResetPageImpl(pageKey)
    end)
end
function M.ShowPageResetConfirm(pageKey)
    if M.BlockCombatAction() then return false end
    if not M.PageHasReset(pageKey) then return false end
    local message = M.BuildPageResetWarning(pageKey)
    if not message then return false end
    if not _G.StaticPopupDialogs then return M.ResetPageToDefaults(pageKey) end
    M.InstallStaticPopup("MSUF2_PAGE_RESET_CONFIRM", {
        text = "%s",
        button1 = _G.YES or "Yes",
        button2 = _G.NO or "No",
        OnAccept = function(_, data)
            if data and data.pageKey then M.ResetPageToDefaults(data.pageKey) end
        end,
    })
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF2_PAGE_RESET_CONFIRM", message, nil, { pageKey = pageKey })
        return true
    end
    return M.ResetPageToDefaults(pageKey)
end
