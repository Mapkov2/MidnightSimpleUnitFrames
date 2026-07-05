local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme
local W = M.Widgets
local GroupPreview = M.GroupPreview or {}
M.GroupPreview = GroupPreview

-- Menu2 Group preview page section.
-- Hosts the group preview box, explanatory note, and preview refresh hooks. The actual mock
-- renderer lives in Preview/MSUF_Menu2_GroupPreview_Native.lua.
local floor = math.floor
local max = math.max
local min = math.min
local GF_PREVIEW_NOTE = "Preview updates live here. Enter MSUF Edit Mode to drag the group container. Buff and Debuff handles can be adjusted in Group Frames > Auras."
local Tr = M.TranslateText or M.Tr or function(text) return text end
local function SetPreviewHeaderStatus(body)
    local gp = M.GroupPage or {}
    local fn = gp.SetSectionHeaderStatus
    if type(fn) == "function" then fn(body, nil) end
end
local function GFPreviewIntroMetrics(width)
    local maxContentW = tonumber(M.formContentMaxWidth) or 980
    local contentW = min(maxContentW, max(320, tonumber(width) or 720))
    local translated = Tr(GF_PREVIEW_NOTE)
    local noteW = max(220, contentW - 28)
    local charsPerLine = max(42, floor(noteW / 5.6))
    local lines = max(1, floor(((#tostring(translated or "") + charsPerLine - 1) / charsPerLine)))
    lines = min(lines, 4)
    local noteTop = 38
    local noteLineH = 14
    local noteGap = 10
    local boxY = -(noteTop + (lines * noteLineH) + noteGap)
    local contentH = max(362, -boxY + 300 + 14)
    return contentH, boxY
end
local function IsCurrentPreviewBox(box)
    if not (box and box.Refresh) then return false end
    if box._msufGFNativePreviewDisposed then return false end
    local key = box._msufGFNativePreviewPageKey
    local wrapper = box._msufGFNativePreviewWrapper
    if key and wrapper and M.cache then
        local entry = M.cache[key]
        return entry and entry.wrapper == wrapper
    end
    return box.GetParent and box:GetParent() ~= nil
end
local function RequestPreviewRefresh(box, reason)
    if not (box and box.Refresh) then return end
    if box.IsVisible and not box:IsVisible() then return end
    if box.RequestRefresh then
        box:RequestRefresh(reason or "GROUP_PREVIEW_PAGE")
    elseif box.IsShown and box:IsShown() then
        box:Refresh()
    end
end
local function RegisterNativePreview(box, ctx)
    if not box then return end
    M._gfNativePreviews = M._gfNativePreviews or {}
    box._msufGFNativePreviewPageKey = ctx and ctx.key
    box._msufGFNativePreviewWrapper = ctx and ctx.wrapper
    M._gfNativePreviews[#M._gfNativePreviews + 1] = box
end
M._gfNativePreviews = M._gfNativePreviews or {}
function M.ReleaseGFNativePreviews(reason, keepKey)
    local previews = M._gfNativePreviews
    if not previews then return end
    for i = 1, #previews do
        local box = previews[i]
        if box and (not keepKey or box._msufGFNativePreviewPageKey ~= keepKey) then
            local record = box._msuf2PinnedPreviewRecord
            if record and type(record.restore) == "function" then record.restore() end
            if box.ReleaseRuntimePreview then box:ReleaseRuntimePreview() end
            if box.Hide then box:Hide() end
        end
    end
end
function M.RefreshGFNativePreviews(reason)
    local previews = M._gfNativePreviews
    if not previews then return end
    local writeIndex = 1
    for readIndex = 1, #previews do
        local box = previews[readIndex]
        if IsCurrentPreviewBox(box) then
            previews[writeIndex] = box
            writeIndex = writeIndex + 1
            if (not box.IsVisible or box:IsVisible()) and box.IsShown and box:IsShown() then RequestPreviewRefresh(box, reason or "GROUP_PREVIEW_REFRESH_ALL") end
        elseif box and box.ReleaseRuntimePreview then
            box:ReleaseRuntimePreview()
        end
    end
    for i = writeIndex, #previews do
        previews[i] = nil
    end
end
local function CreateNativeGFPreview(parent, ctx)
    local create = GroupPreview.CreateNative
    if type(create) == "function" then return create(parent, ctx, GroupPreview.OpenSection) end
    return nil
end
local function AddGFPreview(ctx, builder)
    if not (builder and builder.CollapsibleSection and W and T) then return end
    local sectionH, boxY = GFPreviewIntroMetrics(builder and builder.width or ctx and ctx.width)
    local body = builder:CollapsibleSection("gf_preview_native", "Hide Preview", sectionH, true)
    if W.SetCollapsibleToggleText then W.SetCollapsibleToggleText(body, "Hide Preview", "Show Preview") end
    W.Text(body, GF_PREVIEW_NOTE, 14, -38, (body._msuf2Width or 720) - 28, T.colors.muted)
    local box
    local rendererMissing
    local missingText
    local function PreviewHostShown()
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if body and body.IsShown and not body:IsShown() then return false end
        if body and body.IsVisible and not body:IsVisible() then return false end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return false end
        return true
    end
    local function EnsurePreview()
        if box then
            box._msufGFPreviewHostShown = PreviewHostShown
            if not PreviewHostShown() then return nil end
            if box.Show then box:Show() end
            return box
        end
        if not PreviewHostShown() then return nil end
        box = CreateNativeGFPreview(body, ctx)
        if not box then
            if not rendererMissing then
                missingText = W.Text(body, "Group preview renderer is unavailable.", 14, boxY, (body._msuf2Width or 720) - 28, T.colors.muted)
                rendererMissing = true
            end
            return nil
        end
        if missingText and missingText.Hide then missingText:Hide() end
        box._msufGFPreviewHostShown = PreviewHostShown
        box:SetPoint("TOPLEFT", body, "TOPLEFT", 14, boxY)
        RegisterNativePreview(box, ctx)
        box:Show()
        if W.AttachPinnedPreview then
            W.AttachPinnedPreview(body, box, {
                stateKey = "groupFramePreview",
                title = box._title,
                hint = box._hint,
                left = 14,
                right = 14,
                top = -8,
                pageKey = ctx and ctx.key,
                wrapper = ctx and ctx.wrapper,
                restoreParent = body,
                restorePoint = { "TOPLEFT", body, "TOPLEFT", 14, boxY },
                restoreWidth = box.GetWidth and box:GetWidth(),
                restoreHeight = box.GetHeight and box:GetHeight(),
            })
        end
        return box
    end
    local function RefreshThisPreview()
        SetPreviewHeaderStatus(body)
        local preview = EnsurePreview()
        if preview and preview.IsShown and preview:IsShown() then RequestPreviewRefresh(preview, "GROUP_PREVIEW_PAGE_REFRESH") end
    end
    if body.HookScript then body:HookScript("OnShow", RefreshThisPreview) end
    if body.HookScript then
        body:HookScript("OnHide", function()
            if box and box.ReleaseRuntimePreview then box:ReleaseRuntimePreview() end
            if box and box.Hide then box:Hide() end
        end)
    end
    M.TrackCollapsibleRefresh(ctx, body, RefreshThisPreview)
end
GroupPreview.Add = AddGFPreview
