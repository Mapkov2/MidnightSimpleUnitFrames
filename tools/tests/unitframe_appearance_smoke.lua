local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local exponentCalls, unitQueries = 0, 0
local world = World.New(root, { flavor = flavor, setup = function(env)
    local nativeMath = env.math
    env.math = setmetatable({ exp = function(value) exponentCalls = exponentCalls + 1 return nativeMath.exp(value) end }, { __index = nativeMath })
    for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitInRange", "UnitIsConnected", "UnitExists" }) do
        local native = env[name]
        if native then env[name] = function(...) unitQueries = unitQueries + 1 return native(...) end end
    end
end })
local env, UF = world.env, world.core.UF
world.core.Require("MSUF_EnsureDB", "appearance test")(true)
local Motion, Alpha = assert(UF.Appearance), UF.elements.Alpha
local function IsActive(frame) local state = frame._msufAppearance return state and state.index ~= nil end
local g = env.MSUF_DB.general
g.reduceMotion, g.reducedMotion = false, false
local checks = 0
local function Check(value, why) assert(value, flavor .. ": " .. why) checks = checks + 1 end
local function Near(value, expected, why) Check(math.abs(value - expected) < .00001, why) end
local function Driver()
    for i = 1, 30 do
        local name, value = debug.getupvalue(Motion.Begin, i)
        if name == "driver" then return value end
        if not name then break end
    end
end
local function Advance(seconds)
    local driver = Driver()
    local update = driver and driver:GetScript("OnUpdate")
    if update then update(driver, seconds) end
end
local function Frame(unit, conf, group)
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:Hide()
    frame.MSUFUnitKey = unit
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.hpBar:SetStatusBarTexture("test")
    frame.hpTextLeft = frame:CreateFontString(nil, "OVERLAY")
    frame.targetPowerBar = env.CreateFrame("StatusBar", nil, frame)
    frame.targetPowerBar:SetAlpha(.7)
    frame.hpBar.bg = frame.hpBar:CreateTexture()
    frame.hpBar.bg:SetAlpha(.25)
    frame._msufIsGroupFrame = group
    frame.MSUFSpec = { alpha = UF.Shared.CompileAlpha({}, conf, group), range = { active = false },
        scope = group and "group" or "single", group = {} }
    Alpha.Apply(frame, frame.MSUFSpec)
    return frame
