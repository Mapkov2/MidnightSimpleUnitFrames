--- Castbars/MSUF_CastbarVisuals.lua
--- Profile-driven detail layout for castbar icons, spell text, time text, and
--- per-unit font/icon overrides.
---
--- This file is visual/layout only. It may inspect existing frame sizes and
--- SavedVariables, but it should not decide whether a unit is currently casting
--- or register spellcast events.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
MSUF.Castbars = MSUF.Castbars or {}
local Visuals = MSUF.Castbars.Visuals or {}
MSUF.Castbars.Visuals = Visuals

local issecretvalue = _G.issecretvalue

local function IsSecretValue(value)
    local fn = issecretvalue
    if type(fn) ~= "function" then
        fn = _G.issecretvalue
        if type(fn) == "function" then issecretvalue = fn end
    end
    return type(fn) == "function" and fn(value) == true
end

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" and not _G.MSUF_DB then
        _G.MSUF_EnsureDB()
    elseif type(_G.EnsureDB) == "function" and not _G.MSUF_DB then
        _G.EnsureDB()
    end
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    return _G.MSUF_DB.general
end

local function NormalizeUnit(unit)
    unit = tostring(unit or ""):lower()
    if unit:match("^boss") then return "boss" end
    if unit == "player" or unit == "target" or unit == "focus" then return unit end
    return nil
end

local function UnitFromFrame(frame)
    if not frame then return nil end
    local fromCore = _G.MSUF_GetCastbarUnitFromFrame
    local unit = type(fromCore) == "function" and fromCore(frame) or nil
    unit = NormalizeUnit(unit)
    if unit then return unit end
    if frame._msufIsBossCastbar then return "boss" end
    unit = NormalizeUnit(frame.unit or frame.MSUF_unit or frame._msufUnit)
    if unit then return unit end
    if frame == _G.MSUF_BossCastbarPreview or frame == _G.MSUF_BossCastbarPreview1 then return "boss" end
    local name = frame.GetName and frame:GetName() or nil
    if type(name) == "string" then
        if name:find("Boss", 1, true) or name:find("boss", 1, true) then return "boss" end
        if name:find("Player", 1, true) then return "player" end
        if name:find("Target", 1, true) then return "target" end
        if name:find("Focus", 1, true) then return "focus" end
    end
    return nil
end

local function PrefixForUnit(unit)
    if unit == "player" then return "castbarPlayer" end
    if unit == "target" then return "castbarTarget" end
    if unit == "focus" then return "castbarFocus" end
    if unit == "boss" then return "bossCast" end
    return nil
end

local function CastbarFrameInset(frame, g)
    if type(_G.MSUF_GetCastbarOutlineInset) == "function" then
        local inset = _G.MSUF_GetCastbarOutlineInset(frame, g)
        return tonumber(inset) or 0
    end
    local thickness = tonumber(g and g.castbarOutlineThickness)
    if thickness == nil then thickness = 1 end
    return thickness > 0 and 1 or 0
end

