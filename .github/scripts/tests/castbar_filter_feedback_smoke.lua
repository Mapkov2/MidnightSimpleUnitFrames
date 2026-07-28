--- castbar_filter_feedback_smoke.lua
---
--- Contract for the castbar filtering/feedback settings:
---   * profession casts are dropped in the engine, before any frame work, and
---     the flag they key off is one 12.x never protects;
---   * pushback text is appended after shortening, is gated on an active cast,
---     and never leaks onto the interrupt label, which reuses the same writer.

local repoRoot = ...
if repoRoot and repoRoot ~= "" then
    local sep = package.config:sub(1, 1)
    if repoRoot:sub(-1) ~= sep then repoRoot = repoRoot .. sep end
else
    repoRoot = ""
end

local function LoadFile(relative)
    return assert(loadfile(repoRoot .. relative), "failed to load " .. relative)
end

local now = 500
_G.GetTime = function() return now end
_G.GetTimePreciseSec = _G.GetTime
_G.issecretvalue = function(value) return value == "SECRET" end
_G.C_Timer = { After = function() end }
_G.UIParent = {}

_G.MSUF_DB = { general = {} }
local general = _G.MSUF_DB.general

local ns = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

LoadFile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua")("MSUF", ns)

local ApplyTexts = assert(_G.MSUF_CB_ApplyTexts, "text writer missing")

-- 1. Pushback text ---------------------------------------------------------
local written
local frame = {
    unit = "target",
    MSUF_castActive = true,
    castText = { SetText = function(_, value) written = value end },
}

frame._msufPushbackMS = 400
ApplyTexts(frame, nil, "Fireball", nil)
assert(written == "Fireball", "pushback must stay off until the option is enabled")

general.castbarShowPushback = true
ApplyTexts(frame, nil, "Fireball", nil)
assert(written == "Fireball +0.4", "pushback suffix missing: " .. tostring(written))

frame._msufPushbackMS = nil
ApplyTexts(frame, nil, "Fireball", nil)
assert(written == "Fireball", "a cast without delay must not gain a suffix")

-- The interrupt label reuses this writer, so an inactive cast must never take
-- the suffix - that is how "Interrupted +0.4" would reach the bar.
frame._msufPushbackMS = 400
frame.MSUF_castActive = false
ApplyTexts(frame, nil, "Interrupted", nil)
assert(written == "Interrupted", "pushback leaked onto an inactive bar: " .. tostring(written))
frame.MSUF_castActive = true
frame.interrupted = true
ApplyTexts(frame, nil, "Interrupted", nil)
assert(written == "Interrupted", "pushback leaked onto the interrupt label")
frame.interrupted = nil
general.castbarShowPushback = false

-- 2. Tradeskill filter -----------------------------------------------------
-- The engine captures the cast API as an upvalue at load, so the stub has to
-- stay the same function and only change what it answers.
local castInfo = { "Smelting", "Smelting", 1, 1000, 3000, true, "cast-1", false, 42, 7, 0 }
_G.UnitCastingInfo = function()
    return castInfo[1], castInfo[2], castInfo[3], castInfo[4], castInfo[5], castInfo[6],
        castInfo[7], castInfo[8], castInfo[9], castInfo[10], castInfo[11]
end
_G.UnitChannelInfo = function() return nil end
_G.UnitIsEmpowering = function() return false end
_G.UnitShouldDisplaySpellTargetName = function() return false end
_G.MSUF_EnsureDBLazy = function() end

LoadFile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarEngine.lua")("MSUF", ns)
local engine = assert(_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine(), "castbar engine missing")

local state = engine:BuildState("target")
assert(state and state.active == true, "a profession cast must show while the filter is off")

general.castbarHideTradeSkills = true
now = now + 1
state = engine:BuildState("target")
assert(not (state and state.active == true), "profession cast was not filtered")

-- A normal cast must still pass with the filter on.
castInfo[1], castInfo[2], castInfo[6], castInfo[7] = "Fireball", "Fireball", false, "cast-2"
now = now + 1
state = engine:BuildState("target")
assert(state and state.active == true, "the filter dropped a non-profession cast")

print("castbar filter feedback smoke: ok")
