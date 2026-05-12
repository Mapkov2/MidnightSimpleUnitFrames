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

local function BuildFonts(ctx)
    local b = W.PageBuilder(ctx)

    local scopeValues = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "targettarget", text = "ToT" },
        { value = "focus", text = "Focus" },
        { value = "pet", text = "Pet" },
        { value = "boss", text = "Boss" },
        { value = "gf_party", text = "Party" },
        { value = "gf_raid", text = "Raid" },
    }

    local scope = b:Section("", 128)
    if scope.title then scope.title:Hide() end
    local scopeSeg = W.ScopeOverrideBar(ctx, scope, {
        values = scopeValues,
        getValue = function() return CurrentFontScope() end,
        setValue = function(v)
            G()._fontScopeKey = NormalizeScopeKey(v)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "fontOverride")
        end,
    })

    local override = W.ToggleAt(scope, "Override shared settings", 14, -58, 220)
    M.BindToggle(ctx, override,
        function()
            local key = CurrentFontScope()
            return key ~= "shared" and ScopeHasOverride(key, "fontOverride")
        end,
        function(v)
            local key = CurrentFontScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "fontOverride", v)
                ApplyFonts("MSUF2_FONT_OVERRIDE")
            end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    local overrideInfo = W.Text(scope, "", 14, -58, ctx.width - 130, T.colors.text)
    local reset = T.Button(scope, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -14, -50)
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
    local hint = W.Text(scope, "Shared baseline plus per-unit and group-frame font overrides.", 14, -92, ctx.width - 28, T.colors.muted)
    M.AddRefresher(ctx, function()
        local current = CurrentFontScope()
        local active = {}
        for i = 1, #scopeValues do
            local item = scopeValues[i]
            if item.value ~= "shared" and ScopeHasOverride(item.value, "fontOverride") then active[#active + 1] = item.text end
        end
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        overrideInfo:SetText("|cffffffffOverrides:|r " .. (#active > 0 and table.concat(active, ", ") or "None"))
        scopeSeg:Refresh()
        hint:SetWidth(ctx.width - 28)
    end)

    local font = b:CollapsibleSection("fonts_global_font", "Global Font", 112, true)
    local fontDrop = W.Dropdown(font, "Font (SharedMedia)", function() return FontValues(IsGFScope(CurrentFontScope())) end, 340)
    M.BindDropdown(ctx, fontDrop,
        function() return FontKeyGet() end,
        function(v)
            FontKeySet(v)
            M.RequestGeneralApply("MSUF2_FONT_KEY", { preview = true, applyAll = false })
            if type(_G.MSUF_NormalizeStoredFontKeys) == "function" then _G.MSUF_NormalizeStoredFontKeys() end
            ApplyFonts("MSUF2_FONT_KEY")
        end)

    local text = b:CollapsibleSection("fonts_text_style", "Text Style", 212, true)
    local fontSize = W.Slider(text, "Font size", 6, 32, 1, 300)
    M.BindSlider(ctx, fontSize,
        function() return tonumber(FontScopeGet("fontSize", 14)) or 14 end,
        function(v)
            FontScopeSet("fontSize", floor((tonumber(v) or 14) + 0.5), "MSUF2_FONT_SIZE")
            ApplyFonts("MSUF2_FONT_SIZE")
        end)

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

    local names = b:CollapsibleSection("fonts_name_shortening", "Name Shortening", 250, true)
    local shorten = W.Toggle(names, "Shorten names")
    M.BindToggle(ctx, shorten,
        function()
            if IsGFScope(CurrentFontScope()) then return false end
            return FontScopeGet("shortenNames", false, "shortenNames") and true or false
        end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNames", v and true or false, "MSUF2_SHORTEN_NAMES", "shortenNames")
            ApplyFonts("MSUF2_SHORTEN_NAMES")
        end)

    local side = W.Segment(names, "Clip side", {
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, 260)
    M.BindSegment(ctx, side,
        function() return FontScopeGet("shortenNameClipSide", "LEFT") end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNameClipSide", v or "LEFT", "MSUF2_SHORTEN_SIDE")
            ApplyFonts("MSUF2_SHORTEN_SIDE")
        end)

    local chars = W.Slider(names, "Max characters", 2, 64, 1, 300)
    M.BindSlider(ctx, chars,
        function() return tonumber(FontScopeGet("shortenNameMaxChars", 6)) or 6 end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNameMaxChars", floor((tonumber(v) or 6) + 0.5), "MSUF2_SHORTEN_MAX")
            ApplyFonts("MSUF2_SHORTEN_MAX")
        end)

    local dots = W.Toggle(names, "Show ellipsis")
    M.BindToggle(ctx, dots,
        function() return FontScopeGet("shortenNameShowDots", true) and true or false end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNameShowDots", v and true or false, "MSUF2_SHORTEN_DOTS")
            ApplyFonts("MSUF2_SHORTEN_DOTS")
        end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_fonts", { title = "MSUF Fonts", build = BuildFonts, version = 2 })
