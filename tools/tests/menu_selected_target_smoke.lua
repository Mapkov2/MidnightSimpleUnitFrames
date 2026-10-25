-- A bound scalar follows its selected declaration at input time, including refusal.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local profile = { player = {}, target = {} }
local calls, after = {}, 0
local M = { Widgets = {}, EnsureDB = function() return profile end }
local ns = { MSUF2 = M, CPBuilders = { ExtraAuraDefaults = {} } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua"))("Options", ns)
local S = M.ControlSchema
local selected = { key = "left", reason = "left-reason" }
local spec = { id = "selected-scalar", kind = "toggle", scope = "player", setting = S.Family({ "player.left", "player.right" }),
    write = { selected = { get = function() return selected end, key = "key", reason = "reason" }, boolean = true,
        call = function(unit, key, value, reason) profile[unit][key] = value; calls[#calls + 1] = reason end,
        after = function() after = after + 1 end } }
local set = S.Setter(spec)
set(true)
selected = { key = "right", reason = "right-reason" }
set(false)
assert(profile.player.left == true and profile.player.right == false, "selected target was captured at build time")
assert(calls[1] == "left-reason" and calls[2] == "right-reason", "selected reason was captured at build time")
selected = {}
set(true)
assert(#calls == 2 and after == 3, "missing selected target changed the old no-write/refresh policy")
selected = { key = "escaped", reason = "escape" }
assert(not pcall(set, true), "selected target escaped its declaration")
assert(profile.player.escaped == nil and profile.target.left == nil, "foreign field was written")
print("PASS selected scalar target, reason, absent target and declared-family refusal")
