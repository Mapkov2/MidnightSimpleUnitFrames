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

-- Drive the real staged commit in a layout with two imported systems. Reload
-- is protected even outside combat, and the staged rows must survive a save error.
local copyStart = assert(text:find("local function CopyTable(", 1, true))
local copyEnd = assert(text:find("\nend", copyStart, true)) + 3
local commitStart = assert(text:find("local function CommitStaged(", 1, true))
local commitEnd = assert(text:find("local function OfferReload(", commitStart, true))
local commitChunk = assert(loadstring(text:sub(copyStart, copyEnd) .. "\n" .. text:sub(commitStart, commitEnd - 1)
    .. "\nreturn CommitStaged"))
local staged = { { [1] = 8 }, { [2] = 9 } }
local stageRoot = { ["Imported layout"] = { bags = staged[1], micromenu = staged[2] } }
local entries = { { settings = {} }, { settings = {} } }
local combat, saveError, stagedSaves, snapshots, reported = false, false, 0, 0, 0
local saveCallback
env.STAGED_KEYS = { [1] = "bags", [2] = "micromenu" }
env.StagedRows = function(id)
    local layout = stageRoot["Imported layout"]
    local key = env.STAGED_KEYS[id]
    return layout and layout[key], layout, key, stageRoot, "Imported layout"
end
env.SystemEntry = function(id) return entries[id] end
env.ActiveLayout = function() return original, { layoutName = "Imported layout" } end
env.ValidateLayoutCache = function() end
env.InCombat = function() return combat end
env.ApplySettingsTo = function(entry, rows)
    for key, value in pairs(rows) do entry.settings[key] = value end
end
env.SaveLayouts = function()
    assert(next(staged[1]) and next(staged[2]), "staged settings were discarded before save")
    if saveError then error("native save failed") end
    stagedSaves = stagedSaves + 1
    if saveCallback then saveCallback() end
    return true
end
env.StoreSnapshot = function() snapshots = snapshots + 1 end
env.ReloadUI = function() error("protected reload called from staged commit") end
env.geterrorhandler = function() return function(message)
    assert(message:find("native save failed", 1, true))
    reported = reported + 1
end end
env.MSUF = {}
local boundary = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
setfenv(boundary, env)
env.MSUF.ExportPublic = function() end
boundary("MSUF", env.MSUF)
setfenv(commitChunk, env)
local commit = commitChunk()
local target = "Imported layout"
combat = true
assert(not commit(target) and stagedSaves == 0 and snapshots == 0)
combat = false
assert(not commit("Other layout") and not next(entries[1].settings) and stagedSaves == 0)
local second = entries[2]
entries[2] = nil
assert(not commit(target) and not next(entries[1].settings) and stagedSaves == 0)
entries[2] = second
saveError = true
assert(not commit(target) and reported == 1 and staged[1][1] == 8 and staged[2][2] == 9 and snapshots == 0)
assert(not next(entries[1].settings) and not next(entries[2].settings), "failed save leaked into the cached layout")
saveError = false
assert(commit(target) and stagedSaves == 1 and snapshots == 2)
assert(entries[1].settings[1] == 8 and entries[2].settings[2] == 9)
assert(not next(staged[1]) and not next(staged[2]))
assert(not next(stageRoot), "committed layout left an empty staged entry")
assert(commit(target) and stagedSaves == 1 and snapshots == 2, "empty retry saved the layout twice")

staged[1][1], staged[1][3], staged[2][2] = 20, 21, 22
stageRoot[target] = { bags = staged[1], micromenu = staged[2] }
local imported = { [1] = { [1] = "20" } }
saveError = true
assert(not commit(target, imported) and entries[1].settings[1] == 8 and staged[1][1] == 20)
assert(stagedSaves == 1 and reported == 2 and snapshots == 2)
saveError = false
saveCallback = function()
    staged[1][1] = 23
end
assert(commit(target, imported) and stagedSaves == 2 and snapshots == 3)
assert(entries[1].settings[1] == 20 and entries[1].settings[3] == nil and entries[2].settings[2] == 9,
    "import persisted an unrelated pending setting")
assert(staged[1][1] == 23 and staged[1][3] == 21 and staged[2][2] == 22,
    "import discarded an unrelated or reentrant pending setting")
saveCallback = nil
assert(commit(target, imported) and stagedSaves == 2, "obsolete import retried with a newer staged value")
assert(commit(target) and stagedSaves == 3 and snapshots == 5 and not next(stageRoot),
    "unrelated staged settings stopped being independently committable")
-- A synchronous API import can request native layout apply during combat.
-- The deferred callback must keep import mode and stay bound to that profile.
local applyStart = assert(text:find("local snapshotRetry,", 1, true))
local applyEnd = assert(text:find("local function UIPanel(", applyStart, true))
local applyChunk = assert(loadstring(text:sub(applyStart, applyEnd - 1) .. "\nreturn ApplyProfileSnapshot"))
local nativeEntry = { system = 1, anchorInfo = {}, settings = {} }
local layout = { layoutName = target, systems = { nativeEntry } }
local settings = { [4] = 24 }
local general = { blizzardEditModeSnapshot = { bags = { point = "CENTER", settings = settings } } }
local profile = {}
local eventFrame, importCommits, importSaves = nil, 0, 0
env.SNAPSHOT_KEYS, env.IS_FOREVER = { [1] = "bags" }, false
env.General = function() return general end
env.OwnSaveInFlight = function() return true end
env.ActiveLayout = function() return original, layout end
env.SplitStaged = function(_, _, values) assert(values == settings) end
env.SaveLayouts = function() importSaves = importSaves + 1 return true end
env.ApplyAnchorVisual = function() end
env.ApplyVisual = function() end
env.CommitStaged = function(name, scope)
    assert(not combat and name == target and scope[1] == settings)
    importCommits = importCommits + 1
    return true
end
env.MSUF.ProfileRuntime = {
    Identity = function() return profile end,
    IsCurrentIdentity = function(identity) return identity == profile end,
}
env.CreateFrame = function()
    eventFrame = {
        SetScript = function(self, _, handler) self.fire = handler end,
        RegisterEvent = function(self, event) self.event = event end,
        UnregisterAllEvents = function(self) self.event = nil end,
    }
    return eventFrame
end
setfenv(applyChunk, env)
local applySnapshot = applyChunk()
combat = true
assert(not applySnapshot(true) and eventFrame.event == "PLAYER_REGEN_ENABLED")
assert(importSaves == 0 and importCommits == 0)
combat = false
eventFrame:fire()
assert(importSaves == 1 and importCommits == 1 and not eventFrame.event, "combat retry lost import mode")
combat = true
assert(not applySnapshot(true))
profile = {}
combat = false
eventFrame:fire()
assert(importSaves == 1 and importCommits == 1, "combat retry applied to a changed profile")
combat = true
assert(not applySnapshot())
combat = false
eventFrame:fire()
assert(importSaves == 2 and importCommits == 1, "restore retried as an import")
print("PASS editmode_layout_cache_smoke")
