--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua
--- Castbar preview configuration, scene composition and interaction handles.
---
--- Resolves castbar DB fields and the configured size for the Menu2 previews, which paint the engine's
--- castbar scene. It does not subscribe to UNIT_SPELLCAST events or mutate live castbar frames.
local _, MSUF = ...
local FILE = "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua"
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local CanonKey = PreviewModel.CanonKey
local Castbar = MSUF.UFPreviewCastbar or {}
MSUF.UFPreviewCastbar = Castbar
local CoreFrame = MSUF.UF.GetFrame
local EMPTY_DETAILS = {}
-- The castbar module API is published once by the core castbar files, which load before this addon. It is
-- resolved here because these lookups run on every preview refresh and drag step.
local GetCastbarDefaultOffsets = MSUF.Require("MSUF_GetCastbarDefaultOffsets", FILE)
local GetCastbarPrefix = MSUF.Require("MSUF_GetCastbarPrefix", FILE)
local NormalizeWidthSource = MSUF.Require("MSUF_NormalizeCastbarWidthSource", FILE)
local GetCastbarWidthSourceKey = MSUF.Require("MSUF_GetCastbarWidthSourceKey", FILE)
local GetCastbarDesiredSize = MSUF.Require("MSUF_GetCastbarDesiredSize", FILE)
local ShouldUseMSUFCastbar = MSUF.Require("MSUF_ShouldUseMSUFCastbar", FILE)
local GetEffectiveCooldownFrame = MSUF.Require("MSUF_GetEffectiveCooldownFrame", FILE)
local CDMGetScaledWidth = MSUF.Require("MSUF_CDM_GetScaledWidth", FILE)
local PREVIEW_CASTBAR_KEYS = { player = "playerPreview", target = "targetPreview", focus = "focusPreview" }
local RUNTIME_UNITS = { boss = "boss1", arena = "arena1" }
function Castbar.OffsetFields(unitKey)
    -- Runtime and preview need the same DB keys for offsets, but only runtime owns live frame
    -- anchoring. Keep the key translation here and the actual SetPoint calls in render code.
    unitKey = CanonKey(unitKey)
    local dx, dy = GetCastbarDefaultOffsets(unitKey)
    dx, dy = dx or 0, dy or 0
    if unitKey == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY", dx, dy end
    if unitKey == "arena" then return "arenaCastbarOffsetX", "arenaCastbarOffsetY", dx, dy end
    local prefix = GetCastbarPrefix(unitKey)
    if not prefix or prefix == "" then return nil, nil, dx, dy end
    return prefix .. "OffsetX", prefix .. "OffsetY", dx, dy
end
function Castbar.Prefix(unitKey)
    return GetCastbarPrefix(CanonKey(unitKey))
end
function Castbar.Detached(key, g)
    key = CanonKey(key)
    if not g then return false end
    if key == "boss" then return g.bossCastbarDetached == true end
    if key == "arena" then return g.arenaCastbarDetached == true end
    local prefix = Castbar.Prefix(key)
    return prefix and g[prefix .. "Detached"] == true or false
end
local function WidthSourceKey(key)
    key = CanonKey(key)
    local dbKey = GetCastbarWidthSourceKey(key)
    if dbKey then return dbKey end
    if key == "player" then return "castbarPlayerMatchWidth", "castbarPlayerMatchUnitWidth" end
    if key == "target" then return "castbarTargetMatchWidth", "castbarTargetMatchUnitWidth" end
    if key == "focus" then return "castbarFocusMatchWidth", "castbarFocusMatchUnitWidth" end
    if key == "boss" then return "bossCastbarMatchWidth", "castbarBossMatchUnitWidth", "castbarBossMatchWidth" end
    if key == "arena" then return "arenaCastbarMatchWidth", "castbarArenaMatchUnitWidth", "castbarArenaMatchWidth" end
