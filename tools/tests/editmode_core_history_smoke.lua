-- The real core graph owns every Edit Mode gesture before Options is parsed.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checks = 0
local function Check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world.env.GetCursorPosition = function() return 300, 400 end
    local loadFile, parsedOptions = world.LoadFile, 0
    function world:LoadFile(path, ...)
        if path:find("MidnightSimpleUnitFrames_Options/", 1, true) then parsedOptions = parsedOptions + 1 end
        return loadFile(self, path, ...)
    end
    local suffix = world.client.tocSuffix or flavor
    local gameType = world.client.isForever and "camelot" or nil
    world:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root, World.CoreTOC(suffix), "enUS", gameType), world.core)
    Check(world:FirstFailure() == nil, flavor .. ": core graph failed")
    local ns, env = world.core, world.env
    local widgetMethods = getmetatable(env.UIParent).__index
    for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets",
        "SetMaxLetters", "ClearFocus", "SetCursorPosition", "HighlightText", "SetAutoFocus" }) do
        widgetMethods[name] = function() end
    end
    widgetMethods.HasFocus = function() return false end
    local H = assert(ns.History, "core history missing")
    local apply = assert(ns.ApplyService, "core apply missing")
    env.MSUF_InitProfiles()
    local loads = 0
    env.MSUF_EnsureOptionsLoaded = function() loads = loads + 1 return false end
    -- Native rendering is checked by the existing apply and drag budget tests.
    -- Here only the history/lifecycle owners run, against the real profile.
    apply.QueueFlush, apply.Flush, apply.Quiesce = function() return true end, function() end, function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_ForceTextLayoutForUnitKey = function() end
    env.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function() end
    ns.UF.Apply = function() return true end
    local em = env.MSUF_EM2
    local initial = env.MSUF_DB.player.offsetX
    local bar = env.CreateFrame("Frame", nil, env.UIParent)
    bar:SetSize(env.MSUF_DB.player.width, env.MSUF_DB.player.height)
    bar.left = env.UIParent:GetWidth() * 0.5 + initial - bar:GetWidth()
    bar.bottom = env.UIParent:GetHeight() * 0.5 + env.MSUF_DB.player.offsetY - bar:GetHeight()
    ns.UF.GetFrame = function(key) if key == "player" then return bar end end
    Check(env.MSUF_SetMSUFEditModeDirect(true, "player") == true, "direct entry refused")
    Check(H.GetHistoryState().activeSurfaces == 1, "entry did not start exactly one core surface")
    Check(not ns.MSUF2.CaptureHistory and loads == 0, "entry parsed Options")
    Check(em.UnitPopup.Open("player") == true and em.UnitPopup.IsOpen(), "core-only popup did not open")
    em.UnitPopup.Close()
    -- Use the same history calls as the release path of a unit drag.
    Check(em.Undo.BeginChange("unit", "player"), "drag history refused")
    local strategy = ns.EditModeKinds.unit
    local drag = assert(strategy:beginDrag(bar, "player", {
        popupType = "unit", getConf = function() return env.MSUF_DB.player end,
    }, { bar = bar }), "real unit drag refused")
    Check(strategy:applyDrag(drag, drag.startCX + 17, drag.startCY, 1), "real unit drag did not apply")
    Check(strategy:commit(drag), "real unit drag did not finish")
    em.Undo.CommitChange()
    Check(H.GetHistoryState().undoCount == 1, "drag did not record one diff")
    Check(em.Undo.DoUndo() and env.MSUF_DB.player.offsetX == initial, "core-only undo failed")
    Check(em.Undo.DoRedo() and env.MSUF_DB.player.offsetX == initial + 17, "core-only redo failed")
    Check(em.Nudge.By(1, 0) and env.MSUF_DB.player.offsetX > initial + 17, "real nudge failed")
    Check(H.GetHistoryState().canUndo, "pending nudge was not undoable")
    Check(em.Undo.DoUndo() and env.MSUF_DB.player.offsetX == initial + 17, "pending nudge undo failed")
    -- Run the real popup input and its deferred history completion.
    bar.left = env.UIParent:GetWidth() * 0.5 + env.MSUF_DB.player.offsetX - bar:GetWidth()
    bar.bottom = env.UIParent:GetHeight() * 0.5 + env.MSUF_DB.player.offsetY - bar:GetHeight()
    em.UnitPopup.Open("player")
    local popup
    for _, frame in ipairs(world.widgets.frames) do
        if frame.frameName == "MSUF_EM2_UnitPopup" then popup = frame end
    end
    assert(popup, "unit popup frame missing")
    popup.xBox:SetText(tostring(initial + 19))
    assert(popup.xBox:GetScript("OnEnterPressed"))(popup.xBox)
    world.widgets:RunTimers(100)
    em.UnitPopup.Close()
    Check(env.MSUF_DB.player.offsetX == initial + 19,
        "popup input did not reach the profile: " .. tostring(env.MSUF_DB.player.offsetX) .. " expected " .. (initial + 19))
    Check(loads == 0 and parsedOptions == 0 and not ns.MSUF2.CaptureHistory, "gesture parsed Options")
    local undo, redo = H.historyUndo, H.historyRedo
    local depth = H.GetHistoryState().undoCount
    world:LoadGraph("MidnightSimpleUnitFrames_Options", World.Graph(root, World.OptionsTOC(suffix), "enUS", gameType), world.options)
    Check(world:FirstFailure() == nil, "late Options graph failed")
    local M = ns.MSUF2
    Check(M.ApplyService == apply and ns.History == H, "late UI replaced a core service")
    Check(M.historyUndo == undo and M.historyRedo == redo and H.GetHistoryState().undoCount == depth,
        "late UI lost or duplicated steps")
    Check(M.StartHistorySession("menu") and H.GetHistoryState().activeSurfaces == 2, "menu failed to join session")
    Check(M.Undo() and env.MSUF_DB.player.offsetX == initial + 17, "late menu could not undo core popup")
    Check(M.Redo() and env.MSUF_DB.player.offsetX == initial + 19, "late menu could not redo core popup")
    local original, intercepted = M.RequestUnitApply, 0
    M.RequestUnitApply = function(...)
        intercepted = intercepted + 1
        return original(...)
    end
    Check(M.RequestUnitDomains("player", "wrapped", { history = false, preview = false }) ~= false
        and intercepted == 1, "legacy request wrap recursed or lost interception")
    M.RequestUnitApply = original
    Check(em.State.CancelAll() ~= false and env.MSUF_DB.player.offsetX == initial, "Cancel All lost entry marker")
    Check(H.GetHistoryState().activeSurfaces == 1, "Cancel All closed the menu surface")
    M.EndHistorySession("menu")
    Check(H.GetHistoryState().activeSurfaces == 0 and loads == 0, "exit leaked a surface or loaded Options")
end
print("PASS core-only Edit Mode history and late Options bridge: " .. checks .. " checks across five clients")
