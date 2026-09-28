-- Undoing unit-preview movement must preserve global scale and the redo chain.
-- Session reset intentionally clears history, but must not recalculate an
-- unchanged Blizzard UI scale. A real scale-setting undo must restore it.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Near(a, b)
    return type(a) == "number" and math.abs(a - b) < 0.0001
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.message))
    local env = world.env
    local history = assert(env.MSUF2, flavor .. ": Menu2 history missing")
    local applyService = assert(history.ApplyService, flavor .. ": apply service missing")
    applyService.Flush = function() return true end
    local db = assert(history.EnsureDB(), flavor .. ": profile DB missing")
    local ui = assert(db.general and db.general.UIScale, flavor .. ": UI scale state missing")
    local player = assert(db.player, flavor .. ": player profile missing")
    ui.Enabled, ui.Scale = false, 1
    db.general.globalUiScalePreset = "auto"
    env.UIParent:SetScale(1)
    local blizzardRecalculations = 0
    env.UIParent_UpdateScale = function()
        blizzardRecalculations = blizzardRecalculations + 1
        env.UIParent:SetScale(0.72)
    end

    assert(history.StartHistorySession("menu"), flavor .. ": history session did not start")
    local function Move(label, source, x)
        assert(history.CaptureHistory(label, source, function()
            player.portraitOffsetX = x
            return true
        end))
    end
    local originalX = player.portraitOffsetX
    Move("Move: Portrait", "unitPreview:player:portrait:Move", 10)
    Move("Nudge: Portrait", "unitPreview:player:portrait:Nudge", 11)
    Move("Nudge: Portrait", "unitPreview:player:portrait:Nudge", 12)
    for step = 1, 3 do
        assert(history.Undo(), flavor .. ": portrait undo " .. step .. " failed")
        local state = history.GetHistoryState()
        assert(state.redoCount == step, flavor .. ": portrait undo discarded earlier redo steps")
        assert(Near(env.UIParent:GetScale(), 1) and blizzardRecalculations == 0,
            flavor .. ": portrait undo recalculated global UI scale")
    end
    assert(player.portraitOffsetX == originalX, flavor .. ": portrait drag did not restore")
    for step = 1, 3 do
        assert(history.Redo(), flavor .. ": portrait redo " .. step .. " failed")
    end
    assert(player.portraitOffsetX == 12, flavor .. ": portrait redo did not restore nudges")
    assert(history.ResetHistorySession(), flavor .. ": session reset failed")
    assert(history.GetHistoryState().redoCount == 0, flavor .. ": reset retained redo")
    assert(Near(env.UIParent:GetScale(), 1) and blizzardRecalculations == 0,
        flavor .. ": reset recalculated unchanged Blizzard UI scale")

    assert(history.CaptureHistory("Global UI scale", "dashboard:globalScale", function()
        ui.Enabled, ui.Scale = true, 0.6
        db.general.globalUiScalePreset = "custom"
        return true
    end))
    env.MSUF_SetGlobalUiScale(0.6, true)
    assert(Near(env.UIParent:GetScale(), 0.6), flavor .. ": scale setup failed")
    assert(history.Undo(), flavor .. ": global scale undo failed")
    assert(Near(env.UIParent:GetScale(), 1) and blizzardRecalculations == 0,
        flavor .. ": scale undo did not restore captured baseline")
    assert(history.GetHistoryState().redoCount == 1, flavor .. ": scale undo lost redo")
    assert(history.Redo(), flavor .. ": global scale redo failed")
    assert(Near(env.UIParent:GetScale(), 0.6), flavor .. ": scale redo failed")
    assert(blizzardRecalculations == 0, flavor .. ": restore called UIParent_UpdateScale")
    history.EndHistorySession("menu")
end

print("classic_history_ui_scale_smoke: ok (5 clients, portrait undo/redo, session reset, scale undo/redo)")
