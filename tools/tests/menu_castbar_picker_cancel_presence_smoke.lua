-- Real native Cast picker Cancel preserves absence, explicit values and inheritance.
-- All offered detail families use the native Editing dropdown before opening the modal picker.
-- <root> <flavor> [page-input] [context-input]; optional inputs are private causal seams.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, pageInput, contextInput = arg[2] or "Mainline", arg[3], arg[4]
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


local pagePath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
local contextPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Context.lua"
local loaded = { page = 0, context = 0 }
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
    clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = InstallNativeInputs,
    beforeOptions = function(world)
        InstallColorSelect(world)
        local load = world.LoadFile
        world.LoadFile = function(self, path, addon, namespace)
            local normalized = path:gsub("\\", "/")
            if normalized == root .. "/" .. pagePath then
                loaded.page = loaded.page + 1
                if pageInput and pageInput ~= "-" then path = pageInput end
            elseif normalized == root .. "/" .. contextPath then
                loaded.context = loaded.context + 1
                if contextInput and contextInput ~= "-" then path = contextInput end
            end
            return load(self, path, addon, namespace)
        end
    end })
assert(loaded.page == 1 and loaded.context == 1, "exact Cast picker product input must load once")
local M, core, env = mw.M, mw.core, mw.env
local ids = {}
local function Equal(a, b) return Encode(a, ids) == Encode(b, ids) end
local function Snapshot()
    local copy, valid, why = core.ProfileFields.CopySnapshot(env.MSUF_DB)
    assert(valid and type(copy) == "table", why or "invalid Cast picker profile snapshot")
    return copy
end
local function SameDB(before, label)
    assert(Equal(before, Snapshot()), "cast picker Cancel raw profile drift: " .. label)
end
local function Settle() mw:RunTimers() end
local function Shown(w)
    while w do if not w:IsShown() then return false end w = w:GetParent() end
    return true
end
assert(core.ApplyService.RequestGeneralDomains("CAST_PICKER_PRESENCE_LOGIN", { preview = true })) Settle()
local settled = Snapshot()
assert(core.ApplyService.RequestGeneralDomains("CAST_PICKER_PRESENCE_LOGIN", { preview = true })) Settle()
SameDB(settled, "second real login apply")
-- Real unrelated Aura initialization is complete before the Colors page is built.
do
    local model = assert(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel)
    local record = assert(env.MSUF_DB.auras3.customContainers.perUnit.player)
    local item = assert(record.items[4])
    local placed, expected = assert(item.placed), Snapshot()
    local expectedRecord = expected.auras3.customContainers.perUnit.player
    expectedRecord._msufA3CustomContainersMigrated_v1 = true
    expectedRecord.items[4].placed.iconShape = "RECTANGLE"
    expectedRecord.items[4]._msufA3LocalStyleFromShared_v1 = true
    assert(model.CustomContainer("player", 4, false) == item)
    SameDB(expected, "unrelated Aura initialization")
    assert(record.items[4] == item and item.placed == placed and M.cache.opt_colors == nil)
end
assert(mw:Select("opt_colors")) Settle()
local entry = assert(M.cache.opt_colors)
local selector = assert(M.RuntimeControlCatalog.Get(M.ControlMeta("opt_colors", "advanced", "preview.scope.selector").controlId)).widget
for _, button in ipairs(selector.buttons) do
    if button._msuf2Value == "cast" then button:Click("LeftButton") Settle() break end
end
assert(M.colorsPainterCategory == "cast", "native Cast category was not selected")
entry = assert(M.cache.opt_colors)
local section = assert(entry.sections.colors_castbar)
local disclosure = assert(section._msuf2CollapsibleEntry)
if not disclosure.open then disclosure.header:Click("LeftButton") Settle() end
assert(disclosure.open, "native Cast section did not open")
local detailSection = assert(entry.sections.colors_castbar_text)
local detailDisclosure = assert(detailSection._msuf2CollapsibleEntry)
if not detailDisclosure.open then detailDisclosure.header:Click("LeftButton") Settle() end
assert(detailDisclosure.open, "native Cast detail section did not open")
local function Widget(path)
    local id = M.ControlMeta("opt_colors", "advanced", path).controlId
    local record = assert(M.RuntimeControlCatalog.Get(id), "native Cast color missing: " .. path)
    assert(record.kind == "color" and record.widget, "native Cast color kind drift: " .. path)
    ids[record.widget] = id
    return record.widget
