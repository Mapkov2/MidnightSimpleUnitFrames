-- Castbar Palette and Aura Timer native owners; existing Dispel controls remain in parity.
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
    { "api.SetInterruptibleCastColor", "color", "cast" },
    { "api.SetNonInterruptibleCastColor", "color", "cast" },
    { "api.SetInterruptFeedbackCastColor", "color", "cast" },
    { "api.SetCastbarTextColor", "color", "cast" },
    { "api.SetCastbarTargetNameColor", "color", "cast" },
    { "general.castbarBorder", "color", "cast" },
    { "general.castbarBg", "color", "cast" },
    { "castbar.player_override.custom_color", "color", "cast" },
    { "castbar.player_override.mode", "dropdown", "cast", true },
    { "castbar.player_override.enabled", "toggle", "cast", true },
    { "table.kickReadyColor", "color", "cast" },
    { "table.kickNotReadyColor", "color", "cast" },
    { "api.SetInterruptUnavailableCastColor", "color", "cast" },
    { "castbar.reset", "button", "cast" },
    { "auras.cooldown.color_by_time", "toggle", "auras", true },
    { "auras.color.aurasCooldownTextSafeColor", "color", "auras" },
    { "auras.color.aurasCooldownTextWarningColor", "color", "auras" },
    { "auras.color.aurasCooldownTextUrgentColor", "color", "auras" },
    { "auras.cooldown.safe_seconds", "slider", "auras", true },
    { "auras.cooldown.warning_seconds", "slider", "auras", true },
    { "auras.cooldown.urgent_seconds", "slider", "auras", true },
    { "auras.reset", "button", "auras" },
}
local dispels = { { "Magic", "magic" }, { "Curse", "curse" }, { "Disease", "disease" }, { "Poison", "poison" }, { "Bleed", "bleed" } }
for _, row in ipairs(dispels) do
    specs[#specs + 1] = { "auras.dispel." .. row[2] .. ".enabled", "toggle", "auras", "dispel", row[1] }
    specs[#specs + 1] = { "auras.dispel." .. row[2] .. ".color", "color", "auras", "dispel", row[1] }
end
local sectionKeys = { cast = "colors_castbar", auras = "colors_auras" }
local resetNames = { "ResetCastbarTextColorToGlobal", "ResetCastbarTargetNameColor", "ResetCastbarBorderColor", "ResetCastbarBackgroundColor" }
local function Shown(w)
    while w do if not w:IsShown() then return false end w = w:GetParent() end return true
end
local function Replay(width, original, saved)
    print("CastAura " .. flavor .. ":" .. (original and "parent" or "candidate") .. ":" .. width .. (saved and ":fresh" or ""))
    local override, loaded = original and parent or candidate, 0
    local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
        clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = InstallNativeInputs,
        beforeOptions = function(world)
            InstallColorSelect(world) local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if path:gsub("\\", "/") == root .. "/" .. target then loaded = loaded + 1 if override and override ~= "-" then path = override end end
                return load(self, path, addon, namespace)
            end
        end })
    assert(loaded == 1, "exact CastAura source override must load once")
    local M, core, env = mw.M, mw.core, mw.env
    local rows, ids, controls, bindings, created, captured, texts, calls = {}, {}, {}, {}, {}, {}, {}, {}
    local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Snapshot()
        local copy, valid, why = core.ProfileFields.CopySnapshot(env.MSUF_DB)
        assert(valid and type(copy) == "table", why or "invalid CastAura profile snapshot") return copy
    end
    local function SameDB(before, tag) assert(Equal(before, Snapshot()), "CastAura whole-profile drift: " .. tag) end
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
                assert(not (driver and driver:GetScript("OnUpdate")), "CastAura finite selection did not settle")
            end
        end
        mw:RunTimers()
    end
    assert(core.ApplyService.RequestGeneralDomains("CAST_AURA_FIXTURE_LOGIN", { preview = true })) Settle()
    local settled = Snapshot()
    assert(core.ApplyService.RequestGeneralDomains("CAST_AURA_FIXTURE_LOGIN", { preview = true })) Settle()
    SameDB(settled, "second actual native login apply")
    assert(not M.cache.opt_colors, "native fixture built Colors early")
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
    if saved then Restore(env.MSUF_DB, saved) SameDB(saved, "fresh restored aliases") end
    local cold = Snapshot()
    for _, name in ipairs({ "BindColor", "BindToggle", "BindDropdown", "BindSlider" }) do
        local bind = assert(M[name])
        M[name] = function(ctx, w, ...) bindings[w] = (bindings[w] or 0) + 1 return bind(ctx, w, ...) end
    end
    local function Capture(w)
        if not captured[w] then captured[w] = true created[#created + 1] = w end return w
    end
    for _, name in ipairs({ "Color", "Toggle", "ToggleAt", "SwitchAt", "Dropdown", "Slider" }) do
        local create = assert(M.Widgets[name]) M.Widgets[name] = function(...) return Capture(create(...)) end
    end
    local nativeButton, nativeFont = M.Theme.Button, M.Theme.Font
    M.Theme.Button = function(...) return Capture(nativeButton(...)) end
    M.Theme.Font = function(...) local fs = nativeFont(...) texts[#texts + 1] = fs return fs end
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    assert(mw:Select("opt_colors")) Settle()
    local entry = assert(M.cache.opt_colors)
    local selectorID = M.ControlMeta("opt_colors", "advanced", "preview.scope.selector").controlId
    local selector = assert(M.RuntimeControlCatalog.Get(selectorID)).widget
    local function Category(key)
        if M.colorsPainterCategory == key then return end
        for _, button in ipairs(selector.buttons) do
            if button._msuf2Value == key then button:Click("LeftButton") Settle() assert(M.colorsPainterCategory == key) return end
        end
        error("native Colors category missing: " .. key)
    end
    for _, key in ipairs({ "cast", "auras" }) do
        Category(key) local section = assert(entry.sections[sectionKeys[key]]) local disclosure = assert(section._msuf2CollapsibleEntry)
        ids[section], ids[disclosure.header] = sectionKeys[key], sectionKeys[key] .. ".header"
        Add("birth:" .. key, disclosure.open, section._msuf2Width, section:GetHeight())
        if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
        assert(disclosure.open and Shown(section), "CastAura native disclosure did not open")
        if not original then
            local schema = assert(disclosure.header._msuf2ControlSchema, "CastAura header declaration missing")
            assert(schema.owner == disclosure.header and schema.scope == "colors" and schema.applyDomain == "sectionNavigation")
        end
    end
    SameDB(cold, "cold CastAura construction")
    if saved then Add("fresh:first-selection", cold, Snapshot()) end
    local function Section(w)
        while w do
            for key, id in pairs(sectionKeys) do if w == entry.sections[id] then return key end end
            w = w:GetParent()
        end
    end
    local seen, generic, legacyDispel, added = {}, 0, 0, 0
    for _, spec in ipairs(specs) do
        local id = M.ControlMeta("opt_colors", "advanced", spec[1]).controlId
        local record = assert(M.RuntimeControlCatalog.Get(id), "CastAura native owner missing: " .. spec[1])
        local w = assert(record.widget) controls[spec[1]], ids[w], seen[w] = w, id, true
        assert(record.kind == spec[2] and Section(w) == spec[3], "CastAura native identity/placement drift")
        if spec[2] == "button" then assert(bindings[w] == nil, "CastAura native action gained a binder")
        else assert(bindings[w] == 1, "CastAura native input rebound") end
        if spec[4] then
            assert(w._msuf2ControlSchema, "existing CastAura declaration lost")
            if spec[4] == "dispel" then legacyDispel = legacyDispel + 1 else generic = generic + 1 end
        else
            added = added + 1
            if not original then
                local schema = assert(w._msuf2ControlSchema, "CastAura native declaration missing: " .. spec[1])
                assert(schema.id == id and schema.kind == spec[2] and schema.owner == w and schema.scope == "colors"
                    and schema.applyDomain == (spec[3] == "cast" and "castbar" or "auras"), "CastAura native Owned contract drift")
                if spec[2] == "button" then assert(type(schema.action) == "function")
                else assert(type(schema.get) == "function" and type(schema.set) == "function") end
            end
        end
    end
    assert(#specs == 32 and generic == 6 and legacyDispel == 10 and added == 16, "CastAura owner census drift")
    local interactive = { color = true, toggle = true, dropdown = true, slider = true, segment = true, button = true, textinput = true }
    local counted = 0
    for _, row in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local record = M.RuntimeControlCatalog.Get(row.controlId) local w = record and record.widget
        if w and w.GetParent and Section(w) and interactive[record.kind] then
            assert(seen[w], "extra CastAura registered input/action: " .. row.controlId) counted = counted + 1
        end
    end
    assert(counted == 32, "CastAura registered input census incomplete")
    local function Constructors()
        local native, owners = {}, {}
        for _, w in ipairs(created) do
            if Section(w) then
                local owner = seen[w._msuf2ControlPartOf] and w._msuf2ControlPartOf or w
                while owner and not seen[owner] do owner = owner:GetParent() end
                assert(owner, "extra/orphan CastAura native constructor")
                owners[owner] = true
                native[#native + 1] = { ids[owner], w:GetObjectType(), w._msuf2ControlKind, Pack(w:GetPoint(1)), Pack(w:GetSize()) }
            end
        end
        local count = 0 for _ in pairs(owners) do count = count + 1 end
        assert(count == 32, "CastAura native constructor owner census incomplete") return native
    end
    Add("native-constructors", Constructors())
    local samples = {}
    for _, fs in ipairs(texts) do
        local box = fs:GetParent() local point, relative, anchor, x, y = fs:GetPoint(1)
        if Section(fs) == "auras" and (fs:GetText() == "60" or fs:GetText() == "15" or fs:GetText() == "5")
            and box:GetHeight() == 54 and point == "CENTER" and relative == box and anchor == "CENTER" and x == 0 and y == 6 then
            samples[#samples + 1] = fs
        end
    end
    assert(#samples == 3, "actual Aura timer preview sample census drift")
    local function Command(w) return assert(w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command) end
    local function SampleColors(strict)
        local out = {} for _, fs in ipairs(samples) do out[#out + 1] = { fs:GetText(), Pack(fs:GetTextColor()), Pack(fs:GetPoint(1)) } end
        if strict and Shown(samples[1]) then
            local g = env.MSUF_DB.general local sr, sg, sb = M._ContextGetAuraSafeRGB()
            local expected = { Pack(sr, sg, sb, 1), Pack(sr, sg, sb, 1), Pack(sr, sg, sb, 1) }
            if g.aurasCooldownTextUseBuckets == true then
                local wr, wg, wb = M.ColorsPage.TableRGB(g, "aurasCooldownTextWarningColor", 1, .85, .20)
                local ur, ug, ub = M.ColorsPage.TableRGB(g, "aurasCooldownTextUrgentColor", 1, .55, .10)
                expected[2], expected[3] = Pack(wr, wg, wb, 1), Pack(ur, ug, ub, 1)
            end
            for i, fs in ipairs(samples) do assert(Equal(Pack(fs:GetTextColor()), expected[i]), "actual Aura preview sample color drift") end
        end
        return out
    end
    local function Display(strict)
        local out = {}
        local enabled = Command(controls["castbar.player_override.enabled"]).get() and true or false
        local mode = Command(controls["castbar.player_override.mode"]).get()
        assert(controls["castbar.player_override.mode"]:IsEnabled() == enabled, "castbar mode gate drift")
        assert(controls["castbar.player_override.custom_color"]:IsEnabled() == (enabled and mode == "CUSTOM"), "castbar custom gate drift")
        for _, spec in ipairs(specs) do
            local w, model, painted = controls[spec[1]]
            if spec[2] ~= "button" then model = Pack(Command(w).get()) end
            if spec[2] == "color" then
                painted = Pack(w:GetRGB())
                assert(not strict or not Shown(w) or Equal(Pack(model[1], model[2], model[3]), painted), "CastAura visible model/display drift")
            elseif spec[2] == "toggle" then painted = Pack(w:GetChecked())
            elseif spec[2] ~= "button" then painted = Pack(w:GetValue()) end
            out[#out + 1] = { spec[1], model, painted, w:IsEnabled(), Shown(w), Pack(w:GetPoint(1)), Pack(w:GetSize()), w._msuf2SearchMeta,
                w._msuf2ColorHasOpacity, w._msuf2GetColorOpacity and w._msuf2GetColorOpacity() }
        end
        return out
    end
    local function Observe(tag, strict) Add(tag, Snapshot(), Display(strict), SampleColors(strict), M.GetHistoryState(), calls, M.colorsPainterCategory) end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { "ApplyService." .. name, Pack(...) } return fn(...)
        end end
    end
    for _, name in ipairs({ "MSUF_GF_ForceAuraTextColorRefresh", "MSUF_UFCore_NotifyConfigChanged", "MSUF_UFPreview_RequestRefresh" }) do
        local fn = env[name]
        if type(fn) == "function" then env[name] = function(...)
            calls[#calls + 1] = { "Runtime." .. name, Pack(...) } return fn(...)
        end end
    end
    local a3 = core.MSUF_Auras3
    if a3 and type(a3.SetDispelColorPreviewType) == "function" then
        local set = a3.SetDispelColorPreviewType
        a3.SetDispelColorPreviewType = function(...)
            calls[#calls + 1] = { "A3.SetDispelColorPreviewType", Pack(...) } return set(...)
        end
    end
    local api, apiFunctions = core._colorsAPI, {}
    for name, fn in pairs(api) do
        if type(fn) == "function" then
            apiFunctions[name] = function(...)
                if name:match("^ResetCastbar") then assert(select("#", ...) == 0, "castbar reset API arity drift") end
                calls[#calls + 1] = { "ColorsAPI." .. name, Pack(...) } return fn(...)
            end
            api[name] = apiFunctions[name]
        end
    end
    local function Writes()
        local count = 0 for _, row in ipairs(calls) do
            if row[1]:find("ApplyService.", 1, true) == 1 or row[1]:find("Runtime.", 1, true) == 1
                or row[1]:match("^ColorsAPI%.Set") or row[1]:match("^ColorsAPI%.Reset") or row[1] == "ColorsAPI.PushVisualUpdates" then count = count + 1 end
        end return count
    end
    local function Refresh(tag)
        local before = Snapshot() M.Refresh() Settle() SameDB(before, tag .. ":read-only refresh") Observe(tag .. ":refresh", true)
    end
    local function Choose(w, value)
        w:Click("LeftButton") Settle() if M.IsConfigCombatLocked() then return end
        for _, option in ipairs(mw.world.widgets.frames) do
            if option._msuf2Owner == w and option._msuf2Value == value and Shown(option) and not option._msuf2DropdownDisabled then
                option:Click("LeftButton") Settle() return
            end
        end error("castbar native dropdown value missing")
    end
    local function Input(spec, value)
        Category(spec[3]) local w = controls[spec[1]]
        if spec[2] == "dropdown" then Choose(w, value)
        elseif spec[2] == "toggle" then
            local current, wanted = Command(w).get() and true or false, value and true or false
            local blocked = M.IsConfigCombatLocked()
            -- BindToggle flips its model; a checked-cache preload cannot request a value.
            if blocked or current ~= wanted then w:Click("LeftButton") Settle() end
            local expected = wanted
            if blocked then expected = current end
            assert((Command(w).get() and true or false) == expected and (w:GetChecked() and true or false) == expected,
                "native CastAura toggle model/cache drift: " .. spec[1])
        elseif spec[2] == "slider" then w:SetValue(value) MenuWorld.FireScript(w, "OnValueChanged", value)
        elseif spec[2] == "button" then w:Click("LeftButton")
        else w._msuf2OnColorChanged(unpack(value)) end Settle()
        if spec[1] == "castbar.reset" and not M.IsConfigCombatLocked() then
            local g = env.MSUF_DB.general
            assert(g.playerCastbarOverrideEnabled == false and g.playerCastbarOverrideMode == "CLASS"
                and g.kickReadyColor == nil and g.kickNotReadyColor == nil and g.castbarInterruptUnavailableColor == nil,
                "castbar reset did not retain native reset fields")
        end
        if spec[2] == "color" then
            local model = Pack(Command(w).get()) assert(Equal(Pack(model[1], model[2], model[3]), Pack(w:GetRGB())), "CastAura input color readback drift")
        end
    end
    local function Panel(w)
        for _, frame in ipairs(mw.world.widgets.frames) do if frame.owner == w and frame.compactHex and Shown(frame) then return frame end end
    end
    Category("cast") local background = controls["general.castbarBg"] background:Click("LeftButton") Settle()
    local panel = assert(Panel(background), "actual castbar picker missing") MenuWorld.FireVisibilityScripts(panel)
    assert(type(env.MSUF_DB.menu2ColorPicker) == "table") panel.cancel:Click("LeftButton") Settle()
    M.StartHistorySession("menu") M.SyncExternalHistoryState() M.ClearHistory() local factory = Snapshot()
    local function Setup(state)
        Restore(env.MSUF_DB, factory) for name, fn in pairs(apiFunctions) do api[name] = fn end
        local g = env.MSUF_DB.general
        g.castAuraSentinel, env.MSUF_DB.target.castAuraSentinel = { false, 0, nested = { "keep" } }, { false, 0 }
        if state == "custom" then
            g.playerCastbarOverrideEnabled, g.playerCastbarOverrideMode = true, "CUSTOM"
            g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = .17, .28, .39
            g.kickReadyColor, g.kickNotReadyColor = { .17, .28, .39 }, { .31, .42, .53 }
            g.aurasCooldownTextUseBuckets = true
            g.aurasCooldownTextSafeColor, g.aurasCooldownTextWarningColor, g.aurasCooldownTextUrgentColor = { .12, .23, .34 }, { .45, .56, .67 }, { .78, .89, .91 }
            g.aurasCooldownTextSafeSeconds, g.aurasCooldownTextWarningSeconds, g.aurasCooldownTextUrgentSeconds = 81, 23, 7
            g.dispelTypeColorOverrides = {} for _, row in ipairs(dispels) do g.dispelTypeColorOverrides[row[1]] = { .21, .32, .43 } end
        elseif state == "sparse" or state == "api-absent" then
            for _, key in ipairs({ "playerCastbarOverrideEnabled", "playerCastbarOverrideMode", "playerCastbarOverrideR", "playerCastbarOverrideG",
                "playerCastbarOverrideB", "kickReadyColor", "kickNotReadyColor", "aurasCooldownTextUseBuckets", "aurasCooldownTextSafeColor",
                "aurasCooldownTextWarningColor", "aurasCooldownTextUrgentColor", "aurasCooldownTextSafeSeconds", "aurasCooldownTextWarningSeconds",
                "aurasCooldownTextUrgentSeconds", "dispelTypeColorOverrides" }) do g[key] = nil end
            if state == "api-absent" then
                for name in pairs(apiFunctions) do if name:find("Cast", 1, true) then api[name] = nil end end
            end
        elseif state == "edge" then
            g.playerCastbarOverrideEnabled, g.playerCastbarOverrideMode, g.aurasCooldownTextUseBuckets = 0, "invalid", false
            g.aurasCooldownTextSafeSeconds, g.aurasCooldownTextWarningSeconds, g.aurasCooldownTextUrgentSeconds = false, 0, 1000
            g.kickReadyColor, g.kickNotReadyColor = { 0, false, nil }, { false, 0, 1 }
            g.aurasCooldownTextSafeColor, g.aurasCooldownTextWarningColor, g.aurasCooldownTextUrgentColor = nil, { 0, false, nil }, { 0, .25, 1 }
        end
        Refresh(state) M.ClearHistory() M.SyncExternalHistoryState() calls = {}
    end
    local function Prepare(spec)
        Category(spec[3])
        if spec[1] == "castbar.player_override.custom_color" or spec[1] == "castbar.player_override.mode" then
            if not Command(controls["castbar.player_override.enabled"]).get() then Input(specs[10], true) end
            if spec[1] == "castbar.player_override.custom_color" then Choose(controls["castbar.player_override.mode"], "CUSTOM") end
        end
        if spec[4] == "dispel" and spec[2] == "color" then
            local toggle = controls[spec[1]:gsub("%.color$", ".enabled")]
            if not Command(toggle).get() then Input({ spec[1]:gsub("%.color$", ".enabled"), "toggle", "auras" }, true) end
        end
        M.ClearHistory() M.SyncExternalHistoryState() calls = {}
    end
    local function Value(spec)
        if spec[2] == "color" then return { .23, .47, .71, .37 } end
        if spec[2] == "toggle" then return not Command(controls[spec[1]]).get() end
        if spec[2] == "dropdown" then return Command(controls[spec[1]]).get() == "CUSTOM" and "CLASS" or "CUSTOM" end
        if spec[2] == "slider" then return spec[1]:find("safe_seconds", 1, true) and 600 or 0 end
    end
    local function History(before, after, tag, required)
        calls = {} local undo = M.Undo() Settle() Add(tag .. ":undo", undo, Snapshot(), M.GetHistoryState(), calls)
        if required and not Equal(before, after) then assert(undo, "CastAura changed color has no Undo: " .. tag) end
        if undo then
            SameDB(before, tag .. ":undo") calls = {} assert(M.Redo(), "CastAura Redo missing") Settle() SameDB(after, tag .. ":redo")
            Add(tag .. ":redo", Snapshot(), M.GetHistoryState(), calls)
        else SameDB(after, tag .. ":no-undo") end
    end
    if saved then
        for _, index in ipairs({ 7, 8, 16, 24 }) do
            local spec = specs[index] Prepare(spec) local before = Snapshot()
            Input(spec, Value(spec)) Observe("fresh:input:" .. spec[1]) History(before, Snapshot(), "fresh:" .. spec[1], true) Refresh("fresh")
        end return rows
    end
    for _, state in ipairs(width == 400 and { "edge" } or { "factory", "custom", "sparse", "edge", "api-absent" }) do
        for _, spec in ipairs(specs) do
            Setup(state) Prepare(spec) local before = Snapshot() Input(spec, Value(spec)) local after = Snapshot()
            assert(Equal(before.general.castAuraSentinel, after.general.castAuraSentinel)
                and Equal(before.target.castAuraSentinel, after.target.castAuraSentinel), "CastAura changed unrelated profile data")
            Observe(state .. ":input:" .. spec[1]) History(before, after, spec[1], spec[2] == "color") Refresh(spec[1])
            if spec[2] ~= "button" and spec[2] ~= "toggle" and controls[spec[1]]:IsEnabled() then
                M.ClearHistory() M.SyncExternalHistoryState() calls = {} before = Snapshot()
                local current = Pack(Command(controls[spec[1]]).get())
                Input(spec, spec[2] == "color" and { current[1], current[2], current[3], type(current[4]) == "number" and current[4] or nil } or current[1])
                SameDB(before, "CastAura effective no-op") assert(Writes() == 0 and M.GetHistoryState().undoCount == 0, "CastAura no-op applied")
            end
        end
    end
    -- Each true reset owner must suppress only the fallback, without short-circuiting the other resets.
    for _, retained in ipairs({ 1, 4 }) do
        Setup("custom") Category("cast")
        for i, name in ipairs(resetNames) do if i ~= retained then api[name] = nil end end
        local before = Snapshot() Input(specs[14]) Observe("partial-reset:" .. retained)
        local resetCount = 0 for _, row in ipairs(calls) do if row[1]:match("^ColorsAPI%.ResetCastbar") then resetCount = resetCount + 1 end end
        assert(resetCount == 1, "partial castbar reset did not reach actual remaining owner")
        History(before, Snapshot(), "partial-reset:" .. retained) Refresh("partial-reset")
    end
    Setup("custom") Category("auras") local before = Snapshot() Input(specs[22])
    assert(env.MSUF_DB.general.dispelTypeColorOverrides == nil, "Aura reset did not clear existing Dispel overrides")
    for _, row in ipairs(dispels) do assert(not Command(controls["auras.dispel." .. row[2] .. ".enabled"]).get(), "Aura reset left a Dispel override enabled") end
    Observe("aura-reset:all-Dispel") History(before, Snapshot(), "Aura reset full Dispel history") Refresh("Aura reset")
    Setup("custom") Category("cast") before = Snapshot() background:Click("LeftButton") Settle() panel = assert(Panel(background)) MenuWorld.FireVisibilityScripts(panel)
    panel.compactHex:SetText("0040FF") MenuWorld.FireScript(panel.compactHex, "OnTextChanged", true)
    MenuWorld.FireScript(panel.compactHex, "OnEnterPressed") Settle() panel.cancel:Click("LeftButton") Settle()
    SameDB(before, "real castbar picker Cancel") Observe("native:Cancel")
    background:Click("LeftButton") Settle() panel = assert(Panel(background)) MenuWorld.FireVisibilityScripts(panel)
    assert(Shown(panel.more), "native CastAura More Options missing")
    panel.more:Click("LeftButton") Settle()
    assert(panel.advanced == true and Shown(panel.opacity) and Shown(panel.hex), "native CastAura alpha/HEX editors hidden")
    -- Genuine UI position normalization precedes the color transaction snapshot.
    M.ClearHistory() M.SyncExternalHistoryState() before = Snapshot()
    panel.hex:SetText("CC6622") MenuWorld.FireScript(panel.hex, "OnTextChanged", true)
    MenuWorld.FireScript(panel.hex, "OnEnterPressed") Settle()
    local _, _, _, alpha = Command(background).get()
    if type(alpha) == "number" then
        assert(Shown(panel.opacity), "native CastAura alpha input hidden")
        MenuWorld.FireScript(panel.opacity, "OnValueChanged", .37) Settle()
    end
    panel.done:Click("LeftButton") Settle()
    local red, green, blue = Command(background).get()
    assert(Equal(Pack(red, green, blue), Pack(.8, .4, 34 / 255)), "native castbar picker did not reach actual API getter")
    local after = Snapshot() Observe("native:OK-alpha") History(before, after, "real castbar picker", true)
    for _, spec in ipairs(specs) do
        if spec[2] == "color" then
            Setup("custom") Prepare(spec) before = Snapshot() controls[spec[1]]:Click("RightButton") Settle()
            Observe("right-reset:" .. spec[1]) History(before, Snapshot(), "right-reset:" .. spec[1]) Refresh("right-reset")
        end
    end
    for _, lockdown in ipairs({ false, true }) do
        for _, key in ipairs({ "cast", "auras" }) do
            Setup("custom") Category(key) before = Snapshot() local history = Encode(M.GetHistoryState(), ids)
            core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
            for _, spec in ipairs(specs) do if spec[3] == key and spec[2] ~= "button" then Input(spec, Value(spec)) end end
            SameDB(before, "CastAura event-derived combat refusal") assert(Encode(M.GetHistoryState(), ids) == history and Writes() == 0)
            Observe("combat:input:" .. key .. ":" .. tostring(lockdown))
            local action = key == "cast" and specs[14] or specs[22] calls = {} local raw = Snapshot()
            Input(action) Add("combat:reset:" .. key .. ":" .. tostring(lockdown), raw, Snapshot(), M.GetHistoryState(), calls)
            core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end mw:Fire("PLAYER_REGEN_ENABLED") Settle()
            Refresh("combat:leave")
        end
    end
    Setup("factory") Category("cast")
    for _, enabled in ipairs({ true, false, true }) do
        Input(specs[10], enabled) for _, mode in ipairs({ "CLASS", "CUSTOM" }) do
            if enabled then Input(specs[9], mode) end Observe("override-gates:" .. tostring(enabled) .. ":" .. mode)
        end
    end
    Input(specs[10], false) M.ClearHistory() M.SyncExternalHistoryState() calls = {} before = Snapshot()
    controls["castbar.player_override.custom_color"]:Click("LeftButton") Settle()
    assert(not Panel(controls["castbar.player_override.custom_color"]), "disabled castbar override opened a picker")
    SameDB(before, "disabled castbar override") assert(Writes() == 0 and M.GetHistoryState().undoCount == 0)
    for _, key in ipairs({ "cast", "auras" }) do
        Category(key) local header = entry.sections[sectionKeys[key]]._msuf2CollapsibleEntry.header
        header:Click("LeftButton") Settle() header:Click("LeftButton") Settle() Refresh("warm:" .. key)
    end
    for _, spec in ipairs(specs) do assert(M.RuntimeControlCatalog.Get(ids[controls[spec[1]]]).widget == controls[spec[1]], "warm CastAura owner replaced") end
    Add("warm:native-constructors", Constructors()) Observe("warm:reopen", true)
    Setup("custom") return rows, Snapshot()
end
local count = 0
local function Compare(a, b, tag)
    assert(#a == #b, "CastAura parent observation count drift: " .. tag)
    for i, row in ipairs(a) do assert(row == b[i], "CastAura parent parity drift:" .. tag .. ":" .. i .. ":" .. row:match("^[^\t]+")) end
end
for _, width in ipairs({ 720, 400 }) do
    local expected, parentSaved if parent and parent ~= "-" then expected, parentSaved = Replay(width, true) end
    local actual, saved = Replay(width, false) if expected then Compare(expected, actual, "ordinary") end count = count + #actual
    if width == 720 then
        local expectedFresh = parentSaved and Replay(width, true, parentSaved) local fresh = Replay(width, false, saved)
        if expectedFresh then Compare(expectedFresh, fresh, "fresh") end count = count + #fresh
    end
end
print("menu_castbar_aura_colors_schema_parity_smoke " .. flavor .. ":32 native owners/" .. count
    .. " observations PASS (" .. (parent and parent ~= "-" and "parent-candidate exact" or "candidate behavior") .. ")")
