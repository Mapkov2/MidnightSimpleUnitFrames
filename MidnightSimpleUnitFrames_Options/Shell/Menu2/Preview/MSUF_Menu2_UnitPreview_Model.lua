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
local PreviewFullNumbers = _G.BreakUpLargeNumbers
--- Mirrors the live abbreviation style so the preview shows what the frames
--- will actually render (see Runtime/MSUF_NumberFormat.lua).
local PreviewNumOpts = nil
do
    local NumberFormat = MSUF.NumberFormat
    if NumberFormat and NumberFormat.Register then
        NumberFormat.Register(function(options) PreviewNumOpts = options end)
    end
end
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
local CanDetachUnitPowerBar = _G.MSUF_CanDetachUnitPowerBar
local UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet" }
local UNIT_SET = {}
for i = 1, #UNIT_KEYS do UNIT_SET[UNIT_KEYS[i]] = true end
local CONTROL_CHILD_KEYS, CONTROL_NAME_SUFFIXES = M.WordList "minusButton plusButton Button _msufPeelButton", M.WordList "Button Text Low High"
local UNIT_LABELS = { player = "Player", target = "Target", targettarget = "Target of Target", focustarget = "Focus Target", focus = "Focus", boss = "Boss Frames", pet = "Pet" }
local UNIT_DATA = {
    -- Stylized fallback data. The preview prefers a live snapshot of the real
    -- unit (see LiveUnitData below) so it mirrors the frame's current state;
    -- this table backfills any unit or field that is unavailable (unit does
    -- not exist, loading screens, secret-restricted values).
    player = { name = "MIDNIGHT", class = "ROGUE", className = "Rogue", race = "Night Elf", hp = 0.72, power = 0.52, powerToken = "ENERGY", level = "80", elite = false, isPlayer = true, portraitTexture = "Interface\\ICONS\\Ability_Stealth" },
    target = { name = "Astral Warden", class = "MAGE", className = "Mage", race = "Construct", hp = 0.41, power = 0.68, powerToken = "MANA", level = "82", elite = true, classification = "elite", reactionKind = "neutral", npcKind = "npcRegular", portraitTexture = "Interface\\ICONS\\Spell_Frost_FrostBolt02" },
    targettarget = { name = "Moonlit Tank", class = "WARRIOR", className = "Warrior", race = "Human", hp = 0.88, power = 0.36, powerToken = "RAGE", level = "80", elite = false, isPlayer = true, portraitTexture = "Interface\\ICONS\\Ability_Warrior_DefensiveStance" },
    focustarget = { name = "Marked Add", class = "WARRIOR", className = "Warrior", race = "Orc", hp = 0.57, power = 0.24, powerToken = "RAGE", level = "81", elite = false, reactionKind = "enemy", npcKind = "npcMelee", portraitTexture = "Interface\\ICONS\\Ability_Warrior_Charge" },
    focus = { name = "Voidcaller", class = "WARLOCK", className = "Warlock", race = "Orc", hp = 0.63, power = 0.81, powerToken = "MANA", level = "81", elite = true, classification = "rareelite", reactionKind = "enemy", npcKind = "npcCaster", portraitTexture = "Interface\\ICONS\\Spell_Shadow_Metamorphosis" },
    boss = { name = "Boss Preview", class = "DEATHKNIGHT", className = "Death Knight", race = "Undead", hp = 0.55, power = 0.35, powerToken = "MANA", level = "??", elite = true, classification = "worldboss", reactionKind = "enemy", npcKind = "npcBoss", portraitTexture = "Interface\\ICONS\\Achievement_Boss_LichKing" },
    pet = { name = "Companion", class = "HUNTER", className = "Hunter", race = "Beast", hp = 0.79, power = 0.44, powerToken = "FOCUS", level = "80", elite = false, isPet = true, reactionKind = "friendly", portraitTexture = "Interface\\ICONS\\Ability_Hunter_BeastCall" },
}
local POWER_BAR_MASTER_KEYS = {
    player = "showPlayerPowerBar",
    target = "showTargetPowerBar",
    focus = "showFocusPowerBar",
    boss = "showBossPowerBar",
}
local POWER_BAR_DEFAULT_ON = {
    player = true,
    target = true,
    focus = false,
    targettarget = false,
    focustarget = false,
    pet = true,
    boss = false,
}
local function PreviewRaidGroupNameAllowed(key)
    return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "focus"
