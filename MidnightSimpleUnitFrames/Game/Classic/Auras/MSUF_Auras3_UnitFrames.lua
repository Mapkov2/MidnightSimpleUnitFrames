--- Classic aura backend selected before the Retail 12.1 AuraContainer backend.
--- Classic Era, TBC Classic and MoP Classic expose the C_UnitAuras/AuraUtil scan contract
--- used here, while Classic does not ship the Retail native aura-container runtime.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
--- Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua
--- Delta-first UnitFrame aura backend.
---
--- Runtime ownership:
--- * Menu_Model writes SavedVariables and invalidates runtime config.
--- * EditMode builds fake preview groups and drag handles only.
--- * This file owns live aura state, full scans, UNIT_AURA deltas, button pools,
---   and frame-level aura visuals for unit and group frames.
---
--- Keep gameplay aura work here and keep menu/edit code out of UNIT_AURA paths.
--- Aura scans are one of the most expensive frame events in MSUF, so new logic
--- should either compile into lane config or run behind the existing delta/full
--- scan split.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

ExportPublic("MSUF_Auras3", A3)

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

if A3.__unitFrameBackendLoaded then return end
A3.__unitFrameBackendLoaded = true

local type, tostring, tonumber, pairs, next, select = type, tostring, tonumber, pairs, next, select
local math_floor, math_ceil, math_min, math_max = math.floor, math.ceil, math.min, math.max
local table_sort = table.sort
local wipe = table.wipe or wipe
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local UnitExists = _G.UnitExists
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local AuraUtil = _G.AuraUtil
local InCombatLockdown = _G.InCombatLockdown
local UnitIsUnit = _G.UnitIsUnit
local UnitInRange = _G.UnitInRange
local UnitIsPlayer = _G.UnitIsPlayer
local UnitPlayerOrPetInParty = _G.UnitPlayerOrPetInParty
local UnitPlayerOrPetInRaid = _G.UnitPlayerOrPetInRaid
local IsSecret = _G.issecretvalue or function() return false end

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID

-- Saved profiles can arrive from Retail, an older Classic build, or another
-- Classic family client. Keep the explicit three-state setting authoritative
-- while preserving the former boolean contract (which represented the old
-- border+symbol presentation).
A3.NormalizeClassicDebuffTypeBorderMode = A3.NormalizeClassicDebuffTypeBorderMode or function(value, legacyBorder, legacySymbol)
    local mode = type(value) == "string" and value:upper() or nil
    if mode == "SYMBOL" or mode == "BORDER" then return mode end
    if mode == "OFF" then
        if legacySymbol == true then return "SYMBOL" end
        if legacyBorder == true then return "SYMBOL" end
        return "OFF"
    end
    if legacySymbol == true or legacyBorder == true then return "SYMBOL" end
    return "OFF"
end
A3.NormalizeClassicStealableStyle = A3.NormalizeClassicStealableStyle or function(value)
    value = type(value) == "string" and value:upper() or "BORDER_ICON"
    if value == "BORDER" or value == "BORDER_ICON" or value == "ICON" then return value end
    return "BORDER_ICON"
end
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
local GetAuraDispelTypeColor = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor

local Compile = A3._ClassicCompile
assert(type(Compile) == "table", "Classic aura backend requires Game/Classic/Auras/MSUF_Auras3_Compile.lua")
local MANAGED_UNITS = Compile.MANAGED_UNITS
local DEFAULT_SHARED = Compile.DEFAULT_SHARED
local WipeTable = Compile.WipeTable
local FillAuraSlots = Compile.FillAuraSlots
local PlainNumber = Compile.PlainNumber
local PlainString = Compile.PlainString
local DirectVisualFilterForTrigger = Compile.DirectVisualFilterForTrigger
local ColorObjectRGBA = Compile.ColorObjectRGBA
local HasSecretColor = Compile.HasSecretColor
local NormalizeRuntimeUnit = Compile.NormalizeRuntimeUnit
local IsUnitToken = Compile.IsUnitToken
local IsGroupFrame = Compile.IsGroupFrame
local SortAuras = Compile.SortAuras
local SortComparator = Compile.SortComparator
local CompileFrameAuraVisual = Compile.CompileFrameAuraVisual
local ResolveGroupFrameConfig = Compile.ResolveGroupFrameConfig
local FrameAuraConfig = Compile.FrameAuraConfig

local EMPTY_EVENTS = {}
-- Read-only stand-in for a missing lanes table, so lane walks never allocate.
local EMPTY_LANES = {}
-- Features.lua loads before this file; ShouldShowAura falls back to the live
-- field only if a harness loads the backend without it.
local Features = A3.ClassicFeatures
local COMBAT_AURA_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local W8 = "Interface\\Buttons\\WHITE8X8"
local DEBUFF_OVERLAY_TEXTURE = "Interface\\Buttons\\UI-Debuff-Overlays"

-- Intentional cross-client data kept in step with the Retail list: an ID that
-- this Classic client never applies simply never matches, so no per-flavor split.
local SATED_SPELLS = {
    [57723] = true, -- Exhaustion
    [57724] = true, -- Sated
    [80354] = true, -- Temporal Displacement
    [95809] = true, -- Insanity
    [160455] = true, -- Fatigued
    [264689] = true, -- Fatigued
}

--- Era/Mists/TBC do not consistently expose tooltip setters by aura instance
--- ID. Resolve the current filtered index only on mouseover; this never adds
--- work to UNIT_AURA or the render path.
A3._ClassicAuraIndexByInstanceID = function(unit, auraInstanceID, filter)
    if not (GetAuraDataByIndex and auraInstanceID) then return nil end
    local index = 1
    local data = GetAuraDataByIndex(unit, index, filter)
    while data do
        if data.auraInstanceID == auraInstanceID then return index end
        index = index + 1
        data = GetAuraDataByIndex(unit, index, filter)
    end
    return nil
end

local function OnAuraEnter(button)
    if not (button and button:IsVisible() and GameTooltip and not GameTooltip:IsForbidden()) then return end
    local lane = button._msufA3Lane
    if not (lane and lane.config and lane.config.showTooltip and button.auraInstanceID) then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    if button._msufA3WeaponEnchantSlot then
        if GameTooltip.SetInventoryItem then GameTooltip:SetInventoryItem("player", button._msufA3WeaponEnchantSlot) end
        return
    end
    local filter = lane.config.filter
    if GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(lane.unit, button.auraInstanceID)
    elseif lane.config.harmful ~= true and GameTooltip.SetUnitBuffByAuraInstanceID then
        GameTooltip:SetUnitBuffByAuraInstanceID(lane.unit, button.auraInstanceID, filter)
    elseif lane.config.harmful == true and GameTooltip.SetUnitDebuffByAuraInstanceID then
        GameTooltip:SetUnitDebuffByAuraInstanceID(lane.unit, button.auraInstanceID, filter)
    else
        local index = A3._ClassicAuraIndexByInstanceID(lane.unit, button.auraInstanceID, filter)
        if index and lane.config.harmful ~= true and GameTooltip.SetUnitBuff then
            GameTooltip:SetUnitBuff(lane.unit, index, filter)
        elseif index and lane.config.harmful == true and GameTooltip.SetUnitDebuff then
            GameTooltip:SetUnitDebuff(lane.unit, index, filter)
        elseif index and GameTooltip.SetUnitAura then
            GameTooltip:SetUnitAura(lane.unit, index, filter)
        end
    end
end

local function OnAuraLeave()
    if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local function ApplyFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    if fs.SetFont then fs:SetFont(fontPath, size or 14, fontFlags) end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, button, cfg)
    if not (fs and button and cfg) then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PositionButton(lane, button, index)
    local cfg = lane.config
    local perRow = cfg.perRow > 0 and cfg.perRow or 1
    local idx = index - 1
    local col, row
    if cfg.verticalGrowth == true then
        row = idx % perRow
        col = (idx - row) / perRow
    else
        col = idx % perRow
        row = (idx - col) / perRow
    end
    local padding = cfg.padding or 0
    local x = (padding + col * (cfg.stepX or cfg.step)) * cfg.xSign
    local y = (padding + row * (cfg.stepY or cfg.step)) * cfg.ySign
    button:ClearAllPoints()
    button:SetPoint(cfg.initialAnchor, lane.frame, cfg.initialAnchor, x, y)
end

local CooldownTextRegion
local ResetCooldownTextColor

local function CooldownTextLayoutCustom(cfg)
    if not cfg then return false end
    if (cfg.cooldownSize or DEFAULT_SHARED.cooldownTextSize) ~= DEFAULT_SHARED.cooldownTextSize then return true end
    if (cfg.cooldownX or 0) ~= 0 or (cfg.cooldownY or 0) ~= 0 then return true end
    return cfg.cooldownAnchor ~= nil and cfg.cooldownAnchor ~= "CENTER"
end

local function ApplyCooldownTextLayout(cooldown, button, cfg)
    if not (cooldown and button and cfg) then return end
    local custom = CooldownTextLayoutCustom(cfg)
    local fs = cooldown._msufA3TextRegion
    if not custom and not fs then return end
    fs = fs or (CooldownTextRegion and CooldownTextRegion(cooldown))
    if not fs then return end

    if fs.GetFont and not fs._msufA3BaseFont then
        fs._msufA3BaseFont, fs._msufA3BaseSize, fs._msufA3BaseFlags = fs:GetFont()
    end

    if fs.SetFont then
        local font = fs._msufA3BaseFont
        local size = custom and (cfg.cooldownSize or DEFAULT_SHARED.cooldownTextSize) or fs._msufA3BaseSize
        local flags = fs._msufA3BaseFlags
        if font and size and fs._msufA3AppliedSize ~= size then
            fs:SetFont(font, size, flags or "")
            fs._msufA3AppliedSize = size
        end
    end

    if fs.ClearAllPoints and fs.SetPoint then
        local anchor = custom and (cfg.cooldownAnchor or "CENTER") or "CENTER"
        local x = custom and (cfg.cooldownX or 0) or 0
        local y = custom and (cfg.cooldownY or 0) or 0
        if fs._msufA3Anchor ~= anchor or fs._msufA3X ~= x or fs._msufA3Y ~= y then
            fs:ClearAllPoints()
            fs:SetPoint(anchor, button, anchor, x, y)
            fs._msufA3Anchor, fs._msufA3X, fs._msufA3Y = anchor, x, y
        end
    end
end

local function ApplyButtonLayout(lane, button, index)
    local cfg = lane.config
    if not cfg then return end
    button._msufA3Lane = lane
    button:SetSize(cfg.buttonWidth or cfg.size, cfg.buttonHeight or cfg.size)
    -- Click-through and tooltip hover are independent on every supported
    -- Classic branch. EnableMouse(false) disabled both and made the tooltip
    -- setting silently non-functional for the common click-through profile.
    if button.SetMouseClickEnabled and button.SetMouseMotionEnabled then
        button:SetMouseClickEnabled(cfg.clickThrough ~= true)
        button:SetMouseMotionEnabled(cfg.showTooltip == true)
    else
        button:EnableMouse(cfg.clickThrough ~= true or cfg.showTooltip == true)
    end
    if button.Cooldown then
        if button.Cooldown.SetDrawSwipe then button.Cooldown:SetDrawSwipe(cfg.showCooldown == true and cfg.showCooldownSwipe ~= false) end
        if button.Cooldown.SetHideCountdownNumbers then button.Cooldown:SetHideCountdownNumbers(cfg.showCooldownText == false) end
        if button.Cooldown.SetCountdownMillisecondsThreshold then
            button.Cooldown:SetCountdownMillisecondsThreshold(cfg.cooldownDecimalSeconds or 0)
        end
        ApplyCooldownTextLayout(button.Cooldown, button, cfg)
        if cfg.cooldownTextBuckets ~= true and ResetCooldownTextColor then
            ResetCooldownTextColor(button.Cooldown)
        end
        if button.Cooldown.SetSwipeColor then
            if cfg.cooldownSwipeDarken == true then
                button.Cooldown:SetSwipeColor(0, 0, 0, 0.78)
            else
                button.Cooldown:SetSwipeColor(0, 0, 0, 0.55)
            end
        end
        if cfg.showCooldown ~= true then
            button.Cooldown:Hide()
            button._msufA3CooldownShown = nil
        end
    end
    if button.Count then
        if cfg.showStacks == false then
            button.Count:Hide()
        else
            button.Count:Show()
            ApplyFont(button.Count, cfg.stackSize)
            PlaceStackText(button.Count, button, cfg)
            if button.Count.SetTextColor then
                button.Count:SetTextColor(cfg.stackR or 1, cfg.stackG or 1, cfg.stackB or 1, 1)
            end
        end
    end
    if cfg.showDispelTypeBorder ~= true and button._msufA3DispelOverlay then
        button._msufA3DispelOverlay._msufA3Shown = nil
        button._msufA3DispelOverlay:Hide()
    end
    if cfg.showDispelTypeSymbol ~= true and button._msufA3DispelTypeSymbol then
        button._msufA3DispelTypeSymbol:Hide()
    end
    if cfg.ownHighlight ~= true and button._msufA3OwnHighlight then
        button._msufA3OwnHighlight._msufA3Shown = nil
        button._msufA3OwnHighlight:Hide()
    end
    PositionButton(lane, button, index)
    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.ApplyButtonLayout) == "function" then
        visuals.ApplyButtonLayout(lane, button)
    end
