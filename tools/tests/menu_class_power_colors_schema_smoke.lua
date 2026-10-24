-- Class Power Colors retain all native owners, resource selection and profile transactions.
-- Standard args: <root> <flavor>; optional authentic parent/page overrides are diagnostic.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local parent, candidate = arg[3], arg[4]
assert(arg[5] == nil or arg[5] == "--focused-cancel", "unknown ClassPower smoke mode")
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Resources.lua"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    if type(value) == "function" then return "<function>" end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget:" .. tostring(ids[value] or value:GetObjectType()) end
    seen = seen or {} assert(not seen[value], "cyclic observation") seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key, ids, seen) .. "=" .. Encode(value[key], ids, seen) end
    seen[value] = nil return "{" .. table.concat(out, ",") .. "}"
end
local function Restore(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end Restore(dst[key], value)
        else dst[key] = value end
    end
end
local function InstallNativeInputs(world)
    local native = world.env
    local power = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))().PT
    local enum = native.Enum
    native.Enum = setmetatable({ PowerType = { Mana = power.MANA, Rage = power.RAGE,
        Focus = 2, Energy = power.ENERGY, ComboPoints = power.COMBO } }, { __index = enum })
    native.UnitPowerType = function() return power.RAGE, "RAGE" end
    native.UnitPower = function() return 0 end
    native.UnitPowerMax = function(_, value) return (value == nil or value == power.RAGE) and 100 or 5 end
    native.UnitPowerDisplayMod = function() return 1 end
    native.UnitHasVehicleUI = function() return false end
    native.PlayerVehicleHasComboPoints = function() return false end
    native.GetShapeshiftFormID = function() return nil end
    local function Number(value)
        assert(type(value) == "number" and value == value and value - value == 0, "native finite numeric input required")
        return value
    end
    local function Abbreviate(value)
        value = Number(value)
        if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
        if value >= 1000 then return string.format("%.1fK", value / 1000) end
        return string.format("%d", value)
    end
    native.AbbreviateNumbers, native.AbbreviateLargeNumbers = Abbreviate, Abbreviate
    native.BreakUpLargeNumbers = function(value) return string.format("%d", math.floor(Number(value))) end
    native.RAID_CLASS_COLORS = {}
    for index, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
        "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
        native.RAID_CLASS_COLORS[token] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
    end
    local tocPath = root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. world.client.tocSuffix .. ".toc"
    local toc = assert(io.open(tocPath, "rb")) local metadata = toc:read("*a") assert(toc:close())
    local prefix = metadata:match("\n## X%-MSUF%-UnitFrames%-Prefix:%s*([^\r\n]+)")
    assert(prefix == "MSUF", "native frame-name metadata fixture drift")
    local getMetadata = native.C_AddOns.GetAddOnMetadata
    native.C_AddOns.GetAddOnMetadata = function(addon, field)
        if addon == "MidnightSimpleUnitFrames" and field == "X-MSUF-UnitFrames-Prefix" then return prefix end
        return getMetadata(addon, field)
    end
    native.GetAddOnMetadata = native.C_AddOns.GetAddOnMetadata
    native.TotemFrame = native.CreateFrame("Frame", nil, native.UIParent)
end
local function InstallColorSelect(world)
    local methods = world.widgets.Methods
    for _, part in ipairs({ "Wheel", "Value" }) do
        local key = part
        methods["SetColor" .. key .. "Texture"] = function(self, texture) self["color" .. key] = texture end
        methods["SetColor" .. key .. "ThumbTexture"] = function(self, path)
            local texture = self:CreateTexture() texture:SetTexture(path) self["color" .. key .. "Thumb"] = texture
        end
        methods["GetColor" .. key .. "ThumbTexture"] = function(self) return self["color" .. key .. "Thumb"] end
    end
    methods.SetColorRGB = function(self, red, green, blue)
        self.nativeRGB = { red, green, blue } MenuWorld.FireScript(self, "OnColorSelect", red, green, blue)
    end
end