end
local function WidthSource(g, key)
    if not g then return nil end
    local primary, legacy, alias = WidthSourceKey(key)
    local source = NormalizeWidthSource(primary and g[primary])
    if source then return source end
    source = NormalizeWidthSource(alias and g[alias])
    if source then return source end
    if legacy and g[legacy] == true then return "unitframe" end
    return nil
end
-- Blizzard's cooldown viewers appear when their load-on-demand addon loads, so they are read at use time.
local function ExternalWidthSourceFrame(source)
    if source == "essential" then
        return GetEffectiveCooldownFrame("EssentialCooldownViewer") or EssentialCooldownViewer
    elseif source == "utility" then
        return UtilityCooldownViewer
    end
end
--- The live castbar frame a unit's preview projects from (boss and arena: the
--- first frame of their pool). Runtime.lua reads the same lookup for scale and
--- detached offset. The pool tables are the castbar pools' published tables (the
--- MSUF_BossCastbars / MSUF_ArenaCastbars globals); the frames are named globals.
local function RuntimeCastbarFrame(key)
    key = CanonKey(key)
    if key == "boss" then
        local bars = MSUF.Castbars.Pools.BossCastbars
        return (bars and bars[1])
            or MSUF_BossCastbar1
            or MSUF.Castbars.Frames.Get("bossPreview")
    elseif key == "arena" then
        local bars = MSUF.Castbars.Pools.ArenaCastbars
        return (bars and bars[1])
            or MSUF_ArenaCastbar1
            or MSUF.Castbars.Frames.Get("arenaPreview")
            or MSUF_ArenaCastbarPreview1
    end
    local previewKey = PREVIEW_CASTBAR_KEYS[key]
    if previewKey then
        return MSUF.Castbars.Frames.Get(key) or MSUF.Castbars.Frames.Get(previewKey)
    end
end
Castbar.RuntimeFrame = RuntimeCastbarFrame
local function RuntimeUnitFrame(key)
    key = CanonKey(key)
    local unit = RUNTIME_UNITS[key] or key
    return CoreFrame(unit) or (unit and _G["MSUF_" .. unit])
