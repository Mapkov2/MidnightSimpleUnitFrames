_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local path = RuntimeManifest.ResolveCompanionRoot() .. "/Assistant/MSUF_AssistantHistory.lua"

local frameCreates = 0
local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = { general = {} }
_G.CreateFrame = function()
    frameCreates = frameCreates + 1
    return {}
end
_G.time = function() return 123 end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local A = assert(MSUF.Assistant, "assistant namespace missing")
assert(frameCreates == 0, "assistant history must not create a login event frame")
assert(_G.MSUF_DB.assistant == nil, "assistant history must not mutate profile DB while loading")

local added = A.AddLoginGreeting("Tester", 12)
assert(added == true, "lazy assistant greeting was not added")
assert(#A.GetHistory() == 1, "lazy assistant greeting history entry missing")
assert(A.AddLoginGreeting("Tester", 12) == false, "assistant greeting must remain once per session")

io.write("assistant_history_lazy_smoke: ok\n")
