-- Assistant GroupFrames visual-overlay setting registry.
-- Keeps late visual metadata out of the main group settings file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterVisualSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupColor = ctx.RegisterGroupColor
    local NormalizeGroupDispelTrigger = ctx.NormalizeGroupDispelTrigger
    local GROUP_DISPEL_TRIGGER_VALUES = ctx.GROUP_DISPEL_TRIGGER_VALUES or {}
    local GROUP_DISPEL_STYLE_VALUES = ctx.GROUP_DISPEL_STYLE_VALUES or {}
    local GROUP_STRIPE_EDGE_VALUES = ctx.GROUP_STRIPE_EDGE_VALUES or {}
    local GROUP_RANGE_LAYER_VALUES = ctx.GROUP_RANGE_LAYER_VALUES or {}
    local RegisterVisualHighlightSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterVisualHighlightSettings

    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(ClampNumber) ~= "function" or type(NormalizeGroupDispelTrigger) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupColor) ~= "function" then return end
    if type(RegisterVisualHighlightSettings) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay")
    AddAliasesForUnit(aliases, scope, "debuff overlay")
    AddAliasesForUnit(aliases, scope, "dispellable overlay")
    AddAliasesForUnit(aliases, scope, "dispellable debuff overlay")
    AddAliasesForUnit(aliases, scope, "dispel health overlay")
    AddAliasesForUnit(aliases, scope, "dispellable health overlay")
    RegisterGroupBoolean(scope, "dispelOverlay", "dispelOverlayEnabled", "Dispel Overlay", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay detects")
    AddAliasesForUnit(aliases, scope, "dispel overlay trigger")
    AddAliasesForUnit(aliases, scope, "debuff overlay trigger")
    AddAliasesForUnit(aliases, scope, "dispellable overlay detects")
    AddAliasesForUnit(aliases, scope, "dispellable overlay trigger")
    AddAliasesForUnit(aliases, scope, "dispellable debuff overlay detects")
    AddAliasesForUnit(aliases, scope, "dispellable debuff overlay trigger")
    RegisterGroupEnum(scope, "dispelOverlayTrigger", "dispelOverlayTrigger", "Dispel Overlay Detects", "BORDER", GROUP_DISPEL_TRIGGER_VALUES, {
        border = "BORDER",
        inherit = "BORDER",
        same = "BORDER",
        ["dispel border"] = "BORDER",
        byme = "BY_ME",
        ["by me"] = "BY_ME",
        dispellable = "BY_ME",
        ["dispellable by me"] = "BY_ME",
        byraid = "BY_RAID",
        ["by raid"] = "BY_RAID",
        ["by group"] = "BY_RAID",
        ["dispellable by group"] = "BY_RAID",
        type = "DISPEL_TYPE",
        dispeltype = "DISPEL_TYPE",
        ["dispel type"] = "DISPEL_TYPE",
        any = "DISPEL_TYPE",
        debuff = "DISPEL_TYPE",
        ["any dispel type"] = "DISPEL_TYPE",
        ["any debuff"] = "DISPEL_TYPE",
        ["all debuffs"] = "DISPEL_TYPE",
    }, "visual", aliases, {
        get = function(scopeKey) return NormalizeGroupDispelTrigger(GroupDB(scopeKey).dispelOverlayTrigger) end,
        set = function(scopeKey, value) GroupDB(scopeKey).dispelOverlayTrigger = NormalizeGroupDispelTrigger(value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay style")
    AddAliasesForUnit(aliases, scope, "debuff overlay style")
    AddAliasesForUnit(aliases, scope, "dispellable overlay style")
    AddAliasesForUnit(aliases, scope, "dispellable debuff overlay style")
    RegisterGroupEnum(scope, "dispelOverlayStyle", "dispelOverlayStyle", "Dispel Overlay Style", "FULL", GROUP_DISPEL_STYLE_VALUES, {
        full = "FULL",
        ["full frame"] = "FULL",
        bottom = "BOTTOM",
        top = "TOP",
        left = "LEFT",
        right = "RIGHT",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay current health")
    AddAliasesForUnit(aliases, scope, "dispel overlay current health only")
    AddAliasesForUnit(aliases, scope, "dispel overlay on current health only")
    AddAliasesForUnit(aliases, scope, "dispel overlay on health")
    AddAliasesForUnit(aliases, scope, "debuff overlay on health")
    AddAliasesForUnit(aliases, scope, "debuff overlay current health only")
    AddAliasesForUnit(aliases, scope, "dispellable overlay on health")
    AddAliasesForUnit(aliases, scope, "dispellable overlay current health only")
    AddAliasesForUnit(aliases, scope, "dispellable debuff overlay current health only")
    RegisterGroupBoolean(scope, "dispelOverlayOnHealth", "dispelOverlayOnHealth", "Dispel Overlay on Current Health", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dispel overlay opacity")
    AddAliasesForUnit(aliases, scope, "dispel overlay alpha")
    AddAliasesForUnit(aliases, scope, "debuff overlay opacity")
    AddAliasesForUnit(aliases, scope, "dispellable overlay opacity")
    AddAliasesForUnit(aliases, scope, "dispellable overlay alpha")
    AddAliasesForUnit(aliases, scope, "dispellable debuff overlay opacity")
    RegisterGroupNumber(scope, "dispelOverlayAlpha", "dispelOverlayAlpha", "Dispel Overlay Opacity", 0.35, 0.05, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe")
    AddAliasesForUnit(aliases, scope, "debuff stripe enabled")
    RegisterGroupBoolean(scope, "debuffStripe", "debuffStripeEnabled", "Debuff Stripe", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe edge")
    AddAliasesForUnit(aliases, scope, "debuff stripe position")
    RegisterGroupEnum(scope, "debuffStripeEdge", "debuffStripeEdge", "Debuff Stripe Edge", "BOTTOM", GROUP_STRIPE_EDGE_VALUES, {
        bottom = "BOTTOM",
        lower = "BOTTOM",
        top = "TOP",
        upper = "TOP",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe height")
    AddAliasesForUnit(aliases, scope, "debuff stripe size")
    RegisterGroupNumber(scope, "debuffStripeHeight", "debuffStripeHeight", "Debuff Stripe Height", 3, 1, 8, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe opacity")
    AddAliasesForUnit(aliases, scope, "debuff stripe alpha")
    RegisterGroupNumber(scope, "debuffStripeAlpha", "debuffStripeAlpha", "Debuff Stripe Opacity", 0.60, 0.10, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "debuff stripe color")
    AddAliasesForUnit(aliases, scope, "stripe color")
    RegisterGroupColor(scope, "debuffStripeColor", "debuffStripeColor", "Debuff Stripe Color", 0.80, 0.20, 0.20, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade affects")
    AddAliasesForUnit(aliases, scope, "range fade layer")
    AddAliasesForUnit(aliases, scope, "range fade mode")
    RegisterGroupEnum(scope, "rangeFadeLayerMode", "rangeFadeLayerMode", "Range Fade Affects", "frame", GROUP_RANGE_LAYER_VALUES, {
        frame = "frame",
        whole = "frame",
        ["whole frame"] = "frame",
        health = "health",
        hp = "health",
        ["hp only"] = "health",
        ["health only"] = "health",
    }, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "offline fade")
    AddAliasesForUnit(aliases, scope, "dim offline members")
    AddAliasesForUnit(aliases, scope, "dim disconnected members")
    RegisterGroupBoolean(scope, "offlineFade", "offlineFadeEnabled", "Offline Fade", false, "visual", aliases, {
        description = "Dims group frames of disconnected members to the offline opacity. Hiding offline members takes precedence over this.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "offline alpha")
    AddAliasesForUnit(aliases, scope, "offline opacity")
    AddAliasesForUnit(aliases, scope, "offline member opacity")
    AddAliasesForUnit(aliases, scope, "offline transparency")
    AddAliasesForUnit(aliases, scope, "fade offline members")
    AddAliasesForUnit(aliases, scope, "offline member fade")
    RegisterGroupNumber(scope, "offlineAlpha", "offlineAlpha", "Offline Opacity", 0.5, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health fade")
    AddAliasesForUnit(aliases, scope, "healthy fade")
    AddAliasesForUnit(aliases, scope, "healer health fade")
    AddAliasesForUnit(aliases, scope, "fade healthy members")
    AddAliasesForUnit(aliases, scope, "dim healthy members")
    AddAliasesForUnit(aliases, scope, "dim healthy frames")
    AddAliasesForUnit(aliases, scope, "fade full health")
    AddAliasesForUnit(aliases, scope, "dim full health")
    RegisterGroupBoolean(scope, "healthFade", "healthFadeEnabled", "Health Fade", false, "visual", aliases, {
        description = "Dims group frames when a member is at or above the configured health percentage.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health fade threshold")
    AddAliasesForUnit(aliases, scope, "health fade percent")
    AddAliasesForUnit(aliases, scope, "fade above health")
    AddAliasesForUnit(aliases, scope, "fade above health percent")
    AddAliasesForUnit(aliases, scope, "dim above health")
    AddAliasesForUnit(aliases, scope, "dim above health percent")
    AddAliasesForUnit(aliases, scope, "healthy frame threshold")
    RegisterGroupNumber(scope, "healthFadeThreshold", "healthFadeThreshold", "Health Fade Threshold", 95, 1, 100, 1, "visual", aliases, {
        description = "Health percentage at or above which health fade dims group frames.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health fade opacity")
    AddAliasesForUnit(aliases, scope, "health fade alpha")
    AddAliasesForUnit(aliases, scope, "healthy frame opacity")
    AddAliasesForUnit(aliases, scope, "healthy member opacity")
    AddAliasesForUnit(aliases, scope, "dimmed health opacity")
    AddAliasesForUnit(aliases, scope, "dimmed healthy opacity")
    RegisterGroupNumber(scope, "healthFadeAlpha", "healthFadeAlpha", "Health Fade Opacity", 0.45, 0.05, 1, 0.05, "visual", aliases, { percent = true })

    RegisterVisualHighlightSettings(ctx, scope)
end
