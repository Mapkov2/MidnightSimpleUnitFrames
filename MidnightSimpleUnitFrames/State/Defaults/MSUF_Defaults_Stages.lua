-- Default seed-stage composition and status, aura and unit-state stages.
local _, MSUF = ...
local Parts = MSUF.DefaultsParts
local IS_CLASSIC_FAMILY = Parts.IS_CLASSIC_FAMILY
local MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION = Parts.MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
local MSUF_DEFAULTS_GROUP_AURA_SCOPES = Parts.MSUF_DEFAULTS_GROUP_AURA_SCOPES
local MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = Parts.MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION
local MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION = Parts.MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION
local MSUF_DEFAULTS_TEXT_SCOPE_KEYS = Parts.MSUF_DEFAULTS_TEXT_SCOPE_KEYS
local MSUF_DEFAULT_ARENA_OFFSET_X = Parts.MSUF_DEFAULT_ARENA_OFFSET_X
local MSUF_DEFAULT_ARENA_OFFSET_Y = Parts.MSUF_DEFAULT_ARENA_OFFSET_Y
local MSUF_DEFAULT_BOSS_OFFSET_X = Parts.MSUF_DEFAULT_BOSS_OFFSET_X
local MSUF_DEFAULT_BOSS_OFFSET_Y = Parts.MSUF_DEFAULT_BOSS_OFFSET_Y
local MSUF_Defaults_CopyIfMissing = Parts.MSUF_Defaults_CopyIfMissing
local MSUF_Defaults_CreateCanonicalGroupAuraState = Parts.MSUF_Defaults_CreateCanonicalGroupAuraState
local MSUF_Defaults_CreateCanonicalUnitAuras = Parts.MSUF_Defaults_CreateCanonicalUnitAuras
local MSUF_Defaults_GetMenuFontDefault = Parts.MSUF_Defaults_GetMenuFontDefault
local MSUF_Defaults_MigrateUnitDispelOwnership = Parts.MSUF_Defaults_MigrateUnitDispelOwnership
local MSUF_Defaults_NormalizeFontShadowScope = Parts.MSUF_Defaults_NormalizeFontShadowScope
local MSUF_Defaults_NormalizePortraitClassStyleValue = Parts.MSUF_Defaults_NormalizePortraitClassStyleValue
local MSUF_Defaults_NormalizePortraitRenderValue = Parts.MSUF_Defaults_NormalizePortraitRenderValue
local sharedShellDefaults = MSUF.DefaultsStageFactories.Shell({
    MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION,
    MSUF_Defaults_GetMenuFontDefault = MSUF_Defaults_GetMenuFontDefault,
    MSUF_Defaults_MigrateUnitDispelOwnership = MSUF_Defaults_MigrateUnitDispelOwnership,
    MSUF_Defaults_NormalizeFontShadowScope = MSUF_Defaults_NormalizeFontShadowScope,
})
local MSUF_Defaults_Stage_SeedShellDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedShellDefaults

--- Dark mode, bar background fill/colour modes, gradients, aggro border,
--- bar mode legacy flags, NPC colour mode, unified bar colour, outline colour.
local MSUF_Defaults_Stage_SeedFontDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedFontDefaults

--- Mouseover highlight, status indicators, boss target highlight, dispel
--- overlay/symbol ownership, obsolete update tuning keys, unit tooltips.
local MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults

--- Castbar colours, per-unit backend + enable flags, cast time formats, boss
--- castbar geometry (physical edge anchor migration), icon/text offsets, sizes.
local sharedBarsDefaults = MSUF.DefaultsStageFactories.Bars({
})
local MSUF_Defaults_Stage_SeedCastbarCoreDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedCastbarCoreDefaults

--- Legacy Auras 1.x key cleanup and the global/per-text font sizes.
local MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes = sharedBarsDefaults.MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes

--- Castbar textures/visuals, width-source normalization, interrupt-ready
--- indicator, per-castbar toggles and detail defaults, focus kick icon.
local MSUF_Defaults_Stage_SeedCastbarDetailDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedCastbarDetailDefaults

--- Bar/background textures, prediction texture validation, HP/power text
--- modes and separators, bar settings scope key.
local MSUF_Defaults_Stage_SeedBarTextureDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedBarTextureDefaults

