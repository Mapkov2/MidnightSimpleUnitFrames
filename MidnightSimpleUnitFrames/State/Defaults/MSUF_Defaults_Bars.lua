-- Shared bars defaults. Client-specific policy is bound once, outside gameplay paths.
local _, MSUF = ...
MSUF.DefaultsStageFactories = MSUF.DefaultsStageFactories or {}
MSUF.DefaultsStageFactories.Bars = function(dependencies)
local function MSUF_Defaults_Stage_SeedCastbarCoreDefaults(profileDB, g)
    if g.castbarInterruptibleColor == nil then
        g.castbarInterruptibleColor = "turquoise"
    end
    if g.castbarNonInterruptibleColor == nil then
        g.castbarNonInterruptibleColor = "red"
    end
    if g.castbarInterruptColor == nil then
        g.castbarInterruptColor = "red"
    end
    if g.playerCastbarOverrideEnabled == nil then
        g.playerCastbarOverrideEnabled = true
    end
    if g.playerCastbarOverrideMode == nil then
        g.playerCastbarOverrideMode = "CLASS" --- "CLASS" or "CUSTOM"
    end
    if g.playerCastbarOverrideR == nil then g.playerCastbarOverrideR = 1 end
    if g.playerCastbarOverrideG == nil then g.playerCastbarOverrideG = 1 end
    if g.playerCastbarOverrideB == nil then g.playerCastbarOverrideB = 1 end
    if g.castbarFillDirection == nil then
        g.castbarFillDirection = "RTL"
    end
    if g.castbarUnifiedFillDirection ~= nil then
        if g.castbarUnifiedDirection == nil then
            g.castbarUnifiedDirection = (g.castbarUnifiedFillDirection == true)
        end
        g.castbarUnifiedFillDirection = nil
    end
    if g.castbarUnifiedDirection == nil then
        g.castbarUnifiedDirection = false
    end
    --- Channeled casts: show spell-specific tick lines (five-line fallback)
    if g.castbarShowChannelTicks == nil then
        g.castbarShowChannelTicks = false
    end
    --- Opposite fill-direction for enemy castbar
    if g.castbarOpositeDirectionTarget == nil then
        g.castbarOpositeDirectionTarget = false
    end
    --- Hide profession/tradeskill casts. isTradeskill is NeverSecret in 12.x, so
    --- this filter also holds for PvP-restricted units.
    if g.castbarHideTradeSkills == nil then
        g.castbarHideTradeSkills = false
    end
    --- Append the pushback/delay of a cast to the spell text ("+0.4").
    if g.castbarShowPushback == nil then
        g.castbarShowPushback = false
    end
    --- GCD/instant-cast bar (12.1 native-duration rebuild in Castbars/MSUF_CastbarGCD.lua).
    --- Opt-in: the v32 factory profile pins showGCDBar = false, and removal-era
    --- profiles carry an explicit false from the old force-disable.
    if g.showGCDBar == nil then
        g.showGCDBar = false
    end
    if g.showGCDBarTime == nil then
        g.showGCDBarTime = true
    end
    if g.showGCDBarSpell == nil then
        g.showGCDBarSpell = true
    end
    if g.empowerColorStages == nil then
        g.empowerColorStages = true
    end
    if g.empowerStageBlink == nil then
        g.empowerStageBlink = true
    end
    if g.empowerStageBlinkTime == nil or type(g.empowerStageBlinkTime) ~= "number" then
        g.empowerStageBlinkTime = 0.25
    end
    if g.enableTargetCastbar == nil then
        g.enableTargetCastbar = true
    end
    if g.enableFocusCastbar == nil then
        g.enableFocusCastbar = true
    end
    if g.enablePlayerCastbar == nil then
        g.enablePlayerCastbar = true
    end
    if g.enableBossCastbar == nil then
        g.enableBossCastbar = true
    end
    if g.enableArenaCastbar == nil then
        g.enableArenaCastbar = true
    end
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
    if g.showPlayerCastTime == nil then
        g.showPlayerCastTime = true
    end
    if g.showTargetCastTime == nil then
        g.showTargetCastTime = true
    end
    if g.showFocusCastTime == nil then
        g.showFocusCastTime = true
    end
    if g.showBossCastTime == nil then
        g.showBossCastTime = true