end
local function PreviewRaidGroupNameText(conf)
    local style = conf and conf.raidGroupNameStyle
    local group = tostring(Preview.LiveRaidSubgroup and Preview.LiveRaidSubgroup() or 2)
    if style == "BRACKET" then return "[" .. group .. "]" end
    if style == "NONE" then return group end
    return "(" .. group .. ")"
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
    portraitSizeMode = "UNIFORM",
    portraitSizeOverride = 0,
    portraitOffsetX = 0,
    portraitOffsetY = 0,
    portraitZoom = 100,
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
local IsSecretValue = _G.issecretvalue or function(_) return false end
local LIVE_UNIT_TOKENS = { player = "player", target = "target", targettarget = "targettarget", focustarget = "focustarget", focus = "focus", boss = "boss1", pet = "pet" }
local liveUnitDataCache = {}
local function LiveNumber(value)
    if value == nil or IsSecretValue(value) == true then return nil end
    return tonumber(value)
end
local function LivePlain(value)
    if value == nil or IsSecretValue(value) == true then return nil end
    return value
end
--- Live snapshot of the unit behind a preview key so the preview mirrors the
--- frame's current state (name, class, exact HP/power values, level, elite,
--- reaction). Strictly pull-based: only preview refreshes call this (menu
--- open, out of combat), never events or combat code, so it adds zero combat
--- overhead. Every field falls back to the stylized UNIT_DATA mock when the
--- unit or a value is unavailable (missing unit, loading, secret values).
local function LiveUnitData(key)
    key = CanonKey(key)
    local unit = LIVE_UNIT_TOKENS[key]
    local UnitExists = _G.UnitExists
    if not (unit and type(UnitExists) == "function") then return nil end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    local exists = UnitExists(unit)
    if IsSecretValue(exists) == true or exists ~= true then return nil end
    local mock = UNIT_DATA[key] or UNIT_DATA.player or {}
    local d = liveUnitDataCache[key]
    if not d then
        d = {}
        liveUnitDataCache[key] = d
    end
    d.live = true
    d.liveUnit = unit
    d.name = LivePlain(_G.UnitName and _G.UnitName(unit)) or mock.name
    local className, classToken
    if _G.UnitClass then className, classToken = _G.UnitClass(unit) end
    d.class = LivePlain(classToken) or mock.class
    d.className = LivePlain(className) or mock.className
    d.race = (_G.UnitRace and LivePlain(_G.UnitRace(unit)))
        or (_G.UnitCreatureType and LivePlain(_G.UnitCreatureType(unit)))
        or mock.race
    local level = _G.UnitLevel and LiveNumber(_G.UnitLevel(unit))
    d.level = (level and level > 0 and tostring(level)) or (level and "??") or mock.level
    local isPlayer = _G.UnitIsPlayer and _G.UnitIsPlayer(unit)
    if IsSecretValue(isPlayer) == true then isPlayer = mock.isPlayer end
    d.isPlayer = isPlayer == true
    d.isPet = key == "pet"
    local classification = _G.UnitClassification and LivePlain(_G.UnitClassification(unit))
    d.classification = classification or mock.classification
    d.elite = classification == "elite" or classification == "rareelite"
        or classification == "worldboss" or classification == "rare"
        or (classification == nil and mock.elite == true)
    local dead = _G.UnitIsDeadOrGhost and _G.UnitIsDeadOrGhost(unit)
    if IsSecretValue(dead) == true then dead = false end
    local reaction = _G.UnitReaction and LiveNumber(_G.UnitReaction(unit, "player"))
    if d.isPlayer or dead ~= true then
        if reaction and reaction >= 5 then
            d.reactionKind = "friendly"
        elseif reaction and reaction == 4 then
            d.reactionKind = "neutral"
        elseif reaction then
            d.reactionKind = "enemy"
        else
            d.reactionKind = mock.reactionKind or (d.isPlayer and "friendly" or "enemy")
        end
    else
        d.reactionKind = "dead"
    end
    local hpCur = _G.UnitHealth and LiveNumber(_G.UnitHealth(unit))
    local hpMax = _G.UnitHealthMax and LiveNumber(_G.UnitHealthMax(unit))
    if hpCur and hpMax and hpMax > 0 then
        if hpCur < 0 then hpCur = 0 elseif hpCur > hpMax then hpCur = hpMax end
        d.hpCur, d.hpMax = hpCur, hpMax
        d.hp = hpCur / hpMax
    else
        d.hpCur, d.hpMax = nil, nil
        d.hp = mock.hp or 0.72
    end
    local powerToken
    if _G.UnitPowerType then
        local _, token = _G.UnitPowerType(unit)
        powerToken = LivePlain(token)
    end
    d.powerToken = powerToken or mock.powerToken or "MANA"
    local powerCur = _G.UnitPower and LiveNumber(_G.UnitPower(unit))
    local powerMax = _G.UnitPowerMax and LiveNumber(_G.UnitPowerMax(unit))
    if powerCur and powerMax and powerMax > 0 then
        if powerCur < 0 then powerCur = 0 elseif powerCur > powerMax then powerCur = powerMax end
        d.powerCur, d.powerMax = powerCur, powerMax
        d.power = powerCur / powerMax
    else
        d.powerCur, d.powerMax = nil, nil
        d.power = mock.power or 0.5
    end
    -- Absorb is exact only while one exists; a zero would blank the absorb
    -- element preview, so the stylized sample backs the zero case.
    local absorb = _G.UnitGetTotalAbsorbs and LiveNumber(_G.UnitGetTotalAbsorbs(unit))
    d.absorb = (absorb and absorb > 0) and absorb or nil
    -- Type classification mirrors the live NPC tint decisions closely enough
    -- for a preview; PreviewNPCKind applies the same settings gating on top.
    if d.isPlayer then
        d.npcKind = nil
    elseif key == "boss" or classification == "worldboss" then
        d.npcKind = "npcBoss"
    elseif classification == "elite" or classification == "rareelite" then
        d.npcKind = d.powerToken == "MANA" and "npcCaster" or "npcMelee"
    elseif classification == "normal" or classification == "trivial" or classification == "minus" then
        d.npcKind = "npcRegular"
    else
        d.npcKind = mock.npcKind
    end
    d.portraitTexture = mock.portraitTexture
    return d
