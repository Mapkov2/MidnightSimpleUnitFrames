-- MSUF_GF_AuraPreview.lua — Group Frames: Drag-to-Position Preview Box
-- Renders a live mock frame in the GF options panel with draggable handles
-- for aura groups (buff/debuff/externals), text, spell indicators, status
-- icons, and private auras. All colors, textures, fonts sync live from the active
-- config. Drag resolves nearest anchor + x/y offset, writes to DB.
-- Midnight 12.0, cold-path only, zero combat overhead.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local CreateFrame   = _G.CreateFrame
local GetCursorPosition = _G.GetCursorPosition
local UnitExists    = _G.UnitExists
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local GetCurrentKeyBoardFocus = _G.GetCurrentKeyBoardFocus
local pairs         = pairs
local ipairs        = ipairs
local type          = type
local tostring      = tostring
local tonumber      = tonumber
local floor         = math.floor
local max           = math.max
local min           = math.min

local L  = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local GameTooltip = _G.GameTooltip
local SI = GF.SpellIndicators or (_G.MSUF_GF_SpellIndicators)
local W8 = "Interface\\Buttons\\WHITE8x8"
local PREVIEW_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(ns) == "table" and type(ns.Translate) == "function" then
        return ns.Translate(text)
    end
    local translated = rawget(L, text)
    if translated ~= nil then return translated end
    return text
end

local function SetPreviewLabelFont(fs, size, flags)
    if not fs or not fs.SetFont then return end
    fs:SetFont(PREVIEW_TEXT_FONT, size or 9, flags or "")
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
end

local function PreviewScopeLabel(kind)
    if kind == "mythicraid" then return Tr("Mythic Raid") end
    if kind == "raid" then return Tr("Raid") end
    return Tr("Party")
end

------------------------------------------------------------------------
-- Health text sample strings for preview (per text-mode key)
------------------------------------------------------------------------
local HP_SAMPLES = {
    NONE = "", PERCENT = "72%", CURRENT = "148.2k", MAX = "205.8k",
    DEFICIT = "-57.6k", CURMAX = "148.2k / 205.8k",
    CURPERCENT = "148.2k 72%", CURMAXPERCENT = "148k/205k 72%",
    MAXPERCENT = "205.8k 72%", PERCENTCUR = "72% 148.2k",
    PERCENTMAX = "72% 205.8k", PERCENTCURMAX = "72% 148k/205k",
}

------------------------------------------------------------------------
-- Visibility toggles state (cold-path, UI only).
-- "text" controls name/HP/power FontStrings on the mock frame.  Default
-- OFF because the text overlays obscure the aura icons underneath — the
-- primary subject of the Buffs & Debuffs preview.  User enables it on
-- demand via the sidebar button to verify name/HP/power text placement.
-- "auraText" controls cooldown + stack count FontStrings on the mock
-- aura icons.  Default ON because cooldown/stack positioning is the
-- primary setting this tab configures — users need live feedback on
-- every icon while dragging the offset sliders.
------------------------------------------------------------------------
local _visToggles = { buff = true, debuff = true, externals = true, blizzard = true,
    status = true, si = true, private = true,
    text = false, auraText = true }

-- Solo-highlight: when non-nil, only this layer group is rendered at full
-- alpha; all other layers fade to _SOLO_DIM. Activated via Shift+Click on
-- a layer button. nil = normal multi-layer mode.
local _soloKey = nil
local _SOLO_DIM = 0.15

local function ShouldShowTextPreview()
    local focus = GF._previewFocus
    local userTextOn = (_visToggles.text == true) or (_soloKey == "text")
    return userTextOn or (not focus) or focus == "text" or focus == "overlay"
end

------------------------------------------------------------------------
-- Anchor fraction table: x from left (0-1), y from bottom (0-1)
------------------------------------------------------------------------
local AF = {
    TOPLEFT     = { 0,   1   },
    TOP         = { 0.5, 1   },
    TOPRIGHT    = { 1,   1   },
    LEFT        = { 0,   0.5 },
    CENTER      = { 0.5, 0.5 },
    RIGHT       = { 1,   0.5 },
    BOTTOMLEFT  = { 0,   0   },
    BOTTOM      = { 0.5, 0   },
    BOTTOMRIGHT = { 1,   0   },
}

------------------------------------------------------------------------
-- Resolve nearest anchor from normalized position (0-1 from top-left)
------------------------------------------------------------------------
local function ResolveAnchor(rx, ry)
    local best, bestD = "CENTER", 1e9
    for pt, frac in pairs(AF) do
        local dx = rx - frac[1]
        local dy = ry - (1 - frac[2])
        local d  = dx * dx + dy * dy
        if d < bestD then best, bestD = pt, d end
    end
    return best
end

------------------------------------------------------------------------
-- Calculate x/y offset of handle's anchor-point vs target frame's anchor-point
------------------------------------------------------------------------
local function CalcOffset(handle, anchorFrame, anchor)
    local frac = AF[anchor]
    if not frac then return 0, 0 end
    if not anchorFrame then return 0, 0 end
    local mL = anchorFrame:GetLeft()  or 0
    local mB = anchorFrame:GetBottom() or 0
    local mW = max(1, anchorFrame:GetWidth()  or 1)
    local mH = max(1, anchorFrame:GetHeight() or 1)
    local aX = mL + frac[1] * mW
    local aY = mB + frac[2] * mH
    local hW = handle:GetWidth()  or 1
    local hH = handle:GetHeight() or 1
    local hAX = (handle:GetLeft() or 0) + frac[1] * hW
    local hAY = (handle:GetBottom() or 0) + frac[2] * hH
    return floor(hAX - aX + 0.5), floor(hAY - aY + 0.5)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local _box                 -- outer container
local _mockFrame           -- the visual mock group-frame
local _handles       = {}  -- [key] = handle frame
local _siHandles     = {}  -- [spellName] = handle frame (SI pool)
local _statusHandles = {}  -- [iconKey] = handle frame
local _textHandles   = {}  -- name / health / power text handles
local _selected            -- currently selected handle
local _getKind             -- fn() → "party" | "raid"
local _coordLabel          -- FontString for coord display
local _classIdx     = 1    -- class rotation index
local _onSectionOpen       -- callback(sectionKey)
local _statusPreviewSelectedKey = "roleIcon"
local _statusPreviewShowAll = false

local function IsHandleLocked(handle)
    return handle and handle._previewLocked == true
end

local function GetHandleAnchorFrame(handle)
    if handle and handle._getAnchorFrame then
        local target = handle:_getAnchorFrame()
        if target then return target end
    end
    return _mockFrame
end

local function RequestVisualRefresh()
    if GF.MarkAllDirty then
        GF.MarkAllDirty(GF.DIRTY_ALL or 0x3F)
    elseif GF.RefreshVisuals then
        GF.RefreshVisuals()
    end
end

local PREVIEW_CLASSES = {
    "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT",
    "SHAMAN","MAGE","WARLOCK","MONK","DRUID","DEMONHUNTER","EVOKER",
}
local PREVIEW_NAMES = {
    "Thrall","Jaina","Sylvanas","Anduin","Tyrande","Arthas",
    "Garrosh","Yrel","Vol'jin","Chen","Malfurion","Illidan","Alexstrasza",
}

local HANDLE_COLORS = {
    buff      = { 0.36, 0.79, 0.36 },
    debuff    = { 0.89, 0.29, 0.29 },
    externals = { 0.20, 0.67, 0.53 },
    blizzard  = { 0.36, 0.62, 0.95 },
    si        = { 0.69, 0.50, 0.88 },
    status    = { 0.80, 0.67, 0.20 },
    private   = { 0.50, 0.50, 0.50 },
    text      = { 0.55, 0.78, 0.95 },
}

local NATIVE_AURA_HANDLE_TYPES = {
    buff = "buffs",
    debuff = "debuffs",
    externals = "externals",
    private = "privateAuras",
}

local function IsNativeAuraHandle(kind, key)
    local nativeKey = NATIVE_AURA_HANDLE_TYPES[key]
    if not nativeKey or not GF.IsBlizzardAuraTypeEnabled or not GF.GetConf then return false end
    local conf = GF.GetConf(kind or "party")
    if nativeKey == "privateAuras" then
        local pa = conf and conf.privateAuras
        if pa and pa.enabled == false then return false end
    end
    return GF.IsBlizzardAuraTypeEnabled(conf, nativeKey) == true
end

local function IsNativeRendererActive(kind)
    if not GF.GetConf then return false end
    local conf = GF.GetConf(kind or "party")
    local auras = conf and conf.auras
    local nativeRenderer = (GF.IsAuraRendererBlizzard and GF.IsAuraRendererBlizzard(conf)) or (auras and auras.renderer == "BLIZZARD")
    if not (auras and auras.enabled ~= false and nativeRenderer) then return false end
    if GF.IsBlizzardAuraTypeEnabled then
        return GF.IsBlizzardAuraTypeEnabled(conf, "buffs")
            or GF.IsBlizzardAuraTypeEnabled(conf, "debuffs")
            or GF.IsBlizzardAuraTypeEnabled(conf, "dispels")
            or GF.IsBlizzardAuraTypeEnabled(conf, "externals")
            or IsNativeAuraHandle(kind, "private")
    end
    local types = auras.blizzardTypes
    if type(types) ~= "table" then return true end
    return types.buffs ~= false or types.debuffs ~= false or types.dispels ~= false or types.externals ~= false or types.privateAuras ~= false
end

local STATUS_ICON_SPECS = {
    { key = "roleIcon",      label = "Role",        sizeKey = "roleIconSize",      anchorKey = "roleIconAnchor",   xKey = "roleIconX",   yKey = "roleIconY",   layerKey = "roleIconLayer",   defAnchor = "TOPLEFT",  defSize = 12 },
    { key = "leaderIcon",    label = "Leader",       sizeKey = "leaderIconSize",    anchorKey = "leaderIconAnchor", xKey = "leaderIconX", yKey = "leaderIconY", layerKey = "leaderIconLayer", defAnchor = "TOPRIGHT", defSize = 12 },
    { key = "assistIcon",    label = "Assist",       sizeKey = "assistIconSize",    anchorKey = "assistIconAnchor", xKey = "assistIconX", yKey = "assistIconY", layerKey = "assistIconLayer", defAnchor = "TOPRIGHT", defSize = 12 },
    { key = "raidMarker",    label = "Marker",       sizeKey = "raidMarkerSize",    anchorKey = "raidMarkerAnchor", xKey = "raidMarkerX", yKey = "raidMarkerY", layerKey = "raidMarkerLayer", defAnchor = "CENTER",   defSize = 14 },
    { key = "readyCheckIcon",label = "Ready",        sizeKey = "readyCheckSize",    anchorKey = "readyCheckAnchor", xKey = "readyCheckX", yKey = "readyCheckY", layerKey = "readyCheckLayer", defAnchor = "CENTER",   defSize = 16 },
    { key = "summonIcon",    label = "Summon",       sizeKey = "summonIconSize",    anchorKey = "summonAnchor",     xKey = "summonX",     yKey = "summonY",     layerKey = "summonLayer",     defAnchor = "CENTER",   defSize = 16 },
    { key = "resurrectIcon", label = "Rez",          sizeKey = "resurrectIconSize", anchorKey = "resurrectAnchor",  xKey = "resurrectX",  yKey = "resurrectY",  layerKey = "resurrectLayer",  defAnchor = "CENTER",   defSize = 16 },
    { key = "phaseIcon",     label = "Phase",        sizeKey = "phaseIconSize",     anchorKey = "phaseAnchor",      xKey = "phaseX",      yKey = "phaseY",      layerKey = "phaseLayer",      defAnchor = "TOPLEFT",  defSize = 14 },
    { key = "statusText",      label = "Dead Text",      sizeKey = "statusTextSize",      anchorKey = "statusTextAnchor",      xKey = "statusOffsetX",      yKey = "statusOffsetY",      layerKey = "statusTextLayer",      defAnchor = "CENTER", defSize = 14, isText = true, previewText = "DEAD" },
    { key = "statusGhostText", label = "Ghost Text",     sizeKey = "statusGhostTextSize", anchorKey = "statusGhostTextAnchor", xKey = "statusGhostOffsetX", yKey = "statusGhostOffsetY", layerKey = "statusGhostTextLayer", defAnchor = "CENTER", defSize = 14, isText = true, previewText = "GHOST" },
    { key = "statusAFKText",   label = "AFK / DND Text", sizeKey = "statusAFKTextSize",   anchorKey = "statusAFKTextAnchor",   xKey = "statusAFKOffsetX",   yKey = "statusAFKOffsetY",   layerKey = "statusAFKTextLayer",   defAnchor = "CENTER", defSize = 14, isText = true, previewText = "AFK" },
}

local function ShouldShowStatusPreviewHandle(iconKey)
    if _visToggles.status == false then return false end
    if GF._previewFocus == "sicons" and _statusPreviewShowAll ~= true and _statusPreviewSelectedKey then
        return iconKey == _statusPreviewSelectedKey
    end
    return true
end

------------------------------------------------------------------------
-- Selection
------------------------------------------------------------------------
local function UpdateCoordDisplay(key, anchor, offX, offY)
    if not _coordLabel then return end
    if not key then
        _coordLabel:SetText(Tr("Click a handle to select - custom layers can be moved; Blizzard is locked"))
    elseif anchor == "LOCKED" then
        _coordLabel:SetText((key or "?") .. "   " .. Tr("locked: Blizzard controls native aura placement"))
    else
        _coordLabel:SetText((key or "?") .. "   " .. string.format(Tr("anchor: %s"), (anchor or "?")) .. "   x: " .. (offX or 0) .. "   y: " .. (offY or 0))
    end
end

local function GetCurrentHandleAnchor(handle)
    local anchor
    if handle and handle._getCurrentAnchor then
        anchor = handle:_getCurrentAnchor()
    end
    if anchor and AF[anchor] then return anchor end

    if handle and handle.GetPoint then
        local point, _, relPoint = handle:GetPoint(1)
        if point and AF[point] then return point end
        if relPoint and AF[relPoint] then return relPoint end
    end
    return "CENTER"
end

local function RoundToNearest(v)
    v = tonumber(v) or 0
    if v >= 0 then return floor(v + 0.5) end
    return -floor((-v) + 0.5)
end

local function ScaleFrameValue(value, scale, minValue)
    value = tonumber(value) or 0
    scale = tonumber(scale) or 1
    local v
    if scale == 1 then
        v = value
    elseif GF.ScaleValue then
        v = GF.ScaleValue(value, scale, minValue)
    else
        v = RoundToNearest(value * scale)
    end
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

local function GetPreviewZoom()
    local zoom = _mockFrame and _mockFrame._previewZoom or 1
    if zoom == 0 then zoom = 1 end
    return zoom
end

local function GetPreviewFrameScale()
    local frameScale = _mockFrame and _mockFrame._previewFrameScale or 1
    if frameScale == 0 then frameScale = 1 end
    return frameScale
end

local function LiveToPreviewValue(value)
    return RoundToNearest((tonumber(value) or 0) * GetPreviewZoom())
end

local function PreviewToConfigOffset(offX, offY)
    local denom = GetPreviewZoom() * GetPreviewFrameScale()
    if denom == 0 then denom = 1 end
    return RoundToNearest((offX or 0) / denom), RoundToNearest((offY or 0) / denom)
end

local function ConfigToPreviewOffset(cfgX, cfgY)
    local frameScale = GetPreviewFrameScale()
    return LiveToPreviewValue(ScaleFrameValue(cfgX or 0, frameScale)),
           LiveToPreviewValue(ScaleFrameValue(cfgY or 0, frameScale))
end

local function GetHandlePreviewAdjust(handle)
    return (handle and handle._previewOffsetAdjustX) or 0,
           (handle and handle._previewOffsetAdjustY) or 0
end

local function PreviewToHandleConfigOffset(handle, offX, offY)
    local adjX, adjY = GetHandlePreviewAdjust(handle)
    return PreviewToConfigOffset((offX or 0) - adjX, (offY or 0) - adjY)
end

local function ConfigToHandlePreviewOffset(handle, cfgX, cfgY)
    local offX, offY = ConfigToPreviewOffset(cfgX, cfgY)
    local adjX, adjY = GetHandlePreviewAdjust(handle)
    return offX + adjX, offY + adjY
end

local function GetHandlePosition(handle)
    if not handle or not _mockFrame then return nil end
    local anchorFrame = GetHandleAnchorFrame(handle) or _mockFrame
    local anchor = GetCurrentHandleAnchor(handle)
    local offX, offY = CalcOffset(handle, anchorFrame, anchor)
    local cfgX, cfgY = PreviewToHandleConfigOffset(handle, offX, offY)
    return anchorFrame, anchor, offX, offY, cfgX, cfgY
end

local function RefreshSelectedCoordDisplay()
    if not _selected or not _selected.IsShown or not _selected:IsShown() then return false end
    if IsHandleLocked(_selected) then
        UpdateCoordDisplay(_selected._cfgKey, "LOCKED")
        return true
    end
    local _, anchor, _, _, cfgX, cfgY = GetHandlePosition(_selected)
    if not anchor then return false end
    UpdateCoordDisplay(_selected._cfgKey, anchor, cfgX, cfgY)
    return true
end

------------------------------------------------------------------------
-- Layer visibility helpers.
-- Encapsulates the per-key → handle mapping so OnClick, solo-apply, and
-- post-rebuild refresh all share one implementation. Declared here
-- (after _handles/_statusHandles/_siHandles are defined above) so the
-- closures resolve to the correct file-scope locals.
-- Cold-path UI only; no protected API reads, no secret values.
------------------------------------------------------------------------
local function ForEachLayerHandle(key, fn)
    if key == "buff" or key == "debuff" or key == "externals" then
        local h = _handles[key]
        if h then fn(h) end
    elseif key == "blizzard" then
        local h = _handles.blizzard
        if h then fn(h) end
    elseif key == "status" then
        for _, sh in pairs(_statusHandles) do fn(sh) end
    elseif key == "si" then
        for _, sh in pairs(_siHandles) do fn(sh) end
    elseif key == "private" then
        local h = _handles.private
        if h then fn(h) end
    elseif key == "text" then
        for _, th in pairs(_textHandles) do fn(th) end
    end
