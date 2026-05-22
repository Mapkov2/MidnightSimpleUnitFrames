local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local UNIT_SCOPE_KEYS = GP.UNIT_SCOPE_KEYS or {}
local TEXT_SCOPE_KEYS = GP.TEXT_SCOPE_KEYS or {}
local POWER_BAR_SCOPE_UNITS = GP.POWER_BAR_SCOPE_UNITS or {}
local GRADIENT_DIRECTIONS = GP.GRADIENT_DIRECTIONS or {}
local GRADIENT_DIR_KEYS = GP.GRADIENT_DIR_KEYS or {}
local PRIORITY_SINGLE = GP.PRIORITY_SINGLE or {}
local PRIORITY_TYPE = GP.PRIORITY_TYPE or {}
local PRIORITY_LABELS = GP.PRIORITY_LABELS or {}
local PRIORITY_COLORS = GP.PRIORITY_COLORS or {}

local Call = GP.Call
local DB = GP.DB
local G = GP.G
local Bars = GP.Bars
local Unit = GP.Unit
local ReadG = GP.ReadG
local Targeted = GP.Targeted
local SetG = GP.SetG
local ReadGBool = GP.ReadGBool
local SetGBool = GP.SetGBool
local ReadB = GP.ReadB
local SetB = GP.SetB
local SetUBool = GP.SetUBool
local NormalizeScopeKey = GP.NormalizeScopeKey
local ScopeDBKeys = GP.ScopeDBKeys
local ScopeHasOverride = GP.ScopeHasOverride
local ScopeSetOverride = GP.ScopeSetOverride
local ScopeRead = GP.ScopeRead
local ScopeWrite = GP.ScopeWrite
local CurrentFontScope = GP.CurrentFontScope
local CurrentBarsScope = GP.CurrentBarsScope
local IsGFScope = GP.IsGFScope
local IsTextScopeKey = GP.IsTextScopeKey
local BarsFlagForKey = GP.BarsFlagForKey
local FontScopeGet = GP.FontScopeGet
local FontScopeSet = GP.FontScopeSet
local BarScopeGet = GP.BarScopeGet
local BarScopeSet = GP.BarScopeSet
local BarScopeGetBars = GP.BarScopeGetBars
local BarScopeSetBars = GP.BarScopeSetBars
local NormalizeFontKey = GP.NormalizeFontKey
local FontValues = GP.FontValues
local ClearUFFontKeyOverrides = GP.ClearUFFontKeyOverrides
local FontKeyGet = GP.FontKeyGet
local FontKeySet = GP.FontKeySet
local TextureValues = GP.TextureValues
local BarsScopeHasOverride = GP.BarsScopeHasOverride
local BarsScopeSetOverride = GP.BarsScopeSetOverride
local CurrentPowerBarScopeUnit = GP.CurrentPowerBarScopeUnit
local SmoothPowerGet = GP.SmoothPowerGet
local SmoothPowerSet = GP.SmoothPowerSet
local NormalizeHpMode = GP.NormalizeHpMode
local NormalizePowerMode = GP.NormalizePowerMode
local CurrentGradientDirection = GP.CurrentGradientDirection
local SetGradientDirection = GP.SetGradientDirection
local PriorityDefaults = GP.PriorityDefaults
local PriorityAllowed = GP.PriorityAllowed
local PriorityOrder = GP.PriorityOrder
local PriorityColor = GP.PriorityColor
local SetPriorityOrder = GP.SetPriorityOrder
local RefreshBorderTestModes = GP.RefreshBorderTestModes
local SetAbsorbTextureTest = GP.SetAbsorbTextureTest
local ClearAbsorbTextureTest = GP.ClearAbsorbTextureTest
local NormalizeGlowStyle = GP.NormalizeGlowStyle
local SetControlEnabled = GP.SetControlEnabled
local SetControlsEnabled = GP.SetControlsEnabled
local ApplyFonts = GP.ApplyFonts
local ApplyBars = GP.ApplyBars
local ApplyCastbars = GP.ApplyCastbars

