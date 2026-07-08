-- Assistant GroupFrames status-icon setting registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; the main settings domain
-- passes the shared helper context and current group scope.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterStatusIconSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local AddGroupStatusIconAliases = ctx.AddGroupStatusIconAliases
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local GROUP_STATUS_ICON_STYLE_VALUES = ctx.GROUP_STATUS_ICON_STYLE_VALUES or {}
    local GROUP_STATUS_ICON_STYLE_ALIASES = ctx.GROUP_STATUS_ICON_STYLE_ALIASES or {}
    local GROUP_STATUS_ICON_PACK_VALUES = ctx.GROUP_STATUS_ICON_PACK_VALUES or {}
    local GROUP_STATUS_ICON_PACK_ALIASES = ctx.GROUP_STATUS_ICON_PACK_ALIASES or {}
    local GROUP_STATUS_ANCHOR_VALUES = ctx.GROUP_STATUS_ANCHOR_VALUES or {}
    local GROUP_STATUS_ANCHOR_ALIASES = ctx.GROUP_STATUS_ANCHOR_ALIASES or {}
    local GROUP_STATUS_ICON_SPECS = ctx.GROUP_STATUS_ICON_SPECS or {}

    if type(AddAliasesForUnit) ~= "function" or type(AddGroupStatusIconAliases) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "default role icon style")
    AddAliasesForUnit(aliases, scope, "role icon style")
    AddAliasesForUnit(aliases, scope, "status icon style")
    AddAliasesForUnit(aliases, scope, "status icons style")
    AddAliasesForUnit(aliases, scope, "group icon style")
    RegisterGroupEnum(scope, "statusIconStyle", "iconStyle", "Default Role Icon Style", "BLIZZARD", GROUP_STATUS_ICON_STYLE_VALUES, GROUP_STATUS_ICON_STYLE_ALIASES, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "midnight status icons")
    AddAliasesForUnit(aliases, scope, "midnight icon style")
    AddAliasesForUnit(aliases, scope, "use midnight icons")
    RegisterGroupBoolean(scope, "useMidnightIcons", "useMidnightIcons", "Use Midnight Status Icons", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon tanks")
    AddAliasesForUnit(aliases, scope, "show role icon for tanks")
    AddAliasesForUnit(aliases, scope, "tank role icon")
    RegisterGroupBoolean(scope, "roleIconShowTank", "roleIconShowTank", "Role Icon for Tanks", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon healers")
    AddAliasesForUnit(aliases, scope, "show role icon for healers")
    AddAliasesForUnit(aliases, scope, "healer role icon")
    RegisterGroupBoolean(scope, "roleIconShowHealer", "roleIconShowHealer", "Role Icon for Healers", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role icon dps")
    AddAliasesForUnit(aliases, scope, "show role icon for dps")
    AddAliasesForUnit(aliases, scope, "dps role icon")
    RegisterGroupBoolean(scope, "roleIconShowDPS", "roleIconShowDPS", "Role Icon for DPS", true, "visual", aliases)

    local function IsRoleStatusIconSpec(spec)
        local value = spec and spec.value
        return value == "roleIcon" or value == "leaderIcon" or value == "assistIcon"
    end
    local function StatusIconStyleLabel(spec)
        return tostring(spec and spec.label or "Status Indicator") .. (IsRoleStatusIconSpec(spec) and " Role Icon Style" or " Indicator Icon Set")
    end

    for _, spec in ipairs(GROUP_STATUS_ICON_SPECS) do
        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec)
        AddGroupStatusIconAliases(aliases, scope, spec, "enabled")
        RegisterGroupBoolean(scope, "statusIcon" .. spec.value .. "Enabled", spec.enabled, spec.label, false, "visual", aliases, { description = spec.description })

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "size")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Size", spec.size, spec.label .. " Size", spec.defaultSize, 6, 40, 1, "visual", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "anchor")
        AddGroupStatusIconAliases(aliases, scope, spec, "position")
        RegisterGroupEnum(scope, "statusIcon" .. spec.value .. "Anchor", spec.anchor, spec.label .. " Anchor", spec.defaultAnchor, GROUP_STATUS_ANCHOR_VALUES, GROUP_STATUS_ANCHOR_ALIASES, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "x")
        AddGroupStatusIconAliases(aliases, scope, spec, "x offset")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "X", spec.x, spec.label .. " X Offset", 0, -500, 500, 1, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "y")
        AddGroupStatusIconAliases(aliases, scope, spec, "y offset")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Y", spec.y, spec.label .. " Y Offset", 0, -500, 500, 1, "geometry", aliases)

        aliases = {}
        AddGroupStatusIconAliases(aliases, scope, spec, "layer")
        AddGroupStatusIconAliases(aliases, scope, spec, "draw layer")
        RegisterGroupNumber(scope, "statusIcon" .. spec.value .. "Layer", spec.layer, spec.label .. " Layer", spec.defaultLayer, 0, 30, 1, "visual", aliases)

    end