end

-- Apply current _soloKey state to every managed handle's alpha.
-- Does NOT touch :SetShown — that is owned by RefreshPreviewHandles' inline
-- logic which respects per-group config.enabled. Solo mode is a pure
-- alpha concern: soloed layer at full alpha, others at _SOLO_DIM.
-- When _soloKey is nil, every handle is restored to alpha 1 (unless the
-- handle-selection dim-cascade in SelectHandle is active, which composes
-- with this by early-returning in solo mode).
local function ApplyLayerVisibility()
    local KEYS = { "buff", "debuff", "externals", "blizzard", "status", "si", "private", "text" }
    for i = 1, #KEYS do
        local k = KEYS[i]
        local alpha = 1
        if _soloKey ~= nil and _soloKey ~= k then
            alpha = _SOLO_DIM
        end
        ForEachLayerHandle(k, function(h)
            if h.SetAlpha then h:SetAlpha(alpha) end
        end)
    end
end

local function SelectHandle(handle, skipSectionOpen)
    if _selected and _selected ~= handle and _selected._selBorder then
        _selected._selBorder:Hide()
    end
    _selected = handle
    if handle then
        if handle._selBorder then handle._selBorder:Show() end
        if not skipSectionOpen and handle._sectionKey and _onSectionOpen then
            _onSectionOpen(handle._sectionKey)
        end
        RefreshSelectedCoordDisplay()
    end
    -- While solo-highlight is active, solo owns alpha — don't fight it
    -- from the selection dim-cascade. ApplyLayerVisibility has already
    -- set each handle's alpha based on its layer's solo state.
    if _soloKey ~= nil then return end
    -- Dim non-selected handles
    local dimAlpha = handle and 0.35 or 1
    for _, h in pairs(_handles) do
        if h ~= handle then h:SetAlpha(dimAlpha) else h:SetAlpha(1) end
    end
    for _, h in pairs(_statusHandles) do
        if h ~= handle then h:SetAlpha(dimAlpha) else h:SetAlpha(1) end
    end
    for _, h in pairs(_siHandles) do
        if h ~= handle then h:SetAlpha(dimAlpha) else h:SetAlpha(1) end
    end
    for _, h in pairs(_textHandles) do
        if h ~= handle then h:SetAlpha(dimAlpha) else h:SetAlpha(1) end
    end
end

local function GetNudgeStep()
    if IsControlKeyDown and IsControlKeyDown() then return 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
    return 1
end

local function IsTextInputFocused()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end

local function NudgeSelectedHandle(dx, dy)
    local h = _selected
    if IsHandleLocked(h) then
        RefreshSelectedCoordDisplay()
        return false
    end
    if not h or not h.IsShown or not h:IsShown() or not h._onDragFinish then return false end
    if not _mockFrame then return false end

    local anchorFrame, anchor, _, _, cfgX, cfgY = GetHandlePosition(h)
    if not anchorFrame or not anchor then return false end

    local step = GetNudgeStep()
    local newCfgX = (cfgX or 0) + dx * step
    local newCfgY = (cfgY or 0) + dy * step
    local newOffX, newOffY = ConfigToHandlePreviewOffset(h, newCfgX, newCfgY)

    h:ClearAllPoints()
    h:SetPoint(anchor, anchorFrame, anchor, newOffX, newOffY)
    h._onDragFinish(anchor, newOffX, newOffY)

    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
    SelectHandle(h, true)
    UpdateCoordDisplay(h._cfgKey, anchor, newCfgX, newCfgY)
    return true
end

------------------------------------------------------------------------
-- Drag system (OnMouseDown/Up/OnUpdate — no StartMoving, scroll-safe)
------------------------------------------------------------------------
do
    local _dragging      = false
    local _dragHandle    = nil
    local _dragOffX      = 0
    local _dragOffY      = 0
    local _dragOrigStrata = "MEDIUM"

    local function DragUpdate(self)
        if not _dragging or self ~= _dragHandle then return end
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        if s == 0 then s = 1 end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT",
            cx / s + _dragOffX, cy / s + _dragOffY)
    end

    local function DragStart(self, btn)
        if btn ~= "LeftButton" then return end
        SelectHandle(self)
        if IsHandleLocked(self) then return end
        _dragging     = true
        _dragHandle   = self
        _dragOrigStrata = self:GetFrameStrata() or "MEDIUM"
        local cx, cy  = GetCursorPosition()
        local s       = self:GetEffectiveScale()
        if s == 0 then s = 1 end
        _dragOffX = (self:GetLeft() or 0) - cx / s
        _dragOffY = (self:GetTop()  or 0) - cy / s
        self:SetFrameStrata("TOOLTIP")
        -- Show snap guides
        if _mockFrame and _mockFrame._snapLines then
            for i = 1, 6 do _mockFrame._snapLines[i]:Show() end
        end
    end

    local function DragStop(self, btn)
        if btn ~= "LeftButton" or not _dragging or self ~= _dragHandle then return end
        _dragging   = false
        _dragHandle = nil
        self:SetFrameStrata(_dragOrigStrata)
        -- Hide snap guides
        if _mockFrame and _mockFrame._snapLines then
            for i = 1, 6 do _mockFrame._snapLines[i]:Hide() end
        end
        if not _mockFrame then return end
        local anchorFrame = GetHandleAnchorFrame(self) or _mockFrame

        local mL = anchorFrame:GetLeft()  or 0
        local mT = anchorFrame:GetTop()   or 0
        local mW = max(1, anchorFrame:GetWidth()  or 1)
        local mH = max(1, anchorFrame:GetHeight() or 1)
        local hCX = ((self:GetLeft() or 0) + (self:GetRight()  or 0)) / 2
        local hCY = ((self:GetTop()  or 0) + (self:GetBottom() or 0)) / 2

        local rx = max(0, min(1, (hCX - mL) / mW))
        local ry = max(0, min(1, (mT - hCY) / mH))

        -- If handle has a fixed anchor from config, keep it; otherwise resolve from position
        local anchor
        if self._getCurrentAnchor then
            anchor = self:_getCurrentAnchor()
        end
        if not anchor or not AF[anchor] then
            anchor = ResolveAnchor(rx, ry)
        end
        local offX, offY = CalcOffset(self, anchorFrame, anchor)

        self:ClearAllPoints()
        self:SetPoint(anchor, anchorFrame, anchor, offX, offY)

        local cfgX, cfgY = PreviewToHandleConfigOffset(self, offX, offY)
        UpdateCoordDisplay(self._cfgKey, anchor, cfgX, cfgY)

        if self._onDragFinish then
            self._onDragFinish(anchor, offX, offY)
        end
    end

    function GF._PreviewMakeDraggable(handle)
        handle:EnableMouse(true)
        handle:SetScript("OnMouseDown", DragStart)
        handle:SetScript("OnMouseUp",   DragStop)
        handle:SetScript("OnUpdate",    DragUpdate)
    end
end

------------------------------------------------------------------------
-- Handle factory
------------------------------------------------------------------------
local function CreateHandle(parent, key, sectionKey, w, h, colorKey)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(max(6, w), max(6, h))
    f:SetFrameLevel(parent:GetFrameLevel() + 20)
    f._cfgKey     = key
    f._sectionKey = sectionKey

    local sel = f:CreateTexture(nil, "OVERLAY", nil, 7)
    sel:SetPoint("TOPLEFT",     f, "TOPLEFT",     -2, 2)
    sel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  2, -2)
    sel:SetColorTexture(0.27, 0.53, 0.80, 0.45)
    sel:Hide()
    f._selBorder = sel

    local c = HANDLE_COLORS[colorKey or key] or HANDLE_COLORS.status
    local lbl = f:CreateFontString(nil, "OVERLAY")
    SetPreviewLabelFont(lbl, 9, "OUTLINE")
    lbl:SetText(key)
    lbl:SetTextColor(c[1], c[2], c[3], 0.9)
    f._label = lbl

    GF._PreviewMakeDraggable(f)

    -- Handle tooltip (shows anchor/offset/section)
    f:HookScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._cfgKey or "?", 1, 1, 1)
            if IsHandleLocked(self) then
                GameTooltip:AddLine(Tr("Locked: Blizzard controls native aura placement."), 0.7, 0.7, 0.7)
                GameTooltip:AddLine(Tr("The preview shows where Blizzard-rendered auras can appear."), 0.4, 0.4, 0.5)
            elseif self._getCurrentAnchor then
                local anc = self:_getCurrentAnchor() or "?"
                GameTooltip:AddLine(string.format(Tr("Anchor: %s"), anc), 0.7, 0.7, 0.7)
            end
            if self._sectionKey then
                GameTooltip:AddLine(string.format(Tr("Section: %s"), self._sectionKey), 0.5, 0.5, 0.6)
            end
            if not IsHandleLocked(self) then
                GameTooltip:AddLine(Tr("Drag to reposition. Arrow keys nudge by 1."), 0.4, 0.4, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    f:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return f
end

local function AddMockIcon(handle, size, r, g, b, isCircle)
    local t = handle:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetColorTexture(r or 0.3, g or 0.3, b or 0.3, 1)
    if not handle._icons then handle._icons = {} end
    handle._icons[#handle._icons + 1] = t
    return t
end

local function LayoutMockIcons(handle, size, spacing, perRow, anchor)
    local icons = handle._icons
    if not icons then return end
    local n = #icons
    if n == 0 then return end
    local cols = min(perRow or n, n)
    local rows = floor((n - 1) / cols) + 1
    local totalW = cols * size + max(0, cols - 1) * spacing
    local totalH = rows * size + max(0, rows - 1) * spacing
    handle:SetSize(max(6, totalW), max(6, totalH))
    for i = 1, n do
        local ic = icons[i]
        local col = (i - 1) % cols
        local row = floor((i - 1) / cols)
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        ic:SetPoint("TOPLEFT", handle, "TOPLEFT",
            col * (size + spacing), -(row * (size + spacing)))
    end
end

------------------------------------------------------------------------
-- Build mock group-frame (real StatusBar + BackdropTemplate)
------------------------------------------------------------------------
local PREVIEW_MIN_W = 380
local PREVIEW_MIN_H = 130
local PREVIEW_ROLE = "HEALER"

local function GetMockPowerHeight(kind, conf, zoom, frameScale)
    local livePowerH
    if GF.GetEffectivePowerHeight then
        livePowerH = GF.GetEffectivePowerHeight(kind, nil, PREVIEW_ROLE, conf)
    end
    if livePowerH == nil then
        local rawPowerH = conf and (conf.powerHeight or 6) or 6
        if GF.ShouldShowPowerBarForRole and not GF.ShouldShowPowerBarForRole(kind, PREVIEW_ROLE, conf) then
            rawPowerH = 0
        end
        livePowerH = rawPowerH > 0 and ScaleFrameValue(rawPowerH, frameScale or 1, 0) or 0
    end
    livePowerH = tonumber(livePowerH) or 0
    if livePowerH <= 0 then return 0 end
    zoom = tonumber(zoom) or 1
    if zoom == 0 then zoom = 1 end
    return RoundToNearest(livePowerH * zoom)
end

local function EnsureMockPowerBar(f, kind, conf)
    if f._power then return f._power end

    local power = CreateFrame("StatusBar", nil, f)
    power:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    power:SetMinMaxValues(0, 1)
    power:SetValue(1)
    power:SetStatusBarColor(0.13, 0.27, 0.67, 1)
    f._power = power

    local powerBg = power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(power)
    powerBg:SetTexture(W8)
    powerBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f._powerBg = powerBg

    return power
end

local function RefreshMockGroupBorder(f, conf, previewScale)
    if not f then return end
    local border = f._groupBorderPreview
    if not border then
        border = CreateFrame("Frame", nil, f, "BackdropTemplate")
        border:EnableMouse(false)
        f._groupBorderPreview = border
    end
    if not conf or conf.groupBorderEnabled ~= true then
        border:Hide()
        return
    end

    local scale = tonumber(previewScale) or 1
    if scale <= 0 then scale = 1 end
    local size = floor(((tonumber(conf.groupBorderSize) or 1) * scale) + 0.5)
    if size < 1 then size = 1 elseif size > 24 then size = 24 end
    local pad = floor(((tonumber(conf.groupBorderPadding) or 2) * scale) + 0.5)
    if pad < 0 then pad = 0 elseif pad > 96 then pad = 96 end

    if border._msufPreviewGBSize ~= size then
        border._msufPreviewGBSize = size
        border:SetBackdrop({ edgeFile = W8, edgeSize = size })
        border:SetBackdropColor(0, 0, 0, 0)
    end
    border:SetBackdropBorderColor(
        tonumber(conf.groupBorderR) or 0.38,
        tonumber(conf.groupBorderG) or 0.68,
        tonumber(conf.groupBorderB) or 1.00,
        tonumber(conf.groupBorderA) or 0.95
    )
    border:SetFrameLevel((f.GetFrameLevel and f:GetFrameLevel() or 0) + 14)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pad, -pad)
    border:Show()
end

local function BuildMockFrame(parent)
    local kind = _getKind and _getKind() or "party"
    local conf = GF.GetConf(kind)
    local rawW = conf.width or 120
    local rawH = conf.height or 40
    local liveW, liveH, frameScale = rawW, rawH, 1
    if GF.GetScaledFrameMetrics then
        liveW, liveH, _, frameScale = GF.GetScaledFrameMetrics(kind)
    elseif GF.GetFrameScale then
        frameScale = GF.GetFrameScale(kind) or 1
        liveW = floor(rawW * frameScale + 0.5)
        liveH = floor(rawH * frameScale + 0.5)
    end
    -- Aspect-faithful scaling: pick a uniform scale such that the mock
    -- frame fits inside (PREVIEW_MIN_W × PREVIEW_MIN_H) while preserving
    -- the live w/h ratio exactly.  Previously a max(PREVIEW_MIN_W, ...)
    -- floor stretched narrow frames horizontally so the preview no longer
    -- matched what the user saw in-game.
    local scaleW = PREVIEW_MIN_W / max(1, liveW)
    local scaleH = PREVIEW_MIN_H / max(1, liveH)
    local scale = max(1.4, min(2.8, min(scaleW, scaleH)))
    local rawToMock = scale * (frameScale or 1)
    local w = floor(liveW * scale + 0.5)
    local h = floor(liveH * scale + 0.5)
    local powerH = GetMockPowerHeight(kind, conf, scale, frameScale)
    local insetBase = (GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind)) or 1
    local inset = max(0, floor(insetBase * rawToMock + 0.5))

    local f = CreateFrame("Frame", "MSUF_GFPreviewMock", parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    f:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = inset,
        insets = { left = inset, right = inset, top = inset, bottom = inset } })
    f:SetBackdropColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f:SetBackdropBorderColor(conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1)
    RefreshMockGroupBorder(f, conf, rawToMock)

    local health = CreateFrame("StatusBar", nil, f)
    health:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    health:SetMinMaxValues(0, 1)
    health:SetValue(0.72)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset,
        powerH > 0 and (powerH + inset) or inset)
    f._health = health

    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    healthBg:SetTexture(GF.ResolveBarBgTexture and GF.ResolveBarBgTexture(kind) or W8)
    healthBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f._healthBg = healthBg

    -- Heal prediction overlay
    local healPred = CreateFrame("StatusBar", nil, f)
    healPred:SetStatusBarTexture(W8)
    healPred:SetStatusBarColor(0, 1, 0.4, 0.45)
    healPred:SetMinMaxValues(0, 1)
    healPred:SetValue(0.12)
    healPred:SetPoint("TOPLEFT", health, "TOPRIGHT", -1, 0)
    healPred:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
    healPred:SetWidth(max(1, w * 0.12))
    f._healPred = healPred

    -- Absorb overlay
    local absorb = CreateFrame("StatusBar", nil, f)
    absorb:SetStatusBarTexture(W8)
    absorb:SetStatusBarColor(0.55, 0.70, 1.0, 0.5)
    absorb:SetMinMaxValues(0, 1)
    absorb:SetValue(1)
    absorb:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    absorb:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
    absorb:SetWidth(max(1, w * 0.08))
    f._absorb = absorb

    -- Power bar
    if powerH > 0 then
        local power = EnsureMockPowerBar(f, kind, conf)
        power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(powerH)
    end

    -- Name text layer
    local nameLayer = CreateFrame("Frame", nil, f)
    nameLayer:SetAllPoints(health)
    nameLayer:SetFrameLevel(health:GetFrameLevel() + (conf.nameTextLayer or 5))
    f._nameLayer = nameLayer

    -- Text overlay layer (above health/absorb bars so text is visible)
    local textLayer = CreateFrame("Frame", nil, f)
    textLayer:SetAllPoints(health)
    textLayer:SetFrameLevel(health:GetFrameLevel() + (conf.textLayer or 5))
    f._textLayer = textLayer

    -- Name text
    local nameFS = nameLayer:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(GF.ResolveFontPath(kind), conf.nameFontSize or 12, GF.ResolveFontFlags(kind))
    nameFS:SetPoint("LEFT", health, "LEFT", 6, 0)
    nameFS:SetText(PREVIEW_NAMES[_classIdx] or "Thrall")
    nameFS:SetShadowColor(0, 0, 0, 1)
    nameFS:SetShadowOffset(1, -1)
    f._nameFS = nameFS

    -- HP text
    local hpLeftFS = textLayer:CreateFontString(nil, "OVERLAY")
    local hpCenterFS = textLayer:CreateFontString(nil, "OVERLAY")
    local hpRightFS = textLayer:CreateFontString(nil, "OVERLAY")
    for _, fs in ipairs({ hpLeftFS, hpCenterFS, hpRightFS }) do
        fs:SetFont(GF.ResolveFontPath(kind), conf.hpFontSize or 10, GF.ResolveFontFlags(kind))
        fs:SetText("72%")
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:Hide()
    end
    hpLeftFS:SetPoint("LEFT", health, "LEFT", 6, 0)
    hpLeftFS:SetJustifyH("LEFT")
    hpCenterFS:SetPoint("CENTER", health, "CENTER", 0, 0)
    hpCenterFS:SetJustifyH("CENTER")
    hpRightFS:SetPoint("RIGHT", health, "RIGHT", -6, 0)
    hpRightFS:SetJustifyH("RIGHT")
    f._hpLeftFS = hpLeftFS
    f._hpCenterFS = hpCenterFS
    f._hpRightFS = hpRightFS
    f._hpFS = hpCenterFS

    -- Power text
    local powLayer = CreateFrame("Frame", nil, f)
    powLayer:SetAllPoints(f)
    powLayer:SetFrameLevel(health:GetFrameLevel() + (conf.powerTextLayer or 2))
    f._powerTextLayer = powLayer
    local fr, fg, fb = GF.ResolveFontColor(kind)
    local powLeftFS = powLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local powCenterFS = powLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local powRightFS = powLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    for _, fs in ipairs({ powLeftFS, powCenterFS, powRightFS }) do
        fs:SetFont(GF.ResolveFontPath(kind), conf.powerFontSize or 9, GF.ResolveFontFlags(kind))
        fs:SetText("70")
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:SetTextColor(fr, fg, fb, 0.9)
        fs:Hide()
    end
    local powerAnchor = (powerH > 0 and f._power) or health
    powLeftFS:SetPoint("LEFT", powerAnchor, "LEFT", 2, 0)
    powLeftFS:SetJustifyH("LEFT")
    powCenterFS:SetPoint("CENTER", powerAnchor, "CENTER", 0, 0)
    powCenterFS:SetJustifyH("CENTER")
    powRightFS:SetPoint("RIGHT", powerAnchor, "RIGHT", -2, 0)
    powRightFS:SetJustifyH("RIGHT")
    f._powerLeftFS = powLeftFS
    f._powerCenterFS = powCenterFS
    f._powerRightFS = powRightFS
    f._powerFS = powCenterFS

    _mockFrame = f
    f._previewScale = rawToMock
    f._previewZoom = scale
    f._previewFrameScale = frameScale

    -- Corner indicator dots are lazy-created in RefreshPreviewHandles (BackdropTemplate frames)

    -- Anchor reference dots (9 anchor positions, subtle guides)
    do
        local ANCHOR9_LIST = {
            "TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT",
            "BOTTOMLEFT","BOTTOM","BOTTOMRIGHT",
        }
        f._anchorDots = {}
        for _, pt in ipairs(ANCHOR9_LIST) do
            local dot = f:CreateTexture(nil, "OVERLAY", nil, 1)
            dot:SetSize(3, 3)
            dot:SetColorTexture(0.5, 0.5, 0.7, 0.4)
            dot:SetPoint(pt, f, pt,
                pt:find("LEFT") and 1 or (pt:find("RIGHT") and -1 or 0),
                pt:find("TOP") and -1 or (pt:find("BOTTOM") and 1 or 0))
            f._anchorDots[pt] = dot
        end
    end

    -- Target / aggro highlight border (glow overlay)
    do
        local hl = CreateFrame("Frame", nil, f)
        hl:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
        hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
        hl:SetFrameLevel(f:GetFrameLevel() + 15)
        local edges = {}
        for i = 1, 4 do
            edges[i] = hl:CreateTexture(nil, "OVERLAY")
            edges[i]:SetColorTexture(1, 0.4, 0, 0.6)
        end
        edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(2)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(2)
        edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(2)
        edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(2)
        f._hlBorder = hl
        f._hlEdges = edges
        hl:Hide()
    end

    -- Snap guide lines (horizontal + vertical at each anchor axis, shown during drag)
    do
        f._snapLines = {}
        for i = 1, 6 do
            local line = f:CreateTexture(nil, "OVERLAY", nil, 2)
            line:SetColorTexture(0.35, 0.55, 0.85, 0.3)
            line:Hide()
            f._snapLines[i] = line
        end
        -- Lines 1-3: horizontal at top/center/bottom
        -- Lines 4-6: vertical at left/center/right
    end

    return f
