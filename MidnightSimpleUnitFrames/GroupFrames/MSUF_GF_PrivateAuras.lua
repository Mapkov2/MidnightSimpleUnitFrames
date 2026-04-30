-- MSUF_GF_PrivateAuras.lua — Private aura anchoring for Group Frames
-- 12.0.5+ baseline. No fallback paths.
--
-- 12.0.5 lifted combat-lockdown restrictions on AddPrivateAuraAnchor /
-- RemovePrivateAuraAnchor / SetPrivateWarningTextAnchor / RemovePrivateAura-
-- AppliedSound. We don't use AddPrivateAuraAppliedSound (still restricted
-- during encounters/M+/PvP), so this file has zero combat-aware code.
--
-- The Blizzard-rendered "Private Aura Dispel Overlay" uses a second anchor
-- with `isContainer = true` + container attributes (max-buffs / max-debuffs /
-- max-dispel-debuffs / dispel-indicator-option / aura-organization-type).
-- Blizzard paints it; addons have no colour/art control. Independent of the
-- icon anchor stack — does not replace it.
local _, ns = ...
ns.GF = ns.GF or {}
local GF = ns.GF

local C_Timer     = _G.C_Timer
local CreateFrame = _G.CreateFrame
local math_floor  = math.floor
local math_max    = math.max
local math_min    = math.min
local type        = type

-- Direct localizations: 12.0.5+ guarantees these APIs exist.
local AddPrivateAuraAnchor    = _G.C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = _G.C_UnitAuras.RemovePrivateAuraAnchor

local function AddPrivateAuraAnchorSafe(args)
    if type(AddPrivateAuraAnchor) ~= "function" then return nil, "AddPrivateAuraAnchor unavailable" end
    local ok, anchorID = pcall(AddPrivateAuraAnchor, args)
    if ok then return anchorID end
    return nil, anchorID
end

------------------------------------------------------------------------
-- Clear anchors for a frame (icon anchors + optional container overlay)
------------------------------------------------------------------------
local function ClearAnchors(f)
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

    -- Container overlay anchor
    local coID = f._gfPrivContainerOverlayID
    if coID then RemovePrivateAuraAnchor(coID) end
    f._gfPrivContainerOverlayID  = nil
    f._gfPrivContainerOverlayUnit = nil

    local slots = f._gfPrivSlots
    if type(slots) == "table" then
        for i = 1, #slots do if slots[i] then slots[i]:Hide() end end
    end
    if f._gfPrivContainer then f._gfPrivContainer:Hide() end
    if f._gfPrivOverlayFrame then f._gfPrivOverlayFrame:Hide() end
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
    for i = 1, #slots do
        local s = slots[i]
        if s and s:IsShown() then NormalizeSlot(s, sz) end
    end
end

