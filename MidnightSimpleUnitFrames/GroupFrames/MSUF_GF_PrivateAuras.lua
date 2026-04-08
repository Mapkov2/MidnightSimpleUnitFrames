-- MSUF_GF_PrivateAuras.lua — Private aura anchoring for Group Frames
-- Midnight 12.0 secret-safe. Combat-safe: defers Add/Remove calls.
-- Uses same C_UnitAuras.AddPrivateAuraAnchor API as A2_Render.
local _, ns = ...
ns.GF = ns.GF or {}
local GF = ns.GF

local C_UnitAuras = _G.C_UnitAuras
local C_Timer     = _G.C_Timer
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local math_floor  = math.floor
local math_max    = math.max
local math_min    = math.min
local type        = type
local select      = select

------------------------------------------------------------------------
-- API availability
------------------------------------------------------------------------
local function Supported()
    return C_UnitAuras
        and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function"
end

------------------------------------------------------------------------
-- Combat-deferred removal queue
------------------------------------------------------------------------
local _pendingRemoveIDs

local function FlushPendingRemoves()
    local ids = _pendingRemoveIDs
    if not ids then return end
    _pendingRemoveIDs = nil
    local removeFn = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
    if not removeFn then return end
    for i = 1, #ids do
        if ids[i] then removeFn(ids[i]) end
    end
end

------------------------------------------------------------------------
-- Clear anchors for a frame
------------------------------------------------------------------------
local function ClearAnchors(f)
    local ids = f._gfPrivAnchorIDs
    if type(ids) == "table" and C_UnitAuras then
        local removeFn = C_UnitAuras.RemovePrivateAuraAnchor
        if removeFn then
            if InCombatLockdown and InCombatLockdown() then
                if not _pendingRemoveIDs then _pendingRemoveIDs = {} end
                for i = 1, #ids do
                    if ids[i] then _pendingRemoveIDs[#_pendingRemoveIDs + 1] = ids[i] end
                end
            else
                for i = 1, #ids do
                    if ids[i] then removeFn(ids[i]) end
                end
            end
        end
    end
    f._gfPrivAnchorIDs = nil
    f._gfPrivUnit = nil
    f._gfPrivSize = nil
    f._gfPrivMax = nil
    f._gfPrivAnchor = nil
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
    for i = 1, #slots do
        local s = slots[i]
        if s and s:IsShown() then NormalizeSlot(s, sz) end
    end
end

------------------------------------------------------------------------
-- Apply private auras for a GF frame
------------------------------------------------------------------------
function GF.ApplyPrivateAuras(f, unit)
    if not f then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    -- Read from nested privateAuras table (migrated) or flat keys (legacy)
    local pa = conf.privateAuras
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

    -- Feature disabled or API unavailable → clear
    if paEnabled == false or not Supported() then
        ClearAnchors(f)
        return
    end

    -- No unit → clear
    if not unit then ClearAnchors(f); return end

    -- Combat lock: cannot call AddPrivateAuraAnchor in combat
    if InCombatLockdown and InCombatLockdown() then return end

    local maxN = math_max(0, math_floor((tonumber(paMax) or 4) + 0.5))
    if maxN == 0 then ClearAnchors(f); return end
    if maxN > 12 then maxN = 12 end

    local iconSz = math_max(8, math_floor((tonumber(paSize) or 20) + 0.5))
    local pt = paAnchor
    local ox = tonumber(paX) or 0
    local oy = tonumber(paY) or 0
    local countdown = paCountdown

    -- Diff check: skip rebuild if nothing changed
    if f._gfPrivUnit == unit
       and f._gfPrivSize == iconSz
       and f._gfPrivMax == maxN
       and f._gfPrivAnchor == pt
       and f._gfPrivDir == paDirection
       and type(f._gfPrivAnchorIDs) == "table"
    then
        if f._gfPrivContainer then f._gfPrivContainer:Show() end
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
        f._gfPrivContainer = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end

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
        args.iconInfo.iconWidth = iconSz
        args.iconInfo.iconHeight = iconSz
        args.iconInfo.borderScale = borderScale
        args.iconInfo.iconAnchor.relativeTo = slot

        local ok, anchorID = true, C_UnitAuras.AddPrivateAuraAnchor(args)
        if ok and anchorID then
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
end

------------------------------------------------------------------------
-- Clear (exported for unit-change / hide)
------------------------------------------------------------------------
GF.ClearPrivateAuras = ClearAnchors

------------------------------------------------------------------------
-- Combat end flush (registered once)
------------------------------------------------------------------------
local _flushFrame
local function EnsureFlushHook()
    if _flushFrame then return end
    _flushFrame = CreateFrame("Frame")
    _flushFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _flushFrame:SetScript("OnEvent", function()
        FlushPendingRemoves()
        -- Re-apply private auras on all visible frames (were blocked in combat)
        if GF.frames then
            for f in pairs(GF.frames) do
                if f.unit and f:IsShown() then
                    GF.ApplyPrivateAuras(f, f.unit)
                end
            end
        end
    end)
end
EnsureFlushHook()

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
        f._gfPrivPreviewCont = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end

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
