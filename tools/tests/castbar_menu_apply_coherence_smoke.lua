-- menu_coherence_probe.lua <root> <flavor> [pages]
-- Drives every bound Menu2 control on the castbar-related pages through its real
-- command.set, runs the real apply flush, and then compares the castbar Config
-- snapshot with the live SavedVariables for the written key.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local pages = {}
for key in (arg[3] or "opt_castbar,uf_player,uf_target,uf_focus,uf_boss,uf_arena,opt_colors,opt_fonts,opt_bars"):gmatch("[^,]+") do
    pages[#pages + 1] = key
end
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
    beforeCore = function(world)
        world.env.MAX_TOTEMS = 4
        world.widgets.Methods.GetNumPoints = function(frame) return #(frame.points or {}) end
    end })
local M, env, core = mw.M, mw.env, mw.core
local castbars = core.Castbars
local Config = castbars and castbars.Config

-- Unrelated native unit-frame/class-resource owners are outside this fixture.
env.MSUF_UFCore_NotifyConfigChanged = function() return false end
env.MSUF_RefreshAllUnitAlphas = function() end
env.MSUF_ClassPower_Apply = function() end
env.MSUF_ApplyModules = function() end
core.MSUF_Gameplay_PlayerTotems_Apply = function() end
local controls, order = {}, {}
local Register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.controlId and payload.command then
        if not controls[payload.controlId] then order[#order + 1] = payload.controlId end
        controls[payload.controlId] = { payload = payload, widget = widget }
    end
    return Register(widget, payload, ...)
end

local function Settle() for _ = 1, 3 do mw:RunTimers() end end
local function Build(pageKey)
    local ok = M.SelectPage(pageKey)
    Settle()
    local entry = M.cache and M.cache[pageKey]
    if not entry then print("PAGE-MISSING", pageKey, ok) return end
    for _, section in pairs(entry.sections or {}) do M.Widgets.EnsureSectionContent(section) end
    Settle()
end

local function Resolve(tbl, path)
    local node = tbl
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil, false end
        node = node[part]
    end
    return node, true
end

for _, page in ipairs(pages) do Build(page) end
M.ColorsEnsureCategoryBuilt("colors_castbar")
Settle()
Build("opt_colors")
print("controls", #order)

local stale, checked, failed = {}, 0, 0
local kinds = {}
for _, id in ipairs(order) do
    local entry = controls[id]
    local payload, command = entry.payload, entry.payload.command
    local key = payload.settingKey
    local lower = key and key:lower() or ""
    local relevant = key and not lower:find("portrait", 1, true) and payload.classification ~= "ephemeral" and (payload.pageKey == "opt_castbar"
        or lower:find("cast", 1, true) or lower:find("kick", 1, true) or lower:find("interrupt", 1, true)
        or lower:find("empower", 1, true) or lower:find("gcd", 1, true) or key == "general.anchorToCooldown")
    if relevant and type(key) == "string" and type(command.get) == "function" and type(command.set) == "function"
        then
        local ok, current, green, blue, alpha = pcall(command.get)
        assert(ok, current)
        if ok then
            local nextValue
            local values = entry.widget.values
            if type(values) == "function" then values = values() end
            if payload.kind == "color" then
                nextValue = 0.23
            elseif type(values) == "table" then
                for _, item in ipairs(values) do
                    local value = type(item) == "table" and (item.value or item.key or item[2] or item[1]) or item
                    if value ~= current then nextValue = value break end
                end
                nextValue = nextValue or current
            elseif type(current) == "boolean" then
                nextValue = not current
            elseif type(current) == "number" then
                local low, high = entry.widget:GetMinMaxValues()
                if type(low) == "number" and type(high) == "number" and high > low then
                    nextValue = current < high and math.min(high, current + 1) or math.max(low, current - 1)
                else nextValue = current + 1 end
            elseif type(current) == "string" then
                nextValue = current == "Test" and "Other" or "Test"
            elseif current == nil then
                nextValue = true
            end
            assert(nextValue ~= nil, "no test value for " .. id)
            if nextValue ~= nil then
                local before = {}
                for field, value in pairs(env.MSUF_DB.general) do before[field] = value end
                local setOk, err
                if payload.kind == "color" then setOk, err = pcall(command.set, nextValue, 0.41, 0.67, 0.83)
                else setOk, err = pcall(command.set, nextValue) end
                if not setOk then
                    failed = failed + 1
                    print("SET-ERROR", id, key, tostring(err):sub(1, 160))
                end
                M.ApplyService.Flush()
                Settle()
                local live = Resolve(env.MSUF_DB, key)
                for field, value in pairs(env.MSUF_DB.general) do
                    -- Edit Mode's public anchor getter reads the source; exercised below.
                    if field ~= "anchorToCooldown" and before[field] ~= value and Config.DB.general[field] ~= value then
                        stale[#stale + 1] = "general." .. field
                        print("STALE-WRITE", id, field)
                    end
                end
                checked = checked + 1
                kinds[payload.kind] = (kinds[payload.kind] or 0) + 1
                if Config and Config.DB then
                    local snapshot, present = Resolve(Config.DB, key)
                    if key == "general.anchorToCooldown" then snapshot = live end
                    if present and live ~= snapshot and type(live) ~= "table" then
                        stale[#stale + 1] = key
                        print("STALE", payload.kind, key, "live=" .. tostring(live), "snapshot=" .. tostring(snapshot), id)
                    end
                end
                command.set(current, green, blue, alpha)
                M.ApplyService.Flush()
                Settle()
            end
        end
    end
end
print(("checked %d settings, %d stale, %d set errors"):format(checked, #stale, failed))
for kind, count in pairs(kinds) do print(kind, count) end
assert(kinds.color and kinds.color >= 10, "castbar color category was not materialized")

assert(checked >= 76, "too few real castbar menu settings checked: " .. checked)
assert(failed == 0 and #stale == 0, "real menu apply left castbar settings stale")
local behaviorKeys = {}
for _, id in ipairs(order) do local p = controls[id].payload behaviorKeys[p.settingKey or ""] = p end
local function Set(key, value)
    assert(behaviorKeys[key], "missing real menu control " .. key).command.set(value)
    M.ApplyService.Flush()
    Settle()
end
Set("general.castbarFillDirection", "LTR")
local count, compile = 0, Config.Compile
Config.Compile = function(...) count = count + 1 return compile(...) end
M.ApplyService.RequestCastbars("test")
M.ApplyService.Flush()
Config.Compile = compile
assert(count == 1, "one real menu flush compiled " .. count .. " times")
Set("general.castbarInterruptFeedbackDuration", 2.5)
assert(castbars.Utils.GetInterruptFeedbackDuration() == 2.5, "runtime interrupt duration is stale")
if core.Client.SupportsUnit("focus") then
    env.MSUF_DB.general.enableFocusKickIcon = true
    env.MSUF_Castbars_OnSettingsChanged("test")
    Settle()
    for _, value in ipairs({ true, false, true }) do
        Set("general.focusKickShowCastbar", value)
        assert((castbars.Frames.Get("focus")._msufFocusKickSuppressed == true) == not value, "focus suppression is stale")
    end
else
    assert(not behaviorKeys["general.focusKickShowCastbar"], "unsupported focus control was built")
end
if core.Client.HostsCooldownManager then
    local viewer = env.CreateFrame("Frame", "EssentialCooldownViewer", env.UIParent)
    env.EssentialCooldownViewer = viewer
    viewer:Show()
    env.MSUF_GetUsableCooldownAnchorSize = function(frame) if frame then return 100, 20 end end
    Set("general.anchorToCooldown", true)
    assert(env.MSUF_GetAnchorFrame() == viewer, "Edit Mode cooldown anchor is stale")
    Set("general.anchorToCooldown", false)
    assert(env.MSUF_GetAnchorFrame() == env.UIParent, "Edit Mode cooldown anchor did not reset")
end
print("castbar_menu_apply_coherence_smoke: ok")
