-- Config compilation is a cold boundary: casts read a stable per-unit record.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local ns = { ExportPublic = function(name, value) _G[name] = value end }
_G.MSUF = ns
_G.MSUF_NS = ns
_G.MSUF_EnsureDB = function() end
_G.MSUF_DB = { general = { showTargetCastTime = false, enableTargetCastbar = false }, target = { enabled = true } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MSUF", ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_PublicAPI.lua"),
    "castbars need namespace providers and one public compatibility boundary")("MSUF", ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Backend.lua"))("MSUF", ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarConfig.lua"))("MSUF", ns)
local config = ns.Castbars.Config
assert(config.DB.general == nil, "profile must not be read at file load")
config.Compile()
local target = config.records.target
assert(target.timeEnabled == false and target.backend == "HIDE", "legacy backend/time settings must compile")
local previous = config.revisions.time
_G.MSUF_DB.general.showTargetCastTime = true
_G.MSUF_DB.general.castbarTargetBackend = "MSUF"
assert(target.timeEnabled == false and target.backend == "HIDE", "the current revision must stay stable")
config.Compile("time")
assert(config.records.target == target, "records must be reused")
assert(target.timeEnabled == true and target.backend == "MSUF", "apply must compile edited settings")
assert(config.revisions.time == previous + 1, "the revision must advance once")
assert(_G.MSUF_DB.general.enableTargetCastbar == false, "pure compilation must not repair legacy flags")
ns.Castbars.Backend.Sync(config.Source().general)
assert(_G.MSUF_DB.general.enableTargetCastbar == true, "the explicit backend sync must keep legacy flags")
_G.MSUF_DB = { general = { showTargetCastTime = false }, target = { enabled = false } }
config.Compile()
-- Backend ownership matches the pre-refactor driver even when its unit frame is off.
assert(target.timeEnabled == false and target.enabled == true, "profile replacement must rebuild the backend-owned record")
local frames = ns.Castbars.Frames
local frame, preview = {}, {}
frames.Register("target", nil, frame)
frames.Register("targetPreview", nil, preview)
assert(frames.Get("target") == frame and frames.Get("targetPreview") == preview, "real/preview identity must be separate")
assert(frames.Get("boss", 1) == nil, "unbuilt pools have no frame")
print("castbar_config_snapshot_smoke: ok")
