-- Assistant GroupFrames text/layout helper core.
-- Builds shared text, alias, color, and normalization helpers for the GroupFrames registry core.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildTextCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local EnsureDB = ctx.EnsureDB
    local GeneralDB = ctx.GeneralDB
    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup
    local RegisterGroupString = ctx.RegisterGroupString
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local GroupFramesData = ctx.GroupFramesData

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return nil end
    if type(RegisterGroupString) ~= "function" or type(RegisterGroupEnum) ~= "function" then return nil end
    if type(GroupFramesData) ~= "table" then return nil end

    local function NormalizeGroupRoleOrder(value)
        local labels = { tank = "TANK", tanks = "TANK", healer = "HEALER", healers = "HEALER", heal = "HEALER", dps = "DAMAGER", damage = "DAMAGER", damager = "DAMAGER", damagers = "DAMAGER", dd = "DAMAGER" }
        local seen, out = {}, {}
        for token in tostring(value or ""):gmatch("[^,%s/|>%+%-]+") do
            local upper = tostring(token or ""):upper()
            local mapped = labels[tostring(token or ""):lower()] or upper
            if mapped == "MELEE" or mapped == "RANGED" then mapped = "DAMAGER" end
            if (mapped == "TANK" or mapped == "HEALER" or mapped == "DAMAGER") and not seen[mapped] then
                seen[mapped] = true
                out[#out + 1] = mapped
            end
        end
        if not seen.TANK then out[#out + 1] = "TANK" end
        if not seen.HEALER then out[#out + 1] = "HEALER" end
        if not seen.DAMAGER then out[#out + 1] = "DAMAGER" end
        return table.concat(out, ",")
    end

    local function TrimString(value)
        return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local BuildTextNameContext = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildTextNameContext
    local TextNames = type(BuildTextNameContext) == "function" and BuildTextNameContext({
        EnsureDB = EnsureDB,
        GeneralDB = GeneralDB,
        GroupDB = GroupDB,
    }) or nil
    if type(TextNames) ~= "table" then return nil end
    local GroupNameShorteningEnabled = TextNames.GroupNameShorteningEnabled
    local GroupNameShorteningMax = TextNames.GroupNameShorteningMax
    local GroupNameShorteningSide = TextNames.GroupNameShorteningSide
    local GroupNameShorteningNoEllipsis = TextNames.GroupNameShorteningNoEllipsis
    local SetGroupFontOverrideValue = TextNames.SetGroupFontOverrideValue

    local BuildTextColorContext = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildTextColorContext
    local TextColors = type(BuildTextColorContext) == "function" and BuildTextColorContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        GroupDB = GroupDB,
        ApplyGroup = ApplyGroup,
    }) or nil
    if type(TextColors) ~= "table" then return nil end
    local RegisterGroupColor = TextColors.RegisterGroupColor
    local GroupColorSame = TextColors.GroupColorSame
    local GetGroupHealthBarColor = TextColors.GetGroupHealthBarColor
    local SetGroupHealthBarColor = TextColors.SetGroupHealthBarColor

    local function StandardGroupAnchorTarget(value)
        return value == nil or value == "" or value == "FREE" or value == "player" or value == "target"
            or value == "targettarget" or value == "focustarget" or value == "focus"
    end

    local BuildTextAliasContext = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildTextAliasContext
    local TextAliases = type(BuildTextAliasContext) == "function" and BuildTextAliasContext({
        GroupFramesData = GroupFramesData,
    }) or nil
    if type(TextAliases) ~= "table" then return nil end

    local GroupBarModeExactAliases = TextAliases.GroupBarModeExactAliases
    local GroupGrowthExactAliases = TextAliases.GroupGrowthExactAliases
    local GroupReverseFillExactAliases = TextAliases.GroupReverseFillExactAliases
    local GroupReverseFillBooleanAliases = TextAliases.GroupReverseFillBooleanAliases

    local GROUP_TEXT_MODE_VALUES = GroupFramesData.GROUP_TEXT_MODE_VALUES or {}
    local GROUP_TEXT_MODE_ALIASES = GroupFramesData.GROUP_TEXT_MODE_ALIASES or {}
    local GROUP_DELIMITER_VALUES = GroupFramesData.GROUP_DELIMITER_VALUES or {}
    local GROUP_DELIMITER_ALIASES = GroupFramesData.GROUP_DELIMITER_ALIASES or {}

    local function NormalizeGroupTextureName(value)
        value = TrimString(value)
        local lower = value:lower()
        if lower == "" or lower == "global" or lower == "follow global" or lower == "global style" then return "" end
        if lower == "default" or lower == "inherit" or lower == "inherited" then return "" end
        return value
    end

    local function NormalizeGroupDispelTrigger(value)
        if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
        if value == "BY_RAID" or value == "RAID" or value == "DISPELLABLE_BY_GROUP" then return "BY_RAID" end
        if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
        if value == "BY_ME" or value == "PLAYER" or value == "DISPELLABLE_BY_ME" then return "BY_ME" end
        return "BORDER"
    end

    local function RegisterGroupTexture(scope, attr, dbKey, label, aliases)
        RegisterGroupString(scope, attr, dbKey, label, "", "visual", aliases, {
            set = function(scopeKey, value)
                local conf = GroupDB(scopeKey)
                local texture = NormalizeGroupTextureName(value)
                conf[dbKey] = texture
                if texture ~= "" then conf.hlOverride = true end
            end,
            description = "Sets the group-frame texture name, or clears it to follow the global style.",
        })
    end

    local function RegisterGroupTextMode(scope, attr, dbKey, label, defaultValue, aliases)
        RegisterGroupEnum(scope, attr, dbKey, label, defaultValue or "NONE", GROUP_TEXT_MODE_VALUES, GROUP_TEXT_MODE_ALIASES, "visual", aliases)
    end

    local function RegisterGroupDelimiter(scope, attr, dbKey, label, aliases)
        RegisterGroupEnum(scope, attr, dbKey, label, " / ", GROUP_DELIMITER_VALUES, GROUP_DELIMITER_ALIASES, "visual", aliases)
    end

    return {
        RegisterGroupColor = RegisterGroupColor,
        RegisterGroupTexture = RegisterGroupTexture,
        RegisterGroupTextMode = RegisterGroupTextMode,
        RegisterGroupDelimiter = RegisterGroupDelimiter,
        GroupReverseFillExactAliases = GroupReverseFillExactAliases,
        GroupReverseFillBooleanAliases = GroupReverseFillBooleanAliases,
        GroupNameShorteningMax = GroupNameShorteningMax,
        GroupNameShorteningEnabled = GroupNameShorteningEnabled,
        GroupNameShorteningSide = GroupNameShorteningSide,
        GroupNameShorteningNoEllipsis = GroupNameShorteningNoEllipsis,
        SetGroupFontOverrideValue = SetGroupFontOverrideValue,
        GroupGrowthExactAliases = GroupGrowthExactAliases,
        NormalizeGroupRoleOrder = NormalizeGroupRoleOrder,
        StandardGroupAnchorTarget = StandardGroupAnchorTarget,
        TrimString = TrimString,
        GroupBarModeExactAliases = GroupBarModeExactAliases,
        GroupColorSame = GroupColorSame,
        GetGroupHealthBarColor = GetGroupHealthBarColor,
        SetGroupHealthBarColor = SetGroupHealthBarColor,
        NormalizeGroupDispelTrigger = NormalizeGroupDispelTrigger,
    }
end
