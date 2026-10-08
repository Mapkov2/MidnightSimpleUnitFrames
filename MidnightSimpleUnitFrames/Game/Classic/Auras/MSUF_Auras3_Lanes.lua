local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Game/Classic/Auras/MSUF_Auras3_Lanes.lua
--- Lane state of the Classic scan backend: a frame's lane frames and button
--- pools, applying a compiled config, full scans (capped, inline-rendered or
--- through AuraUtil.ForEachAura), the UNIT_AURA delta merge, sorted and
--- natural-order rendering, and the per-lane choice between a full scan and
--- a delta.
---
--- Game/<Flavor>/Auras.xml loads the unit-frame aura backend after Compile.lua
--- in this order: Buttons, Filters, FrameVisuals, Lanes, UnitFrames, Requests.
--- Each file imports the earlier ones from A3._ClassicBackend at load time.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
local Backend = type(A3) == "table" and A3._ClassicBackend
assert(Backend, "Classic aura lanes require Game/Classic/Auras/MSUF_Auras3_Buttons.lua")
if Backend.Lanes then return end
local Compile = A3._ClassicCompile
local Buttons, Filters, FrameVisuals = Backend.Buttons, Backend.Filters, Backend.FrameVisuals
local Lanes = {}
local CompactLaneOrder

local type, tonumber, pairs, next = type, tonumber, pairs, next
local math_ceil, math_min = math.ceil, math.min
local table_sort = table.sort
local CreateFrame = _G.CreateFrame
local AuraUtil = _G.AuraUtil
local IsSecret = _G.issecretvalue or function() return false end
local C_UnitAuras = _G.C_UnitAuras
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID

local WipeTable = Compile.WipeTable
local FillAuraSlots = Compile.FillAuraSlots
local PlainNumber = Compile.PlainNumber
local SortAuras = Compile.SortAuras
local SortComparator = Compile.SortComparator
local BASE_LANE_ORDER = Compile.BASE_LANE_ORDER
local ApplyButtonLayout = Buttons.ApplyButtonLayout
local EnsureButton = Buttons.EnsureButton
local PrewarmLaneButtons = Buttons.PrewarmLaneButtons
local HideButton = Buttons.HideButton
local HideTrailingButtons = Buttons.HideTrailingButtons
local UpdateButton = Buttons.UpdateButton
local BuildButtonUpdater = Buttons.BuildButtonUpdater
local ProcessData = Filters.ProcessData
local SourceMemo = Filters.SourceMemo
local ShouldShowAura = Filters.ShouldShowAura
local DataMatchesLane = Filters.DataMatchesLane
local ResetLaneVisualCache = FrameVisuals.ResetLaneVisualCache
local ConsiderLaneAuraVisual = FrameVisuals.ConsiderLaneAuraVisual
local ClearFrameAuraVisualState = FrameVisuals.ClearFrameAuraVisualState

-- Read-only stand-in for a missing lanes table, so lane walks never allocate.
local EMPTY_LANES = {}

local function ApplyLaneLayout(lane)
    local cfg = lane.config
    if not (lane.frame and cfg) then return end
    lane.frame:ClearAllPoints()
    lane.frame:SetPoint(cfg.anchor, lane.root, cfg.anchor, cfg.x, cfg.y)
    lane.frame:SetSize(cfg.width, cfg.height)
    if lane.frame.SetAlpha then lane.frame:SetAlpha(cfg.alpha or 1) end
    -- A lane takes its parent's strata, as Retail's native aura hosts do
    -- (ResolveFrameStrata, Auras3/Runtime/MSUF_Auras3_Runtime_Platform.lua): a
    -- stored per-lane strata is a legacy value no menu edits, and it must not
    -- lift one container out of the frame's 0..30 layer order.
    A3.SyncFrameStrata(lane.frame, A3.ReadParentFrameStrata(lane.root))
    if lane.root.GetFrameLevel and lane.frame.SetFrameLevel then
        lane.frame:SetFrameLevel((lane.root:GetFrameLevel() or 0) + cfg.layer)
    end
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then ApplyButtonLayout(lane, button, i) end
    end
