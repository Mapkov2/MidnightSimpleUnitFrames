_G = _G or _ENV

local function exists(path) local f = io.open(path, "rb"); if f then f:close(); return true end return false end
local function read(path) local f = assert(io.open(path, "rb"), path); local s = f:read("*a"); f:close(); return s end
local prefix = exists("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc") and "" or "../../"
local core = prefix .. "MidnightSimpleUnitFrames/"
local optionsRoot = prefix .. "MidnightSimpleUnitFrames_Options/"
local companionRoot = prefix .. "MidnightSimpleUnitFrames_Assistant/"
local bridgePath = optionsRoot .. "Shell/Menu2/MSUF_AssistantBridge.lua"
local mainToc = read(core .. "MidnightSimpleUnitFrames.toc")
local menuXml = read(optionsRoot .. "Shell/Menu2/MSUF_Menu2.xml")
local runtimeToc = read(companionRoot .. "MidnightSimpleUnitFrames_Assistant.toc")
local runtimeXml = read(companionRoot .. "MSUF_AssistantRuntime.xml")
local bridge = read(bridgePath)
local pkgmeta = read(prefix .. ".pkgmeta")

assert(not mainToc:find("MSUF_AssistantRuntime.xml", 1, true), "core TOC eagerly loads the V1 runtime")
assert(not exists(core .. "Shell/Menu2/Assistant/MSUF_Assistant.lua"), "core still owns the V1 runtime")
assert(not exists(core .. "Shell/Menu2/AssistantV2"), "core still owns an AssistantV2 directory")
assert(menuXml:find('<Script file="MSUF_AssistantBridge.lua"/>', 1, true), "Menu2 does not load the zero-idle bridge")
assert(runtimeToc:find("## LoadOnDemand: 1", 1, true), "companion is not LoD")
assert(runtimeToc:match("%sMSUF_AssistantRuntime%.xml%s*$"), "companion TOC payload is not the V1 runtime manifest")
assert(not runtimeToc:find("MSUF_AssistantV2", 1, true), "companion TOC still references V2")
assert(pkgmeta:find("MidnightSimpleUnitFrames_Assistant", 1, true), "companion is not packaged")

