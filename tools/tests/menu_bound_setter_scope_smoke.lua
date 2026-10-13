-- menu_bound_setter_scope_smoke.lua <repoRoot> <flavor>
--
-- A bound control whose metadata names a setting key records its undo step by
-- comparing only that key's profile root (MSUF_Menu2_Bindings.lua,
-- WidgetHistoryScope). That step is exact only while the setter writes inside
-- that root. On one client's real core and Options graph, with every page built:
--   * every bound control with a setting key, a getter and a setter is driven
--     through its real setter with a changed value (toggles, numbers, choices,
--     colors and number text); each profile root that changed, the writes the
--     following timers make included, must be its own root, unless the control
--     is marked historyScope = false and records whole-profile steps;
--   * Bars > "Enable slanted bars" (it writes every unit and group root), then a
--     bound Player width edit: one undo lands exactly on the state after the
--     click and a second exactly on the start.
-- Plain Lua 5.1.

local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
-- Each part runs on a fresh world: the sweep leaves runtime state behind.
local mw, M
local function OpenWorld()
    mw = MenuWorld.Open(root, flavor, { locale = "enUS", page = "opt_misc", beforeOptions = function(world)
        if world.core.FirstLoad6 then world.core.FirstLoad6.deferredThisSession = true end
    end })
    mw.env.InCombatLockdown = function() return false end
    mw.env.UnitAffectingCombat = function() return false end
    M = mw.M
    M.ShowHistoryFeedback = function() end
    M.ShowStatusFeedback = function() end
end

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = flavor .. ": " .. message end
    return ok
end
local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[key] = Copy(item, seen) end
    return out
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Replace(dst, src)
    for k in pairs(dst) do if src[k] == nil then dst[k] = nil end end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Replace(dst[k], v)
        else
            dst[k] = v
        end
    end
end

-- The slanted switch writes every unit and group root, so its step must be whole.
do
    OpenWorld()
    mw:Select("opt_bars")
    local record = M.RuntimeControlCatalog.Get("menu2.opt.bars.global.slanted.enabled")
    local widget = record and record.widget
    if widget then
        local db = M.EnsureDB()
        M.ClearHistory()
        local start = Copy(db)
        if widget.Click then widget:Click() else widget:GetScript("OnClick")(widget, "LeftButton") end
        mw:RunTimers()
        db = M.EnsureDB()
        local afterClick = Copy(db)
        Check(not Equal(start.player, afterClick.player), "the slanted switch did not write the unit roots")
        local width = tonumber(db.player.width) or 250
        M.SetUnitValue("player", "width", width + 1)
        Check(M.Undo() and Equal(M.EnsureDB(), afterClick), "one undo did not land exactly on the state after the slanted click")
        Check(M.Undo() and Equal(M.EnsureDB(), start), "the second undo did not restore the start exactly")
        M.ClearHistory()
    end
end


-- Build every page the search knows, so every bound control registers.
OpenWorld()
local pages, keys = {}, {}
for _, rec in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
    if rec.key and not pages[rec.key] then
        pages[rec.key] = true
        keys[#keys + 1] = rec.key
    end
end
table.sort(keys)
for _, key in ipairs(keys) do pcall(mw.Select, mw, key) end

-- The values a control's setter is driven with: something other than now.
local function ChoiceValues(widget)
    local out = {}
    for _, button in ipairs(widget.buttons or {}) do out[#out + 1] = button._msuf2Value end
    local values = widget.values or widget._msuf2Values
    if type(values) == "function" then
        local ok, list = pcall(values)
        values = ok and list or nil
    end
    for _, item in ipairs(type(values) == "table" and values or {}) do
        if type(item) == "table" then out[#out + 1] = item.value else out[#out + 1] = item end
    end
    return out
end
local function Candidates(command, widget)
    local ok, value, g, b, a = pcall(command.get)
    if not ok then return {} end
    local kind = command.kind
    if kind == "color" and type(value) == "number" then
        return { { 1 - value, 1 - (tonumber(g) or 0), 1 - (tonumber(b) or 0), a } }
    end
    if kind == "toggle" or type(value) == "boolean" then return { { not value } } end
    if type(value) == "number" then return { { value + 1 }, { value - 1 } } end
    if kind == "textinput" and tonumber(value) then return { { tostring(tonumber(value) + 1) } } end
    local out = {}
    for _, choice in ipairs(ChoiceValues(widget)) do
        if choice ~= value then out[#out + 1] = { choice } end
        if #out >= 2 then break end
    end
    return out
end

local Catalog = M.RuntimeControlCatalog
local checked, unscoped, outside = 0, 0, {}
for _, public in ipairs(Catalog.GetRecords()) do
    local record = Catalog.Get(public.controlId)
    local widget = record and record.widget
    local command = widget and widget._msuf2CommandAction
    local settingKey = command and command.settingKey
    if type(settingKey) == "string" and settingKey ~= "" and command.get and command.set then
        local db = M.EnsureDB()
        local scope = settingKey:match("^([^.]+)")
        if command.historyScope == false then
            unscoped = unscoped + 1
        elseif type(db[scope]) == "table" then
            local hit = {}
            for _, args in ipairs(Candidates(command, widget)) do
                local before = Copy(db)
                if pcall(command.set, args[1], args[2], args[3], args[4]) then
                    pcall(mw.RunTimers, mw)
                    checked = checked + 1
                    for k, v in pairs(db) do
                        if k ~= scope and not Equal(v, before[k]) then hit[#hit + 1] = tostring(k) end
                    end
                    for k in pairs(before) do
                        if k ~= scope and db[k] == nil then hit[#hit + 1] = tostring(k) end
                    end
                end
                Replace(db, before)
                M.ClearHistory()
            end
            if #hit > 0 then
                outside[#outside + 1] = public.controlId .. " [" .. settingKey .. "] also wrote " .. table.concat(hit, ",")
            end
        end
    end
end
Check(checked > 200, "only " .. checked .. " bound setters were driven; the sweep would prove nothing")
for _, line in ipairs(outside) do
    Check(false, "a scoped control writes outside its root (mark it historyScope = false): " .. line)
end

if #failures > 0 then error("menu_bound_setter_scope_smoke failed:\n  " .. table.concat(failures, "\n  ")) end
print(("menu_bound_setter_scope_smoke: %s ok (%d bound setters stay inside their root, %d record whole-profile steps)")
    :format(flavor, checked, unscoped))
