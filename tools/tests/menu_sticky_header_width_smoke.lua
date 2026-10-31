-- Cached sticky unit headers must follow every committed page width.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local sizeEvents = 0
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, {
    page = "home", clientScriptBindings = true,
    beforeCore = function(world)
        -- The base stub changes .parent but leaves stale GetChildren entries.
        -- Native reparenting removes docked sections from wrapper traversal.
        world.widgets.Methods.SetParent = function(self, parent)
            local old = self.parent
            if old == parent then return end
            if old then
                for _, list in ipairs({ old.children, old.regions }) do
                    for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
                end
            end
            self.parent = parent
            if parent then
                local kind = self:GetObjectType()
                local list = (kind == "Texture" or kind == "FontString") and parent.regions or parent.children
                list[#list + 1] = self
            end
        end
        -- Size callbacks are synchronous for native frames. Limit this fixture
        -- addition to sticky sections and the menu shell, leaving other widgets.
        for _, name in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
            local setter = world.widgets.Methods[name]
            world.widgets.Methods[name] = function(self, ...)
                local oldWidth, oldHeight = self:GetWidth(), self:GetHeight()
                setter(self, ...)
                if (self._msuf2StickyPageHeaderRecord or self:GetName() == "MSUF2_Window")
                    and (self:GetWidth() ~= oldWidth or self:GetHeight() ~= oldHeight) then
                    sizeEvents = sizeEvents + 1
                    MenuWorld.FireScript(self, "OnSizeChanged", self:GetWidth(), self:GetHeight())
                end
            end
        end
        world.env.UIParent:SetSize(1920, 1080)
    end,
})
local M, width = mw.M, 1300
M.GetContentMetrics = function() return width, 900 end
M.Theme.ReducedMotionEnabled = function() return true end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function Check(entry, label)
    assert(entry == M.cache.uf_player, label .. ": expected retained unit page")
    assert(#entry.pageHeaders == 2, "unit tabs and fixed preview are both required")
    assert(entry.wrapper:GetWidth() == width - 12, label .. ": page body did not resize")
    for i, record in ipairs(entry.pageHeaders) do
        local section = record.section
        assert(section:GetParent() == M.pageHeaderHost, label .. ": header was not docked")
        assert(section:GetWidth() == width - 32, string.format(
            "%s: header %d width %.0f exceeds/misses page content %.0f", label, i, section:GetWidth(), width - 32))
    end
    local expander = assert(entry.pageHeaders[2].section._msuf2FixedPreviewExpanderRecord)
    assert(expander.box:GetWidth() == width - 60, label .. ": preview descendant retained its old explicit width")
end
local function Select()
    assert(M.SelectPage("uf_player"))
    Settle()
    return M.cache.uf_player
end
local entry = Select()
Check(entry, "initial wide")
local expander = assert(entry.pageHeaders[2].section._msuf2FixedPreviewExpanderRecord)
expander.button:Click()
Settle()
assert(expander.expanded, "full preview must be active before resizing")
-- The public builder can reflow a retained entry while its stack is hosted.
width = 900
assert(M.BuildPageEntry("uf_player", false) == entry, "same layout slot rebuilt the page")
Settle()
Check(entry, "active expanded shrink")
assert(expander.expanded, "active resize lost full-preview state")
M.RelayoutPageHeaderHost()
Check(entry, "height-only relayout after shrink")
-- A committed window resize deactivates the stack before selecting the page.
for _, nextWidth in ipairs({ 1200, 900, 1300, 900 }) do
    width = nextWidth
    M.SetActivePageHeader(nil)
    M.activeKey = nil
    assert(Select() == entry, "committed resize rebuilt the retained page")
    Check(entry, "deactivated resize " .. width)
end
assert(M.SelectPage("home"))
width = 1100
assert(Select() == entry, "cached return rebuilt the page")
Check(entry, "cached return at new width")
M.HideSlashMenuAndMinibar(mw.win)
Settle()
assert(M.Open("uf_player"))
Settle()
Check(entry, "closed/reopened")
-- Closing partway through a shrink cancels its geometry commit. Reopening
-- must compare the new content width with the retained page's stale metrics.
M.Theme.ReducedMotionEnabled = function() return false end
local beforeShrink = mw.win:GetWidth()
mw.win.minimizeButton:Click()
local animation = assert(mw.win._msuf2WindowLayoutAnim, "minimize animation must start")
MenuWorld.FireScript(animation.driver, "OnUpdate", animation.duration * 0.25)
assert(mw.win:GetWidth() < beforeShrink and mw.win._msuf2WindowLayoutAnim == animation,
    "partial animation must shrink without committing the page layout")
local oldWidth = width
width = math.floor(width - (beforeShrink - mw.win:GetWidth()) + 0.5)
assert(width >= 832 and width < oldWidth, "interrupted shrink must retain the normal columns layout slot")
M.HideSlashMenuAndMinibar(mw.win)
assert(not mw.win._msuf2WindowLayoutAnim, "closing must cancel the pending layout commit")
assert(entry.layoutWidth == oldWidth, "cancelled animation unexpectedly committed the page metrics")
M.Theme.ReducedMotionEnabled = function() return true end
assert(M.Open("uf_player"))
Settle()
Check(entry, "reopen after interrupted shrink")
-- Exercise the actual titlebar commands; geometry metrics stand in for native
-- two-point anchors, which the shared fixture deliberately does not solve.
width = 1500
mw.win.maximizeButton:Click()
Settle()
assert(mw.win._msuf2WindowState == "maximized", "maximize command did not run")
local maximized = M.cache.uf_player
Check(maximized, "maximized")
width = 1000
mw.win.maximizeButton:Click()
Settle()
assert(mw.win._msuf2WindowState == "normal", "restore command did not run")
Check(entry, "restored cached normal slot")
assert(sizeEvents > 0, "native size callbacks were not exercised")
print("menu_sticky_header_width_smoke " .. flavor .. ": resize, relayout, cached return, reopen and maximize/restore pass")