end

local function CreateAuraButton(lane, index)
    local button = CreateFrame("Button", nil, lane.frame)
    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.Icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    button.Cooldown = cooldown

    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints(button)
    if cooldown.GetFrameLevel and textLayer.SetFrameLevel then
        textLayer:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    end
    local count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.Count = count

    button:SetScript("OnEnter", OnAuraEnter)
    button:SetScript("OnLeave", OnAuraLeave)
    ApplyButtonLayout(lane, button, index)
    button:Hide()

    lane[index] = button
    lane.createdButtons = index
    if type(lane.PostCreateButton) == "function" then
        lane:PostCreateButton(button)
    end
    local CT = A3.CooldownText
    if CT and type(CT.RegisterButton) == "function" then
        CT.RegisterButton(button, "unit")
    end
    return button
end

local function EnsureButton(lane, index)
    return lane[index] or CreateAuraButton(lane, index)
end

--- Button pools and lane state are runtime-owned. Config may change the desired
--- max/layout, but live buttons stay attached to their lane so delta updates can
--- reuse them without creating frames during combat.
-- Pre-create the visible button pool for single unit frames while out of
-- combat, so the first swap onto an aura-heavy target never pays a burst of
-- CreateFrame calls mid-fight. Group frames keep the lazy path: their pools
-- are per-member, so eager prewarm would multiply login/reload cost across the
-- raid. If group creation spikes regress, fix them with a budgeted render queue
-- instead of creating every member's buttons up front.
local function PrewarmLaneButtons(lane, frame)
    local cfg = lane.config
    if not cfg then return end
    if frame and frame._msufA3GroupRuntime == true then return end
    local want = cfg.max or 0
    if want <= (lane.createdButtons or 0) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    for i = (lane.createdButtons or 0) + 1, want do
        EnsureButton(lane, i)
    end
end

local function ApplyLaneLayout(lane)
    local cfg = lane.config
    if not (lane.frame and cfg) then return end
    lane.frame:ClearAllPoints()
    lane.frame:SetPoint(cfg.anchor, lane.root, cfg.anchor, cfg.x, cfg.y)
    lane.frame:SetSize(cfg.width, cfg.height)
    if lane.frame.SetAlpha then lane.frame:SetAlpha(cfg.alpha or 1) end
    if lane.frame.SetFrameStrata and cfg.strata and cfg.strata ~= "AUTO" then
        lane.frame:SetFrameStrata(cfg.strata)
    end
    if lane.root.GetFrameLevel and lane.frame.SetFrameLevel then
        lane.frame:SetFrameLevel((lane.root:GetFrameLevel() or 0) + cfg.layer)
    end
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then ApplyButtonLayout(lane, button, i) end
    end
end

local HideButton
local HideTrailingButtons
local ClearFrameAuraVisualState
local BuildButtonUpdater
local UpdateButton

local function ResetLaneVisualCache(lane)
    if not lane then return end
    local cfg = lane.config
    local visual = cfg and cfg.visual
    lane._msufA3VisualCacheReady = cfg
        and cfg.enabled == true
        and cfg.visualDirect ~= true
        and visual
        and visual.enabled == true or nil
    lane._msufA3VisualAnyDebuff = nil
    lane._msufA3VisualBorderActive = nil
    lane._msufA3VisualBorderR = nil
    lane._msufA3VisualBorderG = nil
    lane._msufA3VisualBorderB = nil
    lane._msufA3VisualBorderA = nil
    lane._msufA3VisualBorderSecret = nil
    lane._msufA3VisualBorderToken = nil
    lane._msufA3VisualOverlayActive = nil
    lane._msufA3VisualOverlayR = nil
    lane._msufA3VisualOverlayG = nil
    lane._msufA3VisualOverlayB = nil
    lane._msufA3VisualOverlayA = nil
    lane._msufA3VisualOverlaySecret = nil
    lane._msufA3VisualOverlayToken = nil
end

