-- Castbars/MSUF_CastbarAnchors.lua
--
-- Pure castbar layout logic: positioning (ClearAllPoints/SetPoint), sizing
-- (SetWidth/SetHeight) and the "width source" sync machinery that keeps a
-- castbar's width matched to another frame (the MSUF unitframe, or a Cooldown
-- Viewer container). No combat-path/secret reads happen here.
--
-- This file was previously shipped minified (single-letter names, one statement
-- per line). It has been de-minified for maintainability; behavior is unchanged.
--
-- "Width source" overview:
--   A unit's castbar can either use a manually configured width, or match the
--   width of another frame ("unitframe" / "essential" / "utility"). When a
--   match is configured we hook the source frame's size/show/hide events and
--   re-apply the castbar size whenever the source changes. Because the source
--   frame may not exist yet at login, a bounded retry schedule keeps trying to
--   install the hooks. All of this is deferred out of combat.

local _G = _G
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local floor = math.floor
local ceil = math.ceil
local type = type
local tonumber = tonumber
local tostring = tostring

-- Cached Core unitframe table (refreshed lazily; may be nil early at login).
local unitFramesCache

-- Per-unit castbar DB keys + default anchor offsets (dx/dy used when the saved
-- offset is missing).
local UNIT_CASTBAR = {
    player = { w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight", x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY", detached = "castbarPlayerDetached", match = "castbarPlayerMatchWidth", enable = "enablePlayerCastbar", dx = 0,  dy = 5   },
    target = { w = "castbarTargetBarWidth", h = "castbarTargetBarHeight", x = "castbarTargetOffsetX", y = "castbarTargetOffsetY", detached = "castbarTargetDetached", match = "castbarTargetMatchWidth", enable = "enableTargetCastbar", dx = 65, dy = -15 },
    focus  = { w = "castbarFocusBarWidth",  h = "castbarFocusBarHeight",  x = "castbarFocusOffsetX",  y = "castbarFocusOffsetY",  detached = "castbarFocusDetached",  match = "castbarFocusMatchWidth",  enable = "enableFocusCastbar",  dx = 65, dy = -15 },
    boss   = { w = "bossCastbarWidth",       h = "bossCastbarHeight",      x = "bossCastbarOffsetX",   y = "bossCastbarOffsetY",   detached = "bossCastbarDetached",   match = "bossCastbarMatchWidth",   enable = "enableBossCastbar",   dx = 0,  dy = 0   },
}

-- Valid width-source kinds.
local WIDTH_SOURCE_KINDS = { unitframe = true, essential = true, utility = true }
local COOLDOWN_VIEWER_KINDS = {
    EssentialCooldownViewer = "essential",
    UtilityCooldownViewer = "utility",
}

-- Units that participate in width-source sync.
local CASTBAR_UNITS = { "player", "target", "focus", "boss" }

-- Backoff delays (seconds) for retrying width-source hook installation at login.
local WIDTH_SOURCE_RETRY_DELAYS = { 0.05, 0.15, 0.35, 0.75, 1.5, 3.0, 5.0, 7.0 }

-- Frames already hooked for width-source change notifications (weak keys).
local hookedWidthSourceFrames = setmetatable({}, { __mode = "k" })

-- Current frame -> castbar-unit ownership. A per-unit generation invalidates
-- retired dependencies without walking frames whose WoW hooks cannot be removed.
local widthSourceFrameDependents = setmetatable({}, { __mode = "k" })
local widthSourceDependencyGeneration = { player = 0, target = 0, focus = 0, boss = 0 }

-- Per-unit reusable numeric source snapshots. Avoid building transient strings
-- on every source Show/Hide/Size event.
local widthSourceSignatures = {}
local dirtyWidthSourceUnits = {}

-- Sync state machine flags.
local widthSourceQueued = false             -- a next-frame flush is queued
local widthSourcePendingAfterCombat = false -- work was deferred due to combat
local widthSourceRetryActive = false        -- the hook-install retry loop is running
local widthSourceRetryIndex = 0             -- index into WIDTH_SOURCE_RETRY_DELAYS
local widthSourceRetryGeneration = 0
local widthSourceLifecycleActive = false
local widthSourceBoot
local SyncWidthSourceLifecycle

-- Forward declaration (assigned far below; referenced by the sync machinery).
local ApplyCastbarEffectiveSizeUnit

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

-- Round half away from zero.
local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return floor(value + 0.5)
    end
    return ceil(value - 0.5)
end

local function GeneralDB()
    if type(EnsureDB) == "function" then EnsureDB() end
    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local function CastbarFrameInset(frame, g)
    if type(_G.MSUF_GetCastbarOutlineInset) == "function" then
        local inset = _G.MSUF_GetCastbarOutlineInset(frame, g)
        return tonumber(inset) or 0
    end
    local thickness = tonumber(g and g.castbarOutlineThickness)
    if thickness == nil then thickness = 1 end
    return thickness > 0 and 1 or 0
end

local function GetUnitFrames()
    local uf = MSUF and MSUF.UF
    unitFramesCache = (uf and uf.frames) or unitFramesCache
    return unitFramesCache
end

local function InCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end

-- "boss", "boss1".."boss5" -> "boss"; everything else unchanged.
local function NormalizeUnit(unit)
    unit = tostring(unit or "")
    return unit:match("^boss%d*$") and "boss" or unit
end

local function NormalizeWidthSourceKind(kind)
    return WIDTH_SOURCE_KINDS[kind] and kind or nil
end

local function IsCooldownWidthSourceKind(kind)
    return kind == "essential" or kind == "utility"
end

-- Whether the MSUF castbar should be used for this unit (vs disabled/Blizzard).
local function ShouldUseMSUFCastbar(unit, g)
    local fn = _G.MSUF_ShouldUseMSUFCastbar
    if type(fn) == "function" then
        return fn(unit, g) == true
    end
    local def = UNIT_CASTBAR[NormalizeUnit(unit)]
    return not (def and g and g[def.enable] == false)
end

-- Dirty-only SetPoint wrapper (rounds in the fallback path only; the shared
-- MSUF_SetPointIfChanged rounds internally).
local function SetPoint(frame, point, relTo, relPoint, x, y)
    local fn = _G.MSUF_SetPointIfChanged
    if type(fn) == "function" then
        fn(frame, point, relTo, relPoint, x, y)
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relTo, relPoint, Round(x), Round(y))
end

