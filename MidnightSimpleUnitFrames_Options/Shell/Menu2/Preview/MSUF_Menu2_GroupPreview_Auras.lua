-- Auras state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.GroupRenderFactories = M.GroupRenderFactories or {}

M.GroupRenderFactories.Auras = function(
    MSUF, M, wipe, max, Stage
)

local EMPTY_RAW_LANE = {}
-- Tracked lane field -> the tracked buff setting it copies as it stands.
local TRACKED_LANE_COPIES = {
    showCooldownSwipe = "trackedShowCooldownSwipe", cooldownSwipeReverse = "trackedCooldownSwipeReverse",
    showCooldown = "trackedShowCooldown", showCooldownText = "trackedShowCooldown", showStacks = "trackedShowStacks",
    showTooltip = "trackedShowTooltip", showDurationBar = "trackedShowDurationBar",
    durationBarHeight = "trackedDurationBarHeight", durationBarDisplay = "trackedDurationBarDisplay",
    durationBarPosition = "trackedDurationBarPosition", durationBarDirection = "trackedDurationBarDirection",
    cooldownSize = "trackedCooldownSize", cooldownAnchor = "trackedCooldownAnchor", cooldownX = "trackedCooldownX",
    cooldownY = "trackedCooldownY", cooldownDecimalSeconds = "trackedCooldownDecimalSeconds",
    stackSize = "trackedStackSize", stackAnchor = "trackedStackAnchor", stackX = "trackedStackX", stackY = "trackedStackY",
}
local function RawTrackedBuffLane(scene, rawBuff, out)
    rawBuff = rawBuff or EMPTY_RAW_LANE
    local indicators = scene.conf.spellIndicators
    out.enabled = rawBuff.trackedEnabled == true
        or (rawBuff.trackedEnabled == nil and indicators and indicators.enabled == true)
    out.max = rawBuff.trackedMax or 8
    out.perRow = rawBuff.trackedPerRow or rawBuff.perRow or 4
    out.size = rawBuff.trackedSize or rawBuff.size or 22
    out.spacing = rawBuff.trackedSpacing or rawBuff.spacing or 1
    out.anchor = rawBuff.trackedAnchor or "TOPLEFT"
    out.growth = rawBuff.trackedGrowth or "RIGHTDOWN"
    out.x = rawBuff.trackedX or 0
    out.y = rawBuff.trackedY or 0
    out.layer = rawBuff.trackedLayer or (indicators and indicators.layer) or 9
    out.strata = rawBuff.trackedStrata or (indicators and indicators.strata) or rawBuff.strata
    for field, setting in pairs(TRACKED_LANE_COPIES) do out[field] = rawBuff[setting] end
    return out
end

local function SceneAuraLaneAvailable(scene, cfg, defaultMax)
    return scene.customRenderer
        and (scene.runtimeAuras and cfg.enabled == true or cfg.enabled ~= false)
        and (tonumber(cfg.max) or defaultMax or 0) > 0
end

--- A compiled Auras3 lane carries a resolved layout signature; a raw config
--- never does. The two spell the cooldown text differently, so every reader of
--- that flag has to branch on the same test.
local function IsRuntimeAuraLane(cfg)
    return cfg._msufA3LayoutSignature ~= nil and cfg.initialAnchor ~= nil
        and cfg.xSign ~= nil and cfg.ySign ~= nil
end

--- The CD/Stack chip owns the timer and stack texts printed on the aura icons,
--- so it is only "on in settings" when a lane that draws icons actually prints
--- one of them. Reporting it available off the bare lane made the chip claim a
--- layer that had nothing to show.
local function SceneAuraLaneTextAvailable(scene, cfg, defaultMax)
    if not SceneAuraLaneAvailable(scene, cfg, defaultMax) then return false end
    if cfg.showStacks ~= false then return true end
    if IsRuntimeAuraLane(cfg) then return cfg.showCooldownText == true end
    return cfg.showCooldown ~= false
end

local AURA_PREVIEW_RAW_FIELDS = {
    "showCooldownSwipe", "cooldownSwipeReverse", "showCooldown", "showCooldownText", "showStacks", "showTooltip",
    "showDurationBar", "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY", "cooldownDecimalSeconds",
    "stackSize", "stackAnchor", "stackX", "stackY", "dispelBorderMode", "showDispelBorder", "showDispelSymbol",
}

