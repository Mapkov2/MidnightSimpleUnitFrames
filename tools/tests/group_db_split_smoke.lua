-- group_db_split_smoke.lua <repoRoot>
--
-- MSUF_GroupFrames_DB.lua was split by cohesion into the core (defaults, DB
-- repair entry, config access) and its _Geometry, _Text and _Textures parts
-- (2026-10-01). The parts share one MSUF.GF table, so two things must hold on
-- every client:
--   * load order: DB, Geometry, Text, Textures, then Migrations, before any other
--     group file, in each client's real load graph;
--   * every public export of the four files resolves after boot. An export that
--     reads a GF function from a part loading later publishes nil (the split
--     first exported MSUF_GF_GetHighlightVal from the core that way).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local PARTS = {
    "GroupFrames/MSUF_GroupFrames_DB.lua",
    "GroupFrames/MSUF_GroupFrames_DB_Geometry.lua",
    "GroupFrames/MSUF_GroupFrames_DB_Text.lua",
    "GroupFrames/MSUF_GroupFrames_DB_Textures.lua",
    "GroupFrames/MSUF_GroupFrames_DB_Migrations.lua",
}

local exports = {}
for index = 1, 4 do
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/" .. PARTS[index], "rb"))
    local source = file:read("*a")
    file:close()
    for name in source:gmatch('ExportPublic%("([%w_]+)"') do exports[#exports + 1] = name end
end
Check(#exports >= 15, "the group DB files publish only " .. #exports .. " exports")

for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. " did not boot: " .. tostring(failure and failure.file))
    local position, firstGroup = {}, nil
    for index, path in ipairs(world.loaded) do
        local relative = path:gsub("^MidnightSimpleUnitFrames/", "")
        position[relative] = index
        if not firstGroup and (relative:find("^GroupFrames/") or relative:find("^UnitFrames/Engine/Group/")) then
            firstGroup = relative
        end
    end
    Check(firstGroup == PARTS[1], flavor .. ": the first group file is " .. tostring(firstGroup))
    for index = 1, #PARTS do
        Check(position[PARTS[index]] ~= nil, flavor .. " does not load " .. PARTS[index])
        if index > 1 then
            Check(position[PARTS[index]] == position[PARTS[index - 1]] + 1,
                flavor .. ": " .. PARTS[index] .. " must load right after " .. PARTS[index - 1])
        end
    end
    for _, name in ipairs(exports) do
        Check(rawget(world.env, name) ~= nil, flavor .. ": " .. name .. " is published as nil")
    end
end

print(string.format("group_db_split_smoke: ok (%d exports, 5 clients)", #exports))