local function SetWidth(frame, width)
    if _G.MSUF_SetWidthIfChanged then
        _G.MSUF_SetWidthIfChanged(frame, width)
    else
        frame:SetWidth(width)
    end
end

local function SetHeight(frame, height)
    if _G.MSUF_SetHeightIfChanged then
        _G.MSUF_SetHeightIfChanged(frame, height)
    else
        frame:SetHeight(height)
    end
end

------------------------------------------------------------------------
-- Frame lookups
------------------------------------------------------------------------

-- The MSUF unitframe object for a unit (handles boss1..boss5 indexing).
local function GetCoreUnitframe(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = GetUnitFrames()
    return (frames and frames[unit]) or _G["MSUF_" .. tostring(unit or "")]
end

local function GetUnitframe(unit)
    unit = tostring(unit or "")
    local index = tonumber(unit:match("^boss(%d+)$")) or 1
    if NormalizeUnit(unit) == "boss" then
        return GetCoreUnitframe("boss" .. index) or GetCoreUnitframe("boss1")
    end
    return GetCoreUnitframe(unit)
end

-- The visible health geometry of a unitframe. Legacy rectangular frames may
-- expose a dedicated outline host; current 6.0 frames expose their normal
-- outside border separately and account for it below.
local function GetUnitframeWidthSourceFromFrame(frame)
    if not frame then return nil end
    local outline = frame._msufBarOutline
    local outlineFrame = outline and outline.frame
    if outlineFrame and outlineFrame.GetWidth
        and (not outlineFrame.IsShown or outlineFrame:IsShown())
        and (outlineFrame:GetWidth() or 0) > 0 then
        return outlineFrame
    end
    local hp = frame.hpBar or frame.healthBar or frame.health
    if hp and hp.GetWidth and (hp:GetWidth() or 0) > 0 then
        return hp
    end
    return frame
end

local function GetUnitframeWidthSource(unit)
    return GetUnitframeWidthSourceFromFrame(GetUnitframe(unit))
end

-- Width of sourceFrame expressed in targetFrame's scale.
local function ScaledWidth(sourceFrame, targetFrame)
    if not (sourceFrame and sourceFrame.GetWidth) then return nil end
    local w = sourceFrame:GetWidth()
    if not w or w <= 0 then return nil end
    local sourceScale = (sourceFrame.GetEffectiveScale and sourceFrame:GetEffectiveScale()) or 1
    local targetScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
    if sourceScale <= 0 then sourceScale = 1 end
    if targetScale <= 0 then targetScale = 1 end
    -- Preserve the exact on-screen source width. The receiving castbar already
    -- snaps once in its layout path; rounding here first can discard roughly
    -- half a pixel at fractional effective scales and makes its right edge
    -- consistently stop short. UUF likewise applies the container width once.
    return w * sourceScale / targetScale
end

local function ScaledValue(sourceFrame, targetFrame, value)
    value = tonumber(value) or 0
    local sourceScale = (sourceFrame and sourceFrame.GetEffectiveScale and sourceFrame:GetEffectiveScale()) or 1
    local targetScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
    if sourceScale <= 0 then sourceScale = 1 end
    if targetScale <= 0 then targetScale = 1 end
    return value * sourceScale / targetScale
end

-- The 6.0 unitframe's normal border is rendered outside the health/frame
-- rectangle. Use only the stable normal border here; temporary aggro/dispel
-- highlights must never resize attached castbars during combat.
local function UnitframeNormalBorderInset(frame, sourceFrame)
    if not frame then return 0 end
    local outline = frame._msufBarOutline
    if outline and outline.frame == sourceFrame then return 0 end

    local enabled = frame._msufBorderRuntimeNormal == true
    local thickness = tonumber(frame._msufBorderRuntimeNormalThickness)
    if not enabled then
        local border = frame.MSUFSpec and frame.MSUFSpec.border
        enabled = border and border.enabled == true
        thickness = tonumber(border and border.thickness)
    end
    if not enabled or not thickness or thickness <= 0 then return 0 end
    return thickness
end

-- Normal borders are configured in unitframe units, except for boss frames
-- whose corrected geometry rounds the setting to an exact physical-pixel
-- count. Express that visible inset in the receiving castbar's units.
local function UnitframeNormalBorderInsetForTarget(frame, sourceFrame, targetFrame)
    local inset = UnitframeNormalBorderInset(frame, sourceFrame)
    if inset <= 0 then return 0 end

    if frame and frame._msufBossPhysicalGeometryApplied == true
        and type(_G.MSUF_GetPhysicalPixelSize) == "function"
    then
        -- Mirror the boss border's own conversion: the setting is a unitframe-unit
        -- value, so it becomes a physical-pixel count through the unitframe's
        -- scale, not one pixel per configured unit.
        local framePixel = _G.MSUF_GetPhysicalPixelSize(frame, 1)
        local pixels = inset
        if type(framePixel) == "number" and framePixel > 0 then
            pixels = inset / framePixel
        end
        pixels = math.floor(pixels + 0.5)
        if pixels < 1 then pixels = 1 end
        return _G.MSUF_GetPhysicalPixelSize(targetFrame, pixels)
    end

    return ScaledValue(sourceFrame or frame, targetFrame, inset)
end

local function UnitframeVisibleWidth(unit, targetFrame)
    local frame = GetUnitframe(unit)
    local source = GetUnitframeWidthSource(unit)
    local width = ScaledWidth(source, targetFrame)
    if not width then return nil end
    local inset = UnitframeNormalBorderInsetForTarget(frame, source, targetFrame)
    return width + (inset * 2)
end

-- Cooldown Viewer container/viewer global names for a width-source kind.
local function WidthSourceNames(kind)
    if kind == "utility" then
        return "UtilityCooldownViewer_AnchorContainer", "UtilityCooldownViewer"
    elseif kind == "essential" then
        return "EssentialCooldownViewer_CDM_Container", "EssentialCooldownViewer"
    end
end

-- Resolve the effective Cooldown Viewer frame for a viewer global name.
local function EffectiveCooldownViewer(viewerKey)
    return viewerKey
        and (_G.MSUF_GetEffectiveCooldownFrame and _G.MSUF_GetEffectiveCooldownFrame(viewerKey) or _G[viewerKey])
end

local function IsUsableCooldownWidthFrame(frame)
    if not (frame and frame.GetWidth) or frame._msufLegacyCooldownAnchor == true then return false end
    if frame.IsShown and not frame:IsShown() then return false end
    local width = frame:GetWidth()
    return type(width) == "number" and width > 0
end

local function CooldownWidthSourceFrame(kind)
    local containerKey, viewerKey = WidthSourceNames(kind)
    local container = containerKey and _G[containerKey] or nil
    if IsUsableCooldownWidthFrame(container) then return container end

    local viewer = EffectiveCooldownViewer(viewerKey)
    if IsUsableCooldownWidthFrame(viewer) then return viewer end

    local rawViewer = viewerKey and _G[viewerKey] or nil
    if rawViewer ~= viewer and IsUsableCooldownWidthFrame(rawViewer) then return rawViewer end
    return nil
end

local function CooldownWidthSourceUsable(kind)
    return CooldownWidthSourceFrame(kind) ~= nil
end

local function WidthSourceRuntimeActive(kind)
    kind = NormalizeWidthSourceKind(kind)
    return kind ~= nil and (not IsCooldownWidthSourceKind(kind) or CooldownWidthSourceUsable(kind))
end

-- Effective width to apply, derived from the configured width source.
local function WidthFromSource(unit, kind, targetFrame)
    kind = NormalizeWidthSourceKind(kind)
    if kind == "unitframe" then
        return UnitframeVisibleWidth(unit, targetFrame)
    end

    return ScaledWidth(CooldownWidthSourceFrame(kind), targetFrame)
end

-- The configured (and validated) width-source kind for a unit, or nil.
local function ConfiguredWidthSource(g, unit)
    local def = UNIT_CASTBAR[NormalizeUnit(unit)]
    if not def then return nil end
    local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUse) == "function" then
        if shouldUse(NormalizeUnit(unit), g) ~= true then return nil end
    elseif g and g[def.enable] == false then
        return nil
    end
    return NormalizeWidthSourceKind(def and g and g[def.match])
