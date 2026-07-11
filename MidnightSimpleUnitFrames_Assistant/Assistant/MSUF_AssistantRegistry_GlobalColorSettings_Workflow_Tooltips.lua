-- Assistant global tooltip workflow helpers.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings_Workflow.lua; installs tooltip workflow functions.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.InstallTooltipWorkflow(ctx)
    if type(ctx) ~= "table" then return false end

    local GeneralDB = ctx.GeneralDB
    local ApplyGeneral = ctx.ApplyGeneral
    local MSUFRef = ctx.MSUF or MSUF

    if type(GeneralDB) ~= "function" or type(ApplyGeneral) ~= "function" then return false end

    A.Workflow = A.Workflow or {}

    function A.Workflow.NormalizeTooltipMode(mode)
        mode = tostring(mode or "ALWAYS"):upper()
        if mode == "OOC" or mode == "MODIFIER" or mode == "NEVER" then return mode end
        if mode == "OFF" then return "NEVER" end
        return "ALWAYS"
    end

    function A.Workflow.NormalizeTooltipModifier(modifier)
        modifier = tostring(modifier or "ALT"):upper()
        if modifier == "CTRL" or modifier == "SHIFT" then return modifier end
        return "ALT"
    end

    function A.Workflow.ReadTooltipProvider()
        local g = GeneralDB()
        if g.unitTooltipProvider == "MSUF" then return "MSUF" end
        if g.unitTooltipProvider == "GAME" then return "GAME" end
        return g.disableUnitInfoTooltips == false and "MSUF" or "GAME"
    end

    function A.Workflow.ReadTooltipAnchor()
        local g = GeneralDB()
        local anchor = g.unitTooltipAnchor
        if anchor == "EXTERNAL" or anchor == "FIXED" or anchor == "CURSOR" then return anchor end
        if A.Workflow.ReadTooltipProvider() == "MSUF" then
            return g.unitInfoTooltipStyle == "modern" and "CURSOR" or "FIXED"
        end
        if type(g.tooltipPosX) == "number" and type(g.tooltipPosY) == "number" then return "FIXED" end
        if g.unitInfoTooltipStyle == "modern" then return "CURSOR" end
        return "EXTERNAL"
    end

    function A.Workflow.RefreshTooltipPreview()
        local tooltips = MSUFRef and MSUFRef.Tooltips
        if tooltips and type(tooltips.Refresh) == "function" then tooltips.Refresh() end
        local editActive = _G.MSUF_UnitEditModeActive == true
        if not editActive and type(_G.MSUF_IsMSUFEditModeActive) == "function" then editActive = _G.MSUF_IsMSUFEditModeActive() and true or false end
        if editActive and type(_G.MSUF_Tooltip_ShowEditPreview) == "function" then _G.MSUF_Tooltip_ShowEditPreview() end
    end

    function A.Workflow.WriteTooltipSettings(provider, anchor)
        local g = GeneralDB()
        provider = provider == "MSUF" and "MSUF" or "GAME"
        if anchor ~= "FIXED" and anchor ~= "CURSOR" and anchor ~= "EXTERNAL" then anchor = "EXTERNAL" end
        if provider == "MSUF" and anchor == "EXTERNAL" then anchor = "FIXED" end
        g.unitTooltipProvider = provider
        g.unitTooltipAnchor = anchor
        g.disableUnitInfoTooltips = provider ~= "MSUF"
        g.unitInfoTooltipStyle = anchor == "CURSOR" and "modern" or "classic"
        ApplyGeneral("MSUF_ASSISTANT_TOOLTIPS", { preview = false, applyAll = false, notify = false })
        A.Workflow.RefreshTooltipPreview()
    end

    function A.Workflow.WriteTooltipBehavior(mode, modifier)
        local g = GeneralDB()
        g.unitTooltipMode = A.Workflow.NormalizeTooltipMode(mode)
        g.unitTooltipModifier = A.Workflow.NormalizeTooltipModifier(modifier)
        ApplyGeneral("MSUF_ASSISTANT_TOOLTIP_BEHAVIOR", { preview = false, applyAll = false, notify = false })
        A.Workflow.RefreshTooltipPreview()
    end

    return true
end
