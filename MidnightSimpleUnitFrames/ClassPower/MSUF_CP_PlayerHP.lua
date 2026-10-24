--- PlayerHP native painters, bound to state owned by UF.PlayerHP.
local _, MSUF = ...
local FILE = "ClassPower/MSUF_CP_PlayerHP.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)

local builders = MSUF.Require("MSUF_CP_CONST", FILE).BuilderRegistry("MSUF_CP_CORE_BUILDERS")

local GetFontPath = MSUF.Require("MSUF_GetFontPath", FILE)
local GetFontFlags = MSUF.Require("MSUF_GetFontFlags", FILE)
local ApplyResolvedFont = MSUF.Require("MSUF_ApplyResolvedFont", FILE)
local ResolveSafeFontPath = MSUF.Require("MSUF_ResolveSafeFontPath", FILE)

local DISPATCH_KEY = MSUF.UFText and MSUF.UFText.DISPATCH_KEY
if type(DISPATCH_KEY) ~= "table" then
    error("MSUF: missing required dependency 'UFText.DISPATCH_KEY' required by " .. FILE
        .. " - check that MSUF_UF_Text_Format.lua still names it and still loads first in MidnightSimpleUnitFrames.toc.", 2)
end
local STAMPS_HP = { [DISPATCH_KEY.CURRENT] = true, [DISPATCH_KEY.CURRENT_MAX] = true }
local STAMPS_MAX = { [DISPATCH_KEY.MAX] = true, [DISPATCH_KEY.CURRENT_MAX] = true, [DISPATCH_KEY.PERCENT_MAX] = true }
local STAMPS_PERCENT = { [DISPATCH_KEY.PERCENT] = true, [DISPATCH_KEY.PERCENT_MAX] = true }

local NUM_OPTS = nil
do
    local NumberFormat = MSUF.NumberFormat
    if NumberFormat and NumberFormat.Register then
        NumberFormat.Register(function(options) NUM_OPTS = options end)
    end
end

local PHP, CP, _cpDB
local UnitHealth, UnitHealthMax, UnitClass, RAID_CLASS_COLORS
local CreateFrame, GetPlayerFrame, ResolveTexture
local tonumber, type, tostring, pairs = tonumber, type, tostring, pairs
local math_floor, string_format = math.floor, string.format
local IsSecretValue, UnitHealthPercentAPI, SCALE_100
local POWER_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
--- shape -> media art name; each art has a fill, a background and an edge image.
local POWER_SHAPE_ART = { ROUND = "power_round", CRYSTAL = "power_crystal", ORB = "pip_circle" }
local POWER_SHAPE_TEXTURES = {}
for shape, art in pairs(POWER_SHAPE_ART) do
    POWER_SHAPE_TEXTURES[shape] = {
        fill = POWER_SHAPE_MEDIA .. art .. "_fill.tga",
        bg = POWER_SHAPE_MEDIA .. art .. "_bg.tga",
        edge = POWER_SHAPE_MEDIA .. art .. "_edge.tga",
        axis = shape == "ORB" and "VERTICAL" or nil,
    }
end

local HP_TEXT_REVERSE = {
    CURMAX = "MAXCUR",
    MAXCUR = "CURMAX",
    CURPERCENT = "PERCENTCUR",
    PERCENTCUR = "CURPERCENT",
    MAXPERCENT = "PERCENTMAX",
    PERCENTMAX = "MAXPERCENT",
    CURMAXPERCENT = "PERCENTCURMAX",
    PERCENTCURMAX = "CURMAXPERCENT",
    PERCENTMAXCUR = "CURMAXPERCENT",
}

--- A delimiter symbol is shown spaced on both sides; no symbol is one space.
local HP_TEXT_DELIMITERS = { [""] = " " }
for _, symbol in ipairs({ "-", "/", "\\", "|", "<", ">", "~", ":" }) do
    HP_TEXT_DELIMITERS[symbol] = " " .. symbol .. " "
end

local function UsePlayerText(b)
    return b and b.playerHPBarUsePlayerText ~= false
end

local function PlayerConfig()
    local db = MSUF_DB
    return db and db.player or nil, db and db.general or nil
end

local function PlayerHealthTextEnabled(player)
    if not player then return true end
    local enabled = player.showHP
    if enabled == nil then enabled = player.showHPText end
    return enabled ~= false
end

local function TextEnabled(b)
    if not b or b.playerHPBarTextEnabled == false then return false end
    if UsePlayerText(b) then
        local player = PlayerConfig()
        return PlayerHealthTextEnabled(player)
    end
    return true
end

local function ColorMode(b)
    local mode = tostring(b and b.playerHPBarColorMode or "GLOBAL"):upper()
    if mode == "CLASS" or mode == "DARK" or mode == "GRADIENT" then return mode end
    return "GLOBAL"
end

local NormalizeClassPowerShape = MSUF.Require("MSUF_UF_NormalizeClassPowerShape", FILE)

local function NormalizePowerShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end

local NormalizeHPShape = MSUF.Require("MSUF_UF_NormalizePlayerHPShape", FILE)

local function ResolveFollowPowerShape(b)
    local db = MSUF_DB
    local player = db and db.player or nil
    if not (player and player.powerBarDetached == true) then return "BAR" end
    local value = tostring(player.detachedPowerBarShape or "BAR"):upper()
    if value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    if value == "BAR" then return "BAR" end
    local classShape = NormalizeClassPowerShape(b and b.classPowerShape)
    if classShape == "CIRCLE" then return "ROUND" end
    if classShape == "DIAMOND" or classShape == "HEX" then return "CRYSTAL" end
    return "BAR"
end

