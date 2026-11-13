-- Capture complete differences from an immutable, detached deep-copy baseline.
-- Baseline/live value records never share identity: an equal value is therefore
-- a scalar. Test this first to avoid a type() call for every unchanged leaf.
local type, next = type, next
local removed = function() end
local empty = {}
local currentRoot, sizes = nil, { [empty] = 0 }
local function UseBaseline(root)
    if root ~= currentRoot then currentRoot, sizes = root, { [empty] = 0 } end
end
local function Size(record)
    local count = sizes[record]
    if count then return count end
    count = 0
    for _ in next, record do count = count + 1 end
    sizes[record] = count
    return count
end
local function CaptureValue(before, after)
    if type(after) ~= "table" then
        if before == after then return nil end
        if after == nil then return removed end
        return after
    end
    local wasTable = type(before) == "table"
    local baseline = wasTable and before or empty
    local changes
    if not wasTable then changes = {} end
    local matched = 0
    for key, value in next, after do
        local previous = baseline[key]
        if previous ~= nil then matched = matched + 1 end
        if value ~= previous then
            local change
            if type(value) == "table" then change = CaptureValue(previous, value)
            else change = value end
            if change ~= nil then
                if not changes then changes = {} end
                changes[key] = change
            end
        end
    end
    if matched ~= Size(baseline) then
        for key in next, baseline do
            if after[key] == nil then
                if not changes then changes = {} end
                changes[key] = removed
            end
        end
    end
    return changes
end
local function Capture(before, after)
    UseBaseline(before)
    return CaptureValue(before, after)
end
-- Materialize only changed ancestors. Everything shared with the old snapshot
-- is private immutable data, never a value record belonging to the live world.
local function Materialize(baseline, changes)
    if changes == nil then return baseline end
    if changes == removed then return nil end
    if type(changes) ~= "table" then return changes end
    local before = type(baseline) == "table" and baseline or empty
    local out = {}
    for key, value in next, before do out[key] = value end
    for key, change in next, changes do out[key] = Materialize(before[key], change) end
    return out
end
local function Snapshot(baseline, actual)
    local changes = Capture(baseline, actual)
    return Materialize(baseline, changes), changes
end
-- Fresh deltas restore the same values as Replace without scanning unchanged
-- records again. Surviving tables keep their identity, as with full Replace.
local function Restore(dst, baseline, changes, replace)
    if not changes then return end
    for key, change in next, changes do
        local original = baseline[key]
        if type(original) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
                replace(dst[key], original)
            elseif type(change) == "table" then Restore(dst[key], original, change, replace)
            else replace(dst[key], original) end
        else dst[key] = original end
    end
end
-- A baseline record has immutable cardinality. Checking each actual member and
-- the expected count detects both extra and missing keys without a second walk
-- over every unchanged subtree. A delta adjusts that count at its own level.
local function MatchValue(baseline, changes, actual)
    if changes == removed then return actual == nil, " removed value" end
    if changes == nil and type(baseline) ~= "table" then return baseline == actual, " values" end
    if changes ~= nil and type(changes) ~= "table" then return changes == actual, " values" end
    if type(actual) ~= "table" then return false, " types" end
    local before = type(baseline) == "table" and baseline or empty
    local expectedCount = Size(before)
    if changes then
        for key, change in next, changes do
            if change == removed then expectedCount = expectedCount - 1
            elseif before[key] == nil then expectedCount = expectedCount + 1 end
        end
    end
    local count = 0
    for key, value in next, actual do
        local previous, change = before[key], changes and changes[key]
        if change ~= nil or value ~= previous then
            local ok, why = MatchValue(previous, change, value)
            if not ok then return false, "." .. tostring(key) .. why end
        end
        count = count + 1
    end
    return count == expectedCount, " missing key"
end
local function Matches(baseline, changes, actual)
    UseBaseline(baseline)
    return MatchValue(baseline, changes, actual)
end
local function VisitLeaves(record, visit, path, depth)
    if type(record) ~= "table" or next(record) == nil then
        visit(table.concat(path, ".", 1, depth))
        return
    end
    local childDepth = depth + 1
    for key, value in next, record do
        path[childDepth] = tostring(key)
        VisitLeaves(value, visit, path, childDepth)
    end
end
local function VisitDelta(before, changes, visit, path, depth)
    if type(before) ~= "table" then
        VisitLeaves(changes, visit, path, depth)
    elseif type(changes) ~= "table" then
        VisitLeaves(before, visit, path, depth)
    else
        local childDepth = depth + 1
        for key, change in next, changes do
            path[childDepth] = tostring(key)
            VisitDelta(before[key], change, visit, path, childDepth)
        end
    end
end
-- Audit only changed paths in a complete delta. Replacing an entire table
-- still visits all its leaves, or its own path when the record was empty.
local function VisitWrites(before, changes, visit)
    if changes ~= nil then VisitDelta(before, changes, visit, {}, 0) end
end
return Capture, Restore, Matches, Snapshot, VisitWrites
