local addonName, addonNS = ...
local ns = addonNS or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

ns.L = ns.L or (_G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(_, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local format = string.format
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local SYMBOL_MEDIA = MEDIA .. "Symbols\\"
local MASK_MEDIA = MEDIA .. "Masks\\"
local PREVIEW_ROUNDED_MASK = MASK_MEDIA .. "rounded_bar_4x.tga"
local PREVIEW_ROUNDED_EDGE = MASK_MEDIA .. "rounded_bar_edge_4x.tga"

local Preview = ns.UFPreview or {}
ns.UFPreview = Preview
_G.MSUF_UFPreview = Preview
local PreviewBaseEdgeColor
local PreviewHelpers = (ns.MSUF2 and ns.MSUF2.PreviewHelpers) or {}

local function MenuTheme()
    local m = ns and ns.MSUF2
    return m and m.Theme
end

local function ApplyPreviewBackdrop(frame, bg, border, fallback)
    local T = MenuTheme()
    if T and type(T.ApplyBackdrop) == "function" then
        T.ApplyBackdrop(frame, bg, border)
        return
    end
    if not (frame and frame.SetBackdrop) then return end
    fallback = fallback or {}
    frame:SetBackdrop(fallback.backdrop or {
        bgFile = TEX_W8,
        edgeFile = TEX_W8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local b = bg or fallback.bg or { 0.035, 0.043, 0.058, 0.96 }
    local e = border or fallback.border or { 0.19, 0.25, 0.34, 0.95 }
    frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
    frame:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
end

local UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet" }
local UNIT_SET = { player = true, target = true, targettarget = true, focustarget = true, focus = true, boss = true, pet = true }
local UNIT_LABELS = {
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    focustarget = "Focus Target",
    focus = "Focus",
    boss = "Boss Frames",
    pet = "Pet",
}
local UNIT_DATA = {
    player = { name = "MIDNIGHT", class = "ROGUE", hp = 0.72, power = 0.52, powerToken = "ENERGY", level = "80", elite = false, isPlayer = true, portraitTexture = "Interface\\ICONS\\Ability_Stealth" },
    target = { name = "Astral Warden", class = "MAGE", hp = 0.41, power = 0.68, powerToken = "MANA", level = "82", elite = true, reactionKind = "neutral", npcKind = "npcRegular", portraitTexture = "Interface\\ICONS\\Spell_Frost_FrostBolt02" },
    targettarget = { name = "Moonlit Tank", class = "WARRIOR", hp = 0.88, power = 0.36, powerToken = "RAGE", level = "80", elite = false, isPlayer = true, portraitTexture = "Interface\\ICONS\\Ability_Warrior_DefensiveStance" },
    focustarget = { name = "Marked Add", class = "WARRIOR", hp = 0.57, power = 0.24, powerToken = "RAGE", level = "81", elite = false, reactionKind = "enemy", npcKind = "npcMelee", portraitTexture = "Interface\\ICONS\\Ability_Warrior_Charge" },
    focus = { name = "Voidcaller", class = "WARLOCK", hp = 0.63, power = 0.81, powerToken = "MANA", level = "81", elite = true, reactionKind = "enemy", npcKind = "npcCaster", portraitTexture = "Interface\\ICONS\\Spell_Shadow_Metamorphosis" },
    boss = { name = "Boss Preview", class = "DEATHKNIGHT", hp = 0.55, power = 0.35, powerToken = "MANA", level = "??", elite = true, reactionKind = "enemy", npcKind = "npcBoss", portraitTexture = "Interface\\ICONS\\Achievement_Boss_LichKing" },
    pet = { name = "Companion", class = "HUNTER", hp = 0.79, power = 0.44, powerToken = "FOCUS", level = "80", elite = false, isPet = true, reactionKind = "friendly", portraitTexture = "Interface\\ICONS\\Ability_Hunter_BeastCall" },
}

local function PreviewRaidGroupNameAllowed(key)
    return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "focus"
end

local function PreviewRaidGroupNameText(conf)
    local style = conf and conf.raidGroupNameStyle
    if style == "BRACKET" then return "[2]" end
    if style == "NONE" then return "2" end
    return "(2)"
end

local function NormalizePreviewRaidGroupNameAnchor(anchor)
    if anchor == "NAMELEFT" or anchor == "NAMERIGHT"
        or anchor == "TOPLEFT" or anchor == "TOPRIGHT"
        or anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT"
        or anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM"
        or anchor == "LEFT" or anchor == "RIGHT" then
        return anchor
    end
    return "NAMERIGHT"
end

local TEXT_ANCHORS = {
    { key = "LEFT", label = "Left" },
    { key = "CENTER", label = "Center" },
    { key = "RIGHT", label = "Right" },
}
local HP_MODES = {
    { key = "PERCENT", label = "Percent" },
    { key = "CURRENT", label = "Current" },
    { key = "MAX", label = "Max" },
    { key = "DEFICIT", label = "Deficit" },
    { key = "CURMAX", label = "Current / Max" },
    { key = "CURPERCENT", label = "Current / Percent" },
    { key = "CURMAXPERCENT", label = "Current / Max / Percent" },
    { key = "MAXPERCENT", label = "Max / Percent" },
    { key = "PERCENTCUR", label = "Percent / Current" },
    { key = "PERCENTMAX", label = "Percent / Max" },
    { key = "PERCENTCURMAX", label = "Percent / Current / Max" },
    { key = "NONE", label = "None" },
}
local POWER_MODES = {
    { key = "CURRENT", label = "Current" },
    { key = "MAX", label = "Max" },
    { key = "CURMAX", label = "Current / Max" },
    { key = "PERCENT", label = "Percent" },
    { key = "CURPERCENT", label = "Current / Percent" },
    { key = "CURMAXPERCENT", label = "Current / Max / Percent" },
    { key = "NONE", label = "None" },
}
local SEP_ITEMS = {
    { key = "", label = "space" },
    { key = "-", label = "-" },
    { key = "/", label = "/" },
    { key = "\\", label = "\\" },
    { key = "|", label = "|" },
    { key = "<", label = "<" },
    { key = ">", label = ">" },
    { key = "~", label = "~" },
    { key = ":", label = ":" },
}
local PORTRAIT_MODE_ITEMS = {
    { key = "OFF", label = "Off" },
    { key = "LEFT", label = "Left" },
    { key = "RIGHT", label = "Right" },
}
local PORTRAIT_RENDER_ITEMS = {
    { key = "2D", label = "2D portrait" },
    { key = "CLASS", label = "Class portrait" },
}
local function PortraitClassItems()
    local PM = ns and ns.PortraitMedia
    local opts = (PM and PM.GetPackOptions and PM.GetPackOptions()) or {
        { value = "BLIZZARD", text = "Blizzard Class Icon" },
    }
    local items = {}
    for i = 1, #opts do
        local o = opts[i]
        items[#items + 1] = { key = o.value, label = o.text }
    end
    return items
end
local PORTRAIT_SHAPE_ITEMS = {
    { key = "SQUARE", label = "Square" },
    { key = "CIRCLE", label = "Circle" },
    { key = "ROUNDED", label = "Rounded" },
    { key = "DIAMOND", label = "Diamond" },
}
local PORTRAIT_BORDER_ITEMS = {
    { key = "NONE", label = "No border" },
    { key = "SOLID", label = "Solid" },
    { key = "CLASS_COLOR", label = "Class color" },
    { key = "REACTION", label = "Reaction color" },
    { key = "CUSTOM", label = "Custom color" },
}

local PORTRAIT_STYLE_DEFAULTS = {
    portraitRender = "2D",
    portraitClassStyle = "BLIZZARD",
    portraitShape = "SQUARE",
    portraitSizeOverride = 0,
    portraitOffsetX = 0,
    portraitOffsetY = 0,
    portraitBorderStyle = "NONE",
    portraitBorderThickness = 2,
    portraitBorderColorR = 1,
    portraitBorderColorG = 1,
    portraitBorderColorB = 1,
    portraitBorderColorA = 1,
    portraitBgEnabled = false,
    portraitBgColorR = 0.05,
    portraitBgColorG = 0.05,
    portraitBgColorB = 0.05,
    portraitBgColorA = 0.85,
    portraitFillBorder = false,
}

local function CanonKey(key)
    if key == "tot" then return "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then return "focustarget" end
    if type(key) == "string" and key:match("^boss%d+$") then return "boss" end
    if UNIT_SET[key] then return key end
    return "player"
end

local function EnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB()
    elseif ns and type(ns.MSUF_EnsureDB or ns.EnsureDB) == "function" then
        (ns.MSUF_EnsureDB or ns.EnsureDB)()
    end
    _G.MSUF_DB = _G.MSUF_DB or {}
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    for i = 1, #UNIT_KEYS do
        _G.MSUF_DB[UNIT_KEYS[i]] = _G.MSUF_DB[UNIT_KEYS[i]] or {}
    end
end

local function CurrentPanelKey(panel)
    local key = panel and panel._msufGetCurrentKey and panel._msufGetCurrentKey()
    if key == nil then key = panel and panel._msufLastApplyKey end
    return CanonKey(key)
end

local function UnitDB(key)
    EnsureDB()
    key = CanonKey(key)
    _G.MSUF_DB[key] = _G.MSUF_DB[key] or {}
    return _G.MSUF_DB[key], _G.MSUF_DB.general, key
end

local function SeedTextFromGeneral(db)
    if not db then return end
    if type(_G.MSUF_Bars_SeedTextFromGeneral) == "function" then
        _G.MSUF_Bars_SeedTextFromGeneral(db)
    else
        local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
        if db.hpTextMode == nil then db.hpTextMode = g.hpTextMode end
        if db.hpTextReverse == nil then db.hpTextReverse = g.hpTextReverse end
        if db.powerTextMode == nil then db.powerTextMode = g.powerTextMode end
        if db.textLeft == nil and db.textCenter == nil and db.textRight == nil then
            db.textLeft = "NONE"
            db.textCenter = "NONE"
            db.textRight = db.hpTextMode or g.hpTextMode or "CURPERCENT"
        end
        if db.powerTextLeft == nil and db.powerTextCenter == nil and db.powerTextRight == nil then
            db.powerTextLeft = "NONE"
            db.powerTextCenter = "NONE"
            db.powerTextRight = db.powerTextMode or g.powerTextMode or "CURPERCENT"
        end
        if db.hpTextSeparator == nil then db.hpTextSeparator = g.hpTextSeparator end
        if db.powerTextSeparator == nil then db.powerTextSeparator = g.powerTextSeparator end
    end
    if db.nameTextLayer == nil then db.nameTextLayer = 5 end
    if db.hpTextLayer == nil then db.hpTextLayer = 5 end
    if db.powerTextLayer == nil then db.powerTextLayer = 2 end
    if db.showRaidGroupInName == nil then db.showRaidGroupInName = false end
    if db.raidGroupNameAnchor == nil then db.raidGroupNameAnchor = "NAMERIGHT" end
    if db.raidGroupNameOffsetX == nil then db.raidGroupNameOffsetX = 3 end
    if db.raidGroupNameOffsetY == nil then db.raidGroupNameOffsetY = 0 end
    if db.raidGroupNameStyle == nil then db.raidGroupNameStyle = "PAREN" end
    db.hpPowerTextOverride = nil
end

local function NormalizeHpMode(mode)
    if type(_G.MSUF_NormalizeHpTextMode) == "function" then return _G.MSUF_NormalizeHpTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end

local function NormalizePowerMode(mode)
    if type(_G.MSUF_NormalizePowerTextMode) == "function" then return _G.MSUF_NormalizePowerTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_SLASH_MAX" then return "CURMAX" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
    return mode
end

local function TextScopeGet(key, field, defaultValue)
    local u, g = UnitDB(key)
    SeedTextFromGeneral(u)
    if u[field] ~= nil then return u[field] end
    if g[field] ~= nil then return g[field] end
    return defaultValue
end

local function TextScopeHasSlots(key, leftKey, centerKey, rightKey)
    local u, g = UnitDB(key)
    SeedTextFromGeneral(u)
    return (u and (u[leftKey] ~= nil or u[centerKey] ~= nil or u[rightKey] ~= nil))
        or (g and (g[leftKey] ~= nil or g[centerKey] ~= nil or g[rightKey] ~= nil))
end

local function TextScopeSlotGet(key, field, fallback, normalizer)
    local u, g = UnitDB(key)
    SeedTextFromGeneral(u)
    local value = u[field]
    if value == nil and g then value = g[field] end
    if value == nil or value == "" then value = fallback or "NONE" end
    if normalizer then value = normalizer(value) end
    return value or fallback or "NONE"
end

local TOTINLINE_SEP_VALID = {
    [" "] = true, ["."] = true, ["-"] = true, ["/"] = true, ["\\"] = true, ["|"] = true,
    ["<<<"] = true, [">>>"] = true, ["||"] = true, ["--"] = true,
    [">"] = true, ["<"] = true, ["~"] = true, [":"] = true,
}
local TOTINLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local TOTINLINE_CUSTOM_SEPARATOR_MAX = 5
local function TruncateUtf8Chars(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 or value == "" then return "" end

    local bytePos = 1
    local valueLen = #value
    local chars = 0
    while bytePos <= valueLen and chars < maxChars do
        local b = string.byte(value, bytePos)
        if not b then break end
        if b < 128 then
            bytePos = bytePos + 1
        elseif b < 224 then
            bytePos = bytePos + 2
        elseif b < 240 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        chars = chars + 1
    end
    return string.sub(value, 1, bytePos - 1)
end
local function CleanToTInlineCustomSeparator(v)
    v = tostring(v or ""):gsub("[%c]", " ")
    return TruncateUtf8Chars(v, TOTINLINE_CUSTOM_SEPARATOR_MAX)
end
local function ToTInlineSeparator(v, custom)
    if v == TOTINLINE_CUSTOM_SEPARATOR then
        local token = CleanToTInlineCustomSeparator(custom)
        return token ~= "" and token or " "
    end
    if type(v) ~= "string" or v == "" or not TOTINLINE_SEP_VALID[v] then return "|" end
    return v
end

local function ShortenPreviewName(name, key, layoutConf)
    name = tostring(name or "")
    key = CanonKey(key)
    if key == "player" or name == "" then return name end
    EnsureDB()
    local db = _G.MSUF_DB or {}
    local g = db.general or {}
    local u = db[key] or {}
    local shorten = db.shortenNames and true or false
    if u.fontOverride == true and u.shortenNames ~= nil then
        shorten = u.shortenNames and true or false
    end
    if not shorten then return name end

    local maxChars
    if u.fontOverride == true and tonumber(u.shortenNameMaxChars) then
        maxChars = tonumber(u.shortenNameMaxChars)
    else
        maxChars = tonumber(g.shortenNameMaxChars) or 6
    end
    maxChars = floor(max(4, min(40, maxChars)) + 0.5)
    if #name <= maxChars then return name end

    local mode
    if u.fontOverride == true and u.shortenNameClipSide ~= nil then
        mode = u.shortenNameClipSide
    else
        mode = g.shortenNameClipSide or "LEFT"
    end
    local showDots
    if u.fontOverride == true and u.shortenNameShowDots ~= nil then
        showDots = u.shortenNameShowDots and true or false
    elseif g.shortenNameShowDots ~= nil then
        showDots = g.shortenNameShowDots and true or false
    else
        showDots = true
    end
    local anchorConf = layoutConf or u
    if (anchorConf.nameTextAnchor or "LEFT") ~= "LEFT" then showDots = false end

    if mode == "RIGHT" then
        local text = name:sub(1, maxChars)
        return showDots and (text .. "...") or text
    end
    local text = name:sub(#name - maxChars + 1)
    return showDots and ("..." .. text) or text
end

local function TextScopeSet(key, field, value)
    local u = UnitDB(key)
    SeedTextFromGeneral(u)
    u[field] = value
    u.hpPowerTextOverride = nil
end

local function ForceTextUnit(key, reason)
    key = CanonKey(key)
    if type(_G.MSUF_UFCore_RequestLayoutForUnit) == "function" then
        _G.MSUF_UFCore_RequestLayoutForUnit(key, reason or "UNIT_TEXT_OPTIONS", key == "target" or key == "targettarget" or key == "focustarget" or key == "focus")
    end
    if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
        _G.MSUF_ForceTextLayoutForUnitKey(key)
    end
end

local function ApplyPanelUnit(panel, key, reason)
    key = CanonKey(key or CurrentPanelKey(panel))
    if panel and panel._msufAPI and type(panel._msufAPI.ApplySettingsForKey) == "function" then
        panel._msufAPI.ApplySettingsForKey(key)
    end
    if type(_G.MSUF_SyncUnitPositionPopup) == "function" then _G.MSUF_SyncUnitPositionPopup(key, _G.MSUF_DB and _G.MSUF_DB[key]) end
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh(reason or "UNIT_OPTIONS") end
end

local function RefreshAllControls(list)
    if not list then return end
    for i = 1, #list do
        local w = list[i]
        if w and type(w.Refresh) == "function" then w:Refresh() end
    end
end

local function Label(parent, text, anchor, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local rel = (anchor and anchor ~= parent) and "BOTTOMLEFT" or "TOPLEFT"
    fs:SetPoint("TOPLEFT", anchor or parent, rel, x or 12, y or -8)
    fs:SetText(TR(text or ""))
    if width then fs:SetWidth(width); fs:SetJustifyH("LEFT") end
    return fs
end

local function PlaceTopLeft(widget, anchor, x, y)
    if not widget or not widget.ClearAllPoints or not widget.SetPoint then return end
    anchor = anchor or (widget.GetParent and widget:GetParent())
    if not anchor then return end
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", anchor, "TOPLEFT", x or 0, y or 0)
end

local function SetOptionWidth(widget, width)
    if widget and width and widget.SetWidth then widget:SetWidth(width) end
end

local function AddOptionDivider(parent, anchor, y, width)
    if not parent or not anchor then return nil end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(0.20, 0.32, 0.45, 0.32)
    line:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, y or 0)
    line:SetWidth(width or 260)
    return line
end

local function SetWidgetEnabled(w, enabled)
    if not w then return end
    enabled = enabled and true or false
    if type(w.SetEnabled) == "function" then
        w:SetEnabled(enabled)
    elseif enabled then
        if type(w.Enable) == "function" then w:Enable() end
    else
        if type(w.Disable) == "function" then w:Disable() end
    end
    if w.SetAlpha then w:SetAlpha(enabled and 1 or 0.45) end
    if w.EnableMouse then w:EnableMouse(enabled) end

    local label = w.Text or w.text
    if not label and w.GetName then
        local n = w:GetName()
        label = n and (_G[n .. "Text"] or _G[n .. "Label"])
    end
    if label and label.SetTextColor then
        if enabled then label:SetTextColor(1, 1, 1, 1) else label:SetTextColor(0.55, 0.55, 0.55, 1) end
    end

    if w.editBox then
        if w.editBox.EnableMouse then w.editBox:EnableMouse(enabled) end
        if enabled then
            if w.editBox.Enable then w.editBox:Enable() end
            if w.editBox.SetTextColor then w.editBox:SetTextColor(1, 1, 1, 1) end
        else
            if w.editBox.Disable then w.editBox:Disable() end
            if w.editBox.SetTextColor then w.editBox:SetTextColor(0.55, 0.55, 0.55, 1) end
        end
    end
    for _, childKey in ipairs({ "minusButton", "plusButton", "Button", "_msufPeelButton" }) do
        local child = w[childKey]
        if child then
            if child.EnableMouse then child:EnableMouse(enabled) end
            if enabled then
                if child.Enable then child:Enable() end
                if child.SetAlpha then child:SetAlpha(1) end
            else
                if child.Disable then child:Disable() end
                if child.SetAlpha then child:SetAlpha(0.45) end
            end
        end
    end
    if w.GetName then
        local n = w:GetName()
        if n then
            for _, suffix in ipairs({ "Button", "Text", "Low", "High" }) do
                local obj = _G[n .. suffix]
                if obj then
                    if obj.EnableMouse then obj:EnableMouse(enabled) end
                    if enabled then
                        if obj.Enable then obj:Enable() end
                        if obj.SetAlpha then obj:SetAlpha(1) end
                        if obj.SetTextColor then obj:SetTextColor(1, 1, 1, 1) end
                    else
                        if obj.Disable then obj:Disable() end
                        if obj.SetAlpha then obj:SetAlpha(0.45) end
                        if obj.SetTextColor then obj:SetTextColor(0.55, 0.55, 0.55, 1) end
                    end
                end
            end
        end
    end
    if type(w.Refresh) == "function" then w:Refresh() end
    if type(w._msufToggleUpdate) == "function" then w._msufToggleUpdate() end
end

local function AddPlainCheck(parent, name, label, x, y)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 12, y or -8)
    if cb.Text then cb.Text:SetText(TR(label or "")) end
    if ns.UI and ns.UI.StyleCheckmark then ns.UI.StyleCheckmark(cb) end
    if _G.MSUF_ClampCheckboxText then _G.MSUF_ClampCheckboxText(cb, 180) end
    return cb
end

local function NormalizePortraitClassStyle(style)
    if style == "class_colored_border" or style == "colored" then return "RONDO_COLOR" end
    if style == "wow_icon_border" or style == "wow" then return "RONDO_WOW" end
    if style == "RONDO_COLOR" or style == "RONDO_WOW" or style == "BLIZZARD" then return style end
    return "BLIZZARD"
end

local function EnsureUnitPortraitStyle(key)
    local u = UnitDB(key)
    if not u then return nil end
    u.portraitDecoOverride = nil
    for field, value in pairs(PORTRAIT_STYLE_DEFAULTS) do
        if u[field] == nil then u[field] = value end
    end
    u.portraitRender = (u.portraitRender == "CLASS") and "CLASS" or "2D"
    u.portraitClassStyle = NormalizePortraitClassStyle(u.portraitClassStyle)
    return u
end

local function PortraitStyleGet(key, field, defaultValue)
    local u = EnsureUnitPortraitStyle(key)
    if u and u[field] ~= nil then return u[field] end
    return defaultValue
end

local function PortraitStyleSet(key, field, value)
    local u = EnsureUnitPortraitStyle(key)
    if not u then return end
    if field == "portraitClassStyle" then
        value = NormalizePortraitClassStyle(value)
    elseif field == "portraitRender" then
        value = (value == "CLASS") and "CLASS" or "2D"
    end
    u[field] = value
end

local function ApplyPortrait(panel, key, reason)
    key = CanonKey(key or CurrentPanelKey(panel))
    if type(_G.MSUF_Portraits_SyncUnit) == "function" then _G.MSUF_Portraits_SyncUnit(key) end
    if type(_G.MSUF_PortraitDecoration_SyncUnit) == "function" then _G.MSUF_PortraitDecoration_SyncUnit(key) end
    if type(_G.MSUF_PortraitDecoration_RefreshAll) == "function" then _G.MSUF_PortraitDecoration_RefreshAll() end
    ApplyPanelUnit(panel, key, reason or "UNIT_PORTRAIT_OPTIONS")
end

local function NormalizeStatusPreviewId(id)
    id = tostring(id or "")
    if id == "eliteicon" then return "elite" end
    return id
end

Preview.statusPreviewMode = "current"
Preview.selectedStatusId = nil
local SelectPreviewHandle

function Preview.SetStatusPreviewMode(mode)
    Preview.statusPreviewMode = (mode == "all") and "all" or "current"
    Preview.RequestRefresh("STATUS_PREVIEW_MODE")
end

function Preview.GetStatusPreviewMode()
    return (Preview.statusPreviewMode == "all") and "all" or "current"
end

function Preview.SelectStatusIcon(id)
    Preview.selectedStatusId = NormalizeStatusPreviewId(id)
    local box = Preview.active
    local h = box and box.statusHandles and box.statusHandles[Preview.selectedStatusId]
    if h and SelectPreviewHandle then SelectPreviewHandle(h, true) end
    Preview.RequestRefresh("STATUS_PREVIEW_SELECT")
end

local function ClassColor(class)
    if type(_G.MSUF_UFCore_GetClassBarColorFast) == "function" then
        local r, g, b = _G.MSUF_UFCore_GetClassBarColorFast(class)
        if r then return r, g, b end
    end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.12, 0.62, 0.95
end

local function Clamp01(v, fallback)
    v = tonumber(v)
    if v == nil then return fallback or 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function SettingsCache()
    return type(_G.MSUF_UFCore_GetSettingsCache) == "function" and _G.MSUF_UFCore_GetSettingsCache() or nil
end

local function PreviewNPCKind(key, data, cache, forText)
    data = data or {}
    local typeColorEnabled
    if cache then
        if forText then
            typeColorEnabled = cache.npcTypeColorText
        else
            typeColorEnabled = cache.npcTypeColorBar
        end
    end
    if cache and cache.npcColorMode == "type" and typeColorEnabled then
        local allowed = true
        if key == "target" then allowed = cache.npcTypeTarget ~= false
        elseif key == "focus" then allowed = cache.npcTypeFocus ~= false
        elseif key == "boss" then allowed = cache.npcTypeBoss ~= false
        elseif key == "targettarget" then allowed = cache.npcTypeToT ~= false
        elseif key == "focustarget" then allowed = cache.npcTypeToT ~= false
        end
        if allowed and data.npcKind then return data.npcKind end
    end
    return data.reactionKind or "enemy"
end

local function NPCColor(kind)
    if type(_G.MSUF_UFCore_GetNPCReactionColorFast) == "function" then
        local r, g, b = _G.MSUF_UFCore_GetNPCReactionColorFast(kind)
        if r then return r, g, b end
    end
    local api = ns and ns._colorsAPI
    if api and type(api.GetNPCColor) == "function" then
        local r, g, b = api.GetNPCColor(kind)
        if r then return r, g, b end
    end
    if kind == "friendly" then return 0, 1, 0 end
    if kind == "neutral" then return 1, 1, 0 end
    if kind == "dead" then return 0.4, 0.4, 0.4 end
    if kind == "npcBoss" then return 0.74, 0.11, 0 end
    if kind == "npcMiniboss" then return 0.56, 0, 0.74 end
    if kind == "npcCaster" then return 0, 0.45, 0.74 end
    if kind == "npcMelee" then return 0.99, 0.99, 0.99 end
    if kind == "npcRegular" then return 0.70, 0.56, 0.33 end
    return 0.85, 0.10, 0.10
end

local function GradientPreviewColor(pct)
    pct = Clamp01(pct, 0.75)
    if pct < 0.5 then
        local t = pct * 2
        return 1, t, 0
    end
    local t = (pct - 0.5) * 2
    return 1 - t, 1, 0
end

local function HealthColor(key, data)
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local cache = SettingsCache()
    local mode = (cache and cache.barMode) or g.barMode or "dark"
    if mode == "gradient" then
        local enabled = cache and cache.healthGradientEnabled
        if enabled == nil then enabled = g.enableHealthGradient ~= false end
        if not enabled then mode = "class" end
    end
    data = data or UNIT_DATA.player
    if mode == "class" then
        if data.isPet and cache and cache.petFrameColorEnabled then
            return cache.petFrameColorR or 0, cache.petFrameColorG or 0.8, cache.petFrameColorB or 0
        end
        if data.isPlayer then return ClassColor(data.class) end
        return NPCColor(PreviewNPCKind(key, data, cache))
    end
    if mode == "gradient" then return GradientPreviewColor(data.hp) end
    if mode == "unified" then
        return (cache and cache.unifiedBarR) or g.unifiedBarR or 0.10,
               (cache and cache.unifiedBarG) or g.unifiedBarG or 0.60,
               (cache and cache.unifiedBarB) or g.unifiedBarB or 0.90
    end
    return (cache and cache.darkBarR) or g.darkBarR or g.darkBarGray or 0.07,
           (cache and cache.darkBarG) or g.darkBarG or g.darkBarGray or 0.07,
           (cache and cache.darkBarB) or g.darkBarB or g.darkBarGray or 0.07
end

local function DarkMatchHPColor(r, g, b, cache)
    local gen = (cache and cache.generalRef) or (_G.MSUF_DB and _G.MSUF_DB.general)
    if gen and gen.darkMode and not gen.darkBgCustomColor then
        local br = Clamp01((cache and cache.darkBgBrightness) or gen.darkBgBrightness, 1)
        return Clamp01(r * br, 0), Clamp01(g * br, 0), Clamp01(b * br, 0)
    end
    return Clamp01(r, 0), Clamp01(g, 0), Clamp01(b, 0)
end

local function HealthBackgroundColor(hr, hg, hb, data)
    local cache = SettingsCache()
    local gen = (cache and cache.generalRef) or (_G.MSUF_DB and _G.MSUF_DB.general)
    local r, g, b, a
    if cache then
        r, g, b, a = cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA
    elseif type(_G.MSUF_GetBarBackgroundTintRGBA) == "function" then
        r, g, b, a = _G.MSUF_GetBarBackgroundTintRGBA()
    end
    r, g, b, a = Clamp01(r, 0), Clamp01(g, 0), Clamp01(b, 0), Clamp01(a, 0.9)
    if ((cache and cache.barBgClassColor) or ((not cache) and gen and gen.barBgClassColor)) and data and data.isPlayer then
        r, g, b = ClassColor(data.class)
    elseif (cache and cache.barBgMatchHPColor) or ((not cache) and gen and gen.barBgMatchHPColor) then
        r, g, b = DarkMatchHPColor(hr, hg, hb, cache)
    end
    a = a * Clamp01(cache and cache.barBackgroundAlpha, 0.9)
    return r, g, b, a
end

local function PowerBackgroundColor(pr, pg, pb, hr, hg, hb)
    local cache = SettingsCache()
    local r, g, b, a
    if cache then
        r, g, b, a = cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA
    elseif type(_G.MSUF_GetPowerBarBackgroundTintRGBA) == "function" then
        r, g, b, a = _G.MSUF_GetPowerBarBackgroundTintRGBA()
    end
    r, g, b, a = Clamp01(r, pr * 0.16), Clamp01(g, pg * 0.16), Clamp01(b, pb * 0.16), Clamp01(a, 0.9)
    if cache and cache.powerBarBgMatchHPColor then
        r, g, b = DarkMatchHPColor(hr, hg, hb, cache)
    end
    a = a * Clamp01(cache and cache.barBackgroundAlpha, 0.9)
    return r, g, b, a
end

local function PowerColor(token)
    if type(_G.MSUF_GetResolvedPowerColor) == "function" then
        local r, g, b = _G.MSUF_GetResolvedPowerColor(0, token or "MANA")
        if r then return r, g, b end
    end
    if token == "ENERGY" then return 1, 0.82, 0.10 end
    if token == "RAGE" then return 0.82, 0.12, 0.08 end
    if token == "FOCUS" then return 0.95, 0.45, 0.10 end
    return 0.10, 0.35, 0.95
end

local function ClassPortraitVisual(class, style)
    local PM = ns and ns.PortraitMedia
    if PM and PM.ResolveClassPortrait then
        return PM.ResolveClassPortrait(class, NormalizePortraitClassStyle(style))
    end
    local coords = class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]
    if coords then
        return {
            texture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
            left = coords[1] or 0,
            right = coords[2] or 1,
            top = coords[3] or 0,
            bottom = coords[4] or 1,
        }
    end
    return { texture = "Interface\\ICONS\\INV_Misc_QuestionMark", left = 0, right = 1, top = 0, bottom = 1 }
end

local function UnitPreviewPortraitTexture(key, data)
    data = data or UNIT_DATA[CanonKey(key)] or UNIT_DATA.player
    return data.portraitTexture or "Interface\\ICONS\\INV_Misc_QuestionMark"
end

local function FontColor()
    local fn = (ns and ns.MSUF_GetConfiguredFontColor) or _G.MSUF_GetConfiguredFontColor
    if type(fn) == "function" then
        local r, g, b = fn()
        if r then return r, g, b end
    end
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    return g.fontColorR or 1, g.fontColorG or 1, g.fontColorB or 1
end

local function NormalizeToTInlineColorMode(value)
    if value == "TOT_NAME" or value == "TARGET_NAME" or value == "NPC" or value == "DEFAULT" then
        return value
    end
    return "AUTO"
end

local function PreviewNameColorFlags(key)
    local db = _G.MSUF_DB or {}
    local gen = db.general or {}
    local wantClass = gen.nameClassColor
    local wantNpc = gen.npcNameRed
    local conf = db[key]
    if conf and conf.fontOverride then
        if conf.nameClassColor ~= nil then wantClass = conf.nameClassColor end
        if conf.npcNameRed ~= nil then wantNpc = conf.npcNameRed end
    end
    return wantClass == true, wantNpc == true
end

local function PreviewNameColor(key, data, fallbackR, fallbackG, fallbackB)
    data = data or UNIT_DATA[CanonKey(key)] or UNIT_DATA.player
    local wantClass, wantNpc = PreviewNameColorFlags(key)
    if data.isPlayer then
        if wantClass then return ClassColor(data.class) end
    elseif wantNpc then
        return NPCColor(PreviewNPCKind(key, data, SettingsCache(), true))
    end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end

local function PreviewToTInlineColor(mode, totData, targetR, targetG, targetB, fallbackR, fallbackG, fallbackB)
    mode = NormalizeToTInlineColorMode(mode)
    if mode == "DEFAULT" then
        return fallbackR, fallbackG, fallbackB
    elseif mode == "TARGET_NAME" then
        return targetR, targetG, targetB
    elseif mode == "TOT_NAME" then
        return PreviewNameColor("targettarget", totData, fallbackR, fallbackG, fallbackB)
    elseif mode == "NPC" then
        local _, wantNpc = PreviewNameColorFlags("targettarget")
        if wantNpc and totData and not totData.isPlayer then
            return NPCColor(PreviewNPCKind("targettarget", totData, SettingsCache(), true))
        end
        return fallbackR, fallbackG, fallbackB
    end

    if totData and totData.isPlayer then
        local wantClass = PreviewNameColorFlags("target")
        if wantClass then return ClassColor(totData.class) end
        return 1, 1, 1
    end
    return NPCColor(totData and totData.reactionKind or "enemy")
end

local function SetTex(region, tex)
    if region and region.SetTexture then region:SetTexture(tex or TEX_W8) end
end

local function NormalizePreviewAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback or 3
    if mode < 1 or mode > 5 then mode = fallback or 3 end
    return mode
end

local function UnitPreviewBarOverrideEnabled(conf)
    return conf and (conf.hlOverride == true or conf.hpPowerTextOverride == true)
end

local function PreviewHealPredictionEnabled(g)
    if g then
        if g.showSelfHealPrediction ~= nil then return g.showSelfHealPrediction == true end
        if g.enableHealPrediction ~= nil then return g.enableHealPrediction ~= false end
    end
    return false
end

local function PreviewResolveHealPredAnchorMode(conf, g)
    if UnitPreviewBarOverrideEnabled(conf) and conf.healPredAnchorMode ~= nil then
        return NormalizePreviewAnchorMode(conf.healPredAnchorMode, 3)
    end
    return NormalizePreviewAnchorMode(g and g.healPredAnchorMode, 3)
end

local function PreviewResolveAbsorbAnchorMode(conf, g)
    if UnitPreviewBarOverrideEnabled(conf) and conf.absorbAnchorMode ~= nil then
        return NormalizePreviewAnchorMode(conf.absorbAnchorMode, 2)
    end
    return NormalizePreviewAnchorMode(g and g.absorbAnchorMode, 2)
end

local function PreviewAbsorbBarEnabled(conf, g)
    local mode
    if UnitPreviewBarOverrideEnabled(conf) and conf.absorbTextMode ~= nil then
        mode = tonumber(conf.absorbTextMode)
    end
    if mode == nil and g then mode = tonumber(g.absorbTextMode) end
    if mode then return mode == 2 or mode == 3 end
    return not (g and g.enableAbsorbBar == false)
end

local function PreviewOverlayWidth(areaW, frac)
    return max(1, floor((tonumber(areaW) or 1) * (tonumber(frac) or 0.1) + 0.5))
end

local function LayoutUnitPreviewOverlay(tex, hpBG, hpFill, mode, frac, hpReverse, followAnchor, areaW)
    if not (tex and hpBG and hpFill) then return end
    mode = NormalizePreviewAnchorMode(mode, 3)
    tex:ClearAllPoints()
    tex:SetWidth(PreviewOverlayWidth(areaW, frac))
    if mode == 3 or mode == 4 then
        local anchor = followAnchor or hpFill
        if hpReverse then
            tex:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 0, 0)
        else
            tex:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
        end
    elseif mode == 1 or (mode == 5 and hpReverse) then
        tex:SetPoint("TOPLEFT", hpBG, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMLEFT", hpBG, "BOTTOMLEFT", 0, 0)
    else
        tex:SetPoint("TOPRIGHT", hpBG, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", hpBG, "BOTTOMRIGHT", 0, 0)
    end
    tex:Show()
end

local function MakeFS(parent, layer, size)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size or 12, "OUTLINE")
    fs:SetShadowOffset(1, -1)
    return fs
end

local function ReadPowerBarEnabled(conf, key)
    if key == "pet" or key == "targettarget" or key == "focustarget" then return false end
    if conf.showPowerBar ~= nil then return conf.showPowerBar ~= false end
    if key == "boss" then return true end
    return true
end

local function CanDetachPowerBarKey(key)
    key = CanonKey(key)
    return key == "player" or key == "target" or key == "focus"
end

local function ReadPowerBarHeight(conf)
    local h = tonumber(conf.powerBarHeight) or 3
    if h < 1 then h = 1 elseif h > 20 then h = 20 end
    return h
end

local function ResolveNameAnchor(anchor, x)
    x = tonumber(x) or 0
    if anchor == "RIGHT" then return "TOPRIGHT", "TOPRIGHT", -x, "RIGHT" end
    if anchor == "CENTER" then return "TOP", "TOP", x, "CENTER" end
    return "TOPLEFT", "TOPLEFT", x, "LEFT"
end

local function NumText(v)
    if v >= 1000000 then return format("%.1fm", v / 1000000) end
    if v >= 1000 then return format("%.1fk", v / 1000) end
    return tostring(v)
end

local function JoinSep(sep)
    sep = tostring(sep or "")
    if sep == "" then return " " end
    return " " .. sep .. " "
end

local function FormatMode(mode, cur, maxVal, pct, sep, isPower)
    if isPower then mode = NormalizePowerMode(mode) else mode = NormalizeHpMode(mode) end
    if mode == "NONE" then return "" end
    local c = NumText(cur)
    local m = NumText(maxVal)
    local p = tostring(pct) .. "%"
    local s = JoinSep(sep)
    if mode == "PERCENT" then return p end
    if mode == "CURRENT" then return c end
    if mode == "MAX" then return m end
    if mode == "DEFICIT" then return "-" .. NumText(maxVal - cur) end
    if mode == "CURMAX" then return c .. s .. m end
    if mode == "MAXCUR" then return m .. s .. c end
    if mode == "CURPERCENT" then return c .. s .. p end
    if mode == "PERCENTCUR" then return p .. s .. c end
    if mode == "CURMAXPERCENT" then return c .. s .. m .. s .. p end
    if mode == "PERCENTMAXCUR" then return p .. s .. m .. s .. c end
    if mode == "MAXPERCENT" then return m .. s .. p end
    if mode == "PERCENTMAX" then return p .. s .. m end
    if mode == "PERCENTCURMAX" then return p .. s .. c .. s .. m end
    return c .. s .. p
end

local UnitPreviewText = {}

function UnitPreviewText.PlaceHandleAroundRegions(handle, parent, regions, pad)
    if not (handle and parent and parent.GetLeft and regions) then return false end
    pad = tonumber(pad) or 3
    local left, right, top, bottom
    for i = 1, #regions do
        local r = regions[i]
        if r and r.IsShown and r:IsShown() and r.GetLeft then
            local l, rr, t, b = r:GetLeft(), r:GetRight(), r:GetTop(), r:GetBottom()
            if l and rr and t and b then
                left = left and min(left, l) or l
                right = right and max(right, rr) or rr
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

local function PositionFromAnchor(frame, anchor, x, y, target, size)
    frame:ClearAllPoints()
    size = tonumber(size) or 14
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    anchor = tostring(anchor or "TOPLEFT")
    if anchor == "TOPRIGHT" then frame:SetPoint("CENTER", target, "TOPRIGHT", x - size * 0.5, y - size * 0.5)
    elseif anchor == "NAMERIGHT" then frame:SetPoint("LEFT", target, "TOPLEFT", x + 44, y - 8)
    elseif anchor == "NAMELEFT" then frame:SetPoint("RIGHT", target, "TOPLEFT", x + 2, y - 8)
    elseif anchor == "TOP" then frame:SetPoint("CENTER", target, "TOP", x, y - size * 0.5)
    elseif anchor == "BOTTOM" then frame:SetPoint("CENTER", target, "BOTTOM", x, y + size * 0.5)
    elseif anchor == "LEFT" then frame:SetPoint("CENTER", target, "LEFT", x + size * 0.5, y)
    elseif anchor == "RIGHT" then frame:SetPoint("CENTER", target, "RIGHT", x - size * 0.5, y)
    elseif anchor == "BOTTOMLEFT" then frame:SetPoint("CENTER", target, "BOTTOMLEFT", x + size * 0.5, y + size * 0.5)
    elseif anchor == "BOTTOMRIGHT" then frame:SetPoint("CENTER", target, "BOTTOMRIGHT", x - size * 0.5, y + size * 0.5)
    elseif anchor == "CENTER" then frame:SetPoint("CENTER", target, "CENTER", x, y)
    else frame:SetPoint("CENTER", target, "TOPLEFT", x + size * 0.5, y - size * 0.5) end
end

local function ResolveRuntimeIconLayoutAnchor(anchor, allowCenter)
    if allowCenter and anchor == "CENTER" then return "CENTER", "CENTER" end
    if anchor == "TOPRIGHT" then return "RIGHT", "TOPRIGHT" end
    if anchor == "BOTTOMLEFT" then return "LEFT", "BOTTOMLEFT" end
    if anchor == "BOTTOMRIGHT" then return "RIGHT", "BOTTOMRIGHT" end
    return "LEFT", "TOPLEFT"
end

local function PositionRuntimeLayoutIconPreview(frame, anchor, x, y, target, allowCenter)
    if not frame or not target then return end
    frame:ClearAllPoints()
    local point, relPoint = ResolveRuntimeIconLayoutAnchor(tostring(anchor or "TOPLEFT"), allowCenter)
    frame:SetPoint(point, target, relPoint, tonumber(x) or 0, tonumber(y) or 0)
end

local function PositionStatusCornerPreview(frame, anchor, x, y, target, pad)
    if not frame or not target then return end
    frame:ClearAllPoints()
    anchor = tostring(anchor or "TOPLEFT")
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    pad = tonumber(pad) or 2
    if anchor == "CENTER" then
        frame:SetPoint("CENTER", target, "CENTER", x, y)
    elseif anchor == "TOPRIGHT" then
        frame:SetPoint("TOPRIGHT", target, "TOPRIGHT", -pad + x, -pad + y)
    elseif anchor == "BOTTOMLEFT" then
        frame:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", pad + x, pad + y)
    elseif anchor == "BOTTOMRIGHT" then
        frame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -pad + x, pad + y)
    else
        frame:SetPoint("TOPLEFT", target, "TOPLEFT", pad + x, -pad + y)
    end
end

local function PositionSameAnchorPreview(frame, anchor, x, y, target)
    if not frame or not target then return end
    frame:ClearAllPoints()
    anchor = tostring(anchor or "CENTER")
    frame:SetPoint(anchor, target, anchor, tonumber(x) or 0, tonumber(y) or 0)
end

local function PositionLevelPreview(frame, anchor, x, y, mock, gap)
    if not frame or not mock then return end
    frame:ClearAllPoints()
    anchor = tostring(anchor or "NAMERIGHT")
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    gap = tonumber(gap) or 6
    local nameVisible = mock.nameText and (not mock.nameText.IsShown or mock.nameText:IsShown())
    if anchor == "NAMELEFT" and nameVisible then
        frame:SetPoint("RIGHT", mock.nameText, "LEFT", -gap + x, y)
    elseif anchor == "NAMERIGHT" and nameVisible then
        frame:SetPoint("LEFT", mock.nameText, "RIGHT", gap + x, y)
    elseif anchor == "NAMELEFT" or anchor == "NAMERIGHT" then
        PositionSameAnchorPreview(frame, "CENTER", x, y, mock.textFrame or mock)
    else
        PositionSameAnchorPreview(frame, anchor, x, y, mock.textFrame or mock)
    end
end

local function RoundOffset(v)
    v = tonumber(v) or 0
    if v >= 0 then return floor(v + 0.5) end
    return -floor((-v) + 0.5)
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

local function CastbarOffsetFields(unitKey)
    unitKey = CanonKey(unitKey)
    local dx, dy = 0, 0
    if type(_G.MSUF_GetCastbarDefaultOffsets) == "function" then
        dx, dy = _G.MSUF_GetCastbarDefaultOffsets(unitKey)
    end
    if unitKey == "boss" then
        return "bossCastbarOffsetX", "bossCastbarOffsetY", dx or 0, dy or 0
    end
    local prefix = type(_G.MSUF_GetCastbarPrefix) == "function" and _G.MSUF_GetCastbarPrefix(unitKey) or nil
    if not prefix or prefix == "" then return nil, nil, dx or 0, dy or 0 end
    return prefix .. "OffsetX", prefix .. "OffsetY", dx or 0, dy or 0
end

local function CastbarPrefix(unitKey)
    unitKey = CanonKey(unitKey)
    if type(_G.MSUF_GetCastbarPrefix) == "function" then
        return _G.MSUF_GetCastbarPrefix(unitKey)
    end
    if unitKey == "player" then return "castbarPlayer" end
    if unitKey == "target" then return "castbarTarget" end
    if unitKey == "focus" then return "castbarFocus" end
    return nil
end

local function CastbarDetached(key, g)
    key = CanonKey(key)
    if not g then return false end
    if key == "boss" then return g.bossCastbarDetached == true end
    local prefix = CastbarPrefix(key)
    return prefix and g[prefix .. "Detached"] == true or false
end

local function NormalizeCastbarWidthSource(v)
    local fn = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
    if type(fn) == "function" then return fn(v) end
    if v == true then return "unitframe" end
    if v == "unitframe" or v == "essential" or v == "utility" then return v end
    return nil
end

local function CastbarWidthSourceKey(key)
    key = CanonKey(key)
    local fn = _G.MSUF_GetCastbarWidthSourceKey
    if type(fn) == "function" then
        local dbKey = fn(key)
        if dbKey then return dbKey end
    end
    if key == "player" then return "castbarPlayerMatchWidth", "castbarPlayerMatchUnitWidth" end
    if key == "target" then return "castbarTargetMatchWidth", "castbarTargetMatchUnitWidth" end
    if key == "focus" then return "castbarFocusMatchWidth", "castbarFocusMatchUnitWidth" end
    if key == "boss" then return "bossCastbarMatchWidth", "castbarBossMatchUnitWidth", "castbarBossMatchWidth" end
end

local function CastbarWidthSource(g, key)
    if not g then return nil end
    local primary, legacy, alias = CastbarWidthSourceKey(key)
    local source = NormalizeCastbarWidthSource(primary and g[primary])
    if source then return source end
    source = NormalizeCastbarWidthSource(alias and g[alias])
    if source then return source end
    if legacy and g[legacy] == true then return "unitframe" end
    return nil
end

local function ExternalCastbarWidthSourceFrame(source)
    if source == "essential" then
        return (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
            or _G.EssentialCooldownViewer
    elseif source == "utility" then
        return _G.UtilityCooldownViewer
    end
end

local function ReadExternalCastbarWidth(source, targetFrame)
    local frame = ExternalCastbarWidthSourceFrame(source)
    if not (frame and frame.GetWidth and frame.IsShown and frame:IsShown()) then return nil end
    local scaleWidth = _G.MSUF_CDM_GetScaledWidth
    if type(scaleWidth) == "function" then
        local w = scaleWidth(frame, targetFrame)
        if w and w > 0 then return w end
    end
    local w = frame:GetWidth()
    if w and w > 0 then return w end
end

local function ReadCastbarSize(key, g, fallbackW, fallbackH)
    key = CanonKey(key)
    fallbackW = tonumber(fallbackW) or 250
    fallbackH = tonumber(fallbackH) or 18
    local widthSource = CastbarWidthSource(g, key)
    local w, h
    if widthSource == "unitframe" then
        w = fallbackW
    elseif widthSource == "essential" or widthSource == "utility" then
        w = ReadExternalCastbarWidth(widthSource) or nil
    end
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        local desiredW, desiredH = _G.MSUF_GetCastbarDesiredSize(key, g or {}, nil, fallbackW, fallbackH)
        if not w or w <= 0 then w = desiredW end
        h = desiredH
    end
    if not w or w <= 0 then
        if key == "boss" then
            w = g and tonumber(g.bossCastbarWidth)
        else
            local prefix = CastbarPrefix(key)
            w = prefix and g and tonumber(g[prefix .. "BarWidth"]) or nil
        end
    end
    if not h or h <= 0 then
        if key == "boss" then
            h = g and tonumber(g.bossCastbarHeight)
        else
            local prefix = CastbarPrefix(key)
            h = prefix and g and tonumber(g[prefix .. "BarHeight"]) or nil
        end
    end
    w = tonumber(w) or fallbackW
    h = tonumber(h) or fallbackH
    if w < 40 then w = 40 elseif w > 900 then w = 900 end
    if h < 6 then h = 6 elseif h > 80 then h = 80 end
    return w, h
end

local function CastbarTextKey(key, suffix, bossKey)
    key = CanonKey(key)
    if key == "boss" then return bossKey end
    local prefix = CastbarPrefix(key)
    return prefix and (prefix .. suffix) or nil
end

local function ReadCastbarNum(g, key, suffix, bossKey, fallback)
    local dbKey = CastbarTextKey(key, suffix, bossKey)
    local v = dbKey and g and tonumber(g[dbKey]) or nil
    if v == nil and suffix and suffix:find("Icon", 1, true) then
        local globalKey = suffix:gsub("^Icon", "castbarIcon")
        v = g and tonumber(g[globalKey]) or nil
    end
    return (v ~= nil) and v or fallback
end

local function FormatCastbarPreviewTime(g, key, current, total)
    local mode = "CURRENT"
    if type(_G.MSUF_GetCastbarTimeFormat) == "function" then
        mode = _G.MSUF_GetCastbarTimeFormat(key, g)
    end
    if type(_G.MSUF_FormatCastbarTimeText) == "function" then
        return _G.MSUF_FormatCastbarTimeText(mode, current, total) or ""
    end
    return format("%.1f", tonumber(current) or 0)
end

local function ClampPreviewLayer(v, fallback)
    v = floor((tonumber(v) or fallback or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 30 then return 30 end
    return v
end

local function ResolveHandleFields(preview, fields)
    if fields and fields.castbar then
        return CastbarOffsetFields(preview and preview.key)
    end
    return fields and fields.x, fields and fields.y, fields and fields.defaultX or 0, fields and fields.defaultY or 0
end

local function HandleStore(preview, fields)
    local conf, g, key = UnitDB(preview and preview.key)
    if fields and fields.portrait then EnsureUnitPortraitStyle(key) end
    if fields and (fields.global or fields.castbar) then return g, key, conf, g end
    return conf, key, conf, g
end

local function ReadHandleOffsets(handle)
    if not handle then return 0, 0 end
    local preview = handle._preview
    local fields = handle._fields or {}
    local xKey, yKey, defX, defY = ResolveHandleFields(preview, fields)
    local store = HandleStore(preview, fields)
    local x = xKey and tonumber(store[xKey]) or nil
    local y = yKey and tonumber(store[yKey]) or nil
    if x == nil then x = tonumber(defX) or 0 end
    if y == nil then y = tonumber(defY) or 0 end
    return x, y, xKey, yKey
end

local function UnitPreviewTextMovesTogether(unitKey, kind)
    local m = _G.MSUF2
    local byUnit = m and m.unitTextMoveTogether and m.unitTextMoveTogether[unitKey or "player"]
    local value = byUnit and byUnit[kind]
    if value == nil then return true end
    return value == true
end

local function UnitPreviewSetTextMoveTogether(unitKey, kind, value)
    local m = _G.MSUF2
    if not m then return end
    unitKey = unitKey or "player"
    m.unitTextMoveTogether = m.unitTextMoveTogether or {}
    m.unitTextMoveTogether[unitKey] = m.unitTextMoveTogether[unitKey] or {}
    m.unitTextMoveTogether[unitKey][kind] = value ~= false
end

local function UpdateHandleHint(box, handle)
    if not box or not box.hint then return end
    if not handle then
        box.hint:SetText(TR("click layers to hide - drag preview elements - arrows nudge selected"))
        return
    end
    local x, y = ReadHandleOffsets(handle)
    box.hint:SetText(format("%s   x: %d   y: %d   %s", TR(handle._label or handle._key or "?"), x, y, TR("arrows nudge, Shift=5, Ctrl=10")))
end

local function RefreshHandleSelectionVisuals(box)
    if not box then return end
    local selected = box._selectedHandle
    if selected and selected.IsShown and not selected:IsShown() then selected = nil; box._selectedHandle = nil end
    for i = 1, #(box.handles or {}) do
        local h = box.handles[i]
        local isSel = h and h == selected
        if h then
            local isHover = h._hovering == true
            if h._selBorder then
                if isSel then h._selBorder:Show() else h._selBorder:Hide() end
            end
            local c = h._color or { 0.7, 0.8, 1.0 }
            local isDrag = h._dragging == true
            if h.tex then
                h.tex:SetColorTexture(c[1], c[2], c[3], isDrag and 0.18 or (isHover and 0.14 or 0))
            end
            if h.edge then
                h.edge:SetColorTexture(c[1], c[2], c[3], isDrag and 0.18 or (isHover and 0.08 or 0))
            end
            if h.SetAlpha then h:SetAlpha(1) end
        end
    end
    UpdateHandleHint(box, selected)
end

local function CommitHandleMove(handle, reason)
    if not handle then return end
    local box = handle._preview
    local fields = handle._fields or {}
    local _, _, key = UnitDB(box and box.key)
    if fields.text then
        ForceTextUnit(key, reason or "UNIT_PREVIEW_MOVE")
    elseif fields.portrait then
        ApplyPortrait(box and box._msufPanel, key, reason or "UNIT_PREVIEW_PORTRAIT_MOVE")
    elseif fields.detachedPower then
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
            _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true)
        end
    elseif fields.castbar then
        if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
            _G.MSUF_ApplyCastbarUnitAndSync(key)
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            _G.MSUF_UpdateCastbarVisuals()
        end
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
            _G.MSUF_SyncCastbarPositionPopup(key)
        end
    elseif fields.statusRefresh then
        local fn = _G[fields.statusRefresh]
        if type(fn) == "function" then fn() end
    end
    ApplyPanelUnit(box and box._msufPanel, key, reason or "UNIT_PREVIEW_MOVE")
    Preview.Refresh(box)
    RefreshHandleSelectionVisuals(box)
end

local function MenuHistoryLabel(handle, action)
    local label = handle and (handle._label or handle._key) or "Preview element"
    return tostring(action or "Move") .. ": " .. tostring(label or "Preview element")
end

local function MenuHistorySource(handle, action)
    local box = handle and handle._preview
    return "unitPreview:" .. tostring(box and box.key or "unit") .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
end

local function BeginMenuHistory(handle, action)
    local h = _G.MSUF2
    if not (h and type(h.BeginHistoryTransaction) == "function") then return false end
    return h.BeginHistoryTransaction(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action))
end

local function CommitMenuHistory()
    local h = _G.MSUF2
    if h and type(h.CommitHistoryTransaction) == "function" then return h.CommitHistoryTransaction() end
    return false
end

local function CheckpointMenuHistory(handle, action)
    local h = _G.MSUF2
    if h and type(h.CheckpointHistory) == "function" then
        return h.CheckpointHistory(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action))
    end
    return false
end

local function WriteHandleOffsets(handle, x, y, reason)
    if not handle then return false end
    local box = handle._preview
    local fields = handle._fields or {}
    local xKey, yKey = ResolveHandleFields(box, fields)
    if not xKey or not yKey then return false end
    local store = HandleStore(box, fields)
    store[xKey] = RoundOffset(x)
    store[yKey] = RoundOffset(y)
    CommitHandleMove(handle, reason)
    if not handle._msuf2PreviewHistoryTx then
        CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move")
    end
    return true
end

local function NudgeSelectedHandle(box, dx, dy)
    local h = box and box._selectedHandle
    if not h or not h.IsShown or not h:IsShown() then return false end
    local x, y = ReadHandleOffsets(h)
    local step = GetNudgeStep()
    return WriteHandleOffsets(h, x + (dx * step), y + (dy * step), "UNIT_PREVIEW_NUDGE")
end

SelectPreviewHandle = function(handle, skipSectionOpen)
    local box = handle and handle._preview or Preview.active
    if not box then return end
    if box.EnableKeyboard then box:EnableKeyboard(true) end
    if box.SetFocus then box:SetFocus() end
    box._selectedHandle = handle
    if handle then
        local p = box._msufPanel
        local fields = handle._fields or {}
        local menu = _G.MSUF2
        if fields.statusRefresh then
            Preview.selectedStatusId = NormalizeStatusPreviewId(handle._key)
            if not skipSectionOpen and p and type(p._msufUFStatusSet) == "function" then
                p._msufUFStatusSet("selected", handle._key)
            end
        end
        if menu and (handle._key == "hpLeft" or handle._key == "hpCenter" or handle._key == "hpRight") then
            UnitPreviewSetTextMoveTogether(box.key, "hp", false)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextSlotSelection = menu.unitTextSlotSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "hp"
            menu.unitTextSlotSelection[box.key or "player"] = menu.unitTextSlotSelection[box.key or "player"] or {}
            menu.unitTextSlotSelection[box.key or "player"].hp = (handle._key == "hpLeft" and "left") or (handle._key == "hpRight" and "right") or "center"
        elseif menu and handle._key == "hp" then
            UnitPreviewSetTextMoveTogether(box.key, "hp", true)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "hp"
        elseif menu and (handle._key == "powerLeft" or handle._key == "powerCenter" or handle._key == "powerRight") then
            UnitPreviewSetTextMoveTogether(box.key, "power", false)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextSlotSelection = menu.unitTextSlotSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "power"
            menu.unitTextSlotSelection[box.key or "player"] = menu.unitTextSlotSelection[box.key or "player"] or {}
            menu.unitTextSlotSelection[box.key or "player"].power = (handle._key == "powerLeft" and "left") or (handle._key == "powerRight" and "right") or "center"
        elseif menu and handle._key == "power" then
            UnitPreviewSetTextMoveTogether(box.key, "power", true)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "power"
        end
        if not skipSectionOpen and p and type(p._msufOpenUnitSection) == "function" then
            p._msufOpenUnitSection(fields.section or "text")
        end
    end
    RefreshHandleSelectionVisuals(box)
end

local function PreviewArrowKeyDown(self, keyName)
    local box = (self and self._preview) or self or Preview.active
    local dx, dy = 0, 0
    if keyName == "LEFT" then
        dx = -1
    elseif keyName == "RIGHT" then
        dx = 1
    elseif keyName == "UP" then
        dy = 1
    elseif keyName == "DOWN" then
        dy = -1
    else
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        return
    end

    if IsTextInputFocused() then
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        return
    end
    if NudgeSelectedHandle(box, dx, dy) then
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    else
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end
end

local function MakeHandle(preview, key, fields, label, color)
    local h = CreateFrame("Button", nil, preview.canvas)
    h:SetFrameLevel((preview.canvas:GetFrameLevel() or 0) + 30)
    h:SetSize(20, 20)
    h:RegisterForClicks("LeftButtonUp")
    h:EnableMouse(true)
    h:EnableKeyboard(true)
    if h.SetPropagateKeyboardInput then h:SetPropagateKeyboardInput(true) end
    h.tex = h:CreateTexture(nil, "OVERLAY")
    h.tex:SetAllPoints()
    h.tex:SetColorTexture(color[1], color[2], color[3], 0)
    h.edge = h:CreateTexture(nil, "BORDER")
    h.edge:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.edge:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.edge:SetColorTexture(color[1], color[2], color[3], 0)
    h._label = label
    h._fields = fields
    h._key = key
    h._preview = preview
    h._color = color
    h._selBorder = CreateFrame("Frame", nil, h)
    h._selBorder:SetPoint("TOPLEFT", h, "TOPLEFT", -1, 1)
    h._selBorder:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 1, -1)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local line = h._selBorder:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0.30, 0.58, 0.95, 0.70)
        h._selBorder[side] = line
    end
    h._selBorder.top:SetPoint("TOPLEFT")
    h._selBorder.top:SetPoint("TOPRIGHT")
    h._selBorder.top:SetHeight(1)
    h._selBorder.bottom:SetPoint("BOTTOMLEFT")
    h._selBorder.bottom:SetPoint("BOTTOMRIGHT")
    h._selBorder.bottom:SetHeight(1)
    h._selBorder.left:SetPoint("TOPLEFT")
    h._selBorder.left:SetPoint("BOTTOMLEFT")
    h._selBorder.left:SetWidth(1)
    h._selBorder.right:SetPoint("TOPRIGHT")
    h._selBorder.right:SetPoint("BOTTOMRIGHT")
    h._selBorder.right:SetWidth(1)
    h._selBorder:Hide()
    h:SetScript("OnEnter", function(self)
        self._hovering = true
        RefreshHandleSelectionVisuals(preview)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR(label), 1, 1, 1)
            GameTooltip:AddLine(TR("Drag this preview element to adjust the same X/Y offsets used by Edit Mode."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Arrow keys nudge the selected element. Shift = 5, Ctrl = 10."), 0.55, 0.62, 0.72, true)
            GameTooltip:Show()
        end
    end)
    h:SetScript("OnLeave", function(self)
        self._hovering = nil
        RefreshHandleSelectionVisuals(preview)
        if GameTooltip then GameTooltip:Hide() end
    end)
    h:SetScript("OnClick", function(self)
        SelectPreviewHandle(self)
    end)
    local function StartHandleDrag(self, button)
        if button and button ~= "LeftButton" then return end
        SelectPreviewHandle(self)
        local x, y = ReadHandleOffsets(self)
        self._startX = x
        self._startY = y
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragging = true
        self._msuf2PreviewHistoryTx = BeginMenuHistory(self, "Move")
        local cx, cy = GetCursorPosition()
        self._cursorX, self._cursorY = cx, cy
        preview.dragFrame._handle = self
        preview.dragFrame:SetScript("OnUpdate", preview._onDragUpdate)
        preview.dragFrame:Show()
        RefreshHandleSelectionVisuals(preview)
    end
    local function StopHandleDrag(self, button)
        if button and button ~= "LeftButton" then return end
        if preview.dragFrame._handle == self then
            preview.dragFrame:SetScript("OnUpdate", nil)
            preview.dragFrame._handle = nil
            preview.dragFrame:Hide()
        end
        if self._msuf2PreviewHistoryTx then
            self._msuf2PreviewHistoryTx = nil
            CommitMenuHistory()
        end
        self._dragging = nil
        self._lastDragX = nil
        self._lastDragY = nil
        RefreshHandleSelectionVisuals(preview)
    end
    h:SetScript("OnMouseDown", StartHandleDrag)
    h:SetScript("OnMouseUp", StopHandleDrag)
    h:SetScript("OnHide", StopHandleDrag)
    h:SetScript("OnKeyDown", PreviewArrowKeyDown)
    h:Hide()
    preview.handles[#preview.handles + 1] = h
    return h
end

local function StatusSymbolTexture(symbolKey)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then return nil end
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local mid = g.statusIconsUseMidnightStyle == true
    local folder, suffix = "Combat", mid and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    if symbolKey:find("^rested_") then
        folder, suffix = "Rested", mid and "_midnight_64.tga" or "_classic_64.tga"
    elseif symbolKey:find("^resurrection_") then
        folder, suffix = "Ress", mid and "_midnight_64.tga" or "_classic_64.tga"
    end
    return SYMBOL_MEDIA .. folder .. "\\" .. symbolKey .. suffix
end

local function CreateIcon(parent, color, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(16, 16)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.txt = MakeFS(f, "OVERLAY", 10)
    f.txt:SetPoint("CENTER")
    f.txt:SetText(text or "")
    f.txt:SetTextColor(color[1], color[2], color[3], 1)
    return f
end

local function SetPreviewIconTexture(icon, spec, conf, g, key, data)
    if not icon or not spec then return end
    local tex, txt = icon.tex, icon.txt
    if tex then
        tex:Show()
        tex:SetVertexColor(1, 1, 1, 1)
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    end
    if txt then txt:Hide() end
    if spec.id == "raidmarker" then
        if tex then
            tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            if SetRaidTargetIconTexture then SetRaidTargetIconTexture(tex, 8) end
        end
    elseif spec.id == "leader" then
        if tex then
            local isAssist = key == "target"
            local path = isAssist and "Interface\\GroupFrame\\UI-Group-AssistantIcon" or "Interface\\GroupFrame\\UI-Group-LeaderIcon"
            local style = (conf and conf.leaderIconStyle) or (g and g.leaderIconStyle) or "BLIZZARD"
            if type(style) == "string" and style ~= "" and style ~= "DEFAULT" and style ~= "BLIZZARD" then
                local resolver = isAssist and _G.MSUF_GetAssistStatusIconTexture or _G.MSUF_GetLeaderStatusIconTexture
                if type(resolver) == "function" then
                    local customPath, l, r, t, b = resolver(style, false)
                    if type(customPath) == "string" and customPath ~= "" then
                        path = customPath
                        if tex.SetTexCoord then tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1) end
                    end
                end
            end
            tex:SetTexture(path)
        end
    elseif spec.id == "elite" then
        if tex and tex.SetAtlas then
            tex:SetAtlas((key == "boss") and "nameplates-icon-elite-gold" or "nameplates-icon-elite-silver")
        elseif tex then
            tex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        end
    elseif spec.id == "statusCombat" then
        local path = StatusSymbolTexture(conf.combatStateIndicatorSymbol or g.combatStateIndicatorSymbol)
        if tex and path then
            tex:SetTexture(path)
        elseif tex and tex.SetAtlas then
            tex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitCombatIcon")
        elseif tex then
            tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            if tex.SetTexCoord then tex:SetTexCoord(0.5, 1, 0, 0.5) end
        end
    elseif spec.id == "statusResting" then
        local path = StatusSymbolTexture(conf.restedStateIndicatorSymbol or conf.restingStateIndicatorSymbol or g.restedStateIndicatorSymbol or g.restingStateIndicatorSymbol)
        if tex and path then
            tex:SetTexture(path)
        elseif tex and tex.SetAtlas then
            tex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitRestingIcon")
        elseif tex then
            tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            if tex.SetTexCoord then tex:SetTexCoord(0, 0.5, 0, 0.5) end
        end
    elseif spec.id == "statusIncomingRes" then
        local path = StatusSymbolTexture(conf.incomingResIndicatorSymbol or g.incomingResIndicatorSymbol)
        if tex then tex:SetTexture(path or "Interface\\RaidFrame\\Raid-Icon-Rez") end
    elseif spec.id == "level" or spec.id == "statusText" then
        if tex then tex:Hide() end
        if txt then
            txt:SetText(spec.id == "level" and (data.level or "80") or "DEAD")
            txt:SetTextColor(FontColor())
            txt:Show()
        end
    else
        if tex then tex:SetTexture("Interface\\Buttons\\WHITE8X8"); tex:SetVertexColor((spec.color and spec.color[1]) or 1, (spec.color and spec.color[2]) or 1, (spec.color and spec.color[3]) or 1, 0.85) end
    end
end

local function ResolveStatusPreviewAnchor(spec, conf, g)
    if not spec then return "TOPLEFT" end
    conf = conf or {}
    g = g or {}
    local anchor = spec.anchor and (conf[spec.anchor] or g[spec.anchor]) or nil
    if anchor == nil then
        if spec.id == "statusCombat" then
            anchor = conf.combatStateIndicatorPos or g.combatStateIndicatorPos
        elseif spec.id == "statusResting" then
            anchor = conf.combatStateIndicatorAnchor or g.combatStateIndicatorAnchor
                or conf.combatStateIndicatorPos or g.combatStateIndicatorPos
        elseif spec.id == "statusIncomingRes" then
            anchor = conf.incomingResIndicatorPos or g.incomingResIndicatorPos
        end
    end
    return anchor or spec.defaultAnchor or "TOPLEFT"
end

local STATUS_PREVIEW = {
    { id = "raidmarker", show = "showRaidMarker", size = "raidMarkerSize", anchor = "raidMarkerAnchor", x = "raidMarkerOffsetX", y = "raidMarkerOffsetY", layer = "raidMarkerLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPLEFT", defaultX = 16, defaultY = 3, text = "8", color = { 1, 0.82, 0.05 }, label = "Raid marker", refresh = "MSUF_RefreshRaidMarkerFrames" },
    { id = "leader", show = "showLeaderIcon", size = "leaderIconSize", anchor = "leaderIconAnchor", x = "leaderIconOffsetX", y = "leaderIconOffsetY", layer = "leaderIconLayer", defaultLayer = 7, defaultSize = 14, defaultAnchor = "TOPLEFT", defaultX = 0, defaultY = 3, text = "L", color = { 0.95, 0.82, 0.20 }, label = "Leader icon", refresh = "MSUF_RefreshLeaderIconFrames", allowed = function(k) return k == "player" or k == "target" end },
    { id = "level", show = "showLevelIndicator", size = "levelIndicatorSize", anchor = "levelIndicatorAnchor", x = "levelIndicatorOffsetX", y = "levelIndicatorOffsetY", layer = "levelIndicatorLayer", defaultLayer = 7, defaultSize = 14, defaultAnchor = "NAMERIGHT", defaultX = 0, defaultY = 0, text = "80", color = { 0.45, 0.70, 1.0 }, label = "Level indicator", refresh = "MSUF_RefreshLevelIndicatorFrames" },
    { id = "elite", show = "showEliteIcon", size = "eliteIconSize", anchor = "eliteIconAnchor", x = "eliteIconOffsetX", y = "eliteIconOffsetY", layer = "eliteIconLayer", defaultLayer = 7, defaultSize = 20, defaultAnchor = "TOPRIGHT", defaultX = 2, defaultY = 2, text = "*", color = { 1.0, 0.58, 0.16 }, label = "Elite icon", refresh = "MSUF_RefreshEliteIconFrames", allowed = function(k) return k == "target" or k == "focus" or k == "targettarget" or k == "focustarget" or k == "boss" end },
    { id = "statusText", show = "statusTextEnabled", size = "statusTextSize", anchor = "statusTextAnchor", x = "statusTextOffsetX", y = "statusTextOffsetY", layer = "statusTextLayer", defaultLayer = 7, defaultSize = 16, defaultAnchor = "CENTER", defaultX = 0, defaultY = 0, text = "DEAD", color = { 0.68, 0.70, 0.74 }, label = "Dead text", refresh = "MSUF_RequestStatusTextRefresh" },
    { id = "statusCombat", show = "showCombatStateIndicator", size = "combatStateIndicatorSize", anchor = "combatStateIndicatorAnchor", x = "combatStateIndicatorOffsetX", y = "combatStateIndicatorOffsetY", layer = "combatStateIndicatorLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPLEFT", defaultX = 0, defaultY = 0, text = "C", color = { 1.0, 0.22, 0.16 }, label = "Combat icon", refresh = "MSUF_RequestStatusCombatIndicatorRefresh", allowed = function(k) return k == "player" or k == "target" end },
    { id = "statusResting", show = "showRestingIndicator", size = "restedStateIndicatorSize", anchor = "restedStateIndicatorAnchor", x = "restedStateIndicatorOffsetX", y = "restedStateIndicatorOffsetY", layer = "restedStateIndicatorLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPLEFT", defaultX = 0, defaultY = 0, text = "Z", color = { 0.34, 0.62, 1.0 }, label = "Rested icon", refresh = "MSUF_RequestStatusRestingIndicatorRefresh", defaultShow = false, allowed = function(k) return k == "player" end },
    { id = "statusIncomingRes", show = "showIncomingResIndicator", size = "incomingResIndicatorSize", anchor = "incomingResIndicatorAnchor", x = "incomingResIndicatorOffsetX", y = "incomingResIndicatorOffsetY", layer = "incomingResIndicatorLayer", defaultLayer = 7, defaultSize = 18, defaultAnchor = "TOPRIGHT", defaultX = 0, defaultY = 0, text = "+", color = { 0.22, 1.0, 0.56 }, label = "Incoming Rez icon", refresh = "MSUF_RequestStatusIncomingResIndicatorRefresh", allowed = function(k) return k == "player" or k == "target" end },
}

local PREVIEW_LAYERS = {
    { key = "body", label = "Body", color = { 0.36, 0.62, 0.95 } },
    { key = "nameText", label = "Name", color = { 0.30, 0.66, 1.00 } },
    { key = "hpText", label = "HP Text", color = { 0.25, 0.90, 0.42 } },
    { key = "powerText", label = "Pwr Text", color = { 0.95, 0.72, 0.18 } },
    { key = "portrait", label = "Portrait", color = { 0.90, 0.42, 1.00 } },
    { key = "power", label = "Power", color = { 0.95, 0.72, 0.18 } },
    { key = "classPower", label = "Class", color = { 0.30, 0.78, 0.55 } },
    { key = "castbar", label = "Cast", color = { 0.20, 0.90, 0.85 } },
    { key = "status", label = "Status", color = { 0.85, 0.70, 0.25 } },
    { key = "bounds", label = "Bounds", color = { 1.00, 0.22, 0.12 } },
}

local function BuildPreview(parent, panel, width, height)
    local sideW = 72
    local T = MenuTheme()
    local colors = (T and T.colors) or {}
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width or 632, height or 228)
    ApplyPreviewBackdrop(
        box,
        colors.panel2 or { 0.035, 0.043, 0.058, 0.96 },
        colors.border or { 0.19, 0.25, 0.34, 0.95 }
    )
    box._msufStaticH = height or 228
    box._msufPanel = panel

    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    title:SetText(TR("Unit Frame Preview"))
    box.title = title

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetText(TR("click layers to hide - drag preview elements - arrows nudge selected"))
    box.hint = hint

    local canvas = CreateFrame("Frame", nil, box, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(sideW + 18), 12)
    ApplyPreviewBackdrop(
        canvas,
        { 0, 0, 0, 1 },
        colors.borderSoft or { 1, 1, 1, 0.06 },
        { backdrop = { bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 }, bg = { 0.01, 0.012, 0.018, 0.86 } }
    )
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    box.canvas = canvas

    local sidebar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", canvas, "TOPRIGHT", 6, 0)
    sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    ApplyPreviewBackdrop(
        sidebar,
        colors.panel or { 0.025, 0.028, 0.04, 0.82 },
        colors.borderSoft or { 0.10, 0.13, 0.18, 0.65 },
        { backdrop = { bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 } }
    )
    box.sidebar = sidebar

    local sHdr = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sHdr:SetPoint("TOP", sidebar, "TOP", 0, -5)
    sHdr:SetText(TR("LAYERS"))
    sHdr:SetTextColor(0.45, 0.50, 0.62, 0.8)

    box.layerVisibility = {}
    box.layerButtons = {}
    for i = 1, #PREVIEW_LAYERS do
        local def = PREVIEW_LAYERS[i]
        box.layerVisibility[def.key] = true
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(sideW - 10, 18)
        btn:SetPoint("TOP", sidebar, "TOP", 0, -(20 + (i - 1) * 20))
        btn:EnableMouse(true)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bg = bg
        local bar = btn:CreateTexture(nil, "ARTWORK")
        bar:SetSize(2, 14)
        bar:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn.bar = bar
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("LEFT", bar, "RIGHT", 5, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(TR(def.label))
        btn.fs = fs
        local off = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        off:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        off:SetText("OFF")
        off:SetJustifyH("RIGHT")
        off:Hide()
        btn.off = off
        btn.key = def.key
        btn.color = def.color
        btn.refresh = function(self)
            local on = box.layerVisibility[self.key] ~= false
            local available = not (box.layerAvailable and box.layerAvailable[self.key] == false)
            local c = self.color
            self.off:SetShown(not available)
            if not available then
                self.bg:SetColorTexture(0.020, 0.020, 0.028, 0.48)
                self.bar:SetColorTexture(0.18, 0.18, 0.22, 0.35)
                self.fs:SetTextColor(0.30, 0.30, 0.36, 0.55)
                self.off:SetTextColor(0.36, 0.36, 0.42, 0.65)
            elseif on then
                self.bg:SetColorTexture(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 0.58)
                self.bar:SetColorTexture(c[1], c[2], c[3], 0.88)
                self.fs:SetTextColor(0.76, 0.80, 0.90, 0.95)
            else
                self.bg:SetColorTexture(0.035, 0.035, 0.045, 0.35)
                self.bar:SetColorTexture(0.18, 0.18, 0.22, 0.32)
                self.fs:SetTextColor(0.30, 0.30, 0.36, 0.55)
            end
        end
        btn:SetScript("OnClick", function(self)
            if box.layerAvailable and box.layerAvailable[self.key] == false then
                box.hint:SetText(TR("This layer is off in settings and cannot be shown in preview."))
                return
            end
            box.layerVisibility[self.key] = (box.layerVisibility[self.key] == false)
            for j = 1, #box.layerButtons do box.layerButtons[j]:refresh() end
            Preview.Refresh(box)
        end)
        btn:SetScript("OnEnter", function(self)
            local c = self.color
            if box.layerAvailable and box.layerAvailable[self.key] == false then
                self.bg:SetColorTexture(0.045, 0.045, 0.055, 0.62)
                self.fs:SetTextColor(0.42, 0.42, 0.48, 0.75)
                box.hint:SetText(TR("This layer is off in settings and cannot be shown in preview."))
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(TR("Layer disabled"), 1, 1, 1)
                    GameTooltip:AddLine(TR("Turn this feature on in settings to make the preview layer available."), 0.82, 0.82, 0.82, true)
                    GameTooltip:Show()
                end
            elseif box.layerVisibility[self.key] ~= false then
                self.bg:SetColorTexture(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 0.78)
                if GameTooltip then GameTooltip:Hide() end
            else
                self.bg:SetColorTexture(0.08, 0.08, 0.10, 0.55)
                if GameTooltip then GameTooltip:Hide() end
            end
            if not (box.layerAvailable and box.layerAvailable[self.key] == false) then
                self.fs:SetTextColor(0.90, 0.92, 1.0, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            self:refresh()
            UpdateHandleHint(box, box._selectedHandle)
        end)
        box.layerButtons[#box.layerButtons + 1] = btn
        btn:refresh()
    end

    local mock = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock:SetBackdropColor(0, 0, 0, 0.92)
    do
        local r, g, b = PreviewBaseEdgeColor()
        mock:SetBackdropBorderColor(r, g, b, 1)
    end
    box.mock = mock

    mock.bounds = CreateFrame("Frame", nil, mock, "BackdropTemplate")
    mock.bounds:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.bounds:SetBackdropColor(0, 0, 0, 0)
    mock.bounds:SetBackdropBorderColor(1, 0.14, 0.08, 0.95)
    mock.bounds:SetFrameLevel((mock:GetFrameLevel() or 0) + 28)
    mock.bounds:SetAllPoints(mock)

    mock.sizeTag = mock.bounds:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.sizeTag:SetPoint("BOTTOM", mock.bounds, "TOP", 0, 2)
    mock.sizeTag:SetTextColor(1, 0.35, 0.25, 0.95)

    mock.hpBG = mock:CreateTexture(nil, "BACKGROUND")
    mock.hpBG:SetTexture(TEX_W8)
    mock.hpBG:SetColorTexture(0, 0, 0, 0.82)
    mock.hp = mock:CreateTexture(nil, "ARTWORK")
    SetTex(mock.hp, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    mock.healPred = mock:CreateTexture(nil, "ARTWORK")
    mock.healPred:SetTexture(TEX_W8)
    mock.healPred:SetVertexColor(0, 1, 0.4, 0.55)
    mock.absorb = mock:CreateTexture(nil, "ARTWORK")
    mock.absorb:SetTexture(TEX_W8)
    mock.absorb:SetVertexColor(0.55, 0.70, 1, 0.58)
    mock.powerBG = mock:CreateTexture(nil, "BACKGROUND")
    mock.powerBG:SetTexture(TEX_W8)
    mock.powerBG:SetColorTexture(0, 0, 0, 0.9)
    mock.power = mock:CreateTexture(nil, "ARTWORK")
    SetTex(mock.power, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)

    mock.classPower = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.classPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.classPower:SetBackdropColor(0, 0, 0, 0.55)
    mock.classPower:SetBackdropBorderColor(0, 0, 0, 1)
    mock.classPower.segments = {}
    for i = 1, 6 do
        local seg = mock.classPower:CreateTexture(nil, "ARTWORK")
        seg:SetTexture(TEX_W8)
        mock.classPower.segments[i] = seg
    end

    mock.detachedPower = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.detachedPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.detachedPower:SetBackdropColor(0, 0, 0, 0.82)
    mock.detachedPower:SetBackdropBorderColor(0, 0, 0, 1)
    mock.detachedPower.fill = mock.detachedPower:CreateTexture(nil, "ARTWORK")
    SetTex(mock.detachedPower.fill, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    mock.detachedPower.fill:SetPoint("TOPLEFT", mock.detachedPower, "TOPLEFT", 1, -1)
    mock.detachedPower.fill:SetPoint("BOTTOMLEFT", mock.detachedPower, "BOTTOMLEFT", 1, 1)

    mock.portrait = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.portrait:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.portrait:SetBackdropColor(0.03, 0.035, 0.05, 1)
    mock.portrait:SetBackdropBorderColor(0.72, 0.72, 0.80, 0.82)
    mock.portrait.tex = mock.portrait:CreateTexture(nil, "ARTWORK")
    mock.portrait.tex:SetPoint("TOPLEFT", 2, -2)
    mock.portrait.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    mock.portrait.initial = MakeFS(mock.portrait, "OVERLAY", 22)
    mock.portrait.initial:SetPoint("CENTER")

    mock.textFrame = CreateFrame("Frame", nil, mock)
    mock.textFrame:SetAllPoints(mock)
    mock.nameLayer = CreateFrame("Frame", nil, mock.textFrame)
    mock.nameLayer:SetAllPoints(mock.textFrame)
    mock.hpLayer = CreateFrame("Frame", nil, mock.textFrame)
    mock.hpLayer:SetAllPoints(mock.textFrame)
    mock.powerLayer = CreateFrame("Frame", nil, mock.textFrame)
    mock.powerLayer:SetAllPoints(mock.textFrame)
    mock.nameText = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.raidGroupNameText = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.totInlineSep = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.totInlineText = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.hpTextLeft = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.hpTextCenter = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.hpText = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.hpTextPct = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.powerTextLeft = MakeFS(mock.powerLayer, "OVERLAY", 12)
    mock.powerTextCenter = MakeFS(mock.powerLayer, "OVERLAY", 12)
    mock.powerText = MakeFS(mock.powerLayer, "OVERLAY", 12)
    mock.powerTextPct = MakeFS(mock.powerLayer, "OVERLAY", 12)

    mock.cast = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.cast:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.cast:SetBackdropColor(0, 0, 0, 0.92)
    mock.cast:SetBackdropBorderColor(0, 0, 0, 1)
    mock.cast:EnableMouse(true)
    mock.cast:SetScript("OnMouseUp", function()
        local p = box and box._msufPanel
        if p and type(p._msufOpenUnitSection) == "function" then p._msufOpenUnitSection("castbar") end
    end)
    mock.cast:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Castbar"), 1, 1, 1)
            GameTooltip:AddLine(TR("Preview follows the current castbar visibility, icon, text, and global color settings."), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end
    end)
    mock.cast:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mock.cast.fill = mock.cast:CreateTexture(nil, "ARTWORK")
    SetTex(mock.cast.fill, type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture() or TEX_W8)
    mock.cast.fill:SetPoint("TOPLEFT", 1, -1)
    mock.cast.fill:SetPoint("BOTTOMRIGHT", -60, 1)
    mock.cast.icon = CreateFrame("Frame", nil, mock.cast, "BackdropTemplate")
    mock.cast.icon:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.cast.icon:SetBackdropColor(0.08, 0.12, 0.22, 1)
    mock.cast.icon:SetBackdropBorderColor(0.2, 0.28, 0.40, 1)
    mock.cast.text = MakeFS(mock.cast, "OVERLAY", 11)
    mock.cast.text:SetPoint("LEFT", mock.cast, "LEFT", 24, 0)
    mock.cast.time = MakeFS(mock.cast, "OVERLAY", 11)
    mock.cast.time:SetPoint("RIGHT", mock.cast, "RIGHT", -6, 0)
    mock.cast.sizeTag = mock.cast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.cast.sizeTag:SetPoint("BOTTOM", mock.cast, "TOP", 0, 2)
    mock.cast.sizeTag:SetTextColor(0.20, 0.90, 0.85, 0.95)

    mock.icons = {}
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        mock.icons[spec.id] = CreateIcon(canvas, spec.color, spec.text)
    end

    box.handles = {}
    box.dragFrame = CreateFrame("Frame", nil, canvas)
    box.dragFrame:Hide()
    box._onDragUpdate = function(df)
        local h = df._handle
        if not h then return end
        local cx, cy = GetCursorPosition()
        local scale = box._mockScale or 1
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiScale <= 0 then uiScale = 1 end
        local dx = (((cx or 0) - (h._cursorX or 0)) / uiScale) / scale
        local dy = (((cy or 0) - (h._cursorY or 0)) / uiScale) / scale
        local nextX = RoundOffset((h._startX or 0) + dx)
        local nextY = RoundOffset((h._startY or 0) + dy)
        if h._lastDragX == nextX and h._lastDragY == nextY then return end
        h._lastDragX = nextX
        h._lastDragY = nextY
        WriteHandleOffsets(h, nextX, nextY, "UNIT_PREVIEW_DRAG")
    end

    box.handleName = MakeHandle(box, "name", { x = "nameOffsetX", y = "nameOffsetY", defaultX = 4, defaultY = -4, text = true, section = "text" }, "Name text", { 0.30, 0.66, 1.0 })
    box.handleRaidGroupName = MakeHandle(box, "raidgroupname", { x = "raidGroupNameOffsetX", y = "raidGroupNameOffsetY", defaultX = 3, defaultY = 0, statusRefresh = "MSUF_RefreshRaidGroupNameFrames", section = "status" }, "Raid group", { 0.45, 0.70, 1.0 })
    box.handleHP = MakeHandle(box, "hp", { x = "hpOffsetX", y = "hpOffsetY", defaultX = -4, defaultY = -4, text = true, section = "text" }, "HP text", { 0.25, 0.90, 0.42 })
    box.handleHPLeft = MakeHandle(box, "hpLeft", { x = "hpTextLeftOffsetX", y = "hpTextLeftOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "HP left text", { 0.25, 0.90, 0.42 })
    box.handleHPCenter = MakeHandle(box, "hpCenter", { x = "hpTextCenterOffsetX", y = "hpTextCenterOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "HP center text", { 0.25, 0.90, 0.42 })
    box.handleHPRight = MakeHandle(box, "hpRight", { x = "hpTextRightOffsetX", y = "hpTextRightOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "HP right text", { 0.25, 0.90, 0.42 })
    box.handlePower = MakeHandle(box, "power", { x = "powerOffsetX", y = "powerOffsetY", defaultX = -4, defaultY = 4, text = true, section = "text" }, "Power text", { 0.95, 0.72, 0.18 })
    box.handlePowerLeft = MakeHandle(box, "powerLeft", { x = "powerTextLeftOffsetX", y = "powerTextLeftOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "Power left text", { 0.95, 0.72, 0.18 })
    box.handlePowerCenter = MakeHandle(box, "powerCenter", { x = "powerTextCenterOffsetX", y = "powerTextCenterOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "Power center text", { 0.95, 0.72, 0.18 })
    box.handlePowerRight = MakeHandle(box, "powerRight", { x = "powerTextRightOffsetX", y = "powerTextRightOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "Power right text", { 0.95, 0.72, 0.18 })
    box.handlePortrait = MakeHandle(box, "portrait", { x = "portraitOffsetX", y = "portraitOffsetY", defaultX = 0, defaultY = 0, portrait = true, section = "portrait" }, "Portrait", { 0.90, 0.42, 1.0 })
    box.handleDetachedPower = MakeHandle(box, "detachedPower", { x = "detachedPowerBarOffsetX", y = "detachedPowerBarOffsetY", defaultX = 0, defaultY = -4, detachedPower = true, section = "power" }, "Detached power bar", { 0.95, 0.72, 0.18 })
    box.handleCastbar = MakeHandle(box, "castbar", { castbar = true, global = true, section = "castbar" }, "Castbar", { 0.20, 0.90, 0.85 })
    box.statusHandles = { raidgroupname = box.handleRaidGroupName }
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        box.statusHandles[spec.id] = MakeHandle(box, spec.id, { x = spec.x, y = spec.y, defaultX = spec.defaultX or 0, defaultY = spec.defaultY or 0, statusRefresh = spec.refresh, section = "status" }, spec.label, spec.color)
    end

    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", PreviewArrowKeyDown)

    box:SetScript("OnShow", function(self)
        Preview.active = self
        if self.RegisterEvent then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
        end
        Preview.RequestRefresh("SHOW")
    end)
    box:SetScript("OnHide", function(self)
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
        self._selectedHandle = nil
        RefreshHandleSelectionVisuals(self)
        if Preview.active == self then Preview.active = nil end
        self.dragFrame:SetScript("OnUpdate", nil)
        self.dragFrame._handle = nil
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
    box:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            Preview.RequestRefresh("COMBAT_ALPHA")
        elseif event == "PLAYER_REGEN_DISABLED" then
            box._refreshReason = nil
            box._refreshQueued = nil
        end
    end)

    return box
end

local function CastbarEnabled(key, g)
    if key == "player" then return g.enablePlayerCastbar ~= false end
    if key == "target" then return g.enableTargetCastbar ~= false end
    if key == "focus" then return g.enableFocusCastbar ~= false end
    if key == "boss" then return g.enableBossCastbar ~= false end
    return false
end

local function CastbarShowIcon(key, g)
    if key == "boss" then return g.showBossCastIcon ~= false end
    if key == "player" and g.castbarPlayerShowIcon ~= nil then return g.castbarPlayerShowIcon ~= false end
    if key == "target" and g.castbarTargetShowIcon ~= nil then return g.castbarTargetShowIcon ~= false end
    if key == "focus" and g.castbarFocusShowIcon ~= nil then return g.castbarFocusShowIcon ~= false end
    return g.castbarShowIcon ~= false
end

local function CastbarShowText(key, g)
    if key == "boss" then return g.showBossCastName ~= false end
    if key == "player" and g.castbarPlayerShowSpellName ~= nil then return g.castbarPlayerShowSpellName ~= false end
    if key == "target" and g.castbarTargetShowSpellName ~= nil then return g.castbarTargetShowSpellName ~= false end
    if key == "focus" and g.castbarFocusShowSpellName ~= nil then return g.castbarFocusShowSpellName ~= false end
    return g.castbarShowSpellName ~= false
end

local function PlaceHandle(handle, target, pad)
    if not handle or not target or not target.GetCenter then return end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", target, "CENTER", pad or 0, 0)
    handle:SetShown(target:IsShown())
end

local function SetShownSafe(region, shown)
    if region and region.SetShown then region:SetShown(shown and true or false) end
end

local function ReadPreviewBarsBool(key, default)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local value = bars and bars[key]
    if value == nil then return default and true or false end
    return value and true or false
end

local function ClampPreviewEdgeSize(value, fallback, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    n = floor(n + 0.5)
    if n < 0 then n = 0 end
    maxValue = tonumber(maxValue) or 8
    if n > maxValue then n = maxValue end
    return n
end

local function PreviewRoundedOutlineThickness(key, conf, scale)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local raw
    if conf and conf.hlOverride and conf.barOutlineThickness ~= nil then
        raw = conf.barOutlineThickness
    else
        raw = bars and bars.barOutlineThickness
    end
    local t = ClampPreviewEdgeSize(raw, 1, 8)
    if t > 0 and scale then
        t = floor(t * scale + 0.5)
        if t < 1 then t = 1 end
    end
    return t
end

local function PreviewRoundedUnitFramesEnabled()
    return ReadPreviewBarsBool("roundedFramesEnabled", false)
        and ReadPreviewBarsBool("roundedUnitFrames", true)
end

local function PreviewRoundedPowerBarsEnabled()
    return ReadPreviewBarsBool("roundedFramesEnabled", false)
        and ReadPreviewBarsBool("roundedPowerBars", true)
end

local function PreviewSnapOff(region)
    if PreviewHelpers.SnapOff then PreviewHelpers.SnapOff(region) end
end

local function EnsurePreviewRoundedMask(mock, key, anchor, tex)
    if not PreviewHelpers.EnsureRoundedMask then return nil end
    return PreviewHelpers.EnsureRoundedMask(mock, key, anchor, tex, "_msufPreviewRoundedMasks", PREVIEW_ROUNDED_MASK, PreviewSnapOff)
end

local function PreviewSetMask(mock, tex, mask)
    if PreviewHelpers.SetMask then PreviewHelpers.SetMask(mock, tex, mask, "_msufPreviewRoundedMasked") end
end

local function ClearPreviewRoundedMasks(mock)
    if PreviewHelpers.ClearMasks then PreviewHelpers.ClearMasks(mock, "_msufPreviewRoundedMasked") end
end

function PreviewBaseEdgeColor()
    if PreviewHelpers.BaseEdgeColor then return PreviewHelpers.BaseEdgeColor() end
    return 0, 0, 0, 1
end

local function EnsurePreviewRoundedVisuals(mock)
    if not (mock and mock.CreateTexture) then return false end
    if not mock.roundedBg then
        mock.roundedBg = mock:CreateTexture(nil, "BACKGROUND")
        mock.roundedBg:SetTexture(TEX_W8)
        PreviewSnapOff(mock.roundedBg)
    end
    if not mock.roundedEdge then
        mock.roundedEdge = mock:CreateTexture(nil, "OVERLAY")
        PreviewSnapOff(mock.roundedEdge)
    end
    mock.roundedEdge:SetTexture(PREVIEW_ROUNDED_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return true
end

local function PreviewForEachRoundedEdge(mock, fn)
    if not (mock and type(fn) == "function") then return end
    if mock.roundedEdge then fn(mock.roundedEdge, 1) end
    local stack = mock._msufPreviewRoundedEdgeStack
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        if stack[i] then fn(stack[i], i) end
    end
end

local function PreviewSetRoundedEdgeStackShown(mock, shown)
    local count = shown and ClampPreviewEdgeSize(mock and mock._msufPreviewRoundedEdgeCount, 1, 8) or 0
    PreviewForEachRoundedEdge(mock, function(edge, i)
        SetShownSafe(edge, i <= count)
    end)
end

local function PreviewSetRoundedEdgeStackAlpha(mock, alpha)
    alpha = Clamp01(alpha, 1)
    PreviewForEachRoundedEdge(mock, function(edge)
        if edge and edge.SetAlpha then edge:SetAlpha(alpha) end
    end)
end

local function PreviewApplyRoundedEdgeStack(mock, edgeSize)
    local count = ClampPreviewEdgeSize(edgeSize, 0, 8)
    mock._msufPreviewRoundedEdgeCount = count
    if count <= 0 then
        PreviewSetRoundedEdgeStackShown(mock, false)
        return false
    end

    mock._msufPreviewRoundedEdgeStack = mock._msufPreviewRoundedEdgeStack or {}
    mock._msufPreviewRoundedEdgeStack[1] = mock.roundedEdge
    local r, g, b, a = PreviewBaseEdgeColor()
    for i = 1, count do
        local edge = (i == 1) and mock.roundedEdge or mock._msufPreviewRoundedEdgeStack[i]
        if not edge then
            edge = mock:CreateTexture(nil, "OVERLAY")
            PreviewSnapOff(edge)
            mock._msufPreviewRoundedEdgeStack[i] = edge
        end
        edge:SetTexture(PREVIEW_ROUNDED_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", mock, "TOPLEFT", -i, i)
        edge:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", i, -i)
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
    end
    PreviewSetRoundedEdgeStackShown(mock, true)
    return true
end

local function ApplyPreviewRounded(box, key, powerOn, outlineThickness)
    if not (box and box.mock) then return end
    local mock = box.mock
    local rounded = PreviewRoundedUnitFramesEnabled()
    if not rounded or not EnsurePreviewRoundedVisuals(mock) then
        mock._msufPreviewRoundedActive = nil
        mock._msufPreviewRoundedEdgeEnabled = nil
        ClearPreviewRoundedMasks(mock)
        SetShownSafe(mock.roundedBg, false)
        PreviewSetRoundedEdgeStackShown(mock, false)
        return
    end
    mock._msufPreviewRoundedActive = true

    local bodyMask = EnsurePreviewRoundedMask(mock, "body", mock, mock.roundedBg)
    local hpBgMask = EnsurePreviewRoundedMask(mock, "health", mock.hpBG, mock.hpBG)
    local hpMask = EnsurePreviewRoundedMask(mock, "health", mock.hpBG, mock.hp)
    local healPredMask = EnsurePreviewRoundedMask(mock, "healPred", mock.hpBG, mock.healPred)
    local absorbMask = EnsurePreviewRoundedMask(mock, "absorb", mock.hpBG, mock.absorb)
    local conf, g = UnitDB(key)
    local healPredMode = PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = PreviewResolveAbsorbAnchorMode(conf, g)
    PreviewSetMask(mock, mock.roundedBg, bodyMask)
    PreviewSetMask(mock, mock.hpBG, hpBgMask)
    PreviewSetMask(mock, mock.hp, hpMask)
    PreviewSetMask(mock, mock.healPred, healPredMode == 4 and nil or healPredMask)
    PreviewSetMask(mock, mock.absorb, absorbMode == 4 and nil or absorbMask)

    local powerBgMask = (powerOn and PreviewRoundedPowerBarsEnabled()) and EnsurePreviewRoundedMask(mock, "power", mock.powerBG, mock.powerBG) or nil
    local powerMask = (powerOn and PreviewRoundedPowerBarsEnabled()) and EnsurePreviewRoundedMask(mock, "power", mock.powerBG, mock.power) or nil
    PreviewSetMask(mock, mock.powerBG, powerBgMask)
    PreviewSetMask(mock, mock.power, powerMask)

    mock.roundedBg:ClearAllPoints()
    mock.roundedBg:SetAllPoints(mock)
    mock.roundedBg:SetColorTexture(0, 0, 0, 0.92)
    mock.roundedBg:Show()

    local edgeSize = ClampPreviewEdgeSize(outlineThickness, 1, 30)
    mock._msufPreviewRoundedEdgeEnabled = edgeSize > 0
    if edgeSize > 0 then
        PreviewApplyRoundedEdgeStack(mock, edgeSize)
    else
        PreviewSetRoundedEdgeStackShown(mock, false)
    end

    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    if mock.SetBackdropBorderColor then mock:SetBackdropBorderColor(0, 0, 0, 0) end
end

local function ApplyPreviewLayerVisibility(box)
    if not box or not box.mock then return end
    local v = box.layerVisibility or {}
    local available = box.layerAvailable or {}
    local function LayerOn(key)
        return available[key] ~= false and v[key] ~= false
    end
    local mock = box.mock
    local bodyOn = LayerOn("body")
    local powerOn = LayerOn("power")
    local nameOn = LayerOn("nameText")
    local hpTextOn = LayerOn("hpText")
    local powerTextOn = LayerOn("powerText")
    local portraitOn = LayerOn("portrait")
    local classOn = LayerOn("classPower")
    local castOn = LayerOn("castbar")
    local statusOn = LayerOn("status")
    local boundsOn = LayerOn("bounds")

    local roundedActive = mock._msufPreviewRoundedActive == true
    if bodyOn then
        if roundedActive then
            mock:SetBackdropColor(0, 0, 0, 0)
            mock:SetBackdropBorderColor(0, 0, 0, 0)
            SetShownSafe(mock.roundedBg, true)
            PreviewSetRoundedEdgeStackShown(mock, mock._msufPreviewRoundedEdgeEnabled ~= false)
        else
            local r, g, b = PreviewBaseEdgeColor()
            mock:SetBackdropColor(0, 0, 0, 0.92)
            mock:SetBackdropBorderColor(r, g, b, 1)
            SetShownSafe(mock.roundedBg, false)
            PreviewSetRoundedEdgeStackShown(mock, false)
        end
    else
        mock:SetBackdropColor(0, 0, 0, 0)
        mock:SetBackdropBorderColor(0, 0, 0, 0)
        SetShownSafe(mock.roundedBg, false)
        PreviewSetRoundedEdgeStackShown(mock, false)
    end
    SetShownSafe(mock.hpBG, bodyOn)
    SetShownSafe(mock.hp, bodyOn)
    if not bodyOn then
        SetShownSafe(mock.healPred, false)
        SetShownSafe(mock.absorb, false)
    end

    if not powerOn then
        SetShownSafe(mock.powerBG, false)
        SetShownSafe(mock.power, false)
        SetShownSafe(mock.detachedPower, false)
        SetShownSafe(box.handleDetachedPower, false)
    end
    if not classOn then SetShownSafe(mock.classPower, false) end
    if mock.classPower and mock.classPower.segments and (not classOn or not mock.classPower:IsShown()) then
        for i = 1, #mock.classPower.segments do SetShownSafe(mock.classPower.segments[i], false) end
    end
    if not nameOn then
        SetShownSafe(mock.nameText, false)
        SetShownSafe(mock.totInlineSep, false)
        SetShownSafe(mock.totInlineText, false)
        SetShownSafe(box.handleName, false)
    end
    if not hpTextOn then
        SetShownSafe(mock.hpTextLeft, false)
        SetShownSafe(mock.hpTextCenter, false)
        SetShownSafe(mock.hpText, false)
        SetShownSafe(mock.hpTextPct, false)
        SetShownSafe(box.handleHP, false)
        SetShownSafe(box.handleHPLeft, false)
        SetShownSafe(box.handleHPCenter, false)
        SetShownSafe(box.handleHPRight, false)
    end
    if not powerTextOn then
        SetShownSafe(mock.powerTextLeft, false)
        SetShownSafe(mock.powerTextCenter, false)
        SetShownSafe(mock.powerText, false)
        SetShownSafe(mock.powerTextPct, false)
        SetShownSafe(box.handlePower, false)
        SetShownSafe(box.handlePowerLeft, false)
        SetShownSafe(box.handlePowerCenter, false)
        SetShownSafe(box.handlePowerRight, false)
    end
    if not portraitOn then
        SetShownSafe(mock.portrait, false)
        SetShownSafe(box.handlePortrait, false)
    end
    if not castOn then
        SetShownSafe(mock.cast, false)
        SetShownSafe(box.handleCastbar, false)
    end
    if not statusOn then
        for _, icon in pairs(mock.icons or {}) do SetShownSafe(icon, false) end
        SetShownSafe(mock.raidGroupNameText, false)
        for _, handle in pairs(box.statusHandles or {}) do SetShownSafe(handle, false) end
    end
    SetShownSafe(mock.bounds, boundsOn)
end

local function NormalizePreviewAlphaLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" then return "background" end
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then return "health" end
    return "foreground"
end

local function PreviewInCombat()
    local inCombat = _G.MSUF_InCombat
    if inCombat == nil and _G.InCombatLockdown then inCombat = _G.InCombatLockdown() end
    return inCombat == true
end

local function PreviewAlphaPair(conf, mode)
    if not conf then return 1, 1 end
    mode = NormalizePreviewAlphaLayerMode(mode or conf.alphaLayerMode)
    local aIn = Clamp01(conf.alphaInCombat, 1)
    local aOut = Clamp01(conf.alphaOutOfCombat, 1)
    if conf.alphaExcludeTextPortrait == true then
        if mode == "background" then
            aIn = Clamp01(conf.alphaBGInCombat, aIn)
            aOut = Clamp01(conf.alphaBGOutOfCombat, aOut)
        elseif mode == "health" then
            aIn = Clamp01(conf.alphaHPInCombat, Clamp01(conf.alphaFGInCombat, aIn))
            aOut = Clamp01(conf.alphaHPOutOfCombat, Clamp01(conf.alphaFGOutOfCombat, aOut))
        else
            aIn = Clamp01(conf.alphaFGInCombat, aIn)
            aOut = Clamp01(conf.alphaFGOutOfCombat, aOut)
        end
    end
    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end
    if sync then aOut = aIn end
    return aIn, aOut
end

local function PreviewCurrentAlpha(conf, mode)
    local aIn, aOut = PreviewAlphaPair(conf, mode)
    return PreviewInCombat() and aIn or aOut
end

local function PreviewAlphaState(conf)
    local frameAlpha = PreviewCurrentAlpha(conf, "foreground")
    if _G.MSUF_UnitEditModeActive == true and frameAlpha < 0.35 then frameAlpha = 0.35 end
    local state = {
        flat = true,
        frame = frameAlpha,
        fg = 1,
        bg = 1,
        hp = 1,
        power = 1,
        text = 1,
        portrait = 1,
        preserveHPColor = false,
    }
    if conf and conf.alphaExcludeTextPortrait == true then
        local mode = NormalizePreviewAlphaLayerMode(conf.alphaLayerMode)
        local fg = PreviewCurrentAlpha(conf, "foreground")
        local bg = PreviewCurrentAlpha(conf, "background")
        local hp = (mode == "health") and PreviewCurrentAlpha(conf, "health") or fg
        state.flat = false
        state.frame = 1
        state.fg = fg
        state.bg = bg
        state.hp = hp
        state.power = (mode == "health") and 1 or fg
        state.text = 1
        state.portrait = 1
        state.preserveHPColor = conf.alphaPreserveHPColor == true
    end
    return state
end

local function SetRegionAlpha(region, alpha)
    if region and region.SetAlpha then region:SetAlpha(Clamp01(alpha, 1)) end
end

local function SetFrameBackdropAlpha(frame, bgAlpha, borderAlpha)
    if not frame or not frame.SetBackdropColor then return end
    frame:SetBackdropColor(0, 0, 0, Clamp01(bgAlpha, 1))
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, Clamp01(borderAlpha, 1)) end
end

local function ApplyPreviewTransparency(box, conf)
    if not box or not box.mock then return end
    local mock = box.mock
    local alpha = PreviewAlphaState(conf)
    local v = box.layerVisibility or {}
    local available = box.layerAvailable or {}
    local bodyOn = available.body ~= false and v.body ~= false

    if mock.SetAlpha then mock:SetAlpha(1) end
    if bodyOn then
        if mock._msufPreviewRoundedActive == true then
            SetFrameBackdropAlpha(mock, 0, 0)
            SetRegionAlpha(mock.roundedBg, 0.92 * (alpha.flat and alpha.frame or alpha.bg))
            PreviewSetRoundedEdgeStackAlpha(mock, (mock._msufPreviewRoundedEdgeEnabled ~= false) and (alpha.flat and alpha.frame or alpha.fg) or 0)
        else
            SetFrameBackdropAlpha(mock, 0.92 * (alpha.flat and alpha.frame or alpha.bg), alpha.flat and alpha.frame or alpha.fg)
        end
    else
        SetFrameBackdropAlpha(mock, 0, 0)
        SetRegionAlpha(mock.roundedBg, 0)
        PreviewSetRoundedEdgeStackAlpha(mock, 0)
    end

    if alpha.preserveHPColor then
        SetRegionAlpha(mock.hpBG, alpha.hp)
    else
        SetRegionAlpha(mock.hpBG, alpha.flat and alpha.frame or alpha.bg)
    end
    SetRegionAlpha(mock.hp, alpha.flat and alpha.frame or alpha.hp)
    SetRegionAlpha(mock.healPred, alpha.flat and alpha.frame or alpha.hp)
    SetRegionAlpha(mock.absorb, alpha.flat and alpha.frame or alpha.hp)
    SetRegionAlpha(mock.powerBG, alpha.flat and alpha.frame or alpha.bg)
    SetRegionAlpha(mock.power, alpha.flat and alpha.frame or alpha.power)
    SetRegionAlpha(mock.classPower, alpha.flat and alpha.frame or alpha.power)
    SetRegionAlpha(mock.detachedPower, alpha.flat and alpha.frame or alpha.power)
    if mock.detachedPower and mock.detachedPower.fill then SetRegionAlpha(mock.detachedPower.fill, 1) end
    SetRegionAlpha(mock.portrait, alpha.flat and alpha.frame or alpha.portrait)
    SetRegionAlpha(mock.textFrame, alpha.flat and alpha.frame or alpha.text)
    SetRegionAlpha(mock.cast, alpha.flat and alpha.frame or alpha.fg)
    for _, icon in pairs(mock.icons or {}) do
        SetRegionAlpha(icon, alpha.flat and alpha.frame or alpha.fg)
    end
end

do
    local deps = Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    deps.PreviewInCombat = PreviewInCombat
    deps.TR = TR
    deps.PortraitStyleGet = PortraitStyleGet
    deps.max = max
    deps.min = min
    deps.abs = abs
    deps.floor = floor
    deps.format = format
    deps.TEX_W8 = TEX_W8
    deps.FONT = FONT
    deps.CurrentPanelKey = CurrentPanelKey
    deps.UnitDB = UnitDB
    deps.UNIT_DATA = UNIT_DATA
    deps.UNIT_LABELS = UNIT_LABELS
    deps.ReadPowerBarEnabled = ReadPowerBarEnabled
    deps.PreviewRaidGroupNameAllowed = PreviewRaidGroupNameAllowed
    deps.PreviewRaidGroupNameText = PreviewRaidGroupNameText
    deps.NormalizeRaidGroupNameAnchor = NormalizePreviewRaidGroupNameAnchor
    deps.STATUS_PREVIEW = STATUS_PREVIEW
    deps.CastbarEnabled = CastbarEnabled
    deps.ReadCastbarSize = ReadCastbarSize
    deps.CastbarOffsetFields = CastbarOffsetFields
    deps.CastbarDetached = CastbarDetached
    deps.CanDetachPowerBarKey = CanDetachPowerBarKey
    deps.ClampPreviewLayer = ClampPreviewLayer
    deps.SetTex = SetTex
    deps.ReadPowerBarHeight = ReadPowerBarHeight
    deps.PlaceHandle = PlaceHandle
    deps.UnitPreviewText = UnitPreviewText
    deps.UnitPreviewTextMovesTogether = UnitPreviewTextMovesTogether
    deps.SetShownSafe = SetShownSafe
    deps.ApplyPreviewLayerVisibility = ApplyPreviewLayerVisibility
    deps.ApplyPreviewTransparency = ApplyPreviewTransparency
    deps.RefreshHandleSelectionVisuals = RefreshHandleSelectionVisuals
end

function Preview.Refresh(box, reason)
    box = box or Preview.active
    if not box or not box:IsShown() then return end
    local D = Preview.RefreshDeps
    local PreviewInCombat = D.PreviewInCombat
    if PreviewInCombat() then return end
    local TR = D.TR
    local PortraitStyleGet = D.PortraitStyleGet
    local max, min, abs, floor = D.max, D.min, D.abs, D.floor
    local format, TEX_W8, FONT = D.format, D.TEX_W8, D.FONT
    local CastbarEnabled = D.CastbarEnabled
    local ReadCastbarSize = D.ReadCastbarSize
    local CastbarOffsetFields = D.CastbarOffsetFields
    local CastbarDetached = D.CastbarDetached
    local CanDetachPowerBarKey = D.CanDetachPowerBarKey
    local ClampPreviewLayer = D.ClampPreviewLayer
    local SetTex = D.SetTex
    local ReadPowerBarHeight = D.ReadPowerBarHeight
    local PlaceHandle = D.PlaceHandle
    local UnitPreviewText = D.UnitPreviewText
    local UnitPreviewTextMovesTogether = D.UnitPreviewTextMovesTogether
    local SetShownSafe = D.SetShownSafe
    local ApplyPreviewLayerVisibility = D.ApplyPreviewLayerVisibility
    local ApplyPreviewTransparency = D.ApplyPreviewTransparency
    local RefreshHandleSelectionVisuals = D.RefreshHandleSelectionVisuals
    local panel = box._msufPanel
    local key = D.CurrentPanelKey(panel)
    local conf, g = D.UnitDB(key)
    local data = D.UNIT_DATA[key] or D.UNIT_DATA.player
    box.key = key
    local skipControlRefresh = (reason == "OPTIONS_APPLY_DB" or reason == "UNIT_MENU_ENTER" or reason == "UNIT_MENU_REENTER")
    if panel and panel._msufRefreshUnitTextControls and not skipControlRefresh and not box._refreshingControls then
        box._refreshingControls = true
        panel._msufRefreshUnitTextControls()
        if panel._msufRefreshUnitPortraitControls then panel._msufRefreshUnitPortraitControls() end
        if panel._msufRefreshUnitPowerControls then panel._msufRefreshUnitPowerControls() end
        box._refreshingControls = nil
    end
    if box.title then box.title:SetText(TR("Unit Frame Preview") .. " - " .. TR(D.UNIT_LABELS[key] or key)) end

    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end

    local w = tonumber(conf.width) or (key == "boss" and 160 or 220)
    local h = tonumber(conf.height) or (key == "boss" and 34 or 44)
    if w < 60 then w = 60 elseif w > 520 then w = 520 end
    if h < 18 then h = 18 elseif h > 140 then h = 140 end
    local mode = conf.portraitMode
    local hasPortrait = (mode == "LEFT" or mode == "RIGHT")
    local pSize = hasPortrait and (tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0) or 0
    if pSize <= 0 then pSize = max(22, h - 4) end
    local castEnabled = CastbarEnabled(key, g)
    local castW, castBarH = ReadCastbarSize(key, g, w, 18)
    local castH = castEnabled and castBarH or 0
    local castXKey, castYKey, castDefX, castDefY = CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and CastbarDetached(key, g)
    local castPreviewVisible = castEnabled
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars or {}
    local detachedPower = CanDetachPowerBarKey(key) and conf.powerBarDetached == true and D.ReadPowerBarEnabled(conf, key)
    local classPowerOn = key == "player" and (bars.showClassPower == true or detachedPower)
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and key ~= "player" then powerFrac = 1 end
    if powerFrac < 0 then powerFrac = 0 elseif powerFrac > 1 then powerFrac = 1 end
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local detachedH = detachedPower and (tonumber(conf.detachedPowerBarHeight) or 6) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 80 then detachedH = 80 end
    local wideW = w
    if classPowerOn and bars.classPowerWidthMode == "custom" then wideW = max(wideW, tonumber(bars.classPowerWidth) or w) end
    if detachedPower then wideW = max(wideW, tonumber(conf.detachedPowerBarWidth) or w) end
    local minX, maxX, minY, maxY = 0, w, 0, h
    if hasPortrait then
        local poX = tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0
        local poY = tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0
        local left, right
        if mode == "RIGHT" then
            left, right = w + 4 + poX, w + 4 + poX + pSize
        else
            left, right = -4 + poX - pSize, -4 + poX
        end
        minX, maxX = min(minX, left), max(maxX, right)
        minY, maxY = min(minY, poY - pSize * 0.5 + h * 0.5), max(maxY, poY + pSize * 0.5 + h * 0.5)
    end
    if classPowerOn then
        local cpW = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (w - 4)) or (w - 4)
        local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
        local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + cpH)
    end
    if detachedPower then
        local dW = tonumber(conf.detachedPowerBarWidth) or w
        local dx = tonumber(conf.detachedPowerBarOffsetX) or 0
        local dy = tonumber(conf.detachedPowerBarOffsetY) or -4
        local dLeft, dBottom = dx, -detachedH + dy
        if key == "player" and conf.detachedPowerBarAnchorToClassPower == true and classPowerOn then
            local cpW = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (w - 4)) or (w - 4)
            local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
            local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
            dLeft = cx + (cpW - dW) * 0.5 + dx
            dBottom = cy - detachedH + dy
        end
        minX, maxX = min(minX, dLeft), max(maxX, dLeft + dW)
        minY, maxY = min(minY, dBottom), max(maxY, dBottom + detachedH)
    end
    if castEnabled then
        local cLeft, cBottom
        if castDetached then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = (h - castBarH) * 0.5 + castOffsetY
        elseif key == "player" then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = h + castOffsetY
        else
            cLeft = castOffsetX
            cBottom = h + castOffsetY + ((key == "boss") and 2 or 0)
        end
        local tooFar
        if castDetached then
            tooFar = (abs(castOffsetX) > 260 or abs(castOffsetY) > 180)
        else
            local limitX = max(w * 1.25, 180)
            local limitY = max(h * 3.0, 120)
            tooFar = (cLeft > w + limitX)
                or ((cLeft + castW) < -limitX)
                or (cBottom > h + limitY)
                or ((cBottom + castBarH) < -limitY)
        end
        castPreviewVisible = not tooFar
        if castPreviewVisible then
            wideW = max(wideW, castW)
            minX, maxX = min(minX, cLeft), max(maxX, cLeft + castW)
            minY, maxY = min(minY, cBottom), max(maxY, cBottom + castBarH)
        end
    end
    local footprintW = max(wideW, maxX - minX)
    local footprintH = max(h, maxY - minY)
    local scale = min(1.45, (cw - 60) / max(footprintW, 1), (ch - 42) / max(footprintH, 1))
    if scale < 0.75 then scale = 0.75 end
    box._mockScale = scale
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    local sw, sh, sp = S(w), S(h), S(pSize)
    local mockOffsetX = -S(((minX + maxX) * 0.5) - (w * 0.5))
    local mockOffsetY = -S(((minY + maxY) * 0.5) - (h * 0.5))

    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    if mock.classPower and mock.classPower.SetFrameLevel then
        mock.classPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(bars.classPowerFrameLevelOffset, 5))
    end
    if mock.detachedPower and mock.detachedPower.SetFrameLevel then
        mock.detachedPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(conf.detachedPowerBarFrameLevelOffset, 6))
    end
    if mock.portrait and mock.portrait.SetFrameLevel then mock.portrait:SetFrameLevel(baseLevel + 7) end
    if mock.cast and mock.cast.SetFrameLevel then mock.cast:SetFrameLevel(baseLevel + 6) end
    if mock.textFrame and mock.textFrame.SetFrameLevel then mock.textFrame:SetFrameLevel(baseLevel + 10) end
    local textBase = baseLevel + 12
    if mock.nameLayer and mock.nameLayer.SetFrameLevel then mock.nameLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.nameTextLayer, 5)) end
    if mock.hpLayer and mock.hpLayer.SetFrameLevel then mock.hpLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.hpTextLayer, 5)) end
    if mock.powerLayer and mock.powerLayer.SetFrameLevel then mock.powerLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.powerTextLayer, 2)) end
    if mock.bounds and mock.bounds.SetFrameLevel then mock.bounds:SetFrameLevel(baseLevel + 28) end
    SetTex(mock.hp, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    SetTex(mock.power, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    SetTex(mock.hpBG, type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture() or TEX_W8)
    SetTex(mock.powerBG, type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture() or TEX_W8)
    SetTex(mock.detachedPower.fill, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    SetTex(mock.cast.fill, type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture() or TEX_W8)
    mock:SetSize(sw, sh)
    if mock.sizeTag then mock.sizeTag:SetText(format("%d x %d", w, h)) end
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", canvas, "CENTER", mockOffsetX, mockOffsetY)

    local powerOn = D.ReadPowerBarEnabled(conf, key) and not detachedPower
    local powerH = powerOn and S(ReadPowerBarHeight(conf)) or 0
    if powerOn and powerH < 2 then powerH = 2 end
    mock.hpBG:ClearAllPoints()
    mock.hpBG:SetPoint("TOPLEFT", mock, "TOPLEFT", S(2), -S(2))
    mock.hpBG:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -S(2), powerOn and (S(3) + powerH) or S(2))
    mock.hp:ClearAllPoints()
    local hpReverse = conf.reverseFillBars == true
    if hpReverse then
        mock.hp:SetPoint("TOPRIGHT", mock.hpBG, "TOPRIGHT", 0, 0)
        mock.hp:SetPoint("BOTTOMRIGHT", mock.hpBG, "BOTTOMRIGHT", 0, 0)
    else
        mock.hp:SetPoint("TOPLEFT", mock.hpBG, "TOPLEFT", 0, 0)
        mock.hp:SetPoint("BOTTOMLEFT", mock.hpBG, "BOTTOMLEFT", 0, 0)
    end
    local hpAreaW = max(1, sw - S(4))
    local hpFrac = max(0, min(1, tonumber(data.hp) or 0.6))
    mock.hp:SetWidth(max(1, hpAreaW * hpFrac))
    local healPredMode = PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = PreviewResolveAbsorbAnchorMode(conf, g)
    local healPredShown = PreviewHealPredictionEnabled(g)
    local absorbShown = PreviewAbsorbBarEnabled(conf, g)
    local healPredFrac = ((healPredMode == 3) and min(0.14, max(0.02, 1 - hpFrac))) or 0.14
    if healPredShown then
        local r = tonumber(g and g.healPredColorR) or 0
        local gg = tonumber(g and g.healPredColorG) or 1
        local b = tonumber(g and g.healPredColorB) or 0.4
        mock.healPred:SetVertexColor(r, gg, b, 0.55)
        LayoutUnitPreviewOverlay(mock.healPred, mock.hpBG, mock.hp, healPredMode, healPredFrac, hpReverse, nil, hpAreaW)
    else
        mock.healPred:Hide()
    end
    if absorbShown then
        local absorbAnchor = nil
        if healPredShown and (healPredMode == 3 or healPredMode == 4) and (absorbMode == 3 or absorbMode == 4) then
            absorbAnchor = mock.healPred
        end
        LayoutUnitPreviewOverlay(mock.absorb, mock.hpBG, mock.hp, absorbMode, 0.10, hpReverse, absorbAnchor, hpAreaW)
    else
        mock.absorb:Hide()
    end
    local hr, hg, hb = HealthColor(key, data)
    local hbr, hbg, hbb, hba = HealthBackgroundColor(hr, hg, hb, data)
    mock.hpBG:SetVertexColor(hbr, hbg, hbb, hba)
    mock.hp:SetVertexColor(hr, hg, hb, 1)
    if powerOn then
        mock.powerBG:Show(); mock.power:Show()
        mock.powerBG:ClearAllPoints()
        mock.powerBG:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", S(2), S(2))
        mock.powerBG:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -S(2), S(2))
        mock.powerBG:SetHeight(powerH)
        local pr, pg, pb = PowerColor(data.powerToken)
        local pbr, pbg, pbb, pba = PowerBackgroundColor(pr, pg, pb, hr, hg, hb)
        mock.powerBG:SetVertexColor(pbr, pbg, pbb, pba)
        mock.power:ClearAllPoints()
        mock.power:SetPoint("TOPLEFT", mock.powerBG, "TOPLEFT", 0, 0)
        mock.power:SetPoint("BOTTOMLEFT", mock.powerBG, "BOTTOMLEFT", 0, 0)
        mock.power:SetWidth(max(1, (sw - S(4)) * powerFrac))
        mock.power:SetVertexColor(pr, pg, pb, 1)
    else
        mock.powerBG:Hide(); mock.power:Hide()
    end

    local pr, pg, pb = PowerColor(data.powerToken)
    if classPowerOn then
        mock.classPower:Show()
        local cpW
        if bars.classPowerWidthMode == "custom" then cpW = tonumber(bars.classPowerWidth) or (w - 4) else cpW = w - 4 end
        if cpW < 30 then cpW = w - 4 elseif cpW > 800 then cpW = 800 end
        mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
        mock.classPower:ClearAllPoints()
        mock.classPower:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(2 + (tonumber(bars.classPowerOffsetX) or 0)), S(4 + (tonumber(bars.classPowerOffsetY) or 0)))
        local segCount = 5
        local gap = max(0, S(tonumber(bars.classPowerGap) or 0))
        local segW = floor((S(cpW) - (segCount - 1) * gap) / segCount)
        for i = 1, #mock.classPower.segments do
            local seg = mock.classPower.segments[i]
            if i <= segCount then
                seg:Show()
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", mock.classPower, "TOPLEFT", (i - 1) * (segW + gap), 0)
                seg:SetPoint("BOTTOMLEFT", mock.classPower, "BOTTOMLEFT", (i - 1) * (segW + gap), 0)
                seg:SetWidth(i == segCount and (S(cpW) - (i - 1) * (segW + gap)) or segW)
                local filled = i <= 3
                seg:SetColorTexture(pr, pg, pb, filled and 0.95 or 0.28)
            else
                seg:Hide()
            end
        end
    else
        mock.classPower:Hide()
        for i = 1, #mock.classPower.segments do mock.classPower.segments[i]:Hide() end
    end

    if detachedPower then
        mock.detachedPower:Show()
        local dW = tonumber(conf.detachedPowerBarWidth) or w
        if key == "player" and bars.detachedPowerBarWidthMode and bars.detachedPowerBarWidthMode ~= "manual" then
            dW = classPowerOn and (mock.classPower:GetWidth() / max(scale, 0.01)) or w
        end
        if dW < 20 then dW = 20 elseif dW > 800 then dW = 800 end
        mock.detachedPower:SetSize(S(dW), max(2, S(detachedH)))
        mock.detachedPower:ClearAllPoints()
        local dx = S(tonumber(conf.detachedPowerBarOffsetX) or 0)
        local dy = S(tonumber(conf.detachedPowerBarOffsetY) or -4)
        if key == "player" and conf.detachedPowerBarAnchorToClassPower == true and classPowerOn and mock.classPower:IsShown() then
            mock.detachedPower:SetPoint("TOP", mock.classPower, "BOTTOM", dx, dy)
        else
            mock.detachedPower:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", dx, dy)
        end
        mock.detachedPower.fill:SetVertexColor(pr, pg, pb, 1)
        mock.detachedPower.fill:SetWidth(max(1, S(dW) * powerFrac - 2))
        box.handleDetachedPower:SetSize(max(36, S(dW)), max(18, S(detachedH) + 8))
        PlaceHandle(box.handleDetachedPower, mock.detachedPower)
    else
        mock.detachedPower:Hide()
        box.handleDetachedPower:Hide()
    end

    ApplyPreviewRounded(box, key, powerOn, PreviewRoundedOutlineThickness(key, conf, scale))

    local fr, fg, fb = FontColor()
    local baseTextSize = tonumber(g.fontSize) or 14
    local nameSize = S(tonumber(conf.nameFontSize) or tonumber(g.nameFontSize) or baseTextSize); if nameSize < 7 then nameSize = 7 end
    local hpSize = S(tonumber(conf.hpFontSize) or tonumber(g.hpFontSize) or baseTextSize); if hpSize < 7 then hpSize = 7 end
    local pwrSize = S(tonumber(conf.powerFontSize) or tonumber(g.powerFontSize) or baseTextSize); if pwrSize < 7 then pwrSize = 7 end
    mock.nameText:SetFont(FONT, nameSize, "OUTLINE")
    mock.raidGroupNameText:SetFont(FONT, nameSize, "OUTLINE")
    mock.totInlineSep:SetFont(FONT, nameSize, "OUTLINE")
    mock.totInlineText:SetFont(FONT, nameSize, "OUTLINE")
    mock.hpTextLeft:SetFont(FONT, hpSize, "OUTLINE")
    mock.hpTextCenter:SetFont(FONT, hpSize, "OUTLINE")
    mock.hpText:SetFont(FONT, hpSize, "OUTLINE")
    mock.hpTextPct:SetFont(FONT, hpSize, "OUTLINE")
    mock.powerTextLeft:SetFont(FONT, pwrSize, "OUTLINE")
    mock.powerTextCenter:SetFont(FONT, pwrSize, "OUTLINE")
    mock.powerText:SetFont(FONT, pwrSize, "OUTLINE")
    mock.powerTextPct:SetFont(FONT, pwrSize, "OUTLINE")
    mock.nameText:SetTextColor(fr, fg, fb, 1)
    mock.raidGroupNameText:SetTextColor(fr, fg, fb, 1)
    mock.totInlineSep:SetTextColor(0.72, 0.76, 0.84, 1)
    mock.totInlineText:SetTextColor(fr, fg, fb, 1)
    mock.hpTextLeft:SetTextColor(fr, fg, fb, 1)
    mock.hpTextCenter:SetTextColor(fr, fg, fb, 1)
    mock.hpText:SetTextColor(fr, fg, fb, 1)
    mock.hpTextPct:SetTextColor(fr, fg, fb, 1)
    if g.colorPowerTextByType == true then
        local prt, pgt, pbt = PowerColor(data.powerToken)
        mock.powerTextLeft:SetTextColor(prt, pgt, pbt, 1)
        mock.powerTextCenter:SetTextColor(prt, pgt, pbt, 1)
        mock.powerText:SetTextColor(prt, pgt, pbt, 1)
        mock.powerTextPct:SetTextColor(prt, pgt, pbt, 1)
    else
        mock.powerTextLeft:SetTextColor(fr, fg, fb, 1)
        mock.powerTextCenter:SetTextColor(fr, fg, fb, 1)
        mock.powerText:SetTextColor(fr, fg, fb, 1)
        mock.powerTextPct:SetTextColor(fr, fg, fb, 1)
    end
    mock.nameText:SetText(ShortenPreviewName(data.name, key, conf))
    mock.raidGroupNameText:SetText(D.PreviewRaidGroupNameText(conf))
    local hpMax, pMax = 1000000, 240000
    local hpCur, pCur = floor(hpMax * data.hp + 0.5), floor(pMax * powerFrac + 0.5)
    local hpSlots = TextScopeHasSlots(key, "textLeft", "textCenter", "textRight")
    local hpLeftMode, hpCenterMode, hpRightMode
    if hpSlots then
        hpLeftMode = TextScopeSlotGet(key, "textLeft", "NONE", NormalizeHpMode)
        hpCenterMode = TextScopeSlotGet(key, "textCenter", "NONE", NormalizeHpMode)
        hpRightMode = TextScopeSlotGet(key, "textRight", "CURPERCENT", NormalizeHpMode)
    else
        hpLeftMode, hpCenterMode, hpRightMode = "NONE", "NONE", NormalizeHpMode(TextScopeGet(key, "hpTextMode", "CURPERCENT"))
    end
    if TextScopeGet(key, "hpTextReverse", false) == true then
        local rev = { CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", CURMAX = "MAXCUR", MAXCUR = "CURMAX", CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT", MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT", PERCENTCURMAX = "CURMAXPERCENT" }
        hpLeftMode = rev[hpLeftMode] or hpLeftMode
        hpCenterMode = rev[hpCenterMode] or hpCenterMode
        hpRightMode = rev[hpRightMode] or hpRightMode
    end
    local hpPctValue = floor(data.hp * 100 + 0.5)
    local hpSepRaw = TextScopeGet(key, "hpTextSeparator", "")
    mock.hpTextLeft:SetText(FormatMode(hpLeftMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextCenter:SetText(FormatMode(hpCenterMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpText:SetText(FormatMode(hpRightMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextPct:SetText("")

    local powerSlots = TextScopeHasSlots(key, "powerTextLeft", "powerTextCenter", "powerTextRight")
    local powerLeftMode, powerCenterMode, powerRightMode
    if powerSlots then
        powerLeftMode = TextScopeSlotGet(key, "powerTextLeft", "NONE", NormalizePowerMode)
        powerCenterMode = TextScopeSlotGet(key, "powerTextCenter", "NONE", NormalizePowerMode)
        powerRightMode = TextScopeSlotGet(key, "powerTextRight", "CURPERCENT", NormalizePowerMode)
    else
        powerLeftMode, powerCenterMode, powerRightMode = "NONE", "NONE", NormalizePowerMode(TextScopeGet(key, "powerTextMode", "CURPERCENT"))
    end
    local powerPctValue = floor(powerFrac * 100 + 0.5)
    local powerSepRaw = TextScopeGet(key, "powerTextSeparator", TextScopeGet(key, "hpTextSeparator", ""))
    mock.powerTextLeft:SetText(FormatMode(powerLeftMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextCenter:SetText(FormatMode(powerCenterMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerText:SetText(FormatMode(powerRightMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextPct:SetText("")
    mock.nameText:SetShown(conf.showName ~= false)
    local raidGroupAnchor = D.NormalizeRaidGroupNameAnchor(conf.raidGroupNameAnchor)
    if conf.showName == false and (raidGroupAnchor == "NAMERIGHT" or raidGroupAnchor == "NAMELEFT") then
        raidGroupAnchor = "CENTER"
    end
    local showRaidGroupName = conf.showRaidGroupInName == true and D.PreviewRaidGroupNameAllowed(key)
    mock.raidGroupNameText:SetShown(showRaidGroupName)
    mock.totInlineSep:Hide()
    mock.totInlineText:Hide()
    local hpTextOn = conf.showHP ~= false
    local powerTextOn = (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true
    mock.hpTextLeft:SetShown(hpTextOn and hpLeftMode ~= "NONE")
    mock.hpTextCenter:SetShown(hpTextOn and hpCenterMode ~= "NONE")
    mock.hpText:SetShown(hpTextOn and hpRightMode ~= "NONE")
    mock.hpTextPct:SetShown(false)
    mock.powerTextLeft:SetShown(powerTextOn and powerLeftMode ~= "NONE")
    mock.powerTextCenter:SetShown(powerTextOn and powerCenterMode ~= "NONE")
    mock.powerText:SetShown(powerTextOn and powerRightMode ~= "NONE")
    mock.powerTextPct:SetShown(false)

    mock.nameText:ClearAllPoints()
    local npt, nrel, nx, njust = ResolveNameAnchor(conf.nameTextAnchor or "LEFT", S(tonumber(conf.nameOffsetX) or 4))
    mock.nameText:SetPoint(npt, mock.textFrame, nrel, nx, S(tonumber(conf.nameOffsetY) or -4))
    mock.nameText:SetJustifyH(njust)
    mock.raidGroupNameText:ClearAllPoints()
    local raidGroupX = S(tonumber(conf.raidGroupNameOffsetX) or 3)
    local raidGroupY = S(tonumber(conf.raidGroupNameOffsetY) or 0)
    if raidGroupAnchor == "NAMERIGHT" then
        mock.raidGroupNameText:SetPoint("LEFT", mock.nameText, "RIGHT", raidGroupX, raidGroupY)
    elseif raidGroupAnchor == "NAMELEFT" then
        mock.raidGroupNameText:SetPoint("RIGHT", mock.nameText, "LEFT", raidGroupX, raidGroupY)
    else
        mock.raidGroupNameText:SetPoint(raidGroupAnchor, mock.textFrame, raidGroupAnchor, raidGroupX, raidGroupY)
    end
    mock.raidGroupNameText:SetJustifyH("LEFT")
    do
        local totConf = (_G.MSUF_DB and _G.MSUF_DB.targettarget) or {}
        local showInline = key == "target" and conf.showName ~= false and totConf.showToTInTargetName == true
        if showInline then
            local sep = ToTInlineSeparator(totConf.totInlineSeparator, totConf.totInlineCustomSeparator)
            local totData = UNIT_DATA.targettarget or { name = "Target" }
            local tr, tg, tb = PreviewNameColor("target", data, fr, fg, fb)
            local ir, ig, ib = PreviewToTInlineColor(totConf.totInlineColorMode, totData, tr, tg, tb, fr, fg, fb)
            mock.totInlineSep:SetText(sep ~= "" and sep or " ")
            mock.totInlineText:SetText(ShortenPreviewName(totData.name, "targettarget", conf))
            mock.totInlineText:SetTextColor(ir, ig, ib, 1)
            local inlineAnchor = (showRaidGroupName and raidGroupAnchor == "NAMERIGHT") and mock.raidGroupNameText or mock.nameText
            mock.totInlineSep:ClearAllPoints()
            mock.totInlineSep:SetPoint("LEFT", inlineAnchor, "RIGHT", S(4), 0)
            mock.totInlineText:ClearAllPoints()
            mock.totInlineText:SetPoint("LEFT", mock.totInlineSep, "RIGHT", S(4), 0)
            mock.totInlineSep:Show()
            mock.totInlineText:Show()
        end
    end
    local function PlacePreviewSlot(fs, parent, point, relPoint, x, y, justify)
        if not fs then return end
        fs:ClearAllPoints()
        fs:SetPoint(point, parent, relPoint, x, y)
        fs:SetJustifyH(justify)
    end

    local hpOX = S(tonumber(conf.hpOffsetX) or -4)
    local hpOY = S(tonumber(conf.hpOffsetY) or -4)
    local hpLeftOX = S(tonumber(conf.hpTextLeftOffsetX) or 0)
    local hpLeftOY = S(tonumber(conf.hpTextLeftOffsetY) or 0)
    local hpCenterOX = S(tonumber(conf.hpTextCenterOffsetX) or 0)
    local hpCenterOY = S(tonumber(conf.hpTextCenterOffsetY) or 0)
    local hpRightOX = S(tonumber(conf.hpTextRightOffsetX) or 0)
    local hpRightOY = S(tonumber(conf.hpTextRightOffsetY) or 0)
    PlacePreviewSlot(mock.hpTextLeft, mock.textFrame, "TOPLEFT", "TOPLEFT", S(4) + hpOX + hpLeftOX, hpOY + hpLeftOY, "LEFT")
    PlacePreviewSlot(mock.hpTextCenter, mock.textFrame, "TOP", "TOP", hpOX + hpCenterOX, hpOY + hpCenterOY, "CENTER")
    PlacePreviewSlot(mock.hpText, mock.textFrame, "TOPRIGHT", "TOPRIGHT", -S(4) + hpOX + hpRightOX, hpOY + hpRightOY, "RIGHT")
    PlacePreviewSlot(mock.hpTextPct, mock.textFrame, "TOPRIGHT", "TOPRIGHT", -S(4) + hpOX + hpRightOX, hpOY + hpRightOY, "RIGHT")

    local pOX = S(tonumber(conf.powerOffsetX) or -4)
    local pOY = S(tonumber(conf.powerOffsetY) or 4)
    local pLeftOX = S(tonumber(conf.powerTextLeftOffsetX) or 0)
    local pLeftOY = S(tonumber(conf.powerTextLeftOffsetY) or 0)
    local pCenterOX = S(tonumber(conf.powerTextCenterOffsetX) or 0)
    local pCenterOY = S(tonumber(conf.powerTextCenterOffsetY) or 0)
    local pRightOX = S(tonumber(conf.powerTextRightOffsetX) or 0)
    local pRightOY = S(tonumber(conf.powerTextRightOffsetY) or 0)
    if detachedPower and conf.detachedPowerBarTextOnBar == true and mock.detachedPower:IsShown() then
        PlacePreviewSlot(mock.powerTextLeft, mock.detachedPower, "LEFT", "LEFT", S(2) + pOX + pLeftOX, pOY + pLeftOY, "LEFT")
        PlacePreviewSlot(mock.powerTextCenter, mock.detachedPower, "CENTER", "CENTER", pOX + pCenterOX, pOY + pCenterOY, "CENTER")
        PlacePreviewSlot(mock.powerText, mock.detachedPower, "RIGHT", "RIGHT", -S(2) + pOX + pRightOX, pOY + pRightOY, "RIGHT")
        PlacePreviewSlot(mock.powerTextPct, mock.detachedPower, "RIGHT", "RIGHT", -S(2) + pOX + pRightOX, pOY + pRightOY, "RIGHT")
    else
        PlacePreviewSlot(mock.powerTextLeft, mock.textFrame, "BOTTOMLEFT", "BOTTOMLEFT", S(4) + pOX + pLeftOX, pOY + pLeftOY, "LEFT")
        PlacePreviewSlot(mock.powerTextCenter, mock.textFrame, "BOTTOM", "BOTTOM", pOX + pCenterOX, pOY + pCenterOY, "CENTER")
        PlacePreviewSlot(mock.powerText, mock.textFrame, "BOTTOMRIGHT", "BOTTOMRIGHT", -S(4) + pOX + pRightOX, pOY + pRightOY, "RIGHT")
        PlacePreviewSlot(mock.powerTextPct, mock.textFrame, "BOTTOMRIGHT", "BOTTOMRIGHT", -S(4) + pOX + pRightOX, pOY + pRightOY, "RIGHT")
    end

    if hasPortrait then
        mock.portrait:Show()
        mock.portrait:SetSize(sp, sp)
        mock.portrait:ClearAllPoints()
        local ox = S(tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0)
        local oy = S(tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0)
        if mode == "RIGHT" then mock.portrait:SetPoint("LEFT", mock, "RIGHT", S(4) + ox, oy)
        else mock.portrait:SetPoint("RIGHT", mock, "LEFT", -S(4) + ox, oy) end
        local cr, cg, cb = ClassColor(data.class)
        local renderMode = PortraitStyleGet(key, "portraitRender", "2D")
        if renderMode == "CLASS" then
            local visual = ClassPortraitVisual(data.class, PortraitStyleGet(key, "portraitClassStyle", "BLIZZARD"))
            mock.portrait.tex:SetTexture(visual and visual.texture or "Interface\\ICONS\\INV_Misc_QuestionMark")
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            if mock.portrait.tex.SetTexCoord then
                mock.portrait.tex:SetTexCoord(
                    (visual and visual.left) or 0,
                    (visual and visual.right) or 1,
                    (visual and visual.top) or 0,
                    (visual and visual.bottom) or 1
                )
            end
            mock.portrait.initial:Hide()
        else
            mock.portrait.tex:SetTexture(UnitPreviewPortraitTexture(key, data))
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            if mock.portrait.tex.SetTexCoord then
                mock.portrait.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            mock.portrait.initial:Hide()
        end
        if PortraitStyleGet(key, "portraitBgEnabled", false) == true then
            mock.portrait:SetBackdropColor(
                g.portraitBgColorR or 0.05,
                g.portraitBgColorG or 0.05,
                g.portraitBgColorB or 0.05,
                g.portraitBgColorA or 0.85
            )
        else
            mock.portrait:SetBackdropColor(0.03, 0.035, 0.05, 1)
        end
        local bStyle = PortraitStyleGet(key, "portraitBorderStyle", "NONE")
        if bStyle == "NONE" then
            mock.portrait:SetBackdropBorderColor(0, 0, 0, 0)
        elseif bStyle == "CUSTOM" or bStyle == "SOLID" then
            mock.portrait:SetBackdropBorderColor(
                g.portraitBorderColorR or 1,
                g.portraitBorderColorG or 1,
                g.portraitBorderColorB or 1,
                g.portraitBorderColorA or 1
            )
        elseif bStyle == "CLASS_COLOR" then
            mock.portrait:SetBackdropBorderColor(cr, cg, cb, 1)
        elseif bStyle == "REACTION" then
            local hostile = (key == "target" or key == "boss" or key == "focus" or key == "focustarget")
            mock.portrait:SetBackdropBorderColor(hostile and 1 or 0.1, hostile and 0.2 or 0.85, 0.1, 1)
        else
            mock.portrait:SetBackdropBorderColor(1, 1, 1, 1)
        end
        box.handlePortrait:SetSize(max(18, sp), max(18, sp))
        PlaceHandle(box.handlePortrait, mock.portrait)
    else
        mock.portrait:Hide()
        box.handlePortrait:Hide()
    end

    if castPreviewVisible then
        mock.cast:Show()
        if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
            local br, bg, bb, ba = _G.MSUF_GetCastbarBackgroundColor()
            mock.cast:SetBackdropColor(br or 0.10, bg or 0.10, bb or 0.10, ba or 0.85)
        end
        local scw, sch = max(20, S(castW)), max(6, S(castBarH))
        mock.cast:SetSize(scw, sch)
        if mock.cast.sizeTag then
            mock.cast.sizeTag:SetText(format("%d x %d", floor(castW + 0.5), floor(castBarH + 0.5)))
            mock.cast.sizeTag:Show()
        end
        mock.cast:ClearAllPoints()
        if castDetached then
            mock.cast:SetPoint("CENTER", canvas, "CENTER", S(castOffsetX), S(castOffsetY))
        elseif key == "player" then
            mock.cast:SetPoint("BOTTOM", mock, "TOP", S(castOffsetX), S(castOffsetY))
        else
            mock.cast:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(castOffsetX), S(castOffsetY + ((key == "boss") and 2 or 0)))
        end
        local cr, cg, cb = 0.0, 0.9, 0.8
        if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
            cr, cg, cb = _G.MSUF_GetInterruptibleCastColor()
        end
        mock.cast.fill:SetVertexColor(cr or 0.0, cg or 0.9, cb or 0.8, 1)
        local showIcon = CastbarShowIcon(key, g)
        mock.cast.icon:SetShown(showIcon)
        local iconX = ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0)
        local iconY = ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0)
        local iconSize = ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH)
        if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end
        local sIcon = max(6, S(iconSize))
        local iconDetached = showIcon and (iconX ~= 0 or iconY ~= 0)
        if showIcon then
            mock.cast.icon:SetSize(sIcon, sIcon)
            mock.cast.icon:ClearAllPoints()
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX), S(iconY))
        end
        mock.cast.fill:ClearAllPoints()
        if showIcon and not iconDetached then
            mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", sIcon + S(1), -S(1))
        else
            mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", S(1), -S(1))
        end
        local timeReserve = max(S(2), min(S(60), floor(scw * 0.34 + 0.5)))
        mock.cast.fill:SetPoint("BOTTOMRIGHT", mock.cast, "BOTTOMRIGHT", -timeReserve, S(1))
        local showText = CastbarShowText(key, g)
        mock.cast.text:SetShown(showText)
        if showText then
            local tr, tg, tb = fr, fg, fb
            if type(_G.MSUF_GetCastbarTextColor) == "function" then
                tr, tg, tb = _G.MSUF_GetCastbarTextColor()
            end
            mock.cast.text:SetTextColor(tr, tg, tb, 1)
            local textSize = ReadCastbarNum(g, key, "SpellNameFontSize", "bossCastSpellNameFontSize", g.castbarSpellNameFontSize or g.fontSize or 14)
            if not textSize or textSize <= 0 then textSize = g.fontSize or 14 end
            mock.cast.text:SetFont(FONT, max(7, S(textSize)), "OUTLINE")
            mock.cast.text:ClearAllPoints()
            local textX = ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0)
            local textY = ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0)
            mock.cast.text:SetPoint("LEFT", mock.cast.fill, "LEFT", S(2 + textX), S(textY))
            mock.cast.text:SetPoint("RIGHT", mock.cast.time, "LEFT", -S(6), 0)
            mock.cast.text:SetText(TR(key == "boss" and "Celestial Ruin" or "Arcane Surge"))
        end
        local showTime = key == "boss" and g.showBossCastTime ~= false
            or (key == "target" and g.showTargetCastTime ~= false)
            or (key == "focus" and g.showFocusCastTime ~= false)
            or (key == "player" and g.showPlayerCastTime ~= false)
        mock.cast.time:SetShown(showTime)
        mock.cast.time:SetText(FormatCastbarPreviewTime(g, key, 1.4, 2.0))
        if showTime then
            local timeX = ReadCastbarNum(g, key, "TimeOffsetX", "bossCastTimeOffsetX", g.castbarPlayerTimeOffsetX or -2)
            local timeY = ReadCastbarNum(g, key, "TimeOffsetY", "bossCastTimeOffsetY", g.castbarPlayerTimeOffsetY or 0)
            local timeSize = ReadCastbarNum(g, key, "TimeFontSize", "bossCastTimeFontSize", g.castbarTimeFontSize or g.fontSize or 14)
            if not timeSize or timeSize <= 0 then timeSize = g.fontSize or 14 end
            mock.cast.time:SetFont(FONT, max(7, S(timeSize)), "OUTLINE")
            mock.cast.time:ClearAllPoints()
            mock.cast.time:SetPoint("RIGHT", mock.cast.fill, "RIGHT", S(timeX), S(timeY))
        end
        box.handleCastbar:SetSize(max(36, scw), max(18, sch + 8))
        PlaceHandle(box.handleCastbar, mock.cast)
    else
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        mock.cast:Hide()
        box.handleCastbar:Hide()
    end

    local statusLayerAvailable = false
    for i = 1, #D.STATUS_PREVIEW do
        local spec = D.STATUS_PREVIEW[i]
        local icon = mock.icons[spec.id]
        local handle = box.statusHandles[spec.id]
        local showVal = conf[spec.show]
        if showVal == nil then showVal = g[spec.show] end
        local show = (showVal == nil) and (spec.defaultShow ~= false) or (showVal ~= false)
        if spec.allowed and not spec.allowed(key) then show = false end
        if spec.id == "elite" and not data.elite then show = false end
        if Preview.GetStatusPreviewMode() ~= "all" then
            local selected = NormalizeStatusPreviewId(Preview.selectedStatusId)
            if selected == "" then selected = "raidmarker" end
            show = show and (spec.id == selected)
        end
        icon:SetShown(show)
        if show then
            statusLayerAvailable = true
            local rawSize = tonumber(conf[spec.size]) or tonumber(g[spec.size]) or spec.defaultSize
            local sz = S(rawSize)
            if spec.id == "level" then
                if sz < 7 then sz = 7 end
            elseif sz < 10 then
                sz = 10
            end
            if icon.SetFrameLevel then
                local rawLayer = spec.layer and (tonumber(conf[spec.layer]) or tonumber(g[spec.layer])) or spec.defaultLayer
                icon:SetFrameLevel(textBase + ClampPreviewLayer(rawLayer, spec.defaultLayer or 7))
            end
            SetPreviewIconTexture(icon, spec, conf, g, key, data)
            if spec.id == "level" then
                local anchor = ResolveStatusPreviewAnchor(spec, conf, g)
                local x = S(tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0)
                local y = S(tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
                if icon.txt then
                    icon.txt:SetFont(FONT, max(7, sz), "OUTLINE")
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("LEFT", icon, "LEFT", 0, 0)
                    icon.txt:SetJustifyH("LEFT")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                PositionLevelPreview(icon, anchor, x, y, mock, S(6))
            elseif spec.id == "statusText" then
                local anchor = ResolveStatusPreviewAnchor(spec, conf, g)
                local x = S(tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0)
                local y = S(tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
                if icon.txt then
                    icon.txt:SetFont(FONT, max(7, sz), "OUTLINE")
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                PositionSameAnchorPreview(icon, anchor, x, y, mock.hpBG or mock)
            else
                icon:SetSize(sz, sz)
                if icon.txt then
                    icon.txt:SetFont(FONT, max(7, floor(sz * 0.52 + 0.5)), "OUTLINE")
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local anchor = ResolveStatusPreviewAnchor(spec, conf, g)
                local x = S(tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0)
                local y = S(tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
                if spec.id == "raidmarker" then
                    PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, true)
                elseif spec.id == "leader" or spec.id == "elite" then
                    PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, false)
                elseif spec.id == "statusCombat" or spec.id == "statusResting" or spec.id == "statusIncomingRes" then
                    PositionStatusCornerPreview(icon, anchor, x, y, mock, S(2))
                else
                    PositionFromAnchor(icon, anchor, x, y, mock, sz)
                end
            end
            handle:SetSize(max(18, icon:GetWidth() + 8), max(18, icon:GetHeight() + 8))
            PlaceHandle(handle, icon)
        else
            handle:Hide()
        end
    end
    if showRaidGroupName then
        statusLayerAvailable = true
    end

    box.layerAvailable = {
        body = true,
        nameText = conf.showName ~= false,
        hpText = conf.showHP ~= false,
        powerText = (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true,
        portrait = hasPortrait,
        power = D.ReadPowerBarEnabled(conf, key),
        classPower = classPowerOn,
        castbar = castEnabled,
        status = statusLayerAvailable,
        bounds = true,
    }
    for i = 1, #(box.layerButtons or {}) do
        if box.layerButtons[i].refresh then box.layerButtons[i]:refresh() end
    end

    local nameHandleW = mock.nameText:GetStringWidth() + 10
    if mock.totInlineSep and mock.totInlineSep:IsShown() then
        nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + S(8)
    end
    box.handleName:SetSize(max(46, nameHandleW), max(18, mock.nameText:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas, { mock.nameText, mock.totInlineSep, mock.totInlineText }, 3) then
        PlaceHandle(box.handleName, mock.nameText)
    end
    local function PlaceTextSlotHandle(handle, region)
        if not handle then return end
        if not (region and region.IsShown and region:IsShown()) then
            handle:Hide()
            return
        end
        local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
        local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
        handle:SetSize(max(26, w + 10), max(18, h + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(handle, canvas, { region }, 3) then
            PlaceHandle(handle, region)
        end
    end
    PlaceTextSlotHandle(box.handleRaidGroupName, mock.raidGroupNameText)
    if UnitPreviewTextMovesTogether(key, "hp") then
        SetShownSafe(box.handleHPLeft, false)
        SetShownSafe(box.handleHPCenter, false)
        SetShownSafe(box.handleHPRight, false)
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleHP, canvas, { mock.hpTextLeft, mock.hpTextCenter, mock.hpText }, 3) then
            if not ((mock.hpTextLeft and mock.hpTextLeft:IsShown()) or (mock.hpTextCenter and mock.hpTextCenter:IsShown()) or (mock.hpText and mock.hpText:IsShown())) then
                box.handleHP:Hide()
            else
                box.handleHP:SetSize(max(46, mock.hpText:GetStringWidth() + 10), max(18, mock.hpText:GetStringHeight() + 6))
                PlaceHandle(box.handleHP, mock.hpText)
            end
        end
    else
        if box.handleHP then box.handleHP:Hide() end
        PlaceTextSlotHandle(box.handleHPLeft, mock.hpTextLeft)
        PlaceTextSlotHandle(box.handleHPCenter, mock.hpTextCenter)
        PlaceTextSlotHandle(box.handleHPRight, mock.hpText)
    end
    if UnitPreviewTextMovesTogether(key, "power") then
        SetShownSafe(box.handlePowerLeft, false)
        SetShownSafe(box.handlePowerCenter, false)
        SetShownSafe(box.handlePowerRight, false)
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handlePower, canvas, { mock.powerTextLeft, mock.powerTextCenter, mock.powerText }, 3) then
            if not ((mock.powerTextLeft and mock.powerTextLeft:IsShown()) or (mock.powerTextCenter and mock.powerTextCenter:IsShown()) or (mock.powerText and mock.powerText:IsShown())) then
                box.handlePower:Hide()
            else
                box.handlePower:SetSize(max(46, mock.powerText:GetStringWidth() + 10), max(18, mock.powerText:GetStringHeight() + 6))
                PlaceHandle(box.handlePower, mock.powerText)
            end
        end
    else
        if box.handlePower then box.handlePower:Hide() end
        PlaceTextSlotHandle(box.handlePowerLeft, mock.powerTextLeft)
        PlaceTextSlotHandle(box.handlePowerCenter, mock.powerTextCenter)
        PlaceTextSlotHandle(box.handlePowerRight, mock.powerText)
    end
    ApplyPreviewLayerVisibility(box)
    ApplyPreviewTransparency(box, conf)
    RefreshHandleSelectionVisuals(box)
end

function Preview.RequestRefresh(reason)
    local box = Preview.active
    if not box or not box:IsShown() then return end
    if PreviewInCombat() then
        box._refreshReason = nil
        box._refreshQueued = nil
        return
    end
    if InstallPreviewHooks then InstallPreviewHooks() end
    if reason == "OPTIONS_APPLY_DB_IMMEDIATE" then
        box._refreshQueued = nil
        Preview.Refresh(box, reason)
        return
    end
    box._refreshReason = reason or box._refreshReason
    if box._refreshQueued then return end
    box._refreshQueued = true
    local function run()
        if not box then return end
        local refreshReason = box._refreshReason
        box._refreshReason = nil
        box._refreshQueued = nil
        Preview.Refresh(box, refreshReason)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

_G.MSUF_UFPreview_RequestRefresh = function(reason)
    if PreviewInCombat() then return end
    Preview.RequestRefresh(reason)
end

_G.MSUF_UFPreview_SetStatusPreviewMode = function(mode)
    Preview.SetStatusPreviewMode(mode)
end

_G.MSUF_UFPreview_GetStatusPreviewMode = function()
    return Preview.GetStatusPreviewMode()
end

_G.MSUF_UFPreview_SelectStatusIcon = function(id)
    Preview.SelectStatusIcon(id)
end

local hookedNames = {}
InstallPreviewHooks = function()
    local names = {
        "MSUF_ForceTextLayoutForUnitKey",
        "MSUF_UpdateAllFonts",
        "MSUF_UpdateAllFonts_Immediate",
        "MSUF_UpdateAllBarTextures",
        "MSUF_UpdateAllBarTextures_Immediate",
        "MSUF_UpdateCastbarVisuals",
        "MSUF_ApplyCastbarUnitAndSync",
        "MSUF_SyncCastbarPositionPopup",
        "MSUF_SyncUnitPositionPopup",
        "MSUF_ApplyUnitFrameKey_Immediate",
        "MSUF_UFCore_RefreshSettingsCache",
        "MSUF_RefreshAllIdentityColors",
        "MSUF_RefreshAllPowerTextColors",
        "MSUF_RefreshAllFrames",
        "MSUF_RefreshAllUnitAlphas",
        "MSUF_RequestAlphaRefresh",
        "MSUF_ClassPower_Refresh",
        "MSUF_ApplyPowerBarEmbedLayout",
        "MSUF_ApplyPowerBarEmbedLayout_All",
        "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
        "MSUF_Portraits_SyncUnit",
        "MSUF_PortraitDecoration_SyncUnit",
        "MSUF_RefreshRaidMarkerFrames",
        "MSUF_RefreshLeaderIconFrames",
        "MSUF_RefreshLevelIndicatorFrames",
        "MSUF_RefreshEliteIconFrames",
        "MSUF_RequestStatusTextRefresh",
        "MSUF_RequestStatusCombatIndicatorRefresh",
        "MSUF_RequestStatusRestingIndicatorRefresh",
        "MSUF_RequestStatusIncomingResIndicatorRefresh",
    }
    for i = 1, #names do
        local name = names[i]
        local fn = _G[name]
        if type(fn) == "function" and type(hooksecurefunc) == "function" then
            if not hookedNames[name] then
                hookedNames[name] = true
                hooksecurefunc(name, function()
                    if not PreviewInCombat() then Preview.RequestRefresh(name) end
                end)
            end
        end
    end
end

function ns.MSUF_Menu2_CreateUnitPreviewBox(parent, panel, width, height)
    local box = BuildPreview(parent, panel, width, height)
    return box
end

_G.MSUF_Menu2_CreateUnitPreviewBox = ns.MSUF_Menu2_CreateUnitPreviewBox