local function ResolveHPShape(b)
    local value = NormalizeHPShape(b and b.playerHPBarShape)
    if value == "FOLLOW_POWER" then return ResolveFollowPowerShape(b) end
    return NormalizePowerShape(value)
end

local function ShapeTextures(shape)
    return POWER_SHAPE_TEXTURES[NormalizePowerShape(shape)]
end

local ShapeOutlineAlpha = MSUF.Require("MSUF_UF_ShapeOutlineAlpha", FILE)

local function Clamp(value, fallback, minValue, maxValue)
    value = tonumber(value) or fallback
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ResolveOrbSize(b)
    if NormalizeHPShape(b and b.playerHPBarShape) == "FOLLOW_POWER" then
        local db = MSUF_DB
        local player = db and db.player or nil
        return Clamp(player and player.detachedPowerOrbSize, 54, 20, 160)
    end
    return Clamp(b and b.playerHPBarOrbSize, 54, 20, 160)
end

local function ClearShapeFill(bar)
    if not bar then return end
    local wasVertical = bar._msufPHPShapeAxis == "VERTICAL"
    bar._msufPHPShapeAxis = nil
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
    if tex and tex.SetTexCoord then
        tex:SetTexCoord(0, 1, 0, 1)
    end
    if wasVertical and bar.SetOrientation then
        bar:SetOrientation("HORIZONTAL")
    end
end