local function ClearLane(lane)
    lane.all = WipeTable(lane.all)
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
    local frame = CreateFrame("Frame", nil, parent)
    lane = {
        kind = kind,
        root = parent,
        frame = frame,
        all = {},
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
        root = CreateFrame("Frame", nil, frame)
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
            local comparator = SortComparator(lane.config.sortOrder)
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
    local order = cfg.laneOrder or A3._ClassicBaseLaneOrder
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

--- Token-filter membership. C_UnitAuras.IsAuraFilteredOutByInstanceID has no
--- engine-validated consumer on any Classic branch and reported every aura as
--- filtered on Mists, which turned each token filter into an empty lane.
--- Blizzard's own Classic UI evaluates filter tokens through aura scans
--- (Blizzard_RaidUI walks "HELPFUL|RAID|PLAYER"), so membership is derived
--- from the same scan primitive: one filtered instance-ID scan per
--- unit+filter, cached until the unit's serial is bumped.
--- UpdateAuras bumps the serial only when membership can change: a full update
--- (forced, no payload, isFullUpdate, a pending needFullUpdate, or a newly
--- applied config) or a payload with added or removed auras. An update-only
--- payload refreshes existing auras and keeps each aura's source, so it keeps
--- the cached sets; a set built at an older serial is rebuilt lazily on its
--- next query.
--- (Lane config compilation lives in Game/Classic/Auras/MSUF_Auras3_Compile.lua.)
--- Sets are stored as sets[unit][filter] rather than under a concatenated
--- "unit|filter" key: both levels are bounded by the finite unit tokens and
--- lane filter strings, so a cached membership query allocates nothing.
A3._ClassicAuraTokenSets = A3._ClassicAuraTokenSets or {}
A3._ClassicAuraTokenSerial = A3._ClassicAuraTokenSerial or {}
A3._ClassicAuraTokenSet = function(unit, filter)
    local serial = A3._ClassicAuraTokenSerial[unit] or 0
    local setsByFilter = A3._ClassicAuraTokenSets[unit]
    if not setsByFilter then
        setsByFilter = {}
        A3._ClassicAuraTokenSets[unit] = setsByFilter
    end
    local entry = setsByFilter[filter]
    if entry and entry.serial == serial then return entry.set end
    if not entry then
        entry = { set = {} }
        setsByFilter[filter] = entry
    end
    local set = WipeTable(entry.set)
    entry.set = set
    entry.serial = serial
    local getInstanceIDs = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if type(getInstanceIDs) == "function" then
        local ids = getInstanceIDs(unit, filter)
        if type(ids) == "table" and not IsSecret(ids) then
            for i = 1, #ids do
                local id = ids[i]
                if id ~= nil and not IsSecret(id) then set[id] = true end
            end
        end
        return set
    end
    if GetAuraSlots and GetAuraDataBySlot then
        local slots, count = FillAuraSlots(entry.scratch or {}, GetAuraSlots(unit, filter))
        entry.scratch = slots
        for i = 2, count do
            local data = GetAuraDataBySlot(unit, slots[i])
            local id = data and data.auraInstanceID
            if id ~= nil and not IsSecret(id) then set[id] = true end
        end
    end
    return set
end

local function Filtered(unit, auraInstanceID, filter)
    if unit == nil or auraInstanceID == nil or filter == nil then return false end
    return A3._ClassicAuraTokenSet(unit, filter)[auraInstanceID] ~= true
end

local function ProcessData(lane, unit, data, fromLaneScan)
    if type(data) ~= "table" then return nil end
    local auraInstanceID = data.auraInstanceID
    if auraInstanceID == nil then return nil end
    local cfg = lane.config
    if cfg.nativePlayerFilter == true
        and lane._msufA3NativePlayerFilterTrusted ~= false then
        -- Full-scan data already passed Blizzard's PLAYER filter. Delta
        -- payloads do not carry that guarantee, so test their exact native
        -- membership before they can enter or remain in an Only Mine lane.
        data.isPlayerAura = fromLaneScan == true
            or not Filtered(unit, auraInstanceID, cfg.filter)
        return data
    end
    if cfg.needsPlayerFlag == true then
        -- Mists/TBC do not reliably populate isFromPlayerOrPlayerPet (the
        -- player's own party-frame HoTs carried false/nil, which blanked
        -- "only mine" lanes). Blizzard compares sourceUnit through UnitIsUnit,
        -- because the player or pet can arrive through an equivalent group /
        -- vehicle token. A positive legacy flag is still useful, but false is
        -- not authoritative. Fall back to PLAYER scan membership only while
        -- that native filter is trustworthy: on an explicitly out-of-range
        -- group unit some Classic clients return every aura for |PLAYER.
        local sourceUnit = data.sourceUnit
        local fromPlayer = data.isFromPlayerOrPlayerPet
        if sourceUnit ~= nil and not IsSecret(sourceUnit) then
            -- The literal tokens are the common case and need no API call.
            local sourceIsPlayer = sourceUnit == "player"
                or sourceUnit == "pet" or sourceUnit == "vehicle"
            if not sourceIsPlayer and UnitIsUnit then
                sourceIsPlayer = UnitIsUnit("player", sourceUnit)
                    or UnitIsUnit("pet", sourceUnit)
                    or UnitIsUnit("vehicle", sourceUnit)
            end
            data.isPlayerAura = sourceIsPlayer == true
                or (lane._msufA3NativePlayerFilterTrusted ~= false
                    and fromPlayer ~= nil and not IsSecret(fromPlayer) and fromPlayer == true)
        elseif lane._msufA3NativePlayerFilterTrusted ~= false
            and fromPlayer ~= nil and not IsSecret(fromPlayer) and fromPlayer == true then
            data.isPlayerAura = true
        else
            data.isPlayerAura = lane._msufA3NativePlayerFilterTrusted ~= false
                and not Filtered(unit, auraInstanceID, cfg.playerFilter)
        end
    end
    return data
end

local function Blacklisted(cfg, data)
    local blacklist = cfg.blacklist
    if not blacklist then return false end
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    if type(spellID) == "number" then
        return blacklist[spellID] == true
    end
    spellID = tonumber(spellID)
    return spellID and blacklist[math_floor(spellID + 0.5)] == true or false
end

local function MatchFilter(unit, auraInstanceID, filter)
    return not Filtered(unit, auraInstanceID, filter)
end

local function AuraDispelColorByCurve(curve, unit, data)
    if not (curve and unit and data and data.auraInstanceID and GetAuraDispelTypeColor) then
        return false
    end
    if data._msufA3DispelKnown == true then
        if data._msufA3DispelHasColor == true then
            if data._msufA3DispelSecretColor == true then
                local color = data._msufA3DispelColorObject
                local r, g, b, a = ColorObjectRGBA(color)
                if r then
                    return true, r, g, b, a or 1, true
                end
                return false
            end
            return true, data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA, false
        end
        return false
    end
    local color = GetAuraDispelTypeColor(unit, data.auraInstanceID, curve)
    local r, g, b, a = ColorObjectRGBA(color)
    data._msufA3DispelKnown = true
    if r then
        data._msufA3DispelHasColor = true
        if HasSecretColor(r, g, b, a) then
            data._msufA3DispelSecretColor = true
            data._msufA3DispelColorObject = color
            data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA = nil, nil, nil, nil
            return true, r, g, b, a or 1, true
        end
        data._msufA3DispelSecretColor = nil
        data._msufA3DispelColorObject = nil
        data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA = r, g, b, a or 1
        return true, r, g, b, a or 1, false
    end
    data._msufA3DispelHasColor = false
    data._msufA3DispelSecretColor = nil
    data._msufA3DispelColorObject = nil
    data._msufA3DispelR, data._msufA3DispelG, data._msufA3DispelB, data._msufA3DispelA = nil, nil, nil, nil
    return false
end

local function AuraDispelColor(cfg, unit, data)
    local hasColor, r, g, b, a, secret = AuraDispelColorByCurve(cfg and cfg.dispelColorCurve, unit, data)
    if hasColor then return hasColor, r, g, b, a, secret end
    local name = PlainString(data and data.dispelName)
    local color = name and _G.DebuffTypeColor and _G.DebuffTypeColor[name]
    if color then
        r, g, b, a = ColorObjectRGBA(color)
        if r then return true, r, g, b, a or 1, HasSecretColor(r, g, b, a) end
    end
    return false
end

local function AuraDispelNoneColor(cfg)
    if cfg and cfg.dispelNoneReady == true then
        if cfg.dispelNoneSecret == true then
            return true, cfg.dispelNoneR, cfg.dispelNoneG, cfg.dispelNoneB, cfg.dispelNoneA, true
        end
        return true, cfg.dispelNoneR, cfg.dispelNoneG, cfg.dispelNoneB, cfg.dispelNoneA or 1, false
    end
    local curve = cfg and cfg.dispelColorCurve
    if not (curve and curve.Evaluate) then return false end
    local color = curve:Evaluate(0)
    local r, g, b, a = ColorObjectRGBA(color)
    if r then return true, r, g, b, a or 1, HasSecretColor(r, g, b, a) end
    return false
end

local function MatchDispelTrigger(lane, unit, data, trigger)
    if not (lane and data) then return false end
    if trigger == "ANY_DEBUFF" then
        return true
    elseif trigger == "PLAYER_CAST" then
        return data.isPlayerAura == true
    elseif trigger == "DISPEL_TYPE" then
        local dispelName = PlainString(data.dispelName)
        return dispelName ~= nil and dispelName ~= ""
    end
    return MatchFilter(unit, data.auraInstanceID, lane.config.dispellableFilter)
end

local function DispelVisualColor(lane, visual, unit, data)
    if visual and visual.colorMode == "TYPE" then
        local hasColor, r, g, b, a, secret = AuraDispelColor(lane.config, unit, data)
        if hasColor then return r, g, b, a, secret == true end
    end
    return visual and visual.r or 0.25, visual and visual.g or 0.75, visual and visual.b or 1, visual and visual.a or 1, false
end

local function DirectDispelVisualColor(visual, unit, data)
    if visual and visual.colorMode == "TYPE" then
        local hasColor, r, g, b, a, secret = AuraDispelColorByCurve(visual.dispelColorCurve, unit, data)
        if hasColor then return r, g, b, a, secret == true end
    end
    return visual and visual.r or 0.25, visual and visual.g or 0.75, visual and visual.b or 1, visual and visual.a or 1, false
end

local function ResolveDirectDispelTriggerVisual(unit, visual, trigger)
    local filter = DirectVisualFilterForTrigger(trigger)
    if not (filter and GetAuraDataByIndex and IsUnitToken(unit)) then
        return false
    end
    local data = GetAuraDataByIndex(unit, 1, filter)
    if not (data and data.auraInstanceID) then
        return false
    end
    if trigger == "DISPEL_TYPE" then
        local dispelName = PlainString(data.dispelName)
        if dispelName == nil or dispelName == "" then return false end
    end
    local token = data.auraInstanceID
    if IsSecret(token) then token = nil end
    local r, g, b, a, secret = DirectDispelVisualColor(visual, unit, data)
    return true, r, g, b, a, secret == true, token
end

local function ConsiderLaneAuraVisual(lane, unit, data)
    if not (lane and lane._msufA3VisualCacheReady == true and data) then return end
    local visual = lane.config and lane.config.visual
    if not (visual and visual.enabled == true) then return end
    if lane._msufA3VisualAnyDebuff == true
        and (visual.borderEnabled ~= true or lane._msufA3VisualBorderActive == true)
        and (visual.overlayEnabled ~= true or lane._msufA3VisualOverlayActive == true) then
        return
    end
    lane._msufA3VisualAnyDebuff = true

    local borderMatched = false
    if visual.borderEnabled == true and lane._msufA3VisualBorderActive ~= true then
        borderMatched = MatchDispelTrigger(lane, unit, data, visual.borderTrigger)
        if borderMatched then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            lane._msufA3VisualBorderActive = true
            lane._msufA3VisualBorderR, lane._msufA3VisualBorderG = r, g
            lane._msufA3VisualBorderB, lane._msufA3VisualBorderA = b, a
            lane._msufA3VisualBorderSecret = secret == true
            lane._msufA3VisualBorderToken = token
        end
    end

    if visual.overlayEnabled == true and lane._msufA3VisualOverlayActive ~= true then
        -- Sharing the border's result is valid only when the border was
        -- evaluated. The overlay inherits the border's trigger, not its
        -- enabled state (Retail compiles it as a sensor of its own).
        if visual.borderEnabled == true and visual.overlayTrigger == visual.borderTrigger then
            if lane._msufA3VisualBorderActive == true then
                lane._msufA3VisualOverlayActive = true
                lane._msufA3VisualOverlayR = lane._msufA3VisualBorderR
                lane._msufA3VisualOverlayG = lane._msufA3VisualBorderG
                lane._msufA3VisualOverlayB = lane._msufA3VisualBorderB
                lane._msufA3VisualOverlayA = lane._msufA3VisualBorderA
                lane._msufA3VisualOverlaySecret = lane._msufA3VisualBorderSecret
                lane._msufA3VisualOverlayToken = lane._msufA3VisualBorderToken
            end
        elseif MatchDispelTrigger(lane, unit, data, visual.overlayTrigger) then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            lane._msufA3VisualOverlayActive = true
            lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG = r, g
            lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA = b, a
            lane._msufA3VisualOverlaySecret = secret == true
            lane._msufA3VisualOverlayToken = token
        end
    end
end

local function TimedAura(unit, data)
    local duration = PlainNumber(data and data.duration)
    local expirationTime = PlainNumber(data and data.expirationTime)
    if duration ~= nil and expirationTime ~= nil then
        return duration > 0 and expirationTime > 0
    end

    -- Group-unit AuraData may protect the raw duration fields even though the
    -- permanent/timed distinction is still available through the sanctioned
    -- LuaDurationObject API. IsZero is scale-independent, so it is also safe
    -- on the Classic clients where binding this object as a cooldown produced
    -- millisecond/second drift. Keep an unreadable result indeterminate rather
    -- than misclassifying every protected timed aura as permanent.
    local auraInstanceID = data and data.auraInstanceID
    local getAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if unit ~= nil and auraInstanceID ~= nil and not IsSecret(auraInstanceID)
        and type(getAuraDuration) == "function" then
        local durationObject = getAuraDuration(unit, auraInstanceID)
        local isZero = durationObject and durationObject.IsZero
        if type(isZero) == "function" then
            local zero = isZero(durationObject)
            if not IsSecret(zero) then return zero ~= true end
        end
    end
    return nil
end

A3._ClassicAuraFromAnyPlayerOrPet = function(data)
    if type(data) ~= "table" then return nil end
    local raw = data.isFromPlayerOrPlayerPet
    if raw ~= nil and not IsSecret(raw) and raw == true then return true end

    -- Supported Classic clients expose the AuraData flag, but some Mists/TBC
    -- group payloads report false/nil for player-owned effects. Use the public
    -- source token to reject those false negatives before accepting a public
    -- false flag as an environment/NPC aura.
    local sourceUnit = data.sourceUnit
    if sourceUnit ~= nil and not IsSecret(sourceUnit) then
        local isPlayer = type(UnitIsPlayer) == "function" and UnitIsPlayer(sourceUnit) or nil
        if isPlayer ~= nil and not IsSecret(isPlayer) and isPlayer == true then return true end
        local inParty = type(UnitPlayerOrPetInParty) == "function"
            and UnitPlayerOrPetInParty(sourceUnit) or nil
        if inParty ~= nil and not IsSecret(inParty) and inParty == true then return true end
        local inRaid = type(UnitPlayerOrPetInRaid) == "function"
            and UnitPlayerOrPetInRaid(sourceUnit) or nil
        if inRaid ~= nil and not IsSecret(inRaid) and inRaid == true then return true end
    end

    if raw ~= nil and not IsSecret(raw) then return raw == true end
    return nil
end

local function RemainingTime(data)
    local expirationTime = PlainNumber(data and data.expirationTime)
    if not (expirationTime and expirationTime > 0 and GetTime) then return nil end
    local remaining = expirationTime - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function SatedAura(data)
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    if type(spellID) == "number" then
        return SATED_SPELLS[spellID] == true
    end
    spellID = tonumber(spellID)
    return spellID and SATED_SPELLS[math_floor(spellID + 0.5)] == true or false
end

local function ShouldShowAura(lane, unit, data)
    local cfg = lane.config
    local features = Features or A3.ClassicFeatures
    if features and type(features.IsAutoExcluded) == "function"
        and features.IsAutoExcluded(cfg, data) then
        return false
    end
    if Blacklisted(cfg, data) then return false end
    if cfg.classicFeatureMatch == true and features
        and type(features.MatchAura) == "function" then
        return features.MatchAura(cfg, unit, data, MatchFilter)
    end
    if type(cfg.includeSpellIDs) == "table" then
        local spellID = data and data.spellId
        local matched = spellID ~= nil and not IsSecret(spellID)
            and cfg.includeSpellIDs[tonumber(spellID)] == true
        if not matched and type(cfg.includeSpellNames) == "table" then
            -- Rank/alias drift: fall back to the aura name so a whitelisted
            -- spell still matches when the live aura reports another spellId.
            local name = data and data.name
            matched = name ~= nil and not IsSecret(name)
                and cfg.includeSpellNames[name] == true
        end
        if not matched then return false end
    end
    if cfg.nonPlayerFilter == true and A3._ClassicAuraFromAnyPlayerOrPet(data) ~= false then return false end
    if cfg.hidePermanent == true and TimedAura(unit, data) == false then return false end
    if cfg.maxDuration and cfg.maxDuration > 0 then
        local duration = PlainNumber(data and data.duration) or 0
        if duration > cfg.maxDuration then return false end
    end
    if cfg.satedFilter == true and SatedAura(data) then
        if cfg.showSated ~= true then return false end
        local threshold = cfg.satedThreshold or 0
        local remaining = threshold > 0 and RemainingTime(data) or nil
        if remaining and remaining > threshold then return false end
    end
    if cfg.filterRequirements and features
        and type(features.MatchFilterRequirements) == "function" then
        return features.MatchFilterRequirements(
            cfg.filterPlan or cfg.filterRequirements, unit, data, MatchFilter)
    end
    if not cfg.hasFilterWork then return true end
    local auraInstanceID = data.auraInstanceID
    if cfg.exclusiveImportant then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.onlyImportant and not cfg.hasInclusive then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.hasInclusive then
        if cfg.onlyMine and data.isPlayerAura then return true end
        if cfg.raid and MatchFilter(unit, auraInstanceID, cfg.raidFilter) then return true end
        if cfg.raidInCombat and MatchFilter(unit, auraInstanceID, cfg.raidInCombatFilter) then return true end
        if cfg.includeStealable and MatchFilter(unit, auraInstanceID, cfg.stealableFilter) then return true end
        if cfg.boss and MatchFilter(unit, auraInstanceID, cfg.bossFilter) then return true end
        if cfg.onlyImportant and MatchFilter(unit, auraInstanceID, cfg.importantFilter) then return true end
        return false
    end
    return true
end

local function DataMatchesLane(data, cfg)
    if type(data) == "table" then
        local harmful = data.isHarmful
        if harmful ~= nil and not IsSecret(harmful) then
            return (harmful == true) == (cfg.harmful == true)
        end
        local helpful = data.isHelpful
        if helpful ~= nil and not IsSecret(helpful) then
            return (helpful == true) ~= (cfg.harmful == true)
        end
    end
    local auraInstanceID = data and data.auraInstanceID
    return auraInstanceID ~= nil and not Filtered(cfg.unit, auraInstanceID, cfg.filter)
end

local function AddAuraToLane(lane, unit, data, fromLaneScan)
    data = ProcessData(lane, unit, data, fromLaneScan)
    if not data then return false, nil end
    local auraInstanceID = data.auraInstanceID
    local isNew = lane.all[auraInstanceID] == nil
    lane.all[auraInstanceID] = data
    if isNew then
        local n = (lane.orderedCount or 0) + 1
        lane.ordered[n] = auraInstanceID
        lane.orderedCount = n
    end
    if lane.config.hasFilterWork ~= true then
        lane.active[auraInstanceID] = true
        if lane._msufA3VisualCacheReady == true then
            ConsiderLaneAuraVisual(lane, unit, data)
        end
        return true, data
    end
    if ShouldShowAura(lane, unit, data) then
        lane.active[auraInstanceID] = true
        if lane._msufA3VisualCacheReady == true then
            ConsiderLaneAuraVisual(lane, unit, data)
        end
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

function A3._AppendClassicWeaponEnchants(lane, unit, inlineRender, visible, maxVisible, visibleByID, updateButton)
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
    visible = A3._AppendClassicWeaponEnchants(lane, unit, inlineRender, visible, maxVisible, visibleByID, updateButton)

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

local function ShowButton(button)
    if button._msufA3Shown ~= true then
        button._msufA3Shown = true
        button:Show()
    end
end

HideButton = function(button)
    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.HideButtonVisual) == "function" then visuals.HideButtonVisual(button) end
    -- ClearLane intentionally invalidates auraInstanceID before reaching this
    -- helper. Always hide here so a stale/missing visibility marker cannot
    -- leave a pooled Classic aura button visible after its container is off.
    button._msufA3Shown = nil
    button:Hide()
