local World = {}
local function Callable(value)
  return type(value) == "function" or (type(value) == "table" and getmetatable(value)
    and type(getmetatable(value).__call) == "function")
end
local function Watched(name)
  return type(name) == "string" and (name:match("^Unit") or name:match("^GetUnit")
    or name:match("^GetSpecialization") or name == "GetRaidTargetIndex" or name == "GetComboPoints"
    or name:match("^GetRune") or name == "GetShapeshiftFormID" or name == "GetNumSpecializations"
    or name == "IsPlayerSpell" or name == "GetPowerRegenForPowerType" or name == "GetPowerRegen"
    or name == "PlayerVehicleHasComboPoints")
end

function World.Open(root, flavor, state)
  local function RejectLoadWork() error("scene did work at file load") end
  local inert = { CreateFrame = RejectLoadWork, C_Timer = { After = RejectLoadWork,
    NewTimer = RejectLoadWork, NewTicker = RejectLoadWork } }
  inert._G = inert
  setmetatable(inert, { __index = function(_, key)
    if Watched(key) then return RejectLoadWork end
    return _G[key]
  end, __newindex = function() error("scene added a global at file load") end })
  local namespace = { UF = {} }
  for _, file in ipairs({ "MSUF_UF_PreviewKit.lua", "MSUF_UF_PreviewSurfaces.lua",
    "MSUF_UF_CastbarScene.lua", "MSUF_UF_ClassPowerScene.lua" }) do
    setfenv(assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/" .. file)), inert)("MSUF", namespace)
  end
  local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
  local Regions = dofile(root .. "/tools/tests/preview_oracle_regions.lua")
  local spy = { calls = {}, armed = false }
  local function Record(name)
    if spy.armed then error("scene called unit API: " .. name, 2) end
  end
  local h = Harness.New(root, flavor, { beforeBoot = function(w)
    local env = w.env
    env.MAX_BOSS_FRAMES = 5
    env.INTERRUPTED = "Interrupted"
    Regions.Install(w.world)
    for _, name in ipairs({ "Enum", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_UnitAuras" }) do
      env[name] = setmetatable({}, { __index = env[name] })
    end
    env.Constants = { UnitPowerSpellIDs = {} }
    env.STAGGER_YELLOW_TRANSITION, env.STAGGER_RED_TRANSITION = .3, .6
    env.C_Secrets = { ShouldAurasBeSecret = function() return false end }
    env.CreateColor = function(r, g, b, a)
      return { r = r, g = g, b = b, a = a or 1, GetRGB = function() return r, g, b end,
        GetRGBA = function() return r, g, b, a or 1 end }
    end
    env.RAID_CLASS_COLORS = { MAGE = env.CreateColor(.2, .5, .8), ROGUE = env.CreateColor(1, .9, .3) }
    for name, value in pairs({ SPEC_DEMONHUNTER_DEVOURER = 3, SPEC_MAGE_ARCANE = 1,
      SPEC_MONK_WINDWALKER = 3, SPEC_MONK_BREWMASTER = 1, SPEC_WARLOCK_DESTRUCTION = 3,
      SPEC_WARLOCK_DEMONOLOGY = 2, SPEC_DEMONHUNTER_VENGEANCE = 2 }) do env[name] = value end
    env.Enum.PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5,
      RunicPower = 6, SoulShards = 7, LunarPower = 8, HolyPower = 9, Alternate = 10, Maelstrom = 11,
      Chi = 12, Insanity = 13, BurningEmbers = 14, DemonicFury = 15, ArcaneCharges = 16,
      Fury = 17, Pain = 18, Essence = 19, Balance = 26, ShadowOrbs = 28 }
    if state then
      env.UnitClass = function() return state.class, state.class end
      env.UnitPowerType = function() return state.primaryPower or 0 end
      env.UnitPower = function(_, _, raw) return state.count * (raw and (state.modifier or 1) or 1) end
      env.GetComboPoints = function() return state.count end
      env.UnitPowerMax = function(_, power, raw)
        return state.maximum * (raw and (state.modifier or 1) or 1)
      end
      env.UnitPowerDisplayMod = function() return state.modifier or 1 end
      env.UnitPartialPower = function() return (state.partial or 0) * 1000 end
      env.UnitHealthMax = function() return state.maximum end
      env.UnitStagger = function() return state.count end
      env.GetSpecialization = function() return state.spec end
      env.C_SpecializationInfo.GetSpecialization = env.GetSpecialization
      env.UnitHasVehicleUI = function() return false end
      env.GetShapeshiftFormID = function() return state.formID end
      env.GetRuneCooldown = function(i)
        local rune = state.runes and state.runes[i]
        if rune then return rune.start, rune.duration, rune.ready end
        return 0, 10, i <= state.count
      end
      env.GetRuneType = function(i) return (i - 1) % 3 + 1 end
      env.C_SpellBook.IsSpellKnown = function() return true end
      env.C_Spell.GetSpellCastCount = function() return state.count end
      env.C_Spell.GetSpellMaxCumulativeAuraApplications = function() return state.maximum end
      env.GetTime = function() return state.time or 100 end
      env.C_UnitAuras.GetPlayerAuraBySpellID = function(id)
        if id == 1217607 then return nil end
        if state.auras then return state.auras[id] end
        return { applications = state.count, spellId = id, auraInstanceID = id }
      end
    end
    local function Wrap(name, fn)
      spy.calls[name] = 0
      local function Call(...)
        spy.calls[name] = spy.calls[name] + 1
        Record(name)
        return fn(...)
      end
      if type(fn) == "table" then
        local meta = {}
        for key, value in pairs(getmetatable(fn)) do meta[key] = value end
        meta.__call = function(_, ...) return Call(...) end
        return setmetatable({}, meta)
      end
      return Call
    end
    for name, value in pairs(env) do
      if Watched(name) and Callable(value) then env[name] = Wrap(name, value) end
    end
    for _, name in ipairs({ "C_PlayerInfo", "C_UnitAuras", "C_SpecializationInfo", "C_Spell", "C_SpellBook" }) do
      local original = env[name]
      if type(original) == "table" then
        local proxy = {}
        setmetatable(proxy, { __index = function(_, key)
          local fn = original[key]
          if not Callable(fn) then return fn end
          local wrapped = Wrap(name .. "." .. key, fn)
          rawset(proxy, key, wrapped)
          return wrapped
        end })
        env[name] = proxy
      end
    end
    local meta = getmetatable(env)
    local fallback = meta.__index
    meta.__index = function(t, key)
      local value = fallback(t, key)
      if Watched(key) and Callable(value) then
        value = Wrap(key, value)
        rawset(t, key, value)
      end
      return value
    end
  end })
  h.Regions, h.spy = Regions, spy
  for _, method in ipairs({ "RegisterEvent", "RegisterUnitEvent", "SetAttribute", "HookScript", "SetScript" }) do
    local original = assert(h.widgets.Methods[method])
    h.widgets.Methods[method] = function(region, key, value, ...)
      local r = region
      while r and not r._msufPreviewScope do r = r.parent end
      if r and (method ~= "SetScript" or value ~= nil) then error("scene attempted " .. method, 2) end
      return original(region, key, value, ...)
    end
  end
  if state then
    h.env.C_StringUtil = { CreateNumericRuleFormatter = function()
      return { SetBreakpoints = function(self, points) self.format = points[1].format end }
    end }
    h.env.MSUF_Auras3.CreateClassPowerAuraSensor = function(host, _, _, initialize)
      Record("CreateClassPowerAuraSensor")
      local button = h.env.CreateFrame("Button", nil, host)
      button.SetApplicationBar = function(_, bar, config)
        bar:SetMinMaxValues(0, config.maxApplications); bar:SetValue(state.count)
      end
      button.SetApplicationCount = function(_, text, config)
        text:SetFormattedText(config.formatter.format, state.count)
      end
      button.ClearApplicationCount = function() end
      initialize(button)
      return { SetEnabled = function() end }
    end
  end
  function h:SceneCall(fn, ...)
    spy.armed = true
    local result = { pcall(fn, ...) }
    spy.armed = false
    assert(result[1], result[2])
    return unpack(result, 2)
  end
  for _, name in ipairs({ "UnitCastingInfo", "UnitChannelInfo", "UnitPower", "UnitPowerMax",
    "GetSpecialization", "GetRaidTargetIndex", "GetRuneCooldown" }) do
    local ok, why = pcall(h.SceneCall, h, function() h.env[name]("player") end)
    assert(not ok and tostring(why):find("scene called unit API: " .. name, 1, true), "unwatched API " .. name)
  end
  for _, api in ipairs({ { "C_PlayerInfo", "GetClass" }, { "C_UnitAuras", "GetPlayerAuraBySpellID" },
    { "C_SpecializationInfo", "GetSpecialization" }, { "C_Spell", "GetSpellCastCount" },
    { "C_SpellBook", "IsSpellKnown" } }) do
    local name = api[1]
    local ok, why = pcall(h.SceneCall, h, function() h.env[name][api[2]]("player") end)
    assert(not ok and tostring(why):find("scene called unit API: " .. name, 1, true), "unwatched namespace " .. name)
  end
  function h:Host()
    local frame = self.env.CreateFrame("Frame", nil, self.env.UIParent)
    frame:SetSize(800, 600)
    frame:SetPoint("CENTER", self.env.UIParent, "CENTER", 27, -31)
    return frame
  end
  return h
end

function World.Upvalue(fn, name, seen)
  seen = seen or {}
  if seen[fn] then return end
  seen[fn] = true
  local nested = {}
  for i = 1, 200 do
    local key, value = debug.getupvalue(fn, i)
    if not key then break end
    if key == name then return value end
    if type(value) == "function" then nested[#nested + 1] = value end
  end
  for _, child in ipairs(nested) do
    local value = World.Upvalue(child, name, seen)
    if value ~= nil then return value end
  end
end

local ANCHORS = { TOPLEFT = {0,1}, TOP = {.5,1}, TOPRIGHT = {1,1}, LEFT = {0,.5}, CENTER = {.5,.5},
  RIGHT = {1,.5}, BOTTOMLEFT = {0,0}, BOTTOM = {.5,0}, BOTTOMRIGHT = {1,0} }
local function Scale(r)
  if not r then return 1 end
  return (r.scale or 1) * (r.ignoreParentScale and 1 or Scale(r.parent))
end

function World.Rect(r, cache, visiting)
  cache, visiting = cache or {}, visiting or {}
  if cache[r] then return cache[r] end
  assert(not visiting[r], "geometry anchor cycle")
  visiting[r] = true
  local rect
  if r.allPoints then
    rect = World.Rect(r.allPoints, cache, visiting)
  elseif r.parent and r.parent.statusBarTexture == r then
    local p = World.Rect(r.parent, cache, visiting)
    local b = r.parent
    local lo, hi = b.minimum or 0, b.maximum or 1
    local fraction = hi > lo and math.max(0, math.min(1, ((b.value or lo) - lo) / (hi - lo))) or 0
    rect = { p[1] + (b.reverseFill and p[3] * (1 - fraction) or 0), p[2], p[3] * fraction, p[4] }
  else
    local scale = Scale(r)
    local w, h = (r.width or 0) * scale, (r.height or 0) * scale
    local coords = {}
    for _, point in ipairs(r.points or {}) do
      local relative = point.relativeTo or r.parent
      local base = relative and World.Rect(relative, cache, visiting) or {0,0,0,0}
      local a, b = ANCHORS[point.point], ANCHORS[point.relativePoint or point.point]
      assert(a and b, "unknown point")
      coords[#coords + 1] = { a[1], a[2], base[1] + b[1] * base[3] + (point.x or 0) * scale,
        base[2] + b[2] * base[4] + (point.y or 0) * scale }
    end
    local first = coords[1]
    if first then
      for i = 2, #coords do
        local c = coords[i]
        if c[1] ~= first[1] then w = (c[3] - first[3]) / (c[1] - first[1]) end
        if c[2] ~= first[2] then h = (c[4] - first[4]) / (c[2] - first[2]) end
      end
      rect = { first[3] - first[1] * w, first[4] - first[2] * h, w, h }
    else rect = { 0, 0, w, h } end
  end
  visiting[r], cache[r] = nil, rect
  return rect
end

function World.Snapshot(h, frame, owner, roots)
  local snapshot, objects = h.Regions.Capture(h.world, roots or { surface = frame }, { owner = owner })
  for name, props in pairs(snapshot) do
    if props.kind == "AnimationGroup" or props.kind == "Alpha" then
      snapshot[name] = nil
    else
    props.rect = World.Rect(objects[name])
    props.points, props.allPoints, props.parent = nil, nil, nil
    -- Size is resolved above, including native two-anchor regions.
    props.width, props.height = nil, nil
    end
  end
  return snapshot
end

function World.CPSnapshot(h, CP, owner)
  local roots = { surface = CP.container }
  for _, key in ipairs({ "textFrame", "text", "bgTex", "_outline" }) do
    if CP[key] then roots["surface/" .. key] = CP[key] end
  end
  for _, key in ipairs({ "bars", "ticks" }) do
    for i, region in ipairs(CP[key]) do roots["surface/" .. key .. "/" .. i] = region end
  end
  return World.Snapshot(h, CP.container, owner, roots)
end

function World.Equal(h, expected, actual, label)
  local diffs = h.Regions.Compare(expected, actual)
  assert(#diffs == 0, label .. "\n" .. table.concat(diffs, "\n", 1, math.min(15, #diffs)))
end

function World.Isolated(h, frame)
  local _, objects = h.Regions.Capture(h.world, { surface = frame }, { owner = frame.parent })
  for name, r in pairs(objects) do
    assert(not next(r.events or {}), "scene event: " .. name)
    assert(not next(r.attributes or {}), "scene secure attribute: " .. name)
    assert(not next(r.scripts or {}), "scene script: " .. name)
    assert(not r.IsProtected or not r:IsProtected(), "protected scene: " .. name)
  end
end

function World.Lifecycle(h, root, scene)
  local first = scene:Frame()
  World.Isolated(h, first)
  h:SceneCall(root.Deactivate, root)
  assert(not scene:IsActive() and not first:IsShown(), "closed scene shown")
  for _, event in ipairs({ "CONFIG_APPLIED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    local handlers = h.core.EventBus.handlers[event]
    assert(not handlers or not handlers.index[root.eventKey], "closed subscription " .. event)
  end
  local n, tickers, afters = #h.widgets.timers, #h.widgets.tickers, h.widgets.afterCount
  h:SceneCall(scene.Refresh, scene)
  h:SceneCall(scene.Show, scene)
  h:SceneCall(root.Request, root, "closed")
  assert(#h.widgets.timers == n, "timer while closed")
  assert(#h.widgets.tickers == tickers and h.widgets.afterCount == afters, "clock or callback while closed")
  h:SceneCall(root.Activate, root)
  assert(scene:Frame() == first, "scene pool not reused")
  local paints = 0
  local original = scene.host.opts.paint
  scene.host.opts.paint = function(...) paints = paints + 1; return original(...) end
  h.widgets:SetCombat(true)
  h:SceneCall(root.onCombat)
  assert(h:SceneCall(h.GF.HidePreviewsForCombat) == false, "isolated combat hide requested live header rebuild")
  local pending, clocks = h.widgets.afterCount, #h.widgets.tickers
  h:SceneCall(scene.Refresh, scene)
  h:SceneCall(scene.Show, scene)
  h:SceneCall(root.Request, root, "combat")
  h:SceneCall(root.onConfig)
  h:SceneCall(root.host.Refresh, root.host)
  assert(paints == 0 and not first:IsShown(), "scene work in combat")
  assert(h.widgets.afterCount == pending and #h.widgets.tickers == clocks, "scheduled work in combat")
  assert(not scene.host.clock, "animation survives combat")
  h.widgets:SetCombat(false)
  h:SceneCall(root.onRegen)
  h:SceneCall(root.host.run)
  assert(paints == 1 and scene:Frame() == first and first:IsShown(), "regen restore")
  h:SceneCall(scene.Hide, scene)
  h:SceneCall(root.host.Refresh, root.host)
  assert(not first:IsShown(), "explicit hide forgotten")
  h:SceneCall(scene.Show, scene)
  h:SceneCall(root.Release, root)
  assert(not first:IsShown() and not scene.host.clock, "released scene remains active")
  assert(#h.violations == 0, "blocked calls: " .. table.concat(h.violations, "\n"))
end

function World.InputAndIsolation(h, root, scene)
  local copy = scene.opts
  local secret = setmetatable({}, { __index = function() error("secret indexed") end,
    __eq = function() error("secret compared") end })
  local original = h.env.issecretvalue
  h.env.issecretvalue = function(v) return rawequal(v, secret) or original(v) end
  assert(not pcall(scene.SetOptions, scene, { sample = secret }), "secret accepted")
  assert(scene.opts == copy, "secret input partially changed options")
  h.env.issecretvalue = original
  local otherRoot = h.GF.NewPreviewScene(root.parent)
  local other = h:SceneCall(otherRoot[scene.kind], otherRoot,
    scene.kind == "Castbar" and scene.key or copy, scene.kind == "Castbar" and copy or nil)
  assert(not other:Frame(), "second closed root allocated")
  h:SceneCall(otherRoot.Activate, otherRoot)
  assert(other:Frame() ~= scene:Frame(), "pool shared across roots")
  local before = World.Snapshot(h, scene:Frame(), root.parent)
  h:SceneCall(other.Hide, other)
  World.Equal(h, before, World.Snapshot(h, scene:Frame(), root.parent), "cross-root hide")
  h:SceneCall(otherRoot.Release, otherRoot)
end

return World
