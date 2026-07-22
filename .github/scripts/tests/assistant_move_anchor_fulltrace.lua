-- Full-trace guard for the move-vs-anchor class.
--
-- A single fix is not enough: the same intent is resolved by more than one path
-- (parser AND router), so a movement verb missing from the shared set let
-- "drag/scoot/slide name to the left" silently set the Name Text Anchor.  This
-- runs the WHOLE verb x object x direction matrix through the real A.Submit
-- pipeline (with prior name-anchor context, the worst case) and asserts that no
-- movement phrasing ever changes or reports-as-set a text ANCHOR, and never
-- mutates a non-offset setting.  It is the regression net for the entire class.
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

-- Worst case: the previous turn discussed the player name anchor, so any stale
-- context path has maximum opportunity to hijack the movement request.
local function primeContext()
    local c = A.GetContext()
    for k in pairs(c) do c[k] = nil end
    c.lastSetting = "player.nameTextAnchor"
    c.lastUnit, c.lastFrameType, c.lastCategory = "player", "unitframe", "Player / Text"
    c.turnSerial, c.lastSubjectTurn = 5, 5
    c.lastChangeBundle = { { key = "player.nameTextAnchor", attribute = "nameTextAnchor",
        unit = "player", frameType = "unitframe", value = "LEFT", oldValue = "CENTER" } }
end
local function submit(prompt)
    primeContext()
    local ok, res = pcall(A.Submit, prompt)
    return ok and type(res) == "table" and res or { text = tostring(res), status = "error" }
end

local verbs = { "move", "shift", "nudge", "push", "drag", "scoot", "slide" }
-- Objects that name the player's name text, including the screenshot casing.
local objects = { "player name", "player text name", "PLAYER text name", "player name text" }
local directions = { "to the left", "to the right", "left", "right", "up", "down",
    "to the left a bit", "left 10", "10 to the left" }

local total, anchorBugs, wrongMutations = 0, 0, 0
local firstBug
for _, verb in ipairs(verbs) do
    for _, object in ipairs(objects) do
        for _, dir in ipairs(directions) do
            total = total + 1
            local prompt = verb .. " " .. object .. " " .. dir
            local res = submit(prompt)
            local text = tostring(res.text or "")
            local status = tostring(res.status or res.result or "")
            local applied = status == "applied" or status == "unchanged"
            -- A movement request must never resolve to a text anchor...
            if applied and text:find("Anchor", 1, true) then
                anchorBugs = anchorBugs + 1
                firstBug = firstBug or (prompt .. " => " .. text:gsub("\n", " "):sub(1, 70))
            -- ...and must never mutate something that is not an offset.
            elseif applied and text:find("Done. I changed", 1, true) and not text:find("Offset", 1, true) then
                wrongMutations = wrongMutations + 1
                firstBug = firstBug or (prompt .. " => " .. text:gsub("\n", " "):sub(1, 70))
            end
        end
    end
end

Check(anchorBugs == 0, "movement phrasing set a text anchor (" .. anchorBugs .. "/" .. total .. "); first: " .. tostring(firstBug))
Check(wrongMutations == 0, "movement phrasing mutated a non-offset setting (" .. wrongMutations .. "/" .. total .. "); first: " .. tostring(firstBug))

-- Positive assertion: a clear movement request does reach the X/Y offset.
local sample = submit("move PLAYER text name to the left")
Check(tostring(sample.text or ""):find("Offset", 1, true) ~= nil,
    "'move PLAYER text name to the left' must reach the name offset, got: " .. tostring(sample.text):sub(1, 80))

io.write("move/anchor full trace: " .. tostring(total) .. " phrasings, 0 anchor/wrong mutations\n")
print("assistant_move_anchor_fulltrace: PASS")
