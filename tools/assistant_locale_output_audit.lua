_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
local M = assert(MSUF.MSUF2, "Menu namespace missing")
local A = assert(MSUF.Assistant, "Assistant missing after dashboard smoke")

-- The Assistant runtime smoke intentionally does not load the main addon's
-- Menu2 API. Mirror the API's exact-control contract so result follow-ups test
-- the current focused-control path instead of failing on a missing harness
-- integration. Keep the received identity for semantic assertions below.
local lastExactControlOpen
_G.MSUF_OpenExactSettingControl = function(settingKey, label, page)
    lastExactControlOpen = { settingKey = settingKey, label = label, page = page }
    local opened = type(M.Open) == "function" and M.Open(page) ~= false
    if not opened then return false, "I could not open the MSUF options page." end
    return true, "Opened " .. tostring(label or settingKey) .. " and focused its exact control."
end

-- Poison the surrounding Menu2 locale sources. Assistant chat/panel output must
-- stay English-only and must not inherit localized menu labels or M.Tr output.
M.pages = {
    opt_castbar = { title = "DE Zauberleisten" },
    gf_layout = { title = "DE Gruppenlayout" },
    gf_bars = { title = "DE Gesundheit und Text" },
    gf_indicators = { title = "DE Gruppenindikatoren" },
    modules = { title = "DE Module" },
    classpower = { title = "DE Klassenressourcen" },
}
M.navItems = {
    { header = "DE Gruppenframes", id = "groupframes", defaultOpen = false },
    { key = "gf_layout", label = "DE Gruppenlayout" },
    { key = "gf_bars", label = "DE Gruppengesundheit" },
    { key = "gf_indicators", label = "DE Gruppenindikatoren" },
    { key = "modules", label = "DE Module" },
    { key = "classpower", label = "DE Klassenressourcen" },
}
M.ResolveNavHeader = function()
    return "groupframes", "DE Gruppenframes", { defaultOpen = false }
end
M.Tr = function(text) return "DE:" .. tostring(text or "") end

if A.Knowledge and A.Knowledge.MarkDirty then A.Knowledge.MarkDirty() end

local function clearPending()
    A.pendingChoices = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.pendingConfirmation = nil
        ctx.pendingFlow = nil
    end
    M.activeKey = "home"
end

local forbidden = {
    "DE:",
    "DE ",
    "Gruppenlayout",
    "Gruppenframes",
    "Zauberleisten",
    "Gesundheit",
    "Gruppenindikatoren",
    "Klassenressourcen",
}

local function assertEnglish(label, output)
    local text = tostring(output or "")
    for i = 1, #forbidden do
        assert(not text:find(forbidden[i], 1, true), label .. " leaked localized text " .. forbidden[i] .. ": " .. text)
    end
end

local function latestAssistantHistory()
    local history = A.GetHistory and A.GetHistory() or nil
    if type(history) ~= "table" then return nil end
    for i = #history, 1, -1 do
        local item = history[i]
        if item and item.role == "assistant" then return item end
    end
    return nil
end

local function submit(label, prompt, expected)
    local result = A.Submit(prompt)
    assert(type(result) == "table", label .. ": missing result")
    assertEnglish(label, result.text)
    assertEnglish(label .. " summary", result.summary)
    local historyItem = latestAssistantHistory()
    if historyItem then assertEnglish(label .. " history summary", historyItem.actionSummary) end
    if expected then
        assert(tostring(result.text or ""):find(expected, 1, true), label .. ": missing " .. expected .. ": " .. tostring(result.text or ""))
    end
    return result
end

submit("group layout search", "search raid frame scaling", "Raid Frame Scaling - Group Layout")
submit("group layout open followup", "open result 1", "Opened Raid Frame Scaling and focused its exact control")
assert(type(lastExactControlOpen) == "table", "group layout follow-up did not call exact-control navigation")
assert(lastExactControlOpen.settingKey == "gf_raid.frameScaleEnabled", "group layout follow-up opened the wrong setting")
assert(lastExactControlOpen.page == "gf_layout" and M.activeKey == "gf_layout", "group layout follow-up opened the wrong page")

if A.Knowledge and A.Knowledge.MarkDirty then A.Knowledge.MarkDirty() end
submit("module search", "search style module", "MSUF Style Module")
submit("module open followup", "open result 1", "Opened MSUF Style Module and focused its exact control")
assert(type(lastExactControlOpen) == "table", "module follow-up did not call exact-control navigation")
assert(lastExactControlOpen.settingKey == "general.styleEnabled", "module follow-up opened the wrong setting")
assert(lastExactControlOpen.page == "modules" and M.activeKey == "modules", "module follow-up opened the wrong page")

clearPending()
if A.Knowledge and A.Knowledge.MarkDirty then A.Knowledge.MarkDirty() end
local index = A.Knowledge and A.Knowledge.EnsureIndex and A.Knowledge.EnsureIndex()
assert(type(index) == "table" and type(index.items) == "table", "knowledge index missing")
local poisoned = false
for i = 1, #index.items do
    local item = index.items[i]
    if item and item.key == "general.styleEnabled" then
        item.pageLabel = "DE Module"
        poisoned = true
        break
    end
end
assert(poisoned == true, "did not poison MSUF Style Module knowledge item")
A.Knowledge.searchCache = nil
A.Knowledge.searchCacheOrder = nil
submit("poisoned knowledge page label", "search style module", "MSUF Style Module - Modules")
submit("poisoned knowledge action hint", "explain result 1", "Page: Modules")

clearPending()
if A.Knowledge and A.Knowledge.MarkDirty then A.Knowledge.MarkDirty() end
submit("class resources direct", "open class resources", "Opened Class Resources")

clearPending()
submit("navigation section", "expand group frames section", "Opened Group Frames navigation section")

M.ResolveNavHeader = nil
M.navItems = { { header = "DE Sonderbereich", id = "customnav", defaultOpen = false } }
local navOk, navMessage = A.Workflow.SetNavSection("DE Sonderbereich", true)
assert(navOk == true, "custom navigation section did not open: " .. tostring(navMessage))
assertEnglish("custom navigation section", navMessage)
assert(tostring(navMessage or ""):find("customnav navigation section", 1, true), "custom navigation section leaked menu header: " .. tostring(navMessage))

clearPending()
M.activeKey = "opt_castbar"
submit("scoped current page help", "what can i do on this page", "Assistant help for Cast Bars:")

clearPending()
M.activeKey = "opt_castbar"
local contextual = submit("contextual summary history", "show timer", "Target Cast Time Text")
assert(tostring(contextual.summary or ""):find("Current-page context: Cast Bars", 1, true), "contextual summary did not use safe page label: " .. tostring(contextual.summary))
local contextualHistory = latestAssistantHistory()
assert(type(contextualHistory) == "table", "contextual summary history missing")
assert(tostring(contextualHistory.actionSummary or ""):find("Current-page context: Cast Bars", 1, true), "history summary did not use safe page label: " .. tostring(contextualHistory.actionSummary))

clearPending()
M.activeKey = "auras3"
submit("auras current page help", "what can i do on this page", "Assistant help for Auras:")

local setting = assert(A.Registry:GetSetting("gf_raid.frameScaleEnabled"), "missing gf_raid.frameScaleEnabled")
local choiceText = A._ChoiceTextForTest({ { setting = setting, value = true, valueLabel = "enabled" } })
assertEnglish("single choice text", choiceText)
assert(choiceText:find("Raid Frame Scaling", 1, true), "single choice text missing English setting label: " .. choiceText)

io.write("assistant_locale_output_audit: ok\n")
