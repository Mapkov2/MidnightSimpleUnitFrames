-- MSUF Edit Mode toolbar wiring (quality program A-C6), on the real core and
-- Options graphs (tools/tests/client_world.lua). Every toolbar control is
-- clicked the way a user clicks it and its effect is checked: Preview, Motion,
-- Auras, Snap, the grid and background widgets, Reset, Position (dock popup),
-- Settings, Cooldown (where the client hosts it), Anchor, Help, the frame and
-- settings pickers, Undo/Redo, Discard (confirm dialog) and Done. The toolbar
-- module layout can change; this wiring cannot.
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
local SETTERS = {
    "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetNumeric", "SetMaxLetters",
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture",
}

local function Boot(flavor)
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env, core = world.env, world.core
    for _, name in ipairs(FANOUT) do env[name] = function() end end
    for _, name in ipairs(SETTERS) do
        if world.widgets.Methods[name] == nil then world.widgets.Methods[name] = function() end end
    end
    core.UF.Apply = function() return true end
    -- The client finalizes the language at ADDON_LOADED; labels read it.
    core.FinalizeLocale()
    env.MSUF_InitProfiles()
    local history = assert(env.MSUF2, flavor .. ": Menu2 history missing")
    history.ApplyService.Flush = function() return true end
    return world, env, history
end

-- The newest frame of that name: the client returns a named frame from _G,
-- the harness does not publish names, so a rebuilt dialog is a new frame.
local function Named(world, name)
    local found
    for _, frame in ipairs(world.widgets.frames) do
        if frame.frameName == name then found = frame end
    end
    return found
end

local function LabelOf(frame)
    local label = frame._msuf2Label or frame._label
    return label and label.GetText and label:GetText() or nil
end

local function Button(world, parent, text)
    for _, frame in ipairs(world.widgets.frames) do
        if LabelOf(frame) == text and frame.scripts and frame.scripts.OnClick then
            local node = frame
            while node and node ~= parent do node = node.parent end
            if node == parent or parent == nil then return frame end
        end
    end
end

local function Click(frame, button)
    return frame.scripts.OnClick(frame, button or "LeftButton")
end

