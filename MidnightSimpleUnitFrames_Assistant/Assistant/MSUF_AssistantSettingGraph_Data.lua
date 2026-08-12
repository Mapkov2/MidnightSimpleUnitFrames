-- Declarative setting-dependency evidence for the in-game Assistant.
--
-- This catalog intentionally contains only relationships that can be traced to
-- an existing registry/runtime implementation.  The graph engine expands these
-- compact rules against registered setting keys on first use; no graph work is
-- performed while the addon is loading.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local D = {
    schemaVersion = 2,

    -- Relation direction is always dependent -> prerequisite/source.
    relationKinds = {
        enablement = true,
        visibility = true,
        availability = true,
        requires = true,
        inheritance = true,
        override = true,
        conflict = true,
        -- A navigation-only relationship derived from two registered controls
        -- living in the same MSUF menu section/scope.  Association never
        -- participates in runtime prerequisite evaluation.
        association = true,
    },

    unitScopes = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss" },
    groupScopes = { "gf_party", "gf_raid", "gf_mythicraid" },
    auraScopes = { "player", "target", "focus", "boss" },
}

-- Page-resolvable settings normally need another setting node that explains
-- their runtime gate, inheritance source, conflict, or navigation context.
-- A small reviewed exception list is allowed when the dependency is an
-- Assistant action rather than another scalar setting.  Keep these records
-- explicit and evidence-backed so graph coverage never invents a false
-- setting-to-setting edge merely to reach 100 percent.
D.intentionalStandaloneSettings = {
    ["profiles.specAutoSwitch"] = {
        classification = "intentional-standalone-with-action-dependency",
        actionKeys = { "set_spec_profile", "clear_spec_profile" },
        reason = "Spec auto-switch is an independent boolean; its useful routing state is created or removed by the specialization-profile assignment actions, not by another registered scalar setting.",
        evidence = "MSUF_Profiles.lua:MSUF_SetSpecAutoSwitchEnabled/MSUF_SetSpecProfile and MSUF_AssistantRegistry_Profiles.lua:set_spec_profile/clear_spec_profile",
    },
}

-- Top-level runtime gates.  A disabled parent does not make its children
-- uneditable: it makes them ineffective until the parent is enabled again.
D.scopeRootRules = {
    {
        id = "unit-frame-root",
        scopes = "unitScopes",
        frameTypes = { "unitframe" },
        parent = "{scope}.enabled",
        kind = "enablement",
        impact = "runtimeEffectiveness",
        reason = "The unit frame must be enabled before its child settings can affect the live frame.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Base.lua:RegisterUnitBaseSettings and the unit-frame runtime enabled gate",
    },
    {
        id = "group-frame-root",
        scopes = "groupScopes",
        frameTypes = { "group", "groupAura" },
        parent = "{scope}.enabled",
        kind = "enablement",
        impact = "runtimeEffectiveness",
        reason = "The group-frame scope must be enabled before its child settings can affect live group frames.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSettings_Basic.lua:RegisterGroupBoolean(enabled) and group-frame config/runtime",
    },
    {
        id = "unit-aura-root",
        keyPrefix = "auras3.",
        parent = "auras3.enabled",
        kind = "enablement",
        impact = "runtimeEffectiveness",
        reason = "The Aura system must be enabled before per-scope Aura settings can render.",
        evidence = "MSUF_AssistantRegistry_Auras_Menu_Shared.lua:auras3.enabled and the Aura model root enabled flag",
    },
}

