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

assert(factory:find("local function EnableScreenClamp(frame)", 1, true),
    "unit-frame screen clamp helper is missing")
assert(factory:find("layout:SetClampedToScreen(true)", 1, true),
    "unit-frame root does not enable Blizzard's physical screen clamp")
assert(factory:find("EnableScreenClamp(frame)\n  UF.AttachFrame", 1, true),
    "unit-frame clamp is not installed on the spawn cold path")
assert(factory:find("layout:SetPoint(point, anchor, relativePoint, x, y)", 1, true),
    "unit-frame clamp replaced the configured CDM/custom anchor")

assert(headers:find("anchor:SetClampedToScreen(true)", 1, true),
    "live group root does not enable the native screen clamp")
assert(headers:find("ClampAnchorOnScreen(anchor, point, relativePoint, parent", 1, true),
    "live group root lost its explicit full-grid clamp")
assert(headers:find("anchor:SetPoint(point, parent, relativePoint", 1, true),
    "live group clamp replaced the configured custom anchor")

assert(editMode:find("f:SetClampedToScreen(true)", 1, true)
    and not editMode:find("f:SetClampedToScreen(false)", 1, true),
    "group Edit Mode root can leave the screen")
assert(preview:find("container:SetClampedToScreen(true)", 1, true),
    "group preview root can leave the screen")

io.write("frame_screen_clamp_contract_smoke: ok\n")
