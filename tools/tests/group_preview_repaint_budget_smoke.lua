-- group_preview_repaint_budget_smoke.lua <repoRoot> <flavor>
--
-- Review R7 item 9: every group preview repaint built a new scene and stage
-- state table, a tracked-lane table, four compiled lane tables, four lane
-- default tables and about forty closures, and asked the spell model for the
-- current aura five times, each building the whole aura picker list: 17.7 KB
-- (Midnight) to 20.2 KB (Classic Era) per repaint. The preview now keeps its
-- scene, stage state, lane tables and painters per preview box and reads each
-- refresh's inputs from that state. This smoke pins:
--   1. Lua heap growth per repaint (GC stopped; the shared widget stubs that
--      allocate per call are swapped for field-reusing ones, so only the
--      addon's own tables count) stays within KB_BUDGET;
--   2. widget method calls per repaint (the client's native calls) stay
--      within 2 % of the counts measured before the change, and a repaint
--      creates no frame or region;
--   3. the spell model's current-aura answer is the one the aura picker list
--      gives (first choice, kept choice, empty picker, custom entries).
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("group_preview_repaint_budget_smoke " .. flavor .. ": " .. message, 2) end
end

-- Measured 2026-10-02 after the change: 2.11 KB (Midnight, WoW Forever), 1.89 KB (Classic).
local KB_BUDGET = 2.3
-- Widget calls per repaint of the Auras page preview, measured before the change.
local NATIVE_CALLS = { Mainline = 1468, Forever = 1484, Vanilla = 1181, TBC = 1265, Mists = 1249 }
local REPAINTS = 10

-- Collection shrinks the VM stack. Regrow it before counting heap growth so
-- a later deep widget call measures the repaint, not the collector's work.
local function RegrowStack(depth)
    local a, b, c, d, e, f, g, h = 1, 2, 3, 4, 5, 6, 7, 8
    if depth > 0 then return RegrowStack(depth - 1) + a + b + c + d + e + f + g + h end
    return 0
end

-- Fixed product array cohort per repaint: FinalizeScene's outer auraHandles,
-- four inner handles and auraKeys; SelectionBar's widgets, steps and picker
-- color; two Theme gradient arrays. Keep their full 32-bit cost (944 bytes)
-- and normalize only the runtime representation excess of those 11 arrays.
-- All other allocations, including any additional table, remain counted.
local function ArrayBytes(make)
    collectgarbage("collect")
    collectgarbage("stop")
    RegrowStack(300)
    local before = collectgarbage("count")
    local value = make()
    local bytes = (collectgarbage("count") - before) * 1024
    collectgarbage("restart")
    Check(value[1] == false, "array allocation probe changed")
    return bytes
end
local array4 = ArrayBytes(function() return { false, false, false, false } end)
local array3 = ArrayBytes(function() return { false, false, false } end)
local array2 = ArrayBytes(function() return { false, false } end)
local arrayCohort = 5 * array4 + 5 * array3 + array2
Check(arrayCohort == 944 or arrayCohort == 1296, "unexpected Lua 5.1 array representation")
local arrayExcessKB = (arrayCohort - 944) / 1024

local mw = MenuWorld.Open(root, flavor, { page = "gf_auras" })
local widgets = mw.world.widgets
local box
for _, frame in ipairs(widgets.frames) do
    if rawget(frame, "_msufGFRenderState") then box = frame end
end
Check(box ~= nil and type(box.Refresh) == "function", "the Auras page built no group preview")

---------------------------------------------------------------------------
-- Field-reusing stand-ins for the stub methods that allocate per call. The
-- client's widget methods are native and allocate nothing on the Lua heap.
---------------------------------------------------------------------------
local Methods = widgets.Methods
local function Slot(self, field)
    local t = rawget(self, field)
    if type(t) ~= "table" then
        t = {}
        rawset(self, field, t)
    end
    return t
end
local function Color(field)
    return function(self, r, g, b, a)
        local t = Slot(self, field)
        t[1], t[2], t[3], t[4] = r, g, b, a
    end
end
local REUSE = {
    SetStatusBarColor = Color("color"), SetVertexColor = Color("vertexColor"), SetTextColor = Color("textColor"),
    SetShadowColor = Color("shadowColor"), SetBackdropColor = Color("backdropColor"),
    SetBackdropBorderColor = Color("backdropBorderColor"), SetSwipeColor = Color("swipeColor"),
    SetColorTexture = function(self, r, g, b, a)
        local t = Slot(self, "colorTexture")
        t[1], t[2], t[3], t[4] = r, g, b, a
        local v = Slot(self, "vertexColor")
        v[1], v[2], v[3], v[4] = r, g, b, a
    end,
    SetTexCoord = function(self, a, b, c, d, e, f, g, h)
        local t = Slot(self, "texCoord")
        t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8] = a, b, c, d, e, f, g, h
    end,
    SetShadowOffset = function(self, x, y)
        local t = Slot(self, "shadowOffset")
        t[1], t[2] = x, y
    end,
    SetOffset = function(self, x, y)
        local t = Slot(self, "offset")
        t[1], t[2] = x, y
    end,
    SetGradient = function(self, orientation, from, to)
        local t = Slot(self, "gradient")
        t.orientation, t.from, t.to = orientation, from, to
    end,
    SetHitRectInsets = function(self, left, right, top, bottom)
        local t = Slot(self, "hitRectInsets")
        t.left, t.right, t.top, t.bottom = left, right, top, bottom
    end,
    SetFormattedText = function(self, text) self.text = text end,
    SetPoint = function(self, point, relativeTo, relativePoint, x, y)
        if type(relativeTo) == "string" or type(relativeTo) == "number" then
            relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
        end
        local points = self.points
        local pool = Slot(self, "_budgetPointPool")
        local n = #points + 1
        local entry = pool[n]
        if not entry then
            entry = {}
            pool[n] = entry
        end
        entry.point, entry.relativeTo, entry.relativePoint = point, relativeTo, relativePoint or point
        entry.x, entry.y = x or 0, y or 0
        points[n] = entry
    end,
}
for name, fn in pairs(REUSE) do Methods[name] = fn end
local calls = 0
for name, fn in pairs(Methods) do
    if type(fn) == "function" then
        Methods[name] = function(...)
            calls = calls + 1
            return fn(...)
        end
    end
end
local function Regions()
    local total = #widgets.frames
    for i = 1, #widgets.frames do total = total + #(widgets.frames[i].regions or {}) end
    return total
end

---------------------------------------------------------------------------
-- 1 and 2. Heap growth, native calls and widgets per repaint
---------------------------------------------------------------------------
for _ = 1, 3 do box:Refresh("SETTINGS") end
local regions = Regions()
collectgarbage("collect")
collectgarbage("stop")
calls = 0
RegrowStack(300)
local before = collectgarbage("count")
for _ = 1, REPAINTS do box:Refresh("SETTINGS") end
local kb = (collectgarbage("count") - before) / REPAINTS - arrayExcessKB
collectgarbage("restart")
local perRepaint = calls / REPAINTS
Check(kb <= KB_BUDGET, string.format("a repaint allocates %.2f KB, the budget is %.2f KB", kb, KB_BUDGET))
local recorded = assert(NATIVE_CALLS[flavor], "no recorded native call count for " .. flavor)
local ceiling = math.ceil(recorded * 1.02)
Check(perRepaint <= ceiling, string.format("a repaint makes %d widget calls, the ceiling is %d (recorded %d + 2 %%)",
    perRepaint, ceiling, recorded))
Check(Regions() == regions, string.format("repaints created %d frames or regions", Regions() - regions))

---------------------------------------------------------------------------
-- 3. The current aura is the aura picker's answer
---------------------------------------------------------------------------
local GP = mw.M.GroupPage
Check(type(GP.CurrentSpellAura) == "function" and type(GP.SpellAuraValues) == "function",
    "the group spell model no longer exports CurrentSpellAura / SpellAuraValues")
local registry = mw.core.GF and mw.core.GF.SpellIndicators
Check(type(registry) == "table", "the group spell indicator registry is missing")
local savedSpecInfo, savedTrackable, savedPlayerSpec = registry.SpecInfo, registry.TrackableAuras, registry.GetPlayerSpec
local partyConf = GP.Conf("party")
local savedSelection, savedIndicators = mw.M.gfSpellIndicatorSelection, partyConf.spellIndicators
partyConf.spellIndicators = { enabled = true, spec = "TestSpec", specs = { TestSpec = { Custom2 = {} } } }
registry.SpecInfo = { TestSpec = {} }
registry.GetPlayerSpec = function() return "TestSpec" end
local function Expected(kind)
    local selection = mw.M.gfSpellIndicatorSelection or {}
    local selected = selection[tostring(kind) .. "\030TestSpec"]
    local values = GP.SpellAuraValues(kind)
    for i = 1, #values do
        if values[i].value == selected then return selected end
    end
    return values[1] and values[1].value or ""
end
local CASES = {
    { label = "first choice", list = { { name = "A" }, { name = "B" } }, selected = nil },
    { label = "kept choice", list = { { name = "A" }, { name = "B" } }, selected = "B" },
    { label = "stale choice", list = { { name = "A" }, { name = "B" } }, selected = "Gone" },
    { label = "custom without config", list = { { name = "Custom1", custom = true }, { name = "B" } }, selected = "Custom1" },
    { label = "custom with config", list = { { name = "Custom2", custom = true }, { name = "B" } }, selected = "Custom2" },
    { label = "empty picker", list = {}, selected = nil },
    { label = "empty picker, empty choice", list = {}, selected = "" },
    { label = "custom only", list = { { name = "Custom1", custom = true } }, selected = "X" },
}
for _, case in ipairs(CASES) do
    registry.TrackableAuras = { TestSpec = case.list }
    mw.M.gfSpellIndicatorSelection = { ["party\030TestSpec"] = case.selected }
    local want = Expected("party")
    mw.M.gfSpellIndicatorSelection = { ["party\030TestSpec"] = case.selected }
    local got = GP.CurrentSpellAura("party")
    Check(got == want, string.format("%s: current aura %s, the picker gives %s", case.label, tostring(got), tostring(want)))
    local storedKind = mw.M.gfSpellIndicatorSelection.party
    local wantKind = want
    if case.selected == want then wantKind = nil end
    Check(mw.M.gfSpellIndicatorSelection["party\030TestSpec"] == want and storedKind == wantKind,
        case.label .. ": the stored selection differs from the picker's")
end
registry.SpecInfo, registry.TrackableAuras, registry.GetPlayerSpec = savedSpecInfo, savedTrackable, savedPlayerSpec
mw.M.gfSpellIndicatorSelection, partyConf.spellIndicators = savedSelection, savedIndicators

print(string.format("group_preview_repaint_budget_smoke %s: ok (%.2f KB and %d widget calls per repaint; %d spell aura cases)",
    flavor, kb, perRepaint, #CASES))
