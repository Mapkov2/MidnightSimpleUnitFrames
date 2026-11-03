-- Resolves the selected group configuration and samples into one reusable scene.
-- Per-box state stays on its owner; this module performs no handle presentation.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
M.GroupRenderFactories = M.GroupRenderFactories or {}
M.GroupRenderFactories.Plan = function(runtime, scene)
    RequireFields("GroupPlan.Runtime", runtime, "Exports Wipe")
    RequireFields("GroupPlan.Scene", scene,
        "AuraLanes BuildAuraLanes BuildSpells StatusAvailable AuraAvailable AuraTextAvailable SampleLayerSections")
    local CoreExports, wipe = runtime.Exports, runtime.Wipe
    local AURA_LANES, BuildSceneAuraLanes, BuildSceneSpells = scene.AuraLanes, scene.BuildAuraLanes, scene.BuildSpells
    local SceneStatusAvailable = scene.StatusAvailable
    local SceneAuraLaneAvailable, SceneAuraLaneTextAvailable = scene.AuraAvailable, scene.AuraTextAvailable
    local SAMPLE_LAYER_SECTIONS = scene.SampleLayerSections
    local min, max = math.min, math.max
-- Scene field -> compiled spec section.
local RUNTIME_SPEC_SECTIONS = {
    runtimeText = "text", runtimePower = "power", runtimeHealth = "health", runtimeBorder = "border",
    runtimeTempMaxHealth = "tempMaxHealth", runtimePrediction = "prediction", runtimeStatus = "status",
}

local function BuildSceneLayers(scene, box, kind, conf, runtimeSpec)
    local RenderState, gf = scene.S, scene.gf
    local statusAvailable = false
    for i = 1, #RenderState.statusSpecs do
        local spec = RenderState.statusSpecs[i]
        if RenderState.StatusSpecInMode(spec, scene.statusSpec) and SceneStatusAvailable(scene, spec) then
            statusAvailable = true
            break
        end
    end
    local aurasEnabled, powerTextEnabled
    if scene.runtimeAuras then
        local custom = false
        for i = 1, #AURA_LANES do
            if scene[AURA_LANES[i][3]].enabled == true then
                custom = true
                break
            end
        end
        scene.customRenderer = custom
        aurasEnabled = custom or scene.runtimeAuras.enabled == true
    else
        scene.customRenderer = true
        aurasEnabled = scene.rawAuras.enabled ~= false
    end
    if runtimeSpec then
        powerTextEnabled = runtimeSpec.showPowerText == true
    else
        powerTextEnabled = (gf and gf.IsPowerTextEnabled and gf.IsPowerTextEnabled(kind, conf))
            or conf.showPowerText == true or conf.showPower == true
    end
    local customAuraText = false
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        if SceneAuraLaneTextAvailable(scene, scene[lane[3]], lane[4]) then
            customAuraText = true
            break
        end
    end
    local textAvailable
    if runtimeSpec then
        textAvailable = runtimeSpec.showName == true
            or runtimeSpec.showHealthText == true or powerTextEnabled == true
    else
        textAvailable = conf.showName ~= false or conf.showHPText ~= false or powerTextEnabled == true
    end
    local selectedSpellAvailable = conf.spellIndicators and conf.spellIndicators.enabled == true
        and (scene.selectedSpellPlacedEnabled or scene.selectedSpellNeedsPlacementPreview
            or scene.selectedSpellEffectAvailable)
    -- Same role-gated enablement the runtime uses: the layer is unavailable
    -- (not merely hidden) when the bar is off for the preview role.
    local powerAvailable
    if runtimeSpec then
        powerAvailable = scene.runtimePower and scene.runtimePower.enabled == true or false
    else
        powerAvailable = (tonumber(scene.H.MockPowerHeight(kind, conf, 1, 1)) or 0) > 0
    end
    local layerAvailable = box._msufGFLayerAvailableState
    if not layerAvailable then
        layerAvailable = {}
        box._msufGFLayerAvailableState = layerAvailable
    end
    layerAvailable.guides, layerAvailable.bounds = true, true
    layerAvailable.power = powerAvailable
    layerAvailable.portrait = kind == "party" and runtimeSpec and runtimeSpec.portrait
        and runtimeSpec.portrait.enabled == true or false
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        layerAvailable[lane[1]] = SceneAuraLaneAvailable(scene, scene[lane[3]], lane[4])
    end
    layerAvailable.status = statusAvailable
    layerAvailable.si = scene.runtimeSpellIndicators and scene.runtimeSpellIndicators.enabled == true
        and (scene.runtimeSpellPlacedAvailable or scene.runtimeSpellEffectAvailable)
        or selectedSpellAvailable or false
    layerAvailable.auraText = aurasEnabled and customAuraText
    layerAvailable.text = textAvailable
    layerAvailable.dispelOverlay = runtimeSpec and runtimeSpec.group
        and runtimeSpec.group.dispelOverlayEnabled == true or false
    layerAvailable.dispelSymbol = runtimeSpec and runtimeSpec.dispelSymbol
        and runtimeSpec.dispelSymbol.enabled == true or false
    scene.layerAvailable = layerAvailable
    box._layerAvailable = layerAvailable
    if scene.soloLayer and layerAvailable[scene.soloLayer] == false then
        scene.M.gfPreviewSoloLayer = nil
        scene.soloLayer = nil
    end
