-- Shared units defaults. Client-specific policy is bound once, outside gameplay paths.
local _, MSUF = ...
MSUF.DefaultsStageFactories = MSUF.DefaultsStageFactories or {}
MSUF.DefaultsStageFactories.Units = function(dependencies)
local MSUF_Defaults_NormalizePortraitClassStyleValue = dependencies.MSUF_Defaults_NormalizePortraitClassStyleValue
local MSUF_Defaults_NormalizePortraitRenderValue = dependencies.MSUF_Defaults_NormalizePortraitRenderValue
local function MSUF_Defaults_Stage_SeedPortraitBaselineDefaults(profileDB, g)
    --- Legacy portrait baseline. Kept only as a migration source for older profiles;
    --- runtime and Unit Frame options use per-unit portrait fields directly.
    MSUF.DefaultsSchema.SeedGeneral(g, "units_01")
    if g.portraitSizeMode ~= "UNIFORM" and g.portraitSizeMode ~= "SEPARATE" then
        if (tonumber(g.portraitSizeOverride) or 0) > 0 then
            g.portraitSizeMode = "UNIFORM"
        elseif (tonumber(g.portraitWidth) or 0) > 0 or (tonumber(g.portraitHeight) or 0) > 0 then
            g.portraitSizeMode = "SEPARATE"
        else
            g.portraitSizeMode = "UNIFORM"
        end
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "units_02")
    g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    MSUF.DefaultsSchema.SeedGeneral(g, "units_03")
    --- Retired Portrait panel UI state / old shared render value. Kept for imports only.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.Units_portraitScopeKey)
    --- Initialize _portraitSharedRender from player's actual render type (migration from old layout)
    if g._portraitSharedRender == nil then
        local pConf = profileDB.player
        if pConf and pConf.portraitRender then
            g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(pConf.portraitRender)
        else
            g._portraitSharedRender = "2D"
        end
    else
        g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
    end
    --- Which unit's portrait settings are currently shown in the Portraits menu (UI state only).
    --- Moved from positional tabs to scope dropdown (Bars pattern).
end

local function MSUF_Defaults_Stage_FillUnitFrameDefaults(profileDB)
    local values = MSUF.DefaultsSchema.Values
    for key, defaults in pairs(values.UnitFrames) do
        profileDB[key] = profileDB[key] or {}
        MSUF.DefaultsSchema.Fill(profileDB[key], defaults)
        MSUF.DefaultsSchema.Fill(profileDB[key], values.UnitText)
    end
    if type(profileDB.player.castbar) ~= "table" then profileDB.player.castbar = {} end
    local pc = profileDB.player.castbar
    MSUF.DefaultsSchema.Fill(pc, MSUF.DefaultsSchema.Values.UnitsChannelTickUseCustom)
    if type(pc.channelTickCount) ~= "number" then pc.channelTickCount = 5 end
    if type(pc.channelTickPosPct) ~= "table" then pc.channelTickPosPct = {} end
    local tot = profileDB.targettarget
    MSUF.DefaultsSchema.Fill(tot, MSUF.DefaultsSchema.Values.UnitsShowToTInTargetName)
    local arena = profileDB.arena
    MSUF.DefaultsSchema.Fill(arena, MSUF.DefaultsSchema.Values.UnitsRangeFadeCastbar004)
end

