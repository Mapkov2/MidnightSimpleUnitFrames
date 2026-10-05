-- forever_swing_details_smoke.lua <repoRoot>
--
-- WoW Forever swing timer details (Game/Forever/SwingTimer.lua):
-- 1. The off-hand lane draws the off-hand timer inside the main-hand bar,
--    driven by the off-hand's own native duration, in the off-hand colour.
-- 2. Out of reach, a bar takes its reach colour and fades to the chosen
--    opacity; an uncheckable or restricted range never counts as outside;
--    the lane inherits the main-hand fade instead of fading twice.
-- 3. The range switch C_SwingTimer.EnableRangeCheck is shared with Blizzard's
--    bars, which drop it when their CVar turns off: MSUF re-asserts it.
-- 4. A queued next-swing attack (Heroic Strike, Cleave, Maul, Raptor Strike)
--    shows its icon beside the main-hand bar and tints the border. With the
--    cue text on, the bar's title names it in the cue colour: the client's
--    spell name, or the player's own text for that attack; the title comes
--    back when the queue clears or the text is turned off.
-- 5. Hot path: target changes, haste procs and spell-state events do only
--    their own minimal work, with no spell-name lookups or repeated writes;
--    classes without next-swing attacks do not listen for spell state.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local writes, counting = 0, false
local COUNTED = { SetShown = true, Show = true, Hide = true, SetAlpha = true, SetStatusBarColor = true,
    SetText = true, SetTextColor = true, SetTexture = true, SetBackdropBorderColor = true, SetTimerDuration = true,
    SetPoint = true, ClearAllPoints = true, SetEnabled = true, EnableMouse = true, SetValue = true }
local W = {}
W.__index = function(self, key)
    local method = W[key]
    if counting and method and COUNTED[key] then
        return function(...) writes = writes + 1; return method(...) end
    end
    return method
end
local named = {}
local function Widget(parent)
    return setmetatable({ parent = parent, shown = true, scale = 1, scripts = {}, events = {}, alpha = 1 }, W)
end
for _, key in ipairs({ "SetMovable", "SetClampedToScreen", "RegisterForDrag", "SetMinMaxValues", "SetAllPoints",
    "SetJustifyH", "SetBackdrop", "SetOrientation", "SetRotatesTexture", "SetReverseFill", "SetHorizTile",
    "SetVertTile", "SetBlendMode", "SetFrameLevel", "SetFont", "SetDuration", "SetUpdateInterval", "SetExpiredText",
    "SetZeroDurationText", "SetFontString", "SetTextFormat", "SetBreakpoints", "SetTexCoord" }) do
    W[key] = function() end
end
function W:SetPoint(...) self.point = { ... } end
function W:ClearAllPoints() self.point = nil end
function W:SetSize(a, b) self.width, self.height = a, b end
function W:SetWidth(v) self.width = v end
function W:SetHeight(v) self.height = v end
function W:SetScale(v) self.scale = v end
function W:GetScale() return self.scale end
function W:GetFrameLevel() return 1 end
function W:SetScript(k, v) self.scripts[k] = v end
function W:HookScript(k, v) self.scripts[k] = v end
function W:RegisterEvent(k) self.events[k] = true end
function W:RegisterUnitEvent(k) self.events[k] = true end
function W:UnregisterEvent(k) self.events[k] = nil end
function W:UnregisterAllEvents() self.events = {} end
function W:CreateTexture() return Widget(self) end
function W:CreateFontString() return Widget(self) end
function W:SetStatusBarTexture(v) self.texture = v; self.fill = self.fill or Widget(self) end
function W:GetStatusBarTexture() return self.fill end
function W:SetStatusBarColor(...) self.color = { ... } end
function W:SetVertexColor(...) self.vertex = { ... } end
function W:SetTextColor(...) self.textColor = { ... } end
function W:SetBackdropBorderColor(...) self.border = { ... } end
function W:SetTexture(v) self.textureFile = v end
function W:SetText(v) self.text = v end
function W:SetAlpha(v) self.alpha = v end
function W:SetShown(v) self.shown = v and true or false end
function W:IsShown() return self.shown end
function W:Show() self.shown = true end
function W:Hide() self.shown = false end
function W:SetEnabled(v) self.enabled = v end
function W:EnableMouse(v) self.mouse = v end
function W:SetValue(v) self.value = v end
function W:Reset() self.reset = true end
function W:SetTimeFromEnd(finish, duration) self.finish, self.duration = finish, duration end
function W:SetTimerDuration(value, _, direction) self.timer, self.timerDirection = value, direction end

