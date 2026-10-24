local addonName, MSUF = ...
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Rendering.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2
local H = M.PreviewHelpers

-- Preview media, masks, edge stacks and shared drawing primitives.
-- These helpers paint options scenes without coupling pages to live frames.
local floor = math.floor
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
local ROUNDED_MEDIA_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"

local ROUNDED_SLICE_MARGIN = 9.5
local ROUNDED_MASK_PATHS, ROUNDED_EDGE_PATHS = {}, {}
for i = 1, 5 do
    ROUNDED_MASK_PATHS[i] = ROUNDED_MEDIA_ROOT .. "rounded_clean_mask_s" .. i .. ".png"
    ROUNDED_EDGE_PATHS[i] = ROUNDED_MEDIA_ROOT .. "rounded_clean_edge_s" .. i .. ".png"
end
local STRETCHED_SLICE_MODE = Enum and Enum.UITextureSliceMode
    and Enum.UITextureSliceMode.Stretched
-- Full Unit/Group previews use the exact clean media family selected by the
-- live rounded runtime. Resolving this only while a preview is repainted keeps
-- slider feedback accurate without putting any work on gameplay paths.
function H.ResolveRoundedMedia()
    local db = MSUF_DB
    local bars = db and db.bars
    local strength = floor((tonumber(bars and bars.roundedCornerStrength) or 3) + 0.5)
    if strength < 1 then strength = 1 elseif strength > 5 then strength = 5 end
    return ROUNDED_MASK_PATHS[strength], ROUNDED_EDGE_PATHS[strength], strength
end
function H.ResolveFrameBarMedia(style, scope, conf)
    if style == "SLANTED" then
        return MSUF.RoundedSurface.ResolveSlantedMedia(scope, conf)
    end
    return H.ResolveRoundedMedia()
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

function H.ApplyRoundedMediaSlice(region, strength)
    if not region then return end
    strength = tonumber(strength) or 3
    if region._msufPreviewRoundedSliceStrength == strength then return end
    region._msufPreviewRoundedSliceStrength = strength
    if type(region.SetTextureSliceMargins) == "function" then
        local margin = strength == 0 and 0 or ROUNDED_SLICE_MARGIN
        region:SetTextureSliceMargins(margin, margin, margin, margin)
    end
    if STRETCHED_SLICE_MODE ~= nil and type(region.SetTextureSliceMode) == "function" then
        region:SetTextureSliceMode(STRETCHED_SLICE_MODE)
    end
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
function H.MaskOwner(mock, tex, anchor)
    local owner = tex and tex.GetParent and tex:GetParent() or nil
    if owner and owner.CreateMaskTexture then return owner end
    if anchor and anchor.CreateMaskTexture then return anchor end
    return mock
