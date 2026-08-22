local root = (...) or "."
local path = root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local bodyStart = source:find("function A3.ApplyFontsFromGlobal(scope, reason)", 1, true)
local bodyEnd = bodyStart and source:find("\n--- Narrow ClassPower", bodyStart, true) or nil
Check(bodyStart ~= nil and bodyEnd ~= nil, "ApplyFontsFromGlobal body not found")
local body = source:sub(bodyStart, bodyEnd - 1)
local executable = body:gsub("%-%-[^\r\n]*", "")
Check(body:find("RuntimeFrame%(runtimeUnit%)") ~= nil,
    "global aura font fanout does not target existing runtime frames directly")
Check(body:find("gf%.ForEachFrame") ~= nil,
    "global aura font fanout does not cover existing group frames")
Check(body:find("A3%.RenderFrame%(frame, visualReason%)") ~= nil,
    "global aura font fanout does not use the native aura renderer")
Check(executable:find("A3%.RefreshAll", 1, false) == nil,
    "global aura font fanout still rebuilds the complete aura/runtime route")
Check(executable:find("RefreshVisuals", 1, true) == nil,
    "global aura font fanout still enters GroupFrame structural refresh")
Check(executable:find("ApplyElementToFrame", 1, true) == nil,
    "global aura font fanout still rebuilds UnitFrame element routes")
Check(body:find("A3%.RefreshEditPreview%(%)") ~= nil,
    "global aura font fanout no longer refreshes the Edit Mode preview")

print("aura_font_fanout_smoke: ok")
