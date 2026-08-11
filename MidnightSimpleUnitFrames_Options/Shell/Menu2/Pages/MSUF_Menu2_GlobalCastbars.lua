local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 global Castbars page.
-- Exposes shared castbar backend/visual/text/timing controls and drives a page-local preview.
-- Actual cast/channel state handling is owned by the castbar runtime modules.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList
local CastbarPreview = MSUF.UFPreviewCastbar or {}
local floor = math.floor
local max = math.max
local min = math.min
local C_Timer = M.MenuTimer or _G.C_Timer
local Call, G, ReadG, SetG, ReadGBool, SetGBool, TextureValues, SetControlEnabled, SetControlsEnabled, ApplyCastbars, ControlMeta, RegisterControl = M.Pick(GP, [[Call G ReadG SetG ReadGBool SetGBool TextureValues SetControlEnabled SetControlsEnabled ApplyCastbars ControlMeta RegisterControl]])
local CASTBAR_ACTION_BY_PATH = {
    ["focus_kick.reset_position"] = "reset_focus_kick_position",
}
local function Meta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    resolved.actionKey = resolved.actionKey or CASTBAR_ACTION_BY_PATH[path]
    return ControlMeta("opt_castbar", "global", path, classification, resolved)
end
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local CASTBAR_PREVIEW_UNITS = M.KeySetFromWords "player target focus boss"
local CASTBAR_PREVIEW_TYPES = M.KeySetFromWords "normal channel empowered"
local CASTBAR_PAGE_WORK_DELAY = 0.04
local CASTBAR_PREVIEW_REFRESH_INTERVAL = 1 / 30
local CASTBAR_PREVIEW_ANIMATION_INTERVAL = 1 / 20
local castbarPageWorkPending = {}
local function ScheduleCastbarPageWork(key, delay, fn)
    if type(fn) ~= "function" then return end
    key = key or fn
    if castbarPageWorkPending[key] then return end
    castbarPageWorkPending[key] = fn
    local function Run()
        local cb = castbarPageWorkPending[key]
        castbarPageWorkPending[key] = nil
        if type(cb) == "function" then cb() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or CASTBAR_PAGE_WORK_DELAY, Run)
    else
        Run()
    end
end
local function NormalizeCastbarPreviewUnit(unit)
    unit = tostring(unit or ""):lower()
    if unit == "boss1" or unit == "bosses" or unit == "boss frames" then unit = "boss" end
    return CASTBAR_PREVIEW_UNITS[unit] and unit or "player"
end
local function NormalizeCastbarPreviewType(kind)
    kind = tostring(kind or ""):lower()
    if kind == "channeled" or kind == "channelled" then kind = "channel" end
    if kind == "empower" or kind == "empowerment" then kind = "empowered" end
    return CASTBAR_PREVIEW_TYPES[kind] and kind or "normal"
end
function M.SetCastbarPreviewUnit(unit)
    unit = NormalizeCastbarPreviewUnit(unit)
    M._msuf2CastbarPreviewUnit = unit
    local preview = M._msuf2CastbarPreview
    if preview then
        preview.layoutUnit = unit
        if preview.Refresh then preview:Refresh() end
    end
    -- The out-of-menu castbar preview follows the selected unit while the
    -- castbar page is open (boss borrows the boss frame preview for anchoring).
    if M.activeKey == "opt_castbar" and type(M.RequestBossPagePreviewForKey) == "function" then
        M.RequestBossPagePreviewForKey("opt_castbar", true)
    end
    return true, unit
end
function M.SetCastbarPreviewType(kind, progress)
    -- Preview type changes are local UI state. They simulate normal/channel/empowered casts
    -- without mutating live unit castbar runtime state.
    kind = NormalizeCastbarPreviewType(kind)
    M._msuf2CastbarPreviewType = kind
    local preview = M._msuf2CastbarPreview
    if preview then
        preview.castType = kind
        preview.progress = tonumber(progress) or 0
        preview._stageFlashStart = {}
        preview._stageFlashUntil = {}
        preview._lastEmpowerStageTick = nil
        preview._lastEmpowerProgress = nil
        if preview.Refresh then preview:Refresh() end
    end
    return true, kind
end
function M.PlayCastbarPreviewInterrupt()
    M._msuf2CastbarPreviewInterruptPending = true
    local preview = M._msuf2CastbarPreview
    if preview and preview.PlayShake then
        M._msuf2CastbarPreviewInterruptPending = nil
        preview:PlayShake(tonumber(ReadG("castbarShakeStrength", 8)) or 8, true)
        return true
    end
    return false
