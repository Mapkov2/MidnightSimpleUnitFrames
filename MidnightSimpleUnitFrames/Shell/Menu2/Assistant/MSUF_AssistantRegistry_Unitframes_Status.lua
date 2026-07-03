-- Assistant UnitFrame status icon registry.
-- Keeps status-icon metadata outside the main UnitFrame registry loop while
-- preserving the same cold Assistant registration behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.RegisterStatusIconSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitString = ctx.RegisterUnitString
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local StatusIconOpts = ctx.StatusIconOpts
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local AllowedMap = ctx.AllowedMap

    if type(AddAliasesForUnit) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitBooleanSetting) ~= "function" or type(RegisterUnitString) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" or type(RegisterUnitNumberSetting) ~= "function" then return end
    if type(StatusIconOpts) ~= "function" or type(UnitDB) ~= "function" or type(GeneralDB) ~= "function" then return end
    if type(AllowedMap) ~= "function" then return end

    local STATUS_CONTROL_SPECS = ctx.STATUS_CONTROL_SPECS or {}
    local STATUS_ICON_PACK_FALLBACK_VALUES = ctx.STATUS_ICON_PACK_FALLBACK_VALUES or {}
    local STATUS_SYMBOL_ALIASES = ctx.STATUS_SYMBOL_ALIASES
    local STATUS_ANCHOR_VALUES = ctx.STATUS_ANCHOR_VALUES
    local STATUS_CORNER_ANCHOR_VALUES = ctx.STATUS_CORNER_ANCHOR_VALUES
    local STATUS_ANCHOR_ALIASES = ctx.STATUS_ANCHOR_ALIASES
    local RAID_GROUP_STYLE_VALUES = ctx.RAID_GROUP_STYLE_VALUES
    local RAID_GROUP_STYLE_ALIASES = ctx.RAID_GROUP_STYLE_ALIASES
    local function IsRoleStatusSpec(spec)
        local value = spec and spec.value
        return value == "leader" or value == "assist"
    end
    local function StatusIconStyleLabel(spec)
        return tostring(spec and spec.label or "Status Indicator") .. (IsRoleStatusSpec(spec) and " Role Icon Style" or " Indicator Icon Set")
    end

    for s = 1, #STATUS_CONTROL_SPECS do
        local spec = STATUS_CONTROL_SPECS[s]
        if not spec.units or spec.units[unit] == true then
            local aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a]
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitBooleanSetting(unit, spec.show, spec.show, spec.label, spec.defaultShow, aliases, StatusIconOpts(spec, {
                reason = "MSUF_ASSISTANT_STATUS_" .. spec.value,
                text = true,
                description = spec.description or ("Status icon visibility for " .. spec.label .. "."),
            }))

            if spec.symbol then
                aliases = {}
                for a = 1, #(spec.aliases or {}) do
                    local base = spec.aliases[a]
                    local alias = tostring(base):find("symbol", 1, true) and base or (tostring(base) .. " symbol")
                    aliases[#aliases + 1] = alias
                    AddAliasesForUnit(aliases, unit, alias)
                end
                RegisterUnitEnum(unit, spec.symbol, spec.symbol, spec.label .. " Symbol", "DEFAULT", spec.symbolValues or { "DEFAULT" }, aliases, StatusIconOpts(spec, {
                    valueAliases = STATUS_SYMBOL_ALIASES,
                }))
            end

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " size"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "Size", spec.size, spec.label .. " Size", spec.defaultSize, 8, 64, aliases, StatusIconOpts(spec, {
                keySuffix = spec.size,
                get = function(unitKey) return tonumber(UnitDB(unitKey)[spec.size]) or tonumber(GeneralDB()[spec.size]) or spec.defaultSize end,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " anchor"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitEnum(unit, spec.value .. "Anchor", spec.anchor, spec.label .. " Anchor", spec.defaultAnchor, spec.nameAnchors and STATUS_ANCHOR_VALUES or STATUS_CORNER_ANCHOR_VALUES, aliases, StatusIconOpts(spec, {
                keySuffix = spec.anchor,
                valueAliases = STATUS_ANCHOR_ALIASES,
                get = function(unitKey)
                    local value = UnitDB(unitKey)[spec.anchor] or GeneralDB()[spec.anchor]
                    local allowed = AllowedMap(spec.nameAnchors and STATUS_ANCHOR_VALUES or STATUS_CORNER_ANCHOR_VALUES)
                    return allowed[value] and value or spec.defaultAnchor
                end,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " x offset"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "OffsetX", spec.x, spec.label .. " X Offset", spec.defaultX, -1000, 1000, aliases, StatusIconOpts(spec, {
                keySuffix = spec.x,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " y offset"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "OffsetY", spec.y, spec.label .. " Y Offset", spec.defaultY, -1000, 1000, aliases, StatusIconOpts(spec, {
                keySuffix = spec.y,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " layer"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "Layer", spec.layer, spec.label .. " Layer", spec.defaultLayer, 1, 10, aliases, StatusIconOpts(spec, {
                keySuffix = spec.layer,
            }))

            if spec.value == "raidgroupname" then
                aliases = MakeAliases(unit, "raid group style", "raid group name style", "group number style")
                RegisterUnitEnum(unit, "raidGroupNameStyle", "raidGroupNameStyle", "Raid Group Name Style", "PAREN", RAID_GROUP_STYLE_VALUES, aliases, StatusIconOpts(spec, {
                    valueAliases = RAID_GROUP_STYLE_ALIASES,
                }))
            end
        end
    end

    RegisterUnitBooleanSetting(unit, "stateIconsTestMode", "stateIconsTestMode", "Status Icon Test Mode", false, MakeAliases(unit,
        "status icon test mode",
        "status icons test mode",
        "test status icons",
        "test status icon",
        "status icon preview mode",
        "status icons preview mode",
        "status preview mode",
        "status indicator test mode",
        "test status indicators"
    ), {
        category = "Status Icons",
        get = function(unitKey)
            local value = UnitDB(unitKey).stateIconsTestMode
            if value == nil then value = GeneralDB().stateIconsTestMode end
            return value == true
        end,
        refresh = "MSUF_RequestStatusIconsRefreshForCurrent",
        applyOpts = { preview = true, text = true },
        applyWhenUnchanged = true,
    })
end
