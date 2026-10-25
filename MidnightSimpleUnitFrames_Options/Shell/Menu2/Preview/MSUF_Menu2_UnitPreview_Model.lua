-- Menu2 unit preview model: creates fake preview data and model state for unit pages.
-- Preview-only state must not leak into live unit frames or profile runtime paths.
local MSUF = _G.MSUF
local FILE = "Menu2/UnitPreview_Model"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2 or {}
local ExportPublic = MSUF.ExportPublic
local TR = MSUF.MSUF2.PreviewHelpers.TranslateUnitPreview
local max, min = math.max, math.min
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
local CanDetachUnitPowerBar = MSUF.Require("MSUF_CanDetachUnitPowerBar", FILE)
local UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "boss", "arena", "pet", "pettarget" }
local UNIT_SET = {}
for i = 1, #UNIT_KEYS do UNIT_SET[UNIT_KEYS[i]] = true end
local CONTROL_CHILD_KEYS, CONTROL_NAME_SUFFIXES = M.WordList "minusButton plusButton Button _msufPeelButton", M.WordList "Button Text Low High"
local UNIT_LABELS = { player = "Player", target = "Target", targettarget = "Target of Target", focustarget = "Focus Target", focus = "Focus",
    boss = "Boss Frames", arena = "Arena Frames", pet = "Pet", pettarget = "Pet Target" }
local UNIT_DATA = {
    -- Stylized fallback data. The preview prefers a live snapshot of the real
    -- unit (see LiveUnitData below) so it mirrors the frame's current state;
    -- this table backfills any unit or field that is unavailable (unit does
    -- not exist, loading screens, secret-restricted values).
    player = { name = "MIDNIGHT", class = "ROGUE", className = "Rogue", race = "Night Elf", hp = 0.72, power = 0.52, powerToken = "ENERGY", level = "80",
        elite = false, isPlayer = true, portraitTexture = "Interface\\ICONS\\Ability_Stealth" },
    target = { name = "Astral Warden", class = "MAGE", className = "Mage", race = "Construct", hp = 0.41, power = 0.68, powerToken = "MANA", level = "82",
        elite = true, classification = "elite", reactionKind = "neutral", npcKind = "npcRegular",
        portraitTexture = "Interface\\ICONS\\Spell_Frost_FrostBolt02" },
    targettarget = { name = "Moonlit Tank", class = "WARRIOR", className = "Warrior", race = "Human", hp = 0.88, power = 0.36, powerToken = "RAGE",
        level = "80", elite = false, isPlayer = true, portraitTexture = "Interface\\ICONS\\Ability_Warrior_DefensiveStance" },
    pettarget = { name = "Hunted Foe", class = "WARRIOR", className = "Warrior", race = "Orc", hp = 0.57, power = 0.24, powerToken = "RAGE", level = "81",
        elite = false, reactionKind = "enemy", npcKind = "npcMelee", portraitTexture = "Interface\\ICONS\\Ability_Warrior_Charge" },
    focustarget = { name = "Marked Add", class = "WARRIOR", className = "Warrior", race = "Orc", hp = 0.57, power = 0.24, powerToken = "RAGE", level = "81",
        elite = false, reactionKind = "enemy", npcKind = "npcMelee", portraitTexture = "Interface\\ICONS\\Ability_Warrior_Charge" },
    focus = { name = "Voidcaller", class = "WARLOCK", className = "Warlock", race = "Orc", hp = 0.63, power = 0.81, powerToken = "MANA", level = "81",
        elite = true, classification = "rareelite", reactionKind = "enemy", npcKind = "npcCaster",
        portraitTexture = "Interface\\ICONS\\Spell_Shadow_Metamorphosis" },
    boss = { name = "Boss Preview", class = "DEATHKNIGHT", className = "Death Knight", race = "Undead", hp = 0.55, power = 0.35, powerToken = "MANA",
        level = "??", elite = true, classification = "worldboss", reactionKind = "enemy", npcKind = "npcBoss",
        portraitTexture = "Interface\\ICONS\\Achievement_Boss_LichKing" },
    pet = { name = "Companion", class = "HUNTER", className = "Hunter", race = "Beast", hp = 0.79, power = 0.44, powerToken = "FOCUS", level = "80",
        elite = false, isPet = true, reactionKind = "friendly", portraitTexture = "Interface\\ICONS\\Ability_Hunter_BeastCall" },
    arena = { name = "Arena Opponent", class = "MAGE", className = "Mage", race = "Human", hp = 0.65, power = 0.80, powerToken = "MANA", level = "80",
        elite = false, isPlayer = true, reactionKind = "enemy", portraitTexture = "Interface\\ICONS\\Spell_Frost_FrostBolt02" },
}
local POWER_BAR_MASTER_KEYS = {
    player = "showPlayerPowerBar",
    target = "showTargetPowerBar",
    focus = "showFocusPowerBar",
    boss = "showBossPowerBar",
    arena = "showArenaPowerBar",
}
-- Units not listed (focus, targettarget, focustarget, pettarget, boss) default to off.
local POWER_BAR_DEFAULT_ON = { player = true, target = true, pet = true, arena = true }
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
    if type(key) == "string" and key:match("^arena%d+$") then return "arena" end
    if UNIT_SET[key] then return key end
    return "player"
