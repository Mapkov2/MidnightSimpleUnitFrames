local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local selected = arg[3]
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Boot()
    local world = World.New(root, flavor)
    world.env.MAX_BOSS_FRAMES = 5
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    local M = world.core.MSUF2
    M.ApplyService.Flush = function() return true end
    world.env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    return world, M, M.EnsureDB()
end
local cases = {}
function cases.cancel()
    local world, M, db = Boot()
    db.general.showMinimapIcon, db.general.msufUiScale = true, 1
    local icon, scale = {}, {}
    world.env.MSUF_SetMinimapIconEnabled = function(v) icon[#icon + 1] = v end
    world.env.MSUF_ApplyMsufScale = function(v) scale[#scale + 1] = v end
    assert(M.StartHistorySession("edit_mode"))
    assert(M.CaptureHistory("Options", "opt_misc:toggle", function()
        db.general.showMinimapIcon, db.general.msufUiScale = false, 1.5
        return true
    end))
    assert(M.CancelHistorySurface("edit_mode", true))
    assert(#icon == 1 and icon[1] == true, "Cancel All did not restore the minimap setter exactly once")
    assert(#scale == 1 and scale[1] == 1, "Cancel All did not restore the frame scale")
end
function cases.navigation()
    local _, M, db = Boot()
    db.general.hideAdvancedMenu, db.general.showNavigationIcons = false, true
    local advanced, icons = 0, 0
    M.RefreshAdvancedNavVisibility = function() advanced = advanced + 1 end
    M.RefreshNavIconVisibility = function() icons = icons + 1 end
    assert(M.StartHistorySession("menu"))
    assert(M.CaptureHistory("Navigation", "opt_misc:toggle", function()
        db.general.hideAdvancedMenu, db.general.showNavigationIcons = true, false
        return true
    end))
    assert(M.Undo())
    assert(advanced == 1 and icons == 1, "Undo left navigation unchanged")
    assert(M.Redo())
    assert(advanced == 2 and icons == 2, "Redo left navigation unchanged")
end
function cases.tooltip()
    local world, M, db = Boot()
    db.general.unitTooltipMode = "ALWAYS"
    local refreshes = 0
    world.core.Tooltips.Refresh = function() refreshes = refreshes + 1 end
    assert(M.StartHistorySession("menu"))
    assert(M.CaptureHistory("Tooltips", "opt_misc:segment", function()
        db.general.unitTooltipMode = "NEVER"
        return true
    end))
    assert(M.Undo())
    assert(refreshes == 1, "Undo did not release the NEVER tooltip gate")
end
function cases.castbar()
    local world, M, db = Boot()
    world.env.MSUF_SetCastbarBackend("target", "MSUF", db.general)
    local backendRequests = 0
    M.ApplyService.RequestCastbarUnit = function(unit)
        assert(unit == "target")
        backendRequests = backendRequests + 1
        return true
    end
    assert(M.StartHistorySession("menu"))
    assert(M.CaptureHistory("Castbar", "unit:target:castbar", function()
        world.env.MSUF_SetCastbarBackend("target", "HIDE", db.general)
        return true
    end))
    assert(M.Undo())
    assert(backendRequests == 1, "Undo did not queue the target castbar backend")
    assert(M.CaptureHistory("Width", "unit:target:width", function()
        db.target.width = db.target.width + 1
        return true
    end))
    assert(M.Undo())
    assert(backendRequests == 1, "Geometry-only undo reinitialized castbar backend")
end
function cases.bars()
    local _, M, db = Boot()
    local requests = {}
    M.ApplyService.RequestGeneral = function(_, opts) requests[#requests + 1] = opts; return true end
    assert(M.StartHistorySession("menu"))
    assert(M.CaptureHistory("Outline", "opt_bars:slider:outline", function()
        db.general.barOutlineThickness = (db.general.barOutlineThickness or 1) + 2
        return true
    end))
    assert(M.Undo())
    local outline, gradient = false, false
    for _, flags in ipairs(requests) do
        outline = outline or flags.barOutline == true
        gradient = gradient or flags.barGradients == true
    end
    assert(outline, "Outline undo refreshed only bar textures")
    assert(not gradient, "Outline undo repainted unchanged gradients")
end
local failed = {}
for _, name in ipairs({ "cancel", "navigation", "tooltip", "castbar", "bars" }) do
    if not selected or selected == name then
        local ok, message = pcall(cases[name])
        print(name .. ": " .. (ok and "PASS" or tostring(message)))
        if not ok then failed[#failed + 1] = name end
    end
end
assert(#failed == 0, "history regressions: " .. table.concat(failed, ", "))
