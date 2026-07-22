-- Screenshot regression: "move player name to the left" must MOVE the name
-- (X/Y offset), not set its Name Text Anchor to LEFT.  A movement verb
-- (move/shift/nudge/push/raise/lower) plus a directional phrase like "to the
-- left" is a position change; only an explicit anchor/align word means anchor.
--
-- The fix guards A._ParseNameTextAnchorShortcut so a movement verb without an
-- anchor/align word hands the request to the offset path.  This drives the real
-- parser via the context-free A.Parse so no leftover conversation context can
-- mask the resolution.
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

local function resolvedKey(prompt)
    if A.GetContext then local c = A.GetContext() for k in pairs(c) do c[k] = nil end end
    local r = A.Parse(prompt)
    local setting = r and ((r.changes and r.changes[1] and r.changes[1].setting) or r.setting)
    return setting and tostring(setting.key) or nil, r
end

-- Every movement verb + direction, across units, must resolve to the matching
-- offset axis (X for left/right, Y for up/down) and never to the name anchor.
local cases = {
    { "move player name to the left", "player.nameOffsetX" },
    { "move player name on player frame to the left", "player.nameOffsetX" },
    { "shift player name to the right", "player.nameOffsetX" },
    { "nudge player name to the left", "player.nameOffsetX" },
    { "move target name to the right", "target.nameOffsetX" },
    { "move focus name up", "focus.nameOffsetY" },
    { "move boss name down", "boss.nameOffsetY" },
}
for i = 1, #cases do
    local prompt, want = cases[i][1], cases[i][2]
    local key = resolvedKey(prompt)
    Check(key == want, "'" .. prompt .. "' must resolve to " .. want .. ", got " .. tostring(key))
    -- Hard guarantee: a movement request must never land on the anchor.
    Check(key ~= "player.nameTextAnchor" and key ~= "target.nameTextAnchor"
        and key ~= "focus.nameTextAnchor" and key ~= "boss.nameTextAnchor",
        "'" .. prompt .. "' must not set the name anchor")
end

-- The guard predicate itself: a movement verb without anchor/align is a move.
Check(A.HasNudgeMovementVerb("move player name to the left") == true, "move must be a movement verb")
Check(A.HasNudgeMovementVerb("shift player name") == true, "shift must be a movement verb")
Check(A.HasNudgeMovementVerb("anchor player name to the left") == false, "anchor is not a movement verb")
Check(A.HasNudgeMovementVerb("align player name left") == false, "align is not a movement verb")

-- Genuine ambiguity: a bare "name to the left/right" (no move verb, no
-- anchor/align word) must ASK with a two-way anchor-vs-position choice rather
-- than silently pick one.
local function parsed(prompt)
    if A.GetContext then local c = A.GetContext() for k in pairs(c) do c[k] = nil end end
    return A.Parse(prompt)
end
for _, prompt in ipairs({ "player name to the left", "player name to the right" }) do
    local r = parsed(prompt)
    Check(type(r) == "table" and r.kind == "ambiguous",
        "'" .. prompt .. "' must ask (ambiguous), got " .. tostring(r and r.kind))
    Check(type(r.choices) == "table" and #r.choices == 2,
        "'" .. prompt .. "' must offer exactly two choices (anchor vs position)")
    -- One choice must be the anchor, the other the X offset.
    local keys = {}
    for i = 1, #r.choices do
        keys[tostring(r.choices[i].setting and r.choices[i].setting.key)] = true
    end
    Check(keys["player.nameTextAnchor"], "one choice must be the name text anchor")
    Check(keys["player.nameOffsetX"], "one choice must be the name X offset")
end
-- An explicit anchor/align phrasing must NOT trigger the ambiguity choice.
Check(parsed("align player name left").kind ~= "ambiguous", "'align ... left' is not ambiguous")
-- A movement request must NOT trigger the ambiguity choice.
Check(parsed("move player name to the left").kind ~= "ambiguous", "'move ... to the left' is not ambiguous")

print("assistant_move_vs_anchor_smoke: PASS")