--- Legacy shared portrait baseline kept as a migration source for the
--- per-unit portrait fields filled in FillUnitDefaults.
local sharedUnitsDefaults = MSUF.DefaultsStageFactories.Units({
    MSUF_DEFAULT_ARENA_OFFSET_X = MSUF_DEFAULT_ARENA_OFFSET_X,
    MSUF_DEFAULT_ARENA_OFFSET_Y = MSUF_DEFAULT_ARENA_OFFSET_Y,
    MSUF_DEFAULT_BOSS_OFFSET_X = MSUF_DEFAULT_BOSS_OFFSET_X,
    MSUF_DEFAULT_BOSS_OFFSET_Y = MSUF_DEFAULT_BOSS_OFFSET_Y,
    MSUF_Defaults_NormalizePortraitClassStyleValue = MSUF_Defaults_NormalizePortraitClassStyleValue,
    MSUF_Defaults_NormalizePortraitRenderValue = MSUF_Defaults_NormalizePortraitRenderValue,
})
local MSUF_Defaults_Stage_SeedPortraitBaselineDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_SeedPortraitBaselineDefaults

--- Power/HP text mode key migration and the one-shot per-unit flattening of
--- inherited HP/Power text settings.
local MSUF_Defaults_Stage_MigrateUnitTextModes = sharedShellDefaults.MSUF_Defaults_Stage_MigrateUnitTextModes

--- Absorb/heal prediction bars, legacy absorb text mode collapse and the v2
--- absorb colour cleanup.
local MSUF_Defaults_Stage_SeedPredictionDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedPredictionDefaults

--- Leader/level/raid group/combat/resting/PvP indicators, the ...Pos ->
--- ...Anchor lift, per-unit raid marker, PvP flag and elite icon defaults.
local function MSUF_Defaults_Stage_SeedStatusIndicatorDefaults(profileDB, g)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_07")
    --- Level indicator offset (global)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_08")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreLevelIndicatorAnchor)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_09")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreRaidGroupNameAnchor)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_10")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreRaidGroupNameStyle)
    --- Misc -> Indicators
    ---
    --- Combat/IncomingRes shipped their anchor as `...Pos` while every other
    --- status indicator uses `...Anchor`. The unitframe status compiler only
    --- reads the `...Anchor` schema (MSUF_UF_Config PrefixedStatusDef), so a
    --- profile carrying a moved `...Pos` was silently rendered at the default
    --- while the menu preview still honoured the old key. Lift the legacy value
    --- once, never overwriting an anchor the user has already set.
    --- One-shot: after this runs, the seeded `...Pos` defaults below must not be
    --- lifted again, or every later login would materialize an explicit anchor
    --- where the profile intentionally had none.
    if g._msufStatusPosAnchorMigrated_v1 ~= true then
        g._msufStatusPosAnchorMigrated_v1 = true
        for _, aliasPair in ipairs({
            { "combatStateIndicatorAnchor", "combatStateIndicatorPos" },
            { "incomingResIndicatorAnchor", "incomingResIndicatorPos" },
        }) do
            MSUF_Defaults_CopyIfMissing(g, aliasPair[1], aliasPair[2])
            for _, unitKey in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
                local conf = profileDB[unitKey]
                if type(conf) == "table" then
                    MSUF_Defaults_CopyIfMissing(conf, aliasPair[1], aliasPair[2])
                end
            end
        end
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreShowIncomingResIndicator)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_11")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreCombatStateIndicatorPos)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_12")
    --- Status Icons (Summon / Resting)
    --- These are used by the Unitframe Status element (player/target) and can be overridden per-unit in the Frames menu.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreShowRestingIndicator)
    --- Rested icon defaults (Blizzard animated Zzz)
    --- Requirement: default size 39 and centered above the attached Player portrait.
    --- Only apply when the profile does not already carry explicit values (no regression for users who moved it).
    MSUF.DefaultsSchema.SeedGeneral(g, "base_13")
    if g.restedStateIndicatorOffsetX == nil or type(g.restedStateIndicatorOffsetX) ~= "number" then
        g.restedStateIndicatorOffsetX = -40
    end
    if g.restedStateIndicatorOffsetY == nil or type(g.restedStateIndicatorOffsetY) ~= "number" then
        g.restedStateIndicatorOffsetY = 50
    end
    if g.restedStateIndicatorSize == nil or type(g.restedStateIndicatorSize) ~= "number" or g.restedStateIndicatorSize <= 0 then
        g.restedStateIndicatorSize = 39
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "base_14")
    --- Player indicators (Frames -> Player)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_15")
    local legacyShowRaidMarker = g.showRaidMarker
    for _, key in ipairs({"player","target","focus","targettarget","focustarget","pet", "pettarget","boss", "arena"}) do
        profileDB[key] = profileDB[key] or {}
        if profileDB[key].showRaidMarker == nil and legacyShowRaidMarker ~= nil then
            profileDB[key].showRaidMarker = legacyShowRaidMarker
        end
        MSUF.DefaultsSchema.Fill(profileDB[key], MSUF.DefaultsSchema.Values.CoreShowRaidMarker)
    end
    local legacyRaidMarkerOffsetX = g.raidMarkerOffsetX
    local legacyRaidMarkerOffsetY = g.raidMarkerOffsetY
    local legacyRaidMarkerAnchor  = g.raidMarkerAnchor
        local legacyRaidMarkerSize    = g.raidMarkerSize
    for _, key in ipairs({"player","target","focus","targettarget","focustarget","pet", "pettarget","boss", "arena"}) do
        profileDB[key] = profileDB[key] or {}
        local conf = profileDB[key]
        if conf.raidMarkerOffsetX == nil and legacyRaidMarkerOffsetX ~= nil then
            conf.raidMarkerOffsetX = legacyRaidMarkerOffsetX
        end
        if conf.raidMarkerOffsetY == nil and legacyRaidMarkerOffsetY ~= nil then
            conf.raidMarkerOffsetY = legacyRaidMarkerOffsetY
        end
        if conf.raidMarkerAnchor == nil and legacyRaidMarkerAnchor ~= nil then
            conf.raidMarkerAnchor = legacyRaidMarkerAnchor
        end
        if conf.raidMarkerSize == nil and legacyRaidMarkerSize ~= nil then
            conf.raidMarkerSize = legacyRaidMarkerSize
        end
        if conf.raidMarkerOffsetX == nil then
            if key == "player" then
                conf.raidMarkerOffsetX = 21
            elseif key == "target" then
                conf.raidMarkerOffsetX = -15
            else
                conf.raidMarkerOffsetX = 16
            end
        end
        MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.CoreRaidMarkerOffsetY)
        if conf.raidMarkerAnchor == nil then
            if key == "target" then
                conf.raidMarkerAnchor = "TOPRIGHT"
            else
                conf.raidMarkerAnchor = "TOPLEFT"
            end
        end
        MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.CoreRaidMarkerSize)
    end
