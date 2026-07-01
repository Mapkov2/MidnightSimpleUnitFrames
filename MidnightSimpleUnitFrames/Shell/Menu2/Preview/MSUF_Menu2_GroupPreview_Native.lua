local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Native group preview renderer.
-- Draws the Menu2 party/raid preview using lightweight mock data and page settings. It should
-- mirror runtime layout decisions but never create secure headers or mutate live group frames.
local T = M.Theme
local PreviewHelpers = M.PreviewHelpers or {}
local Specs = M.GroupPreviewSpecs or {}
local GFZoomPan = M.GroupPreviewZoomPan or {}
local PickDefaults = M.PickDefaults
local F = M.Fallbacks or {}
local floor = math.floor
local max = math.max
local min = math.min
local MSUF_ResolveIconTexturePath = _G.MSUF_ResolveIconTexturePath
local GROUP_PREVIEW_REFRESH_DELAY = 0.05
local LAYER_HEADER_COLOR = { 0.45, 0.50, 0.62, 0.80 }
local LAYER_TEXT_ON = { 0.76, 0.80, 0.90, 0.95 }
local LAYER_TEXT_OFF = { 0.30, 0.30, 0.36, 0.55 }
local LAYER_TEXT_HIGHLIGHT = { 0.90, 0.92, 1.00, 1.00 }
local GF_PREVIEW_ROLE = Specs.ROLE or "HEALER"
local SECTION_PAGE, PAGE_FOCUS, GF_PREVIEW_CLASSES, GF_PREVIEW_NAMES, GF_PREVIEW_ANCHOR_FRAC, GF_AURA_MOCK_ICON_IDS, GF_AURA_GROWTH_TABLE, GF_STATUS_RUNTIME_KEYS = PickDefaults(Specs, [[
    SECTION_PAGE PAGE_FOCUS CLASSES NAMES ANCHOR_FRAC AURA_MOCK_ICON_IDS AURA_GROWTH_TABLE STATUS_RUNTIME_KEYS
]])
if not GF_AURA_GROWTH_TABLE.RIGHTDOWN then GF_AURA_GROWTH_TABLE.RIGHTDOWN = { px = 1, py = 0, sx = 0, sy = -1 } end
local function ShallowCopy(src)
    if type(src) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end
local function SetFSColor(fs, color)
    if fs and fs.SetTextColor and color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end
local function ScheduleNativePreviewRefresh(box, fn)
    if type(fn) ~= "function" then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(GROUP_PREVIEW_REFRESH_DELAY, fn)
    else
        fn()
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
local function CompiledSpec(kind)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.CompileSpec) == "function" then
        kind = kind or CurrentScope()
        local base = gf.CompileSpec(kind, nil, nil)
        if type(base) ~= "table" then return base end
        local spec = ShallowCopy(base) or {}
        local conf = Conf(kind)
        spec.key = "gf_" .. tostring(kind)
        spec.groupKind = kind
        spec._msufMenu2PreviewRuntime = true
        if type(base.power) == "table" then
            local power = ShallowCopy(base.power) or {}
            local powerHeight = tonumber(power.height) or 0
            if type(gf.GetEffectivePowerHeight) == "function" then
                powerHeight = tonumber(gf.GetEffectivePowerHeight(kind, nil, GF_PREVIEW_ROLE, conf)) or 0
            elseif type(gf.ShouldShowPowerBarForRole) == "function" and gf.ShouldShowPowerBarForRole(kind, GF_PREVIEW_ROLE, conf) ~= true then
                powerHeight = 0
            end
            power.enabled = powerHeight > 0
            power.height = powerHeight
            spec.power = power
        end
        if type(base.status) == "table" then
            local status = ShallowCopy(base.status) or {}
            status.roleValue = GF_PREVIEW_ROLE
            spec.status = status
        end
        return spec
    end
    return nil
end
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
    if pageKey and M.SelectPage then
        local scope = CurrentScope()
        ExportPublic("MSUF_EM2_MenuFocusRequest", {
            key = (scope == "raid" and "gf_raid") or (scope == "mythicraid" and "gf_mythicraid") or "gf_party",
            component = sectionKey,
            pageKey = pageKey,
            sectionId = sectionKey,
            source = "group-preview",
            explicit = true,
            changedAt = GetTime and GetTime() or 0,
        })
        M.SelectPage(pageKey)
    end
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
        local texture = _G.MSUF_ResolveStatusbarTextureKey(value)
        if texture then return texture end
    end
    if LibStub then
        local lsm = LibStub("LibSharedMedia-3.0", true)
        if lsm and type(lsm.Fetch) == "function" then
            local texture = lsm:Fetch("statusbar", value, true)
            if texture then return texture end
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end
local function HealthColor(conf, pct, classToken)
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
        if type(fastClass) == "function" then r, g, b = fastClass(classToken) end
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
local WHITE8X8 = Specs.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
local maskRoot = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local GF_PREVIEW_ROUNDED_MASK = Specs.ROUNDED_MASK or (maskRoot .. "rounded_bar_4x.tga")
local GF_PREVIEW_ROUNDED_EDGE = Specs.ROUNDED_EDGE or (maskRoot .. "rounded_bar_edge_4x.tga")
local GF_PREVIEW_MIN_W = Specs.MIN_W or 380
local GF_PREVIEW_MIN_H = Specs.MIN_H or 130
local GF_PREVIEW_ZOOM_MIN = Specs.ZOOM_MIN or 0.35
local GF_PREVIEW_ZOOM_MAX = Specs.ZOOM_MAX or 4.0
local function Tr(text)
    return (M.Tr and M.Tr(text)) or text
