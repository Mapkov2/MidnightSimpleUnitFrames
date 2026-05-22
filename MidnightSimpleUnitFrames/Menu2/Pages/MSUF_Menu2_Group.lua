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
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_BG = { 0.105, 0.082, 0.052, 0.44 }
local WARNING_ARROW = { 0.88, 0.62, 0.22, 1 }
local WARNING_NOTICE_BG = { 0.105, 0.082, 0.052, 0.34 }
local WARNING_NOTICE_TOP = { 0.48, 0.36, 0.20, 0.55 }
local WARNING_NOTICE_BOTTOM = { 0.28, 0.21, 0.12, 0.48 }

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

local BLIZZARD_FALLBACK_VALUES = {
    { value = "AUTO", text = "Blizzard default" },
    { value = "SHOW", text = "Force Blizzard frames" },
    { value = "NONE", text = "Hide all frames" },
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
    { value = "MAXPERCENT", text = "Max / Percent" },
    { value = "PERCENTCUR", text = "Percent / Current" },
    { value = "PERCENTMAX", text = "Percent / Max" },
    { value = "PERCENTCURMAX", text = "Percent / Current / Max" },
}

local DELIMITER_VALUES = {
    { value = " ", text = "Space" },
    { value = "  ", text = "Double Space" },
    { value = " / ", text = "/" },
    { value = " - ", text = "-" },
    { value = " : ", text = ":" },
    { value = " | ", text = "|" },
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

local function SIMPLE_TEXTURES()
    local ui = ns and ns.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then
        return ui.StatusBarTextureItems("Follow Global Style")
    end
    return {
        { value = "", text = "Follow Global Style" },
        { value = "Blizzard", text = "Blizzard", texture = "Interface\\TargetingFrame\\UI-StatusBar" },
        { value = "Solid", text = "Solid", texture = "Interface\\Buttons\\WHITE8X8" },
        { value = "Flat", text = "Flat", texture = "Interface\\Buttons\\WHITE8X8" },
        { value = "MSUF Smooth v2", text = "MSUF Smooth v2", texture = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\Smoothv2.tga" },
    }
end

local GF_ANCHOR_TO = {
    { value = "FREE", text = "Free (UIParent)" },
    { value = "player", text = "Player Frame" },
    { value = "target", text = "Target Frame" },
    { value = "targettarget", text = "Target of Target" },
    { value = "focustarget", text = "Focus Target" },
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
    { value = "roleIcon", text = "Role Icon", enabled = "roleIcon", iconStyle = "roleIconStyle", size = "roleIconSize", anchor = "roleIconAnchor", x = "roleIconX", y = "roleIconY", layer = "roleIconLayer", defaultSize = 12, defaultAnchor = "TOPLEFT", defaultLayer = 1 },
    { value = "leaderIcon", text = "Leader", enabled = "leaderIcon", iconStyle = "leaderIconStyle", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconX", y = "leaderIconY", layer = "leaderIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2 },
    { value = "assistIcon", text = "Assist", enabled = "assistIcon", iconStyle = "assistIconStyle", size = "assistIconSize", anchor = "assistIconAnchor", x = "assistIconX", y = "assistIconY", layer = "assistIconLayer", defaultSize = 12, defaultAnchor = "TOPRIGHT", defaultLayer = 2 },
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
    if type(M.SyncGFPagePreviewForKey) == "function" then M.SyncGFPagePreviewForKey(M.activeKey, true) end
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
    if InCombatLockdown and InCombatLockdown() then
        if rebuild and type(gf.RebuildAll) == "function" then gf.RebuildAll() end
        if geometry then gf._pendingRefreshGeometry = true end
        if font or visual then gf._pendingRefreshVisuals = true end
        RefreshGFPreview()
        return
    end
    if rebuild and type(gf.RebuildAll) == "function" then
        gf.RebuildAll()
        RefreshGFPreview()
        return
    end
    if geometry then
        if type(gf.RefreshGeometry) == "function" then gf.RefreshGeometry() end
    end
    if font and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
    if visual then
        if type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals() end
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
    local function Write()
        local conf = Conf(kind)
        if conf[key] == value then return false end
        conf[key] = value
        QueueGF(kind, mode or "visual")
        return true
    end
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
        return M.CaptureHistory("Group " .. tostring(key), "group:" .. tostring(kind) .. ":" .. tostring(key), Write)
    end
    return Write()
end

local function Bool(kind, key, default)
    local value = Val(kind, key, default and true or false)
    return value and true or false
end

local function Num(kind, key, default)
    return tonumber(Val(kind, key, default)) or default or 0
end

local function CurrentScope()
    return M.gfScope or "party"
end

local function ScopeLabel(kind)
    if kind == "mythicraid" then return M.Tr("Mythic Raid") end
    if kind == "raid" then return M.Tr("Raid") end
    return M.Tr("Party")
end

local function ScopeShortLabel(kind)
    if kind == "mythicraid" then return M.Tr("Mythic") end
    return ScopeLabel(kind)
end

local GF_COPY_EXCLUDE = {
    offsetX = true,
    offsetY = true,
    point = true,
    positionMode = true,
    _hlMigrated = true,
}

local GF_COPY_CATEGORIES = {
    { key = "general", label = "General", keys = { "enabled", "blizzardFallbackMode", "showPlayer", "showSolo", "width", "height", "spacing", "growth", "groupFilter", "sortMode", "sortByRole", "roleOrder", "playerFirstInRole", "unitsPerColumn", "maxColumns", "preserveRaidGroups", "reverseFill", "smoothFill", "hideInClientScene", "hideOfflineEnabled", "hideOfflineInCombat", "hideOfflineDelay", "tooltipMode", "tooltipModifier", "frameScaleMode", "frameScaleManual", "scaleAt10", "scaleAt20", "scaleAt25", "scaleOver25" } },
    { key = "health", label = "Health & Bars", keys = { "gfBarMode", "healthColorMode", "healthCustomR", "healthCustomG", "healthCustomB", "gfDarkR", "gfDarkG", "gfDarkB", "gfUnifiedR", "gfUnifiedG", "gfUnifiedB", "barTexture", "barBgTexture", "powerBarEnabled", "powerHeight", "showPower", "showPowerText", "powerTextLeft", "powerTextCenter", "powerTextRight", "powerTextDelimiter", "powerFontSize", "powerOffsetX", "powerOffsetY", "powerTextLayer", "powerSmoothFill", "powerShowTank", "powerShowHealer", "powerShowDamager", "dispelOverlayEnabled", "dispelOverlayStyle", "dispelOverlayOnHealth", "dispelOverlayAlpha", "dispelOverlayTrigger" } },
    { key = "text", label = "Text & Name", keys = { "showName", "hideNameOnDeadOffline", "nameFontSize", "nameAnchor", "nameOffsetX", "nameOffsetY", "nameTextLayer", "nameColorMode", "nameColorR", "nameColorG", "nameColorB", "nameShortenEnabled", "nameClipSide", "nameMaxChars", "nameNoEllipsis", "showHPText", "hpFontSize", "textLeft", "textCenter", "textRight", "textDelimiter", "hpTextReverse", "hpOffsetX", "hpOffsetY", "textLayer" } },
    { key = "font", label = "Font Override", keys = { "fontOverride", "fontOutline", "useGlobalFontColor", "fontR", "fontG", "fontB" } },
    { key = "border", label = "Background & Opacity", keys = { "bgR", "bgG", "bgB", "bgA", "hpBarAlpha", "hpBgAlpha", "hpTextIgnoreAlpha", "alphaPreserveHPColor" } },
    { key = "range", label = "Range Fade", keys = { "rangeFadeEnabled", "rangeFadeAlpha", "rangeFadeLayerMode", "offlineAlpha", "alphaPreserveHPColor" } },
    { key = "indicators", label = "Indicators & Status Icons", keys = { "showGroupNumber", "groupNumberSize", "groupNumberAnchor", "groupNumberX", "groupNumberY", "groupBorderEnabled", "groupBorderSize", "groupBorderPadding", "groupBorderR", "groupBorderG", "groupBorderB", "groupBorderA", "iconStyle", "useMidnightIcons", "roleIconStyle", "leaderIconStyle", "assistIconStyle", "statusText", "statusTextSize", "statusTextAnchor", "statusOffsetX", "statusOffsetY", "statusTextLayer", "statusGhostText", "statusGhostTextSize", "statusGhostTextAnchor", "statusGhostOffsetX", "statusGhostOffsetY", "statusGhostTextLayer", "statusAFKText", "statusAFKTextSize", "statusAFKTextAnchor", "statusAFKOffsetX", "statusAFKOffsetY", "statusAFKTextLayer" }, prefix = { "si_", "statusIcon", "indicator" } },
    { key = "auras", label = "Auras", tables = { "auras" } },
    { key = "highlight", label = "Highlight & Aggro", prefix = { "hl", "dispel" } },
    { key = "dstripe", label = "Debuff Stripe", prefix = { "debuffStripe" } },
    { key = "features", label = "Corner/Spell/Private", keys = { "ciEnabled", "ciAlpha" }, tables = { "spellIndicators", "privateAuras" }, prefix = { "ci" } },
}

local function DeepCopy(value)
    local gf = GF()
    if gf and type(gf._DeepCopyTable) == "function" then return gf._DeepCopyTable(value) end
    if type(_G.MSUF_DeepCopy) == "function" then return _G.MSUF_DeepCopy(value) end
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v) end
    return out
end

local function NewGFCopyScopes()
    local scopes = {}
    for i = 1, #GF_COPY_CATEGORIES do
        scopes[GF_COPY_CATEGORIES[i].key] = true
    end
    return scopes
end

local function CopyGroupSettings(srcKind, dstKind, scopes)
    local srcConf = Conf(srcKind)
    local dstConf = Conf(dstKind)
    if not (srcConf and dstConf and srcKind and dstKind) or srcKind == dstKind then return false end

    scopes = (type(scopes) == "table") and scopes or NewGFCopyScopes()
    local allowKeys, allowPrefixes, allowTables = {}, {}, {}
    for i = 1, #GF_COPY_CATEGORIES do
        local cat = GF_COPY_CATEGORIES[i]
        if scopes[cat.key] then
            if cat.keys then
                for j = 1, #cat.keys do allowKeys[cat.keys[j]] = true end
            end
            if cat.prefix then
                for j = 1, #cat.prefix do allowPrefixes[#allowPrefixes + 1] = cat.prefix[j] end
            end
            if cat.tables then
                for j = 1, #cat.tables do allowTables[cat.tables[j]] = true end
            end
        end
    end

    for key, value in pairs(srcConf) do
        if not GF_COPY_EXCLUDE[key] then
            local copy = allowKeys[key] or allowTables[key]
            if (not copy) and type(key) == "string" then
                for i = 1, #allowPrefixes do
                    local prefix = allowPrefixes[i]
                    if key:sub(1, #prefix) == prefix then
                        copy = true
                        break
                    end
                end
            end
            if copy then dstConf[key] = DeepCopy(value) end
        end
    end

    QueueGF(dstKind, "rebuild")
    RefreshGFPreview()
    return true
end

local function RefreshContext(ctx)
    if not (ctx and ctx.refreshers) then return end
    for i = 1, #ctx.refreshers do
        local fn = ctx.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

local function SetSectionHeaderStatus(sec, opts)
    local entry = sec and sec._msuf2CollapsibleEntry
    if not entry then return end

    T.ApplyCollapseVisual(entry.arrow, entry.hint, entry.open)
    if entry.headerBg and entry.headerBg.SetColorTexture then
        entry.headerBg:SetColorTexture(0.060, 0.070, 0.130, 0.48)
    end
    if entry.label and entry.label.SetTextColor and T.colors and T.colors.text then
        local c = T.colors.text
        entry.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    opts = opts or {}
    if opts.bg and entry.headerBg and entry.headerBg.SetColorTexture then
        local bg = opts.bg
        entry.headerBg:SetColorTexture(bg[1] or 0.060, bg[2] or 0.070, bg[3] or 0.130, bg[4] or 0.48)
    end
    if opts.labelColor and entry.label and entry.label.SetTextColor then
        local c = opts.labelColor
        entry.label:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if opts.arrowColor and entry.arrow and entry.arrow.SetVertexColor then
        local c = opts.arrowColor
        entry.arrow:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if entry.hint and entry.hint.SetText then
        if opts.hint ~= nil then
            entry.hint:SetText(opts.hint)
            if opts.hintColor and entry.hint.SetTextColor then
                local c = opts.hintColor
                entry.hint:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
        else
            entry.hint:SetText(entry.open and "" or "click to expand")
        end
    end
end

local function CreateSectionNotice(sec, topY, buttonLabel, buttonWidth)
    local notice = CreateFrame("Frame", nil, sec)
    notice:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, topY)
    notice:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, topY)
    notice:SetHeight(24)
    notice._msuf2GroupFrameGateAlwaysEnabled = true

    local bg = notice:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.018, 0.040, 0.088, 0.30)
    local top = notice:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(0.16, 0.34, 0.66, 0.55)
    local bottom = notice:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(0.10, 0.20, 0.38, 0.48)

    local text = T.Font(notice, "GameFontDisableSmall", "", T.colors.dim)
    text:SetPoint("LEFT", notice, "LEFT", 10, 0)
    text:SetJustifyH("LEFT")

    local button
    if buttonLabel and buttonLabel ~= "" then
        button = (W.StyleTopActionButton and W.StyleTopActionButton(T.Button(notice, buttonLabel, buttonWidth or 92, 20))) or T.Button(notice, buttonLabel, buttonWidth or 92, 20)
        button:SetPoint("RIGHT", notice, "RIGHT", -2, 0)
        button._msuf2GroupFrameGateAlwaysEnabled = true
        text:SetPoint("RIGHT", notice, "RIGHT", -(buttonWidth or 92) - 18, 0)
    else
        text:SetPoint("RIGHT", notice, "RIGHT", -10, 0)
    end

    function notice:SetTone(kind)
        if kind == "warning" then
            bg:SetColorTexture(WARNING_NOTICE_BG[1], WARNING_NOTICE_BG[2], WARNING_NOTICE_BG[3], WARNING_NOTICE_BG[4])
            top:SetColorTexture(WARNING_NOTICE_TOP[1], WARNING_NOTICE_TOP[2], WARNING_NOTICE_TOP[3], WARNING_NOTICE_TOP[4])
            bottom:SetColorTexture(WARNING_NOTICE_BOTTOM[1], WARNING_NOTICE_BOTTOM[2], WARNING_NOTICE_BOTTOM[3], WARNING_NOTICE_BOTTOM[4])
            if text.SetTextColor then text:SetTextColor(WARNING_HINT[1], WARNING_HINT[2], WARNING_HINT[3], WARNING_HINT[4]) end
        else
            bg:SetColorTexture(0.018, 0.040, 0.088, 0.30)
            top:SetColorTexture(0.16, 0.34, 0.66, 0.55)
            bottom:SetColorTexture(0.10, 0.20, 0.38, 0.48)
            if text.SetTextColor then text:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1) end
        end
    end

    function notice:SetMessage(message, tone)
        self:SetTone(tone)
        text:SetText(tostring(message or ""))
    end

    notice:Hide()
    return notice, text, button
