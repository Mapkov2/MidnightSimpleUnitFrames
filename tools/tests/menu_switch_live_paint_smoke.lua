-- menu_switch_live_paint_smoke.lua <repoRoot> <flavor>
-- Native CheckButton input can change GetChecked before the Lua binding runs.
-- A SectionSwitch must paint the value accepted by the binding immediately,
-- without depending on a later hover or OnClick post-hook. The full native
-- hook sequence used to hide this gap, so exercise that sequence separately.
-- Boot the real menu with client-style independent base scripts/post-hooks.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local checks = 0
local function Check(condition, message)
    checks = checks + 1
    if not condition then error("menu_switch_live_paint_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, W, env = mw.M, mw.M.Widgets, mw.env
-- The menu's header tooltip uses these native methods, absent in the shared
-- tooltip stub. Keep the full hover handlers; only supply the missing API.
env.GameTooltip.SetOwner = function(self, owner) self.owner = owner end
env.GameTooltip.AddLine = function() end
local host = env.CreateFrame("Frame", nil, env.UIParent)
host._msuf2Width = 600
local section = env.CreateFrame("Frame", nil, host)
section._msuf2CollapsibleEntry = { header = host }
local master = W.SectionSwitch(section, "Enable")
local ordinary = W.SwitchAt(host, "Enable", 0, -40)
local reference = W.SwitchAt(host, "Enable", 0, -80, 0, "HIDDEN")

local function Bind(button)
    local state = { value = false, accepted = true, writes = 0 }
    local ctx = { key = "switch-smoke", entry = { refreshers = {} } }
    M.BindToggle(ctx, button, function() return state.value end, function(value)
        state.writes = state.writes + 1
        if state.accepted then state.value = value end
    end)
    M.Refresh(ctx)
    state.ctx = ctx
    return state
end
local masterState, ordinaryState = Bind(master), Bind(ordinary)
local masterPaints = 0
local rawPaint = master._msuf2SwitchFill.SetVertexColor
master._msuf2SwitchFill.SetVertexColor = function(self, ...)
    masterPaints = masterPaints + 1
    return rawPaint(self, ...)
end

local function Visual(button, checked, label)
    Check((button:GetChecked() and true or false) == checked, label .. ": native state disagrees")
    local point, _, relativePoint, x = button._msuf2SwitchKnob:GetPoint()
    Check(point == (checked and "RIGHT" or "LEFT") and relativePoint == point
        and x == (checked and -2 or 2), label .. ": knob has stale position")
    -- Compare colors with an independently painted ordinary switch. The
    -- assertion follows the active theme without duplicating its palette.
    reference._msuf2SwitchHovered = button._msuf2SwitchHovered
    reference._msuf2SwitchPressed = button._msuf2SwitchPressed
    reference:SetChecked(checked)
    for _, field in ipairs({ "_msuf2SwitchFill", "_msuf2SwitchEdge", "_msuf2SwitchKnob" }) do
        local actual = { button[field]:GetVertexColor() }
        local expected = { reference[field]:GetVertexColor() }
        for channel = 1, 4 do
            Check(actual[channel] == expected[channel], label .. ": stale " .. field .. " color")
        end
    end
end

local function BaseClick(button)
    -- Model only native state mutation and the bound base handler. No hover,
    -- mouse-up paint, or independent OnClick post-hook can rescue this case.
    button._msuf2RawSetChecked(button, not button:GetChecked())
    button:GetScript("OnClick")(button, "LeftButton", false)
end
for _, checked in ipairs({ true, false }) do
    BaseClick(master)
    Check(masterState.value == checked, "the master binding did not accept the click")
    Visual(master, checked, "master base click " .. tostring(checked))
    local before = masterPaints
    M.Refresh(masterState.ctx)
    M.Refresh(masterState.ctx)
    Check(masterPaints == before, "settled master refresh repainted unchanged state")
    BaseClick(ordinary)
    Check(ordinaryState.value == checked, "ordinary switch binding did not accept the click")
    Visual(ordinary, checked, "ordinary base click " .. tostring(checked))
end

-- An unbound native change also needs repair when a profile/history refresh
-- supplies the value already held by GetChecked.
for _, checked in ipairs({ true, false }) do
    masterState.value = checked
    master._msuf2RawSetChecked(master, checked)
    M.Refresh(masterState.ctx)
    Visual(master, checked, "external value refresh " .. tostring(checked))
end
local before = masterPaints
master:SetChecked(nil)
master:SetChecked(false)
Check(masterPaints == before, "equivalent false values repainted a settled master")
master:SetChecked(1)
Visual(master, true, "truthy SetChecked")
before = masterPaints
master:SetChecked(true)
Check(masterPaints == before, "equivalent true values repainted a settled master")
master:SetChecked(false)

local function NativeClick(button)
    MenuWorld.FireScript(button, "OnEnter")
    MenuWorld.FireScript(button, "OnMouseDown", "LeftButton")
    MenuWorld.FireScript(button, "OnMouseUp", "LeftButton")
    button._msuf2RawSetChecked(button, not button:GetChecked())
    MenuWorld.FireScript(button, "OnClick", "LeftButton", false)
end
for _, checked in ipairs({ true, false }) do
    NativeClick(master)
    Check(masterState.value == checked, "full native dispatch did not accept the master click")
    Visual(master, checked, "full native master click " .. tostring(checked))
    MenuWorld.FireScript(master, "OnLeave")
    Visual(master, checked, "master mouse leave " .. tostring(checked))
    NativeClick(ordinary)
    Check(ordinaryState.value == checked, "full native dispatch did not accept the ordinary click")
    Visual(ordinary, checked, "full native ordinary click " .. tostring(checked))
    MenuWorld.FireScript(ordinary, "OnLeave")
end

-- Rejected and combat-blocked setters restore the accepted value, both on
-- and off. The setter must never run while the binding refuses combat input.
for _, item in ipairs({ { master, masterState }, { ordinary, ordinaryState } }) do
    local button, state = item[1], item[2]
    for _, checked in ipairs({ false, true }) do
        state.value = checked
        M.Refresh(state.ctx)
        state.accepted = false
        BaseClick(button)
        Visual(button, checked, "rejected base click " .. tostring(checked))
        state.accepted = true
        local writes = state.writes
        mw.world.widgets:SetCombat(true)
        BaseClick(button)
        mw.world.widgets:SetCombat(false)
        Check(state.writes == writes and state.value == checked, "combat click reached the setter")
        Visual(button, checked, "combat base click " .. tostring(checked))
    end
    state.value = false
    M.Refresh(state.ctx)
end

local label = Check(ordinary._msuf2LabelHit, "ordinary switch has no label click surface")
for _, checked in ipairs({ true, false }) do
    MenuWorld.FireScript(label, "OnEnter")
    MenuWorld.FireScript(label, "OnMouseDown", "LeftButton")
    MenuWorld.FireScript(label, "OnMouseUp", "LeftButton")
    MenuWorld.FireScript(label, "OnClick", "LeftButton", false)
    Check(ordinaryState.value == checked, "label click did not reach the binding")
    Visual(ordinary, checked, "label click " .. tostring(checked))
    MenuWorld.FireScript(label, "OnLeave")
end
Check(W.SectionSwitch(section, "Enable") == master, "lazy section rebuilt its master switch")
print("menu_switch_live_paint_smoke " .. flavor .. ": " .. checks .. " checks passed")
