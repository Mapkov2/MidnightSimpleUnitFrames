--- Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua
--- Cold-path status icon preview element helpers.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local SYMBOL_MEDIA = MEDIA .. "Symbols\\"

local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local MakeFS = PreviewModel.MakeFS
local FontColor = PreviewModel.FontColor

local Status = MSUF.UFPreviewStatus or {}
MSUF.UFPreviewStatus = Status

function Status.PositionFromAnchor(frame, anchor, x, y, target, size)
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

function Status.PositionRuntimeLayoutIconPreview(frame, anchor, x, y, target, allowCenter)
    if not frame or not target then return end
    frame:ClearAllPoints()
    local point, relPoint = ResolveRuntimeIconLayoutAnchor(tostring(anchor or "TOPLEFT"), allowCenter)
    frame:SetPoint(point, target, relPoint, tonumber(x) or 0, tonumber(y) or 0)
end

function Status.PositionStatusCornerPreview(frame, anchor, x, y, target, pad)
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
    elseif anchor == "TOP" then
        frame:SetPoint("TOP", target, "TOP", x, -pad + y)
    elseif anchor == "BOTTOM" then
        frame:SetPoint("BOTTOM", target, "BOTTOM", x, pad + y)
    elseif anchor == "LEFT" then
        frame:SetPoint("LEFT", target, "LEFT", pad + x, y)
    elseif anchor == "RIGHT" then
        frame:SetPoint("RIGHT", target, "RIGHT", -pad + x, y)
    else
        frame:SetPoint("TOPLEFT", target, "TOPLEFT", pad + x, -pad + y)
    end
end

function Status.PositionSameAnchorPreview(frame, anchor, x, y, target)
    if not frame or not target then return end
    frame:ClearAllPoints()
    anchor = tostring(anchor or "CENTER")
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    frame:SetPoint(anchor, target, anchor, x, y)
end

function Status.PositionLevelPreview(frame, anchor, x, y, mock, gap)
    if not (frame and mock) then return end
    anchor = tostring(anchor or "NAMERIGHT")
    gap = tonumber(gap) or 6
    local nameVisible = mock.nameText and (not mock.nameText.IsShown or mock.nameText:IsShown())
    if anchor == "NAMELEFT" and nameVisible then
        frame:SetPoint("RIGHT", mock.nameText, "LEFT", -gap + x, y)
    elseif anchor == "NAMERIGHT" and nameVisible then
        frame:SetPoint("LEFT", mock.nameText, "RIGHT", gap + x, y)
    elseif anchor == "NAMELEFT" or anchor == "NAMERIGHT" then
        Status.PositionSameAnchorPreview(frame, "CENTER", x, y, mock.textFrame or mock)
    else
        Status.PositionSameAnchorPreview(frame, anchor, x, y, mock.textFrame or mock)
    end
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

function Status.SetIconTexture(icon, spec, conf, g, key, data)
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
