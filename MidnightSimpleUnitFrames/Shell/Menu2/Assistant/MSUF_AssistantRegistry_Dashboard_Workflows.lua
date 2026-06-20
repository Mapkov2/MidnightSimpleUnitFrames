-- Assistant Dashboard workflow wiring.
-- Loaded after MSUF_AssistantRegistry_Dashboard.lua and before DashboardActions.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A
A.Workflow = A.Workflow or {}

local ctx = A.DashboardRegistry and A.DashboardRegistry.WorkflowContext
if type(ctx) ~= "table" then return end

local BuildStagingSelectors = A.DashboardRegistry and A.DashboardRegistry.BuildStagingSelectors
local StagingSelectors = type(BuildStagingSelectors) == "function" and BuildStagingSelectors({
    M = ctx.M,
    A = ctx.A,
    NormalizeKey = ctx.NormalizeKey,
    ResolveToken = ctx.ResolveToken,
    PersistScalar = ctx.PersistScalar,
    OpenMenuPage = ctx.OpenMenuPage,
    SelectorBool = ctx.SelectorBool,
}) or {}
local SetColorTokenSelector = StagingSelectors.SetColorTokenSelector
local SetProfileStagingSelector = StagingSelectors.SetProfileStagingSelector

local BuildTextSelectors = A.DashboardRegistry and A.DashboardRegistry.BuildTextSelectors
local TextSelectors = type(BuildTextSelectors) == "function" and BuildTextSelectors({
    M = ctx.M,
    A = ctx.A,
    NormalizeKey = ctx.NormalizeKey,
    ResolveUnitKey = ctx.ResolveUnitKey,
    ResolveGroupScope = ctx.ResolveGroupScope,
    PersistScalar = ctx.PersistScalar,
    PersistTableValue = ctx.PersistTableValue,
    PersistNestedTableValue = ctx.PersistNestedTableValue,
    OpenMenuPage = ctx.OpenMenuPage,
    SelectorBool = ctx.SelectorBool,
    UnitLabel = ctx.UnitLabel,
    GroupLabel = ctx.GroupLabel,
    UNIT_PAGE_KEYS = ctx.UNIT_PAGE_KEYS,
}) or {}
local SetUnitTextSelector = TextSelectors.SetUnitTextSelector
local SetUnitTextMoveTogether = TextSelectors.SetUnitTextMoveTogether
local SetGroupTextSelector = TextSelectors.SetGroupTextSelector
local SetGroupTextMoveTogether = TextSelectors.SetGroupTextMoveTogether

local BuildStyleTabSelectors = A.DashboardRegistry and A.DashboardRegistry.BuildStyleTabSelectors
local StyleTabSelectors = type(BuildStyleTabSelectors) == "function" and BuildStyleTabSelectors({
    NormalizeKey = ctx.NormalizeKey,
    PersistScalar = ctx.PersistScalar,
    OpenMenuPage = ctx.OpenMenuPage,
}) or {}
local SetClassPowerStyleTabSelector = StyleTabSelectors.SetClassPowerStyleTabSelector
local SetBarsHighlightTabSelector = StyleTabSelectors.SetBarsHighlightTabSelector

local BuildCopySelectors = A.DashboardRegistry and A.DashboardRegistry.BuildCopySelectors
local CopySelectors = type(BuildCopySelectors) == "function" and BuildCopySelectors({
    M = ctx.M,
    A = ctx.A,
    NormalizeKey = ctx.NormalizeKey,
    ResolveUnitKey = ctx.ResolveUnitKey,
    OpenMenuPage = ctx.OpenMenuPage,
    SelectorBool = ctx.SelectorBool,
    UNIT_PAGE_KEYS = ctx.UNIT_PAGE_KEYS,
}) or {}
local SetUnitCopyScopeSelector = CopySelectors.SetUnitCopyScopeSelector
local SetGroupCopyScopeSelector = CopySelectors.SetGroupCopyScopeSelector

