--- UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua
--- Edit Mode 2 bridge for Group Frames.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry then return end

local Reg = EM2.Registry
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local floor, max, min = math.floor, math.max, math.min
local type, tonumber, tostring = type, tonumber, tostring

local KIND_TO_KEY = {
    party = "gf_party",
    raid = "gf_raid",
    mythicraid = "gf_mythicraid",
}

local KEY_TO_KIND = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
}

local LABELS = {
    party = "Group: Party",
    raid = "Group: Raid",
    mythicraid = "Group: Mythic Raid",
}

local _containers = {}
local _previewAnchors = {}
local _popups = {}
local _em2Active = false
local _previewShownByEM2 = true
local _activePreviewKind
local _gfButton
local DRAG_WIRE_VERSION = 2
local _childScratch = {}
local _childScratchCount = 0

local function GF()
    return MSUF and MSUF.GF
end

local function NormalizeKind(kind)
    if kind == "party" or kind == "raid" or kind == "mythicraid" then return kind end
    return KEY_TO_KIND[kind]
end

local function GetConf(kind)
    local gf = GF()
    if gf and type(gf.GetConf) == "function" then return gf.GetConf(kind) end
    local db = _G.MSUF_DB
    local key = KIND_TO_KEY[kind]
    return db and key and db[key] or nil
end

local function KindEnabled(kind)
    local conf = GetConf(kind)
    return conf and conf.enabled == true
end

local function PartyEnabled()
    return KindEnabled("party")
end

local function RaidEnabled()
    return KindEnabled("raid")
end

local function MythicRaidEnabled()
    return KindEnabled("mythicraid")
end

local function ConfigLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function ShowConfigLock()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    end
end

local function BlockConfigLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if ConfigLocked() then
        ShowConfigLock()
        return true
    end
    return false
end

local function GetDefaultCenter(kind)
    if kind == "raid" or kind == "mythicraid" then return -500, 0 end
    return -400, 0
end

local function GetLiveGroupKind()
    local gf = GF()
    if IsInRaid and IsInRaid() then
        return (gf and type(gf.GetLiveRaidKind) == "function" and NormalizeKind(gf.GetLiveRaidKind())) or "raid"
    end
    if IsInGroup and IsInGroup() then
        return "party"
    end
    return nil
end

local function RuntimeHeaderKey(kind)
    if kind == "party" then return "party" end
    if kind == "raid" or kind == "mythicraid" then return "raid" end
    return nil
end

local function UsesRuntimeAnchor(kind)
    local live = GetLiveGroupKind()
    if not live then return false end
    return NormalizeKind(kind) == live
end

local function RuntimeAnchor(kind)
    kind = NormalizeKind(kind)
    if not (kind and UsesRuntimeAnchor(kind)) then return nil end
    local gf = GF()
    local headerKey = RuntimeHeaderKey(kind)
    local anchor = gf and gf.anchors and headerKey and gf.anchors[headerKey]
    if anchor and anchor.GetLeft and anchor:GetLeft() then
        return anchor
    end
    return nil
end

local function EnsureRuntimeAnchor(kind)
    kind = NormalizeKind(kind)
    if not (kind and UsesRuntimeAnchor(kind)) then return nil end
    local anchor = RuntimeAnchor(kind)
    if anchor then return anchor end

    local gf = GF()
    local headerKey = RuntimeHeaderKey(kind)
    if gf and headerKey and type(gf.SetupHeader) == "function" and not ConfigLocked() then
        gf.SetupHeader(headerKey, kind)
        return RuntimeAnchor(kind)
    end
    return nil
end

local function EnsurePreviewAnchor(kind)
    kind = NormalizeKind(kind)
    if not kind then return nil end
    local anchor = _previewAnchors[kind]
    if not anchor then
        anchor = CreateFrame("Frame", "MSUF_GF_EM2PreviewAnchor_" .. kind, UIParent)
        anchor:EnableMouse(false)
        anchor._msufIsGroupFrame = true
        anchor._msufGFKind = kind
        anchor._msufGFLogicalPreviewAnchor = true
        _previewAnchors[kind] = anchor
    end
    return anchor
end

local function GetRuntimePreviewCount(kind)
    kind = NormalizeKind(kind)
    if not (kind and UsesRuntimeAnchor(kind)) then return nil end

    if kind == "party" then
        local conf = GetConf(kind)
        local n = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
        if n > 0 and (not conf or conf.showPlayer ~= false) then
            n = n + 1
        elseif n == 0 and conf and conf.showSolo == true and conf.showPlayer ~= false then
            n = 1
        end
        return n > 0 and n or nil
    end

    local n = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
    return n > 0 and n or nil
end

local function GetRequestedPreviewCount(kind)
    local liveCount = GetRuntimePreviewCount(kind)
    if liveCount then return liveCount end
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function GetSelectedPreviewKind()
    local gf = GF()
    local optionsKind = gf and NormalizeKind(gf._optionsActiveKind)
    if optionsKind then return optionsKind end
    local explicitKind = NormalizeKind(_activePreviewKind)
    if explicitKind then return explicitKind end
    local stateKey = EM2.State and EM2.State.GetUnitKey and EM2.State.GetUnitKey()
    local stateKind = NormalizeKind(stateKey)
    if stateKind then return stateKind end
    return GetLiveGroupKind()
end

local function ShouldShowPreviewKind(kind)
    local selected = GetSelectedPreviewKind()
    return selected == nil or selected == kind
end

local function HasNativePreviewAPI(gf)
    return gf
        and type(gf.SetPreviewAnchor) == "function"
        and type(gf.ShowPreview) == "function"
        and type(gf.HidePreview) == "function"
end

local function ResolveAnchorFrame(conf)
    local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
    if type(name) == "string" and name ~= "" and name ~= "FREE" and name ~= "UIParent" then
        local UF = MSUF and MSUF.UF
        if UF and UF.frames and UF.frames[name] then return UF.frames[name] end
        if _G[name] then return _G[name] end
    end
    return UIParent
end

local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function AnchorPoint(conf)
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not VALID_POINTS[point] then point = "CENTER" end
    return point
end

local function IsPreviewActive(kind)
    if not (_em2Active and _previewShownByEM2 and KindEnabled(kind) and ShouldShowPreviewKind(kind)) then
        return false
    end
    if UsesRuntimeAnchor(kind) then
        return true
    end
    local gf = GF()
    if HasNativePreviewAPI(gf) and not ConfigLocked() then
        return gf._previewActive and gf._previewActive[kind] == true
    end
    return true
end

local function EditDragActive()
    return EM2.Ticker and EM2.Ticker.IsDragging and EM2.Ticker.IsDragging()
end

