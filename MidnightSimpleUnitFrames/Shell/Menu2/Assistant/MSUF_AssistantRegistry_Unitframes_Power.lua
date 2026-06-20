-- Assistant UnitFrame power bar setting registry.
-- Keeps power and detached-power controls outside the main UnitFrame registry loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local POWER_UNITS = { player = true, target = true, focus = true, targettarget = true, focustarget = true, pet = true, boss = true }

local function UnitDefaultPowerBar(unit)
    return not (unit == "targettarget" or unit == "focustarget")
end

local UnitframesRegistry = A.UnitframesRegistry
local AddDetachedPowerVerbAliases = UnitframesRegistry.AddDetachedPowerVerbAliases
local DetachedPowerMoveAliases = UnitframesRegistry.DetachedPowerMoveAliases
local DetachedPowerMoveGuard = UnitframesRegistry.DetachedPowerMoveGuard
local InitDetachedPowerBar = UnitframesRegistry.InitDetachedPowerBar

function A.UnitframesRegistry.RegisterPowerSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" or not POWER_UNITS[unit] then return end

    local UnitDB = ctx.UnitDB
    local BarsDB = ctx.BarsDB
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local DETACHED_POWER_SHAPE_VALUES = ctx.DETACHED_POWER_SHAPE_VALUES or {}
    local DETACHED_POWER_SHAPE_ALIASES = ctx.DETACHED_POWER_SHAPE_ALIASES or {}

    if type(UnitDB) ~= "function" or type(BarsDB) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitBooleanSetting) ~= "function" or type(RegisterUnitNumberSetting) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" then return end
    if type(AddDetachedPowerVerbAliases) ~= "function" or type(DetachedPowerMoveAliases) ~= "function" then return end
    if type(DetachedPowerMoveGuard) ~= "function" or type(InitDetachedPowerBar) ~= "function" then return end

    RegisterUnitBooleanSetting(unit, "powerBar", "showPowerBar", "Power Bar", UnitDefaultPowerBar(unit),
        MakeAliases(unit, "power bar", "show power bar"), { category = "Power Bar", power = true })
    RegisterUnitBooleanSetting(unit, "powerBarBorder", "powerBarBorderEnabled", "Power Bar Border", false, MakeAliases(unit, "power bar border", "power border"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
            return BarsDB().powerBarBorderEnabled == true
        end,
    })
    RegisterUnitNumberSetting(unit, "powerBarHeight", "powerBarHeight", "Power Bar Height", 3, 1, 20, MakeAliases(unit, "power bar height", "power height"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey) return tonumber(UnitDB(unitKey).powerBarHeight) or tonumber(BarsDB().powerBarHeight) or 3 end,
    })
    RegisterUnitNumberSetting(unit, "powerBarBorderThickness", "powerBarBorderThickness",
        "Power Bar Border Thickness", 1, 0, 6,
        MakeAliases(unit, "power bar border thickness", "power border size"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey) return tonumber(UnitDB(unitKey).powerBarBorderThickness) or tonumber(BarsDB().powerBarBorderThickness or BarsDB().powerBarBorderSize) or 1 end,
    })
    RegisterUnitBooleanSetting(unit, "embedPowerBarIntoHealth", "embedPowerBarIntoHealth",
        "Embed Power Bar into Health", false,
        MakeAliases(unit, "embed power bar", "embed power into health", "power bar embedded"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return BarsDB().embedPowerBarIntoHealth == true
        end,
    })
    RegisterUnitBooleanSetting(unit, "powerSmoothFill", "powerSmoothFill", "Power Bar Smooth Fill",
        unit == "player",
        MakeAliases(unit, "power smooth fill", "smooth power bar"), { category = "Power Bar", power = true })

    local detachedPowerAliases = MakeAliases(unit, "detached power bar", "detach power bar", "power bar detached")
    AddDetachedPowerVerbAliases(detachedPowerAliases, unit, { "detach", "undock", "attach", "dock" }, "power bar")
    AddDetachedPowerVerbAliases(detachedPowerAliases, unit, { "abkoppeln", "ankoppeln" }, "power balken")
    RegisterUnitBooleanSetting(unit, "powerBarDetached", "powerBarDetached", "Detach Power Bar from Frame", false, detachedPowerAliases, {
        category = "Power Bar",
        power = true,
        set = function(unitKey, value)
            UnitDB(unitKey).powerBarDetached = value and true or false
            if value then InitDetachedPowerBar(ctx, unitKey) end
        end,
    })
    RegisterUnitBooleanSetting(unit, "detachedPowerBarTextOnBar", "detachedPowerBarTextOnBar",
        "Text on Detached Power Bar", false,
        MakeAliases(unit, "text on detached power bar", "detached power text on bar"),
        { category = "Power Bar", power = true, text = true })

    if unit == "player" then
        RegisterUnitBooleanSetting(unit, "detachedPowerBarSyncClassPower", "detachedPowerBarSyncClassPower",
            "Detached Power Bar Syncs to Class Resource Width", true,
            MakeAliases(unit, "detached power sync class resource", "sync power bar to class resource"), {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return UnitDB(unitKey).detachedPowerBarSyncClassPower ~= false end,
        })
        RegisterUnitBooleanSetting(unit, "detachedPowerBarAnchorToClassPower", "detachedPowerBarAnchorToClassPower",
            "Detached Power Bar Anchors to Class Resource", false,
            MakeAliases(unit, "anchor detached power to class resource", "detached power anchor class resource"),
            { category = "Power Bar", power = true })
        RegisterUnitEnum(unit, "detachedPowerBarShape", "detachedPowerBarShape", "Detached Power Bar Shape", "FOLLOW_CLASS", DETACHED_POWER_SHAPE_VALUES, MakeAliases(unit,
            "player power shape", "detached power shape", "detached power bar shape", "player detached power shape",
            "follow class resource shape", "power bar shape", "mana orb", "power orb", "mana ball", "power ball", "power sphere"
        ), {
            category = "Power Bar",
            power = true,
            valueAliases = DETACHED_POWER_SHAPE_ALIASES,
            get = function(unitKey)
                local value = tostring(UnitDB(unitKey).detachedPowerBarShape or "FOLLOW_CLASS"):upper()
                if value == "FOLLOW_CLASS" or value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
                return "FOLLOW_CLASS"
            end,
        })
        RegisterUnitNumberSetting(unit, "detachedPowerOrbSize", "detachedPowerOrbSize", "Detached Power Orb Size", 54, 20, 160, MakeAliases(unit,
            "mana orb size", "power orb size", "detached power orb size", "orb size", "mana ball size", "power ball size"
        ), {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return tonumber(UnitDB(unitKey).detachedPowerOrbSize) or 54 end,
        })
    end

    RegisterUnitNumberSetting(unit, "detachedPowerBarOffsetX", "detachedPowerBarOffsetX",
        "Detached Power Bar X Offset", 0, -1000, 1000,
        MakeAliases(unit, "detached power x", "detached power bar x offset"), {
        category = "Power Bar",
        power = true,
        exactAliases = DetachedPowerMoveAliases(unit, "x"),
        moveAxis = "x",
        moveStep = 10,
        intentGuard = DetachedPowerMoveGuard(ctx, unit),
    })
    RegisterUnitNumberSetting(unit, "detachedPowerBarOffsetY", "detachedPowerBarOffsetY",
        "Detached Power Bar Y Offset", -4, -1000, 1000,
        MakeAliases(unit, "detached power y", "detached power bar y offset"), {
        category = "Power Bar",
        power = true,
        exactAliases = DetachedPowerMoveAliases(unit, "y"),
        moveAxis = "y",
        moveStep = 10,
        intentGuard = DetachedPowerMoveGuard(ctx, unit),
    })
    RegisterUnitNumberSetting(unit, "detachedPowerBarWidth", "detachedPowerBarWidth",
        "Detached Power Bar Width", unit == "focus" and 180 or 275, 20, 800,
        MakeAliases(unit, "detached power width", "detached power bar width"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey) return tonumber(UnitDB(unitKey).detachedPowerBarWidth) or tonumber(UnitDB(unitKey).width) or (unitKey == "focus" and 180 or 275) end,
    })
    RegisterUnitNumberSetting(unit, "detachedPowerBarHeight", "detachedPowerBarHeight",
        "Detached Power Bar Height", 6, 2, 80,
        MakeAliases(unit, "detached power height", "detached power bar height"),
        { category = "Power Bar", power = true })
    RegisterUnitNumberSetting(unit, "detachedPowerBarFrameLevelOffset", "detachedPowerBarFrameLevelOffset",
        "Detached Power Bar Layer", 6, 0, 20,
        MakeAliases(unit, "detached power layer", "detached power bar frame level"),
        { category = "Power Bar", power = true })
end
