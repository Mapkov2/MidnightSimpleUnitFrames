-- Regression: leaving the cached Colors page releases and Hide()s its pinned
-- preview host. Returning to the cached page must show the host and reattach
-- pin ownership; showing only its Player/Target children leaves a blank card.

local unpack = table.unpack or unpack

local Frame = {}
Frame.__index = Frame

local function NewFrame(parent)
    return setmetatable({
        parent = parent,
        shown = true,
        scripts = {},
        hooks = {},
        frameLevel = ((parent and parent.frameLevel) or 0) + 1,
        width = 1,
        height = 1,
    }, Frame)
end

function Frame:SetPoint(...) self.point = { ... } end
function Frame:ClearAllPoints() self.point = nil end
function Frame:SetAllPoints(target) self.allPoints = target or true end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetParent() return self.parent end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel end
function Frame:SetScript(kind, callback) self.scripts[kind] = callback end
function Frame:GetScript(kind) return self.scripts[kind] end
function Frame:HookScript(kind, callback)
    local hooks = self.hooks[kind] or {}
    self.hooks[kind] = hooks
    hooks[#hooks + 1] = callback
end
function Frame:RunScript(kind, ...)
    local script = self.scripts[kind]
    if script then script(self, ...) end
    for _, callback in ipairs(self.hooks[kind] or {}) do callback(self, ...) end
end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    self:RunScript("OnShow")
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    self:RunScript("OnHide")
end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown == true end
function Frame:IsVisible() return self:IsShown() end
function Frame:EnableMouse(enabled) self.mouse = enabled end
function Frame:EnableMouseWheel(enabled) self.mouseWheel = enabled end
function Frame:SetPropagateMouseWheel(enabled) self.propagateMouseWheel = enabled end
function Frame:EnableKeyboard(enabled) self.keyboard = enabled end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:SetText(text) self.text = text end
function Frame:SetTextColor(...) self.textColor = { ... } end
function Frame:SetJustifyH(value) self.justifyH = value end
function Frame:SetColorTexture(...) self.color = { ... } end
function Frame:SetTexture(texture) self.texture = texture end
function Frame:SetActive(active) self.active = active end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:CreateTexture() return NewFrame(self) end
function Frame:CreateFontString() return NewFrame(self) end

_G = _G or _ENV
_G.CreateFrame = function(_, _, parent) return NewFrame(parent) end
_G.C_Timer = nil

local attachCalls = {}
local registeredPinControls = 0
local refreshers = {}
local previewBoxes = {}

local M = {
    activeKey = "opt_colors",
    MENU_POPUP_FRAME_LEVEL = 120,
    Theme = { colors = {
        text = { 1, 1, 1, 1 }, title = { 1, 1, 1, 1 }, muted = { 0.5, 0.5, 0.5, 1 },
        dim = { 0.4, 0.45, 0.55, 1 }, borderSoft = { 0.3, 0.4, 0.5, 1 },
    } },
    Widgets = {},
    AdvancedPage = {},
}
local T, W, AP = M.Theme, M.Widgets, M.AdvancedPage

function M.Pick(source, names)
    local values, count = {}, 0
    for name in names:gmatch("%S+") do
        count = count + 1
        values[count] = source[name]
    end
    return unpack(values, 1, count)
end
function AP.ControlMeta(...) return { ... } end
function AP.RegisterControl(widget, _, label)
    if label == "Pin Color Preview" then registeredPinControls = registeredPinControls + 1 end
    return widget
end
function T.Font(parent, _, text)
    local font = parent:CreateFontString()
    font:SetText(text)
    return font
end
function T.Button(parent, text, width, height)
    local button = NewFrame(parent)
    button:SetText(text)
    button:SetSize(width, height)
    return button
end
function T.CreateSuperellipseLayers(parent)
    local fill, edge = parent:CreateTexture(), parent:CreateTexture()
    function edge:SetVertexColor(...) self.vertexColor = { ... } end
    return fill, edge
end
function W.AttachPinnedPreview(body, box, opts)
    local record = { body = body, box = box, pageKey = opts.pageKey, pageWrapper = opts.wrapper }
    box._msuf2PinnedPreviewRecord = record
    box._msuf2PinButton = box._msuf2PinButton or T.Button(box, "Pinned", 78, 20)
    attachCalls[#attachCalls + 1] = record
    return record
end
function M.TrackRefresh(_, callback) refreshers[#refreshers + 1] = callback end
function M.SetMenuStateValue(key, value) M[key] = value end
function M.AddTooltip() end

local wrapper = NewFrame()
local section = NewFrame(wrapper)
section._msuf2Width = 900
local builder = {}
function builder:CollapsibleSection(id)
    assert(id == "colors_preview", "unexpected Color Painter section")
    return section
end

local MSUF = { MSUF2 = M }
function MSUF.MSUF_Menu2_CreateUnitPreviewBox(parent, panel, width, height)
    local box = NewFrame(parent)
    box:SetSize(width, height)
    box._msufPanel = panel
    box.canvas = NewFrame(box)
    box.layerVisibility = { body = true, guides = true, bounds = true }
    box.layerButtons = {}
    box.handles = {}
    function box:RequestRefresh() self.refreshes = (self.refreshes or 0) + 1 end
    previewBoxes[#previewBoxes + 1] = box
    return box
end

local path = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_ColorPainter.lua"
assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
local painter = assert(M.ColorPainter and M.ColorPainter.Build, "Color Painter builder missing")
local ctx = { key = "opt_colors", width = 900, wrapper = wrapper }
painter(ctx, builder, { { key = "unit", title = "Bars & Text" } })

assert(#attachCalls == 1, "initial Color Painter pin attachment was not unique")
assert(#previewBoxes == 2, "Color Painter did not create Player and Target previews")
local host = assert(attachCalls[1].box, "Color Painter preview host missing")
assert(host:IsShown(), "initial Color Painter preview host is hidden")

-- This is the state produced by M.ReleasePinnedPreviews when another Menu2
-- page is selected while the Colors page remains cached.
host._msuf2PinnedPreviewRecord = nil
host:Hide()
assert(not host:IsShown(), "release simulation did not hide the preview host")

assert(#refreshers > 0, "Color Painter page refresher missing")
for i = 1, #refreshers do refreshers[i]() end

assert(host:IsShown(), "cached Colors page did not restore its released preview host")
assert(#attachCalls == 2, "cached Colors page did not reattach pin ownership")
assert(host._msuf2PinnedPreviewRecord == attachCalls[2], "replacement pin record was not installed")
assert(registeredPinControls == 1, "pin control metadata was registered more than once")
for i = 1, #previewBoxes do
    assert(previewBoxes[i]:IsShown(), "cached Colors page did not restore unit preview " .. i)
    assert((previewBoxes[i].refreshes or 0) > 0, "restored unit preview " .. i .. " was not refreshed")
end

print("color painter lifecycle smoke: ok (cached host show + pin reattach)")
