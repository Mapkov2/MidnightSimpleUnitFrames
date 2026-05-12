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
local CurrentGradientDirections = GP.CurrentGradientDirections
local SetGradientDirection = GP.SetGradientDirection
local ToggleGradientDirection = GP.ToggleGradientDirection
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
local function BuildBars(ctx)
    local b = W.PageBuilder(ctx)

    local function SharedBarsControlsActive()
        return CurrentBarsScope() == "shared"
    end

    local function ScopedBarsControlsActive()
        local scope = CurrentBarsScope()
        return scope == "shared" or BarsScopeHasOverride(scope)
    end

    local function TextBarsControlsActive()
        local scope = CurrentBarsScope()
        return (not IsGFScope(scope)) and (scope == "shared" or BarsScopeHasOverride(scope))
    end

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
        getValue = function() return CurrentBarsScope() end,
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            if _G.MSUF_AbsorbTextureTestMode then SetAbsorbTextureTest(true) end
            RefreshBorderTestModes()
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and BarsScopeHasOverride(value)
        end,
    })
    local override = W.ToggleAt(scope, "Override shared settings", 14, -58, 220)
    M.BindToggle(ctx, override,
        function()
            local key = CurrentBarsScope()
            return BarsScopeHasOverride(key)
        end,
        function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                BarsScopeSetOverride(key, v)
                ApplyBars("MSUF2_BARS_OVERRIDE")
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
            if key ~= "shared" then BarsScopeSetOverride(key, false) end
        end
        ApplyBars("MSUF2_BARS_RESET_OVERRIDES")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local hint = W.Text(scope, "Group Frames inherit Shared textures and gradients by default. Raid also applies to Mythic Raid.", 14, -92, ctx.width - 28, T.colors.muted)
    M.AddRefresher(ctx, function()
        local current = CurrentBarsScope()
        local active = {}
        for i = 1, #scopeValues do
            local item = scopeValues[i]
            if item.value ~= "shared" and BarsScopeHasOverride(item.value) then active[#active + 1] = item.text end
        end
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        if #active > 0 then
            overrideInfo:SetText("|cffffffffOverrides:|r " .. table.concat(active, ", "))
        else
            overrideInfo:SetText("|cffffffffOverrides:|r None")
        end
        scopeSeg:Refresh()
        hint:SetWidth(ctx.width - 28)
    end)

    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", 214, true)
    local leftX, topY = 14, -42
    local rightX = math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = math.min(300, math.max(220, rightX - 48))

    local barTexture = W.Dropdown(textures, "Bar textures (SharedMedia)", function() return TextureValues(nil) end, 280)
    if barTexture._msuf2Title then
        barTexture._msuf2Title:ClearAllPoints()
        barTexture._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY)
    end
    barTexture:ClearAllPoints()
    barTexture:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY - 22)
    barTexture:SetWidth(leftW)
    M.BindDropdown(ctx, barTexture,
        function() return ReadG("barTexture", "Blizzard") end,
        function(v) SetG("barTexture", v or "Blizzard", "MSUF2_BAR_TEXTURE", { preview = true }); ApplyBars("MSUF2_BAR_TEXTURE") end)
    local bgTexture = W.Dropdown(textures, "Background texture", function() return TextureValues("Use foreground texture") end, 280)
    if bgTexture._msuf2Title then
        bgTexture._msuf2Title:ClearAllPoints()
        bgTexture._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY - 54)
    end
    bgTexture:ClearAllPoints()
    bgTexture:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY - 76)
    bgTexture:SetWidth(leftW)
    M.BindDropdown(ctx, bgTexture,
        function() return ReadG("barBackgroundTexture", "") end,
        function(v) SetG("barBackgroundTexture", v or "", "MSUF2_BAR_BG_TEXTURE", { preview = true }); ApplyBars("MSUF2_BAR_BG_TEXTURE") end)

    local gradLabel = T.Font(textures, "GameFontHighlightSmall", "Gradient", T.colors.muted)
    gradLabel:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, topY)
    local hpGradient = W.ToggleAt(textures, "HP bar gradient", rightX, topY - 24, 180)
    M.BindToggle(ctx, hpGradient,
        function() return BarScopeGet("enableGradient", true) ~= false end,
        function(v) BarScopeSet("enableGradient", v and true or false, "MSUF2_HP_GRADIENT"); ApplyBars("MSUF2_HP_GRADIENT") end)
    local powerGradient = W.ToggleAt(textures, "Power bar gradient", rightX, topY - 54, 190)
    M.BindToggle(ctx, powerGradient,
        function() return BarScopeGet("enablePowerGradient", false) == true end,
        function(v) BarScopeSet("enablePowerGradient", v and true or false, "MSUF2_POWER_GRADIENT"); ApplyBars("MSUF2_POWER_GRADIENT") end)
    local strength = W.Slider(textures, "Gradient strength", 0, 1, 0.05, 220)
    if strength._msuf2Title then
        strength._msuf2Title:ClearAllPoints()
        strength._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, topY - 90)
        strength._msuf2Title:SetWidth(220)
    end
    strength:ClearAllPoints()
    strength:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, topY - 112)
    strength:SetWidth(220)
    if strength._msuf2UpdateFill then strength:_msuf2UpdateFill() end
    M.BindSlider(ctx, strength,
        function() return tonumber(BarScopeGet("gradientStrength", 0.45)) or 0.45 end,
        function(v) BarScopeSet("gradientStrength", tonumber(v) or 0.45, "MSUF2_GRADIENT_STRENGTH"); ApplyBars("MSUF2_GRADIENT_STRENGTH") end)

    local padX = math.min(rightX + 238, (ctx.width or 720) - 104)
    local pad = T.Panel(textures, nil, { 0.020, 0.024, 0.046, 0.55 }, T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, topY - 18)
    pad:SetSize(84, 64)
    local center = pad:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER", pad, "CENTER", 0, 0)
    center:SetSize(10, 10)
    center:SetColorTexture(0.23, 0.25, 0.34, 0.95)
    local directionButtons = {}
    local function PadButton(text, value, x, y)
        local btn = T.Button(pad, text, 22, 18)
        btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, y)
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2Label:SetJustifyH("CENTER")
        btn:SetScript("OnClick", function()
            if ToggleGradientDirection then
                ToggleGradientDirection(value or "RIGHT")
            else
                SetGradientDirection(value or "RIGHT")
            end
            ApplyBars("MSUF2_GRADIENT_DIRECTION")
        end)
        directionButtons[value] = btn
        return btn
    end
    PadButton("^", "UP", 31, -5)
    PadButton("<", "LEFT", 8, -27)
    PadButton(">", "RIGHT", 54, -27)
    PadButton("v", "DOWN", 31, -49)
    M.AddRefresher(ctx, function()
        local current = (CurrentGradientDirections and CurrentGradientDirections()) or { [CurrentGradientDirection()] = true }
        local controlsActive = ScopedBarsControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local valueControlsActive = controlsActive and ((BarScopeGet("enableGradient", true) ~= false) or (BarScopeGet("enablePowerGradient", false) == true))
        SetControlEnabled(barTexture, sharedActive)
        SetControlEnabled(bgTexture, sharedActive)
        SetControlEnabled(hpGradient, controlsActive)
        SetControlEnabled(powerGradient, controlsActive)
        SetControlEnabled(strength, valueControlsActive)
        pad:SetAlpha(valueControlsActive and 1 or 0.45)
        for value, btn in pairs(directionButtons) do
            btn:SetActive(current[value] == true)
            SetControlEnabled(btn, valueControlsActive)
        end
    end)

    local absorb = b:CollapsibleSection("bars_absorb", "Absorb Display", 336, true)
    local absorbW = absorb._msuf2Width or ctx.width or 720
    local absorbLeftX = 30
    local absorbRightX = max(430, min(560, floor(absorbW * 0.52)))
    local absorbLeftW = max(300, min(380, absorbRightX - absorbLeftX - 58))
    local absorbRightW = max(300, min(420, absorbW - absorbRightX - 42))

    W.LabelAt(absorb, "Display", absorbLeftX, -42, absorbLeftW, "GameFontNormalSmall", T.colors.accent)
    local absorbMode = W.Dropdown(absorb, "Display mode", {
        { value = 1, text = "Absorb off" },
        { value = 2, text = "Absorb bar" },
        { value = 3, text = "Absorb bar + text" },
        { value = 4, text = "Absorb text only" },
    }, absorbLeftW)
    M.BindDropdown(ctx, absorbMode,
        function() return tonumber(BarScopeGet("absorbTextMode", 2)) or 2 end,
        function(v) BarScopeSet("absorbTextMode", tonumber(v) or 2, "MSUF2_ABSORB_MODE"); ApplyBars("MSUF2_ABSORB_MODE") end)
    W.MoveWidget(absorbMode, absorb, absorbLeftX, -70, absorbLeftW, "LEFT")

    local absorbAnchor = W.Dropdown(absorb, "Absorb bar anchoring", {
        { value = 1, text = "Anchor to left side" },
        { value = 2, text = "Anchor to right side" },
        { value = 3, text = "Follow HP bar" },
        { value = 4, text = "Follow HP bar (overflow)" },
        { value = 5, text = "Reverse from max" },
    }, absorbLeftW)
    M.BindDropdown(ctx, absorbAnchor,
        function() return tonumber(BarScopeGet("absorbAnchorMode", 2)) or 2 end,
        function(v) BarScopeSet("absorbAnchorMode", tonumber(v) or 2, "MSUF2_ABSORB_ANCHOR"); ApplyBars("MSUF2_ABSORB_ANCHOR") end)
    W.MoveWidget(absorbAnchor, absorb, absorbLeftX, -124, absorbLeftW, "LEFT")

    local selfHeal = W.ToggleAt(absorb, "Heal prediction", absorbLeftX, -186, absorbLeftW)
    M.BindToggle(ctx, selfHeal,
        function() return ReadGBool("showSelfHealPrediction", true) end,
        function(v) SetGBool("showSelfHealPrediction", v, "MSUF2_SELF_HEAL", { preview = true }); ApplyBars("MSUF2_SELF_HEAL") end)

    local absorbOpacity = W.Slider(absorb, "Absorb bar opacity", 0, 1, 0.05, absorbLeftW)
    M.BindSlider(ctx, absorbOpacity,
        function() return tonumber(BarScopeGet("absorbBarOpacity", 0.75)) or 0.75 end,
        function(v) BarScopeSet("absorbBarOpacity", tonumber(v) or 0.75, "MSUF2_ABSORB_OPACITY"); ApplyBars("MSUF2_ABSORB_OPACITY") end)
    W.MoveWidget(absorbOpacity, absorb, absorbLeftX, -240, absorbLeftW, "LEFT")

    W.LabelAt(absorb, "Textures", absorbRightX, -42, absorbRightW, "GameFontNormalSmall", T.colors.accent)
    local absorbTex = W.Dropdown(absorb, "Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, absorbRightW)
    M.BindDropdown(ctx, absorbTex,
        function() return ReadG("absorbBarTexture", "") end,
        function(v) SetG("absorbBarTexture", v or "", "MSUF2_ABSORB_TEXTURE", { preview = true }); Call("MSUF_UpdateAbsorbBarTextures"); ApplyBars("MSUF2_ABSORB_TEXTURE") end)
    W.MoveWidget(absorbTex, absorb, absorbRightX, -70, absorbRightW, "LEFT")

    local healAbsorbTex = W.Dropdown(absorb, "Heal-absorb texture", function() return TextureValues("Use foreground texture") end, absorbRightW)
    M.BindDropdown(ctx, healAbsorbTex,
        function() return ReadG("healAbsorbBarTexture", "") end,
        function(v) SetG("healAbsorbBarTexture", v or "", "MSUF2_HEAL_ABSORB_TEXTURE", { preview = true }); Call("MSUF_UpdateAbsorbBarTextures"); ApplyBars("MSUF2_HEAL_ABSORB_TEXTURE") end)
    W.MoveWidget(healAbsorbTex, absorb, absorbRightX, -124, absorbRightW, "LEFT")

    local absorbTest = W.ToggleAt(absorb, "Test absorb textures", absorbRightX, -186, absorbRightW)
    M.BindToggle(ctx, absorbTest,
        function() return _G.MSUF_AbsorbTextureTestMode and true or false end,
        function(v) SetAbsorbTextureTest(v and true or false) end)
    absorbTest:HookScript("OnHide", function() ClearAbsorbTextureTest() end)

    local healAbsorbOpacity = W.Slider(absorb, "Heal-absorb bar opacity", 0, 1, 0.05, absorbRightW)
    M.BindSlider(ctx, healAbsorbOpacity,
        function() return tonumber(BarScopeGet("healAbsorbBarOpacity", 1)) or 1 end,
        function(v) BarScopeSet("healAbsorbBarOpacity", tonumber(v) or 1, "MSUF2_HEAL_ABSORB_OPACITY"); ApplyBars("MSUF2_HEAL_ABSORB_OPACITY") end)
    W.MoveWidget(healAbsorbOpacity, absorb, absorbRightX, -240, absorbRightW, "LEFT")

    M.AddRefresher(ctx, function()
        local mode = tonumber(BarScopeGet("absorbTextMode", 2)) or 2
        local showBar = mode == 2 or mode == 3
        local scopedActive = ScopedBarsControlsActive()
        local sharedActive = SharedBarsControlsActive()
        SetControlEnabled(absorbMode, scopedActive)
        SetControlEnabled(absorbAnchor, scopedActive and showBar)
        SetControlEnabled(absorbTex, sharedActive and showBar)
        SetControlEnabled(healAbsorbTex, sharedActive and showBar)
        SetControlEnabled(absorbTest, showBar)
        SetControlEnabled(absorbOpacity, scopedActive and showBar)
        SetControlEnabled(healAbsorbOpacity, scopedActive and showBar)
        SetControlEnabled(selfHeal, sharedActive and mode ~= 1)
    end)

    local outline = b:CollapsibleSection("bars_outline", "Frame Outline", 126, false)
    local outlineSlider = W.Slider(outline, "Bar outline thickness", 0, 8, 1, 300)
    M.BindSlider(ctx, outlineSlider,
        function() return tonumber(BarScopeGetBars("barOutlineThickness", 1)) or 1 end,
        function(v) BarScopeSetBars("barOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_BAR_OUTLINE"); ApplyBars("MSUF2_BAR_OUTLINE") end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(outlineSlider, ScopedBarsControlsActive())
    end)

    local highlights = b:CollapsibleSection("bars_highlight", "Highlight Borders", 626, true)
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlLeftX = 30
    local hlRightX = max(430, min(560, floor(hlW * 0.52)))
    local hlLeftW = max(300, min(380, hlRightX - hlLeftX - 58))
    local hlRightW = max(300, min(420, hlW - hlRightX - 42))

    W.LabelAt(highlights, "Border Modes", hlLeftX, -42, hlLeftW, "GameFontNormalSmall", T.colors.accent)
    local highlight = W.Slider(highlights, "Highlight border thickness", 1, 30, 1, hlLeftW)
    M.BindSlider(ctx, highlight,
        function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
        function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER")
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER")
            ApplyBars("MSUF2_HIGHLIGHT_BORDER")
        end)
    W.MoveWidget(highlight, highlights, hlLeftX, -70, hlLeftW, "LEFT")
    local borderModes = {
        { value = 0, text = "Off" },
        { value = 1, text = "On" },
    }
    local aggro = W.Dropdown(highlights, "Aggro border", borderModes, hlLeftW)
    M.BindDropdown(ctx, aggro,
        function() return tonumber(BarScopeGet("aggroOutlineMode", 1)) or 1 end,
        function(v) BarScopeSet("aggroOutlineMode", tonumber(v) or 1, "MSUF2_AGGRO_BORDER"); ApplyBars("MSUF2_AGGRO_BORDER") end)
    W.MoveWidget(aggro, highlights, hlLeftX, -136, hlLeftW, "LEFT")

    local dispelBorder = W.Dropdown(highlights, "Dispel border", borderModes, hlLeftW)
    M.BindDropdown(ctx, dispelBorder,
        function() return tonumber(BarScopeGet("dispelOutlineMode", 1)) or 1 end,
        function(v) BarScopeSet("dispelOutlineMode", tonumber(v) or 1, "MSUF2_DISPEL_BORDER"); ApplyBars("MSUF2_DISPEL_BORDER") end)
    W.MoveWidget(dispelBorder, highlights, hlLeftX, -190, hlLeftW, "LEFT")

    local purge = W.Dropdown(highlights, "Purge border", borderModes, hlLeftW)
    M.BindDropdown(ctx, purge,
        function() return tonumber(BarScopeGet("purgeOutlineMode", 0)) or 0 end,
        function(v) BarScopeSet("purgeOutlineMode", tonumber(v) or 0, "MSUF2_PURGE_BORDER"); ApplyBars("MSUF2_PURGE_BORDER") end)
    W.MoveWidget(purge, highlights, hlLeftX, -244, hlLeftW, "LEFT")

    local bossTarget = W.Dropdown(highlights, "Boss target border", borderModes, hlLeftW)
    M.BindDropdown(ctx, bossTarget,
        function()
            local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
            return tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback
        end,
        function(v)
            local value = tonumber(v) or 1
            SetG("bossTargetOutlineMode", value, "MSUF2_BOSS_TARGET_BORDER", { preview = true })
            SetGBool("bossTargetHighlightEnabled", value == 1, "MSUF2_BOSS_TARGET_BORDER", { preview = true })
            ApplyBars("MSUF2_BOSS_TARGET_BORDER")
        end)
    W.MoveWidget(bossTarget, highlights, hlLeftX, -298, hlLeftW, "LEFT")

    local bossSharedHint = W.Text(highlights, "Boss target border is a shared boss-frame setting.", hlLeftX, -360, hlLeftW, T.colors.dim)
    if bossSharedHint.SetWordWrap then bossSharedHint:SetWordWrap(true) end

    W.LabelAt(highlights, "Preview", hlRightX, -42, hlRightW, "GameFontNormalSmall", T.colors.accent)
    local aggroTest = W.ToggleAt(highlights, "Test aggro border", hlRightX, -72, hlRightW)
    M.BindToggle(ctx, aggroTest,
        function() return _G.MSUF_AggroBorderTestMode and true or false end,
        function(v)
            local scope = CurrentBarsScope()
            if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
            if type(_G.MSUF_SetAggroBorderTestMode) == "function" then _G.MSUF_SetAggroBorderTestMode(v and true or false, scope) end
        end)
    aggroTest:HookScript("OnHide", function(self)
        if _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
            _G.MSUF_SetAggroBorderTestMode(false)
            self:SetChecked(false)
        end
    end)

    local dispelTest = W.ToggleAt(highlights, "Test dispel border", hlRightX, -104, hlRightW)
    M.BindToggle(ctx, dispelTest,
        function() return _G.MSUF_DispelBorderTestMode and true or false end,
        function(v)
            local scope = CurrentBarsScope()
            if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
            if type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(v and true or false, scope) end
        end)
    dispelTest:HookScript("OnHide", function(self)
        if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
            _G.MSUF_SetDispelBorderTestMode(false)
            self:SetChecked(false)
        end
    end)
    _G.MSUF_DispelBorderTestType = _G.MSUF_DispelBorderTestType or "Magic"
    local dispelType = W.Dropdown(highlights, "Dispel test type", {
        { value = "Magic", text = "Magic" },
        { value = "Curse", text = "Curse" },
        { value = "Disease", text = "Disease" },
        { value = "Poison", text = "Poison" },
        { value = "Bleed", text = "Bleed" },
    }, hlRightW)
    M.BindDropdown(ctx, dispelType,
        function() return _G.MSUF_DispelBorderTestType or "Magic" end,
        function(v)
            _G.MSUF_DispelBorderTestType = v or "Magic"
            RefreshBorderTestModes()
        end)
    W.MoveWidget(dispelType, highlights, hlRightX, -150, hlRightW, "LEFT")

    local purgeTest = W.ToggleAt(highlights, "Test purge border", hlRightX, -214, hlRightW)
    M.BindToggle(ctx, purgeTest,
        function() return _G.MSUF_PurgeBorderTestMode and true or false end,
        function(v)
            if type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(v and true or false) end
        end)
    purgeTest:HookScript("OnHide", function(self)
        if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
            _G.MSUF_SetPurgeBorderTestMode(false)
            self:SetChecked(false)
        end
    end)

    local bossTargetTest = W.ToggleAt(highlights, "Test boss target border", hlRightX, -246, hlRightW)
    M.BindToggle(ctx, bossTargetTest,
        function() return _G.MSUF_BossTargetBorderTestMode and true or false end,
        function(v)
            if type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then _G.MSUF_SetBossTargetBorderTestMode(v and true or false) end
        end)
    bossTargetTest:HookScript("OnHide", function(self)
        if _G.MSUF_BossTargetBorderTestMode and type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then
            _G.MSUF_SetBossTargetBorderTestMode(false)
            self:SetChecked(false)
        end
    end)

    W.DividerAt(highlights, -288, hlRightX, 42)
    W.LabelAt(highlights, "Dispel Glow", hlRightX, -314, hlRightW, "GameFontNormalSmall", T.colors.accent)
    local enabled = W.ToggleAt(highlights, "Dispel glow effect", hlRightX, -344, hlRightW)
    M.BindToggle(ctx, enabled,
        function() return BarScopeGet("hlDispelGlowEnabled", true) ~= false end,
        function(v) BarScopeSet("hlDispelGlowEnabled", v and true or false, "MSUF2_DISPEL_GLOW"); ApplyBars("MSUF2_DISPEL_GLOW") end)
    local style = W.Segment(highlights, "Glow style", {
        { value = "PIXEL", text = "Pixel" },
        { value = "AUTOCAST", text = "AutoCast" },
        { value = "PROC", text = "Proc" },
    }, hlRightW)
    M.BindSegment(ctx, style,
        function() return NormalizeGlowStyle(BarScopeGet("hlDispelGlowStyle", "PIXEL")) end,
        function(v) BarScopeSet("hlDispelGlowStyle", NormalizeGlowStyle(v), "MSUF2_DISPEL_STYLE"); ApplyBars("MSUF2_DISPEL_STYLE") end)
    W.MoveWidget(style, highlights, hlRightX, -392, hlRightW, "LEFT")

    local lines = W.Slider(highlights, "Glow lines / particles", 2, 16, 1, hlRightW)
    M.BindSlider(ctx, lines,
        function() return tonumber(BarScopeGet("hlDispelGlowLines", 8)) or 8 end,
        function(v) BarScopeSet("hlDispelGlowLines", floor((tonumber(v) or 8) + 0.5), "MSUF2_DISPEL_GLOW_LINES"); ApplyBars("MSUF2_DISPEL_GLOW_LINES") end)
    W.MoveWidget(lines, highlights, hlRightX, -446, hlRightW, "LEFT")

    local speed = W.Slider(highlights, "Glow speed", 0.05, 1, 0.05, hlRightW)
    M.BindSlider(ctx, speed,
        function() return tonumber(BarScopeGet("hlDispelGlowFrequency", 0.25)) or 0.25 end,
        function(v) BarScopeSet("hlDispelGlowFrequency", tonumber(v) or 0.25, "MSUF2_DISPEL_GLOW_SPEED"); ApplyBars("MSUF2_DISPEL_GLOW_SPEED") end)
    W.MoveWidget(speed, highlights, hlRightX, -500, hlRightW, "LEFT")

    local thickness = W.Slider(highlights, "Glow thickness (Pixel)", 1, 5, 1, hlRightW)
    M.BindSlider(ctx, thickness,
        function() return tonumber(BarScopeGet("hlDispelGlowThickness", 2)) or 2 end,
        function(v) BarScopeSet("hlDispelGlowThickness", floor((tonumber(v) or 2) + 0.5), "MSUF2_DISPEL_THICKNESS"); ApplyBars("MSUF2_DISPEL_THICKNESS") end)
    W.MoveWidget(thickness, highlights, hlRightX, -554, hlRightW, "LEFT")

    M.AddRefresher(ctx, function()
        local scopedActive = ScopedBarsControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local glowOn = BarScopeGet("hlDispelGlowEnabled", true) ~= false
        local pixelGlow = NormalizeGlowStyle(BarScopeGet("hlDispelGlowStyle", "PIXEL")) == "PIXEL"
        SetControlEnabled(highlight, scopedActive)
        SetControlEnabled(aggro, scopedActive)
        SetControlEnabled(dispelBorder, scopedActive)
        SetControlEnabled(purge, scopedActive)
        SetControlEnabled(bossTarget, sharedActive)
        SetControlEnabled(aggroTest, scopedActive)
        SetControlEnabled(dispelTest, scopedActive)
        SetControlEnabled(dispelType, scopedActive)
        SetControlEnabled(purgeTest, scopedActive)
        SetControlEnabled(bossTargetTest, sharedActive)
        SetControlEnabled(enabled, scopedActive)
        SetControlEnabled(style, scopedActive and glowOn)
        SetControlEnabled(lines, scopedActive and glowOn)
        SetControlEnabled(speed, scopedActive and glowOn)
        SetControlEnabled(thickness, scopedActive and glowOn and pixelGlow)
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1)
    end)

    local priority = b:CollapsibleSection("bars_priority", "Highlight Priority", 280, false)
    local prio = W.ToggleAt(priority, "Custom highlight priority", 14, -8, 240)
    M.BindToggle(ctx, prio,
        function() return BarScopeGet("hlPrioEnabled", false) == true end,
        function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY")
            if CurrentBarsScope() == "shared" then G().highlightPrioEnabled = on and 1 or 0 end
            ApplyBars("MSUF2_HIGHLIGHT_PRIORITY")
        end)

    local rowH, rowGap, rowMax = 22, 4, 8
    local prioContainer = CreateFrame("Frame", nil, priority)
    prioContainer:SetPoint("TOPLEFT", prio, "BOTTOMLEFT", -2, -4)
    prioContainer:SetSize(200, rowMax * (rowH + rowGap))

    local prioRows, prioCount = {}, 0
    local function PrioritySlotY(slot)
        return -((slot - 1) * (rowH + rowGap))
    end
    local function SnapPriorityRows()
        for i = 1, prioCount do
            local row = prioRows[i]
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", prioContainer, "TOPLEFT", 0, PrioritySlotY(row.slotIndex))
            row.frame:Show()
        end
        for i = prioCount + 1, rowMax do
            if prioRows[i] then prioRows[i].frame:Hide() end
        end
        prioContainer:SetHeight(prioCount * (rowH + rowGap))
    end
    local function SavePriorityRows()
        local sorted = {}
        for i = 1, prioCount do sorted[i] = prioRows[i] end
        table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
        local order = {}
        for i = 1, prioCount do order[i] = sorted[i].key end
        SetPriorityOrder(order)
        ApplyBars("MSUF2_HIGHLIGHT_PRIORITY_ORDER")
    end
    local function SetPriorityRowsEnabled(enabled)
        enabled = enabled and true or false
        for i = 1, prioCount do
            local frame = prioRows[i].frame
            frame:SetAlpha(enabled and 1 or 0.4)
            frame:EnableMouse(enabled)
        end
    end

    for i = 1, rowMax do
        local rowFrame = CreateFrame("Frame", nil, prioContainer, T.Template and T.Template() or nil)
        rowFrame:SetSize(190, rowH)
        rowFrame:SetMovable(true)
        rowFrame:EnableMouse(true)
        rowFrame:RegisterForDrag("LeftButton")
        if rowFrame.SetBackdrop then
            rowFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            rowFrame:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
            rowFrame:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.60)
        end
        local stripe = rowFrame:CreateTexture(nil, "ARTWORK")
        stripe:SetSize(4, rowH - 2)
        stripe:SetPoint("LEFT", rowFrame, "LEFT", 2, 0)
        rowFrame._stripe = stripe
        local label = T.Font(rowFrame, "GameFontHighlightSmall", "", T.colors.text)
        label:SetPoint("LEFT", stripe, "RIGHT", 6, 0)
        rowFrame._label = label
        local num = T.Font(rowFrame, "GameFontNormalSmall", "", T.colors.dim)
        num:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
        rowFrame._numText = num
        rowFrame:SetScript("OnDragStart", function(self)
            if not (ScopedBarsControlsActive() and BarScopeGet("hlPrioEnabled", false) == true) then return end
            if GameTooltip then GameTooltip:Hide() end
            self._msuf2OldStrata = self:GetFrameStrata()
            self:StartMoving()
            self:SetFrameStrata("TOOLTIP")
        end)
        rowFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetFrameStrata(self._msuf2OldStrata or prioContainer:GetFrameStrata() or "MEDIUM")
            local _, selfY = self:GetCenter()
            local contTop = prioContainer:GetTop()
            if not (selfY and contTop) then
                SnapPriorityRows()
                return
            end
            local bestSlot, bestDist = 1, math.huge
            for slot = 1, prioCount do
                local slotY = contTop + PrioritySlotY(slot) - (rowH / 2)
                local dist = math.abs(selfY - slotY)
                if dist < bestDist then
                    bestDist = dist
                    bestSlot = slot
                end
            end
            local thisRow
            for idx = 1, prioCount do
                if prioRows[idx].frame == self then
                    thisRow = prioRows[idx]
                    break
                end
            end
            if thisRow and thisRow.slotIndex ~= bestSlot then
                for idx = 1, prioCount do
                    if prioRows[idx].slotIndex == bestSlot then
                        prioRows[idx].slotIndex = thisRow.slotIndex
                        break
                    end
                end
                thisRow.slotIndex = bestSlot
            end
            for idx = 1, prioCount do
                prioRows[idx].frame._numText:SetText(tostring(prioRows[idx].slotIndex))
            end
            SnapPriorityRows()
            SavePriorityRows()
        end)
        rowFrame:Hide()
        prioRows[i] = { frame = rowFrame, key = "", slotIndex = i }
    end

    local function RefreshPriorityRows()
        local order = PriorityOrder()
        prioCount = math.min(#order, rowMax)
        for i = 1, prioCount do
            local key = order[i]
            local r, g, bcol = PriorityColor(key)
            local row = prioRows[i]
            row.key = key
            row.slotIndex = i
            row.frame._stripe:SetColorTexture(r, g, bcol, 1)
            row.frame._label:SetText(PRIORITY_LABELS[key] or key)
            row.frame._numText:SetText(tostring(i))
        end
        SnapPriorityRows()
        SetPriorityRowsEnabled(ScopedBarsControlsActive() and BarScopeGet("hlPrioEnabled", false) == true)
    end
    RefreshPriorityRows()
    M.AddRefresher(ctx, function()
        SetControlEnabled(prio, ScopedBarsControlsActive())
        RefreshPriorityRows()
    end)

    local text = b:CollapsibleSection("bars_text", "HP / Power Text", 340, false)
    local hpModeOptions = {
        { value = "PERCENT", text = "Percent" },
        { value = "CURRENT", text = "Current" },
        { value = "MAX", text = "Max" },
        { value = "DEFICIT", text = "Deficit" },
        { value = "CURMAX", text = "Current / Max" },
        { value = "CURPERCENT", text = "Current / Percent" },
        { value = "CURMAXPERCENT", text = "Current / Max / Percent" },
        { value = "MAXPERCENT", text = "Max / Percent" },
        { value = "PERCENTCUR", text = "Percent / Current" },
        { value = "PERCENTMAX", text = "Percent / Max" },
        { value = "PERCENTCURMAX", text = "Percent / Current / Max" },
        { value = "NONE", text = "None" },
    }
    local powerModeOptions = {
        { value = "CURRENT", text = "Current" },
        { value = "MAX", text = "Max" },
        { value = "CURMAX", text = "Cur/Max" },
        { value = "PERCENT", text = "Percent" },
        { value = "CURPERCENT", text = "Cur + Percent" },
        { value = "CURMAXPERCENT", text = "Cur/Max + Percent" },
    }
    local separatorOptions = {
        { value = "", text = " " },
        { value = "-", text = "-" },
        { value = "/", text = "/" },
        { value = "\\", text = "\\" },
        { value = "|", text = "|" },
        { value = "<", text = "<" },
        { value = ">", text = ">" },
        { value = "~", text = "~" },
        { value = "\194\183", text = "\194\183" },
        { value = "\226\128\162", text = "\226\128\162" },
        { value = ":", text = ":" },
        { value = "\194\187", text = "\194\187" },
        { value = "\194\171", text = "\194\171" },
    }
    local hpMode = W.Dropdown(text, "HP text mode", hpModeOptions, 260)
    M.BindDropdown(ctx, hpMode,
        function() return NormalizeHpMode(BarScopeGet("hpTextMode", "FULL_PLUS_PERCENT")) end,
        function(v) BarScopeSet("hpTextMode", v or "CURPERCENT", "MSUF2_HP_TEXT_MODE"); ApplyBars("MSUF2_HP_TEXT_MODE") end)
    local powerMode = W.Dropdown(text, "Power text mode", powerModeOptions, 260)
    M.BindDropdown(ctx, powerMode,
        function() return NormalizePowerMode(BarScopeGet("powerTextMode", "CURPERCENT")) end,
        function(v) BarScopeSet("powerTextMode", v or "CURPERCENT", "MSUF2_POWER_TEXT_MODE"); ApplyBars("MSUF2_POWER_TEXT_MODE") end)
    local hpReverse = W.Toggle(text, "Reverse HP text order")
    M.BindToggle(ctx, hpReverse,
        function() return BarScopeGet("hpTextReverse", false) == true end,
        function(v) BarScopeSet("hpTextReverse", v and true or false, "MSUF2_HP_TEXT_REVERSE"); ApplyBars("MSUF2_HP_TEXT_REVERSE") end)
    local hpSep = W.Dropdown(text, "HP separator", separatorOptions, 120)
    M.BindDropdown(ctx, hpSep,
        function() return BarScopeGet("hpTextSeparator", "") or "" end,
        function(v) BarScopeSet("hpTextSeparator", v or "", "MSUF2_HP_TEXT_SEPARATOR"); ApplyBars("MSUF2_HP_TEXT_SEPARATOR") end)
    local powerSep = W.Dropdown(text, "Power separator", separatorOptions, 120)
    M.BindDropdown(ctx, powerSep,
        function() return BarScopeGet("powerTextSeparator", BarScopeGet("hpTextSeparator", "")) or "" end,
        function(v) BarScopeSet("powerTextSeparator", v or "", "MSUF2_POWER_TEXT_SEPARATOR"); ApplyBars("MSUF2_POWER_TEXT_SEPARATOR") end)
    M.AddRefresher(ctx, function()
        local active = TextBarsControlsActive()
        SetControlEnabled(hpMode, active)
        SetControlEnabled(powerMode, active)
        SetControlEnabled(hpReverse, active)
        SetControlEnabled(hpSep, active)
        SetControlEnabled(powerSep, active)
    end)

    local spacers = b:CollapsibleSection("bars_text_spacers", "Text Spacers", 300, false)
    local hpSpacer = W.Toggle(spacers, "HP Spacer on/off")
    M.BindToggle(ctx, hpSpacer,
        function() return BarScopeGet("hpTextSpacerEnabled", false) == true end,
        function(v) BarScopeSet("hpTextSpacerEnabled", v and true or false, "MSUF2_HP_TEXT_SPACER"); ApplyBars("MSUF2_HP_TEXT_SPACER") end)
    local hpSpacerX = W.Slider(spacers, "HP Spacer (X)", 0, 2000, 1, 300)
    M.BindSlider(ctx, hpSpacerX,
        function() return tonumber(BarScopeGet("hpTextSpacerX", 0)) or 0 end,
        function(v) BarScopeSet("hpTextSpacerX", floor((tonumber(v) or 0) + 0.5), "MSUF2_HP_TEXT_SPACER_X"); ApplyBars("MSUF2_HP_TEXT_SPACER_X") end)
    local powerSpacer = W.Toggle(spacers, "Power Spacer on/off")
    M.BindToggle(ctx, powerSpacer,
        function() return BarScopeGet("powerTextSpacerEnabled", false) == true end,
        function(v) BarScopeSet("powerTextSpacerEnabled", v and true or false, "MSUF2_POWER_TEXT_SPACER"); ApplyBars("MSUF2_POWER_TEXT_SPACER") end)
    local powerSpacerX = W.Slider(spacers, "Power Spacer (X)", 0, 1000, 1, 300)
    M.BindSlider(ctx, powerSpacerX,
        function() return tonumber(BarScopeGet("powerTextSpacerX", 0)) or 0 end,
        function(v) BarScopeSet("powerTextSpacerX", floor((tonumber(v) or 0) + 0.5), "MSUF2_POWER_TEXT_SPACER_X"); ApplyBars("MSUF2_POWER_TEXT_SPACER_X") end)
    M.AddRefresher(ctx, function()
        local active = TextBarsControlsActive()
        SetControlEnabled(hpSpacer, active)
        SetControlEnabled(hpSpacerX, active and BarScopeGet("hpTextSpacerEnabled", false) == true)
        SetControlEnabled(powerSpacer, active)
        SetControlEnabled(powerSpacerX, active and BarScopeGet("powerTextSpacerEnabled", false) == true)
    end)

    local power = b:CollapsibleSection("bars_power", "Bar Animation + Text Accuracy", 152, false)
    local smoothPower = W.Toggle(power, "Smooth power bar")
    M.BindToggle(ctx, smoothPower,
        function() return SmoothPowerGet() end,
        function(v) SmoothPowerSet(v, "MSUF2_BARS_SMOOTH_POWER"); ApplyBars("MSUF2_BARS_SMOOTH_POWER") end)
    local realtimePower = W.Toggle(power, "Realtime power text")
    M.BindToggle(ctx, realtimePower,
        function() return ReadB("realtimePowerText", true) ~= false end,
        function(v) SetB("realtimePowerText", v and true or false, "MSUF2_BARS_REALTIME_POWER", { preview = true }); ApplyBars("MSUF2_BARS_REALTIME_POWER") end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(smoothPower, CurrentPowerBarScopeUnit() ~= nil)
        SetControlEnabled(realtimePower, SharedBarsControlsActive())
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 4 })
