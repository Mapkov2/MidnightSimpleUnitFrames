-- Group preview native owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
local Specs = M.GroupPreviewSpecs
local PreviewHelpers = M.PreviewHelpers
local GFZoomPan = M.GroupPreviewZoomPan
local Fallbacks = M.Fallbacks
local floor = math.floor
local Chrome = RequireFields("GroupNative.Chrome", M.GroupPreviewChrome,
    "KillPreviewAnimationForCombat PreviewAnimationActive PreviewAnimationInCombat RefreshPreviewAnimationButton "
    .. "StartPreviewAnimationDriver StopPreviewAnimationDriver UpdateHint")
local KillPreviewAnimationForCombat = Chrome.KillPreviewAnimationForCombat
local PreviewAnimationActive = Chrome.PreviewAnimationActive
local PreviewAnimationInCombat = Chrome.PreviewAnimationInCombat
local RefreshPreviewAnimationButton = Chrome.RefreshPreviewAnimationButton
local StartPreviewAnimationDriver = Chrome.StartPreviewAnimationDriver
local StopPreviewAnimationDriver = Chrome.StopPreviewAnimationDriver
local UpdateHint = Chrome.UpdateHint
local Layers = RequireFields("GroupNative.Layers", M.GroupPreviewLayers, "Build")
local Model = RequireFields("GroupNative.Config", M.GroupPreviewModel, "")
local Selection = RequireFields("GroupNative.Selection", M.GroupPreviewSelection,
    "GroupSelection OpenGFSection SuspendSelection")
local GroupSelection = Selection.GroupSelection
local OpenGFSection = Selection.OpenGFSection
local SuspendSelection = Selection.SuspendSelection
local View = RequireFields("GroupNative.View", M.GroupPreviewView, "Frame Stage Mock")

