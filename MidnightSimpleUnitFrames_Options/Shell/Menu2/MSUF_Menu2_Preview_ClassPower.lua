local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_ClassPower.lua"
local Optional, CP, floor = MSUF.Optional, M.ClassPowerPreview, math.floor
local addonName = MSUF.AddonName

CP.WHITE8 = CP.WHITE8 or "Interface\\Buttons\\WHITE8X8"
CP.MEDIA = CP.MEDIA or ("Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\ClassPower\\")
function CP.ShapeTextures(prefix, axis)
    local tex = { fill = CP.MEDIA .. prefix .. "_fill.tga", bg = CP.MEDIA .. prefix .. "_bg.tga", edge = CP.MEDIA .. prefix .. "_edge.tga" }
    tex.axis = axis
    return tex
end
CP.CLASS_SHAPES = CP.CLASS_SHAPES or {
    CIRCLE = CP.ShapeTextures("pip_circle"),
    DIAMOND = CP.ShapeTextures("pip_diamond"),
    HEX = CP.ShapeTextures("pip_hex"),
}
CP.POWER_SHAPES = CP.POWER_SHAPES or {
    ROUND = CP.ShapeTextures("power_round"),
    CRYSTAL = CP.ShapeTextures("power_crystal"),
    ORB = CP.ShapeTextures("pip_circle", "VERTICAL"),
}
function CP.NormalizeClassShape(value)
    value = tostring(value or "BAR"):upper()
    return (value == "CIRCLE" or value == "DIAMOND" or value == "HEX") and value or "BAR"
end
function CP.ResolvePowerShape(value, classShape)
    value = tostring(value or "BAR"):upper()
    if value == "ROUND" or value == "CRYSTAL" or value == "ORB" or value == "BAR" then return value end
    if value == "FOLLOW_CLASS" then
        classShape = CP.NormalizeClassShape(classShape)
        if classShape == "CIRCLE" then return "ROUND" end
        if classShape == "DIAMOND" or classShape == "HEX" then return "CRYSTAL" end
    end
    return "BAR"
end
local DETACHED_POWER_WIDTH_FRAMES = {
    cooldown = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    tracked_buffs = "BuffIconCooldownViewer",
}
-- The class power constants table, a core load-time export the options load after.
local CPConst = Optional("MSUF_CP_CONST")
local function PreviewFrameWidth(frame)
    if not (frame and frame.GetWidth) then return nil end
    if frame._msufLegacyCooldownAnchor == true then return nil end
    if frame.IsShown and not frame:IsShown() then return nil end
    local width = frame:GetWidth()
    if type(width) == "number" and width > 1 then return width end
    return nil
end
local function PreviewExternalFrameWidth(frameName, relativeTo)
    local common = MSUF.UFBarTextCommon
    return common.ExternalFrameWidth(frameName, relativeTo)
end
local function ClampDetachedPowerWidth(value, fallback, minValue, maxValue)
    value = tonumber(value) or tonumber(fallback) or 1
    minValue, maxValue = minValue or 20, maxValue or 800
    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
    return floor(value + 0.5)
