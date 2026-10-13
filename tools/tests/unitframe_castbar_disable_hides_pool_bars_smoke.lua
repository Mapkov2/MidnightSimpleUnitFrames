-- unitframe_castbar_disable_hides_pool_bars_smoke.lua <repoRoot>
--
-- Turning a boss or arena unit frame's castbar off (UnitFrames/Engine/Elements/
-- MSUF_UF_Elements_Bridges.lua, Castbars.Disable) hides the bars of that pool.
-- The hide used to look up the pre-pool frame names (MSUF_boss1CastBar ...), which
-- no code creates, so the bars the pool builds (MSUF_BossCastbar1, MSUF_ArenaCastbar1
-- ...) stayed on screen. The other pool, the target bar and a unit without a
-- castbar are left alone.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local CORE = root .. "/MidnightSimpleUnitFrames/"

local PoolNamespace = assert(loadfile(root .. "/tools/tests/castbar_pool_namespace.lua"))()
local MSUF = PoolNamespace(root, 3)

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local function NewBar(name)
    local bar = { name = name, shown = true }
    function bar:Hide() self.shown = false end
    function bar:Show() self.shown = true end
    return bar
end

-- The refresh the element queues is not under test: swallow it.
_G.MSUF_ScheduleOnce = function() end

local UF = { elements = {}, elementOrder = {} }
UF.RegisterElement = function(name, element) UF.elements[name] = element end
MSUF.UF = UF
assert(loadfile(CORE .. "Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(CORE .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua"))("MidnightSimpleUnitFrames", MSUF)
local Castbars = assert(UF.elements.Castbars, "the Castbars element did not register")

-- The bars as EnsureCastbars publishes them: pool table plus named frame.
local function Publish(pool, global, prefix, count)
    local bars = {}
    for index = 1, count do
        bars[index] = NewBar(prefix .. index)
        _G[prefix .. index] = bars[index]
    end
    _G[global] = bars
    Check(pool.Bar(1) == bars[1], pool.kind .. " pool Bar(1) does not return the published bar")
    return bars
end

local pools = MSUF.Castbars.Pools.kinds
local bossBars = Publish(pools.boss, "MSUF_BossCastbars", "MSUF_BossCastbar", 5)
-- Arena slot 3 is not built: a missing slot must not break the hide.
local arenaBars = Publish(pools.arena, "MSUF_ArenaCastbars", "MSUF_ArenaCastbar", 2)
local targetBar = NewBar("MSUF_TargetCastbar")
_G.MSUF_TargetCastbar = targetBar

local function Reset()
    for _, bar in ipairs(bossBars) do bar.shown = true end
    for _, bar in ipairs(arenaBars) do bar.shown = true end
    targetBar.shown = true
end

-- 1. A boss frame's castbar turned off hides every boss bar and nothing else.
Reset()
Castbars.Disable({ MSUFUnitKey = "boss2" })
for index, bar in ipairs(bossBars) do
    Check(bar.shown == false, "boss castbar " .. index .. " stayed shown after the boss castbar was turned off")
end
for index, bar in ipairs(arenaBars) do
    Check(bar.shown == true, "arena castbar " .. index .. " was hidden by the boss castbar being turned off")
end
Check(targetBar.shown == true, "the target castbar was hidden by the boss castbar being turned off")

-- 2. The same for arena.
Reset()
Castbars.Disable({ MSUFUnitKey = "arena1" })
for index, bar in ipairs(arenaBars) do
    Check(bar.shown == false, "arena castbar " .. index .. " stayed shown after the arena castbar was turned off")
end
for index, bar in ipairs(bossBars) do
    Check(bar.shown == true, "boss castbar " .. index .. " was hidden by the arena castbar being turned off")
end

-- 3. The target bar is still hidden through its own name.
Reset()
Castbars.Disable({ MSUFUnitKey = "target" })
Check(targetBar.shown == false, "the target castbar stayed shown after it was turned off")
Check(bossBars[1].shown == true and arenaBars[1].shown == true, "turning the target castbar off hid a pool bar")

if failures > 0 then error(("unit frame castbar disable smoke: %d failure(s)"):format(failures)) end
print("unitframe_castbar_disable_hides_pool_bars_smoke: ok")
