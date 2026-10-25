-- Exercise the real page lifecycle and the real runtime writer behind its name sample.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { beforeOptions = function(world)
    if not arg[3] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        if path:match("/MSUF_Menu2_UnitText%.lua$") then
            local chunk = assert(loadfile(arg[3]))
            setfenv(chunk, self.env)
            return pcall(chunk, addon, namespace)
        end
        return load(self, path, addon, namespace)
    end
end })
local M, core = mw.M, mw.core
local paints = {}
local paint = core.UFText.PaintSampleName
core.UFText.PaintSampleName = function(frame, value)
    paint(frame, value)
    paints[#paints + 1] = { frame = frame, value = value }
end
assert(mw:Select("uf_player"))
local entry = assert(M.cache.uf_player)
local section = assert(entry.sections.text)
local disclosure = assert(section._msuf2CollapsibleEntry)
if disclosure._msuf2EnsureContent then disclosure._msuf2EnsureContent() end
disclosure.SetOpenImmediate(true)
M.Refresh()
assert(#paints > 0, "name example bypassed runtime text state (red baseline)")
local sample
for _, call in ipairs(paints) do
    if call.value == "Mapko" then sample = call.frame end
end
assert(sample and sample._msufTextRuntime, "page name has no runtime text state")
local conf = M.EnsureDB().player
local statuses = core.UFStatusRuntime
for _, case in ipairs({ { "PAREN", "Mapko (2)" }, { "BRACKET", "Mapko [2]" }, { "NONE", "Mapko 2" }, { "other", "Mapko (2)" } }) do
    conf.showRaidGroupInName, conf.raidGroupNameStyle = true, case[1]
    M.Refresh()
    assert(sample.nameText:GetText() == case[2], "name/group sample changed for " .. case[1])
    assert(sample.nameText:GetText() == "Mapko " .. statuses.RaidGroupText(case[1], 2), "group sample bypassed runtime formatting")
end
conf.showRaidGroupInName = false
M.Refresh()
assert(sample.nameText:GetText() == "Mapko", "disabled group suffix survived refresh")
assert(mw:Select("uf_target"))
assert(mw:Select("uf_player"))
M.Refresh()
assert(sample.nameText:GetText() == "Mapko", "cached page retained stale name sample")
print("PASS runtime name sample, group styles, refresh and page re-entry " .. flavor)
