--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua
--- Cold-path status icon preview element helpers.
---
--- Mirrors runtime status-icon anchoring for mock preview frames. It must stay deterministic
--- and should not call live Unit* status APIs.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local SYMBOL_MEDIA = MEDIA .. "Symbols\\"
local VALID_STATE_SYMBOLS = {
    weapon_axes_crossed = true, weapon_bows_crossed = true,
    weapon_crossbows_crossed = true, weapon_daggers_crossed = true,
    weapon_fishing_poles_crossed = true, weapon_fist_crossed = true,
    weapon_guns_crossed = true, weapon_maces_crossed = true,
    weapon_polearms_crossed = true, weapon_shuriken = true,
    weapon_staves_crossed = true, weapon_swords_crossed = true,
    weapon_thrown_crossed = true, weapon_wands_crossed = true,
    weapon_warglaives_crossed = true,
    rested_moonzzz = true, rested_moonzzzz = true,
    rested_sleep_zzzz = true, rested_zzz_compact = true,
    rested_zzz_diag = true, rested_zzz_stack = true,
    resurrection_ankh = true, resurrection_cross = true,
    resurrection_soul = true, resurrection_wings = true,
}
local PVP_ALLIANCE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon"
local PVP_HORDE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-HordeIcon"
local RESTING_ANIMATED_SYMBOL = "rested_blizzard_animated"
local RestingFlipbook = MSUF.UFRestingFlipbook or {}
local ApplyRestingFlipbook = RestingFlipbook.Apply
local StopRestingFlipbook = RestingFlipbook.Stop
local function StatusIconOnHide(self)
    if StopRestingFlipbook then StopRestingFlipbook(self.tex) end
end
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local MakeFS = PreviewModel.MakeFS
local FontColor = PreviewModel.FontColor
local Status = MSUF.UFPreviewStatus or {}
MSUF.UFPreviewStatus = Status
-- stance renders through the identity-text preview path: name-font sizing and
-- a plain text glyph, without joining the Dead/Ghost status-text state family.
local IDENTITY_TEXT_IDS = { level = true, bossNumber = true, raceText = true, classText = true, stance = true }
local STATUS_TEXT_STATE_IDS = {
    statusText = "DEAD",
    statusGhostText = "GHOST",
    statusAFKText = "AFK",
    -- Value doubles as the preview glyph; the AFK timer shows a sample duration.
    statusAFKTimer = "5m",
    statusDNDText = "DND",
}
local function AnchorLikeRuntime(region, anchor, x, y, frame, nameText)
    -- Runtime supports name-relative anchors; preview duplicates that math so the editor shows
    -- the same visual result without depending on a real unitframe.
    if not (region and frame) then return end
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    anchor = tostring(anchor or "TOPLEFT")
    local target, point, relPoint = frame, anchor, anchor
    if anchor == "NAMERIGHT" then
        if nameText then
            target, point, relPoint = nameText, "LEFT", "RIGHT"
        else
            point, relPoint = "RIGHT", "RIGHT"
        end
    elseif anchor == "NAMELEFT" then
        if nameText then
            target, point, relPoint = nameText, "RIGHT", "LEFT"
        else
            point, relPoint = "LEFT", "LEFT"
        end
    end
    region:ClearAllPoints()
    region:SetPoint(point, target, relPoint, x, y)
end
function Status.PositionFromAnchor(frame, anchor, x, y, target)
    AnchorLikeRuntime(frame, anchor, x, y, target)
end
function Status.PositionRuntimeLayoutIconPreview(frame, anchor, x, y, target, allowCenter)
    AnchorLikeRuntime(frame, anchor, x, y, target)
end
function Status.PositionStatusCornerPreview(frame, anchor, x, y, target, pad)
    AnchorLikeRuntime(frame, anchor, x, y, target)
end
function Status.PositionSameAnchorPreview(frame, anchor, x, y, target)
    AnchorLikeRuntime(frame, anchor, x, y, target)
end
function Status.PositionLevelPreview(frame, anchor, x, y, mock, gap)
    if not (frame and mock) then return end
    AnchorLikeRuntime(frame, anchor or "NAMERIGHT", x, y, mock, mock.nameText)
end
local function StatusSymbolTexture(symbolKey)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then return nil end
    if not VALID_STATE_SYMBOLS[symbolKey] then return nil end
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
local function EffectiveIconPackStyle(spec, conf, g, runtimeCfg)
    if not (spec and (spec.id == "leader" or spec.id == "assist")) then return nil end
    local style = runtimeCfg and runtimeCfg.style
    if (type(style) ~= "string" or style == "" or style == "DEFAULT") and spec and spec.iconStyle then
        style = (conf and conf[spec.iconStyle]) or (g and g[spec.iconStyle]) or spec.defaultIconStyle
    end
    if type(style) ~= "string" or style == "" or style == "DEFAULT" or style == "BLIZZARD" then return nil end
    return style
