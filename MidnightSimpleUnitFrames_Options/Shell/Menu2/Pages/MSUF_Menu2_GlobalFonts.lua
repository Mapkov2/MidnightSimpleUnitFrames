local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

-- Menu2 global Fonts page.
-- Binds shared/scoped font family, size, outline, shadow, alpha, and baseline controls.
-- Runtime font resolution and live font-string updates remain in the font runtime registry.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList
local floor = math.floor
local max = math.max
local min = math.min
local SHADOW_OPACITY_APPLY_DELAY = 0.18
local UNIT_SCOPE_KEYS = GP.UNIT_SCOPE_KEYS or {}
local DB, G, Unit, NormalizeScopeKey, ScopeDBKeys, ScopeHasOverride, ScopeSetOverride, ScopeWrite, CurrentFontScope, IsGFScope, FontScopeGet, FontScopeSet, FontOutlineGetFor, FontOutlineSetFor, FontShadowMetricsFor, FontTextColorModeGetFor, FontTextColorModeSetFor, NormalizeFontKey, FontValues, FontKeyGet, FontKeySet, SetControlEnabled, SetControlsEnabled, ApplyFonts, ControlMeta, RegisterControl = M.Pick(GP, [[DB G Unit NormalizeScopeKey ScopeDBKeys ScopeHasOverride ScopeSetOverride ScopeWrite CurrentFontScope IsGFScope FontScopeGet FontScopeSet FontOutlineGetFor FontOutlineSetFor FontShadowMetricsFor FontTextColorModeGetFor FontTextColorModeSetFor NormalizeFontKey FontValues FontKeyGet FontKeySet SetControlEnabled SetControlsEnabled ApplyFonts ControlMeta RegisterControl]])
local FONT_DYNAMIC_SETTING_KEYS_BY_PATH = {
    ["name_shortening.enabled"] = { "gf_party.nameShortenEnabled", "gf_raid.nameShortenEnabled" },
    ["name_shortening.style"] = { "gf_party.nameClipSide", "gf_raid.nameClipSide" },
    ["name_shortening.max_length"] = { "gf_party.nameMaxChars", "gf_raid.nameMaxChars" },
    ["name_shortening.no_ellipsis"] = { "gf_party.nameNoEllipsis", "gf_raid.nameNoEllipsis" },
}
local FONT_DYNAMIC_SETTING_SUFFIXES_BY_PATH = {
    ["scope.override.enabled"] = { "override" },
    ["text_style.outline"] = { "outline" },
    ["text_style.rendering"] = { "fontMonochrome", "fontSlug" },
    ["text_style.shadow.enabled"] = { "textBackdrop" },
    ["text_style.shadow.opacity"] = { "fontShadowOpacity" },
    ["text_style.shadow.distance"] = { "fontShadowDistance" },
    ["text_style.opacity"] = { "fontTextAlpha" },
    ["text_style.baseline"] = { "fontBaselineOffset" },
    ["colors.player_name"] = { "nameColorMode" },
    ["colors.npc_name"] = { "npcNameRed", "nameNpcClassColor" },
    ["colors.colorHealthTextByHealth"] = { "colorHealthTextByHealth" },
    ["colors.colorPowerTextByType"] = { "colorPowerTextByType" },
    ["name_shortening.enabled"] = { "shortenNames" },
    ["name_shortening.style"] = { "shortenNameClipSide" },
    ["name_shortening.max_length"] = { "shortenNameMaxChars" },
    ["name_shortening.no_ellipsis"] = { "shortenNameNoEllipsis" },
}
local function Meta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    if path == "font.family" then
        resolved.settingKey = resolved.settingKey or "general.fontKey"
    elseif path == "scope.overrides.reset" then
        resolved.actionKey = resolved.actionKey or "reset_all_scoped_global_font_overrides"
    elseif (classification or "setting") == "setting" then
        resolved.assistantDisposition = resolved.assistantDisposition or "dynamic"
        resolved.assistantDispositionReason = resolved.assistantDispositionReason
            or "This control reads and writes the explicitly selected Shared, unit, Party, or Raid font scope; some modes intentionally span multiple stored representation keys."
        resolved.assistantSettingKeys = resolved.assistantSettingKeys or FONT_DYNAMIC_SETTING_KEYS_BY_PATH[path]
        local suffixes = FONT_DYNAMIC_SETTING_SUFFIXES_BY_PATH[path]
        if suffixes and not resolved.assistantSettingKeyPatterns then
            resolved.assistantSettingKeyPatterns = {}
            for i = 1, #suffixes do
                resolved.assistantSettingKeyPatterns[i] = "^fontScope%.[%w_]+%." .. suffixes[i] .. "$"
            end
        end
    end
    return ControlMeta("opt_fonts", "global", path, classification, resolved)