end
local function EffectiveScaleProxy(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    scale = tonumber(scale)
    if not scale or scale <= 0 then return nil end
    return {
        GetEffectiveScale = function()
            return scale
        end
    }
end
local function ReadExternalWidth(source, targetFrame)
    local frame = ExternalWidthSourceFrame(source)
    if not (frame and frame.GetWidth and frame.IsShown and frame:IsShown()) then return nil end
    local scaled = CDMGetScaledWidth(frame, targetFrame)
    if scaled and scaled > 0 then return scaled end
    local w = frame:GetWidth()
    if w and w > 0 then return w end
end
function Castbar.ReadSize(key, g, fallbackW, fallbackH)
    key = CanonKey(key)
    fallbackW = tonumber(fallbackW) or 250
    fallbackH = tonumber(fallbackH) or 18
    local widthSource = WidthSource(g, key)
    local targetFrame = RuntimeCastbarFrame(key) or EffectiveScaleProxy(RuntimeUnitFrame(key))
    local w, h
    if widthSource == "essential" or widthSource == "utility" then
        w = ReadExternalWidth(widthSource, targetFrame) or nil
    end
    local desiredW, desiredH = GetCastbarDesiredSize(RUNTIME_UNITS[key] or key, g or {}, targetFrame, fallbackW, fallbackH)
    if not w or w <= 0 then w = desiredW end
    h = desiredH
    if not w or w <= 0 then
        if key == "boss" then
            w = g and tonumber(g.bossCastbarWidth)
        elseif key == "arena" then
            w = g and tonumber(g.arenaCastbarWidth)
        else
            local prefix = Castbar.Prefix(key)
            w = prefix and g and tonumber(g[prefix .. "BarWidth"]) or nil
        end
    end
    if not h or h <= 0 then
        if key == "boss" then
            h = g and tonumber(g.bossCastbarHeight)
        elseif key == "arena" then
            h = g and tonumber(g.arenaCastbarHeight)
        else
            local prefix = Castbar.Prefix(key)
            h = prefix and g and tonumber(g[prefix .. "BarHeight"]) or nil
        end
    end
    w = tonumber(w) or fallbackW
    h = tonumber(h) or fallbackH
    if w < 40 then w = 40 elseif w > 900 then w = 900 end
    if h < 6 then h = 6 elseif h > 80 then h = 80 end
    return w, h
end
local function TextKey(key, suffix, bossKey)
    key = CanonKey(key)
    if key == "boss" then return bossKey end
    if key == "arena" and bossKey then return (bossKey:gsub("^bossCast", "arenaCast")) end
    local prefix = Castbar.Prefix(key)
    return prefix and (prefix .. suffix) or nil
end
function Castbar.ReadNumber(g, key, suffix, bossKey, fallback)
    g = g or EMPTY_DETAILS
    local dbKey = TextKey(key, suffix, bossKey)
    local globalKey
    if suffix and suffix:find("Icon", 1, true) then globalKey = suffix:gsub("^Icon", "castbarIcon") end
    return MSUF.Castbars.Visuals.DetailNum(g, nil, nil, dbKey, nil)
        or MSUF.Castbars.Visuals.DetailNum(g, nil, nil, globalKey, fallback)
end
function Castbar.Enabled(key, g)
    return ShouldUseMSUFCastbar(key, g) == true
end
function Castbar.ShowIcon(key, g)
    return MSUF.Castbars.Visuals.ShowIconForUnit(g, key, MSUF.Castbars.Visuals.PrefixForUnit(key))
end
function Castbar.ShowText(key, g)
    return MSUF.Castbars.Visuals.ShowSpellForUnit(g, key, MSUF.Castbars.Visuals.PrefixForUnit(key))
end

-- Scene composition owns the sample and interaction handles; the runtime
-- castbar scene remains the only painter.
local max, min = math.max, math.min

--- The castbar slot paints the engine's castbar scene (root:Castbar), so every look setting is read the way the
--- live castbar reads it. This module sizes and places the slot, feeds the sample and fits the handles.
local CAST_SCENE_UNIT = { boss = "boss1", arena = "arena1" }
local CAST_SAMPLE_NAMES = { boss = "Celestial Ruin", arena = "Greater Pyroblast" }
local CAST_KICK_RECOVERY = { 0.4 }
local CAST_PROGRESS = 0.70
local CAST_DURATION = 2.0
-- One-region lists for the handle placer, kept on the region itself.
local function RegionList(region)
    local list = region._msufPreviewRegionList
    if not list then
        list = { region }
        region._msufPreviewRegionList = list
    end
    return list
end
local function CastbarShowTime(key, g)
    return key == "boss" and g.showBossCastTime ~= false
        or (key == "arena" and g.showArenaCastTime ~= false)
        or (key == "target" and g.showTargetCastTime ~= false)
        or (key == "focus" and g.showFocusCastTime ~= false)
        or (key == "player" and g.showPlayerCastTime ~= false)
end
local function CastbarShowTargetName(key, g)
    return (key == "target" and g.castbarTargetShowTargetName == true)
        or (key == "focus" and g.castbarFocusShowTargetName == true)
        or (key == "boss" and g.showBossCastTargetName == true)
        or (key == "arena" and g.showArenaCastTargetName == true)
end
-- The GCD strip: status bar, background, spell and time texts and the spell icon.
-- The GCD owner supplies both the detached surface and the ordinary player
-- castbar surface. Only placement/fitting belongs to this workbench.
local function ApplyGcdSample(mock, canvas, g, key, width, height, S, scale)
    local samples = mock.cast._featureSamples
    if not samples then samples = {} mock.cast._featureSamples = samples end
    if key ~= "player" or g.showGCDBar ~= true then
        if samples.gcd then samples.gcd:Hide() end
        return
    end
    local runtime = MSUF.Castbars.GCD
    local detached = g.gcdBarDetached == true
    local field = detached and "gcdDetached" or "gcdAttached"
    local gcd = samples[field]
    if samples.gcd then samples.gcd:Hide() end
    if not gcd then gcd = runtime.CreateSurface(canvas, detached) samples[field] = gcd end
    samples.gcd = gcd
    if detached then runtime.LayoutSurface(gcd, g, canvas)
    else gcd:SetSize(width / scale, height / scale) end
    gcd:SetScale(scale)
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local w, h = gcd:GetWidth() * scale, gcd:GetHeight() * scale
    local x = detached and (cw * .5 + S(tonumber(g.gcdBarX) or 0) - w * .5) or S(12)
    local y = detached and (ch * .5 + S(tonumber(g.gcdBarY) or -180) - h * .5) or S(8)
    gcd:ClearAllPoints()
    gcd:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", max(S(12), min(cw - w - S(12), x)) / scale,
        max(S(8), min(ch - h - S(8), y)) / scale)
    runtime.PaintSample(gcd, g)
