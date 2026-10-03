-- MSUF Edit Mode popup focus and combat contracts (quality program A-C6),
-- pinned on the real core and Options graphs (tools/tests/client_world.lua).
-- The harness gains the client's EditBox focus rules: ClearFocus fires
-- OnEditFocusLost, and hiding a frame clears the focus of an EditBox inside it.
--   C6.1  Cancel All with a focused, half-typed popup box restores the
--         pre-session profile; the box's focus-lost commit never lands on top.
--   C6.2  A combat exit with a focused, half-typed box applies nothing: no
--         profile write and no undo entry the user could never undo.
--   C6.3  Combat that starts mid-drag commits an external element's position
--         (another addon's frame or a Blizzard system) inside the
--         PLAYER_REGEN_DISABLED handler, before lockdown; nothing reaches the
--         element's provider once lockdown is on.
--   C6.5  Edit Mode history labels reach Menu2's undo surfaces translated.
--   C6.6  A box blur without an edit opens no undo entry, and "Copy size to"
--         adds exactly one entry per target.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local FANOUT = {
    "MSUF_ApplyMsufScale", "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
    "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
    "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
    "MSUF_UpdateAllFonts_Immediate", "MSUF_ForceReanchorAllUnitFrames_Once",
}

-- The client's focus rules, on every widget of this world.
local EDITBOX_SETTERS = {
    "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetNumeric", "SetMaxLetters",
    "SetCursorPosition", "HighlightText", "SetTextInsets", "SetMultiLine", "SetCountInvisibleLetters",
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture", "SetCheckedTexture",
}

local function InstallFocusModel(world)
    local methods = world.widgets.Methods
    for _, name in ipairs(EDITBOX_SETTERS) do
        if methods[name] == nil then methods[name] = function() end end
    end
    local focused
    function methods:SetFocus()
        if focused and focused ~= self then focused:ClearFocus() end
        focused = self
    end
    function methods:HasFocus() return focused == self end
    function methods:ClearFocus()
        if focused ~= self then return end
        focused = nil
        local handler = self.scripts and self.scripts.OnEditFocusLost
        if handler then handler(self) end
    end
    local hide = methods.Hide
    function methods:Hide()
        hide(self)
        local node = focused
        while node do
            if node == self then focused:ClearFocus(); break end
            node = node.parent
        end
    end
    return function() return focused end
end

local function Boot(flavor)
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env, core = world.env, world.core
    for _, name in ipairs(FANOUT) do env[name] = function() end end
    core.UF.Apply = function() return true end
    env.MSUF_InitProfiles()
    local history = assert(env.MSUF2, flavor .. ": Menu2 history missing")
    history.ApplyService.Flush = function() return true end
    local focused = InstallFocusModel(world)
    return world, env, history, focused
end

local function Fire(world, event)
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame.events and frame.events[event] and frame.scripts and frame.scripts.OnEvent
        if handler then handler(frame, event) end
    end
end

local function NamedFrame(world, name)
    for _, frame in ipairs(world.widgets.frames) do
        if frame.frameName == name then return frame end
    end
end

local function OpenUnitPopup(world, env, context)
    local EM2 = env.MSUF_EM2
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    EM2.Popups.Open("player")
    local pf = NamedFrame(world, "MSUF_EM2_UnitPopup")
    Check(pf ~= nil and EM2.UnitPopup.IsOpen() == true, context .. ": the unit popup did not open")
    return pf
end

local function UndoCount(history)
    return history.GetHistoryState().undoCount
end

-- C6.1 ----------------------------------------------------------------------
local function RunCancelAllFocusedBox(flavor)
    local world, env, history, focused = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " C6.1 Cancel All"
    local player = env.MSUF_DB.player
    local beforeX, beforeW = player.offsetX, player.width
    local pf = OpenUnitPopup(world, env, context)
    if not pf then return end
    -- The user is typing a width; the box still has focus.
    pf.wBox:SetFocus()
    pf.wBox:SetText(tostring((tonumber(beforeW) or 250) + 37))
    EM2.State.CancelAll()
    world.widgets:RunTimers()
    Check(focused() == nil, context .. ": the popup box kept keyboard focus after Cancel All")
    Check(env.MSUF_DB.player.width == beforeW, context .. ": the half-typed width landed on the restored profile ("
        .. tostring(beforeW) .. " -> " .. tostring(env.MSUF_DB.player.width) .. ")")
    Check(env.MSUF_DB.player.offsetX == beforeX, context .. ": Cancel All did not restore the position")
    Check(EM2.State.IsActive() ~= true, context .. ": Edit Mode stayed open")

    -- A stepper box no popup ever synced cannot be reverted to a shown value;
    -- discarding still must not commit it.
    local Quick = EM2.QuickPopup
    local host = env.CreateFrame("Frame", nil, env.UIParent)
    local commits = 0
    Quick.SingleValue(host, host, -10, "Smoke", "smokeBox", function() commits = commits + 1 end)
    host.smokeBox:SetFocus()
    host.smokeBox:SetText("12")
    Quick.DiscardFocusedEdits()
    Check(focused() == nil and commits == 0, context .. ": discarding committed an unsynced box ("
        .. commits .. " commits)")
    host.smokeBox:SetFocus()
    host.smokeBox:SetText("13")
    host.smokeBox:ClearFocus()
    Check(commits == 1, context .. ": an unsynced box no longer commits on blur")
end

-- C6.2 ----------------------------------------------------------------------
local function RunCombatExitFocusedBox(flavor)
    local world, env, history, focused = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " C6.2 combat exit"
    local beforeW = env.MSUF_DB.player.width
    local pf = OpenUnitPopup(world, env, context)
    if not pf then return end
    local undoBefore = UndoCount(history)
    pf.wBox:SetFocus()
    pf.wBox:SetText(tostring((tonumber(beforeW) or 250) + 41))
    -- PLAYER_REGEN_DISABLED arrives while the client still reports no lockdown.
    Fire(world, "PLAYER_REGEN_DISABLED")
    world.widgets:SetCombat(true)
    world.widgets:RunTimers()
    Check(EM2.State.IsActive() ~= true, context .. ": Edit Mode stayed open at PLAYER_REGEN_DISABLED")
    Check(focused() == nil, context .. ": the popup box kept keyboard focus after the combat exit")
    Check(env.MSUF_DB.player.width == beforeW, context .. ": the half-typed width was applied at combat start ("
        .. tostring(beforeW) .. " -> " .. tostring(env.MSUF_DB.player.width) .. ")")
    world.widgets:SetCombat(false)
    Fire(world, "PLAYER_REGEN_ENABLED")
    world.widgets:RunTimers()
    Check(env.MSUF_DB.player.width == beforeW, context .. ": the half-typed width was applied after combat")
    Check(UndoCount(history) == undoBefore, context .. ": the combat exit left an undo entry for the discarded edit")
end

-- C6.3 ----------------------------------------------------------------------
local function RunCombatMidDrag(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " C6.3 combat mid-drag"
    local API = assert(env.MSUF_EditModeAPI, context .. ": public Edit Mode API missing")
    local frame = env.CreateFrame("Frame", "SmokeExternalBar", env.UIParent)
    frame.left, frame.bottom, frame.width, frame.height = 400, 300, 120, 40
    local saved = { x = 10, y = 20 }
    local calls = {}
    local ok, reason = API.RegisterElement("Smoke.Owner", {
        id = "bar", label = "Smoke bar",
        getFrame = function() return frame end,
        captureState = function() return { x = saved.x, y = saved.y } end,
        restoreState = function(state, why)
            calls[#calls + 1] = { phase = why, combat = env.InCombatLockdown() }
            saved.x, saved.y = state.x, state.y
            return true
        end,
        movePosition = function(request)
            calls[#calls + 1] = { phase = request.phase, combat = env.InCombatLockdown(),
                dx = request.deltaX, dy = request.deltaY }
            if request.phase == "commit" then
                saved.x = request.state.x + request.deltaX
                saved.y = request.state.y + request.deltaY
            end
            return true
        end,
    })
    Check(ok == true, context .. ": registration failed: " .. tostring(reason))
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    local key = "external:smoke.owner:bar"
    local mover = EM2.Movers.Get(key)
    if not Check(mover ~= nil, context .. ": the external mover was not created") then return end
    -- The mover follows its own SetPoint like a client frame does.
    mover.left, mover.bottom, mover.width, mover.height = 400, 300, 120, 40
    local setPoint = mover.SetPoint
    function mover:SetPoint(point, relativeTo, relativePoint, x, y)
        setPoint(self, point, relativeTo, relativePoint, x, y)
        if point == "TOPLEFT" and relativePoint == "TOPLEFT" then
            self.left, self.bottom = x, env.UIParent.height + y - self.height
        end
    end
    local cursorX, cursorY = 460, 320
    env.GetCursorPosition = function() return cursorX, cursorY end
    env.IsMouseButtonDown = function() return true end
    Check(mover._msufEM2BeginDrag(mover, "LeftButton") == true, context .. ": the drag did not start")
    local ticker = NamedFrame(world, "MSUF_EM2_TickerFrame")
    local tick = ticker and ticker.scripts and ticker.scripts.OnUpdate
    if not Check(type(tick) == "function", context .. ": the drag tick is not running") then return end
    cursorX, cursorY = 560, 280
    tick(ticker, 0.016)
    local preview = calls[#calls]
    Check(preview and preview.phase == "preview" and preview.dx == 100 and preview.dy == -40,
        context .. ": the drag tick did not preview the external element")

    -- Combat starts with the button still held.
    local before = #calls
    Fire(world, "PLAYER_REGEN_DISABLED")
    Check(EM2.State.IsActive() ~= true, context .. ": Edit Mode stayed open at PLAYER_REGEN_DISABLED")
    local commit
    for index = before + 1, #calls do
        if calls[index].phase == "commit" then commit = calls[index] end
    end
    Check(commit ~= nil, context .. ": entering combat mid-drag dropped the external commit")
    Check(commit == nil or commit.combat == false, context .. ": the external commit ran after lockdown")
    Check(saved.x == 110 and saved.y == -20, context .. ": the committed position is not the dragged one ("
        .. tostring(saved.x) .. ", " .. tostring(saved.y) .. ")")
    local inCombat = #calls
    world.widgets:SetCombat(true)
    tick(ticker, 0.016)
    world.widgets:RunTimers()
    Check(#calls == inCombat, context .. ": the element's provider was called after lockdown")
    world.widgets:SetCombat(false)
    Fire(world, "PLAYER_REGEN_ENABLED")
    world.widgets:RunTimers()
    Check(history.Undo() == true and saved.x == 10 and saved.y == 20,
        context .. ": Undo did not revert the committed combat-start drag")
end

-- C6.6 ----------------------------------------------------------------------
local function RunUndoEntries(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " C6.6 undo entries"
    local pf = OpenUnitPopup(world, env, context)
    if not pf then return end
    world.widgets:RunTimers()
    local base = UndoCount(history)
    for _, box in ipairs({ pf.xBox, pf.yBox, pf.wBox, pf.hBox }) do
        box.scripts.OnEditFocusLost(box)
        box.scripts.OnEnterPressed(box)
    end
    world.widgets:RunTimers()
    Check(UndoCount(history) == base, context .. ": a blur or Enter without an edit opened "
        .. (UndoCount(history) - base) .. " undo entries")

    -- The fallback stack (Menu2 not loaded) sees the same blur.
    local menu = env.MSUF2
    env.MSUF2, world.core.MSUF2 = nil, nil
    EM2.Undo.Clear()
    pf.xBox.scripts.OnEditFocusLost(pf.xBox)
    world.widgets:RunTimers()
    Check(EM2.Undo.CanUndo() ~= true, context .. ": a blur without an edit pushed a fallback undo entry")
    env.MSUF2, world.core.MSUF2 = menu, menu

    -- Copy size to one target: one entry. The menu is clicked like a user does.
    local db = env.MSUF_DB
    db.target = db.target or {}
    db.player.width, db.target.width = 271, 199
    EM2.UnitPopup.Sync()
    base = UndoCount(history)
    local copyButton
    for _, frame in ipairs(world.widgets.frames) do
        local label = frame._msuf2Label or frame._label
        if frame._menu and label and label.GetText and label:GetText() == "Copy size to..." then copyButton = frame end
    end
    local function copy(entry)
        copyButton.scripts.OnClick(copyButton)
        for _, item in ipairs(copyButton._menu._items or {}) do
            if item._row and item._row.key == entry.key then return item.scripts.OnClick(item) end
        end
        error("copy target row missing: " .. tostring(entry.key))
    end
    if Check(copyButton ~= nil, context .. ": the Copy size menu button is missing") then
        copy({ key = "target" })
        world.widgets:RunTimers()
        Check(db.target.width == 271, context .. ": Copy size did not copy the width")
        Check(UndoCount(history) - base == 1, context .. ": Copy size to one target added "
            .. (UndoCount(history) - base) .. " undo entries")
        -- With the Menu2 history unavailable the fallback stack holds one per target as well.
        env.MSUF2, world.core.MSUF2 = nil, nil
        EM2.Undo.Clear()
        db.target.width = 150
        copy({ key = "target" })
        world.widgets:RunTimers()
        Check(EM2.Undo.CanUndo() == true, context .. ": the fallback copy left no undo entry")
        EM2.Undo.DoUndo()
        Check(EM2.Undo.CanUndo() ~= true, context .. ": the fallback copy pushed more than one undo entry")
        env.MSUF2, world.core.MSUF2 = menu, menu
    end
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

-- C6.5 ----------------------------------------------------------------------
-- Menu2 shows Edit Mode history labels as given, so they arrive translated.
local function RunTranslatedHistoryLabel(flavor)
    local world = World.New(root, flavor, { locale = "deDE" }):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. " deDE: boot failed: " .. tostring(failure and failure.file))
    local env = world.env
    -- The client finalizes the language at ADDON_LOADED.
    Check(world.core.FinalizeLocale() == "deDE", flavor .. " C6.5: the world did not select deDE")
    for _, name in ipairs(FANOUT) do env[name] = function() end end
    world.core.UF.Apply = function() return true end
    env.MSUF_InitProfiles()
    local history = env.MSUF2
    history.ApplyService.Flush = function() return true end
    local EM2 = env.MSUF_EM2
    local context = flavor .. " C6.5 history label"
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    Check(EM2.Undo.BeginChange("unit", "player", "Move") == true, context .. ": undo transaction did not open")
    env.MSUF_DB.player.offsetX = (tonumber(env.MSUF_DB.player.offsetX) or 0) + 9
    EM2.Undo.CommitChange()
    local label = history.GetHistoryState().undoLabel
    -- The whole-sentence "Move %s" lets German put the verb last.
    Check(label == "Unitframe verschieben: player", context .. ": the undo label is not translated ("
        .. tostring(label) .. ")")
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    RunTranslatedHistoryLabel(flavor)
    RunCancelAllFocusedBox(flavor)
    RunCombatExitFocusedBox(flavor)
    RunCombatMidDrag(flavor)
    RunUndoEntries(flavor)
end

if #failures > 0 then
    error("editmode_popup_focus_combat_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_popup_focus_combat_smoke: ok (C6.1 Cancel All, C6.2 combat exit, C6.3 combat mid-drag, C6.5 history labels, C6.6 undo entries)")
