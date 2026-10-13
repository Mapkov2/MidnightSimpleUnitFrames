-- castbar_pool_namespace.lua -- test helper, not a smoke.
--
-- Loads the real boss and arena pool modules and their previews
-- (MSUF_CastbarPools.lua, MSUF_CastbarPoolPreviews.lua and the four kind
-- files) into a fresh addon namespace, for smokes whose walkers iterate
-- MSUF.Castbars.Pools. Nothing is built: pool.Bar and preview:Frame read the
-- pool table and the named frames the caller publishes in _G.
--
-- Usage (Lua 5.1):
--   local PoolNamespace = assert(loadfile(root .. "/tools/tests/castbar_pool_namespace.lua"))()
--   local ns = PoolNamespace(root, 5)   -- arena slots; nil = the Mainline fallback 3
local function BindFrames(ns, arenaSlots)
    local frames, pools = ns.Castbars.Frames, ns.Castbars.Pools
    for _, kind in ipairs({ "boss", "arena" }) do
        local prefix = kind == "boss" and "MSUF_Boss" or "MSUF_Arena"
        local live = _G[prefix .. "Castbars"]
        pools.live[kind] = live
        local count = kind == "boss" and 5 or (arenaSlots or 3)
        for index = 1, count do
            frames.Register(kind, index, (live and live[index]) or _G[prefix .. "Castbar" .. index])
            local name = prefix .. "CastbarPreview" .. (kind == "boss" and index == 1 and "" or index)
            frames.Register(kind .. "Preview", index, _G[name])
        end
    end
end

return function(root, arenaSlots, existing)
    local loadfile = assert(loadfile(root .. "/tools/tests/castbar_namespace_fixture.lua"))().Loader(loadfile)
    if existing then
        BindFrames(existing, arenaSlots)
        return existing
    end
    local fakeBoss, fakeArena = _G.MSUF_BossCastbars, _G.MSUF_ArenaCastbars
    local saved = {
        CreateFrame = _G.CreateFrame,
        C_Timer = _G.C_Timer,
        MSUF_MAX_ARENA_FRAMES = _G.MSUF_MAX_ARENA_FRAMES,
        MSUF_EventBus_Register = _G.MSUF_EventBus_Register,
        MSUF_EventBus_Unregister = _G.MSUF_EventBus_Unregister,
    }
    local function Stub()
        local stub = {}
        function stub:SetScript() end
        function stub:RegisterEvent() end
        function stub:UnregisterEvent() end
        function stub:UnregisterAllEvents() end
        return stub
    end
    _G.CreateFrame = Stub
    _G.C_Timer = { After = function() end }
    -- The shared EventBus is outside this helper: subscriptions are accepted, nothing is delivered.
    _G.MSUF_EventBus_Register = function() return true end
    _G.MSUF_EventBus_Unregister = function() end
    _G.MSUF_MAX_ARENA_FRAMES = arenaSlots
    local ns = {}
    function ns.ExportPublic(name, value)
        _G[name] = value
        return value
    end
    for _, file in ipairs({
        "MSUF_CastbarPools.lua", "MSUF_CastbarPoolPreviews.lua",
        "MSUF_BossCastbars.lua", "MSUF_BossCastbars_Preview.lua",
        "MSUF_ArenaCastbars.lua", "MSUF_ArenaCastbars_Preview.lua",
    }) do
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/" .. file))("MidnightSimpleUnitFrames", ns)
    end
    ns.Castbars.Pools.live.boss, ns.Castbars.Pools.live.arena = fakeBoss, fakeArena
    for _, kind in ipairs({ "boss", "arena" }) do
        local prefix = kind == "boss" and "MSUF_Boss" or "MSUF_Arena"
        local count = kind == "boss" and 5 or (arenaSlots or 3)
        for index = 1, count do
            ns.Castbars.Frames.Register(kind, index, _G[prefix .. "Castbar" .. index])
            local name = prefix .. "CastbarPreview" .. (kind == "boss" and index == 1 and "" or index)
            ns.Castbars.Frames.Register(kind .. "Preview", index, _G[name])
        end
    end
    BindFrames(ns, arenaSlots)
    _G.CreateFrame = saved.CreateFrame
    _G.C_Timer = saved.C_Timer
    _G.MSUF_EventBus_Register = saved.MSUF_EventBus_Register
    _G.MSUF_EventBus_Unregister = saved.MSUF_EventBus_Unregister
    _G.MSUF_MAX_ARENA_FRAMES = saved.MSUF_MAX_ARENA_FRAMES
    return ns
end