end
local function RGB(r, g, b, a)
    return { r or 1, g or 1, b or 1, a or 1 }
end
local function ShadowMetrics()
    return FontShadowMetricsFor(CurrentFontScope())
end
local function NormalizeShadowOpacity(value)
    local alpha = _G.MSUF_ResolveFontShadowMetrics(value, 1)
    return floor(alpha * 20 + 0.5) / 20
end
local function NormalizeShadowDistance(value)
    local _, distance = _G.MSUF_ResolveFontShadowMetrics(1, value)
    return distance
end
local function ClearLegacyShadowStrength()
    local scope = CurrentFontScope()
    if scope == "shared" then
        G().fontShadowStrength = nil
        return
    end
    local db, keys = DB(), ScopeDBKeys(scope)
    for i = 1, #(keys or {}) do
        local entry = db[keys[i]]
        if entry then entry.fontShadowStrength = nil end
    end
end
local function SetShadowAndApply(key, value, reason)
    ClearLegacyShadowStrength()
    FontScopeSet(key, value, reason)
    ApplyFonts(reason)
end
local function SetShadowValueWithoutApply(key, value)
    ClearLegacyShadowStrength()
    ScopeWrite(CurrentFontScope(), "fontOverride", G(), key, value)
end
local function NormalizeTextAlpha(value)
    value = tonumber(value) or 1
    if value <= 0.75 then return 0.70 end
    if value <= 0.925 then return 0.85 end
    return 1
end
local function NormalizeBaselineOffset(value)
    value = floor((tonumber(value) or 0) + 0.5)
    if value < -4 then return -4 end
    if value > 4 then return 4 end
    return value
end
local function ComposeFontFlags(outline, monochrome, slug)
    local flags = ""
    outline = tostring(outline or "OUTLINE"):upper()
    if slug == true then
        return (outline == "NONE" or outline == "") and "SLUG" or "OUTLINE,SLUG"
    end
    if outline == "THICKOUTLINE" then
        flags = "THICKOUTLINE"
    elseif outline ~= "NONE" and outline ~= "" then
        flags = "OUTLINE"
    end
    if monochrome == true then flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME" end
    return flags
end
local function ConfiguredFontColorPreview(scope)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    local getFor = GP.FontScopeGetFor
    local overrideFor = GP.FontOverrideGetFor
    if IsGFScope(scope) and type(overrideFor) == "function" and overrideFor(scope)
        and type(getFor) == "function" and getFor(scope, "useGlobalFontColor", true) == false
    then
        return RGB(getFor(scope, "fontR", 1), getFor(scope, "fontG", 1), getFor(scope, "fontB", 1))
    end
    local fn = _G.MSUF_GetConfiguredFontColor or (MSUF and MSUF.MSUF_GetConfiguredFontColor)
    if type(fn) == "function" then
        local r, g, b = fn()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return RGB(r, g, b) end
    end
    local general = G()
    if general.useCustomFontColor and type(general.fontColorCustomR) == "number"
        and type(general.fontColorCustomG) == "number"
        and type(general.fontColorCustomB) == "number" then
        return RGB(general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB)
    end
    local colors = (MSUF and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
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
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return RGB(r, g, b) end
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
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return RGB(r, g, b) end
    end
    return RGB(0.85, 0.10, 0.10)
end
local function CurrentPowerColorPreview()
    local powerType, powerToken
    if type(_G.UnitPowerType) == "function" then powerType, powerToken = _G.UnitPowerType("player") end
    if _G.MSUF_EleMaelstromActive or _G.MSUF_ShadowManaActive then
        powerType, powerToken = 0, "MANA"
    elseif _G.MSUF_AugEvokerActive then
        powerType, powerToken = 19, "ESSENCE"
    end
    if powerType == nil and (powerToken == nil or powerToken == "") then powerType, powerToken = 0, "MANA" end
    local fn = _G.MSUF_GetResolvedPowerColor or (MSUF and MSUF.MSUF_GetResolvedPowerColor)
    if type(fn) == "function" then
        local r, g, b = fn(powerType, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return RGB(r, g, b) end
    end
    local pbc = _G.PowerBarColor
    local color = pbc and ((powerToken and pbc[powerToken]) or (powerType and pbc[powerType]) or pbc.MANA or pbc[0])
    return RGB((color and (color.r or color[1])) or 0.00, (color and (color.g or color[2])) or 0.44, (color and (color.b or color[3])) or 0.87)
end
local function CurrentHealthGradientPreview()
    return RGB(1, 0.7, 0)
end
-- Unit and group scopes both store the custom name color in nameColorR/G/B,
-- so one preview reader serves the whole Fonts scope selector.
local function CustomNameColorPreview(scope)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    local getFor = GP.FontScopeGetFor
    if type(getFor) == "function" then
        return RGB(getFor(scope, "nameColorR", 1), getFor(scope, "nameColorG", 1), getFor(scope, "nameColorB", 1))
    end
    return RGB(FontScopeGet("nameColorR", 1), FontScopeGet("nameColorG", 1), FontScopeGet("nameColorB", 1))
end
local function NameColorValues(scope)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = function() return ConfiguredFontColorPreview(scope) end },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassColorPreview },
        { value = "CUSTOM", text = "Custom Color", swatchColor = function() return CustomNameColorPreview(scope) end },
    }
