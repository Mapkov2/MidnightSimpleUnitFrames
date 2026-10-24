local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Scenes.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)

-- Cold-bound policies retain each preview's cleanup, hint and refresh order.
function H.CreateAnimationStarter(inCombat, refresh, refreshButton, clearState, combatHint, finishToggle, unregisterCombat)
    local interval = 1 / 20
    local function Stop(box)
        if not (box and box.SetScript) then return end
        box:SetScript("OnUpdate", nil)
        if unregisterCombat and box.UnregisterEvent then box:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    end
    local function Kill(box)
        if not box then return end
        Stop(box)
        box._animationEnabled = nil
        box._animationElapsed = 0
        box._animationAccum = 0
        clearState(box)
        refreshButton(box)
    end
    local function Tick(box, elapsed)
        if not (box and box._animationEnabled == true and box.IsShown and box:IsShown()) then
            Stop(box)
            return
        end
        if inCombat() then
            Kill(box)
            combatHint(box)
            return
        end
        elapsed = tonumber(elapsed) or 0
        box._animationElapsed = (tonumber(box._animationElapsed) or 0) + elapsed
        box._animationAccum = (tonumber(box._animationAccum) or 0) + elapsed
        if box._animationAccum < interval then return end
        box._animationAccum = 0
        refresh(box)
    end
    local function Start(box)
        if not (box and box._animationEnabled == true) then return end
        if inCombat() then
            Stop(box)
            return
        end
        if box.RegisterEvent then box:RegisterEvent("PLAYER_REGEN_DISABLED") end
        box:SetScript("OnUpdate", Tick)
    end
    local function SetEnabled(box, enabled, reason)
        if not box then return end
        enabled = enabled == true
        if enabled and inCombat() then
            Kill(box)
            combatHint(box)
            refreshButton(box)
            return
        end
        if enabled and box._animationEnabled ~= true then
            box._animationElapsed = 0
            box._animationAccum = 0
        end
        box._animationEnabled = enabled
        if enabled then
            Start(box)
        else
            Stop(box)
            clearState(box, true)
        end
        refreshButton(box)
        finishToggle(box, reason)
    end
    return Start, Stop, Kill, SetEnabled
end