end

local function UsesUnitframeWidth(g, unit)
    local normalized = NormalizeUnit(unit)
    local configured = ConfiguredWidthSource(g, normalized)
    if configured then return configured == "unitframe" end
    local def = UNIT_CASTBAR[normalized]
    local manualWidth = def and tonumber(g and g[def.w])
    return normalized ~= "player"
        and def ~= nil
        and not (g and g[def.detached] == true)
        and not (manualWidth and manualWidth > 0)
end

local function ScaledLeft(frame)
    if not frame then return nil end
    if frame.GetScaledRect then
        local left = frame:GetScaledRect()
        if type(left) == "number" then return left end
    end
    if not frame.GetLeft then return nil end
    local left = frame:GetLeft()
    if type(left) ~= "number" then return nil end
    local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    return left * scale
end

local function GetCastbarAutoAnchorOffsetX(g, unit, targetFrame)
    if not UsesUnitframeWidth(g, unit) then return 0 end

    local frame = GetUnitframe(unit)
    local source = GetUnitframeWidthSource(unit)
    if not frame or not source then return 0 end

    local frameLeft = ScaledLeft(frame)
    local sourceLeft = ScaledLeft(source)
    if not frameLeft or not sourceLeft then return 0 end

    local targetScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
    if targetScale <= 0 then targetScale = 1 end
    local inset = UnitframeNormalBorderInsetForTarget(frame, source, targetFrame)
    return ((sourceLeft - frameLeft) / targetScale) - inset
end

local function GetCastbarUnitframeBottomInset(unit, targetFrame)
    local frame = GetUnitframe(unit)
    local source = GetUnitframeWidthSource(unit)
    return UnitframeNormalBorderInsetForTarget(frame, source, targetFrame)
end

------------------------------------------------------------------------
-- Desired size
------------------------------------------------------------------------

-- Resolve the castbar (width, height) for a unit. Manual values win, then the
-- width source, then (non-player, non-detached) the unitframe width, then the
-- global castbar size, then the provided fallbacks.
function MSUF_GetCastbarDesiredSize(unit, g, bar, fallbackW, fallbackH)
    local normalized = NormalizeUnit(unit)
    local def = UNIT_CASTBAR[normalized]
    g = g or GeneralDB()

    local w = def and tonumber(g[def.w]) or nil
    local h = def and tonumber(g[def.h]) or nil
    local preserveWidth = false

    local matchSrc = ConfiguredWidthSource(g, normalized)
    if matchSrc then
        local ww = WidthFromSource(unit, matchSrc, bar)
        if ww and ww > 0 then
            w = ww
            preserveWidth = true
        end
    end

    if (not w or w <= 0)
        and normalized ~= "player"
        and not (g and def and g[def.detached] == true) then
        local ww = UnitframeVisibleWidth(unit, bar)
        if ww and ww > 0 then
            w = ww
            preserveWidth = true
        end
    end

    if not w or w <= 0 then w = tonumber(g.castbarGlobalWidth) or fallbackW or 250 end
    if not h or h <= 0 then h = tonumber(g.castbarGlobalHeight) or fallbackH or 18 end

    return w, h, preserveWidth
end

------------------------------------------------------------------------
-- Width-source signatures (skip redundant re-anchors)
------------------------------------------------------------------------

local function InvalidateWidthSourceSignature(unit)
    if unit then
        widthSourceSignatures[NormalizeUnit(unit)] = nil
    else
        for _, unitKey in ipairs(CASTBAR_UNITS) do
            widthSourceSignatures[unitKey] = nil
        end
    end
end

-- Store one frame's compact geometry in a reused numeric array. Returns the
-- next free index and whether this slice changed.
local function StoreFrameSignature(state, offset, frame)
    local w, h, scale, shown = 0, 0, 1, 0
    if frame then
        w = (frame.GetWidth and frame:GetWidth()) or 0
        h = (frame.GetHeight and frame:GetHeight()) or 0
        scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
        shown = (frame.IsShown and frame:IsShown()) and 1 or 0
    end
    w = Round(w * 100)
    h = Round(h * 100)
    scale = Round(scale * 1000)

    local changed = state[offset] ~= frame
        or state[offset + 1] ~= w
        or state[offset + 2] ~= h
        or state[offset + 3] ~= scale
        or state[offset + 4] ~= shown
    state[offset] = frame
    state[offset + 1] = w
    state[offset + 2] = h
    state[offset + 3] = scale
    state[offset + 4] = shown
    return offset + 5, changed
end