end
local IsSecretValue = issecretvalue or MSUF.Util.NoSecret
local LIVE_UNIT_TOKENS = { player = "player", target = "target", targettarget = "targettarget", focustarget = "focustarget", focus = "focus", boss = "boss1",
    arena = "arena1", pet = "pet", pettarget = "pettarget" }
local liveUnitDataCache = {}
local function LiveNumber(value)
    if IsSecretValue(value) == true or value == nil then return nil end
    return tonumber(value)
end
local function LivePlain(value)
    if IsSecretValue(value) == true or value == nil then return nil end
    return value
end
--- Live snapshot of the unit behind a preview key so the preview mirrors the
--- frame's current state (name, class, exact HP/power values, level, elite,
--- reaction). Strictly pull-based: only preview refreshes call this (menu
--- open, out of combat), never events or combat code, so it adds zero combat
--- overhead. Every field falls back to the stylized UNIT_DATA mock when the
--- unit or a value is unavailable (missing unit, loading, secret values).
local function LiveUnitData(key, playerManaSourceActive)
    key = CanonKey(key)
    local unit = LIVE_UNIT_TOKENS[key]
    if not (unit and type(UnitExists) == "function") then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
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
    d.name = LivePlain(UnitName and UnitName(unit)) or TR(mock.name)
    local className, classToken
    if UnitClass then className, classToken = UnitClass(unit) end
    d.class = LivePlain(classToken) or mock.class
    d.className = LivePlain(className) or mock.className
    d.race = (UnitRace and LivePlain(UnitRace(unit)))
        or (UnitCreatureType and LivePlain(UnitCreatureType(unit)))
        or mock.race
    local level = UnitLevel and LiveNumber(UnitLevel(unit))
    d.level = (level and level > 0 and tostring(level)) or (level and "??") or mock.level
    local isPlayer = UnitIsPlayer and UnitIsPlayer(unit)
    if IsSecretValue(isPlayer) == true then isPlayer = mock.isPlayer end
    d.isPlayer = isPlayer == true
    d.isPet = key == "pet"
    local classification = UnitClassification and LivePlain(UnitClassification(unit))
    d.classification = classification or mock.classification
    d.elite = classification == "elite" or classification == "rareelite"
        or classification == "worldboss" or classification == "rare"
        or (classification == nil and mock.elite == true)
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if IsSecretValue(dead) == true then dead = false end
    d.dead = dead == true
    local reaction = UnitReaction and LiveNumber(UnitReaction(unit, "player"))
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
    local hpCur = UnitHealth and LiveNumber(UnitHealth(unit))
    local hpMax = UnitHealthMax and LiveNumber(UnitHealthMax(unit))
    d.hpMax = hpMax and hpMax > 0 and hpMax or nil
    d.hpCur = hpCur and max(0, min(d.hpMax or MSUF.UF.UnitScene.HEALTH_MAX, hpCur)) or nil
    -- A live unit whose current health is secret shows a full bar, like its frame out of combat, instead of the
    -- stylized 72% sample; units without readable live health keep the sample.
    d.hp = d.hpCur and d.hpMax and d.hpCur / d.hpMax or (d.hpMax and 1) or mock.hp or 0.72
    local powerType = playerManaSourceActive == true
        and ((Enum and Enum.PowerType and Enum.PowerType.Mana) or 0) or nil
    local powerToken
    if powerType then
        powerToken = "MANA"
    elseif UnitPowerType then
        local id, token = UnitPowerType(unit)
        powerType, powerToken = LiveNumber(id), LivePlain(token)
    end
    d.powerType = powerType
    d.powerToken = powerToken or mock.powerToken or "MANA"
    local powerCur = UnitPower and LiveNumber(UnitPower(unit, powerType))
    local powerMax = UnitPowerMax and LiveNumber(UnitPowerMax(unit, powerType))
    d.powerMax = powerMax and powerMax > 0 and powerMax or nil
    d.powerCur = powerCur and max(0, min(d.powerMax or 100, powerCur)) or nil
    d.power = d.powerCur and d.powerMax and d.powerCur / d.powerMax or mock.power or 0.5
    -- Keep the absorb element inspectable when the live unit has no shield.
    local absorb = UnitGetTotalAbsorbs and LiveNumber(UnitGetTotalAbsorbs(unit))
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
    local status = MSUF.UFStatusRuntime
    if status and status.LevelDifficultyTier then
        d.levelTier = status.LevelDifficultyTier(unit, d.level == "??" and -1 or tonumber(d.level))
    end
    d.portraitTexture = mock.portraitTexture
    return d
