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

local function Now()
    if type(_G.time) == "function" then return _G.time() end
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
