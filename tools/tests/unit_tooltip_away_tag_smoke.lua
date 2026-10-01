-- unit_tooltip_away_tag_smoke.lua <repoRoot>
--
-- The MSUF unit info tooltip (Runtime/MSUF_UnitTooltips.lua) appends <AFK> or
-- <DND> to a player's name line. It used to prefer a cached away provider,
-- _G.MSUF_GetCachedAwayStatus, that no file has defined since 6.0, so only the
-- direct read below it ever ran. The dead guard is gone and the direct read is
-- the one path; this smoke pins what the tag does on each client:
--   * AFK and DND show on players, AFK wins when both are set;
--   * NPCs never get a tag;
--   * a secret flag (chat messaging lockdown) shows no tag and raises nothing;
--   * the tooltip never looks up the retired provider name.
--
-- Plain Lua 5.1, repo root as arg 1.

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

    local infoFrame
    local createFrame = env.CreateFrame
    env.CreateFrame = function(kind, name, ...)
        local frame = createFrame(kind, name, ...)
        if name == "MSUF_PlayerInfoFrame" then infoFrame = frame end
        return frame
    end
    local SECRET = newproxy(false)
    local secretValues = { [SECRET] = true }
    local realIsSecret = env.issecretvalue
    env.issecretvalue = function(value)
        if secretValues[value] then return true end
        return realIsSecret and realIsSecret(value) or false
    end
    local state = { player = true, afk = false, dnd = false }
    env.UnitExists = function() return true end
    env.UnitIsPlayer = function() return state.player end
    env.UnitName = function() return "Bob" end
    env.UnitIsAFK = function() return state.afk end
    env.UnitIsDND = function() return state.dnd end

    -- Count lookups of the retired provider from here on.
    local providerReads = 0
    local meta = getmetatable(env) or {}
    local previousIndex = meta.__index
    meta.__index = function(tbl, key)
        if key == "MSUF_GetCachedAwayStatus" then providerReads = providerReads + 1 end
        if type(previousIndex) == "function" then return previousIndex(tbl, key) end
        if type(previousIndex) == "table" then return previousIndex[key] end
        return nil
    end
    setmetatable(env, meta)

    env.MSUF_EnsureDB()
    local function NameLine(afk, dnd, isPlayer)
        state.afk, state.dnd, state.player = afk, dnd, isPlayer ~= false
        env.MSUF_ShowUnitInfoTooltip("target", "Target")
        Check(infoFrame ~= nil, flavor .. ": the info tooltip frame was never built")
        return infoFrame.name:GetText()
    end
    Check(NameLine(false, false) == "Bob", flavor .. ": a present player got a tag")
    Check(NameLine(true, false) == "Bob <AFK>", flavor .. ": the AFK tag is missing, got " .. tostring(NameLine(true, false)))
    Check(NameLine(false, true) == "Bob <DND>", flavor .. ": the DND tag is missing")
    Check(NameLine(true, true) == "Bob <AFK>", flavor .. ": AFK must win over DND")
    Check(NameLine(true, false, false) == "Bob", flavor .. ": an NPC got an away tag")
    Check(NameLine(SECRET, SECRET) == "Bob", flavor .. ": a secret away flag produced a tag")
    Check(NameLine(false, SECRET) == "Bob", flavor .. ": a secret DND flag produced a tag")
    Check(providerReads == 0, flavor .. ": the tooltip still looks up the retired MSUF_GetCachedAwayStatus ("
        .. providerReads .. " reads)")
    print("unit_tooltip_away_tag_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
