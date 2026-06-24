-- Assistant group aura lane settings.
-- Loaded before MSUF_AssistantRegistry_AurasGroupSettings.lua; the main registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterGroupAuraLaneSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Assistant = ctx.A or A
    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local AddGFAuraAliases = ctx.AddGFAuraAliases
    local AddGFAuraStrictAliases = ctx.AddGFAuraStrictAliases
    local AddGFAuraRelativeSizeAliases = ctx.AddGFAuraRelativeSizeAliases
    local RegisterGFAuraBoolean = ctx.RegisterGFAuraBoolean
    local RegisterGFAuraNumber = ctx.RegisterGFAuraNumber
    local RegisterGFAuraEnum = ctx.RegisterGFAuraEnum
    local RegisterGroupAuraRootSettings = ctx.RegisterGroupAuraRootSettings
    local GFReadConfValue = ctx.GFReadConfValue
    local GFWriteConfValue = ctx.GFWriteConfValue
    local ApplyGroup = ctx.ApplyGroup
    local RegisterGroupAuraLaneGeometrySettings = A.AurasRegistry and A.AurasRegistry.RegisterGroupAuraLaneGeometrySettings
    local GF_AURA_GROUPS = ctx.GF_AURA_GROUPS or {}
    local GF_AURA_FILTER_VALUES = ctx.GF_AURA_FILTER_VALUES or {}
    local GF_AURA_FILTER_ALIASES = ctx.GF_AURA_FILTER_ALIASES
    local AURA_LANES = ctx.AURA_LANES or {}

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(AddGFAuraAliases) ~= "function" or type(AddGFAuraStrictAliases) ~= "function" or type(AddGFAuraRelativeSizeAliases) ~= "function" then return end
    if type(RegisterGFAuraBoolean) ~= "function" or type(RegisterGFAuraNumber) ~= "function" or type(RegisterGFAuraEnum) ~= "function" then return end
    if type(RegisterGroupAuraLaneGeometrySettings) ~= "function" then return end

    local GroupAuraRootSettings = {
        Registry = ctx.Registry,
        UNIT_LABELS = UNIT_LABELS,
        AddAliasesForUnit = AddAliasesForUnit,
        GFAurasRoot = ctx.GFAurasRoot,
        ApplyGroup = ctx.ApplyGroup,
    }

    for _, scope in ipairs(GF_AURA_GROUPS) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            local maxDefault = 6
            local sizeDefault = lane == "buff" and 22 or 20
            local perRowDefault = lane == "buff" and 4 or 3
            local layerDefault = lane == "buff" and 5 or 6
            local aliases = {}
            AddAliasesForUnit(aliases, scope, laneInfo.plural:lower())
            AddGFAuraAliases(aliases, scope, lane, "visibility")
            RegisterGFAuraBoolean(scope, lane, "Visible", "enabled", laneInfo.plural, true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "max icons")
            AddGFAuraAliases(aliases, scope, lane, "count")
            local exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "max icons", "maximum icons", "icon count", "count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "max icons", "maximum icons", "icon count", "count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "max icons", "maximum icons", "icon count", "count" })
            RegisterGFAuraNumber(scope, lane, "Max", "max", laneInfo.label .. " Max Icons", maxDefault, 0, 20, aliases, "visual")

            aliases = {}
            exactAliases = {}
            AddGFAuraStrictAliases(exactAliases, scope, lane, "size")
            AddGFAuraStrictAliases(exactAliases, scope, lane, "icon size")
            AddGFAuraRelativeSizeAliases(exactAliases, scope, lane)
            for i = 1, #exactAliases do aliases[#aliases + 1] = exactAliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "size", "icon size" })
            Assistant._AssistantAddGFAuraAllLaneRelativeSizeAliases(aliases, scope)
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "size", "icon size" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "size", "icon size" })
            Assistant._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all group")
            Assistant._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all")
            RegisterGFAuraNumber(scope, lane, "Size", "size", laneInfo.label .. " Icon Size", sizeDefault, 8, 64, aliases, "geometry")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "per row")
            AddGFAuraAliases(aliases, scope, lane, "icons per row")
            exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "per row", "icons per row", "wrap count", "row count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "per row", "icons per row", "wrap count", "row count" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "per row", "icons per row", "wrap count", "row count" })
            RegisterGFAuraNumber(scope, lane, "PerRow", "perRow", laneInfo.label .. " Icons Per Row", perRowDefault, 1, 20, aliases, "geometry")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "spacing")
            exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "spacing", "gap", "icon gap" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "spacing", "gap", "icon gap" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "spacing", "gap", "icon gap" })
            RegisterGFAuraNumber(scope, lane, "Spacing", "spacing", laneInfo.label .. " Spacing", 1, 0, 12, aliases, "geometry")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "layer")
            AddGFAuraAliases(aliases, scope, lane, "z order")
            exactAliases = {}
            for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
            Assistant._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "layer", "z order", "frame level" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all group", { "layer", "z order", "frame level" })
            Assistant._AssistantAddAllAuraNouns(aliases, lane, "all", { "layer", "z order", "frame level" })
            RegisterGFAuraNumber(scope, lane, "Layer", "layer", laneInfo.label .. " Layer", layerDefault, 1, 15, aliases, "geometry")

            RegisterGroupAuraLaneGeometrySettings(ctx, scope, lane, laneInfo)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "filter")
            AddGFAuraAliases(aliases, scope, lane, "filter type")
            AddGFAuraAliases(aliases, scope, lane, "inclusive filter")
            RegisterGFAuraEnum(scope, lane, "FilterToken", "filterToken", laneInfo.label .. " Filter", GF_AURA_FILTER_VALUES[lane], GF_AURA_FILTER_ALIASES, "ALL", aliases, "visual")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown text")
            RegisterGFAuraBoolean(scope, lane, "CooldownText", "showCooldown", laneInfo.label .. " Cooldown Text", true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown swipe")
            RegisterGFAuraBoolean(scope, lane, "CooldownSwipe", "showCooldownSwipe", laneInfo.label .. " Cooldown Swipe", true, aliases)

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "stack count")
            AddGFAuraAliases(aliases, scope, lane, "stacks")
            RegisterGFAuraBoolean(scope, lane, "StackCount", "showStacks", laneInfo.label .. " Stack Count", true, aliases)

            if lane == "debuff" then
                aliases = {}
                AddGFAuraAliases(aliases, scope, lane, "dispel type border")
                AddGFAuraAliases(aliases, scope, lane, "debuff type border")
                AddGFAuraAliases(aliases, scope, lane, "dispel border")
                RegisterGFAuraBoolean(scope, lane, "DispelTypeBorder", "showDispelBorder", laneInfo.label .. " Dispel-type Border", false, aliases)
            end

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "cooldown font")
            AddGFAuraAliases(aliases, scope, lane, "cooldown size")
            RegisterGFAuraNumber(scope, lane, "CooldownSize", "cooldownSize", laneInfo.label .. " Cooldown Font Size", 8, 6, 24, aliases, "font")

            aliases = {}
            AddGFAuraAliases(aliases, scope, lane, "stack font")
            AddGFAuraAliases(aliases, scope, lane, "stack size")
            RegisterGFAuraNumber(scope, lane, "StackSize", "stackSize", laneInfo.label .. " Stack Font Size", 10, 6, 24, aliases, "font")
        end

        if type(RegisterGroupAuraRootSettings) == "function" then
            RegisterGroupAuraRootSettings(GroupAuraRootSettings, scope)
        end

        if scope ~= "mythicraid"
            and Registry and type(Registry.RegisterSetting) == "function"
            and type(GFReadConfValue) == "function" and type(GFWriteConfValue) == "function"
            and type(ApplyGroup) == "function"
        then
            local settingScope = scope
            local aliases = {}
            AddAliasesForUnit(aliases, settingScope, "aura cooldown darkens on loss")
            AddAliasesForUnit(aliases, settingScope, "cooldown darkens on loss")
            AddAliasesForUnit(aliases, settingScope, "cooldown swipe darkens on loss")
            AddAliasesForUnit(aliases, settingScope, "darken cooldown swipe on loss")
            AddAliasesForUnit(aliases, settingScope, "cooldown swipe dunkelt")
            AddAliasesForUnit(aliases, settingScope, "cooldown dunkelt bei verlust")
            Registry:RegisterSetting({
                key = "gf_" .. settingScope .. ".cooldownSwipeDarkenOnLoss",
                label = UNIT_LABELS[settingScope] .. " Aura Cooldown Swipe Darkens on Loss",
                category = UNIT_LABELS[settingScope] .. " / Group Auras",
                unit = settingScope,
                frameType = "groupAura",
                attribute = "gfAuraCooldownSwipeDarkenOnLoss",
                type = "boolean",
                aliases = aliases,
                exactAliases = aliases,
                get = function()
                    return GFReadConfValue(settingScope, "cooldownSwipeDarkenOnLoss", false) and true or false
                end,
                set = function(value)
                    value = value and true or false
                    GFWriteConfValue(settingScope, "cooldownSwipeDarkenOnLoss", value)
                    if settingScope == "raid" then GFWriteConfValue("mythicraid", "cooldownSwipeDarkenOnLoss", value) end
                end,
                apply = function()
                    ApplyGroup(settingScope, "visual")
                    if settingScope == "raid" then ApplyGroup("mythicraid", "visual") end
                end,
                combatSafe = false,
            })
        end
    end
end
