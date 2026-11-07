--- EditMode/MSUF_EditMode_Layout.lua - Edit Mode drag ticker
--- Resolves each element's anchor, applies drags to units, castbars, group
--- frames, resources and external elements, and batches the idle mover and
--- toolbar syncs. Loads last of the layout family (Grid, Snap, Nudge).
local _, MSUF = ...
local MAX_ARENA_FRAMES = MSUF.Require("MSUF", "Shell/EditMode/MSUF_EditMode_Layout.lua").Client.MaxArenaOpponents
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing. Boss geometry resolves its existing Factory owner; other
-- legacy providers retain their global hook boundary.
local CALLER = "Shell/EditMode/MSUF_EditMode_Layout.lua"
-- Drag-path collaborators (castbars, group popups, the Factory boss geometry)
-- load after Edit Mode and are never hooked: each is required on its first
-- use and kept, so a drag tick makes no lookup call.
local DragProviders = {}

local EM2 = MSUF.Optional("MSUF_EM2")
if not EM2 then return end

local max   = math.max
local min   = math.min
local abs   = math.abs
local U     = EM2.Util or {}
local round = U.Round

local RefreshUFPreview       = U.RefreshUFPreview
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local IsConfigCombatLocked   = U.IsConfigCombatLocked
local GetFrameEdgesUI        = EM2.Snap.GetFrameEdgesUI
local GetCastbarOffsetKeys   = EM2.Nudge.GetCastbarOffsetKeys

local function NotifyGuidedEditModeMoved(key)
    local menu = MSUF.MSUF2
    if menu and type(menu.NotifyGuidedEditModeMoved) == "function" then
        return menu.NotifyGuidedEditModeMoved(key)
    end
    local tour = MSUF.GuidedTour6
    if tour and type(tour.MarkEditModePlacementComplete) == "function" then
        return tour:MarkEditModePlacementComplete(key)
    end
    return false
end

--- Group drag commits re-apply their kind's geometry (EditMode_Core Util).
local function RefreshGroupGeometryScoped(kind)
    return U.RefreshGroupGeometryScoped(kind, "EM2_LAYOUT_GROUP_GEOMETRY")
end

local Ticker = {}
EM2.Ticker = Ticker
local Kinds = MSUF.EditModeKinds
local Driver = MSUF.EditModeDragDriver

local format = string.format

local function PointXY(fr, p)
    if not fr or not p then return nil, nil end
    if p == "CENTER" then return fr:GetCenter() end
    local l, r, t, b = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
    if not (l and r and t and b) then return nil, nil end
    local cx, cy = (l + r) * 0.5, (t + b) * 0.5
    if p == "TOPLEFT" then return l, t end
    if p == "TOP" then return cx, t end
    if p == "TOPRIGHT" then return r, t end
    if p == "LEFT" then return l, cy end
    if p == "RIGHT" then return r, cy end
    if p == "BOTTOMLEFT" then return l, b end
    if p == "BOTTOM" then return cx, b end
    if p == "BOTTOMRIGHT" then return r, b end
    return fr:GetCenter()
end

local function PointOffsetFromCenter(point, width, height)
    local x, y = 0, 0
    width = width or 0
    height = height or 0
    if point and point:find("LEFT", 1, true) then
        x = width * -0.5
    elseif point and point:find("RIGHT", 1, true) then
        x = width * 0.5
    end
    if point and point:find("TOP", 1, true) then
        y = height * 0.5
    elseif point and point:find("BOTTOM", 1, true) then
        y = height * -0.5
    end
    return x, y
end

local function ClampCenterAxis(center, halfSize, screenSize)
    center = tonumber(center) or 0
    halfSize = max(0, tonumber(halfSize) or 0)
    screenSize = max(0, tonumber(screenSize) or 0)
    if screenSize <= 0 then return center end
    local minCenter = halfSize
    local maxCenter = screenSize - halfSize
    if minCenter > maxCenter then
        minCenter, maxCenter = maxCenter, minCenter
    end
    return max(minCenter, min(maxCenter, center))
end

local VALID_UNIT_POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function UnitFramePoint(conf)
    local point = conf and conf.point or "CENTER"
    if not VALID_UNIT_POINTS[point] then point = "CENTER" end
    return point
end

local function UnitFrameRelativePoint(conf, point)
    local relativePoint = conf and conf.relativePoint or point or "CENTER"
    if not VALID_UNIT_POINTS[relativePoint] then relativePoint = point or "CENTER" end
    return relativePoint
end

local function ApplyFramePoint(frame, point, anchor, relativePoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, anchor, relativePoint, x, y)
end

local function IsExternalEditAnchor(anchor)
    if anchor == nil or anchor == UIParent or anchor == WorldFrame then return false end
    return anchor._msufOwnedAnchorRoot ~= true
end

--- A drag onto an external anchor captures its rollback points every tick:
--- one flat scratch array (5 slots per point, .n points) consumed within the
--- same TryApplyFramePoint call, so no tick allocates.
local rollbackPoints = { n = 0 }

local function CaptureFramePoints(frame)
    if not (frame and frame.GetPoint) then return nil end
    local count = 1
    if frame.GetNumPoints then count = tonumber(frame:GetNumPoints()) or 0 end
    local points, n = rollbackPoints, 0
    for i = 1, count do
        local point, anchor, relativePoint, x, y = frame:GetPoint(i)
        if point then
            local slot = n * 5
            n = n + 1
            points[slot + 1], points[slot + 2], points[slot + 3] = point, anchor, relativePoint
            points[slot + 4], points[slot + 5] = x, y
        end
    end
    points.n = n
    return points
end

local function RestoreFramePoints(frame, points)
    if not (frame and points) then return false end
    frame.ClearAllPoints(frame)

    for i = 1, points.n do
        local slot = (i - 1) * 5
        frame:SetPoint(points[slot + 1], points[slot + 2], points[slot + 3], points[slot + 4], points[slot + 5])
    end
    return true
end

local function TryApplyFramePoint(frame, point, anchor, relativePoint, x, y)
    if not (frame and anchor) then return false end
    -- A drag tick must never straddle combat with a protected frame mutation.
    -- The edit-mode driver stops on PLAYER_REGEN_DISABLED as well, but this
    -- guard closes the event/ticker boundary itself.
    if InCombatLockdown and InCombatLockdown() then return false end

    -- External anchors stay live out of combat so the frame follows provider
    -- movement; the Factory combat-edge freeze severs the link for combat.
    -- Positioning onto one is still transactional: keep the previous points so
    -- an unresolvable provider chain can be rolled back atomically.
    local externalAnchor = IsExternalEditAnchor(anchor)
    local rollbackPoints
    if externalAnchor then
        rollbackPoints = CaptureFramePoints(frame)
        if not rollbackPoints then return false end
    end

    ApplyFramePoint(frame, point, anchor, relativePoint, x, y)

    if not externalAnchor then return true end

    -- Accept the live link only when the provider chain resolves to a real
    -- screen rect; a rectless chain would render the frame nowhere.
    if frame.GetCenter and frame:GetCenter() ~= nil then return true end
    RestoreFramePoints(frame, rollbackPoints)
    return false
end

