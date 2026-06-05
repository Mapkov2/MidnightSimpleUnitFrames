local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local DEFAULT_HISTORY_LIMIT = 100
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
        _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
        _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
        db = _G.MSUF_DB
    end
    return db
end

function A.EnsureDB()
    local db = EnsureRootDB()
    db.assistant = type(db.assistant) == "table" and db.assistant or {}
    local adb = db.assistant
    adb.history = type(adb.history) == "table" and adb.history or {}
    adb.context = type(adb.context) == "table" and adb.context or {}
    adb.historyLimit = tonumber(adb.historyLimit) or DEFAULT_HISTORY_LIMIT
    if adb.historyLimit < 20 then adb.historyLimit = 20 end
    if adb.historyLimit > 200 then adb.historyLimit = 200 end
    return adb
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
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
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
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
end

function A.GetContext()
    return A.EnsureDB().context
end

function A.SetContextValue(key, value)
    local ctx = A.GetContext()
    ctx[key] = value
    return value
end

function A.RememberAppliedBundle(bundle)
    local ctx = A.GetContext()
    ctx.lastAction = bundle and bundle.action or "change"
    ctx.lastValue = bundle and bundle.lastValue
    ctx.lastSetting = bundle and bundle.lastSetting
    ctx.lastUnit = bundle and bundle.lastUnit
    ctx.lastFrameType = bundle and bundle.lastFrameType
    ctx.lastCategory = bundle and bundle.lastCategory
    ctx.lastChangeBundle = bundle and bundle.serializable or nil
end

if type(_G.CreateFrame) == "function" then
    local loginGreetingFrame = _G.CreateFrame("Frame")
    if loginGreetingFrame and type(loginGreetingFrame.RegisterEvent) == "function" and type(loginGreetingFrame.SetScript) == "function" then
        loginGreetingFrame:RegisterEvent("PLAYER_LOGIN")
        loginGreetingFrame:SetScript("OnEvent", function(self, event)
            if event ~= "PLAYER_LOGIN" then return end
            if self and type(self.UnregisterEvent) == "function" then self:UnregisterEvent("PLAYER_LOGIN") end
            A.AddLoginGreeting()
        end)
    end
end
