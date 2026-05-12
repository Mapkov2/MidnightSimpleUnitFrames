local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme

local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

local SCOPE_VALUES = {
    { value = "party", text = "Party" },
    { value = "raid", text = "Raid" },
    { value = "mythicraid", text = "Mythic Raid" },
}

local GROWTH_VALUES = {
    { value = "DOWN", text = "Down" },
    { value = "UP", text = "Up" },
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
}

local HEALTH_MODES = {
    { value = "CLASS", text = "Class" },
    { value = "GRADIENT", text = "Gradient" },
    { value = "CUSTOM", text = "Custom" },
}

local TEXT_MODES = {
    { value = "NONE", text = "None" },
    { value = "PERCENT", text = "Percent" },
    { value = "CURRENT", text = "Current" },
    { value = "MAX", text = "Max" },
    { value = "DEFICIT", text = "Deficit" },
    { value = "CURMAX", text = "Current / Max" },
    { value = "CURPERCENT", text = "Current / Percent" },
    { value = "CURMAXPERCENT", text = "Current / Max / Percent" },
}

local ANCHORS = {
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
}

local AURA_ANCHORS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local GF_RENDERERS = {
    { value = "BLIZZARD", text = "Blizzard" },
    { value = "CUSTOM", text = "Custom" },
}

local GF_AURA_FILTERS = {
    { value = "RAID", text = "Raid helpful" },
    { value = "ALL", text = "All" },
    { value = "PLAYER", text = "Mine only" },
}

local GF_AURA_ORG = {
    { value = "default", text = "Default" },
    { value = "BUFFS_TOP_DEBUFFS_BOTTOM", text = "Buffs Top / Debuffs Bottom" },
    { value = "BUFFS_RIGHT_DEBUFFS_LEFT", text = "Buffs Right / Debuffs Left" },
}

local SORT_MODES = {
    { value = "INDEX", text = "Index (Default)" },
    { value = "ROLE", text = "By Role" },
    { value = "GROUP", text = "By Raid Group" },
    { value = "GROUP_ROLE", text = "Group + Role" },
    { value = "NAME", text = "Alphabetical" },
}

local GF_BAR_MODES = {
    { value = "GLOBAL", text = "Follow Global Style" },
    { value = "CLASS", text = "Class Color" },
    { value = "dark", text = "Dark Mode" },
    { value = "unified", text = "Unified Color" },
    { value = "GRADIENT", text = "Health Gradient" },
    { value = "CUSTOM", text = "Custom Color" },
}

local SIMPLE_TEXTURES = {
    { value = "", text = "Follow Global Style" },
    { value = "Blizzard", text = "Blizzard" },
    { value = "Solid", text = "Solid" },
    { value = "Flat", text = "Flat" },
    { value = "MSUF Smooth v2", text = "MSUF Smooth v2" },
}

local GF_ANCHOR_TO = {
    { value = "FREE", text = "Free (UIParent)" },
    { value = "player", text = "Player Frame" },
    { value = "target", text = "Target Frame" },
    { value = "targettarget", text = "Target of Target" },
    { value = "focus", text = "Focus Frame" },
}

local GF_ANCHOR_POINTS = {
    { value = "TOPLEFT", text = "TOPLEFT" },
    { value = "TOP", text = "TOP" },
    { value = "TOPRIGHT", text = "TOPRIGHT" },
    { value = "LEFT", text = "LEFT" },
    { value = "CENTER", text = "CENTER" },
    { value = "RIGHT", text = "RIGHT" },
    { value = "BOTTOMLEFT", text = "BOTTOMLEFT" },
    { value = "BOTTOM", text = "BOTTOM" },
    { value = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
}

local TOOLTIP_MODES = {
    { value = "ALWAYS", text = "Always" },
    { value = "OOC", text = "Out of Combat" },
    { value = "MODIFIER", text = "Modifier Key" },
    { value = "NEVER", text = "Never" },
}

local TOOLTIP_MODIFIERS = {
    { value = "ALT", text = "Alt" },
    { value = "CTRL", text = "Ctrl" },
    { value = "SHIFT", text = "Shift" },
}

local STATUS_ICON_ANCHORS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}