end
local function BuildCastbars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Castbar", "Castbar behavior, textures and interrupt indicators.", 72)
    local function ApplyCastbarTextures(reason)
        Call("MSUF_UpdateCastbarTextures_Immediate")
        Call("MSUF_UpdateBossCastbarPreview")
        ApplyCastbars(reason or "MSUF2_CASTBAR_TEXTURES")
    end
    local function BuildPreview()
        local availableW = b.width or ctx.width or 720
        local compactControls = availableW < 694
        local previewHeight = ctx and ctx.hiddenBuild and 72 or (compactControls and 178 or 148)
        local section, _, fixedPreview = W.FixedPreviewSection(ctx, b, {
            title = "Preview",
            height = previewHeight,
        })
        if ctx and ctx.hiddenBuild then
            W.Text(section, "Castbar preview is built when this page is opened.", 14, -42, ctx.width - 28, T.colors.muted)
            return nil, section, fixedPreview
        end
        local sectionW = section._msuf2Width or b.width or ctx.width or 720
        local innerW = max(360, sectionW - 28)
        local preview = {
            castType = NormalizeCastbarPreviewType(M._msuf2CastbarPreviewType or "normal"),
            layoutUnit = NormalizeCastbarPreviewUnit(M._msuf2CastbarPreviewUnit or "player"),
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
        subtitle:SetPoint("TOPLEFT", section.title or section, "BOTTOMLEFT", 0, -4)
        subtitle:SetJustifyH("LEFT")
        subtitle:Hide()
        local function ReadPreviewCastbarSize(unit, g)
            local fallbackW, fallbackH = 271, 18
            if unit == "target" then fallbackW = 272
            elseif unit == "focus" then fallbackW = 175
            elseif unit == "boss" then fallbackW, fallbackH = 176, 12 end
            return CastbarPreview.ReadSize(unit, g,
                tonumber(ReadG("castbarGlobalWidth", fallbackW)) or fallbackW,
                tonumber(ReadG("castbarGlobalHeight", fallbackH)) or fallbackH)
        end
        local function ReadCastbarNum(g, unit, suffix, bossKey, fallback)
            return CastbarPreview.ReadNumber(g, unit, suffix, bossKey, fallback)
        end
        local function CastbarShowIcon(unit, g)
            return CastbarPreview.ShowIcon(unit, g or G())
        end
        local function CastbarShowText(unit, g)
            return CastbarPreview.ShowText(unit, g or G())
        end
        local function CastbarShowTime(unit, g)
            if unit == "boss" then return not (g and g.showBossCastTime == false) end
            local key = (unit == "player" and "showPlayerCastTime")
                or (unit == "target" and "showTargetCastTime")
                or (unit == "focus" and "showFocusCastTime")
            return not (key and g and g[key] == false)
        end
        local function CastbarShowTargetName(unit, g)
            if unit == "target" then return g and g.castbarTargetShowTargetName == true end
            if unit == "focus" then return g and g.castbarFocusShowTargetName == true end
            if unit == "boss" then return g and g.showBossCastTargetName == true end
            return false
        end
        local function PreviewTexture(parent, layer, r, g, b, a, texture, subLevel)
            local tex = parent:CreateTexture(nil, layer, nil, subLevel)
            tex:SetTexture(texture or WHITE8)
            if r then tex:SetVertexColor(r, g, b, a or 1) end
            return tex
        end
        local function PreviewButtonGroup(parent, point, relPoint, x, y, specs, buttonW, gap, onClick, semanticPath)
            local buttons = {}
            local holder = CreateFrame("Frame", nil, parent)
            holder:SetSize((#specs * buttonW) + ((#specs - 1) * gap), 24)
            local anchorX = x + (point:find("LEFT", 1, true) and 8 or -4)
            holder:SetPoint(point, parent, relPoint, anchorX, y - 5)
            for i = 1, #specs do
                local spec = specs[i]
                local btn = T.CenterButtonLabel(T.Button(holder, spec.text, buttonW, 24))
                local value = spec.key
                btn._msuf2AllowCombatClick = true
                btn._msuf2SkipHistoryCheckpoint = true
                btn:SetPoint("LEFT", holder, "LEFT", (i - 1) * (buttonW + gap), 0)
                btn:SetScript("OnClick", function() onClick(value) end)
                RegisterControl(btn, Meta(semanticPath .. ".option." .. tostring(value), "ephemeral"), spec.text, "button")
                buttons[value] = btn
            end
            return buttons, holder
        end
        local unitButtons = PreviewButtonGroup(section, "TOPLEFT", "TOPLEFT", 82, -12, {
            { key = "player", text = "Player" },
            { key = "target", text = "Target" },
            { key = "focus", text = "Focus" },
            { key = "boss", text = "Boss" },
        }, 52, 4, M.SetCastbarPreviewUnit, "preview.unit")
        local buttonGap, interruptW = 6, 90
        local buttonW = compactControls
            and max(68, min(82, floor((sectionW - 132 - (buttonGap * 2)) / 3)))
            or 82
        local typeButtons = PreviewButtonGroup(section,
            compactControls and "TOPLEFT" or "TOPRIGHT",
            compactControls and "TOPLEFT" or "TOPRIGHT",
            compactControls and 8 or -(14 + interruptW + 10),
            compactControls and -42 or -12, {
            { key = "normal", text = "Normal" },
            { key = "channel", text = "Channel" },
            { key = "empowered", text = "Empowered" },
        }, buttonW, buttonGap, M.SetCastbarPreviewType, "preview.cast_type")
        local interrupt = T.CenterButtonLabel(T.SkinDangerButton(T.Button(section, "Interrupt", interruptW, 24)))
        interrupt._msuf2AllowCombatClick = true
        interrupt._msuf2SkipHistoryCheckpoint = true
        interrupt:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, compactControls and -46 or -16)
        interrupt:SetScript("OnClick", function()
            M.PlayCastbarPreviewInterrupt()
        end)
        RegisterControl(interrupt, Meta("preview.interrupt", "ephemeral"), "Interrupt", "button")
        local box = T.Panel(section, nil, { 0.018, 0.022, 0.044, 0.88 }, T.colors.borderSoft)
        box:SetPoint("TOPLEFT", section, "TOPLEFT", 16, compactControls and -82 or -52)
        box:SetSize(innerW, 62)
        local portrait = T.Panel(box, nil, { 0.040, 0.060, 0.120, 0.96 }, { 0.16, 0.22, 0.42, 0.75 })
        portrait:SetSize(52, 52)
        portrait:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -20)
        local portraitGlow = PreviewTexture(portrait, "ARTWORK", 0.45, 0.52, 1.00, 0.45)
        portraitGlow:SetPoint("CENTER", portrait, "CENTER", 0, 8)
        portraitGlow:SetSize(28, 28)
        local portraitBody = PreviewTexture(portrait, "OVERLAY", 0.10, 0.28, 0.34, 0.78)
        portraitBody:SetPoint("BOTTOM", portrait, "BOTTOM", 0, 8)
        portraitBody:SetSize(38, 16)
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
            local fill = PreviewTexture(track, "ARTWORK", fillColor[1], fillColor[2], fillColor[3], fillColor[4])
            fill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
            fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
            fill:SetWidth(max(1, width * 0.72))
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
        local iconGlow = PreviewTexture(icon, "ARTWORK", 0.20, 0.78, 0.94, 0.72)
        iconGlow:SetPoint("CENTER", icon, "CENTER", 0, 0)
        iconGlow:SetSize(9, 9)
        local iconTexture = PreviewTexture(icon, "OVERLAY", nil, nil, nil, nil, 136235, 7)
        iconTexture:SetAllPoints(icon)
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        preview.iconTexture = iconTexture
        preview.icon = icon
        if icon.SetBackdrop then icon:SetBackdrop(nil) end
        local iconOutlineFrame = CreateFrame("Frame", nil, icon, "BackdropTemplate")
        iconOutlineFrame:SetAllPoints(icon)
        if iconOutlineFrame.SetFrameLevel and icon.GetFrameLevel then iconOutlineFrame:SetFrameLevel((icon:GetFrameLevel() or 1) + 6) end
        iconOutlineFrame:Hide()
        preview.iconOutlineFrame = iconOutlineFrame
        local castbar = T.Panel(castRow, nil, { 0.018, 0.020, 0.030, 0.98 }, T.colors.borderSoft)
        castbar:SetSize(max(180, barW), 20)
        castbar:SetPoint("CENTER", castRow, "CENTER", 0, 0)
        if castbar.SetBackdrop then castbar:SetBackdrop(nil) end
        preview.bar = castbar
        local textLayer = CreateFrame("Frame", nil, castbar)
        textLayer:SetAllPoints(castbar)
        if textLayer.SetFrameLevel and castbar.GetFrameLevel then textLayer:SetFrameLevel((castbar:GetFrameLevel() or 1) + 8) end
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
        local castTargetText = T.Font(castRow, "GameFontHighlightSmall", "", { 1, 0.82, 0.20, 1 })
        castTargetText:SetWidth(max(120, barW - 4))
        castTargetText:SetJustifyH("RIGHT")
        castTargetText:Hide()
        preview.castTargetText = castTargetText
        local barBg = PreviewTexture(castbar, "BACKGROUND", 0.10, 0.10, 0.10, 0.85)
        barBg:SetPoint("TOPLEFT", castbar, "TOPLEFT", 1, -1)
        barBg:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", -1, 1)
        preview.barBg = barBg
        local fill = PreviewTexture(castbar, "ARTWORK")
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
            local band = PreviewTexture(castbar, "BORDER", empowerColors[i][1], empowerColors[i][2], empowerColors[i][3], 0.24)
            band:Hide()
            preview.empowerBands[i] = band
        end
        preview.empowerFills = {}
        for i = 1, 4 do
            local seg = PreviewTexture(castbar, "ARTWORK", empowerColors[i][1], empowerColors[i][2], empowerColors[i][3], empowerColors[i][4])
            seg:Hide()
            preview.empowerFills[i] = seg
        end
        local latency = PreviewTexture(castbar, "OVERLAY", 1, 0, 0, 0.25)
        latency:SetPoint("TOPRIGHT", castbar, "TOPRIGHT", -1, -1)
        latency:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", -1, 1)
        latency:SetWidth(max(8, (barW - 28) * 0.12))
        preview.latency = latency
        local spark = PreviewTexture(castbar, "OVERLAY", 1, 1, 1, 1, 4417031)
        spark:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
        spark:SetDesaturated(true)
        spark:SetSize(16, 24)
        spark:SetBlendMode("ADD")
        spark:Hide()
        preview.spark = spark
        preview.ticks = {}
        for i = 1, 4 do
            local tick = PreviewTexture(castbar, "OVERLAY", 1, 1, 1, 0.80)
            tick:SetWidth(1)
            tick:Hide()
            preview.ticks[i] = tick
        end
        preview.stageTicks = {}
        for i = 1, 3 do
            local tick = PreviewTexture(castbar, "OVERLAY", 1, 1, 1, 0.85)
            tick:SetWidth(2)
            tick:Hide()
            local flash = PreviewTexture(castbar, "OVERLAY", 1.0, 0.10, 0.10, 1.0)
            flash:SetBlendMode("ADD")
            flash:SetAlpha(0)
            flash:Hide()
            tick.MSUF_flash = flash
            tick.MSUF_baseWidth = 2
            tick.MSUF_baseAlpha = 0.85
            preview.stageTicks[i] = tick
        end
        local outlineFrame = CreateFrame("Frame", nil, castbar, "BackdropTemplate")
        outlineFrame:SetAllPoints(castbar)
        if outlineFrame.SetFrameLevel and castbar.GetFrameLevel then outlineFrame:SetFrameLevel((castbar:GetFrameLevel() or 1) + 6) end
        outlineFrame:Hide()
        preview.outlineFrame = outlineFrame
        local kick = T.Panel(castRow, nil, { 0.12, 0.72, 0.36, 0.92 }, { 0.40, 1.00, 0.62, 0.70 })
        kick:SetSize(20, 20)
        kick:SetPoint("LEFT", castbar, "RIGHT", 8, 0)
        kick:Hide()
        preview.kick = kick
        function preview:PlayShake(strength, interrupted)
            self.shakeStrength = max(0, tonumber(strength) or tonumber(ReadG("castbarShakeStrength", 8)) or 8)
            self.shakeStart = GetTime and GetTime() or 0
            self.shakeUntil = self.shakeStart + 0.36
            if interrupted then
                local duration = max(0, min(5, tonumber(ReadG("castbarInterruptFeedbackDuration", 0.5)) or 0.5))
                self.interruptUntil = self.shakeStart + duration
            end
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
        local function PreviewSpellText(unit, kind)
            local text = SpellText(kind)
            local shorten = _G.MSUF_ShortenCastbarSpellName
            if type(shorten) ~= "function" then return text end

            preview._spellNameShortenFrame = preview._spellNameShortenFrame or {}
            preview._spellNameShortenFrame.unit = unit == "boss" and "boss1" or unit
            return shorten(preview._spellNameShortenFrame, text)
        end
        local function CastDuration(kind)
            if kind == "channel" then return 4.5 end
            if kind == "empowered" then return 3.0 end
            return 2.0
        end
        local function FormatPreviewTime(unit, g, current, total)
            if type(CastbarPreview.FormatPreviewTime) == "function" then return CastbarPreview.FormatPreviewTime(g or G(), unit, current, total) end
            return string.format("%.1f", tonumber(current) or 0)
        end
        local function EmpowerBlinkEnabled()
            if type(_G.MSUF_IsEmpowerStageBlinkEnabled) == "function" then
                return _G.MSUF_IsEmpowerStageBlinkEnabled() and true or false
            end
            return ReadGBool("empowerStageBlink", true)
        end
        local function EmpowerBlinkTime()
            if type(_G.MSUF_GetEmpowerStageBlinkTime) == "function" then
                local value = tonumber(_G.MSUF_GetEmpowerStageBlinkTime())
                if value then return max(0.05, min(1.00, value)) end
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
            if unit == "target" and ((g and g.castbarOpositeDirectionTarget == true) or ReadGBool("castbarOpositeDirectionTarget", false)) then reverse = not reverse end
            -- Channels keep the cast's anchor; unified direction instead makes
            -- them fill like a cast (see the visual progress computation).
            return reverse
        end
        local function GlowBlend(r, g, b, progress)
            if not ReadGBool("castbarShowGlow", false) then return r, g, b end
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
        local function ResolveUnavailablePreviewColor(gdb)
            if type(_G.MSUF_ResolveInterruptUnavailableCastColor) == "function" then
                local r, g, b = _G.MSUF_ResolveInterruptUnavailableCastColor()
                if r and g and b then return r, g, b end
            end

            gdb = gdb or {}
            local r = tonumber(gdb.castbarInterruptUnavailableR)
            local g = tonumber(gdb.castbarInterruptUnavailableG)
            local b = tonumber(gdb.castbarInterruptUnavailableB)
            if r and g and b then return r, g, b end

            local key = gdb.castbarInterruptUnavailableColor
            local color = key and type(_G.MSUF_GetColorFromKey) == "function" and _G.MSUF_GetColorFromKey(key) or nil
            if color and color.GetRGB then
                r, g, b = color:GetRGB()
                if r and g and b then return r, g, b end
            end

            return 1.0, 0.494117647, 0.137254902
        end
        local function LayoutOutline(frame, scale)
            local holder = frame and frame.outlineFrame
            if not (holder and holder.SetBackdrop) then return 0 end
            local thickness = floor((tonumber(ReadG("castbarOutlineThickness", 1)) or 1) + 0.5)
            if thickness < 0 then thickness = 0 end
            if thickness > 12 then thickness = 12 end
            if thickness <= 0 then
                holder:SetBackdrop(nil)
                holder:Hide()
                frame._outlinePreviewT = 0
                frame._outlinePreviewEdge = 0
                frame._outlinePreviewR, frame._outlinePreviewG, frame._outlinePreviewB, frame._outlinePreviewA = nil, nil, nil, nil
                return 0
            end
            local edgeSize = max(1, floor((thickness * (scale or 1)) + 0.5))
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
            if frame._outlinePreviewT ~= thickness or frame._outlinePreviewEdge ~= edgeSize then
                holder:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = edgeSize,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                holder:SetBackdropColor(0, 0, 0, 0)
                frame._outlinePreviewT = thickness
                frame._outlinePreviewEdge = edgeSize
            end
            if frame._outlinePreviewR ~= r or frame._outlinePreviewG ~= gg or frame._outlinePreviewB ~= b or frame._outlinePreviewA ~= a then
                holder:SetBackdropBorderColor(r, gg, b, a)
                frame._outlinePreviewR, frame._outlinePreviewG, frame._outlinePreviewB, frame._outlinePreviewA = r, gg, b, a
            end
            holder:Show()
            return edgeSize
        end
        local function LayoutIconOutline(frame, scale, unit, gdb)
            local holder = frame and frame.iconOutlineFrame
            local iconFrame = frame and frame.icon
            if not (holder and holder.SetBackdrop and iconFrame) then return end
            local prefix = unit == "player" and "castbarPlayer"
                or unit == "target" and "castbarTarget"
                or unit == "focus" and "castbarFocus"
                or unit == "boss" and "bossCast"
            local thickness = prefix and tonumber(gdb and gdb[prefix .. "IconBorderThickness"]) or 0
            local style = prefix and tostring((gdb and gdb[prefix .. "IconBorderStyle"]) or "NONE"):upper() or "NONE"
            thickness = max(0, min(8, floor((thickness or 0) + 0.5)))
            if thickness <= 0 or style == "NONE" or not iconFrame:IsShown() then
                holder:SetBackdrop(nil)
                holder:Hide()
                frame._iconOutlinePreviewKey = nil
                frame._iconOutlinePreviewColorKey = nil
                return
            end
            local edgeSize = max(1, floor((thickness * (scale or 1)) + 0.5))
            local key = tostring(edgeSize)
            if frame._iconOutlinePreviewKey ~= key then
                holder:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = edgeSize,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                holder:SetBackdropColor(0, 0, 0, 0)
                frame._iconOutlinePreviewKey = key
            end
            local r, gg, b, a = 0, 0, 0, 0.95
            if style == "CASTBAR" then
                r = tonumber(gdb.castbarBorderR) or 0
                gg = tonumber(gdb.castbarBorderG) or 0
                b = tonumber(gdb.castbarBorderB) or 0
                a = tonumber(gdb.castbarBorderA) or 1
            end
            local colorKey = tostring(r) .. "|" .. tostring(gg) .. "|" .. tostring(b) .. "|" .. tostring(a)
            if frame._iconOutlinePreviewColorKey ~= colorKey then
                holder:SetBackdropBorderColor(r, gg, b, a)
                frame._iconOutlinePreviewColorKey = colorKey
            end
            holder:Show()
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
            if showIcon then needW = needW + max(0, -(iconX or 0)) + max(0, (iconX or 0) + iconSize - realW) end
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
            local outlineInset = LayoutOutline(self, scale) or 0
            local statusX = (showIcon and not iconDetached) and (sIcon + S(1)) or outlineInset
            local barWLocal = max(1, scw - statusX - outlineInset)
            local barHLocal = max(1, sch - (outlineInset * 2))
            self.statusX, self.statusW, self.statusH, self.statusScale = statusX, barWLocal, barHLocal, scale
            if self.statusBar then
                self.statusBar:ClearAllPoints()
                self.statusBar:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -outlineInset)
                self.statusBar:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -outlineInset - barHLocal)
                self.statusBar:SetSize(barWLocal, barHLocal)
            end
            local texture = (_G.MSUF_GetCastbarTexture and _G.MSUF_GetCastbarTexture()) or WHITE8
            local bgTexture = (_G.MSUF_GetCastbarBackgroundTexture and _G.MSUF_GetCastbarBackgroundTexture()) or WHITE8
            local duration = CastDuration(kind)
            local progress = self.progress or 0
            local reverse = ResolvePreviewReverse(self, unit, kind, g)
            local unifiedFill = (g and g.castbarUnifiedDirection == true) or ReadGBool("castbarUnifiedDirection", false)
            local visual = (kind == "channel" and not unifiedFill) and (1 - progress) or progress
            visual = max(0.01, min(1, visual))
            local fillW = max(1, floor(barWLocal * visual + 0.5))
            local baseR, baseG, baseB = 0.20, 0.78, 0.94
            if type(_G.MSUF_ResolveCastbarColors) == "function" then
                local r, g, b = _G.MSUF_ResolveCastbarColors()
                if r then baseR, baseG, baseB = r, g or baseG, b or baseB end
            end
            local kickKey = KickReadyKey(unit)
            local kickEnabled = kickKey and ReadGBool(kickKey, false)
            local kickStyle = ReadG("kickReadyStyle", "border")
            local interruptActive = now < (self.interruptUntil or 0)
            if interruptActive then
                local resolveColor = _G.MSUF_ResolveInterruptFeedbackCastColor
                if type(resolveColor) == "function" then
                    baseR, baseG, baseB = resolveColor()
                else
                    baseR, baseG, baseB = 1.0, 0.82, 0.0
                end
            elseif kickEnabled and kickStyle == "fill" then
                baseR, baseG, baseB = ResolveUnavailablePreviewColor(g)
            end
            local ir, ig, ib
            if interruptActive then
                ir, ig, ib = baseR, baseG, baseB
            else
                ir, ig, ib = GlowBlend(baseR, baseG, baseB, progress)
            end
            self.barBg:SetTexture(bgTexture)
            self.barBg:ClearAllPoints()
            self.barBg:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -outlineInset)
            self.barBg:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -outlineInset - barHLocal)
            if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
                local br, bg, bb, ba = _G.MSUF_GetCastbarBackgroundColor()
                self.barBg:SetVertexColor(br or 0.10, bg or 0.10, bb or 0.10, ba or 0.85)
            else
                self.barBg:SetVertexColor(0.10, 0.10, 0.10, 0.85)
            end
            LayoutIconOutline(self, scale, unit, g)
            local remaining = max(0, (1 - progress) * duration)
            local previewTimeText = FormatPreviewTime(unit, g, remaining, duration)
            local fontPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or _G.STANDARD_TEXT_FONT
            local fontFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
            local resolveSafe = _G.MSUF_ResolveSafeFontPath
            if type(resolveSafe) == "function" then
                local gdb = _G.MSUF_DB and _G.MSUF_DB.general
                fontPath = resolveSafe(fontPath, 14, fontFlags, gdb and gdb.fontKey)
            end
            local tr, tg, tb = 1, 1, 1
            if type(_G.MSUF_GetCastbarTextColor) == "function" then tr, tg, tb = _G.MSUF_GetCastbarTextColor() end
            local showTargetName = CastbarShowTargetName(unit, g)
            self.castTargetText:SetShown(showTargetName)
            if showTargetName then
                local targetSize = ReadCastbarNum(g, unit, "TargetNameFontSize", "bossCastTargetNameFontSize", 10)
                if not targetSize or targetSize <= 0 then targetSize = 10 end
                if fontPath and self.castTargetText.SetFont then
                    pcall(self.castTargetText.SetFont, self.castTargetText, fontPath, max(7, S(targetSize)), fontFlags)
                end
                local targetR, targetG, targetB = CastbarPreview.ResolveTargetTextPreviewColor(unit, 1, 0.82, 0.20)
                self.castTargetText:SetTextColor(targetR, targetG, targetB, 1)
                self.castTargetText:SetText(M.Tr("Cleave Training Dummy"))
                local targetX = ReadCastbarNum(g, unit, "TargetNameOffsetX", "bossCastTargetNameOffsetX", 0)
                local targetY = ReadCastbarNum(g, unit, "TargetNameOffsetY", "bossCastTargetNameOffsetY", 1)
                local targetPosition = CastbarPreview.NormalizeTextPosition(
                    CastbarPreview.ReadString(g, unit, "TargetNamePosition", "bossCastTargetNamePosition", "BELOW"), "BELOW")
                local targetJustify = CastbarPreview.NormalizeTextJustify(
                    CastbarPreview.ReadString(g, unit, "TargetNameAlign", "bossCastTargetNameAlign", "RIGHT"), "RIGHT")
                self.castTargetText:SetWidth(max(20, barWLocal - S(4)))
                CastbarPreview.AnchorText(self.castTargetText, self.statusBar or self.bar,
                    targetPosition, targetX, targetY, targetJustify, S)
            else
                self.castTargetText:SetText("")
            end
            local showTime = CastbarShowTime(unit, g)
            local timeW = 0
            self.time:SetShown(showTime)
            if showTime then
                local timeSize = ReadCastbarNum(g, unit, "TimeFontSize", "bossCastTimeFontSize", ReadG("castbarTimeFontSize", ReadG("fontSize", 14)))
                if not timeSize or timeSize <= 0 then timeSize = ReadG("fontSize", 14) end
                local timeSizePx = max(7, S(timeSize))
                if fontPath and self.time.SetFont then pcall(self.time.SetFont, self.time, fontPath, timeSizePx, fontFlags) end
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
                local timePosition = CastbarPreview.NormalizeTextPosition(
                    CastbarPreview.ReadString(g, unit, "TimePosition", "bossCastTimePosition", "RIGHT"), "RIGHT")
                CastbarPreview.AnchorText(self.time, self.statusBar or self.bar,
                    timePosition, timeX, timeY, CastbarPreview.JustifyForTextPosition(timePosition), S)
            else
                self.time:SetText("")
            end
            local showText = CastbarShowText(unit, g)
            self.spell:SetShown(showText)
            if showText then
                local textSize = ReadCastbarNum(g, unit, "SpellNameFontSize", "bossCastSpellNameFontSize", ReadG("castbarSpellNameFontSize", ReadG("fontSize", 14)))
                if not textSize or textSize <= 0 then textSize = ReadG("fontSize", 14) end
                local textSizePx = max(7, S(textSize))
                if fontPath and self.spell.SetFont then pcall(self.spell.SetFont, self.spell, fontPath, textSizePx, fontFlags) end
                self.spell:SetTextColor(tr or 1, tg or 1, tb or 1, 1)
                self.spell:SetText(PreviewSpellText(unit, kind))
                self.spell:ClearAllPoints()
                if self.spell.SetMaxLines then self.spell:SetMaxLines(1) end
                if self.spell.SetWordWrap then self.spell:SetWordWrap(false) end
                local textX = ReadCastbarNum(g, unit, "TextOffsetX", "bossCastTextOffsetX", 0)
                local textY = ReadCastbarNum(g, unit, "TextOffsetY", "bossCastTextOffsetY", 0)
                local textPosition = CastbarPreview.NormalizeTextPosition(
                    CastbarPreview.ReadString(g, unit, "SpellNamePosition", "bossCastSpellNamePosition", "LEFT"), "LEFT")
                local leftPad = (unit == "boss") and 2 or 4
                local gap = (unit == "boss") and 6 or 4
                local shorteningMode = tonumber(ReadG("castbarSpellNameShortening", 0)) or 0
                if unit == "boss" and g.bossCastSpellNameShortening ~= nil then shorteningMode = tonumber(g.bossCastSpellNameShortening) or shorteningMode end
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
                    self.spell:SetWidth(max(S(20), min(estimated, avail)))
                elseif showTime then
                    self.spell:SetWidth(max(S(20), barWLocal - timeW - S(leftPad + gap + 4)))
                else
                    self.spell:SetWidth(max(S(20), barWLocal - S(leftPad + 4)))
                end
                CastbarPreview.AnchorText(self.spell, self.statusBar or self.bar,
                    textPosition, textX, textY, CastbarPreview.JustifyForTextPosition(textPosition), S)
            else
                self.spell:SetText("")
            end
            self.latency:ClearAllPoints()
            if reverse then
                self.latency:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -outlineInset)
                self.latency:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX, -outlineInset - barHLocal)
            else
                self.latency:SetPoint("TOPRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -outlineInset)
                self.latency:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -outlineInset - barHLocal)
            end
            self.latency:SetWidth(max(6, floor(barWLocal * 0.12 + 0.5)))
            self.latency:SetShown(unit == "player" and kind ~= "empowered" and ReadGBool("castbarShowLatency", true))
            local showSpark = ReadGBool("castbarShowSpark", false)
            self.spark:SetShown(showSpark)
            self.kick:SetShown(kickEnabled and kickStyle == "box")
            if self.kick:IsShown() then
                local kickSize = ReadGBool("kickReadyAutoSize", true) and sch or max(8, S(ReadG("kickReadySize", 16)))
                self.kick:SetSize(kickSize, kickSize)
                self.kick:ClearAllPoints()
                self.kick:SetPoint("LEFT", self.bar, "LEFT", statusX + barWLocal + S(8), 0)
            end
            self.fill:SetTexture(texture)
            self.fill:SetVertexColor(ir, ig, ib, 1)
            self.fill:ClearAllPoints()
            if reverse then
                self.fill:SetPoint("TOPRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -outlineInset)
                self.fill:SetPoint("BOTTOMRIGHT", self.bar, "TOPLEFT", statusX + barWLocal, -outlineInset - barHLocal)
            else
                self.fill:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX, -outlineInset)
                self.fill:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX, -outlineInset - barHLocal)
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
                    band:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX + x, -outlineInset)
                    band:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX + x, -outlineInset - barHLocal)
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
                        seg:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX + x, -outlineInset)
                        seg:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", statusX + x, -outlineInset - barHLocal)
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
                for i = 1, count do
                    local tick = self.ticks[i]
                    if tick then
                        local x = floor(barWLocal * (i / (count + 1)) + 0.5)
                        tick:ClearAllPoints()
                        tick:SetPoint("TOPLEFT", self.bar, "TOPLEFT", statusX + x, -outlineInset)
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
                if self._lastEmpowerProgress or self._lastEmpowerStageTick then ResetEmpowerBlinkState(self) end
            else
                self._stageFlashStart = self._stageFlashStart or {}
                self._stageFlashUntil = self._stageFlashUntil or {}
                if self._lastEmpowerProgress and progress < (self._lastEmpowerProgress - 0.001) then ResetEmpowerBlinkState(self) end
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
                    tick:SetPoint("CENTER", self.bar, "TOPLEFT", statusX + x, -outlineInset - floor(barHLocal * 0.5))
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
                local active = key == kind
                if btn.SetActive and btn._msuf2Active ~= active then btn:SetActive(active) end
            end
            for key, btn in pairs(unitButtons) do
                local active = key == unit
                if btn.SetActive and btn._msuf2Active ~= active then btn:SetActive(active) end
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
            preview._animationRefreshElapsed = (tonumber(preview._animationRefreshElapsed) or 0) + elapsed
            if preview._animationRefreshElapsed < CASTBAR_PREVIEW_ANIMATION_INTERVAL then return end
            preview._animationRefreshElapsed = 0
            preview:Refresh()
        end)
        M._msuf2CastbarPreview = preview
        if M._msuf2CastbarPreviewUnit then M.SetCastbarPreviewUnit(M._msuf2CastbarPreviewUnit) end
        if M._msuf2CastbarPreviewType then M.SetCastbarPreviewType(M._msuf2CastbarPreviewType) end
        if M._msuf2CastbarPreviewInterruptPending then M.PlayCastbarPreviewInterrupt() end
        M.TrackMethodRefresh(ctx, preview, "Refresh")
        return preview, section, fixedPreview
    end
    local castPreview, castPreviewSection, fixedPreview = BuildPreview()
    local function RefreshCastPreview() if castPreview and castPreview.Refresh then castPreview:Refresh() end end
    local castPreviewRefreshQueued = false
    local function RequestCastPreviewRefresh()
        if castPreviewRefreshQueued then return end
        castPreviewRefreshQueued = true
        ScheduleCastbarPageWork("MSUF2_CASTBAR_PAGE_PREVIEW", CASTBAR_PREVIEW_REFRESH_INTERVAL, function()
            castPreviewRefreshQueued = false
            RefreshCastPreview()
        end)
    end
    -- Castbar uses the same bounded Preview slot as every other page-level
    -- preview; only the settings sections below it participate in scrolling.
    if castPreviewSection and fixedPreview then fixedPreview.onActivate = RequestCastPreviewRefresh end
    local function ShakeCastPreview(strength) if castPreview and castPreview.PlayShake then castPreview:PlayShake(strength, false) end end
    local function ShowEmpoweredPreview() M.SetCastbarPreviewType("empowered", 0.62) end
    local function MoveToggle(toggle, parent, x, y, labelWidth)
        W.MoveWidget(toggle, parent, x, y)
        if toggle and toggle._msuf2Label and toggle._msuf2Label.SetWidth then toggle._msuf2Label:SetWidth(max(40, tonumber(labelWidth) or 260)) end
        return toggle
    end
    local function BindCastToggle(parent, label, x, y, labelWidth, key, default, reason, afterSet, opts)
        opts = opts or {}
        local toggle = opts.switch and W.SwitchAt(parent, label, x, y, labelWidth) or W.Toggle(parent, label)
        if not opts.switch then MoveToggle(toggle, parent, x, y, labelWidth) end
        M.BindBoolWidget(ctx, toggle,
            opts.getValue or function() return ReadGBool(key, default) end,
            opts.setValue or function(v)
                SetGBool(key, v, reason, { castbar = true, preview = true })
                if afterSet then afterSet(reason, v, true) end
            end,
            opts.meta)
        return toggle
    end
    local function BindCastSlider(parent, label, x, y, width, minValue, maxValue, step, key, default, reason, afterSet, opts)
        opts = opts or {}
        local slider = W.Slider(parent, label, minValue, maxValue, step, 300)
        W.MoveWidget(slider, parent, x, y, width or 320)
        local metadata = {}
        if type(opts.meta) == "table" then for metaKey, value in pairs(opts.meta) do metadata[metaKey] = value end end
        metadata.step, metadata.roundStep = step, not opts.precise
        M.BindNumberWidget(ctx, slider,
            opts.getValue or function() return tonumber(ReadG(key, default)) or default end,
            opts.setValue or function(v)
                local fallback = opts.setDefault ~= nil and opts.setDefault or default
                local nextValue = opts.precise and (tonumber(v) or fallback) or floor((tonumber(v) or fallback) + 0.5)
                SetG(key, nextValue, reason, { castbar = true, preview = true })
                if afterSet then afterSet(reason, nextValue, true) end
            end,
            opts.setDefault ~= nil and opts.setDefault or default, metadata)
        return slider
    end
    local function BindCastDropdown(parent, label, x, y, width, values, key, default, reason, afterSet, opts)
        opts = opts or {}
        local getValue, setValue = opts.getValue, opts.setValue
        if key then
            getValue = getValue or function() return ReadG(key, default) end
            setValue = setValue or function(v)
                local normalize = opts.normalize
                local nextValue = normalize and normalize(v, default) or (v or default)
                SetG(key, nextValue, reason, { castbar = true, preview = true })
                if afterSet then afterSet(reason, nextValue, true) end
            end
        end
        local dropdown = W.Dropdown(parent, label, values, width or 260)
        W.MoveWidget(dropdown, parent, x, y, width or 300)
        M.BindDropdownWidget(ctx, dropdown, getValue, setValue, opts.meta)
        return dropdown
    end
    local CAST_SPEC_OPTION_INDEX = { toggle = 10, slider = 13, dropdown = 11 }
    local function BuildCastControlSpecs(parent, specs, semanticPrefix)
        return M.BuildControlSpecs(specs, {
            toggle = function(spec, i)
                local label, x, y, width, key = spec[2], spec[3], spec[4], spec[5], spec[6]
                local opts = spec[CAST_SPEC_OPTION_INDEX.toggle] or {}
                opts.meta = opts.meta or Meta(semanticPrefix .. "." .. tostring(key or opts.name), opts.classification,
                    opts.classification == "ephemeral" and nil or { settingKey = opts.settingKey or (key and ("general." .. key)) })
                return BindCastToggle(parent, label, x, y, width, key, spec[7], spec[8], opts.afterSet or spec[9], opts), opts.name or key or i
            end,
            slider = function(spec, i)
                local label, x, y, width, key = spec[2], spec[3], spec[4], spec[5], spec[9]
                local opts = spec[CAST_SPEC_OPTION_INDEX.slider] or {}
                opts.meta = opts.meta or Meta(semanticPrefix .. "." .. tostring(key or opts.name), opts.classification,
                    opts.classification == "ephemeral" and nil or { settingKey = opts.settingKey or (key and ("general." .. key)) })
                return BindCastSlider(parent, label, x, y, width, spec[6], spec[7], spec[8], key, spec[10], spec[11], opts.afterSet or spec[12], opts), opts.name or key or i
            end,
            dropdown = function(spec, i)
                local label, x, y, width, key = spec[2], spec[3], spec[4], spec[5], spec[7]
                local opts = spec[CAST_SPEC_OPTION_INDEX.dropdown] or {}
                opts.meta = opts.meta or Meta(semanticPrefix .. "." .. tostring(key or opts.name), opts.classification,
                    opts.classification == "ephemeral" and nil or { settingKey = opts.settingKey or (key and ("general." .. key)) })
                return BindCastDropdown(parent, label, x, y, width, spec[6], key, spec[8], spec[9], opts.afterSet or spec[10], opts), opts.name or key or i
            end,
        })
    end
    local function ApplyCastbarsIfNeeded(reason, _, applyQueued)
        if applyQueued ~= true then ApplyCastbars(reason) end
    end
    local function ApplyAndRefresh(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        RequestCastPreviewRefresh()
    end
    -- Sections route through the shared lazy-section registry: the open
    -- Behavior section defers its content one frame behind its shell, closed
    -- sections build on their first expand, and hidden search-index builds
    -- stay synchronous inside BuildSectionLazy.
    local function LazyCastbarSection(spec)
        local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
        if type(buildLazy) == "function" then return buildLazy(ctx, b, nil, spec) end
        return spec.build(ctx, b)
    end
    local function BuildBehaviorSection(_, secBuilder)
    local behavior = secBuilder:CollapsibleSection("castbar_behavior", "Shake & Fill Direction", 196, true)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(behavior, { "cast.interrupt_feedback" }, {
            title = "Interrupt Feedback Color",
            historySource = "menu:castbars-interrupt-feedback-color",
        })
    end
    local leftX, rightX = 14, 392
    local behaviorControls = BuildCastControlSpecs(behavior, {
        { "toggle", "Shake on interrupt", leftX, -42, 260, "castbarInterruptShake", false, "MSUF2_CASTBAR_SHAKE", ApplyAndRefresh },
        { "slider", "Shake strength", leftX, -72, 320, 0, 30, 1, "castbarShakeStrength", 8, "MSUF2_CASTBAR_SHAKE_STRENGTH", function(reason, value, applyQueued) ApplyCastbarsIfNeeded(reason, nil, applyQueued); ShakeCastPreview(value) end },
        { "slider", "Interrupt display duration (sec)", leftX, -126, 320, 0, 5, 0.1, "castbarInterruptFeedbackDuration", 0.5, "MSUF2_CASTBAR_INTERRUPT_DURATION", nil, {
            precise = true,
            setValue = function(value)
                local duration = max(0, min(5, tonumber(value) or 0.5))
                SetG("castbarInterruptFeedbackDuration", duration, "MSUF2_CASTBAR_INTERRUPT_DURATION", { preview = true })
                M.PlayCastbarPreviewInterrupt()
            end,
        } },
        { "toggle", "Always use fill direction for all casts", rightX, -42, 360, "castbarUnifiedDirection", false, "MSUF2_CASTBAR_UNIFIED_DIRECTION", ApplyAndRefresh },
        { "dropdown", "Castbar fill direction", rightX, -72, 300, VT("RTL", "Right to left (default)", "LTR", "Left to right"), "castbarFillDirection", "RTL", "MSUF2_CASTBAR_FILL_DIRECTION", ApplyAndRefresh },
        { "toggle", "Use opposite fill direction for target", rightX, -126, 360, "castbarOpositeDirectionTarget", false, "MSUF2_CASTBAR_TARGET_DIRECTION", ApplyAndRefresh },
        { "toggle", "Spell-specific channel tick markers", rightX, -150, 360, "castbarShowChannelTicks", false, "MSUF2_CASTBAR_TICKS", ApplyAndRefresh },
    }, "behavior")
    if M.AddTooltip then
        M.AddTooltip(behaviorControls.castbarShowChannelTicks,
            "Spell-specific channel tick markers",
            "Shows tick separators on the Player castbar while channeling.\n\nSupported spells use their actual tick count, including supported talent and channel-duration changes. Unsupported channels keep five evenly spaced fallback lines. Custom channel tick settings override the automatic layout.\n\nThe markers are event-driven and add no recurring channel polling.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
    end
    end
    LazyCastbarSection({ sectionId = "castbar_behavior", title = "Shake & Fill Direction", height = 196, defaultOpen = true, build = BuildBehaviorSection })
    local function BuildFilterSection(_, secBuilder)
    local filters = secBuilder:CollapsibleSection("castbar_filters", "Filtering & Feedback", 110, false)
    local filterLeftX = 14
    local filterControls = BuildCastControlSpecs(filters, {
        { "toggle", "Hide profession casts", filterLeftX, -46, 320, "castbarHideTradeSkills", false, "MSUF2_CASTBAR_HIDE_TRADESKILLS", ApplyAndRefresh },
        { "toggle", "Show cast pushback", filterLeftX, -72, 320, "castbarShowPushback", false, "MSUF2_CASTBAR_PUSHBACK", ApplyAndRefresh },
    }, "filters")
    if M.AddTooltip then
        M.AddTooltip(filterControls.castbarHideTradeSkills,
            "Hide profession casts",
            "Keeps crafting and gathering casts off every castbar.\n\nThe profession flag is never a protected value, so this filter also holds for units whose spell data is restricted in PvP.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
        M.AddTooltip(filterControls.castbarShowPushback,
            "Show cast pushback",
            "Appends the delay a cast has accumulated to the spell name, for example \"Fireball +0.4\".\n\nThe delay is read once per cast from the same event that starts the bar.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
    end
    end
    LazyCastbarSection({ sectionId = "castbar_filters", title = "Filtering & Feedback", height = 110, build = BuildFilterSection })
    local function BuildGCDSection(_, secBuilder)
    local gcd = secBuilder:CollapsibleSection("castbar_gcd", "GCD Bar", 148, false)
    local gcdLeftX = 14
    local syncGCD
    local gcdControls = BuildCastControlSpecs(gcd, {
        { "toggle", "Show GCD bar for instant casts", gcdLeftX, -46, 300, "showGCDBar", false, "MSUF2_CASTBAR_GCD", nil, { switch = true,
            afterSet = function(_, enabled)
                Call("MSUF_SetGCDBarEnabled", enabled and true or false)
                if syncGCD then syncGCD() end
            end } },
        { "toggle", "GCD bar: show time text", gcdLeftX, -78, 300, "showGCDBarTime", true, "MSUF2_CASTBAR_GCD_TIME" },
        { "toggle", "GCD bar: show spell name + icon", gcdLeftX, -104, 300, "showGCDBarSpell", true, "MSUF2_CASTBAR_GCD_SPELL" },
    }, "gcd")
    if M.AddTooltip then
        M.AddTooltip(gcdControls.showGCDBar,
            "Show GCD bar for instant casts",
            "Runs a short castbar for the global cooldown whenever an instant spell triggers it.\n\nThe fill and time text are driven natively by the client from the real (haste-scaled) GCD duration - no per-frame addon work while the bar runs. A real cast, channel or empower always takes priority.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
    end
    syncGCD = function()
        SetControlsEnabled({ gcdControls.showGCDBarTime, gcdControls.showGCDBarSpell }, ReadGBool("showGCDBar", false))
    end
    M.TrackRefresh(ctx, syncGCD)
    end
    LazyCastbarSection({ sectionId = "castbar_gcd", title = "GCD Bar", height = 148, build = BuildGCDSection })
    local function BuildTexturesSection(_, secBuilder)
    local textures = secBuilder:CollapsibleSection("castbar_textures", "Textures & Outline", 220, false)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(textures, {
            "cast.interruptible", "cast.non_interruptible", "cast.background", "cast.border",
        }, {
            title = "Castbar Colors",
            historySource = "menu:castbars-texture-colors",
        })
    end
    local texLeftX, texRightX = 14, 392
    local function ApplyTexturesAndPreview(reason, _, applyQueued)
        if applyQueued ~= true then ApplyCastbarTextures(reason) end
        RequestCastPreviewRefresh()
    end
    BuildCastControlSpecs(textures, {
        { "dropdown", "Castbar texture", texLeftX, -42, 300, function() return TextureValues(nil) end, "castbarTexture", "Blizzard", "MSUF2_CASTBAR_TEXTURE", ApplyTexturesAndPreview },
        { "dropdown", "Castbar background texture", texLeftX, -96, 300, function() return TextureValues(nil) end, "castbarBackgroundTexture", "Blizzard", "MSUF2_CASTBAR_BG_TEXTURE", ApplyTexturesAndPreview, {
            getValue = function()
                local v = ReadG("castbarBackgroundTexture", nil)
                return (type(v) == "string" and v ~= "") and v or ReadG("castbarTexture", "Blizzard")
            end } },
        { "slider", "Outline thickness", texRightX, -42, 320, 0, 6, 1, "castbarOutlineThickness", 1, "MSUF2_CASTBAR_OUTLINE", ApplyTexturesAndPreview },
        { "toggle", "Show castbar glow effect", texRightX, -96, 360, "castbarShowGlow", false, "MSUF2_CASTBAR_GLOW", ApplyTexturesAndPreview },
        { "toggle", "Show latency indicator", texRightX, -120, 360, "castbarShowLatency", true, "MSUF2_CASTBAR_LATENCY", ApplyTexturesAndPreview },
        { "toggle", "Show spark (leading edge highlight)", texRightX, -144, 360, "castbarShowSpark", false, "MSUF2_CASTBAR_SPARK", ApplyTexturesAndPreview },
        { "toggle", "Spark extends beyond bar", texRightX, -168, 360, "castbarSparkOverflow", true, "MSUF2_CASTBAR_SPARK_OVERFLOW", ApplyTexturesAndPreview },
    }, "textures")
    end
    LazyCastbarSection({ sectionId = "castbar_textures", title = "Textures & Outline", height = 220, build = BuildTexturesSection })
    local function BuildEmpoweredSection(_, secBuilder)
    local empowered = secBuilder:CollapsibleSection("castbar_empowered", "Empowered Casts", 130, false)
    local empoweredLeftX, empoweredRightX = 14, 392
    local syncEmpowered
    local function ApplyEmpoweredPreview(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        ShowEmpoweredPreview()
    end
    local empoweredControls = BuildCastControlSpecs(empowered, {
        { "toggle", "Add color to stages (Empowered casts)", empoweredLeftX, -42, 300, "empowerColorStages", true, "MSUF2_CASTBAR_EMPOWER_COLOR", ApplyEmpoweredPreview },
        { "toggle", "Add stage blink (Empowered casts)", empoweredLeftX, -68, 300, "empowerStageBlink", true, "MSUF2_CASTBAR_EMPOWER_BLINK", function(reason, value, applyQueued) ApplyEmpoweredPreview(reason, value, applyQueued); if syncEmpowered then syncEmpowered() end end },
        { "slider", "Stage blink time (sec)", empoweredRightX, -42, 320, 0.05, 1.00, 0.01, "empowerStageBlinkTime", 0.25, "MSUF2_CASTBAR_EMPOWER_TIME", ApplyEmpoweredPreview, { precise = true } },
    }, "empowered")
    local blinkControls = { empoweredControls.empowerStageBlinkTime }
    syncEmpowered = function() SetControlsEnabled(blinkControls, ReadGBool("empowerStageBlink", true)) end
    M.TrackRefresh(ctx, syncEmpowered)
    end
    LazyCastbarSection({ sectionId = "castbar_empowered", title = "Empowered Casts", height = 130, build = BuildEmpoweredSection })
    local function BuildNameShorteningSection(_, secBuilder)
    local text = secBuilder:CollapsibleSection("castbar_name_shortening", "Name Shortening", 154, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(text, {
            title = "Cast Text Settings",
            historyLabel = "Cast text color",
            historySource = "menu:castbars-name-text-color",
            textSettings = {
                scope = "shared",
                kind = "cast",
                colorReferences = { "cast.text" },
                colorTitle = "Cast Text Color",
                subtitle = "Castbar font style follows the shared Fonts settings.",
                capabilities = { baseline = false },
            },
        })
    end
    local textLeftX, textRightX = 14, 392
    local syncNameShortening
    local function NameShorteningEnabled() return (tonumber(ReadG("castbarSpellNameShortening", 0)) or 0) == 1 end
    local textControls = BuildCastControlSpecs(text, {
        { "toggle", "Spell name shortening", textLeftX, -42, 260, nil, nil, nil, nil, { name = "shorten", switch = true, getValue = NameShorteningEnabled,
            settingKey = "general.castbarSpellNameShortening",
            setValue = function(v)
                SetG("castbarSpellNameShortening", v and 1 or 0, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true })
                RequestCastPreviewRefresh()
                if syncNameShortening then syncNameShortening() end
            end } },
        { "slider", "Max name length", textRightX, -42, 320, 6, 30, 1, "castbarSpellNameMaxLen", 30, "MSUF2_CASTBAR_NAME_MAX", ApplyAndRefresh },
        { "slider", "Reserved space", textRightX, -96, 320, 0, 30, 1, "castbarSpellNameReservedSpace", 8, "MSUF2_CASTBAR_NAME_RESERVED", ApplyAndRefresh },
    }, "name_shortening")
    local nameShorteningControls = { textControls.castbarSpellNameMaxLen, textControls.castbarSpellNameReservedSpace }
    syncNameShortening = function() SetControlsEnabled(nameShorteningControls, NameShorteningEnabled()) end
    M.TrackRefresh(ctx, syncNameShortening)
    end
    LazyCastbarSection({ sectionId = "castbar_name_shortening", title = "Name Shortening", height = 154, build = BuildNameShorteningSection })
    local function BuildFocusKickSection(_, secBuilder)
    local focusKick = secBuilder:CollapsibleSection("castbar_focus_kick", "Focus Kick", 326, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(focusKick, {
            title = "Focus Kick Text & Colors",
            historyLabel = "Focus Kick color",
            historySource = "menu:castbars-focus-kick-colors",
            textSettings = {
                scope = "shared",
                kind = "cast",
                colorReferences = { "font.global", "cast.kick_ready", "cast.kick_not_ready" },
                colorTitle = "Focus Kick Colors",
                subtitle = "Focus Kick text follows the shared Fonts settings.",
                capabilities = { shadow = false, opacity = false, baseline = false },
            },
        })
    end
    local focusHint = W.Text(focusKick, "Track interrupts on your focus without showing the focus castbar.", 14, -38, (focusKick._msuf2Width or ctx.width or 720) - 28, T.colors.muted)
    if focusHint and focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    focusKick._msuf2CursorY = -68
    local focusLeftX, focusRightX = 14, 392
    local syncFocusKick
    local focusKickOptionsQueued = false
    local focusKickTextFontQueued = false
    local function ApplyFocusKickOptions()
        if focusKickOptionsQueued then return end
        focusKickOptionsQueued = true
        ScheduleCastbarPageWork("MSUF2_FOCUS_KICK_OPTIONS", CASTBAR_PAGE_WORK_DELAY, function()
            focusKickOptionsQueued = false
            Call("MSUF_UpdateFocusKickIconOptions")
        end)
    end
    local function RequestFocusKickTextFont()
        if focusKickTextFontQueued then return end
        focusKickTextFontQueued = true
        ScheduleCastbarPageWork("MSUF2_FOCUS_KICK_TEXT_FONT", CASTBAR_PAGE_WORK_DELAY, function()
            focusKickTextFontQueued = false
            Call("MSUF_FocusKick_ApplyTimeTextFont")
        end)
    end
    local focusControls = BuildCastControlSpecs(focusKick, {
        { "toggle", "Focus interrupt tracker", focusLeftX, -74, 260, "enableFocusKickIcon", false, "MSUF2_FOCUS_KICK_ENABLE", nil, { name = "enable", switch = true,
            afterSet = function(_, enabled)
                Call("MSUF_FocusKickDriver_ForceUpdate")
                Call("MSUF_KickReady_RefreshAll")
                ApplyFocusKickOptions()
                if not enabled then Call("MSUF_FocusKick_SetPreviewEnabled", false) end
                if syncFocusKick then syncFocusKick() end
            end } },
        { "toggle", "Show on-screen preview", focusLeftX, -100, 300, nil, nil, nil, nil, { name = "preview",
            getValue = function()
                local fn = _G.MSUF_FocusKick_IsPreviewEnabled
                return type(fn) == "function" and fn() or false
            end,
            setValue = function(v) Call("MSUF_FocusKick_SetPreviewEnabled", v and true or false) end, classification = "ephemeral" } },
        { "slider", "Width", focusRightX, -74, 320, 16, 128, 1, "focusKickIconWidth", 40, "MSUF2_FOCUS_KICK_WIDTH", ApplyFocusKickOptions, { name = "width" } },
        { "slider", "Height", focusRightX, -128, 320, 16, 128, 1, "focusKickIconHeight", 40, "MSUF2_FOCUS_KICK_HEIGHT", ApplyFocusKickOptions, { name = "height" } },
        { "slider", "Text size", focusRightX, -182, 320, 8, 24, 1, nil, nil, nil, nil, { name = "text",
            settingKey = "general.focusKickTextSize",
            getValue = function()
                local v = tonumber(ReadG("focusKickTextSize", nil))
                if v then return v end
                return (tonumber(ReadG("focusKickIconHeight", 40)) or 40) >= 48 and 14 or 12
            end,
            setValue = function(v)
                SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
                RequestFocusKickTextFont()
                ApplyFocusKickOptions()
            end } },
        { "slider", "X offset", focusLeftX, -150, 320, -500, 500, 1, "focusKickIconOffsetX", 300, "MSUF2_FOCUS_KICK_X", ApplyFocusKickOptions, { name = "x", setDefault = 0 } },
        { "slider", "Y offset", focusLeftX, -204, 320, -500, 500, 1, "focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_Y", ApplyFocusKickOptions, { name = "y" } },
    }, "focus_kick")
    local resetFocus = W.Button(focusKick, "Reset Position", 150)
    W.MoveWidget(resetFocus, focusKick, focusLeftX, -258)
    resetFocus:SetScript("OnClick", function()
        SetG("focusKickIconOffsetX", 300, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        SetG("focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        ApplyFocusKickOptions()
        if M.RequestRefresh then M.RequestRefresh(ctx, "castbars-focus-kick-reset") elseif M.Refresh then M.Refresh(ctx) end
    end)
    RegisterControl(resetFocus, Meta("focus_kick.reset_position", "action"), "Reset Position", "button")
    local focusKickControls = { focusControls.preview, focusControls.width, focusControls.height, focusControls.text, focusControls.x, focusControls.y, resetFocus }
    syncFocusKick = function() SetControlsEnabled(focusKickControls, ReadGBool("enableFocusKickIcon", false)) end
    M.TrackRefresh(ctx, syncFocusKick)
    end
    LazyCastbarSection({ sectionId = "castbar_focus_kick", title = "Focus Kick", height = 326, build = BuildFocusKickSection })
    local function BuildInterruptReadySection(_, secBuilder)
    local kick = secBuilder:CollapsibleSection("castbar_interrupt_ready", "Interrupt Ready Indicator", 328, false)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(kick, function()
            if tostring(ReadG("kickReadyStyle", "border") or "border"):lower() == "fill" then
                return { "cast.interruptible", "cast.interrupt_unavailable" }
            end
            return { "cast.kick_ready", "cast.kick_not_ready" }
        end, {
            title = "Interrupt Ready Colors",
            note = "The shown colors follow the selected indicator style.",
            historySource = "menu:castbars-interrupt-ready-colors",
        })
    end
    local kickLeftX, kickRightX = 14, 392
    W.LabelAt(kick, "Castbars", kickLeftX, -38, 160, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(kick, "Appearance", kickRightX, -38, 160, "GameFontNormalSmall", T.colors.accent)
    local syncKickReady
    local function ApplyKickReady(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        Call("MSUF_KickReady_RefreshAll")
        RequestCastPreviewRefresh()
        if syncKickReady then syncKickReady() end
    end
    local kickControls = BuildCastControlSpecs(kick, {
        { "toggle", "Show on Target castbar", kickLeftX, -56, 300, "kickReadyShowTarget", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "toggle", "Show on Focus castbar", kickLeftX, -82, 300, "kickReadyShowFocus", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "toggle", "Show on Boss castbars", kickLeftX, -108, 300, "kickReadyShowBoss", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "dropdown", "Indicator style", kickRightX, -56, 300, VT("border", "Castbar border", "box", "Color box next to cast", "fill", "Unavailable cast fill"), "kickReadyStyle", "border", "MSUF2_KICK_READY_STYLE", ApplyKickReady },
        { "slider", "Indicator size", kickRightX, -110, 320, 8, 32, 1, "kickReadySize", 16, "MSUF2_KICK_READY_SIZE", ApplyAndRefresh },
        { "toggle", "Auto-size to castbar height", kickRightX, -164, 360, "kickReadyAutoSize", true, "MSUF2_KICK_READY_AUTO", ApplyKickReady },
    }, "interrupt_ready")
    local colorHint = W.Text(kick, "Colors: Colors menu > Castbar Colors", kickRightX, -196, 370, T.colors.muted)
    W.LabelAt(kick, "Placement", kickLeftX, -146, 160, "GameFontNormalSmall", T.colors.accent)
    M.Assign(kickControls, BuildCastControlSpecs(kick, {
        { "dropdown", "Anchor", kickLeftX, -164, 260, VT("RIGHT", "Right", "LEFT", "Left", "TOP", "Top", "BOTTOM", "Bottom"), "kickReadyAnchor", "RIGHT", "MSUF2_KICK_READY_ANCHOR", ApplyCastbarsIfNeeded },
        { "slider", "X offset", kickLeftX, -218, 320, -50, 50, 1, "kickReadyOffsetX", 4, "MSUF2_KICK_READY_X", ApplyCastbarsIfNeeded },
        { "slider", "Y offset", kickLeftX, -272, 320, -50, 50, 1, "kickReadyOffsetY", 0, "MSUF2_KICK_READY_Y", ApplyCastbarsIfNeeded },
    }, "interrupt_ready.placement"))
    local style, size, auto = kickControls.kickReadyStyle, kickControls.kickReadySize, kickControls.kickReadyAutoSize
    local placementControls = { kickControls.kickReadyAnchor, kickControls.kickReadyOffsetX, kickControls.kickReadyOffsetY }
    syncKickReady = function()
        local enabled = ReadGBool("kickReadyShowTarget", false) or ReadGBool("kickReadyShowFocus", false) or ReadGBool("kickReadyShowBoss", false)
        local autoOn = ReadGBool("kickReadyAutoSize", true)
        local isFill = ReadG("kickReadyStyle", "border") == "fill"
        SetControlEnabled(style, enabled)
        SetControlEnabled(auto, enabled and not isFill)
        SetControlEnabled(size, enabled and not isFill and not autoOn)
        SetControlsEnabled(placementControls, enabled and not isFill)
        SetControlEnabled(colorHint, enabled)
    end
    M.TrackRefresh(ctx, syncKickReady)
    end
    LazyCastbarSection({ sectionId = "castbar_interrupt_ready", title = "Interrupt Ready Indicator", height = 328, build = BuildInterruptReadySection })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_castbar", { title = "MSUF Castbar", build = BuildCastbars, version = 6 })
