--- Arena descriptor: opponent events refresh one bar; unknown tokens queue a pool pass.
--- Completed matches stop the pool. Compatibility/lifecycle details: Castbars/README.md.

local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_ArenaCastbars.lua").Castbars
local Previews = Castbars.Previews
local Config = Castbars.Config
local Pools = Castbars.Pools
local PublicAPI = Castbars.PublicAPI
local Publish = PublicAPI.Publish



-- arena1..N (N = MSUF.Client.MaxArenaOpponents: 3 on Mainline, 5 on TBC/Mists).
-- Game/Shared/Initialize.lua publishes it as MSUF_MAX_ARENA_FRAMES; clamp it to
-- 0..5 and fall back to 3 when the client initializer did not run.
local MAX_ARENA_FRAMES = math.max(0, math.min(5, math.floor(tonumber(MSUF_MAX_ARENA_FRAMES) or 3)))
-- Classic Era and WoW Forever load this file without arena units
-- (MSUF.Client.SupportsUnit). The answer is fixed for the session, so read it once.
local HAS_ARENA_UNITS = not (MSUF.Client and MSUF.Client.SupportsUnit and not MSUF.Client.SupportsUnit("arena"))
-- The client model's answer includes its Classic event denylist; a partial
-- load without the client model asks the event table directly.
local HAS_PVP_MATCH_STATE_CHANGED
if MSUF.Client and type(MSUF.Client.SupportsEvent) == "function" then
    HAS_PVP_MATCH_STATE_CHANGED = MSUF.Client.SupportsEvent("PVP_MATCH_STATE_CHANGED") == true
else
    HAS_PVP_MATCH_STATE_CHANGED = C_EventUtils
        and type(C_EventUtils.IsEventValid) == "function"
        and C_EventUtils.IsEventValid("PVP_MATCH_STATE_CHANGED") == true
end

-- UF_Config loads first and exports the arena layout delta at file load.
local GetArenaLayoutDelta = MSUF.Require("MSUF_GetArenaLayoutDelta", "Castbars/MSUF_ArenaCastbars.lua")

local function MatchIsComplete()
    local isComplete = C_PvP and C_PvP.IsMatchComplete
    return type(isComplete) == "function" and isComplete() == true
end

local pool = Pools.Define({
    kind = "arena",
    unitPrefix = "arena",
    maxFrames = MAX_ARENA_FRAMES,
    hasUnits = HAS_ARENA_UNITS,
    framePrefix = "MSUF_ArenaCastbar",
    poolGlobal = "MSUF_ArenaCastbars",
    publishPool = function(castbars) Pools.ArenaCastbars = castbars
        Pools.live.arena = castbars
    Publish("MSUF_ArenaCastbars", Pools.ArenaCastbars) end,
    kindFlag = "_msufIsArenaCastbar",
    indexField = "_msufArenaIndex",
    -- Above the boss band (51..55), so arena1..5 never share a level with it.
    frameLevelBase = 56,
    fallbackY = -320,
    enableKey = "enableArenaCastbar",
    db = {
        offsetX = "arenaCastbarOffsetX",
        offsetY = "arenaCastbarOffsetY",
        detached = "arenaCastbarDetached",
        width = "arenaCastbarWidth",
        height = "arenaCastbarHeight",
    },
    GetLayoutDelta = function() return GetArenaLayoutDelta end,
    GetPreviewUpdate = function() return Previews.UpdateArenaCastbarPreview end,
    scheduleKeys = { pass = "MSUF_ARENA_POOL_LIFECYCLE" },
    lifecycle = {
        { event = "PLAYER_LOGIN", key = "MSUF_ARENA_CASTBARS_LOGIN", action = "pass", once = true },
        { event = "PLAYER_ENTERING_WORLD", key = "MSUF_ARENA_CASTBARS_WORLD", action = "pass" },
        { event = "ARENA_OPPONENT_UPDATE", key = "MSUF_ARENA_CASTBARS_OPPONENT", action = "unit", unitFallback = "pass" },
        { event = "ARENA_PREP_OPPONENT_SPECIALIZATIONS", key = "MSUF_ARENA_CASTBARS_PREP", action = "pass" },
        -- Terminal only once the match is complete; any other state change is a pass.
        { event = "PVP_MATCH_STATE_CHANGED", key = "MSUF_ARENA_CASTBARS_MATCH", action = "terminal",
            terminalWhen = MatchIsComplete, supported = HAS_PVP_MATCH_STATE_CHANGED },
    },
})

Pools.ApplyArenaCastbarPositionSetting = pool.ApplyPositionSetting
Publish("MSUF_ApplyArenaCastbarPositionSetting", Pools.ApplyArenaCastbarPositionSetting)
Pools.ApplyArenaCastbarsEnabled = pool.ApplyEnabled
Pools.ArenaCastbar_Stop = pool.Stop
Pools.ArenaCastbars_SyncLifecycle = pool.SyncLifecycle
