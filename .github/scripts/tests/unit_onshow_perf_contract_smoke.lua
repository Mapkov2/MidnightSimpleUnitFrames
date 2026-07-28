local root = arg and arg[1] or "."

local function Read(relative)
  local file = assert(io.open(root .. "/" .. relative, "rb"))
  local source = file:read("*a")
  file:close()
  return (source:gsub("\r\n", "\n"))
end

local core = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
local factory = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua")
local health = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua")

assert(core:find("frame._msufCoreOnShowIdentityRefreshed =\n      UF.RunLeanIdentity", 1, true),
  "Core OnShow no longer publishes the lean identity result")
assert(core:find("IDENTITY_ELEMENTS[name] ~= true and IDENTITY_BAR_ELEMENTS[name] ~= true", 1, true),
  "Core no longer preserves the full-refresh fallback for uncovered elements")
assert(factory:find("local identityRefreshed = frame._msufCoreOnShowIdentityRefreshed == true", 1, true)
    and factory:find("frame._msufCoreOnShowIdentityRefreshed = nil", 1, true),
  "Factory OnShow does not consume the one-shot Core refresh result")
assert(factory:find("if identityRefreshed and frame._msufRuntimeOnShowNeedsFull ~= true then return end", 1, true)
    and factory:find('UF.FrameRuntimeUpdate(frame, "MSUF_FRAME_SHOWN")', 1, true),
  "Factory lost either the dedupe or its conservative full-refresh fallback")

local attach = assert(factory:find('UF.AttachFrame(frame, { scope = "single" })', 1, true))
local ensure = assert(factory:find("EnsureRuntimeOnShow(frame)", attach, true))
assert(attach < ensure, "Factory OnShow hook can run before Core owns visibility")

assert(health:find('if mode == "gradient" and PrepareHealthGradientCurve then\n    PrepareHealthGradientCurve(h)', 1, true),
  "health gradient curve returned to first-unit acquisition")

print("unit OnShow perf contract smoke: ok")
