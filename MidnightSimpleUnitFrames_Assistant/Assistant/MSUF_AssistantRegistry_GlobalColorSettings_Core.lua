-- Assistant global color setting helper context.
-- Builds cold color conversion and DB access helpers for the color registry orchestrator.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.BuildColorSettingsCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local ApplyColors = ctx.ApplyColors
    local MSUFRef = ctx.MSUF or MSUF

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GeneralDB) ~= "function" then return nil end

    local ColorData = ctx.ColorData or {}
    local CP_SLOT_DEFAULTS = ColorData.CP_SLOT_DEFAULTS or {}

    local BuildColorValueHelpers = A.GlobalRegistry and A.GlobalRegistry.BuildColorValueHelpers
    local ColorValues = type(BuildColorValueHelpers) == "function" and BuildColorValueHelpers({
        MSUF = MSUFRef,
        ColorData = ColorData,
    }) or nil
    if type(ColorValues) ~= "table" then return nil end
    local Clamp01 = ColorValues.Clamp01
    local ColorComponents = ColorValues.ColorComponents
    local ColorFromName = ColorValues.ColorFromName
    local ColorSame = ColorValues.ColorSame
    local ColorValue = ColorValues.ColorValue

    local BuildColorDBHelpers = A.GlobalRegistry and A.GlobalRegistry.BuildColorDBHelpers
    local ColorDBHelpers = type(BuildColorDBHelpers) == "function" and BuildColorDBHelpers({
        MSUF = MSUFRef,
        GeneralDB = GeneralDB,
    }) or nil
    if type(ColorDBHelpers) ~= "table" then return nil end
    local ApiRGB = ColorDBHelpers.ApiRGB
    local ApiSetRGB = ColorDBHelpers.ApiSetRGB
    local ColorAPI = ColorDBHelpers.ColorAPI
    local GeneralRGB = ColorDBHelpers.GeneralRGB
    local GeneralRGBAlias = ColorDBHelpers.GeneralRGBAlias
    local SetGeneralRGB = ColorDBHelpers.SetGeneralRGB
    local SetGeneralRGBAlias = ColorDBHelpers.SetGeneralRGBAlias
    local SetTableRGB = ColorDBHelpers.SetTableRGB
    local TableRGB = ColorDBHelpers.TableRGB

    local function ColorSetting(key, label, aliases, getRGB, setRGB, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = key,
            label = label,
            category = opts.category or "Colors",
            unit = opts.unit or "global",
            frameType = opts.frameType or "colors",
            attribute = opts.attribute or key,
            type = "color",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            get = function()
                local r, g, b, colorLabel = getRGB()
                return ColorValue(r, g, b, colorLabel)
            end,
            set = function(value)
                local r, g, b = ColorComponents(value, opts.defaultR or 1, opts.defaultG or 1, opts.defaultB or 1)
                setRGB(r, g, b, value)
            end,
            sameValue = ColorSame,
            apply = opts.apply or ApplyColors,
            combatSafe = opts.combatSafe == true,
            menuControlDisposition = opts.menuControlDisposition,
            menuControlDispositionReason = opts.menuControlDispositionReason,
            menuControlDispositionEvidence = opts.menuControlDispositionEvidence,
            description = opts.description,
            resourceToken = opts.resourceToken,
            resourceLabel = opts.resourceLabel,
            className = opts.className,
            slot = opts.slot,
        })
    end

    local BuildPowerColorHelpers = A.GlobalRegistry and A.GlobalRegistry.BuildPowerColorHelpers
    local PowerColors = type(BuildPowerColorHelpers) == "function" and BuildPowerColorHelpers({
        GeneralDB = GeneralDB,
        TableRGB = TableRGB,
    }) or nil
    if type(PowerColors) ~= "table" then return nil end
    local EnsurePowerOverrides = PowerColors.EnsurePowerOverrides
    local PowerDefaultRGB = PowerColors.PowerDefaultRGB
    local PowerOverrideRGB = PowerColors.PowerOverrideRGB
    local SetPowerOverrideRGB = PowerColors.SetPowerOverrideRGB

    local BuildClassPowerColorHelpers = A.GlobalRegistry and A.GlobalRegistry.BuildClassPowerColorHelpers
    local ClassPowerColors = type(BuildClassPowerColorHelpers) == "function" and BuildClassPowerColorHelpers({
        GeneralDB = GeneralDB,
        CP_SLOT_DEFAULTS = CP_SLOT_DEFAULTS,
        ApiRGB = ApiRGB,
        GeneralRGB = GeneralRGB,
        PowerDefaultRGB = PowerDefaultRGB,
        TableRGB = TableRGB,
    }) or nil
    if type(ClassPowerColors) ~= "table" then return nil end

    local ClassPowerBgRGB = ClassPowerColors.ClassPowerBgRGB
    local ClassPowerRGB = ClassPowerColors.ClassPowerRGB
    local EnsureClassPowerOverrides = ClassPowerColors.EnsureClassPowerOverrides
    local SetClassPowerBgRGB = ClassPowerColors.SetClassPowerBgRGB
    local SetClassPowerRGB = ClassPowerColors.SetClassPowerRGB
    if type(ClassPowerBgRGB) ~= "function" then return nil end
    if type(ClassPowerRGB) ~= "function" then return nil end
    if type(EnsureClassPowerOverrides) ~= "function" then return nil end
    if type(SetClassPowerBgRGB) ~= "function" then return nil end
    if type(SetClassPowerRGB) ~= "function" then return nil end

    return {
        ApiRGB = ApiRGB,
        ApiSetRGB = ApiSetRGB,
        ClassPowerBgRGB = ClassPowerBgRGB,
        ClassPowerRGB = ClassPowerRGB,
        Clamp01 = Clamp01,
        ColorAPI = ColorAPI,
        ColorComponents = ColorComponents,
        ColorFromName = ColorFromName,
        ColorSame = ColorSame,
        ColorSetting = ColorSetting,
        EnsureClassPowerOverrides = EnsureClassPowerOverrides,
        EnsurePowerOverrides = EnsurePowerOverrides,
        GeneralRGB = GeneralRGB,
        GeneralRGBAlias = GeneralRGBAlias,
        SetClassPowerBgRGB = SetClassPowerBgRGB,
        SetClassPowerRGB = SetClassPowerRGB,
        SetGeneralRGB = SetGeneralRGB,
        SetGeneralRGBAlias = SetGeneralRGBAlias,
        SetPowerOverrideRGB = SetPowerOverrideRGB,
        SetTableRGB = SetTableRGB,
        PowerOverrideRGB = PowerOverrideRGB,
        TableRGB = TableRGB,
    }
end
