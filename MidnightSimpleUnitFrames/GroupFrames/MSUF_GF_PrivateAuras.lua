-- MSUF_GF_PrivateAuras.lua — Private aura anchoring for Group Frames
-- 12.0.5+ baseline. No fallback paths.
--
-- 12.0.5 lifted combat-lockdown restrictions on AddPrivateAuraAnchor /
-- RemovePrivateAuraAnchor / SetPrivateWarningTextAnchor / RemovePrivateAura-
-- AppliedSound. We don't use AddPrivateAuraAppliedSound (still restricted
-- during encounters/M+/PvP), so this file has zero combat-aware code.
--
-- Blizzard-like private/dispel indicators are handled by the shared native
-- aura renderer. The custom Private Aura path here only owns explicit private
-- aura icon anchors.
local _, ns = ...
ns.GF = ns.GF or {}
local GF = ns.GF

local C_Timer     = _G.C_Timer
local CreateFrame = _G.CreateFrame
local math_floor  = math.floor
local math_max    = math.max
local type        = type

local function ScaleFrameValue(value, scale, minValue)
    value = tonumber(value) or 0
    scale = tonumber(scale) or 1
    local v
    if scale == 1 then
        v = value
    elseif GF.ScaleValue then
        v = GF.ScaleValue(value, scale, minValue)
    else
        local scaled = value * scale
        if scaled >= 0 then
            v = math_floor(scaled + 0.5)
        else
            v = -math_floor((-scaled) + 0.5)
        end
        if minValue ~= nil and v < minValue then v = minValue end
    end
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

-- Direct localizations: 12.0.5+ guarantees these APIs exist.
local AddPrivateAuraAnchor    = _G.C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = _G.C_UnitAuras.RemovePrivateAuraAnchor

local function AddPrivateAuraAnchorSafe(args)
    if type(AddPrivateAuraAnchor) ~= "function" then return nil, "AddPrivateAuraAnchor unavailable" end
    local ok, anchorID = pcall(AddPrivateAuraAnchor, args)
    if ok then return anchorID end
    return nil, anchorID
end

local function HasNativeBlizzardPrivateAuras(conf)
    if not (conf and GF.IsBlizzardAuraTypeEnabled) then return false end
    return GF.IsBlizzardAuraTypeEnabled(conf, "privateAuras")
end

local function ForceFrameLevelRefresh(frame)
    if not frame or not frame.GetFrameLevel or not frame.SetFrameLevel then return end
    local level = frame:GetFrameLevel()
    frame:SetFrameLevel(0)
    frame:SetFrameLevel(level)
end

local function SyncSlotLayer(slot, container)
    if not (slot and container) then return end
    if slot.SetFrameStrata and container.GetFrameStrata then
        local strata = container:GetFrameStrata()
        if strata and (not slot.GetFrameStrata or slot:GetFrameStrata() ~= strata) then
            slot:SetFrameStrata(strata)
        end
    end
    if slot.SetFrameLevel and container.GetFrameLevel then
        local lvl = (container:GetFrameLevel() or 0) + 1
        if not slot.GetFrameLevel or slot:GetFrameLevel() ~= lvl then
            slot:SetFrameLevel(lvl)
        end
    end
end

local function ClearContainerOverlay(f)
    if not f then return end
    if f._gfPrivContainerOverlayID then
        RemovePrivateAuraAnchor(f._gfPrivContainerOverlayID)
    end
    f._gfPrivContainerOverlayID = nil
    f._gfPrivContainerOverlayUnit = nil
    f._gfPrivCOCached = nil
    if f._gfPrivOverlayFrame then f._gfPrivOverlayFrame:Hide() end
end

local TriggerPrivateAuraShowDispelType = _G.C_UnitAuras and _G.C_UnitAuras.TriggerPrivateAuraShowDispelType
local privateAuraShowDispelType = false
local privateAuraShowDispelCount = 0

local function UpdatePrivateAuraShowDispelType(f, enabled)
    local want = enabled == true
    local prev = f and f._gfPrivShowDispelType == true
    if prev == want then return end
    if f then f._gfPrivShowDispelType = want end
    if want then
        privateAuraShowDispelCount = privateAuraShowDispelCount + 1
    else
        privateAuraShowDispelCount = privateAuraShowDispelCount - 1
        if privateAuraShowDispelCount < 0 then privateAuraShowDispelCount = 0 end
    end
    local show = privateAuraShowDispelCount > 0
    if privateAuraShowDispelType ~= show then
        privateAuraShowDispelType = show
        if type(TriggerPrivateAuraShowDispelType) == "function" then
            pcall(TriggerPrivateAuraShowDispelType, show)
        end
    end
