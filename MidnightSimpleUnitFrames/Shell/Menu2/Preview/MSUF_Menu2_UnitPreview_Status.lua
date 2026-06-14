--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua
--- Cold-path status icon preview element helpers.
---
--- Mirrors runtime status-icon anchoring for mock preview frames. It must stay deterministic
--- and should not call live Unit* status APIs.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local SYMBOL_MEDIA = MEDIA .. "Symbols\\"
local PVP_ALLIANCE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon"
local PVP_HORDE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-HordeIcon"
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local MakeFS = PreviewModel.MakeFS
local FontColor = PreviewModel.FontColor
local Status = MSUF.UFPreviewStatus or {}
MSUF.UFPreviewStatus = Status
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
function Status.StatusTextPreviewText(source)
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
    if showDead then return "DEAD" end
    if showGhost then return "GHOST" end
    if showAFK then return "AFK" end
    if showDND then return "DND" end
    return nil
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
    return f
end
function Status.SetIconTexture(icon, spec, conf, g, key, data, runtimeCfg)
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
            local style = (runtimeCfg and runtimeCfg.style) or (conf and conf.leaderIconStyle) or (g and g.leaderIconStyle) or "BLIZZARD"
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
        local path = StatusSymbolTexture((runtimeCfg and runtimeCfg.symbol) or conf.combatStateIndicatorSymbol or g.combatStateIndicatorSymbol)
        if tex and path then
            tex:SetTexture(path)
        elseif tex and tex.SetAtlas then
            tex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitCombatIcon")
        elseif tex then
            tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            if tex.SetTexCoord then tex:SetTexCoord(0.5, 1, 0, 0.5) end
        end
    elseif spec.id == "statusResting" then
        local path = StatusSymbolTexture((runtimeCfg and runtimeCfg.symbol) or conf.restedStateIndicatorSymbol or conf.restingStateIndicatorSymbol or g.restedStateIndicatorSymbol or g.restingStateIndicatorSymbol)
        if tex and path then
            tex:SetTexture(path)
        elseif tex and tex.SetAtlas then
            tex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitRestingIcon")
        elseif tex then
            tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            if tex.SetTexCoord then tex:SetTexCoord(0, 0.5, 0, 0.5) end
        end
    elseif spec.id == "statusIncomingRes" then
        local path = StatusSymbolTexture((runtimeCfg and runtimeCfg.symbol) or conf.incomingResIndicatorSymbol or g.incomingResIndicatorSymbol)
        if tex then tex:SetTexture(path or "Interface\\RaidFrame\\Raid-Icon-Rez") end
    elseif spec.id == "statusPvp" then
        if tex and tex.SetAtlas then
            tex:SetAtlas((key == "target" or key == "focus") and PVP_HORDE_ATLAS or PVP_ALLIANCE_ATLAS)
        elseif tex then
            tex:SetTexture((key == "target" or key == "focus") and "Interface\\TargetingFrame\\UI-PVP-Horde" or "Interface\\TargetingFrame\\UI-PVP-Alliance")
            if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
        end
    elseif spec.id == "level" or spec.id == "statusText" then
        if tex then tex:Hide() end
        if txt then
            txt:SetText(spec.id == "level" and (data.level or "80") or (Status.StatusTextPreviewText(runtimeCfg or g) or ""))
            txt:SetTextColor(FontColor())
            txt:Show()
        end
    else
        if tex then tex:SetTexture("Interface\\Buttons\\WHITE8X8"); tex:SetVertexColor((spec.color and spec.color[1]) or 1, (spec.color and spec.color[2]) or 1, (spec.color and spec.color[3]) or 1, 0.85) end
    end
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
