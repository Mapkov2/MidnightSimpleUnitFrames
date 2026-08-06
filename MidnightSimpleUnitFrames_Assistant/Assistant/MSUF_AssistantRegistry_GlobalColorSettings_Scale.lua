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

    local function CopyTable(value)
        local out = {}
        for key, item in pairs(type(value) == "table" and value or {}) do out[key] = item end
        return out
    end

    local function CaptureGlobalScaleState()
        local g, ui = Workflow.GlobalScaleState()
        return {
            ui = CopyTable(ui),
            preset = g.globalUiScalePreset,
            value = g.globalUiScaleValue,
            hasPreset = g.globalUiScalePreset ~= nil,
            hasValue = g.globalUiScaleValue ~= nil,
        }
    end

    local function RestoreGlobalScaleState(state)
        if type(state) ~= "table" or type(state.ui) ~= "table" then return false end
        local g = GeneralDB()
        g.UIScale = CopyTable(state.ui)
        g.globalUiScalePreset = state.hasPreset and state.preset or nil
        g.globalUiScaleValue = state.hasValue and state.value or nil
        return true
    end

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
        dbScopes = { { scope = "general", dbKey = "UIScale.Scale" } },
        dbScopesReplace = true,
        get = function()
            local _, ui = Workflow.GlobalScaleState()
            return ui.Scale
        end,
        set = function(value)
            Workflow.SetGlobalScaleState(true, value, "custom")
        end,
        apply = function() Workflow.PushGlobalScale() end,
        captureTransactionState = CaptureGlobalScaleState,
        restoreTransactionState = RestoreGlobalScaleState,
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
        dbScopes = { { scope = "general", dbKey = "UIScale.Enabled" } },
        dbScopesReplace = true,
        get = function()
            local _, ui = Workflow.GlobalScaleState()
            return ui.Enabled == true
        end,
        set = function(value)
            local _, ui = Workflow.GlobalScaleState()
            Workflow.SetGlobalScaleState(value and true or false, ui.Scale, value and "custom" or "auto")
        end,
        apply = function() Workflow.PushGlobalScale() end,
        captureTransactionState = CaptureGlobalScaleState,
        restoreTransactionState = RestoreGlobalScaleState,
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
        get = function() return Workflow.ClampScale(GeneralDB().msufUiScale or 1, 0.25, 2.0) or 1 end,
        set = function(value) GeneralDB().msufUiScale = Workflow.ClampScale(value, 0.25, 2.0) or 1 end,
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
        max = 2.0,
        step = 0.01,
        percent = true,
        -- The stored value is this percentage times 0.8 and ClampScale rounds
        -- it to 0.01, so the menu scale can only land on multiples of 1.25%:
        -- asking for 101% stores 0.808 -> rounds to 0.81 -> reads back 101.25%.
        -- That is a normalization, not a failed write, but without saying so the
        -- transaction compared 101.25% against the requested 101%, called it a
        -- mismatch and rolled back -- so any non-multiple simply did nothing.
        normalizesValue = true,
        aliases = { "msuf menu scale", "menu scale", "configuration menu scale", "dashboard scale" },
        get = function()
            local stored = Workflow.ClampScale(GeneralDB().slashMenuScale or 0.8, 0.2, 1.6) or 0.8
            return stored / 0.8
        end,
        set = function(value)
            local percentScale = Workflow.ClampScale(value, 0.25, 2.0) or 1
            GeneralDB().slashMenuScale = percentScale * 0.8
        end,
        apply = function() Workflow.ApplyMenuScale(GeneralDB().slashMenuScale or 0.8) end,
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
