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
local floor = math.floor
local ceil = math.ceil
local type = type
local tonumber = tonumber
local tostring = tostring

-- Cached _G.MSUF_UnitFrames table (refreshed lazily; may be nil early at login).
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

-- Units that participate in width-source sync.
local CASTBAR_UNITS = { "player", "target", "focus", "boss" }

-- Backoff delays (seconds) for retrying width-source hook installation at login.
local WIDTH_SOURCE_RETRY_DELAYS = { 0.05, 0.15, 0.35, 0.75, 1.5, 3.0, 5.0, 7.0 }

-- Frames already hooked for width-source change notifications (weak keys).
local hookedWidthSourceFrames = setmetatable({}, { __mode = "k" })

-- Per-unit signature of the current width source, used to skip redundant work.
local widthSourceSignatures = {}

-- Sync state machine flags.
local widthSourceQueued = false             -- a next-frame flush is queued
local widthSourcePendingAfterCombat = false -- work was deferred due to combat
local widthSourceRetryActive = false        -- the hook-install retry loop is running
local widthSourceRetryIndex = 0             -- index into WIDTH_SOURCE_RETRY_DELAYS

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

local function GetUnitFrames()
    unitFramesCache = _G.MSUF_UnitFrames or unitFramesCache or _G.UnitFrames
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

local function SetAlpha(frame, alpha)
    if _G.MSUF_SetAlphaIfChanged then
        _G.MSUF_SetAlphaIfChanged(frame, alpha)
    else
        frame:SetAlpha(alpha)
    end
end

------------------------------------------------------------------------
-- Frame lookups
------------------------------------------------------------------------

-- The MSUF unitframe object for a unit (handles boss1..boss5 indexing).
local function GetUnitframe(unit)
    local frames = GetUnitFrames()
    unit = tostring(unit or "")
    local index = tonumber(unit:match("^boss(%d+)$")) or 1
    if NormalizeUnit(unit) == "boss" then
        return (frames and frames["boss" .. index])
            or _G["MSUF_boss" .. index]
            or (frames and frames.boss1)
            or _G.MSUF_boss1
    end
    return (frames and frames[unit]) or _G["MSUF_" .. unit]
end

-- The visible health bar of a unitframe (preferred width source), or the frame
-- itself. Matching the bar rather than the outer container avoids reading a few
-- pixels too wide in "MSUF Unit Frame" width mode.
local function GetUnitframeWidthSource(unit)
    local frame = GetUnitframe(unit)
    if not frame then return nil end
    local hp = frame.hpBar or frame.healthBar or frame.health
    if hp and hp.GetWidth and (hp:GetWidth() or 0) > 0 then
        return hp
    end
    return frame
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
    return Round(sourceScale == targetScale and w or w * sourceScale / targetScale)
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

-- Effective width to apply, derived from the configured width source.
local function WidthFromSource(unit, kind, targetFrame)
    kind = NormalizeWidthSourceKind(kind)
    if kind == "unitframe" then
        return ScaledWidth(GetUnitframeWidthSource(unit), targetFrame)
    end

    local containerKey, viewerKey = WidthSourceNames(kind)
    local w = ScaledWidth(_G[containerKey], targetFrame)
    if not w then
        w = ScaledWidth(EffectiveCooldownViewer(viewerKey), targetFrame)
    end
    if not w and viewerKey and _G[viewerKey] ~= EffectiveCooldownViewer(viewerKey) then
        w = ScaledWidth(_G[viewerKey], targetFrame)
    end
    return w
end

-- The configured (and validated) width-source kind for a unit, or nil.
local function ConfiguredWidthSource(g, unit)
    local def = UNIT_CASTBAR[NormalizeUnit(unit)]
    return NormalizeWidthSourceKind(def and g and g[def.match])
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

    local matchSrc = ConfiguredWidthSource(g, normalized)
    if matchSrc then
        local ww = WidthFromSource(unit, matchSrc, bar)
        if ww and ww > 0 then w = ww end
    end

    if (not w or w <= 0)
        and normalized ~= "player"
        and not (g and def and g[def.detached] == true) then
        local ww = ScaledWidth(GetUnitframeWidthSource(unit), bar)
        if ww and ww > 0 then w = ww end
    end

    if not w or w <= 0 then w = tonumber(g.castbarGlobalWidth) or fallbackW or 250 end
    if not h or h <= 0 then h = tonumber(g.castbarGlobalHeight) or fallbackH or 18 end

    return w, h
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

