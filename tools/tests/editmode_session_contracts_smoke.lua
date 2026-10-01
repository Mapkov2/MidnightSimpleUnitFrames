-- MSUF Edit Mode session contracts from review 2 (classic-shell), each
-- pinned on the real core and Options graphs (tools/tests/client_world.lua):
--   F6  an undo or redo resyncs the Class Resource / detached power popup and
--       an open external-element popup, and refreshes the external popup's
--       history buttons, so the next edit cannot write undone values back.
--   F10 Edit Mode closing for combat never runs the full restore inside
--       combat: PLAYER_REGEN_DISABLED arrives before InCombatLockdown() is
--       true, and the restore waits for PLAYER_REGEN_ENABLED; an exit whose
--       next-frame restore lands in combat defers the same way.
--   F21 a castbar or resource nudge (PrepareChange/CommitPrepared) inside the
--       debounce window of a unit nudge gets its own undo entry instead of
--       folding into the unit's entry through the dead fallback stack.
--   F11 the HUD Auras, Cooldown and Anchor tools record their own undo entry
--       instead of writing the profile between two history snapshots.
-- Only runtime owners with no offline unit data are stubbed.
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
    return world, env, history
end

local function Counter(counts, owner, name, replacement)
    local original = owner[name]
    owner[name] = function(...)
        counts[name] = (counts[name] or 0) + 1
        if replacement then return replacement(...) end
        if original then return original(...) end
    end
end