end

local function ClearLane(lane)
    lane.all = WipeTable(lane.all)
    lane.mine = WipeTable(lane.mine)
    lane.active = WipeTable(lane.active)
    lane.sorted = WipeTable(lane.sorted)
    lane.ordered = WipeTable(lane.ordered)
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.orderedCount = 0
    lane.orderDirty = nil
    lane.visible = 0
    lane._msufA3CappedFullScan = nil
    ResetLaneVisualCache(lane)
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
end

local function ResetLaneData(lane, skipOrderScratch)
    lane.all = WipeTable(lane.all)
    lane.mine = WipeTable(lane.mine)
    lane.active = WipeTable(lane.active)
    if skipOrderScratch ~= true then
        lane.sorted = WipeTable(lane.sorted)
        lane.ordered = WipeTable(lane.ordered)
    end
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.orderedCount = 0
    lane.orderDirty = nil
    lane._msufA3CappedFullScan = nil
    ResetLaneVisualCache(lane)
end

local function EnsureLane(root, state, kind, cfg)
    local lanes = state.lanes
    local lane = lanes[kind]
    local parent = cfg and cfg.anchorTarget == "portrait"
        and state.frame and state.frame.MSUFPortraitHolder or root
    if lane then
        if parent and lane.root ~= parent and lane.frame and lane.frame.SetParent then
            lane.frame:SetParent(parent)
            lane.root = parent
        end
        -- The shared Edit Mode layer treats the rendered lane frame as its
        -- input-forwarding surface. Keep the same compact contract exposed by
        -- Retail's native Aura containers so Classic aura buttons cannot eat
        -- drag clicks while the preview mover is active.
        lane.frame._msufA3NativeLane = kind
        lane.frame._msufA3NativeLaneConfig = lane
        return lane
    end
    local frame = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    lane = {
        kind = kind,
        root = parent,
        frame = frame,
        all = {},
        -- Per-lane "cast by the player" answers by aura instance ID. They never
        -- go into the AuraData: a UNIT_AURA payload is one set of tables for
        -- every lane and frame on the unit, and lanes resolve ownership by
        -- different rules (native PLAYER membership or the source unit).
        mine = {},
        active = {},
        sorted = {},
        ordered = {},
        slotScratch = {},
        visibleByID = {},
        orderedCount = 0,
        visible = 0,
        createdButtons = 0,
    }
    frame._msufA3NativeLane = kind
    frame._msufA3NativeLaneConfig = lane
    frame.GetAuraFrameCount = function()
        return lane.createdButtons or 0
    end
    frame.GetAuraFrame = function(_, index)
        return lane[index]
    end
    lanes[kind] = lane
    return lane
end

local function EnsureState(frame)
    local state = frame._msufA3State
    if state then return state end
    local root = frame.Auras
    if not (root and root.SetAllPoints) then
        root = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        root:SetAllPoints(frame)
        frame.Auras = root
    end
    state = {
        frame = frame,
        root = root,
        lanes = {},
        configGen = 0,
        needFullUpdate = true,
    }
    frame._msufA3State = state
    root.__owner = frame
    local buffLane = EnsureLane(root, state, "buff")
    local debuffLane = EnsureLane(root, state, "debuff")
    root.Buffs = buffLane.frame
    root.Debuffs = debuffLane.frame
    return state
end

