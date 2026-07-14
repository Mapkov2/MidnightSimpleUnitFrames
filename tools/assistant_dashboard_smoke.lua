_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {},
    bars = {},
    gameplay = {},
    player = {},
    target = {},
    focus = {},
    pet = {},
    targettarget = {},
    focustarget = {},
    boss = {},
    gf_party = {},
    gf_raid = {},
    gf_mythicraid = {},
    auras3 = { shared = { showInEditMode = true } },
}
_G.MSUF_GlobalDB = {
    global = { dashboard = {} },
    profiles = {
        Default = { general = {}, bars = {}, gameplay = {} },
        Raid = _G.MSUF_DB,
    },
    char = {
        ["Player-Realm"] = {
            activeProfile = "Raid",
            specProfileMap = { [123] = "Raid" },
        },
    },
}
_G.MSUF_ActiveProfile = "Raid"
_G.GetLocale = function() return "enUS" end
_G.GetServerTime = function() return 123456 end
_G.GetTime = function() return os.clock() end
_G.UnitName = function() return "Player" end
_G.GetRealmName = function() return "Realm" end
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.CopyTable = function(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = _G.CopyTable(v) end
    return out
end
_G.MSUF_ScheduleOnce = function(key, fn)
    if type(fn) == "function" then fn() end
end
_G.C_Timer = { After = function(_, fn) if type(fn) == "function" then fn() end end }

local createdFrames = {}
_G.CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:Show() self.visible = true end
    function frame:Hide() self.visible = false end
    function frame:IsShown() return self.visible == true end
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:SetMovable() end
    function frame:SetClampedToScreen() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:CreateFontString()
        local fs = {}
        function fs:SetText(text) self.text = text end
        function fs:GetText() return self.text end
        function fs:SetPoint() end
        function fs:SetFontObject() end
        function fs:SetTextColor() end
        function fs:SetJustifyH() end
        function fs:SetJustifyV() end
        return fs
    end
    createdFrames[#createdFrames + 1] = frame
    return frame
end

local unpack = table.unpack or unpack
local M = MSUF.MSUF2
M.activeKey = "home"
M.Tr = function(text) return tostring(text or "") end
M.Format = function(fmt, ...) return string.format(tostring(fmt or ""), ...) end
M.WordList = function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end
M.KeySetFromWords = function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[word] = true end
    return out
end
M.Pick = function(source, names)
    local values, count = {}, 0
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        values[count] = source and source[name]
    end
    return unpack(values, 1, count)
end
M.PickDefaults = function(source, names)
    local values, count = {}, 0
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        values[count] = (source and source[name]) or {}
    end
    return unpack(values, 1, count)
end
M.EnsureDB = function()
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    _G.MSUF_DB.bars = _G.MSUF_DB.bars or {}
    _G.MSUF_DB.gameplay = _G.MSUF_DB.gameplay or {}
    return _G.MSUF_DB
end
M.Open = function(page) M.activeKey = page or "home"; return true end
M.SelectPage = M.Open
M.GetPageHistoryState = function() return { canBack = false, canForward = false } end
M.RequestUnitApply = function(unit, reason) MSUF._lastUnitApply = { unit = unit, reason = reason } end
M.RequestGeneralApply = function(reason) MSUF._lastGeneralApply = reason end
M.Undo = function() MSUF._menuUndo = (MSUF._menuUndo or 0) + 1; return true end
M.Redo = function() MSUF._menuRedo = (MSUF._menuRedo or 0) + 1; return true end
M.ResetHistorySession = function() MSUF._menuReset = (MSUF._menuReset or 0) + 1; return true end

MSUF.MSUF_RequestGameplayApply = function(reason) MSUF._lastGameplayApply = reason end
_G.MSUF_RequestStatusIconsRefreshForCurrent = function() MSUF._statusRefresh = (MSUF._statusRefresh or 0) + 1 end
_G.MSUF_SyncAllUnitPreviews = function() MSUF._unitPreviewSync = (MSUF._unitPreviewSync or 0) + 1 end
_G.MSUF_Auras3_RefreshEditPreview = function() MSUF._auraEditPreview = (MSUF._auraEditPreview or 0) + 1 end
_G.MSUF_Auras3_RefreshAll = function() MSUF._auraRefreshAll = (MSUF._auraRefreshAll or 0) + 1 end
_G.MSUF_GF_EM2_ShowPreview = function() MSUF._gfPreviewShown = true end
_G.MSUF_GF_EM2_HidePreview = function() MSUF._gfPreviewShown = false end
_G.MSUF_GF_EM2_IsPreviewShown = function() return MSUF._gfPreviewShown == true end
_G.MSUF_EM2_ReforcePreviewFrames = function() MSUF._editPreviewForce = (MSUF._editPreviewForce or 0) + 1 end
_G.MSUF_EnsureAnchorPicker = function()
    local overlay = {}
    function overlay:Show() MSUF._anchorPickerOpened = (MSUF._anchorPickerOpened or 0) + 1 end
    return overlay
end
_G.MSUF_EM2 = {
    State = { GetUnitKey = function() return "player" end },
    Snap = {
        _enabled = false,
        IsEnabled = function() return _G.MSUF_EM2.Snap._enabled end,
        SetEnabled = function(value) _G.MSUF_EM2.Snap._enabled = value and true or false end,
    },
    HUD = {
        RefreshControls = function() end,
        ResetCurrentPosition = function() end,
        SetStatus = function(text, kind) MSUF._editHudStatus = { text = text, kind = kind } end,
    },
    Movers = { SyncAll = function() end },
    Util = { ApplyAllSettingsSafe = function() return true end },
}

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local loadedAssistantFiles = RuntimeManifest.LoadAssistantRuntime(MSUF)
local runtimeEntries = RuntimeManifest.ReadRuntimeEntries()
assert(#loadedAssistantFiles == #runtimeEntries - 3, "Dashboard smoke non-Dashboard runtime inventory mismatch")

local A = assert(MSUF.Assistant, "Assistant namespace missing")
assert(type(A.Submit) == "function", "Assistant Submit path missing")
assert(type(A.SubmitDeferred) == "function", "Assistant deferred Submit path missing")
assert(type(A.HandleInput) == "function", "Assistant input handler missing")
assert(type(A._ChoiceTextForTest) == "function", "Assistant choice text formatter missing")
assert(type(A.RecordNoMatch) == "function", "NoMatch recorder missing")

local function submit(text)
    local result = A.Submit(text)
    assert(type(result) == "table", text .. ": missing result")
    return result
end

local function expectStatus(text, status, contains)
    local result = submit(text)
    assert((result.status or result.result) == status, text .. ": wrong status " .. tostring(result.status or result.result) .. "; actual " .. tostring(result.text or ""))
    if contains then
        local actual = tostring(result.text or "")
        assert(actual:find(contains, 1, true), text .. ": missing text " .. tostring(contains) .. "; actual " .. actual)
    end
    return result
end

local function expectApplied(text, contains)
    return expectStatus(text, "applied", contains)
end

local function assertNoRaw(text, raw, label)
    assert(not tostring(text or ""):find(raw, 1, true), tostring(label or "output") .. " repeated raw phrase: " .. raw)
end

local historyBefore = #(A.GetHistory and A.GetHistory() or {})
expectApplied("turn off player name", "I changed")
assert(_G.MSUF_DB.player.showName == false, "Submit did not write player.showName")
assert(MSUF._lastUnitApply and MSUF._lastUnitApply.unit == "player", "Submit did not request player apply")
assert(#(A.GetHistory and A.GetHistory() or {}) >= historyBefore + 2, "Submit did not record user and assistant history")

expectApplied("same for target", "I changed")
assert(_G.MSUF_DB.target.showName == false, "Follow-up did not reuse the previous setting for Target")

local choiceText = A._ChoiceTextForTest({
    { setting = A.Registry:GetSetting("player.showName"), value = false, valueLabel = "off" },
    { setting = A.Registry:GetSetting("target.showName"), value = false, valueLabel = "off" },
})
assert(choiceText:find("I found multiple matches:", 1, true), "Choice text missing multiple-match header")
assert(choiceText:find("Player Name: off", 1, true), "Choice text did not use English display labels")
assert(choiceText:find("Cancel and keep it as it is", 1, true), "Choice text missing English cancel option")

local noMatch = expectStatus("zeige mir befehle", "info", "I'm not sure which MSUF request you mean yet.")
assertNoRaw(noMatch.text, "zeige mir befehle", "NoMatch response")

for i = 1, 5 do A.RecordNoMatch("target mystery texture color", { status = "failed" }, "smoke") end
for i = 1, 2 do A.RecordNoMatch("anchor minimap to cooldownmanager", { status = "failed" }, "smoke") end
A.RecordNoMatch("set aura editing scope to target", { status = "failed" }, "smoke")

local telemetry = expectStatus("assistant no match telemetry", "info", "Assistant wording to improve:")
local telemetryText = tostring(telemetry.text or "")
assert(telemetryText:find("phrase #", 1, true), "NoMatch telemetry did not use sanitized phrase references")
assert(telemetryText:find("[high] phrase #", 1, true), "NoMatch telemetry did not keep priority metadata")
assert(telemetryText:find("closest MSUF options: barScope.target.", 1, true), "NoMatch telemetry did not include registry candidates")
assert(telemetryText:find("note: check the saved phrase", 1, true), "NoMatch telemetry did not include sanitized learning plan")
assertNoRaw(telemetryText, "target mystery texture color", "NoMatch telemetry")
assertNoRaw(telemetryText, "anchor minimap to cooldownmanager", "NoMatch telemetry")

local worklist = expectStatus("assistant no match worklist", "info", "Assistant wording to improve:")
local worklistText = tostring(worklist.text or "")
assert(worklistText:find("Phrases to improve:", 1, true), "NoMatch worklist missing priority queue")
assert(worklistText:find("[high] phrase #", 1, true), "NoMatch worklist missing sanitized high-priority phrase")
assert(worklistText:find("area: Anchoring", 1, true), "NoMatch worklist missing anchor metadata")
assertNoRaw(worklistText, "target mystery texture color", "NoMatch worklist")
assertNoRaw(worklistText, "anchor minimap to cooldownmanager", "NoMatch worklist")

local deferredHistory = #(A.GetHistory and A.GetHistory() or {})
local deferredTurnBefore = tonumber((A.GetContext and A.GetContext() or {}).turnSerial) or 0
local deferred = A.SubmitDeferred("turn off focus name")
assert(deferred and (deferred.status or deferred.result) == "applied", "SubmitDeferred did not execute through the normal input path")
assert(_G.MSUF_DB.focus.showName == false, "SubmitDeferred did not apply Focus name setting")
assert(#(A.GetHistory and A.GetHistory() or {}) >= deferredHistory + 2, "SubmitDeferred did not write history")
assert((tonumber((A.GetContext and A.GetContext() or {}).turnSerial) or 0) == deferredTurnBefore + 1,
    "SubmitDeferred did not advance exactly one conversational turn")

expectApplied("undo", "Reverted")
expectApplied("redo", "Reapplied")

assert(type(A.StartNewTask) == "function", "runtime New Task implementation missing")
local taskContext = assert(A.GetContext())
taskContext.lastSetting = "target.width"
assert(A.StartNewTask() == true, "runtime New Task did not reset")
assert(#(A.GetHistory and A.GetHistory() or {}) == 0, "runtime New Task did not clear history")
assert(next(taskContext) == nil, "runtime New Task did not clear conversational context")

io.write("assistant_dashboard_smoke: ok\n")
