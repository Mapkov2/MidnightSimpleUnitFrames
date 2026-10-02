-- uf_sibling_called_exports_smoke.lua <repoRoot>
--
-- Engine functions with no Classic caller that a sibling addon tree still
-- calls stay defined: a dead-code removal needs zero callers across Classic,
-- the Retail tree and the Suite. Each row names the sibling caller.
--   UF.GetSecureHeaderUnitButtonTemplate: the Retail tree's
--     UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua builds its header
--     buttons from it (wave 4 removed it as dead; CX-R7 restored it).
-- Every client boots its real core graph; the export must exist and return the
-- same template the single-unit buttons use.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local UF = world.core.UF
    Check(type(UF.GetSecureHeaderUnitButtonTemplate) == "function",
        flavor .. ": UF.GetSecureHeaderUnitButtonTemplate is gone; the Retail group headers call it")
    Check(UF.GetSecureHeaderUnitButtonTemplate() == UF.GetSecureUnitButtonTemplate(),
        flavor .. ": the header button template differs from the unit button template")
    print("uf_sibling_called_exports_smoke: ok (" .. flavor .. ")")
end