------------------------------------------------------------------------
-- Apply private auras for a GF frame
------------------------------------------------------------------------
-- Reusable across GF and boss frames.
--
-- Signature: GF.ApplyPrivateAuras(f, unit [, paOverride])
--   paOverride: optional privateAuras config table. If supplied, all
--   settings are read from it and the GF config lookup is skipped
--   entirely. Used by the boss-frame bridge so boss frames can opt into
--   the same private-aura icons + 12.0.5 container overlay without being
--   registered as GF children (which would interfere with GF layout,
--   range fade, aggro tracking, etc.).
function GF.ApplyPrivateAuras(f, unit, paOverride)
    if not f then return end

    local pa, conf
    if type(paOverride) == "table" then
        pa   = paOverride
        conf = paOverride   -- satisfies the `conf.privateAura*` fallback reads below
    else
        local kind = f._msufGFKind or "party"
        conf = GF.GetConf(kind)
        pa   = conf.privateAuras
    end

    -- Read from nested privateAuras table (migrated) or flat keys (legacy)
    local paEnabled, paMax, paSize, paAnchor, paX, paY, paCountdown, paDirection, paNumbers, paLayer
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

    local iconSz = math_max(8, math_floor((tonumber(paSize) or 20) + 0.5))
    local pt = paAnchor
    local ox = tonumber(paX) or 0
    local oy = tonumber(paY) or 0
    local countdown = paCountdown

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
                container:SetFrameLevel(parent:GetFrameLevel() + paLayer)
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
    local spacing = 1
    local isVertical = (paDirection == "TOP" or paDirection == "BOTTOM")
    local totalPrimary = maxN * iconSz + (maxN - 1) * spacing

    container:ClearAllPoints()
    if isVertical then
        container:SetSize(iconSz, totalPrimary)
    else
        container:SetSize(totalPrimary, iconSz)
    end
    container:SetPoint(pt, parent, pt, ox, oy)
    container:SetFrameLevel(parent:GetFrameLevel() + paLayer)
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
            showCountdownNumbers = false,
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

    for i = 1, maxN do
        local slot = slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, container)
            slot:SetFrameStrata("MEDIUM")
            slot:SetFrameLevel(62)
            if slot.SetClipsChildren then slot:SetClipsChildren(false) end
            if not slot._gfPrivSizeHook then
                slot._gfPrivSizeHook = true
                slot:HookScript("OnSizeChanged", function(self)
                    NormalizeSlot(self, self._gfPrivSz or iconSz)
                end)
            end
            slots[i] = slot
        end
        slot:ClearAllPoints()
        slot:SetPoint(slotAnchor, container, slotAnchor, (i - 1) * slotDX, (i - 1) * slotDY)
        NormalizeSlot(slot, iconSz)
        slot:Show()

        args.unitToken = unit
        args.auraIndex = i
        args.parent = slot
        args.showCountdownFrame = countdown
        args.showCountdownNumbers = paNumbers
        args.isContainer = false
        args.iconInfo.iconWidth = iconSz
        args.iconInfo.iconHeight = iconSz
        args.iconInfo.borderScale = borderScale
        args.iconInfo.iconAnchor.relativeTo = slot

        local anchorID = AddPrivateAuraAnchorSafe(args)
        if anchorID then
            f._gfPrivAnchorIDs[#f._gfPrivAnchorIDs + 1] = anchorID
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

    -- 12.0.5+ native Private Aura Dispel Overlay (separate container anchor).
    GF.ApplyPrivateAuraContainerOverlay(f, unit, pa)
end

------------------------------------------------------------------------
-- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered)
--
-- A SECOND anchor with isContainer=true. Blizzard paints the overlay
-- inside the wrapper frame using attributes set BEFORE AddPrivateAuraAnchor
-- (OnAnchorAdded reads ReadContainerSettings immediately).
--
-- Customisation is deliberately limited by Blizzard:
--   dispel-indicator-option         : "dispellableByMe" | "allDispellable"
--   aura-organization-type          : sweep direction ("default", etc.)
--   suppress-dispel-border-icons    : hide the small Magic/Curse/Poison/Disease icon
--   group-type                      : 4 for party slots, 5 for raid — required for
--                                     Blizzard's internal hooks even on a GF frame.
--
-- This is additive: the icon anchors set up above (which show the actual
-- private aura textures + countdown) remain unchanged. The container
-- overlay only replaces the old DF-drawn frame-border overlay.
------------------------------------------------------------------------
local function _GetContainerOverlayConf(pa)
    -- Nested table (new) or flat-key legacy — both supported.
    if type(pa) == "table" and pa.containerOverlay then
        local co = pa.containerOverlay
        return {
            enabled     = co.enabled and true or false,
            showIcons   = co.showIcons ~= false,                 -- default true
            dispelMode  = co.dispelMode or "dispellableByMe",
            gradientDir = co.gradientDir or "default",
        }
    end
    return {
        enabled     = false,
        showIcons   = true,
        dispelMode  = "dispellableByMe",
        gradientDir = "default",
    }
end

local function _GroupTypeForUnit(unit)
    local G = _G.CompactRaidGroupTypeEnum
    if type(unit) == "string" and unit:find("^party") then
        return G and G.Party or 4
    end
    return G and G.Raid or 5
end

local function _ResolveAuraOrganizationType(gradientDir)
    local E = _G.Enum and _G.Enum.RaidAuraOrganizationType
    local legacy = E and E.Legacy or 0
    local buffsTop = E and E.BuffsTopDebuffsBottom or 1
    local buffsRight = E and E.BuffsRightDebuffsLeft or 2

    if gradientDir == "BOTTOM" then return buffsTop end
    if gradientDir == "LEFT" or gradientDir == "RIGHT" then return buffsRight end
    return legacy
end

local function _ResolveDispelIndicatorOption(dispelMode)
    local E = _G.Enum and _G.Enum.RaidDispelDisplayType
    local byMe = E and E.DispellableByMe or 2
    local all = E and E.DisplayAll or 1
    if dispelMode == "allDispellable" then return all end
    return byMe
end