local function ApplyConfigLane(root, state, cfg, kind)
    local laneConfig = cfg.lanes and cfg.lanes[kind]
    local lane = EnsureLane(root, state, kind, laneConfig)
    lane.unit = cfg.unit
    lane.ownerFrame = state.frame
    lane.config = laneConfig
    if lane.config and lane.config.rootKey then root[lane.config.rootKey] = lane.frame end
    if lane.config and lane.config.enabled then
        if lane.config.sortReverse == true then
            local comparator = lane.config.priorityComparator or SortComparator(lane.config.sortOrder)
            lane.config.sortComparator = function(a, b) return comparator(b, a) end
        elseif not lane.config.sortComparator then
            lane.config.sortComparator = SortComparator(lane.config.sortOrder)
        end
        lane.updateButton = BuildButtonUpdater and BuildButtonUpdater(lane.config) or UpdateButton
        if lane.config.renderEnabled == true then
            lane.frame:Show()
            ApplyLaneLayout(lane)
            PrewarmLaneButtons(lane, state.frame)
        else
            lane.frame:Hide()
        end
    else
        lane.updateButton = nil
        lane.frame:Hide()
        ClearLane(lane)
    end
end

local function ApplyConfig(frame, cfg)
    local state = EnsureState(frame)
    if frame._msufA3PurgeActive == true and cfg.purgeEnabled ~= true then Backend.FrameVisuals.UpdatePurgeVisual(frame) end
    local root = state.root
    root:SetAllPoints(frame)
    root:Show()
    state.unit = cfg.unit
    state.config = cfg
    state.configGen = A3._runtimeConfigGen or 1
    state.frameSpec = frame.MSUFSpec
    state.needFullUpdate = true

    for kind, lane in pairs(state.lanes) do
        if not (cfg.lanes and cfg.lanes[kind]) then
            lane.config = nil
            lane.frame:Hide()
            ClearLane(lane)
        end
    end
    local order = cfg.laneOrder or BASE_LANE_ORDER
    for i = 1, #order do ApplyConfigLane(root, state, cfg, order[i]) end
    return state
end

local function HideState(frame)
    local state = frame and frame._msufA3State
    if not state then return end
    for _, lane in pairs(state.lanes or EMPTY_LANES) do
        -- Portrait-anchored lanes are parented outside state.root, so hiding
        -- only the root can leave their already-rendered buttons on screen.
        if lane.frame then lane.frame:Hide() end
        ClearLane(lane)
    end
    if state.root then state.root:Hide() end
    ClearFrameAuraVisualState(frame)
end

local function AddAuraToLane(lane, unit, data, fromLaneScan)
    data = ProcessData(lane, unit, data, fromLaneScan)
    if not data then return false, nil end
    local auraInstanceID = data.auraInstanceID
    local isNew = lane.all[auraInstanceID] == nil
    lane.all[auraInstanceID] = data
    -- Arrival order is kept for the natural-order render alone, which also
    -- compacts it (RenderLaneNatural). A sorted lane rebuilds its order from
    -- lane.active on every render, so an id appended there was never read or
    -- dropped again and the list grew with every delta-added aura until the
    -- next full scan.
    if isNew and lane.config.naturalOrder == true then
        local n = (lane.orderedCount or 0) + 1
        lane.ordered[n] = auraInstanceID
        lane.orderedCount = n
    end
    -- Frame cleanse visuals read every aura the lane scanned, so an aura the
    -- icon filters drop still reaches them (CompileLane).
    if lane._msufA3VisualCacheReady == true then
        ConsiderLaneAuraVisual(lane, unit, data)
    end
    if lane.config.hasFilterWork ~= true or ShouldShowAura(lane, unit, data) then
        lane.active[auraInstanceID] = true
        return true, data
    end
    lane.active[auraInstanceID] = nil
    lane.orderDirty = true
    return false, data
end

local function AddVisibleAuraToCappedLane(lane, unit, data, fromLaneScan)
    data = ProcessData(lane, unit, data, fromLaneScan)
    if not data then return false, nil end
    if lane.config.hasFilterWork == true and ShouldShowAura(lane, unit, data) ~= true then
        return false, data
    end
    local auraInstanceID = data.auraInstanceID
    lane.all[auraInstanceID] = data
    lane.active[auraInstanceID] = true
    if lane._msufA3VisualCacheReady == true then
        ConsiderLaneAuraVisual(lane, unit, data)
    end
    return true, data
end