end

local function NormalizeTextAnchor(anchor)
    if anchor == "RIGHT" or anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" then return "RIGHT" end
    if anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then return "CENTER" end
    return "LEFT"
end

------------------------------------------------------------------------
-- Refresh mock frame visuals from config (colors, textures, fonts, size)
------------------------------------------------------------------------
function GF.RefreshPreviewBox()
    if not _mockFrame or not _getKind then return end
    local kind = _getKind()
    local conf = GF.GetConf(kind)
    local m    = _mockFrame
    if _box and _box._previewTitle then
        _box._previewTitle:SetText(Tr("Group Frame Preview") .. " - " .. PreviewScopeLabel(kind))
    end

    -- Size (aspect-faithful scaling — mirrors BuildMockFrame exactly).
    -- Pick a uniform scale so the mock fits inside PREVIEW_MIN_W ×
    -- PREVIEW_MIN_H while preserving the live w/h ratio. The previous
    -- max(PREVIEW_MIN_W, ...) floor stretched narrow frames horizontally.
    local rawW = conf.width or 120
    local rawH = conf.height or 40
    local liveW, liveH, frameScale = rawW, rawH, 1
    if GF.GetScaledFrameMetrics then
        liveW, liveH, _, frameScale = GF.GetScaledFrameMetrics(kind)
    elseif GF.GetFrameScale then
        frameScale = GF.GetFrameScale(kind) or 1
        liveW = floor(rawW * frameScale + 0.5)
        liveH = floor(rawH * frameScale + 0.5)
    end
    local scaleW = PREVIEW_MIN_W / max(1, liveW)
    local scaleH = PREVIEW_MIN_H / max(1, liveH)
    local scale = max(1.4, min(2.8, min(scaleW, scaleH)))
    local rawToMock = scale * (frameScale or 1)
    local w = floor(liveW * scale + 0.5)
    local h = floor(liveH * scale + 0.5)
    m:SetSize(w, h)
    m._previewScale = rawToMock
    m._previewZoom = scale
    m._previewFrameScale = frameScale

    -- Background
    m:SetBackdropColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    m:SetBackdropBorderColor(conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1)
    RefreshMockGroupBorder(m, conf, rawToMock)
    if m._healthBg then
        m._healthBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    end
    if m._powerBg then
        m._powerBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    end

    -- Bar textures
    local barTex = GF.ResolveBarTexture(kind)
    if m._health then m._health:SetStatusBarTexture(barTex) end
    if m._power  then m._power:SetStatusBarTexture(barTex) end
    if m._healthBg then
        local bgTex = (GF.ResolveBarBgTexture and GF.ResolveBarBgTexture(kind)) or W8
        m._healthBg:SetTexture(bgTex)
    end
    if m._powerBg then
        m._powerBg:SetTexture(W8)
    end

    -- Power bar geometry
    local powerH = GetMockPowerHeight(kind, conf, scale, frameScale)
    local insetBase = (GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind)) or 1
    local inset = max(0, floor(insetBase * rawToMock + 0.5))
    if m._health then
        m._health:ClearAllPoints()
        m._health:SetPoint("TOPLEFT", m, "TOPLEFT", inset, -inset)
        m._health:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -inset,
            powerH > 0 and (powerH + inset) or inset)
    end
    if powerH > 0 then
        local power = EnsureMockPowerBar(m, kind, conf)
        power:SetStatusBarTexture(barTex)
        power:ClearAllPoints()
        power:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(powerH)
        power:Show()
    elseif m._power then
        m._power:SetHeight(0.001)
        m._power:Hide()
    end
    if m._powerTextLayer then
        m._powerTextLayer:ClearAllPoints()
        m._powerTextLayer:SetAllPoints(m)
    end

    -- Health color (mirror GF_Render ApplyHealthColor: gfBarMode → global fallback)
    do
        local cls = PREVIEW_CLASSES[_classIdx] or "WARRIOR"
        local gfMode = conf.gfBarMode

        -- Resolve effective mode (same chain as ApplyHealthColor)
        local mode
        if gfMode and gfMode ~= "GLOBAL" then
            mode = gfMode
        else
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            local globalMode = cache and cache.barMode
            if globalMode == "dark" or globalMode == "unified" then
                mode = globalMode
            else
                mode = conf.healthColorMode or "CLASS"
            end
        end

        if mode == "dark" then
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            local r = conf.gfDarkR or (cache and cache.darkBarR) or 0
            local g = conf.gfDarkG or (cache and cache.darkBarG) or 0
            local b = conf.gfDarkB or (cache and cache.darkBarB) or 0
            m._health:SetStatusBarColor(r, g, b, 1)
        elseif mode == "unified" then
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            local r = conf.gfUnifiedR or (cache and cache.unifiedBarR) or 0.10
            local g = conf.gfUnifiedG or (cache and cache.unifiedBarG) or 0.60
            local b = conf.gfUnifiedB or (cache and cache.unifiedBarB) or 0.90
            m._health:SetStatusBarColor(r, g, b, 1)
        elseif mode == "CLASS" then
            local fastC = _G.MSUF_UFCore_GetClassBarColorFast
            local r, g, b
            if type(fastC) == "function" then r, g, b = fastC(cls) end
            if not r then
                local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[cls]
                if cc then r, g, b = cc.r, cc.g, cc.b end
            end
            m._health:SetStatusBarColor(r or 0.2, g or 0.8, b or 0.2, 1)
        elseif mode == "GRADIENT" then
            m._health:SetStatusBarColor(0.65, 0.90, 0.15, 1) -- preview at ~72%
        else
            -- CUSTOM or fallback
            m._health:SetStatusBarColor(
                conf.healthCustomR or 0.2, conf.healthCustomG or 0.8,
                conf.healthCustomB or 0.2, 1)
        end
    end

    -- Overlay colors + visibility from config (mirrors _GF_IsAbsorbEnabled)
    do
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        local gfDbKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
        local gfDb = _G.MSUF_DB and _G.MSUF_DB[gfDbKey]
        local function resolve(key)
            if gfDb and gfDb.hlOverride and gfDb[key] ~= nil then return gfDb[key] end
            return gen and gen[key]
        end

        -- Heal prediction
        if m._healPred then
            local hpEn = (GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(kind, conf)) or false
            if hpEn ~= false then
                local r, g, b = 0, 1, 0.4
                if gen then
                    if type(gen.healPredColorR) == "number" then r = gen.healPredColorR end
                    if type(gen.healPredColorG) == "number" then g = gen.healPredColorG end
                    if type(gen.healPredColorB) == "number" then b = gen.healPredColorB end
                end
                m._healPred:SetStatusBarColor(r, g, b, 0.45)
                m._healPred:SetWidth(max(1, w * 0.12))
                m._healPred:Show()
            else
                m._healPred:Hide()
            end
        end

        -- Absorb
        if m._absorb then
            local absOn = true
            local atm = tonumber(resolve("absorbTextMode"))
            if atm then absOn = (atm == 2 or atm == 3)
            else
                local eab = resolve("enableAbsorbBar")
                if eab ~= nil then absOn = (eab ~= false) end
            end
            if absOn then
                local r, g, b = 0.55, 0.70, 1.0
                if gen then
                    if type(gen.absorbBarColorR) == "number" then r = gen.absorbBarColorR end
                    if type(gen.absorbBarColorG) == "number" then g = gen.absorbBarColorG end
                    if type(gen.absorbBarColorB) == "number" then b = gen.absorbBarColorB end
                end
                local a = tonumber(resolve("absorbBarOpacity")) or 0.6
                m._absorb:SetStatusBarColor(r, g, b, 1)
                local tex = m._absorb.GetStatusBarTexture and m._absorb:GetStatusBarTexture()
                if tex and tex.SetAlpha then tex:SetAlpha(a) end
                m._absorb:SetWidth(max(1, w * 0.08))
                m._absorb:Show()
            else
                m._absorb:Hide()
            end
        end
    end

    -- Font + text colors + positioning (mirrors ApplyTextLayout, scaled)
    do
        local fp    = GF.ResolveFontPath(kind)
        local ff    = GF.ResolveFontFlags(kind)
        local fr, fg, fb = GF.ResolveFontColor(kind)
        local cls   = PREVIEW_CLASSES[_classIdx] or "WARRIOR"
        local nr, ng, nb = GF.ResolveNameColor(kind, cls)
        local textFrameScale = m._previewFrameScale or frameScale or 1
        local function PreviewTextValue(value, minValue)
            return LiveToPreviewValue(ScaleFrameValue(value or 0, textFrameScale, minValue))
        end
        local function PreviewTextFontSize(value)
            return max(6, PreviewTextValue(value or 6, 6))
        end

        -- Text toggle gate: when off (default), hide name/HP/power text
        -- so aura icons underneath read cleanly. When on, render only the
        -- text elements enabled by the active group-frame config.
        local showText = ShouldShowTextPreview()
        if not showText then
            if m._nameFS  then m._nameFS:Hide()  end
            if m._hpFS    then m._hpFS:Hide()    end
            if m._hpLeftFS then m._hpLeftFS:Hide() end
            if m._hpCenterFS then m._hpCenterFS:Hide() end
            if m._hpRightFS then m._hpRightFS:Hide() end
            if m._powerFS then m._powerFS:Hide() end
            if m._powerLeftFS then m._powerLeftFS:Hide() end
            if m._powerCenterFS then m._powerCenterFS:Hide() end
            if m._powerRightFS then m._powerRightFS:Hide() end
        else

        -- Update text layer level from config
        if m._nameLayer and m._health then
            local ntl2 = conf.nameTextLayer or 5
            m._nameLayer:SetFrameLevel(m._health:GetFrameLevel() + ntl2)
        end
        if m._textLayer and m._health then
            local tl2 = conf.textLayer or 5
            m._textLayer:SetFrameLevel(m._health:GetFrameLevel() + tl2)
        end

        if m._nameFS then
            if m._nameLayer and m._nameFS.SetParent and m._nameFS.GetParent and m._nameFS:GetParent() ~= m._nameLayer then
                m._nameFS:SetParent(m._nameLayer)
            end
            m._nameFS:SetFont(fp, PreviewTextFontSize(conf.nameFontSize or 12), ff)
            m._nameFS:SetTextColor(nr or fr, ng or fg, nb or fb, 1)
            m._nameFS:SetText(PREVIEW_NAMES[_classIdx] or "Thrall")
            -- Position from config (anchor + offset, scaled)
            m._nameFS:ClearAllPoints()
            local nAnch = NormalizeTextAnchor(conf.nameAnchor or "LEFT")
            local nox = PreviewTextValue(conf.nameOffsetX or 0)
            local noy = PreviewTextValue(conf.nameOffsetY or 0)
            local pad = PreviewTextValue(3, 1)
            if nAnch == "CENTER" then
                m._nameFS:SetPoint("LEFT", m._health, "LEFT", pad + nox, noy)
                m._nameFS:SetPoint("RIGHT", m._health, "RIGHT", -pad + nox, noy)
                m._nameFS:SetJustifyH("CENTER")
            elseif nAnch == "RIGHT" then
                m._nameFS:SetPoint("LEFT", m._health, "LEFT", pad + nox, noy)
                m._nameFS:SetPoint("RIGHT", m._health, "RIGHT", -pad + nox, noy)
                m._nameFS:SetJustifyH("RIGHT")
            else
                m._nameFS:SetPoint("LEFT", m._health, "LEFT", pad + nox, noy)
                m._nameFS:SetPoint("RIGHT", m._health, "RIGHT", -pad + nox, noy)
                m._nameFS:SetJustifyH("LEFT")
            end
            if conf.showName ~= false then m._nameFS:Show() else m._nameFS:Hide() end
        end
        if m._hpLeftFS or m._hpCenterFS or m._hpRightFS or m._hpFS then
            local hpParent = m._textLayer or m
            if not m._hpCenterFS and m._hpFS then m._hpCenterFS = m._hpFS end
            if not m._hpLeftFS then
                m._hpLeftFS = hpParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif m._hpLeftFS.SetParent then
                m._hpLeftFS:SetParent(hpParent)
            end
            if not m._hpCenterFS then
                m._hpCenterFS = hpParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif m._hpCenterFS.SetParent then
                m._hpCenterFS:SetParent(hpParent)
            end
            if not m._hpRightFS then
                m._hpRightFS = hpParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif m._hpRightFS.SetParent then
                m._hpRightFS:SetParent(hpParent)
            end
            m._hpFS = m._hpCenterFS
            local tl = conf.textLeft or "NONE"
            local tc = conf.textCenter or "NONE"
            local tr = conf.textRight or "NONE"
            local hDelim = conf.textDelimiter or " / "
            local hRev = conf.hpTextReverse
            local hSize = PreviewTextFontSize(conf.hpFontSize or 10)
            local hox = PreviewTextValue(conf.hpOffsetX or 0)
            local hoy = PreviewTextValue(conf.hpOffsetY or 0)
            local hPad = PreviewTextValue(3, 1)

            local function ApplyHPText(fs, mode, point, relPoint, x, justify)
                if not fs then return end
                fs:SetFont(fp, hSize, ff)
                fs:SetTextColor(fr, fg, fb, 0.9)
                fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
                fs:SetText((GF.FormatHealthText and GF.FormatHealthText(mode, 70, 100, hDelim, hRev)) or (HP_SAMPLES[mode] or ""))
                fs:ClearAllPoints()
                fs:SetPoint(point, m._health, relPoint, x, hoy)
                fs:SetJustifyH(justify)
                if mode ~= "NONE" then fs:Show() else fs:Hide() end
            end

            ApplyHPText(m._hpLeftFS, tl, "LEFT", "LEFT", hPad + hox, "LEFT")
            ApplyHPText(m._hpCenterFS, tc, "CENTER", "CENTER", hox, "CENTER")
            ApplyHPText(m._hpRightFS, tr, "RIGHT", "RIGHT", -hPad + hox, "RIGHT")
        end
        -- Power text follows live group-frame fallback: use the power bar
        -- when visible, otherwise anchor to health/mock frame.
        do
            if not m._powerTextLayer then
                local ptl = CreateFrame("Frame", nil, m)
                ptl:SetAllPoints(m)
                m._powerTextLayer = ptl
            end
            if not m._powerCenterFS and m._powerFS then m._powerCenterFS = m._powerFS end
            if not m._powerLeftFS then
                m._powerLeftFS = m._powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif m._powerLeftFS.SetParent then
                m._powerLeftFS:SetParent(m._powerTextLayer)
            end
            if not m._powerCenterFS then
                m._powerCenterFS = m._powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif m._powerCenterFS.SetParent then
                m._powerCenterFS:SetParent(m._powerTextLayer)
            end
            if not m._powerRightFS then
                m._powerRightFS = m._powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif m._powerRightFS.SetParent then
                m._powerRightFS:SetParent(m._powerTextLayer)
            end
            m._powerFS = m._powerCenterFS
            local powerAnchor = (m._power and powerH > 0 and m._power) or m._health or m
            local baseLevel = (m._health and m._health.GetFrameLevel and m._health:GetFrameLevel())
                or (m.GetFrameLevel and m:GetFrameLevel())
                or 0
            local ptl2 = conf.powerTextLayer or 2
            m._powerTextLayer:ClearAllPoints()
            m._powerTextLayer:SetAllPoints(m)
            m._powerTextLayer:SetFrameLevel(baseLevel + ptl2)
            local pcm = conf.powerTextCenter or "NONE"
            local prm = conf.powerTextRight or "NONE"
            local plm = conf.powerTextLeft or "NONE"
            local pDelim = conf.powerTextDelimiter or " / "
            local pSize = PreviewTextFontSize(conf.powerFontSize or 9)
            local pox = PreviewTextValue(conf.powerOffsetX or 0)
            local poy = PreviewTextValue(conf.powerOffsetY or 0)
            local pPad = PreviewTextValue(2, 1)

            local function ApplyPowerText(fs, mode, point, relPoint, x, justify)
                if not fs then return end
                if fp then fs:SetFont(fp, pSize, ff or "") end
                fs:SetText((GF.FormatPowerText and GF.FormatPowerText(mode, 70, 100, pDelim)) or "")
                fs:SetTextColor(fr, fg, fb, 0.9)
                fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
                fs:ClearAllPoints()
                fs:SetPoint(point, powerAnchor, relPoint, x, poy)
                fs:SetJustifyH(justify)
                local powerTextOn = (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) or false
                if powerTextOn and mode ~= "NONE" then fs:Show() else fs:Hide() end
            end

            ApplyPowerText(m._powerLeftFS, plm, "LEFT", "LEFT", pPad + pox, "LEFT")
            ApplyPowerText(m._powerCenterFS, pcm, "CENTER", "CENTER", pox, "CENTER")
            ApplyPowerText(m._powerRightFS, prm, "RIGHT", "RIGHT", -pPad + pox, "RIGHT")
        end
        end  -- end of _visToggles.text else-branch
    end

    -- Corner indicators are refreshed in RefreshPreviewHandles (lazy-created BackdropTemplate frames)

    -- Target/aggro highlight border
    if m._hlBorder then
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        local gfDbKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
        local gfDb = _G.MSUF_DB and _G.MSUF_DB[gfDbKey]
        local function outlineModeToEnabled(mode)
            if mode == nil then return nil end
            if mode == true or mode == false then return mode end
            local n = tonumber(mode)
            if n ~= nil then return n == 1 end
            return nil
        end
        local function outlineModeKey(key)
            if key == "hlAggroEnabled" then return "aggroOutlineMode" end
            if key == "hlDispelEnabled" then return "dispelOutlineMode" end
            return nil
        end
        local function resolveHL(key, fallback)
            local modeKey = outlineModeKey(key)
            if gfDb and gfDb.hlOverride then
                if modeKey then
                    local enabled = outlineModeToEnabled(gfDb[modeKey])
                    if enabled ~= nil then return enabled end
                end
                if gfDb[key] ~= nil then
                    if modeKey then
                        local enabled = outlineModeToEnabled(gfDb[key])
                        if enabled ~= nil then return enabled end
                    end
                    return gfDb[key]
                end
            end
            if gen then
                if modeKey then
                    local enabled = outlineModeToEnabled(gen[modeKey])
                    if enabled ~= nil then return enabled end
                end
                if gen[key] ~= nil then
                    if modeKey then
                        local enabled = outlineModeToEnabled(gen[key])
                        if enabled ~= nil then return enabled end
                    end
                    return gen[key]
                end
            end
            return fallback
        end

        local aggroEn  = resolveHL("hlAggroEnabled",  conf.aggroEnabled)
        local targetEn = resolveHL("hlTargetEnabled", conf.targetIndicator)
        local hlEn = (aggroEn ~= false) or (targetEn ~= false)
        if hlEn then
            local sz  = max(1, tonumber(resolveHL("hlAggroSize", (gen and gen.highlightBorderThickness) or 2)) or 2)
            local ofs = tonumber(resolveHL("hlAggroOffset", 0)) or 0
            local r, g, b = 1, 0.4, 0
            if aggroEn ~= false then
                r = tonumber(resolveHL("hlAggroColorR", 1.0)) or 1.0
                g = tonumber(resolveHL("hlAggroColorG", 0.2)) or 0.2
                b = tonumber(resolveHL("hlAggroColorB", 0.1)) or 0.1
            elseif targetEn ~= false then
                r = tonumber(resolveHL("hlTargetColorR", 1.0)) or 1.0
                g = tonumber(resolveHL("hlTargetColorG", 1.0)) or 1.0
                b = tonumber(resolveHL("hlTargetColorB", 1.0)) or 1.0
            end
            m._hlBorder:ClearAllPoints()
            m._hlBorder:SetPoint("TOPLEFT", m, "TOPLEFT", -ofs, ofs)
            m._hlBorder:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", ofs, -ofs)
            if m._hlEdges then
                m._hlEdges[1]:SetHeight(sz)
                m._hlEdges[2]:SetHeight(sz)
                m._hlEdges[3]:SetWidth(sz)
                m._hlEdges[4]:SetWidth(sz)
                for i = 1, 4 do m._hlEdges[i]:SetColorTexture(r, g, b, 0.6) end
            end
            m._hlBorder:Show()
        else
            m._hlBorder:Hide()
        end
    end

    -- Position snap guide lines (3 horizontal + 3 vertical at anchor axes)
    if m._snapLines then
        local mW = m:GetWidth() or 1
        local mH = m:GetHeight() or 1
        local lines = m._snapLines
        -- Horizontal: top, center, bottom
        lines[1]:ClearAllPoints(); lines[1]:SetPoint("TOPLEFT", m, "TOPLEFT", 0, 0)
        lines[1]:SetSize(mW, 1)
        lines[2]:ClearAllPoints(); lines[2]:SetPoint("LEFT", m, "LEFT", 0, 0)
        lines[2]:SetSize(mW, 1)
        lines[3]:ClearAllPoints(); lines[3]:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 0, 0)
        lines[3]:SetSize(mW, 1)
        -- Vertical: left, center, right
        lines[4]:ClearAllPoints(); lines[4]:SetPoint("TOPLEFT", m, "TOPLEFT", 0, 0)
        lines[4]:SetSize(1, mH)
        lines[5]:ClearAllPoints(); lines[5]:SetPoint("TOP", m, "TOP", 0, 0)
        lines[5]:SetSize(1, mH)
        lines[6]:ClearAllPoints(); lines[6]:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, 0)
        lines[6]:SetSize(1, mH)
    end

    -- Refresh handle positions from config
    GF.RefreshPreviewHandles()
