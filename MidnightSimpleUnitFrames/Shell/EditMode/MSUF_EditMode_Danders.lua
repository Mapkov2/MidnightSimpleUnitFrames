--- DandersFrames adapter for MSUF Edit Mode. DandersFrames keeps ownership of
--- every container and saved position; all anchors are screen-space pixels
--- relative to UIParent CENTER, so mover deltas apply without scale math.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local API = _G.MSUF_EditModeAPI
if not (API and API.RegisterElement) then return end

local OWNER, SETTING = "MSUF.DandersFrames", "dandersEditModeIntegration"
local registered = {}
local active, unlockedScope = false, nil
local sessionMover
local positionIdentities, nextPositionIdentity = setmetatable({}, { __mode = "k" }), 0
local function Identity(value)
    if type(value) ~= "table" then return 0 end
    local id = positionIdentities[value]
    if not id then
        nextPositionIdentity = nextPositionIdentity + 1
        id = nextPositionIdentity
        positionIdentities[value] = id
    end
    return id
end
local function PositionRoute(df, mode, db)
    local ap = mode == "raid" and df.AutoProfilesUI
    -- Native SetPositionRecord routes to this exact active/editing destination.
    -- Numeric identities survive MSUF's copied undo snapshots without copying
    -- another addon's profile table or confusing two equally named layouts.
    local destination = ap and ((ap.IsEditing and ap:IsEditing()) and ap.editingProfile or ap.activeRuntimeProfile)
    return Identity(db) .. ":" .. Identity(destination)
end
local function CopyAnchor(anchor)
    if type(anchor) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(anchor) do copy[key] = value end
    return copy
end
local function MoverLocked()
    unlockedScope = nil
end
local function SessionMover()
    local libStub = _G.LibStub
    local lib = libStub and libStub("DandersMover-1.0", true)
    -- LibStub's versioned library contract owns these method types.
    if not (lib and lib.IsUnlocked and lib.Lock and lib.RegisterCallback) then return nil end
    if sessionMover ~= lib then
        if sessionMover and sessionMover.UnregisterCallback then sessionMover.UnregisterCallback(OWNER, "Locked") end
        sessionMover = lib
        lib.RegisterCallback(OWNER, "Locked", MoverLocked)
    end
    return lib
end

local Export = MSUF.ExportPublic

local General = _G.MSUF_GetGeneralDB
local InCombatLockdown = _G.InCombatLockdown

local function Enabled()
    local general = General()
    return not general or general[SETTING] ~= false
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

local function Danders()
    local df = _G.DandersFrames
    if type(df) ~= "table" or type(df.GetDB) ~= "function" or type(df.GetRaidDB) ~= "function"
        or type(df.UpdateContainerPosition) ~= "function"
        or type(df.UpdateRaidContainerPosition) ~= "function" then return nil end
    return df
end

local function Visible(frame)
    if type(frame) == "table" and frame.IsVisible and frame:IsVisible() == true then return frame end
    return nil
end

--- Native position records preserve point/anchor metadata and active-layout
--- routing. Flat fields are only the compatibility path for older versions.
local MODES = {
    party = {
        db = function(df) return df:GetDB() end,
        xField = "anchorX", yField = "anchorY",
        apply = function(df) df:UpdateContainerPosition() end,
        frame = function(df) return Visible(df.container) or Visible(df.testPartyContainer) or df.container end,
    },
    raid = {
        db = function(df) return df:GetRaidDB() end,
        xField = "raidAnchorX", yField = "raidAnchorY",
        apply = function(df) df:UpdateRaidContainerPosition() end,
        frame = function(df) return Visible(df.raidContainer) or Visible(df.testRaidContainer) or df.raidContainer end,
    },
}

local function ModeDB(mode)
    local df = Danders()
    local db = df and MODES[mode].db(df)
    if type(db) ~= "table" then return nil end
    return db, df
end

local function ModeFrame(mode)
    local df = Danders()
    return df and MODES[mode].frame(df) or nil
end

local function CaptureMode(mode)
    local db, df = ModeDB(mode)
    if not db then return nil end
    local native = df.GetPositionRecord ~= nil and df.SetPositionRecord ~= nil
    local record = native and df:GetPositionRecord(mode) or nil
    local spec = MODES[mode]
    local frame = ModeFrame(mode)
    return {
        x = tonumber(record and record.x or db[spec.xField]) or 0,
        y = tonumber(record and record.y or db[spec.yField]) or 0,
        point = record and record.point or "CENTER", anchor = record and CopyAnchor(record.anchor),
        route = PositionRoute(df, mode, db), native = native,
        scale = tonumber(db.frameScale),
        width = frame and frame.GetWidth and frame:GetWidth() or nil,
        height = frame and frame.GetHeight and frame:GetHeight() or nil,
    }