end
local stopWatch = world:Watch({
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_Group_RangeFade.lua",
})
local conf = { hpBarAlpha = .6, fadeInOnShow = true, alphaExcludeTextPortrait = true }
local frame = Frame("target", conf)
Check(frame._msufAppearance ~= nil, "appearance flag was not compiled/applied")
frame:Show()
Near(frame:GetAlpha(), 0, "show did not begin transparent")
Advance(.05)
Check(frame:GetAlpha() > 0 and frame:GetAlpha() < 1, "fade has no intermediate alpha")
Near(frame.hpBar:GetStatusBarTexture():GetAlpha(), .6, "foreground slider was overwritten")
Near(frame.hpTextLeft:GetAlpha(), 1, "text exclusion was overwritten")
Near(frame.targetPowerBar:GetAlpha(), .7, "power opacity was overwritten")
Near(frame.hpBar.bg:GetAlpha(), .25, "background opacity was overwritten")
local progress, velocity = frame._msufAppearance.value, frame._msufAppearance.velocity
conf.hpBarAlpha = .4
frame.MSUFSpec.alpha = UF.Shared.CompileAlpha(frame.MSUFSpec.alpha, conf)
Alpha.Apply(frame, frame.MSUFSpec)
Near(frame:GetAlpha(), progress, "slider refresh restarted/squared the fade")
Near(frame.hpBar:GetStatusBarTexture():GetAlpha(), .4, "slider change was delayed")
Check(frame._msufAppearance.velocity == velocity, "slider refresh discarded spring velocity")
UF.ApplyRangeModifier(frame, .35, true)
Near(frame:GetAlpha(), .35 * progress, "range update ignored the current fade factor")
Advance(.3)
Near(frame:GetAlpha(), .35, "fade did not end at the range alpha")
Near(frame.hpBar:GetStatusBarTexture():GetAlpha(), .4, "opacity was applied twice")
Check(not IsActive(frame) and Driver():GetScript("OnUpdate") == nil, "idle driver still runs")
frame:Hide()
frame:Show()
Advance(.05)
local retained = frame:GetAlpha()
Motion.Begin(frame)
Near(frame:GetAlpha(), retained, "duplicate appearance restarted the fade")
frame:Hide()
Check(not IsActive(frame), "hidden frame remained scheduled")
frame:Show()
Advance(.03)
conf.fadeInOnShow = false
frame.MSUFSpec.alpha = UF.Shared.CompileAlpha(frame.MSUFSpec.alpha, conf)
Alpha.Apply(frame, frame.MSUFSpec)
Near(frame:GetAlpha(), .35, "disabling mid-fade lost the normal alpha")
Check(frame._msufAppearance == nil and Driver():GetScript("OnUpdate") == nil, "disabled fade remained active")
conf.fadeInOnShow = true
frame.MSUFSpec.alpha = UF.Shared.CompileAlpha(frame.MSUFSpec.alpha, conf)
Alpha.Apply(frame, frame.MSUFSpec)
frame:Hide()
frame:Show()
Advance(.04)
g.reduceMotion = true
Motion.UpdateSettings()
Check(IsActive(frame), "reducing menu motion cancelled live unit-frame appearance")
g.reducedMotion = true
Motion.UpdateSettings()
Near(frame:GetAlpha(), .35, "saved motion override did not restore the composed alpha")
Check(not IsActive(frame), "saved motion override kept the animation running")
g.reduceMotion, g.reducedMotion = false, false
Motion.UpdateSettings()
-- Both restricted range choices stay native. The animation never reads GetAlpha.
frame:Hide()
frame:Show()
frame._msufRangeOutAlpha = .3
UF.ApplyRangeBoolean(frame, world.Secrets.New("boolean"), world.Secrets.New("boolean"), true, false)
Advance(.04)
Check(world.Secrets.IsSecret(frame.alphaBoolean), "secret checked-range selection was read in Lua")
Near(frame.alphaIfFalse, .3 * frame._msufAppearance.value, "checked-range fallback lost the fade factor")
Motion.Cancel(frame)
Near(frame.alphaIfFalse, .3, "secret fallback did not end at the original opacity")
frame:Hide()
-- Re-enabling at 100% foreground must not resurrect an old range target.
local coldConf = { fadeInOnShow = true }
local cold = Frame("focus", coldConf)
UF.ApplyRangeModifier(cold, .4, true)
coldConf.fadeInOnShow = false
cold.MSUFSpec.alpha = UF.Shared.CompileAlpha(cold.MSUFSpec.alpha, coldConf)
Alpha.Apply(cold, cold.MSUFSpec)
UF.ApplyRangeModifier(cold, 1, true)
coldConf.fadeInOnShow = true
cold.MSUFSpec.alpha = UF.Shared.CompileAlpha(cold.MSUFSpec.alpha, coldConf)
Alpha.Apply(cold, cold.MSUFSpec)
cold:Show()
Advance(.3)
Near(cold:GetAlpha(), 1, "re-enable resurrected stale range opacity")
cold:SetAlpha(.2)
world.core.UFVisuals.SetFrameAlpha(cold, 1)
Near(cold:GetAlpha(), 1, "root cache did not correct an outside alpha write")
cold:Hide()
cold:Show()
Advance(.04)
local coldProgress = cold._msufAppearance.value
cold:SetAlpha(1)
world.core.UFVisuals.SetFrameAlpha(cold, 1)
Near(cold:GetAlpha(), coldProgress, "active root correction bypassed the fade")
cold:Hide()
-- Group range owns a separate root cache; numeric and native Boolean paths must both compose.
local group = Frame("party1", { hpBarAlpha = .6, fadeInOnShow = true }, true)
group._msufGFRangeFadeEnabled, group._msufGFRangeKnown = true, true
group._msufGFRangeUnit = "party1"
group._msufGFInRangeRaw, group._msufGFRangeFadeAlphaValue = false, .4
local booleanWriter = group.SetAlphaFromBoolean
group.SetAlphaFromBoolean = false
group:Show()
local range = UF.elements.GroupRangeFade
range.UpdateConnectionState(group, "MSUF_TEST")
local groupForeground = group.hpBar:GetStatusBarTexture():GetAlpha()
Advance(.05)
Near(group:GetAlpha(), .4 * group._msufAppearance.value, "group range cache overrode fade")
Advance(.3)
Near(group:GetAlpha(), .4, "group fade ended at the wrong opacity")
Near(group.hpBar:GetStatusBarTexture():GetAlpha(), groupForeground, "appearance changed the group painter opacity")
group:Hide()
group.SetAlphaFromBoolean = booleanWriter
group:Show()
range.Update(group, "UNIT_IN_RANGE_UPDATE", "party1", world.Secrets.New("boolean"))
Advance(.04)
Check(world.Secrets.IsSecret(group.alphaBoolean), "group secret range did not stay native")
Near(group.alphaIfFalse, .4 * group.alphaIfTrue, "group range branches use different fade factors")
group:Hide()
Check(Driver():GetScript("OnUpdate") == nil, "group hide did not stop the shared driver")
local violations = stopWatch()
Check(#violations == 0, table.concat(violations, "\n"))
-- No per-tick queries/tables/closures: 40 simultaneous plain frames use one bounded driver.
local frames, writes = {}, 0
for i = 1, 40 do
    local f = Frame("raid" .. i, { fadeInOnShow = true }, true)
    local native = f.SetAlpha
    f.SetAlpha = function(self, alpha) writes = writes + 1 native(self, alpha) end
    frames[i] = f
    f:Show()
end
local driver, update = Driver(), Driver():GetScript("OnUpdate")
writes = 0
local exponentBefore, queriesBefore = exponentCalls, unitQueries
update(driver, .01)
Check(writes == 40, "fade tick did more than one native alpha write per member")
Check(exponentCalls - exponentBefore <= 1, "spring decay was recomputed for every raid member")
Check(unitQueries == queriesBefore, "animation tick queried units")
collectgarbage("collect")
collectgarbage("stop")
local memory = collectgarbage("count")
for _ = 1, 200 do update(driver, .00001) end
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
Check(allocated < .01, "animation tick allocated: " .. tostring(allocated) .. " KB")
for i = 1, #frames do frames[i]:Hide() end
Check(driver:GetScript("OnUpdate") == nil, "raid fade left idle work")
Check(#world.errors == 0, table.concat(world.errors, "\n"))
print("unitframe_appearance_smoke " .. flavor .. ": " .. checks .. " checks passed; 40 writes/tick, no idle update")