end
local function Command(w) return assert(w._msuf2CommandAction) end
local function Model(w) return Pack(Command(w).get()) end
local function Paint(w)
    return { rgb = Pack(w:GetRGB()), opacity = Pack(w._msuf2GetColorOpacity()), hasOpacity = w._msuf2ColorHasOpacity }
end
local function CheckPaint(w, label)
    local value = Model(w)
    assert(Equal(Pack(value[1], value[2], value[3]), Pack(w:GetRGB())), "native Cast RGB readback drift: " .. label)
    assert(w._msuf2ColorHasOpacity == (type(value[4]) == "number"), "native Cast opacity flag drift: " .. label)
end
local function Panel(w)
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame.owner == w and frame.compactHex and Shown(frame) then return frame end
    end
end
-- The UI may persist its own position on Open. Warm it without painting a color.
local background = Widget("general.castbarBg")
local beforeWarm = Snapshot()
background:Click("LeftButton") Settle()
local warmPanel = assert(Panel(background), "native Cast picker warm Open missing")
MenuWorld.FireVisibilityScripts(warmPanel)
warmPanel.cancel:Click("LeftButton") Settle()
assert(Equal(beforeWarm.general, Snapshot().general), "opening an unedited picker changed general settings")
local db, general = env.MSUF_DB, env.MSUF_DB.general
general.playerCastbarOverrideEnabled, general.playerCastbarOverrideMode = true, "CUSTOM"
general.castPickerPresenceSentinel = { false, 0, [0] = "keep", nested = { false, 0 } }
local sentinel = general.castPickerPresenceSentinel
M.Refresh() Settle()
M.StartHistorySession("menu") M.SyncExternalHistoryState() M.ClearHistory()
local base = Snapshot()
local owners = {
    { "api.SetInterruptibleCastColor",
        { "castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB" }, "castbarInterruptibleColor" },
    { "api.SetNonInterruptibleCastColor",
        { "castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB" }, "castbarNonInterruptibleColor" },
    { "api.SetInterruptFeedbackCastColor",
        { "castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB" }, "castbarInterruptFeedbackColor" },
    { "api.SetCastbarTextColor", { "castbarFontR", "castbarFontG", "castbarFontB" } },
    { "api.SetCastbarTargetNameColor", { "castbarTargetNameR", "castbarTargetNameG", "castbarTargetNameB" } },
    { "general.castbarBorder", { "castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA" } },
    { "general.castbarBg", { "castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA" } },
    { "castbar.player_override.custom_color", { "playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB" } },
    { "table.kickReadyColor", { "kickReadyColor" }, true },
    { "table.kickNotReadyColor", { "kickNotReadyColor" }, true },
    { "api.SetInterruptUnavailableCastColor",
        { "castbarInterruptUnavailableR", "castbarInterruptUnavailableG", "castbarInterruptUnavailableB" }, "castbarInterruptUnavailableColor" },
}
local detailOwners = {
    { "castbar.text_color.spell_name", "SpellName" },
    { "castbar.text_color.time", "Time" },
    { "castbar.text_color.target_name", "TargetName" },
}
-- Public Colors storage contract, independently observed through native picker input and getters.
local detailPrefixes = { player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus",
    boss = "bossCast", arena = "arenaCast" }
