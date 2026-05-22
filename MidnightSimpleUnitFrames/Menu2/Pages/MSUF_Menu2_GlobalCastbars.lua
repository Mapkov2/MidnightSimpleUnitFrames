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

local WHITE8 = "Interface\\Buttons\\WHITE8X8"

local function BuildCastbars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Castbar", "Castbar behavior, textures, GCD and interrupt indicators.", 72)

    local function EnsureCastbars()
        if type(_G.MSUF_EnsureAddonLoaded) == "function" then
            pcall(_G.MSUF_EnsureAddonLoaded, "MidnightSimpleUnitFrames_Castbars")
        elseif _G.C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
            pcall(C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
        end
    end

    local function ApplyCastbarTextures(reason)
        EnsureCastbars()
        Call("MSUF_UpdateCastbarTextures_Immediate")
        Call("MSUF_UpdateCastbarTextures")
        Call("MSUF_UpdateCastbarVisuals_Immediate")
        Call("MSUF_UpdateCastbarVisuals")
        Call("MSUF_UpdateBossCastbarPreview")
        ApplyCastbars(reason or "MSUF2_CASTBAR_TEXTURES")
    end

    local function BuildPreview()
        EnsureCastbars()

        local section = b:Section("Preview", 132)
        local sectionW = section._msuf2Width or b.width or ctx.width or 720
        local innerW = max(360, sectionW - 28)
        local preview = {
            castType = "normal",
            layoutUnit = M._msuf2CastbarPreviewUnit or "player",
            progress = 0,
            interruptUntil = 0,
            shakeUntil = 0,
            shakeStart = 0,
            shakeStrength = tonumber(ReadG("castbarShakeStrength", 8)) or 8,
        }

        local function ResetEmpowerBlinkState(target)
            if not target then return end
            local flashStart = target._stageFlashStart or {}
            local flashUntil = target._stageFlashUntil or {}
            for i = 1, 4 do
                flashStart[i] = nil
                flashUntil[i] = nil
            end
            target._stageFlashStart = flashStart
            target._stageFlashUntil = flashUntil
            target._lastEmpowerStageTick = nil
            target._lastEmpowerProgress = nil
        end
        ResetEmpowerBlinkState(preview)

        local subtitle = T.Font(section, "GameFontDisableSmall", "Normal / Channel / Empowered", T.colors.muted)
        subtitle:SetPoint("TOPLEFT", section.title or section, "BOTTOMLEFT", 0, -5)
        subtitle:SetJustifyH("LEFT")
        subtitle:Hide()

        local function CenterButtonText(btn)
            if btn and btn._msuf2Label then
                btn._msuf2Label:ClearAllPoints()
                btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
                btn._msuf2Label:SetJustifyH("CENTER")
            end
            return btn
        end

        local function CastbarPrefix(unit)
            if type(_G.MSUF_GetCastbarPrefix) == "function" then
                return _G.MSUF_GetCastbarPrefix(unit)
            end
            if unit == "player" then return "castbarPlayer" end
            if unit == "target" then return "castbarTarget" end
            if unit == "focus" then return "castbarFocus" end
            return nil
        end

        local function CastbarReferenceFrame(unit)
            if unit == "player" then return _G.MSUF_PlayerCastbarPreview or _G.MSUF_PlayerCastbar end
            if unit == "target" then return _G.MSUF_TargetCastbarPreview or _G.MSUF_TargetCastbar end
            if unit == "focus" then return _G.MSUF_FocusCastbarPreview or _G.MSUF_FocusCastbar end
            if unit == "boss" then return _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1 or _G.MSUF_BossCastbar1 end
            return nil
        end

        local function ReadPreviewCastbarSize(unit, g)
            local fallbackW, fallbackH = 271, 18
            if unit == "target" then fallbackW = 272
            elseif unit == "focus" then fallbackW = 175
            elseif unit == "boss" then fallbackW, fallbackH = 176, 12 end
            if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
                local desiredW, desiredH = _G.MSUF_GetCastbarDesiredSize(unit == "boss" and "boss1" or unit, g or {}, CastbarReferenceFrame(unit), fallbackW, fallbackH)
                if desiredW and desiredW > 0 and desiredH and desiredH > 0 then
                    return min(900, max(40, desiredW)), min(80, max(6, desiredH))
                end
            end
            local w, h
            if unit == "boss" then
                w = g and tonumber(g.bossCastbarWidth)
                h = g and tonumber(g.bossCastbarHeight)
            else
                local prefix = CastbarPrefix(unit)
                w = prefix and g and tonumber(g[prefix .. "BarWidth"]) or nil
                h = prefix and g and tonumber(g[prefix .. "BarHeight"]) or nil
            end
            w = tonumber(w) or tonumber(ReadG("castbarGlobalWidth", fallbackW)) or fallbackW
            h = tonumber(h) or tonumber(ReadG("castbarGlobalHeight", fallbackH)) or fallbackH
            return min(900, max(40, w)), min(80, max(6, h))
        end

        local function CastbarTextKey(unit, suffix, bossKey)
            if unit == "boss" then return bossKey end
            local prefix = CastbarPrefix(unit)
            return prefix and (prefix .. suffix) or nil
        end

        local function ReadCastbarNum(g, unit, suffix, bossKey, fallback)
            local key = CastbarTextKey(unit, suffix, bossKey)
            local value = key and g and tonumber(g[key]) or nil
            if value == nil and suffix and suffix:find("Icon", 1, true) then
                local globalKey = suffix:gsub("^Icon", "castbarIcon")
                value = g and tonumber(g[globalKey]) or nil
            end
            return value ~= nil and value or fallback
        end

        local function CastbarShowIcon(unit, g)
            if unit == "boss" then return not (g and g.showBossCastIcon == false) end
            local prefix = CastbarPrefix(unit)
            local key = prefix and (prefix .. "ShowIcon") or nil
            if key and g and g[key] ~= nil then return g[key] ~= false end
            return ReadGBool("castbarShowIcon", true)
        end

        local function CastbarShowText(unit, g)
            if unit == "boss" then return not (g and g.showBossCastName == false) end
            local prefix = CastbarPrefix(unit)
            local key = prefix and (prefix .. "ShowSpellName") or nil
            if key and g and g[key] ~= nil then return g[key] ~= false end
            return ReadGBool("castbarShowSpellName", true)
        end

        local function CastbarShowTime(unit, g)
            if unit == "boss" then return not (g and g.showBossCastTime == false) end
            local key = (unit == "player" and "showPlayerCastTime")
                or (unit == "target" and "showTargetCastTime")
                or (unit == "focus" and "showFocusCastTime")
            return not (key and g and g[key] == false)
        end

        local unitButtons = {}
        local unitBox = T.Panel(section, nil, { 0.020, 0.026, 0.052, 0.94 }, T.colors.borderSoft)
        unitBox:SetSize(232, 34)
        unitBox:SetPoint("TOPLEFT", section, "TOPLEFT", 82, -12)
        for i, spec in ipairs({
            { key = "player", text = "Player" },
            { key = "target", text = "Target" },
            { key = "focus", text = "Focus" },
            { key = "boss", text = "Boss" },
        }) do
            local layoutUnit = spec.key
            local btn = CenterButtonText(T.Button(unitBox, spec.text, 52, 24))
            btn._msuf2AllowCombatClick = true
            btn._msuf2SkipHistoryCheckpoint = true
            btn:SetPoint("LEFT", unitBox, "LEFT", 6 + ((i - 1) * 56), 0)
            btn:SetScript("OnClick", function()
                preview.layoutUnit = layoutUnit
                M._msuf2CastbarPreviewUnit = layoutUnit
                if preview.Refresh then preview:Refresh() end
            end)
            unitButtons[layoutUnit] = btn
        end

        local typeButtons = {}
        local buttonW, buttonGap, interruptW = 82, 6, 90
        local buttonsW = (buttonW * 3) + (buttonGap * 2) + 12
        local typeBox = T.Panel(section, nil, { 0.020, 0.026, 0.052, 0.94 }, T.colors.borderSoft)
        typeBox:SetSize(buttonsW, 34)
        typeBox:SetPoint("TOPRIGHT", section, "TOPRIGHT", -(14 + interruptW + 10), -12)

        for i, spec in ipairs({
            { key = "normal", text = "Normal" },
            { key = "channel", text = "Channel" },
            { key = "empowered", text = "Empowered" },
        }) do
            local castType = spec.key
            local btn = CenterButtonText(T.Button(typeBox, spec.text, buttonW, 24))
            btn._msuf2AllowCombatClick = true
            btn._msuf2SkipHistoryCheckpoint = true
            btn:SetPoint("LEFT", typeBox, "LEFT", 6 + ((i - 1) * (buttonW + buttonGap)), 0)
            btn:SetScript("OnClick", function()
                preview.castType = castType
                preview.progress = 0
                if preview.Refresh then preview:Refresh() end
            end)
            typeButtons[castType] = btn
        end

        local interrupt = CenterButtonText(T.SkinDangerButton(T.Button(section, "Interrupt", interruptW, 24)))
        interrupt._msuf2AllowCombatClick = true
        interrupt._msuf2SkipHistoryCheckpoint = true
        interrupt:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -17)
        interrupt:SetScript("OnClick", function()
            if preview.PlayShake then preview:PlayShake(tonumber(ReadG("castbarShakeStrength", 8)) or 8, true) end
        end)

        local box = T.Panel(section, nil, { 0.018, 0.022, 0.044, 0.88 }, T.colors.borderSoft)
        box:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -50)
        box:SetSize(innerW, 62)

        local portrait = T.Panel(box, nil, { 0.040, 0.060, 0.120, 0.96 }, { 0.16, 0.22, 0.42, 0.75 })
        portrait:SetSize(52, 52)
        portrait:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -19)
        local portraitGlow = portrait:CreateTexture(nil, "ARTWORK")
        portraitGlow:SetPoint("CENTER", portrait, "CENTER", 0, 7)
        portraitGlow:SetSize(28, 28)
        portraitGlow:SetTexture(WHITE8)
        portraitGlow:SetVertexColor(0.45, 0.52, 1.00, 0.45)
        local portraitBody = portrait:CreateTexture(nil, "OVERLAY")
        portraitBody:SetPoint("BOTTOM", portrait, "BOTTOM", 0, 6)
        portraitBody:SetSize(38, 16)
        portraitBody:SetTexture(WHITE8)
        portraitBody:SetVertexColor(0.10, 0.28, 0.34, 0.78)
        portrait:Hide()

        local mainX = 18
        local barW = min(720, max(280, innerW - 36))
        local unitName = T.Font(box, "GameFontNormalSmall", "Target of Target", T.colors.text)
        unitName:SetPoint("TOPLEFT", box, "TOPLEFT", mainX, -12)
        unitName:Hide()
        local unitLevel = T.Font(box, "GameFontHighlightSmall", "Elite 72", { 1.0, 0.82, 0.38, 1 })
        unitLevel:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -12)
        unitLevel:Hide()

        local function MakeTrack(parent, width, height, x, y, fillColor)
            local track = T.Panel(parent, nil, { 0.020, 0.024, 0.034, 0.96 }, { 0.10, 0.16, 0.30, 0.65 })
            track:SetSize(width, height)
            track:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            local fill = track:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
            fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
            fill:SetWidth(max(1, width * 0.72))
            fill:SetTexture(WHITE8)
            fill:SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 1)
            track.fill = fill
            return track
        end

        local healthTrack = MakeTrack(box, barW, 14, mainX, -31, { 0.16, 0.78, 0.38, 0.95 })
        local powerTrack = MakeTrack(box, barW, 7, mainX, -50, { 0.24, 0.58, 1.00, 0.95 })
        healthTrack:Hide()
        powerTrack:Hide()

        local castRow = CreateFrame("Frame", nil, box)
        castRow:SetSize(barW, 46)
        castRow:SetPoint("TOPLEFT", box, "TOPLEFT", mainX, -8)
        preview.castRow = castRow
        preview.castRowBase = { parent = box, x = mainX, y = -8 }

        local icon = T.Panel(castRow, nil, { 0.030, 0.050, 0.100, 0.98 }, { 0.16, 0.22, 0.42, 0.75 })
        icon:SetSize(20, 20)
        icon:SetPoint("BOTTOMLEFT", castRow, "BOTTOMLEFT", 0, 0)
        local iconGlow = icon:CreateTexture(nil, "ARTWORK")
        iconGlow:SetPoint("CENTER", icon, "CENTER", 0, 0)
        iconGlow:SetSize(9, 9)
        iconGlow:SetTexture(WHITE8)
        iconGlow:SetVertexColor(0.20, 0.78, 0.94, 0.72)
        local iconTexture = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        iconTexture:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        iconTexture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        iconTexture:SetTexture(136235)
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        preview.iconTexture = iconTexture
        preview.icon = icon

        local castbar = T.Panel(castRow, nil, { 0.018, 0.020, 0.030, 0.98 }, T.colors.borderSoft)
        castbar:SetSize(max(180, barW), 20)
        castbar:SetPoint("CENTER", castRow, "CENTER", 0, 0)
        preview.bar = castbar

        local textLayer = CreateFrame("Frame", nil, castbar)
        textLayer:SetAllPoints(castbar)
        if textLayer.SetFrameLevel and castbar.GetFrameLevel then
            textLayer:SetFrameLevel((castbar:GetFrameLevel() or 1) + 8)
        end
        preview.textLayer = textLayer

        local statusAnchor = CreateFrame("Frame", nil, textLayer)
        statusAnchor:EnableMouse(false)
        preview.statusBar = statusAnchor

        local spell = T.Font(textLayer, "GameFontHighlightSmall", "", T.colors.text)
        spell:SetPoint("LEFT", textLayer, "LEFT", 2, 0)
        spell:SetWidth(max(120, barW - 138))
        spell:SetJustifyH("LEFT")
        preview.spell = spell
        preview.castText = spell

        local time = T.Font(textLayer, "GameFontHighlightSmall", "", T.colors.text)
        time:SetPoint("RIGHT", textLayer, "RIGHT", -2, 0)
        time:SetWidth(82)
        time:SetJustifyH("RIGHT")
        preview.time = time
        preview.timeText = time

        local barBg = castbar:CreateTexture(nil, "BACKGROUND")
        barBg:SetTexture(WHITE8)
        barBg:SetPoint("TOPLEFT", castbar, "TOPLEFT", 1, -1)
        barBg:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", -1, 1)
        barBg:SetVertexColor(0.10, 0.10, 0.10, 0.85)
        preview.barBg = barBg

        local fill = castbar:CreateTexture(nil, "ARTWORK")
        fill:SetTexture(WHITE8)
        fill:SetPoint("TOPLEFT", castbar, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMLEFT", castbar, "BOTTOMLEFT", 1, 1)
        preview.fill = fill

        local empowerColors = {
            { 0.20, 0.90, 0.20, 0.72 },
            { 0.95, 0.80, 0.20, 0.76 },
            { 1.00, 0.55, 0.20, 0.78 },
            { 1.00, 0.25, 0.25, 0.82 },
        }
        preview.empowerBands = {}
        for i = 1, 4 do
            local band = castbar:CreateTexture(nil, "BORDER")
            band:SetTexture(WHITE8)
            band:SetVertexColor(empowerColors[i][1], empowerColors[i][2], empowerColors[i][3], 0.24)
            band:Hide()
            preview.empowerBands[i] = band
        end
        preview.empowerFills = {}
        for i = 1, 4 do
            local seg = castbar:CreateTexture(nil, "ARTWORK")
            seg:SetTexture(WHITE8)
            seg:SetVertexColor(empowerColors[i][1], empowerColors[i][2], empowerColors[i][3], empowerColors[i][4])
            seg:Hide()
            preview.empowerFills[i] = seg
        end

        local latency = castbar:CreateTexture(nil, "OVERLAY")
        latency:SetPoint("TOPRIGHT", castbar, "TOPRIGHT", -1, -1)
        latency:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", -1, 1)
        latency:SetWidth(max(8, (barW - 28) * 0.12))
        latency:SetTexture(WHITE8)
        latency:SetVertexColor(1, 0, 0, 0.25)
        preview.latency = latency

        local spark = castbar:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(4417031)
        spark:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
        spark:SetDesaturated(true)
        spark:SetSize(16, 24)
        spark:SetVertexColor(1, 1, 1, 1)
        spark:SetBlendMode("ADD")
        spark:Hide()
        preview.spark = spark

        preview.ticks = {}
        for i = 1, 4 do
            local tick = castbar:CreateTexture(nil, "OVERLAY")
            tick:SetTexture(WHITE8)
            tick:SetWidth(1)
            tick:SetVertexColor(1, 1, 1, 0.80)
            tick:Hide()
            preview.ticks[i] = tick
        end

        preview.stageTicks = {}
        for i = 1, 3 do
            local tick = castbar:CreateTexture(nil, "OVERLAY")
            tick:SetTexture(WHITE8)
            tick:SetWidth(2)
            tick:SetVertexColor(1, 1, 1, 0.85)
            tick:Hide()

            local flash = castbar:CreateTexture(nil, "OVERLAY")
            flash:SetTexture(WHITE8)
            flash:SetBlendMode("ADD")
            flash:SetVertexColor(1.0, 0.10, 0.10, 1.0)
            flash:SetAlpha(0)
            flash:Hide()
            tick.MSUF_flash = flash
            tick.MSUF_baseWidth = 2
            tick.MSUF_baseAlpha = 0.85

            preview.stageTicks[i] = tick
        end
        local outlineFrame = CreateFrame("Frame", nil, castbar)
        outlineFrame:SetAllPoints(castbar)
        if outlineFrame.SetFrameLevel and castbar.GetFrameLevel then
            outlineFrame:SetFrameLevel((castbar:GetFrameLevel() or 1) + 6)
        end
        outlineFrame.edges = {}
        for _, key in ipairs({ "top", "bottom", "left", "right" }) do
            local edge = outlineFrame:CreateTexture(nil, "OVERLAY")
            edge:SetTexture(WHITE8)
            edge:Hide()
            outlineFrame.edges[key] = edge
        end
        preview.outlineFrame = outlineFrame

        local kick = T.Panel(castRow, nil, { 0.12, 0.72, 0.36, 0.92 }, { 0.40, 1.00, 0.62, 0.70 })
        kick:SetSize(20, 20)
        kick:SetPoint("LEFT", castbar, "RIGHT", 7, 0)
        kick:Hide()
        preview.kick = kick

        function preview:PlayShake(strength, interrupted)
            self.shakeStrength = max(0, tonumber(strength) or tonumber(ReadG("castbarShakeStrength", 8)) or 8)
            self.shakeStart = GetTime and GetTime() or 0
            self.shakeUntil = self.shakeStart + 0.36
            if interrupted then self.interruptUntil = self.shakeStart + 0.58 end
            if self.Refresh then self:Refresh() end
        end

        function preview:SetRowOffset(x)
            local base = self.castRowBase
            self.castRow:ClearAllPoints()
            self.castRow:SetPoint("TOPLEFT", base.parent, "TOPLEFT", base.x + (x or 0), base.y)
        end

        local previewSpellNames = {
            normal = "Glacial Spike of the Infinite Midnight Archive",
            channel = "Mind Flay: Insanity of the Devouring Void",
            empowered = "Fire Breath of the Obsidian Aspect",
        }

        local function SpellText(kind)
            return previewSpellNames[kind or "normal"] or previewSpellNames.normal
        end

        local function CastDuration(kind)
            if kind == "channel" then return 4.5 end
            if kind == "empowered" then return 3.0 end
            return 2.0
        end

        local function FormatPreviewTime(unit, g, current, total)
            local mode = "CURRENT"
            if type(_G.MSUF_GetCastbarTimeFormat) == "function" then
                mode = _G.MSUF_GetCastbarTimeFormat(unit, g)
            end
            if type(_G.MSUF_FormatCastbarTimeText) == "function" then
                return _G.MSUF_FormatCastbarTimeText(mode, current, total) or ""
            end
            return string.format("%.1f", tonumber(current) or 0)
        end

        local function EmpowerBlinkEnabled()
            if type(_G.MSUF_IsEmpowerStageBlinkEnabled) == "function" then
                local ok, enabled = pcall(_G.MSUF_IsEmpowerStageBlinkEnabled)
                if ok then return enabled and true or false end
            end
            return ReadGBool("empowerStageBlink", true)
        end

        local function EmpowerBlinkTime()
            if type(_G.MSUF_GetEmpowerStageBlinkTime) == "function" then
                local ok, value = pcall(_G.MSUF_GetEmpowerStageBlinkTime)
                if ok and tonumber(value) then
                    return max(0.05, min(1.00, tonumber(value)))
                end
            end
            local value = tonumber(ReadG("empowerStageBlinkTime", 0.25)) or 0.25
            return max(0.05, min(1.00, value))
        end

        local function ResolvePreviewReverse(frame, unit, kind, g)
            local isChanneled = kind == "channel" or kind == "empowered"
            frame.unit = unit
            frame.MSUF_unit = unit
            frame._msufBarKey = unit
            frame.MSUF_isChanneled = isChanneled and true or nil
            frame.isEmpower = (kind == "empowered") and true or nil

            local direction = (g and g.castbarFillDirection) or ReadG("castbarFillDirection", "RTL")
            if direction == "LEFT" then direction = "RTL" end
            if direction == "RIGHT" then direction = "LTR" end
            local reverse = direction ~= "LTR"
            if unit == "target" and ((g and g.castbarOpositeDirectionTarget == true) or ReadGBool("castbarOpositeDirectionTarget", false)) then
                reverse = not reverse
            end
            if isChanneled and not ((g and g.castbarUnifiedDirection == true) or ReadGBool("castbarUnifiedDirection", false)) then
                reverse = not reverse
            end

            return reverse
        end

        local function GlowBlend(r, g, b, progress)
            if not ReadGBool("castbarShowGlow", false) then
                return r, g, b
            end
            local p = max(0, min(1, tonumber(progress) or 0))
            p = p * p
            return r + ((1 - r) * p), g + ((1 - g) * p), b + ((1 - b) * p)
        end

        local function KickReadyKey(unit)
            if unit == "player" then return "kickReadyShowPlayer" end
            if unit == "target" then return "kickReadyShowTarget" end
            if unit == "focus" then return "kickReadyShowFocus" end
            if unit == "boss" then return "kickReadyShowBoss" end
            return nil
        end

        local function ReadColorTable(tbl, dr, dg, db)
            if type(tbl) ~= "table" then return dr, dg, db end
            return tonumber(tbl["1"]) or tonumber(tbl[1]) or dr,
                   tonumber(tbl["2"]) or tonumber(tbl[2]) or dg,
                   tonumber(tbl["3"]) or tonumber(tbl[3]) or db
        end

        local function LayoutOutline(frame, scale)
            local holder = frame and frame.outlineFrame
            local edges = holder and holder.edges
            if not edges then return end

            local thickness = floor((tonumber(ReadG("castbarOutlineThickness", 1)) or 1) + 0.5)
            if thickness < 0 then thickness = 0 end
            if thickness > 12 then thickness = 12 end
            if thickness <= 0 then
                for _, edge in pairs(edges) do edge:Hide() end
                return
            end
            thickness = max(1, floor((thickness * (scale or 1)) + 0.5))

            local gdb = (type(G) == "function" and G()) or {}
            local r = tonumber(gdb.castbarBorderR) or 0
            local gg = tonumber(gdb.castbarBorderG) or 0
            local b = tonumber(gdb.castbarBorderB) or 0
            local a = tonumber(gdb.castbarBorderA) or 1
            local kickKey = KickReadyKey(frame.layoutUnit)
            if kickKey and ReadGBool(kickKey, false) and ReadG("kickReadyStyle", "border") == "border" then
                r, gg, b = ReadColorTable(gdb.kickReadyColor, 0, 1, 0)
                a = 1
            end

            local top, bottom, left, right = edges.top, edges.bottom, edges.left, edges.right
            top:ClearAllPoints()
            top:SetPoint("BOTTOMLEFT", frame.bar, "TOPLEFT", 0, 0)
            top:SetPoint("BOTTOMRIGHT", frame.bar, "TOPRIGHT", 0, 0)
            top:SetHeight(thickness)

            bottom:ClearAllPoints()
            bottom:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("TOPRIGHT", frame.bar, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(thickness)

            left:ClearAllPoints()
            left:SetPoint("TOPRIGHT", frame.bar, "TOPLEFT", 0, thickness)
            left:SetPoint("BOTTOMRIGHT", frame.bar, "BOTTOMLEFT", 0, -thickness)
            left:SetWidth(thickness)

            right:ClearAllPoints()
            right:SetPoint("TOPLEFT", frame.bar, "TOPRIGHT", 0, thickness)
            right:SetPoint("BOTTOMLEFT", frame.bar, "BOTTOMRIGHT", 0, -thickness)
            right:SetWidth(thickness)

            for _, edge in pairs(edges) do
                edge:SetVertexColor(r, gg, b, a)
                edge:Show()
            end
        end

        function preview:Refresh()
            local now = GetTime and GetTime() or 0
            local kind = self.castType or "normal"
            local unit = self.layoutUnit or "player"
            local g = (type(G) == "function" and G()) or {}
            local realW, realH = ReadPreviewCastbarSize(unit, g)
            local showIcon = CastbarShowIcon(unit, g)
            local iconX = ReadCastbarNum(g, unit, "IconOffsetX", "bossCastIconOffsetX", 0)
            local iconY = ReadCastbarNum(g, unit, "IconOffsetY", "bossCastIconOffsetY", 0)
            local iconSize = ReadCastbarNum(g, unit, "IconSize", "bossCastIconSize", realH)
            iconSize = min(128, max(6, iconSize or realH))
            local rowW = max(1, self.castRow:GetWidth())
            local needW = realW
            if showIcon then
                needW = needW + max(0, -(iconX or 0)) + max(0, (iconX or 0) + iconSize - realW)
            end
            local scale = min(1, (rowW - 8) / max(1, needW))
            if scale <= 0 then scale = 1 end
            local function S(v) return floor(((tonumber(v) or 0) * scale) + 0.5) end
            local scw, sch = max(20, S(realW)), max(6, S(realH))
            self.bar:SetSize(scw, sch)
            self.bar:ClearAllPoints()
            self.bar:SetPoint("CENTER", self.castRow, "CENTER", 0, 0)

            local sIcon = max(6, S(iconSize))
            local iconDetached = showIcon and ((unit == "player" and iconX ~= 0) or (unit ~= "player" and (iconX ~= 0 or iconY ~= 0)))
            self.icon:SetShown(showIcon)
            if showIcon then
                self.icon:SetSize(sIcon, sIcon)
                self.icon:ClearAllPoints()
                self.icon:SetPoint("LEFT", self.bar, "LEFT", S(iconX), S(iconY))
            end
            local statusX = (showIcon and not iconDetached) and (sIcon + S(1)) or 0
            local barWLocal = max(1, scw - statusX)
            local barHLocal = max(1, sch - S(2))
            self.statusX, self.statusW, self.statusH, self.statusScale = statusX, barWLocal, barHLocal, scale
            if self.statusBar then
                self.statusBar:ClearAllPoints()
                self.statusBar:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -1)
                self.statusBar:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -1 - barHLocal)
                self.statusBar:SetSize(barWLocal, barHLocal)
            end
            local texture = (_G.MSUF_GetCastbarTexture and _G.MSUF_GetCastbarTexture()) or WHITE8
            local bgTexture = (_G.MSUF_GetCastbarBackgroundTexture and _G.MSUF_GetCastbarBackgroundTexture()) or WHITE8
            local duration = CastDuration(kind)
            local progress = self.progress or 0
            local reverse = ResolvePreviewReverse(self, unit, kind, g)
            local visual = (kind == "channel") and (1 - progress) or progress
            visual = max(0.01, min(1, visual))
            local fillW = max(1, floor(barWLocal * visual + 0.5))

            local ir, ig, ib = 0.20, 0.78, 0.94
            if type(_G.MSUF_ResolveCastbarColors) == "function" then
                local ok, r, g, b = pcall(_G.MSUF_ResolveCastbarColors)
                if ok and r then ir, ig, ib = r, g or ig, b or ib end
            end
            if now < (self.interruptUntil or 0) then
                ir, ig, ib = 0.90, 0.14, 0.20
            end
            ir, ig, ib = GlowBlend(ir, ig, ib, progress)

            if self.bar.SetBackdropBorderColor then
                self.bar:SetBackdropBorderColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], T.colors.borderSoft[4] or 0.7)
                local kickKey = KickReadyKey(unit)
                if kickKey and ReadGBool(kickKey, false) and ReadG("kickReadyStyle", "border") == "border" then
                    self.bar:SetBackdropBorderColor(0.24, 0.86, 0.46, 0.95)
                end
            end
            self.barBg:SetTexture(bgTexture)
            self.barBg:ClearAllPoints()
            self.barBg:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -1)
            self.barBg:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -1 - barHLocal)
            if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
                local br, bg, bb, ba = _G.MSUF_GetCastbarBackgroundColor()
                self.barBg:SetVertexColor(br or 0.10, bg or 0.10, bb or 0.10, ba or 0.85)
            else
                self.barBg:SetVertexColor(0.10, 0.10, 0.10, 0.85)
            end
            LayoutOutline(self, scale)

            local remaining = max(0, (1 - progress) * duration)
            local previewTimeText = FormatPreviewTime(unit, g, remaining, duration)
            local fontPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or _G.STANDARD_TEXT_FONT
            local fontFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
            local tr, tg, tb = 1, 1, 1
            if type(_G.MSUF_GetCastbarTextColor) == "function" then
                tr, tg, tb = _G.MSUF_GetCastbarTextColor()
            end
            local showTime = CastbarShowTime(unit, g)
            local timeW = 0
            self.time:SetShown(showTime)
            if showTime then
                local timeSize = ReadCastbarNum(g, unit, "TimeFontSize", "bossCastTimeFontSize", ReadG("castbarTimeFontSize", ReadG("fontSize", 14)))
                if not timeSize or timeSize <= 0 then timeSize = ReadG("fontSize", 14) end
                local timeSizePx = max(7, S(timeSize))
                if fontPath and self.time.SetFont then self.time:SetFont(fontPath, timeSizePx, fontFlags) end
                self.time:SetText(previewTimeText)
                self.time:SetTextColor(tr or 1, tg or 1, tb or 1, 1)
                local measured = self.time.GetStringWidth and self.time:GetStringWidth() or nil
                timeW = measured and measured > 0 and floor(measured + S(8) + 0.5) or floor(((#previewTimeText) * (timeSizePx * 0.58)) + S(8) + 0.5)
                local minTimeW = max(16, S(24))
                local maxTimeW = max(minTimeW, S(180))
                timeW = max(minTimeW, min(maxTimeW, timeW))
                self.time:SetWidth(timeW)
                self.time:ClearAllPoints()
                local timeX = ReadCastbarNum(g, unit, "TimeOffsetX", "bossCastTimeOffsetX", -2)
                local timeY = ReadCastbarNum(g, unit, "TimeOffsetY", "bossCastTimeOffsetY", 0)
                if unit == "boss" then
                    timeX = -2 + (tonumber(g.bossCastTimeOffsetX) or 0)
                    timeY = tonumber(g.bossCastTimeOffsetY) or 0
                end
                self.time:SetPoint("RIGHT", self.statusBar or self.bar, "RIGHT", S(timeX), S(timeY))
                if self.time.SetJustifyH then self.time:SetJustifyH("RIGHT") end
            else
                self.time:SetText("")
            end
            local showText = CastbarShowText(unit, g)
            self.spell:SetShown(showText)
            if showText then
                local textSize = ReadCastbarNum(g, unit, "SpellNameFontSize", "bossCastSpellNameFontSize", ReadG("castbarSpellNameFontSize", ReadG("fontSize", 14)))
                if not textSize or textSize <= 0 then textSize = ReadG("fontSize", 14) end
                local textSizePx = max(7, S(textSize))
                if fontPath and self.spell.SetFont then self.spell:SetFont(fontPath, textSizePx, fontFlags) end
                self.spell:SetTextColor(tr or 1, tg or 1, tb or 1, 1)
                self.spell:SetText(SpellText(kind))
                self.spell:ClearAllPoints()
                if self.spell.SetMaxLines then self.spell:SetMaxLines(1) end
                if self.spell.SetWordWrap then self.spell:SetWordWrap(false) end
                local textX = ReadCastbarNum(g, unit, "TextOffsetX", "bossCastTextOffsetX", 0)
                local textY = ReadCastbarNum(g, unit, "TextOffsetY", "bossCastTextOffsetY", 0)
                local leftPad = (unit == "boss") and 2 or 4
                local gap = (unit == "boss") and 6 or 4
                local shorteningMode = tonumber(ReadG("castbarSpellNameShortening", 0)) or 0
                if unit == "boss" and g.bossCastSpellNameShortening ~= nil then
                    shorteningMode = tonumber(g.bossCastSpellNameShortening) or shorteningMode
                end

                if shorteningMode > 0 then
                    local maxLen = tonumber(g.castbarSpellNameMaxLen) or tonumber(ReadG("castbarSpellNameMaxLen", 30)) or 30
                    local reservedSpace = tonumber(g.castbarSpellNameReservedSpace) or tonumber(ReadG("castbarSpellNameReservedSpace", 8)) or 8
                    if unit == "boss" then
                        local bossMaxLen = tonumber(g.bossCastSpellNameMaxLen or g.bossCastSpellNameMaxChars or g.bossSpellNameMaxLen)
                        local bossReserved = tonumber(g.bossCastSpellNameReservedSpace or g.bossCastSpellNameReserved or g.bossSpellNameReservedSpace)
                        if bossMaxLen and bossMaxLen > 0 then maxLen = bossMaxLen end
                        if bossReserved and bossReserved > 0 then reservedSpace = bossReserved end
                    end
                    if maxLen <= 0 then maxLen = 12 end
                    if reservedSpace < 0 then reservedSpace = 0 end
                    local avail = barWLocal - (showTime and timeW or 0) - S(reservedSpace) - S(leftPad + 4)
                    if avail < S(20) then avail = S(20) end
                    local estimated = floor((maxLen * (textSizePx * 0.60)) + S(6) + 0.5)
                    if estimated < S(40) then estimated = S(40) end
                    if estimated > S(800) then estimated = S(800) end
                    self.spell:SetPoint("LEFT", self.statusBar or self.bar, "LEFT", S(leftPad + textX), S(textY))
                    self.spell:SetWidth(max(S(20), min(estimated, avail)))
                    if self.spell.SetJustifyH then self.spell:SetJustifyH("LEFT") end
                elseif showTime then
                    self.spell:SetWidth(max(S(20), barWLocal - timeW - S(leftPad + gap + 4)))
                    self.spell:SetPoint("LEFT", self.statusBar or self.bar, "LEFT", S(leftPad + textX), S(textY))
                    self.spell:SetPoint("RIGHT", self.time, "LEFT", -S(gap), 0)
                    if self.spell.SetJustifyH then self.spell:SetJustifyH("LEFT") end
                else
                    self.spell:SetWidth(max(S(20), barWLocal - S(leftPad + 4)))
                    self.spell:SetPoint("LEFT", self.statusBar or self.bar, "LEFT", S(leftPad + textX), S(textY))
                    self.spell:SetPoint("RIGHT", self.statusBar or self.bar, "RIGHT", -S(4), 0)
                    if self.spell.SetJustifyH then self.spell:SetJustifyH("LEFT") end
                end
            else
                self.spell:SetText("")
            end
            self.latency:ClearAllPoints()
            if reverse then
                self.latency:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -1)
                self.latency:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX, -1 - barHLocal)
            else
                self.latency:SetPoint("TOPRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -1)
                self.latency:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -1 - barHLocal)
            end
            self.latency:SetWidth(max(6, floor(barWLocal * 0.12 + 0.5)))
            self.latency:SetShown(unit == "player" and kind ~= "empowered" and ReadGBool("castbarShowLatency", true))
            self.spark:SetShown(ReadGBool("castbarShowSpark", false))
            local kickKey = KickReadyKey(unit)
            self.kick:SetShown(kickKey and ReadGBool(kickKey, false) and ReadG("kickReadyStyle", "border") == "box")
            if self.kick:IsShown() then
                local kickSize = ReadGBool("kickReadyAutoSize", true) and sch or max(8, S(ReadG("kickReadySize", 16)))
                self.kick:SetSize(kickSize, kickSize)
                self.kick:ClearAllPoints()
                self.kick:SetPoint("LEFT", self.bar, "LEFT", statusX + barWLocal + S(7), 0)
            end

            self.fill:SetTexture(texture)
            self.fill:SetVertexColor(ir, ig, ib, 1)
            self.fill:ClearAllPoints()
            if reverse then
                self.fill:SetPoint("TOPRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -1)
                self.fill:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -1 - barHLocal)
            else
                self.fill:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -1)
                self.fill:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX, -1 - barHLocal)
            end
            self.fill:SetWidth(fillW)

            local useEmpowerSegs = kind == "empowered" and ReadGBool("empowerColorStages", true)
            for i = 1, #self.empowerBands do
                self.empowerBands[i]:Hide()
            end
            if useEmpowerSegs then
                for i = 1, 4 do
                    local startPct = (i - 1) / 4
                    local endPct = i / 4
                    local bandW = max(1, floor(barWLocal * 0.25 + 0.5))
                    local x = floor(barWLocal * startPct + 0.5)
                    if reverse then x = floor(barWLocal * (1 - endPct) + 0.5) end
                    local band = self.empowerBands[i]
                    band:ClearAllPoints()
                    band:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX + x, -1)
                    band:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX + x, -1 - barHLocal)
                    band:SetWidth(bandW)
                    local er, eg, eb = GlowBlend(empowerColors[i][1], empowerColors[i][2], empowerColors[i][3], progress)
                    band:SetVertexColor(er, eg, eb, 0.24)
                    band:Show()
                end
            end
            self.fill:SetShown(not useEmpowerSegs)
            for i = 1, #self.empowerFills do
                self.empowerFills[i]:Hide()
            end
            if useEmpowerSegs then
                for i = 1, 4 do
                    local startPct = (i - 1) / 4
                    local endPct = i / 4
                    local visiblePct = max(0, min(visual, endPct) - startPct)
                    local seg = self.empowerFills[i]
                    if visiblePct > 0 then
                        local segW = max(1, floor(barWLocal * visiblePct + 0.5))
                        local x = floor(barWLocal * startPct + 0.5)
                        if reverse then x = floor(barWLocal * (1 - endPct) + 0.5) end
                        seg:ClearAllPoints()
                        seg:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX + x, -1)
                        seg:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX + x, -1 - barHLocal)
                        seg:SetWidth(segW)
                        local er, eg, eb = GlowBlend(empowerColors[i][1], empowerColors[i][2], empowerColors[i][3], progress)
                        seg:SetVertexColor(er, eg, eb, empowerColors[i][4])
                        seg:Show()
                    end
                end
            end

            self.spark:ClearAllPoints()
            self.spark:SetSize(max(4, S(16)), ReadGBool("castbarSparkOverflow", true) and max(sch, S(realH * 2.1)) or sch)
            self.spark:SetPoint("CENTER", self.bar, "LEFT", reverse and (statusX + barWLocal - fillW) or (statusX + fillW), 0)

            for i = 1, #self.ticks do self.ticks[i]:Hide() end
            if kind == "channel" and ReadGBool("castbarShowChannelTicks", false) then
                local count = 5
                for i = 1, count - 1 do
                    local tick = self.ticks[i]
                    if tick then
                        local x = floor(barWLocal * (i / count) + 0.5)
                        tick:ClearAllPoints()
                        tick:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX + x, -1)
                        tick:SetHeight(barHLocal)
                        tick:Show()
                    end
                end
            end

            local blinkEnabled = false
            local blinkTime = 0.25
            if kind == "empowered" then
                blinkEnabled = EmpowerBlinkEnabled()
                blinkTime = EmpowerBlinkTime()
            end
            local currentStageTick = min(#self.stageTicks, max(0, floor(progress * 4)))
            if kind ~= "empowered" then
                if self._lastEmpowerProgress or self._lastEmpowerStageTick then
                    ResetEmpowerBlinkState(self)
                end
            else
                self._stageFlashStart = self._stageFlashStart or {}
                self._stageFlashUntil = self._stageFlashUntil or {}
                if self._lastEmpowerProgress and progress < (self._lastEmpowerProgress - 0.001) then
                    ResetEmpowerBlinkState(self)
                end
                if blinkEnabled and currentStageTick > 0 and currentStageTick ~= self._lastEmpowerStageTick then
                    self._stageFlashStart[currentStageTick] = now
                    self._stageFlashUntil[currentStageTick] = now + blinkTime
                end
                self._lastEmpowerStageTick = currentStageTick
                self._lastEmpowerProgress = progress
            end

            for i = 1, #self.stageTicks do
                local tick = self.stageTicks[i]
                local flash = tick and tick.MSUF_flash
                if kind == "empowered" then
                    local x = floor(barWLocal * (i / 4) + 0.5)
                    if reverse then x = barWLocal - x end
                    tick:ClearAllPoints()
                    tick:SetPoint("CENTER", self.bar, "TOPLEFT", statusX + x, -1 - floor(barHLocal * 0.5))
                    tick:SetHeight(barHLocal)
                    local flashStart = self._stageFlashStart and self._stageFlashStart[i]
                    local flashUntil = self._stageFlashUntil and self._stageFlashUntil[i]
                    local flashing = blinkEnabled and flashStart and flashUntil and now < flashUntil
                    local baseW = max(1, S(tick.MSUF_baseWidth or 2))
                    local flashTickW = max(baseW, S(4))
                    if flashing then
                        local phase = max(0, min(1, (now - flashStart) / blinkTime))
                        local flashAlpha = max(0, 1 - phase)
                        tick:SetWidth(flashTickW)
                        tick:SetVertexColor(1.0, 0.10, 0.10, 1.0)
                        if flash then
                            flash:ClearAllPoints()
                            flash:SetPoint("CENTER", tick, "CENTER", 0, 0)
                            flash:SetWidth(max(10, S(12)))
                            flash:SetHeight(barHLocal)
                            flash:SetVertexColor(1.0, 0.10, 0.10, 1.0)
                            flash:SetAlpha(flashAlpha)
                            flash:Show()
                        end
                    else
                        tick:SetWidth(baseW)
                        tick:SetVertexColor(1, 1, 1, tick.MSUF_baseAlpha or 0.85)
                        if flash then
                            flash:SetAlpha(0)
                            flash:Hide()
                        end
                    end
                    tick:Show()
                else
                    tick:Hide()
                    if flash then
                        flash:SetAlpha(0)
                        flash:Hide()
                    end
                end
            end

            for key, btn in pairs(typeButtons) do
                if btn.SetActive then btn:SetActive(key == kind) end
            end
            for key, btn in pairs(unitButtons) do
                if btn.SetActive then btn:SetActive(key == unit) end
            end
        end

        box:SetScript("OnUpdate", function(_, elapsed)
            elapsed = tonumber(elapsed) or 0
            preview.progress = (preview.progress or 0) + (elapsed / CastDuration(preview.castType or "normal"))
            if preview.progress > 1 then preview.progress = preview.progress - floor(preview.progress) end

            local now = GetTime and GetTime() or 0
            if now < (preview.shakeUntil or 0) then
                local span = max(0.001, (preview.shakeUntil or now) - (preview.shakeStart or now))
                local t = (now - (preview.shakeStart or now)) / span
                local amp = (preview.shakeStrength or 0) * max(0, 1 - t)
                preview:SetRowOffset(math.sin(t * 42) * amp)
            else
                preview:SetRowOffset(0)
            end
            preview:Refresh()
        end)

        preview:Refresh()
        M.AddRefresher(ctx, function() preview:Refresh() end)
        return preview
    end

    local castPreview = BuildPreview()
    local function RefreshCastPreview()
        if castPreview and castPreview.Refresh then castPreview:Refresh() end
    end
    local function ShakeCastPreview(strength)
        if castPreview and castPreview.PlayShake then castPreview:PlayShake(strength, false) end
    end
    local function ShowEmpoweredPreview()
        if not castPreview then return end
        castPreview.castType = "empowered"
        castPreview.progress = 0.62
        castPreview._stageFlashStart = {}
        castPreview._stageFlashUntil = {}
        castPreview._lastEmpowerStageTick = nil
        castPreview._lastEmpowerProgress = nil
        if castPreview.Refresh then castPreview:Refresh() end
    end
    local function MoveToggle(toggle, parent, x, y, labelWidth)
        W.MoveWidget(toggle, parent, x, y)
        if toggle and toggle._msuf2Label and toggle._msuf2Label.SetWidth then
            toggle._msuf2Label:SetWidth(max(40, tonumber(labelWidth) or 260))
        end
        return toggle
    end

    local behavior = b:CollapsibleSection("castbar_behavior", "Shake & Fill Direction", 196, true)
    local leftX, rightX = 14, 392
    local shake = W.Toggle(behavior, "Shake on interrupt")
    MoveToggle(shake, behavior, leftX, -42, 260)
    M.BindToggle(ctx, shake,
        function() return ReadGBool("castbarInterruptShake", false) end,
        function(v) SetGBool("castbarInterruptShake", v, "MSUF2_CASTBAR_SHAKE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_SHAKE"); RefreshCastPreview() end)

    local strength = W.Slider(behavior, "Shake strength", 0, 30, 1, 300)
    W.MoveWidget(strength, behavior, leftX, -72, 320)
    M.BindSlider(ctx, strength,
        function() return tonumber(ReadG("castbarShakeStrength", 8)) or 8 end,
        function(v)
            local nextValue = floor((tonumber(v) or 8) + 0.5)
            SetG("castbarShakeStrength", nextValue, "MSUF2_CASTBAR_SHAKE_STRENGTH", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_CASTBAR_SHAKE_STRENGTH")
            ShakeCastPreview(nextValue)
        end)

    local unified = W.Toggle(behavior, "Always use fill direction for all casts")
    MoveToggle(unified, behavior, rightX, -42, 360)
    M.BindToggle(ctx, unified,
        function() return ReadGBool("castbarUnifiedDirection", false) end,
        function(v) SetGBool("castbarUnifiedDirection", v, "MSUF2_CASTBAR_UNIFIED_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_UNIFIED_DIRECTION"); RefreshCastPreview() end)

    local direction = W.Dropdown(behavior, "Castbar fill direction", {
        { value = "RTL", text = "Right to left (default)" },
        { value = "LTR", text = "Left to right" },
    }, 260)
    W.MoveWidget(direction, behavior, rightX, -72, 300)
    M.BindDropdown(ctx, direction,
        function() return ReadG("castbarFillDirection", "RTL") end,
        function(v) SetG("castbarFillDirection", v or "RTL", "MSUF2_CASTBAR_FILL_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_FILL_DIRECTION"); RefreshCastPreview() end)

    local opposite = W.Toggle(behavior, "Use opposite fill direction for target")
    MoveToggle(opposite, behavior, rightX, -126, 360)
    M.BindToggle(ctx, opposite,
        function() return ReadGBool("castbarOpositeDirectionTarget", false) end,
        function(v) SetGBool("castbarOpositeDirectionTarget", v, "MSUF2_CASTBAR_TARGET_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_TARGET_DIRECTION"); RefreshCastPreview() end)

    local ticks = W.Toggle(behavior, "Show channel tick lines (5)")
    MoveToggle(ticks, behavior, rightX, -150, 360)
    M.BindToggle(ctx, ticks,
        function() return ReadGBool("castbarShowChannelTicks", false) end,
        function(v) SetGBool("castbarShowChannelTicks", v, "MSUF2_CASTBAR_TICKS", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_TICKS"); RefreshCastPreview() end)

    local gcd = b:CollapsibleSection("castbar_gcd", "GCD Bar", 150, false)
    local syncGCDSubs
    local gcdShow = W.Toggle(gcd, "Show GCD bar for instant casts")
    M.BindToggle(ctx, gcdShow,
        function() return ReadGBool("showGCDBar", false) end,
        function(v)
            SetGBool("showGCDBar", v, "MSUF2_CASTBAR_GCD", { castbar = true, preview = true })
            EnsureCastbars()
            if type(_G.MSUF_SetGCDBarEnabled) == "function" then pcall(_G.MSUF_SetGCDBarEnabled, v) end
            ApplyCastbars("MSUF2_CASTBAR_GCD")
            if syncGCDSubs then syncGCDSubs() end
        end)
    local gcdTime = W.Toggle(gcd, "GCD bar: show time text")
    M.BindToggle(ctx, gcdTime,
        function() return ReadGBool("showGCDBarTime", true) end,
        function(v) SetGBool("showGCDBarTime", v, "MSUF2_CASTBAR_GCD_TIME", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_GCD_TIME") end)
    local gcdSpell = W.Toggle(gcd, "GCD bar: show spell name + icon")
    M.BindToggle(ctx, gcdSpell,
        function() return ReadGBool("showGCDBarSpell", true) end,
        function(v) SetGBool("showGCDBarSpell", v, "MSUF2_CASTBAR_GCD_SPELL", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_GCD_SPELL") end)
    syncGCDSubs = function()
        SetControlsEnabled({ gcdTime, gcdSpell }, ReadGBool("showGCDBar", false))
    end
    M.AddRefresher(ctx, syncGCDSubs)
    syncGCDSubs()

    local textures = b:CollapsibleSection("castbar_textures", "Textures & Outline", 220, false)
    local texLeftX, texRightX = 14, 392
    local tex = W.Dropdown(textures, "Castbar texture", function() return TextureValues(nil) end, 280)
    W.MoveWidget(tex, textures, texLeftX, -42, 300)
    M.BindDropdown(ctx, tex,
        function() return ReadG("castbarTexture", "Blizzard") end,
        function(v) SetG("castbarTexture", v or "Blizzard", "MSUF2_CASTBAR_TEXTURE", { castbar = true, preview = true }); ApplyCastbarTextures("MSUF2_CASTBAR_TEXTURE"); RefreshCastPreview() end)
    local bgTex = W.Dropdown(textures, "Castbar background texture", function() return TextureValues(nil) end, 280)
    W.MoveWidget(bgTex, textures, texLeftX, -96, 300)
    M.BindDropdown(ctx, bgTex,
        function()
            local v = ReadG("castbarBackgroundTexture", nil)
            if type(v) ~= "string" or v == "" then v = ReadG("castbarTexture", "Blizzard") end
            return v
        end,
        function(v) SetG("castbarBackgroundTexture", v or "Blizzard", "MSUF2_CASTBAR_BG_TEXTURE", { castbar = true, preview = true }); ApplyCastbarTextures("MSUF2_CASTBAR_BG_TEXTURE"); RefreshCastPreview() end)
    local outline = W.Slider(textures, "Outline thickness", 0, 6, 1, 300)
    W.MoveWidget(outline, textures, texRightX, -42, 320)
    M.BindSlider(ctx, outline,
        function() return tonumber(ReadG("castbarOutlineThickness", 1)) or 1 end,
        function(v)
            SetG("castbarOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_CASTBAR_OUTLINE", { castbar = true, preview = true })
            Call("MSUF_ApplyCastbarOutlineToAll", true)
            ApplyCastbarTextures("MSUF2_CASTBAR_OUTLINE")
            RefreshCastPreview()
        end)
    for i, spec in ipairs({
        { "castbarShowGlow", "Show castbar glow effect", false, "MSUF2_CASTBAR_GLOW" },
        { "castbarShowLatency", "Show latency indicator", true, "MSUF2_CASTBAR_LATENCY" },
        { "castbarShowSpark", "Show spark (leading edge highlight)", false, "MSUF2_CASTBAR_SPARK" },
        { "castbarSparkOverflow", "Spark extends beyond bar", true, "MSUF2_CASTBAR_SPARK_OVERFLOW" },
    }) do
        local toggle = W.Toggle(textures, spec[2])
        MoveToggle(toggle, textures, texRightX, -96 - ((i - 1) * 24), 360)
        M.BindToggle(ctx, toggle,
            function() return ReadGBool(spec[1], spec[3]) end,
            function(v) SetGBool(spec[1], v, spec[4], { castbar = true, preview = true }); ApplyCastbarTextures(spec[4]); RefreshCastPreview() end)
    end

    local empowered = b:CollapsibleSection("castbar_empowered", "Empowered Casts", 130, false)
    local empoweredLeftX, empoweredRightX = 14, 392
    local syncEmpowered
    local empColor = W.Toggle(empowered, "Add color to stages (Empowered casts)")
    MoveToggle(empColor, empowered, empoweredLeftX, -42, 300)
    M.BindToggle(ctx, empColor,
        function() return ReadGBool("empowerColorStages", true) end,
        function(v) SetGBool("empowerColorStages", v, "MSUF2_CASTBAR_EMPOWER_COLOR", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_COLOR"); ShowEmpoweredPreview() end)
    local empBlink = W.Toggle(empowered, "Add stage blink (Empowered casts)")
    MoveToggle(empBlink, empowered, empoweredLeftX, -68, 300)
    M.BindToggle(ctx, empBlink,
        function() return ReadGBool("empowerStageBlink", true) end,
        function(v)
            SetGBool("empowerStageBlink", v, "MSUF2_CASTBAR_EMPOWER_BLINK", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_CASTBAR_EMPOWER_BLINK")
            ShowEmpoweredPreview()
            if syncEmpowered then syncEmpowered() end
        end)
    local blinkTime = W.Slider(empowered, "Stage blink time (sec)", 0.05, 1.00, 0.01, 300)
    W.MoveWidget(blinkTime, empowered, empoweredRightX, -42, 320)
    M.BindSlider(ctx, blinkTime,
        function() return tonumber(ReadG("empowerStageBlinkTime", 0.25)) or 0.25 end,
        function(v) SetG("empowerStageBlinkTime", tonumber(v) or 0.25, "MSUF2_CASTBAR_EMPOWER_TIME", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_TIME"); ShowEmpoweredPreview() end)
    syncEmpowered = function()
        SetControlsEnabled({ blinkTime }, ReadGBool("empowerStageBlink", true))
    end
    M.AddRefresher(ctx, syncEmpowered)
    syncEmpowered()

    local text = b:CollapsibleSection("castbar_name_shortening", "Name Shortening", 154, false)
    local textLeftX, textRightX = 14, 392
    local shorten = W.SwitchAt(text, "Spell name shortening", textLeftX, -42, 260)
    local syncNameShortening
    local function NameShorteningEnabled()
        return (tonumber(ReadG("castbarSpellNameShortening", 0)) or 0) == 1
    end
    M.BindToggle(ctx, shorten,
        NameShorteningEnabled,
        function(v)
            local nextValue = v and 1 or 0
            SetG("castbarSpellNameShortening", nextValue, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_CASTBAR_NAME_SHORTEN")
            RefreshCastPreview()
            if syncNameShortening then syncNameShortening() end
        end)

    local maxLen = W.Slider(text, "Max name length", 6, 30, 1, 300)
    W.MoveWidget(maxLen, text, textRightX, -42, 320)
    M.BindSlider(ctx, maxLen,
        function() return tonumber(ReadG("castbarSpellNameMaxLen", 30)) or 30 end,
        function(v) SetG("castbarSpellNameMaxLen", floor((tonumber(v) or 30) + 0.5), "MSUF2_CASTBAR_NAME_MAX", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_MAX"); RefreshCastPreview() end)
    local reserved = W.Slider(text, "Reserved space", 0, 30, 1, 300)
    W.MoveWidget(reserved, text, textRightX, -96, 320)
    M.BindSlider(ctx, reserved,
        function() return tonumber(ReadG("castbarSpellNameReservedSpace", 8)) or 8 end,
        function(v) SetG("castbarSpellNameReservedSpace", floor((tonumber(v) or 8) + 0.5), "MSUF2_CASTBAR_NAME_RESERVED", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_RESERVED"); RefreshCastPreview() end)
    syncNameShortening = function()
        SetControlsEnabled({ maxLen, reserved }, NameShorteningEnabled())
    end
    M.AddRefresher(ctx, syncNameShortening)
    syncNameShortening()

    local focusKick = b:CollapsibleSection("castbar_focus_kick", "Focus Kick", 326, false)
    local focusHint = W.Text(focusKick, "Track interrupts on your focus without showing the focus castbar.", 14, -38, (focusKick._msuf2Width or ctx.width or 720) - 28, T.colors.muted)
    if focusHint and focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    focusKick._msuf2CursorY = -68
    local focusLeftX, focusRightX = 14, 392
    local syncFocusKick
    local focusEnable = W.SwitchAt(focusKick, "Focus interrupt tracker", focusLeftX, -74, 260)
    M.BindToggle(ctx, focusEnable,
        function() return ReadGBool("enableFocusKickIcon", false) end,
        function(v)
            SetGBool("enableFocusKickIcon", v, "MSUF2_FOCUS_KICK_ENABLE", { castbar = true, preview = true })
            Call("MSUF_UpdateFocusKickIconOptions")
            if not v then Call("MSUF_FocusKick_SetPreviewEnabled", false) end
            if syncFocusKick then syncFocusKick() end
        end)
    local focusPreview = W.Toggle(focusKick, "Show on-screen preview")
    MoveToggle(focusPreview, focusKick, focusLeftX, -100, 300)
    M.BindToggle(ctx, focusPreview,
        function()
            local fn = _G.MSUF_FocusKick_IsPreviewEnabled
            return type(fn) == "function" and fn() or false
        end,
        function(v) Call("MSUF_FocusKick_SetPreviewEnabled", v and true or false) end)
    local focusW = W.Slider(focusKick, "Width", 16, 128, 1, 300)
    W.MoveWidget(focusW, focusKick, focusRightX, -74, 320)
    M.BindSlider(ctx, focusW,
        function() return tonumber(ReadG("focusKickIconWidth", 40)) or 40 end,
        function(v) SetG("focusKickIconWidth", floor((tonumber(v) or 40) + 0.5), "MSUF2_FOCUS_KICK_WIDTH", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusH = W.Slider(focusKick, "Height", 16, 128, 1, 300)
    W.MoveWidget(focusH, focusKick, focusRightX, -128, 320)
    M.BindSlider(ctx, focusH,
        function() return tonumber(ReadG("focusKickIconHeight", 40)) or 40 end,
        function(v) SetG("focusKickIconHeight", floor((tonumber(v) or 40) + 0.5), "MSUF2_FOCUS_KICK_HEIGHT", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusText = W.Slider(focusKick, "Text size", 8, 24, 1, 300)
    W.MoveWidget(focusText, focusKick, focusRightX, -182, 320)
    M.BindSlider(ctx, focusText,
        function()
            local v = tonumber(ReadG("focusKickTextSize", nil))
            if v then return v end
            return (tonumber(ReadG("focusKickIconHeight", 40)) or 40) >= 48 and 14 or 12
        end,
        function(v)
            SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
            Call("MSUF_FocusKick_ApplyTimeTextFont")
            Call("MSUF_UpdateFocusKickIconOptions")
        end)
    local focusX = W.Slider(focusKick, "X offset", -500, 500, 1, 300)
    W.MoveWidget(focusX, focusKick, focusLeftX, -150, 320)
    M.BindSlider(ctx, focusX,
        function() return tonumber(ReadG("focusKickIconOffsetX", 300)) or 300 end,
        function(v) SetG("focusKickIconOffsetX", floor((tonumber(v) or 0) + 0.5), "MSUF2_FOCUS_KICK_X", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusY = W.Slider(focusKick, "Y offset", -500, 500, 1, 300)
    W.MoveWidget(focusY, focusKick, focusLeftX, -204, 320)
    M.BindSlider(ctx, focusY,
        function() return tonumber(ReadG("focusKickIconOffsetY", 0)) or 0 end,
        function(v) SetG("focusKickIconOffsetY", floor((tonumber(v) or 0) + 0.5), "MSUF2_FOCUS_KICK_Y", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local resetFocus = W.Button(focusKick, "Reset Position", 150)
    W.MoveWidget(resetFocus, focusKick, focusLeftX, -258)
    resetFocus:SetScript("OnClick", function()
        SetG("focusKickIconOffsetX", 300, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        SetG("focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        Call("MSUF_UpdateFocusKickIconOptions")
        if ctx.refreshers then
            for i = 1, #ctx.refreshers do
                local fn = ctx.refreshers[i]
                if type(fn) == "function" then pcall(fn) end
            end
        end
    end)
    syncFocusKick = function()
        SetControlsEnabled({ focusPreview, focusW, focusH, focusText, focusX, focusY, resetFocus }, ReadGBool("enableFocusKickIcon", false))
    end
    M.AddRefresher(ctx, syncFocusKick)
    syncFocusKick()

    local kick = b:CollapsibleSection("castbar_interrupt_ready", "Interrupt Ready Indicator", 360, false)
    W.Text(kick, "Shows a colored indicator on castbars when your interrupt is ready or on cooldown.", 14, -38, ctx.width - 28, T.colors.muted)
    local kickLeftX, kickRightX = 14, 392
    W.LabelAt(kick, "Castbars", kickLeftX, -70, 160, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(kick, "Appearance", kickRightX, -70, 160, "GameFontNormalSmall", T.colors.accent)
    local syncKickReady
    for i, spec in ipairs({
        { "kickReadyShowTarget", "Show on Target castbar" },
        { "kickReadyShowFocus", "Show on Focus castbar" },
        { "kickReadyShowBoss", "Show on Boss castbars" },
    }) do
        local toggle = W.Toggle(kick, spec[2])
        MoveToggle(toggle, kick, kickLeftX, -88 - ((i - 1) * 26), 300)
        M.BindToggle(ctx, toggle,
            function() return ReadGBool(spec[1], false) end,
            function(v)
                SetGBool(spec[1], v, "MSUF2_KICK_READY_ENABLE", { castbar = true, preview = true })
                ApplyCastbars("MSUF2_KICK_READY_ENABLE")
                RefreshCastPreview()
                if syncKickReady then syncKickReady() end
            end)
    end
    local style = W.Dropdown(kick, "Indicator style", {
        { value = "border", text = "Castbar border" },
        { value = "box", text = "Color box next to cast" },
    }, 260)
    W.MoveWidget(style, kick, kickRightX, -88, 300)
    M.BindDropdown(ctx, style,
        function() return ReadG("kickReadyStyle", "border") end,
        function(v) SetG("kickReadyStyle", v or "border", "MSUF2_KICK_READY_STYLE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_STYLE"); RefreshCastPreview() end)
    local size = W.Slider(kick, "Indicator size", 8, 32, 1, 300)
    W.MoveWidget(size, kick, kickRightX, -142, 320)
    M.BindSlider(ctx, size,
        function() return tonumber(ReadG("kickReadySize", 16)) or 16 end,
        function(v) SetG("kickReadySize", floor((tonumber(v) or 16) + 0.5), "MSUF2_KICK_READY_SIZE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_SIZE"); RefreshCastPreview() end)
    local auto = W.Toggle(kick, "Auto-size to castbar height")
    MoveToggle(auto, kick, kickRightX, -196, 360)
    M.BindToggle(ctx, auto,
        function() return ReadGBool("kickReadyAutoSize", true) end,
        function(v)
            SetGBool("kickReadyAutoSize", v, "MSUF2_KICK_READY_AUTO", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_KICK_READY_AUTO")
            RefreshCastPreview()
            if syncKickReady then syncKickReady() end
        end)
    local colorHint = W.Text(kick, "Ready / cooldown colors: Colors menu > Interrupt Ready Indicator", kickRightX, -228, 370, T.colors.muted)
    W.LabelAt(kick, "Placement", kickLeftX, -178, 160, "GameFontNormalSmall", T.colors.accent)
    local anchor = W.Dropdown(kick, "Anchor", {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "TOP", text = "Top" },
        { value = "BOTTOM", text = "Bottom" },
    }, 180)
    W.MoveWidget(anchor, kick, kickLeftX, -196, 260)
    M.BindDropdown(ctx, anchor,
        function() return ReadG("kickReadyAnchor", "RIGHT") end,
        function(v) SetG("kickReadyAnchor", v or "RIGHT", "MSUF2_KICK_READY_ANCHOR", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_ANCHOR") end)
    local offX = W.Slider(kick, "X offset", -50, 50, 1, 300)
    W.MoveWidget(offX, kick, kickLeftX, -250, 320)
    M.BindSlider(ctx, offX,
        function() return tonumber(ReadG("kickReadyOffsetX", 4)) or 4 end,
        function(v) SetG("kickReadyOffsetX", floor((tonumber(v) or 4) + 0.5), "MSUF2_KICK_READY_X", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_X") end)
    local offY = W.Slider(kick, "Y offset", -50, 50, 1, 300)
    W.MoveWidget(offY, kick, kickLeftX, -304, 320)
    M.BindSlider(ctx, offY,
        function() return tonumber(ReadG("kickReadyOffsetY", 0)) or 0 end,
        function(v) SetG("kickReadyOffsetY", floor((tonumber(v) or 0) + 0.5), "MSUF2_KICK_READY_Y", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_Y") end)
    syncKickReady = function()
        local enabled = ReadGBool("kickReadyShowTarget", false) or ReadGBool("kickReadyShowFocus", false) or ReadGBool("kickReadyShowBoss", false)
        local autoOn = ReadGBool("kickReadyAutoSize", true)
        SetControlsEnabled({ style, auto, anchor, offX, offY }, enabled)
        SetControlEnabled(size, enabled and not autoOn)
        SetControlEnabled(colorHint, enabled)
    end
    M.AddRefresher(ctx, syncKickReady)
    syncKickReady()

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_castbar", { title = "MSUF Castbar", build = BuildCastbars, version = 5 })