local function EnsureContainer(kind)
    if _containers[kind] then return _containers[kind] end
    local f = CreateFrame("Frame", "MSUF_GF_Container_" .. kind, UIParent, "BackdropTemplate")
    f:SetSize(120, 40)
    f:SetPoint("CENTER", UIParent, "CENTER", GetDefaultCenter(kind))
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(320)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    f.msufConfigKey = KIND_TO_KEY[kind]
    f._msufIsGroupFrame = true
    f._msufGFKind = kind

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.06, 0.12, 0.28)
    f._msufGFEditBg = bg

    local edge = CreateFrame("Frame", nil, f, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    edge:SetBackdropBorderColor(0.20, 0.65, 1.00, 0.45)
    edge:SetFrameLevel((f:GetFrameLevel() or 0) + 1)
    f._msufGFEditEdge = edge

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", 11, "")
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(0.68, 0.83, 1.00, 0.88)
    fs:SetPoint("CENTER")
    fs:SetText(LABELS[kind] or "Group Frame")
    f._msufGFEditLabel = fs

    _containers[kind] = f
    return f
end

local function GetPositionCount(kind)
    local gf = GF()
    if gf and type(gf.GetPositionCount) == "function" then
        return gf.GetPositionCount(kind)
    end
    return GetRequestedPreviewCount(kind)
end

local function FrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
        return nil
    end
    if frame.IsShown and not frame:IsShown() then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local fS = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiS = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not fS or fS == 0 then fS = 1 end
    if not uiS or uiS == 0 then uiS = 1 end
    local ratio = fS / uiS
    return l * ratio, r * ratio, t * ratio, b * ratio
end

local function ExpandBounds(bounds, frame)
    local l, r, t, b = FrameRectToUI(frame)
    if not l then return bounds end
    if not bounds then
        return { l = l, r = r, t = t, b = b }
    end
    if l < bounds.l then bounds.l = l end
    if r > bounds.r then bounds.r = r end
    if t > bounds.t then bounds.t = t end
    if b < bounds.b then bounds.b = b end
    return bounds
end

local function FrameCenterToUI(frame)
    local l, r, t, b = FrameRectToUI(frame)
    if not l then return nil, nil end
    return (l + r) * 0.5, (b + t) * 0.5
end

local function PreviewBounds(kind)
    local gf = GF()
    local frames = gf and gf._previewFrames and gf._previewFrames[kind]
    local bounds
    if frames then
        for i = 1, #frames do
            bounds = ExpandBounds(bounds, frames[i])
        end
    end
    if bounds then return bounds end
    return ExpandBounds(nil, gf and gf._previewLayoutFrame and gf._previewLayoutFrame[kind])
end

local function CaptureChildren(...)
    local count = select("#", ...)
    for i = 1, count do
        _childScratch[i] = select(i, ...)
    end
    for i = count + 1, _childScratchCount do
        _childScratch[i] = nil
    end
    _childScratchCount = count
    return count
end

local function RuntimeBounds(kind)
    local gf = GF()
    local headerKey = RuntimeHeaderKey(kind)
    local header = gf and gf.headers and headerKey and gf.headers[headerKey]
    local bounds
    if header and header.GetChildren then
        local count = CaptureChildren(header:GetChildren())
        for i = 1, count do
            bounds = ExpandBounds(bounds, _childScratch[i])
        end
    end
    if bounds then return bounds end
    return ExpandBounds(nil, RuntimeAnchor(kind))
end

local function SetFrameToBounds(frame, bounds)
    if not (frame and bounds) then return false end
    local w = max((bounds.r or 0) - (bounds.l or 0), 1)
    local h = max((bounds.t or 0) - (bounds.b or 0), 1)
    frame:SetSize(w, h)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", floor((bounds.l or 0) + 0.5), floor(((bounds.t or 0) - UIParent:GetHeight()) + 0.5))
    return true
end

local function HidePreviewVisualsForCombat()
    local gf = GF()
    if gf and type(gf.HidePreview) == "function" then
        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
            gf.HidePreview(kind)
        end
    end
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if _containers[kind] then _containers[kind]:Hide() end
        if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
    end
end

local function PositionLogicalPreviewAnchor(kind, conf, totalW, totalH)
    local anchor = EnsurePreviewAnchor(kind)
    if not anchor then return nil end
    anchor:SetSize(max(totalW or 1, 1), max(totalH or 1, 1))
    anchor:ClearAllPoints()
    local defX, defY = GetDefaultCenter(kind)
    local cx = tonumber(conf and conf.offsetX)
    local cy = tonumber(conf and conf.offsetY)
    if cx == nil then cx = defX end
    if cy == nil then cy = defY end
    local point = AnchorPoint(conf)
    anchor:SetPoint(point, ResolveAnchorFrame(conf), point, floor(cx + 0.5), floor(cy + 0.5))
    anchor:Show()
    return anchor
end

local function SyncContainer(kind)
    kind = NormalizeKind(kind)
    if not kind then return nil end
    if ConfigLocked() then
        if _containers[kind] then _containers[kind]:Hide() end
        if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
        return nil
    end
    local conf = GetConf(kind)
    if not conf then return nil end
    local container = EnsureContainer(kind)
    local gf = GF()

    if not IsPreviewActive(kind) then
        container:Hide()
        return nil
    end

    local totalW, totalH = tonumber(conf.width) or 80, tonumber(conf.height) or 32
    local gridDX, gridDY = 0, 0
    if gf and type(gf.GetGridMetrics) == "function" then
        local dx, dy, w, h = gf.GetGridMetrics(kind, GetPositionCount(kind))
        gridDX = tonumber(dx) or 0
        gridDY = tonumber(dy) or 0
        totalW = tonumber(w) or totalW
        totalH = tonumber(h) or totalH
    end

    local runtime = RuntimeAnchor(kind) or ((not ConfigLocked()) and EnsureRuntimeAnchor(kind)) or nil
    if runtime then
        runtime.msufConfigKey = KIND_TO_KEY[kind]
        runtime._msufIsGroupFrame = true
        runtime._msufGFKind = kind
        runtime._msufGFDragCenterToGridX = gridDX
        runtime._msufGFDragCenterToGridY = gridDY
        totalW = max((runtime.GetWidth and runtime:GetWidth()) or totalW, totalW, 1)
        totalH = max((runtime.GetHeight and runtime:GetHeight()) or totalH, totalH, 1)
    end

    container:SetSize(max(totalW, 1), max(totalH, 1))
    container._msufGFGridWidth = max(totalW, 1)
    container._msufGFGridHeight = max(totalH, 1)
    container:ClearAllPoints()
    if runtime then
        container:SetPoint("CENTER", runtime, "CENTER", 0, 0)
        container._msufGFLiveAnchor = runtime
        container._msufGFLogicalAnchor = nil
    else
        container._msufGFLiveAnchor = nil
        container._msufGFLogicalAnchor = PositionLogicalPreviewAnchor(kind, conf, totalW, totalH)
        if container._msufGFLogicalAnchor then
            container:SetPoint("CENTER", container._msufGFLogicalAnchor, "CENTER", 0, 0)
        else
            local defX, defY = GetDefaultCenter(kind)
            local cx = tonumber(conf.offsetX)
            local cy = tonumber(conf.offsetY)
            if cx == nil then cx = defX end
            if cy == nil then cy = defY end
            local point = AnchorPoint(conf)
            container:SetPoint(point, ResolveAnchorFrame(conf), point, floor(cx + 0.5), floor(cy + 0.5))
        end
    end
    local nativeActive = HasNativePreviewAPI(gf)
        and not ConfigLocked()
        and gf._previewActive
        and gf._previewActive[kind] == true
    local fallbackVisuals = not (nativeActive or runtime)
    if container._msufGFEditBg then container._msufGFEditBg:SetShown(fallbackVisuals) end
    if container._msufGFEditEdge then container._msufGFEditEdge:SetShown(fallbackVisuals) end
    if container._msufGFEditLabel then container._msufGFEditLabel:SetShown(fallbackVisuals) end
    local bounds = runtime and RuntimeBounds(kind) or PreviewBounds(kind)
    local centerToGridX, centerToGridY = gridDX, gridDY
    if bounds then
        local anchor = runtime or container._msufGFLogicalAnchor
        local anchorCX, anchorCY = FrameCenterToUI(anchor)
        if anchorCX and anchorCY then
            centerToGridX = anchorCX - ((bounds.l + bounds.r) * 0.5)
            centerToGridY = anchorCY - ((bounds.b + bounds.t) * 0.5)
        end
        SetFrameToBounds(container, bounds)
    end
    container._msufGFDragCenterToGridX = centerToGridX
    container._msufGFDragCenterToGridY = centerToGridY
    if runtime then
        runtime._msufGFDragCenterToGridX = centerToGridX
        runtime._msufGFDragCenterToGridY = centerToGridY
    end
    container:Show()
    if not fallbackVisuals then
        local layout = gf and gf._previewLayoutFrame and gf._previewLayoutFrame[kind]
        if layout and layout.IsShown and layout:IsShown() then
            layout.msufConfigKey = KIND_TO_KEY[kind]
            layout._msufIsGroupFrame = true
            layout._msufGFKind = kind
        end
    end
    return container
end

local function SyncAllContainers()
    SyncContainer("party")
    SyncContainer("raid")
    SyncContainer("mythicraid")
end

local function SyncMoversSoon(delay)
    if not C_Timer then return end
    C_Timer.After(delay or 0, function()
        if not _em2Active then return end
        if ConfigLocked() then return end
        SyncAllContainers()
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end)
end

local function RefreshGFPositionUI(kind)
    local gf = GF()
    if gf and gf._RequestOptionsResync then gf._RequestOptionsResync() end
    if type(_G.MSUF_EM2_SyncGFPopups) == "function" then
        _G.MSUF_EM2_SyncGFPopups()
    end
    if EM2.HUD and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
end

local function BeginGroupDrag(frame, kind, source)
    kind = NormalizeKind(kind)
    local key = kind and KIND_TO_KEY[kind]
    local cfg = key and Reg.Get and Reg.Get(key)
    local mover = key and EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(key)
    if not (key and cfg and mover and EM2.Ticker) then return end
    if BlockConfigLocked() then return end
    frame._msufGFEM2Dragging = true
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = source or "group-drag" })
    end
    if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    EM2.Ticker.BeginDrag(mover, key, cfg)
