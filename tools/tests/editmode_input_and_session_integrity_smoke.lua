-- Edit Mode correctness regressions on real modules and the client load graph.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local mode = assert(arg[2], "case required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end
local function Load(env, ns, path)
    assert(loadfile(root .. "/tools/tests/editmode_prerequisites.lua"))().Install(root, ns, env)
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))
    setfenv(chunk, env)
    return chunk("MidnightSimpleUnitFrames", ns)
end
local function Namespace(env)
    -- The shipped Kernel namespace API inside the sandbox: exports reach the registry and, for the kept
    -- names, the sandbox's globals, as in the client.
    local ns = {}
    assert(loadfile(root .. "/tools/tests/require_fixture.lua"))().InstallKernel(root, ns, env)
    return ns
end
local function Environment()
    local env = setmetatable({}, { __index = _G })
    env._G = env
    return env
end
local function Boot(flavor, options)
    local world = World.New(root, flavor)
    if options == false then
        local suffix = world.client.tocSuffix or flavor
        local gameType = world.client.isForever and "camelot" or nil
        world:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root, World.CoreTOC(suffix), "enUS", gameType), world.core)
    else
        world:Boot()
    end
    local failure = world:FirstFailure()
    assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    local env = world.env
    for _, name in ipairs({ "MSUF_ApplyMsufScale", "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
        "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
        "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
        "MSUF_UpdateAllFonts_Immediate", "MSUF_ForceReanchorAllUnitFrames_Once" }) do world.core.ExportPublic(name, function() end) end
    for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetNumeric", "SetMaxLetters",
        "SetCursorPosition", "HighlightText", "SetTextInsets", "SetNormalTexture", "SetHighlightTexture",
        "SetPushedTexture", "SetDisabledTexture" }) do
        world.widgets.Methods[name] = world.widgets.Methods[name] or function() end
    end
    world.core.UF.Apply = function() return true end
    world.core.FinalizeLocale()
    env.MSUF_InitProfiles()
    if env.MSUF2 and env.MSUF2.ApplyService then env.MSUF2.ApplyService.Flush = function() return true end end
    return world, env, world.core
end
local function Named(world, name)
    for _, frame in ipairs(world.widgets.frames) do if frame.frameName == name then return frame end end
end
local function Element(id, state)
    return { id = id, label = id, getFrame = function() return {} end,
        captureState = function() return { x = state.x } end,
        restoreState = function(saved) state.x = saved.x return true end,
        movePosition = function() return true end }
end
local cases = {}
function cases.coordinates()
    local world, env = Boot("Mainline")
    local ui = env.UIParent
    ui:SetSize(1920, 1080)
    local frame = env.CreateFrame("Frame", nil, ui)
    frame:SetSize(100, 50)
    frame:SetPoint("CENTER", ui, "CENTER", -150, 0)
    Check(env.MSUF_EM2.QuickPopup.San(3000, 0) == 3000, "popup follow-up rejected a legal offset")
    local translate = env.MSUF_EM2.Util.TranslateFramePosition
    local cx, cy = env.MSUF_EM2.Util.FramePositionValues(frame)
    for _, value in ipairs({ "1e309", "-1e309", 0/0, "garbage" }) do
        local x, y, changed = translate(frame, -150, 0, value, value)
        Check(x == -150 and y == 0 and not changed, "non-finite/invalid coordinate was accepted: " .. tostring(value))
    end
    local x, y = translate(frame, -150, 0, "999999", "-999999")
    Check(x <= 4096 and x >= -4096 and y <= 4096 and y >= -4096, "huge input escaped nudge bounds")
    x, y = translate(frame, -150, 0, cx, cy)
    Check(x == -150 and y == 0, "unchanged rounded geometry drifted")
    frame:SetPoint("CENTER", ui, "CENTER", 5500, 0)
    local unchangedX, unchangedY = env.MSUF_EM2.Util.FramePositionValues(frame)
    x, y = translate(frame, 5500, 0, unchangedX, unchangedY)
    Check(x == 5500 and y == 0, "unchanged legacy out-of-range offset was clamped")
    local missing
    x, y, missing = translate(nil, 10, 20, 500, -500)
    Check(x == 10 and y == 20 and not missing, "a missing frame stopped ignoring typed coordinates")
    frame:SetScale(0.1)
    x, y = translate(frame, -150, 0, 4000, -4000)
    Check(math.abs(x) <= 4096 and math.abs(y) <= 4096, "scale conversion escaped saved offset bounds")
    local em, db = env.MSUF_EM2, env.MSUF_DB
    db.player.offsetX = 3000
    em.Popups.Open("player")
    local popup = assert(Named(world, "MSUF_EM2_UnitPopup"))
    Check(popup.xBox:GetText() == "3000", "unit popup did not show a legal 3000 offset")
    popup.wBox:SetText(tostring(db.player.width + 1))
    popup.wBox.scripts.OnEditFocusLost(popup.wBox)
    Check(db.player.offsetX == 3000, "unit width edit reset a legal 3000 offset")
    world.core.PublicGlobals.MSUF_EM2_ShowGFPopup("priority")
    local group = assert(Named(world, "MSUF_EM2_GFPopup_priority"))
    local conf = assert(world.core.GF.GetPriorityConf())
    conf.offsetX, conf.offsetY = 3000, 0
    group.Sync()
    Check(group.xBox:GetText() == "3000", "group popup follow-up rejected the accepted offset")
    group.wBox:SetText(tostring(conf.width + 1))
    group.Apply()
    Check(conf.offsetX == 3000, "group width edit reset the accepted offset")
