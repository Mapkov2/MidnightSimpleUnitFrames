-- Real cache/save/event owners, isolated from movers and their native frames.
local root = assert(arg[1]):gsub("\\", "/")
local measure = arg[2] == "measure"
local w = dofile(root .. "/tools/tests/client_world.lua").New(root, "Mainline")
local env, reads, now, active, saves = w.env, 0, 0, 3, 0
local nativeX
local source = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua", "rb"))
local text = source:read("*a"):gsub("\r\n", "\n")
source:close()
local first = assert(text:find("local cachedLayoutInfo", 1, true))
local last = assert(text:find("local function ActiveLayout()", first, true))
env.GetTime = function() return now end
env.InCombat = function() return false end
local api = {}
function api.GetLayouts()
    reads = reads + 1
    local info = { activeLayout = active, layouts = {} }
    for i = 1, 5 do
        local layout = { systems = {} }
        info.layouts[i] = layout
        for j = 1, 100 do layout.systems[j] = { system = j, anchorInfo = { offsetX = nativeX or j, offsetY = i } } end
    end
    return info
end
function api.SaveLayouts(info) saves = saves + 1 end
env.Blizzard = function() return api end
env.EditModeManagerFrame = { layoutInfo = { activeLayout = active, layouts = { "preset1", "preset2" } } }
local activeEnd = assert(text:find("local function SystemEntry(", last, true))
local sessionStart = assert(text:find("local function SessionChanged(enabled)", 1, true))
local sessionEnd = assert(text:find("local Add =", sessionStart, true))
env.Enabled = function() return true end
env.EditModeRuleBlocked = function() return false end
env.OfferReload = function() end
env.SystemFrame = function() end
env.systemEnum = {}
env.PresetCount = function() return 2 end
local chunk = assert(loadstring(text:sub(first, activeEnd - 1) .. text:sub(sessionStart, sessionEnd - 1)
    .. "\nreturn LayoutInfo, ValidateLayoutCache, OnLayoutsUpdated, SaveLayouts, InvalidateLayoutCache, SessionChanged"))
setfenv(chunk, env)
local Info, Validate, Updated, Save, Invalidate, Session = chunk()
local original = assert(Info())
reads = 0
Session(true)
print("A2 cached layout session-entry reads=" .. reads)
assert(reads == 1, "session entry must recover from a lost own-save echo")
original = Info()
for pass = 1, 2 do
reads = 0
collectgarbage("collect")
collectgarbage("stop")
local kb, vm = collectgarbage("count"), 0
debug.sethook(function() vm = vm + 1 end, "", 1)
for i = 1, 18 do Validate() assert(Info() == original) end
debug.sethook()
local delta = collectgarbage("count") - kb
collectgarbage("restart")
print(string.format("A2 layout-validation x18 vm=%d kb=%.3f native=%d", vm, delta, reads))
if not measure then assert(reads == 0, "unchanged layouts fetched native tables again") end
end
active = 4
env.EditModeManagerFrame.layoutInfo.activeLayout = active
Validate()
assert(Info().activeLayout == 4 and Info() ~= original, "silent layout switch was missed")
original = Info()
assert(Save(api, original) and saves == 1)
original.layouts[2].systems[1].anchorInfo.offsetX = 888
active = 3 -- the native read is one behind until the save echo
env.EditModeManagerFrame.layoutInfo.activeLayout = 3
local before = reads
Validate()
assert(Info() == original and reads == before, "own save lost the in-flight table")
active = 4
env.EditModeManagerFrame.layoutInfo.activeLayout = 4
Updated(nil, "EDIT_MODE_LAYOUTS_UPDATED")
assert(Info() == original and Info().layouts[2].systems[1].anchorInfo.offsetX == 888)
Updated(nil, "EDIT_MODE_LAYOUTS_UPDATED")
assert(Info() ~= original, "foreign save failed to invalidate")
original = Info()
assert(Save(api, original))
nativeX = 9
Updated(nil, "EDIT_MODE_LAYOUTS_UPDATED") -- a foreign update consumed the stale own-save token
assert(Info() == original)
Session(true)
assert(Info().layouts[1].systems[1].anchorInfo.offsetX == 9, "entry retained a same-index foreign layout")
env.EditModeManagerFrame = nil
active = 5
Validate()
assert(Info().activeLayout == 5, "missing manager fallback lost active layout")
Invalidate()
assert(Info().activeLayout == 5)
print("PASS editmode_layout_cache_smoke")