end

local function EndGroupDrag(frame)
    if not (frame and frame._msufGFEM2Dragging) then return end
    frame._msufGFEM2Dragging = nil
    frame._msufGFEM2LastDragEnd = GetTime and GetTime() or 0
    if EM2.Ticker then EM2.Ticker.EndDrag() end
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end
end

local function ClickGroupFrame(frame, kind, button, source)
    if button ~= "LeftButton" and button ~= "RightButton" then return end
    if frame and frame._msufGFEM2Dragging then return end
    local now = GetTime and GetTime() or 0
    if frame and frame._msufGFEM2LastDragEnd and (now - frame._msufGFEM2LastDragEnd) < 0.12 then return end
    kind = NormalizeKind(kind)
    local key = kind and KIND_TO_KEY[kind]
    if not key then return end
    if EM2.State then EM2.State.SetUnitKey(key) end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = source or "group-preview" })
    end
    if EM2.Popups and EM2.Popups.Open then
        EM2.Popups.Open(key, frame)
    end
end

local function WireDragFrame(frame, kind, source)
    if not frame or frame._msufGFEM2DragWired == DRAG_WIRE_VERSION then return end
    frame._msufGFEM2DragWired = DRAG_WIRE_VERSION
    frame._msufGFEM2Kind = kind
    if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    if frame.EnableMouse then frame:EnableMouse(true) end
    frame:SetScript("OnDragStart", function(self)
        BeginGroupDrag(self, self._msufGFEM2Kind or kind, source)
    end)
    frame:SetScript("OnDragStop", EndGroupDrag)
    frame:SetScript("OnMouseUp", function(self, button)
        ClickGroupFrame(self, self._msufGFEM2Kind or kind, button, source)
    end)
end

local function WirePreviewMouse(kind)
    local gf = GF()
    local frames = gf and gf._previewFrames and gf._previewFrames[kind]
    if not frames then return end
    for i = 1, #frames do
        local f = frames[i]
        if f and not f._msufGFEM2MouseWired then
            f._msufGFEM2MouseWired = true
            f._msufGFEM2Kind = kind
            if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
            if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
            if f.EnableMouse then f:EnableMouse(true) end
            f:SetScript("OnEnter", function(self)
                local key = KIND_TO_KEY[self._msufGFEM2Kind or kind]
                if EM2.Focus and EM2.Focus.SetHover then EM2.Focus.SetHover(key, nil, nil, { source = "group-preview" }) end
            end)
            f:SetScript("OnLeave", function()
                if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("group-preview") end
            end)
            f:SetScript("OnDragStart", function(self)
                BeginGroupDrag(self, self._msufGFEM2Kind or kind, "group-preview")
            end)
            f:SetScript("OnDragStop", EndGroupDrag)
            f:SetScript("OnClick", function(self, button)
                ClickGroupFrame(self, self._msufGFEM2Kind or kind, button, "group-preview")
            end)
        elseif f then
            f._msufGFEM2Kind = kind
            if f.EnableMouse then f:EnableMouse(true) end
        end
    end
end

