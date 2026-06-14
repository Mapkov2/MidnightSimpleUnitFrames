-- Menu2 unit preview model: creates fake preview data and model state for unit pages.
-- Preview-only state must not leak into live unit frames or profile runtime paths.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
MSUF.L = MSUF.L or (_G.MSUF_L) or {}
local L = MSUF.L
if not getmetatable(L) then setmetatable(L, { __index = function(_, k) return k end }) end
local isEn = (MSUF and MSUF.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local PreviewAbbreviateNumbers = _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers or _G.ShortenNumber
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
ExportPublic("MSUF_UFPreview", Preview)

-- Unit preview model.
-- Provides deterministic mock units, names, colors, and derived text for Menu2 previews. This
-- file is display-only; live unit state and event dispatch remain in UnitFrames runtime.
local Model = Preview.Model or {}
Preview.Model = Model
local PreviewHelpers = M.PreviewHelpers or {}
local UnitPage = M.UnitPage or {}
local UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet" }
local UNIT_SET = M.KeySetFromWords "player target targettarget focustarget focus boss pet"
local CONTROL_CHILD_KEYS, CONTROL_NAME_SUFFIXES = M.WordList "minusButton plusButton Button _msufPeelButton", M.WordList "Button Text Low High"
local UNIT_LABELS = { player = "Player", target = "Target", targettarget = "Target of Target", focustarget = "Focus Target", focus = "Focus", boss = "Boss Frames", pet = "Pet" }
local UNIT_DATA = {
    -- Preview data is intentionally stylized and stable. Do not replace this with live Unit*
    -- API calls; preview should render identically while the player is offline, in combat, or
    -- inspecting another profile.
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
local function KeyLabelValues(values)
    local out = {}
    for i = 1, #(values or {}) do
        local item = values[i]
        local key = item and (item.key or item.value or item[1])
        out[#out + 1] = { key = key, label = item and (item.label or item.text or item[2] or key) or "" }
    end
    return out
end
local TEXT_ANCHORS = KeyLabelValues(UnitPage.TEXT_ANCHORS)
local HP_MODES = KeyLabelValues(UnitPage.HP_MODES)
local POWER_MODES = KeyLabelValues(UnitPage.POWER_MODES)
local SEP_ITEMS = KeyLabelValues(UnitPage.SEPARATORS)
local PORTRAIT_MODE_ITEMS = { { key = "OFF", label = "Off" }, { key = "LEFT", label = "Left" }, { key = "RIGHT", label = "Right" } }
local PORTRAIT_RENDER_ITEMS = KeyLabelValues(UnitPage.PORTRAIT_RENDER)
local function PortraitClassItems()
    local PM = MSUF and MSUF.PortraitMedia
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
local PORTRAIT_SHAPE_ITEMS = KeyLabelValues(UnitPage.PORTRAIT_SHAPES)
local PORTRAIT_BORDER_ITEMS = KeyLabelValues(UnitPage.PORTRAIT_BORDERS)
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
    elseif MSUF and type(MSUF.MSUF_EnsureDB or MSUF.EnsureDB) == "function" then
        (MSUF.MSUF_EnsureDB or MSUF.EnsureDB)()
    end
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
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
local NormalizeHpMode = M.NormalizeHpMode
local NormalizePowerMode = M.NormalizePowerMode
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
    ["<<<"] = true, [">>>"] = true, ["||"] = true, ["---"] = true,
    [">"] = true, ["<"] = true, ["~"] = true, [":"] = true,
}
local TOTINLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local TOTINLINE_CUSTOM_SEPARATOR_MAX = 5
local TruncateUtf8Chars = M.TruncateUtf8Chars
local function CleanToTInlineCustomSeparator(v) return M.CleanToTInlineCustomSeparator(v, TOTINLINE_CUSTOM_SEPARATOR_MAX) end
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
    if u.fontOverride == true and u.shortenNames ~= nil then shorten = u.shortenNames and true or false end
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
    if type(_G.MSUF_UFCore_RequestLayoutForUnit) == "function" then _G.MSUF_UFCore_RequestLayoutForUnit(key, reason or "UNIT_TEXT_OPTIONS", key == "target" or key == "targettarget" or key == "focustarget" or key == "focus") end
    if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
end
local function ApplyPanelUnit(panel, key, reason)
    key = CanonKey(key or CurrentPanelKey(panel))
    if panel and panel._msufAPI and type(panel._msufAPI.ApplySettingsForKey) == "function" then panel._msufAPI.ApplySettingsForKey(key) end
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
    for _, childKey in ipairs(CONTROL_CHILD_KEYS) do
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
            for _, suffix in ipairs(CONTROL_NAME_SUFFIXES) do
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
    if MSUF.UI and MSUF.UI.StyleCheckmark then MSUF.UI.StyleCheckmark(cb) end
    if _G.MSUF_ClampCheckboxText then _G.MSUF_ClampCheckboxText(cb, 180) end
    return cb
end
local NormalizePortraitClassStyle = M.NormalizePortraitClassStyle
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
    ApplyPanelUnit(panel, key, reason or "UNIT_PORTRAIT_OPTIONS")
end
local function NormalizeStatusPreviewId(id)
    id = tostring(id or "")
    if id == "eliteicon" then return "elite" end
    return id
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
local Clamp01 = M.Clamp01
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
    local api = MSUF and MSUF._colorsAPI
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
        if data.isPet and cache and cache.petFrameColorEnabled then return cache.petFrameColorR or 0, cache.petFrameColorG or 0.8, cache.petFrameColorB or 0 end
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
    if cache and cache.powerBarBgMatchHPColor then r, g, b = DarkMatchHPColor(hr, hg, hb, cache) end
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
    local PM = MSUF and MSUF.PortraitMedia
    if PM and PM.ResolveClassPortrait then return PM.ResolveClassPortrait(class, NormalizePortraitClassStyle(style)) end
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
    local fn = (MSUF and MSUF.MSUF_GetConfiguredFontColor) or _G.MSUF_GetConfiguredFontColor
    if type(fn) == "function" then
        local r, g, b = fn()
        if r then return r, g, b end
    end
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    return g.fontColorR or 1, g.fontColorG or 1, g.fontColorB or 1
end
local function NormalizeToTInlineColorMode(value)
    if value == "TOT_NAME" or value == "TARGET_NAME" or value == "NPC" or value == "DEFAULT" then return value end
    return "AUTO"
end
local function PreviewNameColorFlags(key)
    local db = _G.MSUF_DB or {}
    local gen = db.general or {}
    local wantClass = gen.nameClassColor
    local wantNpc = gen.npcNameRed
    local wantNpcClass = gen.nameNpcClassColor
    local conf = db[key]
    if conf and conf.fontOverride then
        if conf.nameClassColor ~= nil then wantClass = conf.nameClassColor end
        if conf.npcNameRed ~= nil then wantNpc = conf.npcNameRed end
        if conf.nameNpcClassColor ~= nil then wantNpcClass = conf.nameNpcClassColor end
    end
    return wantClass == true, wantNpc == true, wantNpcClass == true
end
local function PreviewNameColor(key, data, fallbackR, fallbackG, fallbackB)
    data = data or UNIT_DATA[CanonKey(key)] or UNIT_DATA.player
    local wantClass, wantNpc, wantNpcClass = PreviewNameColorFlags(key)
    if data.isPlayer then
        if wantClass then return ClassColor(data.class) end
    else
        if wantNpcClass and data.class then return ClassColor(data.class) end
        if wantNpc or wantNpcClass then return NPCColor(PreviewNPCKind(key, data, SettingsCache(), true)) end
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
        if wantNpc and totData and not totData.isPlayer then return NPCColor(PreviewNPCKind("targettarget", totData, SettingsCache(), true)) end
        return fallbackR, fallbackG, fallbackB
    end
    if totData and totData.isPlayer then
        local wantClass = PreviewNameColorFlags("target")
        if wantClass then return ClassColor(totData.class) end
        return 1, 1, 1
    end
    local _, wantNpc, wantNpcClass = PreviewNameColorFlags("target")
    if wantNpcClass and totData and totData.class then return ClassColor(totData.class) end
    if (wantNpc or wantNpcClass) and totData then return NPCColor(PreviewNPCKind("target", totData, SettingsCache(), true)) end
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
local function PreviewHealPredictionEnabled(conf, g)
    if g == nil then g, conf = conf, nil end
    if UnitPreviewBarOverrideEnabled(conf) and conf.healPredEnabled ~= nil then return conf.healPredEnabled == true end
    if g then
        if g.showSelfHealPrediction ~= nil then return g.showSelfHealPrediction == true end
        if g.enableHealPrediction ~= nil then return g.enableHealPrediction ~= false end
    end
    return false
end
local function PreviewResolveHealPredAnchorMode(conf, g)
    if UnitPreviewBarOverrideEnabled(conf) and conf.healPredAnchorMode ~= nil then return NormalizePreviewAnchorMode(conf.healPredAnchorMode, 3) end
    return NormalizePreviewAnchorMode(g and g.healPredAnchorMode, 3)
end
local function PreviewResolveAbsorbAnchorMode(conf, g)
    if UnitPreviewBarOverrideEnabled(conf) and conf.absorbAnchorMode ~= nil then return NormalizePreviewAnchorMode(conf.absorbAnchorMode, 2) end
    return NormalizePreviewAnchorMode(g and g.absorbAnchorMode, 2)
end
local function PreviewAbsorbBarEnabled(conf, g, key)
    if _G.MSUF_ShouldShowAbsorbTextureTest and _G.MSUF_ShouldShowAbsorbTextureTest(nil, key) then return true end
    local mode
    if UnitPreviewBarOverrideEnabled(conf) and conf.absorbTextMode ~= nil then mode = tonumber(conf.absorbTextMode) end
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
    if PreviewAbbreviateNumbers then return PreviewAbbreviateNumbers(v) end
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
    return PreviewHelpers.PlaceHandleAroundRegions(handle, parent, regions, pad)
end
M.AssignNamedValues(Model, [[
    UNIT_KEYS UNIT_SET UNIT_LABELS UNIT_DATA PreviewRaidGroupNameAllowed PreviewRaidGroupNameText NormalizePreviewRaidGroupNameAnchor
    TEXT_ANCHORS HP_MODES POWER_MODES SEP_ITEMS PORTRAIT_MODE_ITEMS PORTRAIT_RENDER_ITEMS PortraitClassItems
    PORTRAIT_SHAPE_ITEMS PORTRAIT_BORDER_ITEMS PORTRAIT_STYLE_DEFAULTS CanonKey EnsureDB CurrentPanelKey UnitDB
    SeedTextFromGeneral NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet
    TOTINLINE_SEP_VALID TOTINLINE_CUSTOM_SEPARATOR TOTINLINE_CUSTOM_SEPARATOR_MAX TruncateUtf8Chars CleanToTInlineCustomSeparator
    ToTInlineSeparator ShortenPreviewName TextScopeSet ForceTextUnit ApplyPanelUnit RefreshAllControls Label PlaceTopLeft
    SetOptionWidth AddOptionDivider SetWidgetEnabled AddPlainCheck NormalizePortraitClassStyle EnsureUnitPortraitStyle
    PortraitStyleGet PortraitStyleSet ApplyPortrait NormalizeStatusPreviewId ClassColor Clamp01 SettingsCache PreviewNPCKind
    NPCColor GradientPreviewColor HealthColor DarkMatchHPColor HealthBackgroundColor PowerBackgroundColor PowerColor
    ClassPortraitVisual UnitPreviewPortraitTexture FontColor NormalizeToTInlineColorMode PreviewNameColorFlags PreviewNameColor
    PreviewToTInlineColor SetTex NormalizePreviewAnchorMode UnitPreviewBarOverrideEnabled PreviewHealPredictionEnabled
    PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewAbsorbBarEnabled PreviewOverlayWidth LayoutUnitPreviewOverlay
    MakeFS ReadPowerBarEnabled CanDetachPowerBarKey ReadPowerBarHeight ResolveNameAnchor NumText JoinSep FormatMode UnitPreviewText
]],
    UNIT_KEYS, UNIT_SET, UNIT_LABELS, UNIT_DATA, PreviewRaidGroupNameAllowed, PreviewRaidGroupNameText, NormalizePreviewRaidGroupNameAnchor,
    TEXT_ANCHORS, HP_MODES, POWER_MODES, SEP_ITEMS, PORTRAIT_MODE_ITEMS, PORTRAIT_RENDER_ITEMS, PortraitClassItems,
    PORTRAIT_SHAPE_ITEMS, PORTRAIT_BORDER_ITEMS, PORTRAIT_STYLE_DEFAULTS, CanonKey, EnsureDB, CurrentPanelKey, UnitDB,
    SeedTextFromGeneral, NormalizeHpMode, NormalizePowerMode, TextScopeGet, TextScopeHasSlots, TextScopeSlotGet,
    TOTINLINE_SEP_VALID, TOTINLINE_CUSTOM_SEPARATOR, TOTINLINE_CUSTOM_SEPARATOR_MAX, TruncateUtf8Chars, CleanToTInlineCustomSeparator,
    ToTInlineSeparator, ShortenPreviewName, TextScopeSet, ForceTextUnit, ApplyPanelUnit, RefreshAllControls, Label, PlaceTopLeft,
    SetOptionWidth, AddOptionDivider, SetWidgetEnabled, AddPlainCheck, NormalizePortraitClassStyle, EnsureUnitPortraitStyle,
    PortraitStyleGet, PortraitStyleSet, ApplyPortrait, NormalizeStatusPreviewId, ClassColor, Clamp01, SettingsCache, PreviewNPCKind,
    NPCColor, GradientPreviewColor, HealthColor, DarkMatchHPColor, HealthBackgroundColor, PowerBackgroundColor, PowerColor,
    ClassPortraitVisual, UnitPreviewPortraitTexture, FontColor, NormalizeToTInlineColorMode, PreviewNameColorFlags, PreviewNameColor,
    PreviewToTInlineColor, SetTex, NormalizePreviewAnchorMode, UnitPreviewBarOverrideEnabled, PreviewHealPredictionEnabled,
    PreviewResolveHealPredAnchorMode, PreviewResolveAbsorbAnchorMode, PreviewAbsorbBarEnabled, PreviewOverlayWidth, LayoutUnitPreviewOverlay,
    MakeFS, ReadPowerBarEnabled, CanDetachPowerBarKey, ReadPowerBarHeight, ResolveNameAnchor, NumText, JoinSep, FormatMode, UnitPreviewText)
