-- Assistant global visual workflow helpers: UI scale, tooltip, and style behavior.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterVisualWorkflowSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    M = ctx.M or M
    MSUF = ctx.MSUF or MSUF
    local GeneralDB = ctx.GeneralDB
    local ClampNumber = ctx.ClampNumber
    local CallGlobal = ctx.CallGlobal
    local ApplyGeneral = ctx.ApplyGeneral

    if not (Registry and type(Registry.RegisterSetting) == "function" and type(Registry.RegisterAction) == "function") then return end
    if type(GeneralDB) ~= "function" or type(ClampNumber) ~= "function" then return end
    if type(CallGlobal) ~= "function" or type(ApplyGeneral) ~= "function" then return end

    A.Workflow = A.Workflow or {}

    function A.Workflow.ClampScale(value, minValue, maxValue)
        return ClampNumber(value, minValue or 0.25, maxValue or 1.5, 0.01)
    end

    function A.Workflow.GlobalScaleState()
        local g = GeneralDB()
        g.UIScale = type(g.UIScale) == "table" and g.UIScale or { Enabled = false, Scale = 1 }
        local ui = g.UIScale
        ui.Enabled = ui.Enabled == true
        ui.Scale = A.Workflow.ClampScale(ui.Scale, 0.3, 1.5) or 1
        return g, ui
    end

    function A.Workflow.PixelScale()
        if type(_G.MSUF_GetPixelPerfectScale) == "function" then
            local value = tonumber(_G.MSUF_GetPixelPerfectScale())
            if value then return A.Workflow.ClampScale(value, 0.3, 1.5) or 1 end
        end
        if type(_G.GetPhysicalScreenSize) == "function" then
            local _, height = _G.GetPhysicalScreenSize()
            height = tonumber(height)
            if height and height > 0 then return A.Workflow.ClampScale(768 / height, 0.3, 1.5) or 1 end
        end
        return 1
    end

    function A.Workflow.GlobalScalePresetValue(preset)
        preset = tostring(preset or "custom"):lower()
        if preset == "1080" or preset == "1080p" then return true, 768 / 1080, "1080p" end
        if preset == "1440" or preset == "1440p" then return true, 768 / 1440, "1440p" end
        if preset == "4k" or preset == "2160" or preset == "2160p" then return true, 768 / 2160, "4k" end
        if preset == "pixel" or preset == "pixel perfect" then return true, A.Workflow.PixelScale(), "pixel" end
        if preset == "off" or preset == "auto" or preset == "disabled" then return false, 1, "auto" end
        return nil, nil, nil
    end

    function A.Workflow.SetGlobalScaleState(enabled, value, preset)
        local g, ui = A.Workflow.GlobalScaleState()
        ui.Enabled = enabled == true
        ui.Scale = A.Workflow.ClampScale(value or ui.Scale, 0.3, 1.5) or 1
        g.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
        g.globalUiScaleValue = ui.Enabled and ui.Scale or nil
    end

    function A.Workflow.PushGlobalScale()
        local _, ui = A.Workflow.GlobalScaleState()
        if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
            _G.MSUF_SetGlobalUiScale(ui.Scale, true)
        elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            _G.MSUF_ResetGlobalUiScale(true)
        end
        ApplyGeneral("MSUF_ASSISTANT_GLOBAL_UI_SCALE", { preview = true, applyAll = false })
    end

    local GLOBAL_SCALE_PRESET_LABELS = {
        ["1080p"] = "1080p",
        ["1440p"] = "1440p",
        ["4k"] = "4K",
        pixel = "pixel-perfect",
        auto = "automatic",
        custom = "custom",
    }

    local function GlobalScalePresetLabel(key)
        key = tostring(key or "")
        return GLOBAL_SCALE_PRESET_LABELS[key] or key:gsub("_", " ")
    end

    function A.Workflow.ApplyScalePreset(preset)
        local enabled, value, key = A.Workflow.GlobalScalePresetValue(preset)
        if enabled == nil then return false, "Which global UI scale preset do you want me to use?" end
        A.Workflow.SetGlobalScaleState(enabled, value, key)
        A.Workflow.PushGlobalScale()
        return true, enabled and ("Done. Applied global UI scale preset " .. GlobalScalePresetLabel(key) .. ".") or "Done. Global UI scale override is off."
    end

    function A.Workflow.ApplyMsufScale(value)
        local scale = A.Workflow.ClampScale(value, 0.25, 2.0) or 1
        GeneralDB().msufUiScale = scale
        if type(_G.MSUF_ApplyMsufScale) == "function" then _G.MSUF_ApplyMsufScale(scale) end
        ApplyGeneral("MSUF_ASSISTANT_MSUF_SCALE", { preview = true, applyAll = false, notify = false })
    end

    function A.Workflow.ApplyMenuScale(value)
        local scale = A.Workflow.ClampScale(value, 0.2, 1.6) or 0.8
        GeneralDB().slashMenuScale = scale
        if M and M.frame and type(M.frame.SetScale) == "function" then
            M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(scale)) or scale)
        end
    end

    function A.Workflow.ModuleStyleEnabled()
        if type(_G.MSUF_StyleIsEnabled) == "function" then return _G.MSUF_StyleIsEnabled() and true or false end
        return GeneralDB().styleEnabled ~= false
    end

    function A.Workflow.SetModuleStyleEnabled(enabled)
        enabled = enabled and true or false
        if type(_G.MSUF_SetStyleEnabled) == "function" then
            _G.MSUF_SetStyleEnabled(enabled)
        else
            GeneralDB().styleEnabled = enabled
        end
        GeneralDB().styleEnabled = enabled
        CallGlobal("MSUF_ApplyModules")
    end

    function A.Workflow.NormalizeDropdownStyleMode(mode)
        mode = tostring(mode or "msuf"):lower()
        if mode == "old" or mode == "blizzard" or mode == "legacy" then return "old" end
        return "msuf"
    end

    function A.Workflow.DropdownStyleMode()
        if type(_G.MSUF_GetDropdownStyleMode) == "function" then return A.Workflow.NormalizeDropdownStyleMode(_G.MSUF_GetDropdownStyleMode()) end
        return A.Workflow.NormalizeDropdownStyleMode(GeneralDB().dropdownStyleMode)
    end

    function A.Workflow.SetDropdownStyleMode(mode)
        mode = A.Workflow.NormalizeDropdownStyleMode(mode)
        if type(_G.MSUF_ApplyDropdownStyleModeImmediate) == "function" then
            _G.MSUF_ApplyDropdownStyleModeImmediate(mode)
        elseif type(_G.MSUF_SetDropdownStyleMode) == "function" then
            _G.MSUF_SetDropdownStyleMode(mode)
            GeneralDB().dropdownStyleMode = mode
        else
            GeneralDB().dropdownStyleMode = mode
        end
    end

    local InstallTooltipWorkflow = A.GlobalRegistry and A.GlobalRegistry.InstallTooltipWorkflow
    if type(InstallTooltipWorkflow) == "function" then
        InstallTooltipWorkflow({
            GeneralDB = GeneralDB,
            ApplyGeneral = ApplyGeneral,
            MSUF = MSUF,
        })
    end

    local RegisterVisualScaleSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterVisualScaleSettings
    if type(RegisterVisualScaleSettings) == "function" then
        RegisterVisualScaleSettings(ctx)
    end
end
