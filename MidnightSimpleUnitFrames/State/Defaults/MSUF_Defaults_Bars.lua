-- Shared bars defaults. Client-specific policy is bound once, outside gameplay paths.
local _, MSUF = ...
MSUF.DefaultsStageFactories = MSUF.DefaultsStageFactories or {}
MSUF.DefaultsStageFactories.Bars = function(dependencies)
local function MSUF_Defaults_Stage_SeedCastbarCoreDefaults(profileDB, g)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_01")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsPlayerCastbarOverrideMode)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_02")
    if g.castbarUnifiedFillDirection ~= nil then
        if g.castbarUnifiedDirection == nil then
            g.castbarUnifiedDirection = (g.castbarUnifiedFillDirection == true)
        end
        g.castbarUnifiedFillDirection = nil
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarUnifiedDirection)
    --- Channeled casts: show spell-specific tick lines (five-line fallback)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_03")
    --- Opposite fill-direction for enemy castbar
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarOpositeDirectionTarget)
    --- Hide profession/tradeskill casts. isTradeskill is NeverSecret in 12.x, so
    --- this filter also holds for PvP-restricted units.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarHideTradeSkills)
    --- Append the pushback/delay of a cast to the spell text ("+0.4").
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarShowPushback)
    --- GCD/instant-cast bar (12.1 native-duration rebuild in Castbars/MSUF_CastbarGCD.lua).
    --- Opt-in: the v32 factory profile pins showGCDBar = false, and removal-era
    --- profiles carry an explicit false from the old force-disable.
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_04")
    if g.empowerStageBlinkTime == nil or type(g.empowerStageBlinkTime) ~= "number" then
        g.empowerStageBlinkTime = 0.25
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_05")
    local function _NormalizeCastbarBackendDefault(value)
        if value == true then return "MSUF" end
        if value == false then return "BLIZZARD" end
        if type(value) ~= "string" then return nil end
        local v = value:upper()
        if v == "MSUF" then return "MSUF" end
        if v == "BLIZZARD" or v == "BLIZZ" or v == "DEFAULT" or v == "SHOW" then return "BLIZZARD" end
        if v == "HIDE" or v == "HIDDEN" or v == "NONE" or v == "DISABLED" then return "HIDE" end
        return nil
    end
    local function _InitCastbarBackend(unit, backendKey, enableKey)
        local backend = _NormalizeCastbarBackendDefault(g[backendKey])
        if not backend then
            backend = (g[enableKey] == false) and ((unit == "player") and "BLIZZARD" or "HIDE") or "MSUF"
        elseif backend == "BLIZZARD" and unit ~= "player" then
            backend = "HIDE"
        end
        g[backendKey] = backend
        g[enableKey] = (backend == "MSUF")
    end
    _InitCastbarBackend("player", "castbarPlayerBackend", "enablePlayerCastbar")
    _InitCastbarBackend("target", "castbarTargetBackend", "enableTargetCastbar")
    _InitCastbarBackend("focus", "castbarFocusBackend", "enableFocusCastbar")
    _InitCastbarBackend("boss", "bossCastbarBackend", "enableBossCastbar")
    _InitCastbarBackend("arena", "arenaCastbarBackend", "enableArenaCastbar")
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_06")
MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsArenaCastTimeFormat)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_07")
--- Arena castbars start on the boss physical edge-anchor model directly:
--- castbar TOP anchors to the frame outline BOTTOM, no legacy conversion.
MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsArenaCastbarOffsetX)
    -- Attached boss castbars now use a stable edge-to-edge anchor: castbar TOP to
    -- the visible boss outline BOTTOM. Convert the legacy TOP-of-container /
    -- BOTTOM-of-castbar offset once, preserving the current on-screen position at
    -- the profile's present boss/castbar heights. Subsequent odd/even boss height
    -- changes then keep a constant physical gap instead of changing pixel phase.
    if g._msufBossCastbarPhysicalEdgeAnchor_v1 ~= true
        and g.bossCastbarDetached ~= true
    then
        local bossHeight = tonumber(profileDB and profileDB.boss and profileDB.boss.height) or 30
        local castbarHeight = tonumber(g.bossCastbarHeight) or 12
        local legacyOffsetY = tonumber(g.bossCastbarOffsetY) or -46
        g.bossCastbarOffsetY = legacyOffsetY + bossHeight + castbarHeight + 4
        g._msufBossCastbarPhysicalEdgeAnchor_v1 = true
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_08")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarShakeStrength)
    if type(g.castbarInterruptFeedbackDuration) ~= "number" then
        g.castbarInterruptFeedbackDuration = 0.5
    elseif g.castbarInterruptFeedbackDuration < 0 then
        g.castbarInterruptFeedbackDuration = 0
    elseif g.castbarInterruptFeedbackDuration > 5 then
        g.castbarInterruptFeedbackDuration = 5
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_09")
    if g.castbarFocusTimeOffsetX == nil then
        g.castbarFocusTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarFocusTimeOffsetY == nil then
        g.castbarFocusTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    if g.castbarTargetTimeOffsetX == nil then
        g.castbarTargetTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarTargetTimeOffsetY == nil then
        g.castbarTargetTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarGlobalWidth)
    --- Per-castbar default sizes (match Edit Mode preview defaults)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_10")