end
local function NPCColorValues(scope)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = function() return ConfiguredFontColorPreview(scope) end },
        { value = "NPC", text = "NPC / Reaction Color", swatchColor = NPCReactionColorPreview },
        { value = "CLASS", text = "Class Color (Reaction fallback)", swatchColor = PlayerClassColorPreview },
    }
end
local function HealthColorValues(scope)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = function() return ConfiguredFontColorPreview(scope) end },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassColorPreview },
        { value = "HEALTH", text = "Health Gradient", swatchColor = CurrentHealthGradientPreview },
    }
end
local function PowerColorValues(scope)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    return {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = function() return ConfiguredFontColorPreview(scope) end },
        { value = "RESOURCE", text = "By Power Type", swatchColor = CurrentPowerColorPreview },
    }
end
local function FontTextColorValuesFor(scope, kind)
    scope = NormalizeScopeKey(scope or CurrentFontScope())
    kind = tostring(kind or "name"):lower():gsub("[%s%-]+", "_")
    if kind == "npc" or kind == "npc_name" or kind == "boss" or kind == "boss_name" then
        return NPCColorValues(scope)
    elseif kind == "hp" or kind == "health" or kind == "health_text" then
        return HealthColorValues(scope)
    elseif kind == "power" or kind == "resource" or kind == "power_text" then
        return PowerColorValues(scope)
    end
    return NameColorValues(scope)
end
-- Shared UI source for the Fonts page and the contextual Text popup. Keeping
-- the value factories here also keeps their live swatch previews identical.
GP.FontTextColorValuesFor = FontTextColorValuesFor
local function PreviewFontKey()
    local key = FontKeyGet()
    if key == nil or key == "" then key = NormalizeFontKey(G().fontKey or "FRIZQT") end
    return key
end
local function PreviewFontFlags()
    local monochrome = FontScopeGet("fontMonochrome", false) == true
    local slug = FontScopeGet("fontSlug", false) == true
    if slug then monochrome = false end
    return ComposeFontFlags(FontOutlineGetFor(CurrentFontScope()), monochrome, slug)
end
local function ApplyPreviewFont(fs)
    if not (fs and fs.SetFont) then return end
    local key = PreviewFontKey()
    local size = max(10, min(22, tonumber(FontScopeGet("fontSize", 14)) or 14))
    local flags = PreviewFontFlags()
    local path
    local pathForKey = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
    if type(pathForKey) == "function" then path = pathForKey(key, size, flags) end
    if (not path or path == "") and key and key ~= "" then
        local fetch = _G.MSUF_FetchFontPathFromLSM or (MSUF and MSUF.MSUF_FetchFontPathFromLSM)
        if type(fetch) == "function" then path = fetch(key) end
    end
    path = path or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    local resolve = _G.MSUF_ResolveFontPath
    if type(resolve) == "function" then path = resolve(path, size, flags, key) end
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then path = resolveSafe(path, size, flags, key) end
    local applyScaleMode = _G.MSUF_ApplyFontScaleAnimationMode
    if type(applyScaleMode) == "function" then applyScaleMode(fs, flags) end
    local ok = pcall(fs.SetFont, fs, path, size, flags)
    if not ok then
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags)
    end
    local c = ConfiguredFontColorPreview()
    c[4] = NormalizeTextAlpha(FontScopeGet("fontTextAlpha", 1))
    if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    if fs.SetShadowOffset then
        local shadowOn = FontScopeGet("textBackdrop", true) == true
            and not tostring(flags):upper():find("SLUG", 1, true)
        if shadowOn then
            local a, x, y = ShadowMetrics()
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, a) end
            fs:SetShadowOffset(x, y)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