end
--- Player's current raid subgroup for the raid-group name preview. nil when
--- not in a raid (callers keep their stylized fallback).
local function LiveRaidSubgroup()
    if InCombatLockdown and InCombatLockdown() then return nil end
    if not (IsInRaid and IsInRaid() and GetRaidRosterInfo) then return nil end
    local index = UnitInRaid and UnitInRaid("player")
    if IsSecretValue(index) == true then return nil end
    index = tonumber(index)
    if not index then return nil end
    -- UnitInRaid has historically been 0-based; accept either convention.
    -- Allocation-free: this runs inside preview refreshes.
    local candidate = index
    for _ = 1, 2 do
        if candidate >= 1 and candidate <= 40 then
            local name, _, subgroup = GetRaidRosterInfo(candidate)
            if name ~= nil and not IsSecretValue(subgroup) then
                local mine = UnitIsUnit and UnitIsUnit("player", "raid" .. candidate)
                if (not IsSecretValue(mine) and mine == true) or UnitIsUnit == nil then return tonumber(subgroup) end
            end
        end
        candidate = index + 1
    end
    return nil
end
Preview.LiveUnitData = LiveUnitData
Preview.LiveRaidSubgroup = LiveRaidSubgroup
local ProfileSystemNeedsInit = M.ProfileSystemNeedsInit
-- Core State providers, loaded before the Options addon and never reassigned: resolved once, since EnsureDB
-- runs for every preview setting read.
local CoreEnsureDB = MSUF.Optional("MSUF_EnsureDB") or MSUF.MSUF_EnsureDB or MSUF.EnsureDB
local InitProfiles = MSUF.Require("MSUF_InitProfiles", FILE)
local function EnsureDB()
    if ProfileSystemNeedsInit() then InitProfiles() end
    if CoreEnsureDB then CoreEnsureDB() end
    ExportPublic("MSUF_DB", MSUF_DB or {})
    MSUF_DB.general = MSUF_DB.general or {}
    local db = MSUF_DB
    for i = 1, #UNIT_KEYS do
        db[UNIT_KEYS[i]] = db[UNIT_KEYS[i]] or {}
    end
    return db
