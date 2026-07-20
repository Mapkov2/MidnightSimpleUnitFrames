local ROOT = (arg and arg[1]) or "."

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function Source(relative)
    return Read(ROOT .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/" .. relative)
end

local factory = Source("MSUF_UF_Factory.lua")
local headers = Source("Group/MSUF_UF_Group_Headers.lua")
local editMode = Source("Group/MSUF_UF_Group_EM2.lua")
local preview = Source("Group/MSUF_UF_Group_Preview.lua")
local layout = Read(ROOT .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_Layout.lua")
local picker = Read(ROOT .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_AnchorPicker.lua")

assert(factory:find("local function EnableScreenClamp(frame)", 1, true),
    "unit-frame screen clamp helper is missing")
assert(factory:find("layout:SetClampedToScreen(true)", 1, true),
    "unit-frame root does not enable Blizzard's physical screen clamp")
assert(factory:find("EnableScreenClamp(frame)\n  UF.AttachFrame", 1, true),
    "unit-frame clamp is not installed on the spawn cold path")
assert(factory:find("layout:SetPoint(point, anchor, relativePoint, x, y)", 1, true),
    "unit-frame clamp replaced the configured CDM/custom anchor")
assert(factory:find("local LATE_GROUP_ANCHOR_KEYS", 1, true)
    and factory:find("and not HasLateAnchorConfig() then return end", 1, true),
    "third-party ADDON_LOADED or group custom anchors cannot trigger late rebinding")

assert(headers:find("anchor:SetClampedToScreen(true)", 1, true),
    "live group root does not enable the native screen clamp")
assert(headers:find("ClampAnchorOnScreen(anchor, point, relativePoint, parent", 1, true),
    "live group root lost its explicit full-grid clamp")
assert(headers:find("anchor:SetPoint(point, parent, relativePoint", 1, true),
    "live group clamp replaced the configured custom anchor")
assert(headers:find("function GF.ResolveAnchorFrame(conf, owner)", 1, true)
    and headers:find("factory.AnchorWouldCreateCycle(owner, resolved)", 1, true),
    "live groups do not use the shared cycle-safe custom-anchor resolver")
assert(headers:find("MSUF_ScheduleLateAnchorReanchor", 1, true),
    "missing live group anchors do not request bounded late rebinding")

assert(editMode:find("f:SetClampedToScreen(true)", 1, true)
    and not editMode:find("f:SetClampedToScreen(false)", 1, true),
    "group Edit Mode root can leave the screen")
assert(preview:find("container:SetClampedToScreen(true)", 1, true),
    "group preview root can leave the screen")
assert(editMode:find("ResolveAnchorFrame(conf, container), relativePoint", 1, true),
    "group Edit Mode fallback ignores configured relativePoint")
assert(layout:find("PointXY(anchor, relativePoint)", 1, true),
    "group drag offset is measured from anchorPoint instead of relativePoint")
assert(picker:find("type(ov._isCandidateAllowed) == \"function\"", 1, true)
    and picker:find("self._isCandidateAllowed = nil", 1, true),
    "anchor picker does not reject or clear unsafe caller-specific targets")

io.write("frame_screen_clamp_contract_smoke: ok\n")
