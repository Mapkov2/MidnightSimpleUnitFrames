--- Group preview render/composition.
---
--- Coordinates the ordered scene stages and per-host install state.
--- Planning and presentation have dedicated owners; Native owns lifecycle.
local _, MSUF = ...
MSUF = MSUF or {}
local FILE = "Menu2/GroupPreview_Render"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- The animation owner and status icon provider load before the Options addon.
local Animation = assert(MSUF.PreviewAnimation, "Group preview requires PreviewAnimation")
local CoreExports = {
    BuildAnimationFrameState = Animation.BuildFrameState,
    GetStatusIconTexture = MSUF.Require("MSUF_GetStatusIconTexture", FILE),
}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB
local Render = M.GroupPreviewRender or {}
M.GroupPreviewRender = Render
local Fallbacks = M.Fallbacks or {}
local RequireFields = M.PreviewContracts.RequireFields
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local issecretvalue, wipe = issecretvalue, wipe
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local Stage = {}
local SceneAuraLaneAvailable, SceneAuraLaneTextAvailable, PreviewIconScale, AURA_LANES, BuildSceneAuraLanes, RenderAuras
local BuildSceneSpells, FinalizeSpellLevels, SuspendHandleEffects
local TEXT_HANDLE_KEYS, TEXT_LEVEL_SPECS, TEXT_SLOT_HANDLE_KEYS, EMPTY_APPEARANCE, SELECTED_SPELL_PLACED_DEFAULT
local MENU_EXTRA_OPTIONS = { position = false, sampleCount = 3 }
-- Blizzard's BackdropTemplateMixin:SetBackdrop skips a table it already holds
-- (HasBackdropInfo compares identity), so each repaint passes the same table.
local MOCK_BACKDROPS = {}
function Render.MockBackdrop(file)
    local backdrop = MOCK_BACKDROPS[file]
    if not backdrop then
        backdrop = { bgFile = file }
        MOCK_BACKDROPS[file] = backdrop
    end
    return backdrop
end
-- Friendly bosses need boss units, which Classic Era and TBC do not have: a
-- client fact read once at load. A harness without MSUF.Client previews them.
local PREVIEW_BOSS_UNITS = MSUF.Client.SupportsUnit("boss1") == true
local ADDITIONAL_PREVIEW_PREFIXES = PREVIEW_BOSS_UNITS and { "pets", "targets", "friendlyBoss", "healerMana" }
    or { "pets", "targets", "healerMana" }
Render.ADDITIONAL_PREVIEW_PREFIXES = ADDITIONAL_PREVIEW_PREFIXES
-- The Group Bars settings section that owns each sample-effect layer.
Render.SAMPLE_LAYER_SECTIONS = { dispelOverlay = "dispel", dispelSymbol = "dispelSymbol" }
-- Menu samples form a compact shared scene. Screen positions belong to the
-- live/Edit Mode layout; projecting them here would hide the group or samples.
-- `out` (optional) is the caller's reused result table, so a settings repaint
-- allocates nothing once the layout exists.
function Render.AdditionalPreviewLayout(gf, kind, conf, liveW, liveH, out)
    if not (gf and gf.GetAdditionalPreviewSpec) or conf.enabled == false
        or (conf.petsEnabled ~= true and (kind ~= "party" or conf.targetsEnabled ~= true)
            and (conf.friendlyBossEnabled ~= true or not PREVIEW_BOSS_UNITS) and conf.healerManaEnabled ~= true) then return nil end
    local count = kind == "party" and 5 or 10
    local result = out or {}
    local items = result._items
    if not items then
        items = {}
        result._items = items
    end
    result.minX, result.maxX, result.minY, result.maxY = -liveW / 2, liveW / 2, -liveH / 2, liveH / 2
    local left = liveW / 2 + 18
    for i = 1, #ADDITIONAL_PREVIEW_PREFIXES do
        local prefix = ADDITIONAL_PREVIEW_PREFIXES[i]
        local spec = gf.GetAdditionalPreviewSpec(kind, prefix, count, MENU_EXTRA_OPTIONS)
        if spec and spec.enabled then
            local x, y = left + spec.totalWidth / 2, liveH / 2 - spec.totalHeight / 2
            local item = items[prefix]
            if not item then
                item = {}
                items[prefix] = item
            end
            item.spec, item.x, item.y = spec, x, y
            result[prefix] = item
            result.maxX = x + spec.totalWidth / 2
            result.minY = math.min(result.minY, y - spec.totalHeight / 2)
            left = result.maxX + 18
        else
            result[prefix] = nil
        end
    end
    return result