local function RGB(r, g, b, a)
    return { r or 1, g or 1, b or 1, a or 1 }
end

local function ConfiguredFontColorPreview()
    local fn = _G.MSUF_GetConfiguredFontColor or (ns and ns.MSUF_GetConfiguredFontColor)
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return RGB(r, g, b)
        end
    end

    local general = G()
    if general.useCustomFontColor and type(general.fontColorCustomR) == "number"
        and type(general.fontColorCustomG) == "number"
        and type(general.fontColorCustomB) == "number" then
        return RGB(general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB)
    end

    local colors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
    local key = tostring(general.fontColor or "white"):lower()
    local color = colors and (colors[key] or colors.white)
    return RGB((color and color[1]) or 1, (color and color[2]) or 1, (color and color[3]) or 1)
end

local function PlayerClassColorPreview()
    local classToken
    if type(_G.UnitClass) == "function" then
        local _, token = _G.UnitClass("player")
        classToken = token
    end
    classToken = classToken or "WARRIOR"
    if type(_G.MSUF_GetClassBarColor) == "function" then
        local r, g, b = _G.MSUF_GetClassBarColor(classToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return RGB(r, g, b)
        end
    end
    local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    return RGB((color and color.r) or 0.78, (color and color.g) or 0.61, (color and color.b) or 0.43)
end

local function NPCReactionColorPreview()
    local kind = "enemy"
    if type(_G.UnitExists) == "function" and _G.UnitExists("target")
        and not (type(_G.UnitIsPlayer) == "function" and _G.UnitIsPlayer("target")) then
        if type(_G.UnitIsDeadOrGhost) == "function" and _G.UnitIsDeadOrGhost("target") then
            kind = "dead"
        elseif type(_G.UnitReaction) == "function" then
            local reaction = _G.UnitReaction("player", "target")
            if reaction and reaction >= 5 then
                kind = "friendly"
            elseif reaction == 4 then
                kind = "neutral"
            end
        end
    end
    if type(_G.MSUF_GetNPCReactionColor) == "function" then
        local r, g, b = _G.MSUF_GetNPCReactionColor(kind)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return RGB(r, g, b)
        end
    end
    return RGB(0.85, 0.10, 0.10)
end

local function CurrentPowerColorPreview()
    local powerType, powerToken
    if type(_G.UnitPowerType) == "function" then
        powerType, powerToken = _G.UnitPowerType("player")
    end
    if _G.MSUF_EleMaelstromActive or _G.MSUF_ShadowManaActive then
        powerType, powerToken = 0, "MANA"
    elseif _G.MSUF_AugEvokerActive then
        powerType, powerToken = 19, "ESSENCE"
    end
    if powerType == nil and (powerToken == nil or powerToken == "") then
        powerType, powerToken = 0, "MANA"
    end

    local fn = _G.MSUF_GetResolvedPowerColor or (ns and ns.MSUF_GetResolvedPowerColor)
    if type(fn) == "function" then
        local r, g, b = fn(powerType, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return RGB(r, g, b)
        end
    end

    local pbc = _G.PowerBarColor
    local color = pbc and ((powerToken and pbc[powerToken]) or (powerType and pbc[powerType]) or pbc.MANA or pbc[0])
    return RGB((color and (color.r or color[1])) or 0.00, (color and (color.g or color[2])) or 0.44, (color and (color.b or color[3])) or 0.87)
end

local function NameColorValues()
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = ConfiguredFontColorPreview },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassColorPreview },
    }
end

local function NPCColorValues()
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = ConfiguredFontColorPreview },
        { value = "NPC", text = "NPC / Reaction Color", swatchColor = NPCReactionColorPreview },
    }
end

local function PowerColorValues()
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = ConfiguredFontColorPreview },
        { value = "RESOURCE", text = "By Power Type", swatchColor = CurrentPowerColorPreview },
    }
