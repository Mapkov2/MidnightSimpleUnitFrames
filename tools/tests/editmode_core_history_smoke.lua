-- The real core graph owns every Edit Mode gesture before Options is parsed.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checks = 0
local function Check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
-- Native position popups: core-only first open, real setters and shared history.
if arg[3] == "positions" then
    local flavor = arg[2] or "Mainline"
    local w = World.New(root, flavor)
    local env, ns = w.env, w.core
    env.GetCursorPosition = function() return 300, 400 end
    env.IsShiftKeyDown = function() return false end
    env.IsControlKeyDown = function() return false end
    for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets",
        "SetMaxLetters", "ClearFocus", "SetCursorPosition", "HighlightText", "SetAutoFocus" }) do
        w.widgets.Methods[name] = function() end
    end
    w.widgets.Methods.HasFocus = function(self) return self.focused == true end
    w.widgets.Methods.ClearFocus = function(self) self.focused = false end
    local suffix = w.client.tocSuffix or flavor
    local gameType = w.client.isForever and "camelot" or nil
    w:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root, World.CoreTOC(suffix), "enUS", gameType), ns)
    Check(w:FirstFailure() == nil, "position core graph failed")
    env.MSUF_InitProfiles()
    ns.GF.EnsureDB()
    local apply, H, em = ns.ApplyService, ns.History, env.MSUF_EM2
    apply.QueueFlush, apply.Flush, apply.Quiesce = function() return true end, function() end, function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    ns.UF.Apply = function() return true end
    local loads = 0
    env.MSUF_EnsureOptionsLoaded = function() loads = loads + 1 return false end
    local priority = ns.GF.GetPriorityConf()
    priority.enabled, priority.anchorMode = true, "FREE"
    priority.offsetX, priority.offsetY = -123, 47
    local g = env.MSUF_DB.gameplay
    g.combatOffsetX, g.combatOffsetY = 61, -202
    g.combatStateOffsetX, g.combatStateOffsetY = -33, 85
    local prioritySetter, priorityWrites = ns.GF.SetPriorityOption, 0
    ns.GF.SetPriorityOption = function(...)
        priorityWrites = priorityWrites + 1
        return prioritySetter(...)
    end
    local function PopupFrame()
        for _, f in ipairs(w.widgets.frames) do if f._msufPositionKey then return f end end
    end
    Check(PopupFrame() == nil, "position widgets were built at startup")
    Check(env.MSUF_SetMSUFEditModeDirect(true, "player") == true, "position entry refused")
    local cases = {
        { "gf_priority", "gf_priority", "offsetX", "offsetY", 4000 },
        { "external:msuf_gameplay:combat_timer", "gameplay", "combatOffsetX", "combatOffsetY", 800 },
        { "external:msuf_gameplay:combat_state", "gameplay", "combatStateOffsetX", "combatStateOffsetY", 800 },
    }
    local function Typed(box, value)
        box:SetText(tostring(value))
        box:GetScript("OnEnterPressed")(box)
        -- A subsequent native blur must not commit again.
        box:GetScript("OnEditFocusLost")(box)
    end
    for _, c in ipairs(cases) do
        local key, section, xKey, yKey, limit = unpack(c)
        if not arg[4] or (arg[4] == "priority") == (section == "gf_priority") then
            local db = env.MSUF_DB[section]
            local x, y = db[xKey], db[yKey]
            Check(em.Popups.Open(key) == true, key .. ": popup did not open")
            local f = assert(PopupFrame(), "position shell missing")
            Check(f:IsShown() and f.xBox:GetText() == tostring(x) and f.yBox:GetText() == tostring(y), key .. ": menu values differ")
            local plus
            for _, button in ipairs(w.widgets.frames) do
                local _, relative = button:GetPoint()
                if relative == f.xBox and button:GetScript("OnClick") then plus = button end
            end
            Check(plus ~= nil, "native plus button missing")
            local depth = H.GetHistoryState().undoCount
            f.xBox.focused = true
            plus:GetScript("OnClick")(plus)
            Check(f.xBox:HasFocus() and f.xBox:GetText() == tostring(x + 1)
                and f.xBox._msufShownText == tostring(x + 1), key .. ": focused step display drift")
            Check(db[xKey] == x + 1 and db[yKey] == y, key .. ": step did not write the axis: " .. tostring(db[xKey]) .. "/" .. tostring(db[yKey]))
            Check(H.GetHistoryState().undoCount == depth + 1, key .. ": step did not make ONE transaction")
            Check(H.historyUndo[#H.historyUndo].label:find("Move", 1, true), "position history is not Move")
            Check(em.Undo.DoUndo() and db[xKey] == x and f.xBox:GetText() == tostring(x), key .. ": undo failed")
            Check(f.xBox:HasFocus() and f.xBox._msufShownText == tostring(x), key .. ": focused undo committed text drift")
            Check(em.Undo.DoRedo() and db[xKey] == x + 1 and f.xBox:GetText() == tostring(x + 1), key .. ": redo failed")
            Check(f.xBox:HasFocus() and f.xBox._msufShownText == tostring(x + 1), key .. ": focused redo committed text drift")
            depth = H.GetHistoryState().undoCount
            f.xBox:ClearFocus()
            f.xBox:GetScript("OnEditFocusLost")(f.xBox)
            Check(H.GetHistoryState().undoCount == depth and db[xKey] == x + 1, key .. ": restored focus blur added history")
            Typed(f.yBox, -12.5)
            Check(db[yKey] == -12 and H.GetHistoryState().undoCount == depth + 1, key .. ": typed rounding/blur transaction drift")
            Typed(f.xBox, 999999)
            Typed(f.yBox, -999999)
            Check(db[xKey] == limit and db[yKey] == -limit, key .. ": range clamp failed")
            depth = H.GetHistoryState().undoCount
            f.xBox.focused = true
            plus:GetScript("OnClick")(plus)
            Check(f.xBox:GetText() == tostring(limit), key .. ": focused step kept an unclamped value")
            f.xBox.focused = false
            Typed(f.xBox, 999999)
            Check(H.GetHistoryState().undoCount == depth, "clamped no-op added history")
            Typed(f.xBox, "nan")
            Check(db[xKey] == limit and f.xBox:GetText() == tostring(limit), "invalid input changed position")
            w.widgets:SetCombat(true)
            depth = H.GetHistoryState().undoCount
            Typed(f.xBox, 7)
            Check(db[xKey] == limit and H.GetHistoryState().undoCount == depth and f.xBox:GetText() == tostring(limit), key .. ": combat write/history escaped")
            w.widgets:SetCombat(false)
            if section == "gf_priority" then
                Check(priorityWrites >= 4, "popup bypassed Priority setter")
                local full, selected = em.Focus.OpenFullSettings, em.Focus.SetSelection
                local opened, placement = 0, false
                em.Focus.SetSelection = function(k, component) placement = k == key and component == "placement" end
                em.Focus.OpenFullSettings = function(page) opened = opened + 1 return page == "gf_priority" end
                f.settingsBtn:GetScript("OnClick")(f.settingsBtn)
                Check(opened == 1 and placement and not f:IsShown(), "Priority full placement route lost")
                em.Focus.OpenFullSettings, em.Focus.SetSelection = full, selected
                priority.anchorMode = "RIGHT"
                em.Popups.Open(key)
                Typed(f.xBox, 15)
                Check(priority.offsetX == limit and priority.anchorMode == "RIGHT", "attached Priority was detached by popup")
                priority.anchorMode = "FREE"
                prioritySetter("offsetX", 36)
                env.MSUF_EM2_SyncGFPopups()
                Check(f.xBox:GetText() == "36", "Priority popup did not follow existing group sync")
            end
            em.Popups.CloseAll()
            Check(not f:IsShown() and not em.Popups.IsAnyOpen(), "router did not close position popup")
        end
    end
    Check(loads == 0, "position popup parsed Options")
    Check(em.State.CancelAll() ~= false, "position Cancel All refused")
    Check(env.MSUF_DB.gf_priority.offsetX == -123 and env.MSUF_DB.gameplay.combatOffsetX == 61
        and env.MSUF_DB.gameplay.combatStateOffsetX == -33, "position Cancel All lost entry values")
    -- Real Gameplay menu sliders and movers share the exact core table setter.
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local mw = MenuWorld.Open(root, flavor, { page = "gameplay", clientScriptBindings = true,
        beforeCore = function(world)
            -- This smoke has no native totem owner; unknown globals are generic proxies.
            world.env.TotemFrame = false
            world.env.IsShiftKeyDown = function() return false end
            world.env.IsControlKeyDown = function() return false end
        end })
    local M, menv, core = mw.M, mw.env, mw.core
    local mem, mg = menv.MSUF_EM2, menv.MSUF_DB.gameplay
    -- Native unit rendering has its own worlds; this menu fixture covers setters.
    menv.MSUF_UFCore_NotifyConfigChanged = function() return true end
    menv.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    core.UF.Apply = function() return true end
    Check(menv.MSUF_SetMSUFEditModeDirect(true, "player"), "menu world edit entry failed")
    mg.enableCombatTimer, mg.enableCombatStateText = true, true
    -- MenuWorld pumps C_Timer, while ScheduleOnce uses a native OnUpdate.
    -- Drive the real Gameplay apply owner to create the two enabled frames.
    core.MSUF_ApplyGameplayVisuals()
    mw:RunTimers()
    for _, section in pairs(M.cache.gameplay.sections) do
        if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
    M.Refresh(M.cache.gameplay.ctx)
    local writes, setter = 0, core.History.SetAdvancedValue
    core.History.SetAdvancedValue = function(...)
        writes = writes + 1
        return setter(...)
    end
    for _, c in ipairs({ cases[2], cases[3] }) do
        local key, _, xKey, yKey = unpack(c)
        local mover = assert(mem.Movers.Get(key), "Gameplay mover missing")
        Check(mover:IsShown(), key .. ": Gameplay mover was hidden; enabled="
            .. tostring(mem.Registry.Get(key).isEnabled()) .. "; frame=" .. tostring(mem.Registry.Get(key).getFrame()))
        mover:Click("LeftButton")
        local f
        for _, frame in ipairs(mw.world.widgets.frames) do if frame._msufPositionKey == key then f = frame end end
        Check(f and f:IsShown(), "Gameplay mover click did not open native popup")
        for axis, field in ipairs({ xKey, yKey }) do
            local record, slider = M.RuntimeControlCatalog.FindBySettingKey("gameplay." .. field, "gameplay")
            Check(record and slider, "Gameplay position menu slider lost")
            local box = axis == 1 and f.xBox or f.yBox
            Check(slider:GetValue() == tonumber(box:GetText()), "initial menu/popup mismatch")
            slider:SetValue(-27)
            MenuWorld.FireScript(slider, "OnValueChanged", -27)
            Check(mg[field] == -27 and box:GetText() == "-27", "menu setter did not sync popup")
            Typed(box, 43.6)
            Check(mg[field] == 44 and slider:GetValue() == 44, "popup setter did not sync menu")
            Check(mem.Undo.DoUndo() and mg[field] == -27 and slider:GetValue() == -27
                and box:GetText() == "-27", "menu/popup undo mismatch")
            Check(mem.Undo.DoRedo() and mg[field] == 44 and slider:GetValue() == 44
                and box:GetText() == "44", "menu/popup redo mismatch")
        end
        Check(writes >= 4, "Gameplay popup bypassed shared menu setter")
        mem.Popups.CloseAll()
    end
    -- Resolve the old Priority placement navigation through the real menu.
    Check(mem.Popups.Open("gf_priority"), "Priority popup with Options did not open")
    local pf
    for _, frame in ipairs(mw.world.widgets.frames) do if frame._msufPositionKey == "gf_priority" then pf = frame end end
    pf.settingsBtn:Click()
    mw:RunTimers()
    Check(M.cache.gf_priority and M.cache.gf_priority.sections.placement and not pf:IsShown(), "Priority full placement page lost")
    print("PASS native position popup core: " .. flavor .. " / " .. checks .. " checks")
    return
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
