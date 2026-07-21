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
local GF_PREVIEW_EXPANDED_BOX_HEIGHT = 292
local GF_PREVIEW_COMPACT_BOX_HEIGHT = 132
local Tr = M.TranslateText or M.Tr or function(text) return text end
local function SetPreviewHeaderStatus(body)
    local gp = M.GroupPage or {}
    local fn = gp.SetSectionHeaderStatus
    if type(fn) == "function" then fn(body, nil) end
end
local function GFPreviewIntroMetrics(width)
    if M.groupPreviewExpanded ~= true then return GF_PREVIEW_COMPACT_BOX_HEIGHT + 16, -8 end
    local maxContentW = tonumber(M.formContentMaxWidth) or 980
    local contentW = min(maxContentW, max(320, tonumber(width) or 720))
    local translated = Tr(GF_PREVIEW_NOTE)
    local noteW = max(220, contentW - 28)
    local charsPerLine = max(42, floor(noteW / 5.6))
    local lines = max(1, floor(((#tostring(translated or "") + charsPerLine - 1) / charsPerLine)))
    lines = min(lines, 4)
    local noteTop = 40
    local noteLineH = 14
    local noteGap = 18
    local boxY = -(noteTop + (lines * noteLineH) + noteGap)
    local contentH = max(378, -boxY + 292 + 14)
    return contentH, boxY
end
local function GroupPreviewScopeLabel()
    local scope = tostring(M.gfScope or "party")
    if scope == "raid" then return Tr("Raid") end
    if scope == "mythicraid" then return Tr("Mythic Raid") end
    return Tr("Party")
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
    if box.RequestRefresh then
        -- RequestRefresh owns the deferred render. Do not reject the request
        -- during an ancestor OnShow: effective visibility lags logical ownership.
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
    for i = 1, #M._gfNativePreviews do
        if M._gfNativePreviews[i] == box then return end
    end
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
            if record and type(record.restore) == "function" then record.restore(true) end
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
            if box.IsShown and box:IsShown() then RequestPreviewRefresh(box, reason or "GROUP_PREVIEW_REFRESH_ALL") end
        elseif box and box.ReleaseRuntimePreview then
            box:ReleaseRuntimePreview()
        end
    end
    for i = writeIndex, #previews do
        previews[i] = nil
    end
end
-- Window hide is a suspension for cached pages, while ReleaseGFNativePreviews
-- deliberately clears the box's local Shown state.  Resume that exact owner
-- explicitly instead of relying on a page data refresh or an ancestor OnShow.
function M.ResumeGFNativePreviews(reason, pageKey)
    local previews = M._gfNativePreviews
    pageKey = pageKey or M.activeKey
    if not previews or not pageKey then return false end
    local resumed = false
    for i = 1, #previews do
        local box = previews[i]
        if IsCurrentPreviewBox(box) and box._msufGFNativePreviewPageKey == pageKey then
            local hostShown = box._msufGFPreviewHostShown
            if type(hostShown) ~= "function" or hostShown() then
                if box.Show then box:Show() end
                RequestPreviewRefresh(box, reason or "GROUP_PREVIEW_RESUME")
                resumed = true
            end
        end
    end
    return resumed
end
local function CreateNativeGFPreview(parent, ctx)
    local create = GroupPreview.CreateNative
    if type(create) == "function" then return create(parent, ctx, GroupPreview.OpenSection) end
    return nil
end
local function RebindNativeGFPreview(box, parent, ctx)
    if not (box and parent) then return nil end
    if box.Hide then box:Hide() end
    if box.SetParent then box:SetParent(parent) end
    if box.ClearAllPoints then box:ClearAllPoints() end
    local width = ((ctx and ctx.width) or 720) - 28
    if box.SetWidth then box:SetWidth(width) end
    if box.SetFrameLevel and parent.GetFrameLevel then box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2) end
    local renderState = box._msufGFRenderState
    if renderState then
        renderState.ctx = ctx
        renderState.width = width
    end
    if box.RegisterRuntimeControlsForPage then box:RegisterRuntimeControlsForPage(ctx and ctx.key) end
    return box
end
local function AddGFPreview(ctx, builder)
    if not (builder and builder.CollapsibleSection and W and T) then return end
    local sectionH, boxY = GFPreviewIntroMetrics(builder and builder.width or ctx and ctx.width)
    local body = builder:CollapsibleSection("gf_preview_native", "Hide Preview", sectionH, true)
    local sectionEntry = body and body._msuf2CollapsibleEntry
    local previewHeader = sectionEntry and sectionEntry.header
    if sectionEntry then
        sectionEntry._msuf2ManualHintLayout = true
        if sectionEntry.hint then sectionEntry.hint:Hide() end
        if sectionEntry.label then
            sectionEntry.label:SetText("Preview - " .. GroupPreviewScopeLabel())
            sectionEntry.label:ClearAllPoints()
            sectionEntry.label:SetPoint("LEFT", sectionEntry.arrow, "RIGHT", 8, 0)
            sectionEntry.label:SetJustifyH("LEFT")
        end
    end
    local noteText = W.Text(body, GF_PREVIEW_NOTE, 14, -38, (body._msuf2Width or 720) - 28, T.colors.muted)
    noteText:SetShown(M.groupPreviewExpanded == true)
    local box
    local rendererMissing
    local missingText
    local expandBtn = T.Button(previewHeader or body, "Expand", 88, 20)
    if T.CenterButtonLabel then T.CenterButtonLabel(expandBtn) end
    local ApplyPreviewMode
    local function OwnsPreview()
        if not box then return false end
        local pageKey = ctx and ctx.key
        local wrapper = ctx and ctx.wrapper
        if box._msufGFNativePreviewPageKey ~= pageKey or box._msufGFNativePreviewWrapper ~= wrapper then return false end
        return box._msuf2PinnedFloating == true or (box.GetParent and box:GetParent() == body)
    end
    local function EnsurePreviewAttachment()
        if not (box and W.AttachPinnedPreview) then return end
        local record = box._msuf2PinnedPreviewRecord
        local pageKey = ctx and ctx.key
        local wrapper = ctx and ctx.wrapper
        if record and record.pageKey == pageKey and record.pageWrapper == wrapper then return end
        W.AttachPinnedPreview(body, box, {
            stateKey = "groupFramePreview",
            title = box._title,
            hint = box._hint,
            left = 14,
            right = 14,
            top = -8,
            pinnedHeight = 232,
            buttonWidth = 78,
            buttonHeight = 20,
            centerButton = true,
            quietButton = true,
            pageKey = pageKey,
            wrapper = wrapper,
            restoreParent = body,
            restorePoint = { "TOPLEFT", body, "TOPLEFT", 14, boxY },
            restoreWidth = box.GetWidth and box:GetWidth(),
            restoreHeight = box.GetHeight and box:GetHeight(),
        })
        local page = M.GroupPage
        if page and type(page.RegisterControl) == "function" then
            page.RegisterControl(box._msuf2PinButton, { key = pageKey }, "preview.pin.toggle",
                "Pin Group Preview", "toggle", "ephemeral")
        end
    end
    local function PreviewHostShown()
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return false end
        if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
        if body and body.IsShown and not body:IsShown() then return false end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return false end
        return true
    end
    local function EnsurePreview()
        if box and not OwnsPreview() then box = nil end
        if box then
            box._msufGFPreviewHostShown = PreviewHostShown
            if not PreviewHostShown() then return nil end
            if box.Show then box:Show() end
            EnsurePreviewAttachment()
            if ApplyPreviewMode then ApplyPreviewMode() end
            return box
        end
        if not PreviewHostShown() then return nil end
        local shared = GroupPreview._sharedNativeBox
        if shared and not shared._msufGFNativePreviewDisposed then
            box = RebindNativeGFPreview(shared, body, ctx)
        else
            box = CreateNativeGFPreview(body, ctx)
            GroupPreview._sharedNativeBox = box
        end
        if not box then
            if not rendererMissing then
                missingText = W.Text(body, "Group preview renderer is unavailable.", 14, boxY, (body._msuf2Width or 720) - 28, T.colors.muted)
                rendererMissing = true
            end
            return nil
        end
        if missingText and missingText.Hide then missingText:Hide() end
        box._msufGFPreviewHostShown = PreviewHostShown
        box._msuf2PreferredRestoreHeight = M.groupPreviewExpanded == true and GF_PREVIEW_EXPANDED_BOX_HEIGHT or GF_PREVIEW_COMPACT_BOX_HEIGHT
        box._msuf2PreferredRestoreYOffset = boxY
        box._msuf2CompactHeader = previewHeader
        box._msuf2CompactExpandButton = expandBtn
        box:SetPoint("TOPLEFT", body, "TOPLEFT", 16, boxY)
        RegisterNativePreview(box, ctx)
        box:Show()
        EnsurePreviewAttachment()
        if ApplyPreviewMode then ApplyPreviewMode() end
        return box
    end
    local function RefreshExpandButton()
        local expanded = M.groupPreviewExpanded == true
        expandBtn:SetParent(previewHeader or body)
        expandBtn:ClearAllPoints()
        expandBtn:SetSize(expanded and 130 or 88, 20)
        if previewHeader then
            expandBtn:SetPoint("RIGHT", previewHeader, "RIGHT", -12, 0)
            if expandBtn.SetFrameLevel and previewHeader.GetFrameLevel then expandBtn:SetFrameLevel((previewHeader:GetFrameLevel() or 1) + 3) end
        else
            expandBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, -8)
        end
        expandBtn:SetText(expanded and "Compact Preview" or "Expand")
    end
    ApplyPreviewMode = function()
        local expanded = M.groupPreviewExpanded == true
        local contentH, currentBoxY = GFPreviewIntroMetrics(builder and builder.width or ctx and ctx.width)
        local boxH = expanded and GF_PREVIEW_EXPANDED_BOX_HEIGHT or GF_PREVIEW_COMPACT_BOX_HEIGHT
        if sectionEntry and sectionEntry.label then sectionEntry.label:SetText("Preview - " .. GroupPreviewScopeLabel()) end
        if noteText then noteText:SetShown(expanded) end
        RefreshExpandButton()
        if OwnsPreview() and box._msuf2PinnedFloating ~= true then
            local previousH = box.GetHeight and box:GetHeight() or 0
            box._msuf2PreferredRestoreHeight = boxH
            box._msuf2PreferredRestoreYOffset = currentBoxY
            box._msuf2CompactHeader = previewHeader
            box._msuf2CompactExpandButton = expandBtn
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", body, "TOPLEFT", 14, currentBoxY)
            if box.ApplyCompactPreviewPresentation then box:ApplyCompactPreviewPresentation(not expanded) end
            box:SetHeight(boxH)
            if math.abs(previousH - boxH) > 0.5 then RequestPreviewRefresh(box, "GROUP_PREVIEW_HEIGHT") end
        end
        if sectionEntry and sectionEntry.contentHeight ~= contentH then
            sectionEntry.contentHeight = contentH
            if sectionEntry.body and sectionEntry.body.SetHeight then sectionEntry.body:SetHeight(contentH) end
            if sectionEntry.outer and sectionEntry.outer.SetHeight then
                sectionEntry.outer:SetHeight(sectionEntry.headerHeight + (sectionEntry.open and contentH or 0))
            end
            if sectionEntry.builder and sectionEntry.builder.RequestRelayoutCollapsibles then sectionEntry.builder:RequestRelayoutCollapsibles() end
        end
    end
    expandBtn:SetScript("OnClick", function()
        local expanded = not (M.groupPreviewExpanded == true)
        if M.SetMenuStateValue then M.SetMenuStateValue("groupPreviewExpanded", expanded)
        else M.groupPreviewExpanded = expanded end
        ApplyPreviewMode()
    end)
    if M.AddTooltip then M.AddTooltip(expandBtn, "Preview size", "Toggle between the compact reference preview and the full-height canvas.", { hook = true }) end
    local groupPage = M.GroupPage
    if groupPage and type(groupPage.RegisterControl) == "function" then
        groupPage.RegisterControl(expandBtn, { key = ctx and ctx.key }, "preview.height.toggle", "Expand Group Preview", "button", "ephemeral")
    end
    RefreshExpandButton()
    local function RefreshThisPreview()
        SetPreviewHeaderStatus(body)
        ApplyPreviewMode()
        local preview = EnsurePreview()
        if preview and preview.IsShown and preview:IsShown() then RequestPreviewRefresh(preview, "GROUP_PREVIEW_PAGE_REFRESH") end
    end
    M._assistantGroupPreviewEnsurers = M._assistantGroupPreviewEnsurers or {}
    M._assistantGroupPreviewEnsurers[ctx.key] = function()
        local entry = body and body._msuf2CollapsibleEntry
        if entry and type(entry.SetOpenImmediate) == "function" and not entry.SetOpenImmediate(true) then return false end
        RefreshThisPreview()
        return box ~= nil and PreviewHostShown()
    end
    M.EnsureGroupPagePreviewForAssistant = M.EnsureGroupPagePreviewForAssistant or function(pageKey)
        local ensure = M._assistantGroupPreviewEnsurers and M._assistantGroupPreviewEnsurers[pageKey]
        return type(ensure) == "function" and ensure() == true or false
    end
    if body.HookScript then body:HookScript("OnShow", RefreshThisPreview) end
    if body.HookScript then
        body:HookScript("OnHide", function()
            if OwnsPreview() and box.ReleaseRuntimePreview then box:ReleaseRuntimePreview() end
            if OwnsPreview() and box.Hide then box:Hide() end
        end)
    end
    M.TrackCollapsibleRefresh(ctx, body, RefreshThisPreview)
end
GroupPreview.Add = AddGFPreview