local function OverlayRawAuraPreviewStyle(compiled, raw)
    if type(compiled) ~= "table" or type(raw) ~= "table" then return compiled end
    for i = 1, #AURA_PREVIEW_RAW_FIELDS do
        local key = AURA_PREVIEW_RAW_FIELDS[i]
        if raw[key] ~= nil then compiled[key] = raw[key] end
    end
    return compiled
end

local function PreviewIconScale(value)
    value = tonumber(value) or 100
    if value < 20 then value = 20 elseif value > 300 then value = 300 end
    return value / 100
end

-- The four aura lanes in paint order: lane key, handle field, config field, default max icons, default layer.
local AURA_LANES = {
    { "buff", "buffHandle", "buffCfg", 6, 5 },
    { "trackedBuff", "trackedBuffHandle", "trackedBuffCfg", 4, 9 },
    { "debuff", "debuffHandle", "debuffCfg", 6, 6 },
    { "external", "externalHandle", "externalCfg", 2, 7 },
}
local function ResolveLaneConfig(scene, runtimeLanes, key, raw, lanes)
    local cfg = runtimeLanes and runtimeLanes[key]
    if cfg then return cfg end
    cfg = scene.runtimeAuras and scene.S.CompiledAuraLane(scene.runtimeAuras, key, raw or {}, lanes[key])
    return cfg or raw or {}
end

local function BuildSceneAuraLanes(scene, box, kind, conf, runtimeSpec)
    local rawAuras = conf.auras or {}
    local trackedRawState = box._msufGFTrackedRawState
    if not trackedRawState then
        trackedRawState = {}
        box._msufGFTrackedRawState = trackedRawState
    end
    local trackedRaw = RawTrackedBuffLane(scene, rawAuras.buff, trackedRawState)
    local a3 = scene.MSUF and scene.MSUF.MSUF_Auras3
    local runtimeAuraConfig
    if runtimeSpec and a3 and a3.ResolveAuraPreviewConfig then
        local proxy = box._msufA3GroupPreviewConfigProxy or {}
        box._msufA3GroupPreviewConfigProxy = proxy
        proxy._msufIsGroupFrame = true
        proxy._msufGFIsPreviewFrame = true
        proxy._msufGFKind = kind
        proxy.MSUFUnitKey = "player"
        proxy.MSUFSpec = runtimeSpec
        runtimeAuraConfig = a3.ResolveAuraPreviewConfig(proxy, "player")
    end
    scene.runtimeAuraConfig = runtimeAuraConfig
    local runtimeLanes = runtimeAuraConfig and runtimeAuraConfig.lanes
    scene.rawAuras = rawAuras
    scene.auraIconZoom = tonumber(rawAuras.iconZoom) or tonumber(scene.runtimeAuras and scene.runtimeAuras.iconZoom) or 100
    -- Compiled lanes are rebuilt into tables kept per preview box.
    local lanes = box._msufGFCompiledLaneState
    if not lanes then
        lanes = { buff = {}, trackedBuff = {}, debuff = {}, external = {} }
        box._msufGFCompiledLaneState = lanes
    end
    scene.buffCfg = ResolveLaneConfig(scene, runtimeLanes, "buff", rawAuras.buff, lanes)
    scene.trackedBuffCfg = ResolveLaneConfig(scene, runtimeLanes, "trackedBuff", trackedRaw, lanes)
    scene.debuffCfg = ResolveLaneConfig(scene, runtimeLanes, "debuff", rawAuras.debuff, lanes)
    scene.externalCfg = ResolveLaneConfig(scene, runtimeLanes, "external", rawAuras.externals, lanes)
    if not runtimeLanes then
        OverlayRawAuraPreviewStyle(scene.buffCfg, rawAuras.buff)
        OverlayRawAuraPreviewStyle(scene.trackedBuffCfg, trackedRaw)
        OverlayRawAuraPreviewStyle(scene.debuffCfg, rawAuras.debuff)
        OverlayRawAuraPreviewStyle(scene.externalCfg, rawAuras.externals)
    end
