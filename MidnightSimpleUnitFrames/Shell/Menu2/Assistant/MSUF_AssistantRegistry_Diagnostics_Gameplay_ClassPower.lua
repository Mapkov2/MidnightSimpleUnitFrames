-- Assistant Class Resource gameplay diagnostic helper.
-- Loaded before MSUF_AssistantRegistry_Diagnostics_Gameplay.lua; keeps class-resource checks separate from gameplay helper checks.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildClassPowerDiagnostic(ctx)
    if type(ctx) ~= "table" then return nil end

    local BarsDB = ctx.BarsDB
    local UnitDB = ctx.UnitDB
    local AddFixChoice = ctx.AddFixChoice
    local AppendFixChoices = ctx.AppendFixChoices
    local LowOpacity = ctx.LowOpacity

    if type(BarsDB) ~= "function" or type(UnitDB) ~= "function" then return nil end
    if type(AddFixChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return nil end
    if type(LowOpacity) ~= "function" then return nil end

    local function ClassPowerDiagnosticText()
        local bars = BarsDB()
        local player = UnitDB("player")
        local issues = {}
        local choices = {}
        if bars.showClassPower == false then
            issues[#issues + 1] = "Class Resources are disabled. Say 'turn on class resources' to enable them."
            AddFixChoice(choices, "bars.showClassPower", true, "Turn on Class Resources")
        end
        if tonumber(bars.classPowerHeight) ~= nil and tonumber(bars.classPowerHeight) < 1 then
            issues[#issues + 1] = "Class Resource height is extremely small. Say 'set class resource height to 4'."
            AddFixChoice(choices, "bars.classPowerHeight", 4, "Set Class Resource height to 4")
        end
        if (bars.classPowerWidthMode == "custom" or bars.classPowerWidthMode == "manual") and (tonumber(bars.classPowerWidth) or 0) <= 0 then
            issues[#issues + 1] = "Class Resource width mode is custom but width is zero. Set a width or use player/cooldown width mode."
            AddFixChoice(choices, "bars.classPowerWidth", 120, "Set Class Resource width to 120")
            AddFixChoice(choices, "bars.classPowerWidthMode", "player", "Use Player width mode for Class Resources")
        end
        if LowOpacity(bars.classPowerFilledAlpha) and LowOpacity(bars.classPowerEmptyAlpha) then
            issues[#issues + 1] = "Filled and empty Class Resource opacity are both near zero."
            AddFixChoice(choices, "bars.classPowerFilledAlpha", 1, "Set Class Resource filled opacity to 100%")
            AddFixChoice(choices, "bars.classPowerEmptyAlpha", 0.3, "Set Class Resource empty opacity to 30%")
        elseif LowOpacity(bars.classPowerFilledAlpha) then
            issues[#issues + 1] = "Filled Class Resource opacity is near zero."
            AddFixChoice(choices, "bars.classPowerFilledAlpha", 1, "Set Class Resource filled opacity to 100%")
        end
        if bars.classPowerHideOOC == true then
            issues[#issues + 1] = "Class Resources hide out of combat by setting."
            AddFixChoice(choices, "bars.classPowerHideOOC", false, "Turn off Class Resource Hide Out of Combat")
        end
        if bars.classPowerHideWhenFull == true and bars.classPowerHideWhenEmpty == true then
            issues[#issues + 1] = "Class Resources are configured to hide when full and when empty."
            AddFixChoice(choices, "bars.classPowerHideWhenFull", false, "Turn off Class Resource Hide When Full")
            AddFixChoice(choices, "bars.classPowerHideWhenEmpty", false, "Turn off Class Resource Hide When Empty")
        elseif bars.classPowerHideWhenFull == true then
            issues[#issues + 1] = "Class Resources hide when full by setting."
            AddFixChoice(choices, "bars.classPowerHideWhenFull", false, "Turn off Class Resource Hide When Full")
        elseif bars.classPowerHideWhenEmpty == true then
            issues[#issues + 1] = "Class Resources hide when empty by setting."
            AddFixChoice(choices, "bars.classPowerHideWhenEmpty", false, "Turn off Class Resource Hide When Empty")
        end
        if player.powerBarDetached == true then
            issues[#issues + 1] = "Player power bar is detached. If it should align with Class Resources, check detached power sync/anchor settings."
        end

        local lines = {
            "Class Resources diagnostic:",
            "Enabled: " .. (bars.showClassPower == false and "off" or "on"),
            "Height: " .. tostring(bars.classPowerHeight or "default"),
            "Width mode: " .. tostring(bars.classPowerWidthMode or "player"),
            "Width: " .. tostring(bars.classPowerWidth or "auto"),
            "Hide rules: OOC=" .. tostring(bars.classPowerHideOOC == true) .. ", full=" .. tostring(bars.classPowerHideWhenFull == true) .. ", empty=" .. tostring(bars.classPowerHideWhenEmpty == true),
        }
        if #issues == 0 then
            lines[#lines + 1] = "Class Resource options look OK. Some specs have no class-resource bar until the relevant resource exists."
        else
            for i = 1, #issues do lines[#lines + 1] = issues[i] end
        end
        return AppendFixChoices(table.concat(lines, "\n"), choices)
    end

    return {
        ClassPowerDiagnosticText = ClassPowerDiagnosticText,
    }
end