end

local function RestoreMode(mode, state)
    local db, df = ModeDB(mode)
    if InCombat() or not db or type(state) ~= "table" then return false end
    local x, y = tonumber(state.x), tonumber(state.y)
    if not x or not y then return false end
    if state.route and state.route ~= PositionRoute(df, mode, db) then return false end
    local spec = MODES[mode]
    local scale = tonumber(state.scale)
    local scaleChanged = scale ~= nil and scale ~= tonumber(db.frameScale)
    if scale ~= nil then db.frameScale = scale end
    local native = df.GetPositionRecord ~= nil and df.SetPositionRecord ~= nil
    if native then
        df:SetPositionRecord(mode, { point = state.point, x = x, y = y, anchor = CopyAnchor(state.anchor) }, "MSUF_EDIT_MODE")
    else
        db[spec.xField], db[spec.yField] = x, y
    end
    local ap = native and mode == "raid" and df.AutoProfilesUI
    local routed = ap and ap.IsLayoutActive and ap:IsLayoutActive()
        and not (ap.IsEditing and ap:IsEditing()) and ap.SetActiveLayoutRaidPosition
    if not routed then spec.apply(df) end
    if scaleChanged and type(df.UpdateAllFrames) == "function" then df:UpdateAllFrames() end
    return true
end

--- Frame Scale in the popup: the value lives in the scope's own db
--- (DandersFrames' Options slider writes the same frameScale field,
--- 0.5–2.0) and applies through the addon's own updaters.
local function ScaleControl(mode)
    return {
        id = mode .. "_scale", kind = "number", label = "Scale",
        min = 50, max = 200, step = 5,
        get = function()
            local db = ModeDB(mode)
            if not db then return nil end
            return math.floor(((tonumber(db.frameScale) or 1) * 100) + 0.5)
        end,
        set = function(value)
            local db, df = ModeDB(mode)
            value = tonumber(value)
            if InCombat() or not (db and df and value) then return false end
            db.frameScale = value / 100
            MODES[mode].apply(df)
            if type(df.UpdateAllFrames) == "function" then df:UpdateAllFrames() end
            return true
        end,
    }
end

--- Pinned frame sets. Sets glued to the party/raid container via
--- position.anchorTo (FRAMES_*) follow it natively and must not get their own
--- mover; nil/SCREEN means free screen placement.
local function Pinned()
    local df = Danders()
    local pf = df and df.PinnedFrames
    if type(pf) ~= "table" or type(pf.GetSetForPosition) ~= "function"
        or type(pf.ApplySetPosition) ~= "function" then return nil end
    return pf
end

local function PinnedSet(index)
    local pf = Pinned()
    local set = pf and pf:GetSetForPosition(index)
    if type(set) ~= "table" or set.enabled ~= true then return nil end
    local anchorTo = type(set.position) == "table" and set.position.anchorTo or nil
    if anchorTo ~= nil and anchorTo ~= "SCREEN" then return nil end
    return set, pf
end

local function PinnedFrame(index)
    local pf = Pinned()
    if not pf then return nil end
    local live = type(pf.containers) == "table" and pf.containers[index] or nil
    local test = type(pf.testContainers) == "table" and pf.testContainers[index] or nil
    if pf.testModeActive then return test or live end
    return Visible(live) or Visible(test) or live
end

local function CapturePinned(index)
    local set = PinnedSet(index)
    if not set then return nil end
    local pos = type(set.position) == "table" and set.position or nil
    local frame = PinnedFrame(index)
    return {
        point = pos and type(pos.point) == "string" and pos.point or "CENTER",
        x = pos and tonumber(pos.x) or 0, y = pos and tonumber(pos.y) or 0,
        width = frame and frame.GetWidth and frame:GetWidth() or nil,
        height = frame and frame.GetHeight and frame:GetHeight() or nil,
    }
end

local function RestorePinned(index, state)
    local set, pf = PinnedSet(index)
    if InCombat() or not set or type(state) ~= "table" then return false end
    local x, y = tonumber(state.x), tonumber(state.y)
    if not x or not y then return false end
    if type(set.position) ~= "table" then set.position = {} end
    local pos = set.position
    if type(state.point) == "string" then pos.point = state.point end
    pos.x, pos.y = x, y
    pf:ApplySetPosition(index)
    return true
end