local GF_STATUS_ICON_SPECS = {
    { value = "roleIcon", text = "Role Icon", enabled = "roleIcon", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", layer = "roleIconLayer", defaultSize = 12, defaultAnchor = "TOPLEFT", defaultLayer = 1 },
    { value = "leaderIcon", text = "Leader", enabled = "leaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", layer = "leaderIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2 },
    { value = "assistIcon", text = "Assist", enabled = "assistIcon", size = "assistIconSize", anchor = "assistIconAnchor", x = "assistIconX", y = "assistIconY", layer = "assistIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2 },
    { value = "raidMarker", text = "Raid Marker", enabled = "raidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerX", y = "raidMarkerY", layer = "raidMarkerLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 3 },
    { value = "readyCheckIcon", text = "Ready Check", enabled = "readyCheckIcon", size = "readyCheckSize", anchor = "readyCheckAnchor", x = "readyCheckX", y = "readyCheckY", layer = "readyCheckLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4 },
    { value = "summonIcon", text = "Summon", enabled = "summonIcon", size = "summonIconSize", anchor = "summonAnchor", x = "summonX", y = "summonY", layer = "summonLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4 },
    { value = "resurrectIcon", text = "Resurrect", enabled = "resurrectIcon", size = "resurrectIconSize", anchor = "resurrectAnchor", x = "resurrectX", y = "resurrectY", layer = "resurrectLayer", defaultSize = 16, defaultAnchor = "CENTER", defaultLayer = 4 },
    { value = "phaseIcon", text = "Phase", enabled = "phaseIcon", size = "phaseIconSize", anchor = "phaseAnchor", x = "phaseX", y = "phaseY", layer = "phaseLayer", defaultSize = 14, defaultAnchor = "TOPLEFT", defaultLayer = 3 },
    { value = "statusText", text = "Dead Text", enabled = "statusText", size = "statusTextSize", anchor = "statusTextAnchor", x = "statusOffsetX", y = "statusOffsetY", layer = "statusTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7 },
    { value = "statusGhostText", text = "Ghost Text", enabled = "statusGhostText", size = "statusGhostTextSize", anchor = "statusGhostTextAnchor", x = "statusGhostOffsetX", y = "statusGhostOffsetY", layer = "statusGhostTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7 },
    { value = "statusAFKText", text = "AFK / DND Text", enabled = "statusAFKText", size = "statusAFKTextSize", anchor = "statusAFKTextAnchor", x = "statusAFKOffsetX", y = "statusAFKOffsetY", layer = "statusAFKTextLayer", defaultSize = 14, defaultAnchor = "CENTER", defaultLayer = 7 },
}

local GF_STATUS_ICON_VALUES = {}
for i = 1, #GF_STATUS_ICON_SPECS do
    GF_STATUS_ICON_VALUES[i] = { value = GF_STATUS_ICON_SPECS[i].value, text = GF_STATUS_ICON_SPECS[i].text }
end

local PLACED_INDICATOR_TYPES = {
    { value = "none", text = "None" },
    { value = "icon", text = "Icon" },
    { value = "square", text = "Square" },
    { value = "bar", text = "Bar" },
    { value = "number", text = "Number" },
}

local FRAME_EFFECT_TYPES = {
    { value = "none", text = "None" },
    { value = "healthtint", text = "Health Tint" },
    { value = "border", text = "Border" },
    { value = "glow", text = "Glow" },
    { value = "pulse", text = "Pulse" },
    { value = "namecolor", text = "Name Color" },
}

local SPELL_GROWTH_VALUES = {
    { value = "RIGHTDOWN", text = "Right then Down" },
    { value = "LEFTDOWN", text = "Left then Down" },
    { value = "RIGHTUP", text = "Right then Up" },
    { value = "LEFTUP", text = "Left then Up" },
}

local CI_SLOT_VALUES = {
    { value = "TL", text = "Top Left" },
    { value = "TR", text = "Top Right" },
    { value = "BL", text = "Bottom Left" },
    { value = "BR", text = "Bottom Right" },
    { value = "C", text = "Center" },
}

local CI_SLOT_DEFAULTS = {
    TL = "dispel",
    TR = "aggro",
    BL = "none",
    BR = "none",
    C = "none",
}

local DISPEL_OVERLAY_STYLES = {
    { value = "FULL", text = "Full Frame" },
    { value = "BOTTOM", text = "Bottom Edge" },
    { value = "TOP", text = "Top Edge" },
    { value = "LEFT", text = "Left Edge" },
    { value = "RIGHT", text = "Right Edge" },
}

local DEBUFF_STRIPE_EDGES = {
    { value = "BOTTOM", text = "Bottom Edge" },
    { value = "TOP", text = "Top Edge" },
}

local pendingGF = {}
local gfFlushQueued = false

local function GF()
    return ns and ns.GF
end

local function RefreshGFPreview()
    local gf = GF()
    if gf and type(gf.RefreshPreviewBox) == "function" then gf.RefreshPreviewBox() end
    if gf and type(gf.ResizePreviewContainer) == "function" then gf.ResizePreviewContainer() end
    if type(M.RefreshGFNativePreviews) == "function" then M.RefreshGFNativePreviews() end
end

local function Conf(kind)
    local gf = GF()
    if gf and type(gf.GetConf) == "function" then return gf.GetConf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end

local function Val(kind, key, default)
    local gf = GF()
    if gf and type(gf.Val) == "function" then
        local value = gf.Val(kind, key)
        if value ~= nil then return value end
    end
    local conf = Conf(kind)
    if conf[key] ~= nil then return conf[key] end
    return default
end

local function FlushGF()
    gfFlushQueued = false
    local gf = GF()
    if not gf then return end
    local rebuild = pendingGF.rebuild
    local geometry = pendingGF.geometry
    local visual = pendingGF.visual
    local font = pendingGF.font
    pendingGF.rebuild = nil
    pendingGF.geometry = nil
    pendingGF.visual = nil
    pendingGF.font = nil
    if rebuild and type(gf.RebuildAll) == "function" then
        gf.RebuildAll()
        RefreshGFPreview()
        return
    end
    if geometry then
        if type(gf.RefreshGeometry) == "function" then gf.RefreshGeometry() end
        if type(gf.MarkAllDirty) == "function" then gf.MarkAllDirty(gf.DIRTY_LAYOUT or 32) end
    end
    if font and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
    if visual then
        if type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals() end
        if type(gf.MarkAllDirty) == "function" then gf.MarkAllDirty(gf.DIRTY_VISUAL or 2) end
    end
    RefreshGFPreview()
end

local function QueueGF(kind, mode)
    if mode == "rebuild" then pendingGF.rebuild = true end
    if mode == "geometry" then pendingGF.geometry = true end
    if mode == "visual" then pendingGF.visual = true end
    if mode == "font" then pendingGF.font = true; pendingGF.visual = true end
    if gfFlushQueued then return end
    gfFlushQueued = true
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("MSUF2_GF_APPLY", FlushGF)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushGF)
    else
        FlushGF()
    end
end

local function Set(kind, key, value, mode)
    local conf = Conf(kind)
    if conf[key] == value then return end
    conf[key] = value
    QueueGF(kind, mode or "visual")
end

local function Bool(kind, key, default)
    local value = Val(kind, key, default and true or false)
    return value and true or false
end

local function Num(kind, key, default)
    return tonumber(Val(kind, key, default)) or default or 0
end

local function ScopeSection(ctx, builder)
    local sec = builder:Section("Scope", 100)
    local scope = W.Segment(sec, "Editing", SCOPE_VALUES, 480)
    M.BindSegment(ctx, scope,
        function() return M.gfScope or "party" end,
        function(v)
            M.gfScope = v or "party"
            local gf = GF()
            if gf and type(gf.PreviewScopeChanged) == "function" then
                gf.PreviewScopeChanged()
            else
                RefreshGFPreview()
            end
            if ctx.refreshers then
                for i = 1, #ctx.refreshers do
                    local fn = ctx.refreshers[i]
                    if type(fn) == "function" then pcall(fn) end
                end
            end
        end)
end

local function CurrentScope()
    return M.gfScope or "party"
end

local SECTION_PAGE = {
    general = "gf_layout",
    layout = "gf_layout",
    sorting = "gf_layout",
    scaling = "gf_layout",
    border = "gf_layout",
    anchor = "gf_layout",
    tooltip = "gf_layout",

    hcolor = "gf_bars",
    bars = "gf_bars",
    power = "gf_bars",
    text = "gf_bars",
    healpred = "gf_bars",
    dispel = "gf_bars",
    dstripe = "gf_bars",
    range = "gf_bars",

    blizzrenderer = "gf_auras",
    buffs = "gf_auras",
    debuffs = "gf_auras",
    ext = "gf_auras",
    textcolor = "gf_auras",
    priv = "gf_auras",
    masque = "gf_auras",
    autil = "gf_auras",

    indicators = "gf_indicators",
    sicons = "gf_indicators",
    si = "gf_indicators",
    ci = "gf_indicators",
}

local PAGE_FOCUS = {
    gf_layout = "layout",
    gf_bars = "text",
    gf_auras = "blizzrenderer",
    gf_indicators = "indicators",
}

local function PageForGFSection(sectionKey)
    return SECTION_PAGE[sectionKey or ""]
end

local function PreviewFocusForPage(pageKey)
    local focus = M.gfPreviewFocus
    if focus and PageForGFSection(focus) == pageKey then return focus end
    return PAGE_FOCUS[pageKey]
end

local function OpenGFSection(sectionKey)
    M.gfPreviewFocus = sectionKey
    local pageKey = PageForGFSection(sectionKey)
    if pageKey and M.SelectPage then M.SelectPage(pageKey) end
end

local function PreviewScopeLabel(kind)
    if kind == "raid" then return "Raid" end
    if kind == "mythicraid" then return "Mythic Raid" end
    return "Party"
end

local function MakePreviewSectionButton(parent, label, color, sectionKey, onOpen)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(68, 16)
    btn._sectionKey = sectionKey
    btn._bg = btn:CreateTexture(nil, "BACKGROUND")
    btn._bg:SetAllPoints()
    btn._bg:SetColorTexture(0.020, 0.024, 0.046, 0.85)
    btn._stripe = btn:CreateTexture(nil, "ARTWORK")
    btn._stripe:SetPoint("LEFT", btn, "LEFT", 0, 0)
    btn._stripe:SetSize(2, 12)
    btn._stripe:SetColorTexture(color[1], color[2], color[3], 1)
    btn._label = T.Font(btn, "GameFontDisableSmall", label, T.colors.muted)
    btn._label:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn._label:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn._label:SetJustifyH("LEFT")
    btn:SetScript("OnClick", function(self)
        if type(onOpen) == "function" then onOpen(self._sectionKey) end
    end)
    function btn:SetPreviewActive(active, visible, solo)
        visible = visible ~= false
        if solo then
            self._bg:SetColorTexture(0.20, 0.14, 0.02, 0.75)
            self._stripe:SetColorTexture(1.00, 0.82, 0.18, 1)
            self._label:SetTextColor(1.00, 0.92, 0.62, 1)
        elseif active and visible then
            local bg, tx = T.colors.pillActive, T.colors.pillTextActive
            self._bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
            self._label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1)
            self._stripe:SetAlpha(1)
        elseif not visible then
            self._bg:SetColorTexture(0.02, 0.02, 0.03, 0.45)
            self._stripe:SetColorTexture(0.16, 0.16, 0.20, 0.45)
            self._label:SetTextColor(0.38, 0.40, 0.48, 0.70)
        else
            self._bg:SetColorTexture(0.020, 0.024, 0.046, 0.85)
            local tx = T.colors.pillText or T.colors.muted
            self._label:SetTextColor(tx[1], tx[2], tx[3], 0.95)
            self._stripe:SetAlpha(1)
        end
    end
    return btn
end

local function ResolvePreviewStatusbarTexture(conf, key)
    conf = conf or {}
    local value = conf[key]
    if value == nil or value == "" then
        local db = M.EnsureDB and M.EnsureDB()
        value = db and db.general and db.general.barTexture or "Solid"
    end
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        local ok, texture = pcall(_G.MSUF_ResolveStatusbarTextureKey, value)
        if ok and texture then return texture end
    end
    if LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok and lsm and type(lsm.Fetch) == "function" then
            local okFetch, texture = pcall(lsm.Fetch, lsm, "statusbar", value, true)
            if okFetch and texture then return texture end
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function PreviewHealthColor(conf, index)
    conf = conf or {}
    local mode = conf.gfBarMode or conf.healthColorMode or "CLASS"
    if mode == "unified" or mode == "CUSTOM" then
        return conf.healthCustomR or conf.gfUnifiedR or 0.20,
            conf.healthCustomG or conf.gfUnifiedG or 0.72,
            conf.healthCustomB or conf.gfUnifiedB or 0.48
    end
    if mode == "GRADIENT" then
        local pct = 0.35 + ((index or 1) % 5) * 0.12
        return 1.0 - pct * 0.45, 0.18 + pct * 0.72, 0.10
    end
    local colors = {
        { 0.78, 0.31, 0.92 },
        { 0.96, 0.55, 0.73 },
        { 0.58, 0.82, 0.98 },
        { 1.00, 0.80, 0.10 },
        { 0.40, 0.85, 0.52 },
    }
    local c = colors[((index or 1) - 1) % #colors + 1]
    return c[1], c[2], c[3]
end

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local GF_PREVIEW_MIN_W = 380
local GF_PREVIEW_MIN_H = 130
local GF_PREVIEW_ROLE = "HEALER"

local GF_PREVIEW_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local GF_PREVIEW_NAMES = {
    "Thrall", "Jaina", "Sylvanas", "Anduin", "Tyrande", "Arthas",
    "Garrosh", "Yrel", "Vol'jin", "Chen", "Malfurion", "Illidan", "Alexstrasza",
}

local GF_PREVIEW_ANCHOR_FRAC = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local GF_AURA_MOCK_ICON_IDS = {
    buff = { 774, 17, 139, 33076, 33763, 81749 },
    debuff = { 589, 980, 172, 12294, 1943, 5782 },
    externals = { 6940, 102342, 1022, 116849 },
    private = { 206151, 234153, 265178, 320141 },
}

local gfMockSpellTextureCache = {}
local function GFMockSpellTexture(spellId)
    local cached = gfMockSpellTextureCache[spellId]
    if cached then return cached end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then gfMockSpellTextureCache[spellId] = tex; return tex end
    end
    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellId)
        if icon then gfMockSpellTextureCache[spellId] = icon; return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GFPreviewRound(value)
    return floor((tonumber(value) or 0) + 0.5)
end

local function GFPreviewScaleValue(value, scale, minValue)
    local v = GFPreviewRound((tonumber(value) or 0) * (tonumber(scale) or 1))
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

local function GFPreviewConfigToOffset(value, scale)
    return GFPreviewRound((tonumber(value) or 0) * (tonumber(scale) or 1))
end

local function GFPreviewOffsetToConfig(value, scale)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return GFPreviewRound((tonumber(value) or 0) / scale)
end

local function GFPreviewResolveAnchor(rx, ry)
    local best, bestD = "CENTER", 1e9
    for point, frac in pairs(GF_PREVIEW_ANCHOR_FRAC) do
        local dx = rx - frac[1]
        local dy = ry - (1 - frac[2])
        local d = dx * dx + dy * dy
        if d < bestD then
            best, bestD = point, d
        end
    end
    return best
end

local function GFPreviewHandleOffset(handle, anchorFrame, anchor)
    local frac = GF_PREVIEW_ANCHOR_FRAC[anchor]
    if not (handle and anchorFrame and frac) then return 0, 0 end
    local hL, hB, hW, hH = handle:GetLeft() or 0, handle:GetBottom() or 0, handle:GetWidth() or 1, handle:GetHeight() or 1
    local aL, aB, aW, aH = anchorFrame:GetLeft() or 0, anchorFrame:GetBottom() or 0, anchorFrame:GetWidth() or 1, anchorFrame:GetHeight() or 1
    local hx = hL + hW * frac[1]
    local hy = hB + hH * frac[2]
    local ax = aL + aW * frac[1]
    local ay = aB + aH * frac[2]
    return GFPreviewRound(hx - ax), GFPreviewRound(hy - ay)
end

local function GFPreviewMockPowerHeight(kind, conf, zoom, frameScale)
    local livePowerH
    local gf = ns and ns.GF
    if gf and gf.GetEffectivePowerHeight then
        livePowerH = gf.GetEffectivePowerHeight(kind, nil, GF_PREVIEW_ROLE, conf)
    end
    if livePowerH == nil then
        local raw = conf and (tonumber(conf.powerHeight) or 6) or 6
        if gf and gf.ShouldShowPowerBarForRole and not gf.ShouldShowPowerBarForRole(kind, GF_PREVIEW_ROLE, conf) then
            raw = 0
        end
        livePowerH = raw > 0 and GFPreviewScaleValue(raw, frameScale or 1, 0) or 0
    end
    livePowerH = tonumber(livePowerH) or 0
    if livePowerH <= 0 then return 0 end
    return GFPreviewRound(livePowerH * (tonumber(zoom) or 1))
end

local function CreateNativeGFPreview(parent, ctx, onOpen)
    local width = (ctx.width or 720) - 28
    local box = T.Panel(parent, nil, T.colors.panel2, T.colors.border)
    box:SetSize(width, 300)
    if parent and parent.GetFrameLevel and box.SetFrameLevel then
        box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2)
    end

    local title = T.Font(box, "GameFontNormal", "", T.colors.text)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    title:SetText("Group Frame Preview - " .. PreviewScopeLabel(CurrentScope()))
    box._title = title
    local hint = T.Font(box, "GameFontDisableSmall", "click layers to hide - drag custom handles - arrows nudge selected", T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local stage = T.Panel(box, nil, { 0, 0, 0, 1 }, T.colors.borderSoft)
    stage:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -34)
    stage:SetSize(width - 98, 218)
    box._stage = stage

    local bounds = CreateFrame("Frame", nil, stage, T.Template())
    bounds:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bounds:SetBackdropColor(0, 0, 0, 0)
    bounds:SetBackdropBorderColor(0.90, 0.05, 0.02, 0.95)
    box._bounds = bounds

    local layers = T.Panel(box, nil, T.colors.panel, T.colors.borderSoft)
    layers:SetPoint("TOPLEFT", stage, "TOPRIGHT", 8, 0)
    layers:SetSize(78, 218)
    box._layers = layers
    local layersTitle = T.Font(layers, "GameFontDisableSmall", "LAYERS", T.colors.dim)
    layersTitle:SetPoint("TOPLEFT", layers, "TOPLEFT", 10, -10)

    M.gfPreviewLayerVisible = M.gfPreviewLayerVisible or {
        buff = true,
        debuff = true,
        externals = true,
        blizzard = true,
        status = true,
        si = true,
        private = true,
        auraText = true,
        text = true,
    }
    local layerDefs = {
        { "Buffs", { 0.20, 0.90, 0.35 }, "buffs", "buff" },
        { "Debuffs", { 0.90, 0.20, 0.22 }, "debuffs", "debuff" },
        { "Extern", { 0.20, 0.72, 0.95 }, "ext", "externals" },
        { "Blizzard", { 0.30, 0.55, 1.00 }, "blizzrenderer", "blizzard" },
        { "Status", { 0.95, 0.78, 0.22 }, "sicons", "status" },
        { "Spells", { 0.86, 0.50, 1.00 }, "si", "si" },
        { "Private", { 0.72, 0.72, 0.78 }, "priv", "private" },
        { "CD/Stack", { 1.00, 0.82, 0.28 }, "textcolor", "auraText" },
        { "Text", { 0.70, 0.90, 1.00 }, "text", "text" },
    }
    box._layerButtons = {}
    for i = 1, #layerDefs do
        local def = layerDefs[i]
        local btn = MakePreviewSectionButton(layers, def[1], def[2], def[3], onOpen)
        btn._layerKey = def[4]
        btn:SetPoint("TOPLEFT", layers, "TOPLEFT", 8, -28 - ((i - 1) * 18))
        btn:SetScript("OnClick", function(self)
            local key = self._layerKey
            if key then
                if IsShiftKeyDown and IsShiftKeyDown() then
                    M.gfPreviewSoloLayer = (M.gfPreviewSoloLayer == key) and nil or key
                else
                    M.gfPreviewSoloLayer = nil
                    M.gfPreviewLayerVisible[key] = M.gfPreviewLayerVisible[key] == false
                    if type(onOpen) == "function" then onOpen(self._sectionKey) end
                end
            elseif type(onOpen) == "function" then
                onOpen(self._sectionKey)
            end
            if box.Refresh then box:Refresh() end
        end)
        box._layerButtons[#box._layerButtons + 1] = btn
    end

    local mock = CreateFrame("Frame", nil, stage, T.Template())
    mock:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    mock:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
    mock:SetBackdropBorderColor(0.0, 0.0, 0.0, 1)
    mock:EnableMouse(true)
    mock:SetScript("OnMouseDown", function()
        if type(onOpen) == "function" then onOpen("general") end
    end)
    box._mock = mock

    mock._health = CreateFrame("StatusBar", nil, mock)
    mock._health:SetMinMaxValues(0, 1)
    mock._health:SetValue(0.72)
    mock._healthBg = mock._health:CreateTexture(nil, "BACKGROUND")
    mock._healthBg:SetAllPoints()

    mock._healPred = CreateFrame("StatusBar", nil, mock)
    mock._healPred:SetMinMaxValues(0, 1)
    mock._healPred:SetValue(0.12)
    mock._healPred:SetStatusBarTexture(WHITE8X8)
    mock._healPred:SetStatusBarColor(0, 1, 0.4, 0.45)

    mock._absorb = CreateFrame("StatusBar", nil, mock)
    mock._absorb:SetMinMaxValues(0, 1)
    mock._absorb:SetValue(1)
    mock._absorb:SetStatusBarTexture(WHITE8X8)
    mock._absorb:SetStatusBarColor(0.55, 0.70, 1, 0.55)

    mock._power = CreateFrame("StatusBar", nil, mock)
    mock._power:SetMinMaxValues(0, 1)
    mock._power:SetValue(1)
    mock._power:SetStatusBarColor(0.13, 0.27, 0.67, 1)
    mock._powerBg = mock._power:CreateTexture(nil, "BACKGROUND")
    mock._powerBg:SetAllPoints()

    mock._nameFS = T.Font(mock, "GameFontHighlightSmall", "", T.colors.text)
    mock._hpFS = T.Font(mock, "GameFontHighlight", "", T.colors.text)
    mock._powerFS = T.Font(mock, "GameFontHighlightSmall", "", T.colors.text)

    box._selectedHandle = nil
    box._handles = {}

    local function SelectHandle(handle)
        if box._selectedHandle and box._selectedHandle._selectTex then
            box._selectedHandle._selectTex:Hide()
        end
        box._selectedHandle = handle
        if handle and handle._selectTex then handle._selectTex:Show() end
        if box.SetFocus then box:SetFocus() end
    end

    local function SaveHandlePosition(handle)
        if not (handle and box._mock) or handle._locked then return end
        local m = box._mock
        local mL, mT = m:GetLeft() or 0, m:GetTop() or 0
        local mW, mH = max(1, m:GetWidth() or 1), max(1, m:GetHeight() or 1)
        local hL, hT = handle:GetLeft() or 0, handle:GetTop() or 0
        local hW, hH = handle:GetWidth() or 1, handle:GetHeight() or 1
        local cx, cy = hL + hW * 0.5, hT - hH * 0.5
        local anchor = GFPreviewResolveAnchor((cx - mL) / mW, (mT - cy) / mH)
        local offX, offY = GFPreviewHandleOffset(handle, m, anchor)
        local scale = handle._previewScale or m._previewScale or 1
        local cfgX, cfgY = GFPreviewOffsetToConfig(offX, scale), GFPreviewOffsetToConfig(offY, scale)
        local conf = Conf(CurrentScope())

        if handle._cfgGroup then
            conf.auras = conf.auras or {}
            conf.auras[handle._cfgGroup] = conf.auras[handle._cfgGroup] or {}
            conf.auras[handle._cfgGroup].anchor = anchor
            conf.auras[handle._cfgGroup].x = cfgX
            conf.auras[handle._cfgGroup].y = cfgY
        elseif handle._cfgStatus then
            conf.statusTextAnchor = anchor
            conf.statusOffsetX = cfgX
            conf.statusOffsetY = cfgY
        elseif handle._cfgPrivate then
            conf.privateAuras = conf.privateAuras or {}
            conf.privateAuras.anchor = anchor
            conf.privateAuras.x = cfgX
            conf.privateAuras.y = cfgY
        elseif handle._cfgSpell then
            conf.spellIndicators = conf.spellIndicators or {}
            local placed = conf.spellIndicators.placed or conf.spellIndicators
            placed.anchor = anchor
            placed.x = cfgX
            placed.y = cfgY
            conf.spellIndicators.placed = placed
        elseif handle._cfgText then
            if anchor == "RIGHT" or anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" then
                conf.nameAnchor = "RIGHT"
            elseif anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then
                conf.nameAnchor = "CENTER"
            else
                conf.nameAnchor = "LEFT"
            end
            conf.nameOffsetX = cfgX
            conf.nameOffsetY = cfgY
        end

        local gf = ns and ns.GF
        if gf and gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_ALL or 0x3F)
        elseif gf and gf.RefreshVisuals then
            gf.RefreshVisuals()
        end
        box:Refresh()
    end

    local function CreatePreviewHandle(key, sectionKey, color, label, width, height, locked)
        local handle = CreateFrame("Button", nil, mock, T.Template())
        handle:SetSize(width or 32, height or 32)
        handle:SetMovable(true)
        handle:EnableMouse(true)
        if handle.RegisterForDrag then handle:RegisterForDrag("LeftButton") end
        handle:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        handle:SetBackdropColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.42)
        handle:SetBackdropBorderColor(color[1], color[2], color[3], locked and 0.55 or 0.95)
        handle._key = key
        handle._sectionKey = sectionKey
        handle._locked = locked and true or false
        handle._color = color

        local selectTex = handle:CreateTexture(nil, "OVERLAY", nil, 7)
        selectTex:SetAllPoints()
        selectTex:SetColorTexture(1, 0.82, 0, 0.18)
        selectTex:Hide()
        handle._selectTex = selectTex

        local fs = T.Font(handle, "GameFontDisableSmall", label or key, { color[1], color[2], color[3], 0.95 })
        fs:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        fs:SetJustifyH("CENTER")
        handle._label = fs

        handle:SetScript("OnClick", function(self)
            SelectHandle(self)
            if type(onOpen) == "function" then onOpen(self._sectionKey) end
        end)
        handle:SetScript("OnDragStart", function(self)
            SelectHandle(self)
            if self._locked then return end
            if self.StartMoving then self:StartMoving() end
        end)
        handle:SetScript("OnDragStop", function(self)
            if self.StopMovingOrSizing then self:StopMovingOrSizing() end
            SaveHandlePosition(self)
        end)
        box._handles[key] = handle
        return handle
    end

    local function AddIconPool(handle, count)
        handle._icons = handle._icons or {}
        for i = 1, count do
            local tex = handle._icons[i] or handle:CreateTexture(nil, "ARTWORK")
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            handle._icons[i] = tex
        end
    end

    local buffHandle = CreatePreviewHandle("buff", "buffs", { 0.36, 0.79, 0.36 }, "BUFFS", 86, 34, false)
    buffHandle._cfgGroup = "buff"
    AddIconPool(buffHandle, 6)

    local debuffHandle = CreatePreviewHandle("debuff", "debuffs", { 0.89, 0.29, 0.29 }, "DEBUFFS", 86, 34, false)
    debuffHandle._cfgGroup = "debuff"
    AddIconPool(debuffHandle, 6)

    local externHandle = CreatePreviewHandle("externals", "ext", { 0.20, 0.67, 0.53 }, "DEF", 42, 42, false)
    externHandle._cfgGroup = "externals"
    AddIconPool(externHandle, 2)

    local blizzHandle = CreatePreviewHandle("blizzard", "blizzrenderer", { 0.36, 0.62, 0.95 }, "Blizzard locked", 140, 76, true)
    AddIconPool(blizzHandle, 10)

    local statusHandle = CreatePreviewHandle("status", "sicons", { 0.80, 0.67, 0.20 }, "", 78, 28, false)
    statusHandle._cfgStatus = true
    statusHandle._statusText = T.Font(statusHandle, "GameFontHighlightLarge", "DEAD", { 1, 1, 1, 1 })
    statusHandle._statusText:SetPoint("CENTER")

    local spellHandle = CreatePreviewHandle("si", "si", { 0.69, 0.50, 0.88 }, "SPELL", 44, 44, false)
    spellHandle._cfgSpell = true
    AddIconPool(spellHandle, 1)

    local privateHandle = CreatePreviewHandle("private", "priv", { 0.50, 0.50, 0.55 }, "PRIVATE", 48, 24, false)
    privateHandle._cfgPrivate = true
    AddIconPool(privateHandle, 3)

    local textHandle = CreatePreviewHandle("text", "text", { 0.55, 0.78, 0.95 }, "TEXT", 74, 18, false)
    textHandle._cfgText = true

    local footer = T.Font(box, "GameFontDisableSmall", "Click a handle to select - drag custom layers - arrow keys nudge selected; Blizzard is locked", T.colors.muted)
    footer:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)

    function box:Refresh()
        local kind = CurrentScope()
        local label = PreviewScopeLabel(kind)
        local conf = Conf(kind)
        local gf = ns and ns.GF
        local focus = PreviewFocusForPage(ctx.key)
        local layerVisible = M.gfPreviewLayerVisible or {}
        local soloLayer = M.gfPreviewSoloLayer
        local function LayerOn(key)
            return layerVisible[key] ~= false
        end
        local function LayerAlpha(key)
            return (soloLayer and soloLayer ~= key) and 0.15 or 1
        end
        self._title:SetText("Group Frame Preview - " .. label)

        local stageW = self._stage:GetWidth() or (width - 98)
        local stageH = self._stage:GetHeight() or 218
        if stageW <= 1 then stageW = math.max(260, width - 98) end
        if stageH <= 1 then stageH = 218 end

        local liveW, liveH, frameScale = tonumber(conf.width) or 120, tonumber(conf.height) or 40, 1
        if gf and gf.GetScaledFrameMetrics then
            local w2, h2, _, sc2 = gf.GetScaledFrameMetrics(kind)
            liveW, liveH, frameScale = tonumber(w2) or liveW, tonumber(h2) or liveH, tonumber(sc2) or 1
        end
        liveW, liveH = max(1, liveW), max(1, liveH)
        local zoom = min(GF_PREVIEW_MIN_W / liveW, GF_PREVIEW_MIN_H / liveH)
        zoom = max(1.4, min(2.8, zoom))
        local previewScale = zoom * (frameScale or 1)
        local mockW = max(48, GFPreviewRound(liveW * zoom))
        local mockH = max(20, GFPreviewRound(liveH * zoom))
        local powerH = GFPreviewMockPowerHeight(kind, conf, zoom, frameScale)
        local outline = 1
        if gf and gf.GetBarOutlineThickness then outline = tonumber(gf.GetBarOutlineThickness(kind)) or outline end
        local inset = max(0, GFPreviewRound(outline * previewScale))
        local startX = GFPreviewRound((stageW - mockW) * 0.5)
        local startY = -GFPreviewRound((stageH - mockH) * 0.5)
        local mock = self._mock
        mock._previewScale = previewScale
        mock:ClearAllPoints()
        mock:SetPoint("TOPLEFT", self._stage, "TOPLEFT", startX, startY)
        mock:SetSize(mockW, mockH)
        mock:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = max(1, inset),
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
        mock:SetBackdropColor(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09, conf.bgA or 0.88)
        mock:SetBackdropBorderColor(conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1)

        local barTex = (gf and gf.ResolveBarTexture and gf.ResolveBarTexture(kind)) or ResolvePreviewStatusbarTexture(conf, "barTexture")
        local bgTex = (gf and gf.ResolveBarBgTexture and gf.ResolveBarBgTexture(kind)) or WHITE8X8
        mock._health:SetStatusBarTexture(barTex)
        mock._health:ClearAllPoints()
        mock._health:SetPoint("TOPLEFT", mock, "TOPLEFT", inset, -inset)
        mock._health:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inset, powerH > 0 and (powerH + inset) or inset)
        local hr, hg, hb = PreviewHealthColor(conf, 3)
        if gf and gf.ResolveNameColor then
            local cls = GF_PREVIEW_CLASSES[((kind == "party" and 5 or 2) % #GF_PREVIEW_CLASSES) + 1]
            local rr, rg, rb = gf.ResolveNameColor(kind, cls)
            hr, hg, hb = rr or hr, rg or hg, rb or hb
        end
        mock._health:SetStatusBarColor(hr, hg, hb, tonumber(conf.hpBarAlpha) or 1)
        mock._healthBg:SetTexture(bgTex)
        mock._healthBg:SetVertexColor(conf.bgR or 0.06, conf.bgG or 0.06, conf.bgB or 0.07, conf.hpBgAlpha or conf.bgA or 0.85)

        mock._healPred:ClearAllPoints()
        mock._healPred:SetPoint("TOPLEFT", mock._health, "TOPRIGHT", -1, 0)
        mock._healPred:SetPoint("BOTTOM", mock._health, "BOTTOM", 0, 0)
        mock._healPred:SetWidth(max(1, mockW * 0.12))
        mock._healPred:SetShown(conf.healPrediction ~= false)

        mock._absorb:ClearAllPoints()
        mock._absorb:SetPoint("TOPRIGHT", mock._health, "TOPRIGHT", 0, 0)
        mock._absorb:SetPoint("BOTTOM", mock._health, "BOTTOM", 0, 0)
        mock._absorb:SetWidth(max(1, mockW * 0.08))

        if powerH > 0 then
            mock._power:SetStatusBarTexture(barTex)
            mock._power:ClearAllPoints()
            mock._power:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", inset, inset)
            mock._power:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inset, inset)
            mock._power:SetHeight(powerH)
            mock._powerBg:SetTexture(bgTex)
            mock._powerBg:SetVertexColor(conf.bgR or 0.06, conf.bgG or 0.06, conf.bgB or 0.07, conf.bgA or 0.85)
            mock._power:Show()
        else
            mock._power:Hide()
        end

        local showText = LayerOn("text") and (focus == "text" or focus == "overlay" or soloLayer == "text")
        local fontPath = (gf and gf.ResolveFontPath and gf.ResolveFontPath(kind)) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        local fontFlags = (gf and gf.ResolveFontFlags and gf.ResolveFontFlags(kind)) or "OUTLINE"
        local fr, fg, fb = T.colors.text[1], T.colors.text[2], T.colors.text[3]
        if gf and gf.ResolveFontColor then fr, fg, fb = gf.ResolveFontColor(kind) end
        mock._nameFS:SetFont(fontPath, max(6, GFPreviewScaleValue(conf.nameFontSize or 12, previewScale, 6)), fontFlags)
        mock._nameFS:SetText(GF_PREVIEW_NAMES[5])
        mock._nameFS:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
        mock._nameFS:ClearAllPoints()
        mock._nameFS:SetPoint("LEFT", mock._health, "LEFT", GFPreviewScaleValue(3, previewScale, 1), GFPreviewConfigToOffset(conf.nameOffsetY or 0, previewScale))
        mock._nameFS:SetPoint("RIGHT", mock._health, "RIGHT", -GFPreviewScaleValue(3, previewScale, 1), GFPreviewConfigToOffset(conf.nameOffsetY or 0, previewScale))
        mock._nameFS:SetJustifyH(conf.nameAnchor == "RIGHT" and "RIGHT" or (conf.nameAnchor == "CENTER" and "CENTER" or "LEFT"))
        mock._nameFS:SetShown(showText and conf.showName ~= false)

        mock._hpFS:SetFont(fontPath, max(7, GFPreviewScaleValue(conf.hpFontSize or 10, previewScale, 6)), fontFlags)
        mock._hpFS:SetText("72%")
        mock._hpFS:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
        mock._hpFS:ClearAllPoints()
        mock._hpFS:SetPoint("RIGHT", mock._health, "RIGHT", -GFPreviewScaleValue(3, previewScale, 1), GFPreviewConfigToOffset(conf.hpOffsetY or 0, previewScale))
        mock._hpFS:SetShown(showText)

        mock._powerFS:SetFont(fontPath, max(6, GFPreviewScaleValue(conf.powerFontSize or 9, previewScale, 6)), fontFlags)
        mock._powerFS:SetText("70")
        mock._powerFS:SetTextColor(fr or 1, fg or 1, fb or 1, 0.9)
        mock._powerFS:ClearAllPoints()
        mock._powerFS:SetPoint("CENTER", powerH > 0 and mock._power or mock._health, "CENTER", 0, 0)
        mock._powerFS:SetShown(showText and powerH > 0)

        self._bounds:ClearAllPoints()
        self._bounds:SetPoint("TOPLEFT", mock, "TOPLEFT", -2, 2)
        self._bounds:SetSize(mockW + 4, mockH + 4)

        local function LayoutHandle(handle, anchor, x, y, defaultAnchor)
            anchor = anchor or defaultAnchor or "CENTER"
            if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaultAnchor or "CENTER" end
            handle._previewScale = previewScale
            handle:ClearAllPoints()
            handle:SetPoint(anchor, mock, anchor, GFPreviewConfigToOffset(x or 0, previewScale), GFPreviewConfigToOffset(y or 0, previewScale))
        end

        local function LayoutIconRow(handle, groupKey, count, size, cols)
            local ids = GF_AURA_MOCK_ICON_IDS[groupKey] or GF_AURA_MOCK_ICON_IDS.debuff
            handle._icons = handle._icons or {}
            cols = max(1, cols or count)
            for i = 1, count do
                local tex = handle._icons[i]
                if tex then
                    tex:SetTexture(GFMockSpellTexture(ids[((i - 1) % #ids) + 1]))
                    tex:SetSize(size, size)
                    tex:ClearAllPoints()
                    local col, row = (i - 1) % cols, floor((i - 1) / cols)
                    tex:SetPoint("TOPLEFT", handle, "TOPLEFT", col * size, -row * size)
                    tex:Show()
                end
            end
            for i = count + 1, #(handle._icons or {}) do
                if handle._icons[i] then handle._icons[i]:Hide() end
            end
        end

        local function LayoutBlizzardAuraBlock(handle, size)
            handle._icons = handle._icons or {}
            handle._tags = handle._tags or {}
            local cols = 5
            for i = 1, 10 do
                local tex = handle._icons[i]
                if tex then
                    local groupKey = i <= 5 and "buff" or "debuff"
                    local ids = GF_AURA_MOCK_ICON_IDS[groupKey]
                    tex:SetTexture(GFMockSpellTexture(ids[((i - 1) % #ids) + 1]))
                    tex:SetSize(size, size)
                    tex:ClearAllPoints()
                    local col, row = (i - 1) % cols, floor((i - 1) / cols)
                    tex:SetPoint("TOPLEFT", handle, "TOPLEFT", col * size, -row * size)
                    tex:Show()

                    local tag = handle._tags[i]
                    if not tag then
                        tag = handle:CreateFontString(nil, "OVERLAY")
                        tag:SetFont("Fonts\\FRIZQT__.TTF", 6, "OUTLINE")
                        handle._tags[i] = tag
                    end
                    if col == 0 then
                        tag:SetText(groupKey == "buff" and "BUFFS" or "DEBUFFS")
                        if groupKey == "buff" then
                            tag:SetTextColor(0.55, 1.00, 0.55, 1)
                        else
                            tag:SetTextColor(1.00, 0.45, 0.45, 1)
                        end
                        tag:ClearAllPoints()
                        tag:SetPoint("TOPLEFT", tex, "TOPLEFT", 1, -1)
                        tag:Show()
                    else
                        tag:Hide()
                    end
                end
            end
        end

        local auras = conf.auras or {}
        local buffCfg = auras.buff or {}
        local debuffCfg = auras.debuff or {}
        local extCfg = auras.externals or {}
        local auraSize = max(10, GFPreviewScaleValue(buffCfg.size or 16, previewScale, 8))
        local debuffSize = max(10, GFPreviewScaleValue(debuffCfg.size or 16, previewScale, 8))
        local extSize = max(14, GFPreviewScaleValue(extCfg.size or 22, previewScale, 10))

        buffHandle:SetSize(auraSize * 3, auraSize * 2)
        LayoutIconRow(buffHandle, "buff", 6, auraSize, 3)
        LayoutHandle(buffHandle, buffCfg.anchor, buffCfg.x, buffCfg.y, "BOTTOMLEFT")

        debuffHandle:SetSize(debuffSize * 3, debuffSize * 2)
        LayoutIconRow(debuffHandle, "debuff", 6, debuffSize, 3)
        LayoutHandle(debuffHandle, debuffCfg.anchor, debuffCfg.x, debuffCfg.y, "TOPRIGHT")

        externHandle:SetSize(extSize * 2, extSize)
        LayoutIconRow(externHandle, "externals", 2, extSize, 2)
        LayoutHandle(externHandle, extCfg.anchor, extCfg.x, extCfg.y, "CENTER")

        local blizzSize = max(14, GFPreviewScaleValue(20, previewScale, 8))
        blizzHandle:SetSize(blizzSize * 5, blizzSize * 2)
        LayoutBlizzardAuraBlock(blizzHandle, blizzSize)
        LayoutHandle(blizzHandle, "CENTER", 0, 0, "CENTER")

        statusHandle:SetSize(max(42, GFPreviewScaleValue(conf.statusTextSize or 14, previewScale, 12) * 4), max(18, GFPreviewScaleValue(conf.statusTextSize or 14, previewScale, 12) + 8))
        if statusHandle._statusText and statusHandle._statusText.SetFont then
            statusHandle._statusText:SetFont(fontPath, max(12, GFPreviewScaleValue(conf.statusTextSize or 14, previewScale, 10)), fontFlags)
        end
        LayoutHandle(statusHandle, conf.statusTextAnchor, conf.statusOffsetX, conf.statusOffsetY, "CENTER")

        local spellSize = max(14, GFPreviewScaleValue(20, previewScale, 10))
        spellHandle:SetSize(spellSize, spellSize)
        LayoutIconRow(spellHandle, "buff", 1, spellSize, 1)
        local placed = conf.spellIndicators and (conf.spellIndicators.placed or conf.spellIndicators) or {}
        LayoutHandle(spellHandle, placed.anchor, placed.x, placed.y, "TOPLEFT")

        local privateSize = max(12, GFPreviewScaleValue((conf.privateAuras and conf.privateAuras.size) or 16, previewScale, 8))
        privateHandle:SetSize(privateSize * 3, privateSize)
        LayoutIconRow(privateHandle, "private", 3, privateSize, 3)
        local pa = conf.privateAuras or {}
        LayoutHandle(privateHandle, pa.anchor, pa.x, pa.y, "TOPRIGHT")

        textHandle:SetSize(max(54, mockW * 0.35), max(14, GFPreviewScaleValue(conf.nameFontSize or 12, previewScale, 8)))
        LayoutHandle(textHandle, conf.nameAnchor or "LEFT", conf.nameOffsetX or 0, conf.nameOffsetY or 0, "LEFT")

        local baseLevel = mock.GetFrameLevel and mock:GetFrameLevel() or 1
        buffHandle:SetFrameLevel(baseLevel + 5)
        debuffHandle:SetFrameLevel(baseLevel + 5)
        externHandle:SetFrameLevel(baseLevel + 5)
        blizzHandle:SetFrameLevel(baseLevel + 4)
        statusHandle:SetFrameLevel(baseLevel + (tonumber(conf.statusTextLayer) or 7))
        spellHandle:SetFrameLevel(baseLevel + 6)
        privateHandle:SetFrameLevel(baseLevel + 6)
        textHandle:SetFrameLevel(baseLevel + (tonumber(conf.nameTextLayer) or 6))

        local aurasEnabled = auras.enabled ~= false
        local customRenderer = (auras.renderer or conf.auraRenderer or "BLIZZARD") == "CUSTOM"
        buffHandle:SetShown(aurasEnabled and customRenderer and LayerOn("buff"))
        debuffHandle:SetShown(aurasEnabled and customRenderer and LayerOn("debuff"))
        externHandle:SetShown(aurasEnabled and customRenderer and LayerOn("externals"))
        blizzHandle:SetShown(aurasEnabled and not customRenderer and LayerOn("blizzard"))
        statusHandle:SetShown(conf.statusText ~= false and LayerOn("status"))
        spellHandle:SetShown((focus == "si" or (conf.spellIndicators and conf.spellIndicators.enabled ~= false)) and LayerOn("si"))
        privateHandle:SetShown(pa.enabled ~= false and LayerOn("private"))
        textHandle:SetShown(showText)

        buffHandle:SetAlpha(LayerAlpha("buff"))
        debuffHandle:SetAlpha(LayerAlpha("debuff"))
        externHandle:SetAlpha(LayerAlpha("externals"))
        blizzHandle:SetAlpha(LayerAlpha("blizzard"))
        statusHandle:SetAlpha(LayerAlpha("status"))
        spellHandle:SetAlpha(LayerAlpha("si"))
        privateHandle:SetAlpha(LayerAlpha("private"))
        textHandle:SetAlpha(LayerAlpha("text"))

        for i = 1, #self._layerButtons do
            local btn = self._layerButtons[i]
            btn:SetPreviewActive(btn._sectionKey == focus, LayerOn(btn._layerKey), soloLayer == btn._layerKey)
        end
        if self._selectedHandle and self._selectedHandle.IsShown and not self._selectedHandle:IsShown() then
            SelectHandle(nil)
        end
    end

    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", function(self, key)
        local handle = self._selectedHandle
        if not handle or handle._locked then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        local focusFrame = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focusFrame then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
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
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        local point, relativeTo, relativePoint, xOfs, yOfs = handle:GetPoint(1)
        if not point then return end
        handle:ClearAllPoints()
        handle:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + dx, (yOfs or 0) + dy)
        SaveHandlePosition(handle)
    end)

    box:Refresh()
    box:HookScript("OnShow", function(self)
        self:Refresh()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self and self:IsShown() then self:Refresh() end
            end)
        end
    end)
    box:HookScript("OnSizeChanged", function(self)
        if self:IsShown() then self:Refresh() end
    end)
    return box
end

M._gfNativePreviews = M._gfNativePreviews or {}
function M.RefreshGFNativePreviews()
    for i = 1, #M._gfNativePreviews do
        local box = M._gfNativePreviews[i]
        if box and box.Refresh and box:IsShown() then pcall(box.Refresh, box) end
    end
end

local function AddGFPreview(ctx, builder)
    local body = builder:CollapsibleSection("gf_preview_native", "Hide Preview", 326, true)
    local box = CreateNativeGFPreview(body, ctx, OpenGFSection)
    box:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -12)
    box:Show()
    local function RefreshThisPreview()
        if box and box.Refresh and box:IsShown() then box:Refresh() end
    end
    RefreshThisPreview()
    if body.HookScript then
        body:HookScript("OnShow", RefreshThisPreview)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshThisPreview)
    end
    M._gfNativePreviews[#M._gfNativePreviews + 1] = box
    M.AddRefresher(ctx, RefreshThisPreview)
end

local function BindScopeToggle(ctx, widget, key, default, mode)
    M.BindToggle(ctx, widget,
        function() return Bool(CurrentScope(), key, default) end,
        function(v)
            Set(CurrentScope(), key, v and true or false, mode or "visual")
            if ctx and ctx.refreshers then
                for i = 1, #ctx.refreshers do
                    local fn = ctx.refreshers[i]
                    if type(fn) == "function" then pcall(fn) end
                end
            end
        end)
    return widget
end

local function BindScopeSlider(ctx, widget, key, default, mode)
    M.BindSlider(ctx, widget,
        function() return Num(CurrentScope(), key, default) end,
        function(v) Set(CurrentScope(), key, floor((tonumber(v) or default or 0) + 0.5), mode or "visual") end)
    return widget
end

local function BindScopeDropdown(ctx, widget, key, default, mode)
    M.BindDropdown(ctx, widget,
        function() return Val(CurrentScope(), key, default) end,
        function(v) Set(CurrentScope(), key, v or default, mode or "visual") end)
    return widget
end

local GROWTH_TILE_VALUES = {
    { value = "DOWN", text = "Down", dx = 0, dy = -1, arrow = "v" },
    { value = "UP", text = "Up", dx = 0, dy = 1, arrow = "^" },
    { value = "RIGHT", text = "Right", dx = 1, dy = 0, arrow = ">" },
    { value = "LEFT", text = "Left", dx = -1, dy = 0, arrow = "<" },
}

local function BuildGrowthDirectionTiles(ctx, section)
    if not section then return nil end

    local x = section._msuf2ContentX or 14
    local y = section._msuf2CursorY or -38
    local tileW, tileH, gap = 64, 64, 6
    section._msuf2CursorY = y - tileH - 40

    local label = T.Font(section, "GameFontNormalSmall", "Growth Direction", { 1.00, 0.82, 0.18, 1 })
    label:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)

    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 20)
    holder:SetSize((tileW * 4) + (gap * 3), tileH)

    local buttons = {}

    local function SetTileVisual(btn, active, hover)
        if not btn then return end
        if btn.SetBackdropColor then
            if active then
                btn:SetBackdropColor(0.100, 0.180, 0.300, hover and 0.98 or 0.92)
                btn:SetBackdropBorderColor(0.260, 0.620, 1.000, 1.00)
            elseif hover then
                btn:SetBackdropColor(0.115, 0.135, 0.185, 0.95)
                btn:SetBackdropBorderColor(0.380, 0.450, 0.620, 0.95)
            else
                btn:SetBackdropColor(0.045, 0.052, 0.076, 0.92)
                btn:SetBackdropBorderColor(0.190, 0.220, 0.310, 0.85)
            end
        end
        if btn._label then
            if active then
                btn._label:SetTextColor(0.95, 1.00, 1.00, 1)
            else
                btn._label:SetTextColor(0.74, 0.80, 0.90, 0.95)
            end
        end
    end

    local function DrawMiniPreview(btn, info, raidLike)
        if not btn or not info then return end
        btn._cells = btn._cells or {}
        local cols, rows
        if raidLike then
            if info.dy ~= 0 then
                cols, rows = 4, 5
            else
                cols, rows = 5, 4
            end
        elseif info.dy ~= 0 then
            cols, rows = 1, 5
        else
            cols, rows = 5, 1
        end

        local pad = 5
        local labelH = 13
        local innerW = tileW - (pad * 2)
        local innerH = tileH - pad - labelH
        local cellGap = 1
        local cellW = max(3, floor((innerW - ((cols - 1) * cellGap)) / cols))
        local cellH = max(3, floor((innerH - ((rows - 1) * cellGap)) / rows))
        local gridW = (cols * cellW) + ((cols - 1) * cellGap)
        local gridH = (rows * cellH) + ((rows - 1) * cellGap)
        local originX = pad + floor((innerW - gridW) * 0.5 + 0.5)
        local originY = -pad - floor((innerH - gridH) * 0.5 + 0.5)

        local positions = {}
        if info.dy ~= 0 then
            local rowStart, rowEnd, rowStep = 0, rows - 1, 1
            if info.dy == 1 then rowStart, rowEnd, rowStep = rows - 1, 0, -1 end
            for col = 0, cols - 1 do
                for row = rowStart, rowEnd, rowStep do
                    positions[#positions + 1] = { col = col, row = row }
                end
            end
        else
            local colStart, colEnd, colStep = 0, cols - 1, 1
            if info.dx == -1 then colStart, colEnd, colStep = cols - 1, 0, -1 end
            for row = 0, rows - 1 do
                for col = colStart, colEnd, colStep do
                    positions[#positions + 1] = { col = col, row = row }
                end
            end
        end

        for i = 1, #positions do
            local cell = btn._cells[i]
            if not cell then
                cell = btn:CreateTexture(nil, "ARTWORK")
                btn._cells[i] = cell
            end
            local pos = positions[i]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", btn, "TOPLEFT", originX + (pos.col * (cellW + cellGap)), originY - (pos.row * (cellH + cellGap)))
            cell:SetSize(cellW, cellH)
            if i == 1 then
                cell:SetColorTexture(0.120, 0.950, 0.620, 0.98)
            elseif i <= 4 then
                cell:SetColorTexture(0.220, 0.580, 0.940, 0.78)
            else
                cell:SetColorTexture(0.160, 0.360, 0.640, 0.42)
            end
            cell:Show()
        end
        for i = #positions + 1, #btn._cells do
            btn._cells[i]:Hide()
        end

        if not btn._firstText then
            btn._firstText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._firstText.SetFont then btn._firstText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE") end
            btn._firstText:SetText("1")
            btn._firstText:SetTextColor(0, 0, 0, 1)
        end
        local first = positions[1]
        if first then
            btn._firstText:ClearAllPoints()
            btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
                originX + (first.col * (cellW + cellGap)) + (cellW * 0.5),
                originY - (first.row * (cellH + cellGap)) - (cellH * 0.5))
            btn._firstText:Show()
        end

        if not btn._arrow then
            btn._arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._arrow.SetFont then btn._arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE") end
            btn._arrow:SetTextColor(1.00, 0.82, 0.18, 0.95)
        end
        btn._arrow:SetText(info.arrow)
        btn._arrow:ClearAllPoints()
        if info.dy == -1 then
            btn._arrow:SetPoint("BOTTOM", btn, "BOTTOM", 0, labelH + 1)
        elseif info.dy == 1 then
            btn._arrow:SetPoint("TOP", btn, "TOP", 0, -4)
        elseif info.dx == 1 then
            btn._arrow:SetPoint("RIGHT", btn, "RIGHT", -4, labelH * 0.5)
        else
            btn._arrow:SetPoint("LEFT", btn, "LEFT", 4, labelH * 0.5)
        end
        btn._arrow:Show()
    end

    local function RefreshGrowthTiles()
        local current = Val(CurrentScope(), "growth", "DOWN")
        local raidLike = CurrentScope() ~= "party"
        for i = 1, #GROWTH_TILE_VALUES do
            local info = GROWTH_TILE_VALUES[i]
            local btn = buttons[info.value]
            if btn then
                DrawMiniPreview(btn, info, raidLike)
                SetTileVisual(btn, current == info.value, btn.IsMouseOver and btn:IsMouseOver())
            end
        end
    end

    for i = 1, #GROWTH_TILE_VALUES do
        local info = GROWTH_TILE_VALUES[i]
        local btn = CreateFrame("Button", nil, holder, T.Template and T.Template() or nil)
        btn:SetSize(tileW, tileH)
        btn:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (tileW + gap), 0)
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
        end

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if text.SetFont then text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE") end
        text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 3)
        text:SetText(info.text)
        btn._label = text

        btn:SetScript("OnEnter", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, true)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Growth: " .. info.text, 1, 1, 1)
                GameTooltip:AddLine("Click to set group frame growth direction.", 0.72, 0.76, 0.86)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, false)
        end)
        btn:SetScript("OnClick", function()
            Set(CurrentScope(), "growth", info.value, "rebuild")
            RefreshGrowthTiles()
        end)
        buttons[info.value] = btn
    end

    RefreshGrowthTiles()
    M.AddRefresher(ctx, RefreshGrowthTiles)
    return holder
end

local ROLE_SORT_DEFS = {
    { key = "TANK", label = "Tank", r = 0.30, g = 0.55, b = 0.85 },
    { key = "HEALER", label = "Healer", r = 0.20, g = 0.72, b = 0.35 },
    { key = "DAMAGER", label = "DPS", r = 0.82, g = 0.30, b = 0.30 },
}

local ROLE_SORT_BY_KEY = {}
for i = 1, #ROLE_SORT_DEFS do
    ROLE_SORT_BY_KEY[ROLE_SORT_DEFS[i].key] = i
end

local function BuildRoleOrderRows(ctx, section)
    if not section then return nil end

    local rowW, rowH, rowGap = 200, 22, 4
    local x = section._msuf2ContentX or 14
    local y = section._msuf2CursorY or -146
    section._msuf2CursorY = y - (#ROLE_SORT_DEFS * (rowH + rowGap)) - 10

    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
    holder:SetSize(rowW, (#ROLE_SORT_DEFS * (rowH + rowGap)))

    local rows = {}
    local activeCount = #ROLE_SORT_DEFS

    local function SlotY(slot)
        return -((slot - 1) * (rowH + rowGap))
    end

    local function NormalizeRoleToken(token)
        if token == "MELEE" or token == "RANGED" then return "DAMAGER" end
        return token
    end

    local function SnapRows()
        for i = 1, #rows do
            local row = rows[i]
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, SlotY(row.slotIndex))
            row.frame._numText:SetText(tostring(row.slotIndex))
            row.frame:Show()
        end
    end

    local function SaveOrder()
        local ordered = {}
        for i = 1, #rows do ordered[#ordered + 1] = rows[i] end
        table.sort(ordered, function(a, b) return (a.slotIndex or 0) < (b.slotIndex or 0) end)
        local parts = {}
        for i = 1, #ordered do parts[#parts + 1] = ordered[i].key end
        local conf = Conf(CurrentScope())
        conf.roleOrder = table.concat(parts, ",")
        QueueGF(CurrentScope(), "rebuild")
    end

    local function LoadOrder()
        local conf = Conf(CurrentScope())
        local order = type(conf.roleOrder) == "string" and conf.roleOrder or "TANK,HEALER,DAMAGER"
        local slot = 0
        local assigned = {}
        for token in order:gmatch("[^,]+") do
            token = NormalizeRoleToken(token)
            local index = ROLE_SORT_BY_KEY[token]
            if index and not assigned[index] then
                slot = slot + 1
                rows[index].slotIndex = slot
                assigned[index] = true
            end
        end
        for i = 1, #rows do
            if not assigned[i] then
                slot = slot + 1
                rows[i].slotIndex = slot
            end
        end
        SnapRows()
    end

    local function SetRowEnabled(row, enabled)
        if not row then return end
        local frame = row.frame
        frame:SetAlpha(enabled and 1 or 0.42)
        frame:EnableMouse(enabled and true or false)
        if frame._label then
            local c = enabled and T.colors.text or T.colors.dim
            frame._label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
    end

    function holder:SetRowsEnabled(enabled)
        self._enabled = enabled and true or false
        for i = 1, #rows do
            SetRowEnabled(rows[i], self._enabled)
        end
    end

    for i = 1, #ROLE_SORT_DEFS do
        local def = ROLE_SORT_DEFS[i]
        local row = CreateFrame("Frame", nil, holder, T.Template and T.Template() or nil)
        row:SetSize(rowW, rowH)
        row:SetMovable(true)
        row:EnableMouse(true)
        row:RegisterForDrag("LeftButton")
        if row.SetBackdrop then
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            row:SetBackdropColor(0.055, 0.060, 0.075, 0.88)
            row:SetBackdropBorderColor(0.210, 0.230, 0.300, 0.78)
        end

        local stripe = row:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("LEFT", row, "LEFT", 2, 0)
        stripe:SetSize(4, rowH - 2)
        stripe:SetColorTexture(def.r, def.g, def.b, 1)

        local label = T.Font(row, "GameFontHighlightSmall", def.label, T.colors.text)
        label:SetPoint("LEFT", stripe, "RIGHT", 7, 0)
        label:SetJustifyH("LEFT")
        row._label = label

        local number = T.Font(row, "GameFontNormalSmall", tostring(i), T.colors.dim)
        number:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        number:SetJustifyH("RIGHT")
        row._numText = number

        row:SetScript("OnEnter", function(self)
            if not holder._enabled then return end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.380, 0.550, 0.900, 0.95) end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(def.label, 1, 1, 1)
                GameTooltip:AddLine("Drag to change role priority.", 0.72, 0.76, 0.86)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.210, 0.230, 0.300, 0.78) end
        end)
        row:SetScript("OnDragStart", function(self)
            if not holder._enabled then return end
            if GameTooltip then GameTooltip:Hide() end
            self._msuf2OldStrata = self.GetFrameStrata and self:GetFrameStrata() or nil
            if self.SetFrameStrata then self:SetFrameStrata("TOOLTIP") end
            self:StartMoving()
        end)
        row:SetScript("OnDragStop", function(self)
            if not holder._enabled then return end
            self:StopMovingOrSizing()
            if self.SetFrameStrata and self._msuf2OldStrata then self:SetFrameStrata(self._msuf2OldStrata) end

            local _, centerY = self:GetCenter()
            local top = holder:GetTop()
            local bestSlot, bestDist = 1, math.huge
            if centerY and top then
                for slotIndex = 1, activeCount do
                    local slotCenter = top + SlotY(slotIndex) - (rowH * 0.5)
                    local dist = math.abs(centerY - slotCenter)
                    if dist < bestDist then
                        bestDist = dist
                        bestSlot = slotIndex
                    end
                end
            end

            local moving
            for ri = 1, #rows do
                if rows[ri].frame == self then
                    moving = rows[ri]
                    break
                end
            end
            if moving and moving.slotIndex ~= bestSlot then
                for ri = 1, #rows do
                    if rows[ri] ~= moving and rows[ri].slotIndex == bestSlot then
                        rows[ri].slotIndex = moving.slotIndex
                        break
                    end
                end
                moving.slotIndex = bestSlot
                SaveOrder()
            end
            SnapRows()
        end)

        rows[i] = { frame = row, key = def.key, slotIndex = i }
    end

    holder.Refresh = LoadOrder
    M.AddRefresher(ctx, LoadOrder)
    LoadOrder()
    holder:SetRowsEnabled(false)
    return holder
end

local function AurasRoot(kind)
    local conf = Conf(kind)
    conf.auras = conf.auras or {}
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    conf.auras.externals = conf.auras.externals or {}
    return conf.auras
end

local function AuraGroup(kind, groupKey)
    local root = AurasRoot(kind)
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end

local function PrivateAuras(kind)
    local conf = Conf(kind)
    conf.privateAuras = conf.privateAuras or {}
    return conf.privateAuras
end

local function SpellIndicators(kind)
    local conf = Conf(kind)
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 }
    end
    conf.spellIndicators.specs = conf.spellIndicators.specs or {}
    return conf.spellIndicators
end

local function IconStyleValues()
    local gf = GF()
    if gf and type(gf.ICON_STYLE_ITEMS) == "table" then return gf.ICON_STYLE_ITEMS end
    return {
        { value = "BLIZZARD", text = "Blizzard (Default)" },
        { value = "GLOSSY_ORBS", text = "Glossy Orbs" },
        { value = "DARK_EMBOSS", text = "Dark Emboss" },
        { value = "GLASS_PANELS", text = "Glass Panels" },
        { value = "NEON_OUTLINE", text = "Neon Outline" },
        { value = "RING_SYMBOLS", text = "Ring Symbols" },
        { value = "DOTS", text = "Dots" },
        { value = "SHAPES", text = "Shapes" },
        { value = "DIAMONDS", text = "Diamonds" },
        { value = "SQUARES", text = "Squares" },
    }
end

local function CurrentGFStatusSpec()
    M.gfStatusIconSelection = M.gfStatusIconSelection or "roleIcon"
    for i = 1, #GF_STATUS_ICON_SPECS do
        local spec = GF_STATUS_ICON_SPECS[i]
        if spec.value == M.gfStatusIconSelection then return spec end
    end
    M.gfStatusIconSelection = GF_STATUS_ICON_SPECS[1].value
    return GF_STATUS_ICON_SPECS[1]
end

local function QueueSpellIndicators(kind)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.InvalidateRuntimeCaches) == "function" then si.InvalidateRuntimeCaches() end
    QueueGF(kind or CurrentScope(), "visual")