end

function A.GroupFramesRegistry.RegisterTargetedSpellSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope ~= "party" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupColor = ctx.RegisterGroupColor
    local GROUP_STATUS_ANCHOR_VALUES = ctx.GROUP_STATUS_ANCHOR_VALUES or {}
    local GROUP_STATUS_ANCHOR_ALIASES = ctx.GROUP_STATUS_ANCHOR_ALIASES or {}

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupColor) ~= "function" then return end

    local function AddTargetedSpellAliases(out, suffix)
        local bases = {
            "targeted spell", "targeted spells", "targeted spell indicator",
            "targeted spell indicators", "targeted spell tracker",
            "targeted spells tracker", "enemy targeted spell",
            "enemy targeted spells", "enemy nameplate cast tracker",
        }
        for i = 1, #bases do
            local base = bases[i]
            local alias = suffix and (base .. " " .. suffix) or base
            out[#out + 1] = alias
            out[#out + 1] = "group " .. alias
            AddAliasesForUnit(out, scope, alias)
            if suffix then
                local prefixAlias = suffix .. " " .. base
                out[#out + 1] = prefixAlias
                out[#out + 1] = "group " .. prefixAlias
                AddAliasesForUnit(out, scope, prefixAlias)
            end
        end
    end

    local TARGETED_SPELL_MODE_VALUES = { "whenHealing", "always" }
    local TARGETED_SPELL_MODE_ALIASES = {
        always = "always",
        ["all the time"] = "always",
        on = "always",
        healing = "whenHealing",
        ["when healing"] = "whenHealing",
        healer = "whenHealing",
        ["healing only"] = "whenHealing",
        smart = "whenHealing",
    }
    local TARGETED_SPELL_GROW_VALUES = { "CENTER", "RIGHT", "LEFT", "UP", "DOWN" }
    local TARGETED_SPELL_GROW_ALIASES = {
        center = "CENTER",
        centered = "CENTER",
        centre = "CENTER",
        middle = "CENTER",
        right = "RIGHT",
        left = "LEFT",
        up = "UP",
        above = "UP",
        down = "DOWN",
        below = "DOWN",
    }

    local aliases = {}
    AddTargetedSpellAliases(aliases)
    AddTargetedSpellAliases(aliases, "enabled")
    AddTargetedSpellAliases(aliases, "visible")
    RegisterGroupBoolean(scope, "targetedSpellsEnabled", "targetedSpellsEnabled", "Targeted Spell Indicators", false, "targetedSpells", aliases, {
        description = "Shows party-only targeted spell indicators for enemy nameplate casts targeting party members.",
    })

    aliases = {}
    AddTargetedSpellAliases(aliases, "mode")
    RegisterGroupEnum(scope, "targetedSpellsMode", "targetedSpellsMode", "Targeted Spell Mode", "whenHealing", TARGETED_SPELL_MODE_VALUES, TARGETED_SPELL_MODE_ALIASES, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "icon size")
    AddTargetedSpellAliases(aliases, "size")
    RegisterGroupNumber(scope, "targetedSpellsIconSize", "targetedSpellsIconSize", "Targeted Spell Icon Size", 24, 8, 64, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "max icons")
    AddTargetedSpellAliases(aliases, "icon count")
    RegisterGroupNumber(scope, "targetedSpellsMaxIcons", "targetedSpellsMaxIcons", "Targeted Spell Max Icons", 3, 1, 5, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "layer")
    AddTargetedSpellAliases(aliases, "draw layer")
    RegisterGroupNumber(scope, "targetedSpellsLayer", "targetedSpellsLayer", "Targeted Spell Layer", 10, 0, 30, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "anchor")
    AddTargetedSpellAliases(aliases, "position")
    RegisterGroupEnum(scope, "targetedSpellsAnchor", "targetedSpellsAnchor", "Targeted Spell Anchor", "CENTER", GROUP_STATUS_ANCHOR_VALUES, GROUP_STATUS_ANCHOR_ALIASES, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "growth")
    AddTargetedSpellAliases(aliases, "grow")
    RegisterGroupEnum(scope, "targetedSpellsGrow", "targetedSpellsGrow", "Targeted Spell Growth", "CENTER", TARGETED_SPELL_GROW_VALUES, TARGETED_SPELL_GROW_ALIASES, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "x")
    AddTargetedSpellAliases(aliases, "x offset")
    RegisterGroupNumber(scope, "targetedSpellsX", "targetedSpellsX", "Targeted Spell X Offset", 0, -200, 200, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "y")
    AddTargetedSpellAliases(aliases, "y offset")
    RegisterGroupNumber(scope, "targetedSpellsY", "targetedSpellsY", "Targeted Spell Y Offset", 0, -200, 200, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "cooldown text")
    AddTargetedSpellAliases(aliases, "timer text")
    RegisterGroupBoolean(scope, "targetedSpellsTextEnabled", "targetedSpellsTextEnabled", "Targeted Spell Cooldown Text", true, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "cooldown text size")
    AddTargetedSpellAliases(aliases, "timer text size")
    RegisterGroupNumber(scope, "targetedSpellsTextSize", "targetedSpellsTextSize", "Targeted Spell Cooldown Text Size", 10, 6, 24, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "cooldown decimals")
    AddTargetedSpellAliases(aliases, "timer decimals")
    AddTargetedSpellAliases(aliases, "decimal threshold")
    RegisterGroupNumber(scope, "targetedSpellsTextDecimalBelow", "targetedSpellsTextDecimalBelow", "Targeted Spell Cooldown Decimal Threshold", 3, 0, 30, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "color by time")
    AddTargetedSpellAliases(aliases, "timer color by time")
    RegisterGroupBoolean(scope, "targetedSpellsTextColorByTime", "targetedSpellsTextColorByTime", "Targeted Spell Cooldown Color by Time", false, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "safe seconds")
    AddTargetedSpellAliases(aliases, "safe timer threshold")
    RegisterGroupNumber(scope, "targetedSpellsTextSafeSeconds", "targetedSpellsTextSafeSeconds", "Targeted Spell Safe Seconds", 60, 0, 600, 5, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "warning seconds")
    AddTargetedSpellAliases(aliases, "warning timer threshold")
    RegisterGroupNumber(scope, "targetedSpellsTextWarningSeconds", "targetedSpellsTextWarningSeconds", "Targeted Spell Warning Seconds", 15, 0, 60, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "urgent seconds")
    AddTargetedSpellAliases(aliases, "urgent timer threshold")
    RegisterGroupNumber(scope, "targetedSpellsTextUrgentSeconds", "targetedSpellsTextUrgentSeconds", "Targeted Spell Urgent Seconds", 5, 0, 30, 1, "targetedSpells", aliases)

    aliases = {}
    AddTargetedSpellAliases(aliases, "safe color")
    AddTargetedSpellAliases(aliases, "safe timer color")
    RegisterGroupColor(scope, "targetedSpellsTextSafeColor", "targetedSpellsTextSafe", "Targeted Spell Safe Color", 1, 1, 1, aliases, { mode = "targetedSpells" })

    aliases = {}
    AddTargetedSpellAliases(aliases, "warning color")
    AddTargetedSpellAliases(aliases, "warning timer color")
    RegisterGroupColor(scope, "targetedSpellsTextWarningColor", "targetedSpellsTextWarning", "Targeted Spell Warning Color", 1, 0.85, 0.20, aliases, { mode = "targetedSpells" })

    aliases = {}
    AddTargetedSpellAliases(aliases, "urgent color")
    AddTargetedSpellAliases(aliases, "urgent timer color")
    RegisterGroupColor(scope, "targetedSpellsTextUrgentColor", "targetedSpellsTextUrgent", "Targeted Spell Urgent Color", 1, 0.55, 0.10, aliases, { mode = "targetedSpells" })
end
