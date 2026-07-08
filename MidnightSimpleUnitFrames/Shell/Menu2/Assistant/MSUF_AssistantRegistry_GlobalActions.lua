local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Global assistant action domain.
-- Depends on MSUF_AssistantRegistry_Global.lua for scoped global helpers.
local ctx = A.GlobalRegistry and A.GlobalRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
M = ctx.M or M
local NormalizeGlobalScope = ctx.NormalizeGlobalScope
local GlobalScopeSetOverride = ctx.GlobalScopeSetOverride
local GlobalScopeLabel = ctx.GlobalScopeLabel
local GLOBAL_SCOPE_ORDER = ctx.GLOBAL_SCOPE_ORDER or {}
local ApplyBars = ctx.ApplyBars
local ApplyFonts = ctx.ApplyFonts
local ApplyAbsorbBars = ctx.ApplyAbsorbBars

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(NormalizeGlobalScope) ~= "function" or type(GlobalScopeSetOverride) ~= "function" or type(GlobalScopeLabel) ~= "function" then return end

local BORDER_TEST_LABELS = {
    aggro = "aggro",
    dispel = "dispel",
    purge = "purge",
    bossTarget = "boss target",
}

local function ResetGlobalScopeOverride(flag, scope, applyFn, reason)
    scope = NormalizeGlobalScope(scope)
    if scope == "shared" then return false, "Shared options already use the base value, so there is no override to reset." end
    GlobalScopeSetOverride(scope, flag, false)
    if type(applyFn) == "function" then applyFn(reason, scope) end
    return true, "Done. " .. GlobalScopeLabel(scope) .. " now follows Shared options."
end

local function ResetAllGlobalScopeOverrides(flag, applyFn, reason, label)
    for _, scope in ipairs(GLOBAL_SCOPE_ORDER) do
        GlobalScopeSetOverride(scope, flag, false)
    end
    if type(applyFn) == "function" then applyFn(reason) end
    return true, "Done. All " .. tostring(label or "matching") .. " overrides now follow Shared options."
end

Registry:RegisterAction({
    key = "reset_scoped_global_bars_override",
    label = "Reset Section Bars Override",
    type = "globalBars",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        return ResetGlobalScopeOverride("hlOverride", args and args.scope, ApplyBars, "MSUF_ASSISTANT_RESET_SCOPED_BARS")
    end,
})
Registry:RegisterAction({
    key = "reset_all_scoped_global_bars_overrides",
    label = "Reset All Section Bars Overrides",
    type = "globalBars",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        return ResetAllGlobalScopeOverrides("hlOverride", ApplyBars, "MSUF_ASSISTANT_RESET_ALL_SCOPED_BARS", "Bars")
    end,
})

Registry:RegisterAction({
    key = "reset_scoped_global_font_override",
    label = "Reset Section Font Override",
    type = "fonts",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        return ResetGlobalScopeOverride("fontOverride", args and args.scope, ApplyFonts, "MSUF_ASSISTANT_RESET_SCOPED_FONTS")
    end,
})

Registry:RegisterAction({
    key = "reset_all_scoped_global_font_overrides",
    label = "Reset All Section Font Overrides",
    type = "fonts",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        return ResetAllGlobalScopeOverrides("fontOverride", ApplyFonts, "MSUF_ASSISTANT_RESET_ALL_SCOPED_FONTS", "Font")
    end,
})


Registry:RegisterAction({
    key = "toggle_absorb_bar_test",
    label = "Toggle Absorb Bar Test",
    type = "globalBars",
    combatSafe = true,
    run = function(args)
        local value = args and args.value
        if value == nil then value = not (_G.MSUF_AbsorbTextureTestMode == true) end
        local fn = _G.MSUF_SetAbsorbTextureTestMode
        if type(fn) == "function" then
            fn(value and true or false, "shared")
        else
            ExportPublic("MSUF_AbsorbTextureTestMode", value and true or false)
            ExportPublic("MSUF_AbsorbTextureTestScope", "shared")
        end
        ApplyAbsorbBars("MSUF_ASSISTANT_ABSORB_TEST")
        return true, (value and "Enabled" or "Disabled") .. " absorb prediction bar test."
    end,
})

Registry:RegisterAction({
    key = "toggle_highlight_border_test",
    label = "Toggle Highlight Border Test",
    type = "globalBars",
    combatSafe = true,
    run = function(args)
        local kind = tostring(args and args.kind or "aggro")
        local enabled = args and args.value
        if enabled == nil then enabled = true end
        local setterName
        if kind == "dispel" then setterName = "MSUF_SetDispelBorderTestMode"
        elseif kind == "purge" then setterName = "MSUF_SetPurgeBorderTestMode"
        elseif kind == "bossTarget" then setterName = "MSUF_SetBossTargetBorderTestMode"
        else kind, setterName = "aggro", "MSUF_SetAggroBorderTestMode" end
        local fn = _G[setterName]
        if type(fn) == "function" then
            if kind == "bossTarget" then fn(enabled and true or false) else fn(enabled and true or false, "shared") end
        else
            ExportPublic("MSUF_" .. kind .. "BorderTestMode", enabled and true or false)
        end
        return true, (enabled and "Enabled" or "Disabled") .. " " .. tostring(BORDER_TEST_LABELS[kind] or kind) .. " border test."
    end,
})