end

------------------------------------------------------------------------
-- Clear anchors for a frame (icon anchors + optional container overlay)
------------------------------------------------------------------------
local function ClearAnchors(f)
    UpdatePrivateAuraShowDispelType(f, false)
    -- Icon anchor IDs
    local ids = f._gfPrivAnchorIDs
    if type(ids) == "table" then
        for i = 1, #ids do
            local id = ids[i]
            if id then RemovePrivateAuraAnchor(id) end
        end
    end
    f._gfPrivAnchorIDs = nil
    f._gfPrivUnit = nil
    f._gfPrivSize = nil
    f._gfPrivMax = nil
    f._gfPrivAnchor = nil
    f._gfPrivX = nil
    f._gfPrivY = nil
    f._gfPrivLayer = nil
    f._gfPrivDir = nil
    f._gfPrivSpacing = nil
    f._gfPrivCountdown = nil
    f._gfPrivNumbers = nil

    ClearContainerOverlay(f)

    local slots = f._gfPrivSlots
    if type(slots) == "table" then
        for i = 1, #slots do if slots[i] then slots[i]:Hide() end end
    end
    if f._gfPrivContainer then f._gfPrivContainer:Hide() end
end

------------------------------------------------------------------------
-- Slot normalization (mirrors A2_Render pattern)
------------------------------------------------------------------------
local function RelaxTexSnap(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end

local function NormalizeSlot(slot, sz)
    if not slot then return end
    sz = math_floor((tonumber(sz) or 20) + 0.5)
    if sz < 1 then sz = 1 end
    slot:SetSize(sz, sz)
    slot._gfPrivSz = sz
    local child = select(1, slot:GetChildren())
    if child then
        child:ClearAllPoints()
        child:SetAllPoints(slot)
        if child.Icon then
            child.Icon:ClearAllPoints()
            child.Icon:SetAllPoints(child)
            RelaxTexSnap(child.Icon)
        end
        if child.Cooldown then
            child.Cooldown:ClearAllPoints()
            child.Cooldown:SetAllPoints(child)
        end
    end
end

local function NormalizeAllSlots(f, sz)
    local slots = f._gfPrivSlots
    if not slots then return end
    local container = f._gfPrivContainer
    for i = 1, #slots do
        local s = slots[i]
        if s and s:IsShown() then
            SyncSlotLayer(s, container)
            NormalizeSlot(s, sz)
        end
    end
end

------------------------------------------------------------------------
-- Apply private auras for a GF frame
------------------------------------------------------------------------
function GF.ApplyPrivateAuras(f, unit)
    if not f then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf then ClearAnchors(f); return end
    local pa = conf.privateAuras

    if conf.auras and conf.auras.enabled == false then
        ClearAnchors(f)
        return
    end

    if HasNativeBlizzardPrivateAuras(conf) then
        ClearAnchors(f)
        return
    end

    -- Read from nested privateAuras table (migrated) or flat keys (legacy)
    local paEnabled, paMax, paSize, paAnchor, paX, paY, paCountdown, paDirection, paNumbers, paLayer, paShowDispelType
    if pa and pa.enabled ~= nil then
        paEnabled   = pa.enabled
        paMax       = pa.max or 4
        paSize      = pa.size or 20
        paAnchor    = pa.anchor or "TOPRIGHT"
        paDirection = pa.direction or "LEFT"
        paX         = pa.x or 0
        paY         = pa.y or 0
        paCountdown = pa.showCountdown ~= false
        paNumbers   = pa.showNumbers == true
        paLayer     = pa.layer or 8
        paShowDispelType = pa.showDispelType == true
    else
        paEnabled   = conf.privateAurasEnabled
        paMax       = conf.privateAuraMax or 4
        paSize      = conf.privateAuraSize or 20
        paAnchor    = conf.privateAuraAnchor or "TOPRIGHT"
        paDirection = "LEFT"
        paX         = conf.privateAuraX or 0
        paY         = conf.privateAuraY or 0
        paCountdown = conf.privateAuraCountdown ~= false
        paNumbers   = false
        paLayer     = 8
        paShowDispelType = conf.privateAuraShowDispelType == true
    end

    -- Feature disabled → clear
    if paEnabled == false then
        ClearAnchors(f)
        return
    end

    -- No unit → clear
    if not unit then ClearAnchors(f); return end

    local maxN = math_max(0, math_floor((tonumber(paMax) or 4) + 0.5))
    if maxN == 0 then ClearAnchors(f); return end
    if maxN > 12 then maxN = 12 end
    UpdatePrivateAuraShowDispelType(f, paShowDispelType)

    local frameScale = 1
    if kind then
        if conf and conf._resolvedFrameScale then
            frameScale = conf._resolvedFrameScale
        elseif GF.GetFrameScale then
            frameScale = GF.GetFrameScale(kind) or 1
        end
    end

    local iconSz = ScaleFrameValue(paSize or 20, frameScale, 8)
    local pt = paAnchor
    local ox = ScaleFrameValue(paX or 0, frameScale)
    local oy = ScaleFrameValue(paY or 0, frameScale)
    local countdown = paCountdown
    local showNumbers = paNumbers == true
    local spacing = ScaleFrameValue((pa and pa.spacing) or 1, frameScale, 0)

    -- Diff check: skip rebuild if all structural settings match.
    -- ox / oy / paLayer are NOT structural — they only reposition the
    -- container, so we apply them via a cheap fast-path without tearing
    -- down the AddPrivateAuraAnchor registrations (which is what made the
    -- options X/Y sliders and Layer dropdown appear to do nothing).
    if f._gfPrivUnit == unit
       and f._gfPrivSize == iconSz
       and f._gfPrivMax == maxN
       and f._gfPrivAnchor == pt
       and f._gfPrivDir == paDirection
       and f._gfPrivSpacing == spacing
       and f._gfPrivCountdown == countdown
       and f._gfPrivNumbers == showNumbers
       and type(f._gfPrivAnchorIDs) == "table"
    then
        local container = f._gfPrivContainer
        if container then
            -- Cheap reposition: only the anchor offset and layer changed.
            if f._gfPrivX ~= ox or f._gfPrivY ~= oy then
                f._gfPrivX, f._gfPrivY = ox, oy
                local parent = container:GetParent() or f.statusIconLayer or f.barGroup or f
                container:ClearAllPoints()
                container:SetPoint(pt, parent, pt, ox, oy)
            end
            if f._gfPrivLayer ~= paLayer then
                f._gfPrivLayer = paLayer
                local parent = container:GetParent() or f.statusIconLayer or f.barGroup or f
                if GF.SetFrameLayerLevel then
                    GF.SetFrameLayerLevel(container, f, paLayer, 8)
                else
                    container:SetFrameLevel(parent:GetFrameLevel() + paLayer)
                end
            end
            container:Show()
        end
        NormalizeAllSlots(f, iconSz)
        return
    end

    ClearAnchors(f)

    -- Create container if needed
    local parent = f.statusIconLayer or f.barGroup or f
    local container = f._gfPrivContainer
    if not container then
        container = CreateFrame("Frame", nil, parent)
        container:EnableMouse(false)
        if container.SetClipsChildren then container:SetClipsChildren(false) end
        f._gfPrivContainer = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end
    if container.SetClipsChildren then container:SetClipsChildren(false) end

    -- Direction-aware container sizing + slot positioning
    local isVertical = (paDirection == "TOP" or paDirection == "BOTTOM")
    local totalPrimary = maxN * iconSz + (maxN - 1) * spacing

    container:ClearAllPoints()
    if isVertical then
        container:SetSize(iconSz, totalPrimary)
    else
        container:SetSize(totalPrimary, iconSz)
    end
    container:SetPoint(pt, parent, pt, ox, oy)
    if GF.SetFrameLayerLevel then
        GF.SetFrameLayerLevel(container, f, paLayer, 8)
    else
        container:SetFrameLevel(parent:GetFrameLevel() + paLayer)
    end
    container:Show()

    -- Store diff keys
    f._gfPrivUnit = unit
    f._gfPrivSize = iconSz
    f._gfPrivMax = maxN
    f._gfPrivAnchor = pt
    f._gfPrivDir = paDirection
    f._gfPrivX = ox
    f._gfPrivY = oy
    f._gfPrivLayer = paLayer
    f._gfPrivSpacing = spacing
    f._gfPrivCountdown = countdown
    f._gfPrivNumbers = showNumbers
    f._gfPrivAnchorIDs = {}

    local slots = f._gfPrivSlots or {}
    f._gfPrivSlots = slots
    local step = iconSz + spacing

    -- Direction vectors for slot positioning
    local slotAnchor, slotDX, slotDY
    if paDirection == "LEFT" then
        slotAnchor = "RIGHT"; slotDX = -step; slotDY = 0
    elseif paDirection == "RIGHT" then
        slotAnchor = "LEFT"; slotDX = step; slotDY = 0
    elseif paDirection == "TOP" then
        slotAnchor = "BOTTOM"; slotDX = 0; slotDY = step
    elseif paDirection == "BOTTOM" then
        slotAnchor = "TOP"; slotDX = 0; slotDY = -step
    else
        slotAnchor = "LEFT"; slotDX = step; slotDY = 0
    end

    local borderScale = iconSz / 10

    -- Reuse args table
    local args = f._gfPrivArgs
    if not args then
        args = {
            unitToken = unit,
            auraIndex = 1,
            parent = nil,
            showCountdownFrame = countdown,
            showCountdownNumbers = showNumbers,
            -- 12.0.5 REQUIRED FIELD for slot/index anchors too.
            -- GF icon private auras still use the same one-anchor-per-slot
            -- model as Auras2, so this path must stay non-container.
            isContainer = false,
            iconInfo = {
                iconWidth = iconSz,
                iconHeight = iconSz,
                borderScale = borderScale,
                iconAnchor = {
                    point = "CENTER", relativeTo = nil, relativePoint = "CENTER",
                    offsetX = 0, offsetY = 0,
                },
            },
        }
        f._gfPrivArgs = args
    end

    local Native = ns and ns.MSUF_AuraNative
    local ensureDispelOverlay = Native and Native.EnsurePrivateAuraDispelOverlay
    for i = 1, maxN do
        local slot = slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, container)
            if slot.SetClipsChildren then slot:SetClipsChildren(false) end
            if not slot._gfPrivSizeHook then
                slot._gfPrivSizeHook = true
                slot:HookScript("OnSizeChanged", function(self)
                    NormalizeSlot(self, self._gfPrivSz or iconSz)
                end)
            end
            slots[i] = slot
        end
        if ensureDispelOverlay then
            ensureDispelOverlay(slot)
        end
        SyncSlotLayer(slot, container)
        slot:ClearAllPoints()
        slot:SetPoint(slotAnchor, container, slotAnchor, (i - 1) * slotDX, (i - 1) * slotDY)
        NormalizeSlot(slot, iconSz)
        slot:Show()

        args.unitToken = unit
        args.auraIndex = i
        args.parent = slot
        args.showCountdownFrame = countdown
        args.showCountdownNumbers = showNumbers
        args.isContainer = false
        args.iconInfo.iconWidth = iconSz
        args.iconInfo.iconHeight = iconSz
        args.iconInfo.borderScale = borderScale
        args.iconInfo.iconAnchor.relativeTo = slot

        local anchorID = AddPrivateAuraAnchorSafe(args)
        if anchorID then
            f._gfPrivAnchorIDs[#f._gfPrivAnchorIDs + 1] = anchorID
            ForceFrameLevelRefresh(slot)
        end
    end

    NormalizeAllSlots(f, iconSz)
    -- Queue deferred normalize (Blizzard may resize after AddPrivateAuraAnchor)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if f and f._gfPrivContainer and f._gfPrivContainer:IsShown() then
                NormalizeAllSlots(f, f._gfPrivSize or iconSz)
            end
        end)
    end

    -- The old separate Private Aura Dispel Overlay is no longer exposed for
    -- custom Private Auras. Blizzard-like dispel indicators are owned by the
    -- native Blizzard aura renderer.
    GF.ApplyPrivateAuraContainerOverlay(f, unit, { containerOverlay = { enabled = false } })