local function SetStackedPreviewPosition(unitPrefix, count, layoutDelta, point, anchor, relativePoint, x, y, conf, rollbackX, rollbackY)
    local uf = MSUF and MSUF.UF
    local frames = uf and uf.frames
    local moved = false
    for i = 1, count do
        local unit = unitPrefix .. i
        local frame = (frames and frames[unit]) or MSUF.Optional("MSUF_" .. unit)
        if frame then
            local dx, dy = layoutDelta(i, conf)
            frame._msufDragActive = true
            if not TryApplyFramePoint(frame, point, anchor, relativePoint, x + (dx or 0), y + (dy or 0)) then
                if rollbackX ~= nil and rollbackY ~= nil then
                    for restoreIndex = 1, count do
                        local restoreUnit = unitPrefix .. restoreIndex
                        local restoreFrame = (frames and frames[restoreUnit]) or MSUF.Optional("MSUF_" .. restoreUnit)
                        if restoreFrame then
                            local restoreDX, restoreDY = layoutDelta(restoreIndex, conf)
                            TryApplyFramePoint(restoreFrame, point, anchor, relativePoint,
                                rollbackX + (restoreDX or 0), rollbackY + (restoreDY or 0))
                            local applyGeometry = DragProviders.bossGeometry
                            if not applyGeometry then
                                applyGeometry = MSUF.Require("ApplyBossPhysicalBarGeometry", CALLER, MSUF.UF.Factory)
                                DragProviders.bossGeometry = applyGeometry
                            end
                            applyGeometry(restoreFrame)
                        end
                    end
                end
                return false
            end
            local applyGeometry = DragProviders.bossGeometry
            if not applyGeometry then
                applyGeometry = MSUF.Require("ApplyBossPhysicalBarGeometry", CALLER, MSUF.UF.Factory)
                DragProviders.bossGeometry = applyGeometry
            end
            applyGeometry(frame)
            moved = true
        end
    end
    return moved
end

--- Drag-frame hot path: the unit-frame config publishes both layout deltas
--- once, after Edit Mode loads, so each is bound on its first use.
local bossLayoutDelta, arenaLayoutDelta

local function SetBossPreviewPosition(point, anchor, relativePoint, x, y, conf, rollbackX, rollbackY)
    bossLayoutDelta = bossLayoutDelta or MSUF.Require("MSUF_GetBossLayoutDelta", CALLER)
    return SetStackedPreviewPosition("boss", 5, bossLayoutDelta,
        point, anchor, relativePoint, x, y, conf, rollbackX, rollbackY)
end

local function SetArenaPreviewPosition(point, anchor, relativePoint, x, y, conf, rollbackX, rollbackY)
    arenaLayoutDelta = arenaLayoutDelta or MSUF.Require("MSUF_GetArenaLayoutDelta", CALLER)
    return SetStackedPreviewPosition("arena", tonumber(MAX_ARENA_FRAMES) or 3, arenaLayoutDelta,
        point, anchor, relativePoint, x, y, conf, rollbackX, rollbackY)
end

local function UnitDragOffsets(d, centerX, centerY, uiScale, frameScale)
    local ax, ay = PointXY(d.anchor, d.relativePoint)
    local fallback = ax == nil or ay == nil
    if fallback then
        ax, ay = d.unitAnchorPX, d.unitAnchorPY
    else
        local anchorScale = d.anchor == UIParent and uiScale or (d.anchor.GetEffectiveScale and d.anchor:GetEffectiveScale()) or 1
        ax, ay = ax * anchorScale, ay * anchorScale
        d.unitAnchorPX, d.unitAnchorPY = ax, ay
    end
    local dx, dy = 0, 0
    if d.point ~= "CENTER" then
        dx, dy = PointOffsetFromCenter(d.point, d.bar:GetWidth(), d.bar:GetHeight())
    end
    local x = (centerX * uiScale - ax) / frameScale
        + d.unitCenterDX + dx - d.unitBaseX + d.unitBiasX
    local y = (centerY * uiScale - ay) / frameScale
        + d.unitCenterDY + dy - d.unitBaseY + d.unitBiasY
    return d.unitStartX + round(x - d.unitStartX), d.unitStartY + round(y - d.unitStartY), fallback
end

-- Clicking to select must not snap or save a frame before the pointer moves.
local function UnitDragHasCursorMotion(d, x, y)
    if d.unitCursorMoved ~= false then return true end
    if abs(x - d.unitCursorPX) <= 4 and abs(y - d.unitCursorPY) <= 4 then return false end
    d.unitCursorMoved = true
    return true
end

local function UpdateUnitDragBounds(d, uiScale)
    if d.unitGeometryScale == nil then return nil end
    local scale = d.bar:GetEffectiveScale()
    if not scale or scale <= 0 then return nil end
    local relativeScale = scale / uiScale
    if relativeScale ~= d.unitGeometryScale then
        local ratio = relativeScale / d.unitGeometryScale
        d.halfW, d.halfH = d.halfW * ratio, d.halfH * ratio
        d.mover:SetSize(d.halfW * 2, d.halfH * 2)
        d.unitGeometryScale = relativeScale
    end
    return scale
end

local function ApplyUnitDragPosition(d, centerX, centerY, uiScale, phase, frameScale)
    if not (d and d.bar and d.conf and d.anchor) then return false end
    frameScale = frameScale or (d.bar.GetEffectiveScale and d.bar:GetEffectiveScale()) or 1
    if frameScale <= 0 then frameScale = 1 end
    uiScale = tonumber(uiScale) or 1
    if uiScale <= 0 then uiScale = 1 end

    local currentCX = tonumber(centerX) or d.startCX or 0
    local currentCY = tonumber(centerY) or d.startCY or 0
    local nextX, nextY, fallback = UnitDragOffsets(d, currentCX, currentCY, uiScale, frameScale)
    if nextX == nil then return false end
    if d.lastUnitX == nextX and d.lastUnitY == nextY and d.unitAnchorFallback == fallback then return true end

    local previousX = d.lastUnitX
    local previousY = d.lastUnitY
    if previousX == nil then previousX = d.unitStartX or 0 end
    if previousY == nil then previousY = d.unitStartY or 0 end

    local point, anchor, relativePoint = d.point, d.anchor, d.relativePoint
    local baseX, extraY = d.unitBaseX, d.unitBaseY
    if fallback then
        anchor, relativePoint = UIParent, "BOTTOMLEFT"
        baseX, extraY = baseX + d.unitAnchorPX / frameScale, extraY + d.unitAnchorPY / frameScale
    end
    local placedX, placedY = baseX + nextX, extraY + nextY
    local rollbackX, rollbackY = baseX + previousX, extraY + previousY
    local positioned
    if d.isBossLayout then
        positioned = SetBossPreviewPosition(point, anchor, relativePoint,
            placedX, placedY, d.conf, rollbackX, rollbackY)
    elseif d.isArenaLayout then
        positioned = SetArenaPreviewPosition(point, anchor, relativePoint,
            placedX, placedY, d.conf, rollbackX, rollbackY)
    else
        positioned = TryApplyFramePoint(d.bar, point, anchor, relativePoint, placedX, placedY)
    end
    if not positioned then
        if not (d.isBossLayout or d.isArenaLayout) then
            TryApplyFramePoint(d.bar, point, anchor, relativePoint, rollbackX, rollbackY)
        end
        return false
    end

    d.conf.offsetX = nextX
    d.conf.offsetY = nextY
    d.unitPositionChanged, d.unitAnchorFallback = true, fallback
    if d.anchor == UIParent and d.conf.screenPositionMode == "relativeHeight" then
        local height = UIParent:GetHeight()
        if height >= 400 and height <= 10000 then d.conf.screenPositionHeight = height end
    end
    d.lastUnitX = nextX
    d.lastUnitY = nextY
    return true