end
--- Player's current raid subgroup for the raid-group name preview. nil when
--- not in a raid (callers keep their stylized fallback).
local function LiveRaidSubgroup()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    if not (_G.IsInRaid and _G.IsInRaid() and _G.GetRaidRosterInfo) then return nil end
    local index = _G.UnitInRaid and _G.UnitInRaid("player")
    if IsSecretValue(index) == true then return nil end
    index = tonumber(index)
    if not index then return nil end
    -- UnitInRaid has historically been 0-based; accept either convention.
    -- Allocation-free: this runs inside preview refreshes.
    local candidate = index
    for _ = 1, 2 do
        if candidate >= 1 and candidate <= 40 then
            local name, _, subgroup = _G.GetRaidRosterInfo(candidate)
            if name ~= nil and not IsSecretValue(subgroup) then
                local mine = _G.UnitIsUnit and _G.UnitIsUnit("player", "raid" .. candidate)
                if mine == true or _G.UnitIsUnit == nil then return tonumber(subgroup) end
            end
        end
        candidate = index + 1
    end
    return nil
end
Preview.LiveUnitData = LiveUnitData
Preview.LiveRaidSubgroup = LiveRaidSubgroup
local function ProfileSystemNeedsInit()
    local active = _G.MSUF_ActiveProfile
    local gdb = _G.MSUF_GlobalDB
    local profiles = type(gdb) == "table" and gdb.profiles or nil
    local activeTable = type(active) == "string" and type(profiles) == "table" and profiles[active] or nil
    return type(active) ~= "string"
        or active == ""
        or type(_G.MSUF_DB) ~= "table"
        or type(activeTable) ~= "table"
        or _G.MSUF_DB ~= activeTable
