-- Auras3 runtime: Platform.
-- Client capability checks and shared numeric/frame primitives. The loaded-addon latch belongs here; no aura payload is read.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Platform = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type

local FrameLayers = UF.Layers or {}
local DISPEL_OVERLAY_EFFECT_OFFSET = tonumber(FrameLayers.DISPEL_OVERLAY_EFFECT_OFFSET) or 12
-- Dispel/Purge border sensors share the Frame Outline's 0..30 Layer and the
-- Borders element's highlight detail (Layers.BorderOffset: 8 + (OVER_NATIVE_
-- DISPEL - NORMAL)), so the live Cleanse border lands exactly where the
-- Cleanse test border draws instead of the topmost Layer slot.
local BORDER_SENSOR_DETAIL = 8
    + ((tonumber(FrameLayers.FRAME_BORDER_OVER_NATIVE_DISPEL_OFFSET) or 50)
        - (tonumber(FrameLayers.FRAME_BORDER_NORMAL_OFFSET) or 35))
local AURA_ICON_BASE_OFFSET = tonumber(FrameLayers.AURA_ICON_BASE_OFFSET) or 64
local UNIT_AURA_BASE_OFFSET = tonumber(FrameLayers.UNIT_AURA_BASE_OFFSET) or 10
local FILE = "Auras3/Runtime/MSUF_Auras3_Runtime_Platform.lua"
local Require = MSUF.Require
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
--- Kernel next-frame queue. It dedupes by key and shares one OnUpdate, so a
--- burst of deferrals costs table stores instead of one C_Timer object each.
--- Exported by MSUF_Scheduler.lua, which loads long before Auras3.
local RunNextFrame = Require("MSUF_RunNextFrame", FILE)
local issecretvalue = issecretvalue
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ClampNumber, Clamp01

local EMPTY_EVENTS = {}
local AURA_CONTAINER_ADDON = "Blizzard_AuraContainer"
local MAX_CONFIGURABLE_DEBUFF_DURATION = 180
-- Blizzard's native maxDuration candidate filter also rejects duration == 0.
-- Use a practically unreachable finite ceiling so this behaves as an
-- "exclude permanent" rule without dropping normal long-duration auras.
local MAX_FINITE_AURA_DURATION = 2147483647
local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- NOTE: Inbound AuraContainer/AuraButton methods (SetEnabled, SetUnit,
-- AddAuraGroup/AddAuraSlot, SetIcon, ...)
-- are secure delegates. Call them directly from our code. Wrapping them does
-- not fix forbidden table access and makes PTR stack traces harder to reason
-- about.
--
-- 12.1 native containers own AuraButton creation and anchoring. MSUF does not create
-- AuraButton objects directly; all lane/sensor buttons are created by
-- AddAuraGroup/AddAuraSlot and customized in initializeFrame.

-- C_AddOns first; pre-C_AddOns clients keep the plain global.
local function AddOnLoaded(addonName)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(addonName) == true
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(addonName) == true
    end
    return false
end

local function EnsureBlizzardAuraContainerLoaded()
    if AddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if type(loadAddOn) ~= "function" then
        A3.nativeAuraRuntimeLoadError = "LoadAddOn API is unavailable"
        return false
    end

    local loaded, reason = loadAddOn(AURA_CONTAINER_ADDON)
    if loaded == true or AddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    A3.nativeAuraRuntimeLoadError = tostring(reason or loaded or "not loaded")
    return false
end

-- PTR 7 allows creating aura containers (and their batched AuraButtons)
-- during combat, so aura cold paths no longer wait for PLAYER_REGEN. The one
-- remaining hard blocker is demand-loading Blizzard_AuraContainer itself:
-- LoadAddOn is refused in combat. Addons never unload, so after the first
-- successful check this collapses to a single upvalue read -- combat identity
-- refreshes pay zero C calls here.
local _auraContainerLoadedOnce = false
local function AuraRuntimeCombatBlocked()
    if _auraContainerLoadedOnce then return false end
    if AddOnLoaded(AURA_CONTAINER_ADDON) then
        _auraContainerLoadedOnce = true
        return false
    end
    return InCombat()
