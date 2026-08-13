-- Assistant diagnostics frame visibility checks.
-- Loaded before MSUF_AssistantRegistry_Diagnostics.lua; builds cold diagnostic text helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildFrameDiagnostics(ctx)
    if type(ctx) ~= "table" then return nil end

    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local UnitDB = ctx.UnitDB
    local GroupDB = ctx.GroupDB
    local LowOpacity = ctx.LowOpacity
    local AddFixChoice = ctx.AddFixChoice
    local AppendFixChoices = ctx.AppendFixChoices

    if type(UnitDB) ~= "function" or type(GroupDB) ~= "function" then return nil end
    if type(LowOpacity) ~= "function" or type(AddFixChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return nil end

    local function UnitDefaultWidth(unit)
        if unit == "boss" or unit == "focus" then return 180 end
        return 275
    end

    local function UnitDefaultHeight(unit)
        if unit == "boss" or unit == "focus" then return 30 end
        return 40
    end

    local function GroupDefaultWidth(scope)
        return scope == "party" and 120 or 80
    end

    local function GroupDefaultHeight(scope)
        return scope == "party" and 40 or 32
    end

    local function UnitLabel(unit)
        if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
        local label = UNIT_LABELS[unit]
        if label ~= nil and tostring(label) ~= "" then return tostring(label) end
        if unit == "targettarget" then return "Target of Target" end
        if unit == "focustarget" then return "Focus Target" end
        return tostring(unit or "Unit Frame")
    end

    local function GroupLabel(scope)
        if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
        if scope == "mythicraid" then return "Mythic Raid" end
        if scope == "raid" then return "Raid" end
        if scope == "party" then return "Party" end
        return UnitLabel(scope)
    end

    local function CommandSubject(key, label)
        key = tostring(key or "")
        if key == "targettarget" then return "target of target" end
        if key == "focustarget" then return "focus target" end
        if key == "mythicraid" then return "mythic raid" end
        label = tostring(label or key)
        if label == "" then return "player" end
        return label:lower()
    end

    local LOAD_CONDITION_FIXES = {
        { key = "loadCondHideInHousing", label = "Hide in Housing" },
        { key = "loadCondHideInCombat", label = "Hide in Combat" },
        { key = "loadCondHideInGroup", label = "Hide in Group" },
        { key = "loadCondHideInInstance", label = "Hide in Instance" },
        { key = "loadCondHideInVehicle", label = "Hide in Vehicle" },
        { key = "loadCondHideMounted", label = "Hide Mounted" },
        { key = "loadCondHideNoTarget", label = "Hide with No Target" },
        { key = "loadCondHideOutOfCombat", label = "Hide Out of Combat" },
        { key = "loadCondHideOutOfCombatNoTarget", label = "Hide Out of Combat with No Target" },
        { key = "loadCondHideResting", label = "Hide Resting" },
        { key = "loadCondHideSolo", label = "Hide Solo" },
        { key = "loadCondHideStealthed", label = "Hide Stealthed" },
    }

    local function UnitFrameDiagnosticText(unit)
        unit = UNIT_LABELS[unit] and unit or "player"
        local conf = UnitDB(unit)
        local label = UnitLabel(unit)
        local subject = CommandSubject(unit, label)
        local issues = {}
        local choices = {}
        if conf.enabled == false then
            issues[#issues + 1] = label .. " frame is disabled. Say 'show " .. subject .. " frame' to enable it."
            AddFixChoice(choices, unit .. ".enabled", true, "Show " .. label .. " frame")
        end
        local width = tonumber(conf.width)
        local height = tonumber(conf.height)
        if width ~= nil and width < 10 then
            issues[#issues + 1] = label .. " width is extremely small. Say 'make " .. subject .. " width " .. tostring(UnitDefaultWidth(unit)) .. "'."
            AddFixChoice(choices, unit .. ".width", UnitDefaultWidth(unit), "Set " .. label .. " width to " .. tostring(UnitDefaultWidth(unit)))
        end
        if height ~= nil and height < 6 then
            issues[#issues + 1] = label .. " height is extremely small. Say 'make " .. subject .. " height " .. tostring(UnitDefaultHeight(unit)) .. "'."
            AddFixChoice(choices, unit .. ".height", UnitDefaultHeight(unit), "Set " .. label .. " height to " .. tostring(UnitDefaultHeight(unit)))
        end
        if LowOpacity(conf.hpBarAlpha) then
            issues[#issues + 1] = label .. " HP bar opacity is near zero. It may be hard to see. Set HP bar opacity back to 100%."
            AddFixChoice(choices, unit .. ".hpBarAlpha", 1, "Set " .. label .. " HP bar opacity to 100%")
        end
        for i = 1, #LOAD_CONDITION_FIXES do
            local spec = LOAD_CONDITION_FIXES[i]
            if conf[spec.key] == true then
                issues[#issues + 1] = label .. " has load condition '" .. spec.label .. "' enabled; the frame can hide when that condition matches."
                AddFixChoice(choices, unit .. "." .. spec.key, false, "Turn off " .. label .. " " .. spec.label)
            end
        end
        if unit == "pet" then
            issues[#issues + 1] = "Pet frames also require an active pet; this diagnostic only checks MSUF options."
        elseif unit == "targettarget" then
            issues[#issues + 1] = "Target of Target only appears when your target has a target."
        elseif unit == "focustarget" then
            issues[#issues + 1] = "Focus Target only appears when your focus has a target."
        elseif unit == "boss" then
            issues[#issues + 1] = "Boss frames also require boss units from the encounter or preview context."
        end
        if #issues == 0 then
            return label .. " frame is enabled in MSUF and has no obvious hidden-size or opacity problem. Open " .. label .. " settings or Edit Mode to inspect position."
        end
        return AppendFixChoices(table.concat(issues, "\n"), choices)
    end

    local function GroupFrameDiagnosticText(scope)
        scope = scope == "mythicraid" and "mythicraid" or (scope == "raid" and "raid" or "party")
        local conf = GroupDB(scope)
        local label = GroupLabel(scope)
        local subject = CommandSubject(scope, label)
        local issues = {}
        local choices = {}
        if conf.enabled ~= true then
            issues[#issues + 1] = label .. " Group Frames are disabled. Say 'show " .. subject .. " group frames' to enable them."
            AddFixChoice(choices, "gf_" .. scope .. ".enabled", true, "Show " .. label .. " group frames")
        end
        if scope == "party" and conf.showSolo ~= true then
            issues[#issues + 1] = "Party frames are set to hide while solo. This is normal outside a group unless Show while Solo is enabled."
            AddFixChoice(choices, "gf_party.showSolo", true, "Show Party frames while solo")
        end
        local width = tonumber(conf.width)
        local height = tonumber(conf.height)
        if width ~= nil and width < 10 then
            issues[#issues + 1] = label .. " frame width is extremely small. Say 'make " .. subject .. " width " .. tostring(GroupDefaultWidth(scope)) .. "'."
            AddFixChoice(choices, "gf_" .. scope .. ".width", GroupDefaultWidth(scope), "Set " .. label .. " frame width to " .. tostring(GroupDefaultWidth(scope)))
        end
        if height ~= nil and height < 6 then
            issues[#issues + 1] = label .. " frame height is extremely small. Say 'make " .. subject .. " height " .. tostring(GroupDefaultHeight(scope)) .. "'."
            AddFixChoice(choices, "gf_" .. scope .. ".height", GroupDefaultHeight(scope), "Set " .. label .. " frame height to " .. tostring(GroupDefaultHeight(scope)))
        end
        if LowOpacity(conf.hpBarAlpha) then
            issues[#issues + 1] = label .. " HP bar opacity is near zero. It may be hard to see. Set HP bar opacity back to 100%."
            AddFixChoice(choices, "gf_" .. scope .. ".hpBarAlpha", 1, "Set " .. label .. " HP bar opacity to 100%")
        end
        if conf.hideInClientScene == true then
            issues[#issues + 1] = label .. " frames hide during client scenes by setting; that only applies during those scenes."
            AddFixChoice(choices, "gf_" .. scope .. ".hideInClientScene", false, "Turn off " .. label .. " Hide During Client Scene")
        end
        if #issues == 0 then
            return label .. " Group Frames are enabled and have no obvious hidden-size or opacity problem. Open Group Frames or Edit Mode to inspect position and current group context."
        end
        return AppendFixChoices(table.concat(issues, "\n"), choices)
    end

    return {
        GroupFrameDiagnosticText = GroupFrameDiagnosticText,
        UnitFrameDiagnosticText = UnitFrameDiagnosticText,
    }
end
