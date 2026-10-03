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
return function(root, arenaSlots)
    local saved = {
        CreateFrame = _G.CreateFrame,
        C_Timer = _G.C_Timer,
        MSUF_MAX_ARENA_FRAMES = _G.MSUF_MAX_ARENA_FRAMES,
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
    _G.CreateFrame = saved.CreateFrame
    _G.C_Timer = saved.C_Timer
    _G.MSUF_MAX_ARENA_FRAMES = saved.MSUF_MAX_ARENA_FRAMES
    return ns
end