end
local function ClassColor(classToken, dr, dg, db)
    if type(_G.MSUF_UFCore_GetClassBarColorFast) == "function" then
        local r, g, b = _G.MSUF_UFCore_GetClassBarColorFast(classToken)
        if r then return r, g, b end
    end
    local c = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return dr or 0.06, dg or 0.06, db or 0.07
end
local function AuraGrowth(growth)
    return GF_AURA_GROWTH_TABLE[growth] or GF_AURA_GROWTH_TABLE.RIGHTDOWN
end
local function GrowthFromCompiled(primary, wrap, fallback)
    if primary == "LEFT" then
        return wrap == "UP" and "LEFTUP" or "LEFTDOWN"
    elseif primary == "UP" then
        return "UPRIGHT"
    elseif primary == "DOWN" then
        return "DOWNRIGHT"
    end
    return wrap == "UP" and "RIGHTUP" or (fallback or "RIGHTDOWN")
end
local function CompiledAuraLane(auras, key, fallback)
    if type(auras) ~= "table" then return fallback or {} end
    local prefix, showKey
    if key == "buff" then
        prefix, showKey = "buff", "showBuffs"
    elseif key == "debuff" then
        prefix, showKey = "debuff", "showDebuffs"
    else
        return fallback or {}
    end
    local out = {
        _compiled = true,
        enabled = auras[showKey] == true,
        max = auras["max" .. (key == "buff" and "Buffs" or "Debuffs")],
        perRow = auras[prefix .. "PerRow"],
        size = auras[prefix .. "IconSize"],
        spacing = auras[prefix .. "Spacing"],
        anchor = auras[prefix .. "Anchor"],
        growth = GrowthFromCompiled(auras[prefix .. "GrowthX"], auras[prefix .. "GrowthY"], fallback and fallback.growth),
        x = auras[prefix .. "OffsetX"],
        y = auras[prefix .. "OffsetY"],
        layer = auras[prefix .. "Layer"],
        showCooldownSwipe = auras[prefix .. "ShowCooldownSwipe"],
        cooldownSwipeReverse = auras[prefix .. "CooldownSwipeReverse"],
        showCooldown = auras[prefix .. "ShowCooldown"],
        showStacks = auras[prefix .. "ShowStacks"],
        cooldownSize = auras[prefix .. "CooldownSize"],
        cooldownAnchor = auras[prefix .. "CooldownAnchor"],
        cooldownX = auras[prefix .. "CooldownX"],
        cooldownY = auras[prefix .. "CooldownY"],
        stackSize = auras[prefix .. "StackSize"],
        stackAnchor = auras[prefix .. "StackAnchor"],
        stackX = auras[prefix .. "StackX"],
        stackY = auras[prefix .. "StackY"],
        dispelBorderMode = key == "debuff" and auras.debuffDispelBorderMode or nil,
        showDispelBorder = key == "debuff" and auras.debuffShowDispelBorder or nil,
        showDispelSymbol = key == "debuff" and auras.debuffShowDispelSymbol or nil,
        alpha = tonumber(auras[prefix .. "Alpha"]) or 1,
        behindBar = (tonumber(auras[prefix .. "Alpha"]) or 1) < 1,
    }
    return out
end
local function RuntimeStatusConfig(status, spec)
    if type(status) ~= "table" or type(spec) ~= "table" then return nil end
    local value = spec.value
    if value == "statusText" then
        return status.statusText and status.statusText.dead or status.statusText
    elseif value == "statusGhostText" then
        return status.statusText and status.statusText.ghost or nil
    elseif value == "statusAFKText" then
        return status.statusText and status.statusText.afk or nil
    end
    local key = GF_STATUS_RUNTIME_KEYS[value]
    return key and status[key] or nil
end
local function Int(value, fallback, minValue, maxValue)
    local n = floor((tonumber(value) or tonumber(fallback) or 0) + 0.0001)
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end
local gfMockSpellTextureCache = {}
local function MockSpellTexture(spellId)
    local cached = gfMockSpellTextureCache[spellId]
    if cached then return cached end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then
            tex = (type(MSUF_ResolveIconTexturePath) == "function" and MSUF_ResolveIconTexturePath(tex)) or tex
            gfMockSpellTextureCache[spellId] = tex
            return tex
        end
    end
    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellId)
        if icon then
            icon = (type(MSUF_ResolveIconTexturePath) == "function" and MSUF_ResolveIconTexturePath(icon)) or icon
            gfMockSpellTextureCache[spellId] = icon
            return icon
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function CurrentSpellInfo(kind)
    local gp = GroupPage()
    local gf = MSUF and MSUF.GF
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
local function CurrentSpellConfig(kind)
    local gp = GroupPage()
    if type(gp.CurrentSpellConfig) == "function" then
        local cfg = gp.CurrentSpellConfig(kind, false)
        if type(cfg) == "table" then return cfg end
    end
    return nil