-- Nested gates whose child controls remain safe to configure while the gate is
-- off, but are hidden, secondary, or not currently effective in the live UI.
D.patternGateRules = {
    {
        id = "group-aura-root",
        scanTops = "groupScopes",
        match = "^(gf_[^.]+)%.auras%..+",
        parent = "{1}.auras.enabled",
        kind = "enablement",
        impact = "runtimeEffectiveness",
        reason = "This group Aura setting is effective only while Auras are enabled for the group scope.",
        evidence = "MSUF_AssistantRegistry_AurasGroupRootSettings.lua:RegisterGFAuraRootBoolean(enabled)",
    },
    {
        id = "group-aura-lane",
        scanTops = "groupScopes",
        match = "^(gf_[^.]+)%.auras%.([^.]+)%.+",
        allowedCapture = { index = 2, values = { "buff", "debuff" } },
        parent = "{1}.auras.{2}.enabled",
        kind = "visibility",
        impact = "laneVisibility",
        reason = "Lane layout and style are visible only while that group Aura lane is enabled.",
        evidence = "MSUF_AssistantRegistry_AurasGroupLaneCore.lua:RegisterGFAuraBoolean(enabled)",
    },
    {
        id = "unit-aura-lane",
        scanTop = "auras3",
        match = "^auras3%.([^.]+)%.([^.]+)%.+",
        allowedCapture = { index = 2, values = { "buff", "debuff" } },
        deniedCapture = { index = 1, values = { "shared" } },
        parent = "auras3.{1}.{2}.visible",
        kind = "visibility",
        impact = "laneVisibility",
        reason = "Lane layout, filters, and style are visible only while that Aura lane is shown.",
        evidence = "MSUF_AssistantRegistry_AurasUnitLanes.lua:RegisterAuraUnitLaneBoolean(visible)",
    },
    {
        id = "unit-aura-filters",
        scanTop = "auras3",
        match = "^auras3%.([^.]+)%.([^.]+)%.filter%..+",
        parent = "auras3.{1}.{2}.filtersEnabled",
        kind = "availability",
        impact = "filterEvaluation",
        reason = "Individual filter switches participate only while filters are enabled for this Aura scope.",
        evidence = "MSUF_AssistantRegistry_Auras_Filters.lua:RegisterFilterSettings(filtersEnabled)",
    },
}

