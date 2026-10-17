-- Real tour navigation must reuse its finite special-stage views and refresh
-- the Dashboard launcher/summary without leaving another native frame tree.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local baseline, replaceFile = os.getenv("BH3_BASELINE"), os.getenv("BH3_FILE")
if baseline and replaceFile then
    local original = loadfile
    loadfile = function(path)
        if path:gsub("\\", "/") == root .. "/" .. replaceFile then path = baseline .. "/" .. replaceFile end
        return original(path)
    end
end
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "opt_misc", clientScriptBindings = true })
local M, tour = mw.M, mw.core.GuidedTour6
mw.core.FirstLoad6:Complete("fixture")
mw:Select("home")
local function Count()
    local n = #mw.world.widgets.frames
    for _, frame in ipairs(mw.world.widgets.frames) do n = n + #(frame.regions or {}) end
    return n
end
local function HasText(entry, expected)
    local function Inside(frame)
        while frame do if frame == entry.wrapper then return true end; frame = frame.parent end
    end
    for _, frame in ipairs(mw.world.widgets.frames) do
        if Inside(frame) then
            for _, region in ipairs(frame.regions or {}) do
                if region.text == expected then return true end
            end
        end
    end
end
local home = M.cache.home
assert(home and HasText(home, "Start Quick Setup"), "normal Dashboard launcher missing")
local function Start()
    assert(M.StartGuidedTour({ mode = "complete", setupArea = "all" }))
    mw:RunTimers()
end
local function Stage(key)
    assert(M.OpenGuidedTourAtStage(key))
    mw:RunTimers()
    local entry = assert(M.cache.guided_setup)
    if key ~= "final_review" then
        assert(M._guidedTourRuntime.specialClickTargets.stageId == key, "stale click-target owner for " .. key)
    end
    return entry
end
Start()
local stages = { "menu_basics", "unit_intro", "edit_mode", "group_intro", "group_edit_mode", "class_intro", "power_moves", "final_review" }
local views = {}
for _, key in ipairs(stages) do views[key] = Stage(key) end
local function CheckAction(suffix, height, labelTop)
    local button
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame._msuf2RuntimeControlId == "menu2.guided_setup." .. suffix then button = frame end
    end
    assert(button, "missing guided action " .. suffix)
    local action = button:GetParent()
    assert(action:GetHeight() == height, "guided action height changed: " .. suffix)
    local point, owner, relativePoint, x, y = button:GetPoint()
    assert(point == "RIGHT" and owner == action and relativePoint == "RIGHT" and x == -16 and y == 0,
        "guided action button anchor changed: " .. suffix)
    local label, copy
    for _, region in ipairs(action.regions or {}) do
        local p, anchor, rp, dx, dy = region:GetPoint()
        if p == "TOPLEFT" and anchor == action and rp == "TOPLEFT" and dx == 16 and dy == labelTop then label = region end
    end
    assert(label and label:GetWidth() == math.max(120, action:GetWidth() - 252), "guided action label changed: " .. suffix)
    for _, region in ipairs(action.regions or {}) do
        local p, anchor, rp, dx, dy = region:GetPoint()
        if p == "TOPLEFT" and anchor == label and rp == "BOTTOMLEFT" and dx == 0 and dy == -8 then copy = region end
    end
    assert(copy and copy:GetWidth() == label:GetWidth(), "guided action copy changed: " .. suffix)
    assert(type(button:GetScript("OnClick")) == "function", "guided action click handler lost: " .. suffix)
    assert(button._msuf2Primary == true and button._msuf2Role == "primary", "guided action button lost its primary style: " .. suffix)
end
CheckAction("edit_mode_toggle", 84, -20)
CheckAction("group_edit_mode_toggle", 92, -22)
assert(Stage("menu_basics") == views.menu_basics, "returning to a special stage discarded its frame tree")
mw:Select("home")
assert(M.cache.home == home, "starting setup discarded the Dashboard frame tree")
assert(HasText(home, "Resume setup"), "cached Dashboard still offers Start instead of Resume")
local start = Count()
for cycle = 1, 20 do
    for _, key in ipairs(stages) do
        assert(Stage(key) == views[key], "warm special stage rebuilt its frame tree: " .. key)
    end
    mw:Select("home")
    assert(M.cache.home == home, "returning home rebuilt the Dashboard")
end
assert(Count() == start, "warm tour navigation allocated " .. (Count() - start) .. " frames/regions")
local liveSummary = M.GetGuidedTourSummary
M.GetGuidedTourSummary = function() return { reviewedControls = 7, keptControls = 4 } end
local final = Stage("final_review")
assert(HasText(final, "11 guided settings were changed or deliberately kept. Nothing was copied into a separate wizard."), "cached summary is stale")
M.GetGuidedTourSummary = liveSummary
tour:Complete()
M.MarkMenuDataDirty("test-complete")
mw:Select("home")
assert(M.cache.home == home and HasText(home, "Run setup again"), "completion did not repaint the same launcher")
Start()
assert(Stage("menu_basics") == views.menu_basics, "restarting setup discarded its reusable views")
Stage("final_review")
local restore
for _, frame in ipairs(mw.world.widgets.frames) do
    if frame._msuf2RuntimeControlId == "menu2.guided_setup.restore_start" then restore = frame end
end
assert(restore, "missing restore action")
local calls = 0
M.RestoreGuidedTourRestorePoint = function() calls = calls + 1; return true end
MenuWorld.FireScript(restore, "OnClick")
assert(calls == 0, "first restore click skipped confirmation")
Start()
assert(Stage("final_review") == final, "a new tour needlessly rebuilt the same final-review view")
MenuWorld.FireScript(restore, "OnClick")
assert(calls == 0, "confirmation from an earlier tour restored the new tour's snapshot")
MenuWorld.FireScript(restore, "OnClick")
assert(calls == 1 and restore.enabled == false, "confirmed restore did not refresh its used state")
MenuWorld.FireScript(restore, "OnClick")
assert(calls == 1, "a used restore point ran again")
print("bh3_guided_page_reuse_smoke " .. flavor .. ": ok (20 warm cycles, no new frames/regions)")