end
local function ApplyNameShortening(reason)
    ApplyFonts(reason)
    local scope = CurrentFontScope()
    if IsGFScope(scope) then return end
    if scope == "shared" then
        for _, unit in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }) do
            M.RequestUnitApply(unit, reason or "MSUF2_SHORTEN_NAMES", { text = true, preview = true })
        end
    elseif UNIT_SCOPE_KEYS[scope] then
        M.RequestUnitApply(scope, reason or "MSUF2_SHORTEN_NAMES", { text = true, preview = true })
        if scope == "targettarget" then M.RequestUnitApply("target", reason or "MSUF2_SHORTEN_NAMES", { text = true, preview = true }) end
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
    if GFNameScopeGet("nameShortenEnabled", nil) == nil then GFNameScopeSet("nameShortenEnabled", SharedNameShorteningEnabled()) end
    if GFNameScopeGet("nameClipSide", nil) == nil then GFNameScopeSet("nameClipSide", SharedNameShorteningSide()) end
    if GFNameScopeGet("nameNoEllipsis", nil) == nil then GFNameScopeSet("nameNoEllipsis", SharedNameShorteningNoEllipsis()) end
    if (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) <= 0 then GFNameScopeSet("nameMaxChars", SharedNameShorteningMax()) end
end
local function SetFontAndApply(key, value, reason, sourceKey)
    FontScopeSet(key, value, reason, sourceKey)
    ApplyFonts(reason)
end
local function FontRenderingMode()
    if FontScopeGet("fontSlug", false) == true then return "SLUG" end
    if FontScopeGet("fontMonochrome", false) == true then return "SHARP" end
    return "SMOOTH"
end
local function SetFontRenderingMode(value)
    value = tostring(value or "SMOOTH"):upper()
    local scope = CurrentFontScope()
    local slug = value == "SLUG"
    ScopeWrite(scope, "fontOverride", G(), "fontMonochrome", value == "SHARP")
    ScopeWrite(scope, "fontOverride", G(), "fontSlug", slug)
    if slug and FontOutlineGetFor(scope) == "THICKOUTLINE" then
        if IsGFScope(scope) then
            ScopeWrite(scope, "fontOverride", G(), "fontOutline", "OUTLINE")
        else
            ScopeWrite(scope, "fontOverride", G(), "boldText", false)
            ScopeWrite(scope, "fontOverride", G(), "noOutline", false)
        end
    end
    ApplyFonts("MSUF2_FONT_RENDERING")