end
local function CurrentSpellPlaced(kind)
    local gp = GroupPage()
    if type(gp.PlacedConfig) == "function" then
        local placed = gp.PlacedConfig(kind, false)
        if type(placed) == "table" then return placed end
    end
    local cfg = CurrentSpellConfig(kind)
    return type(cfg and cfg.placed) == "table" and cfg.placed or nil
end
local function CurrentSpellTexture(kind)
    local info, specKey, auraName = CurrentSpellInfo(kind)
    local gf = MSUF and MSUF.GF
    local si = gf and gf.SpellIndicators
    if si and type(si.GetAuraIcon) == "function" and specKey and auraName and auraName ~= "" then
        local icon = si.GetAuraIcon(specKey, auraName)
        if icon then return icon end
    end
    if info and info.spellId then return MockSpellTexture(info.spellId) end
    return MockSpellTexture(774)
end
local function CurrentSpellColor(kind)
    local info = CurrentSpellInfo(kind)
    local c = info and info.color
    return (c and c[1]) or 0.69, (c and c[2]) or 0.50, (c and c[3]) or 0.88
end
local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end
local function ScaleValue(value, scale, minValue)
    local v = Round((tonumber(value) or 0) * (tonumber(scale) or 1))
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end
local UpdateHint
if GFZoomPan.Configure then
    GFZoomPan.Configure({
        T = T,
        TR = Tr,
        WHITE8X8 = WHITE8X8,
        UpdateHint = function(box, selected)
            if UpdateHint then UpdateHint(box, selected) end
        end,
    })
end
local ClampZoom = GFZoomPan.Clamp or function(value)
    value = tonumber(value) or 1
    if value < GF_PREVIEW_ZOOM_MIN then return GF_PREVIEW_ZOOM_MIN end
    if value > GF_PREVIEW_ZOOM_MAX then return GF_PREVIEW_ZOOM_MAX end
    return floor(value * 100 + 0.5) / 100
end
local UpdateZoomControls = GFZoomPan.UpdateControls or F.Noop
local SetZoom = GFZoomPan.SetZoom or F.Noop
local StepZoom = GFZoomPan.Step or F.Noop
local StartPan = GFZoomPan.Start or F.False
local StopPan = GFZoomPan.Stop or F.Noop
local function ReadBarsBool(key, default)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local value = bars and bars[key]
    if value == nil then return default and true or false end
    return value and true or false
end
local function NormalizeAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback or 3
    if mode < 1 or mode > 5 then mode = fallback or 3 end
    return mode
end
local function SharedHealPredictionEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if type(gen) ~= "table" then return false end
    if gen.showSelfHealPrediction ~= nil then return gen.showSelfHealPrediction == true end
    if gen.enableHealPrediction ~= nil then return gen.enableHealPrediction ~= false end
    return false
end
local function HealPredictionEnabled(kind, conf)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.IsHealPredictionEnabled) == "function" then return gf.IsHealPredictionEnabled(kind, conf) == true end
    if conf and conf.hlOverride == true and conf.healPredEnabled ~= nil then return conf.healPredEnabled == true end
    return SharedHealPredictionEnabled()
end
local function HealPredAnchorMode(conf)
    if conf and conf.hlOverride == true and conf.healPredAnchorMode ~= nil then return NormalizeAnchorMode(conf.healPredAnchorMode, 3) end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    return NormalizeAnchorMode(gen and gen.healPredAnchorMode, 3)
end
local GFRounded = (M.GroupPreviewRounded and M.GroupPreviewRounded.Install and M.GroupPreviewRounded.Install({
    PreviewHelpers = PreviewHelpers,
    Specs = Specs,
    WHITE8X8 = WHITE8X8,
    ROUNDED_MASK = GF_PREVIEW_ROUNDED_MASK,
    ROUNDED_EDGE = GF_PREVIEW_ROUNDED_EDGE,
    ReadBarsBool = ReadBarsBool,
    Round = Round,
    HealPredAnchorMode = HealPredAnchorMode,
})) or {}
local SetOutlineShown = GFRounded.SetOutlineShown or F.Noop
local LayoutOutline = GFRounded.LayoutOutline or F.Noop
local BaseEdgeColor = GFRounded.BaseEdgeColor or F.BlackRGBA
local ApplyRounded = GFRounded.ApplyRounded or F.False
local function ConfigToOffset(value, scale)
    return Round((tonumber(value) or 0) * (tonumber(scale) or 1))
end
local function OffsetToConfig(value, scale)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return Round((tonumber(value) or 0) / scale)
end
local function ResolveAnchor(rx, ry)
    local best, bestD = "CENTER", 1e9
    for point, frac in pairs(GF_PREVIEW_ANCHOR_FRAC) do
        local dx = rx - frac[1]
        local dy = ry - (1 - frac[2])
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = point, d end
    end
    return best