--- Hunter Pet Happiness exists again on WoW Forever. Keep the native 24 px
--- visual scale and familiar right-side placement, the same as on Classic Era
--- and TBC, without adding dead fields to Midnight profiles.
if MSUF.Client.SupportsPetHappiness == true then
    profileDB.pet = profileDB.pet or {}
    local pet = profileDB.pet
    MSUF.DefaultsSchema.Fill(pet, MSUF.DefaultsSchema.Values.CoreShowPetHappinessIndicator)
end

if IS_CLASSIC_FAMILY then
    profileDB.pet = profileDB.pet or {}
    local pet = profileDB.pet
    MSUF.DefaultsSchema.Fill(pet, MSUF.DefaultsSchema.Values.CoreShowPetXPBar)
end

--- PvP flag defaults (per-unit). Arena opponents are always PvP-flagged, so
--- the indicator ships disabled there; the control stays available.
for _, key in ipairs({"player","target","focus","targettarget","focustarget","arena"}) do
        profileDB[key] = profileDB[key] or {}
        local conf = profileDB[key]
    if conf.showPvpIndicator == nil then conf.showPvpIndicator = (key ~= "arena") end
        MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.CorePvpIndicatorSize)
    end
    --- Elite / Rare icon defaults (per-unit)
    for _, key in ipairs({"target","focus","targettarget","focustarget","boss", "arena"}) do
        profileDB[key] = profileDB[key] or {}
        local u = profileDB[key]
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreShowEliteIcon)
        --- TOPRIGHT attaches matching corners. +18 places the 18 px icon flush
        --- outside the frame edge, clear of HP/power text and top aura rows.
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreEliteIconOffsetX)
    end
end

--- MSUF_DB.bars: power bar switches, class power shape, detached power bar
--- texture retirement, Player HP bar, rounded frames, outline thickness.
local MSUF_Defaults_Stage_SeedBarsTableDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedBarsTableDefaults

