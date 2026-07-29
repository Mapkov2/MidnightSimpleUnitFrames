local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames assistant setting domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for shared group helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.Settings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
if not (Registry and type(Registry.RegisterSetting) == "function") then return end

local RegisterGroupStatusIconSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterStatusIconSettings
local RegisterGroupTextBasics = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterTextBasics
local RegisterGroupTextSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterTextSettings
local RegisterGroupVisualSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterVisualSettings
local RegisterGroupScalingSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterScalingSettings
local RegisterGroupLayoutSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterLayoutSettings
local RegisterGroupPortraitSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterPortraitSettings
local RegisterGroupBasicSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterBasicSettings
local RegisterPrioritySettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterPrioritySettings
local RegisterGroupBarAndPowerSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterBarAndPowerSettings
local RegisterFramePowerToggleSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterFramePowerToggleSettings
local RegisterFrameOrderingSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterFrameOrderingSettings
local RegisterFrameAlphaAnchorSettings = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterFrameAlphaAnchorSettings

do
for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    if type(RegisterGroupBasicSettings) == "function" then
        RegisterGroupBasicSettings(ctx, scope)
    end

    local widthDefault = scope == "party" and 120 or 80
    local heightDefault = scope == "party" and 40 or 32
    local powerHeightDefault = scope == "party" and 6 or 4
    local hpFontDefault = scope == "party" and 10 or 9
    local nameFontDefault = scope == "party" and 12 or 10
    local textCenterDefault = scope == "party" and "PERCENT" or "NONE"
    local maxColumnsDefault = scope == "party" and 1 or 8

    if type(RegisterGroupTextBasics) == "function" then
        RegisterGroupTextBasics(ctx, scope, {
            hpFontSize = hpFontDefault,
            nameFontSize = nameFontDefault,
            textCenter = textCenterDefault,
        })
    end

    if type(RegisterFramePowerToggleSettings) == "function" then
        RegisterFramePowerToggleSettings(ctx, scope)
    end

    if type(RegisterGroupLayoutSettings) == "function" then
        RegisterGroupLayoutSettings(ctx, scope, {
            width = widthDefault,
            height = heightDefault,
            maxColumns = maxColumnsDefault,
            powerHeight = powerHeightDefault,
        })
    end

    if scope == "party" and type(RegisterGroupPortraitSettings) == "function" then
        RegisterGroupPortraitSettings(ctx)
    end

    if type(RegisterFrameOrderingSettings) == "function" then
        RegisterFrameOrderingSettings(ctx, scope)
    end

    if type(RegisterGroupScalingSettings) == "function" then
        RegisterGroupScalingSettings(ctx, scope)
    end

    if type(RegisterFrameAlphaAnchorSettings) == "function" then
        RegisterFrameAlphaAnchorSettings(ctx, scope)
    end

    if type(RegisterGroupBarAndPowerSettings) == "function" then
        RegisterGroupBarAndPowerSettings(ctx, scope)
    end

    if type(RegisterGroupTextSettings) == "function" then
        RegisterGroupTextSettings(ctx, scope)
    end

    if type(RegisterGroupVisualSettings) == "function" then
        RegisterGroupVisualSettings(ctx, scope)
    end

    if type(RegisterGroupStatusIconSettings) == "function" then RegisterGroupStatusIconSettings(ctx, scope) end

end
end

if type(RegisterPrioritySettings) == "function" then
    RegisterPrioritySettings(ctx)
end
