-- Actual Aura workspaces: native owners and complete parent/candidate observations.
-- <root> <flavor> [all three parent paths, or '-' '-' '-'] [candidateAuras] [candidateCustom] [candidateIconSkin]
-- All providers and apply owners remain real. This is offline lifecycle evidence.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local parent = { arg[3], arg[4], arg[5] }
local omittedParents = arg[3] == nil and arg[4] == nil and arg[5] == nil
local skippedParents = arg[3] == "-" and arg[4] == "-" and arg[5] == "-"
local hasParent = not (omittedParents or skippedParents)
assert(not hasParent or (arg[3] and arg[3] ~= "-" and arg[3] ~= ""
    and arg[4] and arg[4] ~= "-" and arg[4] ~= "" and arg[5] and arg[5] ~= "-" and arg[5] ~= ""),
    "provide all three parent paths, omit all three, or use three '-' placeholders")
print("AuraWorkspace mode=" .. (hasParent and "parent-parity" or "candidate-only"))
local candidate = { arg[6], arg[7], arg[8] }
local targets = { "MSUF_Menu2_Auras.lua", "MSUF_Menu2_Auras_CustomWorkspace.lua", "MSUF_Menu2_Auras_IconSkin.lua" }
local prefix = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    local kind = type(value)
    if kind == "function" then return "<function>" end
    if kind == "string" then return "string:" .. value:gsub("table: %x+", "table:<address>") end
    if kind ~= "table" then return kind .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget:" .. tostring(ids[value] or value:GetObjectType()) end
    seen = seen or {} if seen[value] then return "<cycle>" end seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key, ids) .. "=" .. Encode(value[key], ids, seen) end
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
local function Shown(widget)
    while widget do if widget.shown == false then return false end widget = widget:GetParent() end
    return true
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

