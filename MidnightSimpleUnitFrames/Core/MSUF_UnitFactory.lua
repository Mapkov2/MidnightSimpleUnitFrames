local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

local CreateFrame = CreateFrame
local unpack = unpack or table.unpack
local floor = math.floor
local F = (ns.Cache and ns.Cache.F) or {}

local function ConfBool(conf, field, default)
    local v = conf and conf[field]
    if v == nil then return default and true or false end
    return v and true or false
end

local function Clamp01(v)
    v = tonumber(v)
    if not v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function GetOverlayColor(defR, defG, defB, defA, keyR, keyG, keyB)
    local r, g, b, a = defR, defG, defB, defA
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local ar, ag, ab = gen[keyR], gen[keyG], gen[keyB]
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            r = Clamp01(ar)
            g = Clamp01(ag)
            b = Clamp01(ab)
        end
    end
    return r, g, b, a
end

local function GetAbsorbOverlayColor()
    return GetOverlayColor(0.8, 0.9, 1.0, 0.6, "absorbBarColorR", "absorbBarColorG", "absorbBarColorB")
end

local function GetHealAbsorbOverlayColor()
    return GetOverlayColor(1.0, 0.4, 0.4, 0.7, "healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB")
end

local function CreateOverlayStatusBar(parent, baseBar, frameLevel, r, g, b, a, reverseFill)
    if not (parent and baseBar) then return nil end
    local bar = (F.CreateFrame or CreateFrame)("StatusBar", nil, parent)
    bar:SetAllPoints(baseBar)
    bar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    _G.MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    if frameLevel then bar:SetFrameLevel(frameLevel) end
    if r and g and b then bar:SetStatusBarColor(r, g, b, a or 1) end
    if reverseFill ~= nil and bar.SetReverseFill then
        bar:SetReverseFill(reverseFill and true or false)
    end
    bar:Hide()
    return bar
end

local function CreateSelfHealPredBar(f, hpBar)
    local clip = CreateFrame("Frame", nil, hpBar)
    clip:SetAllPoints(hpBar)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    f.selfHealPredClip = clip
    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    _G.MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    bar:SetFrameLevel(clip:GetFrameLevel())
    bar:SetStatusBarColor(0.0, 1.0, 0.4, 0.35)
    bar:Hide()
    f.selfHealPredBar = bar
    if hpBar and hpBar.GetReverseFill and bar.SetReverseFill then
        local okRF, rf = pcall(hpBar.GetReverseFill, hpBar)
        if okRF and rf ~= nil then pcall(bar.SetReverseFill, bar, rf and true or false) end
    end
end

