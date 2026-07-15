_G = _G or _ENV

local function Noop() end
local function Frame(parent)
    local f = { parent = parent, shown = true, scripts = {}, hooks = {}, width = 0, height = 0, level = 1 }
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(v) self.level = v end
    function f:GetParent() return self.parent end
    function f:SetParent(v) self.parent = v end
    function f:SetPoint(...) self.point = { ... } end
    function f:ClearAllPoints() self.point = nil end
    function f:SetAllPoints() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:SetStatusBarTexture() end
    function f:SetStatusBarColor() end
    function f:SetMinMaxValues() end
    function f:SetValue() end
    function f:SetClipsChildren() end
    function f:EnableMouse() end
    function f:EnableMouseWheel() end
    function f:EnableKeyboard() end
    function f:SetPropagateMouseWheel() end
    function f:SetPropagateKeyboardInput() end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(v) self.shown = v == true end
    function f:SetScript(kind, fn) self.scripts[kind] = fn end
    function f:GetScript(kind) return self.scripts[kind] end
    function f:HookScript(kind, fn)
        self.hooks[kind] = self.hooks[kind] or {}
        self.hooks[kind][#self.hooks[kind] + 1] = fn
    end
    function f:CreateTexture()
        local t = Frame(self)
        t.SetTexture, t.SetColorTexture, t.SetVertexColor, t.SetTexCoord, t.SetAlpha = Noop, Noop, Noop, Noop, Noop
        return t
    end
    function f:CreateFontString()
        local fs = Frame(self)
        function fs:SetText(v) self.text = v end
        function fs:GetText() return self.text end
        fs.SetTextColor, fs.SetJustifyH, fs.SetFont, fs.SetWordWrap, fs.SetMaxLines = Noop, Noop, Noop, Noop, Noop
        return fs
    end
    return f
end

_G.UIParent = Frame(nil)
_G.CreateFrame = function(_, _, parent) return Frame(parent) end
_G.C_Timer = { After = function(_, fn) fn() end }
_G.InCombatLockdown = function() return false end
_G.IsShiftKeyDown = function() return false end
_G.STANDARD_TEXT_FONT = "font"

local colors = setmetatable({
    panel = { 0.01, 0.02, 0.03, 1 }, panel2 = { 0.01, 0.02, 0.03, 1 },
    border = { 0.1, 0.2, 0.3, 1 }, borderSoft = { 0.1, 0.2, 0.3, 1 },
    accent = { 0.4, 0.7, 1, 1 }, muted = { 0.5, 0.6, 0.7, 1 }, text = { 1, 1, 1, 1 },
}, { __index = function() return { 0.5, 0.5, 0.5, 1 } end })
local T = { colors = colors }
function T.Template() return nil end
function T.Panel(parent) return Frame(parent) end
function T.Font(parent, _, text)
    local fs = parent:CreateFontString()
    fs:SetText(text or "")
    return fs
end
function T.FontSize() return 10 end
function T.StyleFontString() end
function T.ApplyBackdrop() end

local F = setmetatable({
    Noop = Noop, False = function() return false end, One = function() return 1 end,
    Empty = function() return "" end, Nil = function() return nil end,
}, { __index = function() return Noop end })
local M = { Theme = T, Fallbacks = F, GroupPreviewSpecs = {} }
function M.Tr(v) return v end
function M.PickDefaults(source, names)
    local out = {}
    for name in names:gmatch("%S+") do out[#out + 1] = source[name] or {} end
    return unpack(out)
end
M.AddTooltip = function(widget) return widget end
M.GroupPreviewRender = { Install = function(box)
    function box:Refresh(reason) self.lastRefreshReason = reason end
end }

local MSUF = { MSUF2 = M, ExportPublic = function(name, value) _G[name] = value return value end }
assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))("MidnightSimpleUnitFrames", MSUF)
local H = assert(M.PreviewHelpers)
H.BuildZoomBar = function(box)
    box._zoomBar = Frame(box)
    box._zoomOutButton, box._zoomFitButton, box._zoomOneButton = Frame(box), Frame(box), Frame(box)
    box._zoomInButton, box._zoomHelpButton = Frame(box), Frame(box)
end
H.BuildZoomCommand = function() return {} end
H.EnsurePreviewControlsHint = function() return nil end

assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local parent = Frame(UIParent)
local box = assert(M.GroupPreview.CreateNative(parent, { width = 720, key = "group" }))
assert(#box._layerButtons == 11, "group layer buttons missing")
local button = box._layerButtons[1]
assert(M.gfPreviewLayerVisible.guides == true, "guides did not start enabled")
assert(type(button.scripts.OnClick) == "function", "group layer click handler missing")
button.scripts.OnClick(button)
assert(M.gfPreviewLayerVisible.guides == false, "group layer click did not disable guides")
button.scripts.OnClick(button)
assert(M.gfPreviewLayerVisible.guides == true, "group layer click did not re-enable guides")
print("group preview layer click smoke: ok")