-- Compare and update a unit's numeric width-source snapshot.
local function WidthSourceNeedsReanchor(g, unit)
    unit = NormalizeUnit(unit)
    if not ShouldUseMSUFCastbar(unit, g) then
        widthSourceSignatures[unit] = nil
        return false
    end

    local matchSrc = ConfiguredWidthSource(g, unit)
    if not matchSrc
        or (IsCooldownWidthSourceKind(matchSrc) and not CooldownWidthSourceUsable(matchSrc)) then
        widthSourceSignatures[unit] = nil
        return false
    end

    local state = widthSourceSignatures[unit]
    if not state then
        state = {}
        widthSourceSignatures[unit] = state
    end
    local changed = state.kind ~= matchSrc
    state.kind = matchSrc
    local offset = 1

    if matchSrc == "unitframe" then
        local count = unit == "boss" and 5 or 1
        if state.count ~= count then changed = true end
        state.count = count
        for i = 1, count do
            local sourceUnit = unit == "boss" and ("boss" .. i) or unit
            local frame = GetUnitframe(sourceUnit)
            local source = GetUnitframeWidthSourceFromFrame(frame)
            local sliceChanged
            offset, sliceChanged = StoreFrameSignature(state, offset, frame)
            changed = sliceChanged or changed
            offset, sliceChanged = StoreFrameSignature(state, offset, source)
            changed = sliceChanged or changed
            local inset = Round(UnitframeNormalBorderInset(frame, source) * 100)
            if state[offset] ~= inset then changed = true end
            state[offset] = inset
            offset = offset + 1
        end
    else
        if state.count ~= 1 then changed = true end
        state.count = 1
        local sliceChanged
        offset, sliceChanged = StoreFrameSignature(state, offset, CooldownWidthSourceFrame(matchSrc))
        changed = sliceChanged or changed
    end

    local oldValueCount = state.valueCount or 0
    for i = offset, oldValueCount do
        state[i] = nil
    end
    state.valueCount = offset - 1
    return changed
end

------------------------------------------------------------------------
-- Width-source sync machinery
------------------------------------------------------------------------

local function FlushWidthSourceSync()
    widthSourceQueued = false
    if not widthSourceLifecycleActive then return end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return
    end
    local g = GeneralDB()
    for _, unit in ipairs(CASTBAR_UNITS) do
        if dirtyWidthSourceUnits[unit] then
            dirtyWidthSourceUnits[unit] = nil
            if WidthSourceNeedsReanchor(g, unit) then
                ApplyCastbarEffectiveSizeUnit(unit, g)
            end
        end
    end
end

local function MarkAllWidthSourceUnitsDirty(g)
    for _, unit in ipairs(CASTBAR_UNITS) do
        dirtyWidthSourceUnits[unit] = ConfiguredWidthSource(g, unit) and true or nil
    end
end

local function ResetWidthSourceDependencies(unit)
    unit = NormalizeUnit(unit)
    local generation = widthSourceDependencyGeneration[unit]
    if generation == nil then return nil end
    generation = generation + 1
    widthSourceDependencyGeneration[unit] = generation
    return generation
end

local function ClearWidthSourceRuntimeState()
    for _, unit in ipairs(CASTBAR_UNITS) do
        dirtyWidthSourceUnits[unit] = nil
        ResetWidthSourceDependencies(unit)
    end
end

-- Queue a one-shot, next-frame pass that re-applies the size of any unit whose
-- width source changed. Deferred during combat and deduped while queued.
local function QueueWidthSourceSync()
    if not widthSourceLifecycleActive then return end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        widthSourceQueued = false
        return
    end
    if widthSourceQueued then return end
    widthSourceQueued = true

    local runNext = _G.MSUF_Castbars_RunNextFrame
    if type(runNext) == "function" then
        runNext(FlushWidthSourceSync)
    else
        _G.C_Timer.After(0, FlushWidthSourceSync)
    end
end

-- Hook a source frame so size/show/hide changes re-queue a sync. Returns true
-- if the frame was newly hooked (or already valid).
local function HookWidthSourceFrame(frame, unit, generation)
    if not (frame and frame.HookScript) then
        return false
    end
    unit = NormalizeUnit(unit)
    generation = generation or widthSourceDependencyGeneration[unit]
    if generation == nil then return false end
    local dependents = widthSourceFrameDependents[frame]
    if not dependents then
        dependents = {}
        widthSourceFrameDependents[frame] = dependents
    end
    dependents[unit] = generation
    if hookedWidthSourceFrames[frame] then return true end
    if InCombat() and frame.IsProtected and frame:IsProtected() then
        return false
    end
    hookedWidthSourceFrames[frame] = true
    local function QueueIfActive()
        if not widthSourceLifecycleActive then return end
        local current = widthSourceFrameDependents[frame]
        local anyDirty = false
        if current then
            for dependentUnit, dependencyGeneration in pairs(current) do
                if widthSourceDependencyGeneration[dependentUnit] == dependencyGeneration then
                    dirtyWidthSourceUnits[dependentUnit] = true
                    anyDirty = true
                end
            end
        end
        if anyDirty then QueueWidthSourceSync() end
    end
    frame:HookScript("OnSizeChanged", QueueIfActive)
    frame:HookScript("OnShow", QueueIfActive)
    frame:HookScript("OnHide", QueueIfActive)
    return true
end

-- Ensure all source frames for a unit's configured width source are hooked.
-- Returns true if at least one source frame currently exists.
local function EnsureWidthSourceHooks(g, unit)
    unit = NormalizeUnit(unit)
    local generation = ResetWidthSourceDependencies(unit)
    if not generation then return false end
    local matchSrc = ConfiguredWidthSource(g, unit)
    if not matchSrc then return false end

    if matchSrc == "unitframe" then
        local found = false
        local count = unit == "boss" and 5 or 1
        for i = 1, count do
            local sourceUnit = unit == "boss" and ("boss" .. i) or unit
            local frame = GetUnitframe(sourceUnit)
            found = HookWidthSourceFrame(frame, unit, generation) or found
            found = HookWidthSourceFrame(GetUnitframeWidthSourceFromFrame(frame), unit, generation) or found
        end
        return found
    end

    if IsCooldownWidthSourceKind(matchSrc) then
        return CooldownWidthSourceUsable(matchSrc)
    end

    local containerKey, viewerKey = WidthSourceNames(matchSrc)
    local found = HookWidthSourceFrame(_G[containerKey], unit, generation)
    local viewer = EffectiveCooldownViewer(viewerKey)
    found = HookWidthSourceFrame(viewer, unit, generation) or found
    if viewerKey and _G[viewerKey] ~= viewer then
        found = HookWidthSourceFrame(_G[viewerKey], unit, generation) or found
    end
    return found