end
if g.showArenaCastTime == nil then
    g.showArenaCastTime = true
    end
    if g.castbarPlayerTimeFormat == nil then
        g.castbarPlayerTimeFormat = "CURRENT"
    end
    if g.castbarTargetTimeFormat == nil then
        g.castbarTargetTimeFormat = "CURRENT"
    end
    if g.castbarFocusTimeFormat == nil then
        g.castbarFocusTimeFormat = "CURRENT"
    end
    if g.bossCastTimeFormat == nil then
        g.bossCastTimeFormat = "CURRENT"
    end
if g.arenaCastTimeFormat == nil then
    g.arenaCastTimeFormat = "CURRENT"
end
    if g.bossCastbarOffsetX == nil then
        g.bossCastbarOffsetX = 2
    end
    if g.bossCastbarOffsetY == nil then
        g.bossCastbarOffsetY = -46
    end
    if g.bossCastbarWidth == nil then
        g.bossCastbarWidth = 176
    end
    if g.bossCastbarHeight == nil then
        g.bossCastbarHeight = 12
end
--- Arena castbars start on the boss physical edge-anchor model directly:
--- castbar TOP anchors to the frame outline BOTTOM, no legacy conversion.
if g.arenaCastbarOffsetX == nil then
    g.arenaCastbarOffsetX = 2
end
if g.arenaCastbarOffsetY == nil then
    g.arenaCastbarOffsetY = 0
end
if g.arenaCastbarWidth == nil then
    g.arenaCastbarWidth = 176
end
if g.arenaCastbarHeight == nil then
    g.arenaCastbarHeight = 12
    end
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
    if g.castbarShowIcon == nil then
        g.castbarShowIcon = true
    end
    if g.castbarShowSpellName == nil then
        g.castbarShowSpellName = true
    end
    if g.castbarShakeStrength == nil then
        g.castbarShakeStrength = 8   --- pixels; 0 = no movement
    end
    if type(g.castbarInterruptFeedbackDuration) ~= "number" then
        g.castbarInterruptFeedbackDuration = 0.5
    elseif g.castbarInterruptFeedbackDuration < 0 then
        g.castbarInterruptFeedbackDuration = 0
    elseif g.castbarInterruptFeedbackDuration > 5 then
        g.castbarInterruptFeedbackDuration = 5
    end
    if g.castbarSpellNameFontSize == nil then
        g.castbarSpellNameFontSize = 0
    end
    if g.castbarTimeFontSize == nil then
        g.castbarTimeFontSize = 0
    end
    if g.castbarIconOffsetX == nil then
        g.castbarIconOffsetX = 0
    end
    if g.castbarIconOffsetY == nil then
        g.castbarIconOffsetY = 0
    end
    if g.castbarIconZoom == nil then
        g.castbarIconZoom = 100
    end
    if g.castbarTargetOffsetX == nil then
        g.castbarTargetOffsetX = 0
    end
    if g.castbarTargetOffsetY == nil then
        g.castbarTargetOffsetY = -60
    end
    if g.castbarFocusOffsetX == nil then
        g.castbarFocusOffsetX = 2
    end
    if g.castbarFocusOffsetY == nil then
        g.castbarFocusOffsetY = -50
    end
    if g.castbarPlayerOffsetX == nil then
        g.castbarPlayerOffsetX = -2
    end
    if g.castbarPlayerOffsetY == nil then
        g.castbarPlayerOffsetY = -59
    end
    if g.castbarPlayerTimeOffsetX == nil then
        g.castbarPlayerTimeOffsetX = -2
    end
    if g.castbarPlayerTimeOffsetY == nil then
        g.castbarPlayerTimeOffsetY = 0
    end
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
    if g.castbarGlobalWidth == nil then
        g.castbarGlobalWidth = 200   --- Standardbreite
    end
    if g.castbarGlobalHeight == nil then
        g.castbarGlobalHeight = 18   --- StandardhÃƒÂ¶he
    end
    --- Per-castbar default sizes (match Edit Mode preview defaults)
    if g.castbarPlayerBarWidth == nil then g.castbarPlayerBarWidth = 271 end
    if g.castbarPlayerBarHeight == nil then g.castbarPlayerBarHeight = 18 end
    if g.castbarTargetBarWidth == nil then g.castbarTargetBarWidth = 272 end
    if g.castbarTargetBarHeight == nil then g.castbarTargetBarHeight = 18 end
    if g.castbarFocusBarWidth == nil then g.castbarFocusBarWidth = 175 end
    if g.castbarFocusBarHeight == nil then g.castbarFocusBarHeight = 18 end
    if g.castbarPlayerPreviewEnabled == nil then
        g.castbarPlayerPreviewEnabled = true
    end
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
    if g.fontSize == nil then
        g.fontSize = 14
    end
    --- Per-text font sizes (0 means "use global" in some menus, but these are explicit defaults)
    if g.nameFontSize == nil then g.nameFontSize = 14 end
    if g.hpFontSize == nil then g.hpFontSize = 14 end
    if g.powerFontSize == nil then g.powerFontSize = 12 end
    if g.auraFontSize == nil then g.auraFontSize = 25 end
