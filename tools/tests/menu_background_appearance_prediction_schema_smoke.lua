-- The three legacy Colors sections keep their native controls and history owners.
-- Standard args: <root> <flavor>; optional authentic parent/page overrides are diagnostic.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local parent, candidate = arg[3], arg[4]
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
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
    { "background.fill_mode", "dropdown", "colors_background", true },
    { "background.color_mode", "dropdown", "colors_background", true },
    { "general.classBarBg", "color", "colors_background" },
    { "background.dark_mode_custom_color", "toggle", "colors_background", true },
    { "background.reset_to_black", "button", "colors_background" },
    { "appearance.bar_mode", "segment", "colors_appearance" },
    { "general.unifiedBar", "color", "colors_appearance" },
    { "appearance.dark_mode_tone", "slider", "colors_appearance", true },
    { "appearance.gradient.strength", "slider", "colors_appearance", true },
    { "appearance.gradient.enabled", "toggle", "colors_appearance", true },
    { "general.healthGradientLow", "color", "colors_appearance" },
    { "general.healthGradientMid", "color", "colors_appearance" },
    { "general.healthGradientHigh", "color", "colors_appearance" },
    { "appearance.gradient.reset", "button", "colors_appearance" },
    { "api.SetAbsorbOverlayColor", "color", "colors_bar_colors" },
    { "api.SetHealAbsorbOverlayColor", "color", "colors_bar_colors" },
    { "api.SetPowerBarBackgroundColor", "color", "colors_bar_colors" },
    { "api.SetAggroBorderColor", "color", "colors_bar_colors" },
    { "prediction.heal_color", "color", "colors_bar_colors" },
    { "bar.health_loss_color", "color", "colors_bar_colors" },
    { "bar.purge_border_color", "color", "colors_bar_colors" },
    { "bar.outline_color", "color", "colors_bar_colors" },
    { "bar.power_background_match_health", "toggle", "colors_bar_colors", true },
    { "bar.power_loss_color", "color", "colors_bar_colors" },
    { "bar.reset", "button", "colors_bar_colors" },
}
local sections = { "colors_background", "colors_appearance", "colors_bar_colors" }
local function Shown(widget)
    while widget do if not widget:IsShown() then return false end widget = widget:GetParent() end
    return true