local function ShowPreviewOnly()
    local gf = GF()
    if not gf then return end
    _previewShownByEM2 = true
    if ConfigLocked() then
        HidePreviewVisualsForCombat()
        return
    end

    local nativeAllowed = HasNativePreviewAPI(gf) and not ConfigLocked()
    local needsLiveVisibility = false
    if nativeAllowed then
        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
            if KindEnabled(kind) and ShouldShowPreviewKind(kind) then
                local liveAnchor = UsesRuntimeAnchor(kind) and (RuntimeAnchor(kind) or EnsureRuntimeAnchor(kind)) or nil
                if liveAnchor then
                    gf.SetPreviewAnchor(kind, nil)
                    gf.HidePreview(kind)
                    needsLiveVisibility = true
                else
                    gf.SetPreviewAnchor(kind, EnsurePreviewAnchor(kind) or EnsureContainer(kind))
                    gf.ShowPreview(kind, GetRequestedPreviewCount(kind))
                    WirePreviewMouse(kind)
                end
            else
                gf.SetPreviewAnchor(kind, nil)
                gf.HidePreview(kind)
            end
        end
        if needsLiveVisibility and gf.UpdateGroupVisibility then
            gf.UpdateGroupVisibility()
        end
    else
        if type(gf.RefreshAll) == "function" and not ConfigLocked() then
            gf.RefreshAll()
        elseif type(gf.RefreshVisuals) == "function" and not ConfigLocked() then
            gf.RefreshVisuals()
        end
    end

    SyncAllContainers()
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if _containers[kind] then WireDragFrame(_containers[kind], kind, "group-container") end
    end
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if nativeAllowed and gf.RefreshPreviewLayout and gf._previewActive and gf._previewActive[kind] then
            gf.RefreshPreviewLayout(kind)
        end
    end
    SyncAllContainers()
    SyncMoversSoon(0)
    SyncMoversSoon(0.05)
end

local function HidePreviewOnly()
    local gf = GF()
    _previewShownByEM2 = false
    if ConfigLocked() then
        HidePreviewVisualsForCombat()
        return
    end

    if HasNativePreviewAPI(gf) then
        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
            gf.SetPreviewAnchor(kind, nil)
            gf.HidePreview(kind)
        end
    end

    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if _containers[kind] then _containers[kind]:Hide() end
        if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
    end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function RefreshEditModePreviewAfterRuntimeChange()
    if not _em2Active then return end
    if EditDragActive() then return end
    if ConfigLocked() then
        HidePreviewVisualsForCombat()
        return
    end
    local gf = GF()
    if _previewShownByEM2 and HasNativePreviewAPI(gf) then
        ShowPreviewOnly()
    else
        SyncAllContainers()
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end
end

local function NudgePreviewKind(kind, dx, dy)
    kind = NormalizeKind(kind)
    local key = kind and KIND_TO_KEY[kind]
    if not key then return false end
    if not IsPreviewActive(kind) then return false end
    if ConfigLocked() then return true end

    local conf = GetConf(kind)
    if not conf then return false end
    if _G.MSUF_EM_UndoBeforeChange then
        _G.MSUF_EM_UndoBeforeChange("gf", kind, true)
    end

    local defX, defY = GetDefaultCenter(kind)
    conf.offsetX = floor(((tonumber(conf.offsetX) or defX) + (tonumber(dx) or 0)) + 0.5)
    conf.offsetY = floor(((tonumber(conf.offsetY) or defY) + (tonumber(dy) or 0)) + 0.5)

    local gf = GF()
    SyncContainer(kind)
    if gf and HasNativePreviewAPI(gf) and gf.RefreshPreviewLayout then
        gf.RefreshPreviewLayout(kind)
    elseif gf and gf.RefreshAll then
        gf.RefreshAll()
    end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshGFPositionUI(kind)
    return true
end

function _G.MSUF_GF_EM2_NudgePreview(kind, dx, dy)
    return NudgePreviewKind(kind, dx, dy)
end

function _G.MSUF_GF_EM2_SetPreviewNudgeTarget(kind, source)
    kind = NormalizeKind(kind)
    local key = kind and KIND_TO_KEY[kind]
    if not key then return end
    if EM2.State then EM2.State.SetUnitKey(key) end
    if type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then
        _G.MSUF_EM2_SetPreviewNudgeTarget({
            key = key,
            frame = EnsureContainer(kind),
            sourceFrame = source,
            IsActive = function()
                return IsPreviewActive(kind)
            end,
            Nudge = function(_, dx, dy)
                NudgePreviewKind(kind, dx, dy)
            end,
        })
    end
end

function _G.MSUF_GF_EM2_SetActivePreviewKind(kind)
    _activePreviewKind = NormalizeKind(kind)
    local gf = GF()
    if gf and type(gf.EM2_SetActivePreviewKind) == "function" then
        gf.EM2_SetActivePreviewKind(_activePreviewKind)
    end
    if _em2Active and _previewShownByEM2 then
        ShowPreviewOnly()
    end
end

local function EnterEditMode()
    if _em2Active then return end
    _em2Active = true
    _previewShownByEM2 = true
    ShowPreviewOnly()
    SyncMoversSoon(0.1)
end

local function ExitEditMode()
    if not _em2Active then return end
    _em2Active = false
    _previewShownByEM2 = false

    local gf = GF()
    if HasNativePreviewAPI(gf) then
        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
            gf.SetPreviewAnchor(kind, nil)
            gf.HidePreview(kind)
        end
    end

    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if _containers[kind] then _containers[kind]:Hide() end
        if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
        if _popups[kind] then _popups[kind]:Hide() end
    end

    if gf and type(gf.RefreshAll) == "function" and not ConfigLocked() then
        gf.RefreshAll()
    end
end

local function RegisterGF()
    Reg.Register({
        key       = "gf_party",
        label     = LABELS.party,
        order     = 70,
        popupType = "gf_party",
        canResize = false,
        canNudge  = true,
        getFrame  = function() return SyncContainer("party") end,
        getConf   = function() return GetConf("party") end,
        isEnabled = PartyEnabled,
        onEnter   = EnterEditMode,
        onExit    = ExitEditMode,
    })

    Reg.Register({
        key       = "gf_raid",
        label     = LABELS.raid,
        order     = 71,
        popupType = "gf_raid",
        canResize = false,
        canNudge  = true,
        getFrame  = function() return SyncContainer("raid") end,
        getConf   = function() return GetConf("raid") end,
        isEnabled = RaidEnabled,
        onEnter   = EnterEditMode,
        onExit    = ExitEditMode,
    })

    Reg.Register({
        key       = "gf_mythicraid",
        label     = LABELS.mythicraid,
        order     = 72,
        popupType = "gf_mythicraid",
        canResize = false,
        canNudge  = true,
        getFrame  = function() return SyncContainer("mythicraid") end,
        getConf   = function() return GetConf("mythicraid") end,
        isEnabled = MythicRaidEnabled,
        onEnter   = EnterEditMode,
        onExit    = ExitEditMode,
    })

    if EM2.State and EM2.State.IsActive and EM2.State.IsActive() then
        EnterEditMode()
        if EM2.Movers and EM2.Movers.Show then EM2.Movers.Show() end
    end