end

------------------------------------------------------------------------
-- Build aura group handles (buff / debuff / externals)
------------------------------------------------------------------------
local AURA_GRP_COLORS = {
    buff      = { {0.23,0.42,0.23}, {0.23,0.35,0.29}, {0.29,0.48,0.23}, {0.20,0.40,0.20}, {0.25,0.45,0.25}, {0.22,0.38,0.22} },
    debuff    = { {0.42,0.13,0.13}, {0.48,0.17,0.17}, {0.38,0.10,0.10}, {0.45,0.15,0.15}, {0.40,0.12,0.12}, {0.50,0.18,0.18} },
    externals = { {0.10,0.35,0.23}, {0.17,0.42,0.29}, {0.12,0.38,0.25}, {0.15,0.40,0.27} },
}

------------------------------------------------------------------------
-- Growth vector table (mirrors MSUF_GF_Auras.lua GROWTH_TABLE).
-- Kept identical to the renderer so preview positioning matches live.
-- px/py = primary axis vector (within a row), sx/sy = secondary axis
-- vector (row wrap direction). `centered` groups grow symmetrically
-- from the anchor center.
------------------------------------------------------------------------
local PREVIEW_GROWTH = {
    RIGHTDOWN = { px =  1, py =  0, sx =  0, sy = -1 },
    RIGHTUP   = { px =  1, py =  0, sx =  0, sy =  1 },
    LEFTDOWN  = { px = -1, py =  0, sx =  0, sy = -1 },
    LEFTUP    = { px = -1, py =  0, sx =  0, sy =  1 },
    DOWNRIGHT = { px =  0, py = -1, sx =  1, sy =  0 },
    DOWNLEFT  = { px =  0, py = -1, sx = -1, sy =  0 },
    UPRIGHT   = { px =  0, py =  1, sx =  1, sy =  0 },
    UPLEFT    = { px =  0, py =  1, sx = -1, sy =  0 },
    CENTER_H  = { px =  1, py =  0, sx =  0, sy = -1, centered = true },
    CENTER_V  = { px =  0, py = -1, sx =  1, sy =  0, centered = true },
}

-- Resolve a growth key to its vector table. Unknown / nil keys fall back
-- to RIGHTDOWN (matches renderer default in GetGrowthVectors).  Legacy
-- aliases "RIGHT"/"LEFT"/"UP"/"DOWN" used in some old presets map to a
-- sensible compound default.
local GROWTH_ALIAS = {
    RIGHT = "RIGHTDOWN",
    LEFT  = "LEFTDOWN",
    UP    = "UPRIGHT",
    DOWN  = "DOWNRIGHT",
}
local function ResolvePreviewGrowth(growth)
    if not growth then return PREVIEW_GROWTH.RIGHTDOWN end
    local g = PREVIEW_GROWTH[growth]
    if g then return g end
    local alias = GROWTH_ALIAS[growth]
    if alias then return PREVIEW_GROWTH[alias] end
    return PREVIEW_GROWTH.RIGHTDOWN
end

------------------------------------------------------------------------
-- Mock spell IDs per group (Platynator-style real-texture preview).
-- These are real spell IDs, resolved at render time through
-- C_Spell.GetSpellTexture with a process-lifetime cache.  Using file IDs
-- directly in SetTexture() fails in Midnight 12.0 — the retail-safe path
-- is to resolve spell → icon path via the C_Spell API (same pattern MSUF
-- uses in HealerBuffs and A2_Reminder).
------------------------------------------------------------------------
local AURA_GRP_ICON_IDS = {
    buff = {
        774,    -- Rejuvenation
        17,     -- Power Word: Shield
        139,    -- Renew
        33076,  -- Prayer of Mending
        33763,  -- Lifebloom
        81749,  -- Atonement
    },
    debuff = {
        589,     -- Shadow Word: Pain (Priest)
        980,     -- Agony (Warlock)
        172,     -- Corruption (Warlock)
        12294,   -- Mortal Strike (Warrior)
        1943,    -- Rupture (Rogue)
        5782,    -- Fear (Warlock)
    },
    externals = {
        6940,    -- Blessing of Sacrifice
        102342,  -- Ironbark
        1022,    -- Blessing of Protection
        116849,  -- Life Cocoon
    },
}

-- Shared spell-texture cache. One lookup per unique spell ID per session.
local _mockSpellTexCache = {}
local function GetMockSpellTexture(spellId)
    local cached = _mockSpellTexCache[spellId]
    if cached then return cached end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then _mockSpellTexCache[spellId] = tex; return tex end
    end
    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellId)
        if icon then _mockSpellTexCache[spellId] = icon; return icon end
    end
    -- Fallback: generic question-mark icon so "never black" is guaranteed
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Mock text values (countdown / stacks) — rendered ONLY on icon[1] of each
-- group so the preview doesn't become "a wall of 3s and 2s".  Single
-- representative icon communicates the position/anchor/offset settings;
-- the remaining icons stay clean so the group's layout + spacing reads.
local AURA_MOCK_CD_TEXT     = "3"
local AURA_MOCK_STACK_TEXT  = "2"

------------------------------------------------------------------------
-- Resolve font for mock aura text. Cold-path: re-read each refresh so
-- live LSM font changes propagate without a rebuild.
------------------------------------------------------------------------
local function GetAuraMockFont(kind)
    local path = (GF.ResolveFontPath and GF.ResolveFontPath(kind)) or "Fonts\\FRIZQT__.TTF"
    local flags = (GF.ResolveFontFlags and GF.ResolveFontFlags(kind)) or "OUTLINE"
    return path, flags
end

local function ReadAuraMockColor(t, dr, dg, db)
    if type(t) ~= "table" then return dr, dg, db, 1 end
    local r = t[1] or t.r
    local g = t[2] or t.g
    local b = t[3] or t.b
    if type(r) ~= "number" then r = dr end
    if type(g) ~= "number" then g = dg end
    if type(b) ~= "number" then b = db end
    return r, g, b, 1
end

local function GetAuraMockBaseCooldownColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if g and g.useCustomFontColor == true then
        local r = g.fontColorCustomR
        local gg = g.fontColorCustomG
        local b = g.fontColorCustomB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, 1
        end
    end
    return 1, 1, 1, 1
end

local function GetAuraMockCooldownColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local nr, ng, nb, na = GetAuraMockBaseCooldownColor()
    local sr, sg, sb, sa = ReadAuraMockColor(g and g.aurasCooldownTextSafeColor, nr, ng, nb)
    if g and g.gfAurasCooldownTextUseBuckets == false then
        return sr, sg, sb, sa
    end

    local remain = tonumber(AURA_MOCK_CD_TEXT) or 3
    local warn = (g and type(g.gfAurasCooldownTextWarningSeconds) == "number") and g.gfAurasCooldownTextWarningSeconds or 15
    local urgent = (g and type(g.gfAurasCooldownTextUrgentSeconds) == "number") and g.gfAurasCooldownTextUrgentSeconds or 5
    if urgent > warn then urgent = warn end

    if remain <= urgent then
        return ReadAuraMockColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.10)
    end
    if remain <= warn then
        return ReadAuraMockColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.20)
    end
    return sr, sg, sb, sa
end

local function GetAuraMockStackColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return ReadAuraMockColor(g and g.aurasStackCountColor, 1, 1, 1)
end

-- Apply cooldown + stack text to a single mock icon. Reads the same gcfg
-- keys the real aura pipeline uses so the options sliders provide live
-- visual feedback on the mock frame.
-- `showText` gates whether the text layer is rendered. Cooldown and stack
-- text still obey the group's own showCooldown/showStacks settings.
------------------------------------------------------------------------
local function ApplyMockIconText(ic, gcfg, kind, showText)
    if not ic or not gcfg then return end

    -- Hide path: if caller doesn't want text on this icon, hide any
    -- FontStrings that may have been created on a previous pass.  Never
    -- destroy them — they're pooled with the icon and reused.
    if not showText then
        if ic._cdText  then ic._cdText:Hide()  end
        if ic._stkText then ic._stkText:Hide() end
        return
    end

    local fontPath, fontFlags = GetAuraMockFont(kind)
    local frameScale = GetPreviewFrameScale()
    local showCd = gcfg.showCooldown ~= false
    local showSt = gcfg.showStacks ~= false

    local cdTarget = ic._cdPreviewFrame
    if not cdTarget then
        cdTarget = CreateFrame("Frame", nil, ic)
        cdTarget:EnableMouse(false)
        ic._cdPreviewFrame = cdTarget
    end
    cdTarget:ClearAllPoints()
    cdTarget:SetAllPoints(ic)

    -- Cooldown text: same settings as live GF auras, scaled with the mock frame.
    local cd = ic._cdText
    if not cd then
        cd = ic:CreateFontString(nil, "OVERLAY")
        ic._cdText = cd
    end
    if showCd then
        local cdFlags = gcfg.cooldownOutline or fontFlags
        local cdSize = max(6, LiveToPreviewValue(ScaleFrameValue(gcfg.cooldownSize or 8, frameScale, 6)))
        if cd.SetFont then cd:SetFont(fontPath, cdSize, cdFlags) end
        cd:SetText(AURA_MOCK_CD_TEXT)
        cd:SetTextColor(GetAuraMockCooldownColor())
        cd:ClearAllPoints()
        local cdAnchor = gcfg.cooldownAnchor or "CENTER"
        local cdOX = LiveToPreviewValue(ScaleFrameValue(gcfg.cooldownOffsetX or 0, frameScale))
        local cdOY = LiveToPreviewValue(ScaleFrameValue(gcfg.cooldownOffsetY or 0, frameScale))
        cd:SetPoint(cdAnchor, cdTarget, cdAnchor, cdOX, cdOY)
        cd:Show()
    else
        cd:Hide()
    end

    -- Stack count text: same settings as live GF auras, scaled with the mock frame.
    local st = ic._stkText
    if not st then
        st = ic:CreateFontString(nil, "OVERLAY")
        ic._stkText = st
    end
    if showSt then
        local stFlags = gcfg.stackOutline or fontFlags
        local stSize = max(6, LiveToPreviewValue(ScaleFrameValue(gcfg.stackSize or 10, frameScale, 6)))
        if st.SetFont then st:SetFont(fontPath, stSize, stFlags) end
        st:SetText(AURA_MOCK_STACK_TEXT)
        st:SetTextColor(GetAuraMockStackColor())
        st:ClearAllPoints()
        local stAnchor = gcfg.stackAnchor or "BOTTOMRIGHT"
        local stOX = LiveToPreviewValue(ScaleFrameValue(gcfg.stackOffsetX or -1, frameScale))
        local stOY = LiveToPreviewValue(ScaleFrameValue(gcfg.stackOffsetY or 1, frameScale))
        st:SetPoint(stAnchor, ic, stAnchor, stOX, stOY)
        st:Show()
    else
        st:Hide()
    end