end
function CP.ResolveDetachedPowerWidth(opts)
    opts = opts or {}
    if tostring(opts.shape or "BAR"):upper() == "ORB" then
        return ClampDetachedPowerWidth(opts.orbSize, 54, 20, 160)
    end
    local liveFrame, livePower = opts.liveFrame, opts.livePower
    local powerElement = MSUF.UF.Elements.Power
    local liveResolver = powerElement.ResolveDetachedWidth
    if liveFrame and livePower then
        -- Unit Preview must not maintain a second width policy. When the live
        -- unit exists, consume the same resolver and its per-bar combat cache.
        return liveResolver(liveFrame, livePower)
    end
    -- Mirrors the live resolver's precedence: the Detached width mode, then a
    -- matched Class Resource bar, then a Detached width configured on this
    -- frame, then the shared Class Resource width mode as the sync fallback.
    local frameName = opts.widthFrameName
    if type(frameName) ~= "string" or frameName == "" then
        local cdmFrames = CPConst and CPConst.CDM_FRAMES or DETACHED_POWER_WIDTH_FRAMES
        frameName = cdmFrames and cdmFrames[opts.widthMode]
    end
    if type(frameName) == "string" and frameName ~= "" then
        local sourceWidth = PreviewExternalFrameWidth(frameName, opts.relativeTo)
        if sourceWidth then return ClampDetachedPowerWidth(sourceWidth) end
    end
    if opts.syncClass == true then
        local classWidth = tonumber(opts.classWidth)
        if classWidth and classWidth > 1 then return ClampDetachedPowerWidth(classWidth) end
    end
    local explicitWidth = tonumber(opts.explicitWidth)
    if explicitWidth then return ClampDetachedPowerWidth(explicitWidth) end
    if opts.syncClass == true then
        local classWidth = tonumber(opts.classFallbackWidth)
        if classWidth and classWidth > 1 then return ClampDetachedPowerWidth(classWidth) end
    end
    return ClampDetachedPowerWidth(opts.manualWidth, opts.frameWidth)
end
CP.FALLBACK_COLORS = CP.FALLBACK_COLORS or {
    ARCANE_CHARGES = { 0.45, 0.55, 1.00 },
    CHARGED = { 0.60, 0.20, 0.80 },
    CHI = { 0.70, 1.00, 0.86 },
    COMBO_POINTS = { 1.00, 0.82, 0.10 },
    EBON_MIGHT = { 0.40, 0.80, 0.60 },
    ESSENCE = { 0.32, 0.74, 1.00 },
    HOLY_POWER = { 0.95, 0.86, 0.20 },
    IRONFUR = { 1.00, 0.49, 0.04 },
    INSANITY = { 0.55, 0.32, 0.95 },
    MAELSTROM = { 0.00, 0.55, 1.00 },
    MAELSTROM_ABOVE_5 = { 1.00, 0.50, 0.00 },
    RUNES = { 0.55, 0.85, 1.00 },
    SOUL_FRAGMENTS = { 0.00, 0.80, 0.00 },
    SOUL_FRAGMENTS_META = { 0.60, 0.20, 0.93 },
    SOUL_FRAGMENTS_VENG = { 0.34, 0.06, 0.46 },
    SOUL_SHARDS = { 0.58, 0.28, 0.92 },
    STAGGER_GREEN = { 0.52, 1.00, 0.52 },
    STAGGER_YELLOW = { 1.00, 0.98, 0.72 },
    STAGGER_RED = { 1.00, 0.42, 0.42 },
    TIP_OF_THE_SPEAR = { 0.60, 0.80, 0.20 },
    WHIRLWIND = { 0.20, 0.80, 0.20 },
}
function CP.ColorOverride(tableName, token)
    local db = MSUF_DB
    local general = db and db.general
    local overrides = general and general[tableName]
    return MSUF.ClassPowerColors.OverrideRGB(overrides, token)
end
-- The runtime power-color helpers, resolved once: the class power preview asks for every
-- segment color on each animation tick.
local GetPowerBarColor = MSUF.Require("MSUF_GetPowerBarColor", FILE)
local GetDefaultPowerColor = MSUF.Require("MSUF_GetDefaultPowerColor", FILE)
function CP.ResolveColor(token, fallbackR, fallbackG, fallbackB, powerColorFn)
    -- User overrides should show in preview, then fall back to runtime power-color helpers,
    -- and finally to fixed preview colors when the real runtime is unavailable.
    local r, g, b = CP.ColorOverride("classPowerColorOverrides", token)
    if r then return r, g, b end
    if token then
        r, g, b = GetPowerBarColor(0, token)
        if type(r) == "number" then return r, g, b end
    end
    if token then
        r, g, b = GetDefaultPowerColor(token)
        if type(r) == "number" then return r, g, b end
    end
    local pbc = PowerBarColor
    local c = pbc and token and pbc[token]
    if c then
        r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
        if type(r) == "number" then return r, g, b end
    end
    c = token and CP.FALLBACK_COLORS[token]
    if c then return c[1], c[2], c[3] end
    if type(powerColorFn) == "function" and token then
        r, g, b = powerColorFn(token)
        if type(r) == "number" then return r, g, b end
    end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end
