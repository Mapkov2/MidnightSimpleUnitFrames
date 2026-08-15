--- ClassPower/MSUF_CP_PlayerHP.lua
--- Optional second Player HP bar owned by Class Resources.
--- Loaded before the controller; exposes a small builder so the controller does
--- not carry the feature implementation or hit Lua's chunk-local limit.
---
--- The controller injects WoW APIs, cached DB access, and shared unit-frame
--- helpers through `E`. Keep this file as a feature builder: it may create and
--- maintain the optional HP bar, but it must not create its own event frame or
--- take ownership of ClassPower's refresh loop.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_CORE_BUILDERS", builders)
end

--- Global abbreviation style (see Runtime/MSUF_NumberFormat.lua). Registered at
--- file scope, not inside the builder, so rebuilding the HP bar never stacks a
--- second sink.
local NUM_OPTS = nil
do
    local NumberFormat = MSUF.NumberFormat
    if NumberFormat and NumberFormat.Register then
        NumberFormat.Register(function(options) NUM_OPTS = options end)
    end
end

--- Builds closures bound to the ClassPower controller environment. Nothing in
--- this file should touch frames at load time; actual frame creation waits until
--- the player frame exists and the feature is enabled.
builders.PLAYER_HP = function(E)
    local PHP = E.PHP or {
        frame = nil,
        bar = nil,
        bg = nil,
        shapeEdge = nil,
        borderHost = nil,
        borderEdges = nil,
        textFrame = nil,
        left = nil,
        center = nil,
        right = nil,
        visible = false,
    }

    local CP = E.CP
    local _cpDB = E._cpDB
    local UnitHealth = E.UnitHealth
    local UnitHealthMax = E.UnitHealthMax
    local UnitClass = E.UnitClass
    local RAID_CLASS_COLORS = E.RAID_CLASS_COLORS
    local CreateFrame = E.CreateFrame
    local GetPlayerFrame = E.GetPlayerFrame
    local ResolveTexture = E.ResolveTexture
    local tonumber = E.tonumber or tonumber
    local type = E.type or type
    local tostring = E.tostring or tostring
    local pairs = E.pairs or pairs
    local math_floor = E.math_floor or math.floor
    local string_format = E.string_format or string.format
    local issecretvalue = _G.issecretvalue or function(_) return false end
    local UnitHealthPercent = _G.UnitHealthPercent
    local SCALE_100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100
    local POWER_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
    local POWER_SHAPE_TEXTURES = {
        ROUND = {
            fill = POWER_SHAPE_MEDIA .. "power_round_fill.tga",
            bg = POWER_SHAPE_MEDIA .. "power_round_bg.tga",
            edge = POWER_SHAPE_MEDIA .. "power_round_edge.tga",
        },
        CRYSTAL = {
            fill = POWER_SHAPE_MEDIA .. "power_crystal_fill.tga",
            bg = POWER_SHAPE_MEDIA .. "power_crystal_bg.tga",
            edge = POWER_SHAPE_MEDIA .. "power_crystal_edge.tga",
        },
        ORB = {
            fill = POWER_SHAPE_MEDIA .. "pip_circle_fill.tga",
            bg = POWER_SHAPE_MEDIA .. "pip_circle_bg.tga",
            edge = POWER_SHAPE_MEDIA .. "pip_circle_edge.tga",
            axis = "VERTICAL",
        },
    }

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

    local HP_TEXT_DELIMITERS = {
        [""] = " ",
        ["-"] = " - ",
        ["/"] = " / ",
        ["\\"] = " \\ ",
        ["|"] = " | ",
        ["<"] = " < ",
        [">"] = " > ",
        ["~"] = " ~ ",
        [":"] = " : ",
    }

    local function Enabled()
        local b = _cpDB.bars or {}
        return b.playerHPBarEnabled == true
    end

    local function UsePlayerText(b)
        return b and b.playerHPBarUsePlayerText ~= false
    end

    --- Player HP text can either use its own ClassPower settings or mirror the
    --- normal player-frame text. Centralizing that bridge prevents later runtime
    --- code from scattering direct profile reads across the hot health update.
    local function PlayerConfig()
        local db = MSUF_DB
        return db and db.player or nil, db and db.general or nil
    end

    --- showHP is the current unit-frame setting. Preserve support for profiles
    --- that only carry the old showHPText alias, but never let that alias veto
    --- an explicit current value.
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

    local function NormalizeClassPowerShape(value)
        value = tostring(value or "BAR"):upper()
        if value == "CIRCLE" or value == "DIAMOND" or value == "HEX" then return value end
        return "BAR"
    end

    local function NormalizePowerShape(value)
        value = tostring(value or "BAR"):upper()
        if value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
        return "BAR"
    end

    local function NormalizeHPShape(value)
        value = tostring(value or "BAR"):upper()
        if value == "FOLLOW_POWER" or value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
        return "BAR"
    end

    --- FOLLOW_POWER means "look like the detached player power bar if one is in
    --- use". This keeps the two auxiliary bars visually linked without making
    --- the HP bar depend on the power-bar element's internal objects.
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

    local function ShapeOutlineAlpha(value)
        value = tonumber(value) or 0
        if value <= 0 then return 0 end
        if value >= 8 then return 1 end
        return 0.49 + (value * 0.065)
    end

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
        local abbrev = _G.AbbreviateShortNumber or _G.AbbreviateLargeNumbers
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
        local g = _G.MSUF_DB and _G.MSUF_DB.general
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

    --- Some clients can return protected/secret health values. When raw values
    --- are unavailable, use Blizzard's percent helper if it exposes a safe
    --- scalar and let text fall back to percent-only output.
    local function UnitPercent()
        if not UnitHealthPercent then return nil end
        local pct
        if SCALE_100 then
            pct = UnitHealthPercent("player", true, SCALE_100)
        else
            pct = UnitHealthPercent("player", true)
        end
        if issecretvalue(pct) == true then return nil end
        pct = tonumber(pct)
        if not pct then return nil end
        if pct <= 1 then pct = pct * 100 end
        if pct < 0 then return 0 end
        if pct > 100 then return 100 end
        return math_floor(pct + 0.5)
    end

    local function DarkColor()
        local ns = _G.MSUF_NS
        local cache = ns and ns.UF and ns.UF.Config and ns.UF.Config.settingsCache
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
        if issecretvalue(hp) == true or issecretvalue(maxHP) == true then
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
        if issecretvalue(text) == true then
            fs._msufPHPText = nil
            fs:SetText(text)
            return
        end
        text = text or ""
        if fs._msufPHPText == text then return end
        fs._msufPHPText = text
        fs:SetText(text)
    end

    --- Mirroring the already-rendered player-frame text avoids reimplementing
    --- every text mode twice. The runtime stamp check makes sure we only copy
    --- text that was rendered for the same health inputs.
    local function RenderedTextMatches(rt, hp, maxHP)
        if not (rt and rt.healthSlotCount and rt.healthSlotCount > 0) then return false end
        local keyHP, keyMax = false, false
        local mode = rt.healthDispatchKeyMode or 0
        if mode == 1 then
            keyHP = hp
        elseif mode == 2 then
            keyMax = maxHP
        elseif mode == 3 then
            keyHP, keyMax = hp, maxHP
        elseif mode == 4 or mode == 5 then
            keyHP = Percent(hp, maxHP)
            keyMax = mode == 5 and maxHP or false
        end
        local missing
        if rt.healthNeedsMissing == true then
            missing = (tonumber(maxHP) or 0) - (tonumber(hp) or 0)
            if missing < 0 then missing = 0 end
        end
        return rt._lastHealthTextHP == keyHP
            and rt._lastHealthTextMax == keyMax
            and rt._lastHealthTextMissing == missing
    end

    local function ApplyCopiedTextColor(dst, r, g, b, a)
        if not (dst and r and dst.SetTextColor) then return end
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
            if text == nil then text = "" end
            r, g, b, a = src._msufTextR, src._msufTextG, src._msufTextB, src._msufTextA
            if r == nil and src.GetTextColor then
                r, g, b, a = src:GetTextColor()
            end
        end
        return text, r, g, b, a
    end

    local function CopyTextSlot(src, dst)
        if not dst then return false end
        local text, r, g, b, a = ReadTextSlot(src)
        ApplyCopiedTextColor(dst, r, g, b, a)
        SetText(dst, text)
        return true
    end

    local function CopyCompactText(playerFrame)
        if not (PHP.center and playerFrame) then return false end
        local text, r, g, b, a = ReadTextSlot(playerFrame.hpTextCenter)
        if text == "" then text, r, g, b, a = ReadTextSlot(playerFrame.hpTextRight) end
        if text == "" then text, r, g, b, a = ReadTextSlot(playerFrame.hpTextLeft) end
        ApplyCopiedTextColor(PHP.center, r, g, b, a)
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
        if UsePlayerText(b) then
            local player, general = PlayerConfig()
            size = player and player.hpFontSize or nil
            if size == nil then size = general and general.hpFontSize or nil end
        end
        size = Clamp(size, 14, 6, 48)
        local fontPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or _G.STANDARD_TEXT_FONT
        local fontFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
        if not fontPath or fontPath == "" then fontPath = "Fonts\\FRIZQT__.TTF" end
        if not fontFlags or fontFlags == "" then fontFlags = "OUTLINE" end
        local resolveSafe = _G.MSUF_ResolveSafeFontPath
        if type(resolveSafe) == "function" then
            local g = _G.MSUF_DB and _G.MSUF_DB.general
            fontPath = resolveSafe(fontPath, size, fontFlags, g and g.fontKey)
        end
        local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
        local stamp = tostring(fontPath) .. ":" .. tostring(size) .. ":" .. tostring(fontFlags)
            .. ":" .. tostring(fontEpoch)
        if PHP._fontStamp == stamp then return end
        local function FontApplied(fs, path, px, fontFlags)
            if type(fs.GetFont) ~= "function" then return true end
            local actual, actualSize, actualFlags = fs:GetFont()
            if not actual then return false end
            if actualSize and math.abs((tonumber(actualSize) or 0) - px) > 0.01 then return false end
            if (actualFlags or "") ~= (fontFlags or "") then return false end
            if actual == path then return true end
            local matches = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
            if type(matches) == "function" then return matches(path, actual) == true end
            return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(path or ""):gsub("/", "\\"):lower()
        end
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        for _, fs in pairs({ PHP.left, PHP.center, PHP.right }) do
            if fs.SetFont then
                local applyResolved = _G.MSUF_ApplyResolvedFont
                if type(applyResolved) == "function" then
                    applyResolved(fs, fontPath, size, fontFlags, general and general.fontKey)
                else
                    local ok, applied = pcall(fs.SetFont, fs, fontPath, size, fontFlags)
                    if not ok or applied == false or not FontApplied(fs, fontPath, size, fontFlags) then
                        pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, fontFlags)
                        if type(_G.MSUF_MarkFontApplyFailed) == "function" then _G.MSUF_MarkFontApplyFailed() end
                    end
                end
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

    --- Cold creation path. The bar is parented to the player frame so frame
    --- lifetime, scale, and secure anchoring stay with the owning unit frame.
    local function Ensure(playerFrame)
        if PHP.frame then return true end
        if not playerFrame then return false end

        local f = CreateFrame("Frame", "MSUF_ClassPowerPlayerHealthBar", playerFrame)
        f:Hide()
        PHP.frame = f

        local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetAllPoints(f)
        bg:SetColorTexture(0, 0, 0, 0.35)
        PHP.bg = bg

        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetStatusBarTexture(ResolveTexture(nil))
        PHP.bar = bar

        local tf = CreateFrame("Frame", nil, f)
        tf:SetAllPoints(f)
        PHP.textFrame = tf

        local left = tf:CreateFontString(nil, "OVERLAY")
        left:SetJustifyH("LEFT")
        if left.SetJustifyV then left:SetJustifyV("MIDDLE") end
        PHP.left = left

        local center = tf:CreateFontString(nil, "OVERLAY")
        center:SetJustifyH("CENTER")
        if center.SetJustifyV then center:SetJustifyV("MIDDLE") end
        PHP.center = center

        local right = tf:CreateFontString(nil, "OVERLAY")
        right:SetJustifyH("RIGHT")
        if right.SetJustifyV then right:SetJustifyV("MIDDLE") end
        PHP.right = right

        ApplyFont()
        return true
    end

    local function EnsureShapeEdge()
        if PHP.shapeEdge then return PHP.shapeEdge end
        if not PHP.bar then return nil end
        local edge = PHP.bar:CreateTexture(nil, "OVERLAY", nil, 7)
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
            PHP.borderHost = CreateFrame("Frame", nil, parent)
            PHP.borderHost:EnableMouse(false)
        elseif PHP.borderHost.GetParent and PHP.borderHost:GetParent() ~= parent then
            PHP.borderHost:SetParent(parent)
            PHP.borderEdges = nil
            PHP._barOutlineThickness = nil
        end
        if PHP.borderEdges and PHP.borderEdges._host == PHP.borderHost then return PHP.borderEdges, PHP.borderHost end
        local edges = {}
        for i = 1, 4 do
            local edge = PHP.borderHost:CreateTexture(nil, "OVERLAY", nil, 6)
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

    --- Layout/config path. This can run on profile changes and ClassPower
    --- refreshes, so every expensive frame operation is guarded by stamps.
    local function ApplyLayout(playerFrame)
        local b = _cpDB.bars or {}
        if not Enabled() then
            if PHP.frame then PHP.frame:Hide() end
            HideBarEdges()
            HideShapeEdge()
            PHP.visible = false
            return false
        end
        if not Ensure(playerFrame) then return false end

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
        local layoutStamp = tostring(anchor) .. ":" .. anchorMode .. ":" .. shape .. ":" .. width .. ":" .. h .. ":" .. gap .. ":" .. x .. ":" .. y .. ":" .. levelOffset .. ":" .. baseLevel
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
            local common = _G.MSUF_NS and _G.MSUF_NS.UFBarTextCommon
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

    --- Color is part of the health hotpath. Prefer the shared unit-frame color
    --- helpers when available so reaction/class/gradient behavior stays aligned
    --- with the main player HP bar.
    local function ApplyColor(hp, maxHP, event)
        local bar = PHP.bar
        if not bar then return end
        local common = _G.MSUF_NS and _G.MSUF_NS.UFBarTextCommon
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

    --- Text update is deliberately tolerant: copy main-frame text when it is
    --- current, synthesize text when safe numeric values exist, and degrade to a
    --- percent-only display when health values are protected.
    local function UpdateText(hp, maxHP)
        if not PHP.left then return end
        local b = _cpDB.bars or {}
        if not TextEnabled(b) then
            SetText(PHP.left, "")
            SetText(PHP.center, "")
            SetText(PHP.right, "")
            return
        end
        local hpSecret = issecretvalue(hp) == true
        local maxSecret = issecretvalue(maxHP) == true
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
                local pct = UnitPercent()
                SetText(PHP.center, PercentText(pct, compactHide))
            else
                SetText(PHP.center, ModeText(compactMode, hp, maxHP, delimiter, compactHide))
            end
            return
        end
        if hpSecret or maxSecret then
            local pct = UnitPercent()
            SetText(PHP.left, left:find("PERCENT", 1, true) and PercentText(pct, hideLeft) or "")
            SetText(PHP.center, center:find("PERCENT", 1, true) and PercentText(pct, hideCenter) or "")
            SetText(PHP.right, right:find("PERCENT", 1, true) and PercentText(pct, hideRight) or "")
            return
        end
        SetText(PHP.left, ModeText(left, hp, maxHP, delimiter, hideLeft))
        SetText(PHP.center, ModeText(center, hp, maxHP, delimiter, hideCenter))
        SetText(PHP.right, ModeText(right, hp, maxHP, delimiter, hideRight))
    end

    --- Health event entry. Keep this small and cache-aware because ClassPower
    --- calls it from frequent UNIT_HEALTH/UNIT_MAXHEALTH style updates.
    local function Update(event)
        if not PHP.visible or not PHP.bar then return end
        local common = _G.MSUF_NS and _G.MSUF_NS.UFBarTextCommon
        local hp, maxHP
        if type(UnitHealth) == "function" then hp = UnitHealth("player") end
        if type(UnitHealthMax) == "function" then maxHP = UnitHealthMax("player") end
        local hpSecret = issecretvalue(hp) == true
        local maxSecret = issecretvalue(maxHP) == true
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

    --- Full refresh re-applies layout/config first, then clears cached health
    --- values so the following update repaints min/max/value/text/color.
    local function Refresh(playerFrame)
        if ApplyLayout(playerFrame or GetPlayerFrame()) then
            PHP._hp = nil
            PHP._maxHP = nil
            PHP._textMaxHP = nil
            Update("FULL_REFRESH")
        end
    end

    return {
        PHP = PHP,
        Refresh = Refresh,
        Update = Update,
        ApplyFont = ApplyFont,
    }
end
