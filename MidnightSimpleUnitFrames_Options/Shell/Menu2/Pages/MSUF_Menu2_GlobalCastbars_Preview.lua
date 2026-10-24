local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars_Preview.lua")

-- Menu2 global Castbars page preview.
-- Owns the page-local preview state (selected unit/type, replayed interrupt), the
-- deferred page-work scheduler and the animated castbar preview built into the
-- Castbar page's fixed Preview slot. Split from MSUF_Menu2_GlobalCastbars.lua: it
-- loads right before that page and publishes through M.GlobalPage, so the page
-- keeps picking the same names from one table.
-- The cast itself is the engine's castbar scene (root:Castbar), so the preview
-- reads every look setting the way the live castbar does. This file keeps the
-- chrome: unit and cast type selection, the interrupt replay with its shake, the
-- progress loop, the empower stage blink timing and the fit-to-row scale.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
M.GlobalPage = GP
local CastbarPreview = MSUF.UFPreviewCastbar or {}
local floor = math.floor
local max = math.max
local min = math.min
local C_Timer = M.MenuTimer or C_Timer
local G, ReadG, ReadGBool, ControlMeta, RegisterControl = GP.G, GP.ReadG, GP.ReadGBool, GP.ControlMeta, GP.RegisterControl
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
local CASTBAR_PREVIEW_UNITS = M.KeySetFromWords "player target focus boss arena"
-- Empowered casts are an Evoker mechanic, Midnight only: the same client gate as
-- the castbar page's Empowered Casts section (MSUF.Client.HasEmpoweredCasts).
local CASTBAR_PREVIEW_EMPOWERED = MSUF.Client.HasEmpoweredCasts ~= false and MSUF.Client.IsClassic ~= true
local CASTBAR_PREVIEW_TYPES = M.KeySetFromWords(CASTBAR_PREVIEW_EMPOWERED and "normal channel empowered" or "normal channel")
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
    if unit == "arena1" or unit == "arenas" or unit == "arena frames" then unit = "arena" end
    if M.SupportsUnitPage and not M.SupportsUnitPage("uf_" .. unit) then return "player" end
    return CASTBAR_PREVIEW_UNITS[unit] and unit or "player"
end
local function NormalizeCastbarPreviewType(kind)
    kind = tostring(kind or ""):lower()
    if kind == "channeled" or kind == "channelled" then kind = "channel" end
    if kind == "empower" or kind == "empowerment" then kind = "empowered" end
    return CASTBAR_PREVIEW_TYPES[kind] and kind or "normal"
end
local function ResetEmpowerBlinkState(target)
    if not target then return end
    target._blinkStage, target._blinkStart, target._blinkUntil = nil, nil, nil
    target._lastEmpowerStageTick, target._lastEmpowerProgress = nil, nil
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
        ResetEmpowerBlinkState(preview)
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
local function ReadPreviewCastbarSize(unit, g)
    local fallbackW, fallbackH = 271, 18
    if unit == "target" then fallbackW = 272
    elseif unit == "focus" then fallbackW = 175
    elseif unit == "boss" or unit == "arena" then fallbackW, fallbackH = 176, 12 end
    return CastbarPreview.ReadSize(unit, g,
        tonumber(ReadG("castbarGlobalWidth", fallbackW)) or fallbackW,
        tonumber(ReadG("castbarGlobalHeight", fallbackH)) or fallbackH)
end
local function PreviewButtonGroup(parent, specs, buttonW, gap, onClick, semanticPath)
    local buttons, ordered = {}, {}
    local holder = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    local width = 0
    for i = 1, #specs do
        local spec = specs[i]
        local btn = T.CenterButtonLabel(T.Button(holder, spec.text, buttonW, 24))
        T.FitButtonWidth(btn, buttonW)
        local value = spec.key
        btn._msuf2Value, btn._msuf2SegmentChoice = value, true
        ordered[i] = btn
        btn._msuf2AllowCombatClick = true
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("LEFT", holder, "LEFT", width, 0)
        width = width + btn:GetWidth() + gap
        btn:SetScript("OnClick", function() onClick(value) end)
        RegisterControl(btn, Meta(semanticPath .. ".option." .. tostring(value), "ephemeral"), spec.text, "button")
        buttons[value] = btn
    end
    holder:SetSize(max(1, width - gap), 24)
    W.AttachSelectionMotion(holder, ordered, false, semanticPath)
    return buttons, holder
