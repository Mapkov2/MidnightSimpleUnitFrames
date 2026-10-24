-- menu_page_rebuild_leak_smoke.lua <repoRoot> <flavor> [report]
--
-- WoW never frees a frame, so every page rebuild leaves its old frame tree
-- behind for the session (review 2026-10-01, C5.2). The menu therefore
-- rebuilds a page only when its structure has to change:
--   1. undo and redo repaint the page on screen in place through its
--      refreshers: the frame and region count stays flat over N cycles, the
--      page keeps its entry and every undone toggle shows its old value again;
--   2. a page reset repaints in place the same way and still restores the
--      default, and undoing the reset brings the edit back;
--   3. a page that rebuilt itself while on screen (its structure follows its
--      data) is still built again on undo, so its rows never go stale;
--   4. the Dashboard keys a cached view by its open disclosures and the
--      changelog page by its selected release: toggling between views that
--      were built once creates nothing.
-- Pass "report" to print the frame counts per trigger, including the search
-- results (built once, then repainted in place: search_results_repaint_smoke)
-- and repeated resize commits, which must reuse their frame trees.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local report = arg[3] == "report"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_page_rebuild_leak_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- The base widget stub stores explicit sizes only. Colors category containers
-- have TOPLEFT/TOPRIGHT anchors instead: native WoW resolves their width from
-- their parent. Model that relation so retained-page reflow sees the same width
-- a rebuild's builder receives, rather than the stub's default 100 pixels.
local function InstallAnchoredWidths(world)
    local methods = world.widgets.Methods
    local explicitWidth = methods.GetWidth
    function methods:GetWidth()
        local left, right
        for _, point in ipairs(self.points or {}) do
            if point.point == "TOPLEFT" and point.relativePoint == "TOPLEFT" then left = point end
            if point.point == "TOPRIGHT" and point.relativePoint == "TOPRIGHT" then right = point end
        end
        if left and right and left.relativeTo == right.relativeTo and left.relativeTo ~= self then
            return left.relativeTo:GetWidth() + right.x - left.x
        end
        return explicitWidth(self)
    end
end
local mw = MenuWorld.Open(root, flavor, { page = "home", beforeCore = InstallAnchoredWidths })
local M, env, core = mw.M, mw.env, mw.core
local widgets = mw.world.widgets
env.StaticPopup_Show = function() return nil end
-- The queued unit-frame, module and class-power applies read runtime APIs the
-- harness only stubs; this contract is about the menu's own frames.
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ApplyModules = function() return true end
env.MSUF_ClassPower_Apply = function() return true end

local function Settle()
    widgets:RunTimers()
    -- Observe settled cached views after the finite disclosure/selection motions.
    M.Theme.StopAllMenuAnimations()
end
-- Frames plus their textures and font strings: regions leak with a tree too.
local function WidgetCount()
    local total = #widgets.frames
    for i = 1, #widgets.frames do total = total + #(widgets.frames[i].regions or {}) end
    return total
