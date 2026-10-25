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
-- Original ce4767d34 renderer, warmed real TOC/MenuWorld; allocations use the
-- minimum of four 50-call windows (a 5-call window caught one-off table growth
-- from unrelated load-time strings and tables, not per-refresh work).
-- Refresh VM is +1 since c50ebdbe2: the PixelLayoutRegion "ready" field check
-- on a cold region (warm visits drop 34011 -> 16011 VM per 1000).
local pins = {
    Mainline = {
        ["party.refresh"] = { 63888, 2541, 34.077246 },
        ["party.animate"] = { 37787, 1335, 23.188281 },
        ["raid.refresh"] = { 64665, 2564, 34.653809 },
        ["raid.animate"] = { 38019, 1334, 23.416719 },
    },
    Vanilla = {
        ["party.refresh"] = { 66266, 2666, 34.260684 },
        ["party.animate"] = { 38757, 1382, 23.277969 },
        ["raid.refresh"] = { 67011, 2689, 34.837246 },
        ["raid.animate"] = { 38989, 1381, 23.573418 },
    },
    TBC = {
        ["party.refresh"] = { 67034, 2738, 34.261934 },
        ["party.animate"] = { 38757, 1382, 23.279219 },
        ["raid.refresh"] = { 67779, 2761, 34.838496 },
        ["raid.animate"] = { 38989, 1381, 23.510469 },
    },
    Mists = {
        ["party.refresh"] = { 66124, 2687, 34.261934 },
        ["party.animate"] = { 38350, 1365, 23.279219 },
        ["raid.refresh"] = { 66898, 2710, 34.838496 },
        ["raid.animate"] = { 38582, 1364, 23.510469 },
    },
    Forever = {
        ["party.refresh"] = { 64345, 2536, 34.074434 },
        ["party.animate"] = { 38206, 1352, 23.185469 },
        ["raid.refresh"] = { 65093, 2559, 34.650996 },
        ["raid.animate"] = { 38438, 1351, 23.416719 },
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
    for _ = 1, 4 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 50 do fn() end
        allocations = math.min(allocations, (collectgarbage("count") - before) / 50)
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