end

local function PreviewFontKey()
    local key = FontKeyGet()
    if key == nil or key == "" then
        key = NormalizeFontKey(G().fontKey or "FRIZQT")
    end
    return key
end

local function PreviewFontFlags()
    if IsGFScope(CurrentFontScope()) then
        local v = FontScopeGet("fontOutline", "OUTLINE")
        if v == "" or v == "NONE" then return "" end
        if v == "THICKOUTLINE" then return "THICKOUTLINE" end
        return "OUTLINE"
    end
    if FontScopeGet("noOutline", false) then return "" end
    if FontScopeGet("boldText", false) then return "THICKOUTLINE" end
    return "OUTLINE"
end

local function ApplyPreviewFont(fs)
    if not (fs and fs.SetFont) then return end
    local key = PreviewFontKey()
    local size = max(10, min(22, tonumber(FontScopeGet("fontSize", 14)) or 14))
    local flags = PreviewFontFlags()
    local path
    local pathForKey = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (ns and ns.MSUF_GetFontPathForKey)
    if type(pathForKey) == "function" then
        path = pathForKey(key, size, flags)
    end
    if (not path or path == "") and key and key ~= "" then
        local fetch = _G.MSUF_FetchFontPathFromLSM or (ns and ns.MSUF_FetchFontPathFromLSM)
        if type(fetch) == "function" then path = fetch(key) end
    end
    path = path or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    local resolve = _G.MSUF_ResolveFontPath
    if type(resolve) == "function" then path = resolve(path, size, flags, key) end
    local safeSet = _G.MSUF_SetFontSafe
    if type(safeSet) == "function" then
        safeSet(fs, path, size, flags, key)
    else
        pcall(fs.SetFont, fs, path, size, flags)
    end

    local c = ConfiguredFontColorPreview()
    if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function ApplyNameShortening(reason)
    ApplyFonts(reason)
    local scope = CurrentFontScope()
    if IsGFScope(scope) then return end
    if scope == "shared" then
        for _, unit in ipairs({ "target", "targettarget", "focustarget", "focus", "pet", "boss" }) do
            M.RequestUnitApply(unit, reason or "MSUF2_SHORTEN_NAMES", { text = true, preview = true })
        end
    elseif UNIT_SCOPE_KEYS[scope] then
        M.RequestUnitApply(scope, reason or "MSUF2_SHORTEN_NAMES", { text = true, preview = true })
    end
end

local function CurrentFontScopeCanEdit()
    local scope = CurrentFontScope()
    return scope == "shared" or ScopeHasOverride(scope, "fontOverride")
end

local function GFNameScopeGet(key, default)
    local db = DB()
    local keys = ScopeDBKeys(CurrentFontScope())
    for i = 1, #(keys or {}) do
        local entry = db[keys[i]]
        if entry and entry[key] ~= nil then return entry[key] end
    end
    return default
end

local function GFNameScopeSet(key, value)
    local db = DB()
    local keys = ScopeDBKeys(CurrentFontScope())
    for i = 1, #(keys or {}) do
        local scopeKey = keys[i]
        db[scopeKey] = db[scopeKey] or {}
        db[scopeKey][key] = value
        db[scopeKey].nameShortenOverride = nil
        db[scopeKey]._msufGFNameTruncationOverride = nil
    end
end

local function SharedNameShorteningEnabled()
    return DB().shortenNames == true
end

local function SharedNameShorteningSide()
    local g = G()
    return (g and g.shortenNameClipSide) or "LEFT"
end

local function SharedNameShorteningMax()
    local g = G()
    return tonumber(g and g.shortenNameMaxChars) or 6
end

local function SharedNameShorteningNoEllipsis()
    local g = G()
    return not (g and g.shortenNameShowDots ~= false)
end

local function GFNameUsesLocalScope()
    return IsGFScope(CurrentFontScope()) and ScopeHasOverride(CurrentFontScope(), "fontOverride")
