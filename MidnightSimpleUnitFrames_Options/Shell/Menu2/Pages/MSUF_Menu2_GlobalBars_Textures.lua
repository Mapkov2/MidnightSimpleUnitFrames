-- GlobalBars: Textures responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GlobalBarsParts
local ApplyBars = Parts.ApplyBars
local ApplyGradientRuntime = Parts.ApplyGradientRuntime
local AttachBarsColorShortcut = Parts.AttachBarsColorShortcut
local BarBackgroundTextureForScope = Parts.BarBackgroundTextureForScope
local BarScopeGet = Parts.BarScopeGet
local BarScopeSet = Parts.BarScopeSet
local BarTextureForScope = Parts.BarTextureForScope
local Bars = Parts.Bars
local CaptureBarsScopeFields = Parts.CaptureBarsScopeFields
local CurrentBarsScope = Parts.CurrentBarsScope
local CurrentGradientDirectionsForScope = Parts.CurrentGradientDirectionsForScope
local DB = Parts.DB
local FILE = Parts.FILE
local FreezePowerGradientScope = Parts.FreezePowerGradientScope
local G = Parts.G
local GP = Parts.GP
local GradientControlsActive = Parts.GradientControlsActive
local GradientScopeGet = Parts.GradientScopeGet
local GradientScopeSet = Parts.GradientScopeSet
local GroupScope = Parts.GroupScope
local IsAbsorbTextureTestEnabled = Parts.IsAbsorbTextureTestEnabled
local IsGFScope = Parts.IsGFScope
local Meta = Parts.Meta
local NormalizeScopeKey = Parts.NormalizeScopeKey
local PixelLayoutRegion = Parts.PixelLayoutRegion
local ReadG = Parts.ReadG
local ReadGBool = Parts.ReadGBool
local RefreshBorderTestModes = Parts.RefreshBorderTestModes
local RegisterControl = Parts.RegisterControl
local RequestApply = Parts.RequestApply
local RestoreBarsScopeFields = Parts.RestoreBarsScopeFields
local Rows = Parts.Rows
local ScopeDBKeys = Parts.ScopeDBKeys
local ScopeHasOverride = Parts.ScopeHasOverride
local ScopeSetOverride = Parts.ScopeSetOverride
local ScopedControls = Parts.ScopedControls
local SetAbsorbTextureTest = Parts.SetAbsorbTextureTest
local SetBarBackgroundTextureForScope = Parts.SetBarBackgroundTextureForScope
local SetBarTextureForScope = Parts.SetBarTextureForScope
local SetControlEnabled = Parts.SetControlEnabled
local SetControlsEnabled = Parts.SetControlsEnabled
local SharedScope = Parts.SharedScope
local T = Parts.T
local TEMP_MAX_HEALTH_COLOR_STATE_FIELDS = Parts.TEMP_MAX_HEALTH_COLOR_STATE_FIELDS
local TextureControlsActive = Parts.TextureControlsActive
local TextureValues = Parts.TextureValues
local ToggleGradientDirectionForScope = Parts.ToggleGradientDirectionForScope
local VT = Parts.VT
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

local function BuildScopeSection(ctx, b)
    local function HasScopedSlantedDirection(scope)
        -- Selector values are already canonical; keep its badge refresh allocation-free.
        local conf = DB()[scope]
        local value = conf and conf.slantedBarDirection
        return value == "RIGHT_DOWN" or value == "RIGHT_UP" or value == "LEFT_DOWN"
            or value == "LEFT_UP" or value == "BOTH_DOWN" or value == "BOTH_UP"
    end
    local scopeValues = GP.SCOPE_VALUES
    local function RefreshBarsPage(reason)
        M.RequestRefresh(ctx, reason)
    end
    local scopeUI = GP.BuildScopeOverrideSection(ctx, b, {
        values = scopeValues,
        meta = Meta,
        getValue = function() return CurrentBarsScope() end,
        selectorWriteTargets = "general.hpPowerTextSelectedKey",
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            RefreshBorderTestModes()
            RefreshBarsPage("bars-scope-change")
        end,
        hasOverride = function(value)
            return value ~= "shared" and (ScopeHasOverride(value, "hlOverride") or HasScopedSlantedDirection(value))
        end,
        getOverride = function()
            local key = CurrentBarsScope()
            return ScopeHasOverride(key, "hlOverride")
        end,
        setOverride = function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "hlOverride", v)
                -- Group textures follow this switch again, also after a Copy To flag.
                GP.SetGroupTextureOwner(key, nil)
                -- Texture refresh alone leaves the unit outline's painted state stale.
                M.RequestGeneralDomains("MSUF2_BARS_OVERRIDE", {
                    preview = true, applyAll = false, bars = true,
                    barOutline = not IsGFScope(key), barsScope = key,
                })
            end
            RefreshBarsPage("bars-scope-override")
        end,
        reset = function()
            local resetDirections = false
            for i = 1, #scopeValues do
                local key = scopeValues[i].value
                if key ~= "shared" then
                    ScopeSetOverride(key, "hlOverride", false)
                    GP.SetGroupTextureOwner(key, nil)
                    local keys, db = ScopeDBKeys(key), DB()
                    for j = 1, #(keys or {}) do
                        local entry = db[keys[j]]
                        if entry and entry.slantedBarDirection ~= nil then
                            entry.slantedBarDirection = nil
                            resetDirections = true
                        end
                    end
                end
            end
            M.RequestGeneralDomains("MSUF2_BARS_RESET_OVERRIDES", {
                preview = true, applyAll = false, bars = true, barOutline = true, roundedBars = resetDirections, barsScope = "shared",
            })
            RefreshBarsPage("bars-reset-overrides")
        end,
        hint = "Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.",
        updateHint = function(hint, current, active, shared)
            if shared then
                hint:SetText("Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.")
            elseif HasScopedSlantedDirection(current) then
                hint:SetText("This scope uses its own slanted cut direction. Other bar settings follow the custom-settings switch.")
            elseif IsGFScope(current) and ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This group scope can use custom textures and gradients. Raid also applies to Mythic Raid.")
            elseif ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This scope can use custom gradients and bar settings. Textures still follow Shared.")
            else
                hint:SetText("This scope follows Shared bar settings. Turn on custom settings here when this scope needs different gradients or bar settings.")
            end
        end,
    })
    if scopeUI then
        local scope = Rows.Schema.ScopeOwner(scopeUI.segment, "bars", "menuState", "general.hpPowerTextSelectedKey")._msuf2ControlSchema
        Rows.Schema.Owned(scopeUI.override, "bars", "bars")
        Rows.Schema.Owned(scopeUI.reset, "bars", "bars")
        Rows.Schema.Custom(scopeUI.section, { id = scope.id .. ".owner", kind = "scope", scope = "bars",
            applyDomain = "menuState", owner = scopeUI.section, selector = scopeUI.segment })
    end
    if M.AddTooltip and scopeUI then
        M.AddTooltip(scopeUI.override, "Use custom settings for this scope",
            "Gives this unit or group its own gradient, absorb, outline and highlight " ..
                "settings instead of following Shared. Turning it off keeps your custom values.",
            { hook = true, labelHit = true })
        M.AddTooltip(scopeUI.reset, "Reset",
            "Resets all scoped slanted directions to Shared and turns off custom bar settings for every unit and group. Other custom values stay saved.",
                { hook = true })
    end