--- MSUF_DB.gameplay: combat timer, combat state text, crosshair, melee
--- range spell storage.
local MSUF_Defaults_Stage_SeedGameplayDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedGameplayDefaults

--- Auras3 root, group aura factory seeding, custom display/container tables,
--- Blizzard aura frame split, debuff type border mode, defensive shape, filters.
local function MSUF_Defaults_Stage_SeedAuraDefaults(profileDB)
    --- Auras3 defaults (new installs / reset profile). A value that is not a
    --- table (a corrupt or hand-edited import) is replaced the same way, and a
    --- per-unit owner that is not a table is dropped so the runtime never
    --- indexes a scalar owner.
    if type(profileDB.auras3) ~= "table" then
        profileDB.auras3 = MSUF_Defaults_CreateCanonicalUnitAuras()
    end
    if type(profileDB.auras3.perUnit) == "table" then
        for unit, owner in pairs(profileDB.auras3.perUnit) do
            if type(owner) ~= "table" then profileDB.auras3.perUnit[unit] = nil end
        end
    end
    --- Group Aura defaults use the same explicit native factory as profile
    --- reset. Only truly Aura-empty scopes are initialized here; an old flat
    --- or nested payload remains unmarked so Profiles.lua can hard-cut it once
    --- while preserving its visible lane size/position.
    local canonicalGroupAuras = MSUF_Defaults_CreateCanonicalGroupAuraState()
    for i = 1, #MSUF_DEFAULTS_GROUP_AURA_SCOPES do
        local scope = MSUF_DEFAULTS_GROUP_AURA_SCOPES[i]
        local conf = type(profileDB[scope]) == "table" and profileDB[scope] or {}
        profileDB[scope] = conf
        local hasAuraPayload = type(conf.auras) == "table"
            or type(conf.privateAuras) == "table" or type(conf.spellIndicators) == "table"
            or conf.aurasEnabled ~= nil or conf.auraMaxIcons ~= nil or conf.auraIconSize ~= nil
            or conf.auraAnchor ~= nil or conf.auraGrowthX ~= nil or conf.auraGrowthY ~= nil
            or conf.auraSpacing ~= nil or conf.auraPerRow ~= nil
            or conf.privateAurasEnabled ~= nil or conf.privateAuraMax ~= nil
            or conf.privateAuraSize ~= nil or conf.privateAuraAnchor ~= nil
            or conf.privateAuraX ~= nil or conf.privateAuraY ~= nil
            or conf.privateAuraCountdown ~= nil or conf._auraMigV2 ~= nil
        local state = canonicalGroupAuras and canonicalGroupAuras[scope]
        if not hasAuraPayload and type(state) == "table" then
            conf.auras = state.auras
            conf.privateAuras = state.privateAuras
            conf.spellIndicators = state.spellIndicators
        end
    end
    --- Auras3: PTR 5 restored the native IMPORTANT filter. Keep the old split
    --- migration marker, but no longer overwrite the per-lane values on load.
    if profileDB and profileDB.auras3 then
        local a3 = profileDB.auras3
        if type(a3.customDisplays) ~= "table" then a3.customDisplays = {} end
        if type(a3.customDisplays.shared) ~= "table" then a3.customDisplays.shared = { items = {} } end
        if type(a3.customDisplays.shared.items) ~= "table" then a3.customDisplays.shared.items = {} end
        if type(a3.customDisplays.perUnit) ~= "table" then a3.customDisplays.perUnit = {} end
        if type(a3.customDisplays.serial) ~= "number" then a3.customDisplays.serial = 0 end
        if type(a3.customContainers) ~= "table" then a3.customContainers = {} end
        if type(a3.customContainers.perUnit) ~= "table" then a3.customContainers.perUnit = {} end
        if type(a3.shared) ~= "table" then a3.shared = {} end
        --- The first local version exposed one combined Blizzard Aura switch.
        --- Split that stored choice once so testers keep the same result while
        --- Buff and Debuff visibility become independently configurable.
        --- Not adopted on Classic: no Classic build ever wrote the combined key,
        --- and the aura menu model performs the same split where it does appear.
        if not IS_CLASSIC_FAMILY and a3.shared.hideBlizzardAuraFrames ~= nil then
            if a3.shared.hideBlizzardBuffFrame == nil then
                a3.shared.hideBlizzardBuffFrame = a3.shared.hideBlizzardAuraFrames == true
            end
            if a3.shared.hideBlizzardDebuffFrame == nil then
                a3.shared.hideBlizzardDebuffFrame = a3.shared.hideBlizzardAuraFrames == true
            end
            a3.shared.hideBlizzardAuraFrames = nil
        end
        local legacyAuraModel = tonumber(a3.profileModelRevision) ~= MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
        if legacyAuraModel and a3.shared._msufA3_debuffTypeBorderModeMigrated_v1 ~= true then
            if a3.shared.useDebuffTypeBorders == true then
                a3.shared.debuffTypeBorderMode = "SYMBOL"
            elseif a3.shared.debuffTypeBorderMode == nil then
                a3.shared.debuffTypeBorderMode = "OFF"
            end
            a3.shared._msufA3_debuffTypeBorderModeMigrated_v1 = true
        end
        --- Defaults revision 10: Player Defensives icons follow the frame
        --- portrait. Profiles predating the shared Appearance products fell
        --- back to RECTANGLE inside the portrait replacement, so the shape is
        --- seeded exactly once; a stored choice (including an explicit
        --- Rectangular) stays authoritative afterwards.
        if (tonumber(profileDB._msufDefaultsRevision) or 0) < MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION then
            a3.shared._msufA3_factoryDefensiveShape_v1 = nil
            local shapes = type(a3.shared.appearanceIconShapes) == "table" and a3.shared.appearanceIconShapes or {}
            a3.shared.appearanceIconShapes = shapes
            MSUF.DefaultsSchema.Fill(shapes, MSUF.DefaultsSchema.Values.CorePlayerDefensives)
        end

        local function EnsureImportantSplit(f)
            if not f then return end
            f.buffs = (type(f.buffs) == "table") and f.buffs or {}
            f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
            local b, d = f.buffs, f.debuffs

            --- One-time migration: legacy onlyImportantAuras is retired.
            if f._msufA3_onlyImportantSplitMigrated_v1 ~= true then
                f.onlyImportantAuras = false
                f._msufA3_onlyImportantSplitMigrated_v1 = true
            end

            f.onlyImportantAuras = false
        end

        if legacyAuraModel then
            if type(a3.shared.filters) == "table" then
                EnsureImportantSplit(a3.shared.filters)
            end
            if type(a3.perUnit) == "table" then
                for _, pu in pairs(a3.perUnit) do
                    if type(pu) == "table" and type(pu.filters) == "table" then
                        EnsureImportantSplit(pu.filters)
                    end
                end
            end
        end
    end