end

local function BuildAuraGroupHandles(mockFrame)
    local GROUPS = {
        { key = "buff",      section = "buffs",   defAnchor = "BOTTOMLEFT", defSize = 16 },
        { key = "debuff",    section = "debuffs",  defAnchor = "TOPRIGHT",   defSize = 16 },
        { key = "externals", section = "ext",      defAnchor = "CENTER",     defSize = 22 },
    }
    for _, grp in ipairs(GROUPS) do
        local handle = CreateHandle(mockFrame, grp.key, grp.section,
            grp.defSize, grp.defSize, grp.key)
        handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        handle._label:SetText(grp.key:sub(1,1):upper() .. grp.key:sub(2))
        handle._grpKey = grp.key
        handle._defAnchor = grp.defAnchor
        handle._grpIcons = {}
        handle._onDragFinish = function(anchor, offX, offY)
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            if not conf.auras then conf.auras = {} end
            if not conf.auras[grp.key] then conf.auras[grp.key] = {} end
            local cfgX, cfgY = PreviewToConfigOffset(offX, offY)
            conf.auras[grp.key].anchor = anchor
            conf.auras[grp.key].x = cfgX
            conf.auras[grp.key].y = cfgY
            RequestVisualRefresh()
        end
        handle._getCurrentAnchor = function()
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            local ac = conf.auras and conf.auras[grp.key]
            if ac and ResolvePreviewGrowth(ac.growth).centered then return "CENTER" end
            return ac and ac.anchor or grp.defAnchor
        end
        _handles[grp.key] = handle
    end

    local nativeHandle = CreateHandle(mockFrame, "blizzard", "blizzrenderer", 56, 24, "blizzard")
    nativeHandle._label:SetPoint("BOTTOM", nativeHandle, "TOP", 0, 1)
    nativeHandle._label:SetText(Tr("Blizzard locked"))
    nativeHandle._getAnchorFrame = function() return _mockFrame end
    nativeHandle._previewLocked = true
    nativeHandle._getCurrentAnchor = function()
        return "LOCKED"
    end
    nativeHandle._blizzIcons = {}
    _handles.blizzard = nativeHandle
end

------------------------------------------------------------------------
-- Build status icon handles
------------------------------------------------------------------------
local function BuildStatusIconHandles(mockFrame)
    for _, spec in ipairs(STATUS_ICON_SPECS) do
        local handle = CreateHandle(mockFrame, spec.key, "sicons",
            spec.defSize, spec.defSize, "status")
        handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        handle._label:SetText(spec.label)
        if spec.isText then
            local fs = handle:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            fs:SetPoint("CENTER", handle, "CENTER", 0, 0)
            fs:SetJustifyH("CENTER")
            fs:SetText(spec.previewText or spec.label or "TEXT")
            handle._statusText = fs
        else
            local t = handle:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints(handle)
            handle._statusTex = t
        end
        handle._statusSpec = spec
        handle._onDragFinish = function(anchor, offX, offY)
            local sc = _mockFrame and _mockFrame._previewScale or 1
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            conf[spec.anchorKey] = anchor
            conf[spec.xKey] = floor(offX / sc + 0.5)
            conf[spec.yKey] = floor(offY / sc + 0.5)
            RequestVisualRefresh()
        end
        handle._getCurrentAnchor = function()
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            return conf[spec.anchorKey] or spec.defAnchor
        end
        _statusHandles[spec.key] = handle
    end
end

------------------------------------------------------------------------
-- Build spell indicator handles (dynamic per spec)
------------------------------------------------------------------------
function GF.RebuildSIHandles()
    if not _mockFrame or not _getKind then return end
    if not SI then SI = GF.SpellIndicators or _G.MSUF_GF_SpellIndicators end
    -- Hide existing
    for _, h in pairs(_siHandles) do
        h:Hide()
    end
    local kind   = _getKind()
    local conf   = GF.GetConf(kind)
    local siCfg  = conf.spellIndicators
    if not siCfg or siCfg.enabled == false then return end
    if not SI or not SI.SpecDefaults then return end

    local specKey = siCfg.spec or "auto"
    if specKey == "auto" then
        specKey = (SI.ResolveSpec and SI.ResolveSpec(siCfg)) or "RestorationDruid"
    end
    if specKey == "multi" then specKey = "RestorationDruid" end

    local defaults = SI.SpecDefaults[specKey]
    if not defaults then return end

    local specData = siCfg.specs and siCfg.specs[specKey]

    local seen = {}
    local function AddPreviewSpell(spellName, defCfg)
        if not spellName or seen[spellName] then return end
        seen[spellName] = true
        defCfg = defCfg or {}
        local userCfg = specData and specData[spellName]
        local placed
        if userCfg and userCfg.placed ~= nil then
            placed = userCfg.placed
        else
            placed = defCfg.placed
        end
        if placed then
            -- Check user override
            local userPlaced
            if specData and specData[spellName] and specData[spellName].placed then
                userPlaced = specData[spellName].placed
            end
            local cfg = userPlaced or placed

            local h = _siHandles[spellName]
            if not h then
                h = CreateHandle(_mockFrame, spellName, "si",
                    cfg.size or 18, cfg.size or 18, "si")
                h._label:SetPoint("BOTTOM", h, "TOP", 0, 1)
                _siHandles[spellName] = h
            end

            local sz = cfg.size or 18
            h:SetSize(max(6, sz), max(6, sz))
            h._label:SetText(spellName:sub(1, 8))
            h._cfgKey = spellName

            local itype = cfg.type or "icon"
            if not h._siTex then
                h._siTex = h:CreateTexture(nil, "ARTWORK")
            end
            h._siTex:ClearAllPoints()
            h._siTex:SetPoint("CENTER", h, "CENTER", 0, 0)

            if itype == "number" then
                if not h._siValue then
                    h._siValue = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
                    h._siValue:SetPoint("CENTER", h, "CENTER", 0, 0)
                end
                local fontSz = max(8, sz)
                h._siValue:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
                h._siValue:SetText("12")
                h._siValue:Show()
                h._siTex:Hide()
            else
                if h._siValue then h._siValue:Hide() end
                h._siTex:SetSize(sz, sz)
                if itype == "icon" and SI.GetAuraIcon then
                    h._siTex:SetTexture(SI.GetAuraIcon(specKey, spellName))
                    h._siTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                elseif itype == "square" or itype == "bar" then
                    local clr = (defCfg.placed and defCfg.placed.color)
                        or (defCfg.frame and defCfg.frame.color) or {0.5, 0.8, 0.5}
                    h._siTex:SetColorTexture(clr[1] or 0.5, clr[2] or 0.8, clr[3] or 0.5, 1)
                    h._siTex:SetTexCoord(0, 1, 0, 1)
                else
                    h._siTex:SetColorTexture(0.35, 0.55, 0.35, 1)
                    h._siTex:SetTexCoord(0, 1, 0, 1)
                end
                h._siTex:Show()
            end

            -- Position from config (scaled for preview)
            local psc = _mockFrame._previewScale or 1.6
            local anchor = cfg.anchor or "TOPLEFT"
            local offX   = floor(((cfg.x) or 0) * psc + 0.5)
            local offY   = floor(((cfg.y) or 0) * psc + 0.5)
            if itype == "number" then
                local fontSz = max(8, sz)
                local pfs = max(8, floor(fontSz * psc + 0.5))
                local pw = max(18, floor(fontSz * psc * 2.2 + 0.5))
                local ph = max(10, floor(fontSz * psc * 1.4 + 0.5))
                h:SetSize(pw, ph)
                if h._siValue then
                    h._siValue:SetFont("Fonts\\FRIZQT__.TTF", pfs, "OUTLINE")
                end
            else
                local ssz = floor(sz * psc + 0.5)
                h:SetSize(max(6, ssz), max(6, ssz))
                h._siTex:SetSize(ssz, ssz)
            end
            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(((_mockFrame._health and _mockFrame._health.GetFrameLevel and _mockFrame._health:GetFrameLevel()) or (_mockFrame:GetFrameLevel() + 1)) + (siCfg.layer or 9))
            h:SetShown(_visToggles.si ~= false)

            -- Drag writes to per-spell config (unscaled)
            local capturedSpec = specKey
            local capturedSpell = spellName
            h._onDragFinish = function(anc, ox, oy)
                local dsc = _mockFrame and _mockFrame._previewScale or 1
                local k = _getKind and _getKind() or "party"
                local c = GF.GetConf(k)
                if not c.spellIndicators then c.spellIndicators = { enabled = true, spec = "auto", specs = {} } end
                local si = c.spellIndicators
                if not si.specs then si.specs = {} end
                if not si.specs[capturedSpec] then si.specs[capturedSpec] = {} end
                if not si.specs[capturedSpec][capturedSpell] then
                    si.specs[capturedSpec][capturedSpell] = {}
                end
                local entry = si.specs[capturedSpec][capturedSpell]
                if not entry.placed then
                    entry.placed = {}
                    local def = defaults[capturedSpell] and defaults[capturedSpell].placed
                    if def then
                        for dk, dv in pairs(def) do entry.placed[dk] = dv end
                    end
                end
                entry.placed.anchor = anc
                entry.placed.x = floor(ox / dsc + 0.5)
                entry.placed.y = floor(oy / dsc + 0.5)
                RequestVisualRefresh()
            end
            h._getCurrentAnchor = function()
                local k = _getKind and _getKind() or "party"
                local c = GF.GetConf(k)
                local si = c.spellIndicators
                local sp = si and si.specs and si.specs[capturedSpec]
                local e = sp and sp[capturedSpell]
                local p = e and e.placed
                return p and p.anchor
            end
        end
    end
    local ordered = SI.TrackableAuras and SI.TrackableAuras[specKey]
    if ordered then
        for _, info in ipairs(ordered) do
            AddPreviewSpell(info.name, defaults[info.name])
        end
    end
    for spellName, defCfg in pairs(defaults) do
        AddPreviewSpell(spellName, defCfg)
    end
    if specData then
        for spellName in pairs(specData) do
            AddPreviewSpell(spellName, defaults[spellName])
        end
    end
end

------------------------------------------------------------------------
-- Build private aura handle
------------------------------------------------------------------------
local function BuildPrivateAuraHandle(mockFrame)
    local handle = CreateHandle(mockFrame, "private", "priv", 16, 16, "private")
    handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
    handle._label:SetText(Tr("Private"))
    handle._onDragFinish = function(anchor, offX, offY)
        local kind = _getKind and _getKind() or "party"
        local conf = GF.GetConf(kind)
        if not conf.privateAuras then conf.privateAuras = {} end
        local cfgX, cfgY = PreviewToConfigOffset(offX, offY)
        conf.privateAuras.anchor = anchor
        conf.privateAuras.x = cfgX
        conf.privateAuras.y = cfgY
        RequestVisualRefresh()
    end
    handle._getCurrentAnchor = function()
        local kind = _getKind and _getKind() or "party"
        local conf = GF.GetConf(kind)
        local pa = conf.privateAuras
        return pa and pa.anchor or "TOPRIGHT"
    end
    _handles.private = handle
end

------------------------------------------------------------------------
-- Build text handles
------------------------------------------------------------------------
local function IsTextModeActive(mode)
    return mode ~= nil and mode ~= "NONE"
end

local function PickTextSlotAnchor(leftMode, centerMode, rightMode)
    if IsTextModeActive(centerMode) then return "CENTER" end
    if IsTextModeActive(leftMode) then return "LEFT" end
    if IsTextModeActive(rightMode) then return "RIGHT" end
    return "CENTER"
end

local function GetTextHandleAnchor(textKey, conf)
    if textKey == "nameText" then
        return NormalizeTextAnchor((conf and conf.nameAnchor) or "LEFT")
    elseif textKey == "hpText" then
        return PickTextSlotAnchor(conf and conf.textLeft, conf and conf.textCenter, conf and conf.textRight)
    end
    return PickTextSlotAnchor(conf and conf.powerTextLeft, conf and conf.powerTextCenter, conf and conf.powerTextRight)
end

local function GetTextHandleTarget(textKey)
    if not _mockFrame then return nil end
    if textKey == "powerText" and _mockFrame._power and _mockFrame._power.IsShown and _mockFrame._power:IsShown() then
        return _mockFrame._power
    end
    return _mockFrame._health or _mockFrame
end

local function GetTextHandleFontString(textKey, anchor)
    if not _mockFrame then return nil end
    if textKey == "nameText" then return _mockFrame._nameFS end
    if textKey == "hpText" then
        if anchor == "LEFT" then return _mockFrame._hpLeftFS end
        if anchor == "RIGHT" then return _mockFrame._hpRightFS end
        return _mockFrame._hpCenterFS or _mockFrame._hpFS
    end
    if anchor == "LEFT" then return _mockFrame._powerLeftFS end
    if anchor == "RIGHT" then return _mockFrame._powerRightFS end
    return _mockFrame._powerCenterFS or _mockFrame._powerFS
end

local function GetTextHandleConfigKeys(textKey)
    if textKey == "nameText" then return "nameOffsetX", "nameOffsetY" end
    if textKey == "hpText" then return "hpOffsetX", "hpOffsetY" end
    return "powerOffsetX", "powerOffsetY"
end

local function GetTextHandlePad(textKey, anchor)
    local base = (textKey == "powerText") and 2 or 3
    local pad = LiveToPreviewValue(ScaleFrameValue(base, GetPreviewFrameScale(), 1))
    if anchor == "LEFT" then return pad end
    if anchor == "RIGHT" then return -pad end
    return 0
end

local function IsTextHandleEnabled(textKey, conf)
    if textKey == "nameText" then
        return not conf or conf.showName ~= false
    elseif textKey == "hpText" then
        return (not conf or conf.showHPText ~= false)
            and (IsTextModeActive(conf and conf.textLeft)
                or IsTextModeActive(conf and conf.textCenter)
                or IsTextModeActive(conf and conf.textRight))
    end
    return (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(_getKind and _getKind() or "party", conf) or false)
        and (IsTextModeActive(conf and conf.powerTextLeft)
            or IsTextModeActive(conf and conf.powerTextCenter)
            or IsTextModeActive(conf and conf.powerTextRight))
end

local function MeasureTextHandle(fs, fallbackW, fallbackH)
    local w = fallbackW or 48
    local h = fallbackH or 14
    if fs and fs.GetStringWidth then
        local sw = fs:GetStringWidth()
        if sw and sw > 0 then w = max(w, RoundToNearest(sw) + 10) end
    end
    if fs and fs.GetStringHeight then
        local sh = fs:GetStringHeight()
        if sh and sh > 0 then h = max(h, RoundToNearest(sh) + 6) end
    end
    return max(24, w), max(12, h)
end

local function SaveTextHandlePosition(handle, textKey, anchor, offX, offY)
    local kind = _getKind and _getKind() or "party"
    local conf = GF.GetConf(kind)
    if not conf then return end
    local xKey, yKey = GetTextHandleConfigKeys(textKey)
    local cfgX, cfgY = PreviewToHandleConfigOffset(handle, offX, offY)
    conf[xKey] = cfgX
    conf[yKey] = cfgY
    if textKey == "nameText" then
        conf.nameAnchor = NormalizeTextAnchor(anchor)
    end
    if GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_LAYOUT or 0x04) end
    if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
    if GF._RefreshOptionWidgets then GF._RefreshOptionWidgets() end
end

local function BuildTextHandles(mockFrame)
    local specs = {
        { key = "nameText", label = "Name" },
        { key = "hpText", label = "HP" },
        { key = "powerText", label = "Power" },
    }
    for _, spec in ipairs(specs) do
        local textKey = spec.key
        local handle = CreateHandle(mockFrame, textKey, "text", 54, 16, "text")
        handle._label:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        handle._label:SetText(spec.label)
        handle._textKey = textKey
        handle._getAnchorFrame = function(self)
            return GetTextHandleTarget(self._textKey)
        end
        handle._getCurrentAnchor = function(self)
            local kind = _getKind and _getKind() or "party"
            local conf = GF.GetConf(kind)
            return GetTextHandleAnchor(self._textKey, conf)
        end
        handle._onDragFinish = function(anchor, offX, offY)
            SaveTextHandlePosition(handle, textKey, anchor, offX, offY)
        end
        _textHandles[textKey] = handle
    end
end