end
local function BuildFonts(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Fonts", "Shared font, text style, name and power colors.", 72)
    local scopeValues = GP.SCOPE_VALUES
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
    local function RefreshFontsPage(reason)
        if M.RequestRefresh then
            M.RequestRefresh(ctx, reason)
        elseif M.Refresh then
            M.Refresh(ctx)
        elseif M.SelectPage then
            M.SelectPage(ctx.key)
        end
    end
    GP.BuildScopeOverrideSection(ctx, b, {
        values = scopeValues,
        selectorMeta = Meta("scope.selector", "ephemeral"),
        selectorOptionMeta = function(value) return Meta("scope.selector.option." .. tostring(value), "ephemeral") end,
        overrideMeta = Meta("scope.override.enabled"),
        resetMeta = Meta("scope.overrides.reset", "action"),
        getValue = function() return CurrentFontScope() end,
        setValue = function(v)
            G()._fontScopeKey = NormalizeScopeKey(v)
            if M.InvalidatePage then M.InvalidatePage(ctx.key) end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "fontOverride")
        end,
        getOverride = function()
            local key = CurrentFontScope()
            return key ~= "shared" and ScopeHasOverride(key, "fontOverride")
        end,
        setOverride = function(v)
            local key = CurrentFontScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "fontOverride", v)
                if v and IsGFScope(key) then SeedGFNameShorteningFromShared() end
                ApplyFonts("MSUF2_FONT_OVERRIDE")
            end
            RefreshFontsPage("fonts-scope-override")
        end,
        activeLabels = ActiveFontOverrideLabels,
        heightPad = 34,
        reset = function()
            for i = 1, #scopeValues do
                local key = scopeValues[i].value
                if key ~= "shared" then ScopeSetOverride(key, "fontOverride", false) end
            end
            ApplyFonts("MSUF2_FONT_RESET_OVERRIDES")
            RefreshFontsPage("fonts-reset-overrides")
        end,
        hint = "Shared baseline plus per-unit and group-frame font overrides.",
        updateHint = function(hint, current, active, shared)
            if shared then
                if #active > 0 then
                    hint:SetText(M.Tr("Shared font settings are the baseline. Active overrides keep their own font and name-shortening settings."))
                else
                    hint:SetText(M.Tr("Shared font settings are the baseline for units and group frames."))
                end
            elseif ScopeHasOverride(current, "fontOverride") then
                hint:SetText(M.Tr("This scope is using custom font settings. Shared changes will not affect it until the override is reset."))
            else
                hint:SetText(M.Tr("This scope follows Shared font settings. Turn on custom settings here only when this scope needs different fonts."))
            end
        end,
    })
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
    local function RefreshShadowPreview()
        if not (preview and preview.SetShadowOffset) then return end
        if FontScopeGet("textBackdrop", true) == true and FontRenderingMode() ~= "SLUG" then
            local alpha, x, y = ShadowMetrics()
            if preview.SetShadowColor then preview:SetShadowColor(0, 0, 0, alpha) end
            preview:SetShadowOffset(x, y)
        else
            preview:SetShadowOffset(0, 0)
        end
    end
    M.BindDropdownWidget(ctx, fontDrop,
        function() return FontKeyGet() end,
        function(v)
            FontKeySet(v)
            if type(_G.MSUF_NormalizeStoredFontKeys) == "function" then _G.MSUF_NormalizeStoredFontKeys() end
            ApplyFonts("MSUF2_FONT_KEY")
            RefreshFontPreview()
        end,
        Meta("font.family"))
    M.TrackRefresh(ctx, RefreshFontPreview)
    local RefreshScopedFontControls = M.RefreshProxy()
    local text = b:CollapsibleSection("fonts_text_style", "Text Style", 430, true)
    local function BindTextSegment(label, values, width, getValue, setValue, path, afterSet)
        local control = W.Segment(text, label, values, width)
        M.BindSegment(ctx, control, getValue, function(v)
            setValue(v)
            RefreshFontPreview()
            M.CallIf(afterSet)
        end, Meta(path))
        return control
    end
    local outline = W.Segment(text, "Outline", VT("OUTLINE", "Outline", "THICKOUTLINE", "Thick Outline", "NONE", "None"), 420)
    M.BindSegment(ctx, outline,
        function() return FontOutlineGetFor(CurrentFontScope()) end,
        function(v)
            FontOutlineSetFor(CurrentFontScope(), v)
            RefreshFontPreview()
        end,
        Meta("text_style.outline"))
    local rendering = BindTextSegment("Rendering", VT("SMOOTH", "Smooth", "SHARP", "Sharp / Pixel", "SLUG", "Slug"), 420,
        FontRenderingMode,
        SetFontRenderingMode,
        "text_style.rendering",
        function() RefreshScopedFontControls() end)
    if M.AddTooltip then
        M.AddTooltip(rendering, "Font rendering",
            "Slug uses WoW's crisp vector font renderer. Slug supports None or normal Outline; Thick Outline and text shadow are unavailable while it is active.",
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local shadow = BindTextSegment("Text shadow", VT("ON", "On", "OFF", "Off"), 260,
        function() return FontScopeGet("textBackdrop", true) and "ON" or "OFF" end,
        function(v) SetFontAndApply("textBackdrop", v == "ON", "MSUF2_FONT_SHADOW") end,
        "text_style.shadow.enabled",
        function() RefreshScopedFontControls() end)
    local shadowOpacity = W.Slider(text, "Shadow opacity", 0.20, 1, 0.05, 300)
    local shadowOpacityApplyTimer
    local shadowOpacityApplyPending
    local shadowOpacityApplyScope
    local function CancelShadowOpacityApplyTimer()
        if shadowOpacityApplyTimer and shadowOpacityApplyTimer.Cancel then
            shadowOpacityApplyTimer:Cancel()
        end
        shadowOpacityApplyTimer = nil
    end
    local function FlushShadowOpacityApply()
        if not shadowOpacityApplyPending then return end
        shadowOpacityApplyPending = nil
        CancelShadowOpacityApplyTimer()
        M.RequestGeneralApply("MSUF2_FONT_SHADOW_OPACITY", {
            history = false,
            preview = true,
            applyAll = false,
            fonts = true,
            fontScope = shadowOpacityApplyScope or CurrentFontScope(),
        })
        shadowOpacityApplyScope = nil
    end
    local function QueueShadowOpacityApply()
        shadowOpacityApplyPending = true
        shadowOpacityApplyScope = CurrentFontScope()
        CancelShadowOpacityApplyTimer()
        -- A drag updates only the single sample FontString. The runtime refresh
        -- is committed once by OnMouseUp, never once per OnValueChanged tick.
        if shadowOpacity._msuf2SliderActive then return end
        if C_Timer and C_Timer.NewTimer then
            shadowOpacityApplyTimer = C_Timer.NewTimer(SHADOW_OPACITY_APPLY_DELAY, FlushShadowOpacityApply)
        else
            FlushShadowOpacityApply()
        end
    end
    if M.UsePercentInput then M.UsePercentInput(shadowOpacity) end
    M.BindNumberWidget(ctx, shadowOpacity,
        function()
            local alpha = ShadowMetrics()
            return alpha
        end,
        function(v)
            SetShadowValueWithoutApply("fontShadowOpacity", NormalizeShadowOpacity(v))
            RefreshShadowPreview()
            QueueShadowOpacityApply()
        end,
        1, Meta("text_style.shadow.opacity", "setting", { step = 0.05 }))
    shadowOpacity:HookScript("OnMouseUp", FlushShadowOpacityApply)
    shadowOpacity:HookScript("OnHide", FlushShadowOpacityApply)
    local shadowDistance = BindTextSegment("Shadow distance", VT(1, "1 px", 2, "2 px"), 260,
        function()
            local _, distance = ShadowMetrics()
            return distance
        end,
        function(v) SetShadowAndApply("fontShadowDistance", NormalizeShadowDistance(v), "MSUF2_FONT_SHADOW_DISTANCE") end,
        "text_style.shadow.distance")
    local opacity = BindTextSegment("Text opacity", VT(1, "100%", 0.85, "85%", 0.70, "70%"), 320,
        function() return NormalizeTextAlpha(FontScopeGet("fontTextAlpha", 1)) end,
        function(v) SetFontAndApply("fontTextAlpha", NormalizeTextAlpha(v), "MSUF2_FONT_TEXT_ALPHA") end,
        "text_style.opacity")
    W.NextRow(text, 8)
    local baseline = W.Slider(text, "Baseline", -4, 4, 1, 300)
    baseline:SetValueFormatter(function(v)
        v = NormalizeBaselineOffset(v)
        if v > 0 then return "+" .. tostring(v) .. " px" end
        return tostring(v) .. " px"
    end)
    M.BindNumberWidget(ctx, baseline,
        function() return NormalizeBaselineOffset(FontScopeGet("fontBaselineOffset", 0)) end,
        function(v) SetFontAndApply("fontBaselineOffset", NormalizeBaselineOffset(v), "MSUF2_FONT_BASELINE") end,
        0, Meta("text_style.baseline", "setting", { step = 1, roundStep = true }))
    local function BindFontDropdown(parent, label, values, getValue, setValue, width, path)
        local control = W.Dropdown(parent, label, values, width or 280)
        M.BindDropdownWidget(ctx, control, getValue, setValue, Meta(path))
        return control
    end
    local function BindFontColorModeDropdown(parent, label, values, kind, path)
        return BindFontDropdown(parent, label, values,
            function() return FontTextColorModeGetFor(CurrentFontScope(), kind) end,
            function(v) FontTextColorModeSetFor(CurrentFontScope(), kind, v) end,
            nil,
            path)
    end
    local function BuildNameShorteningControls(parent, label, minChars, noticeFallbackY, getEnabled, setEnabled, getSide, setSide, getChars, setChars, getNoEllipsis, setNoEllipsis, formatChars)
        local controls = {}
        controls.shorten = W.Toggle(parent, label)
        M.BindBoolWidget(ctx, controls.shorten, getEnabled, setEnabled, Meta("name_shortening.enabled"))
        controls.side = W.Segment(parent, "Truncation style", VT("LEFT", "Keep end (last letters)", "RIGHT", "Keep start (first letters)"), 430)
        M.BindSegment(ctx, controls.side, getSide, setSide, Meta("name_shortening.style"))
        controls.chars = W.Slider(parent, "Max name length", minChars or 4, 30, 1, 300)
        if formatChars then controls.chars:SetValueFormatter(formatChars) end
        M.BindNumberWidget(ctx, controls.chars, getChars, setChars, minChars or 4,
            Meta("name_shortening.max_length", "setting", { step = 1, roundStep = true }))
        controls.noEllipsis = W.Toggle(parent, "No Ellipsis (truncate without ..)")
        M.BindBoolWidget(ctx, controls.noEllipsis, getNoEllipsis, setNoEllipsis, Meta("name_shortening.no_ellipsis"))
        local scopeNoticeY = (parent._msuf2CursorY or noticeFallbackY or -194) - 8
        controls.scopeNotice = W.Text(parent, "", 14, scopeNoticeY, ctx.width - 28, T.colors.muted)
        if controls.scopeNotice.SetWordWrap then controls.scopeNotice:SetWordWrap(true) end
        if controls.scopeNotice.SetHeight then controls.scopeNotice:SetHeight(44) end
        return controls
    end
    local colors = b:CollapsibleSection("fonts_name_power_colors", "Text Colors", 280, true)
    local nameColor = BindFontColorModeDropdown(colors, "Player Name Color", NameColorValues, "name", "colors.player_name")
    local npcColor = BindFontColorModeDropdown(colors, "NPC / Boss Name Color", NPCColorValues, "npc", "colors.npc_name")
    local healthColor = BindFontColorModeDropdown(colors, "HP Text Color", HealthColorValues, "hp", "colors.colorHealthTextByHealth")
    local powerColor = BindFontColorModeDropdown(colors, "Power Text Color", PowerColorValues, "power", "colors.colorPowerTextByType")
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(colors, { "font.default.current" }, {
            title = "Default Font Color",
            note = "Uses this Fonts scope's effective Default font color.",
            historySource = "menu:fonts-global-font-color",
            context = function() return { scope = CurrentFontScope() } end,
        })
    end
    local scopedFontControls = { outline, rendering, shadow, shadowOpacity, shadowDistance, opacity, baseline, nameColor, healthColor, powerColor }
    RefreshScopedFontControls = RefreshScopedFontControls(function()
        local scopeKey = CurrentFontScope()
        local canEdit = CurrentFontScopeCanEdit()
        local gfScope = IsGFScope(scopeKey)
        SetControlsEnabled(scopedFontControls, canEdit)
        local slug = FontRenderingMode() == "SLUG"
        SetControlEnabled(shadow, canEdit and not slug)
        local shadowEnabled = canEdit and not slug and FontScopeGet("textBackdrop", true) == true
        SetControlEnabled(shadowOpacity, shadowEnabled)
        SetControlEnabled(shadowDistance, shadowEnabled)
        SetControlEnabled(npcColor, canEdit and not gfScope)
    end)
    M.TrackRefresh(ctx, RefreshScopedFontControls)
    local nameScope = CurrentFontScope()
    if IsGFScope(nameScope) then
        local names = b:CollapsibleSection("fonts_name_shortening", "Name Shortening", 288, true)
        names._msuf2CursorY = -40
        local shorten, side, chars, noEllipsis
        local function RefreshGFNameShorteningUI()
            if M.RequestRefresh then M.RequestRefresh(ctx, "fonts-gf-name-shortening") elseif M.Refresh then M.Refresh(ctx) end
        end
        local controls = BuildNameShorteningControls(names, "Shorten group names", 1, -194,
            function()
                if GFNameUsesLocalScope() then return GFNameScopeGet("nameShortenEnabled", (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) > 0) and true or false end
                return SharedNameShorteningEnabled()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                GFNameScopeSet("nameShortenEnabled", v and true or false)
                if v and (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) <= 0 then GFNameScopeSet("nameMaxChars", SharedNameShorteningMax()) end
                ApplyFonts("MSUF2_GF_NAME_SHORTEN")
                RefreshGFNameShorteningUI()
            end,
            function()
                if GFNameUsesLocalScope() then return GFNameScopeGet("nameClipSide", "RIGHT") end
                return SharedNameShorteningSide()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                GFNameScopeSet("nameClipSide", v or "RIGHT")
                ApplyFonts("MSUF2_GF_NAME_SHORTEN_SIDE")
                RefreshGFNameShorteningUI()
            end,
            function()
                if GFNameUsesLocalScope() then return tonumber(GFNameScopeGet("nameMaxChars", 6)) or 6 end
                return SharedNameShorteningMax()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                v = floor((tonumber(v) or 6) + 0.5)
                GFNameScopeSet("nameMaxChars", v)
                ApplyFonts("MSUF2_GF_NAME_MAX")
                RefreshGFNameShorteningUI()
            end,
            function()
                if GFNameUsesLocalScope() then return GFNameScopeGet("nameNoEllipsis", false) and true or false end
                return SharedNameShorteningNoEllipsis()
            end,
            function(v)
                if not GFNameUsesLocalScope() then return end
                GFNameScopeSet("nameNoEllipsis", v and true or false)
                ApplyFonts("MSUF2_GF_NAME_ELLIPSIS")
                RefreshGFNameShorteningUI()
            end,
            function(v) return tostring(floor((tonumber(v) or 6) + 0.5)) end)
        shorten, side, chars, noEllipsis = controls.shorten, controls.side, controls.chars, controls.noEllipsis
        local scopeNotice, gfNameShorteningControls = controls.scopeNotice, { side, chars, noEllipsis }
        local function RefreshGFNameShorteningControls()
            local canEdit = CurrentFontScopeCanEdit()
            local enabled
            if GFNameUsesLocalScope() then
                enabled = GFNameScopeGet("nameShortenEnabled", (tonumber(GFNameScopeGet("nameMaxChars", 0)) or 0) > 0) == true
            else
                enabled = SharedNameShorteningEnabled()
            end
            SetControlEnabled(shorten, canEdit)
            SetControlsEnabled(gfNameShorteningControls, canEdit and enabled)
            if GFNameUsesLocalScope() then
                scopeNotice:SetText(M.Tr("This group scope uses custom font settings. Shared name-shortening changes will not affect it until the override is reset."))
            else
                scopeNotice:SetText(M.Tr("This group scope follows Shared name shortening. Turn on custom settings above only when group names need different truncation."))
            end
        end
        M.TrackRefresh(ctx, RefreshGFNameShorteningControls)
    else
        local names = b:CollapsibleSection("fonts_name_shortening", "Name Shortening", 294, true)
        local shorten, side, chars, noEllipsis, scopeNotice, nameShorteningControls
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
            SetControlsEnabled(nameShorteningControls, canEdit and enabled)
            SetControlEnabled(noEllipsis, canEdit)
            if scopeNotice then
                local current = CurrentFontScope()
                if current == "shared" then
                    local active = ActiveFontOverrideLabels()
                    if #active > 0 then
                        scopeNotice:SetText("|cffffd200" .. M.Tr("Font overrides active:") .. "|r "
                            .. table.concat(active, ", ")
                            .. M.Tr(". Shared name-shortening changes do not affect those scopes."))
                    else
                        scopeNotice:SetText(M.Tr("Shared name shortening affects all unit names and group frames unless a scope has custom font settings."))
                    end
                elseif ScopeHasOverride(current, "fontOverride") then
                    scopeNotice:SetText(M.Tr("This scope uses custom font settings. Shared name-shortening changes will not affect it until the override is reset."))
                else
                    scopeNotice:SetText(M.Tr("This scope follows Shared name shortening. Turn on custom settings above only when this scope needs different names."))
                end
            end
        end
        local function ApplyNameShorteningChange(reason, onlyWhenEnabled)
            RefreshNameShorteningControls()
            if (not onlyWhenEnabled) or NameShorteningEnabled() then ApplyNameShortening(reason) end
        end
        local controls = BuildNameShorteningControls(names,
            nameScope == "shared" and "Shorten names" or "Shorten unit names",
            4, -194, NameShorteningEnabled,
            function(v)
                FontScopeSet("shortenNames", v and true or false, "MSUF2_SHORTEN_NAMES", "shortenNames")
                ApplyNameShorteningChange("MSUF2_SHORTEN_NAMES", false)
            end,
            function() return FontScopeGet("shortenNameClipSide", "LEFT") end,
            function(v)
                FontScopeSet("shortenNameClipSide", v or "LEFT", "MSUF2_SHORTEN_SIDE")
                ApplyNameShorteningChange("MSUF2_SHORTEN_SIDE", true)
            end,
            function() return tonumber(FontScopeGet("shortenNameMaxChars", 6)) or 6 end,
            function(v)
                FontScopeSet("shortenNameMaxChars", floor((tonumber(v) or 6) + 0.5), "MSUF2_SHORTEN_MAX")
                ApplyNameShorteningChange("MSUF2_SHORTEN_MAX", true)
            end,
            function() return not FontScopeGet("shortenNameShowDots", true) end,
            function(v)
                FontScopeSet("shortenNameShowDots", not (v and true or false), "MSUF2_SHORTEN_DOTS")
                ApplyNameShorteningChange("MSUF2_SHORTEN_DOTS", false)
            end)
        shorten, side, chars, noEllipsis, scopeNotice = controls.shorten, controls.side, controls.chars, controls.noEllipsis, controls.scopeNotice; nameShorteningControls = { side, chars }
        M.TrackRefresh(ctx, RefreshNameShorteningControls)
    end
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_fonts", { title = "MSUF Fonts", build = BuildFonts, version = 6 })