end

-- Everything below that the 20 Hz animation tick reaches (the text handle placers) stays inline: no helper or
-- wrapper call per tick beyond the region list and option getters.
local function CastHandleOptions(box, scale)
    local opts = box._msufCastHandleOptions
    if not opts then
        opts = { fitText = true, useScaledRect = true }
        box._msufCastHandleOptions = opts
    end
    opts.coordinateScale = scale
    return opts
end
--- A text handle around the scene's FontString as it reads now: the refresh and the animation tick (the cast time
--- counts) share it.
local function PlaceCastTextHandle(st, handle, region, shown, minWidth)
    if not (shown and region and region:IsShown()) then
        handle:Hide()
        return
    end
    local max = st.max
    handle:SetSize(max(minWidth, region:GetStringWidth() + 10), max(18, region:GetStringHeight() + 6))
    if not st.UnitPreviewText.PlaceHandleAroundRegions(handle, st.canvas, RegionList(region), 3,
        CastHandleOptions(st.box, st.box._castHandleScale)) then st.PlaceHandle(handle, region) end
end
local function PlaceCastTimeHandle(st)
    local frame = st.box._castScene and st.box._castScene:Frame()
    if frame then PlaceCastTextHandle(st, st.box.handleCastbarTime, frame.timeText, CastbarShowTime(st.key, st.g), 28) end
end
--- Icon, spell, target and time handles follow the scene's own regions; the castbar handle follows the slot.
local function PlaceCastbarHandles(st, frame)
    local box, g, key = st.box, st.g, st.key
    local scale = st.scale * (box._mockCastFrameScale or 1)
    box._castHandleScale = scale
    local icon = frame.icon
    if st.R.CastbarShowIcon(key, g) and icon:IsShown() then
        box.handleCastbarIcon:SetSize(max(18, icon:GetWidth() * scale + 8), max(18, icon:GetHeight() * scale + 8))
        st.PlaceHandle(box.handleCastbarIcon, icon)
    else
        box.handleCastbarIcon:Hide()
    end
    PlaceCastTextHandle(st, box.handleCastbarText, frame.castText, st.R.CastbarShowText(key, g), 34)
    PlaceCastTextHandle(st, box.handleCastbarTarget, frame.castTargetText, CastbarShowTargetName(key, g), 48)
    PlaceCastTimeHandle(st)
end
Castbar.ShowTargetName = CastbarShowTargetName
Castbar.RefreshTimeHandle = PlaceCastTimeHandle

