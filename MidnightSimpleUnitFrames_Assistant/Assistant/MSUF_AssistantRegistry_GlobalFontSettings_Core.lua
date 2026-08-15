-- Assistant global font setting helper context.
-- Loaded before MSUF_AssistantRegistry_GlobalFontSettings.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

local FontData = A.GlobalFontSettingsRegistryData or {}

function A.GlobalRegistry.BuildFontSettingsContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local GeneralDB = ctx.GeneralDB
    local NormalizeGlobalScope = ctx.NormalizeGlobalScope
    local GlobalScopeIsGroup = ctx.GlobalScopeIsGroup
    local GlobalScopeRead = ctx.GlobalScopeRead
    local GlobalScopeWrite = ctx.GlobalScopeWrite
    local GlobalScopeAliases = ctx.GlobalScopeAliases

    if type(GeneralDB) ~= "function" then return nil end
    if type(NormalizeGlobalScope) ~= "function" or type(GlobalScopeIsGroup) ~= "function" then return nil end
    if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return nil end
    if type(GlobalScopeAliases) ~= "function" then return nil end

    local function SharedOrScopedAliases(scope, aliases, suffix)
        if NormalizeGlobalScope(scope) == "shared" then return aliases end
        return GlobalScopeAliases(scope, aliases, suffix)
    end

    local function NormalizeFontTextAlpha(value)
        value = tonumber(value) or 1
        if value > 1 and value <= 100 then value = value / 100 end
        if value <= 0.75 then return 0.70 end
        if value <= 0.925 then return 0.85 end
        return 1
    end

    local function ScopedFontOutline(scope)
        if GlobalScopeIsGroup(scope) then
            local value = GlobalScopeRead(scope, "fontOverride", GeneralDB(), "fontOutline", "OUTLINE")
            return value == "THICKOUTLINE" and "THICKOUTLINE" or (value == "NONE" and "NONE" or "OUTLINE")
        end
        if GlobalScopeRead(scope, "fontOverride", GeneralDB(), "noOutline", false) then return "NONE" end
        if GlobalScopeRead(scope, "fontOverride", GeneralDB(), "boldText", false) then return "THICKOUTLINE" end
        return "OUTLINE"
    end

    local function SetScopedFontOutline(scope, value)
        value = FontData.FONT_OUTLINE_ALIASES[value] or value
        if value ~= "THICKOUTLINE" and value ~= "NONE" then value = "OUTLINE" end
        if value == "THICKOUTLINE"
            and GlobalScopeRead(scope, "fontOverride", GeneralDB(), "fontSlug", false)
        then
            value = "OUTLINE"
        end
        if GlobalScopeIsGroup(scope) then
            GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "fontOutline", value)
            return
        end
        GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "boldText", value == "THICKOUTLINE")
        GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "noOutline", value == "NONE")
    end

    local function ScopedFontNameColor(scope)
        if GlobalScopeIsGroup(scope) then
            return GlobalScopeRead(scope, "fontOverride", GeneralDB(), "nameColorMode", "DEFAULT") == "CLASS" and "CLASS" or "DEFAULT"
        end
        return GlobalScopeRead(scope, "fontOverride", GeneralDB(), "nameClassColor", false) and "CLASS" or "DEFAULT"
    end

    local function SetScopedFontNameColor(scope, value)
        value = value == "CLASS" and "CLASS" or "DEFAULT"
        if GlobalScopeIsGroup(scope) then
            GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "nameColorMode", value)
        else
            GlobalScopeWrite(scope, "fontOverride", GeneralDB(), "nameClassColor", value == "CLASS")
        end
    end

    return {
        FontData = FontData,
        SharedOrScopedAliases = SharedOrScopedAliases,
        NormalizeFontTextAlpha = NormalizeFontTextAlpha,
        ScopedFontOutline = ScopedFontOutline,
        SetScopedFontOutline = SetScopedFontOutline,
        ScopedFontNameColor = ScopedFontNameColor,
        SetScopedFontNameColor = SetScopedFontNameColor,
    }
end
