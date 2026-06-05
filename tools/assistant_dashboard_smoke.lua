_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local addonRoot = "MidnightSimpleUnitFrames/Shell/Menu2/"
if not exists(addonRoot .. "Assistant/MSUF_Assistant.lua") then
    addonRoot = "Shell/Menu2/"
end
local stateRoot = "MidnightSimpleUnitFrames/State/"
if not exists(stateRoot .. "MSUF_Profiles.lua") then
    stateRoot = "State/"
end

local MSUF = { MSUF2 = {} }
local capturedPrints = {}
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    capturedPrints[#capturedPrints + 1] = table.concat(parts, " ")
end
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
_G.InCombatLockdown = function() return false end
_G.GetLocale = function() return "enUS" end
_G.UnitName = function() return "Player" end
_G.GetRealmName = function() return "Realm" end
_G.CopyTable = function(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = _G.CopyTable(v) end
    return out
end
_G.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
    }
end
_G.MSUF_CurrentEditUnitKey = "target"
_G.MSUF_UnitEditModeActive = true
_G.MSUF_UnitPreviewActive = true
_G.MSUF_SyncAllUnitPreviews = function() MSUF._unitPreviewSync = (MSUF._unitPreviewSync or 0) + 1 end
_G.MSUF_Auras3_RefreshEditPreview = function() MSUF._auraEditPreview = (MSUF._auraEditPreview or 0) + 1 end
_G.MSUF_Auras3_RefreshAll = function() MSUF._auraRefreshAll = (MSUF._auraRefreshAll or 0) + 1 end
_G.MSUF_GF_EM2_ShowPreview = function() MSUF._gfPreviewShown = true; MSUF._gfPreviewShowCount = (MSUF._gfPreviewShowCount or 0) + 1 end
_G.MSUF_GF_EM2_HidePreview = function() MSUF._gfPreviewShown = false; MSUF._gfPreviewHideCount = (MSUF._gfPreviewHideCount or 0) + 1 end
_G.MSUF_GF_EM2_IsPreviewShown = function() return MSUF._gfPreviewShown == true end
_G.MSUF_EM2_ReforcePreviewFrames = function() MSUF._editPreviewForce = (MSUF._editPreviewForce or 0) + 1 end
_G.MSUF_EnsureAnchorPicker = function()
    local overlay = {}
    function overlay:Show()
        MSUF._anchorPickerOpened = (MSUF._anchorPickerOpened or 0) + 1
    end
    MSUF._anchorPickerOverlay = overlay
    return overlay
end
_G.MSUF_EM2 = {
    State = {
        GetUnitKey = function() return _G.MSUF_CurrentEditUnitKey end,
    },
    Snap = {
        _enabled = false,
        IsEnabled = function() return _G.MSUF_EM2.Snap._enabled and true or false end,
        SetEnabled = function(value) _G.MSUF_EM2.Snap._enabled = value and true or false end,
    },
    HUD = {
        RefreshControls = function() MSUF._editHudRefresh = (MSUF._editHudRefresh or 0) + 1 end,
        ResetCurrentPosition = function()
            MSUF._editResetPosition = (MSUF._editResetPosition or 0) + 1
            local key = _G.MSUF_CurrentEditUnitKey
            if key and _G.MSUF_DB[key] then
                _G.MSUF_DB[key].offsetX = 0
                _G.MSUF_DB[key].offsetY = 0
            end
        end,
        SetStatus = function(text, kind)
            MSUF._editHudStatus = { text = text, kind = kind }
        end,
    },
    Movers = {
        SyncAll = function() MSUF._editMoverSync = (MSUF._editMoverSync or 0) + 1 end,
    },
    Util = {
        ApplyAllSettingsSafe = function()
            MSUF._editApplyAll = (MSUF._editApplyAll or 0) + 1
            return true
        end,
    },
}

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
    return _G.MSUF_DB
end
M.RequestUnitApply = function(unit, reason) MSUF._lastUnitApply = { unit = unit, reason = reason } end
M.RequestGeneralApply = function(reason) MSUF._lastGeneralApply = reason end
_G.MSUF_RequestStatusIconsRefreshForCurrent = function() MSUF._statusRefresh = (MSUF._statusRefresh or 0) + 1 end
MSUF.MSUF_RequestGameplayApply = function(reason) MSUF._lastGameplayApply = reason end
M.Open = function(page) M.activeKey = page; return true end
M.SelectPage = M.Open
M.InvalidatePage = function() end
M.SyncGFPagePreviewForKey = function(key, force)
    MSUF._gfPagePreviewSync = { key = key, force = force, scope = M.gfScope }
    if _G.MSUF_UnitEditModeActive == true then
        _G.MSUF2_GFPagePreviewActive = nil
        _G.MSUF2_GFPagePreviewKind = nil
        return
    end
    if key == "gf_layout" or key == "gf_bars" or key == "gf_indicators" then
        _G.MSUF2_GFPagePreviewActive = true
        _G.MSUF2_GFPagePreviewKind = M.gfScope
    else
        _G.MSUF2_GFPagePreviewActive = nil
        _G.MSUF2_GFPagePreviewKind = nil
    end
end
M.PersistMenuStateValue = function(key, value) M[key] = value end
M.GetPersistentMenuStateTable = function(key)
    M[key] = type(M[key]) == "table" and M[key] or {}
    return M[key]
end
M.navItems = {
    { header = "Frames", id = "unitframes", defaultOpen = true },
    { key = "uf_player", group = "unitframes" },
    { header = "Group Frames", id = "groupframes", defaultOpen = true },
    { key = "gf_layout", group = "groupframes" },
    { header = "Appearance", id = "globalstyle", defaultOpen = true },
    { key = "opt_bars", group = "globalstyle" },
}
M.navHeaderState = { unitframes = true, groupframes = false, globalstyle = true }
M.nav = {
    _msuf2NavReflow = function()
        MSUF._navReflowed = (MSUF._navReflowed or 0) + 1
    end,
}

local function loadAddon(relative)
    local path = addonRoot .. relative
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function loadState(relative)
    local path = stateRoot .. relative
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

loadState("MSUF_Profiles.lua")
assert(type(_G.MSUF_RenameProfile) == "function", "Core profile rename helper missing")

local assistantFiles = {
    "Assistant/MSUF_AssistantHistory.lua",
    "Assistant/MSUF_AssistantUndo.lua",
    "Assistant/MSUF_AssistantQueue.lua",
    "Assistant/MSUF_AssistantRegistry.lua",
    "Assistant/MSUF_AssistantRegistry_Core.lua",
    "Assistant/MSUF_AssistantRegistry_Unitframes.lua",
    "Assistant/MSUF_AssistantRegistry_Castbars.lua",
    "Assistant/MSUF_AssistantRegistry_Auras.lua",
    "Assistant/MSUF_AssistantRegistry_GroupFrames.lua",
    "Assistant/MSUF_AssistantRegistry_Boss.lua",
    "Assistant/MSUF_AssistantRegistry_ClassPower.lua",
    "Assistant/MSUF_AssistantRegistry_Gameplay.lua",
    "Assistant/MSUF_AssistantRegistry_Global.lua",
    "Assistant/MSUF_AssistantRegistry_Dashboard.lua",
    "Assistant/MSUF_AssistantRegistry_Profiles.lua",
    "Assistant/MSUF_AssistantRegistry_EditMode.lua",
    "Assistant/MSUF_AssistantRegistry_Workflows.lua",
    "Assistant/MSUF_AssistantRegistry_Diagnostics.lua",
    "Assistant/MSUF_AssistantMediaResolver.lua",
    "Assistant/MSUF_AssistantParser_Core.lua",
    "Assistant/MSUF_AssistantParser_Profiles.lua",
    "Assistant/MSUF_AssistantParser_Auras.lua",
    "Assistant/MSUF_AssistantParser_Actions.lua",
    "Assistant/MSUF_AssistantParser_Registry.lua",
    "Assistant/MSUF_AssistantParser_Features.lua",
    "Assistant/MSUF_AssistantParser_Geometry.lua",
    "Assistant/MSUF_AssistantParser_Followups.lua",
    "Assistant/MSUF_AssistantParser.lua",
    "Assistant/MSUF_Assistant.lua",
}

local searchFiles = {
    "Search/MSUF_Menu2_Search_Data.lua",
    "Search/MSUF_Menu2_Search_Keywords.lua",
    "Search/MSUF_Menu2_Search_QueryAliases.lua",
    "Search/MSUF_Menu2_Search_FAQ.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_01.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_02.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_03.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_04.lua",
    "Search/MSUF_Menu2_Search_Text.lua",
    "Search/MSUF_Menu2_Search_IndexQuery.lua",
    "Search/MSUF_Menu2_Search_API.lua",
}

for _, file in ipairs(assistantFiles) do loadAddon(file) end
for _, file in ipairs(searchFiles) do loadAddon(file) end
loadAddon("Assistant/MSUF_AssistantKnowledge.lua")
loadAddon("Assistant/MSUF_AssistantRouter.lua")

local A = assert(MSUF.Assistant, "Assistant namespace missing")
assert(type(A.Submit) == "function", "Assistant Submit path missing")
assert(type(A.SubmitDeferred) == "function", "Assistant deferred Submit path missing")
assert(type(A.HandleInput) == "function", "Assistant input handler missing")
assert(type(A.RouteInput) == "function", "Assistant router missing")
assert(type(A._ChoiceTextForTest) == "function", "Assistant choice text formatter missing")
assert(A.IsBusy() == false, "Assistant should not start busy")
A.SetBusy(true, "Testing busy state")
local busySubmit = A.SubmitDeferred("turn off target name")
assert(busySubmit and busySubmit.status == "busy", "Assistant deferred Submit did not guard concurrent requests")
A.SetBusy(false)
_G.MSUF_DB.player.showName = true
local deferredHistoryCount = #A.GetHistory()
local deferredResult = A.SubmitDeferred("turn off player name")
assert(deferredResult and deferredResult.status == "applied", "Assistant deferred Submit did not execute through the normal input path")
assert(A.IsBusy() == false, "Assistant deferred Submit did not clear busy state")
assert(#A.GetHistory() == deferredHistoryCount + 2, "Assistant deferred Submit did not write user and assistant history")
assert(_G.MSUF_DB.player.showName == false, "Assistant deferred Submit did not apply the requested setting")
_G.MSUF_DB.player.showName = true
local oldScheduler = MSUF.Scheduler
local scheduledDeferred
MSUF.Scheduler = {
    RunNextFrame = function(fn)
        scheduledDeferred = fn
    end,
}
_G.MSUF_DB.target.showName = true
local queuedHistoryCount = #A.GetHistory()
local queuedDeferred = A.SubmitDeferred("turn off target name")
assert(queuedDeferred and queuedDeferred.status == "queued", "Assistant deferred Submit did not use the next-frame path when a scheduler is available")
assert(A.IsBusy() == true, "Assistant deferred Submit did not stay busy while queued")
assert(type(scheduledDeferred) == "function", "Assistant deferred Submit did not schedule the next-frame worker")
assert(#A.GetHistory() == queuedHistoryCount + 1, "Assistant deferred Submit should write only the user history before the worker runs")
scheduledDeferred()
assert(A.IsBusy() == false, "Assistant deferred Submit did not clear busy state after the queued worker")
assert(#A.GetHistory() == queuedHistoryCount + 2, "Assistant deferred Submit did not write assistant history after the queued worker")
assert(_G.MSUF_DB.target.showName == false, "Assistant deferred Submit queued worker did not apply the requested setting")
_G.MSUF_DB.target.showName = true
MSUF.Scheduler = oldScheduler
local choiceText = A._ChoiceTextForTest({
    { label = "Global Bar Texture [] EQOL: Absorb" },
    { label = "Global Bar Texture [] EQOL: Astral" },
})
assert(not choiceText:find("%[%]", 1, false), "Assistant choice text still renders empty [] scope marker")
assert(choiceText:find("Global Bar Texture EQOL: Absorb", 1, true), "Assistant choice text removed too much content")
assert(choiceText:find("0. None", 1, true), "Assistant choice text does not show a visible None option")
local barTextureSetting = assert(A.Registry:GetSetting("general.barTexture"), "Global Bar Texture registry setting missing")
_G.MSUF_DB.general.barTexture = "Solid"
A.pendingChoices = {
    { setting = barTextureSetting, value = "EQOL: Absorb", label = "Global Bar Texture [] EQOL: Absorb" },
    { setting = barTextureSetting, value = "EQOL: Astral", label = "Global Bar Texture [] EQOL: Astral" },
}
local cancelChoice = A.Submit("no i dont want to change")
assert(cancelChoice.status == "info" and tostring(cancelChoice.text or ""):find("Cancelled", 1, true), "Assistant did not cancel pending choices from human no-answer")
assert(A.pendingChoices == nil, "Assistant did not clear pending choices after no-answer")
assert(_G.MSUF_DB.general.barTexture == "Solid", "Assistant changed a setting after pending choice cancel")
A.pendingChoices = {
    { setting = barTextureSetting, value = "EQOL: Absorb", label = "Global Bar Texture [] EQOL: Absorb" },
    { setting = barTextureSetting, value = "EQOL: Astral", label = "Global Bar Texture [] EQOL: Astral" },
}
local noneChoice = A.Submit("none")
assert(noneChoice.status == "info" and tostring(noneChoice.text or ""):find("Cancelled", 1, true), "Assistant did not cancel pending choices from none")
assert(A.pendingChoices == nil, "Assistant did not clear pending choices after none")
assert(_G.MSUF_DB.general.barTexture == "Solid", "Assistant changed a setting after none")
A.pendingChoices = {
    { setting = barTextureSetting, value = "EQOL: Absorb", label = "Global Bar Texture [] EQOL: Absorb" },
    { setting = barTextureSetting, value = "EQOL: Astral", label = "Global Bar Texture [] EQOL: Astral" },
}
local zeroChoice = A.Submit("0")
assert(zeroChoice.status == "info" and tostring(zeroChoice.text or ""):find("Cancelled", 1, true), "Assistant did not cancel pending choices from option 0")
assert(A.pendingChoices == nil, "Assistant did not clear pending choices after option 0")
assert(_G.MSUF_DB.general.barTexture == "Solid", "Assistant changed a setting after option 0")
A.pendingChoices = {
    { setting = barTextureSetting, value = "EQOL: Absorb", label = "Global Bar Texture [] EQOL: Absorb" },
    { setting = barTextureSetting, value = "EQOL: Astral", label = "Global Bar Texture [] EQOL: Astral" },
}
local freshCommand = A.Submit("help")
assert(freshCommand.status == "applied", "Assistant did not route a fresh command after clearing pending choices")
assert(A.pendingChoices == nil, "Assistant did not clear pending choices before fresh command")
assert(_G.MSUF_DB.general.barTexture == "Solid", "Assistant applied stale pending choice instead of the fresh command")
assert(A.LoginGreetingForHour(8) == "Good morning", "Login greeting did not detect morning")
assert(A.LoginGreetingForHour(14) == "Good afternoon", "Login greeting did not detect afternoon")
assert(A.LoginGreetingForHour(20) == "Good evening", "Login greeting did not detect evening")
assert(A.LoginGreetingForHour(2) == "Good night", "Login greeting did not detect night")
local greetingHistoryCount = #A.GetHistory()
A._loginGreetingShown = nil
local greeted, greetingText = A.AddLoginGreeting("Mapko", 14)
assert(greeted == true, "Assistant login greeting did not add a session greeting")
assert(greetingText == "Good afternoon, Mapko. I am ready to help with MSUF.", "Assistant login greeting used the wrong text")
assert(#A.GetHistory() == greetingHistoryCount + 1, "Assistant login greeting did not write to history")
local greetedAgain = A.AddLoginGreeting("Mapko", 14)
assert(greetedAgain == false, "Assistant login greeting should only run once per session")

local function submit(text)
    local result = A.Submit(text)
    assert(type(result) == "table", text .. ": missing result")
    return result
end

local function expectStatus(text, status, contains)
    local result = submit(text)
    assert(result.status == status, text .. ": wrong status " .. tostring(result.status))
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), text .. ": missing text " .. tostring(contains))
    end
    return result
end

local function assertNear(actual, expected, label)
    assert(type(actual) == "number", tostring(label) .. ": expected number, got " .. tostring(actual))
    assert(math.abs(actual - expected) < 0.0005, tostring(label) .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function expectApplied(text, contains)
    return expectStatus(text, "applied", contains)
end

local searchSubmitCount = 0
local searchSubmitQuery
local originalSubmit = A.Submit
A.Submit = function(text)
    searchSubmitCount = searchSubmitCount + 1
    searchSubmitQuery = text
    return originalSubmit(text)
end
M.activeKey = "uf_target"
assert(M.Search and type(M.Search.OpenResults) == "function", "Search public OpenResults path missing")
M.Search.OpenResults("where is castbar texture")
assert(searchSubmitCount == 1, "Search OpenResults did not route through Assistant Submit")
assert(searchSubmitQuery == "where is castbar texture", "Search OpenResults changed the submitted query")
assert(M.activeKey == "home", "Search OpenResults did not return to the Assistant dashboard page")
A.Submit = originalSubmit

local supportDB = A.EnsureDB()
supportDB.powerUserSupportSuccessCount = 99
supportDB.powerUserSupportHintAt = 0
_G.MSUF_DB.player.showName = true
local supportHintHistoryCount = #A.GetHistory()
local supportHintResult = expectApplied("turn off player name", "I changed")
assert(tostring(supportHintResult.text or ""):find("from enabled to disabled", 1, true), "Dashboard Assistant success response did not explain the old and new values before the power-user hint")
assert(#A.GetHistory() == supportHintHistoryCount + 3, "Power-user hint should add user, success, and one info history row")
local supportHint = A.GetHistory()[#A.GetHistory()]
assert(supportHint.status == "info" and tostring(supportHint.text or ""):find("links on the Dashboard", 1, true), "Power-user hint did not point to the Dashboard links")
assert(supportDB.powerUserSupportSuccessCount == 0, "Power-user hint did not reset the success counter after showing")
supportDB.powerUserSupportSuccessCount = 99
_G.MSUF_DB.player.showName = true
local cooldownHintHistoryCount = #A.GetHistory()
expectApplied("turn off player name", "I changed")
assert(#A.GetHistory() == cooldownHintHistoryCount + 2, "Power-user hint ignored the weekly cooldown")
assert(supportDB.powerUserSupportSuccessCount == 100, "Power-user hint should keep the threshold ready while the cooldown is active")

_G.MSUF_DB.player.showName = true
local humanSingleChange = expectApplied("turn off player name", "I changed")
assert(tostring(humanSingleChange.text or ""):find("from enabled to disabled", 1, true), "Dashboard Assistant success response did not explain the old and new values")
assert(_G.MSUF_DB.player.showName == false, "Dashboard Submit did not write player.showName")
assert(MSUF._lastUnitApply and MSUF._lastUnitApply.unit == "player", "Dashboard Submit did not request player apply")
_G.MSUF_DB.player.showName = true
expectApplied("spieler name aus", "Done.")
assert(_G.MSUF_DB.player.showName == false, "Dashboard Submit did not understand German Player name off")
_G.MSUF_DB.player.enabled = true
expectApplied("turn off frame", "Done.")
assert(_G.MSUF_DB.player.enabled == false, "Dashboard conversation context did not route bare frame toggle to last player unit")
_G.MSUF_DB.player.enabled = true
expectApplied("turn off player frame", "Done.")
assert(_G.MSUF_DB.player.enabled == false, "Dashboard Submit did not write player.enabled")
expectApplied("turn it back on", "Done.")
assert(_G.MSUF_DB.player.enabled == true, "Dashboard context follow-up did not re-enable player.enabled")
_G.MSUF_DB.player.enabled = false
expectApplied("spieler frame einschalten", "Done.")
assert(_G.MSUF_DB.player.enabled == true, "Dashboard Submit did not understand German Player frame on")
_G.MSUF_DB.general.slashMenuSnapEnabled = true
expectApplied("turn off snapping feature", "Done.")
assert(_G.MSUF_DB.general.slashMenuSnapEnabled == false, "Dashboard Submit did not turn off Misc menu edge snapping")
_G.MSUF_DB.general.slashMenuSnapEnabled = true
expectApplied("turn off menu snapping", "Done.")
assert(_G.MSUF_DB.general.slashMenuSnapEnabled == false, "Dashboard Submit did not understand menu snapping alias")
_G.MSUF_DB.general.hideAdvancedMenu = false
expectApplied("hide advanced menu section", "Done.")
assert(_G.MSUF_DB.general.hideAdvancedMenu == true, "Dashboard Submit did not hide Advanced menu section")
expectApplied("show advanced menu section", "Done.")
assert(_G.MSUF_DB.general.hideAdvancedMenu == false, "Dashboard Submit did not show Advanced menu section")
_G.MSUF_DB.general.reduceMotion = false
expectApplied("turn on reduce menu motion", "Done.")
assert(_G.MSUF_DB.general.reduceMotion == true, "Dashboard Submit did not enable Reduce Menu Motion")
_G.MSUF_DB.general.showWelcomeMessage = true
expectApplied("turn off welcome message", "Done.")
assert(_G.MSUF_DB.general.showWelcomeMessage == false, "Dashboard Submit did not turn off Welcome Message")
_G.MSUF_DB.general.versionCheckEnabled = true
expectApplied("turn off peer version check", "Done.")
assert(_G.MSUF_DB.general.versionCheckEnabled == false, "Dashboard Submit did not turn off Peer Version Check")
_G.MSUF_DB.general.showMinimapIcon = true
expectApplied("hide minimap icon", "Done.")
assert(_G.MSUF_DB.general.showMinimapIcon == false, "Dashboard Submit did not hide MSUF Minimap Icon")
_G.MSUF_DB.general.playTargetSelectLostSounds = false
expectApplied("turn on target lost sounds", "Done.")
assert(_G.MSUF_DB.general.playTargetSelectLostSounds == true, "Dashboard Submit did not enable Target Select/Lost Sounds")
_G.MSUF_DB.general.disableBlizzardUnitFrames = false
expectApplied("disable blizzard unitframes", "Done.")
assert(_G.MSUF_DB.general.disableBlizzardUnitFrames == true, "Dashboard Submit did not disable Blizzard Unitframes")
expectApplied("enable blizzard unitframes", "Done.")
assert(_G.MSUF_DB.general.disableBlizzardUnitFrames == false, "Dashboard Submit did not enable Blizzard Unitframes")
_G.MSUF_DB.general.hardKillBlizzardPlayerFrame = false
expectApplied("fully hide blizzard player frame", "Done.")
assert(_G.MSUF_DB.general.hardKillBlizzardPlayerFrame == true, "Dashboard Submit routed Fully Hide Blizzard PlayerFrame to the wrong setting")
expectApplied("set menu language to german", "Done.")
assert(_G.MSUF_DB.general.menuLocale == "deDE", "Dashboard Submit did not set Menu Language")
expectApplied("set tooltip source to msuf", "Done.")
assert(_G.MSUF_DB.general.unitTooltipProvider == "MSUF", "Dashboard Submit did not set Tooltip Source")
expectApplied("set tooltip anchor to cursor", "Done.")
assert(_G.MSUF_DB.general.unitTooltipAnchor == "CURSOR", "Dashboard Submit did not set Tooltip Anchor")
expectApplied("show tooltips only out of combat", "Done.")
assert(_G.MSUF_DB.general.unitTooltipMode == "OOC", "Dashboard Submit did not set Tooltip Mode to Out of Combat")
expectApplied("set tooltip modifier to shift", "Done.")
assert(_G.MSUF_DB.general.unitTooltipModifier == "SHIFT", "Dashboard Submit did not set Tooltip Modifier")
for _, unit in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
    _G.MSUF_DB[unit].portraitMode = "OFF"
end
_G.MSUF_DB.targettarget.enabled = false
_G.MSUF_DB.focustarget.enabled = false
expectApplied("turn on portraits for all unitframes", "MSUF settings:")
for _, unit in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
    assert(_G.MSUF_DB[unit].portraitMode == "LEFT", "Dashboard Submit did not turn on " .. unit .. " portrait")
end
assert(_G.MSUF_DB.targettarget.enabled == false, "Dashboard Submit enabled Target of Target frame instead of only portraits")
assert(_G.MSUF_DB.focustarget.enabled == false, "Dashboard Submit enabled Focus Target frame instead of only portraits")
_G.MSUF_DB.player.showName = true
_G.MSUF_DB.target.showName = true
expectApplied("turn off player name", "Done.")
expectApplied("same for target", "Done.")
assert(_G.MSUF_DB.target.showName == false, "Dashboard follow-up did not replay Player name change to Target")
_G.MSUF_DB.gf_raid.showName = true
expectApplied("same for raid", "Done.")
assert(_G.MSUF_DB.gf_raid.showName == false, "Dashboard follow-up did not map Unit name change to Raid group name")

expectStatus("reset player settings", "confirmation_needed", "Type 'yes'")
expectStatus("cancel", "failed", "Cancelled.")
local menuUndoCount = 0
local menuRedoCount = 0
local menuResetCount = 0
M.Undo = function() menuUndoCount = menuUndoCount + 1; return true end
M.Redo = function() menuRedoCount = menuRedoCount + 1; return true end
M.GetHistoryState = function() return { canResetAll = true, undoCount = menuUndoCount, redoCount = menuRedoCount } end
M.ResetHistorySession = function() menuResetCount = menuResetCount + 1; return true end
expectApplied("undo menu change", "Done. Undid")
assert(menuUndoCount == 1, "Dashboard Submit did not call menu history undo helper")
expectApplied("redo menu change", "Done. Redid")
assert(menuRedoCount == 1, "Dashboard Submit did not call menu history redo helper")
expectStatus("reset all menu changes from this session", "confirmation_needed", "Type 'yes'")
expectApplied("yes", "Reset all MSUF menu changes")
assert(menuResetCount == 1, "Dashboard Submit did not call menu history session reset helper")

local ctx = A.GetContext()
ctx.lastSetting = nil
ctx.lastUnit = nil
ctx.lastFrameType = nil
ctx.lastCategory = nil
ctx.lastValue = nil
ctx.lastChangeBundle = nil
M.activeKey = "home"
local ambiguous = submit("turn off name")
assert(ambiguous.status == "ambiguous", "turn off name should ask for a numbered choice")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices > 0, "pending choices missing")
expectApplied("option 1")

local firstAmbiguous = submit("turn on name")
assert(firstAmbiguous.status == "ambiguous", "turn on name should ask for a numbered choice")
expectApplied("first")

M.activeKey = "uf_player"
_G.MSUF_DB.player.showName = true
expectApplied("turn off name", "Done.")
assert(_G.MSUF_DB.player.showName == false, "Player page context did not route bare name toggle to player.showName")
_G.MSUF_DB.player.hpOffsetY = 0
expectApplied("move health down 4", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == -4, "Player page context did not move Player HP text down")
expectApplied("set hp y offset to -8", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == -8, "Player page context did not set Player HP Y text offset")
_G.MSUF_DB.player.hpTextLeftOffsetY = 0
expectApplied("move left hp text down 3", "Done.")
assert(_G.MSUF_DB.player.hpTextLeftOffsetY == -3, "Player page context did not move Player left HP text slot down")
_G.MSUF_DB.player.textLeft = "NONE"
expectApplied("set left hp text to current", "Done.")
assert(_G.MSUF_DB.player.textLeft == "CURRENT", "Player page context did not set Player left HP text slot content")
_G.MSUF_DB.player.textLeft = "NONE"
expectApplied("add max hp text left side player frame", "Done.")
assert(_G.MSUF_DB.player.textLeft == "MAX", "Dashboard Submit selected Player HP left slot instead of setting Max HP content")
expectApplied("change hp text player to only %", "Done.")
assert(_G.MSUF_DB.player.textLeft == "PERCENT", "Dashboard Submit did not use selected Player HP left slot for percent-only text")
expectApplied("now make it max hp", "Done.")
assert(_G.MSUF_DB.player.textLeft == "MAX", "Dashboard Submit did not reuse selected Player HP left slot for Max HP")
_G.MSUF_DB.target.textLeft = "NONE"
expectApplied("do same for target", "Done.")
assert(_G.MSUF_DB.target.textLeft == "MAX", "Dashboard Submit did not replay Player HP left text content to Target")
_G.MSUF_DB.player.textLeft = "NONE"
expectApplied("put max hp on left side player frame", "Done.")
assert(_G.MSUF_DB.player.textLeft == "MAX", "Dashboard Submit did not understand put Max HP on Player left side")
_G.MSUF_DB.player.textLeft = "MAX"
expectApplied("clear player hp text left", "Done.")
assert(_G.MSUF_DB.player.textLeft == "NONE", "Dashboard Submit did not clear Player HP left text slot")
_G.MSUF_DB.player.powerTextLeft = "CURRENT"
_G.MSUF_DB.player.powerTextCenter = "MAX"
_G.MSUF_DB.player.powerTextRight = "CURMAX"
expectApplied("remove player power text", "Done.")
assert(_G.MSUF_DB.player.powerTextLeft == "NONE" and _G.MSUF_DB.player.powerTextCenter == "NONE" and _G.MSUF_DB.player.powerTextRight == "NONE", "Dashboard Submit did not clear all Player Power text slots")
expectApplied("set player power text right to percent", "Done.")
assert(_G.MSUF_DB.player.powerTextRight == "PERCENT", "Dashboard Submit did not set Player Power right text to Percent")
_G.MSUF_DB.target.powerTextLeft = "NONE"
_G.MSUF_DB.target.powerTextCenter = "NONE"
_G.MSUF_DB.target.powerTextRight = "CURPERCENT"
expectApplied("set target power text to percent", "Target Power Right Slot")
assert(_G.MSUF_DB.target.powerTextRight == "PERCENT", "Dashboard Submit did not reuse the only active Target Power text slot")
assert(_G.MSUF_DB.target.powerTextCenter == "NONE", "Dashboard Submit incorrectly created a new Target Power center text slot")
_G.MSUF_DB.target.powerTextLeft = "CURRENT"
_G.MSUF_DB.target.powerTextCenter = "NONE"
_G.MSUF_DB.target.powerTextRight = "CURPERCENT"
ctx.lastTextFrameType = nil
ctx.lastTextUnit = nil
ctx.lastTextArea = nil
ctx.lastTextSlot = nil
ctx.lastTextSetting = nil
ctx.lastTextValue = nil
ctx.selectedTextEditorTarget = nil
local targetPowerTextChoice = expectStatus("set target power text to percent", "ambiguous", "Target Power Left Slot -> PERCENT")
assert(tostring(targetPowerTextChoice.text or ""):find("Target Power Right Slot -> PERCENT", 1, true), "Dashboard Submit did not offer the other active Target Power text slot")
assert(not tostring(targetPowerTextChoice.text or ""):find("Target Power Center Slot", 1, true), "Dashboard Submit offered an inactive Target Power center text slot")
expectApplied("2", "Done.")
assert(_G.MSUF_DB.target.powerTextRight == "PERCENT", "Dashboard Submit did not apply selected Target Power text slot choice")
assert(_G.MSUF_DB.target.powerTextLeft == "CURRENT", "Dashboard Submit changed the wrong active Target Power text slot")
expectApplied("set target hp text right to current/max", "Done.")
assert(_G.MSUF_DB.target.textRight == "CURMAX", "Dashboard Submit did not set Target HP right text to Current/Max")
_G.MSUF_DB.player.textLeft = "NONE"
expectApplied("create new hp text at player frame anchor left side with hp max", "Done.")
assert(_G.MSUF_DB.player.textLeft == "MAX", "Player page context selected Player HP left slot instead of setting HP Max content")
_G.MSUF_DB.player.hpFontSize = 14
expectApplied("set hp text size to 18", "Done.")
assert(_G.MSUF_DB.player.hpFontSize == 18, "Player page context did not set Player HP text font size")
_G.MSUF_DB.player.hpTextLayer = 5
expectApplied("set hp text layer to 8", "Done.")
assert(_G.MSUF_DB.player.hpTextLayer == 8, "Player page context did not set Player HP text layer")
expectApplied("send hp text layer behind", "Done.")
assert(_G.MSUF_DB.player.hpTextLayer == 7, "Player page context did not lower Player HP text layer")

M.activeKey = "gf_bars"
M.gfScope = "raid"
_G.MSUF_DB.gf_party.showName = true
_G.MSUF_DB.gf_raid.showName = true
expectApplied("turn off name", "Done.")
assert(_G.MSUF_DB.gf_raid.showName == false, "Group Health & Text context did not route bare name toggle to raid showName")
assert(_G.MSUF_DB.gf_party.showName == true, "Group Health & Text context changed the wrong group scope")
_G.MSUF_DB.gf_raid.hpOffsetY = 0
expectApplied("move hp down 4", "Done.")
assert(_G.MSUF_DB.gf_raid.hpOffsetY == -4, "Group Health & Text context did not move Raid HP text down")
expectApplied("set hp y offset to -8", "Done.")
assert(_G.MSUF_DB.gf_raid.hpOffsetY == -8, "Group Health & Text context did not set Raid HP Y text offset")
_G.MSUF_DB.gf_raid.hpTextCenterOffsetX = 0
expectApplied("set center hp text x offset to 5", "Done.")
assert(_G.MSUF_DB.gf_raid.hpTextCenterOffsetX == 5, "Group Health & Text context did not set Raid center HP text slot X offset")
_G.MSUF_DB.gf_raid.textCenter = "NONE"
expectApplied("set center hp text to percent", "Done.")
assert(_G.MSUF_DB.gf_raid.textCenter == "PERCENT", "Group Health & Text context did not set Raid center HP text slot content")
_G.MSUF_DB.gf_raid.textCenter = "NONE"
expectApplied("create new hp text at raid frame anchor center side with hp percent", "Done.")
assert(_G.MSUF_DB.gf_raid.textCenter == "PERCENT", "Group Health & Text context did not create Raid center HP text content")
_G.MSUF_DB.gf_raid.hpFontSize = 9
expectApplied("set hp text size to 13", "Done.")
assert(_G.MSUF_DB.gf_raid.hpFontSize == 13, "Group Health & Text context did not set Raid HP text font size")
_G.MSUF_DB.gf_raid.textLayer = 3
expectApplied("set hp text layer to 7", "Done.")
assert(_G.MSUF_DB.gf_raid.textLayer == 7, "Group Health & Text context did not set Raid HP text layer")
expectApplied("bring hp text layer forward", "Done.")
assert(_G.MSUF_DB.gf_raid.textLayer == 8, "Group Health & Text context did not raise Raid HP text layer")
M.activeKey = "home"
_G.MSUF_DB.gf_party.enabled = true
_G.MSUF_DB.gf_raid.enabled = true
expectApplied("turn off frame", "Done.")
assert(_G.MSUF_DB.gf_raid.enabled == false, "Dashboard conversation context did not route bare frame toggle to last raid group")
assert(_G.MSUF_DB.gf_party.enabled == true, "Dashboard conversation context changed the wrong group frame scope")
_G.MSUF_DB.gf_party.nameOffsetY = 0
expectApplied("move party frame name down", "Done.")
assert(_G.MSUF_DB.gf_party.nameOffsetY == -10, "Dashboard Submit did not move Party group name text down")
expectApplied("move party frame name text down", "Done.")
assert(_G.MSUF_DB.gf_party.nameOffsetY == -20, "Dashboard Submit did not move Party group name text down with explicit text phrase")
do
    local savedAliases = A.UnitAliases
    A.UnitAliases = {}
    expectApplied("move party frame name down", "Done.")
    assert(_G.MSUF_DB.gf_party.nameOffsetY == -30, "Dashboard Submit did not move Party group name text down without alias bootstrap")
    A.UnitAliases = savedAliases
end
expectApplied("move the party frames name down", "Done.")
assert(_G.MSUF_DB.gf_party.nameOffsetY == -40, "Dashboard Submit did not move Party group name text down with possessive/plural frame phrase")
expectApplied("move party names up 2", "Done.")
assert(_G.MSUF_DB.gf_party.nameOffsetY == -38, "Dashboard Submit did not move Party plural name text up")
_G.MSUF_DB.player.hpOffsetY = 0
expectApplied("move player health down 4", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == -4, "Dashboard Submit did not move Player HP text down with health shorthand")
_G.MSUF_DB.player.hpOffsetY = 0
expectApplied("verschiebe spieler lebensanzeige runter 4", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == -4, "Dashboard Submit did not understand German Player health movement")
_G.MSUF_DB.target.powerOffsetY = 0
expectApplied("verschiebe ziel energie hoch 2", "Done.")
assert(_G.MSUF_DB.target.powerOffsetY == 2, "Dashboard Submit did not understand German Target power movement")
_G.MSUF_DB.player.width = 200
expectApplied("setze spieler breite auf 222", "Done.")
assert(_G.MSUF_DB.player.width == 222, "Dashboard Submit did not understand German Player width set")
_G.MSUF_DB.general.enableTargetCastbar = true
expectApplied("ziel zauberleiste ausschalten", "Done.")
assert(_G.MSUF_DB.general.enableTargetCastbar == false, "Dashboard Submit did not understand German Target castbar off")
_G.MSUF_DB.targettarget.totInlineSeparator = "|"
_G.MSUF_DB.targettarget.totInlineCustomSeparator = ""
local inlinePrompt = submit("change target inline seperator")
assert(inlinePrompt.status == "ambiguous", "Dashboard Submit did not ask for inline separator value")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices >= 3, "Dashboard Submit did not expose inline separator choices")
expectApplied("option 3", "Done.")
assert(_G.MSUF_DB.targettarget.totInlineSeparator == "/", "Dashboard Submit did not apply inline separator choice")
_G.MSUF_DB.targettarget.totInlineSeparator = "|"
expectApplied("change target of target inline seperator to /", "Done.")
assert(_G.MSUF_DB.targettarget.totInlineSeparator == "/", "Dashboard Submit did not understand misspelled Target of Target inline separator")
_G.MSUF_DB.targettarget.totInlineSeparator = "|"
_G.MSUF_DB.targettarget.totInlineCustomSeparator = ""
expectApplied("change target inline separator to ->", "Done.")
assert(_G.MSUF_DB.targettarget.totInlineSeparator == "__CUSTOM__", "Dashboard Submit did not switch inline separator to Custom for freeform value")
assert(_G.MSUF_DB.targettarget.totInlineCustomSeparator == "->", "Dashboard Submit did not write inline custom separator")
_G.MSUF_DB.targettarget.showToTInTargetName = true
local inlineTextPrompt = submit("turn off target of target inline")
assert(inlineTextPrompt.status == "ambiguous", "Dashboard Submit did not suggest a choice for partial Target of Target inline text")
assert(tostring(inlineTextPrompt.text or ""):find("likely match", 1, true), "Dashboard Submit did not explain single suggested inline text choice")
assert(type(A.pendingChoices) == "table" and A.pendingChoices[1] and A.pendingChoices[1].setting.key == "targettarget.showToTInTargetName", "Dashboard Submit suggested wrong partial inline text setting")
expectApplied("1", "Done.")
assert(_G.MSUF_DB.targettarget.showToTInTargetName == false, "Dashboard Submit did not apply partial inline text suggestion")
_G.MSUF_DB.targettarget.showToTInTargetName = true
expectApplied("turn off target of target inline text", "Done.")
assert(_G.MSUF_DB.targettarget.showToTInTargetName == false, "Dashboard Submit regressed exact inline text command")
_G.MSUF_DB.player.hpOffsetY = -14
expectApplied("move player hp text up", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == -4, "Dashboard Submit did not move Player HP text up before contextual repeat")
expectApplied("more", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == 6, "Dashboard contextual 'more' did not repeat the previous Player HP text movement")
_G.MSUF_DB.target.powerOffsetY = 0
expectApplied("move target mana up 2", "Done.")
assert(_G.MSUF_DB.target.powerOffsetY == 2, "Dashboard Submit did not move Target power text up with mana shorthand")
_G.MSUF_DB.target.powerTextRight = "NONE"
expectApplied("create new mana text at target frame anchor right side with mana current max", "Done.")
assert(_G.MSUF_DB.target.powerTextRight == "CURMAX", "Dashboard Submit did not set Target right power text content")
M.activeKey = "uf_target"
_G.MSUF_DB.target.showPowerBar = true
_G.MSUF_DB.target.powerTextLeft = "CURRENT"
_G.MSUF_DB.target.powerTextCenter = "MAX"
_G.MSUF_DB.target.powerTextRight = "PERCENT"
expectApplied("turn off power bar", "Done.")
assert(_G.MSUF_DB.target.showPowerBar == false, "Target page context did not turn off Target power bar")
assert(_G.MSUF_DB.target.powerTextLeft == "CURRENT" and _G.MSUF_DB.target.powerTextCenter == "MAX" and _G.MSUF_DB.target.powerTextRight == "PERCENT", "Power bar command incorrectly changed Target power text slots")
_G.MSUF_DB.target.showPowerBar = true
expectApplied("turn off powerbar", "Done.")
assert(_G.MSUF_DB.target.showPowerBar == false, "Target page context did not normalize compact powerbar wording")
_G.MSUF_DB.target.powerBarHeight = 3
expectApplied("set power bar height to 8", "Done.")
assert(_G.MSUF_DB.target.powerBarHeight == 8, "Target page context did not set Target power bar height")
M.activeKey = "home"
_G.MSUF_DB.target.showPowerBar = true
expectApplied("turn off target power bar", "Done.")
assert(_G.MSUF_DB.target.showPowerBar == false, "Dashboard Submit did not turn off explicit Target power bar")
_G.MSUF_DB.target.powerBarHeight = 5
expectApplied("increase power bar hight target", "Done.")
assert(_G.MSUF_DB.target.powerBarHeight == 6, "Dashboard Submit did not increase Target power bar height with misspelled hight")
_G.MSUF_DB.bars.classPowerOutline = 2
_G.MSUF_DB.player.powerBarBorderEnabled = false
expectApplied("add for player power bar a border", "Player Power Bar Border")
assert(_G.MSUF_DB.player.powerBarBorderEnabled == true, "Dashboard Submit changed the wrong setting for Player Power Bar Border")
assert(_G.MSUF_DB.bars.classPowerOutline == 2, "Dashboard Submit changed Class Resource Outline for a Player Power Bar Border command")
_G.MSUF_DB.bars.showClassPower = true
_G.MSUF_DB.player.showPowerBar = true
expectApplied("no not class resource power bar player", "Player Power Bar")
assert(_G.MSUF_DB.player.showPowerBar == false, "Dashboard Submit did not route negated Class Resource correction to Player Power Bar")
assert(_G.MSUF_DB.bars.showClassPower == true, "Dashboard Submit disabled Class Resource after the user said not Class Resource")
_G.MSUF_DB.bars.classPowerOutline = 2
expectApplied("increase class resource outline", "Class Resource Outline")
assert(_G.MSUF_DB.bars.classPowerOutline == 3, "Dashboard Submit regressed explicit Class Resource Outline commands")
_G.MSUF_DB.target.powerBarDetached = false
expectApplied("detach target power bar", "Done.")
assert(_G.MSUF_DB.target.powerBarDetached == true, "Dashboard Submit did not detach Target power bar")
expectApplied("attach target power bar", "Done.")
assert(_G.MSUF_DB.target.powerBarDetached == false, "Dashboard Submit did not attach Target power bar back to frame")
_G.MSUF_DB.player.portraitMode = "LEFT"
_G.MSUF_DB.player.portraitOffsetX = 0
expectApplied("move player portrait closer to player unitframe", "Done.")
assert(_G.MSUF_DB.player.portraitOffsetX == 10, "Dashboard Submit did not move Player portrait closer to the frame")
expectApplied("move player portrait farther from player unitframe", "Done.")
assert(_G.MSUF_DB.player.portraitOffsetX == 0, "Dashboard Submit did not move Player portrait farther from the frame")
_G.MSUF_DB.player.detachedPowerBarOffsetX = 0
expectApplied("move player detached power bar right 5", "Done.")
assert(_G.MSUF_DB.player.detachedPowerBarOffsetX == 5, "Dashboard Submit routed detached power bar movement to the wrong setting")
_G.MSUF_DB.general.castbarTargetIconOffsetX = 0
expectApplied("move target castbar icon right 4", "Done.")
assert(_G.MSUF_DB.general.castbarTargetIconOffsetX == 4, "Dashboard Submit moved Target castbar instead of Target castbar icon")
_G.MSUF_DB.general.focusKickIconOffsetY = 0
expectApplied("move focus kick icon down 3", "Done.")
assert(_G.MSUF_DB.general.focusKickIconOffsetY == -3, "Dashboard Submit moved Focus frame instead of Focus Kick icon")
_G.MSUF_DB.bars.classPowerTextOffsetX = 0
expectApplied("move class resource text right 5", "Done.")
assert(_G.MSUF_DB.bars.classPowerTextOffsetX == 5, "Dashboard Submit moved Class Resource frame instead of Class Resource text")
_G.MSUF_DB.gf_raid.readyCheckY = 0
expectApplied("move raid ready check icon up 2", "Done.")
assert(_G.MSUF_DB.gf_raid.readyCheckY == 2, "Dashboard Submit did not move Raid ready check icon")
_G.MSUF_DB.gf_raid.groupNumberX = 0
expectApplied("move raid group number right 2", "Done.")
assert(_G.MSUF_DB.gf_raid.groupNumberX == 2, "Dashboard Submit did not move Raid group number")
_G.MSUF_DB.player.showPowerBar = true
_G.MSUF_DB.target.showPowerBar = true
_G.MSUF_DB.focus.showPowerBar = true
_G.MSUF_DB.boss.showPowerBar = true
_G.MSUF_DB.gf_party.powerBarEnabled = true
_G.MSUF_DB.gf_raid.powerBarEnabled = true
_G.MSUF_DB.gf_mythicraid.powerBarEnabled = true
_G.MSUF_DB.bars.smoothPowerBar = true
local humanBulkChange = expectApplied("turn off all power bars", "MSUF settings:")
assert(tostring(humanBulkChange.text or ""):find("1. ", 1, true), "Dashboard Assistant bulk success response did not list changed settings")
assert(tostring(humanBulkChange.text or ""):find("from enabled to disabled", 1, true), "Dashboard Assistant bulk success response did not explain changed values")
assert(_G.MSUF_DB.player.showPowerBar == false and _G.MSUF_DB.target.showPowerBar == false and _G.MSUF_DB.focus.showPowerBar == false and _G.MSUF_DB.boss.showPowerBar == false, "Dashboard Submit did not turn off all unit power bars")
assert(_G.MSUF_DB.gf_party.powerBarEnabled == false and _G.MSUF_DB.gf_raid.powerBarEnabled == false and _G.MSUF_DB.gf_mythicraid.powerBarEnabled == false, "Dashboard Submit did not turn off all group power bars")
assert(_G.MSUF_DB.bars.smoothPowerBar == true, "Dashboard Submit changed Smooth Power Bar instead of only root Power Bar visibility")
_G.MSUF_DB.gf_raid.hpOffsetY = 0
expectApplied("move raid health down 4", "Done.")
assert(_G.MSUF_DB.gf_raid.hpOffsetY == -4, "Dashboard Submit did not move Raid HP text down with health shorthand")
_G.MSUF_DB.gf_raid.hpOffsetX = 0
expectApplied("move raid frame hp text right 5", "Done.")
assert(_G.MSUF_DB.gf_raid.hpOffsetX == 5, "Dashboard Submit did not move Raid HP text right")
_G.MSUF_DB.gf_party.powerOffsetY = 0
expectApplied("move party power text up 3", "Done.")
assert(_G.MSUF_DB.gf_party.powerOffsetY == 3, "Dashboard Submit did not move Party power text up")
expectApplied("set party name y offset to -6", "Done.")
assert(_G.MSUF_DB.gf_party.nameOffsetY == -6, "Dashboard Submit did not set Party name Y offset")
expectApplied("set target mana x offset to 7", "Done.")
assert(_G.MSUF_DB.target.powerOffsetX == 7, "Dashboard Submit did not set Target power X offset")
expectApplied("set party power text size to 11", "Done.")
assert(_G.MSUF_DB.gf_party.powerFontSize == 11, "Dashboard Submit did not set Party power text font size")
_G.MSUF_DB.gf_party.powerTextLayer = 2
expectApplied("set party power text layer to 4", "Done.")
assert(_G.MSUF_DB.gf_party.powerTextLayer == 4, "Dashboard Submit did not set Party power text layer")
_G.MSUF_DB.gf_party.powerTextRightOffsetY = 0
expectApplied("move party power right text up 2", "Done.")
assert(_G.MSUF_DB.gf_party.powerTextRightOffsetY == 2, "Dashboard Submit did not move Party right power text slot up")
_G.MSUF_DB.gf_party.hpTextLeftOffsetY = 0
expectApplied("move party hp left text down 3", "Done.")
assert(_G.MSUF_DB.gf_party.hpTextLeftOffsetY == -3, "Dashboard Submit did not move Party left HP text slot down")
_G.MSUF_DB.gf_raid.powerTextRightOffsetY = 0
expectApplied("move raid right power label up 2", "Done.")
assert(_G.MSUF_DB.gf_raid.powerTextRightOffsetY == 2, "Dashboard Submit did not move Raid right power label up")
_G.MSUF_DB.gf_party.powerTextCenter = "NONE"
expectApplied("set party power center text to current percent", "Done.")
assert(_G.MSUF_DB.gf_party.powerTextCenter == "CURPERCENT", "Dashboard Submit did not set Party center power text slot content")
_G.MSUF_DB.gf_raid.textCenter = "NONE"
expectApplied("create new hp text at raid frame anchor center side with hp percent", "Done.")
assert(_G.MSUF_DB.gf_raid.textCenter == "PERCENT", "Dashboard Submit did not set Raid center HP text content")
_G.MSUF_DB.gf_party.alphaInCombat = 1
_G.MSUF_DB.gf_party.alphaOutOfCombat = 1
expectApplied("set party alpha to 50", "Done.")
assertNear(_G.MSUF_DB.gf_party.alphaInCombat, 0.5, "Dashboard Submit did not set Party in-combat opacity")
assertNear(_G.MSUF_DB.gf_party.alphaOutOfCombat, 0.5, "Dashboard Submit did not set Party out-of-combat opacity")
M.activeKey = "gf_bars"
M.gfScope = "raid"
_G.MSUF_DB.gf_raid.showName = true
_G.MSUF_DB.focus.showName = true
expectApplied("turn off name", "Done.")
expectApplied("do that for focus", "Done.")
assert(_G.MSUF_DB.focus.showName == false, "Dashboard follow-up did not map Raid group name change to Focus name")
M.activeKey = "gf_bars"
M.gfScope = "raid"
_G.MSUF_DB.gf_raid.alphaInCombat = 1
_G.MSUF_DB.gf_raid.alphaOutOfCombat = 1
expectApplied("set alpha to 60", "Done.")
assertNear(_G.MSUF_DB.gf_raid.alphaInCombat, 0.6, "Group page context did not set Raid in-combat opacity")
assertNear(_G.MSUF_DB.gf_raid.alphaOutOfCombat, 0.6, "Group page context did not set Raid out-of-combat opacity")
_G.MSUF_DB.gf_raid.powerBarEnabled = true
_G.MSUF_DB.gf_raid.powerTextLeft = "CURRENT"
_G.MSUF_DB.gf_raid.powerTextCenter = "PERCENT"
_G.MSUF_DB.gf_raid.powerTextRight = "MAX"
expectApplied("turn off power bar", "Done.")
assert(_G.MSUF_DB.gf_raid.powerBarEnabled == false, "Group page context did not turn off Raid power bar")
assert(_G.MSUF_DB.gf_raid.powerTextLeft == "CURRENT" and _G.MSUF_DB.gf_raid.powerTextCenter == "PERCENT" and _G.MSUF_DB.gf_raid.powerTextRight == "MAX", "Power bar command incorrectly changed Raid power text slots")
_G.MSUF_DB.gf_raid.powerHeight = 4
expectApplied("set power bar height to 9", "Done.")
assert(_G.MSUF_DB.gf_raid.powerHeight == 9, "Group page context did not set Raid power bar height")
M.activeKey = "home"
_G.MSUF_DB.gf_raid.powerBarEnabled = true
expectApplied("turn off raid power bar", "Done.")
assert(_G.MSUF_DB.gf_raid.powerBarEnabled == false, "Dashboard Submit did not turn off explicit Raid power bar")
_G.MSUF_DB.bars.smoothPowerBar = true
expectApplied("turn off smooth power bar", "Done.")
assert(_G.MSUF_DB.bars.smoothPowerBar == false, "Dashboard Submit did not turn off global Smooth Power Bar")
_G.MSUF_DB.player.showInterrupt = true
_G.MSUF_DB.target.showInterrupt = true
_G.MSUF_DB.focus.showInterrupt = true
_G.MSUF_DB.boss.showInterrupt = true
expectApplied("turn off for all castbars interrupt", "Done.")
assert(_G.MSUF_DB.player.showInterrupt == false and _G.MSUF_DB.target.showInterrupt == false and _G.MSUF_DB.focus.showInterrupt == false and _G.MSUF_DB.boss.showInterrupt == false, "Dashboard Submit did not turn off all unit castbar interrupt toggles")
_G.MSUF_DB.player.showInterrupt = true
_G.MSUF_DB.target.showInterrupt = true
_G.MSUF_DB.focus.showInterrupt = true
_G.MSUF_DB.boss.showInterrupt = true
expectApplied("turn off player target focus castbar interrupt", "Done.")
assert(_G.MSUF_DB.player.showInterrupt == false and _G.MSUF_DB.target.showInterrupt == false and _G.MSUF_DB.focus.showInterrupt == false, "Dashboard Submit did not turn off explicitly named castbar interrupt toggles")
assert(_G.MSUF_DB.boss.showInterrupt == true, "Dashboard Submit changed Boss castbar interrupt even though Boss was not requested")
_G.MSUF_DB.player.enabled = true
_G.MSUF_DB.gf_raid.showPlayer = true
_G.MSUF_DB.gf_raid.showSolo = false
local groupPlayerPrompt = submit("dont show player in group when solo")
assert(groupPlayerPrompt.status == "ambiguous", "Dashboard Submit should ask which group scope for player-in-group command")
assert(type(A.pendingChoices) == "table" and A.pendingChoices[2] and A.pendingChoices[2].setting.key == "gf_raid.showPlayer", "Dashboard Submit suggested wrong group player choices")
expectApplied("2", "Done.")
assert(_G.MSUF_DB.gf_raid.showPlayer == false, "Dashboard Submit did not apply Raid Show Player choice")
assert(_G.MSUF_DB.gf_raid.showSolo == false, "Dashboard Submit changed Show While Solo instead of Show Player")
assert(_G.MSUF_DB.player.enabled == true, "Dashboard Submit changed Player frame instead of group Show Player")
M.activeKey = "gf_layout"
M.gfScope = "party"
_G.MSUF_DB.player.enabled = true
_G.MSUF_DB.gf_party.showPlayer = true
_G.MSUF_DB.gf_party.showSolo = false
expectApplied("dont show player in group when solo", "Done.")
assert(_G.MSUF_DB.gf_party.showPlayer == false, "Group layout context did not apply Show Player for current Party scope")
assert(_G.MSUF_DB.gf_party.showSolo == false, "Group layout context changed Show While Solo instead of Show Player")
assert(_G.MSUF_DB.player.enabled == true, "Group layout context changed Player frame instead of group Show Player")
M.activeKey = "home"
_G.MSUF_DB.target.loadCondHideOutOfCombat = false
_G.MSUF_DB.target.enabled = true
expectApplied("change load condition from target frame to not show out of combat", "Target Hide Out Of Combat")
assert(_G.MSUF_DB.target.loadCondHideOutOfCombat == true, "Dashboard Submit did not enable Target Hide Out Of Combat load condition")
assert(_G.MSUF_DB.target.enabled == true, "Dashboard Submit changed Target Frame Enabled instead of the load condition")
expectApplied("show target frame out of combat", "Target Hide Out Of Combat")
assert(_G.MSUF_DB.target.loadCondHideOutOfCombat == false, "Dashboard Submit did not disable Target Hide Out Of Combat for a show-out-of-combat request")
_G.MSUF_DB.player.loadCondHideMounted = false
expectApplied("hide player frame when mounted", "Player Hide Mounted")
assert(_G.MSUF_DB.player.loadCondHideMounted == true, "Dashboard Submit did not enable Player Hide Mounted load condition")
_G.MSUF_DB.gf_raid.showSolo = false
expectApplied("change raid group load condition to show while solo", "Raid Show While Solo")
assert(_G.MSUF_DB.gf_raid.showSolo == true, "Dashboard Submit did not enable Raid Show While Solo from load-condition wording")
expectApplied("change raid group load condition to not show while solo", "Raid Show While Solo")
assert(_G.MSUF_DB.gf_raid.showSolo == false, "Dashboard Submit did not disable Raid Show While Solo from not-show wording")
expectStatus("change raid group load condition to hide out of combat", "info", "do not have a real load-condition")

_G.MSUF_UnitEditModeActive = false
_G.MSUF_UnitPreviewActive = false
_G.MSUF2_GFPagePreviewActive = nil
_G.MSUF2_GFPagePreviewKind = nil
M.gfScope = "party"
MSUF._gfPreviewShown = false
local outsidePreviewEMShowCount = MSUF._gfPreviewShowCount or 0
expectApplied("turn on raid frame preview", "outside Edit Mode")
assert(M.gfScope == "raid", "Dashboard Submit did not select Raid scope for Raid frame preview")
assert(M.activeKey == "gf_layout", "Dashboard Submit did not open Group Layout for Raid frame preview outside Edit Mode")
assert(_G.MSUF2_GFPagePreviewActive == true and _G.MSUF2_GFPagePreviewKind == "raid", "Dashboard Submit did not enable Raid Group Frame page preview outside Edit Mode")
assert(_G.MSUF_UnitPreviewActive == false, "Dashboard Submit toggled Unit/Edit Mode preview instead of Raid Group Frame preview")
assert((MSUF._gfPreviewShowCount or 0) == outsidePreviewEMShowCount, "Dashboard Submit used the Edit Mode Group Preview bridge while Edit Mode was off")
expectApplied("turn off raid frame preview", "outside Edit Mode")
assert(_G.MSUF2_GFPagePreviewActive == nil, "Dashboard Submit did not disable Raid Group Frame page preview outside Edit Mode")

_G.MSUF_UnitEditModeActive = true
M.gfScope = "party"
MSUF._gfPreviewShown = false
local editPreviewEMShowCount = MSUF._gfPreviewShowCount or 0
expectApplied("turn on raid frame preview", "in Edit Mode")
assert(M.gfScope == "raid", "Dashboard Submit did not keep Raid scope for Raid frame preview in Edit Mode")
assert(MSUF._gfPreviewShown == true, "Dashboard Submit did not use the Edit Mode Group Preview bridge while Edit Mode was on")
assert((MSUF._gfPreviewShowCount or 0) > editPreviewEMShowCount, "Dashboard Submit did not show the Edit Mode Group Preview")

_G.MSUF_DB.auras3.shared.showInEditMode = true
expectApplied("in edit mode turn off preview auras", "Done.")
assert(_G.MSUF_DB.auras3.shared.showInEditMode == false, "Dashboard Submit did not turn off Edit Mode Auras preview")
assert((MSUF._auraEditPreview or 0) > 0 and (MSUF._auraRefreshAll or 0) > 0, "Dashboard Submit did not refresh Auras edit preview after toggling the HUD control")
_G.MSUF_UnitPreviewActive = true
expectApplied("turn off edit mode preview", "Done.")
assert(_G.MSUF_UnitPreviewActive == false, "Dashboard Submit did not turn off Edit Mode unit preview")
assert((MSUF._unitPreviewSync or 0) > 0, "Dashboard Submit did not sync unit previews after toggling Edit Mode Preview")
MSUF._gfPreviewShown = true
expectApplied("turn off edit mode gf preview", "Done.")
assert(MSUF._gfPreviewShown == false and (MSUF._gfPreviewHideCount or 0) > 0, "Dashboard Submit did not hide Edit Mode Group Frames preview")
_G.MSUF_EM2.Snap._enabled = false
expectApplied("turn on edit mode snap", "Done.")
assert(_G.MSUF_EM2.Snap._enabled == true, "Dashboard Submit did not turn on Edit Mode Snap")
_G.MSUF_DB.general.anchorToCooldown = false
expectApplied("turn on edit mode cdm", "Done.")
assert(_G.MSUF_DB.general.anchorToCooldown == true, "Dashboard Submit did not turn on Edit Mode CDM anchor")
assert((MSUF._editApplyAll or 0) > 0 and (MSUF._editMoverSync or 0) > 0, "Dashboard Submit did not apply and sync after Edit Mode CDM change")
_G.MSUF_DB.target.offsetX = 12
_G.MSUF_DB.target.offsetY = -8
expectApplied("reset selected edit mode frame position", "Done.")
assert((MSUF._editResetPosition or 0) > 0, "Dashboard Submit did not call Edit Mode HUD reset helper")
assert(_G.MSUF_DB.target.offsetX == 0 and _G.MSUF_DB.target.offsetY == 0, "Dashboard Submit did not reset selected Edit Mode frame position")
expectApplied("open edit mode anchor picker", "Opened")
assert((MSUF._anchorPickerOpened or 0) > 0, "Dashboard Submit did not open the Edit Mode Anchor picker")
assert(type(MSUF._anchorPickerOverlay) == "table" and type(MSUF._anchorPickerOverlay._onPick) == "function", "Dashboard Submit did not wire the Edit Mode Anchor picker callback")
MSUF._anchorPickerOverlay._onPick("MSUF_TestAnchorFrame")
assert(_G.MSUF_DB.general.anchorName == "MSUF_TestAnchorFrame", "Edit Mode Anchor picker callback did not write the global anchor frame")
assert(_G.MSUF_DB.general.anchorToCooldown == false, "Edit Mode Anchor picker callback did not disable CDM anchoring")

expectApplied("how do i move the player frame", "Edit Mode")
expectApplied("search castbar texture", "I found")
expectApplied("where is castbar texture", "MSUF")
expectApplied("how do profiles work", "Profiles help")
expectApplied("profil hilfe", "Profiles help")
expectApplied("what can i change here")
expectApplied("help")
local firstJoke = expectStatus("tell me a joke", "info", "unit frame")
local secondJoke = expectStatus("tell me another joke", "info", "castbar")
assert(firstJoke.text ~= secondJoke.text, "Assistant repeated the same joke for another-joke request")
local typoJoke = expectStatus("tell me antoher joke", "info", "healer")
assert(typoJoke.text ~= secondJoke.text, "Assistant did not advance joke rotation for typo another-joke request")
expectStatus("noch einen witz", "info", "Unit Frame")
expectStatus("can we talk normal", "info", "local MSUF Assistant")
expectStatus("can you help me to get better at wow", "info", "https://www.wowhead.com/guides")
expectStatus("wie werde ich besser in wow", "info", "Wowhead")
expectStatus("how are you?", "info", "ready to help with MSUF")
expectStatus("how are yuo?", "info", "ready to help with MSUF")
expectStatus("I found a bug", "info", "https://discord.gg/2Gf9b2Wprz")
expectStatus("I found a bgu", "info", "https://discord.gg/2Gf9b2Wprz")
expectStatus("where do I report felher", "info", "https://discord.gg/2Gf9b2Wprz")
expectStatus("where do I report bugs", "info", "https://www.curseforge.com/wow/addons/midnightsimpleunitframes")
expectStatus("wo kann ich fehler melden", "info", "MSUF CurseForge-Seite")
expectStatus("search zzzqqq yyyxxx", "info", "https://discord.gg/2Gf9b2Wprz")
expectStatus("flibbertigibbet", "info", "https://discord.gg/2Gf9b2Wprz")
expectApplied("diagnose profiles", "Profile diagnostic:")
expectApplied("diagnose class resources", "Class Resources diagnostic:")
expectApplied("diagnose dashboard setup", "Dashboard setup diagnostic:")
_G.MSUF_DB.bars.classPowerOffsetY = 0
expectApplied("move class resource down 5", "Done.")
assert(_G.MSUF_DB.bars.classPowerOffsetY == -5, "Dashboard Submit did not move Class Resource down")
M.activeKey = "classpower"
_G.MSUF_DB.bars.classPowerWidthMode = "player"
expectApplied("set width mode to custom", "Done.")
assert(_G.MSUF_DB.bars.classPowerWidthMode == "custom", "Class Resource page context did not set width mode")
_G.MSUF_DB.bars.classPowerBgAlpha = 0.3
expectApplied("set background opacity to 40", "Done.")
assertNear(_G.MSUF_DB.bars.classPowerBgAlpha, 0.4, "Class Resource page context did not set background opacity")
_G.MSUF_DB.bars.classPowerShowPrediction = true
expectApplied("turn off prediction", "Done.")
assert(_G.MSUF_DB.bars.classPowerShowPrediction == false, "Class Resource page context did not turn off prediction")
M.activeKey = "home"
_G.MSUF_DB.bars.altManaHeight = 4
expectApplied("set alt mana height to 12", "Done.")
assert(_G.MSUF_DB.bars.altManaHeight == 12, "Dashboard Submit did not set Alternative Mana height")
M.activeKey = "home"
_G.MSUF_DB.target.rangeFadeAlpha = 0.4
expectApplied("set target range fade alpha to 30", "Done.")
assertNear(_G.MSUF_DB.target.rangeFadeAlpha, 0.3, "Dashboard Submit did not set Target range fade alpha")
_G.MSUF_DB.target.rangeFadeLayerMode = "frame"
expectApplied("set target range fade affects health", "Done.")
assert(_G.MSUF_DB.target.rangeFadeLayerMode == "health", "Dashboard Submit did not set Target range fade layer mode")
_G.MSUF_DB.general.unitDispelOverlayEnabled = false
expectApplied("turn on unitframe dispel overlay", "Done.")
assert(_G.MSUF_DB.general.unitDispelOverlayEnabled == true, "Dashboard Submit did not enable shared UnitFrame Dispel Overlay")
_G.MSUF_DB.general.unitDispelOverlayTrigger = "BORDER"
expectApplied("set unitframe dispel overlay detects any debuff", "Done.")
assert(_G.MSUF_DB.general.unitDispelOverlayTrigger == "ANY_DEBUFF", "Dashboard Submit did not set shared UnitFrame Dispel Overlay trigger")
_G.MSUF_DB.general.unitDispelOverlayStyle = "FULL"
expectApplied("set unitframe dispel overlay style top", "Done.")
assert(_G.MSUF_DB.general.unitDispelOverlayStyle == "TOP", "Dashboard Submit did not set shared UnitFrame Dispel Overlay style")
_G.MSUF_DB.general.unitDispelOverlayOnHealth = true
expectApplied("turn off unitframe dispel overlay current health only", "Done.")
assert(_G.MSUF_DB.general.unitDispelOverlayOnHealth == false, "Dashboard Submit did not disable shared UnitFrame Dispel Overlay current-health mode")
_G.MSUF_DB.general.unitDispelOverlayAlpha = 0.35
expectApplied("set unitframe dispel overlay opacity to 45", "Done.")
assertNear(_G.MSUF_DB.general.unitDispelOverlayAlpha, 0.45, "Dashboard Submit did not set shared UnitFrame Dispel Overlay opacity")
_G.MSUF_DB.target.hlOverride = false
_G.MSUF_DB.target.unitDispelOverlayAlpha = 0.35
expectApplied("set only target unitframe dispel overlay opacity to 40", "Done.")
assert(_G.MSUF_DB.target.hlOverride == true, "Scoped UnitFrame Dispel Overlay command did not enable Target bars override")
assertNear(_G.MSUF_DB.target.unitDispelOverlayAlpha, 0.4, "Dashboard Submit did not set scoped Target UnitFrame Dispel Overlay opacity")
_G.MSUF_DB.target.fontOverride = false
_G.MSUF_DB.target.colorPowerTextByType = false
expectApplied("only turn on color text by power for target", "Done.")
assert(_G.MSUF_DB.target.fontOverride == true, "Scoped Power Text Color command did not enable Target font override")
assert(_G.MSUF_DB.target.colorPowerTextByType == true, "Dashboard Submit did not set Target Power Text Color to Resource")
expectApplied("turn off color text by power for target", "Done.")
assert(_G.MSUF_DB.target.colorPowerTextByType == false, "Dashboard Submit did not reset Target Power Text Color to Font Color")
M.activeKey = "gameplay"
_G.MSUF_DB.gameplay.enableCombatTimer = false
expectApplied("turn on timer", "Done.")
assert(_G.MSUF_DB.gameplay.enableCombatTimer == true, "Gameplay page context did not enable Combat Timer")
assert(MSUF._lastGameplayApply == "MSUF_ASSISTANT_COMBAT_TIMER", "Gameplay enable did not request gameplay apply")
_G.MSUF_DB.gameplay.combatOffsetY = 0
expectApplied("move timer down 5", "Done.")
assert(_G.MSUF_DB.gameplay.combatOffsetY == -5, "Gameplay page context did not move Combat Timer down")
expectApplied("set timer anchor to target", "Done.")
assert(_G.MSUF_DB.gameplay.combatTimerAnchor == "target", "Gameplay page context did not set Combat Timer anchor")
_G.MSUF_DB.gameplay.combatFontSize = 24
expectApplied("set combat timer size to 32", "Done.")
assert(_G.MSUF_DB.gameplay.combatFontSize == 32, "Dashboard Submit did not set Combat Timer size")
_G.MSUF_DB.gameplay.combatTimerClickThrough = false
expectApplied("turn on combat timer click through", "Done.")
assert(_G.MSUF_DB.gameplay.combatTimerClickThrough == true, "Dashboard Submit did not set Combat Timer click-through")
_G.MSUF_DB.gameplay.enableCombatStateText = false
expectApplied("turn on combat enter leave text", "Done.")
assert(_G.MSUF_DB.gameplay.enableCombatStateText == true, "Dashboard Submit did not enable Combat Enter Leave text")
_G.MSUF_DB.gameplay.combatStateOffsetY = 0
expectApplied("move combat enter leave text up 8", "Done.")
assert(_G.MSUF_DB.gameplay.combatStateOffsetY == 8, "Dashboard Submit did not move Combat Enter Leave text up")
expectApplied("set combat state duration to 2.5", "Done.")
assertNear(_G.MSUF_DB.gameplay.combatStateDuration, 2.5, "Dashboard Submit did not set Combat State duration")
expectApplied("set combat enter text to Pulling", "Done.")
assert(_G.MSUF_DB.gameplay.combatStateEnterText == "Pulling", "Dashboard Submit did not set Combat Enter text")
_G.MSUF_DB.gameplay.enablePlayerTotems = false
expectApplied("turn on totem frame", "Done.")
assert(_G.MSUF_DB.gameplay.enablePlayerTotems == true, "Dashboard Submit did not enable Totem Frame")
_G.MSUF_DB.gameplay.playerTotemsOffsetX = 0
expectApplied("move totem frame right 6", "Done.")
assert(_G.MSUF_DB.gameplay.playerTotemsOffsetX == 6, "Dashboard Submit did not move Totem Frame right")
_G.MSUF_DB.gameplay.playerTotemsAnchorTo = "TOP"
expectApplied("set totem frame to anchor to bottom left", "Done.")
assert(_G.MSUF_DB.gameplay.playerTotemsAnchorTo == "BOTTOMLEFT", "Dashboard Submit did not set Totem Frame anchor-to")
_G.MSUF_DB.gameplay.enableFirstDanceTimer = false
expectApplied("turn on first dance", "Done.")
assert(_G.MSUF_DB.gameplay.enableFirstDanceTimer == true, "Dashboard Submit did not enable First Dance")
_G.MSUF_DB.gameplay.firstDanceOffsetY = 0
expectApplied("move first dance down 12", "Done.")
assert(_G.MSUF_DB.gameplay.firstDanceOffsetY == -12, "Dashboard Submit did not move First Dance down")
_G.MSUF_DB.gameplay.firstDanceShowReady = true
expectApplied("turn off first dance ready", "Done.")
assert(_G.MSUF_DB.gameplay.firstDanceShowReady == false, "Dashboard Submit did not disable First Dance ready visibility")
_G.MSUF_DB.gameplay.enableCombatCrosshair = false
expectApplied("turn on combat crosshair", "Done.")
assert(_G.MSUF_DB.gameplay.enableCombatCrosshair == true, "Dashboard Submit did not enable Combat Crosshair")
expectApplied("set crosshair size to 44", "Done.")
assert(_G.MSUF_DB.gameplay.crosshairSize == 44, "Dashboard Submit did not set Crosshair size")
_G.MSUF_DB.gameplay.crosshairThickness = 3
expectApplied("make crosshair thicker by 2", "Done.")
assert(_G.MSUF_DB.gameplay.crosshairThickness == 5, "Dashboard Submit did not make Crosshair thicker")
_G.MSUF_DB.gameplay.enableCombatCrosshairMeleeRangeColor = false
expectApplied("turn on crosshair range color", "Done.")
assert(_G.MSUF_DB.gameplay.enableCombatCrosshairMeleeRangeColor == true, "Dashboard Submit did not enable Crosshair range color")
expectStatus("move crosshair down 5", "failed", "position is not exposed")
M.activeKey = "home"

expectApplied("collapse frames navigation section", "Closed Frames navigation section.")
assert(M.navHeaderState.unitframes == false, "NavRail frames section did not collapse")
assert((MSUF._navReflowed or 0) > 0, "NavRail section action did not reflow")
expectApplied("open group frames navigation section", "Opened Group Frames navigation section.")
assert(M.navHeaderState.groupframes == true, "NavRail group frames section did not open")
M.searchIntroSeen = true
expectApplied("reset search intro", "Search intro")
assert(M.searchIntroSeen == false, "Search intro reset did not clear seen state")
expectApplied("show search intro", "Search intro")
assert(M.searchIntroSeen == false, "Search intro fallback should remain pending when the NavRail UI is not built")

A.Workflow.navStack = {}
M.activeKey = "home"
expectApplied("oeffne spieler", "Opened Player")
assert(M.activeKey == "uf_player", "German open Player did not select Player page")
M.activeKey = "home"
expectApplied("open player", "Opened Player")
assert(M.activeKey == "uf_player", "Open player did not select Player page")
expectApplied("open target", "Opened Target")
assert(M.activeKey == "uf_target", "Open target did not select Target page")
expectApplied("back", "Opened previous page.")
assert(M.activeKey == "uf_player", "Dashboard back did not return to previous Assistant-opened page")
expectApplied("open previous page", "Opened previous page.")
assert(M.activeKey == "home", "Dashboard back did not return to Dashboard page")

expectApplied("turn on class color mode for raidframe", "Done.")
assert(_G.MSUF_DB.gf_raid.gfBarMode == "CLASS", "Raid frame class color mode did not set gf_raid.gfBarMode")
assert(_G.MSUF_DB.gf_raid.healthColorMode == "CLASS", "Raid frame class color mode did not sync healthColorMode")
_G.MSUF_DB.gf_party.gfBarMode = "CUSTOM"
_G.MSUF_DB.gf_raid.gfBarMode = "CUSTOM"
_G.MSUF_DB.gf_mythicraid.gfBarMode = "CUSTOM"
expectApplied("turn on class color mode for group frames", "Done.")
assert(_G.MSUF_DB.gf_party.gfBarMode == "CLASS", "Group frames class color mode did not set party")
assert(_G.MSUF_DB.gf_raid.gfBarMode == "CLASS", "Group frames class color mode did not set raid")
assert(_G.MSUF_DB.gf_mythicraid.gfBarMode == "CLASS", "Group frames class color mode did not set mythic raid")
_G.MSUF_DB.gf_raid.anchorToFrame = "FREE"
expectApplied("set raid anchor to target", "Done.")
assert(_G.MSUF_DB.gf_raid.anchorToFrame == "target", "Dashboard Submit changed Target unit anchoring instead of Raid group Anchor To")
_G.MSUF_DB.gf_raid.growth = "DOWN"
expectApplied("set raid frames to grow right", "Done.")
assert(_G.MSUF_DB.gf_raid.growth == "RIGHT", "Dashboard Submit did not understand natural Raid growth wording")
_G.MSUF_DB.gf_raid.frameScaleManual = 100
expectApplied("set raid scale to 90", "Done.")
assert(_G.MSUF_DB.gf_raid.frameScaleManual == 90, "Dashboard Submit did not set Raid manual frame scale")
_G.MSUF_DB.gf_raid.scaleAt10 = 80
expectApplied("set raid scale at 10 to 95", "Done.")
assert(_G.MSUF_DB.gf_raid.scaleAt10 == 95, "Dashboard Submit used the breakpoint label number instead of the requested Scale 1-10 value")
_G.MSUF_DB.gf_raid.scaleAt20 = 85
expectApplied("set raid 11-20 player scale to 80", "Done.")
assert(_G.MSUF_DB.gf_raid.scaleAt20 == 80, "Dashboard Submit used the range label number instead of the requested Scale 11-20 value")
_G.MSUF_DB.gf_raid.scaleAt10 = 90
expectApplied("increase raid scale at 10 by 5", "Done.")
assert(_G.MSUF_DB.gf_raid.scaleAt10 == 95, "Dashboard Submit did not use the explicit relative value for Scale 1-10")
_G.MSUF_DB.gf_raid.bgA = 0.85
expectApplied("set raid backdrop opacity to 50", "Done.")
assertNear(_G.MSUF_DB.gf_raid.bgA, 0.5, "Dashboard Submit did not route Raid backdrop opacity to the registered Group Layout slider")
_G.MSUF_DB.gf_raid.hpBarAlpha = 1
expectApplied("set raid hp fill opacity to 75", "Done.")
assertNear(_G.MSUF_DB.gf_raid.hpBarAlpha, 0.75, "Dashboard Submit did not route Raid HP fill opacity to the registered Group Layout slider")
_G.MSUF_DB.gf_raid.hpBgAlpha = 1
expectApplied("set raid hp track opacity to 25", "Done.")
assertNear(_G.MSUF_DB.gf_raid.hpBgAlpha, 0.25, "Dashboard Submit did not route Raid HP track opacity to the registered Group Layout slider")
_G.MSUF_DB.gf_raid.dispelOverlayEnabled = false
expectApplied("turn on raid dispel overlay", "Done.")
assert(_G.MSUF_DB.gf_raid.dispelOverlayEnabled == true, "Dashboard Submit did not enable Raid Dispel Overlay")
_G.MSUF_DB.gf_raid.dispelOverlayTrigger = "BORDER"
expectApplied("set raid dispel overlay detects any debuff", "Done.")
assert(_G.MSUF_DB.gf_raid.dispelOverlayTrigger == "ANY_DEBUFF", "Dashboard Submit did not set Raid Dispel Overlay trigger")
_G.MSUF_DB.gf_raid.dispelOverlayStyle = "FULL"
expectApplied("set raid dispel overlay style bottom", "Done.")
assert(_G.MSUF_DB.gf_raid.dispelOverlayStyle == "BOTTOM", "Dashboard Submit did not set Raid Dispel Overlay style")
_G.MSUF_DB.gf_raid.dispelOverlayOnHealth = true
expectApplied("turn off raid dispel overlay current health only", "Done.")
assert(_G.MSUF_DB.gf_raid.dispelOverlayOnHealth == false, "Dashboard Submit did not disable Raid Dispel Overlay current-health mode")
_G.MSUF_DB.gf_raid.dispelOverlayAlpha = 0.35
expectApplied("set raid dispel overlay opacity to 55", "Done.")
assertNear(_G.MSUF_DB.gf_raid.dispelOverlayAlpha, 0.55, "Dashboard Submit did not set Raid Dispel Overlay opacity")
expectApplied("set player border color to rgb 255 128 0", "Done.")
assertNear(_G.MSUF_DB.player.barOutlineColorR, 1, "Player bar outline red")
assertNear(_G.MSUF_DB.player.barOutlineColorG, 128 / 255, "Player bar outline green")
assertNear(_G.MSUF_DB.player.barOutlineColorB, 0, "Player bar outline blue")
expectApplied("same for target", "Done.")
assertNear(_G.MSUF_DB.target.barOutlineColorR, 1, "Target bar outline replay red")
assertNear(_G.MSUF_DB.target.barOutlineColorG, 128 / 255, "Target bar outline replay green")
assertNear(_G.MSUF_DB.target.barOutlineColorB, 0, "Target bar outline replay blue")
expectApplied("change the interrupt castbar color to blue", "Done.")
assertNear(_G.MSUF_DB.general.castbarInterruptibleR, 0, "Interruptible cast color red")
assertNear(_G.MSUF_DB.general.castbarInterruptibleG, 0, "Interruptible cast color green")
assertNear(_G.MSUF_DB.general.castbarInterruptibleB, 1, "Interruptible cast color blue")
expectStatus("change the interrupt color to blue", "ambiguous", "Interruptible Cast Color")
assert(_G.MSUF_DB.general.castbarInterruptFeedbackR == nil, "Plain interrupt color should not silently change feedback color")
expectApplied("3", "Done.")
assertNear(_G.MSUF_DB.general.castbarInterruptFeedbackR, 0, "Interrupt feedback color red")
assertNear(_G.MSUF_DB.general.castbarInterruptFeedbackG, 0, "Interrupt feedback color green")
assertNear(_G.MSUF_DB.general.castbarInterruptFeedbackB, 1, "Interrupt feedback color blue")
expectApplied("change non interruptible castbar color to blue", "Done.")
assertNear(_G.MSUF_DB.general.castbarNonInterruptibleR, 0, "Non-interruptible cast color red")
assertNear(_G.MSUF_DB.general.castbarNonInterruptibleG, 0, "Non-interruptible cast color green")
assertNear(_G.MSUF_DB.general.castbarNonInterruptibleB, 1, "Non-interruptible cast color blue")
expectApplied("change raid group border color to blue", "Done.")
assertNear(_G.MSUF_DB.gf_raid.groupBorderR, 0, "Raid group border red")
assertNear(_G.MSUF_DB.gf_raid.groupBorderG, 0, "Raid group border green")
assertNear(_G.MSUF_DB.gf_raid.groupBorderB, 1, "Raid group border blue")
expectApplied("change party health bar color to blue", "Done.")
assert(_G.MSUF_DB.gf_party.gfBarMode == "CUSTOM", "Party health color should switch the editable group bar mode to CUSTOM")
assert(_G.MSUF_DB.gf_party.healthColorMode == "CUSTOM", "Party health color should switch healthColorMode to CUSTOM")
assertNear(_G.MSUF_DB.gf_party.healthCustomR, 0, "Party health color red")
assertNear(_G.MSUF_DB.gf_party.healthCustomG, 0, "Party health color green")
assertNear(_G.MSUF_DB.gf_party.healthCustomB, 1, "Party health color blue")
expectApplied("change mythic raid focus highlight color to blue", "Done.")
assertNear(_G.MSUF_DB.gf_mythicraid.hlFocusColorR, 0, "Mythic Raid focus highlight red")
assertNear(_G.MSUF_DB.gf_mythicraid.hlFocusColorG, 0, "Mythic Raid focus highlight green")
assertNear(_G.MSUF_DB.gf_mythicraid.hlFocusColorB, 1, "Mythic Raid focus highlight blue")
expectStatus("change group frame health color to blue", "ambiguous", "Party Health Bar Color")
expectStatus("none", "info", "Cancelled")
_G.MSUF_DB.general.darkBarGray = 0.07
expectApplied("make unitframe dark mode a bit lighter", "Done.")
assert(_G.MSUF_DB.general.darkBarGray == 0.10, "Dark mode lighter command did not increase darkBarGray")
expectApplied("make unitframe dark mode super dark", "Done.")
assert(_G.MSUF_DB.general.darkBarGray == 0.01, "Dark mode super dark command did not set darkBarGray")
expectApplied("make unitframe dark mode 20 percent", "Done.")
assert(_G.MSUF_DB.general.darkBarGray == 0.20, "Dark mode percent command did not set darkBarGray")
expectApplied("make unitframe dark mode darker by 5", "Done.")
assert(_G.MSUF_DB.general.darkBarGray == 0.15, "Dark mode relative darker command did not decrease darkBarGray")
_G.MSUF_DB.bars.barOutlineThickness = 1
expectApplied("set global bar outline thickness to 2", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 2, "Dashboard Submit did not set global bar outline thickness")
expectApplied("more", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 3, "Dashboard follow-up 'more' did not increase the previous numeric setting")
expectApplied("bigger", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 4, "Dashboard follow-up 'bigger' did not increase the previous numeric setting")
expectApplied("smaller", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 3, "Dashboard follow-up 'smaller' did not decrease the previous numeric setting")
expectApplied("higher by 2", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 5, "Dashboard follow-up with explicit amount did not use the last numeric setting")
expectApplied("make it 6", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 6, "Dashboard follow-up exact value did not use the previous numeric setting")
expectApplied("a little less", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 5, "Dashboard follow-up 'a little less' did not decrease by a small contextual step")
expectApplied("max", "Done.")
assert(_G.MSUF_DB.bars.barOutlineThickness == 8, "Dashboard follow-up 'max' did not set the previous numeric setting to max")
expectStatus("what did you change", "info", "Global Bar Outline Thickness")
expectApplied("set only player bar outline thickness to 3", "Done.")
assert(_G.MSUF_DB.player.hlOverride == true, "Scoped player bar outline command did not enable player bar override")
assert(_G.MSUF_DB.player.barOutlineThickness == 3, "Scoped player bar outline command did not set player outline")
_G.MSUF_DB.gf_party.hlOverride = false
_G.MSUF_DB.gf_party.barOutlineThickness = 1
expectApplied("same for party", "Done.")
assert(_G.MSUF_DB.gf_party.hlOverride == true, "Dashboard follow-up did not replay scoped bar override to Party")
assert(_G.MSUF_DB.gf_party.barOutlineThickness == 3, "Dashboard follow-up did not replay scoped bar outline to Party")
expectApplied("set player custom anchor frame to PlayerFrame", "Done.")
assert(_G.MSUF_DB.player.anchorFrameName == "PlayerFrame", "Player custom anchor frame did not set anchorFrameName")
assert(_G.MSUF_DB.player.anchorToUnitframe == "GLOBAL", "Player custom anchor frame did not force global anchor mode")
expectApplied("set raid custom anchor to CompactRaidFrame1", "Done.")
assert(_G.MSUF_DB.gf_raid.anchorToFrame == "CompactRaidFrame1", "Raid custom anchor frame did not set anchorToFrame")

_G.MSUF_DB.player.hpOffsetX = 0
_G.MSUF_DB.player.hpOffsetY = 0
expectApplied("move player hp text up", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == 10, "Dashboard Submit did not move Player HP text up")
expectApplied("more", "Done.")
assert(_G.MSUF_DB.player.hpOffsetY == 20, "Dashboard follow-up 'more' did not repeat Player HP text movement")
expectApplied("revert that", "Reverted")
assert(_G.MSUF_DB.player.hpOffsetY == 10, "Dashboard Assistant did not undo the previous natural-language follow-up change")
expectApplied("redo that", "Reapplied")
assert(_G.MSUF_DB.player.hpOffsetY == 20, "Dashboard Assistant did not redo the reverted natural-language follow-up change")
expectApplied("left", "Done.")
assert(_G.MSUF_DB.player.hpOffsetX == -10, "Dashboard follow-up 'left' did not switch Player HP text movement to X offset")
expectApplied("opposite", "Done.")
assert(_G.MSUF_DB.player.hpOffsetX == 0, "Dashboard follow-up 'opposite' did not reverse the previous Player HP text movement")

expectApplied("select player hp left slot", "Selected Player HP Text left slot.")
assert(M.activeKey == "uf_player", "Unit text selector did not open player page")
assert(M.unitTextTabSelection.player == "hp", "Unit text selector did not select HP tab")
assert(M.unitTextSlotSelection.player.hp == "left", "Unit text selector did not select left slot")
_G.MSUF_DB.player.textLeft = "NONE"
expectApplied("change it to only %", "Done.")
assert(_G.MSUF_DB.player.textLeft == "PERCENT", "Selected text slot context did not set Player HP left slot to Percent")
expectApplied("now make it max hp", "Done.")
assert(_G.MSUF_DB.player.textLeft == "MAX", "Selected text slot context did not update Player HP left slot to Max")
expectApplied("set player hp text anchor to right", "Selected Player HP Text right slot.")
assert(M.activeKey == "uf_player", "Unit text anchor alias did not open player page")
assert(M.unitTextTabSelection.player == "hp", "Unit text anchor alias did not select HP tab")
assert(M.unitTextSlotSelection.player.hp == "right", "Unit text anchor alias did not select right slot")
expectApplied("align player hp text left", "Selected Player HP Text left slot.")
assert(M.activeKey == "uf_player", "Unit text align alias did not open player page")
assert(M.unitTextTabSelection.player == "hp", "Unit text align alias did not select HP tab")
assert(M.unitTextSlotSelection.player.hp == "left", "Unit text align alias did not select left slot")
expectApplied("select party power text right slot", "Selected Party Power Text right slot.")
assert(M.activeKey == "gf_bars", "Group text selector did not open Group Health & Text")
assert(M.gfScope == "party", "Group text selector did not set party scope")
assert(M.gfTextTabSelection.party == "power", "Group text selector did not select power tab")
assert(M.gfTextSlotSelection.party.power == "right", "Group text selector did not select right slot")
expectApplied("set party power text anchor to left", "Selected Party Power Text left slot.")
assert(M.activeKey == "gf_bars", "Group text anchor alias did not open Group Health & Text")
assert(M.gfScope == "party", "Group text anchor alias did not set party scope")
assert(M.gfTextTabSelection.party == "power", "Group text anchor alias did not select power tab")
assert(M.gfTextSlotSelection.party.power == "left", "Group text anchor alias did not select left slot")
expectApplied("put party power text on right", "Selected Party Power Text right slot.")
assert(M.activeKey == "gf_bars", "Group text put alias did not open Group Health & Text")
assert(M.gfScope == "party", "Group text put alias did not set party scope")
assert(M.gfTextTabSelection.party == "power", "Group text put alias did not select power tab")
assert(M.gfTextSlotSelection.party.power == "right", "Group text put alias did not select right slot")
expectApplied("turn off party hp move text as one group", "Set Party HP Text move text as one group off.")
assert(M.gfTextMoveTogether.party.hp == false, "Group text move-together selector did not set party HP per-slot mode")
M.gfTextMoveTogether.party.hp = true
expectApplied("use individual party hp text units", "Set Party HP Text move text as one group off.")
assert(M.gfTextMoveTogether.party.hp == false, "Group text move-together selector did not understand individual text units")
expectApplied("set player power text per slot", "Set Player Power Text move text as one group off.")
assert(M.unitTextMoveTogether.player.power == false, "Unit text move-together selector did not set player power per-slot mode")
M.unitTextMoveTogether.player.power = true
expectApplied("use individual player power text units", "Set Player Power Text move text as one group off.")
assert(M.unitTextMoveTogether.player.power == false, "Unit text move-together selector did not understand individual text units")
expectApplied("select target advanced status tab", "Selected Target Advanced status tab.")
assert(M.activeKey == "uf_target", "Unit status selector did not open target page")
assert(M.unitStatusTabSelection.target == "advanced", "Unit status selector did not select advanced tab")
MSUF._statusRefresh = 0
_G.MSUF_DB.target.stateIconsTestMode = false
expectApplied("show test status icons on target frame", "Done.")
assert(_G.MSUF_DB.target.stateIconsTestMode == true, "Dashboard Submit did not enable Target Status Icon Test Mode")
assert((MSUF._statusRefresh or 0) > 0, "Dashboard Submit did not refresh status icons after enabling Target test mode")
local firstStatusRefresh = MSUF._statusRefresh or 0
expectApplied("show test status icons on target frame", "Already set.")
assert((MSUF._statusRefresh or 0) > firstStatusRefresh, "Dashboard Submit did not refresh status icons when Target test mode was already enabled")
expectApplied("hide test status icons on target frame", "Done.")
assert(_G.MSUF_DB.target.stateIconsTestMode == false, "Dashboard Submit did not disable Target Status Icon Test Mode")
expectApplied("show all status icons target", "Showing all status indicators")
expectApplied("select party leader icon indicator", "Selected Party Leader Icon indicator.")
assert(M.activeKey == "gf_indicators", "Group status selector did not open Group Indicators")
assert(M.gfStatusIconSelection == "leaderIcon", "Group status selector did not select leader icon")
expectApplied("select bottom right corner editor slot", "Selected Party Bottom Right corner editor slot.")
assert(M.gfCornerSlotSelection == "BR", "Corner editor selector did not select bottom right")
expectApplied("select mana power color token", "Selected Mana power color token.")
assert(M.activeKey == "opt_colors", "Color token selector did not open Colors page")
assert(M.colorsPowerToken == "MANA", "Power color token selector did not select mana")
expectApplied("set profile name field to Raid Draft", "Set profile create/copy name")
assert(M.activeKey == "profiles", "Profile name staging did not open Profiles page")
assert(M.profileCreateCopyName == "Raid Draft", "Profile create/copy name staging did not set runtime field")
expectApplied("select profile export kind group frames", "Selected Group Frames profile export kind.")
assert(M.profileExportKind == "groupframe", "Profile export kind staging did not set groupframe")
expectApplied("turn on profile import and create new profile", "Set profile import and create new profile on.")
assert(M.profileImportCreateNew == true, "Profile import-create-new staging did not enable toggle")
expectApplied("set profile import new profile name to Imported Raid", "Set profile import new-profile name")
assert(M.profileImportNewName == "Imported Raid", "Profile import new-profile name staging did not set runtime field")
expectApplied("set profile string field to MSUF5:staged", "Set profile string field.")
assert(M.profileImportString == "MSUF5:staged", "Profile string staging did not set runtime field")
M.activeKey = "home"
local savedUnitPage = M.UnitPage
local unitCopyCalls = {}
M.UnitPage = {
    NewCopyScopeDefaults = function()
        return {
            basics = true,
            text = true,
            portrait = true,
            power = true,
            castbar = true,
            status = true,
            load = true,
            transparency = true,
            layout = false,
        }
    end,
    CopyUnitSettings = function(source, target, scopes)
        unitCopyCalls[#unitCopyCalls + 1] = { source = source, target = target, scopes = scopes }
    end,
}
expectStatus("copy target profile to player", "confirmation_needed", "Copy Target settings")
expectApplied("yes", "Target settings to Player")
assert(#unitCopyCalls == 1, "Unit profile wording did not execute exactly one Unit Copy call")
assert(unitCopyCalls[1].source == "target" and unitCopyCalls[1].target == "player", "Unit profile wording copied the wrong unit direction")
assert(unitCopyCalls[1].scopes and unitCopyCalls[1].scopes.text == true and unitCopyCalls[1].scopes.layout == true, "Unit profile wording did not copy all Unit Copy categories")
unitCopyCalls = {}
expectApplied("copy only text from target profile to player", "Target settings to Player")
assert(#unitCopyCalls == 1, "Scoped Unit Copy wording did not execute exactly one Unit Copy call")
assert(unitCopyCalls[1].source == "target" and unitCopyCalls[1].target == "player", "Scoped Unit Copy wording copied the wrong unit direction")
assert(unitCopyCalls[1].scopes and unitCopyCalls[1].scopes.text == true, "Scoped Unit Copy wording did not enable text")
assert(unitCopyCalls[1].scopes.basics == false and unitCopyCalls[1].scopes.layout == false and unitCopyCalls[1].scopes.castbar == false, "Scoped Unit Copy wording copied extra categories")
M.UnitPage = savedUnitPage
expectApplied("clear player copy categories", "Cleared all unit copy categories.")
assert(M.activeKey == "uf_player", "Unit copy staging did not open Player page")
assert(M.unitCopyScopes and M.unitCopyScopes.text == false and M.unitCopyScopes.castbar == false, "Unit copy clear did not disable categories")
expectApplied("select only unit copy text and castbar categories", "Selected only unit copy categories")
assert(M.unitCopyScopes.text == true and M.unitCopyScopes.castbar == true, "Unit copy only did not enable text/castbar")
assert(M.unitCopyScopes.basics == false and M.unitCopyScopes.layout == false, "Unit copy only did not disable other categories")
expectApplied("turn off unit copy portrait category", "Set unit copy category Portrait off.")
assert(M.unitCopyScopes.portrait == false, "Unit copy category toggle did not disable portrait")
M.activeKey = "uf_target"
expectApplied("clear copy categories", "Cleared all unit copy categories.")
assert(M.activeKey == "uf_target", "Unit page copy staging did not preserve current Unit page")
assert(M.unitCopyScopes.text == false and M.unitCopyScopes.castbar == false, "Unit page copy clear did not disable categories")
expectApplied("clear group copy categories", "Cleared all group copy categories.")
assert(M.activeKey == "gf_layout", "Group copy staging did not open Group Layout page")
assert(M.gfCopyScopes and M.gfCopyScopes.general == false and M.gfCopyScopes.health == false, "Group copy clear did not disable categories")
expectApplied("select only group copy health and text categories", "Selected only group copy categories")
assert(M.gfCopyScopes.health == true and M.gfCopyScopes.text == true, "Group copy only did not enable health/text")
assert(M.gfCopyScopes.general == false and M.gfCopyScopes.font == false, "Group copy only did not disable other categories")
expectApplied("turn off group copy auras category", "Set group copy category Auras off.")
assert(M.gfCopyScopes.auras == false, "Group copy category toggle did not disable auras")

expectStatus("rename profile Raid to Raid PvP", "confirmation_needed", "Type 'yes'")
expectApplied("yes", "Renamed profile Raid to Raid PvP")
assert(_G.MSUF_GlobalDB.profiles.Raid == nil, "Profile rename did not remove old profile key")
assert(type(_G.MSUF_GlobalDB.profiles["Raid PvP"]) == "table", "Profile rename did not create destination profile key")
assert(_G.MSUF_ActiveProfile == "Raid PvP", "Profile rename did not move active profile")
assert(_G.MSUF_DB == _G.MSUF_GlobalDB.profiles["Raid PvP"], "Profile rename did not update active DB reference")
assert(_G.MSUF_GlobalDB.char["Player-Realm"].specProfileMap[123] == "Raid PvP", "Profile rename did not update spec profile mapping")

local history = A.GetHistory and A.GetHistory() or {}
assert(#history >= 12, "Dashboard Submit did not record conversation history")

io.write("assistant_dashboard_smoke: ok\n")
