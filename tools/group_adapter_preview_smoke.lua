_G = _G or _ENV

local attached, detached = 0, 0
local MSUF = { UF = {}, GF = {} }
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.ClickCastFrames = {}
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

function MSUF.UF.SetFrameSpec(frame, spec, unit)
  frame.MSUFSpec, frame.unit, frame.unitKey = spec, unit, unit
end
function MSUF.UF.AttachFrame() attached = attached + 1; return true end
function MSUF.UF.DetachFrame() detached = detached + 1; return true end
function MSUF.UF.ApplySpec() return true end

local serial = 0
function MSUF.GF.CompileSpec(kind, _, unit)
  serial = serial + 1
  return {
    scope = "group",
    key = "gf_" .. kind,
    unit = unit,
    width = 120,
    height = 36,
    _msufGFCompileSerial = serial,
  }
end

local preview = {
  _msufGFIsPreviewFrame = true,
  attributes = { unit = "player" },
}
function preview:GetAttribute(key) return self.attributes[key] end
function preview:RegisterForClicks() self.clickRegistrations = (self.clickRegistrations or 0) + 1 end
function preview:SetSize(w, h) self.width, self.height = w, h end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

assert(MSUF.GF.ApplyButton(preview, "party", "PREVIEW") == true, "preview apply failed")
assert(attached == 1 and MSUF.GF.frames[preview] == true, "preview did not attach for rendering")
assert(_G.ClickCastFrames[preview] == nil, "preview joined ClickCastFrames")
assert(preview.clickRegistrations == nil, "preview registered default clicks")

MSUF.GF.UntrackFrame(preview)
assert(detached == 1 and MSUF.GF.frames[preview] == nil, "preview did not detach from runtime tracking")
assert(_G.ClickCastFrames[preview] == nil, "detached preview remained in ClickCastFrames")

assert(MSUF.GF.ApplyButton(preview, "party", "PREVIEW_REOPEN") == true, "pooled preview reapply failed")
assert(attached == 2 and MSUF.GF.frames[preview] == true, "pooled preview did not reattach")
assert(_G.ClickCastFrames[preview] == nil and preview.clickRegistrations == nil,
  "reopened preview gained click handling")

print("group adapter preview smoke: ok")
