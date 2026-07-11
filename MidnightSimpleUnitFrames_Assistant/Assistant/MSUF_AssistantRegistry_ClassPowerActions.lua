local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Class Resources assistant action domain.
-- Depends on MSUF_AssistantRegistry_ClassPower.lua for preview parser helpers.
local ctx = A.ClassPowerRegistry and A.ClassPowerRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
M = ctx.M or M
local ParseClassPowerPreviewAnimationAliasArgs = ctx.ParseClassPowerPreviewAnimationAliasArgs

if not (Registry and type(Registry.RegisterAction) == "function") then return end
Registry:RegisterAction({
    key = "class_power_preview_animate",
    label = "Animate Class Resource Preview",
    type = "classPower",
    aliases = {
        "animate class resource preview",
        "animate class power preview",
        "animate class resource",
        "animate class power",
        "start class resource animation",
        "stop class resource animation",
        "start class power animation",
        "stop class power animation",
        "turn on class resource animation",
        "turn off class resource animation",
        "start class resource preview animation",
        "stop class resource preview animation",
        "toggle class resource preview animation",
        "start resource preview animation",
        "stop resource preview animation",
    },
    parseAliasArgs = ParseClassPowerPreviewAnimationAliasArgs,
    combatSafe = true,
    run = function(args)
        local preview = M and M._msuf2ClassPowerInlinePreview
        if not (preview and type(preview.SetPreviewAnimating) == "function") then
            return false, "Open Class Resources first so I can animate the preview."
        end
        local value = args and args.value
        if value == nil then value = not preview._msuf2Animating end
        preview:SetPreviewAnimating(value and true or false)
        return true, value and "Started the Class Resource preview animation." or "Stopped the Class Resource preview animation."
    end,
})

Registry:RegisterAction({
    key = "class_power_quick_setup",
    label = "Quick Setup Class Resources",
    type = "classPower",
    aliases = {
        "quick setup class resources",
        "quick setup class resource",
        "quick setup class power",
        "quick setup class bar",
        "class resource quick setup",
        "class resources quick setup",
        "class power quick setup",
        "setup class resources",
        "setup class resource",
        "setup class power",
    },
    aliasNoArgs = true,
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        local fn = _G.MSUF2_ClassPowerQuickSetup
        if type(fn) ~= "function" then return false, "Open Class Resources first so I can run quick setup." end
        fn()
        return true, "Done. Started the Class Resources quick setup."
    end,
})
