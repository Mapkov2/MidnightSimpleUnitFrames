-- Runs with native loadfile, without the legacy loader's service injection.
local ns = {}
local base = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local function load(path) assert(loadfile(path))("MidnightSimpleUnitFrames", ns) end
load("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua")
local Stubs = assert(loadfile(".github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
local timers, combat, scheduleError = {}, false, nil
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { NewTimer = function(delay, fn)
    if scheduleError then error(scheduleError) end
    local timer = { delay = delay, callback = fn }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local function drain()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if not timer.cancelled then timer.callback(timer) end
    end
end
_G.UnitName = function() return "Tester" end
_G.CopyTable = function(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and CopyTable(value) or value
    end
    return copy
end
_G.GetRealmName = function() return "Realm" end
_G.UnitClass = function() return "Paladin", "PALADIN", 2 end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.UnitSex = function() return 2 end
for _, name in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
    local field = name .. "Texture"
    env.Methods["Set" .. field] = function(self, value)
        local texture = type(value) == "table" and value or env:Region("Texture", self)
        if type(value) ~= "table" then texture:SetTexture(value) end
        self[field] = texture
    end
    env.Methods["Get" .. field] = function(self) return self[field] end
end
for _, property in ipairs({ "ValueStep", "ObeyStepOnDrag", "Orientation", "ThumbTexture",
    "AutoFocus", "MaxLetters", "MultiLine", "Numeric", "TextInsets", "ScrollChild",
    "Thickness", "StartPoint", "EndPoint" }) do
    env.Methods["Set" .. property] = function(self, value) self[property] = value end
    env.Methods["Get" .. property] = function(self) return self[property] end
end
function env.Methods:Show()
    if self.shown then return end
    self.shown = true
    local handler = self:GetScript("OnShow")
    if handler then handler(self) end
end
function env.Methods:Hide()
    if not self.shown then return end
    self.shown = false
    local handler = self:GetScript("OnHide")
    if handler then handler(self) end
end
_G.GetLocale = function() return "enUS" end
_G.SlashCmdList = {}
for _, file in ipairs({
 "Kernel/MSUF_Require", "Kernel/MSUF_Libs", "Locales/MSUF_Localization",
 "Kernel/MSUF_Util", "State/MSUF_StateHelpers", "State/MSUF_Defaults",
 "Shell/UI/MSUF_Style", "State/MSUF_FirstLoad", "State/MSUF_GuidedTour",
 "State/MSUF_ProfileCodec", "State/MSUF_ProfileRuntime", "State/MSUF_Profiles",
 "GroupFrames/MSUF_GroupFrames_DB", "GroupFrames/MSUF_GroupFrames_DB_Migrations",
}) do load("MidnightSimpleUnitFrames/" .. file .. ".lua") end
local xmlFile = assert(io.open(base .. "MSUF_Menu2.xml", "rb"))
local xml = xmlFile:read("*a"); xmlFile:close()
-- Load the production shell manifest through its API, in declared order.
for file in xml:gmatch('<Script file="([^"]+)"') do
 load(base .. file)
 if file == "MSUF_Menu2_API.lua" then break end
end
load(base .. "Preview/MSUF_Menu2_ClassPowerPreview_Lifecycle.lua")
load(base .. "Pages/MSUF_Menu2_GroupPreview.lua")
load(base .. "MSUF_Menu2_GuidedTour.lua")
local M = ns.MSUF2
local marker = {}
local ok, failure
M.activeKey = nil
M.RegisterPage("home", { version = 1, build = function() return 900 end })
assert(M.Open("home") and M.activeKey == "home" and M.frame:IsShown())
assert(M._msuf2MenuSessionSerial == 1, "first open did not execute the real OnShow")
drain()
local home = M.cache.home
local failRefresh, refreshes = true, 0
M.RegisterPage("second", { version = 1, build = function(ctx)
    ctx:AddRefresher(function()
        if failRefresh then error(marker) end
        refreshes = refreshes + 1
    end)
    return 910
end })
ok, failure = pcall(M.SelectPage, "second")
assert(not ok and failure == marker and M._msuf2DeferPageHeaderLayout == nil)
failRefresh = false
assert(M.SelectPage("second") and refreshes == 1 and M.cache.second.wrapper:IsShown())
assert(M.SelectPage("home") and M.cache.home == home)
M.frame:Hide()
assert(M.MenuRuntime:PendingTaskCount() == 0, "hide retained scheduled menu work")
assert(M.Open("home") and M.cache.home == home and M._msuf2MenuSessionSerial == 2)
drain()
M.InvalidatePage("home")
assert(M.SelectPage("home") and M.cache.home ~= home and home.wrapper:GetParent() == nil)
drain()
print("PASS real window open/switch/reopen: actual shell, native OnShow/OnHide, lazy resume API, invalidation and refresher recovery")