local function Num(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function KeyPart(value)
    if value == nil then return "" end
    return tostring(value)
end

local function BoolKey(value)
    return value and "1" or "0"
end

--- Width/height reads can be secret/protected on some clients. Treat those as
--- "unknown" and keep the caller's fallback instead of propagating wrappers.
local function RegionNumber(region, method, fallback)
    if not (region and method and region[method]) then return fallback end
    local value = region[method](region)
    if IsSecretValue(value) then return fallback end
    return Num(value, fallback)
end

local function DetailNum(g, prefix, suffix, globalKey, fallback)
    local value = prefix and g[prefix .. suffix] or nil
    if value == nil and globalKey then value = g[globalKey] end
    return Num(value, fallback)
end

local function DetailString(g, prefix, suffix, globalKey, fallback)
    local value = prefix and g[prefix .. suffix] or nil
    if (value == nil or value == "") and globalKey then value = g[globalKey] end
    if value == nil or value == "" then value = fallback end
    return tostring(value or fallback or "")
end

local function ShowIconForUnit(g, unit, prefix)
    local show = g.castbarShowIcon ~= false
    if unit == "boss" then
        if g.showBossCastIcon ~= nil then show = g.showBossCastIcon ~= false end
    elseif prefix and g[prefix .. "ShowIcon"] ~= nil then
        show = g[prefix .. "ShowIcon"] ~= false
    end
    return show
end

local function ShowSpellForUnit(g, unit, prefix)
    local show = g.castbarShowSpellName ~= false
    if unit == "boss" then
        if g.showBossCastName ~= nil then show = g.showBossCastName ~= false end
    elseif prefix and g[prefix .. "ShowSpellName"] ~= nil then
        show = g[prefix .. "ShowSpellName"] ~= false
    end
    return show
end

local function ShowTimeForUnit(g, unit)
    if unit == "player" then return g.showPlayerCastTime ~= false end
    if unit == "target" then return g.showTargetCastTime ~= false end
    if unit == "focus" then return g.showFocusCastTime ~= false end
    if unit == "boss" then return g.showBossCastTime ~= false end
    return true
end

local function NormalizeIconPosition(value)
    value = tostring(value or "LEFT"):upper():gsub("%s+", "_"):gsub("-", "_")
    if value == "INSIDELEFT" then value = "INSIDE_LEFT" end
    if value == "INSIDERIGHT" then value = "INSIDE_RIGHT" end
    if value == "RIGHT" or value == "INSIDE_LEFT" or value == "INSIDE_RIGHT" then return value end
    return "LEFT"
end

local function NormalizeTextPosition(value, fallback)
    value = tostring(value or fallback or "LEFT"):upper():gsub("%s+", "_"):gsub("-", "_")
    if value == "CENTER" or value == "RIGHT" or value == "ABOVE" or value == "BELOW" then return value end
    return "LEFT"
end

local function JustifyForTextPosition(position)
    if position == "LEFT" or position == "RIGHT" then return position end
    return "CENTER"
end

local function NormalizeJustify(value, fallback)
    value = tostring(value or fallback or "LEFT"):upper()
    if value == "CENTER" or value == "RIGHT" then return value end
    return "LEFT"
end

local function NormalizeSpellNameTruncate(value)
    value = tostring(value or "AUTO"):upper()
    if value == "CLIP" or value == "NONE" then return value end
    return "AUTO"
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ApplyIconZoom(texture, zoom)
    if not (texture and texture.SetTexCoord) then return end
    zoom = Clamp(zoom, 100, 200)
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function CastbarTextColor(g, prefix, suffix)
    local r = prefix and g[prefix .. suffix .. "ColorR"] or nil
    local green = prefix and g[prefix .. suffix .. "ColorG"] or nil
    local b = prefix and g[prefix .. suffix .. "ColorB"] or nil
    if r ~= nil or green ~= nil or b ~= nil then
        return Num(r, 1), Num(green, 1), Num(b, 1)
    end
    if type(_G.MSUF_GetCastbarTextColor) == "function" then
        local cr, cg, cb = _G.MSUF_GetCastbarTextColor()
        return cr or 1, cg or 1, cb or 1
    end
    if type(_G.MSUF_GetConfiguredFontColor) == "function" then
        local cr, cg, cb = _G.MSUF_GetConfiguredFontColor()
        return cr or 1, cg or 1, cb or 1
    end
    return 1, 1, 1
end

local function MonochromeFromFlags(flags)
    return tostring(flags or ""):upper():find("MONOCHROME", 1, true) ~= nil
end

local function SlugFromFlags(flags)
    return tostring(flags or ""):upper():find("SLUG", 1, true) ~= nil
end

local function ComposeFontFlags(outline, globalFlags)
    outline = tostring(outline or "GLOBAL"):upper()
    if outline == "GLOBAL" or outline == "" then
        return globalFlags or "OUTLINE"
    end
    local slug = SlugFromFlags(globalFlags)
    local flags = ""
    if outline == "THICKOUTLINE" and not slug then
        flags = "THICKOUTLINE"
    elseif outline ~= "NONE" then
        flags = "OUTLINE"
    end
    if slug then
        flags = flags ~= "" and (flags .. ",SLUG") or "SLUG"
    elseif MonochromeFromFlags(globalFlags) then
        flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME"
    end
    return flags
end

local function FontPathForSelection(value, globalPath)
    value = tostring(value or "GLOBAL")
    if value == "" or value == "GLOBAL" then return globalPath, nil end
    if value:find("\\", 1, true) or value:find("/", 1, true) then return value, value end
    local resolver = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey
    if type(resolver) == "function" then
        local path = resolver(value)
        if type(path) == "string" and path ~= "" then return path, value end
    end
    return value, value
end

--- The Fonts page writes its text shadow into the shared general table, but the
--- same controls also write a per-unit scope (MSUF_DB.player/target/focus/boss
--- with fontOverride). MSUF_FontRuntime refreshes exactly this unit's castbar
--- when that scope changes, so the castbar has to resolve the override too --
--- otherwise the refresh runs and the text keeps the shared value. Precedence
--- matches ResolveFontShadow in UnitFrames/Engine/MSUF_UF_Config.lua.
local function ResolveFontShadow(g, unit)
    local enabled = g.textBackdrop ~= false
    local alpha, x, y = _G.MSUF_ResolveFontShadowMetrics(
        g.fontShadowOpacity, g.fontShadowDistance, g.fontShadowStrength)
    local conf = unit and _G.MSUF_DB and _G.MSUF_DB[unit]
    if type(conf) == "table" and conf.fontOverride == true then
        if conf.textBackdrop ~= nil then enabled = conf.textBackdrop == true end
        if conf.fontShadowOpacity ~= nil or conf.fontShadowDistance ~= nil or conf.fontShadowStrength ~= nil then
            alpha, x, y = _G.MSUF_ResolveFontShadowMetrics(conf.fontShadowOpacity,
                conf.fontShadowDistance, conf.fontShadowStrength, alpha, x)
        end
    end
    return enabled, alpha, x, y
end

--- Castbar details can use global font settings or per-unit overrides. The
--- helper keeps all font-path, outline, color, alpha, and shadow rules in one
--- place so text layout functions only choose geometry.
local function ApplyFont(fontString, g, unit, prefix, suffix, size, colorSuffix)
    if not fontString then return true end
    local globalPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    local globalFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
    local selected = DetailString(g, prefix, suffix .. "Font", nil, "GLOBAL")
    local fontPath, fontKey = FontPathForSelection(selected, globalPath)
    local outline = DetailString(g, prefix, suffix .. "Outline", nil, "GLOBAL")
    local flags = ComposeFontFlags(outline, globalFlags)
    size = Clamp(size, 6, 128)
    local r, green, b = CastbarTextColor(g, prefix, colorSuffix)
    local alpha = Clamp(g.fontTextAlpha or 1, 0.7, 1)
    -- The target-class writer later forwards secret RGB values directly with
    -- the native three-argument SetTextColor path. Keep opacity on the region
    -- for this one FontString so those safe recolors cannot reset it to 100%.
    local targetTextAlpha = colorSuffix == "TargetName"
    local shadowEnabled, shadowAlpha, shadowX, shadowY = ResolveFontShadow(g, unit)
    if SlugFromFlags(flags) then shadowEnabled = false end
    local shadow = shadowEnabled and (KeyPart(shadowAlpha) .. ":" .. KeyPart(shadowX)) or "NONE"
    local fontCacheKey = fontPath .. "|"
        .. KeyPart(size) .. "|"
        .. KeyPart(flags) .. "|"
        .. KeyPart(r) .. "|"
        .. KeyPart(green) .. "|"
        .. KeyPart(b) .. "|"
        .. KeyPart(alpha) .. "|"
        .. shadow
    local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    if fontString._msufCastbarFontKey == fontCacheKey
        and fontString._msufCastbarFontEpoch == fontEpoch
    then
        return fontString._msufCastbarFontReady == true
    end

    local requestedReady = false
    if fontString.SetFont then
        local applyResolved = _G.MSUF_ApplyResolvedFont
        if type(applyResolved) == "function" then
            local ok, _, source = applyResolved(fontString, fontPath, size, flags, fontKey)
            requestedReady = ok == true and source ~= "fallback"
        else
            local ok, applied = pcall(fontString.SetFont, fontString, fontPath, size, flags)
            requestedReady = ok and applied ~= false
            local matches = _G.MSUF_FontApplicationMatches
            if requestedReady and type(matches) == "function" then
                requestedReady = matches(fontString, fontPath, size) == true
            end
            if not requestedReady and type(_G.MSUF_MarkFontApplyFailed) == "function" then
                _G.MSUF_MarkFontApplyFailed()
            end
        end
    end
    -- Cache the bounded attempt, including readable fallback, for this epoch.
    -- The coordinator owns retries by advancing the epoch.
    fontString._msufCastbarFontKey = fontCacheKey
    fontString._msufCastbarFontEpoch = fontEpoch
    fontString._msufCastbarFontReady = requestedReady

    if fontString.SetTextColor then fontString:SetTextColor(r, green, b, targetTextAlpha and 1 or alpha) end
    if targetTextAlpha and fontString.SetAlpha then fontString:SetAlpha(alpha) end

    if shadowEnabled then
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, shadowAlpha) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(shadowX, shadowY) end
    elseif fontString.SetShadowOffset then
        fontString:SetShadowOffset(0, 0)
    end
    return requestedReady
