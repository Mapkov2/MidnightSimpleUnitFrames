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
-- and the resize rebuild, which still builds a new tree each time.
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

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env, core = mw.M, mw.env, mw.core
local widgets = mw.world.widgets
env.StaticPopup_Show = function() return nil end
-- The queued unit-frame, module and class-power applies read runtime APIs the
-- harness only stubs; this contract is about the menu's own frames.
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ApplyModules = function() return true end
env.MSUF_ClassPower_Apply = function() return true end

local function Settle() widgets:RunTimers() end
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
do
    local data = core.MSUF_Changelog
    local entries = type(data) == "table" and data.entries or nil
    if type(entries) == "table" and #entries >= 2 then
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
end

---------------------------------------------------------------------------
-- Report only: the triggers that still build a new tree
---------------------------------------------------------------------------
if report then
    if M.SearchBridge and M.SearchBridge.RunSearchQuery then
        local before = WidgetCount()
        for i = 1, 4 do
            M.SearchBridge.RunSearchQuery(i % 2 == 0 and "castbar" or "health")
            Settle()
        end
        Note("search submit x4", (WidgetCount() - before) .. " widgets")
    end
    Select("opt_misc")
    local before = WidgetCount()
    M._msuf2LayoutVersion = (M._msuf2LayoutVersion or 0) + 1
    M.activeKey = nil
    M.SelectPage("opt_misc")
    Settle()
    Note("opt_misc same-size relayout select", (WidgetCount() - before) .. " widgets")
    print("menu_page_rebuild_leak_smoke " .. flavor .. ":")
    for i = 1, #lines do print(lines[i]) end
end

print(string.format("menu_page_rebuild_leak_smoke %s: ok (%d pages undo/redo in place; reset, self-rebuild and view switches flat)",
    flavor, undoPages))
