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
-- Keep the historical measured scene explicit. Default-All and preview-only
-- out-of-context indicators have separate layer/status behavior coverage.
M.gfStatusPreviewMode = "current"
for _, scope in ipairs({ "party", "raid" }) do
    local conf = core.GF.GetConf(scope)
    local pvpSpec = core.GF.CompileSpec(scope).status.pvp
    conf.pvpIcon = pvpSpec.enabled == true
        and (flavor ~= "Forever" or core.UF.PVPIndicatorContextActive())
    core.GF.InvalidateCompiledSpecs(scope)
end
-- Original ce4767d34 renderer, warmed real TOC/MenuWorld; allocations use the
-- minimum of four 50-call windows (a 5-call window caught one-off table growth
-- from unrelated load-time strings and tables, not per-refresh work).
-- Refresh VM is +1 since c50ebdbe2: the PixelLayoutRegion "ready" field check
-- on a cold region (warm visits drop 34011 -> 16011 VM per 1000).
-- 27a05e03fb cancels stale queued portrait work in SceneApply and Disable.
-- Each cancellation runs twice per refresh and once per animation: +4/+2 VM.
-- Replaying only the portrait source at c14c585ad restores every old client pin;
-- native calls and paired allocations are unchanged. portrait_model_refresh_smoke
-- verifies both cancellations, including pending work before each transition.
local pins = {
    Mainline = {
        ["party.refresh"] = { 63892, 2541, 34.077246 },
        ["party.animate"] = { 37789, 1335, 23.188281 },
        ["raid.refresh"] = { 64669, 2564, 34.653809 },
        ["raid.animate"] = { 38021, 1334, 23.416719 },
    },
    Vanilla = {
        ["party.refresh"] = { 66270, 2666, 34.260684 },
        ["party.animate"] = { 38759, 1382, 23.277969 },
        ["raid.refresh"] = { 67015, 2689, 34.837246 },
        ["raid.animate"] = { 38991, 1381, 23.573418 },
    },
    TBC = {
        ["party.refresh"] = { 67038, 2738, 34.261934 },
        ["party.animate"] = { 38759, 1382, 23.279219 },
        ["raid.refresh"] = { 67783, 2761, 34.838496 },
        ["raid.animate"] = { 38991, 1381, 23.510469 },
    },
    Mists = {
        ["party.refresh"] = { 66128, 2687, 34.261934 },
        ["party.animate"] = { 38352, 1365, 23.279219 },
        ["raid.refresh"] = { 66902, 2710, 34.838496 },
        ["raid.animate"] = { 38584, 1364, 23.510469 },
    },
    -- The Forever editor owns one more status handle. Compared with Beta 2,
    -- refresh adds 526 VM instructions and 21 C calls, animation adds 413 and 17.
    -- Paired warm allocations match Beta 2, and their ceilings stay unchanged.
    Forever = {
        ["party.refresh"] = { 64758, 2545, 34.074434 },
        ["party.animate"] = { 38602, 1366, 23.185469 },
        ["raid.refresh"] = { 65500, 2568, 34.650996 },
        ["raid.animate"] = { 38831, 1365, 23.416719 },
    },
}
-- The widget fixture stores arguments to these native C setters in newly
-- allocated Lua tables. Count their exact allocations separately while GC is
-- stopped. Keep the real setters and their complete state transitions.
local FIXTURE_SETTERS = { "SetPoint", "SetColorTexture", "SetVertexColor", "SetTexCoord",
    "SetBackdropColor", "SetBackdropBorderColor", "SetStatusBarColor", "SetTextColor", "SetShadowColor" }
-- Same scene on stock Lua 5.1, tagged Beta 6 and the release candidate.
-- Retain the original 32-bit raw caps in pins. The independently checked
-- adjusted caps cover everything outside these nine C stand-ins, including
-- the menu's own points, colors, strings, layout and model records.
local wordBytes = string.dump(function() end):byte(9)
assert(wordBytes == 4 or wordBytes == 8, "unknown Lua 5.1 size_t width")
local wide = wordBytes == 8
local raw64 = (flavor == "Mainline" or flavor == "Forever")
    and { ["party.refresh"] = 45.18, ["party.animate"] = 30.79, ["raid.refresh"] = 45.96, ["raid.animate"] = 31.16 }
    or  { ["party.refresh"] = 45.43, ["party.animate"] = 30.92, ["raid.refresh"] = 46.21, ["raid.animate"] = 31.29 }
local otherCaps = wide and { 1.58, 0.67 } or { 1.17, 0.51 }
local function TrackFixtureStorage(methods)
    local total, originals, allowed, active = 0, {}, {}, false
    for _, name in ipairs(FIXTURE_SETTERS) do
        local original = methods[name]
        assert(debug.getinfo(original, "S").source:gsub("\\", "/"):match("/msuf_test_stubs%.lua$"),
            "unrecognized widget setter in the allocation sample: " .. name)
        originals[name] = original
        allowed[original] = true
        methods[name] = function(...)
            assert(not active, "nested fixture setter would double count")
            local before = collectgarbage("count")
            active = true
            original(...)
            active = false
            total = total + (collectgarbage("count") - before)
        end
    end
    local function validate(fn)
        -- Audit one identical paint before measuring it. A fixture edit that
        -- calls an addon script must never silently exempt the script's heap.
        debug.sethook(function()
            if active then
                local info = debug.getinfo(2, "Sf")
                assert(info.what == "C" or allowed[info.func], "widget setter called unmeasured Lua")
            end
        end, "c")
        fn()
        debug.sethook()
    end
    return function() return total end, function()
        for name, original in pairs(originals) do methods[name] = original end
    end, validate
end
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
    local allocations, totalKB = math.huge, math.huge
    local storage, restoreMethods, validate = TrackFixtureStorage(mw.world.widgets.Methods)
    validate(fn)
    for _ = 1, 4 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before, fixtureBefore = collectgarbage("count"), storage()
        for _ = 1, 50 do fn() end
        local raw = collectgarbage("count") - before
        local addon = (raw - (storage() - fixtureBefore)) / 50
        allocations, totalKB = math.min(allocations, addon), math.min(totalKB, raw / 50)
        collectgarbage("restart")
    end
    restoreMethods()
    return instructions, native, allocations, totalKB
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
        local vm, native, kb, totalKB = Measure(fn)
        local key = scope .. (index == 1 and ".refresh" or ".animate")
        local pin = pins[flavor] and pins[flavor][key]
        if pin and not arg[3] then
            assert(vm <= pin[1] and native <= pin[2], key .. ": split added VM/native work")
            assert(totalKB <= (wide and raw64[key] or pin[3]) + 0.05, key .. ": total warm allocations increased")
            assert(kb <= otherCaps[index], key .. ": warm allocations outside native widget storage increased")
        end
        print(("BUDGET %s %s %d %d %.6f; raw %.6f KB"):format(flavor, key, vm, native, kb, totalKB))
    end
    box:Hide()
end
print("PASS real group owner refresh/animation budget " .. flavor)