end

local function IconTexture(frame)
    return frame and (frame.icon or frame.Icon or (frame.IconFrame and (frame.IconFrame.Icon or frame.IconFrame.icon)) or frame.iconTexture or frame.IconTexture)
end

local function EnsureIconHost(frame)
    if frame._msufDetailIconHost then return frame._msufDetailIconHost end
    local host = CreateFrame("Frame", nil, frame)
    host:EnableMouse(false)
    frame._msufDetailIconHost = host
    return host
end

local ICON_BORDER_BACKDROPS = {}

local function IconBorderEdge(host, thickness)
    local scale = host and host.GetEffectiveScale and host:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    if _G.PixelUtil and type(_G.PixelUtil.GetNearestPixelSize) == "function" then
        local edge = _G.PixelUtil.GetNearestPixelSize(thickness, scale, 1)
        if edge and edge > 0 then return edge end
    end
    return thickness
end

local function IconBorderBackdrop(edge)
    local key = tostring(edge)
    local backdrop = ICON_BORDER_BACKDROPS[key]
    if not backdrop then
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = edge,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        }
        ICON_BORDER_BACKDROPS[key] = backdrop
    end
    return backdrop
end

local function EnsureIconBorder(frame, iconHost)
    local border = frame._msufDetailIconBorder
    if border and not border.SetBackdrop then
        for _, key in ipairs({ "top", "bottom", "left", "right" }) do
            if border[key] then border[key]:Hide() end
        end
        border = nil
    end
    if not border then
        border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        border:EnableMouse(false)
        frame._msufDetailIconBorder = border
    end
    border:ClearAllPoints()
    border:SetAllPoints(iconHost)
    if border.SetFrameLevel and iconHost.GetFrameLevel then
        border:SetFrameLevel((iconHost:GetFrameLevel() or 0) + 2)
    end
    return border
