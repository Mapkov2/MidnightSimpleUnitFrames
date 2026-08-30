-- Assistant history: stores submitted prompts and rendered responses for the Menu2 shell.
-- History is UI/session state; undoable DB snapshots live in the Assistant undo module.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Assistant history and context storage.
-- This is profile-local assistant UX state, not gameplay state. Keep it bounded so
-- chat-style history never becomes a SavedVariables growth problem.
local DEFAULT_HISTORY_LIMIT = 100
local profileBindingInitialized = false
local boundProfileDB
local boundProfileName
local boundProfileEpoch
local SUPPORT_HINT_SUCCESS_THRESHOLD = 100
local SUPPORT_HINT_COOLDOWN_SECONDS = 7 * 24 * 60 * 60

local function Now()
    if type(_G.time) == "function" then return _G.time() end
    if os and type(os.time) == "function" then return os.time() end
    return 0
end

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
A.Trim = A.Trim or Trim

local function EnsureRootDB()
    local db
    if M and type(M.EnsureDB) == "function" then
        db = M.EnsureDB()
    else
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
        _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
        db = _G.MSUF_DB
    end
    return db
end

local function ActiveProfileName()
    local name = tostring(rawget(_G, "MSUF_ActiveProfile") or "Default")
    return name ~= "" and name or "Default"
end

local function ActiveProfileEpoch()
    return tonumber(rawget(_G, "MSUF_ProfileOwnerEpoch")) or 0
end

