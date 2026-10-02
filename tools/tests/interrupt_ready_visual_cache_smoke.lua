-- interrupt_ready_visual_cache_smoke.lua <repoRoot>
--
-- The interrupt-ready indicator repaints a castbar only when its visual
-- changes. RefreshFrame runs for target, focus and every boss bar on each
-- interrupt cooldown event, so the cache compares the last painted visual
-- field by field (style, readiness, raw interruptibility, RGBA) instead of
-- building a key string per refresh. Pinned for plain (readable) readiness:
--   * an unchanged visual paints nothing;
--   * a change of readiness, raw interruptibility, colour or style repaints;
--   * _msufKickReadyVisualKey = nil (what the outline and layout owners do)
--     forces the next paint;
--   * a border tint that found no outline is not remembered, so the next
--     refresh tries again;
--   * the box style caches the same way.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local remaining = 0
local frameStamp = 100
_G.GetTime = function() return frameStamp end
_G.MSUF_DB = {
    general = {
        kickReadyShowTarget = true,
        kickReadyStyle = "border",
        kickReadyColor = { ["1"] = 0.1, ["2"] = 0.8, ["3"] = 0.2 },
        kickNotReadyColor = { ["1"] = 0.9, ["2"] = 0.1, ["3"] = 0.2 },
    },
}
_G.MSUF_EnsureDB = function() end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.issecretvalue = function() return false end
_G.CreateColor = function(red, green, blue, alpha)
    return { GetRGBA = function() return red, green, blue, alpha end }
end
_G.C_Timer = { After = function() end }
local cooldownObject = {
    GetRemainingDuration = function() return remaining end,
    IsZero = function() return remaining <= 0 end,
}
_G.C_Spell = { GetSpellCooldownDuration = function() return cooldownObject end }
_G.C_CurveUtil = {
    EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse) return value and ifTrue or ifFalse end,
    EvaluateColorFromBoolean = function(value, ifTrue, ifFalse) return value and ifTrue or ifFalse end,
}

local function Region()
    local region = { shown = true }
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:SetAlpha() end
    function region:SetSize() end
    function region:SetWidth() end
    function region:SetHeight() end
    function region:ClearAllPoints() end
    function region:SetPoint() end
    function region:SetAllPoints() end
    function region:SetFrameLevel() end
    function region:GetFrameLevel() return 1 end
    function region:GetHeight() return 18 end
    function region:GetWidth() return 200 end
    function region:SetVertexColor() end
    function region:SetAlphaFromBoolean() end
    function region:SetFrameStrata() end
    function region:EnableMouse() end
    function region:SetTexture() end
    function region:SetColorTexture() end
    function region:SetDrawLayer() end
    function region:CreateTexture() return Region() end
    function region:SetScript() end
    function region:RegisterEvent() end
    function region:UnregisterEvent() end
    function region:UnregisterAllEvents() end
    return region
end
_G.CreateFrame = function() return Region() end
_G.UIParent = Region()

local interruptNamespace = { ExportPublic = function(name, value) _G[name] = value return value end,
    Scheduler = { ScheduleAfter = function() return true end, CancelScheduled = function() return false end } }
-- Castbars/MSUF_CastbarUtils.lua loads first in every TOC (the interrupt-ready unit rule).
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))(
    "MidnightSimpleUnitFrames", interruptNamespace)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))(
    "MidnightSimpleUnitFrames", interruptNamespace)
local refresh = assert(_G.MSUF_KickReady_RefreshFrame, "MSUF_KickReady_RefreshFrame missing")

