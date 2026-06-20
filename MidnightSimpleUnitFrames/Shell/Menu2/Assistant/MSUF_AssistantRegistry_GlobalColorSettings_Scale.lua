-- Assistant global scale settings and scale preset action.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; called by the visual workflow registrar.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterVisualScaleSettings(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local Workflow = A.Workflow

    if not (Registry and type(Registry.RegisterSetting) == "function" and type(Registry.RegisterAction) == "function") then return false end
    if type(GeneralDB) ~= "function" or type(Workflow) ~= "table" then return false end
    if type(Workflow.ClampScale) ~= "function" or type(Workflow.GlobalScaleState) ~= "function" then return false end
    if type(Workflow.SetGlobalScaleState) ~= "function" or type(Workflow.PushGlobalScale) ~= "function" then return false end

    Registry:RegisterSetting({
        key = "general.globalUiScale",
        label = "Global WoW UI Scale",
        category = "Dashboard / Scaling",
        unit = "global",
        frameType = "dashboard",
        attribute = "globalUiScale",
        type = "number",
        min = 0.3,
        max = 1.5,
        step = 0.01,
        percent = true,
        aliases = { "global ui scale", "wow ui scale", "global wow scale", "global scale" },
        get = function()
            local _, ui = Workflow.GlobalScaleState()
            return ui.Scale
        end,
        set = function(value)
            Workflow.SetGlobalScaleState(true, value, "custom")
        end,
        apply = function() Workflow.PushGlobalScale() end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.globalUiScaleEnabled",
        label = "Global WoW UI Scale Override",
        category = "Dashboard / Scaling",
        unit = "global",
        frameType = "dashboard",
        attribute = "globalUiScaleEnabled",
        type = "boolean",
        aliases = { "global ui scale override", "wow ui scale override", "global scale override" },
        get = function()
            local _, ui = Workflow.GlobalScaleState()
            return ui.Enabled == true
        end,
        set = function(value)
            local _, ui = Workflow.GlobalScaleState()
            Workflow.SetGlobalScaleState(value and true or false, ui.Scale, value and "custom" or "auto")
        end,
        apply = function() Workflow.PushGlobalScale() end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.msufUiScale",
        label = "MSUF Frame Scale",
        category = "Dashboard / Scaling",
        unit = "global",
        frameType = "dashboard",
        attribute = "msufFrameScale",
        type = "number",
        min = 0.25,
        max = 1.5,
        step = 0.01,
        percent = true,
        aliases = { "msuf frame scale", "msuf ui scale", "unit frame scale", "frame scale" },
        get = function() return Workflow.ClampScale(GeneralDB().msufUiScale or 1, 0.25, 1.5) or 1 end,
        set = function(value) GeneralDB().msufUiScale = Workflow.ClampScale(value, 0.25, 1.5) or 1 end,
        apply = function() Workflow.ApplyMsufScale(GeneralDB().msufUiScale or 1) end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.slashMenuScale",
        label = "MSUF Menu Scale",
        category = "Dashboard / Scaling",
        unit = "global",
        frameType = "dashboard",
        attribute = "menuScale",
        type = "number",
        min = 0.25,
        max = 1.5,
        step = 0.01,
        percent = true,
        aliases = { "msuf menu scale", "menu scale", "configuration menu scale", "dashboard scale" },
        get = function() return Workflow.ClampScale(GeneralDB().slashMenuScale or 1, 0.25, 1.5) or 1 end,
        set = function(value) GeneralDB().slashMenuScale = Workflow.ClampScale(value, 0.25, 1.5) or 1 end,
        apply = function() Workflow.ApplyMenuScale(GeneralDB().slashMenuScale or 1) end,
        combatSafe = false,
    })

    Registry:RegisterAction({
        key = "apply_global_scale_preset",
        label = "Apply Global UI Scale Preset",
        type = "preset",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            return Workflow.ApplyScalePreset(args and args.preset)
        end,
    })

    return true
end