end

-- One backoff step of the hook-install retry loop. Stops when no unit needs a
-- width source, or once every active source has been hooked (then syncs once).
local function WidthSourceRetryStep()
    local generation = widthSourceRetryGeneration
    if not widthSourceLifecycleActive then
        widthSourceRetryActive = false
        return
    end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        widthSourceRetryActive = false
        return
    end
    widthSourceRetryIndex = widthSourceRetryIndex + 1

    local g = GeneralDB()
    local anyMissing = false
    local anyActive = false
    for _, unit in ipairs(CASTBAR_UNITS) do
        local source = ConfiguredWidthSource(g, unit)
        if source then
            anyActive = WidthSourceRuntimeActive(source) or anyActive
            if not EnsureWidthSourceHooks(g, unit) and not IsCooldownWidthSourceKind(source) then
                anyMissing = true
            end
        end
    end

    if not anyActive then
        widthSourceRetryActive = false
        return
    end
    if not anyMissing then
        widthSourceRetryActive = false
        MarkAllWidthSourceUnitsDirty(g)
        QueueWidthSourceSync()
        return
    end

    local delay = WIDTH_SOURCE_RETRY_DELAYS[widthSourceRetryIndex]
    if delay then
        _G.C_Timer.After(delay, function()
            if generation == widthSourceRetryGeneration then WidthSourceRetryStep() end
        end)
    else
        widthSourceRetryActive = false
    end
end

local function StartWidthSourceRetry()
    if not widthSourceLifecycleActive then return end
    if widthSourceRetryActive then return end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return
    end
    widthSourceRetryActive = true
    widthSourceRetryIndex = 0
    local generation = widthSourceRetryGeneration
    _G.C_Timer.After(0, function()
        if generation == widthSourceRetryGeneration then WidthSourceRetryStep() end
    end)
end

-- Public entry: refresh width-source hooks (and optionally re-anchor) for a unit
-- or, when unit is nil, all units. keepSignature avoids clearing cached sigs.
function MSUF_UpdateCastbarWidthSourceSync(g, unit, keepSignature)
    g = g or GeneralDB()
    -- Cooldown-kind castbars share the central source observer instead of
    -- installing duplicate hooks. Its generation fastpath makes unchanged
    -- castbar applies O(1), while profile/import changes still activate the
    -- newly selected viewer immediately.
    if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
        _G.MSUF_EnsureCooldownWidthObservers()
    end
    if SyncWidthSourceLifecycle and not SyncWidthSourceLifecycle(g) then
        InvalidateWidthSourceSignature(unit)
        return
    end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return
    end
    if not keepSignature then
        InvalidateWidthSourceSignature(unit)
    end

    if unit then
        local source = ConfiguredWidthSource(g, unit)
        if not source then
            ResetWidthSourceDependencies(unit)
            return
        end
        if not EnsureWidthSourceHooks(g, unit) and not IsCooldownWidthSourceKind(source) then
            StartWidthSourceRetry()
        end
        if WidthSourceNeedsReanchor(g, unit) then
            ApplyCastbarEffectiveSizeUnit(unit, g)
        end
        return
    end

    local anyActive = false
    for _, unitKey in ipairs(CASTBAR_UNITS) do
        local source = ConfiguredWidthSource(g, unitKey)
        if source then
            anyActive = WidthSourceRuntimeActive(source) or anyActive
            if not EnsureWidthSourceHooks(g, unitKey) and not IsCooldownWidthSourceKind(source) then
                StartWidthSourceRetry()
            end
        else
            ResetWidthSourceDependencies(unitKey)
        end
    end
    if anyActive then
        MarkAllWidthSourceUnitsDirty(g)
        QueueWidthSourceSync()
    end
end

-- Re-run width-source sync after login / leaving combat.
do
    widthSourceBoot = CreateFrame("Frame")
    widthSourceBoot:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon ~= "Blizzard_CooldownViewer" and addon ~= "Blizzard_EditMode" then
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            if not widthSourcePendingAfterCombat and not widthSourceQueued then
                return
            end
        elseif InCombat() then
            widthSourcePendingAfterCombat = true
            return
        end
        widthSourcePendingAfterCombat = false
        local g = GeneralDB()
        MSUF_UpdateCastbarWidthSourceSync(g, nil, true)
        QueueWidthSourceSync()
    end)

    SyncWidthSourceLifecycle = function(g)
        g = g or GeneralDB()
        local wanted = false
        for i = 1, #CASTBAR_UNITS do
            if ConfiguredWidthSource(g, CASTBAR_UNITS[i]) then
                wanted = true
                break
            end
        end
        if widthSourceLifecycleActive == wanted then return wanted end
        widthSourceLifecycleActive = wanted
        widthSourceRetryGeneration = widthSourceRetryGeneration + 1
        widthSourceRetryActive = false
        widthSourceQueued = false
        widthSourcePendingAfterCombat = false
        if not wanted then ClearWidthSourceRuntimeState() end
        widthSourceBoot:UnregisterAllEvents()
        if wanted then
            widthSourceBoot:RegisterEvent("PLAYER_ENTERING_WORLD")
            widthSourceBoot:RegisterEvent("PLAYER_REGEN_ENABLED")
            widthSourceBoot:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
            widthSourceBoot:RegisterEvent("ADDON_LOADED")
        end
        return wanted
    end
    SyncWidthSourceLifecycle(GeneralDB())
end

------------------------------------------------------------------------
-- Player castbar icon + statusbar layout
------------------------------------------------------------------------

