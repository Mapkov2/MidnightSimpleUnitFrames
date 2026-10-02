--- Castbars/MSUF_ArenaCastbars.lua
--- Live arena castbar pool: the arena descriptor of MSUF_CastbarPools.lua.
---
--- arena1..N follow the opponent lifecycle instead of encounter events.
--- ARENA_OPPONENT_UPDATE refreshes the one bar it names (seen, unseen,
--- destroyed, cleared and Solo Shuffle round rebinds) and queues a pool pass
--- when the token is unknown or secret; ARENA_PREP_OPPONENT_SPECIALIZATIONS and
--- PVP_MATCH_STATE_CHANGED queue a pool pass, and a completed match stops every
--- bar. The menu-facing globals (MSUF_ApplyArenaCastbarPositionSetting,
--- MSUF_ApplyArenaCastbarsEnabled, MSUF_ArenaCastbar_Stop,
--- MSUF_ArenaCastbars_SyncLifecycle, MSUF_ArenaCastbars) stay as compatibility
--- aliases of the pool module.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local Pools = assert(MSUF.Castbars and MSUF.Castbars.Pools, "MSUF_CastbarPools.lua must load first")

-- arena1..N (N = MSUF.Client.MaxArenaOpponents: 3 on Mainline, 5 on TBC/Mists).
-- Game/Shared/Initialize.lua publishes it as MSUF_MAX_ARENA_FRAMES; clamp it to
-- 0..5 and fall back to 3 when the client initializer did not run.
local MAX_ARENA_FRAMES = math.max(0, math.min(5, math.floor(tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)))
-- Classic Era and WoW Forever load this file without arena units
-- (MSUF.Client.SupportsUnit). The answer is fixed for the session, so read it once.
local HAS_ARENA_UNITS = not (MSUF.Client and MSUF.Client.SupportsUnit and not MSUF.Client.SupportsUnit("arena"))
-- The client model's answer includes its Classic event denylist; a partial
-- load without the client model asks the event table directly.
local HAS_PVP_MATCH_STATE_CHANGED
if MSUF.Client and type(MSUF.Client.SupportsEvent) == "function" then
    HAS_PVP_MATCH_STATE_CHANGED = MSUF.Client.SupportsEvent("PVP_MATCH_STATE_CHANGED") == true
else
    HAS_PVP_MATCH_STATE_CHANGED = _G.C_EventUtils
        and type(_G.C_EventUtils.IsEventValid) == "function"
        and _G.C_EventUtils.IsEventValid("PVP_MATCH_STATE_CHANGED") == true
end

local function MatchIsComplete()
    local isComplete = _G.C_PvP and _G.C_PvP.IsMatchComplete
    return type(isComplete) == "function" and isComplete() == true
end

local pool = Pools.Define({
    kind = "arena",
    unitPrefix = "arena",
    maxFrames = MAX_ARENA_FRAMES,
    hasUnits = HAS_ARENA_UNITS,
    framePrefix = "MSUF_ArenaCastbar",
    poolGlobal = "MSUF_ArenaCastbars",
    publishPool = function(castbars) ExportPublic("MSUF_ArenaCastbars", castbars) end,
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
    layoutDelta = "MSUF_GetArenaLayoutDelta",
    previewUpdate = "MSUF_UpdateArenaCastbarPreview",
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

ExportPublic("MSUF_ApplyArenaCastbarPositionSetting", pool.ApplyPositionSetting)
ExportPublic("MSUF_ApplyArenaCastbarsEnabled", pool.ApplyEnabled)
ExportPublic("MSUF_ArenaCastbar_Stop", pool.Stop)
ExportPublic("MSUF_ArenaCastbars_SyncLifecycle", pool.SyncLifecycle)