end

local function MSUF_Defaults_Stage_SeedCastbarDetailDefaults(g)
    if g.castbarBackgroundTexture == nil then
        g.castbarBackgroundTexture = "Solid"
    end
    --- Textures (explicit defaults)
    if g.castbarTexture == nil then
        g.castbarTexture = "MSUF Lucent"
    end
    --- Castbar visuals
    if g.castbarShowGlow == nil then
        g.castbarShowGlow = false
    end
    if g.castbarShowSpark == nil then
        g.castbarShowSpark = false
    end
    if g.castbarSparkOverflow == nil then
        g.castbarSparkOverflow = true
    end
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
    if g.kickReadyShowTarget == nil then g.kickReadyShowTarget = false end
    if g.kickReadyShowFocus  == nil then g.kickReadyShowFocus  = false end
    if g.kickReadyShowBoss   == nil then g.kickReadyShowBoss   = false end
if g.kickReadyShowArena  == nil then g.kickReadyShowArena  = false end
    if g.kickReadyStyle      == nil then g.kickReadyStyle      = "border" end
    if g.kickReadySize       == nil then g.kickReadySize       = 8 end
    if g.kickReadyAnchor     == nil then g.kickReadyAnchor     = "RIGHT" end
    if g.kickReadyOffsetX    == nil then g.kickReadyOffsetX    = 4 end
    if g.kickReadyOffsetY    == nil then g.kickReadyOffsetY    = 0 end
    if g.kickReadyColor      == nil then g.kickReadyColor      = { ["1"] = 0, ["2"] = 1, ["3"] = 0 } end
    if g.kickNotReadyColor   == nil then g.kickNotReadyColor   = { ["1"] = 1, ["2"] = 0, ["3"] = 0 } end
    --- Per-castbar toggles + offsets
    if g.castbarTargetShowIcon == nil then g.castbarTargetShowIcon = true end
    if g.castbarFocusShowIcon == nil then g.castbarFocusShowIcon = true end
    if g.castbarPlayerShowIcon == nil then g.castbarPlayerShowIcon = true end
    if g.castbarTargetShowSpellName == nil then g.castbarTargetShowSpellName = true end
    if g.castbarFocusShowSpellName == nil then g.castbarFocusShowSpellName = true end
    if g.castbarPlayerShowSpellName == nil then g.castbarPlayerShowSpellName = true end
    if g.castbarTargetShowTargetName == nil then g.castbarTargetShowTargetName = false end
    if g.castbarFocusShowTargetName == nil then g.castbarFocusShowTargetName = false end
    if g.showBossCastTargetName == nil then g.showBossCastTargetName = false end
    if g.showArenaCastTargetName == nil then g.showArenaCastTargetName = false end
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
    if g.castbarTargetTextOffsetX == nil then g.castbarTargetTextOffsetX = 0 end
    if g.castbarTargetTextOffsetY == nil then g.castbarTargetTextOffsetY = 0 end
    if g.castbarFocusTextOffsetX == nil then g.castbarFocusTextOffsetX = 0 end
    if g.castbarFocusTextOffsetY == nil then g.castbarFocusTextOffsetY = 0 end
    if g.castbarPlayerTextOffsetX == nil then g.castbarPlayerTextOffsetX = 0 end
    if g.castbarPlayerTextOffsetY == nil then g.castbarPlayerTextOffsetY = 0 end
    if g.castbarTargetIconOffsetX == nil then g.castbarTargetIconOffsetX = 0 end
    if g.castbarTargetIconOffsetY == nil then g.castbarTargetIconOffsetY = 0 end
    if g.castbarFocusIconOffsetX == nil then g.castbarFocusIconOffsetX = 0 end
    if g.castbarFocusIconOffsetY == nil then g.castbarFocusIconOffsetY = 0 end
    if g.castbarPlayerIconOffsetX == nil then g.castbarPlayerIconOffsetX = 0 end
    if g.castbarPlayerIconOffsetY == nil then g.castbarPlayerIconOffsetY = 0 end
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
    if g.showBossCastIcon == nil then g.showBossCastIcon = true end
    if g.showBossCastName == nil then g.showBossCastName = true end
    if g.bossPreviewEnabled == nil then g.bossPreviewEnabled = true end
    if g.bossCastIconOffsetX == nil then g.bossCastIconOffsetX = 0 end
    if g.bossCastIconOffsetY == nil then g.bossCastIconOffsetY = 0 end
    if g.bossCastTextOffsetX == nil then g.bossCastTextOffsetX = 0 end
    if g.bossCastTextOffsetY == nil then g.bossCastTextOffsetY = 0 end
    if g.bossCastTimeOffsetX == nil then g.bossCastTimeOffsetX = 0 end
    if g.bossCastTimeOffsetY == nil then g.bossCastTimeOffsetY = 0 end
    InitCastbarDetailDefaults("bossCast")
    --- Arena castbar UI bits (ArenaCastbars module reads these from general)
    if g.showArenaCastIcon == nil then g.showArenaCastIcon = true end
    if g.showArenaCastName == nil then g.showArenaCastName = true end
    if g.arenaPreviewEnabled == nil then g.arenaPreviewEnabled = true end
    if g.arenaCastIconOffsetX == nil then g.arenaCastIconOffsetX = 0 end
    if g.arenaCastIconOffsetY == nil then g.arenaCastIconOffsetY = 0 end
    if g.arenaCastTextOffsetX == nil then g.arenaCastTextOffsetX = 0 end
    if g.arenaCastTextOffsetY == nil then g.arenaCastTextOffsetY = 0 end
    if g.arenaCastTimeOffsetX == nil then g.arenaCastTimeOffsetX = 0 end
    if g.arenaCastTimeOffsetY == nil then g.arenaCastTimeOffsetY = 0 end
    InitCastbarDetailDefaults("arenaCast")
    --- Focus Kick Icon defaults
    if g.enableFocusKickIcon == nil then g.enableFocusKickIcon = false end
    if g.focusKickShowCastbar == nil then g.focusKickShowCastbar = false end
    if g.focusKickIconWidth == nil then g.focusKickIconWidth = 40 end
    if g.focusKickIconHeight == nil then g.focusKickIconHeight = 40 end
    if g.focusKickIconOffsetX == nil then g.focusKickIconOffsetX = 300 end
    if g.focusKickIconOffsetY == nil then g.focusKickIconOffsetY = 0 end