-- Lays out the cast icon and inner statusBar for player-style castbars.
function MSUF_ApplyPlayerCastbarIconLayout(bar, g, topInset, bottomInset)
    if not (bar and g and bar.statusBar) then return end
    local statusBar = bar.statusBar
    topInset = tonumber(topInset) or 0
    bottomInset = tonumber(bottomInset) or 0
    local height = (bar.GetHeight and bar:GetHeight()) or 18

    -- Global + per-player icon visibility (forced on while in Edit Mode so it
    -- can still be positioned).
    local showIcon = g.castbarShowIcon ~= false
    if g.castbarPlayerShowIcon ~= nil then
        showIcon = g.castbarPlayerShowIcon ~= false
    end
    local isPlayerBar = bar == _G.MSUF_PlayerCastbar
        or bar == _G.MSUF_PlayerCastbarPreview
        or bar == _G.PlayerCastingBarFrame
        or bar == _G.CastingBarFrame
    if isPlayerBar
        and (_G.MSUF_UnitEditModeActive == true
            or (EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown())) then
        showIcon = true
    end

    local iconOffsetX = tonumber(g.castbarPlayerIconOffsetX)
    if iconOffsetX == nil then iconOffsetX = tonumber(g.castbarIconOffsetX) or 0 end
    local iconOffsetY = tonumber(g.castbarPlayerIconOffsetY)
    if iconOffsetY == nil then iconOffsetY = tonumber(g.castbarIconOffsetY) or 0 end

    local iconSize = tonumber(g.castbarPlayerIconSize) or tonumber(g.castbarIconSize) or height
    if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end
    local iconZoom = tonumber(g.castbarPlayerIconZoom) or tonumber(g.castbarIconZoom) or 100
    if iconZoom < 100 then iconZoom = 100 elseif iconZoom > 200 then iconZoom = 200 end

    local icon = bar.Icon or bar.icon or (bar.IconFrame and bar.IconFrame.Icon)
    local iconDetached = (iconOffsetX ~= 0) -- detach only on X

    if icon then
        if showIcon then
            icon:Show()
            local host = bar._msufPCIconHost
            if not host then
                host = CreateFrame("Frame", nil, bar)
                host:EnableMouse(false)
                bar._msufPCIconHost = host
            end
            host:SetSize(iconSize, iconSize)
            host:ClearAllPoints()
            host:SetPoint("LEFT", bar, "LEFT", iconOffsetX, iconOffsetY)
            if statusBar.GetFrameLevel and host.SetFrameLevel then
                local resolveIconLevel = _G.MSUF_ResolveCastbarIconFrameLevel
                local unitFromFrame = _G.MSUF_GetCastbarUnitFromFrame
                local manualIconLevel = type(resolveIconLevel) == "function"
                    and resolveIconLevel(type(unitFromFrame) == "function" and unitFromFrame(bar) or "player", g)
                    or nil
                host:SetFrameLevel(manualIconLevel or ((statusBar:GetFrameLevel() or 0) + 3))
            end
            host:Show()

            local key = "H:" .. (iconDetached and "D" or "A") .. ":" .. iconSize .. ":" .. iconZoom .. ":" .. iconOffsetX .. ":" .. iconOffsetY
            if icon._msufPCIconKey ~= key or (icon.GetParent and icon:GetParent() ~= host) then
                icon:SetParent(host)
                icon:ClearAllPoints()
                icon:SetAllPoints(host)
                if icon.SetDrawLayer then
                    icon:SetDrawLayer("OVERLAY", 7) -- above bar texture, below texts
                end
                if icon.SetTexCoord then
                    local visible = 100 / iconZoom
                    local inset = (1 - visible) * 0.5
                    icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
                end
                icon._msufPCIconKey = key
            end
        else
            icon:Hide()
            if bar._msufPCIconHost then bar._msufPCIconHost:Hide() end
        end
    elseif bar._msufPCIconHost then
        bar._msufPCIconHost:Hide()
    end

    -- StatusBar anchoring (only re-anchor when the layout state changes).
    local frameInset = CastbarFrameInset(bar, g)
    if frameInset <= 0 then
        topInset = 0
        bottomInset = 0
    end
    local layoutKey = "I" .. frameInset .. ":" .. ((showIcon and icon and not iconDetached) and ("G:" .. iconSize) or "F")
    if statusBar._msufPCLayoutKey ~= layoutKey then
        statusBar:ClearAllPoints()
        if showIcon and icon and not iconDetached then
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", iconSize + 1, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -frameInset, bottomInset)
        else
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", frameInset, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -frameInset, bottomInset)
        end
        statusBar._msufPCLayoutKey = layoutKey
    end

    -- Explicit StatusBar sizing: point-anchoring alone can leave the bar in a
    -- "border-only" state until the next frame. Force size so the fill spans the
    -- full new width immediately (fixes black bar on CDM sync).
    local barWidth = (bar.GetWidth and bar:GetWidth()) or 250
    if barWidth <= 0 then barWidth = 250 end
    local sbWidth = (showIcon and icon and not iconDetached) and (barWidth - iconSize - 1 - frameInset) or (barWidth - (frameInset * 2))
    if sbWidth < 1 then sbWidth = 1 end
    local sbHeight = height - (frameInset * 2)
    if sbHeight < 1 then sbHeight = 1 end

    if statusBar._msufPCSbW ~= sbWidth then
        statusBar:SetWidth(sbWidth)
        statusBar._msufPCSbW = sbWidth
    end
    if statusBar._msufPCSbH ~= sbHeight then
        statusBar:SetHeight(sbHeight)
        statusBar._msufPCSbH = sbHeight
    end

    local bg = bar.backgroundBar
    if bg and bg.SetAllPoints then
        bg:ClearAllPoints()
        bg:SetAllPoints(statusBar)
    end
end

------------------------------------------------------------------------
-- Sizing helpers
------------------------------------------------------------------------

-- Apply only outer geometry and empower-tick height. Visuals owns icon/text
-- layout, while Castbars_Core owns the spark follower.
local function ApplyPlayerCastbarSizeAndLayout(bar, g, w, h, preserveWidth)
    if not bar then return end

    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
        if w ~= nil and not preserveWidth then w = snap(bar, w) end
        if h ~= nil then h = snap(bar, h) end
    end

    SetWidth(bar, w)
    SetHeight(bar, h)

    -- Empower stage ticks follow bar height.
    if bar.empowerStageTicks then
        local barH = bar:GetHeight() or h
        for _, tick in pairs(bar.empowerStageTicks) do
            if tick and tick.SetHeight then
                tick:SetHeight(barH)
            end
        end
    end

end

