-- Assistant gameplay-oriented diagnostics.
-- Loaded before MSUF_AssistantRegistry_Diagnostics.lua; the main diagnostics registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildGameplayDiagnostic(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local Menu = ctx.M or M
    local BarsDB = ctx.BarsDB
    local GameplayDB = ctx.GameplayDB
    local UnitDB = ctx.UnitDB
    local AddFixChoice = ctx.AddFixChoice
    local AddActionChoice = ctx.AddActionChoice
    local AppendFixChoices = ctx.AppendFixChoices
    local LowOpacity = ctx.LowOpacity

    if type(BarsDB) ~= "function" or type(GameplayDB) ~= "function" or type(UnitDB) ~= "function" then return nil end
    if type(AddFixChoice) ~= "function" or type(AddActionChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return nil end
    if type(LowOpacity) ~= "function" then return nil end

    local BuildClassPowerDiagnostic = A.DiagnosticsRegistry.BuildClassPowerDiagnostic
    local ClassPowerDiagnostic = type(BuildClassPowerDiagnostic) == "function" and BuildClassPowerDiagnostic({
        BarsDB = BarsDB,
        UnitDB = UnitDB,
        AddFixChoice = AddFixChoice,
        AppendFixChoices = AppendFixChoices,
        LowOpacity = LowOpacity,
    }) or {}
    local ClassPowerDiagnosticText = ClassPowerDiagnostic.ClassPowerDiagnosticText

    local BuildDashboardSetupDiagnostic = A.DiagnosticsRegistry.BuildDashboardSetupDiagnostic
    local DashboardSetupDiagnostic = type(BuildDashboardSetupDiagnostic) == "function" and BuildDashboardSetupDiagnostic({
        A = Assistant,
        M = Menu,
        AddActionChoice = AddActionChoice,
        AppendFixChoices = AppendFixChoices,
    }) or {}
    local DashboardSetupDiagnosticText = DashboardSetupDiagnostic.DashboardSetupDiagnosticText

    local function OnOff(value)
        return value == true and "on" or "off"
    end

    local function GameplayFeatureLabel(feature)
        if feature == "combatTimer" then return "Combat Timer" end
        if feature == "combatState" then return "Combat Enter/Leave Text" end
        if feature == "playerTotems" then return "Totem Frame" end
        if feature == "combatCrosshair" then return "Combat Crosshair" end
        return "Gameplay features"
    end

    local function GameplayDiagnosticText(feature)
        local g = GameplayDB()
        feature = tostring(feature or "all")
        local focus = feature ~= "all" and feature or nil
        local lines = {
            "Gameplay feature check:",
            "Focused feature: " .. GameplayFeatureLabel(focus or "all"),
            "Combat Timer: " .. OnOff(g.enableCombatTimer) .. ", size=" .. tostring(g.combatFontSize or 24) .. ", anchor=" .. tostring(g.combatTimerAnchor or "none"),
            "Combat Enter/Leave Text: " .. OnOff(g.enableCombatStateText) .. ", size=" .. tostring(g.combatStateFontSize or 24) .. ", duration=" .. tostring(g.combatStateDuration or 1.5),
            "Totem Frame: " .. OnOff(g.enablePlayerTotems) .. ", icon size=" .. tostring(g.playerTotemsIconSize or 24),
            "Combat Crosshair: " .. OnOff(g.enableCombatCrosshair) .. ", size=" .. tostring(g.crosshairSize or 40) .. ", thickness=" .. tostring(g.crosshairThickness or 3) .. ", melee spell=" .. tostring(g.nameplateMeleeSpellID or 0),
        }
        local issues = {}
        local choices = {}

        if focus == "combatTimer" then
            if g.enableCombatTimer ~= true then
                issues[#issues + 1] = "Combat Timer is disabled. It only appears when enabled and combat timing is active."
                AddFixChoice(choices, "gameplay.enableCombatTimer", true, "Turn on Combat Timer")
            end
            if tonumber(g.combatFontSize) ~= nil and tonumber(g.combatFontSize) < 10 then
                issues[#issues + 1] = "Combat Timer text size is extremely small."
                AddFixChoice(choices, "gameplay.combatFontSize", 24, "Set Combat Timer size to 24")
            end
        elseif focus == "combatState" then
            if g.enableCombatStateText ~= true then
                issues[#issues + 1] = "Combat enter/leave text is disabled."
                AddFixChoice(choices, "gameplay.enableCombatStateText", true, "Turn on Combat enter/leave text")
            end
            if tonumber(g.combatStateDuration) ~= nil and tonumber(g.combatStateDuration) <= 0 then
                issues[#issues + 1] = "Combat enter/leave duration is zero or negative."
                AddFixChoice(choices, "gameplay.combatStateDuration", 1.5, "Set Combat enter/leave duration to 1.5")
            end
            if tonumber(g.combatStateFontSize) ~= nil and tonumber(g.combatStateFontSize) < 10 then
                issues[#issues + 1] = "Combat enter/leave text size is extremely small."
                AddFixChoice(choices, "gameplay.combatStateFontSize", 24, "Set Combat enter/leave text size to 24")
            end
        elseif focus == "playerTotems" then
            if g.enablePlayerTotems ~= true then
                issues[#issues + 1] = "Totem Frame is disabled. It is only useful for classes or states with totems/statues."
                AddFixChoice(choices, "gameplay.enablePlayerTotems", true, "Turn on Totem Frame")
            end
            if tonumber(g.playerTotemsIconSize) ~= nil and tonumber(g.playerTotemsIconSize) < 8 then
                issues[#issues + 1] = "Totem Frame icon size is extremely small."
                AddFixChoice(choices, "gameplay.playerTotemsIconSize", 24, "Set Totem Frame icon size to 24")
            end
        elseif focus == "combatCrosshair" then
            if g.enableCombatCrosshair ~= true then
                issues[#issues + 1] = "Combat Crosshair is disabled."
                AddFixChoice(choices, "gameplay.enableCombatCrosshair", true, "Turn on Combat Crosshair")
            end
            if tonumber(g.crosshairSize) ~= nil and tonumber(g.crosshairSize) < 20 then
                issues[#issues + 1] = "Combat Crosshair size is extremely small."
                AddFixChoice(choices, "gameplay.crosshairSize", 40, "Set Combat Crosshair size to 40")
            end
            if tonumber(g.crosshairThickness) ~= nil and tonumber(g.crosshairThickness) < 1 then
                issues[#issues + 1] = "Combat Crosshair thickness is zero."
                AddFixChoice(choices, "gameplay.crosshairThickness", 3, "Set Combat Crosshair thickness to 3")
            end
            if g.enableCombatCrosshairMeleeRangeColor == true and (tonumber(g.nameplateMeleeSpellID) or 0) <= 0 then
                issues[#issues + 1] = "Crosshair range color is on but no melee range spell is set. Use 'set crosshair spell to 12345' with a real spell ID."
            end
        else
            local enabledCount = 0
            if g.enableCombatTimer == true then enabledCount = enabledCount + 1 end
            if g.enableCombatStateText == true then enabledCount = enabledCount + 1 end
            if g.enablePlayerTotems == true then enabledCount = enabledCount + 1 end
            if g.enableCombatCrosshair == true then enabledCount = enabledCount + 1 end
            lines[#lines + 1] = "Enabled optional features: " .. tostring(enabledCount) .. " of 4."
            if enabledCount == 0 then
                issues[#issues + 1] = "All optional Gameplay features are off. That is valid if you do not use them; ask me to check a feature such as 'check combat timer' if one should be visible."
            end
        end

        if #issues == 0 then
            lines[#lines + 1] = "Gameplay options look OK. Some features only appear in combat, with a matching class/spec, or when the related gameplay event exists."
        else
            for i = 1, #issues do lines[#lines + 1] = issues[i] end
        end
        AddActionChoice(choices, "open_page", { page = "gameplay", label = "Gameplay" }, "Open Gameplay page", "Opens the Gameplay page for review.")
        return AppendFixChoices(table.concat(lines, "\n"), choices)
    end

    return {
        ClassPowerDiagnosticText = ClassPowerDiagnosticText,
        DashboardSetupDiagnosticText = DashboardSetupDiagnosticText,
        GameplayDiagnosticText = GameplayDiagnosticText,
    }
end