local function InCombat()
    return rawget(_G, "MSUF_InCombat") == true
        or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true)
        or (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player") == true)
end

-- These fields can authorize a follow-up write (a bare number, "more", "do
-- it", a selected result, or a picker callback).  Turn serials are deliberately
-- profile-local, so merely switching away cannot age them.  Retaining them in
-- either profile would therefore let an arbitrarily old prompt become the
-- "adjacent" turn again after a profile round trip.
--
-- Chat history and saved helpContext are intentionally absent: they are
-- non-executable profile memory and should remain available when the player
-- returns to that profile.
local PROFILE_EXECUTABLE_CONTEXT_FIELDS = {
    "pendingCandidates", "pendingCandidatesTurn",
    "pendingChoices", "pendingChoicesTurn",
    "pendingResults", "pendingResultsTurn",
    "pendingSelectedResult", "pendingSelectedResultTurn",
    "pendingConfirmation", "pendingConfirmationTurn",
    "pendingFlow", "pendingFlowTurn",
    "planningContext",
    "humanConversationChoice", "relationshipChoice",
    "settingBrowser", "relationshipBrowser",
    "lastChangeBundle", "lastSetting", "lastSettingTurn", "lastSubjectTurn",
    "lastAction", "lastActionLabel", "lastActionMessage", "lastActionUndoable", "lastActionArgs",
    "lastValue", "lastUnit", "lastFrameType", "lastCategory",
    "lastDirection", "lastAttribute",
    "lastMentionedSetting", "lastMentionedUnit", "lastMentionedCategory", "lastMentionedTurn",
    "recentSubjects",
    "lastTextArea", "lastTextSlot", "lastTextSetting", "lastTextValue",
    "lastTextFrameType", "lastTextUnit", "selectedTextEditorTarget",
}

local function ClearProfileExecutableContext(db)
    local assistant = type(db) == "table" and db.assistant or nil
    local context = type(assistant) == "table" and assistant.context or nil
    if type(context) ~= "table" then return end
    for i = 1, #PROFILE_EXECUTABLE_CONTEXT_FIELDS do
        context[PROFILE_EXECUTABLE_CONTEXT_FIELDS[i]] = nil
    end
end

local function CloseProfileBoundLargeTextPanel()
    -- The rendered import panel owns an OnClick closure even after the backing
    -- spec is dropped.  Hide and neutralize that live widget immediately so a
    -- profile switch cannot leave one frame where the old prompt imports into
    -- the newly active profile before the deferred UI refresh runs.
    local ui = A.dashboardUI
    local panel = type(ui) == "table" and ui.largePanel or nil
    if type(panel) == "table" then
        if panel.box and type(panel.box.ClearFocus) == "function" then
            pcall(panel.box.ClearFocus, panel.box)
        end
        if panel.box and type(panel.box.SetText) == "function" then
            pcall(panel.box.SetText, panel.box, "")
        end
        if panel.primary and type(panel.primary.SetScript) == "function" then
            pcall(panel.primary.SetScript, panel.primary, "OnClick", nil)
        end
        if type(panel.Hide) == "function" then pcall(panel.Hide, panel) end
    end
    if type(A.CloseLargeTextPanel) == "function" then
        A.CloseLargeTextPanel()
    else
        A.largeTextPanel = nil
    end
end

local function RebindProfileLocalRuntime(db, profileName, previousDB)
    -- Invalidate both sides of the boundary. Clearing the outgoing store stops
    -- a later return from reviving it; clearing the incoming store also retires
    -- state saved by an older build before this profile-epoch rule existed.
    ClearProfileExecutableContext(previousDB)
    if db ~= previousDB then ClearProfileExecutableContext(db) end

    -- Combat-paused plans and between-frame submit/queue continuations contain
    -- executable setting/action objects. They belong to the profile epoch in
    -- which the player created them and must never resume against this DB.
    if type(A.CancelProfileBoundExecutableWork) == "function" then
        A.CancelProfileBoundExecutableWork("profile-boundary")
    elseif type(A.ClearQueuedPlansForProfileBoundary) == "function" then
        A.ClearQueuedPlansForProfileBoundary("profile-boundary")
    end

    -- Saved context follows the active profile DB, but these hydrated mirrors
    -- are ordinary session Lua fields.  Drop the previous profile's mirrors
    -- before any pending resolver can return them ahead of the new DB state.
    A.pendingCandidates = nil
    A.pendingChoices = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingFlow = nil
    A.pendingConfirmation = nil
    CloseProfileBoundLargeTextPanel()
    A.lastAssistantHelpContext = nil
    A.lastAssistantPlanningContext = nil
    A._helpContextRestored = nil
    A._planningContextRestored = nil
    A._pendingResultFollowupHandled = nil
    A._droppedPendingConfirmation = nil
    A._droppedPendingChoice = nil
    A._droppedPendingFlow = nil

    -- Anchor-pick callbacks close over a semantic target but write through the
    -- currently active DB. Leaving one alive across a profile switch could
    -- apply the old profile's pending pick to the new profile.
    local anchorPicker = rawget(_G, "MSUF_AnchorPicker")
    if type(anchorPicker) == "table" then
        anchorPicker._onPick = nil
        if type(anchorPicker.Hide) == "function" then pcall(anchorPicker.Hide, anchorPicker) end
    end

    -- Undo bundles are runtime-only and carry their owner profile.  The Undo
    -- module is loaded after History, so keep this hook optional during early
    -- startup while still failing closed if it is unavailable.
    if type(A.RebindUndoForProfile) == "function" then
        A.RebindUndoForProfile(profileName, db)
    else
        A.undoStack = {}
        A.redoStack = {}
    end
end

function A.EnsureDB()
    -- Assistant data lives under the active profile DB because history/context follows the
    -- profile the user is editing.
    local db = EnsureRootDB()
    local profileName = ActiveProfileName()
    local profileEpoch = ActiveProfileEpoch()
    local previousDB = boundProfileDB
    local crossedBoundary = (profileBindingInitialized
        and (db ~= previousDB or profileName ~= boundProfileName or profileEpoch ~= boundProfileEpoch))
        or (not profileBindingInitialized and profileEpoch > 0)
    -- Publish the new identity before cancellation callbacks run so an optional
    -- callback that consults Assistant history/context cannot recursively
    -- rediscover the same boundary.
    profileBindingInitialized = true
    boundProfileDB = db
    boundProfileName = profileName
    boundProfileEpoch = profileEpoch
    if crossedBoundary then RebindProfileLocalRuntime(db, profileName, previousDB) end
    db.assistant = type(db.assistant) == "table" and db.assistant or {}
    local adb = db.assistant
    adb.history = type(adb.history) == "table" and adb.history or {}
    adb.context = type(adb.context) == "table" and adb.context or {}
    adb.historyLimit = tonumber(adb.historyLimit) or DEFAULT_HISTORY_LIMIT
    if adb.historyLimit < 20 then adb.historyLimit = 20 end
    if adb.historyLimit > 200 then adb.historyLimit = 200 end
    return adb
end

function A.OnProfileEpochChanged(profileName, profileDB, profileEpoch)
    -- The core profile owner calls this only after an explicit out-of-combat
    -- profile mutation is fully applied. Keep a defensive combat gate here as
    -- well so an external caller cannot make Assistant cleanup part of a
    -- combat-time profile path.
    if InCombat() then return false end
    if tostring(profileName or "") ~= ActiveProfileName()
        or type(profileDB) ~= "table"
        or profileDB ~= rawget(_G, "MSUF_DB")
        or (profileEpoch ~= nil and tonumber(profileEpoch) ~= ActiveProfileEpoch())
    then
        return false
    end
    A.EnsureDB()
    return true
end


-- Compatibility for a core build that predates the generalized epoch name.
function A.OnProfileOwnerSwitched(profileName, profileDB)
    return A.OnProfileEpochChanged(profileName, profileDB)
end

function A.TrimHistory()
    local adb = A.EnsureDB()
    local history = adb.history
    local limit = tonumber(adb.historyLimit) or DEFAULT_HISTORY_LIMIT
    while #history > limit do
        table.remove(history, 1)
    end
end

function A.AddHistory(role, text, status, summary)
    text = Trim(text)
    if text == "" then return nil end
    local adb = A.EnsureDB()
    local item = {
        role = tostring(role or "assistant"),
        text = text,
        timestamp = Now(),
        status = status,
        actionSummary = summary,
    }
    adb.history[#adb.history + 1] = item
    A.TrimHistory()
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.history")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return item
end

local function CurrentHour()
    local hour
    if type(_G.date) == "function" then
        hour = tonumber(_G.date("%H"))
    end
    if hour == nil and os and type(os.date) == "function" then
        hour = tonumber(os.date("%H"))
    end
    if hour == nil then hour = 12 end
    return hour
end

function A.LoginGreetingForHour(hour)
    hour = tonumber(hour) or CurrentHour()
    hour = hour % 24
    if hour >= 5 and hour < 12 then return "Good morning" end
    if hour >= 12 and hour < 17 then return "Good afternoon" end
    if hour >= 17 and hour < 22 then return "Good evening" end
    return "Good night"
end

function A.LoginGreetingText(playerName, hour)
    playerName = Trim(playerName)
    if playerName == "" then playerName = "Player" end
    return A.LoginGreetingForHour(hour) .. ", " .. playerName .. ". I am ready to help with MSUF."
end

function A.AddLoginGreeting(playerName, hour)
    if A._loginGreetingShown then return false end
    A._loginGreetingShown = true
    if playerName == nil and type(_G.UnitName) == "function" then
        playerName = _G.UnitName("player")
    end
    local text = A.LoginGreetingText(playerName, hour)
    A.AddHistory("assistant", text, "info", "Assistant login greeting")
    return true, text
end

function A.RecordSuccessfulAssistantAction()
    local adb = A.EnsureDB()
    adb.powerUserSupportSuccessCount = (tonumber(adb.powerUserSupportSuccessCount) or 0) + 1
    if adb.powerUserSupportSuccessCount > SUPPORT_HINT_SUCCESS_THRESHOLD then
        adb.powerUserSupportSuccessCount = SUPPORT_HINT_SUCCESS_THRESHOLD
    end
    return adb.powerUserSupportSuccessCount
end

function A.MaybePowerUserSupportHint()
    local adb = A.EnsureDB()
    local count = tonumber(adb.powerUserSupportSuccessCount) or 0
    if count < SUPPORT_HINT_SUCCESS_THRESHOLD then return nil end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end

    local now = Now()
    local last = tonumber(adb.powerUserSupportHintAt) or 0
    if now > 0 and last > 0 and (now - last) < SUPPORT_HINT_COOLDOWN_SECONDS then
        return nil
    end

    adb.powerUserSupportSuccessCount = 0
    adb.powerUserSupportHintAt = now
    return "Power-user note: you have made a lot of successful MSUF changes. If MSUF helps you, check out the links on the Dashboard."
end

function A.GetHistory()
    return A.EnsureDB().history
end

function A.ClearHistory()
    local adb = A.EnsureDB()
    for key in pairs(adb.history) do
        adb.history[key] = nil
    end
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.history.clear")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
end

function A.GetContext()
    return A.EnsureDB().context
end

function A.SetContextValue(key, value)
    local ctx = A.GetContext()
    ctx[key] = value
    return value
end

-- Bounded ring of recently discussed distinct subjects.  The follow-up engine
-- resolves "make it bigger / also for target" against a single last subject;
-- this ring lets a later turn reach back to an earlier one ("the other frame",
-- "back to the player one").  It is deliberately small and dedup-by-key so it
-- can never grow SavedVariables or drift into stale-context guessing: the
-- consumer still checks each entry's turn age before trusting it.
local RECENT_SUBJECTS_LIMIT = 5

local function PushRecentSubject(ctx, bundle)
    local key = bundle and bundle.lastSetting
    if type(key) ~= "string" or key == "" then return end
    local ring = type(ctx.recentSubjects) == "table" and ctx.recentSubjects or {}
    ctx.recentSubjects = ring
    -- Drop any earlier mention of the same subject so re-touching it moves the
    -- entry to the front instead of duplicating it.
    for i = #ring, 1, -1 do
        local entry = ring[i]
        if type(entry) ~= "table" or entry.settingKey == key then
            table.remove(ring, i)
        end
    end
    table.insert(ring, 1, {
        settingKey = key,
        unit = bundle.lastUnit,
        frameType = bundle.lastFrameType,
        category = bundle.lastCategory,
        label = bundle.actionLabel or bundle.label,
        turn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0,
    })
    while #ring > RECENT_SUBJECTS_LIMIT do
        table.remove(ring)
    end
end

function A.ConversationContext()
    local ctx = A.GetContext()
    local turnSerial = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0
    local subjectTurn = tonumber(ctx.lastSubjectTurn)
    local ageTurns
    if subjectTurn then ageTurns = turnSerial - subjectTurn end
    local recentSubjects = {}
    for i = 1, #(type(ctx.recentSubjects) == "table" and ctx.recentSubjects or {}) do
        local entry = ctx.recentSubjects[i]
        if type(entry) == "table" then
            local entryTurn = tonumber(entry.turn) or 0
            recentSubjects[#recentSubjects + 1] = {
                settingKey = entry.settingKey,
                unit = entry.unit,
                frameType = entry.frameType,
                category = entry.category,
                label = entry.label,
                turn = entryTurn,
                ageTurns = turnSerial - entryTurn,
            }
        end
    end
    return {
        subject = {
            settingKey = ctx.lastSetting,
            unit = ctx.lastUnit,
            frameType = ctx.lastFrameType,
            category = ctx.lastCategory,
            textArea = ctx.lastTextArea,
            textSlot = ctx.lastTextSlot,
        },
        recentSubjects = recentSubjects,
        lastValue = ctx.lastValue,
        lastDirection = ctx.lastDirection,
        turnSerial = turnSerial,
        ageTurns = ageTurns,
    }
end

function A.RememberAppliedBundle(bundle)
    local ctx = A.GetContext()
    ctx.lastAction = bundle and bundle.action or "change"
    ctx.lastActionLabel = bundle and bundle.actionLabel or bundle and bundle.label
    ctx.lastActionMessage = bundle and bundle.actionMessage
    ctx.lastActionUndoable = bundle and bundle.undoAvailable == true or nil
    ctx.lastActionArgs = bundle and bundle.actionArgs or nil
    ctx.lastValue = bundle and bundle.lastValue
    ctx.lastSetting = bundle and bundle.lastSetting
    ctx.lastUnit = bundle and bundle.lastUnit
    ctx.lastFrameType = bundle and bundle.lastFrameType
    ctx.lastCategory = bundle and bundle.lastCategory
    ctx.lastChangeBundle = bundle and bundle.serializable or nil
    if bundle and bundle.lastSetting ~= nil then
        ctx.lastSubjectTurn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or ctx.lastSubjectTurn
        PushRecentSubject(ctx, bundle)
    end
end
