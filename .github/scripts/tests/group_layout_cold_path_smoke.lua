local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local timerCallbacks = 0
local addon = {
    MSUF2 = {
        MenuTimer = {
            After = function(_, callback)
                timerCallbacks = timerCallbacks + 1
                callback()
            end,
        },
        UnitPage = {},
    },
}
assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitLazy.lua"))("MSUF", addon)

local function NewBuilder(open)
    local builder = { relayouts = 0 }
    function builder:CollapsibleSection(id, title, height)
        local body = { id = id, title = title, height = height }
        local entry = {
            body = body,
            builder = self,
            open = open == true,
        }
        body._msuf2CollapsibleEntry = entry
        self.entry = entry
        return body
    end
    function builder:RelayoutCollapsibles()
        self.relayouts = self.relayouts + 1
    end
    return builder
end

local builds, refreshes = 0, 0
local spec = {
    sectionId = "general",
    title = "Frame Basics",
    height = 430,
    build = function(ctx, builder)
        builds = builds + 1
        local body = builder:CollapsibleSection("general", "Frame Basics", 430, false)
        body.contentBuilt = true
        ctx.refreshers[#ctx.refreshers + 1] = function() refreshes = refreshes + 1 end
    end,
}

local closedCtx = { key = "gf_layout", refreshers = {} }
local closedBuilder = NewBuilder(false)
assert(addon.MSUF2.UnitPage.BuildSectionLazy(closedCtx, closedBuilder, nil, spec) == true)
assert(builds == 0, "closed Group Layout content was built during the cold page frame")
closedBuilder.entry.open = true
closedBuilder.entry._msuf2RefreshState(closedBuilder.entry)
assert(builds == 1 and refreshes == 1, "opening the section did not materialize and refresh its controls exactly once")
closedBuilder.entry._msuf2RefreshState(closedBuilder.entry)
assert(builds == 1, "materialized section content was rebuilt")
assert(timerCallbacks == 1 and closedBuilder.relayouts == 1, "opened lazy section did not settle layout exactly once")

local openBuilder = NewBuilder(true)
addon.MSUF2.UnitPage.BuildSectionLazy({ key = "gf_layout", refreshers = {} }, openBuilder, nil, spec)
assert(builds == 2, "saved-open section was not built synchronously")

local hiddenBuilder = NewBuilder(false)
addon.MSUF2.UnitPage.BuildSectionLazy({ key = "gf_layout", entry = { hiddenBuild = true }, refreshers = {} }, hiddenBuilder, nil, spec)
assert(builds == 3, "search hidden-build no longer materializes the complete searchable page")

local layout = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua")
for _, sectionId in ipairs({ "general", "text", "power", "range", "transparency", "layout_advanced", "sorting", "scaling", "anchor" }) do
    assert(layout:find('sectionId = "' .. sectionId .. '"', 1, true), "missing lazy Group Layout section: " .. sectionId)
end
assert(layout:find("M.UnitPage and M.UnitPage.BuildSectionLazy", 1, true),
    "Group Layout no longer uses the established lazy-section lifecycle")
assert(layout:find("M.GroupPreview.Add(ctx, b)", 1, true),
    "visible Group Preview was removed from the page cold path")
assert(layout:find('{ sectionId = "text", title = "Text", height = 690', 1, true),
    "Group Layout Text section no longer reserves enough height for the HP Appearance card")
assert(layout:find('version = 24', 1, true), "Group Layout cache version was not bumped")

local globalBars = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua")
for _, sectionId in ipairs({ "bars_outline", "bars_unit_dispel_overlay", "bars_power" }) do
    assert(globalBars:find('sectionId = "' .. sectionId .. '"', 1, true),
        "closed Global Bars section still builds eagerly: " .. sectionId)
end
assert(globalBars:find("BuildGlobalBarsSectionLazy", 1, true)
    and globalBars:find('version = 17', 1, true),
    "Global Bars closed-section cold path is not cache-versioned and lazy")

local previewPage = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua")
assert(previewPage:find("GroupPreview._sharedNativeBox", 1, true)
    and previewPage:find("RebindNativeGFPreview", 1, true)
    and previewPage:find("EnsurePreviewAttachment", 1, true),
    "Group Preview is not rebound with its pinning contract")
local previewNative = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
assert(previewNative:find("function box:RegisterRuntimeControlsForPage", 1, true)
    and previewNative:find("R.RegisterPreviewControl = RegisterPreviewControl", 1, true),
    "shared Group Preview does not preserve Search/Assistant control ownership")

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        shown = true,
        width = 720,
        height = 292,
        hooks = {},
    }
    function frame:SetParent(value) self.parent = value end
    function frame:GetParent() return self.parent end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetText(value) self.text = value end
    function frame:SetTextColor() end
    function frame:SetJustifyH() end
    function frame:SetAlpha() end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:GetFrameLevel() return self.frameLevel or 1 end
    function frame:SetScript(event, callback) self.scripts = self.scripts or {}; self.scripts[event] = callback end
    function frame:HookScript(event, callback)
        local hooks = self.hooks[event] or {}
        hooks[#hooks + 1] = callback
        self.hooks[event] = hooks
    end
    function frame:RunHooks(event)
        for i = 1, #(self.hooks[event] or {}) do self.hooks[event][i](self) end
    end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false; self.hideCount = (self.hideCount or 0) + 1 end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    function frame:IsShown() return self.shown end
    return frame
end

local previewCreates, previewRebinds, pinAttachments = 0, 0, 0
local previewAddon = { MSUF2 = {} }
local previewM = previewAddon.MSUF2
previewM.Theme = {
    colors = { muted = { 0.5, 0.5, 0.5, 1 } },
    Button = function(parent) return FakeFrame(parent) end,
    CenterButtonLabel = function() end,
}
previewM.Widgets = {
    Text = function(parent) return FakeFrame(parent) end,
    SetCollapsibleBadges = function() end,
    AttachPinnedPreview = function(body, box, opts)
        pinAttachments = pinAttachments + 1
        box._msuf2PinButton = box._msuf2PinButton or FakeFrame(box)
        box._msuf2PinnedPreviewRecord = {
            pageKey = opts.pageKey,
            pageWrapper = opts.wrapper,
        }
    end,
}
previewM.GroupPage = {
    RegisterControl = function() end,
    SetSectionHeaderStatus = function() end,
}
previewM.GroupPreview = {
    CreateNative = function(parent, ctx)
        previewCreates = previewCreates + 1
        local box = FakeFrame(parent)
        box._title, box._hint = FakeFrame(box), FakeFrame(box)
        box._msufGFRenderState = { ctx = ctx, width = ctx.width - 28 }
        function box:RegisterRuntimeControlsForPage(pageKey)
            previewRebinds = previewRebinds + 1
            self.lastRuntimePage = pageKey
        end
        function box:ApplyCompactPreviewPresentation(value) self.compact = value end
        function box:RequestRefresh() self.refreshes = (self.refreshes or 0) + 1 end
        function box:ReleaseRuntimePreview() self.releases = (self.releases or 0) + 1 end
        return box
    end,
}
previewM.TranslateText = function(value) return value end
previewM.TrackCollapsibleRefresh = function(_, _, callback) callback() end
previewM.AddTooltip = function() end
previewM.frame = FakeFrame()
previewM.groupPreviewExpanded = false
previewM.formContentMaxWidth = 980

assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua"))("MSUF", previewAddon)
local function BuildPreviewPage(key)
    local wrapper = FakeFrame()
    local builder = { width = 720 }
    function builder:CollapsibleSection()
        local body = FakeFrame(wrapper)
        self.entry = body
        body._msuf2Width = self.width
        body._msuf2CollapsibleEntry = {
            body = body,
            outer = FakeFrame(wrapper),
            header = FakeFrame(wrapper),
            arrow = FakeFrame(wrapper),
            label = FakeFrame(wrapper),
            hint = FakeFrame(wrapper),
            builder = self,
            open = true,
            headerHeight = 28,
            contentHeight = 148,
        }
        return body
    end
    function builder:RequestRelayoutCollapsibles() end
    function builder:RelayoutCollapsibles() end
    local ctx = { key = key, wrapper = wrapper, width = 720, refreshers = {} }
    previewM.activeKey = key
    previewM.cache = previewM.cache or {}
    previewM.cache[key] = { wrapper = wrapper }
    previewM.GroupPreview.Add(ctx, builder)
    return ctx, builder
end

local firstCtx, firstBuilder = BuildPreviewPage("gf_layout")
local sharedPreview = previewM.GroupPreview._sharedNativeBox
assert(previewCreates == 1 and sharedPreview and sharedPreview:GetParent() == firstBuilder.entry,
    "first Group page did not create exactly one native preview")
local secondCtx, secondBuilder = BuildPreviewPage("gf_bars")
assert(previewCreates == 1 and sharedPreview:GetParent() == secondBuilder.entry,
    "second Group page created a duplicate preview instead of rebinding the shared one")
assert(previewRebinds == 1 and sharedPreview.lastRuntimePage == secondCtx.key,
    "shared preview Runtime Controls did not move to the new page")
assert(sharedPreview._msufGFRenderState.ctx == secondCtx and sharedPreview._msufGFRenderState.width == 692,
    "shared preview renderer retained stale page geometry/context")
assert(pinAttachments == 2 and sharedPreview._msuf2PinnedPreviewRecord.pageKey == secondCtx.key,
    "shared preview pinning ownership did not move to the new page")
local hidesBeforeOldOwner = sharedPreview.hideCount or 0
firstBuilder.entry:RunHooks("OnHide")
assert((sharedPreview.hideCount or 0) == hidesBeforeOldOwner,
    "stale Group page hid the preview after ownership moved")
secondBuilder.entry:RunHooks("OnHide")
assert((sharedPreview.hideCount or 0) == hidesBeforeOldOwner + 1 and sharedPreview.releases == 1,
    "current Group page no longer releases its preview on hide")

print("group_layout_cold_path_smoke: ok")
