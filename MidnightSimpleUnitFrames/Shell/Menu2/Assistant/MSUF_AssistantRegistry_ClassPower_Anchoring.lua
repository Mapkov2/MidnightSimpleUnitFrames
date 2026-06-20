-- Assistant ClassPower anchoring setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterAnchoringSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local ClassPowerAliases = ctx.ClassPowerAliases
    local CLASS_POWER_PLACEMENT_TERMS = A.ClassPowerRegistry.CLASS_POWER_PLACEMENT_TERMS
    local ClassPowerPlacementXValue = A.ClassPowerRegistry.ClassPowerPlacementXValue
    local ClassPowerPlacementYValue = A.ClassPowerRegistry.ClassPowerPlacementYValue
    if type(RegisterBarsBoolean) ~= "function" or type(ClassPowerAliases) ~= "function" then return end
    if type(CLASS_POWER_PLACEMENT_TERMS) ~= "table" then return end
    if type(ClassPowerPlacementXValue) ~= "function" or type(ClassPowerPlacementYValue) ~= "function" then return end

    RegisterBarsBoolean("classPowerAnchorToCooldown", "anchorToCooldown", "Class Resource Anchor to Essential Cooldowns", false, ClassPowerAliases(
        "anchor to cooldown", "anchor to cooldowns", "anchor to essential cooldowns",
        "anchor to essential cooldownmanager", "anchor to cooldownmanager",
        "class resource anchor to essential cooldowns", "class resource anchor to essential cooldownmanager",
        "class power follow cooldowns", "class resource follow essential cooldowns",
        "follow essential cooldowns", "follow cooldownmanager", "position above essential cooldowns"
    ), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_ANCHOR_COOLDOWN",
        valueAliases = {
            ["to cooldown"] = true,
            ["to cooldowns"] = true,
            ["to cooldown manager"] = true,
            ["to cooldownmanager"] = true,
            ["to essential cooldowns"] = true,
            ["to essential cooldownmanager"] = true,
            ["attach to cooldownmanager"] = true,
            ["dock to cooldownmanager"] = true,
            ["follow cooldownmanager"] = true,
            ["follow essential cooldowns"] = true,
            player = false,
            ["player frame"] = false,
            playerframe = false,
            ["unit frame"] = false,
            detach = false,
            detached = false,
            undock = false,
            disconnect = false,
            ["stop following"] = false,
            ["do not follow"] = false,
            ["dont follow"] = false,
            ["remove from"] = false,
        },
        companionChanges = {
            {
                key = "bars.classPowerWidthMode",
                value = "player",
                whenValue = false,
                whenTextHas = { "player", "player frame", "unit frame" },
            },
            {
                key = "bars.classPowerOffsetX",
                value = ClassPowerPlacementXValue,
                whenValue = false,
                whenTextHas = CLASS_POWER_PLACEMENT_TERMS,
            },
            {
                key = "bars.classPowerOffsetY",
                value = ClassPowerPlacementYValue,
                whenValue = false,
                whenTextHas = CLASS_POWER_PLACEMENT_TERMS,
            },
            {
                key = "bars.classPowerWidthMode",
                value = "cooldown",
                whenValue = true,
                whenTextHas = { "width", "match width", "same width" },
            },
        },
        exactAliases = {
            "anchor class resource to cooldownmanager",
            "anchor class resources to cooldownmanager",
            "anchor class resource to cooldown manager",
            "anchor class resources to cooldown manager",
            "anchor class resource to essential cooldowns",
            "anchor class resources to essential cooldowns",
            "anchor class resource to essential cooldownmanager",
            "anchor class resources to essential cooldownmanager",
            "attach class resource to cooldownmanager",
            "attach class resources to cooldownmanager",
            "dock class resource to cooldownmanager",
            "dock class resources to cooldownmanager",
            "follow cooldownmanager with class resource",
            "follow cooldownmanager with class resources",
            "anchor combo points to cooldownmanager",
            "anchor combo points to cooldown manager",
            "anchor combo points to essential cooldowns",
            "attach combo points to cooldownmanager",
            "dock combo points to cooldownmanager",
            "anchor class resource to player frame",
            "anchor class resources to player frame",
            "anchor class resource player frame",
            "anchor class resources player frame",
            "class resource anchor to player frame",
            "class resources anchor to player frame",
            "anchor combo points to player frame",
            "combo points anchor to player frame",
            "move class resource under player frame",
            "move class resources under player frame",
            "move class resource below player frame",
            "move class resources below player frame",
            "put class resource under player frame",
            "put class resources under player frame",
            "put class resource below player frame",
            "put class resources below player frame",
            "move combo points under player frame",
            "put combo points under player frame",
            "move combo points below player frame",
            "put combo points below player frame",
            "move class resource above player frame",
            "move class resources above player frame",
            "put class resource above player frame",
            "put class resources above player frame",
            "move combo points above player frame",
            "put combo points above player frame",
            "move class resource on player frame",
            "move class resources on player frame",
            "put class resource on player frame",
            "put class resources on player frame",
            "move combo points on player frame",
            "put combo points on player frame",
            "detach class resource from cooldownmanager",
            "detach class resources from cooldownmanager",
            "detach class resource from cooldown manager",
            "detach class resources from cooldown manager",
            "detach combo points from cooldownmanager",
            "detach combo points from cooldown manager",
            "undock class resource from cooldownmanager",
            "undock combo points from cooldownmanager",
            "stop class resource following cooldownmanager",
            "stop combo points following cooldownmanager",
        },
    })
end
