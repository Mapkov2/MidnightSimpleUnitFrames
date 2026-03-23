local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local Group = ns.Group
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local math_floor = math.floor

local framesCreated = false
local partyFrames, raidFrames, activeFrames = {}, {}, {}
local partyContainer, raidContainer

Group.partyFrames = partyFrames
Group.raidFrames = raidFrames
Group.activeFrames = activeFrames

local function EnsureOverrideTables(scopeDB)
    scopeDB = scopeDB or {}
    scopeDB.overrides = scopeDB.overrides or {}
    scopeDB.overrides.bars = scopeDB.overrides.bars or {}
    scopeDB.overrides.font = scopeDB.overrides.font or {}
    scopeDB.overrides.aura = scopeDB.overrides.aura or {}
    return scopeDB
end

local function NormalizeGroupConf(conf, defaultY)
    conf = conf or {}
    conf.anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", 20, defaultY or -200 }
    conf.anchor[1] = conf.anchor[1] or "TOPLEFT"
    conf.anchor[3] = conf.anchor[3] or conf.anchor[1]

    local anchorX = tonumber(conf.anchor[4])
    local anchorY = tonumber(conf.anchor[5])
    if anchorX == nil then anchorX = 20 end
    if anchorY == nil then anchorY = defaultY or -200 end

    if conf.offsetX == nil then conf.offsetX = anchorX end
    if conf.offsetY == nil then conf.offsetY = anchorY end

    conf.offsetX = tonumber(conf.offsetX) or anchorX
    conf.offsetY = tonumber(conf.offsetY) or anchorY
    conf.anchor[4] = conf.offsetX
    conf.anchor[5] = conf.offsetY
    return conf
end

local function GetGroupDB()
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
    local db = _G.MSUF_DB or {}
    db.group = db.group or {}
    db.group.shared = db.group.shared or {}
    db.group.shared.bars = db.group.shared.bars or {}
    db.group.shared.font = db.group.shared.font or {}
    db.group.shared.aura = db.group.shared.aura or {}
    db.group.shared.aura.designer = db.group.shared.aura.designer or { text = "", groups = {} }
    db.group.party = EnsureOverrideTables(NormalizeGroupConf(db.group.party, -200))
    db.group.raid = EnsureOverrideTables(NormalizeGroupConf(db.group.raid, -400))
    return db.group
end

local function GetScopeForUnit(unit)
    if type(unit) ~= "string" then return "party" end
    if string.sub(unit, 1, 4) == "raid" then return "raid" end
    return "party"
end

_G.MSUF_Group_NormalizeConf = NormalizeGroupConf
_G.MSUF_Group_GetOffsets = function(conf, defaultY)
    conf = NormalizeGroupConf(conf, defaultY)
    return tonumber(conf.offsetX) or 0, tonumber(conf.offsetY) or 0
end
_G.MSUF_Group_SetOffsets = function(conf, x, y, defaultY)
    conf = NormalizeGroupConf(conf, defaultY)
    conf.offsetX = tonumber(x) or 0
    conf.offsetY = tonumber(y) or 0
    conf.anchor[4] = conf.offsetX
    conf.anchor[5] = conf.offsetY
    return conf
end
_G.MSUF_Group_GetScopeForUnit = GetScopeForUnit
_G.MSUF_Group_GetSetting = function(scope, category, key, fallback)
    local groupDB = GetGroupDB()
    local shared = groupDB.shared or {}
    local scopeDB = groupDB[scope] or {}
    local overrides = scopeDB.overrides and scopeDB.overrides[category]
    if overrides and overrides[key] ~= nil then
        return overrides[key]
    end
    local sharedCategory = shared[category]
    if sharedCategory and sharedCategory[key] ~= nil then
        return sharedCategory[key]
    end
    if shared[key] ~= nil then
        return shared[key]
    end
    return fallback
end

local function UpdateTargetHighlight(frame)
    local unit = frame and frame._assignedUnit
    if not frame or not frame.highlightBorder then return end
    frame.highlightBorder:SetShown(unit and UnitExists(unit) and UnitIsUnit(unit, "target") or false)
end

