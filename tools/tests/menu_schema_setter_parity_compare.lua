-- Capture complete differences from an immutable, detached deep-copy baseline.
-- Baseline/live value records never share identity: an equal value is therefore
-- a scalar. Test this first to avoid a type() call for every unchanged leaf.
local type, next = type, next
local removed = function() end
local empty = {}
local currentRoot, sizes = nil, { [empty] = 0 }
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
    if before ~= currentRoot then currentRoot, sizes = before, { [empty] = 0 } end
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
    return Materialize(baseline, Capture(baseline, actual))
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
-- Compare the complete expected profile (baseline plus delta) with a live
-- branch. Unchanged subtrees go through the original full equality function;
-- the two key sweeps also reject missing expected keys and unexpected writes.
local function Matches(baseline, changes, actual, equal)
    if changes == nil then return equal(baseline, actual) end
    if changes == removed then return actual == nil, " removed value" end
    if type(changes) ~= "table" then return equal(changes, actual) end
    if type(actual) ~= "table" then return false, " types" end
    local before = type(baseline) == "table" and baseline or empty
    for key, value in next, before do
        local change, other = changes[key], actual[key]
        local ok, why
        if change ~= nil then ok, why = Matches(value, change, other, equal)
        elseif type(value) == "table" then ok, why = equal(value, other)
        else ok, why = value == other, " values" end
        if not ok then return false, "." .. tostring(key) .. tostring(why) end
    end
    for key, change in next, changes do
        if before[key] == nil then
            local ok, why = Matches(nil, change, actual[key], equal)
            if not ok then return false, "." .. tostring(key) .. tostring(why) end
        end
    end
    for key in next, actual do
        if before[key] == nil and changes[key] == nil then return false, "." .. tostring(key) .. " extra" end
    end
    return true
end
return Capture, Restore, Matches, Snapshot
