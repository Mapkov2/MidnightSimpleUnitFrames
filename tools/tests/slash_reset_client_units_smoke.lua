-- slash_reset_client_units_smoke.lua <repoRoot>
--
-- "/msuf reset" puts every frame's size, position, layout and text visibility
-- back to the defaults. Two contracts:
--
--   * Client units: its Classic hunk added arena (and Retail's list had boss),
--     so on a client without those units (arena on Classic Era and WoW Forever,
--     boss on Classic Era and TBC) the reset wrote enabled = true and fresh
--     geometry into settings that client never shows. Only units the client
--     supports reset.
--   * One source of defaults: the values come from the factory default profile
--     (MSUF_CreateFactoryDefaultProfile plus the defaults pass), the profile a
--     new install and "reset profile" start from. A hand-kept copy in
--     Runtime/MSUF_SlashCommands.lua had drifted far from it.
--
-- This smoke boots each client's real graph, feeds the factory pipeline a
-- snapshot with marker values, runs the real command and pins both.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Marker values nobody else uses: the reset must copy exactly these.
local function FactoryPayload()
    return {
        general = { anchorName = "UIParent", anchorToCooldown = false },
        player = { enabled = true, width = 301, height = 41, offsetX = -311, offsetY = -181,
            showName = false, showHP = true, showPower = true },
        target = { enabled = true, width = 302, height = 42, offsetX = 312, offsetY = -182,
            showName = true, showHP = true, showPower = false },
        boss = { enabled = true, width = 171, height = 31, offsetX = 511, offsetY = 371, spacing = -91,
            bossLayoutMode = "VERTICAL_UP", showName = true, showHP = false, showPower = false },
        arena = { enabled = true, width = 172, height = 32, offsetX = 611, offsetY = -241, spacing = -92,
            bossLayoutMode = "VERTICAL_DOWN", showName = true, showHP = true, showPower = true },
        focustarget = { enabled = false, width = 133, height = 23, offsetX = 263, offsetY = 183 },
    }
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
    -- The factory pipeline decodes the embedded export; hand it marker values.
    local factoryAvailable = true
    env.MSUF_TryDecodeCompactString = function()
        if not factoryAvailable then return nil end
        return { addon = "MSUF", fmt = 2, kind = "all", profile = "Default", schema = 1, payload = FactoryPayload(),
            msuf6 = { schema = 600, payload = FactoryPayload() } }
    end

    env.MSUF_EnsureDB()
    local db = env.MSUF_DB
    for _, key in ipairs({ "player", "boss", "arena" }) do
        db[key] = { width = 999, marker = key, enabled = true }
    end
    db.target = { width = 999, enabled = false, marker = "target" }
    db.focustarget = { width = 999 }
    db.pettarget = { width = 999, enabled = true }
    local slash = assert(env.SlashCmdList and env.SlashCmdList.MSUF2OPTIONS, flavor .. ": /msuf is not registered")
    slash("reset")

    local player = db.player
    Check(player.width == 301 and player.height == 41 and player.offsetX == -311 and player.offsetY == -181
        and player.showName == false and player.showHP == true and player.showPower == true,
        flavor .. ": /msuf reset did not put the player frame back to the factory defaults (width "
        .. tostring(player.width) .. ", offsetY " .. tostring(player.offsetY) .. ")")
    Check(player.marker == "player" and player.enabled == true, flavor .. ": /msuf reset touched other player settings")
    Check(db.target.width == 302 and db.target.showPower == false and db.target.enabled == false,
        flavor .. ": /msuf reset did not keep a disabled target frame disabled with factory geometry")
    if client.SupportsUnit("focustarget") then
        Check(db.focustarget.width == 133 and db.focustarget.offsetY == 183 and db.focustarget.enabled == false,
            flavor .. ": /msuf reset did not give an unset Focus Target its factory on/off state")
    else
        Check(db.focustarget.width == 999 and db.focustarget.enabled == nil,
            flavor .. ": /msuf reset wrote Focus Target defaults on a client without a focus")
    end
    Check(db.pettarget.width ~= 999 and db.pettarget.enabled == false,
        flavor .. ": /msuf reset did not put Pet Target back to its code default and off")
    for _, key in ipairs({ "boss", "arena" }) do
        local conf, expected = db[key], FactoryPayload()[key]
        if client.SupportsUnit(key) then
            Check(conf.width == expected.width and conf.spacing == expected.spacing
                and conf.bossLayoutMode == expected.bossLayoutMode and conf.showHP == expected.showHP,
                flavor .. ": /msuf reset did not put the " .. key .. " frames back to the factory defaults")
        else
            Check(conf.width == 999 and conf.marker == key and conf.spacing == nil,
                flavor .. ": /msuf reset wrote " .. key .. " defaults on a client without " .. key .. " frames")
        end
    end

    -- Without the factory defaults the command changes nothing.
    factoryAvailable = false
    db.player.width = 555
    world.prints = {}
    slash("reset")
    Check(db.player.width == 555, flavor .. ": /msuf reset changed frames without factory defaults")
    Check(world.prints[#world.prints] and world.prints[#world.prints]:find("Factory defaults are not available", 1, true),
        flavor .. ": /msuf reset did not say why nothing was reset")
    print("slash_reset_client_units_smoke: ok (" .. flavor .. ")")
end
