-- Full-trace natural-language coverage for enum and boolean settings.
--
-- A human says "set growth to right down" and "enable player name", not the raw
-- enum token.  This drives every writable enum with its human value label and
-- every writable boolean with an enable phrasing through the real A.Submit
-- pipeline, and asserts both a high resolution rate and -- the safety
-- invariant -- zero wrong-target mutations.
_G = _G or _ENV
_G.unpack = _G.unpack or table.unpack

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function e(p) local h = io.open(p, "r") if h then h:close() return true end return false end
dofile((e(root .. "/tools/assistant_runtime_manifest_loader.lua") and root .. "/tools/assistant_runtime_manifest_loader.lua")
    or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
dofile((e(root .. "/tools/assistant_dashboard_smoke.lua") and root .. "/tools/assistant_dashboard_smoke.lua")
    or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
local A = _G.MSUF_NS.Assistant
if A.AutoCoverage and A.AutoCoverage.EnsureFilled then pcall(A.AutoCoverage.EnsureFilled) end
Check(type(A.Submit) == "function", "A.Submit must exist")

local Registry = A.Registry
local function submit(prompt)
    local c = A.GetContext() for k in pairs(c) do c[k] = nil end
    local ok, res = pcall(A.Submit, prompt)
    return ok and type(res) == "table" and res or { status = "error" }
end
local function appliedTo(res, key)
    local status = tostring(res.status or res.result or "")
    if status ~= "applied" and status ~= "unchanged" then return false, false end
    local wrong = false
    if res.changes then
        for j = 1, #res.changes do
            local hit = res.changes[j].setting and tostring(res.changes[j].setting.key) or ""
            if hit ~= "" and hit ~= key then wrong = true end
        end
    end
    return true, wrong
end

-- Enum: use the human value label the user would actually say.
local enumTotal, enumApplied, enumWrong = 0, 0, 0
for _, s in ipairs(Registry:AllSettings()) do
    if s.type == "enum" and s.assistantMutationSafe ~= false and s.label
        and s.values and #s.values > 0
    then
        enumTotal = enumTotal + 1
        local raw = s.values[#s.values]
        local label = (s.valueLabels and s.valueLabels[raw])
            or (A.HumanizeDisplayKey and A.HumanizeDisplayKey(raw)) or raw
        local ok, wrong = appliedTo(submit("set " .. tostring(s.label) .. " to " .. tostring(label)), tostring(s.key))
        if ok then enumApplied = enumApplied + 1 end
        if wrong then enumWrong = enumWrong + 1 end
    end
end

-- Boolean: an enable phrasing, falling back to "turn on".
local boolTotal, boolApplied, boolWrong = 0, 0, 0
for _, s in ipairs(Registry:AllSettings()) do
    if s.type == "boolean" and s.assistantMutationSafe ~= false and s.label then
        boolTotal = boolTotal + 1
        local ok, wrong = appliedTo(submit("enable " .. tostring(s.label)), tostring(s.key))
        if not ok then ok, wrong = appliedTo(submit("turn on " .. tostring(s.label)), tostring(s.key)) end
        if ok then boolApplied = boolApplied + 1 end
        if wrong then boolWrong = boolWrong + 1 end
    end
end

Check(enumTotal > 300 and boolTotal > 300, "expected many enum/boolean settings")
-- Safety invariant first: no natural request may move a different setting.
Check(enumWrong == 0, "enum request mutated a different setting: " .. enumWrong .. "/" .. enumTotal)
Check(boolWrong == 0, "boolean request mutated a different setting: " .. boolWrong .. "/" .. boolTotal)
-- Coverage floors (set below the measured 89.8% / 98.8% so real drift trips it).
Check(enumApplied >= math.floor(enumTotal * 0.85),
    "enum natural coverage dropped: " .. enumApplied .. "/" .. enumTotal)
Check(boolApplied >= math.floor(boolTotal * 0.95),
    "boolean natural coverage dropped: " .. boolApplied .. "/" .. boolTotal)

io.write(string.format("natural coverage: enum %d/%d (%.1f%%), boolean %d/%d (%.1f%%), 0 wrong-target\n",
    enumApplied, enumTotal, enumApplied * 100 / enumTotal,
    boolApplied, boolTotal, boolApplied * 100 / boolTotal))
print("assistant_natural_coverage_fulltrace: PASS")