end

local function ScopeSection(ctx, builder)
    local compactTop = (tonumber(builder.width) or 0) < 600
    local h = compactTop and 72 or 40
    local sec = CreateFrame("Frame", nil, builder.parent)
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(builder.width, h)
    sec._msuf2Width = builder.width

    builder.y = builder.y - h - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end

    local function ApplyTopButtonVisual(btn, hover)
        local bg = btn._msuf2TopActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
        local br = btn._msuf2TopActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
        local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
        local mul = hover and 1.06 or 1
        if btn._msuf2Fill then btn._msuf2Fill:SetVertexColor(min(bg[1] * mul, 1), min(bg[2] * mul, 1), min(bg[3] * mul, 1), bg[4] or 1) end
        if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(min(br[1] * mul, 1), min(br[2] * mul, 1), min(br[3] * mul, 1), br[4] or 1) end
        if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
    end

    local function MakeTopButton(parent, text, width, opts)
        opts = opts or {}
        local btn = T.Button(parent, text, width, 24)
        btn._msuf2TopBg = opts.bg or { 0.018, 0.028, 0.058, 0.95 }
        btn._msuf2TopBorder = opts.border or { 0.082, 0.125, 0.245, 0.66 }
        btn._msuf2TopText = opts.textColor or { 0.82, 0.90, 1.00, 1 }
        btn._msuf2TopHoverBg = opts.hoverBg or { 0.026, 0.040, 0.078, 0.97 }
        btn._msuf2TopHoverBorder = opts.hoverBorder or { 0.125, 0.220, 0.430, 0.80 }
        btn._msuf2TopActiveBg = opts.activeBg or { 0.050, 0.105, 0.245, 0.98 }
        btn._msuf2TopActiveBorder = opts.activeBorder or { 0.200, 0.420, 0.820, 0.92 }
        btn._msuf2TopActiveText = opts.activeTextColor or { 0.94, 0.98, 1.00, 1 }
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
        end
        btn.SetActive = function(self, active)
            self._msuf2TopActive = active and true or false
            ApplyTopButtonVisual(self)
        end
        btn.SetEnabled = function(self, enabled)
            if enabled then
                if self.Enable then self:Enable() end
            elseif self.Disable then
                self:Disable()
            end
            ApplyTopButtonVisual(self)
        end
        btn:SetScript("OnEnter", function(self) ApplyTopButtonVisual(self, true) end)
        btn:SetScript("OnLeave", function(self) ApplyTopButtonVisual(self) end)
        btn:SetScript("OnEnable", function(self) ApplyTopButtonVisual(self) end)
        btn:SetScript("OnDisable", function(self) ApplyTopButtonVisual(self) end)
        ApplyTopButtonVisual(btn)
        return btn
    end

    local function IsEditModeActive()
        if type(_G.MSUF_IsMSUFEditModeActive) == "function" then return _G.MSUF_IsMSUFEditModeActive() and true or false end
        local em2 = _G.MSUF_EM2
        if em2 and em2.State and type(em2.State.IsActive) == "function" then return em2.State.IsActive() and true or false end
        return _G.MSUF_UnitEditModeActive == true
    end

    local function AddScopeTooltip(frame, title, text)
        if not (frame and frame.HookScript) then return end
        frame:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
            if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        frame:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    local function ScopeTooltipText(kind)
        if kind == "party" then
            return "Use this scope for normal 5-player party layouts."
        elseif kind == "raid" then
            return "Use this scope for flexible raid layouts. Mythic Raid has its own scope."
        elseif kind == "mythicraid" then
            return "Use this scope for 20-player Mythic Raid layouts."
        end
        return ""
    end

    local function SelectScope(kind)
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("gfScope", kind or "party")
        else
            M.gfScope = kind or "party"
        end
        local gf = GF()
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(M.gfScope) end
        if type(M.SyncGFPagePreviewForKey) == "function" then M.SyncGFPagePreviewForKey(M.activeKey) end
        if gf and type(gf.PreviewScopeChanged) == "function" then
            gf.PreviewScopeChanged()
        else
            RefreshGFPreview()
        end
        RefreshContext(ctx)
    end

    local editing = T.Font(sec, "GameFontNormalSmall", M.Tr("Editing:"), { 0.72, 0.82, 1.00, 1 })
    editing:SetPoint("TOPLEFT", sec, "TOPLEFT", 8, -15)

    local scopeBtns = {}
    local previous
    for i = 1, #SCOPE_VALUES do
        local info = SCOPE_VALUES[i]
        local width = (info.value == "mythicraid") and 68 or 56
        local btn = MakeTopButton(sec, ScopeShortLabel(info.value), width, {
            bg = { 0.026, 0.040, 0.084, 0.95 },
            border = { 0.095, 0.165, 0.330, 0.62 },
            activeBg = { 0.050, 0.110, 0.255, 0.98 },
            activeBorder = { 0.200, 0.430, 0.850, 0.92 },
        })
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", editing, "RIGHT", 8, 2)
        end
        btn:SetScript("OnClick", function() SelectScope(info.value) end)
        AddScopeTooltip(btn, ScopeShortLabel(info.value), ScopeTooltipText(info.value))
        scopeBtns[info.value] = btn
        previous = btn
    end

    local actionY = compactTop and -42 or -10
    local copy = MakeTopButton(sec, M.Tr("Copy To"), compactTop and 82 or 86)
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -8, actionY)
    local edit = MakeTopButton(sec, M.Tr("MSUF Edit Mode"), compactTop and 118 or 128)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    local reset = MakeTopButton(sec, M.Tr("Reset Scopes"), compactTop and 94 or 104, {
        bg = { 0.070, 0.026, 0.034, 0.94 },
        border = { 0.340, 0.090, 0.110, 0.82 },
        textColor = { 1.00, 0.82, 0.82, 1 },
        hoverBg = { 0.090, 0.035, 0.045, 0.96 },
        hoverBorder = { 0.420, 0.120, 0.140, 0.90 },
        activeBg = { 0.070, 0.026, 0.034, 0.94 },
        activeBorder = { 0.340, 0.090, 0.110, 0.82 },
        activeTextColor = { 1.00, 0.82, 0.82, 1 },
    })
    reset:SetPoint("RIGHT", edit, "LEFT", -8, 0)
    AddScopeTooltip(reset, "Reset Scopes", "Resets Party, Raid, and Mythic Raid Group Frame settings for the active profile.")
    AddScopeTooltip(edit, "MSUF Edit Mode", "Drag frames to move them. Group aura handles can be selected in previews; Blizzard-controlled aura blocks cannot be dragged.")

    local function RefreshTop()
        local current = CurrentScope()
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            if scopeBtns[info.value] and scopeBtns[info.value].SetActive then scopeBtns[info.value]:SetActive(current == info.value) end
        end
        if edit.SetText then edit:SetText(IsEditModeActive() and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode")) end
    end

    if not StaticPopupDialogs["MSUF2_GF_RESET_ALL_CONFIRM"] then
        StaticPopupDialogs["MSUF2_GF_RESET_ALL_CONFIRM"] = {
            text = M.Tr("Reset all Group Frame settings to defaults?\n\nThis resets Party, Raid, and Mythic Raid Group Frames for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically."),
            button1 = YES or M.Tr("Yes"),
            button2 = NO or M.Tr("No"),
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopupDialogs["MSUF2_GF_RESET_ALL_CONFIRM"].OnAccept = function()
        local function ResetAllGroupFrames()
            local gf = GF()
            if gf and type(gf.ResetAllToDefaults) == "function" and gf.ResetAllToDefaults() then
                RefreshGFPreview()
                RefreshContext(ctx)
                print(M.Tr("|cffffd700MSUF:|r Group Frames reset to defaults."))
            end
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Reset Group Frames", "group:resetAll", ResetAllGroupFrames)
        else
            ResetAllGroupFrames()
        end
    end
    reset:SetScript("OnClick", function()
        if StaticPopup_Show then StaticPopup_Show("MSUF2_GF_RESET_ALL_CONFIRM") end
    end)

    edit:SetScript("OnClick", function()
        if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return end
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
            return
        end
        local active = IsEditModeActive()
        local key = "gf_" .. CurrentScope()
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active, key)
        elseif _G.MSUF_EM2 and _G.MSUF_EM2.State then
            if active and type(_G.MSUF_EM2.State.Exit) == "function" then
                _G.MSUF_EM2.State.Exit("msuf2_group")
            elseif (not active) and type(_G.MSUF_EM2.State.Enter) == "function" then
                _G.MSUF_EM2.State.Enter(key)
            end
        end
        local function RefreshAfterToggle()
            RefreshTop()
            if type(M.SyncGFPagePreviewForKey) == "function" then M.SyncGFPagePreviewForKey(M.activeKey) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshAfterToggle) else RefreshAfterToggle() end
    end)

    M.gfCopyScopes = (type(M.gfCopyScopes) == "table") and M.gfCopyScopes or NewGFCopyScopes()
    local copyPopup
    local function ShowCopyPopup(anchor)
        if copyPopup and copyPopup:IsShown() then copyPopup:Hide(); return end
        if not copyPopup then
            copyPopup = CreateFrame("Frame", nil, UIParent, T.Template and T.Template() or nil)
            copyPopup:SetSize(430, 334)
            if M.ApplyMenuPopupFramePriority then
                M.ApplyMenuPopupFramePriority(copyPopup)
            elseif M.ApplyMenuFramePriority then
                M.ApplyMenuFramePriority(copyPopup, M.MENU_POPUP_FRAME_LEVEL or 120)
            else
                copyPopup:SetFrameStrata("FULLSCREEN_DIALOG")
                copyPopup:SetFrameLevel(120)
            end
            copyPopup:EnableMouse(true)
            if copyPopup.SetBackdrop then
                copyPopup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
                copyPopup:SetBackdropColor(0.014, 0.024, 0.050, 0.985)
                copyPopup:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.80)
            end

            local title = T.Font(copyPopup, "GameFontNormal", "", T.colors.accent)
            title:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -12)
            copyPopup._title = title

            local destLabel = T.Font(copyPopup, "GameFontDisableSmall", M.Tr("Destination"), T.colors.dim)
            destLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -40)

            local close = MakeTopButton(copyPopup, "x", 20, {
                bg = { 0.070, 0.026, 0.034, 0.94 },
                border = { 0.340, 0.090, 0.110, 0.82 },
                textColor = { 0.95, 0.70, 0.70, 1 },
                hoverBg = { 0.090, 0.035, 0.045, 0.96 },
                hoverBorder = { 0.420, 0.120, 0.140, 0.90 },
            })
            close:SetSize(20, 20)
            close:SetPoint("TOPRIGHT", copyPopup, "TOPRIGHT", -12, -9)
            close:SetScript("OnClick", function() copyPopup:Hide() end)

            copyPopup._targets = {}
            local tx = 16
            for i = 1, #SCOPE_VALUES do
                local info = SCOPE_VALUES[i]
                local width = (info.value == "mythicraid") and 70 or 58
                local btn = MakeTopButton(copyPopup, ScopeShortLabel(info.value), width, {
                    bg = { 0.020, 0.048, 0.105, 0.96 },
                    border = { 0.070, 0.160, 0.330, 0.72 },
                    activeBg = { 0.050, 0.110, 0.240, 0.98 },
                    activeBorder = { 0.135, 0.300, 0.600, 0.86 },
                })
                btn:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", tx, -58)
                btn:SetScript("OnClick", function()
                    local function RunCopy()
                        if CopyGroupSettings(CurrentScope(), info.value, M.gfCopyScopes) then
                            RefreshContext(ctx)
                        end
                    end
                    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                        M.CaptureHistory("Copy Group Settings", "group:copy:" .. tostring(CurrentScope()) .. ":" .. tostring(info.value), RunCopy)
                    else
                        RunCopy()
                    end
                    copyPopup:Hide()
                end)
                copyPopup._targets[info.value] = btn
                tx = tx + width + 6
            end

            local catLabel = T.Font(copyPopup, "GameFontDisableSmall", M.Tr("Copy categories"), T.colors.dim)
            catLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -90)
            copyPopup._checks = {}
            for i = 1, #GF_COPY_CATEGORIES do
                local cat = GF_COPY_CATEGORIES[i]
                local col = (i > 6) and 1 or 0
                local row = (i - 1) % 6
                local cb = W.SwitchAt(copyPopup, cat.label, 16 + col * 205, -110 - row * 28, 150)
                cb:SetChecked(M.gfCopyScopes[cat.key] == true)
                cb:SetScript("OnClick", function(self) M.gfCopyScopes[cat.key] = self:GetChecked() and true or false end)
                copyPopup._checks[i] = cb
            end

            local allBtn = MakeTopButton(copyPopup, M.Tr("All"), 48)
            allBtn:SetPoint("BOTTOMLEFT", copyPopup, "BOTTOMLEFT", 16, 12)
            allBtn:SetScript("OnClick", function()
                for i = 1, #GF_COPY_CATEGORIES do
                    local cat = GF_COPY_CATEGORIES[i]
                    M.gfCopyScopes[cat.key] = true
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(true) end
                end
            end)
            local noneBtn = MakeTopButton(copyPopup, M.Tr("None"), 58)
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
            noneBtn:SetScript("OnClick", function()
                for i = 1, #GF_COPY_CATEGORIES do
                    local cat = GF_COPY_CATEGORIES[i]
                    M.gfCopyScopes[cat.key] = false
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(false) end
                end
            end)
        end

        local src = CurrentScope()
        if copyPopup._title then
            copyPopup._title:SetText(M.Format(M.Tr("Copy from %s"), ScopeLabel(src)))
        end
        for i = 1, #GF_COPY_CATEGORIES do
            if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(M.gfCopyScopes[GF_COPY_CATEGORIES[i].key] == true) end
        end
        local nextX = 16
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            local btn = copyPopup._targets[info.value]
            if btn then
                local shown = info.value ~= src
                btn:SetShown(shown)
                if shown then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", nextX, -58)
                    nextX = nextX + btn:GetWidth() + 6
                end
            end
        end
        if M.ApplyMenuPopupFramePriority then
            M.ApplyMenuPopupFramePriority(copyPopup)
        elseif M.ApplyMenuFramePriority then
            M.ApplyMenuFramePriority(copyPopup, M.MENU_POPUP_FRAME_LEVEL or 120)
        end
        copyPopup:ClearAllPoints()
        copyPopup:SetPoint("TOPRIGHT", anchor or copy, "BOTTOMRIGHT", 0, -6)
        copyPopup:Show()
    end
    copy:SetScript("OnClick", function(self) ShowCopyPopup(self) end)
    sec:SetScript("OnHide", function() if copyPopup then copyPopup:Hide() end end)

    M.AddRefresher(ctx, RefreshTop)
    RefreshTop()
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

