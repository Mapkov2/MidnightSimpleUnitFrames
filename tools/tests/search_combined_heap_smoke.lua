-- One live graph: translated index, warmed fuzzy records and every built page coexist.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
-- The combined-heap test on 64-bit Lua models native drawable state without
-- charging frame-only tables to every texture, font string or line. Each
-- drawable keeps its own writable state under the normal field names.
local function UseCompactDrawableStorage(widgets)
    local defaults = {
        shown = widgets.defaultShown, alpha = 1, scale = 1,
        width = widgets.defaultWidth, height = widgets.defaultHeight,
        frameLevel = widgets.defaultFrameLevel, frameStrata = widgets.defaultStrata,
        left = 0, bottom = 0,
    }
    local collections = {
        points = true, children = true, regions = true, masks = true,
        scripts = true, events = true, attributes = true,
    }
    local methods = widgets.Methods
    -- One private mask distinguishes explicitly cleared fields from native
    -- defaults without allocating a second table per drawable.
    local flags, history = {}, {}
    local flag = 1
    for name in pairs(defaults) do flags[name], flag = flag, flag * 2 end
    for name in pairs(collections) do flags[name], flag = flag, flag * 2 end
    local compactMeta = {}
    compactMeta.__newindex = function(widget, name, value)
        local mark = flags[name]
        if mark then
            local touched = rawget(widget, history) or 0
            if touched % (mark * 2) < mark then rawset(widget, history, touched + mark) end
        end
        rawset(widget, name, value)
    end
    compactMeta.__index = function(widget, name)
        local mark = flags[name]
        if not mark or (rawget(widget, history) or 0) % (mark * 2) >= mark then
            return methods[name]
        end
        if collections[name] then
            local values = {}
            widget[name] = values
            return values
        end
        return defaults[name]
    end
    local createRegion = widgets.Region
    local drawable = { Texture = true, MaskTexture = true, FontString = true, Line = true }
    function widgets:Region(objectType, parent)
        local original = createRegion(self, objectType, parent)
        -- An initializer can retain or customize the widget it receives. In
        -- that case its original identity and storage must be preserved.
        if not drawable[objectType] or self.initialize then return original end
        local widget = setmetatable({}, compactMeta)
        for name, value in pairs(original) do
            if not flags[name] then
                rawset(widget, name, value)
            elseif collections[name] then
                if type(value) ~= "table" or next(value) then widget[name] = value end
            elseif value ~= defaults[name] then
                widget[name] = value
            end
        end
        return widget
    end
end

-- Lua 5.1 stores sizeof(size_t) at byte 9 of its binary chunk header.
-- Keep the original 32-bit fixture and its historical absolute limits.
local wide = string.byte(string.dump(function() end), 9) == 8
-- Exercise the same public API and direct model fields in both layouts,
-- independently of the measured world and its historical 32-bit baseline.
local function CheckDrawableStorage()
    local stubs = assert(loadfile(root .. "/.github/scripts/msuf_test_stubs.lua"))()
    for _, compact in ipairs({ false, true }) do
        local world = stubs.New({ shown = true })
        if compact then UseCompactDrawableStorage(world) end
        local parent = world:CreateFrame("Frame", nil, world.UIParent)
        local child = world:CreateFrame("Button", nil, parent)
        local texture, font = parent:CreateTexture(), parent:CreateFontString()
        assert(parent:GetChildren() == child and child:GetParent() == parent and parent:GetNumChildren() == 1)
        local first, second = parent:GetRegions()
        assert(first == texture and second == font and texture:GetParent() == parent)
        for _, name in ipairs({ "points", "children", "regions", "masks", "scripts", "events", "attributes" }) do
            assert(type(texture[name]) == "table" and texture[name] ~= font[name] and not next(font[name]))
            texture[name].probe = true
            assert(font[name].probe == nil)
            texture[name].probe = nil
        end
        texture:SetPoint("TOPLEFT", parent, "BOTTOMRIGHT", 3, -7)
        local point, owner, relative, x, y = texture:GetPoint()
        assert(point == "TOPLEFT" and owner == parent and relative == "BOTTOMRIGHT" and x == 3 and y == -7)
        assert(texture.points[1].relativeTo == parent and font:GetNumPoints() == 0)
        assert(texture:GetAlpha() == 1 and texture:IsShown())
        texture:SetAlpha(0)
        texture:Hide()
        assert(texture.alpha == 0 and not texture.shown and font.alpha == 1 and font.shown)
        texture.alpha, texture.events = nil, nil
        assert(texture:GetAlpha() == nil and texture.events == nil)
        texture.events = {}
        local events = 0
        child:SetScript("OnEvent", function() events = events + 1 end)
        child:RegisterEvent("TEST")
        assert(world:FireEvent("TEST") == 1 and events == 1)
        child:UnregisterEvent("TEST")
        assert(world:FireEvent("TEST") == 0)
        world.Methods.Probe = function(self) return self == font end
        assert(font:Probe() and not texture:Probe())
    end
