local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets
local GP = M.GroupPage or {}
local SetSectionHeaderStatus = GP.SetSectionHeaderStatus

local floor = math.floor
local max = math.max
local min = math.min

local LAYER_HEADER_COLOR = { 0.45, 0.50, 0.62, 0.80 }
local LAYER_TEXT_ON = { 0.76, 0.80, 0.90, 0.95 }
local LAYER_TEXT_OFF = { 0.30, 0.30, 0.36, 0.55 }
local LAYER_TEXT_HIGHLIGHT = { 0.90, 0.92, 1.00, 1.00 }

local function SetFSColor(fs, color)
    if fs and fs.SetTextColor and color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function LayerFont(parent, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText((M.Tr and M.Tr(text or "")) or (text or ""))
    SetFSColor(fs, color or LAYER_TEXT_ON)
    return fs
end

local function GroupPage()
    M.GroupPage = M.GroupPage or {}
    return M.GroupPage
end

local function CurrentScope()
    local gp = GroupPage()
    if type(gp.CurrentScope) == "function" then return gp.CurrentScope() end
    return M.gfScope or "party"
end

local function Conf(kind)
    local gp = GroupPage()
    if type(gp.Conf) == "function" then return gp.Conf(kind) end
    return {}
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
    btn._label = LayerFont(btn, label, LAYER_TEXT_ON)
    btn._label:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn._label:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    btn._label:SetJustifyH("LEFT")
    btn._off = LayerFont(btn, "OFF", LAYER_TEXT_OFF)
    btn._off:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn._off:SetJustifyH("RIGHT")
    btn._off:Hide()
    btn:SetScript("OnClick", function() end)
    function btn:SetPreviewActive(active, visible, solo, available)
        visible = visible ~= false
        available = available ~= false
        self._off:SetShown(not available)
        if not available then
            self._bg:SetColorTexture(0.018, 0.018, 0.024, 0.52)
            self._stripe:SetColorTexture(0.18, 0.18, 0.22, 0.42)
            SetFSColor(self._label, LAYER_TEXT_OFF)
            SetFSColor(self._off, LAYER_TEXT_OFF)
        elseif solo then
            self._bg:SetColorTexture(0.20, 0.14, 0.02, 0.75)
            self._stripe:SetColorTexture(1.00, 0.82, 0.18, 1)
            SetFSColor(self._label, LAYER_TEXT_HIGHLIGHT)
        elseif active and visible then
            local bg = T.colors.pillActive
            self._bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
            SetFSColor(self._label, LAYER_TEXT_HIGHLIGHT)
            self._stripe:SetAlpha(1)
        elseif not visible then
            self._bg:SetColorTexture(0.02, 0.02, 0.03, 0.45)
            self._stripe:SetColorTexture(0.16, 0.16, 0.20, 0.45)
            SetFSColor(self._label, LAYER_TEXT_OFF)
        else
            self._bg:SetColorTexture(0.020, 0.024, 0.046, 0.85)
            SetFSColor(self._label, LAYER_TEXT_ON)
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

local function PreviewHealthColor(conf, pct, classToken)
    conf = conf or {}
    local gfMode = conf.gfBarMode
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = type(getCache) == "function" and getCache() or nil
    local mode
    if gfMode and gfMode ~= "GLOBAL" then
        mode = gfMode
    else
        local globalMode = cache and cache.barMode
        if globalMode == "dark" or globalMode == "unified" then
            mode = globalMode
        else
            mode = conf.healthColorMode or "CLASS"
        end
    end

    if mode == "dark" then
        return conf.gfDarkR or (cache and cache.darkBarR) or 0,
            conf.gfDarkG or (cache and cache.darkBarG) or 0,
            conf.gfDarkB or (cache and cache.darkBarB) or 0
    end
    if mode == "unified" then
        return conf.gfUnifiedR or (cache and cache.unifiedBarR) or 0.10,
            conf.gfUnifiedG or (cache and cache.unifiedBarG) or 0.60,
            conf.gfUnifiedB or (cache and cache.unifiedBarB) or 0.90
    end
    if mode == "CLASS" then
        local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
        local r, g, b
        if type(fastClass) == "function" then
            r, g, b = fastClass(classToken)
        end
        if not r then
            local cc = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
        return r or 0.2, g or 0.8, b or 0.2
    end
    if mode == "GRADIENT" then
        local p = max(0, min(1, tonumber(pct) or 0.72))
        local r = p > 0.5 and (1 - (p - 0.5) * 2) or 1
        local g = p > 0.5 and 1 or (p * 2)
        return r, g, 0
    end
    return conf.healthCustomR or 0.2,
        conf.healthCustomG or 0.8,
        conf.healthCustomB or 0.2
end

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local GF_PREVIEW_MIN_W = 380
local GF_PREVIEW_MIN_H = 130
local GF_PREVIEW_ROLE = "HEALER"

local GF_PREVIEW_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local function PreviewClassColor(classToken, dr, dg, db)
    if type(_G.MSUF_UFCore_GetClassBarColorFast) == "function" then
        local r, g, b = _G.MSUF_UFCore_GetClassBarColorFast(classToken)
        if r then return r, g, b end
    end
    local c = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return dr or 0.06, dg or 0.06, db or 0.07
end

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

local GF_AURA_GROWTH_TABLE = {
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

local function GFPreviewAuraGrowth(growth)
    return GF_AURA_GROWTH_TABLE[growth] or GF_AURA_GROWTH_TABLE.RIGHTDOWN
end

local function GFPreviewInt(value, fallback, minValue, maxValue)
    local n = floor((tonumber(value) or tonumber(fallback) or 0) + 0.0001)
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

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

local function GFPreviewCurrentSpellInfo(kind)
    local gp = GroupPage()
    local gf = ns and ns.GF
    local si = gf and gf.SpellIndicators
    local specKey = type(gp.EffectiveSpellSpec) == "function" and gp.EffectiveSpellSpec(kind) or nil
    local auraName = type(gp.CurrentSpellAura) == "function" and gp.CurrentSpellAura(kind) or nil
    if not (specKey and auraName and auraName ~= "") then return nil, specKey, auraName end
    local trackable = si and si.TrackableAuras and si.TrackableAuras[specKey]
    if type(trackable) == "table" then
        for i = 1, #trackable do
            local info = trackable[i]
            if info and info.name == auraName then return info, specKey, auraName end
        end
    end
    return nil, specKey, auraName
end

local function GFPreviewCurrentSpellConfig(kind)
    local gp = GroupPage()
    if type(gp.CurrentSpellConfig) == "function" then
        local cfg = gp.CurrentSpellConfig(kind, false)
        if type(cfg) == "table" then return cfg end
    end
    return nil
end

local function GFPreviewCurrentSpellPlaced(kind)
    local gp = GroupPage()
    if type(gp.PlacedConfig) == "function" then
        local placed = gp.PlacedConfig(kind, false)
        if type(placed) == "table" then return placed end
    end
    local cfg = GFPreviewCurrentSpellConfig(kind)
    return type(cfg and cfg.placed) == "table" and cfg.placed or nil
end

local function GFPreviewCurrentSpellTexture(kind)
    local info, specKey, auraName = GFPreviewCurrentSpellInfo(kind)
    local gf = ns and ns.GF
    local si = gf and gf.SpellIndicators
    if si and type(si.GetAuraIcon) == "function" and specKey and auraName and auraName ~= "" then
        local ok, icon = pcall(si.GetAuraIcon, specKey, auraName)
        if ok and icon then return icon end
    end
    if info and info.spellId then return GFMockSpellTexture(info.spellId) end
    return GFMockSpellTexture(774)
end

local function GFPreviewCurrentSpellColor(kind)
    local info = GFPreviewCurrentSpellInfo(kind)
    local c = info and info.color
    return (c and c[1]) or 0.69, (c and c[2]) or 0.50, (c and c[3]) or 0.88
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

local function GFPreviewPointOffset(px, py, anchorFrame, anchor)
    local frac = GF_PREVIEW_ANCHOR_FRAC[anchor]
    if not (anchorFrame and frac) then return 0, 0 end
    local aL, aB = anchorFrame:GetLeft() or 0, anchorFrame:GetBottom() or 0
    local aW, aH = anchorFrame:GetWidth() or 1, anchorFrame:GetHeight() or 1
    local ax = aL + aW * frac[1]
    local ay = aB + aH * frac[2]
    return GFPreviewRound((px or 0) - ax), GFPreviewRound((py or 0) - ay)
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

local function GFPreviewHandleText(handle)
    if not handle then return "Group preview" end
    local label = handle._label
    local text = label and label.GetText and label:GetText()
    if text and text ~= "" then return text end
    local previewText = handle._previewText
    if previewText and previewText ~= "" then return previewText end
    return handle._key or "Group preview"
end

local GF_STATUS_PREVIEW_FALLBACK_SPECS = {
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

local function GFPreviewStatusSpecs()
    local gp = GroupPage()
    if type(gp.GF_STATUS_ICON_SPECS) == "table" and #gp.GF_STATUS_ICON_SPECS > 0 then
        return gp.GF_STATUS_ICON_SPECS
    end
    return GF_STATUS_PREVIEW_FALLBACK_SPECS
end

local function GFPreviewCurrentStatusSpec()
    local gp = GroupPage()
    if type(gp.CurrentGFStatusSpec) == "function" then
        local spec = gp.CurrentGFStatusSpec()
        if type(spec) == "table" then return spec end
    end
    local specs = GFPreviewStatusSpecs()
    local selected = M.gfStatusIconSelection or "roleIcon"
    for i = 1, #specs do
        if specs[i].value == selected then return specs[i] end
    end
    return specs[1]
end

local function GFPreviewStatusSpecIsText(spec)
    local value = spec and spec.value
    return value == "statusText" or value == "statusGhostText" or value == "statusAFKText"
end

local function GFPreviewStatusText(spec)
    local value = spec and spec.value
    if value == "statusGhostText" then return "GHOST" end
    if value == "statusAFKText" then return "AFK" end
    return "DEAD"
end

local function GFPreviewStatusLabel(spec)
    local value = spec and spec.value
    if value == "roleIcon" then return "Role" end
    if value == "leaderIcon" then return "Leader" end
    if value == "assistIcon" then return "Assist" end
    if value == "raidMarker" then return "Marker" end
    if value == "readyCheckIcon" then return "Ready" end
    if value == "summonIcon" then return "Summon" end
    if value == "resurrectIcon" then return "Rez" end
    if value == "phaseIcon" then return "Phase" end
    if value == "statusText" then return "Dead Text" end
    if value == "statusGhostText" then return "Ghost Text" end
    if value == "statusAFKText" then return "AFK/DND" end
    return (spec and spec.text) or "Status"
end

local function GFPreviewStatusPreviewMode()
    local gf = ns and ns.GF
    if gf and type(gf.GetStatusPreviewMode) == "function" then
        local mode = gf.GetStatusPreviewMode()
        if mode == "all" then return "all" end
    end
    return M.gfStatusPreviewMode == "all" and "all" or "current"
end

local function GFPreviewStatusSpecEnabled(conf, spec)
    if not spec then return false end
    conf = conf or {}
    return conf[spec.enabled] ~= false
end

local function GFPreviewStatusSpecInMode(spec, selectedSpec)
    if GFPreviewStatusPreviewMode() == "all" then return true end
    local selected = selectedSpec and selectedSpec.value or M.gfStatusIconSelection or "roleIcon"
    return spec and spec.value == selected
end

local function GFPreviewCurrentTextKind()
    local scope = CurrentScope()
    local selected = M.gfTextTabSelection and M.gfTextTabSelection[scope] or "name"
    if selected == "hp" or selected == "power" then return selected end
    return "name"
end

local function GFPreviewTextOffsetKeys(kind, slot)
    if kind == "hp" then
        if slot == "left" then return "hpTextLeftOffsetX", "hpTextLeftOffsetY" end
        if slot == "center" then return "hpTextCenterOffsetX", "hpTextCenterOffsetY" end
        if slot == "right" then return "hpTextRightOffsetX", "hpTextRightOffsetY" end
        return "hpOffsetX", "hpOffsetY"
    end
    if kind == "power" then
        if slot == "left" then return "powerTextLeftOffsetX", "powerTextLeftOffsetY" end
        if slot == "center" then return "powerTextCenterOffsetX", "powerTextCenterOffsetY" end
        if slot == "right" then return "powerTextRightOffsetX", "powerTextRightOffsetY" end
        return "powerOffsetX", "powerOffsetY"
    end
    return "nameOffsetX", "nameOffsetY"
end

local function GFPreviewTextLabel(kind, slot)
    if kind == "hp" then
        if slot == "left" then return "HP Left Text" end
        if slot == "center" then return "HP Center Text" end
        if slot == "right" then return "HP Right Text" end
        return "HP Text"
    end
    if kind == "power" then
        if slot == "left" then return "Power Left Text" end
        if slot == "center" then return "Power Center Text" end
        if slot == "right" then return "Power Right Text" end
        return "Power Text"
    end
    return "Name Text"
end

local function GFPreviewTextMovesTogether(scope, kind)
    local byScope = M.gfTextMoveTogether and M.gfTextMoveTogether[scope or CurrentScope()]
    local value = byScope and byScope[kind]
    if value == nil then return true end
    return value == true
end

local function GFPreviewSetTextMoveTogether(scope, kind, value)
    scope = scope or CurrentScope()
    M.gfTextMoveTogether = M.gfTextMoveTogether or {}
    M.gfTextMoveTogether[scope] = M.gfTextMoveTogether[scope] or {}
    M.gfTextMoveTogether[scope][kind] = value ~= false
end

local function GFPreviewPlaceHandleAroundRegions(handle, parent, regions, pad)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    pad = tonumber(pad) or 3
    local left, right, top, bottom
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() and region.GetLeft then
            local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
            if l and r and t and b then
                local regionW = r - l
                if region.GetStringWidth and regionW > 0 then
                    local textW = tonumber(region:GetStringWidth()) or 0
                    if textW > 0 and textW < regionW then
                        local justify = (region.GetJustifyH and region:GetJustifyH()) or region._msufPreviewJustifyH or "LEFT"
                        if justify == "RIGHT" then
                            l = r - textW
                        elseif justify == "CENTER" then
                            local cx = (l + r) * 0.5
                            l = cx - (textW * 0.5)
                            r = cx + (textW * 0.5)
                        else
                            r = l + textW
                        end
                    end
                end
                local regionH = t - b
                if region.GetStringHeight and regionH > 0 then
                    local textH = tonumber(region:GetStringHeight()) or 0
                    if textH > 0 and textH < regionH then
                        local cy = (t + b) * 0.5
                        t = cy + (textH * 0.5)
                        b = cy - (textH * 0.5)
                    end
                end
                left = left and min(left, l) or l
                right = right and max(right, r) or r
                top = top and max(top, t) or t
                bottom = bottom and min(bottom, b) or b
            end
        end
    end
    local pLeft, pBottom = parent:GetLeft(), parent:GetBottom()
    if not (left and right and top and bottom and pLeft and pBottom) then return false end
    handle:ClearAllPoints()
    handle:SetSize(max(18, right - left + pad * 2), max(18, top - bottom + pad * 2))
    handle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left - pLeft - pad, bottom - pBottom - pad)
    handle:Show()
    return true
end

local function GFPreviewHandleOffsets(handle)
    if not handle then return nil end
    local conf = Conf(CurrentScope()) or {}
    if handle._cfgGroup then
        local auras = conf.auras or {}
        local cfg = auras[handle._cfgGroup] or {}
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgStatus then
        local spec = handle._statusSpec or GFPreviewCurrentStatusSpec()
        if not spec then return nil end
        return conf[spec.anchor] or spec.defaultAnchor, tonumber(conf[spec.x]) or 0, tonumber(conf[spec.y]) or 0
    elseif handle._cfgPrivate then
        local cfg = conf.privateAuras or {}
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgSpell then
        local cfg = GFPreviewCurrentSpellPlaced(CurrentScope()) or {}
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgText then
        local kind = handle._cfgTextKind or GFPreviewCurrentTextKind()
        local slot = handle._cfgTextSlot
        local xKey, yKey = GFPreviewTextOffsetKeys(kind, slot)
        return (kind == "name" and (conf.nameAnchor or "LEFT") or GFPreviewTextLabel(kind, slot)), tonumber(conf[xKey]) or 0, tonumber(conf[yKey]) or 0
    end
    return nil
end

local function GFPreviewUpdateHint(box, handle)
    if not (box and box._hint) then return end
    if not handle then
        box._hint:SetText("click layers to hide - drag custom handles - arrows nudge selected")
        return
    end
    local anchor, x, y = GFPreviewHandleOffsets(handle)
    if anchor then
        box._hint:SetText(string.format("%s   %s   x: %d   y: %d   arrows nudge, Shift=5, Ctrl=10",
            GFPreviewHandleText(handle), tostring(anchor or "CENTER"), GFPreviewRound(x or 0), GFPreviewRound(y or 0)))
    else
        box._hint:SetText(string.format("%s   arrows nudge, Shift=5, Ctrl=10", GFPreviewHandleText(handle)))
    end
end

local function GFPreviewNudgeStep()
    if IsControlKeyDown and IsControlKeyDown() then return 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
    return 1
end

local function GFPreviewRefreshHandleSelection(box)
    if not box then return end
    local selected = box._selectedHandle
    if selected and selected.IsShown and not selected:IsShown() then
        selected = nil
        box._selectedHandle = nil
    end
    local handles = box._handleList or {}
    for i = 1, #handles do
        local handle = handles[i]
        if handle then
            local color = handle._color or { 0.7, 0.8, 1.0 }
            local isSelected = handle == selected
            local isHover = handle._hovering == true
            local isDrag = handle._dragging == true
            if handle._selectFill then
                handle._selectFill:SetColorTexture(color[1], color[2], color[3], isDrag and 0.18 or (isHover and 0.14 or 0))
            end
            if handle._selectBorder then
                handle._selectBorder:SetShown(isSelected or isHover)
                handle._selectBorder:SetBackdropBorderColor(color[1], color[2], color[3], isSelected and 0.70 or 0.72)
            end
            if handle.SetBackdropBorderColor then
                local borderAlpha = isSelected and 0.70 or (isHover and 0.85 or (handle._locked and 0.55 or 0.95))
                if handle._cfgText then borderAlpha = 0 end
                handle:SetBackdropBorderColor(color[1], color[2], color[3], borderAlpha)
            end
            if handle._cfgText and handle.SetBackdropColor then
                handle:SetBackdropColor(0, 0, 0, 0)
            end
        end
    end
    GFPreviewUpdateHint(box, selected)
end

local function CreateNativeGFPreview(parent, ctx, onOpen)
    local width = (ctx.width or 720) - 28
    local box = T.Panel(parent, nil, T.colors.panel2, T.colors.border)
    box:SetSize(width, 300)
    if parent and parent.GetFrameLevel and box.SetFrameLevel then
        box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2)
    end

    local title = T.Font(box, "GameFontNormal", "", T.colors.accent)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    title:SetText("Group Frame Preview - " .. PreviewScopeLabel(CurrentScope()))
    box._title = title
    local hint = T.Font(box, "GameFontDisableSmall", "click layers to hide - drag custom handles - arrows nudge selected", T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    box._hint = hint

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
    local layersTitle = LayerFont(layers, "LAYERS", LAYER_HEADER_COLOR)
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
        btn:SetScript("OnEnter", function(self)
            if self._layerAvailable == false and box._hint then
                box._hint:SetText((self._label and self._label:GetText() or "Layer") .. " is off in settings and cannot be shown in preview.")
            end
            if GameTooltip and self._layerAvailable == false then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Layer disabled", 1, 1, 1)
                GameTooltip:AddLine("Turn this feature on in settings to make the preview layer available.", 0.82, 0.82, 0.82, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
            GFPreviewUpdateHint(box, box._selectedHandle)
        end)
        btn:SetScript("OnClick", function(self)
            local key = self._layerKey
            if self._layerAvailable == false then
                if box._hint then
                    box._hint:SetText((self._label and self._label:GetText() or "Layer") .. " is off in settings and cannot be shown in preview.")
                end
                return
            end
            if key then
                if IsShiftKeyDown and IsShiftKeyDown() then
                    M.gfPreviewSoloLayer = (M.gfPreviewSoloLayer == key) and nil or key
                else
                    M.gfPreviewSoloLayer = nil
                    M.gfPreviewLayerVisible[key] = M.gfPreviewLayerVisible[key] == false
                end
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

    mock._nameTextLayer = CreateFrame("Frame", nil, mock._health)
    mock._nameTextLayer:SetAllPoints(mock._health)
    mock._healthTextLayer = CreateFrame("Frame", nil, mock._health)
    mock._healthTextLayer:SetAllPoints(mock._health)
    mock._powerTextLayer = CreateFrame("Frame", nil, mock)
    mock._powerTextLayer:SetAllPoints(mock)

    mock._nameFS = T.Font(mock._nameTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    mock._hpFS = T.Font(mock._healthTextLayer, "GameFontHighlight", "", T.colors.text)
    mock._powerFS = T.Font(mock._powerTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    mock._hpLeftFS = T.Font(mock._healthTextLayer, "GameFontHighlight", "", T.colors.text)
    mock._hpCenterFS = T.Font(mock._healthTextLayer, "GameFontHighlight", "", T.colors.text)
    mock._hpRightFS = mock._hpFS
    mock._powerLeftFS = T.Font(mock._powerTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    mock._powerCenterFS = mock._powerFS
    mock._powerRightFS = T.Font(mock._powerTextLayer, "GameFontHighlightSmall", "", T.colors.text)

    box._selectedHandle = nil
    box._handles = {}
    box._handleList = {}
    local dragBounds = UIParent or box
    box._dragFrame = CreateFrame("Frame", nil, box)
    box._dragFrame:SetAllPoints(dragBounds)
    box._dragFrame:EnableMouse(true)
    if box._dragFrame.SetFrameStrata then box._dragFrame:SetFrameStrata("TOOLTIP") end
    box._dragFrame:Hide()

    local function SelectHandle(handle)
        box._selectedHandle = handle
        if box.SetFocus then box:SetFocus() end
        if handle and handle._cfgStatus and handle._statusSpec then
            M.gfStatusIconSelection = handle._statusSpec.value
        end
        if handle and handle._cfgTextKind then
            M.gfTextTabSelection = M.gfTextTabSelection or {}
            M.gfTextTabSelection[CurrentScope()] = handle._cfgTextKind
            if handle._cfgTextSlot then
                GFPreviewSetTextMoveTogether(CurrentScope(), handle._cfgTextKind, false)
                M.gfTextSlotSelection = M.gfTextSlotSelection or {}
                M.gfTextSlotSelection[CurrentScope()] = M.gfTextSlotSelection[CurrentScope()] or {}
                M.gfTextSlotSelection[CurrentScope()][handle._cfgTextKind] = handle._cfgTextSlot
            elseif handle._cfgTextKind == "hp" or handle._cfgTextKind == "power" then
                GFPreviewSetTextMoveTogether(CurrentScope(), handle._cfgTextKind, true)
            end
        end
        GFPreviewRefreshHandleSelection(box)
    end

    local function HandleHistoryLabel(handle, action)
        local text = GFPreviewHandleText(handle)
        return tostring(action or "Move") .. ": " .. tostring(text)
    end

    local function CheckpointHandleHistory(handle, action)
        if not (M and type(M.CheckpointHistory) == "function") then return end
        M.CheckpointHistory(
            HandleHistoryLabel(handle, action),
            "groupPreview:" .. tostring(CurrentScope()) .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
        )
    end

    local function RefreshGroupPreviewAfterMove()
        local gf = ns and ns.GF
        if gf and gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_ALL or 0x3F)
        elseif gf and gf.RefreshVisuals then
            gf.RefreshVisuals()
        end
        box:Refresh()
        GFPreviewRefreshHandleSelection(box)
    end

    local function WriteTextHandleOffsets(handle, x, y, action, checkpoint)
        if not handle then return false end
        local conf = Conf(CurrentScope())
        if not conf then return false end
        local kind = handle._cfgTextKind or GFPreviewCurrentTextKind()
        local xKey, yKey = GFPreviewTextOffsetKeys(kind, handle._cfgTextSlot)
        conf[xKey] = GFPreviewRound(x or 0)
        conf[yKey] = GFPreviewRound(y or 0)
        RefreshGroupPreviewAfterMove()
        if checkpoint then CheckpointHandleHistory(handle, action or "Move") end
        return true
    end

    local function SaveHandlePosition(handle, action)
        if not (handle and box._mock) or handle._locked then return end
        if handle._cfgText then return end
        local m = box._mock
        local anchorFrame = (handle._cfgGroup and handle._previewAnchorFrame) or m
        local mL, mT = anchorFrame:GetLeft() or 0, anchorFrame:GetTop() or 0
        local mW, mH = max(1, anchorFrame:GetWidth() or 1), max(1, anchorFrame:GetHeight() or 1)
        local hL, hT = handle:GetLeft() or 0, handle:GetTop() or 0
        local hB = handle:GetBottom() or 0
        local hW, hH = handle:GetWidth() or 1, handle:GetHeight() or 1
        local anchor, offX, offY
        if handle._cfgGroup and handle._previewOriginX and handle._previewOriginY then
            local px = hL + handle._previewOriginX
            local py = hB + handle._previewOriginY
            anchor = GFPreviewResolveAnchor((px - mL) / mW, (mT - py) / mH)
            offX, offY = GFPreviewPointOffset(px, py, anchorFrame, anchor)
        else
            local cx, cy = hL + hW * 0.5, hT - hH * 0.5
            anchor = GFPreviewResolveAnchor((cx - mL) / mW, (mT - cy) / mH)
            offX, offY = GFPreviewHandleOffset(handle, m, anchor)
        end
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
            local spec = handle._statusSpec or GFPreviewCurrentStatusSpec()
            if spec then
                conf[spec.anchor] = anchor
                conf[spec.x] = cfgX
                conf[spec.y] = cfgY
            end
        elseif handle._cfgPrivate then
            conf.privateAuras = conf.privateAuras or {}
            conf.privateAuras.anchor = anchor
            conf.privateAuras.x = cfgX
            conf.privateAuras.y = cfgY
        elseif handle._cfgSpell then
            local placed = GFPreviewCurrentSpellPlaced(CurrentScope())
            local spellCfg = GFPreviewCurrentSpellConfig(CurrentScope())
            if not placed and spellCfg then
                spellCfg.placed = { type = "icon", size = 18 }
                placed = spellCfg.placed
            end
            if placed then
                placed.anchor = anchor
                placed.x = cfgX
                placed.y = cfgY
            end
        end

        RefreshGroupPreviewAfterMove()
        CheckpointHandleHistory(handle, action)
    end

    local function StopHandleDrag(handle, button)
        if button and button ~= "LeftButton" then return end
        handle = handle or (box._dragFrame and box._dragFrame._handle)
        local wasDragging = handle and handle._dragging == true
        if box._dragFrame then
            box._dragFrame:SetScript("OnUpdate", nil)
            box._dragFrame._handle = nil
            box._dragFrame:Hide()
        end
        if handle then
            handle._dragging = nil
            handle._dragPoint = nil
            handle._dragRelTo = nil
            handle._dragRelPoint = nil
            handle._dragStartX = nil
            handle._dragStartY = nil
            handle._dragCfgStartX = nil
            handle._dragCfgStartY = nil
            handle._dragCursorX = nil
            handle._dragCursorY = nil
            handle._dragScale = nil
        end
        if wasDragging and handle and handle._cfgText then
            if handle._lastDragX ~= nil or handle._lastDragY ~= nil then
                CheckpointHandleHistory(handle, "Move")
            else
                GFPreviewRefreshHandleSelection(box)
            end
        elseif wasDragging then
            SaveHandlePosition(handle, "Move")
        else
            GFPreviewRefreshHandleSelection(box)
        end
    end
    box._dragFrame:SetScript("OnMouseUp", function(_, button)
        StopHandleDrag(nil, button)
    end)

    local function UpdateHandleDrag(df)
        local handle = df and df._handle
        if not (handle and handle._dragging) then return end
        local cx, cy = GetCursorPosition()
        if not (cx and cy) then return end
        if handle._cfgText then
            local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if uiScale <= 0 then uiScale = 1 end
            local previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
            if previewScale <= 0 then previewScale = 1 end
            local dx = ((cx - (handle._dragCursorX or cx)) / uiScale) / previewScale
            local dy = ((cy - (handle._dragCursorY or cy)) / uiScale) / previewScale
            local nextX = GFPreviewRound((handle._dragCfgStartX or 0) + dx)
            local nextY = GFPreviewRound((handle._dragCfgStartY or 0) + dy)
            if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
            handle._lastDragX = nextX
            handle._lastDragY = nextY
            WriteTextHandleOffsets(handle, nextX, nextY, "Move", false)
            return
        end
        local scale = handle._dragScale or 1
        if scale <= 0 then scale = 1 end
        local dx = (cx - (handle._dragCursorX or cx)) / scale
        local dy = (cy - (handle._dragCursorY or cy)) / scale
        local nextX = GFPreviewRound((handle._dragStartX or 0) + dx)
        local nextY = GFPreviewRound((handle._dragStartY or 0) + dy)
        if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
        handle._lastDragX = nextX
        handle._lastDragY = nextY
        handle:ClearAllPoints()
        handle:SetPoint(handle._dragPoint or "CENTER", handle._dragRelTo or box._mock, handle._dragRelPoint or "CENTER", nextX, nextY)
        GFPreviewUpdateHint(box, handle)
    end

    local function StartHandleDrag(handle, button)
        if button and button ~= "LeftButton" then return end
        SelectHandle(handle)
        if not handle or handle._locked then return end
        local point, relativeTo, relativePoint, xOfs, yOfs = handle:GetPoint(1)
        local cx, cy = GetCursorPosition()
        if not (point and cx and cy) then return end
        handle._dragging = true
        if handle._cfgText then
            local _, cfgX, cfgY = GFPreviewHandleOffsets(handle)
            handle._dragCfgStartX = tonumber(cfgX) or 0
            handle._dragCfgStartY = tonumber(cfgY) or 0
        end
        handle._dragPoint = point
        handle._dragRelTo = relativeTo or box._mock
        handle._dragRelPoint = relativePoint or point
        handle._dragStartX = xOfs or 0
        handle._dragStartY = yOfs or 0
        handle._dragCursorX = cx
        handle._dragCursorY = cy
        handle._lastDragX = nil
        handle._lastDragY = nil
        local rel = handle._dragRelTo
        handle._dragScale = (rel and rel.GetEffectiveScale and rel:GetEffectiveScale())
            or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
            or 1
        box._dragFrame._handle = handle
        box._dragFrame:SetScript("OnUpdate", UpdateHandleDrag)
        box._dragFrame:Show()
        GFPreviewRefreshHandleSelection(box)
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

        local selectFill = handle:CreateTexture(nil, "OVERLAY", nil, 6)
        selectFill:SetAllPoints()
        selectFill:SetColorTexture(color[1], color[2], color[3], 0)
        handle._selectFill = selectFill

        local selectBorder = CreateFrame("Frame", nil, handle, T.Template())
        selectBorder:SetPoint("TOPLEFT", handle, "TOPLEFT", -2, 2)
        selectBorder:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 2, -2)
        selectBorder:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        selectBorder:SetBackdropColor(0, 0, 0, 0)
        selectBorder:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        selectBorder:Hide()
        handle._selectBorder = selectBorder

        local fs = T.Font(handle, "GameFontDisableSmall", label or key, { color[1], color[2], color[3], 0.95 })
        fs:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        fs:SetJustifyH("CENTER")
        handle._label = fs

        handle:SetScript("OnEnter", function(self)
            self._hovering = true
            GFPreviewRefreshHandleSelection(box)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(GFPreviewHandleText(self), 1, 1, 1)
                if self._locked then
                    GameTooltip:AddLine("This preview layer follows Blizzard/native placement and is locked.", 0.82, 0.82, 0.82, true)
                else
                    GameTooltip:AddLine("Drag this preview element to adjust the same placement offsets used by Group Frames.", 0.82, 0.82, 0.82, true)
                    GameTooltip:AddLine("Arrow keys nudge the selected element. Shift = 5, Ctrl = 10.", 0.55, 0.62, 0.72, true)
                end
                GameTooltip:Show()
            end
        end)
        handle:SetScript("OnLeave", function(self)
            self._hovering = nil
            GFPreviewRefreshHandleSelection(box)
            if GameTooltip then GameTooltip:Hide() end
        end)
        handle:SetScript("OnClick", function(self)
            SelectHandle(self)
        end)
        handle:SetScript("OnMouseDown", StartHandleDrag)
        handle:SetScript("OnMouseUp", StopHandleDrag)
        handle:HookScript("OnHide", function(self)
            StopHandleDrag(self)
            if box._selectedHandle == self then SelectHandle(nil) end
        end)
        box._handles[key] = handle
        box._handleList[#box._handleList + 1] = handle
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

    local statusHandles = {}
    local statusSpecs = GFPreviewStatusSpecs()
    for i = 1, #statusSpecs do
        local spec = statusSpecs[i]
        local statusHandle = CreatePreviewHandle("status_" .. tostring(spec.value or i), "sicons", { 0.80, 0.67, 0.20 }, GFPreviewStatusLabel(spec), 78, 28, false)
        statusHandle._cfgStatus = true
        statusHandle._statusSpec = spec
        statusHandle._statusTex = statusHandle:CreateTexture(nil, "ARTWORK")
        statusHandle._statusTex:SetPoint("TOPLEFT", statusHandle, "TOPLEFT", 0, 0)
        statusHandle._statusTex:SetPoint("BOTTOMRIGHT", statusHandle, "BOTTOMRIGHT", 0, 0)
        statusHandle._statusTex:Hide()
        statusHandle._statusText = T.Font(statusHandle, "GameFontHighlightLarge", "DEAD", { 1, 1, 1, 1 })
        statusHandle._statusText:SetPoint("CENTER")
        statusHandles[#statusHandles + 1] = statusHandle
    end

    local spellHandle = CreatePreviewHandle("si", "si", { 0.69, 0.50, 0.88 }, "SPELL", 44, 44, false)
    spellHandle._cfgSpell = true
    AddIconPool(spellHandle, 1)

    local privateHandle = CreatePreviewHandle("private", "priv", { 0.50, 0.50, 0.55 }, "PRIVATE", 48, 24, false)
    privateHandle._cfgPrivate = true
    AddIconPool(privateHandle, 3)

    local function ConfigureTextHandle(handle, kind, slot)
        if not handle then return end
        handle._cfgText = true
        handle._cfgTextKind = kind
        handle._cfgTextSlot = slot
        handle._previewText = GFPreviewTextLabel(kind, slot)
        if handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
        if handle.SetBackdropBorderColor then
            local color = handle._color or { 0.55, 0.78, 0.95 }
            handle:SetBackdropBorderColor(color[1], color[2], color[3], 0)
        end
        if handle._label then handle._label:Hide() end
    end

    local nameTextHandle = CreatePreviewHandle("nameText", "text", { 0.30, 0.66, 1.00 }, "NAME", 74, 18, false)
    ConfigureTextHandle(nameTextHandle, "name")
    local hpTextHandle = CreatePreviewHandle("hpText", "text", { 0.25, 0.90, 0.42 }, "HP", 74, 18, false)
    ConfigureTextHandle(hpTextHandle, "hp")
    local hpLeftTextHandle = CreatePreviewHandle("hpTextLeft", "text", { 0.25, 0.90, 0.42 }, "HP L", 74, 18, false)
    ConfigureTextHandle(hpLeftTextHandle, "hp", "left")
    local hpCenterTextHandle = CreatePreviewHandle("hpTextCenter", "text", { 0.25, 0.90, 0.42 }, "HP C", 74, 18, false)
    ConfigureTextHandle(hpCenterTextHandle, "hp", "center")
    local hpRightTextHandle = CreatePreviewHandle("hpTextRight", "text", { 0.25, 0.90, 0.42 }, "HP R", 74, 18, false)
    ConfigureTextHandle(hpRightTextHandle, "hp", "right")
    local powerTextHandle = CreatePreviewHandle("powerText", "text", { 0.95, 0.72, 0.18 }, "POWER", 74, 18, false)
    ConfigureTextHandle(powerTextHandle, "power")
    local powerLeftTextHandle = CreatePreviewHandle("powerTextLeft", "text", { 0.95, 0.72, 0.18 }, "PWR L", 74, 18, false)
    ConfigureTextHandle(powerLeftTextHandle, "power", "left")
    local powerCenterTextHandle = CreatePreviewHandle("powerTextCenter", "text", { 0.95, 0.72, 0.18 }, "PWR C", 74, 18, false)
    ConfigureTextHandle(powerCenterTextHandle, "power", "center")
    local powerRightTextHandle = CreatePreviewHandle("powerTextRight", "text", { 0.95, 0.72, 0.18 }, "PWR R", 74, 18, false)
    ConfigureTextHandle(powerRightTextHandle, "power", "right")
    box._textHandles = {
        name = nameTextHandle,
        hpGroup = hpTextHandle,
        hpLeft = hpLeftTextHandle,
        hpCenter = hpCenterTextHandle,
        hpRight = hpRightTextHandle,
        powerGroup = powerTextHandle,
        powerLeft = powerLeftTextHandle,
        powerCenter = powerCenterTextHandle,
        powerRight = powerRightTextHandle,
    }

    local footer = T.Font(box, "GameFontDisableSmall", "Click a handle to select - drag custom layers - arrow keys nudge selected; Blizzard is locked", T.colors.muted)
    footer:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)

    function box:Refresh()
        local textHandles = self._textHandles or {}
        local kind = CurrentScope()
        local label = PreviewScopeLabel(kind)
        local conf = Conf(kind)
        local gf = ns and ns.GF
        local focus = PreviewFocusForPage(ctx.key)
        local layerVisible = M.gfPreviewLayerVisible or {}
        local soloLayer = M.gfPreviewSoloLayer
        local auras = conf.auras or {}
        local buffCfg = auras.buff or {}
        local debuffCfg = auras.debuff or {}
        local extCfg = auras.externals or {}
        local pa = conf.privateAuras or {}
        local statusSpec = GFPreviewCurrentStatusSpec()
        local selectedSpellCfg = GFPreviewCurrentSpellConfig(kind)
        local selectedPlaced = GFPreviewCurrentSpellPlaced(kind)
        local selectedSpellPlacedEnabled = selectedPlaced and (selectedPlaced.type or "icon") ~= "none"
        local statusLayerAvailable = false
        for i = 1, #statusSpecs do
            local spec = statusSpecs[i]
            if GFPreviewStatusSpecInMode(spec, statusSpec) then
                statusLayerAvailable = true
                break
            end
        end
        local aurasEnabled = auras.enabled ~= false
        local customRenderer = (auras.renderer or conf.auraRenderer or "BLIZZARD") == "CUSTOM"
        local powerTextEnabled = (gf and gf.IsPowerTextEnabled and gf.IsPowerTextEnabled(kind, conf)) or (conf.showPowerText == true or conf.showPower == true)
        local layerAvailable = {
            buff = aurasEnabled and customRenderer and buffCfg.enabled ~= false and (tonumber(buffCfg.max) or 6) > 0,
            debuff = aurasEnabled and customRenderer and debuffCfg.enabled ~= false and (tonumber(debuffCfg.max) or 6) > 0,
            externals = aurasEnabled and customRenderer and extCfg.enabled ~= false and (tonumber(extCfg.max) or 2) > 0,
            blizzard = aurasEnabled and not customRenderer,
            status = statusLayerAvailable,
            si = (conf.spellIndicators and conf.spellIndicators.enabled ~= false and selectedSpellPlacedEnabled) and true or false,
            private = pa.enabled ~= false,
            auraText = aurasEnabled and ((customRenderer and (
                (buffCfg.enabled ~= false and (tonumber(buffCfg.max) or 6) > 0)
                or (debuffCfg.enabled ~= false and (tonumber(debuffCfg.max) or 6) > 0)
                or (extCfg.enabled ~= false and (tonumber(extCfg.max) or 2) > 0)
            )) or ((not customRenderer) and auras.blizzardShowCooldownText ~= false)),
            text = conf.showName ~= false or conf.showHPText ~= false or powerTextEnabled,
        }
        self._layerAvailable = layerAvailable
        if soloLayer and layerAvailable[soloLayer] == false then
            M.gfPreviewSoloLayer = nil
            soloLayer = nil
        end
        local function LayerOn(key)
            return layerAvailable[key] ~= false and layerVisible[key] ~= false
        end
        local function LayerAlpha(key)
            if layerAvailable[key] == false then return 0 end
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
        local cls = GF_PREVIEW_CLASSES[((kind == "party" and 5 or 2) % #GF_PREVIEW_CLASSES) + 1]
        local hr, hg, hb = PreviewHealthColor(conf, 0.72, cls)
        mock._health:SetStatusBarColor(hr, hg, hb, tonumber(conf.hpBarAlpha) or 1)
        mock._healthBg:SetTexture(bgTex)
        local hbr, hbg, hbb = conf.bgR or 0.06, conf.bgG or 0.06, conf.bgB or 0.07
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        if gen and gen.barBgClassColor then
            hbr, hbg, hbb = PreviewClassColor(cls, hbr, hbg, hbb)
        end
        mock._healthBg:SetVertexColor(hbr, hbg, hbb, conf.hpBgAlpha or conf.bgA or 0.85)

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

        local textBaseLevel = (mock.GetFrameLevel and mock:GetFrameLevel()) or 1
        if mock._nameTextLayer then
            mock._nameTextLayer:ClearAllPoints()
            mock._nameTextLayer:SetAllPoints(mock._health)
            mock._nameTextLayer:SetFrameLevel(textBaseLevel + (tonumber(conf.nameTextLayer) or 5))
        end
        if mock._healthTextLayer then
            mock._healthTextLayer:ClearAllPoints()
            mock._healthTextLayer:SetAllPoints(mock._health)
            mock._healthTextLayer:SetFrameLevel(textBaseLevel + (tonumber(conf.textLayer) or 5))
        end
        if mock._powerTextLayer then
            mock._powerTextLayer:ClearAllPoints()
            mock._powerTextLayer:SetAllPoints(mock)
            mock._powerTextLayer:SetFrameLevel(textBaseLevel + (tonumber(conf.powerTextLayer) or 2))
        end

        local showText = LayerOn("text") and (focus == "text" or focus == "overlay" or soloLayer == "text")
        local fontPath = (gf and gf.ResolveFontPath and gf.ResolveFontPath(kind)) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        local fontFlags = (gf and gf.ResolveFontFlags and gf.ResolveFontFlags(kind)) or "OUTLINE"
        local db = _G.MSUF_DB
        local fontKey = db and db.general and db.general.fontKey
        local safeSetFont = _G.MSUF_SetFontSafe
        local function SetPreviewFont(fs, size)
            if not fs then return end
            if type(safeSetFont) == "function" then
                safeSetFont(fs, fontPath, size, fontFlags, fontKey)
            else
                fs:SetFont(fontPath, size, fontFlags)
            end
        end
        local fr, fg, fb = T.colors.text[1], T.colors.text[2], T.colors.text[3]
        if gf and gf.ResolveFontColor then fr, fg, fb = gf.ResolveFontColor(kind) end
        SetPreviewFont(mock._nameFS, max(6, GFPreviewScaleValue(conf.nameFontSize or 12, previewScale, 6)))
        local previewName = GF_PREVIEW_NAMES[5]
        if gf and gf.ResolveNameTruncation and gf.TruncateName then
            local maxC, noEllipsis, clipSide = gf.ResolveNameTruncation(kind)
            if maxC and maxC > 0 then
                previewName = gf.TruncateName(previewName, maxC, noEllipsis, clipSide)
            end
        end
        mock._nameFS:SetText(previewName)
        mock._nameFS:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
        mock._nameFS:ClearAllPoints()
        local pad3 = GFPreviewScaleValue(3, previewScale, 1)
        local pad2 = GFPreviewScaleValue(2, previewScale, 1)
        local nox = GFPreviewConfigToOffset(conf.nameOffsetX or 0, previewScale)
        local noy = GFPreviewConfigToOffset(conf.nameOffsetY or 0, previewScale)
        local nameAnchor = conf.nameAnchor or "LEFT"
        if nameAnchor == "CENTER" then
            mock._nameFS:SetPoint("LEFT", mock._health, "LEFT", pad3 + nox, noy)
            mock._nameFS:SetPoint("RIGHT", mock._health, "RIGHT", -pad3 + nox, noy)
            mock._nameFS:SetJustifyH("CENTER")
            mock._nameFS._msufPreviewJustifyH = "CENTER"
        elseif nameAnchor == "RIGHT" then
            mock._nameFS:SetPoint("LEFT", mock._health, "LEFT", pad3 + nox, noy)
            mock._nameFS:SetPoint("RIGHT", mock._health, "RIGHT", -pad3 + nox, noy)
            mock._nameFS:SetJustifyH("RIGHT")
            mock._nameFS._msufPreviewJustifyH = "RIGHT"
        else
            mock._nameFS:SetPoint("LEFT", mock._health, "LEFT", pad3 + nox, noy)
            mock._nameFS:SetPoint("RIGHT", mock._health, "RIGHT", -pad3, noy)
            mock._nameFS:SetJustifyH("LEFT")
            mock._nameFS._msufPreviewJustifyH = "LEFT"
        end
        if mock._nameFS.SetWordWrap then mock._nameFS:SetWordWrap(false) end
        mock._nameFS:SetShown(showText and conf.showName ~= false)

        local hpSize = max(7, GFPreviewScaleValue(conf.hpFontSize or 10, previewScale, 6))
        local hox = GFPreviewConfigToOffset(conf.hpOffsetX or 0, previewScale)
        local hoy = GFPreviewConfigToOffset(conf.hpOffsetY or 0, previewScale)
        local hpTextOn = showText and conf.showHPText ~= false
        local hpModes = {
            { fs = mock._hpLeftFS, mode = conf.textLeft or "NONE", point = "LEFT", rel = "LEFT", x = pad3 + hox + GFPreviewConfigToOffset(conf.hpTextLeftOffsetX or 0, previewScale), y = hoy + GFPreviewConfigToOffset(conf.hpTextLeftOffsetY or 0, previewScale), justify = "LEFT" },
            { fs = mock._hpCenterFS, mode = conf.textCenter or "NONE", point = "CENTER", rel = "CENTER", x = hox + GFPreviewConfigToOffset(conf.hpTextCenterOffsetX or 0, previewScale), y = hoy + GFPreviewConfigToOffset(conf.hpTextCenterOffsetY or 0, previewScale), justify = "CENTER" },
            { fs = mock._hpRightFS, mode = conf.textRight or "NONE", point = "RIGHT", rel = "RIGHT", x = -pad3 + hox + GFPreviewConfigToOffset(conf.hpTextRightOffsetX or 0, previewScale), y = hoy + GFPreviewConfigToOffset(conf.hpTextRightOffsetY or 0, previewScale), justify = "RIGHT" },
        }
        local fakeHP, fakeMax = 720000, 1000000
        for i = 1, #hpModes do
            local spec = hpModes[i]
            local fs = spec.fs
            SetPreviewFont(fs, hpSize)
            fs:SetTextColor(fr or 1, fg or 1, fb or 1, 0.9)
            fs:ClearAllPoints()
            fs:SetPoint(spec.point, mock._health, spec.rel, spec.x, spec.y)
            fs:SetJustifyH(spec.justify)
            fs._msufPreviewJustifyH = spec.justify
            if gf and gf.FormatHealthText then
                fs:SetText(gf.FormatHealthText(spec.mode, fakeHP, fakeMax, conf.textDelimiter or " - ", conf.hpTextReverse == true))
            else
                fs:SetText(spec.mode == "PERCENT" and "72%" or "720k")
            end
            fs:SetShown(hpTextOn and spec.mode ~= "NONE")
        end

        local pwrSize = max(6, GFPreviewScaleValue(conf.powerFontSize or 9, previewScale, 6))
        local pox = GFPreviewConfigToOffset(conf.powerOffsetX or 0, previewScale)
        local poy = GFPreviewConfigToOffset(conf.powerOffsetY or 0, previewScale)
        local powerTextAnchor = (powerH > 0 and mock._power) or mock._health
        local showPowerText = showText
        if gf and gf.IsPowerTextEnabled then showPowerText = showText and gf.IsPowerTextEnabled(kind, conf) end
        local powerModes = {
            { fs = mock._powerLeftFS, mode = conf.powerTextLeft or "NONE", point = "LEFT", rel = "LEFT", x = pad2 + pox + GFPreviewConfigToOffset(conf.powerTextLeftOffsetX or 0, previewScale), y = poy + GFPreviewConfigToOffset(conf.powerTextLeftOffsetY or 0, previewScale), justify = "LEFT" },
            { fs = mock._powerCenterFS, mode = conf.powerTextCenter or "NONE", point = "CENTER", rel = "CENTER", x = pox + GFPreviewConfigToOffset(conf.powerTextCenterOffsetX or 0, previewScale), y = poy + GFPreviewConfigToOffset(conf.powerTextCenterOffsetY or 0, previewScale), justify = "CENTER" },
            { fs = mock._powerRightFS, mode = conf.powerTextRight or "NONE", point = "RIGHT", rel = "RIGHT", x = -pad2 + pox + GFPreviewConfigToOffset(conf.powerTextRightOffsetX or 0, previewScale), y = poy + GFPreviewConfigToOffset(conf.powerTextRightOffsetY or 0, previewScale), justify = "RIGHT" },
        }
        local fakePow, fakePowMax = 70, 100
        for i = 1, #powerModes do
            local spec = powerModes[i]
            local fs = spec.fs
            SetPreviewFont(fs, pwrSize)
            fs:SetTextColor(fr or 1, fg or 1, fb or 1, 0.9)
            fs:ClearAllPoints()
            fs:SetPoint(spec.point, powerTextAnchor, spec.rel, spec.x, spec.y)
            fs:SetJustifyH(spec.justify)
            fs._msufPreviewJustifyH = spec.justify
            if gf and gf.FormatPowerText then
                fs:SetText(gf.FormatPowerText(spec.mode, fakePow, fakePowMax, conf.powerTextDelimiter or conf.textDelimiter or " - "))
            else
                fs:SetText(spec.mode == "PERCENT" and "70%" or "70")
            end
            fs:SetShown(showPowerText and spec.mode ~= "NONE")
        end

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

        local auraDynamicScale = (gf and gf.GetPreviewDynamicScale and gf.GetPreviewDynamicScale(conf, kind)) or 1
        local function LayoutAuraGroup(handle, groupKey, cfg, defaults)
            cfg = cfg or {}
            defaults = defaults or {}
            local maxIcons = GFPreviewInt(cfg.max, defaults.max or 6, 0, 40)
            local perRow = GFPreviewInt(cfg.perRow, defaults.perRow or maxIcons, 1, 40)
            local rawSize = cfg.size or defaults.size or 16
            local minSize = defaults.minSize or 8
            local size = max(minSize, GFPreviewScaleValue(rawSize, previewScale * auraDynamicScale, minSize))
            local spacing = max(0, GFPreviewScaleValue(cfg.spacing or defaults.spacing or 1, previewScale, 0))
            local anchor = cfg.anchor or defaults.anchor or "CENTER"
            if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaults.anchor or "CENTER" end
            if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = "CENTER" end
            local growth = cfg.growth or defaults.growth or "RIGHTDOWN"
            local gv = GFPreviewAuraGrowth(growth)
            local effectiveAnchor = gv.centered and "CENTER" or anchor
            local anchorTarget = (cfg.behindBar and mock._health) or mock
            local anchorFrac = GF_PREVIEW_ANCHOR_FRAC[anchor] or GF_PREVIEW_ANCHOR_FRAC.CENTER
            local ids = GF_AURA_MOCK_ICON_IDS[groupKey] or GF_AURA_MOCK_ICON_IDS.debuff
            local step = size + spacing

            AddIconPool(handle, maxIcons)
            handle._previewRects = handle._previewRects or {}

            local minL, minB, maxR, maxT
            for i = 1, maxIcons do
                local left, bottom
                if gv.centered then
                    local totalPrimary = maxIcons * size + max(0, maxIcons - 1) * spacing
                    local halfOfs = totalPrimary * 0.5
                    local col = i - 1
                    if gv.px ~= 0 then
                        local cx = col * step - halfOfs + size * 0.5
                        left, bottom = cx - size * 0.5, -size * 0.5
                    else
                        local cy = -(col * step - halfOfs) - size * 0.5
                        left, bottom = -size * 0.5, cy - size * 0.5
                    end
                else
                    local col = (i - 1) % perRow
                    local row = floor((i - 1) / perRow)
                    local ox = col * step * gv.px + row * step * gv.sx
                    local oy = col * step * gv.py + row * step * gv.sy
                    left = ox - anchorFrac[1] * size
                    bottom = oy - anchorFrac[2] * size
                end

                local right, top = left + size, bottom + size
                local rect = handle._previewRects[i] or {}
                rect[1], rect[2] = left, bottom
                handle._previewRects[i] = rect
                minL = minL and min(minL, left) or left
                minB = minB and min(minB, bottom) or bottom
                maxR = maxR and max(maxR, right) or right
                maxT = maxT and max(maxT, top) or top
            end

            if not minL then
                minL, minB, maxR, maxT = -size * 0.5, -size * 0.5, size * 0.5, size * 0.5
            end

            local handleW = max(1, GFPreviewRound(maxR - minL))
            local handleH = max(1, GFPreviewRound(maxT - minB))
            local originX, originY = -minL, -minB
            handle:SetSize(handleW, handleH)
            handle._previewOriginX = originX
            handle._previewOriginY = originY
            handle._previewAnchorFrame = anchorTarget
            handle._previewScale = previewScale
            handle:ClearAllPoints()
            handle:SetPoint(
                "BOTTOMLEFT",
                anchorTarget,
                effectiveAnchor,
                GFPreviewConfigToOffset(cfg.x or 0, previewScale) - originX,
                GFPreviewConfigToOffset(cfg.y or 0, previewScale) - originY
            )

            for i = 1, maxIcons do
                local tex = handle._icons and handle._icons[i]
                local rect = handle._previewRects[i]
                if tex and rect then
                    tex:SetTexture(GFMockSpellTexture(ids[((i - 1) % #ids) + 1]))
                    tex:SetSize(size, size)
                    tex:ClearAllPoints()
                    tex:SetPoint("BOTTOMLEFT", handle, "BOTTOMLEFT", rect[1] - minL, rect[2] - minB)
                    tex:Show()
                end
            end
            for i = maxIcons + 1, #(handle._icons or {}) do
                if handle._icons[i] then handle._icons[i]:Hide() end
            end

            return size
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

        LayoutAuraGroup(buffHandle, "buff", buffCfg, {
            anchor = "BOTTOMRIGHT", growth = "LEFTUP",
            size = 22, perRow = 4, max = 6, spacing = 1, minSize = 8,
        })
        LayoutAuraGroup(debuffHandle, "debuff", debuffCfg, {
            anchor = "TOPLEFT", growth = "RIGHTDOWN",
            size = 20, perRow = 3, max = 6, spacing = 1, minSize = 8,
        })
        LayoutAuraGroup(externHandle, "externals", extCfg, {
            anchor = "CENTER", growth = "RIGHTDOWN",
            size = 28, perRow = 3, max = 2, spacing = 1, minSize = 8,
        })

        local blizzSize = max(14, GFPreviewScaleValue(20, previewScale, 8))
        blizzHandle:SetSize(blizzSize * 5, blizzSize * 2)
        LayoutBlizzardAuraBlock(blizzHandle, blizzSize)
        LayoutHandle(blizzHandle, "CENTER", 0, 0, "CENTER")

        local function ConfigureStatusHandle(statusHandle)
            local spec = statusHandle and statusHandle._statusSpec
            if not (statusHandle and spec) then return end
            local enabled = GFPreviewStatusSpecEnabled(conf, spec)
            local statusIsText = GFPreviewStatusSpecIsText(spec)
            local statusRawSize = tonumber(conf[spec.size]) or tonumber(spec.defaultSize) or 14
            local statusSize = GFPreviewScaleValue(statusRawSize, previewScale, statusIsText and 10 or 8)
            statusHandle._previewText = spec.text or "Status"
            if statusHandle._label and statusHandle._label.SetText then
                statusHandle._label:SetText(GFPreviewStatusLabel(spec))
                statusHandle._label:SetTextColor(0.80, 0.67, 0.20, enabled and 0.95 or 0.55)
            end
            if statusIsText then
                statusHandle:SetSize(max(42, statusSize * 4), max(18, statusSize + 8))
                if statusHandle._statusText and statusHandle._statusText.SetFont then
                    SetPreviewFont(statusHandle._statusText, max(12, statusSize))
                end
                if statusHandle._statusText then
                    statusHandle._statusText:SetText(GFPreviewStatusText(spec))
                    statusHandle._statusText:SetTextColor(enabled and 1 or 0.45, enabled and 1 or 0.45, enabled and 1 or 0.50, enabled and 1 or 0.60)
                    statusHandle._statusText:ClearAllPoints()
                    statusHandle._statusText:SetPoint("CENTER", statusHandle, "CENTER", 0, 0)
                    statusHandle._statusText:Show()
                end
                if statusHandle._statusTex then statusHandle._statusTex:Hide() end
            else
                statusSize = max(8, statusSize)
                statusHandle:SetSize(statusSize, statusSize)
                if statusHandle._statusText then statusHandle._statusText:Hide() end
                local tex = statusHandle._statusTex
                if tex then
                    local path, l, r, t, b = nil, 0, 1, 0, 1
                    local value = spec.value
                    if value == "roleIcon" and gf and gf.GetRoleTexture then
                        path, l, r, t, b = gf.GetRoleTexture(kind, GF_PREVIEW_ROLE)
                    elseif value == "leaderIcon" and gf and gf.GetLeaderTexture then
                        path, l, r, t, b = gf.GetLeaderTexture(kind)
                    elseif value == "assistIcon" and gf and gf.GetAssistTexture then
                        path, l, r, t, b = gf.GetAssistTexture(kind)
                    elseif value == "raidMarker" then
                        path = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
                        l, r, t, b = 0, 0.25, 0, 0.25
                    elseif value == "readyCheckIcon" then
                        path = "Interface\\RaidFrame\\ReadyCheck-Ready"
                    elseif value == "summonIcon" then
                        path = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
                    elseif value == "resurrectIcon" then
                        path = "Interface\\RaidFrame\\Raid-Icon-Rez"
                    elseif value == "phaseIcon" then
                        path = "Interface\\TargetingFrame\\UI-PhasingIcon"
                    end
                    if path then
                        tex:SetTexture(path)
                        tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                        if enabled then
                            tex:SetVertexColor(1, 1, 1, 1)
                        else
                            tex:SetVertexColor(0.40, 0.40, 0.45, 0.55)
                        end
                        tex:ClearAllPoints()
                        tex:SetPoint("TOPLEFT", statusHandle, "TOPLEFT", 0, 0)
                        tex:SetPoint("BOTTOMRIGHT", statusHandle, "BOTTOMRIGHT", 0, 0)
                        tex:Show()
                    else
                        tex:Hide()
                    end
                end
            end
            LayoutHandle(statusHandle, conf[spec.anchor], conf[spec.x], conf[spec.y], spec.defaultAnchor or "CENTER")
        end

        for i = 1, #statusHandles do
            ConfigureStatusHandle(statusHandles[i])
        end

        local selectedSpellIcon = GFPreviewCurrentSpellTexture(kind)
        local spellType = (selectedPlaced and selectedPlaced.type) or "icon"
        local spellBaseSize = tonumber(selectedPlaced and selectedPlaced.size) or 20
        local spellSize = max(14, GFPreviewScaleValue(spellBaseSize, previewScale, 10))
        local spellR, spellG, spellB = GFPreviewCurrentSpellColor(kind)
        spellHandle._icons = spellHandle._icons or {}
        local spellTex = spellHandle._icons[1]
        if spellType == "bar" then
            local barW = max(spellSize * 2, GFPreviewScaleValue((selectedPlaced and selectedPlaced.barWidth) or (spellBaseSize * 3), previewScale, 16))
            spellHandle:SetSize(barW, spellSize)
            if spellTex then
                spellTex:SetTexture(WHITE8X8)
                spellTex:SetTexCoord(0, 1, 0, 1)
                spellTex:SetVertexColor(spellR, spellG, spellB, 1)
                spellTex:ClearAllPoints()
                spellTex:SetAllPoints(spellHandle)
                spellTex:Show()
            end
        elseif spellType == "square" then
            spellHandle:SetSize(spellSize, spellSize)
            if spellTex then
                spellTex:SetTexture(WHITE8X8)
                spellTex:SetTexCoord(0, 1, 0, 1)
                spellTex:SetVertexColor(spellR, spellG, spellB, 1)
                spellTex:ClearAllPoints()
                spellTex:SetAllPoints(spellHandle)
                spellTex:Show()
            end
        elseif spellType == "number" then
            spellHandle:SetSize(max(18, spellSize), max(18, spellSize))
            if spellTex then
                spellTex:Hide()
            end
            if spellHandle._label and spellHandle._label.SetText then
                spellHandle._label:SetText("9")
            end
        else
            spellHandle:SetSize(spellSize, spellSize)
            if spellTex then
                spellTex:SetTexture(selectedSpellIcon)
                spellTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                spellTex:SetVertexColor(1, 1, 1, 1)
                spellTex:ClearAllPoints()
                spellTex:SetAllPoints(spellHandle)
                spellTex:Show()
            end
        end
        if spellType ~= "number" and spellHandle._label and spellHandle._label.SetText then
            spellHandle._label:SetText("SPELL")
        end
        LayoutHandle(spellHandle, selectedPlaced and selectedPlaced.anchor, selectedPlaced and selectedPlaced.x, selectedPlaced and selectedPlaced.y, "TOPLEFT")

        local privateSize = max(12, GFPreviewScaleValue((conf.privateAuras and conf.privateAuras.size) or 16, previewScale, 8))
        privateHandle:SetSize(privateSize * 3, privateSize)
        LayoutIconRow(privateHandle, "private", 3, privateSize, 3)
        LayoutHandle(privateHandle, pa.anchor, pa.x, pa.y, "TOPRIGHT")

        textHandles.name._previewScale = previewScale
        textHandles.hpGroup._previewScale = previewScale
        textHandles.hpLeft._previewScale = previewScale
        textHandles.hpCenter._previewScale = previewScale
        textHandles.hpRight._previewScale = previewScale
        textHandles.powerGroup._previewScale = previewScale
        textHandles.powerLeft._previewScale = previewScale
        textHandles.powerCenter._previewScale = previewScale
        textHandles.powerRight._previewScale = previewScale
        if not GFPreviewPlaceHandleAroundRegions(textHandles.name, mock, { mock._nameFS }, 3) then
            textHandles.name:Hide()
        end
        if GFPreviewTextMovesTogether(kind, "hp") then
            textHandles.hpLeft:Hide()
            textHandles.hpCenter:Hide()
            textHandles.hpRight:Hide()
            if not GFPreviewPlaceHandleAroundRegions(textHandles.hpGroup, mock, { mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS }, 3) then
                textHandles.hpGroup:Hide()
            end
        else
            textHandles.hpGroup:Hide()
            if not GFPreviewPlaceHandleAroundRegions(textHandles.hpLeft, mock, { mock._hpLeftFS }, 3) then textHandles.hpLeft:Hide() end
            if not GFPreviewPlaceHandleAroundRegions(textHandles.hpCenter, mock, { mock._hpCenterFS }, 3) then textHandles.hpCenter:Hide() end
            if not GFPreviewPlaceHandleAroundRegions(textHandles.hpRight, mock, { mock._hpRightFS }, 3) then textHandles.hpRight:Hide() end
        end
        if GFPreviewTextMovesTogether(kind, "power") then
            textHandles.powerLeft:Hide()
            textHandles.powerCenter:Hide()
            textHandles.powerRight:Hide()
            if not GFPreviewPlaceHandleAroundRegions(textHandles.powerGroup, mock, { mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS }, 3) then
                textHandles.powerGroup:Hide()
            end
        else
            textHandles.powerGroup:Hide()
            if not GFPreviewPlaceHandleAroundRegions(textHandles.powerLeft, mock, { mock._powerLeftFS }, 3) then textHandles.powerLeft:Hide() end
            if not GFPreviewPlaceHandleAroundRegions(textHandles.powerCenter, mock, { mock._powerCenterFS }, 3) then textHandles.powerCenter:Hide() end
            if not GFPreviewPlaceHandleAroundRegions(textHandles.powerRight, mock, { mock._powerRightFS }, 3) then textHandles.powerRight:Hide() end
        end

        local baseLevel = mock.GetFrameLevel and mock:GetFrameLevel() or 1
        buffHandle:SetFrameLevel(baseLevel + (tonumber(buffCfg.layer) or 5))
        debuffHandle:SetFrameLevel(baseLevel + (tonumber(debuffCfg.layer) or 6))
        externHandle:SetFrameLevel(baseLevel + (tonumber(extCfg.layer) or 7))
        blizzHandle:SetFrameLevel(baseLevel + 4)
        for i = 1, #statusHandles do
            local handle = statusHandles[i]
            local spec = handle and handle._statusSpec
            if handle then
                handle:SetFrameLevel(baseLevel + (tonumber(spec and conf[spec.layer]) or tonumber(spec and spec.defaultLayer) or 7))
            end
        end
        spellHandle:SetFrameLevel(baseLevel + 6)
        privateHandle:SetFrameLevel(baseLevel + 6)
        textHandles.name:SetFrameLevel(baseLevel + (tonumber(conf.nameTextLayer) or 6))
        textHandles.hpGroup:SetFrameLevel(baseLevel + (tonumber(conf.textLayer) or 6))
        textHandles.hpLeft:SetFrameLevel(baseLevel + (tonumber(conf.textLayer) or 6))
        textHandles.hpCenter:SetFrameLevel(baseLevel + (tonumber(conf.textLayer) or 6))
        textHandles.hpRight:SetFrameLevel(baseLevel + (tonumber(conf.textLayer) or 6))
        textHandles.powerGroup:SetFrameLevel(baseLevel + (tonumber(conf.powerTextLayer) or 6))
        textHandles.powerLeft:SetFrameLevel(baseLevel + (tonumber(conf.powerTextLayer) or 6))
        textHandles.powerCenter:SetFrameLevel(baseLevel + (tonumber(conf.powerTextLayer) or 6))
        textHandles.powerRight:SetFrameLevel(baseLevel + (tonumber(conf.powerTextLayer) or 6))

        buffHandle:SetShown(aurasEnabled and customRenderer and LayerOn("buff"))
        debuffHandle:SetShown(aurasEnabled and customRenderer and LayerOn("debuff"))
        externHandle:SetShown(aurasEnabled and customRenderer and LayerOn("externals"))
        blizzHandle:SetShown(aurasEnabled and not customRenderer and LayerOn("blizzard"))
        for i = 1, #statusHandles do
            local handle = statusHandles[i]
            local spec = handle and handle._statusSpec
            if handle then
                handle:SetShown(GFPreviewStatusSpecInMode(spec, statusSpec) and LayerOn("status"))
            end
        end
        spellHandle:SetShown((conf.spellIndicators and conf.spellIndicators.enabled ~= false and selectedSpellPlacedEnabled) and LayerOn("si"))
        privateHandle:SetShown(pa.enabled ~= false and LayerOn("private"))

        buffHandle:SetAlpha(LayerAlpha("buff"))
        debuffHandle:SetAlpha(LayerAlpha("debuff"))
        externHandle:SetAlpha(LayerAlpha("externals"))
        blizzHandle:SetAlpha(LayerAlpha("blizzard"))
        for i = 1, #statusHandles do
            if statusHandles[i] then statusHandles[i]:SetAlpha(LayerAlpha("status")) end
        end
        spellHandle:SetAlpha((selectedSpellCfg and selectedSpellCfg.enabled == false) and (LayerAlpha("si") * 0.45) or LayerAlpha("si"))
        privateHandle:SetAlpha(LayerAlpha("private"))
        textHandles.name:SetAlpha(LayerAlpha("text"))
        textHandles.hpGroup:SetAlpha(LayerAlpha("text"))
        textHandles.hpLeft:SetAlpha(LayerAlpha("text"))
        textHandles.hpCenter:SetAlpha(LayerAlpha("text"))
        textHandles.hpRight:SetAlpha(LayerAlpha("text"))
        textHandles.powerGroup:SetAlpha(LayerAlpha("text"))
        textHandles.powerLeft:SetAlpha(LayerAlpha("text"))
        textHandles.powerCenter:SetAlpha(LayerAlpha("text"))
        textHandles.powerRight:SetAlpha(LayerAlpha("text"))

        for i = 1, #self._layerButtons do
            local btn = self._layerButtons[i]
            local available = layerAvailable[btn._layerKey] ~= false
            btn._layerAvailable = available
            btn:SetPreviewActive(btn._sectionKey == focus, LayerOn(btn._layerKey), soloLayer == btn._layerKey, available)
        end
        if self._selectedHandle and self._selectedHandle.IsShown and not self._selectedHandle:IsShown() then
            SelectHandle(nil)
        end
        GFPreviewRefreshHandleSelection(self)
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
        if handle._cfgText then
            local _, x, y = GFPreviewHandleOffsets(handle)
            local step = GFPreviewNudgeStep()
            WriteTextHandleOffsets(handle, (tonumber(x) or 0) + (dx * step), (tonumber(y) or 0) + (dy * step), "Nudge", true)
            return
        end
        local point, relativeTo, relativePoint, xOfs, yOfs = handle:GetPoint(1)
        if not point then return end
        local step = GFPreviewNudgeStep()
        handle:ClearAllPoints()
        handle:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + (dx * step), (yOfs or 0) + (dy * step))
        SaveHandlePosition(handle, "Nudge")
        GFPreviewRefreshHandleSelection(self)
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
    box:HookScript("OnHide", function(self)
        StopHandleDrag(self and self._selectedHandle)
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
    local body = builder:CollapsibleSection("gf_preview_native", "Hide Preview", 362, true)
    if W and W.SetCollapsibleToggleText then W.SetCollapsibleToggleText(body, "Hide Preview", "Show Preview") end
    W.Text(body, "Preview updates live here. Enter MSUF Edit Mode to drag the group container. Blizzard-controlled aura blocks can be previewed but not dragged.", 14, -38, (body._msuf2Width or 720) - 28, T.colors.muted)
    local box = CreateNativeGFPreview(body, ctx, OpenGFSection)
    box:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -48)
    box:Show()
    local function RefreshThisPreview()
        if type(SetSectionHeaderStatus) == "function" then
            SetSectionHeaderStatus(body, nil)
        end
        if box and box.Refresh and box:IsShown() then box:Refresh() end
    end
    local entry = body and body._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshThisPreview end
    RefreshThisPreview()
    if body.HookScript then
        body:HookScript("OnShow", RefreshThisPreview)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshThisPreview)
    end
    M._gfNativePreviews[#M._gfNativePreviews + 1] = box
    M.AddRefresher(ctx, RefreshThisPreview)
    if W and W.AttachPinnedPreview then
        W.AttachPinnedPreview(body, box, { stateKey = "groupFramePreview", title = box._title, hint = box._hint, left = 14, right = 14, top = -8 })
    end
end


M.GroupPreview = M.GroupPreview or {}
M.GroupPreview.Add = AddGFPreview
