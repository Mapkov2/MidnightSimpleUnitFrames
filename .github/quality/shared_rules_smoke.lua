-- The driver installs actual shared pure-rule bodies for standalone consumers.
local compose = assert(_G.MSUF_ComposeFontFlags)
local border = assert(_G.MSUF_NormalizeAuraDebuffTypeBorderMode)
local fraction = assert(_G.MSUF_UF_PointFraction)
assert(compose(nil, false, false) == "OUTLINE")
assert(compose("none", true, false) == "MONOCHROME")
assert(compose("THICKOUTLINE", true, true) == "OUTLINE,SLUG")
assert(border(true) == "SYMBOL" and border(false) == "OFF")
for _, value in ipairs({ "symbol", "BORDER_SYMBOL", "BORDER_SYMBOLS", "BORDER+SYMBOL", "ICON", "WITH_SYMBOL" }) do
    assert(border(value, "BORDER") == "SYMBOL", "saved border alias changed: " .. value)
end
assert(border("COLOR") == "BORDER" and border("disabled") == "OFF")
assert(border("unknown", "BORDER") == "BORDER" and border(nil) == "OFF")
for _, row in ipairs({
    { "BOTTOMLEFT", 0, 0 }, { "BOTTOM", 0.5, 0 }, { "BOTTOMRIGHT", 1, 0 },
    { "LEFT", 0, 0.5 }, { "CENTER", 0.5, 0.5 }, { "RIGHT", 1, 0.5 },
    { "TOPLEFT", 0, 1 }, { "TOP", 0.5, 1 }, { "TOPRIGHT", 1, 1 },
    { "unknown", 0.5, 0.5 },
}) do
    local x, y = fraction(row[1])
    assert(x == row[2] and y == row[3], "anchor coordinate changed: " .. row[1])
end

-- Exercise the actual nested builder against a small layout seam. Repeated
-- child settles must not schedule redundant parent layouts or lose context.
local handle = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua", "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
local bodySource = assert(source:match("local function CreateNestedAuraBuilder%b().-\nend"))
local build = assert(loadstring("local W, max = ...\n" .. bodySource .. "\nreturn CreateNestedAuraBuilder"))
local context, nested
local W = { PageBuilder = function(ctx)
    context = ctx
    nested = { y = -70, settles = 0, RelayoutCollapsibles = function(self) self.settles = self.settles + 1 end }
    return nested
end }
local create = build(W, math.max)
local parent = { width = 600, relayouts = 0, RequestRelayoutCollapsibles = function(self) self.relayouts = self.relayouts + 1 end }
assert(create({}, parent, {}) == parent, "missing entry must use parent builder")
local entry = {}
local body = { _msuf2CollapsibleEntry = entry, _msuf2Width = 300, SetHeight = function(self, height) self.height = height end }
local ctx = { key = "auras", entry = {}, inheritedValue = {} }
assert(create(ctx, parent, body) == nested)
assert(context.width == 320 and context.inheritedValue == ctx.inheritedValue
    and context.key == ctx.key and context.entry == ctx.entry and context.wrapper == body,
    "nested builder lost minimum width or inherited page context")
context:SetContentHeight(10)
assert(body.height == 80 and entry.contentHeight == 80 and parent.relayouts == 1)
context:SetContentHeight(79.8)
assert(parent.relayouts == 1, "unchanged clamped height rescheduled parent")
entry._msuf2SettleContentLayout()
assert(nested.settles == 1 and body.height == 112 and parent.relayouts == 2, "child settle lost parent height update")
entry._msuf2SettleContentLayout()
assert(nested.settles == 2 and parent.relayouts == 2, "unchanged child settle rescheduled parent")
print("shared_rules_smoke: OK (saved font/aura values, anchor geometry, nested layout)")