end

local function ApplySubframeDragPosition(d, centerX, centerY, uiScale)
    if not (d and d.bar and d.conf and d.cfg and d.cfg.subframeOffsetXKey) then return false end
    local scale = d.bar.GetEffectiveScale and d.bar:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    local nextX = (d.subframeStartX or 0) + round(((centerX or d.startCX) - d.startCX) * uiScale / scale)
    local nextY = (d.subframeStartY or 0) + round(((centerY or d.startCY) - d.startCY) * uiScale / scale)
    local xKey, yKey = d.cfg.subframeOffsetXKey, d.cfg.subframeOffsetYKey
    if d.lastSubframeX == nextX and d.lastSubframeY == nextY then return true end

    -- Preserve the live Player or Class Resource anchor. Only the owner's own
    -- offset changes, so a bound Energy bar follows Combo Points while either
    -- bar can still be dragged independently.
    local point, anchor, relativePoint, x, y = d.bar:GetPoint(1)
    if not point then return false end
    anchor = anchor or d.bar:GetParent()
    relativePoint = relativePoint or point
    if not anchor then return false end
    local dx = nextX - (d.lastSubframeX or d.subframeStartX or 0)
    local dy = nextY - (d.lastSubframeY or d.subframeStartY or 0)
    if not TryApplyFramePoint(d.bar, point, anchor, relativePoint, (x or 0) + dx, (y or 0) + dy) then return false end
    d.conf[xKey], d.conf[yKey] = nextX, nextY
    if d.cfg.resourceKind == "classpower" and dy ~= 0 then
        d.conf.classPowerCooldownTopAnchor = true
    end
    d.lastSubframeX, d.lastSubframeY = nextX, nextY
    return true
end

local GROUP_VALID_POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function ResolveGroupAnchor(conf, owner)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.ResolveAnchorFrame) == "function" then
        return gf.ResolveAnchorFrame(conf, owner)
    end
    return UIParent
end

local function GroupAnchorPoint(conf)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.GetAnchorPoint) == "function" then return gf.GetAnchorPoint(conf) end
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not GROUP_VALID_POINTS[point] then point = "CENTER" end
    return point
end

--- Both sides of a group anchor come from the single visible Anchor Point; see
--- GF.ResolveAnchorPoint (MSUF_GroupFrames_DB.lua) for the legacy pair it retires.
local function GroupAnchorPoints(kind, conf, parent)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.ResolveAnchorPoint) == "function" then
        return gf.ResolveAnchorPoint(kind, conf, parent)
    end
    local point = GroupAnchorPoint(conf)
    return point, point
end