end

local function MSUF_Defaults_Stage_SeedBarTextureDefaults(g)
    if g.barTexture == nil then
        g.barTexture = "MSUF Lucent"
    end
    if g.barBackgroundTexture == nil then
        g.barBackgroundTexture = "Solid"
    end
    --- Prediction opacity defaults. Texture nil/"" remains a valid explicit
    --- request to follow the foreground texture outside the factory profile.
    if g.absorbBarOpacity == nil then g.absorbBarOpacity = 1 end
    if g.healAbsorbBarOpacity == nil then g.healAbsorbBarOpacity = 1 end
    if g.tempMaxHealthEnabled == nil then g.tempMaxHealthEnabled = false end
    if type(g.tempMaxHealthTexture) ~= "string" then g.tempMaxHealthTexture = "Solid" end
    if g.tempMaxHealthColorR == nil then g.tempMaxHealthColorR = 0.70 end
    if g.tempMaxHealthColorG == nil then g.tempMaxHealthColorG = 0.10 end
    if g.tempMaxHealthColorB == nil then g.tempMaxHealthColorB = 0.10 end
    if g.tempMaxHealthOpacity == nil then g.tempMaxHealthOpacity = 1 end
    if g.tempMaxHealthBackgroundOpacity == nil then g.tempMaxHealthBackgroundOpacity = 0.65 end
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
    local function _MSUF_IsValidStatusbarKey(key)
        if type(key) ~= "string" or key == "" then  return false end
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
            local tex = _G.MSUF_ResolveStatusbarTextureKey(key)
            if type(tex) == "string" and tex ~= "" then
                return true
            end
            return false
        end
        local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
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
    if g.hpTextMode == nil then
        g.hpTextMode = "FULL_PLUS_PERCENT"
    end
    if g.hpTextSeparator == nil then
        g.hpTextSeparator = "-"
    end
    if g.powerTextSeparator == nil then
        g.powerTextSeparator = g.hpTextSeparator
    end
    --- Bar settings scope: always default to Shared so users edit globally first.
    if g.hpPowerTextSelectedKey == nil then
        g.hpPowerTextSelectedKey = "shared"
    end
