-- Presents group-preview text handles, strata, visibility and range alpha.
-- The renderer retains stage order and coordinates the spell-level pass.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
M.GroupRenderFactories = M.GroupRenderFactories or {}
M.GroupRenderFactories.Presentation = function(runtime, layout, layers)
    RequireFields("GroupPresentation.Runtime", runtime, "Menu")
    RequireFields("GroupPresentation.Layout", layout, "SetFrameLevel TextHandleKeys TextSlotHandleKeys AuraLanes")
    RequireFields("GroupPresentation.Layers", layers, "IsOn Alpha StatusAvailable")
    local M = runtime.Menu
    local SetPreviewFrameLevel, AURA_LANES = layout.SetFrameLevel, layout.AuraLanes
    local TEXT_HANDLE_KEYS, TEXT_SLOT_HANDLE_KEYS = layout.TextHandleKeys, layout.TextSlotHandleKeys
    local SceneLayerOn, SceneLayerAlpha, SceneStatusAvailable = layers.IsOn, layers.Alpha, layers.StatusAvailable
    local min, max = math.min, math.max
local PREDICTION_BAR_FIELDS = { "_healPred", "_absorb", "_healAbsorb" }
local function TextRegionList(box, key, a, b, c)
    local lists = box._msufGFTextRegionLists
    if not lists then
        lists = {}
        box._msufGFTextRegionLists = lists
    end
    local list = lists[key]
    if not list then
        list = {}
        lists[key] = list
    end
    list[1], list[2], list[3] = a, b, c
    return list
end
-- Animation-tick path: the handle placements stay inline, one Lua call per handle and no wrapper.
local function PlaceTextHandleGroup(scene, handles, groupKey, prefix, left, center, right)
    local box, mock, H = scene.box, scene.mock, scene.H
    local keys = TEXT_SLOT_HANDLE_KEYS[prefix]
    if H.TextMovesTogether(scene.kind, prefix) then
        handles[keys[1]]:Hide()
        handles[keys[2]]:Hide()
        handles[keys[3]]:Hide()
        if not H.PlaceHandleAroundRegions(handles[groupKey], mock, TextRegionList(box, prefix, left, center, right), 3) then
            handles[groupKey]:Hide()
        end
    else
        handles[groupKey]:Hide()
        if not H.PlaceHandleAroundRegions(handles[keys[1]], mock, TextRegionList(box, keys[1], left), 3) then
            handles[keys[1]]:Hide()
        end
        if not H.PlaceHandleAroundRegions(handles[keys[2]], mock, TextRegionList(box, keys[2], center), 3) then
            handles[keys[2]]:Hide()
        end
        if not H.PlaceHandleAroundRegions(handles[keys[3]], mock, TextRegionList(box, keys[3], right), 3) then
            handles[keys[3]]:Hide()
        end
    end
end
local function PlaceTextHandles(scene)
    local box, mock, H = scene.box, scene.mock, scene.H
    local handles = scene.textHandles
    for i = 1, #TEXT_HANDLE_KEYS do handles[TEXT_HANDLE_KEYS[i]]._previewScale = scene.previewScale end
    -- With the Text layer off the cell draws no text, so there is nothing for a handle to wrap.
    if not SceneLayerOn(scene, "text") then
        for i = 1, #TEXT_HANDLE_KEYS do handles[TEXT_HANDLE_KEYS[i]]:Hide() end
        H.ApplyTextFocus(box, mock)
        return
    end
    -- Name is a natural-width FontString. Its actual region is the sole source
    -- for glyph, grab-handle and focus geometry.
    if not H.PlaceHandleAroundRegions(handles.name, mock, TextRegionList(box, "name", mock._nameFS), 3, "name") then handles.name:Hide() end
    PlaceTextHandleGroup(scene, handles, "hpGroup", "hp", mock._hpLeftFS, mock._hpCenterFS, mock._hpRightFS)
    PlaceTextHandleGroup(scene, handles, "powerGroup", "power", mock._powerLeftFS, mock._powerCenterFS, mock._powerRightFS)
    H.ApplyTextFocus(box, mock)
end

--- Strata of the preview host. Handles and effect roots stay on it: the live
--- runtime keeps every layer-aware element on its owning frame's strata, so
--- neither a live frame's strata nor a configured legacy strata applies here.
local function PreviewHostStrata(scene)
    local RenderState = scene.S
    local host = scene.mock.GetFrameStrata and scene.mock:GetFrameStrata()
    if RenderState.issecretvalue(host) == true or not host or host == "" then
        host = scene.box.GetFrameStrata and scene.box:GetFrameStrata()
        if RenderState.issecretvalue(host) == true or host == "" then host = nil end
    end
    return host
end

local function ApplyHandleStrata(scene, handle, host)
    local RenderState = scene.S
    if handle and handle.SetFrameStrata and host then
        local current = handle.GetFrameStrata and handle:GetFrameStrata()
        if RenderState.issecretvalue(current) == true or current ~= host then handle:SetFrameStrata(host) end
    end
end

local function SyncIconDetailLevels(layers, handle)
    if not (handle and handle.GetFrameLevel) then return end
    layers = layers or {}
    local baseLevel = handle:GetFrameLevel() or 0
    SetPreviewFrameLevel(handle._iconDurationLayer,
        baseLevel + (layers.AURA_DURATION_BAR_LEVEL_OFFSET or 2))
    SetPreviewFrameLevel(handle._iconSwipeLayer,
        baseLevel + (layers.AURA_COOLDOWN_LEVEL_OFFSET or 4))
    SetPreviewFrameLevel(handle._iconTextLayer,
        baseLevel + (layers.AURA_TEXT_LEVEL_OFFSET or 8))
