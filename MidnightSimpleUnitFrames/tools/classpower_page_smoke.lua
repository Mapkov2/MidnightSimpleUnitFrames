-- Local-only smoke harness for the non-Assistant ClassPower page.
table.unpack = table.unpack or unpack
unpack = table.unpack
local controls, widgets, refreshers, dialogs, globals = {}, {}, {}, {}, {}
local db = { bars = {}, player = {}, general = {} }

local Frame = {}
Frame.__index = function(self, key)
    if key == "GetFrameLevel" then return function() return 1 end end
    if key == "SetScript" then return function(owner, event, fn) owner.scripts[event] = fn end end
    if key == "SetValue" then return function(owner, value) owner.value = value end end
    if key == "GetValue" then return function(owner) return owner.value end end
    return function() end
end
local function NewFrame(label)
    local frame = setmetatable({ label = label, scripts = {}, _msuf2Title = setmetatable({ scripts = {} }, Frame) }, Frame)
    widgets[#widgets + 1] = frame
    return frame
end

local W, T, M = {}, { colors = { header = {}, borderSoft = {}, muted = {}, text = {} } }, {}
local function Widget(_, label) return NewFrame(label) end
W.Dropdown, W.Slider, W.Toggle, W.SwitchAt, W.Segment, W.Text = Widget, Widget, Widget, Widget, Widget, Widget
W.MoveWidget = function(control) return control end
W.SetControlEnabled = function(control, enabled) if control then control.enabled = enabled end end
W.SetControlsEnabled = function(list, enabled) for i = 1, #(list or {}) do W.SetControlEnabled(list[i], enabled) end end
W.ControlCard, W.ControlCardBackdrop = function() return NewFrame("card") end, function() return NewFrame("backdrop") end
W.SegmentTabs = function() return NewFrame("tabs") end
W.StyleTopActionButton, W.StyleTopSuccessButton = function() end, function() end
W.PageBuilder = function(ctx)
    local builder = { parent = NewFrame("page"), x = 0, y = -12, width = ctx.width }
    function builder:Section(label, second, third)
        local height = type(second) == "number" and second or third
        self.y = self.y - (height or 0) - 8
        local frame = NewFrame(label); frame._msuf2Width = self.width; return frame
    end
    builder.CollapsibleSection = builder.Section
    return builder
end
T.Panel, T.Button = function() return NewFrame("panel") end, function(_, label) return NewFrame(label) end
T.ApplySurface = function() end

function M.RefreshProxy()
    local target
    return function(fn) if fn then target = fn; return fn end; if target then return target() end end
end
function M.Pick(source, words)
    local out = {}
    for key in words:gmatch("%S+") do out[#out + 1] = source[key] end
    return table.unpack(out)
end
function M.ValueTextList(...)
    local values = {}
    for i = 1, select("#", ...), 2 do values[#values + 1] = { value = select(i, ...), text = select(i + 1, ...) } end
    return values
end
function M.ValueTextPairs(text)
    local values = {}
    for pair in text:gmatch("[^|]+") do local value, label = pair:match("^([^=]+)=(.*)$"); values[#values + 1] = { value = value, text = label } end
    return values
end
function M.WordList(text) local out = {}; for word in text:gmatch("%S+") do out[#out + 1] = word end; return out end
function M.KeySetFromWords(text) local out = {}; for word in text:gmatch("%S+") do out[word] = true end; return out end
function M.AppendValues(target, ...) for i = 1, select("#", ...) do target[#target + 1] = select(i, ...) end; return target end
function M.AppendNamedValues(target, source, names) for key in names:gmatch("%S+") do target[#target + 1] = source[key] end; return target end
function M.Assign(target, source) for key, value in pairs(source or {}) do target[key] = value end; return target end
function M.EnsureDB() db.bars, db.player, db.general = db.bars or {}, db.player or {}, db.general or {}; return db end
function M.TrackRefresh(_, fn) refreshers[#refreshers + 1] = fn end
function M.BindBoolWidget(_, control, get, set, meta) control.getter, control.setter, control.meta = get, set, meta end
M.BindDropdownWidget, M.BindSegment = M.BindBoolWidget, M.BindBoolWidget
function M.BindNumberWidget(_, control, get, set, _, meta) control.getter, control.setter, control.meta = get, set, meta end
function M.RunWithHistory(_, _, fn) return fn() end
function M.InstallStaticPopup(key, spec) dialogs[key] = spec end
function M.RegisterPage(key, spec) M.pageKey, M.page = key, spec end
function M.TextSlotOffsetKeys(_, slot) return "powerText" .. slot:gsub("^%l", string.upper) .. "OffsetX", "powerText" .. slot:gsub("^%l", string.upper) .. "OffsetY" end
M.StatusBarTextureItems = function(label) return { { value = "", text = label } } end
M.Tr = function(text) return text end
M.AddTooltip, M.RequestGeneralApply, M.RequestUnitApply, M.RequestRefresh, M.SelectPage = function() end, function() end, function() end, function() end, function() end
M.ClassPowerPreview = {
    NormalizeClassShape = function(value) value = tostring(value or "BAR"):upper(); return ({ BAR = 1, CIRCLE = 1, DIAMOND = 1, HEX = 1 })[value] and value or "BAR" end,
    ResolvePowerShape = function(value, classShape) value = tostring(value or "BAR"):upper(); if value == "FOLLOW_CLASS" then return classShape == "CIRCLE" and "ROUND" or "BAR" end; return value end,
}
M.ClassPowerStackPreview = { Create = function(_, builder) return builder:Section("preview", 64) end }
M.UnitSectionsShared = { MakeTabFrames = function(_, _, _, _, ...)
    local frames = {}
    for i = 1, select("#", ...) do frames[i] = NewFrame(select(i, ...)) end
    return table.unpack(frames)
end }

local AP = {}
function AP.CallGlobal(name, ...) globals[#globals + 1] = { name, ... }; return false end
function AP.Bars() return M.EnsureDB().bars end
function AP.BoolValue(source, key, default) local value = source and source[key]; if value == nil then return default end; return value == true end
function AP.NumValue(source, key, default) return tonumber(source and source[key]) or default end
function AP.SetValue(source, key, value, apply) source[key] = value; if apply then apply() end end
AP.DeepCopyTable = function(value) if type(value) ~= "table" then return value end; local out = {}; for key, item in pairs(value) do out[key] = AP.DeepCopyTable(item) end; return out end
function AP.ControlMeta(_, _, path, classification, exact) return { path = path, classification = classification, exact = exact } end
function AP.RegisterControl(control, meta) control.meta = control.meta or meta; controls[#controls + 1] = control end
function AP.SetControlEnabled(control, enabled) W.SetControlEnabled(control, enabled) end
function AP.SwitchAt(ctx, parent, label, _, _, _, source, key, default, apply, meta)
    local control = W.SwitchAt(parent, label)
    M.BindBoolWidget(ctx, control, function() local value = source()[key]; return value == nil and default or value end,
        function(value) AP.SetValue(source(), key, value, apply) end, meta)
    return control
end
function AP.BuildTableControlSpecs(ctx, parent, source, apply, specs, customKinds)
    local result = {}
    for i = 1, #specs do
        local spec, control = specs[i]
        if customKinds[spec[2]] then
            control = customKinds[spec[2]](ctx, parent, source, apply, spec)
        else
            control = W[spec[2] == "toggle" and "Toggle" or spec[2] == "slider" and "Slider" or "Dropdown"](parent, spec[3])
            local key = spec[2] == "toggle" and spec[4] or spec[2] == "slider" and spec[8] or spec[6]
            local default = spec[2] == "toggle" and spec[5] or spec[2] == "slider" and spec[9] or spec[7]
            local callback = spec[2] == "toggle" and spec[6] or spec[2] == "slider" and spec[10] or spec[8]
            M.BindBoolWidget(ctx, control, function() local value = source()[key]; return value == nil and default or value end,
                function(value) AP.SetValue(source(), key, value, callback or apply) end, spec.meta)
        end
        result[spec[1]] = control
    end
    return result
end
M.AdvancedPage = AP
M.Widgets, M.Theme = W, T

local MSUF = { MSUF2 = M, UF = {} }
function MSUF.ExportPublic(name, value) _G[name] = value; return value end
_G.StaticPopupDialogs, _G.C_Timer, _G.OKAY = {}, { After = function() end }, "OK"
_G.StaticPopup_Show = function(key) dialogs.lastShown = key end
_G.GameTooltip = NewFrame("tooltip")

assert(loadfile("Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(M.pageKey == "classpower" and M.page.version == 18, "page registration changed")
for _, width in ipairs({ 900, 580 }) do
    local ctx = { width = width, SetContentHeight = function(self, value) self.height = value end }
    M.page.build(ctx)
    assert(ctx.height and ctx.height > 0, "content height was not set")
end
local byPath = {}
for i = 1, #widgets do
    local meta = rawget(widgets[i], "meta")
    if type(meta) == "table" and meta.path then byPath[meta.path] = widgets[i] end
end
for _, path in ipairs({ "layout.enabled", "layout.shape", "behavior.ironfur", "behavior.ironfurHashes", "behavior.smooth", "style.resources.fgTex",
    "visibility.out_of_combat", "detached_power.enabled", "detached_power.text.slot_offset.x", "player_hp.enabled", "alternative_mana.enabled" }) do
    assert(byPath[path], "missing control metadata: " .. path)
end
db.bars.showClassPower = false
assert(byPath["layout.enabled"].getter() == false, "class resource toggle must read OFF without inversion")
byPath["layout.enabled"].setter(true)
assert(db.bars.showClassPower == true and byPath["layout.enabled"].getter() == true, "class resource toggle ON state inverted")
byPath["layout.enabled"].setter(false)
assert(db.bars.showClassPower == false and byPath["layout.enabled"].getter() == false, "class resource toggle OFF state inverted")
db.player.hpPowerTextOverride = true
byPath["detached_power.text.powerTextRightHidePercentSymbol"].setter(true)
assert(db.player.powerTextRightHidePercentSymbol == true and db.player.hpPowerTextOverride == nil, "detached text override binding changed")
byPath["detached_power.enabled"].setter(true)
assert(db.player.powerBarDetached == true and db.player.detachedPowerBarOffsetY == -4, "detached power defaults changed")
byPath["layout.independent_powerbar_shape"].setter("ORB")
assert(db.player.detachedPowerBarShape == "ORB" and db.player.detachedPowerOrbSize == 54, "detached orb defaults changed")
byPath["detached_power.layout.mode"].setter("cooldown")
assert(db.bars.detachedPowerBarWidthMode == "cooldown", "detached width mode binding changed")
byPath["detached_power.layout.mode"].setter("manual")
assert(db.bars.detachedPowerBarWidthMode == nil, "detached width default must remain sparse")
for i = 1, #refreshers do refreshers[i]() end

db.bars.showClassPower, db.bars.classPowerShape, db.bars.playerHPBarEnabled = false, "CIRCLE", true
db.player.powerBarDetached, db.player.showPowerText = true, true
for i = 1, #refreshers do refreshers[i]() end

db.bars.classPowerShape, db.player.powerBarDetached = "HEX", false
_G.MSUF2_ClassPowerQuickSetup()
assert(db.bars.showClassPower == true and db.bars.classPowerWidthMode == "cooldown", "quick setup class bar changed")
assert(db.player.powerBarDetached == true and db.player.detachedPowerBarAnchorToClassPower == true, "quick setup player power changed")
assert(dialogs.MSUF2_CLASSPOWER_QUICK_RESULT, "quick setup result popup missing")
dialogs.MSUF2_CLASSPOWER_QUICK_RESULT.OnCancel()
assert(db.bars.classPowerShape == "HEX" and db.player.powerBarDetached == false, "quick setup undo changed")

print(("classpower page smoke ok: %d explicit catalog controls, %d refreshers"):format(#controls, #refreshers))