end

local function HideIconBorder(frame)
    local border = frame and frame._msufDetailIconBorder
    if not border then return end
    frame._msufDetailIconBorderKey = nil
    if border.SetBackdrop then border:SetBackdrop(nil) end
    border:Hide()
end

local function ApplyIconBorder(frame, host, g, prefix)
    local style = DetailString(g, prefix, "IconBorderStyle", nil, "NONE"):upper()
    local thickness = Clamp(DetailNum(g, prefix, "IconBorderThickness", nil, 0), 0, 8)
    if style == "NONE" or style == "" or thickness <= 0 then
        HideIconBorder(frame)
        return
    end
    local r, green, b, a = 0, 0, 0, 0.95
    if style == "CASTBAR" then
        r = Num(g.castbarBorderR, 0)
        green = Num(g.castbarBorderG, 0)
        b = Num(g.castbarBorderB, 0)
        a = Num(g.castbarBorderA, 1)
    end
    local key = style .. "|"
        .. KeyPart(thickness) .. "|"
        .. KeyPart(r) .. "|"
        .. KeyPart(green) .. "|"
        .. KeyPart(b) .. "|"
        .. KeyPart(a)
    if frame and frame._msufDetailIconBorderKey == key then
        return
    end
    if frame then
        frame._msufDetailIconBorderKey = key
    end
    local border = EnsureIconBorder(frame, host)
    local edge = IconBorderEdge(host, thickness)
    border:SetBackdrop(IconBorderBackdrop(edge))
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(r, green, b, a)
    border:Show()
end