local UNIT_CREATE_DEFS = {
    player       = { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    target       = { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    focus        = { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    targettarget = { w = 220, h = 30, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    pet          = { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
}
local UNIT_CREATE_DEF_BOSS = { w = 220, h = 30, showName = true, showHP = true, showPower = true, isBoss = true, startHidden = true }
local tipFuncs = {
    player = "MSUF_ShowPlayerInfoTooltip",
    target = "MSUF_ShowTargetInfoTooltip",
    focus = "MSUF_ShowFocusInfoTooltip",
    targettarget = "MSUF_ShowTargetTargetInfoTooltip",
    pet = "MSUF_ShowPetInfoTooltip",
}
_G.MSUF_UNIT_TIP_FUNCS = tipFuncs
MSUF_UNIT_TIP_FUNCS = tipFuncs

function CreateSimpleUnitFrame(unit)
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then _G.EnsureDB() end
    local getKey = _G.GetConfigKeyForUnit or _G.MSUF_GetConfigKeyForUnit
    local key = type(getKey) == "function" and getKey(unit) or unit
    local conf = (key and _G.MSUF_DB and _G.MSUF_DB[key]) or {}
    local f = (F.CreateFrame or CreateFrame)("Button", "MSUF_" .. unit, UIParent, "BackdropTemplate,SecureUnitButtonTemplate,PingableUnitFrameTemplate")
    f.unit = unit
    if type(_G.MSUF_EnsureUnitFlags) == "function" then _G.MSUF_EnsureUnitFlags(f) end
    f.msufConfigKey = key
    f.cachedConfig = conf
    f:SetClampedToScreen(true)

    local isBossUnit = (f._msufBossIndex ~= nil)
    local def = UNIT_CREATE_DEFS[unit] or (isBossUnit and UNIT_CREATE_DEF_BOSS) or nil
    if def then
        f:SetSize(conf.width or def.w, conf.height or def.h)
        f.showName = ConfBool(conf, "showName", def.showName)
        f.showHPText = ConfBool(conf, "showHP", def.showHP)
        f.showPowerText = ConfBool(conf, "showPower", def.showPower)
        f.isBoss = def.isBoss and true or false
        if def.startHidden then f:Hide() end
        if f.isBoss and type(_G.MSUF_ApplyUnitVisibilityDriver) == "function" then
            _G.MSUF_ApplyUnitVisibilityDriver(f, false)
        end
    end

    if type(_G.MSUF_PositionUnitFrame) == "function" then _G.MSUF_PositionUnitFrame(f, unit) end
    if type(_G.MSUF_EnableUnitFrameDrag) == "function" then _G.MSUF_EnableUnitFrameDrag(f, unit) end
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    if not f._msufHpSpacerSelectHooked then
        f._msufHpSpacerSelectHooked = true
        f:HookScript("OnMouseDown", ns.UF.HpSpacerSelect_OnMouseDown)
    end

    local bg = ns.UF.MakeTex(f, "bg", "self", "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)

    local hpBar = ns.UF.MakeBar(f, "hpBar", "self")
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    hpBar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
    hpBar:SetMinMaxValues(0, 1)
    _G.MSUF_SetBarValue(hpBar, 0, false)
    hpBar.MSUF_lastValue = 0
    hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
    local bgTex = ns.UF.MakeTex(f, "hpBarBG", "hpBar", "BACKGROUND")
    bgTex:SetAllPoints(hpBar)
    if type(_G.MSUF_ApplyBarBackgroundVisual) == "function" then _G.MSUF_ApplyBarBackgroundVisual(f) end

    local portrait = ns.UF.MakeTex(f, "portrait", "self", "ARTWORK")
    portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    portrait:Hide()

    if not f.hpGradients and ns.Bars and ns.Bars._PreCreateHPGradients then
        local grads = ns.Bars._PreCreateHPGradients(hpBar)
        f.hpGradients = grads
        f.hpGradient = grads and grads.right or nil
    end
    if ns.Bars and ns.Bars._ApplyHPGradient then ns.Bars._ApplyHPGradient(f) end

    if unit == "player" then
        CreateSelfHealPredBar(f, hpBar)
    end

    f.absorbBar = CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 2, GetAbsorbOverlayColor(), true)
    f.healAbsorbBar = CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 3, GetHealAbsorbOverlayColor(), false)
    if ns.Bars and ns.Bars.SetOverlayBarTexture then
        ns.Bars.SetOverlayBarTexture(f.absorbBar, _G.MSUF_GetAbsorbBarTexture)
        ns.Bars.SetOverlayBarTexture(f.healAbsorbBar, _G.MSUF_GetHealAbsorbBarTexture)
    end
    f._msufAlphaSupportsLayered = true

    if unit == "player" or unit == "focus" or unit == "target" or isBossUnit then
        local pBar = ns.UF.MakeBar(f, "targetPowerBar", "self")
        pBar:SetStatusBarTexture(_G.MSUF_GetBarTexture())
        local h = ((_G.MSUF_DB and _G.MSUF_DB.bars and type(_G.MSUF_DB.bars.powerBarHeight) == "number" and _G.MSUF_DB.bars.powerBarHeight > 0) and _G.MSUF_DB.bars.powerBarHeight) or 3
        pBar:SetHeight(h)
        pBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetMinMaxValues(0, 1)
        _G.MSUF_SetBarValue(pBar, 0, false)
        pBar.MSUF_lastValue = 0
        pBar:SetFrameLevel(hpBar:GetFrameLevel())
        local pbg = ns.UF.MakeTex(f, "powerBarBG", "targetPowerBar", "BACKGROUND")
        pbg:SetAllPoints(pBar)
        if type(_G.MSUF_ApplyBarBackgroundVisual) == "function" then _G.MSUF_ApplyBarBackgroundVisual(f) end
        if not f.powerGradients and ns.Bars and ns.Bars._PreCreateHPGradients then
            local pgrads = ns.Bars._PreCreateHPGradients(pBar)
            f.powerGradients = pgrads
            f.powerGradient = pgrads and pgrads.right or nil
        end
        if ns.Bars and ns.Bars._ApplyPowerGradient then ns.Bars._ApplyPowerGradient(f) end
        if _G.MSUF_ApplyPowerBarBorder then _G.MSUF_ApplyPowerBarBorder(pBar) end
        pBar:Hide()
    end

    local textFrame = ns.UF.MakeFrame(f, "textFrame", "Frame", "self")
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    local fontPath = ns.Castbars._GetFontPath()
    local flags = ns.Castbars._GetFontFlags()
    local fontColorFn = ns.MSUF_GetConfiguredFontColor or _G.MSUF_GetConfiguredFontColor
    local fr, fg, fb = 1, 1, 1
    if type(fontColorFn) == "function" then fr, fg, fb = fontColorFn() end
    ns.UF.EnsureTextObjects(f, fontPath, flags, fr, fg, fb)
    ns.UF.EnsureStatusIndicatorOverlays(f, unit, fontPath, flags, fr, fg, fb)
    if type(_G.MSUF_ApplyTextLayout) == "function" then _G.MSUF_ApplyTextLayout(f, conf) elseif type(_G.ApplyTextLayout) == "function" then _G.ApplyTextLayout(f, conf) end
    if type(_G.MSUF_ClampNameWidth) == "function" then _G.MSUF_ClampNameWidth(f, conf) end
    if type(_G.MSUF_UpdateNameColor) == "function" then _G.MSUF_UpdateNameColor(f) end

    do
        local isPlayer = (unit == "player")
        local isPT = isPlayer or (unit == "target")
        local getAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
        local defs = {
            { "leaderIcon", isPT, "self", "OVERLAY", nil, 16, "Interface\\GroupFrame\\UI-Group-LeaderIcon", { "LEFT", f, "TOPLEFT", 0, 3 }, nil, _G.MSUF_ApplyLeaderIconLayout },
            { "raidMarkerIcon", true, "textFrame", "OVERLAY", 7, 16, "Interface\\TargetingFrame\\UI-RaidTargetingIcons", { "LEFT", textFrame, "TOPLEFT", 16, 3 }, nil, _G.MSUF_ApplyRaidMarkerLayout },
            { "combatStateIndicatorIcon", isPT, "textFrame", "OVERLAY", 7, 18, "Interface\\CharacterFrame\\UI-StateIcon", nil, { "UI-HUD-UnitFrame-Player-PortraitCombatIcon", 0.5, 1, 0, 0.5 } },
            { "incomingResIndicatorIcon", isPT, "textFrame", "OVERLAY", 7, 18, "Interface\\RaidFrame\\Raid-Icon-Rez" },
            { "classificationIndicatorIcon", (unit == "target"), "textFrame", "OVERLAY", 7, 18, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
            { "summonIndicatorIcon", isPT, "textFrame", "OVERLAY", 7, 18, "Interface\\RaidFrame\\Raid-Icon-Summon", nil, { "Raid-Icon-SummonPending" } },
            { "restingIndicatorIcon", isPlayer, "textFrame", "OVERLAY", 7, 18, "Interface\\CharacterFrame\\UI-StateIcon", nil, { "UI-HUD-UnitFrame-Player-PortraitRestingIcon", 0, 0.5, 0, 0.5 } },
        }
        for i = 1, #defs do
            local ikey, ok, parentKey, layer, sub, size, file, pt, atlas, apply = unpack(defs[i])
            if ok then
                local tex = ns.UF.MakeTex(f, ikey, parentKey, layer, sub)
                if size then tex:SetSize(size, size) end
                if pt then tex:ClearAllPoints(); tex:SetPoint(unpack(pt)) end
                if atlas and getAtlasInfo and getAtlasInfo(atlas[1]) then
                    tex:SetAtlas(atlas[1], true)
                else
                    tex:SetTexture(file)
                    if atlas and atlas[2] then tex:SetTexCoord(atlas[2], atlas[3], atlas[4], atlas[5]) end
                end
                tex:Hide()
                if apply then apply(f) end
            end
        end
        if unit == "target" and type(_G.MSUF_CreateClassificationText) == "function" then
            _G.MSUF_CreateClassificationText(f, textFrame, conf, fontPath, flags, fr, fg, fb)
        end
    end

    if _G.MSUF_UFCore_AttachFrame then _G.MSUF_UFCore_AttachFrame(f) end
    f:EnableMouse(true)
    local highlight = ns.UF.MakeFrame(f, "highlightBorder", "Frame", "self", (BackdropTemplateMixin and "BackdropTemplate") or nil)
    highlight:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    highlight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    do
        local baseLevel = 0
        if f.GetFrameLevel then baseLevel = f:GetFrameLevel() or 0 end
        if f.hpBar and f.hpBar.GetFrameLevel then
            local hb = f.hpBar:GetFrameLevel() or 0
            if hb > baseLevel then baseLevel = hb end
        end
        highlight:SetFrameLevel(baseLevel + 10)
    end
    highlight:EnableMouse(false)
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    highlight:Hide()
    f.UpdateHighlightColor = ns.UF.UpdateHighlightColor
    f:SetScript("OnEnter", ns.UF.Unitframe_OnEnter)
    f:SetScript("OnLeave", ns.UF.Unitframe_OnLeave)
    ClickCastFrames[f] = true

    if f.targetPowerBar and f.hpBar and type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout(f)
    end
    if ns.Bars and ns.Bars._ApplyReverseFillBars then ns.Bars._ApplyReverseFillBars(f, conf) end
    ns.UF.RequestUpdate(f, true, true, "F.CreateFrame")

    if type(_G.MSUF_A2_RequestUnit) == "function" then
        _G.MSUF_A2_RequestUnit(unit)
    elseif unit == "target" and type(_G.MSUF_UpdateTargetAuras) == "function" then
        _G.MSUF_UpdateTargetAuras(f)
    end

    local unitFrames = _G.MSUF_UnitFrames or _G.UnitFrames
    if unitFrames then unitFrames[unit] = f end
    local unitFramesList = _G.MSUF_UnitFramesList
    if unitFramesList and not f._msufInUnitFramesList then
        f._msufInUnitFramesList = true
        table.insert(unitFramesList, f)
    end
    if type(_G.MSUF_ApplyUnitVisibilityDriver) == "function" then
        _G.MSUF_ApplyUnitVisibilityDriver(f, _G.MSUF_UnitEditModeActive)
    end
    return f
end

_G.MSUF_CreateSimpleUnitFrame = CreateSimpleUnitFrame