end
local function Replay(width, original)
    local override, loaded = original and parent or candidate, 0
    local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
        clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = InstallNativeInputs,
        beforeOptions = function(world)
            InstallColorSelect(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if path:gsub("\\", "/") == root .. "/" .. target then
                    loaded = loaded + 1 if override and override ~= "-" then path = override end
                end
                return load(self, path, addon, namespace)
            end
        end })
    assert(loaded == 1, "real Colors page override must load exactly once")
    local M, env, core = mw.M, mw.env, mw.core
    local rows, ids, controls, bindings, calls, createdColors = {}, {}, {}, {}, {}, {}
    local preview, paints = nil, 0
    local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Snapshot()
        local copy, ok, why = core.ProfileFields.CopySnapshot(env.MSUF_DB) assert(ok, why) return copy
    end
    local function SameDB(before, tag) assert(Equal(before, env.MSUF_DB), "whole-profile drift: " .. tag) end
    local function Settle()
        mw:RunTimers()
        for _, frame in ipairs(mw.world.widgets.frames) do
            for _, key in ipairs({ "_msuf2AlphaFade", "_msuf2AlphaScale" }) do
                local animation = frame[key]
                if animation and animation:IsPlaying() and animation:GetScript("OnFinished") then
                    animation:Finish() MenuWorld.FireScript(animation, "OnFinished")
                end
            end
            for _, selection in ipairs(frame._msuf2SelectionMotions or {}) do
                local driver = selection.driver
                for _ = 1, 120 do
                    if not (driver and driver:GetScript("OnUpdate")) then break end
                    MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                end
                assert(not (driver and driver:GetScript("OnUpdate")), "finite selection failed to settle")
            end
        end
        mw:RunTimers()
    end
    local painter = assert(M.RefreshHealthBackgroundInlinePreview)
    M.RefreshHealthBackgroundInlinePreview = function(state)
        local result = painter(state) preview, paints = state, paints + 1 return result
    end
    for _, key in ipairs({ "BindColor", "BindSegment", "BindSlider", "BindToggle", "BindDropdown" }) do
        local bind = assert(M[key])
        M[key] = function(ctx, widget, ...)
            bindings[widget] = (bindings[widget] or 0) + 1 return bind(ctx, widget, ...)
        end
    end
    local nativeColor = M.Widgets.Color
    M.Widgets.Color = function(...)
        local widget = nativeColor(...) createdColors[#createdColors + 1] = widget return widget
    end
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    assert(M.cache.opt_colors == nil, "target page was not cold")
    -- The native preview has a separate, existing one-shot Aura normalization.
    local auraModel = assert(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel)
    local auraRecord = assert(env.MSUF_DB.auras3.customContainers.perUnit.player)
    local auraItem = assert(auraRecord.items[4])
    local auraPlaced, expectedAura = assert(auraItem.placed), Snapshot()
    local expectedRecord = expectedAura.auras3.customContainers.perUnit.player
    assert(expectedRecord._msufA3CustomContainersMigrated_v1 == nil
        and expectedRecord.items[4]._msufA3LocalStyleFromShared_v1 == nil
        and expectedRecord.items[4].placed.iconShape == nil, "fresh Aura fixture drift")
    assert(auraModel.CustomContainer("player", 4, false) == auraItem)
    expectedRecord._msufA3CustomContainersMigrated_v1 = true
    expectedRecord.items[4]._msufA3LocalStyleFromShared_v1 = true
    expectedRecord.items[4].placed.iconShape = "RECTANGLE"
    SameDB(expectedAura, "unrelated Aura preparation")
    assert(auraRecord.items[4] == auraItem and auraItem.placed == auraPlaced)
    assert(M.cache.opt_colors == nil, "fixture built the target page")
    local fresh = Snapshot()
    assert(mw:Select("opt_colors"))
    local entry = assert(M.cache.opt_colors)
    assert(entry.sections.colors_appearance and entry.sections.colors_bar_colors, "initial unit slice missing")
    Settle()
    for _, key in ipairs(sections) do
        local section = assert(entry.sections[key], "lazy Colors section missing: " .. key)
        local disclosure = assert(section._msuf2CollapsibleEntry)
        ids[section], ids[disclosure.header] = key, key .. ".header"
        Add("birth:" .. key, disclosure.open, section._msuf2Width, section:GetHeight())
        if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
        assert(disclosure.open and Shown(section), "real disclosure did not open: " .. key)
        if not original then
            local spec = assert(disclosure.header._msuf2ControlSchema, "Colors section declaration missing")
            assert(spec.owner == disclosure.header and spec.scope == "colors"
                and spec.applyDomain == "sectionNavigation", "section navigation owner drift")
        end
    end
    SameDB(fresh, "cold lazy construction")
    ids[entry.wrapper] = "opt_colors.wrapper"
    local legacy, added, colorOwners = 0, 0, 0
    for _, spec in ipairs(specs) do
        local id = M.ControlMeta("opt_colors", "advanced", spec[1]).controlId
        local record = assert(M.RuntimeControlCatalog.Get(id), "native Colors owner missing: " .. spec[1])
        local widget = assert(record.widget) controls[spec[1]], ids[widget] = widget, id
        assert(record.kind == spec[2] and widget:GetParent() == entry.sections[spec[3]], "native control identity drift")
        if spec[2] == "button" then assert(bindings[widget] == nil, "native action gained an input binder")
        else assert(bindings[widget] == 1, "native Colors owner rebound") end
        if spec[2] == "color" then colorOwners = colorOwners + 1 end
        if spec[4] then
            legacy = legacy + 1
            assert(widget._msuf2ControlSchema, "existing generic owner lost")
        else
            added = added + 1
            if not original then
                local declaration = assert(widget._msuf2ControlSchema, "native Colors declaration missing: " .. spec[1])
                assert(declaration.id == id and declaration.kind == spec[2] and declaration.scope == "colors"
                    and declaration.applyDomain == "unitColors" and declaration.owner == widget,
                    "native Colors schema owner/kind/domain drift")
            end
        end
    end
    assert(#specs == 25 and legacy == 7 and added == 18 and colorOwners == 14, "Colors owner census drift")
    local function ColorCount()
        local count = 0
        for _, widget in ipairs(createdColors) do
            for _, key in ipairs(sections) do if widget:GetParent() == entry.sections[key] then count = count + 1 end end
        end
        return count
    end
    assert(ColorCount() == 14, "three Colors sections created duplicate/unregistered swatches")
    local function Command(widget) return assert(widget._msuf2CommandAction or widget._msuf2RuntimeControlRecord.command) end
    local function Gates()
        local mode = Command(controls["appearance.bar_mode"]).get()
        local enabled = mode == "gradient" and env.MSUF_DB.general.enableHealthGradient ~= false
        assert(controls["general.unifiedBar"]:IsEnabled() == (mode == "unified"), "unified gate drift")
        assert(controls["appearance.dark_mode_tone"]:IsEnabled() == (mode == "dark"), "dark-tone gate drift")
        assert(controls["appearance.gradient.enabled"]:IsEnabled() == (mode == "gradient"), "gradient master gate drift")
        for _, path in ipairs({ "appearance.gradient.strength", "general.healthGradientLow", "general.healthGradientMid",
            "general.healthGradientHigh", "appearance.gradient.reset" }) do
            assert(controls[path]:IsEnabled() == enabled, "gradient detail gate drift: " .. path)
        end
        assert(controls["api.SetPowerBarBackgroundColor"]:IsEnabled()
            == (not controls["bar.power_background_match_health"]:GetChecked()), "power-background matching gate drift")
    end
    local function Preview()
        assert(preview and preview.bar and preview.backgroundBar and preview.background, "real inline painter missing")
        return { preview.healthFraction, preview.bar:GetValue(), preview.backgroundBar:GetValue(),
            preview.backgroundBar:GetReverseFill(), Pack(preview.bar:GetStatusBarColor()),
            Pack(preview.background:GetVertexColor()), preview.bar:GetStatusBarTexture():GetTexture(),
            preview.background:GetTexture(), preview.mode:GetText() }
    end
    local function Observe(tag)
        local shown = {}
        Gates()
        for _, spec in ipairs(specs) do
            local widget = controls[spec[1]]
            local command = widget._msuf2CommandAction or widget._msuf2RuntimeControlRecord.command
            local model, displayed
            if spec[2] == "color" then
                model, displayed = Pack(command.get()), Pack(widget:GetRGB())
                assert(Equal(Pack(model[1], model[2], model[3]), displayed), "displayed color/model drift: " .. spec[1])
            elseif command and command.get then model = Pack(command.get()) end
            local label = widget._msuf2Title or widget._msuf2Label
            shown[#shown + 1] = { spec[1], model, displayed, widget:IsEnabled(), Shown(widget),
                Pack(widget:GetPoint(1)), Pack(widget:GetSize()), label and label:GetText(),
                label and label:GetWidth(), widget._msuf2SearchMeta }
        end
        Add(tag, Snapshot(), shown, Preview(), M.GetHistoryState(), calls, paints)
    end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, Pack(...) } return fn(...)
        end end
    end
    local function Refresh()
        local before = Snapshot() M.Refresh() Settle() SameDB(before, "read-only refresh") Gates()
    end
    local function Choose(widget, value)
        if widget._msuf2RuntimeControlRecord.kind == "segment" then
            for _, option in ipairs(widget.buttons) do
                if option._msuf2Value == value then option:Click("LeftButton") Settle() return end
            end
        else
            widget:Click("LeftButton") Settle()
            if M.IsConfigCombatLocked() then return end
            for _, option in ipairs(mw.world.widgets.frames) do
                if option._msuf2Owner == widget and option._msuf2Value == value and Shown(option)
                    and not option._msuf2DropdownDisabled then option:Click("LeftButton") Settle() return end
            end
        end
        error("native choice missing: " .. tostring(value))
    end
    local function Input(spec, value)
        local widget = controls[spec[1]]
        if spec[2] == "dropdown" or spec[2] == "segment" then Choose(widget, value)
        elseif spec[2] == "slider" then widget:SetValue(value) MenuWorld.FireScript(widget, "OnValueChanged", value)
        elseif spec[2] == "toggle" then widget:SetChecked(value) widget:Click("LeftButton")
        elseif spec[2] == "button" then widget:Click("LeftButton")
        else widget._msuf2OnColorChanged(unpack(value)) end
        Settle()
    end
    local factory = Snapshot()
    local function Setup(case)
        Restore(env.MSUF_DB, factory)
        local g = env.MSUF_DB.general
        g.threeColorsContract = { enabled = false, zero = 0, nested = { "preserve" } }
        env.MSUF_DB.target.threeColorsContract = { false, 0 }
        if case == "sparse" then
            for _, key in ipairs({ "barBgFillMode", "barBgColorMode", "classBarBgR", "classBarBgG", "classBarBgB",
                "classBarBgA", "darkBgCustomColor", "barMode", "darkMode", "useClassColors", "darkBarGray",
                "enableHealthGradient", "gradientStrength", "powerBarBgMatchBarColor" }) do g[key] = nil end
        elseif case == "edge" then
            g.barMode, g.darkMode, g.useClassColors = "invalid", false, 0
            g.darkBarGray, g.darkBarTone, g.gradientStrength = 0, 32, 0
            g.enableHealthGradient, g.classBarBgR, g.classBarBgG, g.classBarBgB, g.classBarBgA = false, false, 0, nil, 0
            g.barBgFillMode, g.barBgColorMode, g.barBgClassColor, g.barBgMatchHPColor = nil, nil, false, true
            g.hlPurgeColorR, g.hlPurgeColorG, g.hlPurgeColorB, g.purgeBorderColorR = nil, 0, false, 0.31
        elseif case == "explicit-defaults" then
            g.barMode, g.useClassColors, g.darkBarGray = "dark", false, 0.07
            g.barBgFillMode, g.barBgColorMode, g.classBarBgA = "full", "custom", 1
            g.enableHealthGradient, g.gradientStrength, g.powerBarBgMatchBarColor = true, 0.45, false
        end
        Refresh() M.ClearHistory() calls, paints = {}, 0
    end
    local function Prepare(spec)
        if spec[1] == "general.unifiedBar" then Choose(controls["appearance.bar_mode"], "unified")
        elseif spec[1] == "appearance.dark_mode_tone" then Choose(controls["appearance.bar_mode"], "dark")
        elseif spec[1]:find("gradient", 1, true) or spec[1]:find("healthGradient", 1, true) then
            Choose(controls["appearance.bar_mode"], "gradient")
            if not Command(controls["appearance.gradient.enabled"]).get() then
                Input(specs[10], true)
            end
        elseif spec[1] == "api.SetPowerBarBackgroundColor" and Command(controls["bar.power_background_match_health"]).get() then
            Input(specs[23], false)
        end
        M.ClearHistory() calls, paints = {}, 0
    end
    local function Value(spec, index)
        local current = spec[2] ~= "button" and Pack(Command(controls[spec[1]]).get()) or {}
        if spec[2] == "color" then return { 0.23, 0.47, 0.71, 0.37 }
        elseif spec[2] == "toggle" then return not current[1]
        elseif spec[2] == "slider" then return current[1] == 0 and (index == 8 and 27 or 0.65) or 0
        elseif spec[2] == "segment" then return current[1] == "class" and "dark" or "class"
        elseif spec[1] == "background.fill_mode" then return current[1] == "missing" and "full" or "missing"
        elseif spec[1] == "background.color_mode" then return current[1] == "health_gradient" and "custom" or "health_gradient" end
    end
    local function History(before, after, label)
        if Equal(before, after) then assert(M.GetHistoryState().undoCount == 0, "unchanged reset gained history") return end
        local widthBefore = tonumber(env.MSUF_DB.player.width) or 250
        M.SetUnitValue("player", "width", widthBefore + 1) Settle()
        local afterWidth = Snapshot()
        assert(M.Undo(), "missing width Undo: " .. label) Settle() SameDB(after, "width Undo: " .. label)
        assert(M.Undo(), "missing Colors Undo: " .. label) Settle() SameDB(before, "Colors Undo: " .. label)
        assert(M.Redo(), "missing Colors Redo: " .. label) Settle() SameDB(after, "Colors Redo: " .. label)
        assert(M.Redo(), "missing width Redo: " .. label) Settle() SameDB(afterWidth, "width Redo: " .. label)
    end
    for _, case in ipairs(width == 400 and { "edge" } or { "factory", "sparse", "edge", "explicit-defaults" }) do
        for index, spec in ipairs(specs) do
            Setup(case) Prepare(spec)
            local before = Snapshot()
            Input(spec, Value(spec, index))
            local after = Snapshot()
            assert(Equal(before.target, after.target) and Equal(before.general.threeColorsContract, after.general.threeColorsContract),
                "Colors input changed unrelated roots")
            Observe(case .. ":input:" .. spec[1])
            History(before, after, spec[1]) Observe(case .. ":history:" .. spec[1])
            if spec[2] ~= "button" and spec[2] ~= "toggle" and controls[spec[1]]:IsEnabled() then
                M.ClearHistory() calls, paints = {}, 0 before = Snapshot()
                local current = Pack(Command(controls[spec[1]]).get())
                Input(spec, spec[2] == "color" and { current[1], current[2], current[3], current[4] } or current[1])
                SameDB(before, "effective no-op: " .. spec[1])
                assert(M.GetHistoryState().undoCount == 0 and #calls == 0, "effective no-op applied or added history")
                Observe(case .. ":noop:" .. spec[1])
            end
        end
    end
    local function Panel(widget)
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.owner == widget and frame.compactHex and Shown(frame) then return frame end
        end
    end
    Setup("edge")
    local cold = Snapshot()
    assert(cold.menu2ColorPicker == nil, "native tint fixture was not cold")
    local tint = controls["general.classBarBg"]
    tint:Click("LeftButton") Settle()
    local picker = assert(Panel(tint), "native background color picker missing")
    MenuWorld.FireVisibilityScripts(picker)
    local opened = Snapshot()
    assert(Equal(opened.menu2ColorPicker, { recent = {}, saved = {}, x = -783, y = -363 }), "cold picker store initialization drift")
    cold.menu2ColorPicker = opened.menu2ColorPicker
    SameDB(cold, "cold native picker initialization")
    -- The edit baseline follows genuine cold picker preparation, which creates its own store.
    assert(M.SyncExternalHistoryState(), "native tint history baseline unavailable")
    SameDB(opened, "native tint history synchronization")
    assert(M.GetHistoryState().undoCount == 0 and M.GetHistoryState().redoCount == 0, "picker preparation gained history")
    local before = Snapshot()
    picker.compactHex:SetText("0040FF") MenuWorld.FireScript(picker.compactHex, "OnTextChanged", true)
    MenuWorld.FireScript(picker.compactHex, "OnEnterPressed") Settle()
    MenuWorld.FireScript(picker.opacity, "OnValueChanged", 0.37) Settle()
    picker.done:Click("LeftButton") Settle()
    local g = env.MSUF_DB.general
    assert(g.classBarBgR == 0 and g.classBarBgG == 64 / 255 and g.classBarBgB == 1 and g.classBarBgA == 0.37,
        "native background HEX/alpha did not reach real API")
    local after = Snapshot() Observe("native-tint-hex-alpha")
    assert(M.GetHistoryState().undoCount == 1, "native picker transaction gained multiple entries")
    History(before, after, "native tint picker")
    M.ClearHistory() before = Snapshot()
    tint:Click("LeftButton") Settle() picker = assert(Panel(tint))
    MenuWorld.FireVisibilityScripts(picker)
    picker.compactHex:SetText("CC6622") MenuWorld.FireScript(picker.compactHex, "OnTextChanged", true)
    MenuWorld.FireScript(picker.compactHex, "OnEnterPressed") Settle()
    picker.cancel:Click("LeftButton") Settle() SameDB(before, "native Cancel")
    for _, spec in ipairs(specs) do
        if spec[2] == "color" then
            Setup("factory") Prepare(spec) before = Snapshot()
            controls[spec[1]]:Click("RightButton") Settle()
            Observe("native-default:" .. spec[1]) History(before, Snapshot(), "native default")
        end
    end
    for _, lockdown in ipairs({ false, true }) do
        Setup("factory")
        Choose(controls["appearance.bar_mode"], "gradient")
        Input(specs[10], false)
        Choose(controls["appearance.bar_mode"], "dark")
        M.ClearHistory() before = Snapshot()
        Input(specs[1], "missing") local edited = Snapshot()
        assert(M.Undo()) Settle() SameDB(before, "combat Redo preparation")
        local history = Encode(M.GetHistoryState(), ids)
        calls, paints = {}, 0
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
        for _, spec in ipairs({ specs[1], specs[4], specs[6], specs[8], specs[15], specs[25] }) do
            Input(spec, Value(spec, 8))
        end
        SameDB(before, "event-derived combat refusal")
        assert(Encode(M.GetHistoryState(), ids) == history and #calls == 0, "combat consumed history or applied")
        Observe("combat:" .. tostring(lockdown))
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle()
        assert(M.Redo(), "combat consumed pending Redo") Settle() SameDB(edited, "post-combat Redo")
    end
    Setup("factory") Choose(controls["appearance.bar_mode"], "class")
    before = Snapshot() M.ClearHistory() calls = {}
    controls["general.unifiedBar"]:Click("LeftButton") Settle()
    assert(not Panel(controls["general.unifiedBar"]), "disabled swatch opened a picker")
    SameDB(before, "disabled swatch") assert(#calls == 0 and M.GetHistoryState().undoCount == 0)
    local same = {} for path, widget in pairs(controls) do same[path] = widget end
    for _, key in ipairs(sections) do
        local disclosure = entry.sections[key]._msuf2CollapsibleEntry
        disclosure.header:Click("LeftButton") Settle()
        disclosure.header:Click("LeftButton") Settle()
    end
    M.Refresh() Settle() SameDB(before, "warm reopen")
    for path, widget in pairs(same) do
        assert(M.RuntimeControlCatalog.Get(ids[widget]).widget == widget, "warm page replaced native owner: " .. path)
    end
    assert(ColorCount() == 14, "warm Colors page created extra swatches")
    Observe("warm-reopen")
    mw:Select("home") mw:Select("opt_colors") Settle() SameDB(before, "warm page revisit")
    Observe("page-revisit")
    return rows
end
local count = 0
for _, width in ipairs({ 720, 400 }) do
    local expected = parent and parent ~= "-" and Replay(width, true) or nil
    local actual = Replay(width, false)
    if expected then
        assert(#expected == #actual, "three-section parent observation count drift")
        for index, row in ipairs(expected) do
            assert(row == actual[index], "three-section parent parity drift at " .. index .. " " .. row:match("^[^\t]+"))
        end
    end
    count = count + #actual
end
print("menu_background_appearance_prediction_schema_smoke " .. flavor .. ":25 owners/" .. count
    .. " observations PASS (" .. (parent and parent ~= "-" and "parent-candidate exact" or "candidate behavior") .. ")")
