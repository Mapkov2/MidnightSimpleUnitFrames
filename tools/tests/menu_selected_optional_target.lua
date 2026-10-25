-- Selected icon controls stay harmless when the selected status has no icon field.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home" })
local M, schema = mw.M, mw.M.ControlSchema
local selected
local bind = schema.Bind
schema.Bind = function(ctx, widget, spec)
    if arg[3] == "--without-optional-guard" and spec.write then spec.write.targetAvailable = nil end
    local result = bind(ctx, widget, spec)
    if spec.key == "iconStyle" and spec.scope == "group" then selected = spec end
    return result
end
M.SetMenuStateValue("gfStatusIconSelection", "roleIcon")
assert(mw:Select("gf_indicators"))
assert(selected and selected.write, "selected style is not a derived scalar")
local path = schema.ResolvePath(selected)
local owner, field = path:match("^([^.]+)%.([^.]+)$")
assert(owner and field, "style target is not a scope field")
local stale = { _msuf2SchemaResetTargets = { { spec = selected, root = owner, key = field } } }
for _, status in ipairs({ "levelText", "threatText" }) do
    M.SetMenuStateValue("gfStatusIconSelection", status)
    schema.ResetSection(stale, { field }, M.EnsureDB()[owner], {}, {}, false)
    M.InvalidatePage("gf_indicators")
    assert(mw:Select("gf_indicators"))
    assert(not M.cache.gf_indicators._msuf2BuildIncomplete, "text status prevented page build: " .. status)
end
print("PASS selected optional targets " .. flavor .. ": icon to text, stale reset and reopen")