local function ApplyShapeFill(bar, axis)
    ClearShapeFill(bar)
    if bar and bar.SetOrientation then
        bar:SetOrientation(axis == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
    end
    if bar then
        bar._msufPHPShapeAxis = axis == "VERTICAL" and "VERTICAL" or nil
    end
end

local function ShortValue(value)
    value = tonumber(value) or 0
    local abbrev = AbbreviateShortNumber or AbbreviateLargeNumbers
    if type(abbrev) == "function" then
        local text = abbrev(value, NUM_OPTS)
        if text ~= nil then return text end
    end
    local absValue = value < 0 and -value or value
    local sign = value < 0 and "-" or ""
    if absValue >= 1000000 then
        local n = math_floor((absValue / 100000) + 0.5) / 10
        if n >= 10 or n == math_floor(n) then
            return sign .. string_format("%dM", math_floor(n + 0.5))
        end
        return sign .. string_format("%.1fM", n)
    elseif absValue >= 1000 then
        local n = math_floor((absValue / 100) + 0.5) / 10
        if n >= 10 or n == math_floor(n) then
            return sign .. string_format("%dK", math_floor(n + 0.5))
        end
        return sign .. string_format("%.1fK", n)
    end
    return string_format("%d", value)
end

local function Delimiter(delimiter)
    if delimiter == nil then return " " end
    return HP_TEXT_DELIMITERS[delimiter] or delimiter
end

local function Percent(hp, maxHP)
    if type(hp) ~= "number" or type(maxHP) ~= "number" or maxHP <= 0 then return 0 end
    local pct = math_floor((hp / maxHP) * 100 + 0.5)
    if pct < 0 then return 0 end
    if pct > 100 then return 100 end
    return pct
end

local function GlobalHidePercentSymbol()
    -- Per health text update: read the profile inline, not through PlayerConfig.
    local db = MSUF_DB
    local g = db and db.general
    return g and g.hidePercentSymbol == true
end

local function ReadHidePercentSymbol(conf, key)
    if conf and conf[key] ~= nil then return conf[key] == true end
    return GlobalHidePercentSymbol()
end

local function PercentText(pct, hidePercentSymbol)
    if pct == nil then return "" end
    return string_format("%d%s", pct, hidePercentSymbol and "" or "%")
end

local function UnitPercent()
    if not UnitHealthPercentAPI then return nil end
    local pct
    if SCALE_100 then
        pct = UnitHealthPercentAPI("player", true, SCALE_100)
    else
        pct = UnitHealthPercentAPI("player", true)
    end
    if IsSecretValue(pct) == true then
        if SCALE_100 then return nil, pct end
        return nil
    end
    pct = tonumber(pct)
    if not pct then return nil end
    if pct <= 1 then pct = pct * 100 end
    if pct < 0 then return 0 end
    if pct > 100 then return 100 end
    return math_floor(pct + 0.5)
end

local function DarkColor()
    local cache = MSUF.UF and MSUF.UF.Config and MSUF.UF.Config.settingsCache
    if cache and type(cache.darkBarR) == "number" and type(cache.darkBarG) == "number" and type(cache.darkBarB) == "number" then
        return cache.darkBarR, cache.darkBarG, cache.darkBarB
    end
    local g = MSUF_DB and MSUF_DB.general or nil
    local gray = tonumber(g and (g.darkBarGray or g.darkBgBrightness)) or 0.07
    if gray > 1 then gray = gray / 100 end
    return tonumber(g and g.darkBarR) or gray, tonumber(g and g.darkBarG) or gray, tonumber(g and g.darkBarB) or gray
end

local function GradientColor(hp, maxHP, common)
    if common and type(common.GradientColor) == "function" then
        local r, g, b = common.GradientColor("player", nil)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    local pct
    if IsSecretValue(hp) == true or IsSecretValue(maxHP) == true then
        pct = UnitPercent()
        if pct == nil then return 1, 1, 0 end
    else
        pct = Percent(hp, maxHP)
    end
    pct = pct / 100
    if pct <= 0.5 then return 1, pct * 2, 0 end
    return (1 - pct) * 2, 1, 0
end

local function ApplyCachedColor(bar, r, g, b)
    if not bar then return end
    if bar._phpR == r and bar._phpG == g and bar._phpB == b then return end
    bar:SetStatusBarColor(r, g, b, 1)
    bar._phpR, bar._phpG, bar._phpB = r, g, b
    bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = r, g, b, 1
end

local function ModeText(mode, hp, maxHP, delimiter, hidePercentSymbol)
    mode = tostring(mode or "NONE"):upper()
    if mode == "NONE" then return "" end
    local current = ShortValue(hp)
    local maxText = ShortValue(maxHP)
    local pctText = PercentText(Percent(hp, maxHP), hidePercentSymbol == true)
    delimiter = Delimiter(delimiter)
    if mode == "CURRENT" then return current end
    if mode == "MAX" then return maxText end
    if mode == "DEFICIT" then
        local missing = (tonumber(maxHP) or 0) - (tonumber(hp) or 0)
        return missing > 0 and ("-" .. ShortValue(missing)) or ""
    end
    if mode == "PERCENT" then return pctText end
    if mode == "CURMAX" then return current .. delimiter .. maxText end
    if mode == "MAXCUR" then return maxText .. delimiter .. current end
    if mode == "CURPERCENT" then return current .. delimiter .. pctText end
    if mode == "PERCENTCUR" then return pctText .. delimiter .. current end
    if mode == "MAXPERCENT" then return maxText .. delimiter .. pctText end
    if mode == "PERCENTMAX" then return pctText .. delimiter .. maxText end
    if mode == "CURMAXPERCENT" then return current .. delimiter .. maxText .. delimiter .. pctText end
    if mode == "PERCENTCURMAX" then return pctText .. delimiter .. current .. delimiter .. maxText end
    if mode == "PERCENTMAXCUR" then return pctText .. delimiter .. maxText .. delimiter .. current end
    return current .. delimiter .. maxText
end

local function SetText(fs, text)
    if not fs then return end
    if IsSecretValue(text) == true then
        fs._msufPHPText = nil
        fs:SetText(text)
        return
    end
    text = text or ""
    if fs._msufPHPText == text then return end
    fs._msufPHPText = text
    fs:SetText(text)
end

local function SetPercentText(fs, pct, secretPct, hidePercentSymbol)
    if IsSecretValue(secretPct) == true then
        if not fs then return end
        fs._msufPHPText = nil
        fs:SetFormattedText(hidePercentSymbol and "%.0f" or "%.0f%%", secretPct)
        return
    end
    SetText(fs, PercentText(pct, hidePercentSymbol))
end

local function RenderedTextMatches(rt, hp, maxHP)
    if not (rt and rt.healthSlotCount and rt.healthSlotCount > 0) then return false end
    local keyHP, keyMax = false, false
    local mode = rt.healthDispatchKeyMode
    if STAMPS_PERCENT[mode] then
        keyHP = Percent(hp, maxHP)
    elseif STAMPS_HP[mode] then
        keyHP = hp
    end
    if STAMPS_MAX[mode] then keyMax = maxHP end
    local missing
    if rt.healthNeedsMissing == true then
        missing = (tonumber(maxHP) or 0) - (tonumber(hp) or 0)
        if missing < 0 then missing = 0 end
    end
    return rt._lastHealthTextHP == keyHP
        and rt._lastHealthTextMax == keyMax
        and rt._lastHealthTextMissing == missing
end

local function ApplyCopiedTextColor(dst, r, g, b, a, secretColor)
    if not (dst and dst.SetTextColor) then return end
    if secretColor then
        dst:SetTextColor(r, g, b, a)
        dst._phpTextR, dst._phpTextG, dst._phpTextB, dst._phpTextA = nil, nil, nil, nil
        return
    end
    if r == nil then return end
    a = a or 1
    if dst._phpTextR == r and dst._phpTextG == g and dst._phpTextB == b and dst._phpTextA == a then return end
    dst:SetTextColor(r, g, b, a)
    dst._phpTextR, dst._phpTextG, dst._phpTextB, dst._phpTextA = r, g, b, a
end

local function ReadTextSlot(src)
    local text = ""
    local r, g, b, a
    if src then
        if not (src.IsShown and not src:IsShown()) then
            text = src._aText
            if text == nil and src.GetText then text = src:GetText() end
        end
        if IsSecretValue(text) ~= true and text == nil then text = "" end
        r, g, b, a = src._msufTextR, src._msufTextG, src._msufTextB, src._msufTextA
        if r == nil and src.GetTextColor then
            r, g, b, a = src:GetTextColor()
            if IsSecretValue(r) then return text, r, g, b, a, true end
        end
    end
    return text, r, g, b, a
end

local function CopyTextSlot(src, dst)
    if not dst then return false end
    local text, r, g, b, a, secretColor = ReadTextSlot(src)
    ApplyCopiedTextColor(dst, r, g, b, a, secretColor)
    SetText(dst, text)
    return true
end

local function CopyCompactText(playerFrame)
    if not (PHP.center and playerFrame) then return false end
    local text, r, g, b, a, secretColor = ReadTextSlot(playerFrame.hpTextCenter)
    if IsSecretValue(text) ~= true and text == "" then
        text, r, g, b, a, secretColor = ReadTextSlot(playerFrame.hpTextRight)
    end
    if IsSecretValue(text) ~= true and text == "" then
        text, r, g, b, a, secretColor = ReadTextSlot(playerFrame.hpTextLeft)
    end
    ApplyCopiedTextColor(PHP.center, r, g, b, a, secretColor)
    SetText(PHP.left, "")
    SetText(PHP.right, "")
    SetText(PHP.center, text)
    return true
end

local function CopyPlayerTextSlots(playerFrame)
    if PHP._compactText == true then
        return CopyCompactText(playerFrame)
    end
    local copied = false
    copied = CopyTextSlot(playerFrame and playerFrame.hpTextLeft, PHP.left) or copied
    copied = CopyTextSlot(playerFrame and playerFrame.hpTextCenter, PHP.center) or copied
    copied = CopyTextSlot(playerFrame and playerFrame.hpTextRight, PHP.right) or copied
    return copied
end

local function CopyRenderedPlayerText(hp, maxHP)
    local playerFrame = GetPlayerFrame()
    local rt = playerFrame and playerFrame._msufTextRuntime
    if not RenderedTextMatches(rt, hp, maxHP) then return false end
    return CopyPlayerTextSlots(playerFrame)
end

local function CopyPlayerTextBestEffort()
    local playerFrame = GetPlayerFrame()
    local rt = playerFrame and playerFrame._msufTextRuntime
    if not (rt and rt.healthSlotCount and rt.healthSlotCount > 0) then return false end
    return CopyPlayerTextSlots(playerFrame)
end

local function ApplyFont()
    if not PHP.left then return end
    local b = _cpDB.bars or {}
    local size = b.playerHPBarTextSize
    local player, general = PlayerConfig()
    if UsePlayerText(b) then
        size = player and player.hpFontSize or nil
        if size == nil then size = general and general.hpFontSize or nil end
    end
    size = Clamp(size, 14, 6, 48)
    local fontPath = GetFontPath() or STANDARD_TEXT_FONT
    local fontFlags = GetFontFlags() or "OUTLINE"
    if not fontPath or fontPath == "" then fontPath = "Fonts\\FRIZQT__.TTF" end
    if not fontFlags or fontFlags == "" then fontFlags = "OUTLINE" end
    fontPath = ResolveSafeFontPath(fontPath, size, fontFlags, general and general.fontKey)
    local fontEpoch = tonumber(MSUF_FontApplyEpoch) or 0
    local stamp = tostring(fontPath) .. ":" .. tostring(size) .. ":" .. tostring(fontFlags)
        .. ":" .. tostring(fontEpoch)
    if PHP._fontStamp == stamp then return end
    for _, fs in pairs({ PHP.left, PHP.center, PHP.right }) do
        if fs.SetFont then
            ApplyResolvedFont(fs, fontPath, size, fontFlags, general and general.fontKey)
        end
        fs._phpTextR, fs._phpTextG, fs._phpTextB, fs._phpTextA = nil, nil, nil, nil
        if fs.SetTextColor then fs:SetTextColor(1, 1, 1, 1) end
        local useShadow = not tostring(fontFlags or ""):upper():find("SLUG", 1, true)
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, useShadow and 1 or 0) end
        if fs.SetShadowOffset then fs:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0) end
    end
    -- Cache the attempt after all three strings have been processed. A
    -- failed requested font remains readable and retries on the next epoch.
    PHP._fontStamp = stamp