-- A compact, comparable signature of a frame's geometry/visibility.
local function FrameSignature(frame)
    if not frame then return "nil" end
    local w = (frame.GetWidth and frame:GetWidth()) or 0
    local h = (frame.GetHeight and frame:GetHeight()) or 0
    local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local shown = (frame.IsShown and frame:IsShown()) and 1 or 0
    return tostring(Round(w * 100)) .. ":"
        .. tostring(Round(h * 100)) .. ":"
        .. tostring(Round(scale * 1000)) .. ":"
        .. tostring(shown)
end

-- Build the width-source signature for a unit (nil if no active source).
local function WidthSourceSignature(g, unit)
    unit = NormalizeUnit(unit)
    if not ShouldUseMSUFCastbar(unit, g) then return nil end

    local matchSrc = ConfiguredWidthSource(g, unit)
    if not matchSrc then return nil end

    if matchSrc == "unitframe" then
        local count = unit == "boss" and 5 or 1
        local sig = matchSrc
        for i = 1, count do
            local sourceUnit = unit == "boss" and ("boss" .. i) or unit
            sig = sig
                .. "|" .. sourceUnit
                .. "=" .. FrameSignature(GetUnitframe(sourceUnit))
                .. "/" .. FrameSignature(GetUnitframeWidthSource(sourceUnit))
        end
        return sig
    end

    local containerKey, viewerKey = WidthSourceNames(matchSrc)
    local container = containerKey and _G[containerKey] or nil
    local viewer = EffectiveCooldownViewer(viewerKey)
    local rawViewer = viewerKey and _G[viewerKey] or nil
    return matchSrc
        .. "|c=" .. FrameSignature(container)
        .. "|v=" .. FrameSignature(viewer)
        .. "|g=" .. FrameSignature(rawViewer)
end

-- True (and stores the new signature) when the width source changed since last.
local function WidthSourceNeedsReanchor(g, unit)
    unit = NormalizeUnit(unit)
    local sig = WidthSourceSignature(g, unit)
    if not sig then
        widthSourceSignatures[unit] = nil
        return false
    end
    if widthSourceSignatures[unit] == sig then
        return false
    end
    widthSourceSignatures[unit] = sig
    return true
end

------------------------------------------------------------------------
-- Width-source sync machinery
------------------------------------------------------------------------

-- Queue a one-shot, next-frame pass that re-applies the size of any unit whose
-- width source changed. Deferred during combat and deduped while queued.
local function QueueWidthSourceSync()
    if InCombat() then
        widthSourcePendingAfterCombat = true
        widthSourceQueued = false
        return
    end
    if widthSourceQueued then return end
    widthSourceQueued = true

    local flush = function()
        widthSourceQueued = false
        if InCombat() then
            widthSourcePendingAfterCombat = true
            return
        end
        local g = GeneralDB()
        for _, unit in ipairs(CASTBAR_UNITS) do
            if WidthSourceNeedsReanchor(g, unit) then
                ApplyCastbarEffectiveSizeUnit(unit, g)
            end
        end
    end

    local runNext = _G.MSUF_Castbars_RunNextFrame
    if type(runNext) == "function" then
        runNext(flush)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, flush)
    else
        flush()
    end
end

-- Hook a source frame so size/show/hide changes re-queue a sync. Returns true
-- if the frame was newly hooked (or already valid).
local function HookWidthSourceFrame(frame)
    if not (frame and frame.HookScript) or hookedWidthSourceFrames[frame] then
        return false
    end
    hookedWidthSourceFrames[frame] = true
    frame:HookScript("OnSizeChanged", QueueWidthSourceSync)
    frame:HookScript("OnShow", QueueWidthSourceSync)
    frame:HookScript("OnHide", QueueWidthSourceSync)
    return true