-- Refresh all handle positions from config
------------------------------------------------------------------------
function GF.RefreshPreviewHandles()
    if not _mockFrame or not _getKind then return end
    local kind = _getKind()
    local conf = GF.GetConf(kind)
    local sc   = _mockFrame._previewScale or 1.6
    local frameScale = _mockFrame._previewFrameScale or 1
    -- Dynamic content scale: simulates icon shrink for large raids (mirrors live GetDynamicScale)
    local dynScale = GF.GetPreviewDynamicScale and GF.GetPreviewDynamicScale(conf, kind) or 1

    -- Aura groups mirror the live renderer: icons may intentionally be
    -- larger than the unit frame, especially centered defensive groups.
    for _, grpKey in ipairs({"buff", "debuff", "externals"}) do
        local h = _handles[grpKey]
        if h then
            local ac = conf.auras and conf.auras[grpKey]
            local anchor  = (ac and ac.anchor) or h._defAnchor or "BOTTOMLEFT"
            local offX, offY = ConfigToPreviewOffset((ac and ac.x) or 0, (ac and ac.y) or 0)
            local anchorTarget = (ac and ac.behindBar and _mockFrame._health) or _mockFrame
            h._getAnchorFrame = function()
                local k = _getKind and _getKind() or "party"
                local c = GF.GetConf(k)
                local cfg = c and c.auras and c.auras[grpKey]
                return ((cfg and cfg.behindBar and _mockFrame and _mockFrame._health) or _mockFrame)
            end

            local rawSz   = (ac and ac.size) or (grpKey == "externals" and 18 or 14)
            local liveSz  = ScaleFrameValue(rawSz, dynScale * frameScale, 8)
            local sz      = max(6, LiveToPreviewValue(liveSz))

            -- Realistic defaults: 3 icons per row (not 6) so a live preview
            -- with config-less defaults matches typical user setups.
            local perRow  = (ac and ac.perRow) or (grpKey == "externals" and 2 or 3)
            local rawSpc  = (ac and ac.spacing) or 1
            local spacing = max(0, LiveToPreviewValue(ScaleFrameValue(rawSpc, frameScale, 0)))
            local maxIcons = (ac and ac.max) or (grpKey == "externals" and 2 or 3)
            local en = not ac or ac.enabled ~= false
            local nativeGroup = IsNativeAuraHandle(kind, grpKey)

            -- Growth direction drives where icons flow from the anchor.
            -- Must match the canonical renderer (MSUF_GF_Auras.lua
            -- PositionIcon) exactly so preview = live.
            local gv = ResolvePreviewGrowth(ac and ac.growth)
            local isCentered = gv.centered == true
            local effectiveAnchor = isCentered and "CENTER" or anchor

            -- Ensure icon pool (Platynator-style: real spell icon + soft border + mock text on icon[1])
            local pool = h._grpIcons or {}
            h._grpIcons = pool
            local iconIDs = AURA_GRP_ICON_IDS[grpKey] or AURA_GRP_ICON_IDS.buff

            -- Resolve per-group config used for mock text (live-feedback for
            -- Beta 4 cooldown/stack sliders). Fallback to empty table so the
            -- ApplyMockIconText defaults take effect.
            local gcfg = (ac and ac) or {}

            for i = 1, maxIcons do
                local ic = pool[i]
                if not ic then
                    -- Use a Frame so we can parent a border + FontStrings
                    ic = CreateFrame("Frame", nil, h)
                    ic:SetFrameLevel(h:GetFrameLevel() + 1)

                    local tex = ic:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints(ic)
                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Blizzard-style edge trim
                    ic._tex = tex
                    ic.texture = tex
                    ic._msufGFIsPreviewAura = true

                    -- Soft charcoal edge (not pure black) so a mock icon
                    -- never reads as a solid black block even if the spell
                    -- texture fails to resolve.  Drawn at BORDER layer so
                    -- the icon texture in ARTWORK covers the center.
                    local bd = ic:CreateTexture(nil, "BORDER")
                    bd:SetTexture(W8)
                    bd:SetVertexColor(0.10, 0.10, 0.12, 0.8)
                    ic._border = bd

                    pool[i] = ic
                end

                -- Resolve real spell icon path from spell ID (cached)
                local spellId = iconIDs[((i - 1) % #iconIDs) + 1]
                local path = GetMockSpellTexture(spellId)
                ic._tex:SetTexture(path)
                -- Disabled state: dim icons to grayscale-tint so the user
                -- sees "this layer is off" while the handle stays clickable
                -- for navigation to the matching Options section. Live
                -- (en=true) renders icons at full color.
                if en then
                    ic._tex:SetVertexColor(1, 1, 1, 1)
                else
                    ic._tex:SetVertexColor(0.40, 0.40, 0.45, 0.55)
                end

                ic:SetSize(sz, sz)
                ic.texture = ic._tex
                ic._msufGFMasqueKind = kind

                local masqueActive = false
                if GF.Masque and GF.Masque.SyncIconGeometry then
                    masqueActive = GF.Masque.SyncIconGeometry(ic, sz, kind) == true
                end
                if masqueActive then
                    ic._border:Hide()
                else
                    ic._tex:ClearAllPoints()
                    ic._tex:SetAllPoints(ic)
                    ic._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    ic._border:Show()
                    -- 1px border at preview scale (resolves to exactly 1 screen px)
                    local bw = max(1, floor(sc * 0.5 + 0.5))
                    ic._border:ClearAllPoints()
                    ic._border:SetPoint("TOPLEFT", ic, "TOPLEFT", -bw, bw)
                    ic._border:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", bw, -bw)
                end

                -- Mock countdown/stack text rendered on every icon so the
                -- user gets live feedback on every drag of the offset
                -- sliders.  Gated by the "CD/Stack" sidebar toggle (+
                -- solo-on-auraText override).  Default ON.
                local showAuraText = (_visToggles.auraText ~= false) or (_soloKey == "auraText")
                ApplyMockIconText(ic, gcfg, kind, showAuraText)
                if masqueActive and GF.Masque and GF.Masque.SyncIconGeometry then
                    GF.Masque.SyncIconGeometry(ic, sz, kind)
                end

                ic:Show()
            end
            for i = maxIcons + 1, #pool do
                pool[i]:Hide()
            end

            -- Canonical positioning (mirrors MSUF_GF_Auras.lua PositionIcon):
            -- Each icon is anchored at `anchor` of the container, offset by
            -- the growth vector × step.  Icon[1] sits exactly on the
            -- container's anchor corner (zero offset), subsequent icons
            -- flow along the primary axis, wrapping to the secondary axis
            -- every perRow.  This matches live exactly.
            local step = sz + spacing
            if isCentered and maxIcons > 0 then
                -- Centered growth: icons spread outward from the anchor
                -- point along the primary axis (mirrors renderer line
                -- 831-845).  Always single-row since centered groups don't
                -- wrap.
                local isH = (gv.px ~= 0)
                local totalPrimary = maxIcons * sz + (maxIcons - 1) * spacing
                local halfOfs = totalPrimary * 0.5
                for i = 1, maxIcons do
                    local ic = pool[i]
                    if ic then
                        ic:ClearAllPoints()
                        local col = i - 1
                        if isH then
                            local ox = col * step - halfOfs + sz * 0.5
                            ic:SetPoint("CENTER", h, "CENTER", ox, 0)
                        else
                            local oy = -(col * step - halfOfs) - sz * 0.5
                            ic:SetPoint("CENTER", h, "CENTER", 0, oy)
                        end
                    end
                end
            else
                for i = 1, maxIcons do
                    local ic = pool[i]
                    if ic then
                        ic:ClearAllPoints()
                        local col = (i - 1) % perRow
                        local row = floor((i - 1) / perRow)
                        local ox = col * step * gv.px + row * step * gv.sx
                        local oy = col * step * gv.py + row * step * gv.sy
                        ic:SetPoint(anchor, h, anchor, ox, oy)
                    end
                end
            end

            -- Handle bounding box: just large enough to cover all positioned
            -- icons in every direction.  Used only as drag-hit area — actual
            -- icon placement is driven by the canonical positioning above.
            -- We size it to the primary × secondary extent plus the icon
            -- diameter so edge icons aren't clipped from the handle rect.
            local cols = min(perRow, maxIcons)
            local rows = max(1, floor((maxIcons - 1) / max(1, cols)) + 1)
            local extentP = cols * sz + max(0, cols - 1) * spacing
            local extentS = rows * sz + max(0, rows - 1) * spacing
            local handleW, handleH
            if gv.px ~= 0 then
                handleW, handleH = extentP, extentS
            else
                handleW, handleH = extentS, extentP
            end
            if isCentered then
                -- Centered handles need to span the full primary extent
                -- (icons spread both directions from anchor center).
                local centeredExtent = maxIcons * sz + max(0, maxIcons - 1) * spacing
                if gv.px ~= 0 then
                    handleW = centeredExtent
                    handleH = sz
                else
                    handleW = sz
                    handleH = centeredExtent
                end
            end
            h:SetSize(max(sz, handleW), max(sz, handleH))

            h:ClearAllPoints()
            h:SetPoint(effectiveAnchor, anchorTarget, effectiveAnchor, offX, offY)
            h:SetFrameLevel(((_mockFrame._health and _mockFrame._health.GetFrameLevel and _mockFrame._health:GetFrameLevel()) or (_mockFrame:GetFrameLevel() + 1)) + (ac and ac.layer or (grpKey == "buff" and 5 or (grpKey == "debuff" and 6 or 7))))
            -- Per-category handles are custom-layout handles. They are visible
            -- whenever Blizzard does not own this exact aura type.
            h:SetShown(_visToggles[grpKey] ~= false and not nativeGroup)
            -- Label tint reflects en state: bright = live, dim = disabled.
            -- Cheap; HANDLE_COLORS is a small file-scope literal table.
            if h._label then
                local lc = HANDLE_COLORS[grpKey] or HANDLE_COLORS.status
                if nativeGroup then
                    h._label:SetTextColor(0.36, 0.62, 0.95, 0.95)
                elseif en then
                    h._label:SetTextColor(lc[1], lc[2], lc[3], 0.9)
                else
                    h._label:SetTextColor(lc[1] * 0.5, lc[2] * 0.5, lc[3] * 0.5, 0.6)
                end
            end
            UpdateCoordDisplay(nil)
        end
    end

    -- Single native Blizzard aura block preview. It is locked because
    -- Blizzard owns the final native aura placement.
    do
        local h = _handles.blizzard
        if h then
            local nativeActive = IsNativeRendererActive(kind)
            if not nativeActive then
                h:Hide()
            else
                local auras = conf.auras or {}
                local anchor = "CENTER"
                local offX, offY = 0, 0

                local types = auras.blizzardTypes or {}
                local buffOn = IsNativeAuraHandle(kind, "buff") or (type(types) ~= "table" and true)
                local debuffOn = IsNativeAuraHandle(kind, "debuff") or (type(types) ~= "table" and true)
                local extOn = IsNativeAuraHandle(kind, "externals") or (type(types) ~= "table" and true)
                local dispelOn = false
                if GF.IsBlizzardAuraTypeEnabled then
                    dispelOn = GF.IsBlizzardAuraTypeEnabled(conf, "dispels") == true
                else
                    dispelOn = type(types) ~= "table" or types.dispels ~= false
                end
                local pa = conf.privateAuras or {}
                local privateOn = IsNativeAuraHandle(kind, "private") or (type(types) ~= "table" and pa.enabled ~= false)
                local function CountValue(value, def)
                    local n = RoundToNearest(tonumber(value) or def or 0)
                    if n < 0 then return 0 end
                    return n
                end
                local buffMax = buffOn and CountValue(auras.buff and auras.buff.max, 6) or 0
                local debuffMax = debuffOn and CountValue(auras.debuff and auras.debuff.max, 6) or 0
                local privateMax = privateOn and CountValue(pa.max, 4) or 0
                local dispelMax = dispelOn and 3 or 0
                debuffMax = max(debuffMax, privateMax, dispelMax)
                local extMax = extOn and 1 or 0
                local nativeScale = dynScale or 1
                local liveSz
                if GF.GetBlizzardAuraIconSize then
                    liveSz = GF.GetBlizzardAuraIconSize(conf, nativeScale, frameScale)
                else
                    liveSz = ScaleFrameValue(auras.blizzardIconSize or 20, nativeScale * frameScale, 8)
                end
                local extCfg = auras.externals or {}
                local liveBigSz = extOn and ScaleFrameValue(extCfg.size or liveSz or 20, nativeScale * frameScale, 8) or liveSz
                local sz = max(8, LiveToPreviewValue(liveSz or 20))
                local bigSz = max(8, LiveToPreviewValue(liveBigSz or liveSz or 20))
                local gap = max(1, LiveToPreviewValue(ScaleFrameValue(2, frameScale, 0)))

                local buffEntries, harmfulEntries = {}, {}
                local function AddEntries(out, entryKind, count, iconSize, firstTag, tagColor)
                    for i = 1, count do
                        out[#out + 1] = {
                            kind = entryKind,
                            size = iconSize,
                            seq = i,
                            tag = (i == 1) and firstTag or nil,
                            tagColor = tagColor,
                        }
                    end
                end
                AddEntries(buffEntries, "buff", buffMax, sz, "BUFFS", { 0.55, 1.00, 0.55 })

                local harmfulMarks = {}
                if debuffOn then harmfulMarks[#harmfulMarks + 1] = { kind = "debuff", tag = "DEBUFFS", color = { 1.00, 0.45, 0.45 } } end
                if dispelOn then harmfulMarks[#harmfulMarks + 1] = { kind = "debuff", tag = "DISPEL", color = { 0.55, 0.78, 1.00 } } end
                if privateOn then harmfulMarks[#harmfulMarks + 1] = { kind = "debuff", tag = "PRIVATE", color = { 0.78, 0.78, 0.84 } } end
                for i = 1, debuffMax do
                    local mark = harmfulMarks[i]
                    harmfulEntries[#harmfulEntries + 1] = {
                        kind = (mark and mark.kind) or "debuff",
                        size = sz,
                        seq = i,
                        tag = mark and mark.tag or nil,
                        tagColor = mark and mark.color or nil,
                    }
                end
                AddEntries(harmfulEntries, "externals", extMax, bigSz, "DEF", { 0.45, 1.00, 0.78 })
                if #buffEntries == 0 and #harmfulEntries == 0 then
                    AddEntries(harmfulEntries, "debuff", 1, sz, "DEBUFFS", { 1.00, 0.45, 0.45 })
                end

                local function Metrics(entries, cellSize)
                    local count = #entries
                    if count <= 0 then return 0, 0, 0 end
                    local cols = min(6, count)
                    local rows = floor((count - 1) / cols) + 1
                    return cols * cellSize + max(0, cols - 1) * gap,
                           rows * cellSize + max(0, rows - 1) * gap,
                           cols
                end

                local org = auras.blizzardOrganizationType or auras.blizzardOrganization or "default"
                local cellHarm = max(sz, bigSz)
                local buffW, buffH, buffCols = Metrics(buffEntries, sz)
                local harmW, harmH, harmCols = Metrics(harmfulEntries, cellHarm)
                local splitRows = (org == "BUFFS_TOP_DEBUFFS_BOTTOM" or org == "BOTTOM")
                local splitCols = (org == "BUFFS_RIGHT_DEBUFFS_LEFT" or org == "LEFT" or org == "RIGHT")
                local w, hh
                if splitRows then
                    w = max(sz, buffW, harmW)
                    hh = max(sz, buffH + harmH + ((buffH > 0 and harmH > 0) and gap or 0))
                elseif splitCols then
                    w = max(sz, buffW + harmW + ((buffW > 0 and harmW > 0) and gap or 0))
                    hh = max(sz, buffH, harmH)
                else
                    local allCount = #buffEntries + #harmfulEntries
                    local cell = max(sz, bigSz)
                    local cols = min(6, allCount)
                    local rows = floor((allCount - 1) / cols) + 1
                    w = max(sz, cols * cell + max(0, cols - 1) * gap)
                    hh = max(sz, rows * cell + max(0, rows - 1) * gap)
                end

                h:SetSize(w, hh)
                h:ClearAllPoints()
                h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
                local Native = ns and ns.MSUF_AuraNative
                local layerCfg = {
                    containerStrata = auras.blizzardContainerStrata or "AUTO",
                    containerFrameLevel = auras.blizzardContainerFrameLevel,
                    privateLayerFix = auras.blizzardPrivateLayerFix ~= false,
                    privateLayerOffset = auras.blizzardPrivateLayerOffset or 1,
                }
                if Native and Native.ApplyBlizzardAuraContainerLayer then
                    if Native.ApplyBlizzardAuraContainerLayerForConfig then
                        Native.ApplyBlizzardAuraContainerLayerForConfig(h, kind, layerCfg, _mockFrame, _mockFrame)
                    else
                        Native.ApplyBlizzardAuraContainerLayer(h, kind, {
                            config = layerCfg,
                            parent = _mockFrame,
                            levelParent = _mockFrame,
                        })
                    end
                    if privateOn and layerCfg.privateLayerFix ~= false and Native.EnsurePrivateAuraHost then
                        if Native.EnsurePrivateAuraHostForConfig then
                            Native.EnsurePrivateAuraHostForConfig(h, kind, layerCfg)
                        else
                            Native.EnsurePrivateAuraHost(h, kind, { config = layerCfg })
                        end
                    elseif Native.ClearPrivateAuraHost then
                        Native.ClearPrivateAuraHost(h)
                    end
                else
                    h:SetFrameLevel(_mockFrame:GetFrameLevel() + 10)
                end

                local pool = h._blizzIcons or {}
                h._blizzIcons = pool
                local tagPool = h._blizzTags or {}
                h._blizzTags = tagPool
                local poolIndex = 1
                local function PlaceEntry(entry, x, y, cellSize)
                    local idx = poolIndex
                    local tex = pool[idx]
                    if not tex then
                        tex = h:CreateTexture(nil, "ARTWORK")
                        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        pool[idx] = tex
                    end
                    local iconIDs = AURA_GRP_ICON_IDS[entry.kind] or AURA_GRP_ICON_IDS.debuff
                    local spellId = iconIDs[((entry.seq - 1) % #iconIDs) + 1]
                    local iconSize = entry.size or sz
                    local pad = max(0, RoundToNearest((cellSize - iconSize) * 0.5))
                    tex:SetTexture(GetMockSpellTexture(spellId))
                    tex:SetSize(iconSize, iconSize)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", h, "TOPLEFT", x + pad, -(y + pad))
                    tex:SetVertexColor(1, 1, 1, 0.92)
                    tex:Show()

                    local tag = tagPool[idx]
                    if not tag then
                        tag = h:CreateFontString(nil, "OVERLAY")
                        tag:SetFont("Fonts\\FRIZQT__.TTF", 6, "OUTLINE")
                        tagPool[idx] = tag
                    end
                    if entry.tag then
                        local tc = entry.tagColor or { 1, 1, 1 }
                        tag:SetText(entry.tag)
                        tag:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, 1)
                        tag:ClearAllPoints()
                        tag:SetPoint("TOPLEFT", h, "TOPLEFT", x + pad + 1, -(y + pad + 1))
                        tag:Show()
                    else
                        tag:Hide()
                    end

                    poolIndex = idx + 1
                end
                local function PlaceGrid(entries, startX, startY, cellSize, cols)
                    if #entries <= 0 then return end
                    cols = max(1, cols or min(6, #entries))
                    for i, entry in ipairs(entries) do
                        local col = (i - 1) % cols
                        local row = floor((i - 1) / cols)
                        PlaceEntry(entry, startX + col * (cellSize + gap), startY + row * (cellSize + gap), cellSize)
                    end
                end

                if splitRows then
                    PlaceGrid(buffEntries, 0, 0, sz, buffCols)
                    PlaceGrid(harmfulEntries, 0, buffH + ((buffH > 0 and harmH > 0) and gap or 0), cellHarm, harmCols)
                elseif splitCols then
                    PlaceGrid(harmfulEntries, 0, 0, cellHarm, harmCols)
                    PlaceGrid(buffEntries, harmW + ((buffW > 0 and harmW > 0) and gap or 0), 0, sz, buffCols)
                else
                    local allEntries = {}
                    for _, entry in ipairs(buffEntries) do allEntries[#allEntries + 1] = entry end
                    for _, entry in ipairs(harmfulEntries) do allEntries[#allEntries + 1] = entry end
                    PlaceGrid(allEntries, 0, 0, max(sz, bigSz), min(6, #allEntries))
                end

                for i = poolIndex, #pool do
                    local tex = pool[i]
                    if tex then tex:Hide() end
                end
                for i = poolIndex, #tagPool do
                    local tag = tagPool[i]
                    if tag then tag:Hide() end
                end
                if h._label then
                    h._label:SetTextColor(0.36, 0.62, 0.95, 0.95)
                end
                h:SetShown(_visToggles.blizzard ~= false)
            end
        end
    end

    -- Status icons (real textures from icon style, layer = z-order)
    local baseLvl = _mockFrame:GetFrameLevel() + 1
    for _, spec in ipairs(STATUS_ICON_SPECS) do
        local h = _statusHandles[spec.key]
        if h then
            local anchor = conf[spec.anchorKey] or spec.defAnchor
            local offX   = floor(((conf[spec.xKey]) or 0) * sc + 0.5)
            local offY   = floor(((conf[spec.yKey]) or 0) * sc + 0.5)
            local sz     = floor(((conf[spec.sizeKey]) or spec.defSize) * sc + 0.5)
            local layer  = (conf[spec.layerKey]) or 1
            if spec.isText then
                h:SetSize(max(42, sz * 4), max(12, sz + 4))
            else
                h:SetSize(max(6, sz), max(6, sz))
            end
            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(baseLvl + layer)
            local en = (conf[spec.key] ~= false)
            -- Visibility = sidebar toggle plus optional Status Icons focus
            -- filter. Disabled-config handles still need to be clickable for
            -- click-to-navigate whenever they are in the active preview set.
            h:SetShown(ShouldShowStatusPreviewHandle(spec.key))

            -- Apply real texture
            local tex = h._statusTex
            if spec.isText then
                local fs = h._statusText
                if fs then
                    local fp, ff = GetAuraMockFont(kind)
                    fs:SetFont(fp, max(8, sz), ff or "OUTLINE")
                    fs:SetText(spec.previewText or spec.label or "TEXT")
                    fs:SetTextColor(en and 1 or 0.45, en and 1 or 0.45, en and 1 or 0.50, en and 1 or 0.60)
                    fs:ClearAllPoints()
                    fs:SetPoint("CENTER", h, "CENTER", 0, 0)
                    fs:Show()
                end
                if tex then tex:Hide() end
            elseif tex then
                local sKey = spec.key
                local l, r, t, b = 0, 1, 0, 1
                local path
                if sKey == "roleIcon" and GF.GetRoleTexture then
                    path, l, r, t, b = GF.GetRoleTexture(kind, "HEALER")
                elseif sKey == "leaderIcon" and GF.GetLeaderTexture then
                    path, l, r, t, b = GF.GetLeaderTexture(kind)
                elseif sKey == "assistIcon" and GF.GetAssistTexture then
                    path, l, r, t, b = GF.GetAssistTexture(kind)
                elseif sKey == "raidMarker" then
                    path = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
                    l, r, t, b = 0, 0.25, 0, 0.25 -- star marker
                elseif sKey == "readyCheckIcon" then
                    path = "Interface\\RaidFrame\\ReadyCheck-Ready"
                elseif sKey == "summonIcon" then
                    path = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
                elseif sKey == "resurrectIcon" then
                    path = "Interface\\RaidFrame\\Raid-Icon-Rez"
                elseif sKey == "phaseIcon" then
                    path = "Interface\\TargetingFrame\\UI-PhasingIcon"
                end
                if path then
                    tex:SetTexture(path)
                    tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                    -- Live = full color, disabled = dim grayscale tint.
                    if en then
                        tex:SetVertexColor(1, 1, 1, 1)
                    else
                        tex:SetVertexColor(0.40, 0.40, 0.45, 0.55)
                    end
                end
            end
            -- Label tint to mirror disabled state on status handles.
            if h._label then
                local lc = HANDLE_COLORS.status
                if en then
                    h._label:SetTextColor(lc[1], lc[2], lc[3], 0.9)
                else
                    h._label:SetTextColor(lc[1] * 0.5, lc[2] * 0.5, lc[3] * 0.5, 0.6)
                end
            end
        end
    end

    -- Private auras
    do
        local h = _handles.private
        if h then
            local pa = conf.privateAuras or {}
            local anchor = pa.anchor or "TOPRIGHT"
            local offX, offY = ConfigToPreviewOffset(pa.x or 0, pa.y or 0)
            local livePaSz = ScaleFrameValue(pa.size or 20, frameScale, 8)
            local paSz = max(6, LiveToPreviewValue(livePaSz))
            local paMax = RoundToNearest(tonumber(pa.max) or 4)
            if paMax < 0 then paMax = 0 end
            if paMax > 12 then paMax = 12 end
            local paSpacing = max(0, LiveToPreviewValue(ScaleFrameValue(pa.spacing or 1, frameScale, 0)))
            local dir = pa.direction or "LEFT"
            local isVertical = (dir == "TOP" or dir == "BOTTOM")
            local totalPrimary = paMax > 0 and (paMax * paSz + max(0, paMax - 1) * paSpacing) or paSz
            if isVertical then
                h:SetSize(max(6, paSz), max(6, totalPrimary))
            else
                h:SetSize(max(6, totalPrimary), max(6, paSz))
            end
            h:ClearAllPoints()
            h:SetPoint(anchor, _mockFrame, anchor, offX, offY)
            h:SetFrameLevel(((_mockFrame._health and _mockFrame._health.GetFrameLevel and _mockFrame._health:GetFrameLevel()) or (_mockFrame:GetFrameLevel() + 1)) + (pa.layer or 8))
            if not h._paIcons then
                h._paIcons = {}
            end
            local paEn = pa.enabled ~= false
            local paR, paG, paB, paA
            if paEn then
                paR, paG, paB, paA = 0.20, 0.20, 0.25, 1
            else
                paR, paG, paB, paA = 0.10, 0.10, 0.12, 0.50
            end
            local step = paSz + paSpacing
            local slotAnchor, slotDX, slotDY
            if dir == "LEFT" then
                slotAnchor = "RIGHT"; slotDX = -step; slotDY = 0
            elseif dir == "RIGHT" then
                slotAnchor = "LEFT"; slotDX = step; slotDY = 0
            elseif dir == "TOP" then
                slotAnchor = "BOTTOM"; slotDX = 0; slotDY = step
            else
                slotAnchor = "TOP"; slotDX = 0; slotDY = -step
            end
            for pi = 1, paMax do
                local pic = h._paIcons[pi]
                if not pic then
                    pic = h:CreateTexture(nil, "ARTWORK")
                    h._paIcons[pi] = pic
                end
                pic:SetSize(paSz, paSz)
                pic:ClearAllPoints()
                pic:SetPoint(slotAnchor, h, slotAnchor, (pi - 1) * slotDX, (pi - 1) * slotDY)
                pic:SetColorTexture(paR, paG, paB, paA)
                pic:Show()
            end
            for pi = paMax + 1, #h._paIcons do
                h._paIcons[pi]:Hide()
            end
            -- Visibility = sidebar toggle only. Disabled-config still
            -- clickable so the user can navigate to the Private Aura
            -- options section to re-enable it.
            local nativePrivate = IsNativeAuraHandle(kind, "private")
            h:SetShown(_visToggles.private ~= false and not nativePrivate and paMax > 0)
            -- Label tint reflects enabled state.
            if h._label then
                local lc = HANDLE_COLORS.private
                if nativePrivate then
                    h._label:SetTextColor(0.36, 0.62, 0.95, 0.95)
                elseif paEn then
                    h._label:SetTextColor(lc[1], lc[2], lc[3], 0.9)
                else
                    h._label:SetTextColor(lc[1] * 0.5, lc[2] * 0.5, lc[3] * 0.5, 0.6)
                end
            end
        end
    end

    -- Name / HP / Power text handles. They share the same drag and keyboard
    -- pipeline as every other preview handle, but keep their internal text
    -- padding separate from the stored config offsets.
    do
        local showTextHandles = ShouldShowTextPreview()
        local textSpecs = {
            nameText  = { rawSize = conf.nameFontSize or 12, fallbackW = 54, fallbackH = 16 },
            hpText    = { rawSize = conf.hpFontSize or 10, fallbackW = 58, fallbackH = 16 },
            powerText = { rawSize = conf.powerFontSize or 9, fallbackW = 52, fallbackH = 15 },
        }
        for textKey, spec in pairs(textSpecs) do
            local h = _textHandles[textKey]
            if h then
                local anchor = GetTextHandleAnchor(textKey, conf)
                local target = GetTextHandleTarget(textKey) or _mockFrame
                local xKey, yKey = GetTextHandleConfigKeys(textKey)
                h._previewOffsetAdjustX = GetTextHandlePad(textKey, anchor)
                h._previewOffsetAdjustY = 0
                local offX, offY = ConfigToHandlePreviewOffset(h, conf[xKey] or 0, conf[yKey] or 0)
                local liveFont = ScaleFrameValue(spec.rawSize, frameScale, 6)
                local fallbackH = max(spec.fallbackH, LiveToPreviewValue(liveFont) + 6)
                local fs = GetTextHandleFontString(textKey, anchor)
                local w, hh = MeasureTextHandle(fs, spec.fallbackW, fallbackH)
                h:SetSize(w, hh)
                h:ClearAllPoints()
                h:SetPoint(anchor, target, anchor, offX, offY)
                h:SetFrameLevel(_mockFrame:GetFrameLevel() + 30)
                h:SetShown(showTextHandles and IsTextHandleEnabled(textKey, conf))
                if h._label then
                    local lc = HANDLE_COLORS.text
                    h._label:SetTextColor(lc[1], lc[2], lc[3], 0.9)
                end
            end
        end
    end

    -- SI handles
    GF.RebuildSIHandles()

    -- Corner Indicator preview dots
    -- All 5 slots always visible: active = filled color, inactive = dim outline
    do
        local CI_SPECS = {
            { key = "TL", anchor = "TOPLEFT",     ox =  2, oy = -2 },
            { key = "TR", anchor = "TOPRIGHT",    ox = -2, oy = -2 },
            { key = "BL", anchor = "BOTTOMLEFT",  ox =  2, oy =  2 },
            { key = "BR", anchor = "BOTTOMRIGHT", ox = -2, oy =  2 },
            { key = "C",  anchor = "CENTER",      ox =  0, oy =  0 },
        }
        local CI_CAT_COLORS = {
            dispel  = { 0.25, 0.75, 1.00 },
            aggro   = { 1.00, 0.55, 0.00 },
            -- custom: per-slot color resolved from conf.ciCustomXX.r/g/b below
        }
        local CI_CAT_LABELS = {
            dispel  = "D",
            aggro   = "A",
            custom  = "C",
        }

        if not _mockFrame._ciDots then _mockFrame._ciDots = {} end
        local dots = _mockFrame._ciDots
        local ciRawSz = conf.ciSize or 8
        local ciSz = max(8, floor(ciRawSz * sc + 0.5))
        local ciEnabled = conf.ciEnabled ~= false
        local bdTbl = { bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

        for _, spec in ipairs(CI_SPECS) do
            -- Lazy-create as Frame with backdrop (not just a texture)
            local dot = dots[spec.key]
            if not dot then
                dot = CreateFrame("Frame", nil, _mockFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
                dot:EnableMouse(false)
                dots[spec.key] = dot

                -- Fill texture
                dot._ciFill = dot:CreateTexture(nil, "ARTWORK")
                dot._ciFill:SetAllPoints(dot)

                -- Label (slot initial or category letter)
                dot._ciLabel = dot:CreateFontString(nil, "OVERLAY")
                dot._ciLabel:SetPoint("CENTER", dot, "CENTER", 0, 0)
                dot._ciLabel:SetShadowColor(0, 0, 0, 1)
                dot._ciLabel:SetShadowOffset(1, -1)
            end

            local dbKey = "ciSlot" .. spec.key
            local cat = conf[dbKey] or "none"
            local c = CI_CAT_COLORS[cat]
            -- Custom: pull color from per-slot config (or default green).
            -- TYPE-GUARD: cc must be a table; fall back to default if not.
            if cat == "custom" then
                local cc = conf["ciCustom" .. spec.key]
                if type(cc) ~= "table" then cc = nil end
                c = { (cc and cc.r) or 0.40, (cc and cc.g) or 1.00, (cc and cc.b) or 0.40 }
            elseif cat == "aggro" then
                -- Override with user-configurable aggro color if set
                c = {
                    conf.ciAggroColorR or 1.00,
                    conf.ciAggroColorG or 0.55,
                    conf.ciAggroColorB or 0.00,
                }
            end
            local isActive = ciEnabled and cat ~= "none" and c

            -- Size + position
            dot:SetSize(ciSz, ciSz)
            dot:ClearAllPoints()
            dot:SetPoint(spec.anchor, _mockFrame, spec.anchor,
                floor(spec.ox * sc + 0.5), floor(spec.oy * sc + 0.5))
            dot:SetFrameLevel(_mockFrame:GetFrameLevel() + 10)

            -- Backdrop border
            if dot.SetBackdrop then
                dot:SetBackdrop(bdTbl)
            end

            -- Font size scales with dot
            local fSz = max(6, floor(ciSz * 0.65 + 0.5))
            local fp = GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
            dot._ciLabel:SetFont(fp, fSz, "OUTLINE")

            if isActive then
                -- Active: filled with category color + bright border
                dot._ciFill:SetColorTexture(c[1], c[2], c[3], conf.ciAlpha or 1.0)
                dot._ciFill:Show()
                if dot.SetBackdropColor then
                    dot:SetBackdropColor(c[1], c[2], c[3], conf.ciAlpha or 1.0)
                end
                if dot.SetBackdropBorderColor then
                    dot:SetBackdropBorderColor(0, 0, 0, 1)
                end
                dot._ciLabel:SetText(CI_CAT_LABELS[cat] or "")
                dot._ciLabel:SetTextColor(1, 1, 1, 0.95)
                dot._ciLabel:Show()
                dot:Show()
            elseif ciEnabled then
                -- Inactive: dim outline placeholder showing slot position
                dot._ciFill:SetColorTexture(0.15, 0.15, 0.18, 0.5)
                dot._ciFill:Show()
                if dot.SetBackdropColor then
                    dot:SetBackdropColor(0.15, 0.15, 0.18, 0.5)
                end
                if dot.SetBackdropBorderColor then
                    dot:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.6)
                end
                dot._ciLabel:SetText(spec.key)
                dot._ciLabel:SetTextColor(0.5, 0.5, 0.55, 0.7)
                dot._ciLabel:Show()
                dot:Show()
            else
                -- CI disabled entirely
                dot:Hide()
            end
        end
    end

    -- Section-aware focus: dim/hide elements not relevant to the active Options section
    local focus = GF._previewFocus
    -- The user-controlled "Text" sidebar toggle always wins over section
    -- focus: if the user has explicitly enabled Text preview, it stays
    -- visible in every Options tab (Layout, Health & Text, Buffs, etc.)
    -- The focus-based auto-dim is just a convenience for when the toggle
    -- is off — it shows text during the Text accordion section and hides
    -- it elsewhere so aura layouts read cleanly.
    local showText   = ShouldShowTextPreview()
    local showAuras  = not focus or focus == "indicators" or focus == "sicons" or focus == "blizzrenderer"
    local showSIcons = not focus or focus == "sicons"
    local showSI     = not focus or focus == "indicators"
    local showPriv   = not focus or focus == "indicators"
    local showCI     = not focus or focus == "ci"

    -- Text layer visibility
    if _mockFrame._nameLayer then _mockFrame._nameLayer:SetShown(showText) end
    if _mockFrame._textLayer then _mockFrame._textLayer:SetShown(showText) end
    if _mockFrame._powerTextLayer then _mockFrame._powerTextLayer:SetShown(showText) end
    for _, h in pairs(_textHandles) do
        if h and h:IsShown() then
            h:SetAlpha(showText and 1 or 0.15)
        end
    end

    -- Aura group handles
    for _, grpKey in ipairs({"buff", "debuff", "externals"}) do
        local h = _handles[grpKey]
        if h and h:IsShown() then
            h:SetAlpha(showAuras and 1 or 0.15)
        end
    end

    -- Status icon handles
    for _, spec in ipairs(STATUS_ICON_SPECS) do
        local h = _statusHandles[spec.key]
        if h and h:IsShown() then
            h:SetAlpha(showSIcons and 1 or 0.15)
        end
    end

    -- SI handles
    if _siHandles then
        for _, h in pairs(_siHandles) do
            if h and h:IsShown() then
                h:SetAlpha(showSI and 1 or 0.15)
            end
        end
    end

    -- Private aura handle
    local privH = _handles.private
    if privH and privH:IsShown() then
        privH:SetAlpha(showPriv and 1 or 0.15)
    end

    -- Corner Indicator preview dots
    if _mockFrame._ciDots then
        for _, dot in pairs(_mockFrame._ciDots) do
            if dot and type(dot.IsShown) == "function" and dot:IsShown() then
                dot:SetAlpha(showCI and 1 or 0.10)
            end
        end
    end

    -- Solo + visibility pass (last-write wins): overrides any alpha set by
    -- the section-focus logic above so solo-highlight mode behaves
    -- consistently after a rebuild.
    ApplyLayerVisibility()
    if _selected and _selected.IsShown and _selected:IsShown() then
        SelectHandle(_selected, true)
    else
        RefreshSelectedCoordDisplay()
    end
end

------------------------------------------------------------------------
-- Section-aware preview focus
-- Called by Options panel when accordion sections expand/collapse.
-- focus = sectionKey ("text", "sicons", "indicators", "overlay", etc.) or nil (show all)
------------------------------------------------------------------------
function GF.SetPreviewFocus(focus)
    GF._previewFocus = focus
    -- Refresh both the preview box (frame + text) and handles so the
    -- focus change takes effect across all layers. RefreshPreviewBox
    -- is needed for the text-toggle override to apply when the user
    -- switches Options tabs while the Text toggle is on.
    if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
end

function GF.SetStatusPreviewMode(mode)
    _statusPreviewShowAll = (mode == "all")
    if _statusPreviewShowAll then
        SelectHandle(nil, true)
    end
    if GF.SetPreviewFocus then GF.SetPreviewFocus("sicons") end
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
end

function GF.GetStatusPreviewMode()
    return _statusPreviewShowAll and "all" or "current"
end

------------------------------------------------------------------------
-- Main API: Create the full preview box
-- parent: scrollChild frame to embed into
-- getKindFn: function returning "party" or "raid"
-- onSectionOpenFn: function(sectionKey) to auto-open accordion
-- Returns: the container frame (for anchoring sections below)
------------------------------------------------------------------------

function GF.CreatePreviewBox(parent, getKindFn, onSectionOpenFn)
    if _box then
        _getKind = getKindFn or _getKind
        _onSectionOpen = onSectionOpenFn or _onSectionOpen
        if parent then
            _box:SetParent(parent)
            _box:ClearAllPoints()
            _box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        end
        _box:Show()
        if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
        if GF.ResizePreviewContainer then GF.ResizePreviewContainer() end
        return _box
    end
    _getKind       = getKindFn
    _onSectionOpen = onSectionOpenFn

    local sideW = 72

    -- Outer container
    local container = CreateFrame("Frame", "MSUF_GFPreviewContainer", parent, "BackdropTemplate")
    container:SetSize(680, 280)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    container:SetBackdropColor(0.04, 0.04, 0.055, 1)
    container:SetBackdropBorderColor(0.10, 0.10, 0.14, 0.7)
    _box = container

    -- Top accent line (thin colored stripe)
    local accent = container:CreateTexture(nil, "ARTWORK", nil, 2)
    accent:SetHeight(1)
    accent:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", container, "TOPRIGHT", -1, -1)
    accent:SetColorTexture(0.25, 0.45, 0.75, 0.35)

    -- Header bar (elevated surface)
    local headerBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    headerBar:SetHeight(26)
    headerBar:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -2)
    headerBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -1, -2)
    headerBar:SetBackdrop({ bgFile = W8 })
    headerBar:SetBackdropColor(0.065, 0.065, 0.085, 1)

    local hdr = headerBar:CreateFontString(nil, "OVERLAY")
    SetPreviewLabelFont(hdr, 12, "")
    hdr:SetPoint("LEFT", headerBar, "LEFT", 10, 1)
    hdr:SetText(Tr("Group Frame Preview") .. " - " .. PreviewScopeLabel(_getKind and _getKind() or "party"))
    hdr:SetTextColor(0.92, 0.95, 1.00, 1)
    container._previewTitle = hdr

    local hint = headerBar:CreateFontString(nil, "OVERLAY")
    SetPreviewLabelFont(hint, 9, "")
    hint:SetPoint("LEFT", hdr, "RIGHT", 12, 0)
    hint:SetText(Tr("click to configure - custom layers drag; Blizzard is locked"))
    hint:SetTextColor(0.55, 0.58, 0.70, 0.85)
    container._previewHint = hint

    -- Header separator
    local sep = container:CreateTexture(nil, "ARTWORK", nil, 1)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.12, 0.12, 0.16, 0.5)

    -- Preview canvas (dark recessed surface)
    local area = CreateFrame("Frame", nil, container, "BackdropTemplate")
    area:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -30)
    area:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(sideW + 8), 22)
    area:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    area:SetBackdropColor(0.015, 0.015, 0.025, 1)
    area:SetBackdropBorderColor(0.08, 0.08, 0.11, 0.5)
    container._area = area

    -- Inner vignette overlays for depth
    do
        local topFade = area:CreateTexture(nil, "ARTWORK", nil, 1)
        topFade:SetHeight(20)
        topFade:SetPoint("TOPLEFT", area, "TOPLEFT", 1, -1)
        topFade:SetPoint("TOPRIGHT", area, "TOPRIGHT", -1, -1)
        topFade:SetColorTexture(0, 0, 0, 1)
        topFade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.25))

        local botFade = area:CreateTexture(nil, "ARTWORK", nil, 1)
        botFade:SetHeight(15)
        botFade:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 1, 1)
        botFade:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 1)
        botFade:SetColorTexture(0, 0, 0, 1)
        botFade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.3), CreateColor(0, 0, 0, 0))
    end

    -- Sidebar: layer visibility toggles
    do
        local sidebar = CreateFrame("Frame", nil, container, "BackdropTemplate")
        sidebar:SetPoint("TOPLEFT", area, "TOPRIGHT", 4, 0)
        sidebar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 22)
        sidebar:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        sidebar:SetBackdropColor(0.04, 0.04, 0.055, 0.8)
        sidebar:SetBackdropBorderColor(0.08, 0.08, 0.11, 0.4)

        local sHdr = sidebar:CreateFontString(nil, "OVERLAY")
        SetPreviewLabelFont(sHdr, 8, "")
        sHdr:SetPoint("TOP", sidebar, "TOP", 0, -4)
        sHdr:SetText(Tr("LAYERS"))
        sHdr:SetTextColor(0.45, 0.50, 0.62, 0.82)

        local VIS_BTNS = {
            { key="buff",      label="Buffs",   color={0.40,0.82,0.40} },
            { key="debuff",    label="Debuffs", color={0.92,0.32,0.32} },
            { key="externals", label="Extern",  color={0.25,0.70,0.55} },
            { key="blizzard",  label="Blizzard",color={0.36,0.62,0.95} },
            { key="status",    label="Status",  color={0.85,0.70,0.25} },
            { key="si",        label="Spells",  color={0.72,0.52,0.90} },
            { key="private",   label="Private", color={0.55,0.55,0.60} },
            -- Aura Text: cooldown + stack count FontStrings on mock
            -- aura icons.  Default on (primary purpose of this tab).
            { key="auraText",  label="CD/Stack",color={0.95,0.82,0.35} },
            -- Text: name + HP + power FontStrings on the frame itself
            -- (off by default so the aura layout reads clearly).
            { key="text",      label="Text",    color={0.55,0.78,0.95} },
        }
        -- Collect buttons so solo transitions can refresh their visuals.
        local _layerBtns = {}

        -- Refresh every layer button (after solo state change).
        local function RefreshAllLayerBtns()
            for i = 1, #_layerBtns do
                local rb = _layerBtns[i]._refresh
                if rb then rb() end
            end
        end

        local btnH, gap, topPad = 18, 2, 20
        for i, spec in ipairs(VIS_BTNS) do
            local btn = CreateFrame("Button", nil, sidebar)
            btn:SetSize(sideW - 10, btnH)
            btn:SetPoint("TOP", sidebar, "TOP", 0, -(topPad + (i-1) * (btnH + gap)))
            btn:EnableMouse(true)
            -- Accept right-click so Shift+RightClick can also exit solo mode
            -- without triggering the normal toggle branch.
            if btn.RegisterForClicks then
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
            local c = spec.color

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            btn._bg = bg

            local bar = btn:CreateTexture(nil, "ARTWORK")
            bar:SetSize(2, btnH - 4)
            bar:SetPoint("LEFT", btn, "LEFT", 2, 0)
            btn._bar = bar

            -- Solo indicator: thin gold edge when this button owns the solo.
            -- Hidden by default; toggled in RefreshBtn based on _soloKey.
            local soloEdge = btn:CreateTexture(nil, "OVERLAY")
            soloEdge:SetTexture(W8)
            soloEdge:SetVertexColor(1, 0.82, 0, 0.9)
            soloEdge:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            soloEdge:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            soloEdge:SetWidth(2)
            soloEdge:Hide()
            btn._soloEdge = soloEdge

            local fs = btn:CreateFontString(nil, "OVERLAY")
            SetPreviewLabelFont(fs, 9, "")
            fs:SetPoint("LEFT", bar, "RIGHT", 5, 0)
            fs:SetText(spec.label)
            btn._fs = fs

            local function RefreshBtn()
                local on = _visToggles[spec.key]
                local isSolo = (_soloKey == spec.key)
                if on then
                    bg:SetColorTexture(c[1]*0.12, c[2]*0.12, c[3]*0.12, 0.6)
                    bar:SetColorTexture(c[1], c[2], c[3], 0.85)
                    fs:SetTextColor(0.75, 0.78, 0.85, 0.95)
                else
                    bg:SetColorTexture(0.04, 0.04, 0.05, 0.3)
                    bar:SetColorTexture(0.18, 0.18, 0.22, 0.3)
                    fs:SetTextColor(0.38, 0.40, 0.48, 0.65)
                end
                -- Solo indicator: shown on the single soloed button. Also
                -- brighten its label so it reads clearly when solo-dimming
                -- its siblings visually in the preview area.
                if isSolo then
                    soloEdge:Show()
                    fs:SetTextColor(1, 0.90, 0.50, 1)
                else
                    soloEdge:Hide()
                end
            end
            btn._refresh = RefreshBtn
            _layerBtns[#_layerBtns + 1] = btn
            RefreshBtn()

            btn:SetScript("OnClick", function(self, mouseBtn)
                -- Shift+Click (either button) → toggle solo mode for this key.
                -- Shift+Click on the already-soloed key → exit solo mode.
                -- This does not touch _visToggles — solo is orthogonal to
                -- the plain visibility toggle and restores on exit.
                if IsShiftKeyDown and IsShiftKeyDown() then
                    if _soloKey == spec.key then
                        _soloKey = nil
                    else
                        _soloKey = spec.key
                    end
                    ApplyLayerVisibility()
                    RefreshAllLayerBtns()
                    -- Text gate depends on _soloKey ("text" solos force
                    -- text on) — re-run the preview-box refresh so the
                    -- FontStrings update in the same frame.
                    if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
                    -- Aura-text gate also depends on _soloKey — re-run
                    -- handles so per-icon cooldown/stack FontStrings
                    -- reflect the new solo state on this frame.
                    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
                    return
                end
                -- Right-click without shift: no-op (reserved for future use).
                if mouseBtn == "RightButton" then return end

                -- Normal left-click: toggle visibility for this layer.
                -- If solo is active, a normal click on a non-soloed layer
                -- exits solo first so the user's toggle intent is visible.
                if _soloKey ~= nil and _soloKey ~= spec.key then
                    _soloKey = nil
                end
                _visToggles[spec.key] = not _visToggles[spec.key]
                local on = _visToggles[spec.key]
                -- Show/hide handles via the same branches as RefreshPreviewHandles
                -- inline logic (which is the source of truth for visibility).
                if spec.key == "buff" or spec.key == "debuff" or spec.key == "externals" then
                    local h = _handles[spec.key]
                    if h then h:SetShown(on) end
                elseif spec.key == "blizzard" then
                    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
                elseif spec.key == "status" then
                    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
                elseif spec.key == "si" then
                    for _, sh in pairs(_siHandles) do sh:SetShown(on) end
                elseif spec.key == "private" then
                    local h = _handles.private
                    if h then h:SetShown(on) end
                elseif spec.key == "text" then
                    -- Text visibility is gated inside RefreshPreviewBox via
                    -- the _visToggles.text check.  Re-run it so name/HP/power
                    -- FontStrings and drag handles show or hide immediately.
                    if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
                    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
                elseif spec.key == "auraText" then
                    -- Aura-icon cooldown/stack text is applied inside
                    -- RefreshPreviewHandles → ApplyMockIconText.  Re-run
                    -- handles so the toggle change takes effect on all
                    -- mock icons immediately.
                    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
                end
                -- Sync alpha (solo transitions set above may need applying)
                ApplyLayerVisibility()
                RefreshAllLayerBtns()
            end)
            btn:SetScript("OnEnter", function(self)
                if _visToggles[spec.key] then
                    bg:SetColorTexture(c[1]*0.18, c[2]*0.18, c[3]*0.18, 0.8)
                else
                    bg:SetColorTexture(0.08, 0.08, 0.10, 0.5)
                end
                fs:SetTextColor(0.85, 0.88, 0.95, 1)
            end)
            btn:SetScript("OnLeave", function() RefreshBtn() end)
        end

        -- Store required sidebar height so ResizePreviewContainer can
        -- enlarge the preview box when more layer buttons are added.
        -- Previously this was hardcoded to 7*24 — adding buttons would
        -- silently clip the last ones (Text, CD/Stack) off the bottom.
        container._sidebarReqH = topPad + #VIS_BTNS * btnH + (#VIS_BTNS - 1) * gap + 4
    end

    -- Bottom status bar
    local statusBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    statusBar:SetHeight(18)
    statusBar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 1, 1)
    statusBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
    statusBar:SetBackdrop({ bgFile = W8 })
    statusBar:SetBackdropColor(0.055, 0.055, 0.07, 1)

    local sepBot = container:CreateTexture(nil, "ARTWORK", nil, 1)
    sepBot:SetHeight(1)
    sepBot:SetPoint("BOTTOMLEFT", statusBar, "TOPLEFT", 0, 0)
    sepBot:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", 0, 0)
    sepBot:SetColorTexture(0.10, 0.10, 0.14, 0.4)

    -- Build mock frame inside area
    BuildMockFrame(area)

    -- Click on frame background opens General section
    _mockFrame:EnableMouse(true)
    _mockFrame:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        SelectHandle(nil)
        UpdateCoordDisplay("general", nil, nil, nil)
        if _onSectionOpen then _onSectionOpen("general") end
    end)

    -- Build all handles
    BuildAuraGroupHandles(_mockFrame)
    BuildStatusIconHandles(_mockFrame)
    BuildPrivateAuraHandle(_mockFrame)
    BuildTextHandles(_mockFrame)

    -- Coord display (in status bar)
    local coord = statusBar:CreateFontString(nil, "OVERLAY")
    SetPreviewLabelFont(coord, 9, "")
    coord:SetPoint("LEFT", statusBar, "LEFT", 10, 0)
    coord:SetTextColor(1, 0.82, 0, 0.9)
    coord:SetText(Tr("Click a handle to select - custom layers can be moved; Blizzard is locked"))
    _coordLabel = coord

    container:EnableKeyboard(true)
    if container.SetPropagateKeyboardInput then container:SetPropagateKeyboardInput(true) end
    container:SetScript("OnKeyDown", function(self, key)
        local dx, dy = 0, 0
        if key == "LEFT" then
            dx = -1
        elseif key == "RIGHT" then
            dx = 1
        elseif key == "UP" then
            dy = 1
        elseif key == "DOWN" then
            dy = -1
        else
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end

        if IsTextInputFocused() then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        if not NudgeSelectedHandle(dx, dy) then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        end
    end)
    container:SetScript("OnHide", function(self)
        SelectHandle(nil)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)

    -- Initial refresh
    GF.RefreshPreviewBox()

    return container