--- Applies icon visibility and reserves statusbar space when the icon is outside
--- the bar. Inside-icon modes must not shrink the statusbar because text layout
--- still needs the full bar width.
local function ApplyIconLayout(frame, g, unit, prefix)
    local statusBar = frame and frame.statusBar
    if not statusBar then return end
    local icon = IconTexture(frame)
    local showIcon = ShowIconForUnit(g, unit, prefix)
    local barW = RegionNumber(frame, "GetWidth", nil) or RegionNumber(statusBar, "GetWidth", 250)
    local barH = RegionNumber(frame, "GetHeight", nil) or RegionNumber(statusBar, "GetHeight", 18)
    local size = DetailNum(g, prefix, "IconSize", "castbarIconSize", barH)
    if size == nil or size <= 0 then size = barH end
    size = Clamp(size, 6, 128)
    local zoom = Clamp(DetailNum(g, prefix, "IconZoom", "castbarIconZoom", 100), 100, 200)
    local spacing = Clamp(DetailNum(g, prefix, "IconSpacing", nil, 1), 0, 40)
    local x = DetailNum(g, prefix, "IconOffsetX", "castbarIconOffsetX", 0)
    local y = DetailNum(g, prefix, "IconOffsetY", "castbarIconOffsetY", 0)
    local position = NormalizeIconPosition(DetailString(g, prefix, "IconPosition", "castbarIconPosition", "LEFT"))
    local frameInset = CastbarFrameInset(frame, g)
    local layoutKey = KeyPart(unit) .. "|"
        .. BoolKey(icon ~= nil) .. "|"
        .. BoolKey(showIcon) .. "|"
        .. KeyPart(barW) .. "|"
        .. KeyPart(barH) .. "|"
        .. KeyPart(size) .. "|"
        .. KeyPart(zoom) .. "|"
        .. KeyPart(spacing) .. "|"
        .. KeyPart(x) .. "|"
        .. KeyPart(y) .. "|"
        .. position .. "|"
        .. KeyPart(frameInset) .. "|"
        .. KeyPart(DetailString(g, prefix, "IconBorderStyle", nil, "NONE")) .. "|"
        .. KeyPart(DetailNum(g, prefix, "IconBorderThickness", nil, 0)) .. "|"
        .. KeyPart(g.castbarBorderR) .. "|"
        .. KeyPart(g.castbarBorderG) .. "|"
        .. KeyPart(g.castbarBorderB) .. "|"
        .. KeyPart(g.castbarBorderA)
    if frame._msufDetailIconLayoutKey == layoutKey then
        return
    end
    frame._msufDetailIconLayoutKey = layoutKey

    if icon then
        if showIcon then
            local host = EnsureIconHost(frame)
            host:SetSize(size, size)
            host:ClearAllPoints()
            if position == "RIGHT" then
                host:SetPoint("RIGHT", frame, "RIGHT", x, y)
            elseif position == "INSIDE_RIGHT" then
                host:SetPoint("RIGHT", frame, "RIGHT", x - spacing, y)
            elseif position == "INSIDE_LEFT" then
                host:SetPoint("LEFT", frame, "LEFT", x + spacing, y)
            else
                host:SetPoint("LEFT", frame, "LEFT", x, y)
            end
            local resolveIconLevel = _G.MSUF_ResolveCastbarIconFrameLevel
            local manualIconLevel = type(resolveIconLevel) == "function" and resolveIconLevel(unit, g) or nil
            if host.SetFrameLevel and statusBar.GetFrameLevel then host:SetFrameLevel(manualIconLevel or ((statusBar:GetFrameLevel() or 0) + 6)) end
            host:Show()
            if icon.SetParent and ((not icon.GetParent) or icon:GetParent() ~= host) then icon:SetParent(host) end
            icon:ClearAllPoints()
            icon:SetAllPoints(host)
            ApplyIconZoom(icon, zoom)
            if icon.SetDrawLayer then icon:SetDrawLayer("OVERLAY", 7) end
            if icon.SetShown then icon:SetShown(true) else icon:Show() end
            ApplyIconBorder(frame, host, g, prefix)
        else
            if icon.SetShown then icon:SetShown(false) else icon:Hide() end
            if frame._msufDetailIconHost then frame._msufDetailIconHost:Hide() end
            HideIconBorder(frame)
        end
    else
        if frame._msufDetailIconHost then frame._msufDetailIconHost:Hide() end
        HideIconBorder(frame)
    end

    local leftInset, rightInset = 0, 0
    if showIcon and icon then
        if position == "LEFT" then
            leftInset = size + spacing
        elseif position == "RIGHT" then
            rightInset = size + spacing
        end
    end
    if leftInset + rightInset > barW - 8 then
        leftInset, rightInset = 0, 0
    end
    statusBar:ClearAllPoints()
    statusBar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftInset + frameInset, -frameInset)
    statusBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(rightInset + frameInset), frameInset)
    if statusBar.SetSize then
        statusBar:SetSize(math.max(1, barW - leftInset - rightInset - (frameInset * 2)), math.max(1, barH - (frameInset * 2)))
    end
    if frame.backgroundBar and frame.backgroundBar.SetAllPoints then
        frame.backgroundBar:ClearAllPoints()
        frame.backgroundBar:SetAllPoints(statusBar)
    end