end

local function SeedGFNameShorteningFromShared()
    if not IsGFScope(CurrentFontScope()) then return end
    if GFNameScopeGet("nameShortenEnabled", nil) == nil then
        GFNameScopeSet("nameShortenEnabled", SharedNameShorteningEnabled())
    end
    if GFNameScopeGet("nameClipSide", nil) == nil then
        GFNameScopeSet("nameClipSide", SharedNameShorteningSide())
    end
    if GFNameScopeGet("nameNoEllipsis", nil) == nil then
        GFNameScopeSet("nameNoEllipsis", SharedNameShorteningNoEllipsis())
    end
    if (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) <= 0 then
        GFNameScopeSet("nameMaxChars", SharedNameShorteningMax())
    end
end

local function BuildFonts(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Fonts", "Shared font, text style, name and power colors.", 72)

    local scopeValues = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "targettarget", text = "ToT" },
        { value = "focustarget", text = "Focus Target" },
        { value = "focus", text = "Focus" },
        { value = "pet", text = "Pet" },
        { value = "boss", text = "Boss" },
        { value = "gf_party", text = "Party" },
        { value = "gf_raid", text = "Raid" },
    }

    local function ActiveFontOverrideLabels(filter)
        local active = {}
        for i = 1, #scopeValues do
            local item = scopeValues[i]
            if item.value ~= "shared"
                and ScopeHasOverride(item.value, "fontOverride")
                and (not filter or filter(item.value))
            then
                active[#active + 1] = M.Tr(item.text or "")
            end
        end
        return active
    end

    local scopeOpts = {
        values = scopeValues,
        width = ctx.width,
        getValue = function() return CurrentFontScope() end,
        setValue = function(v)
            G()._fontScopeKey = NormalizeScopeKey(v)
            if M.InvalidatePage then M.InvalidatePage(ctx.key) end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "fontOverride")
        end,
    }
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(scopeValues, scopeOpts)
    local scopeBottomY = (scopeMetrics and scopeMetrics.bottomY) or -40
    local overrideY = math.min(-58, scopeBottomY - 18)
    local hintY = overrideY - 34

    local scope = b:Section("", math.max(128, math.abs(hintY) + 34))
    if scope.title then scope.title:Hide() end
    local scopeSeg = W.ScopeOverrideBar(ctx, scope, scopeOpts)

    local override = W.ToggleAt(scope, "Use custom settings for this scope", 14, overrideY, 260)
    M.BindToggle(ctx, override,
        function()
            local key = CurrentFontScope()
            return key ~= "shared" and ScopeHasOverride(key, "fontOverride")
        end,
        function(v)
            local key = CurrentFontScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "fontOverride", v)
                if v and IsGFScope(key) then SeedGFNameShorteningFromShared() end
                ApplyFonts("MSUF2_FONT_OVERRIDE")
            end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    local overrideInfo = W.Text(scope, "", 14, overrideY, ctx.width - 130, T.colors.text)
    local reset = T.Button(scope, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -14, overrideY + 8)
    reset._msuf2Label:ClearAllPoints()
    reset._msuf2Label:SetPoint("CENTER", reset, "CENTER", 0, 0)
    reset._msuf2Label:SetJustifyH("CENTER")
    reset:SetScript("OnClick", function()
        for i = 1, #scopeValues do
            local key = scopeValues[i].value
            if key ~= "shared" then ScopeSetOverride(key, "fontOverride", false) end
        end
        ApplyFonts("MSUF2_FONT_RESET_OVERRIDES")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)
    local hint = W.Text(scope, "Shared baseline plus per-unit and group-frame font overrides.", 14, hintY, ctx.width - 28, T.colors.muted)
    M.AddRefresher(ctx, function()
        local current = CurrentFontScope()
        local active = ActiveFontOverrideLabels()
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        overrideInfo:SetText("|cffffffff" .. M.Tr("Overrides:") .. "|r " .. (#active > 0 and table.concat(active, ", ") or M.Tr("None")))
        if shared then
            if #active > 0 then
                hint:SetText("Shared font settings are the baseline. Active overrides keep their own font and name-shortening settings.")
            else
                hint:SetText("Shared font settings are the baseline for units and group frames.")
            end
        elseif ScopeHasOverride(current, "fontOverride") then
            hint:SetText("This scope is using custom font settings. Shared changes will not affect it until the override is reset.")
        else
            hint:SetText("This scope follows Shared font settings. Turn on custom settings here only when this scope needs different fonts.")
        end
        scopeSeg:Refresh()
        hint:SetWidth(ctx.width - 28)
    end)

    local font = b:CollapsibleSection("fonts_global_font", "Global Font", 146, true)
    local RefreshFontPreview
    local fontDrop = W.Dropdown(font, "Font (SharedMedia)", function() return FontValues(false) end, 340)
    local fontScopeInfo = W.Text(font, "Font family is global and can be changed in Shared scope.", 374, -42, ctx.width - 402, T.colors.muted)
    if fontScopeInfo.SetShown then fontScopeInfo:SetShown(CurrentFontScope() ~= "shared") end
    local preview = W.Text(font, "AaBbCc 12345 - Midnight Simple Unit Frames", 14, -82, ctx.width - 56, T.colors.text)
    if preview.SetHeight then preview:SetHeight(28) end
    if preview.SetJustifyV then preview:SetJustifyV("MIDDLE") end
    RefreshFontPreview = function()
        local sharedScope = CurrentFontScope() == "shared"
        SetControlEnabled(fontDrop, sharedScope)
        if preview and preview.SetWidth then preview:SetWidth(ctx.width - 56) end
        if fontScopeInfo and fontScopeInfo.SetShown then fontScopeInfo:SetShown(CurrentFontScope() ~= "shared") end
        if fontScopeInfo and fontScopeInfo.SetWidth then fontScopeInfo:SetWidth(ctx.width - 402) end
        ApplyPreviewFont(preview)
    end
    M.BindDropdown(ctx, fontDrop,
        function() return FontKeyGet() end,
        function(v)
            FontKeySet(v)
            M.RequestGeneralApply("MSUF2_FONT_KEY", { preview = true, applyAll = false })
            if type(_G.MSUF_NormalizeStoredFontKeys) == "function" then _G.MSUF_NormalizeStoredFontKeys() end
            ApplyFonts("MSUF2_FONT_KEY")
            if RefreshFontPreview then RefreshFontPreview() end
        end)
    M.AddRefresher(ctx, RefreshFontPreview)
    RefreshFontPreview()

    local text = b:CollapsibleSection("fonts_text_style", "Text Style", 164, true)

    local outline = W.Segment(text, "Outline", {
        { value = "OUTLINE", text = "Outline" },
        { value = "THICKOUTLINE", text = "Thick Outline" },
        { value = "NONE", text = "None" },
    }, 420)
    M.BindSegment(ctx, outline,
        function()
            if IsGFScope(CurrentFontScope()) then
                local v = FontScopeGet("fontOutline", "OUTLINE")
                if v == "" then return "OUTLINE" end
                return v or "OUTLINE"
            end
            if FontScopeGet("noOutline", false) then return "NONE" end
            if FontScopeGet("boldText", false) then return "THICKOUTLINE" end
            return "OUTLINE"
        end,
        function(v)
            if IsGFScope(CurrentFontScope()) then
                FontScopeSet("fontOutline", v or "OUTLINE", "MSUF2_GF_FONT_OUTLINE")
                ApplyFonts("MSUF2_GF_FONT_OUTLINE")
                return
            end
            FontScopeSet("boldText", v == "THICKOUTLINE", "MSUF2_FONT_OUTLINE")
            FontScopeSet("noOutline", v == "NONE", "MSUF2_FONT_OUTLINE")
            ApplyFonts("MSUF2_FONT_OUTLINE")
        end)

    local shadow = W.Segment(text, "Text shadow", {
        { value = "ON", text = "On" },
        { value = "OFF", text = "Off" },
    }, 260)
    M.BindSegment(ctx, shadow,
        function() return FontScopeGet("textBackdrop", true) and "ON" or "OFF" end,
        function(v)
            FontScopeSet("textBackdrop", v == "ON", "MSUF2_FONT_SHADOW")
            ApplyFonts("MSUF2_FONT_SHADOW")
        end)

    local colors = b:CollapsibleSection("fonts_name_power_colors", "Name & Power Colors", 220, true)
    local nameColor = W.Dropdown(colors, "Player Name Color", NameColorValues, 280)
    M.BindDropdown(ctx, nameColor,
        function()
            if IsGFScope(CurrentFontScope()) then
                return FontScopeGet("nameColorMode", "DEFAULT") == "CLASS" and "CLASS" or "DEFAULT"
            end
            return FontScopeGet("nameClassColor", false) and "CLASS" or "DEFAULT"
        end,
        function(v)
            if IsGFScope(CurrentFontScope()) then
                FontScopeSet("nameColorMode", v == "CLASS" and "CLASS" or "DEFAULT", "MSUF2_GF_NAME_COLOR")
                ApplyFonts("MSUF2_GF_NAME_COLOR")
                return
            end
            FontScopeSet("nameClassColor", v == "CLASS", "MSUF2_NAME_CLASS_COLOR")
            ApplyFonts("MSUF2_NAME_CLASS_COLOR")
        end)
    local npcColor = W.Dropdown(colors, "NPC / Boss Name Color", NPCColorValues, 280)
    M.BindDropdown(ctx, npcColor,
        function() return FontScopeGet("npcNameRed", false) and "NPC" or "DEFAULT" end,
        function(v)
            FontScopeSet("npcNameRed", v == "NPC", "MSUF2_NPC_RED")
            ApplyFonts("MSUF2_NPC_RED")
        end)
    local powerColor = W.Dropdown(colors, "Power Text Color", PowerColorValues, 280)
    M.BindDropdown(ctx, powerColor,
        function() return FontScopeGet("colorPowerTextByType", false) and "RESOURCE" or "DEFAULT" end,
        function(v)
            FontScopeSet("colorPowerTextByType", v == "RESOURCE", "MSUF2_POWER_TEXT_COLOR")
            ApplyFonts("MSUF2_POWER_TEXT_COLOR")
        end)
    local function RefreshScopedFontControls()
        local scopeKey = CurrentFontScope()
        local canEdit = CurrentFontScopeCanEdit()
        local gfScope = IsGFScope(scopeKey)
        SetControlEnabled(outline, canEdit)
        SetControlEnabled(shadow, canEdit and not gfScope)
        SetControlEnabled(nameColor, canEdit)
        SetControlEnabled(npcColor, canEdit and not gfScope)
        SetControlEnabled(powerColor, canEdit and not gfScope)
    end
    M.AddRefresher(ctx, RefreshScopedFontControls)
    RefreshScopedFontControls()

    local nameScope = CurrentFontScope()
    if IsGFScope(nameScope) then
        local names = b:CollapsibleSection("fonts_name_shortening", "Name Shortening", 322, true)
        W.Text(names, "Group Frame Name Truncation", 14, -38, ctx.width - 28, T.colors.text)
        names._msuf2CursorY = -72

        local shorten, side, chars, noEllipsis
        local function RefreshGFNameShorteningUI()
            if M.Refresh then M.Refresh(ctx) end
        end

        shorten = W.Toggle(names, "Shorten group names")
        M.BindToggle(ctx, shorten,
            function()
                if GFNameUsesLocalScope() then
                    return GFNameScopeGet("nameShortenEnabled", (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) > 0) and true or false
                end
                return SharedNameShorteningEnabled()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                GFNameScopeSet("nameShortenEnabled", v and true or false)
                if v and (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) <= 0 then
                    GFNameScopeSet("nameMaxChars", SharedNameShorteningMax())
                end
                ApplyFonts("MSUF2_GF_NAME_SHORTEN")
                RefreshGFNameShorteningUI()
            end)

        side = W.Segment(names, "Truncation style", {
            { value = "LEFT", text = "Keep end (last letters)" },
            { value = "RIGHT", text = "Keep start (first letters)" },
        }, 430)
        M.BindSegment(ctx, side,
            function()
                if GFNameUsesLocalScope() then
                    return GFNameScopeGet("nameClipSide", "RIGHT")
                end
                return SharedNameShorteningSide()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                GFNameScopeSet("nameClipSide", v or "RIGHT")
                ApplyFonts("MSUF2_GF_NAME_SHORTEN_SIDE")
                RefreshGFNameShorteningUI()
            end)

        chars = W.Slider(names, "Max name length", 1, 30, 1, 300)
        chars:SetValueFormatter(function(v)
            return tostring(floor((tonumber(v) or 6) + 0.5))
        end)
        M.BindSlider(ctx, chars,
            function()
                if GFNameUsesLocalScope() then
                    return tonumber(GFNameScopeGet("nameMaxChars", 6)) or 6
                end
                return SharedNameShorteningMax()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                v = floor((tonumber(v) or 6) + 0.5)
                GFNameScopeSet("nameMaxChars", v)
                ApplyFonts("MSUF2_GF_NAME_MAX")
                RefreshGFNameShorteningUI()
            end)

        noEllipsis = W.Toggle(names, "No Ellipsis (truncate without ..)")
        M.BindToggle(ctx, noEllipsis,
            function()
                if GFNameUsesLocalScope() then
                    return GFNameScopeGet("nameNoEllipsis", false) and true or false
                end
                return SharedNameShorteningNoEllipsis()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                GFNameScopeSet("nameNoEllipsis", v and true or false)
                ApplyFonts("MSUF2_GF_NAME_ELLIPSIS")
                RefreshGFNameShorteningUI()
            end)
        local scopeNoticeY = (names._msuf2CursorY or -228) - 8
        local scopeNotice = W.Text(names, "", 14, scopeNoticeY, ctx.width - 28, T.colors.muted)
        if scopeNotice.SetWordWrap then scopeNotice:SetWordWrap(true) end
        if scopeNotice.SetHeight then scopeNotice:SetHeight(44) end
        local function RefreshGFNameShorteningControls()
            local canEdit = CurrentFontScopeCanEdit()
            local enabled
            if GFNameUsesLocalScope() then
                enabled = GFNameScopeGet("nameShortenEnabled", (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) > 0) == true
            else
                enabled = SharedNameShorteningEnabled()
            end
            SetControlEnabled(shorten, canEdit)
            SetControlEnabled(side, canEdit and enabled)
            SetControlEnabled(chars, canEdit and enabled)
            SetControlEnabled(noEllipsis, canEdit and enabled)
            if GFNameUsesLocalScope() then
                scopeNotice:SetText("This group scope uses custom font settings. Shared name-shortening changes will not affect it until the override is reset.")
            else
                scopeNotice:SetText("This group scope follows Shared name shortening. Turn on custom settings above only when group names need different truncation.")
            end
        end
        M.AddRefresher(ctx, RefreshGFNameShorteningControls)
        RefreshGFNameShorteningControls()
    elseif nameScope ~= "player" then
        local names = b:CollapsibleSection("fonts_name_shortening", "Name Shortening", 294, true)

        local shorten, side, chars, noEllipsis, scopeNotice
        local function CanEditNameShortening()
            return CurrentFontScopeCanEdit() and not IsGFScope(CurrentFontScope())
        end
        local function NameShorteningEnabled()
            return FontScopeGet("shortenNames", false, "shortenNames") and true or false
        end
        local function RefreshNameShorteningControls()
            local canEdit = CanEditNameShortening()
            local enabled = NameShorteningEnabled()
            SetControlEnabled(shorten, canEdit)
            SetControlEnabled(side, canEdit and enabled)
            SetControlEnabled(chars, canEdit and enabled)
            SetControlEnabled(noEllipsis, canEdit)
            if scopeNotice then
                local current = CurrentFontScope()
                if current == "shared" then
                    local active = ActiveFontOverrideLabels()
                    if #active > 0 then
                        scopeNotice:SetText("|cffffd200" .. M.Tr("Font overrides active:") .. "|r "
                            .. table.concat(active, ", ")
                            .. ". Shared name-shortening changes do not affect those scopes.")
                    else
                        scopeNotice:SetText("Shared name shortening affects all non-player unit names and group frames unless a scope has custom font settings.")
                    end
                elseif ScopeHasOverride(current, "fontOverride") then
                    scopeNotice:SetText("This scope uses custom font settings. Shared name-shortening changes will not affect it until the override is reset.")
                else
                    scopeNotice:SetText("This scope follows Shared name shortening. Turn on custom settings above only when this scope needs different names.")
                end
            end
        end
        local function ApplyNameShorteningChange(reason, onlyWhenEnabled)
            RefreshNameShorteningControls()
            if (not onlyWhenEnabled) or NameShorteningEnabled() then
                ApplyNameShortening(reason)
            end
        end

        shorten = W.Toggle(names, nameScope == "shared" and "Shorten names (except Player)" or "Shorten unit names (except Player)")
        M.BindToggle(ctx, shorten,
            function()
                return NameShorteningEnabled()
            end,
            function(v)
                FontScopeSet("shortenNames", v and true or false, "MSUF2_SHORTEN_NAMES", "shortenNames")
                ApplyNameShorteningChange("MSUF2_SHORTEN_NAMES", false)
            end)

        side = W.Segment(names, "Truncation style", {
            { value = "LEFT", text = "Keep end (last letters)" },
            { value = "RIGHT", text = "Keep start (first letters)" },
        }, 430)
        M.BindSegment(ctx, side,
            function() return FontScopeGet("shortenNameClipSide", "LEFT") end,
            function(v)
                FontScopeSet("shortenNameClipSide", v or "LEFT", "MSUF2_SHORTEN_SIDE")
                ApplyNameShorteningChange("MSUF2_SHORTEN_SIDE", true)
            end)

        chars = W.Slider(names, "Max name length", 6, 30, 1, 300)
        M.BindSlider(ctx, chars,
            function() return tonumber(FontScopeGet("shortenNameMaxChars", 6)) or 6 end,
            function(v)
                FontScopeSet("shortenNameMaxChars", floor((tonumber(v) or 6) + 0.5), "MSUF2_SHORTEN_MAX")
                ApplyNameShorteningChange("MSUF2_SHORTEN_MAX", true)
            end)

        noEllipsis = W.Toggle(names, "No Ellipsis (truncate without ..)")
        M.BindToggle(ctx, noEllipsis,
            function() return not FontScopeGet("shortenNameShowDots", true) end,
            function(v)
                FontScopeSet("shortenNameShowDots", not (v and true or false), "MSUF2_SHORTEN_DOTS")
                ApplyNameShorteningChange("MSUF2_SHORTEN_DOTS", false)
            end)
        local scopeNoticeY = (names._msuf2CursorY or -194) - 8
        scopeNotice = W.Text(names, "", 14, scopeNoticeY, ctx.width - 28, T.colors.muted)
        if scopeNotice.SetWordWrap then scopeNotice:SetWordWrap(true) end
        if scopeNotice.SetHeight then scopeNotice:SetHeight(44) end
        M.AddRefresher(ctx, RefreshNameShorteningControls)
        RefreshNameShorteningControls()
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_fonts", { title = "MSUF Fonts", build = BuildFonts, version = 3 })
