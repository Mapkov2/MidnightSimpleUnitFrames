-- Assistant Dashboard style-tab selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; the main dashboard registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

function A.DashboardRegistry.BuildStyleTabSelectors(ctx)
    if type(ctx) ~= "table" then return {} end

    local NormalizeKey = ctx.NormalizeKey
    local PersistScalar = ctx.PersistScalar
    local OpenMenuPage = ctx.OpenMenuPage

    if type(NormalizeKey) ~= "function" or type(PersistScalar) ~= "function" then return {} end
    if type(OpenMenuPage) ~= "function" then return {} end

    local function DisplayTabLabel(label, tab)
        if A and type(A.DisplayEnumLabel) == "function" then return A.DisplayEnumLabel(label, tab) end
        if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(tab or "") then return tostring(label) end
        local parser = A and A.Parser
        if parser and type(parser.ValueDisplay) == "function" then
            return parser.ValueDisplay({ type = "enum" }, tab)
        end
        return tostring(tab or "")
    end

    local function ResolveClassPowerStyleTab(tab)
        local key = NormalizeKey(tab)
        if key == "texture" or key == "textures" or key == "resource" or key == "resources" then return "resources", "Textures" end
        if key == "text" or key == "texts" then return "text", "Text" end
        if key == "opacity" or key == "alpha" or key == "transparency" then return "opacity", "Opacity" end
        if key == "pip" or key == "pips" or key == "separator" or key == "separators" then return "pips", "Pips" end
        return nil
    end

    local function SetClassPowerStyleTabSelector(args)
        local tab, label = ResolveClassPowerStyleTab(args and args.tab)
        if not tab then return false, "Which Class Resources style tab do you want me to select?" end
        PersistScalar("classPowerStyleTab", tab)
        OpenMenuPage("classpower")
        return true, "Selected Class Resources Style " .. DisplayTabLabel(label, tab) .. " tab."
    end

    local function ResolveBarsHighlightTab(tab)
        local key = NormalizeKey(tab)
        if key == "mode" or key == "modes" or key == "border" or key == "borders" then return "modes", "Modes" end
        if key == "preview" or key == "test" or key == "tests" then return "preview", "Preview" end
        if key == "priority" or key == "priorities" or key == "order" or key == "ordering" then return "priority", "Priority" end
        return nil
    end

    local function SetBarsHighlightTabSelector(args)
        local tab, label = ResolveBarsHighlightTab(args and args.tab)
        if not tab then return false, "Which Highlight Borders tab do you want me to select?" end
        PersistScalar("barsHighlightTab", tab)
        OpenMenuPage("opt_bars")
        return true, "Selected Highlight Borders " .. DisplayTabLabel(label, tab) .. " tab."
    end

    return {
        SetClassPowerStyleTabSelector = SetClassPowerStyleTabSelector,
        SetBarsHighlightTabSelector = SetBarsHighlightTabSelector,
    }
end
