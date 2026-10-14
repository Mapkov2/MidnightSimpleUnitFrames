-- The declaration calls the real selector, including its normalization and repaint.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
assert(not arg[3], "lazy owner fixtures are immutable original-source receipts")
local original = false
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    world.env.GetSpecialization = function() return 1 end
    world.env.GetSpecializationInfo = function() return 62 end
    world.env.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 62 end,
    }
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local M, env, core = mw.M, mw.env, mw.core
local F = core.ProfileFields
-- Native rendering is outside this menu owner fixture.
core.ProfileRuntime.Apply = function() end
core.MSUF_ApplyGameplayVisuals = function() end
env.MSUF_UFCore_NotifyConfigChanged = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
-- Keep an intentionally sparse current root from being replaced by profile initialization.
local initProfiles = env.MSUF_InitProfiles
env.MSUF_InitProfiles = function() end
local lines = {}
local function Encode(value)
    if type(value) == "table" then
        local out = {}
        for i, item in ipairs(value) do out[i] = tostring(item.value) .. "=" .. tostring(item.text) end
        return table.concat(out, ",")
    end
    return type(value) .. ":" .. tostring(value):gsub("[\r\n\t]", " ")
end
local function Row(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = Encode(select(i, ...)) end
    lines[#lines + 1] = table.concat(out, "\t")
end
local function Expand(page)
    for _, section in pairs(M.cache[page].sections or {}) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
    M.Refresh(M.cache[page].ctx)
    mw:RunTimers()
end
local function Verify(name)
    local result = table.concat(lines, "\n") .. "\n"
    local f = assert(io.open(root .. "/tools/fixtures/menu-pilot-lazy/" .. name .. "-" .. flavor .. ".tsv", "rb"))
    local expected = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    assert(result == expected, name .. ": original-source inventory/behavior drift on " .. flavor)
    print(name .. " " .. flavor .. ": " .. #lines .. " original-source state/control rows OK")
end

local valuesValid = true
local cases = { { "missing" }, { "false", false }, { "zero", 0 }, { "number", 5 },
    { "invalid", "invalid" }, { "empty", "" }, { "case", "OOC" }, { "combat", "combat" }, { "ooc", "ooc" } }
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    local page = "uf_" .. unit
    if M.pages[page] then
        assert(mw:Select(page))
        -- The selector must remain lazy until its real section opens.
        local id = "menu2." .. page .. ".unit.transparency.state_selector"
        assert(not M.RuntimeControlCatalog.Get(id), "alpha selector lost lazy construction")
        Expand(page)
        local record = assert(M.RuntimeControlCatalog.Get(id))
        local bar = assert(record.widget)
        local spec = bar._msuf2ControlSchema
        if not original then
            assert(spec and spec.id == id and spec.kind == record.kind and spec.labelKey == record.label,
                "selector declaration identity/kind/label drift")
            assert(spec.scope == unit and spec.applyDomain == "navigation", "selector scope/apply drift")
            valuesValid = valuesValid and spec.values == bar.values
        end
        local calls, refreshes, shown, paints, gets = 0, 0, 0, 0, 0
        local setter, refresher, show, getter = bar.SetValue, bar.Refresh, M.Widgets.SetControlShown, bar.GetValue
        bar.GetValue = function(self) gets = gets + 1 return getter(self) end
        bar.SetValue = function(self, value) calls = calls + 1 return setter(self, value) end
        bar.Refresh = function(self) refreshes = refreshes + 1 return refresher(self) end
        M.Widgets.SetControlShown = function(...) shown = shown + 1 return show(...) end
        for _, button in ipairs(bar.buttons) do
            local paint = button.SetActive
            button.SetActive = function(...) paints = paints + 1 return paint(...) end
        end
        local _, general = M.RuntimeControlCatalog.FindBySettingKey(unit .. ".hpBarAlpha", page)
        local _, ooc = M.RuntimeControlCatalog.FindBySettingKey(unit .. ".oocFadeAlpha", page)
        local function Probe(state)
            for _, initial in ipairs({ "combat", "ooc" }) do
                for _, case in ipairs(cases) do
                    bar:SetValue(initial)
                    calls, refreshes, shown, paints, gets = 0, 0, 0, 0, 0
                    local before = F.CopySnapshot(env.MSUF_DB)
                    local result
                    if original then result = bar:SetValue(case[2]) else result = spec.set(case[2]) end
                    local value = original and bar:GetValue() or spec.get()
                    assert(value == bar:GetValue() and F.Equal(before, env.MSUF_DB), "selector wrote profile or getter drifted")
                    Row(page, state, initial, case[1], result, value, calls, refreshes, shown, paints, gets,
                        bar.buttons[1]._msuf2Active, bar.buttons[2]._msuf2Active,
                        general:GetParent():IsShown(), ooc:GetParent():IsShown(), bar.values,
                        record.controlId, record.kind, record.label, record.settingKey, record.controlPath)
                end
            end
        end
        Probe("cold")
        mw:Select("home")
        assert(mw:Select(page))
        assert(M.RuntimeControlCatalog.Get(id).widget == bar, "cached selector was replaced")
        Probe("reopen")
        local profile = env.MSUF_DB
        env.MSUF_DB = F.CopySnapshot(profile)
        env.MSUF_DB[unit] = { hpBarAlpha = 0.3, oocFadeEnabled = true }
        M.Refresh(M.cache[page].ctx)
        Probe("partial-profile")
        env.MSUF_DB = profile
        env.MSUF_InitProfiles = initProfiles
        initProfiles()
        local active = env.MSUF_ActiveProfile
        env.MSUF_GlobalDB.profiles["Selector alternate"] = F.CopySnapshot(env.MSUF_DB)
        assert(env.MSUF_SwitchProfile("Selector alternate") == true, "real profile switch failed")
        M.Refresh(M.cache[page].ctx)
        Probe("real-profile-switch")
        assert(env.MSUF_SwitchProfile(active) == true, "real profile switch back failed")
        env.MSUF_InitProfiles = function() end
        core.Util.InCombat("PLAYER_REGEN_DISABLED")
        env.InCombatLockdown = function() return false end
        Probe("combat")
        core.Util.InCombat("PLAYER_REGEN_ENABLED")
        M.ClearHistory()
        Probe("history")
        assert(not M.Undo(), "ephemeral selector created history")
        M.HideSlashMenuAndMinibar(mw.win)
        assert(M.Open(page) ~= false)
        mw:RunTimers()
        Probe("window-reopen")
        M.Widgets.SetControlShown = show
    end
end
Verify("alpha-selector")
assert(valuesValid, "selector declaration lost the actual values owner")