end
local function EnsureDB()
    if ProfileSystemNeedsInit() and type(_G.MSUF_InitProfiles) == "function" then
        _G.MSUF_InitProfiles()
    end
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
    if name == "" then return name end
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
    local nameAnchor = tostring(anchorConf.nameTextAnchor or "TOPLEFT"):upper()
    if nameAnchor ~= "LEFT" and nameAnchor ~= "TOPLEFT" and nameAnchor ~= "FRAMELEFT" then showDots = false end
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
    if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
        _G.MSUF_ForceTextLayoutForUnitKey(key)
    elseif type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        -- Text-layout entry unavailable: a full scoped apply must still land
        -- so a preview edit can never stay preview-only.
        _G.MSUF_UFCore_NotifyConfigChanged(key, true, true, reason or "UNIT_TEXT_OPTIONS")
    end
end
local function ApplyPanelUnit(panel, key, reason)
    key = CanonKey(key or CurrentPanelKey(panel))
    if panel and panel._msufAPI and type(panel._msufAPI.ApplySettingsForKey) == "function" then
        panel._msufAPI.ApplySettingsForKey(key)
    elseif type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        -- Pinned/floating previews can commit without a host panel; the live
        -- frame must still re-apply the written settings (preview<->live parity).
        _G.MSUF_UFCore_NotifyConfigChanged(key, true, true, reason or "UNIT_OPTIONS")
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
local function PreviewGradientHealth(cache, g)
    return {
        gradientLowR = (cache and cache.healthGradientLowR) or g.healthGradientLowR or 1,
        gradientLowG = (cache and cache.healthGradientLowG) or g.healthGradientLowG or 0,
        gradientLowB = (cache and cache.healthGradientLowB) or g.healthGradientLowB or 0,
        gradientMidR = (cache and cache.healthGradientMidR) or g.healthGradientMidR or 1,
        gradientMidG = (cache and cache.healthGradientMidG) or g.healthGradientMidG or 1,
        gradientMidB = (cache and cache.healthGradientMidB) or g.healthGradientMidB or 0,
        gradientHighR = (cache and cache.healthGradientHighR) or g.healthGradientHighR or 0,
        gradientHighG = (cache and cache.healthGradientHighG) or g.healthGradientHighG or 1,
        gradientHighB = (cache and cache.healthGradientHighB) or g.healthGradientHighB or 0,
    }
end
local function GradientPreviewColor(pct, health)
    pct = Clamp01(pct, 0.75)
    local common = MSUF and MSUF.UFBarTextCommon
    if common and type(common.PreviewHealthGradientColor) == "function" then
        local r, g, b = common.PreviewHealthGradientColor(health, pct)
        if r ~= nil then return r, g, b end
    end
    health = health or {}
    local lr, lg, lb = health.gradientLowR or 1, health.gradientLowG or 0, health.gradientLowB or 0
    local mr, mg, mb = health.gradientMidR or 1, health.gradientMidG or 1, health.gradientMidB or 0
    local hr, hg, hb = health.gradientHighR or 0, health.gradientHighG or 1, health.gradientHighB or 0
    if pct < 0.5 then
        local t = pct * 2
        return lr + (mr - lr) * t, lg + (mg - lg) * t, lb + (mb - lb) * t
    end
    local t = (pct - 0.5) * 2
    return mr + (hr - mr) * t, mg + (hg - mg) * t, mb + (hb - mb) * t