end
function Render.HideAdditionalPreview(box)
    for _, root in pairs(box._additionalPreviewRoots or {}) do root:Hide() end
    if box._mock and MSUF.GF and MSUF.GF.HideBuffCoveragePreview then
        MSUF.GF.HideBuffCoveragePreview(box._mock)
    end
end
local function DefaultCompiledAuraLane(_, _, fallback) return fallback or {} end


local SetPreviewFrameLevel, PreviewElementLevel, PreviewInteractionLevel

-- Raise the cached mock above the preview canvas, then use that exact level as
-- the bias for every absolute runtime ElementLevel encoded below.
local PREVIEW_LOCAL_BASE_OFFSET = 400
local PREVIEW_FRAME_LEVEL_MAX = 65535
local function SafePreviewFrameLevel(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value < 0 then return 0 end
    if value > PREVIEW_FRAME_LEVEL_MAX then return PREVIEW_FRAME_LEVEL_MAX end
    return value
end
SetPreviewFrameLevel = function(frame, value)
    if not (frame and frame.SetFrameLevel) then return 0 end
    value = SafePreviewFrameLevel(value)
    frame:SetFrameLevel(value)
    return value
end
--- The live layer encoder is intentionally absolute. Menu2, however, raises
--- its cached Group mock into a private frame-level band so it stays above the
--- preview canvas. Translate every encoded live level by that one mock-owned
--- bias; mixing an unshifted ElementLevel with the raised mock puts ordinary
--- Layer 0..9 content (notably Name/HP/Power text) underneath the health bar.
PreviewElementLevel = function(mock, layerAPI, layer, fallback, detail)
    local encoded
    if layerAPI and layerAPI.ElementLevel then
        encoded = layerAPI.ElementLevel(layer, fallback, detail)
    else
        local value = math.floor((tonumber(layer) or fallback or 0) + 0.5)
        if value < 0 then value = 0 elseif value > 30 then value = 30 end
        detail = math.floor((tonumber(detail) or 0) + 0.5)
        if detail < 0 then detail = 0 elseif detail > 31 then detail = 31 end
        encoded = 100 + value * 32 + detail
    end
    return SafePreviewFrameLevel((tonumber(mock and mock._msufPreviewElementLevelBias) or 0) + encoded)
end
PreviewInteractionLevel = function(mock, layerAPI, extra)
    local top = PreviewElementLevel(mock, layerAPI, 30, 30,
        layerAPI and layerAPI.ELEMENT_DETAIL_MAX or 31)
    return SafePreviewFrameLevel(top + (tonumber(layerAPI and layerAPI.ELEMENT_LEVEL_STRIDE) or 32)
        + (tonumber(extra) or 0))
end

-- A refresh first resolves immutable inputs into a scene. Render components then
-- measure and paint that scene without reaching back through the install closure.
-- The tracked lane is read into one table kept per preview box: every key is
-- written on each refresh, so the table never carries a stale field.
local function SceneStatusAvailable(scene, spec)
    if scene.runtimeSpec then
        local cfg = scene.S.RuntimeStatusConfig(scene.runtimeStatus, spec)
        return cfg and cfg.enabled == true
    end
    return scene.S.StatusSpecEnabled(scene.conf, spec)
end

local function SceneLayerOn(scene, key)
    return scene.layerAvailable[key] ~= false and scene.layerVisible[key] ~= false
end

local function SceneLayerAlpha(scene, key)
    if scene.layerAvailable[key] == false then return 0 end
    return scene.soloLayer and scene.soloLayer ~= key and 0.15 or 1
end

local BuildScene

local PlaceTextHandles, PreviewHostStrata, ApplyHandleStrata, SyncIconDetailLevels

local function FinalizeLevels(scene, hostStrata)
    local RenderState, mock, conf = scene.S, scene.mock, scene.conf
    local layers = RenderState.Layers
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        local handle = RenderState[lane[2]]
        if handle then
            ApplyHandleStrata(scene, handle, hostStrata)
            local level = SetPreviewFrameLevel(handle, PreviewElementLevel(mock, layers, scene[lane[3]].layer, lane[5], 0))
            if handle._msufEngineFrameLevel then SetPreviewFrameLevel(handle, handle._msufEngineFrameLevel) end
        end
    end
    for i = 1, #RenderState.statusHandles do
        local handle = RenderState.statusHandles[i]
        local spec = handle and handle._statusSpec
        if handle then
            local cfg = RenderState.RuntimeStatusConfig(scene.runtimeStatus, spec)
            SetPreviewFrameLevel(handle, handle._msufEngineFrameLevel or PreviewElementLevel(mock, layers,
                cfg and cfg.layer or spec and conf[spec.layer], spec and spec.defaultLayer or 7, 8))
        end
    end
    -- Dispel symbol row. Same foreground band as the aura handles so its Effect
    -- Layer slider is judgeable against them in the preview, mirroring the live
    -- DispelSensorFrameLevel (frame base + aura icon base + configured layer).
    -- Without this the handle kept its creation-time level and the slider looked
    -- dead in the preview while it worked on the real frame.
    local dispelSymbolCfg = scene.runtimeSpec and scene.runtimeSpec.dispelSymbol
    if RenderState.dispelSymbolHandle then
        ApplyHandleStrata(scene, RenderState.dispelSymbolHandle, hostStrata)
        SetPreviewFrameLevel(RenderState.dispelSymbolHandle,
            RenderState.dispelSymbolHandle._msufEngineFrameLevel
                or PreviewElementLevel(mock, layers, dispelSymbolCfg and dispelSymbolCfg.layer, 8, 8))
    end
    FinalizeSpellLevels(scene, hostStrata)
    for i = 1, #TEXT_LEVEL_SPECS do
        local item = TEXT_LEVEL_SPECS[i]
        SetPreviewFrameLevel(scene.textHandles[item[1]],
            PreviewElementLevel(mock, layers, scene.runtimeText[item[2]] or conf[item[3]], item[4], 8))
    end
end

local FinalizeVisibility, FinalizeRangeFade

local function FinalizeScene(scene)
    local RenderState, box = scene.S, scene.box
    PlaceTextHandles(scene)
    FinalizeLevels(scene, PreviewHostStrata(scene))
    FinalizeVisibility(scene)
    FinalizeRangeFade(scene)
    local visibleLayerButtonCount = 0
    for i = 1, #box._layerButtons do
        local button = box._layerButtons[i]
        local visible = button._layerKey ~= "portrait" or scene.kind == "party"
        if button.SetShown then button:SetShown(visible) end
        if visible then visibleLayerButtonCount = visibleLayerButtonCount + 1 end
        local available = scene.layerAvailable[button._layerKey] ~= false
        button._layerAvailable = available
        if button.Refresh then button:Refresh() end
    end
    box._visibleLayerButtonCount = visibleLayerButtonCount
    M.PreviewHelpers.RefreshSampleEffectHint(box)
    -- The in-world dummies answer to the same rail. Pushing from here instead of
    -- from the chip's OnClick covers every route into the state -- click, Shift
    -- solo, Search command, page re-entry -- and the engine compares a
    -- signature, so a refresh that changed nothing costs one string.
    if scene.gf and scene.gf.SetPreviewLayerFilter then
        scene.gf.SetPreviewLayerFilter(scene.layerVisible, scene.soloLayer)
    end
    if box._selectedHandle and box._selectedHandle.IsShown and not box._selectedHandle:IsShown() then RenderState.SelectHandle(nil) end
    RenderState.RefreshHandleSelection(box)
end

--- Render stages. Each renders one slice of the mock from a shared per-refresh
--- state table (the Refresh stages also take the install-time env table);
--- RenderAuras and Stage.Refresh run them in the original order.

-- Specialize owners at load; refresh and animation keep the original call graph.
SceneAuraLaneAvailable, SceneAuraLaneTextAvailable, PreviewIconScale, AURA_LANES, BuildSceneAuraLanes, RenderAuras = M.GroupRenderFactories.Auras(
    { Core = MSUF, Menu = M, Wipe = wipe, Max = max }, { Stage = Stage }
)
TEXT_HANDLE_KEYS, TEXT_LEVEL_SPECS, TEXT_SLOT_HANDLE_KEYS, EMPTY_APPEARANCE, SELECTED_SPELL_PLACED_DEFAULT = M.GroupRenderFactories.Frame(
    { Core = MSUF, Menu = M, Exports = CoreExports, EnsureDB = EnsureDB, IsSecret = issecretvalue },
    { Render = Render, Stage = Stage, RenderAuras = RenderAuras, AuraLanes = AURA_LANES,
        ExtraOptions = MENU_EXTRA_OPTIONS, AdditionalPrefixes = ADDITIONAL_PREVIEW_PREFIXES },
    { PixelLayoutRegion = PixelLayoutRegion, Floor = floor, Max = max, Min = min },
    { API = Layers, SetFrameLevel = SetPreviewFrameLevel, ElementLevel = PreviewElementLevel, IsOn = SceneLayerOn, Alpha = SceneLayerAlpha }
)
local RequireFields = M.PreviewContracts.RequireFields
local presentation = M.GroupRenderFactories.Presentation(
    { Menu = M },
    { SetFrameLevel = SetPreviewFrameLevel, TextHandleKeys = TEXT_HANDLE_KEYS,
        TextSlotHandleKeys = TEXT_SLOT_HANDLE_KEYS, AuraLanes = AURA_LANES },
    { IsOn = SceneLayerOn, Alpha = SceneLayerAlpha, StatusAvailable = SceneStatusAvailable }
)
RequireFields("GroupPreview.Presentation", presentation,
    "PlaceTextHandles HostStrata ApplyHandleStrata SyncIconDetailLevels FinalizeVisibility FinalizeRangeFade")
PlaceTextHandles, PreviewHostStrata = presentation.PlaceTextHandles, presentation.HostStrata
ApplyHandleStrata, SyncIconDetailLevels = presentation.ApplyHandleStrata, presentation.SyncIconDetailLevels
FinalizeVisibility, FinalizeRangeFade = presentation.FinalizeVisibility, presentation.FinalizeRangeFade
BuildSceneSpells, FinalizeSpellLevels, SuspendHandleEffects = M.GroupRenderFactories.Spells(
    { Core = MSUF, Menu = M, Wipe = wipe },
    { PixelLayoutRegion = PixelLayoutRegion, Floor = floor, Max = max, Min = min, IconScale = PreviewIconScale },
    { API = Layers, SetFrameLevel = SetPreviewFrameLevel, ElementLevel = PreviewElementLevel,
        ApplyHandleStrata = ApplyHandleStrata, SyncIconDetailLevels = SyncIconDetailLevels },
    { Finalize = FinalizeScene, Stage = Stage, EmptyAppearance = EMPTY_APPEARANCE, SelectedPlacedDefault = SELECTED_SPELL_PLACED_DEFAULT }
)

BuildScene = M.GroupRenderFactories.Plan(
    { Exports = CoreExports, Wipe = wipe },
    { AuraLanes = AURA_LANES, BuildAuraLanes = BuildSceneAuraLanes, BuildSpells = BuildSceneSpells,
        StatusAvailable = SceneStatusAvailable, AuraAvailable = SceneAuraLaneAvailable,
        AuraTextAvailable = SceneAuraLaneTextAvailable, SampleLayerSections = Render.SAMPLE_LAYER_SECTIONS }
)
Render.Components = { Plan = BuildScene, Auras = RenderAuras, Finalize = FinalizeScene }
Render.ComponentOrder = { "Plan", "FrameAndText", "Auras", "Indicators", "Finalize" }
local KEY_NUDGE = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

--- Installs the group preview renderer into the preview host. Native.lua owns
--- frame creation and input handles; this function owns repeated composition
--- from compiled group specs, visible layers, zoom state, and selected handles.
function Render.Install(box, ctx, deps)
    if not box then return end
    local Config = RequireFields("GroupRender.Config", deps.Config,
        "GF_PREVIEW_ROLE_DEFAULT StatusSpecs ScaleValue ConfigToOffset CompiledSpec CompiledAuraLane RuntimeStatusConfig CurrentStatusSpec "
        .. "StatusSpecEnabled StatusSpecInMode StatusSpecIsText StatusText CurrentSpellInfo "
        .. "PreviewAllSpecSpellIcons CurrentSpellConfig CurrentSpellPlaced CurrentSpellTexture "
        .. "CurrentSpellColor MockSpellTexture Round ClampLayer ClassColor AuraGrowth Int")
    local Selection = RequireFields("GroupRender.Selection", deps.Selection,
        "RefreshHandleSelection Helpers")
    local Interaction = RequireFields("GroupRender.Interaction", deps.Interaction,
        "ResolveDefaultZoomLock UpdateZoomControls ClampZoom")
    local Handles = RequireFields("GroupRender.Handles", deps.Handles,
        "statusHandles SelectHandle NudgeHandlePosition")
    local specs = deps.Specs
    local mock = deps.mock or box._mock
    local selectedSpellEffectOwner = box._msufGFSelectedSpellEffectOwner
    if not selectedSpellEffectOwner then
        selectedSpellEffectOwner = PixelLayoutRegion(CreateFrame("Frame", nil, mock))
        selectedSpellEffectOwner:EnableMouse(false)
        selectedSpellEffectOwner:SetAllPoints(mock)
        box._msufGFSelectedSpellEffectOwner = selectedSpellEffectOwner
    end
    local env = {
        floor = floor, max = max, min = min, ceil = ceil,
        H = Selection.Helpers, M = M, MSUF = MSUF, T = M.Theme,
        ctx = ctx, width = tonumber(deps.width) or 720, mock = mock,
        WHITE8X8 = specs.WHITE8X8,
        GF_PREVIEW_NAMES = specs.NAMES or {}, GF_PREVIEW_CLASSES = specs.CLASSES or {},
        GF_AURA_MOCK_ICON_IDS = specs.AURA_MOCK_ICON_IDS or {},
        GF_PREVIEW_MIN_W = tonumber(specs.MIN_W) or 380, GF_PREVIEW_MIN_H = tonumber(specs.MIN_H) or 130,
        GF_PREVIEW_ROLE = Config.GF_PREVIEW_ROLE_DEFAULT, GF_PREVIEW_ANCHOR_FRAC = specs.ANCHOR_FRAC or {},
        statusHandles = Handles.statusHandles, statusSpecs = Config.StatusSpecs(),
        ApplyBoundsGuide = MSUF.UFPreviewCore.ApplyBoundsGuide,
        Layers = Layers, issecretvalue = issecretvalue, box = box, selectedSpellEffectOwner = selectedSpellEffectOwner,
    }
    env.ScaleValue = Config.ScaleValue
    env.ConfigToOffset = Config.ConfigToOffset
    env.CompiledSpec = Config.CompiledSpec
    env.CompiledAuraLane = Config.CompiledAuraLane
    env.RuntimeStatusConfig = Config.RuntimeStatusConfig
    env.CurrentStatusSpec = Config.CurrentStatusSpec
    env.StatusSpecEnabled = Config.StatusSpecEnabled
    env.StatusSpecInMode = Config.StatusSpecInMode
    env.StatusSpecIsText = Config.StatusSpecIsText
    env.StatusText = Config.StatusText
    env.CurrentSpellInfo = Config.CurrentSpellInfo
    env.PreviewAllSpecSpellIcons = Config.PreviewAllSpecSpellIcons
    env.CurrentSpellConfig = Config.CurrentSpellConfig
    env.CurrentSpellPlaced = Config.CurrentSpellPlaced
    env.CurrentSpellTexture = Config.CurrentSpellTexture
    env.CurrentSpellColor = Config.CurrentSpellColor
    env.MockSpellTexture = Config.MockSpellTexture
    env.Round = Config.Round
    env.ClampLayer = Config.ClampLayer
    env.ClassColor = Config.ClassColor
    env.AuraGrowth = Config.AuraGrowth
    env.Int = Config.Int
    env.RefreshHandleSelection = Selection.RefreshHandleSelection
    env.ResolveDefaultZoomLock = Interaction.ResolveDefaultZoomLock
    env.UpdateZoomControls = Interaction.UpdateZoomControls
    env.ClampZoom = Interaction.ClampZoom
    env.buffHandle = Handles.buffHandle
    env.trackedBuffHandle = Handles.trackedBuffHandle
    env.debuffHandle = Handles.debuffHandle
    env.externalHandle = Handles.externalHandle
    env.powerBarHandle = Handles.powerBarHandle
    env.portraitHandle = Handles.portraitHandle
    env.dispelSymbolHandle = Handles.dispelSymbolHandle
    env.spellHandle = Handles.spellHandle
    env.SelectHandle = Handles.SelectHandle
    env.NudgeHandlePosition = Handles.NudgeHandlePosition
    box._msufGFRenderState = env
    function box:SuspendSpellPreviewEffects()
        for _, handle in pairs(self._spellIndicatorHandles or {}) do SuspendHandleEffects(env, handle) end
        SuspendHandleEffects(env, env.spellHandle)
        SuspendHandleEffects(env, selectedSpellEffectOwner)
    end
    --- Refresh is menu-only. It reads compiled/runtime-like specs to draw a mock
    --- group frame and must not rebuild secure headers or subscribe to roster
    --- events.
    function box:Refresh(reason)
        return Stage.Refresh(env, self, reason)
    end
    function box:RefreshAnimation()
        return Stage.Animate(env, self)
    end
    local RefreshHandleSelection, NudgeHandlePosition = env.RefreshHandleSelection, env.NudgeHandlePosition
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    -- Key repeat runs this handler: arrow keys nudge the selected handle and Tab steps through the
    -- placed handles; every other key (and any key typed into an edit box) passes through to the game.
    -- Kept inline, with no helper call per key.
    box:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then
            self._selectedHandle = nil
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            RefreshHandleSelection(self)
            return
        end
        local focusFrame = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        -- Tab steps through the placed handles. Overlapping elements in dense
        -- corners cannot all be reached by clicking, so keyboard traversal is
        -- the only way to select what sits underneath. It also works with
        -- nothing selected yet, and never while an edit box has focus.
        if key == "TAB" and not focusFrame and M.PreviewSelectionBar then
            if M.PreviewSelectionBar.CycleHandle(self, IsShiftKeyDown and IsShiftKeyDown()) then
                if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
                return
            end
        end
        local handle, nudge = self._selectedHandle, KEY_NUDGE[key]
        if not handle or handle._locked or focusFrame or not nudge then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        NudgeHandlePosition(handle, nudge[1], nudge[2])
        RefreshHandleSelection(self)
    end)