end

local function MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes(g)
    --- Legacy Auras 1.x DB cleanup (Patch 6D Step 2)
    g.targetAuraFilter = nil
    g.targetAuraWidth = nil
    g.targetAuraHeight = nil
    g.targetAuraScale = nil
    g.targetAuraAlpha = nil
    g.targetAuraOffsetX = nil
    g.targetAuraOffsetY = nil
    g.targetAuraDisplay = nil
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsFontSize)
    --- Per-text font sizes (0 means "use global" in some menus, but these are explicit defaults)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_11")
end

local function MSUF_Defaults_Stage_SeedCastbarDetailDefaults(g)
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarBackgroundTexture)
    --- Textures (explicit defaults)
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsCastbarTexture)
    --- Castbar visuals
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_12")
    --- Unit castbar width matching:
    --- nil/"manual" = manual, "unitframe" = own MSUF unitframe,
    --- "essential" = CDM essential row, "utility" = CDM utility bar.
    local function NormalizeCastbarWidthSourceKey(key, legacyUnitWidthKey, aliasKey)
        if aliasKey and g[key] == nil and g[aliasKey] ~= nil then
            g[key] = g[aliasKey]
        end
        if g[key] == nil and legacyUnitWidthKey and g[legacyUnitWidthKey] == true then
            g[key] = "unitframe"
        end
        if g[key] == "manual" then
            g[key] = nil
        elseif g[key] ~= nil
            and g[key] ~= "unitframe"
            and g[key] ~= "essential"
            and g[key] ~= "utility"
        then
            g[key] = nil
        end
    end
    NormalizeCastbarWidthSourceKey("castbarPlayerMatchWidth", "castbarPlayerMatchUnitWidth")
    NormalizeCastbarWidthSourceKey("castbarTargetMatchWidth", "castbarTargetMatchUnitWidth")
    NormalizeCastbarWidthSourceKey("castbarFocusMatchWidth", "castbarFocusMatchUnitWidth")
    NormalizeCastbarWidthSourceKey("bossCastbarMatchWidth", "castbarBossMatchUnitWidth", "castbarBossMatchWidth")