end
local PREVIEW_HEALTH_MODE_ALIASES = {
    CLASS = "class", class = "class",
    GRADIENT = "gradient", gradient = "gradient",
    DARK = "dark", dark = "dark",
    UNIFIED = "unified", unified = "unified",
}
local function NormalizePreviewHealthMode(value)
    if type(value) ~= "string" then return nil end
    return PREVIEW_HEALTH_MODE_ALIASES[value] or PREVIEW_HEALTH_MODE_ALIASES[value:lower()]
end
local function PreviewGlobalHealthMode(g, cache)
    local mode = (cache and cache.barMode) or g.barMode or "dark"
    mode = NormalizePreviewHealthMode(mode) or ((g.useClassColors and "class") or "dark")
    if mode == "gradient" then
        local enabled = cache and cache.healthGradientEnabled
        if enabled == nil then enabled = g.enableHealthGradient ~= false end
        if not enabled then mode = "class" end
    end
    return mode
end
local function PreviewHealthMode(key, g, cache)
    local db = _G.MSUF_DB
    local conf = db and db[CanonKey(key)]
    return NormalizePreviewHealthMode(conf and conf.healthColorMode) or PreviewGlobalHealthMode(g, cache)
end
local function HealthColor(key, data)
    local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local cache = SettingsCache()
    local mode = PreviewHealthMode(key, g, cache)
    data = data or UNIT_DATA.player
    if mode == "class" then
        if data.isPet and cache and cache.petFrameUsePlayerClassColor then
            return cache.petPlayerClassR or 0.12, cache.petPlayerClassG or 0.62, cache.petPlayerClassB or 0.95
        end
        if data.isPet and cache and cache.petFrameColorEnabled then return cache.petFrameColorR or 0, cache.petFrameColorG or 0.8, cache.petFrameColorB or 0 end
        if data.isPlayer then return ClassColor(data.class) end
        local npcClassColor = cache and cache.npcClassColorBar
        if npcClassColor == nil then npcClassColor = g.npcClassColorBar == true end
        if npcClassColor and not data.isPet and key ~= "boss" then return ClassColor(data.class) end
        return NPCColor(PreviewNPCKind(key, data, cache))
    end
    if mode == "gradient" then return GradientPreviewColor(data.hp, PreviewGradientHealth(cache, g)) end
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
local function PerUnitBackgroundAlpha(conf, key, fallbackKey, resolvedAlpha, resolver)
    local alpha = conf and conf[key]
    if alpha == nil and fallbackKey then alpha = conf and conf[fallbackKey] end
    if type(alpha) ~= "number" then return Clamp01(resolvedAlpha, 0.9) end
    local tintAlpha = 1
    if type(resolver) == "function" then
        local _, _, _, value = resolver()
        tintAlpha = Clamp01(value, 1)
    end
    return Clamp01(alpha, 1) * tintAlpha
end
local function HealthBackgroundColor(hr, hg, hb, data, conf)
    local cache = SettingsCache()
    local gen = (cache and cache.generalRef) or (_G.MSUF_DB and _G.MSUF_DB.general)
    local r, g, b, a
    if cache then
        r, g, b, a = cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA
    elseif type(_G.MSUF_GetBarBackgroundTintRGBA) == "function" then
        r, g, b, a = _G.MSUF_GetBarBackgroundTintRGBA()
    end
    r, g, b, a = Clamp01(r, 0), Clamp01(g, 0), Clamp01(b, 0), Clamp01(a, 0.9)
    a = PerUnitBackgroundAlpha(conf, "hpBgAlpha", nil, a, _G.MSUF_GetBarBackgroundTintRGBA)
    if (cache and cache.barBgClassColor) or ((not cache) and gen and gen.barBgClassColor) then
        local classToken = data and data.isPlayer and data.class or UNIT_DATA.player.class
        r, g, b = ClassColor(classToken)
    elseif (cache and cache.barBgMatchHPColor) or ((not cache) and gen and gen.barBgMatchHPColor) then
        r, g, b = DarkMatchHPColor(hr, hg, hb, cache)
    end
    return r, g, b, a
