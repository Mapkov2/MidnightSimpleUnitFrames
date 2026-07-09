--- Group preview render/composition.
---
--- Native creates the preview host and interaction handles; this module owns
--- the hot refresh path that lays out the mock group frame and preview layers.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Render = M.GroupPreviewRender or {}
M.GroupPreviewRender = Render
local F = M.Fallbacks or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local function DefaultCompiledAuraLane(_, _, fallback) return fallback or {} end
local function DefaultInt(value, fallback, minValue, maxValue)
    local n = math.floor((tonumber(value) or tonumber(fallback) or 0) + 0.0001)
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end
local function NumberOrOne(value) return tonumber(value) or 1 end
local function DefaultAuraGrowth() return { px = 1, py = 0, sx = 0, sy = -1 } end
local function DefaultClampLayer(value, fallback) return tonumber(value) or fallback or 0 end
local function DefaultClassColor(_, r, g, b) return r or 1, g or 1, b or 1 end
local GROUP_RENDER_FALLBACKS = {
    CompiledSpec = F.Nil, CompiledAuraLane = DefaultCompiledAuraLane, RuntimeStatusConfig = F.Nil,
    CurrentStatusSpec = F.Nil, StatusSpecEnabled = F.False, StatusSpecInMode = F.False, StatusSpecIsText = F.False,
    StatusText = F.Empty, StatusLabel = F.Status, CurrentSpellConfig = F.Nil, CurrentSpellPlaced = F.Nil,
    CurrentSpellTexture = F.QuestionIcon, CurrentSpellColor = F.WhiteRGB, MockSpellTexture = F.QuestionIcon,
    Int = DefaultInt, Round = F.Round, ClampZoom = NumberOrOne, UpdateZoomControls = F.Noop,
    AuraGrowth = DefaultAuraGrowth, ApplyRounded = F.False, ClampLayer = DefaultClampLayer,
    ClassColor = DefaultClassColor, HealthColor = F.HealthRGB,
    SelectHandle = F.Noop, NudgeHandlePosition = F.Noop, AddIconPool = F.Noop, RefreshHandleSelection = F.Noop,
}
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}

