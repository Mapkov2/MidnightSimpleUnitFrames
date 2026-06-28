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

local previousUpdateCastbarVisuals = _G.MSUF_UpdateCastbarVisuals
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

local function Num(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
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

local function ComposeFontFlags(outline, globalFlags)
    outline = tostring(outline or "GLOBAL"):upper()
    if outline == "GLOBAL" or outline == "" then
        return globalFlags or "OUTLINE"
    end
    local flags = ""
    if outline == "THICKOUTLINE" then
        flags = "THICKOUTLINE"
    elseif outline ~= "NONE" then
        flags = "OUTLINE"
    end
    if MonochromeFromFlags(globalFlags) then
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

--- Castbar details can use global font settings or per-unit overrides. The
--- helper keeps all font-path, outline, color, alpha, and shadow rules in one
--- place so text layout functions only choose geometry.
local function ApplyFont(fontString, g, prefix, suffix, size, colorSuffix)
    if not fontString then return end
    local globalPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    local globalFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
    local selected = DetailString(g, prefix, suffix .. "Font", nil, "GLOBAL")
    local fontPath, fontKey = FontPathForSelection(selected, globalPath)
    local outline = DetailString(g, prefix, suffix .. "Outline", nil, "GLOBAL")
    local flags = ComposeFontFlags(outline, globalFlags)
    size = Clamp(size, 6, 128)
    if fontString.SetFont then
        pcall(fontString.SetFont, fontString, fontPath, size, flags)
    end

    local r, green, b = CastbarTextColor(g, prefix, colorSuffix)
    local alpha = Clamp(g.fontTextAlpha or 1, 0.7, 1)
    if fontString.SetTextColor then fontString:SetTextColor(r, green, b, alpha) end

    if g.textBackdrop ~= false then
        local shadow = tostring(g.fontShadowStrength or "NORMAL"):upper()
        local sa, sx, sy = 1, 1, -1
        if shadow == "SOFT" then
            sa, sx, sy = 0.55, 1, -1
        elseif shadow == "DEEP" then
            sa, sx, sy = 1, 2, -2
        end
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, sa) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(sx, sy) end
    elseif fontString.SetShadowOffset then
        fontString:SetShadowOffset(0, 0)
    end
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

local function EnsureIconBorder(frame)
    if frame._msufDetailIconBorder then return frame._msufDetailIconBorder end
    local border = {}
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        border[key] = frame:CreateTexture(nil, "OVERLAY", nil, 8)
        border[key]:SetColorTexture(0, 0, 0, 1)
        border[key]:Hide()
    end
    frame._msufDetailIconBorder = border
    return border
end

local function HideIconBorder(frame)
    local border = frame and frame._msufDetailIconBorder
    if not border then return end
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        if border[key] then border[key]:Hide() end
    end
end