end

function GP.BuildGradientDirectionPads(textures, padX, hpY, powerY, SyncGradientControls)
    local padW, padH = 104, 78
    local padButtonW, padButtonH = 22, 18
    local directionButtons = { health = {}, power = {} }
    local pads = {}
    local function BuildDirectionPad(kind, y)
        local pad = T.Panel(textures, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, T.colors.borderSoft)
        pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, y)
        pad:SetSize(padW, padH)
        local center = PixelLayoutRegion(pad:CreateTexture(nil, "ARTWORK"))
        center:SetPoint("CENTER", pad, "CENTER", 0, 0)
        center:SetSize(10, 10)
        local centerColor = T.colors.coreRim or { 0.043, 0.096, 0.150 }
        center:SetColorTexture(centerColor[1], centerColor[2], centerColor[3], 0.95)
        local function PadButton(text, value, x, buttonY)
            local btn = T.Button(pad, text, padButtonW, padButtonH, { history = true })
            btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, buttonY)
            T.CenterButtonLabel(btn)
            btn:SetScript("OnClick", function()
                ToggleGradientDirectionForScope(kind, value or "RIGHT")
                ApplyGradientRuntime(kind == "power" and "MSUF2_POWER_GRADIENT_DIRECTION" or "MSUF2_HP_GRADIENT_DIRECTION", kind)
                SyncGradientControls()
            end)
            -- The arrow glyphs are no searchable names. The pad is found once, by its
            -- name on the first arrow; the other arrows keep their glyph.
            local meta = Meta("gradient." .. kind .. ".direction." .. tostring(value), "action")
            local label = value == "UP" and "Gradient direction" or text
            RegisterControl(btn, meta, label, "button")
            Rows.Schema.Custom(btn, { id = meta.controlId, meta = meta,
                kind = "button", labelKey = label, scope = "bars", applyDomain = "bars", owner = btn,
                setting = Rows.Schema.ScopedFields(M.WordList [[
                    gradientDirUp gradientDirDown gradientDirLeft gradientDirRight gradientDirection gradientStrength
                    powerGradientDirUp powerGradientDirDown powerGradientDirLeft powerGradientDirRight powerGradientDirection powerGradientStrength
                ]], "general", "hlOverride"), action = Rows.Schema.ButtonAction(btn) })
            if M.AddTooltip then
                M.AddTooltip(btn, nil,
                    "Adds or removes a fade direction; the shade darkens toward this arrow. Directions can be combined, and one always stays on.",
                    { hook = true })
            end
            directionButtons[kind][value] = btn
        end
        local centerX = (padW - padButtonW) * 0.5
        local centerY = (padH - padButtonH) * 0.5
        local sideOffset = 23
        PadButton("^", "UP", centerX, -(centerY - sideOffset))
        PadButton("<", "LEFT", centerX - sideOffset, -centerY)
        PadButton(">", "RIGHT", centerX + sideOffset, -centerY)
        PadButton("v", "DOWN", centerX, -(centerY + sideOffset))
        Rows.Schema.Custom(pad, { id = Meta("gradient." .. kind .. ".direction", "ephemeral").controlId,
            kind = "directionpad", scope = "bars", applyDomain = "bars", owner = pad, controls = directionButtons[kind] })
        pads[kind] = pad
    end
    BuildDirectionPad("health", hpY - 2)
    BuildDirectionPad("power", powerY - 2)
    return directionButtons, pads
end

function GP.BuildBarTextureControls(ctx, textures, leftW, leftX, topY)
    local options = Rows.Options(function(key, fallback) return Bars()[key] or fallback end,
        function(key, value) Bars()[key] = value end, function(row) ApplyBars(row.reason) end,
        function(key) return Bars()[key] end)
    -- Shared power-bar art for every unit power bar (detached or not). Stored in
    -- the shared bars table like powerBarHeight, and resolved in the UF compiler
    -- as: this value -> Class Resources detached art -> per-unit powerBarTexture.
    local refs = Rows.Schema.Build(ctx, textures, {
        { "dropdown", "foreground", "", { "Bar textures (SharedMedia)", function() return TextureValues(nil) end, leftW },
            { leftX, topY, leftW, "LEFT" }, path = "textures.foreground", get = BarTextureForScope,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(v) if SetBarTextureForScope(v) then ApplyBars("MSUF2_BAR_TEXTURE") end end },
        { "dropdown", "background", "", { "Background texture", function() return TextureValues("Use foreground texture") end, leftW },
            { leftX, topY - 54, leftW, "LEFT" }, path = "textures.background", get = BarBackgroundTextureForScope,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(v) if SetBarBackgroundTextureForScope(v) then ApplyBars("MSUF2_BAR_BG_TEXTURE") end end },
        { "dropdown", "powerBarTexture", "", { "Power bar texture", function() return TextureValues("Use bar texture") end, leftW },
            { leftX, topY - 108, leftW, "LEFT" }, path = "textures.power_foreground", skipEqual = true, reason = "MSUF2_POWER_BAR_TEXTURE",
            tip = { "Power Bar Texture",
                "Art for every unit's power bar. Leave on Use bar texture to keep the shared bar art. Each unit page can override this, and the Class " ..
                    "Resources detached power texture still wins for a detached Player bar.",
                { hook = true, owner = "ANCHOR_RIGHT" } } },
        { "dropdown", "powerBarBgTexture", "", { "Power background texture", function() return TextureValues("Use bar background texture") end, leftW },
            { leftX, topY - 162, leftW, "LEFT" }, path = "textures.power_background", skipEqual = true, reason = "MSUF2_POWER_BAR_BG_TEXTURE",
            tip = { "Power Background Texture", "Background art behind every unit's power bar. Overridable per unit on the unit page.", { hook = true,
                owner = "ANCHOR_RIGHT" } } },
    }, options)
    return refs.foreground, refs.background