end

local function InstallStateHooks()
    if _G.MSUF_RegisterAnyEditModeListener then
        _G.MSUF_RegisterAnyEditModeListener(function(active)
            if active then EnterEditMode() else ExitEditMode() end
        end)
    end

    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" and not _G.MSUF_GF_EM2_DirectHooked then
        _G.MSUF_GF_EM2_DirectHooked = true
        hooksecurefunc("MSUF_SetMSUFEditModeDirect", function(active)
            if active then EnterEditMode() else ExitEditMode() end
        end)
    end
end

local function UpdateGFButton()
    if not _gfButton or not _gfButton._label then return end
    if _previewShownByEM2 then
        _gfButton._label:SetTextColor(0.38, 0.65, 1.00, 1)
        if _gfButton._dot then _gfButton._dot:Show() end
    else
        _gfButton._label:SetTextColor(0.40, 0.42, 0.50, 0.85)
        if _gfButton._dot then _gfButton._dot:Hide() end
    end
end

local function InstallHUDToggle()
    local HUD = EM2.HUD
    if not HUD or type(HUD.Show) ~= "function" or HUD._msufGFBridgeWrapped then return end
    HUD._msufGFBridgeWrapped = true
    local origShow = HUD.Show
    HUD.Show = function(...)
        origShow(...)
        if not _gfButton then
            local hf = _G.MSUF_EM2_HUD
            if not hf then return end
            local slot = _G.MSUF_EM2_HUD_PreviewAddonSlot
            _gfButton = CreateFrame("Button", nil, slot or hf)
            _gfButton:SetSize(38, 32)
            if slot then
                _gfButton:SetAllPoints(slot)
            else
                _gfButton:SetPoint("LEFT", hf, "CENTER", -198, 0)
            end

            local hl = _gfButton:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.05)

            local label = _gfButton:CreateFontString(nil, "OVERLAY")
            label:SetFont(STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", 12, "")
            label:SetShadowOffset(1, -1)
            label:SetPoint("CENTER")
            label:SetText("GF")
            _gfButton._label = label

            local dot = _gfButton:CreateTexture(nil, "OVERLAY")
            dot:SetSize(30, 2)
            dot:SetPoint("BOTTOM", _gfButton, "BOTTOM", 0, 2)
            dot:SetColorTexture(0.38, 0.65, 1.00, 0.90)
            _gfButton._dot = dot

            _gfButton:SetScript("OnClick", function()
                if _previewShownByEM2 then HidePreviewOnly() else ShowPreviewOnly() end
                UpdateGFButton()
                SyncMoversSoon(0.05)
            end)
            _gfButton:SetScript("OnEnter", function(self)
                if GameTooltip and not GameTooltip:IsForbidden() then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
                    GameTooltip:SetText("Toggle Group Frames preview", 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            _gfButton:SetScript("OnLeave", function()
                if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
            end)
        end
        UpdateGFButton()
    end

    if EM2.State and EM2.State.IsActive and EM2.State.IsActive() then
        HUD.Show()
    end
end

local function InstallRuntimeHooks()
    local gf = GF()
    if not gf or gf._msufEM2BridgeHooked then return end
    gf._msufEM2BridgeHooked = true

    local origRefreshVisuals = gf.RefreshVisuals
    if type(origRefreshVisuals) == "function" then
        gf.RefreshVisuals = function(...)
            local ret = origRefreshVisuals(...)
            RefreshEditModePreviewAfterRuntimeChange()
            return ret
        end
        _G.MSUF_GF_RefreshVisuals = gf.RefreshVisuals
    end

    local origRebuildAll = gf.RebuildAll
    if type(origRebuildAll) == "function" then
        gf.RebuildAll = function(...)
            local ret = origRebuildAll(...)
            RefreshEditModePreviewAfterRuntimeChange()
            if _em2Active and C_Timer then
                C_Timer.After(0.05, RefreshEditModePreviewAfterRuntimeChange)
            end
            return ret
        end
        _G.MSUF_GF_RebuildAll = gf.RebuildAll
    end
end

local combatHookFrame
local function InstallCombatHooks()
    if combatHookFrame then return end
    combatHookFrame = CreateFrame("Frame")
    combatHookFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatHookFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatHookFrame:SetScript("OnEvent", function(_, event)
        if not _em2Active then return end
        if event == "PLAYER_REGEN_DISABLED" then
            HidePreviewVisualsForCombat()
        elseif _previewShownByEM2 then
            ShowPreviewOnly()
        end
    end)
end

local function San(v, d)
    v = tonumber(v) or d or 0
    if v ~= v or v > 2000 or v < -2000 then v = d or 0 end
    return floor(v + 0.5)
end

local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local PC = {
    panelBg   = { 0.03, 0.05, 0.12, 0.95 },
    panelEdge = { 0.10, 0.20, 0.45, 0.90 },
    title     = { 0.75, 0.88, 1.00, 1.00 },
    white     = { 0.86, 0.92, 1.00, 0.95 },
    muted     = { 0.55, 0.62, 0.78, 0.70 },
    inputBg   = { 0.02, 0.03, 0.08, 0.90 },
    inputEdge = { 0.10, 0.18, 0.38, 0.70 },
    stepBg    = { 0.09, 0.10, 0.15, 0.85 },
    btnBg     = { 0.09, 0.10, 0.14, 0.90 },
    btnEdge   = { 0.10, 0.20, 0.42, 0.65 },
    btnHover  = { 0.20, 0.40, 0.80, 0.12 },
}

local GROUP_COPY_TARGETS = {
    { key = "party", label = "Party" },
    { key = "raid", label = "Raid" },
    { key = "mythicraid", label = "Mythic Raid" },
}

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF) == "table" and type(MSUF.Translate) == "function" then
        return MSUF.Translate(text)
    end
    local locale = (type(MSUF) == "table" and MSUF.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local function PFS(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    local c = color or PC.white
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

local function GetStep()
    if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
    if IsControlKeyDown and IsControlKeyDown() then return 10 end
    if IsAltKeyDown and IsAltKeyDown() then
        return (EM2.Grid and EM2.Grid.GetGridStep and EM2.Grid.GetGridStep()) or 20
    end
    return 1
end

local function PMakeStep(parent, text)
    local S = _G.MSUF_EM2_Menu2Style
    if S and S.Step then return S.Step(parent, text, 20, 22) end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(20, 22)
    b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    b:SetBackdropColor(PC.stepBg[1], PC.stepBg[2], PC.stepBg[3], PC.stepBg[4])
    b:SetBackdropBorderColor(PC.inputEdge[1], PC.inputEdge[2], PC.inputEdge[3], PC.inputEdge[4])
    local fs = PFS(b, 12, PC.white)
    fs:SetPoint("CENTER")
    fs:SetText(text)
    return b
end

local function PMakeBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w or 52, 22)
    e:SetAutoFocus(false)
    e:SetNumeric(false)
    e:SetFontObject(GameFontHighlightSmall)
    e:SetJustifyH("CENTER")
    e:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    e:SetBackdropColor(PC.inputBg[1], PC.inputBg[2], PC.inputBg[3], PC.inputBg[4])
    e:SetBackdropBorderColor(PC.inputEdge[1], PC.inputEdge[2], PC.inputEdge[3], PC.inputEdge[4])
    local S = _G.MSUF_EM2_Menu2Style
    if S and S.EditBox then S.EditBox(e) end
    return e
end

local function PWireStepper(minusBtn, box, plusBtn, cb)
    local function bump(delta)
        local v = tonumber(box:GetText()) or 0
        box:SetText(tostring(San(v + delta * GetStep(), 0)))
        if cb then cb() end
    end
    minusBtn:SetScript("OnClick", function() bump(-1) end)
    plusBtn:SetScript("OnClick", function() bump(1) end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if cb then cb() end end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end

local function PMakeTinyButton(popup, text, x, y, w, onClick)
    local S = _G.MSUF_EM2_Menu2Style
    if S and S.Button then
        local b = S.Button(popup, text, w or 66, 30, onClick)
        b:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
        return b
    end
    local b = CreateFrame("Button", nil, popup, "BackdropTemplate")
    b:SetSize(w or 66, 30)
    b:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
    b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    b:SetBackdropColor(PC.btnBg[1], PC.btnBg[2], PC.btnBg[3], 0.88)
    b:SetBackdropBorderColor(PC.btnEdge[1], PC.btnEdge[2], PC.btnEdge[3], 0.82)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(PC.btnHover[1], PC.btnHover[2], PC.btnHover[3], 0.18)
    local fs = PFS(b, 11, PC.white)
    fs:SetPoint("CENTER")
    fs:SetText(Tr(text))
    b._label = fs
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function PMakeCloseButton(popup)
    local S = _G.MSUF_EM2_Menu2Style
    if S and S.CloseButton then
        local b = S.CloseButton(popup, function() popup:Hide() end)
        b:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, -10)
        return b
    end
    local b = CreateFrame("Button", nil, popup)
    b:SetSize(24, 24)
    b:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, -10)
    local fs = PFS(b, 16, PC.muted)
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText("x")
    b:SetScript("OnClick", function() popup:Hide() end)
    b:SetScript("OnEnter", function() fs:SetTextColor(1.00, 0.42, 0.42, 1) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(PC.muted[1], PC.muted[2], PC.muted[3], PC.muted[4] or 1) end)
    return b
end

local function PMakeValuePair(popup, y, label1, key1, label2, key2, onChanged)
    local row = CreateFrame("Frame", nil, popup)
    row:SetSize(400, 24)
    row:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, y)

    local l1 = PFS(row, 12, PC.title)
    l1:SetPoint("LEFT", row, "LEFT", 0, 0)
    l1:SetText(label1)
    local m1 = PMakeStep(row, "-")
    m1:SetPoint("LEFT", l1, "RIGHT", 6, 0)
    local b1 = PMakeBox(row, 52)
    b1:SetPoint("LEFT", m1, "RIGHT", 1)
    local p1 = PMakeStep(row, "+")
    p1:SetPoint("LEFT", b1, "RIGHT", 1)
    PWireStepper(m1, b1, p1, onChanged)
    b1:SetScript("OnEditFocusLost", onChanged)
    popup[key1] = b1

    local l2 = PFS(row, 12, PC.title)
    l2:SetPoint("LEFT", p1, "RIGHT", 18, 0)
    l2:SetText(label2)
    local m2 = PMakeStep(row, "-")
    m2:SetPoint("LEFT", l2, "RIGHT", 6, 0)
    local b2 = PMakeBox(row, 52)
    b2:SetPoint("LEFT", m2, "RIGHT", 1)
    local p2 = PMakeStep(row, "+")
    p2:SetPoint("LEFT", b2, "RIGHT", 1)
    PWireStepper(m2, b2, p2, onChanged)
    b2:SetScript("OnEditFocusLost", onChanged)
    popup[key2] = b2
end

local function PMakeCopyButton(popup, x, y, w, currentMode, onCopy)
    local b = PMakeTinyButton(popup, "Copy to", x, y, w, nil)
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(960)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    menu:SetBackdropColor(PC.panelBg[1], PC.panelBg[2], PC.panelBg[3], 0.98)
    menu:SetBackdropBorderColor(PC.panelEdge[1], PC.panelEdge[2], PC.panelEdge[3], 0.95)
    local S = _G.MSUF_EM2_Menu2Style
    if S and S.Shell then S.Shell(menu) end
    menu:Hide()

    local itemH = 22
    menu:SetSize(w, #GROUP_COPY_TARGETS * itemH + 6)
    for i, src in ipairs(GROUP_COPY_TARGETS) do
        local item = CreateFrame("Button", nil, menu)
        item:SetSize(w - 4, itemH)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))
        local bg = item:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        local fs = PFS(item, 10, (src.key == currentMode) and PC.muted or PC.white)
        fs:SetPoint("LEFT", 8, 0)
        fs:SetText(Tr(src.label))
        item:SetScript("OnEnter", function()
            bg:SetColorTexture(PC.btnHover[1], PC.btnHover[2], PC.btnHover[3], 0.22)
        end)
        item:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
        item:SetScript("OnClick", function()
            menu:Hide()
            if src.key ~= currentMode and onCopy then onCopy(src.key) end
            if b then
                if S and S.SetButtonText then S.SetButtonText(b, src.label)
                elseif b._label then b._label:SetText(Tr(src.label)) end
                if C_Timer and C_Timer.After then
                    C_Timer.After(1.2, function()
                        if S and S.SetButtonText then S.SetButtonText(b, "Copy to")
                        elseif b._label then b._label:SetText(Tr("Copy to")) end
                    end)
                end
            end
        end)
    end
    b:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide(); return end
        menu:ClearAllPoints()
        menu:SetPoint("TOP", b, "BOTTOM", 0, -3)
        menu:Show()
    end)
    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if b:IsMouseOver() or self:IsMouseOver() then
            self._closeTimer = nil
        else
            if not self._closeTimer then self._closeTimer = GetTime() + 0.35
            elseif GetTime() >= self._closeTimer then self:Hide() end
        end
    end)
    popup:HookScript("OnHide", function() menu:Hide() end)
    return b
