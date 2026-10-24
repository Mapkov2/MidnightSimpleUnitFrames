local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Hints.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Fallbacks = M.Fallbacks
local shared = H._Shared
local FlatBackdrop, ThemedFont = shared.FlatBackdrop, shared.ThemedFont
local CreatePreviewPopup, PopupButton = shared.CreatePreviewPopup, shared.PopupButton
local SetShownText, RegisterPopupDismiss = shared.SetShownText, shared.RegisterPopupDismiss

local PREVIEW_DRAG_CUE_ATLAS = "newplayertutorial-drag-cursor"
local PreviewDragCueEnabled = H._HintState.DragCueEnabled
local PreviewDragCueIsNewProfile = H._HintState.IsNewProfile
local PreparePreviewMoveCueOwner = H._HintState.PrepareOwner

function H.HidePreviewMoveCue()
    local cue = H._previewMoveCue
    if not cue then return end
    local anim = cue._motionAnim
    if anim and anim.IsPlaying and anim:IsPlaying() then anim:Stop() end
    cue:Hide()
end
local function CreatePreviewMoveCue()
    if H._previewMoveCue then return H._previewMoveCue end
    local cue = PixelLayoutRegion(CreateFrame("Frame", "MSUF2PreviewMoveCue", UIParent, "BackdropTemplate"))
    cue:SetSize(252, 64)
    cue:SetFrameStrata("TOOLTIP")
    if cue.SetToplevel then cue:SetToplevel(true) end
    if cue.SetClampedToScreen then cue:SetClampedToScreen(true) end
    cue:EnableMouse(false)
    if cue.SetBackdrop then
        FlatBackdrop(cue, { 0.012, 0.020, 0.040, 0.96 }, { 0.18, 0.64, 0.88, 0.96 })
    end

    local motion = PixelLayoutRegion(CreateFrame("Frame", nil, cue))
    motion:SetSize(72, 46)
    motion:SetPoint("LEFT", cue, "LEFT", 10, 0)
    local mouse = PixelLayoutRegion(CreateFrame("Frame", nil, motion, "BackdropTemplate"))
    mouse:SetSize(24, 34)
    mouse:SetPoint("LEFT", motion, "LEFT", 1, 0)
    if mouse.SetBackdrop then
        FlatBackdrop(mouse, { 0.08, 0.12, 0.18, 0.98 }, { 0.72, 0.86, 0.98, 1 })
    end
    local split = PixelLayoutRegion(mouse:CreateTexture(nil, "ARTWORK"))
    split:SetColorTexture(0.72, 0.86, 0.98, 0.82)
    split:SetPoint("TOP", mouse, "TOP", 0, -10)
    split:SetPoint("LEFT", mouse, "LEFT", 2, 0)
    split:SetPoint("RIGHT", mouse, "RIGHT", -2, 0)
    split:SetHeight(1)
    local wheel = PixelLayoutRegion(mouse:CreateTexture(nil, "ARTWORK"))
    wheel:SetColorTexture(0.18, 0.64, 0.88, 1)
    wheel:SetSize(2, 6)
    wheel:SetPoint("TOP", mouse, "TOP", 0, -3)
    local cursor = PixelLayoutRegion(motion:CreateTexture(nil, "OVERLAY", nil, 2))
    if cursor.SetAtlas then
        cursor:SetAtlas(PREVIEW_DRAG_CUE_ATLAS, true)
    else
        cursor:SetTexture("Interface\\Cursor\\UI-Cursor-Move")
        cursor:SetSize(32, 32)
    end
    cursor:SetPoint("CENTER", mouse, "BOTTOMRIGHT", 5, 2)

    local label = PixelLayoutRegion(cue:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    label:SetPoint("LEFT", cue, "LEFT", 90, 0)
    label:SetPoint("RIGHT", cue, "RIGHT", -88, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.82, 0.94, 1, 1)

    local keys = PixelLayoutRegion(CreateFrame("Frame", nil, cue))
    keys:SetSize(70, 50)
    keys:SetPoint("RIGHT", cue, "RIGHT", -8, 0)
    local function ArrowKey(atlas, x, y)
        local key = PixelLayoutRegion(CreateFrame("Frame", nil, keys, "BackdropTemplate"))
        key:SetSize(20, 20)
        key:SetPoint("BOTTOMLEFT", keys, "BOTTOMLEFT", x, y)
        if key.SetBackdrop then
            FlatBackdrop(key, { 0.06, 0.10, 0.16, 0.98 }, { 0.46, 0.66, 0.82, 0.95 })
        end
        local arrow = PixelLayoutRegion(key:CreateTexture(nil, "ARTWORK"))
        arrow:SetPoint("CENTER")
        arrow:SetSize(12, 12)
        if arrow.SetAtlas then arrow:SetAtlas(atlas, false) end
        arrow:SetVertexColor(0.82, 0.94, 1, 1)
        return key
    end
    ArrowKey("NPE_ArrowUp", 25, 27)
    ArrowKey("NPE_ArrowLeft", 3, 5)
    ArrowKey("NPE_ArrowDown", 25, 5)
    ArrowKey("NPE_ArrowRight", 47, 5)
    cue._label, cue._keys = label, keys

    if motion.CreateAnimationGroup then
        local group = motion:CreateAnimationGroup()
        local theme = M.Theme
        if theme and theme.TrackMenuAnimationGroup then theme.TrackMenuAnimationGroup(group) end
        for i = 1, 6 do
            local move = group:CreateAnimation("Translation")
            move:SetOrder(i)
            move:SetDuration(i == 1 and 0.32 or 0.26)
            move:SetOffset(i % 2 == 1 and 20 or -20, 0)
            if move.SetSmoothing then move:SetSmoothing("IN_OUT") end
        end
        group:SetScript("OnFinished", function() cue:Hide() end)
        cue._motionAnim = group
    end
    cue:Hide()
    H._previewMoveCue = cue
    return cue
end
function H.ShowPreviewMoveCue(owner, handle)
    if not PreviewDragCueEnabled() then
        H.HidePreviewMoveCue()
        return false
    end
    if not handle or handle._locked == true or handle._msufPlaced == false then return false end
    if handle.IsShown and not handle:IsShown() then return false end
    PreparePreviewMoveCueOwner(owner)
    local newProfile = PreviewDragCueIsNewProfile()
    if newProfile then
        if owner and owner._msuf2PreviewDragCueShownForOpen == true then return false end
    elseif H._previewDragCueSessionShown == true then
        return false
    end
    local cue = CreatePreviewMoveCue()
    if not cue then return false end
    local anim = cue._motionAnim
    if anim and anim.IsPlaying and anim:IsPlaying() then anim:Stop() end
    cue:Hide()
    cue:ClearAllPoints()
    cue:SetPoint("BOTTOM", handle, "TOP", 0, 12)
    local tr = (M.Tr) or Fallbacks.Identity
    cue._label:SetText(tr("Drag to move"))
    cue._previewOwner = owner
    cue:Show()
    if anim and anim.Play then anim:Play() end
    if newProfile and owner then
        owner._msuf2PreviewDragCueShownForOpen = true
    else
        H._previewDragCueSessionShown = true
    end
    return true
end
local function PreviewControlsLines(tr)
    tr = tr or Fallbacks.Identity
    return {
        tr("Drag handles to move."),
        tr("Right-click: quick actions."),
        tr("Arrows nudge. Shift=5, Ctrl=10."),
        tr("Drag background: pan. Ctrl+wheel: zoom."),
        tr("Fit recenters."),
    }
end
function H.ShowPreviewControlsHelp(anchor, opts)
    opts = opts or {}
    local M2 = opts.M or M
    local T = opts.T or (M2.Theme)
    local W = opts.W or (M2.Widgets)
    local tr = opts.Tr or opts.TR or (M2.Tr) or Fallbacks.Identity
    local popup = H._previewControlsHelpPopup
    if not popup then
        popup = CreatePreviewPopup(M2, "MSUF2PreviewControlsHelp", 328, 188)
        popup._title = ThemedFont(popup, T, "GameFontNormalSmall", "accent", { 0.78, 0.92, 1, 1 })
        popup._title:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -12)
        popup._title:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
        popup._title:SetJustifyH("LEFT")
        popup._lines = {}
        for i = 1, 6 do
            local fs = ThemedFont(popup, T, "GameFontDisableSmall", "muted", { 0.72, 0.78, 0.90, 1 })
            fs:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -32 - ((i - 1) * 20))
            fs:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
            if fs.SetMaxLines then fs:SetMaxLines(1) end
            popup._lines[i] = fs
        end
        local close = PopupButton(W, T, popup, tr, "Got it", 84)
        close:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 12)
        close:SetScript("OnClick", function(self)
            local p = self:GetParent()
            if p then p:Hide() end
        end)
        RegisterPopupDismiss(M2, close, popup, "preview-controls-help.dismiss", "Got it",
            "Closes the Preview Controls help popup.")
        popup._close = close
        H._previewControlsHelpPopup = popup
    end
    SetShownText(popup._title, tr(opts.title or "Preview Controls"))
    -- Callers with a reduced interaction model (e.g. the color-only preview)
    -- can supply their own lines instead of the full editing help.
    local lines = opts.lines or PreviewControlsLines(tr)
    for i = 1, #(popup._lines or {}) do
        local fs = popup._lines[i]
        if fs then SetShownText(fs, lines[i] and ("- " .. lines[i]) or "") end
    end
    M2.ApplyPopupFramePriority(popup)
    popup:ClearAllPoints()
    if anchor and anchor.GetLeft then
        popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popup:Show()
    return popup
