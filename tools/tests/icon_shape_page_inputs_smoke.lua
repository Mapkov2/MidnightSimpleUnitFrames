-- Shape controls live on Icon Skins, outside the frozen legacy layouts.
-- Exercise their real dropdown clicks, bindings, profile writes, undo/redo,
-- combat refusal, reset buttons, capability gates and search identities.
-- Optional arg3 replaces only the page source for causal controls.
local root, flavor = assert(arg[1], "repository root required"), assert(arg[2], "client required")
root = root:gsub("\\", "/"):gsub("/$", "")
local pagePath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_IconSkins.lua"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local replaced = 0
local mw = MenuWorld.Open(root, flavor, { open = false, clientScriptBindings = true, nativeButtonLifecycle = true,
    beforeCore = function(world)
        local native = world.env
        local power = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))().PT
        local enum = native.Enum
        native.Enum = setmetatable({ PowerType = { Mana = power.MANA, Rage = power.RAGE, Focus = 2,
            Energy = power.ENERGY, ComboPoints = power.COMBO } }, { __index = enum })
        local function CheckPowerType(value)
            assert(value == nil or type(value) == "number", "native power-type argument must be numeric or nil")
        end
        native.UnitPowerType = function() return power.RAGE, "RAGE" end
        native.UnitPower = function(_, value) CheckPowerType(value) return 0 end
        native.UnitPowerMax = function(_, value)
            CheckPowerType(value)
            if value == nil or value == power.RAGE then return 100 end
            return 5
        end
        native.UnitPowerDisplayMod = function() return 1 end
        native.UnitHasVehicleUI = function() return false end
        native.PlayerVehicleHasComboPoints = function() return false end
        native.GetShapeshiftFormID = function() return nil end
        assert(native.UnitPowerType("player") == power.RAGE and native.UnitPower("player", power.RAGE) == 0
            and native.UnitPowerMax("player", power.RAGE) == 100 and native.UnitPowerMax("player", power.COMBO) == 5
            and native.UnitPowerDisplayMod(power.COMBO) == 1 and native.UnitHasVehicleUI("player") == false
            and native.PlayerVehicleHasComboPoints() == false and native.GetShapeshiftFormID() == nil,
            "native idle Warrior power fixture drift")
        local function NativeNumber(value)
            assert(type(value) == "number" and value == value and value - value == 0, "native numeric formatter requires a finite number")
            return value
        end
        local function Abbreviate(value)
            value = NativeNumber(value)
            if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
            if value >= 1000 then return string.format("%.1fK", value / 1000) end
            return string.format("%d", value)
        end
        native.AbbreviateNumbers, native.AbbreviateLargeNumbers = Abbreviate, Abbreviate
        native.BreakUpLargeNumbers = function(value) return string.format("%d", math.floor(NativeNumber(value))) end
        assert(native.AbbreviateNumbers(1234) == "1.2K" and native.AbbreviateLargeNumbers(1234000) == "1.2M"
            and native.BreakUpLargeNumbers(1234) == "1234", "native numeric formatter fixture drift")
        local tocPath = root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. world.client.tocSuffix .. ".toc"
        local toc = assert(io.open(tocPath, "rb"), "shape core TOC metadata missing")
        local metadata = toc:read("*a")
        assert(toc:close(), "shape core TOC metadata close failed")
        local prefix = assert(metadata, "shape core TOC metadata unreadable"):match("\n## X%-MSUF%-UnitFrames%-Prefix:%s*([^\r\n]+)")
        assert(prefix == "MSUF", "native unit-frame TOC prefix fixture drift")
        local getMetadata = native.C_AddOns.GetAddOnMetadata
        native.C_AddOns.GetAddOnMetadata = function(addon, field)
            if addon == "MidnightSimpleUnitFrames" and field == "X-MSUF-UnitFrames-Prefix" then return prefix end
            return getMetadata(addon, field)
        end
        native.GetAddOnMetadata = native.C_AddOns.GetAddOnMetadata
        native.TotemFrame = native.CreateFrame("Frame", nil, native.UIParent)
        assert(native.TotemFrame:GetObjectType() == "Frame" and native.TotemFrame:GetNumPoints() == 0,
            "native TotemFrame empty layout fixture drift")
    end,
    beforeOptions = function(world)
        assert(world.core.UF.frameNamePrefix == "MSUF", "shape real unit prefix was not loaded")
        if not arg[3] then return end
        local load = world.LoadFile
        world.LoadFile = function(self, path, addon, namespace)
            if path:gsub("\\", "/") == root .. "/" .. pagePath then path, replaced = arg[3], replaced + 1 end
            return load(self, path, addon, namespace)
        end
    end })
