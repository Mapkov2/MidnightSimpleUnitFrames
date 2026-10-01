-- rounded_outline_thickness_smoke.lua <repoRoot>
--
-- Rounded Frames draws a unit frame's outline as a stack of rounded edge
-- textures, one per pixel of thickness. It read the thickness from
-- _G.MSUF_GetDesiredBarBorderThicknessAndStamp, a provider no file defines, so
-- it always fell back to the global bars.barOutlineThickness and ignored a
-- unit's own outline override (hlOverride + barOutlineThickness). The compiled
-- spec (MSUFSpec.border.thickness, unit and group config) is the source now.
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
    local bars = env.MSUF_DB.bars
    bars.roundedFramesEnabled = true
    bars.roundedUnitFrames = true
    bars.barOutlineThickness = 1
    env.MSUF_ApplyRoundedUnitframes()
    local refresh = env.MSUF_RoundedUF_OnRareVisualsRefreshed
    Check(type(refresh) == "function", flavor .. ": the rounded rare-visual hook is not exported")

    local function EdgeCount(spec)
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = "player"
        frame.MSUFSpec = spec
        refresh(frame)
        local stack = frame._msufRUF_EdgeStack
        return stack and stack._msufCount or 0
    end
    -- A unit override of 4 px draws four edges while the global outline is 1.
    Check(EdgeCount({ key = "player", border = { thickness = 4 } }) == 4,
        flavor .. ": the unit's own outline thickness was ignored (got "
        .. EdgeCount({ key = "player", border = { thickness = 4 } }) .. " edges)")
    -- A frame without a compiled border keeps the global value.
    bars.barOutlineThickness = 3
    Check(EdgeCount({ key = "player" }) == 3, flavor .. ": the global outline fallback was lost")
    -- The rounded outline caps at 8 px like before.
    Check(EdgeCount({ key = "player", border = { thickness = 20 } }) == 8, flavor .. ": the 8 px cap was lost")
    -- Zero hides the outline.
    Check(EdgeCount({ key = "player", border = { thickness = 0 } }) == 0, flavor .. ": a 0 px override still drew edges")
    Check(env.MSUF_GetDesiredBarBorderThicknessAndStamp == nil,
        flavor .. ": a provider that used to be defined nowhere appeared; wire it on purpose or drop it")
    print("rounded_outline_thickness_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