end

local function Ensure(playerFrame)
    if PHP.frame then return true end
    if not playerFrame then return false end

    local f = PixelLayoutRegion(CreateFrame("Frame", "MSUF_ClassPowerPlayerHealthBar", playerFrame._msufHealthVisualRoot or playerFrame))
    f:Hide()
    PHP.frame = f

    local bg = PixelLayoutRegion(f:CreateTexture(nil, "BACKGROUND", nil, -1))
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.35)
    PHP.bg = bg

    local bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, f))
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture(ResolveTexture(nil))
    PHP.bar = bar

    local tf = PixelLayoutRegion(CreateFrame("Frame", nil, f))
    tf:SetAllPoints(f)
    PHP.textFrame = tf

    local left = PixelLayoutRegion(tf:CreateFontString(nil, "OVERLAY"))
    left:SetJustifyH("LEFT")
    if left.SetJustifyV then left:SetJustifyV("MIDDLE") end
    PHP.left = left

    local center = PixelLayoutRegion(tf:CreateFontString(nil, "OVERLAY"))
    center:SetJustifyH("CENTER")
    if center.SetJustifyV then center:SetJustifyV("MIDDLE") end
    PHP.center = center

    local right = PixelLayoutRegion(tf:CreateFontString(nil, "OVERLAY"))
    right:SetJustifyH("RIGHT")
    if right.SetJustifyV then right:SetJustifyV("MIDDLE") end
    PHP.right = right

    ApplyFont()
    return true
end

local function EnsureShapeEdge()
    if PHP.shapeEdge then return PHP.shapeEdge end
    if not PHP.bar then return nil end
    local edge = PixelLayoutRegion(PHP.bar:CreateTexture(nil, "OVERLAY", nil, 7))
    edge:SetVertexColor(0, 0, 0, 1)
    edge:Hide()
    PHP.shapeEdge = edge
    return edge
end

local function HideShapeEdge()
    if PHP.shapeEdge then PHP.shapeEdge:Hide() end
end

local function HideLegacyEdge()
    if PHP.edge then
        PHP.edge:Hide()
        if PHP.edge.ClearAllPoints then PHP.edge:ClearAllPoints() end
    end
end

local function EnsureBarEdges()
    if not PHP.frame then return nil end
    local parent = PHP.frame.GetParent and PHP.frame:GetParent()
    if not parent then return nil end
    if not PHP.borderHost then
        PHP.borderHost = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
        PHP.borderHost:EnableMouse(false)
    elseif PHP.borderHost.GetParent and PHP.borderHost:GetParent() ~= parent then
        PHP.borderHost:SetParent(parent)
        PHP.borderEdges = nil
        PHP._barOutlineThickness = nil
    end
    if PHP.borderEdges and PHP.borderEdges._host == PHP.borderHost then return PHP.borderEdges, PHP.borderHost end
    local edges = {}
    for i = 1, 4 do
        local edge = PixelLayoutRegion(PHP.borderHost:CreateTexture(nil, "OVERLAY", nil, 6))
        edge:SetColorTexture(0, 0, 0, 1)
        edge:Hide()
        edges[i] = edge
    end
    edges._host = PHP.borderHost
    PHP.borderEdges = edges
    PHP._barOutlineThickness = nil
    return edges, PHP.borderHost
