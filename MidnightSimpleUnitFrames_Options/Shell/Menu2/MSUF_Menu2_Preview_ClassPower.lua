local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_ClassPower.lua"
local CP, floor = M.ClassPowerPreview, math.floor

CP.NormalizeClassShape = MSUF.UF.Shared.NormalizeClassPowerShape
CP.ResolvePowerShape = MSUF.ClassPowerShapes.ResolvePower

local function SampleFrameWidth(self) return self.width end
function CP.ResolveDetachedPowerWidth(opts)
    local power = MSUF.UF.Elements.Power
    if opts.liveFrame and opts.livePower then return power.ResolveDetachedWidth(opts.liveFrame, opts.livePower) end
    local constants = MSUF.Require("MSUF_CP_CONST", FILE)
    local matched = opts.syncClass and opts.classWidth or nil
    local frame = { width = opts.frameWidth or 275, GetWidth = SampleFrameWidth, targetPowerBar = opts.relativeTo }
    return power.ResolveDetachedWidth(frame, {
        detachedWidthFrameName = opts.widthFrameName or constants.CDM_FRAMES[opts.widthMode],
        detachedSyncClass = false,
        detachedWidthExplicit = matched or opts.explicitWidth or opts.manualWidth,
        detachedWidth = opts.syncClass and opts.classFallbackWidth or opts.manualWidth,
    })
end

-- The sample animation below produces public fixture values only. Native
-- runtime mode painters own all colour, geometry, fill and text decisions.

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


local RUNE_PREVIEW_REMAINING = { nil, 7.2, nil, 4.1, nil, 1.4 }
local RUNE_PREVIEW_OFFSET = { nil, 0.0, nil, 3.1, nil, 6.2 }
local RUNE_PREVIEW_READY_HOLD = 1.2
--- Scene samples of the previewed class resource (root:ClassPower). SceneStatic writes what a full paint needs
--- once; SceneValues writes the count, partial and rune states a wave tick changes, without allocating after
--- its first call. Runtime gates retain the saved settings in every sample.
local SAMPLE_PRIMARY_POWER = { WARRIOR = 1, ROGUE = 3, DEATHKNIGHT = 6, MONK = 3, DEMONHUNTER = 17 }
local HUNTER_USES_FOCUS = MSUF.Client.IsRetail and not MSUF.Client.IsForever
function CP.PrimaryPower(spec, class)
    if spec and spec.primaryPower ~= nil then return spec.primaryPower end
    if class == "HUNTER" then return HUNTER_USES_FOCUS and 2 or 0 end
    if class == "PRIEST" and spec and spec.token == "INSANITY" then return 13 end
    if class == "SHAMAN" and spec and spec.mode == "continuous" then return 11 end
    return SAMPLE_PRIMARY_POWER[class] or 0
end
function CP.SceneStatic(sample, spec, class)
    sample.class, sample.spec, sample.primaryPower, sample.time = class, spec.specIndex or 1, CP.PrimaryPower(spec, class), 100
    sample.charged = spec.chargedSlots
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
CP.ResolveTexture = MSUF.ClassPowerConfig.ResolveTexture