local function ApplyIconBorder(frame, host, g, prefix)
    local style = DetailString(g, prefix, "IconBorderStyle", nil, "NONE"):upper()
    if style == "NONE" or style == "" then
        HideIconBorder(frame)
        return
    end
    local border = EnsureIconBorder(frame)
    local thickness = style == "CASTBAR" and Clamp(g.castbarOutlineThickness or 1, 1, 8) or 1
    local r, green, b, a = 0, 0, 0, 0.95
    if style == "CASTBAR" then
        r = Num(g.castbarBorderR, 0)
        green = Num(g.castbarBorderG, 0)
        b = Num(g.castbarBorderB, 0)
        a = Num(g.castbarBorderA, 1)
    end
    border.top:ClearAllPoints()
    border.top:SetPoint("TOPLEFT", host, "TOPLEFT", -thickness, thickness)
    border.top:SetPoint("TOPRIGHT", host, "TOPRIGHT", thickness, thickness)
    border.top:SetHeight(thickness)
    border.bottom:ClearAllPoints()
    border.bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -thickness, -thickness)
    border.bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", thickness, -thickness)
    border.bottom:SetHeight(thickness)
    border.left:ClearAllPoints()
    border.left:SetPoint("TOPLEFT", host, "TOPLEFT", -thickness, thickness)
    border.left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -thickness, -thickness)
    border.left:SetWidth(thickness)
    border.right:ClearAllPoints()
    border.right:SetPoint("TOPRIGHT", host, "TOPRIGHT", thickness, thickness)
    border.right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", thickness, -thickness)
    border.right:SetWidth(thickness)
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        border[key]:SetVertexColor(r, green, b, a)
        border[key]:Show()
    end
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
    local spacing = Clamp(DetailNum(g, prefix, "IconSpacing", nil, 1), 0, 40)
    local x = DetailNum(g, prefix, "IconOffsetX", "castbarIconOffsetX", 0)
    local y = DetailNum(g, prefix, "IconOffsetY", "castbarIconOffsetY", 0)
    local position = NormalizeIconPosition(DetailString(g, prefix, "IconPosition", "castbarIconPosition", "LEFT"))

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
            if host.SetFrameLevel and statusBar.GetFrameLevel then host:SetFrameLevel((statusBar:GetFrameLevel() or 0) + 6) end
            host:Show()
            if icon.SetParent and ((not icon.GetParent) or icon:GetParent() ~= host) then icon:SetParent(host) end
            icon:ClearAllPoints()
            icon:SetAllPoints(host)
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
    statusBar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftInset, -1)
    statusBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -rightInset, 1)
    if statusBar.SetSize then
        statusBar:SetSize(math.max(1, barW - leftInset - rightInset), math.max(1, barH - 2))
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
    fs:ClearAllPoints()
    if position == "CENTER" then
        fs:SetPoint("CENTER", relativeTo, "CENTER", x, y)
        fs:SetJustifyH(defaultJustify or "CENTER")
    elseif position == "RIGHT" then
        fs:SetPoint("RIGHT", relativeTo, "RIGHT", x, y)
        fs:SetJustifyH(defaultJustify or "RIGHT")
    elseif position == "ABOVE" then
        fs:SetPoint("BOTTOM", relativeTo, "TOP", x, y + 2)
        fs:SetJustifyH(defaultJustify or "CENTER")
    elseif position == "BELOW" then
        fs:SetPoint("TOP", relativeTo, "BOTTOM", x, y - 2)
        fs:SetJustifyH(defaultJustify or "CENTER")
    else
        fs:SetPoint("LEFT", relativeTo, "LEFT", 2 + x, y)
        fs:SetJustifyH(defaultJustify or "LEFT")
    end
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
    if not (fs and statusBar) then return end
    local show = ShowSpellForUnit(g, unit, prefix)
    fs:Show()
    fs:SetAlpha(show and 1 or 0)
    if not show then
        SetTextIfChanged(fs, "")
        return
    end

    local baseSize = Num(g.castbarSpellNameFontSize, 0)
    if baseSize <= 0 then baseSize = Num(g.fontSize, 14) end
    local size = DetailNum(g, prefix, "SpellNameFontSize", nil, baseSize)
    if not size or size <= 0 then size = baseSize end
    ApplyFont(fs, g, prefix, "SpellName", size, "SpellName")

    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end

    local x = DetailNum(g, prefix, "TextOffsetX", nil, 0)
    local y = DetailNum(g, prefix, "TextOffsetY", nil, 0)
    local position = NormalizeTextPosition(DetailString(g, prefix, "SpellNamePosition", nil, "LEFT"), "LEFT")
    local justify = NormalizeJustify(DetailString(g, prefix, "SpellNameAlign", nil, position == "RIGHT" and "RIGHT" or position == "CENTER" and "CENTER" or "LEFT"), "LEFT")
    AnchorFontString(fs, statusBar, position, x, y, justify)

    local statusW = RegionNumber(statusBar, "GetWidth", nil) or RegionNumber(frame, "GetWidth", 250)
    local maxWidth = DetailNum(g, prefix, "SpellNameMaxWidth", nil, 0)
    local truncate = NormalizeSpellNameTruncate(DetailString(g, prefix, "SpellNameTruncate", nil, "AUTO"))
    local width
    if truncate == "NONE" then
        width = math.max(statusW, 1000)
    elseif maxWidth and maxWidth > 0 then
        width = maxWidth
    else
        local reserve = 0
        if frame.timeText and frame.timeText.IsShown and frame.timeText:IsShown() then
            local timeW = RegionNumber(frame.timeText, "GetStringWidth", nil)
            reserve = timeW and math.max(44, timeW + 10) or ApproxTimeTextReserve(frame, g, prefix, statusW)
        end
        width = math.max(20, statusW - reserve - 8)
    end
    if fs.SetWidth then fs:SetWidth(width) end

    local raw = frame._msufRawCastText
    if raw ~= nil and truncate ~= "AUTO" then
        SetTextIfChanged(fs, raw)
    elseif type(_G.MSUF_RefreshCastbarSpellNameText) == "function" then
        _G.MSUF_RefreshCastbarSpellNameText(frame)
    end
end