local BuildStatusSelectors = A.DashboardRegistry and A.DashboardRegistry.BuildStatusSelectors
local StatusSelectors = type(BuildStatusSelectors) == "function" and BuildStatusSelectors({
    A = ctx.A,
    NormalizeKey = ctx.NormalizeKey,
    ResolveUnitKey = ctx.ResolveUnitKey,
    ResolveGroupScope = ctx.ResolveGroupScope,
    PersistScalar = ctx.PersistScalar,
    PersistTableValue = ctx.PersistTableValue,
    OpenMenuPage = ctx.OpenMenuPage,
    UnitLabel = ctx.UnitLabel,
    GroupLabel = ctx.GroupLabel,
    UNIT_PAGE_KEYS = ctx.UNIT_PAGE_KEYS,
}) or {}
local SetUnitStatusSelector = StatusSelectors.SetUnitStatusSelector
local SetGroupStatusSelector = StatusSelectors.SetGroupStatusSelector
local SetGroupSpellSelector = StatusSelectors.SetGroupSpellSelector
local SetGroupCornerSelector = StatusSelectors.SetGroupCornerSelector

function A.Workflow.SetMenuSelectorState(args)
    local selector = tostring(args and args.selector or "")
    if selector == "unit_text" then return SetUnitTextSelector(args) end
    if selector == "group_text" then return SetGroupTextSelector(args) end
    if selector == "unit_text_move_together" then return SetUnitTextMoveTogether(args) end
    if selector == "group_text_move_together" then return SetGroupTextMoveTogether(args) end
    if selector == "unit_status" then return SetUnitStatusSelector(args) end
    if selector == "group_status" then return SetGroupStatusSelector(args) end
    if selector == "group_spell" then return SetGroupSpellSelector(args) end
    if selector == "group_corner" then return SetGroupCornerSelector(args) end
    if selector == "color_token" then return SetColorTokenSelector(args) end
    if selector == "profile_staging" then return SetProfileStagingSelector(args) end
    if selector == "class_power_style_tab" then return SetClassPowerStyleTabSelector(args) end
    if selector == "bars_highlight_tab" then return SetBarsHighlightTabSelector(args) end
    if selector == "unit_copy_scope" and type(SetUnitCopyScopeSelector) == "function" then return SetUnitCopyScopeSelector(args) end
    if selector == "group_copy_scope" and type(SetGroupCopyScopeSelector) == "function" then return SetGroupCopyScopeSelector(args) end
    return false, "Which menu choice do you want me to select?"
end

function A.Workflow.ControlMenuWindow(command)
    command = tostring(command or "")
    local frame = ctx.M and ctx.M.frame or nil
    if command == "close" then
        if ctx.M and type(ctx.M.HideSlashMenuAndMinibar) == "function" then
            ctx.M.HideSlashMenuAndMinibar(frame)
            return true, "Closed the MSUF menu."
        end
        return false, "Open the MSUF menu first so I can close it."
    end
    if command == "minimize" then
        if ctx.M and type(ctx.M.MinimizeSlashMenuWindow) == "function" then
            if ctx.M.MinimizeSlashMenuWindow(frame) ~= false then return true, "Minimized the MSUF menu." end
        end
        return false, "Open the MSUF menu first so I can minimize it."
    end
    if command == "maximize" then
        if ctx.M and type(ctx.M.MaximizeSlashMenuWindow) == "function" then
            if ctx.M.MaximizeSlashMenuWindow(frame) ~= false then return true, "Maximized or restored the MSUF menu." end
        end
        return false, "Open the MSUF menu first so I can maximize it."
    end
    if command == "restore" then
        if ctx.M and ctx.M.minimizedBar and ctx.M.minimizedBar.IsShown and ctx.M.minimizedBar:IsShown() and type(ctx.M.RestoreMinimizedSlashMenu) == "function" then
            if ctx.M.RestoreMinimizedSlashMenu(frame) ~= false then return true, "Restored the MSUF menu." end
        end
        if ctx.M and type(ctx.M.RestoreSlashMenuWindow) == "function" then
            if ctx.M.RestoreSlashMenuWindow(frame) ~= false then return true, "Restored the MSUF menu." end
        end
        return false, "Open the MSUF menu first so I can restore it."
    end
    return false, "Which menu window task do you want me to run?"
end
