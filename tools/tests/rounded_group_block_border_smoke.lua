-- rounded_group_block_border_smoke.lua <repoRoot>
--
-- A party/raid group block border follows its scope's frame shape
-- (gf_*.frameBarShape). UnitFrames/Effects/MSUF_UF_RoundedFrames.lua repaints
-- every block border at the end of a bulk apply by replaying the state it kept
-- as the conf. That state had no frameBarShape, so with the global Rounded
-- switch off a ROUNDED scope resolved to SQUARE on the replay and its border
-- vanished right after the group painter drew it.
--
-- Plain Lua 5.1, repo root as arg 1. Boots each client's real load graph.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    local db = env.MSUF_DB
    db.bars.roundedFramesEnabled = false
    db.gf_party = db.gf_party or {}
    local conf = db.gf_party
    conf.frameBarShape = "ROUNDED"
    conf.groupBorderSize, conf.groupBorderPadding = 2, 2
    conf.groupBorderR, conf.groupBorderG, conf.groupBorderB, conf.groupBorderA = 0.2, 0.4, 0.6, 1
    env.MSUF_ApplyRoundedUnitframes()
    local paint = env.MSUF_RoundedUF_OnGroupBlockBorder
    Check(type(paint) == "function", flavor .. ": the group block border hook is not exported")

    local host = env.CreateFrame("Frame", nil, env.UIParent)
    host.MSUFGFGroupBorder = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        host.MSUFGFGroupBorder[side] = host:CreateTexture(nil, "OVERLAY")
    end
    Check(paint(host, conf, true) == true, flavor .. ": a ROUNDED scope did not get a rounded block border")
    local state = host._msufRGFBlockBorderState
    Check(state and state.enabled == true, flavor .. ": the rounded block border state is not enabled")

    -- The bulk apply replays every kept block border.
    env.MSUF_ApplyRoundedUnitframes()
    state = host._msufRGFBlockBorderState
    Check(state and state.enabled == true, flavor .. ": the replay removed the rounded border of a ROUNDED scope")
    Check(host._msufRUFForcedStyle == "ROUNDED", flavor .. ": the replay resolved the scope to "
        .. tostring(host._msufRUFForcedStyle))
    Check(state.r == 0.2 and state.size == 2, flavor .. ": the replay lost the border colour or size")

    -- A scope that asks for SQUARE keeps the square border on the replay.
    conf.frameBarShape = "SQUARE"
    paint(host, conf, true)
    env.MSUF_ApplyRoundedUnitframes()
    Check(host._msufRUFForcedStyle == "SQUARE", flavor .. ": a SQUARE scope came back rounded")
    print("rounded_group_block_border_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