end

function GP.BuildBarGlossControls(ctx, section, leftX, rightX, width, compact)
    local topY = compact and -546 or -304
    local Sync = M.RefreshProxy()
    local options = Rows.Options(function(key, fallback, row)
        local value = BarScopeGet(key, row.percent and 0.5 or fallback)
        return row.percent and floor(max(0, min(1, tonumber(value) or 0.5)) * 100 + 0.5) or value
    end, function(key, value, row)
        if row.percent then value = max(0, min(100, value)) / 100 end
        BarScopeSet(key, value, row.reason, true)
    end, function(row)
        RequestApply("RequestBarGradients", row.reason, CurrentBarsScope())
        Sync()
    end)
    local refs = Rows.Build(ctx, section, {
        { "toggle", "healthGlossEnabled", false, { "Health gloss", leftX, topY, width },
            path = "gloss.health.enabled", reason = "MSUF2_HEALTH_GLOSS",
            tip = "Adds a white reflection over the filled bar, including dark bars." },
        { "slider", "healthGlossStrength", 50, { "Health gloss strength", 0, 100, 5, width },
            { leftX, topY - 38, width, "LEFT" }, path = "gloss.health.strength", percent = true, reason = "MSUF2_HEALTH_GLOSS_STRENGTH",
            tip = "Sets the reflection strength from 0 to 100." },
        { "toggle", "powerGlossEnabled", false, { "Power gloss", rightX, compact and topY - 96 or topY, width },
            path = "gloss.power.enabled", reason = "MSUF2_POWER_GLOSS",
            tip = "Adds a white reflection over the filled bar, including dark bars." },
        { "slider", "powerGlossStrength", 50, { "Power gloss strength", 0, 100, 5, width },
            { rightX, (compact and topY - 96 or topY) - 38, width, "LEFT" }, path = "gloss.power.strength",
            percent = true, reason = "MSUF2_POWER_GLOSS_STRENGTH",
            tip = "Sets the reflection strength from 0 to 100." },
    }, options)
    local toggles = { refs.healthGlossEnabled, refs.powerGlossEnabled }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local scopeReason = W.TurnOnReason("Use custom settings for this scope", ScopedControls)
        W.SetControlsDisabledReason(toggles, scopeReason)
        local healthReason = W.TurnOnReason("Health gloss", function() return BarScopeGet("healthGlossEnabled", false) == true end)
        local powerReason = W.TurnOnReason("Power gloss", function() return BarScopeGet("powerGlossEnabled", false) == true end)
        W.SetControlDisabledReason(refs.healthGlossStrength, function(control) return scopeReason(control) or healthReason(control) end)
        W.SetControlDisabledReason(refs.powerGlossStrength, function(control) return scopeReason(control) or powerReason(control) end)
    end
    M.TrackRefresh(ctx, Sync(function()
        local active = GradientControlsActive()
        SetControlsEnabled(toggles, active)
        SetControlEnabled(refs.healthGlossStrength, active and BarScopeGet("healthGlossEnabled", false) == true)
        SetControlEnabled(refs.powerGlossStrength, active and BarScopeGet("powerGlossEnabled", false) == true)
    end))
end

