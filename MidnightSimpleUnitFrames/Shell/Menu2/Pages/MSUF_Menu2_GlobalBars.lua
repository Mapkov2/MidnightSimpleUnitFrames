local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList

local floor = math.floor
local max = math.max
local min = math.min

local ROUNDED_PREVIEW_WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ROUNDED_PREVIEW_MASK_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local ROUNDED_PREVIEW_MASK = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_4x.tga"
local ROUNDED_PREVIEW_EDGE = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_edge_4x.tga"

local GRADIENT_DIR_KEYS, PRIORITY_LABELS = M.PickDefaults(GP, [[GRADIENT_DIR_KEYS PRIORITY_LABELS]])
local Call, DB, G, Bars, Unit, ReadG, SetG, ReadGBool, SetGBool, ReadB, SetB, NormalizeScopeKey, ScopeDBKeys, ScopeHasOverride, ScopeSetOverride, CurrentBarsScope, IsGFScope, BarScopeGet, BarScopeSet, BarScopeGetBars, BarScopeSetBars, TextureValues, CurrentPowerBarScopeUnit, SmoothPowerGet, SmoothPowerSet, PriorityOrder, PriorityColor, SetPriorityOrder, NormalizePriorityKey, RefreshBorderTestModes, SetAbsorbTextureTest, ClearAbsorbTextureTest, SetControlEnabled, SetControlsEnabled, ApplyBars = M.Pick(GP, [[Call DB G Bars Unit ReadG SetG ReadGBool SetGBool ReadB SetB NormalizeScopeKey ScopeDBKeys ScopeHasOverride ScopeSetOverride CurrentBarsScope IsGFScope BarScopeGet BarScopeSet BarScopeGetBars BarScopeSetBars TextureValues CurrentPowerBarScopeUnit SmoothPowerGet SmoothPowerSet PriorityOrder PriorityColor SetPriorityOrder NormalizePriorityKey RefreshBorderTestModes SetAbsorbTextureTest ClearAbsorbTextureTest SetControlEnabled SetControlsEnabled ApplyBars]])
NormalizePriorityKey = NormalizePriorityKey or function(key) return key end
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
            GF.RefreshVisuals(nil, GF.DIRTY_VISUAL)
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
                local c = frame and frame._c
                if frame and frame.unit and c and GF.DispelScanActive and GF.DispelScanActive(c) and GF._UpdateDispel then
                    GF._UpdateDispel(frame, frame.unit)
                else
                    refreshBorder(frame, frame and frame.unit)
                end
            end
        elseif GF.RefreshVisuals then
            GF.RefreshVisuals(nil, GF.DIRTY_BORDER or GF.DIRTY_VISUAL)
        end
    end

    local function RefreshUnitBorders(units)
        local UF = MSUF and MSUF.UF
        local frames = UF and UF.frames
        for i = 1, #units do
            local unit = units[i]
            local frame = (frames and frames[unit]) or _G["MSUF_" .. tostring(unit)]
            if frame and frame.ForceUpdate then frame:ForceUpdate("MSUF2_BORDER") end
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
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_AGGRO_BORDER_RUNTIME")
        Call("MSUF_ApplyBarOutlineThickness_All")
        Call("MSUF_AggroOutline_ApplyEventRegistration")
        RefreshUnitBorders({ "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" })
        RefreshGroupFrameBorders()
    end

    local function ApplyDispelPurgeBorderRuntime()
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_DISPEL_BORDER_RUNTIME")
        Call("MSUF_ApplyBarOutlineThickness_All")
        Call("MSUF_DispelOutline_ApplyEventRegistration")
        Call("MSUF_RefreshDispelOutlineStates", true)
        RefreshUnitBorders({ "player", "target", "focus", "targettarget" })
        Call("MSUF_RefreshUnitDispelOverlays")
        RefreshGroupFrameBorders()
        if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
            _G.MSUF_SetDispelBorderTestMode(true, BorderTestScope())
        end
        if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
            _G.MSUF_SetPurgeBorderTestMode(true, BorderTestScope())
        end
    end

    local function ApplyBossTargetBorderRuntime()
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_BOSS_TARGET_BORDER_RUNTIME")
        if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate(nil) end
        RefreshUnitBorders({ "boss1", "boss2", "boss3", "boss4", "boss5" })
    end

    local function ApplyHighlightPriorityRuntime()
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_HIGHLIGHT_PRIORITY_RUNTIME")
        RefreshUnitBorders({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss1", "boss2", "boss3", "boss4", "boss5" })
        RefreshGroupFrameBorders()
        Call("MSUF_UFPreview_RequestRefresh", "MSUF2_HIGHLIGHT_PRIORITY")
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
        if type(extraKeywords) == "string" and extraKeywords:find("|", 1, true) then
            for keyword in extraKeywords:gmatch("[^|]+") do keywords[#keywords + 1] = keyword end
        elseif type(extraKeywords) == "table" then
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

    local dispelTriggers = VT("BY_ME", "Dispellable by me", "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")
    local unitDispelOverlayTriggers = VT(
        "BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
        "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")
    local unitDispelOverlayStyles = VT(
        "FULL", "Full Frame", "TOP", "Top Fade", "BOTTOM", "Bottom Fade", "LEFT", "Left Fade", "RIGHT", "Right Fade")
    local function NormalizeDispelTrigger(v)
        local fn = _G.MSUF_NormalizeDispelBorderTrigger
        if type(fn) == "function" then return fn(v) end
        if v == "DISPEL_TYPE" or v == "TYPE" or v == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
        if v == "ANY_DEBUFF" or v == "ANY" or v == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
        return "BY_ME"
    end
    local function NormalizeUnitDispelOverlayTrigger(v)
        local fn = _G.MSUF_NormalizeUnitDispelOverlayTrigger
        if type(fn) == "function" then return fn(v) end
        if v == "BORDER" or v == "INHERIT" or v == "SAME" then return "BORDER" end
        return NormalizeDispelTrigger(v)
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

        M.RequestGeneralApply(reason or "MSUF2_GRADIENT", { preview = true, applyAll = false, notify = false })
        Call("MSUF_UpdateAllBarGradients")
    end

    local function SetOutlineColorForScope(r, g, b)
        r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
        local scope = CurrentBarsScope()
        if scope == "shared" then
            local general = G()
            if general.barOutlineColorR == r and general.barOutlineColorG == g and general.barOutlineColorB == b and general.barOutlineColorA == 1 and general.barOutlineColorMode == nil then
                return false
            end
            general.barOutlineColorMode = nil
            general.barOutlineColorR = r
            general.barOutlineColorG = g
            general.barOutlineColorB = b
            general.barOutlineColorA = 1
            return true
        end

        local keys = ScopeDBKeys(scope)
        if not keys then
            local general = G()
            if general.barOutlineColorR == r and general.barOutlineColorG == g and general.barOutlineColorB == b and general.barOutlineColorA == 1 and general.barOutlineColorMode == nil then
                return false
            end
            general.barOutlineColorMode = nil
            general.barOutlineColorR = r
            general.barOutlineColorG = g
            general.barOutlineColorB = b
            general.barOutlineColorA = 1
            return true
        end

        ScopeSetOverride(scope, "hlOverride", true)
        local db = DB()
        local changed = false
        for i = 1, #keys do
            local key = keys[i]
            db[key] = db[key] or {}
            local entry = db[key]
            if entry.barOutlineColorR ~= r or entry.barOutlineColorG ~= g or entry.barOutlineColorB ~= b or entry.barOutlineColorA ~= 1 or entry.barOutlineColorMode ~= nil then
                changed = true
                entry.barOutlineColorMode = nil
                entry.barOutlineColorR = r
                entry.barOutlineColorG = g
                entry.barOutlineColorB = b
                entry.barOutlineColorA = 1
            end
        end
        return changed
    end

    local function BarTextureForScope()
        return BarScopeGet("barTexture", ReadG("barTexture", "Blizzard"))
    end

    local function SetBarTextureForScope(value)
        value = value or "Blizzard"
        if BarTextureForScope() == value then return false end
        BarScopeSet("barTexture", value, "MSUF2_BAR_TEXTURE")
        return true
    end

    local function BarBackgroundTextureForScope()
        local scope = CurrentBarsScope()
        if scope ~= "shared" and ScopeHasOverride(scope, "hlOverride") then
            local db = DB()
            local keys = ScopeDBKeys(scope)
            for i = 1, #(keys or {}) do
                local entry = db[keys[i]]
                if entry then
                    if entry.barBackgroundTexture ~= nil then return entry.barBackgroundTexture end
                    if entry.barBgTexture ~= nil then return entry.barBgTexture end
                end
            end
        end
        return ReadG("barBackgroundTexture", "")
    end

    local function SetBarBackgroundTextureForScope(value)
        value = value or ""
        local scope = CurrentBarsScope()
        if scope == "shared" then
            local general = G()
            if general.barBackgroundTexture == value then return false end
            general.barBackgroundTexture = value
            return true
        end

        local keys = ScopeDBKeys(scope)
        if not keys then
            local general = G()
            if general.barBackgroundTexture == value then return false end
            general.barBackgroundTexture = value
            return true
        end

        ScopeSetOverride(scope, "hlOverride", true)
        local db = DB()
        local changed = false
        local groupScope = IsGFScope(scope)
        for i = 1, #keys do
            local key = keys[i]
            db[key] = db[key] or {}
            local entry = db[key]
            if groupScope then
                if entry.barBackgroundTexture ~= value or entry.barBgTexture ~= value then changed = true end
                entry.barBackgroundTexture = value
                entry.barBgTexture = value
            else
                if entry.barBackgroundTexture ~= value or entry.barBgTexture ~= nil then changed = true end
                entry.barBackgroundTexture = value
                entry.barBgTexture = nil
            end
        end
        return changed
    end

    local scopeValues = GP.SCOPE_VALUES

    GP.BuildScopeOverrideSection(ctx, b, {
        values = scopeValues,
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
        getOverride = function()
            local key = CurrentBarsScope()
            return ScopeHasOverride(key, "hlOverride")
        end,
        setOverride = function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "hlOverride", v)
                ApplyBars("MSUF2_BARS_OVERRIDE")
            end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        reset = function()
            for i = 1, #scopeValues do
                local key = scopeValues[i].value
                if key ~= "shared" then ScopeSetOverride(key, "hlOverride", false) end
            end
            ApplyBars("MSUF2_BARS_RESET_OVERRIDES")
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hint = "Group Frames inherit Shared textures and gradients by default. Raid also applies to Mythic Raid.",
        updateHint = function(hint, current, active, shared)
            if shared then
                hint:SetText("Group Frames inherit Shared textures and gradients by default. Raid also applies to Mythic Raid.")
            elseif ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This scope is using custom bar settings. Shared changes will not affect it until the override is reset.")
            else
                hint:SetText("This scope follows Shared bar settings. Turn on custom settings here only when this scope needs different bars.")
            end
        end,
    })

    local compactTextures = (ctx.width or 720) < 560
    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 326 or 214, true)
    local leftX, topY = 14, -42
    local rightX = compactTextures and leftX or math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = compactTextures and math.max(220, (ctx.width or 720) - 42) or math.min(300, math.max(220, rightX - 48))
    local gradientY = compactTextures and (topY - 126) or topY

    local function BindTextureDropdown(label, values, getValue, setValue, y)
        local control = W.Dropdown(textures, label, values, leftW)
        M.BindDropdown(ctx, control, getValue, setValue)
        W.MoveWidget(control, textures, leftX, y, leftW, "LEFT")
        return control
    end
    local barTexture = BindTextureDropdown("Bar textures (SharedMedia)", function() return TextureValues(nil) end, BarTextureForScope,
        function(v)
            if SetBarTextureForScope(v) then
                ApplyBars("MSUF2_BAR_TEXTURE")
                RefreshGroupFrameVisuals()
            end
        end, topY)
    local bgTexture = BindTextureDropdown("Background texture", function() return TextureValues("Use foreground texture") end, BarBackgroundTextureForScope,
        function(v)
            if SetBarBackgroundTextureForScope(v) then
                ApplyBars("MSUF2_BAR_BG_TEXTURE")
                RefreshGroupFrameVisuals()
            end
        end, topY - 54)

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
            ApplyGradientRuntime("MSUF2_HP_GRADIENT")
            SyncGradientControls()
        end)
    local powerGradient = W.ToggleAt(textures, "Power bar gradient", rightX, gradientY - 54, compactTextures and 170 or 190)
    M.BindToggle(ctx, powerGradient,
        function() return GradientScopeGet("enablePowerGradient", false) == true end,
        function(v)
            GradientScopeSet("enablePowerGradient", v and true or false)
            ApplyGradientRuntime("MSUF2_POWER_GRADIENT")
            SyncGradientControls()
        end)
    local strength = W.Slider(textures, "Gradient strength", 0, 1, 0.05, 220)
    M.BindSlider(ctx, strength,
        function() return tonumber(GradientScopeGet("gradientStrength", 0.45)) or 0.45 end,
        function(v)
            GradientScopeSet("gradientStrength", tonumber(v) or 0.45)
            ApplyGradientRuntime("MSUF2_GRADIENT_STRENGTH")
        end)
    W.MoveWidget(strength, textures, rightX, gradientY - 90, compactTextures and math.min(leftW, 300) or 220, "LEFT")

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
        T.CenterButtonLabel(btn)
        btn:SetScript("OnClick", function()
            ToggleGradientDirectionForScope(value or "RIGHT")
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
        local valueControlsActive = controlsActive and ((GradientScopeGet("enableGradient", false) == true) or (GradientScopeGet("enablePowerGradient", false) == true))
        SetControlEnabled(barTexture, controlsActive)
        SetControlEnabled(bgTexture, controlsActive)
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
    local absorbMode = W.Dropdown(absorb, "Display mode", VT(1, "Absorb off", 2, "Absorb bar"), absorbLeftW)
    local function ReadAbsorbDisplayMode()
        local mode = tonumber(BarScopeGet("absorbTextMode", 2)) or 2
        return (mode == 1 or mode == 4) and 1 or 2
    end
    local function ApplyAbsorbRuntime(reason)
        Call("MSUF_InvalidateAbsorbCache")
        ApplyBars(reason)
        RefreshGroupFrameVisuals()
    end
    local RefreshAbsorbControls
    local function SyncAbsorbControls()
        if RefreshAbsorbControls then RefreshAbsorbControls() end
    end
    local function AbsorbDefault(value)
        if type(value) == "function" then return value() end
        return value
    end
    local function BindAbsorbDropdown(label, values, key, defaultValue, reason, x, y, width)
        local control = W.Dropdown(absorb, label, values, width)
        M.BindDropdown(ctx, control,
            function() return BarScopeGet(key, AbsorbDefault(defaultValue)) end,
            function(v)
                BarScopeSet(key, v or AbsorbDefault(defaultValue), reason)
                ApplyAbsorbRuntime(reason)
            end)
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    local function BindAbsorbNumberDropdown(label, values, key, defaultValue, reason, x, y, width)
        local control = W.Dropdown(absorb, label, values, width)
        M.BindDropdown(ctx, control,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                BarScopeSet(key, tonumber(v) or defaultValue, reason)
                ApplyAbsorbRuntime(reason)
            end)
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    local function BindAbsorbSlider(label, minValue, maxValue, step, key, defaultValue, reason, x, y, width)
        local control = W.Slider(absorb, label, minValue, maxValue, step, width)
        M.BindSlider(ctx, control,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                BarScopeSet(key, tonumber(v) or defaultValue, reason)
                ApplyAbsorbRuntime(reason)
            end)
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    M.BindDropdown(ctx, absorbMode,
        ReadAbsorbDisplayMode,
        function(v)
            local mode = (tonumber(v) == 1) and 1 or 2
            BarScopeSet("absorbTextMode", mode, "MSUF2_ABSORB_MODE")
            ApplyAbsorbRuntime("MSUF2_ABSORB_MODE")
            SyncAbsorbControls()
        end)
    W.MoveWidget(absorbMode, absorb, absorbLeftX, -70, absorbLeftW, "LEFT")

    local absorbAnchors = VT(
        1, "Anchor to left side", 2, "Anchor to right side", 3, "Follow HP bar",
        4, "Follow HP bar (overflow)", 5, "Reverse from max")
    local absorbAnchor = BindAbsorbNumberDropdown("Absorb bar anchoring", absorbAnchors, "absorbAnchorMode", 2, "MSUF2_ABSORB_ANCHOR", absorbLeftX, -124, absorbLeftW)

    local healPredToggle = W.ToggleAt(absorb, "Heal Prediction Overlay", absorbLeftX, -186, absorbLeftW)
    M.BindToggle(ctx, healPredToggle,
        function()
            if CurrentBarsScopeIsGroupFrame() then
                return BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true
            end
            return ReadGBool("showSelfHealPrediction", false)
        end,
        function(v)
            if CurrentBarsScopeIsGroupFrame() then
                BarScopeSet("healPredEnabled", v and true or false, "MSUF2_GF_HEALPRED")
                Call("MSUF_InvalidateAbsorbCache")
                ApplyBars("MSUF2_GF_HEALPRED")
                RefreshGroupFrameVisuals()
                SyncAbsorbControls()
                return
            end
            SetGBool("showSelfHealPrediction", v, "MSUF2_SELF_HEAL", { preview = true })
            Call("MSUF_RefreshSelfHealPredUnitEvent")
            ApplyBars("MSUF2_SELF_HEAL")
            SyncAbsorbControls()
        end)

    local healPredAnchor = BindAbsorbNumberDropdown("Heal prediction anchoring", absorbAnchors, "healPredAnchorMode", 3, "MSUF2_HEALPRED_ANCHOR", absorbLeftX, -240, absorbLeftW)

    local absorbOpacity = BindAbsorbSlider("Absorb bar opacity", 0, 1, 0.05, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY", absorbLeftX, -294, absorbLeftW)

    W.LabelAt(absorb, "Textures", absorbRightX, -42, absorbRightW, "GameFontNormalSmall", T.colors.accent)
    local absorbTex = BindAbsorbDropdown("Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, "absorbBarTexture", function() return ReadG("absorbBarTexture", "") end, "MSUF2_ABSORB_TEXTURE", absorbRightX, -70, absorbRightW)

    local healAbsorbTex = BindAbsorbDropdown("Heal-absorb texture", function() return TextureValues("Use foreground texture") end, "healAbsorbBarTexture", function() return ReadG("healAbsorbBarTexture", "") end, "MSUF2_HEAL_ABSORB_TEXTURE", absorbRightX, -124, absorbRightW)

    local absorbTest = W.ToggleAt(absorb, "Test prediction bars", absorbRightX, -186, absorbRightW)
    M.BindToggle(ctx, absorbTest,
        function() return _G.MSUF_AbsorbTextureTestMode and true or false end,
        function(v) SetAbsorbTextureTest(v and true or false) end)
    absorbTest:HookScript("OnHide", function() ClearAbsorbTextureTest() end)

    local healAbsorbOpacity = BindAbsorbSlider("Heal-absorb bar opacity", 0, 1, 0.05, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY", absorbRightX, -294, absorbRightW)
    local absorbBarControls = { absorbAnchor, absorbTex, healAbsorbTex, absorbOpacity, healAbsorbOpacity }

    RefreshAbsorbControls = function()
        local mode = ReadAbsorbDisplayMode()
        local showBar = mode == 2
        local scopedActive = ScopedBarsControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local groupScope = CurrentBarsScopeIsGroupFrame()
        local healPredOn
        if groupScope then
            healPredOn = BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true
        else
            healPredOn = ReadGBool("showSelfHealPrediction", false)
        end
        SetControlEnabled(absorbMode, scopedActive)
        SetControlsEnabled(absorbBarControls, scopedActive and showBar)
        SetControlEnabled(absorbTest, true)
        SetControlEnabled(healPredToggle, groupScope and scopedActive or sharedActive)
        SetControlEnabled(healPredAnchor, scopedActive and healPredOn)
    end
    M.AddRefresher(ctx, RefreshAbsorbControls)

    local outline = b:CollapsibleSection("bars_outline", "Frame Outline", 170, false)
    local outlineSlider = W.Slider(outline, "Bar outline thickness", 0, 8, 1, 300)
    M.BindSlider(ctx, outlineSlider,
        function() return tonumber(BarScopeGetBars("barOutlineThickness", 1)) or 1 end,
        function(v)
            BarScopeSetBars("barOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_BAR_OUTLINE")
            ApplyBars("MSUF2_BAR_OUTLINE")
            ApplyOutlineRuntime()
        end)
    local outlineColor = W.Color(outline, "Outline color")
    W.MoveWidget(outlineColor, outline, 30, -96)
    M.BindColor(ctx, outlineColor,
        function()
            return tonumber(BarScopeGet("barOutlineColorR", ReadG("barOutlineColorR", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorG", ReadG("barOutlineColorG", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorB", ReadG("barOutlineColorB", 0))) or 0
        end,
        function(r, g, b)
            if SetOutlineColorForScope(r, g, b) then
                ApplyBars("MSUF2_BAR_OUTLINE_COLOR")
                ApplyOutlineRuntime()
            end
        end)
    M.AddRefresher(ctx, function()
        local active = ScopedBarsControlsActive()
        SetControlEnabled(outlineSlider, active)
        SetControlEnabled(outlineColor, active)
    end)

    local rounded = b:CollapsibleSection("bars_rounded", "Rounded Texture", 246, true)
    local roundLeftX = 30
    local roundRightX = 330
    local roundW = 250
    RegisterRoundedSearch(rounded, "Rounded Texture",
        "rounded section|rounded menu|rounded options|where rounded frames|wo rounded frames",
        "Open this section to enable or disable rounded frame textures and its per-surface toggles.", "section")
    local RefreshRoundedControls
    local function SyncRoundedControls()
        if RefreshRoundedControls then RefreshRoundedControls() end
    end
    local function BindRoundedToggle(label, x, y, key, defaultOn, requireReload, searchKeywords, help, useSwitch)
        local control = (useSwitch and W.SwitchAt or W.ToggleAt)(rounded, label, x, y, roundW)
        M.BindToggle(ctx, control,
            function()
                local value = ReadB(key, defaultOn)
                return defaultOn and value ~= false or value == true
            end,
            function(v)
                SetRoundedBool(key, v, requireReload)
                SyncRoundedControls()
            end)
        RegisterRoundedSearch(control, label, searchKeywords, help)
        return control
    end
    BindRoundedToggle("Rounded frame texture", roundLeftX, -52, "roundedFramesEnabled", false, true,
        "master toggle|all rounded frames|rounded frames master|rounded frames on|rounded frames off|rounded frames einschalten|rounded frames ausschalten|alle abgerundeten frames",
        "Master switch for the rounded frame texture style.", true)
    local roundUnits = BindRoundedToggle("Unit frames", roundLeftX, -90, "roundedUnitFrames", true, nil,
        "rounded unit frames|rounded unitframes|unit frame corners|unitframe corners|abgerundete unitframes|unitframes abgerundet|player target focus boss rounded",
        "Enable or disable rounded textures on unit frames.")
    local roundGroups = BindRoundedToggle("Group frames", roundLeftX, -128, "roundedGroupFrames", true, nil,
        "rounded group frames|rounded party frames|rounded raid frames|group frame corners|abgerundete gruppenframes|party raid abgerundet",
        "Enable or disable rounded textures on group frames.")
    local roundPower = BindRoundedToggle("Power bars", roundRightX, -52, "roundedPowerBars", true, nil,
        "rounded power bars|rounded powerbar|power bar corners|powerbar corners|powerbars abgerundet|powerbar abrunden",
        "Enable or disable rounded textures on power bars.")
    local roundMouseover = BindRoundedToggle("Mouseover highlights", roundRightX, -90, "roundedMouseover", true, nil,
        "rounded mouseover|rounded hover|rounded hover border|mouseover rounded|mouseover highlight rounded|mouseover abgerundet|hover abgerundet",
        "Enable or disable rounded mouseover highlight edges.")
    local roundedPreview = CreateRoundedTexturePreview(rounded, roundLeftX, -154, max(320, (rounded._msuf2Width or ctx.width or 720) - 60))
    RegisterRoundedSearch(roundedPreview, "Rounded Texture Preview",
        "rounded preview|rounded example|rounded image|rounded frame preview|preview rounded frames|rounded frames aussehen|vorschau abgerundete frames",
        "Shows a small preview of the rounded frame texture style.", "preview")
    RefreshRoundedControls = function()
        local active = ReadB("roundedFramesEnabled", false) == true
        SetControlsEnabled({ roundUnits, roundGroups, roundPower, roundMouseover }, active)
        if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end
    end
    M.AddRefresher(ctx, RefreshRoundedControls)

    local highlights = b:CollapsibleSection("bars_highlight", "Highlight Borders", 606, true)
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlGap = 28
    local hlLeftX = 30
    local hlInnerW = max(320, hlW - 60)
    local hlLeftW = max(220, min(380, floor((hlInnerW - hlGap) * 0.46)))
    local hlPreviewX = hlLeftX
    local hlPreviewW = max(280, min(440, hlInnerW - 28))

    local highlightTabFrames = {}
    local function CurrentHighlightTab()
        local tab = M.barsHighlightTab or "modes"
        if tab ~= "modes" and tab ~= "preview" and tab ~= "priority" then tab = "modes" end
        return tab
    end
    local function RefreshHighlightTabs()
        local tab = CurrentHighlightTab()
        for key, frame in pairs(highlightTabFrames) do frame:SetShown(key == tab) end
    end
    local function SetHighlightTab(tab)
        tab = (tab == "preview" or tab == "priority") and tab or "modes"
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("barsHighlightTab", tab)
        else
            M.barsHighlightTab = tab
        end
        RefreshHighlightTabs()
    end

    local highlightTabs = W.Segment(highlights, "Highlight area", VT("modes", "Modes", "preview", "Preview", "priority", "Priority"), min(520, hlInnerW))
    W.MoveWidget(highlightTabs, highlights, hlLeftX, -44, min(520, hlInnerW), "LEFT")
    M.BindSegment(ctx, highlightTabs, CurrentHighlightTab, SetHighlightTab)

    local function HighlightTabFrame(key)
        return M.UnitSectionsShared.MakeTabFrame(highlights, key, -88, hlW, highlightTabFrames)
    end
    local modesFrame, previewFrame, priorityFrame = HighlightTabFrame("modes"), HighlightTabFrame("preview"), HighlightTabFrame("priority")
    if highlightTabs.SetValue then highlightTabs:SetValue(CurrentHighlightTab()) end
    M.AddRefresher(ctx, RefreshHighlightTabs)
    RefreshHighlightTabs()

    W.ControlCard(modesFrame, "Border Modes", nil, hlLeftX - 14, -38, hlLeftW + 28, 438)
    local priorityCardW = min(360, max(260, hlLeftW + 28))
    local priorityCard = W.ControlCard(priorityFrame, "Priority Order", nil, hlLeftX - 14, -38, priorityCardW, 296)
    W.ControlCard(previewFrame, "Preview", nil, hlPreviewX - 14, -38, hlPreviewW + 28, 248)

    local function HighlightPriorityEnabled()
        local value = BarScopeGet("hlPrioEnabled", nil)
        if value == nil then value = BarScopeGet("highlightPrioEnabled", false) end
        return value == true or value == 1 or value == "1"
    end

    local highlight = W.Slider(modesFrame, "Highlight border thickness", 1, 30, 1, hlLeftW)
    M.BindSlider(ctx, highlight,
        function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
        function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER")
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER")
            ApplyBars("MSUF2_HIGHLIGHT_BORDER")
            ApplyAllHighlightBorderRuntime()
        end)
    W.MoveWidget(highlight, modesFrame, hlLeftX, -70, hlLeftW, "LEFT")
    local borderModes = VT(0, "Off", 1, "On")
    local function StopBorderTest(flag, setter, value)
        if value == 1 or not _G[flag] then return end
        local fn = _G[setter]
        if type(fn) == "function" then fn(false) end
    end
    local function BindHighlightDropdown(label, values, y, getValue, setValue)
        local control = W.Dropdown(modesFrame, label, values, hlLeftW)
        M.BindDropdown(ctx, control, getValue, setValue)
        W.MoveWidget(control, modesFrame, hlLeftX, y, hlLeftW, "LEFT")
        return control
    end
    local function BindBorderModeDropdown(label, key, defaultValue, reason, y, flag, setter, apply)
        return BindHighlightDropdown(label, borderModes, y,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                local value = tonumber(v) or defaultValue
                BarScopeSet(key, value, reason)
                StopBorderTest(flag, setter, value)
                ApplyBars(reason)
                apply()
            end)
    end
    local aggro = BindBorderModeDropdown("Aggro border", "aggroOutlineMode", 1, "MSUF2_AGGRO_BORDER", -136,
        "MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", ApplyAggroBorderRuntime)
    local dispelBorder = BindBorderModeDropdown("Dispel border", "dispelOutlineMode", 1, "MSUF2_DISPEL_BORDER", -190,
        "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", ApplyDispelPurgeBorderRuntime)
    local dispelTrigger = BindHighlightDropdown("Dispel border detects", dispelTriggers, -244,
        function() return NormalizeDispelTrigger(BarScopeGet("dispelBorderTrigger", "BY_ME")) end,
        function(v)
            BarScopeSet("dispelBorderTrigger", NormalizeDispelTrigger(v), "MSUF2_DISPEL_TRIGGER")
            ApplyDispelPurgeBorderRuntime()
        end)
    local purge = BindBorderModeDropdown("Purge border", "purgeOutlineMode", 0, "MSUF2_PURGE_BORDER", -298,
        "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", ApplyDispelPurgeBorderRuntime)
    local bossTarget = BindHighlightDropdown("Boss target border", borderModes, -352,
        function()
            local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
            return tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback
        end,
        function(v)
            local value = tonumber(v) or 1
            SetG("bossTargetOutlineMode", value, "MSUF2_BOSS_TARGET_BORDER", { preview = true })
            SetGBool("bossTargetHighlightEnabled", value == 1, "MSUF2_BOSS_TARGET_BORDER", { preview = true })
            StopBorderTest("MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", value)
            ApplyBars("MSUF2_BOSS_TARGET_BORDER")
            ApplyBossTargetBorderRuntime()
        end)

    local bossSharedHint = W.Text(modesFrame, "Boss target border is a shared boss-frame setting.", hlLeftX, -414, hlLeftW, T.colors.dim)
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

    local function BindBorderTestToggle(label, y, flagName, setterName, enabledFn, noScope)
        local control = W.ToggleAt(previewFrame, label, hlPreviewX, y, hlPreviewW)
        M.BindToggle(ctx, control,
            function() return _G[flagName] and true or false end,
            function(v)
                if v and not enabledFn() then M.Refresh(ctx); return end
                local fn = _G[setterName]
                if type(fn) == "function" then
                    if noScope then fn(v and true or false)
                    else fn(v and true or false, BorderTestScope()) end
                end
            end)
        control:HookScript("OnHide", function(self)
            local fn = _G[setterName]
            if _G[flagName] and type(fn) == "function" then
                fn(false)
                self:SetChecked(false)
            end
        end)
        return control
    end

    local aggroTest = BindBorderTestToggle("Test aggro border", -72, "MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", AggroBorderOn)
    local dispelTest = BindBorderTestToggle("Test dispel border", -104, "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", DispelBorderOn)
    _G.MSUF_DispelBorderTestType = _G.MSUF_DispelBorderTestType or "Magic"
    local dispelType = W.Dropdown(previewFrame, "Dispel test type",
        VT("Magic", "Magic", "Curse", "Curse", "Disease", "Disease", "Poison", "Poison", "Bleed", "Bleed"), hlPreviewW)
    M.BindDropdown(ctx, dispelType,
        function() return _G.MSUF_DispelBorderTestType or "Magic" end,
        function(v)
            _G.MSUF_DispelBorderTestType = v or "Magic"
            RefreshBorderTestModes()
        end)
    W.MoveWidget(dispelType, previewFrame, hlPreviewX, -150, hlPreviewW, "LEFT")

    local purgeTest = BindBorderTestToggle("Test purge border", -214, "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", PurgeBorderOn)
    local bossTargetTest = BindBorderTestToggle("Test boss target border", -246, "MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", BossTargetBorderOn, true)

    local function ClearBorderTestIfDisabled(flagName, setterName, enabled)
        local fn = _G[setterName]
        if _G[flagName] and not enabled and type(fn) == "function" then fn(false) end
    end

    M.AddRefresher(ctx, function()
        local scopedActive = HighlightControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local aggroOn = AggroBorderOn()
        local dispelOn = DispelBorderOn()
        local purgeOn = PurgeBorderOn()
        local bossTargetOn = BossTargetBorderOn()
        ClearBorderTestIfDisabled("MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", aggroOn)
        ClearBorderTestIfDisabled("MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", dispelOn)
        ClearBorderTestIfDisabled("MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", purgeOn)
        ClearBorderTestIfDisabled("MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", sharedActive and bossTargetOn)
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
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1)
    end)

    local overlaySectionW = ctx.width or 720
    local overlayCardWProbe = min(900, max(320, overlaySectionW - 40))
    local overlayWide = overlayCardWProbe >= 760
    local overlaySectionH = overlayWide and 360 or 470
    local overlayCardH = overlayWide and 296 or 406
    local ufOverlay = b:CollapsibleSection("bars_unit_dispel_overlay", "UnitFrame Dispel Overlay", overlaySectionH, false)
    local ufOverlayW = ufOverlay._msuf2Width or ctx.width or 720
    local ufOverlayCardW = min(900, max(320, ufOverlayW - 40))
    overlayWide = ufOverlayCardW >= 760
    overlayCardH = overlayWide and 296 or 406
    local ufOverlayCard = W.ControlCard(ufOverlay, "UnitFrame Dispel Overlay", "Tints unit-frame health bars when a configured debuff condition is active.", 20, -38, ufOverlayCardW, overlayCardH)
    local function BindUFOverlayDropdown(label, values, key, defaultValue, normalizer, reason, y)
        local dropdown = W.Dropdown(ufOverlayCard, label, values, 280)
        M.BindDropdown(ctx, dropdown,
            function()
                local value = BarScopeGet(key, defaultValue)
                return normalizer and normalizer(value) or value
            end,
            function(value)
                BarScopeSet(key, normalizer and normalizer(value) or (value or defaultValue), reason)
                ApplyDispelPurgeBorderRuntime()
            end)
        W.MoveWidget(dropdown, ufOverlayCard, 16, y, min(280, ufOverlayCardW - 32), "LEFT")
        return dropdown
    end
    local RefreshUFOverlayControls
    local function SyncUFOverlayControls()
        if RefreshUFOverlayControls then RefreshUFOverlayControls() end
    end
    local function BindUFOverlayToggle(label, key, defaultOn, reason, y)
        local toggle = W.ToggleAt(ufOverlayCard, label, 16, y, ufOverlayCardW - 32)
        M.BindToggle(ctx, toggle,
            function() return BarScopeGet(key, defaultOn) ~= false end,
            function(value)
                BarScopeSet(key, value and true or false, reason)
                ApplyDispelPurgeBorderRuntime()
                SyncUFOverlayControls()
            end)
        return toggle
    end
    local function BindUFOverlaySlider(label, key, defaultValue, reason, y)
        local slider = W.Slider(ufOverlayCard, label, 0.05, 1, 0.05, 340)
        M.BindSlider(ctx, slider,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(value)
                BarScopeSet(key, tonumber(value) or defaultValue, reason)
                ApplyDispelPurgeBorderRuntime()
            end)
        W.MoveWidget(slider, ufOverlayCard, 16, y, min(360, ufOverlayCardW - 72), "CENTER")
        return slider
    end
    local ufOverlayToggle = W.SwitchAt(ufOverlayCard, "UnitFrame Dispel Overlay", ufOverlayCardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, ufOverlayToggle,
        function() return BarScopeGet("unitDispelOverlayEnabled", false) == true end,
        function(v)
            BarScopeSet("unitDispelOverlayEnabled", v and true or false, "MSUF2_UF_DISPEL_OVERLAY")
            ApplyBars("MSUF2_UF_DISPEL_OVERLAY")
            ApplyDispelPurgeBorderRuntime()
            SyncUFOverlayControls()
        end)
    local ufOverlayTrigger = BindUFOverlayDropdown("Overlay detects", unitDispelOverlayTriggers, "unitDispelOverlayTrigger", "BORDER", NormalizeUnitDispelOverlayTrigger, "MSUF2_UF_DISPEL_OVERLAY_TRIGGER", -74)
    local ufOverlayStyle = BindUFOverlayDropdown("Overlay style", unitDispelOverlayStyles, "unitDispelOverlayStyle", "FULL", nil, "MSUF2_UF_DISPEL_OVERLAY_STYLE", -126)
    local ufOverlayCurrent = BindUFOverlayToggle("Show on current health only", "unitDispelOverlayOnHealth", true, "MSUF2_UF_DISPEL_OVERLAY_HEALTH", -174)
    local ufOverlayAlpha = BindUFOverlaySlider("Overlay opacity", "unitDispelOverlayAlpha", 0.35, "MSUF2_UF_DISPEL_OVERLAY_ALPHA", -218)
    local ufOverlayControls = { ufOverlayTrigger, ufOverlayStyle, ufOverlayCurrent, ufOverlayAlpha }

    local ufOverlayGroupHintY = overlayWide and -286 or -386
    local ufOverlayGroupHint = W.Text(ufOverlayCard, "Group frame scopes use Group Frames > Health & Bars > Dispel Overlay.", 16, ufOverlayGroupHintY, ufOverlayCardW - 32, T.colors.muted)
    if ufOverlayGroupHint.SetWordWrap then ufOverlayGroupHint:SetWordWrap(true) end

    RefreshUFOverlayControls = function()
        local groupScope = CurrentBarsScopeIsGroupFrame()
        local activeScope = (not groupScope) and ScopedBarsControlsActive()
        local overlayOn = activeScope and BarScopeGet("unitDispelOverlayEnabled", false) == true
        SetControlEnabled(ufOverlayToggle, activeScope)
        SetControlsEnabled(ufOverlayControls, overlayOn)
        ufOverlayGroupHint:SetShown(groupScope)
    end
    M.AddRefresher(ctx, RefreshUFOverlayControls)

    local prio = W.SwitchAt(priorityCard, "Custom highlight priority", 16, -54, priorityCardW - 32)
    M.BindToggle(ctx, prio,
        HighlightPriorityEnabled,
        function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY")
            if CurrentBarsScope() == "shared" then G().highlightPrioEnabled = on and 1 or 0 end
            ApplyHighlightPriorityRuntime()
        end)

    local rowMax = 4
    local prioContainer, prioRows, prioCount
    local function SavePriorityRows()
        local function WritePriorityRows()
            local sorted = {}
            for i = 1, prioCount do sorted[i] = prioRows[i] end
            table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
            local order = {}
            for i = 1, prioCount do order[i] = sorted[i].key end
            SetPriorityOrder(order)
            ApplyHighlightPriorityRuntime()
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Highlight Priority Order", "global:highlightPriorityOrder", WritePriorityRows)
        else
            WritePriorityRows()
        end
    end
    local function SetPriorityRowsEnabled(enabled)
        prioContainer:SetRowsEnabled(enabled)
    end

    prioContainer = M.UnitSectionsShared.MakeDragSortRows(priorityCard, nil, {
        x = -2, y = -82, width = 190, rowHeight = 22, gap = 4, maxRows = rowMax,
        bg = { 0.12, 0.12, 0.12, 0.85 },
        border = { 0.30, 0.30, 0.30, 0.60 },
        disabledAlpha = 0.4,
        dragAllowed = function() return HighlightControlsActive() and HighlightPriorityEnabled() end,
        onReorder = SavePriorityRows,
    })
    prioRows = prioContainer.rows

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
        prioContainer:SetActiveCount(prioCount)
        SetPriorityRowsEnabled(HighlightControlsActive() and HighlightPriorityEnabled())
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

M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 14 })