local function Run(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " toolbar"
    local db = env.MSUF_DB
    db.general.hideAdvancedMenu = false
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}

    local counts = {}
    local function Count(name) counts[name] = (counts[name] or 0) + 1 end
    local menu = env.MSUF2
    menu.OpenGuidedTourAtStage = function(stage) Count("tour:" .. tostring(stage)); return true end
    menu.Open = function() Count("menuOpen"); return true end
    local picker = { Show = function() Count("anchorPicker") end }
    env.MSUF_EnsureAnchorPicker = function() return picker end

    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    local hud = Named(world, "MSUF_EM2_HUD")
    if not Check(hud ~= nil and hud.shown == true and EM2.HUD.IsShown() == true, context .. ": the toolbar is not shown") then
        return
    end
    EM2.Focus.OpenFullSettings = function() Count("settings"); return true end

    -- Preview, Motion, Auras.
    local preview = Button(world, hud, "Preview")
    if Check(preview ~= nil, context .. ": Preview missing") then
        local before = env.MSUF_UnitPreviewActive == true
        Click(preview)
        Check((env.MSUF_UnitPreviewActive == true) ~= before, context .. ": Preview did not toggle the preview")
        Click(preview)
        Check((env.MSUF_UnitPreviewActive == true) == before, context .. ": Preview did not toggle back")
    end
    local motion = Button(world, hud, "Motion")
    if Check(motion ~= nil, context .. ": Motion missing in the advanced toolbar") then
        env.MSUF_TogglePreviewAnimation = function(source) Count("motion:" .. tostring(source)); return true end
        Click(motion)
        Check(counts["motion:edit_mode"] == 1, context .. ": Motion did not toggle the preview animation")
    end
    local auras = Button(world, hud, "Auras")
    if Check(auras ~= nil, context .. ": Auras missing in the advanced toolbar") then
        local before = db.auras3.shared.showInEditMode == true
        Click(auras)
        Check((db.auras3.shared.showInEditMode == true) ~= before, context .. ": Auras did not toggle aura previews")
    end

    -- Snap, grid, background.
    local snap = Button(world, hud, "Snap")
    if Check(snap ~= nil, context .. ": Snap missing") then
        local before = EM2.Snap.IsEnabled()
        Click(snap)
        Check(EM2.Snap.IsEnabled() ~= before, context .. ": Snap did not toggle snapping")
    end
    local tools = env.MSUF_EditModeGridTools
    if Check(type(tools) == "table" and tools._gridWidget and tools._bgWidget, context .. ": grid tools missing") then
        local enabled = EM2.Grid.GetEnabled()
        tools._gridWidget.scripts.OnMouseUp(tools._gridWidget, "LeftButton")
        Check(EM2.Grid.GetEnabled() ~= enabled, context .. ": the grid widget did not toggle the grid")
        local step = EM2.Grid.GetGridStep()
        tools._gridWidget.scripts.OnMouseWheel(tools._gridWidget, 1)
        Check(EM2.Grid.GetGridStep() == math.min(80, step + 4), context .. ": the grid widget did not scroll the spacing")
        local alpha = EM2.Grid.GetBgAlpha()
        tools._bgWidget.scripts.OnMouseWheel(tools._bgWidget, -1)
        Check(math.abs(EM2.Grid.GetBgAlpha() - math.max(0, alpha - 0.05)) < 1e-6,
            context .. ": the background widget did not scroll the opacity")
    end

    -- Reset the selected unit frame.
    local reset = Button(world, hud, "Reset")
    if Check(reset ~= nil, context .. ": Reset missing") then
        local defaultX, defaultY = env.MSUF_GetDefaultUnitOffsets("player")
        db.player.offsetX, db.player.offsetY = (tonumber(defaultX) or 0) + 31, (tonumber(defaultY) or 0) - 17
        EM2.State.SetUnitKey("player")
        Click(reset)
        Check(db.player.offsetX == defaultX and db.player.offsetY == defaultY,
            context .. ": Reset did not restore the default position")
    end

    -- Position popup and dock.
    local position = Button(world, hud, "Position")
    if Check(position ~= nil, context .. ": Position missing") then
        Click(position)
        local popup = Named(world, "MSUF_EM2_HUD_PositionPopup")
        if Check(popup ~= nil and popup.shown == true, context .. ": Position did not open the dock popup") then
            local bottom = Button(world, popup, "Bottom")
            if Check(bottom ~= nil, context .. ": the dock popup has no Bottom choice") then
                Click(bottom)
                local char = env.MSUF_GlobalDB.char[env.MSUF_GetCharKey()]
                Check(char and char.editModeHUDState and char.editModeHUDState.dock == "BOTTOM",
                    context .. ": Bottom did not dock the toolbar")
            end
            Click(position)
            Check(popup.shown ~= true, context .. ": Position did not close the dock popup")
        end
    end

    -- Settings, Cooldown, Anchor, Help.
    local settings = Button(world, hud, "Settings")
    if Check(settings ~= nil, context .. ": Settings missing") then
        Click(settings)
        Check(counts.settings == 1, context .. ": Settings did not open the selected frame's settings")
    end
    local cooldown = Button(world, hud, "Cooldown")
    Check((cooldown ~= nil) == (EM2.HUD.CooldownAnchorSupported() == true),
        context .. ": Cooldown presence does not follow the client")
    if cooldown then
        local before = EM2.HUD.CooldownAnchorEnabled(db.general)
        Click(cooldown)
        Check(EM2.HUD.CooldownAnchorEnabled(db.general) ~= before, context .. ": Cooldown did not toggle the anchor")
        Click(cooldown)
    end
    local anchor = Button(world, hud, "Anchor")
    if Check(anchor ~= nil, context .. ": Anchor missing") then
        Click(anchor)
        Check(counts.anchorPicker == 1 and type(picker._onPick) == "function", context .. ": Anchor did not open the picker")
        picker._onPick("UIParent")
        Check(db.general.anchorName == "UIParent", context .. ": the anchor pick was not saved")
    end
    local help = Button(world, hud, "?")
    if Check(help ~= nil, context .. ": Help missing") then
        Click(help)
        Check(counts["tour:edit_mode"] == 1, context .. ": Help did not open the guided tour at Edit Mode")
    end

    -- Frame picker and settings picker.
    local opened = {}
    local open = EM2.Popups.Open
    EM2.Popups.Open = function(key, anchorFrame) opened[#opened + 1] = key; return open(key, anchorFrame) end
    local contextBtn
    for _, frame in ipairs(world.widgets.frames) do
        local text = LabelOf(frame)
        if (text == "Frames" or text == "Groups" or text == "Player") and frame.parent == hud and frame.scripts.OnClick then
            contextBtn = frame
        end
    end
    if Check(contextBtn ~= nil, context .. ": the frame picker button is missing") then
        Click(contextBtn)
        local pick
        for _, frame in ipairs(world.widgets.frames) do
            if frame._msufKey and frame._msufKey ~= EM2.State.GetUnitKey() and frame.shown and frame.scripts.OnClick then
                pick = pick or frame
            end
        end
        if Check(pick ~= nil, context .. ": the frame picker lists no other frame") then
            local key = pick._msufKey
            Click(pick)
            Check(opened[#opened] == key and EM2.State.GetUnitKey() == key,
                context .. ": picking " .. tostring(key) .. " did not select it and open its popup")
        end
    end
    EM2.Popups.Open = open
    EM2.Popups.CloseAll()
    -- The inspector's chevron opens the settings of the frame picked there.
    local row2, inspector = Named(world, "MSUF_EM2_HUD_Row2"), nil
    for _, frame in ipairs(world.widgets.frames) do
        if row2 and frame.parent == row2 and frame.scripts.OnClick then inspector = frame end
    end
    if Check(inspector ~= nil, context .. ": the inspector settings picker is missing") then
        local before = counts.settings or 0
        Click(inspector)
        local row
        for _, frame in ipairs(world.widgets.frames) do
            if frame._msufKey and frame.shown and frame.scripts.OnClick then row = row or frame end
        end
        if Check(row ~= nil, context .. ": the settings picker lists nothing") then
            Click(row)
            Check((counts.settings or 0) == before + 1, context .. ": the settings picker did not open settings")
        end
    end

    -- History buttons.
    local undoCount, redoCount = 0, 0
    local undo, redo = EM2.Undo.DoUndo, EM2.Undo.DoRedo
    EM2.Undo.DoUndo = function() undoCount = undoCount + 1 end
    EM2.Undo.DoRedo = function() redoCount = redoCount + 1 end
    local undoBtn, redoBtn = env.MSUF_EditModeUndoBtn, env.MSUF_EditModeRedoBtn
    if Check(undoBtn and redoBtn, context .. ": history buttons missing") then
        Click(undoBtn); Click(redoBtn)
        Check(undoCount == 1 and redoCount == 1, context .. ": Undo/Redo did not reach the history")
    end
    EM2.Undo.DoUndo, EM2.Undo.DoRedo = undo, redo

    -- Discard: the confirm dialog, then Done.
    local discard = Button(world, hud, "Discard")
    if Check(discard ~= nil, context .. ": Discard missing") then
        Click(discard)
        local confirm = Named(world, "MSUF_EM2_CancelConfirm")
        if Check(confirm ~= nil and confirm.shown == true, context .. ": Discard did not ask first") then
            Click(Button(world, confirm, "No, keep"))
            Check(confirm.shown ~= true and EM2.State.IsActive() == true, context .. ": No, keep did not keep the session")
        end
    end
    local done = Button(world, hud, "Done")
    if Check(done ~= nil, context .. ": Done missing") then
        Click(done)
        world.widgets:RunTimers()
        Check(EM2.State.IsActive() ~= true and EM2.HUD.IsShown() ~= true, context .. ": Done did not exit Edit Mode")
    end

    -- Discard for real on a second session.
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not reopen")
    world.widgets:RunTimers()
    discard = Button(world, hud, "Discard")
    Click(discard)
    local confirm = Named(world, "MSUF_EM2_CancelConfirm")
    if Check(confirm ~= nil and confirm.shown == true, context .. ": Discard did not ask again") then
        Click(Button(world, confirm, "Yes, discard"))
        world.widgets:RunTimers()
        Check(EM2.State.IsActive() ~= true, context .. ": Yes, discard did not end the session")
    end
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    Run(flavor)
end

if #failures > 0 then
    error("editmode_hud_toolbar_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_hud_toolbar_smoke: ok (every toolbar control on Mainline and Vanilla)")