end

local function HideBarEdges()
    local edges = PHP.borderEdges
    if edges then
        for i = 1, 4 do
            if edges[i] then edges[i]:Hide() end
        end
    end
    if PHP.borderHost then PHP.borderHost:Hide() end
end

local function ApplyBarOutline(outline)
    outline = math_floor((tonumber(outline) or 0) + 0.5)
    if outline <= 0 then
        HideBarEdges()
        return
    end
    if outline > 8 then outline = 8 end
    local edges, host = EnsureBarEdges()
    if not edges then return end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", PHP.frame, "TOPLEFT", -outline, outline)
    host:SetPoint("BOTTOMRIGHT", PHP.frame, "BOTTOMRIGHT", outline, -outline)
    if host.SetFrameLevel and PHP.frame.GetFrameLevel then
        host:SetFrameLevel((PHP.frame:GetFrameLevel() or 1) + 2)
    end
    host:Show()
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    if PHP._barOutlineThickness ~= outline then
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        top:SetHeight(outline)

        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(outline)

        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        left:SetWidth(outline)

        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(outline)
        PHP._barOutlineThickness = outline
    end
    for i = 1, 4 do
        edges[i]:SetColorTexture(0, 0, 0, 1)
        edges[i]:Show()
    end
end

local function ResolveAnchor(playerFrame, mode)
    mode = tostring(mode or "CLASS_TOP"):upper()
    local power = playerFrame and playerFrame.targetPowerBar
    local powerVisible = power and power.IsShown and power:IsShown()
    if (mode == "POWER_TOP" or mode == "POWER_BOTTOM") and powerVisible then
        return power, mode
    end
    local classAnchor = CP and CP.container
    if classAnchor and classAnchor.GetWidth and classAnchor:GetWidth() > 0 then
        if mode == "CLASS_BOTTOM" then return classAnchor, "CLASS_BOTTOM" end
        return classAnchor, "CLASS_TOP"
    end
    if mode == "CLASS_BOTTOM" then return playerFrame, "CLASS_BOTTOM" end
    return playerFrame, "CLASS_TOP"
end

local function ResolveWidth(playerFrame, mode, manualWidth)
    mode = tostring(mode or "class"):lower()
    local width
    if mode == "custom" then
        width = tonumber(manualWidth)
    elseif mode == "power" then
        local power = playerFrame and playerFrame.targetPowerBar
        width = power and power.GetWidth and power:GetWidth() or nil
    elseif mode == "player" then
        width = playerFrame and playerFrame.GetWidth and playerFrame:GetWidth() or nil
    else
        width = CP and CP.container and CP.container.GetWidth and CP.container:GetWidth() or nil
    end
    if not width or width < 20 then
        width = playerFrame and playerFrame.GetWidth and playerFrame:GetWidth() or 160
    end
    if width < 20 then width = 20 elseif width > 1200 then width = 1200 end
    return width
end

local function ApplyTextLayout(b)
    if not PHP.left then return end
    local x = Clamp(b.playerHPBarTextOffsetX, 0, -300, 300)
    local y = Clamp(b.playerHPBarTextOffsetY, 0, -300, 300)
    local enabled = TextEnabled(b)
    local width = PHP._layoutWidth or (PHP.frame and PHP.frame.GetWidth and PHP.frame:GetWidth()) or 160
    local height = PHP._layoutHeight or (PHP.frame and PHP.frame.GetHeight and PHP.frame:GetHeight()) or 8
    local compact = PHP._compactText == true
    local margin = compact and 2 or 4
    if height > 12 and not compact then margin = 6 end
    local innerW = width - (margin * 2)
    if innerW < 1 then innerW = 1 end
    local sideW = math_floor(innerW * 0.34)
    if sideW < 1 then sideW = 1 end
    local centerW = innerW
    local textH = height + 8
    if textH < 12 then textH = 12 end
    local stamp = tostring(enabled) .. ":" .. tostring(compact) .. ":" .. x .. ":" .. y .. ":" .. width .. ":" .. height
    if PHP._textLayoutStamp ~= stamp then
        PHP._textLayoutStamp = stamp
        PHP.left:ClearAllPoints()
        PHP.left:SetPoint("LEFT", PHP.frame, "LEFT", margin + x, y)
        PHP.center:ClearAllPoints()
        PHP.center:SetPoint("CENTER", PHP.frame, "CENTER", x, y)
        PHP.right:ClearAllPoints()
        PHP.right:SetPoint("RIGHT", PHP.frame, "RIGHT", -margin + x, y)
        PHP.left:SetWidth(sideW)
        PHP.center:SetWidth(centerW)
        PHP.right:SetWidth(sideW)
        PHP.left:SetHeight(textH)
        PHP.center:SetHeight(textH)
        PHP.right:SetHeight(textH)
        if PHP.left.SetWordWrap then PHP.left:SetWordWrap(false) end
        if PHP.center.SetWordWrap then PHP.center:SetWordWrap(false) end
        if PHP.right.SetWordWrap then PHP.right:SetWordWrap(false) end
        if PHP.left.SetNonSpaceWrap then PHP.left:SetNonSpaceWrap(false) end
        if PHP.center.SetNonSpaceWrap then PHP.center:SetNonSpaceWrap(false) end
        if PHP.right.SetNonSpaceWrap then PHP.right:SetNonSpaceWrap(false) end
        if PHP.left.SetMaxLines then PHP.left:SetMaxLines(1) end
        if PHP.center.SetMaxLines then PHP.center:SetMaxLines(1) end
        if PHP.right.SetMaxLines then PHP.right:SetMaxLines(1) end
    end
    PHP.left:SetShown(enabled and not compact)
    PHP.center:SetShown(enabled)
    PHP.right:SetShown(enabled and not compact)