end

--- Group preview refresh: the combat and text-drag guards, then every stage in
--- the original order over one shared per-refresh state table.
function Stage.Refresh(env, self, reason)
    if (InCombatLockdown and InCombatLockdown()) or MSUF_InCombat == true then
        self._msufGFRefreshAfterCombat = reason or self._msufGFRefreshAfterCombat or true
        return
    end
    if self._msufGFTextDragActive and reason ~= "GROUP_PREVIEW_TEXT_DRAG" and reason ~= "GROUP_PREVIEW_TEXT_DRAG_END" then
        self._msufGFRefreshReason = reason or self._msufGFRefreshReason
        return
    end
    -- One state table per preview box, emptied for each refresh: the stages
    -- share it without a new table per repaint (review R7 item 9).
    local st = self._msufGFRefreshState
    if st then wipe(st) else
        st = {}
        self._msufGFRefreshState = st
    end
    st.env, st.self, st.reason = env, self, reason
    M.PreviewHelpers.RestoreGroupSceneHandles(self)
    Stage.PrepareScene(st, env)
    Stage.LayoutMockFrame(st, env)
    Stage.ResolveFont(st, env)
    Stage.RenderCell(st, env)
    Stage.PlacePowerHandle(st, env)
    Stage.RenderChrome(st, env)
    Stage.RenderBoundsAndAuras(st, env)
    Stage.ConfigureStatusHandles(st, env)
    Stage.RenderSpellIndicators(st, env)
    -- The animation tick advances this scene (Stage.Animate).
    st.complete, st.animated = true, self._animationEnabled == true
    self._msufGFScene = st