local function CreateIndicatorBorder(frame, key, inset, r, g, b)
    local border = ns.UF.MakeFrame(frame, key, "Frame", "self", (BackdropTemplateMixin and "BackdropTemplate") or nil)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, -inset)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    border:SetBackdropBorderColor(r or 1, g or 1, b or 1, 0.95)
    border:Hide()
    return border
end

local function CreateOverlayBar(parent, baseBar, frameLevel, r, g, b, a, reverseFill)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    _G.MSUF_SetBarValue(bar, 0, false)
    bar:SetFrameLevel(frameLevel or (baseBar:GetFrameLevel() + 1))
    bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 0.6)
    bar:SetAllPoints(baseBar)
    if bar.SetReverseFill then
        bar:SetReverseFill(reverseFill and true or false)
    end
    bar:Hide()
    return bar
end

local function CreateGroupFrame(name)
    local f = CreateFrame("Button", name, UIParent, "BackdropTemplate,SecureUnitButtonTemplate,PingableUnitFrameTemplate")
    f:SetClampedToScreen(true)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:EnableMouse(true)
    f:SetScript("OnEnter", ns.UF.Unitframe_OnEnter)
    f:SetScript("OnLeave", ns.UF.Unitframe_OnLeave)

    local bg = ns.UF.MakeTex(f, "bg", "self", "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)

    local hpBar = ns.UF.MakeBar(f, "hpBar", "self")
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    hpBar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
    hpBar:SetMinMaxValues(0, 1)
    _G.MSUF_SetBarValue(hpBar, 1, false)
    hpBar:SetFrameLevel(f:GetFrameLevel() + 1)

    local hpBG = ns.UF.MakeTex(f, "hpBarBG", "hpBar", "BACKGROUND")
    hpBG:SetAllPoints(hpBar)
    hpBG:SetTexture("Interface\\Buttons\\WHITE8x8")
    hpBG:SetVertexColor(0, 0, 0, 0.35)

    local powerBar = ns.UF.MakeBar(f, "powerBar", "self")
    powerBar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
    powerBar:SetMinMaxValues(0, 1)
    _G.MSUF_SetBarValue(powerBar, 0, false)
    powerBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    powerBar:Hide()

    f.absorbBar = CreateOverlayBar(f, hpBar, hpBar:GetFrameLevel() + 2, 0.3, 0.8, 1.0, 0.55, true)
    f.healAbsorbBar = CreateOverlayBar(f, hpBar, hpBar:GetFrameLevel() + 3, 0.95, 0.2, 0.6, 0.55, false)
    f.healPredictionBar = CreateOverlayBar(f, hpBar, hpBar:GetFrameLevel() + 4, 0.1, 1.0, 0.35, 0.35, true)

    local textFrame = ns.UF.MakeFrame(f, "textFrame", "Frame", "self")
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 3)

    local fontPath = ns.Castbars and ns.Castbars._GetFontPath and ns.Castbars._GetFontPath() or STANDARD_TEXT_FONT
    local flags = ns.Castbars and ns.Castbars._GetFontFlags and ns.Castbars._GetFontFlags() or ""
    local fr, fg, fb = 1, 1, 1
    if type(ns.MSUF_GetConfiguredFontColor) == "function" then
        local r, g, b = ns.MSUF_GetConfiguredFontColor()
        fr, fg, fb = r or 1, g or 1, b or 1
    end

    local nameText = ns.UF.MakeFont(f, "nameText", "textFrame", "GameFontHighlight", "OVERLAY")
    nameText:SetPoint("LEFT", f, "LEFT", 4, 0)
    nameText:SetPoint("RIGHT", f, "RIGHT", -42, 0)
    nameText:SetJustifyH("LEFT")
    if nameText.SetFont then nameText:SetFont(fontPath, 11, flags) end
    nameText:SetTextColor(fr, fg, fb, 1)

    local stateText = ns.UF.MakeFont(f, "stateText", "textFrame", "GameFontHighlightSmall", "OVERLAY")
    stateText:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    stateText:SetJustifyH("RIGHT")
    if stateText.SetFont then stateText:SetFont(fontPath, 10, flags) end
    stateText:SetTextColor(1, 0.2, 0.2, 1)

    local hpText = ns.UF.MakeFont(f, "hpText", "textFrame", "GameFontHighlightSmall", "OVERLAY")
    hpText:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    hpText:SetJustifyH("RIGHT")
    if hpText.SetFont then hpText:SetFont(fontPath, 10, flags) end
    hpText:SetTextColor(fr, fg, fb, 1)
    hpText:Hide()

    local afkText = ns.UF.MakeFont(f, "afkText", "textFrame", "GameFontHighlightSmall", "OVERLAY")
    afkText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    if afkText.SetFont then afkText:SetFont(fontPath, 9, flags) end
    afkText:SetTextColor(1, 0.82, 0, 1)
    afkText:Hide()

    local roleIcon = ns.UF.MakeTex(f, "roleIcon", "textFrame", "OVERLAY", 6)
    roleIcon:SetSize(12, 12)
    roleIcon:SetPoint("LEFT", f, "LEFT", 2, 0)
    roleIcon:Hide()

    local readyCheckIcon = ns.UF.MakeTex(f, "readyCheckIcon", "textFrame", "OVERLAY", 6)
    readyCheckIcon:SetSize(14, 14)
    readyCheckIcon:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    readyCheckIcon:Hide()

    local resIcon = ns.UF.MakeTex(f, "resIcon", "textFrame", "OVERLAY", 6)
    resIcon:SetSize(12, 12)
    resIcon:SetPoint("RIGHT", readyCheckIcon, "LEFT", -2, 0)
    resIcon:Hide()

    local summonIcon = ns.UF.MakeTex(f, "summonIcon", "textFrame", "OVERLAY", 6)
    summonIcon:SetSize(12, 12)
    summonIcon:SetPoint("RIGHT", resIcon, "LEFT", -2, 0)
    summonIcon:Hide()

    local raidMarkerIcon = ns.UF.MakeTex(f, "raidMarkerIcon", "textFrame", "OVERLAY", 6)
    raidMarkerIcon:SetSize(14, 14)
    raidMarkerIcon:SetPoint("TOP", f, "TOP", 0, 6)
    raidMarkerIcon:Hide()

    local phasedIcon = ns.UF.MakeTex(f, "phasedIcon", "textFrame", "OVERLAY", 6)
    phasedIcon:SetSize(12, 12)
    phasedIcon:SetPoint("LEFT", roleIcon, "RIGHT", 2, 0)
    phasedIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    phasedIcon:Hide()

    local buffContainer = ns.UF.MakeFrame(f, "buffContainer", "Frame", "self")
    buffContainer:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
    buffContainer:SetSize(64, 18)
    f.buffIcons = {}

    local debuffContainer = ns.UF.MakeFrame(f, "debuffContainer", "Frame", "self")
    debuffContainer:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
    debuffContainer:SetSize(64, 18)
    f.debuffIcons = {}

    local privateAuraContainer = ns.UF.MakeFrame(f, "privateAuraContainer", "Frame", "self")
    privateAuraContainer:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
    privateAuraContainer:SetSize(64, 18)

    CreateIndicatorBorder(f, "highlightBorder", 1, 1, 1, 1)
    CreateIndicatorBorder(f, "threatBorder", 2, 1, 0.65, 0)
    CreateIndicatorBorder(f, "selfBorder", 3, 0.2, 1, 0.2)

    if ClickCastFrames then
        ClickCastFrames[f] = true
    end

    f.UpdateTargetHighlight = UpdateTargetHighlight
    return f
