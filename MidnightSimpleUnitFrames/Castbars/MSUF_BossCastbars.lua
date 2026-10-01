--- Castbars/MSUF_BossCastbars.lua
--- Live boss castbar pool: the boss descriptor of MSUF_CastbarPools.lua.
---
--- boss1..N follow the encounter lifecycle. ENCOUNTER_START and
--- INSTANCE_ENCOUNTER_ENGAGE_UNIT queue one pool pass plus a one-bar-per-frame
--- anchor prewarm, UNIT_TARGETABLE_CHANGED refreshes the one bar it names, and
--- ENCOUNTER_END stops every bar and cancels queued work. The menu-facing
--- globals (MSUF_ApplyBossCastbarPositionSetting, MSUF_ApplyBossCastbarsEnabled,
--- MSUF_BossCastbar_Stop, MSUF_BossCastbars_SyncLifecycle, MSUF_BossCastbars)
--- stay as compatibility aliases of the pool module.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local Pools = assert(MSUF.Castbars and MSUF.Castbars.Pools, "MSUF_CastbarPools.lua must load first")

--- Boss units are a client fact: Classic Era and TBC have none. Read once at
--- load, never per refresh.
local HAS_BOSS_UNITS = not (MSUF.Client and MSUF.Client.SupportsUnit and not MSUF.Client.SupportsUnit("boss"))
local MAX_BOSS_FRAMES = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
if MAX_BOSS_FRAMES < 1 or MAX_BOSS_FRAMES > 12 then
    MAX_BOSS_FRAMES = 5
end

Pools.Define({
    kind = "boss",
    unitPrefix = "boss",
    maxFrames = MAX_BOSS_FRAMES,
    hasUnits = HAS_BOSS_UNITS,
    framePrefix = "MSUF_BossCastbar",
    poolGlobal = "MSUF_BossCastbars",
    kindFlag = "_msufIsBossCastbar",
    frameLevelBase = 50,
    fallbackY = -220,
    enableKey = "enableBossCastbar",
    db = {
        offsetX = "bossCastbarOffsetX",
        offsetY = "bossCastbarOffsetY",
        detached = "bossCastbarDetached",
        width = "bossCastbarWidth",
        height = "bossCastbarHeight",
    },
    layoutDelta = "MSUF_GetBossLayoutDelta",
    previewUpdate = "MSUF_UpdateBossCastbarPreview",
    scheduleKeys = { pass = "MSUF_BOSS_POOL_LIFECYCLE", prewarm = "MSUF_BOSS_POOL_PREWARM" },
    lifecycle = {
        { event = "PLAYER_LOGIN", key = "MSUF_BOSS_CASTBARS_LOGIN", action = "pass", once = true },
        { event = "PLAYER_ENTERING_WORLD", key = "MSUF_BOSS_CASTBARS_WORLD", action = "pass" },
        { event = "INSTANCE_ENCOUNTER_ENGAGE_UNIT", key = "MSUF_BOSS_CASTBARS_ENGAGE", action = "pass", prewarm = true },
        { event = "ENCOUNTER_START", key = "MSUF_BOSS_CASTBARS_START", action = "pass", prewarm = true },
        { event = "ENCOUNTER_END", key = "MSUF_BOSS_CASTBARS_END", action = "terminal" },
        -- A UNIT_* event: the bus needs the pool's own boss tokens as filter.
        { event = "UNIT_TARGETABLE_CHANGED", key = "MSUF_BOSS_CASTBARS_TARGETABLE", action = "unit", units = true },
    },
    exports = {
        positionSetting = "MSUF_ApplyBossCastbarPositionSetting",
        applyEnabled = "MSUF_ApplyBossCastbarsEnabled",
        stop = "MSUF_BossCastbar_Stop",
        syncLifecycle = "MSUF_BossCastbars_SyncLifecycle",
    },
})
