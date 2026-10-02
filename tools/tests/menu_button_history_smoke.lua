-- menu_button_history_smoke.lua <repoRoot> <flavor>
--
-- The theme button's click checkpoint snapshots the whole profile, so it is
-- opt-in (review 2026-10-01, C5.4). Under the client's script bindings
-- (HookScript adds a post-call binding that a later SetScript keeps):
--   1. every page control that records an undo step today through the
--      checkpoint still does, and Undo brings the value back: the Class
--      Power quick setup, the resource-mark add and remove buttons, the bar
--      gradient direction arrows and the bar scope selector;
--   2. core widgets that record history themselves or write nothing take no
--      snapshot on a click: slider steppers, segment choices, dropdown
--      openers, the preview expander, the navigation rail, and a scope
--      selector clicked on the scope already shown.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_button_history_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, env = mw.M, mw.env
-- Page buttons that record an undo step ask for it explicitly: opts.history is
-- what the page built the button with (nil means the page-content default).
local builtWithHistory = {}
local ThemeButton = M.Theme.Button
M.Theme.Button = function(parent, text, width, height, opts)
    if type(text) == "string" and opts and opts.history ~= nil then builtWithHistory[text] = opts.history end
    return ThemeButton(parent, text, width, height, opts)
end
-- Harness gap: preview frames keep child regions in fields named left and
-- bottom, which the stub geometry reads; the client's GetCenter is native.
local Methods = mw.world.widgets.Methods
local function Number(value) return type(value) == "number" and value or 0 end
Methods.GetCenter = function(self)
    return Number(self.left) + Number(self.width) / 2, Number(self.bottom) + Number(self.height) / 2
end
env.StaticPopup_Show = function() return nil end

-- Count the theme button checkpoints (source "button:<frame>").
local buttonCheckpoints = 0
local CheckpointHistory = M.CheckpointHistory
M.CheckpointHistory = function(label, source, ...)
    if type(source) == "string" and source:find("^button:") then buttonCheckpoints = buttonCheckpoints + 1 end
    return CheckpointHistory(label, source, ...)
end

