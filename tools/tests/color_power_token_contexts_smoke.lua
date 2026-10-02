-- color_power_token_contexts_smoke.lua <repoRoot>
--
-- Group cards name each resource color through a context id
-- "power.token.<token>" (MSUF_Menu2_AdvancedColors_Context). The ids used to be
-- a hand-kept copy of the Colors page's power list (COLOR_POWER_TOKENS); they
-- are derived from it now (review R7). For every power the Colors page lists,
-- on every client: exactly one id resolves, to one target with that power's
-- label, and no power id resolves that the page does not list.
--
-- Boots each client's real core and Options graph (tools/tests/client_world.lua).
-- Plain Lua 5.1 with the repo root as argument.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("color_power_token_contexts_smoke: " .. message, 2) end
    return condition
end

local counts = {}
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local M = Check(world.core.MSUF2, flavor .. ": Menu2 did not load")
    local list = Check(M.ColorsPage and M.ColorsPage.COLOR_POWER_TOKENS, flavor .. ": the Colors page power list is missing")
    local factories = Check(M.ContextColorReferenceFactories, flavor .. ": the context color factories are missing")
    Check(#list >= 11, flavor .. ": only " .. #list .. " powers on the Colors page")
    local listed = {}
    for _, item in ipairs(list) do
        local id = "power.token." .. item.value:lower()
        listed[id] = true
        local targets = M.ResolveContextColorReferences({ id }, {})
        Check(#targets == 1, flavor .. ": " .. id .. " resolves to " .. #targets .. " targets")
        local target = targets[1]
        Check(target.label == item.text or target.title == item.text or target.name == item.text,
            flavor .. ": " .. id .. " is not labelled " .. item.text)
    end
    for id in pairs(factories) do
        if id:match("^power%.token%.") then Check(listed[id], flavor .. ": " .. id .. " is not on the Colors page") end
    end
    counts[#counts + 1] = flavor .. " " .. #list
end
print("color_power_token_contexts_smoke: ok (" .. table.concat(counts, ", ") .. ")")