end

local function Hide()
    if MSUF.ResourceVisibility then
        MSUF.ResourceVisibility.Unbind(PHP.frame)
        MSUF.ResourceVisibility.Unbind(PHP.borderHost)
    end
    if PHP.frame then PHP.frame:Hide() end
    HideBarEdges()
    HideShapeEdge()
    PHP._edgeStamp = nil
    PHP.visible = false
end

local function ApplyLayout(playerFrame)
    local b = _cpDB.bars or {}

    local shape = ResolveHPShape(b)
    local shapeInfo = ShapeTextures(shape)
    local h = Clamp(b.playerHPBarHeight, 6, 2, 80)
    local gap = Clamp(b.playerHPBarGap, 2, 0, 60)
    local x = Clamp(b.playerHPBarOffsetX, 0, -1000, 1000)
    local y = Clamp(b.playerHPBarOffsetY, 0, -1000, 1000)
    local width = ResolveWidth(playerFrame, b.playerHPBarWidthMode, b.playerHPBarWidth)
    if shape == "ORB" then
        h = ResolveOrbSize(b)
        width = h
    end
    local anchor, anchorMode = ResolveAnchor(playerFrame, b.playerHPBarAnchor)
    local levelOffset = math_floor(Clamp(b.playerHPBarFrameLevelOffset, 7, 0, 30) + 0.5)
    local baseLevel = playerFrame and playerFrame.GetFrameLevel and (playerFrame:GetFrameLevel() or 1) or 1
    local outline = Clamp(b.playerHPBarOutline, 1, 0, 8)
    local compactText = shape == "ORB" or (shapeInfo ~= nil and width <= (h * 3))
    PHP._shape = shape
    PHP._shapeInfo = shapeInfo
    PHP._layoutWidth = width
    PHP._layoutHeight = h
    PHP._compactText = compactText
    local layoutStamp = tostring(anchor) .. ":" .. anchorMode .. ":" .. shape .. ":" .. width .. ":" .. h
        .. ":" .. gap .. ":" .. x .. ":" .. y .. ":" .. levelOffset .. ":" .. baseLevel
    if PHP._layoutStamp ~= layoutStamp then
        PHP._layoutStamp = layoutStamp
        PHP.frame:ClearAllPoints()
        if anchorMode == "CLASS_BOTTOM" or anchorMode == "POWER_BOTTOM" then
            PHP.frame:SetPoint("TOP", anchor, "BOTTOM", x, y - gap)
        else
            PHP.frame:SetPoint("BOTTOM", anchor, "TOP", x, y + gap)
        end
        PHP.frame:SetSize(width, h)
        local layers = MSUF.UF and MSUF.UF.Layers
        PHP.frame:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(levelOffset, 7, 0)
            or (baseLevel + levelOffset))
        if PHP.textFrame then PHP.textFrame:SetFrameLevel(PHP.frame:GetFrameLevel() + 5) end
    end

    local edgeStamp = tostring(outline) .. ":" .. shape
    if PHP._edgeStamp ~= edgeStamp then
        PHP._edgeStamp = edgeStamp
        HideLegacyEdge()
        if outline > 0 then
            if shapeInfo then
                HideBarEdges()
                local shapeEdge = EnsureShapeEdge()
                if shapeEdge then
                    shapeEdge:ClearAllPoints()
                    shapeEdge:SetAllPoints(PHP.bar)
                    shapeEdge:SetTexture(shapeInfo.edge)
                    shapeEdge:SetVertexColor(0, 0, 0, ShapeOutlineAlpha(outline))
                    shapeEdge:Show()
                end
            else
                HideShapeEdge()
                ApplyBarOutline(outline)
            end
        else
            HideShapeEdge()
            HideBarEdges()
        end
    end

    local fg = ResolveTexture(b.playerHPBarTexture)
    local bgKey = b.playerHPBarBgTexture
    local bg = ResolveTexture((bgKey and bgKey ~= "") and bgKey or b.playerHPBarTexture)
    local bgAlpha = tonumber(b.playerHPBarBgAlpha) or 0.35
    if bgAlpha < 0 then bgAlpha = 0 elseif bgAlpha > 1 then bgAlpha = bgAlpha / 100 end
    local texStamp = tostring(fg) .. ":" .. tostring(bg) .. ":" .. tostring(bgAlpha) .. ":" .. shape
    if PHP._textureStamp ~= texStamp then
        PHP._textureStamp = texStamp
        if shapeInfo then
            PHP.bar:SetStatusBarTexture(shapeInfo.fill)
            ApplyShapeFill(PHP.bar, shapeInfo.axis)
            PHP.bg:SetTexture(shapeInfo.bg)
            if PHP.shapeEdge then
                PHP.shapeEdge:SetTexture(shapeInfo.edge)
                PHP.shapeEdge:SetVertexColor(0, 0, 0, ShapeOutlineAlpha(outline))
            end
        else
            ClearShapeFill(PHP.bar)
            HideShapeEdge()
            PHP.bar:SetStatusBarTexture(fg)
            PHP.bg:SetTexture(bg)
            HideLegacyEdge()
        end
        PHP.bg:SetVertexColor(0, 0, 0, bgAlpha)
        PHP.bar._phpR, PHP.bar._phpG, PHP.bar._phpB = nil, nil, nil
        PHP.bar._msufStatusR, PHP.bar._msufStatusG, PHP.bar._msufStatusB, PHP.bar._msufStatusA = nil, nil, nil, nil
    end

    local smooth = b.playerHPBarSmoothFill == true
    if PHP._smoothFill ~= smooth then
        PHP._smoothFill = smooth
        local common = MSUF.UFBarTextCommon
        if common and type(common.SetBarSmoothing) == "function" then
            common.SetBarSmoothing(PHP.bar, smooth)
        elseif PHP.bar then
            PHP.bar._msufSmoothInterp = nil
            PHP.bar._msufInterpolating = nil
        end
    end

    local colorMode = ColorMode(b)
    local dr, dg, db = 0, 0, 0
    if colorMode == "DARK" then dr, dg, db = DarkColor() end
    local colorStamp = colorMode .. ":" .. dr .. ":" .. dg .. ":" .. db
    if PHP._colorModeStamp ~= colorStamp then
        PHP._colorModeStamp = colorStamp
        PHP._colorMode = colorMode
        PHP._darkR, PHP._darkG, PHP._darkB = dr, dg, db
        PHP.bar._phpR, PHP.bar._phpG, PHP.bar._phpB = nil, nil, nil
        PHP.bar._msufStatusR, PHP.bar._msufStatusG, PHP.bar._msufStatusB, PHP.bar._msufStatusA = nil, nil, nil, nil
    end

    ApplyFont()
    ApplyTextLayout(b)
    PHP.frame:Show()
    PHP.visible = true
    return true