NormalizeCastbarWidthSourceKey("arenaCastbarMatchWidth", "castbarArenaMatchUnitWidth", "castbarArenaMatchWidth")
    --- Interrupt Ready Indicator
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsKickReadyShowTarget)
    if g.kickReadyColor      == nil then g.kickReadyColor      = { ["1"] = 0, ["2"] = 1, ["3"] = 0 } end
    if g.kickNotReadyColor   == nil then g.kickNotReadyColor   = { ["1"] = 1, ["2"] = 0, ["3"] = 0 } end
    --- Per-castbar toggles + offsets
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_13")
    local function InitCastTargetTextDefaults(prefix)
        if g[prefix .. "TargetNamePosition"] == nil then g[prefix .. "TargetNamePosition"] = "BELOW" end
        if g[prefix .. "TargetNameFontSize"] == nil then g[prefix .. "TargetNameFontSize"] = 10 end
        if g[prefix .. "TargetNameAlign"] == nil then g[prefix .. "TargetNameAlign"] = "RIGHT" end
        if g[prefix .. "TargetNameOffsetX"] == nil then g[prefix .. "TargetNameOffsetX"] = 0 end
        if g[prefix .. "TargetNameOffsetY"] == nil then g[prefix .. "TargetNameOffsetY"] = 1 end
    end
    InitCastTargetTextDefaults("castbarTarget")
    InitCastTargetTextDefaults("castbarFocus")
    InitCastTargetTextDefaults("bossCast")
    InitCastTargetTextDefaults("arenaCast")
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_14")
    local function InitCastbarDetailDefaults(prefix)
        if g[prefix .. "FrameLevelOffset"] == nil then g[prefix .. "FrameLevelOffset"] = 6 end
        if g[prefix .. "IconPosition"] == nil then g[prefix .. "IconPosition"] = "LEFT" end
        if g[prefix .. "IconZoom"] == nil then g[prefix .. "IconZoom"] = 100 end
        if g[prefix .. "IconSpacing"] == nil then g[prefix .. "IconSpacing"] = 1 end
        if g[prefix .. "IconBorderThickness"] == nil then
            local style = tostring(g[prefix .. "IconBorderStyle"] or "NONE"):upper()
            if style == "CASTBAR" then
                local thickness = tonumber(g.castbarOutlineThickness) or 1
                g[prefix .. "IconBorderThickness"] = math.max(0, math.min(8, thickness))
            elseif style == "DARK" then
                g[prefix .. "IconBorderThickness"] = 1
            else
                g[prefix .. "IconBorderThickness"] = 0
            end
            -- The thickness slider owns enable/disable from now on. Preserve
            -- legacy NONE visually as thickness 0, then keep DARK ready so
            -- increasing the slider immediately shows a border.
            if style == "NONE" or style == "" then g[prefix .. "IconBorderStyle"] = "DARK" end
        end
        if g[prefix .. "IconBorderStyle"] == nil then g[prefix .. "IconBorderStyle"] = "DARK" end
        if g[prefix .. "SpellNamePosition"] == nil then g[prefix .. "SpellNamePosition"] = "LEFT" end
        if g[prefix .. "SpellNameFont"] == nil then g[prefix .. "SpellNameFont"] = "GLOBAL" end
        if g[prefix .. "SpellNameOutline"] == nil then g[prefix .. "SpellNameOutline"] = "GLOBAL" end
        if g[prefix .. "SpellNameAlign"] == nil then g[prefix .. "SpellNameAlign"] = "LEFT" end
        if g[prefix .. "SpellNameMaxWidth"] == nil then g[prefix .. "SpellNameMaxWidth"] = 0 end
        if g[prefix .. "SpellNameTruncate"] == nil then g[prefix .. "SpellNameTruncate"] = "AUTO" end
        if g[prefix .. "TimePosition"] == nil then g[prefix .. "TimePosition"] = "RIGHT" end
        if g[prefix .. "TimeFont"] == nil then g[prefix .. "TimeFont"] = "GLOBAL" end
        if g[prefix .. "TimeOutline"] == nil then g[prefix .. "TimeOutline"] = "GLOBAL" end
    end
    InitCastbarDetailDefaults("castbarPlayer")
    InitCastbarDetailDefaults("castbarTarget")
    InitCastbarDetailDefaults("castbarFocus")
    --- Boss castbar UI bits (BossCastbars module reads these from general)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_15")
    InitCastbarDetailDefaults("bossCast")
    --- Arena castbar UI bits (ArenaCastbars module reads these from general)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_16")
    InitCastbarDetailDefaults("arenaCast")
    --- Focus Kick Icon defaults
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_17")
end

