-- Full-trace guard for the color-request class.
--
-- AutoCoverage decomposes composite colors into R/G/B/A channel scalars.  A
-- color value ("set X color to red") must reach a real color setting or a safe
-- clarification -- never a single channel, and never a wrong mutation.  This
-- runs "set <label> to red" for EVERY writable color setting through the real
-- A.Submit pipeline and asserts the whole class stays correct and safe.
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

-- A color-channel component must never be the resolved target of a color value.
local function mentionsChannel(text)
    text = tostring(text or ""):lower()
    return text:find("red channel", 1, true) or text:find("green channel", 1, true)
        or text:find("blue channel", 1, true) or text:find("alpha channel", 1, true)
end

local total, resolved, landedOnChannel = 0, 0, 0
local firstChannelBug
for _, s in ipairs(Registry:AllSettings()) do
    if s.type == "color" and s.assistantMutationSafe ~= false and s.label then
        total = total + 1
        local res = submit("set " .. tostring(s.label) .. " to red")
        local status = tostring(res.status or res.result or "")
        local text = tostring(res.text or "")
        -- Every color request must end in a real outcome: an applied change, a
        -- read-only clarification, or a safe failure -- but never a channel.
        if status == "applied" or status == "unchanged" then resolved = resolved + 1 end
        if (status == "applied" or status == "unchanged") and mentionsChannel(text) then
            landedOnChannel = landedOnChannel + 1
            firstChannelBug = firstChannelBug or (tostring(s.label) .. " => " .. text:sub(1, 70))
        end
        -- A change that landed on a color-channel setting key is the real bug.
        if res.changes then
            for j = 1, #res.changes do
                local key = res.changes[j].setting and tostring(res.changes[j].setting.key) or ""
                if res.changes[j].setting and res.changes[j].setting.assistantColorChannel == true then
                    landedOnChannel = landedOnChannel + 1
                    firstChannelBug = firstChannelBug or (tostring(s.label) .. " => channel " .. key)
                end
            end
        end
    end
end

Check(total > 100, "expected many writable color settings, got " .. total)
Check(landedOnChannel == 0,
    "a color value resolved to a single channel (" .. landedOnChannel .. "/" .. total .. "); first: " .. tostring(firstChannelBug))
-- The large majority must resolve to a concrete color mutation, not a fallback.
Check(resolved >= math.floor(total * 0.95),
    "too few color requests resolved to a concrete change: " .. resolved .. "/" .. total)

io.write("color-request full trace: " .. total .. " color settings, " .. resolved
    .. " resolved, 0 landed on a channel\n")
print("assistant_color_request_fulltrace: PASS")
