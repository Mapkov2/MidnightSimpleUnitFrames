local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB

-- Menu2 Auras page: sample previews.
-- Owns the mini aura preview icons, the preview config readers for unit and group
-- scopes, and the Aura Style preview workbench (zoom bar, pinned preview). Split
-- It reads shared AuraSettings and the five AuraGroupSettings readers, then
-- publishes just the two preview entry points called by the Style builders.
local AurasPage = M.AurasPage
if type(AurasPage) ~= "table" then return end
local W = M.Widgets
local T = M.Theme
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local PreviewHelpers = M.PreviewHelpers or {}
local CreateFrame = _G.CreateFrame
local C_Timer = M.MenuTimer or _G.C_Timer
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local AURA_PREVIEW_EDGE_OPTS = { linesKey = "edge", maxEdgeSize = 1, texture = TEX_W8, color = function() return 1, 1, 1, 0.95 end }
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local function AuraDurationBarColor()
    local resolver = A3 and A3.GetDurationBarColor
    if type(resolver) == "function" then return resolver() end
    return 1, 1, 1
end
local AURA_SCOPE_VALID, AccessibleNumber, AurasMenuCombatLocked = M.AuraSettings.AURA_SCOPE_VALID, M.AuraSettings.AccessibleNumber, M.AuraSettings.AurasMenuCombatLocked
local IsGroupScope, LaneDefaultMax, LaneMaxKey, LanePlural = M.AuraSettings.IsGroupScope, M.AuraSettings.LaneDefaultMax, M.AuraSettings.LaneMaxKey, M.AuraSettings.LanePlural
local LaneSizeKey, Round, ScopeLabel, Tr = M.AuraSettings.LaneSizeKey, M.AuraSettings.Round, M.AuraSettings.ScopeLabel, M.AuraSettings.Tr
local GroupScopeKinds, GroupConf, GFReadRoot, GFReadGroup = M.AuraGroupSettings.GroupScopeKinds, M.AuraGroupSettings.GroupConf, M.AuraGroupSettings.GFReadRoot, M.AuraGroupSettings.GFReadGroup
local ReadGroupDebuffTypeBorderMode = M.AuraGroupSettings.ReadGroupDebuffTypeBorderMode
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local function CreateAuraPreviewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(24, 24)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.85)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    -- Match the full Unit Preview: the swipe must sort above the icon rather
    -- than sharing its otherwise undefined ARTWORK ordering.
    f.swipe = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.swipe:SetPoint("TOPLEFT", f, "TOP", 0, -1)
    f.swipe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.swipe:SetTexture(TEX_W8)
    f.swipe:SetVertexColor(0, 0, 0, 0.58)
    f.swipe:Hide()
    f.durationBar = f:CreateTexture(nil, "OVERLAY")
    f.durationBar:SetTexture(TEX_W8)
    local durationR, durationG, durationB = AuraDurationBarColor()
    f.durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
    f.durationBar:Hide()
    f.dispelBorder = f:CreateTexture(nil, "OVERLAY")
    f.dispelBorder:Hide()
    f.edge = {}
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(f, 1, AURA_PREVIEW_EDGE_OPTS) end
    f.stack = f:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, T.FontSize("micro"), "OUTLINE")
    f.stack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(FONT, T.FontSize("micro"), "OUTLINE")
    f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
    return f
end
local function ApplyAuraPreviewIconZoom(texture, zoom)
    if not (texture and texture.SetTexCoord) then return end
    zoom = tonumber(zoom) or 100
    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end
local function ApplyAuraPreviewFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then fontPath, fontFlags, r, g, b, _, useShadow = _G.MSUF_GetGlobalFontSettings() end
    if fs.SetFont then
        local px = max(7, tonumber(size) or 10)
        local flags = fontFlags or "OUTLINE"
        local path = fontPath or FONT
        local resolveSafe = _G.MSUF_ResolveSafeFontPath
        if type(resolveSafe) == "function" then
            local gdb = EnsureDB().general
            path = resolveSafe(path, px, flags, gdb and gdb.fontKey)
        end
        if not _G.MSUF_SetFontChecked(fs, path, px, flags) then
            _G.MSUF_SetFontChecked(fs, FONT, px, flags)
        end
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0) end
end
local function PlaceAuraPreviewText(fs, icon, anchor, x, y)
    if not (fs and icon) then return end
    anchor = tostring(anchor or "CENTER"):upper()
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    fs:ClearAllPoints()
    fs:SetPoint(anchor, icon, anchor, x, y)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if fs.SetJustifyV then
        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
            fs:SetJustifyV("TOP")
        elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            fs:SetJustifyV("BOTTOM")
        else
            fs:SetJustifyV("MIDDLE")
        end
    end
end
local function RefreshMiniAuraPreviewNow(refreshPreview)
    if AurasMenuCombatLocked() then return end
    if type(refreshPreview) ~= "function" then return end
    refreshPreview()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not AurasMenuCombatLocked() then refreshPreview() end
        end)
    end
end
local function GroupAuraPreviewDefaultSize(scope, lane)
    if scope == "raid" or scope == "mythicraid" then return 16 end
    return lane == "buff" and 22 or 20
end
function M.ResolveAuraStylePreviewIconShape(scope, requested, effective)
    local portraitShape
    if scope ~= "shared" then
        if IsGroupScope(scope) then
            local kind = GroupScopeKinds(scope)
            local conf = GroupConf(kind)
            portraitShape = conf and conf.portraitShape or "SQUARE"
        else
            local conf = type(M.GetUnitDB) == "function" and M.GetUnitDB(scope) or nil
            portraitShape = conf and conf.portraitShape or "SQUARE"
        end
    end
    if type(A3.ResolveAuraIconShape) == "function" then
        return A3.ResolveAuraIconShape(requested or effective, portraitShape)
    end
    return effective or requested or "RECTANGLE"
