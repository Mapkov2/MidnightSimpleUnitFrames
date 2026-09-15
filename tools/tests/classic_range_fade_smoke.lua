-- Classic range fade: the target frame must fade without SPELL_RANGE_CHECK_UPDATE,
-- even when C_Spell.EnableSpellRangeCheck exists (Classic never arms target spells).
-- Loads the real UnitFrames/Range/MSUF_UF_RangeFade.lua with a fresh namespace per
-- scenario and asserts the alpha multiplier it hands to UF.ApplyRangeModifier.
-- Usage (cwd = repo root): lua tools/tests/classic_range_fade_smoke.lua <repoRoot>
local root = arg and arg[1]
assert(type(root) == "string" and root ~= "", "usage: lua classic_range_fade_smoke.lua <repoRoot>")
root = root:gsub("\\", "/"):gsub("/+$", "")
local ELEMENT = root .. "/MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_RangeFade.lua"
local OUT_ALPHA = 0.35

-- Copied from Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua (PlainBool).
local function PlainBool(value)
  if issecretvalue(value) == true then
    return nil
  end
  if value == true or value == 1 then
    return true
  end
  if value == false or value == 0 then
    return false
  end
  return nil
end

local function Load(opts)
  local st = {
    rangeResult = opts.rangeResult,
    interact = opts.interact,
    combat = opts.combat == true,
    known = opts.known or {},
    interactCalls = 0,
    armedCalls = {},
    drivers = {},
    now = 0,
    speed = {},
  }

  _G.MSUF_NS = nil
  _G.MSUF_UnitEditModeActive = nil
  _G.MSUF_ScheduleOnce = nil
  st.scheduled = {}
  if opts.captureSchedule then
    _G.MSUF_ScheduleOnce = function(key, fn) st.scheduled[key] = fn end
  end
  _G.issecretvalue = function() return false end
  _G.C_Timer = {
    NewTimer = function(_, callback)
      st.timerCallback = callback
      return { Cancel = function() end }
    end,
    After = function() end,
  }
  _G.MSUF_MAX_ARENA_FRAMES = opts.maxArena
  _G.CreateFrame = function()
    local f = { events = {}, unitEvents = {} }
    function f:SetScript(name, fn) self[name] = fn end
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event)
      self.events[event] = nil
      self.unitEvents[event] = nil
    end
    function f:RegisterUnitEvent(event, ...)
      assert(select("#", ...) <= 4, "RegisterUnitEvent " .. event .. " got more than 4 unit tokens")
      self.events[event] = true
      self.unitEvents[event] = { ... }
    end
    function f:UnregisterAllEvents()
      self.events = {}
      self.unitEvents = {}
    end
    st.drivers[#st.drivers + 1] = f
    return f
  end
  _G.UnitClass = function() return "Warrior", "WARRIOR" end
  _G.UnitCanAttack = function() return true end
  _G.UnitCanAssist = function() return false end
  _G.UnitIsDeadOrGhost = function() return false end
  _G.UnitInRange = function() return nil end
  _G.GetUnitSpeed = function(unit) return st.speed[unit] or 0 end
  _G.GetTime = function() return st.now end
  _G.InCombatLockdown = function() return st.combat end
  _G.CheckInteractDistance = function()
    st.interactCalls = st.interactCalls + 1
    return st.interact
  end
  _G.IsPlayerSpell = function(spellID) return st.known[spellID] == true end
  _G.C_SpellBook = nil
  _G.Enum = nil
  _G.GetSpellIDForSpellIdentifier = nil

  if opts.noCSpell then
    _G.C_Spell = nil
    _G.IsSpellInRange = function()
      error("legacy IsSpellInRange reached with a spell ID", 2)
    end
  else
    _G.IsSpellInRange = nil
    local C_Spell = {
      IsSpellInRange = function() return st.rangeResult end,
    }
    if opts.armed then
      C_Spell.EnableSpellRangeCheck = function(spellID, enable)
        st.armedCalls[spellID] = enable
      end
    end
    _G.C_Spell = C_Spell
  end

  local elements = {}
  local UF = {
    frames = {},
    RegisterElement = function(name, element) elements[name] = element end,
    UnitExistsSafe = function() return true end,
    ApplyRangeModifier = function(frame, mul)
      frame.appliedMul = mul
      return true
    end,
  }
  local ns = {
    UF = UF,
    Client = { IsClassic = opts.classic },
    Secrets = { PlainBool = PlainBool },
    ExportPublic = function() end,
  }
  assert(loadfile(ELEMENT))("MidnightSimpleUnitFrames", ns)
  assert(elements.RangeFade, "RangeFade element was not registered")

  local units = opts.units or { "target" }
  st.frames = {}
  for i = 1, #units do
    local frame = { MSUFUnitKey = units[i], hooks = {} }
    function frame:IsVisible() return self.hidden ~= true end
    function frame:HookScript(name, fn) self.hooks[name] = fn end
    UF.frames[units[i]] = frame
    st.frames[units[i]] = frame
    elements.RangeFade.Apply(frame, { range = { active = true, alpha = OUT_ALPHA } })
  end

  st.frame = st.frames.target
  st.UF = UF
  st.element = elements.RangeFade
  function st.Refresh()
    UF.Range.Refresh("target")
  end
  function st.Fire(event, ...)
    local driver = assert(st.drivers[1], "range driver was not created")
    assert(driver.events[event], event .. " is not registered on the range driver")
    driver.OnEvent(driver, event, ...)
  end
  return st
end

local function ExpectMul(st, expected, label)
  local got = st.frame.appliedMul
  if got ~= expected then
    error(string.format("%s: expected alpha multiplier %s, got %s", label, tostring(expected), tostring(got)), 2)
  end
end

local scenarios = {}

scenarios[#scenarios + 1] = { "A classic, no armed API, known spell samples the target", function()
  local st = Load({ classic = true, known = { [355] = true }, rangeResult = 0, interact = true })
  ExpectMul(st, OUT_ALPHA, "A apply out of range")
  st.rangeResult = 1
  st.Refresh()
  ExpectMul(st, 1, "A refresh back in range")
  st.rangeResult = 0
  st.Fire("PLAYER_TARGET_CHANGED")
  ExpectMul(st, OUT_ALPHA, "A target change out of range")
  assert(st.interactCalls == 0, "A must answer from the spell, not interact distance")
end }

scenarios[#scenarios + 1] = { "B classic, armed API, no known spell uses interact distance out of combat", function()
  local st = Load({ classic = true, armed = true, known = {}, rangeResult = 0, interact = false })
  assert(next(st.armedCalls) == nil, "B must arm no spell")
  ExpectMul(st, OUT_ALPHA, "B apply out of interact distance")
  assert(st.interactCalls > 0, "B must consult CheckInteractDistance")
  st.combat = true
  st.Refresh()
  ExpectMul(st, 1, "B in combat resolves to full alpha")
end }

scenarios[#scenarios + 1] = { "C Mainline keeps the event-owned target path", function()
  local st = Load({ classic = false, armed = true, known = {}, rangeResult = 0, interact = false })
  ExpectMul(st, 1, "C apply")
  st.Refresh()
  ExpectMul(st, 1, "C refresh")
  st.combat = true
  st.Refresh()
  ExpectMul(st, 1, "C in combat")
  assert(st.interactCalls == 0, "C Mainline must not sample CheckInteractDistance for the target")
end }

scenarios[#scenarios + 1] = { "D no C_Spell never calls the legacy global with an ID", function()
  local st = Load({ classic = true, noCSpell = true, known = { [355] = true }, rangeResult = 0, interact = false })
  ExpectMul(st, OUT_ALPHA, "D apply out of interact distance")
end }

scenarios[#scenarios + 1] = { "E classic with the armed API still polls a target that walks away", function()
  local st = Load({ classic = true, armed = true, known = { [355] = true }, rangeResult = 1, interact = false })
  assert(next(st.armedCalls) == nil, "E Classic must not arm target spells")
  assert(st.drivers[1] and st.drivers[1].events.SPELL_RANGE_CHECK_UPDATE == nil,
    "E Classic must not register SPELL_RANGE_CHECK_UPDATE")
  ExpectMul(st, 1, "E apply in range")
  st.rangeResult = 0
  st.Refresh()
  ExpectMul(st, OUT_ALPHA, "E refresh re-queries the target with no range event")
  st.rangeResult = 1
  st.Refresh()
  ExpectMul(st, 1, "E refresh back in range")
  -- Stationary player, target walks out of range, no event of any kind: only the
  -- poll heartbeat can notice, so the target must keep a timer armed.
  local poll = assert(st.timerCallback, "E blind target must keep the poll timer armed")
  st.speed.target = 7
  st.rangeResult = 0
  st.now = 60
  poll()
  ExpectMul(st, OUT_ALPHA, "E poll samples the moving target")
  assert(st.interactCalls == 0, "E must answer from the spell, not interact distance")
end }

scenarios[#scenarios + 1] = { "F Mainline keeps the armed spell event path", function()
  local st = Load({ classic = false, armed = true, known = { [355] = true }, rangeResult = 0, interact = false })
  assert(st.armedCalls[355] == true, "F must arm spell 355")
  st.Fire("PLAYER_TARGET_CHANGED")
  ExpectMul(st, OUT_ALPHA, "F target change samples the armed spell")
  st.Fire("SPELL_RANGE_CHECK_UPDATE", 355, true, true)
  ExpectMul(st, 1, "F range event back in range")
  assert(st.interactCalls == 0, "F must not fall back to interact distance")
end }

-- Unit-event driver spans: RegisterUnitEvent takes at most 4 unit tokens, so the
-- UNIT_IN_RANGE_UPDATE registrations must spread over enough driver frames.
local function RangeDriverSpans(st)
  local spans, union, total = {}, {}, 0
  for i = 1, #st.drivers do
    local list = st.drivers[i].unitEvents.UNIT_IN_RANGE_UPDATE
    if list then
      assert(#list >= 1 and #list <= 4, "driver " .. i .. " holds " .. #list .. " unit tokens")
      spans[#spans + 1] = table.concat(list, ",")
      for j = 1, #list do
        assert(not union[list[j]], "unit token " .. list[j] .. " registered on two driver frames")
        union[list[j]] = true
        total = total + 1
      end
    end
  end
  return spans, union, total
end

local UNITS_13 = {
  "target", "focus", "pet",
  "boss1", "boss2", "boss3", "boss4", "boss5",
  "arena1", "arena2", "arena3", "arena4", "arena5",
}

scenarios[#scenarios + 1] = { "G TBC/Mists 5 arena slots spread 13 tokens over 4-token drivers", function()
  local st = Load({ classic = true, maxArena = 5, units = UNITS_13, known = {}, rangeResult = nil, interact = true })
  local spans, union, total = RangeDriverSpans(st)
  assert(#spans >= 4, "G expected at least 4 unit-event driver frames, got " .. #spans)
  assert(total == 13, "G expected 13 registered unit tokens, got " .. total)
  for i = 1, #UNITS_13 do
    assert(union[UNITS_13[i]], "G unit " .. UNITS_13[i] .. " is not registered")
  end
  assert(spans[1]:match("^target,"), "G main driver must keep the first span starting at target")
  assert(st.drivers[1].events.ARENA_OPPONENT_UPDATE, "G arena units must register ARENA_OPPONENT_UPDATE")
  -- Dropping arena4/arena5 must leave no stale span or registration behind.
  st.element.Disable(st.frames.arena4)
  st.element.Disable(st.frames.arena5)
  spans, union, total = RangeDriverSpans(st)
  assert(total == 11 and #spans == 3, "G after arena4/5 off expected 11 tokens on 3 frames, got " .. total .. " on " .. #spans)
  assert(not union.arena4 and not union.arena5, "G arena4/arena5 still registered after disable")
  for i = 1, #st.drivers do
    local d = st.drivers[i]
    if not d.unitEvents.UNIT_IN_RANGE_UPDATE then
      assert(d._msufRangeUnitFirst == nil, "G unused driver " .. i .. " kept a stale unit span")
    end
  end
  for i = 1, #UNITS_13 do
    st.element.Disable(st.frames[UNITS_13[i]])
  end
  spans, union, total = RangeDriverSpans(st)
  assert(#spans == 0 and total == 0, "G deactivation must clear every unit-event driver")
  for i = 1, #st.drivers do
    assert(next(st.drivers[i].events) == nil, "G driver " .. i .. " still has events after deactivation")
  end
end }

scenarios[#scenarios + 1] = { "H arena slots unset keeps the Mainline 3-frame spans", function()
  local units = {
    "target", "focus", "pet",
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3", "arena4", "arena5",
  }
  local st = Load({ classic = false, units = units, known = {}, rangeResult = nil, interact = true })
  local spans, union, total = RangeDriverSpans(st)
  assert(#spans == 3, "H expected exactly 3 unit-event driver frames, got " .. #spans)
  assert(spans[1] == "target,focus,pet,boss1", "H span 1 changed: " .. tostring(spans[1]))
  assert(spans[2] == "boss2,boss3,boss4,boss5", "H span 2 changed: " .. tostring(spans[2]))
  assert(spans[3] == "arena1,arena2,arena3", "H span 3 changed: " .. tostring(spans[3]))
  assert(total == 11 and not union.arena4 and not union.arena5, "H arena4/arena5 must stay unsupported without the fact")
  assert(st.element.IsEnabled(st.frames.arena4, { range = { active = true } }) == false,
    "H arena4 must not be a supported range unit when MSUF_MAX_ARENA_FRAMES is unset")
end }

scenarios[#scenarios + 1] = { "I arena slot fact 3 matches unset, junk and 9 clamp to 3 and 5", function()
  local function Tokens(maxArena)
    local st = Load({ classic = true, maxArena = maxArena, units = UNITS_13, known = {}, rangeResult = nil, interact = true })
    local _, _, total = RangeDriverSpans(st)
    for i = 6, 9 do
      assert(st.element.IsEnabled({ MSUFUnitKey = "arena" .. i }, { range = { active = true } }) == false,
        "I arena" .. i .. " must never be a supported range unit (MSUF_MAX_ARENA_FRAMES = " .. tostring(maxArena) .. ")")
    end
    return total
  end
  assert(Tokens(3) == 11, "I MSUF_MAX_ARENA_FRAMES = 3 must register 11 tokens")
  assert(Tokens(0) == 11, "I MSUF_MAX_ARENA_FRAMES = 0 keeps arena1-3 (11 tokens)")
  assert(Tokens("junk") == 11, "I non-numeric MSUF_MAX_ARENA_FRAMES falls back to 3")
  assert(Tokens(4) == 12, "I MSUF_MAX_ARENA_FRAMES = 4 must register 12 tokens")
  assert(Tokens(9) == 13, "I MSUF_MAX_ARENA_FRAMES = 9 must clamp to 5 arena slots")
end }

scenarios[#scenarios + 1] = { "J arena4/arena5 alone still own ARENA_OPPONENT_UPDATE", function()
  local st = Load({ classic = true, maxArena = 5, units = { "arena4", "arena5" }, known = {}, rangeResult = nil, interact = true })
  local spans = RangeDriverSpans(st)
  assert(#spans == 1 and spans[1] == "arena4,arena5", "J expected one span arena4,arena5, got " .. table.concat(spans, " | "))
  assert(st.drivers[1].events.ARENA_OPPONENT_UPDATE, "J arena4/arena5 must register ARENA_OPPONENT_UPDATE")
end }

scenarios[#scenarios + 1] = { "K one batched hide of all 13 frames unregisters every extra driver", function()
  local st = Load({ classic = true, maxArena = 5, units = UNITS_13, captureSchedule = true, known = {}, rangeResult = nil, interact = true })
  local spans = RangeDriverSpans(st)
  assert(#spans >= 4, "K expected at least 4 unit-event driver frames before the hide, got " .. #spans)
  for i = 1, #UNITS_13 do
    local frame = st.frames[UNITS_13[i]]
    frame.hidden = true
    assert(frame.hooks.OnHide, "K " .. UNITS_13[i] .. " has no OnHide hook")(frame)
  end
  -- Extra drivers still hold their spans until the coalesced sync runs once.
  local flush = assert(st.scheduled.MSUF_RANGE_VISIBILITY_SYNC, "K hide did not queue the visibility sync")
  flush()
  for i = 1, #st.drivers do
    local d = st.drivers[i]
    assert(next(d.events) == nil, "K driver " .. i .. " still has events after the last frame hid")
    assert(d._msufRangeUnitFirst == nil and d._msufRangeUnitLast == nil, "K driver " .. i .. " kept a unit span")
  end
end }

local failures = {}
for i = 1, #scenarios do
  local name, fn = scenarios[i][1], scenarios[i][2]
  local ok, err = pcall(fn)
  if not ok then
    failures[#failures + 1] = name .. ": " .. tostring(err)
  end
end

if #failures > 0 then
  for i = 1, #failures do
    print("FAIL " .. failures[i])
  end
  os.exit(1)
end

print("classic range fade smoke passed")
