-- Local-only headless smoke for the non-Assistant group indicators page.
unpack = table.unpack
local widgets, registered, refreshers, dialogs = {}, {}, {}, {}
local scope, config = "party", { party = {}, raid = {} }

local Frame = {}
Frame.__index = function(self, key)
    if key == "SetScript" then return function(owner, event, fn) owner.scripts[event] = fn end end
    if key == "Click" then return function(owner, ...) if owner.scripts.OnClick then return owner.scripts.OnClick(owner, ...) end end end
    if key == "CreateTexture" or key == "CreateFontString" then return function() return NewFrame(key) end end
    if key == "GetFrameStrata" then return function() return "MEDIUM" end end
    if key == "GetLeft" or key == "GetTop" then return function() return 0 end end
    if key == "GetCenter" then return function() return 0, 0 end end
    if key == "GetChildren" then return function() end end
    if key == "SetText" then return function(owner, value) owner.text = value end end
    if key == "GetText" then return function(owner) return owner.text or "" end end
    if key == "SetShown" then return function(owner, value) owner.shown = value end end
    if key == "Show" then return function(owner) owner.shown = true end end
    if key == "Hide" then return function(owner) owner.shown = false end end
    return function() end
end
function NewFrame(label)
    local frame = setmetatable({ label = label, scripts = {}, shown = true }, Frame)
    frame._msuf2Title = setmetatable({ scripts = {} }, Frame)
    widgets[#widgets + 1] = frame
    return frame
end

local W, T, M = {}, { colors = { accent = { .3, .7, 1, 1 }, dim = { .3, .3, .3, 1 }, muted = { .6, .6, .6, 1 }, text = { 1, 1, 1, 1 }, header = {}, borderSoft = {} } }, {}
for _, name in ipairs({ "Button", "Color", "ControlCard", "ControlCardBackdrop", "Dropdown", "LabelAt", "Slider", "SwitchAt", "Text", "TextInput", "ToggleAt" }) do
    W[name] = function(_, label) return NewFrame(label or name) end
end
W.ControlCard = function(_, title, subtitle) local frame = NewFrame(title); if subtitle then frame.subtitle = NewFrame(subtitle) end; return frame end
W.MoveWidget = function(control) return control end
W.SetControlShown = function(control, shown) control.shown = shown end
W.SetControlEnabled = function(control, enabled) if control then control.enabled = enabled end end
W.SetControlsEnabled = function(list, enabled) for i = 1, #(list or {}) do W.SetControlEnabled(list[i], enabled) end end
W.SegmentTabs = function() return NewFrame("tabs") end
W.PageBuilder = function(ctx)
    local builder = { parent = NewFrame("page"), width = ctx.width, x = 0, y = -10 }
    function builder:Section(label, second, third)
        local height = type(second) == "number" and second or third
        self.y = self.y - (height or 0) - 8
        local frame = NewFrame(label); frame._msuf2Width = self.width; return frame
    end
    builder.CollapsibleSection = builder.Section
    return builder
end
T.Panel, T.Button, T.ApplySurface, T.CenterButtonLabel = function() return NewFrame("panel") end, function(_, label) return NewFrame(label) end, function() end, function() end

function M.ValueTextList(...)
    local out = {}
    for i = 1, select("#", ...), 2 do out[#out + 1] = { value = select(i, ...), text = select(i + 1, ...) } end
    return out
end
function M.WordList(text) local out = {}; for word in text:gmatch("%S+") do out[#out + 1] = word end; return out end
function M.Pick(source, names) local out = {}; for name in names:gmatch("%S+") do out[#out + 1] = source[name] end; return table.unpack(out) end
M.PickDefaults = M.Pick
function M.Assign(target, source) for key, value in pairs(source or {}) do target[key] = value end; return target end
function M.AppendValues(target, ...) for i = 1, select("#", ...) do target[#target + 1] = select(i, ...) end; return target end
function M.RefreshProxy() local fn; return function(value) if value then fn = value; return value end; if fn then return fn() end end end
function M.CallIf(fn, ...) if type(fn) == "function" then return fn(...) end end
function M.Format(pattern, ...) return pattern:format(...) end
function M.SetMenuStateValue(key, value) M[key] = value; return value end
function M.RunWithHistory(_, _, fn) return fn() end
function M.InstallStaticPopup(key, spec) dialogs[key] = spec end
function M.RegisterPage(key, spec) M.pageKey, M.page = key, spec end
function M.BuildControlSpecs(specs, handlers)
    local out = {}
    for i = 1, #specs do local control, name = handlers[specs[i][1]](specs[i], i); out[name or i] = control end
    return out
end
local function Bind(control, get, set, meta) control.getter, control.setter, control.meta = get, set, meta; return control end
function M.BindBoolWidget(_, control, get, set, meta) return Bind(control, get, set, meta) end
M.BindDropdownWidget = M.BindBoolWidget
function M.BindNumberWidget(_, control, get, set, _, meta) return Bind(control, get, set, meta) end
function M.BindTextInput(_, control, get, set, _, meta) return Bind(control, get, set, meta) end
function M.BindColor(_, control, get, set, meta) return Bind(control, get, set, meta) end
M.AddTooltip, M.RequestRefresh, M.Refresh, M.SelectPage, M.RefreshGFNativePreviews = function() end, function() end, function() end, function() end, function() end
M.ShowStatusFeedback = function(text, kind) M.feedback = { text, kind } end
M.Tr, M.TranslateText = function(text) return text end, function(text) return text end
M.OnOffBadge = function(enabled, on, off) return { text = enabled and on or off } end
M.OptionText = function(_, value, fallback) return value or fallback end
M.GroupPreview = { Add = function(_, builder) return builder:Section("preview", 80) end }
M.UnitSectionsShared = { MakeTabFrames = function(_, _, _, _, ...)
    local out = {}; for i = 1, select("#", ...) do out[i] = NewFrame(select(i, ...)) end; return table.unpack(out)
end }
M.Widgets, M.Theme = W, T

local statusSpec = { value = "roleIcon", text = "Role", enabled = "roleEnabled", size = "roleSize", anchor = "roleAnchor", x = "roleX", y = "roleY", layer = "roleLayer", iconStyle = "roleStyle", customIcon = "roleCustom", defaultSize = 14, defaultAnchor = "TOPRIGHT", defaultLayer = 5 }
local values = function(...) return M.ValueTextList(...) end
local runtimeSI = {
    SpecInfo = { test = { display = "Test" } },
    TrackableAuras = { test = { { name = "BuffA", display = "Buff A", spellID = 1001, color = { .2, .8, 1 } }, { name = "BuffB", display = "Buff B", spellID = 1002 } } },
    SpellIDs = { test = { BuffA = 1001, BuffB = 1002 } },
    EnsureSpecConfig = function(si, spec) si.specs = si.specs or {}; si.specs[spec] = si.specs[spec] or {} end,
    GetAuraIcon = function() return 136243 end,
    InvalidateRuntimeCaches = function() end,
}
local runtime = { SpellIndicators = runtimeSI, GetIconStyleItems = function() return values("DEFAULT", "Default") end, GetDefault = function() return nil end }
local function Conf(kind)
    config[kind] = config[kind] or {}
    local cfg = config[kind]
    cfg.spellIndicators = cfg.spellIndicators or { enabled = true, spec = "test", specs = { test = { BuffA = { enabled = true, onlyOwn = true, placed = { type = "icon" }, frame = { type = "border" } } } } }
    cfg.ciCustom = cfg.ciCustom or {}
    return cfg
end
local GP
GP = {
    AURA_ANCHORS = values("TOPLEFT", "Top Left"), STATUS_ICON_ANCHORS = values("TOPLEFT", "Top Left"),
    GF_STATUS_ICON_SPECS = { statusSpec }, GF_STATUS_ICON_VALUES = { { value = "roleIcon", text = "Role" } },
    PLACED_INDICATOR_TYPES = values("none", "None", "icon", "Icon", "bar", "Bar"), FRAME_EFFECT_TYPES = values("none", "None", "border", "Border"),
    SPELL_GROWTH_VALUES = values("RIGHTDOWN", "Right Down"), CI_SLOT_VALUES = { { value = "TL", text = "Top Left" } }, CI_SLOT_DEFAULTS = { TL = "none" },
    GF = function() return runtime end, RefreshGFPreview = function() end, Conf = Conf,
    Val = function(kind, key, default) local value = Conf(kind)[key]; return value == nil and default or value end,
    Bool = function(kind, key, default) local value = Conf(kind)[key]; return value == nil and default or value == true end,
    Num = function(kind, key, default) return tonumber(Conf(kind)[key]) or default end,
    Set = function(kind, key, value) Conf(kind)[key] = value end,
    QueueGF = function() end, QueueSpellIndicators = function() end,
    CurrentScope = function() return scope end,
    ScopeSection = function(ctx, builder) return builder:Section("scope", 54) end,
    BindScopeToggle = function(ctx, control, key, default) return Bind(control, function() local v = Conf(scope)[key]; return v == nil and default or v end, function(v) Conf(scope)[key] = v end) end,
    ScopeDropdown = function(ctx, parent, label) return W.Dropdown(parent, label) end,
    ScopeSlider = function(ctx, parent, label) return W.Slider(parent, label) end,
    ScopeColor = function(ctx, parent, label) return W.Color(parent, label) end,
    SpellIndicators = function(kind) return Conf(kind).spellIndicators end,
    IconStyleValues = function() return values("BLIZZARD", "Blizzard") end,
    CurrentGFStatusSpec = function() return statusSpec end,
    SpellSpecValues = function() return values("auto", "Auto", "test", "Test") end,
    SpellTrackedSpecValues = function() return values("test", "Test") end,
    CurrentSpellMultiSpec = function() return "test" end, EffectiveSpellSpec = function() return "test" end,
    SpellAuraValues = function() return values("BuffA", "Buff A", "BuffB", "Buff B") end,
    SetCurrentSpellAura = function(_, aura) M.selectedAura = aura end, ClearCurrentSpellAura = function() M.selectedAura = nil end,
    CurrentSpellAura = function() return M.selectedAura or "BuffA" end,
    CurrentSpellConfig = function(kind, create) local spec = Conf(kind).spellIndicators.specs.test; if create and not spec[M.selectedAura or "BuffA"] then spec[M.selectedAura or "BuffA"] = {} end; return spec[M.selectedAura or "BuffA"] end,
    PlacedConfig = function(kind, create) local cfg = GP.CurrentSpellConfig(kind, create); if create and cfg and type(cfg.placed) ~= "table" then cfg.placed = { type = "icon" } end; return cfg and cfg.placed end,
    FrameEffectConfig = function(kind, create) local cfg = GP.CurrentSpellConfig(kind, create); if create and cfg and type(cfg.frame) ~= "table" then cfg.frame = { type = "none" } end; return cfg and cfg.frame end,
    CICategoryValues = function() return values("none", "None", "custom", "Custom") end, CIFilterValues = function() return values("HELPFUL|PLAYER", "Helpful") end, CIModeValues = function() return values("present", "Present") end,
    CurrentCISlot = function() return "TL" end, CICustomConfig = function(kind, _, create) local cfg = Conf(kind); if create then cfg.ciCustom.TL = cfg.ciCustom.TL or {} end; return cfg.ciCustom.TL end,
    BindNestedSlider = function(ctx, control, get, key, default, _, path) return Bind(control, function() return get()[key] or default end, function(v) get()[key] = v end, { path = path }) end,
    BindNestedStrataSlider = function(ctx, control, get, key, default, _, path) return Bind(control, function() return get()[key] or default end, function(v) get()[key] = v end, { path = path }) end,
    SetOptionEnabled = W.SetControlEnabled, SetOptionsEnabled = W.SetControlsEnabled,
    FinalizeScopePage = function(ctx, builder) ctx:SetContentHeight(math.abs(builder.y) + 42) end,
    SetSectionBadgesAndStatus = function() end, TrackSectionRefresh = function(_, _, fn) refreshers[#refreshers + 1] = fn end,
    OnOffBadge = M.OnOffBadge, OptionText = M.OptionText, FrameStrataCount = 9,
    ControlMeta = function(_, path, classification) return { path = path, classification = classification } end,
    RegisterControl = function(control, _, path) control.meta = control.meta or { path = path }; registered[path] = control end,
}
M.GroupPage = GP

_G.CreateFrame, _G.GameTooltip = function(_, _, parent) local frame = NewFrame("frame"); frame.parent = parent; return frame end, NewFrame("tooltip")
_G.StaticPopupDialogs, _G.StaticPopup_Show, _G.CANCEL = {}, function(key, _, _, data) dialogs.lastKey, dialogs.lastData = key, data end, "Cancel"
_G.C_Spell = { GetSpellInfo = function(id) return { name = "Buff " .. id, iconID = 136243 } end, RequestLoadSpellData = function() end }
_G.C_UnitAuras = {}
_G.issecretvalue = function() return false end

local MSUF = { MSUF2 = M }
assert(loadfile("Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(M.pageKey == "gf_indicators" and M.page.version == 17, "page registration changed")
for _, width in ipairs({ 980, 620 }) do
    local ctx = { width = width, key = "gf_indicators", SetContentHeight = function(self, height) self.height = height end }
    M.page.build(ctx)
    assert(ctx.height and ctx.height > 0, "content height missing")
    GP.BuildSpellIndicatorsSection(ctx, W.PageBuilder(ctx), function() end)
end
for i = 1, #refreshers do refreshers[i]() end
assert(registered["spell.tile.slot.1"] and registered["spell.tile.slot.3"], "spell tiles were not built")
assert(registered["spell.enabled"] == nil, "bound metadata should not require explicit registration")

local addTile = registered["spell.tile.slot.3"]
addTile.scripts.OnMouseUp(addTile, "LeftButton")
assert(dialogs.lastKey == "MSUF2_GF_SPELL_CUSTOM_BUFF_ID", "custom buff popup changed")
local popup = dialogs.MSUF2_GF_SPELL_CUSTOM_BUFF_ID
local edit = { GetText = function() return "12345" end }
popup.OnAccept({ editBox = edit }, dialogs.lastData)
local custom = Conf("party").spellIndicators.specs.test["12345"]
assert(custom and custom.custom == true and custom.spellID == 12345 and custom.spells == "12345", "native AuraSlot spell IDs changed")
assert(custom.onlyOwn == false and custom.placed and custom.placed.type == "icon", "custom buff defaults changed")

print(("group indicators page smoke ok: refreshers=%d catalog_controls=%d"):format(#refreshers, (function() local n=0; for _ in pairs(registered) do n=n+1 end; return n end)()))