-- F6 ------------------------------------------------------------------------
local function RunPopupResync(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " F6 popup resync"
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    local counts = {}
    Counter(counts, EM2.ResourcePopup, "Sync")
    Counter(counts, EM2.ExternalPopup, "RefreshHistory", function() end)

    local bars = env.MSUF_DB.bars
    local before = bars.classPowerOffsetY
    Check(EM2.Undo.BeginChange("classpower", "bars", "Move") == true, context .. ": undo transaction did not open")
    bars.classPowerOffsetY = 33
    EM2.Undo.CommitChange()
    for key in pairs(counts) do counts[key] = 0 end
    Check(history.Undo() == true and bars.classPowerOffsetY == before, context .. ": undo of the resource move failed")
    Check((counts.Sync or 0) > 0, context .. ": Undo left the Class Resource popup showing the undone value")
    Check((counts.RefreshHistory or 0) > 0, context .. ": Undo did not refresh the external popup's history buttons")
    counts.Sync = 0
    Check(history.Redo() == true and bars.classPowerOffsetY == 33, context .. ": redo of the resource move failed")
    Check((counts.Sync or 0) > 0, context .. ": Redo left the Class Resource popup showing the old value")
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

local function RunExternalResync(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " F6 external popup resync"
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    local synced = 0
    EM2.ExternalPopup.IsOpen = function() return true end
    EM2.ExternalPopup.Sync = function() synced = synced + 1; return true end
    local bars = env.MSUF_DB.bars
    EM2.Undo.BeginChange("classpower", "bars", "Move")
    bars.classPowerOffsetX = 21
    EM2.Undo.CommitChange()
    synced = 0
    Check(history.Undo() == true, context .. ": undo failed")
    Check(synced > 0, context .. ": Undo left an open external-element popup showing the undone values")
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

-- F10 -----------------------------------------------------------------------
local function Fire(world, event)
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame.events and frame.events[event] and frame.scripts and frame.scripts.OnEvent
        if handler then handler(frame, event) end
    end
end

local function RunCombatExit(flavor)
    local world, env = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " F10 combat exit"
    local applies, restores = 0, 0
    world.core.UF.Apply = function() applies = applies + 1; return true end
    local refresh = env.MSUF_RefreshAllUnitVisibilityDrivers
    env.MSUF_RefreshAllUnitVisibilityDrivers = function(want)
        if want == false then restores = restores + 1 end
        if refresh then return refresh(want) end
    end

    -- Combat starts: the event arrives while the client still reports no lockdown.
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    applies, restores = 0, 0
    Fire(world, "PLAYER_REGEN_DISABLED")
    Check(EM2.State.IsActive() ~= true, context .. ": Edit Mode stayed open at PLAYER_REGEN_DISABLED")
    world.widgets:SetCombat(true)
    world.widgets:RunTimers()
    Check(applies == 0 and restores == 0, context .. ": the exit restore ran inside combat ("
        .. applies .. " applies, " .. restores .. " visibility restores)")
    world.widgets:SetCombat(false)
    Fire(world, "PLAYER_REGEN_ENABLED")
    world.widgets:RunTimers()
    Check(applies == 1 and restores == 1, context .. ": the exit restore did not run once after combat ("
        .. applies .. " applies, " .. restores .. " visibility restores)")

    -- A normal exit whose next-frame restore lands in combat.
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not reopen")
    world.widgets:RunTimers()
    applies, restores = 0, 0
    EM2.State.Exit("test")
    world.widgets:SetCombat(true)
    world.widgets:RunTimers()
    Check(applies == 0 and restores == 0, context .. ": the deferred exit restore ran in combat")
    world.widgets:SetCombat(false)
    Fire(world, "PLAYER_REGEN_ENABLED")
    world.widgets:RunTimers()
    Check(applies == 1 and restores == 1, context .. ": the deferred exit restore did not run after combat")
end

-- F21 -----------------------------------------------------------------------
local function RunNudgeEntries(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " F21 nudge entries"
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    local db = env.MSUF_DB
    db.general = db.general or {}
    local unitX, castbarX = tonumber(db.player.offsetX) or 0, tonumber(db.general.castbarPlayerOffsetX) or 0
    local baseline = history.GetHistoryState().undoCount
    EM2.Undo.BeforeChange("unit", "player", true)
    db.player.offsetX = unitX + 1
    -- Same frame, inside the unit nudge's debounce window: the castbar nudge.
    local prepared = EM2.Undo.PrepareChange("castbar", "player")
    Check(type(prepared) == "table" and prepared.shared ~= nil,
        context .. ": the castbar nudge fell back to the Edit Mode-only undo stack")
    db.general.castbarPlayerOffsetX = castbarX + 1
    EM2.Undo.CommitPrepared(prepared)
    world.widgets:RunTimers()
    Check(history.GetHistoryState().undoCount == baseline + 2,
        context .. ": unit and castbar nudges did not get one undo entry each ("
        .. (history.GetHistoryState().undoCount - baseline) .. ")")
    Check(history.Undo() == true and db.general.castbarPlayerOffsetX == castbarX and db.player.offsetX == unitX + 1,
        context .. ": the first Undo did not revert exactly the castbar nudge")
    Check(history.Undo() == true and db.player.offsetX == unitX,
        context .. ": the second Undo did not revert the unit nudge")
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

-- F11 -----------------------------------------------------------------------
local function HudButton(world, text)
    for _, frame in ipairs(world.widgets.frames) do
        local label = frame._msuf2Label or frame._label
        local shown = label and label.GetText and label:GetText()
        if shown == text and frame.scripts and frame.scripts.OnClick then return frame end
    end
end

local function RunHudToolEntries(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor .. " F11 HUD tools"
    local db = env.MSUF_DB
    db.general.hideAdvancedMenu = false
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    local picker = { Show = function() end }
    env.MSUF_EnsureAnchorPicker = function() return picker end
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()

    local function Tool(label, mutate, read)
        local before = read()
        local count = history.GetHistoryState().undoCount
        mutate()
        world.widgets:RunTimers()
        Check(history.GetHistoryState().undoCount == count + 1, context .. ": " .. label
            .. " wrote the profile without its own undo entry")
        Check(history.Undo() == true and read() == before, context .. ": Undo did not revert the " .. label .. " change")
    end

    local auras = HudButton(world, "Auras")
    if Check(auras ~= nil, context .. ": Auras button missing") then
        Tool("Auras toggle", function() auras.scripts.OnClick(auras, "LeftButton") end,
            function() return db.auras3.shared.showInEditMode == true end)
    end
    -- Only clients that host the Cooldown Manager offer the Cooldown tool.
    local cooldown = HudButton(world, "Cooldown")
    local hostsCooldown = EM2.HUD.CooldownAnchorSupported() == true
    Check((cooldown ~= nil) == hostsCooldown, context .. ": Cooldown button presence does not match the client")
    if cooldown then
        Tool("Cooldown anchor toggle", function() cooldown.scripts.OnClick(cooldown, "LeftButton") end,
            function() return db.general.anchorToCooldown == true end)
    end
    local anchor = HudButton(world, "Anchor")
    if Check(anchor ~= nil, context .. ": Anchor button missing") then
        Tool("anchor picker", function()
            anchor.scripts.OnClick(anchor, "LeftButton")
            picker._onPick("MSUF_SmokeAnchorFrame")
        end, function() return db.general.anchorName end)
    end
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

for _, flavor in ipairs({ "Mainline", "Vanilla", "Mists" }) do
    RunPopupResync(flavor)
    RunExternalResync(flavor)
    RunCombatExit(flavor)
    RunNudgeEntries(flavor)
    RunHudToolEntries(flavor)
end

if #failures > 0 then
    error("editmode_session_contracts_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_session_contracts_smoke: ok (F6, F10, F11, F21 on Mainline, Vanilla, Mists)")
