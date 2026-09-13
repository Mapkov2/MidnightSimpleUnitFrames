-- Shared units defaults. Client-specific policy is bound once, outside gameplay paths.
local _, MSUF = ...
MSUF.DefaultsStageFactories = MSUF.DefaultsStageFactories or {}
MSUF.DefaultsStageFactories.Units = function(dependencies)
local MSUF_DEFAULT_ARENA_OFFSET_X = dependencies.MSUF_DEFAULT_ARENA_OFFSET_X
local MSUF_DEFAULT_ARENA_OFFSET_Y = dependencies.MSUF_DEFAULT_ARENA_OFFSET_Y
local MSUF_DEFAULT_BOSS_OFFSET_X = dependencies.MSUF_DEFAULT_BOSS_OFFSET_X
local MSUF_DEFAULT_BOSS_OFFSET_Y = dependencies.MSUF_DEFAULT_BOSS_OFFSET_Y
local MSUF_Defaults_NormalizePortraitClassStyleValue = dependencies.MSUF_Defaults_NormalizePortraitClassStyleValue
local MSUF_Defaults_NormalizePortraitRenderValue = dependencies.MSUF_Defaults_NormalizePortraitRenderValue
local function MSUF_Defaults_Stage_SeedPortraitBaselineDefaults(profileDB, g)
    --- Legacy portrait baseline. Kept only as a migration source for older profiles;
    --- runtime and Unit Frame options use per-unit portrait fields directly.
    if g.portraitShape == nil then g.portraitShape = "SQUARE" end
    if g.portraitSizeOverride == nil then g.portraitSizeOverride = 0 end
    if g.portraitPlacement == nil then g.portraitPlacement = "ATTACHED" end
    if g.portraitWidth == nil then g.portraitWidth = 0 end
    if g.portraitHeight == nil then g.portraitHeight = 0 end
    if g.portraitSizeMode ~= "UNIFORM" and g.portraitSizeMode ~= "SEPARATE" then
        if (tonumber(g.portraitSizeOverride) or 0) > 0 then
            g.portraitSizeMode = "UNIFORM"
        elseif (tonumber(g.portraitWidth) or 0) > 0 or (tonumber(g.portraitHeight) or 0) > 0 then
            g.portraitSizeMode = "SEPARATE"
        else
            g.portraitSizeMode = "UNIFORM"
        end
    end
    if g.portraitDetachedPoint == nil then g.portraitDetachedPoint = "RIGHT" end
    if g.portraitDetachedTo == nil then g.portraitDetachedTo = "LEFT" end
    if g.portraitLevelOffset == nil then g.portraitLevelOffset = 7 end
    if g.portraitOverlayAlign == nil then g.portraitOverlayAlign = "LEFT" end
    if g.portraitAlpha == nil then g.portraitAlpha = 100 end
    if g.portraitPanX == nil then g.portraitPanX = 0 end
    if g.portraitPanY == nil then g.portraitPanY = 0 end
    if g.portraitOffsetX == nil then g.portraitOffsetX = 0 end
    if g.portraitOffsetY == nil then g.portraitOffsetY = 0 end
    if g.portraitZoom == nil then g.portraitZoom = 100 end
    if g.portraitBorderStyle == nil then g.portraitBorderStyle = "NONE" end
    if g.portraitEdgeSoftness == nil then g.portraitEdgeSoftness = 0 end
    if g.portraitBorderThickness == nil then g.portraitBorderThickness = 2 end
    if g.portraitBorderColorR == nil then g.portraitBorderColorR = 1 end
    if g.portraitBorderColorG == nil then g.portraitBorderColorG = 1 end
    if g.portraitBorderColorB == nil then g.portraitBorderColorB = 1 end
    if g.portraitBorderColorA == nil then g.portraitBorderColorA = 1 end
    if g.portraitBgEnabled == nil then g.portraitBgEnabled = false end
    if g.portraitBgColorR == nil then g.portraitBgColorR = 0.05 end
    if g.portraitBgColorG == nil then g.portraitBgColorG = 0.05 end
    if g.portraitBgColorB == nil then g.portraitBgColorB = 0.05 end
    if g.portraitBgColorA == nil then g.portraitBgColorA = 0.85 end
    if g.portraitClassStyle == nil then g.portraitClassStyle = "BLIZZARD" end
    g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    if g.portraitFillBorder == nil then g.portraitFillBorder = false end
    if g.portraitBorderArt == nil then g.portraitBorderArt = "FLAT" end
    if g.portraitBorderDirection == nil then g.portraitBorderDirection = "UP" end
    --- Retired Portrait panel UI state / old shared render value. Kept for imports only.
    if g._portraitScopeKey == nil then g._portraitScopeKey = "shared" end
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
    local function fill(key, defaults)
        profileDB[key] = profileDB[key] or {}
        local t = profileDB[key]
        for k, v in pairs(defaults) do
            if t[k] == nil then
                t[k] = v
            end
        end
    end
    local textDefaults = {
        nameTextMouseover = false,
        hpTextMouseover = false,
        powerTextMouseover = false,
        nameTextMouseoverFadeIn = 0,
        nameTextMouseoverFadeOut = 0,
        hpTextMouseoverFadeIn = 0,
        hpTextMouseoverFadeOut = 0,
        powerTextMouseoverFadeIn = 0,
        powerTextMouseoverFadeOut = 0,
        nameTextAnchor = "TOPLEFT",
        nameOffsetX   = 7,
        nameOffsetY   = -4,
        hpOffsetX     = -2,
        hpOffsetY     = -18,
        powerOffsetX  = -6,
        powerOffsetY  = 2,
        powerFontSize = 10,
        textLeft      = "NONE",
        textCenter    = "NONE",
        textRight     = "CURPERCENT",
        hpTextMode    = "CURPERCENT",
        healthTextDecimals = false,
        hpAbsorbIcon = false,
        hpTextLeftOffsetX = 0,
        hpTextLeftOffsetY = 0,
        hpTextCenterOffsetX = 0,
        hpTextCenterOffsetY = 0,
        hpTextRightOffsetX = 0,
        hpTextRightOffsetY = 0,
        powerTextLeft   = "NONE",
        powerTextCenter = "NONE",
        powerTextRight  = "CURRENT",
        powerTextLeftOffsetX = 0,
        powerTextLeftOffsetY = 0,
        powerTextCenterOffsetX = 0,
        powerTextCenterOffsetY = 0,
        powerTextRightOffsetX = 0,
        powerTextRightOffsetY = 0,
        nameTextLayer = 5,
        hpTextLayer = 5,
        powerTextLayer = 2,
        showRaidGroupInName = false,
        raidGroupNameAnchor = "NAMERIGHT",
        raidGroupNameOffsetX = 3,
        raidGroupNameOffsetY = 0,
        raidGroupNameStyle = "PAREN",
    }
    fill("player", {
        width     = 275,
        height    = 40,
        offsetX   = -256,
        offsetY   = -180,
        portraitMode = "LEFT",
        portraitClassStyle = "BLIZZARD",
        showName  = false,
        showLevelIndicator = false,
        showHP    = true,
        showPower = true,
        showPowerText = true,
        powerFontSize = 12,
        showInterrupt = true,
        showInterruptSource = false,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        --- (false = normal left->right fill)
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.player[k] == nil then profileDB.player[k] = v end
    end
    --- Player castbar: custom channel tick markers (PLAYER ONLY)
    --- Stored under MSUF_DB.player.castbar.* so it does not touch general castbar settings.
    profileDB.player.castbar = profileDB.player.castbar or {}
    do
        local pc = profileDB.player.castbar
        if pc.channelTickUseCustom == nil then pc.channelTickUseCustom = false end
        if type(pc.channelTickCount) ~= "number" then pc.channelTickCount = 5 end
        -- Retired preview-only keys are intentionally neither seeded nor
        -- cleared: fresh profiles stay clean and existing profiles remain
        -- losslessly compatible with older builds and exports.
        if type(pc.channelTickPosPct) ~= "table" then pc.channelTickPosPct = {} end
    end
    fill("target", {
        width     = 275,
        height    = 40,
        offsetX   = 320,
        offsetY   = -180,
        portraitMode = "RIGHT",
        portraitClassStyle = "BLIZZARD",
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = true,
        showPowerText = true,
        powerFontSize = 12,
        showInterrupt = true,
        showInterruptSource = false,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.target[k] == nil then profileDB.target[k] = v end
    end
    fill("focus", {
        width     = 180,
        height    = 30,
        offsetX   = -260,
        offsetY   = -300,
        portraitMode = "OFF",
        portraitClassStyle = "BLIZZARD",
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = false,
        showPowerText = false,
        showInterrupt = true,
        showInterruptSource = false,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
        --- Focus-only: optional relative anchor for positioning.
        --- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        --- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.focus[k] == nil then profileDB.focus[k] = v end
    end
    fill("targettarget", {
        width     = 180,
        height    = 30,
        offsetX   = 220,
        offsetY   = -300,
        showName  = false,
        showLevelIndicator = false,
        showHP    = true,
        showPower = false,
        showPowerText = false,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    if profileDB.targettarget.showToTInTargetName == nil then profileDB.targettarget.showToTInTargetName = false end
    --- Target-of-Target inline-in-Target separator token (rendered with spaces around it).
    --- Keep the default as the legacy behavior (" | ") by storing the token "|".
    if profileDB.targettarget.totInlineSeparator == nil then profileDB.targettarget.totInlineSeparator = "|" end
    if profileDB.targettarget.totInlineCustomSeparator == nil then profileDB.targettarget.totInlineCustomSeparator = "" end
    if profileDB.targettarget.totInlineColorMode == nil then profileDB.targettarget.totInlineColorMode = "AUTO" end
    for k, v in pairs(textDefaults) do
        if profileDB.targettarget[k] == nil then profileDB.targettarget[k] = v end
    end
    fill("focustarget", {
        enabled   = false,
        width     = 180,
        height    = 30,
        offsetX   = 260,
        offsetY   = 180,
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = false,
        showPowerText = false,
        --- Focus Target is a lightweight child-style frame: no castbar or auras.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.focustarget[k] == nil then profileDB.focustarget[k] = v end
    end
    fill("pet", {
        width     = 220,
        height    = 30,
        offsetX   = -275,
        offsetY   = -250,
        --- Pet-only: optional relative anchor for positioning.
        --- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        --- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = true,
        showPowerText = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.pet[k] == nil then profileDB.pet[k] = v end
    end
    fill("boss", {
        width        = 180,
        height       = 30,
        offsetX      = MSUF_DEFAULT_BOSS_OFFSET_X,
        offsetY      = MSUF_DEFAULT_BOSS_OFFSET_Y,
        spacing      = -96,
        --- Layout mode: "VERTICAL_DOWN" | "VERTICAL_UP" | "HORIZONTAL_RIGHT" | "HORIZONTAL_LEFT"
        --- Kept invertBossOrder for one-shot migration (see below).
        bossLayoutMode = "VERTICAL_DOWN",
        invertBossOrder = false,
        showName     = true,
        showLevelIndicator = false,
        showHP       = true,
        showPower    = false,
        showPowerText = true,
        showInterrupt = true,
        showInterruptSource = false,
        portraitMode = "OFF",
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.boss[k] == nil then profileDB.boss[k] = v end
    end
    fill("arena", {
        width        = 180,
        height       = 30,
        offsetX      = MSUF_DEFAULT_ARENA_OFFSET_X,
        offsetY      = MSUF_DEFAULT_ARENA_OFFSET_Y,
        spacing      = -96,
        --- Arena reuses the boss stacked-container model and its exact key
        --- names (spacing/bossLayoutMode), so the engine delta math, Edit Mode
        --- drag path, and copy-coverage allowlists apply unchanged.
        bossLayoutMode = "VERTICAL_DOWN",
        showName     = true,
        showLevelIndicator = false,
        showHP       = true,
        showPower    = true,
        showPowerText = false,
        showInterrupt = true,
        showInterruptSource = false,
        portraitMode = "OFF",
        reverseFillBars = false,
        verticalFillBars = false,
        powerBarTexture = "",
        powerBarBgTexture = "",
    })
    for k, v in pairs(textDefaults) do
        if profileDB.arena[k] == nil then profileDB.arena[k] = v end
    end
    --- Range fade: castbar/aura follow-fade for arena opponents (off by default).
    if profileDB.arena.rangeFadeCastbar == nil then profileDB.arena.rangeFadeCastbar = false end
    if profileDB.arena.rangeFadeAuras   == nil then profileDB.arena.rangeFadeAuras   = false end
    --- Trinket/CC readiness icon next to each arena frame (secret-safe swipe).
    if profileDB.arena.showTrinket == nil then profileDB.arena.showTrinket = true end

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
    if profileDB.boss.rangeFadeCastbar == nil then profileDB.boss.rangeFadeCastbar = false end
    if profileDB.boss.rangeFadeAuras   == nil then profileDB.boss.rangeFadeAuras   = false end
    if profileDB.general.rangeFadeEnabled == nil then profileDB.general.rangeFadeEnabled = true end
    for _, unitKey in ipairs({ "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena" }) do
        profileDB[unitKey] = profileDB[unitKey] or {}
        if profileDB[unitKey].rangeFadeEnabled == nil then profileDB[unitKey].rangeFadeEnabled = true end
        if profileDB[unitKey].rangeFadeAlpha == nil then profileDB[unitKey].rangeFadeAlpha = 0.4 end
        if profileDB[unitKey].rangeFadeLayerMode == nil then profileDB[unitKey].rangeFadeLayerMode = "frame" end
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
        for _, unitKey in ipairs({"player", "target", "focus", "targettarget", "focustarget", "pet", "boss", "arena"}) do
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
                for _, unitKey in ipairs({"player", "target", "focus", "targettarget", "focustarget", "pet", "boss", "arena"}) do
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
    for _, unitKey in ipairs({"player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena"}) do
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
        PortraitDefault("portraitClassStyle", "BLIZZARD")
        if u.portraitClickable == nil then u.portraitClickable = false end
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
        PortraitDefault("portraitShape", "SQUARE")
        PortraitDefault("portraitSizeOverride", 0)
        --- 6.0: detached/overlay placement, free width+height, art pan and the
        --- per-unit frame level. All default to the pre-6.0 attached square, so
        --- an untouched profile keeps its exact old geometry.
        PortraitDefault("portraitPlacement", "ATTACHED")
        PortraitDefault("portraitWidth", 0)
        PortraitDefault("portraitHeight", 0)
        if u.portraitSizeMode == nil and inferredPortraitSizeMode ~= nil then
            u.portraitSizeMode = inferredPortraitSizeMode
        end
        PortraitDefault("portraitSizeMode", "UNIFORM")
        PortraitDefault("portraitDetachedPoint", "RIGHT")
        PortraitDefault("portraitDetachedTo", "LEFT")
        PortraitDefault("portraitLevelOffset", 7)
        PortraitDefault("portraitOverlayAlign", "LEFT")
        PortraitDefault("portraitAlpha", 100)
        PortraitDefault("portraitPanX", 0)
        PortraitDefault("portraitPanY", 0)
        PortraitDefault("portraitOffsetX", 0)
        PortraitDefault("portraitOffsetY", 0)
        PortraitDefault("portraitZoom", 100)
        PortraitDefault("portraitBorderStyle", "NONE")
        PortraitDefault("portraitEdgeSoftness", 0)
        PortraitDefault("portraitBorderThickness", 2)
        PortraitDefault("portraitBorderColorR", 1)
        PortraitDefault("portraitBorderColorG", 1)
        PortraitDefault("portraitBorderColorB", 1)
        PortraitDefault("portraitBorderColorA", 1)
        PortraitDefault("portraitBgEnabled", false)
        PortraitDefault("portraitBgColorR", 0.05)
        PortraitDefault("portraitBgColorG", 0.05)
        PortraitDefault("portraitBgColorB", 0.05)
        PortraitDefault("portraitBgColorA", 0.85)
        PortraitDefault("portraitFillBorder", false)
        --- 6.0: relief ring art plus the 90-degree direction it is lit from.
        PortraitDefault("portraitBorderArt", "FLAT")
        PortraitDefault("portraitBorderDirection", "UP")
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
            "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena",
            "gf_party", "gf_raid", "gf_mythicraid",
        }) do
            local conf = profileDB[key]
            if type(conf) == "table" then
                for i = 1, #RETIRED_ALPHA_KEYS do
                    conf[RETIRED_ALPHA_KEYS[i]] = nil
                end
                if conf.hpBarAlpha == nil then conf.hpBarAlpha = 1 end
                if conf.powerBarAlpha == nil then conf.powerBarAlpha = 1 end
                if conf.hpBgAlpha == nil then conf.hpBgAlpha = 0.85 end
                if conf.powerBarBgAlpha == nil then conf.powerBarBgAlpha = conf.hpBgAlpha or 0.85 end
                if conf.alphaExcludeTextPortrait == nil then conf.alphaExcludeTextPortrait = false end
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
