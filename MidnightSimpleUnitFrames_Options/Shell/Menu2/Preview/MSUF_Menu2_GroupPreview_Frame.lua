-- Frame state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.GroupRenderFactories = M.GroupRenderFactories or {}

local function RequireFields(domain, values, fields)
    assert(type(values) == "table", domain .. " interface is required")
    for key in fields:gmatch("%S+") do
        assert(values[key] ~= nil, domain .. "." .. key .. " is required")
    end
end

M.GroupRenderFactories.Frame = function(runtime, scene, layout, layers)
    RequireFields("Frame.Runtime", runtime, "Core Menu Exports EnsureDB IsSecret")
    RequireFields("Frame.Scene", scene, "Render Stage RenderAuras AuraLanes ExtraOptions AdditionalPrefixes")
    RequireFields("Frame.Layout", layout, "PixelLayoutRegion Floor Max Min")
    RequireFields("Frame.Layers", layers, "API SetFrameLevel ElementLevel IsOn Alpha")
local MSUF, M, CoreExports, EnsureDB = runtime.Core, runtime.Menu, runtime.Exports, runtime.EnsureDB
local issecretvalue = runtime.IsSecret
local Render, Stage, RenderAuras = scene.Render, scene.Stage, scene.RenderAuras
local AURA_LANES, MENU_EXTRA_OPTIONS, ADDITIONAL_PREVIEW_PREFIXES = scene.AuraLanes, scene.ExtraOptions, scene.AdditionalPrefixes
local PixelLayoutRegion, floor, max, min = layout.PixelLayoutRegion, layout.Floor, layout.Max, layout.Min
local Layers, SetPreviewFrameLevel, PreviewElementLevel = layers.API, layers.SetFrameLevel, layers.ElementLevel
local SceneLayerOn, SceneLayerAlpha = layers.IsOn, layers.Alpha

local function PaintGroupPreviewPortrait(scene)
    local frame, handle = scene.mock._cell, scene.S.portraitHandle
    if not frame then return end
    local portrait = frame.MSUFSpec and frame.MSUFSpec.portrait
    local holder = frame.MSUFPortraitHolder
    local helpers = M.PreviewHelpers
    helpers.BindGroupSceneHandle(handle, scene.mock, holder, scene.previewScale, nil,
        tonumber(portrait and portrait.x) or 0, tonumber(portrait and portrait.y) or 0)
    if handle then
        handle._locked = portrait and portrait.placement == "OVERLAY" and portrait.overlayAlign == "FULL"
        handle:SetAlpha((scene.soloLayer and scene.soloLayer ~= "portrait" and 0.15 or 1) * (scene.engineAlpha or 1))
    end
    scene.mock._msufGroupPortrait = holder
end

