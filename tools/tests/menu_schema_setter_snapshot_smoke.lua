-- Frozen snapshot results and limits, with a bounded VM-work regression.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local ns = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileFields.lua"))("test", ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileVariants.lua"))("test", ns)
local function Scalar(value)
    local kind = type(value)
    return kind == "boolean" or (kind == "string" and #value <= 8192)
        or (kind == "number" and value == value and value > -math.huge and value < math.huge)
end
local function ReferenceCopy(value, budget)
    budget=budget or {count=0,limit=131072,maxDepth=32,bytes=0,maxBytes=8388608}
    budget.bytes=budget.bytes or 0
    local why
    local function Copy(entry,depth,seen)
        local kind=type(entry)
        if kind=="string" then
            budget.bytes=budget.bytes+#entry
            if budget.bytes>(budget.maxBytes or 8388608) then why="limits"
                return nil,false end
            return entry,true
        end
        if entry==nil or kind=="boolean" or kind=="number" and Scalar(entry) then return entry,true end
        if kind=="number" then why="number"
            return nil,false end
        if kind~="table" or getmetatable(entry)~=nil then why="value"
            return nil,false end
        if seen[entry] then why="cycle"
            return nil,false end
        if depth>=(budget.maxDepth or 32) then why="limits"
            return nil,false end
        seen[entry]=true
        local out={}
        for key,item in pairs(entry) do
            local keyKind=type(key)
            if keyKind~="string" and keyKind~="boolean" and not (keyKind=="number" and Scalar(key)) then
                why=keyKind=="number" and "number" or "value"
                return nil,false
            end
            if keyKind=="string" then budget.bytes=budget.bytes+#key end
            budget.count=budget.count+1
            if budget.count>(budget.limit or 131072) or budget.bytes>(budget.maxBytes or 8388608) then why="limits"
                return nil,false end
            local copied, valid = item, true
            local itemKind = type(item)
            if itemKind == "table" then
                copied, valid = Copy(item, depth + 1, seen)
            elseif itemKind == "string" then
                budget.bytes = budget.bytes + #item
                if budget.bytes > (budget.maxBytes or 8388608) then why, valid = "limits", false end
            elseif itemKind == "number" then
                valid = Scalar(item)
                if not valid then why = "number" end
            elseif itemKind ~= "boolean" then
                why, valid = "value", false
            end
            if not valid then return nil,false end
            out[key]=copied
        end
        seen[entry]=nil
        return out,true
    end
    local copy,valid=Copy(value,0,{})
    return copy,valid,why
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function CopyBudget(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end
local shared, cycle = { value = 3 }, {}
cycle.self = cycle
local records = { false, 0, "", "abc", -3, math.huge, -math.huge, 0 / 0, function() end,
    setmetatable({}, {}), cycle, {}, { [false] = false, [0] = 0, [1.5] = "fraction" },
    { a = shared, b = shared }, { deep = { nested = { leaf = "value" } } },
    { text = string.rep("x", 8193) }, { [string.rep("k", 13)] = "abc" }, { [{}] = 3 } }
local budgets = { { count = 0 }, { count = 3, bytes = 5 }, { count = 0, limit = 0 },
    { count = 0, limit = 2 }, { count = 0, maxDepth = 1 }, { count = 0, maxDepth = 2 },
    { count = 0, maxBytes = 0 }, { count = 0, maxBytes = 12 } }
local checks = 0
for _, record in ipairs(records) do
    for _, limits in ipairs(budgets) do
        local before, after = CopyBudget(limits), CopyBudget(limits)
        local expected, valid, why = ReferenceCopy(record, before)
        local actual, ok, problem = ns.ProfileFields.CopySnapshot(record, after)
        assert(ok == valid and problem == why, "snapshot validity/reason changed")
        assert(Equal(expected, actual) and Equal(before, after), "snapshot result/accounting changed")
        if ok and type(record) == "table" then assert(actual ~= record, "snapshot aliases its input") end
        if ok and type(record) == "table" and record.a == shared then
            assert(actual.a ~= shared and actual.b ~= shared and actual.a ~= actual.b, "shared descendants were not copied separately")
        end
        checks = checks + 1
    end
end
local before, after = { count = 0, limit = 7, maxBytes = 40 }, { count = 0, limit = 7, maxBytes = 40 }
for _ = 1, 4 do
    local expected, valid, why = ReferenceCopy({ nested = { value = "abc" } }, before)
    local actual, ok, problem = ns.ProfileFields.CopySnapshot({ nested = { value = "abc" } }, after)
    assert(Equal(expected, actual) and ok == valid and problem == why and Equal(before, after), "shared capture budget changed")
    checks = checks + 1
end
local db = { general = {}, player = { width = 200 }, profileVariants = { version = 1, entries = {
    { name = "active", conditions = { context = "party" }, patch = { { path = { "player", "width" }, value = 300 } } }
} } }
local V = ns.ProfileVariants
assert(V.Resolve(db, { location = "party", spec = 71, dark = false }))
db.player.width = 301
local snapshot = assert(V.BaseSnapshot(db, true))
assert(snapshot.player.width == 200 and db.player.width == 301, "base/live overlay changed")
assert(snapshot.profileVariants.entries[1].patch[1].value == 301, "overlay edit was not captured")
assert(V.BaseSnapshot(db, false).profileVariants == nil, "partial snapshot retained variants")
snapshot.player.width = 999
assert(db.player.width == 301, "snapshot is not detached")
V.Restore(false)
assert(db.player.width == 200, "base restore changed")
local profile = { general = {}, player = {} }
for i = 1, 1000 do profile.player["setting" .. i] = i end
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for _ = 1, 10 do assert(V.BaseSnapshot(profile, true)) end
debug.sethook()
print(("snapshot x10: %d VM instructions"):format(instructions))
assert(instructions <= 500000, "snapshot repeats scalar calls/budget table work")
print(("PASS setter snapshot: %d frozen result/limit cases, active overlay and detached copies"):format(checks))
