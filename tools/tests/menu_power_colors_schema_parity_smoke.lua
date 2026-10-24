-- Four native Power Bar Colors owners, replayed against the immutable f2a source.
-- Offline semantics and native fixture paint only; no live client or performance claim.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local mode = arg[3] or "full"
assert(mode == "full" or mode == "push" or mode == "original", "unknown Power Colors tier")
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Resources.lua"
local blob = "6656d9e40cacf9de6a47eb5b5b890ba932b38e8f"
local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root .. '" show ' .. blob, "r"))
local source = pipe:read("*a") assert(pipe:close(), "immutable Resources source read failed")
assert(source:find('local function BuildPowerAndClassPowerColors', 1, true), "immutable Resources source missing")
local scratch, owned, diagnostic, diagnosticPath = os.tmpname()
local function Run()
owned = assert(io.open(scratch, "wb")) assert(owned:write(source)) assert(owned:close()) owned = nil
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
local function Replay(original, width)
    print("Power Colors " .. flavor .. ": " .. (original and "immutable parent" or "candidate") .. ":" .. width)
    local loaded = 0
    local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
        clientScriptBindings = true, nativeButtonLifecycle = true,
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
            local toc = assert(io.open(tocPath, "rb"), "Power core TOC metadata missing")
            local metadata = toc:read("*a")
            assert(toc:close(), "Power core TOC metadata close failed")
            local prefix = assert(metadata, "Power core TOC metadata unreadable"):match("\n## X%-MSUF%-UnitFrames%-Prefix:%s*([^\r\n]+)")
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
            local power = world.env.MSUF_CP_CONST.PT
            assert(power.Mana == 0 and power.Rage == 1 and power.ComboPoints == 4, "native captured power identities drift")
            assert(world.core.UF.frameNamePrefix == "MSUF", "native unit-frame prefix metadata was not loaded")
            -- Native ColorSelect methods used by ContextColorPicker600-624; local fixture only.
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
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if path:gsub("\\", "/") == root .. "/" .. target then
                    loaded = loaded + 1
                    if original then path = scratch elseif arg[4] and arg[4] ~= "-" then path = arg[4] end
                end
                return load(self, path, addon, namespace)
            end
        end })
    assert(loaded == 1, "exact Resources source not loaded once")
    local M, env, core = mw.M, mw.env, mw.core
    assert(env.MSUF_DB.bars.showClassPower ~= false, "Power fixture disabled the real ClassPower setting")
    local F, rows, ids, calls, clicked = core.ProfileFields, {}, {}, {}, {}
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Snapshot() local copy, ok, why = F.CopySnapshot(env.MSUF_DB) assert(ok, why) return copy end
    local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function SameDB(expected, tag) assert(Equal(expected, env.MSUF_DB), "whole DB drift: " .. tag) end
    local function Settle()
        mw:RunTimers()
        for _, frame in ipairs(mw.world.widgets.frames) do
            for _, key in ipairs({ "_msuf2AlphaFade", "_msuf2AlphaScale" }) do
                local group = frame[key]
                if group and group:IsPlaying() and group:GetScript("OnFinished") then
                    group:Finish() MenuWorld.FireScript(group, "OnFinished")
                end
            end
            for _, selection in ipairs(frame._msuf2SelectionMotions or {}) do
                local driver = selection.driver
                for _ = 1, 120 do
                    if not (driver and driver:GetScript("OnUpdate")) then break end
                    MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                end
                assert(not (driver and driver:GetScript("OnUpdate")), "finite selection motion did not settle")
            end
        end
        mw:RunTimers()
    end
    local function Shown(w)
        while w do if not w:IsShown() then return false end w = w:GetParent() end return true
    end
    local function Text(w)
        return w and Pack(w:GetText(), Pack(w:GetTextColor()), Pack(w:GetFont()), w:IsShown(), w:GetAlpha()) or {}
    end
    local function Paint(w)
        if not w then return {} end
        if w.L or w.M or w.R then
            assert(w.L and w.M and w.R and not w.GetObjectType, "native paint composite shape drift")
            return { Paint(w.L), Paint(w.M), Paint(w.R) }
        end
        assert(w:GetObjectType() == "Texture", "native paint texture kind drift")
        return { Pack(w:GetVertexColor()), w.colorTexture, w:IsShown(), w:GetAlpha() }
    end
    local function PaintedRGB(w, rgb, role)
        if w.GetObjectType then
            assert(w:GetObjectType() == "Texture" and w:IsShown() and w:GetAlpha() == 1, "native swatch visibility/kind drift: " .. role)
            assert(Equal(Pack(w:GetVertexColor()), Pack(rgb[1], rgb[2], rgb[3], 1)), "native swatch RGB drift: " .. role)
        else
            assert(w.L and w.M and w.R, "native swatch composite drift: " .. role)
            for _, key in ipairs({ "L", "M", "R" }) do PaintedRGB(w[key], rgb, role .. "." .. key) end
        end
    end
    local commandOwners, recordRevisions, catalogRecords = {}, {}, {}
    local function Item(id)
        local item = assert(M.RuntimeControlCatalog.Get(id), "current native owner missing: " .. id)
        catalogRecords[id] = item
        return assert(item.widget, "current native widget missing: " .. id)
    end
    local function ID(path) return M.ControlMeta("opt_colors", "advanced", path).controlId end
    local expected = {
        [ID("power.color_by_class")] = { kind = "toggle", label = "Power bar color by class" },
        [ID("power.editor.resource_selector")] = { kind = "dropdown", label = "Power type" },
        [ID("power.editor.color")] = { kind = "color", label = "Color" },
        [ID("power.editor.reset")] = { kind = "button", label = "Reset" },
    }
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    assert(M.cache.opt_colors == nil, "Power cold build already cached")
    assert(mw:Select("opt_colors"))
    local category = Item(ID("preview.scope.selector"))
    local resourceButton
    for _, button in ipairs(category.buttons) do if button._msuf2Value == "resources" then resourceButton = button end end
    assert(resourceButton and Shown(resourceButton), "native Resources category missing")
    resourceButton:Click("LeftButton") Settle()
    assert(category:GetValue() == "resources" and M.colorsPainterCategory == "resources", "native Resources category callback drift")
    local entry, controls, section = assert(M.cache.opt_colors), {}, nil
    section = assert(entry.sections.colors_power, "Power section missing")
    local disclosure = assert(section._msuf2CollapsibleEntry)
    local headerRecord = assert(disclosure.header._msuf2RuntimeControlRecord)
    assert(headerRecord.kind == "toggle" and Item(headerRecord.controlId) == disclosure.header, "Power native header owner drift")
    ids[disclosure.header] = headerRecord.controlId
    if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
    assert(disclosure.open and Shown(section), "native Power section did not open")
    assert(section._msuf2Width == width, "fresh Power section width drift")
    ids[section], ids[entry.wrapper] = "colors_power", "opt_colors.wrapper"
    local prefix = ID("power") .. "."
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if record.pageKey == "opt_colors" and record.controlId:sub(1, #prefix) == prefix then
            local spec, widget = assert(expected[record.controlId], "unexpected Power owner: " .. record.controlId), Item(record.controlId)
            assert(record.kind == spec.kind and widget._msuf2RuntimeControlRecord.controlId == record.controlId, "Power native identity/kind drift")
            assert(widget:GetParent() == section and Shown(widget), "Power current owner parent/visibility drift")
            assert(not controls[record.controlId], "duplicate Power native ID")
            controls[record.controlId], ids[widget] = widget, record.controlId
            if spec.kind ~= "button" then
                assert(widget._msuf2CommandAction and widget._msuf2CommandAction.get and widget._msuf2CommandAction.set, "real Power binding owner missing")
            end
            if not original then
                local declared = assert(widget._msuf2ControlSchema, "Power schema owner missing")
                assert(declared.id == record.controlId and declared.kind == spec.kind and declared.scope == "colors"
                    and declared.applyDomain == "powerColors", "Power schema owner contract drift")
            end
        end
    end
    local census = 0 for id in pairs(expected) do assert(controls[id], "Power owner missing: " .. id) census = census + 1 end
    assert(census == 4, "Power owner census drift")
    if not original then
        local declared = assert(disclosure.header._msuf2ControlSchema, "Power section schema owner missing")
        assert(declared.id == disclosure.header._msuf2RuntimeControlRecord.controlId and declared.scope == "colors"
            and declared.applyDomain == "sectionNavigation", "Power header declaration drift")
    end
    local toggle, selector, color, reset = controls[ID("power.color_by_class")], controls[ID("power.editor.resource_selector")],
        controls[ID("power.editor.color")], controls[ID("power.editor.reset")]
    local function Model(widget) return Pack(widget._msuf2CommandAction.get()) end
    local function RecordObservation(w, id)
        local record, command = w._msuf2RuntimeControlRecord, w._msuf2CommandAction
        assert(type(record) == "table" and record == catalogRecords[id] and record.widget == w and record.controlId == id,
            "Power catalog physical record owner drift")
        assert(record.command == command and (command == nil or type(command) == "table"), "Power catalog native command owner drift")
        if command then
            assert(command.controlId == id and command.ctxKey == "opt_colors" and command.kind == expected[id].kind,
                "Power catalog command identity contract drift")
            assert(commandOwners[command] == nil or commandOwners[command] == id, "Power shared native command identity")
            commandOwners[command] = id
        end
        local parts = {
            tostring(record.controlId or ""), tostring(record.pageKey or ""), tostring(record.kind or ""),
            tostring(record.label or ""), tostring(record.identityLabel or ""), tostring(record.controlPath or ""),
            tostring(record.settingKey or ""), tostring(record.actionKey or ""), tostring(record.navigationKey or ""),
            tostring(record.help or ""), tostring(record.classification or ""), tostring(record.command or ""),
            table.concat(record.searchSettingKeys or {}, "\030") .. "\029" .. table.concat(record.searchSettingKeyPatterns or {}, "\030"),
            record.searchIndexed and "1" or "0",
        }
        assert(type(record._revisionKey) == "string" and record._revisionKey == table.concat(parts, "\031"),
            "Power catalog revision derivation drift")
        parts[12] = { kind = command and "bound-command" or "no-command", controlId = command and commandOwners[command] or false }
        local previous = recordRevisions[id]
        if previous then
            assert(previous.record == record and previous.command == command, "Power catalog local binding identity changed")
            assert(not command or (previous.get == command.get and previous.set == command.set and previous.sourceFn == command.sourceFn),
                "Power catalog bound callbacks changed")
            assert((previous.raw == record._revisionKey) == Equal(previous.parts, parts), "Power catalog local revision transition drift")
        end
        recordRevisions[id] = { record = record, command = command, raw = record._revisionKey, parts = parts,
            get = command and command.get, set = command and command.set, sourceFn = command and command.sourceFn }
        local observed = {} for key, value in pairs(record) do observed[key] = value end
        observed._revisionKey = { kind = "catalog-revision", parts = parts }
        return observed
    end
    local function Display(tag)
        for id, spec in pairs(expected) do
            local w = controls[id]
            assert(Item(id) == w and w:GetParent() == section, "Power physical native owner changed")
            local label = w._msuf2Title or w._label or w._msuf2Label
            if spec.kind == "toggle" then assert(Equal(Model(w), Pack(w:GetChecked())), "Power toggle display drift")
            elseif spec.kind == "dropdown" then
                assert(Equal(Model(w), Pack(w:GetValue())), "Power dropdown display drift")
                local found
                for _, value in ipairs(w.values) do if value.value == w:GetValue() then found = value.text end end
                assert(found and w:GetText() == found, "Power selected dropdown caption drift")
            elseif spec.kind == "color" then
                assert(Equal(Model(w), Pack(w:GetRGB())), "Power swatch model/display drift")
                PaintedRGB(w._msuf2Swatch, Model(w), "Power")
            end
            assert(label and label:GetText() == spec.label, "Power native label drift")
            local points = {} for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
            Add(tag .. ":" .. id, RecordObservation(w, id), w._msuf2SearchMeta, spec.kind ~= "button" and Model(w),
                spec.kind == "color" and Pack(w:GetRGB()) or spec.kind == "toggle" and Pack(w:GetChecked())
                    or spec.kind == "dropdown" and Pack(w:GetValue()), Text(label), Text(w._msuf2Label), points, Pack(w:GetSize()), w:IsShown(), w:IsEnabled(), w:GetAlpha(),
                Paint(w._msuf2Swatch), Paint(w._msuf2Fill), Paint(w._msuf2Edge))
        end
        Add(tag .. ":header", disclosure.open, section:IsShown(), section:GetHeight(), Text(disclosure.label), disclosure.arrow.rotation)
    end
    local function Refresh(tag)
        local before = Snapshot() M.Refresh() Settle() SameDB(before, tag .. ":refresh-read-only") Display(tag .. ":refresh")
    end
    local function Select(value)
        local before, history = Snapshot(), Encode(M.GetHistoryState(), ids)
        selector:Click("LeftButton") Settle()
        if not selector:IsEnabled() or M.IsConfigCombatLocked() then return end
        local selected
        for _, row in ipairs(mw.world.widgets.frames) do
            if row._msuf2Owner == selector and row._msuf2Value == value and Shown(row) and not row._msuf2DropdownDisabled then selected = row end
        end
        assert(selected and selected:GetScript("OnClick"), "native Power dropdown row missing")
        selected:Click("LeftButton") Settle() clicked[ids[selector]] = true
        assert(selector:GetValue() == value and M.colorsPowerToken == value, "native Power dropdown selection drift")
        SameDB(before, "Power ephemeral selection")
        assert(Encode(M.GetHistoryState(), ids) == history, "Power selector created profile history")
    end
    local function Panel()
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.owner == color and frame.compactHex and Shown(frame) then return frame end
        end
    end
    local function OpenPicker()
        color:Click("LeftButton") Settle()
        local panel = Panel()
        if not color:IsEnabled() then assert(not panel, "disabled Power swatch opened picker") return end
        assert(panel and panel.done and panel.cancel, "native Power picker owner missing")
        if not panel._powerVisibilityFixture then MenuWorld.FireVisibilityScripts(panel) panel._powerVisibilityFixture = true end
        assert(panel.owner == color, "Power picker owner drift")
        return panel
    end
    local function PickerPaint(panel, tag)
        local rgb = Pack(color:GetRGB())
        PaintedRGB(panel.current.fill, rgb, "picker.current") PaintedRGB(panel.selector.color.fill, rgb, "picker.selector")
        Add(tag, Text(panel.title), Text(panel.selector.label), Text(panel.compactHex), Paint(panel.current.fill), Paint(panel.selector.color.fill))
    end
    local function Hex(panel, value)
        panel.compactHex:SetText(value) MenuWorld.FireScript(panel.compactHex, "OnTextChanged", true)
        MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle()
    end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, Pack(...) } return fn(...)
        end end
    end
    local coldDB, coldHistory = Snapshot(), Encode(M.GetHistoryState(), ids)
    local panel = OpenPicker() PickerPaint(panel, "cold-picker-open")
    Add("cold-picker-open-profile", coldDB, Snapshot())
    assert(Encode(M.GetHistoryState(), ids) == coldHistory, "cold Power picker created history")
    assert(Equal(coldDB.general, env.MSUF_DB.general), "cold Power picker changed color settings")
    panel.cancel:Click("LeftButton") Settle() assert(not Panel() and not panel.blocker:IsShown(), "native cold picker close drift")
    local warmDB = Snapshot()
    panel = OpenPicker() PickerPaint(panel, "warm-picker-open") panel.cancel:Click("LeftButton") Settle()
    SameDB(warmDB, "warm picker read-only")
    local factory = Snapshot()
    local function Setup(state)
        Restore(env.MSUF_DB, factory)
        local general = env.MSUF_DB.general
        general.powerColorOverrides = { MANA = { 0.2, 0.4, 0.6 }, RAGE = { 0.8, 0, 0.1 } }
        general.powerColorMode = state == "edge" and "class" or "power"
        general.powerFixtureExtension = { enabled = false, amount = 0 }
        if state == "default" then general.powerColorMode, general.powerColorOverrides = nil, nil end
        Select("MANA") M.ClearHistory() Settle() calls = {} Refresh("setup:" .. state)
    end
    local function DefaultRGB(token)
        local red, green, blue = env.MSUF_GetDefaultPowerColor(token)
        if tonumber(red) and tonumber(green) and tonumber(blue) then return Pack(tonumber(red), tonumber(green), tonumber(blue)) end
        local native = env.PowerBarColor and env.PowerBarColor[token]
        if type(native) == "table" then
            red, green, blue = tonumber(native.r or native[1]), tonumber(native.g or native[2]), tonumber(native.b or native[3])
            if red and green and blue then return Pack(red, green, blue) end
        end
        return Pack(0.8, 0.8, 0.8)
    end
    local function RefusePending(pending, baseline)
        local db, history = Snapshot(), Encode(M.GetHistoryState(), ids)
        local undoCount, redoCount = #M.historyUndo, #M.historyRedo
        local active = OpenPicker() SameDB(db, "pending picker open")
        for _, locked in ipairs({ false, true }) do
            core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return locked end
            assert(M.IsConfigCombatLocked(), "Power combat event-edge owner missing")
            calls = {} toggle:Click("LeftButton") Select("RAGE") Hex(active, "B34411") reset:Click("LeftButton") Settle()
            assert(M.Redo() == false and M.Undo() == false, "Power history accepted combat")
            SameDB(db, "Power pending combat refusal") Display(locked and "lockdown" or "event-edge")
            assert(#calls == 0, "Power refused combat input applied")
            assert(M.historyRedo[#M.historyRedo] == pending and #M.historyUndo == undoCount and #M.historyRedo == redoCount,
                "Power combat destroyed exact pending Redo entry")
            assert(Encode(M.GetHistoryState(), ids) == history, "Power combat changed history state")
        end
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle() active.cancel:Click("LeftButton") Settle()
        SameDB(db, "Power combat release") assert(M.historyRedo[#M.historyRedo] == pending, "Power release destroyed pending Redo")
        assert(M.Redo(), "Power post-refusal Redo missing") Settle() SameDB(baseline, "Power post-refusal Redo") Display("post-refusal-redo")
    end
    local function RequestedColors()
        for _, call in ipairs(calls) do
            if call[1] == "RequestColors" and call[2][1] == "MSUF2_COLORS" then return true end
        end
        return false
    end
    local function Case(kind, state, prepare)
        Setup(state)
        if prepare then prepare(env.MSUF_DB.general) Refresh("independent-absent-input") M.ClearHistory() end
        if kind == "reset" then
            env.MSUF_DB.general.powerColorOverrides = { MANA = { 0.2, 0.4, 0.6 } }
            local seededDB, applyCount = Encode(env.MSUF_DB, ids), #calls
            assert(M.ClearHistory(), "Power Reset seed history initialization failed")
            assert(Encode(env.MSUF_DB, ids) == seededDB, "Power Reset history initialization changed raw whole DB")
            assert(#calls == applyCount, "Power Reset history initialization applied runtime")
            assert(#M.historyUndo == 0 and #M.historyRedo == 0, "Power Reset seed history stacks are not empty")
            Refresh("reset-seed")
        end
        local active
        if kind == "color" then active = OpenPicker() M.ClearHistory() end
        local before, value = Snapshot()
        if kind == "toggle" then value = not toggle:GetChecked() end
        calls = {}
        if kind == "toggle" then toggle:Click("LeftButton") clicked[ids[toggle]] = true
        elseif kind == "selector" then Select("RAGE")
        elseif kind == "color" then
            Hex(active, "0040FF") PickerPaint(active, "native-color-edit") active.done:Click("LeftButton") clicked[ids[color]] = true
        else reset:Click("LeftButton") clicked[ids[reset]] = true end
        Settle() Display(state .. ":" .. kind .. ":input")
        local after = Snapshot()
        if kind == "selector" then
            SameDB(before, "Power selector") assert(#calls == 0 and M.Undo() == false and M.Redo() == false, "Power selector mutated/applied history")
        else
            assert(not Equal(before, after), "Power native input did not change DB: " .. kind)
            assert(RequestedColors(), "Power native input did not request colors: " .. kind)
            if kind == "toggle" then assert(env.MSUF_DB.general.powerColorMode == (value and "class" or "power"), "Power class-color setter drift")
            elseif kind == "color" then
                assert(Equal(env.MSUF_DB.general.powerColorOverrides.MANA, { 0, 64 / 255, 1 }), "Power native color setter drift")
            else assert(env.MSUF_DB.general.powerColorOverrides.MANA == nil, "Power reset did not clear selected override") end
            Add(state .. ":" .. kind .. ":write", before, after, calls)
            Refresh(state .. ":" .. kind .. ":input")
            assert(M.Undo(), "Power input created no Undo entry: " .. kind) Settle()
            SameDB(before, "Power automatic Undo") Display(state .. ":" .. kind .. ":undo")
            local pending = assert(M.historyRedo[#M.historyRedo], "Power exact pending Redo missing")
            Refresh(state .. ":" .. kind .. ":undo") RefusePending(pending, after)
            Refresh(state .. ":" .. kind .. ":redo")
        end
        Refresh(state .. ":" .. kind .. ":final")
    end
    Display("initial")
    local beforeOpen = disclosure.open
    disclosure.header:Click("LeftButton") Settle() assert(disclosure.open ~= beforeOpen, "native Power header did not toggle")
    disclosure.header:Click("LeftButton") Settle() assert(disclosure.open == beforeOpen and Shown(section), "native Power header did not restore")
    Add("native-balanced-header", headerRecord.controlId, disclosure.open, Text(disclosure.label), section:IsShown())
    for _, state in ipairs({ "default", "edge" }) do
        for _, kind in ipairs({ "toggle", "selector", "color", "reset" }) do Case(kind, state) end
    end
    local absent = {
        { "mode", function(g) g.powerColorMode, g.powerBarColorMode = nil, nil end, "toggle", false },
        { "legacy-mode", function(g) g.powerColorMode, g.powerBarColorMode = nil, "class" end, "toggle", true },
        { "override-container", function(g) g.powerColorOverrides = nil end, "color" },
        { "selected-override", function(g) g.powerColorOverrides.MANA = nil end, "color" },
        { "false-container", function(g) g.powerColorOverrides = false end, "color" },
        { "zero-record", function(g) g.powerColorOverrides.MANA = 0 end, "color" },
        { "component", function(g) g.powerColorOverrides.MANA[1] = nil end, "component" },
    }
    for _, spec in ipairs(absent) do
        Setup("edge") spec[2](env.MSUF_DB.general)
        local before = Snapshot() Refresh("absent:" .. spec[1]) SameDB(before, "Power genuine independent absence")
        if spec[3] == "toggle" then assert(toggle:GetChecked() == spec[4], "Power absent mode fallback drift")
        elseif spec[3] == "color" then assert(Equal(Pack(color:GetRGB()), DefaultRGB("MANA")), "Power absent RGB fallback drift")
        else assert(color:GetRGB() == DefaultRGB("MANA")[1], "Power absent component fallback drift") end
        Add("independent-absence:" .. spec[1], before, Snapshot())
        Case(spec[3] == "toggle" and "toggle" or "color", "edge", spec[2])
    end
    Setup("edge")
    env.MSUF_DB.general.powerColorOverrides.MANA = { false, 0, 1 }
    local sparse = Snapshot() Refresh("false-zero") SameDB(sparse, "Power false/zero read-only")
    local red, green, blue = color:GetRGB()
    assert(Equal(Pack(red, green, blue), DefaultRGB("MANA")), "Power explicit false/zero RGB fallback drift")
    assert(env.MSUF_DB.general.powerColorOverrides.MANA[1] == false
        and env.MSUF_DB.general.powerColorOverrides.MANA[2] == 0 and env.MSUF_DB.general.powerColorOverrides.MANA[3] == 1,
        "Power malformed false/zero RGB record changed")
    Setup("edge")
    env.MSUF_DB.general.powerColorOverrides.MANA = { 0, 0, 1 }
    sparse = Snapshot() Refresh("valid-zero") SameDB(sparse, "Power valid zero RGB read-only")
    red, green, blue = color:GetRGB()
    assert(red == 0 and green == 0 and blue == 1, "Power valid explicit zero RGB drift")
    for _, modeValue in ipairs({ false, 0 }) do
        Setup("edge")
        local general = env.MSUF_DB.general
        general.powerColorMode, general.powerBarColorMode = modeValue, "class"
        local before = Snapshot() Refresh("mode-false-zero") SameDB(before, "Power false/zero mode read-only")
        assert(toggle:GetChecked() == (modeValue == false), "Power false/zero legacy mode fallback drift")
        Case("toggle", "edge", function(g) g.powerColorMode, g.powerBarColorMode = modeValue, "class" end)
    end
    local values = selector.values
    assert(type(values) == "table" and #values == 11, "Power type option census drift")
    for i, option in ipairs(values) do
        if mode ~= "push" or i <= 2 then
            Setup("edge") local before = Snapshot() calls = {} Select(option.value) Display("native-token:" .. option.value)
            SameDB(before, "Power token changed global profile scope") assert(#calls == 0, "Power token selector applied")
            assert(Equal(Pack(color:GetRGB()), Pack(M.ColorsPage.GetPowerOverrideRGB(option.value))), "Power selected token RGB routing drift")
            Add("native-token:" .. option.value, option, before, M.GetHistoryState())
        end
    end
    Setup("edge")
    for id in pairs(expected) do
        local w = controls[id] local before, history = Snapshot(), Encode(M.GetHistoryState(), ids)
        M.Widgets.SetControlEnabled(w, false) assert(w:IsEnabled() == false, "Power native disable failed") calls = {}
        w:Click("LeftButton") Settle() SameDB(before, "Power disabled native click")
        assert(#calls == 0 and Encode(M.GetHistoryState(), ids) == history, "Power disabled click applied/history drift")
        M.Widgets.SetControlEnabled(w, true) assert(w:IsEnabled(), "Power native enable failed") Display("disabled-restored:" .. id)
    end
    for id in pairs(expected) do assert(clicked[id], "Power ordinary native owner unexercised: " .. id) end
    local old = entry.wrapper
    assert(mw:Select("home")) assert(mw:Select("opt_colors")) Settle()
    assert(M.cache.opt_colors.wrapper == old, "warm Power page unexpectedly rebuilt")
    Display("warm-reopen") Add("final-profile", Snapshot())
    return rows
end
local total, started = 0, os.clock()
for _, width in ipairs({ 720, 400 }) do
    local expected = Replay(true, width)
    if mode == "original" then total = total + #expected else
        local actual = Replay(false, width)
        assert(#expected == #actual, "Power observation census drift")
        for i = 1, #expected do
            if expected[i] ~= actual[i] then
                diagnosticPath = os.tmpname() diagnostic = assert(io.open(diagnosticPath, "wb"))
                assert(diagnostic:write("parent\n", expected[i], "\ncandidate\n", actual[i], "\n"))
                assert(diagnostic:close()) diagnostic = nil
                io.stderr:write("Power Colors retained mismatch: " .. diagnosticPath .. "\n")
                error("Power parity drift at observation " .. i .. ":" .. expected[i]:match("^[^\t]+"))
            end
        end
        total = total + #expected
    end
end
print(string.format("menu_power_colors_schema_parity_smoke %s %s:4 owners/%d observations, native/default/edge/absence/false0/display/history/combat/400px exact (%.2fs)",
    mode, flavor, total, os.clock() - started))
end
local ok, why = xpcall(Run, debug.traceback)
if owned then assert(owned:close()) owned = nil end
if diagnostic then assert(diagnostic:close()) diagnostic = nil end
local removed, removeWhy = os.remove(scratch)
assert(removed, "owned parent cleanup failed: " .. tostring(removeWhy))
if not ok then error(why, 0) end
