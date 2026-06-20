-- Assistant global color ClassPower helper context.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings_Core.lua; isolates ClassPower color DB access.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.BuildClassPowerColorHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local GeneralDB = ctx.GeneralDB
    local CP_SLOT_DEFAULTS = ctx.CP_SLOT_DEFAULTS or {}
    local ApiRGB = ctx.ApiRGB
    local GeneralRGB = ctx.GeneralRGB
    local PowerDefaultRGB = ctx.PowerDefaultRGB
    local TableRGB = ctx.TableRGB

    if type(GeneralDB) ~= "function" then return nil end
    if type(ApiRGB) ~= "function" or type(GeneralRGB) ~= "function" then return nil end
    if type(PowerDefaultRGB) ~= "function" or type(TableRGB) ~= "function" then return nil end

    local function EnsureClassPowerOverrides()
        local g = GeneralDB()
        g.classPowerColorOverrides = type(g.classPowerColorOverrides) == "table" and g.classPowerColorOverrides or {}
        g.classPowerBgColorOverrides = type(g.classPowerBgColorOverrides) == "table" and g.classPowerBgColorOverrides or {}
        return g
    end

    local function ClassPowerDefaultRGB(token)
        local slot = CP_SLOT_DEFAULTS[token]
        if slot then return slot[1], slot[2], slot[3] end
        if token == "CHARGED" then return 0.60, 0.20, 0.80 end
        if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1, function() return GeneralRGB("fontColorCustom", 1, 1, 1) end) end
        if token == "SOUL_FRAGMENTS" then return 0.00, 0.80, 0.00 end
        if token == "SOUL_FRAGMENTS_META" then return 0.60, 0.20, 0.93 end
        if token == "MAELSTROM" or token == "MAELSTROM_POWER" then return PowerDefaultRGB("MAELSTROM") end
        if token == "MAELSTROM_ABOVE_5" then return 1.00, 0.50, 0.00 end
        if token == "ASTRAL_POWER" or token == "AP_PREDICTION" then return PowerDefaultRGB("LUNAR_POWER") end
        if token == "ECLIPSE_SOLAR" then return 0.82, 0.56, 0.25 end
        if token == "ECLIPSE_LUNAR" then return 0.41, 0.49, 0.82 end
        if token == "ECLIPSE_CA" then return 0.30, 1.00, 0.43 end
        if token == "STAGGER_GREEN" then return 0.52, 1.00, 0.52 end
        if token == "STAGGER_YELLOW" then return 1.00, 0.98, 0.72 end
        if token == "STAGGER_RED" then return 1.00, 0.42, 0.42 end
        if token == "SOUL_FRAGMENTS_VENG" then return 0.34, 0.06, 0.46 end
        if token == "INSANITY" then return PowerDefaultRGB("INSANITY") end
        if token == "WHIRLWIND" then return 0.20, 0.80, 0.20 end
        if token == "TIP_OF_THE_SPEAR" then return 0.60, 0.80, 0.20 end
        if token == "ICICLES" then return 0.50, 0.80, 1.00 end
        if token == "EBON_MIGHT" then return 0.40, 0.80, 0.60 end
        return PowerDefaultRGB(token)
    end

    local function ClassPowerRGB(token)
        local dr, dg, db = ClassPowerDefaultRGB(token)
        return TableRGB(GeneralDB().classPowerColorOverrides, token, dr, dg, db)
    end

    local function SetClassPowerRGB(token, r, gCol, b)
        EnsureClassPowerOverrides().classPowerColorOverrides[token] = { r, gCol, b }
    end

    local function ClassPowerBgRGB(token)
        return TableRGB(GeneralDB().classPowerBgColorOverrides, token, 0, 0, 0)
    end

    local function SetClassPowerBgRGB(token, r, gCol, b)
        EnsureClassPowerOverrides().classPowerBgColorOverrides[token] = { r, gCol, b }
    end

    return {
        ClassPowerBgRGB = ClassPowerBgRGB,
        ClassPowerRGB = ClassPowerRGB,
        EnsureClassPowerOverrides = EnsureClassPowerOverrides,
        SetClassPowerBgRGB = SetClassPowerBgRGB,
        SetClassPowerRGB = SetClassPowerRGB,
    }
end