end

local function EnsureContainers()
    if partyContainer and raidContainer then return end
    partyContainer = CreateFrame("Frame", "MSUF_GroupPartyContainer", UIParent)
    raidContainer = CreateFrame("Frame", "MSUF_GroupRaidContainer", UIParent)
    Group.partyContainer = partyContainer
    Group.raidContainer = raidContainer
end

local function ApplyContainerAnchor(container, conf)
    conf = NormalizeGroupConf(conf)
    local anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", conf.offsetX or 20, conf.offsetY or -200 }
    local point, rel, relPoint = anchor[1], anchor[2], anchor[3]
    local x = tonumber(conf.offsetX)
    local y = tonumber(conf.offsetY)
    if x == nil then x = tonumber(anchor[4]) or 0 end
    if y == nil then y = tonumber(anchor[5]) or 0 end
    anchor[4], anchor[5] = x, y
    container:ClearAllPoints()
    container:SetPoint(point or "TOPLEFT", rel or UIParent, relPoint or point or "TOPLEFT", x or 0, y or 0)
end

local function ApplyFrameGeometry(frame, conf, shared)
    local scope = frame._groupScope or "party"
    local width = conf.width or 90
    local height = conf.height or 36
    local powerMode = _G.MSUF_Group_GetSetting(scope, "bars", "showPowerBar", shared.showPowerBar or "HEALER")
    local powerHeight = _G.MSUF_Group_GetSetting(scope, "bars", "powerBarHeight", shared.powerBarHeight or 3)
    local nameSize = _G.MSUF_Group_GetSetting(scope, "font", "nameSize", 11)
    local hpSize = _G.MSUF_Group_GetSetting(scope, "font", "hpSize", 10)

    frame:SetSize(width, height)
    if frame.nameText and frame.nameText.SetFont then
        local fontPath = ns.Castbars and ns.Castbars._GetFontPath and ns.Castbars._GetFontPath() or STANDARD_TEXT_FONT
        local flags = ns.Castbars and ns.Castbars._GetFontFlags and ns.Castbars._GetFontFlags() or ""
        frame.nameText:SetFont(fontPath, nameSize, flags)
    end
    if frame.hpText and frame.hpText.SetFont then
        local fontPath = ns.Castbars and ns.Castbars._GetFontPath and ns.Castbars._GetFontPath() or STANDARD_TEXT_FONT
        local flags = ns.Castbars and ns.Castbars._GetFontFlags and ns.Castbars._GetFontFlags() or ""
        frame.hpText:SetFont(fontPath, hpSize, flags)
    end
    frame.hpBar:ClearAllPoints()
    frame.hpBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.hpBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

    if powerMode ~= "NONE" then
        frame.hpBar:ClearAllPoints()
        frame.hpBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        frame.hpBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        frame.hpBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, powerHeight + 1)
        frame.powerBar:ClearAllPoints()
        frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        frame.powerBar:SetHeight(powerHeight)
    else
        frame.powerBar:Hide()
    end

    if frame.absorbBar then
        frame.absorbBar:ClearAllPoints()
        frame.absorbBar:SetAllPoints(frame.hpBar)
    end
    if frame.healAbsorbBar then
        frame.healAbsorbBar:ClearAllPoints()
        frame.healAbsorbBar:SetAllPoints(frame.hpBar)
    end
    if frame.healPredictionBar then
        frame.healPredictionBar:ClearAllPoints()
        frame.healPredictionBar:SetAllPoints(frame.hpBar)
    end