local function Replay(original, width, saved)
    print("AuraWorkspace " .. flavor .. ":" .. (original and "parent" or "candidate") .. ":" .. width .. (saved and ":fresh" or ""))
    local loads, bindings, created, captured, calls = {}, {}, {}, {}, {}
    local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
        clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = InstallNativeInputs,
        beforeOptions = function(world)
            InstallColorSelect(world)
            for _, name in ipairs({ "SetFlipBookFrameWidth", "SetFlipBookFrameHeight" }) do
                local field = name .. "Value"
                world.widgets.Methods[name] = function(self, value) self[field] = value end
            end
            local load, installed = world.LoadFile, false
            world.LoadFile = function(self, path, addon, namespace)
                local normalized = path:gsub("\\", "/")
                if normalized == root .. "/" .. prefix .. targets[1] and not installed then
                    installed = true
                    local M = assert(world.core.MSUF2)
                    local apply = M.AuraControls.ApplyUnit
                    M.AuraControls.ApplyUnit = function(ctx, ...)
                        calls[#calls + 1] = { "AuraControls.ApplyUnit", Pack(ctx and ctx.key, ...) }
                        return apply(ctx, ...)
                    end
                    for _, name in ipairs({ "BindToggle", "BindSlider", "BindDropdown", "BindTextInput", "BindColor" }) do
                        local native = assert(M[name])
                        M[name] = function(ctx, widget, ...)
                            bindings[widget] = (bindings[widget] or 0) + 1
                            return native(ctx, widget, ...)
                        end
                    end
                    local function Capture(widget, kind)
                        if widget and not captured[widget] then
                            captured[widget] = true created[#created + 1] = { widget, kind }
                        end
                        return widget
                    end
                    for _, name in ipairs({ "SwitchAt", "ToggleAt", "Dropdown", "Slider", "TextInput", "Color", "ScopeOverrideBar" }) do
                        local native, kind = assert(M.Widgets[name]), name
                        M.Widgets[name] = function(...) return Capture(native(...), kind) end
                    end
                    local native = M.Theme.Button
                    M.Theme.Button = function(...) return Capture(native(...), "Button") end
                end
                for index, name in ipairs(targets) do
                    if normalized == root .. "/" .. prefix .. name then
                        loads[index] = (loads[index] or 0) + 1
                        local override = original and parent[index] or candidate[index]
                        if override and override ~= "-" then path = override end
                    end
                end
                return load(self, path, addon, namespace)
            end
        end })
    for index = 1, 3 do assert(loads[index] == 1, "exact Aura workspace input was not loaded once") end
    local M, core, env = mw.M, mw.core, mw.env
    local Model, rows, ids = core.MSUF_Auras3.MenuModel, {}, {}
    local coverage = { views = 0, inputs = 0, headers = 0, constructors = 0, actions = 0 }
    local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Snapshot()
        local copy, valid, why = core.ProfileFields.CopySnapshot(env.MSUF_DB)
        assert(valid and type(copy) == "table", why or "invalid raw Aura profile snapshot") return copy
    end
    local function Settle()
        mw:RunTimers()
        for _, frame in ipairs(mw.world.widgets.frames) do
            for _, selection in ipairs(frame._msuf2SelectionMotions or {}) do
                local driver = selection.driver
                for _ = 1, 120 do
                    if not (driver and driver:GetScript("OnUpdate")) then break end
                    MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                end
                assert(not (driver and driver:GetScript("OnUpdate")), "native selection failed to settle")
            end
        end
        mw:RunTimers()
    end
    assert(core.ApplyService.RequestGeneralDomains("AURA_WORKSPACE_FIXTURE_LOGIN", { preview = true })) Settle()
    local login = Snapshot()
    assert(core.ApplyService.RequestGeneralDomains("AURA_WORKSPACE_FIXTURE_LOGIN", { preview = true })) Settle()
    assert(Equal(login, Snapshot()), "second real login apply did not stabilize")
    if saved then Restore(env.MSUF_DB, saved) assert(Equal(saved, Snapshot()), "fresh saved aliases did not restore") end
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    for name, native in pairs(M.ApplyService) do
        if type(native) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { "ApplyService." .. name, Pack(...) } return native(...)
        end end
    end
    M.StartHistorySession("menu") M.ClearHistory() M.SyncExternalHistoryState()
    local function Owner(entry, widget)
        local current = widget
        while current do
            if current == entry.wrapper or current._msuf2PageOwnerWrapper == entry.wrapper then return true end
            assert(type(current.GetParent) == "function", "Aura native ancestor lacks GetParent: " .. tostring(ids[widget]))
            current = current:GetParent()
        end
        return false
    end
    local function Command(widget) return widget._msuf2CommandAction end
    local function Value(record)
        local widget, command = record.widget, Command(record.widget)
        if command and command.get then return Pack(command.get()) end
        if record.kind == "segment" then return Pack(widget:GetValue()) end
    end
    local function Display(record)
        local w, kind = record.widget, record.kind
        if kind == "color" then return Pack(w:GetRGB()) end
        if kind == "toggle" then return Pack(w:GetChecked()) end
        if kind == "textinput" then return Pack(w:GetText()) end
        if kind == "slider" or kind == "dropdown" or kind == "segment" then return Pack(w:GetValue()) end
    end
    local function Records(entry)
        local out, virtual = {}, {}
        for _, item in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local record = M.RuntimeControlCatalog.Get(item.controlId)
            if record and record.widget then
                local w = record.widget
                if record.virtual == true then
                    assert(w._msuf2VirtualRuntimeControl == true, "unknown virtual RuntimeCatalog owner: " .. item.controlId)
                    if record.pageKey == M.activeKey and item.controlId:find(".auras.", 1, true) then
                        virtual[#virtual + 1] = { item.controlId, record.kind, record.classification,
                            record.settingKey, record.actionKey, record.anchor ~= nil }
                    end
                else
                    assert(type(w.GetParent) == "function", "unknown nonvirtual RuntimeCatalog owner: " .. item.controlId)
                    ids[w] = item.controlId
                    if Owner(entry, w) and item.controlId:find(".auras.", 1, true) then out[#out + 1] = record end
                end
            end
        end
        table.sort(out, function(a, b) return a.controlId < b.controlId end)
        table.sort(virtual, function(a, b) return a[1] < b[1] end)
        return out, virtual
    end
    local function Observe(entry, tag)
        local list, virtual = Records(entry)
        assert(#list > 0, "empty Aura runtime census: " .. tag)
        local raw = {}
        for _, record in ipairs(list) do
            local w, id, kind = record.widget, record.controlId, record.kind
            if not original then
                local spec = assert(w._msuf2ControlSchema, "Aura declaration missing: " .. id)
                assert(spec.owner == w and spec.id == id and spec.kind == kind and spec.scope == "auras",
                    "Aura actual native-owner identity drift: " .. id)
                local parent = w:GetParent()
                local disclosure = parent and parent._msuf2CollapsibleEntry
                local sectionHeader = disclosure and disclosure.header == w and kind == "toggle"
                    and record.classification == "ephemeral"
                assert(spec.applyDomain == (sectionHeader and "sectionNavigation" or kind == "segment" and "menuState"
                    or record.classification == "ephemeral" and "menuState" or "auras"), "Aura apply domain drift: " .. id)
                local command = Command(w)
                if command and command.get then assert(Equal(Pack(spec.get()), Pack(command.get())), "Aura native getter drift: " .. id) end
                if command and command.set then assert(type(spec.set) == "function", "Aura setter missing: " .. id) end
                if kind == "segment" then
                    assert(Equal(spec.get(), w:GetValue()) and spec.values == w.values and type(spec.set) == "function",
                        "Aura native selector forwarding missing: " .. id)
                end
                if kind == "button" then assert(type(spec.action) == "function", "Aura native action missing: " .. id) end
            end
            if Command(w) and kind ~= "button" then assert(bindings[w] == 1, "Aura native input rebound: " .. id) end
            raw[#raw + 1] = { id, kind, record.classification, record.settingKey, record.actionKey,
                Value(record), Display(record), w:IsEnabled(), w:GetAlpha(), Shown(w), w:GetWidth(), w:GetHeight() }
        end
        local keys = {} for key in pairs(entry.sections) do keys[#keys + 1] = key end table.sort(keys)
        local headers = {}
        for _, key in ipairs(keys) do
            local section = entry.sections[key]
            if key == "auras" or key:match("^aura_style_") or key:match("^aura_reminder_") then
                local disclosure = section._msuf2CollapsibleEntry
                if disclosure then
                    ids[disclosure.header] = key .. ".header"
                    if not original then
                        local spec = assert(disclosure.header._msuf2ControlSchema, "Aura header declaration missing: " .. key)
                        assert(spec.owner == disclosure.header and spec.scope == "auras" and spec.applyDomain == "sectionNavigation")
                    end
                    headers[#headers + 1] = { key, disclosure.open, section._msuf2Width, section:GetHeight() }
                    coverage.headers = coverage.headers + 1
                end
            end
        end
        local constructors = {}
        for index, row in ipairs(created) do
            local w = row[1]
            if Owner(entry, w) then
                local owner = w._msuf2ControlPartOf
                constructors[#constructors + 1] = { row[2], ids[w], owner and ids[owner], w:GetObjectType(), Shown(w) }
                coverage.constructors = coverage.constructors + 1
            end
        end
        Add(tag, raw, headers, constructors, virtual, Snapshot(), M.GetHistoryState(), calls)
        return list
    end
    local function OpenSections(entry)
        local keys = {} for key in pairs(entry.sections) do keys[#keys + 1] = key end table.sort(keys)
        for _, key in ipairs(keys) do
            local section = entry.sections[key]
            if key == "auras" or key:match("^aura_style_") or key:match("^aura_reminder_") then
                local disclosure = section._msuf2CollapsibleEntry
                if disclosure and not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
            end
        end
    end
    local function Select(page)
        assert(mw:Select(page) ~= false, "Aura page selection failed: " .. page) Settle()
        local entry = assert(M.cache[page]) OpenSections(entry) return entry
    end
    local function Bar(entry, label)
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.buttons and frame.values and frame.label and frame.label:GetText() == label
                and Owner(entry, frame) and Shown(frame) then return frame end
        end
        error("native Aura selector missing: " .. label)
    end
    local function Options(bar)
        local out = {} for _, w in ipairs(bar.buttons) do if w:IsEnabled() then out[#out + 1] = w._msuf2Value end end return out
    end
    local function ClickValue(entry, label, value)
        local bar = Bar(entry, label)
        for _, button in ipairs(bar.buttons) do
            if button._msuf2Value == value then button:Click("LeftButton") Settle() return assert(M.cache[M.activeKey]) end
        end
        error("native Aura selector value missing: " .. tostring(value))
    end
    local function Choose(w, value)
        w:Click("LeftButton") Settle()
        if M.IsConfigCombatLocked() then return end
        for _, option in ipairs(mw.world.widgets.frames) do
            if option._msuf2Owner == w and option._msuf2Value == value and Shown(option) and not option._msuf2DropdownDisabled then
                option:Click("LeftButton") Settle() return
            end
        end
        error("native Aura dropdown option missing: " .. tostring(value))
    end
    local function Input(record)
        local w, kind, command = record.widget, record.kind, Command(record.widget)
        if not (command and command.get) then return false end
        local current = command.get()
        if kind == "toggle" then w:Click("LeftButton")
        elseif kind == "slider" then
            local low, high = w:GetMinMaxValues()
            assert(type(low) == "number" and type(high) == "number", "native Aura slider range absent")
            local value = current ~= low and low or high
            MenuWorld.FireScript(w, "OnMouseDown", "LeftButton") w:SetValue(value)
            MenuWorld.FireScript(w, "OnMouseUp", "LeftButton")
        elseif kind == "dropdown" then
            local values = type(w.values) == "function" and w.values() or w.values
            assert(type(values) == "table", "native Aura dropdown values missing")
            for _, row in ipairs(values) do
                local value = row
                if type(row) == "table" then value = row.value end
                if value ~= current and not (type(row) == "table" and row.disabled) then Choose(w, value) Settle() return true end
            end
            return false
        elseif kind == "textinput" then
            w:SetText("774") MenuWorld.FireScript(w, "OnEnterPressed")
        elseif kind == "color" then w._msuf2OnColorChanged(.17, .29, .43)
        else return false end
        Settle() return true
    end
    local exercised, colors = {}, {}
    local function Exercise(entry, tag)
        coverage.views = coverage.views + 1
        local beforeBuild = Snapshot()
        local list = Observe(entry, tag .. ":birth")
        Add(tag .. ":first-profile", beforeBuild, Snapshot())
        -- One real native input per kind in every view, all remaining owners still have exact model/display/raw traces.
        local kinds = {}
        for _, record in ipairs(list) do
            local w, id, kind = record.widget, record.controlId, record.kind
            if kind == "color" then colors[id] = w end
            if not kinds[kind] and Shown(w) and w:IsEnabled() and kind ~= "segment" and kind ~= "button" then
                kinds[kind] = true M.ClearHistory() M.SyncExternalHistoryState() calls = {}
                local before, model = Snapshot(), Value(record)
                if Input(record) then
                    coverage.inputs = coverage.inputs + 1 exercised[kind] = true
                    local after = Snapshot() Observe(assert(M.cache[M.activeKey]), tag .. ":input:" .. id)
                    if not Equal(before, after) then
                        assert(M.Undo(), "real Aura edit had no Undo: " .. id) Settle()
                        Add(tag .. ":undo:" .. id, before, Snapshot(), Value(record), Display(record), M.GetHistoryState(), calls)
                        assert(Equal(model, Value(record)), "Aura Undo did not restore native model: " .. id)
                        assert(M.Redo(), "real Aura edit had no Redo: " .. id) Settle()
                        Add(tag .. ":redo:" .. id, after, Snapshot(), Value(record), Display(record), M.GetHistoryState(), calls)
                        assert(M.Undo(), "real Aura edit could not be undone after Redo") Settle()
                    end
                    for _, lockdown in ipairs({ false, true }) do
                        M.ClearHistory() M.SyncExternalHistoryState() calls = {}
                        local raw, history, value = Snapshot(), M.GetHistoryState(), Value(record)
                        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
                        Input(record)
                        assert(Equal(raw, Snapshot()) and Equal(history, M.GetHistoryState()) and Equal(value, Value(record)),
                            "Aura input wrote at combat edge: " .. id)
                        assert(#calls == 0, "refused Aura input applied runtime work: " .. id)
                        Add(tag .. ":combat:" .. id .. ":" .. tostring(lockdown), Snapshot(), Value(record), Display(record), calls)
                        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
                        mw:Fire("PLAYER_REGEN_ENABLED") Settle()
                    end
                end
            end
        end
        calls = {} local raw = Snapshot() M.Refresh() Settle()
        Add(tag .. ":refresh", raw, Snapshot(), calls)
        Observe(assert(M.cache[M.activeKey]), tag .. ":after-refresh")
    end
    local function ShowUnit(page, container, tool)
        local entry = Select(page)
        entry = ClickValue(entry, "Container:", container)
        if tool then entry = ClickValue(entry, "Edit:", tool) end
        OpenSections(entry) return entry
    end
    if saved or width == 400 then
        for _, view in ipairs({ { "uf_target", "buff", "style" }, { "uf_player", "custom1", "setup" },
            { "uf_target", "custom4", "style" } }) do
            Exercise(ShowUnit(unpack(view)), table.concat(view, ":"))
        end
    else
        for _, page in ipairs({ "uf_target", "uf_player" }) do
            local containers = Options(Bar(Select(page), "Container:")) assert(#containers == 6, "unit container census drift")
            for _, container in ipairs(containers) do
                local tools = Options(Bar(ShowUnit(page, container), "Edit:")) assert(#tools >= 5, "unit tool census drift")
                for _, tool in ipairs(tools) do Exercise(ShowUnit(page, container, tool), page .. ":" .. container .. ":" .. tool) end
            end
        end
    end
    local appearance = Select("auras3_styling")
    local types = Options(Bar(appearance, "Aura type:")) assert(#types == 4, "global Aura appearance type census drift")
    for _, value in ipairs(types) do
        appearance = ClickValue(appearance, "Aura type:", value) OpenSections(appearance)
        Exercise(appearance, "global:" .. value)
    end
    local scopeEntry = ShowUnit("uf_target", "buff", "layout")
    M.ClearHistory() M.SyncExternalHistoryState() calls = {} local scopeBefore = Snapshot()
    scopeEntry = ClickValue(scopeEntry, "Container:", "custom2") OpenSections(scopeEntry)
    Add("native:scope:B", scopeBefore, Snapshot(), Bar(scopeEntry, "Container:"):GetValue(), M.GetHistoryState(), calls)
    local undoScope = M.Undo() Settle()
    Add("native:scope:undo", undoScope, Snapshot(), M.GetHistoryState(), calls)
    local redoScope = M.Redo() Settle()
    Add("native:scope:redo", redoScope, Snapshot(), M.GetHistoryState(), calls)
    for _, lockdown in ipairs({ false, true }) do
        scopeEntry = ShowUnit("uf_target", "buff", "layout")
        M.ClearHistory() M.SyncExternalHistoryState() calls = {} scopeBefore = Snapshot()
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
        ClickValue(scopeEntry, "Container:", "custom2")
        Add("native:scope:combat:" .. tostring(lockdown), scopeBefore, Snapshot(),
            Bar(assert(M.cache.uf_target), "Container:"):GetValue(), M.GetHistoryState(), calls)
        undoScope = M.Undo() Settle() Add("native:scope:combat:undo", undoScope, Snapshot(), M.GetHistoryState(), calls)
        redoScope = M.Redo() Settle() Add("native:scope:combat:redo", redoScope, Snapshot(), M.GetHistoryState(), calls)
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle()
    end
    local colorEntry = ShowUnit("uf_target", "custom1", "style")
    for _, record in ipairs(Records(colorEntry)) do
        if record.kind == "dropdown" and record.controlId:match("%.effect%.type$") then Input(record) break end
    end
    M.Refresh() Settle()
    local colorRecord
    for _, record in ipairs(Records(colorEntry)) do if record.kind == "color" then colorRecord = record break end end
    assert(colorRecord, "actual custom Aura color owner missing")
    local color = colorRecord.widget
    local function Panel()
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.owner == color and frame.compactHex and Shown(frame) then return frame end
        end
    end
    color:Click("LeftButton") Settle()
    local panel = assert(Panel(), "real native Aura picker did not open") MenuWorld.FireVisibilityScripts(panel)
    panel.cancel:Click("LeftButton") Settle()
    assert(type(env.MSUF_DB.menu2ColorPicker.saved) == "table", "native picker store did not materialize")
    M.ClearHistory() M.SyncExternalHistoryState()
    local beforeColor, beforeModel = Snapshot(), Value(colorRecord)
    calls = {} color:Click("LeftButton") Settle() panel = assert(Panel()) MenuWorld.FireVisibilityScripts(panel)
    panel.compactHex:SetText("2B4A6D") MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle()
    panel.cancel:Click("LeftButton") Settle()
    assert(Equal(beforeModel, Value(colorRecord)), "native Aura picker Cancel did not restore actual owner")
    Add("native:picker-cancel", beforeColor, Snapshot(), Value(colorRecord), Display(colorRecord), M.GetHistoryState(), calls)
    M.ClearHistory() M.SyncExternalHistoryState() beforeColor = Snapshot()
    color:Click("LeftButton") Settle() panel = assert(Panel()) MenuWorld.FireVisibilityScripts(panel)
    panel.compactHex:SetText("2B4A6D") MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle()
    panel.done:Click("LeftButton") Settle()
    local r, g, blue = Command(color).get()
    assert(math.abs(r - 43 / 255) < .001 and math.abs(g - 74 / 255) < .001 and math.abs(blue - 109 / 255) < .001,
        "native Aura picker OK did not reach the real owner")
    Add("native:picker-OK", beforeColor, Snapshot(), Value(colorRecord), Display(colorRecord), M.GetHistoryState(), calls)
    assert(M.Undo(), "native Aura picker OK had no Undo") Settle()
    assert(Equal(beforeModel, Value(colorRecord)), "Aura picker Undo model drift")
    Add("native:picker-undo", beforeColor, Snapshot(), Value(colorRecord), Display(colorRecord), calls)
    assert(M.Redo(), "native Aura picker OK had no Redo") Settle()
    Add("native:picker-redo", Snapshot(), Value(colorRecord), Display(colorRecord), calls)
    -- Exact action owners and their existing native history/refusal policies are compared, without a stronger invented reset policy.
    local entry = ShowUnit("uf_target", "custom1", "setup")
    local reset
    for _, record in ipairs(Records(entry)) do if record.controlId:match("%.setup%.reset$") then reset = record end end
    assert(reset and reset.actionKey == "reset_aura_custom_container", "actual custom-container reset owner missing")
    for _, lockdown in ipairs({ false, true }) do
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
        local before = Snapshot() calls = {} reset.widget:Click("LeftButton") Settle()
        Add("native:reset:combat:" .. tostring(lockdown), before, Snapshot(), M.GetHistoryState(), calls)
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle()
    end
    entry = ShowUnit("uf_target", "custom1", "layout")
    for _, record in ipairs(Records(entry)) do
        if record.kind == "slider" and Shown(record.widget) and record.widget:IsEnabled() then Input(record) break end
    end
    entry = ShowUnit("uf_target", "custom1", "setup")
    for _, record in ipairs(Records(entry)) do if record.controlId:match("%.setup%.reset$") then reset = record end end
    M.ClearHistory() M.SyncExternalHistoryState() local resetBefore = Snapshot() calls = {}
    reset.widget:Click("LeftButton") Settle() local resetAfter = Snapshot()
    Add("native:reset:ordinary", resetBefore, resetAfter, M.GetHistoryState(), calls)
    if not Equal(resetBefore, resetAfter) then
        assert(M.Undo(), "native custom reset had no Undo") Settle()
        Add("native:reset:undo", resetBefore, Snapshot(), M.GetHistoryState(), calls)
        assert(M.Redo(), "native custom reset had no Redo") Settle()
        Add("native:reset:redo", resetAfter, Snapshot(), M.GetHistoryState(), calls)
    end
    entry = ShowUnit("uf_target", "custom1", "whitelist")
    local add
    for _, record in ipairs(Records(entry)) do
        local command = Command(record.widget)
        if command and command.valueKind == "text" and record.label == "Add buff" then add = record end
    end
    assert(add, "actual custom whitelist text action missing")
    local whitelistInput
    for _, record in ipairs(Records(entry)) do
        if record.controlId:match("%.custom%-container%.whitelist%.input$") then whitelistInput = record end
    end
    assert(whitelistInput and whitelistInput.kind == "textinput" and whitelistInput.classification == "ephemeral",
        "actual custom whitelist input owner missing")
    M.ClearHistory() M.SyncExternalHistoryState() local before = Snapshot() calls = {}
    whitelistInput.widget:SetText("774") MenuWorld.FireScript(whitelistInput.widget, "OnEnterPressed") Settle()
    assert(Command(whitelistInput.widget).get() == "774", "native whitelist text input did not commit")
    coverage.inputs = coverage.inputs + 1 exercised.textinput = true
    Add("native:whitelist-text-input", before, Snapshot(), Value(whitelistInput), Display(whitelistInput), M.GetHistoryState(), calls)
    M.ClearHistory() M.SyncExternalHistoryState() before = Snapshot() calls = {}
    assert(add.widget:Click("LeftButton") == true, "actual native whitelist add click failed") Settle()
    local added = Snapshot()
    assert(#Model.CustomContainerSpellEntries("target", 1) == 1, "actual whitelist add did not persist")
    Observe(M.cache.uf_target, "native:whitelist-add")
    assert(M.Undo(), "native whitelist add had no Undo") Settle()
    assert(#Model.CustomContainerSpellEntries("target", 1) == 0, "whitelist Undo did not remove exact spell")
    Add("native:whitelist-undo", before, Snapshot(), calls)
    assert(M.Redo(), "native whitelist add had no Redo") Settle()
    Add("native:whitelist-redo", added, Snapshot(), calls)
    coverage.actions = coverage.actions + 1
    entry = Select("auras3_styling")
    local openSkins
    for _, record in ipairs(Records(entry)) do
        if record.controlId:match("%.style%.appearance%.icon%-skin%.open$") then openSkins = record end
    end
    assert(openSkins, "actual Aura IconSkin navigation owner missing")
    calls = {} before = Snapshot() openSkins.widget:Click("LeftButton") Settle()
    assert(M.activeKey == M.IconSkinsPage.PAGE, "Aura IconSkin native navigation reached another page")
    Add("native:IconSkin-navigation", before, Snapshot(), M.activeKey, M.GetHistoryState(), calls)
    Observe(Select("auras3_styling"), "native:IconSkin-return")
    entry = ShowUnit("uf_player", "custom4", "setup")
    local openStyle
    for _, record in ipairs(Records(entry)) do
        if record.controlId:match("%.unit%-workspace%.open%-aura%-style$") then openStyle = record end
    end
    assert(openStyle, "actual UnitAura global-style navigation missing")
    openStyle.widget:Click("LeftButton") Settle()
    assert(M.activeKey == "auras3_styling" and M.auraAppearanceContainer == "playerDefensives",
        "native UnitAura navigation lost selected container")
    Observe(assert(M.cache.auras3_styling), "native:UnitAura-style-navigation")
    coverage.actions = coverage.actions + 2
    assert(coverage.views >= 7 and coverage.headers > 0 and coverage.constructors > 0 and coverage.inputs > 0,
        "Aura fixture coverage was vacuous")
    assert(exercised.toggle and exercised.dropdown and exercised.slider and exercised.textinput, "native Aura input kind absent")
    Add("coverage", coverage, exercised)
    return rows, Snapshot()
end
local function Compare(parentRows, candidateRows, tag)
    assert(#parentRows == #candidateRows, "Aura observation count drift: " .. tag)
    for index, row in ipairs(parentRows) do
        assert(row == candidateRows[index], "Aura parent parity drift: " .. tag .. ":" .. index .. ":" .. row:match("^[^\t]+"))
    end
end
local total = 0
for _, width in ipairs({ 720, 400 }) do
    local expected, parentSaved
    if hasParent then expected, parentSaved = Replay(true, width) end
    local actual, saved = Replay(false, width)
    if hasParent then Compare(expected, actual, "ordinary:" .. width) end
    total = total + #actual
    if width == 720 then
        local expectedFresh
        if hasParent then expectedFresh = Replay(true, width, parentSaved) end
        local actualFresh = Replay(false, width, saved)
        if hasParent then Compare(expectedFresh, actualFresh, "fresh") end
        total = total + #actualFresh
    end
end
print("menu_aura_workspaces_schema_parity_smoke " .. flavor .. ":" .. total .. " exact observations PASS")