end

-- PTR 7 global aura tooltip skinning: when the user runs MSUF's own unit-info
-- tooltips, restyle the shared AuraButtonTooltip to the same dark look so
-- aura hovers match; GAME-provider users keep Blizzard's default style.
-- SetTooltipBackdrop/ResetTooltipStyle are secure delegates: call directly.
local function ApplyAuraTooltipStyle()
    local inbound = AuraContainerInbound
    if not (inbound and type(inbound.SetTooltipBackdrop) == "function") then return end
    local general = MSUF_DB and MSUF_DB.general
    local wantMSUF = (general and general.unitTooltipProvider) == "MSUF"
    local applied = A3._auraTooltipStyleApplied
    if wantMSUF then
        if applied == "MSUF" then return end
        local createColor = CreateColor
        inbound.SetTooltipBackdrop({
            backdropInfo = {
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            },
            centerColor = createColor and createColor(0, 0, 0, 0.9) or nil,
        })
        A3._auraTooltipStyleApplied = "MSUF"
    elseif applied == "MSUF" and type(inbound.ResetTooltipStyle) == "function" then
        inbound.ResetTooltipStyle()
        A3._auraTooltipStyleApplied = "DEFAULT"
    end
end

local function Round(value)
    value = tonumber(value) or 0
    return math_floor(value + 0.5)
end