-- The outline host the castbar style owner builds (MSUF_CastbarStyle.lua).
local paints = {}
local host = Region()
function host:SetBackdropBorderColor(r, g, b, a) paints[#paints + 1] = { r, g, b, a } end
local frame = {
    unit = "target",
    MSUF_castActive = true,
    isNotInterruptible = false,
    statusBar = Region(),
    _msufOutlineHost = host,
}
_G.MSUF_TargetCastbar = frame

local function Refresh(raw)
    frameStamp = frameStamp + 1
    refresh(frame, { active = true, apiNotInterruptibleRaw = raw })
end
local function Paints() local count = #paints; paints = {}; return count end

Refresh(false)
Check(Paints() == 1 and true, "first refresh did not paint")
Refresh(false)
Check(Paints() == 0, "an unchanged visual was painted again")

remaining = 4
Refresh(false)
Check(Paints() == 1, "readiness change did not repaint")
Refresh(false)
Check(Paints() == 0, "unchanged not-ready visual was painted again")

Refresh(nil)
Check(Paints() == 1, "raw interruptibility change (false -> unknown) did not repaint")
Refresh(nil)
Check(Paints() == 0, "unchanged unknown-raw visual was painted again")

-- Each colour channel alone repaints.
for channel = 1, 3 do
    local color = { ["1"] = 0.9, ["2"] = 0.1, ["3"] = 0.2 }
    for previous = 1, channel - 1 do color[tostring(previous)] = 0.5 end
    color[tostring(channel)] = 0.5
    _G.MSUF_DB.general.kickNotReadyColor = color
    Refresh(nil)
    Check(Paints() == 1, "a change of colour channel " .. channel .. " alone did not repaint")
end

-- Readiness alone repaints even when both states share one colour.
_G.MSUF_DB.general.kickReadyColor = { ["1"] = 0.5, ["2"] = 0.5, ["3"] = 0.5 }
remaining = 0
Refresh(nil)
Check(Paints() == 1, "readiness alone (same colour) did not repaint")
remaining = 4
Refresh(nil)
Check(Paints() == 1, "readiness alone (same colour) did not repaint back")

frame._msufKickReadyVisualKey = nil
Refresh(nil)
Check(Paints() == 1, "an invalidated visual key did not force a repaint")

-- A tint that finds no outline is not remembered. The outline owner drops the
-- tint flag and the key when it rebuilds (RestoreOutline, RefreshOutline).
frame._kickReadyBorderTinted = nil
frame._msufKickReadyVisualKey = nil
host:Hide()
Refresh(nil)
Check(Paints() == 0 and frame._kickReadyBorderTinted ~= true, "a hidden outline host was tinted")
host:Show()
Refresh(nil)
Check(Paints() == 1, "a tint that found no outline was cached")

-- The box style caches the same way and repaints on the style change.
local boxPaints = 0
_G.MSUF_DB.general.kickReadyStyle = "box"
Refresh(nil)
local box = frame.kickReadyBox
Check(box and box.fill, "box style built no indicator box")
local setVertexColor = box.fill.SetVertexColor
box.fill.SetVertexColor = function(...)
    boxPaints = boxPaints + 1
    if setVertexColor then return setVertexColor(...) end
end
frame._msufKickReadyVisualKey = nil
Refresh(nil)
Check(boxPaints == 1, "box style did not paint")
Refresh(nil)
Check(boxPaints == 1, "an unchanged box visual was painted again")
remaining = 0
Refresh(nil)
Check(boxPaints == 2, "box readiness change did not repaint")

print("interrupt_ready_visual_cache_smoke: ok")

-- A secret readiness (Midnight, cooldown restricted in combat) must never be
-- compared: the client raised "attempt to compare local 'isReady' (a secret
-- boolean value)" from RefreshFrame. Lua 5.1 cannot raise on `secret == true`,
-- so this pins the source order: ready is read only behind the plain-inputs flag.
local sourceFile = assert(io.open(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua", "rb"))
local source = sourceFile:read("*a"); sourceFile:close()
Check(source:find("local remember = rawKey ~= nil", 1, true)
    and source:find("local ready = remember and isReady == true", 1, true)
    and not source:find("local ready = isReady == true", 1, true),
    "RefreshFrame compares a possibly secret isReady outside the plain-inputs guard")