local function MSUF_Defaults_Stage_SeedBarTextureDefaults(g)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_18")
    --- Prediction opacity defaults. Texture nil/"" remains a valid explicit
    --- request to follow the foreground texture outside the factory profile.
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_19")
    if type(g.tempMaxHealthTexture) ~= "string" then g.tempMaxHealthTexture = "Solid" end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_20")
    if g.absorbBarTexture ~= nil and type(g.absorbBarTexture) ~= "string" then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture ~= nil and type(g.healAbsorbBarTexture) ~= "string" then
        g.healAbsorbBarTexture = nil
    end
    if g.absorbBarTexture == "" then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture == "" then
        g.healAbsorbBarTexture = nil
    end
    --- Best-effort validation: if we can confidently resolve a statusbar key and it fails,
    --- fall back to nil ("follow foreground") so users don't get broken textures after removing SharedMedia packs.
    --- The castbar texture resolver loads after the defaults; a defaults pass
    --- that runs during the core load validates through LibSharedMedia below.
    local function _MSUF_IsValidStatusbarKey(key)
        if type(key) ~= "string" or key == "" then  return false end
        local resolveKey = MSUF.Optional("MSUF_ResolveStatusbarTextureKey")
        if resolveKey then
            local tex = resolveKey(key)
            if type(tex) == "string" and tex ~= "" then
                return true
            end
            return false
        end
        local LSM = (MSUF and MSUF.LSM) or MSUF.PublicGlobals.MSUF_LSM
        if LSM and type(LSM.Fetch) == "function" then
            local tex = LSM:Fetch("statusbar", key, true)
            if type(tex) == "string" and tex ~= "" then
                return true
            end
            return false
        end
        --- Can't validate in this session (no resolver/LSM yet): keep the value to avoid unintended resets.
        return true
    end
    if g.absorbBarTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.absorbBarTexture) then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.healAbsorbBarTexture) then
        g.healAbsorbBarTexture = nil
    end
    if g.tempMaxHealthTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.tempMaxHealthTexture) then
        g.tempMaxHealthTexture = "Solid"
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_21")
    if g.powerTextSeparator == nil then
        g.powerTextSeparator = g.hpTextSeparator
    end
    --- Bar settings scope: always default to Shared so users edit globally first.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsHpPowerTextSelectedKey)
end

local function MSUF_Defaults_Stage_SeedPredictionDefaults(g)
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsEnableAbsorbBar)
    g.showTotalAbsorbAmount = false
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsShowSelfHealPrediction)
    if g.healPredEnabled == nil then
        g.healPredEnabled = g.showSelfHealPrediction == true
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_22")
    if g.healPredictionBarOpacity == nil then g.healPredictionBarOpacity = g.healPredictionColorA or 0.45 end
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_23")

    --- Absorb display is bar-only in 6.0; collapse legacy text modes on load.
    if g.absorbTextMode == nil then
        g.absorbTextMode = 2
        g.enableAbsorbBar = true
    else
        local mode = tonumber(g.absorbTextMode)
        if mode == 1 or mode == 4 then
            g.absorbTextMode = 1
            g.enableAbsorbBar = false
        else
            g.absorbTextMode = 2
            g.enableAbsorbBar = true
        end
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.BarsAbsorbAnchorMode)
    MSUF.DefaultsSchema.SeedGeneral(g, "bars_24")

    --- v2 absorb-colour cleanup. Pre-v2 the colour picker (then in the retired
    --- MSUF_ColorsCore file, now the Menu2 colour pages) wrote to
    --- absorbColor* / healAbsorbColor*, but every reader (UF, GF, Reset) used
    --- the absorbBarColor* / healAbsorbBarColor* keys - so the picker had no
    --- visible effect. The v1 patch tried to migrate by copying old - new,
    --- which surfaced picker-default white into now-live keys and made
    --- absorbs blend into the HP bar. v2 wipes both key sets once, so the
    --- defaults render again until the user explicitly picks a colour via
    --- the (now functional) picker. The marker keeps this idempotent and
    --- preserves any choices made AFTER the marker is set.
    if g.absorbBarColorMigrationV2 ~= true then
        g.absorbBarColorMigrationV2 = true
        g.absorbColorR,        g.absorbColorG,        g.absorbColorB,        g.absorbColorA        = nil, nil, nil, nil
        g.healAbsorbColorR,    g.healAbsorbColorG,    g.healAbsorbColorB,    g.healAbsorbColorA    = nil, nil, nil, nil
        g.absorbBarColorR,     g.absorbBarColorG,     g.absorbBarColorB,     g.absorbBarColorA     = nil, nil, nil, nil
        g.healAbsorbBarColorR, g.healAbsorbBarColorG, g.healAbsorbBarColorB, g.healAbsorbBarColorA = nil, nil, nil, nil
    end
end