local AURA_UTIL_SCAN = {}

--- Full scans rebuild lane state from Blizzard aura data. Deltas are preferred
--- for normal UNIT_AURA, but full scans remain the correctness fallback when
--- Blizzard reports isFullUpdate, the capped visible-only scan loses context,
--- config changes, or identity changes make old lane state untrustworthy.
local function AuraUtilScanCallback(data)
    local scan = AURA_UTIL_SCAN
    local lane = scan.lane
    local unit = scan.unit
    local active, processed = scan.addAura(lane, unit, data, true)
    if scan.inlineRender == true
        and active == true
        and processed
        and scan.visible < scan.maxVisible then
        local visible = scan.visible + 1
        scan.visible = visible
        local button = EnsureButton(lane, visible)
        scan.updateButton(lane, button, unit, processed)
        scan.visibleByID[processed.auraInstanceID] = visible
        if scan.capped == true and visible >= scan.maxVisible then return true end
    end
end

--- Inject one enchanted weapon slot as a synthetic aura. Each slot keeps one
--- data table on the lane that is refilled in place. Every field is written on
--- every call (icon may become nil), so reuse never carries a previous scan's
--- values. FullScanLane's ResetLaneData has already wiped lane.all, active and
--- ordered, so a slot whose enchant ended leaves no entry behind.
local function AppendClassicWeaponEnchantSlot(lane, unit, slot, hasEnchant, expiration, charges, now,
    inlineRender, visible, maxVisible, visibleByID, updateButton)
    local expirationMS = tonumber(expiration)
    if not (hasEnchant == true and expirationMS and expirationMS > 0) then
        return visible
    end
    local remaining = expirationMS * 0.001
    local duration = remaining <= 600 and 600
        or (remaining <= 1800 and 1800 or math_ceil(remaining / 3600) * 3600)
    local dataBySlot = lane._msufA3WeaponEnchantData
    if not dataBySlot then
        dataBySlot = {}
        lane._msufA3WeaponEnchantData = dataBySlot
    end
    local data = dataBySlot[slot]
    if not data then
        data = {}
        dataBySlot[slot] = data
    end
    local auraInstanceID = -1000 - slot
    data.auraInstanceID = auraInstanceID
    data.isHelpful = true
    data.isHarmful = false
    data.isFromPlayerOrPlayerPet = true
    data.isPlayerAura = true
    lane.mine[auraInstanceID] = true
    data.name = _G.ENCHANTED or "Weapon Enchant"
    data.icon = _G.GetInventoryItemTexture and _G.GetInventoryItemTexture("player", slot) or nil
    data.applications = tonumber(charges) or 0
    data.duration = duration
    data.expirationTime = now + remaining
    data.timeMod = 1
    data.spellId = 0
    data._msufA3WeaponEnchantSlot = slot
    lane.all[auraInstanceID] = data
    lane.active[auraInstanceID] = true
    lane.orderedCount = (lane.orderedCount or 0) + 1
    lane.ordered[lane.orderedCount] = auraInstanceID
    if inlineRender == true and visible < maxVisible then
        visible = visible + 1
        local button = EnsureButton(lane, visible)
        updateButton(lane, button, unit, data)
        visibleByID[auraInstanceID] = visible
    end
    return visible
end