end
local function PreviewPlayShake(self, strength, interrupted)
    self.shakeStrength = max(0, tonumber(strength) or tonumber(ReadG("castbarShakeStrength", 8)) or 8)
    self.shakeStart = GetTime and GetTime() or 0
    self.shakeUntil = self.shakeStart + 0.36
    if interrupted then
        local duration = max(0, min(5, tonumber(ReadG("castbarInterruptFeedbackDuration", 0.5)) or 0.5))
        self.interruptUntil = self.shakeStart + duration
    end
    if self.Refresh then self:Refresh() end
end
local function PreviewSetRowOffset(self, x)
    -- OnUpdate asks every frame; re-anchor only when the shake moved the row.
    x = x or 0
    if self._rowOffset == x then return end
    self._rowOffset = x
    local base = self.castRowBase
    self.castRow:ClearAllPoints()
    self.castRow:SetPoint("TOPLEFT", base.parent, "TOPLEFT", base.x + (x or 0), base.y)
end
local previewSpellNames = {
    normal = "Glacial Spike of the Infinite Midnight Archive",
    channel = "Mind Flay: Insanity of the Devouring Void",
    empowered = "Fire Breath of the Obsidian Aspect",
}
local function CastDuration(kind)
    if kind == "channel" then return 4.5 end
    if kind == "empowered" then return 3.0 end
    return 2.0
end
local PREVIEW_ICON = 136235
local SCENE_UNIT = { boss = "boss1", arena = "arena1" }
local SCENE_KIND = { normal = "CAST", channel = "CHANNEL", empowered = "EMPOWER" }
-- Four equal empower stages: three stage ends inside the cast, the fourth is the hold.
local EMPOWER_STAGES = { 0.75, 1.5, 2.25 }
local KICK_RECOVERY = { 0.4 }
-- The empower castbar module loads on the Mainline TOC only (Midnight and
-- WoW Forever); the Classic clients read the stored settings directly.
-- Both providers load with the core before this addon, so resolve them once:
-- the empowered preview reads them on every animation tick.
local IsEmpowerBlinkEnabled = MSUF.Optional("MSUF_IsEmpowerStageBlinkEnabled")
local GetEmpowerBlinkTime = MSUF.Optional("MSUF_GetEmpowerStageBlinkTime")
local function EmpowerBlinkEnabled()
    if IsEmpowerBlinkEnabled then return IsEmpowerBlinkEnabled() and true or false end
    return ReadGBool("empowerStageBlink", true)
end
local function EmpowerBlinkTime()
    local value = GetEmpowerBlinkTime and tonumber(GetEmpowerBlinkTime())
    return max(0.05, min(1.00, value or tonumber(ReadG("empowerStageBlinkTime", 0.25)) or 0.25))