local C_Timer = M.MenuTimer or C_Timer
local GROUP_PREVIEW_REFRESH_DELAY = 0.05
local function ScheduleNativePreviewRefresh(fn, delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(tonumber(delay) or GROUP_PREVIEW_REFRESH_DELAY, fn)
    else
        fn()
    end
end
local function CreateDependencies()
    return {
        Config = Model,
        Selection = Selection,
        Specs = Specs,
        Interaction = {
            StartPan = GFZoomPan.Start,
            StopPan = GFZoomPan.Stop,
            ZoomWheel = Fallbacks.Noop,
            ResolveDefaultZoomLock = GFZoomPan.ResolveDefaultLock,
            UpdateZoomControls = GFZoomPan.UpdateControls,
            ClampZoom = GFZoomPan.Clamp,
        },
    }
end
-- The native preview installs in stages that share one per-call state table;
-- NativeBuild.Create runs them once, in order. Per-refresh work stays inside
-- the box methods and the render module exactly as before.
local NativeBuild = {}
function NativeBuild.Handles(state)
    local Deps, box = state.R, state.box
    box._selectedHandle = nil
    Deps.RegisterPreviewControl = state.RegisterPreviewControl
    local handles = M.GroupPreviewHandles.Install(box, Deps)
    state.handles = handles
    if M.PreviewSelectionBar then GroupSelection.Create(box, state.stage, handles.SelectHandle) end
end
function NativeBuild.Render(state)
    local box, handles = state.box, state.handles
    box.OnPreviewCanvasMoved = function(_, button)
        if PreviewHelpers.NotePreviewCanvasMoved then PreviewHelpers.NotePreviewCanvasMoved(button) end
    end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    M.GroupPreviewRender.Install(box, state.ctx, {
        Config = Model, Selection = Selection, Specs = Specs,
        Interaction = state.R.Interaction, Handles = handles,
        width = state.width, mock = state.mock,
    })
end
-- The page that owns this preview has hidden it: callers release the runtime preview instead of painting.
local function PreviewHostHidden(box)
    local hostShown = box._msufGFPreviewHostShown
    return hostShown and not hostShown()
end
function NativeBuild.Lifecycle(state)
    local box, StopHandleDrag = state.box, state.handles.StopHandleDrag
    function box:CancelPendingRefresh()
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        self._msufGFRefreshQueued = nil
        self._msufGFRefreshReason = nil
    end
    function box:SetTextDragRefreshSuppressed(active)
        if active then
            self._msufGFTextDragActive = true
            if self.CancelPendingRefresh then self:CancelPendingRefresh() end
        else
            self._msufGFTextDragActive = nil
        end
    end
    function box:RequestRefresh(reason)
        if PreviewAnimationInCombat() then
            self._msufGFRefreshAfterCombat = reason or self._msufGFRefreshAfterCombat or true
            if self.CancelPendingRefresh then self:CancelPendingRefresh() end
            return
        end
        self._msufGFRefreshAfterCombat = nil
        if PreviewHostHidden(self) then
            self:ReleaseRuntimePreview()
            return
        end
        if self._msufGFTextDragActive or self._msufGFRefreshQueued then
            self._msufGFRefreshReason = reason or self._msufGFRefreshReason
            return
        end
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        local serial = self._msufGFRefreshSerial
        self._msufGFRefreshQueued = true
        self._msufGFRefreshReason = reason
        local function RunRefresh()
            if not self then return end
            if serial ~= self._msufGFRefreshSerial then return end
            self._msufGFRefreshQueued = nil
            if PreviewAnimationInCombat() then
                self._msufGFRefreshAfterCombat = self._msufGFRefreshReason or self._msufGFRefreshAfterCombat or true
                return
            end
            if self._msufGFNativePreviewDisposed then return end
            if self.IsShown and not self:IsShown() then return end
            if PreviewHostHidden(self) then
                self:ReleaseRuntimePreview()
                return
            end
            if self.Refresh then self:Refresh(self._msufGFRefreshReason) end
            self._msufGFRefreshReason = nil
        end
        -- Live-mirror events (player regen ticks out of combat) coalesce on a
        -- wider window so value streams cost at most five renders per second.
        ScheduleNativePreviewRefresh(RunRefresh, reason == "GROUP_PREVIEW_LIVE_STATE" and 0.2 or nil)
    end
    function box:ReleaseRuntimePreview()
        self:CancelPendingRefresh()
        if M.GroupPreviewRender and M.GroupPreviewRender.HideAdditionalPreview then
            M.GroupPreviewRender.HideAdditionalPreview(self)
        end
        if self.SuspendSpellPreviewEffects then self:SuspendSpellPreviewEffects() end
        StopHandleDrag(self and self._selectedHandle)
        -- The cell is not on screen while the preview is suspended: the scene root goes quiet with it.
        PreviewHelpers.RestoreGroupSceneHandles(self, true)
        if self._scene then self._scene:Deactivate() end
        -- This is the one place the runtime preview is suspended - page switches,
        -- the fixed-preview expander and window hides all funnel through here,
        -- repeatedly and in any order - so it is also the one place the selection
        -- is handed over rather than destroyed.
        SuspendSelection(self)
        if PreviewHelpers.ReleaseKeyboardCapture then
            PreviewHelpers.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end
    box:HookScript("OnShow", function(self)
        if self.RegisterEvent then
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        if PreviewAnimationActive(self) then StartPreviewAnimationDriver(self) end
        RefreshPreviewAnimationButton(self)
        self:RequestRefresh("GROUP_PREVIEW_SHOW")
    end)
    box:HookScript("OnHide", function(self)
        StopPreviewAnimationDriver(self)
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        self:ReleaseRuntimePreview()
    end)
    box:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            PreviewHelpers.RestoreGroupSceneHandles(self, true)
            KillPreviewAnimationForCombat(self)
            if self.SuspendSpellPreviewEffects then self:SuspendSpellPreviewEffects() end
            self._msufGFRefreshAfterCombat = self._msufGFRefreshReason or self._msufGFRefreshAfterCombat or true
            if self.CancelPendingRefresh then self:CancelPendingRefresh() end
        elseif event == "PLAYER_REGEN_ENABLED" and self._msufGFRefreshAfterCombat then
            local reason = self._msufGFRefreshAfterCombat
            self._msufGFRefreshAfterCombat = nil
            self:RequestRefresh(type(reason) == "string" and reason or "GROUP_PREVIEW_REGEN")
        end
    end)
    box:HookScript("OnSizeChanged", function(self, width, height)
        if not self:IsShown() then return end
        width = floor((tonumber(width) or self:GetWidth() or 0) + 0.5)
        height = floor((tonumber(height) or self:GetHeight() or 0) + 0.5)
        if self._msufGFRefreshWidth == width and self._msufGFRefreshHeight == height then return end
        self._msufGFRefreshWidth = width
        self._msufGFRefreshHeight = height
        self:RequestRefresh("GROUP_PREVIEW_SIZE")
    end)