end

local function SetTextIfChanged(fontString, text)
    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fontString, text or "")
    elseif fontString and fontString.SetText then
        fontString:SetText(text or "")
    end
end

local function AnchorFontString(fs, relativeTo, position, x, y, defaultJustify)
    if not (fs and relativeTo) then return end
    local justify
    if position == "CENTER" then
        justify = defaultJustify or "CENTER"
    elseif position == "RIGHT" then
        justify = defaultJustify or "RIGHT"
    elseif position == "ABOVE" or position == "BELOW" then
        justify = defaultJustify or "CENTER"
    else
        justify = defaultJustify or "LEFT"
    end
    if fs._msufCastbarAnchorRelativeTo == relativeTo
        and fs._msufCastbarAnchorPosition == position
        and fs._msufCastbarAnchorX == x
        and fs._msufCastbarAnchorY == y
        and fs._msufCastbarAnchorJustify == justify
    then
        return
    end
    fs._msufCastbarAnchorRelativeTo = relativeTo
    fs._msufCastbarAnchorPosition = position
    fs._msufCastbarAnchorX = x
    fs._msufCastbarAnchorY = y
    fs._msufCastbarAnchorJustify = justify
    fs:ClearAllPoints()
    if position == "CENTER" then
        fs:SetPoint("CENTER", relativeTo, "CENTER", x, y)
    elseif position == "RIGHT" then
        fs:SetPoint("RIGHT", relativeTo, "RIGHT", x, y)
    elseif position == "ABOVE" then
        fs:SetPoint("BOTTOM", relativeTo, "TOP", x, y + 2)
    elseif position == "BELOW" then
        fs:SetPoint("TOP", relativeTo, "BOTTOM", x, y - 2)
    else
        fs:SetPoint("LEFT", relativeTo, "LEFT", 2 + x, y)
    end
    -- SetJustifyH on a rect that is still unresolved after an anchor change
    -- leaves the FontString stuck on its previous alignment, so the Alignment
    -- setting stayed invisible until a later width/font change re-laid the
    -- string out. Blizzard resolves the rect first for the same reason (see
    -- EncounterTimelineTimerEventMixin:UpdateNameTextLayout). This runs on the
    -- cold path only: the cache above already returned for unchanged anchors.
    if fs.GetRect then fs:GetRect() end
    fs:SetJustifyH(justify)
end

local function ResolveTimeTextFontSize(g, prefix)
    local spellSize = DetailNum(g, prefix, "SpellNameFontSize", nil, Num(g.castbarSpellNameFontSize, 0))
    if not spellSize or spellSize <= 0 then spellSize = Num(g.fontSize, 14) end
    local baseSize = Num(g.castbarTimeFontSize, 0)
    if baseSize <= 0 then baseSize = spellSize end
    local size = DetailNum(g, prefix, "TimeFontSize", nil, baseSize)
    if not size or size <= 0 then size = baseSize end
    return Clamp(size, 6, 128)
end

local function ApproxTimeTextReserve(frame, g, prefix, statusW)
    local size = ResolveTimeTextFontSize(g, prefix)
    local format = tostring((frame and frame._msufCastTimeFormat) or DetailString(g, prefix, "TimeFormat", nil, "CURRENT") or "CURRENT"):upper()
    local widthFactor = (format == "CURRENT" or format == "") and 3.2 or 6.8
    local reserve = math.floor(size * widthFactor + 8.5)
    local cap = math.floor((tonumber(statusW) or 250) * 0.45 + 0.5)
    if cap > 0 and reserve > cap then reserve = cap end
    return math.max(44, reserve)
end