end
local function ApplySharedAppearanceStyleToPreview(cfg, kind)
    if kind ~= "debuff" and kind ~= "playerDefensives" and kind ~= "targetDots" then kind = "buff" end
    if type(Model.ReadSharedAppearanceBool) == "function" then
        cfg.styleBorderEnabled = Model.ReadSharedAppearanceBool(kind, "styleBorderEnabled", false)
        cfg.styleShadowEnabled = Model.ReadSharedAppearanceBool(kind, "styleShadowEnabled", false)
    end
    cfg.styleBorderStyle = type(Model.ReadSharedAppearanceBorderStyle) == "function"
        and Model.ReadSharedAppearanceBorderStyle(kind) or "SOLID"
    if type(Model.ReadSharedAppearanceNumber) == "function" then
        cfg.styleBorderThickness = Model.ReadSharedAppearanceNumber(kind, "styleBorderThickness", 1, 1, 8)
        cfg.styleShadowSize = Model.ReadSharedAppearanceNumber(kind, "styleShadowSize", 4, 1, 16)
    end
    if type(Model.ReadSharedAppearanceValue) == "function" then
        local bc = Model.ReadSharedAppearanceValue(kind, "styleBorderColor", nil)
        cfg.styleBorderColor = type(bc) == "table" and bc or nil
        local sc = Model.ReadSharedAppearanceValue(kind, "styleShadowColor", nil)
        cfg.styleShadowColor = type(sc) == "table" and sc or nil
    end
end