end
local function HandleOffset(handle, anchorFrame, anchor)
    local frac = GF_PREVIEW_ANCHOR_FRAC[anchor]
    if not (handle and anchorFrame and frac) then return 0, 0 end
    local hL, hB, hW, hH = handle:GetLeft() or 0, handle:GetBottom() or 0, handle:GetWidth() or 1, handle:GetHeight() or 1
    local aL, aB, aW, aH = anchorFrame:GetLeft() or 0, anchorFrame:GetBottom() or 0, anchorFrame:GetWidth() or 1, anchorFrame:GetHeight() or 1
    local hx = hL + hW * frac[1]
    local hy = hB + hH * frac[2]
    local ax = aL + aW * frac[1]
    local ay = aB + aH * frac[2]
    return Round(hx - ax), Round(hy - ay)
end
local function PointOffset(px, py, anchorFrame, anchor)
    local frac = GF_PREVIEW_ANCHOR_FRAC[anchor]
    if not (anchorFrame and frac) then return 0, 0 end
    local aL, aB = anchorFrame:GetLeft() or 0, anchorFrame:GetBottom() or 0
    local aW, aH = anchorFrame:GetWidth() or 1, anchorFrame:GetHeight() or 1
    local ax = aL + aW * frac[1]
    local ay = aB + aH * frac[2]
    return Round((px or 0) - ax), Round((py or 0) - ay)
end
local function MockPowerHeight(kind, conf, zoom, frameScale)
    local livePowerH
    local gf = MSUF and MSUF.GF
    if gf and gf.GetEffectivePowerHeight then livePowerH = gf.GetEffectivePowerHeight(kind, nil, GF_PREVIEW_ROLE, conf) end
    if livePowerH == nil then
        local raw = conf and (tonumber(conf.powerHeight) or 6) or 6
        if gf and gf.ShouldShowPowerBarForRole and not gf.ShouldShowPowerBarForRole(kind, GF_PREVIEW_ROLE, conf) then raw = 0 end
        livePowerH = raw > 0 and ScaleValue(raw, frameScale or 1, 0) or 0
    end
    livePowerH = tonumber(livePowerH) or 0
    if livePowerH <= 0 then return 0 end
    return Round(livePowerH * (tonumber(zoom) or 1))
end
local function HandleText(handle)
    if not handle then return "Group preview" end
    local label = handle._label
    local text = label and label.GetText and label:GetText()
    if text and text ~= "" then return text end
    local previewText = handle._previewText
    if previewText and previewText ~= "" then return previewText end
    return handle._key or "Group preview"