ClampNumber = function(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 0 end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

Clamp01 = function(value, fallback)
    return ClampNumber(value, fallback or 1, 0, 1)
end

local OutlineInCombat = MSUF.Util.InCombat
-- Read only the unit frame's published, public outline rectangle. Native AuraButtons
-- are sealed after initializeFrame; their position is never inspected to find a snap.
local function OutlineIconLane(lane)
    return lane and lane.anchor and (lane.initialAnchor or lane.visual == "icon") and not lane.portraitOverlay
        and lane.anchorTarget ~= "portrait" and not lane.auraBarFill and not lane.combinedAuraBarFlow
        and (lane.kind ~= "spellIndicator" or lane.visual == "icon") and not (lane.showDurationBar and lane.durationBarDisplay == "BAR_ONLY")
end

local function OutlineBounds(frame)
    return frame and (frame.MSUFNormalOutlineBounds or (UF.GetNormalOutlineBounds and UF.GetNormalOutlineBounds(frame)))
end

local function SnapSize(size, pixel, minimum)
    return math.max(minimum or 0, math_floor(size / pixel + .5)) * pixel
end

local function DisplaySize(size, runtimePixel, pixel, minimum)
    return SnapSize(SnapSize(size, runtimePixel, minimum), pixel, minimum)
end

local function IsSingleIconSlot(lane)
    return (lane.max == 1 and not lane.weaponEnchants and not lane.customPriority)
        or (not lane.initialAnchor and lane.visual == "icon")
end

-- The preview magnifies the real icon and pad after runtime quantization. A fixed
-- AuraSlot attaches its button directly at the configured point, without flow padding.
local function LaneMetrics(lane, pixel, zoom)
    local runtimePixel = pixel * (zoom or 1)
    local single = IsSingleIconSlot(lane)
    local width = DisplaySize(lane.buttonWidth or (single and lane.width) or lane.size or 1, runtimePixel, pixel, 1)
    local height = DisplaySize(lane.buttonHeight or (single and lane.height) or lane.size or 1, runtimePixel, pixel, 1)
    local gap = lane.fixedIconGrid and lane.fixedIconGrid.spacing or lane.spacing or 0
    if gap ~= 0 then
        gap = (gap < 0 and -1 or 1) * DisplaySize(math.abs(gap), runtimePixel, pixel, 1)
    end
    if single then return width, height, 0, gap, width, height end
    return width, height, DisplaySize(lane.padding or 0, runtimePixel, pixel), gap,
        DisplaySize(lane.width or width, runtimePixel, pixel, 1), DisplaySize(lane.height or height, runtimePixel, pixel, 1)
end

function A3.OutlineLaneMetrics(frame, lane, zoom)
    if not OutlineIconLane(lane) or OutlineInCombat() then return end
    local bounds = OutlineBounds(frame)
    if bounds and bounds.pixelSize then return LaneMetrics(lane, bounds.pixelSize, zoom) end
end

local function HardIconOutset(lane, pixel)
    local style = lane.iconStyle
    if not style then return 0, 0 end
    local shape = lane.iconShape or A3.IconShape.RECTANGLE
    local skin = style.skin
    if skin and skin.def and shape == skin.def.shape then
        if skin.a == 0 then return 0, 0 end
        -- Paint computes layer extents from the configured icon's two requested sides.
        local width = lane.buttonWidth or (not lane.initialAnchor and lane.width) or lane.size
        local height = lane.buttonHeight or (not lane.initialAnchor and lane.height) or lane.size
        local x, y = A3.IconSkins.Outset(skin, width, height)
        return SnapSize(x, pixel), SnapSize(y, pixel)
    end
    if not style.borderEnabled or style.borderA == 0 then return 0, 0 end
    local extent = style.borderThickness or 1
    if shape ~= A3.IconShape.RECTANGLE then
        local media = A3.IconShape.MEDIA[shape]
        if not media or (style.borderPlacement == "inner" and not media.borderOuterOnly) then return 0, 0 end
        extent = math.min(8, math.max(1, math_floor(extent + .5)))
    elseif style.borderTexture then
        if style.borderPlacement == "inner" then return 0, 0 end
        extent = math.max(1, style.borderEdge or 8) * .5
    end
    extent = SnapSize(extent, pixel)
    return extent, extent
end

-- Test the first icon's outside edges against the corresponding edge of the
-- owner. Only the closest integer setting denotes flush; its neighbours retain
-- their normal nudge distance. A centred axis keeps its manual offset.
local function EdgeJoins(anchor, start, host, icon, pad, outset, edge)
    local low = (start - anchor) * host + (1 - 2 * start) * pad - start * icon
    return edge - low + outset, edge - low - icon - outset
end

local function SolveAxis(saved, anchor, start, edge, host, icon, pad, outset,
    band, runtimeHost, runtimeIcon, runtimePad, runtimeOutset)
    if anchor == .5 then return end
    local nominal = anchor == 0 and -band or band
    local low, high = EdgeJoins(anchor, start, runtimeHost, runtimeIcon, runtimePad, runtimeOutset, nominal)
    local joinLow, joinHigh = EdgeJoins(anchor, start, host, icon, pad, outset, edge)
    if saved == math_floor(low + .5) then return joinLow end
    if saved == math_floor(high + .5) then return joinHigh end
end

local function NativeOffset(value, pixel)
    if value < 0 then return -SnapSize(-value, pixel) end
    return SnapSize(value, pixel)
end

local function UsesOutlineAnchor(lane)
    return OutlineIconLane(lane) and (lane.anchor ~= "CENTER" or lane.fixedIconGrid ~= nil)
end

function A3.ResolveOutlineLaneOffset(frame, lane, x, y, zoom)
    if not UsesOutlineAnchor(lane) or OutlineInCombat() then return x, y, false end
    local bounds = OutlineBounds(frame)
    local pixel = bounds and bounds.pixelSize
    if not pixel then return x, y, false end
    local grid = lane.fixedIconGrid
    if grid then x, y = grid.x, grid.y end
    local w, h, pad, gap, hostW, hostH = LaneMetrics(lane, pixel, zoom)
    local runtimePixel = pixel * (zoom or 1)
    -- Dispel symbols are manually positioned. Only their size and pitch
    -- follow the pixel grid; their origin never docks to the frame outline.
    if lane.kind == "dispelSymbol" and grid then
        return NativeOffset(NativeOffset(x, runtimePixel), pixel) + grid.col * (w + gap),
            NativeOffset(NativeOffset(y, runtimePixel), pixel) + grid.row * (h + gap), true
    end
    local ox, oy = HardIconOutset(lane, pixel)
    local rw, rh, rp, rHostW, rHostH, rx, ry = w, h, pad, hostW, hostH, ox, oy
    if runtimePixel ~= pixel then
        rw, rh, rp, _, rHostW, rHostH = LaneMetrics(lane, runtimePixel)
        rx, ry = HardIconOutset(lane, runtimePixel)
    end
    local band = bounds.runtimeOutset or 0
    local ax, ay = A3.AnchorOffset(lane.anchor, 1, 1)
    local gx, gy = A3.AnchorOffset(lane.initialAnchor or lane.anchor, 1, 1)
    -- Which saved integer denotes flush is independent of the preview's zoom
    -- and the frame's fractional screen origin. Only the rendered offset follows these.
    local dx = SolveAxis(x, ax, gx, ax == 0 and bounds.leftOffset or bounds.rightOffset,
        hostW, w, pad, ox, band, rHostW, rw, rp, rx)
    local dy = SolveAxis(y, ay, gy, ay == 0 and bounds.bottomOffset or bounds.topOffset,
        hostH, h, pad, oy, band, rHostH, rh, rp, ry)
    if grid then
        -- The first reminder docks like a single icon. All following cells
        -- advance by that icon's rendered size plus the configured pixel gap.
        local baseX = dx or NativeOffset(NativeOffset(x, runtimePixel), pixel)
        local baseY = dy or NativeOffset(NativeOffset(y, runtimePixel), pixel)
        return baseX + grid.col * (w + gap), baseY + grid.row * (h + gap), true
    end
    if dx == nil and dy == nil then return x, y, false end
    return dx or NativeOffset(x, pixel), dy or NativeOffset(y, pixel), true
end

local SetRoundLayout = Require("MSUF_SetRoundLayoutToNearestPixel", FILE)
local function PlaceLaneHost(host, frame, lane, forcePlacement)
    if forcePlacement then
        host._msufA3PlacedParent, host._msufA3PlacedWidth = nil, nil
    end
    local bounds = frame.MSUFNormalOutlineBounds
    local signature = lane._msufA3LayoutSignature
    if host._msufA3PlacedLayout == lane and host._msufA3PlacedSignature == signature
        and host._msufA3PlacedParent == frame and host._msufA3PlacedBounds == bounds
        and host._msufA3PlacedRevision == (bounds and bounds.revision) then return end
    local x, y, solved = A3.ResolveOutlineLaneOffset(frame, lane, lane.x or 0, lane.y or 0)
    local width, height = lane.width or lane.size or 1, lane.height or lane.size or 1
    if IsSingleIconSlot(lane) and OutlineIconLane(lane) then
        width, height = lane.buttonWidth or lane.width or lane.size, lane.buttonHeight or lane.height or lane.size
    end
    if solved then
        local _, _, _, _, w, h = LaneMetrics(lane, frame.MSUFNormalOutlineBounds.pixelSize)
        width, height = w, h
    end
    if host._msufA3ManualOutline == true then
        if not solved then SetRoundLayout(host, true) end
    elseif solved then
        SetRoundLayout(host, false)
    end
    bounds = frame.MSUFNormalOutlineBounds
    host._msufA3PlacedLayout, host._msufA3PlacedSignature = lane, signature
    host._msufA3PlacedBounds, host._msufA3PlacedRevision = bounds, bounds and bounds.revision
    host._msufA3ManualOutline = solved
    if host._msufA3PlacedParent ~= frame or host._msufA3PlacedAnchor ~= lane.anchor
        or host._msufA3PlacedX ~= x or host._msufA3PlacedY ~= y then
        host:ClearAllPoints()
        host:SetPoint(lane.anchor, frame, lane.anchor, x, y)
        host._msufA3PlacedParent, host._msufA3PlacedAnchor = frame, lane.anchor
        host._msufA3PlacedX, host._msufA3PlacedY = x, y
    end
    if host._msufA3PlacedWidth ~= width or host._msufA3PlacedHeight ~= height then
        host:SetSize(width, height)
        host._msufA3PlacedWidth, host._msufA3PlacedHeight = width, height
    end
    if not UsesOutlineAnchor(lane) or not frame.MSUFSpec then
        local registry, key = host._msufA3OutlineRegistry, host._msufA3OutlineKey
        if registry and registry[key] == host then registry[key] = nil end
        host._msufA3OutlineLane, host._msufA3OutlineRegistry, host._msufA3OutlineKey = nil, nil, nil
    end
end

local function QueueOutlineRestore(frame, rebuild)
    local pending = A3._pendingOutlineOwners
    if not pending then
        pending = {}
        A3._pendingOutlineOwners = pending
        A3.Runtime.Facade.EnsureDeferredAuraRuntimeDriver():RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if rebuild then
        local containers = pending[frame]
        if type(containers) ~= "table" then
            containers = {}
            pending[frame] = containers
        end
        containers[rebuild] = true
    elseif not pending[frame] then
        pending[frame] = true
    end
end

local function BindLaneHost(host, frame, lane, key, forcePlacement)
    key = key or lane.rootKey or lane.kind
    if not host._msufA3OutlineLane and not (key and frame.MSUFSpec and UsesOutlineAnchor(lane)) then
        host:ClearAllPoints()
        host:SetPoint(lane.anchor, frame, lane.anchor, lane.x, lane.y)
        host:SetSize(lane.width, lane.height)
        return
    end
    local previous = host._msufA3OutlineRegistry
    if previous and (previous ~= frame._msufA3OutlineLaneHosts or host._msufA3OutlineKey ~= key)
        and previous[host._msufA3OutlineKey] == host then previous[host._msufA3OutlineKey] = nil end
    local hosts = frame._msufA3OutlineLaneHosts
    if not hosts then
        hosts = {}
        frame._msufA3OutlineLaneHosts = hosts
    end
    host._msufA3OutlineKey, host._msufA3OutlineRegistry = key, hosts
    host._msufA3OutlineLane = lane
    hosts[key] = host
    if OutlineInCombat() then
        QueueOutlineRestore(frame)
        -- Existing proxies retain their last anchors until regen. A new ordinary
        -- host uses the pre-existing raw placement while its native pool starts.
        if not host._msufA3PlacedParent and (not host.IsProtected or not host:IsProtected()) then
            host:SetPoint(lane.anchor, frame, lane.anchor, lane.x, lane.y)
            host:SetSize(lane.width or lane.size, lane.height or lane.size)
            host._msufA3PlacedParent = frame
        end
        host._msufA3PlacedLayout = nil
        return
    end
    PlaceLaneHost(host, frame, lane, forcePlacement)
end

-- Allocate at owner creation/configuration. Native initializeFrame captures this
-- reference and never needs to read geometry when Blizzard expands its pool.
local PixelLayoutRegion = Require("MSUF_PixelLayoutRegion", FILE)
function A3.ResolveOutlineSlotAnchor(frame, slot, key, container)
    if not (frame and frame.MSUFSpec and key and UsesOutlineAnchor(slot)) then
        return frame, slot.x, slot.y
    end
    local proxies = frame._msufA3OutlineSlotProxies
    local proxy = proxies and proxies[key]
    if not proxy then
        if OutlineInCombat() then
            -- Its original fixed attachment remains valid in combat. Only the
            -- native owner born without this proxy needs replacement after regen.
            QueueOutlineRestore(frame, container)
            return frame, slot.x, slot.y
        end
        if not proxies then
            proxies = {}
            frame._msufA3OutlineSlotProxies = proxies
        end
        proxy = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        proxies[key] = proxy
    end
    if container then proxy._msufA3OutlineOwner = container end
    BindLaneHost(proxy, frame, slot, key)
    if container then
        local slots = container._msufA3OutlineSlotLanes
        if not slots then
            slots = {}
            container._msufA3OutlineSlotLanes = slots
        end
        slots[key] = slot
    end
    return proxy, 0, 0
end

function A3.RefreshOutlineLaneAnchors(frame)
    local hosts = frame._msufA3OutlineLaneHosts
    if not hosts or OutlineInCombat() then return end
    local bounds = frame.MSUFNormalOutlineBounds
    local pixel = bounds and bounds.pixelSize
    for key, host in pairs(hosts) do
        local owner = host._msufA3OutlineOwner or host._msufA3FlowContainer
        if owner and owner._msufA3OutlineRetired then
            hosts[key] = nil
        else
            PlaceLaneHost(host, frame, host._msufA3OutlineLane)
            local flow = host._msufA3FlowContainer
            if flow and pixel and host._msufA3OutlineGridPixel ~= pixel then
                host._msufA3OutlineGridPixel = pixel
                if flow._msufA3NativeRegistered and flow._msufA3FlowPixel then
                    local nextPixel = A3.Runtime.ButtonVisuals.GridPixel(flow)
                    if nextPixel and nextPixel ~= flow._msufA3FlowPixel then
                        A3.Runtime.Containers.RefreshFlowOwner(flow, flow._msufA3NativeLaneConfig)
                    end
                end
            end
        end
    end
end

local NormalizeFrameStrata = Require("MSUF_NormalizeFrameStrata", FILE)

local ReadParentFrameStrata = Require("MSUF_AuraReadParentFrameStrata", FILE)

local function ResolveFrameStrata(parentFrame, value)
    -- Legacy per-element strata cannot bypass the universal 0..30 order.
    return ReadParentFrameStrata(parentFrame)
end

local SyncFrameStrata = Require("MSUF_AuraSyncFrameStrata", FILE)

return {
    AURA_CONTAINER_ADDON = AURA_CONTAINER_ADDON,
    AURA_ICON_BASE_OFFSET = AURA_ICON_BASE_OFFSET,
    BindLaneHost = BindLaneHost,
    OutlineIconLane = OutlineIconLane,
    ApplyAuraTooltipStyle = ApplyAuraTooltipStyle,
    AuraRuntimeCombatBlocked = AuraRuntimeCombatBlocked,
    BORDER_SENSOR_DETAIL = BORDER_SENSOR_DETAIL,
    C_Timer = C_Timer,
    Clamp01 = Clamp01,
    ClampNumber = ClampNumber,
    CreateFrame = CreateFrame,
    DISPEL_OVERLAY_EFFECT_OFFSET = DISPEL_OVERLAY_EFFECT_OFFSET,
    EMPTY_EVENTS = EMPTY_EVENTS,
    EnsureBlizzardAuraContainerLoaded = EnsureBlizzardAuraContainerLoaded,
    FrameLayers = FrameLayers,
    InCombat = InCombat,
    MAX_CONFIGURABLE_DEBUFF_DURATION = MAX_CONFIGURABLE_DEBUFF_DURATION,
    MAX_FINITE_AURA_DURATION = MAX_FINITE_AURA_DURATION,
    NormalizeFrameStrata = NormalizeFrameStrata,
    ReadParentFrameStrata = ReadParentFrameStrata,
    ResolveFrameStrata = ResolveFrameStrata,
    Round = Round,
    RunNextFrame = RunNextFrame,
    STANDARD_TEXT_FONT = STANDARD_TEXT_FONT,
    SyncFrameStrata = SyncFrameStrata,
    UNIT_AURA_BASE_OFFSET = UNIT_AURA_BASE_OFFSET,
    issecretvalue = issecretvalue,
}
end
