local unpack = table.unpack or unpack
local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end

local function Frame(name)
    local frame = { name = name, shown = true }
    local noops = {
        "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetText", "SetTextColor", "SetAlpha",
        "SetColorTexture", "SetTexture", "SetVertexColor", "SetJustifyH", "SetWordWrap",
        "SetShadowOffset", "SetAllPoints", "ClearAllPoints", "SetActive", "SetChecked",
        "AddMaskTexture", "RemoveMaskTexture", "SetSnapToPixelGrid", "SetTexelSnappingBias",
    }
    for _, method in ipairs(noops) do frame[method] = function() end end
    function frame:SetShown(value) self.shown = value end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:CreateTexture() return Frame("texture") end
    function frame:CreateMaskTexture() return Frame("mask") end
    function frame:HookScript(event, callback) self["hook_" .. event] = callback end
    function frame:SetScript(event, callback) self["script_" .. event] = callback end
    return frame
end

_G.CreateFrame = function(_, name) return Frame(name or "frame") end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end
_G.MSUF_FRAME_STRATA_RANK = {
    AUTO = true, BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true,
    DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}
_G.MSUF_ResolveStatusbarTextureKey = function(key) return "resolved:" .. tostring(key) end

local db = {
    general = {
        hpPowerTextSelectedKey = "shared",
        barTexture = "Blizzard",
        absorbBarTexture = "Shield Texture",
        absorbBarOpacity = 0.65,
        fullHealthAbsorbStripe = true,
    },
    bars = { roundedUnitFrames = true, roundedGroupFrames = true, roundedPowerBars = true, roundedMouseover = true },
}
local registeredPage, sections, bindings, controls = nil, {}, {}, {}
local applyCalls = {}
local predictionTests = {}
local M = {}
local MSUF = { MSUF2 = M, MSUF_Auras3 = { MenuModel = { UnitEnabled = function() return true end } } }

function M.ValueTextList(...)
    local args, result = { ... }, {}
    for i = 1, #args, 2 do result[#result + 1] = { value = args[i], text = args[i + 1] } end
    return result
