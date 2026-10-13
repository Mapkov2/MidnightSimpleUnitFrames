-- Strategies execute the shipped providers on real owned frames, never hand-built drag contexts.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local mode = arg[2] or "all"
local World = dofile(root .. "/tools/tests/client_world.lua")
local checks, failures = 0, {}
local function Check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
local function Probe(label, fn)
    local ok, message = xpcall(fn, debug.traceback)
    if not ok then failures[#failures + 1] = label .. ": " .. tostring(message) end
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
for _, loaded in ipairs({ false, true }) do
    local w = World.New(root, flavor)
    local env, ns = w.env, w.core
    env.MAX_BOSS_FRAMES, env.MAX_TOTEMS = 5, 4
    env.AbbreviateNumbers, env.AbbreviateLargeNumbers, env.BreakUpLargeNumbers = tostring, tostring, tostring
    env.UnitName = function(unit) return "Test " .. unit end
    env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    env.UnitExists, env.UnitIsConnected = function() return true end, function() return true end
    env.UnitHealth, env.UnitHealthMax = function() return 500 end, function() return 1000 end
    env.UnitPower, env.UnitPowerMax = function() return 50 end, function() return 100 end
    env.UnitHealthPercent, env.UnitPowerPercent = function() return .5 end, function() return .5 end
    env.GetNumGroupMembers, env.GetNumSubgroupMembers = function() return 0 end, function() return 0 end
    env.IsInRaid, env.IsInGroup = function() return false end, function() return false end
    env.C_UnitAuras = setmetatable({ GetAuraDataByIndex = function() return nil end }, { __index = env.C_UnitAuras })
    -- Named addon frames and the optional Blizzard totem surface are absent before creation.
    -- The kit's catch-all native stand-in must never be adopted as a real addon frame.
    local index = getmetatable(env).__index
    getmetatable(env).__index = function(t, key)
        if key == "TotemFrame" or (type(key) == "string" and key:find("^MidnightSimpleUnitFrames_")) then return nil end
        return index(t, key)
    end
    local cursorX, cursorY = 960, 540
    env.GetCursorPosition = function() return cursorX, cursorY end
    env.IsMouseButtonDown = function() return true end
    env.UIParent:SetSize(1920, 1080)
    for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetNumeric", "SetMaxLetters",
        "SetCursorPosition", "HighlightText", "SetTextInsets", "SetNormalTexture", "SetHighlightTexture",
        "SetPushedTexture", "SetDisabledTexture" }) do
        if not w.widgets.Methods[name] then
            w.widgets.Methods[name] = function(self, value) self["native" .. name] = value end
        end
    end
    w.widgets.Methods.EnableKeyboard = function(self, value) self.keyboard = value end
    if loaded then w:Boot() else
        local suffix, gameType = w.client.tocSuffix or flavor, w.client.isForever and "camelot" or nil
        w:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root, World.CoreTOC(suffix), "enUS", gameType), ns)
    end
    local failure = w:FirstFailure()
    Check(not failure, "graph failed: " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    ns.FinalizeLocale()
    env.MSUF_InitProfiles()
    Check(ns.UF.Initialize(), "real unit engine did not initialize")
    local em, kinds, driver = env.MSUF_EM2, ns.EditModeKinds, ns.EditModeDragDriver
    local function Start()
        Check(ns.EditMode.Open("player"), "native session refused")
        w.widgets:RunTimers(1000)
    end
    if flavor == "Mainline" and (mode == "all" or mode == "native") then Probe("native engines/Options=" .. tostring(loaded), function()
        ns.GF.EnsureDB()
        env.MSUF_DB.gf_party.enabled = true
        env.MSUF_DB.gf_raid.enabled, env.MSUF_DB.gf_raid.petsEnabled = true, true
        env.WIDTH, env.HEIGHT, env.PET, env.TARGET, env.HEALER, env.BOSS = "Width", "Height", "Pet", "Target", "Healer", "Boss"
        for _, frame in ipairs(w.widgets.frames) do
            local callback = frame:GetScript("OnEvent")
            if callback and frame:IsEventRegistered("PLAYER_LOGIN")
                and debug.getinfo(callback, "S").source:find("Group_EM2", 1, true) then callback(frame, "PLAYER_LOGIN") end
        end
        w.widgets:RunTimers(1000)
        env.MSUF_DB.player.powerBarDetached = true
        Check(env.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true), "native Power owner did not detach")
        for _, spec in ipairs({
            { "unit", "player", "player", "offsetX", "offsetY" },
            { "stacked", "boss", "boss", "offsetX", "offsetY" },
            { "castbar", "castbar_player", "general", "castbarPlayerOffsetX", "castbarPlayerOffsetY" },
            { "subframe", "power_player", "player", "detachedPowerBarOffsetX", "detachedPowerBarOffsetY" },
            { "group", "gf_party", "gf_party", "offsetX", "offsetY" },
            { "external", "external:msuf_group_extras:raid_pets", "gf_raid", "petsX", "petsY" },
        }) do
            Start()
            env.MSUF_GF_EM2_ShowPreview("party")
            env.MSUF_GF_EM2_ShowPreview("raid")
            env.MSUF_UpdatePlayerCastbarPreview()
            w.widgets:RunTimers(1000)
            local name, key, scope, xKey, yKey = unpack(spec)
            local cfg = assert(em.Registry.Get(key), "native registration missing: " .. key)
            local bar = assert(cfg.getFrame(), "real owned frame missing: " .. key)
            Check(kinds.For(key, cfg, bar) == kinds[name], "wrong strategy selected: " .. key)
            bar.left, bar.bottom = 500, 300
            em.Movers.Show()
            em.Movers.SyncAll()
            local mover = assert(em.Movers.Get(key), "real native mover missing: " .. key)
            mover.left, mover.bottom = bar.left, bar.bottom
            local conf = env.MSUF_DB[scope]
            local beforeX, beforeY = conf[xKey], conf[yKey]
            local category, historyKey = kinds[name]:history(key, cfg)
            Check(em.Undo.BeginChange(category, historyKey, "Move"), "history refused: " .. key)
            local context = assert(kinds[name]:beginDrag(mover, key, cfg), "begin refused: " .. key)
            Check(context.bar == bar and context.mover == mover, "strategy replaced native owner/context: " .. key)
            local cx, cy = context.startCX + 31, context.startCY - 17
            Check(kinds[name]:applyDrag(context, cx, cy, 1) ~= false, "apply refused: " .. key)
            Check(kinds[name]:commit(context, cx, cy, 1) ~= false, "commit refused: " .. key)
            em.Undo.CommitChange()
            local afterX, afterY = conf[xKey], conf[yKey]
            Check(afterX ~= beforeX or afterY ~= beforeY, "real persisted values did not change: " .. key)
            Check(em.Undo.CanUndo(), "real history recorded no move: " .. key)
            em.Undo.DoUndo()
            conf = env.MSUF_DB[scope]
            Check(conf[xKey] == beforeX and conf[yKey] == beforeY, "undo failed: " .. key)
            em.Undo.DoRedo()
            conf = env.MSUF_DB[scope]
            Check(conf[xKey] == afterX and conf[yKey] == afterY, "redo failed: " .. key)
            kinds[name]:openPopup(key, bar)
            Check(em.Popups.IsAnyOpen(), "real popup did not open: " .. key)
            em.Popups.CloseAll()
            ns.EditMode.CancelAll()
            conf = env.MSUF_DB[scope]
            Check(conf[xKey] == beforeX and conf[yKey] == beforeY, "Cancel All failed: " .. key)
            Check(not driver.IsRunning() and not em.Ticker.IsDragging(), "cancel left phantom drag: " .. key)
            Start()
            env.MSUF_UpdatePlayerCastbarPreview()
            em.Movers.SyncAll()
            mover.left, mover.bottom = 500, 300
            cursorX, cursorY = mover:GetCenter()
            Check(em.Ticker.BeginDrag(mover, key, cfg), "native held drag refused: " .. key)
            cursorX, cursorY = cursorX + 23, cursorY - 11
            local shared = driver.GetFrame()
            shared:GetScript("OnUpdate")(shared, .016)
            Check(em.Ticker.IsDragging(), "native held drag lost context: " .. key)
            w:EnterCombat()
            Check(not ns.EditMode.IsActive() and not em.Ticker.IsDragging() and not driver.IsRunning(),
                "combat left a held strategy active: " .. key)
            Check(not bar._msufDragActive, "combat left native owner drag flag: " .. key)
            w:LeaveCombat()
            w.widgets:RunTimers(1000)
            Check(not ns.EditMode.IsActive() and not driver.IsRunning(), "regen revived stale drag: " .. key)
        end
    end) end
    if mode == "all" or mode == "aura" then Probe(flavor .. "/aura/Options=" .. tostring(loaded), function()
        Start()
        ns.MSUF_Auras3.RefreshEditPreview("player")
        local group = assert(ns.MSUF_Auras3.EditMode.groups.player.buff, "real aura group missing")
        local context = assert(kinds.aura:beginDrag(group), "aura begin refused")
        Check(context == group and group._dragging, "aura strategy lost native ownership")
        cursorX, cursorY = cursorX + 31, cursorY - 17
        kinds.aura:applyDrag(context, .1)
        Check(group._dragMoved and group._lastDragX == group._dragStartOffsetX + 31, "aura apply did not persist")
        Check(kinds.aura:commit(context), "aura commit refused")
        Check(not group._dragging and not driver.IsRunning(), "aura commit left capture/drag work")
        Check(em.Undo.CanUndo(), "native aura history recorded no move")
        em.Undo.DoUndo()
        em.Undo.DoRedo()
        Check(kinds.aura:openPopup("aura_player", group), "native aura popup refused")
        Check(em.AuraPopup.IsOpen(), "aura popup never opened")
        em.Popups.CloseAll()
        ns.EditMode.CancelAll()
        Check(not ns.EditMode.IsActive(), "aura cancel left session active")
        Start()
        ns.MSUF_Auras3.RefreshEditPreview("player")
        local hide = group.Hide
        group.Hide = function(self)
            local shown = self:IsShown()
            hide(self)
            local onHide = self:GetScript("OnHide")
            if shown and onHide then onHide(self) end
        end
        assert(kinds.aura:beginDrag(group))
        cursorX, cursorY = cursorX + 29, cursorY + 13
        kinds.aura:applyDrag(group, .1)
        ns.EditMode.CancelAll()
        Check(not group._dragging and not driver.IsRunning(), "cancel left native aura capture active")
        Start()
        ns.MSUF_Auras3.RefreshEditPreview("player")
        assert(kinds.aura:beginDrag(group))
        w:EnterCombat()
        Check(not group._dragging and not driver.IsRunning(), "combat left aura capture active")
        w:LeaveCombat()
        w.widgets:RunTimers(1000)
        Check(not ns.EditMode.IsActive() and not group._dragging, "regen revived old aura drag")
    end) end
    if mode == "all" or mode == "gameplay" then Probe(flavor .. "/gameplay/Options=" .. tostring(loaded), function()
        local db = ns.MSUF_EnsureGameplayDefaults()
        db.enableCombatTimer, db.lockCombatTimer, db.combatTimerClickThrough = true, false, false
        ns.MSUF_ApplyGameplayVisuals()
        Start()
        local beforeX, beforeY = db.combatOffsetX, db.combatOffsetY
        local frame = assert(ns.MSUF_GetCombatTimerFrame(), "real gameplay timer missing")
        local context = assert(kinds.gameplay:beginDrag(frame, "Combat timer position", "gameplay:combatTimer:position",
            ns.Gameplay.SelectNudgeFrame, ns.Gameplay.BeginHistory))
        Check(context == frame and frame._msufDragging and frame.moving, "gameplay begin lost native frame")
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", env.UIParent, "CENTER", 37, -19)
        -- The native moving region reports the new screen rect; the shared kit
        -- records SetPoint but does not solve anchors into coordinates.
        local ax, ay = env.UIParent:GetCenter()
        frame.left, frame.bottom = ax + 37 - frame:GetWidth() / 2, ay - 19 - frame:GetHeight() / 2
        kinds.gameplay:applyDrag(context, db, "combatOffsetX", "combatOffsetY", env.UIParent, true, ns.Gameplay.RoundInt)
        Check(db.combatOffsetX == 37 and db.combatOffsetY == -19, "gameplay apply did not persist")
        Check(kinds.gameplay:commit(context), "gameplay commit refused")
        Check(not frame._msufDragging and not frame.moving, "gameplay commit left native movement active")
        Check(not frame._msufGameplayHistoryTransaction, "gameplay history was left open")
        if loaded then
            Check(em.Undo.CanUndo(), "real gameplay history recorded no move with Options loaded")
            em.Undo.DoUndo()
            Check(env.MSUF_DB.gameplay.combatOffsetX == beforeX, "gameplay undo lost original position")
            em.Undo.DoRedo()
            Check(env.MSUF_DB.gameplay.combatOffsetX == 37, "gameplay redo lost stored position")
        end
        -- Native gameplay movers use the Gameplay menu's sliders. The popup
        -- router has no gameplay popup; preserve its existing harmless dispatch.
        kinds.gameplay:openPopup("gameplay", frame)
        Check(not em.Popups.IsAnyOpen(), "gameplay invented a popup owner")
        ns.EditMode.CancelAll()
        Check(env.MSUF_DB.gameplay.combatOffsetX == beforeX and env.MSUF_DB.gameplay.combatOffsetY == beforeY,
            "gameplay Cancel All did not restore real profile")
        w:EnterCombat()
        Check(not frame.keyboard, "gameplay kept keyboard capture in combat")
        w:LeaveCombat()
        Check(not frame.moving and not driver.IsRunning(), "gameplay combat restoration left movement active")
    end) end
    if mode == "all" or mode == "gameplay" then
    for _, feature in ipairs({ "timer", "state" }) do
    local xKey, yKey = feature == "timer" and "combatOffsetX" or "combatStateOffsetX",
        feature == "timer" and "combatOffsetY" or "combatStateOffsetY"
    for _, ending in ipairs({ "cancel", "combat", "close", "reentry", "close-reentry", "nested-reentry",
        "profile-reentry", "combat-reentry", "suspend", "suspend-combat", "suspend-replaced", "opt-out" }) do
    Probe(flavor .. "/held gameplay/" .. feature .. "/" .. ending .. "/Options=" .. tostring(loaded), function()
        ns.EditMode.CancelAll()
        w:LeaveCombat()
        w.widgets:RunTimers(1000)
        local db = ns.MSUF_EnsureGameplayDefaults()
        db.enableCombatTimer, db.lockCombatTimer, db.combatTimerClickThrough = true, false, false
        db.enableCombatStateText, db.lockCombatState = true, false
        db[xKey], db[yKey] = 0, -200
        ns.MSUF_ApplyGameplayVisuals()
        local frame = feature == "timer" and ns.MSUF_GetCombatTimerFrame()
        if not frame then
            for _, owned in ipairs(w.widgets.frames) do
                if owned:GetName() == "MSUF_CombatStateFrame" then frame = owned; break end
            end
        end
        assert(frame, "shipped Gameplay frame missing")
        local starts, stops, syncs = 0, 0, 0
        local startMoving, stopMoving = frame.StartMoving, frame.StopMovingOrSizing
        frame.StartMoving = function(self) starts = starts + 1; startMoving(self) end
        frame.StopMovingOrSizing = function(self)
            stops = stops + 1
            local moving = self.moving
            local cx, cy = self:GetCenter()
            stopMoving(self)
            if moving then
                -- Native StopMovingOrSizing leaves the held screen rect anchored.
                local ax, ay = env.UIParent:GetCenter()
                self:ClearAllPoints()
                self:SetPoint("CENTER", env.UIParent, "CENTER", cx - ax, cy - ay)
            end
        end
        local menu = loaded and env.MSUF2
        local refresh = menu and menu.RefreshVisibleSliders
        if menu then menu.RefreshVisibleSliders = function(...) syncs = syncs + 1; if refresh then return refresh(...) end end end
        local function Position(x, y)
            local ax, ay = env.UIParent:GetCenter()
            frame.left, frame.bottom = ax + x - frame:GetWidth() / 2, ay + y - frame:GetHeight() / 2
        end
        local function HistoryCounts()
            if not menu then return 0, 0 end
            local h = menu.GetHistoryState()
            return h.undoCount, h.redoCount
        end
        if ending == "opt-out" and flavor == "Mainline" then
            env.MSUF_EllesmereEditMode_SetEnabled(false)
            Check(env.MSUF_DB.general.ellesmereEditModeIntegration == false, "opt-out preference lost")
        end
        local suspension = ending:find("^suspend") ~= nil
        local reentry = ending:find("reentry", 1, true) ~= nil
        if suspension then
            Check(ns.EditMode.Open("player", { provider = "ellesmere" }), "external session refused")
            w.widgets:RunTimers(1000)
        else Start() end
        local suspendedSessionClosed = false
        if suspension then
            ns.EventBus:Register("EDITMODE_STATE", "held-suspension", function(_, active)
                if not active then suspendedSessionClosed = true end
            end)
        end
        local undo, redo = HistoryCounts()
        frame:GetScript("OnDragStart")(frame)
        Check(starts == 1 and stops == 0 and frame.moving and frame._msufDragging, "real held start missing")
        Check(not loaded or frame._msufGameplayHistoryTransaction, "real held history did not begin")
        Position(63, -27)
        local expectedX, expectedY = 0, -200
        local originalDB = env.MSUF_DB
        local function ReplaceProfile()
            local identity = ns.ProfileRuntime.Identity()
            ns.ProfileRuntime.BeforeMutation()
            local replacement = env.MSUF_DeepCopy(originalDB)
            replacement.gameplay[xKey], replacement.gameplay[yKey] = 11, -99
            env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile] = replacement
            env.MSUF_DB = replacement
            Check(not ns.ProfileRuntime.IsCurrentIdentity(identity), "replacement retained old profile identity")
            expectedX, expectedY = 11, -99
        end
        if suspension then
            local bridge = flavor == "Mainline" and em.ExternalProviders.providers.ellesmere
            local generation = bridge and bridge.sessionGeneration
            if ending == "suspend" then ns.EditMode.SuspendExternalPreview() else w:EnterCombat() end
            Check(not bridge or bridge.sessionGeneration == generation + 1, "shipped suspension bridge was bypassed")
            Check(ns.EditMode.IsActive() and ns.EditMode.GetProvider() == "ellesmere"
                and ns.EditMode.IsExternalPreviewSuspended(), "suspension closed or lost provider/session")
        elseif ending == "combat" then w:EnterCombat()
        elseif ending == "close" then ns.EditMode.Close("held-gameplay")
        else
            if reentry then
                ns.EventBus:Register("EDITMODE_STATE", "held-reopen", function(_, active)
                    if not active then
                        ns.EventBus:Unregister("EDITMODE_STATE", "held-reopen")
                        if ending == "profile-reentry" then
                            ReplaceProfile()
                        end
                        if ending == "combat-reentry" then
                            Check(not ns.EditMode.Open("player"), "combat accepted replacement session")
                        else
                            Check(ns.EditMode.Open("player"), "subscriber reopen refused")
                            if ending == "nested-reentry" then
                                ns.EditMode.Close("nested")
                                Check(ns.EditMode.Open("target"), "nested reopen refused")
                            end
                        end
                    end
                end)
            end
            if ending == "reentry" or ending == "cancel" then ns.EditMode.CancelAll()
            elseif ending == "combat-reentry" then w:EnterCombat()
            else ns.EditMode.Close("held-reentry") end
        end
        Check(stops == 1 and not frame.moving and not frame._msufDragging, "held " .. ending .. " left native movement")
        Check(not frame._msufGameplayHistoryTransaction, "held teardown left history transaction")
        Check(ns.EditMode.IsActive() == (suspension or (reentry and ending ~= "combat-reentry")), "held teardown/reentry state mismatch")
        db = env.MSUF_DB.gameplay
        Check(db[xKey] == expectedX and db[yKey] == expectedY, "held teardown lost original coordinates")
        local countUndo, countRedo = HistoryCounts()
        Check(countUndo == undo and countRedo == redo, "held teardown wrote history")
        local beforeSync = syncs
        -- Simulate the native release rect even after synchronous Cancel re-anchored.
        Position(63, -27)
        frame:GetScript("OnDragStop")(frame)
        Check(stops == 1 and syncs == beforeSync, "late release repeated native stop/slider sync")
        Check(db[xKey] == expectedX and db[yKey] == expectedY, "late release overwrote restored coordinates")
        countUndo, countRedo = HistoryCounts()
        Check(countUndo == undo and countRedo == redo, "late release wrote history")
        if ending:find("combat", 1, true) or ending == "suspend-replaced" then
            Check(not frame.keyboard, "combat retained gameplay keyboard capture")
            if suspension then
                Check(not ns.EditMode.ResumeExternalPreview(), "combat allowed external resume")
                Check(frame._msufAppliedPositionX == nil and frame._msufAppliedPositionY == nil,
                    "combat restored Gameplay anchors before regen")
            end
            w:LeaveCombat()
        end
        if ending == "suspend" then Check(ns.EditMode.ResumeExternalPreview(), "manual resume refused") end
        if ending == "suspend-replaced" then
            Check(not suspendedSessionClosed, "suspension closed and reopened the session")
            ns.EventBus:Unregister("EDITMODE_STATE", "held-suspension")
            -- Invalidate the queued external resume before it runs. Only the new
            -- profile/session may supply the anchors; late old work must stay inert.
            ns.EditMode.Close("replace-suspended")
            ReplaceProfile()
            Start()
        end
        w.widgets:RunTimers(1000)
        db = env.MSUF_DB.gameplay
        Check(originalDB.gameplay[xKey] == 0 and originalDB.gameplay[yKey] == -200,
            "old session wrote into detached profile")
        if suspension then
            Check(not suspendedSessionClosed, "suspension closed and reopened the session")
            ns.EventBus:Unregister("EDITMODE_STATE", "held-suspension")
            Check(ns.EditMode.IsActive() and not ns.EditMode.IsExternalPreviewSuspended(), "resume lost active session")
            Check(ns.EditMode.GetProvider() == (ending == "suspend-replaced" and "msuf" or "ellesmere"),
                "stale resume replaced provider")
        end
        Check(frame._msufAppliedPositionX == expectedX and frame._msufAppliedPositionY == expectedY, "restore lost applied cache")
        local _, anchor, _, x, y = frame:GetPoint()
        Check(anchor == env.UIParent and x == expectedX and y == expectedY, "restore lost native anchor")
        Check(not driver.IsRunning(), "held teardown revived shared driver")
        if not ns.EditMode.IsActive() then Start() end
        frame:GetScript("OnDragStart")(frame)
        Check(starts == 2 and frame.moving and frame._msufDragging, "fresh reopened drag refused")
        Position(37, -19)
        frame:GetScript("OnDragStop")(frame)
        Check(stops == 2 and not frame.moving and not frame._msufDragging, "fresh release lost native stop")
        Check(db[xKey] == 37 and db[yKey] == -19, "fresh release lost exact coordinates")
        Check(frame._msufAppliedPositionX == 37 and frame._msufAppliedPositionY == -19, "fresh release lost cache sync")
        Check(not loaded or syncs > beforeSync, "fresh release missed slider sync")
        Check(not frame._msufGameplayHistoryTransaction, "fresh release left history open")
        if menu then
            countUndo, countRedo = HistoryCounts()
            Check(countUndo == undo + 1 and countRedo == 0, "fresh release did not record exactly one history step")
            em.Undo.DoUndo()
            Check(env.MSUF_DB.gameplay[xKey] == expectedX and env.MSUF_DB.gameplay[yKey] == expectedY,
                "fresh drag undo lost exact original position")
            em.Undo.DoRedo()
            Check(env.MSUF_DB.gameplay[xKey] == 37 and env.MSUF_DB.gameplay[yKey] == -19,
                "fresh drag redo lost exact committed position")
        end
        ns.EditMode.CancelAll()
        Check(env.MSUF_DB.gameplay[xKey] == expectedX and env.MSUF_DB.gameplay[yKey] == expectedY,
            "fresh session Cancel All lost original snapshot")
        if ending == "opt-out" and flavor == "Mainline" then env.MSUF_EllesmereEditMode_SetEnabled(true) end
        frame.StartMoving, frame.StopMovingOrSizing = startMoving, stopMoving
        if menu then menu.RefreshVisibleSliders = refresh end
    end)
    end
    end
    end
    Check(loaded or w.optionsPaths == nil, "strategy forced Options to load")
end
end
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS real Edit Mode strategy engines: " .. checks .. " checks, five clients, Options unloaded/loaded")
