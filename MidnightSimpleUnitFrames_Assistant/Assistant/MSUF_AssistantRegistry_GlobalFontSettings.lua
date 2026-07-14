-- Assistant Global Font registry: exposes shared font, size, outline, and override controls.
-- Writes must preserve Menu2 fallback semantics and avoid direct FontString runtime ownership.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Scoped Global Fonts assistant registry domain.
local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
local ApplyFonts = C.ApplyFonts
local GLOBAL_SCOPE_ORDER = C.GLOBAL_SCOPE_ORDER
local NormalizeGlobalScope = C.NormalizeGlobalScope
local GlobalScopeIsGroup = C.GlobalScopeIsGroup
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeSetOverride = C.GlobalScopeSetOverride
local GlobalScopeRead = C.GlobalScopeRead
local GlobalScopeWrite = C.GlobalScopeWrite
local GlobalScopeAliases = C.GlobalScopeAliases
local RegisterScopedSetting = C.RegisterScopedSetting

if type(EnsureDB) ~= "function" or type(GeneralDB) ~= "function" or type(RegisterScopedSetting) ~= "function" then return end
if type(GLOBAL_SCOPE_ORDER) ~= "table" or type(GlobalScopeAliases) ~= "function" then return end
if type(NormalizeGlobalScope) ~= "function" or type(GlobalScopeIsGroup) ~= "function" then return end
if type(GlobalScopeHasOverride) ~= "function" or type(GlobalScopeSetOverride) ~= "function" then return end
if type(GlobalScopeRead) ~= "function" or type(GlobalScopeWrite) ~= "function" then return end
do
local GlobalRegistry = A.GlobalRegistry
local BuildFontSettingsContext = GlobalRegistry and GlobalRegistry.BuildFontSettingsContext
if type(BuildFontSettingsContext) ~= "function" then return end

local FontContext = BuildFontSettingsContext({
    GeneralDB = GeneralDB,
    NormalizeGlobalScope = NormalizeGlobalScope,
    GlobalScopeIsGroup = GlobalScopeIsGroup,
    GlobalScopeRead = GlobalScopeRead,
    GlobalScopeWrite = GlobalScopeWrite,
    GlobalScopeAliases = GlobalScopeAliases,
})
if type(FontContext) ~= "table" then return end

local RegisterScopedFontDetailSettings = GlobalRegistry and GlobalRegistry.RegisterScopedFontDetailSettings
if type(RegisterScopedFontDetailSettings) ~= "function" then return end

for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
    RegisterScopedSetting("fontScope", scope, "override", "override", "Font Override", "boolean", false, GlobalScopeAliases(scope, {
        "font override", "custom fonts", "custom font settings", "font custom settings",
    }), {
        flag = "fontOverride",
        get = function(scopeKey) return GlobalScopeHasOverride(scopeKey, "fontOverride") end,
        set = function(scopeKey, value) GlobalScopeSetOverride(scopeKey, "fontOverride", value and true or false) end,
        dbScopeKeys = { "fontOverride" },
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_FONT_OVERRIDE",
        description = "Enables or disables custom font settings for this target.",
    })
    RegisterScopedSetting("fontScope", scope, "fontSize", "fontSize", "Font Size", "number", 14, GlobalScopeAliases(scope, {
        "font size", "text size", "global font size", "scope font size",
    }), {
        flag = "fontOverride",
        min = 8,
        max = 32,
        apply = ApplyFonts,
        reason = "MSUF_ASSISTANT_SCOPED_FONT_SIZE",
    })
end

if RegisterScopedFontDetailSettings({
    EnsureDB = EnsureDB,
    GeneralDB = GeneralDB,
    ApplyFonts = ApplyFonts,
    GlobalScopeIsGroup = GlobalScopeIsGroup,
    GlobalScopeRead = GlobalScopeRead,
    GlobalScopeWrite = GlobalScopeWrite,
    GlobalScopeAliases = GlobalScopeAliases,
    RegisterScopedSetting = RegisterScopedSetting,
    FontContext = FontContext,
}) == false then return end

end