end

------------------------------------------------------------------------
-- Legacy container overlay cleanup
------------------------------------------------------------------------
local function _UpdatePrivateAuraContainerOverlayVisibility(f)
    ClearContainerOverlay(f)
end

function GF.ApplyPrivateAuraContainerOverlay(f, unit, pa)
    ClearContainerOverlay(f)
end

-- Legacy live-update path kept for callers from older configs. It now only
-- clears the removed container overlay.
function GF.UpdatePrivateAuraContainerOverlay(f)
    if not f or not f.unit then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf then return end
    GF.ApplyPrivateAuraContainerOverlay(f, f.unit, conf.privateAuras)
end

GF.UpdatePrivateAuraContainerOverlayVisibility = _UpdatePrivateAuraContainerOverlayVisibility

------------------------------------------------------------------------
-- Clear (exported for unit-change / hide)
------------------------------------------------------------------------
GF.ClearPrivateAuras = ClearAnchors

------------------------------------------------------------------------
-- Preview: mock private aura slots (no real unit, placeholder icons)
------------------------------------------------------------------------
function GF.PreviewPrivateAuras(f, kind)
    if not f then return end
    local conf = GF.GetConf(kind)
    local pa = conf and conf.privateAuras
    if not pa or pa.enabled == false or HasNativeBlizzardPrivateAuras(conf) then
        if f._gfPrivPreviewSlots then
            for i = 1, #f._gfPrivPreviewSlots do f._gfPrivPreviewSlots[i]:Hide() end
        end
        if f._gfPrivPreviewCont then f._gfPrivPreviewCont:Hide() end
        return
    end

    local maxN     = math_max(1, math_floor((tonumber(pa.max) or 4) + 0.5))
    if maxN > 12 then maxN = 12 end
    local frameScale = (conf and conf._resolvedFrameScale) or (GF.GetFrameScale and GF.GetFrameScale(kind)) or 1
    local iconSz   = ScaleFrameValue(pa.size or 20, frameScale, 8)
    local pt       = pa.anchor or "TOPRIGHT"
    local dir      = pa.direction or "LEFT"
    local ox       = ScaleFrameValue(pa.x or 0, frameScale)
    local oy       = ScaleFrameValue(pa.y or 0, frameScale)
    local spacing  = ScaleFrameValue(pa.spacing or 1, frameScale, 0)
    local previewN = maxN

    local parent = f.statusIconLayer or f.barGroup or f
    local container = f._gfPrivPreviewCont
    if not container then
        container = CreateFrame("Frame", nil, parent)
        container:EnableMouse(false)
        if container.SetClipsChildren then container:SetClipsChildren(false) end
        f._gfPrivPreviewCont = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end
    if container.SetClipsChildren then container:SetClipsChildren(false) end

    local isVert = (dir == "TOP" or dir == "BOTTOM")
    local totalP = previewN * iconSz + (previewN - 1) * spacing
    container:ClearAllPoints()
    if isVert then container:SetSize(iconSz, totalP)
    else container:SetSize(totalP, iconSz) end
    container:SetPoint(pt, parent, pt, ox, oy)
    if GF.SetFrameLayerLevel then
        GF.SetFrameLayerLevel(container, f, pa.layer, 8)
    else
        container:SetFrameLevel(parent:GetFrameLevel() + (pa.layer or 8))
    end
    container:Show()

    local step = iconSz + spacing
    local slotAnchor, slotDX, slotDY
    if dir == "LEFT" then      slotAnchor = "RIGHT";  slotDX = -step; slotDY = 0
    elseif dir == "RIGHT" then slotAnchor = "LEFT";   slotDX = step;  slotDY = 0
    elseif dir == "TOP" then   slotAnchor = "BOTTOM"; slotDX = 0;     slotDY = step
    else                       slotAnchor = "TOP";    slotDX = 0;     slotDY = -step end

    f._gfPrivPreviewSlots = f._gfPrivPreviewSlots or {}
    local slots = f._gfPrivPreviewSlots
    for i = 1, previewN do
        local slot = slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, container, "BackdropTemplate")
            slot:EnableMouse(false)
            slot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            slot:SetBackdropColor(0.08, 0.08, 0.10, 0.85)
            slot:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.7)
            local lock = slot:CreateTexture(nil, "ARTWORK")
            lock:SetPoint("CENTER")
            lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
            lock:SetAlpha(0.4)
            lock:SetDesaturated(true)
            slot._lock = lock
            slots[i] = slot
        end
        slot:SetSize(iconSz, iconSz)
        slot._lock:SetSize(iconSz * 0.5, iconSz * 0.5)
        slot:ClearAllPoints()
        slot:SetPoint(slotAnchor, container, slotAnchor, (i - 1) * slotDX, (i - 1) * slotDY)
        slot:Show()
    end
    for i = previewN + 1, #slots do
        if slots[i] then slots[i]:Hide() end
    end
end

function GF.HidePreviewPrivateAuras(f)
    if not f then return end
    if f._gfPrivPreviewSlots then
        for i = 1, #f._gfPrivPreviewSlots do f._gfPrivPreviewSlots[i]:Hide() end
    end
    if f._gfPrivPreviewCont then f._gfPrivPreviewCont:Hide() end
end
