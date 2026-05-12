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

local GroupPage = M.GroupPage or {}
M.GroupPage = GroupPage
GroupPage.Conf = Conf
GroupPage.Val = Val
GroupPage.Set = Set
GroupPage.Bool = Bool
GroupPage.Num = Num
GroupPage.CurrentScope = CurrentScope
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
    W.SetControlEnabled(control, enabled)
end

local function SetOptionsEnabled(controls, enabled)
    W.SetControlsEnabled(controls, enabled)
end

GroupPage.SCOPE_VALUES = SCOPE_VALUES
GroupPage.GROWTH_VALUES = GROWTH_VALUES
GroupPage.HEALTH_MODES = HEALTH_MODES
GroupPage.TEXT_MODES = TEXT_MODES
GroupPage.ANCHORS = ANCHORS
GroupPage.AURA_ANCHORS = AURA_ANCHORS
GroupPage.GF_RENDERERS = GF_RENDERERS
GroupPage.GF_AURA_FILTERS = GF_AURA_FILTERS
GroupPage.GF_AURA_ORG = GF_AURA_ORG
GroupPage.SORT_MODES = SORT_MODES
GroupPage.GF_BAR_MODES = GF_BAR_MODES
GroupPage.SIMPLE_TEXTURES = SIMPLE_TEXTURES
GroupPage.GF_ANCHOR_TO = GF_ANCHOR_TO
GroupPage.GF_ANCHOR_POINTS = GF_ANCHOR_POINTS
GroupPage.TOOLTIP_MODES = TOOLTIP_MODES
GroupPage.TOOLTIP_MODIFIERS = TOOLTIP_MODIFIERS
GroupPage.STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS
GroupPage.GF_STATUS_ICON_SPECS = GF_STATUS_ICON_SPECS
GroupPage.GF_STATUS_ICON_VALUES = GF_STATUS_ICON_VALUES
GroupPage.PLACED_INDICATOR_TYPES = PLACED_INDICATOR_TYPES
GroupPage.FRAME_EFFECT_TYPES = FRAME_EFFECT_TYPES
GroupPage.SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES
GroupPage.CI_SLOT_VALUES = CI_SLOT_VALUES
GroupPage.CI_SLOT_DEFAULTS = CI_SLOT_DEFAULTS
GroupPage.DISPEL_OVERLAY_STYLES = DISPEL_OVERLAY_STYLES
GroupPage.DEBUFF_STRIPE_EDGES = DEBUFF_STRIPE_EDGES
GroupPage.GF = GF
GroupPage.RefreshGFPreview = RefreshGFPreview
GroupPage.QueueGF = QueueGF
GroupPage.ScopeSection = ScopeSection
GroupPage.BindScopeToggle = BindScopeToggle
GroupPage.BindScopeSlider = BindScopeSlider
GroupPage.BindScopeDropdown = BindScopeDropdown
GroupPage.BuildGrowthDirectionTiles = BuildGrowthDirectionTiles
GroupPage.BuildRoleOrderRows = BuildRoleOrderRows
GroupPage.AurasRoot = AurasRoot
GroupPage.AuraGroup = AuraGroup
GroupPage.PrivateAuras = PrivateAuras
GroupPage.SpellIndicators = SpellIndicators
GroupPage.IconStyleValues = IconStyleValues
GroupPage.CurrentGFStatusSpec = CurrentGFStatusSpec
GroupPage.QueueSpellIndicators = QueueSpellIndicators
GroupPage.SpellSpecValues = SpellSpecValues
GroupPage.SpellTrackedSpecValues = SpellTrackedSpecValues
GroupPage.CurrentSpellMultiSpec = CurrentSpellMultiSpec
GroupPage.EffectiveSpellSpec = EffectiveSpellSpec
GroupPage.SpellAuraValues = SpellAuraValues
GroupPage.CurrentSpellAura = CurrentSpellAura
GroupPage.CurrentSpellConfig = CurrentSpellConfig
GroupPage.PlacedConfig = PlacedConfig
GroupPage.FrameEffectConfig = FrameEffectConfig
GroupPage.CICategoryValues = CICategoryValues
GroupPage.CIFilterValues = CIFilterValues
GroupPage.CIModeValues = CIModeValues
GroupPage.CurrentCISlot = CurrentCISlot
GroupPage.CICustomConfig = CICustomConfig
GroupPage.BindNestedToggle = BindNestedToggle
GroupPage.BindNestedSlider = BindNestedSlider
GroupPage.BindNestedDropdown = BindNestedDropdown
GroupPage.SetOptionEnabled = SetOptionEnabled
GroupPage.SetOptionsEnabled = SetOptionsEnabled