end

--- Unit-frame geometry/text defaults: the long fill() section, plus the player
--- castbar tick keys and the ToT inline-name keys. The helper only fills nil
--- fields, so saved user choices survive even when new defaults are added for
--- later versions.
local MSUF_Defaults_Stage_FillUnitFrameDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_FillUnitFrameDefaults

--- One-shot boss layout migration plus the range-fade keys for every
--- non-player unit.
local MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade = sharedUnitsDefaults.MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade

--- Per-unit power bar defaults seeded from the legacy shared bars table, plus
--- the one-shot detached power border migration.
local MSUF_Defaults_Stage_SeedUnitPowerBarDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_SeedUnitPowerBarDefaults

--- Per-unit enabled/ownership state, fill animation, unified alpha, OOC fade
--- and the decorative texture layers.
local function MSUF_Defaults_Stage_SeedUnitStateDefaults(profileDB)
    for _, unitKey in ipairs({"player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena"}) do
        profileDB[unitKey] = profileDB[unitKey] or {}
        local u = profileDB[unitKey]
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreEnabled)
        -- Blizzard ownership is independent from the MSUF enabled state:
        -- both frames may coexist, or MSUF can be disabled while Blizzard stays.
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreUseBlizzardFrame)
        --- Per-unitframe: smooth health fill animation (matches Group Frames default).
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreSmoothFill)
        --- Not adopted on Classic: its profiles have never stored this key and
        --- the config compile reads a missing one as off.
        if not IS_CLASSIC_FAMILY and u.chunkedFill == nil then
            u.chunkedFill = false
        end
        --- Unified alpha: HP fill opacity + power fill opacity + background texture
        --- opacity + a toggle to keep text/portrait opaque. Legacy combat/layered keys
        --- are wiped once by the _msufAlphaUnified_v1 migration below.
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreHpBarAlpha)
        if u.powerBarBgAlpha == nil then u.powerBarBgAlpha = u.hpBgAlpha or 0.85 end
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreAlphaExcludeTextPortrait)
        --- Out-of-combat fade: whole-frame alpha while out of combat (min-composed
        --- with range fade at runtime; strongest fade wins). Off by default.
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreOocFadeEnabled)
        --- Decorative texture layers (3 slots, Blizzard name-bar style):
        --- SharedMedia texture per slot with own alpha, strata/level, anchor
        --- target, color/gradient modes, blend, mirroring, edge softness,
        --- combat visibility and rounded clipping. Applied purely cold path.
        --- The source, size and link keys below exist only on Classic: the
        --- texture layer runtime resolves a missing one from the older rule,
        --- so Midnight and WoW Forever profiles keep the key set they have.
        if IS_CLASSIC_FAMILY then
            MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.CoreTexLayerLinkGeometry)
        end
        for _, texP in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
            if u[texP .. "Enabled"] == nil then u[texP .. "Enabled"] = false end
            if u[texP .. "Atlas"] == nil then u[texP .. "Atlas"] = "" end
            if u[texP .. "Texture"] == nil then u[texP .. "Texture"] = "" end
            if u[texP .. "CustomTexturePath"] == nil then u[texP .. "CustomTexturePath"] = "" end
            if IS_CLASSIC_FAMILY and u[texP .. "SourceMode"] == nil then
                local sourcePath = tostring(u[texP .. "CustomTexturePath"] or "")
                local sourceAtlas = tostring(u[texP .. "Atlas"] or "")
                if sourceAtlas ~= "" then
                    u[texP .. "SourceMode"] = "ATLAS"
                elseif sourcePath:find("^Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\TextureLayers\\") then
                    u[texP .. "SourceMode"] = "PACK"
                elseif sourcePath ~= "" then
                    u[texP .. "SourceMode"] = "CUSTOM"
                else
                    u[texP .. "SourceMode"] = "SHAREDMEDIA"
                end
            end
            if u[texP .. "Alpha"] == nil then u[texP .. "Alpha"] = 1 end
            if u[texP .. "FollowFrameAlpha"] == nil then u[texP .. "FollowFrameAlpha"] = true end
            if u[texP .. "Strata"] == nil then u[texP .. "Strata"] = "AUTO" end
            if u[texP .. "Level"] == nil then u[texP .. "Level"] = 1 end
            if u[texP .. "AnchorTarget"] == nil then u[texP .. "AnchorTarget"] = "FRAME" end
            if u[texP .. "Anchor"] == nil then u[texP .. "Anchor"] = "TOP" end
            if u[texP .. "OffsetX"] == nil then u[texP .. "OffsetX"] = 0 end
            if u[texP .. "OffsetY"] == nil then u[texP .. "OffsetY"] = 0 end
            if IS_CLASSIC_FAMILY then
                if u[texP .. "ResponsiveSize"] == nil then u[texP .. "ResponsiveSize"] = false end
                if u[texP .. "SizeMode"] == nil then
                    u[texP .. "SizeMode"] = u[texP .. "ResponsiveSize"] == true and "FRAME" or "MANUAL"
                end
                if u[texP .. "EdgeAttach"] == nil then u[texP .. "EdgeAttach"] = "FREE" end
            end
            if u[texP .. "Width"] == nil then u[texP .. "Width"] = 0 end
            if u[texP .. "Height"] == nil then u[texP .. "Height"] = 16 end
            if u[texP .. "ColorMode"] == nil then u[texP .. "ColorMode"] = "CUSTOM" end
            if u[texP .. "ColorTreatment"] == nil then u[texP .. "ColorTreatment"] = "ORIGINAL" end
            if u[texP .. "ColorR"] == nil then u[texP .. "ColorR"] = 1 end
            if u[texP .. "ColorG"] == nil then u[texP .. "ColorG"] = 1 end
            if u[texP .. "ColorB"] == nil then u[texP .. "ColorB"] = 1 end
            if u[texP .. "GradientEnabled"] == nil then u[texP .. "GradientEnabled"] = false end
            if u[texP .. "Gradient2R"] == nil then u[texP .. "Gradient2R"] = 0 end
            if u[texP .. "Gradient2G"] == nil then u[texP .. "Gradient2G"] = 0 end
            if u[texP .. "Gradient2B"] == nil then u[texP .. "Gradient2B"] = 0 end
            --- Bars-style multi-direction gradient: independent per-edge toggles.
            if u[texP .. "GradientDirRight"] == nil then u[texP .. "GradientDirRight"] = true end
            if u[texP .. "GradientDirLeft"] == nil then u[texP .. "GradientDirLeft"] = false end
            if u[texP .. "GradientDirUp"] == nil then u[texP .. "GradientDirUp"] = false end
            if u[texP .. "GradientDirDown"] == nil then u[texP .. "GradientDirDown"] = false end
            if u[texP .. "BlendMode"] == nil then u[texP .. "BlendMode"] = "BLEND" end
            if u[texP .. "MirrorH"] == nil then u[texP .. "MirrorH"] = false end
            if u[texP .. "MirrorV"] == nil then u[texP .. "MirrorV"] = false end
            if u[texP .. "CropMode"] == nil then u[texP .. "CropMode"] = "FULL" end
            if u[texP .. "EdgeSoftness"] == nil then u[texP .. "EdgeSoftness"] = 0 end
            if u[texP .. "Visibility"] == nil then u[texP .. "Visibility"] = "ALWAYS" end
            if u[texP .. "RoundedClip"] == nil then u[texP .. "RoundedClip"] = false end
        end
    end
