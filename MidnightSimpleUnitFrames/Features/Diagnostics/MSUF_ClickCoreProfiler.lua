local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local type = type
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local select = select
local pcall = pcall
local table_sort = table.sort
local table_concat = table.concat
local math_min = math.min
local string_format = string.format
local CreateFrame = CreateFrame
local EnumerateFrames = EnumerateFrames
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local RegisterUnitWatch = RegisterUnitWatch
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local Mixin = Mixin
local PingableType_UnitFrameMixin = PingableType_UnitFrameMixin
local GetMouseFoci = GetMouseFoci
local GetMouseFocus = GetMouseFocus

local active = false
local saved = {}
local wrapped = setmetatable({}, { __mode = "k" })
local results = {}
local frameMax = 0
local frameCount = 0
local probeDriver
local probeButtons

local function AddUnique(list, seen, name)
  if type(name) ~= "string" or name == "" or seen[name] then return false end
  seen[name] = true
  list[#list + 1] = name
  return true
end

local function IsLoadedAddOn(name)
  local addons = _G.C_AddOns
  if addons and type(addons.IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(addons.IsAddOnLoaded, name)
    if ok and loaded ~= nil then return loaded == true end
  end
  if type(_G.IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(_G.IsAddOnLoaded, name)
    if ok then return loaded == true end
  end
  return false
end

local function AddAddOnByIndex(list, seen, index)
  local addons = _G.C_AddOns
  local name, title
  if addons and type(addons.GetAddOnInfo) == "function" then
    local ok, a, b = pcall(addons.GetAddOnInfo, index)
    if ok then name, title = a, b end
  elseif type(_G.GetAddOnInfo) == "function" then
    local ok, a, b = pcall(_G.GetAddOnInfo, index)
    if ok then name, title = a, b end
  end
  local n = type(name) == "string" and name or nil
  local t = type(title) == "string" and title or nil
  local hay = tostring(n or "") .. " " .. tostring(t or "")
  if hay:find("Midnight")
    or hay:find("MSUF")
    or hay:find("Unhalted")
    or hay:find("Clique")
    or hay:find("Click")
  then
    if IsLoadedAddOn(n) then AddUnique(list, seen, n) end
  end
end

local function AddInterestingAddOns(list, seen)
  local candidates = {
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_ClickCore",
    "UnhaltedUnitFrames",
    "UnhaltedUnitFrames_Libraries",
    "UnhaltedUnitFrames_Options",
    "Clique",
    "Blizzard_ClickBindingUI",
  }
  for i = 1, #candidates do
    if IsLoadedAddOn(candidates[i]) then AddUnique(list, seen, candidates[i]) end
  end

  local addons = _G.C_AddOns
  local count
  if addons and type(addons.GetNumAddOns) == "function" then
    local ok, n = pcall(addons.GetNumAddOns)
    if ok then count = n end
  elseif type(_G.GetNumAddOns) == "function" then
    local ok, n = pcall(_G.GetNumAddOns)
    if ok then count = n end
  end
  count = tonumber(count) or 0
  for i = 1, count do AddAddOnByIndex(list, seen, i) end
end

local function MouseFrame()
  if type(GetMouseFoci) == "function" then
    local ok, foci = pcall(GetMouseFoci)
    if ok and type(foci) == "table" then return foci[1] end
  end
  if type(GetMouseFocus) == "function" then
    local ok, frame = pcall(GetMouseFocus)
    if ok then return frame end
  end
end

local function SafeAttr(frame, key)
  if not (frame and frame.GetAttribute) then return nil end
  local ok, value = pcall(frame.GetAttribute, frame, key)
  if ok then return value end
end

local function FrameDebugName(frame)
  if not frame then return "nil" end
  local name = frame.GetName and frame:GetName()
  if type(name) ~= "string" or name == "" then name = tostring(frame) end
  return tostring(name)
end

local function InspectMouseFrame()
  local frame = MouseFrame()
  if not frame then
    print("MSUF MouseFocus: nil")
    return
  end
  local name = frame.GetName and frame:GetName()
  if type(name) ~= "string" or name == "" then name = tostring(frame) end
  local p = frame.GetParent and frame:GetParent()
  local parent = p and p.GetName and p:GetName() or nil
  print(string_format("MSUF MouseFocus %s unit=%s parent=%s type1=%s *type1=%s type2=%s *type2=%s clickcast=%s msuf=%s gf=%s",
    tostring(name),
    tostring(SafeAttr(frame, "unit") or frame.unit),
    tostring(parent),
    tostring(SafeAttr(frame, "type1")),
    tostring(SafeAttr(frame, "*type1")),
    tostring(SafeAttr(frame, "type2")),
    tostring(SafeAttr(frame, "*type2")),
    tostring(type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames[frame] == true),
    tostring(frame._msufOufCoreMethods == true or frame.MSUFSpec ~= nil),
    tostring(frame._msufIsGroupFrame == true)))
end

local FRAME_SCRIPTS = {
  "OnEvent",
  "OnAttributeChanged",
  "OnShow",
  "OnHide",
  "OnEnter",
  "OnLeave",
  "OnMouseDown",
  "OnMouseUp",
  "OnClick",
  "OnDoubleClick",
  "OnSizeChanged",
}

local function IsProtectedFrame(frame)
  if not (frame and frame.IsProtected) then return false end
  local ok, protected = pcall(frame.IsProtected, frame)
  return ok == true and protected == true
end

local function Now()
  if debugprofilestop then return debugprofilestop() end
  if GetTimePreciseSec then return GetTimePreciseSec() * 1000 end
  return GetTime() * 1000
end

local function WrappedKey(tbl, key)
  local keys = wrapped[tbl]
  if not keys then
    keys = {}
    wrapped[tbl] = keys
  end
  if keys[key] then return false end
  keys[key] = true
  return true
end

local function Record(label, detail, dt)
  label = tostring(label or "?")
  if detail ~= nil and detail ~= "" then label = label .. " " .. tostring(detail) end
  local r = results[label]
  if not r then
    r = { total = 0, count = 0, max = 0 }
    results[label] = r
  end
  r.total = r.total + dt
  r.count = r.count + 1
  if dt > r.max then r.max = dt end
end

local function Finish(label, detail, t0, ...)
  Record(label, detail, Now() - t0)
  return ...
end

local function WrapTable(tbl, key, label, detailFn)
  if type(tbl) ~= "table" or key == nil or type(tbl[key]) ~= "function" then return false end
  if not WrappedKey(tbl, key) then return false end
  local orig = tbl[key]
  saved[#saved + 1] = { tbl = tbl, key = key, fn = orig }
  tbl[key] = function(...)
    if not active then return orig(...) end
    local detail = detailFn and detailFn(...) or nil
    local t0 = Now()
    return Finish(label, detail, t0, orig(...))
  end
  return true
end

local function WrapScript(frame, script, label)
  if not (frame and script and frame.GetScript and frame.SetScript) then return false end
  -- Never replace scripts on protected unit buttons. Wrapping SecureUnitButton_OnClick
  -- makes Blizzard's protected target/menu actions execute from addon Lua and causes
  -- ADDON_ACTION_FORBIDDEN on TargetUnit().
  if IsProtectedFrame(frame) then return false end
  if not WrappedKey(frame, "script:" .. script) then return false end
  local orig = frame:GetScript(script)
  if type(orig) ~= "function" then return false end
  saved[#saved + 1] = { frame = frame, script = script, fn = orig }
  frame:SetScript(script, function(self, ...)
    if not active then return orig(self, ...) end
    local detail
    if script == "OnEvent" or script == "OnAttributeChanged" then
      detail = select(1, ...)
    elseif script == "OnMouseDown" or script == "OnMouseUp" or script == "OnClick" or script == "OnDoubleClick" then
      detail = select(1, ...)
    else
      detail = script
    end
    local t0 = Now()
    return Finish(label .. "." .. script, detail, t0, orig(self, ...))
  end)
  return true
end

local function FrameLabel(frame, fallback)
  local name = frame and frame.GetName and frame:GetName()
  if type(name) == "string" and name ~= "" then return name end
  return fallback or tostring(frame)
end

local function WrapRuntimeList(frame, listKey, labelKey, ownerLabel)
  local list = frame and frame[listKey]
  if type(list) ~= "table" then return 0 end
  local labels = frame[labelKey]
  local n = 0
  for i = 1, #list do
    local elementName = type(labels) == "table" and labels[i] or nil
    if WrapTable(list, i, ownerLabel .. ":fn:" .. tostring(elementName or i), function(_, reason)
      return reason
    end) then
      n = n + 1
    end
  end
  return n
end

local function WrapFrame(frame, label)
  if not frame then return 0 end
  local n = 0
  label = label or FrameLabel(frame)
  for i = 1, #FRAME_SCRIPTS do
    if WrapScript(frame, FRAME_SCRIPTS[i], label) then n = n + 1 end
  end

  if WrapTable(frame, "_msufIdentityBarPath", label .. ":identityBars", function(_, reason)
    return reason
  end) then n = n + 1 end
  if WrapTable(frame, "_msufIdentityPath", label .. ":identityText", function(_, reason)
    return reason
  end) then n = n + 1 end
  if WrapTable(frame, "_msufRuntimeAllPath", label .. ":runtimeAll", function(_, reason)
    return reason
  end) then n = n + 1 end
  if WrapTable(frame, "_msufGroupIdentityPath", label .. ":groupIdentity", function(_, reason)
    return reason
  end) then n = n + 1 end

  n = n + WrapRuntimeList(frame, "_msufIdentityFns", "_msufIdentityLabels", label .. ":identity")
  n = n + WrapRuntimeList(frame, "_msufRuntimeAllFns", "_msufRuntimeAllLabels", label .. ":runtime")
  n = n + WrapRuntimeList(frame, "_msufGroupIdentityFns", "_msufGroupIdentityLabels", label .. ":groupIdentity")

  local names = frame._msufEventNames
  if type(names) == "table" then
    for i = 1, #names do
      local event = names[i]
      if WrapTable(frame, event, label .. ":eventPath", function(_, ev)
        return ev or event
      end) then
        n = n + 1
      end
    end
  end

  local auras = frame.Auras
  if auras and WrapScript(auras, "OnShow", label .. ".Auras") then n = n + 1 end
  return n
end

local function WrapCoreTables()
  local n = 0
  local UF = MSUF.UF
  if UF then
    local ufKeys = {
      RunLeanIdentity = function(frame, reason) return tostring(frame and frame.unit) .. ":" .. tostring(reason) end,
      FrameRuntimeUpdate = function(frame, reason) return tostring(frame and frame.unit) .. ":" .. tostring(reason) end,
      UpdateRuntime = function(unit, reason) return tostring(unit) .. ":" .. tostring(reason) end,
      FrameForceUpdate = function(frame, reason) return tostring(frame and frame.unit) .. ":" .. tostring(reason) end,
      ApplySpec = function(frame, _, reason) return tostring(frame and frame.unit) .. ":" .. tostring(reason) end,
      ApplyElementToFrame = function(frame, name, _, reason)
        return tostring(frame and frame.unit) .. ":" .. tostring(name) .. ":" .. tostring(reason)
      end,
      OnUnitChanged = function(frame, oldUnit, newUnit)
        return tostring(frame and frame.unit) .. ":" .. tostring(oldUnit) .. ">" .. tostring(newUnit)
      end,
      SetFrameSpec = function(frame, spec) return tostring(frame and frame.unit) .. ":" .. tostring(spec and spec.key) end,
      OptimizeFrameHotpaths = function(frame) return tostring(frame and frame.unit) end,
      FlushDeferredRefreshes = false,
      SyncRuntimeDriver = false,
      RefreshElements = function(unit, _, reason) return tostring(unit) .. ":" .. tostring(reason) end,
      Apply = function(unit) return tostring(unit) end,
      Initialize = false,
    }
    for key, detailFn in pairs(ufKeys) do
      if WrapTable(UF, key, "UF." .. key, detailFn) then n = n + 1 end
    end
    if UF.Factory then
      local factoryKeys = {
        Apply = function(unit) return tostring(unit) end,
        SpawnAll = false,
        EnsureDeferredDriver = false,
      }
      for key, detailFn in pairs(factoryKeys) do
        if WrapTable(UF.Factory, key, "UF.Factory." .. key, detailFn) then n = n + 1 end
      end
    end
  end

  local GF = MSUF.GF or _G.MSUF_GF
  if GF then
    local gfKeys = {
      ApplyButton = function(frame, kind, reason)
        return tostring(frame and frame.unit) .. ":" .. tostring(kind) .. ":" .. tostring(reason)
      end,
      ApplyStructureSpec = function(frame, _, reason) return tostring(frame and frame.unit) .. ":" .. tostring(reason) end,
      RebindGroupHotRuntime = function(frame) return tostring(frame and frame.unit) end,
      ScanHeader = function(key, kind) return tostring(key) .. ":" .. tostring(kind) end,
      ScheduleScan = function(key, kind) return tostring(key) .. ":" .. tostring(kind) end,
      RefreshDirty = false,
      RegisterClickCastFrame = function(frame) return FrameLabel(frame) end,
    }
    for key, detailFn in pairs(gfKeys) do
      if WrapTable(GF, key, "GF." .. key, detailFn) then n = n + 1 end
    end
  end

  local A3 = MSUF.MSUF_Auras3
  if A3 then
    local a3Keys = {
      RenderFrame = function(frameOrUnit, reason)
        if type(frameOrUnit) == "table" then return reason or frameOrUnit.unit end
        return frameOrUnit
      end,
      EnableFrame = function(frame) return tostring(frame and frame.unit) end,
      RequestUnit = function(unit) return tostring(unit) end,
      RefreshUnit = function(unit) return tostring(unit) end,
      RefreshAll = false,
      ForceUpdateFrame = function(frame, reason) return tostring(frame and frame.unit) .. ":" .. tostring(reason) end,
      _ApplyGroupAuraFrame = function(frame, unit, kind) return tostring(unit or frame and frame.unit) .. ":" .. tostring(kind) end,
      _RequestGroupKindNow = function(kind) return tostring(kind) end,
    }
    for key, detailFn in pairs(a3Keys) do
      if WrapTable(A3, key, "A3." .. key, detailFn) then n = n + 1 end
    end
  end

  local bus = _G.MSUF_EventBus
  if bus then
    if WrapTable(bus, "Register", "EventBus.Register") then n = n + 1 end
    if WrapTable(bus, "Dispatch", "EventBus.Dispatch", function(_, event) return event end) then n = n + 1 end
    if bus.driver and WrapScript(bus.driver, "OnEvent", "EventBus.driver") then n = n + 1 end
  end

  return n
end

local function WrapKnownFrames(allFrames)
  local n = 0
  local seen = setmetatable({}, { __mode = "k" })
  local function add(frame, label)
    if frame and not seen[frame] then
      seen[frame] = true
      n = n + WrapFrame(frame, label)
    end
  end

  local UF = MSUF.UF
  if UF then
    if type(UF.frames) == "table" then
      for unit, frame in pairs(UF.frames) do add(frame, "UF:" .. tostring(unit)) end
    end
    if type(UF.frameList) == "table" then
      for i = 1, #UF.frameList do add(UF.frameList[i], "UF:list" .. i) end
    end
    if type(UF.attachedFrameList) == "table" then
      for i = 1, #UF.attachedFrameList do add(UF.attachedFrameList[i], "UF:attached" .. i) end
    end
    if UF.driver then add(UF.driver, "UF.driver") end
  end

  local GF = MSUF.GF or _G.MSUF_GF
  if GF then
    if type(GF.frameList) == "table" then
      for i = 1, #GF.frameList do add(GF.frameList[i], "GF:" .. i) end
    end
    if type(GF.headers) == "table" then
      for key, header in pairs(GF.headers) do add(header, "GF.header:" .. tostring(key)) end
    end
  end

  if type(EnumerateFrames) == "function" then
    local frame = EnumerateFrames()
    while frame do
      local name = frame.GetName and frame:GetName()
      if allFrames == true then
        add(frame, "ALL:" .. FrameLabel(frame))
      elseif type(name) == "string" and name:match("^MSUF") then
        add(frame, name)
      elseif frame._msufCoreScope or frame._msufIsGroupFrame or frame._msufA3NativeRoot then
        add(frame, FrameLabel(frame, "MSUF:anon"))
      end
      frame = EnumerateFrames(frame)
    end
  end
  return n
end

local function Restore()
  for i = #saved, 1, -1 do
    local item = saved[i]
    if item.tbl then
      item.tbl[item.key] = item.fn
    elseif item.frame and item.frame.SetScript then
      item.frame:SetScript(item.script, item.fn)
    end
    saved[i] = nil
  end
  wrapped = setmetatable({}, { __mode = "k" })
end

local function BuildReport()
  local list = {}
  for key, r in pairs(results) do
    list[#list + 1] = { key = key, total = r.total, count = r.count, max = r.max }
  end
  table_sort(list, function(a, b)
    if a.max == b.max then return a.total > b.total end
    return a.max > b.max
  end)
  return list
end

local function PrintReport()
  active = false
  if probeDriver then probeDriver:SetScript("OnUpdate", nil) end

  local list = BuildReport()
  local lines = {}
  lines[#lines + 1] = string_format("MSUF ClickCoreProfiler: frames=%d worstFrame=%.3fms entries=%d", frameCount, frameMax, #list)
  print("|cff7fd5ff" .. lines[1] .. "|r")
  if #list == 0 then
    local msg = "No wrapped MSUF Lua path ran during the spike window."
    lines[#lines + 1] = msg
    print("  " .. msg)
  end
  for i = 1, math_min(#list, 24) do
    local e = list[i]
    local line = string_format("%.3fms max | %.3fms total | %dx | %s", e.max, e.total, e.count, e.key)
    lines[#lines + 1] = line
    print("  " .. line)
  end

  _G.MSUF_ClickCoreProfilerLast = lines
  MSUF.ClickCoreProfilerLast = lines
  if type(_G.MSUF_GlobalDB) == "table" then
    _G.MSUF_GlobalDB.clickCoreProfilerLast = lines
  end

  Restore()
  results = {}
  frameMax = 0
  frameCount = 0
end

local function StartProfiler(seconds, allFrames)
  if active then
    print("MSUF ClickCoreProfiler already running.")
    return
  end
  seconds = tonumber(seconds) or 8
  if seconds < 3 then seconds = 3 elseif seconds > 30 then seconds = 30 end

  results = {}
  frameMax = 0
  frameCount = 0
  Restore()
  local wrappedCount = WrapCoreTables() + WrapKnownFrames(allFrames == true)
  active = true

  if not probeDriver then probeDriver = CreateFrame("Frame") end
  probeDriver:SetScript("OnUpdate", function(_, elapsed)
    local ms = (tonumber(elapsed) or 0) * 1000
    frameCount = frameCount + 1
    if ms > frameMax then frameMax = ms end
  end)

  print(string_format("|cff7fd5ffMSUF ClickCoreProfiler|r armed %.0fs, wrapped=%d%s. Click player/group/target now.", seconds, wrappedCount, allFrames and " allFrames" or ""))
  C_Timer.After(seconds, PrintReport)
end

local function ScriptFlag(frame, script)
  if not (frame and frame.GetScript) then return "0" end
  local ok, fn = pcall(frame.GetScript, frame, script)
  return ok == true and type(fn) == "function" and "1" or "0"
end

local function AttributeValue(frame, key)
  if not (frame and frame.GetAttribute) then return "-" end
  local ok, value = pcall(frame.GetAttribute, frame, key)
  if not ok then return "ERR" end
  if value == nil then return "nil" end
  return tostring(value)
end

local function ActiveElementNames(frame)
  local activeElements = frame and frame._msufActiveElements
  if type(activeElements) ~= "table" then return "-" end
  local names = {}
  for name, enabled in pairs(activeElements) do
    if enabled == true then names[#names + 1] = tostring(name) end
  end
  table_sort(names)
  return #names > 0 and table_concat(names, ",") or "-"
end

local function EventNames(frame)
  local names = frame and frame._msufEventNames
  if type(names) ~= "table" or #names == 0 then return "-" end
  local out = {}
  for i = 1, #names do out[i] = tostring(names[i]) end
  table_sort(out)
  return table_concat(out, ",")
end

local function CountFrameTree(frame, seen)
  if not frame or seen[frame] then
    return 0, 0, 0, 0, 0, 0, 0
  end
  seen[frame] = true

  local frames = 1
  local shown = frame.IsShown and frame:IsShown() and 1 or 0
  local buttons = frame.IsObjectType and frame:IsObjectType("Button") and 1 or 0
  local statusbars = frame.IsObjectType and frame:IsObjectType("StatusBar") and 1 or 0
  local textures, fontstrings = 0, 0
  local regions = 0

  if frame.GetRegions then
    regions = select("#", frame:GetRegions())
    for i = 1, regions do
      local region = select(i, frame:GetRegions())
      local objectType = region and region.GetObjectType and region:GetObjectType()
      if objectType == "Texture" then
        textures = textures + 1
      elseif objectType == "FontString" then
        fontstrings = fontstrings + 1
      end
    end
  end

  if frame.GetChildren then
    for i = 1, select("#", frame:GetChildren()) do
      local child = select(i, frame:GetChildren())
      local cf, cs, cr, ct, cfs, cb, csb = CountFrameTree(child, seen)
      frames = frames + cf
      shown = shown + cs
      regions = regions + cr
      textures = textures + ct
      fontstrings = fontstrings + cfs
      buttons = buttons + cb
      statusbars = statusbars + csb
    end
  end

  return frames, shown, regions, textures, fontstrings, buttons, statusbars
end

local function CountTreeScripts(frame, seen, counts)
  if not frame or seen[frame] then return counts end
  seen[frame] = true
  for i = 1, #FRAME_SCRIPTS do
    local script = FRAME_SCRIPTS[i]
    local ok, fn = frame.GetScript and pcall(frame.GetScript, frame, script)
    if ok == true and type(fn) == "function" then
      counts[i] = (counts[i] or 0) + 1
    end
  end
  if frame.GetChildren then
    for i = 1, select("#", frame:GetChildren()) do
      CountTreeScripts(select(i, frame:GetChildren()), seen, counts)
    end
  end
  return counts
end

local function ScriptCountLine(frame)
  local counts = CountTreeScripts(frame, {}, {})
  local out = {}
  for i = 1, #FRAME_SCRIPTS do
    out[i] = tostring(counts[i] or 0)
  end
  return table_concat(out, "/")
end

local function FindFrame(token)
  token = tostring(token or "")
  if token == "" then token = "player" end
  local UF = MSUF.UF
  if UF and type(UF.frames) == "table" and UF.frames[token] then return UF.frames[token], token end
  if _G[token] then return _G[token], token end
  local globalName = "MSUF_" .. token
  if _G[globalName] then return _G[globalName], token end
  return nil, token
end

local function ListMembership(frame)
  local UF = MSUF.UF
  local inFrames, frameListIndex, attachedIndex = "-", "-", "-"
  if UF and type(UF.frames) == "table" then
    for unit, candidate in pairs(UF.frames) do
      if candidate == frame then
        inFrames = tostring(unit)
        break
      end
    end
  end
  if UF and type(UF.frameList) == "table" then
    for i = 1, #UF.frameList do
      if UF.frameList[i] == frame then frameListIndex = tostring(i) break end
    end
  end
  if UF and type(UF.attachedFrameList) == "table" then
    for i = 1, #UF.attachedFrameList do
      if UF.attachedFrameList[i] == frame then attachedIndex = tostring(i) break end
    end
  end
  local clickcast = type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames[frame] == true
  return inFrames, frameListIndex, attachedIndex, clickcast
end

local function InspectFrame(token)
  local frame, resolved = FindFrame(token)
  if not frame then
    print("MSUF ClickCoreProfiler inspect: no frame for " .. tostring(resolved))
    return
  end

  local name = frame.GetName and frame:GetName() or tostring(frame)
  local unit = frame.unit or AttributeValue(frame, "unit")
  local width = frame.GetWidth and frame:GetWidth() or 0
  local height = frame.GetHeight and frame:GetHeight() or 0
  local level = frame.GetFrameLevel and frame:GetFrameLevel() or 0
  local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "-"
  local frames, shown, regions, textures, fontstrings, buttons, statusbars = CountFrameTree(frame, {})
  local inFrames, frameListIndex, attachedIndex, clickcast = ListMembership(frame)

  local lines = {}
  lines[#lines + 1] = string_format("MSUF Inspect %s name=%s unit=%s shown=%s visible=%s size=%.1fx%.1f strata=%s level=%s",
    tostring(resolved), tostring(name), tostring(unit), tostring(frame.IsShown and frame:IsShown()), tostring(frame.IsVisible and frame:IsVisible()), width or 0, height or 0, tostring(strata), tostring(level))
  lines[#lines + 1] = string_format("tree frames=%d shown=%d regions=%d textures=%d fontstrings=%d buttons=%d statusbars=%d",
    frames, shown, regions, textures, fontstrings, buttons, statusbars)
  lines[#lines + 1] = "scripts OE/OA/OS/OH/EN/LV/MD/MU/CL/DC/SZ="
    .. ScriptFlag(frame, "OnEvent")
    .. ScriptFlag(frame, "OnAttributeChanged")
    .. ScriptFlag(frame, "OnShow")
    .. ScriptFlag(frame, "OnHide")
    .. ScriptFlag(frame, "OnEnter")
    .. ScriptFlag(frame, "OnLeave")
    .. ScriptFlag(frame, "OnMouseDown")
    .. ScriptFlag(frame, "OnMouseUp")
    .. ScriptFlag(frame, "OnClick")
    .. ScriptFlag(frame, "OnDoubleClick")
    .. ScriptFlag(frame, "OnSizeChanged")
  lines[#lines + 1] = "treeScripts OE/OA/OS/OH/EN/LV/MD/MU/CL/DC/SZ=" .. ScriptCountLine(frame)
  lines[#lines + 1] = "attrs unit=" .. AttributeValue(frame, "unit")
    .. " *type1=" .. AttributeValue(frame, "*type1")
    .. " type1=" .. AttributeValue(frame, "type1")
    .. " *type2=" .. AttributeValue(frame, "*type2")
    .. " type2=" .. AttributeValue(frame, "type2")
    .. " *clickbutton2=" .. AttributeValue(frame, "*clickbutton2")
    .. " ping=" .. AttributeValue(frame, "ping-receiver")
    .. " vehicle=" .. AttributeValue(frame, "toggleForVehicle")
  lines[#lines + 1] = "membership UF.frames=" .. inFrames
    .. " frameList=" .. frameListIndex
    .. " attached=" .. attachedIndex
    .. " clickcast=" .. tostring(clickcast)
  local clickShell = frame._msufClickShell or frame._msufSecureShell
  if clickShell then
    local shellFrames, shellFrameList, shellAttached, shellClickcast = ListMembership(clickShell)
    lines[#lines + 1] = "clickShell name=" .. tostring(clickShell.GetName and clickShell:GetName())
      .. " shown=" .. tostring(clickShell.IsShown and clickShell:IsShown())
      .. " protected=" .. tostring(IsProtectedFrame(clickShell))
      .. " unit=" .. AttributeValue(clickShell, "unit")
      .. " type1=" .. AttributeValue(clickShell, "type1")
      .. " *type1=" .. AttributeValue(clickShell, "*type1")
      .. " *type2=" .. AttributeValue(clickShell, "*type2")
      .. " ping=" .. AttributeValue(clickShell, "ping-receiver")
      .. " membership=" .. tostring(shellFrames) .. "/" .. tostring(shellFrameList) .. "/" .. tostring(shellAttached)
      .. " clickcast=" .. tostring(shellClickcast)
  end
  local clickOverlay = frame._msufClickOverlay
  if clickOverlay then
    lines[#lines + 1] = "clickOverlay name=" .. tostring(clickOverlay.GetName and clickOverlay:GetName())
      .. " shown=" .. tostring(clickOverlay.IsShown and clickOverlay:IsShown())
      .. " protected=" .. tostring(IsProtectedFrame(clickOverlay))
      .. " unit=" .. AttributeValue(clickOverlay, "unit")
      .. " *type1=" .. AttributeValue(clickOverlay, "*type1")
      .. " *type2=" .. AttributeValue(clickOverlay, "*type2")
      .. " clickcast=" .. tostring(type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames[clickOverlay] == true)
  end
  lines[#lines + 1] = "elements=" .. ActiveElementNames(frame)
  lines[#lines + 1] = "events=" .. EventNames(frame)

  for i = 1, #lines do print("|cff7fd5ff" .. lines[i] .. "|r") end
  _G.MSUF_ClickCoreInspectLast = lines
  MSUF.ClickCoreInspectLast = lines
end
_G.MSUF_ClickCoreInspect = InspectFrame

local function PaintButton(button, r, g, b, text)
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(r, g, b, 0.88)
  local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text)
end

local function AddBars(button)
  local hp = CreateFrame("StatusBar", nil, button)
  hp:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  hp:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 5)
  hp:SetMinMaxValues(0, 100)
  hp:SetValue(86)
  hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  hp:SetStatusBarColor(0.1, 0.65, 0.16, 1)
  local power = CreateFrame("StatusBar", nil, button)
  power:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -1)
  power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  power:SetMinMaxValues(0, 100)
  power:SetValue(70)
  power:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  power:SetStatusBarColor(0.08, 0.35, 0.95, 1)
end

local function ProbePingGUID(self)
  local unit = self and self.GetAttribute and self:GetAttribute("unit")
  if unit and UnitExists and UnitExists(unit) then
    return UnitGUID and UnitGUID(unit) or nil
  end
end

local function AddProbeOptions(button, options)
  if type(options) ~= "table" then return end
  if options.toggleVehicle and button.SetAttribute then
    button:SetAttribute("toggleForVehicle", true)
  end
  if options.watch and RegisterUnitWatch then
    RegisterUnitWatch(button)
  end
  if options.event and button.RegisterEvent and button.SetScript then
    button:SetScript("OnEvent", function() end)
    button:RegisterEvent("PLAYER_TARGET_CHANGED")
    button:RegisterEvent("UNIT_TARGET")
  end
  if options.clickcast then
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    _G.ClickCastFrames[button] = true
  end
  if options.ping and button.SetAttribute then
    if Mixin and PingableType_UnitFrameMixin then
      Mixin(button, PingableType_UnitFrameMixin)
    end
    button:SetAttribute("ping-receiver", true)
    button.GetTargetPingGUID = ProbePingGUID
  end
  if options.attr and button.HookScript then
    button:HookScript("OnAttributeChanged", function() end)
  end
end

local function CreateProbeButton(name, y, secure, bars, label, options)
  local template = secure and "SecureUnitButtonTemplate" or nil
  local button = CreateFrame("Button", name, UIParent, template)
  button:SetSize(230, 34)
  button:SetPoint("CENTER", UIParent, "CENTER", 0, y)
  if secure then
    button:SetAttribute("unit", "player")
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button:RegisterForClicks("AnyUp")
  else
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function() end)
  end
  if bars then AddBars(button) end
  AddProbeOptions(button, options)
  PaintButton(button, secure and 0.10 or 0.35, bars and 0.25 or 0.10, secure and 0.55 or 0.12, label)
  return button
end

local function CopySpec(spec, unit)
  if type(spec) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(spec) do out[k] = v end
  out.unit = unit or spec.unit or "player"
  return out
end

local function CreateMSUFElementProbe(name, y, unit, label, mask, options)
  local UF = MSUF.UF
  local cfg = UF and UF.Config
  if not (UF and UF.ApplySpec and cfg and cfg.GetSpec) then
    return CreateProbeButton(name, y, true, true, label .. " missing UF")
  end

  unit = unit or "player"
  local spec = CopySpec(cfg.GetSpec(unit), unit)
  if not spec then
    return CreateProbeButton(name, y, true, true, label .. " missing spec")
  end

  local button = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
  button:SetSize(spec.width or 230, spec.height or 34)
  button:SetPoint("CENTER", UIParent, "CENTER", 280, y)
  button.unit = unit
  button.MSUFUnitKey = unit
  button.unitKey = unit
  button.configKey = spec.key
  button:SetAttribute("unit", unit)
  button:SetAttribute("*type1", "target")
  button:SetAttribute("*type2", "togglemenu")
  button:RegisterForClicks("AnyUp")
  AddProbeOptions(button, options)

  if UF.AttachFrame then UF.AttachFrame(button, { scope = "single" }) end
  UF.ApplySpec(button, spec, nil, mask)

  local tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tag:SetPoint("BOTTOM", button, "TOP", 0, 2)
  tag:SetText(label)
  button:Show()
  return button
end

local function ToggleProbeButtons()
  if InCombatLockdown and InCombatLockdown() then
    print("MSUF ClickCoreProfiler: leave combat before toggling probe buttons.")
    return
  end
  if probeButtons then
    local show = not probeButtons[1]:IsShown()
    for i = 1, #probeButtons do probeButtons[i]:SetShown(show) end
    print("MSUF ClickCoreProfiler probe buttons " .. (show and "shown" or "hidden") .. ".")
    return
  end
  probeButtons = {
    CreateProbeButton("MSUF_ClickCoreProbe_Secure", -130, true, false, "A secure player"),
    CreateProbeButton("MSUF_ClickCoreProbe_SecureBars", -170, true, true, "B secure + bars"),
    CreateProbeButton("MSUF_ClickCoreProbe_InertBars", -210, false, true, "C inert + bars"),
    CreateProbeButton("MSUF_ClickCoreProbe_Watch", -250, true, true, "D secure + bars + watch", { watch = true }),
    CreateProbeButton("MSUF_ClickCoreProbe_ClickCast", -290, true, true, "E secure + bars + clickcast", { clickcast = true }),
    CreateProbeButton("MSUF_ClickCoreProbe_Ping", -330, true, true, "F secure + bars + ping", { ping = true }),
    CreateProbeButton("MSUF_ClickCoreProbe_Event", -370, true, true, "G secure + bars + event", { event = true }),
    CreateProbeButton("MSUF_ClickCoreProbe_FullShell", -410, true, true, "H full shell", {
      watch = true,
      clickcast = true,
      ping = true,
      event = true,
      attr = true,
      toggleVehicle = true,
    }),
    CreateMSUFElementProbe("MSUF_ClickCoreProbe_MSUFHP", -130, "player", "I MSUF Health+Power", {
      Health = true,
      Power = true,
    }, { watch = true, clickcast = true, ping = true, toggleVehicle = true }),
    CreateMSUFElementProbe("MSUF_ClickCoreProbe_MSUFText", -190, "player", "J MSUF HP+Power+Text", {
      Health = true,
      Power = true,
      Text = true,
      NameText = true,
      HealthText = true,
      PowerText = true,
      InlineToT = true,
    }, { watch = true, clickcast = true, ping = true, toggleVehicle = true }),
    CreateMSUFElementProbe("MSUF_ClickCoreProbe_MSUFFull", -250, "player", "K MSUF full basic", true, {
      watch = true,
      clickcast = true,
      ping = true,
      attr = true,
      toggleVehicle = true,
    }),
    CreateMSUFElementProbe("MSUF_ClickCoreProbe_MSUFTarget", -310, "target", "L MSUF target full", true, {
      watch = true,
      clickcast = true,
      ping = true,
      attr = true,
      toggleVehicle = true,
    }),
  }
  print("MSUF ClickCoreProfiler probe buttons shown. Compare A-L in WoW CPU profiler.")
end

local function StartAddOnPeakProfiler(seconds)
  local profiler = _G.C_AddOnProfiler
  local metric = _G.Enum and _G.Enum.AddOnProfilerMetric
  if not (profiler and type(profiler.GetAddOnMetric) == "function" and metric and metric.LastTime) then
    print("|cffff5555MSUF AddOnPeak|r C_AddOnProfiler unavailable.")
    return
  end

  seconds = tonumber(seconds) or 10
  if seconds < 2 then seconds = 2 elseif seconds > 30 then seconds = 30 end

  local names, seen = {}, {}
  AddInterestingAddOns(names, seen)
  AddUnique(names, seen, "MidnightSimpleUnitFrames")

  local peak = {}
  local peakFocus = {}
  local peakAt = {}
  for i = 1, #names do
    peak[names[i]] = 0
    peakFocus[names[i]] = "nil"
    peakAt[names[i]] = 0
  end

  local driver = CreateFrame("Frame", "MSUF_AddOnPeakProfilerFrame", UIParent)
  local elapsed = 0
  local samples = 0
  local finished = false
  print(string_format("|cff7fd5ffMSUF AddOnPeak|r sampling %.0fs. Click MSUF real frames, then comparison frames/probes if loaded.", seconds))
  print("Tracking: " .. table_concat(names, ", "))
  if driver.SetSize then driver:SetSize(1, 1) end
  if driver.SetPoint and UIParent then driver:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0) end

  local function FinishPeakReport(self)
    if finished == true then return end
    finished = true
    self:SetScript("OnUpdate", nil)
    if self.Hide then self:Hide() end
    local rows = {}
    for i = 1, #names do
      rows[#rows + 1] = { name = names[i], value = peak[names[i]] or 0 }
    end
    table_sort(rows, function(a, b) return a.value > b.value end)
    print(string_format("|cff7fd5ffMSUF AddOnPeak|r %d frames, peak LastTime:", samples))
    local limit = math_min(#rows, 12)
    for i = 1, limit do
      local row = rows[i]
      print(string_format("  %.3fms @%.2fs | %s | focus=%s",
        row.value,
        peakAt[row.name] or 0,
        row.name,
        peakFocus[row.name] or "nil"))
    end
    _G.MSUF_AddOnPeakLast = rows
    MSUF.AddOnPeakLast = rows
  end

  driver:SetScript("OnUpdate", function(self, dt)
    if finished == true then return end
    elapsed = elapsed + (dt or 0)
    samples = samples + 1
    local focus = FrameDebugName(MouseFrame())
    for i = 1, #names do
      local name = names[i]
      local value = profiler.GetAddOnMetric(name, metric.LastTime)
      if type(value) == "number" and value > (peak[name] or 0) then
        peak[name] = value
        peakFocus[name] = focus
        peakAt[name] = elapsed
      end
    end
    if elapsed >= seconds then
      FinishPeakReport(self)
    end
  end)
  if driver.Show then driver:Show() end
  if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(seconds + 0.25, function()
      FinishPeakReport(driver)
    end)
  end
end

SLASH_MSUFADDONPEAK1 = "/msufaddonpeak"
SLASH_MSUFADDONPEAK2 = "/msufpeak"
SlashCmdList.MSUFADDONPEAK = function(msg)
  StartAddOnPeakProfiler(msg)
end

SLASH_MSUFMOUSEFOCUS1 = "/msufmouse"
SlashCmdList.MSUFMOUSEFOCUS = function()
  InspectMouseFrame()
end

SLASH_MSUFCLICKCORE1 = "/msufclickcore"
SLASH_MSUFCLICKCORE2 = "/msufcc"
local function HandleClickCoreSlash(msg)
  msg = tostring(msg or "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "buttons" or cmd == "btn" then
    ToggleProbeButtons()
    return
  end
  if cmd == "last" then
    local lines = _G.MSUF_ClickCoreProfilerLast
    if type(lines) ~= "table" then print("MSUF ClickCoreProfiler: no last report.") return end
    for i = 1, #lines do print(lines[i]) end
    return
  end
  if cmd == "all" then
    StartProfiler(arg ~= "" and arg or nil, true)
    return
  end
  if cmd == "inspect" or cmd == "i" then
    InspectFrame(arg ~= "" and arg or "player")
    return
  end
  StartProfiler(cmd ~= "" and cmd or arg)
end
SlashCmdList.MSUFCLICKCORE = HandleClickCoreSlash

SLASH_MSUFCLICKINSPECT1 = "/msufinspect"
SLASH_MSUFCLICKINSPECT2 = "/msufi"
SlashCmdList.MSUFCLICKINSPECT = function(msg)
  msg = tostring(msg or "")
  msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
  InspectFrame(msg ~= "" and msg or "player")
end

SLASH_MSUFCLICKALL1 = "/msufclickall"
SLASH_MSUFCLICKALL2 = "/msufcca"
SlashCmdList.MSUFCLICKALL = function(msg)
  msg = tostring(msg or "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "inspect" or cmd == "i" then
    InspectFrame(arg ~= "" and arg or "player")
    return
  end
  StartProfiler(msg, true)
end
