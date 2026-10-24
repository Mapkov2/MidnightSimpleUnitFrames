-- Font and Status native controls against an exact optional current-parent page.
-- <root> <flavor> [parent-page] [candidate-page]; no fixture overrides the apply owners.
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
    { "api.SetGlobalFontColor", "color", "colors_font" },
    { "font.use_palette", "button", "colors_font" },
    { "font.text_mode.player_name", "dropdown", "colors_font", true, { "DEFAULT", "CLASS", "CUSTOM" } },
    { "font.text_mode.npc_name", "dropdown", "colors_font", true, { "DEFAULT", "NPC", "CLASS" } },
    { "font.text_mode.hp_text", "dropdown", "colors_font", true, { "DEFAULT", "CLASS", "HEALTH" } },
    { "font.text_mode.power_text", "dropdown", "colors_font", true, { "DEFAULT", "RESOURCE" } },
    { "font.name_custom.color", "color", "colors_font" },
    { "font.open_text_colors", "button", "colors_font", false, nil, "navigation" },
    { "status_text.color.unit", "dropdown", "colors_status_text", true },
    { "status_text.color.indicator", "dropdown", "colors_status_text", true },
    { "status_text.color.value", "color", "colors_status_text" },
    { "status_text.color.reset", "button", "colors_status_text" },
    { "level_difficulty.impossible", "color", "colors_status_text", false, nil, "levelColorImpossible" },
    { "level_difficulty.very_difficult", "color", "colors_status_text", false, nil, "levelColorVeryDifficult" },
    { "level_difficulty.standard", "color", "colors_status_text", false, nil, "levelColorStandard" },
    { "level_difficulty.easy", "color", "colors_status_text", false, nil, "levelColorEasy" },
    { "level_difficulty.trivial", "color", "colors_status_text", false, nil, "levelColorTrivial" },
}
local sections = { "colors_font", "colors_status_text" }
local function Shown(widget)
    while widget do if not widget:IsShown() then return false end widget = widget:GetParent() end
    return true