end
local lines = {}
local function Note(label, value) lines[#lines + 1] = string.format("  %-46s %s", label, tostring(value)) end

local function EffectivelyShown(frame, stop)
    while frame and frame ~= stop do
        if frame.shown == false then return false end
        frame = frame.parent
    end
    return true
end
-- Visible, enabled bound toggles of a page, in creation order.
local function BoundToggles(entry)
    local list = {}
    local function Walk(frame)
        local command = frame._msuf2CommandAction
        if command and command.kind == "toggle" and type(command.get) == "function"
            and frame.enabled ~= false and EffectivelyShown(frame, entry.wrapper)
            and frame:GetScript("OnClick")
        then
            list[#list + 1] = frame
        end
        for _, child in ipairs(frame.children or {}) do
            if child.parent == frame then Walk(child) end
        end
    end
    Walk(entry.wrapper)
    return list
end
local function Value(toggle) return toggle._msuf2CommandAction.get() and true or false end
local function Click(toggle)
    toggle:GetScript("OnClick")(toggle, "LeftButton")
    Settle()
end
local function Select(key)
    Check(M.SelectPage(key) ~= false, "could not open " .. key)
    Settle()
    return Check(M.cache[key], key .. " was not built")
end

---------------------------------------------------------------------------
-- 1. Undo and redo repaint in place
---------------------------------------------------------------------------
local UNDO_PAGES = {
    "opt_misc", "opt_colors", "opt_fonts", "opt_bars", "modules", "classpower", "gameplay",
    "uf_player", "uf_target", "uf_focus", "uf_pet", "uf_boss",
    "gf_layout", "gf_bars", "gf_auras", "gf_indicators", "auras3_buffs", "auras3_styling",
}
local CYCLES = 3
local undoPages = 0
for _, key in ipairs(UNDO_PAGES) do
    if M.pages[key] then
        local entry = Select(key)
        -- Up to two toggles whose click flips its value and keeps the page as
        -- it is (a toggle that rebuilds its page is section 3's case).
        local picked = {}
        for _, toggle in ipairs(BoundToggles(entry)) do
            if #picked >= 2 then break end
            local before = Value(toggle)
            Click(toggle)
            if M.cache[key] == entry and Value(toggle) ~= before then
                picked[#picked + 1] = { toggle = toggle, original = before }
                Check(M.Undo(), key .. ": undo of a probe click failed")
                Settle()
            elseif M.cache[key] ~= entry then
                entry = Select(key)
                break
            end
        end
        if #picked > 0 and M.cache[key] == entry and not M.PageRebuildsItself(key) then
            undoPages = undoPages + 1
            -- Engine scenes now lazily acquire native clip, gradient and aura pools.
            -- The individual probe clicks above do not warm the combined settings or
            -- the coalesced Redo paint. Visit that complete cycle once before measuring;
            -- every original zero-growth, repaint and value assertion below stays strict.
            for i = 1, #picked do Click(picked[i].toggle) end
            for i = 1, #picked do Check(M.Undo(), key .. ": warm-up undo failed") end
            Settle()
            for i = 1, #picked do Check(M.Redo(), key .. ": warm-up redo failed") end
            Settle()
            for i = 1, #picked do Check(M.Undo(), key .. ": warm-up restore failed") end
            Settle()
            Check(M.cache[key] == entry, key .. ": warm-up rebuilt a reusable page")
            for i = 1, #picked do
                Check(Value(picked[i].toggle) == picked[i].original, key .. ": warm-up lost the original value")
            end
            local first = WidgetCount()
            for cycle = 1, CYCLES do
                for i = 1, #picked do Click(picked[i].toggle) end
                for i = 1, #picked do
                    Check(Value(picked[i].toggle) ~= picked[i].original, key .. ": the toggle click did not apply")
                end
                local beforeUndo = WidgetCount()
                for _ = 1, #picked do Check(M.Undo(), key .. ": undo failed in cycle " .. cycle) end
                Settle()
                Check(M.cache[key] == entry, key .. ": undo rebuilt the page instead of repainting it")
                for i = 1, #picked do
                    local toggle = picked[i].toggle
                    Check(Value(toggle) == picked[i].original, key .. ": undo did not restore the setting")
                    Check((toggle.checked and true or false) == picked[i].original,
                        key .. ": the repainted toggle does not show the restored value")
                end
                Check(WidgetCount() == beforeUndo, key .. ": undo created " .. (WidgetCount() - beforeUndo) .. " widgets")
                for _ = 1, #picked do Check(M.Redo(), key .. ": redo failed in cycle " .. cycle) end
                Settle()
                Check(M.cache[key] == entry, key .. ": redo rebuilt the page")
                Check(Value(picked[1].toggle) ~= picked[1].original, key .. ": redo did not reapply the setting")
                for _ = 1, #picked do M.Undo() end
                Settle()
            end
            Check(WidgetCount() == first, key .. ": " .. CYCLES .. " undo/redo cycles created "
                .. (WidgetCount() - first) .. " widgets")
            Note(key .. " undo+redo x" .. CYCLES, "0 widgets")
        end
    end
end
Check(undoPages >= 9, "only " .. undoPages .. " pages had toggles to undo")

---------------------------------------------------------------------------
-- 2. A page reset repaints in place and stays undoable
---------------------------------------------------------------------------
local F = Check(core.ProfileFields, "ProfileFields did not load")
local factory = Check(F.CopySnapshot(M.EnsureDB()), "booted profile is not snapshot-safe")
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
do
    local key = "opt_misc"
    local entry = Select(key)
    local toggle = Check(BoundToggles(entry)[1], "opt_misc has no toggle")
    local original = Value(toggle)
    local first = WidgetCount()
    for cycle = 1, CYCLES do
        Click(toggle)
        Check(Value(toggle) ~= original, "the opt_misc toggle click did not apply")
        Check(M.ResetPageToDefaults(key) == true, "the opt_misc reset failed in cycle " .. cycle)
        Settle()
        Check(M.cache[key] == entry, "the opt_misc reset rebuilt the page instead of repainting it")
        Check(Value(toggle) == original and (toggle.checked and true or false) == original,
            "the opt_misc reset did not show the default again")
        Check(M.Undo(), "undoing the opt_misc reset failed")
        Settle()
        Check(Value(toggle) ~= original and (toggle.checked and true or false) ~= original,
            "undoing the opt_misc reset did not bring the edit back")
        Check(M.Undo(), "undoing the opt_misc toggle failed")
        Settle()
    end
    Check(M.cache[key] == entry, "a reset cycle replaced the opt_misc page")
    Check(WidgetCount() == first, CYCLES .. " reset cycles created " .. (WidgetCount() - first) .. " widgets")
    Note("opt_misc reset+undo x" .. CYCLES, "0 widgets")
end

---------------------------------------------------------------------------
-- 3. A page that rebuilt itself is still rebuilt on undo
---------------------------------------------------------------------------
do
    local key = "opt_castbar"
    local entry = Select(key)
    Check(not M.PageRebuildsItself(key), "opt_castbar counts as rebuilding itself before it did")
    Check(M.RebuildPageKeepingScroll(key), "opt_castbar did not rebuild itself")
    Settle()
    Check(M.cache[key] ~= entry, "RebuildPageKeepingScroll kept the old opt_castbar entry")
    Check(M.PageRebuildsItself(key), "a page that rebuilt itself is not marked as such")
    entry = M.cache[key]
    local toggle = Check(BoundToggles(entry)[1], "opt_castbar has no toggle")
    local original = Value(toggle)
    Click(toggle)
    entry = M.cache[key]
    Check(M.Undo(), "undo on opt_castbar failed")
    Settle()
    Check(M.cache[key] and M.cache[key] ~= entry, "undo repainted a page that rebuilds itself")
    local fresh = BoundToggles(M.cache[key])[1]
    Check(fresh and Value(fresh) == original and (fresh.checked and true or false) == original,
        "the rebuilt opt_castbar page does not show the undone value")
    -- Invalidating a page that is not on screen is a cache drop, not a rebuild.
    M.InvalidatePage("opt_fonts")
    Check(not M.PageRebuildsItself("opt_fonts"), "dropping a hidden page's cache marked it as rebuilding itself")
end

---------------------------------------------------------------------------
-- 4. Declared views switch between cached entries
---------------------------------------------------------------------------
do
    local entry = Select("home")
    Check(entry.layoutSlot:find("|", 1, true), "the Dashboard entry is not keyed by its view")
    local function Toggle(field)
        M.SetMenuStateValue(field, not (M[field] == true))
        Check(M.RebuildPageKeepingScroll("home"), "the Dashboard did not switch views")
        Settle()
        return M.cache.home
    end
    local views = {}
    local fields = { "dashboardScalingOpen", "dashboardRecoveryOpen", "dashboardChangelogOpen" }
    -- First pass: every field on and off once builds each view at most once.
    for _, field in ipairs(fields) do
        local opened = Toggle(field)
        views[opened.layoutSlot] = views[opened.layoutSlot] or opened
        local closed = Toggle(field)
        views[closed.layoutSlot] = views[closed.layoutSlot] or closed
    end
    local first = WidgetCount()
    for _ = 1, CYCLES do
        for _, field in ipairs(fields) do
            local opened = Toggle(field)
            Check(views[opened.layoutSlot] == opened, "a Dashboard view built before was built again")
            Check(opened.wrapper.shown == true, "the switched-to Dashboard view is hidden")
            Check(M.activeKey == "home", "a Dashboard view switch left the page")
            local closed = Toggle(field)
            Check(views[closed.layoutSlot] == closed, "the closed Dashboard view was built again")
            Check(opened.wrapper.shown == false, "the switched-from Dashboard view stayed visible")
        end
    end
    Check(WidgetCount() == first, CYCLES .. " Dashboard disclosure cycles created " .. (WidgetCount() - first) .. " widgets")
    Note("home disclosures x" .. CYCLES, "0 widgets")
    -- A data change on the Dashboard still repaints the cached view in place.
    local view = M.cache.home
    Check(M.RepaintPageAfterDataChange("home", "smoke") and M.cache.home == view,
        "a Dashboard repaint rebuilt the view")
end

-- 4b. Real disclosure clicks must preserve every cached Dashboard view.
do
    core.FirstLoad6:Complete("fixture")
    M.InvalidatePage("home")
    M.SetMenuStateValue("dashboardChangelogOpen", false)
    M.SetMenuStateValue("dashboardScalingOpen", false)
    M.SetMenuStateValue("dashboardRecoveryOpen", false)
    Select("home")
    local function Header(entry, path)
        local identity = "menu2.home.dashboard." .. M.NormalizeControlPath(path)
        for _, frame in ipairs(widgets.frames) do
            if frame._msuf2RuntimeControlId == identity then
                local parent = frame
                while parent and parent ~= entry.wrapper do parent = parent.parent end
                if parent then return frame end
            end
        end
        error("missing Dashboard disclosure " .. identity)
    end
    local function CheckChangelog(entry, open)
        local head = Header(entry, "changelog.disclosure")
        local card = head.parent
        Check(card:GetHeight() == (open and 420 or 42), "cached Changelog card height changed")
        local hint, arrow, scroll
        for _, region in ipairs(head.regions or {}) do
            if region:GetObjectType() == "FontString" and (region.text == "Hide" or region.text == "View") then hint = region end
            if region:GetObjectType() == "Texture" and region.texture == M.Theme.media.collapseArrow then arrow = region end
        end
        for _, child in ipairs(card.children or {}) do
            if child:GetObjectType() == "ScrollFrame" then scroll = child end
        end
        Check(hint and hint.text == (open and "Hide" or "View"), "cached Changelog hint disagrees with its card height")
        Check(arrow and arrow.rotation == (open and math.pi * 0.5 or 0), "cached Changelog arrow disagrees with its card height")
        Check(scroll and scroll:IsShown() == open, "cached Changelog content disagrees with its card height")
        Check(scroll:GetScrollChild() and scroll:GetScrollChild():GetHeight() > 1, "bundled release notes are missing")
        head:GetScript("OnEnter")(head)
        head:GetScript("OnLeave")(head)
        Check(hint.text == (open and "Hide" or "View"), "hover changed the cached Changelog disclosure state")
    end
    local views, count = {}, 0
    local function Remember()
        local entry = M.cache.home
        if not views[entry] then
            views[entry] = { open = M.dashboardChangelogOpen == true }
            count = count + 1
        end
        Check(entry.wrapper.shown == true, "the clicked Dashboard view is hidden")
        for cached, state in pairs(views) do CheckChangelog(cached, state.open) end
    end
    local paths = { "changelog.disclosure", "scaling.disclosure", "changelog.disclosure", "display_recovery.disclosure",
        "changelog.disclosure", "scaling.disclosure", "changelog.disclosure", "display_recovery.disclosure" }
    local function Cycle()
        for _, path in ipairs(paths) do
            Click(Header(M.cache.home, path))
            Remember()
        end
    end
    Remember()
    Cycle()
    Check(count == 8, "real disclosure clicks did not visit all eight Dashboard views")
    local first = WidgetCount()
    for _ = 1, 20 do
        Click(Header(M.cache.home, "changelog.disclosure"))
        Check(M.dashboardChangelogOpen == true, "Changelog did not open on repeated click")
        Remember()
        Click(Header(M.cache.home, "changelog.disclosure"))
        Check(M.dashboardChangelogOpen == false, "Changelog did not close on repeated click")
        Remember()
    end
    Check(WidgetCount() == first, "repeated Changelog open/close allocated widgets")
    for _ = 1, CYCLES do
        Cycle()
        local entry = M.cache.home
        Select("opt_misc")
        Check(Select("home") == entry, "returning to the Dashboard discarded its view")
        Remember()
    end
    Check(WidgetCount() == first, "warm Dashboard clicks allocated new frames or regions")
    Note("home real clicks, all 8 views x" .. CYCLES, "consistent disclosures; 0 widgets")
end

do
    -- The compact changelog is Options data: a missing payload fails here instead of skipping the check.
    local data = env.MSUF_Changelog
    Check(type(data) == "table" and type(data.entries) == "table" and #data.entries >= 2,
        "the Options addon did not publish the compact changelog with two releases")
    local entries = data.entries
    M.changelogSource = "msuf"
    local a, b = tostring(entries[1].version), tostring(entries[2].version)
    M.changelogSelectedVersion = a
    local entryA = Select("changelog")
    M.changelogSelectedVersion = b
    Check(M.RebuildPageKeepingScroll("changelog"), "the changelog did not switch releases")
    Settle()
    local entryB = M.cache.changelog
    Check(entryB ~= entryA, "the changelog showed the old release")
    local first = WidgetCount()
    for _ = 1, CYCLES do
        M.changelogSelectedVersion = a
        M.RebuildPageKeepingScroll("changelog")
        Settle()
        Check(M.cache.changelog == entryA, "the changelog rebuilt a release it had shown")
        M.changelogSelectedVersion = b
        M.RebuildPageKeepingScroll("changelog")
        Settle()
        Check(M.cache.changelog == entryB, "the changelog rebuilt a release it had shown")
    end
    Check(WidgetCount() == first, "changelog release switches created " .. (WidgetCount() - first) .. " widgets")
    Note("changelog release switches x" .. CYCLES, "0 widgets")
end

---------------------------------------------------------------------------
-- 5. Resize commits reuse an already built page (including same-size commits).
---------------------------------------------------------------------------
do
    local entry = Select("opt_misc")
    local originalW, originalH = M.GetContentMetrics()
    local getMetrics = M.GetContentMetrics
    local width, height = originalW, originalH
    M.GetContentMetrics = function() return width, height end
    local first = WidgetCount()
    for i = 1, 12 do
        width, height = originalW - (i % 3) * 17, originalH - (i % 4) * 11
        M._msuf2LayoutVersion = (M._msuf2LayoutVersion or 0) + 1
        M.activeKey = nil
        Check(M.SelectPage("opt_misc"), "resize selection failed")
        Settle()
        Check(M.cache.opt_misc == entry, "resize replaced the existing page tree")
        Check(entry.wrapper:GetWidth() == width - 12, "retained wrapper did not follow the new width")
        Check(entry.layoutWidth == width and entry.layoutHeight == height, "retained layout metrics are stale")
        Check(#BoundToggles(entry) > 0, "resize lost interactive controls")
        Check(WidgetCount() == first, "resize created " .. (WidgetCount() - first) .. " widgets")
    end
    width, height = originalW, originalH
    M.activeKey = nil
    Check(M.SelectPage("opt_misc"), "returning to the original layout failed")
    Settle()
    Check(M.cache.opt_misc == entry and WidgetCount() == first, "return to original size grew the tree")
    -- Cross the form-width cap in both directions on a real two-column section.
    width, height = 932, originalH
    local colors = Select("opt_colors")
    M.ColorsSetPainterCategory("auras")
    Settle()
    local auraSection = Check(colors.sections.colors_auras, "Colors has no Aura section")
    auraSection._msuf2CollapsibleEntry.SetOpenImmediate(true)
    Settle()
    local cards = Check(auraSection._msuf2ControlCards, "Aura colors cards did not build")
    local left, right
    for _, card in ipairs(cards) do
        if card._msuf2ControlCardTitle == "Cooldown Timer Colors" then left = card end
        if card._msuf2ControlCardTitle == "Timer Thresholds" then right = card end
    end
    Check(left and right, "Aura colors columns did not build")
    local count = WidgetCount()
    for _, nextWidth in ipairs({ 1232, 832, 1232, 932 }) do
        width = nextWidth
        M.activeKey = nil
        Select("opt_colors")
        local expected = math.min(width - 32, M.formContentMaxWidth or 980)
        Check(auraSection._msuf2Width == expected, "accordion body lost its width cap")
        local colW = math.max(310, math.floor((expected - 58) / 2))
        Check(left:GetWidth() == colW and right:GetWidth() == colW, "retained Aura columns have stale widths")
        local _, _, _, x = right:GetPoint()
        Check(x == 42 + colW, "retained right Aura column has a stale position")
        Check(WidgetCount() == count, "Aura columns rebuilt while resizing")
    end
    -- A dropdown's requested width survives a temporary parent clamp.
    local dropdown
    for _, widget in ipairs(colors.searchWidgets) do
        if widget._msuf2ControlKind == "dropdown" and widget._msuf2ContextLayoutParent then dropdown = widget break end
    end
    Check(dropdown, "Colors has no placed dropdown")
    local parent = dropdown._msuf2ContextLayoutParent
    local parentWidth, requested = parent._msuf2Width, dropdown._msuf2RequestedWidth
    Check(requested and requested > 0, "dropdown did not retain its requested width")
    local x, y = dropdown._msuf2ContextLayoutX, dropdown._msuf2ContextLayoutY
    parent._msuf2Width = x + requested - 22
    M.Widgets.MoveWidget(dropdown, parent, x, y)
    Check(dropdown:GetWidth() < requested, "dropdown clamp was not exercised")
    parent._msuf2Width = x + requested + 100
    M.Widgets.MoveWidget(dropdown, parent, x, y)
    Check(dropdown:GetWidth() == requested, "dropdown stayed narrow after regrowing")
    parent._msuf2Width = parentWidth
    M.Widgets.MoveWidget(dropdown, parent, x, y)
    -- Resource Bar retains its ratio columns and the detached slider cap.
    width = 920
    local groupBars = Select("gf_layout")
    local power = Check(groupBars.sections.power, "group bars has no Resource Bar section")
    power._msuf2CollapsibleEntry.SetOpenImmediate(true)
    Settle()
    local detachedWidth
    for _, widget in ipairs(groupBars.searchWidgets) do
        local meta = widget._msuf2SearchMeta
        if meta and meta.label == "Detached width" then detachedWidth = widget break end
    end
    Check(detachedWidth, "group detached width slider did not build")
    local groupCount = WidgetCount()
    for _, nextWidth in ipairs({ 1012, 920, 1012, 920 }) do
        width = nextWidth
        M.activeKey = nil
        Select("gf_layout")
        Check(detachedWidth._msuf2RequestedWidth <= 340, "group detached slider exceeded its source cap")
        local parentW = detachedWidth._msuf2ContextLayoutParent._msuf2Width
        local expected = math.max(160, math.min(340, math.floor((parentW - 48) / 2) - 40))
        Check(detachedWidth._msuf2RequestedWidth == expected, "group detached slider lost its source geometry")
        Check(WidgetCount() == groupCount, "group Resource Bar grew during resize")
    end
    -- Texture Layer's narrow quick-setup row restores its normal widths too.
    width = 832
    local target = Select("uf_target")
    local texture = Check(target.sections.texture_layer, "target has no Texture Layer section")
    texture._msuf2CollapsibleEntry.SetOpenImmediate(true)
    Settle()
    local presets = {}
    for _, widget in ipairs(target.searchWidgets) do
        local label = widget._msuf2HistoryLabel
        if label == "Text background" or label == "Highlight" or label == "MSUF textures" then presets[label] = widget end
    end
    Check(presets["Text background"] and presets.Highlight and presets["MSUF textures"], "quick setups did not build")
    local textureCount = WidgetCount()
    for _, nextWidth in ipairs({ 1012, 832, 1012 }) do
        width = nextWidth
        M.activeKey = nil
        Select("uf_target")
        if nextWidth == 1012 then
            Check(presets["Text background"]:GetWidth() == 142 and presets.Highlight:GetWidth() == 112
                and presets["MSUF textures"]:GetWidth() == 132, "quick setups kept their narrow widths")
            local _, _, _, x = presets.Highlight:GetPoint()
            Check(x == 166, "quick setups kept their narrow positions")
        end
        Check(WidgetCount() == textureCount, "Texture Layer grew during resize")
    end
    -- Lazy class-power construction must read the retained page's current width.
    width = 932
    local cp = Select("classpower")
    width = 1232
    M.activeKey = nil
    Select("classpower")
    Check(cp.context.resizeWidthOwner.width == width - 32, "lazy class-power owner kept its original width")
    width, height = originalW, originalH
    M.GetContentMetrics = getMetrics
    Select("opt_misc")
    Note("resize commits x12 + original layout", "0 widgets")
end
if report then
    print("menu_page_rebuild_leak_smoke " .. flavor .. ":")
    for i = 1, #lines do print(lines[i]) end
end

print(string.format("menu_page_rebuild_leak_smoke %s: ok (%d pages undo/redo in place; reset, self-rebuild and view switches flat)",
    flavor, undoPages))