end
function H.EnsureRoundedMask(mock, key, anchor, tex, maskStoreKey, maskTexture, snapOff)
    if not (mock and anchor) then return nil end
    local owner = H.MaskOwner(mock, tex, anchor)
    if not (owner and owner.CreateMaskTexture) then return nil end
    maskStoreKey = maskStoreKey or "_msufPreviewRoundedMasks"
    mock[maskStoreKey] = mock[maskStoreKey] or {}
    local store = mock[maskStoreKey]
    local bucket = store[key]
    if type(bucket) ~= "table" or bucket.SetTexture then
        bucket = {}
        store[key] = bucket
    end
    local ownerKey = tex or owner
    local mask = bucket[ownerKey]
    if not mask then
        mask = owner:CreateMaskTexture(nil, "ARTWORK")
        local snap = snapOff or H.SnapOff
        snap(mask)
        bucket[ownerKey] = mask
    end
    if mask._msufPreviewRoundedAnchor ~= anchor or mask._msufPreviewRoundedTexture ~= maskTexture then
        mask._msufPreviewRoundedAnchor = anchor
        mask._msufPreviewRoundedTexture = maskTexture
        mask:ClearAllPoints()
        mask:SetTexture(maskTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(anchor)
    end
    H.ApplyRoundedMediaSlice(mask, mock._msufPreviewRoundedMediaStrength)
    return mask
end
function H.SetMask(mock, tex, mask, maskedStoreKey)
    if not (mock and tex and tex.AddMaskTexture) then return end
    maskedStoreKey = maskedStoreKey or "_msufPreviewRoundedMasked"
    mock[maskedStoreKey] = mock[maskedStoreKey] or {}
    local store = mock[maskedStoreKey]
    local old = store[tex]
    if old == mask then return end
    if old and tex.RemoveMaskTexture then tex:RemoveMaskTexture(old) end
    store[tex] = nil
    if mask then
        tex:AddMaskTexture(mask)
        store[tex] = mask
    end
end
function H.ClearMasks(mock, maskedStoreKey)
    local store = mock and mock[maskedStoreKey or "_msufPreviewRoundedMasked"]
    if store then
        for tex, mask in pairs(store) do
            if tex and tex.RemoveMaskTexture and mask then tex:RemoveMaskTexture(mask) end
        end
    end
    if mock then mock[maskedStoreKey or "_msufPreviewRoundedMasked"] = nil end
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
function H.EnsureRoundedVisuals(mock, opts)
    if not (mock and mock.CreateTexture) then return false end
    opts = opts or {}
    local bgKey = opts.bgKey or "roundedBg"
    local edgeKey = opts.edgeKey or "roundedEdge"
    local snap = opts.snapOff or H.SnapOff
    if not mock[bgKey] then
        mock[bgKey] = PixelLayoutRegion(mock:CreateTexture(nil, opts.bgLayer or "BACKGROUND", nil, opts.bgSubLevel))
        mock[bgKey]:SetTexture(opts.whiteTexture or "Interface\\Buttons\\WHITE8X8")
        snap(mock[bgKey])
    end
    if not mock[edgeKey] then
        mock[edgeKey] = PixelLayoutRegion(mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel))
        snap(mock[edgeKey])
    end
    if mock[edgeKey]._msufPreviewRoundedEdgeTexture ~= opts.edgeTexture then
        mock[edgeKey]._msufPreviewRoundedEdgeTexture = opts.edgeTexture
        mock[edgeKey]:SetTexture(opts.edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    H.ApplyRoundedMediaSlice(mock[edgeKey], opts.mediaStrength)
    return true
end
function H.ForEachRoundedEdge(mock, opts, fn)
    if not (mock and type(fn) == "function") then return end
    opts = opts or {}
    local edge = mock[opts.edgeKey or "roundedEdge"]
    if edge then fn(edge, 1) end
    local stack = mock[opts.stackKey or "_msufPreviewRoundedEdgeStack"]
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        if stack[i] then fn(stack[i], i) end
    end
end
-- A True Outline or Texture outline style replaces the solid stack with the
-- core's styled rings (MSUF.RoundedSurface), drawn on the same mock so the
-- preview follows its rounded or slanted shape like the live frame. Owners
-- opt in with opts.outlineStyle(mock), returning the compiled border spec.
local function PreviewStyledKey(opts)
    return opts.styledKey or ((opts.stackKey or "_msufPreviewRoundedEdgeStack") .. "Styled")
end
local function ForEachPreviewStyledRing(mock, opts, fn)
    local surface = MSUF.RoundedSurface
    if surface and surface.ForEachStyledEdgeRing then surface.ForEachStyledEdgeRing(mock, PreviewStyledKey(opts), fn) end
end
function H.SetRoundedEdgeStackShown(mock, shown, opts)
    opts = opts or {}
    local styled = mock and mock[PreviewStyledKey(opts) .. "On"] == true
    local count = shown and not styled and H.ClampEdgeSize(mock and mock[opts.countKey or "_msufPreviewRoundedEdgeCount"], 1, opts.maxEdgeSize or 8) or 0
    H.ForEachRoundedEdge(mock, opts, function(edge, i)
        if edge.SetShown then
            edge:SetShown(i <= count)
        elseif i <= count then
            edge:Show()
        else
            edge:Hide()
        end
    end)
    if styled then
        shown = shown and true or false
        ForEachPreviewStyledRing(mock, opts, function(ring) ring:SetShown(shown) end)
    end
end
local function ApplyPreviewStyledRings(mock, count, opts, anchor, r, g, b, a)
    local styledKey = PreviewStyledKey(opts)
    local style = opts.outlineStyle and opts.outlineStyle(mock) or nil
    local surface = MSUF.RoundedSurface
    if count > 0 and type(style) == "table" and style.textureMode and surface and surface.ApplyStyledEdgeRings
        and surface.ApplyStyledEdgeRings(mock, mock, anchor, styledKey, count, style.textureMode, style.texture,
            style.textureKey, opts.edgeTexture, opts.edgeLayer or "OVERLAY", opts.edgeSubLevel, r, g, b, a) then
        mock[styledKey .. "On"] = true
        return true
    end
    mock[styledKey .. "On"] = nil
    if surface and surface.HideStyledEdgeRings then surface.HideStyledEdgeRings(mock, styledKey) end
    return false
end
function H.ApplyRoundedEdgeStack(mock, edgeSize, opts)
    if not mock then return false end
    opts = opts or {}
    local count = H.ClampEdgeSize(edgeSize, 0, opts.maxEdgeSize or 8)
    local stackKey = opts.stackKey or "_msufPreviewRoundedEdgeStack"
    local countKey = opts.countKey or "_msufPreviewRoundedEdgeCount"
    local edgeKey = opts.edgeKey or "roundedEdge"
    mock[countKey] = count
    local anchor = type(opts.anchor) == "function" and opts.anchor(mock) or opts.anchor or mock
    local r, g, b, a
    if type(opts.baseEdgeColor) == "function" then
        r, g, b, a = opts.baseEdgeColor(mock)
    else
        r, g, b, a = H.BaseEdgeColor()
    end
    if ApplyPreviewStyledRings(mock, count, opts, anchor, r, g, b, a) then
        H.SetRoundedEdgeStackShown(mock, true, opts)
        return true
    end
    if count <= 0 then
        H.SetRoundedEdgeStackShown(mock, false, opts)
        return false
    end
    mock[stackKey] = mock[stackKey] or {}
    mock[stackKey][1] = mock[edgeKey]
    local snap = opts.snapOff or H.SnapOff
    local edgeTexture = opts.edgeTexture
    for i = 1, count do
        local edge = (i == 1) and mock[edgeKey] or mock[stackKey][i]
        if not edge then
            edge = PixelLayoutRegion(mock:CreateTexture(nil, opts.edgeLayer or "OVERLAY", nil, opts.edgeSubLevel))
            snap(edge)
            mock[stackKey][i] = edge
        end
        if edge._msufPreviewRoundedEdgeTexture ~= edgeTexture then
            edge._msufPreviewRoundedEdgeTexture = edgeTexture
            edge:SetTexture(edgeTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        H.ApplyRoundedMediaSlice(edge, opts.mediaStrength)
        if edge._msufPreviewRoundedAnchor ~= anchor or edge._msufPreviewRoundedPad ~= i then
            edge._msufPreviewRoundedAnchor = anchor
            edge._msufPreviewRoundedPad = i
            edge:ClearAllPoints()
            edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -i, i)
            edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", i, -i)
        end
        if edge._msufPreviewRoundedR ~= r or edge._msufPreviewRoundedG ~= g
            or edge._msufPreviewRoundedB ~= b or edge._msufPreviewRoundedA ~= a then
            edge._msufPreviewRoundedR = r
            edge._msufPreviewRoundedG = g
            edge._msufPreviewRoundedB = b
            edge._msufPreviewRoundedA = a
            edge:SetVertexColor(r, g, b, a)
        end
        edge:Show()
    end
    H.SetRoundedEdgeStackShown(mock, true, opts)
    return true
end
local GetBarOutlineColor = MSUF.Require("MSUF_GetBarOutlineColor", FILE)
function H.BaseEdgeColor()
    local r, g, b = GetBarOutlineColor()
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, 1 end
    local db = MSUF_DB
    local gen = db and db.general
    if gen then
        return tonumber(gen.barOutlineColorR) or 0,
               tonumber(gen.barOutlineColorG) or 0,
               tonumber(gen.barOutlineColorB) or 0,
               1
    end
    return 0, 0, 0, 1
end

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
