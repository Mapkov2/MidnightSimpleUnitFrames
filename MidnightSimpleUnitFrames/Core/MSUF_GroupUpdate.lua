local addonName, ns = ...

local Update = {}
ns.GroupUpdate = Update
_G.MSUF_GroupUpdate = Update

local UnitHealthPercent = UnitHealthPercent
local UnitClass = UnitClass
local UnitName = UnitName
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitPowerPercent = UnitPowerPercent

local PREVIEW_CLASS = { "PRIEST", "WARRIOR", "MAGE", "DRUID", "PALADIN", "SHAMAN", "ROGUE", "WARLOCK", "HUNTER", "MONK" }

local function GetDB(kind)
    local db = _G.MSUF_DB
    local gf = db and db.groupFrames
    return gf and gf[kind]
end

local function GetFontPath(conf)
    if conf and conf.fontOverride and conf.fontPath and conf.fontPath ~= "" then
        return conf.fontPath
    end
    if ns and ns.Castbars and type(ns.Castbars._GetFontPath) == "function" then
        return ns.Castbars._GetFontPath()
    end
    return STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
end

local function GetFontFlags()
    if ns and ns.Castbars and type(ns.Castbars._GetFontFlags) == "function" then
        return ns.Castbars._GetFontFlags()
    end
    return ""
end

local function GetBaseFontColor()
    if type(_G.MSUF_GetConfiguredFontColor) == "function" then
        return _G.MSUF_GetConfiguredFontColor()
    end
    return 1, 1, 1
end

local function GetPreviewInfo(kind, index)
    local classes = PREVIEW_CLASS
    local classToken = classes[((index - 1) % #classes) + 1]
    local name = (kind == "party" and "Party" or "Raid") .. " " .. tostring(index)
    local hp = kind == "party" and (0.86 - (index - 1) * 0.09) or (0.96 - ((index - 1) % 5) * 0.12)
    local power = kind == "party" and (0.40 + (index - 1) * 0.08) or (0.25 + ((index - 1) % 4) * 0.14)
    if hp < 0.18 then hp = 0.18 end
    if power > 1 then power = 1 end
    return {
        name = name,
        classToken = classToken,
        health = hp,
        power = power,
        connected = true,
        dead = false,
        offline = false,
    }
end

local function ResolveClassColor(classToken)
    if ns and ns._colorsAPI and type(ns._colorsAPI.GetClassColor) == "function" then
        local r, g, b = ns._colorsAPI.GetClassColor(classToken)
        if r ~= nil then return r, g, b end
    end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(classToken)
        if color and color.GetRGB then return color:GetRGB() end
    end
    local tbl = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if tbl then return tbl.r, tbl.g, tbl.b end
    return 0.35, 0.35, 0.38
end

local function ResolveFillColor(conf, classToken)
    if conf and conf.colorOverride then
        if conf.useClassColors then
            return ResolveClassColor(classToken)
        end
        if conf.darkMode then
            return 0.22, 0.24, 0.28
        end
        return conf.colorR or 0.18, conf.colorG or 0.55, conf.colorB or 0.88
    end
    local db = _G.MSUF_DB
    local g = db and db.general
    if g and g.useClassColors then
        return ResolveClassColor(classToken)
    end
    if g and g.darkMode then
        return 0.22, 0.24, 0.28
    end
    return ResolveClassColor(classToken)
end

local function ResolveBarTexture(conf)
    if conf and conf.barOverride and conf.barTexture and conf.barTexture ~= "" then
        return conf.barTexture
    end
    if type(_G.MSUF_GetBarTexture) == "function" then
        return _G.MSUF_GetBarTexture()
    end
    return "Interface\\Buttons\\WHITE8X8"
end

function Update.ApplySharedStyle(button, kind)
    if not button then return end
    local conf = GetDB(kind)
    local fontPath = GetFontPath(conf)
    local flags = GetFontFlags()
    local fr, fg, fb = GetBaseFontColor()
    local nameSize = (conf and conf.nameFontSize) or 11
    local statusSize = math.max(9, nameSize - 1)
    local texture = ResolveBarTexture(conf)

    if button.hpBar and button.hpBar.SetStatusBarTexture then
        button.hpBar:SetStatusBarTexture(texture)
    end
    if button.powerBar and button.powerBar.SetStatusBarTexture then
        button.powerBar:SetStatusBarTexture(texture)
    end
    if button.nameText and button.nameText.SetFont then
        button.nameText:SetFont(fontPath, nameSize, flags)
        button.nameText:SetTextColor(fr, fg, fb, 1)
    end
    if button.statusText and button.statusText.SetFont then
        button.statusText:SetFont(fontPath, statusSize, flags)
        button.statusText:SetTextColor(fr, fg, fb, 0.9)
    end
end

function Update.ApplyUnit(button, unit, kind, index)
    if not button then return end
    local conf = GetDB(kind)
    local preview = unit and unit:match("^preview_") and true or false
    local info

    if preview then
        info = GetPreviewInfo(kind, index)
    else
        local _, classToken = UnitClass(unit)
        local hp = UnitHealthPercent and UnitHealthPercent(unit, true) or 0
        local power = UnitPowerPercent and UnitPowerPercent(unit, true) or 0
        local connected = UnitIsConnected and UnitIsConnected(unit)
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
        local nm = UnitName and UnitName(unit)
        info = {
            name = nm or unit,
            classToken = classToken,
            health = hp or 0,
            power = power or 0,
            connected = connected ~= false,
            dead = dead and true or false,
            offline = connected == false,
        }
    end

    Update.ApplySharedStyle(button, kind)

    local r, g, b = ResolveFillColor(conf, info.classToken)
    local text = info.name or "Unknown"
    local alpha = info.offline and 0.45 or 1
    local status = ""

    if info.dead then
        status = DEAD or "Dead"
        alpha = 0.55
    elseif info.offline then
        status = PLAYER_OFFLINE or "Offline"
        alpha = 0.45
    end

    if button.hpBar then
        if type(_G.MSUF_SetBarValue) == "function" then
            _G.MSUF_SetBarValue(button.hpBar, info.health or 0, false)
        else
            button.hpBar:SetValue(info.health or 0)
        end
        button.hpBar:SetStatusBarColor(r, g, b, alpha)
    end

    if button.powerBar then
        local showPower = (kind == "party")
        if showPower then
            if type(_G.MSUF_SetBarValue) == "function" then
                _G.MSUF_SetBarValue(button.powerBar, info.power or 0, false)
            else
                button.powerBar:SetValue(info.power or 0)
            end
            button.powerBar:Show()
        else
            button.powerBar:Hide()
        end
    end

    if button.nameText then
        button.nameText:SetText(text)
        button.nameText:SetAlpha(alpha)
    end
    if button.statusText then
        button.statusText:SetText(status)
        button.statusText:SetShown(status ~= "")
    end
    if button.bg then
        button.bg:SetColorTexture(0.05, 0.06, 0.09, 0.92)
    end
    if button.border and button.border.SetBackdropBorderColor then
        button.border:SetBackdropBorderColor(0.10, 0.20, 0.42, preview and 0.55 or 0.35)
    end
    if button.unitLabel then
        button.unitLabel:SetShown(preview)
        if preview then button.unitLabel:SetText(tostring(index)) end
    end
end
