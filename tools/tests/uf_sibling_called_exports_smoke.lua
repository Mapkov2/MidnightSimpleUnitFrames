-- uf_sibling_called_exports_smoke.lua <repoRoot>
--
-- Engine functions with no caller in this tree stay defined only while a
-- sibling addon tree still calls them: a dead-code removal needs zero callers
-- across this repo, the Suite and the other addons. Each row names its caller.
--   (no rows) UF.GetSecureHeaderUnitButtonTemplate was kept for the Retail
--     tree's UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua. That tree is
--     retired (6.22 is a frozen backup, 7.0 builds its group header buttons
--     itself), so the alias is gone; the pin below keeps it gone.
-- Every client boots its real core graph; the single-unit button template
-- accessor must remain, and the retired alias must not return.
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
    Check(type(UF.GetSecureUnitButtonTemplate) == "function",
        flavor .. ": UF.GetSecureUnitButtonTemplate is gone; every unit button is built from it")
    Check(UF.GetSecureUnitButtonTemplate() == "SecureUnitButtonTemplate, PingableUnitFrameTemplate",
        flavor .. ": the unit button template changed")
    Check(UF.GetSecureHeaderUnitButtonTemplate == nil,
        flavor .. ": UF.GetSecureHeaderUnitButtonTemplate returned; no caller remains in any tree")
    print("uf_sibling_called_exports_smoke: ok (" .. flavor .. ")")
end
