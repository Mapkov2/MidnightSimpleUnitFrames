-- Review F12: the public Edit Mode API session stays consistent when an owner
-- callback raises. The host boundary reports the error and continues:
--   * a raising capture leaves that element out of the entry snapshot while
--     healthy elements still capture and restore; the next session retries it;
--   * MSUF's own session listeners (owner "MSUF.*", e.g. the Blizzard adapter's
--     tooltip container and layout snapshot) are notified before any other
--     addon's callback, so a raising third-party callback cannot skip them.
-- Real MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_PublicAPI.lua.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local registry = {}
_G.MSUF_EM2 = {
    Util = {},
    Registry = {
        Register = function(cfg) registry[cfg.key] = cfg end,
        Unregister = function(key) registry[key] = nil end,
        Get = function(key) return registry[key] end,
    },
}
local reports = {}
_G.geterrorhandler = function() return function(message) reports[#reports + 1] = message end end
local ns = {
    ExportPublic = function(name, value) _G[name] = value; return value end,
    ReportError = function() end,
}
assert(loadfile(root .. "/tools/tests/editmode_prerequisites.lua"))().Install(root, ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MidnightSimpleUnitFrames", ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_PublicAPI.lua"))("MidnightSimpleUnitFrames", ns)
local API, External = assert(_G.MSUF_EditModeAPI), assert(_G.MSUF_EM2.ExternalElements)

local function Element(id, state, opts)
    opts = opts or {}
    return {
        id = id, label = id,
        getFrame = function() return {} end,
        captureState = function()
            if opts.raiseCapture and opts.raiseCapture() then error("capture failed: " .. id) end
            return { x = state.x, y = state.y }
        end,
        restoreState = function(saved) state.x, state.y = saved.x, saved.y; return true end,
        movePosition = function() return true end,
        onSessionChanged = opts.onSessionChanged,
    }
end

