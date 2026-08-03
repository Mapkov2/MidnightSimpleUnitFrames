local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme
local W = M.Widgets
local GroupPreview = M.GroupPreview or {}
M.GroupPreview = GroupPreview

-- Menu2 Group preview page section.
-- Hosts the fixed group preview box and preview refresh hooks. The actual mock
-- renderer lives in Preview/MSUF_Menu2_GroupPreview_Native.lua.
local GF_PREVIEW_FIXED_HEIGHT = 180
local GF_PREVIEW_BOX_HEIGHT = 132
local GF_PREVIEW_EXPANDED_HEIGHT = 358
local GF_PREVIEW_BOX_Y = -40
local Tr = M.TranslateText or M.Tr or function(text) return text end
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
            local expander = box._msuf2FixedPreviewExpanderRecord
            if expander and expander.expanded then expander:Close("GROUP_PREVIEW_RELEASE") end
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
    if not (builder and W and W.FixedPreviewSection and T) then return end
    local body, toolbar, fixedRecord = W.FixedPreviewSection(ctx, builder, {
        title = Tr("Preview - ") .. GroupPreviewScopeLabel(),
        height = GF_PREVIEW_FIXED_HEIGHT,
        gap = 8,
    })
    if not body then return end
    local box, expander
    local EnsurePreviewExpander
    local RefreshThisPreview
    local rendererMissing
    local missingText
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
            pageKey = pageKey,
            wrapper = wrapper,
        })
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
            EnsurePreviewAttachment()
            if EnsurePreviewExpander then EnsurePreviewExpander() end
            if expander and expander.expanded then
                if box.Show then box:Show() end
                expander:Relayout("GROUP_PREVIEW_EXPAND_OWNERSHIP")
            elseif box._msuf2PinnedFloating ~= true then
                if box.Show then box:Show() end
                box._msuf2PreferredRestoreHeight = GF_PREVIEW_BOX_HEIGHT
                box._msuf2PreferredRestoreYOffset = GF_PREVIEW_BOX_Y
                box._msuf2CompactHeader = toolbar
                box._msuf2CompactExpandButton = expander and expander.button or nil
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", body, "TOPLEFT", 14, GF_PREVIEW_BOX_Y)
                box:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, GF_PREVIEW_BOX_Y)
                box:SetHeight(GF_PREVIEW_BOX_HEIGHT)
                if box.ApplyCompactPreviewPresentation then box:ApplyCompactPreviewPresentation(true) end
            end
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
                missingText = W.Text(body, "Group preview renderer is unavailable.", 14, GF_PREVIEW_BOX_Y, (body._msuf2Width or 720) - 28, T.colors.muted)
                rendererMissing = true
            end
            return nil
        end
        if missingText and missingText.Hide then missingText:Hide() end
        box._msufGFPreviewHostShown = PreviewHostShown
        box._msuf2PreferredRestoreHeight = GF_PREVIEW_BOX_HEIGHT
        box._msuf2PreferredRestoreYOffset = GF_PREVIEW_BOX_Y
        box._msuf2CompactHeader = toolbar
        box._msuf2CompactExpandButton = expander and expander.button or nil
        box:SetPoint("TOPLEFT", body, "TOPLEFT", 14, GF_PREVIEW_BOX_Y)
        box:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, GF_PREVIEW_BOX_Y)
        box:SetHeight(GF_PREVIEW_BOX_HEIGHT)
        RegisterNativePreview(box, ctx)
        box:Show()
        EnsurePreviewAttachment()
        if EnsurePreviewExpander then EnsurePreviewExpander() end
        if box._msuf2PinnedFloating ~= true and box.ApplyCompactPreviewPresentation then
            box:ApplyCompactPreviewPresentation(true)
        end
        return box
    end
    RefreshThisPreview = function(reason)
        if body.title then body.title:SetText(Tr("Preview - ") .. GroupPreviewScopeLabel()) end
        local preview = EnsurePreview()
        if preview and preview.IsShown and preview:IsShown() then
            RequestPreviewRefresh(preview, reason or (expander and expander.expanded
                and "GROUP_PREVIEW_PAGE_EXPANDED" or "GROUP_PREVIEW_PAGE_COMPACT"))
        end
    end
    EnsurePreviewExpander = function()
        if not (box and W.AttachFixedPreviewExpander) then return nil end
        if expander and expander.box == box and not expander.disposed then
            box._msuf2CompactExpandButton = expander.button
            box._msuf2FixedPreviewExpanderRecord = expander
            return expander
        end
        expander = W.AttachFixedPreviewExpander(body, toolbar, box, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            compactHeight = GF_PREVIEW_BOX_HEIGHT,
            compactTop = GF_PREVIEW_BOX_Y,
            expandedHeight = GF_PREVIEW_EXPANDED_HEIGHT,
            refreshPreview = function(target, reason)
                RequestPreviewRefresh(target, reason or "GROUP_PREVIEW_SIZE")
            end,
            onStateChanged = function(expanded, target)
                if target.ReleaseRuntimePreview then target:ReleaseRuntimePreview() end
                RequestPreviewRefresh(target, expanded and "GROUP_PREVIEW_EXPAND" or "GROUP_PREVIEW_COMPACT")
            end,
        })
        local groupPage = M.GroupPage
        if expander and expander.button and not expander.button._msuf2GroupExpandRegistered
            and groupPage and type(groupPage.RegisterControl) == "function"
        then
            expander.button._msuf2GroupExpandRegistered = true
            groupPage.RegisterControl(expander.button, { key = ctx and ctx.key },
                "preview.height.toggle", "Expand Group Preview", "button", "ephemeral")
        end
        box._msuf2CompactExpandButton = expander and expander.button or nil
        box._msuf2FixedPreviewExpanderRecord = expander
        return expander
    end
    M._assistantGroupPreviewEnsurers = M._assistantGroupPreviewEnsurers or {}
    M._assistantGroupPreviewEnsurers[ctx.key] = function()
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
    M.TrackRefresh(ctx, RefreshThisPreview)
    if fixedRecord then fixedRecord.onActivate = RefreshThisPreview end
end
GroupPreview.Add = AddGFPreview