assert(not arg[3] or replaced == 1, "page causal control was not loaded exactly once")
local M, core, env = mw.M, mw.core, mw.env
local controls, metadata, resets, routes = {}, {}, {}, {}
local register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.pageKey == "icon_skins" and payload.settingKey then
        controls[payload.settingKey] = widget
        local saved = {}
        for key, value in pairs(payload) do saved[key] = value end
        metadata[payload.settingKey] = saved
    end
    return register(widget, payload, ...)
end
local button = M.Widgets.Button
M.Widgets.Button = function(parent, label, ...)
    local widget = button(parent, label, ...)
    if label == "Reset section" then
        local list = resets[parent] or {}
        resets[parent], list[#list + 1] = list, widget
    end
    return widget
end
local requestGeneral, requestUnit = M.RequestGeneralDomains, M.RequestUnitDomains
M.RequestGeneralDomains = function(reason, flags)
    routes[#routes + 1] = { scope = "general", reason = reason, flags = flags }
    return requestGeneral(reason, flags)
end
M.RequestUnitDomains = function(unit, reason, flags)
    routes[#routes + 1] = { scope = unit, reason = reason, flags = flags }
    return requestUnit(unit, reason, flags)
end
local function Settle() mw:RunTimers(20000) end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Snapshot()
    local copy, valid, why = core.ProfileFields.CopySnapshot(env.MSUF_DB)
    assert(valid and type(copy) == "table", "shape profile snapshot failed: " .. tostring(why))
    return copy
end
local function Input(widget, value)
    assert(widget:IsEnabled(), "enabled shape dropdown unexpectedly disabled")
    widget:Click("LeftButton")
    Settle()
    local selected
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame._msuf2Owner == widget and frame._msuf2Value == value and frame:IsShown() then selected = frame end
    end
    assert(selected, "real dropdown opened no row for " .. value)
    selected:Click("LeftButton")
    Settle()
end

-- Search deliberately refuses a closed menu. Open Home while Icon Skins
-- remains unbuilt, so this probes the real cold static index.
assert(M.Open("home") ~= false, "shape search menu did not open")
Settle()
assert(not M.cache.icon_skins, "shape search page was not cold")
-- Cold search must apply the page's client scopes to the shared union.
local supported = {
    ["general.castbarPlayerIconShape"] = core.Client.SupportsUnit("player"),
    ["general.castbarTargetIconShape"] = core.Client.SupportsUnit("target"),
    ["general.castbarFocusIconShape"] = core.Client.SupportsUnit("focus"),
    ["general.bossCastIconShape"] = core.Client.SupportsUnit("boss"),
    ["general.arenaCastIconShape"] = core.Client.SupportsUnit("arena"),
    ["general.focusKickIconShape"] = core.Client.SupportsUnit("focus"),
    ["arena.trinketShape"] = core.Client.MaxArenaOpponents > 0,
}
local foundPlayer = false
for _, query in ipairs({ "castbar icon shape", "focus interrupt tracker icon shape", "trinket icon shape" }) do
    for _, record in ipairs(M.Search._CoreAPI.SearchPages(query)) do
        local target = record.exactTarget
        local key = target and target.settingKey
        if record.key == "icon_skins" and supported[key] ~= nil then
            assert(supported[key], "cold search offers an unsupported shape: " .. key)
            if key == "general.castbarPlayerIconShape" then foundPlayer = true end
        end
    end
end
assert(foundPlayer, "cold search found no real Player shape target")

assert(M.Open("icon_skins") ~= false, "Icon Skins did not open")
Settle()
local entry = assert(M.cache.icon_skins, "Icon Skins built no page entry")
for _, section in pairs(entry.sections or {}) do M.Widgets.EnsureSectionContent(section) end
Settle()
local general = M.GetGeneralDB()
local rows = {
    { "player", "castbarPlayerIconShape", "castbarPlayer", "castbarPlayerBackend", "castbarPlayerShowIcon" },
    { "target", "castbarTargetIconShape", "castbarTarget", "castbarTargetBackend", "castbarTargetShowIcon" },
    { "focus", "castbarFocusIconShape", "castbarFocus", "castbarFocusBackend", "castbarFocusShowIcon" },
    { "boss", "bossCastIconShape", "bossCast", "bossCastbarBackend", "showBossCastIcon" },
    { "arena", "arenaCastIconShape", "arenaCast", "arenaCastbarBackend", "showArenaCastIcon" },
}
for _, row in ipairs(rows) do general[row[4]], general[row[5]] = "MSUF", true end
general.castbarShowIcon, general.enableFocusKickIcon = true, true
for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
Settle()
-- File boot does not perform the native unit apply that precedes an in-game
-- menu. Run that real boundary before the history baseline, and require the
-- complete raw profile to remain stable on the second settled apply.
assert(core.ApplyService.RequestGeneralDomains("ICON_SHAPE_FIXTURE_LOGIN", { preview = true }))
Settle()
local nativeBaseline = Snapshot()
assert(core.ApplyService.RequestGeneralDomains("ICON_SHAPE_FIXTURE_LOGIN", { preview = true }))
Settle()
assert(Equal(nativeBaseline, Snapshot()), "native shape fixture did not settle before history")
M.StartHistorySession("menu")
assert(M.SyncExternalHistoryState(), "shape fixture history baseline unavailable")

local checked = 0
local function Exercise(path, read, resolve, reset, expectedScope, sectionId)
    local widget, meta = assert(controls[path], "shape control missing: " .. path), assert(metadata[path])
    assert(meta.pageKey == "icon_skins" and meta.controlId and meta.controlPath, "shape search identity incomplete: " .. path)
    assert(type(widget._msuf2OnValueChanged) == "function", "shape control not bound: " .. path)
    assert(M.SyncExternalHistoryState(), "shape fixture history rebase unavailable")
    local static
    for _, record in ipairs(M.Search.StaticIndex.GetRecords()) do
        local target = record.exactTarget
        if record.key == "icon_skins" and target and target.settingKey == path then static = record end
    end
    assert(static and static.exactTarget.sectionId == sectionId, "shape static search route missing/wrong: " .. path)
    local section = assert(entry.sections[sectionId])
    local collapsible = assert(section._msuf2CollapsibleEntry)
    collapsible.SetOpenImmediate(false)
    assert(mw:Select("home") ~= false)
    assert(M.OpenExactSettingControl(path, static.label, "icon_skins"), "shape exact search route failed: " .. path)
    Settle()
    local _, resolved = M.RuntimeControlCatalog.ResolveExactTarget("icon_skins", static.exactTarget)
    assert(M.activeKey == "icon_skins" and resolved == widget and collapsible.open == true,
        "shape search did not reach/open its actual control: " .. path)
    assert(M.SyncExternalHistoryState(), "shape post-search history baseline unavailable")
    local before, historyBefore = Snapshot(), M.GetHistoryState().undoCount
    routes = {}
    Input(widget, "CIRCLE")
    assert(read() == "CIRCLE" and resolve() == "CIRCLE" and widget:GetValue() == "CIRCLE", "shape input/readback drift: " .. path)
    assert(M.GetHistoryState().undoCount == historyBefore + 1, "shape input did not create exactly one undo step: " .. path)
    local after = Snapshot()
    local routed
    for _, route in ipairs(routes) do
        if route.scope == expectedScope and route.flags and route.flags.preview then
            if expectedScope ~= "general" or route.flags.castbar then routed = true end
        end
    end
    assert(routed, "shape input lost runtime/preview apply route: " .. path)
    assert(M.Undo(), "shape undo unavailable: " .. path) Settle()
    assert(Equal(before, Snapshot()) and widget:GetValue() == resolve(), "shape undo/readback drift: " .. path)
    assert(M.Redo(), "shape redo unavailable: " .. path) Settle()
    assert(Equal(after, Snapshot()) and widget:GetValue() == "CIRCLE", "shape redo/readback drift: " .. path)
    assert(reset and reset:GetScript("OnClick"), "shape reset button missing: " .. path)
    for _, lockdown in ipairs({ false, true }) do
        core.Util.InCombat("PLAYER_REGEN_DISABLED")
        env.InCombatLockdown = function() return lockdown end
        local locked, undoCount = Snapshot(), M.GetHistoryState().undoCount
        routes = {}
        -- A stale native callback still reaches the binding after combat starts.
        widget._msuf2OnValueChanged("STAR")
        assert(Equal(locked, Snapshot()) and #routes == 0 and M.GetHistoryState().undoCount == undoCount,
            "shape write escaped combat refusal: " .. path)
        reset:Click("LeftButton")
        assert(Equal(locked, Snapshot()) and #routes == 0 and M.GetHistoryState().undoCount == undoCount,
            "shape reset escaped combat refusal: " .. path)
        assert(M.Undo() == false, "shape history was available in combat: " .. path)
        core.Util.InCombat("PLAYER_REGEN_ENABLED")
        env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle()
    end
    local beforeReset, countBeforeReset = Snapshot(), M.GetHistoryState().undoCount
    reset:Click("LeftButton") Settle()
    assert(M.GetHistoryState().undoCount == countBeforeReset + 1, "shape reset did not make exactly one history step: " .. path)
    local afterReset = Snapshot()
    assert(read() == "RECTANGLE" and resolve() == "RECTANGLE" and widget:GetValue() == "RECTANGLE", "shape reset/readback drift: " .. path)
    assert(M.Undo(), "shape reset left no undo step: " .. path) Settle()
    assert(Equal(beforeReset, Snapshot()) and read() == "CIRCLE" and widget:GetValue() == "CIRCLE", "shape reset undo drift: " .. path)
    assert(M.Redo(), "shape reset redo unavailable: " .. path) Settle()
    assert(Equal(afterReset, Snapshot()) and read() == "RECTANGLE", "shape reset redo drift: " .. path)
    checked = checked + 1
end

local castSection = assert(entry.sections.icon_skins_castbar_shapes, "castbar shapes section missing")
local index = 0
for _, row in ipairs(rows) do
    local unit, key, prefix = row[1], row[2], row[3]
    if core.Client.SupportsUnit(unit) then
        index = index + 1
        Exercise("general." .. key, function() return general[key] end,
            function() return core.Castbars.Visuals.IconShape(general, prefix) end, resets[castSection][index], "general", "icon_skins_castbar_shapes")
        local widget = controls["general." .. key]
        general[row[4]] = "HIDE"
        for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
        assert(widget._msuf2DesiredEnabled == false and widget._msuf2DisabledReason(widget), "hidden castbar shape not explained/disabled")
        general[row[4]], general[row[5]] = "MSUF", false
        for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
        assert(widget._msuf2DesiredEnabled == false, "hidden icon shape remained editable")
        general[row[5]] = true
        for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
        assert(widget._msuf2DesiredEnabled == true, "castbar shape did not re-enable")
    else
        assert(controls["general." .. key] == nil, "unsupported castbar shape offered: " .. unit)
    end
end
local focusSection = entry.sections.icon_skins_focus_shape
if core.Client.SupportsUnit("focus") then
    Exercise("general.focusKickIconShape", function() return general.focusKickIconShape end,
        function() return core.MSUF_Auras3.IconShape.Resolve(general.focusKickIconShape) end, resets[assert(focusSection)][1], "general", "icon_skins_focus_shape")
    general.enableFocusKickIcon = false
    for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
    local widget = controls["general.focusKickIconShape"]
    assert(widget._msuf2DesiredEnabled == false and widget._msuf2DisabledReason(widget), "inactive focus tracker shape not explained/disabled")
else
    assert(focusSection == nil and controls["general.focusKickIconShape"] == nil, "unsupported focus tracker shape offered")
end
local trinketSection = entry.sections.icon_skins_trinket_shape
if core.Client.MaxArenaOpponents > 0 then
    Exercise("arena.trinketShape", function() return M.GetUnitDB("arena").trinketShape end,
        function() return core.MSUF_Auras3.IconShape.Resolve(M.GetUnitDB("arena").trinketShape) end,
        resets[assert(trinketSection)][1], "arena", "icon_skins_trinket_shape")
else
    assert(trinketSection == nil and controls["arena.trinketShape"] == nil, "unsupported trinket shape offered")
end
assert(checked >= 2, "shape input test exercised no supported client controls")
print("icon_shape_page_inputs_smoke: OK (" .. flavor .. ", " .. checked .. " controls; real dropdown/history/combat/reset/gates/search identity)")