--- Spell text width is derived from remaining statusbar space after reserving
--- time text. This prevents the two font strings from fighting over the same
--- pixels when users increase font size.
local function ApplySpellTextLayout(frame, g, unit, prefix)
    local fs = frame and frame.castText
    local statusBar = frame and frame.statusBar
    if not (fs and statusBar) then return true end
    local show = ShowSpellForUnit(g, unit, prefix)
    fs:Show()
    fs:SetAlpha(show and 1 or 0)
    if not show then
        SetTextIfChanged(fs, "")
        return true
    end

    local baseSize = Num(g.castbarSpellNameFontSize, 0)
    if baseSize <= 0 then baseSize = Num(g.fontSize, 14) end
    local size = DetailNum(g, prefix, "SpellNameFontSize", nil, baseSize)
    if not size or size <= 0 then size = baseSize end
    local fontReady = ApplyFont(fs, g, unit, prefix, "SpellName", size, "SpellName")

    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end

    local x = DetailNum(g, prefix, "TextOffsetX", nil, 0)
    local y = DetailNum(g, prefix, "TextOffsetY", nil, 0)
    local position = NormalizeTextPosition(DetailString(g, prefix, "SpellNamePosition", nil, "LEFT"), "LEFT")
    AnchorFontString(fs, statusBar, position, x, y, JustifyForTextPosition(position))

    local statusW = RegionNumber(statusBar, "GetWidth", nil) or RegionNumber(frame, "GetWidth", 250)
    local maxWidth = DetailNum(g, prefix, "SpellNameMaxWidth", nil, 0)
    local truncate = NormalizeSpellNameTruncate(DetailString(g, prefix, "SpellNameTruncate", nil, "AUTO"))
    local shortening, shorteningMaxLen, shorteningReserved
    if type(_G.MSUF_GetCastbarSpellNameShorteningConfig) == "function" then
        shortening, shorteningMaxLen, shorteningReserved = _G.MSUF_GetCastbarSpellNameShorteningConfig(frame)
    end
    local function AutoWidth()
        local reserve = shortening and (tonumber(shorteningReserved) or 0) or 0
        if frame.timeText and frame.timeText.IsShown and frame.timeText:IsShown() then
            local timeW = RegionNumber(frame.timeText, "GetStringWidth", nil)
            reserve = reserve + (timeW and math.max(44, timeW + 10) or ApproxTimeTextReserve(frame, g, prefix, statusW))
        end
        return math.max(20, statusW - reserve - 8)
    end
    local width
    if truncate == "NONE" then
        width = math.max(statusW, 1000)
    elseif truncate == "CLIP" then
        width = (maxWidth and maxWidth > 0) and maxWidth or AutoWidth()
    else
        width = AutoWidth()
    end
    if shortening then
        -- Restricted unit cast names can be secret in combat and therefore
        -- cannot legally pass through Lua substring/concatenation. A bounded
        -- one-line FontString gives those values the same renderer-side
        -- truncation contract as the non-secret shortener, on this cold layout
        -- path only.
        local shorteningWidth = math.floor(((tonumber(shorteningMaxLen) or 30) * size * 0.60) + 6.5)
        shorteningWidth = math.max(40, math.min(800, shorteningWidth))
        width = math.min(width, shorteningWidth)
    end
    if fs.SetWidth then fs:SetWidth(width) end

    if type(_G.MSUF_RefreshCastbarSpellNameText) == "function" then
        _G.MSUF_RefreshCastbarSpellNameText(frame)
    elseif frame._msufRawCastText ~= nil then
        SetTextIfChanged(fs, frame._msufRawCastText)
    end
    return fontReady
end

local function ApplyTimeTextLayout(frame, g, unit, prefix)
    local fs = frame and frame.timeText
    local statusBar = frame and frame.statusBar
    if not (fs and statusBar) then return true end
    local show = ShowTimeForUnit(g, unit)
    fs:Show()
    fs:SetAlpha(show and 1 or 0)
    if not show then
        SetTextIfChanged(fs, "")
        return true
    end

    local size = ResolveTimeTextFontSize(g, prefix)
    local fontReady = ApplyFont(fs, g, unit, prefix, "Time", size, "Time")

    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    local fallbackX = unit == "boss" and 0 or -2
    local x = DetailNum(g, prefix, "TimeOffsetX", unit ~= "boss" and "castbarPlayerTimeOffsetX" or nil, fallbackX)
    local y = DetailNum(g, prefix, "TimeOffsetY", unit ~= "boss" and "castbarPlayerTimeOffsetY" or nil, 0)
    if unit == "boss" then x = -2 + (tonumber(x) or 0) end
    local position = NormalizeTextPosition(DetailString(g, prefix, "TimePosition", nil, "RIGHT"), "RIGHT")
    AnchorFontString(fs, statusBar, position, x, y, JustifyForTextPosition(position))
    return fontReady
end