local function ReadMiniAuraPreviewConfig(scope, lane, width, height)
    local isGroup = IsGroupScope(scope)
    local cfg = {
        size = 24,
        spacing = 2,
        perRow = 7,
        maxIcons = 14,
        showStacks = true,
        showTimers = true,
        showSwipe = true,
        cooldownSwipeReverse = false,
        stackSize = 10,
        stackAnchor = "TOPRIGHT",
        stackX = -1,
        stackY = -1,
        cooldownSize = 9,
        cooldownAnchor = "CENTER",
        cooldownX = 0,
        cooldownY = 0,
        debuffBorderMode = "OFF",
        showDurationBar = false,
        durationBarHeight = 2,
        durationBarDisplay = "BAR_ONLY",
        durationBarPosition = "BOTTOM",
        durationBarDirection = "REMAINING",
        iconZoom = 100,
        iconShape = "RECTANGLE",
    }
    local appearanceKind = lane == "debuff" and "debuff" or "buff"
    ApplySharedAppearanceStyleToPreview(cfg, appearanceKind)
    if isGroup then
        local group = GFReadGroup(scope, lane or "debuff")
        local root = GFReadRoot(scope)
        cfg.iconZoom = tonumber(group.iconZoom) or tonumber(root and root.iconZoom) or 100
        local requestedIconShape = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        cfg.iconShape = M.ResolveAuraStylePreviewIconShape(scope, requestedIconShape, requestedIconShape)
        local iconScale = min(300, max(20, AccessibleNumber(group.iconScale, 100))) / 100
        cfg.size = (tonumber(group.size) or GroupAuraPreviewDefaultSize(scope, lane)) * iconScale
        cfg.allowTinyIconScale = true
        cfg.spacing = tonumber(group.spacing) or 1
        cfg.perRow = tonumber(group.perRow) or (lane == "buff" and 4 or 3)
        cfg.maxIcons = tonumber(group.max) or cfg.perRow * 2
        cfg.showStacks = group.showStacks ~= false
        cfg.showTimers = group.showCooldown ~= false
        cfg.showSwipe = group.showCooldownSwipe ~= false
        cfg.cooldownSwipeReverse = group.cooldownSwipeReverse == true
        cfg.stackSize = tonumber(group.stackSize) or 10
        cfg.stackAnchor = group.stackAnchor or "BOTTOMRIGHT"
        cfg.stackX = tonumber(group.stackX) or 0
        cfg.stackY = tonumber(group.stackY) or 0
        cfg.cooldownSize = tonumber(group.cooldownSize) or 8
        cfg.cooldownAnchor = group.cooldownAnchor or "CENTER"
        cfg.cooldownX = tonumber(group.cooldownX) or 0
        cfg.cooldownY = tonumber(group.cooldownY) or 0
        cfg.cooldownDecimalSeconds = tonumber(group.cooldownDecimalSeconds) or 3
        local growthX, growthY = tostring(group.growthX or "RIGHT"), tostring(group.growthY or "DOWN")
        cfg.growth = (growthX == "UP" or growthX == "DOWN") and growthX or (growthX .. growthY)
        cfg.showDurationBar = group.showDurationBar == true
        cfg.durationBarHeight = tonumber(group.durationBarHeight) or 2
        cfg.durationBarDisplay = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        cfg.durationBarPosition = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        cfg.durationBarDirection = group.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
        if lane == "debuff" then cfg.debuffBorderMode = ReadGroupDebuffTypeBorderMode(scope, "debuff") end
    else
        local readScope = scope or "shared"
        local runtimePreview = (readScope ~= "shared" and type(Model.ReadPreviewConfig) == "function") and Model.ReadPreviewConfig(readScope) or nil
        if lane == "buff" then
            cfg.size = tonumber(runtimePreview and runtimePreview.buffSize) or Model.ReadNumber(readScope, LaneSizeKey(lane), 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.buffPerRow) or Model.ReadLanePerRow(readScope, lane)
            cfg.maxIcons = tonumber(runtimePreview and runtimePreview.maxBuffs) or Model.ReadNumber(readScope, LaneMaxKey(lane), LaneDefaultMax(lane), 0, 80)
        elseif lane == "debuff" then
            cfg.size = tonumber(runtimePreview and runtimePreview.debuffSize) or Model.ReadNumber(readScope, LaneSizeKey(lane), 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.debuffPerRow) or Model.ReadLanePerRow(readScope, lane)
            cfg.maxIcons = tonumber(runtimePreview and runtimePreview.maxDebuffs) or Model.ReadNumber(readScope, LaneMaxKey(lane), LaneDefaultMax(lane), 0, 80)
        else
            cfg.size = Model.ReadNumber(readScope, "iconSize", 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.perRow) or Model.ReadNumber(readScope, "perRow", 12, 1, 40)
            cfg.maxIcons = cfg.perRow * 2
        end
        -- Gap is per lane like Size and Per row; only the laneless preview
        -- (shared style workbench) falls back to the unit-wide value.
        if lane == "buff" or lane == "debuff" then
            cfg.spacing = tonumber(runtimePreview and runtimePreview[lane .. "Spacing"])
                or Model.ReadLaneSpacing(readScope, lane)
        else
            cfg.spacing = tonumber(runtimePreview and runtimePreview.spacing) or Model.ReadNumber(readScope, "spacing", 2, 0, 12)
        end
        cfg.iconZoom = lane and Model.ReadLaneStyleNumber(readScope, lane, "iconZoom", 100, 100, 200)
            or Model.ReadNumber(readScope, "iconZoom", 100, 100, 200)
        local configuredIconShape = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        local requestedIconShape = lane and runtimePreview
            and (lane == "buff" and runtimePreview.buffRequestedIconShape or runtimePreview.debuffRequestedIconShape)
            or configuredIconShape
        local effectiveIconShape = lane and runtimePreview
            and (lane == "buff" and runtimePreview.buffIconShape or runtimePreview.debuffIconShape)
            or configuredIconShape
        cfg.iconShape = M.ResolveAuraStylePreviewIconShape(readScope, requestedIconShape, effectiveIconShape)
        cfg.growth = lane and type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(readScope, lane) or "RIGHTDOWN"
        if type(Model.ReadLaneStyleBool) == "function" and lane then
            cfg.showStacks = Model.ReadLaneStyleBool(readScope, lane, "showStackCount", true)
            cfg.showTimers = Model.ReadLaneStyleBool(readScope, lane, "showCooldownText", true)
            cfg.showSwipe = Model.ReadLaneStyleBool(readScope, lane, "showCooldownSwipe", true)
            cfg.cooldownSwipeReverse = Model.ReadLaneStyleBool(readScope, lane, "cooldownSwipeReverse", false)
            cfg.showDurationBar = Model.ReadLaneStyleBool(readScope, lane, "showDurationBar", false)
        else
            cfg.showStacks = Model.ReadBool(readScope, "showStackCount", true)
            cfg.showTimers = Model.ReadBool(readScope, "showCooldownText", true)
            cfg.showSwipe = Model.ReadBool(readScope, "showCooldownSwipe", true)
            cfg.cooldownSwipeReverse = Model.ReadBool(readScope, "cooldownSwipeReverse", false)
            cfg.showDurationBar = Model.ReadBool(readScope, "showDurationBar", false)
        end
        cfg.stackSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "stackTextSize", 14, 6, 40)
        cfg.stackAnchor = lane and type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(readScope, lane) or Model.ReadStackAnchor(readScope)
        cfg.stackX = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetX", -1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetX", -1, -2000, 2000)
        cfg.stackY = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetY", 1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetY", 1, -2000, 2000)
        cfg.cooldownSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "cooldownTextSize", 14, 6, 40)
        if lane and type(Model.ReadLaneCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadLaneCooldownAnchor(readScope, lane)
        elseif type(Model.ReadCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadCooldownAnchor(readScope)
        elseif runtimePreview and runtimePreview.cooldownAnchor then
            cfg.cooldownAnchor = runtimePreview.cooldownAnchor
        end
        cfg.cooldownX = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetX", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetX", 0, -2000, 2000)
        cfg.cooldownY = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetY", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetY", 0, -2000, 2000)
        cfg.cooldownDecimalSeconds = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownDecimalSeconds", 3, 0, 30) or Model.ReadNumber(readScope, "cooldownDecimalSeconds", 3, 0, 30)
        cfg.durationBarHeight = lane and Model.ReadLaneStyleNumber(readScope, lane, "durationBarHeight", 2, 1, 16) or Model.ReadNumber(readScope, "durationBarHeight", 2, 1, 16)
        if lane and type(Model.ReadLaneDurationBarDisplay) == "function" then
            cfg.durationBarDisplay = Model.ReadLaneDurationBarDisplay(readScope, lane)
        else
            cfg.durationBarDisplay = Model.ReadValue(readScope, "durationBarDisplay", "BAR_ONLY")
        end
        if lane and type(Model.ReadLaneDurationBarPosition) == "function" then
            cfg.durationBarPosition = Model.ReadLaneDurationBarPosition(readScope, lane)
        else
            cfg.durationBarPosition = Model.ReadValue(readScope, "durationBarPosition", "BOTTOM")
        end
        if lane and type(Model.ReadLaneDurationBarDirection) == "function" then
            cfg.durationBarDirection = Model.ReadLaneDurationBarDirection(readScope, lane)
        else
            cfg.durationBarDirection = Model.ReadValue(readScope, "durationBarDirection", "REMAINING")
        end
        if lane == "debuff" then
            if type(Model.ReadDebuffTypeBorderMode) == "function" then
                cfg.debuffBorderMode = Model.ReadDebuffTypeBorderMode(readScope)
            elseif type(Model.ReadLaneStyleBool) == "function" then
                cfg.debuffBorderMode = Model.ReadLaneStyleBool(readScope, "debuff", "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
            end
        end
    end
    local maxSize = max(12, min(128, floor((height or 104) - 38), floor((width or 300) - 20)))
    cfg.actualSize = max(cfg.allowTinyIconScale == true and 1 or 10, tonumber(cfg.size) or 24)
    cfg.size = min(maxSize, cfg.actualSize)
    cfg.spacing = min(10, max(0, tonumber(cfg.spacing) or 2))
    cfg.perRow = max(1, Round(cfg.perRow))
    cfg.maxIcons = max(0, Round(cfg.maxIcons))
    local maxCols = max(1, floor(((width or 300) - 20 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.columns = min(cfg.perRow, maxCols)
    cfg.maxRows = max(1, floor(((height or 104) - 38 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    local vertical = cfg.growth == "UP" or cfg.growth == "DOWN"
    cfg.rowsPerColumn = cfg.maxRows
    cfg.columns = vertical and 1 or cfg.columns
    cfg.count = min(14, cfg.maxIcons, cfg.columns * cfg.rowsPerColumn)
    cfg.stackSize = max(7, tonumber(cfg.stackSize) or 10)
    cfg.cooldownSize = max(7, tonumber(cfg.cooldownSize) or 9)
    cfg.cooldownDecimalSeconds = min(30, max(0, tonumber(cfg.cooldownDecimalSeconds) or 3))
    cfg.durationBarHeight = min(max(1, tonumber(cfg.durationBarHeight) or 2), max(1, cfg.size or 24))
    cfg.durationBarDisplay = cfg.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    cfg.durationBarPosition = cfg.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
    cfg.durationBarDirection = cfg.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
    return cfg
end
local function ReadSharedSpecialAuraPreviewConfig(container, width, height)
    local playerDefensives = container == "playerDefensives"
    local cfg = ReadMiniAuraPreviewConfig("shared", playerDefensives and "buff" or "debuff", width, height)
    -- Appearance previews never read a UnitFrame's deep Style. They show only
    -- the global theme for this Aura product on stable dummy geometry.
    cfg.actualSize, cfg.size = 32, 32
    cfg.spacing, cfg.perRow, cfg.maxIcons, cfg.growth = 4, 4, 4, "RIGHTDOWN"
    cfg.iconShape = type(Model.ReadSharedAppearanceIconShape) == "function"
        and Model.ReadSharedAppearanceIconShape(container) or cfg.iconShape
    ApplySharedAppearanceStyleToPreview(cfg, container)
    cfg.pandemicEnabled = false
    cfg.previewTextures = {}
    local entries = {}
    if playerDefensives then
        if type(Model.PlayerDefensivePreviewEntries) == "function" then
            entries = Model.PlayerDefensivePreviewEntries() or {}
        end
    elseif type(Model.TargetDotValues) == "function" then
        entries = Model.TargetDotValues() or {}
    end
    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and entry.header ~= true and entry.icon then
            cfg.previewTextures[#cfg.previewTextures + 1] = entry.icon
            if #cfg.previewTextures >= 4 then break end
        end
    end
    return cfg
end
local function FormatAuraPreviewTimer(seconds, cfg)
    seconds = tonumber(seconds) or 0
    local decimalSec = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3
    if decimalSec > 0 and seconds < decimalSec then return string.format("%.1f", seconds) end
    if seconds >= 60 then return tostring(max(1, floor(seconds / 60))) end
    return tostring(Round(seconds))
end
-- Sample icon art and the per-icon painters used by every mini preview. Hoisted
-- out of BuildMiniAuraPreview; RenderPreviewIcon takes the preview opts explicitly.
local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }
local function HidePreviewIcon(icon)
    icon:Hide()
    icon.swipe:Hide()
    icon.durationBar:Hide()
    icon.dispelBorder:Hide()
    if icon.msufStyleBorder then icon.msufStyleBorder:Hide() end
    if icon.msufStyleBorderPieces then MSUF.BorderStyles.Hide(icon.msufStyleBorderPieces) end
    if icon.msufStyleShadow then MSUF.BorderStyles.Hide(icon.msufStyleShadow) end
end
-- Mirrors the runtime's icon style: a BACKGROUND(-7) soft shadow band and a
-- BORDER(-1) ring that is either the flat pixel quad (Solid) or an edgeFile
-- drawn by the shared 8-piece renderer.
local function ApplyPreviewIconStyle(icon, cfg, barOnly)
    local B = MSUF.BorderStyles
    if type(A3.ApplyIconStylePreview) == "function" then
        local texture = B and cfg.styleBorderStyle and B.Resolve(cfg.styleBorderStyle) or nil
        local c, sc = cfg.styleBorderColor, cfg.styleShadowColor
        A3.ApplyIconStylePreview(icon, not barOnly and {
            borderEnabled = cfg.styleBorderEnabled == true,
            borderTexture = texture,
            borderEdge = B and B.EdgeSize(cfg.styleBorderStyle, cfg.styleBorderThickness or 1) or 1,
            borderPlacement = B and B.Placement(cfg.styleBorderStyle) or "outer",
            borderThickness = cfg.styleBorderThickness or 1,
            borderR = c and c[1] or 0, borderG = c and c[2] or 0,
            borderB = c and c[3] or 0, borderA = c and c[4] or 1,
            shadowEnabled = cfg.styleShadowEnabled == true,
            shadowSize = cfg.styleShadowSize or 4,
            shadowR = sc and sc[1] or 0, shadowG = sc and sc[2] or 0,
            shadowB = sc and sc[3] or 0, shadowA = sc and sc[4] or 0.8,
        } or nil, cfg.size, cfg.iconShape)
        return
    end
    local border = icon.msufStyleBorder
    local borderPieces = icon.msufStyleBorderPieces
    local texture = B and cfg.styleBorderStyle and B.Resolve(cfg.styleBorderStyle) or nil
    if cfg.styleBorderEnabled == true and not barOnly then
        local c = cfg.styleBorderColor
        local cr, cg, cb, ca = c and c[1] or 0, c and c[2] or 0, c and c[3] or 0, c and c[4] or 1
        local t = cfg.styleBorderThickness or 1
        if texture then
            if border then border:Hide() end
            -- Same split as the runtime: inner styles shade the icon from
            -- ARTWORK(7) on top, outer styles frame it from BORDER(-1).
            local inner = B.Placement(cfg.styleBorderStyle) == "inner"
            local edge = B.EdgeSize(cfg.styleBorderStyle, t)
            local inset = 0
            if inner then
                edge = max(1, min(edge, floor(cfg.size * 0.3)))
                inset = edge * 0.5
            end
            if borderPieces and icon.msufStyleBorderInner ~= inner then
                B.Hide(borderPieces)
                borderPieces = nil
            end
            if not borderPieces then
                borderPieces = B.Create(icon, inner and "ARTWORK" or "BORDER", inner and 7 or -1, texture)
                icon.msufStyleBorderPieces = borderPieces
                icon.msufStyleBorderInner = inner
            else
                B.SetTexture(borderPieces, texture)
            end
            B.Apply(borderPieces, icon, edge, cfg.size, cfg.size, cr, cg, cb, ca, inset)
        else
            if borderPieces then B.Hide(borderPieces) end
            if not border then
                border = icon:CreateTexture(nil, "BORDER", nil, -1)
                border:SetTexture("Interface\\Buttons\\WHITE8X8")
                icon.msufStyleBorder = border
            end
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", icon, "TOPLEFT", -t, t)
            border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", t, -t)
            border:SetVertexColor(cr, cg, cb, ca)
            border:Show()
        end
    else
        if border then border:Hide() end
        if borderPieces then B.Hide(borderPieces) end
    end
    local shadow = icon.msufStyleShadow
    if cfg.styleShadowEnabled == true and not barOnly and B then
        if not shadow then
            shadow = B.Create(icon, "BACKGROUND", -7, M.AURA_SHADOW_TEXTURE)
            icon.msufStyleShadow = shadow
        end
        local base = cfg.styleBorderEnabled == true and (cfg.styleBorderThickness or 1) or 0
        local extent = (cfg.styleShadowSize or 4) + base
        local c = cfg.styleShadowColor
        B.Apply(shadow, icon, extent * 2, cfg.size, cfg.size,
            c and c[1] or 0, c and c[2] or 0, c and c[3] or 0, c and c[4] or 0.8)
    elseif shadow then
        B.Hide(shadow)
    end
end
local function RenderPreviewIcon(icon, index, cfg, isBuffIcon, forceText, opts)
    icon:SetSize(cfg.size, cfg.size)
    icon:SetAlpha(tonumber(cfg.alpha) or 1)
    local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    local tex = isBuffIcon and buffTex or debuffTex
    local previewTextures = cfg.previewTextures
    local previewTexture = previewTextures and previewTextures[((index - 1) % max(1, #previewTextures)) + 1]
    icon.icon:SetTexture(previewTexture or tex[((index - 1) % #tex) + 1])
    ApplyAuraPreviewIconZoom(icon.icon, cfg.iconZoom)
    if type(A3.ApplyAuraIconShape) == "function" then
        cfg.iconShape = A3.ApplyAuraIconShape(icon, cfg.iconShape, nil, icon.bg, icon.icon, icon.swipe)
    end
    icon.bg:SetShown(not barOnly)
    icon.icon:SetShown(not barOnly)
    ApplyPreviewIconStyle(icon, cfg, barOnly)
    local r, g, b = isBuffIcon and 0.20 or 0.78, isBuffIcon and 0.72 or 0.20, isBuffIcon and 0.42 or 0.24
    local borderAtlas = (not barOnly and not isBuffIcon) and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode] or nil
    local showPreviewEdges = isBuffIcon == true and not barOnly and cfg.iconShape == "RECTANGLE"
    for _, edge in pairs(icon.edge) do edge:SetShown(showPreviewEdges); edge:SetVertexColor(r, g, b, 0.95) end
    icon.swipe:SetShown(cfg.showSwipe ~= false and not barOnly)
    icon.swipe:ClearAllPoints()
    if cfg.cooldownSwipeReverse == true then
        icon.swipe:SetPoint("TOPRIGHT", icon, "TOP", 0, -1)
        icon.swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
    else
        icon.swipe:SetPoint("TOPLEFT", icon, "TOP", 0, -1)
        icon.swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    end
    if borderAtlas and type(A3.ApplyAuraDispelPreview) == "function" then
        A3.ApplyAuraDispelPreview(icon.dispelBorder, icon, cfg.size, cfg.debuffBorderMode,
            cfg.iconShape, A3.PreviewDispelTypeForIndex(index))
    elseif borderAtlas and icon.dispelBorder.SetAtlas then
        local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
            and A3.NativeAuraDispelBorderPadding(cfg.size)
            or max(1, floor((cfg.size / 6) + 0.5))
        icon.dispelBorder:ClearAllPoints()
        icon.dispelBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        icon.dispelBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        icon.dispelBorder:SetAtlas(borderAtlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
        icon.dispelBorder:Show()
    else
        icon.dispelBorder:Hide()
    end
    if cfg.showDurationBar == true then
        local inset = max(1, floor((cfg.size / 32) + 0.5))
        local availableWidth = max(1, cfg.size - (inset * 2))
        -- This workbench is intentionally event-driven rather than animated.
        -- Give each sample aura a deterministic remaining fraction so the
        -- Remaining/Elapsed setting is still visible without an OnUpdate.
        local remainingFraction = max(0.18, 0.88 - (((index - 1) % 6) * 0.13))
        local fillFraction = cfg.durationBarDirection == "ELAPSED"
            and (1 - remainingFraction) or remainingFraction
        icon.durationBar:ClearAllPoints()
        icon.durationBar:SetHeight(cfg.durationBarHeight or 2)
        icon.durationBar:SetWidth(max(1, floor((availableWidth * fillFraction) + 0.5)))
        if cfg.durationBarPosition == "TOP" then
            icon.durationBar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        else
            icon.durationBar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        end
        local r, g, b = AuraDurationBarColor()
        icon.durationBar:SetVertexColor(r, g, b, 0.92)
        icon.durationBar:Show()
    else
        icon.durationBar:Hide()
    end
    ApplyAuraPreviewFont(icon.stack, cfg.stackSize)
    ApplyAuraPreviewFont(icon.timer, cfg.cooldownSize)
    PlaceAuraPreviewText(icon.stack, icon, cfg.stackAnchor, cfg.stackX, cfg.stackY)
    PlaceAuraPreviewText(icon.timer, icon, cfg.cooldownAnchor, cfg.cooldownX, cfg.cooldownY)
    icon.stack:SetText(cfg.showStacks and ((forceText or index % 3 == 1) and "2" or "") or "")
    local sampleSeconds = forceText and 2.7 or (index % 2 == 0 and 12 or nil)
    icon.timer:SetText(cfg.showTimers and sampleSeconds and FormatAuraPreviewTimer(sampleSeconds, cfg) or "")
    if type(A3.ApplyPandemicVisual) == "function"
        and (opts.previewContainer == "targetDots" or icon._msufA3PandemicRegion) then
        A3.ApplyPandemicVisual(icon, cfg,
            opts.previewContainer == "targetDots" and cfg.pandemicEnabled == true and index == 1 and not barOnly)
    end
    icon:Show()
end
local function BuildMiniAuraPreview(ctx, parent, scope, x, y, width, height, lane, opts)
    if ctx and ctx.hiddenBuild then return nil end
    opts = opts or {}
    lane = lane == "buff" and "buff" or (lane == "debuff" and "debuff" or nil)
    local box = T.Panel(parent, nil, { 0.010, 0.016, 0.034, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width or 300, height or 104)
    local innerPad = T.Space("md", 12)
    local headerH = T.Space("xxl", 32) + T.Space("optical", 2)
    local footerH = T.Space("xxl", 32) - T.Space("optical", 2)
    local contentHost = box
    local zoomPan = type(opts.zoomPan) == "table" and opts.zoomPan or nil
    if opts.focused == true then
        box._msuf2PreviewSurfaceFamily = "aura"
        if PreviewHelpers.ApplyPreviewChrome then PreviewHelpers.ApplyPreviewChrome(box, "canvas", T) end
        if box.SetClipsChildren then box:SetClipsChildren(true) end
        contentHost = CreateFrame("Frame", nil, box)
        contentHost:SetPoint("TOPLEFT", box, "TOPLEFT", innerPad, -headerH)
        contentHost:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -innerPad, footerH)
        if contentHost.SetClipsChildren then contentHost:SetClipsChildren(true) end
        box._msufAuraPreviewViewport = contentHost
    end
    local titleLabel = W.LabelAt(box, opts.title or "Sample Preview", innerPad, -innerPad, 240, "GameFontNormalSmall", T.colors.text)
    local meta
    if opts.focused == true then
        meta = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
        meta:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", innerPad, T.Space("sm", 8))
        meta:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -innerPad, T.Space("sm", 8))
        meta:SetJustifyH("LEFT")
        if meta.SetMaxLines then meta:SetMaxLines(1) end
        if meta.SetWordWrap then meta:SetWordWrap(false) end
        box._msufAuraPreviewMeta = meta
    end
    local icons = {}
    local iconCapacity = opts.focused == true and 0 or min(14, max(1, tonumber(opts.iconCapacity) or 14))
    for i = 1, iconCapacity do icons[i] = CreateAuraPreviewIcon(contentHost) end
    local function EnsureIconCapacity(count)
        count = min(opts.focused == true and 80 or iconCapacity, max(0, Round(count)))
        for i = #icons + 1, count do icons[i] = CreateAuraPreviewIcon(contentHost) end
        return count
    end
    local function RefreshPreview()
        if AurasMenuCombatLocked() then return end
        if opts.focused == true and parent.IsShown and not parent:IsShown() then return end
        local previewScope = type(opts.getPreviewScope) == "function" and opts.getPreviewScope() or scope
        if not AURA_SCOPE_VALID[previewScope] then previewScope = scope end
        if opts.focused == true then
            local cfg = type(opts.readConfig) == "function"
                and opts.readConfig(previewScope, lane, width, height)
                or ReadMiniAuraPreviewConfig(previewScope, lane, width, height)
            -- Sample is a styling workbench, so a lane configured with Max=0
            -- still renders one dummy icon instead of looking broken. Live mode
            -- continues to mirror the actual disabled/empty lane exactly.
            local count = EnsureIconCapacity(max(1, cfg.maxIcons))
            local naturalSize = max(1, tonumber(cfg.actualSize) or tonumber(cfg.size) or 24)
            local naturalGap = max(0, tonumber(cfg.spacing) or 0)
            local boxW, boxH = width or 300, height or 104
            local availableW = max(1, boxW - innerPad * 2)
            local availableH = max(1, boxH - headerH - footerH)
            local growth = tostring(cfg.growth or "RIGHTDOWN"):upper()
            local vertical = growth == "UP" or growth == "DOWN"
            local perLine = max(1, Round(cfg.perRow or count or 1))
            local columns, rows
            if count <= 0 then
                columns, rows = 1, 1
            elseif vertical then
                rows = min(perLine, count)
                columns = max(1, ceil(count / rows))
            else
                columns = min(perLine, count)
                rows = max(1, ceil(count / columns))
            end
            local naturalW = columns * naturalSize + max(0, columns - 1) * naturalGap
            local naturalH = rows * naturalSize + max(0, rows - 1) * naturalGap
            local fitScale = min(1, availableW / max(1, naturalW), availableH / max(1, naturalH))
            if zoomPan and zoomPan.Clamp then fitScale = zoomPan.Clamp(fitScale) end
            local scale = tonumber(box._manualZoom) or fitScale
            if zoomPan and zoomPan.Clamp then scale = zoomPan.Clamp(scale) end
            box._mockAutoScale, box._mockScale = fitScale, scale
            cfg.size = max(2, naturalSize * scale)
            cfg.spacing = naturalGap * scale
            cfg.stackSize = max(5, (tonumber(cfg.stackSize) or 10) * scale)
            cfg.cooldownSize = max(5, (tonumber(cfg.cooldownSize) or 9) * scale)
            cfg.durationBarHeight = max(1, (tonumber(cfg.durationBarHeight) or 2) * scale)
            cfg.styleBorderThickness = max(0.5, (tonumber(cfg.styleBorderThickness) or 1) * scale)
            cfg.styleShadowSize = max(0.5, (tonumber(cfg.styleShadowSize) or 4) * scale)
            local totalW = columns * cfg.size + max(0, columns - 1) * cfg.spacing
            local totalH = rows * cfg.size + max(0, rows - 1) * cfg.spacing
            local startX = (availableW - totalW) * 0.5
            local startY = -((availableH - totalH) * 0.5)
            local left = growth:find("LEFT", 1, true) ~= nil
            local up = growth:find("UP", 1, true) ~= nil
            for i = 1, #icons do
                local icon = icons[i]
                if i <= count then
                    local col, row
                    if vertical then
                        row = (i - 1) % rows
                        col = floor((i - 1) / rows)
                    else
                        col = (i - 1) % columns
                        row = floor((i - 1) / columns)
                    end
                    if left then col = columns - 1 - col end
                    if up then row = rows - 1 - row end
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", contentHost, "TOPLEFT",
                        startX + col * (cfg.size + cfg.spacing),
                        startY - row * (cfg.size + cfg.spacing))
                    RenderPreviewIcon(icon, i, cfg, lane == "buff", false, opts)
                else
                    HidePreviewIcon(icon)
                end
            end
            local label = ScopeLabel(previewScope)
            titleLabel:SetText(M.Format("%s Sample Preview", Tr(label)))
            if type(opts.getSampleMeta) == "function" then
                meta:SetText(opts.getSampleMeta(cfg, previewScope) or "")
            else
                meta:SetText(label .. " / " .. tostring(Round(cfg.actualSize or cfg.size or 0)) .. "px")
            end
            if zoomPan and zoomPan.UpdateControls then zoomPan.UpdateControls(box) end
            return
        end
        if meta then meta:SetText("") end
        local cfg = type(opts.readConfig) == "function"
            and opts.readConfig(previewScope, lane, width, height)
            or ReadMiniAuraPreviewConfig(previewScope, lane, width, height)
        for i = 1, #icons do
            local icon = icons[i]
            if i <= cfg.count then
                local growth = tostring(cfg.growth or "RIGHTDOWN"):upper()
                local vertical = growth == "UP" or growth == "DOWN"
                local col = vertical and floor((i - 1) / max(1, cfg.rowsPerColumn)) or ((i - 1) % cfg.columns)
                local row = vertical and ((i - 1) % max(1, cfg.rowsPerColumn)) or floor((i - 1) / cfg.columns)
                local left = growth:find("LEFT", 1, true) ~= nil
                local up = growth:find("UP", 1, true) ~= nil
                local startX = left and ((width or 300) - 10 - cfg.size) or 10
                local startY = up and (-((height or 104) - 10 - cfg.size)) or -34
                local step = cfg.size + cfg.spacing
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", box, "TOPLEFT", startX + col * step * (left and -1 or 1), startY + row * step * (up and 1 or -1))
                local isBuffIcon = lane and lane == "buff" or (not lane and i <= 7)
                RenderPreviewIcon(icon, i, cfg, isBuffIcon, false, opts)
            else
                HidePreviewIcon(icon)
            end
        end
    end
    box.Refresh = RefreshPreview
    M.TrackRefresh(ctx, RefreshPreview)
    return box, RefreshPreview
end
local function BuildAuraStylePreviewWorkbench(ctx, b, scope, lane, previewContainer)
    local rowY = -40
    local panelY = -68
    local panelH = 100
    local sectionH = 180
    local section, _, fixedPreview = W.FixedPreviewSection(ctx, b, {
        title = "Preview",
        height = sectionH,
    })
    local width = section._msuf2Width or b.width or 720
    local pad = T.Space("xl", 24)
    local previewLabel = previewContainer == "playerDefensives" and "Player Defensives"
        or previewContainer == "targetDots" and "Dots on Target"
        or LanePlural(previewContainer or lane)
    W.LabelAt(section, M.Format("Shared Preview - %s", Tr(previewLabel)), pad, rowY,
        width - (pad * 2), "GameFontNormalSmall", T.colors.accent)

    local refreshPreview
    local zoomPan = M.AuraStylePreviewZoomPan
    if type(zoomPan) ~= "table" then
        zoomPan = {}
        M.AuraStylePreviewZoomPan = zoomPan
    end
    if type(zoomPan.SetZoom) ~= "function" and PreviewHelpers.InstallZoomPan then
        PreviewHelpers.InstallZoomPan(zoomPan, {
            configureTableOnly = true,
            readoutField = "zoomReadout",
            fitButtonTextPath = { "zoomFitButton", "fs" },
            defaultReason = "AURA_STYLE_PREVIEW_ZOOM",
            stepReason = "AURA_STYLE_PREVIEW_ZOOM_STEP",
            themeButton = true,
            buttonTextureKey = "TEX_W8",
            buttonFontField = "fs",
        })
    end
    if zoomPan.Configure then zoomPan.Configure({ T = T, TR = Tr, TEX_W8 = TEX_W8 }) end
    local panelW = width - (pad * 2)
    local box
    local specialPreview = previewContainer == "playerDefensives" or previewContainer == "targetDots"
    local previewLane = previewContainer == "playerDefensives" and "buff"
        or previewContainer == "targetDots" and "debuff" or lane
    box, refreshPreview = BuildMiniAuraPreview(ctx, section, scope, pad, panelY, panelW, panelH, previewLane, {
        focused = true,
        zoomPan = zoomPan,
        previewContainer = previewContainer,
        readConfig = specialPreview and function(_, _, configWidth, configHeight)
            return ReadSharedSpecialAuraPreviewConfig(previewContainer, configWidth, configHeight)
        end or nil,
        getSampleMeta = function(cfg)
            local swipe = cfg.cooldownSwipeReverse == true and "Reverse swipe" or "Default swipe"
            local owner = previewContainer == "playerDefensives" and "Shared Player Defensive theme"
                or previewContainer == "targetDots" and "Shared Dots on Target theme"
                or "Global Aura theme"
            return tostring(Round(cfg.actualSize or cfg.size or 0)) .. "px / " .. swipe .. " / " .. owner
        end,
    })
    if box then box.Refresh = refreshPreview end
    if box then
        if PreviewHelpers.BuildZoomBar and type(zoomPan.SetZoom) == "function" then
            local zoomBar = PreviewHelpers.BuildZoomBar(box, box, {
                width = 200,
                texture = TEX_W8,
                T = T,
                M = M,
                W = W,
                themeReadout = true,
                CreateZoomButton = zoomPan.CreateButton,
                Tr = Tr,
                StepZoom = zoomPan.Step,
                SetZoom = zoomPan.SetZoom,
                fitReason = "AURA_STYLE_PREVIEW_ZOOM_FIT",
                oneReason = "AURA_STYLE_PREVIEW_ZOOM_1TO1",
                helpTitle = "Aura Preview Zoom",
                helpLines = {
                    Tr("Use - / + or Ctrl + mouse wheel to zoom."),
                    Tr("Fit shows the complete aura layout."),
                    Tr("1:1 shows the configured aura pixel size."),
                    Tr("Zoom changes only this preview, not your Aura settings."),
                },
            })
            if zoomBar then
                zoomBar:ClearAllPoints()
                zoomBar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -T.Space("md", 12), T.Space("xs", 4) + 2)
                local backgroundButton = box.previewBackgroundButton
                if backgroundButton then
                    backgroundButton:ClearAllPoints()
                    backgroundButton:SetPoint("RIGHT", zoomBar, "LEFT", -T.Space("xs", 4), 0)
                    local meta = box._msufAuraPreviewMeta
                    if meta then
                        meta:ClearAllPoints()
                        meta:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", T.Space("md", 12), T.Space("sm", 8))
                        meta:SetPoint("BOTTOMRIGHT", backgroundButton, "BOTTOMLEFT", -T.Space("sm", 8), 0)
                    end
                end
                if PreviewHelpers.BindPreviewWheel then
                    PreviewHelpers.BindPreviewWheel(box._msufAuraPreviewViewport, box, box._msuf2PreviewZoomWheel)
                end
            end
            if zoomPan.UpdateControls then zoomPan.UpdateControls(box) end
        end
    end
    local pinnedPreviewOpts
    if box and W.AttachPinnedPreview then
        pinnedPreviewOpts = {
            stateKey = "auraStylePreview",
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
        }
        W.AttachPinnedPreview(section, box, pinnedPreviewOpts)
    end
    local previewShowSerial = 0
    local function RefreshVisibleAuraPreview()
        if type(refreshPreview) ~= "function" then return end
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return end
        if section.IsShown and not section:IsShown() then return end
        if box and pinnedPreviewOpts then
            -- Navigating away runs ReleasePinnedPreviews: it drops the box's
            -- ownership record and hides the box. A cached re-entry skips the
            -- page build, so nothing re-attaches or shows it; this page has no
            -- expander whose Open() would rescue it either. Reclaim both here,
            -- on the page-activation refresh that only runs while the page owns
            -- the docked section.
            if not box._msuf2PinnedPreviewRecord then
                W.AttachPinnedPreview(section, box, pinnedPreviewOpts)
            end
            if box.IsShown and not box:IsShown() then box:Show() end
        end
        refreshPreview()
    end
    local function QueueVisibleAuraPreview()
        previewShowSerial = previewShowSerial + 1
        local serial = previewShowSerial
        RefreshVisibleAuraPreview()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if serial == previewShowSerial then RefreshVisibleAuraPreview() end
            end)
            C_Timer.After(0.05, function()
                if serial == previewShowSerial then RefreshVisibleAuraPreview() end
            end)
        end
    end
    if section.HookScript then
        section:HookScript("OnShow", QueueVisibleAuraPreview)
        section:HookScript("OnHide", function() previewShowSerial = previewShowSerial + 1 end)
    end
    if ctx and ctx.wrapper and ctx.wrapper.HookScript then
        ctx.wrapper:HookScript("OnShow", QueueVisibleAuraPreview)
    end
    QueueVisibleAuraPreview()
    -- Fixed under the Aura scope/navigation stack; styling controls scroll below.
    if fixedPreview then fixedPreview.onActivate = QueueVisibleAuraPreview end
    return refreshPreview
end
-- The Style builders on the page and in the Group sibling reach these lazily at
-- build time.
M.Assign(AurasPage, {
    RefreshMiniAuraPreviewNow = RefreshMiniAuraPreviewNow,
    BuildAuraStylePreviewWorkbench = BuildAuraStylePreviewWorkbench,
})