end

local function BuildScene(box, reason)
    local RenderState = box._msufGFRenderState
    local H, M, runtimeNS = RenderState.H, RenderState.M, RenderState.MSUF
    local kind = H.CurrentScope()
    local conf = H.Conf(kind)
    local gf = runtimeNS and runtimeNS.GF
    local previewAnimation = runtimeNS and runtimeNS.PreviewAnimation
    local buildFrameState = previewAnimation and previewAnimation.BuildFrameState
        or CoreExports.BuildAnimationFrameState
    local animState = box._animationEnabled == true
        and buildFrameState(box, 1, kind, box._msufGFMenuPreviewAnimState or {}, box._animationElapsed)
    if animState then box._msufGFMenuPreviewAnimState = animState end
    local runtimeSpec = RenderState.CompiledSpec(kind)
    -- The group cell mirrors the player's current state (name, class, exact HP/power/absorb) so the preview matches
    -- the live group frame. Pull-based only: sampled during this refresh, stylized values back any missing field.
    -- The engine scene stays unit-free; this stage reads the unit and hands the scene a sample.
    local preview = runtimeNS and runtimeNS.UFPreview
    local liveData = preview and preview.LiveUnitData and preview.LiveUnitData("player") or nil
    -- One scene table per preview box, emptied for each refresh, so a repaint
    -- builds no new scene (review R7 item 9).
    local scene = box._msufGFSceneState
    if scene then wipe(scene) else
        scene = {}
        box._msufGFSceneState = scene
    end
    scene.S, scene.box, scene.reason, scene.H, scene.M, scene.MSUF = RenderState, box, reason, H, M, runtimeNS
    scene.mock, scene.kind, scene.label, scene.conf, scene.gf = RenderState.mock, kind, H.PreviewScopeLabel(kind), conf, gf
    scene.previewAnimation, scene.animState, scene.liveData = previewAnimation, animState, liveData
    scene.hpPct = animState and max(0.02, min(0.98, tonumber(animState.hpPct) or 0.72)) or (liveData and liveData.hp) or 0.72
    scene.powerPct = animState and max(0, min(1, tonumber(animState.powerPct) or 0.70)) or (liveData and liveData.power) or 0.70
    scene.healPct = animState and max(0.01, min(0.24, tonumber(animState.healPct) or 0.12)) or 0.12
    scene.absorbPct = animState and max(0.01, min(0.24, tonumber(animState.absorbPct) or 0.08)) or 0.08
    scene.runtimeSpec = runtimeSpec
    scene.runtimeAuras = runtimeSpec and runtimeSpec.auras
    for field, section in pairs(RUNTIME_SPEC_SECTIONS) do
        scene[field] = runtimeSpec and runtimeSpec[section] or {}
    end
    scene.focus = H.PreviewFocusForPage(RenderState.ctx.key)
    scene.layerVisible = type(M.gfPreviewLayerVisible) == "table" and M.gfPreviewLayerVisible or {}
    -- The sample-effect layers follow their open settings section on the Group Bars page (an edge, so a chip click sticks).
    M.PreviewHelpers.SyncSampleLayerSections(M, scene.layerVisible, "gf_bars", SAMPLE_LAYER_SECTIONS,
        M.accordionState, M.activeKey)
    scene.soloLayer = M.gfPreviewSoloLayer
    scene.textHandles = box._textHandles or {}
    scene.previewRole = H.PreviewRole and H.PreviewRole(kind) or RenderState.GF_PREVIEW_ROLE
    BuildSceneAuraLanes(scene, box, kind, conf, runtimeSpec)
    BuildSceneSpells(scene, box, kind, conf)
    BuildSceneLayers(scene, box, kind, conf, runtimeSpec)
    return scene
end

return BuildScene
end
