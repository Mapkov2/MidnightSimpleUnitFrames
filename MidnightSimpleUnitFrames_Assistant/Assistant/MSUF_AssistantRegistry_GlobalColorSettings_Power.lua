-- Assistant power color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

local function KnownPowerColorToken(tokens, token)
    token = tostring(token or ""):upper():gsub("%s+", "_")
    for i = 1, #(tokens or {}) do
        local row = tokens[i]
        if row.key == token then return row.key, row.label end
    end
    return nil, nil
end

function A.GlobalRegistry.RegisterPowerColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local ColorSetting = ctx.ColorSetting
    local EnsurePowerOverrides = ctx.EnsurePowerOverrides
    local PowerOverrideRGB = ctx.PowerOverrideRGB
    local SetPowerOverrideRGB = ctx.SetPowerOverrideRGB
    local ApplyColors = ctx.ApplyColors
    local COLOR_POWER_TOKENS = ctx.COLOR_POWER_TOKENS or {}

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(ColorSetting) ~= "function" or type(EnsurePowerOverrides) ~= "function" then return end
    if type(PowerOverrideRGB) ~= "function" or type(SetPowerOverrideRGB) ~= "function" then return end

    A.PowerColorTokens = COLOR_POWER_TOKENS
    for i = 1, #COLOR_POWER_TOKENS do
        local token = COLOR_POWER_TOKENS[i].key
        local label = COLOR_POWER_TOKENS[i].label
        local lower = label:lower()
        local aliases = { lower .. " power color", lower .. " bar color", lower .. " resource color" }
        if token ~= "FOCUS" then aliases[#aliases + 1] = lower .. " color" end
        ColorSetting("general.powerColorOverrides." .. token, label .. " Power Bar Color", aliases, function()
            return PowerOverrideRGB(token)
        end, function(r, g, b)
            SetPowerOverrideRGB(token, r, g, b)
        end, { category = "Colors / Power", attribute = "powerColor", apply = ApplyColors })
    end

    Registry:RegisterAction({
        key = "reset_power_color_token",
        label = "Reset Power Bar Token Color",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local token, label = KnownPowerColorToken(COLOR_POWER_TOKENS, args and args.token)
            if not token then return false, "Which power color do you want me to change?" end
            EnsurePowerOverrides()[token] = nil
            if type(ApplyColors) == "function" then ApplyColors("MSUF_ASSISTANT_RESET_POWER_COLOR_TOKEN") end
            return true, "Done. Reset " .. tostring(label) .. " power bar color."
        end,
    })
end