local function GroupOffsetFromCenter(bar, conf, centerX, centerY, gridDX, gridDY)
    local owner = bar and (bar._msufGFLiveAnchor or bar._msufGFLogicalAnchor or bar) or nil
    local anchor = ResolveGroupAnchor(conf, owner)
    local point, relativePoint = GroupAnchorPoints(bar and bar._msufGFKind, conf, anchor)
    local ax, ay = PointXY(anchor, relativePoint)
    if not (ax and ay) then
        ax = ((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0) * 0.5
        ay = ((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0) * 0.5
    end

    local bw = tonumber(bar and bar._msufGFGridWidth) or (bar and bar.GetWidth and bar:GetWidth()) or 0
    local bh = tonumber(bar and bar._msufGFGridHeight) or (bar and bar.GetHeight and bar:GetHeight()) or 0
    local pointDX, pointDY = PointOffsetFromCenter(point, bw, bh)
    local targetX = (centerX or 0) + pointDX + (tonumber(gridDX) or 0)
    local targetY = (centerY or 0) + pointDY + (tonumber(gridDY) or 0)
    return round(targetX - ax), round(targetY - ay)
end

local tickerFrame
local tickerActive = false
local activeDrag
local idleMoverDirty = false
local idleHUDDirty = false
local C_Timer = C_Timer
local dirtyFlushScheduled = false
local dirtyFlushGeneration = 0

local function SyncUnitPopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc >= 0.05 then
        d.popupSyncAcc = 0
        if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    end
end

local function SyncResourcePopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc >= 0.05 then
        d.popupSyncAcc = 0
        if EM2.ResourcePopup and EM2.ResourcePopup.IsOpen and EM2.ResourcePopup.IsOpen() then
            EM2.ResourcePopup.Sync()
        end
    end
end

local function SyncGFPopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc >= 0.05 then
        d.popupSyncAcc = 0
        local syncGFPopups = DragProviders.syncGFPopups
        if not syncGFPopups then
            syncGFPopups = MSUF.Require("MSUF_EM2_SyncGFPopups", CALLER)
            DragProviders.syncGFPopups = syncGFPopups
        end
        syncGFPopups()
    end
end

local function CastbarDefaultOffsets(unit)
    local x, y = MSUF.Require("MSUF_GetCastbarDefaultOffsets", CALLER)(unit)
    return tonumber(x) or 0, tonumber(y) or 0
end

--- Castbar offsets are SetPoint offsets in the bar's own units, and the bar
--- carries the MSUF Frame Scale: the UIParent-space delta converts like the
--- unit drag's (a factor of exactly 1 at scale 1.0).
local function ApplyCastbarDragPosition(d, centerX, centerY, uiScale)
    if not (d and d.conf and d.castbarXKey and d.castbarYKey) then return false end
    local g = d.conf
    local barScale = d.bar and d.bar.GetEffectiveScale and d.bar:GetEffectiveScale() or 0
    local toBar = barScale > 0 and (uiScale or barScale) / barScale or 1
    local dx = ((centerX or d.startCX or 0) - (d.startCX or 0)) * toBar
    local dy = ((centerY or d.startCY or 0) - (d.startCY or 0)) * toBar
    local nextX = round((d.castbarStartX or 0) + dx)
    local nextY = round((d.castbarStartY or 0) + dy)

    if g[d.castbarXKey] == nextX and g[d.castbarYKey] == nextY then
        return true
    end

    g[d.castbarXKey] = nextX
    g[d.castbarYKey] = nextY
    MSUF.Castbars.Config.Invalidate()

    local positionPreview = DragProviders.positionCastbarPreview
    if not positionPreview then
        positionPreview = MSUF.Require("MSUF_PositionCastbarPreviewUnit", CALLER)
        DragProviders.positionCastbarPreview = positionPreview
    end
    if not positionPreview(d.castbarUnit) then
        local applyCastbar = DragProviders.applyCastbar
        if not applyCastbar then
            applyCastbar = MSUF.Require("MSUF_ApplyCastbarUnitAndSync", CALLER)
            DragProviders.applyCastbar = applyCastbar
        end
        applyCastbar(d.castbarUnit)
    end

    return true
end

local function ApplyGroupDragPosition(d, centerX, centerY)
    if not (d and d.conf and d.bar) then return false end
    if IsConfigCombatLocked() then return false end
    local bar = d.bar
    local gridDX = tonumber(bar._msufGFDragCenterToGridX) or 0
    local gridDY = tonumber(bar._msufGFDragCenterToGridY) or 0
    local targetCX = (centerX or d.startCX or 0) + (d.barCenterDX or 0)
    local targetCY = (centerY or d.startCY or 0) + (d.barCenterDY or 0)
    local anchorCX = targetCX + gridDX
    local anchorCY = targetCY + gridDY
    local nextX, nextY = GroupOffsetFromCenter(bar, d.conf, targetCX, targetCY, gridDX, gridDY)
    -- A size tier's own position when Edit Mode shows that tier (MSUF_UF_Group_EM2.lua).
    local xKey, yKey = bar._msufGFOffsetKeyX or "offsetX", bar._msufGFOffsetKeyY or "offsetY"
    local changed = d.conf[xKey] ~= nextX or d.conf[yKey] ~= nextY
    local positionChanged = (d.lastGroupTargetCX == nil)
        or abs(targetCX - d.lastGroupTargetCX) > 0.001
        or abs(targetCY - d.lastGroupTargetCY) > 0.001
        or abs(anchorCX - d.lastGroupAnchorCX) > 0.001
        or abs(anchorCY - d.lastGroupAnchorCY) > 0.001
    if changed or positionChanged then
        local liveAnchor = bar._msufGFLiveAnchor
        local logicalAnchor = bar._msufGFLogicalAnchor
        local anchor = liveAnchor or logicalAnchor
        local _, oldBarCX, _, _, oldBarCY = GetFrameEdgesUI(bar)
        oldBarCX = oldBarCX or d.lastGroupTargetCX or ((d.startCX or targetCX) + (d.barCenterDX or 0))
        oldBarCY = oldBarCY or d.lastGroupTargetCY or ((d.startCY or targetCY) + (d.barCenterDY or 0))
        local oldAnchorCX, oldAnchorCY
        if anchor and anchor ~= bar then
            local _, anchorCenterX, _, _, anchorCenterY = GetFrameEdgesUI(anchor)
            oldAnchorCX = anchorCenterX or d.lastGroupAnchorCX or (oldBarCX + gridDX)
            oldAnchorCY = anchorCenterY or d.lastGroupAnchorCY or (oldBarCY + gridDY)
        end

        if not TryApplyFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", targetCX, targetCY) then
            TryApplyFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", oldBarCX, oldBarCY)
            return false
        end
        if anchor and anchor ~= bar and anchor.ClearAllPoints and anchor.SetPoint then
            if not TryApplyFramePoint(anchor, "CENTER", UIParent, "BOTTOMLEFT", anchorCX, anchorCY) then
                TryApplyFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", oldBarCX, oldBarCY)
                TryApplyFramePoint(anchor, "CENTER", UIParent, "BOTTOMLEFT", oldAnchorCX, oldAnchorCY)
                return false
            end
        end
        d.lastGroupTargetCX = targetCX
        d.lastGroupTargetCY = targetCY
        d.lastGroupAnchorCX = anchorCX
        d.lastGroupAnchorCY = anchorCY
    end
    if changed then
        d.conf[xKey] = nextX
        d.conf[yKey] = nextY
        -- Only the write earns the stamp. A click that never moved would
        -- otherwise label untouched legacy offsets as already converted, and
        -- GF.EnsureStableGridPosition refuses to convert them ever after.
        d.conf.positionMode = "GRID_BOUNDS_V2"
    end
    return true
end

local function ApplyPublicExternalDragPosition(d, centerX, centerY, phase)
    if not (d and d.externalPublicElement and d.externalStartState) then return false end
    local external = EM2.ExternalElements
    if not (external and type(external.ApplyMove) == "function") then return false end
    return external.ApplyMove(
        d.key,
        d.externalStartState,
        (centerX or d.startCX or 0) - (d.startCX or 0),
        (centerY or d.startCY or 0) - (d.startCY or 0),
        centerX,
        centerY,
        phase or "preview"
    ) == true
end

local function SyncCastbarPopupDuringDrag(d, elapsed)
    if not d then return end
    d.popupSyncAcc = (d.popupSyncAcc or 0) + (elapsed or 0)
    if d.popupSyncAcc < 0.05 then return end
    d.popupSyncAcc = 0
    local syncCastbarPopup = DragProviders.syncCastbarPopup
    if not syncCastbarPopup then
        syncCastbarPopup = MSUF.Require("MSUF_SyncCastbarPositionPopup", CALLER)
        DragProviders.syncCastbarPopup = syncCastbarPopup
    end
    syncCastbarPopup(d.castbarUnit)
end

local function NotifyFocusDuringDrag(d, elapsed)
    if not (d and EM2.Focus and EM2.Focus.NotifyPositionChanged) then return end
    d.focusNotifyAcc = (d.focusNotifyAcc or 0) + (elapsed or 0)
    if d.focusNotifyAcc < 0.05 then return end
    d.focusNotifyAcc = 0
    EM2.Focus.NotifyPositionChanged(d.key, false)
end

local function FlushDirty()
    if not tickerActive or activeDrag or (IsConfigCombatLocked and IsConfigCombatLocked()) then return end
    local syncMovers, syncHUD = idleMoverDirty, idleHUDDirty
    idleMoverDirty, idleHUDDirty = false, false
    if syncMovers then
        if EM2.Movers and EM2.Movers.SyncAll and (not EM2.Movers.IsShown or EM2.Movers.IsShown()) then EM2.Movers.SyncAll() end
    end
    if syncHUD then
        if EM2.HUD and EM2.HUD.RefreshControls and (not EM2.HUD.IsShown or EM2.HUD.IsShown()) then EM2.HUD.RefreshControls() end
    end
end

local function ScheduleDirtyFlush(delay)
    if not tickerActive or dirtyFlushScheduled or activeDrag then return end
    if IsConfigCombatLocked and IsConfigCombatLocked() then return end
    if not (C_Timer and C_Timer.After) then
        FlushDirty()
        return
    end
    dirtyFlushScheduled = true
    local generation = dirtyFlushGeneration
    C_Timer.After(delay or 0, function()
        dirtyFlushScheduled = false
        if generation ~= dirtyFlushGeneration then return end
        FlushDirty()
    end)
end

local function SetActiveDragFlags(d, active)
    if not d then return end
    active = active == true
    if d.bar then d.bar._msufDragActive = active end
    if d.isBossLayout then
        local frames = MSUF and MSUF.UF and MSUF.UF.frames
        for i = 1, 5 do
            local frame = (frames and frames["boss" .. i]) or MSUF.Optional("MSUF_boss" .. i)
            if frame then frame._msufDragActive = active end
        end
    end
    if d.isArenaLayout then
        local frames = MSUF and MSUF.UF and MSUF.UF.frames
        for i = 1, tonumber(MAX_ARENA_FRAMES) or 3 do
            local frame = (frames and frames["arena" .. i]) or MSUF.Optional("MSUF_arena" .. i)
            if frame then frame._msufDragActive = active end
        end
    end
    if d.bar and d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = active end
    if d.bar and d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = active end
    if not active and d.mover and d.mover._msufGFEM2DragSourceFrame then
        d.mover._msufGFEM2DragSourceFrame._msufGFEM2Dragging = nil
        d.mover._msufGFEM2DragSourceFrame = nil
    end
end

local function OnUpdate(self, elapsed)
    if activeDrag then
        local d = activeDrag

        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            local mover = d.mover
            local sourceFrame = mover and mover._msufGFEM2DragSourceFrame
            local moved
            if mover and type(mover._msufEM2EndDrag) == "function" then
                moved = mover:_msufEM2EndDrag("LeftButton") == true
            else
                moved = Ticker.EndDrag()
                if mover then
                    if moved then mover._suppressNextClick = true end
                    if mover._dragging ~= nil then mover._dragging = false end
                    if mover._coordFS then mover._coordFS:Hide() end
                    if mover.UpdateLabelVisibility then mover:UpdateLabelVisibility() end
                end
            end
            if moved and sourceFrame then sourceFrame._msufGFEM2LastDragEnd = GetTime and GetTime() or 0 end
            return
        end

        if IsConfigCombatLocked and IsConfigCombatLocked() then return end

        local sc = UIParent:GetEffectiveScale() or d.uiScale or 1
        if sc <= 0 then sc = 1 end
        local mx, my = GetCursorPosition()
        if type(mx) ~= "number" or type(my) ~= "number" then return end
        if not UnitDragHasCursorMotion(d, mx, my) then return end
        local frameScale = UpdateUnitDragBounds(d, sc)

        local rawCX = (mx + (d.offPX or 0)) / sc
        local rawCY = (my + (d.offPY or 0)) / sc

        local snapCX, snapCY = rawCX, rawCY
        if d.snapEnabled and EM2.Snap then
            local nextCX, nextCY = EM2.Snap.Apply(rawCX, rawCY, d.halfW, d.halfH, d.key)
            if type(nextCX) == "number" then snapCX = nextCX end
            if type(nextCY) == "number" then snapCY = nextCY end
        end

        local screenW = UIParent:GetWidth() or d.screenW or 0
        local screenH = UIParent:GetHeight() or d.screenH or 0
        snapCX = ClampCenterAxis(snapCX, d.halfW, screenW)
        snapCY = ClampCenterAxis(snapCY, d.halfH, screenH)

        local positioned = d.strategy:applyDrag(d, snapCX, snapCY, sc, "preview", frameScale)
        --- The mover is only feedback. Never let it outrun the real preview or
        --- leave a detached overlay behind when a protected/runtime move fails.
        if not positioned then return end

        local moverX = snapCX - d.halfW
        local moverY = snapCY + d.halfH - screenH
        local moverMoved = (d.lastMoverX == nil)
            or abs(moverX - d.lastMoverX) > 0.001
            or abs(moverY - d.lastMoverY) > 0.001

        if moverMoved then
            d.lastMoverX = moverX
            d.lastMoverY = moverY
            d.mover:ClearAllPoints()
            d.mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", moverX, moverY)

            if d.mover._coordFS then
                local displayX, displayY
                if type(U.FramePositionValues) == "function" then
                    displayX, displayY = U.FramePositionValues(d.bar)
                end
                local fallbackX
                if not displayX then
                    local left = snapCX - d.halfW
                    local right = snapCX + d.halfW
                    local centerX = screenW * 0.5
                    if right <= centerX then
                        fallbackX = right - centerX
                    elseif left >= centerX then
                        fallbackX = left - centerX
                    else
                        fallbackX = 0
                    end
                end
                d.mover._coordFS:SetText(format("%.0f, %.0f",
                    displayX or round(fallbackX),
                    displayY or round(snapCY + d.halfH - screenH * 0.5)))
            end
        end

        if d.externalPublicElement then
            NotifyFocusDuringDrag(d, elapsed)
            return
        elseif d.isSubframe then
            SyncResourcePopupDuringDrag(d, elapsed)
            NotifyFocusDuringDrag(d, elapsed)
            return
        elseif d.isCastbar then
            SyncCastbarPopupDuringDrag(d, elapsed)
            NotifyFocusDuringDrag(d, elapsed)
            return
        end

        if d.isGroupFrame then
            SyncGFPopupDuringDrag(d, elapsed)
        else
            SyncUnitPopupDuringDrag(d, elapsed)
        end
        NotifyFocusDuringDrag(d, elapsed)
    else
        Driver.Detach(self)
        ScheduleDirtyFlush(0)
    end
end

--- The cursor offset, mover geometry and snap state every drag starts from.
local function SetDragGeometry(drag, uiScale, mL, mCX, mR, mB, mCY, mT, cursorPX, cursorPY)
    drag.offPX, drag.offPY = mCX * uiScale - cursorPX, mCY * uiScale - cursorPY
    drag.startCX, drag.startCY = mCX, mCY
    drag.startCenterPX, drag.startCenterPY = mCX * uiScale, mCY * uiScale
    drag.halfW, drag.halfH = (mR - mL) * 0.5, (mT - mB) * 0.5
    drag.screenW, drag.screenH = UIParent:GetWidth(), UIParent:GetHeight()
    drag.focusNotifyAcc = 0.05
    drag.snapEnabled = EM2.Snap and EM2.Snap.IsEnabled and EM2.Snap.IsEnabled() or false
    drag.uiScale = uiScale
    return drag
end

local function BuildPublicDrag(mover, key, cfg, bar, uiScale, mL, mCX, mR, mB, mCY, mT, cursorPX, cursorPY)
    local external = EM2.ExternalElements
    local externalStartState = external and type(external.CaptureState) == "function"
        and external.CaptureState(key) or nil
    if externalStartState == nil then return false end
    return SetDragGeometry({
        mover = mover,
        key = key,
        cfg = cfg,
        bar = bar,
        externalPublicElement = true,
        externalStartState = externalStartState,
    }, uiScale, mL, mCX, mR, mB, mCY, mT, cursorPX, cursorPY)
end

local function ApplyDragStart(drag, start, isSubframe, uiScale)
    if type(start) == "table" then
        local centerX = tonumber(start.centerX)
        local centerY = tonumber(start.centerY)
        if centerX then
            drag.startCX = centerX
            drag.startCenterPX = centerX * uiScale
        end
        if centerY then
            drag.startCY = centerY
            drag.startCenterPY = centerY * uiScale
        end
        drag.unitStartX = tonumber(start.offsetX) or drag.unitStartX
        drag.unitStartY = tonumber(start.offsetY) or drag.unitStartY
        if isSubframe then
            drag.subframeStartX = tonumber(start.offsetX) or drag.subframeStartX
            drag.subframeStartY = tonumber(start.offsetY) or drag.subframeStartY
        end
        drag.castbarStartX = tonumber(start.castbarX) or drag.castbarStartX
        drag.castbarStartY = tonumber(start.castbarY) or drag.castbarStartY
    end
end

-- Share the runtime compiler's anchor precedence, aliases and cooldown margins.
local function ResolveDragLayout(bar, key, conf, isCastbar, isGroupFrame, groupOwner, isSubframe)
    local point = UnitFramePoint(conf)
    local relativePoint = UnitFrameRelativePoint(conf, point)
    if isGroupFrame then return ResolveGroupAnchor(conf, groupOwner), point, relativePoint, 0, 0 end
    if isCastbar or isSubframe then return UIParent, point, relativePoint, 0, 0 end
    local unit = bar.MSUFUnitKey or (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
    local spec = MSUF.UF.Config.RefreshUnit(unit)
    local factory = MSUF.UF.Factory
    local anchor, missing = factory.ResolveAnchor(spec, bar)
    relativePoint = spec.relativePoint
    if anchor == bar or factory.AnchorWouldCreateCycle(bar, anchor) then
        anchor, relativePoint = UIParent, spec.point
    end
    return anchor, spec.point, relativePoint,
        spec.x - spec.offsetX, spec.y - spec.offsetY, spec.offsetX, spec.offsetY, missing
end

-- Commit the visible fallback once, before runtime can replay its screen cache.
local function CacheDraggedUnitPosition(key)
    local uf = MSUF.UF
    local units = uf.UnitsForConfigKey(key)
    for i = 1, #units do
        local frame = uf.frames[units[i]]
        if frame then
            local spec = uf.Config.GetSpec(units[i])
            local _, missing = uf.Factory.ResolveAnchor(spec, frame)
            if missing then
                MSUF.Require("MSUF_CacheUnitFrameScreenPosition", CALLER)(frame, key, units[i], spec.point)
            end
        end
    end
end

-- Capture the real root/mover geometry once. Each tick converts the desired
-- screen position into the current anchor space, even if either scale changes.
local function PrepareUnitDrag(drag, start)
    if drag.isCastbar or drag.isSubframe or drag.isGroupFrame then return drag end
    local frame = drag.bar
    local scale = frame:GetEffectiveScale()
    local x, y = PointXY(frame, drag.point)
    local cx, cy = frame:GetCenter()
    local ax, ay = PointXY(drag.anchor, drag.relativePoint)
    if not (scale and scale > 0 and x and y and cx and cy and ax and ay) then return nil end
    local anchorScale = drag.anchor.GetEffectiveScale and drag.anchor:GetEffectiveScale() or 1
    x = x - ax * anchorScale / scale - drag.unitBaseX
    y = y - ay * anchorScale / scale - drag.unitBaseY
    if not start then
        if abs(x - drag.unitStartX) * scale > 1 then drag.unitStartX = x end
        if abs(y - drag.unitStartY) * scale > 1 then drag.unitStartY = y end
    end
    drag.unitBiasX, drag.unitBiasY = drag.unitStartX - x, drag.unitStartY - y
    drag.unitCenterDX = cx - drag.startCenterPX / scale
    drag.unitCenterDY = cy - drag.startCenterPY / scale
    drag.lastUnitX, drag.lastUnitY = drag.unitStartX, drag.unitStartY
    drag.unitPositionChanged, drag.unitAnchorFallback = false, false
    drag.unitAnchorPX, drag.unitAnchorPY = ax * anchorScale, ay * anchorScale
    drag.unitGeometryScale = scale / drag.uiScale
    drag.unitCursorPX, drag.unitCursorPY = GetCursorPosition()
    drag.unitCursorMoved = false
    return drag
end

local function BuildDrag(mover, key, cfg, start)
    if not mover or type(cfg) ~= "table" then return nil end
    local bar = type(start) == "table" and start.bar or (cfg.getFrame and cfg.getFrame())
    if not bar then return false end
    local externalPublicElement = cfg.externalPublicElement == true
    local conf = cfg.getConf and cfg.getConf()
    local isCastbar = (cfg.popupType == "castbar") or (type(key) == "string" and key:sub(1, 8) == "castbar_")
    local isSubframe = type(cfg.subframeOffsetXKey) == "string" and type(cfg.subframeOffsetYKey) == "string"
    local castbarUnit = cfg.castbarUnit
    if isCastbar and (not castbarUnit or castbarUnit == "") then
        castbarUnit = key:sub(9)
    end
    if isCastbar and not conf then
        local db = MSUF_DB
        conf = db and db.general or nil
    end
    if not externalPublicElement and type(conf) ~= "table" then return false end

    local uiScale = UIParent:GetEffectiveScale() or 1
    if uiScale <= 0 then uiScale = 1 end
    local cursorPX, cursorPY = GetCursorPosition()
    if type(cursorPX) ~= "number" or type(cursorPY) ~= "number" then return false end

    local mL, mCX, mR, mB, mCY, mT = Kinds.For(key, cfg, bar):bounds(mover)
    if not mL and mover.GetLeft and mover.GetRight and mover.GetTop and mover.GetBottom then
        mL, mR, mT, mB = mover:GetLeft(), mover:GetRight(), mover:GetTop(), mover:GetBottom()
        if mL and mR and mT and mB then
            mCX = (mL + mR) * 0.5
            mCY = (mT + mB) * 0.5
        end
    end
    if not (mL and mCX and mR and mB and mCY and mT) then return false end

    if externalPublicElement then
        return BuildPublicDrag(mover, key, cfg, bar, uiScale, mL, mCX, mR, mB, mCY, mT, cursorPX, cursorPY)
    end

    local isGroupFrame = (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority")
        or (bar and bar._msufIsGroupFrame == true) or false
    local groupKind = (key == "gf_party" and "party")
        or (key == "gf_raid" and "raid")
        or (key == "gf_mythicraid" and "mythicraid")
        or (key == "gf_priority" and "priority")
        or (bar and bar._msufGFKind)
    local groupOwner = isGroupFrame and bar and (bar._msufGFLiveAnchor or bar._msufGFLogicalAnchor or bar) or nil
    local anchor, point, relativePoint, unitBaseX, unitBaseY, unitStartX, unitStartY =
        ResolveDragLayout(bar, key, conf, isCastbar, isGroupFrame, groupOwner, isSubframe)

    local barCenterDX, barCenterDY = 0, 0
    if isGroupFrame then
        local _, bCX, _, _, bCY = GetFrameEdgesUI(bar)
        if bCX and bCY then
            barCenterDX = bCX - mCX
            barCenterDY = bCY - mCY
        end
    end

    local castbarXKey, castbarYKey
    local castbarStartX, castbarStartY
    local castbarReanchorFunc
    if isCastbar then
        castbarXKey, castbarYKey = GetCastbarOffsetKeys(castbarUnit)
        if not (castbarXKey and castbarYKey) then return false end
        local defX, defY = CastbarDefaultOffsets(castbarUnit)
        castbarStartX = tonumber(conf[castbarXKey]) or defX
        castbarStartY = tonumber(conf[castbarYKey]) or defY
        if castbarUnit == "player" then
            castbarReanchorFunc = "MSUF_ReanchorPlayerCastBar"
        elseif castbarUnit == "target" then
            castbarReanchorFunc = "MSUF_ReanchorTargetCastBar"
        elseif castbarUnit == "focus" then
            castbarReanchorFunc = "MSUF_ReanchorFocusCastBar"
        elseif castbarUnit == "boss" then
            castbarReanchorFunc = "MSUF_ReanchorBossCastBar"
        elseif castbarUnit == "arena" then
            castbarReanchorFunc = "MSUF_ReanchorArenaCastBar"
        end
    end

    local isBossLayout = not isCastbar and key == "boss"
    local isArenaLayout = not isCastbar and key == "arena"

    local drag = {
        mover        = mover,
        key          = key,
        cfg          = cfg,
        bar          = bar,
        conf         = conf,
        anchor       = anchor,
        unitBaseX    = unitBaseX,
        unitBaseY    = unitBaseY,
        popupSyncAcc = 0.05,
        isGroupFrame = isGroupFrame,
        isBossLayout = isBossLayout,
        isArenaLayout = isArenaLayout,
        groupKind    = groupKind,
        isCastbar    = isCastbar,
        isSubframe   = isSubframe,
        subframeStartX = isSubframe and (tonumber(conf[cfg.subframeOffsetXKey]) or 0) or nil,
        subframeStartY = isSubframe and (tonumber(conf[cfg.subframeOffsetYKey]) or (cfg.resourceKind == "power" and -4 or 0)) or nil,
        castbarUnit  = castbarUnit,
        castbarXKey  = castbarXKey,
        castbarYKey  = castbarYKey,
        castbarStartX = castbarStartX,
        castbarStartY = castbarStartY,
        castbarReanchorFunc = castbarReanchorFunc,
        point        = point,
        relativePoint = relativePoint,
        unitStartX   = unitStartX or tonumber(conf and conf.offsetX) or 0,
        unitStartY   = unitStartY or tonumber(conf and conf.offsetY) or 0,
        barCenterDX  = barCenterDX,
        barCenterDY  = barCenterDY,
    }
    SetDragGeometry(drag, uiScale, mL, mCX, mR, mB, mCY, mT, cursorPX, cursorPY)
    ApplyDragStart(drag, start, isSubframe, uiScale)
    return PrepareUnitDrag(drag, start)
end

local function ScheduleMoverSyncAfterDrag()
    C_Timer.After(0.06, function()
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end)
end

local function CommitUnitDragPosition(d, cx, cy, uiScale)
    if IsConfigCombatLocked() then return false end
    -- Providers can appear, disappear or change identity while the mouse is
    -- held. Commit the last mover target in the runtime's current anchor space.
    local anchor, point, relativePoint, baseX, baseY, _, _, missing = ResolveDragLayout(d.bar, d.key, d.conf)
    -- A missing provider is temporary. Retain its known coordinate space so
    -- the screen-cache fallback does not turn into a second offset on return.
    if missing then anchor = d.anchor end
    if d.anchor ~= anchor or d.point ~= point or d.relativePoint ~= relativePoint
        or d.unitBaseX ~= baseX or d.unitBaseY ~= baseY then
        d.lastUnitX, d.lastUnitY = nil, nil
    end
    d.anchor, d.point, d.relativePoint = anchor, point, relativePoint
    d.unitBaseX, d.unitBaseY = baseX, baseY
    SetActiveDragFlags(d, true)
    local positioned = ApplyUnitDragPosition(d, cx, cy, uiScale, "commit")
    SetActiveDragFlags(d, false)
    if not positioned then return false end
    CacheDraggedUnitPosition(d.key)
    return true
end

local function FinishUnitDrag(d, cx, cy, uiScale)
    if not CommitUnitDragPosition(d, cx, cy, uiScale) then return false end
    ApplySettingsForKeySafe(d.key)
    ScheduleMoverSyncAfterDrag()
    MSUF.Require("MSUF_SyncUnitPositionPopup", CALLER)()
    if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
    RefreshUFPreview("EM2_UNIT_DRAG_END", d.key)
    return true
end

local function FinishSubframeDrag(d, cx, cy, uiScale)
    ApplySubframeDragPosition(d, cx, cy, uiScale)
    if type(d.cfg.commitSubframePosition) == "function" then d.cfg.commitSubframePosition() end
    ScheduleMoverSyncAfterDrag()
    if EM2.ResourcePopup and EM2.ResourcePopup.Sync then EM2.ResourcePopup.Sync() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
    RefreshUFPreview("EM2_RESOURCE_DRAG_END", d.cfg.resourceUnit or "player")
    return true
end

local function FinishCastbarDrag(d)
    MSUF.Require("MSUF_ApplyCastbarUnitAndSync", CALLER)(d.castbarUnit)
    ScheduleMoverSyncAfterDrag()
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
    RefreshUFPreview("EM2_CASTBAR_DRAG_END", d.castbarUnit)
    return true
end

local function FinishGroupDrag(d, cx, cy)
    if d.conf then
        ApplyGroupDragPosition(d, cx, cy)
        if d.bar and not IsConfigCombatLocked() then
            d.bar._msufDragActive = false
            if d.bar._msufGFLiveAnchor then d.bar._msufGFLiveAnchor._msufDragActive = false end
            if d.bar._msufGFLogicalAnchor then d.bar._msufGFLogicalAnchor._msufDragActive = false end
        end
    end
    if not IsConfigCombatLocked() then RefreshGroupGeometryScoped(d.groupKind) end
    ScheduleMoverSyncAfterDrag()
    MSUF.Require("MSUF_EM2_SyncGFPopups", CALLER)()
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
    return true
end

local function ApplyExternalStrategy(d, cx, cy, _, phase)
    return ApplyPublicExternalDragPosition(d, cx, cy, phase or "preview")
end

local function FinishExternalDrag(d, cx, cy)
    local moved = ApplyPublicExternalDragPosition(d, cx, cy, "commit")
    if not moved then
        local external = EM2.ExternalElements
        if external and type(external.RestoreHistoryState) == "function" then
            external.RestoreHistoryState({ key = d.key, data = d.externalStartState })
        end
    end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(d.key, true) end
    return moved
end

Kinds.Bind("unit", BuildDrag, ApplyUnitDragPosition, FinishUnitDrag)
Kinds.Bind("stacked", BuildDrag, ApplyUnitDragPosition, FinishUnitDrag)
Kinds.Bind("castbar", BuildDrag, ApplyCastbarDragPosition, FinishCastbarDrag)
Kinds.Bind("subframe", BuildDrag, ApplySubframeDragPosition, FinishSubframeDrag)
Kinds.Bind("group", BuildDrag, ApplyGroupDragPosition, FinishGroupDrag)
Kinds.Bind("external", BuildDrag, ApplyExternalStrategy, FinishExternalDrag)

--- A typed visual position is one complete drag transaction. Match the
--- native center-facing X edge / top Y edge, retain the real mover bounds,
--- and leave pixel rounding, preview, save and rollback with the drag owner.
function Ticker.SetExternalPosition(key, axis, value)
    if IsConfigCombatLocked() or not MSUF.EditModeAPI.IsActive() or activeDrag then return false end
    if (issecretvalue and issecretvalue(value)) or (axis ~= "x" and axis ~= "y") then return false end
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge or value >= math.huge then return false end
    local external, undo = EM2.ExternalElements, EM2.Undo
    local cfg = EM2.Registry.Get(key)
    if not (cfg and cfg.externalPublicElement and external and undo) then return false end
    local bar = external.GetPositionFrame(key)
    if not bar then return false end
    local x, y = U.FramePositionValues(bar)
    if value == (axis == "x" and x or y) then return false end
    local left, right, top = MSUF.Geometry.EditRect(bar)
    local uiLeft, uiRight, uiTop, uiBottom = MSUF.Geometry.EditRect(UIParent)
    local centerX, centerY = (uiLeft + uiRight) * 0.5, (uiTop + uiBottom) * 0.5
    local dx, dy = 0, 0
    if axis == "x" then
        local edge = value < 0 and right or value > 0 and left
            or (right <= centerX and right or left >= centerX and left or nil)
        if edge then dx = centerX + value - edge end
    else
        dy = centerY + value - top
    end
    local mover = EM2.Movers.Get(key)
    if not mover then
        EM2.Movers.SyncAll()
        mover = EM2.Movers.Get(key)
    end
    if not mover then return false end
    EM2.Movers.SyncKey(key)
    local d = Kinds.external:beginDrag(mover, key, cfg, { bar = bar })
    if not d then return false end
    local cx = ClampCenterAxis(d.startCX + dx, d.halfW, d.screenW)
    local cy = ClampCenterAxis(d.startCY + dy, d.halfH, d.screenH)
    -- Typed steps remain meaningful below the pointer-release jitter threshold
    -- at small UI scales. The owner still supplies the drag's pixel rounding.
    if cx == d.startCX and cy == d.startCY then return false end
    if undo.BeginChange("external", key, "Move") ~= true then return false end
    SetActiveDragFlags(d, true)
    local applied = d.strategy:applyDrag(d, cx, cy, d.uiScale, "preview")
    SetActiveDragFlags(d, false)
    if applied then
        applied = d.strategy:commit(d, cx, cy, d.uiScale)
    else
        external.RestoreHistoryState({ key = key, data = d.externalStartState })
    end
    if applied then
        undo.CommitChange()
        NotifyGuidedEditModeMoved(key)
    else
        undo.CancelChange()
    end
    Ticker.RequestIdleSync()
    return applied == true
end

function Ticker.BeginDrag(mover, key, cfg)
    if not tickerActive or activeDrag or not tickerFrame then return false end
    local drag = Kinds.For(key, cfg):beginDrag(mover, key, cfg)
    if not drag then return false end
    activeDrag = drag
    SetActiveDragFlags(drag, true)
    Driver.Attach(tickerFrame, OnUpdate)
    tickerFrame:Show()
    return true
end

--- External Edit Mode shells own their own cursor loop. These three cold-path
--- methods reuse the exact native MSUF anchor math without starting a second
--- OnUpdate or exposing its private drag state.
function Ticker.BeginExternalDrag(mover, key, cfg, start)
    local drag = Kinds.For(key, cfg):beginDrag(mover, key, cfg, start)
    if not drag then return nil end
    SetActiveDragFlags(drag, true)
    return drag
end

function Ticker.ApplyExternalDrag(drag)
    if not drag or (IsConfigCombatLocked and IsConfigCombatLocked()) then return false end
    local _, centerX, _, _, centerY = GetFrameEdgesUI(drag.mover)
    if centerX == nil or centerY == nil then return false end
    return drag.strategy:applyDrag(drag, centerX, centerY, UIParent:GetEffectiveScale() or drag.uiScale or 1, "preview")
end

function Ticker.EndExternalDrag(drag, applyFinal)
    if not drag then return false end
    local moved = false
    if applyFinal ~= false and not IsConfigCombatLocked() then
        if drag.unitPositionChanged ~= nil then
            local _, cx, _, _, cy = GetFrameEdgesUI(drag.mover)
            local scale = UIParent:GetEffectiveScale()
            if cx and cy and (drag.unitPositionChanged
                or abs(cx * scale - drag.startCenterPX) > 0.5 or abs(cy * scale - drag.startCenterPY) > 0.5) then
                moved = CommitUnitDragPosition(drag, cx, cy, scale)
            end
        else
            moved = Ticker.ApplyExternalDrag(drag)
        end
    end
    SetActiveDragFlags(drag, false)
    return moved
end

function Ticker.EndDrag()
    if not activeDrag then return false end
    local d = activeDrag
    activeDrag = nil
    SetActiveDragFlags(d, false)
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

    local mover = d.mover
    local mL, cx, mR, mB, cy, mT = GetFrameEdgesUI(mover)
    if not mL then
        mL = mover:GetLeft() or 0
        mR = mover:GetRight() or 0
        mT = mover:GetTop() or 0
        mB = mover:GetBottom() or 0
        cx = (mL + mR) * 0.5
        cy = (mT + mB) * 0.5
    end
    local uiScale = UIParent:GetEffectiveScale() or d.uiScale or 1
    if uiScale <= 0 then uiScale = 1 end
    local moved = abs(cx * uiScale - (d.startCenterPX or cx * uiScale)) > 0.5
        or abs(cy * uiScale - (d.startCenterPY or cy * uiScale)) > 0.5
        or d.unitPositionChanged == true

    if moved then
        moved = d.strategy:commit(d, cx, cy, uiScale) ~= false
        if moved then NotifyGuidedEditModeMoved(d.key) end
    end

    if tickerFrame then
        Driver.Detach(tickerFrame)
    end
    ScheduleDirtyFlush(0)
    return moved
end

function Ticker.IsDragging() return activeDrag ~= nil end

function Ticker.RequestIdleSync(kind)
    if kind == "mover" then
        idleMoverDirty = true
        ScheduleDirtyFlush(0)
        return
    elseif kind == "hud" then
        idleHUDDirty = true
        ScheduleDirtyFlush(0)
        return
    end
    idleMoverDirty = true
    idleHUDDirty = true
    ScheduleDirtyFlush(0)
end

function Ticker.Start()
    if activeDrag then SetActiveDragFlags(activeDrag, false) end
    if not tickerFrame then
        tickerFrame = Driver.GetFrame()
    end
    tickerActive = true
    activeDrag = nil
    idleMoverDirty = true
    idleHUDDirty = true
    dirtyFlushGeneration = dirtyFlushGeneration + 1
    Driver.Detach(tickerFrame)
    ScheduleDirtyFlush(0)
end

--- Edit Mode closes while a drag is still held (combat start, Exit, a
--- profile switch). Native drags wrote their offsets on every tick and the
--- exit re-applies them; an external element only previewed its position,
--- and its provider persists it on "commit". The combat exit runs this inside
--- PLAYER_REGEN_DISABLED, before lockdown, and defers nothing; a provider
--- that refuses gets its start state back.
local function CommitHeldDragOnStop(d)
    if d and d.unitPositionChanged then
        local _, cx, _, _, cy = GetFrameEdgesUI(d.mover)
        if cx and cy and not IsConfigCombatLocked() then
            CommitUnitDragPosition(d, cx, cy, UIParent:GetEffectiveScale())
        else
            CacheDraggedUnitPosition(d.key)
        end
    end
    if not (d and d.externalPublicElement and d.mover) then return end
    local _, cx, _, _, cy = GetFrameEdgesUI(d.mover)
    if cx == nil or cy == nil then return end
    local uiScale = UIParent:GetEffectiveScale() or d.uiScale or 1
    if uiScale <= 0 then uiScale = 1 end
    if abs(cx * uiScale - (d.startCenterPX or cx * uiScale)) <= 0.5
        and abs(cy * uiScale - (d.startCenterPY or cy * uiScale)) <= 0.5 then return end
    if ApplyPublicExternalDragPosition(d, cx, cy, "commit") then return end
    local external = EM2.ExternalElements
    if external and type(external.RestoreHistoryState) == "function" then
        external.RestoreHistoryState({ key = d.key, data = d.externalStartState })
    end
end

function Ticker.Stop(commitHeldDrag)
    tickerActive = false
    if activeDrag then
        if commitHeldDrag == true then CommitHeldDragOnStop(activeDrag) end
        SetActiveDragFlags(activeDrag, false)
    end
    activeDrag = nil
    idleMoverDirty = false
    idleHUDDirty = false
    dirtyFlushScheduled = false
    dirtyFlushGeneration = dirtyFlushGeneration + 1
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides(true) end
    Kinds.Clear()
end