local function BuildGrowthDirectionTiles(ctx, section, opts)
    if not section then return nil end

    opts = opts or {}
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -38
    local tileW, tileH, gap = opts.tileWidth or 64, opts.tileHeight or 64, opts.gap or 6
    if opts.advanceCursor ~= false then
        section._msuf2CursorY = y - tileH - 40
    end

    local label = T.Font(section, "GameFontNormalSmall", M.Tr("Growth Direction"), T.colors.accent)
    label:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)

    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 20)
    holder:SetSize((tileW * 4) + (gap * 3), tileH)
    holder._msuf2Label = label

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
            btn._arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
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
                GameTooltip:AddLine(M.Format(M.Tr("Growth: %s"), M.Tr(info.text or "")), 1, 1, 1)
                GameTooltip:AddLine(M.Tr("Click to set group frame growth direction."), 0.72, 0.76, 0.86)
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

local function BuildRoleOrderRows(ctx, section, opts)
    if not section then return nil end

    opts = opts or {}
    local rowW, rowH, rowGap = opts.width or 220, 22, 4
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -146
    local listY = y
    if opts.hint or opts.title then
        local title = T.Font(section, "GameFontNormalSmall", opts.title or "Role Priority", T.colors.text)
        title:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
        title:SetWidth(rowW)
        title:SetJustifyH("LEFT")
        local hint = T.Font(section, "GameFontDisableSmall", opts.hint or "Drag roles to reorder.", T.colors.dim)
        hint:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 16)
        hint:SetWidth(rowW + 80)
        hint:SetJustifyH("LEFT")
        listY = y - 38
    end
    if opts.advanceCursor ~= false then
        section._msuf2CursorY = listY - (#ROLE_SORT_DEFS * (rowH + rowGap)) - 10
    end

    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, listY)
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
        local kind = CurrentScope()
        local function WriteOrder()
            local ordered = {}
            for i = 1, #rows do ordered[#ordered + 1] = rows[i] end
            table.sort(ordered, function(a, b) return (a.slotIndex or 0) < (b.slotIndex or 0) end)
            local parts = {}
            for i = 1, #ordered do parts[#parts + 1] = ordered[i].key end
            local conf = Conf(kind)
            conf.roleOrder = table.concat(parts, ",")
            QueueGF(kind, "rebuild")
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Role Priority Order", "group:roleOrder:" .. tostring(kind), WriteOrder)
        else
            WriteOrder()
        end
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
                GameTooltip:AddLine(M.Tr(def.label or ""), 1, 1, 1)
                GameTooltip:AddLine(M.Tr("Drag to change role priority."), 0.72, 0.76, 0.86)
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
        { value = "CLASSIC", text = "Classic" },
        { value = "MIDNIGHT", text = "Midnight" },
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
    if not M.gfStatusIconSelection then
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("gfStatusIconSelection", "roleIcon")
        else
            M.gfStatusIconSelection = "roleIcon"
        end
    end
    for i = 1, #GF_STATUS_ICON_SPECS do
        local spec = GF_STATUS_ICON_SPECS[i]
        if spec.value == M.gfStatusIconSelection then return spec end
    end
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("gfStatusIconSelection", GF_STATUS_ICON_SPECS[1].value)
    else
        M.gfStatusIconSelection = GF_STATUS_ICON_SPECS[1].value
    end
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
    if create and type(cfg.placed) ~= "table" then
        cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true }
    end
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
    if not M.gfCornerSlotSelection then
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("gfCornerSlotSelection", "TL")
        else
            M.gfCornerSlotSelection = "TL"
        end
    end
    for i = 1, #CI_SLOT_VALUES do
        if CI_SLOT_VALUES[i].value == M.gfCornerSlotSelection then return M.gfCornerSlotSelection end
    end
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("gfCornerSlotSelection", "TL")
    else
        M.gfCornerSlotSelection = "TL"
    end
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
            local gp = M.GlobalPage
            if gp and type(gp.StopGroupDispelGlowForBlizzardConflict) == "function" then
                gp.StopGroupDispelGlowForBlizzardConflict(CurrentScope())
            end
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
            local gp = M.GlobalPage
            if gp and type(gp.StopGroupDispelGlowForBlizzardConflict) == "function" then
                gp.StopGroupDispelGlowForBlizzardConflict(CurrentScope())
            end
        end)
    return widget
