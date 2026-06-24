-- Assistant Castbars registry helper context.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; keeps the main castbar registry as orchestration only.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.BuildRegistryHelperContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local CallGlobal = ctx.CallGlobal
    local ApplyCastbar = ctx.ApplyCastbar
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local RegisterGeneralString = ctx.RegisterGeneralString

    if type(AddAliasesForUnit) ~= "function" or type(CallGlobal) ~= "function" then return nil end
    if type(ApplyCastbar) ~= "function" or type(RegisterGeneralBoolean) ~= "function" then return nil end
    if type(RegisterGeneralNumberSetting) ~= "function" or type(RegisterGeneralEnum) ~= "function" then return nil end
    if type(RegisterGeneralString) ~= "function" then return nil end

    local function CastbarAliases(noun, ...)
        local out = {
            "castbar " .. noun,
            "cast bar " .. noun,
            noun .. " castbar",
            noun .. " cast bar",
        }
        for i = 1, select("#", ...) do out[#out + 1] = select(i, ...) end
        return out
    end

    local function UnitCastbarAliases(unit, ...)
        local aliases = {}
        for i = 1, select("#", ...) do
            AddAliasesForUnit(aliases, unit, select(i, ...))
        end
        return aliases
    end

    local function ApplyCastbarTextures(reason)
        ApplyCastbar(reason or "MSUF2_CASTBAR_TEXTURES")
    end

    local function ApplyCastbarOutline(reason)
        CallGlobal("MSUF_ApplyCastbarOutlineToAll", true)
        ApplyCastbarTextures(reason or "MSUF2_CASTBAR_OUTLINE")
    end

    local function ApplyFocusKick(reason)
        CallGlobal("MSUF_UpdateFocusKickIconOptions")
        ApplyCastbar(reason or "MSUF2_FOCUS_KICK")
    end

    local function ApplyFocusKickText(reason)
        CallGlobal("MSUF_FocusKick_ApplyTimeTextFont")
        ApplyFocusKick(reason or "MSUF2_FOCUS_KICK_TEXT")
    end

    local function RegisterCastbarBoolean(dbKey, attr, label, defaultValue, aliases, opts)
        opts = opts or {}
        opts.category = opts.category or "Appearance / Cast Bars"
        opts.frameType = opts.frameType or "castbar"
        opts.apply = opts.apply or ApplyCastbar
        RegisterGeneralBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    end

    local function RegisterCastbarNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
        opts = opts or {}
        opts.category = opts.category or "Appearance / Cast Bars"
        opts.frameType = opts.frameType or "castbar"
        opts.apply = opts.apply or ApplyCastbar
        RegisterGeneralNumberSetting(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    end

    local function RegisterCastbarEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
        opts = opts or {}
        opts.category = opts.category or "Appearance / Cast Bars"
        opts.frameType = opts.frameType or "castbar"
        opts.apply = opts.apply or ApplyCastbar
        RegisterGeneralEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    end

    local function RegisterCastbarString(dbKey, attr, label, defaultValue, aliases, opts)
        opts = opts or {}
        opts.category = opts.category or "Appearance / Cast Bars"
        opts.frameType = opts.frameType or "castbar"
        opts.apply = opts.apply or ApplyCastbar
        RegisterGeneralString(dbKey, attr, label, defaultValue, aliases, opts)
    end

    return {
        CastbarAliases = CastbarAliases,
        UnitCastbarAliases = UnitCastbarAliases,
        ApplyCastbarTextures = ApplyCastbarTextures,
        ApplyCastbarOutline = ApplyCastbarOutline,
        ApplyFocusKick = ApplyFocusKick,
        ApplyFocusKickText = ApplyFocusKickText,
        RegisterCastbarBoolean = RegisterCastbarBoolean,
        RegisterCastbarNumber = RegisterCastbarNumber,
        RegisterCastbarEnum = RegisterCastbarEnum,
        RegisterCastbarString = RegisterCastbarString,
    }
end