local function ApplyTimeTextLayout(frame, g, unit, prefix)
    local fs = frame and frame.timeText
    local statusBar = frame and frame.statusBar
    if not (fs and statusBar) then return end
    local show = ShowTimeForUnit(g, unit)
    fs:Show()
    fs:SetAlpha(show and 1 or 0)
    if not show then
        SetTextIfChanged(fs, "")
        return
    end

    local size = ResolveTimeTextFontSize(g, prefix)
    ApplyFont(fs, g, prefix, "Time", size, "Time")

    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    local fallbackX = unit == "boss" and 0 or -2
    local x = DetailNum(g, prefix, "TimeOffsetX", unit ~= "boss" and "castbarPlayerTimeOffsetX" or nil, fallbackX)
    local y = DetailNum(g, prefix, "TimeOffsetY", unit ~= "boss" and "castbarPlayerTimeOffsetY" or nil, 0)
    if unit == "boss" then x = -2 + (tonumber(x) or 0) end
    local position = NormalizeTextPosition(DetailString(g, prefix, "TimePosition", nil, "RIGHT"), "RIGHT")
    AnchorFontString(fs, statusBar, position, x, y, position == "LEFT" and "LEFT" or position == "CENTER" and "CENTER" or "RIGHT")
end

--- Public visual entry for one frame. Call this after frame creation, anchoring,
--- profile changes, or castbar size changes.
local function ApplyCastbarDetailLayout(frame, forcedUnit)
    if not (frame and frame.statusBar) then return end
    local unit = NormalizeUnit(forcedUnit) or UnitFromFrame(frame)
    local prefix = PrefixForUnit(unit)
    if not prefix then return end
    local g = GeneralDB()
    ApplyIconLayout(frame, g, unit, prefix)
    ApplyTimeTextLayout(frame, g, unit, prefix)
    ApplySpellTextLayout(frame, g, unit, prefix)
end

ExportPublic("MSUF_ApplyCastbarDetailLayout", ApplyCastbarDetailLayout)
ExportPublic("MSUF_ApplyCastbarDetailTextLayout", ApplyCastbarDetailLayout)

local function ApplyPlayerCastbarDetailFrames()
    ApplyCastbarDetailLayout(_G.MSUF_PlayerCastbar, "player")
    ApplyCastbarDetailLayout(_G.MSUF_PlayerCastbarPreview, "player")
end

local playerReanchorHooked
--- Player castbar reanchor can change the statusbar width after visual refresh.
--- Hook once and replay detail layout immediately after the anchor pass.
local function HookPlayerCastbarReanchor()
    if playerReanchorHooked then return end
    local previous = _G.MSUF_ReanchorPlayerCastBar
    if type(previous) ~= "function" then return end
    playerReanchorHooked = true
    ExportPublic("MSUF_ReanchorPlayerCastBar", function(...)
        local result = previous(...)
        ApplyPlayerCastbarDetailFrames()
        return result
    end)
end

HookPlayerCastbarReanchor()
C_Timer.After(0, HookPlayerCastbarReanchor)

--- Refreshes one existing frame without touching cast state. This is used by the
--- global visual refresh and by profile/style changes.
local function RefreshCastbarFrame(frame)
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

    ApplyCastbarDetailLayout(frame)
end

local function UpdateCastbarVisuals(...)
    if type(previousUpdateCastbarVisuals) == "function" and previousUpdateCastbarVisuals ~= _G.MSUF_UpdateCastbarVisuals then
        previousUpdateCastbarVisuals(...)
    end

    RefreshCastbarFrame(_G.MSUF_PlayerCastbar)
    RefreshCastbarFrame(_G.MSUF_TargetCastbar)
    RefreshCastbarFrame(_G.MSUF_FocusCastbar)
    RefreshCastbarFrame(_G.MSUF_PlayerCastbarPreview)
    RefreshCastbarFrame(_G.MSUF_TargetCastbarPreview)
    RefreshCastbarFrame(_G.MSUF_FocusCastbarPreview)
    RefreshCastbarFrame(_G.MSUF_BossCastbarPreview)
    RefreshCastbarFrame(_G.MSUF_BossCastbarPreview1)

    local maxBoss = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
    if maxBoss < 1 or maxBoss > 12 then maxBoss = 5 end
    for index = 2, maxBoss do
        RefreshCastbarFrame(_G["MSUF_BossCastbarPreview" .. index])
    end

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            RefreshCastbarFrame(bossCastbars[index])
        end
    end
end
ExportPublic("MSUF_UpdateCastbarVisuals", UpdateCastbarVisuals)