-- Apply the effective runtime size to a unit's castbar(s). Returns true if a
-- bar was sized. (Assigned to the forward-declared local above.)
ApplyCastbarEffectiveSizeUnit = function(unit, g)
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return false
    end
    g = g or GeneralDB()
    unit = NormalizeUnit(unit)
    if not ShouldUseMSUFCastbar(unit, g) then return false end

    -- Set the outer frame size. Returns true when a frame was present.
    local function SetOuterSize(frame, w, h)
        if not frame then return false end
        SetWidth(frame, w)
        if h and h > 0 then SetHeight(frame, h) end
        return true
    end

    if unit == "player" then
        local frame = _G.MSUF_PlayerCastbar
        local preview = _G.MSUF_PlayerCastbarPreview
        local target = frame or preview
        if not target then return false end

        local w, h, preserveWidth = MSUF_GetCastbarDesiredSize("player", g, target, 250, 18)
        if frame then ApplyPlayerCastbarSizeAndLayout(frame, g, w, h, preserveWidth) end
        if preview then ApplyPlayerCastbarSizeAndLayout(preview, g, w, h, preserveWidth) end
        return true
    end

    if unit == "target" or unit == "focus" then
        local frame = (unit == "target"
            and (_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar or ((_G.TargetCastBar and _G.TargetCastBar._msufCastbarDriver == true) and _G.TargetCastBar)))
            or (_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar))
        local preview = (unit == "target" and _G.MSUF_TargetCastbarPreview) or _G.MSUF_FocusCastbarPreview
        local target = frame or preview
        if not target then return false end

        local fallbackW = (target.GetWidth and target:GetWidth()) or 240
        local fallbackH = (target.GetHeight and target:GetHeight()) or 18
        local w, h, preserveWidth = MSUF_GetCastbarDesiredSize(unit, g, target, fallbackW, fallbackH)

        if frame and SetOuterSize(frame, w, h) and frame.statusBar then
            local barH = (frame.GetHeight and frame:GetHeight()) or h or 18
            SetWidth(frame.statusBar, math.max(1, (w or 240) - barH - 1))
        end
        if preview and type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
            _G.MSUF_ApplyPlayerCastbarSizeAndLayout(preview, g, w, h, preserveWidth)
        end
        return true
    end

    if unit == "boss" then
        local applied = false
        local maxBoss = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
        if maxBoss < 1 or maxBoss > 12 then maxBoss = 5 end
        for i = 1, maxBoss do
            local frame = (_G.MSUF_BossCastbars and _G.MSUF_BossCastbars[i]) or _G["MSUF_BossCastbar" .. i]
            if frame then
                local fallbackW = (frame.GetWidth and frame:GetWidth()) or 240
                local fallbackH = (frame.GetHeight and frame:GetHeight()) or 12
                local w, h = MSUF_GetCastbarDesiredSize("boss" .. i, g, frame, fallbackW, fallbackH)
                if SetOuterSize(frame, w, h) then
                    applied = true
                    if frame.ApplyLayout then frame:ApplyLayout() end
                end
            end
        end
        if _G.MSUF_UnitEditModeActive == true and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
            applied = true
        end
        return applied
    end

    return false
end

-- Shared Cooldown Viewer observers call this after coalescing a real source
-- transition. Refresh only castbars configured for that exact viewer; this
-- also applies the manual fallback immediately when the viewer becomes hidden.
local function RefreshCastbarCooldownWidthSource(sourceName)
    local kind = COOLDOWN_VIEWER_KINDS[sourceName]
    if not kind then return false end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return false
    end

    local g = GeneralDB()
    local applied = false
    for i = 1, #CASTBAR_UNITS do
        local unit = CASTBAR_UNITS[i]
        if ConfiguredWidthSource(g, unit) == kind then
            applied = ApplyCastbarEffectiveSizeUnit(unit, g) or applied
            WidthSourceNeedsReanchor(g, unit)
        end
    end
    return applied
end

------------------------------------------------------------------------
-- Re-anchor entry points
------------------------------------------------------------------------

-- Hide a castbar (and its preview) when the unit's MSUF castbar is disabled.
local function HideCastbar(frame, preview)
    if frame then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText and _G.MSUF_IsCastTimeEnabled(frame) then
            _G.MSUF_SetTextIfChanged(frame.timeText, "")
        end
        if frame.latencyBar then frame.latencyBar:Hide() end
        frame:Hide()
    end
    if preview then preview:Hide() end
end