end

-- Ensure all source frames for a unit's configured width source are hooked.
-- Returns true if at least one source frame currently exists.
local function EnsureWidthSourceHooks(g, unit)
    local matchSrc = ConfiguredWidthSource(g, unit)
    if not matchSrc then return false end

    if matchSrc == "unitframe" then
        local found = false
        local count = NormalizeUnit(unit) == "boss" and 5 or 1
        for i = 1, count do
            local sourceUnit = NormalizeUnit(unit) == "boss" and ("boss" .. i) or unit
            found = HookWidthSourceFrame(GetUnitframe(sourceUnit)) or found
            found = HookWidthSourceFrame(GetUnitframeWidthSource(sourceUnit)) or found
        end
        return found
    end

    local containerKey, viewerKey = WidthSourceNames(matchSrc)
    local found = HookWidthSourceFrame(_G[containerKey])
    local viewer = EffectiveCooldownViewer(viewerKey)
    found = HookWidthSourceFrame(viewer) or found
    if viewerKey and _G[viewerKey] ~= viewer then
        found = HookWidthSourceFrame(_G[viewerKey]) or found
    end
    return found
end

-- One backoff step of the hook-install retry loop. Stops when no unit needs a
-- width source, or once every active source has been hooked (then syncs once).
local function WidthSourceRetryStep()
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
        if ConfiguredWidthSource(g, unit) then
            anyActive = true
            if not EnsureWidthSourceHooks(g, unit) then
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
        QueueWidthSourceSync()
        return
    end

    local delay = WIDTH_SOURCE_RETRY_DELAYS[widthSourceRetryIndex]
    if delay and _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(delay, WidthSourceRetryStep)
    else
        widthSourceRetryActive = false
    end
end

local function StartWidthSourceRetry()
    if widthSourceRetryActive or not (_G.C_Timer and _G.C_Timer.After) then return end
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return
    end
    widthSourceRetryActive = true
    widthSourceRetryIndex = 0
    _G.C_Timer.After(0, WidthSourceRetryStep)
end

-- Public entry: refresh width-source hooks (and optionally re-anchor) for a unit
-- or, when unit is nil, all units. keepSignature avoids clearing cached sigs.
function MSUF_UpdateCastbarWidthSourceSync(g, unit, keepSignature)
    g = g or GeneralDB()
    if InCombat() then
        widthSourcePendingAfterCombat = true
        return
    end
    if not keepSignature then
        InvalidateWidthSourceSignature(unit)
    end

    if unit then
        if not ConfiguredWidthSource(g, unit) then return end
        if not EnsureWidthSourceHooks(g, unit) then
            StartWidthSourceRetry()
        end
        if WidthSourceNeedsReanchor(g, unit) then
            ApplyCastbarEffectiveSizeUnit(unit, g)
        end
        return
    end

    local anyActive = false
    for _, unitKey in ipairs(CASTBAR_UNITS) do
        if ConfiguredWidthSource(g, unitKey) then
            anyActive = true
            if not EnsureWidthSourceHooks(g, unitKey) then
                StartWidthSourceRetry()
            end
        end
    end
    if anyActive then
        QueueWidthSourceSync()
    end
end

