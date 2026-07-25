-- PTR 12.1 ping integration must stay template-owned. Blizzard's native
-- PingableType_UnitFrameMixin reads `self.unit` before its secure unit
-- attribute. Addon-owned unit identity must therefore use MSUFUnitKey so the
-- native ping path receives the secure attribute value instead of tainted Lua.
local root = arg and arg[1] or "."

local function Read(path)
  local file = assert(io.open(root .. "/" .. path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function Contains(source, text, message)
  assert(source:find(text, 1, true), message)
end

local function Excludes(source, text, message)
  assert(not source:find(text, 1, true), message)
end

local factory = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua")
local core = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
local adapter = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua")
local headers = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua")
local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")

Contains(factory, 'return "SecureUnitButtonTemplate, PingableUnitFrameTemplate"',
  "standalone unit buttons lost Blizzard's native ping template")
Contains(headers, 'local SECURE_UNIT_BUTTON_TEMPLATE = "SecureUnitButtonTemplate, PingableUnitFrameTemplate"',
  "group children lost Blizzard's native ping template fallback")
Contains(headers, "self:SetAttribute('ping-receiver', true)",
  "secure group child initialization lost its native ping receiver attribute")

Excludes(factory, "Mixin(frame, PingableType_UnitFrameMixin)",
  "addon Lua reapplies Blizzard's ping mixin and taints the radial-wheel path")
Excludes(factory, "frame.GetTargetPingGUID = function", "obsolete addon ping callback survived")
Excludes(factory, "ConfigurePingableUnitFrame", "post-creation ping mutation survived in the factory")
Excludes(adapter, "ConfigurePingableUnitFrame", "group adapter still mutates native ping methods")
Excludes(adapter, 'frame:SetAttribute("ping-receiver", true)',
  "group adapter still performs an insecure post-creation ping attribute write")

for name, source in pairs({
  factory = factory,
  core = core,
  adapter = adapter,
  auras = auras,
}) do
  Excludes(source, "frame.unit =", name .. " writes Blizzard's reserved unit field")
  Excludes(source, "self.unit =", name .. " writes Blizzard's reserved unit field")
  Excludes(source, "shell.unit =", name .. " writes Blizzard's reserved unit field")
  Excludes(source, "visual.unit =", name .. " writes Blizzard's reserved unit field")
end

Contains(factory, "frame.MSUFUnitKey = unit", "standalone runtime unit identity lost MSUFUnitKey")
Contains(core, "frame.MSUFUnitKey = unit", "core frame spec lost MSUFUnitKey")
Contains(adapter, "shell.MSUFUnitKey = unit", "group shell identity lost MSUFUnitKey")

print("PASS pingable unit frames: native template uses secure unit attribute without addon field taint")