local specs = {
    { "class_power.editor.resource_selector", "dropdown", true },
    { "class_power.editor.foreground_color", "color" },
    { "class_power.editor.background_color", "color" },
    { "class_power.editor.reset_foreground", "button" },
    { "class_power.editor.reset_background", "button" },
    { "class_power.resource_slots.mode", "dropdown", true },
    { "class_power.full_resource.enabled", "toggle", true },
    { "class_power.full_resource.color", "color" },
}
for slot = 1, 10 do specs[#specs + 1] = { "class_power.resource_slots.slot." .. slot, "color" } end
specs[#specs + 1] = { "class_power.resource_slots.reset", "button" }
specs[#specs + 1] = { "class_power.full_resource.reset", "button" }
local function Replay(width, original)
    local loaded, constructedColors, constructedButtons = 0, {}, {}
    local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
        clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = InstallNativeInputs,
        beforeOptions = function(world)
            InstallColorSelect(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if path:gsub("\\", "/") == root .. "/" .. target then
                    loaded = loaded + 1
                    local widgets, theme = world.core.MSUF2.Widgets, world.core.MSUF2.Theme
                    local color, button = widgets.Color, theme.Button
                    widgets.Color = function(...)
                        local owner = color(...) constructedColors[#constructedColors + 1] = owner return owner
                    end
                    theme.Button = function(...)
                        local owner = button(...) constructedButtons[#constructedButtons + 1] = owner return owner
                    end
                    if original then path = assert(parent) elseif candidate and candidate ~= "-" then path = candidate end
                end
                return load(self, path, addon, namespace)
            end
        end })
    assert(loaded == 1, "ClassPower Resources provider load census drift")
    local M, env, core = mw.M, mw.env, mw.core
    local F, ids, rows, calls, clicked = core.ProfileFields, {}, {}, {}, {}
    local function Snapshot() local value, ok, why = F.CopySnapshot(env.MSUF_DB) assert(ok, why) return value end
    local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function SameDB(value, label) assert(Equal(value, env.MSUF_DB), "ClassPower whole-profile drift: " .. label) end
    local function Add(label, ...) rows[#rows + 1] = label .. "\t" .. Encode(Pack(...), ids) end
    local function Settle()
        mw:RunTimers()
        for _, frame in ipairs(mw.world.widgets.frames) do
            for _, key in ipairs({ "_msuf2AlphaFade", "_msuf2AlphaScale" }) do
                local group = frame[key]
                if group and group:IsPlaying() and group:GetScript("OnFinished") then
                    group:Finish() MenuWorld.FireScript(group, "OnFinished")
                end
            end
            for _, motion in ipairs(frame._msuf2SelectionMotions or {}) do
                local driver = motion.driver
                for _ = 1, 120 do
                    if not (driver and driver:GetScript("OnUpdate")) then break end
                    MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                end
                assert(not (driver and driver:GetScript("OnUpdate")), "ClassPower selection did not settle")
            end
        end
        mw:RunTimers()
    end
    local function Shown(widget)
        while widget do if not widget:IsShown() then return false end widget = widget:GetParent() end return true
    end
    local function ID(path) return M.ControlMeta("opt_colors", "advanced", path).controlId end
    local function Item(path)
        return assert(assert(M.RuntimeControlCatalog.Get(ID(path)), "ClassPower catalog owner missing: " .. path).widget)
    end
    local function Choose(widget, value)
        widget:Click("LeftButton") Settle()
        if not widget:IsEnabled() or M.IsConfigCombatLocked() then return false end
        local match
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame._msuf2Owner == widget and frame._msuf2Value == value and Shown(frame)
                and not frame._msuf2DropdownDisabled then match = frame end
        end
        assert(match and match:GetScript("OnClick"), "ClassPower real dropdown option missing: " .. tostring(value))
        match:Click("LeftButton") Settle() clicked[ids[widget]] = true return true
    end
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    assert(M.cache.opt_colors == nil, "ClassPower cold page was already built")
    assert(mw:Select("opt_colors"))
    local category = Item("preview.scope.selector")
    local resourceButton
    for _, button in ipairs(category.buttons) do if button._msuf2Value == "resources" then resourceButton = button end end
    assert(resourceButton and Shown(resourceButton), "ClassPower real Resources category absent")
    resourceButton:Click("LeftButton") Settle()
    local entry = assert(M.cache.opt_colors)
    local section = assert(entry.sections.colors_class_power)
    local disclosure = assert(section._msuf2CollapsibleEntry)
    if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
    assert(disclosure.open and Shown(section) and section._msuf2Width == width, "ClassPower real section layout drift")
    ids[section], ids[entry.wrapper], ids[disclosure.header] = "colors_class_power", "opt_colors.wrapper",
        assert(disclosure.header._msuf2RuntimeControlRecord).controlId
    local controls, expected = {}, {}
    for _, spec in ipairs(specs) do expected[ID(spec[1])] = spec end
    local prefix = ID("class_power") .. "."
    local count = 0
    for _, item in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local record = assert(M.RuntimeControlCatalog.Get(item.controlId), "ClassPower runtime record missing: " .. item.controlId)
        if record.pageKey == "opt_colors" and record.controlId:sub(1, #prefix) == prefix then
            local spec = assert(expected[record.controlId], "Unexpected ClassPower native owner: " .. record.controlId)
            local widget = assert(record.widget)
            assert(not controls[spec[1]] and widget:GetParent() == section and record.kind == spec[2],
                "ClassPower native owner identity/kind/parent drift")
            controls[spec[1]], ids[widget], count = widget, record.controlId, count + 1
            if spec[2] ~= "button" then
                assert(widget._msuf2CommandAction and widget._msuf2CommandAction.get and widget._msuf2CommandAction.set,
                    "ClassPower native command missing")
            end
            if not original or spec[3] then
                local declaration = assert(widget._msuf2ControlSchema, "ClassPower native declaration missing: " .. spec[1])
                assert(declaration.id == record.controlId and declaration.kind == spec[2], "ClassPower declaration identity drift")
                if not spec[3] then
                    assert(declaration.scope == "colors" and declaration.applyDomain == "classPowerColors", "ClassPower domain drift")
                end
            end
        end
    end
    assert(count == 20, "ClassPower twenty-owner census drift")
    for _, spec in ipairs(specs) do assert(controls[spec[1]], "ClassPower expected native owner absent: " .. spec[1]) end
    local colorCount, buttonCount, dropdownCount = 0, 0, 0
    for _, widget in ipairs(constructedColors) do if widget:GetParent() == section then colorCount = colorCount + 1 end end
    for _, widget in ipairs(constructedButtons) do
        if widget:GetParent() == section and widget._msuf2RuntimeControlRecord
            and expected[widget._msuf2RuntimeControlRecord.controlId] then
            local spec = expected[widget._msuf2RuntimeControlRecord.controlId]
            if spec[2] == "button" then buttonCount = buttonCount + 1
            else
                assert(spec[2] == "dropdown", "ClassPower unexpected native Button-backed owner: " .. spec[1])
                dropdownCount = dropdownCount + 1
            end
        end
    end
    assert(colorCount == 13 and buttonCount == 4 and dropdownCount == 2, "ClassPower native constructor census drift")
    if not original then
        local header = assert(disclosure.header._msuf2ControlSchema, "ClassPower native header declaration missing")
        assert(header.id == ids[disclosure.header] and header.scope == "colors" and header.applyDomain == "sectionNavigation",
            "ClassPower native header declaration drift")
    end
    local function Paint(widget)
        if not widget then return {} end
        if widget.GetObjectType then
            assert(widget:GetObjectType() == "Texture", "ClassPower native swatch texture drift")
            return { Pack(widget:GetVertexColor()), widget:IsShown(), widget:GetAlpha(), widget.colorTexture }
        end
        assert(widget.L and widget.M and widget.R, "ClassPower native composite swatch drift")
        return { Paint(widget.L), Paint(widget.M), Paint(widget.R) }
    end
    local function Observe(tag)
        for _, spec in ipairs(specs) do
            local widget, record = controls[spec[1]], assert(M.RuntimeControlCatalog.Get(ID(spec[1])))
            assert(record.widget == widget and widget._msuf2RuntimeControlRecord == record, "ClassPower warm physical owner drift")
            local command = widget._msuf2CommandAction
            local model = command and command.get and Pack(command.get())
            local display = spec[2] == "color" and Pack(widget:GetRGB()) or spec[2] == "dropdown" and Pack(widget:GetValue())
                or spec[2] == "toggle" and Pack(widget:GetChecked()) or nil
            if Shown(widget) and spec[2] ~= "button" then assert(Equal(model, display), "ClassPower native display/getter drift") end
            local points = {} for index = 1, widget:GetNumPoints() do points[index] = Pack(widget:GetPoint(index)) end
            local label = widget._msuf2Title or widget._label or widget._msuf2Label
            Add(tag .. ":" .. spec[1], record.controlId, record.pageKey, record.kind, record.label, record.settingKey,
                record.classification, record.actionKey, record.searchSettingKeys, record.searchSettingKeyPatterns,
                widget._msuf2SearchMeta, model, display, points, Pack(widget:GetSize()), widget:IsShown(), widget:IsEnabled(),
                widget:GetAlpha(), label and Pack(label:GetText(), label:GetTextColor()),
                Paint(widget._msuf2Swatch))
        end
        Add(tag .. ":header", disclosure.open, section:IsShown(), section:GetHeight(), disclosure.arrow.rotation)
        Add(tag .. ":state", Snapshot(), M.GetHistoryState(), calls, M.colorsCPToken,
            M.ColorsPage.GetClassPowerRGB(M.colorsCPToken), M.ColorsPage.GetClassPowerBgRGB(M.colorsCPToken))
    end
    local function Refresh(tag)
        local before = Snapshot() M.Refresh() Settle() SameDB(before, tag .. ":refresh") Observe(tag)
    end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, Pack(...) } return fn(...)
        end end
    end
    local function Panel(widget)
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.owner == widget and frame.compactHex and Shown(frame) then return frame end
        end
    end
    local function OpenPicker(widget)
        widget:Click("LeftButton") Settle()
        local panel = Panel(widget)
        if not widget:IsEnabled() or M.IsConfigCombatLocked() then assert(not panel, "ClassPower refused picker opened") return end
        assert(panel and panel.done and panel.cancel, "ClassPower native picker owner absent")
        if not panel._classPowerVisibleFixture then
            MenuWorld.FireVisibilityScripts(panel) panel._classPowerVisibleFixture = true
        end
        return panel
    end
    local function Hex(panel, value)
        panel.compactHex:SetText(value) MenuWorld.FireScript(panel.compactHex, "OnTextChanged", true)
        MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle()
    end
    local foreground = controls["class_power.editor.foreground_color"]
    local beforeCold, coldHistory = Snapshot(), Encode(M.GetHistoryState(), ids)
    local panel = OpenPicker(foreground)
    assert(Equal(beforeCold.general, env.MSUF_DB.general), "ClassPower cold picker changed resource settings")
    assert(Encode(M.GetHistoryState(), ids) == coldHistory, "ClassPower cold picker created history")
    Observe("cold-picker-open") panel.cancel:Click("LeftButton") Settle()
    local warm = Snapshot() panel = OpenPicker(foreground) panel.cancel:Click("LeftButton") Settle()
    SameDB(warm, "warm picker cancel")
    assert(M.SyncExternalHistoryState(), "ClassPower cold picker history baseline unavailable")
    local factory = Snapshot()
    local selector, mode, full = controls[specs[1][1]], controls[specs[6][1]], controls[specs[7][1]]
    local tokens = selector.values
    assert(type(tokens) == "table" and #tokens > 0, "ClassPower native resource list absent")
    for _, option in ipairs(tokens) do
        assert(type(option) == "table" and type(option.value) == "string" and type(option.text) == "string",
            "ClassPower real dropdown values shape drift")
    end
    local function Select(token)
        local before, history = Snapshot(), Encode(M.GetHistoryState(), ids)
        assert(Choose(selector, token))
        assert(M.colorsCPToken == token and selector:GetValue() == token, "ClassPower selected token routing drift")
        SameDB(before, "ephemeral resource selection")
        assert(Encode(M.GetHistoryState(), ids) == history, "ClassPower selector changed history")
    end
    local function Setup(token, absent)
        Restore(env.MSUF_DB, factory)
        local g, bars = env.MSUF_DB.general, env.MSUF_DB.bars
        g.classPowerColorOverrides = { fixture_unrelated = { 0.2, 0.3, 0.4 } }
        g.classPowerBgColorOverrides = { fixture_unrelated = { 0.7, 0.8, 0.9 } }
        bars.classPowerSlotColorModes, bars.classPowerComboPointColorMode, bars.classPowerFullColorEnabled = nil, nil, nil
        g.classPowerFixtureExtension = { enabled = false, amount = 0 }
        if absent then g.classPowerColorOverrides, g.classPowerBgColorOverrides = nil, nil end
        M.Refresh() Settle() M.ClearHistory()
        assert(M.SyncExternalHistoryState(), "ClassPower restored fixture history baseline unavailable")
        Select(token) M.ClearHistory() calls = {} Refresh("setup:" .. token .. ":" .. tostring(absent))
    end
    -- This optional mode adds real changed-HEX Cancel cases; the old full matrix below is untouched.
    if arg[5] == "--focused-cancel" then
        local db, general, bars = env.MSUF_DB, env.MSUF_DB.general, env.MSUF_DB.bars
        local selectorCommand = assert(selector._msuf2CommandAction)
        local states = { "missing", "false", "zero", "partial", "configured" }
        local offered, primary, maximum = {}, nil, -1
        for _, option in ipairs(tokens) do
            assert(not offered[option.value], "ClassPower focused duplicate offered resource")
            offered[option.value] = true
            local slots = M.ColorsPage.ClassPowerSlotCount(option.value)
            assert(slots >= 0 and slots <= 10 and slots == math.floor(slots), "ClassPower focused slot count drift")
            if slots > maximum then primary, maximum = option.value, slots end
        end
        assert(primary and maximum > 0, "ClassPower focused offered slot family missing")
        if flavor == "Mainline" then assert(maximum == 10, "ClassPower focused Mainline thirteen-owner coverage missing") end
        local function Paths(token)
            local paths = { "class_power.editor.foreground_color", "class_power.editor.background_color" }
            local slots = M.ColorsPage.ClassPowerSlotCount(token)
            if slots > 0 then
                paths[#paths + 1] = "class_power.full_resource.color"
                for slot = 1, slots do paths[#paths + 1] = "class_power.resource_slots.slot." .. slot end
            end
            return paths
        end
        local function View()
            local view = {}
            for _, spec in ipairs(specs) do
                local widget, record = controls[spec[1]], M.RuntimeControlCatalog.Get(ID(spec[1]))
                assert(record and record.widget == widget and widget._msuf2RuntimeControlRecord == record,
                    "ClassPower focused physical owner changed")
                local command = widget._msuf2CommandAction
                local model = command and command.get and Pack(command.get())
                local display = spec[2] == "color" and Pack(widget:GetRGB()) or spec[2] == "dropdown" and Pack(widget:GetValue())
                    or spec[2] == "toggle" and Pack(widget:GetChecked()) or nil
                if Shown(widget) and spec[2] ~= "button" then
                    assert(Equal(model, display), "ClassPower focused dependent native display/getter drift: " .. spec[1])
                end
                view[spec[1]] = { model, display, Paint(widget._msuf2Swatch), widget:IsShown(), widget:IsEnabled() }
            end
            return view
        end
        local function Seed(token, state, key)
            Setup(token, true)
            local sentinel = { enabled = false, amount = 0, [0] = "preserve", nested = { false, 0 } }
            general.classPowerFixtureExtension = sentinel
            if state == "false" or state == "zero" then
                local value = state == "zero" and 0 or false
                general.classPowerColorOverrides, general.classPowerBgColorOverrides = value, value
                bars.classPowerSlotColorModes, bars.classPowerComboPointColorMode, bars.classPowerFullColorEnabled = value, value, value
            elseif state == "partial" or state == "configured" then
                local configured = state == "configured"
                local function Values()
                    if configured then return { 0, .28, .39, [0] = "keep", extra = { false, 0 } } end
                    return { [1] = false, [2] = 0, [0] = "keep", extra = { false, 0 } }
                end
                general.classPowerColorOverrides = { [key] = Values(), fixture_unrelated = Values(), [0] = "keep" }
                general.classPowerBgColorOverrides = { [token] = Values(), fixture_unrelated = Values(), [0] = "keep" }
                bars.classPowerSlotColorModes = { fixture_unrelated = { false, 0 }, [0] = "keep" }
                bars.classPowerSlotColorModes[token] = configured and "custom" or false
                bars.classPowerComboPointColorMode = configured and "custom" or { unknown = { false, 0 } }
                bars.classPowerFullColorEnabled = { [token] = configured, fixture_unrelated = { false, 0 }, [0] = "keep" }
            end
            local before = Snapshot() M.Refresh() Settle() SameDB(before, "focused seed/read-only refresh:" .. state)
            assert(env.MSUF_DB == db and db.general == general and db.bars == bars,
                "ClassPower focused setup replaced profile aliases")
            for slot = 1, 10 do
                assert(controls["class_power.resource_slots.slot." .. slot]:IsShown()
                    == (slot <= M.ColorsPage.ClassPowerSlotCount(token)), "ClassPower focused real slot gate drift")
            end
            assert(full:IsShown() == (M.ColorsPage.ClassPowerSlotCount(token) > 0), "ClassPower focused real Full gate drift")
            assert(M.ClearHistory() and M.SyncExternalHistoryState(), "ClassPower focused history baseline unavailable")
            return sentinel
        end
        local completed, primaryCases, familyCases, selectorCases, seen = 0, 0, 0, 0, {}
        local function RunCancel(path, token, state, externalToken)
            local slot = tonumber(path:match("%.slot%.(%d+)$"))
            local background = path == "class_power.editor.background_color"
            local fullColor = path == "class_power.full_resource.color"
            local key = slot and token .. "_" .. slot or fullColor and token .. "_FULL" or token
            local sentinel = Seed(token, state, key)
            local foreignView
            if externalToken then Select(externalToken) foreignView = View() Select(token) end
            local widget, record = controls[path], M.RuntimeControlCatalog.Get(ID(path))
            local command = assert(widget._msuf2CommandAction)
            local before, history, view = Snapshot(), M.GetHistoryState(), View()
            local model, wanted = Pack(command.get()), Pack(25 / 255, 94 / 255, 166 / 255)
            local label = path .. ":" .. token .. ":" .. state .. (externalToken and ":external-selector" or "")
            assert(Shown(widget) and widget:IsEnabled() and not Equal(model, wanted), "ClassPower focused input is vacuous: " .. label)
            local active = assert(OpenPicker(widget), "ClassPower focused native Open failed")
            assert(active.owner == widget and Shown(active.compactHex) and Shown(active.blocker),
                "ClassPower focused native owner/HEX/modal visibility drift")
            SameDB(before, "focused native Open:" .. label)
            assert(selectorCommand.get() == token and selector:GetValue() == token,
                "ClassPower focused actual Open selector drift")
            calls = {} Hex(active, "195EA6")
            local overrides = general[background and "classPowerBgColorOverrides" or "classPowerColorOverrides"]
            assert(type(overrides) == "table" and Equal(overrides[key], { 25 / 255, 94 / 255, 166 / 255 }),
                "ClassPower focused HEX wrote wrong resource/slot: " .. label)
            assert(Equal(Pack(command.get()), wanted) and Equal(Pack(widget:GetRGB()), wanted),
                "ClassPower focused native HEX model/display did not change: " .. label)
            assert(not Equal(before, env.MSUF_DB) and #calls > 0, "ClassPower focused HEX made no real write/apply: " .. label)
            if slot then assert(M.ColorsPage.GetClassPowerSlotMode(token) == "custom", "ClassPower focused slot did not auto-select custom") end
            if fullColor then assert(bars.classPowerFullColorEnabled[token] == true, "ClassPower focused Full did not auto-enable") end
            local edited = Snapshot()
            if externalToken then
                -- Explicit external menu-state API mutation, never a physical click through the real modal blocker.
                M.SetMenuStateValue("colorsCPToken", externalToken)
                M.RequestRefresh(nil, "fixture-external-class-power-token") Settle()
                assert(selectorCommand.get() == externalToken and selector:GetValue() == externalToken,
                    "ClassPower focused external selector did not reach the actual command")
                SameDB(edited, "focused external menu state must not mutate profile")
            end
            local callCount = #calls
            active.cancel:Click("LeftButton") Settle()
            assert(not Shown(active), "ClassPower focused native Cancel did not close picker")
            SameDB(before, "focused HEX Cancel:" .. label)
            assert(Equal(history, M.GetHistoryState()) and not M.Undo() and not M.Redo(),
                "ClassPower focused Cancel changed/consumed history: " .. label)
            SameDB(before, "focused history probes:" .. label)
            assert(env.MSUF_DB == db and db.general == general and db.bars == bars
                and general.classPowerFixtureExtension == sentinel and M.cache.opt_colors == entry,
                "ClassPower focused Cancel replaced unrelated profile/page owners")
            assert(record == M.RuntimeControlCatalog.Get(ID(path)) and record.widget == widget
                and widget._msuf2CommandAction == command, "ClassPower focused Cancel replaced the native input owner")
            local applies = 0
            for i = callCount + 1, #calls do if calls[i][1] == "RequestClassPowerDomains" then applies = applies + 1 end end
            assert(applies == 1, "ClassPower focused Cancel did not request exactly one specialized CP apply")
            if externalToken then
                assert(selectorCommand.get() == externalToken and selector:GetValue() == externalToken,
                    "ClassPower focused Cancel restored a stale selector")
                assert(Equal(foreignView, View()), "ClassPower focused Cancel did not repaint current external selection")
                Select(token) selectorCases = selectorCases + 1
            end
            assert(selectorCommand.get() == token and selector:GetValue() == token and Equal(view, View()),
                "ClassPower focused Cancel did not restore native/dependent model/display: " .. label)
            Add("focused-cancel:" .. label, before, Snapshot(), history, M.GetHistoryState(), view, View(), calls)
            completed, seen[path] = completed + 1, true
        end
        for _, path in ipairs(Paths(primary)) do
            for _, state in ipairs(states) do RunCancel(path, primary, state) primaryCases = primaryCases + 1 end
        end
        assert(primaryCases == (3 + maximum) * #states, "ClassPower focused primary raw-state matrix incomplete")
        for _, option in ipairs(tokens) do
            if option.value ~= primary then
                for _, path in ipairs(Paths(option.value)) do
                    RunCancel(path, option.value, "partial") familyCases = familyCases + 1
                end
            end
        end
        local other
        for _, option in ipairs(tokens) do if option.value ~= primary then other = option.value break end end
        assert(other, "ClassPower focused external-selection family absent")
        RunCancel("class_power.editor.foreground_color", primary, "partial", other)
        local reached = 0 for _ in pairs(seen) do reached = reached + 1 end
        assert(reached == 3 + maximum and selectorCases == 1 and completed == primaryCases + familyCases + selectorCases,
            "ClassPower focused native owner/family/selection coverage incomplete")
        Add("focused-cancel-summary", reached, primaryCases, familyCases, selectorCases, completed, #tokens, width)
        print("CP_FOCUSED_CANCEL_COVERAGE " .. flavor .. " width=" .. width .. " owners=" .. reached
            .. " primary=" .. primaryCases .. " families=" .. familyCases .. " selector=" .. selectorCases .. " total=" .. completed)
        return rows
    end
    local function History(before, after, tag)
        local undone = M.Undo() Settle()
        if undone then SameDB(before, tag .. ":undo") assert(M.Redo(), "ClassPower exact pending Redo missing") Settle()
        else SameDB(after, tag .. ":no-undo") assert(not M.Redo(), "ClassPower unexpected Redo") end
        SameDB(after, tag .. ":redo") Add(tag .. ":history", undone, M.GetHistoryState())
    end
    local function Color(path, token, expectedKey, background, absent)
        Setup(token, absent)
        local widget = controls[path]
        assert(Shown(widget), "ClassPower chosen color is hidden: " .. path)
        local active = OpenPicker(widget) M.ClearHistory()
        local before = Snapshot() calls = {}
        Hex(active, "195EA6") active.done:Click("LeftButton") Settle() clicked[ids[widget]] = true
        local overrides = env.MSUF_DB.general[background and "classPowerBgColorOverrides" or "classPowerColorOverrides"]
        assert(type(overrides) == "table" and Equal(overrides[expectedKey], { 25 / 255, 94 / 255, 166 / 255 }),
            "ClassPower native color wrote wrong selected token/slot")
        assert(not Equal(before, env.MSUF_DB) and #calls > 0, "ClassPower native color did no runtime work")
        if path == "class_power.full_resource.color" then
            assert(env.MSUF_DB.bars.classPowerFullColorEnabled[token] == true, "ClassPower full color did not enable current token")
        elseif path:find("class_power.resource_slots.slot.", 1, true) then
            assert(env.MSUF_DB.bars.classPowerSlotColorModes[token] == "custom", "ClassPower slot color did not choose custom mode")
        end
        local after = Snapshot() Observe("color:" .. token .. ":" .. path) History(before, after, path)
    end
    local counts, exercised = {}, {}
    for _, option in ipairs(tokens) do
        local token = option.value
        Setup(token, true)
        local count = M.ColorsPage.ClassPowerSlotCount(token) counts[count] = true
        for slot = 1, 10 do
            assert(controls["class_power.resource_slots.slot." .. slot]:IsShown() == (slot <= count), "ClassPower visible slot gate drift")
        end
        assert(full:IsShown() == (count > 0), "ClassPower full visibility gate drift")
        Observe("resource:" .. token)
        if not exercised[count] or token == "COMBO_POINTS" then
        exercised[count] = true
        Color("class_power.editor.foreground_color", token, token, false, true)
        Color("class_power.editor.background_color", token, token, true, false)
        if count > 0 then
            Color("class_power.full_resource.color", token, token .. "_FULL", false, true)
            for slot = 1, count do
                local expected = token == "COMBO_POINTS" and "COMBO_POINTS_" .. slot or token .. "_" .. slot
                Color("class_power.resource_slots.slot." .. slot, token, expected, false, false)
            end
            for _, value in ipairs({ "ramp", "custom", "default" }) do
                Setup(token) local before = Snapshot() calls = {} assert(Choose(mode, value))
                assert(M.ColorsPage.GetClassPowerSlotMode(token) == value, "ClassPower native mode routing drift")
                local after = Snapshot() Observe("mode:" .. token .. ":" .. value) History(before, after, "mode:" .. value)
            end
            Setup(token) local before = Snapshot() full:Click("LeftButton") Settle() clicked[ids[full]] = true
            assert(env.MSUF_DB.bars.classPowerFullColorEnabled[token] == true, "ClassPower native full switch routing drift")
            local after = Snapshot() Observe("full-toggle:" .. token) History(before, after, "full-toggle")
        end
        for _, path in ipairs({ "class_power.editor.reset_foreground", "class_power.editor.reset_background",
            "class_power.resource_slots.reset", "class_power.full_resource.reset" }) do
            if count > 0 or path:find("editor", 1, true) then
                Setup(token)
                local g = env.MSUF_DB.general
                g.classPowerColorOverrides[token], g.classPowerBgColorOverrides[token] = { 0, 0.5, 1 }, { 0.4, 0, 0.8 }
                g.classPowerColorOverrides[token .. "_FULL"] = { 1, 0, 0 }
                for slot = 1, count do
                    g.classPowerColorOverrides[token == "COMBO_POINTS" and "COMBO_POINTS_" .. slot or token .. "_" .. slot] = { 0, 0, 1 }
                end
                env.MSUF_DB.bars.classPowerFullColorEnabled = { [token] = true }
                M.ClearHistory() Refresh("reset-seed")
                local before = Snapshot() calls = {} controls[path]:Click("LeftButton") Settle() clicked[ID(path)] = true
                if path:find("reset_foreground", 1, true) then assert(g.classPowerColorOverrides[token] == nil)
                elseif path:find("reset_background", 1, true) then assert(g.classPowerBgColorOverrides[token] == nil)
                elseif path == "class_power.full_resource.reset" then
                    assert(g.classPowerColorOverrides[token .. "_FULL"] == nil and g.classPowerFixtureExtension.enabled == false)
                    assert(env.MSUF_DB.bars.classPowerFullColorEnabled[token] == nil)
                else
                    for slot = 1, count do
                        assert(g.classPowerColorOverrides[token == "COMBO_POINTS" and "COMBO_POINTS_" .. slot or token .. "_" .. slot] == nil)
                    end
                end
                assert(Equal(g.classPowerColorOverrides.fixture_unrelated, { 0.2, 0.3, 0.4 }), "ClassPower reset deleted unrelated resource")
                local after = Snapshot() Observe("reset:" .. token .. ":" .. path) History(before, after, path)
            end
        end
        end
    end
    if flavor == "Mainline" then assert(counts[10] and counts[7] and counts[5] and counts[4] and counts[0], "ClassPower slot-count coverage drift") end
    Setup("COMBO_POINTS")
    env.MSUF_DB.general.classPowerColorOverrides.COMBO_POINTS = { false, 0, 1 }
    local malformed = Snapshot() Refresh("explicit-false-zero") SameDB(malformed, "malformed RGB read-only")
    env.MSUF_DB.general.classPowerColorOverrides.COMBO_POINTS = { 0, 0, 1 }
    Refresh("valid-zero") assert(Equal(Pack(foreground:GetRGB()), Pack(0, 0, 1)), "ClassPower zero component lost")
    for _, locked in ipairs({ false, true }) do
        Setup("COMBO_POINTS")
        local active = OpenPicker(foreground) M.ClearHistory() local before, history = Snapshot(), Encode(M.GetHistoryState(), ids)
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return locked end
        calls = {} foreground:Click("LeftButton") Hex(active, "D42B19") full:Click("LeftButton") Settle()
        SameDB(before, "ClassPower event/lockdown refusal")
        assert(#calls == 0 and Encode(M.GetHistoryState(), ids) == history and not M.Undo() and not M.Redo(),
            "ClassPower refused input applied or consumed history")
        Observe("combat:" .. tostring(locked))
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle() active.cancel:Click("LeftButton") Settle()
    end
    local before = Snapshot()
    disclosure.header:Click("LeftButton") Settle() disclosure.header:Click("LeftButton") Settle()
    M.Refresh() Settle() SameDB(before, "ClassPower warm section reopen") Observe("warm-section")
    assert(mw:Select("home")) assert(mw:Select("opt_colors")) Settle()
    assert(M.cache.opt_colors == entry, "ClassPower warm page replaced native owners") Observe("warm-page")
    Add("construction-counts", colorCount, buttonCount, count)
    return rows
end
local total = 0
for _, width in ipairs({ 720, 400 }) do
    local expected = parent and parent ~= "-" and Replay(width, true) or nil
    local actual = Replay(width, false)
    if expected then
        assert(#expected == #actual, "ClassPower parent observation census drift")
        for index, value in ipairs(expected) do
            assert(value == actual[index], "ClassPower parent parity drift at " .. index .. " " .. value:match("^[^\t]+"))
        end
    end
    total = total + #actual
end
if arg[5] == "--focused-cancel" then
    print("menu_class_power_colors_schema_smoke " .. flavor .. ":focused-cancel PASS (all offered native families; 720/400)")
    return
end
print("menu_class_power_colors_schema_smoke " .. flavor .. ":20 owners/" .. total
    .. " observations PASS (" .. (parent and parent ~= "-" and "parent-candidate exact" or "candidate behavior") .. ")")
