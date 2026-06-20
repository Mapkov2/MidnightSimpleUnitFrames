-- Assistant Global Bar scoped unit dispel overlay registry.
-- Loaded before MSUF_AssistantRegistry_GlobalBarSettings_Scoped_Overlays.lua; called by the scoped overlay registrar for non-group scopes.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalBarRegistry = A.GlobalBarRegistry or {}

function A.GlobalBarRegistry.RegisterScopedUnitDispelOverlaySettings(ctx, scope)
    if type(ctx) ~= "table" then return false end

    local ApplyDispelPurgeBorder = ctx.ApplyDispelPurgeBorder
    local RegisterScopedSetting = ctx.RegisterScopedSetting
    local GlobalScopeAliases = ctx.GlobalScopeAliases
    local UNIT_DISPEL_TRIGGER_VALUES = ctx.UNIT_DISPEL_TRIGGER_VALUES
    local UNIT_DISPEL_TRIGGER_ALIASES = ctx.UNIT_DISPEL_TRIGGER_ALIASES
    local UNIT_DISPEL_STYLE_VALUES = ctx.UNIT_DISPEL_STYLE_VALUES
    local UNIT_DISPEL_STYLE_ALIASES = ctx.UNIT_DISPEL_STYLE_ALIASES

    if type(RegisterScopedSetting) ~= "function" or type(GlobalScopeAliases) ~= "function" then return false end

    RegisterScopedSetting("barScope", scope, "unitDispelOverlayEnabled", "unitDispelOverlay", "UnitFrame Dispel Overlay", "boolean", false, GlobalScopeAliases(scope, {
        "unitframe dispel overlay", "unit frame dispel overlay", "dispel overlay", "health bar dispel overlay",
    }), {
        flag = "hlOverride",
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY",
    })
    RegisterScopedSetting("barScope", scope, "unitDispelOverlayTrigger", "unitDispelOverlayTrigger", "UnitFrame Dispel Overlay Detects", "enum", "BORDER", GlobalScopeAliases(scope, {
        "unitframe dispel overlay detects", "unitframe dispel overlay trigger", "dispel overlay detects",
    }), {
        flag = "hlOverride",
        values = UNIT_DISPEL_TRIGGER_VALUES,
        valueAliases = UNIT_DISPEL_TRIGGER_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_TRIGGER",
    })
    RegisterScopedSetting("barScope", scope, "unitDispelOverlayStyle", "unitDispelOverlayStyle", "UnitFrame Dispel Overlay Style", "enum", "FULL", GlobalScopeAliases(scope, {
        "unitframe dispel overlay style", "dispel overlay style", "unit frame dispel overlay style",
    }), {
        flag = "hlOverride",
        values = UNIT_DISPEL_STYLE_VALUES,
        valueAliases = UNIT_DISPEL_STYLE_ALIASES,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_STYLE",
    })
    RegisterScopedSetting("barScope", scope, "unitDispelOverlayOnHealth", "unitDispelOverlayHealthOnly", "UnitFrame Dispel Overlay Current Health Only", "boolean", true, GlobalScopeAliases(scope, {
        "dispel overlay current health only", "unitframe dispel overlay current health", "dispel overlay on health only",
    }), {
        flag = "hlOverride",
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_HEALTH",
    })
    RegisterScopedSetting("barScope", scope, "unitDispelOverlayAlpha", "unitDispelOverlayOpacity", "UnitFrame Dispel Overlay Opacity", "number", 0.35, GlobalScopeAliases(scope, {
        "dispel overlay opacity", "unitframe dispel overlay opacity", "dispel overlay alpha",
    }), {
        flag = "hlOverride",
        min = 0.05,
        max = 1,
        step = 0.05,
        percent = true,
        apply = ApplyDispelPurgeBorder,
        reason = "MSUF_ASSISTANT_SCOPED_UNIT_DISPEL_OVERLAY_ALPHA",
    })

    return true
end
