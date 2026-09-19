local root = (...) or "."
local path = root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Reason: every assertion below is about what the global font fanout does, so
-- the slice is that one function and nothing else. It used to end at the doc
-- comment of the next function, which made editing that comment a red smoke.
local body = Slice.Function(source, "function A3.ApplyFontsFromGlobal", path)
local executable = body:gsub("%-%-[^\r\n]*", "")
Check(body:find('_QueueDeferredAuraRuntime%(scope or "shared", reason or "AURAS3_FONT_VISUALS", true%)') ~= nil,
    "global aura font fanout no longer defers visual work during combat")
Check(body:find("A3%._nativeVisualGen%s*=") ~= nil,
    "global aura font fanout no longer invalidates native visual state")
Check(body:find("return A3%.RequestScope%(scope, reason or \"AURAS3_FONT_VISUALS\"%)") ~= nil,
    "scoped aura font updates no longer use RequestScope")
Check(body:find("RuntimeFrame%(runtimeUnit%)") ~= nil,
    "global aura font fanout does not target existing runtime frames directly")
Check(body:find('RefreshRuntimeUnit%("player"%)') ~= nil
        and body:find('RefreshRuntimeUnit%("target"%)') ~= nil
        and body:find('RefreshRuntimeUnit%("focus"%)') ~= nil
        and body:find("for i = 1, 5 do RefreshRuntimeUnit%(\"boss\" %.%. i%) end") ~= nil
        and body:find("for i = 1, 3 do RefreshRuntimeUnit%(\"arena\" %.%. i%) end") ~= nil,
    "global aura font fanout no longer covers the bounded standalone unit families")
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
Check(body:find('A3%._NotifyAuraColdpathPreview%(visualReason, "shared"%)') ~= nil,
    "global aura font fanout no longer refreshes the coldpath preview")
Check(body:find("A3%.RefreshEditPreview%(%)") ~= nil,
    "global aura font fanout no longer refreshes the Edit Mode preview")

print("aura_font_fanout_smoke: ok")