end

-- The selected spell, its placement and frame effect, and the spell items the preview paints.
-- A group lane icon is size x size; the swipe and duration bar painters are the shared core ones.
local function BuildAuraLaneHelpers(st, RenderState)
    local mock = RenderState.mock
    local GF_PREVIEW_ANCHOR_FRAC = RenderState.GF_PREVIEW_ANCHOR_FRAC
    local Round, ConfigToOffset = RenderState.Round, RenderState.ConfigToOffset
    local function LayoutHandle(handle, anchor, x, y, defaultAnchor)
        local previewScale = st.previewScale
        anchor = anchor or defaultAnchor or "CENTER"
        if not GF_PREVIEW_ANCHOR_FRAC[anchor] then anchor = defaultAnchor or "CENTER" end
        handle._previewScale = previewScale
        handle._previewWriteScale = previewScale
        handle:ClearAllPoints()
        handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))
    end
    return { st = st, S = RenderState, LayoutHandle = LayoutHandle }
end
function Stage.PrepareAuraLanes(st)
    local scene = st.scene
    local RenderState, box = scene.S, scene.box
    local helpers = box._msufGFAuraLaneHelpers
    if not helpers or helpers.st ~= st or helpers.S ~= RenderState then
        helpers = BuildAuraLaneHelpers(st, RenderState)
        box._msufGFAuraLaneHelpers = helpers
    end
    st.previewScale = scene.previewScale
    st.LayoutHandle = helpers.LayoutHandle
end

-- Layout preparation and visual adoption are separate cold options stages. The old
-- 233-line icon painter duplicated the engine's own lane/shape/font painters.
function Stage.PrepareAuraHandle(st, handle, groupKey, cfg)
    local scene, frame = st.scene, st.scene.mock._cell
    local hosts = frame and frame._msufGFFrameAuraPreviewHosts
    local host = hosts and hosts[groupKey]
    if not host then handle:Hide() return nil end
    -- Restore engine ownership before measuring the configured layout. A previous
    -- drag may have parented the host to its interaction handle.
    local scale = scene.previewScale
    handle._previewWriteScale = scale * ((scene.runtimeAuras and scene.runtimeAuras.dynamicScaleValue) or 1)
    return host, scale
end
function Stage.LayoutAuraGroup(st, handle, groupKey, cfg)
    local host, scale = Stage.PrepareAuraHandle(st, handle, groupKey, cfg)
    if not host then return end
    local frame = st.scene.mock._cell
    -- Engine aura visuals are pooled on the cell, with anchors in the lane host.
    -- Adopt them into that host once; native parent motion then follows a drag.
    for _, visual in ipairs(frame._msufGFFrameAuraPreviews or {}) do
        if visual._sceneAuraLane == cfg and visual:GetParent() ~= host then visual:SetParent(host) end
    end
    M.PreviewHelpers.BindGroupSceneHandle(handle, st.scene.mock, host, scale, cfg.anchor)
    handle._previewWriteScale = scale * ((st.scene.runtimeAuras and st.scene.runtimeAuras.dynamicScaleValue) or 1)
end

--- Lays out the buff, tracked buff, debuff and external lanes and publishes
--- the lane helpers on the scene for the status and spell indicator stages.
local function RenderAuras(scene)
    -- The lane state is kept per preview box and emptied for each refresh.
    local box = scene.box
    local st = box._msufGFAuraState
    if st then wipe(st) else
        st = {}
        box._msufGFAuraState = st
    end
    st.scene = scene
    -- Aura samples follow the box's animation time; a static preview has none.
    st.auraElapsed = box._animationEnabled == true and (tonumber(box._animationElapsed) or 0) or nil
    Stage.PrepareAuraLanes(st)
    for i = 1, #AURA_LANES do
        local lane = AURA_LANES[i]
        local handle = scene.S[lane[2]]
        if handle then Stage.LayoutAuraGroup(st, handle, lane[1], scene[lane[3]]) end
    end
    scene.LayoutHandle = st.LayoutHandle
end

return SceneAuraLaneAvailable, SceneAuraLaneTextAvailable, PreviewIconScale, AURA_LANES, BuildSceneAuraLanes, RenderAuras
end