end
local function ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, iconType, variant)
    if not tex then return false end
    local customIcon = runtimeCfg and runtimeCfg.customIcon
    if (type(customIcon) ~= "string" or customIcon == "") and spec and spec.customIcon then
        customIcon = (conf and conf[spec.customIcon]) or (g and g[spec.customIcon])
    end
    if type(customIcon) == "string" and customIcon ~= "" then
        tex:SetTexture(customIcon)
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
        return true
    end
    local style = EffectiveIconPackStyle(spec, conf, g, runtimeCfg)
    if not style then return false end
    local resolver = _G.MSUF_GetStatusIconTexture
    if type(resolver) ~= "function" then return false end
    local useMidnight = runtimeCfg and runtimeCfg.useMidnight == true
    if not useMidnight then useMidnight = g and g.statusIconsUseMidnightStyle == true end
    local path, l, r, t, b = resolver(style, iconType, variant, useMidnight)
    if type(path) ~= "string" or path == "" then return false end
    tex:SetTexture(path)
    if tex.SetTexCoord then tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1) end
    return true
end
function Status.StatusTextPreviewText(source, preferredText)
    local cfg
    if type(source) == "table" and (source.showDead ~= nil or source.showGhost ~= nil or source.showAFK ~= nil or source.showDND ~= nil) then
        cfg = source
    else
        cfg = type(source) == "table" and type(source.statusIndicators) == "table" and source.statusIndicators or nil
    end
    local showDead = cfg == nil or cfg.showDead ~= false
    local showGhost = cfg == nil or cfg.showGhost ~= false
    local showAFK = cfg ~= nil and cfg.showAFK == true
    local showDND = cfg ~= nil and cfg.showDND == true
    if type(preferredText) ~= "string" then preferredText = nil end
    if preferredText == "OFFLINE" and showDead then return "OFFLINE" end
    if preferredText == "DEAD" and showDead then return "DEAD" end
    if preferredText == "GHOST" and showGhost then return "GHOST" end
    if preferredText == "AFK" and showAFK then return "AFK" end
    if preferredText == "DND" and showDND then return "DND" end
    if showDead then return "DEAD" end
    if showGhost then return "GHOST" end
    if showAFK then return "AFK" end
    if showDND then return "DND" end
    return nil
end
function Status.IsIdentityText(spec)
    local id = type(spec) == "table" and spec.id or spec
    return IDENTITY_TEXT_IDS[id] == true
end
function Status.IsTextIndicator(spec)
    local id = type(spec) == "table" and spec.id or spec
    return STATUS_TEXT_STATE_IDS[id] ~= nil or IDENTITY_TEXT_IDS[id] == true
end
function Status.IsStatusTextState(spec)
    local id = type(spec) == "table" and spec.id or spec
    return STATUS_TEXT_STATE_IDS[id] ~= nil
end
function Status.IdentityPreviewText(spec, data)
    local id = type(spec) == "table" and spec.id or spec
    data = data or {}
    if id == "level" then return tostring(data.level or "80") end
    if id == "bossNumber" then return "1" end
    if id == "raceText" then return data.race or "Tauren" end
    if id == "classText" then return data.className or data.class or "Warrior" end
    if id == "stance" then
        -- Show the player's real stance when one is active so the preview
        -- matches the live frame; classes without a stance bar get the label.
        local ns = _G.MSUF_NS
        local stance = ns and ns.UFStance
        local name = stance and stance.Resolve and stance.Resolve() or nil
        return name or "Stance"
    end
    return ""
end
function Status.CreateIcon(parent, color, text)
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
    if StopRestingFlipbook then f:SetScript("OnHide", StatusIconOnHide) end
    return f
end
local function ElitePreviewState(key, data)
    local classification = data and data.classification
    if classification == "worldboss" then return "BOSS" end
    if classification == "rareelite" then return "RAREELITE" end
    if classification == "rare" then return "RARE" end
    if classification == "elite" then return "ELITE" end
    return key == "boss" and "BOSS" or "ELITE"
end
local function ElitePreviewAtlas(state)
    if state == "RARE" then return "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star" end
    if state == "RAREELITE" then return "nameplates-icon-elite-silver" end
    return "nameplates-icon-elite-gold"