end
local function PowerBackgroundColor(pr, pg, pb, hr, hg, hb, conf)
    local cache = SettingsCache()
    local r, g, b, a
    if cache then
        r, g, b, a = cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA
    elseif type(_G.MSUF_GetPowerBarBackgroundTintRGBA) == "function" then
        r, g, b, a = _G.MSUF_GetPowerBarBackgroundTintRGBA()
    end
    r, g, b, a = Clamp01(r, pr * 0.16), Clamp01(g, pg * 0.16), Clamp01(b, pb * 0.16), Clamp01(a, 0.9)
    a = PerUnitBackgroundAlpha(conf, "powerBarBgAlpha", "hpBgAlpha", a, _G.MSUF_GetPowerBarBackgroundTintRGBA)
    if cache and cache.powerBarBgMatchHPColor then r, g, b = DarkMatchHPColor(hr, hg, hb, cache) end
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
        if g.healPredEnabled ~= nil then return g.healPredEnabled == true end
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
    if _G.MSUF_ShouldShowAbsorbTextureTest and _G.MSUF_ShouldShowAbsorbTextureTest(nil, key, "absorb") then return true end
    local enabled
    if UnitPreviewBarOverrideEnabled(conf) and conf.enableAbsorbBar ~= nil then enabled = conf.enableAbsorbBar end
    if enabled == nil and g and g.enableAbsorbBar ~= nil then enabled = g.enableAbsorbBar end
    if enabled ~= nil then return enabled ~= false end
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
    conf = conf or {}
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    if conf.showPowerBar ~= nil then return conf.showPowerBar ~= false end
    local masterKey = POWER_BAR_MASTER_KEYS[key]
    if masterKey and bars and bars[masterKey] ~= nil then return bars[masterKey] ~= false end
    if conf.showPowerText == nil and conf.showPower ~= nil then return conf.showPower ~= false end
    return POWER_BAR_DEFAULT_ON[key] == true
end
local function CanDetachPowerBarKey(key)
    if type(CanDetachUnitPowerBar) == "function" then
        return CanDetachUnitPowerBar(key) == true
    end
    key = CanonKey(key)
    local powerUnits = UnitPage.POWER_UNITS
    if type(powerUnits) == "table" then return powerUnits[key] == true end
    return UNIT_SET[key] == true
end
local function ReadPowerBarHeight(conf)
    local h = tonumber(conf.powerBarHeight) or 3
    if h < 1 then h = 1 elseif h > 20 then h = 20 end
    return h
end
local function ResolveNameAnchor(anchor, x)
    anchor = tostring(anchor or "TOPLEFT"):upper()
    x = tonumber(x) or 0
    if anchor == "LEFT" then anchor = "TOPLEFT"
    elseif anchor == "CENTER" then anchor = "TOP"
    elseif anchor == "RIGHT" then anchor = "TOPRIGHT" end
    if anchor == "TOPRIGHT" then return "TOPRIGHT", "TOPRIGHT", -x, "RIGHT" end
    if anchor == "TOP" then return "TOP", "TOP", x, "CENTER" end
    if anchor == "FRAMELEFT" then return "LEFT", "LEFT", x, "LEFT" end
    if anchor == "FRAMECENTER" then return "CENTER", "CENTER", x, "CENTER" end
    if anchor == "FRAMERIGHT" then return "RIGHT", "RIGHT", -x, "RIGHT" end
    return "TOPLEFT", "TOPLEFT", x, "LEFT"
end
local function ResolveNameOffsetDelta(anchor, dx, dy)
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    -- Right-edge anchors store an inward-positive X offset and
    -- ResolveNameAnchor negates it. Direct manipulation therefore mirrors the
    -- stored X delta so the text continues to follow the cursor on screen.
    anchor = tostring(anchor or "TOPLEFT"):upper()
    if anchor == "RIGHT" or anchor == "TOPRIGHT" or anchor == "FRAMERIGHT" then dx = -dx end
    return dx, dy