local apiCalls = { name = 0, current = 0, inRange = 0, speed = 0 }
local function Install(class)
    named = {}
    UIParent = Widget()
    CreateFrame = function(_, name, parent) local w = Widget(parent); if name then named[name] = w end; return w end
    GetTime = function() return 100 end
    GetCVarBool = function() return false end
    SetCVar = function() end
    UnitClass = function() return class, class end
    UnitAttackSpeed = function() apiCalls.speed = apiCalls.speed + 1; return 2.5, 1.8, 0 end
    UnitAffectingCombat = function() return true end
    InCombatLockdown = function() return false end
    issecretvalue = function(v) return v == "secret" end
    STANDARD_TEXT_FONT = "font"
    Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
        StatusBarTimerDirection = { RemainingTime = 1, ElapsedTime = 2 }, StatusBarInterpolation = { Immediate = 1 },
        DurationTextBindingProperty = { RemainingDuration = 1 }, NumericRuleFormatRounding = { Nearest = 1 } }
    C_DurationUtil = { CreateDuration = Widget, CreateDurationTextBinding = Widget }
    C_StringUtil = { CreateNumericRuleFormatter = Widget }
end
local rangeSwitch, inRange, queued = {}, { [0] = true, [1] = true, [2] = true }, nil
C_SwingTimer = {
    EnableRangeCheck = function(hand, on) rangeSwitch[hand] = on end,
    IsTargetWithinSwingRange = function(hand) apiCalls.inRange = apiCalls.inRange + 1; return inRange[hand] end,
}
local SPELLS = { [78] = "Heroic Strike", [845] = "Cleave", [6807] = "Maul", [2973] = "Raptor Strike" }
C_Spell = {
    GetSpellName = function(id) apiCalls.name = apiCalls.name + 1; return SPELLS[id] end,
    GetSpellTexture = function(id) return "icon:" .. id end,
    IsCurrentSpell = function(name) apiCalls.current = apiCalls.current + 1; return queued == name end,
}
local module
local function Load(class)
    Install(class)
    MSUF_DB = { swingTimers = { enabled = true } }
    local ns = { Client = { IsForever = true }, MSUF_RegisterModule = function(_, m) module = m end }
    ns.MSUF_ApplyModules = function() if ns.SwingTimer.GetEnabled() then module.Enable() else module.Disable() end end
    local created = {}
    local create = CreateFrame
    CreateFrame = function(...) local w = create(...); created[#created + 1] = w; return w end
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua"))("test", ns)
    module.Enable()
    return ns.SwingTimer, created[1]
end
local function Fire(driver, event, ...) Check(driver.events[event], "the swing driver does not listen to " .. event); driver.scripts.OnEvent(driver, event, ...) end

---------------------------------------------------------------------------
-- 1. Off-hand lane.
---------------------------------------------------------------------------
local swing, driver = Load("WARRIOR")
local main, off = named.MSUF_SwingTimer_main, named.MSUF_SwingTimer_off
Check(main.shown and off.shown and not off.Lane, "the lane is built only when chosen")
swing.Set("off", "color", { 0.2, 0.9, 0.3 })
swing.Set("main", "offhandLane", true)
local lane = Check(off.Lane, "off-hand lane missing")
Check(main.shown and not off.shown and lane.shown and lane.parent == main, "the off-hand timer did not move into the main-hand bar")
Check(lane.color[2] == 0.9, "the lane does not use the off-hand colour")
Check(lane.point and lane.height and lane.height < main.height, "the lane is not a strip inside the main-hand bar")
Fire(driver, "PLAYER_SWING", 1.8, 1)
Check(lane.timer == off.duration and lane.timerDirection == Enum.StatusBarTimerDirection.ElapsedTime
    and off.endsAt == 101.8, "the off-hand swing does not drive the lane")
swing.Set("main", "offhandLane", false)
Check(off.shown and not lane.shown, "turning the lane off did not restore the separate off-hand bar")

---------------------------------------------------------------------------
-- 2. Out of reach.
---------------------------------------------------------------------------
swing.Set("main", "reachCheck", true); swing.Set("off", "reachCheck", true)
Check(rangeSwitch[0] == true and rangeSwitch[1] == true and not rangeSwitch[2], "range checks follow the reach option per hand")
Fire(driver, "PLAYER_SWING_RANGE_UPDATE", 0, false, true)
Check(math.abs(main.alpha - 0.7) < 1e-6, "out of reach must fade to the 70% default")
Check(main.Bar.color[1] == 0.55 and main.Bar.color[3] == 0.6, "out of reach must grey the bar")
Fire(driver, "PLAYER_SWING_RANGE_UPDATE", 0, false, false)
Check(main.alpha == 1 and main.Bar.color[1] == 0.85, "an uncheckable range was treated as outside")
Fire(driver, "PLAYER_SWING_RANGE_UPDATE", 0, "secret", true)
Check(main.alpha == 1, "a restricted range was compared")
swing.Set("main", "offhandLane", true); swing.Set("main", "reachOpacity", 50)
lane = off.Lane
Fire(driver, "PLAYER_SWING_RANGE_UPDATE", 0, false, true)
Check(math.abs(main.alpha - 0.5) < 1e-6 and lane.alpha == 1, "the lane faded on top of the main-hand fade")

---------------------------------------------------------------------------
-- 3. Blizzard's bars drop the shared range switch with their CVar.
---------------------------------------------------------------------------
rangeSwitch[0] = false
Fire(driver, "CVAR_UPDATE", "showSwingTimer", "0")
Check(rangeSwitch[0] == true, "the range check was not re-asserted after Blizzard turned it off")

---------------------------------------------------------------------------
-- 4. Next-swing cue.
---------------------------------------------------------------------------
local border = main.border
queued = "Heroic Strike"
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
Check(main.Cue and main.Cue.shown and main.Cue.textureFile == "icon:78", "queued Heroic Strike has no icon")
Check(main.border[1] == 0.35 and main.border[3] == 1, "queued attack did not tint the border")
Check(main.Title.text ~= "Heroic Strike", "the cue replaced the bar title")
queued = "Cleave"
Fire(driver, "ACTIONBAR_UPDATE_STATE")
Check(main.Cue.textureFile == "icon:845", "switching to Cleave kept the old icon")
queued = nil
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
Check(not main.Cue.shown and main.border[1] == border[1], "clearing the queue left the cue or tint")
-- The cue text: the spell name by default, the player's own text per attack.
Check(swing.Set("main", "nextSwingText", true), "the cue text switch was refused")
Check(swing.Set("main", "nextSwingLabel845", "CLEAVE NOW"), "a cue text was refused")
Check(not swing.Set("main", "nextSwingLabel845", string.rep("x", 41)), "an overlong cue text was stored")
Check(swing.Get("main", "nextSwingLabel845") == "CLEAVE NOW", "a refused cue text replaced the stored one")
-- The limit counts characters, not UTF-8 bytes: 22 Cyrillic letters (42
-- bytes) and 40 Hangul syllables (120 bytes) fit, 41 Cyrillic letters do not.
local cyrillic = "\208\147\208\181\209\128\208\190\208\184\209\135\208\181\209\129\208\186\208\184\208\185 \209\131\208\180\208\176\209\128 \208\179\208\190\209\130\208\190\208\178"
Check(swing.Set("main", "nextSwingLabel78", cyrillic) and swing.Get("main", "nextSwingLabel78") == cyrillic,
    "a 22-character Cyrillic cue text was refused for its 42 bytes")
Check(swing.Set("main", "nextSwingLabel78", string.rep("\236\152\129", 40)), "a 40-character Hangul cue text was refused")
Check(not swing.Set("main", "nextSwingLabel78", string.rep("\208\147", 41)), "a 41-character Cyrillic cue text was stored")
Check(swing.Set("main", "nextSwingLabel78", ""), "clearing a cue text was refused")
queued = "Heroic Strike"
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
Check(main.Title.text == "Heroic Strike" and main.Title.shown, "the cue text does not name the queued attack")
Check(main.Title.textColor[1] == 0.35 and main.Title.textColor[3] == 1, "the cue text is not in the cue colour")
queued = "Cleave"
Fire(driver, "ACTIONBAR_UPDATE_STATE")
Check(main.Title.text == "CLEAVE NOW", "the attack's own cue text is not shown")
queued = nil
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
Check(main.Title.text == "Main Hand" and main.Title.textColor[1] == 1 and main.Title.textColor[2] == 1,
    "clearing the queue did not restore the bar title")
queued = "Heroic Strike"
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
swing.Set("main", "nextSwingText", false)
Check(main.Title.text == "Main Hand" and main.Cue.shown, "turning the cue text off kept the attack name or lost the icon")
swing.Set("main", "nextSwingText", true)
Check(main.Title.text == "Heroic Strike", "turning the cue text on while queued did not name the attack")
queued = nil
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")

---------------------------------------------------------------------------
-- 5. Hot path.
---------------------------------------------------------------------------
local function Measure(label, event, ...)
    for key in pairs(apiCalls) do apiCalls[key] = 0 end
    writes, counting = 0, true
    for _ = 1, 20 do Fire(driver, event, ...) end
    counting = false
    return writes
end
Check(Measure("target", "PLAYER_TARGET_CHANGED") == 0, "an unchanged target swap rewrote the bars")
Check(apiCalls.name == 0 and apiCalls.current == 0 and apiCalls.speed == 0,
    "a target swap read spell names, spell state or weapon speeds")
Check(apiCalls.inRange == 40, "a target swap must read each checked hand's range once")
Check(Measure("haste", "UNIT_ATTACK_SPEED", "player") == 0, "a haste proc rewrote the bars")
Check(apiCalls.inRange == 0 and apiCalls.current == 0 and apiCalls.name == 0, "a haste proc read range or spell state")
queued = "Maul"
Check(Measure("cue", "CURRENT_SPELL_CAST_CHANGED") == 0, "an unchanged spell state rewrote the cue")
queued = "Heroic Strike"
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
Check(Measure("cue text", "CURRENT_SPELL_CAST_CHANGED") == 0, "an unchanged queued attack rewrote the cue text")
queued = nil
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
Check(apiCalls.name == 0, "spell names were looked up per spell-state event")
-- Equipping a shield removes the off-hand: the haste event path still notices.
UnitAttackSpeed = function() return 2.5, nil, 0 end
Fire(driver, "UNIT_ATTACK_SPEED", "player")
Check(not off.Lane.shown and not off.shown, "removing the off-hand weapon kept its bar or lane")
UnitAttackSpeed = function() return 2.5, 1.8, 0 end
Fire(driver, "UNIT_ATTACK_SPEED", "player")
Check(off.Lane.shown, "equipping an off-hand weapon did not bring the lane back")
module.Disable()
Check(not rangeSwitch[0] and not rangeSwitch[1], "disable kept the native range checks")

-- Classes without next-swing attacks never listen for spell state.
local _, mageDriver = Load("MAGE")
Check(not mageDriver.events.CURRENT_SPELL_CAST_CHANGED and not mageDriver.events.ACTIONBAR_UPDATE_STATE,
    "a class without next-swing attacks listens for spell state")
Check(not mageDriver.events.PLAYER_TARGET_CHANGED and not mageDriver.events.PLAYER_SWING_RANGE_UPDATE,
    "range events without any reach option")
module.Disable()
-- A profile saved under the former names of the swing extras keeps them.
Install("WARRIOR")
MSUF_DB = { swingTimers = { enabled = true, main = { combineOffhand = true, rangeWarning = true, rangeAlpha = 40,
    rangeColor = { 1, 0.2, 0.2 }, queuedAttack = true, queuedColor = { 1, 0.85, 0.25 },
    heroicText = "HS", maulText = "", cleaveText = "CL" } } }
do
    local formerNS = { Client = { IsForever = true }, MSUF_RegisterModule = function(_, m) module = m end }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua"))("test", formerNS)
    local carried = formerNS.SwingTimer
    Check(carried.Get("main", "offhandLane") == true and carried.Get("main", "reachCheck") == true
        and carried.Get("main", "reachOpacity") == 40 and carried.Get("main", "reachColor")[2] == 0.2,
        "the former lane and range settings were not carried")
    Check(carried.Get("main", "nextSwingCue") == true and carried.Get("main", "nextSwingColor")[2] == 0.85
        and carried.Get("main", "nextSwingText") == true, "the former queued-attack settings were not carried")
    Check(carried.Get("main", "nextSwingLabel78") == "HS" and carried.Get("main", "nextSwingLabel845") == "CL"
        and carried.Get("main", "nextSwingLabel6807") == "", "the former per-attack texts were not carried")
    for _, key in ipairs({ "combineOffhand", "rangeWarning", "rangeAlpha", "rangeColor", "queuedAttack", "queuedColor",
        "heroicText", "maulText", "cleaveText" }) do
        Check(MSUF_DB.swingTimers.main[key] == nil, "the former key " .. key .. " stayed")
    end
end
-- A hunter's Raptor Strike counts.
local hunterSwing, hunterDriver = Load("HUNTER")
queued = "Raptor Strike"
Fire(hunterDriver, "CURRENT_SPELL_CAST_CHANGED")
Check(named.MSUF_SwingTimer_main.Cue.shown and named.MSUF_SwingTimer_main.Cue.textureFile == "icon:2973", "Raptor Strike has no cue")
module.Disable()

---------------------------------------------------------------------------
-- Embedded samples share styles, but never own native timers or runtime state.
---------------------------------------------------------------------------
local function Clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Clone(item) end
    return out
end
local function Equal(a, b)
    if type(a) ~= "table" then return a == b end
    if type(b) ~= "table" then return false end
    for key, item in pairs(a) do if not Equal(item, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Forbidden() error("sample called native gameplay API", 2) end
swing, driver = Load("WARRIOR")
main, off = named.MSUF_SwingTimer_main, named.MSUF_SwingTimer_off
swing.Set("main", "offhandLane", true)
swing.Set("main", "nextSwingText", true)
queued = "Heroic Strike"
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
local realTitle, realLane, realPoint = main.Title.text, off.Lane, main.point
local profile, listeners = Clone(MSUF_DB), Clone(driver.events)
local durationAPI, cvarGet, cvarSet, swingAPI = C_DurationUtil, GetCVarBool, SetCVar, C_SwingTimer
C_DurationUtil = { CreateDuration = Forbidden, CreateDurationTextBinding = Forbidden }
GetCVarBool, SetCVar, C_SwingTimer = Forbidden, Forbidden, nil
local canvas = Widget(UIParent)
local samples = {}
for _, hand in ipairs({ "main", "off", "ranged" }) do
    samples[hand] = swing.CreateMenuPreview(canvas, hand)
    samples[hand]:SetPoint("CENTER", canvas, "CENTER", 0, 0)
end
swing.PaintMenuPreview(samples)
Check(samples.main.parent == canvas and samples.main.point[2] == canvas, "sample lost its menu parent or anchor")
Check(not samples.main.duration and not samples.main.binding and not samples.main.scripts.OnDragStop,
    "sample became a gameplay timer or draggable frame")
Check(named.MSUF_SwingTimer_main == main and named.MSUF_SwingTimer_off == off,
    "sample collided with a globally named runtime frame")
Check(main.Title.text == realTitle and main.Cue.shown and off.Lane == realLane and main.point == realPoint,
    "sample paint changed a runtime bar, cue, lane or anchor")
Check(Equal(profile, MSUF_DB) and Equal(listeners, driver.events), "sample paint changed saved state or listeners")
Check(samples.off.Lane.parent == samples.main and samples.off.Lane ~= realLane, "sample uses the runtime lane")
Check(samples.main.texture == main.texture and Equal(samples.main.Bar.color, main.Bar.color)
    and Equal(samples.main.Bar.Background.vertex, main.Bar.Background.vertex)
    and samples.main.Bar.Background.alpha == main.Bar.Background.alpha,
    "sample and runtime surface styles differ")
C_DurationUtil, GetCVarBool, SetCVar, C_SwingTimer = durationAPI, cvarGet, cvarSet, swingAPI
writes, counting = 0, true
Fire(driver, "CURRENT_SPELL_CAST_CHANGED")
counting = false
Check(writes == 0, "sample paint invalidated the cached queued-attack state")
module.Disable()
MSUF_DB = { swingTimers = { enabled = false, main = { width = 600, direction = "UP", display = "text", time = false } } }
profile = Clone(MSUF_DB)
GetCVarBool, SetCVar, C_DurationUtil = Forbidden, Forbidden, nil
swing.PaintMenuPreview(samples)
Check(samples.main.width == 600 and not samples.main.Bar.shown and samples.main.Time.shown,
    "module-off, partial profile or text-only sample failed")
Check(samples.ranged.Time.text == "1.2" and Equal(profile, MSUF_DB), "preview migrated or filled a partial profile")
GetCVarBool, SetCVar, C_DurationUtil = cvarGet, cvarSet, durationAPI
module.Enable()
Check(named.MSUF_SwingTimer_main == main and main ~= samples.main, "later enable reused an embedded sample")
module.Disable()
print("forever_swing_details_smoke: OK")