--- Installs the group preview renderer into the preview host. Native.lua owns
--- frame creation and input handles; this function owns repeated composition
--- from compiled group specs, visible layers, zoom state, and selected handles.
function Render.Install(box, ctx, deps)
    if not box then return end
    deps = deps or {}
    local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
    local H = deps.H or {}
    local M = deps.M or _G.MSUF2 or {}
    local MSUF = deps.MSUF or MSUF or {}
    local T = deps.T or M.Theme or {}
    local width = tonumber(deps.width) or 720
    local mock = deps.mock or box._mock
    local WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
    local GF_PREVIEW_NAMES = deps.NAMES or {}
    local GF_PREVIEW_CLASSES = deps.CLASSES or {}
    local GF_AURA_MOCK_ICON_IDS = deps.AURA_MOCK_ICON_IDS or {}
    local GF_PREVIEW_MIN_W = tonumber(deps.MIN_W) or 380
    local GF_PREVIEW_MIN_H = tonumber(deps.MIN_H) or 130
    local GF_PREVIEW_ROLE = deps.ROLE or "HEALER"
    local GF_PREVIEW_ANCHOR_FRAC = deps.ANCHOR_FRAC or {}
    local buffHandle = deps.buffHandle
    local trackedBuffHandle = deps.trackedBuffHandle
    local debuffHandle = deps.debuffHandle
    local statusHandles = deps.statusHandles or {}
    local spellHandle = deps.spellHandle
    local targetedHandle = deps.targetedHandle
    local statusSpecs = deps.statusSpecs or {}
    local CompiledSpec, CompiledAuraLane, RuntimeStatusConfig, CurrentStatusSpec, StatusSpecEnabled, StatusSpecInMode, StatusSpecIsText, StatusText, StatusLabel, CurrentSpellConfig, CurrentSpellPlaced, CurrentSpellTexture, CurrentSpellColor, MockSpellTexture = M.PickFallbacks(deps, GROUP_RENDER_FALLBACKS, [[
        CompiledSpec CompiledAuraLane RuntimeStatusConfig CurrentStatusSpec StatusSpecEnabled StatusSpecInMode StatusSpecIsText StatusText StatusLabel CurrentSpellConfig CurrentSpellPlaced CurrentSpellTexture CurrentSpellColor MockSpellTexture
    ]])
    local Int, Round, ClampZoom, UpdateZoomControls, AuraGrowth, ApplyRounded, ClampLayer, ClassColor, HealthColor, SelectHandle, NudgeHandlePosition, AddIconPool, RefreshHandleSelection = M.PickFallbacks(deps, GROUP_RENDER_FALLBACKS, [[
        Int Round ClampZoom UpdateZoomControls AuraGrowth ApplyRounded ClampLayer ClassColor HealthColor SelectHandle NudgeHandlePosition AddIconPool RefreshHandleSelection
    ]])
    local ScaleValue = deps.ScaleValue or function(value, scale, minValue)
        local v = Round((tonumber(value) or 0) * (tonumber(scale) or 1))
        if minValue ~= nil and v < minValue then v = minValue end
        return v
    end
    local ConfigToOffset = deps.ConfigToOffset or function(value, scale) return Round((tonumber(value) or 0) * (tonumber(scale) or 1)) end
    local ResolvePreviewStatusbarTexture = deps.ResolveStatusbarTexture or function() return WHITE8X8 end
    --- Refresh is menu-only. It reads compiled/runtime-like specs to draw a mock
    --- group frame and must not rebuild secure headers or subscribe to roster
    --- events.
    function box:Refresh()
        local profiling = M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStop
        local profileStarted = profiling and M.ProfileStart() or nil
        local textHandles = self._textHandles or {}
        local kind = H.CurrentScope()
        local label = H.PreviewScopeLabel(kind)
        local conf = H.Conf(kind)
        local gf = MSUF and MSUF.GF
        local previewAnimation = MSUF and MSUF.PreviewAnimation
        local buildFrameState = previewAnimation and previewAnimation.BuildFrameState or _G.MSUF_BuildPreviewAnimationFrameState
        local animState = self._animationEnabled == true and type(buildFrameState) == "function"
            and buildFrameState(self, 1, kind, self._msufGFMenuPreviewAnimState or {}, self._animationElapsed)
        if animState then self._msufGFMenuPreviewAnimState = animState end
        local hpPct = animState and max(0.02, min(0.98, tonumber(animState.hpPct) or 0.72)) or 0.72
        local powerPct = animState and max(0, min(1, tonumber(animState.powerPct) or 0.70)) or 0.70
        local healPct = animState and max(0.01, min(0.24, tonumber(animState.healPct) or 0.12)) or 0.12
        local absorbPct = animState and max(0.01, min(0.24, tonumber(animState.absorbPct) or 0.08)) or 0.08
        local runtimeSpec = CompiledSpec(kind)
        local runtimeAuras = runtimeSpec and runtimeSpec.auras or nil
        local runtimeText = (runtimeSpec and runtimeSpec.text) or {}
        local runtimePower = (runtimeSpec and runtimeSpec.power) or {}
        local runtimeHealth = (runtimeSpec and runtimeSpec.health) or {}
        local runtimeBorder = (runtimeSpec and runtimeSpec.border) or {}
        local runtimePrediction = (runtimeSpec and runtimeSpec.prediction) or {}
        local runtimeStatus = (runtimeSpec and runtimeSpec.status) or {}
        local function ResolveStatusPreviewTexture(spec, runtimeCfg, iconType, variant)
            local customIcon = runtimeCfg and runtimeCfg.customIcon
            if (type(customIcon) ~= "string" or customIcon == "") and spec and spec.customIcon then
                customIcon = conf[spec.customIcon]
            end
            if type(customIcon) == "string" and customIcon ~= "" then return customIcon, 0, 1, 0, 1 end
            local resolver = _G.MSUF_GetStatusIconTexture or (gf and gf.GetStatusIconTexture)
            if type(resolver) == "function" then
                local path, l, r, t, b = resolver("BLIZZARD", iconType, variant, runtimeStatus and runtimeStatus.useMidnight == true)
                if type(path) == "string" and path ~= "" then return path, l, r, t, b end
            end
            if iconType == "raidMarker" then return "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0, 0.25, 0, 0.25 end
            if iconType == "readyCheck" then return "Interface\\RaidFrame\\ReadyCheck-Ready", 0, 1, 0, 1 end
            if iconType == "summon" then return "Interface\\RaidFrame\\Raid-Icon-SummonPending", 0, 1, 0, 1 end
            if iconType == "incomingRes" then return "Interface\\RaidFrame\\Raid-Icon-Rez", 0, 1, 0, 1 end
            if iconType == "pvp" then return "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 1, 0, 1 end
            if iconType == "phase" then return "Interface\\TargetingFrame\\UI-PhasingIcon", 0, 1, 0, 1 end
            return nil
        end
        local focus = H.PreviewFocusForPage(ctx.key)
        local layerVisible = M.gfPreviewLayerVisible or {}
        local soloLayer = M.gfPreviewSoloLayer
        local rawAuras = conf.auras or {}
        local function RawTrackedBuffLane(rawBuff)
            rawBuff = rawBuff or {}
            return {
                enabled = rawBuff.trackedEnabled == true or (rawBuff.trackedEnabled == nil and conf.spellIndicators and conf.spellIndicators.enabled == true),
                max = rawBuff.trackedMax or 8,
                perRow = rawBuff.trackedPerRow or rawBuff.perRow or 4,
                size = rawBuff.trackedSize or rawBuff.size or 22,
                spacing = rawBuff.trackedSpacing or rawBuff.spacing or 1,
                anchor = rawBuff.trackedAnchor or "TOPLEFT",
                growth = rawBuff.trackedGrowth or "RIGHTDOWN",
                x = rawBuff.trackedX or 0,
                y = rawBuff.trackedY or 0,
                layer = rawBuff.trackedLayer or (conf.spellIndicators and conf.spellIndicators.layer) or 9,
                showCooldownSwipe = rawBuff.trackedShowCooldownSwipe,
                cooldownSwipeReverse = rawBuff.trackedCooldownSwipeReverse,
                showCooldown = rawBuff.trackedShowCooldown,
                showStacks = rawBuff.trackedShowStacks,
                cooldownSize = rawBuff.trackedCooldownSize,
                cooldownAnchor = rawBuff.trackedCooldownAnchor,
                cooldownX = rawBuff.trackedCooldownX,
                cooldownY = rawBuff.trackedCooldownY,
                stackSize = rawBuff.trackedStackSize,
                stackAnchor = rawBuff.trackedStackAnchor,
                stackX = rawBuff.trackedStackX,
                stackY = rawBuff.trackedStackY,
            }
        end
        local buffCfg = runtimeAuras and CompiledAuraLane(runtimeAuras, "buff", rawAuras.buff or {}) or (rawAuras.buff or {})
        local trackedBuffCfg = runtimeAuras and CompiledAuraLane(runtimeAuras, "trackedBuff", RawTrackedBuffLane(rawAuras.buff)) or RawTrackedBuffLane(rawAuras.buff)
        local debuffCfg = runtimeAuras and CompiledAuraLane(runtimeAuras, "debuff", rawAuras.debuff or {}) or (rawAuras.debuff or {})
        local statusSpec = CurrentStatusSpec()
        local selectedSpellCfg = CurrentSpellConfig(kind)
        local selectedPlaced = CurrentSpellPlaced(kind)
        local selectedSpellPlacedEnabled = selectedPlaced and (selectedPlaced.type or "icon") ~= "none"
        local runtimeSpellIndicators = runtimeSpec and runtimeSpec.spellIndicators or nil
        local runtimeSpellItems = runtimeSpellIndicators and runtimeSpellIndicators.items or nil
        local runtimeSpellPlacedAvailable = false
        local runtimeSpellEffect
        if type(runtimeSpellItems) == "table" then
            for i = 1, #runtimeSpellItems do
                local item = runtimeSpellItems[i]
                local placed = item and item.placed
                if placed and (placed.type or "icon") ~= "none" then
                    runtimeSpellPlacedAvailable = true
                end
                local effect = item and item.frame
                if effect and effect.type and effect.type ~= "none" then
                    local currentPriority = tonumber(runtimeSpellEffect and runtimeSpellEffect.priority) or 999
                    local nextPriority = tonumber(effect.priority) or 5
                    if not runtimeSpellEffect or nextPriority < currentPriority then
                        runtimeSpellEffect = effect
                    end
                end
            end
        end
        local function StatusConfigAvailable(spec)
            if runtimeSpec then
                local cfg = RuntimeStatusConfig(runtimeStatus, spec)
                return cfg and cfg.enabled == true
            end
            return StatusSpecEnabled(conf, spec)
        end
        local statusLayerAvailable = false
        for i = 1, #statusSpecs do
            local spec = statusSpecs[i]
            if StatusSpecInMode(spec, statusSpec) and StatusConfigAvailable(spec) then
                statusLayerAvailable = true
                break
            end
        end
        local rawCustomRenderer = true
        local customRenderer = false
        local aurasEnabled
        if runtimeAuras then
            customRenderer = buffCfg.enabled == true or trackedBuffCfg.enabled == true or debuffCfg.enabled == true
            aurasEnabled = customRenderer or runtimeAuras.enabled == true
        else
            aurasEnabled = rawAuras.enabled ~= false
            customRenderer = rawCustomRenderer
        end
        local powerTextEnabled
        if runtimeSpec then
            powerTextEnabled = runtimeSpec.showPowerText == true
        else
            powerTextEnabled = (gf and gf.IsPowerTextEnabled and gf.IsPowerTextEnabled(kind, conf)) or (conf.showPowerText == true or conf.showPower == true)
        end
        local function AuraLaneAvailable(cfg, defaultMax)
            return customRenderer
                and (runtimeAuras and cfg.enabled == true or cfg.enabled ~= false)
                and (tonumber(cfg.max) or defaultMax or 0) > 0
        end
        local customAuraText = AuraLaneAvailable(buffCfg, 6) or AuraLaneAvailable(trackedBuffCfg, 4) or AuraLaneAvailable(debuffCfg, 6)
        local textAvailable
        if runtimeSpec then
            textAvailable = runtimeSpec.showName == true or runtimeSpec.showHealthText == true or powerTextEnabled == true
        else
            textAvailable = conf.showName ~= false or conf.showHPText ~= false or powerTextEnabled == true
        end
        local layerAvailable = {
            guides = true,
            bounds = true,
            buff = AuraLaneAvailable(buffCfg, 6),
            trackedBuff = AuraLaneAvailable(trackedBuffCfg, 4),
            debuff = AuraLaneAvailable(debuffCfg, 6),
            status = statusLayerAvailable,
            si = (runtimeSpellIndicators and runtimeSpellIndicators.enabled == true and (runtimeSpellPlacedAvailable or runtimeSpellEffect ~= nil))
                or (runtimeSpec and runtimeSpec.spellIndicators and runtimeSpec.spellIndicators.enabled == true and selectedSpellPlacedEnabled)
                or false,
            targetedSpells = kind == "party" and conf.targetedSpellsEnabled == true,
            auraText = aurasEnabled and customAuraText,
            text = textAvailable,
        }
        self._layerAvailable = layerAvailable
        if soloLayer and layerAvailable[soloLayer] == false then
            M.gfPreviewSoloLayer = nil
            soloLayer = nil
        end
        local function LayerOn(key)
            return layerAvailable[key] ~= false and layerVisible[key] ~= false
        end
        local function LayerAlpha(key)
            if layerAvailable[key] == false then return 0 end
            return (soloLayer and soloLayer ~= key) and 0.15 or 1
        end
        local function AuraPreviewAlpha(cfg)
            if type(cfg) ~= "table" then return 1 end
            if cfg.alpha ~= nil then return tonumber(cfg.alpha) or 1 end
            if cfg.behindBar == true then
                local v = (tonumber(cfg.behindBarAlpha) or 85) / 100
                if v < 0 then return 0 end
                if v > 1 then return 1 end
                return v
            end
            return 1
        end
        local function HideSpellEffectPreview()
            if mock._siPreviewTint then mock._siPreviewTint:Hide() end
            if mock._siPreviewEdges then
                for i = 1, #mock._siPreviewEdges do
                    if mock._siPreviewEdges[i] then mock._siPreviewEdges[i]:Hide() end
                end
            end
            if mock._siPreviewSavedNameColor and mock._nameFS and mock._nameFS.SetTextColor then
                local c = mock._siPreviewSavedNameColor
                mock._nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
            mock._siPreviewSavedNameColor = nil
        end
        local function EnsureSpellPreviewEdges()
            if mock._siPreviewEdges then return mock._siPreviewEdges end
            mock._siPreviewEdges = {}
            for i = 1, 4 do
                local tex = mock:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(WHITE8X8)
                tex:Hide()
                mock._siPreviewEdges[i] = tex
            end
            return mock._siPreviewEdges
        end
        local function ApplySpellEffectPreview(effect)
            HideSpellEffectPreview()
            if type(effect) ~= "table" then return end
            local color = effect.color or {}
            local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
            local a = color[4] or 1
            if effect.type == "healthtint" then
                local tint = mock._siPreviewTint
                if not tint then
                    tint = mock:CreateTexture(nil, "OVERLAY")
                    tint:SetTexture(WHITE8X8)
                    mock._siPreviewTint = tint
                end
                tint:ClearAllPoints()
                tint:SetAllPoints(mock._health or mock)
                tint:SetVertexColor(r, g, b, effect.tintAlpha or a or 0.20)
                tint:Show()
            elseif effect.type == "namecolor" then
                if mock._nameFS and mock._nameFS.SetTextColor then
                    if mock._nameFS.GetTextColor then
                        local cr, cg, cb, ca = mock._nameFS:GetTextColor()
                        mock._siPreviewSavedNameColor = { cr, cg, cb, ca }
                    end
                    mock._nameFS:SetTextColor(r, g, b, a)
                end
            elseif effect.type == "border" or effect.type == "glow" or effect.type == "pulse" then
                local edges = EnsureSpellPreviewEdges()
                local thickness = max(1, ScaleValue(effect.thickness or (effect.type == "glow" and 3 or 2), mock._previewScale or 1, 1))
                local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
                top:ClearAllPoints()
                top:SetPoint("TOPLEFT", mock, "TOPLEFT", -thickness, thickness)
                top:SetPoint("TOPRIGHT", mock, "TOPRIGHT", thickness, thickness)
                top:SetHeight(thickness)
                bottom:ClearAllPoints()
                bottom:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", -thickness, -thickness)
                bottom:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", thickness, -thickness)
                bottom:SetHeight(thickness)
                left:ClearAllPoints()
                left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
                left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
                left:SetWidth(thickness)
                right:ClearAllPoints()
                right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
                right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
                right:SetWidth(thickness)
                for i = 1, 4 do
                    edges[i]:SetVertexColor(r, g, b, effect.type == "glow" and min(1, a * 0.85) or a)
                    edges[i]:Show()
                end
            end
        end
        self._title:SetText(string.format((M.Tr and M.Tr("%s - %s")) or "%s - %s", (M.Tr and M.Tr("Group Frame Preview")) or "Group Frame Preview", label))
        local stageW = self._stage:GetWidth() or (width - 98)
        local stageH = self._stage:GetHeight() or 218
        if stageW <= 1 then stageW = math.max(260, width - 98) end
        if stageH <= 1 then stageH = 218 end
        local liveW, liveH, frameScale = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width) or 120,
            tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height) or 40,
            1
        if gf and gf.GetScaledFrameMetrics then
            local w2, h2, _, sc2 = gf.GetScaledFrameMetrics(kind)
            liveW = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(w2) or liveW
            liveH = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(h2) or liveH
            frameScale = tonumber(sc2) or 1
        end
        liveW, liveH = max(1, liveW), max(1, liveH)
        local autoZoom = min(GF_PREVIEW_MIN_W / liveW, GF_PREVIEW_MIN_H / liveH)
        autoZoom = max(1.4, min(2.8, autoZoom))
        local manualZoom = tonumber(self._manualZoom)
        local frozenZoom = tonumber(self._dragFrozenScale)
        local previewScale = manualZoom and ClampZoom(manualZoom) or (frozenZoom and ClampZoom(frozenZoom) or autoZoom)
        self._mockAutoScale = autoZoom
        self._mockScale = previewScale
        UpdateZoomControls(self)
        local mockW = max(48, Round(liveW * previewScale))
        local mockH = max(20, Round(liveH * previewScale))
        local powerH = runtimePower and runtimePower.enabled == true and ScaleValue(runtimePower.height, previewScale, 0) or 0
        if not runtimeSpec then powerH = H.MockPowerHeight(kind, conf, previewScale, frameScale) end
        local borderEnabled = runtimeSpec and (runtimeBorder.enabled ~= false) or (not runtimeSpec and conf.borderEnabled ~= false)
        local outline = borderEnabled and (tonumber(runtimeBorder and runtimeBorder.thickness) or 1) or 0
        if not runtimeSpec and borderEnabled and gf and gf.GetBarOutlineThickness then outline = tonumber(gf.GetBarOutlineThickness(kind)) or outline end
        local outlineEdge = max(0, Round(outline * previewScale))
        local inset = 0
        local startX = Round((stageW - mockW) * 0.5)
        local startY = -Round((stageH - mockH) * 0.5)
        local mock = self._mock
        mock._previewScale = previewScale
        self._mockBaseOffsetX, self._mockBaseOffsetY = startX, startY
        mock:ClearAllPoints()
        mock:SetPoint("TOPLEFT", self._stage, "TOPLEFT", startX + (tonumber(self._zoomPanX) or 0), startY + (tonumber(self._zoomPanY) or 0))
        mock:SetSize(mockW, mockH)
        mock:SetBackdrop({ bgFile = WHITE8X8 })
        local bgAlpha = conf.hpBgAlpha or 0.85
        if runtimeSpec and runtimeSpec.backgroundAlpha ~= nil then bgAlpha = runtimeSpec.backgroundAlpha end
        mock:SetBackdropColor(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09, bgAlpha)
        mock:SetBackdropBorderColor(0, 0, 0, 0)
        local cls = GF_PREVIEW_CLASSES[((kind == "party" and 5 or 2) % #GF_PREVIEW_CLASSES) + 1]
        local br, bg, bb = runtimeBorder.r or conf.borderR or 0, runtimeBorder.g or conf.borderG or 0, runtimeBorder.b or conf.borderB or 0
        mock._msufGFPreviewBorderR = br
        mock._msufGFPreviewBorderG = bg
        mock._msufGFPreviewBorderB = bb
        mock._msufGFPreviewBorderA = borderEnabled and (runtimeBorder.a or conf.borderA or 1) or 0
        local barTex = runtimeHealth.texture or (runtimeSpec and runtimeSpec.texture) or (gf and gf.ResolveBarTexture and gf.ResolveBarTexture(kind)) or ResolvePreviewStatusbarTexture(conf, "barTexture")
        local bgTex = runtimeHealth.backgroundTexture or (runtimeSpec and runtimeSpec.backgroundTexture) or (gf and gf.ResolveBarBgTexture and gf.ResolveBarBgTexture(kind)) or WHITE8X8
        mock._health:SetStatusBarTexture(barTex)
        mock._health:ClearAllPoints()
        mock._health:SetPoint("TOPLEFT", mock, "TOPLEFT", inset, -inset)
        mock._health:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inset, powerH > 0 and (powerH + inset) or inset)
        local runtimeHealthMode = runtimeHealth and runtimeHealth.mode
        local hr, hg, hb
        if runtimeHealthMode == "dark" or runtimeHealthMode == "unified" or runtimeHealthMode == "custom" then
            hr, hg, hb = runtimeHealth.r, runtimeHealth.g, runtimeHealth.b
        end
        if not hr then hr, hg, hb = HealthColor(conf, hpPct or 0.72, cls) end
        local groupVisual = (runtimeSpec and runtimeSpec.group) or {}
        mock._health:SetStatusBarColor(hr, hg, hb, tonumber(groupVisual.hpBarAlpha) or tonumber(conf.hpBarAlpha) or 1)
        if mock._health.SetMinMaxValues then mock._health:SetMinMaxValues(0, 1) end
        mock._health:SetValue(hpPct)
        local hpReverse = runtimeHealth.reverse == true or (not runtimeSpec and conf.reverseFill == true)
        if mock._health.SetReverseFill then mock._health:SetReverseFill(hpReverse) end
        mock._healthBg:SetTexture(bgTex)
        local hbCfg = runtimeHealth.background or {}
        local hbr, hbg, hbb = hbCfg.r or conf.bgR or 0.06, hbCfg.g or conf.bgG or 0.06, hbCfg.b or conf.bgB or 0.07
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        if runtimeHealth.backgroundMatchHealth == true then hbr, hbg, hbb = hr or hbr, hg or hbg, hb or hbb end
        if not runtimeSpec and gen and gen.barBgClassColor then hbr, hbg, hbb = ClassColor(cls, hbr, hbg, hbb) end
        mock._healthBg:SetVertexColor(hbr, hbg, hbb, hbCfg.a or groupVisual.hpBgAlpha or conf.hpBgAlpha or 0.85)
        local hpTex = mock._health.GetStatusBarTexture and mock._health:GetStatusBarTexture()
        local healPredMode = tonumber(runtimePrediction.healAnchorMode) or H.HealPredAnchorMode(conf)
        local healPredShown
        if runtimeSpec then
            healPredShown = runtimePrediction.heal == true
        else
            healPredShown = H.HealPredictionEnabled(kind, conf)
        end
        mock._healPred:SetStatusBarTexture(runtimePrediction.texture or barTex)
        mock._healPred:SetStatusBarColor(runtimePrediction.healR or 0, runtimePrediction.healG or 1, runtimePrediction.healB or 0.4, runtimePrediction.healA or 0.45)
        mock._healPred:ClearAllPoints()
        if (healPredMode == 3 or healPredMode == 4) and hpTex then
            if hpReverse then
                mock._healPred:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
                mock._healPred:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
                if mock._healPred.SetReverseFill then mock._healPred:SetReverseFill(true) end
            else
                mock._healPred:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
                mock._healPred:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
                if mock._healPred.SetReverseFill then mock._healPred:SetReverseFill(false) end
            end
            mock._healPred:SetWidth(max(1, mockW * healPct))
            mock._healPred:SetValue(1)
        else
            mock._healPred:SetAllPoints(mock._health)
            if mock._healPred.SetReverseFill then mock._healPred:SetReverseFill((healPredMode == 1) and false or ((healPredMode == 5) and not hpReverse or true)) end
            mock._healPred:SetValue(healPct)
        end
        mock._healPred:SetShown(healPredShown)
        mock._absorb:ClearAllPoints()
        mock._absorb:SetStatusBarTexture(runtimePrediction.absorbTexture or runtimePrediction.texture or barTex)
        mock._absorb:SetStatusBarColor(runtimePrediction.absorbR or 0.55, runtimePrediction.absorbG or 0.70, runtimePrediction.absorbB or 1, runtimePrediction.absorbA or 0.55)
        local absorbMode = tonumber(runtimePrediction.absorbAnchorMode) or tonumber((conf.hlOverride and conf.absorbAnchorMode ~= nil and conf.absorbAnchorMode) or (gen and gen.absorbAnchorMode)) or 2
        if absorbMode < 1 or absorbMode > 5 then absorbMode = 2 end
        local absorbShown
        if runtimeSpec then
            absorbShown = runtimePrediction.absorb == true
        else
            local displayMode = (conf.hlOverride and conf.absorbTextMode ~= nil) and conf.absorbTextMode or (gen and gen.absorbTextMode)
            displayMode = tonumber(displayMode)
            if displayMode then
                absorbShown = displayMode == 2 or displayMode == 3
            else
                local enableAbsorbBar = (conf.hlOverride and conf.enableAbsorbBar ~= nil) and conf.enableAbsorbBar or (gen and gen.enableAbsorbBar)
                absorbShown = enableAbsorbBar ~= false
            end
        end
        local absorbAnchorTex = hpTex or mock._health
        if healPredShown and (healPredMode == 3 or healPredMode == 4) and mock._healPred.GetStatusBarTexture then absorbAnchorTex = mock._healPred:GetStatusBarTexture() or absorbAnchorTex end
        local absorbFollows = (absorbMode == 3 or absorbMode == 4) and absorbAnchorTex
        if absorbFollows then
            if hpReverse then
                mock._absorb:SetPoint("TOPRIGHT", absorbAnchorTex, "TOPLEFT", 0, 0)
                mock._absorb:SetPoint("BOTTOMRIGHT", absorbAnchorTex, "BOTTOMLEFT", 0, 0)
                if mock._absorb.SetReverseFill then mock._absorb:SetReverseFill(true) end
            else
                mock._absorb:SetPoint("TOPLEFT", absorbAnchorTex, "TOPRIGHT", 0, 0)
                mock._absorb:SetPoint("BOTTOMLEFT", absorbAnchorTex, "BOTTOMRIGHT", 0, 0)
                if mock._absorb.SetReverseFill then mock._absorb:SetReverseFill(false) end
            end
        else
            mock._absorb:SetAllPoints(mock._health)
            if mock._absorb.SetReverseFill then mock._absorb:SetReverseFill((absorbMode == 1) and false or ((absorbMode == 5) and not hpReverse or true)) end
        end
        if absorbFollows then mock._absorb:SetWidth(max(1, mockW * absorbPct)) end
        mock._absorb:SetValue(absorbFollows and 1 or absorbPct)
        mock._absorb:SetShown(absorbShown)
        if powerH > 0 then
            mock._power:SetStatusBarTexture(runtimePower.texture or barTex)
            mock._power:ClearAllPoints()
            mock._power:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", inset, inset)
            mock._power:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inset, inset)
            mock._power:SetHeight(powerH)
            mock._powerBg:SetTexture(runtimePower.backgroundTexture or bgTex)
            local pbg = runtimePower.background or {}
            mock._powerBg:SetVertexColor(pbg.r or conf.bgR or 0.06, pbg.g or conf.bgG or 0.06, pbg.b or conf.bgB or 0.07, pbg.a or conf.hpBgAlpha or 0.85)
            if mock._power.SetMinMaxValues then mock._power:SetMinMaxValues(0, 1) end
            mock._power:SetValue(powerPct)
            mock._power:Show()
            mock._powerBg:Show()
        else
            mock._power:Hide()
            mock._powerBg:Hide()
        end
        if ApplyRounded(mock, conf, powerH > 0, outlineEdge) then
            H.SetOutlineShown(mock, false)
        else
            H.LayoutOutline(mock, outlineEdge)
        end
        local textBaseLevel = ((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + (Layers.TEXT_BASE_OFFSET or 10)
        if mock._nameTextLayer then
            if mock._nameTextLayer.GetParent and mock._nameTextLayer:GetParent() ~= mock and mock._nameTextLayer.SetParent then mock._nameTextLayer:SetParent(mock) end
            mock._nameTextLayer:ClearAllPoints()
            mock._nameTextLayer:SetAllPoints(mock)
            mock._nameTextLayer:SetFrameLevel(textBaseLevel + (tonumber(runtimeText.nameLayer) or tonumber(conf.nameTextLayer) or 5))
        end
        if mock._healthTextLayer then
            if mock._healthTextLayer.GetParent and mock._healthTextLayer:GetParent() ~= mock and mock._healthTextLayer.SetParent then mock._healthTextLayer:SetParent(mock) end
            mock._healthTextLayer:ClearAllPoints()
            mock._healthTextLayer:SetAllPoints(mock)
            mock._healthTextLayer:SetFrameLevel(textBaseLevel + (tonumber(runtimeText.healthLayer) or tonumber(conf.textLayer) or 5))
        end
        if mock._powerTextLayer then
            mock._powerTextLayer:ClearAllPoints()
            mock._powerTextLayer:SetAllPoints(mock)
            mock._powerTextLayer:SetFrameLevel(textBaseLevel + (tonumber(runtimeText.powerLayer) or tonumber(conf.powerTextLayer) or 2))
        end
        local showText = LayerOn("text")
        local fontPath = (runtimeSpec and runtimeSpec.font) or (gf and gf.ResolveFontPath and gf.ResolveFontPath(kind)) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        local fontFlags = (runtimeSpec and runtimeSpec.fontFlags) or (gf and gf.ResolveFontFlags and gf.ResolveFontFlags(kind)) or "OUTLINE"
        local fontShadow = true
        local fontShadowAlpha = tonumber(runtimeSpec and runtimeSpec.fontShadowAlpha) or 1
        local fontShadowX = tonumber(runtimeSpec and runtimeSpec.fontShadowX) or 1
        local fontShadowY = tonumber(runtimeSpec and runtimeSpec.fontShadowY) or -1
        if runtimeSpec then
            fontShadow = runtimeSpec.fontShadow == true
        elseif gf and gf.ResolveFontShadow then
            fontShadow, fontShadowAlpha, fontShadowX, fontShadowY = gf.ResolveFontShadow(kind)
        end
        local function SetPreviewFont(fs, size)
            if not fs then return end
            local path = fontPath
            local resolveSafe = _G.MSUF_ResolveSafeFontPath
            if type(resolveSafe) == "function" then
                local g = _G.MSUF_DB and _G.MSUF_DB.general
                path = resolveSafe(path, size, fontFlags, g and g.fontKey)
            end
            local ok = pcall(fs.SetFont, fs, path, size, fontFlags)
            if not ok then
                pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, fontFlags)
            end
            if fs.SetShadowOffset then
                if fontShadow then
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, fontShadowAlpha or 1) end
                    fs:SetShadowOffset(fontShadowX or 1, fontShadowY or -1)
                else
                    fs:SetShadowOffset(0, 0)
                end
            end
        end
        local function LayoutPreviewText(fs, point, relPoint, x, y, justify, relativeTo)
            if not fs then return end
            fs:ClearAllPoints()
            fs:SetPoint(point, relativeTo or fs:GetParent(), relPoint or point, x or 0, y or 0)
            fs:SetJustifyH(justify or "LEFT")
            fs._msufPreviewJustifyH = justify or "LEFT"
        end
        local function PaintPreviewText(fs, size, mode, point, relPoint, x, y, justify, r, g, b, a, shown, text)
            if not fs then return end
            SetPreviewFont(fs, size)
            fs:SetTextColor(r, g, b, a)
            LayoutPreviewText(fs, point, relPoint, x, y, justify, mock)
            fs:SetText(text)
            fs:SetShown(shown and mode ~= "NONE")
        end
        local fr, fg, fb = T.colors.text[1], T.colors.text[2], T.colors.text[3]
        if runtimeSpec and runtimeSpec.textColor then fr, fg, fb = runtimeSpec.textColor.r, runtimeSpec.textColor.g, runtimeSpec.textColor.b end
        if gf and gf.ResolveFontColor then fr, fg, fb = gf.ResolveFontColor(kind) end
        local textAlpha = tonumber(runtimeSpec and runtimeSpec.textColor and runtimeSpec.textColor.a)
            or (gf and gf.ResolveFontTextAlpha and gf.ResolveFontTextAlpha(kind))
            or 1
        local baselineOffset = (runtimeSpec and 0) or (gf and gf.ResolveFontBaselineOffset and gf.ResolveFontBaselineOffset(kind)) or 0
        SetPreviewFont(mock._nameFS, max(6, ScaleValue((runtimeSpec and runtimeSpec.nameFontSize) or conf.nameFontSize or 12, previewScale, 6)))
        local previewName = GF_PREVIEW_NAMES[5]
        if gf and gf.ResolveNameTruncation and gf.TruncateName then
            local maxC, noEllipsis, clipSide = gf.ResolveNameTruncation(kind)
            if maxC and maxC > 0 then previewName = gf.TruncateName(previewName, maxC, noEllipsis, clipSide) end
        end
        mock._nameFS:SetText(previewName)
        mock._nameFS:SetTextColor(fr or 1, fg or 1, fb or 1, textAlpha)
        mock._nameFS:ClearAllPoints()
        local pad4 = ScaleValue(4, previewScale, 1)
        local nox = ConfigToOffset(runtimeText.nameX or conf.nameOffsetX or 0, previewScale)
        local noy = ConfigToOffset(runtimeText.nameY or ((conf.nameOffsetY or 0) + baselineOffset), previewScale)
        local nameAnchor = runtimeText.nameAnchor or conf.nameAnchor or "LEFT"
        local nameWidth = max(80, (tonumber(runtimeSpec and runtimeSpec.width) or liveW or 120) * 0.80)
        mock._nameFS:SetWidth(max(40, ScaleValue(nameWidth, previewScale, 40)))
        if nameAnchor == "CENTER" then
            LayoutPreviewText(mock._nameFS, "TOP", "TOP", nox, noy, "CENTER", mock)
        elseif nameAnchor == "RIGHT" then
            LayoutPreviewText(mock._nameFS, "TOPRIGHT", "TOPRIGHT", -nox, noy, "RIGHT", mock)
        else
            LayoutPreviewText(mock._nameFS, "TOPLEFT", "TOPLEFT", nox, noy, "LEFT", mock)
        end
        if mock._nameFS.SetWordWrap then mock._nameFS:SetWordWrap(false) end
        if mock._nameFS.SetNonSpaceWrap then mock._nameFS:SetNonSpaceWrap(false) end
        mock._nameFS:SetShown(showText and ((runtimeSpec and runtimeSpec.showName == true) or (not runtimeSpec and conf.showName ~= false)))
        local hpSize = max(7, ScaleValue((runtimeSpec and runtimeSpec.healthFontSize) or conf.hpFontSize or 10, previewScale, 6))
        local hpTextOn = showText and ((runtimeSpec and runtimeSpec.showHealthText == true) or (not runtimeSpec and conf.showHPText ~= false))
        local hpLeftMode, hpCenterMode, hpRightMode
        if runtimeSpec then
            hpLeftMode, hpCenterMode, hpRightMode = runtimeText.healthLeft or "NONE", runtimeText.healthCenter or "NONE", runtimeText.healthRight or "NONE"
        elseif gf and gf.ResolveHealthTextSlots then
            hpLeftMode, hpCenterMode, hpRightMode = gf.ResolveHealthTextSlots(conf)
        else
            hpLeftMode, hpCenterMode, hpRightMode = runtimeText.healthLeft or conf.textLeft or "NONE", runtimeText.healthCenter or conf.textCenter or "NONE", runtimeText.healthRight or conf.textRight or "NONE"
        end
        local function GlobalHidePercentSymbol()
            local db = M.EnsureDB and M.EnsureDB()
            local g = db and db.general
            return g and g.hidePercentSymbol == true
        end
        local function SlotHidePercentSymbol(runtimeKey, dbKey)
            local value = runtimeText and runtimeText[runtimeKey]
            if value ~= nil then return value == true end
            if conf and conf[dbKey] ~= nil then return conf[dbKey] == true end
            return GlobalHidePercentSymbol()
        end
        local hpLeftHidePercent = SlotHidePercentSymbol("healthLeftHidePercentSymbol", "hpTextLeftHidePercentSymbol")
        local hpCenterHidePercent = SlotHidePercentSymbol("healthCenterHidePercentSymbol", "hpTextCenterHidePercentSymbol")
        local hpRightHidePercent = SlotHidePercentSymbol("healthRightHidePercentSymbol", "hpTextRightHidePercentSymbol")
        if runtimeSpec and runtimeText.healthReverse == true then
            hpLeftMode, hpRightMode = hpRightMode, hpLeftMode
            if gf and gf.ReverseHealthTextMode then
                hpLeftMode = gf.ReverseHealthTextMode(hpLeftMode)
                hpCenterMode = gf.ReverseHealthTextMode(hpCenterMode)
                hpRightMode = gf.ReverseHealthTextMode(hpRightMode)
            end
            hpLeftHidePercent, hpRightHidePercent = hpRightHidePercent, hpLeftHidePercent
        elseif (not runtimeSpec) and conf and conf.hpTextReverse == true then
            hpLeftHidePercent, hpRightHidePercent = hpRightHidePercent, hpLeftHidePercent
        end
        local fakeMax = 1000000
        local fakeHP = max(1, floor(fakeMax * hpPct + 0.5))
        local hpTextR, hpTextG, hpTextB = fr or 1, fg or 1, fb or 1
        if runtimeText.healthColorByHealth == true then
            local pct = fakeHP / fakeMax
            if pct <= 0.5 then
                hpTextR, hpTextG, hpTextB = 1, pct * 2, 0
            else
                hpTextR, hpTextG, hpTextB = (1 - pct) * 2, 1, 0
            end
        end
        local hpDelimiter = runtimeText.healthDelimiter or conf.textDelimiter or " - "
        local function PreviewHealthText(mode, hidePercentSymbol)
            if gf and gf.FormatHealthText then return gf.FormatHealthText(mode, fakeHP, fakeMax, hpDelimiter, false, nil, hidePercentSymbol) end
            return mode == "PERCENT" and (hidePercentSymbol and "72" or "72%") or "720k"
        end
        PaintPreviewText(mock._hpLeftFS, hpSize, hpLeftMode, "LEFT", "LEFT",
            pad4 + ConfigToOffset(runtimeText.healthLeftX or ((conf.hpOffsetX or 0) + (conf.hpTextLeftOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.healthLeftY or ((conf.hpOffsetY or 0) + (conf.hpTextLeftOffsetY or 0) + baselineOffset), previewScale),
            "LEFT", hpTextR, hpTextG, hpTextB, textAlpha, hpTextOn, PreviewHealthText(hpLeftMode, hpLeftHidePercent))
        PaintPreviewText(mock._hpCenterFS, hpSize, hpCenterMode, "CENTER", "CENTER",
            ConfigToOffset(runtimeText.healthCenterX or ((conf.hpOffsetX or 0) + (conf.hpTextCenterOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.healthCenterY or ((conf.hpOffsetY or 0) + (conf.hpTextCenterOffsetY or 0) + baselineOffset), previewScale),
            "CENTER", hpTextR, hpTextG, hpTextB, textAlpha, hpTextOn, PreviewHealthText(hpCenterMode, hpCenterHidePercent))
        PaintPreviewText(mock._hpRightFS, hpSize, hpRightMode, "RIGHT", "RIGHT",
            -pad4 + ConfigToOffset(runtimeText.healthRightX or ((conf.hpOffsetX or 0) + (conf.hpTextRightOffsetX or 0)), previewScale),
            ConfigToOffset(runtimeText.healthRightY or ((conf.hpOffsetY or 0) + (conf.hpTextRightOffsetY or 0) + baselineOffset), previewScale),
            "RIGHT", hpTextR, hpTextG, hpTextB, textAlpha, hpTextOn, PreviewHealthText(hpRightMode, hpRightHidePercent))
        local pwrSize = max(6, ScaleValue((runtimeSpec and runtimeSpec.powerFontSize) or conf.powerFontSize or 9, previewScale, 6))
        local showPowerText = showText
        if runtimeSpec then
            showPowerText = showText and runtimeSpec.showPowerText == true
        elseif gf and gf.IsPowerTextEnabled then
            showPowerText = showText and gf.IsPowerTextEnabled(kind, conf)
        end
        local fakePowMax = 100
        local fakePow = max(0, floor(fakePowMax * powerPct + 0.5))
        local powerDelimiter = runtimeText.powerDelimiter or conf.powerTextDelimiter or conf.textDelimiter or " - "
        local function PreviewPowerText(mode, hidePercentSymbol)
            if gf and gf.FormatPowerText then return gf.FormatPowerText(mode, fakePow, fakePowMax, powerDelimiter, nil, hidePercentSymbol) end
            return mode == "PERCENT" and (hidePercentSymbol and "70" or "70%") or "70"
        end
        local powerLeftMode = runtimeText.powerLeft or conf.powerTextLeft or "NONE"
        local powerCenterMode = runtimeText.powerCenter or conf.powerTextCenter or "NONE"
        local powerRightMode = runtimeText.powerRight or conf.powerTextRight or "NONE"
        local powerLeftHidePercent = SlotHidePercentSymbol("powerLeftHidePercentSymbol", "powerTextLeftHidePercentSymbol")
        local powerCenterHidePercent = SlotHidePercentSymbol("powerCenterHidePercentSymbol", "powerTextCenterHidePercentSymbol")
        local powerRightHidePercent = SlotHidePercentSymbol("powerRightHidePercentSymbol", "powerTextRightHidePercentSymbol")
        PaintPreviewText(mock._powerLeftFS, pwrSize, powerLeftMode, "BOTTOMLEFT", "BOTTOMLEFT",
            pad4 + ConfigToOffset(runtimeText.powerLeftX or ((conf.powerOffsetX or 0) + (conf.powerTextLeftOffsetX or 0)), previewScale),
            ConfigToOffset(1 + (runtimeText.powerLeftY or ((conf.powerOffsetY or 0) + (conf.powerTextLeftOffsetY or 0) + baselineOffset)), previewScale),
            "LEFT", fr or 1, fg or 1, fb or 1, textAlpha, showPowerText, PreviewPowerText(powerLeftMode, powerLeftHidePercent))
        PaintPreviewText(mock._powerCenterFS, pwrSize, powerCenterMode, "BOTTOM", "BOTTOM",
            ConfigToOffset(runtimeText.powerCenterX or ((conf.powerOffsetX or 0) + (conf.powerTextCenterOffsetX or 0)), previewScale),
            ConfigToOffset(1 + (runtimeText.powerCenterY or ((conf.powerOffsetY or 0) + (conf.powerTextCenterOffsetY or 0) + baselineOffset)), previewScale),
            "CENTER", fr or 1, fg or 1, fb or 1, textAlpha, showPowerText, PreviewPowerText(powerCenterMode, powerCenterHidePercent))
        PaintPreviewText(mock._powerRightFS, pwrSize, powerRightMode, "BOTTOMRIGHT", "BOTTOMRIGHT",
            -pad4 + ConfigToOffset(runtimeText.powerRightX or ((conf.powerOffsetX or 0) + (conf.powerTextRightOffsetX or 0)), previewScale),
            ConfigToOffset(1 + (runtimeText.powerRightY or ((conf.powerOffsetY or 0) + (conf.powerTextRightOffsetY or 0) + baselineOffset)), previewScale),
            "RIGHT", fr or 1, fg or 1, fb or 1, textAlpha, showPowerText, PreviewPowerText(powerRightMode, powerRightHidePercent))
        self._bounds:ClearAllPoints()
        local boundsEdge = max(1, outlineEdge)
        self._bounds:SetPoint("TOPLEFT", mock, "TOPLEFT", -boundsEdge, boundsEdge)
        self._bounds:SetSize(mockW + boundsEdge * 2, mockH + boundsEdge * 2)
        if self._bounds.SetFrameLevel and mock.GetFrameLevel then self._bounds:SetFrameLevel((mock:GetFrameLevel() or 1) + (Layers.PREVIEW_BOUNDS_OFFSET or 48)) end
        self._bounds:SetShown(LayerOn("bounds"))
        local function LayoutHandle(handle, anchor, x, y, defaultAnchor)
            anchor = anchor or defaultAnchor or "CENTER"
            if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaultAnchor or "CENTER" end
            handle._previewScale = previewScale
            handle._previewWriteScale = previewScale
            handle:ClearAllPoints()
            handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))
        end
        local auraDynamicScale = (runtimeAuras and runtimeAuras.dynamicScaleValue) or (gf and gf.GetPreviewDynamicScale and gf.GetPreviewDynamicScale(conf, kind)) or 1
        local function RuntimeAuraGrowth(growth)
            if growth == "LEFTUP" then
                return -1, 1, false, "BOTTOMRIGHT"
            elseif growth == "LEFTDOWN" then
                return -1, -1, false, "TOPRIGHT"
            elseif growth == "RIGHTUP" then
                return 1, 1, false, "BOTTOMLEFT"
            elseif growth == "UP" or growth == "UPRIGHT" or growth == "UPLEFT" then
                return 1, 1, true, "BOTTOMLEFT"
            elseif growth == "DOWN" or growth == "DOWNRIGHT" or growth == "DOWNLEFT" then
                return 1, -1, true, "TOPLEFT"
            end
            return 1, -1, false, "TOPLEFT"
        end
        local function RuntimeAuraAnchor(anchor, fallback)
            if anchor == "TOPLEFT" or anchor == "TOPRIGHT"
                or anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT"
                or anchor == "CENTER" then
                return anchor
            end
            return fallback or "CENTER"
        end
        local function RuntimeAuraTextAnchor(anchor, fallback)
            if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT"
                or anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT"
                or anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                return anchor
            end
            return fallback or "CENTER"
        end
        local function NormalizeDispelBorderMode(value, legacyEnabled)
            if value == true then return "SYMBOL" end
            if value == false then return "OFF" end
            value = tostring(value or ""):upper()
            if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
            if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
                or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
                return "SYMBOL"
            end
            if value == "OFF" or value == "NONE" or value == "DISABLED" then return legacyEnabled == true and "SYMBOL" or "OFF" end
            return legacyEnabled == true and "SYMBOL" or "OFF"
        end
        local function PlaceAuraPreviewText(fs, relativeTo, anchor, x, y)
            if not (fs and relativeTo) then return end
            anchor = RuntimeAuraTextAnchor(anchor, "CENTER")
            fs:ClearAllPoints()
            fs:SetPoint(anchor, relativeTo, anchor, x or 0, y or 0)
            if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
                fs:SetJustifyH("LEFT")
            elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
                fs:SetJustifyH("RIGHT")
            else
                fs:SetJustifyH("CENTER")
            end
            if fs.SetJustifyV then
                if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
                    fs:SetJustifyV("TOP")
                elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                    fs:SetJustifyV("BOTTOM")
                else
                    fs:SetJustifyV("MIDDLE")
                end
            end
        end
        local function LayoutAuraPreviewBorder(border, icon, size, mode)
            local atlas = DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[mode]
            if not (border and icon and atlas and border.SetAtlas) then
                if border then border:Hide() end
                return
            end
            local pad = max(1, floor((tonumber(size) or 24) / 24 + 0.5))
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
            border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
            border:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
            border:Show()
        end
        local function PreviewAuraState(groupKey, index, handle, cfg)
            if not (self._animationEnabled == true and handle) then return nil end
            local buildAuraState = previewAnimation and previewAnimation.BuildAuraState or _G.MSUF_BuildPreviewAnimationAuraState
            if type(buildAuraState) ~= "function" then return nil end
            handle._previewAuraStates = handle._previewAuraStates or {}
            local scratch = handle._previewAuraStates[index] or {}
            handle._previewAuraStates[index] = scratch
            return buildAuraState(groupKey, index, scratch, {
                decimalSeconds = cfg and cfg.cooldownDecimalSeconds == true,
            }, self._animationElapsed)
        end
        local function LayoutAuraPreviewSwipe(swipe, icon, size, remainingFrac, reverse)
            if not (swipe and icon) then return end
            remainingFrac = max(0.02, min(1, tonumber(remainingFrac) or 0.48))
            local w = max(1, floor((tonumber(size) or 1) * remainingFrac + 0.5))
            swipe:ClearAllPoints()
            swipe:SetWidth(w)
            swipe:SetHeight(max(1, tonumber(size) or 1))
            if reverse == true then
                swipe:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
                swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
            else
                swipe:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
                swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            end
        end
        local function LayoutAuraDurationBar(bar, icon, cfg, size, auraState)
            if not (bar and icon and cfg and cfg.showDurationBar == true) then
                if bar then bar:Hide() end
                return
            end
            size = max(1, tonumber(size) or 1)
            local height = max(1, min(size, floor((tonumber(cfg.durationBarHeight) or 2) + 0.5)))
            local inset = max(1, floor(size / 32 + 0.5))
            local frac
            if cfg.durationBarDirection == "ELAPSED" then
                frac = auraState and auraState.elapsedFrac or 0.38
                bar:SetVertexColor(0.22, 0.88, 0.50, 0.92)
            else
                frac = auraState and auraState.remainingFrac or 0.62
                bar:SetVertexColor(0.08, 0.78, 1.00, 0.92)
            end
            frac = max(0.02, min(1, tonumber(frac) or 0.62))
            bar:ClearAllPoints()
            bar:SetHeight(height)
            if auraState then
                bar:SetWidth(max(1, floor(max(1, size - inset * 2) * frac + 0.5)))
                if cfg.durationBarPosition == "TOP" then
                    bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
                else
                    bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
                end
            elseif cfg.durationBarPosition == "TOP" then
                bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
                bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
            else
                bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
                bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
            end
            bar:Show()
        end
        local function RuntimeAuraGridShape(count, perRow, verticalGrowth)
            count = max(Round(count), 1)
            perRow = max(Round(perRow), 1)
            if verticalGrowth == true then
                local rows = min(count, perRow)
                return ceil(count / perRow), rows
            end
            local cols = min(count, perRow)
            return cols, ceil(count / perRow)
        end
        local function LayoutAuraGroup(handle, groupKey, cfg, defaults)
            cfg = cfg or {}
            defaults = defaults or {}
            local maxIcons = Int(cfg.max, defaults.max or 6, 0, 40)
            local perRow = Int(cfg.perRow, defaults.perRow or maxIcons, 1, 40)
            local rawSize = cfg.size or defaults.size or 16
            local minSize = defaults.minSize or 8
            local laneScale = cfg._compiled and previewScale or (previewScale * auraDynamicScale)
            local size = max(minSize, ScaleValue(rawSize, laneScale, minSize))
            local spacing = max(0, ScaleValue(cfg.spacing or defaults.spacing or 1, previewScale, 0))
            local anchor = RuntimeAuraAnchor(cfg.anchor, defaults.anchor or "CENTER")
            if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaults.anchor or "CENTER" end
            if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = "CENTER" end
            local textScale = cfg._compiled and previewScale or laneScale
            local showCooldown = cfg.showCooldown ~= false
            local showStacks = cfg.showStacks ~= false
            local showSwipe = cfg.showCooldownSwipe ~= false
            local barOnly = cfg.showDurationBar == true and (cfg.durationBarDisplay or "BAR_ONLY") == "BAR_ONLY"
            local cooldownSwipeReverse = cfg.cooldownSwipeReverse == true
            local cooldownSize = max(6, ScaleValue(cfg.cooldownSize or defaults.cooldownSize or 8, textScale, 6))
            local stackSize = max(6, ScaleValue(cfg.stackSize or defaults.stackSize or 10, textScale, 6))
            local cooldownAnchor = RuntimeAuraTextAnchor(cfg.cooldownAnchor, "CENTER")
            local stackAnchor = RuntimeAuraTextAnchor(cfg.stackAnchor, "BOTTOMRIGHT")
            local cooldownX = ConfigToOffset(cfg.cooldownX or 0, textScale)
            local cooldownY = ConfigToOffset(cfg.cooldownY or 0, textScale)
            local stackX = ConfigToOffset(cfg.stackX or 0, textScale)
            local stackY = ConfigToOffset(cfg.stackY or 0, textScale)
            local dispelMode = groupKey == "debuff" and NormalizeDispelBorderMode(cfg.dispelBorderMode, cfg.showDispelBorder == true or cfg.showDispelSymbol == true) or "OFF"
            local growth = cfg.growth or defaults.growth or "RIGHTDOWN"
            local gv = AuraGrowth(growth)
            local anchorTarget = mock
            local anchorFrac = GF_PREVIEW_ANCHOR_FRAC[anchor] or GF_PREVIEW_ANCHOR_FRAC.CENTER
            local ids = GF_AURA_MOCK_ICON_IDS[groupKey] or GF_AURA_MOCK_ICON_IDS.debuff
            local step = size + spacing
            AddIconPool(handle, maxIcons)
            handle._previewRects = handle._previewRects or {}
            local handleW, handleH, originX, originY
            if gv.centered then
                local minL, minB, maxR, maxT
                for i = 1, maxIcons do
                    local left, bottom
                    local totalPrimary = maxIcons * size + max(0, maxIcons - 1) * spacing
                    local halfOfs = totalPrimary * 0.5
                    local col = i - 1
                    if gv.px ~= 0 then
                        local cx = col * step - halfOfs + size * 0.5
                        left, bottom = cx - size * 0.5, -size * 0.5
                    else
                        local cy = -(col * step - halfOfs) - size * 0.5
                        left, bottom = -size * 0.5, cy - size * 0.5
                    end
                    local right, top = left + size, bottom + size
                    local rect = handle._previewRects[i] or {}
                    rect[1], rect[2], rect.anchor = left, bottom, nil
                    handle._previewRects[i] = rect
                    minL = minL and min(minL, left) or left
                    minB = minB and min(minB, bottom) or bottom
                    maxR = maxR and max(maxR, right) or right
                    maxT = maxT and max(maxT, top) or top
                end
                if not minL then minL, minB, maxR, maxT = -size * 0.5, -size * 0.5, size * 0.5, size * 0.5 end
                handleW = max(1, Round(maxR - minL))
                handleH = max(1, Round(maxT - minB))
                originX, originY = -minL, -minB
            else
                local xSign, ySign, verticalGrowth, initialAnchor = RuntimeAuraGrowth(growth)
                local cols, rows = RuntimeAuraGridShape(maxIcons, perRow, verticalGrowth)
                handleW = max(1, Round(cols * size + max(cols - 1, 0) * spacing))
                handleH = max(1, Round(rows * size + max(rows - 1, 0) * spacing))
                originX = Round(anchorFrac[1] * handleW)
                originY = Round(anchorFrac[2] * handleH)
                for i = 1, maxIcons do
                    local idx = i - 1
                    local col, row
                    if verticalGrowth == true then
                        row = idx % perRow
                        col = (idx - row) / perRow
                    else
                        col = idx % perRow
                        row = (idx - col) / perRow
                    end
                    local rect = handle._previewRects[i] or {}
                    rect[1], rect[2], rect.anchor = col * step * xSign, row * step * ySign, initialAnchor
                    handle._previewRects[i] = rect
                end
            end
            handle:SetSize(handleW, handleH)
            handle._previewOriginX = originX
            handle._previewOriginY = originY
            handle._previewAnchorFrame = anchorTarget
            handle._previewScale = previewScale
            handle._previewWriteScale = cfg._compiled and (previewScale * max(0.0001, auraDynamicScale)) or previewScale
            handle:ClearAllPoints()
            if gv.centered then
                handle:SetPoint(
                    "BOTTOMLEFT",
                    anchorTarget,
                    "CENTER",
                    ConfigToOffset(cfg.x or 0, previewScale) - originX,
                    ConfigToOffset(cfg.y or 0, previewScale) - originY
                )
            else
                handle:SetPoint(
                    anchor,
                    anchorTarget,
                    anchor,
                    ConfigToOffset(cfg.x or 0, previewScale),
                    ConfigToOffset(cfg.y or 0, previewScale)
                )
            end
            for i = 1, maxIcons do
                local tex = handle._icons and handle._icons[i]
                local swipe = handle._iconSwipes and handle._iconSwipes[i]
                local border = handle._iconBorders and handle._iconBorders[i]
                local stack = handle._iconStacks and handle._iconStacks[i]
                local timer = handle._iconTimers and handle._iconTimers[i]
                local durationBar = handle._iconDurationBars and handle._iconDurationBars[i]
                local rect = handle._previewRects[i]
                if tex and rect then
                    local auraState = PreviewAuraState(groupKey, i, handle, cfg)
                    tex:SetTexture(MockSpellTexture(ids[((i - 1) % #ids) + 1]))
                    if tex.SetAlpha then tex:SetAlpha(barOnly and 0 or 1) end
                    tex:SetSize(size, size)
                    tex:ClearAllPoints()
                    if rect.anchor then
                        tex:SetPoint(rect.anchor, handle, rect.anchor, rect[1], rect[2])
                    else
                        tex:SetPoint("BOTTOMLEFT", handle, "BOTTOMLEFT", rect[1] + originX, rect[2] + originY)
                    end
                    if swipe then
                        if showSwipe and not barOnly then
                            LayoutAuraPreviewSwipe(swipe, tex, size, auraState and auraState.remainingFrac, cooldownSwipeReverse)
                            swipe:Show()
                        else
                            swipe:Hide()
                        end
                    end
                    LayoutAuraPreviewBorder(border, tex, size, barOnly and "OFF" or dispelMode)
                    LayoutAuraDurationBar(durationBar, tex, cfg, size, auraState)
                    if stack then
                        SetPreviewFont(stack, stackSize)
                        stack:SetTextColor(1, 1, 1, 1)
                        PlaceAuraPreviewText(stack, tex, stackAnchor, stackX, stackY)
                        stack:SetText(showStacks and (auraState and auraState.stacks or (i % 3 == 1 and "2" or "")) or "")
                        stack:SetShown(showStacks)
                    end
                    if timer then
                        SetPreviewFont(timer, cooldownSize)
                        timer:SetTextColor(1, 1, 1, 1)
                        PlaceAuraPreviewText(timer, tex, cooldownAnchor, cooldownX, cooldownY)
                        timer:SetText(showCooldown and (auraState and auraState.text or (i % 2 == 0 and "12" or "")) or "")
                        timer:SetShown(showCooldown)
                    end
                    tex:Show()
                end
            end
            for i = maxIcons + 1, #(handle._icons or {}) do
                if handle._icons[i] then handle._icons[i]:Hide() end
                if handle._iconSwipes and handle._iconSwipes[i] then handle._iconSwipes[i]:Hide() end
                if handle._iconBorders and handle._iconBorders[i] then handle._iconBorders[i]:Hide() end
                if handle._iconStacks and handle._iconStacks[i] then handle._iconStacks[i]:Hide() end
                if handle._iconTimers and handle._iconTimers[i] then handle._iconTimers[i]:Hide() end
                if handle._iconDurationBars and handle._iconDurationBars[i] then handle._iconDurationBars[i]:Hide() end
            end
            return size
        end
        LayoutAuraGroup(buffHandle, "buff", buffCfg, {
            anchor = "BOTTOMRIGHT", growth = "LEFTUP",
            size = 22, perRow = 4, max = 6, spacing = 1, minSize = 8,
        })
        if trackedBuffHandle then
            LayoutAuraGroup(trackedBuffHandle, "trackedBuff", trackedBuffCfg, {
                anchor = "TOPLEFT", growth = "RIGHTDOWN",
                size = 22, perRow = 4, max = 4, spacing = 1, minSize = 8,
            })
        end
        LayoutAuraGroup(debuffHandle, "debuff", debuffCfg, {
            anchor = "TOPLEFT", growth = "RIGHTDOWN",
            size = 20, perRow = 3, max = 6, spacing = 1, minSize = 8,
        })
        local function TargetedAnchor(anchor)
            if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT"
                or anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT"
                or anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                return anchor
            end
            return "CENTER"
        end
        local function TargetedGrow(grow)
            if grow == "LEFT" or grow == "UP" or grow == "DOWN" or grow == "CENTER" then return grow end
            return "RIGHT"
        end
        local function TargetedNumber(key, fallback, minValue, maxValue)
            local value = tonumber(conf[key])
            if value == nil then value = fallback or 0 end
            if minValue ~= nil and value < minValue then value = minValue end
            if maxValue ~= nil and value > maxValue then value = maxValue end
            return value
        end

        local function LayoutTargetedSpells()
            if not targetedHandle then return end
            local maxIcons = Int(conf.targetedSpellsMaxIcons, 3, 1, 5)
            local size = max(8, ScaleValue(conf.targetedSpellsIconSize or 24, previewScale, 8))
            local gap = max(1, ScaleValue(2, previewScale, 1))
            local step = size + gap
            local anchor = TargetedAnchor(conf.targetedSpellsAnchor)
            local grow = TargetedGrow(conf.targetedSpellsGrow)
            local frac = GF_PREVIEW_ANCHOR_FRAC[anchor] or GF_PREVIEW_ANCHOR_FRAC.CENTER
            local ids = (GF_AURA_MOCK_ICON_IDS and GF_AURA_MOCK_ICON_IDS.targeted) or { 116, 133, 51505, 20484, 257044 }
            if #ids == 0 then ids = { 116, 133, 51505, 20484, 257044 } end
            AddIconPool(targetedHandle, maxIcons)
            targetedHandle._previewRects = targetedHandle._previewRects or {}
            local minL, minB, maxR, maxT
            local centeredOffset = grow == "CENTER" and -((maxIcons - 1) * step * 0.5) or 0
            for i = 1, maxIcons do
                local offset = (i - 1) * step
                local ax, ay = offset, 0
                if grow == "CENTER" then
                    ax = centeredOffset + offset
                elseif grow == "LEFT" then
                    ax = -offset
                elseif grow == "UP" then
                    ax, ay = 0, offset
                elseif grow == "DOWN" then
                    ax, ay = 0, -offset
                end
                local left = ax - ((frac and frac[1]) or 0.5) * size
                local bottom = ay - ((frac and frac[2]) or 0.5) * size
                local right, top = left + size, bottom + size
                local rect = targetedHandle._previewRects[i] or {}
                rect[1], rect[2] = left, bottom
                targetedHandle._previewRects[i] = rect
                minL = minL and min(minL, left) or left
                minB = minB and min(minB, bottom) or bottom
                maxR = maxR and max(maxR, right) or right
                maxT = maxT and max(maxT, top) or top
            end
            if not minL then minL, minB, maxR, maxT = -size * 0.5, -size * 0.5, size * 0.5, size * 0.5 end
            local handleW = max(1, Round(maxR - minL))
            local handleH = max(1, Round(maxT - minB))
            local originX, originY = -minL, -minB
            targetedHandle:SetSize(handleW, handleH)
            targetedHandle._previewOriginX = originX
            targetedHandle._previewOriginY = originY
            targetedHandle._previewAnchorFrame = mock
            targetedHandle._previewScale = previewScale
            targetedHandle._previewWriteScale = previewScale
            targetedHandle._previewText = "Targeted Spells"
            targetedHandle:ClearAllPoints()
            targetedHandle:SetPoint("BOTTOMLEFT", mock, anchor,
                ConfigToOffset(conf.targetedSpellsX or 0, previewScale) - originX,
                ConfigToOffset(conf.targetedSpellsY or 0, previewScale) - originY)
            for i = 1, maxIcons do
                local tex = targetedHandle._icons and targetedHandle._icons[i]
                local swipe = targetedHandle._iconSwipes and targetedHandle._iconSwipes[i]
                local timer = targetedHandle._iconTimers and targetedHandle._iconTimers[i]
                local border = targetedHandle._iconBorders and targetedHandle._iconBorders[i]
                local stack = targetedHandle._iconStacks and targetedHandle._iconStacks[i]
                local rect = targetedHandle._previewRects[i]
                if tex and rect then
                    tex:SetTexture(MockSpellTexture(ids[((i - 1) % #ids) + 1]))
                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    tex:SetVertexColor(1, 1, 1, 1)
                    tex:SetSize(size, size)
                    tex:ClearAllPoints()
                    tex:SetPoint("BOTTOMLEFT", targetedHandle, "BOTTOMLEFT", rect[1] + originX, rect[2] + originY)
                    tex:Show()
                    if swipe then
                        swipe:ClearAllPoints()
                        swipe:SetPoint("TOPLEFT", tex, "TOP", 0, 0)
                        swipe:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
                        swipe:SetShown(true)
                    end
                    if timer then
                        timer:SetText("")
                        timer:Hide()
                    end
                    if border then border:Hide() end
                    if stack then stack:Hide() end
                end
            end
            for i = maxIcons + 1, #(targetedHandle._icons or {}) do
                if targetedHandle._icons[i] then targetedHandle._icons[i]:Hide() end
                if targetedHandle._iconSwipes and targetedHandle._iconSwipes[i] then targetedHandle._iconSwipes[i]:Hide() end
                if targetedHandle._iconBorders and targetedHandle._iconBorders[i] then targetedHandle._iconBorders[i]:Hide() end
                if targetedHandle._iconStacks and targetedHandle._iconStacks[i] then targetedHandle._iconStacks[i]:Hide() end
                if targetedHandle._iconTimers and targetedHandle._iconTimers[i] then targetedHandle._iconTimers[i]:Hide() end
            end
        end
        LayoutTargetedSpells()
        local function ConfigureStatusHandle(statusHandle)
            local spec = statusHandle and statusHandle._statusSpec
            if not (statusHandle and spec) then return end
            local runtimeCfg = RuntimeStatusConfig(runtimeStatus, spec)
            local enabled
            if runtimeSpec then
                enabled = runtimeCfg and runtimeCfg.enabled == true
            else
                enabled = StatusSpecEnabled(conf, spec)
            end
            local statusIsText = StatusSpecIsText(spec)
            local statusRawSize = tonumber(runtimeCfg and runtimeCfg.size) or tonumber(conf[spec.size]) or tonumber(spec.defaultSize) or 14
            local statusSize = ScaleValue(statusRawSize, previewScale, statusIsText and 10 or 8)
            statusHandle._previewText = spec.text or "Status"
            if statusHandle._label and statusHandle._label.SetText then
                statusHandle._label:SetText(StatusLabel(spec))
                statusHandle._label:SetTextColor(0.80, 0.67, 0.20, enabled and 0.95 or 0.55)
            end
            if statusIsText then
                statusHandle:SetSize(max(42, statusSize * 4), max(18, statusSize + 8))
                if statusHandle._statusText and statusHandle._statusText.SetFont then SetPreviewFont(statusHandle._statusText, max(12, statusSize)) end
                if statusHandle._statusText then
                    statusHandle._statusText:SetText(StatusText(spec))
                    statusHandle._statusText:SetTextColor(enabled and 1 or 0.45, enabled and 1 or 0.45, enabled and 1 or 0.50, enabled and 1 or 0.60)
                    statusHandle._statusText:ClearAllPoints()
                    statusHandle._statusText:SetPoint("CENTER", statusHandle, "CENTER", 0, 0)
                    statusHandle._statusText:Show()
                end
                if statusHandle._statusTex then statusHandle._statusTex:Hide() end
            else
                statusSize = max(8, statusSize)
                statusHandle:SetSize(statusSize, statusSize)
                if statusHandle._statusText then statusHandle._statusText:Hide() end
                local tex = statusHandle._statusTex
                if tex then
                    local path, atlas, l, r, t, b = nil, nil, 0, 1, 0, 1
                    local value = spec.value
                    if runtimeCfg and type(runtimeCfg.customIcon) == "string" and runtimeCfg.customIcon ~= "" then
                        path, l, r, t, b = runtimeCfg.customIcon, 0, 1, 0, 1
                    elseif spec.customIcon and type(conf[spec.customIcon]) == "string" and conf[spec.customIcon] ~= "" then
                        path, l, r, t, b = conf[spec.customIcon], 0, 1, 0, 1
                    elseif value == "roleIcon" and gf and gf.GetRoleTexture then
                        path, l, r, t, b = gf.GetRoleTexture(kind, GF_PREVIEW_ROLE, runtimeCfg and runtimeCfg.style)
                    elseif value == "leaderIcon" and gf and gf.GetLeaderTexture then
                        path, l, r, t, b = gf.GetLeaderTexture(kind, runtimeCfg and runtimeCfg.style)
                    elseif value == "assistIcon" and gf and gf.GetAssistTexture then
                        path, l, r, t, b = gf.GetAssistTexture(kind, runtimeCfg and runtimeCfg.style)
                    elseif value == "raidMarker" then
                        path, l, r, t, b = ResolveStatusPreviewTexture(spec, runtimeCfg, "raidMarker", 1)
                    elseif value == "readyCheckIcon" then
                        path, l, r, t, b = ResolveStatusPreviewTexture(spec, runtimeCfg, "readyCheck", "ready")
                    elseif value == "summonIcon" then
                        path, l, r, t, b = ResolveStatusPreviewTexture(spec, runtimeCfg, "summon", 1)
                    elseif value == "resurrectIcon" then
                        path, l, r, t, b = ResolveStatusPreviewTexture(spec, runtimeCfg, "incomingRes", "resurrect")
                    elseif value == "pvpIcon" then
                        path, l, r, t, b = ResolveStatusPreviewTexture(spec, runtimeCfg, "pvp", "Alliance")
                    elseif value == "phaseIcon" then
                        path, l, r, t, b = ResolveStatusPreviewTexture(spec, runtimeCfg, "phase", "phase")
                    end
                    if atlas or path then
                        if atlas and tex.SetAtlas then
                            tex:SetAtlas(atlas)
                        else
                            tex:SetTexture(path or "Interface\\TargetingFrame\\UI-PVP-Alliance")
                            tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                        end
                        if enabled then
                            tex:SetVertexColor(1, 1, 1, 1)
                        else
                            tex:SetVertexColor(0.40, 0.40, 0.45, 0.55)
                        end
                        tex:ClearAllPoints()
                        tex:SetPoint("TOPLEFT", statusHandle, "TOPLEFT", 0, 0)
                        tex:SetPoint("BOTTOMRIGHT", statusHandle, "BOTTOMRIGHT", 0, 0)
                        tex:Show()
                    else
                        tex:Hide()
                    end
                end
            end
            LayoutHandle(statusHandle,
                runtimeCfg and runtimeCfg.anchor or conf[spec.anchor],
                runtimeCfg and runtimeCfg.x or conf[spec.x],
                runtimeCfg and runtimeCfg.y or conf[spec.y],
                spec.defaultAnchor or "CENTER")
        end
        for i = 1, #statusHandles do
            ConfigureStatusHandle(statusHandles[i])
        end
        local dynamicSpellHandlesActive = {}
        local dynamicSpellHandlesUsed = false
        local function ConfigureSpellPreviewHandle(handle, item, placed, fallbackTexture, fallbackColor)
            if not (handle and placed) then return false end
            local spellType = placed.type or "icon"
            local spellBaseSize = tonumber(placed.size) or 20
            local spellSize = max(14, ScaleValue(spellBaseSize, previewScale, 10))
            local color = item and item.color or fallbackColor
            local spellR, spellG, spellB = (color and color[1]) or 0.69, (color and color[2]) or 0.50, (color and color[3]) or 0.88
            handle._icons = handle._icons or {}
            local spellTex = handle._icons[1]
            if spellType == "bar" then
                local barW = max(spellSize * 2, ScaleValue(placed.barWidth or (spellBaseSize * 3), previewScale, 16))
                handle:SetSize(barW, spellSize)
                if spellTex then
                    spellTex:SetTexture(WHITE8X8)
                    spellTex:SetTexCoord(0, 1, 0, 1)
                    spellTex:SetVertexColor(spellR, spellG, spellB, 1)
                    spellTex:ClearAllPoints()
                    spellTex:SetAllPoints(handle)
                    spellTex:Show()
                end
            elseif spellType == "square" then
                handle:SetSize(spellSize, spellSize)
                if spellTex then
                    spellTex:SetTexture(WHITE8X8)
                    spellTex:SetTexCoord(0, 1, 0, 1)
                    spellTex:SetVertexColor(spellR, spellG, spellB, 1)
                    spellTex:ClearAllPoints()
                    spellTex:SetAllPoints(handle)
                    spellTex:Show()
                end
            elseif spellType == "number" then
                handle:SetSize(max(18, spellSize), max(18, spellSize))
                if spellTex then spellTex:Hide() end
                if handle._label and handle._label.SetText then handle._label:SetText("9") end
            else
                handle:SetSize(spellSize, spellSize)
                if spellTex then
                    spellTex:SetTexture((item and item.icon) or fallbackTexture or CurrentSpellTexture(kind))
                    spellTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    spellTex:SetVertexColor(1, 1, 1, 1)
                    spellTex:ClearAllPoints()
                    spellTex:SetAllPoints(handle)
                    spellTex:Show()
                end
            end
            if spellType ~= "number" and handle._label and handle._label.SetText then
                handle._label:SetText(item and (item.display or item.auraName) or "SPELL")
            end
            LayoutHandle(handle, placed.anchor, placed.x, placed.y, "TOPLEFT")
            return true
        end
        if runtimeSpellIndicators and runtimeSpellIndicators.enabled == true and type(runtimeSpellItems) == "table" and box.EnsureSpellIndicatorHandle then
            for i = 1, #runtimeSpellItems do
                local item = runtimeSpellItems[i]
                local placed = item and item.placed
                if placed and (placed.type or "icon") ~= "none" then
                    local handle = box:EnsureSpellIndicatorHandle(item, i)
                    if handle and ConfigureSpellPreviewHandle(handle, item, placed) then
                        dynamicSpellHandlesUsed = true
                        dynamicSpellHandlesActive[handle._msufSpellIndicatorPreviewKey] = true
                    end
                end
            end
        end
        if box.HideUnusedSpellIndicatorHandles then box:HideUnusedSpellIndicatorHandles(dynamicSpellHandlesActive) end
        if dynamicSpellHandlesUsed then
            spellHandle:Hide()
        else
            local selectedSpellIcon = CurrentSpellTexture(kind)
            local spellR, spellG, spellB = CurrentSpellColor(kind)
            ConfigureSpellPreviewHandle(spellHandle, nil, selectedPlaced or { type = "icon", size = 20, anchor = "TOPLEFT", x = 0, y = 0 }, selectedSpellIcon, { spellR, spellG, spellB, 1 })
        end
        ApplySpellEffectPreview(runtimeSpellEffect)
        textHandles.name._previewScale = previewScale
        textHandles.hpGroup._previewScale = previewScale
        textHandles.hpLeft._previewScale = previewScale
        textHandles.hpCenter._previewScale = previewScale
        textHandles.hpRight._previewScale = previewScale
        textHandles.powerGroup._previewScale = previewScale
        textHandles.powerLeft._previewScale = previewScale
        textHandles.powerCenter._previewScale = previewScale
        textHandles.powerRight._previewScale = previewScale
        if not H.PlaceHandleAroundRegions(textHandles.name, mock, { mock._nameFS }, 3) then textHandles.name:Hide() end
        if H.TextMovesTogether(kind, "hp") then
            textHandles.hpLeft:Hide()
            textHandles.hpCenter:Hide()
            textHandles.hpRight:Hide()
            if not H.PlaceHandleAroundRegions(textHandles.hpGroup, mock, { mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS }, 3) then textHandles.hpGroup:Hide() end
        else
            textHandles.hpGroup:Hide()
            if not H.PlaceHandleAroundRegions(textHandles.hpLeft, mock, { mock._hpLeftFS }, 3) then textHandles.hpLeft:Hide() end
            if not H.PlaceHandleAroundRegions(textHandles.hpCenter, mock, { mock._hpCenterFS }, 3) then textHandles.hpCenter:Hide() end
            if not H.PlaceHandleAroundRegions(textHandles.hpRight, mock, { mock._hpRightFS }, 3) then textHandles.hpRight:Hide() end
        end
        if H.TextMovesTogether(kind, "power") then
            textHandles.powerLeft:Hide()
            textHandles.powerCenter:Hide()
            textHandles.powerRight:Hide()
            if not H.PlaceHandleAroundRegions(textHandles.powerGroup, mock, { mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS }, 3) then textHandles.powerGroup:Hide() end
        else
            textHandles.powerGroup:Hide()
            if not H.PlaceHandleAroundRegions(textHandles.powerLeft, mock, { mock._powerLeftFS }, 3) then textHandles.powerLeft:Hide() end
            if not H.PlaceHandleAroundRegions(textHandles.powerCenter, mock, { mock._powerCenterFS }, 3) then textHandles.powerCenter:Hide() end
            if not H.PlaceHandleAroundRegions(textHandles.powerRight, mock, { mock._powerRightFS }, 3) then textHandles.powerRight:Hide() end
        end
        H.ApplyTextFocus(self, mock)
        local baseLevel = mock.GetFrameLevel and mock:GetFrameLevel() or 1
        buffHandle:SetFrameLevel(baseLevel + ClampLayer(buffCfg.layer, 5))
        if trackedBuffHandle then trackedBuffHandle:SetFrameLevel(baseLevel + ClampLayer(trackedBuffCfg.layer, 9)) end
        debuffHandle:SetFrameLevel(baseLevel + ClampLayer(debuffCfg.layer, 6))
        for i = 1, #statusHandles do
            local handle = statusHandles[i]
            local spec = handle and handle._statusSpec
            if handle then
                local runtimeCfg = RuntimeStatusConfig(runtimeStatus, spec)
                handle:SetFrameLevel(baseLevel + ClampLayer(runtimeCfg and runtimeCfg.layer or (spec and conf[spec.layer]), spec and spec.defaultLayer or 7))
            end
        end
        local spellLayer = conf.spellIndicators and conf.spellIndicators.layer
        if runtimeSpec and runtimeSpec.spellIndicators and runtimeSpec.spellIndicators.layer ~= nil then spellLayer = runtimeSpec.spellIndicators.layer end
        spellHandle:SetFrameLevel(baseLevel + ClampLayer(spellLayer, 9))
        if targetedHandle then targetedHandle:SetFrameLevel(baseLevel + (Layers.TARGETED_SPELLS_BASE_OFFSET or 40) + ClampLayer(conf.targetedSpellsLayer, 10)) end
        textHandles.name:SetFrameLevel(baseLevel + (tonumber(runtimeText.nameLayer) or tonumber(conf.nameTextLayer) or 6))
        textHandles.hpGroup:SetFrameLevel(baseLevel + (tonumber(runtimeText.healthLayer) or tonumber(conf.textLayer) or 6))
        textHandles.hpLeft:SetFrameLevel(baseLevel + (tonumber(runtimeText.healthLayer) or tonumber(conf.textLayer) or 6))
        textHandles.hpCenter:SetFrameLevel(baseLevel + (tonumber(runtimeText.healthLayer) or tonumber(conf.textLayer) or 6))
        textHandles.hpRight:SetFrameLevel(baseLevel + (tonumber(runtimeText.healthLayer) or tonumber(conf.textLayer) or 6))
        textHandles.powerGroup:SetFrameLevel(baseLevel + (tonumber(runtimeText.powerLayer) or tonumber(conf.powerTextLayer) or 6))
        textHandles.powerLeft:SetFrameLevel(baseLevel + (tonumber(runtimeText.powerLayer) or tonumber(conf.powerTextLayer) or 6))
        textHandles.powerCenter:SetFrameLevel(baseLevel + (tonumber(runtimeText.powerLayer) or tonumber(conf.powerTextLayer) or 6))
        textHandles.powerRight:SetFrameLevel(baseLevel + (tonumber(runtimeText.powerLayer) or tonumber(conf.powerTextLayer) or 6))
        buffHandle:SetShown(layerAvailable.buff and LayerOn("buff"))
        if trackedBuffHandle then trackedBuffHandle:SetShown(layerAvailable.trackedBuff and LayerOn("trackedBuff")) end
        debuffHandle:SetShown(layerAvailable.debuff and LayerOn("debuff"))
        for i = 1, #statusHandles do
            local handle = statusHandles[i]
            local spec = handle and handle._statusSpec
            if handle then handle:SetShown(StatusSpecInMode(spec, statusSpec) and StatusConfigAvailable(spec) and LayerOn("status")) end
        end
        spellHandle:SetShown(layerAvailable.si and LayerOn("si"))
        if targetedHandle then targetedHandle:SetShown(layerAvailable.targetedSpells and LayerOn("targetedSpells")) end
        buffHandle:SetAlpha(LayerAlpha("buff") * AuraPreviewAlpha(buffCfg))
        if trackedBuffHandle then trackedBuffHandle:SetAlpha(LayerAlpha("trackedBuff") * AuraPreviewAlpha(trackedBuffCfg)) end
        debuffHandle:SetAlpha(LayerAlpha("debuff") * AuraPreviewAlpha(debuffCfg))
        for i = 1, #statusHandles do
            if statusHandles[i] then statusHandles[i]:SetAlpha(LayerAlpha("status")) end
        end
        spellHandle:SetAlpha((selectedSpellCfg and selectedSpellCfg.enabled == false) and (LayerAlpha("si") * 0.45) or LayerAlpha("si"))
        if targetedHandle then targetedHandle:SetAlpha(LayerAlpha("targetedSpells")) end
        textHandles.name:SetAlpha(LayerAlpha("text"))
        textHandles.hpGroup:SetAlpha(LayerAlpha("text"))
        textHandles.hpLeft:SetAlpha(LayerAlpha("text"))
        textHandles.hpCenter:SetAlpha(LayerAlpha("text"))
        textHandles.hpRight:SetAlpha(LayerAlpha("text"))
        textHandles.powerGroup:SetAlpha(LayerAlpha("text"))
        textHandles.powerLeft:SetAlpha(LayerAlpha("text"))
        textHandles.powerCenter:SetAlpha(LayerAlpha("text"))
        textHandles.powerRight:SetAlpha(LayerAlpha("text"))
        for i = 1, #self._layerButtons do
            local btn = self._layerButtons[i]
            local available = layerAvailable[btn._layerKey] ~= false
            btn._layerAvailable = available
            btn:SetPreviewActive(btn._sectionKey == focus, LayerOn(btn._layerKey), soloLayer == btn._layerKey, available)
        end
        if self._selectedHandle and self._selectedHandle.IsShown and not self._selectedHandle:IsShown() then SelectHandle(nil) end
        RefreshHandleSelection(self)
        if profiling then M.ProfileStop("preview", "GroupPreview.Refresh", profileStarted) end
    end
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", function(self, key)
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            self._selectedHandle = nil
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            RefreshHandleSelection(self)
            return
        end
        local handle = self._selectedHandle
        if not handle or handle._locked then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        local focusFrame = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focusFrame then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        local dx, dy = 0, 0
        if key == "LEFT" then
            dx = -1
        elseif key == "RIGHT" then
            dx = 1
        elseif key == "UP" then
            dy = 1
        elseif key == "DOWN" then
            dy = -1
        else
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        NudgeHandlePosition(handle, dx, dy)
        RefreshHandleSelection(self)
    end)
end