end

local function MSUF_Defaults_Stage_SeedPredictionDefaults(g)
    if g.enableAbsorbBar == nil then
        g.enableAbsorbBar = true
    end
    g.showTotalAbsorbAmount = false
    if g.showSelfHealPrediction == nil then
        g.showSelfHealPrediction = true
    end
    if g.healPredEnabled == nil then
        g.healPredEnabled = g.showSelfHealPrediction == true
    end
    if g.healPredAnchorMode == nil then
        g.healPredAnchorMode = 3
    end
    if g.healAbsorbEnabled == nil then
        g.healAbsorbEnabled = true
    end
    if g.healAbsorbAnchorMode == nil then g.healAbsorbAnchorMode = 3 end
    if g.healPredictionBarHeight == nil then g.healPredictionBarHeight = 0 end
    if g.healPredictionBarOffsetY == nil then g.healPredictionBarOffsetY = 0 end
    if g.healPredictionBarOpacity == nil then g.healPredictionBarOpacity = g.healPredictionColorA or 0.45 end
    if g.absorbBarHeight == nil then g.absorbBarHeight = 0 end
    if g.absorbBarOffsetY == nil then g.absorbBarOffsetY = 0 end
    if g.healAbsorbBarHeight == nil then g.healAbsorbBarHeight = 0 end
    if g.healAbsorbBarOffsetY == nil then g.healAbsorbBarOffsetY = 0 end

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
    if g.absorbAnchorMode == nil then
        --- 1 = Left Absorb, Right Heal-Absorb; 2 = Right Absorb, Left Heal-Absorb; 3 = Follow HP; 5 = Reverse from max (default)
        g.absorbAnchorMode = 5
    end
    if g.overAbsorbOverlay == nil then
        g.overAbsorbOverlay = true
    end
    if g.fullHealthAbsorbStripe == nil then
        g.fullHealthAbsorbStripe = false
    end

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
    if profileDB.bars.showTargetPowerBar == nil then
        profileDB.bars.showTargetPowerBar = true
    end
    if profileDB.bars.showBossPowerBar == nil then
        profileDB.bars.showBossPowerBar = true
    end
    if profileDB.bars.showArenaPowerBar == nil then profileDB.bars.showArenaPowerBar = true end
    if profileDB.bars.showFocusPowerBar == nil then
        profileDB.bars.showFocusPowerBar = true
    end
    if profileDB.bars.showPlayerPowerBar == nil then
        profileDB.bars.showPlayerPowerBar = true
    end
    if profileDB.bars.showBarBorder == nil then
        profileDB.bars.showBarBorder = true
    end
    if profileDB.bars.powerBarHeight == nil then
        profileDB.bars.powerBarHeight = 3
    end
    if profileDB.bars.smoothPowerBar == nil then
        profileDB.bars.smoothPowerBar = false
    end
    if profileDB.bars.chunkedPowerBar == nil then
        profileDB.bars.chunkedPowerBar = false
    end
    if profileDB.bars.classPowerSmoothFill == nil then
        profileDB.bars.classPowerSmoothFill = profileDB.bars.smoothPowerBar == true
    end
    if profileDB.bars.altManaSmoothFill == nil then
        profileDB.bars.altManaSmoothFill = profileDB.bars.smoothPowerBar == true
    end
    if profileDB.bars.classPowerComboPointColorMode == nil then
        profileDB.bars.classPowerComboPointColorMode = "default"
    end
    if profileDB.bars.classPowerShape == nil then
        profileDB.bars.classPowerShape = "BAR"
    end
    if profileDB.bars.classPowerShapeAlign == nil then
        profileDB.bars.classPowerShapeAlign = "CENTER"
    end
    --- Shared power-bar art for every unit's power bar (detached or not).
    --- Empty = follow the unit's bar texture, which is the historical behavior.
    --- A per-unit powerBarTexture overrides this.
    if profileDB.bars.powerBarTexture == nil then
        profileDB.bars.powerBarTexture = ""
    end
    if profileDB.bars.powerBarBgTexture == nil then
        profileDB.bars.powerBarBgTexture = ""
    end
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
    if profileDB.bars.detachedPowerBarOutline == nil then
        profileDB.bars.detachedPowerBarOutline = 1
    end
    if profileDB.bars.playerHPBarEnabled == nil then
        profileDB.bars.playerHPBarEnabled = false
    end
    if profileDB.bars.playerHPBarAnchor == nil then
        profileDB.bars.playerHPBarAnchor = "CLASS_TOP"
    end
    if profileDB.bars.playerHPBarWidthMode == nil then
        profileDB.bars.playerHPBarWidthMode = "class"
    end
    if profileDB.bars.playerHPBarWidth == nil then
        profileDB.bars.playerHPBarWidth = 0
    end
    if profileDB.bars.playerHPBarHeight == nil then
        profileDB.bars.playerHPBarHeight = 6
    end
    if profileDB.bars.playerHPBarGap == nil then
        profileDB.bars.playerHPBarGap = 2
    end
    if profileDB.bars.playerHPBarOffsetX == nil then
        profileDB.bars.playerHPBarOffsetX = 0
    end
    if profileDB.bars.playerHPBarOffsetY == nil then
        profileDB.bars.playerHPBarOffsetY = 0
    end
    if profileDB.bars.playerHPBarFrameLevelOffset == nil then
        profileDB.bars.playerHPBarFrameLevelOffset = 7
    end
    if profileDB.bars.playerHPBarShape == nil then
        profileDB.bars.playerHPBarShape = "BAR"
    end
    if profileDB.bars.playerHPBarOrbSize == nil then
        profileDB.bars.playerHPBarOrbSize = 54
    end
    if profileDB.bars.playerHPBarTexture == nil then
        profileDB.bars.playerHPBarTexture = ""
    end
    if profileDB.bars.playerHPBarBgTexture == nil then
        profileDB.bars.playerHPBarBgTexture = ""
    end
    if profileDB.bars.playerHPBarBgAlpha == nil then
        profileDB.bars.playerHPBarBgAlpha = 0.35
    end
    if profileDB.bars.playerHPBarOutline == nil then
        profileDB.bars.playerHPBarOutline = 1
    end
    if profileDB.bars.playerHPBarColorMode == nil then
        profileDB.bars.playerHPBarColorMode = "GLOBAL"
    end
    if profileDB.bars.playerHPBarSmoothFill == nil then
        profileDB.bars.playerHPBarSmoothFill = false
    end
    if profileDB.bars.playerHPBarTextEnabled == nil then
        profileDB.bars.playerHPBarTextEnabled = true
    end
    if profileDB.bars.playerHPBarUsePlayerText == nil then
        profileDB.bars.playerHPBarUsePlayerText = true
    end
    if profileDB.bars.playerHPBarTextLeft == nil then
        profileDB.bars.playerHPBarTextLeft = "NONE"
    end
    if profileDB.bars.playerHPBarTextCenter == nil then
        profileDB.bars.playerHPBarTextCenter = "NONE"
    end
    if profileDB.bars.playerHPBarTextRight == nil then
        profileDB.bars.playerHPBarTextRight = "CURPERCENT"
    end
    if profileDB.bars.playerHPBarTextSeparator == nil then
        profileDB.bars.playerHPBarTextSeparator = ""
    end
    if profileDB.bars.playerHPBarTextReverse == nil then
        profileDB.bars.playerHPBarTextReverse = false
    end
    if profileDB.bars.playerHPBarTextSize == nil then
        profileDB.bars.playerHPBarTextSize = 14
    end
    if profileDB.bars.playerHPBarTextOffsetX == nil then
        profileDB.bars.playerHPBarTextOffsetX = 0
    end
    if profileDB.bars.playerHPBarTextOffsetY == nil then
        profileDB.bars.playerHPBarTextOffsetY = 0
    end
    if profileDB.bars.realtimePowerText == nil then
        profileDB.bars.realtimePowerText = true
    end
    if profileDB.bars.roundedFramesEnabled == nil then
        profileDB.bars.roundedFramesEnabled = false
    end
    if profileDB.bars.roundedUnitFrames == nil then
        profileDB.bars.roundedUnitFrames = true
    end
    if profileDB.bars.roundedGroupFrames == nil then
        profileDB.bars.roundedGroupFrames = true
    end
    if profileDB.bars.roundedPowerBars == nil then
        profileDB.bars.roundedPowerBars = true
    end
    if profileDB.bars.roundedCastbars == nil then
        profileDB.bars.roundedCastbars = false
    end
    if profileDB.bars.roundedClassResources == nil then
        profileDB.bars.roundedClassResources = false
    end
    if profileDB.bars.roundedMouseover == nil then
        profileDB.bars.roundedMouseover = true
    end
    if profileDB.bars.roundedCornerStrength == nil then
        profileDB.bars.roundedCornerStrength = 3
    end
    if profileDB.bars.embedPowerBarIntoHealth == nil then
        --- Pixel-perfect default: keep the power bar *inside* the unitframe bounds.
        --- This prevents the power bar from extending below the frame and breaking
        --- pixel-accurate layouts when toggling power bars on.
        --- Users who want the legacy behavior can disable this in Bars.
        profileDB.bars.embedPowerBarIntoHealth = true
    end
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
    if profileDB.bars.barOutlineLayer == nil then
        -- Additive 0..30 FrameLevel offset. Zero preserves legacy outline order.
        profileDB.bars.barOutlineLayer = 0
    end
    if profileDB.bars.barOutlineTexture == nil then
        -- Optional square-frame edgeFile or stretched statusbar texture. Empty
        -- keeps the classic solid-color outline; Rounded Frames ignores both.
        profileDB.bars.barOutlineTexture = ""
    end
    --- Bar background alpha (0..100). Independent from unit alpha in/out of combat.
    if profileDB.bars.barBackgroundAlpha == nil then
        profileDB.bars.barBackgroundAlpha = 90
    end
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