end

local function RefreshAfterPopupApply(mode)
    local gf = GF()
    if not gf then return end

    if gf.MarkAllDirty then
        gf.MarkAllDirty(gf.DIRTY_ALL or 0x3F)
    elseif type(gf.RefreshAll) == "function" and not ConfigLocked() then
        gf.RefreshAll()
    elseif type(gf.RebuildAll) == "function" and not ConfigLocked() then
        gf.RebuildAll()
    elseif type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals()
    end

    if _em2Active then
        if _previewShownByEM2 and HasNativePreviewAPI(gf) then
            ShowPreviewOnly()
        else
            SyncContainer(mode)
        end
        _G.MSUF_GF_EM2_SetPreviewNudgeTarget(mode)
    end

    if C_Timer then
        C_Timer.After(0.05, function()
            local popup = _popups[mode]
            if popup and popup.IsShown and popup:IsShown() and popup.Sync then popup.Sync() end
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end
end

local function SetHUDStatus(text, kind)
    if type(_G.MSUF_EM2_SetHUDStatus) == "function" then
        _G.MSUF_EM2_SetHUDStatus(Tr(text), kind)
    end
end

local function GroupComponentForPage(pageKey)
    if pageKey == "gf_bars" then return "bars" end
    if pageKey == "gf_auras" then return "auras" end
    if pageKey == "gf_indicators" then return "status" end
    return "layout"
end

local function GroupSectionForPage(pageKey, component)
    if pageKey == "gf_bars" then
        if component == "power" then return "power" end
        if component == "name" or component == "hp" or component == "text" then return "text" end
        return "bars"
    elseif pageKey == "gf_auras" then
        return "buffs"
    elseif pageKey == "gf_indicators" then
        return "sicons"
    end
    return "layout"
end

function _G.MSUF_GF_EM2_ResetPosition(kind)
    kind = NormalizeKind(kind)
    if not kind then return false end
    if BlockConfigLocked() then return true end
    local conf = GetConf(kind)
    if not conf then return false end
    if _G.MSUF_EM_UndoBeforeChange then
        _G.MSUF_EM_UndoBeforeChange("gf", kind)
    end
    local x, y = GetDefaultCenter(kind)
    conf.offsetX = x
    conf.offsetY = y
    RefreshAfterPopupApply(kind)
    RefreshGFPositionUI(kind)
    SetHUDStatus("Reset group position", "ok")
    local key = KIND_TO_KEY[kind]
    if key and EM2.Focus and EM2.Focus.Pulse then
        EM2.Focus.Pulse(key, "layout", nil, { source = "group-reset", duration = 0.32 })
    end
    return true
end

local function BuildGFPopup(mode)
    local gf = GF()
    if not gf then return nil end

    local isRaid = (mode == "raid" or mode == "mythicraid")
    local title = (mode == "mythicraid") and "Mythic Raid Frames" or (isRaid and "Raid Frames" or "Party Frames")
    local popup = CreateFrame("Frame", "MSUF_EM2_GFPopup_" .. mode, UIParent, "BackdropTemplate")
    popup:SetSize(440, 282)
    popup:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(220)
    popup:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    popup:SetBackdropColor(PC.panelBg[1], PC.panelBg[2], PC.panelBg[3], 0.96)
    popup:SetBackdropBorderColor(PC.panelEdge[1], PC.panelEdge[2], PC.panelEdge[3], 0.95)
    do
        local S = _G.MSUF_EM2_Menu2Style
        if S and S.Shell then S.Shell(popup) end
    end
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:SetClampedToScreen(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(s) if not BlockConfigLocked() then s:StartMoving() end end)
    popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    local titleFS = PFS(popup, 15, PC.white)
    titleFS:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -18)
    titleFS:SetText(Tr(title))
    popup._titleFS = titleFS
    local subtitle = PFS(popup, 12, PC.muted)
    subtitle:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -8)
    subtitle:SetText(Tr("Frame bounds"))
    PMakeCloseButton(popup)

    local function Conf()
        return GetConf(mode)
    end

    local function Apply()
        if BlockConfigLocked() then return end
        local conf = Conf()
        if not conf then return end
        if _G.MSUF_EM_UndoBeforeChange then
            _G.MSUF_EM_UndoBeforeChange("gf", mode)
        end

        conf.offsetX = San(popup.xBox and popup.xBox:GetText(), conf.offsetX or 0)
        conf.offsetY = San(popup.yBox and popup.yBox:GetText(), conf.offsetY or 0)

        local w = popup.wBox and tonumber(popup.wBox:GetText())
        if w then conf.width = floor(max(40, min(400, w)) + 0.5) end
        local h = popup.hBox and tonumber(popup.hBox:GetText())
        if h then conf.height = floor(max(16, min(200, h)) + 0.5) end

        RefreshAfterPopupApply(mode)
        local key = KIND_TO_KEY[mode]
        if key and EM2.Focus and EM2.Focus.NotifyPositionChanged then
            EM2.Focus.NotifyPositionChanged(key, true)
        end
    end

    local function Sync()
        local conf = Conf()
        if not conf then return end
        local function S(box, value)
            if box and box.SetText then box:SetText(tostring(value or 0)) end
        end

        S(popup.xBox, San(conf.offsetX, 0))
        S(popup.yBox, San(conf.offsetY, 0))
        S(popup.wBox, conf.width or (isRaid and 80 or 120))
        S(popup.hBox, conf.height or (isRaid and 32 or 40))
    end

    popup.Sync = Sync
    popup.Apply = Apply

    local function OpenMenu2Page(pageKey)
        Apply()
        local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
        local key = KIND_TO_KEY[mode]
        pageKey = pageKey or "gf_layout"
        local component = GroupComponentForPage(pageKey)
        local sectionId = GroupSectionForPage(pageKey, component)
        if EM2.Focus and EM2.Focus.SetSelection then
            EM2.Focus.SetSelection(key, component, nil, { source = "group-popup", menu = false })
        end
        _G.MSUF_EM2_MenuFocusRequest = {
            key = key,
            component = component,
            pageKey = pageKey,
            sectionId = sectionId,
            source = "group-popup",
            explicit = true,
            changedAt = GetTime and GetTime() or 0,
        }
        if M then
            M.gfScope = mode
            if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("gfScope", mode) end
        end
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(mode) end
        popup:Hide()
        if M and pageKey and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
        if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
            _G.MSUF_OpenStandaloneOptionsWindow(pageKey)
        elseif type(_G.MSUF_OpenPage) == "function" then
            _G.MSUF_OpenPage(pageKey)
        elseif M and type(M.Open) == "function" then
            M.Open(pageKey)
        elseif M and type(M.SelectPage) == "function" then
            M.SelectPage(pageKey)
        end
    end

    local function OpenMenu2Settings()
        OpenMenu2Page("gf_layout")
    end

    local function CopyBoundsTo(targetMode)
        targetMode = NormalizeKind(targetMode)
        if not targetMode or targetMode == mode then return end
        Apply()
        local src = Conf()
        local dst = GetConf(targetMode)
        if not src or not dst then return end
        if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("gf", targetMode) end
        dst.offsetX = San(src.offsetX, 0)
        dst.offsetY = San(src.offsetY, 0)
        if src.width ~= nil then dst.width = floor(max(40, min(400, tonumber(src.width) or 120)) + 0.5) end
        if src.height ~= nil then dst.height = floor(max(16, min(200, tonumber(src.height) or 40)) + 0.5) end
        RefreshAfterPopupApply(targetMode)
        local targetKey = KIND_TO_KEY[targetMode]
        if targetKey and EM2.Focus and EM2.Focus.Pulse then
            EM2.Focus.Pulse(targetKey, "layout", nil, { source = "group-copy", duration = 0.32 })
        end
        SetHUDStatus("Copied group bounds", "ok")
        if popup and popup:IsShown() then Sync() end
    end

    local function ResetPosition()
        if BlockConfigLocked() then return end
        local conf = Conf()
        if not conf then return end
        if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("gf", mode) end
        conf.offsetX, conf.offsetY = 0, 0
        RefreshAfterPopupApply(mode)
        local key = KIND_TO_KEY[mode]
        if key and EM2.Focus and EM2.Focus.NotifyPositionChanged then
            EM2.Focus.NotifyPositionChanged(key, true)
        end
        if popup and popup:IsShown() then Sync() end
    end

    local function WireGroupFocus(btn, component)
        if not (btn and btn.HookScript) then return btn end
        btn:HookScript("OnEnter", function()
            local key = KIND_TO_KEY[mode]
            if key and EM2.Focus and EM2.Focus.SetHover then
                EM2.Focus.SetHover(key, component, nil, { source = "group-popup" })
            end
        end)
        btn:HookScript("OnLeave", function()
            if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("group-popup") end
        end)
        return btn
    end

    PMakeValuePair(popup, -72, "X", "xBox", "Y", "yBox", Apply)
    PMakeValuePair(popup, -102, "Width", "wBox", "Height", "hBox", Apply)

    WireGroupFocus(PMakeTinyButton(popup, "Layout", 20, -140, 66, function() OpenMenu2Page("gf_layout") end), "layout")
    WireGroupFocus(PMakeTinyButton(popup, "Bars", 98, -140, 58, function() OpenMenu2Page("gf_bars") end), "bars")
    WireGroupFocus(PMakeTinyButton(popup, "Auras", 168, -140, 68, function() OpenMenu2Page("gf_auras") end), "auras")
    WireGroupFocus(PMakeTinyButton(popup, "Status", 248, -140, 72, function() OpenMenu2Page("gf_indicators") end), "status")

    PMakeTinyButton(popup, "Open settings", 20, -190, 190, OpenMenu2Settings)
    PMakeCopyButton(popup, 224, -190, 190, mode, CopyBoundsTo)

    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(s, k)
        local ctrl = IsControlKeyDown and IsControlKeyDown()
        if k == "ESCAPE" then s:SetPropagateKeyboardInput(false); s:Hide()
        elseif ctrl and k == "Z" then
            s:SetPropagateKeyboardInput(false)
            if EM2.Undo then EM2.Undo.DoUndo() end
            if s._refreshUndoRedo then s._refreshUndoRedo() end
        elseif ctrl and (k == "Y" or k == "R") then
            s:SetPropagateKeyboardInput(false)
            if EM2.Undo then EM2.Undo.DoRedo() end
            if s._refreshUndoRedo then s._refreshUndoRedo() end
        else s:SetPropagateKeyboardInput(true) end
    end)
    popup:HookScript("OnHide", function(s)
        if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(true) end
        local function RefreshPopupFocus()
            local anyOpen = EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen()
            if not anyOpen then
                if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(false) end
                if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
            elseif EM2.Focus and EM2.Focus.RefreshPopupFocus then
                EM2.Focus.RefreshPopupFocus()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshPopupFocus) else RefreshPopupFocus() end
    end)

    local Quick = EM2.QuickPopup or (_G.MSUF_EM2_Menu2Style and _G.MSUF_EM2_Menu2Style.QuickPopup)
    if Quick and Quick.AddFooterControls then
        Quick.AddFooterControls(popup, { y = -230, onResetPosition = ResetPosition })
    end

    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(popup) end
    popup:Hide()
    return popup