end
--- The stage the progress just crossed and how far its blink has run (0..1), or nil.
local function EmpowerBlink(self, empowered, progress, now)
    if not (empowered and EmpowerBlinkEnabled()) then
        ResetEmpowerBlinkState(self)
        return nil
    end
    if self._lastEmpowerProgress and progress < (self._lastEmpowerProgress - 0.001) then ResetEmpowerBlinkState(self) end
    local stage = min(#EMPOWER_STAGES, max(0, floor(progress * 4)))
    if stage > 0 and stage ~= self._lastEmpowerStageTick then
        local blinkTime = EmpowerBlinkTime()
        self._blinkStage, self._blinkStart, self._blinkUntil = stage, now, now + blinkTime
    end
    self._lastEmpowerStageTick, self._lastEmpowerProgress = stage, progress
    if self._blinkStage and self._blinkUntil and now < self._blinkUntil then
        return self._blinkStage, max(0, min(1, (now - self._blinkStart) / max(0.001, self._blinkUntil - self._blinkStart)))
    end
    return nil
end
local function PlayerClass()
    local _, class = UnitClass("player")
    return class or "MAGE"
end
--- The root and scenes are made on the first paint of a visible row, kept for the box and stopped when it hides.
local function EnsureRoot(self)
    local root = self.root
    if root then
        if not root:IsActive() then root:Activate() end
        return root
    end
    local row = self.castRow
    if not row:IsVisible() then return nil end
    root = MSUF.GF.NewPreviewScene(row)
    self.root = root
    self.sample, self.tick = {}, {}
    self.sceneOpts = { sample = self.sample, point = "CENTER", x = 0, y = 0 }
    row:HookScript("OnHide", function() root:Deactivate() end)
    row:HookScript("OnShow", function() root:Activate() end)
    root:Activate()
    return root
end
local function PaintScene(self, kind, unit, width, height, scale, now)
    local root = EnsureRoot(self)
    if not root then return end
    local sample, opts = self.sample, self.sceneOpts
    for field in pairs(sample) do sample[field] = nil end
    local progress = max(0, min(1, self.progress or 0))
    local empowered = kind == "empowered"
    sample.class, sample.kind, sample.name, sample.icon = PlayerClass(), SCENE_KIND[kind], previewSpellNames[kind], PREVIEW_ICON
    sample.duration, sample.progress = CastDuration(kind), progress
    if empowered then
        sample.stages = EMPOWER_STAGES
        sample.blinkStage, sample.blinkPhase = EmpowerBlink(self, true, progress, now)
    else
        EmpowerBlink(self, false, progress, now)
    end
    if unit == "player" then
        if not empowered then sample.latency, sample.latencyMS = 0.12, 50 end
    else
        sample.targetName = M.Tr and M.Tr("Cleave Training Dummy") or "Cleave Training Dummy"
    end
    sample.kickReady, sample.kickRecovery = true, KICK_RECOVERY
    sample.interrupted = now < (self.interruptUntil or 0)
    opts.width, opts.height, opts.scale = width, height, scale
    local key = SCENE_UNIT[unit] or unit
    local scene = root:Castbar(key, opts)
    if self.scene and self.scene ~= scene then self.scene:Hide() end
    self.scene, self.frame = scene, scene:Frame()
    self.paintedUnit, self.paintedKind, self.paintedInterrupt = unit, kind, sample.interrupted
end
--- An animation tick moves the fill and the time text only; a change of unit, type or interrupt, and the empower
--- stage blink, repaint the scene.
local function PreviewAnimate(self)
    local now = GetTime and GetTime() or 0
    local kind = self.castType or "normal"
    local scene = self.scene
    if scene and kind ~= "empowered" and self.paintedUnit == self.layoutUnit and self.paintedKind == kind
        and self.paintedInterrupt == (now < (self.interruptUntil or 0)) then
        self.tick.progress = max(0, min(1, self.progress or 0))
        if scene:Tick(self.tick) then return end
    end
    self:Refresh()
end
local function PreviewRefresh(self)
    local typeButtons, unitButtons = self.typeButtons, self.unitButtons
    local now = GetTime and GetTime() or 0
    local kind = self.castType or "normal"
    local unit = self.layoutUnit or "player"
    local g = (type(G) == "function" and G()) or {}
    local realW, realH = ReadPreviewCastbarSize(unit, g)
    local showIcon = CastbarPreview.ShowIcon(unit, g)
    local iconX = CastbarPreview.ReadNumber(g, unit, "IconOffsetX", "bossCastIconOffsetX", 0)
    local iconSize = CastbarPreview.ReadNumber(g, unit, "IconSize", "bossCastIconSize", realH)
    iconSize = min(128, max(6, iconSize or realH))
    local rowW = max(1, self.castRow:GetWidth())
    local needW = realW
    if showIcon then needW = needW + max(0, -(iconX or 0)) + max(0, (iconX or 0) + iconSize - realW) end
    local scale = min(1, (rowW - 8) / max(1, needW))
    if scale <= 0 then scale = 1 end
    PaintScene(self, kind, unit, realW, realH, scale, now)
    for key, btn in pairs(typeButtons) do
        local active = key == kind
        if btn.SetActive and btn._msuf2Active ~= active then btn:SetActive(active) end
    end
    for key, btn in pairs(unitButtons) do
        local active = key == unit
        if btn.SetActive and btn._msuf2Active ~= active then btn:SetActive(active) end
    end
end
local function BuildPreviewCastRow(box, preview, barW, mainX)
    local castRow = PixelLayoutRegion(CreateFrame("Frame", nil, box))
    castRow:SetSize(barW, 46)
    castRow:SetPoint("TOPLEFT", box, "TOPLEFT", mainX, -8)
    preview.castRow = castRow
    preview.castRowBase = { parent = box, x = mainX, y = -8 }
    preview._rowOffset = 0
end
local function BuildCastbarPagePreview(ctx, b)
    -- Leave enough vertical canvas for below-bar text, thick outlines, and
    -- scoped icon Y offsets. The former 62px body could cut those regions
    -- at the fixed-preview boundary even though the castbar itself fit.
    local previewHeight = ctx and ctx.hiddenBuild and 72 or 180
    local section, toolbar, fixedPreview = W.FixedPreviewSection(ctx, b, {
        title = "Preview",
        height = previewHeight,
    })
    if ctx and ctx.hiddenBuild then
        W.Text(section, "Castbar preview is built when this page is opened.", 14, -42, ctx.width - 28, T.colors.muted)
        return nil, section, fixedPreview
    end
    local sectionW = section._msuf2Width or b.width or ctx.width or 720
    local innerW = max(1, sectionW - 28)
    local preview = {
        castType = NormalizeCastbarPreviewType(M._msuf2CastbarPreviewType or "normal"),
        layoutUnit = NormalizeCastbarPreviewUnit(M._msuf2CastbarPreviewUnit or "player"),
        progress = 0,
        interruptUntil = 0,
        shakeUntil = 0,
        shakeStart = 0,
        shakeStrength = tonumber(ReadG("castbarShakeStrength", 8)) or 8,
    }
    ResetEmpowerBlinkState(preview)
    local unitButtons, unitHolder = PreviewButtonGroup(toolbar, (M.FilterSupportedUnitValues or function(values) return values end)({
        { key = "player", text = "Player" },
        { key = "target", text = "Target" },
        { key = "focus", text = "Focus" },
        { key = "boss", text = "Boss" },
            { key = "arena", text = "Arena" },
        }), 52, 4, M.SetCastbarPreviewUnit, "preview.unit")
    local buttonGap, interruptW = 6, 90
    local typeValues = { { key = "normal", text = "Normal" }, { key = "channel", text = "Channel" } }
    if CASTBAR_PREVIEW_EMPOWERED then typeValues[3] = { key = "empowered", text = "Empowered" } end
    local typeButtons, typeHolder = PreviewButtonGroup(toolbar, typeValues, 82, buttonGap,
        M.SetCastbarPreviewType, "preview.cast_type")
    local interrupt = T.CenterButtonLabel(T.SkinDangerButton(T.Button(toolbar, "Interrupt", interruptW, 24)))
    interrupt._msuf2AllowCombatClick = true
    interrupt._msuf2SkipHistoryCheckpoint = true
    T.FitButtonWidth(interrupt, interruptW)
    -- Use the shared 32px toolbar, like the other fixed previews. Decide whether
    -- to wrap from the translated controls' actual widths, including the title.
    local unitX = 16 + section.title:GetStringWidth() + 12
    local controlsW = typeHolder:GetWidth() + 10 + interrupt:GetWidth()
    local compactControls = unitX + unitHolder:GetWidth() + 16 + controlsW + 16 > sectionW
    unitHolder:SetPoint("LEFT", toolbar, "LEFT", unitX, 0)
    if compactControls then
        typeHolder:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 16, -10)
        interrupt:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -16, -10)
    else
        typeHolder:SetPoint("RIGHT", toolbar, "RIGHT", -(16 + interrupt:GetWidth() + 10), 0)
        interrupt:SetPoint("RIGHT", toolbar, "RIGHT", -16, 0)
    end
    interrupt:SetScript("OnClick", function()
        M.PlayCastbarPreviewInterrupt()
    end)
    RegisterControl(interrupt, Meta("preview.interrupt", "ephemeral"), "Interrupt", "button")
    preview.unitButtons = unitButtons
    preview.typeButtons = typeButtons
    local box = T.Panel(section, nil, { 0.018, 0.022, 0.044, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", section, "TOPLEFT", 14, compactControls and -82 or -52)
    box:SetSize(innerW, 78)
    BuildPreviewCastRow(box, preview, min(720, max(280, innerW - 36)), 18)
    preview.PlayShake = PreviewPlayShake
    preview.SetRowOffset = PreviewSetRowOffset
    preview.Refresh = PreviewRefresh
    preview.Animate = PreviewAnimate
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
        preview:Animate()
    end)
    M._msuf2CastbarPreview = preview
    if M._msuf2CastbarPreviewUnit then M.SetCastbarPreviewUnit(M._msuf2CastbarPreviewUnit) end
    if M._msuf2CastbarPreviewType then M.SetCastbarPreviewType(M._msuf2CastbarPreviewType) end
    if M._msuf2CastbarPreviewInterruptPending then M.PlayCastbarPreviewInterrupt() end
    M.TrackMethodRefresh(ctx, preview, "Refresh")
    return preview, section, fixedPreview
end
GP.CastbarControlMeta = Meta
GP.ScheduleCastbarPageWork = ScheduleCastbarPageWork
GP.CASTBAR_PAGE_WORK_DELAY = CASTBAR_PAGE_WORK_DELAY
GP.CASTBAR_PREVIEW_REFRESH_INTERVAL = CASTBAR_PREVIEW_REFRESH_INTERVAL
GP.BuildCastbarPagePreview = BuildCastbarPagePreview