end
local function CurrentPanelKey(panel)
    local key = panel and panel._msufGetCurrentKey and panel._msufGetCurrentKey()
    if key == nil then key = panel and panel._msufLastApplyKey end
    return CanonKey(key)
end
local function UnitDB(key)
    local db = EnsureDB()
    key = CanonKey(key)
    db[key] = db[key] or {}
    return db[key], db.general, key
end
local function SeedTextFromGeneral(db)
    if not db then return end
    local g = M.EnsureDB().general or {}
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
--- Shortens a preview name like the runtime does. The settings come from the
--- unit's compiled text spec (nameShorten, nameShortenMax, nameShortenSide,
--- nameShortenDots), which UF_Config's ResolveNameShortening fills with every
--- per-frame alias and clamp; the inline target of target uses its own block
--- (text.inlineToT). The cut counts characters, never bytes, so a Cyrillic or
--- CJK name is never split inside a character.
local function TextScopeSet(key, field, value)
    local u = UnitDB(key)
    SeedTextFromGeneral(u)
    u[field] = value
    u.hpPowerTextOverride = nil
end
-- Core providers (UnitFrames runtime, Edit Mode) load before the Options addon and are exported once, so they are
-- resolved here: ForceTextUnit and ApplyPanelUnit run on every preview drag step.
local ForceTextLayoutForUnitKey = MSUF.Require("MSUF_ForceTextLayoutForUnitKey", FILE)
local NotifyConfigChanged = MSUF.Require("MSUF_UFCore_NotifyConfigChanged", FILE)
local SyncUnitPositionPopup = MSUF.Require("MSUF_SyncUnitPositionPopup", FILE)
local function ForceTextUnit(key)
    ForceTextLayoutForUnitKey(CanonKey(key))
end
local function ApplyPanelUnit(panel, key, reason)
    key = CanonKey(key or CurrentPanelKey(panel))
    local api = panel and panel._msufAPI
    if api and type(api.ApplySettingsForKey) == "function" then
        api.ApplySettingsForKey(key)
    else
        -- Pinned/floating previews can commit without a host panel; the live
        -- frame must still re-apply the written settings (preview<->live parity).
        NotifyConfigChanged(key, true, true, reason or "UNIT_OPTIONS")
    end
    SyncUnitPositionPopup(key, M.EnsureDB()[key])
    -- API.lua exports MSUF_UFPreview_RequestRefresh as a forwarder to this method.
    local requestRefresh = Preview.RequestRefresh
    if requestRefresh then requestRefresh(reason or "UNIT_OPTIONS") end
end
local function RefreshAllControls(list)
    if not list then return end
    for i = 1, #list do
        local w = list[i]
        if w and type(w.Refresh) == "function" then w:Refresh() end
    end
end
local function Label(parent, text, anchor, x, y, width)
    local fs = PixelLayoutRegion(parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    local rel = (anchor and anchor ~= parent) and "BOTTOMLEFT" or "TOPLEFT"
    fs:SetPoint("TOPLEFT", anchor or parent, rel, x or 12, y or -8)
    fs:SetText(TR(text or ""))
    if width then
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
    end
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
    local line = PixelLayoutRegion(parent:CreateTexture(nil, "ARTWORK"))
    line:SetHeight(1)
    line:SetColorTexture(0.20, 0.32, 0.45, 0.32)
    line:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, y or 0)
    line:SetWidth(width or 260)
    return line
end
local function SetTextTint(region, enabled)
    if not (region and region.SetTextColor) then return end
    if enabled then region:SetTextColor(1, 1, 1, 1) else region:SetTextColor(0.55, 0.55, 0.55, 1) end
