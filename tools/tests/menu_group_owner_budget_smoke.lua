-- Real group composition after the state-owner split. Optional baseline Render path is read-only.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { beforeOptions = function(world)
    if not arg[3] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        if path:match("/MSUF_Menu2_GroupPreview_Render%.lua$") then
            local chunk = assert(loadfile(arg[3]))
            setfenv(chunk, self.env)
            return pcall(chunk, addon, namespace)
        end
        return load(self, path, addon, namespace)
    end
end })
local M, env, core = mw.M, mw.env, mw.core
core.GF.EnsureDB()
-- Original ce4767d34 renderer, warmed real TOC/MenuWorld; allocations use the minimum of two runs.
local pins = {
    Mainline = {
        ["party.refresh"] = { 63887, 2541, 34.591211 },
        ["party.animate"] = { 37787, 1335, 23.717188 },
        ["raid.refresh"] = { 64664, 2564, 35.294336 },
        ["raid.animate"] = { 38019, 1334, 24.14043 },
    },
    Vanilla = {
        ["party.refresh"] = { 66265, 2666, 34.778711 },
        ["party.animate"] = { 38757, 1382, 23.810938 },
        ["raid.refresh"] = { 67010, 2689, 35.481836 },
        ["raid.animate"] = { 38989, 1381, 24.23418 },
    },
    TBC = {
        ["party.refresh"] = { 67033, 2738, 34.778711 },
        ["party.animate"] = { 38757, 1382, 23.810938 },
        ["raid.refresh"] = { 67778, 2761, 35.481836 },
        ["raid.animate"] = { 38989, 1381, 24.23418 },
    },
    Mists = {
        ["party.refresh"] = { 66123, 2687, 34.778711 },
        ["party.animate"] = { 38350, 1365, 23.810938 },
        ["raid.refresh"] = { 66897, 2710, 35.481836 },
        ["raid.animate"] = { 38582, 1364, 24.23418 },
    },
    Forever = {
        ["party.refresh"] = { 64344, 2536, 34.603711 },
        ["party.animate"] = { 38206, 1352, 23.729688 },
        ["raid.refresh"] = { 65092, 2559, 35.306836 },
        ["raid.animate"] = { 38438, 1351, 23.510938 },
    },
}
local function Measure(fn)
    for _ = 1, 8 do fn() end
    local instructions, native = 0, 0
    debug.sethook(function() instructions = instructions + 1 end, "", 1)
    fn()
    debug.sethook()
    debug.sethook(function(event)
        if event == "call" and debug.getinfo(2, "S").what == "C" then native = native + 1 end
    end, "c")
    fn()
    debug.sethook()
    local allocations = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 5 do fn() end
        allocations = math.min(allocations, (collectgarbage("count") - before) / 5)
        collectgarbage("restart")
    end
    return instructions, native, allocations
end
for _, scope in ipairs({ "party", "raid" }) do
    M.gfScope = scope
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box:Show()
    box._stage:SetSize(600, 220)
    box._animationEnabled, box._animationElapsed = true, 0.25
    box:Refresh("SETTINGS")
    assert(box._msufGFScene and box._msufGFScene.mock._cell, "group scene was not rendered")
    local repaint = function() box:Refresh("SETTINGS") end
    local animate = function() assert(box:RefreshAnimation(), "animation bypassed the composed scene") end
    for index, fn in ipairs({ repaint, animate }) do
        local vm, native, kb = Measure(fn)
        local key = scope .. (index == 1 and ".refresh" or ".animate")
        local pin = pins[flavor] and pins[flavor][key]
        if pin and not arg[3] then
            assert(vm <= pin[1] and native <= pin[2], key .. ": split added VM/native work")
            assert(kb <= pin[3] + 0.05, key .. ": split added warm allocations")
        end
        print(("BUDGET %s %s %d %d %.6f"):format(flavor, key, vm, native, kb))
    end
    box:Hide()
end
print("PASS real group owner refresh/animation budget " .. flavor)
