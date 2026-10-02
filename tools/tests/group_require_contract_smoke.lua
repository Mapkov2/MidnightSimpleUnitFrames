-- group_require_contract_smoke.lua <repoRoot>
--
-- The group files resolve in-addon exports through MSUF.Require instead of
-- guarding them with type(_G.MSUF_X) == "function": a guard cannot tell an
-- optional collaborator from a provider that was renamed or dropped, so the
-- feature behind it silently stops working (2026-10-01 review, B-C1).
--   * static: no group-owned file guards an MSUF_ export, neither inline nor
--     through a local alias checked right below it;
--   * every client: the group compiler's required exports (the UF settings
--     cache and the castbar statusbar texture resolver) resolve on the real
--     load graph, and a configured temporary max-health texture key reaches the
--     compiled spec through the resolver.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"), "missing " .. relative)
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"))
end

local function ListGroupFiles()
    local files = {}
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- '
        .. '"MidnightSimpleUnitFrames/GroupFrames/*.lua" '
        .. '"MidnightSimpleUnitFrames/UnitFrames/Engine/Group/*.lua" '
        .. '"MidnightSimpleUnitFrames/Game/Forever/GroupFrames/*.lua"'))
    for line in pipe:lines() do files[#files + 1] = line end
    pipe:close()
    Check(#files >= 20, "expected the group-owned Lua files, git ls-files listed " .. #files)
    return files
end

---------------------------------------------------------------------------
-- Static: no function guard on an MSUF_ export
---------------------------------------------------------------------------
local guards = {}
for _, relative in ipairs(ListGroupFiles()) do
    local lines = {}
    for line in (Read(relative) .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    for index, code in ipairs(lines) do
        local name = code:match('type%(%s*_G%.(MSUF_[%w_]+)%s*%)%s*[~=]=%s*"function"')
        if not name then
            local alias, global = code:match("local%s+([%w_]+)%s*=%s*_G%.(MSUF_[%w_]+)%s*$")
            if alias then
                for nextIndex = index + 1, math.min(index + 3, #lines) do
                    if lines[nextIndex]:find("type%(%s*" .. alias .. "%s*%)%s*[~=]=%s*\"function\"") then
                        name = global
                        break
                    end
                end
            end
        end
        if name then guards[#guards + 1] = relative .. ":" .. index .. " guards " .. name end
    end
end
Check(#guards == 0, "group files guard in-addon exports instead of requiring them:\n  "
    .. table.concat(guards, "\n  "))

local config = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
for _, name in ipairs({ "MSUF_UFCore_GetSettingsCache", "MSUF_ResolveStatusbarTextureKey" }) do
    Check(config:find('MSUF.Require("' .. name .. '", CONFIG_FILE)', 1, true),
        "Group_Config no longer requires " .. name)
end

---------------------------------------------------------------------------
-- Every client: the required exports resolve on the real load graph
---------------------------------------------------------------------------
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. " did not boot: " .. tostring(failure and failure.file)
        .. " " .. tostring(failure and failure.message))
    local env, GF = world.env, world.core.GF
    Check(type(rawget(env, "MSUF_UFCore_GetSettingsCache")) == "function", flavor .. ": settings cache export missing")
    local resolve = rawget(env, "MSUF_ResolveStatusbarTextureKey")
    Check(type(resolve) == "function", flavor .. ": statusbar texture resolver export missing")

    GF.EnsureDB()
    local general = env.MSUF_DB.general
    general.tempMaxHealthTexture = "Flat"
    GF.InvalidateCompiledSpecs()
    local spec = GF.CompileSpec("party")
    Check(type(spec) == "table" and type(spec.health) == "table", flavor .. ": the party spec did not compile")
    Check(spec.tempMaxHealth.texture == resolve("Flat"),
        flavor .. ": the temporary max-health texture key bypassed the resolver: " .. tostring(spec.tempMaxHealth.texture))
    general.tempMaxHealthTexture = nil
    GF.InvalidateCompiledSpecs()
end

print("group_require_contract_smoke: ok")