end

--- Animation tick: health, prediction and power fills, the value texts and
--- their handles, and the aura timers, stacks, swipes and duration bars follow
--- the clock on the scene the last full refresh built while the animation
--- ran. Layout, textures, fonts, layers and indicators stay as that refresh
--- placed them. False when there is no such scene (first frame, scope switch)
--- or the full refresh has to decide (combat, text drag): the driver then runs
--- it.
function Stage.Animate(env, self)
    local st = self._msufGFScene
    if not (st and st.complete == true and st.animated == true and self._animationEnabled == true) then return false end
    if (InCombatLockdown and InCombatLockdown()) or MSUF_InCombat == true or self._msufGFTextDragActive then
        return false
    end
    local scene = st.scene
    if scene.kind ~= scene.H.CurrentScope() then return false end
    if self._dragFrame and self._dragFrame._handle then return true end
    M.PreviewHelpers.RestoreGroupSceneHandles(self, false, true)
    st.animatingSamples = true
    -- The scene's own clock: the engine repaints bars, texts and prediction at this elapsed time.
    local sample = self._msufGFCellSample
    if sample.portrait.castSpellIcon then sample.portrait.texture = scene.S.CurrentSpellTexture(scene.kind) end
    if self._scene then self._scene:SetClock(self._animationElapsed) end
    PlaceTextHandles(scene)
    local RenderState = scene.S
    scene.gf.AnimateUnitFrameAuras(st.mock._cell, tonumber(self._animationElapsed) or 0)
    Stage.RenderChrome(st)
    RenderAuras(scene)
    Stage.ConfigureStatusHandles(st, env)
    if scene.engineConfig and scene.engineConfig.spellIndicators then Stage.RenderSpellIndicators(st, env)
    else FinalizeScene(scene) end
    st.animatingSamples = nil
    return true