end
local function ClampLayer(value, fallback)
    local v = floor((tonumber(value) or fallback or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 30 then return 30 end
    return v
end
local function StatusSpecs()
    local gp = GroupPage()
    if type(gp.GF_STATUS_ICON_SPECS) == "table" and #gp.GF_STATUS_ICON_SPECS > 0 then return gp.GF_STATUS_ICON_SPECS end
    local sharedSpecs = M.GroupSpecs and M.GroupSpecs.GF_STATUS_ICON_SPECS
    if type(sharedSpecs) == "table" and #sharedSpecs > 0 then return sharedSpecs end
    return {}
end
local function CurrentStatusSpec()
    local gp = GroupPage()
    if type(gp.CurrentGFStatusSpec) == "function" then
        local spec = gp.CurrentGFStatusSpec()
        if type(spec) == "table" then return spec end
    end
    local specs = StatusSpecs()
    local selected = M.gfStatusIconSelection or "roleIcon"
    for i = 1, #specs do
        if specs[i].value == selected then return specs[i] end
    end
    return specs[1]
end
local function StatusSpecIsText(spec)
    local value = spec and spec.value
    return value == "statusText" or value == "statusGhostText" or value == "statusAFKText"
end
local function StatusText(spec)
    local value = spec and spec.value
    if value == "statusGhostText" then return "GHOST" end
    if value == "statusAFKText" then return "AFK" end
    return "DEAD"
end
local function StatusLabel(spec)
    local value = spec and spec.value
    if value == "roleIcon" then return "Role" end
    if value == "leaderIcon" then return "Leader" end
    if value == "assistIcon" then return "Assist" end
    if value == "raidMarker" then return "Marker" end
    if value == "readyCheckIcon" then return "Ready" end
    if value == "summonIcon" then return "Summon" end
    if value == "resurrectIcon" then return "Rez" end
    if value == "pvpIcon" then return "PvP" end
    if value == "phaseIcon" then return "Phase" end
    if value == "statusText" then return "Dead Text" end
    if value == "statusGhostText" then return "Ghost Text" end
    if value == "statusAFKText" then return "AFK/DND" end
    return (spec and spec.text) or "Status"
end
local function StatusPreviewMode()
    local gf = MSUF and MSUF.GF
    if gf and type(gf.GetStatusPreviewMode) == "function" then
        local mode = gf.GetStatusPreviewMode()
        if mode == "all" then return "all" end
    end
    return M.gfStatusPreviewMode == "all" and "all" or "current"
end
local function StatusSpecEnabled(conf, spec)
    if not spec then return false end
    conf = conf or {}
    return conf[spec.enabled] ~= false
end
local function StatusSpecInMode(spec, selectedSpec)
    if StatusPreviewMode() == "all" then return true end
    local selected = selectedSpec and selectedSpec.value or M.gfStatusIconSelection or "roleIcon"
    return spec and spec.value == selected
end
local GFTextFocus = (M.GroupPreviewTextFocus and M.GroupPreviewTextFocus.Install and M.GroupPreviewTextFocus.Install({
    CurrentScope = CurrentScope,
    min = min,
    max = max,
})) or {}
local CurrentTextKind = GFTextFocus.CurrentTextKind or function() return "name" end
local TextOffsetKeys = GFTextFocus.TextOffsetKeys or function() return "nameOffsetX", "nameOffsetY" end
local TextLabel = GFTextFocus.TextLabel or function() return "Name Text" end
local TextMovesTogether = GFTextFocus.TextMovesTogether or F.True
local SetTextMoveTogether = GFTextFocus.SetTextMoveTogether or F.Noop
local PlaceHandleAroundRegions = GFTextFocus.PlaceHandleAroundRegions or F.False
local NormalizeTextFocusKind = GFTextFocus.NormalizeTextFocusKind or F.Identity
local NormalizeTextFocusSlot = GFTextFocus.NormalizeTextFocusSlot or F.Identity
local ApplyTextFocus = GFTextFocus.ApplyTextFocus or F.Noop
local function HandleOffsets(handle)
    if not handle then return nil end
    local conf = Conf(CurrentScope()) or {}
    if handle._cfgGroup then
        local auras = conf.auras or {}
        local cfg = auras[handle._cfgGroup] or {}
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgStatus then
        local spec = handle._statusSpec or CurrentStatusSpec()
        if not spec then return nil end
        return conf[spec.anchor] or spec.defaultAnchor, tonumber(conf[spec.x]) or 0, tonumber(conf[spec.y]) or 0
    elseif handle._cfgSpell then
        local cfg = CurrentSpellPlaced(CurrentScope()) or {}
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgTargetedSpells then
        local cfg = Conf("party") or conf
        return cfg.targetedSpellsAnchor or "CENTER", tonumber(cfg.targetedSpellsX) or 0, tonumber(cfg.targetedSpellsY) or 0
    elseif handle._cfgText then
        local kind = handle._cfgTextKind or CurrentTextKind()
        local slot = handle._cfgTextSlot
        local xKey, yKey = TextOffsetKeys(kind, slot)
        return (kind == "name" and (conf.nameAnchor or "LEFT") or TextLabel(kind, slot)), tonumber(conf[xKey]) or 0, tonumber(conf[yKey]) or 0
    end
    return nil
end
UpdateHint = function(box, handle)
    if not (box and box._hint) then return end
    if not handle then
        box._hint:SetText(Tr("click layers to hide - drag handles - arrows nudge selected - Ctrl+wheel zoom - Ctrl+left drag pans"))
        return
    end
    local anchor, x, y = HandleOffsets(handle)
    local nudgeHint = Tr("arrows nudge, Shift=5, Ctrl=10 - Ctrl+left drag pans")
    if anchor then
        box._hint:SetText(string.format("%s   %s   x: %d   y: %d   %s",
            HandleText(handle), tostring(anchor or "CENTER"), Round(x or 0), Round(y or 0), nudgeHint))
    else
        box._hint:SetText(string.format("%s   %s", HandleText(handle), nudgeHint))
    end
end
local NudgeStep = PreviewHelpers.NudgeStep or F.One
local function RefreshHandleSelection(box)
    if not box then return end
    local selected = box._selectedHandle
    local guidesOn = not (M.gfPreviewLayerVisible and M.gfPreviewLayerVisible.guides == false)
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
            if handle._selectFill then handle._selectFill:SetColorTexture(color[1], color[2], color[3], guidesOn and (isDrag and 0.18 or (isHover and 0.14 or 0)) or 0) end
            if handle._selectBorder then
                handle._selectBorder:SetShown(guidesOn and (isSelected or isHover))
                handle._selectBorder:SetBackdropBorderColor(color[1], color[2], color[3], isSelected and 0.70 or 0.72)
            end
            if handle.SetBackdropBorderColor then
                local borderAlpha = guidesOn and (isSelected and 0.70 or (isHover and 0.85 or (handle._locked and 0.55 or 0.95))) or 0
                if handle._cfgText then borderAlpha = 0 end
                handle:SetBackdropBorderColor(color[1], color[2], color[3], borderAlpha)
            end
            if handle.SetBackdropColor and not handle._cfgText then
                local alpha = guidesOn and 0.42 or 0
                handle:SetBackdropColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, alpha)
            end
            if handle._cfgText and handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
        end
    end
    UpdateHint(box, selected)
end
local Helpers = {
    CurrentScope = CurrentScope, Conf = Conf, PreviewScopeLabel = PreviewScopeLabel,
    SetTextMoveTogether = SetTextMoveTogether, CurrentTextKind = CurrentTextKind, TextOffsetKeys = TextOffsetKeys,
    NudgeStep = NudgeStep, StatusSpecs = StatusSpecs, TextLabel = TextLabel, PreviewFocusForPage = PreviewFocusForPage,
    MockPowerHeight = MockPowerHeight, HealPredAnchorMode = HealPredAnchorMode, HealPredictionEnabled = HealPredictionEnabled,
    SetOutlineShown = SetOutlineShown, LayoutOutline = LayoutOutline, TextMovesTogether = TextMovesTogether,
    PlaceHandleAroundRegions = PlaceHandleAroundRegions, NormalizeTextFocusKind = NormalizeTextFocusKind,
    NormalizeTextFocusSlot = NormalizeTextFocusSlot, ApplyTextFocus = ApplyTextFocus,
}
local NativeDeps = {
    M = M,
    MSUF = MSUF,
    T = T,
    WHITE8X8 = WHITE8X8,
    H = Helpers,
    Helpers = Helpers,
    LayerFont = LayerFont,
    LayerHeaderColor = LAYER_HEADER_COLOR,
    MakePreviewSectionButton = MakePreviewSectionButton,
    CreateZoomButton = GFZoomPan.CreateButton,
    TR = Tr,
    Tr = Tr,
    StepZoom = StepZoom,
    SetZoom = SetZoom,
    StartPan = StartPan,
    StopPan = StopPan,
    ZoomWheel = F.Noop,
    UpdateHint = UpdateHint,
    Round = Round,
    ResolveAnchor = ResolveAnchor,
    PointOffset = PointOffset,
    HandleOffset = HandleOffset,
    OffsetToConfig = OffsetToConfig,
    CurrentStatusSpec = CurrentStatusSpec,
    CurrentSpellConfig = CurrentSpellConfig,
    CurrentSpellPlaced = CurrentSpellPlaced,
    HandleText = HandleText,
    HandleOffsets = HandleOffsets,
    RefreshHandleSelection = RefreshHandleSelection,
    StatusLabel = StatusLabel,
    NAMES = GF_PREVIEW_NAMES,
    CLASSES = GF_PREVIEW_CLASSES,
    AURA_MOCK_ICON_IDS = GF_AURA_MOCK_ICON_IDS,
    MIN_W = GF_PREVIEW_MIN_W,
    MIN_H = GF_PREVIEW_MIN_H,
    ROLE = GF_PREVIEW_ROLE,
    ANCHOR_FRAC = GF_PREVIEW_ANCHOR_FRAC,
    AUTO_ZOOM_MIN = Specs.AUTO_ZOOM_MIN or 0.75,
    AUTO_ZOOM_MAX = Specs.AUTO_ZOOM_MAX or 1.65,
    AUTO_ZOOM_STAGE_PAD_X = Specs.AUTO_ZOOM_STAGE_PAD_X or 48,
    AUTO_ZOOM_STAGE_PAD_Y = Specs.AUTO_ZOOM_STAGE_PAD_Y or 72,
    CompiledSpec = CompiledSpec,
    CompiledAuraLane = CompiledAuraLane,
    RuntimeStatusConfig = RuntimeStatusConfig,
    StatusSpecEnabled = StatusSpecEnabled,
    StatusSpecInMode = StatusSpecInMode,
    StatusSpecIsText = StatusSpecIsText,
    StatusText = StatusText,
    CurrentSpellTexture = CurrentSpellTexture,
    CurrentSpellColor = CurrentSpellColor,
    MockSpellTexture = MockSpellTexture,
    Int = Int,
    ScaleValue = ScaleValue,
    ClampZoom = ClampZoom,
    UpdateZoomControls = UpdateZoomControls,
    ConfigToOffset = ConfigToOffset,
    AuraGrowth = AuraGrowth,
    ApplyRounded = ApplyRounded,
    BaseEdgeColor = BaseEdgeColor,
    LayoutOutline = LayoutOutline,
    ClampLayer = ClampLayer,
    HealPredictionEnabled = HealPredictionEnabled,
    HealPredAnchorMode = HealPredAnchorMode,
    MockPowerHeight = MockPowerHeight,
    ClassColor = ClassColor,
    HealthColor = HealthColor,
    ResolveStatusbarTexture = ResolvePreviewStatusbarTexture,
}
local function CreateNativeGFPreview(parent, ctx, onOpen)
    local R = ShallowCopy(NativeDeps) or {}
    local H, T, M = R.Helpers, R.T, R.M
    local width = (ctx.width or 720) - 28
    local box = T.Panel(parent, nil, T.colors.panel2, T.colors.border)
    box:SetSize(width, 300)
    if parent and parent.GetFrameLevel and box.SetFrameLevel then box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2) end
    local title = T.Font(box, "GameFontNormal", "", T.colors.accent)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    title:SetText(string.format((M.Tr and M.Tr("%s - %s")) or "%s - %s", (M.Tr and M.Tr("Group Frame Preview")) or "Group Frame Preview", H.PreviewScopeLabel(H.CurrentScope())))
    box._title = title
    local hint = T.Font(box, "GameFontDisableSmall", R.Tr("click layers to hide - drag handles - arrows nudge selected - Ctrl+wheel zoom - Ctrl+left drag pans"), T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    box._hint = hint
    local stage = T.Panel(box, nil, { 0, 0, 0, 1 }, T.colors.borderSoft)
    stage:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -34)
    stage:SetSize(width - 98, 218)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    stage:EnableMouse(true)
    stage:EnableMouseWheel(true)
    if stage.SetPropagateMouseWheel then stage:SetPropagateMouseWheel(true) end
    box._stage = stage
    PreviewHelpers.BuildZoomBar(box, stage, {
        template = T.Template(),
        texture = R.WHITE8X8,
        T = T,
        themeReadout = true,
        fieldPrefix = "_",
        wheelField = "_zoomWheel",
        CreateZoomButton = R.CreateZoomButton,
        Tr = R.Tr,
        StepZoom = R.StepZoom,
        SetZoom = R.SetZoom,
        StartPan = R.StartPan,
        StopPan = R.StopPan,
        fitReason = "GROUP_PREVIEW_ZOOM_FIT",
        oneReason = "GROUP_PREVIEW_ZOOM_1TO1",
    })
    R.ZoomWheel = box._zoomWheel or R.ZoomWheel
    local bounds = CreateFrame("Frame", nil, stage, T.Template())
    bounds:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bounds:SetBackdropColor(0, 0, 0, 0)
    bounds:SetBackdropBorderColor(0.90, 0.05, 0.02, 0.95)
    box._bounds = bounds
    local layers = T.Panel(box, nil, T.colors.panel, T.colors.borderSoft)
    layers:SetPoint("TOPLEFT", stage, "TOPRIGHT", 8, 0)
    layers:SetSize(78, 218)
    box._layers = layers
    local layersTitle = R.LayerFont(layers, "LAYERS", R.LayerHeaderColor)
    layersTitle:SetPoint("TOPLEFT", layers, "TOPLEFT", 10, -10)
    M.gfPreviewLayerVisible = M.gfPreviewLayerVisible or {
        guides = true,
        bounds = true,
        buff = true,
        debuff = true,
        status = true,
        si = true,
        targetedSpells = true,
        auraText = true,
        text = true,
    }
    local layerDefs = {
        { "Guides", { 0.42, 0.72, 1.00 }, "layout", "guides" },
        { "Bounds", { 1.00, 0.22, 0.12 }, "layout", "bounds" },
        { "Buffs", { 0.20, 0.90, 0.35 }, "buffs", "buff" },
        { "Debuffs", { 0.90, 0.20, 0.22 }, "debuffs", "debuff" },
        { "Status", { 0.95, 0.78, 0.22 }, "sicons", "status" },
        { "Spells", { 0.86, 0.50, 1.00 }, "si", "si" },
        { "Target", { 1.00, 0.52, 0.18 }, "targetedSpells", "targetedSpells" },
        { "CD/Stack", { 1.00, 0.82, 0.28 }, "textcolor", "auraText" },
        { "Text", { 0.70, 0.90, 1.00 }, "text", "text" },
    }
    box._layerButtons = {}
    for i = 1, #layerDefs do
        local def = layerDefs[i]
        local btn = R.MakePreviewSectionButton(layers, def[1], def[2], def[3], onOpen)
        btn._layerKey = def[4]
        btn:SetPoint("TOPLEFT", layers, "TOPLEFT", 8, -26 - ((i - 1) * 16))
        btn:SetScript("OnEnter", function(self)
            if self._layerAvailable == false and box._hint then box._hint:SetText(string.format((M.Tr and M.Tr("%s is off in settings and cannot be shown in preview.")) or "%s is off in settings and cannot be shown in preview.", self._label and self._label:GetText() or ((M.Tr and M.Tr("Layer")) or "Layer"))) end
        end)
        btn:SetScript("OnLeave", function()
            R.UpdateHint(box, box._selectedHandle)
        end)
        M.AddTooltip(btn, "Layer disabled", "Turn this feature on in settings to make the preview layer available.", {
            hook = true,
            enabled = function(self) return self._layerAvailable == false end,
        })
        btn:SetScript("OnClick", function(self)
            local key = self._layerKey
            if self._layerAvailable == false then
                if box._hint then box._hint:SetText((self._label and self._label:GetText() or "Layer") .. " is off in settings and cannot be shown in preview.") end
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
            if box.RequestRefresh then box:RequestRefresh("GROUP_PREVIEW_LAYER") elseif box.Refresh then box:Refresh() end
        end)
        box._layerButtons[#box._layerButtons + 1] = btn
    end
    local mock = CreateFrame("Frame", nil, stage, T.Template())
    mock:SetBackdrop({ bgFile = R.WHITE8X8 })
    mock:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
    mock:SetBackdropBorderColor(0.0, 0.0, 0.0, 0)
    mock:EnableMouse(true)
    mock:EnableMouseWheel(true)
    if mock.SetPropagateMouseWheel then mock:SetPropagateMouseWheel(true) end
    mock:SetScript("OnMouseWheel", R.ZoomWheel)
    mock:SetScript("OnMouseDown", function(_, button) R.StartPan(stage, box, button) end)
    mock:SetScript("OnMouseUp", function()
        if stage._msufGFPreviewPanning then R.StopPan(stage) end
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
    mock._healPred:SetStatusBarTexture(R.WHITE8X8)
    mock._healPred:SetStatusBarColor(0, 1, 0.4, 0.45)
    mock._absorb = CreateFrame("StatusBar", nil, mock)
    mock._absorb:SetMinMaxValues(0, 1)
    mock._absorb:SetValue(1)
    mock._absorb:SetStatusBarTexture(R.WHITE8X8)
    mock._absorb:SetStatusBarColor(0.55, 0.70, 1, 0.55)
    mock._power = CreateFrame("StatusBar", nil, mock)
    mock._power:SetMinMaxValues(0, 1)
    mock._power:SetValue(1)
    mock._power:SetStatusBarColor(0.13, 0.27, 0.67, 1)
    mock._powerBg = mock._power:CreateTexture(nil, "BACKGROUND")
    mock._powerBg:SetAllPoints()
    mock._nameTextLayer = CreateFrame("Frame", nil, mock)
    mock._nameTextLayer:SetAllPoints(mock)
    mock._healthTextLayer = CreateFrame("Frame", nil, mock)
    mock._healthTextLayer:SetAllPoints(mock)
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
    local handleBundle = (M.GroupPreviewHandles and M.GroupPreviewHandles.Install and M.GroupPreviewHandles.Install(box, R)) or {}
    local buffHandle = handleBundle.buffHandle
    local debuffHandle = handleBundle.debuffHandle
    local statusHandles = handleBundle.statusHandles or {}
    local spellHandle = handleBundle.spellHandle
    local targetedHandle = handleBundle.targetedHandle
    local SelectHandle = handleBundle.SelectHandle or function() end
    local NudgeHandlePosition = handleBundle.NudgeHandlePosition or function() end
    local AddIconPool = handleBundle.AddIconPool or function() end
    local StopHandleDrag = handleBundle.StopHandleDrag or function()
        if box._dragFrame then
            box._dragFrame:SetScript("OnUpdate", nil)
            box._dragFrame._handle = nil
            box._dragFrame:Hide()
        end
    end
    local footer = T.Font(box, "GameFontDisableSmall", R.Tr("Click a handle to select - drag layers - Ctrl+wheel zoom - Ctrl+left drag pans"), T.colors.muted)
    footer:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -8)
    if M.GroupPreviewRender and M.GroupPreviewRender.Install then
        local renderDeps = ShallowCopy(R) or {}
        renderDeps.width, renderDeps.mock = width, mock
        renderDeps.buffHandle, renderDeps.debuffHandle = buffHandle, debuffHandle
        renderDeps.statusHandles, renderDeps.spellHandle = statusHandles, spellHandle
        renderDeps.targetedHandle = targetedHandle
        renderDeps.statusSpecs = H.StatusSpecs and H.StatusSpecs()
        renderDeps.SelectHandle = SelectHandle
        renderDeps.NudgeHandlePosition = NudgeHandlePosition
        renderDeps.AddIconPool = AddIconPool
        M.GroupPreviewRender.Install(box, ctx, renderDeps)
    end
    function box:RequestRefresh(reason)
        local hostShown = self._msufGFPreviewHostShown
        if type(hostShown) == "function" and not hostShown() then
            self:ReleaseRuntimePreview()
            return
        end
        if self._msufGFRefreshQueued then
            self._msufGFRefreshReason = reason or self._msufGFRefreshReason
            return
        end
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        local serial = self._msufGFRefreshSerial
        self._msufGFRefreshQueued = true
        self._msufGFRefreshReason = reason
        local function RunRefresh()
            if not self then return end
            if serial ~= self._msufGFRefreshSerial then return end
            self._msufGFRefreshQueued = nil
            if self._msufGFNativePreviewDisposed then return end
            if self.IsShown and not self:IsShown() then return end
            if self.IsVisible and not self:IsVisible() then return end
            local currentHostShown = self._msufGFPreviewHostShown
            if type(currentHostShown) == "function" and not currentHostShown() then
                self:ReleaseRuntimePreview()
                return
            end
            if self.Refresh then self:Refresh(self._msufGFRefreshReason) end
            self._msufGFRefreshReason = nil
        end
        ScheduleNativePreviewRefresh(self, RunRefresh)
    end
    function box:ReleaseRuntimePreview()
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        self._msufGFRefreshQueued = nil
        self._msufGFRefreshReason = nil
        StopHandleDrag(self and self._selectedHandle)
        self._selectedHandle = nil
        if PreviewHelpers.ReleaseKeyboardCapture then
            PreviewHelpers.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end
    box:HookScript("OnShow", function(self)
        self:RequestRefresh("GROUP_PREVIEW_SHOW")
    end)
    box:HookScript("OnHide", function(self)
        self:ReleaseRuntimePreview()
    end)
    box:HookScript("OnSizeChanged", function(self, width, height)
        if not self:IsShown() then return end
        width = floor((tonumber(width) or self:GetWidth() or 0) + 0.5)
        height = floor((tonumber(height) or self:GetHeight() or 0) + 0.5)
        if self._msufGFRefreshWidth == width and self._msufGFRefreshHeight == height then return end
        self._msufGFRefreshWidth = width
        self._msufGFRefreshHeight = height
        self:RequestRefresh("GROUP_PREVIEW_SIZE")
    end)
    return box
end
M.GroupPreview = M.GroupPreview or {}
M.GroupPreview.CreateNative = CreateNativeGFPreview
M.GroupPreview.OpenSection = OpenGFSection
function M.FocusGFPreviewTextSlot(kind, slot, active)
    local previews = M._gfNativePreviews
    if not previews then return false end
    local focused = false
    for i = 1, #previews do
        local box = previews[i]
        if box and not box._msufGFNativePreviewDisposed and box.FocusTextSlot and box.IsShown and box:IsShown() and (not box.IsVisible or box:IsVisible()) then focused = box:FocusTextSlot(kind, slot, active) or focused end
    end
    return focused
end