end
local function PublicFixture()
    local env, entries = Environment(), {}
    env.geterrorhandler = function() return function(message) entries[#entries + 1] = message end end
    env.InCombatLockdown = function() return false end
    env.MSUF_EM2 = { Util = {}, Registry = {} }
    local registry = {}
    local R = env.MSUF_EM2.Registry
    R.Register = function(cfg) registry[cfg.key] = cfg end
    R.Get = function(key) return registry[key] end
    R.Unregister = function(key) registry[key] = nil end
    local ns = Namespace(env)
    Load(env, ns, "Kernel/MSUF_Boundary.lua")
    Load(env, ns, "Shell/EditMode/MSUF_EditMode_PublicAPI.lua")
    env.MSUF_EM2.State = { IsActive = function() return true end, GetProvider = function() return "msuf" end }
    env.MSUF_EM2.Undo = { BeginChange = function() return true end,
        CommitChange = function() end, CancelChange = function() end }
    return env, registry, entries
end
function cases.registry()
    local env, registry = PublicFixture()
    local api, ext = env.MSUF_EditModeAPI, env.MSUF_EM2.ExternalElements
    local player = { key = "player", label = "Player" }
    registry.player = player
    local malicious = Element("frame", { x = 0 })
    malicious.key, malicious.owner = "player", "MSUF.Core"
    Check(api.RegisterElement("Other", malicious) == false, "MSUF-owned key collision was accepted")
    Check(registry.player == player, "core Player entry was overwritten")
    malicious.key = "forged"
    Check(api.RegisterElement("Other", malicious) == true, "safe namespaced registration failed")
    local record = ext.GetRecord("external:other:frame")
    Check(record and record.owner == "Other" and record.key == "external:other:frame", "owner/key remained caller-controlled")
    Check(api.UnregisterOwner("Other") == true and registry.player == player, "unregistration removed a core entry")
    registry["external:other:frame"] = player
    Check(api.RegisterElement("Other", Element("frame", { x = 0 })) == false, "computed registry collision was accepted")
end
function cases.callbacks()
    local env, registry, reports = PublicFixture()
    local api, ext = env.MSUF_EditModeAPI, env.MSUF_EM2.ExternalElements
    local broken, fine = { x = 1 }, { x = 2 }
    local bad = Element("bad", broken)
    bad.captureState = function() error("capture failure") end
    assert(api.RegisterElement("Other", bad))
    assert(api.RegisterElement("Other", Element("fine", fine)))
    local heard = 0
    assert(api.RegisterSessionListener("Other.Listener", function() error("listener failure") end))
    assert(api.RegisterSessionListener("Healthy", function() heard = heard + 1 end))
    local ok, started = pcall(ext.BeginSession)
    Check(ok and started, "raising capture/listener blocked entry")
    fine.x = 44
    ok = pcall(ext.EndSession, "discard")
    Check(ok and fine.x == 2 and heard == 2, "raising callback blocked healthy discard/listener")
    bad.captureState = function() return { x = broken.x } end
    bad.restoreState = function() error("restore failure") end
    api.UnregisterOwner("Other")
    assert(api.RegisterElement("Other", bad))
    assert(api.RegisterElement("Other", Element("fine", fine)))
    assert(ext.BeginSession())
    fine.x = 55
    ok = pcall(ext.EndSession, "discard")
    Check(ok and fine.x == 2, "raising restore blocked another owner")
    fine.x = 90
    assert(ext.BeginSession())
    fine.x = 99
    ok = pcall(ext.EndSession, "discard")
    Check(ok and fine.x == 90, "discard left a stale entry snapshot")
    api.UnregisterOwner("Other")
    local noisy = Element("controls", { x = 0 })
    noisy.onSessionChanged = function() error("session failure") end
    noisy.extraControls = { { id = "value", label = "Value", kind = "number", min = 0, max = 10,
        get = function() error("getter failure") end, set = function() error("setter failure") end } }
    assert(api.RegisterElement("Other", noisy))
    ok = pcall(ext.BeginSession)
    Check(ok, "onSessionChanged blocked entry")
    local key = "external:other:controls"
    ok = pcall(ext.GetControlValue, key, "value")
    Check(ok, "control getter escaped the host boundary")
    local applied
    ok, applied = pcall(ext.ApplyControl, key, "value", 5)
    Check(ok and applied == false, "control setter escaped the boundary or reported success")
    noisy.movePosition = function()
        local captured = ext.CaptureState(key)
        assert(captured and captured.x == 0, "nested callback lost its subject")
        return false, "specific-rejection"
    end
    api.UnregisterOwner("Other")
    assert(api.RegisterElement("Other", noisy))
    local accepted, detail = ext.ApplyMove(key, { x = 0 }, 1, 0)
    Check(accepted == false and detail == "specific-rejection", "callback rejection detail was lost")
    Check(#reports >= 7, "isolated failures were not reported")
    ext.EndSession("save")
    api.UnregisterOwner("Other")
    local toggle = Element("toggle", { x = 0 })
    toggle.extraControls = { { id = "preview", kind = "toggle", label = "Preview",
        get = function() return false end, set = function() return true end } }
    assert(api.RegisterElement("Other", toggle))
    Check(ext.GetControlValue("external:other:toggle", "preview") == false, "false control value was lost")
    local world, real = Boot("Vanilla")
    local notified = 0
    real.MSUF_RegisterAnyEditModeListener(function() error("any-mode listener failure") end)
    real.MSUF_RegisterAnyEditModeListener(function() notified = notified + 1 end)
    real.geterrorhandler = function() return function() end end
    local stateError
    ok, stateError = pcall(real.MSUF_EM2.State.Enter, "player")
    if ok then world.widgets:RunTimers() end
    Check(ok and real.MSUF_EM2.State.IsActive() and notified == 1, "AnyEditMode callback blocked state entry: " .. tostring(stateError) .. "/" .. notified)
    ok, stateError = pcall(real.MSUF_EM2.State.Exit, "test")
    Check(ok and not real.MSUF_EM2.State.IsActive() and notified == 2, "AnyEditMode callback blocked teardown: " .. tostring(stateError) .. "/" .. notified)
end
local function LoginFixture(general, present)
    local fx = { env = Environment(), frames = {}, calls = { listener = 0, elements = 0 }, general = general }
    local env, frames, calls = fx.env, fx.frames, fx.calls
    env.MSUF_GetGeneralDB = function() return fx.general end
    env.CreateFrame = function()
        local f = { events = {}, RegisterEvent = function(s, e) s.events[e] = true end,
            UnregisterEvent = function(s, e) s.events[e] = nil end, SetScript = function(s, _, fn) s.onEvent = fn end }
        frames[#frames + 1] = f
        return f
    end
    env.hooksecurefunc = function() end
    function fx.Install()
        env.EllesmereUI = { RegisterUnlockElements = function() calls.elements = calls.elements + 1 end,
            UnregisterUnlockElement = function() end,
            RegisterUnlockModeListener = function() calls.listener = calls.listener + 1 end,
            UnregisterUnlockModeListener = function() calls.listener = calls.listener - 1 end,
            IsUnlockModeActive = function() return false end }
    end
    if present then fx.Install() end
    env.MSUF_EM2 = { Registry = { All = function() return {} end,
        RegisterChangeListener = function() end, UnregisterChangeListener = function() end } }
    local ns = Namespace(env)
    Load(env, ns, "Shell/EditMode/MSUF_EditMode_ExternalProvider.lua")
    local controller = env.MSUF_EM2.ExternalProviders.Controller
    controller.ClearMoveState = function() end
    controller.DetachAllProxies = function() end
    Load(env, ns, "Integrations/MSUF_Integration_EllesmereUnlock.lua")
    function fx.Fire(event, addon)
        for _, f in ipairs(frames) do if f.events[event] and f.onEvent then f.onEvent(f, event, addon) end end
    end
    function fx.Watching(event)
        for _, f in ipairs(frames) do if f.events[event] then return true end end
        return false
    end
    return fx
end
function cases.login()
    local fx = LoginFixture(nil, true)
    local env, calls = fx.env, fx.calls
    Check(calls.listener == 0, "Ellesmere registered before SavedVariables/profile bind")
    fx.general = { ellesmereEditModeIntegration = false }
    fx.Fire("PLAYER_LOGIN")
    fx.Fire("ADDON_LOADED", "EllesmereUI")
    Check(calls.listener == 0, "saved opt-out was ignored at login/late load")
    env.MSUF_EllesmereEditMode_SetEnabled(true)
    Check(fx.general.ellesmereEditModeIntegration and calls.listener == 1, "profile enable failed after opted-out login")
    env.MSUF_EllesmereEditMode_SetEnabled(false)
    Check(calls.listener == 0, "profile disable left the listener registered")
    env.EllesmereUI = nil
    env.MSUF_EllesmereEditMode_SetEnabled(true)
    fx.Install()
    fx.Fire("ADDON_LOADED", "EllesmereUI")
    Check(calls.listener == 1, "enabled late-loaded Ellesmere did not activate")
    -- A fresh profile has no saved choice and keeps the integration on, as it always did.
    for label, general in pairs({ ["no general table"] = false, ["general without the key"] = {} }) do
        local fresh = LoginFixture(nil, true)
        fresh.general = general or nil
        fresh.Fire("PLAYER_LOGIN")
        Check(fresh.calls.listener == 1, "fresh profile (" .. label .. ") did not enable the integration at login")
        Check(not fresh.Watching("ADDON_LOADED"), "activation at login left the late-load watcher registered (" .. label .. ")")
    end
    -- Ellesmere loads after login: activate once, then release the watcher.
    local late = LoginFixture({}, false)
    late.Fire("PLAYER_LOGIN")
    Check(late.calls.listener == 0 and late.Watching("ADDON_LOADED"), "absent Ellesmere did not wait for its load")
    late.Install()
    late.Fire("ADDON_LOADED", "SomeOtherAddon")
    Check(late.calls.listener == 0 and late.Watching("ADDON_LOADED"), "an unrelated addon load activated the integration")
    late.Fire("ADDON_LOADED", "EllesmereUI")
    Check(late.calls.listener == 1, "late-loaded Ellesmere did not activate")
    Check(not late.Watching("ADDON_LOADED"), "activation by the late load left the watcher registered")
end
function cases.escape()
    local world, env = Boot("Mainline")
    local quick = env.MSUF_EM2.QuickPopup
    local box, minus, plus = env.CreateFrame("EditBox"), env.CreateFrame("Button"), env.CreateFrame("Button")
    local focused, committed = true, 0
    box.ClearFocus = function(s)
        if not focused then return end
        focused = false
        s.scripts.OnEditFocusLost(s)
    end
    quick.WireStepper(minus, box, plus, function() committed = committed + 1 quick.SetBoxText(box, box:GetText()) end)
    quick.SetBoxText(box, "25")
    box:SetText("999")
    box.scripts.OnEscapePressed(box)
    Check(committed == 0 and box:GetText() == "25" and not focused, "Escape committed or retained half-typed text")
    focused = true
    box:SetText("30")
    box.scripts.OnEnterPressed(box)
    Check(committed == 1 and box:GetText() == "30", "Enter did not commit exactly once")
    box.scripts.OnEditFocusLost(box)
    Check(committed == 1, "unchanged blur committed again")
    -- Group popups fill their boxes through Sync; Escape must restore that text too.
    world.core.PublicGlobals.MSUF_EM2_ShowGFPopup("priority")
    local group = assert(Named(world, "MSUF_EM2_GFPopup_priority"))
    local conf = assert(world.core.GF.GetPriorityConf())
    conf.offsetX, conf.offsetY = 100, 0
    group.Sync()
    local xBox, wBox = group.xBox, group.wBox
    local xFocused = true
    xBox.ClearFocus = function(s)
        if not xFocused then return end
        xFocused = false
        s.scripts.OnEditFocusLost(s)
    end
    wBox.ClearFocus = function() end
    xBox:SetText("777")
    xBox.scripts.OnEscapePressed(xBox)
    Check(xBox:GetText() == "100" and conf.offsetX == 100, "group popup Escape kept the half-typed X text")
    wBox:SetText(tostring(conf.width + 1))
    wBox.scripts.OnEnterPressed(wBox)
    Check(xBox:GetText() == "100" and conf.offsetX == 100, "a later group width edit committed the discarded X text")
end
function cases.abort()
    local env, controller = Environment(), {}
    local commits, cancels, ends = 0, 0, 0
    env.MSUF_EM_UndoCommitChange = function() commits = commits + 1 end
    env.MSUF_EM2 = { ExternalProviders = { Controller = controller, Shared = {} },
        Undo = { CommitChange = env.MSUF_EM_UndoCommitChange, CancelChange = function() cancels = cancels + 1 end } }
    Load(env, Namespace(env), "Shell/EditMode/MSUF_EditMode_ExternalMovement.lua")
    local host = setmetatable({ bridgeUndoDepth = 0, externalMovers = {}, spec = {} }, { __index = controller })
    host.Field = function(_, field) return field end
    host.MoveChanged = function(_, binding) return binding.moved end
    host.DragAdapter = function() return { EndExternalDrag = function(_, final) Check(final == false, "abort finalized drag") ends = ends + 1 end } end
    local function Binding(moved, applied)
        return { externalKey = "player", externalDrag = {}, externalApplied = applied, historyChange = true, moved = moved }
    end
    host:ClearBindingMoveState(Binding(true, true))
    Check(commits == 1 and cancels == 0 and host.sessionDirty, "changed aborted drag lost its undo entry")
    host:ClearBindingMoveState(Binding(false, true))
    host:ClearBindingMoveState(Binding(true, false))
    Check(commits == 1 and cancels == 2 and ends == 3, "unchanged/rejected drag committed history")
end
function cases.movers()
    local world, env = Boot("Mainline")
    local em = env.MSUF_EM2
    local frame = env.CreateFrame("Frame", nil, env.UIParent)
    frame:SetSize(100, 30)
    frame:SetPoint("CENTER", env.UIParent, "CENTER", 0, 0)
    local enabled, reads = false, 0
    em.Registry.Register({ key = "disabled_probe", label = "Disabled probe", popupType = "unit",
        isEnabled = function() return enabled end, getFrame = function() reads = reads + 1 return frame end })
    em.Movers.Show()
    Check(reads == 0, "disabled registry element resolved its live frame")
    local mover = em.Movers.Get and em.Movers.Get("disabled_probe")
    Check(not mover or not mover:IsShown(), "disabled mover was shown")
    enabled = true
    em.Movers.SyncAll()
    Check(reads > 0, "re-enabled element was not resolved")
    enabled = false
    em.Movers.SyncAll()
    mover = em.Movers.Get("disabled_probe")
    Check(mover and not mover:IsShown(), "existing disabled mover stayed shown")
end
function cases.hud()
    local world, env = Boot("Mainline")
    local em, db = env.MSUF_EM2, env.MSUF_DB
    local function Motion()
        for _, frame in ipairs(world.widgets.frames) do
            if frame._label and frame._label:GetText() == "Motion" and frame:IsShown() then return frame end
        end
    end
    db.general.hideAdvancedMenu = true
    em.HUD.Show()
    Check(not Motion(), "Motion shown in simple mode")
    local slot = Named(world, "MSUF_EM2_HUD_PreviewAddonSlot")
    db.general.hideAdvancedMenu = false
    em.HUD.RefreshControls(true)
    local motion = Motion()
    Check(motion ~= nil, "Motion did not appear after enabling advanced mode")
    local count = #world.widgets.frames
    db.general.hideAdvancedMenu = true
    em.HUD.RefreshControls(true)
    Check(not Motion(), "Motion remained after returning to simple mode")
    em.HUD.Hide()
    db.general.hideAdvancedMenu = false
    em.HUD.Show()
    Check(Motion() ~= nil, "Motion missing on re-entry")
    Check(#world.widgets.frames == count, "mode toggling rebuilt and leaked widgets")
    if slot then Check(Named(world, "MSUF_EM2_HUD_PreviewAddonSlot") == slot, "preview addon slot changed identity") end
end
function cases.snapshot()
    for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
        for _, options in ipairs({ true, false }) do
            local world, env = Boot(flavor, options)
            local em, copies = env.MSUF_EM2, 0
            local dc = env.MSUF_DeepCopy
            env.MSUF_DeepCopy = function(value)
                if value == env.MSUF_DB then copies = copies + 1 end
                return dc(value)
            end
            local before = env.MSUF_DB.player.offsetX
            -- The entry listener writes after the snapshot exists, so Cancel All must undo that write.
            assert(env.MSUF_EditModeAPI.RegisterSessionListener("Entry.Probe", function(active)
                if active then env.MSUF_DB.player.offsetX = 111 end
            end))
            assert(em.State.Enter("player"))
            Check(env.MSUF_DB.player.offsetX == 111, flavor .. ": entry listener did not run (Options=" .. tostring(options) .. ")")
            Check(copies == 0, flavor .. ": redundant local profile copy beside core history (Options=" .. tostring(options) .. ")")
            env.MSUF_DB.player.offsetX = 333
            em.State.CancelAll()
            Check(env.MSUF_DB.player.offsetX == before, flavor .. ": Cancel All failed (Options=" .. tostring(options) .. ")")
        end
    end
end
function cases.danders()
    local env, elements = Environment(), {}
    local raidUnlocks, raidLocks, partyUnlocks = 0, 0, 0
    local db = {}
    env.LibStub = nil
    env.InCombatLockdown = function() return false end
    env.MSUF_GetGeneralDB = function() return {} end
    env.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    env.DandersFrames = { GetDB = function() return db end, GetRaidDB = function() return db end,
        UpdateContainerPosition = function() end, UpdateRaidContainerPosition = function() end,
        raidMoverFrame = { IsShown = function() return true end },
        UnlockRaidFrames = function() raidUnlocks = raidUnlocks + 1 end,
        LockRaidFrames = function() raidLocks = raidLocks + 1 end }
    env.MSUF_EditModeAPI = { RegisterElement = function() return true end, RegisterSessionListener = function() end,
        RefreshOwner = function() end, UnregisterOwner = function() end }
    env.MSUF_EM2 = { ExternalProviders = {
        CreateElementRegistrar = function() return function(el) elements[el.id] = el return true end end,
        CreateEnabledSetter = function(_, _, activate, deactivate) return function(on)
            if on then return activate() else return deactivate() end
        end end,
        ActivateAtLogin = function(_, activate) activate() end } }
    Load(env, Namespace(env), "Shell/EditMode/MSUF_EditMode_Danders.lua")
    elements.party.onSelect()
    env.DandersFrames.UnlockFrames = function() partyUnlocks = partyUnlocks + 1 env.DandersFrames.moverFrame = { IsShown = function() return true end } end
    elements.party.onSelect()
    Check(partyUnlocks == 1, "missing party mover fell through to an active raid mover")
    env.MSUF_DandersEditMode_SetEnabled(false)
    Check(raidLocks == 0, "party scope fell through to raid mover and stole its unlock")
    env.DandersFrames.moverFrame = nil
    env.DandersFrames.UnlockFrames = nil
    env.DandersFrames.raidMoverFrame = { IsShown = function() return false end }
    elements.party.onSelect()
    Check(raidUnlocks == 0, "missing party unlock fell through to raid unlock")
end
assert(cases[mode], "unknown case: " .. mode)()
if #failures > 0 then error(mode .. ":\n  " .. table.concat(failures, "\n  ")) end
print("editmode_input_and_session_integrity_smoke: " .. mode .. " ok")