local function MSUF_Defaults_Stage_SeedBarsTableDefaults(profileDB)
    if profileDB.bars == nil then
        profileDB.bars = {}
    end
    MSUF.DefaultsSchema.Fill(profileDB.bars, MSUF.DefaultsSchema.Values.BarsShowTargetPowerBar)
    if profileDB.bars.classPowerSmoothFill == nil then
        profileDB.bars.classPowerSmoothFill = profileDB.bars.smoothPowerBar == true
    end
    if profileDB.bars.altManaSmoothFill == nil then
        profileDB.bars.altManaSmoothFill = profileDB.bars.smoothPowerBar == true
    end
    MSUF.DefaultsSchema.Fill(profileDB.bars, MSUF.DefaultsSchema.Values.BarsClassPowerComboPointColorMode)
    --- Shared power-bar art for every unit's power bar (detached or not).
    --- Empty = follow the unit's bar texture, which is the historical behavior.
    --- A per-unit powerBarTexture overrides this.
    MSUF.DefaultsSchema.Fill(profileDB.bars, MSUF.DefaultsSchema.Values.BarsPowerBarTexture)
    --- The Class Resources detached texture keys are retired: the Bars/unit
    --- page power textures own the detached Player bar too. Carry a customized
    --- value over once so an existing detached bar keeps its art, then drop
    --- the stored keys.
    do
        local player = profileDB.player
        local legacyFg = profileDB.bars.detachedPowerBarTexture
        if type(legacyFg) == "string" and legacyFg ~= ""
            and player and player.powerBarDetached == true
            and (player.powerBarTexture == nil or player.powerBarTexture == "") then
            player.powerBarTexture = legacyFg
        end
        local legacyBg = profileDB.bars.detachedPowerBarBgTexture
        if type(legacyBg) == "string" and legacyBg ~= ""
            and player and player.powerBarDetached == true
            and (player.powerBarBgTexture == nil or player.powerBarBgTexture == "") then
            player.powerBarBgTexture = legacyBg
        end
        profileDB.bars.detachedPowerBarTexture = nil
        profileDB.bars.detachedPowerBarBgTexture = nil
    end
    MSUF.DefaultsSchema.Fill(profileDB.bars, MSUF.DefaultsSchema.Values.BarsDetachedPowerBarOutline)
    if profileDB.bars.barOutlineThickness == nil then
        --- New slider-based bar outline. Backwards compatible default:
        --- - If legacy border is off -> 0
        --- - Else map legacy style to a sensible thickness
        local enabled = true
        if profileDB.general and profileDB.general.useBarBorder == false then
            enabled = false
        end
        if profileDB.bars.showBarBorder ~= nil then
            enabled = (profileDB.bars.showBarBorder ~= false)
        end
        if not enabled then
            profileDB.bars.barOutlineThickness = 0
        else
            local style = (profileDB.general and profileDB.general.barBorderStyle) or "THIN"
            local map = { THIN = 2, THICK = 3, SHADOW = 4, GLOW = 4 }
            profileDB.bars.barOutlineThickness = map[style] or 2
        end
    end
    MSUF.DefaultsSchema.Fill(profileDB.bars, MSUF.DefaultsSchema.Values.BarsBarOutlineLayer)
    --- Bar background alpha (0..100). Independent from unit alpha in/out of combat.
    MSUF.DefaultsSchema.Fill(profileDB.bars, MSUF.DefaultsSchema.Values.BarsBarBackgroundAlpha)
end
return {
    MSUF_Defaults_Stage_SeedCastbarCoreDefaults = MSUF_Defaults_Stage_SeedCastbarCoreDefaults,
    MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes = MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes,
    MSUF_Defaults_Stage_SeedCastbarDetailDefaults = MSUF_Defaults_Stage_SeedCastbarDetailDefaults,
    MSUF_Defaults_Stage_SeedBarTextureDefaults = MSUF_Defaults_Stage_SeedBarTextureDefaults,
    MSUF_Defaults_Stage_SeedPredictionDefaults = MSUF_Defaults_Stage_SeedPredictionDefaults,
    MSUF_Defaults_Stage_SeedBarsTableDefaults = MSUF_Defaults_Stage_SeedBarsTableDefaults,
}
end