local function ApplyCastTargetTextLayout(frame, g, unit, prefix)
    local fs = frame and frame.castTargetText
    local statusBar = frame and frame.statusBar
    if not (fs and statusBar) then return true end

    local size = DetailNum(g, prefix, "TargetNameFontSize", nil, 10)
    if not size or size <= 0 then size = 10 end
    local fontReady = ApplyFont(fs, g, unit, prefix, "TargetName", size, "TargetName")

    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end

    local x = DetailNum(g, prefix, "TargetNameOffsetX", nil, 0)
    local y = DetailNum(g, prefix, "TargetNameOffsetY", nil, 1)
    local position = NormalizeTextPosition(DetailString(g, prefix, "TargetNamePosition", nil, "BELOW"), "BELOW")
    local justify = NormalizeJustify(DetailString(g, prefix, "TargetNameAlign", nil, "RIGHT"), "RIGHT")
    local statusW = RegionNumber(statusBar, "GetWidth", 250)
    if fs.SetWidth then fs:SetWidth(math.max(20, statusW - 4)) end
    AnchorFontString(fs, statusBar, position, x, y, justify)
    return fontReady
end

--- Public visual entry for one frame. Call this after frame creation, anchoring,
--- profile changes, or castbar size changes.
local function ApplyCastbarDetailLayout(frame, forcedUnit, general)
    if not (frame and frame.statusBar) then return end
    local unit = NormalizeUnit(forcedUnit) or UnitFromFrame(frame)
    local prefix = PrefixForUnit(unit)
    if not prefix then return end
    local g = general or GeneralDB()
    ApplyIconLayout(frame, g, unit, prefix)
    local timeFontReady = ApplyTimeTextLayout(frame, g, unit, prefix)
    local spellFontReady = ApplySpellTextLayout(frame, g, unit, prefix)
    local targetFontReady = ApplyCastTargetTextLayout(frame, g, unit, prefix)
    frame._msufCastbarDetailLayoutUnit = unit
    frame._msufCastbarDetailLayoutFontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    frame._msufCastbarDetailLayoutVisualRev = tonumber(_G.MSUF__castbarStyleGlobalRev) or 1
    frame._msufCastbarDetailFontsReady = timeFontReady ~= false
        and spellFontReady ~= false
        and targetFontReady ~= false
    if frame._msufIsPreview ~= true and type(_G.MSUF_RefreshCastTargetText) == "function" then
        _G.MSUF_RefreshCastTargetText(frame)
    end
end

ExportPublic("MSUF_ApplyCastbarDetailLayout", ApplyCastbarDetailLayout)
ExportPublic("MSUF_ApplyCastbarDetailTextLayout", ApplyCastbarDetailLayout)
Visuals.ApplyDetailLayout = ApplyCastbarDetailLayout

--- Refreshes one existing frame without touching cast state. This is used by the
--- global visual refresh and by profile/style changes.
local function RefreshCastbarFrame(frame, forcedUnit, general)
    if not (frame and frame.statusBar) then
        return
    end

    if type(_G.MSUF_ApplyCastbarOutline) == "function" then
        _G.MSUF_ApplyCastbarOutline(frame, false)
    end

    if type(_G.MSUF_KickReady_ApplyLayout) == "function" then
        _G.MSUF_KickReady_ApplyLayout(frame)
    end

    if type(_G.MSUF_KickReady_RefreshFrame) == "function" and frame.MSUF_castActive then
        _G.MSUF_KickReady_RefreshFrame(frame, nil)
    end

    if frame.backgroundBar and type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
        local red, green, blue, alpha = _G.MSUF_GetCastbarBackgroundColor()
        frame.backgroundBar:SetVertexColor(red or 0.176, green or 0.176, blue or 0.176, alpha or 1)
    end

    if frame.statusBar and type(_G.MSUF_RefreshCastbarStyleCache) == "function" then
        _G.MSUF_RefreshCastbarStyleCache(frame)

        if frame.MSUF_cachedCastbarTexture then
            frame.statusBar:SetStatusBarTexture(frame.MSUF_cachedCastbarTexture)
        end

        if frame.backgroundBar and frame.MSUF_cachedCastbarBackgroundTexture then
            frame.backgroundBar:SetTexture(frame.MSUF_cachedCastbarBackgroundTexture)
        end
    end

    if type(_G.MSUF_RoundedCastbar_RefreshFrame) == "function" then
        _G.MSUF_RoundedCastbar_RefreshFrame(frame)
    end

    ApplyCastbarDetailLayout(frame, forcedUnit, general)
end
ExportPublic("MSUF_RefreshCastbarFrame", RefreshCastbarFrame)
Visuals.RefreshFrame = RefreshCastbarFrame
