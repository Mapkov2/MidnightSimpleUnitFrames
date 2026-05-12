local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets

local floor = math.floor
local max = math.max
local min = math.min

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
    if W and W.SetCollapsibleToggleText then W.SetCollapsibleToggleText(body, "Hide Preview", "Show Preview") end
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


M.GroupPreview = M.GroupPreview or {}
M.GroupPreview.Add = AddGFPreview
