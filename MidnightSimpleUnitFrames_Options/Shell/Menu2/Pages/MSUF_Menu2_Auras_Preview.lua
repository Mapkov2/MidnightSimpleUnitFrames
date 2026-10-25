local _, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_Auras_Preview.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB

-- Menu2 Auras page: sample previews.
-- Owns the runtime aura workbench adapter, the config readers for unit and group
-- scopes, and the Aura Style preview workbench (zoom bar, pinned preview). Split
-- It reads shared AuraSettings and the five AuraGroupSettings readers, then
-- publishes just the two preview entry points called by the Style builders.
local AurasPage = M.AurasPage
if type(AurasPage) ~= "table" then return end
local W = M.Widgets
local T = M.Theme
local A3 = MSUF.MSUF_Auras3
local AuraPainter = assert(MSUF.Require("MSUF_Auras3", "Menu2/Auras_Preview").MockAuraPainter,
    "MSUF: missing core mock aura painter")
local Model = A3 and A3.MenuModel
local PreviewHelpers = M.PreviewHelpers or {}
local CreateFrame = CreateFrame
local C_Timer = M.MenuTimer or C_Timer
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local AURA_SCOPE_VALID, AccessibleNumber, AurasMenuCombatLocked =
    M.AuraSettings.AURA_SCOPE_VALID, M.AuraSettings.AccessibleNumber, M.AuraSettings.AurasMenuCombatLocked
local IsGroupScope, LaneDefaultMax, LaneMaxKey, LanePlural =
    M.AuraSettings.IsGroupScope, M.AuraSettings.LaneDefaultMax, M.AuraSettings.LaneMaxKey, M.AuraSettings.LanePlural
local LaneSizeKey, Round, ScopeLabel, Tr = M.AuraSettings.LaneSizeKey, M.AuraSettings.Round, M.AuraSettings.ScopeLabel, M.AuraSettings.Tr
local GroupScopeKinds, GroupConf, GFReadRoot, GFReadGroup =
    M.AuraGroupSettings.GroupScopeKinds, M.AuraGroupSettings.GroupConf, M.AuraGroupSettings.GFReadRoot, M.AuraGroupSettings.GFReadGroup
local ReadGroupDebuffTypeBorderMode = M.AuraGroupSettings.ReadGroupDebuffTypeBorderMode
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
        -- The aura type's skin, read live so the preview shows edits made in combat
        -- at once; the default skin and look come from the Icon Skins page.
        cfg.styleSkin = Model.ReadSharedAppearanceValue(kind, "styleSkin", nil)
    end
end

local function FitMiniAuraPreview(cfg, width, height)
    -- The runtime workbench fits its whole canvas; viewport size never changes lane geometry.
    cfg.actualSize = tonumber(cfg.size) or 24
    cfg.spacing = max(0, tonumber(cfg.spacing) or 2)
    cfg.perRow = max(1, Round(cfg.perRow))
    cfg.maxIcons = max(0, Round(cfg.maxIcons))
    cfg.count = min(14, cfg.maxIcons)
    cfg.stackSize = tonumber(cfg.stackSize) or 10
    cfg.cooldownSize = tonumber(cfg.cooldownSize) or 9
    cfg.cooldownDecimalSeconds = min(30, max(0, tonumber(cfg.cooldownDecimalSeconds) or 3))
    cfg.durationBarHeight = min(max(1, tonumber(cfg.durationBarHeight) or 2), max(1, cfg.size or 24))
    cfg.durationBarDisplay = cfg.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    cfg.durationBarPosition = cfg.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
    cfg.durationBarDirection = cfg.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
    return cfg
end
-- Read on every preview refresh (a style slider tick), so the group and unit
-- readers stay inline in this one function instead of costing extra calls.
local function ReadMiniAuraPreviewConfig(scope, lane, width, height)
    local isGroup = IsGroupScope(scope)
    local cfg = {
        size = 24, spacing = 2, perRow = 7, maxIcons = 14,
        showStacks = true, showTimers = true, showSwipe = true, cooldownSwipeReverse = false,
        stackSize = 10, stackAnchor = "TOPRIGHT", stackX = -1, stackY = -1,
        cooldownSize = 9, cooldownAnchor = "CENTER", cooldownX = 0, cooldownY = 0,
        debuffBorderMode = "OFF", showDurationBar = false, durationBarHeight = 2,
        durationBarDisplay = "BAR_ONLY", durationBarPosition = "BOTTOM", durationBarDirection = "REMAINING",
        iconZoom = 100, iconShape = "RECTANGLE",
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
        cfg.heightPercent = lane and Model.ReadLaneStyleNumber(readScope, lane, "iconHeightPercent", 100, 25, 200)
            or Model.ReadNumber(readScope, "iconHeightPercent", 100, 25, 200)
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
        cfg.stackSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "stackTextSize", 14, 6,
            40)
        cfg.stackAnchor = lane and type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(readScope,
            lane) or Model.ReadStackAnchor(readScope)
        cfg.stackX = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetX", -1, -2000, 2000) or Model.ReadNumber(readScope,
            "stackTextOffsetX", -1, -2000, 2000)
        cfg.stackY = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetY", 1, -2000, 2000) or Model.ReadNumber(readScope,
            "stackTextOffsetY", 1, -2000, 2000)
        cfg.cooldownSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextSize", 14, 6, 40) or Model.ReadNumber(readScope,
            "cooldownTextSize", 14, 6, 40)
        if lane and type(Model.ReadLaneCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadLaneCooldownAnchor(readScope, lane)
        elseif type(Model.ReadCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadCooldownAnchor(readScope)
        elseif runtimePreview and runtimePreview.cooldownAnchor then
            cfg.cooldownAnchor = runtimePreview.cooldownAnchor
        end
        cfg.cooldownX = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetX", 0, -2000, 2000) or Model.ReadNumber(readScope,
            "cooldownTextOffsetX", 0, -2000, 2000)
        cfg.cooldownY = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetY", 0, -2000, 2000) or Model.ReadNumber(readScope,
            "cooldownTextOffsetY", 0, -2000, 2000)
        cfg.cooldownDecimalSeconds = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownDecimalSeconds", 3, 0, 30) or Model.ReadNumber(readScope,
            "cooldownDecimalSeconds", 3, 0, 30)
        cfg.durationBarHeight = lane and Model.ReadLaneStyleNumber(readScope, lane, "durationBarHeight", 2, 1, 16) or Model.ReadNumber(readScope,
            "durationBarHeight", 2, 1, 16)
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
    return FitMiniAuraPreview(cfg, width, height)
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
local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }

-- The icon style the runtime draws: a BACKGROUND(-7) soft shadow band and a BORDER(-1)
-- ring, solid or from an edgeFile (inner styles shade from ARTWORK(7) on top). IconShape
-- loads that shared renderer on every supported client before this page and owns it.
local function PreviewIconStyle(cfg, barOnly)
    if barOnly then return nil end
    local B = MSUF.BorderStyles
    local texture = B and cfg.styleBorderStyle and B.Resolve(cfg.styleBorderStyle) or nil
    local c, sc = cfg.styleBorderColor, cfg.styleShadowColor
    local style = {
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
    }
    -- cfg carries the aura type's live skin (ApplySharedAppearanceStyleToPreview).
    return A3.IconSkins and A3.IconSkins.AttachPreview(style, cfg, A3.IconSkins.LiveDefault()) or style
end

--- The style an aura type's icons show (its border, shadow and skin), for the
--- Icon Skins page's strip.
local function ProductIconStyle(kind)
    local cfg = {}
    ApplySharedAppearanceStyleToPreview(cfg, kind)
    return PreviewIconStyle(cfg, false)
end
local function WorkbenchRefresh(P)
    return function()
        if AurasMenuCombatLocked() or not P.parent:IsVisible() then return end
        local opts, scope = P.opts, P.scope
        local selected = opts.getPreviewScope and opts.getPreviewScope() or scope
        if not AURA_SCOPE_VALID[selected] then selected = scope end
        local cfg = opts.readConfig and opts.readConfig(selected, P.lane, P.width, P.height)
            or ReadMiniAuraPreviewConfig(selected, P.lane, P.width, P.height)
        local count = min(opts.focused and 80 or P.iconCapacity, max(0, Round(opts.focused and cfg.maxIcons or cfg.count)))
        local workbench = P.workbench
        local width, height = workbench:Paint(cfg, count, P.lane, PreviewIconStyle(cfg, cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"),
            cfg.previewTextures or (P.lane == "debuff" and debuffTex or buffTex))
        local fit = min(1, max(1, P.contentHost:GetWidth()) / width, max(1, P.contentHost:GetHeight()) / height)
        if P.zoomPan then fit = P.zoomPan.Clamp(fit) end
        local scale = tonumber(P.box._manualZoom) or fit
        if P.zoomPan then scale = P.zoomPan.Clamp(scale) end
        P.box._mockAutoScale, P.box._mockScale = fit, scale
        workbench:Fit(scale)
        local label = ScopeLabel(selected)
        T.SetTranslatedText(P.titleLabel, M.Format("%s Sample Preview", Tr(label)))
        if P.meta then
            T.SetTranslatedText(P.meta, opts.getSampleMeta and opts.getSampleMeta(cfg, selected)
                or M.Format("%s / %d px", Tr(label), Round(cfg.actualSize or cfg.size or 0)))
        end
        if P.zoomPan then P.zoomPan.UpdateControls(P.box) end
    end
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
        contentHost = PixelLayoutRegion(CreateFrame("Frame", nil, box))
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
    local P = {
        opts = opts, parent = parent, scope = scope, lane = lane, width = width, height = height,
        box = box, contentHost = contentHost, zoomPan = zoomPan, innerPad = innerPad,
        headerH = headerH, footerH = footerH, titleLabel = titleLabel, meta = meta,
        iconCapacity = min(14, max(1, tonumber(opts.iconCapacity) or 14)),
        workbench = AuraPainter.NewWorkbench(contentHost),
    }
    local RefreshPreview = WorkbenchRefresh(P)
    box.Refresh = RefreshPreview
    M.TrackRefresh(ctx, RefreshPreview)
    return box, RefreshPreview
end
-- The shared workbench zoom/pan controller, installed once and reconfigured
-- with the live theme on every build.
local function AuraStylePreviewZoomPan()
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
    return zoomPan
end
-- The zoom bar docks bottom-right; the background button and meta line move left of it.
local function AttachAuraPreviewZoomBar(box, zoomPan)
    if not (PreviewHelpers.BuildZoomBar and type(zoomPan.SetZoom) == "function") then return end
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
    local zoomPan = AuraStylePreviewZoomPan()
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
            return M.Format("%d px / %s / %s", Round(cfg.actualSize or cfg.size or 0), Tr(swipe), Tr(owner))
        end,
    })
    if box then box.Refresh = refreshPreview end
    if box then
        AttachAuraPreviewZoomBar(box, zoomPan)
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
    ProductIconStyle = ProductIconStyle,
})