end
-- Live-state driver: the cell mirrors the player's current values (Render.BuildScene samples them), so refresh when
-- they change while the menu preview is visible. Zero combat overhead by construction: PLAYER_REGEN_DISABLED drops
-- every listener for the whole fight and only the re-arm signal stays.
local GF_LIVE_STATE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_NAME_UPDATE" }
function NativeBuild.LiveState(state)
    local box = state.box
    local driver = CreateFrame("Frame")
    box._msufGFLiveStateDriver = driver
    function box:ArmLiveStateDriver()
        driver:UnregisterAllEvents()
        if PreviewAnimationInCombat() then
            driver._msufLiveArmed = false
            driver:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        driver._msufLiveArmed = true
        driver:RegisterEvent("PLAYER_REGEN_DISABLED")
        if driver.RegisterUnitEvent then
            for i = 1, #GF_LIVE_STATE_EVENTS do
                driver:RegisterUnitEvent(GF_LIVE_STATE_EVENTS[i], "player")
            end
        end
    end
    function box:ReleaseLiveStateDriver()
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
    end
    driver:SetScript("OnEvent", function(_, event)
        if PreviewHelpers.LiveStateDriverGate(driver, event, box) then return end
        if event == "PLAYER_REGEN_ENABLED" then
            box:ArmLiveStateDriver()
            return
        end
        if PreviewAnimationInCombat() then return end
        box:RequestRefresh("GROUP_PREVIEW_LIVE_STATE")
    end)
    box:HookScript("OnShow", box.ArmLiveStateDriver)
    box:HookScript("OnHide", box.ReleaseLiveStateDriver)
end
function NativeBuild.Create(parent, ctx)
    local state = View.Frame(parent, ctx, CreateDependencies())
    View.Stage(state)
    Layers.Build(state)
    View.Mock(state)
    NativeBuild.Handles(state)
    NativeBuild.Render(state)
    NativeBuild.Lifecycle(state)
    NativeBuild.LiveState(state)
    return state.box
end
M.GroupPreview = M.GroupPreview or {}
M.GroupPreview.CreateNative = NativeBuild.Create
M.GroupPreview.OpenSection = OpenGFSection
function M.FocusGFPreviewTextSlot(kind, slot, active)
    local previews = M._gfNativePreviews
    if not previews then return false end
    local focused = false
    for i = 1, #previews do
        local box = previews[i]
        if box and not box._msufGFNativePreviewDisposed and box.FocusTextSlot and box.IsShown and box:IsShown()
            and (not box.IsVisible or box:IsVisible()) then focused = box:FocusTextSlot(kind, slot, active) or focused end
    end
    return focused
end

-- A sample-effect layer follows its open settings section: opening or closing one repaints every shown group preview,
-- whose render reads the section state and applies the edge.
local GF_SAMPLE_SECTION_IDS = { dispel = true, dispelSymbol = true }
local previousSectionStateChanged = M.OnCollapsibleSectionStateChanged
function M.OnCollapsibleSectionStateChanged(pageKey, sectionId, open, entry)
    if previousSectionStateChanged then previousSectionStateChanged(pageKey, sectionId, open, entry) end
    if pageKey ~= "gf_bars" or not GF_SAMPLE_SECTION_IDS[sectionId] then return end
    local previews = M._gfNativePreviews
    for i = 1, previews and #previews or 0 do
        local box = previews[i]
        if box and not box._msufGFNativePreviewDisposed and box.RequestRefresh and box.IsShown and box:IsShown() then
            box:RequestRefresh("GROUP_PREVIEW_SAMPLE_LAYER")
        end
    end
end
