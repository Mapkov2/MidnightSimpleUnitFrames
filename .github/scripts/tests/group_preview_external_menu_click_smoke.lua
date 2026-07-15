local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local handles = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
local native = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
local specs = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Specs.lua")

assert(handles:find('externalHandle._openSettingsOnClick = true', 1, true),
    "external preview handle is not marked for direct settings activation")
assert(handles:find('button == "LeftButton"', 1, true)
    and handles:find('handle._suppressSettingsOnRelease ~= true', 1, true)
    and handles:find('handle._lastDragX == nil and handle._lastDragY == nil', 1, true)
    and handles:find('if openSettingsOnRelease then OpenHandleSettings(handle) end', 1, true),
    "external left-click must open settings only when the handle was not moved or used to pan")
assert(handles:find('if self._openSettingsOnClick == true then', 1, true)
    and handles:find('OpenHandleSettings(self)', 1, true),
    "external right-click direct settings activation is missing")
assert(handles:find('externalHandle:SetHitRectInsets(0, 0, -14, 0)', 1, true),
    "blue EXTERNAL label is outside the external handle hit rectangle")
assert(specs:find('externals=gf_auras', 1, true),
    "external handle is not mapped to the Group Auras page")
assert(native:find('elseif sectionKey == "externals" then', 1, true)
    and native:find('lane = "externals"', 1, true),
    "external settings route does not select the external-defensives lane")

print("group preview external menu click smoke: ok")
