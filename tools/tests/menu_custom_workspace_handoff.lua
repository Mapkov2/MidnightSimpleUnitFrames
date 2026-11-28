-- A moved helper must remain lexical; unknown-global stubs must not mask it.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home", beforeOptions = function(world)
    local meta = getmetatable(world.env)
    local lookup = meta.__index
    meta.__index = function(env, key)
        assert(key ~= "ResetButton" and key ~= "HideInlineSwatch", "moved helper escaped its lexical handoff: " .. key)
        return lookup(env, key)
    end
end })
local M = mw.M
local motionControl, capturingMotion
local bind = M.ControlSchema.Bind
M.ControlSchema.Bind = function(ctx, widget, spec)
    local result = bind(ctx, widget, spec)
    if capturingMotion and spec.id == "menu2.uf_player.auras.custom-container.appearance.animate-new-icons" then
        assert(not motionControl, "duplicate Defensive Buffs motion switch")
        motionControl = assert(widget._msuf2CommandAction)
    end
    return result
end
for _, unit in ipairs({ "player", "target" }) do
    local key = "uf_" .. unit
    assert(mw:Select(key))
    local entry = M.cache[key]
    local ctx = M.CreateContext(key, entry.wrapper, entry)
    for index = 1, 4 do
        for _, tool in ipairs({ "filters", "layout", "appearance", "effect", "behavior", "setup", "whitelist" }) do
            capturingMotion = unit == "player" and index == 4 and tool == "appearance"
            M.BuildAuras3CompactCustomWorkspace(ctx, M.Widgets.PageBuilder(ctx), unit, index, tool)
            capturingMotion = false
        end
    end
end
if flavor == "Mainline" or flavor == "Forever" then
    local control = assert(motionControl, "Defensive Buffs Appearance is missing its motion switch")
    local function placed()
        return M.EnsureDB().auras3.customContainers.perUnit.player.items[4].placed
    end
    placed().animateNewIcons, placed().animateAppearance = nil, true
    assert(control.get() == true, "legacy animation setting was lost")
    control.set(false)
    assert(placed().animateNewIcons == false and control.get() == false)
    control.set(true)
    assert(placed().animateNewIcons == true and control.get() == true)
else
    assert(not motionControl, "Native appearance animation switch leaked to a Classic client")
end
print("PASS Custom Aura handoff " .. flavor .. ": all containers and tools use lexical helpers")