local function BuildTextureSection(ctx, b)
    local compactTextures = (ctx.width or 720) < 560
    local textures = Rows.Schema.Section(b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 766 or 448, true), "bars")
    local leftX, topY = 14, -42
    local rightX = compactTextures and leftX or math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = compactTextures and math.max(220, (ctx.width or 720) - 42) or math.min(300, math.max(220, rightX - 48))
    -- Compact stacks the gradient block under the texture column, which now
    -- carries two extra power dropdowns.
    local gradientY = compactTextures and (topY - 234) or topY
    local barTexture, bgTexture = GP.BuildBarTextureControls(ctx, textures, leftW, leftX, topY)
    GP.BuildBarGlossControls(ctx, textures, leftX, rightX, leftW, compactTextures)
    Rows.Schema.Build(ctx, textures, {
        { "font", "gradientLabel", nil, { "GameFontHighlightSmall", "Gradient", T.colors.muted }, scope = "bars",
            anchor = { "TOPLEFT", textures, "TOPLEFT", rightX, gradientY } },
    })
    local SyncGradientControls = M.RefreshProxy()
    local gradientOptions = Rows.Options(function(key, fallback) return GradientScopeGet(key, fallback) end,
        function(key, value) GradientScopeSet(key, value) end,
        function(row)
            ApplyGradientRuntime(row.reason, row.gradientKind)
            SyncGradientControls()
        end)
    local hpY = gradientY - 28
    local powerY = gradientY - 138
    local padX = compactTextures and math.min(rightX + 210, (ctx.width or 720) - 104) or math.min(rightX + 238, (ctx.width or 720) - 104)
    local compactStrengthW = math.max(150, padX - rightX - 14)
    local gradients = Rows.Build(ctx, textures, {
        { "toggle", "enableGradient", false, { "Health gradient", rightX, hpY, compactTextures and 150 or 180 },
            path = "gradient.enableGradient", reason = "MSUF2_HP_GRADIENT", gradientKind = "health",
            tip = "Adds a shade over the filled part of health bars that darkens toward the arrows you pick. The strength slider sets how dark it gets." },
        { "toggle", "enablePowerGradient", false, { "Power gradient", rightX, powerY, compactTextures and 170 or 190 },
            path = "gradient.enablePowerGradient", reason = "MSUF2_POWER_GRADIENT", gradientKind = "power",
            tip = "Adds the same fading shade to power bars, with its own direction arrows and strength." },
    }, gradientOptions)
    local hpGradient, powerGradient = gradients.enableGradient, gradients.enablePowerGradient
    Rows.Schema.Colors(textures, { "gradient.health", "gradient.power" }, {
        title = "Bar Gradient Colors",
        note = "Health and Power gradient colors for the selected Bars scope.",
        historySource = "menu:bars-gradient-colors",
        offsetY = -8,
    })
    local strengthOptions = Rows.Options(GradientScopeGet, GradientScopeSet, ApplyGradientRuntime, nil, true)
    local strengths = Rows.Build(ctx, textures, {
        { "slider", "gradientStrength", 0.45, { "Health strength", 0, 1, 0.05, 220 },
            { rightX, hpY - 36, compactTextures and compactStrengthW or 220, "LEFT" }, path = "gradient.health.strength",
            reason = "MSUF2_HP_GRADIENT_STRENGTH", gradientKind = "health", beforeWrite = FreezePowerGradientScope,
            tip = "How dark the health bar shade gets at its strongest edge. 0 shows no shade, 1 uses the full shade color." },
        { "slider", "powerGradientStrength", 0.45, { "Power strength", 0, 1, 0.05, 220 },
            { rightX, powerY - 36, compactTextures and compactStrengthW or 220, "LEFT" }, path = "gradient.power.strength",
            reason = "MSUF2_POWER_GRADIENT_STRENGTH", gradientKind = "power", legacyKey = "gradientStrength",
            tip = "How dark the power bar shade gets at its strongest edge. 0 shows no shade, 1 uses the full shade color." },
    }, strengthOptions)
    local hpStrength, powerStrength = strengths.gradientStrength, strengths.powerGradientStrength
    local directionButtons, pads = GP.BuildGradientDirectionPads(textures, padX, hpY, powerY, SyncGradientControls)
    local textureControls = { barTexture, bgTexture }
    local gradientControls = { hpGradient, powerGradient }
    -- Hover reasons: a unit or group scope without its own settings locks this
    -- card, and each strength slider and arrow pad waits for its gradient.
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local scopeReason = W.TurnOnReason("Use custom settings for this scope", ScopedControls)
        W.SetControlsDisabledReason(textureControls, function(control)
            if TextureControlsActive() then return nil end
            if GroupScope() then return scopeReason(control) end
            return M.Tr("Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.")
        end)
        W.SetControlsDisabledReason(gradientControls, scopeReason)
        local hpReason = W.TurnOnReason("Health gradient", function() return GradientScopeGet("enableGradient", false) == true end)
        local powerReason = W.TurnOnReason("Power gradient", function() return GradientScopeGet("enablePowerGradient", false) == true end)
        local function HealthReason(control) return scopeReason(control) or hpReason(control) end
        local function PowerReason(control) return scopeReason(control) or powerReason(control) end
        W.SetControlDisabledReason(hpStrength, HealthReason)
        W.SetControlDisabledReason(powerStrength, PowerReason)
        W.SetControlsDisabledReason(directionButtons.health, HealthReason)
        W.SetControlsDisabledReason(directionButtons.power, PowerReason)
    end
    M.TrackRefresh(ctx, SyncGradientControls(function()
        local hpDirections = CurrentGradientDirectionsForScope("health")
        local powerDirections = CurrentGradientDirectionsForScope("power")
        local textureControlsActive = TextureControlsActive()
        local gradientControlsActive = GradientControlsActive()
        local hpActive = gradientControlsActive and GradientScopeGet("enableGradient", false) == true
        local powerActive = gradientControlsActive and GradientScopeGet("enablePowerGradient", false) == true
        SetControlsEnabled(textureControls, textureControlsActive)
        SetControlsEnabled(gradientControls, gradientControlsActive)
        SetControlEnabled(hpStrength, hpActive)
        SetControlEnabled(powerStrength, powerActive)
        pads.health:SetAlpha(hpActive and 1 or 0.45)
        pads.power:SetAlpha(powerActive and 1 or 0.45)
        for value, btn in pairs(directionButtons.health) do
            btn:SetActive(hpDirections[value] == true)
            SetControlEnabled(btn, hpActive)
        end
        for value, btn in pairs(directionButtons.power) do
            btn:SetActive(powerDirections[value] == true)
            SetControlEnabled(btn, powerActive)
        end
    end))
end