local unitId = M.ControlMeta("opt_colors", "advanced", "castbar.text_color.unit").controlId
local unitRecord = assert(M.RuntimeControlCatalog.Get(unitId), "native Cast detail selector missing")
local unitDropdown = assert(unitRecord.widget)
assert(unitRecord.kind == "dropdown" and type(unitDropdown.values) == "table", "native Cast detail selector shape drift")
local units, offered = {}, {}
for _, option in ipairs(unitDropdown.values) do
    assert(type(option) == "table" and type(option.text) == "string" and detailPrefixes[option.value]
        and not offered[option.value], "native Cast detail offered family drift")
    offered[option.value] = true units[#units + 1] = option.value
end
assert(offered.player and offered.target, "native Cast detail Player/Target families missing")
local function ChooseUnit(value)
    local before = Snapshot()
    unitDropdown:Click("LeftButton") Settle()
    local clicked = false
    for _, option in ipairs(mw.world.widgets.frames) do
        if option._msuf2Owner == unitDropdown and option._msuf2Value == value
            and Shown(option) and not option._msuf2DropdownDisabled then
            option:Click("LeftButton") Settle() clicked = true break
        end
    end
    assert(clicked and Command(unitDropdown).get() == value and unitDropdown:GetValue() == value,
        "native Cast detail selection drift: " .. value)
    SameDB(before, "ephemeral native detail selection:" .. value)
end
local function DetailRow(spec, unit)
    local prefix = assert(detailPrefixes[unit]) .. spec[2] .. "Color"
    return { spec[1], { prefix .. "R", prefix .. "G", prefix .. "B" } }
end
local function Prepare(row, state)
    Restore(db, base)
    for _, key in ipairs(row[2]) do general[key] = nil end
    if row[3] == true then
        local key = row[2][1]
        if state == "partial" then general[key] = { [1] = false, [2] = 0, [0] = "keep", extra = { false, 0 } }
        elseif state == "false0" then general[key] = false
        elseif state == "configured" then general[key] = { 0, .28, .39, 0, extra = { false, 0 } } end
    else
        if row[3] then general[row[3]] = "red" end
        if state == "partial" then general[row[2][1]] = .27
        elseif state == "false0" then
            general[row[2][1]], general[row[2][2]] = false, 0
            if row[2][4] then general[row[2][4]] = 0 end
        elseif state == "configured" then
            general[row[2][1]], general[row[2][2]], general[row[2][3]] = 0, .28, .39
            if row[2][4] then general[row[2][4]] = .42 end
        end
    end
    local before = Snapshot() M.Refresh() Settle()
    SameDB(before, row[1] .. ":" .. state .. ":read-only-refresh")
    assert(env.MSUF_DB == db and db.general == general and general.castPickerPresenceSentinel == sentinel,
        "Cast picker fixture replaced profile aliases")
end
local states = { "missing", "partial", "false0", "configured" }
local count, opacityEdits, seen, logicalOwners = 0, 0, {}, 0
local function RegisterOwner(path)
    local w = Widget(path)
    assert(not seen[w], "native Cast owners overlap") seen[w] = true
    logicalOwners = logicalOwners + 1
    return w
end
local function RunCase(row, state, w, family)
    Prepare(row, state)
    local label = row[1] .. ":" .. (family and family .. ":" or "") .. state
    assert(Shown(w) and w:IsEnabled(), "native Cast owner not reachable: " .. label)
    CheckPaint(w, label .. ":before-open")
    local generalBefore = Snapshot().general
    w:Click("LeftButton") Settle()
    local panel = assert(Panel(w), "native Cast picker Open failed: " .. label)
    MenuWorld.FireVisibilityScripts(panel)
    assert(Equal(generalBefore, Snapshot().general), "native picker Open changed raw color settings: " .. label)
    -- The genuine modal blocker covers UIParent. Family selection occurs before each Open;
    -- do not synthesize a click through that blocker and call it an offered native UI route.
    assert(Shown(panel.blocker), "native Cast picker modal blocker missing")
    if w._msuf2ColorHasOpacity == true then
        assert(Shown(panel.more), "native Cast picker More Options missing: " .. label)
        panel.more:Click("LeftButton") Settle()
        assert(panel.advanced == true and Shown(panel.opacity), "native Cast opacity editor not visible: " .. label)
        assert(Equal(generalBefore, Snapshot().general), "native More Options changed raw color settings: " .. label)
    end
    local hex = panel.advanced and panel.hex or panel.compactHex
    assert(Shown(hex), "native Cast HEX editor not visible: " .. label)
    M.ClearHistory() M.SyncExternalHistoryState()
    local before, model, painted = Snapshot(), Model(w), Paint(w)
    hex:SetText("2B4A6D") MenuWorld.FireScript(hex, "OnTextChanged", true)
    MenuWorld.FireScript(hex, "OnEnterPressed") Settle()
    local edited = Model(w)
    assert(Equal(Pack(edited[1], edited[2], edited[3]), Pack(43 / 255, 74 / 255, 109 / 255)),
        "native Cast picker HEX input did not reach owner: " .. label)
    if w._msuf2ColorHasOpacity == true then
        assert(Shown(panel.opacity), "native Cast opacity input is hidden: " .. label)
        MenuWorld.FireScript(panel.opacity, "OnValueChanged", .31) Settle()
        assert(w._msuf2GetColorOpacity() == .31, "native Cast opacity input did not reach owner: " .. label)
        opacityEdits = opacityEdits + 1
    end
    assert(not Equal(before, Snapshot()), "native Cast Cancel regression performed no real edit: " .. label)
    panel.cancel:Click("LeftButton") Settle()
    SameDB(before, label)
    assert(Equal(model, Model(w)) and Equal(painted, Paint(w)), "native Cast Cancel model/display drift: " .. label)
    CheckPaint(w, label .. ":after-cancel")
    assert(M.GetHistoryState().undoCount == 0, "native Cast Cancel left history: " .. label)
    assert(env.MSUF_DB == db and db.general == general and general.castPickerPresenceSentinel == sentinel,
        "native Cast Cancel replaced profile aliases: " .. label)
    count = count + 1
end
for _, row in ipairs(owners) do
    local w = RegisterOwner(row[1])
    for _, state in ipairs(states) do RunCase(row, state, w) end
end
local details = {}
for _, spec in ipairs(detailOwners) do details[spec[1]] = RegisterOwner(spec[1]) end
-- Target exposes all three detail owners on every supported client: 14 logical owners x 4 raw cases.
ChooseUnit("target")
for _, spec in ipairs(detailOwners) do
    for _, state in ipairs(states) do RunCase(DetailRow(spec, "target"), state, details[spec[1]], "target") end
end
assert(logicalOwners == 14 and count == 56 and opacityEdits == 8, "native Cast primary Cancel coverage incomplete")
local primaryCases, gateCases, familyCases = count, 0, 0
for _, unit in ipairs(units) do
    if unit ~= "target" then
        ChooseUnit(unit)
        for _, spec in ipairs(detailOwners) do
            local row, w = DetailRow(spec, unit), details[spec[1]]
            for _, state in ipairs(states) do
                if unit == "player" and spec[2] == "TargetName" then
                    Prepare(row, state)
                    assert(Shown(w) and not w:IsEnabled(), "Player TargetName color gate drift")
                    M.ClearHistory() M.SyncExternalHistoryState()
                    local before = Snapshot()
                    w:Click("LeftButton") Settle()
                    assert(not Panel(w), "disabled Player TargetName color opened picker")
                    SameDB(before, "disabled Player TargetName:" .. state)
                    assert(M.GetHistoryState().undoCount == 0, "disabled Player TargetName left history")
                    gateCases = gateCases + 1
                else
                    RunCase(row, state, w, unit) familyCases = familyCases + 1
                end
            end
        end
    end
end
assert(gateCases == 4 and familyCases == (#units - 1) * 12 - gateCases,
    "native Cast offered detail-family Cancel coverage incomplete")
assert(count == primaryCases + familyCases and opacityEdits == 8, "native Cast final Cancel coverage incomplete")
print("menu_castbar_picker_cancel_presence_smoke " .. flavor .. ":14 owners/56 primary cases/"
    .. familyCases .. " offered-family cases/4 Player gates/8 opacity edits PASS")