--- Anchors are stored in UIParent pixels, exactly the space mover deltas
--- arrive in, so moving is snapshot + delta with no scale conversion.
local function Move(restore, request)
    local state = request and request.state
    if type(state) ~= "table" then return false end
    return restore({
        point = state.point, anchor = state.anchor, route = state.route, native = state.native,
        x = (tonumber(state.x) or 0) + (tonumber(request.deltaX) or 0),
        y = (tonumber(state.y) or 0) + (tonumber(request.deltaY) or 0),
    })
end

local function OpenSettings()
    local df = Danders()
    if df and type(df.ToggleGUI) == "function" then
        df:ToggleGUI()
        return true
    end
    return false
end

--- Selecting an element starts DandersFrames' OWN unlock for that scope: the
--- full native machinery (test-frame preview, drag overlay, grid, position
--- panel) rather than a bare test-mode claim, which field-testing showed is
--- not enough to actually move the preview. Exactly one scope is unlocked at
--- a time (their unlocks share the position panel and the mutually exclusive
--- test modes), the selection moves it, and every exit path locks it again.
--- An unlock the user started themselves is never taken over or locked.
--- "Is an unlock session actually running right now?" must be read from the
--- live mover overlay (Unlock* shows it, Lock* hides it). The db locked flags
--- are NOT usable: a reload during an unlock session leaves `locked = false`
--- in the SavedVariables forever, which would silently veto every unlock.
local function ScopeUnlocked(df, scope)
    local session = SessionMover()
    if session then return session:IsUnlocked() == true end
    local mover = scope == "party" and df.moverFrame or df.raidMoverFrame
    return type(mover) == "table" and mover.IsShown and mover:IsShown() == true
end

local function ReleaseUnlock()
    local df = unlockedScope and Danders()
    local scope = unlockedScope
    unlockedScope = nil
    if not df then return end
    local session = SessionMover()
    if session then
        if session:IsUnlocked() then session:Lock() end
        return
    end
    if scope == "party" then
        if type(df.LockFrames) == "function" and ScopeUnlocked(df, "party") then df:LockFrames() end
    elseif type(df.LockRaidFrames) == "function" and ScopeUnlocked(df, "raid") then
        df:LockRaidFrames()
    end
end

--- The unlock's drag overlay and its test frames can disagree — the shim in
--- DandersFrames documents that Show* may refuse while the claim stands and
--- expects "the next reconcile" to repair it. One idempotent reconcile after
--- every unlock (and on reselecting an already unlocked scope) makes sure the
--- overlay never sits on an empty shell.
local function EnsurePreview(df, scope)
    if type(df.IsTestModeActive) == "function" and type(df.ReconcileTestMode) == "function"
        and not df:IsTestModeActive(scope) then
        df:ReconcileTestMode(scope, true)
    end
end

local function UnlockScope(scope)
    local df = Danders()
    if not df then return end
    --- The cached scope goes stale whenever DandersFrames ends the session
    --- itself (their Lock button, /df lock): trust only the live overlay, or
    --- re-selecting that element would silently skip the unlock.
    if unlockedScope and not ScopeUnlocked(df, unlockedScope) then unlockedScope = nil end
    if unlockedScope == scope then
        EnsurePreview(df, scope)
        return
    end
    ReleaseUnlock()
    if not scope or InCombat() then return end
    if ScopeUnlocked(df, scope) then
        if not SessionMover() then EnsurePreview(df, scope) end
        return
    end
    local unlock = scope == "party" and df.UnlockFrames or df.UnlockRaidFrames
    if type(unlock) ~= "function" then return end
    unlock(df)
    if ScopeUnlocked(df, scope) then
        unlockedScope = scope
        EnsurePreview(df, scope)
    end
    if API.RefreshOwner then API.RefreshOwner(OWNER) end
end

local function PinnedScope()
    return type(_G.IsInRaid) == "function" and _G.IsInRaid() and "raid" or "party"
end

local function SelectMode(mode)
    UnlockScope(mode)
    return true
end

local function SelectPinned(_)
    UnlockScope(PinnedScope())
    return true
end

--- The HUD's settings picker (the inspector chip) reaches externals ONLY
--- through openSettings — it never fires onSelect. That selection-adjacent
--- route ("focus-full-settings") brings up the scope preview WITHOUT opening
--- the DandersFrames GUI; only the popup's explicit Open settings button
--- toggles the GUI on top.
local function OpenScopeSettings(scope, context)
    UnlockScope(scope)
    if type(context) == "table" and context.source == "focus-full-settings" then return true end
    return OpenSettings()
end