end

local function ApplyColor(hp, maxHP, event)
    local bar = PHP.bar
    if not bar then return end
    local common = MSUF.UFBarTextCommon
    local colorMode = PHP._colorMode or "GLOBAL"
    if colorMode == "CLASS" then
        local r, g, b
        if common and type(common.ClassColor) == "function" then
            r, g, b = common.ClassColor("player")
        end
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
            local _, class = UnitClass("player")
            local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            r, g, b = c and c.r or 0.1, c and c.g or 0.8, c and c.b or 0.1
        end
        ApplyCachedColor(bar, r, g, b)
        return
    elseif colorMode == "DARK" then
        ApplyCachedColor(bar, PHP._darkR or 0.07, PHP._darkG or 0.07, PHP._darkB or 0.07)
        return
    elseif colorMode == "GRADIENT" then
        local r, g, b = GradientColor(hp, maxHP, common)
        --- The shared helper evaluates UnitHealthPercent with a colour curve, which is
        --- SecretReturns while health is secret: such a colour goes to the C sink unread
        --- and leaves no change stamp behind.
        if IsSecretValue(r) == true or IsSecretValue(g) == true or IsSecretValue(b) == true then
            bar:SetStatusBarColor(r, g, b, 1)
            bar._phpR, bar._phpG, bar._phpB = nil, nil, nil
            bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
            return
        end
        ApplyCachedColor(bar, r, g, b)
        return
    end
    local playerFrame = GetPlayerFrame()
    if common and type(common.ApplyHealthStatusColor) == "function" then
        PHP.frame.unit = "player"
        PHP.frame.MSUFSpec = playerFrame and playerFrame.MSUFSpec or PHP.frame.MSUFSpec
        common.ApplyHealthStatusColor(bar, PHP.frame, "player", hp, maxHP, nil, event or "UNIT_HEALTH")
        return
    end
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local r, g, bl = c and c.r or 0.1, c and c.g or 0.8, c and c.b or 0.1
    ApplyCachedColor(bar, r, g, bl)
end

local function UpdateText(hp, maxHP)
    if not PHP.left then return end
    local b = _cpDB.bars or {}
    if not TextEnabled(b) then
        SetText(PHP.left, "")
        SetText(PHP.center, "")
        SetText(PHP.right, "")
        return
    end
    local hpSecret = IsSecretValue(hp) == true
    local maxSecret = IsSecretValue(maxHP) == true
    if not hpSecret and not maxSecret
        and UsePlayerText(b) and CopyRenderedPlayerText(hp, maxHP) then return end
    if (hpSecret or maxSecret) and UsePlayerText(b) and CopyPlayerTextBestEffort() then return end

    local left, center, right, delimiter, reverse
    local hideLeft, hideCenter, hideRight
    if UsePlayerText(b) then
        local player = PlayerConfig()
        player = player or {}
        left = tostring(player.textLeft or "NONE"):upper()
        center = tostring(player.textCenter or "NONE"):upper()
        right = tostring(player.textRight or player.hpTextMode or "CURPERCENT"):upper()
        delimiter = player.hpTextSeparator or ""
        reverse = player.hpTextReverse == true
        hideLeft = ReadHidePercentSymbol(player, "hpTextLeftHidePercentSymbol")
        hideCenter = ReadHidePercentSymbol(player, "hpTextCenterHidePercentSymbol")
        hideRight = ReadHidePercentSymbol(player, "hpTextRightHidePercentSymbol")
    else
        left = tostring(b.playerHPBarTextLeft or "NONE"):upper()
        center = tostring(b.playerHPBarTextCenter or "NONE"):upper()
        right = tostring(b.playerHPBarTextRight or "CURPERCENT"):upper()
        delimiter = b.playerHPBarTextSeparator or ""
        reverse = b.playerHPBarTextReverse == true
        hideLeft = ReadHidePercentSymbol(b, "playerHPBarTextLeftHidePercentSymbol")
        hideCenter = ReadHidePercentSymbol(b, "playerHPBarTextCenterHidePercentSymbol")
        hideRight = ReadHidePercentSymbol(b, "playerHPBarTextRightHidePercentSymbol")
    end
    if reverse then
        left, right = HP_TEXT_REVERSE[right] or right, HP_TEXT_REVERSE[left] or left
        center = HP_TEXT_REVERSE[center] or center
        hideLeft, hideRight = hideRight, hideLeft
    end
    if PHP._compactText == true then
        local compactMode = center ~= "NONE" and center or right
        local compactHide = center ~= "NONE" and hideCenter or hideRight
        if compactMode == "NONE" then
            compactMode = left
            compactHide = hideLeft
        end
        SetText(PHP.left, "")
        SetText(PHP.right, "")
        if compactMode == "NONE" then
            SetText(PHP.center, "")
        elseif hpSecret or maxSecret then
            local pct, secretPct = UnitPercent()
            SetPercentText(PHP.center, pct, secretPct, compactHide)
        else
            SetText(PHP.center, ModeText(compactMode, hp, maxHP, delimiter, compactHide))
        end
        return
    end
    if hpSecret or maxSecret then
        local pct, secretPct = UnitPercent()
        if left:find("PERCENT", 1, true) then
            SetPercentText(PHP.left, pct, secretPct, hideLeft)
        else
            SetText(PHP.left, "")
        end
        if center:find("PERCENT", 1, true) then
            SetPercentText(PHP.center, pct, secretPct, hideCenter)
        else
            SetText(PHP.center, "")
        end
        if right:find("PERCENT", 1, true) then
            SetPercentText(PHP.right, pct, secretPct, hideRight)
        else
            SetText(PHP.right, "")
        end
        return
    end
    SetText(PHP.left, ModeText(left, hp, maxHP, delimiter, hideLeft))
    SetText(PHP.center, ModeText(center, hp, maxHP, delimiter, hideCenter))
    SetText(PHP.right, ModeText(right, hp, maxHP, delimiter, hideRight))