function GF.ApplyPrivateAuraContainerOverlay(f, unit, pa)
    if not f or not unit then return end

    local co = _GetContainerOverlayConf(pa)
    local auraOrgType = _ResolveAuraOrganizationType(co.gradientDir)
    local dispelOption = _ResolveDispelIndicatorOption(co.dispelMode)

    -- Disabled or teardown: clear existing anchor and bail.
    if not co.enabled then
        if f._gfPrivContainerOverlayID then
            RemovePrivateAuraAnchor(f._gfPrivContainerOverlayID)
        end
        f._gfPrivContainerOverlayID   = nil
        f._gfPrivContainerOverlayUnit = nil
        if f._gfPrivOverlayFrame then f._gfPrivOverlayFrame:Hide() end
        return
    end

    -- Diff: same unit + same attrs → just re-show + update-settings attribute.
    local cached = f._gfPrivCOCached
    local wrapper = f._gfPrivOverlayFrame
    local samePayload = wrapper
        and f._gfPrivContainerOverlayID
        and f._gfPrivContainerOverlayUnit == unit
        and cached
        and cached.showIcons   == co.showIcons
        and cached.dispelMode  == co.dispelMode
        and cached.gradientDir == co.gradientDir
        and cached.auraOrgType == auraOrgType
        and cached.dispelOption == dispelOption

    -- Lazy-init wrapper. Parent to the unitframe itself (not a sub-region)
    -- so Blizzard can size/centre the overlay across the whole frame.
    if not wrapper then
        wrapper = CreateFrame("Frame", nil, f)
        wrapper:EnableMouse(false)
        if wrapper.SetMouseClickEnabled then wrapper:SetMouseClickEnabled(false) end
        f._gfPrivOverlayFrame = wrapper
    end
    wrapper:SetParent(f)
    wrapper:ClearAllPoints()
    wrapper:SetAllPoints(f)
    wrapper:Show()

    -- Update attributes BEFORE AddPrivateAuraAnchor — OnAnchorAdded reads them
    -- via ReadContainerSettings immediately on registration.
    wrapper:SetAttribute("max-buffs", 0)
    wrapper:SetAttribute("max-debuffs", 0)
    wrapper:SetAttribute("max-dispel-debuffs", 1)
    wrapper:SetAttribute("ignore-buffs", true)
    wrapper:SetAttribute("ignore-debuffs", true)
    wrapper:SetAttribute("show-dispel-indicator-overlay", true)
    wrapper:SetAttribute("suppress-dispel-border-icons", not co.showIcons)
    wrapper:SetAttribute("dispel-indicator-option", dispelOption)
    wrapper:SetAttribute("aura-organization-type", auraOrgType)
    wrapper:SetAttribute("group-type", _GroupTypeForUnit(unit))
    wrapper:SetAttribute("display-only-dispellable-debuffs", false)
    wrapper:SetAttribute("ignore-dispel-debuffs", false)
    wrapper:SetAttribute("power-bar-used-height", 0)
    wrapper:SetAttribute("icon-size", 10)
    wrapper:SetAttribute("set-aura-size-to-icon-size", false)

    if samePayload then
        -- Live-update path: signal Blizzard to re-read attributes.
        wrapper:SetAttribute("update-settings", true)
        return
    end

    -- Full (re)registration: remove old ID if any, add new anchor.
    if f._gfPrivContainerOverlayID then
        RemovePrivateAuraAnchor(f._gfPrivContainerOverlayID)
        f._gfPrivContainerOverlayID = nil
    end

    local newID, err = AddPrivateAuraAnchorSafe({
        unitToken            = unit,
        parent               = wrapper,
        isContainer          = true,
        auraIndex            = 1,
        showCountdownFrame   = false,
        showCountdownNumbers = false,
    })
    if newID then
        f._gfPrivContainerOverlayID   = newID
        f._gfPrivContainerOverlayUnit = unit
        f._gfPrivCOCached = {
            showIcons   = co.showIcons,
            dispelMode  = co.dispelMode,
            gradientDir = co.gradientDir,
            auraOrgType = auraOrgType,
            dispelOption = dispelOption,
        }
    else
        f._gfPrivContainerOverlayID   = nil
        f._gfPrivContainerOverlayUnit = nil
        f._gfPrivCOCached = nil
        if wrapper then wrapper:Hide() end
        f._gfPrivCOLastError = err
    end
end

-- Cheap live-update path used by Options live-apply. Diff-gate inside
-- ApplyPrivateAuraContainerOverlay short-circuits when nothing changed.
function GF.UpdatePrivateAuraContainerOverlay(f)
    if not f or not f.unit then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf then return end
    GF.ApplyPrivateAuraContainerOverlay(f, f.unit, conf.privateAuras)
end

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
    if not pa or pa.enabled == false then
        if f._gfPrivPreviewSlots then
            for i = 1, #f._gfPrivPreviewSlots do f._gfPrivPreviewSlots[i]:Hide() end
        end
        if f._gfPrivPreviewCont then f._gfPrivPreviewCont:Hide() end
        return
    end

    local maxN     = math_max(1, math_floor((tonumber(pa.max) or 4) + 0.5))
    if maxN > 12 then maxN = 12 end
    local iconSz   = math_max(8, math_floor((tonumber(pa.size) or 20) + 0.5))
    local pt       = pa.anchor or "TOPRIGHT"
    local dir      = pa.direction or "LEFT"
    local ox       = tonumber(pa.x) or 0
    local oy       = tonumber(pa.y) or 0
    local spacing  = tonumber(pa.spacing) or 1
    local previewN = math_min(maxN, 2)

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
    container:SetFrameLevel(parent:GetFrameLevel() + (pa.layer or 8))
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