--- Popup preview toggles: pick which scope preview is on screen straight from
--- the popup. Transient view state — no undo entries — and turning one off
--- only ends an MSUF-owned unlock, never a session the user started.
local function PreviewToggle(scope, label)
    return {
        id = scope .. "_preview", kind = "toggle", label = label, transient = true,
        get = function()
            local df = Danders()
            return df ~= nil and type(df.IsTestModeActive) == "function"
                and df:IsTestModeActive(scope) == true
        end,
        set = function(value)
            local df = Danders()
            if not df then return false end
            if value then
                UnlockScope(scope)
                return type(df.IsTestModeActive) ~= "function" or df:IsTestModeActive(scope) == true
            end
            if unlockedScope == scope then
                ReleaseUnlock()
                return true
            end
            return false
        end,
    }
end

local function PreviewControls()
    return {
        PreviewToggle("party", "Show party preview"),
        PreviewToggle("raid", "Show raid preview"),
    }
end

local function Element(id, label, order, resolveFrame, isReady, capture, restore, select, settings, controls)
    return {
        id = id, label = label, group = "DandersFrames", order = order,
        getFrame = resolveFrame,
        isEnabled = function() return active and Enabled() and isReady() end,
        captureState = capture,
        restoreState = function(state) return restore(state) end,
        movePosition = function(request) return Move(restore, request) end,
        openSettings = settings,
        onSelect = select,
        extraControls = controls or PreviewControls(),
    }
end

local function ModeControls(mode)
    local controls = PreviewControls()
    controls[#controls + 1] = ScaleControl(mode)
    return controls
end

local Add = _G.MSUF_EM2.ExternalProviders.CreateElementRegistrar(API, OWNER, registered)

--- Never unlock at session start: entering the session must stay free (no
--- companion load, no frame pool, no animation ticker) and live frames must
--- stay live. The unlock appears on demand through onSelect above.
local function SessionChanged(enabled)
    if not enabled then ReleaseUnlock() end
end

local function Activate()
    if active or not Enabled() then return false end
    if not Danders() then return false end
    active = true
    SessionMover()
    if not Add(Element("party", "Danders Party Frames", 830,
        function() return ModeFrame("party") end,
        function() return ModeDB("party") ~= nil end,
        function() return CaptureMode("party") end,
        function(state) return RestoreMode("party", state) end,
        function() return SelectMode("party") end,
        function(_, context) return OpenScopeSettings("party", context) end,
        ModeControls("party"))) then
        active = false
        return false
    end
    Add(Element("raid", "Danders Raid Frames", 831,
        function() return ModeFrame("raid") end,
        function() return ModeDB("raid") ~= nil end,
        function() return CaptureMode("raid") end,
        function(state) return RestoreMode("raid", state) end,
        function() return SelectMode("raid") end,
        function(_, context) return OpenScopeSettings("raid", context) end,
        ModeControls("raid")))
    for index = 1, 4 do
        Add(Element(("pinned_%d"):format(index), ("Danders Pinned Set %d"):format(index), 832 + index,
            function() return PinnedFrame(index) end,
            function() return PinnedSet(index) ~= nil end,
            function() return CapturePinned(index) end,
            function(state) return RestorePinned(index, state) end,
            function() return SelectPinned(index) end,
            function(_, context) return OpenScopeSettings(PinnedScope(), context) end))
    end
    API.RegisterSessionListener(OWNER, SessionChanged)
    if API.RefreshOwner then API.RefreshOwner(OWNER) end
    return true
end

local function Deactivate()
    if not active then return false end
    ReleaseUnlock()
    active = false
    if next(registered) then API.UnregisterOwner(OWNER) end
    for id in pairs(registered) do registered[id] = nil end
    return true
end

local External = _G.MSUF_EM2.ExternalProviders
local SetEnabled = External.CreateEnabledSetter(General, SETTING, Activate, Deactivate)

Export("MSUF_DandersEditMode_IsAvailable", function() return Danders() ~= nil end)
Export("MSUF_DandersEditMode_SetEnabled", SetEnabled)

local eventFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if eventFrame then
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:SetScript("OnEvent", function(_, event, addon)
        if event == "PLAYER_REGEN_DISABLED" then
            --- Combat edge, still pre-lockdown: lock the MSUF-owned unlock so
            --- no preview engine or animation ticker survives into combat.
            --- A no-op when nothing is claimed; a user unlock stays theirs.
            ReleaseUnlock()
        elseif addon == "DandersFrames" and Enabled() then
            Activate()
        end
    end)
end

External.ActivateAtLogin(Enabled, Activate)
