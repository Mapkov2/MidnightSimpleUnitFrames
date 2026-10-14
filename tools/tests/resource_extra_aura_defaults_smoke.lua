-- Exact pre-schema VM/native/allocation budgets on the real extra-aura owners.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measureOnly = arg[2] == "--measure"
local source = arg[3]
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
-- 100 calls, including the unchanged loop/hook boundary; measured before the default seam.
local BUDGETS = {
    ["missing/callback"] = { 49708, 4001, 289.04 },
    ["missing/refresh"] = { 143408, 9601, 802.91 },
    ["missing/haste"] = { 3908, 1, 0 },
    ["invalid/callback"] = { 49708, 4001, 289.04 },
    ["invalid/refresh"] = { 143408, 9601, 802.91 },
    ["invalid/haste"] = { 3908, 1, 0 },
    ["normal/callback"] = { 49708, 4001, 289.04 },
    ["normal/refresh"] = { 142808, 9601, 802.91 },
    ["normal/haste"] = { 3908, 1, 0 },
}
local function Noop() end
local function Count(operation)
    for i = 1, 40 do operation() end
    local vm, native = 0, 0
    debug.sethook(function() vm = vm + 1 end, "", 1)
    for i = 1, 100 do operation() end
    debug.sethook()
    debug.sethook(function(event)
        if event == "call" and debug.getinfo(2, "S").what == "C" then native = native + 1 end
    end, "c")
    for i = 1, 100 do operation() end
    debug.sethook()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for i = 1, 100 do operation() end
    local bytes = (collectgarbage("count") - before) * 1024 / 100
    collectgarbage("restart")
    return vm, native, bytes
end
for _, case in ipairs({ "missing", "invalid", "normal" }) do
    local world = World.New(root, "Mainline")
    if source then
        local load = world.LoadFile
        world.LoadFile = function(self, path, addon, namespace)
            if path:match("MSUF_CP_ExtraAuras%.lua$") then path = source end
            return load(self, path, addon, namespace)
        end
    end
    world:Boot()
    assert(not world:FirstFailure(), "real core boot failed")
    local env, core, callbacks = world.env, world.core, {}
    env.InCombatLockdown = function() return false end
    env.C_Secrets = { ShouldAurasBeSecret = function() return false end }
    env.C_Spell = { DoesSpellExist = function() return true end }
    env.C_StringUtil = { CreateNumericRuleFormatter = function() return { SetBreakpoints = Noop } end }
    env.C_CurveUtil = { CreateColorCurve = function()
        return { ClearPoints = Noop, SetType = Noop, AddPoint = Noop }
    end }
    env.CreateColor = function() return { SetRGBA = Noop } end
    env.UnitSpellHaste = function() return 0 end
    world.widgets.Methods.SetDurationBar = Noop
    world.widgets.Methods.SetDurationText = Noop
    env.MSUF_Auras3 = { CreateClassPowerAuraSensor = function(host, name, spells, callback)
        callbacks[#callbacks + 1] = callback
        return { SetEnabled = Noop }
    end }
    local bars = { showArcaneWindow = true }
    local keys = { "arcaneWindowText", "arcaneWindowWarnSeconds", "resourceExtraWidth", "resourceExtraHeight", "resourceExtraOffsetY" }
    if case == "invalid" then for _, key in ipairs(keys) do bars[key] = "bad" end end
    if case == "normal" then
        bars.arcaneWindowText, bars.arcaneWindowWarnSeconds = "seconds", 3
        bars.resourceExtraWidth, bars.resourceExtraHeight, bars.resourceExtraOffsetY = 220, 8, -18
    end
    local helper = core.CPBuilders.ExtraAuras({ db = { bars = bars }, PLAYER_CLASS = "MAGE",
        GetSpec = function() return 1 end, GetPlayerFrame = function() return env.UIParent end,
        Texture = function() return "texture" end, NotSecret = function() return true end })
    helper.Refresh()
    assert(#callbacks == 2, "both native arcane sensors required")
    local button = env.CreateFrame("Frame", nil, env.UIParent)
    callbacks[1](button)
    callbacks[2](env.CreateFrame("Frame", nil, env.UIParent))
    local operations = { callback = function() callbacks[1](button) end,
        refresh = helper.Refresh, haste = helper.UsesHaste }
    for _, name in ipairs({ "callback", "refresh", "haste" }) do
        local vm, native, bytes = Count(operations[name])
        local label = case .. "/" .. name
        print(string.format("%s VM=%d native=%d bytes=%.6f", label, vm, native, bytes))
        if not measureOnly then
            local budget = assert(BUDGETS[label], "old-owner budget missing " .. label)
            assert(vm == budget[1], label .. " VM cost changed: " .. vm .. " expected " .. budget[1])
            assert(native == budget[2], label .. " native calls changed")
            assert(bytes == budget[3], label .. " uninstrumented allocations changed")
        end
    end
end
print("resource_extra_aura_defaults_smoke: real missing/invalid/normal callbacks and refresh measured")