local function MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade(profileDB)
    --- One-shot migration: old invertBossOrder checkbox - new bossLayoutMode dropdown.
    --- Runs once on first login with v4.0 Beta 5+; converts legacy saved setting.
    if profileDB.boss._bossLayoutMigrated ~= true then
        if profileDB.boss.invertBossOrder == true then
            profileDB.boss.bossLayoutMode = "VERTICAL_UP"
        end
        profileDB.boss._bossLayoutMigrated = true
    end
    --- Range fade: also fade castbar / auras when boss is out of range (off by default).
    MSUF.DefaultsSchema.Fill(profileDB.boss, MSUF.DefaultsSchema.Values.UnitsRangeFadeCastbar)
    MSUF.DefaultsSchema.Fill(profileDB.general, MSUF.DefaultsSchema.Values.UnitsRangeFadeEnabled006)
    for _, unitKey in ipairs({ "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
        profileDB[unitKey] = profileDB[unitKey] or {}
        MSUF.DefaultsSchema.Fill(profileDB[unitKey], MSUF.DefaultsSchema.Values.UnitsRangeFadeEnabled)
    end
end

local function MSUF_Defaults_Stage_SeedUnitPowerBarDefaults(profileDB)
    do
        local bars = profileDB.bars or {}
        local showKeys = {
            player = "showPlayerPowerBar",
            target = "showTargetPowerBar",
            focus  = "showFocusPowerBar",
            boss   = "showBossPowerBar",
            arena  = "showArenaPowerBar",
        }
        for _, unitKey in ipairs({"player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena"}) do
            profileDB[unitKey] = profileDB[unitKey] or {}
            local u = profileDB[unitKey]
            local legacyShowKey = showKeys[unitKey]
            if u.showPowerBar == nil then
                local legacyShow = legacyShowKey and bars[legacyShowKey]
                if legacyShow ~= nil then
                    u.showPowerBar = legacyShow ~= false
                else
                    u.showPowerBar = u.showPower ~= false
                end
            end
            if u.powerBarHeight == nil then
                u.powerBarHeight = tonumber(bars.powerBarHeight) or 3
            end
            if u.embedPowerBarIntoHealth == nil then
                u.embedPowerBarIntoHealth = (bars.embedPowerBarIntoHealth == true)
            end
            if u.powerBarBorderEnabled == nil then
                u.powerBarBorderEnabled = (bars.powerBarBorderEnabled == true)
            end
            if u.powerBarBorderThickness == nil then
                u.powerBarBorderThickness = tonumber(bars.powerBarBorderThickness or bars.powerBarBorderSize) or 1
            end
            if u.powerSmoothFill == nil then
                u.powerSmoothFill = (unitKey == "player") and (bars.smoothPowerBar == true) or false
            end
            if u.powerChunkedFill == nil then
                u.powerChunkedFill = (unitKey == "player") and (bars.chunkedPowerBar == true) or false
            end
            if unitKey == "player" then
                local legacyShape = tostring(u.detachedPowerBarShape or "FOLLOW_CLASS"):upper()
                if legacyShape == "FOLLOW_CLASS" then
                    local classShape = tostring(bars.classPowerShape or "BAR"):upper()
                    if classShape == "CIRCLE" then
                        u.detachedPowerBarShape = "ROUND"
                    elseif classShape == "DIAMOND" or classShape == "HEX" then
                        u.detachedPowerBarShape = "CRYSTAL"
                    else
                        u.detachedPowerBarShape = "BAR"
                    end
                elseif u.detachedPowerBarShape == nil then
                    u.detachedPowerBarShape = "BAR"
                end
                u.detachedPowerBarSeparateShape = nil
            end
            if unitKey == "player" and u.detachedPowerOrbSize == nil then
                u.detachedPowerOrbSize = 54
            end
            if u.powerBarDetached == true and u.detachedPowerBarWidth == nil then
                local syncedClassWidth = unitKey == "player"
                    and u.detachedPowerBarSyncClassPower ~= false
                    and bars.classPowerWidthMode == "custom"
                    and tonumber(bars.classPowerWidth)
                    or nil
                local detachedWidth = (syncedClassWidth and syncedClassWidth >= 20 and syncedClassWidth)
                    or tonumber(u.width)
                    or (unitKey == "focus" and 180 or 275)
                if detachedWidth < 20 then
                    detachedWidth = 20
                elseif detachedWidth > 800 then
                    detachedWidth = 800
                end
                u.detachedPowerBarWidth = detachedWidth
            end
        end
        --- A detached rectangular bar used to draw `bars.detachedPowerBarOutline`
        --- instead of its own power border, which left the unit page's border
        --- toggle and thickness inert. That global now only feeds the Player
        --- Round/Crystal/Orb edge, so carry a customized value over once to keep
        --- existing detached bars looking the same.
        if bars._msufDetachedPowerBorderMigrated_v1 ~= true then
            local legacyOutline = tonumber(bars.detachedPowerBarOutline)
            if legacyOutline and legacyOutline > 0 and legacyOutline ~= 1 then
                for _, unitKey in ipairs({"player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena"}) do
                    local u = profileDB[unitKey]
                    local shape = tostring(u.detachedPowerBarShape or "BAR"):upper()
                    if u.powerBarDetached == true and u.powerBarBorderEnabled ~= true
                        and (unitKey ~= "player" or shape == "BAR") then
                        u.powerBarBorderEnabled = true
                        u.powerBarBorderThickness = legacyOutline > 10 and 10 or legacyOutline
                    end
                end
            end
            bars._msufDetachedPowerBorderMigrated_v1 = true
        end
    end
end

local function MSUF_Defaults_Stage_SeedUnitPortraitDefaults(profileDB, g, legacyPortraitOverrideState)
    for _, unitKey in ipairs({"player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena"}) do
        profileDB[unitKey] = profileDB[unitKey] or {}
        local u = profileDB[unitKey]
        --- Portrait defaults used by the clean UF Portrait element.
        --- v4.324+: portraits are always per-unit. Older shared/override profiles
        --- are flattened once: override=true keeps unit values, non-overrides adopt
        --- the old baseline, then the override marker is retired.
        local flattenLegacyPortrait = legacyPortraitOverrideState and g._msufPortraitPerUnitMigrated_v4324 ~= true
        local useLegacyBaseline = flattenLegacyPortrait and u.portraitDecoOverride ~= true
        local function PortraitDefault(field, fallback)
            local shared = g[field]
            if shared == nil then shared = fallback end
            if useLegacyBaseline then
                u[field] = shared
            elseif u[field] == nil then
                u[field] = shared
            end
        end
        if useLegacyBaseline then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender or g.portraitRender)
        elseif u.portraitRender == nil then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
        else
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(u.portraitRender)
        end
        PortraitDefault("portraitClassStyle", MSUF.DefaultsSchema.Values.UnitPortrait.portraitClassStyle)
        MSUF.DefaultsSchema.Fill(u, MSUF.DefaultsSchema.Values.UnitsPortraitClickable)
        u.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(u.portraitClassStyle)
        local inferredPortraitSizeMode
        if not useLegacyBaseline and u.portraitSizeMode == nil then
            if (tonumber(u.portraitSizeOverride) or 0) > 0 then
                inferredPortraitSizeMode = "UNIFORM"
            elseif (tonumber(u.portraitWidth) or 0) > 0 or (tonumber(u.portraitHeight) or 0) > 0 then
                inferredPortraitSizeMode = "SEPARATE"
            end
        elseif u.portraitSizeMode ~= nil
            and u.portraitSizeMode ~= "UNIFORM" and u.portraitSizeMode ~= "SEPARATE"
        then
            u.portraitSizeMode = nil
        end
        PortraitDefault("portraitShape", MSUF.DefaultsSchema.Values.UnitPortrait.portraitShape)
        PortraitDefault("portraitSizeOverride", MSUF.DefaultsSchema.Values.UnitPortrait.portraitSizeOverride)
        --- 6.0: detached/overlay placement, free width+height, art pan and the
        --- per-unit frame level. All default to the pre-6.0 attached square, so
        --- an untouched profile keeps its exact old geometry.
        PortraitDefault("portraitPlacement", MSUF.DefaultsSchema.Values.UnitPortrait.portraitPlacement)
        PortraitDefault("portraitWidth", MSUF.DefaultsSchema.Values.UnitPortrait.portraitWidth)
        PortraitDefault("portraitHeight", MSUF.DefaultsSchema.Values.UnitPortrait.portraitHeight)
        if u.portraitSizeMode == nil and inferredPortraitSizeMode ~= nil then
            u.portraitSizeMode = inferredPortraitSizeMode
        end
        PortraitDefault("portraitSizeMode", MSUF.DefaultsSchema.Values.UnitPortrait.portraitSizeMode)
        PortraitDefault("portraitDetachedPoint", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDetachedPoint)
        PortraitDefault("portraitDetachedTo", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDetachedTo)
        PortraitDefault("portraitLevelOffset", MSUF.DefaultsSchema.Values.UnitPortrait.portraitLevelOffset)
        PortraitDefault("portraitOverlayAlign", MSUF.DefaultsSchema.Values.UnitPortrait.portraitOverlayAlign)
        PortraitDefault("portraitAlpha", MSUF.DefaultsSchema.Values.UnitPortrait.portraitAlpha)
        PortraitDefault("portraitPanX", MSUF.DefaultsSchema.Values.UnitPortrait.portraitPanX)
        PortraitDefault("portraitPanY", MSUF.DefaultsSchema.Values.UnitPortrait.portraitPanY)
        PortraitDefault("portraitOffsetX", MSUF.DefaultsSchema.Values.UnitPortrait.portraitOffsetX)
        PortraitDefault("portraitOffsetY", MSUF.DefaultsSchema.Values.UnitPortrait.portraitOffsetY)
        PortraitDefault("portraitZoom", MSUF.DefaultsSchema.Values.UnitPortrait.portraitZoom)
        PortraitDefault("portraitFlip", MSUF.DefaultsSchema.Values.UnitPortrait.portraitFlip)
        PortraitDefault("portraitBlizzardDirection", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBlizzardDirection)
        PortraitDefault("portraitInnerShadow", MSUF.DefaultsSchema.Values.UnitPortrait.portraitInnerShadow)
        PortraitDefault("portraitDragonArtwork", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonArtwork)
        PortraitDefault("portraitDragonScale", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonScale)
        PortraitDefault("portraitDragonX", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonX)
        PortraitDefault("portraitDragonY", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonY)
        PortraitDefault("portraitDragonFlip", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonFlip)
        PortraitDefault("portraitDragonInInstances", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonInInstances)
        PortraitDefault("portraitDragonLayer", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonLayer)
        PortraitDefault("portraitDragonLevel", MSUF.DefaultsSchema.Values.UnitPortrait.portraitDragonLevel)
        PortraitDefault("portraitBorderStyle", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderStyle)
        PortraitDefault("portraitEdgeSoftness", MSUF.DefaultsSchema.Values.UnitPortrait.portraitEdgeSoftness)
        PortraitDefault("portraitBorderThickness", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderThickness)
        PortraitDefault("portraitBorderColorR", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderColorR)
        PortraitDefault("portraitBorderColorG", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderColorG)
        PortraitDefault("portraitBorderColorB", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderColorB)
        PortraitDefault("portraitBorderColorA", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderColorA)
        PortraitDefault("portraitBgEnabled", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBgEnabled)
        PortraitDefault("portraitBgColorR", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBgColorR)
        PortraitDefault("portraitBgColorG", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBgColorG)
        PortraitDefault("portraitBgColorB", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBgColorB)
        PortraitDefault("portraitBgColorA", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBgColorA)
        PortraitDefault("portraitFillBorder", MSUF.DefaultsSchema.Values.UnitPortrait.portraitFillBorder)
        PortraitDefault("portraitBorderArt", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderArt)
        PortraitDefault("portraitBorderDirection", MSUF.DefaultsSchema.Values.UnitPortrait.portraitBorderDirection)
        u.portraitDecoOverride = nil
    end
    g._msufPortraitPerUnitMigrated_v4324 = true
end

local function MSUF_Defaults_Stage_MigrateUnifiedAlpha(profileDB, g)
    --- Unified alpha migration (hard reset): the old combat/layered alpha model was
    --- replaced by hpBarAlpha (HP fill) + powerBarAlpha (power fill) + hpBgAlpha
    --- (health background) + powerBarBgAlpha (resource background) +
    --- alphaExcludeTextPortrait.
    --- Wipe every retired key once across all unit and group confs and seed the new
    --- defaults. dead/offline tint (deadBg*) and background RGB (bgR/bgG/bgB) are kept.
    if g._msufAlphaUnified_v1 ~= true then
        local RETIRED_ALPHA_KEYS = {
            "alphaInCombat", "alphaOutOfCombat", "alphaSync", "alphaSyncBoth",
            "alphaLayerMode", "alphaFGInCombat", "alphaFGOutOfCombat",
            "alphaBGInCombat", "alphaBGOutOfCombat", "alphaHPInCombat",
            "alphaHPOutOfCombat", "alphaPreserveHPColor", "bgA", "hpTextIgnoreAlpha",
        }
        for _, key in ipairs({
            "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
            "gf_party", "gf_raid", "gf_mythicraid",
        }) do
            local conf = profileDB[key]
            if type(conf) == "table" then
                for i = 1, #RETIRED_ALPHA_KEYS do
                    conf[RETIRED_ALPHA_KEYS[i]] = nil
                end
                MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.UnitsHpBarAlpha)
                if conf.powerBarBgAlpha == nil then conf.powerBarBgAlpha = conf.hpBgAlpha or 0.85 end
                MSUF.DefaultsSchema.Fill(conf, MSUF.DefaultsSchema.Values.UnitsAlphaExcludeTextPortrait)
            end
        end
        g._msufAlphaUnified_v1 = true
    end
end
return {
    MSUF_Defaults_Stage_SeedPortraitBaselineDefaults = MSUF_Defaults_Stage_SeedPortraitBaselineDefaults,
    MSUF_Defaults_Stage_FillUnitFrameDefaults = MSUF_Defaults_Stage_FillUnitFrameDefaults,
    MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade = MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade,
    MSUF_Defaults_Stage_SeedUnitPowerBarDefaults = MSUF_Defaults_Stage_SeedUnitPowerBarDefaults,
    MSUF_Defaults_Stage_SeedUnitPortraitDefaults = MSUF_Defaults_Stage_SeedUnitPortraitDefaults,
    MSUF_Defaults_Stage_MigrateUnifiedAlpha = MSUF_Defaults_Stage_MigrateUnifiedAlpha,
}
end
