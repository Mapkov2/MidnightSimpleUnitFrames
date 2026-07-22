-- Full-trace guard for the numeric-setting class (size/width/height/offset/...).
--
-- "set <label> to N" for a writable number setting must either change THAT
-- setting or fail closed / ask -- it must never mutate a different setting.  A
-- wrong-target write is the dangerous case (the user asked for one control and
-- another silently moved).  This runs every writable, bounded number setting
-- through the real A.Submit pipeline and asserts zero wrong-target mutations.
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
    return ok and type(res) == "table" and res or { status = "error", text = tostring(res) }
end

local total, applied, wrongTarget = 0, 0, 0
local firstWrong
for _, s in ipairs(Registry:AllSettings()) do
    if s.type == "number" and s.assistantMutationSafe ~= false and s.label and s.min and s.max then
        total = total + 1
        local value = math.floor((s.min + s.max) / 2)
        local res = submit("set " .. tostring(s.label) .. " to " .. value)
        local status = tostring(res.status or res.result or "")
        if status == "applied" or status == "unchanged" then
            applied = applied + 1
            -- If it applied a change, it must have targeted this exact setting.
            if res.changes then
                for j = 1, #res.changes do
                    local key = res.changes[j].setting and tostring(res.changes[j].setting.key) or ""
                    if key ~= "" and key ~= tostring(s.key) then
                        wrongTarget = wrongTarget + 1
                        firstWrong = firstWrong or (tostring(s.key) .. " => wrote " .. key)
                    end
                end
            end
        end
        -- Any other status (info / ambiguous / failed) is a safe non-mutation.
    end
end

Check(total > 500, "expected many writable number settings, got " .. total)
Check(wrongTarget == 0,
    "a numeric request mutated a different setting (" .. wrongTarget .. "/" .. total .. "); first: " .. tostring(firstWrong))
-- The large majority must resolve to a concrete change, not a fallback.
Check(applied >= math.floor(total * 0.90),
    "too few numeric requests resolved to a concrete change: " .. applied .. "/" .. total)

io.write("numeric-target full trace: " .. total .. " settings, " .. applied
    .. " applied, 0 wrong-target mutations\n")
print("assistant_number_target_fulltrace: PASS")