end
local function Replay(width, original, saved)
    print("FontStatus " .. flavor .. ":" .. (original and "parent" or "candidate") .. ":" .. width .. (saved and ":fresh" or ""))
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
    assert(loaded == 1, "exact FontStatus page must load once")
    local M, core, env = mw.M, mw.core, mw.env
    local rows, ids, controls, bindings, calls, created, captured = {}, {}, {}, {}, {}, {}, {}
    local list = {} for _, spec in ipairs(specs) do list[#list + 1] = spec end
    if core.Client.SupportsThreatText then
        for _, row in ipairs({ { "low", "threatColorLow" }, { "mid", "threatColorMid" }, { "high", "threatColorHigh" } }) do
            list[#list + 1] = { "threat.curve." .. row[1], "color", "colors_status_text", false, nil, row[2] }
        end
    end
    local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Snapshot()
        local copy, valid, why = core.ProfileFields.CopySnapshot(env.MSUF_DB)
        assert(valid and type(copy) == "table", why or "invalid profile snapshot") return copy
    end
    local function SameDB(before, tag) assert(Equal(before, Snapshot()), "whole-profile drift: " .. tag) end
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
    -- The same actual native boundary the menu sees after login, before any target build.
    assert(core.ApplyService.RequestGeneralDomains("FONT_STATUS_FIXTURE_LOGIN", { preview = true })) Settle()
    local settled = Snapshot()
    assert(core.ApplyService.RequestGeneralDomains("FONT_STATUS_FIXTURE_LOGIN", { preview = true })) Settle()
    SameDB(settled, "second native login apply")
    assert(not M.cache.opt_colors, "fixture built FontStatus early")
    do
        -- Existing native Aura preparation is separate from cold Colors construction.
        local auraModel = assert(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel)
        local auraRecord = assert(env.MSUF_DB.auras3.customContainers.perUnit.player)
        local auraItem = assert(auraRecord.items[4])
        local auraPlaced, expectedAura = assert(auraItem.placed), Snapshot()
        local expectedRecord = expectedAura.auras3.customContainers.perUnit.player
        local previousLocalStyle = auraItem._msufA3LocalStyleFromShared_v1
        assert(expectedRecord._msufA3CustomContainersMigrated_v1 == nil
            and expectedRecord.items[4].placed.iconShape == nil
            and expectedRecord.items[4]._msufA3LocalStyleFromShared_v1 == previousLocalStyle, "fresh Aura fixture drift")
        assert(auraModel.CustomContainer("player", 4, false) == auraItem)
        expectedRecord._msufA3CustomContainersMigrated_v1 = true
        expectedRecord.items[4].placed.iconShape = "RECTANGLE"
        -- The provider guarantees this marker; native login may already have set it.
        expectedRecord.items[4]._msufA3LocalStyleFromShared_v1 = true
        SameDB(expectedAura, "unrelated native Aura preparation")
        assert(auraRecord.items[4] == auraItem and auraItem.placed == auraPlaced)
        assert(auraItem._msufA3LocalStyleFromShared_v1 == true, "native Aura local-style marker drift")
        Add("fixture:Aura-preparation", previousLocalStyle, auraItem._msufA3LocalStyleFromShared_v1)
        assert(M.cache.opt_colors == nil, "Aura preparation built the target page")
    end
    if saved then Restore(env.MSUF_DB, saved) SameDB(saved, "fresh restore into existing aliases") end
    local cold = Snapshot()
    for _, key in ipairs({ "BindColor", "BindToggle", "BindDropdown" }) do
        local bind = assert(M[key])
        M[key] = function(ctx, widget, ...)
            bindings[widget] = (bindings[widget] or 0) + 1 return bind(ctx, widget, ...)
        end
    end
    local function Capture(w)
        if not captured[w] then captured[w] = true created[#created + 1] = w end return w
    end
    for _, name in ipairs({ "Color", "Toggle", "ToggleAt", "SwitchAt", "Dropdown" }) do
        local create = assert(M.Widgets[name])
        M.Widgets[name] = function(...) return Capture(create(...)) end
    end
    local nativeButton = M.Theme.Button
    M.Theme.Button = function(...) return Capture(nativeButton(...)) end
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    assert(mw:Select("opt_colors")) Settle()
    local entry = assert(M.cache.opt_colors)
    for _, key in ipairs(sections) do
        local section = assert(entry.sections[key], "lazy FontStatus section missing: " .. key)
        local disclosure = assert(section._msuf2CollapsibleEntry)
        ids[section], ids[disclosure.header] = key, key .. ".header"
        Add("birth:" .. key, disclosure.open, section._msuf2Width, section:GetHeight())
        if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
        assert(disclosure.open and Shown(section), "native FontStatus header did not open")
        if not original then
            local schema = assert(disclosure.header._msuf2ControlSchema, "FontStatus header declaration missing")
            assert(schema.owner == disclosure.header and schema.scope == "colors" and schema.applyDomain == "sectionNavigation")
        end
    end
    SameDB(cold, "first cold FontStatus construction")
    if saved then Add("fresh:first-selection", cold, Snapshot()) end
    local seen, legacy, added, colors = {}, 0, 0, 0
    for _, spec in ipairs(list) do
        local id = M.ControlMeta("opt_colors", "advanced", spec[1]).controlId
        local record = assert(M.RuntimeControlCatalog.Get(id), "FontStatus native owner missing: " .. spec[1])
        local w = assert(record.widget) controls[spec[1]], ids[w], seen[w] = w, id, true
        assert(record.kind == spec[2] and w:GetParent() == entry.sections[spec[3]], "FontStatus identity/placement drift")
        if spec[2] == "button" then assert(bindings[w] == nil, "native FontStatus button rebound")
        else assert(bindings[w] == 1, "FontStatus input rebound") end
        if spec[2] == "color" then colors = colors + 1 end
        if spec[4] then legacy = legacy + 1 assert(w._msuf2ControlSchema, "existing AP owner lost")
        else
            added = added + 1
            if not original then
                local schema = assert(w._msuf2ControlSchema, "FontStatus native declaration missing: " .. spec[1])
                assert(schema.id == id and schema.kind == spec[2] and schema.scope == "colors"
                    and schema.applyDomain == "fontColors" and record.widget == w, "FontStatus declaration identity contract drift")
                if spec[2] == "button" or spec[1] == "api.SetGlobalFontColor" then
                    assert(schema.owner == w, "FontStatus native Owned contract drift")
                else
                    assert(schema.owner == nil and type(schema.get) == "function" and type(schema.set) == "function",
                        "FontStatus typed Bind accessor contract drift")
                end
            end
        end
    end
    assert(#list == (core.Client.SupportsThreatText and 20 or 17) and legacy == 6
        and added == #list - 6 and colors == #list - 9, "FontStatus control census drift")
    local function Target(w)
        local p = w:GetParent() return p == entry.sections.colors_font or p == entry.sections.colors_status_text
    end
    local counted = 0
    local interactive = { color = true, dropdown = true, toggle = true, slider = true, segment = true, button = true, textinput = true }
    for _, item in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local record = M.RuntimeControlCatalog.Get(item.controlId) local w = record and record.widget
        if w and w.GetParent and Target(w) and interactive[record.kind] then
            assert(seen[w], "unexpected FontStatus runtime input/action: " .. item.controlId) counted = counted + 1
        end
    end
    assert(counted == #list, "FontStatus runtime census is incomplete")
    local nativeCount = 0
    for _, w in ipairs(created) do
        if Target(w) then
            assert(seen[w] or seen[w._msuf2ControlPartOf], "extra/unbound FontStatus native constructor")
            if seen[w] then nativeCount = nativeCount + 1 end
        end
    end
    assert(nativeCount == #list, "FontStatus constructor census is incomplete")
    local function Command(w) return assert(w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command) end
    for _, spec in ipairs(list) do
        if spec[4] then
            local w = controls[spec[1]]
            local id = M.ControlMeta("opt_colors", "advanced", spec[1]).controlId
            local command = Command(w)
            local record = assert(M.RuntimeControlCatalog.Get(id), "existing session runtime record missing")
            assert(command.controlId == id and record.controlId == id and record.widget == w
                and record.command == command and w._msuf2RuntimeControlRecord == record, "existing session owner drift")
            assert(command.classification == "ephemeral" and record.classification == "ephemeral", "existing session classification drift")
        end
    end
    assert(Command(controls["status_text.color.value"]).settingKey == nil, "selected status color gained a fixed setting key")
    local function CheckDisplayed(tag, pending, deferredColor)
        assert(controls["font.name_custom.color"]:IsEnabled() == (env.MSUF_DB.general.nameColorMode == "CUSTOM"), "custom name gate drift")
        local display = {}
        for _, spec in ipairs(list) do
            local w, model, painted = controls[spec[1]]
            if spec[2] ~= "button" then model = Pack(Command(w).get()) end
            if spec[2] == "color" then
                painted = Pack(w:GetRGB())
                assert(pending or spec[1] == deferredColor or Equal(Pack(model[1], model[2], model[3]), painted),
                    "FontStatus model/display drift: " .. spec[1] .. ":" .. tag)
            elseif spec[2] == "dropdown" then painted = Pack(w:GetValue()) end
            display[#display + 1] = { spec[1], model, painted, w:IsEnabled(), Shown(w), Pack(w:GetPoint(1)),
                Pack(w:GetSize()), w._msuf2SearchMeta, w._msuf2Title and w._msuf2Title:GetText() }
        end
        return display
    end
    local function Observe(tag, pending, deferredColor)
        Add(tag, Snapshot(), CheckDisplayed(tag, pending ~= false, deferredColor), M.GetHistoryState(), calls,
            M._colorsStatusTextUnit, M._colorsStatusTextIndicator, M.activeKey, Pack(M._ContextConfiguredGlobalFontRGB()))
    end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { "ApplyService." .. name, Pack(...) } return fn(...)
        end end
    end
    for _, name in ipairs({ "MSUF_RequestThreatIndicatorRefresh", "MSUF_UFCore_NotifyConfigChanged", "MSUF_UFPreview_RequestRefresh" }) do
        local fn = env[name]
        if type(fn) == "function" then env[name] = function(...)
            calls[#calls + 1] = { "Runtime." .. name, Pack(...) } return fn(...)
        end end
    end
    local api, apiFunctions = core._colorsAPI, {}
    for name, fn in pairs(api) do
        if type(fn) == "function" then
            apiFunctions[name] = function(...)
                if name == "SetGlobalFontColor" then assert(select("#", ...) == 4, "global font API alpha/nil arity drift") end
                if name == "ResetGlobalFontToPalette" then assert(select("#", ...) == 0, "font reset API arity drift") end
                calls[#calls + 1] = { "ColorsAPI." .. name, Pack(...) } return fn(...)
            end
            api[name] = apiFunctions[name]
        end
    end
    local function WriteCount()
        local count = 0
        for _, row in ipairs(calls) do
            if row[1]:find("ApplyService.", 1, true) == 1 or row[1]:match("^ColorsAPI%.Set")
                or row[1]:match("^ColorsAPI%.Reset") or row[1] == "ColorsAPI.PushVisualUpdates"
                or row[1]:find("Runtime.", 1, true) == 1 then count = count + 1 end
        end
        return count
    end
    local function Refresh(tag)
        local before = Snapshot() M.Refresh() Settle() SameDB(before, tag .. ":read-only refresh")
        CheckDisplayed(tag) Add(tag .. ":refresh-calls", calls)
    end
    local function Choose(w, value)
        w:Click("LeftButton") Settle()
        if M.IsConfigCombatLocked() then return end
        for _, option in ipairs(mw.world.widgets.frames) do
            if option._msuf2Owner == w and option._msuf2Value == value and Shown(option) and not option._msuf2DropdownDisabled then
                option:Click("LeftButton") Settle() return
            end
        end
        error("FontStatus native option missing: " .. tostring(value))
    end
    local function Input(spec, value)
        local w = controls[spec[1]]
        if spec[2] == "dropdown" then Choose(w, value)
        elseif spec[2] == "button" then w:Click("LeftButton")
        else w._msuf2OnColorChanged(unpack(value)) end
        Settle()
        if spec[2] == "color" then
            local model = Pack(Command(w).get())
            assert(Equal(Pack(model[1], model[2], model[3]), Pack(w:GetRGB())), "input owner's native swatch did not read back")
        end
    end
    local function Panel(w)
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.owner == w and frame.compactHex and Shown(frame) then return frame end
        end
    end
    -- Initialize only through the real picker; rebase history after its own saved store is born.
    local global = controls["api.SetGlobalFontColor"] global:Click("LeftButton") Settle()
    local panel = assert(Panel(global), "native font picker missing") MenuWorld.FireVisibilityScripts(panel)
    assert(type(env.MSUF_DB.menu2ColorPicker) == "table" and type(env.MSUF_DB.menu2ColorPicker.saved) == "table")
    panel.cancel:Click("LeftButton") Settle()
    M.StartHistorySession("menu") M.SyncExternalHistoryState() M.ClearHistory()
    local factory = Snapshot()
    local function Setup(state)
        Restore(env.MSUF_DB, factory)
        for _, name in ipairs({ "GetGlobalFontColor", "SetGlobalFontColor", "ResetGlobalFontToPalette" }) do api[name] = apiFunctions[name] end
        local g = env.MSUF_DB.general
        g.fontStatusSentinel, env.MSUF_DB.target.fontStatusSentinel = { false, 0, nested = { "preserve" } }, { false, 0 }
        M._colorsStatusTextUnit, M._colorsStatusTextIndicator = nil, nil
        if state == "custom" then
            g.nameColorMode, g.nameClassColor, g.nameNpcClassColor, g.npcNameRed = "CUSTOM", false, false, true
            g.colorHealthTextByHealth, g.colorPowerTextByType, g.useCustomFontColor = "HEALTH", true, true
            g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB = .12, .24, .36
            g.nameColorR, g.nameColorG, g.nameColorB = .17, .28, .39
            for _, spec in ipairs(list) do
                if spec[6] and spec[6] ~= "navigation" then
                    g[spec[6] .. "R"], g[spec[6] .. "G"], g[spec[6] .. "B"] = .17, .28, .39
                end
            end
            env.MSUF_DB.player.levelIndicatorColorR, env.MSUF_DB.player.levelIndicatorColorG, env.MSUF_DB.player.levelIndicatorColorB = .21, .32, .43
        elseif state == "sparse" or state == "api-absent" then
            for _, key in ipairs({ "nameColorMode", "nameClassColor", "nameNpcClassColor", "npcNameRed", "colorHealthTextByHealth",
                "colorPowerTextByType", "nameColorR", "nameColorG", "nameColorB", "useCustomFontColor",
                "fontColorCustomR", "fontColorCustomG", "fontColorCustomB" }) do g[key] = nil end
            if state == "api-absent" then
                for _, name in ipairs({ "GetGlobalFontColor", "SetGlobalFontColor", "ResetGlobalFontToPalette" }) do api[name] = nil end
            end
        elseif state == "edge" then
            g.nameColorMode, g.nameClassColor, g.nameNpcClassColor, g.npcNameRed = "invalid", 0, false, 0
            g.colorHealthTextByHealth, g.colorPowerTextByType = 0, false
            g.nameColorR, g.nameColorG, g.nameColorB = false, 0, nil
            g.levelColorImpossibleR, g.levelColorImpossibleG, g.levelColorImpossibleB = 0, false, nil
        end
        Refresh(state) M.ClearHistory() M.SyncExternalHistoryState() calls = {}
    end
    local function Prepare(spec)
        if spec[1] == "font.name_custom.color" then Choose(controls["font.text_mode.player_name"], "CUSTOM") end
        M.ClearHistory() M.SyncExternalHistoryState() calls = {}
    end
    local function Value(spec)
        if spec[2] == "color" then return { .23, .47, .71 } end
        if spec[1] == "status_text.color.unit" then return "target" end
        if spec[1] == "status_text.color.indicator" then return "raceIndicator" end
        return spec[5] and spec[5][#spec[5]]
    end
    local function History(before, after, tag, mustUndo)
        local history, current = M.GetHistoryState(), Snapshot()
        calls = {} local undo = M.Undo() Settle()
        if mustUndo and not Equal(before, after) then assert(undo, "changed native color lacks Undo: " .. tag) end
        Add(tag .. ":undo", undo, Snapshot(), calls, M.GetHistoryState())
        if undo then
            SameDB(before, tag .. ":undo") calls = {} local redo = M.Redo() Settle()
            assert(redo, "FontStatus lost Redo: " .. tag) SameDB(after, tag .. ":redo")
            Add(tag .. ":redo", redo, Snapshot(), calls, M.GetHistoryState())
        else SameDB(current, tag .. ":no-undo") assert(history.undoCount == 0) end
    end
    if saved then
        for _, index in ipairs({ 1, 7, 11, 13 }) do
            local spec = list[index] Prepare(spec) local before = Snapshot()
            Input(spec, Value(spec)) local after = Snapshot() Observe("fresh:input:" .. spec[1])
            History(before, after, "fresh:" .. spec[1], true) Refresh("fresh:" .. spec[1])
        end
        return rows
    end
    for _, state in ipairs(width == 400 and { "edge" } or { "factory", "custom", "sparse", "edge", "api-absent" }) do
        for _, spec in ipairs(list) do
            if spec[6] ~= "navigation" then
                Setup(state) Prepare(spec) local before = Snapshot()
                Input(spec, Value(spec)) local after = Snapshot()
                assert(Equal(before.target.fontStatusSentinel, after.target.fontStatusSentinel)
                    and Equal(before.general.fontStatusSentinel, after.general.fontStatusSentinel), "FontStatus changed unrelated values")
                -- Global font changes the inherited Status model before its companion menu refresher runs.
                local deferredColor = spec[1] == "api.SetGlobalFontColor" and "status_text.color.value" or nil
                Observe(state .. ":input:" .. spec[1], spec[2] == "button", deferredColor)
                History(before, after, state .. ":" .. spec[1], spec[2] == "color") Refresh(state .. ":" .. spec[1])
                if spec[2] == "color" and controls[spec[1]]:IsEnabled() then
                    M.ClearHistory() M.SyncExternalHistoryState() calls = {} before = Snapshot()
                    local current = Pack(Command(controls[spec[1]]).get())
                    Input(spec, { current[1], current[2], current[3] }) SameDB(before, "FontStatus effective color no-op")
                    assert(WriteCount() == 0 and M.GetHistoryState().undoCount == 0, "FontStatus color no-op applied")
                end
            end
        end
    end
    for index = 3, 6 do
        Setup("custom") local spec = list[index]
        for _, value in ipairs(spec[5]) do
            M.ClearHistory() M.SyncExternalHistoryState() calls = {} local before = Snapshot()
            Input(spec, value) Observe("mode:" .. spec[1] .. ":" .. value) History(before, Snapshot(), spec[1] .. ":" .. value)
        end
    end
    -- Exercise a genuinely different selected frame/indicator and revisit the original.
    Setup("custom") Choose(controls["status_text.color.unit"], "target") Choose(controls["status_text.color.indicator"], "raceIndicator")
    M.ClearHistory() M.SyncExternalHistoryState() calls = {} local before = Snapshot()
    Input(list[11], { .31, .52, .73 })
    assert(env.MSUF_DB.target.raceIndicatorColorR == .31 and env.MSUF_DB.player.raceIndicatorColorR == before.player.raceIndicatorColorR,
        "status selected target/indicator setter drift")
    local edited = Snapshot() Observe("selected:B-input") History(before, edited, "selected:B", true)
    Choose(controls["status_text.color.unit"], "player") Choose(controls["status_text.color.indicator"], "levelIndicator") Observe("selected:A")
    Choose(controls["status_text.color.unit"], "target") Choose(controls["status_text.color.indicator"], "raceIndicator") Observe("selected:B-revisit")
    assert(controls["status_text.color.value"]:GetRGB() == .31, "status selection did not restore B display")
    -- Native Cancel/OK use the real picker and its real profile store, without callback substitution.
    Setup("custom") before = Snapshot() global:Click("LeftButton") Settle() panel = assert(Panel(global)) MenuWorld.FireVisibilityScripts(panel)
    panel.compactHex:SetText("0040FF") MenuWorld.FireScript(panel.compactHex, "OnTextChanged", true)
    MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle() panel.cancel:Click("LeftButton") Settle()
    SameDB(before, "native font Cancel") Observe("native:cancel")
    global:Click("LeftButton") Settle() panel = assert(Panel(global)) MenuWorld.FireVisibilityScripts(panel)
    panel.compactHex:SetText("CC6622") MenuWorld.FireScript(panel.compactHex, "OnTextChanged", true)
    MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle() panel.done:Click("LeftButton") Settle()
    local red, green, blue = Command(global).get()
    assert(Equal(Pack(red, green, blue), Pack(.8, .4, 34 / 255)), "native font OK did not reach real getter")
    edited = Snapshot() Observe("native:OK") History(before, edited, "native:OK", true)
    for _, spec in ipairs(list) do
        if spec[2] == "color" then
            Setup("custom") Prepare(spec) before = Snapshot() calls = {}
            controls[spec[1]]:Click("RightButton") Settle() Observe("native:right-reset:" .. spec[1], true)
            History(before, Snapshot(), "native:right-reset:" .. spec[1]) Refresh("native:right-reset:" .. spec[1])
        end
    end
    for _, lockdown in ipairs({ false, true }) do
        Setup("custom") before = Snapshot() local h = Encode(M.GetHistoryState(), ids)
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
        for _, spec in ipairs(list) do
            if spec[2] ~= "button" then Input(spec, Value(spec)) end
        end
        SameDB(before, "FontStatus event-derived input refusal")
        assert(Encode(M.GetHistoryState(), ids) == h and WriteCount() == 0, "FontStatus combat input applied or consumed history")
        Observe("combat:input:" .. tostring(lockdown))
        -- Native reset behavior remains parent-owned, observed without inventing a refusal contract.
        for _, spec in ipairs({ list[2], list[12] }) do
            calls = {} local raw = Snapshot() controls[spec[1]]:Click("LeftButton") Settle()
            Add("combat:action:" .. spec[1] .. ":" .. tostring(lockdown), raw, Snapshot(), M.GetHistoryState(), calls)
        end
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") Settle() Refresh("combat:leave")
    end
    Setup("factory") before = Snapshot() calls = {}
    controls["font.name_custom.color"]:Click("LeftButton") Settle()
    assert(not Panel(controls["font.name_custom.color"]), "disabled custom name swatch opened")
    SameDB(before, "disabled native custom name") assert(WriteCount() == 0 and M.GetHistoryState().undoCount == 0)
    Observe("disabled:name-custom")
    for _, key in ipairs(sections) do
        local disclosure = entry.sections[key]._msuf2CollapsibleEntry
        disclosure.header:Click("LeftButton") Settle() disclosure.header:Click("LeftButton") Settle()
    end
    Refresh("warm:reopen") SameDB(before, "FontStatus warm reopen")
    for _, spec in ipairs(list) do assert(M.RuntimeControlCatalog.Get(ids[controls[spec[1]]]).widget == controls[spec[1]], "warm native owner replaced") end
    Observe("warm:reopen")
    Setup("custom") before = Snapshot() calls = {} controls["font.open_text_colors"]:Click("LeftButton") Settle()
    assert(M.activeKey == "opt_fonts" and M.cache.opt_fonts.sections.fonts_name_power_colors, "native Fonts navigation lost target")
    Add("native:Fonts-navigation", Snapshot(), M.activeKey, env.MSUF_EM2_MenuFocusRequest, calls, M.GetHistoryState())
    assert(mw:Select("opt_colors")) Settle() Observe("native:Fonts-return")
    Setup("custom") return rows, Snapshot()
end
local count = 0
for _, width in ipairs({ 720, 400 }) do
    local expected, parentSaved
    if parent and parent ~= "-" then expected, parentSaved = Replay(width, true) end
    local actual, saved = Replay(width, false)
    local function Compare(a, b, tag)
        assert(#a == #b, "FontStatus observation count drift: " .. tag)
        for index, row in ipairs(a) do assert(row == b[index], "FontStatus parent parity drift:" .. tag .. ":" .. index .. ":" .. row:match("^[^\t]+")) end
    end
    if expected then Compare(expected, actual, "ordinary") end
    count = count + #actual
    if width == 720 then
        local expectedFresh = parentSaved and Replay(width, true, parentSaved)
        local fresh = Replay(width, false, saved)
        if expectedFresh then Compare(expectedFresh, fresh, "fresh") end
        count = count + #fresh
    end
end
print("menu_font_status_colors_schema_parity_smoke " .. flavor .. ":17/20 native owners/" .. count
    .. " observations PASS (" .. (parent and parent ~= "-" and "parent-candidate exact" or "candidate behavior") .. ")")