local function AppendWeaponEnchants(lane, unit, inlineRender, visible, maxVisible, visibleByID, updateButton)
    local cfg = lane and lane.config
    if not (cfg and cfg.weaponEnchants == true and unit == "player" and type(_G.GetWeaponEnchantInfo) == "function") then
        return visible
    end
    -- GetWeaponEnchantInfo reports main hand, off hand, then ranged in blocks
    -- of four; inventory slots 16/17/18 follow the same order. The returns are
    -- read into locals instead of being packed into a table on every scan.
    local mainHas, mainExpiration, mainCharges, _,
        offHas, offExpiration, offCharges, _,
        rangedHas, rangedExpiration, rangedCharges = _G.GetWeaponEnchantInfo()
    local now = _G.GetTime and _G.GetTime() or 0
    -- Injection order is ranged, off hand, then main hand.
    visible = AppendClassicWeaponEnchantSlot(lane, unit, 18, rangedHas, rangedExpiration, rangedCharges, now,
        inlineRender, visible, maxVisible, visibleByID, updateButton)
    visible = AppendClassicWeaponEnchantSlot(lane, unit, 17, offHas, offExpiration, offCharges, now,
        inlineRender, visible, maxVisible, visibleByID, updateButton)
    visible = AppendClassicWeaponEnchantSlot(lane, unit, 16, mainHas, mainExpiration, mainCharges, now,
        inlineRender, visible, maxVisible, visibleByID, updateButton)
    return visible
end

local function FullScanLane(lane, unit, renderInline)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false end
    -- One scan shares the source-is-player answers (Filters.ProcessData).
    SourceMemo.serial = SourceMemo.serial + 1

    local inlineRender = renderInline == true
        and cfg.naturalOrder == true
        and cfg.renderEnabled == true
        and cfg.max > 0
    local cappedScan = inlineRender
        and cfg.visibleOnlyScan == true
        and (cfg.hasFilterWork ~= true or cfg.cappedFilterScan == true)
    local visibleByID = inlineRender and lane.visibleByID or nil
    local updateButton = inlineRender and (lane.updateButton or UpdateButton) or nil
    local visible = 0
    local maxVisible = cfg.max or 0
    local slotLimit = cappedScan and maxVisible or nil
    local addAura = cappedScan and AddVisibleAuraToCappedLane or AddAuraToLane
    ResetLaneData(lane, cappedScan)
    lane._msufA3CappedFullScan = cappedScan or nil
    visible = AppendWeaponEnchants(lane, unit, inlineRender, visible, maxVisible, visibleByID, updateButton)

    if GetAuraSlots and GetAuraDataBySlot then
        if not cappedScan then
            local slots, count
            slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter))
            lane.slotScratch = slots
            if inlineRender then
                for i = 2, count do
                    local active, processed = addAura(lane, unit, GetAuraDataBySlot(unit, slots[i]), true)
                    if active == true and processed and visible < maxVisible then
                        visible = visible + 1
                        local button = EnsureButton(lane, visible)
                        updateButton(lane, button, unit, processed)
                        visibleByID[processed.auraInstanceID] = visible
                    end
                end
            else
                for i = 2, count do
                    addAura(lane, unit, GetAuraDataBySlot(unit, slots[i]), true)
                end
            end
        else
            local continuation
            while true do
                local slots, count
                if continuation ~= nil then
                    slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter, slotLimit, continuation))
                else
                    slots, count = FillAuraSlots(lane.slotScratch, GetAuraSlots(unit, cfg.filter, slotLimit))
                end
                lane.slotScratch = slots
                continuation = slots[1]
                for i = 2, count do
                    local active, processed = addAura(lane, unit, GetAuraDataBySlot(unit, slots[i]), true)
                    if active == true and processed and visible < maxVisible then
                        visible = visible + 1
                        local button = EnsureButton(lane, visible)
                        updateButton(lane, button, unit, processed)
                        visibleByID[processed.auraInstanceID] = visible
                        if visible >= maxVisible then break end
                    end
                end
                if visible >= maxVisible or IsSecret(continuation) or continuation == nil then
                    break
                end
            end
        end
        if inlineRender then HideTrailingButtons(lane, visibleByID, visible) end
        return true, inlineRender
    end

    local forEachAura = AuraUtil and AuraUtil.ForEachAura
    if type(forEachAura) == "function" then
        local auraUtilLimit = cappedScan and cfg.hasFilterWork ~= true and maxVisible or nil
        local scan = AURA_UTIL_SCAN
        scan.lane = lane
        scan.unit = unit
        scan.addAura = addAura
        scan.inlineRender = inlineRender
        scan.visibleByID = visibleByID
        scan.updateButton = updateButton
        scan.maxVisible = maxVisible
        scan.visible = visible
        scan.capped = cappedScan
        forEachAura(unit, cfg.filter, auraUtilLimit, AuraUtilScanCallback, true)
        visible = scan.visible or visible
        scan.lane = nil
        scan.unit = nil
        scan.addAura = nil
        scan.inlineRender = nil
        scan.visibleByID = nil
        scan.updateButton = nil
        scan.maxVisible = nil
        scan.visible = nil
        scan.capped = nil
        if inlineRender then HideTrailingButtons(lane, visibleByID, visible) end
        return true, inlineRender
    end

    if inlineRender then HideTrailingButtons(lane, visibleByID, visible) end
    return true, inlineRender
