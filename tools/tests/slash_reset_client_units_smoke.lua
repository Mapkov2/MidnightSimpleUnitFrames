-- slash_reset_client_units_smoke.lua <repoRoot>
--
-- "/msuf reset" writes default size, position and visibility into every unit
-- table. Its Classic hunk added arena (and Retail's list had boss), so on a
-- client without those units (arena on Classic Era and WoW Forever, boss on
-- Classic Era and TBC) the reset wrote enabled = true and fresh geometry into
-- settings that client never shows. This smoke boots each client's real graph,
-- runs the real command and pins that only units the client supports reset.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    local env = world.env
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local client = assert(world.core.Client, flavor .. ": no MSUF.Client")
    local UF = assert(world.core.UF, flavor .. ": no MSUF.UF")
    -- The reset re-applies every frame afterwards; this smoke is about the data.
    UF.Apply = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UpdateAllFonts = function() end

    env.MSUF_EnsureDB()
    local db = env.MSUF_DB
    for _, key in ipairs({ "player", "boss", "arena" }) do
        db[key] = { width = 999, marker = key }
    end
    local slash = assert(env.SlashCmdList and env.SlashCmdList.MSUF2OPTIONS, flavor .. ": /msuf is not registered")
    slash("reset")

    Check(db.player.width == 275 and db.player.enabled == true, flavor .. ": /msuf reset did not reset the player frame")
    for _, key in ipairs({ "boss", "arena" }) do
        local conf = db[key]
        if client.SupportsUnit(key) then
            Check(conf.width == 180 and conf.enabled == true, flavor .. ": /msuf reset did not reset the " .. key .. " frames")
        else
            Check(conf.width == 999 and conf.enabled == nil and conf.marker == key,
                flavor .. ": /msuf reset wrote " .. key .. " defaults on a client without " .. key .. " frames")
        end
    end
    print("slash_reset_client_units_smoke: ok (" .. flavor .. ")")
end
