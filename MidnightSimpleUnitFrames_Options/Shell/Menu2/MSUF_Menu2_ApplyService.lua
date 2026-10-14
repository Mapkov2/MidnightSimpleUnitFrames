local _, MSUF = ...
local M = MSUF.MSUF2
local Apply = MSUF.ApplyService
M.ApplyService = Apply
Apply.AttachUI(function(name, ...)
    if name == "RefreshUnitPreview" then
        return MSUF.Require("MSUF_UFPreview_RequestRefresh", "Shell/Menu2/MSUF_Menu2_ApplyService.lua")(...)
    end
    if name == "RefreshHighlightPriorityColors" then
        local entry = M.activeKey == "opt_bars" and M.cache and M.cache.opt_bars
        if entry and not entry._msuf2Invalidated and M.frame and M.frame:IsShown()
            and type(entry.refreshHighlightPriorityColors) == "function" then
            entry.refreshHighlightPriorityColors()
        end
        return
    end
    local follower = M[name]
    if follower then return follower(...) end
end)
MSUF.ExportPublic("MSUF_Menu2_ApplyService", Apply)