end

------------------------------------------------------------------------
-- Scope switch hook: full refresh on party/raid toggle
------------------------------------------------------------------------
function GF.PreviewScopeChanged()
    _classIdx = 1
    GF.RefreshPreviewBox()
end

------------------------------------------------------------------------
-- Select a status icon handle by key (called from Options dropdown)
-- Does NOT open section — assumes sicons is already open
------------------------------------------------------------------------
function GF._PreviewSelectStatusIcon(iconKey)
    if not iconKey then return end
    _statusPreviewSelectedKey = iconKey
    local h = _statusHandles[iconKey]
    if not h then return end
    -- Select without triggering section open.
    SelectHandle(h, true)
    RefreshSelectedCoordDisplay()
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
end

------------------------------------------------------------------------
-- Resize container height dynamically based on mock frame
------------------------------------------------------------------------
function GF.ResizePreviewContainer()
    if not _box or not _mockFrame then return end
    local mH = _mockFrame:GetHeight() or 130
    -- Sidebar minimum height is driven by the actual button count stored
    -- on _box when the buttons were built.  Falls back to a safe value
    -- that covers 9 buttons if the computed value isn't set yet (e.g.
    -- before the sidebar finishes its first build).
    local sideMinH = _box._sidebarReqH or (9 * 21 + 16)
    local areaH = max(mH + 50, sideMinH)
    local totalH = areaH + 44  -- header(24) + coord(20)
    totalH = max(200, totalH)
    _box:SetHeight(totalH)
end

------------------------------------------------------------------------
-- Hook into GF.RefreshVisuals to keep preview in sync
------------------------------------------------------------------------
do
    local _origRefresh = GF.RefreshVisuals
    if type(_origRefresh) == "function" then
        GF.RefreshVisuals = function(...)
            _origRefresh(...)
            if _box and _box:IsShown() then
                GF.RefreshPreviewBox()
                GF.RefreshPreviewHandles()
                GF.ResizePreviewContainer()
                if GF._RefreshOptionWidgets then GF._RefreshOptionWidgets() end
            end
        end
    end
end

------------------------------------------------------------------------
_G.MSUF_GF_CreatePreviewBox = GF.CreatePreviewBox
_G.MSUF_GF_RefreshPreviewBox = GF.RefreshPreviewBox