-- Repeated scope-local field families.  Prefixes are DB/registry field stems,
-- not natural-language guesses.
D.scopedFieldGateRules = {
    {
        id = "unit-name",
        scopes = "unitScopes",
        parentSuffix = "showName",
        childPrefixes = { "name", "shortenName" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Name formatting is visible only while the unit name is shown.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Text.lua and showName in Unitframes_Base",
    },
    {
        id = "unit-health-text",
        scopes = "unitScopes",
        parentSuffix = "showHP",
        childPrefixes = { "hpText", "hpFont", "hpOffset", "hpFullValueShort", "healthText", "textLeft", "textCenter", "textRight" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Health-text formatting is visible only while health text is shown.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Text.lua and showHP in Unitframes_Base",
    },
    {
        id = "unit-power-bar",
        scopes = "unitScopes",
        parentSuffix = "showPowerBar",
        childPrefixes = { "powerBar" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Power-bar appearance is visible only while the unit power bar is shown.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Power.lua:showPowerBar",
    },
    {
        id = "unit-power-text",
        scopes = "unitScopes",
        parentSuffix = "showPowerText",
        childPrefixes = { "powerText", "powerFont", "powerOffset" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Power-text formatting is visible only while power text is shown.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Power.lua:showPowerText",
    },
    {
        id = "unit-detached-power",
        scopes = "unitScopes",
        parentSuffix = "powerBarDetached",
        childPrefixes = { "detachedPower" },
        kind = "availability",
        impact = "layoutMode",
        reason = "Detached power-bar layout settings apply only in detached mode.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Power_Detached.lua:powerBarDetached",
    },
    {
        id = "unit-range-fade",
        scopes = "unitScopes",
        parentSuffix = "rangeFadeEnabled",
        childPrefixes = { "rangeFade" },
        kind = "availability",
        impact = "runtimeEffectiveness",
        reason = "Range-fade detail settings apply only while range fading is enabled.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Transparency.lua:rangeFadeEnabled",
    },
    {
        id = "unit-status-text",
        scopes = "unitScopes",
        parentSuffix = "statusTextEnabled",
        childPrefixes = { "statusText" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Status-text layout is visible only while status text is enabled.",
        evidence = "MSUF_AssistantRegistry_Unitframes_StatusText.lua:statusTextEnabled",
    },
    {
        id = "unit-load-conditions",
        scopes = "unitScopes",
        parentSuffix = "loadCondActive",
        childPrefixes = { "loadCondHide" },
        kind = "availability",
        impact = "conditionEvaluation",
        reason = "Individual load conditions are evaluated only while conditional loading is active.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Core_SettingsBase_Unit.lua:loadCondActive",
    },
    {
        id = "unit-portrait-mode",
        scopes = "unitScopes",
        parentSuffix = "portraitMode",
        childPrefixes = { "portrait" },
        condition = { operator = "notEquals", value = "OFF" },
        kind = "availability",
        impact = "componentAvailability",
        reason = "Portrait appearance controls apply only when portrait mode is not Off.",
        evidence = "MSUF_AssistantRegistry_Unitframes_Portrait.lua:portraitMode OFF/LEFT/RIGHT",
    },
    {
        id = "group-name",
        scopes = "groupScopes",
        parentSuffix = "showName",
        childPrefixes = { "name" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Group-name formatting is visible only while group names are shown.",
        evidence = "MSUF_AssistantRegistry_GroupFramesText.lua:showName",
    },
    {
        id = "group-health-text",
        scopes = "groupScopes",
        parentSuffix = "showHPText",
        childPrefixes = { "hpText", "hpFont", "hpOffset", "hpFullValueShort", "healthText" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Group health-text formatting is visible only while health text is shown.",
        evidence = "MSUF_AssistantRegistry_GroupFramesText.lua:showHPText",
    },
    {
        id = "group-power-bar",
        scopes = "groupScopes",
        parentSuffix = "powerBarEnabled",
        childPrefixes = { "powerBar", "powerShow", "detachedPower" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Group power-bar settings are visible only while the power bar is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSettings_Bars_Power.lua:powerBarEnabled",
    },
    {
        id = "group-power-text",
        scopes = "groupScopes",
        parentSuffix = "showPowerText",
        childPrefixes = { "powerText", "powerFont", "powerOffset" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Group power-text formatting is visible only while power text is shown.",
        evidence = "MSUF_AssistantRegistry_GroupFramesText.lua:showPowerText",
    },
    {
        id = "group-range-fade",
        scopes = "groupScopes",
        parentSuffix = "rangeFadeEnabled",
        childPrefixes = { "rangeFade" },
        kind = "availability",
        impact = "runtimeEffectiveness",
        reason = "Group range-fade details apply only while range fading is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSettings_FrameState.lua:rangeFadeEnabled",
    },
    {
        id = "group-corner-indicators",
        scopes = "groupScopes",
        parentSuffix = "ciEnabled",
        childPrefixes = { "ci" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Corner-indicator slots and styling are visible only while corner indicators are enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSpellIndicators_CornerSettings.lua:ciEnabled",
    },
    {
        id = "group-spell-indicators",
        scopes = "groupScopes",
        parentSuffix = "spellIndicators.enabled",
        childPrefixes = { "spellIndicators." },
        kind = "availability",
        impact = "indicatorEvaluation",
        reason = "Spell-indicator details apply only while spell indicators are enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSpellIndicators.lua:spellIndicators.enabled",
    },
    {
        id = "group-border",
        scopes = "groupScopes",
        parentSuffix = "borderEnabled",
        childPrefixes = { "border" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Border appearance is visible only while the frame border is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesVisual.lua:borderEnabled",
    },
    {
        id = "group-container-border",
        scopes = "groupScopes",
        parentSuffix = "groupBorderEnabled",
        childPrefixes = { "groupBorder" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Group-container border details are visible only while that border is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesVisual.lua:groupBorderEnabled",
    },
    {
        id = "group-dispel-overlay",
        scopes = "groupScopes",
        parentSuffix = "dispelOverlayEnabled",
        childPrefixes = { "dispelOverlay" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Dispel-overlay details are visible only while the overlay is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesVisual_Highlights.lua:dispelOverlayEnabled",
    },
    {
        id = "group-debuff-stripe",
        scopes = "groupScopes",
        parentSuffix = "debuffStripeEnabled",
        childPrefixes = { "debuffStripe" },
        kind = "visibility",
        impact = "componentVisibility",
        reason = "Debuff-stripe styling is visible only while the stripe is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesVisual.lua:debuffStripeEnabled",
    },
    {
        id = "group-health-fade",
        scopes = "groupScopes",
        parentSuffix = "healthFadeEnabled",
        childPrefixes = { "healthFade" },
        kind = "availability",
        impact = "runtimeEffectiveness",
        reason = "Health-fade details apply only while health fading is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSettings_FrameAlphaAnchor.lua:healthFadeEnabled",
    },
    {
        id = "group-offline-hide",
        scopes = "groupScopes",
        parentSuffix = "hideOfflineEnabled",
        childPrefixes = { "hideOffline" },
        kind = "availability",
        impact = "conditionEvaluation",
        reason = "Offline-hide timing and combat behavior apply only while offline hiding is enabled.",
        evidence = "MSUF_AssistantRegistry_GroupFramesSettings_FrameState.lua:hideOfflineEnabled",
    },
}

D.prefixGateRules = {
    {
        id = "class-power-display",
        childPrefix = "bars.classPower",
        parent = "bars.showClassPower",
        kind = "availability",
        impact = "componentAvailability",
        reason = "Class-resource appearance and behavior apply only while the class-resource display is enabled.",
        evidence = "MSUF_AssistantRegistry_ClassPower_Base.lua:bars.showClassPower",
    },
    {
        id = "player-hp-bar",
        childPrefix = "bars.playerHPBar",
        parent = "bars.playerHPBarEnabled",
        kind = "availability",
        impact = "componentAvailability",
        reason = "Detached player-health-bar details apply only while that bar is enabled.",
        evidence = "MSUF_AssistantRegistry_ClassPower_PlayerHP.lua:playerHPBarEnabled",
    },
    {
        id = "class-power-conditions",
        childPrefix = "bars.cpCond",
        parent = "bars.cpCondEnabled",
        kind = "availability",
        impact = "conditionEvaluation",
        reason = "Class-resource visibility conditions are evaluated only while conditional visibility is enabled.",
        evidence = "MSUF_AssistantRegistry_ClassPower_Visibility.lua:cpCondEnabled",
    },
    {
        id = "class-power-sounds",
        childPrefix = "bars.cpSound",
        parent = "bars.cpSoundEnabled",
        kind = "availability",
        impact = "soundPlayback",
        reason = "Class-resource sound events apply only while class-resource sounds are enabled.",
        evidence = "MSUF_AssistantRegistry_ClassPower.lua:cpSoundEnabled",
    },
    {
        id = "alternate-mana",
        childPrefix = "bars.altMana",
        parent = "bars.showAltMana",
        kind = "availability",
        impact = "componentAvailability",
        reason = "Alternate-mana layout applies only while alternate mana is shown.",
        evidence = "MSUF_AssistantRegistry_ClassPower_AltMana.lua:showAltMana",
    },
    {
        id = "stagger-bar",
        childPrefix = "bars.stagger",
        parent = "bars.showStagger",
        kind = "availability",
        impact = "componentAvailability",
        reason = "Stagger-bar layout applies only while the Stagger display is shown.",
        evidence = "MSUF_AssistantRegistry_ClassPower.lua:showStagger",
    },
}

D.featureGateRules = {
    {
        id = "combat-timer",
        parent = "gameplay.enableCombatTimer",
        children = { "gameplay.combatTimer", "gameplay.combatFontSize", "gameplay.lockCombatTimer", "gameplay.combatOffset" },
        kind = "availability",
        reason = "Combat-timer details apply only while the Combat Timer module is enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay_Combat.lua:enableCombatTimer",
    },
    {
        id = "combat-state-text",
        parent = "gameplay.enableCombatStateText",
        children = { "gameplay.combatState", "gameplay.lockCombatState" },
        kind = "availability",
        reason = "Combat-state text details apply only while Combat State Text is enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay_Combat.lua:enableCombatStateText",
    },
    {
        id = "player-totems",
        parent = "gameplay.enablePlayerTotems",
        children = { "gameplay.playerTotems" },
        kind = "availability",
        reason = "Totem layout applies only while Player Totems are enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay_Totems.lua:enablePlayerTotems",
    },
    {
        id = "combat-crosshair",
        parent = "gameplay.enableCombatCrosshair",
        children = { "gameplay.crosshair" },
        kind = "availability",
        reason = "Crosshair layout and colors apply only while the combat crosshair is enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay_Crosshair.lua:enableCombatCrosshair",
    },
    {
        id = "kick-tracker",
        parent = "gameplay.enableKickTracker",
        children = { "gameplay.kickTracker", "gameplay.lockKickTracker" },
        kind = "availability",
        reason = "Kick-tracker layout and visibility rules apply only while the Kick Tracker is enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay.lua:enableKickTracker",
    },
    {
        id = "first-dance",
        parent = "gameplay.enableFirstDanceTimer",
        children = { "gameplay.firstDance", "gameplay.lockFirstDance" },
        kind = "availability",
        reason = "First Dance timer details apply only while that timer is enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay.lua:enableFirstDanceTimer",
    },
    {
        id = "apex-alert",
        parent = "gameplay.enableApexAlert",
        children = { "gameplay.apexAlert", "gameplay.lockApexAlert" },
        kind = "availability",
        reason = "Apex Alert details apply only while Apex Alert is enabled.",
        evidence = "MSUF_AssistantRegistry_Gameplay.lua:enableApexAlert",
    },
}

-- Explicit prerequisites with stronger semantics than a presentational gate.
D.requiresEdges = {
    {
        id = "rune-time-text",
        from = "bars.runeShowTimeText",
        to = "bars.runeShowTime",
        condition = { operator = "equals", value = true },
        reason = "Rune time text requires rune time display to be enabled.",
        evidence = "MSUF_AssistantRegistry_ClassPower_Display_Text.lua:runeShowTime/runeShowTimeText",
    },
    {
        id = "gcd-spell",
        from = "general.showGCDBarSpell",
        to = "general.showGCDBar",
        condition = { operator = "equals", value = true },
        reason = "The GCD spell label requires the GCD bar.",
        evidence = "MSUF_AssistantRegistry_Global_CastbarSettings.lua:showGCDBar",
    },
    {
        id = "gcd-time",
        from = "general.showGCDBarTime",
        to = "general.showGCDBar",
        condition = { operator = "equals", value = true },
        reason = "The GCD time label requires the GCD bar.",
        evidence = "MSUF_AssistantRegistry_Global_CastbarSettings.lua:showGCDBar",
    },
}

-- Formatting applicability is an OR relationship: HP abbreviation matters
-- when any of the three HP slots contains a numeric value.  Model the slot
-- controls as non-blocking associations rather than three simultaneous hard
-- prerequisites, while retaining the normal Show HP/root gates above.
D.scopedAssociationRules = {
    {
        id = "unit-hp-abbreviation-numeric-modes",
        scopes = "unitScopes",
        fromSuffix = "hpFullValueShort",
        toSuffixes = { "textLeft", "textCenter", "textRight" },
        condition = {
            operator = "oneOf",
            values = {
                "CURRENT", "FULLVALUE", "MAX", "DEFICIT", "CURMAX", "CURPERCENT",
                "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX",
            },
        },
        impact = "formatApplicability",
        reason = "HP abbreviation affects this slot only when its mode contains a numeric health value; None and Percent-only are unaffected.",
        evidence = "MSUF_Menu2_UnitText.lua:RefreshFullValueToggle and MSUF_UF_Config.lua:healthShortNumbers",
    },
    {
        id = "group-hp-abbreviation-numeric-modes",
        scopes = "groupScopes",
        fromSuffix = "hpFullValueShort",
        toSuffixes = { "textLeft", "textCenter", "textRight" },
        condition = {
            operator = "oneOf",
            values = {
                "CURRENT", "FULLVALUE", "MAX", "DEFICIT", "CURMAX", "CURPERCENT",
                "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "PERCENTCURMAX",
            },
        },
        impact = "formatApplicability",
        reason = "HP abbreviation affects this slot only when its mode contains a numeric health value; None and Percent-only are unaffected.",
        evidence = "MSUF_Menu2_GroupBars.lua:RefreshShortNumbersToggle and MSUF_UF_Group_Config.lua:healthShortNumbers",
    },
}

-- Scoped-global registries implement their inheritance through these exact
-- override gates.  The engine links only an unambiguous registered source.
D.scopedInheritanceRules = {
    {
        id = "font-scope-inheritance",
        prefix = "fontScope",
        scopes = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss", "gf_party", "gf_raid" },
        sourcePrefixes = { "fontScope.shared" },
        overrideSuffix = "override",
        evidence = "MSUF_AssistantRegistry_GlobalFontSettings.lua and Registry_Core_GlobalScope_Accessors.lua:GlobalScopeRead",
    },
    {
        id = "bar-scope-inheritance",
        prefix = "barScope",
        scopes = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss", "gf_party", "gf_raid" },
        sourcePrefixes = { "general", "bars" },
        requireUniqueSource = true,
        overrideSuffix = "override",
        evidence = "MSUF_AssistantRegistry_GlobalBarSettings_Scoped.lua and Registry_Core_GlobalScope_Accessors.lua:GlobalScopeRead",
    },
}

-- Group name shortening uses native gf_* keys rather than fontScope.* keys,
-- but follows the same Shared Fonts source until the group font override is
-- enabled. Keep this cross-prefix relationship explicit so explanations and
-- impact analysis know that No Ellipsis, length, side, and enablement move as
-- one inherited setup.
D.crossPrefixInheritanceRules = {
    {
        id = "group-name-font-inheritance",
        targets = {
            { prefix = "gf_party", gate = "fontScope.gf_party.override" },
        },
        fields = {
            { target = "nameShortenEnabled", source = "shortenNames" },
            { target = "nameMaxChars", source = "shortenNameMaxChars" },
            { target = "nameClipSide", source = "shortenNameClipSide" },
            { target = "nameNoEllipsis", source = "shortenNameNoEllipsis" },
        },
        sourcePrefix = "fontScope.shared",
        reason = "This group name-shortening value follows Shared Fonts while the group font override is off.",
        overrideReason = "The group font override makes this name-shortening value independent from Shared Fonts.",
        evidence = "MSUF_GroupFrames_DB.lua:GF.ResolveNameTruncation and MSUF_Menu2_GlobalFonts.lua:SeedGFNameShorteningFromShared. Raid/Mythic are intentionally omitted here because the Fonts UI gate is aggregate while runtime evaluates their native flags independently.",
    },
}

D.auraInheritance = nil

-- Conflicts are sourced from A.AurasRegistryData.AURA_FILTER_BOOLEAN_SPECS at
-- build time, so the graph cannot drift from the setter that turns the paired
-- filter off.
D.conflictProviders = {
    {
        id = "aura-filter-conflicts",
        provider = "auraFilterSpecs",
        evidence = "MSUF_AssistantRegistry_Auras_Data_StyleFilters.lua:AURA_FILTER_BOOLEAN_SPECS.conflicts and Auras_Filters.lua:set",
    },
}

A.SettingGraphData = D