end

-- Scene fields the refresh state carries flat (Stage.LayoutMockFrame reads them from there).
local STAGE_SCENE_FIELDS = {
    "kind", "label", "conf", "gf", "runtimeSpec", "runtimeHealth", "runtimePower", "runtimeBorder",
}

--- Rebases the preview frame-level band and builds the scene the later
--- stages share.
function Stage.PrepareScene(st, env)
    local reason, self = st.reason, st.self
    local mock = env.mock
    -- Rebase the cached preview into a deterministic local level band before
    -- reading or painting any scene state. Ancestor level changes are not a
    -- render input and must never leak into configured layer calculations.
    local previewRootLevel = SafePreviewFrameLevel(self.GetFrameLevel and self:GetFrameLevel() or 0)
    SetPreviewFrameLevel(self._stage, previewRootLevel + 2)
    SetPreviewFrameLevel(self._layers, previewRootLevel + 3)
    SetPreviewFrameLevel(mock, previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)
    -- One constant translation preserves the exact live ElementLevel order
    -- while keeping every preview visual above the raised mock body.
    mock._msufPreviewElementLevelBias = mock.GetFrameLevel and (mock:GetFrameLevel() or 0)
        or (previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)
    if self._dragFrame then
        SetPreviewFrameLevel(self._dragFrame, PreviewInteractionLevel(mock, Layers, 2))
    end
    local scene = BuildScene(self, reason)
    if self.RefreshRoleButton then self:RefreshRoleButton(scene.kind) end
    for i = 1, #STAGE_SCENE_FIELDS do
        local key = STAGE_SCENE_FIELDS[i]
        st[key] = scene[key]
    end
    st.scene = scene
end