end

local ENGINE_TEXT_FIELDS = { "nameText", "hpTextLeft", "hpTextCenter", "hpTextRight",
    "powerTextLeft", "powerTextCenter", "powerTextRight" }
-- Shown state and layer alpha of the handles that follow a settings layer.
local function FinalizeVisibility(scene)
    local RenderState = scene.S
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        local handle, key = RenderState[lane[2]], lane[1]
        if handle then
            handle:SetShown(scene.layerAvailable[key] and SceneLayerOn(scene, key))
            handle:SetAlpha(SceneLayerAlpha(scene, key) * (scene.engineAlpha or 1))
        end
    end
    for i = 1, #RenderState.statusHandles do
        local handle = RenderState.statusHandles[i]
        local spec = handle and handle._statusSpec
        if handle then
            handle:SetShown(RenderState.StatusSpecInMode(spec, scene.statusSpec)
                and SceneStatusAvailable(scene, spec) and SceneLayerOn(scene, "status"))
            handle:SetAlpha(SceneLayerAlpha(scene, "status") * (scene.engineAlpha or 1))
        end
    end
    local spellVisible = scene.layerAvailable.si and SceneLayerOn(scene, "si")
    local selectedEffectOwner = scene.box._msufGFSelectedSpellEffectOwner
    if selectedEffectOwner then
        selectedEffectOwner:SetShown(spellVisible and scene.selectedSpellEffectAvailable == true)
    end
    local selected = scene.selectedSpellCfg
    RenderState.spellHandle:SetShown(spellVisible)
    RenderState.spellHandle:SetAlpha(selected and selected.enabled == false and SceneLayerAlpha(scene, "si") * 0.45
        or SceneLayerAlpha(scene, "si"))
    for _, handle in pairs(scene.dynamicSpellHandlesActive or {}) do
        handle:SetShown(spellVisible)
        handle:SetAlpha(SceneLayerAlpha(scene, "si"))
    end
    for i = 1, #TEXT_HANDLE_KEYS do scene.textHandles[TEXT_HANDLE_KEYS[i]]:SetAlpha(SceneLayerAlpha(scene, "text")) end
    local frame, helpers = scene.mock._cell, M.PreviewHelpers
    if frame then
        local textAlpha = SceneLayerAlpha(scene, "text")
        for i = 1, #ENGINE_TEXT_FIELDS do
            helpers.ApplyGroupSceneLayerAlpha(scene.box, frame[ENGINE_TEXT_FIELDS[i]], textAlpha)
        end
        helpers.ApplyGroupSceneLayerAlpha(scene.box, frame.targetPowerBar, SceneLayerAlpha(scene, "power"))
        local bar, trail = frame.targetPowerBar, frame.powerLossTrail
        if bar and trail and bar._msufChunkedLoss then
            local pool = trail._msufLossTrailPool
            local alpha = bar:GetStatusBarTexture():GetAlpha() * bar:GetAlpha()
            for i = 1, pool and #pool or 1 do
                local snapshot = pool and pool[i] or trail
                local fill = snapshot:GetStatusBarTexture()
                if fill:GetAlpha() ~= alpha then fill:SetAlpha(alpha) end
                if not bar:IsShown() then snapshot:Hide() end
            end
        end
    end
end

-- The out-of-range fade of the Options preview: whole frame, or the health bar and its prediction bars only.
local function FinalizeRangeFade(scene)
    local box, mock = scene.box, scene.mock
    local rangeAlpha = tonumber(box._msuf2RangeFadePreviewAlpha)
    if rangeAlpha ~= nil then rangeAlpha = max(0, min(1, rangeAlpha)) end
    local rangeHealthOnly = rangeAlpha ~= nil and box._msuf2RangeFadePreviewLayerMode == "health"
    local wholeFrameMul = rangeAlpha ~= nil and not rangeHealthOnly and rangeAlpha or 1
    local healthMul = rangeHealthOnly and rangeAlpha or 1
    if mock.SetAlpha then mock:SetAlpha(wholeFrameMul) end
    if mock._health and mock._health.SetAlpha then mock._health:SetAlpha(healthMul) end
    local trail = mock._cell and mock._cell.healthLossTrail
    if trail and mock._health._msufChunkedLoss then
        local fill = trail:GetStatusBarTexture()
        local alpha = mock._health:GetStatusBarTexture():GetAlpha() * healthMul
        if fill:GetAlpha() ~= alpha then
            fill:SetAlpha(alpha)
        end
    end
    -- The engine paints each prediction bar at its configured opacity (the bar's alpha): the range fade scales it.
    for i = 1, #PREDICTION_BAR_FIELDS do
        local bar = mock[PREDICTION_BAR_FIELDS[i]]
        if bar and bar.SetAlpha then bar:SetAlpha((tonumber(bar._msufA) or 1) * healthMul) end
    end
    for i = 1, #(box._handleList or {}) do
        local handle = box._handleList[i]
        if handle and handle.SetAlpha and handle.GetParent and handle:GetParent() ~= mock then
            handle:SetAlpha((handle.GetAlpha and handle:GetAlpha() or 1) * wholeFrameMul)
        end
    end
end

return { PlaceTextHandles = PlaceTextHandles, HostStrata = PreviewHostStrata,
    ApplyHandleStrata = ApplyHandleStrata, SyncIconDetailLevels = SyncIconDetailLevels,
    FinalizeVisibility = FinalizeVisibility, FinalizeRangeFade = FinalizeRangeFade }
end