end

local function Update(event)
    if not PHP.visible then return end
    local common = MSUF.UFBarTextCommon
    local hp, maxHP
    hp, maxHP = UnitHealth("player"), UnitHealthMax("player")
    local hpSecret = IsSecretValue(hp) == true
    local maxSecret = IsSecretValue(maxHP) == true
    if not hpSecret then hp = tonumber(hp) or 0 end
    if not maxSecret then
        maxHP = tonumber(maxHP) or 1
        if maxHP < 1 then maxHP = 1 end
    end
    local maxChanged = maxSecret or PHP._maxHP ~= maxHP
    local hpChanged = hpSecret or PHP._hp ~= hp
    if maxChanged then
        if common and type(common.SetBarMinMaxKnown) == "function" then
            common.SetBarMinMaxKnown(PHP.bar, maxHP, maxSecret)
        else
            PHP.bar:SetMinMaxValues(0, maxHP)
        end
        if maxSecret then PHP._maxHP = nil else PHP._maxHP = maxHP end
    end
    if hpChanged then
        if common and type(common.SetBarValueKnown) == "function" then
            common.SetBarValueKnown(PHP.bar, hp, hpSecret, true)
        else
            local interp = PHP.bar._msufSmoothInterp
            if interp then
                PHP.bar:SetValue(hp, interp)
                PHP.bar._msufInterpolating = true
            else
                PHP.bar:SetValue(hp)
                PHP.bar._msufInterpolating = nil
            end
        end
        if hpSecret then PHP._hp = nil else PHP._hp = hp end
        UpdateText(hp, maxHP)
    elseif maxSecret or PHP._textMaxHP ~= maxHP then
        UpdateText(hp, maxHP)
    end
    if maxSecret then PHP._textMaxHP = nil else PHP._textMaxHP = maxHP end
    ApplyColor(hp, maxHP, event)
end

local function ApplyResource(playerFrame)
    if ApplyLayout(playerFrame or GetPlayerFrame()) then
        PHP._hp = nil
        PHP._maxHP = nil
        PHP._textMaxHP = nil
        Update("FULL_REFRESH")
        if MSUF.ResourceVisibility then
            local owner = playerFrame or GetPlayerFrame()
            owner = owner._msufHealthVisualRoot or owner
            MSUF.ResourceVisibility.Bind(PHP.frame, owner, _cpDB.bars, "playerHPBar", "health")
            MSUF.ResourceVisibility.Bind(PHP.borderHost, owner, _cpDB.bars, "playerHPBar", "health")
        end
    end
end

local function InjectedAPI(api, name)
    if type(api) == "function" then return api end
    -- Preserve callable-table injection in existing whole-client fixtures.
    -- Missing and wrong-shaped providers still fail at binding readiness.
    local mt = getmetatable(api)
    if mt and type(mt.__call) == "function" then return api end
    error("MSUF: missing required dependency '" .. name .. "' required by " .. FILE, 2)
end
builders.PLAYER_HP_API = InjectedAPI

builders.PLAYER_HP_VISUAL = function(E)
    PHP = assert(E.PHP, "PlayerHP visual provider requires UF-owned state")
    CP, _cpDB = E.CP, E._cpDB
    UnitHealth, UnitHealthMax, UnitClass = E.UnitHealth, E.UnitHealthMax, E.UnitClass
    UnitHealth = InjectedAPI(UnitHealth, "PlayerHP injected UnitHealth")
    UnitHealthMax = InjectedAPI(UnitHealthMax, "PlayerHP injected UnitHealthMax")
    RAID_CLASS_COLORS = E.RAID_CLASS_COLORS
    CreateFrame, GetPlayerFrame, ResolveTexture = E.CreateFrame, E.GetPlayerFrame, E.ResolveTexture
    tonumber, type, tostring, pairs = E.tonumber or tonumber, E.type or type, E.tostring or tostring, E.pairs or pairs
    math_floor, string_format = E.math_floor or math_floor, E.string_format or string_format
    IsSecretValue = issecretvalue
    UnitHealthPercentAPI = UnitHealthPercent
    SCALE_100 = CurveConstants and CurveConstants.ScaleTo100
    return {
        PHP = PHP,
        Apply = ApplyResource,
        Create = Ensure,
        Update = Update,
        ApplyFont = ApplyFont,
        Hide = Hide,
    }
end