-- Kept as a narrow module seam so the interaction smoke can exercise the
-- production portrait handle binding with a real preview Button.
Render.PaintGroupPreviewPortrait = PaintGroupPreviewPortrait
local STATUS_TEXTURE_FALLBACKS = {
    raidMarker = { "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0, 0.25, 0, 0.25 },
    readyCheck = { "Interface\\RaidFrame\\ReadyCheck-Ready", 0, 1, 0, 1 },
    summon = { "Interface\\RaidFrame\\Raid-Icon-SummonPending", 0, 1, 0, 1 },
    incomingRes = { "Interface\\RaidFrame\\Raid-Icon-Rez", 0, 1, 0, 1 },
    pvp = { "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 1, 0, 1 },
    phase = { "Interface\\TargetingFrame\\UI-PhasingIcon", 0, 1, 0, 1 },
}

local function ResolveStatusPreviewTexture(scene, spec, runtimeCfg, iconType, variant)
    local customIcon = runtimeCfg and runtimeCfg.customIcon
    if (type(customIcon) ~= "string" or customIcon == "") and spec and spec.customIcon then
        customIcon = scene.conf[spec.customIcon]
    end
    if type(customIcon) == "string" and customIcon ~= "" then return customIcon, 0, 1, 0, 1 end
    local path, l, r, t, b = CoreExports.GetStatusIconTexture("BLIZZARD", iconType, variant,
        scene.runtimeStatus and scene.runtimeStatus.useMidnight == true)
    if type(path) == "string" and path ~= "" then return path, l, r, t, b end
    local fallback = STATUS_TEXTURE_FALLBACKS[iconType]
    if fallback then return fallback[1], fallback[2], fallback[3], fallback[4], fallback[5] end
end

local TEXT_HANDLE_KEYS = {
    "name", "hpGroup", "hpLeft", "hpCenter", "hpRight",
    "powerGroup", "powerLeft", "powerCenter", "powerRight",
}
local TEXT_LEVEL_SPECS = {
    { "name", "nameLayer", "nameTextLayer", 5 },
    { "hpGroup", "healthLayer", "textLayer", 5 },
    { "hpLeft", "healthLayer", "textLayer", 5 },
    { "hpCenter", "healthLayer", "textLayer", 5 },
    { "hpRight", "healthLayer", "textLayer", 5 },
    { "powerGroup", "powerLayer", "powerTextLayer", 2 },
    { "powerLeft", "powerLayer", "powerTextLayer", 2 },
    { "powerCenter", "powerLayer", "powerTextLayer", 2 },
    { "powerRight", "powerLayer", "powerTextLayer", 2 },
}

-- Handle keys per text slot and reused region lists: placing the text handles
-- on every repaint allocates nothing.
local TEXT_SLOT_HANDLE_KEYS = {
    hp = { "hpLeft", "hpCenter", "hpRight" },
    power = { "powerLeft", "powerCenter", "powerRight" },
}
--- Title, zoom resolution and the mock frame's size, position and backdrop.
function Stage.LayoutMockFrame(st, env)
        local conf, gf, kind, label = st.conf, st.gf, st.kind, st.label
        local runtimeBorder, runtimeHealth, runtimePower, runtimeSpec = st.runtimeBorder, st.runtimeHealth, st.runtimePower, st.runtimeSpec
        local self = st.self
        local ClampZoom, H, M, ResolveDefaultZoomLock = env.ClampZoom, env.H, env.M, env.ResolveDefaultZoomLock
        local Round, ScaleValue, UpdateZoomControls, WHITE8X8 = env.Round, env.ScaleValue, env.UpdateZoomControls, env.WHITE8X8
        local T = env.T
        local max, min, width = env.max, env.min, env.width
        T.SetTranslatedText(self._title, string.format((M.Tr and M.Tr("%s - %s")) or "%s - %s",
            (M.Tr and M.Tr("Group Frame Preview")) or "Group Frame Preview", label))
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
        local additional = Stage.SyncAdditionalLayout(st, liveW, liveH)
        local hasAdditional = (self._additionalPreviewTopology or 0) > 0
        local minX, maxX, minY, maxY
        if hasAdditional then minX, maxX, minY, maxY = additional.minX, additional.maxX, additional.minY, additional.maxY end
        local autoZoom = min(self._msufGFRenderState.GF_PREVIEW_MIN_W / liveW, self._msufGFRenderState.GF_PREVIEW_MIN_H / liveH)
        autoZoom = max(1.4, min(2.8, autoZoom))
        if hasAdditional then
            -- Overview can be smaller than the interactive zoom minimum:
            -- silently clipping enabled samples is not a useful initial view.
            -- Expand and deliberate zoom retain their existing controls.
            autoZoom = min(autoZoom, min(max(1, stageW - 24) / (maxX - minX),
                max(1, stageH - 24) / (maxY - minY)))
        end
        if not hasAdditional then ResolveDefaultZoomLock(self, autoZoom) end
        local manualZoom = tonumber(self._manualZoom)
        local frozenZoom = tonumber(self._dragFrozenScale)
        local previewScale = manualZoom and ClampZoom(manualZoom) or (frozenZoom and ClampZoom(frozenZoom) or autoZoom)
        self._mockAutoScale = autoZoom
        self._mockScale = previewScale
        UpdateZoomControls(self)
        local overview = hasAdditional and not manualZoom and not frozenZoom
        local mockW = max(overview and 1 or 48, Round(liveW * previewScale))
        local mockH = max(overview and 1 or 20, Round(liveH * previewScale))
        local powerH = runtimePower and runtimePower.enabled == true and ScaleValue(runtimePower.height, previewScale, 0) or 0
        if not runtimeSpec then powerH = H.MockPowerHeight(kind, conf, previewScale, frameScale) end
        -- Runtime parity for Power.Apply's three placements: embedded (inside the
        -- frame bottom), attached-below (embed off), and detached (free geometry).
        -- Only the embedded bar insets the health bar (Health.Layout contract).
        local powerEmbed, powerDetached
        if runtimeSpec then
            powerEmbed = runtimePower.embed ~= false
            powerDetached = runtimePower.detached == true
        else
            powerEmbed = conf.embedPowerBarIntoHealth ~= false
            powerDetached = conf.powerBarDetached == true
        end
        local borderEnabled = runtimeSpec and (runtimeBorder.enabled ~= false) or (not runtimeSpec and conf.borderEnabled ~= false)
        local outline = borderEnabled and (tonumber(runtimeBorder and runtimeBorder.thickness) or 1) or 0
        if not runtimeSpec and borderEnabled and gf and gf.GetBarOutlineThickness then outline = tonumber(gf.GetBarOutlineThickness(kind)) or outline end
        local outlineEdge = max(0, Round(outline * previewScale))
        local inset = 0
        local startX = Round((stageW - mockW) * 0.5)
        local startY = -Round((stageH - mockH) * 0.5)
        if hasAdditional then
            startX = Round(stageW / 2 - (minX + maxX) / 2 * previewScale - mockW / 2)
            startY = Round(-stageH / 2 - (minY + maxY) / 2 * previewScale + mockH / 2)
            -- Deliberate zoom may crop the scene; keep its main sample reachable.
            if not overview and mockW < stageW and mockH < stageH then
                startX = max(8, min(stageW - mockW - 8, startX))
                startY = min(-8, max(-stageH + mockH + 8, startY))
            end
        end
        local mock = self._mock
        mock._previewScale = previewScale
        self._mockBaseOffsetX, self._mockBaseOffsetY = startX, startY
        mock:ClearAllPoints()
        mock:SetPoint("TOPLEFT", self._stage, "TOPLEFT", startX + (tonumber(self._zoomPanX) or 0), startY + (tonumber(self._zoomPanY) or 0))
        mock:SetSize(mockW, mockH)
        self._additionalPreviewRoots = self._additionalPreviewRoots or {}
        Stage.RenderAdditionalSamples(st, additional, mock, previewScale)
        PixelLayoutRegion(mock, "SetBackdrop", Render.MockBackdrop(WHITE8X8))
        local bgAlpha = conf.hpBgAlpha or 0.85
        if runtimeSpec and runtimeSpec.backgroundAlpha ~= nil then bgAlpha = runtimeSpec.backgroundAlpha end
        mock:SetBackdropColor(conf.bgR or 0.08, conf.bgG or 0.08, conf.bgB or 0.09,
            (runtimeHealth.backgroundFillMode == "missing"
                or (not runtimeSpec
                    and EnsureDB().general.barBgFillMode == "missing")) and 0 or bgAlpha)
        mock:SetBackdropBorderColor(0, 0, 0, 0)
        st.inset, st.liveW, st.mock, st.mockW, st.outlineEdge = inset, liveW, mock, mockW, outlineEdge
        st.powerDetached, st.powerEmbed, st.powerH, st.previewScale = powerDetached, powerEmbed, powerH, previewScale
end

-- The additional sample blocks' layout. A settings repaint recomputes it and refits the zoom when the scene's
-- contents change; the animation tick reuses the last one.
function Stage.SyncAdditionalLayout(st, liveW, liveH)
        local self, kind = st.self, st.kind
        local additional = self._additionalPreviewLayout
        if st.reason == "GROUP_PREVIEW_ANIMATE" then return additional end
        local layoutScratch = self._additionalPreviewLayoutScratch
        if not layoutScratch then
            layoutScratch = {}
            self._additionalPreviewLayoutScratch = layoutScratch
        end
        additional = Render.AdditionalPreviewLayout(st.gf, kind, st.conf, liveW, liveH, layoutScratch)
        self._additionalPreviewLayout = additional
        local topology = additional and ((additional.pets and 1 or 0) + (additional.targets and 2 or 0)
            + (additional.friendlyBoss and 4 or 0) + (additional.healerMana and 8 or 0)) or 0
        if topology ~= self._additionalPreviewTopology or kind ~= self._additionalPreviewKind then
            -- The initial main-only default lock is not a fit for a newly
            -- enabled scene: refit once when the contents change and give
            -- the default lock back when the scene is main-only again. A
            -- lock the user set keeps its zoom and position, as the lock
            -- tooltip promises; an unlocked (Fit) preview refits.
            if topology > 0 or (self._additionalPreviewTopology or 0) > 0 then
                local userLock = self._manualZoom ~= nil and self._msuf2ZoomLockIsDefault ~= true
                if not userLock then
                    local defaultLock = self._msuf2ZoomLockDefaultPending == true
                        or self._msuf2ZoomLockIsDefault == true
                        or self._msuf2ZoomLockDefaultDropped == true
                    self._manualZoom, self._dragFrozenScale = nil, nil
                    self._zoomPanX, self._zoomPanY = nil, nil
                    self._msuf2ZoomLockIsDefault = nil
                    self._msuf2ZoomLockDefaultPending = defaultLock and topology == 0 or nil
                    self._msuf2ZoomLockDefaultDropped = defaultLock and topology > 0 or nil
                end
            end
            self._additionalPreviewTopology, self._additionalPreviewKind = topology, kind
        end
        return additional
end

-- Pets, targets, bosses and healer-mana samples around the mock, and the buff coverage samples on it.
function Stage.RenderAdditionalSamples(st, additional, mock, previewScale)
        if st.reason == "GROUP_PREVIEW_ANIMATE" then return end
        local self, gf, kind, conf = st.self, st.gf, st.kind, st.conf
        local prefixes = Render.ADDITIONAL_PREVIEW_PREFIXES
        for i = 1, #prefixes do
            local prefix = prefixes[i]
            local item = additional and additional[prefix]
            local root = self._additionalPreviewRoots[prefix]
            if item and gf.RenderAdditionalPreview then
                if not root then
                    root = PixelLayoutRegion(CreateFrame("Frame", nil, self._stage))
                    root:EnableMouse(false)
                    self._additionalPreviewRoots[prefix] = root
                end
                root:ClearAllPoints()
                root:SetPoint("CENTER", mock, "CENTER", item.x * previewScale, item.y * previewScale)
                root:SetSize(item.spec.totalWidth * previewScale, item.spec.totalHeight * previewScale)
                local holder = gf.RenderAdditionalPreview(root, kind, prefix, kind == "party" and 5 or 10, MENU_EXTRA_OPTIONS)
                if holder then
                    holder:SetScale(previewScale)
                    holder:ClearAllPoints()
                    holder:SetPoint("CENTER", root, "CENTER", 0, 0)
                    root:Show()
                else
                    root:Hide()
                end
            elseif root then
                if gf and gf.HideAdditionalPreview then gf.HideAdditionalPreview(root, prefix) end
                root:Hide()
            end
        end
        if gf and gf.RenderBuffCoveragePreview then
            if conf.enabled == false then gf.HideBuffCoveragePreview(mock)
            else gf.RenderBuffCoveragePreview(mock, conf, previewScale) end
        end
end

--- Power bar handle: placement for the embedded, attached-below and detached bar. The engine draws the bar
--- itself (Stage.RenderCell); the handle rides over it.
function Stage.PlacePowerHandle(st, env)
        local powerBarHandle = env.powerBarHandle
        if not powerBarHandle then return end
        local scene, conf, runtimePower, mock = st.scene, st.conf, st.runtimePower, st.mock
        local inset, powerH, previewScale, powerDetached = st.inset, st.powerH, st.previewScale, st.powerDetached
        local Round, ScaleValue = env.Round, env.ScaleValue
        -- LayoutDetached geometry (compiler resolves width to the frame width
        -- when unset; the conf fallback mirrors that for the no-spec path).
        local detachedPowerW = tonumber(runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or 0
        if detachedPowerW <= 0 then detachedPowerW = st.liveW end
        local detachedPowerH = tonumber(runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6
        local detachedPowerX = tonumber(runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
        local detachedPowerY = tonumber(runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
        -- Runtime parity for interaction too: only the detached bar owns
        -- free offsets, so the handle locks itself while the bar is
        -- embedded/attached (single-click settings still work there).
        powerBarHandle._locked = not powerDetached
        if powerBarHandle._dragging ~= true then
            powerBarHandle._previewScale = previewScale
            powerBarHandle._previewWriteScale = previewScale
            powerBarHandle:ClearAllPoints()
            if powerDetached then
                powerBarHandle:SetPoint("TOP", mock, "BOTTOM",
                    Round(detachedPowerX * previewScale), Round(detachedPowerY * previewScale))
                powerBarHandle:SetSize(ScaleValue(detachedPowerW, previewScale, 1),
                    ScaleValue(detachedPowerH, previewScale, 1))
            elseif not st.powerEmbed then
                powerBarHandle:SetPoint("TOP", mock, "BOTTOM", 0, -max(1, Round(previewScale)))
                powerBarHandle:SetSize(max(1, st.mockW - inset * 2), max(12, powerH))
            else
                powerBarHandle:SetPoint("BOTTOM", mock, "BOTTOM", 0, inset)
                powerBarHandle:SetSize(max(1, st.mockW - inset * 2), max(12, powerH))
            end
        end
        powerBarHandle:SetShown(powerH > 0 and SceneLayerOn(scene, "power"))
        powerBarHandle:SetAlpha(SceneLayerAlpha(scene, "power"))
        local powerFrameLevel = powerDetached
            and PreviewElementLevel(mock, Layers,
                runtimePower.detachedLevel or conf.detachedPowerBarFrameLevelOffset, 6, 0)
            or ((mock.GetFrameLevel and mock:GetFrameLevel()) or 1) + 1
        SetPreviewFrameLevel(powerBarHandle, powerFrameLevel)
end

--- The engine paints the frame body: bars, texts, prediction, frame and block border, rounded art. An isolated
--- preview scene (GF.NewPreviewScene) hangs on the mock, zoomed by the preview scale, in the mock's level band; this
--- stage hands it the page's inputs and aliases its regions onto the mock for the handles, the focus ring and the
--- colour painter. No unit is read: the cell shows a fixed sample.
local CELL_ALIASES = {
    { "_health", "hpBar", "Health", "health" }, { "_power", "targetPowerBar", "powerBar", "Power", "power" },
    { "_healPred", "incomingHealBar" }, { "_absorb", "absorbBar" }, { "_healAbsorb", "healAbsorbBar" },
    { "_tempMaxHealth", "tempMaxHealthBar" }, { "_healthBg", "hpBarBG", "healthBg" },
    { "_nameFS", "nameText" }, { "_hpLeftFS", "hpTextLeft" }, { "_hpCenterFS", "hpTextCenter" },
    { "_hpRightFS", "hpTextRight" }, { "_hpFS", "hpTextRight" },
    { "_powerLeftFS", "powerTextLeft" }, { "_powerCenterFS", "powerTextCenter" },
    { "_powerRightFS", "powerTextRight" }, { "_powerFS", "powerTextCenter" },
}
local function AliasCell(mock, frame)
    for i = 1, #CELL_ALIASES do
        local item = CELL_ALIASES[i]
        local region
        for j = 2, #item do
            region = frame and frame[item[j]]
            if region then break end
        end
        -- A text slot the settings leave unused has no engine region: a hidden stand-in keeps the handle and focus
        -- region lists dense (a hidden region is skipped).
        if not region and item[1]:sub(-2) == "FS" then
            local standIn = mock._cellStandInFS
            if not standIn then
                standIn = PixelLayoutRegion(mock:CreateFontString(nil, "OVERLAY"))
                standIn:Hide()
                mock._cellStandInFS = standIn
            end
            region = standIn
        end
        mock[item[1]] = region
    end
    mock._cell = frame
end

local CELL_SAMPLE = { hpMax = 1000000, powerMax = 100, absorb = 125000, healAbsorbPct = 0.07, tempMaxPct = 0.20,
    powerColor = { 0.13, 0.27, 0.67 } }
function Stage.RenderCell(st, env)
        local mock, scene, self, kind = st.mock, st.scene, st.self, st.kind
        local root = self._scene
        if not root then
            root = scene.gf.NewPreviewScene(mock)
            self._scene = root
        end
        root:Activate()
        local cell = root:Group(kind)
        for other, group in pairs(root.groups) do
            if other ~= kind and group:IsActive() then group:Hide() end
        end
        local names, classes = env.GF_PREVIEW_NAMES, env.GF_PREVIEW_CLASSES
        local sample = self._msufGFCellSample
        if not sample then
            sample = {}
            for key, value in pairs(CELL_SAMPLE) do sample[key] = value end
            sample.powerColor = { CELL_SAMPLE.powerColor[1], CELL_SAMPLE.powerColor[2], CELL_SAMPLE.powerColor[3] }
            sample.portrait, sample.statusRegions, sample.auraTextAlpha = {}, {}, {}
            self._msufGFCellSample = sample
        end
        -- The live player when it can be read, the stylized sample for any missing field. The exact maxima and the
        -- absorb amount scale the value texts; while the animation runs the animated fraction drives the current
        -- value on that live maximum.
        local live = scene.liveData
        sample.name = live and live.name or names[5]
        sample.class = live and live.class or classes[((kind == "party" and 5 or 2) % #classes) + 1]
        sample.hpMax = live and live.hpMax or CELL_SAMPLE.hpMax
        sample.powerMax = live and live.powerMax or CELL_SAMPLE.powerMax
        sample.absorb = live and live.absorb or CELL_SAMPLE.absorb
        sample.hpPct, sample.powerPct = scene.hpPct, scene.powerPct
        sample.healPct, sample.absorbPct = scene.healPct, scene.absorbPct
        scene.sampleClass = sample.class
        sample.font = st.previewFont
        for i = 1, #AURA_LANES do
            local key = AURA_LANES[i][1]
            sample.auraTextAlpha[key] = min(1, SceneLayerAlpha(scene, "auraText") / max(0.0001, SceneLayerAlpha(scene, key)))
        end
        Stage.PrepareCellSamples(st, env, sample)
        cell:Configure({
            scale = st.previewScale, level = mock._msufPreviewElementLevelBias, role = scene.previewRole,
            sample = sample, bodyOnly = false, layerVisible = scene.layerVisible, layerSolo = false,
            ignoreOocFade = true, fit = true,
        })
        root:SetClock(self._animationEnabled == true and self._animationElapsed or nil, true)
        cell:Show(1, { immediate = true, reason = st.reason })
        local frames = cell:Frames()
        local frame = frames and frames[1]
        if frame then
            scene.engineConfig = M.PreviewHelpers.PrepareGroupSceneSamples(frame, cell, scene)
            cell:RefreshData()
            -- Capture the live Power painter's configured colour once per settings refresh.
            -- The scene then reuses it on animation ticks without another query or call.
            local power = MSUF.UF.elements.Power
            if frame.targetPowerBar then
                power.PaintSample(frame, "player", floor(scene.powerPct * sample.powerMax + 0.5), sample.powerMax,
                    live and live.powerType or 0, live and live.powerToken or "MANA")
                local r, g, b, a = frame.targetPowerBar:GetStatusBarColor()
                if not issecretvalue(r) and not issecretvalue(g) and not issecretvalue(b) and not issecretvalue(a) then
                    local color = sample.powerColor
                    color[1], color[2], color[3], color[4] = r, g, b, a
                end
            end
            local lanes = scene.engineConfig and scene.engineConfig.lanes or {}
            for i = 1, #AURA_LANES do
                local lane = AURA_LANES[i]
                if lanes[lane[1]] then scene[lane[3]] = lanes[lane[1]] end
            end
        end
        scene.engineAlpha = frame and frame:GetAlpha() or 1
        AliasCell(mock, frame)
end

--- Dispel overlay, portrait and dispel symbol: widgets of the preview's own (the portrait and the symbol row are
--- handles). The frame border, rounded surface and text layers belong to the engine scene.
function Stage.RenderChrome(st)
    local scene, frame = st.scene, st.mock._cell
    if not frame then return end
    scene.previewScale = st.previewScale
    PaintGroupPreviewPortrait(scene)
    M.PreviewHelpers.PaintGroupSceneDispel(frame, scene.engineConfig)
    local overlay, symbol = frame._msufSceneDispelOverlay, frame._msufSceneDispelSymbol
    if overlay then
        overlay:SetShown(scene.layerAvailable.dispelOverlay and scene.layerVisible.dispelOverlay ~= false)
        overlay:SetAlpha(scene.soloLayer and scene.soloLayer ~= "dispelOverlay" and 0.15 or 1)
    end
    if symbol then symbol:SetShown(scene.layerAvailable.dispelSymbol and scene.layerVisible.dispelSymbol ~= false) end
    local cfg = scene.runtimeSpec and scene.runtimeSpec.dispelSymbol
    M.PreviewHelpers.BindGroupSceneHandle(scene.S.dispelSymbolHandle, scene.mock, symbol,
        scene.previewScale, cfg and cfg.anchor, tonumber(cfg and cfg.x) or 0, tonumber(cfg and cfg.y) or 0)
    if scene.S.dispelSymbolHandle then
        scene.S.dispelSymbolHandle:SetAlpha(SceneLayerAlpha(scene, "dispelSymbol") * (scene.engineAlpha or 1))
    end
    scene.mock._msufGFPreviewDispelOverlayHost = overlay
    scene.mock._msufGFPreviewDispelOverlayRegion = overlay and overlay.Region
end

-- Pass the resolved runtime font as scene input, before the scene paints any text.
function Stage.ResolveFont(st, env)
    local spec = st.runtimeSpec
    local font = st.self._msufGFSceneFont or {}
    st.self._msufGFSceneFont, st.previewFont = font, font
    font.path, font.flags = spec.font, spec.fontFlags
    font.key = EnsureDB().general.fontKey
    local shadow = spec.fontShadow == true
    font.shadowAlpha = shadow and (tonumber(spec.fontShadowAlpha) or 1) or 0
    font.shadowX = shadow and (tonumber(spec.fontShadowX) or 1) or 0
    font.shadowY = shadow and (tonumber(spec.fontShadowY) or -1) or 0
end

--- Group block border, bounds guide and the aura lanes (RenderAuras), whose
--- layout helpers later stages reuse.
function Stage.RenderBoundsAndAuras(st, env)
        local scene, mock, self = st.scene, st.mock, st.self
        env.ApplyBoundsGuide(self, max(1, st.outlineEdge))
        if self._bounds.SetFrameLevel and mock.GetFrameLevel then
            SetPreviewFrameLevel(self._bounds, Layers.ElementLevel and (PreviewElementLevel(mock, Layers, 30, 30, 31) + 16)
                or ((mock:GetFrameLevel() or 1) + (Layers.PREVIEW_BOUNDS_OFFSET or 48)))
        end
        self._bounds:SetShown(SceneLayerOn(scene, "bounds"))
        scene.previewScale = st.previewScale
        RenderAuras(scene)
        st.LayoutHandle = scene.LayoutHandle
end

-- Status icon value -> the shared fallback texture table entry and variant.
local STATUS_ICON_TEXTURES = {
    raidMarker = { "raidMarker", 1 }, readyCheckIcon = { "readyCheck", "ready" }, summonIcon = { "summon", 1 },
    resurrectIcon = { "incomingRes", "resurrect" }, pvpIcon = { "pvp", "Alliance" }, phaseIcon = { "phase", "phase" },
}
-- The texture and coords one status icon shows: a custom icon, the group's own role/leader/assist art, or the
-- shared Blizzard texture.
function Stage.StatusIconTexture(scene, spec, runtimeCfg)
    local conf, gf, kind, value = scene.conf, scene.gf, scene.kind, spec.value
    local style = runtimeCfg and runtimeCfg.style
    if runtimeCfg and type(runtimeCfg.customIcon) == "string" and runtimeCfg.customIcon ~= "" then
        return runtimeCfg.customIcon, 0, 1, 0, 1
    elseif spec.customIcon and type(conf[spec.customIcon]) == "string" and conf[spec.customIcon] ~= "" then
        return conf[spec.customIcon], 0, 1, 0, 1
    elseif value == "roleIcon" and gf and gf.GetRoleTexture then
        return gf.GetRoleTexture(kind, scene.previewRole, style)
    elseif value == "leaderIcon" and gf and gf.GetLeaderTexture then
        return gf.GetLeaderTexture(kind, style)
    elseif value == "assistIcon" and gf and gf.GetAssistTexture then
        return gf.GetAssistTexture(kind, style)
    end
    local texture = STATUS_ICON_TEXTURES[value]
    if texture then return ResolveStatusPreviewTexture(scene, spec, runtimeCfg, texture[1], texture[2]) end
end

local ENGINE_STATUS_FIELDS = {
    roleIcon = "roleIcon", leaderIcon = "leaderIcon", assistIcon = "assistIcon", raidMarker = "raidTargetIcon",
    readyCheckIcon = "readyCheckIcon", summonIcon = "summonIcon", resurrectIcon = "incomingResIndicatorIcon",
    pvpIcon = "pvpIndicatorIcon", phaseIcon = "phaseIcon", showGroupNumber = "raidGroupNameText", levelText = "levelText",
    statusText = "_msufScene_statusText", statusGhostText = "_msufScene_statusGhostText",
    statusAFKText = "_msufScene_statusAFKText", statusDNDText = "_msufScene_statusDNDText",
    statusAFKTimer = "statusAFKTimerText", threatText = "threatIndicatorText",
}
-- Retained public sample values cross the scene boundary before it paints. Handles only adopt regions.
function Stage.PrepareCellSamples(st, env, sample)
    local scene, portrait = st.scene, sample.portrait
    local cfg = scene.runtimeSpec and scene.runtimeSpec.portrait
    portrait.shown = st.kind == "party" and cfg and cfg.enabled == true or false
    portrait.texture, portrait.castSpellIcon = nil, false
    portrait.l, portrait.r, portrait.t, portrait.b = 0, 1, 0, 1
    if portrait.shown then
        portrait.castSpellIcon = cfg.castSpellIcon == true and st.self._animationEnabled == true
        if portrait.castSpellIcon then
            portrait.texture = scene.S.CurrentSpellTexture(st.kind)
            portrait.l, portrait.r, portrait.t, portrait.b = 0.08, 0.92, 0.08, 0.92
        elseif cfg.render ~= "CLASS" and SetPortraitTexture then
            local snapshot = st.self._portraitSnapshot
            if not snapshot then
                snapshot = PixelLayoutRegion(st.mock:CreateTexture(nil, "ARTWORK"))
                snapshot:Hide()
                st.self._portraitSnapshot = snapshot
            end
            snapshot:SetTexture(nil)
            SetPortraitTexture(snapshot, "player")
            local art = snapshot:GetTexture()
            if not issecretvalue(art) and (type(art) == "number" or type(art) == "string") then portrait.texture = art end
        end
    end
    sample.player, sample.leader, sample.assist, sample.statusSelection = true, true, true, "all"
    sample.raidTarget, sample.raidGroup, sample.incomingRes, sample.pvp, sample.level = 1, 3, true, "Alliance", 80
    local regions = sample.statusRegions
    for i = 1, #env.statusHandles do
        local spec = env.statusHandles[i]._statusSpec
        local status = env.RuntimeStatusConfig(scene.runtimeStatus, spec)
        local row = regions[i] or {}
        regions[i] = row
        row.field = ENGINE_STATUS_FIELDS[spec.value] or spec.value
        row.shown = status and status.enabled == true and env.StatusSpecInMode(spec, scene.statusSpec) or false
        row.text, row.texture = nil, nil
        if env.StatusSpecIsText(spec) then
            row.text = env.StatusText(spec, status, st.conf)
        else
            row.texture, row.l, row.r, row.t, row.b = Stage.StatusIconTexture(scene, spec, status)
        end
    end
    for i = #regions, #env.statusHandles + 1, -1 do regions[i] = nil end
end
function Stage.ConfigureStatusHandle(st, env, handle)
    local spec, frame = handle._statusSpec, st.mock._cell
    local cfg = env.RuntimeStatusConfig(st.scene.runtimeStatus, spec)
    local region = frame and frame[ENGINE_STATUS_FIELDS[spec.value] or spec.value]
    handle._previewText = spec.text or "Status"
    if handle._label then handle._label:SetText(env.StatusLabel(spec)) end
    M.PreviewHelpers.BindGroupSceneHandle(handle, st.mock, region, st.previewScale, cfg and cfg.anchor)
end
function Stage.ConfigureStatusHandles(st, env)
    if not st.mock._cell then return end
    for i = 1, #env.statusHandles do Stage.ConfigureStatusHandle(st, env, env.statusHandles[i]) end
end

--- Spell indicator handle painters: icon glow effect and the per-visual
--- (icon, bar, square, number) handle configuration.
-- Read-only fallbacks for a handle without its own color or appearance.
local EMPTY_APPEARANCE = {}
-- The selected spell's placement before the editor stored one.
local SELECTED_SPELL_PLACED_DEFAULT = { type = "icon", size = 20, anchor = "TOPLEFT", x = 0, y = 0 }
-- Appearance flag, else the placement's own flag (on unless it is explicitly false).

return TEXT_HANDLE_KEYS, TEXT_LEVEL_SPECS, TEXT_SLOT_HANDLE_KEYS, EMPTY_APPEARANCE, SELECTED_SPELL_PLACED_DEFAULT
end