end
local function NumText(v, shortNumbers)
    if shortNumbers == false then
        if PreviewFullNumbers then return PreviewFullNumbers(v) end
        return tostring(v)
    end
    if PreviewAbbreviateNumbers then return PreviewAbbreviateNumbers(v, PreviewNumOpts) end
    if v >= 1000000 then return format("%.1fm", v / 1000000) end
    if v >= 1000 then return format("%.1fk", v / 1000) end
    return tostring(v)
end
local function JoinSep(sep)
    sep = tostring(sep or "")
    if sep == "" then return " " end
    return " " .. sep .. " "
end
local ABSORB_MODE_BASE = {
    CURRENTABSORB = "CURRENT", FULLVALUEABSORB = "FULLVALUE", MAXABSORB = "MAX", DEFICITABSORB = "DEFICIT",
    CURMAXABSORB = "CURMAX", PERCENTABSORB = "PERCENT", CURPERCENTABSORB = "CURPERCENT",
    CURMAXPERCENTABSORB = "CURMAXPERCENT", MAXPERCENTABSORB = "MAXPERCENT",
    PERCENTCURABSORB = "PERCENTCUR", PERCENTMAXABSORB = "PERCENTMAX",
    PERCENTCURMAXABSORB = "PERCENTCURMAX", MAXCURABSORB = "MAXCUR",
    PERCENTMAXCURABSORB = "PERCENTMAXCUR",
}
local ABSORB_ICON_MARKUP = "|TInterface\\Icons\\INV_Shield_06:0|t"
local function FormatMode(mode, cur, maxVal, pct, sep, isPower, hidePercentSymbol, shortNumbers, absorbIcon, absorbValue)
    if isPower then mode = NormalizePowerMode(mode) else mode = NormalizeHpMode(mode) end
    if mode == "NONE" then return "" end
    local absorbBase = ABSORB_MODE_BASE[mode]
    local c = NumText(cur, shortNumbers)
    local m = NumText(maxVal, shortNumbers)
    local a = NumText(tonumber(absorbValue) or 125000, shortNumbers)
    local absorbText = (absorbIcon and (ABSORB_ICON_MARKUP .. " ") or "") .. a
    local p = tostring(pct)
    if hidePercentSymbol ~= true then p = p .. "%" end
    local s = JoinSep(sep)
    if mode == "ABSORB" then return absorbText end
    mode = absorbBase or mode
    local value
    if mode == "PERCENT" then value = p
    elseif mode == "CURRENT" or mode == "FULLVALUE" then value = c
    elseif mode == "MAX" then value = m
    elseif mode == "DEFICIT" then value = "-" .. NumText(maxVal - cur, shortNumbers)
    elseif mode == "CURMAX" then value = c .. s .. m
    elseif mode == "MAXCUR" then value = m .. s .. c
    elseif mode == "CURPERCENT" then value = c .. s .. p
    elseif mode == "PERCENTCUR" then value = p .. s .. c
    elseif mode == "CURMAXPERCENT" then value = c .. s .. m .. s .. p
    elseif mode == "PERCENTMAXCUR" then value = p .. s .. m .. s .. c
    elseif mode == "MAXPERCENT" then value = m .. s .. p
    elseif mode == "PERCENTMAX" then value = p .. s .. m
    elseif mode == "PERCENTCURMAX" then value = p .. s .. c .. s .. m
    else value = c .. s .. p end
    return absorbBase and (value .. " + " .. absorbText) or value
end
local UnitPreviewText = {}
function UnitPreviewText.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
    return PreviewHelpers.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
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
    MakeFS ReadPowerBarEnabled CanDetachPowerBarKey ReadPowerBarHeight ResolveNameAnchor ResolveNameOffsetDelta NumText JoinSep FormatMode UnitPreviewText LiveUnitData LiveRaidSubgroup
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
    MakeFS, ReadPowerBarEnabled, CanDetachPowerBarKey, ReadPowerBarHeight, ResolveNameAnchor, ResolveNameOffsetDelta, NumText, JoinSep, FormatMode, UnitPreviewText, LiveUnitData, LiveRaidSubgroup)
