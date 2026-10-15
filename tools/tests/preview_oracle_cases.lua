-- Explicit input matrix. Defaults are supplied by the loaded addon, never by a replacement painter.
local Cases = {}

function Cases.For(client)
    local cases = {
        { id = "unit-player-default", surface = "unit", unit = "player" },
        { id = "unit-target-styled", surface = "unit", unit = "target", style = "portrait" },
        { id = "unit-player-native-portrait", surface = "unit", unit = "player", style = "portrait", portrait = "2D", live = true },
        { id = "unit-pet-status", surface = "unit", unit = "pet", status = "all" },
        { id = "unit-player-resources", surface = "unit", unit = "player", resource = "rogue_combo" },
        { id = "unit-player-layers-hidden", surface = "unit", unit = "player", hidden = true },
        { id = "unit-player-animation", surface = "unit", unit = "player", animated = true, resource = "rogue_combo" },
        { id = "group-party-default", surface = "group", scope = "party" },
        { id = "group-party-portrait-auras", surface = "group", scope = "party", style = "portrait", auras = true },
        { id = "group-raid-default", surface = "group", scope = "raid" },
        { id = "group-party-layers-hidden", surface = "group", scope = "party", hidden = true },
        { id = "castbar-player-normal", surface = "castbar", unit = "player", castType = "normal", progress = 0.37 },
        { id = "castbar-target-channel", surface = "castbar", unit = "target", castType = "channel", progress = 0.63, style = "cast" },
        { id = "castbar-player-interrupt", surface = "castbar", unit = "player", castType = "normal", interrupted = true, progress = 0.37 },
        { id = "classpower-combo-circle", surface = "classpower", resource = "rogue_combo", shape = "CIRCLE" },
        { id = "classpower-combo-bar-hidden", surface = "classpower", resource = "rogue_combo", shape = "BAR", hidden = true },
    }
    if client.SupportsUnit("boss1") then
        cases[#cases + 1] = { id = "unit-boss-default", surface = "unit", unit = "boss" }
    end
    if client.SupportsUnit("arena1") then
        cases[#cases + 1] = { id = "unit-arena-detached", surface = "unit", unit = "arena", style = "cast" }
    end
    if client.HasEmpoweredCasts then
        cases[#cases + 1] = { id = "castbar-player-empower", surface = "castbar", unit = "player", castType = "empower", progress = 0.68 }
        cases[#cases + 1] = { id = "classpower-shadow-continuous", surface = "classpower", resource = "priest_shadow", shape = "BAR" }
    end
    return cases
end

function Cases.Configure(mw, case)
    local db, core = mw.env.MSUF_DB, mw.core
    local bars, general = db.bars, db.general
    core.GF.EnsureDB()
    if case.live then mw.env.UnitExists = function(unit) return unit == "player" end end
    general.classPowerPreviewAnimate = false
    if case.resource then
        bars.showClassPower, bars.classPowerShowText = true, true
        bars.classPowerWidthMode, bars.classPowerWidth = "custom", 183
        bars.classPowerHeight, bars.classPowerGap = 11, 3
        bars.classPowerShape = case.shape or "CIRCLE"
        mw.M._msuf2ClassPowerPreviewSpecKey = case.resource
    end
    if case.style == "portrait" then
        local conf = case.surface == "group" and core.GF.GetConf(case.scope) or db[case.unit]
        conf.portraitMode, conf.portraitRender, conf.portraitShape = "LEFT", case.portrait or "CLASS", "CIRCLE"
        conf.portraitBorderStyle, conf.portraitSizeOverride = "CLASS_COLOR", 43
        conf.powerBarDetached, conf.powerBarDetachedWidth, conf.powerBarDetachedHeight = true, 157, 8
        conf.width, conf.height = 263, 47
        general.healthGradientLowR, general.healthGradientLowG, general.healthGradientLowB = 0.17, 0.26, 0.39
        general.healthGradientMidR, general.healthGradientMidG, general.healthGradientMidB = 0.38, 0.57, 0.63
        general.healthGradientHighR, general.healthGradientHighG, general.healthGradientHighB = 0.73, 0.84, 0.96
        general.colorHealthTextByHealth = true
    end
    if case.style == "cast" then
        general.castbarShowIcon, general.castbarTargetShowIcon = true, true
        general.castbarPlayerIconOffsetX, general.castbarTargetIconOffsetX = -22, -25
        general.castbarPlayerTimeOffsetX, general.castbarTargetTimeOffsetX = 7, 13
        general.castbarShowChannelTicks, general.castbarChannelTickCount = true, 3
        general.castbarTargetWidth, general.castbarTargetHeight = 243, 19
        if case.unit == "arena" then
            general.arenaCastbarDetached, general.arenaCastOffsetX, general.arenaCastOffsetY = true, 21, -37
        end
    end
    if case.auras then
        local conf = core.GF.GetConf(case.scope)
        conf.auras = conf.auras or {}
        conf.auras.renderer = "CUSTOM"
        conf.trackedBuffMax = 3
    end
    core.UF.Config.Refresh()
    if core.GF then core.GF.InvalidateCompiledSpecs(case.scope or "party") end
end

return Cases