local scripts, assistantScripts = {}, 0
for file in runtimeXml:gmatch('<Script%s+file="([^"]+)"') do
    file = file:gsub("\\", "/")
    assert(not file:find("..", 1, true), "manifest escapes companion: " .. file)
    assert(exists(companionRoot .. file), "manifest file missing: " .. file)
    scripts[#scripts + 1] = file
    if file:match("^Assistant/.+%.lua$") then assistantScripts = assistantScripts + 1 end
end
assert(#scripts >= 3, "V1 LoD manifest is incomplete")
assert(assistantScripts == #scripts - 2, "V1 LoD manifest must contain only Assistant Lua plus the two locale files")
assert(scripts[1] == "Assistant/MSUF_AssistantLOD_Bootstrap.lua", "V1 bootstrap is not first")
assert(scripts[#scripts - 1] == "MSUF_Menu2_AssistantDialogLocale_Data.lua"
    and scripts[#scripts] == "MSUF_Menu2_AssistantDialogLocale.lua", "dialog locale adapter must load last in historical order")
assert(bridge:find("C_AddOns", 1, true) and bridge:find("LoadAddOn", 1, true), "bridge lacks explicit LoD load")
assert(not bridge:find("RegisterEvent", 1, true) and not bridge:find("OnUpdate", 1, true)
    and not bridge:find("NewTicker", 1, true), "bridge owns passive work")

local counters = { loads = 0, submits = 0, cards = 0, active = 0, newTasks = 0 }
local submittedTexts, scheduled, frames, regions = {}, {}, {}, {}
local combat, menuShown = false, true
local timerMode = "normal"

local function region(text)
    local r = { text = tostring(text or ""), shown = true }
    function r:SetText(value) self.text = tostring(value or "") end
    function r:GetText() return self.text end
    function r:SetPoint() end
    function r:ClearAllPoints() end
    function r:SetWidth() end
    function r:SetJustifyH() end
    function r:SetJustifyV() end
    function r:SetTextColor() end
    function r:SetFontObject() end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    regions[#regions + 1] = r
    return r
end

local function frame(kind, template)
    local f = { kind = kind, template = template, scripts = {}, shown = true, enabled = true, text = "" }
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:SetText(value) self.text = tostring(value or "") end
    function f:GetText() return self.text end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:GetScript(event) return self.scripts[event] end
    function f:HookScript(event, fn)
        local old = self.scripts[event]
        self.scripts[event] = old and function(...)
            old(...)
            return fn(...)
        end or fn
    end
    function f:Show() self.shown = true end
    function f:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:IsShown() return self.shown end
    function f:SetEnabled(value) self.enabled = value and true or false end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:IsEnabled() return self.enabled end
    function f:SetAutoFocus() end
    function f:SetMaxLetters() end
    function f:SetTextInsets() end
    function f:EnableMouse() end
    function f:RegisterForClicks() end
    function f:SetFontObject() end
    function f:SetFocus() self.focused = true end
    function f:ClearFocus() self.focused = false end
    function f:HighlightText() end
    function f:CreateFontString() return region("") end
    frames[#frames + 1] = f
    return f
end

local main = {
    MSUF2 = {
        frame = { IsShown = function() return menuShown end },
        Theme = {
            colors = { text = { 1, 1, 1, 1 }, muted = { 0.7, 0.7, 0.7, 1 } },
            Font = function(_, _, text) return region(text) end,
            SkinPrimaryButton = function() end,
            CenterButtonLabel = function() end,
            SkinEditBox = function() end,
            CreateSuperellipseLayers = function() end,
        },
        Widgets = {
            Text = function(_, text) return region(text) end,
        },
    },
    Assistant = {},
}
_G.MSUF_NS = main
_G.MSUF2 = main.MSUF2
_G.InCombatLockdown = function() return combat end
_G.UnitAffectingCombat = function() return false end
_G.UnitName = function(unit) assert(unit == "player"); return "Marco" end
_G.date = function(format) assert(format == "%H"); return "15" end
_G.CreateFrame = function(kind, _, _, template)
    return frame(kind, template)
end
local function scheduleTimer(delay, callback)
    assert(delay == 0, "first-message load must be deferred by exactly one frame")
    assert(type(callback) == "function", "deferred first-message load has no callback")
    local timer = { cancelled = false }
    function timer:Cancel() self.cancelled = true end
    scheduled[#scheduled + 1] = function()
        if not timer.cancelled then callback() end
    end
    return timer
end
_G.C_Timer = {
    NewTimer = function(delay, callback)
        if timerMode == "newtimer_error" or timerMode == "all_timer_error" then
            error("synthetic NewTimer failure")
        end
        return scheduleTimer(delay, callback)
    end,
    After = function(delay, callback)
        if timerMode == "all_timer_error" then error("synthetic After failure") end
        scheduleTimer(delay, callback)
    end,
}
local loadedAddons = {}
_G.C_AddOns = { LoadAddOn = function(name)
    counters.loads = counters.loads + 1
    assert(name == "MidnightSimpleUnitFrames_Assistant")
    main.Assistant.Submit = function(text)
        counters.submits = counters.submits + 1
        submittedTexts[#submittedTexts + 1] = text
        return {}
    end
    main.Assistant.HandleInput = function() return {} end
    main.Assistant.SetMenuRuntimeActive = function(active) if active then counters.active = counters.active + 1 end end
    main.Assistant.BuildDashboardCard = function() counters.cards = counters.cards + 1; main.Assistant.dashboardUI = {}; return main.Assistant.dashboardUI end
    main.Assistant.AddLoginGreeting = function() error("synthetic greeting hydration failure") end
    main.Assistant.StartNewTask = function() counters.newTasks = counters.newTasks + 1; return true end
    loadedAddons[name] = true
    return true, name
end, IsAddOnLoaded = function(name)
    local loaded = loadedAddons[name] == true
    return loaded, loaded
end }

collectgarbage("collect")
local bridgeBefore = collectgarbage("count")
assert(loadfile(bridgePath))("MidnightSimpleUnitFrames", main)
collectgarbage("collect")
local bridgeKB = collectgarbage("count") - bridgeBefore
assert(bridgeKB < 40, string.format("zero-idle bridge memory budget exceeded: %.1f KB", bridgeKB))
assert(counters.loads == 0, "bridge loaded runtime eagerly")
local parent = frame("Frame")
local card = main.Assistant.BuildDashboardCard(parent, 500, 200)
assert(card, "cold Assistant dashboard card was not built")
assert(counters.loads == 0, "opening/building the dashboard eagerly loaded the companion")

local greeting = "Good afternoon, Marco. I am ready to help with MSUF."
local foundGreeting = false
local foundAlpha = false
for _, value in ipairs(regions) do
    if value:GetText() == greeting then foundGreeting = true; break end
end
assert(foundGreeting, "cold dashboard lacks the personalized afternoon greeting")
-- The maturity tag was retired. Pinned negatively so neither the shell bridge
-- nor the loaded card can reintroduce it on the cold path.
for _, value in ipairs(regions) do
    if value:GetText() == "(Early Alpha)" then foundAlpha = true; break end
end
assert(not foundAlpha, "cold dashboard still shows the retired Early Alpha maturity label")

local input, send
for _, value in ipairs(frames) do
    if value.kind == "EditBox" then input = input or value end
    if value.kind == "Button" and value:GetText() == "Send" then send = value end
    assert(not (value.kind == "Button" and value:GetText() == "Load Assistant"),
        "cold dashboard still exposes a Load Assistant button")
end
assert(input and type(input:GetScript("OnEnterPressed")) == "function", "cold dashboard has no Enter-submit input")
assert(send and type(send:GetScript("OnClick")) == "function", "cold dashboard has no Send button")

local firstQuery = "turn off player name"
input:SetText(firstQuery)
send:GetScript("OnClick")(send, "LeftButton")
local foundLoading = false
for _, value in ipairs(regions) do
    if value:GetText() == "Assistant is loading up..." then foundLoading = true; break end
end
assert(foundLoading, "first query does not immediately show exact loading-up status")
assert(counters.loads == 0 and counters.submits == 0,
    "first query loaded/submitted before the deferred one-frame callback")
assert(#scheduled == 1, "first query must schedule exactly one deferred load")
scheduled[1]()
assert(main.Assistant.IsRuntimeLoaded() == true and counters.loads == 1 and counters.cards == 1,
    "deferred first query did not load/promote V1 exactly once")
assert(counters.submits == 0 and #scheduled == 2,
    "first query executed before the loaded dashboard was atomically promoted")
scheduled[2]()
assert(counters.submits == 1 and #submittedTexts == 1 and submittedTexts[1] == firstQuery,
    "deferred first query was not preserved and submitted exactly once")
assert(main.Assistant.StartNewTaskWithRuntime("loaded-new-task") == true and counters.newTasks == 1,
    "loaded New Task did not promote/reset through the bridge contract")
assert(main.Assistant.GetRuntimeAddonName() == "MidnightSimpleUnitFrames_Assistant", "wrong runtime addon")

-- A toolbar New Task must also be a genuine cold LoD entry point. Exercise a
-- second isolated bridge namespace so this cannot pass merely because the
-- first-message scenario above already loaded the runtime.
local coldCounters = { loads = 0, cards = 0, newTasks = 0 }
local coldMain = {
    MSUF2 = {
        frame = main.MSUF2.frame,
        Theme = main.MSUF2.Theme,
        Widgets = main.MSUF2.Widgets,
    },
    Assistant = {},
}
_G.MSUF_NS, _G.MSUF2 = coldMain, coldMain.MSUF2
_G.C_AddOns.LoadAddOn = function(name)
    assert(name == "MidnightSimpleUnitFrames_Assistant")
    coldCounters.loads = coldCounters.loads + 1
    coldMain.Assistant.Submit = function() return {} end
    coldMain.Assistant.HandleInput = function() return {} end
    coldMain.Assistant.BuildDashboardCard = function()
        coldCounters.cards = coldCounters.cards + 1
        coldMain.Assistant.dashboardUI = {}
        return coldMain.Assistant.dashboardUI
    end
    coldMain.Assistant.StartNewTask = function()
        coldCounters.newTasks = coldCounters.newTasks + 1
        return true
    end
    return true
end
assert(loadfile(bridgePath))("MidnightSimpleUnitFrames", coldMain)
local coldCard = assert(coldMain.Assistant.BuildDashboardCard(frame("Frame"), 500, 200))
local scheduledBeforeNewTask = #scheduled
local queued, queueReason = coldMain.Assistant.StartNewTaskWithRuntime("toolbar-new-task")
assert(queued == true and queueReason == "queued", "cold New Task was not deferred for paint")
assert(coldCounters.loads == 0 and #scheduled == scheduledBeforeNewTask + 1,
    "cold New Task loaded before its one-frame acknowledgement")
scheduled[#scheduled]()
assert(coldCounters.loads == 1 and coldCounters.cards == 1 and coldCounters.newTasks == 1,
    "cold New Task did not load, promote, and reset exactly once")
assert(coldCard ~= nil and coldMain.Assistant._bridgeDashboardCard == nil,
    "cold New Task did not retire the bridge card")

-- Close the menu in the exact frame between runtime promotion and the second
-- first-message handoff. The queued callback may be forced by this harness,
-- but it must perform zero submit/history/mutation work.
local raceCounters = { loads = 0, submits = 0, cards = 0 }
local raceMain = {
    MSUF2 = {
        frame = main.MSUF2.frame,
        Theme = main.MSUF2.Theme,
        Widgets = main.MSUF2.Widgets,
    },
    Assistant = {},
}
_G.MSUF_NS, _G.MSUF2 = raceMain, raceMain.MSUF2
_G.C_AddOns.LoadAddOn = function(name)
    assert(name == "MidnightSimpleUnitFrames_Assistant")
    raceCounters.loads = raceCounters.loads + 1
    raceMain.Assistant.Submit = function() raceCounters.submits = raceCounters.submits + 1 return {} end
    raceMain.Assistant.SubmitDeferred = raceMain.Assistant.Submit
    raceMain.Assistant.HandleInput = function() return {} end
    raceMain.Assistant.SetMenuRuntimeActive = function(active) raceMain.Assistant._menuRuntimeActive = active == true end
    raceMain.Assistant.BuildDashboardCard = function()
        raceCounters.cards = raceCounters.cards + 1
        raceMain.Assistant.dashboardUI = {}
        return raceMain.Assistant.dashboardUI
    end
    return true
end
assert(loadfile(bridgePath))("MidnightSimpleUnitFrames", raceMain)
local raceFrameStart = #frames + 1
local raceParent = frame("Frame")
assert(raceMain.Assistant.BuildDashboardCard(raceParent, 500, 200))
local raceInput, raceSend
for index = raceFrameStart, #frames do
    local value = frames[index]
    if value.kind == "EditBox" then raceInput = raceInput or value end
    if value.kind == "Button" and value:GetText() == "Send" then raceSend = value end
end
assert(raceInput and raceSend, "close-race dashboard controls missing")
raceInput:SetText("turn off target name")
local raceFirstCallback = #scheduled + 1
raceSend:GetScript("OnClick")(raceSend, "LeftButton")
assert(#scheduled == raceFirstCallback and raceCounters.loads == 0, "close-race first stage was not deferred once")
scheduled[raceFirstCallback]()
assert(raceCounters.loads == 1 and raceCounters.cards == 1 and raceCounters.submits == 0,
    "close-race first stage did not stop after promotion")
local raceSecondCallback = raceFirstCallback + 1
assert(#scheduled == raceSecondCallback, "close-race second handoff was not queued")
menuShown = false
scheduled[raceSecondCallback]()
assert(raceCounters.submits == 0, "first-message handoff submitted after the menu closed")
menuShown = true

local function makeColdNamespace()
    return {
        MSUF2 = {
            frame = main.MSUF2.frame,
            Theme = main.MSUF2.Theme,
            Widgets = main.MSUF2.Widgets,
        },
        Assistant = {},
    }
end

local function openColdCard(namespace)
    _G.MSUF_NS, _G.MSUF2 = namespace, namespace.MSUF2
    assert(loadfile(bridgePath))("MidnightSimpleUnitFrames", namespace)
    local firstFrame = #frames + 1
    local parent = frame("Frame")
    local card = assert(namespace.Assistant.BuildDashboardCard(parent, 500, 200))
    local input, send
    for index = firstFrame, #frames do
        local value = frames[index]
        if value.kind == "EditBox" then input = input or value end
        if value.kind == "Button" and value:GetText() == "Send" then send = value end
    end
    assert(input and send, "isolated cold dashboard controls missing")
    return card, input, send, parent
end

-- Reproduce the exact permanent-loading failure: NewTimer throws after the
-- bridge has disabled both controls. The protected scheduler must fall back to
-- Blizzard's legacy After path and still load, promote, and submit.
local timerFallback = makeColdNamespace()
local timerFallbackCounts = { loads = 0, submits = 0, cards = 0 }
loadedAddons = {}
timerMode = "newtimer_error"
_G.C_AddOns.LoadAddOn = function(name)
    assert(name == "MidnightSimpleUnitFrames_Assistant")
    timerFallbackCounts.loads = timerFallbackCounts.loads + 1
    timerFallback.Assistant.Submit = function() timerFallbackCounts.submits = timerFallbackCounts.submits + 1; return {} end
    timerFallback.Assistant.HandleInput = function() return {} end
    timerFallback.Assistant.ScheduleMenuRuntimeNextFrame = function() return false end
    timerFallback.Assistant.BuildDashboardCard = function()
        timerFallbackCounts.cards = timerFallbackCounts.cards + 1
        timerFallback.Assistant.dashboardUI = {}
        return timerFallback.Assistant.dashboardUI
    end
    loadedAddons[name] = true
    return true, name
end
local _, fallbackInput, fallbackSend = openColdCard(timerFallback)
fallbackInput:SetText("change the grow direction of player buffs")
local fallbackFirst = #scheduled + 1
fallbackSend:GetScript("OnClick")(fallbackSend, "LeftButton")
assert(#scheduled == fallbackFirst and timerFallbackCounts.loads == 0,
    "NewTimer failure did not fall back to a deferred After load")
scheduled[fallbackFirst]()
assert(timerFallbackCounts.loads == 1 and timerFallbackCounts.cards == 1 and timerFallbackCounts.submits == 0,
    "After fallback did not load and promote before submitting")
local fallbackSecond = fallbackFirst + 1
assert(#scheduled == fallbackSecond, "After fallback did not defer loaded first-message parsing")
scheduled[fallbackSecond]()
assert(timerFallbackCounts.submits == 1 and timerFallback.Assistant._bridgeDashboardCard == nil,
    "After fallback did not preserve and submit the first request")

-- If both timer APIs themselves fail, the OnClick path must synchronously
-- recover instead of exiting in the disabled loading state.
local timerless = makeColdNamespace()
local timerlessCounts = { loads = 0, submits = 0, cards = 0 }
loadedAddons = {}
timerMode = "all_timer_error"
_G.C_AddOns.LoadAddOn = function(name)
    timerlessCounts.loads = timerlessCounts.loads + 1
    timerless.Assistant.Submit = function() timerlessCounts.submits = timerlessCounts.submits + 1; return {} end
    timerless.Assistant.HandleInput = function() return {} end
    timerless.Assistant.BuildDashboardCard = function()
        timerlessCounts.cards = timerlessCounts.cards + 1
        timerless.Assistant.dashboardUI = {}
        return timerless.Assistant.dashboardUI
    end
    loadedAddons[name] = true
    return true, name
end
local _, timerlessInput, timerlessSend = openColdCard(timerless)
timerlessInput:SetText("change player buff growth")
local scheduledBeforeTimerless = #scheduled
local timerlessOk = pcall(timerlessSend:GetScript("OnClick"), timerlessSend, "LeftButton")
assert(timerlessOk and #scheduled == scheduledBeforeTimerless,
    "timer API failures escaped the first-message OnClick handler")
assert(timerlessCounts.loads == 1 and timerlessCounts.cards == 1 and timerlessCounts.submits == 1
    and timerless.Assistant._bridgeDashboardCard == nil,
    "timer API failures stranded the loading shell instead of synchronously completing")

-- A parser/runtime exception belongs to the real dashboard, not the cold
-- loading shell. Promotion happens first and the runtime recovery hook owns a
-- human-readable fallback response.
local crashingSubmit = makeColdNamespace()
local crashCounts = { loads = 0, cards = 0, recoveries = 0 }
loadedAddons = {}
timerMode = "normal"
_G.C_AddOns.LoadAddOn = function(name)
    crashCounts.loads = crashCounts.loads + 1
    crashingSubmit.Assistant.Submit = function() error("synthetic first-query parser failure") end
    crashingSubmit.Assistant.HandleInput = function() return {} end
    crashingSubmit.Assistant.BuildDashboardCard = function()
        crashCounts.cards = crashCounts.cards + 1
        crashingSubmit.Assistant.dashboardUI = {}
        return crashingSubmit.Assistant.dashboardUI
    end
    crashingSubmit.Assistant.RecoverAssistantFailure = function(_, context)
        crashCounts.recoveries = crashCounts.recoveries + 1
        assert(context.text == "change the grow direction of player buffs" and context.phase == "first-message")
        return { status = "failed", text = "Sorry. Try Player Buff Growth Direction." }
    end
    loadedAddons[name] = true
    return true, name
end
local _, crashInput, crashSend = openColdCard(crashingSubmit)
crashInput:SetText("change the grow direction of player buffs")
local crashFirst = #scheduled + 1
crashSend:GetScript("OnClick")(crashSend, "LeftButton")
scheduled[crashFirst]()
scheduled[crashFirst + 1]()
assert(crashCounts.loads == 1 and crashCounts.cards == 1 and crashCounts.recoveries == 1,
    "first-query exception did not reach runtime recovery exactly once")
assert(crashingSubmit.Assistant._bridgeDashboardCard == nil and crashingSubmit.Assistant.dashboardUI ~= nil,
    "first-query exception rolled back to or stranded the cold loading shell")

-- WoW can report an addon as loaded after a file-level error. Missing runtime
-- entrypoints must be classified as an incomplete partial load, with the cold
-- input restored instead of accepting the API's loaded state as success.
local partial = makeColdNamespace()
loadedAddons = {}
timerMode = "normal"
_G.C_AddOns.LoadAddOn = function(name)
    loadedAddons[name] = true
    return nil, "ADDON_LOADED_WITH_ERRORS"
end
local partialCard, partialInput, partialSend = openColdCard(partial)
local partialQuery = "change the grow direction of player buffs"
partialInput:SetText(partialQuery)
local partialFirst = #scheduled + 1
partialSend:GetScript("OnClick")(partialSend, "LeftButton")
scheduled[partialFirst]()
assert(partial.Assistant.IsRuntimeLoaded() == false and partialCard.loading == false,
    "partial addon load was mistaken for a usable Assistant runtime")
assert(partialInput:IsEnabled() and partialSend:IsEnabled() and partialInput:GetText() == partialQuery,
    "partial addon load did not restore the first query and controls")
assert(partialCard.status:GetText():find("could not finish", 1, true),
    "partial addon load did not explain the incomplete runtime")

-- A thrown LoadAddOn call is also contained locally; it must never escape the
-- button script or leave the UI in its loading state.
local loaderCrash = makeColdNamespace()
loadedAddons = {}
_G.C_AddOns.LoadAddOn = function() error("synthetic C_AddOns.LoadAddOn failure") end
local loaderCrashCard, loaderCrashInput, loaderCrashSend = openColdCard(loaderCrash)
loaderCrashInput:SetText("hello")
local loaderCrashFirst = #scheduled + 1
local loaderClickOk = pcall(loaderCrashSend:GetScript("OnClick"), loaderCrashSend, "LeftButton")
assert(loaderClickOk, "LoadAddOn exception escaped the first-message button")
scheduled[loaderCrashFirst]()
assert(loaderCrashCard.loading == false and loaderCrashInput:IsEnabled() and loaderCrashSend:IsEnabled(),
    "LoadAddOn exception left the cold card disabled")
assert(loaderCrashInput:GetText() == "hello" and loaderCrashCard.status:GetText():find("loader hit an error", 1, true),
    "LoadAddOn exception did not preserve the query and show a recoverable status")

-- Closing the menu before the deferred load runs cancels that one-shot work,
-- but a reused Dashboard card must be enabled and ready when the menu opens
-- again. It must never reappear as a dead "loading up" shell.
local closeDuringLoad = makeColdNamespace()
local closeCounts = { loads = 0, cards = 0, submits = 0 }
loadedAddons = {}
_G.C_AddOns.LoadAddOn = function(name)
    closeCounts.loads = closeCounts.loads + 1
    closeDuringLoad.Assistant.Submit = function() closeCounts.submits = closeCounts.submits + 1; return {} end
    closeDuringLoad.Assistant.HandleInput = function() return {} end
    closeDuringLoad.Assistant.BuildDashboardCard = function()
        closeCounts.cards = closeCounts.cards + 1
        closeDuringLoad.Assistant.dashboardUI = {}
        return closeDuringLoad.Assistant.dashboardUI
    end
    loadedAddons[name] = true
    return true, name
end
local closeCard, closeInput, closeSend, closeParent = openColdCard(closeDuringLoad)
local closeQuery = "change the grow direction of player buffs"
closeInput:SetText(closeQuery)
local closeFirst = #scheduled + 1
closeSend:GetScript("OnClick")(closeSend, "LeftButton")
menuShown = false
closeParent:Hide()
scheduled[closeFirst]()
assert(closeCounts.loads == 0 and closeCard.loading == false and closeInput:IsEnabled() and closeSend:IsEnabled(),
    "closing during cold load did not cancel and restore the reusable card")
assert(closeInput:GetText() == closeQuery and closeCard.status:GetText():find("Loading was paused", 1, true),
    "closing during cold load lost the query or left the loading status")
menuShown = true
closeParent:Show()
local closeRetry = #scheduled + 1
closeSend:GetScript("OnClick")(closeSend, "LeftButton")
scheduled[closeRetry]()
scheduled[closeRetry + 1]()
assert(closeCounts.loads == 1 and closeCounts.cards == 1 and closeCounts.submits == 1,
    "reopened cold card could not retry the preserved first request")

timerMode = "normal"

_G.MSUF_NS, _G.MSUF2 = main, main.MSUF2
_G.C_AddOns.LoadAddOn = function(name)
    counters.loads = counters.loads + 1
    loadedAddons[name] = true
    return true, name
end

combat = true
local loaded, why = main.Assistant.EnsureRuntimeLoaded("combat-reentry")
assert(loaded == false and why == "combat" and counters.loads == 1, "loaded V1 bypassed combat gate")
local newTasksBeforeBlocked = counters.newTasks
local newTaskOk, newTaskWhy = main.Assistant.StartNewTaskWithRuntime("combat-new-task")
assert(newTaskOk == false and newTaskWhy == "combat" and counters.newTasks == newTasksBeforeBlocked,
    "loaded New Task bypassed combat gate")
local submitted = main.Assistant.SubmitExplicitQuery("hello", "combat-query")
assert(submitted == false and counters.submits == 1, "bridge submitted in combat")
combat, menuShown = false, false
loaded, why = main.Assistant.EnsureRuntimeLoaded("closed-reentry")
assert(loaded == false and why == "menu_closed" and counters.loads == 1, "loaded V1 bypassed closed-menu gate")
newTaskOk, newTaskWhy = main.Assistant.StartNewTaskWithRuntime("closed-new-task")
assert(newTaskOk == false and newTaskWhy == "menu_closed" and counters.newTasks == newTasksBeforeBlocked,
    "loaded New Task bypassed hidden-menu gate")
submitted = main.Assistant.SubmitExplicitQuery("hello", "closed-query")
assert(submitted == false and counters.submits == 1, "bridge submitted while menu was closed")
menuShown = true
submitted = main.Assistant.SubmitExplicitQuery("hello", "visible-query")
assert(submitted == true and counters.submits == 2 and submittedTexts[2] == "hello" and counters.active > 0,
    "visible query did not reach V1")

print(string.format("assistant_v1_lod_zero_idle_smoke: ok scripts=%d loads=%d bridge=%.1fKB", #scripts, counters.loads, bridgeKB))