end

local function SetContainerBounds(container, used, conf)
    if not container then return end
    local width = conf.width or 90
    local height = conf.height or 36
    local spacing = conf.spacing or 2
    local grow = conf.growthDirection or "DOWN"
    local wrap = math.max(1, tonumber(conf.wrapAfter) or 5)

    if used == nil or used < 1 then
        container:SetSize(width, height)
        return
    end

    local cols, rows
    if grow == "LEFT" or grow == "RIGHT" then
        cols = math.min(used, wrap)
        rows = math.ceil(used / wrap)
    else
        rows = math.min(used, wrap)
        cols = math.ceil(used / wrap)
    end

    local totalWidth = (cols * width) + (math.max(0, cols - 1) * spacing)
    local totalHeight = (rows * height) + (math.max(0, rows - 1) * spacing)
    container:SetSize(totalWidth, totalHeight)
end

local function LayoutPool(container, pool, used, conf)
    local width = conf.width or 90
    local height = conf.height or 36
    local spacing = conf.spacing or 2
    local grow = conf.growthDirection or "DOWN"
    local wrap = conf.wrapAfter or 5

    SetContainerBounds(container, used, conf)

    local stepX, stepY, wrapX, wrapY = 0, 0, 0, 0
    if grow == "DOWN" then stepY = -(height + spacing); wrapX = width + spacing end
    if grow == "UP" then stepY = height + spacing; wrapX = width + spacing end
    if grow == "RIGHT" then stepX = width + spacing; wrapY = -(height + spacing) end
    if grow == "LEFT" then stepX = -(width + spacing); wrapY = -(height + spacing) end

    for i = 1, #pool do
        local frame = pool[i]
        if i <= used then
            local col = (i - 1) % wrap
            local row = math_floor((i - 1) / wrap)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", container, "TOPLEFT", col * stepX + row * wrapX, col * stepY + row * wrapY)
            frame:Show()
        else
            frame:Hide()
        end
    end