end
CheckDrawableStorage()
local baseline
local mw = MenuWorld.Open(root, flavor, {
    locale = locale,
    beforeCore = function(world)
        if wide then UseCompactDrawableStorage(world.widgets) end
    end,
    beforeOptions = function()
        collectgarbage("collect")
        baseline = collectgarbage("count")
    end,
})
local M = mw.M
local function Drain()
    for _ = 1, 50 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("combined heap: menu did not settle")
end
local pages = {}
for key in pairs(M.pages) do pages[#pages + 1] = key end
table.sort(pages)
for _, key in ipairs(pages) do
    assert(mw:Select(key), "combined heap: failed page " .. key)
    local entry = assert(M.cache[key])
    for _ = 1, 3 do
        for _, section in pairs(entry.sections or {}) do
            local disclosure = section._msuf2CollapsibleEntry
            if disclosure then disclosure.SetOpenImmediate(true) end
        end
        Drain()
    end
    assert(not entry._msuf2BuildIncomplete, "combined heap: incomplete page " .. key)
end
collectgarbage("collect")
local built = collectgarbage("count") - baseline
local peak, fuzzyObserved = built, false
-- Observe query completion before Pump releases its monotonically growing
-- distance cache. One collection per query measures live residents without
-- making collection on every slice dominate the release check.
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value, i end
    end
    error("combined heap: missing observation seam " .. wanted)
end
local build = Upvalue(M.Search._CoreAPI.WhenIndexReady, "SearchIndexBuild")
local search, slot = Upvalue(build.Pump, "SearchPages")
-- A local keeps the injected pump alive: Lua 5.1's lua_setupvalue puts its GC
-- write barrier on the closure, not on the upvalue cell, so an otherwise
-- unreferenced replacement can be collected while installed.
local function MeasuredSearchPages(...)
    local result = search(...)
    if result then
        local request = M.Search._RenderContext.SEARCH_STATE.request
        local cache = request and request.job and request.job.fuzzy
        if cache and next(cache) ~= nil then
            fuzzyObserved = true
            collectgarbage("collect")
            peak = math.max(peak, collectgarbage("count") - baseline)
        end
    end
    return result
end
debug.setupvalue(build.Pump, slot, MeasuredSearchPages)
for _, query in ipairs({ "castbar", "cstbr", "helth", "player power", "auras", "thret", "portrait" }) do
    M.Search._CoreAPI.OpenSearchResults(query)
    Drain()
end
local records = assert(M.Search._RenderContext.SEARCH_STATE.records)
local tokens = 0
for _, row in ipairs(records) do if row.tokens and #row.tokens > 0 then tokens = tokens + 1 end end
assert(#pages > 20 and #records > 3000 and tokens > 3000, "combined heap did not warm pages/index/fuzzy together")
local recordCount = #records
assert(M.Search.StaticIndex.IsDecoded(), "combined heap did not retain decoded index")
collectgarbage("collect")
local combined = math.max(peak, collectgarbage("count") - baseline)
assert(fuzzyObserved, "combined heap never observed active fuzzy-distance caches")
-- Offline widget tables are retained like native WoW frames, whose GPU/native
-- bytes are outside this Lua heap model. Fixed KiB ceilings cover both families.
-- Measured 2026-10-24, HEAD 03146e6c7 plus concurrent H lanes, enUS/deDE:
-- Mainline peak 269972 / closed 251216 KiB; Vanilla 189727 / 176404 KiB.
-- Fixed family budgets allow about 8-11% growth, rather than a relative limit
-- that would silently grow along with the implementation under test.
local budgets = { Mainline = { 288 * 1024, 272 * 1024 }, Vanilla = { 200 * 1024, 188 * 1024 } }
local family = assert(budgets[flavor], "combined heap: unsupported index family")
local OPEN_KIB, CLOSED_KIB = family[1], family[2]
records = nil
debug.setupvalue(build.Pump, slot, search)
M.HideSlashMenuAndMinibar(M.frame)
Drain()
collectgarbage("collect")
local closed = collectgarbage("count") - baseline
assert(not M.Search.StaticIndex.IsDecoded() and M.Search._RenderContext.SEARCH_STATE.records == nil,
    "combined heap: close retained index or fuzzy records")
print(string.format("combined heap %s/%s: %d pages, %d records, %d tokenized; built=%.1f combined=%.1f/%d closed=%.1f/%d KiB",
    flavor, locale, #pages, recordCount, tokens, built, combined, OPEN_KIB, closed, CLOSED_KIB))
assert(combined <= OPEN_KIB, "combined search/page heap budget exceeded: " .. combined)
assert(closed <= CLOSED_KIB, "closed page heap budget exceeded: " .. closed)
print("PASS combined search/page budgets " .. flavor .. "/" .. locale)