-- Group scenes own these spec/config copies. Sample counts and editor selection must never
-- write into the compiled config shared by live frames or Edit Mode's independent scenes.
local GROUP_SAMPLE_SOURCES = { "auras", "spellIndicators", "cornerIndicators" }
local function CopyPreviewFields(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end
function H.PrepareGroupSceneSamples(frame, scene, inputs)
    local spec = frame.MSUFSpec
    if frame._msufMenuGroupSpec ~= spec then
        spec = CopyPreviewFields(spec)
        for i = 1, #GROUP_SAMPLE_SOURCES do
            local key = GROUP_SAMPLE_SOURCES[i]
            if spec[key] then spec[key] = CopyPreviewFields(spec[key]) end
        end
        frame._msufMenuGroupSpec = spec
        frame.MSUFSpec, frame._msufGFSpecBase = spec, spec
    end
    local auras = MSUF.MSUF_Auras3
    local config = auras.ResolveAuraPreviewConfig(frame, "player", spec)
    scene.auraSampleCount = 40
    for key, lane in pairs(config and config.lanes or {}) do
        local entries = lane._msufMenuEntries or {}
        lane._msufMenuEntries, lane._msufSceneEntries = entries, entries
        local icons = inputs.S.GF_AURA_MOCK_ICON_IDS[key] or inputs.S.GF_AURA_MOCK_ICON_IDS.buff
        local count = math.min(40, math.max(0, math.floor(tonumber(lane.max) or 0)))
        for i = 1, count do
            local entry = entries[i] or {}
            entry.icon = icons and #icons > 0 and icons[((i - 1) % #icons) + 1] or nil
            entries[i] = entry
        end
        for i = #entries, count + 1, -1 do entries[i] = nil end
    end
    local indicators = config and config.spellIndicators
    for _, slot in ipairs(indicators and indicators.slots or {}) do
        if slot._msufMenuEnabled == nil then slot._msufMenuEnabled = slot.enabled == true end
        local selected = slot.specKey == inputs.selectedSpellSpecKey and slot.auraName == inputs.selectedSpellAuraName
        slot.enabled = slot._msufMenuEnabled and (selected or inputs.previewAllSpecSpellIcons == true)
    end
    return config
end

-- Project an engine region into the unscaled interaction plane. Parenting the visual to
-- the handle keeps pointer dragging native: no new call or allocation in the drag update.
local GROUP_HANDLE_OPTIONS = {}
function H.BindGroupSceneHandle(handle, mock, visual, scale, anchor, configX, configY)
    if not handle then return false end
    if not (visual and visual:IsShown()) then
        handle._msufEngineVisual = nil
        handle:Hide()
        return false
    end
    handle._msufEngineVisual = visual
    handle._previewScale, handle._previewWriteScale = scale, scale
    if handle._dragging then return true end
    local regions = handle._msufEngineRegions or {}
    handle._msufEngineRegions, regions[1] = regions, visual
    if not H.PlaceHandleAroundRegions(handle, mock, regions, 0, GROUP_HANDLE_OPTIONS) then return false end
    local fractions = MSUF.MSUF2.GroupPreviewSpecs.ANCHOR_FRAC
    local point = fractions[anchor or "CENTER"] or fractions.CENTER
    local width, height = visual:GetWidth() * scale, visual:GetHeight() * scale
    handle._previewOriginX = (handle:GetWidth() - width) * 0.5 + point[1] * width
    handle._previewOriginY = (handle:GetHeight() - height) * 0.5 + point[2] * height
    handle._previewAnchorFrame = mock
    local _, _, _, x, y = handle:GetPoint(1)
    handle._msufEngineOffsetX = configX and ((x or 0) - configX * scale) or nil
    handle._msufEngineOffsetY = configY and ((y or 0) - configY * scale) or nil
    local geometry = handle._msufEngineGeometry or { points = {} }
    handle._msufEngineGeometry = geometry
    geometry.active = true
    geometry.parent = visual:GetParent()
    geometry.scale = visual.GetScale and visual:GetScale()
    geometry.level = visual.GetFrameLevel and visual:GetFrameLevel()
    geometry.count = visual:GetNumPoints()
    for i = 1, geometry.count do
        local point = geometry.points[i] or {}
        point[1], point[2], point[3], point[4], point[5] = visual:GetPoint(i)
        geometry.points[i] = point
    end
    -- Retail textures also have SetScale; only frames have a frame level.
    if visual.GetFrameLevel then
        -- Aura hosts/portraits are frames. Their children inherit the same scale they
        -- had under the engine frame; the parent is now the unscaled drag handle.
        local level = visual:GetFrameLevel()
        handle._msufEngineFrameLevel = math.max(0, level - 1)
        handle:SetFrameLevel(handle._msufEngineFrameLevel)
        visual:SetParent(handle)
        visual:SetFrameLevel(level)
        visual:SetScale(scale)
        visual:ClearAllPoints()
        visual:SetPoint("CENTER", handle, "CENTER", 0, 0)
    else
        local parent = visual:GetParent()
        local level = parent:GetFrameLevel()
        handle._msufEngineFrameLevel = math.max(0, level - 1)
        handle:SetFrameLevel(handle._msufEngineFrameLevel)
        local holder = handle._msufEngineRegionHost
        if not holder then
            holder = PixelLayoutRegion(CreateFrame("Frame", nil, handle))
            holder:EnableMouse(false)
            handle._msufEngineRegionHost = holder
        end
        holder:SetFrameLevel(level)
        holder:SetScale(scale)
        holder:SetSize(visual:GetWidth(), visual:GetHeight())
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", handle, "CENTER", 0, 0)
        visual:SetParent(holder)
        visual:ClearAllPoints()
        visual:SetPoint("CENTER", holder, "CENTER", 0, 0)
    end
    return true
end

local function GroupSceneDispelTypes(frame, native)
    local present = frame._msufMenuDispelTypes
    if not present then
        present = {}
        frame._msufMenuDispelTypes = present
        for i = 1, #native.DispelTypes do present[native.DispelTypes[i]] = true end
    end
    return present
end
function H.PaintGroupSceneDispel(frame, config)
    local auras = MSUF.MSUF_Auras3
    if auras.PaintSceneEffects then
        auras.PaintSceneEffects(frame, config and config.sensors)
    else
        local visual, native = config and config.visual, auras.ClassicVisuals
        local present = GroupSceneDispelTypes(frame, native)
        native.UpdateDispelOverlay(frame, visual, visual and visual.overlayEnabled,
            visual and visual.r, visual and visual.g, visual and visual.b, 1)
        native.UpdateDispelSymbols(frame, visual, present)
        frame._msufSceneDispelOverlay = frame._msufA3ClassicDispelOverlayHost
        frame._msufSceneDispelSymbol = frame._msufA3ClassicDispelSymbolHost
    end
end

-- Reattach before engine layout/teardown so native caches and pooling retain their
-- own parents/anchors. No listener, ticker or hook runs outside an open menu preview.
function H.RestoreGroupSceneHandles(box, force, keepSpellSamples)
    for region, alpha in pairs(box._msufMenuAlphaRegions or {}) do region:SetAlpha(alpha) end
    for _, handle in ipairs(box._handleList or {}) do
        local visual, geometry = handle._msufEngineVisual, handle._msufEngineGeometry
        if visual and geometry and geometry.active and (force or not handle._dragging)
            and not (keepSpellSamples and visual._msufMenuSpellSample) then
            visual:SetParent(geometry.parent)
            if geometry.scale then visual:SetScale(geometry.scale) end
            if geometry.level then visual:SetFrameLevel(geometry.level) end
            visual:ClearAllPoints()
            for i = 1, geometry.count do
                local point = geometry.points[i]
                visual:SetPoint(point[1], point[2], point[3], point[4], point[5])
            end
            geometry.active = false
            -- A selection sample is repainted only if it is still needed. The
            -- configured-slot pool is refreshed separately by the engine scene.
            if visual._msufMenuSpellSample then MSUF.GF.HidePreviewSpellSample(visual) end
        end
    end
end

function H.ApplyGroupSceneLayerAlpha(box, region, multiplier)
    if not region then return end
    local regions = box._msufMenuAlphaRegions
    if not regions then regions = {} box._msufMenuAlphaRegions = regions end
    local alpha = region:GetAlpha()
    regions[region] = alpha
    region:SetAlpha(alpha * multiplier)
end

function H.BindPreviewAnimationButton(button, box, toggle, active, inCombat, setEnabled, reason)
    button:SetScript("OnClick", function(self) toggle(self._preview) end)
    button._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return active(box) end,
        set = function(enabled)
            if enabled == true and inCombat() then return false end
            setEnabled(box, enabled == true, reason)
            return active(box) == (enabled == true)
        end,
    }
end