end

local function ShowCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= true then
        button._msufA3CooldownShown = true
        cooldown:Show()
    end
end

local function HideCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= nil then
        button._msufA3CooldownShown = nil
        if cooldown.Clear then cooldown:Clear() end
        cooldown:Hide()
    end
end

local function EnsureOwnHighlight(button)
    local tex = button._msufA3OwnHighlight
    if tex then return tex end
    tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(W8)
    tex:SetAllPoints(button)
    tex:SetBlendMode("ADD")
    tex:Hide()
    button._msufA3OwnHighlight = tex
    return tex
end

local function EnsureDispelTypeOverlay(button)
    local tex = button._msufA3DispelOverlay
    if tex then return tex end
    tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(DEBUFF_OVERLAY_TEXTURE)
    tex:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    tex:SetAllPoints(button)
    tex:Hide()
    button._msufA3DispelOverlay = tex
    return tex
end

A3._EnsureClassicAuraDispelTypeSymbol = function(button)
    local tex = button and button._msufA3DispelTypeSymbol
    if tex then return tex end
    if not button then return nil end
    tex = button:CreateTexture(nil, "OVERLAY", nil, 6)
    tex:Hide()
    button._msufA3DispelTypeSymbol = tex
    return tex
end

A3._UpdateClassicAuraDispelTypeSymbol = function(button, cfg, data)
    local tex = button and button._msufA3DispelTypeSymbol
    local dispelName = cfg and cfg.showDispelTypeSymbol == true and PlainString(data and data.dispelName) or nil
    local visuals = A3.ClassicVisuals
    if not (dispelName and visuals and type(visuals.SetDispelSymbolArt) == "function") then
        if tex then tex:Hide() end
        return false
    end
    tex = tex or A3._EnsureClassicAuraDispelTypeSymbol(button)
    if not (tex and visuals.SetDispelSymbolArt(tex, "BLIZZARD", dispelName)) then
        if tex then tex:Hide() end
        return false
    end
    local size = math_max(8, math_floor(((cfg.size or 24) * 0.44) + 0.5))
    tex:ClearAllPoints()
    tex:SetSize(size, size)
    tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    tex:Show()
    return true
end

local function UpdateDispelTypeOverlay(button, lane, unit, data)
    local cfg = lane and lane.config
    if not (cfg and cfg.showDispelTypeBorder == true) then
        local tex = button and button._msufA3DispelOverlay
        if tex and tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
        A3._UpdateClassicAuraDispelTypeSymbol(button, cfg, nil)
        return
    end
    local hasColor, r, g, b, a, secret = AuraDispelColor(cfg, unit, data)
    if not hasColor then
        hasColor, r, g, b, a, secret = AuraDispelNoneColor(cfg)
    end
    local tex = button._msufA3DispelOverlay
    if hasColor then
        tex = tex or EnsureDispelTypeOverlay(button)
        -- Geometry only, and only when the lane's shape or size changed. Nothing
        -- here may colour or show the texture: both are cached below, and the
        -- preview helper's sample colour, written behind that cache, survived
        -- every later repaint of the same dispel type.
        local shape, size = cfg.iconShape or "RECTANGLE", cfg.size
        if tex._msufA3BorderShape ~= shape or tex._msufA3BorderSize ~= size then
            local shaped = type(A3.ApplyAuraDispelShape) == "function"
                and A3.ApplyAuraDispelShape(tex, button.Icon or button, size, shape) == true
            if not shaped then
                tex:SetTexture(DEBUFF_OVERLAY_TEXTURE)
                if tex.SetTexCoord then tex:SetTexCoord(0.296875, 0.5703125, 0, 0.515625) end
                tex:ClearAllPoints()
                tex:SetAllPoints(button)
            end
            tex._msufA3BorderShape, tex._msufA3BorderSize = shape, size
        end
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
        if secret == true or tex._msufA3ColorPlain ~= true
            or tex._msufA3R ~= r or tex._msufA3G ~= g
            or tex._msufA3B ~= b or tex._msufA3A ~= a then
            tex:SetVertexColor(r, g, b, a)
            if secret == true then
                tex._msufA3ColorPlain = nil
            else
                tex._msufA3ColorPlain = true
                tex._msufA3R, tex._msufA3G, tex._msufA3B, tex._msufA3A = r, g, b, a
            end
        end
        if tex._msufA3Shown ~= true then
            tex._msufA3Shown = true
            tex:Show()
        end
    elseif tex then
        if tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
    end
    A3._UpdateClassicAuraDispelTypeSymbol(button, cfg, data)
end

local function UpdateOwnHighlight(button, cfg, data)
    local active = cfg and cfg.ownHighlight == true and data and data.isPlayerAura == true
    local tex = button._msufA3OwnHighlight
    if active then
        tex = EnsureOwnHighlight(button)
        local r, g, b, a = cfg.ownR or 1, cfg.ownG or 1, cfg.ownB or 1, 0.24
        if tex._msufA3ColorPlain ~= true
            or tex._msufA3R ~= r or tex._msufA3G ~= g
            or tex._msufA3B ~= b or tex._msufA3A ~= a then
            tex:SetVertexColor(r, g, b, a)
            tex._msufA3ColorPlain = true
            tex._msufA3R, tex._msufA3G, tex._msufA3B, tex._msufA3A = r, g, b, a
        end
        if tex._msufA3Shown ~= true then
            tex._msufA3Shown = true
            tex:Show()
        end
    elseif tex then
        if tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
    end
end

local function CooldownTextRGB(cfg, data)
    if not (cfg and cfg.cooldownTextBuckets == true) then
        return cfg and cfg.cooldownSafeR or 1, cfg and cfg.cooldownSafeG or 1, cfg and cfg.cooldownSafeB or 1
    end
    local remaining = RemainingTime(data)
    if not remaining then
        return cfg.cooldownSafeR or 1, cfg.cooldownSafeG or 1, cfg.cooldownSafeB or 1
    end
    if remaining <= (cfg.cooldownUrgentSeconds or 5) then
        return cfg.cooldownUrgentR or 1, cfg.cooldownUrgentG or 0.55, cfg.cooldownUrgentB or 0.10
    end
    if remaining <= (cfg.cooldownWarningSeconds or 15) then
        return cfg.cooldownWarnR or 1, cfg.cooldownWarnG or 0.85, cfg.cooldownWarnB or 0.20
    end
    return cfg.cooldownSafeR or 1, cfg.cooldownSafeG or 1, cfg.cooldownSafeB or 1
end