end
function H.HideTransientPopups()
    local context = H._previewHandleContextPopup
    if context and context.Hide then context:Hide() end
    local help = H._previewControlsHelpPopup
    if help and help.Hide then help:Hide() end
    H.HidePreviewMoveCue()
end
M.HideMenuPreviewPopups = H.HideTransientPopups
function H.EnsurePreviewControlsHint(box, anchor, opts)
    opts = opts or {}
    if not box then return nil end
    local M2 = opts.M or M
    local T = opts.T or (M2.Theme)
    local tr = opts.Tr or opts.TR or (M2.Tr) or Fallbacks.Identity
    local state = M2.GetPersistentMenuStateTable("previewControlsHintState")
    if state and state.seen == true then return nil end
    local parent = anchor or box.canvas or box._stage or box
    if not parent then return nil end
    local hint = box._msuf2PreviewControlsHint
    if not hint then
        local template = T and T.Template and T.Template() or "BackdropTemplate"
        hint = PixelLayoutRegion(CreateFrame("Frame", nil, parent, template))
        hint:SetSize(288, 48)
        hint:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
        if hint.SetFrameLevel and parent.GetFrameLevel then hint:SetFrameLevel((parent:GetFrameLevel() or 0) + 90) end
        if hint.SetBackdrop then
            FlatBackdrop(hint, { 0.012, 0.020, 0.040, 0.94 }, { 0.10, 0.32, 0.54, 0.92 })
        end
        hint:EnableMouse(true)
        local text = ThemedFont(hint, T, "GameFontDisableSmall", "text", { 0.86, 0.90, 0.98, 1 })
        text:SetPoint("TOPLEFT", hint, "TOPLEFT", 12, -8)
        text:SetPoint("RIGHT", hint, "RIGHT", -60, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        hint._text = text
        local close = PixelLayoutRegion(CreateFrame("Button", nil, hint, "BackdropTemplate"))
        close:SetSize(44, 24)
        close:SetPoint("RIGHT", hint, "RIGHT", -8, 0)
        close.fs = close.fs or PixelLayoutRegion(close:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
        close.fs:SetPoint("CENTER")
        close.fs:SetText(tr("OK"))
        if T and T.StyleFontString then T.StyleFontString(close.fs, (T.colors.text) or { 1, 1, 1, 1 }, 0) end
        if T then H.StylePreviewPillButton(close, T, { fontField = "fs" }) end
        close:SetScript("OnClick", function(self)
            local p = self:GetParent()
            local s = M2.GetPersistentMenuStateTable("previewControlsHintState") or state
            if s then s.seen = true end
            if p then p:Hide() end
        end)
        hint._close = close
        box._msuf2PreviewControlsHint = hint
    end
    if hint._text then T.SetTranslatedText(hint._text, tr("Drag handles to move.")) end
    hint:Show()
    return hint
end