end
function Status.SetIconTexture(icon, spec, conf, g, key, data, runtimeCfg, statusPreviewText)
    if not icon or not spec then return end
    local tex, txt = icon.tex, icon.txt
    if StopRestingFlipbook then StopRestingFlipbook(tex, true) end
    if tex then
        tex:Show()
        tex:SetVertexColor(1, 1, 1, 1)
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    end
    if txt then txt:Hide() end
    if spec.id == "raidmarker" then
        if tex then
            if not ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, "raidMarker", 8) then
                tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                if SetRaidTargetIconTexture then SetRaidTargetIconTexture(tex, 8) end
            end
        end
    elseif spec.id == "leader" or spec.id == "assist" then
        if tex then
            local isAssist = spec.id == "assist"
            local path = isAssist and "Interface\\GroupFrame\\UI-Group-AssistantIcon" or "Interface\\GroupFrame\\UI-Group-LeaderIcon"
            local customKey = isAssist and "assistIconCustomIcon" or "leaderIconCustomIcon"
            local customIcon = (runtimeCfg and runtimeCfg.customIcon) or (conf and conf[customKey]) or (g and g[customKey])
            if type(customIcon) == "string" and customIcon ~= "" then
                tex:SetTexture(customIcon)
                if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
                return
            end
            tex:SetTexture(path)
        end
    elseif spec.id == "elite" then
        local state = ElitePreviewState(key, data)
        if tex and ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, "elite", state) then
            -- Custom texture applied above.
        elseif tex and tex.SetAtlas then
            tex:SetAtlas(ElitePreviewAtlas(state))
        elseif tex then
            tex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        end
    elseif spec.id == "statusCombat" then
        local path = StatusSymbolTexture((runtimeCfg and runtimeCfg.symbol) or conf.combatStateIndicatorSymbol or g.combatStateIndicatorSymbol)
        if tex and path then
            tex:SetTexture(path)
        elseif tex and ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, "combat", "combat") then
            -- Custom texture applied above.
        elseif tex and tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo("UI-HUD-UnitFrame-Player-PortraitCombatIcon") then
            tex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitCombatIcon")
        elseif tex then
            tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            if tex.SetTexCoord then tex:SetTexCoord(0.5, 1, 0, 0.5) end
        end
    elseif spec.id == "statusResting" then
        local symbol = (runtimeCfg and runtimeCfg.symbol) or conf.restedStateIndicatorSymbol or conf.restingStateIndicatorSymbol or g.restedStateIndicatorSymbol or g.restingStateIndicatorSymbol
        local path = StatusSymbolTexture(symbol)
        if tex and symbol == RESTING_ANIMATED_SYMBOL and ApplyRestingFlipbook and ApplyRestingFlipbook(tex, true) then
            -- Blizzard's native 42-frame rested loop applied above.
        elseif tex and path then
            tex:SetTexture(path)
        elseif tex and ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, "resting", "resting") then
            -- Custom texture applied above.
        elseif tex then
            tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            if tex.SetTexCoord then tex:SetTexCoord(0, 0.5, 0, 0.5) end
        end
    elseif spec.id == "statusIncomingRes" then
        local path = StatusSymbolTexture((runtimeCfg and runtimeCfg.symbol) or conf.incomingResIndicatorSymbol or g.incomingResIndicatorSymbol)
        if tex and path then
            tex:SetTexture(path)
        elseif tex and ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, "incomingRes", "resurrect") then
            -- Custom texture applied above.
        elseif tex then
            tex:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        end
    elseif spec.id == "statusPvp" then
        local variant = (key == "target" or key == "focus") and "Horde" or "Alliance"
        if tex and ApplyStatusIconPackPreview(tex, spec, conf, g, runtimeCfg, "pvp", variant) then
            -- Custom texture applied above.
        elseif tex and tex.SetAtlas then
            tex:SetAtlas((key == "target" or key == "focus") and PVP_HORDE_ATLAS or PVP_ALLIANCE_ATLAS)
        elseif tex then
            tex:SetTexture((key == "target" or key == "focus") and "Interface\\TargetingFrame\\UI-PVP-Horde" or "Interface\\TargetingFrame\\UI-PVP-Alliance")
            if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
        end
    elseif Status.IsTextIndicator(spec) then
        if tex then tex:Hide() end
        if txt then
            txt:SetText(Status.IsIdentityText(spec) and Status.IdentityPreviewText(spec, data)
                or STATUS_TEXT_STATE_IDS[spec.id]
                or statusPreviewText or Status.StatusTextPreviewText(runtimeCfg or g) or "")
            txt:SetTextColor(Status.TextIndicatorColor(spec, conf, g))
            txt:Show()
        end
    else
        if tex then tex:SetTexture("Interface\\Buttons\\WHITE8X8"); tex:SetVertexColor((spec.color and spec.color[1]) or 1, (spec.color and spec.color[2]) or 1, (spec.color and spec.color[3]) or 1, 0.85) end
    end
end
--- A text indicator may carry its own color, and the preview has to show it or
--- the swatch and the live frame disagree. The DB prefix is derived from the
--- spec's size key ("levelIndicatorSize" -> "levelIndicator") so this cannot
--- drift from the engine's PrefixedStatusDef naming. No stored triple means the
--- indicator is still following the frame font color.
function Status.TextIndicatorColor(spec, conf, g)
    local sizeKey = spec and spec.size
    local prefix = type(sizeKey) == "string" and sizeKey:match("^(.*)Size$") or nil
    if prefix then
        local function Component(suffix)
            local value = conf and conf[prefix .. suffix]
            if value == nil then value = g and g[prefix .. suffix] end
            return tonumber(value)
        end
        local r, green, b = Component("ColorR"), Component("ColorG"), Component("ColorB")
        if r and green and b then return r, green, b end
    end
    return FontColor()
end
function Status.ResolveAnchor(spec, conf, g)
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