end
--- Greys out or restores one part of a control: mouse, Enable/Disable, then optionally alpha and text tint.
local function SetPartEnabled(part, enabled, withAlpha, withTint)
    if part.EnableMouse then part:EnableMouse(enabled) end
    if enabled then
        if part.Enable then part:Enable() end
    elseif part.Disable then
        part:Disable()
    end
    if withAlpha and part.SetAlpha then part:SetAlpha(enabled and 1 or 0.45) end
    if withTint then SetTextTint(part, enabled) end
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
    SetTextTint(label, enabled)
    if w.editBox then SetPartEnabled(w.editBox, enabled, false, true) end
    for _, childKey in ipairs(CONTROL_CHILD_KEYS) do
        local child = w[childKey]
        if child then SetPartEnabled(child, enabled, true, false) end
    end
    local n = w.GetName and w:GetName()
    if n then
        for _, suffix in ipairs(CONTROL_NAME_SUFFIXES) do
            local obj = _G[n .. suffix]
            if obj then SetPartEnabled(obj, enabled, true, true) end
        end
    end
    if type(w.Refresh) == "function" then w:Refresh() end
    if type(w._msufToggleUpdate) == "function" then w._msufToggleUpdate() end
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
local ClassColor = MSUF.UF.Config.ClassColor
local Clamp01 = M.Clamp01
local SettingsCache = MSUF.Require("MSUF_UFCore_GetSettingsCache", FILE)
-- Settings-cache switch of the NPC type tint per unit; units not listed always allow it.
local NPC_TYPE_SWITCHES = {
    target = "npcTypeTarget", focus = "npcTypeFocus", boss = "npcTypeBoss", targettarget = "npcTypeToT", focustarget = "npcTypeToT",
}
local function PreviewNPCKind(key, data, cache, forText)
    data = data or {}
    if cache and cache.npcColorMode == "type" and cache[forText and "npcTypeColorText" or "npcTypeColorBar"] then
        local switch = NPC_TYPE_SWITCHES[key]
        if (not switch or cache[switch] ~= false) and data.npcKind then return data.npcKind end
    end
    return data.reactionKind or "enemy"
end
-- One stops table, refilled on every call: the shared gradient evaluator
-- caches its colour curve on the table and checks it against these values, so
-- a repaint or an animation tick builds neither a table nor a curve.
local function GradientPreviewColor(pct, health)
    return MSUF.UFBarTextCommon.PreviewHealthGradientColor(health, Clamp01(pct, 0.75))
end
local ResolvePowerColor = MSUF.Require("MSUF_GetResolvedPowerColor", FILE)
local function PowerColor(token)
    local r, g, b = ResolvePowerColor(0, token or "MANA")
    if r then return r, g, b end
    if token == "ENERGY" then return 1, 0.82, 0.10 end
    if token == "RAGE" then return 0.82, 0.12, 0.08 end
    if token == "FOCUS" then return 0.95, 0.45, 0.10 end
    return 0.10, 0.35, 0.95
end
local GetConfiguredFontColor = MSUF.MSUF_GetConfiguredFontColor or MSUF.Optional("MSUF_GetConfiguredFontColor")
local function FontColor()
    if GetConfiguredFontColor then
        local r, g, b = GetConfiguredFontColor()
        if r then return r, g, b end
    end
    local g = M.EnsureDB().general or {}
    return g.fontColorR or 1, g.fontColorG or 1, g.fontColorB or 1
end
local function NormalizeToTInlineColorMode(value)
    if value == "TOT_NAME" or value == "TARGET_NAME" or value == "NPC" or value == "DEFAULT" then return value end
    return "AUTO"
end
local function ReadPowerBarEnabled(conf, key)
    conf = conf or {}
    local bars = M.EnsureDB().bars
    if conf.showPowerBar ~= nil then return conf.showPowerBar ~= false end
    local masterKey = POWER_BAR_MASTER_KEYS[key]
    if masterKey and bars and bars[masterKey] ~= nil then return bars[masterKey] ~= false end
    if conf.showPowerText == nil and conf.showPower ~= nil then return conf.showPower ~= false end
    return POWER_BAR_DEFAULT_ON[key] == true
end
local function CanDetachPowerBarKey(key)
    return CanDetachUnitPowerBar(key) == true
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
local UnitPreviewText = {}
function UnitPreviewText.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
    return PreviewHelpers.PlaceHandleAroundRegions(handle, parent, regions, pad, opts)
