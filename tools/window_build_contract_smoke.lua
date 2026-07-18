local M = {
    Theme = {}, Widgets = {}, SearchBridge = {}, MenuRuntime = {}, ALIASES = {},
    AssignNamedValues = function(target, names, ...)
        local values, index = { ... }, 1
        for name in names:gmatch("%S+") do target[name], index = values[index], index + 1 end
    end,
}
local MSUF = { MSUF2 = M }
local chunk = assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

for _, api in ipairs({
    "Open", "Toggle", "MinimizeSlashMenuWindow", "MaximizeSlashMenuWindow",
    "RestoreSlashMenuWindow", "RestoreMinimizedSlashMenu", "InvalidatePage",
}) do
    assert(type(M[api]) == "function", "missing window API: " .. api)
end

local file = assert(io.open("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua", "rb"))
local source = file:read("*a")
file:close()

local components = {
    "BuildWindowShell", "InstallWindowInteractions", "BuildWindowChrome",
    "BuildWindowToolbar", "InstallWindowStatusRuntime", "InstallWindowLifecycle",
    "BuildWindowScrollHost",
}
for _, name in ipairs(components) do
    assert(source:find("local function " .. name, 1, true), "missing component: " .. name)
end
local calls = { "BuildWindowShell()" }
for i = 2, #components do calls[#calls + 1] = components[i] .. "(state)" end
local cursor = assert(source:find("local function BuildWindow()", 1, true))
for _, call in ipairs(calls) do
    cursor = assert(source:find(call, cursor, true), "component not wired in order: " .. call) + #call
end

local contracts = {
    "_msuf2BeginWindowDrag", "_msuf2FinishWindowDrag", "_msuf2CancelWindowInteractions",
    "GetSlashMenuSnapLayout", "ApplySlashMenuSnap", "_msuf2ResizeProxy", "WindowMaxBounds",
    "MinimizeSlashMenuWindow", "MaximizeSlashMenuWindow", "RestoreMinimizedSlashMenu",
    "BuildNav", "StartHistorySession", "EndHistorySession", "CancelSearchBackgroundIndex",
    "RequestBossPagePreviewForKey", "RequestGroupPagePreviewForKey", "RefreshToolbarPageReset",
    "MenuRuntime:Resume", "MenuRuntime:Quiesce", "StyleScrollFrame",
}
for _, token in ipairs(contracts) do
    assert(source:find(token, 1, true), "missing window contract: " .. token)
end
assert(not source:find("PostponeAssistantPerformanceWarmup", 1, true),
    "removed Assistant warmup path returned")
assert(not source:find("SetAssistantMenuRuntimeActive", 1, true),
    "Window regained Assistant lifecycle orchestration")

local snapStart = assert(source:find("local function GetSlashMenuSnapLayout", 1, true),
    "missing slash-menu snap layout")
local snapEnd = assert(source:find("local function ApplySlashMenuSnap", snapStart, true),
    "missing slash-menu snap apply boundary")
local snapSource = source:sub(snapStart, snapEnd - 1)
assert(snapSource:find("FrameRectToUIParent(frame)", 1, true),
    "menu snap must compare scaled frame bounds in UIParent space")

print("window build contract smoke: ok")