-- Re-run width-source sync after login / leaving combat.
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:RegisterEvent("PLAYER_REGEN_ENABLED")
    boot:SetScript("OnEvent", function(_, event)
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
                host:SetFrameLevel((statusBar:GetFrameLevel() or 0) + 3)
            end
            host:Show()

            local key = "H:" .. (iconDetached and "D" or "A") .. ":" .. iconSize .. ":" .. iconOffsetX .. ":" .. iconOffsetY
            if icon._msufPCIconKey ~= key or (icon.GetParent and icon:GetParent() ~= host) then
                icon:SetParent(host)
                icon:ClearAllPoints()
                icon:SetAllPoints(host)
                if icon.SetDrawLayer then
                    icon:SetDrawLayer("OVERLAY", 7) -- above bar texture, below texts
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
    local layoutKey = (showIcon and icon and not iconDetached) and ("G:" .. iconSize) or "F"
    if statusBar._msufPCLayoutKey ~= layoutKey then
        statusBar:ClearAllPoints()
        if showIcon and icon and not iconDetached then
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", iconSize + 1, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bottomInset)
        else
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bottomInset)
        end
        statusBar._msufPCLayoutKey = layoutKey
    end

    -- Explicit StatusBar sizing: point-anchoring alone can leave the bar in a
    -- "border-only" state until the next frame. Force size so the fill spans the
    -- full new width immediately (fixes black bar on CDM sync).
    local barWidth = (bar.GetWidth and bar:GetWidth()) or 250
    if barWidth <= 0 then barWidth = 250 end
    local sbWidth = (showIcon and icon and not iconDetached) and (barWidth - iconSize - 1) or barWidth
    if sbWidth < 1 then sbWidth = 1 end
    local sbHeight = height - 2
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

