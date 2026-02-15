-- MSUF Castbar Registry (Step 1 stub)
--
-- Goal (later): central place to register castbar instances (player/target/focus/boss etc.)
-- so the Engine can drive updates consistently.
-- This file is intentionally minimal for now, just a simple registry with no behavior.
-- This file MUST NOT change existing behavior yet.

local addonName, ns = ...
ns = ns or {}

ns.MSUF_CastbarRegistry = ns.MSUF_CastbarRegistry or {}
local R = ns.MSUF_CastbarRegistry

-- barKey -> { unit=string, frame=Frame, styleGetter=function|nil }
R.bars = R.bars or {}

function R:Register(barKey, unit, frame, styleGetter)
    if not barKey then return end
    R.bars[barKey] = {
        unit = unit,
        frame = frame,
        styleGetter = styleGetter,
    }
end

function R:Unregister(barKey)
    if not barKey then return end
    R.bars[barKey] = nil
end

function R:Get(barKey)
    if not barKey then return nil end
    return R.bars[barKey]
end

function R:Iterate()
    return pairs(R.bars)
end