CooldownTextRegion = function(cooldown)
    if not cooldown then return nil end
    local cached = cooldown._msufA3TextRegion
    if cached and cached.SetTextColor then return cached end
    if not cooldown.GetRegions then return nil end
    for i = 1, cooldown:GetNumRegions() do
        local region = select(i, cooldown:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString"
            and region.SetTextColor then
            cooldown._msufA3TextRegion = region
            return region
        end
    end
    return nil
end

local function MarkCooldownTextColor(cooldown, region, r, g, b)
    if region.GetTextColor and not region._msufA3BaseTextR then
        region._msufA3BaseTextR, region._msufA3BaseTextG, region._msufA3BaseTextB, region._msufA3BaseTextA = region:GetTextColor()
    end
    region:SetTextColor(r, g, b, 1)
    region._msufA3ColorApplied = true
    if cooldown then cooldown._msufA3ColorApplied = true end
end

ResetCooldownTextColor = function(cooldown)
    if not (cooldown and cooldown._msufA3ColorApplied == true) then return end
    local region = cooldown._msufA3TextRegion
    if region and region.SetTextColor and region._msufA3ColorApplied == true then
        region:SetTextColor(region._msufA3BaseTextR or 1, region._msufA3BaseTextG or 1, region._msufA3BaseTextB or 1, region._msufA3BaseTextA or 1)
        region._msufA3ColorApplied = nil
    elseif cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(1, 1, 1, 1)
    elseif cooldown.SetTextColor then
        cooldown:SetTextColor(1, 1, 1, 1)
    end
    cooldown._msufA3ColorApplied = nil
    cooldown._msufA3TextColorPlain = nil
    cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = nil, nil, nil
end

local function ApplyCooldownTextColor(cooldown, cfg, data)
    if not (cooldown and cfg and cfg.showCooldownText ~= false and cfg.cooldownTextBuckets == true) then return end
    local r, g, b = CooldownTextRGB(cfg, data)
    if cooldown._msufA3TextColorPlain == true
        and cooldown._msufA3TextR == r
        and cooldown._msufA3TextG == g
        and cooldown._msufA3TextB == b then
        return
    end
    if cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
        return
    end
    if cooldown.SetTextColor then
        cooldown:SetTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
        return
    end
    local region = CooldownTextRegion(cooldown)
    if region then
        MarkCooldownTextColor(cooldown, region, r, g, b)
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
    end
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
                if AddAuraToLane(lane, unit, data) then needsRender = true end
            end
        end
    end

    local updated = updateInfo and updateInfo.updatedAuraInstanceIDs
    if updated and GetAuraDataByAuraInstanceID then
        for i = 1, #updated do
            local auraInstanceID = updated[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local oldData = lane.all[auraInstanceID]
                local oldPlayer = oldData and oldData.isPlayerAura
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
                    if visualEnabled and wasActive then
                        lane._msufA3VisualCacheReady = nil
                        visualDirty = true
                    end
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        if visualEnabled and not wasActive then
                            ConsiderLaneAuraVisual(lane, unit, data)
                        end
                        if wasActive then
                            if oldPlayer ~= data.isPlayerAura
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
                    lane.orderDirty = true
                    if wasActive then
                        if visualEnabled then
                            lane._msufA3VisualCacheReady = nil
                            visualDirty = true
                        end
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
                lane.orderDirty = true
                if lane.active[auraInstanceID] then
                    if visualEnabled then
                        lane._msufA3VisualCacheReady = nil
                        visualDirty = true
                    end
                    lane.active[auraInstanceID] = nil
                    needsRender = true
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
                    lane.active[auraInstanceID] = nil
                    lane.orderDirty = true
                    if wasActive then return true, true end
                end
            end
        end
    end

    return changed, false
end

local function SetIcon(button, icon)
    local tex = button.Icon
    if not tex then return end
    if IsSecret(icon) then
        tex:SetTexture(icon)
        button._msufA3IconPlain = nil
        button._msufA3Icon = nil
        return
    end
    if button._msufA3IconPlain == true and button._msufA3Icon == icon then
        return
    end
    tex:SetTexture(icon)
    button._msufA3Icon = icon
    button._msufA3IconPlain = true
end

local function SetCount(button, text)
    local count = button.Count
    if not count then return end
    if IsSecret(text) then
        count:SetText(text)
        button._msufA3Count = nil
        button._msufA3CountPlain = nil
        return
    end
    text = text or ""
    if button._msufA3CountPlain == true and button._msufA3Count == text then
        return
    end
    count:SetText(text)
    button._msufA3Count = text
    button._msufA3CountPlain = true
end

local UpdateButtonStacks
if GetAuraApplicationDisplayCount then
    UpdateButtonStacks = function(button, unit, data)
        local applications = data.applications
        if not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
            return
        end
        SetCount(button, GetAuraApplicationDisplayCount(unit, data.auraInstanceID, 2, 999))
    end
else
    UpdateButtonStacks = function(button, unit, data)
        local applications = data.applications
        if not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
        else
            SetCount(button, "")
        end
    end
end

-- Classic never uses GetAuraDuration/SetCooldownFromDurationObject: no
-- Blizzard UI on any Classic branch exercises that API pair, and on
-- Mists/TBC it painted hour-scale cooldowns (millisecond-scale values read
-- as seconds -- the "1h Renewing Mist" report). Classic aura duration and
-- expiration are plain numbers, so the raw SetCooldown pair that Blizzard's
-- own Classic target frame uses is the only correct path.
-- TimedAura (Hide permanent) may still read LuaDurationObject:IsZero; that is a
-- scale-independent boolean and never feeds a cooldown widget.
local function UpdateCooldown(button, cooldown, unit, data)
    local duration = data.duration
    local expirationTime = data.expirationTime
    if not IsSecret(duration) and not IsSecret(expirationTime)
        and type(duration) == "number" and type(expirationTime) == "number"
        and duration > 0 and expirationTime > 0 then
        local start = expirationTime - duration
        if button._msufA3CooldownPlain ~= true
            or button._msufA3CooldownStart ~= start
            or button._msufA3CooldownDuration ~= duration then
            cooldown:SetCooldown(start, duration)
            button._msufA3CooldownStart = start
            button._msufA3CooldownDuration = duration
            button._msufA3CooldownPlain = true
        end
        ShowCooldown(button, cooldown)
        return
    end

    if button._msufA3CooldownPlain ~= nil then
        button._msufA3CooldownStart = nil
        button._msufA3CooldownDuration = nil
        button._msufA3CooldownPlain = nil
    end
    HideCooldown(button, cooldown)
end

UpdateButton = function(lane, button, unit, data)
    local cfg = lane.config
    button.auraInstanceID = data.auraInstanceID
    button._msufA3WeaponEnchantSlot = data._msufA3WeaponEnchantSlot
    SetIcon(button, data.icon)
    local cooldown = button.Cooldown
    if cooldown and cfg.showCooldown == true then
        UpdateCooldown(button, cooldown, unit, data)
        if cfg.cooldownTextBuckets == true then
            ApplyCooldownTextColor(cooldown, cfg, data)
        end
    elseif cooldown then
        HideCooldown(button, cooldown)
    end
    if cfg.showStacks ~= false then
        UpdateButtonStacks(button, unit, data)
    end
    if cfg.ownHighlight == true or button._msufA3OwnHighlight then
        UpdateOwnHighlight(button, cfg, data)
    end
    if cfg.showDispelTypeBorder == true or button._msufA3DispelOverlay then
        UpdateDispelTypeOverlay(button, lane, unit, data)
    end
    ShowButton(button)
end

local function UpdateButtonHeader(lane, button, data)
    button.auraInstanceID = data.auraInstanceID
    button._msufA3WeaponEnchantSlot = data._msufA3WeaponEnchantSlot
    SetIcon(button, data.icon)
end

local function UpdateButtonCooldownOnly(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateCooldown(button, button.Cooldown, unit, data)
    ShowButton(button)
end

local function UpdateButtonCooldownStacks(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateCooldown(button, button.Cooldown, unit, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonCooldownBuckets(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    local cooldown = button.Cooldown
    UpdateCooldown(button, cooldown, unit, data)
    ApplyCooldownTextColor(cooldown, lane.config, data)
    ShowButton(button)
end

local function UpdateButtonCooldownBucketsStacks(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    local cooldown = button.Cooldown
    UpdateCooldown(button, cooldown, unit, data)
    ApplyCooldownTextColor(cooldown, lane.config, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonStacksOnly(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonBasic(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    ShowButton(button)
end

BuildButtonUpdater = function(cfg)
    if not cfg then return UpdateButton end

    local core
    if cfg.showCooldown == true then
        if cfg.cooldownTextBuckets == true and cfg.showCooldownText ~= false then
            core = cfg.showStacks ~= false and UpdateButtonCooldownBucketsStacks or UpdateButtonCooldownBuckets
        else
            core = cfg.showStacks ~= false and UpdateButtonCooldownStacks or UpdateButtonCooldownOnly
        end
    else
        core = cfg.showStacks ~= false and UpdateButtonStacksOnly or UpdateButtonBasic
    end

    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.UpdateButtonVisual) == "function" then
        local rawCore = core
        core = function(lane, button, unit, data)
            rawCore(lane, button, unit, data)
            visuals.UpdateButtonVisual(lane, button, unit, data)
        end
    end

    local own = cfg.ownHighlight == true
    local dispel = cfg.showDispelTypeBorder == true
    if own and dispel then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateOwnHighlight(button, lane.config, data)
            UpdateDispelTypeOverlay(button, lane, unit, data)
        end
    elseif own then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateOwnHighlight(button, lane.config, data)
        end
    elseif dispel then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateDispelTypeOverlay(button, lane, unit, data)
        end
    end
    return core
end

HideTrailingButtons = function(lane, visibleByID, visible)
    local oldVisible = lane.visible or 0
    if visible >= oldVisible then
        lane.visible = visible
        return
    end
    for i = visible + 1, oldVisible do
        local button = lane[i]
        if button then
            if button.auraInstanceID ~= nil then
                visibleByID[button.auraInstanceID] = nil
            end
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
    lane.visible = visible
end

--- Drops only the ids that left lane.all. An aura that is tracked but filtered
--- out keeps its slot: AddAuraToLane appends an id once, when it enters
--- lane.all, so an update that makes it visible again could never put it back.
local function CompactLaneOrder(lane)
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
        table_sort(sorted, cfg.sortComparator or SortAuras)
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

local function ResolveDispelTriggerVisual(lane, unit, visual, trigger)
    if not (lane and visual and trigger) then return false end
    local active = lane.active
    local all = lane.all
    if not (active and all) then return false end
    for auraInstanceID in next, active do
        local data = all[auraInstanceID]
        if data and MatchDispelTrigger(lane, unit, data, trigger) then
            local token = data.auraInstanceID
            if IsSecret(token) then token = nil end
            local r, g, b, a, secret = DispelVisualColor(lane, visual, unit, data)
            return true, r, g, b, a, secret == true, token
        end
    end
    return false
end

A3._UpdateClassicDispelSymbols = function(frame, lane, visual, unit)
    local renderer = A3.ClassicVisuals
    if not (renderer and type(renderer.UpdateDispelSymbols) == "function") then return false end
    local symbol = visual and visual.symbol
    if not (frame and symbol and symbol.enabled == true and lane and lane.all) then
        return renderer.HideDispelSymbols and renderer.HideDispelSymbols(frame) or false
    end
    -- Per-frame scratch set, wiped instead of reallocated on every
    -- visual-dirty UNIT_AURA; the renderer only reads it during this call.
    local present = WipeTable(frame._msufA3ClassicDispelPresent)
    frame._msufA3ClassicDispelPresent = present
    for _, data in pairs(lane.all) do
        local dispelName = PlainString(data and data.dispelName)
        if dispelName and dispelName ~= "" then
            local matched = symbol.trigger == "DISPEL_TYPE"
                or MatchDispelTrigger(lane, unit, data, symbol.trigger)
            if matched then present[dispelName] = true end
        end
    end
    return renderer.UpdateDispelSymbols(frame, visual, present)
end

local function HasActiveDebuff(lane)
    return lane and lane.active and next(lane.active) ~= nil or false
end

local function StoreLaneAuraVisualCache(lane, anyDebuff, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken)
    lane._msufA3VisualCacheReady = true
    lane._msufA3VisualAnyDebuff = anyDebuff == true
    lane._msufA3VisualBorderActive = borderActive == true
    lane._msufA3VisualBorderR, lane._msufA3VisualBorderG = br, bg
    lane._msufA3VisualBorderB, lane._msufA3VisualBorderA = bb, ba
    lane._msufA3VisualBorderSecret = borderSecret == true
    lane._msufA3VisualBorderToken = borderToken
    lane._msufA3VisualOverlayActive = overlayActive == true
    lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG = orr, og
    lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA = ob, oa
    lane._msufA3VisualOverlaySecret = overlaySecret == true
    lane._msufA3VisualOverlayToken = overlayToken
end

local function NotifyFrameAuraVisuals(frame)
    if not frame then return end
    if frame._msufA3DeferAuraVisualNotify == true then
        return
    end
    local active = frame._msufActiveElements
    local elements = UF and UF.elements
    local borders = active and active.Borders == true and elements and elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_A3_AURA_VISUAL", A3._ClassicBindFrameUnit(frame))
    end
    if frame.MSUFSpec and frame.MSUFSpec.scope == "group" then
        local visuals = active and active.GroupVisuals == true and elements and elements.GroupVisuals
        if visuals and visuals.Update then
            visuals.Update(frame, "MSUF_A3_AURA_VISUAL", A3._ClassicBindFrameUnit(frame))
        end
    end
end

local function SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
    if not frame then return false end
    br, bg, bb, ba = br or 0.25, bg or 0.75, bb or 1, ba or 1
    orr, og, ob, oa = orr or br, og or bg, ob or bb, oa or ba
    borderSecret = borderSecret == true
    overlaySecret = overlaySecret == true
    local renderer = A3.ClassicVisuals
    local overlayRendererChanged = renderer and type(renderer.UpdateDispelOverlay) == "function"
        and renderer.UpdateDispelOverlay(frame, visual, overlayActive, orr, og, ob, oa) or false
    local borderChanged = frame._msufA3DispelActive ~= borderActive
        or frame._msufA3DispelColorSecret ~= borderSecret
        or frame._msufA3DispelToken ~= borderToken
    if not borderChanged and not borderSecret then
        if HasSecretColor(frame._msufA3DispelR, frame._msufA3DispelG, frame._msufA3DispelB, frame._msufA3DispelA) then
            borderChanged = true
        else
            borderChanged = frame._msufA3DispelR ~= br
                or frame._msufA3DispelG ~= bg
                or frame._msufA3DispelB ~= bb
                or frame._msufA3DispelA ~= ba
        end
    end
    local overlayChanged = frame._msufA3DispelOverlayActive ~= overlayActive
        or frame._msufA3DispelOverlayColorSecret ~= overlaySecret
        or frame._msufA3DispelOverlayToken ~= overlayToken
    if not overlayChanged and not overlaySecret then
        if HasSecretColor(frame._msufA3DispelOverlayR, frame._msufA3DispelOverlayG, frame._msufA3DispelOverlayB, frame._msufA3DispelOverlayA) then
            overlayChanged = true
        else
            overlayChanged = frame._msufA3DispelOverlayR ~= orr
                or frame._msufA3DispelOverlayG ~= og
                or frame._msufA3DispelOverlayB ~= ob
                or frame._msufA3DispelOverlayA ~= oa
        end
    end
    local changed = borderChanged or overlayChanged
        or frame._msufA3DebuffStripeActive ~= stripeActive
        or frame._msufA3DebuffStripeR ~= (visual and visual.stripeR)
        or frame._msufA3DebuffStripeG ~= (visual and visual.stripeG)
        or frame._msufA3DebuffStripeB ~= (visual and visual.stripeB)
        or frame._msufA3DebuffStripeA ~= (visual and visual.stripeAlpha)
        or frame._msufA3DebuffStripeEdge ~= (visual and visual.stripeEdge)
        or frame._msufA3DebuffStripeHeight ~= (visual and visual.stripeHeight)
    if not changed then return overlayRendererChanged end
    frame._msufA3DispelActive = borderActive == true
    frame._msufA3DispelColorSecret = borderSecret or nil
    frame._msufA3DispelToken = borderToken
    frame._msufA3DispelR, frame._msufA3DispelG, frame._msufA3DispelB, frame._msufA3DispelA = br, bg, bb, ba
    frame._msufA3DispelOverlayActive = overlayActive == true
    frame._msufA3DispelOverlayColorSecret = overlaySecret or nil
    frame._msufA3DispelOverlayToken = overlayToken
    frame._msufA3DispelOverlayR, frame._msufA3DispelOverlayG, frame._msufA3DispelOverlayB, frame._msufA3DispelOverlayA = orr, og, ob, oa
    frame._msufA3DebuffStripeActive = stripeActive == true
    frame._msufA3DebuffStripeR = visual and visual.stripeR or nil
    frame._msufA3DebuffStripeG = visual and visual.stripeG or nil
    frame._msufA3DebuffStripeB = visual and visual.stripeB or nil
    frame._msufA3DebuffStripeA = visual and visual.stripeAlpha or nil
    frame._msufA3DebuffStripeEdge = visual and visual.stripeEdge or nil
    frame._msufA3DebuffStripeHeight = visual and visual.stripeHeight or nil
    NotifyFrameAuraVisuals(frame)
    return true
end

local function FrameHasAuraVisualState(frame)
    return frame
        and (frame._msufA3DispelActive == true
            or frame._msufA3DispelOverlayActive == true
            or frame._msufA3DebuffStripeActive == true
            or frame._msufA3DispelColorSecret == true
            or frame._msufA3DispelOverlayColorSecret == true
            or frame._msufA3DispelToken ~= nil
            or frame._msufA3DispelOverlayToken ~= nil
            or frame._msufA3ClassicDispelSymbolsActive == true)
end

ClearFrameAuraVisualState = function(frame)
    if not frame then return false end
    local renderer = A3.ClassicVisuals
    local symbolChanged = renderer and type(renderer.HideDispelSymbols) == "function"
        and renderer.HideDispelSymbols(frame) or false
    if not FrameHasAuraVisualState(frame) then
        return symbolChanged
    end
    return SetFrameAuraVisualState(frame, false, nil, nil, nil, nil, false, nil, false, nil, nil, nil, nil, false, nil, false, nil)
        or symbolChanged
end

local function UpdateFrameAuraVisualState(frame, state, cfg, unit)
    local visual = cfg and cfg.visual
    if not (visual and visual.enabled == true) then
        return ClearFrameAuraVisualState(frame)
    end
    if cfg and cfg.visualDirect == true then
        --- directVisualEligible is false whenever the symbol is enabled, so this
        --- branch only ever runs with symbols off. It must still clear a host
        --- left over from the previous config: turning the symbol off flips
        --- eligibility on, and every later update takes this branch, so the last
        --- rendered symbol would stay frozen on the frame. Every other exit from
        --- this function touches the symbol host; this one did not.
        local directRenderer = A3.ClassicVisuals
        local directSymbolChanged = directRenderer
            and type(directRenderer.HideDispelSymbols) == "function"
            and directRenderer.HideDispelSymbols(frame) or false
        local borderActive, br, bg, bb, ba, borderSecret, borderToken = false
        local overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = false
        if visual.borderEnabled == true then
            borderActive, br, bg, bb, ba, borderSecret, borderToken = ResolveDirectDispelTriggerVisual(unit, visual, visual.borderTrigger)
        end
        if visual.overlayEnabled == true then
            if visual.borderEnabled == true and visual.overlayTrigger == visual.borderTrigger then
                overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = borderActive, br, bg, bb, ba, borderSecret, borderToken
            else
                overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = ResolveDirectDispelTriggerVisual(unit, visual, visual.overlayTrigger)
            end
        end
        return SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, false, visual)
            or directSymbolChanged
    end
    local lane = state and state.lanes and state.lanes.debuff
    if not (lane and lane.config and lane.config.enabled == true) then
        return ClearFrameAuraVisualState(frame)
    end
    if lane._msufA3VisualCacheReady == true then
        local anyDebuff = lane._msufA3VisualAnyDebuff == true
        local stripeActive = anyDebuff and visual.stripeEnabled == true
        local symbolChanged = A3._UpdateClassicDispelSymbols(frame, lane, visual, unit)
        return SetFrameAuraVisualState(frame,
            anyDebuff and lane._msufA3VisualBorderActive == true,
            lane._msufA3VisualBorderR, lane._msufA3VisualBorderG,
            lane._msufA3VisualBorderB, lane._msufA3VisualBorderA,
            lane._msufA3VisualBorderSecret == true, lane._msufA3VisualBorderToken,
            anyDebuff and lane._msufA3VisualOverlayActive == true,
            lane._msufA3VisualOverlayR, lane._msufA3VisualOverlayG,
            lane._msufA3VisualOverlayB, lane._msufA3VisualOverlayA,
            lane._msufA3VisualOverlaySecret == true, lane._msufA3VisualOverlayToken,
            stripeActive, visual) or symbolChanged
    end
    local anyDebuff = HasActiveDebuff(lane)
    local borderActive, br, bg, bb, ba, borderSecret, borderToken = false
    local overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = false
    if anyDebuff and visual.borderEnabled == true then
        borderActive, br, bg, bb, ba, borderSecret, borderToken = ResolveDispelTriggerVisual(lane, unit, visual, visual.borderTrigger)
    end
    if anyDebuff and visual.overlayEnabled == true then
        if visual.borderEnabled == true and visual.overlayTrigger == visual.borderTrigger then
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = borderActive, br, bg, bb, ba, borderSecret, borderToken
        else
            overlayActive, orr, og, ob, oa, overlaySecret, overlayToken = ResolveDispelTriggerVisual(lane, unit, visual, visual.overlayTrigger)
        end
    end
    StoreLaneAuraVisualCache(lane, anyDebuff, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken)
    local stripeActive = anyDebuff and visual.stripeEnabled == true
    local symbolChanged = A3._UpdateClassicDispelSymbols(frame, lane, visual, unit)
    return SetFrameAuraVisualState(frame, borderActive, br, bg, bb, ba, borderSecret, borderToken, overlayActive, orr, og, ob, oa, overlaySecret, overlayToken, stripeActive, visual)
        or symbolChanged
end

local function EmptyAuraPayload(updateInfo)
    return updateInfo and not updateInfo.isFullUpdate
        and not updateInfo.addedAuras
        and not updateInfo.updatedAuraInstanceIDs
        and not updateInfo.removedAuraInstanceIDs
end

local function ConfigHasEnabledAuraLane(cfg)
    local lanes = cfg and cfg.lanes
    for _, lane in pairs(lanes or EMPTY_LANES) do
        if lane and lane.enabled == true then return true end
    end
    return false
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

local function CurrentFrameState(frame, unit)
    local state = frame and frame._msufA3State
    if frame and frame._msufA3GroupRuntime == true then
        local cfg = ResolveGroupFrameConfig(frame, unit)
        if state and state.config == cfg and state.unit == unit then
            return state, cfg
        end
        if not (cfg and cfg.enabled) then
            return state, cfg
        end
        state = ApplyConfig(frame, cfg)
        return state, cfg
    end

    local gen = A3._runtimeConfigGen or 1
    if state and state.configGen == gen and state.config and state.unit == unit
        and state.frameSpec == frame.MSUFSpec then
        return state, state.config
    end

    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        return state, cfg
    end
    state = ApplyConfig(frame, cfg)
    return state, cfg
end

--- AurasElement.Update lands here from Dispatch. Keep this function narrow:
--- normalize the unit, get/apply compiled config, update both lanes, and notify
--- frame-level aura visuals. Menu preview refreshes and DB writes belong outside.
local function UpdateAuras(frame, event, unit, updateInfo, forceFull)
    if not frame then return false end
    local frameUnit = A3._ClassicBindFrameUnit(frame)
    if unit and IsSecret(unit) == true then
        unit = frameUnit
    elseif unit == nil then
        unit = frameUnit
    elseif unit ~= frameUnit then
        return false
    end
    local preState = frame._msufA3State
    -- A lane update that raised never reached the end of the lane loop below,
    -- so its sentinel is still set and the lanes are only partly merged: this
    -- event owes a full update whatever its payload says.
    if preState and preState.scanning == true then preState.needFullUpdate = true end
    if EmptyAuraPayload(updateInfo) and forceFull ~= true
        and not (preState and preState.needFullUpdate == true) then
        return false
    end

    -- Invalidate this unit's token-membership sets only when this event can
    -- change membership (see A3._ClassicAuraTokenSet). The config-applied case
    -- is folded in after CurrentFrameState below.
    local added = updateInfo and updateInfo.addedAuras
    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    local membershipBumped = forceFull == true or not updateInfo or updateInfo.isFullUpdate == true
        or (preState and preState.needFullUpdate == true)
        or (added ~= nil and added[1] ~= nil) or (removed ~= nil and removed[1] ~= nil)
    if membershipBumped then
        A3._ClassicAuraTokenSerial[unit] = (A3._ClassicAuraTokenSerial[unit] or 0) + 1
    end

    local state, cfg = CurrentFrameState(frame, unit)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        return false
    end

    forceFull = forceFull == true or state.config ~= cfg
    local full = forceFull == true or state.needFullUpdate == true or not updateInfo or updateInfo.isFullUpdate == true
    if full and not membershipBumped then
        -- CurrentFrameState applied a new config: the lanes rescan fully and
        -- their filters may differ, so no cached set may answer them.
        A3._ClassicAuraTokenSerial[unit] = (A3._ClassicAuraTokenSerial[unit] or 0) + 1
    end

    -- needFullUpdate and the scanning sentinel are cleared only where the lane
    -- state is known good again: the two lane-less exits here, and the end of
    -- the lane loop below.
    if cfg.visualDirect == true and not ConfigHasEnabledAuraLane(cfg) then
        state.scanning, state.needFullUpdate = nil, false
        return UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
    end

    if full and UnitExists then
        local exists = UnitExists(unit)
        if not IsSecret(exists) and exists == false then
            for _, lane in pairs(state.lanes or EMPTY_LANES) do ClearLane(lane) end
            ClearFrameAuraVisualState(frame)
            state.scanning, state.needFullUpdate = nil, false
            return false
        end
    end

    local changedCount = 0
    local auraVisualDirty = false

    local order = cfg.laneOrder or A3._ClassicBaseLaneOrder
    -- Native PLAYER filter trust is a property of the unit, not the lane:
    -- evaluate UnitInRange at most once per event, for the first enabled lane
    -- that uses the native filter. The player is always in range.
    local rangeTrusted
    -- Dirty until every lane finished. A scan or delta merge that raises leaves
    -- the sentinel set and keeps a pending needFullUpdate, so the next event
    -- rescans instead of trusting half-merged lanes and their stale buttons.
    state.scanning = true
    for i = 1, #order do
        local lane = state.lanes[order[i]]
        local laneCfg = lane and lane.config
        if rangeTrusted == nil and laneCfg and laneCfg.enabled and laneCfg.nativePlayerFilter == true then
            rangeTrusted = true
            if unit ~= "player" and type(UnitInRange) == "function" then
                local inRange, checkedRange = UnitInRange(unit)
                if not IsSecret(inRange) and not IsSecret(checkedRange)
                    and checkedRange == true and inRange == false then
                    rangeTrusted = false
                end
            end
        end
        local changed, visualDirty = UpdateAuraLaneRuntime(lane, unit, updateInfo, full, rangeTrusted)
        if changed then
            changedCount = changedCount + 1
            if visualDirty then auraVisualDirty = true end
        end
    end
    state.scanning, state.needFullUpdate = nil, false

    local visualChanged = false
    if cfg.visualDirect == true then
        visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
    elseif auraVisualDirty == true then
        if cfg.visual ~= nil or FrameHasAuraVisualState(frame) then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    elseif full then
        local hasFrameVisual = FrameHasAuraVisualState(frame)
        if hasFrameVisual then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    end
    return changedCount > 0 or visualChanged == true
end

local function RenderCachedAuras(frame, combatOnly)
    if not frame then return false end
    local unit = A3._ClassicBindFrameUnit(frame)
    local state, cfg = CurrentFrameState(frame, unit)
    if not (state and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    if state.needFullUpdate == true or state.scanning == true then
        return UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    end

    local changed = false
    local order = cfg.laneOrder or A3._ClassicBaseLaneOrder
    for i = 1, #order do
        local lane = state.lanes[order[i]]
        local laneCfg = lane and lane.config
        if laneCfg and laneCfg.enabled and (combatOnly ~= true or laneCfg.needsCombatRefresh == true) then
            RenderLane(lane, unit)
            changed = true
        end
    end
    if changed and (cfg.visual ~= nil or FrameHasAuraVisualState(frame)) then
        UpdateFrameAuraVisualState(frame, state, cfg, unit)
    end
    return changed
end

local function ResetAurasForIdentity(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", A3._ClassicBindFrameUnit(frame), nil, true)
end

local function NeedsCombatAuraEvents(cfg)
    if not (cfg and cfg.enabled and cfg.lanes) then return false end
    for _, lane in pairs(cfg.lanes) do
        if lane and lane.enabled and lane.needsCombatRefresh == true then return true end
    end
    return false
end

function A3.EnableFrame(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    if not (unit and MANAGED_UNITS[unit]) then return false end
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(unit, frame, false)
        return false
    end
    ApplyConfig(frame, cfg)
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[unit] = frame
    A3.SetUnitFrameOwner(unit, frame, true)
    UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    return true
end

function A3.DisableFrame(frame)
    if not frame then return true end
    local unit = A3._ClassicBindFrameUnit(frame)
    HideState(frame)
    frame._msufA3GroupConfig = nil
    frame._msufA3GroupSource = nil
    frame._msufA3GroupUnit = nil
    frame._msufA3GroupGen = nil
    frame._msufA3GroupRuntime = nil
    if unit then
        if A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
            A3._runtimeFrames[unit] = nil
        end
        A3.SetUnitFrameOwner(unit, frame, false)
    end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", A3._ClassicBindFrameUnit(frame), nil, true)
end

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = RenderCachedAuras

function A3.HandleUnitAura(frame, event, unit, updateInfo)
    return UpdateAuras(frame, event, unit, updateInfo, false)
end

function A3.UnitFrameOwnsUnitAura(unit, frame)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame or false
end

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

A3._ClassicAuraRuntimeCombatBlocked = function()
    return (InCombatLockdown and InCombatLockdown()) or _G.MSUF_InCombat == true
end

function A3._EnsureDeferredAuraRuntimeDriver()
    if A3._deferredAuraRuntimeFrame then return A3._deferredAuraRuntimeFrame end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or A3._ClassicAuraRuntimeCombatBlocked() then return end
        -- The flush unregisters this event only after its queue is consumed,
        -- so an error while applying one scope keeps the retry armed.
        A3._FlushDeferredAuraRuntime()
    end)
    A3._deferredAuraRuntimeFrame = frame
    return frame
end

function A3._QueueDeferredAuraRuntime(scope, reason, visuals)
    scope = tostring(scope or "shared"):lower()
    A3._deferredAuraRuntime = true
    A3._deferredAuraRuntimeReason = reason or A3._deferredAuraRuntimeReason or "AURAS3_CLASSIC_DEFERRED"
    if visuals == true then A3._deferredAuraRuntimeVisuals = true end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
    elseif A3._deferredAuraRuntimeAll ~= true then
        A3._deferredAuraRuntimeScopes = A3._deferredAuraRuntimeScopes or {}
        A3._deferredAuraRuntimeScopes[scope] = true
    end
    local frame = A3._EnsureDeferredAuraRuntimeDriver()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return false
end

function A3._AuraPreviewGroupKind(scope)
    local key = tostring(scope or ""):lower()
    if key == "party" or key == "gf_party" or key:match("^party%d+$") then return "party", true end
    if key == "raid" or key == "gf_raid" or key:match("^raid%d+$") then return "raid", true end
    if key == "mythicraid" or key == "gf_mythicraid" then return "mythicraid", true end
    if key == "" or key == "shared" or key == "global" or key == "all" or key == "*"
        or key == "group" or key == "groups" then
        return nil, true
    end
    return nil, false
end

function A3._NotifyAuraColdpathPreview(reason, scope)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_CLASSIC_PREVIEW")
    end
    local didWork = false
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason or "AURAS3_CLASSIC_PREVIEW")
        didWork = true
    end
    local gf = A3._GroupAPI()
    local kind, touchesGroup = A3._AuraPreviewGroupKind(scope)
    if touchesGroup and gf and type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout(kind)
        didWork = true
    elseif touchesGroup and type(_G.MSUF_GF_RefreshPreviewLayout) == "function" then
        _G.MSUF_GF_RefreshPreviewLayout()
        didWork = true
    end
    return didWork
end

local function ApplyRuntimeUnit(runtimeUnit)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(runtimeUnit, "AURAS3_CLASSIC_RUNTIME_UNIT")
    end
    local frame = (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit])
        or (UF.frames and UF.frames[runtimeUnit])
        or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[runtimeUnit])
        or _G["MSUF_" .. runtimeUnit]
    if not frame then return false end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.EnableFrame(frame)
    end
    return true
end

function A3._GroupAPI()
    local ns = MSUF or _G.MSUF_NS or _G.MSUF
    return ns and ns.GF or nil
end

function A3._ApplyGroupAuraFrame(frame, unit, kind)
    if not (frame and type(unit) == "string" and unit ~= "") then return false end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_GROUP_FRAME")
    end
    frame._msufIsGroupFrame = true
    if kind then frame._msufGFKind = kind end
    local spec = frame.MSUFSpec
    local gf = A3._GroupAPI()
    if gf and type(gf.CompileSpec) == "function" and kind then
        spec = gf.CompileSpec(kind, frame, unit)
    end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", spec, nil)
    else
        A3.RenderFrame(frame)
    end
    return true
end

function A3._RequestGroupKindNow(kind)
    local gf = A3._GroupAPI()
    if not gf then return false end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(kind or "group", "AURAS3_CLASSIC_GROUP_KIND")
    end

    local didWork = false
    if type(gf.ForEachFrame) == "function" then
        didWork = gf.ForEachFrame(function(frame, frameUnit, frameKind)
            if kind == nil or frameKind == kind then
                return A3._ApplyGroupAuraFrame(frame, frameUnit, frameKind)
            end
            return false
        end, true) == true
    end

    if not didWork and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, gf.DIRTY_AURAS)
        return true
    end
    return didWork
end

function A3._RequestGroupUnitNow(unit)
    local gf = A3._GroupAPI()
    if not (gf and type(unit) == "string" and unit ~= "") then return false end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_GROUP_UNIT")
    end
    local frame = type(gf.FrameForUnit) == "function" and gf.FrameForUnit(unit) or nil
    return frame and A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) or false
end

local function RequestUnitNow(unit)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        local didWork = ApplyRuntimeUnit("player")
        didWork = ApplyRuntimeUnit("target") or didWork
        didWork = ApplyRuntimeUnit("focus") or didWork
        for i = 1, 5 do
            didWork = ApplyRuntimeUnit("boss" .. i) or didWork
        end
        for i = 1, math_max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3) do
            didWork = ApplyRuntimeUnit("arena" .. i) or didWork
        end
        didWork = A3._RequestGroupKindNow(nil) or didWork
        return didWork
    end
    if unit == "boss" then
        local didWork = false
        for i = 1, 5 do
            didWork = ApplyRuntimeUnit("boss" .. i) or didWork
        end
        return didWork
    end
    if unit == "arena" then
        local didWork = false
        for i = 1, math_max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3) do
            didWork = ApplyRuntimeUnit("arena" .. i) or didWork
        end
        return didWork
    end
    if unit == "group" or unit == "groups" then
        return A3._RequestGroupKindNow(nil)
    end
    if unit == "party" or unit == "gf_party" then
        return A3._RequestGroupKindNow("party")
    end
    if unit == "raid" or unit == "gf_raid" then
        local didWork = A3._RequestGroupKindNow("raid")
        return A3._RequestGroupKindNow("mythicraid") or didWork
    end
    if unit == "mythicraid" or unit == "gf_mythicraid" then
        return A3._RequestGroupKindNow("mythicraid")
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
        return A3._RequestGroupUnitNow(unit)
    end
    unit = NormalizeRuntimeUnit(unit)
    return unit and ApplyRuntimeUnit(unit) or false
end

function A3.RequestUnit(unit, delay)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_REQUEST_UNIT")
    end
    delay = tonumber(delay) or 0
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function() A3.RequestUnit(unit, 0) end)
        return true
    end
    return RequestUnitNow(unit)
end

function A3._ClassicRefreshAllNow()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    Compile.ResetFrameSpecConfigCache()
    RequestUnitNow("*")
    return true
end

function A3.RefreshAll()
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime("shared", "AURAS3_CLASSIC_REFRESH_ALL")
    end
    if A3._deferredAuraRuntime == true then
        -- Out of combat a queue survives only a flush that stopped on an error.
        -- A full refresh covers every queued scope, so widen that queue and let
        -- the flush run it once and consume it.
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
        return A3._FlushDeferredAuraRuntime()
    end
    return A3._ClassicRefreshAllNow()
end

A3._requestApplyScopeKeys = A3._requestApplyScopeKeys or {
    player = true, target = true, focus = true, boss = true, arena = true,
    party = true, raid = true, mythicraid = true,
    gf_party = true, gf_raid = true, gf_mythicraid = true,
    group = true, groups = true,
    shared = true, global = true, all = true, ["*"] = true,
}

A3._LooksLikeApplyScope = function(value)
    value = tostring(value or ""):lower()
    if value == "" then return false end
    if A3._requestApplyScopeKeys[value] then return true end
    return value:match("^boss%d+$") ~= nil
        or value:match("^arena%d+$") ~= nil
        or value:match("^party%d+$") ~= nil
        or value:match("^raid%d+$") ~= nil
end

--- The shared Auras3 core installs a no-runtime RequestScope stub before the
--- client backend loads.  Classic must replace it just like Mainline does;
--- otherwise Menu2 changes only invalidate configuration and never reach the
--- scan lanes until a reload or unrelated identity event.
function A3.RequestScope(scope, reason)
    scope = tostring(scope or "shared"):lower()
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope, reason or "AURAS3_CLASSIC_SCOPE_APPLY")
    end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        return A3.RefreshAll()
    end
    local result = A3.RefreshUnit(scope)
    A3._NotifyAuraColdpathPreview(reason or "AURAS3_CLASSIC_SCOPE_APPLY", scope)
    return result
end

function A3.RequestApply(scopeOrReason, reason)
    if A3._LooksLikeApplyScope(scopeOrReason) then
        local result = A3.RequestScope(scopeOrReason, reason or "AURAS3_CLASSIC_REQUEST_APPLY")
        -- Retry a queue left by a flush that stopped on an error. The requested
        -- scope is applied first, so a still-failing queued scope cannot block
        -- it. RefreshAll below consumes a stale queue itself.
        if A3._deferredAuraRuntime == true and not A3._ClassicAuraRuntimeCombatBlocked() then
            A3._FlushDeferredAuraRuntime()
        end
        return result
    end
    return A3.RefreshAll()
end

function A3.RefreshUnit(unit)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_REFRESH_UNIT")
    end
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    Compile.ResetFrameSpecConfigCache()
    return A3.RequestUnit(unit, 0)
end

function A3.ApplyFontsFromGlobal(scope, reason)
    if A3._ClassicAuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_CLASSIC_FONT_VISUALS", true)
    end
    local frames = A3._runtimeFrames
    if not frames then return true end
    for _, frame in pairs(frames) do
        local state = frame and frame._msufA3State
        if state then
            for _, lane in pairs(state.lanes or EMPTY_LANES) do
                for i = 1, lane.createdButtons or 0 do
                    local button = lane[i]
                    if button then ApplyButtonLayout(lane, button, i) end
                end
            end
        end
    end
    if scope ~= nil then return A3.RequestScope(scope, reason or "AURAS3_CLASSIC_FONT_VISUALS") end
    return true
end
MSUF.ExportPublic("MSUF_Auras3_ApplyFontsFromGlobal", A3.ApplyFontsFromGlobal)

--- Applies the queue collected while combat blocked aura runtime work. The
--- queue is consumed only as work completes: a scope entry is removed after its
--- RefreshUnit returns, and the flags and PLAYER_REGEN_ENABLED registration are
--- cleared only after every scope succeeded. A Lua error while applying one
--- scope therefore leaves that scope and the not-yet-run ones queued, and the
--- next combat end, RefreshAll or scoped RequestApply retries them. Returns
--- false without consuming anything if combat blocks the work, including when
--- combat begins mid-flush.
function A3._FlushDeferredAuraRuntime()
    if A3._ClassicAuraRuntimeCombatBlocked() then return false end
    local driver = A3._deferredAuraRuntimeFrame
    if A3._deferredAuraRuntime ~= true then
        if driver then driver:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    local all = A3._deferredAuraRuntimeAll == true
    local scopes = A3._deferredAuraRuntimeScopes
    local reason = A3._deferredAuraRuntimeReason or "AURAS3_CLASSIC_DEFERRED"
    local previewScope = all and "shared" or nil
    if all or not scopes then
        A3._ClassicRefreshAllNow()
        if A3._ClassicAuraRuntimeCombatBlocked() then return false end
    else
        -- Snapshot the keys: RefreshUnit may requeue a scope, and pairs must
        -- not see the live table change while it walks it.
        local keys = WipeTable(A3._deferredAuraFlushKeys)
        A3._deferredAuraFlushKeys = keys
        local count = 0
        for scope in pairs(scopes) do
            count = count + 1
            keys[count] = scope
        end
        for i = 1, count do
            local scope = keys[i]
            if scope == nil then break end
            previewScope = previewScope or scope
            A3.RefreshUnit(scope)
            if A3._ClassicAuraRuntimeCombatBlocked() then return false end
            local live = A3._deferredAuraRuntimeScopes
            if live then live[scope] = nil end
        end
    end
    A3._deferredAuraRuntime = nil
    A3._deferredAuraRuntimeAll = nil
    A3._deferredAuraRuntimeScopes = nil
    A3._deferredAuraRuntimeVisuals = nil
    A3._deferredAuraRuntimeReason = nil
    if driver then driver:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    A3._NotifyAuraColdpathPreview(reason, previewScope)
    return true
end

A3._HideLane = function(lane)
    if not lane then return false end
    if lane.frame and lane.createdButtons ~= nil then
        ClearLane(lane)
        lane.frame:Hide()
        return true
    end
    if lane.Hide then lane:Hide(); return true end
    return false
end

MSUF.InstallClassicAuraPreview({
    A3 = A3,
    ApplyConfig = ApplyConfig,
    CompileFrameAuraVisual = CompileFrameAuraVisual,
    ExportPublic = ExportPublic,
    HideState = HideState,
    ResolveGroupFrameConfig = ResolveGroupFrameConfig,
    UF = UF,
    UpdateAuras = UpdateAuras,
})

function A3.InvalidateUnitRuntimeConfig(unit)
    local runtimeUnit = NormalizeRuntimeUnit(unit)
    if runtimeUnit and A3._runtimeConfigCache then A3._runtimeConfigCache[runtimeUnit] = nil end
    Compile.ResetFrameSpecConfigCache()
    return runtimeUnit
end

function A3.RenderUnitChangedFrame(frame, oldUnit, newUnit)
    if not frame then return false end
    newUnit = newUnit or A3._ClassicBindFrameUnit(frame)
    if oldUnit and A3._runtimeFrames and A3._runtimeFrames[oldUnit] == frame then
        A3._runtimeFrames[oldUnit] = nil
    end
    if newUnit then
        frame.unit = newUnit
        A3.InvalidateUnitRuntimeConfig(newUnit)
    end
    if A3._ClassicAuraRuntimeCombatBlocked() then
        -- Only the config recompile waits for combat end. The rescan below
        -- stays synchronous: a secure header can rebind this button to another
        -- unit in combat, and the scan touches only non-secure aura children.
        A3._QueueDeferredAuraRuntime(newUnit or "shared", "AURAS3_CLASSIC_UNIT_CHANGED")
    end
    -- This is a cold identity path. Blizzard's Classic TargetFrame performs a
    -- complete synchronous UpdateAuras here; delaying ours could leave a lane
    -- on the previous/partial unit until an unrelated menu apply or unit swap.
    return ResetAurasForIdentity(frame)
end

A3.OnFrameUnitChanged = A3.RenderUnitChangedFrame
A3.RefreshRuntime = A3.RefreshAll

local AurasElement = {
    events = { "UNIT_AURA" },
    unitlessEvents = EMPTY_EVENTS,
}

local function EnsureClassicAuraOnShowRefresh(frame)
    if not (frame and frame.HookScript) or frame._msufA3ClassicOnShowHooked == true then return end
    frame._msufA3ClassicOnShowHooked = true
    frame:HookScript("OnShow", function(owner)
        local active = owner and owner._msufActiveElements
        -- Hidden target/focus/boss frames can miss their identity event before
        -- RegisterUnitWatch shows them. The core's lean OnShow reseed excludes
        -- Auras by design, so Classic owns this one cold full scan itself.
        if active and active.Auras == true and not IsGroupFrame(owner) then
            ResetAurasForIdentity(owner)
        elseif owner and owner._msufA3ClassicHiddenStale == true
            and owner._msufGFHeaderOnShowDeferred ~= true
            and owner._msufA3GroupRuntime == true and IsGroupFrame(owner) then
            -- A hidden group child receives no UNIT_AURA, so removals delivered
            -- while it was hidden are lost. Reconcile once per show edge. A
            -- deferred header show keeps the marker and needFullUpdate instead.
            owner._msufA3ClassicHiddenStale = nil
            ResetAurasForIdentity(owner)
        end
    end)
    frame:HookScript("OnHide", function(owner)
        local state = owner and owner._msufA3State
        if state and IsGroupFrame(owner) then
            state.needFullUpdate = true
            owner._msufA3ClassicHiddenStale = true
        end
    end)
end

A3._ClassicWeaponAuraEvents = A3._ClassicWeaponAuraEvents or { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }
A3._ClassicCombatWeaponAuraEvents = A3._ClassicCombatWeaponAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }
A3._ClassicTargetIdentityAuraEvents = A3._ClassicTargetIdentityAuraEvents or { "PLAYER_TARGET_CHANGED" }
A3._ClassicFocusIdentityAuraEvents = A3._ClassicFocusIdentityAuraEvents or { "PLAYER_FOCUS_CHANGED" }
A3._ClassicBossIdentityAuraEvents = A3._ClassicBossIdentityAuraEvents or { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }
A3._ClassicArenaIdentityAuraEvents = A3._ClassicArenaIdentityAuraEvents or { "ARENA_OPPONENT_UPDATE" }
A3._ClassicTargetIdentityCombatAuraEvents = A3._ClassicTargetIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }
A3._ClassicFocusIdentityCombatAuraEvents = A3._ClassicFocusIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_FOCUS_CHANGED" }
A3._ClassicBossIdentityCombatAuraEvents = A3._ClassicBossIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }
A3._ClassicArenaIdentityCombatAuraEvents = A3._ClassicArenaIdentityCombatAuraEvents
    or { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ARENA_OPPONENT_UPDATE" }
A3._ClassicIdentityAuraEventsByUnit = A3._ClassicIdentityAuraEventsByUnit or {
    target = A3._ClassicTargetIdentityAuraEvents,
    focus = A3._ClassicFocusIdentityAuraEvents,
    boss1 = A3._ClassicBossIdentityAuraEvents,
    boss2 = A3._ClassicBossIdentityAuraEvents,
    boss3 = A3._ClassicBossIdentityAuraEvents,
    boss4 = A3._ClassicBossIdentityAuraEvents,
    boss5 = A3._ClassicBossIdentityAuraEvents,
    arena1 = A3._ClassicArenaIdentityAuraEvents,
    arena2 = A3._ClassicArenaIdentityAuraEvents,
    arena3 = A3._ClassicArenaIdentityAuraEvents,
}
A3._ClassicIdentityCombatAuraEventsByUnit = A3._ClassicIdentityCombatAuraEventsByUnit or {
    target = A3._ClassicTargetIdentityCombatAuraEvents,
    focus = A3._ClassicFocusIdentityCombatAuraEvents,
    boss1 = A3._ClassicBossIdentityCombatAuraEvents,
    boss2 = A3._ClassicBossIdentityCombatAuraEvents,
    boss3 = A3._ClassicBossIdentityCombatAuraEvents,
    boss4 = A3._ClassicBossIdentityCombatAuraEvents,
    boss5 = A3._ClassicBossIdentityCombatAuraEvents,
    arena1 = A3._ClassicArenaIdentityCombatAuraEvents,
    arena2 = A3._ClassicArenaIdentityCombatAuraEvents,
    arena3 = A3._ClassicArenaIdentityCombatAuraEvents,
}
-- Arena identity events for arena4..N (TBC and Mists field five opponents).
for i = 4, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3 do
    local byUnit, combatByUnit = A3._ClassicIdentityAuraEventsByUnit, A3._ClassicIdentityCombatAuraEventsByUnit
    if byUnit["arena" .. i] == nil then byUnit["arena" .. i] = A3._ClassicArenaIdentityAuraEvents end
    if combatByUnit["arena" .. i] == nil then
        combatByUnit["arena" .. i] = A3._ClassicArenaIdentityCombatAuraEvents
    end
end
A3._ClassicIdentityAuraEvent = A3._ClassicIdentityAuraEvent or {
    PLAYER_TARGET_CHANGED = true,
    PLAYER_FOCUS_CHANGED = true,
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = true,
    ARENA_OPPONENT_UPDATE = true,
}

function AurasElement.IsEnabled(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    if not unit then return false end
    if IsGroupFrame(frame) then
        local cfg = ResolveGroupFrameConfig(frame, unit)
        return cfg and cfg.enabled == true or false
    end
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    return cfg and cfg.enabled == true or false
end

function AurasElement.GetUnitlessEvents(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    local cfg = unit and FrameAuraConfig(frame, unit)
    local combat = NeedsCombatAuraEvents(cfg)
    local weapon = unit == "player" and cfg and cfg.lanes and cfg.lanes.buff
        and cfg.lanes.buff.weaponEnchants == true
    local identity = unit and A3._ClassicIdentityAuraEventsByUnit[unit]
    if identity then
        return combat and A3._ClassicIdentityCombatAuraEventsByUnit[unit] or identity
    end
    if combat and weapon then return A3._ClassicCombatWeaponAuraEvents end
    if weapon then return A3._ClassicWeaponAuraEvents end
    return combat and COMBAT_AURA_EVENTS or EMPTY_EVENTS
end

function AurasElement.Create(frame)
    if frame then
        EnsureState(frame)
        EnsureClassicAuraOnShowRefresh(frame)
    end
end

function AurasElement.Apply(frame)
    if not frame then return end
    local unit = A3._ClassicBindFrameUnit(frame)
    local isGroup = IsGroupFrame(frame)
    frame._msufA3GroupRuntime = isGroup == true or nil
    if isGroup then
        frame._msufA3GroupConfig = nil
    end
    local cfg = isGroup and ResolveGroupFrameConfig(frame, unit) or A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if cfg and cfg.enabled then
        ApplyConfig(frame, cfg)
        if frame._msufActiveElements and frame._msufActiveElements.Auras == true then
            UpdateAuras(frame, "ForceUpdate", unit, nil, true)
        end
    else
        HideState(frame)
    end
end

function AurasElement.Enable(frame)
    EnsureClassicAuraOnShowRefresh(frame)
    local unit = A3._ClassicBindFrameUnit(frame)
    if IsGroupFrame(frame) then
        frame._msufA3GroupRuntime = true
        frame._msufA3GroupConfig = nil
        local cfg = ResolveGroupFrameConfig(frame, unit)
        if not (cfg and cfg.enabled == true) then
            HideState(frame)
            return false
        end
        local state = frame._msufA3State
        if not (state and state.config == cfg and state.unit == unit) then
            ApplyConfig(frame, cfg)
        end
        UpdateAuras(frame, "ForceUpdate", unit, nil, true)
        return true
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        return A3.HandleUnitAura(frame, event, unit, updateInfo)
    end
    if A3._ClassicIdentityAuraEvent[event] == true then
        -- Classic does not guarantee a UNIT_AURA payload when a stable token
        -- (target/focus/bossN) changes GUID. Blizzard's own TargetFrame performs
        -- a full UpdateAuras from PLAYER_TARGET_CHANGED for the same reason.
        -- Keep this cold-path scan synchronous, matching Blizzard's Classic
        -- TargetFrame. Deferring it could leave a partial/previous identity
        -- visible until an unrelated menu apply or another unit swap.
        return ResetAurasForIdentity(frame)
    end
    if event == "WEAPON_ENCHANT_CHANGED" or event == "WEAPON_SLOT_CHANGED" then
        return UpdateAuras(frame, event, A3._ClassicBindFrameUnit(frame), nil, true)
    end
    if event == "MSUF_UNIT_IDENTITY_AURAS"
        or event == "MSUF_UNIT_IDENTITY_SOFT_AURAS" then
        return ResetAurasForIdentity(frame)
    end
    if event == "ForceUpdate"
        or event == "MSUF_FORCE_UPDATE"
        or event == "MSUF_UNIT_IDENTITY"
        or event == "MSUF_UNIT_IDENTITY_SOFT"
        or event == "MSUF_GF_UNIT_IDENTITY" then
        return A3.RenderFrame(frame)
    end
    if event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        return RenderCachedAuras(frame, true)
    end
    return A3.HandleUnitAura(frame, event, unit, updateInfo)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3.nativeAuraBackend = false
A3.classicAuraBackend = true
MSUF.AuraBackendEnabled = true

MSUF.ExportPublic("MSUF_A3_RequestUnit", A3.RequestUnit)
MSUF.ExportPublic("MSUF_Auras3_RefreshUnit", A3.RefreshUnit)
MSUF.ExportPublic("MSUF_Auras3_RefreshAll", A3.RefreshAll)