-- Apply a computed (width, height) to a player-style bar, plus icon layout,
-- empower-tick heights and the optional leading-edge spark.
local function ApplyPlayerCastbarSizeAndLayout(bar, g, w, h)
    if not bar then return end

    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
        if w ~= nil then w = snap(bar, w) end
        if h ~= nil then h = snap(bar, h) end
    end

    SetWidth(bar, w)
    SetHeight(bar, h)

    if bar.statusBar then
        _G.MSUF_ApplyPlayerCastbarIconLayout(bar, g, -1, 1)
    end

    -- Empower stage ticks follow bar height.
    if bar.empowerStageTicks then
        local barH = bar:GetHeight() or h
        for _, tick in pairs(bar.empowerStageTicks) do
            if tick and tick.SetHeight then
                tick:SetHeight(barH)
            end
        end
    end

    -- Spark (leading-edge highlight) — lazy-created when first enabled.
    if bar.statusBar then
        local showSpark = g and g.castbarShowSpark == true
        local spark = bar.spark
        if showSpark and not spark then
            spark = bar.statusBar:CreateTexture(nil, "OVERLAY", nil, 6)
            spark:SetTexture(4417031)
            spark:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
            spark:SetDesaturated(true)
            spark:SetVertexColor(1, 1, 1, 1)
            spark:SetBlendMode("ADD")
            bar.spark = spark
        end
        if spark then
            if spark.SetShown then
                spark:SetShown(showSpark)
            elseif showSpark then
                spark:Show()
            else
                spark:Hide()
            end
            if showSpark then
                local overflow = (g and g.castbarSparkOverflow ~= false)
                local sparkH = overflow and math.max(4, (bar:GetHeight() or h or 18) * 2.1)
                    or (bar:GetHeight() or h or 18)
                spark:SetSize(16, sparkH)
                local fillTex = bar.statusBar:GetStatusBarTexture()
                if fillTex then
                    spark:ClearAllPoints()
                    spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
                end
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

        local w, h = MSUF_GetCastbarDesiredSize("player", g, target, 250, 18)
        if frame then ApplyPlayerCastbarSizeAndLayout(frame, g, w, h) end
        if preview then ApplyPlayerCastbarSizeAndLayout(preview, g, w, h) end
        return true
    end

    if unit == "target" or unit == "focus" then
        local frame = (unit == "target" and (_G.MSUF_TargetCastbar or _G.TargetCastBar))
            or (_G.MSUF_FocusCastbar or _G.FocusCastBar)
        local preview = (unit == "target" and _G.MSUF_TargetCastbarPreview) or _G.MSUF_FocusCastbarPreview
        local target = frame or preview
        if not target then return false end

        local fallbackW = (target.GetWidth and target:GetWidth()) or 240
        local fallbackH = (target.GetHeight and target:GetHeight()) or 18
        local w, h = MSUF_GetCastbarDesiredSize(unit, g, target, fallbackW, fallbackH)

        if frame and SetOuterSize(frame, w, h) and frame.statusBar then
            local barH = (frame.GetHeight and frame:GetHeight()) or h or 18
            SetWidth(frame.statusBar, math.max(1, (w or 240) - barH - 1))
        end
        if preview and type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
            _G.MSUF_ApplyPlayerCastbarSizeAndLayout(preview, g, w, h)
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
local function ReanchorTargetOrFocusCastbar(unit)
    EnsureDB()
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local frame = (unit == "target" and (_G.MSUF_TargetCastbar or _G.TargetCastBar))
        or (_G.MSUF_FocusCastbar or _G.FocusCastBar)
    local preview = (unit == "target" and _G.MSUF_TargetCastbarPreview) or _G.MSUF_FocusCastbarPreview
    if not frame then return end

    if not ShouldUseMSUFCastbar(unit, g) then
        HideCastbar(frame, preview)
        return
    end

    local def = UNIT_CASTBAR[unit]
    local anchorFrame = GetUnitframe(unit)
    local offsetX = Round((tonumber(g[def.x]) or (unit == "focus" and tonumber(g.castbarTargetOffsetX)) or def.dx) + 0.5)
    local offsetY = Round((tonumber(g[def.y]) or (unit == "focus" and tonumber(g.castbarTargetOffsetY)) or def.dy) + 0.5)

    if g[def.detached] then
        SetPoint(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not anchorFrame then return end
        SetPoint(frame, "BOTTOMLEFT", anchorFrame, "TOPLEFT", offsetX, offsetY)
    end

    MSUF_UpdateCastbarWidthSourceSync(g, unit, true)
    local width, desiredHeight = MSUF_GetCastbarDesiredSize(unit, g, frame,
        (frame.GetWidth and frame:GetWidth()) or 240,
        (frame.GetHeight and frame:GetHeight()) or 18)

    local snap = _G.MSUF_Snap
    if type(snap) == "function" then width = snap(frame, width) end
    local barH = (frame.GetHeight and frame:GetHeight()) or desiredHeight or 18

    SetWidth(frame, width)
    if frame.statusBar then
        SetWidth(frame.statusBar, math.max(1, width - barH - 1))
    end
    if preview and type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarSizeAndLayout(preview, g, width, desiredHeight)
    end

    local showTime = (type(_G.MSUF_IsCastTimeEnabled) == "function") and _G.MSUF_IsCastTimeEnabled(frame) or true
    if frame.timeText and frame.statusBar then
        frame.timeText:Show()
        SetAlpha(frame.timeText, showTime and 1 or 0)
        if not showTime then _G.MSUF_SetTextIfChanged(frame.timeText, "") end

        local timeX = g[unit == "target" and "castbarTargetTimeOffsetX" or "castbarFocusTimeOffsetX"]
        if timeX == nil then timeX = g.castbarPlayerTimeOffsetX or -2 end
        local timeY = g[unit == "target" and "castbarTargetTimeOffsetY" or "castbarFocusTimeOffsetY"]
        if timeY == nil then timeY = g.castbarPlayerTimeOffsetY or 0 end

        SetPoint(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", timeX, timeY)
        if _G.MSUF_SetJustifyHIfChanged then
            _G.MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
        else
            frame.timeText:SetJustifyH("RIGHT")
        end
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        _G.MSUF_ApplyCastbarTimeTextLayout(frame, unit)
    end

    local positionPreview = unit == "target" and _G.MSUF_PositionTargetCastbarPreview or _G.MSUF_PositionFocusCastbarPreview
    if preview and positionPreview then positionPreview() end
end

function MSUF_ReanchorTargetCastBar()
    ReanchorTargetOrFocusCastbar("target")
end

function MSUF_ReanchorFocusCastBar()
    ReanchorTargetOrFocusCastbar("focus")
end

function MSUF_ReanchorPlayerCastBar()
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

    local offsetX = Round((g.castbarPlayerOffsetX or 0) + 0.5)
    local offsetY = Round((g.castbarPlayerOffsetY or 5) + 0.5)
    if g.castbarPlayerDetached then
        SetPoint(_G.MSUF_PlayerCastbar, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        SetPoint(_G.MSUF_PlayerCastbar, "BOTTOM", anchorFrame, "TOP", offsetX, offsetY)
    end

    MSUF_UpdateCastbarWidthSourceSync(g, "player", true)
    local width, height = MSUF_GetCastbarDesiredSize("player", g, _G.MSUF_PlayerCastbar, 250, 18)
    ApplyPlayerCastbarSizeAndLayout(_G.MSUF_PlayerCastbar, g, width, height)

    if _G.MSUF_PlayerCastbar.timeText and _G.MSUF_PlayerCastbar.statusBar then
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0
        SetPoint(_G.MSUF_PlayerCastbar.timeText, "RIGHT", _G.MSUF_PlayerCastbar.statusBar, "RIGHT", timeX, timeY)
        if _G.MSUF_SetJustifyHIfChanged then
            _G.MSUF_SetJustifyHIfChanged(_G.MSUF_PlayerCastbar.timeText, "RIGHT")
        else
            _G.MSUF_PlayerCastbar.timeText:SetJustifyH("RIGHT")
        end

        local showTime = g.showPlayerCastTime ~= false
        _G.MSUF_PlayerCastbar.timeText:Show()
        SetAlpha(_G.MSUF_PlayerCastbar.timeText, showTime and 1 or 0)
        if not showTime then _G.MSUF_PlayerCastbar.timeText:SetText("") end
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        _G.MSUF_ApplyCastbarTimeTextLayout(_G.MSUF_PlayerCastbar, "player")
    end

    -- Keep the preview size 1:1 with the real bar (show/hide handled elsewhere).
    if _G.MSUF_PlayerCastbarPreview then
        ApplyPlayerCastbarSizeAndLayout(_G.MSUF_PlayerCastbarPreview, g, width, height)
    end
    if _G.MSUF_PlayerCastbarPreview and _G.MSUF_PositionPlayerCastbarPreview then
        _G.MSUF_PositionPlayerCastbarPreview()
    end
end

MSUF_PlayerCastbarManageHooked = true -- Blizzard fallback removed; nothing to manage here.

function MSUF_ReanchorBossCastBar()
    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
        _G.MSUF_ApplyBossCastbarPositionSetting(false)
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
_G.MSUF_ReanchorTargetCastBar             = MSUF_ReanchorTargetCastBar
_G.MSUF_ReanchorFocusCastBar              = MSUF_ReanchorFocusCastBar
_G.MSUF_NormalizeCastbarWidthSource       = NormalizeWidthSourceKind
_G.MSUF_NormalizePlayerCastbarWidthSource = NormalizeWidthSourceKind
_G.MSUF_GetCastbarWidthSourceKey          = function(unit)
    local def = UNIT_CASTBAR[NormalizeUnit(unit)]
    return def and def.match
end
_G.MSUF_GetCastbarDesiredSize             = MSUF_GetCastbarDesiredSize
_G.MSUF_UpdateCastbarWidthSourceSync      = MSUF_UpdateCastbarWidthSourceSync
_G.MSUF_ApplyCastbarEffectiveSizeUnit     = ApplyCastbarEffectiveSizeUnit
_G.MSUF_GetPlayerCastbarDesiredSize       = function(g, bar, fallbackW, fallbackH)
    return MSUF_GetCastbarDesiredSize("player", g, bar, fallbackW, fallbackH)
end
_G.MSUF_ApplyPlayerCastbarSizeAndLayout   = ApplyPlayerCastbarSizeAndLayout
_G.MSUF_ApplyPlayerCastbarIconLayout      = MSUF_ApplyPlayerCastbarIconLayout
_G.MSUF_ReanchorPlayerCastBar             = MSUF_ReanchorPlayerCastBar
_G.MSUF_ReanchorBossCastBar               = MSUF_ReanchorBossCastBar