end

local function UpdateLaneFromDelta(lane, unit, updateInfo)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false end
    local needsRender = false
    local visualEnabled = cfg.visual and cfg.visual.enabled == true and cfg.visualDirect ~= true
    local visualDirty = false
    local updateButton = lane.updateButton or UpdateButton

    local added = updateInfo and updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local data = added[i]
            local auraInstanceID = data and data.auraInstanceID
            if auraInstanceID ~= nil and DataMatchesLane(data, cfg) then
                local active, stored = AddAuraToLane(lane, unit, data)
                if active then
                    needsRender = true
                elseif stored and visualEnabled then
                    visualDirty = true
                end
            end
        end
    end

    local updated = updateInfo and updateInfo.updatedAuraInstanceIDs
    if updated and GetAuraDataByAuraInstanceID then
        for i = 1, #updated do
            local auraInstanceID = updated[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local oldData = lane.all[auraInstanceID]
                local oldPlayer = lane.mine[auraInstanceID]
                -- Time-keyed sorts re-render only when a sort input moved. Read
                -- the old values before the fetch, and as plain numbers: the
                -- comparators rank a secret or missing time as one constant.
                local oldDuration, oldExpiration
                if cfg.reorderOnUpdate == true then
                    oldDuration, oldExpiration = PlainNumber(oldData.duration), PlainNumber(oldData.expirationTime)
                end
                local wasActive = lane.active[auraInstanceID] == true
                local data = ProcessData(lane, unit, GetAuraDataByAuraInstanceID(unit, auraInstanceID))
                if data then
                    lane.all[auraInstanceID] = data
                    local nowActive = cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data)
                    -- The cached visual comes from every stored aura, yet an
                    -- in-place refresh keeps an aura's dispel type and filter
                    -- membership. A filtered-out aura moves it only by flipping
                    -- its owner (Cast by me); a shown one, or one entering the
                    -- lane, also moves the stripe.
                    if visualEnabled and (wasActive or nowActive
                        or oldPlayer ~= lane.mine[auraInstanceID]) then
                        lane._msufA3VisualCacheReady = nil
                        visualDirty = true
                    end
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        if wasActive then
                            if oldPlayer ~= lane.mine[auraInstanceID]
                                or (cfg.reorderOnUpdate == true
                                    and (oldDuration ~= PlainNumber(data.duration)
                                        or oldExpiration ~= PlainNumber(data.expirationTime))) then
                                needsRender = true
                            else
                                local index = lane.visibleByID and lane.visibleByID[auraInstanceID]
                                local button = index and lane[index]
                                if button then
                                    updateButton(lane, button, unit, data)
                                end
                            end
                        else
                            needsRender = true
                        end
                    else
                        lane.active[auraInstanceID] = nil
                        lane.orderDirty = true
                        if wasActive then needsRender = true end
                    end
                else
                    lane.all[auraInstanceID] = nil
                    lane.mine[auraInstanceID] = nil
                    lane.orderDirty = true
                    if visualEnabled then
                        lane._msufA3VisualCacheReady = nil
                        visualDirty = true
                    end
                    if wasActive then
                        lane.active[auraInstanceID] = nil
                        needsRender = true
                    end
                end
            end
        end
    end

    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local auraInstanceID = removed[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                lane.all[auraInstanceID] = nil
                lane.mine[auraInstanceID] = nil
                lane.orderDirty = true
                if visualEnabled then
                    lane._msufA3VisualCacheReady = nil
                    visualDirty = true
                end
                if lane.active[auraInstanceID] then
                    lane.active[auraInstanceID] = nil
                    needsRender = true
                elseif lane.orderDirty and lane.orderedCount > 96 then
                    CompactLaneOrder(lane)
                end
            end
        end
    end

    return needsRender, visualDirty
end

local function UpdateCappedLaneFromDelta(lane, unit, updateInfo)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false, false end

    local added = updateInfo and updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local data = added[i]
            if data and data.auraInstanceID ~= nil and DataMatchesLane(data, cfg) then
                if cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data) == true then
                    return true, true
                end
            end
        end
    end

    local needsFullScan = false
    local changed = false
    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local auraInstanceID = removed[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                if lane.active[auraInstanceID] == true then
                    needsFullScan = true
                end
                lane.all[auraInstanceID] = nil
                lane.mine[auraInstanceID] = nil
                lane.active[auraInstanceID] = nil
                lane.orderDirty = true
            end
        end
        if needsFullScan then return true, true end
    end

    local updated = updateInfo and updateInfo.updatedAuraInstanceIDs
    if updated and GetAuraDataByAuraInstanceID then
        local visibleByID = lane.visibleByID
        local updateButton = lane.updateButton or UpdateButton
        for i = 1, #updated do
            local auraInstanceID = updated[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local data = ProcessData(lane, unit, GetAuraDataByAuraInstanceID(unit, auraInstanceID))
                local wasActive = lane.active[auraInstanceID] == true
                if data then
                    lane.all[auraInstanceID] = data
                    local nowActive = cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data)
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        local index = visibleByID and visibleByID[auraInstanceID]
                        local button = index and lane[index]
                        if wasActive and button then
                            updateButton(lane, button, unit, data)
                            changed = true
                        else
                            return true, true
                        end
                    else
                        lane.active[auraInstanceID] = nil
                        lane.orderDirty = true
                        if wasActive then return true, true end
                    end
                else
                    lane.all[auraInstanceID] = nil
                    lane.mine[auraInstanceID] = nil
                    lane.active[auraInstanceID] = nil
                    lane.orderDirty = true
                    if wasActive then return true, true end
                end
            end
        end
    end

    return changed, false
end

--- Drops only the ids that left lane.all. An aura that is tracked but filtered
--- out keeps its slot: AddAuraToLane appends an id once, when it enters
--- lane.all, so an update that makes it visible again could never put it back.
CompactLaneOrder = function(lane)
    local ordered = lane.ordered
    local all = lane.all
    local write = 0
    for i = 1, lane.orderedCount or 0 do
        local auraInstanceID = ordered[i]
        if all[auraInstanceID] then
            write = write + 1
            ordered[write] = auraInstanceID
        end
    end
    for i = write + 1, lane.orderedCount or 0 do
        ordered[i] = nil
    end
    lane.orderedCount = write
    lane.orderDirty = nil
end

local function RenderLaneNatural(lane, unit, cfg)
    local visibleByID = WipeTable(lane.visibleByID)
    local ordered = lane.ordered
    local all = lane.all
    local active = lane.active
    local updateButton = lane.updateButton or UpdateButton
    local visible = 0
    local maxVisible = cfg.max
    for i = 1, lane.orderedCount or 0 do
        local auraInstanceID = ordered[i]
        if active[auraInstanceID] then
            local data = all[auraInstanceID]
            if data then
                visible = visible + 1
                local button = EnsureButton(lane, visible)
                updateButton(lane, button, unit, data)
                visibleByID[auraInstanceID] = visible
                if visible >= maxVisible then break end
            end
        end
    end
    HideTrailingButtons(lane, visibleByID, visible)
    if lane.orderDirty == true and (lane.orderedCount or 0) > 96 then
        CompactLaneOrder(lane)
    end
    return true
end

local function RenderLane(lane, unit)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then
        ClearLane(lane)
        return false
    end
    if cfg.max <= 0 or cfg.renderEnabled ~= true then
        for i = 1, lane.visible do
            local button = lane[i]
            if button then
                button.auraInstanceID = nil
                HideButton(button)
            end
        end
        lane.visibleByID = WipeTable(lane.visibleByID)
        lane.visible = 0
        return true
    end
    if cfg.naturalOrder == true then
        return RenderLaneNatural(lane, unit, cfg)
    end
    local sorted = WipeTable(lane.sorted)
    local count = 0
    for auraInstanceID in next, lane.active do
        local data = lane.all[auraInstanceID]
        if data then
            count = count + 1
            sorted[count] = data
        end
    end
    if count > 1 then
        -- The comparators read this lane's ownership answers (lane.mine).
        Compile.SetSortOwnership(lane.mine)
        table_sort(sorted, cfg.sortComparator or SortAuras)
        Compile.SetSortOwnership(nil)
    end

    local visible = math_min(cfg.max, count)
    local visibleByID = WipeTable(lane.visibleByID)
    local updateButton = lane.updateButton or UpdateButton
    for i = 1, visible do
        local button = EnsureButton(lane, i)
        local data = sorted[i]
        updateButton(lane, button, unit, data)
        visibleByID[data.auraInstanceID] = i
    end
    HideTrailingButtons(lane, visibleByID, visible)
    return true
end

local function LaneAffectsFrameAuraVisual(lane)
    local cfg = lane and lane.config
    return cfg and cfg.visual and cfg.visual.enabled == true and cfg.visualDirect ~= true or false
end

--- Runtime update path for one lane. It chooses full scan vs delta merge,
--- renders only when the visible order changed, and reports whether frame-level
--- aura visuals need to be recomputed. rangeTrusted is the caller's once-per-
--- event native PLAYER filter trust (false only for an explicitly out-of-range
--- unit); it is nil when no enabled lane before this one needed it.
local function UpdateAuraLaneRuntime(lane, unit, updateInfo, full, rangeTrusted)
    if not (lane and lane.config and lane.config.enabled) then
        return false, false
    end
    local cfg = lane.config
    if cfg.nativePlayerFilter == true then
        lane._msufA3NativePlayerFilterTrusted = rangeTrusted ~= false
    else
        lane._msufA3NativePlayerFilterTrusted = nil
    end
    local laneAffectsVisual = LaneAffectsFrameAuraVisual(lane)
    if full then
        local changed, rendered = FullScanLane(lane, unit, true)
        if changed then
            if rendered ~= true then
                RenderLane(lane, unit)
            end
            return true, laneAffectsVisual
        end
        return false, false
    end
    if lane._msufA3CappedFullScan == true then
        local changed, needsFullScan = UpdateCappedLaneFromDelta(lane, unit, updateInfo)
        if needsFullScan == true then
            local scanned, rendered = FullScanLane(lane, unit, true)
            if scanned then
                if rendered ~= true then
                    RenderLane(lane, unit)
                end
                return true, laneAffectsVisual
            end
            return false, false
        end
        return changed == true, changed == true and laneAffectsVisual or false
    end
    local needsRender, visualDirty = UpdateLaneFromDelta(lane, unit, updateInfo)
    if needsRender then
        RenderLane(lane, unit)
        return true, laneAffectsVisual
    end
    if visualDirty then
        return true, true
    end
    return false, false
end

Lanes.EMPTY_LANES = EMPTY_LANES
Lanes.EnsureState = EnsureState
Lanes.ApplyConfig = ApplyConfig
Lanes.HideState = HideState
Lanes.ClearLane = ClearLane
Lanes.RenderLane = RenderLane
Lanes.UpdateAuraLaneRuntime = UpdateAuraLaneRuntime
Backend.Lanes = Lanes
