local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function Compile(source, name, env)
    if _VERSION == "Lua 5.1" then
        local chunk = assert(loadstring(source, name))
        assert(setfenv)(chunk, env)
        return chunk
    end
    return assert(load(source, name, "t", env))
end

local unpack = table.unpack or unpack
local textureCount, timerCount = 0, 0

local Frame = {}
Frame.__index = Frame

local function NewFrame(parent)
    local frame = setmetatable({
        children = {},
        points = {},
        hooks = {},
        shown = true,
        width = 1,
        height = 1,
        frameLevel = 1,
    }, Frame)
    frame:SetParent(parent)
    return frame
end

function Frame:SetParent(parent)
    if self.parent and self.parent.children then self.parent.children[self] = nil end
    self.parent = parent
    if parent and parent.children then parent.children[self] = true end
end
function Frame:GetParent() return self.parent end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:GetPoint(index)
    local point = self.points[index or 1]
    if point then return unpack(point) end
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
function Frame:Show() self.showCalls = (self.showCalls or 0) + 1; self.shown = true end
function Frame:Hide() self.hideCalls = (self.hideCalls or 0) + 1; self.shown = false end
function Frame:IsShown() return self.shown == true end
function Frame:HookScript(kind, callback)
    self.hooks[kind] = self.hooks[kind] or {}
    self.hooks[kind][#self.hooks[kind] + 1] = callback
end
function Frame:SetScrollChild(child) self.scrollChild = child end
function Frame:CreateTexture()
    textureCount = textureCount + 1
    return NewFrame(self)
end

local M = { Widgets = {}, Theme = {} }
local W, T = M.Widgets, M.Theme
function M.CallIf(fn, ...)
    if type(fn) == "function" then return fn(...) end
end
local pinnedRefreshes = 0
function M.RefreshPinnedPreviews() pinnedRefreshes = pinnedRefreshes + 1 end

local function CreateFrame(_, _, parent) return NewFrame(parent) end
local env = setmetatable({
    M = M,
    W = W,
    T = T,
    CreateFrame = CreateFrame,
    CONTENT_W = 900,
    CONTENT_H = 620,
    max = math.max,
    C_Timer = {
        After = function()
            timerCount = timerCount + 1
        end,
    },
}, { __index = _G })

local windowSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua")
local buildScrollHost = assert(windowSource:match(
    "(local function BuildWindowScrollHost.-\nend)\n\nlocal function BuildWindow%(")
    or windowSource:match("(local function BuildWindowScrollHost.-\r\nend)\r\n\r\nlocal function BuildWindow%(") ,
    "BuildWindowScrollHost source block missing")
buildScrollHost = buildScrollHost:gsub("local function BuildWindowScrollHost", "BuildWindowScrollHost = function", 1)
Compile(buildScrollHost, "@sticky-window-host", env)()

local widgetsSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local attachHeader = assert(widgetsSource:match(
    "(function W%.AttachStickyPageHeader.-\nend)\n\nlocal function InstallPinnedPreviewUpdater")
    or widgetsSource:match("(function W%.AttachStickyPageHeader.-\r\nend)\r\n\r\nlocal function InstallPinnedPreviewUpdater"),
    "AttachStickyPageHeader source block missing")
Compile(attachHeader, "@sticky-widget-registration", env)()

local root = NewFrame()
local host = NewFrame(root)
local status = NewFrame(host)
local window = NewFrame(root)
window.host, window.status = host, status
M.frame = window
env.BuildWindowScrollHost({ frame = window })

assert(textureCount == 0, "structural page-header host created an extra background texture")
assert(M.pageHeaderHost and not M.pageHeaderHost:IsShown(), "empty page-header host starts visible")
assert(M.scrollFrame.points[1][2] == status,
    "plain page does not anchor ScrollFrame directly below the status owner")

local wrapper = NewFrame(M.scrollChild)
local section = NewFrame(wrapper)
section:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 12, -12)
section:SetSize(868, 54)
section:SetFrameLevel(7)
local entry = { key = "uf_player", wrapper = wrapper }
local builder = { y = -78 }
local ctx = { key = entry.key, wrapper = wrapper, entry = entry }
function ctx:SetContentHeight(height) self.contentHeight = height end
-- Same-key rebuilds must still be passive until SelectPage commits them.
M.activeKey = entry.key