-- Shared re-anchor for the Target and Focus castbars.
local function ReanchorTargetOrFocusCastbarBase(unit)
    EnsureDB()
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local frame = (unit == "target"
        and (_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar or ((_G.TargetCastBar and _G.TargetCastBar._msufCastbarDriver == true) and _G.TargetCastBar)))
        or (_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar))
    local preview = (unit == "target" and _G.MSUF_TargetCastbarPreview) or _G.MSUF_FocusCastbarPreview
    if not frame then return end

    if not ShouldUseMSUFCastbar(unit, g) then
        HideCastbar(frame, preview)
        return
    end

    local def = UNIT_CASTBAR[unit]
    local anchorFrame = GetUnitframe(unit)
    local offsetX = Round(tonumber(g[def.x]) or (unit == "focus" and tonumber(g.castbarTargetOffsetX)) or def.dx)
    local offsetY = Round(tonumber(g[def.y]) or (unit == "focus" and tonumber(g.castbarTargetOffsetY)) or def.dy)

    if g[def.detached] then
        SetPoint(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not anchorFrame then return end
        SetPoint(frame, "BOTTOMLEFT", anchorFrame, "TOPLEFT",
            offsetX + GetCastbarAutoAnchorOffsetX(g, unit, frame), offsetY)
    end

    MSUF_UpdateCastbarWidthSourceSync(g, unit, true)
    local width, desiredHeight, preserveWidth = MSUF_GetCastbarDesiredSize(unit, g, frame,
        (frame.GetWidth and frame:GetWidth()) or 240,
        (frame.GetHeight and frame:GetHeight()) or 18)

    local snap = _G.MSUF_Snap
    if not preserveWidth and type(snap) == "function" then width = snap(frame, width) end
    SetWidth(frame, width)
    SetHeight(frame, desiredHeight)
    if preview and type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarSizeAndLayout(preview, g, width, desiredHeight, preserveWidth)
    end

    local positionPreview = unit == "target" and _G.MSUF_PositionTargetCastbarPreview or _G.MSUF_PositionFocusCastbarPreview
    if preview and positionPreview then positionPreview() end
    return frame, preview, g
end

local function RefreshCastbarVisualFollowers(frame, unit, general)
    if not frame then return end
    local refreshFrame = _G.MSUF_RefreshCastbarFrame
    if type(refreshFrame) == "function" then
        refreshFrame(frame)
    elseif type(_G.MSUF_ApplyCastbarDetailLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailLayout(frame, unit)
    end
    local applySpark = _G.MSUF_ApplyCastbarSparkVisual
    if type(applySpark) == "function" then applySpark(frame, general) end
end

local function ReanchorTargetCastBarBase()
    return ReanchorTargetOrFocusCastbarBase("target")
end

local function ReanchorFocusCastBarBase()
    return ReanchorTargetOrFocusCastbarBase("focus")
end

function MSUF_ReanchorTargetCastBar()
    local frame, preview, general = ReanchorTargetCastBarBase()
    RefreshCastbarVisualFollowers(frame, "target", general)
    RefreshCastbarVisualFollowers(preview, "target", general)
end

function MSUF_ReanchorFocusCastBar()
    local frame, preview, general = ReanchorFocusCastBarBase()
    RefreshCastbarVisualFollowers(frame, "focus", general)
    RefreshCastbarVisualFollowers(preview, "focus", general)
end

local function ReanchorPlayerCastBarBase()
    EnsureDB()
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}

    if not (_G.MSUF_ShouldUseBlizzardCastbar and _G.MSUF_ShouldUseBlizzardCastbar("player", g))
        and _G.MSUF_HideBlizzardPlayerCastbar then
        _G.MSUF_HideBlizzardPlayerCastbar()
    end

    if not ShouldUseMSUFCastbar("player", g) then
        local applyPlayerState = _G.MSUF_PlayerCastbar_ApplyBackendState
        if type(applyPlayerState) == "function" then applyPlayerState() end
        HideCastbar(_G.MSUF_PlayerCastbar, _G.MSUF_PlayerCastbarPreview)
        return
    end

    local applyPlayerState = _G.MSUF_PlayerCastbar_ApplyBackendState
    if type(applyPlayerState) == "function" then
        applyPlayerState()
    else
        MSUF_InitSafePlayerCastbar()
    end

    local anchorFrame = GetUnitframe("player")
    if not _G.MSUF_PlayerCastbar or (not g.castbarPlayerDetached and not anchorFrame) then
        return
    end

    local offsetX = Round(g.castbarPlayerOffsetX or 0)
    local offsetY = Round(g.castbarPlayerOffsetY or 5)
    if g.castbarPlayerDetached then
        SetPoint(_G.MSUF_PlayerCastbar, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        SetPoint(_G.MSUF_PlayerCastbar, "BOTTOM", anchorFrame, "TOP", offsetX, offsetY)
    end

    MSUF_UpdateCastbarWidthSourceSync(g, "player", true)
    local width, height, preserveWidth = MSUF_GetCastbarDesiredSize("player", g, _G.MSUF_PlayerCastbar, 250, 18)
    ApplyPlayerCastbarSizeAndLayout(_G.MSUF_PlayerCastbar, g, width, height, preserveWidth)

    -- Keep the preview size 1:1 with the real bar (show/hide handled elsewhere).
    if _G.MSUF_PlayerCastbarPreview then
        ApplyPlayerCastbarSizeAndLayout(_G.MSUF_PlayerCastbarPreview, g, width, height, preserveWidth)
    end
    if _G.MSUF_PlayerCastbarPreview and _G.MSUF_PositionPlayerCastbarPreview then
        _G.MSUF_PositionPlayerCastbarPreview()
    end
    return _G.MSUF_PlayerCastbar, _G.MSUF_PlayerCastbarPreview, g
end

function MSUF_ReanchorPlayerCastBar()
    local frame, preview, general = ReanchorPlayerCastBarBase()
    RefreshCastbarVisualFollowers(frame, "player", general)
    RefreshCastbarVisualFollowers(preview, "player", general)
end

MSUF_PlayerCastbarManageHooked = true -- Blizzard fallback removed; nothing to manage here.

function MSUF_ReanchorBossCastBar()
    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
        _G.MSUF_ApplyBossCastbarPositionSetting(false, true)
    end
    if not InCombat() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    if type(MSUF_SyncBossCastbarSliders) == "function" then
        MSUF_SyncBossCastbarSliders()
    end
    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup("boss")
    end
end

------------------------------------------------------------------------
-- _G exports
------------------------------------------------------------------------
ExportPublic("MSUF_ReanchorTargetCastBar", MSUF_ReanchorTargetCastBar)
ExportPublic("MSUF_ReanchorFocusCastBar", MSUF_ReanchorFocusCastBar)
ExportPublic("MSUF_ReanchorTargetCastBarBase", ReanchorTargetCastBarBase)
ExportPublic("MSUF_ReanchorFocusCastBarBase", ReanchorFocusCastBarBase)
ExportPublic("MSUF_NormalizeCastbarWidthSource", NormalizeWidthSourceKind)
ExportPublic("MSUF_NormalizePlayerCastbarWidthSource", NormalizeWidthSourceKind)
ExportPublic("MSUF_GetCastbarWidthSourceKey", function(unit)
    local def = UNIT_CASTBAR[NormalizeUnit(unit)]
    return def and def.match
end)
ExportPublic("MSUF_GetCastbarUnitframeWidthSource", GetUnitframeWidthSource)
ExportPublic("MSUF_GetCastbarAutoAnchorOffsetX", GetCastbarAutoAnchorOffsetX)
ExportPublic("MSUF_GetCastbarUnitframeBottomInset", GetCastbarUnitframeBottomInset)
ExportPublic("MSUF_GetCastbarDesiredSize", MSUF_GetCastbarDesiredSize)
ExportPublic("MSUF_UpdateCastbarWidthSourceSync", MSUF_UpdateCastbarWidthSourceSync)
ExportPublic("MSUF_ApplyCastbarEffectiveSizeUnit", ApplyCastbarEffectiveSizeUnit)
ExportPublic("MSUF_RefreshCastbarCooldownWidthSource", RefreshCastbarCooldownWidthSource)
ExportPublic("MSUF_GetPlayerCastbarDesiredSize", function(g, bar, fallbackW, fallbackH)
    return MSUF_GetCastbarDesiredSize("player", g, bar, fallbackW, fallbackH)
end)
ExportPublic("MSUF_ApplyPlayerCastbarSizeAndLayout", ApplyPlayerCastbarSizeAndLayout)
ExportPublic("MSUF_ApplyPlayerCastbarIconLayout", MSUF_ApplyPlayerCastbarIconLayout)
ExportPublic("MSUF_ReanchorPlayerCastBar", MSUF_ReanchorPlayerCastBar)
ExportPublic("MSUF_ReanchorPlayerCastBarBase", ReanchorPlayerCastBarBase)
ExportPublic("MSUF_ReanchorBossCastBar", MSUF_ReanchorBossCastBar)