end

local function ShowGFPopup(mode)
    mode = NormalizeKind(mode)
    if not mode then return end
    if not _popups[mode] then _popups[mode] = BuildGFPopup(mode) end
    local popup = _popups[mode]
    if not popup then return end
    _G.MSUF_GF_EM2_SetPreviewNudgeTarget(mode)
    popup.Sync()
    popup:Show()
    do
        local S = _G.MSUF_EM2_Menu2Style
        if S and S.FadeIn then S.FadeIn(popup, 0.12, 0.86, 1) end
    end
    if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(true) end
    if EM2.Focus and EM2.Focus.SetPopupFocus then EM2.Focus.SetPopupFocus(KIND_TO_KEY[mode], popup) end
end

local function HideGFPopup(mode)
    mode = NormalizeKind(mode)
    if not mode then return end
    if _popups[mode] then _popups[mode]:Hide() end
    local function RefreshFocus()
        if EM2.Focus and EM2.Focus.RefreshPopupFocus then EM2.Focus.RefreshPopupFocus() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, RefreshFocus) else RefreshFocus() end
end

_G.MSUF_EM2_ShowGFPopup = ShowGFPopup
_G.MSUF_EM2_HideGFPopup = HideGFPopup
_G.MSUF_EM2_SyncGFPopups = function()
    for _, popup in pairs(_popups) do
        if popup and popup.IsShown and popup:IsShown() and popup.Sync then
            popup.Sync()
        end
    end
end
_G.MSUF_EM2_GFPopupIsOpen = function()
    return (_popups.party and _popups.party:IsShown())
        or (_popups.raid and _popups.raid:IsShown())
        or (_popups.mythicraid and _popups.mythicraid:IsShown())
        or false
end

_G.MSUF_GF_EM2_ShowPreview = ShowPreviewOnly
_G.MSUF_GF_EM2_HidePreview = HidePreviewOnly
_G.MSUF_GF_EM2_IsPreviewShown = function()
    return _previewShownByEM2 == true
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if C_Timer then
        C_Timer.After(0.1, function()
            RegisterGF()
            InstallStateHooks()
            InstallHUDToggle()
            InstallRuntimeHooks()
            InstallCombatHooks()
        end)
    else
        RegisterGF()
        InstallStateHooks()
        InstallHUDToggle()
        InstallRuntimeHooks()
        InstallCombatHooks()
    end
end)
