-- Native Castbar Text owners; optional immutable parent path enables exact replay.
-- lua menu_castbar_text_schema_smoke.lua <root> <flavor> [parent-page] [candidate-page]
-- Candidate-only is the stable gate contract; an override is diagnostic-only.
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
local prefixes = { player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus",
    boss = "bossCast", arena = "arenaCast" }
local units = { "player", "target", "focus", "boss", "arena" }
local suffixes = { "SpellName", "Time", "TargetName" }
local paths = { "spell_name", "time", "target_name" }
local function Sparse(g)
    for _, prefix in pairs(prefixes) do
        for _, suffix in ipairs(suffixes) do
            for _, channel in ipairs({ "R", "G", "B" }) do g[prefix .. suffix .. "Color" .. channel] = nil end
        end
    end
    g.castbarTextSchemaExtension = { enabled = false, amount = 0, unknown = "keep" }
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
local function Replay(width, original)
    local override, loaded = original and parent or candidate, 0
    local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
        clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = InstallNativeInputs,
        beforeOptions = function(world)
            InstallColorSelect(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if path:gsub("\\", "/") == root .. "/" .. target then
                    loaded = loaded + 1 if override then path = override end
                end
                return load(self, path, addon, namespace)
            end
        end })
    assert(loaded == 1, "real AdvancedColors page must load exactly once per world")
    local M, env, core = mw.M, mw.env, mw.core
    local ids, rows, calls, controls = {}, {}, {}, {}
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
                assert(not (driver and driver:GetScript("OnUpdate")), "finite native selection failed to settle")
            end
        end
        mw:RunTimers()
    end
    local function Shown(widget)
        while widget do if not widget:IsShown() then return false end widget = widget:GetParent() end return true
    end
    local function ID(path) return M.ControlMeta("opt_colors", "advanced", "castbar.text_color." .. path).controlId end
    local function Widget(path)
        local id = ID(path) local record = assert(M.RuntimeControlCatalog.Get(id), "owner missing: " .. path)
        local widget = assert(record.widget) ids[widget] = id controls[path] = widget return widget
    end
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    -- The player preview first reads this existing Aura menu model on Colors.
    -- Prepare its unrelated one-shot normalization while the page stays cold.
    assert(M.cache.opt_colors == nil, "target page was not cold before Aura model preparation")
    local auraModel = assert(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel)
    local auraRecord = assert(env.MSUF_DB.auras3.customContainers.perUnit.player)
    local auraItem = assert(auraRecord.items[4])
    local auraPlaced = assert(auraItem.placed)
    local expectedAura = Snapshot()
    local expectedRecord = expectedAura.auras3.customContainers.perUnit.player
    local expectedItem = expectedRecord.items[4]
    assert(expectedRecord._msufA3CustomContainersMigrated_v1 == nil
        and expectedItem._msufA3LocalStyleFromShared_v1 == nil and expectedItem.placed.iconShape == nil,
        "fresh Aura menu-model normalization fixture drift")
    assert(auraModel.CustomContainer("player", 4, false) == auraItem,
        "Aura model preparation replaced the existing item")
    expectedRecord._msufA3CustomContainersMigrated_v1 = true
    expectedItem._msufA3LocalStyleFromShared_v1 = true
    expectedItem.placed.iconShape = "RECTANGLE"
    assert(Equal(expectedAura, env.MSUF_DB), "Aura model preparation changed unexpected profile paths")
    assert(env.MSUF_DB.auras3.customContainers.perUnit.player == auraRecord and auraItem.placed == auraPlaced,
        "Aura model preparation replaced existing profile objects")
    local preparedAura = Snapshot()
    assert(auraModel.CustomContainer("player", 4, false) == auraItem, "Aura model repeat replaced the existing item")
    SameDB(preparedAura, "Aura model preparation idempotence")
    assert(M.cache.opt_colors == nil, "Aura model preparation built the target page")
    Sparse(env.MSUF_DB.general)
    local fresh = Snapshot()
    assert(M.cache.opt_colors == nil, "target page was not cold")
    assert(mw:Select("opt_colors"))
    local category = assert(M.RuntimeControlCatalog.Get(M.ControlMeta("opt_colors", "advanced", "preview.scope.selector").controlId)).widget
    assert(category:GetValue() ~= "cast", "castbar category was not lazy")
    local button
    for _, value in ipairs(category.buttons) do if value._msuf2Value == "cast" then button = value end end
    assert(button and Shown(button), "native Castbars category missing") button:Click("LeftButton") Settle()
    local entry = assert(M.cache.opt_colors)
    local section = assert(entry.sections.colors_castbar_text)
    local disclosure = assert(section._msuf2CollapsibleEntry)
    if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
    assert(disclosure.open and Shown(section) and section._msuf2Width == width, "section lazy layout drift")
    ids[section], ids[entry.wrapper] = "colors_castbar_text", "opt_colors.wrapper"
    local selector, reset = Widget("unit"), Widget("reset")
    for _, path in ipairs(paths) do Widget(path) end
    SameDB(fresh, "fresh sparse category construction")
    if not original then
        local header = assert(disclosure.header._msuf2ControlSchema, "real header declaration missing")
        assert(header.owner == disclosure.header and header.applyDomain == "sectionNavigation", "header owner drift")
    end
    local nativeKinds = { unit = "dropdown", reset = "button", spell_name = "color", time = "color", target_name = "color" }
    for path, widget in pairs(controls) do
        local record = widget._msuf2RuntimeControlRecord
        assert(record.kind == nativeKinds[path] and widget:GetParent() == section, "native kind/parent drift")
        if path ~= "reset" then
            local command = assert(widget._msuf2CommandAction)
            assert(command.get and command.set and command.settingKey == nil and command.historyScope == nil,
                "dynamic whole-profile history metadata drift")
        end
        if path == "unit" or path == "reset" then assert(record.classification == "ephemeral", "ephemeral disposition lost") end
        if not original then
            local spec = assert(widget._msuf2ControlSchema, "ordinary declaration missing: " .. path)
            assert(spec.id == ids[widget] and spec.kind == record.kind and spec.scope == "colors", "declaration identity drift")
            assert(spec.applyDomain == (path == "unit" and "menuState" or "castbar"), "declaration domain drift")
            if path == "reset" then assert(spec.owner == widget and type(spec.action) == "function", "owned action drift") end
        end
    end
    local ownerCount, ownerPrefix = 0, ID("unit"):sub(1, -5)
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if record.controlId:sub(1, #ownerPrefix) == ownerPrefix then ownerCount = ownerCount + 1 end
    end
    assert(ownerCount == 5, "Castbar Text native owner census drift")
    local function Paint(texture)
        if not texture then return nil end
        if texture.GetObjectType then return Pack(texture:GetVertexColor()) end
        return { Paint(texture.L), Paint(texture.M), Paint(texture.R) }
    end
    local function Display(tag)
        local values = {}
        for _, path in ipairs({ "unit", "spell_name", "time", "target_name", "reset" }) do
            local widget = controls[path]
            local points = {} for index = 1, widget:GetNumPoints() do points[index] = Pack(widget:GetPoint(index)) end
            local model, displayed
            if path == "unit" then model, displayed = selector._msuf2CommandAction.get(), selector:GetValue()
            elseif path ~= "reset" then
                model, displayed = Pack(widget._msuf2CommandAction.get()), Pack(widget:GetRGB())
                assert(Equal(Pack(model[1], model[2], model[3]), displayed), "displayed RGB/model drift: " .. path)
                local suffix = path == "spell_name" and "SpellName" or path == "time" and "Time" or "TargetName"
                local red, green, blue, custom = env.MSUF_GetCastbarDetailTextColor(selector:GetValue(), suffix)
                if custom ~= true then red, green, blue = core._colorsAPI.GetCastbarTextColor() end
                assert(Equal(displayed, Pack(red, green, blue)), "selected-family RGB routing drift: " .. path)
                assert(widget._msuf2DefaultRGB == nil, "detail swatch gained a fixed right-click default")
            end
            local label = widget._msuf2Title or widget._msuf2Label
            values[#values + 1] = { path, model, displayed, points, Pack(widget:GetSize()), widget:IsShown(), widget:IsEnabled(),
                label and label:GetText(), label and label:GetWidth(), Paint(widget._msuf2Swatch), widget._msuf2SearchMeta }
        end
        assert(selector:GetValue() == (M._colorsCastbarDetailUnit or "player"), "selected unit display drift")
        assert(controls.target_name:IsEnabled() == (selector:GetValue() ~= "player"), "player target-color gate drift")
        Add(tag, values, disclosure.open, section:GetHeight(), selector.values)
    end
    local function Refresh(tag)
        local before = Snapshot() M.Refresh() Settle() SameDB(before, tag .. ":refresh-read-only") Display(tag)
    end
    local function Select(value)
        local before, history = Snapshot(), Encode(M.GetHistoryState(), ids)
        local effective, stored, applied = selector._msuf2CommandAction.get(), M._colorsCastbarDetailUnit, #calls
        selector:Click("LeftButton") Settle()
        if M.IsConfigCombatLocked() then return end
        local option
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame._msuf2Owner == selector and frame._msuf2Value == value and Shown(frame)
                and not frame._msuf2DropdownDisabled then option = frame end
        end
        assert(option and option:GetScript("OnClick"), "native unit option missing: " .. value)
        local requestRefresh, refreshes = assert(M.RequestRefresh), 0
        M.RequestRefresh = function(ctx, reason, ...)
            if reason == "castbar-text-color-unit" then refreshes = refreshes + 1 end
            return requestRefresh(ctx, reason, ...)
        end
        option:Click("LeftButton") Settle()
        M.RequestRefresh = requestRefresh
        assert(selector:GetValue() == value and selector._msuf2CommandAction.get() == value, "unit selection drift")
        if effective == value then
            assert(M._colorsCastbarDetailUnit == stored and refreshes == 0, "no-op unit selection changed session state/refreshed")
        else
            assert(M._colorsCastbarDetailUnit == value and refreshes == 1, "unit transition lost session state/refresh")
        end
        assert(#calls == applied, "unit selection applied stored colors")
        SameDB(before, "ephemeral unit selection") assert(Encode(M.GetHistoryState(), ids) == history, "selector added profile history")
    end
    local function Panel(widget)
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.owner == widget and frame.compactHex and Shown(frame) then return frame end
        end
    end
    local function OpenPicker(widget, mouseButton)
        widget:Click(mouseButton or "LeftButton") Settle()
        local panel = Panel(widget) assert(panel and panel.done and panel.cancel, "native detail picker missing")
        if not panel._castTextVisibilityFixture then MenuWorld.FireVisibilityScripts(panel) panel._castTextVisibilityFixture = true end
        return panel
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
    local function Applied()
        for _, call in ipairs(calls) do
            local args = call[2]
            if call[1] == "RequestGeneralDomains" and args[1] == "MSUF2_CASTBAR_COLORS" then
                local opts = args[2]
                if opts.castbar and opts.castbarTextures and opts.preview and opts.applyAll == false then return true end
            end
        end
        return false
    end
    assert(selector:GetValue() == "player" and selector._msuf2CommandAction.get() == "player"
        and M._colorsCastbarDetailUnit == nil, "fresh default unit selection was materialized")
    Display("cold-sparse")
    local warm = OpenPicker(controls.spell_name) warm.cancel:Click("LeftButton") Settle()
    local factory = Snapshot()
    local function Setup()
        Restore(env.MSUF_DB, factory)
        local g = env.MSUF_DB.general
        for index, unit in ipairs(units) do
            local prefix = prefixes[unit]
            for detailIndex, suffix in ipairs(suffixes) do
                g[prefix .. suffix .. "ColorR"], g[prefix .. suffix .. "ColorG"], g[prefix .. suffix .. "ColorB"] = index / 10, detailIndex / 10, 0.4
            end
        end
        M.ClearHistory() Refresh("setup") calls = {}
    end
    local function OtherFamilies(before, selected)
        local g = env.MSUF_DB.general
        for unit, prefix in pairs(prefixes) do
            if unit ~= selected then
                for _, suffix in ipairs(suffixes) do
                    for _, channel in ipairs({ "R", "G", "B" }) do
                        local key = prefix .. suffix .. "Color" .. channel
                        assert(g[key] == before.general[key], "input/reset touched another family: " .. key)
                    end
                end
            end
        end
        assert(Equal(g.castbarTextSchemaExtension, before.general.castbarTextSchemaExtension), "unknown false/zero extension changed")
    end
    local function Write(path, suffix)
        local widget, unit = controls[path], selector:GetValue()
        local before = Snapshot() M.ClearHistory() calls = {}
        local panel = OpenPicker(widget) Hex(panel, "0040FF") panel.done:Click("LeftButton") Settle()
        local g, key = env.MSUF_DB.general, prefixes[unit] .. suffix .. "Color"
        assert(g[key .. "R"] == 0 and g[key .. "G"] == 64 / 255 and g[key .. "B"] == 1,
            "input did not reach currently selected family/suffix")
        OtherFamilies(before, unit)
        assert(Applied(), "native detail input lost castbar domain apply")
        local after = Snapshot() Add("write:" .. unit .. ":" .. path, before, after, calls) Display("write")
        calls = {} assert(M.Undo(), "native color has no Undo") Settle() SameDB(before, "native color Undo") Refresh("undo")
        calls = {} assert(M.Redo(), "native color has no Redo") Settle() SameDB(after, "native color Redo") Refresh("redo")
        Add("history:" .. unit .. ":" .. path, before, after, M.GetHistoryState())
    end
    local expectedValues = M.FilterSupportedUnitValues(M.ValueTextPairs "player=Player|target=Target|focus=Focus|boss=Boss|arena=Arena")
    assert(Equal(selector.values, expectedValues), "supported unit choices drift")
    for _, option in ipairs(selector.values) do
        Setup() Select(option.value) calls = {} Display("selected:" .. option.value)
        assert(#calls == 0, "unit selector applied stored colors")
        if option.value == "player" then
            local before, history = Snapshot(), Encode(M.GetHistoryState(), ids)
            controls.target_name:Click("LeftButton") Settle()
            assert(not Panel(controls.target_name), "disabled Player target color opened a picker")
            SameDB(before, "disabled Player target color")
            assert(#calls == 0 and Encode(M.GetHistoryState(), ids) == history, "disabled target color applied/history drift")
        end
        for index, path in ipairs(paths) do
            if controls[path]:IsEnabled() then Write(path, suffixes[index]) end
        end
        local before = Snapshot() M.ClearHistory() calls = {} reset:Click("LeftButton") Settle()
        for _, suffix in ipairs(suffixes) do
            local key = prefixes[option.value] .. suffix .. "Color"
            assert(env.MSUF_DB.general[key .. "R"] == nil and env.MSUF_DB.general[key .. "G"] == nil
                and env.MSUF_DB.general[key .. "B"] == nil, "reset did not clear selected detail triple")
        end
        OtherFamilies(before, option.value)
        assert(Applied(), "reset lost castbar apply")
        local after = Snapshot() Add("reset:" .. option.value, before, after, calls) Refresh("reset")
        assert(M.Undo(), "owned reset lost Undo") Settle() SameDB(before, "reset Undo")
        assert(M.Redo(), "owned reset lost Redo") Settle() SameDB(after, "reset Redo") Refresh("reset-redo")
    end
    Setup() Select("target")
    local g = env.MSUF_DB.general
    g.castbarTargetSpellNameColorR, g.castbarTargetSpellNameColorG, g.castbarTargetSpellNameColorB = false, 0, 1
    g.castbarTargetTimeColorR, g.castbarTargetTimeColorG, g.castbarTargetTimeColorB = 0, 0, 1
    g.castbarTargetTargetNameColorR, g.castbarTargetTargetNameColorG, g.castbarTargetTargetNameColorB = nil, 0.5, 0
    local sparse = Snapshot() Refresh("independent-false-zero-nil") SameDB(sparse, "malformed values were materialized")
    local sr, sg, sb = core._colorsAPI.GetCastbarTextColor()
    assert(Equal(Pack(controls.spell_name:GetRGB()), Pack(sr, sg, sb)), "false triple must inherit shared text")
    assert(Equal(Pack(controls.time:GetRGB()), Pack(0, 0, 1)), "valid zero channels lost")
    assert(Equal(Pack(controls.target_name:GetRGB()), Pack(sr, sg, sb)), "partial triple must inherit shared text")
    for index, path in ipairs(paths) do Write(path, suffixes[index]) end
    Setup() Select("target") M.ClearHistory()
    local before = Snapshot() calls = {}
    controls.spell_name._msuf2OnColorChanged(controls.spell_name:GetRGB()) Settle()
    SameDB(before, "equal RGB no-op") assert(#calls == 0 and not M.Undo(), "equal RGB created apply/history")
    local right = OpenPicker(controls.spell_name, "RightButton")
    SameDB(before, "right click must retain original picker behavior")
    right.cancel:Click("LeftButton") Settle() SameDB(before, "right-click cancel")
    local panel = OpenPicker(controls.spell_name) Hex(panel, "B34411") panel.cancel:Click("LeftButton") Settle()
    SameDB(before, "native changed-color cancel") assert(not M.Undo(), "canceled color left an undo step")
    Setup() Select("target") M.ClearHistory()
    panel = OpenPicker(controls.spell_name) Hex(panel, "0040FF") panel.done:Click("LeftButton") Settle()
    local edited = Snapshot() assert(M.Undo()) Settle()
    local pending = assert(M.historyRedo[#M.historyRedo]) before = Snapshot()
    panel = OpenPicker(controls.spell_name)
    for _, locked in ipairs({ false, true }) do
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return locked end
        assert(M.IsConfigCombatLocked(), "event-derived combat edge was not refused") calls = {}
        Select("focus") Hex(panel, "FF9911") reset:Click("LeftButton") Settle()
        assert(not M.Undo() and not M.Redo(), "combat allowed profile history")
        SameDB(before, "combat input") assert(#calls == 0, "refused combat input applied")
        assert(M.historyRedo[#M.historyRedo] == pending, "combat replaced pending Redo")
        Display(locked and "combat-lockdown" or "combat-event-edge")
    end
    core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
    mw:Fire("PLAYER_REGEN_ENABLED") Settle() panel.cancel:Click("LeftButton") Settle()
    assert(M.Redo(), "post-combat Redo missing") Settle() SameDB(edited, "post-combat Redo") Refresh("post-combat")
    local open = disclosure.open
    disclosure.header:Click("LeftButton") Settle() assert(disclosure.open ~= open, "header native click missing")
    disclosure.header:Click("LeftButton") Settle() assert(disclosure.open == open, "header native reopen drift")
    local wrapper = entry.wrapper
    assert(mw:Select("home")) assert(mw:Select("opt_colors")) Settle()
    assert(M.cache.opt_colors.wrapper == wrapper and controls.spell_name == Widget("spell_name"), "warm page rebuilt owners")
    Refresh("warm-reopen") Add("final-profile", Snapshot())
    return rows
end
local total = 0
for _, width in ipairs({ 720, 400 }) do
    local expected = parent and Replay(width, true)
    local actual = Replay(width, false)
    if expected then
        assert(#expected == #actual, "parent/candidate observation census drift")
        for index, value in ipairs(expected) do
            assert(value == actual[index], "parent/candidate drift at observation " .. index .. ":" .. value:match("^[^\t]+"))
        end
    end
    total = total + #actual
end
print(string.format("menu_castbar_text_schema_smoke %s:5 owners/%d observations, native RGB/selection/apply/display/history/combat/400px %s",
    flavor, total, parent and "parent-candidate exact" or "candidate contract OK"))