local function BuildTempMaxHealthSection(ctx, b)
    local sectionW = ctx.width or 720
    local compact = sectionW < 700
    local section = Rows.Schema.Section(b:CollapsibleSection("bars_temp_max_health", "Maximum Health Loss", compact and 414 or 274, true), "bars")
    sectionW = section._msuf2Width or sectionW
    local leftX = compact and 20 or 30
    local rightX = compact and 20 or max(390, min(540, floor(sectionW * 0.52)))
    local leftW = compact and max(240, sectionW - 40) or max(280, rightX - leftX - 54)
    local rightW = compact and leftW or max(280, sectionW - rightX - 32)
    local SyncControls = M.RefreshProxy()

    local RefreshTempMaxHealth = MSUF.Require("MSUF_RefreshTempMaxHealth", FILE)
    local RequestPreviewRefresh = MSUF.Require("MSUF_UFPreview_RequestRefresh", FILE)
    local function Refresh(reason)
        local scope = CurrentBarsScope()
        RefreshTempMaxHealth(scope, reason or "MSUF2_TEMP_MAX_HEALTH")
        RequestPreviewRefresh(reason or "MSUF2_TEMP_MAX_HEALTH")
        if type(M.RefreshGFNativePreviews) == "function" then
            M.RefreshGFNativePreviews(reason or "MSUF2_TEMP_MAX_HEALTH")
        end
        SyncControls()
    end

    local bindings = Rows.Options(function(key, fallback, row)
        if row.booleanFallback then return BarScopeGet(key, ReadGBool(key, fallback)) end
        return BarScopeGet(key, ReadG(key, fallback))
    end, function(key, value, row) BarScopeSet(key, value, row.reason, true) end,
        function(row) Refresh(row.reason) end)
    local controls = Rows.Schema.Build(ctx, section, {
        { "text", "tempHealthHint", nil, { "Shows the part of maximum health that is temporarily unavailable.",
            20, -36, sectionW - 40, T.colors.muted }, scope = "bars" },
        { "toggle", "tempMaxHealthEnabled", false, { "Show maximum-health loss", leftX, -78, leftW },
            path = "temp_max_health.enabled", booleanFallback = true, reason = "MSUF2_TEMP_MAX_HEALTH_ENABLED" },
        { "dropdown", "tempMaxHealthTexture", "Solid", { "Texture", function() return TextureValues("Use foreground texture") end, leftW },
            { leftX, -132, leftW, "LEFT" }, path = "temp_max_health.texture", writeDefault = "", reason = "MSUF2_TEMP_MAX_HEALTH_TEXTURE" },
    }, bindings)

    AttachBarsColorShortcut(section,
        "Maximum Health Loss Color",
        "Loss color for the selected Bars scope.",
        "Loss color",
        function()
            return tonumber(BarScopeGet("tempMaxHealthColorR", ReadG("tempMaxHealthColorR", 0.70))) or 0.70,
                tonumber(BarScopeGet("tempMaxHealthColorG", ReadG("tempMaxHealthColorG", 0.10))) or 0.10,
                tonumber(BarScopeGet("tempMaxHealthColorB", ReadG("tempMaxHealthColorB", 0.10))) or 0.10
        end,
        function(r, g, b)
            BarScopeSet("tempMaxHealthColorR", tonumber(r) or 0.70, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            BarScopeSet("tempMaxHealthColorG", tonumber(g) or 0.10, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            BarScopeSet("tempMaxHealthColorB", tonumber(b) or 0.10, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_COLOR")
        end,
        "menu:bars-temp-max-health-color",
        function() return CaptureBarsScopeFields(TEMP_MAX_HEALTH_COLOR_STATE_FIELDS) end,
        function(state)
            RestoreBarsScopeFields(state)
            Refresh("MSUF2_TEMP_MAX_HEALTH_COLOR_CANCEL")
        end,
        Meta("temp_max_health.color"))

    Rows.Schema.Build(ctx, section, {
        { "slider", "tempMaxHealthOpacity", 1, { "Overlay opacity", 0.05, 1, 0.05, rightW },
            { rightX, compact and -204 or -78, rightW, "LEFT" }, path = "temp_max_health.opacity", reason = "MSUF2_TEMP_MAX_HEALTH_OPACITY" },
        { "slider", "tempMaxHealthBackgroundOpacity", 0.65, { "Background opacity", 0, 1, 0.05, rightW },
            { rightX, compact and -268 or -142, rightW, "LEFT" }, path = "temp_max_health.background_opacity", reason = "MSUF2_TEMP_MAX_HEALTH_BACKGROUND" },
        { "toggle", "preview", false, { "Preview effect", rightX, compact and -340 or -214, rightW },
            path = "temp_max_health.preview", classification = "ephemeral", get = function() return IsAbsorbTextureTestEnabled("tempMaxHealth") == true end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(value) SetAbsorbTextureTest(value and true or false, "tempMaxHealth") end },
    }, bindings, controls)
    local options = { controls.tempMaxHealthTexture, controls.tempMaxHealthOpacity, controls.tempMaxHealthBackgroundOpacity }
    M.TrackRefresh(ctx, SyncControls(function()
        local scopedActive = ScopedControls()
        local on = BarScopeGet("tempMaxHealthEnabled", ReadGBool("tempMaxHealthEnabled", false)) == true
        SetControlEnabled(controls.tempMaxHealthEnabled, scopedActive)
        SetControlsEnabled(options, scopedActive and on)
        SetControlEnabled(controls.preview, true)
    end))
end

function GP.AbsorbControlMeta(parent, path, classification, frames, selectTab)
    local meta = Meta(path, classification)
    local prepare = meta.prepareExactSearchTarget
    local tab = parent == frames.negative and "negative" or parent == frames.heal and "heal" or "positive"
    meta.searchPrepareKind, meta.searchPrepareValue = "barsAbsorbTab", tab
    meta.legacyBarsSettingKey = meta.searchPrepareSettingKey
    meta.searchPrepareSettingKey = nil
    meta.prepareExactSearchTarget = function(widget, target)
        if prepare then
            local scoped = {}
            for key, value in pairs(target) do scoped[key] = value end
            scoped.prepareKind, scoped.prepareValue = "barsScope", "shared"
            if not prepare(widget, scoped) then return false end
        end
        selectTab(tab)
        return true
    end
    return meta
end
function GP.BuildAbsorbTabs(ctx, b)
    local section = Rows.Schema.Section(b:CollapsibleSection("bars_absorb", "Absorb Display", 414, true), "bars")
    local sectionW = section._msuf2Width or ctx.width or 720
    local leftX = 30
    local rightX = max(430, min(560, floor(sectionW * 0.52)))
    local leftW = max(300, min(380, rightX - leftX - 58))
    local rightW = max(300, min(420, sectionW - rightX - 42))
    local tabFrames = {}
    local tabValues = VT(
        "positive", "Absorb (positive)",
        "negative", "Absorb (negative)",
        "heal", "Heal Prediction")
    M.globalBarsAbsorbTabSelection = M.globalBarsAbsorbTabSelection or {}
    local function CurrentTab()
        local key = M.globalBarsAbsorbTabSelection[CurrentBarsScope()] or "positive"
        if key ~= "positive" and key ~= "negative" and key ~= "heal" then key = "positive" end
        return key
    end
    local positive, negative, heal = M.UnitSectionsShared.MakeTabFrames(
        section, -64, sectionW, tabFrames, "positive", "negative", "heal")
    for name, frame in pairs(tabFrames) do
        Rows.Schema.ContextColors(frame, Meta("absorb." .. name .. ".colors", "ephemeral").controlId, "bars")
    end
    Rows.Schema.Colors(positive, { "bar.absorb" }, {
        title = "Absorb Color",
        historySource = "menu:bars-absorb-color",
    })
    Rows.Schema.Colors(negative, { "bar.heal_absorb" }, {
        title = "Heal Absorb Color",
        historySource = "menu:bars-heal-absorb-color",
    })
    Rows.Schema.Colors(heal, { "bar.heal_prediction" }, {
        title = "Heal Prediction Color",
        historySource = "menu:bars-heal-prediction-color",
    })
    local tabs, _, _, SelectAbsorbTab = W.SegmentTabs(ctx, section, {
        label = "", values = tabValues, width = min(660, sectionW - 48),
        frames = tabFrames, defaultTab = "positive", get = CurrentTab,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
            set = function(value) M.globalBarsAbsorbTabSelection[CurrentBarsScope()] = value or "positive" end,
        x = 20, y = -12,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    RegisterControl(tabs, Meta("absorb.workspace_tab", "ephemeral"), "Absorb area", "segment")
    Rows.Schema.Owned(tabs, "bars", "sectionNavigation")

    return section, leftX, rightX, leftW, rightW, tabFrames, SelectAbsorbTab, positive, negative, heal
end

function GP.BuildAbsorbControls(ctx, positive, negative, heal, leftX, rightX, leftW, rightW,
    options, TextureDefault, anchorValues, negativeAnchorValues, healAnchorValues, SyncControls)
    local refs = {}
    Rows.Build(ctx, positive, {
        { "toggle", "enableAbsorbBar", true, { "Show positive absorbs", leftX, -10, leftW },
            path = "absorb.positive.enabled", reason = "MSUF2_ABSORB_ENABLED", afterWrite = function(value)
            BarScopeSet("absorbTextMode", value and 2 or 1, "MSUF2_ABSORB_ENABLED", true)
        end,
            tip = "Draws absorb shields on the unit, such as Power Word: Shield, as an overlay on the health bar." },
        { "dropdown", "absorbAnchorMode", 2, { "Anchor", anchorValues, leftW }, { leftX, -64, leftW, "LEFT" },
            path = "absorb.positive.anchor", reason = "MSUF2_ABSORB_ANCHOR", numeric = true },
        { "slider", "absorbBarHeight", 0, { "Bar height (0 = full)", 0, 100, 1, leftW }, { leftX, -118, leftW, "LEFT" },
            path = "absorb.positive.height", reason = "MSUF2_ABSORB_HEIGHT" },
        { "slider", "absorbBarOffsetY", 0, { "Vertical offset", -100, 100, 1, leftW }, { leftX, -182, leftW, "LEFT" },
            path = "absorb.positive.offset_y", reason = "MSUF2_ABSORB_OFFSET" },
        { "dropdown", "absorbBarTexture", TextureDefault("absorbBarTexture"), { "Texture", function() return TextureValues("Use foreground texture") end,
            rightW }, { rightX, -10, rightW, "LEFT" },
            path = "absorb.positive.texture", reason = "MSUF2_ABSORB_TEXTURE" },
        { "slider", "absorbBarOpacity", 0.75, { "Opacity", 0, 1, 0.05, rightW }, { rightX, -64, rightW, "LEFT" },
            path = "absorb.positive.opacity", reason = "MSUF2_ABSORB_OPACITY" },
        { "toggle", "positiveTest", false, { "Test prediction bars", rightX, -128, rightW }, path = "absorb.positive.preview.test",
            classification = "ephemeral",
            get = function() return IsAbsorbTextureTestEnabled("absorb") == true end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(value) SetAbsorbTextureTest(value and true or false, "absorb") end,
            tip = "Shows sample bars on the frames of the selected scope, even while this bar " ..
                "is turned off, so you can check its look. Cannot be turned on in combat." },
        { "toggle", "overAbsorbOverlay", false, { "Over-absorb overlay", rightX, -182, rightW },
            path = "absorb.positive.over_absorb", reason = "MSUF2_OVER_ABSORB_OVERLAY",
            tip = "Adds a shield glow at the end of the health bar when absorbs plus incoming heals cover all of the missing health." },
        { "toggle", "fullHealthAbsorbStripe", false, { "Full-health absorb stripe", rightX, -236, rightW },
            path = "absorb.positive.full_health_stripe", reason = "MSUF2_FULL_HEALTH_ABSORB_STRIPE",
            tip = "Shows a shield glow at the end of the health bar while the unit is at full health and still has an absorb shield." },
    }, options, refs)
    Rows.Build(ctx, negative, {
        { "toggle", "healAbsorbEnabled", true, { "Show negative heal absorbs", leftX, -10, leftW },
            path = "absorb.negative.enabled", reason = "MSUF2_HEAL_ABSORB_ENABLED",
            tip = "Shows heal absorbs, effects that soak up incoming healing before health can rise, as a bar over current health." },
        { "dropdown", "healAbsorbAnchorMode", 3, { "Anchor", negativeAnchorValues, leftW }, { leftX, -64, leftW, "LEFT" },
            path = "absorb.negative.anchor", reason = "MSUF2_HEAL_ABSORB_ANCHOR", numeric = true },
        { "slider", "healAbsorbBarHeight", 0, { "Bar height (0 = full)", 0, 100, 1, leftW }, { leftX, -118, leftW, "LEFT" },
            path = "absorb.negative.height", reason = "MSUF2_HEAL_ABSORB_HEIGHT" },
        { "slider", "healAbsorbBarOffsetY", 0, { "Vertical offset", -100, 100, 1, leftW }, { leftX, -182, leftW, "LEFT" },
            path = "absorb.negative.offset_y", reason = "MSUF2_HEAL_ABSORB_OFFSET" },
        { "dropdown", "healAbsorbBarTexture", TextureDefault("healAbsorbBarTexture"), { "Texture",
            function() return TextureValues("Use foreground texture") end, rightW }, { rightX, -10, rightW, "LEFT" },
            path = "absorb.negative.texture", reason = "MSUF2_HEAL_ABSORB_TEXTURE" },
        { "slider", "healAbsorbBarOpacity", 1, { "Opacity", 0, 1, 0.05, rightW }, { rightX, -64, rightW, "LEFT" },
            path = "absorb.negative.opacity", reason = "MSUF2_HEAL_ABSORB_OPACITY" },
        { "toggle", "negativeTest", false, { "Test prediction bars", rightX, -128, rightW }, path = "absorb.negative.preview.test",
            classification = "ephemeral",
            get = function() return IsAbsorbTextureTestEnabled("healAbsorb") == true end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(value) SetAbsorbTextureTest(value and true or false, "healAbsorb") end,
            tip = "Shows sample bars on the frames of the selected scope, even while this bar " ..
                "is turned off, so you can check its look. Cannot be turned on in combat." },
    }, options, refs)
    Rows.Build(ctx, heal, {
        { "toggle", "healPredEnabled", ReadGBool("showSelfHealPrediction", false), { "Show heal prediction", leftX, -10, leftW },
            path = "absorb.heal_prediction.enabled", reason = "MSUF2_HEAL_PRED_ENABLED", afterWrite = function(value)
            if SharedScope() then
                G().showSelfHealPrediction = value
            end
        end,
            tip = "Shows incoming heals as a bar on the health bar before they land. Only your own heals count unless Include healing from others is on." },
        { "dropdown", "healPredAnchorMode", 3, { "Anchor", healAnchorValues, leftW }, { leftX, -64, leftW, "LEFT" },
            path = "absorb.heal_prediction.anchor", reason = "MSUF2_HEALPRED_ANCHOR", numeric = true },
        { "slider", "healPredictionBarHeight", 0, { "Bar height (0 = full)", 0, 100, 1, leftW }, { leftX, -118, leftW, "LEFT" },
            path = "absorb.heal_prediction.height", reason = "MSUF2_HEALPRED_HEIGHT" },
        { "slider", "healPredictionBarOffsetY", 0, { "Vertical offset", -100, 100, 1, leftW }, { leftX, -182, leftW, "LEFT" },
            path = "absorb.heal_prediction.offset_y", reason = "MSUF2_HEALPRED_OFFSET" },
        { "dropdown", "healPredictionBarTexture", "", { "Texture", function() return TextureValues("Use foreground texture") end, rightW }, { rightX, -10,
            rightW, "LEFT" },
            path = "absorb.heal_prediction.texture", reason = "MSUF2_HEALPRED_TEXTURE" },
        { "slider", "healPredictionBarOpacity", 0.45, { "Opacity", 0, 1, 0.05, rightW }, { rightX, -64, rightW, "LEFT" },
            path = "absorb.heal_prediction.opacity", reason = "MSUF2_HEALPRED_OPACITY" },
        { "toggle", "healTest", false, { "Test prediction bars", rightX, -128, rightW }, path = "absorb.heal_prediction.preview.test",
            classification = "ephemeral",
            get = function() return IsAbsorbTextureTestEnabled("heal") == true end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(value) SetAbsorbTextureTest(value and true or false, "heal") end,
            tip = "Shows sample bars on the frames of the selected scope, even while this bar " ..
                "is turned off, so you can check its look. Cannot be turned on in combat." },
        { "toggle", "healPredAllHealers", false, { "Include healing from others", rightX, -182, rightW },
            path = "absorb.heal_prediction.all_healers", reason = "MSUF2_HEALPRED_ALL_HEALERS",
            tip = "Counts incoming heals from every healer, not only your own. Useful on group frames when several healers are active." },
    }, options, refs)

    local positiveOptions = { refs.absorbAnchorMode, refs.absorbBarHeight, refs.absorbBarOffsetY, refs.absorbBarTexture, refs.absorbBarOpacity,
        refs.overAbsorbOverlay, refs.fullHealthAbsorbStripe }
    local negativeOptions = { refs.healAbsorbAnchorMode, refs.healAbsorbBarHeight, refs.healAbsorbBarOffsetY, refs.healAbsorbBarTexture,
        refs.healAbsorbBarOpacity }
    local healOptions = { refs.healPredAnchorMode, refs.healPredictionBarHeight, refs.healPredictionBarOffsetY, refs.healPredictionBarTexture,
        refs.healPredictionBarOpacity, refs.healPredAllHealers }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local scopeReason = W.TurnOnReason("Use custom settings for this scope", ScopedControls)
        local function Chain(label, isOn)
            local own = W.TurnOnReason(label, isOn)
            return function(control) return scopeReason(control) or own(control) end
        end
        W.SetControlsDisabledReason({ refs.enableAbsorbBar, refs.healAbsorbEnabled, refs.healPredEnabled }, scopeReason)
        W.SetControlsDisabledReason(positiveOptions, Chain("Show positive absorbs", function() return BarScopeGet("enableAbsorbBar", true) ~= false end))
        W.SetControlsDisabledReason(negativeOptions, Chain("Show negative heal absorbs", function() return BarScopeGet("healAbsorbEnabled", true) ~= false end))
        W.SetControlsDisabledReason(healOptions, Chain("Show heal prediction", function()
            return BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true
        end))
    end
    M.TrackRefresh(ctx, SyncControls(function()
        local scopedActive = ScopedControls()
        SetControlEnabled(refs.enableAbsorbBar, scopedActive)
        SetControlEnabled(refs.healAbsorbEnabled, scopedActive)
        SetControlEnabled(refs.healPredEnabled, scopedActive)
        SetControlsEnabled(positiveOptions, scopedActive and BarScopeGet("enableAbsorbBar", true) ~= false)
        SetControlsEnabled(negativeOptions, scopedActive and BarScopeGet("healAbsorbEnabled", true) ~= false)
        SetControlsEnabled(healOptions, scopedActive and BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true)
        SetControlEnabled(refs.positiveTest, true)
        SetControlEnabled(refs.negativeTest, true)
        SetControlEnabled(refs.healTest, true)
        if refs.absorbAnchorMode.RefreshPreview then refs.absorbAnchorMode:RefreshPreview() end
        if refs.healAbsorbAnchorMode.RefreshPreview then refs.healAbsorbAnchorMode:RefreshPreview() end
        if refs.healPredAnchorMode.RefreshPreview then refs.healPredAnchorMode:RefreshPreview() end
    end))
end

function GP.BuildAbsorbBindings(ctx, tabFrames, SelectAbsorbTab, Apply)
    local options = Rows.Options(BarScopeGet, BarScopeSet, Apply, nil, true)
    options.beforeBind = function(widget, row)
        row.meta = GP.AbsorbControlMeta(widget:GetParent(), row.path, row.classification, tabFrames, SelectAbsorbTab)
    end
    return options
end

local function BuildAbsorbSection(ctx, b)
    local section, leftX, rightX, leftW, rightW, tabFrames, SelectAbsorbTab, positive, negative, heal = GP.BuildAbsorbTabs(ctx, b)

    local SyncControls = M.RefreshProxy()
    local function Apply(reason)
        ApplyBars(reason)
        SyncControls()
    end
    local function TextureDefault(key)
        return function() return ReadG(key, "") end
    end
    local options = GP.BuildAbsorbBindings(ctx, tabFrames, SelectAbsorbTab, Apply)
    local resolve = MSUF.Optional("MSUF_ResolveStatusbarTextureKey")
    local function ResolveBarPreviewTexture(key, fallback)
        key = type(key) == "string" and key ~= "" and key or fallback
        if type(resolve) == "function" then
            local texture = resolve(key)
            if type(texture) == "string" and texture ~= "" then return texture end
        end
        return "Interface\\Buttons\\WHITE8X8"
    end
    local function AnchorPreview(category)
        return function(item)
            local foregroundKey = BarTextureForScope()
            local backgroundKey = BarBackgroundTextureForScope()
            local mode = tonumber(item and item.value) or 3
            local textureKey, opacity, color, showAbsorbEdgeGlow
            if category == "negative" then
                textureKey = BarScopeGet("healAbsorbBarTexture", ReadG("healAbsorbBarTexture", ""))
                opacity = tonumber(BarScopeGet("healAbsorbBarOpacity", ReadG("healAbsorbBarOpacity", 1))) or 1
                color = {
                    tonumber(ReadG("healAbsorbBarColorR", 0.70)) or 0.70,
                    tonumber(ReadG("healAbsorbBarColorG", 0)) or 0,
                    tonumber(ReadG("healAbsorbBarColorB", 0)) or 0,
                    max(0, min(1, opacity)),
                }
            elseif category == "heal" then
                textureKey = BarScopeGet("healPredictionBarTexture", ReadG("healPredictionBarTexture", ""))
                opacity = tonumber(BarScopeGet("healPredictionBarOpacity", ReadG("healPredictionColorA", 0.45))) or 0.45
                color = {
                    tonumber(ReadG("healPredictionColorR", 0)) or 0,
                    tonumber(ReadG("healPredictionColorG", 1)) or 1,
                    tonumber(ReadG("healPredictionColorB", 0)) or 0,
                    max(0, min(1, opacity)),
                }
            else
                textureKey = BarScopeGet("absorbBarTexture", ReadG("absorbBarTexture", ""))
                opacity = tonumber(BarScopeGet("absorbBarOpacity", ReadG("absorbBarOpacity", 0.75))) or 0.75
                color = {
                    tonumber(ReadG("absorbBarColorR", 1)) or 1,
                    tonumber(ReadG("absorbBarColorG", 1)) or 1,
                    tonumber(ReadG("absorbBarColorB", 1)) or 1,
                    max(0, min(1, opacity)),
                }
                showAbsorbEdgeGlow = BarScopeGet("fullHealthAbsorbStripe", ReadGBool("fullHealthAbsorbStripe", false)) == true
            end
            return {
                mode = mode,
                category = category,
                dualDirection = true,
                followInsideHealth = category == "negative",
                showAbsorbEdgeGlow = showAbsorbEdgeGlow,
                healthFraction = mode == 4 and 0.84 or 0.68,
                overlayFraction = category == "negative" and 0.16 or 0.22,
                healthTexture = ResolveBarPreviewTexture(foregroundKey, "Blizzard"),
                backgroundTexture = ResolveBarPreviewTexture(backgroundKey, foregroundKey),
                overlayTexture = ResolveBarPreviewTexture(textureKey, foregroundKey),
                healthColor = { 0.12, 0.62, 0.25, 1 },
                backgroundColor = { 0.025, 0.075, 0.045, 0.92 },
                overlayColor = color,
            }
        end
    end
    -- Negative absorbs have no overflow anchor (choice 4).
    local function AnchorValues(preview, skipOverflow)
        local values = {}
        for _, choice in ipairs({
            { 1, "Anchor to left side" }, { 2, "Anchor to right side" }, { 3, "Follow HP bar" },
            { 4, "Follow HP bar (overflow)" }, { 5, "Reverse from max" },
        }) do
            if not (skipOverflow and choice[1] == 4) then
                values[#values + 1] = { value = choice[1], text = choice[2], previewKind = "barOverlay", barPreview = preview }
            end
        end
        return values
    end
    local anchorValues = AnchorValues(AnchorPreview("positive"))
    local negativeAnchorValues = AnchorValues(AnchorPreview("negative"), true)
    local healAnchorValues = AnchorValues(AnchorPreview("heal"))

    GP.BuildAbsorbControls(ctx, positive, negative, heal, leftX, rightX, leftW, rightW,
        options, TextureDefault, anchorValues, negativeAnchorValues, healAnchorValues, SyncControls)
end


-- Explicit load-time exports for the following responsibility modules.
Parts.BuildAbsorbSection = BuildAbsorbSection
Parts.BuildScopeSection = BuildScopeSection
Parts.BuildTempMaxHealthSection = BuildTempMaxHealthSection
Parts.BuildTextureSection = BuildTextureSection
