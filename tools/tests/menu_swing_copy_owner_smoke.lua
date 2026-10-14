-- Actual Copy To owner and every control materialized by its lazy popup.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
assert(not arg[3], "lazy owner fixtures are immutable original-source receipts")
local original = false
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
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

if not M.pages.swingtimers then
    Row("swingtimers", "unsupported", core.Client.IsForever)
else
    assert(mw:Select("swingtimers"))
    Expand("swingtimers")
    local ui = assert(core.SwingTimer.menuContext._msuf2SwingTimerPreview)
    assert(not ui.copyPopup.GetPopup(), "copy popup lost lazy construction")
    local suffixes = { "close", "target.main", "target.off", "target.ranged", "target.all",
        "category.layout", "category.appearance", "category.text", "category.behavior", "categories.all", "categories.none", "run" }
    local function Control(suffix)
        return assert(M.RuntimeControlCatalog.Get("menu2.swingtimers.swing.copy." .. suffix), "copy control dropped: " .. suffix).widget
    end
    local function Snapshot(state)
        local widgets = { ui.copyButton }
        for _, suffix in ipairs(suffixes) do widgets[#widgets + 1] = Control(suffix) end
        local count = 0
        for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if r.controlId:find("menu2.swingtimers.swing.copy.", 1, true) == 1 then count = count + 1 end
        end
        assert(count == 12, "lazy copy inventory lost or duplicated a real control")
        for _, w in ipairs(widgets) do
            local r = w._msuf2RuntimeControlRecord or assert(w._msuf2SearchMeta, "Copy To metadata missing")
            if not original then
                local s = assert(w._msuf2ControlSchema, "copy owner declaration missing: " .. (r.controlId or "Copy To"))
                assert(s.id == (r.controlId or "menu2.swingtimers.swing.copy.button")
                    and s.kind == r.kind and s.labelKey == r.label, "copy declaration identity/kind/label drift")
                assert(s.scope == "swing" and s.applyDomain == "copyNavigation", "copy scope/apply drift")
                OwnerAssert.Button(w, s)
                assert(s.settingPath == r.settingKey and s.actionKey == r.actionKey, "copy declaration route drift")
            end
            local lo, hi
            if w:GetObjectType() == "Slider" then lo, hi = w:GetMinMaxValues() end
            Row(state, r.controlId, r.kind, r.label, r.settingKey, r.controlPath, r.actionKey, r.classification,
                w:GetObjectType(), lo, hi, w.valueStep, w.values, w:IsShown(), w:IsEnabled(), w:GetChecked(), w._msuf2Active,
                ui.selected, ui.copyPopup.GetPopup():IsShown())
        end
    end
    for _, hand in ipairs({ "main", "off", "ranged" }) do
        ui.SelectHand(hand)
        ui.copyPopup.Show(ui.copyButton)
        local frame = assert(ui.copyPopup.GetPopup())
        Snapshot(hand .. ":open")
        for _, target in ipairs({ "main", "off", "ranged", "all" }) do
            local btn = Control("target." .. target)
            assert(btn:IsShown() == (target ~= hand), "copy target visibility drift")
            if target ~= hand then btn:Click() Snapshot(hand .. ":target:" .. target) end
        end
        Control("categories.none"):Click()
        Snapshot(hand .. ":none")
        local before = F.CopySnapshot(env.MSUF_DB)
        Control("run"):Click()
        assert(F.Equal(before, env.MSUF_DB) and frame:IsShown(), "empty copy selection changed profile or closed popup")
        for i, category in ipairs({ "layout", "appearance", "text", "behavior" }) do
            local cb = Control("category." .. category)
            cb:SetChecked(true)
            cb:Click()
            assert(ui.copyScopes[category] == true, "category owner setter drift")
            ui.copyPopup.Refresh()
            Snapshot(hand .. ":include:" .. category)
            cb:SetChecked(false)
            cb:Click()
            assert(ui.copyScopes[category] == false, "category exclusion lost")
        end
        Control("categories.all"):Click()
        Snapshot(hand .. ":all")
        Control("close"):Click()
        Snapshot(hand .. ":close")
        ui.copyPopup.Show(ui.copyButton)
        assert(ui.copyPopup.GetPopup() == frame, "reopen rebuilt popup owners")
        Snapshot(hand .. ":reopen")
        ui.copyPopup.Show(ui.copyButton)
        assert(not frame:IsShown(), "second open did not toggle closed")
        ui.copyPopup.Show(ui.copyButton)
        Snapshot(hand .. ":toggle-reopen")
        ui.SelectHand(hand == "main" and "off" or "main")
        assert(not frame:IsShown(), "source change did not invalidate popup")
        Snapshot(hand .. ":source-change")
    end
    -- Execute real category copy and history using distinct source/destination values.
    ui.SelectHand("main")
    ui.copyPopup.Show(ui.copyButton)
    Control("categories.none"):Click()
    local layout = Control("category.layout")
    layout:SetChecked(true)
    layout:Click()
    Control("target.off"):Click()
    core.SwingTimer.Set("main", "width", 333)
    core.SwingTimer.Set("off", "width", 444)
    core.SwingTimer.Set("off", "x", 91)
    core.SwingTimer.Set("off", "fontSize", 21)
    M.ClearHistory()
    local before = F.CopySnapshot(env.MSUF_DB)
    Control("run"):Click()
    assert(core.SwingTimer.Get("off", "width") == 333 and core.SwingTimer.Get("off", "x") == 91
        and core.SwingTimer.Get("off", "fontSize") == 21, "copy category/filter route drift")
    assert(not ui.copyPopup.GetPopup():IsShown(), "successful copy stayed open")
    assert(M.Undo() and F.Equal(before, env.MSUF_DB), "copy undo drift")
    assert(M.Redo() and core.SwingTimer.Get("off", "width") == 333, "copy redo drift")
    local sourceValues = { width = 333, height = 17, scale = 125, opacity = 75, texture = "",
        backgroundTexture = "", backgroundOpacity = 60, borderSize = 3, fill = "remaining", direction = "LEFT",
        color = { 0.1, 0.2, 0.3 }, backgroundColor = { 0.2, 0.3, 0.4 }, borderColor = { 0.3, 0.4, 0.5 },
        title = false, time = false, font = "", fontSize = 23, outline = "THICKOUTLINE", textAlign = "RIGHT",
        textX = 13, textY = 17, textColor = { 0.4, 0.5, 0.6 }, visibility = "combat", display = "text",
        reachCheck = true, reachOpacity = 35, reachColor = { 0.5, 0.6, 0.7 } }
    local keys = {}
    for key in pairs(sourceValues) do keys[#keys + 1] = key end
    table.sort(keys)
    local function Settings(state)
        for _, hand in ipairs({ "main", "off", "ranged" }) do
            for _, key in ipairs(keys) do
                local value = core.SwingTimer.Get(hand, key)
                if type(value) == "table" then value = table.concat(value, ",") end
                Row(state, hand, key, value)
            end
        end
    end
    for _, category in ipairs({ "layout", "appearance", "text", "behavior" }) do
        for _, target in ipairs({ "off", "ranged", "all" }) do
            env.MSUF_DB.swingTimers.off = nil
            env.MSUF_DB.swingTimers.ranged = nil
            for _, key in ipairs(keys) do core.SwingTimer.Set("main", key, sourceValues[key]) end
            ui.copyPopup.Hide()
            ui.copyPopup.Show(ui.copyButton)
            Control("categories.none"):Click()
            local cb = Control("category." .. category)
            cb:SetChecked(true)
            cb:Click()
            Control("target." .. target):Click()
            Settings(category .. ":" .. target .. ":before")
            Control("run"):Click()
            Settings(category .. ":" .. target .. ":after")
        end
    end
    -- Reset the small layout history scenario before checking its refusal/late callback.
    core.SwingTimer.Set("main", "width", 333)
    core.SwingTimer.Set("off", "width", 333)
    ui.copyPopup.Show(ui.copyButton)
    Control("categories.none"):Click()
    layout:SetChecked(true)
    layout:Click()
    Control("target.off"):Click()
    core.Util.InCombat("PLAYER_REGEN_DISABLED")
    env.InCombatLockdown = function() return false end
    before = F.CopySnapshot(env.MSUF_DB)
    M.ClearHistory()
    Control("run"):Click()
    assert(F.Equal(before, env.MSUF_DB) and not M.Undo(), "combat copy/refusal history drift")
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    Snapshot("combat-refusal")
    ui.copyPopup.Hide()
    -- Cached controls survive page/window close and follow the current profile.
    mw:Select("home")
    assert(mw:Select("swingtimers"))
    ui.copyPopup.Show(ui.copyButton)
    Snapshot("page-reopen")
    local profile = env.MSUF_DB
    env.MSUF_DB = F.CopySnapshot(profile)
    env.MSUF_DB.swingTimers.main.width = 555
    Control("run"):Click()
    assert(core.SwingTimer.Get("off", "width") == 555 and profile.swingTimers.off.width == 333,
        "late copy callback captured old profile")
    env.MSUF_DB = profile
    env.MSUF_InitProfiles = initProfiles
    initProfiles()
    local active = env.MSUF_ActiveProfile
    local alternate = F.CopySnapshot(env.MSUF_DB)
    alternate.swingTimers.main.width = 666
    env.MSUF_GlobalDB.profiles["Swing alternate"] = alternate
    assert(env.MSUF_SwitchProfile("Swing alternate") == true, "real Swing profile switch failed")
    Snapshot("real-profile-switch")
    Control("run"):Click()
    assert(core.SwingTimer.Get("off", "width") == 666, "cached popup callback ignored the real profile switch")
    assert(env.MSUF_SwitchProfile(active) == true, "real Swing profile switch back failed")
    Snapshot("real-profile-switch-back")
    env.MSUF_InitProfiles = function() end
    ui.copyPopup.Hide()
    ui.copyPopup.Show(ui.copyButton)
    M.HideSlashMenuAndMinibar(mw.win)
    -- The harness does not propagate ancestor visibility to child OnHide scripts.
    MenuWorld.FireScript(ui.section, "OnHide")
    assert(not ui.copyPopup.GetPopup():IsShown(), "window close left copy popup open")
    assert(M.Open("swingtimers") ~= false)
    mw:RunTimers()
    ui.copyPopup.Show(ui.copyButton)
    Snapshot("window-reopen")
end
Verify("swing-copy")
