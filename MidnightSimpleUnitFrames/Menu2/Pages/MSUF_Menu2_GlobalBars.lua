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

local ROUNDED_PREVIEW_WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ROUNDED_PREVIEW_MASK_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local ROUNDED_PREVIEW_MASK = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_4x.tga"
local ROUNDED_PREVIEW_EDGE = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_edge_4x.tga"

local UNIT_SCOPE_KEYS = GP.UNIT_SCOPE_KEYS or {}
local TEXT_SCOPE_KEYS = GP.TEXT_SCOPE_KEYS or {}
local POWER_BAR_SCOPE_UNITS = GP.POWER_BAR_SCOPE_UNITS or {}
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
local CurrentPowerBarScopeUnit = GP.CurrentPowerBarScopeUnit
local SmoothPowerGet = GP.SmoothPowerGet
local SmoothPowerSet = GP.SmoothPowerSet
local PriorityDefaults = GP.PriorityDefaults
local PriorityAllowed = GP.PriorityAllowed
local PriorityOrder = GP.PriorityOrder
local PriorityColor = GP.PriorityColor
local SetPriorityOrder = GP.SetPriorityOrder
local HasGroupBlizzardRendererConflict = GP.HasGroupBlizzardRendererConflict
local GroupBlizzardRendererConflictText = GP.GroupBlizzardRendererConflictText
local NotifyDispelGlowBlizzardConflict = GP.NotifyDispelGlowBlizzardConflict
local StopGroupDispelGlowForBlizzardConflict = GP.StopGroupDispelGlowForBlizzardConflict
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
    b:GlobalStyleHeader("Bars", "Textures, gradients, outlines and highlight borders.", 72)

    local function SharedBarsControlsActive()
        return CurrentBarsScope() == "shared"
    end

    local function CurrentBarsScopeIsGroupFrame()
        local scope = CurrentBarsScope()
        if type(IsGFScope) == "function" then return IsGFScope(scope) end
        return scope == "gf_party" or scope == "gf_raid"
    end

    local function ScopedBarsControlsActive()
        local scope = CurrentBarsScope()
        return scope == "shared" or ScopeHasOverride(scope, "hlOverride")
    end

    local function HighlightControlsActive()
        return CurrentBarsScope() ~= nil
    end

    local function BorderTestScope()
        local scope = CurrentBarsScope()
        if scope == "gf_party" then return "party" end
        if scope == "gf_raid" then return "raid" end
        return scope
    end

    local function RefreshGroupFrameVisuals()
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if not GF then return end
        if GF.InvalidateConfCache then GF.InvalidateConfCache() end
        if GF.RefreshVisuals then
            GF.RefreshVisuals()
        elseif _G.MSUF_GF_RefreshOverlays then
            _G.MSUF_GF_RefreshOverlays()
        end
    end

    local function RefreshGroupFrameBorders()
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if not GF then return end
        if GF.InvalidateConfCache then GF.InvalidateConfCache() end
        local refreshBorder = _G.MSUF_GF_RefreshBorder
        if refreshBorder and GF.frames then
            for frame in pairs(GF.frames) do
                if GF.BuildFrameCache then GF.BuildFrameCache(frame) end
                refreshBorder(frame, frame.unit)
            end
        elseif GF.RefreshVisuals then
            GF.RefreshVisuals()
        end
    end

    local function RefreshUnitBorders(units)
        local fn, frames = _G.MSUF_RefreshRareBarVisuals, _G.MSUF_UnitFrames
        if type(fn) ~= "function" or not frames then return end
        for i = 1, #units do
            local frame = frames[units[i]]
            if frame then fn(frame) end
        end
    end

    local function ApplyOutlineRuntime()
        Call("MSUF_ApplyBarOutlineThickness_All")
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and type(GF.RefreshOutlineGeometry) == "function" then
            GF.RefreshOutlineGeometry()
        else
            Call("MSUF_GF_RefreshOutlineGeometry")
            RefreshGroupFrameVisuals()
        end
        Call("MSUF_ApplyRoundedUnitframes")
        Call("MSUF_UFPreview_RequestRefresh", "MSUF2_BAR_OUTLINE")
    end

    local function ApplyAggroBorderRuntime()
        Call("MSUF_ApplyBarOutlineThickness_All")
        Call("MSUF_AggroOutline_ApplyEventRegistration")
        RefreshUnitBorders({ "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" })
        RefreshGroupFrameBorders()
    end

    local function ApplyDispelPurgeBorderRuntime()
        Call("MSUF_ApplyBarOutlineThickness_All")
        Call("MSUF_DispelOutline_ApplyEventRegistration")
        Call("MSUF_RefreshDispelOutlineStates", true)
        RefreshUnitBorders({ "player", "target", "focus", "targettarget" })
        RefreshGroupFrameVisuals()
        if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
            _G.MSUF_SetDispelBorderTestMode(true, BorderTestScope())
        end
        if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
            _G.MSUF_SetPurgeBorderTestMode(true, BorderTestScope())
        end
    end

    local function ApplyBossTargetBorderRuntime()
        Call("MSUF_UpdateBossTargetHighlight", true)
        RefreshUnitBorders({ "boss1", "boss2", "boss3", "boss4", "boss5" })
    end

    local function ApplyAllHighlightBorderRuntime()
        ApplyAggroBorderRuntime()
        ApplyDispelPurgeBorderRuntime()
        ApplyBossTargetBorderRuntime()
    end

    local function ApplyRoundedRuntime()
        Call("MSUF_ApplyRoundedUnitframes")
        Call("MSUF_RefreshAllFrames")
        RefreshGroupFrameVisuals()
        Call("MSUF_UFPreview_RequestRefresh", "MSUF2_ROUNDED")
        Call("MSUF_GF_RefreshPreviewLayout", "party")
        Call("MSUF_GF_RefreshPreviewLayout", "raid")
        Call("MSUF_GF_RefreshPreviewLayout", "mythicraid")
        Call("MSUF_GF_RefreshPreviewBox")
    end

    local function ShowRoundedReloadRequiredPopup()
        if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then
            if _G.print then
                _G.print(M.Tr("|cffffd700MSUF:|r Rounded frame texture changed. Reload the UI with /reload."))
            end
            return
        end
        if not _G.StaticPopupDialogs.MSUF2_ROUNDED_RELOAD_REQUIRED then
            _G.StaticPopupDialogs.MSUF2_ROUNDED_RELOAD_REQUIRED = {
                text = M.Tr("Rounded frame texture was changed.\n\nA UI reload is required because this style rebuilds frame masks and protected frame visuals.\n\nReload now?"),
                button1 = _G.RELOAD or M.Tr("Reload"),
                timeout = 0,
                whileDead = true,
                hideOnEscape = false,
                preferredIndex = 3,
                OnAccept = function()
                    if _G.InCombatLockdown and _G.InCombatLockdown() then
                        if _G.print then
                            _G.print(M.Tr("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload."))
                        end
                        return
                    end
                    if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
                end,
            }
        end
        _G.StaticPopup_Show("MSUF2_ROUNDED_RELOAD_REQUIRED")
    end

    local function SetRoundedBool(key, value, requireReload)
        SetB(key, value and true or false, "MSUF2_ROUNDED", { preview = true })
        ApplyRoundedRuntime()
        if requireReload then ShowRoundedReloadRequiredPopup() end
    end

    local function RegisterRoundedSearch(control, label, extraKeywords, help, kind)
        if not (control and type(M.RegisterSearchWidget) == "function") then return end
        local keywords = {
            "rounded texture", "rounded frame texture", "rounded frames", "round corners", "rounded corners",
            "bars rounded", "global style bars rounded", "enable rounded frames", "disable rounded frames",
            "turn on rounded frames", "turn off rounded frames", "abgerundete frames", "runde kanten",
            "runde ecken", "abrundung", "abrunden", "einschalten", "ausschalten",
        }
        if type(extraKeywords) == "table" then
            for i = 1, #extraKeywords do keywords[#keywords + 1] = extraKeywords[i] end
        elseif extraKeywords then
            keywords[#keywords + 1] = extraKeywords
        end
        M.RegisterSearchWidget(control, {
            label = label,
            kind = kind or control._msuf2ControlKind or "toggle",
            anchor = control._msuf2Title or control._msuf2Label or control,
            values = { "On", "Off", "Enable", "Disable", "Einschalten", "Ausschalten" },
            keywords = keywords,
            help = help or "Controls the rounded frame texture style for unit frames, group frames, power bars, and mouseover highlights.",
        })
    end

    local function SnapPreviewRegion(region)
        if not region then return end
        if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end

    local function MaskRoundedPreviewTexture(sample, key, tex)
        if not (sample and tex and tex.AddMaskTexture and sample.CreateMaskTexture) then return end
        sample._msuf2RoundedPreviewMasks = sample._msuf2RoundedPreviewMasks or {}
        local mask = sample._msuf2RoundedPreviewMasks[key]
        if not mask then
            mask = sample:CreateMaskTexture(nil, "ARTWORK")
            SnapPreviewRegion(mask)
            sample._msuf2RoundedPreviewMasks[key] = mask
        end
        mask:ClearAllPoints()
        mask:SetTexture(ROUNDED_PREVIEW_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(sample)
        if sample._msuf2RoundedPreviewMasked and sample._msuf2RoundedPreviewMasked[tex] == mask then return end
        sample._msuf2RoundedPreviewMasked = sample._msuf2RoundedPreviewMasked or {}
        local old = sample._msuf2RoundedPreviewMasked[tex]
        if old and tex.RemoveMaskTexture then pcall(tex.RemoveMaskTexture, tex, old) end
        if pcall(tex.AddMaskTexture, tex, mask) then
            sample._msuf2RoundedPreviewMasked[tex] = mask
        end
    end

    local function CreateRoundedTexturePreview(parent, x, y, width)
        width = max(320, floor((tonumber(width) or 560) + 0.5))
        local card = W.ControlCard(parent, "Preview", nil, x, y, width, 88)
        if not card then return nil end

        local sampleW = min(440, max(280, width - 44))
        local sampleH = 46
        local powerH = 8
        local sample = CreateFrame("Frame", nil, card)
        sample:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -38)
        sample:SetSize(sampleW, sampleH)
        card._msuf2RoundedPreviewSample = sample

        local bg = sample:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetTexture(ROUNDED_PREVIEW_WHITE8)
        bg:SetAllPoints(sample)
        bg:SetColorTexture(0.015, 0.020, 0.032, 0.96)
        SnapPreviewRegion(bg)
        sample._previewBg = bg

        local healthBg = sample:CreateTexture(nil, "BORDER", nil, -1)
        healthBg:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
        healthBg:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 0, powerH)
        healthBg:SetColorTexture(0.060, 0.070, 0.075, 1)
        sample._previewHealthBg = healthBg

        local health = sample:CreateTexture(nil, "ARTWORK", nil, 1)
        health:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
        health:SetSize(floor(sampleW * 0.78 + 0.5), sampleH - powerH)
        health:SetColorTexture(0.70, 0.69, 0.30, 0.94)
        sample._previewHealth = health

        local powerBg = sample:CreateTexture(nil, "ARTWORK", nil, 2)
        powerBg:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 0, 0)
        powerBg:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 0, 0)
        powerBg:SetHeight(powerH)
        powerBg:SetColorTexture(0.090, 0.055, 0.115, 1)
        sample._previewPowerBg = powerBg

        local power = sample:CreateTexture(nil, "ARTWORK", nil, 3)
        power:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 0, 0)
        power:SetSize(floor(sampleW * 0.66 + 0.5), powerH)
        power:SetColorTexture(0.62, 0.12, 0.78, 1)
        sample._previewPower = power

        local gloss = sample:CreateTexture(nil, "ARTWORK", nil, 4)
        gloss:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
        gloss:SetPoint("BOTTOMRIGHT", sample, "RIGHT", 0, -1)
        gloss:SetColorTexture(1, 1, 1, 0.045)
        sample._previewGloss = gloss

        local name = T.Font(sample, "GameFontHighlightSmall", "Mapkotwo", T.colors.text)
        name:SetPoint("LEFT", sample, "LEFT", 10, 4)
        name:SetWidth(floor(sampleW * 0.42))
        name:SetJustifyH("LEFT")
        if name.SetShadowOffset then name:SetShadowOffset(1, -1) end

        local value = T.Font(sample, "GameFontHighlightSmall", "404K - 100.0%", T.colors.text)
        value:SetPoint("RIGHT", sample, "RIGHT", -10, 4)
        value:SetWidth(floor(sampleW * 0.50))
        value:SetJustifyH("RIGHT")
        if value.SetShadowOffset then value:SetShadowOffset(1, -1) end

        for key, tex in pairs({
            bg = bg,
            healthBg = healthBg,
            health = health,
            powerBg = powerBg,
            power = power,
            gloss = gloss,
        }) do
            MaskRoundedPreviewTexture(sample, key, tex)
        end

        sample._msuf2RoundedPreviewEdges = {}
        for i = 1, 2 do
            local edge = sample:CreateTexture(nil, "OVERLAY", nil, 6)
            edge:SetTexture(ROUNDED_PREVIEW_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            edge:SetPoint("TOPLEFT", sample, "TOPLEFT", -i, i)
            edge:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", i, -i)
            edge:SetVertexColor(0, 0, 0, 1)
            SnapPreviewRegion(edge)
            sample._msuf2RoundedPreviewEdges[i] = edge
        end

        function card:RefreshRoundedPreview()
            sample:SetAlpha((ReadB("roundedFramesEnabled", false) == true) and 1 or 0.62)
        end
        card:RefreshRoundedPreview()
        return card
    end

    local function CurrentGroupGlowBlocked()
        local scope = CurrentBarsScope()
        if scope ~= "gf_party" and scope ~= "gf_raid" then return false end
        return type(HasGroupBlizzardRendererConflict) == "function" and HasGroupBlizzardRendererConflict(scope) == true
    end

    local function GlowConflictTextForCurrentScope()
        if type(GroupBlizzardRendererConflictText) ~= "function" then return nil end
        local scope = CurrentBarsScope()
        if scope == "gf_party" or scope == "gf_raid" then
            return GroupBlizzardRendererConflictText(scope)
        end
        return GroupBlizzardRendererConflictText("shared")
    end

    local function StopGroupGlowForCurrentConflict()
        if type(StopGroupDispelGlowForBlizzardConflict) == "function" then
            StopGroupDispelGlowForBlizzardConflict(CurrentBarsScope())
        end
    end

    local dispelTriggers = {
        { value = "BY_ME", text = "Dispellable by me" },
        { value = "DISPEL_TYPE", text = "Any dispel-type debuff" },
        { value = "ANY_DEBUFF", text = "Any debuff" },
    }
    local function NormalizeDispelTrigger(v)
        local fn = _G.MSUF_NormalizeDispelBorderTrigger
        if type(fn) == "function" then return fn(v) end
        if v == "DISPEL_TYPE" or v == "TYPE" or v == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
        if v == "ANY_DEBUFF" or v == "ANY" or v == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
        return "BY_ME"
    end

    local function GradientKeyActive(entry, key)
        return entry and entry.hlOverride == true
            and entry.gradientOverride == true
            and entry.gradientOverrideVersion == 2
            and type(entry.gradientOverrideKeys) == "table"
            and entry.gradientOverrideKeys[key] == true
    end

    local function MarkGradientKey(entry, key)
        if not entry then return end
        entry.hlOverride = true
        entry.gradientOverride = true
        entry.gradientOverrideVersion = 2
        if type(entry.gradientOverrideKeys) ~= "table" then entry.gradientOverrideKeys = {} end
        entry.gradientOverrideKeys[key] = true
    end

    local function AdoptChangedGradientKey(entry, key, defaultValue)
        if not (entry and entry.hlOverride == true and entry[key] ~= nil) then return end
        if GradientKeyActive(entry, key) then return end
        local shared = ReadG(key, defaultValue)
        if entry[key] ~= shared then MarkGradientKey(entry, key) end
    end

    local function GradientControlsActive()
        local scope = CurrentBarsScope()
        return scope == "shared" or ScopeHasOverride(scope, "hlOverride")
    end

    local function GradientScopeGet(key, defaultValue)
        local scope = CurrentBarsScope()
        if scope ~= "shared" and ScopeHasOverride(scope, "hlOverride") then
            local db = DB()
            local keys = ScopeDBKeys(scope)
            for i = 1, #(keys or {}) do
                local entry = db[keys[i]]
                AdoptChangedGradientKey(entry, key, defaultValue)
                if GradientKeyActive(entry, key) and entry[key] ~= nil then return entry[key] end
            end
        end
        return ReadG(key, defaultValue)
    end

    local function GradientScopeSet(key, value)
        local scope = CurrentBarsScope()
        if scope == "shared" then
            G()[key] = value
            return
        end
        local db = DB()
        local keys = ScopeDBKeys(scope)
        for i = 1, #(keys or {}) do
            local entryKey = keys[i]
            db[entryKey] = db[entryKey] or {}
            MarkGradientKey(db[entryKey], key)
            db[entryKey][key] = value
        end
    end

    local function CurrentGradientDirectionsForScope()
        local directions = {}
        local any = false
        for dir, key in pairs(GRADIENT_DIR_KEYS) do
            local on = GradientScopeGet(key, false) == true
            directions[dir] = on
            if on then any = true end
        end
        if not any then
            local legacy = GradientScopeGet("gradientDirection", "RIGHT")
            if not GRADIENT_DIR_KEYS[legacy] then legacy = "RIGHT" end
            directions[legacy] = true
        end
        return directions
    end

    local function ToggleGradientDirectionForScope(direction)
        direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
        local directions = CurrentGradientDirectionsForScope()
        directions[direction] = not directions[direction]
        local any = false
        for dir in pairs(GRADIENT_DIR_KEYS) do
            if directions[dir] == true then
                any = true
                break
            end
        end
        if not any then directions[direction] = true end
        for dir, key in pairs(GRADIENT_DIR_KEYS) do
            GradientScopeSet(key, directions[dir] == true)
        end
        GradientScopeSet("gradientDirection", direction)
    end

    local function ApplyGradientRuntime(reason)
        if (GradientScopeGet("enableGradient", false) == true) or (GradientScopeGet("enablePowerGradient", false) == true) then
            local strength = tonumber(GradientScopeGet("gradientStrength", nil))
            if not (strength and strength > 0) then GradientScopeSet("gradientStrength", 0.45) end
        end

        local scope = CurrentBarsScope()
        if scope == "shared" then
            Call("MSUF_UFCore_RefreshSettingsCache", reason or "MSUF2_GradientShared")
        elseif not (scope == "gf_party" or scope == "gf_raid") then
            Call("MSUF_UFCore_NotifyConfigChanged", scope == "boss" and nil or scope, true, true, reason or "MSUF2_GradientScope")
        end

        local frames = _G.MSUF_UnitFrames
        if type(frames) == "table" then
            for _, frame in pairs(frames) do
                if frame and frame.unit and frame.hpBar then
                    frame._msufHeavyVisualNextAt = 0
                    local update = _G.MSUF_UpdateSimpleUnitFrame
                    if update then update(frame) end
                    if _G.MSUF_UFCore_UpdatePowerBarFast then _G.MSUF_UFCore_UpdatePowerBarFast(frame) end
                    if ns.Bars and ns.Bars._ApplyHPGradient then
                        if frame.hpGradients then
                            ns.Bars._ApplyHPGradient(frame)
                        elseif frame.hpGradient then
                            ns.Bars._ApplyHPGradient(frame.hpGradient)
                        end
                    end
                    if ns.Bars and ns.Bars.ApplyPowerGradientOnce then
                        frame._msufPowerGradEnabled = nil
                        ns.Bars.ApplyPowerGradientOnce(frame)
                    elseif ns.Bars and ns.Bars._ApplyPowerGradient then
                        if frame.powerGradients then
                            ns.Bars._ApplyPowerGradient(frame)
                        elseif frame.powerGradient then
                            ns.Bars._ApplyPowerGradient(frame.powerGradient)
                        end
                    end
                end
            end
        end
        RefreshGroupFrameVisuals()
    end

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

    local scopeOpts = {
        values = scopeValues,
        width = ctx.width,
        getValue = function() return CurrentBarsScope() end,
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            if _G.MSUF_AbsorbTextureTestMode then SetAbsorbTextureTest(true) end
            RefreshBorderTestModes()
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "hlOverride")
        end,
    }
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(scopeValues, scopeOpts)
    local scopeBottomY = (scopeMetrics and scopeMetrics.bottomY) or -40
    local overrideY = math.min(-58, scopeBottomY - 18)
    local hintY = overrideY - 34

    local scope = b:Section("", math.max(128, math.abs(hintY) + 42))
    if scope.title then scope.title:Hide() end
    local scopeSeg = W.ScopeOverrideBar(ctx, scope, scopeOpts)
    local override = W.ToggleAt(scope, "Use custom settings for this scope", 14, overrideY, 260)
    M.BindToggle(ctx, override,
        function()
            local key = CurrentBarsScope()
            return ScopeHasOverride(key, "hlOverride")
        end,
        function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "hlOverride", v)
                ApplyBars("MSUF2_BARS_OVERRIDE")
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
            if key ~= "shared" then ScopeSetOverride(key, "hlOverride", false) end
        end
        ApplyBars("MSUF2_BARS_RESET_OVERRIDES")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local hint = W.Text(scope, "Group Frames inherit Shared textures and gradients by default. Raid also applies to Mythic Raid.", 14, hintY, ctx.width - 28, T.colors.muted)
    M.AddRefresher(ctx, function()
        local current = CurrentBarsScope()
        local active = {}
        for i = 1, #scopeValues do
            local item = scopeValues[i]
            if item.value ~= "shared" and ScopeHasOverride(item.value, "hlOverride") then
                active[#active + 1] = M.Tr(item.text or "")
            end
        end
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        if #active > 0 then
            overrideInfo:SetText("|cffffffff" .. M.Tr("Overrides:") .. "|r " .. table.concat(active, ", "))
        else
            overrideInfo:SetText("|cffffffff" .. M.Tr("Overrides:") .. "|r " .. M.Tr("None"))
        end
        if shared then
            hint:SetText("Group Frames inherit Shared textures and gradients by default. Raid also applies to Mythic Raid.")
        elseif ScopeHasOverride(current, "hlOverride") then
            hint:SetText("This scope is using custom bar settings. Shared changes will not affect it until the override is reset.")
        else
            hint:SetText("This scope follows Shared bar settings. Turn on custom settings here only when this scope needs different bars.")
        end
        scopeSeg:Refresh()
        hint:SetWidth(ctx.width - 28)
    end)

    local compactTextures = (ctx.width or 720) < 560
    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 326 or 214, true)
    local leftX, topY = 14, -42
    local rightX = compactTextures and leftX or math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = compactTextures and math.max(220, (ctx.width or 720) - 42) or math.min(300, math.max(220, rightX - 48))
    local gradientY = compactTextures and (topY - 126) or topY

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
        function(v)
            SetG("barTexture", v or "Blizzard", "MSUF2_BAR_TEXTURE", { preview = true })
            ApplyBars("MSUF2_BAR_TEXTURE")
            RefreshGroupFrameVisuals()
        end)
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
        function(v)
            SetG("barBackgroundTexture", v or "", "MSUF2_BAR_BG_TEXTURE", { preview = true })
            ApplyBars("MSUF2_BAR_BG_TEXTURE")
            RefreshGroupFrameVisuals()
        end)

    local gradLabel = T.Font(textures, "GameFontHighlightSmall", M.Tr("Gradient"), T.colors.muted)
    gradLabel:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, gradientY)
    local RefreshGradientControls
    local function SyncGradientControls()
        if RefreshGradientControls then RefreshGradientControls() end
    end
    local hpGradient = W.ToggleAt(textures, "HP bar gradient", rightX, gradientY - 24, compactTextures and 150 or 180)
    M.BindToggle(ctx, hpGradient,
        function() return GradientScopeGet("enableGradient", false) == true end,
        function(v)
            GradientScopeSet("enableGradient", v and true or false)
            ApplyBars("MSUF2_HP_GRADIENT")
            ApplyGradientRuntime("MSUF2_HP_GRADIENT")
            SyncGradientControls()
        end)
    local powerGradient = W.ToggleAt(textures, "Power bar gradient", rightX, gradientY - 54, compactTextures and 170 or 190)
    M.BindToggle(ctx, powerGradient,
        function() return GradientScopeGet("enablePowerGradient", false) == true end,
        function(v)
            GradientScopeSet("enablePowerGradient", v and true or false)
            ApplyBars("MSUF2_POWER_GRADIENT")
            ApplyGradientRuntime("MSUF2_POWER_GRADIENT")
            SyncGradientControls()
        end)
    local strength = W.Slider(textures, "Gradient strength", 0, 1, 0.05, 220)
    if strength._msuf2Title then
        strength._msuf2Title:ClearAllPoints()
        strength._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, gradientY - 90)
        strength._msuf2Title:SetWidth(compactTextures and leftW or 220)
    end
    strength:ClearAllPoints()
    strength:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, gradientY - 112)
    strength:SetWidth(compactTextures and math.min(leftW, 300) or 220)
    if strength._msuf2UpdateFill then strength:_msuf2UpdateFill() end
    M.BindSlider(ctx, strength,
        function() return tonumber(GradientScopeGet("gradientStrength", 0.45)) or 0.45 end,
        function(v)
            GradientScopeSet("gradientStrength", tonumber(v) or 0.45)
            ApplyBars("MSUF2_GRADIENT_STRENGTH")
            ApplyGradientRuntime("MSUF2_GRADIENT_STRENGTH")
        end)

    local padX = compactTextures and math.min(rightX + 210, (ctx.width or 720) - 104) or math.min(rightX + 238, (ctx.width or 720) - 104)
    local pad = T.Panel(textures, nil, { 0.020, 0.024, 0.046, 0.55 }, T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, gradientY - 18)
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
            ToggleGradientDirectionForScope(value or "RIGHT")
            ApplyBars("MSUF2_GRADIENT_DIRECTION")
            ApplyGradientRuntime("MSUF2_GRADIENT_DIRECTION")
            SyncGradientControls()
        end)
        directionButtons[value] = btn
        return btn
    end
    PadButton("^", "UP", 31, -5)
    PadButton("<", "LEFT", 8, -27)
    PadButton(">", "RIGHT", 54, -27)
    PadButton("v", "DOWN", 31, -49)
    RefreshGradientControls = function()
        local current = CurrentGradientDirectionsForScope()
        local controlsActive = GradientControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local valueControlsActive = controlsActive and ((GradientScopeGet("enableGradient", false) == true) or (GradientScopeGet("enablePowerGradient", false) == true))
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
    end
    M.AddRefresher(ctx, RefreshGradientControls)

    local absorb = b:CollapsibleSection("bars_absorb", "Absorb Display", 390, true)
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
        function(v)
            local mode = tonumber(v) or 2
            BarScopeSet("absorbTextMode", mode, "MSUF2_ABSORB_MODE")
            Call("MSUF_InvalidateAbsorbCache")
            Call("MSUF_UpdateAbsorbTextMode", mode)
            ApplyBars("MSUF2_ABSORB_MODE")
            RefreshGroupFrameVisuals()
        end)
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
        function(v)
            BarScopeSet("absorbAnchorMode", tonumber(v) or 2, "MSUF2_ABSORB_ANCHOR")
            Call("MSUF_InvalidateAbsorbCache")
            ApplyBars("MSUF2_ABSORB_ANCHOR")
            RefreshGroupFrameVisuals()
        end)
    W.MoveWidget(absorbAnchor, absorb, absorbLeftX, -124, absorbLeftW, "LEFT")

    local selfHeal = W.ToggleAt(absorb, "UnitFrame heal prediction", absorbLeftX, -186, absorbLeftW)
    M.BindToggle(ctx, selfHeal,
        function()
            if CurrentBarsScopeIsGroupFrame() then return false end
            return ReadGBool("showSelfHealPrediction", true)
        end,
        function(v)
            if CurrentBarsScopeIsGroupFrame() then return end
            SetGBool("showSelfHealPrediction", v, "MSUF2_SELF_HEAL", { preview = true })
            Call("MSUF_RefreshSelfHealPredUnitEvent")
            ApplyBars("MSUF2_SELF_HEAL")
        end)
    local selfHealGroupHint = W.Text(absorb, "Group Frame heal prediction is controlled in Group Frames > Health & Bars.", absorbLeftX + 30, -212, absorbLeftW + 80, T.colors.muted)
    selfHealGroupHint:Hide()

    local healPredAnchor = W.Dropdown(absorb, "Heal prediction anchoring", {
        { value = 1, text = "Anchor to left side" },
        { value = 2, text = "Anchor to right side" },
        { value = 3, text = "Follow HP bar" },
        { value = 4, text = "Follow HP bar (overflow)" },
        { value = 5, text = "Reverse from max" },
    }, absorbLeftW)
    M.BindDropdown(ctx, healPredAnchor,
        function() return tonumber(BarScopeGet("healPredAnchorMode", 3)) or 3 end,
        function(v)
            BarScopeSet("healPredAnchorMode", tonumber(v) or 3, "MSUF2_HEALPRED_ANCHOR")
            Call("MSUF_InvalidateAbsorbCache")
            ApplyBars("MSUF2_HEALPRED_ANCHOR")
            RefreshGroupFrameVisuals()
        end)
    W.MoveWidget(healPredAnchor, absorb, absorbLeftX, -240, absorbLeftW, "LEFT")

    local absorbOpacity = W.Slider(absorb, "Absorb bar opacity", 0, 1, 0.05, absorbLeftW)
    M.BindSlider(ctx, absorbOpacity,
        function() return tonumber(BarScopeGet("absorbBarOpacity", 0.75)) or 0.75 end,
        function(v)
            BarScopeSet("absorbBarOpacity", tonumber(v) or 0.75, "MSUF2_ABSORB_OPACITY")
            Call("MSUF_InvalidateAbsorbCache")
            ApplyBars("MSUF2_ABSORB_OPACITY")
            RefreshGroupFrameVisuals()
        end)
    W.MoveWidget(absorbOpacity, absorb, absorbLeftX, -294, absorbLeftW, "LEFT")

    W.LabelAt(absorb, "Textures", absorbRightX, -42, absorbRightW, "GameFontNormalSmall", T.colors.accent)
    local absorbTex = W.Dropdown(absorb, "Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, absorbRightW)
    M.BindDropdown(ctx, absorbTex,
        function() return ReadG("absorbBarTexture", "") end,
        function(v)
            SetG("absorbBarTexture", v or "", "MSUF2_ABSORB_TEXTURE", { preview = true })
            Call("MSUF_UpdateAbsorbBarTextures")
            ApplyBars("MSUF2_ABSORB_TEXTURE")
            RefreshGroupFrameVisuals()
        end)
    W.MoveWidget(absorbTex, absorb, absorbRightX, -70, absorbRightW, "LEFT")

    local healAbsorbTex = W.Dropdown(absorb, "Heal-absorb texture", function() return TextureValues("Use foreground texture") end, absorbRightW)
    M.BindDropdown(ctx, healAbsorbTex,
        function() return ReadG("healAbsorbBarTexture", "") end,
        function(v)
            SetG("healAbsorbBarTexture", v or "", "MSUF2_HEAL_ABSORB_TEXTURE", { preview = true })
            Call("MSUF_UpdateAbsorbBarTextures")
            ApplyBars("MSUF2_HEAL_ABSORB_TEXTURE")
            RefreshGroupFrameVisuals()
        end)
    W.MoveWidget(healAbsorbTex, absorb, absorbRightX, -124, absorbRightW, "LEFT")

    local absorbTest = W.ToggleAt(absorb, "Test absorb textures", absorbRightX, -186, absorbRightW)
    M.BindToggle(ctx, absorbTest,
        function() return _G.MSUF_AbsorbTextureTestMode and true or false end,
        function(v) SetAbsorbTextureTest(v and true or false) end)
    absorbTest:HookScript("OnHide", function() ClearAbsorbTextureTest() end)

    local healAbsorbOpacity = W.Slider(absorb, "Heal-absorb bar opacity", 0, 1, 0.05, absorbRightW)
    M.BindSlider(ctx, healAbsorbOpacity,
        function() return tonumber(BarScopeGet("healAbsorbBarOpacity", 1)) or 1 end,
        function(v)
            BarScopeSet("healAbsorbBarOpacity", tonumber(v) or 1, "MSUF2_HEAL_ABSORB_OPACITY")
            Call("MSUF_InvalidateAbsorbCache")
            ApplyBars("MSUF2_HEAL_ABSORB_OPACITY")
            RefreshGroupFrameVisuals()
        end)
    W.MoveWidget(healAbsorbOpacity, absorb, absorbRightX, -294, absorbRightW, "LEFT")

    M.AddRefresher(ctx, function()
        local mode = tonumber(BarScopeGet("absorbTextMode", 2)) or 2
        local showBar = mode == 2 or mode == 3
        local scopedActive = ScopedBarsControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local groupScope = CurrentBarsScopeIsGroupFrame()
        SetControlEnabled(absorbMode, scopedActive)
        SetControlEnabled(absorbAnchor, scopedActive and showBar)
        SetControlEnabled(absorbTex, sharedActive and showBar)
        SetControlEnabled(healAbsorbTex, sharedActive and showBar)
        SetControlEnabled(absorbTest, showBar)
        SetControlEnabled(absorbOpacity, scopedActive and showBar)
        SetControlEnabled(healAbsorbOpacity, scopedActive and showBar)
        SetControlEnabled(selfHeal, (not groupScope) and sharedActive and mode ~= 1)
        SetControlEnabled(healPredAnchor, (not groupScope) and scopedActive and mode ~= 1 and ReadGBool("showSelfHealPrediction", true))
        if groupScope then selfHealGroupHint:Show() else selfHealGroupHint:Hide() end
    end)

    local outline = b:CollapsibleSection("bars_outline", "Frame Outline", 126, false)
    local outlineSlider = W.Slider(outline, "Bar outline thickness", 0, 8, 1, 300)
    M.BindSlider(ctx, outlineSlider,
        function() return tonumber(BarScopeGetBars("barOutlineThickness", 1)) or 1 end,
        function(v)
            BarScopeSetBars("barOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_BAR_OUTLINE")
            ApplyBars("MSUF2_BAR_OUTLINE")
            ApplyOutlineRuntime()
        end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(outlineSlider, ScopedBarsControlsActive())
    end)

    local rounded = b:CollapsibleSection("bars_rounded", "Rounded Texture", 246, true)
    local roundLeftX = 30
    local roundRightX = 330
    local roundW = 250
    RegisterRoundedSearch(rounded, "Rounded Texture", {
        "rounded section", "rounded menu", "rounded options", "where rounded frames", "wo rounded frames",
    }, "Open this section to enable or disable rounded frame textures and its per-surface toggles.", "section")
    local roundMaster = W.SwitchAt(rounded, "Rounded frame texture", roundLeftX, -52, roundW)
    M.BindToggle(ctx, roundMaster,
        function() return ReadB("roundedFramesEnabled", false) == true end,
        function(v) SetRoundedBool("roundedFramesEnabled", v, true) end)
    RegisterRoundedSearch(roundMaster, "Rounded frame texture", {
        "master toggle", "all rounded frames", "rounded frames master", "rounded frames on", "rounded frames off",
        "rounded frames einschalten", "rounded frames ausschalten", "alle abgerundeten frames",
    }, "Master switch for the rounded frame texture style.")
    local roundUnits = W.ToggleAt(rounded, "Unit frames", roundLeftX, -90, roundW)
    M.BindToggle(ctx, roundUnits,
        function() return ReadB("roundedUnitFrames", true) ~= false end,
        function(v) SetRoundedBool("roundedUnitFrames", v) end)
    RegisterRoundedSearch(roundUnits, "Unit frames", {
        "rounded unit frames", "rounded unitframes", "unit frame corners", "unitframe corners",
        "abgerundete unitframes", "unitframes abgerundet", "player target focus boss rounded",
    }, "Enable or disable rounded textures on unit frames.")
    local roundGroups = W.ToggleAt(rounded, "Group frames", roundLeftX, -128, roundW)
    M.BindToggle(ctx, roundGroups,
        function() return ReadB("roundedGroupFrames", true) ~= false end,
        function(v) SetRoundedBool("roundedGroupFrames", v) end)
    RegisterRoundedSearch(roundGroups, "Group frames", {
        "rounded group frames", "rounded party frames", "rounded raid frames", "group frame corners",
        "abgerundete gruppenframes", "party raid abgerundet",
    }, "Enable or disable rounded textures on group frames.")
    local roundPower = W.ToggleAt(rounded, "Power bars", roundRightX, -52, roundW)
    M.BindToggle(ctx, roundPower,
        function() return ReadB("roundedPowerBars", true) ~= false end,
        function(v) SetRoundedBool("roundedPowerBars", v) end)
    RegisterRoundedSearch(roundPower, "Power bars", {
        "rounded power bars", "rounded powerbar", "power bar corners", "powerbar corners",
        "powerbars abgerundet", "powerbar abrunden",
    }, "Enable or disable rounded textures on power bars.")
    local roundMouseover = W.ToggleAt(rounded, "Mouseover highlights", roundRightX, -90, roundW)
    M.BindToggle(ctx, roundMouseover,
        function() return ReadB("roundedMouseover", true) ~= false end,
        function(v) SetRoundedBool("roundedMouseover", v) end)
    RegisterRoundedSearch(roundMouseover, "Mouseover highlights", {
        "rounded mouseover", "rounded hover", "rounded hover border", "mouseover rounded",
        "mouseover highlight rounded", "mouseover abgerundet", "hover abgerundet",
    }, "Enable or disable rounded mouseover highlight edges.")
    local roundedPreview = CreateRoundedTexturePreview(rounded, roundLeftX, -154, max(320, (rounded._msuf2Width or ctx.width or 720) - 60))
    RegisterRoundedSearch(roundedPreview, "Rounded Texture Preview", {
        "rounded preview", "rounded example", "rounded image", "rounded frame preview",
        "preview rounded frames", "rounded frames aussehen", "vorschau abgerundete frames",
    }, "Shows a small preview of the rounded frame texture style.", "preview")
    M.AddRefresher(ctx, function()
        local active = ReadB("roundedFramesEnabled", false) == true
        SetControlsEnabled({ roundUnits, roundGroups, roundPower, roundMouseover }, active)
        if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end
    end)

    local highlights = b:CollapsibleSection("bars_highlight", "Highlight Borders", 672, true)
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlGap = 28
    local hlLeftX = 30
    local hlInnerW = max(320, hlW - 60)
    local hlLeftW = max(220, min(380, floor((hlInnerW - hlGap) * 0.46)))
    local hlRightX = hlLeftX + hlLeftW + hlGap
    local hlRightW = max(220, min(420, hlInnerW - hlLeftW - hlGap))

    W.ControlCard(highlights, "Border Modes", nil, hlLeftX - 14, -38, hlLeftW + 28, 438)
    W.ControlCard(highlights, "Preview", nil, hlRightX - 14, -38, hlRightW + 28, 248)
    W.ControlCard(highlights, "Dispel Glow", nil, hlRightX - 14, -308, hlRightW + 28, 352)

    local highlight = W.Slider(highlights, "Highlight border thickness", 1, 30, 1, hlLeftW)
    M.BindSlider(ctx, highlight,
        function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
        function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER")
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER")
            ApplyBars("MSUF2_HIGHLIGHT_BORDER")
            ApplyAllHighlightBorderRuntime()
        end)
    W.MoveWidget(highlight, highlights, hlLeftX, -70, hlLeftW, "LEFT")
    local borderModes = {
        { value = 0, text = "Off" },
        { value = 1, text = "On" },
    }
    local aggro = W.Dropdown(highlights, "Aggro border", borderModes, hlLeftW)
    M.BindDropdown(ctx, aggro,
        function() return tonumber(BarScopeGet("aggroOutlineMode", 1)) or 1 end,
        function(v)
            local value = tonumber(v) or 1
            BarScopeSet("aggroOutlineMode", value, "MSUF2_AGGRO_BORDER")
            if value ~= 1 and _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
                _G.MSUF_SetAggroBorderTestMode(false)
            end
            ApplyBars("MSUF2_AGGRO_BORDER")
            ApplyAggroBorderRuntime()
        end)
    W.MoveWidget(aggro, highlights, hlLeftX, -136, hlLeftW, "LEFT")

    local dispelBorder = W.Dropdown(highlights, "Dispel border", borderModes, hlLeftW)
    M.BindDropdown(ctx, dispelBorder,
        function() return tonumber(BarScopeGet("dispelOutlineMode", 1)) or 1 end,
        function(v)
            local value = tonumber(v) or 1
            BarScopeSet("dispelOutlineMode", value, "MSUF2_DISPEL_BORDER")
            if value ~= 1 and _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
                _G.MSUF_SetDispelBorderTestMode(false)
            end
            ApplyBars("MSUF2_DISPEL_BORDER")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(dispelBorder, highlights, hlLeftX, -190, hlLeftW, "LEFT")

    local dispelTrigger = W.Dropdown(highlights, "Dispel border detects", dispelTriggers, hlLeftW)
    M.BindDropdown(ctx, dispelTrigger,
        function() return NormalizeDispelTrigger(BarScopeGet("dispelBorderTrigger", "BY_ME")) end,
        function(v)
            BarScopeSet("dispelBorderTrigger", NormalizeDispelTrigger(v), "MSUF2_DISPEL_TRIGGER")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(dispelTrigger, highlights, hlLeftX, -244, hlLeftW, "LEFT")

    local purge = W.Dropdown(highlights, "Purge border", borderModes, hlLeftW)
    M.BindDropdown(ctx, purge,
        function() return tonumber(BarScopeGet("purgeOutlineMode", 0)) or 0 end,
        function(v)
            local value = tonumber(v) or 0
            BarScopeSet("purgeOutlineMode", value, "MSUF2_PURGE_BORDER")
            if value ~= 1 and _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
                _G.MSUF_SetPurgeBorderTestMode(false)
            end
            ApplyBars("MSUF2_PURGE_BORDER")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(purge, highlights, hlLeftX, -298, hlLeftW, "LEFT")

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
            if value ~= 1 and _G.MSUF_BossTargetBorderTestMode and type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then
                _G.MSUF_SetBossTargetBorderTestMode(false)
            end
            ApplyBars("MSUF2_BOSS_TARGET_BORDER")
            ApplyBossTargetBorderRuntime()
        end)
    W.MoveWidget(bossTarget, highlights, hlLeftX, -352, hlLeftW, "LEFT")

    local bossSharedHint = W.Text(highlights, "Boss target border is a shared boss-frame setting.", hlLeftX, -414, hlLeftW, T.colors.dim)
    if bossSharedHint.SetWordWrap then bossSharedHint:SetWordWrap(true) end

    local function AggroBorderOn()
        return tonumber(BarScopeGet("aggroOutlineMode", 1)) == 1
    end

    local function DispelBorderOn()
        return tonumber(BarScopeGet("dispelOutlineMode", 1)) == 1
    end

    local function PurgeBorderOn()
        return tonumber(BarScopeGet("purgeOutlineMode", 0)) == 1
    end

    local function BossTargetBorderOn()
        local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
        return (tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback) == 1
    end

    local aggroTest = W.ToggleAt(highlights, "Test aggro border", hlRightX, -72, hlRightW)
    M.BindToggle(ctx, aggroTest,
        function() return _G.MSUF_AggroBorderTestMode and true or false end,
        function(v)
            if v and not AggroBorderOn() then M.Refresh(ctx); return end
            if type(_G.MSUF_SetAggroBorderTestMode) == "function" then _G.MSUF_SetAggroBorderTestMode(v and true or false, BorderTestScope()) end
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
            if v and not DispelBorderOn() then M.Refresh(ctx); return end
            if type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(v and true or false, BorderTestScope()) end
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
            if v and not PurgeBorderOn() then M.Refresh(ctx); return end
            if type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(v and true or false, BorderTestScope()) end
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
            if v and not BossTargetBorderOn() then M.Refresh(ctx); return end
            if type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then _G.MSUF_SetBossTargetBorderTestMode(v and true or false) end
        end)
    bossTargetTest:HookScript("OnHide", function(self)
        if _G.MSUF_BossTargetBorderTestMode and type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then
            _G.MSUF_SetBossTargetBorderTestMode(false)
            self:SetChecked(false)
        end
    end)

    local glowConflictHint = W.Text(highlights, "", hlRightX, -336, hlRightW, { 1.00, 0.72, 0.25, 1 })
    if glowConflictHint.SetWordWrap then glowConflictHint:SetWordWrap(true) end
    local enabled = W.ToggleAt(highlights, "Dispel glow effect", hlRightX, -382, hlRightW)
    M.BindToggle(ctx, enabled,
        function()
            if CurrentGroupGlowBlocked() then return false end
            return BarScopeGet("hlDispelGlowEnabled", true) ~= false
        end,
        function(v)
            if v and CurrentGroupGlowBlocked() then
                if type(NotifyDispelGlowBlizzardConflict) == "function" then NotifyDispelGlowBlizzardConflict(CurrentBarsScope()) end
                StopGroupGlowForCurrentConflict()
                M.Refresh(ctx)
                return
            end
            BarScopeSet("hlDispelGlowEnabled", v and true or false, "MSUF2_DISPEL_GLOW")
            ApplyBars("MSUF2_DISPEL_GLOW")
            ApplyDispelPurgeBorderRuntime()
        end)
    local style = W.Segment(highlights, "Glow style", {
        { value = "PIXEL", text = "Pixel" },
        { value = "AUTOCAST", text = "AutoCast" },
        { value = "PROC", text = "Proc" },
    }, hlRightW)
    M.BindSegment(ctx, style,
        function() return NormalizeGlowStyle(BarScopeGet("hlDispelGlowStyle", "PIXEL")) end,
        function(v)
            BarScopeSet("hlDispelGlowStyle", NormalizeGlowStyle(v), "MSUF2_DISPEL_STYLE")
            ApplyBars("MSUF2_DISPEL_STYLE")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(style, highlights, hlRightX, -430, hlRightW, "LEFT")

    local lines = W.Slider(highlights, "Glow lines / particles", 2, 16, 1, hlRightW)
    M.BindSlider(ctx, lines,
        function() return tonumber(BarScopeGet("hlDispelGlowLines", 8)) or 8 end,
        function(v)
            BarScopeSet("hlDispelGlowLines", floor((tonumber(v) or 8) + 0.5), "MSUF2_DISPEL_GLOW_LINES")
            ApplyBars("MSUF2_DISPEL_GLOW_LINES")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(lines, highlights, hlRightX, -484, hlRightW, "LEFT")

    local speed = W.Slider(highlights, "Glow speed", 0.05, 1, 0.05, hlRightW)
    M.BindSlider(ctx, speed,
        function() return tonumber(BarScopeGet("hlDispelGlowFrequency", 0.25)) or 0.25 end,
        function(v)
            BarScopeSet("hlDispelGlowFrequency", tonumber(v) or 0.25, "MSUF2_DISPEL_GLOW_SPEED")
            ApplyBars("MSUF2_DISPEL_GLOW_SPEED")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(speed, highlights, hlRightX, -538, hlRightW, "LEFT")

    local thickness = W.Slider(highlights, "Glow thickness (Pixel)", 1, 5, 1, hlRightW)
    M.BindSlider(ctx, thickness,
        function() return tonumber(BarScopeGet("hlDispelGlowThickness", 2)) or 2 end,
        function(v)
            BarScopeSet("hlDispelGlowThickness", floor((tonumber(v) or 2) + 0.5), "MSUF2_DISPEL_THICKNESS")
            ApplyBars("MSUF2_DISPEL_THICKNESS")
            ApplyDispelPurgeBorderRuntime()
        end)
    W.MoveWidget(thickness, highlights, hlRightX, -592, hlRightW, "LEFT")

    M.AddRefresher(ctx, function()
        local scopedActive = HighlightControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local aggroOn = AggroBorderOn()
        local dispelOn = DispelBorderOn()
        local purgeOn = PurgeBorderOn()
        local bossTargetOn = BossTargetBorderOn()
        if _G.MSUF_AggroBorderTestMode and not aggroOn and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
            _G.MSUF_SetAggroBorderTestMode(false)
        end
        if _G.MSUF_DispelBorderTestMode and not dispelOn and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
            _G.MSUF_SetDispelBorderTestMode(false)
        end
        if _G.MSUF_PurgeBorderTestMode and not purgeOn and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
            _G.MSUF_SetPurgeBorderTestMode(false)
        end
        if _G.MSUF_BossTargetBorderTestMode and (not sharedActive or not bossTargetOn) and type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then
            _G.MSUF_SetBossTargetBorderTestMode(false)
        end
        local groupGlowBlocked = CurrentGroupGlowBlocked()
        if groupGlowBlocked then StopGroupGlowForCurrentConflict() end
        local glowOn = (not groupGlowBlocked) and BarScopeGet("hlDispelGlowEnabled", true) ~= false
        local pixelGlow = NormalizeGlowStyle(BarScopeGet("hlDispelGlowStyle", "PIXEL")) == "PIXEL"
        local conflictText = GlowConflictTextForCurrentScope()
        if conflictText then
            glowConflictHint:SetText(conflictText)
            glowConflictHint:Show()
            local color = groupGlowBlocked and { 1.00, 0.55, 0.20, 1 } or T.colors.muted
            glowConflictHint:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        else
            glowConflictHint:SetText("")
            glowConflictHint:Hide()
        end
        SetControlEnabled(highlight, scopedActive)
        SetControlEnabled(aggro, scopedActive)
        SetControlEnabled(dispelBorder, scopedActive)
        SetControlEnabled(dispelTrigger, scopedActive and dispelOn)
        SetControlEnabled(purge, scopedActive)
        SetControlEnabled(bossTarget, sharedActive)
        SetControlEnabled(aggroTest, scopedActive and aggroOn)
        SetControlEnabled(dispelTest, scopedActive and dispelOn)
        SetControlEnabled(dispelType, scopedActive and dispelOn)
        SetControlEnabled(purgeTest, scopedActive and purgeOn)
        SetControlEnabled(bossTargetTest, sharedActive and bossTargetOn)
        SetControlEnabled(enabled, scopedActive and not groupGlowBlocked)
        SetControlEnabled(style, scopedActive and glowOn)
        SetControlEnabled(lines, scopedActive and glowOn)
        SetControlEnabled(speed, scopedActive and glowOn)
        SetControlEnabled(thickness, scopedActive and glowOn and pixelGlow)
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1)
    end)

    local priority = b:CollapsibleSection("bars_priority", "Highlight Priority", 350, false)
    local priorityCardW = min(360, max(260, (priority._msuf2Width or ctx.width or 720) - 40))
    local priorityCard = W.ControlCard(priority, "Priority Order", nil, 20, -38, priorityCardW, 296)
    local prio = W.SwitchAt(priorityCard, "Custom highlight priority", 16, -54, priorityCardW - 32)
    M.BindToggle(ctx, prio,
        function() return BarScopeGet("hlPrioEnabled", false) == true end,
        function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY")
            if CurrentBarsScope() == "shared" then G().highlightPrioEnabled = on and 1 or 0 end
            ApplyBars("MSUF2_HIGHLIGHT_PRIORITY")
            ApplyAllHighlightBorderRuntime()
        end)

    local rowH, rowGap, rowMax = 22, 4, 8
    local prioContainer = CreateFrame("Frame", nil, priorityCard)
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
        local function WritePriorityRows()
            local sorted = {}
            for i = 1, prioCount do sorted[i] = prioRows[i] end
            table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
            local order = {}
            for i = 1, prioCount do order[i] = sorted[i].key end
            SetPriorityOrder(order)
            ApplyBars("MSUF2_HIGHLIGHT_PRIORITY_ORDER")
            ApplyAllHighlightBorderRuntime()
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Highlight Priority Order", "global:highlightPriorityOrder", WritePriorityRows)
        else
            WritePriorityRows()
        end
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
            if not (HighlightControlsActive() and BarScopeGet("hlPrioEnabled", false) == true) then return end
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
            row.frame._label:SetText(M.Tr(PRIORITY_LABELS[key] or key))
            row.frame._numText:SetText(tostring(i))
        end
        SnapPriorityRows()
        SetPriorityRowsEnabled(HighlightControlsActive() and BarScopeGet("hlPrioEnabled", false) == true)
    end
    RefreshPriorityRows()
    M.AddRefresher(ctx, function()
        SetControlEnabled(prio, HighlightControlsActive())
        RefreshPriorityRows()
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

M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 9 })
