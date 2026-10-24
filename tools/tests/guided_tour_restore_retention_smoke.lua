-- Saved tour lifecycle: active undo survives reload; abandoned snapshots expire.
local root = assert(arg[1]):gsub("/$", "")
local now = 2000000000
local function Boot(saved)
    local env = setmetatable({ MSUF_GlobalDB = { global = { guidedTour6 = saved } }, time = function() return now end }, { __index = _G })
    env._G = env
    local core = { ExportPublic = function() end, FirstLoad6 = {} }
    function core.FirstLoad6.ResolveLiveGlobalDB() return env.MSUF_GlobalDB, true end
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_GuidedTour.lua"))
    setfenv(chunk, env)("MidnightSimpleUnitFrames", core)
    return core.GuidedTour6, env
end
local tour, env = Boot()
local snapshot = { general = { slashMenuScale = 0.8 }, player = { enabled = false } }
assert(tour:Start("Old profile", "menu_basics", snapshot))
assert(tour:GetRestorePoint() == snapshot and tour:MarkRestorePointUsed(true))
assert(tour:MarkRestorePointUsed(false) and tour:GetRestorePoint() == snapshot, "active undo lost its restore point")
local saved = env.MSUF_GlobalDB.global.guidedTour6
local reloaded = Boot(saved)
assert(reloaded:Resume() and reloaded:GetRestorePoint() == snapshot, "fresh active tour did not survive reload")
assert(reloaded:MarkRestorePointUsed(true))
assert(reloaded:Dismiss())
assert(reloaded:GetRestorePoint() == nil, "dismissed tour retained the full profile")
assert(saved.restorePointCreatedAt == nil and saved.restorePointUsedAt == nil, "dismiss retained snapshot metadata")
for _, status in ipairs({ "inactive", "dismissed", "completed", "active" }) do
    local legacy = { revision = 1, status = status, restorePoint = snapshot,
        restorePointCreatedAt = now - 31 * 86400, restorePointUsedAt = now - 30 * 86400,
        currentStageId = "edit_mode", preferences = { keep = false }, cursors = { old = { controlIndex = 2 } } }
    local loaded = Boot(legacy)
    assert(loaded:GetRestorePoint() == nil, status .. " stale snapshot survived load")
    assert(loaded:GetState().preferences.keep == false and loaded:GetCursor("old").controlIndex == 2,
        "snapshot cleanup changed old tour progress")
end
local malformed = Boot({ revision = 1, status = "active", restorePoint = snapshot })
assert(malformed:GetRestorePoint() == nil, "undated legacy snapshot has unbounded retention")
local late, lateEnv = Boot()
lateEnv.MSUF_GlobalDB = { global = { guidedTour6 = { revision = 1, status = "active",
    restorePoint = snapshot, restorePointCreatedAt = now - 31 * 86400 } } }
assert(late:GetRestorePoint() == nil, "late SavedVariables bind retained a stale snapshot")
print("guided_tour_restore_retention_smoke: active undo/reload retained; dismiss and stale load released snapshots")