end

local function SetOptionEnabled(control, enabled)
    W.SetControlEnabled(control, enabled)
end

local function SetOptionsEnabled(controls, enabled)
    W.SetControlsEnabled(controls, enabled)
end

local function ForEachGroupPageControl(parent, callback)
    if not (parent and parent.GetChildren and type(callback) == "function") then return end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child._msuf2ControlKind and not child._msuf2GroupFrameGateAlwaysEnabled then
            callback(child)
        end
        ForEachGroupPageControl(child, callback)
    end
end

local function ApplyScopeEnabledGate(ctx)
    local wrapper = ctx and ctx.wrapper
    if not wrapper then return end
    local scope = CurrentScope()
    local enabled = Bool(scope, "enabled", false)
    local gateKey = "groupFrameEnabled"
    ForEachGroupPageControl(wrapper, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
end

GroupPage.SCOPE_VALUES = SCOPE_VALUES
GroupPage.GROWTH_VALUES = GROWTH_VALUES
GroupPage.BLIZZARD_FALLBACK_VALUES = BLIZZARD_FALLBACK_VALUES
GroupPage.HEALTH_MODES = HEALTH_MODES
GroupPage.TEXT_MODES = TEXT_MODES
GroupPage.DELIMITER_VALUES = DELIMITER_VALUES
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
GroupPage.ApplyScopeEnabledGate = ApplyScopeEnabledGate
GroupPage.SetSectionHeaderStatus = SetSectionHeaderStatus
GroupPage.CreateSectionNotice = CreateSectionNotice
