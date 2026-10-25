local addonName, MSUF = ...
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Rendering.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2
local H = M.PreviewHelpers

-- Preview popups and bounds drawing primitives.
-- These helpers paint options scenes without coupling pages to live frames.
local IsSecretValue = issecretvalue
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
-- The MSUF profile tables arrive with the saved variables and are replaced on a
-- profile switch, so every use reads MSUF_DB again, inline (preview ticks and
-- drag steps read them per segment and per step).
-- One-pixel flat backdrop on a BackdropTemplate frame; the colors are optional.
local function FlatBackdrop(frame, bg, border, texture)
    texture = texture or WHITE8X8
    PixelLayoutRegion(frame, "SetBackdrop", { bgFile = texture, edgeFile = texture, edgeSize = 1 })
    if bg then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4]) end
end
-- A themed font string when the theme builds them, else a plain overlay one. The color is
-- the theme's colorKey entry (when given) or the fallback.
local function ThemedFont(parent, T, template, colorKey, fallbackColor)
    local font
    if T and T.Font then
        font = T.Font(parent, template, "", (colorKey and T.colors[colorKey]) or fallbackColor)
    end
    return font or PixelLayoutRegion(parent:CreateFontString(nil, "OVERLAY", template))
end
-- A popup panel from the theme (or a flat backdrop frame) in the dialog strata.
local function CreatePreviewPopup(M2, name, width, height)
    local popup
    popup = M2.CreateMenuPopupPanel(UIParent, { name = name, glass = "popup" })
    popup:SetSize(width, height)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    return popup
end
-- A 24 px popup button: the widget kit's top button, else the theme's, else a bare backdrop button.
local function PopupButton(W, T, popup, tr, label, width)
    local btn = W and W.TopButton and W.TopButton(popup, label, width, 24) or (T and T.Button and T.Button(popup, label, width, 24))
        or PixelLayoutRegion(CreateFrame("Button", nil, popup, "BackdropTemplate"))
    if not btn.GetText then btn:SetText(tr(label)) end
    return btn
end
-- A popup button that only closes the popup it belongs to, registered with the menu chrome.
local function RegisterPopupDismiss(M2, button, popup, controlId, label, help)
    M2.RegisterMenuChromeControl(button, controlId, label, "action", {
        historyMode = "none",
        help = help,
        command = {
            kind = "button",
            historyMode = "none",
            canExecute = function() return popup.IsShown and popup:IsShown() end,
            set = function()
                if not (popup.IsShown and popup:IsShown()) then return false end
                popup:Hide()
                return true
            end,
        },
    })
end
-- Text translated already, or composed from translated parts, goes through the
-- theme's raw setter so a theme font does not look it up a second time.
local function SetShownText(fs, text)
    return M.Theme.SetTranslatedText(fs, text)
end
--- Mirrors the controller's effective Player Mana ownership in both previews.
--- Native API fallback exists only for isolated/early preview loads.
function H.PlayerManaSourceActive(player)
    if not (player and player.playerPowerSource == "MANA") then return false end
    local ownership = MSUF.ClassPowerOwnership
    local published = ownership and ownership.playerManaOverride
    if type(published) == "boolean" then return published end
    local vehicle = UnitHasVehicleUI and UnitHasVehicleUI("player")
    if IsSecretValue(vehicle) or vehicle == true then return false end
    local hasPowerType = UnitHasPowerType
    if type(hasPowerType) ~= "function" then return true end
    local manaType = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
    local hasMana = hasPowerType("player", manaType)
    return not IsSecretValue(hasMana) and hasMana == true
end

local EDGE_ANCHORS = {
    top = { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    left = { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
    right = { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}
function H.SnapOff(region)
    if region and region.SetSnapToPixelGrid then
        PixelLayoutRegion(region, true)
        region:SetSnapToPixelGrid(false)
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
end
local EDGE_LINE_KEYS = { "top", "bottom", "left", "right" }
function H.SetEdgeLinesShown(frame, shown, opts)
    local lines = frame and frame[(opts and opts.linesKey) or "_lines"]
    if type(lines) ~= "table" then return end
    local keys = (opts and opts.keys) or EDGE_LINE_KEYS
    for i = 1, #keys do
        local line = lines[keys[i]]
        if line then
            if shown then line:Show() else line:Hide() end
        end
    end
end
-- Stretches one border line along its side of the frame, `thickness` pixels thick.
local function PlaceEdgeLine(line, frame, side, thickness)
    local spec = EDGE_ANCHORS[side]
    line:ClearAllPoints()
    line:SetPoint(spec[1], frame, spec[1], 0, 0)
    line:SetPoint(spec[2], frame, spec[2], 0, 0)
    line[spec[3]](line, thickness)
end
function H.LayoutEdgeLines(frame, edge, opts)
    if not (frame and frame.CreateTexture) then return false end
    opts = opts or {}
    edge = H.ClampEdgeSize(edge, 1, opts.maxEdgeSize or 30)
    if edge <= 0 then
        H.SetEdgeLinesShown(frame, false, opts)
        return false
    end
    local linesKey = opts.linesKey or "_lines"
    local keys = opts.keys or EDGE_LINE_KEYS
    frame[linesKey] = frame[linesKey] or {}
    local lines = frame[linesKey]
    local texture = opts.texture or "Interface\\Buttons\\WHITE8X8"
    local snap = opts.snapOff or H.SnapOff
    for i = 1, #keys do
        local key = keys[i]
        if not lines[key] then
            lines[key] = PixelLayoutRegion(frame:CreateTexture(nil, opts.layer or "OVERLAY"))
            snap(lines[key])
        end
        lines[key]:SetTexture(texture)
    end
    local r, g, b, a = 0, 0, 0, 1
    if type(opts.color) == "function" then r, g, b, a = opts.color(frame) end
    for i = 1, #keys do
        local key, line = keys[i], lines[keys[i]]
        line:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
        PlaceEdgeLine(line, frame, key, edge)
    end
    H.SetEdgeLinesShown(frame, true, opts)
    return true
end
H.ClampEdgeSize = MSUF.Require("MSUF_ClampRoundedEdgeSize", FILE)
-- Shared ClassPower preview contract. BAR mode only needs its two boundary
-- segments clipped; every interior separator remains square and every non-BAR
-- shape bypasses this helper entirely.
local function PreviewBackgroundColorMode(health, general)
    return MSUF.UF.Config.ResolveBarBackgroundColorMode(general, health)
end
H.HealthBackgroundColorMode = PreviewBackgroundColorMode

local function ExactPreviewDelta(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
H.ExactPreviewDelta = ExactPreviewDelta

local function ReadPreviewBarsBool(key, default)
    local db = MSUF_DB
    local bars = db and db.bars
    local value = bars and bars[key]
    if value == nil then return default and true or false end
    return value and true or false
end
H.ReadPreviewBarsBool = ReadPreviewBarsBool

local UNIT_PREVIEW_ENGLISH = MSUF.LOCALE == "enUS"
function H.TranslateUnitPreview(value)
    if type(value) ~= "string" or UNIT_PREVIEW_ENGLISH then return value end
    return MSUF.L[value] or value
end


-- Shared bindings are captured once by the following preview modules.
H._Shared = {
    FlatBackdrop = FlatBackdrop, ThemedFont = ThemedFont,
    CreatePreviewPopup = CreatePreviewPopup, PopupButton = PopupButton,
    RegisterPopupDismiss = RegisterPopupDismiss, SetShownText = SetShownText,
    EDGE_ANCHORS = EDGE_ANCHORS,
}