end

local function SpellSpecValues()
    local values = {
        { value = "auto", text = "Auto-Detect" },
        { value = "multi", text = "Multi-Spec" },
    }
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.SpecInfo) == "table" then
        for specKey, info in pairs(si.SpecInfo) do
            values[#values + 1] = { value = specKey, text = (info and info.display) or tostring(specKey) }
        end
    end
    return values
end

local function SpellTrackedSpecValues()
    local values = {}
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.SpecInfo) == "table" then
        for specKey, info in pairs(si.SpecInfo) do
            values[#values + 1] = { value = specKey, text = (info and info.display) or tostring(specKey) }
        end
        table.sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
    end
    if #values == 0 then values[1] = { value = "", text = "No supported specs" } end
    return values
end

local function CurrentSpellMultiSpec(kind)
    M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
    local selected = M.gfSpellMultiSpecSelection[kind]
    local values = SpellTrackedSpecValues()
    for i = 1, #values do
        if values[i].value == selected then return selected end
    end
    selected = values[1] and values[1].value or ""
    M.gfSpellMultiSpecSelection[kind] = selected
    return selected
end

local function EffectiveSpellSpec(kind)
    local cfg = SpellIndicators(kind)
    local selected = cfg.spec or "auto"
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if selected ~= "auto" and selected ~= "multi" and si and si.SpecInfo and si.SpecInfo[selected] then
        return selected
    end
    if selected == "multi" then
        local chosen = CurrentSpellMultiSpec(kind)
        if chosen and si and si.SpecInfo and si.SpecInfo[chosen] then return chosen end
        if type(cfg.multiSpecs) == "table" then
            for specKey, enabled in pairs(cfg.multiSpecs) do
                if enabled and si and si.SpecInfo and si.SpecInfo[specKey] then return specKey end
            end
        end
    end
    if si and type(si.GetPlayerSpec) == "function" then
        local ok, specKey = pcall(si.GetPlayerSpec)
        if ok and specKey and si.SpecInfo and si.SpecInfo[specKey] then return specKey end
    end
    if si and type(si.SpecInfo) == "table" then
        for specKey in pairs(si.SpecInfo) do return specKey end
    end
    return nil
end

local function SpellAuraValues(kind)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    local specKey = EffectiveSpellSpec(kind)
    local trackable = specKey and si and si.TrackableAuras and si.TrackableAuras[specKey]
    local values = {}
    if type(trackable) == "table" then
        for i = 1, #trackable do
            local info = trackable[i]
            local key = info and info.name
            if key then values[#values + 1] = { value = key, text = info.display or key } end
        end
    end
    if #values == 0 then values[1] = { value = "", text = "No spells for current spec" } end
    return values
end

local function CurrentSpellAura(kind)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    local selected = M.gfSpellIndicatorSelection[kind]
    local values = SpellAuraValues(kind)
    for i = 1, #values do
        if values[i].value == selected then return selected end
    end
    selected = values[1] and values[1].value or ""
    M.gfSpellIndicatorSelection[kind] = selected
    return selected
end

local function CurrentSpellConfig(kind, create)
    local specKey = EffectiveSpellSpec(kind)
    local auraName = CurrentSpellAura(kind)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local cfg = SpellIndicators(kind)
    cfg.specs[specKey] = cfg.specs[specKey] or {}
    if create and type(cfg.specs[specKey][auraName]) ~= "table" then
        cfg.specs[specKey][auraName] = { enabled = true, onlyOwn = true }
    end
    return cfg.specs[specKey][auraName], specKey, auraName
end

local function PlacedConfig(kind, create)
    local cfg = CurrentSpellConfig(kind, create)
    if not cfg then return nil end
    if create and type(cfg.placed) ~= "table" then cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18 } end
    return cfg.placed
end

local function FrameEffectConfig(kind, create)
    local cfg = CurrentSpellConfig(kind, create)
    if not cfg then return nil end
    if create and type(cfg.frame) ~= "table" then cfg.frame = { type = "none" } end
    return cfg.frame
end

local function CICategoryValues()
    local gf = GF()
    if gf and type(gf.CI_CATEGORIES) == "table" then return gf.CI_CATEGORIES end
    return {
        { value = "none", text = "None" },
        { value = "dispel", text = "Dispellable" },
        { value = "aggro", text = "Aggro/Threat" },
        { value = "custom", text = "Custom Spell" },
    }
end

local function CIFilterValues()
    local gf = GF()
    if gf and type(gf.CI_CUSTOM_FILTERS) == "table" then return gf.CI_CUSTOM_FILTERS end
    return {
        { value = "HELPFUL|PLAYER", text = "Buff (cast by me)" },
        { value = "HELPFUL", text = "Buff (any caster)" },
        { value = "HARMFUL|PLAYER", text = "Debuff (cast by me)" },
        { value = "HARMFUL", text = "Debuff (any caster)" },
    }
end

local function CIModeValues()
    local gf = GF()
    if gf and type(gf.CI_CUSTOM_MODES) == "table" then return gf.CI_CUSTOM_MODES end
    return {
        { value = "present", text = "Show when present" },
        { value = "missing", text = "Show when missing" },
    }
end

local function CurrentCISlot()
    M.gfCornerSlotSelection = M.gfCornerSlotSelection or "TL"
    for i = 1, #CI_SLOT_VALUES do
        if CI_SLOT_VALUES[i].value == M.gfCornerSlotSelection then return M.gfCornerSlotSelection end
    end
    M.gfCornerSlotSelection = "TL"
    return "TL"
end

local function CICustomConfig(kind, slot, create)
    local conf = Conf(kind)
    local key = "ciCustom" .. (slot or CurrentCISlot())
    if create and type(conf[key]) ~= "table" then
        conf[key] = { spells = "", mode = "present", filter = "HELPFUL|PLAYER", r = 0.40, g = 1.00, b = 0.40 }
    end
    return type(conf[key]) == "table" and conf[key] or nil
end

local function BindNestedToggle(ctx, widget, getTable, key, default, mode)
    M.BindToggle(ctx, widget,
        function()
            local tbl = getTable()
            local value = tbl[key]
            if value == nil then return default and true or false end
            return value and true or false
        end,
        function(v)
            local tbl = getTable()
            if tbl[key] == (v and true or false) then return end
            tbl[key] = v and true or false
            QueueGF(CurrentScope(), mode or "visual")
            if ctx and ctx.refreshers then
                for i = 1, #ctx.refreshers do
                    local fn = ctx.refreshers[i]
                    if type(fn) == "function" then pcall(fn) end
                end
            end
        end)
    return widget
end

local function BindNestedSlider(ctx, widget, getTable, key, default, mode)
    M.BindSlider(ctx, widget,
        function()
            local tbl = getTable()
            return tonumber(tbl[key]) or default or 0
        end,
        function(v)
            local tbl = getTable()
            v = floor((tonumber(v) or default or 0) + 0.5)
            if tbl[key] == v then return end
            tbl[key] = v
            QueueGF(CurrentScope(), mode or "visual")
        end)
    return widget
end

local function BindNestedDropdown(ctx, widget, getTable, key, default, mode)
    M.BindDropdown(ctx, widget,
        function()
            local tbl = getTable()
            return tbl[key] or default
        end,
        function(v)
            local tbl = getTable()
            tbl[key] = v or default
            QueueGF(CurrentScope(), mode or "visual")
        end)
    return widget
end

local function SetOptionEnabled(control, enabled)
    if not control then return end
    enabled = enabled and true or false
    if control.EnableMouse then control:EnableMouse(enabled) end
    if control.SetEnabled then control:SetEnabled(enabled) end
    if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
    if control._msuf2Title and control._msuf2Title.SetTextColor then
        local c = enabled and T.colors.text or T.colors.dim
        control._msuf2Title:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if control._msuf2Label and control._msuf2Label.SetTextColor then
        local c = enabled and T.colors.text or T.colors.dim
        control._msuf2Label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if control._msuf2LabelHit and control._msuf2LabelHit.EnableMouse then
        control._msuf2LabelHit:EnableMouse(enabled)
    end
    if control.editBox then
        if control.editBox.EnableMouse then control.editBox:EnableMouse(enabled) end
        if control.editBox.SetAlpha then control.editBox:SetAlpha(enabled and 1 or 0.45) end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            if btn.SetEnabled then btn:SetEnabled(enabled) end
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
end

local function SetOptionsEnabled(controls, enabled)
    for i = 1, #(controls or {}) do
        SetOptionEnabled(controls[i], enabled)
    end
end

local function BuildGFLayout(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    AddGFPreview(ctx, b)

    local general = b:CollapsibleSection("general", "General", 292, false)
    BindScopeToggle(ctx, W.Toggle(general, "Enable group frames"), "enabled", false, "rebuild")
    BindScopeToggle(ctx, W.Toggle(general, "Show player"), "showPlayer", true, "rebuild")
    BindScopeToggle(ctx, W.Toggle(general, "Show solo"), "showSolo", false, "rebuild")
    BindScopeToggle(ctx, W.Toggle(general, "Reverse fill direction"), "reverseFill", false, "visual")
    BindScopeToggle(ctx, W.Toggle(general, "Smooth health fill"), "smoothFill", true, "visual")
    BindScopeToggle(ctx, W.Toggle(general, "Hide in client scene"), "hideInClientScene", true, "visual")
    BindScopeSlider(ctx, W.Slider(general, "Hide offline after", 0, 120, 1, 300), "hideOfflineDelay", 0, "visual")

    local layout = b:CollapsibleSection("layout", "Layout", 450, false)
    BindScopeSlider(ctx, W.Slider(layout, "Width", 40, 300, 1, 300), "width", 120, "rebuild")
    BindScopeSlider(ctx, W.Slider(layout, "Height", 16, 120, 1, 300), "height", 40, "rebuild")
    BindScopeSlider(ctx, W.Slider(layout, "Spacing", 0, 20, 1, 300), "spacing", 1, "rebuild")
    BuildGrowthDirectionTiles(ctx, layout)
    BindScopeSlider(ctx, W.Slider(layout, "Units per column", 1, 40, 1, 300), "unitsPerColumn", 5, "rebuild")
    BindScopeSlider(ctx, W.Slider(layout, "Max columns", 1, 8, 1, 300), "maxColumns", 8, "rebuild")

    local sorting = b:CollapsibleSection("sorting", "Sorting", 300, false)
    local sortMode = W.Dropdown(sorting, "Sort Mode", SORT_MODES, 240)
    if sortMode._msuf2Title then
        sortMode._msuf2Title:ClearAllPoints()
        sortMode._msuf2Title:SetPoint("LEFT", sortMode, "RIGHT", 8, 0)
        sortMode._msuf2Title:SetJustifyH("LEFT")
        sortMode._msuf2Title:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
    end
    local refreshSortingControls
    M.BindDropdown(ctx, sortMode,
        function()
            local conf = Conf(CurrentScope())
            if conf.sortMode then return conf.sortMode end
            return conf.sortByRole and "ROLE" or "INDEX"
        end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.sortMode = v or "INDEX"
            conf.sortByRole = (conf.sortMode == "ROLE")
            QueueGF(CurrentScope(), "rebuild")
            if refreshSortingControls then refreshSortingControls() end
        end)
    local roleSort = W.Toggle(sorting, "Sort by Role")
    M.BindToggle(ctx, roleSort,
        function()
            local conf = Conf(CurrentScope())
            if conf.sortMode then return conf.sortMode == "ROLE" end
            return conf.sortByRole and true or false
        end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.sortByRole = v and true or false
            conf.sortMode = v and "ROLE" or "INDEX"
            QueueGF(CurrentScope(), "rebuild")
            if refreshSortingControls then refreshSortingControls() end
        end)
    local playerFirst = BindScopeToggle(ctx, W.Toggle(sorting, "Player first in role"), "playerFirstInRole", false, "rebuild")
    local roleRows = BuildRoleOrderRows(ctx, sorting)
    refreshSortingControls = function()
        local conf = Conf(CurrentScope())
        local currentMode = conf.sortMode or (conf.sortByRole and "ROLE" or "INDEX")
        local enabled = currentMode == "ROLE"
        if sortMode.SetValue then sortMode:SetValue(currentMode) end
        if roleSort.SetChecked then roleSort:SetChecked(enabled) end
        SetOptionEnabled(playerFirst, enabled)
        if roleRows then
            if roleRows.Refresh then roleRows.Refresh() end
            if roleRows.SetRowsEnabled then roleRows:SetRowsEnabled(enabled) end
        end
    end
    M.AddRefresher(ctx, refreshSortingControls)

    local scale = b:CollapsibleSection("scaling", "Frame Scaling", 380, false)
    local RefreshScalingState
    local scaleMode = W.Dropdown(scale, "Scale Mode", {
        { value = "off", text = "Off (100%)" },
        { value = "auto", text = "Auto (by group size)" },
        { value = "manual", text = "Manual" },
    }, 220)
    M.BindDropdown(ctx, scaleMode,
        function() return Val(CurrentScope(), "frameScaleMode", "off") end,
        function(v)
            Set(CurrentScope(), "frameScaleMode", v or "off", "rebuild")
            if RefreshScalingState then RefreshScalingState() end
        end)

    local function PlaceDropdown(control, x, y, width)
        if not control then return end
        width = width or 220
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", scale, "TOPLEFT", x, y)
        control:SetSize(width, 22)
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("LEFT", control, "RIGHT", 8, 0)
            control._msuf2Title:SetJustifyH("LEFT")
            control._msuf2Title:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
        end
    end

    local function PlaceScaleSlider(control, x, y, width)
        if not control then return end
        width = width or 220
        control._msuf2TitleJustify = "LEFT"
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", x, y)
            control._msuf2Title:SetJustifyH("LEFT")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", scale, "TOPLEFT", x, y - 22)
        if control._msuf2SetLayoutWidth then
            control:_msuf2SetLayoutWidth(width)
        else
            control:SetSize(width, 16)
            if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        end
    end

    local function BindScaleSlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                Set(CurrentScope(), key, floor((tonumber(v) or default or 0) + 0.5), "rebuild")
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(floor((tonumber(value) or default or 0) + 0.5)))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    PlaceDropdown(scaleMode, 14, -38, 220)
    local manualScale = BindScaleSlider(W.Slider(scale, "", 50, 150, 5, 220), "frameScaleManual", 100,
        function(v) return string.format("Manual Scale: %d%%", v) end)
    PlaceScaleSlider(manualScale, 14, -78, 220)

    local autoLabel = T.Font(scale, "GameFontNormalSmall", "Auto Breakpoints", { 1.00, 0.82, 0.18, 1 })
    autoLabel:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -130)

    local scaleAt10 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, 220), "scaleAt10", 100,
        function(v) return string.format("1-10 players: %d%%", v) end)
    PlaceScaleSlider(scaleAt10, 14, -158, 220)
    local scaleAt20 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, 220), "scaleAt20", 85,
        function(v) return string.format("11-20 players: %d%%", v) end)
    PlaceScaleSlider(scaleAt20, 14, -208, 220)
    local scaleAt25 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, 220), "scaleAt25", 80,
        function(v) return string.format("21-25 players: %d%%", v) end)
    PlaceScaleSlider(scaleAt25, 14, -258, 220)
    local scaleOver25 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, 220), "scaleOver25", 70,
        function(v) return string.format("26+ players: %d%%", v) end)
    PlaceScaleSlider(scaleOver25, 14, -308, 220)

    local scaleHint = W.Text(scale, "Scales frame size, fonts, and icons proportionally.\nBuff/debuff positions stay relative to their anchors.", 18, -348, 330, T.colors.dim)
    if scaleHint.SetWordWrap then scaleHint:SetWordWrap(true) end

    RefreshScalingState = function()
        local mode = Val(CurrentScope(), "frameScaleMode", "off")
        local manualOn = mode == "manual"
        local autoOn = mode == "auto"
        SetOptionEnabled(manualScale, manualOn)
        SetOptionEnabled(scaleAt10, autoOn)
        SetOptionEnabled(scaleAt20, autoOn)
        SetOptionEnabled(scaleAt25, autoOn)
        SetOptionEnabled(scaleOver25, autoOn)
        if autoLabel then
            if autoOn then
                autoLabel:SetTextColor(1.00, 0.82, 0.18, 1)
                autoLabel:SetAlpha(1)
            else
                autoLabel:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
                autoLabel:SetAlpha(0.55)
            end
        end
        if scaleHint then scaleHint:SetAlpha((manualOn or autoOn) and 1 or 0.55) end
    end
    M.AddRefresher(ctx, RefreshScalingState)
    RefreshScalingState()

    local transparency = b:CollapsibleSection("border", "Transparency", 310, false)
    local tHint = W.Text(transparency, "Outline border thickness is configured in\nGlobal Style > Bars > Outline & Highlight Border.", 14, -38, 300, { 0.60, 0.75, 1.00, 1 })
    if tHint.SetWordWrap then tHint:SetWordWrap(true) end

    local bgColor = W.Color(transparency, "Background Color")
    if bgColor._msuf2Title then
        bgColor._msuf2Title:ClearAllPoints()
        bgColor._msuf2Title:SetPoint("TOPLEFT", transparency, "TOPLEFT", 14, -92)
        bgColor._msuf2Title:SetWidth(120)
        bgColor._msuf2Title:SetJustifyH("LEFT")
    end
    bgColor:ClearAllPoints()
    bgColor:SetPoint("TOPLEFT", transparency, "TOPLEFT", 142, -90)
    bgColor:SetSize(34, 16)
    M.BindColor(ctx, bgColor,
        function()
            local conf = Conf(CurrentScope())
            return conf.bgR or 0.10, conf.bgG or 0.10, conf.bgB or 0.10
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf.bgR, conf.bgG, conf.bgB = r, g, b
            QueueGF(CurrentScope(), "visual")
        end)

    local function PlaceTransparencySlider(control, x, y, width)
        if not control then return end
        width = width or 270
        control._msuf2TitleJustify = "LEFT"
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", transparency, "TOPLEFT", x, y)
            control._msuf2Title:SetJustifyH("LEFT")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", transparency, "TOPLEFT", x, y - 22)
        if control._msuf2SetLayoutWidth then
            control:_msuf2SetLayoutWidth(width)
        else
            control:SetSize(width, 16)
            if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        end
    end

    local function BindTransparencySlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = tonumber(v) or default or 0
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(tonumber(value) or default or 0))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local bgAlpha = BindTransparencySlider(W.Slider(transparency, "", 0, 1, 0.05, 270), "bgA", 0.85,
        function(v) return string.format("Background Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceTransparencySlider(bgAlpha, 14, -120, 270)

    local hpFg = BindTransparencySlider(W.Slider(transparency, "", 0.3, 1, 0.05, 270), "hpBarAlpha", 1,
        function(v) return string.format("HP Bar Foreground: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceTransparencySlider(hpFg, 14, -166, 270)

    local preserveHP = W.ToggleAt(transparency, "Preserve HP color", 330, -188, 220)
    M.BindToggle(ctx, preserveHP,
        function() return Bool(CurrentScope(), "alphaPreserveHPColor", false) end,
        function(v) Set(CurrentScope(), "alphaPreserveHPColor", v and true or false, "visual") end)

    local textIgnore = W.ToggleAt(transparency, "Text ignores HP opacity", 14, -208, 250)
    M.BindToggle(ctx, textIgnore,
        function() return Bool(CurrentScope(), "hpTextIgnoreAlpha", true) end,
        function(v) Set(CurrentScope(), "hpTextIgnoreAlpha", v and true or false, "visual") end)

    local hpBg = W.Slider(transparency, "", 0, 1, 0.05, 270)
    M.BindSlider(ctx, hpBg,
        function()
            local conf = Conf(CurrentScope())
            return tonumber(conf.hpBgAlpha) or tonumber(conf.bgA) or 0.85
        end,
        function(v)
            local n = tonumber(v) or 0.85
            local conf = Conf(CurrentScope())
            if conf.hpBgAlpha == n then return end
            conf.hpBgAlpha = n
            QueueGF(CurrentScope(), "visual")
        end)
    local function RefreshHPBgLabel()
        if hpBg and hpBg._msuf2Title then
            local conf = Conf(CurrentScope())
            hpBg._msuf2Title:SetText(string.format("HP Background: %.0f%%", (tonumber(conf.hpBgAlpha) or tonumber(conf.bgA) or 0.85) * 100))
        end
    end
    hpBg:HookScript("OnValueChanged", function(_, value)
        if hpBg._msuf2Title then hpBg._msuf2Title:SetText(string.format("HP Background: %.0f%%", (tonumber(value) or 0) * 100)) end
    end)
    M.AddRefresher(ctx, RefreshHPBgLabel)
    RefreshHPBgLabel()
    PlaceTransparencySlider(hpBg, 14, -252, 270)

    local anchor = b:CollapsibleSection("anchor", "Anchoring", 220, false)

    local function PlaceAnchorDropdown(control, x, y, width)
        if not control then return end
        width = width or 200
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("LEFT")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y - 22)
        control:SetSize(width, 22)
    end

    local anchorTo = W.Dropdown(anchor, "Anchor To", GF_ANCHOR_TO, 200)
    PlaceAnchorDropdown(anchorTo, 14, -38, 200)
    M.BindDropdown(ctx, anchorTo,
        function() return Conf(CurrentScope()).anchorToFrame or "FREE" end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.anchorToFrame = (v == "FREE") and nil or v
            QueueGF(CurrentScope(), "rebuild")
        end)

    local anchorPoint = W.Dropdown(anchor, "Anchor Point", GF_ANCHOR_POINTS, 160)
    PlaceAnchorDropdown(anchorPoint, 254, -38, 160)
    BindScopeDropdown(ctx, anchorPoint, "anchorPoint", "CENTER", "rebuild")

    local customLabel = T.Font(anchor, "GameFontHighlightSmall", "Custom Anchor Frame", { 0.62, 0.74, 0.96, 1 })
    customLabel:SetPoint("TOPLEFT", anchor, "TOPLEFT", 14, -104)
    customLabel:SetJustifyH("LEFT")

    local customBox = CreateFrame("EditBox", nil, anchor, "InputBoxTemplate")
    customBox:SetPoint("TOPLEFT", anchor, "TOPLEFT", 14, -126)
    customBox:SetSize(200, 22)
    customBox:SetAutoFocus(false)
    customBox:SetMaxLetters(100)
    customBox:SetJustifyH("LEFT")
    T.SkinEditBox(customBox)

    local function IsStandardAnchorTarget(value)
        return value == nil or value == "" or value == "FREE" or value == "player" or value == "target"
            or value == "targettarget" or value == "focus"
    end

    local function RefreshCustomAnchorBox()
        local value = Conf(CurrentScope()).anchorToFrame or ""
        if customBox and not customBox:HasFocus() then
            customBox:SetText(IsStandardAnchorTarget(value) and "" or value)
        end
    end

    customBox:SetScript("OnEnterPressed", function(self)
        local value = self:GetText() or ""
        local conf = Conf(CurrentScope())
        conf.anchorToFrame = (value ~= "") and value or nil
        self:ClearFocus()
        QueueGF(CurrentScope(), "rebuild")
    end)
    customBox:SetScript("OnEscapePressed", function(self)
        RefreshCustomAnchorBox()
        self:ClearFocus()
    end)
    customBox:SetScript("OnEditFocusLost", RefreshCustomAnchorBox)

    local pick = T.Button(anchor, "Pick", 50, 22)
    pick:SetPoint("LEFT", customBox, "RIGHT", 6, 0)
    pick._msuf2Label:ClearAllPoints()
    pick._msuf2Label:SetPoint("CENTER", pick, "CENTER", 0, 0)
    pick._msuf2Label:SetJustifyH("CENTER")
    pick:SetScript("OnClick", function()
        local overlay = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker() or nil
        if not overlay then return end
        overlay._onPick = function(frameName)
            local conf = Conf(CurrentScope())
            conf.anchorToFrame = frameName
            customBox:SetText(frameName or "")
            QueueGF(CurrentScope(), "rebuild")
        end
        overlay:Show()
    end)

    local clear = T.SkinDangerButton(T.Button(anchor, "Clear", 50, 22))
    clear:SetPoint("LEFT", pick, "RIGHT", 4, 0)
    clear._msuf2Label:ClearAllPoints()
    clear._msuf2Label:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clear._msuf2Label:SetJustifyH("CENTER")
    clear:SetScript("OnClick", function()
        local conf = Conf(CurrentScope())
        conf.anchorToFrame = nil
        customBox:SetText("")
        QueueGF(CurrentScope(), "rebuild")
    end)

    M.AddRefresher(ctx, RefreshCustomAnchorBox)

    local tooltip = b:CollapsibleSection("tooltip", "Tooltip", 150, false)
    BindScopeDropdown(ctx, W.Dropdown(tooltip, "Tooltip Mode", TOOLTIP_MODES, 220), "tooltipMode", "ALWAYS", "visual")
    BindScopeDropdown(ctx, W.Dropdown(tooltip, "Modifier Key", TOOLTIP_MODIFIERS, 180), "tooltipModifier", "ALT", "visual")

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildGFBars(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    AddGFPreview(ctx, b)

    local hcolor = b:CollapsibleSection("hcolor", "Health Colors  (Global)", 156, true)
    local mode = W.Dropdown(hcolor, "Bar Color Mode", GF_BAR_MODES, 270)
    M.BindDropdown(ctx, mode,
        function() return Conf(CurrentScope()).gfBarMode or "GLOBAL" end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.gfBarMode = (v == "GLOBAL") and nil or v
            if v == "CLASS" or v == "GRADIENT" then conf.healthColorMode = v end
            QueueGF(CurrentScope(), "visual")
        end)
    local color = W.Color(hcolor, "Health bar")
    M.BindColor(ctx, color,
        function()
            local conf = Conf(CurrentScope())
            return conf.healthCustomR or conf.gfUnifiedR or 0.2, conf.healthCustomG or conf.gfUnifiedG or 0.8, conf.healthCustomB or conf.gfUnifiedB or 0.2
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf.healthCustomR, conf.healthCustomG, conf.healthCustomB = r, g, b
            QueueGF(CurrentScope(), "visual")
        end)

    local bars = b:CollapsibleSection("bars", "Bars  (Custom)", 206, false)
    BindScopeDropdown(ctx, W.Dropdown(bars, "Foreground Texture", SIMPLE_TEXTURES, 280), "barTexture", "", "visual")
    BindScopeDropdown(ctx, W.Dropdown(bars, "Background Texture", SIMPLE_TEXTURES, 280), "barBgTexture", "", "visual")
    BindScopeDropdown(ctx, W.Dropdown(bars, "Health color mode", HEALTH_MODES, 220), "healthColorMode", "CLASS", "visual")

    local power = b:CollapsibleSection("power", "Power Bar", 260, false)
    BindScopeSlider(ctx, W.Slider(power, "Power height", 0, 30, 1, 300), "powerHeight", 6, "geometry")
    BindScopeToggle(ctx, W.Toggle(power, "Smooth fill"), "powerSmoothFill", false, "visual")
    local showPowerText = W.Toggle(power, "Show power text")
    M.BindToggle(ctx, showPowerText,
        function()
            local gf = GF()
            if gf and type(gf.IsPowerTextEnabled) == "function" then
                return gf.IsPowerTextEnabled(CurrentScope(), Conf(CurrentScope())) and true or false
            end
            return Bool(CurrentScope(), "showPowerText", false) or Bool(CurrentScope(), "showPower", false)
        end,
        function(v)
            local gf = GF()
            if gf and type(gf.SetPowerTextEnabled) == "function" then
                gf.SetPowerTextEnabled(CurrentScope(), v and true or false)
                QueueGF(CurrentScope(), "visual")
            else
                Set(CurrentScope(), "showPowerText", v and true or false, "visual")
                Set(CurrentScope(), "showPower", v and true or false, "visual")
            end
        end)
    BindScopeToggle(ctx, W.Toggle(power, "Show power for tanks"), "powerShowTank", true, "visual")
    BindScopeToggle(ctx, W.Toggle(power, "Show power for healers"), "powerShowHealer", true, "visual")
    BindScopeToggle(ctx, W.Toggle(power, "Show power for damage"), "powerShowDamager", false, "visual")

    local text = b:CollapsibleSection("text", "Text", 706, false)
    BindScopeToggle(ctx, W.Toggle(text, "Show name"), "showName", true, "font")
    BindScopeSlider(ctx, W.Slider(text, "Name font size", 6, 48, 1, 260), "nameFontSize", 12, "font")
    BindScopeDropdown(ctx, W.Dropdown(text, "Name anchor", ANCHORS, 180), "nameAnchor", "LEFT", "geometry")
    BindScopeSlider(ctx, W.Slider(text, "Name X", -100, 100, 1, 260), "nameOffsetX", 0, "geometry")
    BindScopeSlider(ctx, W.Slider(text, "Name Y", -100, 100, 1, 260), "nameOffsetY", 0, "geometry")

    BindScopeToggle(ctx, W.Toggle(text, "Show health text"), "showHPText", true, "font")
    BindScopeDropdown(ctx, W.Dropdown(text, "Health left", TEXT_MODES, 240), "textLeft", "NONE", "visual")
    BindScopeDropdown(ctx, W.Dropdown(text, "Health center", TEXT_MODES, 240), "textCenter", "PERCENT", "visual")
    BindScopeDropdown(ctx, W.Dropdown(text, "Health right", TEXT_MODES, 240), "textRight", "NONE", "visual")
    BindScopeToggle(ctx, W.Toggle(text, "Reverse health text"), "hpTextReverse", false, "visual")
    BindScopeSlider(ctx, W.Slider(text, "Health font size", 6, 48, 1, 260), "hpFontSize", 10, "font")
    BindScopeSlider(ctx, W.Slider(text, "Health X", -100, 100, 1, 260), "hpOffsetX", 0, "geometry")
    BindScopeSlider(ctx, W.Slider(text, "Health Y", -100, 100, 1, 260), "hpOffsetY", 0, "geometry")

    local healpred = b:CollapsibleSection("healpred", "Heal Prediction", 120, false)
    BindScopeToggle(ctx, W.Toggle(healpred, "Heal Prediction Overlay"), "healPredEnabled", false, "visual")
    W.Text(healpred, "Shows incoming heals as a lighter overlay on the health bar.", 14, -74, ctx.width - 28, T.colors.muted)

    local dispel = b:CollapsibleSection("dispel", "Dispel Overlay", 284, false)
    local dispelToggle = BindScopeToggle(ctx, W.Toggle(dispel, "Enable Dispel Overlay"), "dispelOverlayEnabled", true, "visual")
    W.Text(dispel, "Tints the health bar when a dispellable debuff is active.", 14, -74, ctx.width - 28, T.colors.muted)
    dispel._msuf2CursorY = -108
    local dispelStyle = BindScopeDropdown(ctx, W.Dropdown(dispel, "Overlay style", DISPEL_OVERLAY_STYLES, 220), "dispelOverlayStyle", "FULL", "visual")
    local dispelCurrent = BindScopeToggle(ctx, W.Toggle(dispel, "Show on current health only"), "dispelOverlayOnHealth", true, "visual")
    local dispelAlpha = BindScopeSlider(ctx, W.Slider(dispel, "Overlay opacity", 0.05, 1, 0.05, 300), "dispelOverlayAlpha", 0.35, "visual")
    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ dispelStyle, dispelCurrent, dispelAlpha }, Bool(CurrentScope(), "dispelOverlayEnabled", true))
        SetOptionEnabled(dispelToggle, true)
    end)

    local stripe = b:CollapsibleSection("dstripe", "Debuff Stripe", 276, false)
    local stripeToggle = BindScopeToggle(ctx, W.Toggle(stripe, "Enable Debuff Stripe"), "debuffStripeEnabled", false, "visual")
    W.Text(stripe, "Shows a thin colored stripe for debuffs matched by the debuff filter.", 14, -74, ctx.width - 28, T.colors.muted)
    stripe._msuf2CursorY = -108
    local stripeEdge = BindScopeDropdown(ctx, W.Dropdown(stripe, "Stripe edge", DEBUFF_STRIPE_EDGES, 220), "debuffStripeEdge", "BOTTOM", "visual")
    local stripeHeight = BindScopeSlider(ctx, W.Slider(stripe, "Stripe height", 1, 8, 1, 300), "debuffStripeHeight", 3, "visual")
    local stripeAlpha = BindScopeSlider(ctx, W.Slider(stripe, "Stripe opacity", 0.10, 1, 0.05, 300), "debuffStripeAlpha", 0.60, "visual")
    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ stripeEdge, stripeHeight, stripeAlpha }, Bool(CurrentScope(), "debuffStripeEnabled", false))
        SetOptionEnabled(stripeToggle, true)
    end)

    local range = b:CollapsibleSection("range", "Range Fade", 210, false)
    local rangeToggle = BindScopeToggle(ctx, W.Toggle(range, "Enable Range Fade"), "rangeFadeEnabled", false, "visual")

    local function PlaceRangeDropdown(control, x, y, width)
        if not control then return end
        width = width or 180
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", range, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("LEFT")
            control._msuf2Title:SetTextColor(1.00, 0.82, 0.18, 1)
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", range, "TOPLEFT", x, y - 22)
        control:SetSize(width, 22)
    end

    local function PlaceRangeSlider(control, x, y, width)
        if not control then return end
        width = width or 270
        control._msuf2TitleJustify = "CENTER"
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", range, "TOPLEFT", x, y)
            control._msuf2Title:SetJustifyH("CENTER")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", range, "TOPLEFT", x, y - 22)
        if control._msuf2SetLayoutWidth then
            control:_msuf2SetLayoutWidth(width)
        else
            control:SetSize(width, 16)
            if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        end
    end

    local function BindRangeSlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = tonumber(v) or default or 0
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then widget._msuf2Title:SetText(labelFn(tonumber(value) or default or 0)) end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local rangeMode = BindScopeDropdown(ctx, W.Dropdown(range, "Range fade affects", {
        { value = "frame", text = "Frame" },
        { value = "health", text = "HP Bar" },
    }, 180), "rangeFadeLayerMode", "frame", "visual")
    PlaceRangeDropdown(rangeMode, 14, -74, 180)

    local rangeAlpha = BindRangeSlider(W.Slider(range, "", 0, 1, 0.05, 270), "rangeFadeAlpha", 0.4,
        function(v) return string.format("Out of Range Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(rangeAlpha, 14, -124, 270)

    local offlineAlpha = BindRangeSlider(W.Slider(range, "", 0, 1, 0.05, 270), "offlineAlpha", 0.5,
        function(v) return string.format("Offline Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(offlineAlpha, 14, -174, 270)

    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ rangeMode, rangeAlpha, offlineAlpha }, Bool(CurrentScope(), "rangeFadeEnabled", false))
        SetOptionEnabled(rangeToggle, true)
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    AddGFPreview(ctx, b)

    local renderer = b:CollapsibleSection("blizzrenderer", "Blizzard Renderer", 456, false)
    W.Text(renderer, "Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview.", 14, -38, 620, T.colors.muted)

    local function PlaceDropdown(dropdown, x, y, width, hideTitle)
        if dropdown._msuf2Title then
            dropdown._msuf2Title:ClearAllPoints()
            dropdown._msuf2Title:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y + 20)
            dropdown._msuf2Title:SetShown(not hideTitle)
        end
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y)
        dropdown:SetSize(width, 22)
    end

    local function PlaceSlider(slider, x, y, width)
        if slider._msuf2Title then
            slider._msuf2Title:ClearAllPoints()
            slider._msuf2Title:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y)
            slider._msuf2TitleJustify = "CENTER"
        end
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y - 22)
        if slider._msuf2SetLayoutWidth then slider:_msuf2SetLayoutWidth(width) end
    end

    local function BindRendererSlider(widget, getTable, key, default, mode, labelFn)
        BindNestedSlider(ctx, widget, getTable, key, default, mode)
        local function RefreshLabel()
            local tbl = getTable()
            local value = tonumber(tbl and tbl[key]) or default or 0
            if widget._msuf2Title then widget._msuf2Title:SetText(labelFn(value)) end
        end
        widget:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            if self._msuf2Title then self._msuf2Title:SetText(labelFn(value)) end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local rendererMode = BindNestedDropdown(ctx, W.Dropdown(renderer, "", GF_RENDERERS, 180), function() return AurasRoot(CurrentScope()) end, "renderer", "BLIZZARD", "rebuild")
    PlaceDropdown(rendererMode, 14, -96, 180, true)

    local iconSize = BindRendererSlider(W.Slider(renderer, "", 8, 80, 1, 260), function() return AurasRoot(CurrentScope()) end, "blizzardIconSize", 20, "geometry",
        function(v) return string.format("Icon size: %d", v) end)
    PlaceSlider(iconSize, 14, -156, 260)

    local buffMax = BindRendererSlider(W.Slider(renderer, "", 0, 20, 1, 260), function() return AuraGroup(CurrentScope(), "buff") end, "max", 6, "visual",
        function(v) return string.format("Buff max: %d", v) end)
    PlaceSlider(buffMax, 14, -208, 260)

    local debuffMax = BindRendererSlider(W.Slider(renderer, "", 0, 20, 1, 260), function() return AuraGroup(CurrentScope(), "debuff") end, "max", 3, "visual",
        function(v) return string.format("Debuff max: %d", v) end)
    PlaceSlider(debuffMax, 14, -260, 260)

    local routingLabel = W.Text(renderer, "Rendered by Blizzard", 350, -82, 330, T.colors.text)
    local buffChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Buffs", 350, -112, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "buffs", true, "rebuild")
    local debuffChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Debuffs", 350, -172, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "debuffs", true, "rebuild")
    local dispelChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Dispels", 350, -232, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "dispels", true, "rebuild")
    local extChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Defensives", 520, -112, 150), function() return AurasRoot(CurrentScope()).blizzardTypes end, "externals", true, "rebuild")
    local cdTextChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Blizzard Cooldown Text", 520, -172, 150), function() return AurasRoot(CurrentScope()) end, "blizzardShowCooldownText", true, "visual")
    local privateChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Private", 520, -232, 150), function() return AurasRoot(CurrentScope()).blizzardTypes end, "privateAuras", true, "rebuild")

    local orgLabel = W.Text(renderer, "Organization", 350, -292, 240, T.colors.text)
    local orgMode = BindNestedDropdown(ctx, W.Dropdown(renderer, "", GF_AURA_ORG, 260), function() return AurasRoot(CurrentScope()) end, "blizzardOrganizationType", "default", "geometry")
    PlaceDropdown(orgMode, 350, -314, 260, true)

    local posLabel = W.Text(renderer, "Blizzard Position", 350, -362, 240, T.colors.text)
    local posHint = W.Text(renderer, "Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime.", 350, -382, 330, T.colors.muted)

    M.AddRefresher(ctx, function()
        local native = (AurasRoot(CurrentScope()).renderer or "BLIZZARD") ~= "CUSTOM"
        SetOptionsEnabled({ buffChk, debuffChk, dispelChk, extChk, cdTextChk, privateChk, iconSize, buffMax, debuffMax, orgMode }, native)
        SetOptionEnabled(rendererMode, true)
        local c = native and T.colors.text or T.colors.dim
        routingLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        orgLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        posLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        posHint:SetTextColor((native and T.colors.muted or T.colors.dim)[1], (native and T.colors.muted or T.colors.dim)[2], (native and T.colors.muted or T.colors.dim)[3], native and 1 or 0.75)
    end)

    local buffs = b:CollapsibleSection("buffs", "Buffs", 420, false)
    local buffsEnable = BindNestedToggle(ctx, W.Toggle(buffs, "Enable buffs"), function() return AuraGroup(CurrentScope(), "buff") end, "enabled", true, "visual")
    local buffsControls = {
        BindNestedSlider(ctx, W.Slider(buffs, "Max buffs", 0, 20, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(buffs, "Icon size", 8, 64, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "size", 20, "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Icons per row", 1, 20, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "perRow", 4, "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Spacing", 0, 12, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "spacing", 1, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(buffs, "Filter", GF_AURA_FILTERS, 240), function() return AuraGroup(CurrentScope(), "buff") end, "filterToken", "RAID", "visual"),
        BindNestedDropdown(ctx, W.Dropdown(buffs, "Anchor", AURA_ANCHORS, 220), function() return AuraGroup(CurrentScope(), "buff") end, "anchor", "BOTTOMLEFT", "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Offset X", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Offset Y", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "y", 0, "geometry"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(buffsControls, AuraGroup(CurrentScope(), "buff").enabled ~= false)
        SetOptionEnabled(buffsEnable, true)
    end)

    local debuffs = b:CollapsibleSection("debuffs", "Debuffs", 420, false)
    local debuffsEnable = BindNestedToggle(ctx, W.Toggle(debuffs, "Enable debuffs"), function() return AuraGroup(CurrentScope(), "debuff") end, "enabled", true, "visual")
    local debuffsControls = {
        BindNestedSlider(ctx, W.Slider(debuffs, "Max debuffs", 0, 20, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Icon size", 8, 64, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "size", 20, "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Icons per row", 1, 20, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "perRow", 4, "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Spacing", 0, 12, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "spacing", 1, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(debuffs, "Filter", GF_AURA_FILTERS, 240), function() return AuraGroup(CurrentScope(), "debuff") end, "filterToken", "ALL", "visual"),
        BindNestedDropdown(ctx, W.Dropdown(debuffs, "Anchor", AURA_ANCHORS, 220), function() return AuraGroup(CurrentScope(), "debuff") end, "anchor", "BOTTOMRIGHT", "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Offset X", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Offset Y", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "y", 0, "geometry"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(debuffsControls, AuraGroup(CurrentScope(), "debuff").enabled ~= false)
        SetOptionEnabled(debuffsEnable, true)
    end)

    local externals = b:CollapsibleSection("ext", "Defensives", 282, false)
    local externalsEnable = BindNestedToggle(ctx, W.Toggle(externals, "Enable externals"), function() return AuraGroup(CurrentScope(), "externals") end, "enabled", true, "visual")
    local externalsControls = {
        BindNestedSlider(ctx, W.Slider(externals, "Max externals", 0, 12, 1, 300), function() return AuraGroup(CurrentScope(), "externals") end, "max", 2, "visual"),
        BindNestedSlider(ctx, W.Slider(externals, "Icon size", 8, 64, 1, 300), function() return AuraGroup(CurrentScope(), "externals") end, "size", 24, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(externals, "Filter", GF_AURA_FILTERS, 240), function() return AuraGroup(CurrentScope(), "externals") end, "filterToken", "RAID", "visual"),
        BindNestedDropdown(ctx, W.Dropdown(externals, "Anchor", AURA_ANCHORS, 220), function() return AuraGroup(CurrentScope(), "externals") end, "anchor", "TOPRIGHT", "geometry"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(externalsControls, AuraGroup(CurrentScope(), "externals").enabled ~= false)
        SetOptionEnabled(externalsEnable, true)
    end)

    local textcolor = b:CollapsibleSection("textcolor", "Text Coloring", 232, false)
    BindNestedToggle(ctx, W.Toggle(textcolor, "Show cooldown text"), function() return AurasRoot(CurrentScope()) end, "showCooldownText", true, "visual")
    BindNestedToggle(ctx, W.Toggle(textcolor, "Use pandemic coloring"), function() return AurasRoot(CurrentScope()) end, "pandemicColorEnabled", true, "visual")
    BindNestedSlider(ctx, W.Slider(textcolor, "Pandemic seconds", 1, 30, 1, 300), function() return AurasRoot(CurrentScope()) end, "pandemicSeconds", 5, "visual")
    BindNestedSlider(ctx, W.Slider(textcolor, "Text size", 6, 32, 1, 300), function() return AurasRoot(CurrentScope()) end, "textSize", 11, "font")

    local priv = b:CollapsibleSection("priv", "Private Auras", 390, false)
    local privEnable = BindNestedToggle(ctx, W.Toggle(priv, "Enable private auras"), function() return PrivateAuras(CurrentScope()) end, "enabled", true, "visual")
    local privControls = {
        BindNestedSlider(ctx, W.Slider(priv, "Private aura max", 0, 12, 1, 300), function() return PrivateAuras(CurrentScope()) end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura size", 8, 64, 1, 300), function() return PrivateAuras(CurrentScope()) end, "size", 20, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(priv, "Private aura anchor", AURA_ANCHORS, 220), function() return PrivateAuras(CurrentScope()) end, "anchor", "TOPRIGHT", "geometry"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura X", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura Y", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "y", 0, "geometry"),
        BindNestedToggle(ctx, W.Toggle(priv, "Show countdown"), function() return PrivateAuras(CurrentScope()) end, "showCountdown", true, "visual"),
        BindNestedToggle(ctx, W.Toggle(priv, "Show numbers"), function() return PrivateAuras(CurrentScope()) end, "showNumbers", false, "visual"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(privControls, PrivateAuras(CurrentScope()).enabled ~= false)
        SetOptionEnabled(privEnable, true)
    end)

    local style = b:CollapsibleSection("masque", "Cooldown Style", 166, false)
    BindScopeToggle(ctx, W.Toggle(style, "Cooldown darkens on loss"), "cooldownSwipeDarkenOnLoss", false, "visual")
    BindScopeToggle(ctx, W.Toggle(style, "Masque skin"), "masqueEnabled", false, "visual")
    BindNestedToggle(ctx, W.Toggle(style, "Dynamic icon scale"), function() return AurasRoot(CurrentScope()) end, "dynamicScale", false, "geometry")

    local utilities = b:CollapsibleSection("autil", "Aura Utilities", 180, false)
    BindNestedToggle(ctx, W.Toggle(utilities, "Show tooltip on auras"), function() return AurasRoot(CurrentScope()) end, "showTooltip", true, "visual")
    BindNestedToggle(ctx, W.Toggle(utilities, "Sort by duration"), function() return AurasRoot(CurrentScope()) end, "sortByDuration", false, "visual")
    BindNestedToggle(ctx, W.Toggle(utilities, "Prefer player auras"), function() return AurasRoot(CurrentScope()) end, "preferPlayer", true, "visual")

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    AddGFPreview(ctx, b)

    local indicators = b:CollapsibleSection("indicators", "Indicators", 520, true)
    W.Text(indicators, "Aggro, dispel and target highlight are controlled from Global Style > Bars.", 14, -38, ctx.width - 28, T.colors.muted)
    indicators._msuf2CursorY = -78
    BindScopeToggle(ctx, W.Toggle(indicators, "Show group number"), "showGroupNumber", false, "visual")
    BindScopeSlider(ctx, W.Slider(indicators, "Group number size", 6, 24, 1, 260), "groupNumberSize", 10, "font")
    BindScopeDropdown(ctx, W.Dropdown(indicators, "Group number anchor", AURA_ANCHORS, 220), "groupNumberAnchor", "TOPLEFT", "geometry")
    BindScopeSlider(ctx, W.Slider(indicators, "Group number X", -100, 100, 1, 260), "groupNumberX", -2, "geometry")
    BindScopeSlider(ctx, W.Slider(indicators, "Group number Y", -100, 100, 1, 260), "groupNumberY", 2, "geometry")
    BindScopeSlider(ctx, W.Slider(indicators, "Hover highlight border", 1, 6, 1, 260), "hlHoverSize", 1, "visual")
    BindScopeToggle(ctx, W.Toggle(indicators, "Enable Focus Glow"), "hlFocusEnabled", true, "visual")
    BindScopeSlider(ctx, W.Slider(indicators, "Focus border thickness", 1, 6, 1, 260), "hlFocusSize", 2, "visual")

    local sicons = b:CollapsibleSection("sicons", "Status Icons", 672, false)
    BindScopeDropdown(ctx, W.Dropdown(sicons, "Icon style", IconStyleValues, 260), "iconStyle", "BLIZZARD", "visual")
    BindScopeToggle(ctx, W.Toggle(sicons, "Use Midnight Style"), "useMidnightIcons", false, "visual")

    local statusSelector = W.Dropdown(sicons, "Indicator", GF_STATUS_ICON_VALUES, 260)
    M.BindDropdown(ctx, statusSelector,
        function() return CurrentGFStatusSpec().value end,
        function(value)
            for i = 1, #GF_STATUS_ICON_SPECS do
                if GF_STATUS_ICON_SPECS[i].value == value then
                    M.gfStatusIconSelection = value
                    local gf = GF()
                    if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(value) end
                    if M.SelectPage then M.SelectPage(ctx.key) end
                    return
                end
            end
        end)

    local statusEnabled = W.Toggle(sicons, "Enabled")
    M.BindToggle(ctx, statusEnabled,
        function()
            local spec = CurrentGFStatusSpec()
            return Bool(CurrentScope(), spec.enabled, true)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.enabled, value and true or false, "visual")
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local statusSize = W.Slider(sicons, "Size", 6, 40, 1, 300)
    M.BindSlider(ctx, statusSize,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.size, spec.defaultSize)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.size, floor((tonumber(value) or spec.defaultSize) + 0.5), "visual")
        end)

    local statusAnchor = W.Dropdown(sicons, "Anchor", STATUS_ICON_ANCHORS, 220)
    M.BindDropdown(ctx, statusAnchor,
        function()
            local spec = CurrentGFStatusSpec()
            return Val(CurrentScope(), spec.anchor, spec.defaultAnchor)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.anchor, value or spec.defaultAnchor, "geometry")
        end)

    local statusX = W.Slider(sicons, "X Offset", -100, 100, 1, 300)
    M.BindSlider(ctx, statusX,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.x, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.x, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)

    local statusY = W.Slider(sicons, "Y Offset", -100, 100, 1, 300)
    M.BindSlider(ctx, statusY,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.y, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.y, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)

    local statusLayer = W.Slider(sicons, "Layer", 0, 30, 1, 300)
    M.BindSlider(ctx, statusLayer,
        function()
            local spec = CurrentGFStatusSpec()
            local value = Num(CurrentScope(), spec.layer, spec.defaultLayer)
            if value < 0 then value = 0 elseif value > 30 then value = 30 end
            return value
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            value = floor((tonumber(value) or spec.defaultLayer) + 0.5)
            if value < 0 then value = 0 elseif value > 30 then value = 30 end
            Set(CurrentScope(), spec.layer, value, "visual")
        end)

    local statusReset = W.Button(sicons, "Reset selected", 150)
    statusReset:SetScript("OnClick", function()
        local kind = CurrentScope()
        local spec = CurrentGFStatusSpec()
        local conf = Conf(kind)
        local gf = GF()
        for _, key in ipairs({ spec.size, spec.anchor, spec.x, spec.y, spec.layer }) do
            if key then
                conf[key] = gf and gf.GetDefault and gf.GetDefault(kind, key) or nil
            end
        end
        QueueGF(kind, "visual")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local previewCurrent = W.Button(sicons, "Preview current", 142)
    previewCurrent:SetScript("OnClick", function()
        local gf = GF()
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("current") end
        if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        QueueGF(CurrentScope(), "visual")
    end)
    local previewAll = W.Button(sicons, "Show all", 112)
    previewAll:SetScript("OnClick", function()
        local gf = GF()
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("all") end
        QueueGF(CurrentScope(), "visual")
    end)

    M.AddRefresher(ctx, function()
        local spec = CurrentGFStatusSpec()
        local enabled = Bool(CurrentScope(), spec.enabled, true)
        SetOptionEnabled(statusSize, enabled)
        SetOptionEnabled(statusAnchor, enabled)
        SetOptionEnabled(statusX, enabled)
        SetOptionEnabled(statusY, enabled)
        SetOptionEnabled(statusLayer, enabled)
        SetOptionEnabled(statusReset, spec ~= nil)
    end)

    local spells = b:CollapsibleSection("si", "Spell Indicators", 922, false)
    M.BindToggle(ctx, W.Toggle(spells, "Enable Spell Indicators"),
        function() return SpellIndicators(CurrentScope()).enabled == true end,
        function(value)
            SpellIndicators(CurrentScope()).enabled = value and true or false
            QueueSpellIndicators(CurrentScope())
        end)
    BindNestedSlider(ctx, W.Slider(spells, "Layer", 1, 15, 1, 300), function() return SpellIndicators(CurrentScope()) end, "layer", 9, "visual")

    local specDrop = W.Dropdown(spells, "Spec", SpellSpecValues, 260)
    M.BindDropdown(ctx, specDrop,
        function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[kind] = nil
            QueueSpellIndicators(kind)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local multiSpecDrop = W.Dropdown(spells, "Multi-Spec Entry", function() return SpellTrackedSpecValues() end, 300)
    M.BindDropdown(ctx, multiSpecDrop,
        function() return CurrentSpellMultiSpec(CurrentScope()) end,
        function(value)
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[CurrentScope()] = value or ""
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local multiSpecEnabled = W.Toggle(spells, "Track selected multi spec")
    M.BindToggle(ctx, multiSpecEnabled,
        function()
            local cfg = SpellIndicators(CurrentScope())
            local specKey = CurrentSpellMultiSpec(CurrentScope())
            return cfg.spec == "multi" and specKey ~= "" and cfg.multiSpecs and cfg.multiSpecs[specKey] == true
        end,
        function(value)
            local kind = CurrentScope()
            local cfg = SpellIndicators(kind)
            local specKey = CurrentSpellMultiSpec(kind)
            if specKey == "" then return end
            cfg.multiSpecs = cfg.multiSpecs or {}
            cfg.multiSpecs[specKey] = value and true or nil
            QueueSpellIndicators(kind)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local auraDrop = W.Dropdown(spells, "Spell", function() return SpellAuraValues(CurrentScope()) end, 300)
    M.BindDropdown(ctx, auraDrop,
        function() return CurrentSpellAura(CurrentScope()) end,
        function(value)
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[CurrentScope()] = value
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local spellEnabled = W.Toggle(spells, "Selected spell enabled")
    M.BindToggle(ctx, spellEnabled,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.enabled ~= false or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.enabled = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local onlyMine = W.Toggle(spells, "Only my cast")
    M.BindToggle(ctx, onlyMine,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.onlyOwn ~= false or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.onlyOwn = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedType = W.Dropdown(spells, "Indicator Type", PLACED_INDICATOR_TYPES, 260)
    M.BindDropdown(ctx, placedType,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.type or "none"
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if not cfg then return end
            if value == "none" then
                cfg.placed = false
            else
                cfg.placed = cfg.placed or {}
                cfg.placed.type = value or "icon"
                cfg.placed.anchor = cfg.placed.anchor or "TOPLEFT"
                cfg.placed.size = tonumber(cfg.placed.size) or 18
            end
            QueueSpellIndicators(CurrentScope())
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local placedAnchor = W.Dropdown(spells, "Indicator Anchor", STATUS_ICON_ANCHORS, 220)
    M.BindDropdown(ctx, placedAnchor,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.anchor or "TOPLEFT"
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.anchor = value or "TOPLEFT" end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedSize = W.Slider(spells, "Indicator Size", 6, 48, 1, 300)
    M.BindSlider(ctx, placedSize,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.size) or 18
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.size = floor((tonumber(value) or 18) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedX = W.Slider(spells, "Indicator X", -100, 100, 1, 300)
    M.BindSlider(ctx, placedX,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.x) or 0
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.x = floor((tonumber(value) or 0) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedY = W.Slider(spells, "Indicator Y", -100, 100, 1, 300)
    M.BindSlider(ctx, placedY,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.y) or 0
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.y = floor((tonumber(value) or 0) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedBarWidth = W.Slider(spells, "Bar Width", 8, 120, 1, 300)
    M.BindSlider(ctx, placedBarWidth,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.barWidth) or 42
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.barWidth = floor((tonumber(value) or 42) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedGrowth = W.Dropdown(spells, "Growth", SPELL_GROWTH_VALUES, 240)
    M.BindDropdown(ctx, placedGrowth,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.growth or "RIGHTDOWN"
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.growth = value or "RIGHTDOWN" end
            QueueSpellIndicators(CurrentScope())
        end)

    local frameType = W.Dropdown(spells, "Frame Effect", FRAME_EFFECT_TYPES, 260)
    M.BindDropdown(ctx, frameType,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            return frame and frame.type or "none"
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if not cfg then return end
            if value == "none" then
                cfg.frame = false
            else
                cfg.frame = cfg.frame or {}
                cfg.frame.type = value
            end
            QueueSpellIndicators(CurrentScope())
        end)

    M.AddRefresher(ctx, function()
        local multi = SpellIndicators(CurrentScope()).spec == "multi"
        if W.SetControlShown then
            W.SetControlShown(multiSpecDrop, multi)
            W.SetControlShown(multiSpecEnabled, multi)
        else
            multiSpecDrop:SetShown(multi)
            multiSpecEnabled:SetShown(multi)
        end
        local placed = PlacedConfig(CurrentScope(), false)
        local placedEnabled = placed and placed.type and placed.type ~= "none"
        local hasSpell = CurrentSpellConfig(CurrentScope(), false) ~= nil
        SetOptionEnabled(spellEnabled, hasSpell)
        SetOptionEnabled(onlyMine, hasSpell)
        SetOptionEnabled(placedType, hasSpell)
        SetOptionEnabled(frameType, hasSpell)
        SetOptionEnabled(placedAnchor, placedEnabled)
        SetOptionEnabled(placedSize, placedEnabled)
        SetOptionEnabled(placedX, placedEnabled)
        SetOptionEnabled(placedY, placedEnabled)
        SetOptionEnabled(placedBarWidth, placedEnabled and placed.type == "bar")
        SetOptionEnabled(placedGrowth, placedEnabled)
    end)

    local corners = b:CollapsibleSection("ci", "Corner Indicators", 1046, false)
    BindScopeToggle(ctx, W.Toggle(corners, "Enable"), "ciEnabled", true, "visual")
    BindScopeSlider(ctx, W.Slider(corners, "Icon Size", 4, 24, 1, 300), "ciSize", 8, "visual")
    local ciAlpha = W.Slider(corners, "Alpha", 10, 100, 5, 300)
    M.BindSlider(ctx, ciAlpha,
        function() return floor((Num(CurrentScope(), "ciAlpha", 1) * 100) + 0.5) end,
        function(value) Set(CurrentScope(), "ciAlpha", (tonumber(value) or 100) / 100, "visual") end)

    for i = 1, #CI_SLOT_VALUES do
        local slotInfo = CI_SLOT_VALUES[i]
        local slotKey = slotInfo.value
        local slotDrop = W.Dropdown(corners, slotInfo.text .. " Indicator", CICategoryValues, 260)
        M.BindDropdown(ctx, slotDrop,
            function()
                return Val(CurrentScope(), "ciSlot" .. slotKey, CI_SLOT_DEFAULTS[slotKey] or "none")
            end,
            function(value)
                M.gfCornerSlotSelection = slotKey
                Set(CurrentScope(), "ciSlot" .. slotKey, value or "none", "visual")
                if M.SelectPage then M.SelectPage(ctx.key) end
            end)
    end

    local slotDrop = W.Dropdown(corners, "Custom editor slot", CI_SLOT_VALUES, 220)
    M.BindDropdown(ctx, slotDrop,
        function() return CurrentCISlot() end,
        function(value)
            M.gfCornerSlotSelection = value or "TL"
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local categoryDrop = W.Dropdown(corners, "Selected slot indicator", CICategoryValues, 260)
    M.BindDropdown(ctx, categoryDrop,
        function()
            local slot = CurrentCISlot()
            return Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        end,
        function(value)
            local slot = CurrentCISlot()
            Set(CurrentScope(), "ciSlot" .. slot, value or "none", "visual")
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local customSpells = W.TextInput(corners, "Custom Spell IDs", 380)
    M.BindTextInput(ctx, customSpells,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.spells or ""
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.spells = value or "" end
            QueueGF(CurrentScope(), "visual")
        end,
        true)

    local customMode = W.Dropdown(corners, "Custom Mode", CIModeValues, 260)
    M.BindDropdown(ctx, customMode,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.mode or "present"
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.mode = value or "present" end
            QueueGF(CurrentScope(), "visual")
        end)

    local customFilter = W.Dropdown(corners, "Custom Filter", CIFilterValues, 260)
    M.BindDropdown(ctx, customFilter,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.filter or "HELPFUL|PLAYER"
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.filter = value or "HELPFUL|PLAYER" end
            QueueGF(CurrentScope(), "visual")
        end)

    local customColor = W.Color(corners, "Custom Color")
    M.BindColor(ctx, customColor,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return (cfg and cfg.r) or 0.40, (cfg and cfg.g) or 1.00, (cfg and cfg.b) or 0.40
        end,
        function(r, g, b)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.r, cfg.g, cfg.b = r, g, b end
            QueueGF(CurrentScope(), "visual")
        end)

    M.AddRefresher(ctx, function()
        local slot = CurrentCISlot()
        local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        local showCustom = category == "custom"
        for _, control in ipairs({ customSpells, customMode, customFilter, customColor }) do
            if control then
                control:SetShown(showCustom)
                if control._msuf2Title then control._msuf2Title:SetShown(showCustom) end
            end
        end
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 5 })
M.RegisterPage("gf_bars", { title = "MSUF Group Health & Text", build = BuildGFBars, version = 5 })
M.RegisterPage("gf_auras", { title = "MSUF Group Buffs & Debuffs", build = BuildGFAuras, version = 5 })
M.RegisterPage("gf_indicators", { title = "MSUF Group Indicators", build = BuildGFIndicators, version = 5 })