local function Descendants(frame, out)
    out = out or {}
    for _, child in ipairs(frame.children or {}) do
        out[#out + 1] = child
        Descendants(child, out)
    end
    return out
end
local function FindButton(key, label, nth)
    mw:Select(key)
    local entry = Check(M.cache[key], key .. " was not built")
    local seen = 0
    for _, frame in ipairs(Descendants(entry.wrapper)) do
        if frame._msuf2RawSetScript and (frame._msuf2RawText or frame._msuf2SearchText) == label then
            seen = seen + 1
            if seen == (nth or 1) then return frame end
        end
    end
    error("menu_button_history_smoke " .. flavor .. ": no '" .. label .. "' button on " .. key, 2)
end
local function Undos() return M.GetHistoryState().undoCount end

---------------------------------------------------------------------------
-- 1. Page controls keep their undo step
---------------------------------------------------------------------------
local F = mw.core.ProfileFields
-- Paths whose value differs between two profile snapshots.
local function ChangedPaths(a, b, path, out)
    out = out or {}
    if type(a) == "table" and type(b) == "table" then
        for k, v in pairs(b) do ChangedPaths(a[k], v, path and (path .. "." .. tostring(k)) or tostring(k), out) end
        for k, v in pairs(a) do
            if b[k] == nil then ChangedPaths(v, nil, path and (path .. "." .. tostring(k)) or tostring(k), out) end
        end
    elseif a ~= b then
        out[#out + 1] = path or "<root>"
    end
    return out
end
local function At(tbl, path)
    for part in path:gmatch("[^%.]+") do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[part] ~= nil and tbl[part] or tbl[tonumber(part)]
    end
    return tbl
end
local function ExpectUndoable(key, label, nth)
    local button = FindButton(key, label, nth)
    local before, count = (F.CopySnapshot(M.EnsureDB())), Undos()
    -- The checkpoint runs inside the click; the unit-frame applies the
    -- handlers queue read client APIs the harness only stubs.
    button:Click()
    mw.world.widgets:ClearTimers()
    local changed = ChangedPaths(before, (F.CopySnapshot(M.EnsureDB())))
    Check(#changed > 0, key .. " '" .. label .. "' changed no setting")
    Check(Undos() == count + 1, key .. " '" .. label .. "' recorded no undo step")
    Check(M.Undo(), "undo of " .. key .. " '" .. label .. "' failed")
    mw.world.widgets:ClearTimers()
    local restored = (F.CopySnapshot(M.EnsureDB()))
    for i = 1, #changed do
        Check(F.Equal(At(restored, changed[i]), At(before, changed[i])),
            "undo of " .. key .. " '" .. label .. "' did not restore " .. changed[i])
    end
end
local cases = 0
if M.pages.classpower then
    ExpectUndoable("classpower", "Quick Setup: Class Bar")
    ExpectUndoable("classpower", "Add resource mark")
    cases = cases + 2
end
ExpectUndoable("opt_bars", "<")
ExpectUndoable("opt_bars", "Target")
cases = cases + 2
-- Class Power quick setup, resource-mark buttons and the gradient direction pad
-- do not rely on the page-content default.
local explicit = { "<", ">", "^", "v" }
if M.pages.classpower then
    explicit[#explicit + 1] = "Quick Setup: Class Bar"
    explicit[#explicit + 1] = "Add resource mark"
    explicit[#explicit + 1] = "Remove resource mark"
end
for i = 1, #explicit do
    Check(builtWithHistory[explicit[i]] == true, "'" .. explicit[i] .. "' is not built with an explicit history = true")
end

---------------------------------------------------------------------------
-- 2. Core widgets take no snapshot on a click
---------------------------------------------------------------------------
local function ExpectNoSnapshot(what, click)
    local count = buttonCheckpoints
    click()
    mw:RunTimers()
    Check(buttonCheckpoints == count, what .. " took a profile snapshot on a click")
end
mw:Select("opt_misc")
local misc = Descendants(M.cache.opt_misc.wrapper)
local stepper, segmentChoice, dropdown
for _, frame in ipairs(misc) do
    if frame._msuf2ControlPartOf and frame._msuf2ControlPartOf._msuf2ControlKind == "slider" and frame._msuf2RawSetScript then
        stepper = stepper or frame
    elseif frame._msuf2RawSetScript and frame._msuf2Value ~= nil and frame:GetParent()
        and frame:GetParent()._msuf2ControlKind == "segment" then
        segmentChoice = segmentChoice or frame
    elseif frame._msuf2ControlKind == "dropdown" and frame._msuf2RawSetScript then
        dropdown = dropdown or frame
    end
end
for _, key in ipairs({ "opt_fonts", "opt_bars", "opt_colors", "gameplay" }) do
    if stepper and segmentChoice and dropdown then break end
    mw:Select(key)
    for _, frame in ipairs(Descendants(M.cache[key].wrapper)) do
        if frame._msuf2ControlPartOf and frame._msuf2ControlPartOf._msuf2ControlKind == "slider" and frame._msuf2RawSetScript then
            stepper = stepper or frame
        elseif frame._msuf2RawSetScript and frame._msuf2Value ~= nil and frame:GetParent()
            and frame:GetParent()._msuf2ControlKind == "segment" then
            segmentChoice = segmentChoice or frame
        elseif frame._msuf2ControlKind == "dropdown" and frame._msuf2RawSetScript then
            dropdown = dropdown or frame
        end
    end
end
Check(stepper and segmentChoice and dropdown, "the sweep found no slider stepper, segment choice or dropdown")
ExpectNoSnapshot("a slider stepper", function() stepper:Click() end)
ExpectNoSnapshot("a segment choice", function() segmentChoice:Click() end)
ExpectNoSnapshot("a dropdown opener", function() dropdown:Click() end)
mw:Select("opt_bars")
local shownScope
for _, frame in ipairs(Descendants(M.cache.opt_bars.wrapper)) do
    if frame._msuf2SegmentChoice and frame._msuf2Active == true then shownScope = frame break end
end
Check(shownScope, "opt_bars shows no active scope choice")
ExpectNoSnapshot("the scope already shown", function() shownScope:Click() end)
local navButton
for _, btn in pairs(M.navButtons or {}) do navButton = btn break end
Check(navButton, "the navigation rail has no buttons")
ExpectNoSnapshot("a navigation rail button", function() navButton:Click() end)
local expanderPage
for _, key in ipairs({ "gf_layout", "uf_player", "classpower" }) do
    if M.pages[key] then
        mw:Select(key)
        for _, frame in ipairs(Descendants(M.scrollChild)) do
            local text = frame._msuf2RawSetScript and (frame._msuf2RawText or frame._msuf2SearchText)
            if text == "Expand" or text == "Compact Preview" then
                expanderPage = frame
                break
            end
        end
    end
    if expanderPage then break end
end
if expanderPage then ExpectNoSnapshot("the preview expander", function() expanderPage:Click() end) end

M.CheckpointHistory = CheckpointHistory
print(string.format("menu_button_history_smoke: ok (%s: %d page controls stay undoable; steppers, segments, dropdowns, scope, navigation%s take no snapshot)",
    flavor, cases, expanderPage and " and the preview expander" or ""))