end

local function AssignUnit(frame, unit)
    if frame._assignedUnit == unit then return end
    Group.DeferIfCombat(function()
        if frame._assignedUnit then
            UnregisterUnitWatch(frame)
            activeFrames[frame._assignedUnit] = nil
        end
        frame._groupScope = unit and GetScopeForUnit(unit) or frame._groupScope
        frame._assignedUnit = unit
        frame:SetAttribute("unit", unit)
        if unit then
            RegisterUnitWatch(frame)
            activeFrames[unit] = frame
        else
            frame:Hide()
        end
        if type(_G.MSUF_Group_OnAssignedUnit) == "function" then
            _G.MSUF_Group_OnAssignedUnit(frame, unit)
        end
    end)
end

local function ReleaseUnit(frame)
    AssignUnit(frame, nil)
end

local function EnsurePools()
    if framesCreated then return end
    EnsureContainers()
    for i = 1, 4 do
        partyFrames[i] = CreateGroupFrame("MSUF_GroupParty" .. i)
        partyFrames[i]:SetParent(partyContainer)
    end
    for i = 1, 40 do
        raidFrames[i] = CreateGroupFrame("MSUF_GroupRaid" .. i)
        raidFrames[i]:SetParent(raidContainer)
    end
    framesCreated = true
end

function _G.MSUF_EnsureGroupFrames()
    local groupDB = GetGroupDB()
    if groupDB.enabled == false then return end
    EnsurePools()
end

function _G.MSUF_HideAllGroupFrames()
    for i = 1, #partyFrames do ReleaseUnit(partyFrames[i]) end
    for i = 1, #raidFrames do ReleaseUnit(raidFrames[i]) end
    if partyContainer then partyContainer:Hide() end
    if raidContainer then raidContainer:Hide() end
end

function _G.MSUF_LayoutGroupFrames()
    if not framesCreated then return end
    local groupDB = GetGroupDB()
    if groupDB.enabled == false then
        _G.MSUF_HideAllGroupFrames()
        return
    end

    local shared = groupDB.shared or {}
    local partyConf = groupDB.party or {}
    local raidConf = groupDB.raid or {}

    ApplyContainerAnchor(partyContainer, partyConf)
    ApplyContainerAnchor(raidContainer, raidConf)

    for i = 1, #partyFrames do
        ApplyFrameGeometry(partyFrames[i], partyConf, shared)
    end
    for i = 1, #raidFrames do
        ApplyFrameGeometry(raidFrames[i], raidConf, shared)
    end

    local roster = Group.roster or {}
    local count = roster.count or 0
    if roster.type == "raid" then
        partyContainer:Hide()
        raidContainer:Show()
        LayoutPool(raidContainer, raidFrames, count, raidConf)
    elseif roster.type == "party" then
        raidContainer:Hide()
        partyContainer:Show()
        LayoutPool(partyContainer, partyFrames, count, partyConf)
    else
        partyContainer:Hide()
        raidContainer:Hide()
    end
end

local function OnRosterChanged(roster)
    if not framesCreated then return end
    local groupDB = GetGroupDB()
    if groupDB.enabled == false then
        _G.MSUF_HideAllGroupFrames()
        return
    end

    if roster.type == "raid" then
        for i = 1, 40 do
            local unit = roster.units[i]
            if unit then AssignUnit(raidFrames[i], unit) else ReleaseUnit(raidFrames[i]) end
        end
        for i = 1, 4 do ReleaseUnit(partyFrames[i]) end
    elseif roster.type == "party" then
        for i = 1, 4 do
            local unit = roster.units[i]
            if unit then AssignUnit(partyFrames[i], unit) else ReleaseUnit(partyFrames[i]) end
        end
        for i = 1, 40 do ReleaseUnit(raidFrames[i]) end
    else
        _G.MSUF_HideAllGroupFrames()
    end

    _G.MSUF_LayoutGroupFrames()
    if type(_G.MSUF_Group_RefreshAll) == "function" then
        _G.MSUF_Group_RefreshAll()
    end
end

Group.OnRosterChanged = OnRosterChanged
