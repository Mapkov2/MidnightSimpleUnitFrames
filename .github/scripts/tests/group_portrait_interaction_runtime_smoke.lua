_G = _G or _ENV

local function Noop() end
local unpack = unpack or table.unpack

local function Frame(parent)
    local frame = {
        parent = parent,
        shown = true,
        scripts = {},
        hooks = {},
        width = 0,
        height = 0,
        level = 1,
        alpha = 1,
    }
    function frame:SetParent(value) self.parent = value end
    function frame:GetParent() return self.parent end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:GetPoint() return unpack(self.point or {}) end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetAllPoints(target) self.allPoints = target or true end
    function frame:SetFrameLevel(value) self.level = value end
    function frame:GetFrameLevel() return self.level end
    function frame:GetEffectiveScale() return 1 end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return self.alpha end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(value) self.shown = value == true end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    function frame:GetScript(kind) return self.scripts[kind] end
    function frame:HookScript(kind, callback)
        self.hooks[kind] = self.hooks[kind] or {}
        self.hooks[kind][#self.hooks[kind] + 1] = callback
    end
    function frame:EnableMouse(value) self.mouseEnabled = value ~= false end
    function frame:EnableMouseWheel(value) self.mouseWheelEnabled = value ~= false end
    function frame:EnableKeyboard(value) self.keyboardEnabled = value ~= false end
    function frame:SetMouseClickEnabled(value) self.mouseClickEnabled = value == true end
    function frame:SetMouseMotionEnabled(value) self.mouseMotionEnabled = value == true end
    function frame:SetPropagateMouseWheel() end
    function frame:SetPropagateKeyboardInput() end
    function frame:RegisterForClicks(...) self.registeredClicks = { ... } end
    function frame:RegisterForDrag(...) self.registeredDrag = { ... } end
    function frame:SetMovable(value) self.movable = value == true end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:SetHitRectInsets(...) self.hitRectInsets = { ... } end
    function frame:SetTexture(value) self.texture = value end
    function frame:SetColorTexture(...) self.colorTexture = { ... } end
    function frame:SetVertexColor(...) self.vertexColor = { ... } end
    function frame:SetTexCoord(...) self.texCoord = { ... } end
    function frame:AddMaskTexture(mask) self.maskTexture = mask end
    function frame:SetBlendMode() end
    function frame:SetDesaturated() end
    function frame:CreateTexture() return Frame(self) end
    function frame:CreateMaskTexture() return Frame(self) end
    function frame:CreateFontString()
        local fontString = Frame(self)
        function fontString:SetText(value) self.text = value end
        function fontString:GetText() return self.text end
        fontString.SetTextColor = Noop
        fontString.SetJustifyH = Noop
        fontString.SetFont = Noop
        fontString.SetWordWrap = Noop
        fontString.SetMaxLines = Noop
        return fontString
    end
    return frame
end

local cursorX, cursorY = 100, 100
local mouseDown = true
_G.UIParent = Frame(nil)
_G.CreateFrame = function(_, _, parent) return Frame(parent) end
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.IsMouseButtonDown = function(button) return button == "LeftButton" and mouseDown end
_G.IsControlKeyDown = function() return false end
_G.InCombatLockdown = function() return false end
_G.SetPortraitTexture = function(texture) texture:SetTexture("portrait") end
_G.STANDARD_TEXT_FONT = "font"

local F = {
    Identity = function(value) return value end,
    Round = function(value)
        value = tonumber(value) or 0
        return value >= 0 and math.floor(value + 0.5) or -math.floor(-value + 0.5)
    end,
    Center = function() return "CENTER" end,
    ZeroPair = function() return 0, 0 end,
    Nil = function() return nil end,
    Noop = Noop,
    Status = function() return "Status" end,
    False = function() return false end,
}
local T = {}
function T.Template() return nil end
function T.Font(parent, _, text)
    local fontString = parent:CreateFontString()
    fontString:SetText(text)
    return fontString
end
function T.FontSize() return 10 end

local M = { Theme = T, Fallbacks = F, PreviewHelpers = {} }
function M.PickFallbacks(source, fallbacks, names)
    local values = {}
    local count = 0
    for name in names:gmatch("%S+") do
        count = count + 1
        values[count] = source[name] or fallbacks[name]
    end
    return unpack(values, 1, count)
end
local MSUF = {
    MSUF2 = M,
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local conf = { portraitMode = "LEFT", portraitOffsetX = 0, portraitOffsetY = 0 }
local stage = Frame(UIParent)
stage:SetSize(800, 400)
local mock = Frame(stage)
mock:SetSize(220, 50)
mock._previewScale = 1
local box = Frame(UIParent)
box._stage = stage
box._mock = mock
function box:SetFocus() self.focused = true end
function box:RequestRefresh(reason) self.refreshReason = reason end

local H = {
    CurrentScope = function() return "party" end,
    Conf = function() return conf end,
    StatusSpecs = function() return {} end,
    TextLabel = function(kind, slot) return tostring(kind) .. ":" .. tostring(slot or "group") end,
}
local openedSection
local handleBundle = assert(M.GroupPreviewHandles.Install(box, {
    M = M,
    MSUF = MSUF,
    T = T,
    H = H,
    Round = F.Round,
    ResolveAnchor = F.Center,
    PointOffset = F.ZeroPair,
    HandleOffset = F.ZeroPair,
    OffsetToConfig = F.Round,
    CurrentStatusSpec = F.Nil,
    CurrentSpellConfig = F.Nil,
    CurrentSpellPlaced = F.Nil,
    HandleText = function(handle) return handle and handle._previewText or "Handle" end,
    HandleOffsets = F.Nil,
    UpdateHint = Noop,
    RefreshHandleSelection = Noop,
    StatusLabel = F.Status,
    StartPan = F.False,
    StopPan = Noop,
    ZoomWheel = Noop,
    OpenSection = function(section) openedSection = section end,
}))
local portraitHandle = assert(handleBundle.portraitHandle, "portrait handle missing")

M.GroupPreviewRender.Install(box, {}, {
    M = M,
    MSUF = MSUF,
    T = T,
    mock = mock,
    portraitHandle = portraitHandle,
    statusHandles = {},
    statusSpecs = {},
})
assert(box._msufGFRenderState and box._msufGFRenderState.portraitHandle == portraitHandle,
    "Render.Install dropped the portrait handle before the real refresh path")

local portrait = {
    enabled = true,
    render = "2D",
    shape = "SQUARE",
    width = 36,
    height = 36,
    x = 0,
    y = 0,
    placement = "ATTACHED",
    side = "LEFT",
    levelOffset = 7,
    alpha = 1,
    border = { style = "NONE", thickness = 2 },
    bg = { enabled = false },
}
M.GroupPreviewRender.PaintGroupPreviewPortrait({
    runtimeSpec = { portrait = portrait },
    kind = "party",
    mock = mock,
    box = box,
    previewScale = 1,
    layerAvailable = { portrait = true },
    layerVisible = { portrait = true },
    S = {
        portraitHandle = box._msufGFRenderState.portraitHandle,
        ScaleValue = function(value) return tonumber(value) or 0 end,
        GF_PREVIEW_CLASSES = { "MAGE" },
        CurrentSpellTexture = F.Nil,
        ClassColor = function() return 0.2, 0.5, 1 end,
    },
    liveData = { class = "MAGE" },
})

assert(mock._msufGroupPortrait == portraitHandle,
    "visible portrait must be the interactive Button, not an overlay frame")
assert(portraitHandle:GetParent() == stage, "portrait Button must live on the preview stage")
assert(portraitHandle.mouseEnabled == true, "portrait Button mouse input is disabled")
assert(portraitHandle.mouseClickEnabled == true, "portrait Button click input is disabled")
assert(portraitHandle.mouseMotionEnabled == true, "portrait Button hover input is disabled")
assert(portraitHandle.bg and portraitHandle.tex and portraitHandle.border,
    "portrait artwork is not owned by the interactive Button")
assert(portraitHandle.border.mouseEnabled == false, "portrait border can intercept the Button")
for _, scriptName in ipairs({
    "OnEnter", "OnLeave", "OnClick", "OnDoubleClick",
    "OnMouseDown", "OnMouseUp", "OnDragStart", "OnDragStop",
}) do
    assert(type(portraitHandle:GetScript(scriptName)) == "function",
        "portrait interaction script missing: " .. scriptName)
end

portraitHandle:GetScript("OnEnter")(portraitHandle)
assert(portraitHandle._hovering == true, "portrait hover did not reach its Button")
box._selectedHandle = nil
portraitHandle:GetScript("OnClick")(portraitHandle, "LeftButton")
assert(box._selectedHandle == portraitHandle, "portrait click did not select the layer")
portraitHandle:GetScript("OnDoubleClick")(portraitHandle, "LeftButton")
assert(openedSection == "portrait", "portrait double-click did not open Portrait settings")
portraitHandle:GetScript("OnMouseDown")(portraitHandle, "LeftButton")
assert(box._selectedHandle == portraitHandle, "portrait mouse-down did not select the layer")
assert(box._dragFrame._handle == portraitHandle and portraitHandle._dragging == true,
    "portrait mouse-down did not start drag")

cursorX, cursorY = 112, 95
box._dragFrame:GetScript("OnUpdate")(box._dragFrame)
assert(portraitHandle._lastDragX == 12 and portraitHandle._lastDragY == -5,
    "portrait drag did not track cursor movement")
mouseDown = false
box._dragFrame:GetScript("OnMouseUp")(box._dragFrame, "LeftButton")
assert(conf.portraitOffsetX == 12 and conf.portraitOffsetY == -5,
    "portrait drag did not persist Party portrait X/Y")
assert(portraitHandle._dragging == nil and box._dragFrame._handle == nil,
    "portrait drag did not release cleanly")

print("PASS Group portrait runtime interaction: hover, click, settings, drag, release, and persistence")