function CP.ResolveBaseColor(spec, bars, fallbackR, fallbackG, fallbackB, powerColorFn)
    if bars and bars.classPowerColorByType == false then return 1, 1, 1 end
    return CP.ResolveColor(spec and spec.token, fallbackR, fallbackG, fallbackB, powerColorFn)
end
function CP.ResolveTextColor(fallbackR, fallbackG, fallbackB, powerColorFn)
    return CP.ResolveColor("RESOURCE_TEXT", fallbackR or 1, fallbackG or 1, fallbackB or 1, powerColorFn)
end
--- Segments a class resource preview draws: the spec's count, at most ten,
--- or eighteen for Sweeping Strikes, whose live bar shows 18 stacks
--- (MSUF_CP_NativeAuras.lua).
--- The dark bar colour the engine draws: the settings cache's resolved
--- colour, else the saved dark colour, else the dark gray, else 0.07 (the
--- rule of UF_Config ResolveDarkColor and CP_PlayerHP DarkColor).
local darkBarColor = {}
function H.DarkBarColor(cache)
    if cache and type(cache.darkBarR) == "number" and type(cache.darkBarG) == "number"
        and type(cache.darkBarB) == "number" then
        return cache.darkBarR, cache.darkBarG, cache.darkBarB
    end
    local db = MSUF_DB
    MSUF.UF.Config.ResolveDarkColor(db and db.general, darkBarColor)
    return darkBarColor.r, darkBarColor.g, darkBarColor.b
end
function CP.SegmentCount(spec)
    local count = floor(tonumber(spec and spec.segments) or 5)
    local limit = spec and spec.token == "SWEEPING_STRIKES" and 18 or 10
    if count < 1 then count = 1 elseif count > limit then count = limit end
    return count
end
function CP.IsSingleBarMode(mode)
    return mode == "continuous" or mode == "timer_bar" or mode == "stagger" or mode == "aura_single" or mode == "ironfur"
end
function CP.IsEssence(spec)
    return spec and spec.token == "ESSENCE"
end
function CP.AnimatedValue(spec, elapsed)
    if not spec then return nil end
    local mode = spec.mode or "segmented"
    local maxValue = tonumber(spec.segments) or 1
    if CP.IsSingleBarMode(mode) then maxValue = 1 elseif maxValue < 1 then maxValue = 1 end
    elapsed = tonumber(elapsed) or 0
    if mode == "timer_bar" then return 1 - ((elapsed % 4.8) / 4.8) end
    local phase = (elapsed % 2.4) / 2.4
    local wave = phase < 0.5 and (phase * 2) or ((1 - phase) * 2)
    if mode == "continuous" or mode == "stagger" or mode == "aura_single" then return 0.08 + (wave * 0.88) end
    if CP.IsEssence(spec) then
        local cycle = (elapsed / 1.15) % (maxValue + 1)
        if cycle >= maxValue then return maxValue end
        local full = floor(cycle)
        return full + (cycle - full)
    end
    if mode == "fractional" then return wave * maxValue end
    local steps = maxValue * 2
    local step = floor((elapsed / 0.42) % steps)
    if step <= maxValue then return step end
    return steps - step
end
function CP.TextForValue(spec, value)
    if not spec then return "" end
    if value == nil then return spec.previewText or "" end
    local mode = spec.mode or "segmented"
    if mode == "continuous" then return tostring(floor((value * 100) + 0.5)) .. " / 100" end
    if mode == "timer_bar" then return string.format("%.1f", floor((value * 20 * 10) + 0.5) / 10) end
    if mode == "stagger" then return tostring(floor((value * 34) + 0.5)) .. "K" end
    if mode == "aura_single" then return tostring(floor((value * (tonumber(spec.fragments) or 5)) + 0.5)) end
    if mode == "fractional" then return string.format("%.1f", value) end
    local rounded = CP.IsEssence(spec) and floor(value) or floor(value + 0.5)
    if spec.token == "SOUL_FRAGMENTS_VENG" then return tostring(rounded) .. " / " .. tostring(tonumber(spec.segments) or 6) end
    return tostring(rounded)