end
-- The export is named, in four groups. A named table keeps one table on the
-- stack, where one positional call with every value kept them all there and
-- this main chunk sat at 223 of Lua 5.1's 250 stack slots (the gate holds main
-- chunks to 230).
M.Assign(Model, {
    UNIT_KEYS = UNIT_KEYS, UNIT_SET = UNIT_SET, UNIT_LABELS = UNIT_LABELS, UNIT_DATA = UNIT_DATA,
    TEXT_ANCHORS = TEXT_ANCHORS,
    HP_MODES = HP_MODES, POWER_MODES = POWER_MODES, SEP_ITEMS = SEP_ITEMS, PORTRAIT_MODE_ITEMS = PORTRAIT_MODE_ITEMS,
    PORTRAIT_RENDER_ITEMS = PORTRAIT_RENDER_ITEMS, PortraitClassItems = PortraitClassItems,
    PORTRAIT_SHAPE_ITEMS = PORTRAIT_SHAPE_ITEMS, PORTRAIT_BORDER_ITEMS = PORTRAIT_BORDER_ITEMS,
    PORTRAIT_STYLE_DEFAULTS = PORTRAIT_STYLE_DEFAULTS, CanonKey = CanonKey, EnsureDB = EnsureDB,
    CurrentPanelKey = CurrentPanelKey, UnitDB = UnitDB, SeedTextFromGeneral = SeedTextFromGeneral,
    NormalizeHpMode = NormalizeHpMode,
})
M.Assign(Model, {
    NormalizePowerMode = NormalizePowerMode, TextScopeGet = TextScopeGet, TextScopeHasSlots = TextScopeHasSlots,
    TextScopeSlotGet = TextScopeSlotGet, TOTINLINE_SEP_VALID = TOTINLINE_SEP_VALID,
    TOTINLINE_CUSTOM_SEPARATOR = TOTINLINE_CUSTOM_SEPARATOR,
    TOTINLINE_CUSTOM_SEPARATOR_MAX = TOTINLINE_CUSTOM_SEPARATOR_MAX, TruncateUtf8Chars = TruncateUtf8Chars,
    CleanToTInlineCustomSeparator = CleanToTInlineCustomSeparator, ToTInlineSeparator = ToTInlineSeparator,
    TextScopeSet = TextScopeSet, ForceTextUnit = ForceTextUnit,
    ApplyPanelUnit = ApplyPanelUnit, RefreshAllControls = RefreshAllControls, Label = Label,
    PlaceTopLeft = PlaceTopLeft, SetOptionWidth = SetOptionWidth, AddOptionDivider = AddOptionDivider,
    SetWidgetEnabled = SetWidgetEnabled,
    NormalizePortraitClassStyle = NormalizePortraitClassStyle, EnsureUnitPortraitStyle = EnsureUnitPortraitStyle,
})
M.Assign(Model, {
    PortraitStyleGet = PortraitStyleGet, PortraitStyleSet = PortraitStyleSet, ApplyPortrait = ApplyPortrait,
    NormalizeStatusPreviewId = NormalizeStatusPreviewId, ClassColor = ClassColor, Clamp01 = Clamp01,
    SettingsCache = SettingsCache, PreviewNPCKind = PreviewNPCKind, GradientPreviewColor = GradientPreviewColor, PowerColor = PowerColor, FontColor = FontColor,
    NormalizeToTInlineColorMode = NormalizeToTInlineColorMode,
})
M.Assign(Model, {
    ReadPowerBarEnabled = ReadPowerBarEnabled,
    CanDetachPowerBarKey = CanDetachPowerBarKey, ReadPowerBarHeight = ReadPowerBarHeight,
    ResolveNameAnchor = ResolveNameAnchor, ResolveNameOffsetDelta = ResolveNameOffsetDelta, UnitPreviewText = UnitPreviewText, LiveUnitData = LiveUnitData,
    LiveRaidSubgroup = LiveRaidSubgroup,
})

Model.POWER_TYPES = { MANA = 0, RAGE = 1, FOCUS = 2, ENERGY = 3, RUNIC_POWER = 6 }