end

--- Per-unit portrait defaults. Legacy shared/override portrait profiles are
--- flattened once (v4.324 note below), so this runs after the unit tables exist.
local MSUF_Defaults_Stage_SeedUnitPortraitDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_SeedUnitPortraitDefaults

--- Legacy/unit defaults, split per domain and run in this order. The portrait
--- stage flattens the unit tables the earlier stages created, so keep it last.
local function MSUF_Defaults_Stage_FillUnitDefaults(profileDB, g, legacyPortraitOverrideState)
    MSUF_Defaults_Stage_FillUnitFrameDefaults(profileDB)
    MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade(profileDB)
    MSUF_Defaults_Stage_SeedUnitPowerBarDefaults(profileDB)
    MSUF_Defaults_Stage_SeedUnitStateDefaults(profileDB)
    MSUF_Defaults_Stage_SeedUnitPortraitDefaults(profileDB, g, legacyPortraitOverrideState)
end

--- One-shot unified alpha migration: wipe the retired combat/layered alpha
--- keys and seed the new fill/background alphas across unit and group confs.
local MSUF_Defaults_Stage_MigrateUnifiedAlpha = sharedUnitsDefaults.MSUF_Defaults_Stage_MigrateUnifiedAlpha


Parts.MSUF_Defaults_Stage_FillUnitDefaults = MSUF_Defaults_Stage_FillUnitDefaults
Parts.MSUF_Defaults_Stage_MigrateUnifiedAlpha = MSUF_Defaults_Stage_MigrateUnifiedAlpha
Parts.MSUF_Defaults_Stage_MigrateUnitTextModes = MSUF_Defaults_Stage_MigrateUnitTextModes
Parts.MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes = MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes
Parts.MSUF_Defaults_Stage_SeedAuraDefaults = MSUF_Defaults_Stage_SeedAuraDefaults
Parts.MSUF_Defaults_Stage_SeedBarTextureDefaults = MSUF_Defaults_Stage_SeedBarTextureDefaults
Parts.MSUF_Defaults_Stage_SeedBarsTableDefaults = MSUF_Defaults_Stage_SeedBarsTableDefaults
Parts.MSUF_Defaults_Stage_SeedCastbarCoreDefaults = MSUF_Defaults_Stage_SeedCastbarCoreDefaults
Parts.MSUF_Defaults_Stage_SeedCastbarDetailDefaults = MSUF_Defaults_Stage_SeedCastbarDetailDefaults
Parts.MSUF_Defaults_Stage_SeedFontDefaults = MSUF_Defaults_Stage_SeedFontDefaults
Parts.MSUF_Defaults_Stage_SeedGameplayDefaults = MSUF_Defaults_Stage_SeedGameplayDefaults
Parts.MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults = MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults
Parts.MSUF_Defaults_Stage_SeedPortraitBaselineDefaults = MSUF_Defaults_Stage_SeedPortraitBaselineDefaults
Parts.MSUF_Defaults_Stage_SeedPredictionDefaults = MSUF_Defaults_Stage_SeedPredictionDefaults
Parts.MSUF_Defaults_Stage_SeedShellDefaults = MSUF_Defaults_Stage_SeedShellDefaults
Parts.MSUF_Defaults_Stage_SeedStatusIndicatorDefaults = MSUF_Defaults_Stage_SeedStatusIndicatorDefaults