end
local RUNE_PREVIEW_REMAINING = { nil, 7.2, nil, 4.1, nil, 1.4 }
local RUNE_PREVIEW_OFFSET = { nil, 0.0, nil, 3.1, nil, 6.2 }
local RUNE_PREVIEW_READY_HOLD = 1.2
--- Scene samples of the previewed class resource (root:ClassPower). SceneStatic writes what a full paint needs
--- once; SceneValues writes the count, partial and rune states a wave tick changes, without allocating after
--- its first call. The resource gates the picker ignores are forced on in the sample's bar overlay.
local SCENE_GATES = { "showShadowMana", "showEleMaelstrom", "showGuardianIronfur", "showSweepingStrikes", "showStagger" }
function CP.SceneStatic(sample, spec, class)
    sample.class, sample.spec, sample.primaryPower, sample.time = class, spec.specIndex or 1, spec.primaryPower, 100
    sample.charged = spec.chargedSlots
    local bars = sample.bars
    if not bars then
        bars = {}
        sample.bars = bars
    end
    for i = 1, #SCENE_GATES do bars[SCENE_GATES[i]] = true end
    return sample
end
local function SceneRunes(out, spec, elapsed, animated)
    local runes = out.runes
    if not runes then
        runes = {}
        out.runes = runes
    end
    local total = tonumber(spec.runeDuration) or 10
    if total < 1 then total = 10 end
    local ready = 0
    for i = 1, 6 do
        local rune = runes[i]
        if not rune then
            rune = {}
            runes[i] = rune
        end
        rune.duration = total
        local remaining, cooled = RUNE_PREVIEW_REMAINING[i], nil
        if remaining then
            cooled = animated and (((tonumber(elapsed) or 0) + (RUNE_PREVIEW_OFFSET[i] or 0)) % (total + RUNE_PREVIEW_READY_HOLD))
                or (total - remaining)
            if cooled >= total then cooled = nil end
        end
        rune.ready, rune.start = cooled == nil, cooled and (100 - cooled) or 0
        if cooled == nil then ready = ready + 1 end
    end
    return ready
end
function CP.SceneValues(out, spec, value, elapsed, animated)
    local mode = spec.mode or "segmented"
    if value == nil then value = tonumber(spec.value) or 0 end
    out.partial = nil
    if mode == "rune" then
        out.maximum = 6
        out.count = SceneRunes(out, spec, elapsed, animated)
    elseif mode == "aura_single" then
        out.maximum = floor(tonumber(spec.fragments) or 5)
        out.count = floor(value * out.maximum + 0.5)
    elseif mode == "ironfur" then
        out.maximum, out.count = 5, 3
    elseif CP.IsSingleBarMode(mode) then
        out.maximum, out.count = 100, floor(value * 100 + 0.5)
    else
        out.maximum = floor(tonumber(spec.segments) or 5)
        if mode == "fractional" then
            out.count = value
        elseif CP.IsEssence(spec) then
            out.count = floor(value)
            out.partial = value - out.count
        else
            out.count = floor(value)
        end
    end
    return out
end
local ResolveStatusbarTextureKey = Optional("MSUF_ResolveStatusbarTextureKey")
local GetBarTexture = MSUF.Require("MSUF_GetBarTexture", FILE)
function CP.ResolveTexture(key, fallback)
    if key and key ~= "" then
        local path = type(ResolveStatusbarTextureKey) == "function" and ResolveStatusbarTextureKey(key) or nil
        if path and path ~= "" then return path end
    end
    if fallback and fallback ~= "" then return fallback end
    local path = GetBarTexture()
    if path and path ~= "" then return path end
    return CP.WHITE8
end