-- A capture that raises once while the session starts.
local brokenState, fineState = { x = 1, y = 1 }, { x = 2, y = 2 }
local raiseOnce = true
assert(API.RegisterElement("Third.Party", Element("broken", brokenState, {
    raiseCapture = function() local raise = raiseOnce; raiseOnce = false; return raise end,
})))
assert(API.RegisterElement("Third.Party", Element("fine", fineState)))
local started = pcall(External.BeginSession)
Check(started and #reports == 1, "the raising capture was not isolated and reported")
fineState.x = 60
Check(External.EndSession("discard") == true and fineState.x == 2, "healthy snapshot did not restore after a capture failure")
Check(External.BeginSession() == true, "the next session did not retry the raising capture")
brokenState.x, fineState.x = 50, 60
Check(External.EndSession("discard") == true, "discard did not end the session")
Check(brokenState.x == 1 and fineState.x == 2, "discard after a raising capture restored only part of the elements ("
    .. brokenState.x .. ", " .. fineState.x .. ")")
API.UnregisterOwner("Third.Party")

-- A third-party session callback that raises.
local msufHeard = {}
assert(API.RegisterSessionListener("MSUF.Blizzard", function(enabled, reason) msufHeard[#msufHeard + 1] = { enabled, reason } end))
assert(API.RegisterElement("Third.Party", Element("noisy", { x = 0, y = 0 }, {
    onSessionChanged = function(enabled) if not enabled then error("third-party session callback failed") end end,
})))
Check(External.BeginSession() == true, "the session did not start")
local ended = pcall(External.EndSession, "save")
Check(ended and #reports == 2, "the raising third-party callback was not isolated and reported")
local last = msufHeard[#msufHeard]
Check(last and last[1] == false and last[2] == "save",
    "a raising third-party session callback kept MSUF's own adapter from hearing the session end")
Check(External.BeginSession() == true, "a new session did not start after the raising session end")

if #failures > 0 then
    error("editmode_public_api_session_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_public_api_session_smoke: ok (isolated callback failures, own listeners first)")

-- Exercise the full popup position transaction with the native core and providers.
do
-- Real popup widgets, drag strategies, provider saves and core history.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = dofile(root .. "/tools/tests/client_world.lua")
local w = World.New(root, flavor)
local env, ns = w.env, w.core
local checks = 0
local function Check(ok, message) assert(ok, message); checks = checks + 1 end
local function Near(a, b, message) Check(type(a) == "number" and math.abs(a - b) < .001,
    message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
env.GetCursorPosition = function() return 600, 400 end
env.IsShiftKeyDown = function() return false end
env.IsControlKeyDown = function() return false end
env.IsAltKeyDown = function() return false end
env.UIParent:SetSize(1920, 1080)
env.UIParent.left, env.UIParent.bottom = 0, 0
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetAutoFocus", "SetNumeric",
    "SetMaxLetters", "SetCursorPosition", "HighlightText", "SetTextInsets", "ClearFocus" }) do
    w.widgets.Methods[name] = function() end
end
w.widgets.Methods.HasFocus = function() return false end
local widgetSetPoint = w.widgets.Methods.SetPoint
function w.widgets.Methods:SetPoint(point, relative, relativePoint, x, y)
    widgetSetPoint(self, point, relative, relativePoint, x, y)
    if self._barKey and self._barKey:sub(1, 9) == "external:" and point == "TOPLEFT" then
        Check(relative == env.UIParent and relativePoint == "TOPLEFT", "mover anchor changed")
        self.left, self.bottom = x, 1080 + y - self:GetHeight()
    end
end
-- The shared widget kit records anchors. These external fixtures also solve
-- CENTER anchors so assertions observe the provider's real visual writes.
local function Target(scale, width, height)
    local f = env.CreateFrame("Frame", nil, env.UIParent)
    f:SetSize(width or 100, height or 50)
    f:SetScale(scale or 1)
    local setPoint = f.SetPoint
    function f:SetPoint(point, relative, relativePoint, x, y)
        setPoint(self, point, relative, relativePoint, x, y)
        Check(point == "CENTER" and relativePoint == "CENTER", "fixture anchor changed")
        local ratio = self:GetEffectiveScale() / env.UIParent:GetEffectiveScale()
        self.left = 960 / ratio + x - self:GetWidth() / 2
        self.bottom = 540 / ratio + y - self:GetHeight() / 2
    end
    f:SetPoint("CENTER", env.UIParent, "CENTER", -300, -100)
    return f
end
local suite = Target(1.25, 96, 48)
local saved, moves = { x = -300, y = -100, width = 96, height = 48 }, {}
local rejectCommit = false
local dominos = Target(.8)
dominos.sets = { point = "CENTER", relPoint = "CENTER", x = -300, y = -100 }
function dominos:GetSavedPosition() return self.sets.point, self.sets.relPoint, self.sets.x, self.sets.y end
function dominos:SavePosition(point, relativePoint, x, y)
    self.sets.point, self.sets.relPoint, self.sets.x, self.sets.y = point, relativePoint, x, y
end
function dominos:RestorePosition()
    self:SetPoint(self.sets.point, env.UIParent, self.sets.relPoint, self.sets.x, self.sets.y)
    return true
end
env.Dominos = { RegisterCallback = function() end, UnregisterCallback = function() end,
    Frame = { Get = function() return dominos end, GetAll = function() return pairs({ [1] = dominos }) end } }
local blizzard = Target()
local layouts = { activeLayout = 3, layouts = { { layoutName = "Test", layoutType = 1, systems = {
    { system = 2, systemIndex = 1, anchorInfo = { point = "CENTER", relativeTo = "UIParent",
        relativePoint = "CENTER", offsetX = -300, offsetY = -100 }, settings = {} },
} } } }
local saves = 0
-- Unknown namespaces are read-only stubs in the full-graph harness.
-- Supply real enum tables so system IDs cannot collapse onto one stub key.
env.Enum = setmetatable({
    EditModeSystem = { Minimap = 2, ChatFrame = 8, HudTooltip = 11, MicroMenu = 13, Bags = 14, DamageMeter = 23 },
    EditModePresetLayoutsMeta = { NumValues = 2 },
}, { __index = env.Enum })
env.MinimapCluster = blizzard
env.C_EditMode = { GetLayouts = function() return layouts end,
    SaveLayouts = function(info) layouts = info; saves = saves + 1 end }
local suffix = w.client.tocSuffix or flavor
w:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root, World.CoreTOC(suffix), "enUS",
    w.client.isForever and "camelot" or nil), ns)
local failure = w:FirstFailure()
Check(not failure, "core load failed: " .. tostring(failure and failure.message))
env.MSUF_InitProfiles()
local em, api = env.MSUF_EM2, env.MSUF_EditModeAPI
local function Restore(state)
    state = state.values
    saved.x, saved.y, saved.width, saved.height = state.x, state.y, state.width, state.height
    suite:SetSize(saved.width, saved.height)
    suite:SetPoint("CENTER", env.UIParent, "CENTER", saved.x, saved.y)
    return true
end
Check(api.RegisterElement("Test.Suite", {
    id = "overlay", label = "Suite-like overlay", getFrame = function() return suite end,
    captureState = function() return { epoch = 1,
        values = { x = saved.x, y = saved.y, width = saved.width, height = saved.height } } end,
    restoreState = Restore,
    movePosition = function(request)
        Check((suite._msufDragActive == true) == (request.phase == "preview"), "drag flags differ from release path")
        moves[#moves + 1] = request.phase
        local x = request.state.values.x + request.deltaX / 1.25
        local y = request.state.values.y + request.deltaY / 1.25
        suite:SetPoint("CENTER", env.UIParent, "CENTER", x, y)
        if request.phase == "commit" and rejectCommit then return false end
        if request.phase == "commit" then saved.x, saved.y = x, y end
        return true
    end,
    extraControls = {
        { id = "width", label = "Width", kind = "number", min = 20, max = 300,
            get = function() return saved.width end, set = function(v) saved.width = v; suite:SetWidth(v); return true end },
        { id = "height", label = "Height", kind = "number", min = 20, max = 100,
            get = function() return saved.height end, set = function(v) saved.height = v; suite:SetHeight(v); return true end },
    },
}), "Suite-like registration refused")
env.MSUF_DominosEditMode_SetEnabled(true)
env.MSUF_BlizzardEditMode_SetEnabled(true)
Check(em.State.Enter("player"), "session refused")
w.widgets:RunTimers(1000)
Check(api.IsActive(), "public session did not become active")
local cases = {
    { key = "external:test.suite:overlay", frame = suite, state = function() return saved.x, saved.y end, scale = 1.25 },
    { key = "external:msuf.dominos:bar_1", frame = dominos,
        state = function() return dominos.sets.x, dominos.sets.y end, scale = .8 },
    { key = "external:msuf.blizzard:minimap", frame = blizzard, state = function()
        local a = layouts.layouts[1].systems[1].anchorInfo; return a.offsetX, a.offsetY end, scale = 1 },
}
local popup
local function Enter(box, value)
    box:SetText(tostring(value))
    assert(box:GetScript("OnEnterPressed"))(box)
end
for _, case in ipairs(cases) do
    Check(em.ExternalPopup.Open(case.key), "popup refused: " .. case.key)
    for _, frame in ipairs(w.widgets.frames) do
        if frame.frameName == "MSUF_EM2_ExternalPopup" then popup = frame end
    end
    Check(popup and popup.xBox and popup.yBox, "external popup lacks editable X/Y: " .. case.key)
    Check(em.ExternalElements.GetPositionFrame(case.key) == case.frame, "position geometry unavailable: " .. case.key)
    local beforeX, beforeY = case.state()
    local oldVisualX, oldVisualY = em.Util.FramePositionValues(case.frame)
    local beforeCount = ns.History.GetHistoryState().undoCount
    Enter(popup.xBox, oldVisualX - 40)
    local afterX, afterY = case.state()
    Near(afterX, beforeX - 40 / case.scale, "X provider save")
    Near(afterY, beforeY, "X changed Y")
    Near(em.Util.FramePositionValues(case.frame), oldVisualX - 40, "X visual position")
    Check(ns.History.GetHistoryState().undoCount == beforeCount + 1, "X history count")
    Check(ns.History.historyUndo[#ns.History.historyUndo].label:find("Move", 1, true), "position history is not Move")
    Check(em.Undo.DoUndo(), "X undo refused")
    Near(case.state(), beforeX, "X undo save")
    Near(em.Util.FramePositionValues(case.frame), oldVisualX, "X undo visual")
    Near(tonumber(popup.xBox:GetText()), oldVisualX, "X undo popup refresh")
    Check(em.Undo.DoRedo(), "X redo refused")
    Near(case.state(), afterX, "X redo save")
    Near(em.Util.FramePositionValues(case.frame), oldVisualX - 40, "X redo visual")
    Near(tonumber(popup.xBox:GetText()), oldVisualX - 40, "X redo popup refresh")
    em.ExternalPopup.Sync()
    Enter(popup.yBox, oldVisualY + 30)
    local x, y = case.state()
    Near(x, afterX, "Y changed X")
    Near(y, beforeY + 30 / case.scale, "Y provider save")
    local _, visualY = em.Util.FramePositionValues(case.frame)
    Near(visualY, oldVisualY + 30, "Y visual position")
    Check(em.Undo.DoUndo(), "Y undo refused")
    local _, undoY = case.state(); Near(undoY, beforeY, "Y undo save")
    local _, undoVisualY = em.Util.FramePositionValues(case.frame); Near(undoVisualY, oldVisualY, "Y undo visual")
    Near(tonumber(popup.yBox:GetText()), oldVisualY, "Y undo popup refresh")
    Check(em.Undo.DoRedo(), "Y redo refused")
    local _, redoY = case.state(); Near(redoY, y, "Y redo save")
    local _, redoVisualY = em.Util.FramePositionValues(case.frame); Near(redoVisualY, visualY, "Y redo visual")
    Near(tonumber(popup.yBox:GetText()), visualY, "Y redo popup refresh")
    local count = ns.History.GetHistoryState().undoCount
    em.ExternalPopup.Sync()
    Enter(popup.yBox, popup.yBox:GetText())
    Check(ns.History.GetHistoryState().undoCount == count, "unchanged rounded value created history")
    env.InCombatLockdown = function() return true end
    Enter(popup.xBox, 999)
    Near(case.state(), x, "combat changed saved X")
    Check(ns.History.GetHistoryState().undoCount == count, "combat changed history")
    env.InCombatLockdown = function() return false end
    Check(env.MSUF_IsConfigCombatLocked("PLAYER_REGEN_DISABLED"), "combat edge did not lock configuration")
    Enter(popup.yBox, 999)
    local _, combatY = case.state(); Near(combatY, y, "combat entry changed saved Y")
    Check(ns.History.GetHistoryState().undoCount == count, "combat entry changed history")
    Check(not env.MSUF_IsConfigCombatLocked("PLAYER_REGEN_ENABLED"), "combat edge did not unlock configuration")
    em.ExternalPopup.Sync()
    Enter(popup.xBox, 99999)
    local _, right = ns.Geometry.EditRect(case.frame)
    Near(right, 1920, "right screen clamp")
    Enter(popup.yBox, -99999)
    local _, _, _, bottom = ns.Geometry.EditRect(case.frame)
    Near(bottom, 0, "bottom screen clamp")
    Enter(popup.xBox, -99999)
    Near(ns.Geometry.EditRect(case.frame), 0, "left screen clamp")
    Enter(popup.yBox, 99999)
    local _, _, top = ns.Geometry.EditRect(case.frame)
    Near(top, 1080, "top screen clamp")
    Enter(popup.xBox, -100.5)
    local _, fractionalRight = ns.Geometry.EditRect(case.frame)
    Near(fractionalRight - 960, -100.5, "fractional input changed provider drag rounding")
    local fractionalX = case.state()
    Enter(popup.xBox, popup.xBox:GetText())
    Near(case.state(), fractionalX, "rounded readout drifted on re-entry")
end
Check(saves > 0, "Blizzard never saved its layout")
Check(moves[1] == "preview" and moves[2] == "commit", "Suite-like move skipped drag phases")
Check(em.ExternalPopup.Open(cases[1].key), "Suite-like reopen")
local controls = popup._activeControlSet.numbers
Check(#controls == 2 and controls[1].id == "width" and controls[2].id == "height", "owner dimensions changed")
Enter(controls[1].box, 140)
Check(saved.width == 140 and suite:GetWidth() == 140, "width control changed")
local beforeX, beforeY, count = saved.x, saved.y, ns.History.GetHistoryState().undoCount
local oldLeft, isSecret = suite.GetLeft, env.issecretvalue
-- A secret number must pass the numeric type check if the secret guard regresses.
local secret = -424242
env.issecretvalue = function(value) return rawequal(value, secret) end
suite.GetLeft = function() return secret end
Check(em.ExternalElements.GetPositionFrame(cases[1].key) == nil, "secret numeric geometry accepted")
popup.xBox:SetText("100")
assert(popup.xBox:GetScript("OnEnterPressed"))(popup.xBox)
Near(saved.x, beforeX, "restricted geometry changed position")
Check(ns.History.GetHistoryState().undoCount == count, "restricted geometry changed history")
suite.GetLeft = oldLeft
Check(em.Ticker.SetExternalPosition(cases[1].key, "x", secret) == false, "secret input accepted")
env.issecretvalue = isSecret
for _, value in ipairs({ "bad", "", "1e309", "-1e309" }) do
    Enter(popup.xBox, value)
    Near(saved.x, beforeX, "invalid input changed position")
end
em.ExternalPopup.Sync()
rejectCommit = true
Enter(popup.xBox, -100)
rejectCommit = false
Near(saved.x, beforeX, "rejected commit changed saved X")
Near(saved.y, beforeY, "rejected commit changed saved Y")
Check(ns.History.GetHistoryState().undoCount == count, "rejected commit created history")
local restoredX = (suite:GetCenter() * suite:GetEffectiveScale() - 960) / 1.25
Near(restoredX, beforeX, "rejected preview was not rolled back")
-- The alternate public API contract needs no owner quick controls.
local plain = Target()
local plainState = { x = -300, y = -100 }
Check(api.RegisterElement("Test.Plain", { id = "frame", label = "Plain frame",
    getFrame = function() return plain end,
    getInspectorValues = function() return { x = 21, y = -31, width = 70, height = 22 } end,
    getPosition = function() return { x = plainState.x, y = plainState.y } end,
    setPosition = function(state)
        plainState.x, plainState.y = state.x, state.y
        plain:SetPoint("CENTER", env.UIParent, "CENTER", state.x, state.y)
        return true
    end,
}), "get/set registration refused")
Check(em.ExternalPopup.Open("external:test.plain:frame"), "plain popup refused")
Check(popup._activeControlSet == nil and popup.xBox and popup.yBox, "controls leaked across popup reuse")
Enter(popup.xBox, -200)
Near(plainState.x, -250, "get/set position path failed")
Check(em.Undo.DoUndo(), "get/set undo refused")
Near(plainState.x, -300, "get/set undo failed")
Check(em.Undo.DoRedo(), "get/set redo refused")
Near(plainState.x, -250, "get/set redo failed")
-- A one-unit button step is less than half a physical pixel at small UI scales.
-- It is an explicit edit, so pointer-release jitter filtering must not eat it.
env.UIParent:SetScale(.4)
em.ExternalPopup.Sync()
local plus
for _, widget in ipairs(w.widgets.frames) do
    if widget.parent == popup._positionRow and widget.GetPoint and widget:GetScript("OnClick") then
        local _, relative = widget:GetPoint(1)
        if relative == popup.xBox then plus = widget end
    end
end
Check(plus ~= nil, "X stepper plus button missing")
local stepCount = ns.History.GetHistoryState().undoCount
plus:GetScript("OnClick")(plus)
Near(plainState.x, -249, "small-scale step was discarded")
Near(em.Util.FramePositionValues(plain), -199, "small-scale step visual position")
Check(ns.History.GetHistoryState().undoCount == stepCount + 1, "small-scale step history count")
Check(em.Undo.DoUndo(), "small-scale step undo refused")
Near(plainState.x, -250, "small-scale step undo save")
Check(em.Undo.DoRedo(), "small-scale step redo refused")
Near(plainState.x, -249, "small-scale step redo save")
env.UIParent:SetScale(1)
-- A live owner can expose inspector data before its geometry becomes readable.
local getLeft = plain.GetLeft
plain.GetLeft = function() return nil end
Check(em.ExternalElements.GetPositionFrame("external:test.plain:frame") == nil, "unreadable geometry accepted")
local label, x, y, width, height = em.ExternalElements.GetInspectorValues("external:test.plain:frame")
Check(label == "Plain frame" and x == 21 and y == -31 and width == 70 and height == 22,
    "owner inspector fallback lost without readable geometry")
em.ExternalPopup.Sync()
Check(tonumber(popup.xBox:GetText()) == 21 and tonumber(popup.yBox:GetText()) == -31,
    "read-only owner coordinates missing")
local function CheckPositionControls(enabled)
    for _, child in ipairs({ popup._positionRow:GetChildren() }) do
        Check(child:IsMouseEnabled() == enabled, "position row mouse state did not follow readable geometry")
        Check(child:IsEnabled() == enabled, "position row enabled state did not follow readable geometry")
    end
end
CheckPositionControls(false)
local unavailableCount = ns.History.GetHistoryState().undoCount
Enter(popup.xBox, 123)
Near(plainState.x, -249, "read-only inspector changed saved position")
Check(ns.History.GetHistoryState().undoCount == unavailableCount, "read-only inspector changed history")
plain.GetLeft = getLeft
em.ExternalPopup.Sync()
CheckPositionControls(true)
Near(tonumber(popup.xBox:GetText()), em.Util.FramePositionValues(plain), "readable geometry did not replace owner fallback")
Check(api.GetCapabilities().positionFields == true, "host positionFields capability missing")
Check(api.GetElementCapabilities("Test.Plain", "frame").positionFields == true,
    "element positionFields capability missing")
print("editmode_external_xy_smoke: ok (" .. flavor .. ", " .. checks .. " checks)")
end