end
function M.Tr(value) return value end
function M.Pick(source, names)
    local result = {}
    for name in names:gmatch("%S+") do result[#result + 1] = source[name] end
    return unpack(result)
end
function M.PickDefaults(source)
    return source.GRADIENT_DIR_KEYS, source.PRIORITY_LABELS
end

local GP = {
    GRADIENT_DIR_KEYS = { LEFT = "gradientLeft", RIGHT = "gradientRight", UP = "gradientUp", DOWN = "gradientDown" },
    PRIORITY_LABELS = { AGGRO = "Aggro", DISPEL = "Dispel", PURGE = "Purge", BOSS = "Boss" },
    SCOPE_VALUES = M.ValueTextList("shared", "Shared", "player", "Player", "gf_party", "Party", "gf_raid", "Raid"),
}
GP.Call = function() return true end
GP.DB = function() return db end
GP.G = function() return db.general end
GP.Bars = function() return db.bars end
GP.ReadG = function(key, fallback) local v = db.general[key]; return v == nil and fallback or v end
GP.ReadGBool = GP.ReadG
GP.ReadB = function(key, fallback) local v = db.bars[key]; return v == nil and fallback or v end
GP.NormalizeScopeKey = function(value) return value end
GP.ScopeDBKeys = function(scope) return scope == "gf_raid" and { "raid", "mythicraid" } or { scope } end
GP.ScopeHasOverride = function(scope) return scope == "shared" or db[scope] and db[scope].hlOverride == true end
GP.ScopeSetOverride = function(scope, _, value) db[scope] = db[scope] or {}; db[scope].hlOverride = value end
GP.CurrentBarsScope = function() return db.general.hpPowerTextSelectedKey end
GP.IsGFScope = function(scope) return scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid" end
GP.BarScopeGet = function(key, fallback)
    local scope = db.general.hpPowerTextSelectedKey
    local scoped = scope ~= "shared" and db[scope]
    local v
    if scoped and scoped.hlOverride == true and scoped[key] ~= nil then
        v = scoped[key]
    else
        v = db.general[key]
    end
    return v == nil and fallback or v
end
GP.BarScopeSet = function(key, value)
    local scope = db.general.hpPowerTextSelectedKey
    if scope ~= "shared" then
        db[scope] = db[scope] or { hlOverride = true }
        db[scope][key] = value
    else
        db.general[key] = value
    end
end
GP.BarScopeGetBars = function(key, fallback) local v = db.bars[key]; return v == nil and fallback or v end
GP.BarScopeSetBars = function(key, value) db.bars[key] = value end
GP.GradientScopeGet = function(key, fallback, legacyKey)
    local value = db.general[key]
    if value == nil and legacyKey then value = db.general[legacyKey] end
    return value == nil and fallback or value
end
GP.GradientScopeSet = function(key, value) db.general[key] = value end
GP.GradientScopeHasExplicit = function(key) return db.general[key] ~= nil end
GP.TextureValues = function() return M.ValueTextList("Blizzard", "Blizzard") end
GP.CurrentPowerBarScopeUnit = function() return "player" end
GP.SmoothPowerGet = function() return true end
GP.SmoothPowerSet = function() end
GP.PriorityOrder = function() return { "AGGRO", "DISPEL", "PURGE", "BOSS" } end
GP.PriorityColor = function() return 1, 0.5, 0 end
GP.RefreshBorderTestModes = function() end
GP.SetAbsorbTextureTest = function(enabled, category)
    predictionTests[category] = enabled == true or nil
end
GP.IsAbsorbTextureTestEnabled = function(category) return predictionTests[category] == true end
GP.SetControlEnabled = function(control, value) if control then control.enabled = value end end
GP.SetControlsEnabled = function(list, value)
    if type(list) ~= "table" or list.SetShown then list = { list } end
    for _, control in ipairs(list) do if control then control.enabled = value end end
end
GP.ApplyBars = function(reason) applyCalls[#applyCalls + 1] = reason end
GP.ControlMeta = function(page, scope, path, classification, exact)
    return { page = page, scope = scope, path = path, classification = classification, exact = exact }
end
GP.RegisterControl = function(control, meta) controls[#controls + 1] = { control = control, meta = meta } end
GP.BuildScopeOverrideSection = function(_, builder, spec)
    builder:CollapsibleSection("bars_scope", "Scope", 100)
    local current = spec.getValue()
    spec.hasOverride(current)
    spec.getOverride()
    if spec.updateHint then spec.updateHint(Widget and Widget("hint") or Frame("hint"), current, true, current == "shared") end
end
M.GlobalPage = GP

local function Widget(name)
    local frame = Frame(name)
    frame._msuf2Title = Frame(name .. "Title")
    frame._msuf2Label = frame._msuf2Title
    frame._msuf2ControlKind = name
    function frame:SetValueFormatter(callback) self.formatter = callback end
    function frame:SetValueParser(callback) self.parser = callback end
    return frame
end
M.Widgets = {
    PageBuilder = function()
        local builder = { y = -72 }
        function builder:GlobalStyleHeader() end
        function builder:CollapsibleSection(key, _, height)
            sections[key] = true
            self.y = self.y - height
            local frame = Widget("section"); frame._msuf2Width = 900
            return frame
        end
        return builder
    end,
    Dropdown = function(_, label, values)
        local widget = Widget("dropdown:" .. tostring(label))
        widget.values = values
        return widget
    end,
    Slider = function(_, label) return Widget("slider:" .. tostring(label)) end,
    Toggle = function(_, label) return Widget("toggle:" .. tostring(label)) end,
    ToggleAt = function(_, label) return Widget("toggle:" .. tostring(label)) end,
    SwitchAt = function(_, label) return Widget("toggle:" .. tostring(label)) end,
    Color = function(_, label) return Widget("color:" .. tostring(label)) end,
    Text = function() return Widget("text") end,
    LabelAt = function() return Widget("label") end,
    ControlCard = function() return Widget("card") end,
    MoveWidget = function() end,
    SegmentTabs = function(_, _, spec)
        local segment = Widget("segment"); segment.buttons = {}
        for i = 1, #spec.values do segment.buttons[i] = Widget("button") end
        return segment
    end,
}
M.Theme = {
    colors = { muted = { 1, 1, 1 }, dim = { 1, 1, 1 }, accent = { 1, 1, 1 }, text = { 1, 1, 1 } },
    Font = function() return Widget("font") end,
    Panel = function() return Widget("panel") end,
    Button = function() return Widget("button") end,
    CenterButtonLabel = function() end,
}

local function Bind(kind, control, getter, setter)
    bindings[#bindings + 1] = { kind = kind, control = control, get = getter, set = setter }
end
M.BindDropdownWidget = function(_, c, g, s) Bind("dropdown", c, g, s) end
M.BindBoolWidget = function(_, c, g, s) Bind("bool", c, g, s) end
M.BindNumberWidget = function(_, c, g, s) Bind("number", c, g, s) end
M.BindSlider = function(_, c, g, s) Bind("slider", c, g, s) end
M.BindColor = function(_, c, g, s) Bind("color", c, g, s) end
M.AddRefresher = function(_, callback) callback() end
M.TrackRefresh = function(_, callback) if type(callback) == "function" then callback() end end
M.RefreshProxy = function()
    local callback
    return function(value)
        if type(value) == "function" then callback = value; return value end
        if callback then return callback() end
    end
end
M.BindGateGroup = function() return function() end end
M.BuildControlSpecs = function(specs, builders)
    local result = {}
    for i, spec in ipairs(specs) do
        local build = builders[spec[1]] or builders["*"]
        local control, key = build(spec, i)
        result[key or i] = control
    end
    return result
end
M.UnitSectionsShared = {
    MakeTabFrames = function(_, _, _, store, ...)
        local result = {}
        for _, key in ipairs({ ... }) do local f = Widget("tab"); store[key] = f; result[#result + 1] = f end
        return unpack(result)
    end,
    MakeDragSortRows = function(_, _, spec)
        local container = { rows = {} }
        for i = 1, spec.maxRows do
            local frame = Widget("row"); frame._stripe, frame._label, frame._numText = Widget("stripe"), Widget("label"), Widget("number")
            container.rows[i] = { frame = frame, slotIndex = i }
        end
        function container:SetRowsEnabled(value) self.enabled = value end
        function container:SetActiveCount(value) self.activeCount = value end
        return container
    end,
}
M.PreviewHelpers = {
    SnapOff = function() end,
    EnsureRoundedMask = function() return Widget("mask") end,
    SetMask = function() end,
}
M.ApplyService = setmetatable({}, { __index = function(_, method)
    return function(...) applyCalls[#applyCalls + 1] = method; return true end
end })
M.RegisterSearchWidget = function() end
M.InstallStaticPopup = function() end
M.RunWithHistory = function(_, _, callback) callback() end
M.RequestUnitApply = function() return true end
M.RequestRefresh = function() end
M.SelectPage = function() end
M.RegisterPage = function(key, page) assert(key == "opt_bars"); registeredPage = page end

assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(registeredPage and type(registeredPage.build) == "function", "Bars page was not registered")
local ctx = { width = 900, key = "opt_bars", SetContentHeight = function(self, value) self.contentHeight = value end }
registeredPage.build(ctx)

local anchorCount, testCount = 0, 0
local anchorPreviewCategories = {}
for _, binding in ipairs(bindings) do
    if binding.control.name == "dropdown:Anchor" then
        anchorCount = anchorCount + 1
        local values = binding.control.values
        assert(type(values) == "table" and #values >= 4, "anchor preview values missing")
        local category
        for _, item in ipairs(values) do
            assert(item.previewKind == "barOverlay" and type(item.barPreview) == "function",
                "anchor option has no visual bar preview")
            local preview = item.barPreview(item)
            assert(type(preview) == "table" and preview.mode == item.value,
                "anchor preview does not reflect its option")
            assert(type(preview.overlayTexture) == "string" and type(preview.overlayColor) == "table",
                "anchor preview does not reflect texture/color settings")
            category = category or preview.category
            assert(preview.category == category, "anchor dropdown mixed prediction categories")
            if preview.category == "negative" then
                assert(preview.followInsideHealth == true, "negative follow-current-HP preview is not inside health")
            end
        end
        anchorPreviewCategories[category] = true
    end
    if binding.control.name == "toggle:Test prediction bars" then testCount = testCount + 1 end
end
assert(anchorCount == 3, "the three prediction categories need independent anchors")
assert(testCount == 3, "the three prediction categories need independent test toggles")
assert(anchorPreviewCategories.positive and anchorPreviewCategories.negative and anchorPreviewCategories.heal,
    "the three anchor dropdowns need category-specific previews")

local fullHealthStripeBinding
for _, binding in ipairs(bindings) do
    if binding.control.name == "toggle:Full-health absorb stripe" then
        fullHealthStripeBinding = binding
        break
    end
end
assert(fullHealthStripeBinding, "full-health absorb stripe binding missing")
db.player = { hlOverride = true, fullHealthAbsorbStripe = false }
db.general.hpPowerTextSelectedKey = "player"
assert(fullHealthStripeBinding.get() == false, "full-health stripe did not read the selected scope")
fullHealthStripeBinding.set(true)
assert(db.general.fullHealthAbsorbStripe == true and db.player.fullHealthAbsorbStripe == true,
    "full-health stripe did not stay inside the selected scope")
db.general.fullHealthAbsorbStripe = true
db.general.hpPowerTextSelectedKey = "shared"

for _, key in ipairs({ "bars_textures", "bars_absorb", "bars_outline", "bars_rounded", "bars_highlight", "bars_unit_dispel_overlay", "bars_power" }) do
    assert(sections[key], "missing section: " .. key)
end
assert(ctx.contentHeight and ctx.contentHeight > 0, "content height was not finalized")
assert(#bindings >= 25, "unexpected binding count: " .. #bindings)
assert(#controls == 15, "control metadata registration changed: " .. #controls)
local expectedControlPaths = {
    ["gradient.health.direction.UP"] = true,
    ["gradient.health.direction.DOWN"] = true,
    ["gradient.power.direction.UP"] = true,
    ["gradient.power.direction.DOWN"] = true,
    ["gradient.colors"] = true,
    ["absorb.workspace_tab"] = true,
    ["highlight.workspace_tab"] = true,
    ["highlight.priority.order.order"] = true,
}
for _, item in ipairs(controls) do
    if item.meta then expectedControlPaths[item.meta.path] = nil end
end
assert(next(expectedControlPaths) == nil, "semantic control metadata registration was lost")
for i, binding in ipairs(bindings) do
    local values = pack(binding.get())
    assert(values.n > 0, "binding getter returned no value: " .. i .. " " .. binding.control.name)
    if binding.kind == "color" then
        binding.set(unpack(values))
    else
        binding.set(values[1])
    end
end

print(("global bars page smoke ok: %d bindings, %d registered controls, %d apply calls")
    :format(#bindings, #controls, #applyCalls))