function Castbar.ComposeScene(st)
    local S, box, g, key, max, mock = st.S, st.box, st.g, st.key, st.max, st.mock
    local castW, castBarH, castOffsetX, castOffsetY = st.castW, st.castBarH, st.castOffsetX, st.castOffsetY
    local scene = box._castScene
    if not st.castPreviewVisible then
        if scene then scene:Hide() end
        mock.cast:Hide()
        if mock.cast._featureSamples and mock.cast._featureSamples.gcd then mock.cast._featureSamples.gcd:Hide() end
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        box.handleCastbar:Hide()
        box.handleCastbarIcon:Hide()
        box.handleCastbarText:Hide()
        box.handleCastbarTarget:Hide()
        box.handleCastbarTime:Hide()
        return
    end
    mock.cast:Show()
    -- The live castbar is not a child of the scaled unit frame. Preserve
    -- that independent frame geometry inside Menu2 instead of stretching
    -- the castbar with the unit-frame preview.
    if mock.cast.SetScale then mock.cast:SetScale(box._mockCastFrameScale or 1) end
    local scw, sch = max(20, S(castW)), max(6, S(castBarH))
    mock.cast:SetSize(scw, sch)
    if mock.cast.sizeTag then
        mock.cast.sizeTag:SetText(st.format("%d x %d", st.floor(castW + 0.5), st.floor(castBarH + 0.5)))
        mock.cast.sizeTag:Show()
    end
    mock.cast:ClearAllPoints()
    if st.castDetached then
        box._detachedCastPreview = true
        box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = S(castOffsetX), S(castOffsetY)
        mock.cast:SetPoint("CENTER", mock._body, "CENTER", box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY)
    elseif key == "player" then
        mock.cast:SetPoint("BOTTOM", mock._body, "TOP", S(castOffsetX), S(castOffsetY))
    elseif key == "boss" or key == "arena" then
        mock.cast:SetPoint("TOPLEFT", mock._body, "BOTTOMLEFT",
            S(castOffsetX - box._bossBorderInset),
            S(castOffsetY - box._bossBorderInset - box._bossCastbarGap)
                + (box._runtimePowerEmbedded == true and st.powerH or 0))
    else
        mock.cast:SetPoint("BOTTOMLEFT", mock._body, "TOPLEFT", S(castOffsetX), S(castOffsetY))
    end
    local root = box._castSceneRoot
    if not root then
        root = MSUF.GF.NewPreviewScene(mock.cast)
        box._castSceneRoot = root
        box._castSample = {}
        box._castTick = {}
        box._castOpts = { sample = box._castSample, point = "CENTER", x = 0, y = 0 }
    end
    root:Activate()
    local animState = st.animState
    local sample = box._castSample
    for field in pairs(sample) do sample[field] = nil end
    local channel = key == "player" and g.castbarShowChannelTicks == true
    sample.class = st.data and st.data.class or "MAGE"
    sample.kind = channel and "CHANNEL" or "CAST"
    sample.name = st.TR(channel and "Channel" or CAST_SAMPLE_NAMES[key] or "Arcane Surge")
    sample.icon = 136235
    sample.duration = animState and tonumber(animState.castDuration) or CAST_DURATION
    sample.progress = animState and tonumber(animState.castPct) or CAST_PROGRESS
    if key == "player" then
        sample.latency, sample.latencyMS = 0.12, 50
    else
        sample.targetName = st.TR("Cleave Training Dummy")
    end
    sample.kickReady, sample.kickRecovery = true, CAST_KICK_RECOVERY
    local opts = box._castOpts
    opts.width, opts.height, opts.scale = castW, castBarH, st.scale
    local previous = scene
    scene = root:Castbar(CAST_SCENE_UNIT[key] or key, opts)
    if previous and previous ~= scene then previous:Hide() end
    box._castScene = scene
    local frame = scene:Frame()
    if frame then
        frame:SetFrameLevel(mock.cast:GetFrameLevel() + 1)
        PlaceCastbarHandles(st, frame)
        local bar = frame.statusBar
        ApplyGcdSample(mock, st.canvas, g, key, bar:GetWidth() * st.scale, max(1, bar:GetHeight() * st.scale), S, st.scale)
    end
    box.handleCastbar:SetSize(
        max(36, scw * (box._mockCastFrameScale or 1)),
        max(18, (sch + 8) * (box._mockCastFrameScale or 1)))
    st.PlaceHandle(box.handleCastbar, mock.cast)
end