local record = assert(W.AttachStickyPageHeader(section, {
    pageKey = entry.key,
    wrapper = wrapper,
    builder = builder,
    ctx = ctx,
    gap = 4,
    flowGap = 12,
}), "sticky header registration failed")

assert(entry.pageHeader == record, "header record is not owned by its page entry")
assert(not M.scrollFrame._msuf2StickyPageHeader, "same-key registration activated during page build")
assert(section:GetParent() == wrapper, "registration reparented the panel before page activation")
assert(builder.y == 0, "released PageBuilder flow does not start scrolling content at zero")
assert(record.hostHeight == 70, "54 px header did not produce exact 12 + 54 + 4 slot height")
assert(#section.points == 1 and section.points[1][2] == wrapper
    and section.points[1][4] == 12 and section.points[1][5] == -12,
    "registration changed the original panel anchor")
assert(timerCount == 0, "sticky registration queued a timer")
assert(not wrapper.hooks.OnShow and not wrapper.hooks.OnHide,
    "sticky registration attached wrapper lifecycle hooks")

assert(M.SetActivePageHeader(entry) == true, "page header did not activate")
assert(M.scrollFrame._msuf2StickyPageHeader == record, "active record is not stored on the ScrollFrame")
assert(section:GetParent() == M.pageHeaderHost and section:IsShown(), "active panel is not in the fixed host")
assert(M.pageHeaderHost:GetHeight() == 70 and M.pageHeaderHost:IsShown(), "fixed slot height/visibility is wrong")
assert(#section.points == 1 and section.points[1][2] == M.pageHeaderHost,
    "active panel has more than its original left anchor")
assert(section:GetWidth() == 868, "active panel width was stretched by the host")
assert(M.scrollFrame.points[1][2] == M.pageHeaderHost,
    "header page ScrollFrame does not start below the fixed slot")

local plainWrapper = NewFrame(M.scrollChild)
assert(M.SetActivePageHeader({ key = "home", wrapper = plainWrapper }) == false,
    "plain page unexpectedly activated a header")
assert(not M.scrollFrame._msuf2StickyPageHeader, "plain page retained the old active record")
assert(M.pageHeaderHost:GetHeight() == 0 and not M.pageHeaderHost:IsShown(),
    "plain page retained visible header space")
assert(next(M.pageHeaderHost.children) == nil, "plain page left a panel parented to the shared host")
assert(section:GetParent() == wrapper and section:GetWidth() == 868 and section:GetHeight() == 54,
    "deactivation did not restore the original panel geometry")
assert(#section.points == 1 and section.points[1][2] == wrapper
    and section.points[1][4] == 12 and section.points[1][5] == -12,
    "deactivation did not restore the original panel anchor")
assert(M.scrollFrame.points[1][2] == status,
    "plain page still routes through the hidden optional header host")

assert(M.SetActivePageHeader(entry) == true, "cached header did not reactivate")
assert(M.scrollFrame._msuf2StickyPageHeader == record and next(M.pageHeaderHost.children) == section,
    "cached return duplicated or replaced the page-owned header")
local cachedHideCalls, cachedShowCalls = section.hideCalls, section.showCalls
assert(M.SetActivePageHeader(entry) == true, "already-active cached header did not reconcile")
assert(section.hideCalls == cachedHideCalls and section.showCalls == cachedShowCalls,
    "already-active cached header was needlessly hidden/shown")
assert(timerCount == 0, "cached header activation queued a timer")

M.DisposePageHeader(entry)
assert(record.disposed and entry.pageHeader == nil, "header disposal did not clear entry ownership")
assert(not M.scrollFrame._msuf2StickyPageHeader and next(M.pageHeaderHost.children) == nil,
    "header disposal retained an active/shared-host child")
assert(section:GetParent() == wrapper, "header disposal did not return the panel to its page wrapper")
wrapper:SetParent(nil)
assert(section:GetParent() == wrapper and next(M.pageHeaderHost.children) == nil,
    "invalidated wrapper left an orphaned panel in the shared host")
assert(timerCount == 0, "sticky lifecycle used a deferred timer")
assert(pinnedRefreshes >= 4, "sticky transitions did not refresh dependent pinned geometry")

local castbarSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
assert(not castbarSource:find("AttachStickyPageHeader", 1, true),
    "Castbar Preview is still incorrectly registered as an Editing header")

io.write("menu2_sticky_page_header_lifecycle_smoke: ok\n")
