local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF
local CreateFrame = V.CreateFrame or CreateFrame
local InCombatLockdown = V.InCombatLockdown or InCombatLockdown
local tonumber = V.tonumber or tonumber
local type = V.type or type
local pairs = V.pairs or pairs
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local Clamp01 = V.Clamp01
local SetFrameAlpha = V.SetFrameAlpha
local SetAlphaCached = V.SetAlphaCached

local Alpha = {}

local TEXT_ALPHA_FIELDS = {
    "nameText",
    "levelText",
    "hpTextLeft",
    "hpTextCenter",
    "hpTextRight",
    "powerTextLeft",
    "powerTextCenter",
    "powerTextRight",
    "totInlineSep",
    "totInlineText",
    "raidGroupNameText",
    "statusIndicatorText",
}

local STATUS_ALPHA_FIELDS = {
    "raidTargetIcon",
    "LeaderIndicator",
    "levelText",
    "raidGroupNameText",
    "eliteIcon",
    "statusIndicatorText",
    "combatStateIndicatorIcon",
    "restingIndicatorIcon",
    "incomingResIndicatorIcon",
}

local function ClearAlphaField(obj, field)
    if obj then
        obj[field] = nil
    end
end

local function StatusBarTexture(bar)
    if not (bar and bar.GetStatusBarTexture) then
        return nil
    end
    local texture = bar._msufAlphaStatusTextureObject
    if not texture then
        texture = bar:GetStatusBarTexture()
        bar._msufAlphaStatusTextureObject = texture
    end
    return texture
end

local function SetStatusBarLayerAlpha(bar, alpha, field, force)
    if not bar then
        return
    end
    SetAlphaCached(bar, 1, (field or "_msufAlphaStatusBar") .. "Object", force)
    SetAlphaCached(StatusBarTexture(bar), alpha, field or "_msufAlphaStatusTexture", force)
end

local function SetTextureLayerAlpha(texture, alpha, field, force)
    SetAlphaCached(texture, alpha, field or "_msufAlphaLayer", force)
end

local function SetTextLayerAlpha(frame, alpha, force)
    for i = 1, #TEXT_ALPHA_FIELDS do
        SetAlphaCached(frame and frame[TEXT_ALPHA_FIELDS[i]], alpha, "_msufAlphaText", force)
    end
end

local function SetStatusLayerAlpha(frame, alpha, force)
    for i = 1, #STATUS_ALPHA_FIELDS do
        local region = frame and frame[STATUS_ALPHA_FIELDS[i]]
        if region then
            local base = tonumber(region._msufStatusAlpha) or 1
            SetAlphaCached(region, base * alpha, "_msufAlphaStatus", force)
        end
    end
end

local function SetPortraitLayerAlpha(frame, alpha, force)
    SetAlphaCached(frame and frame.MSUFPortraitHolder, alpha, "_msufAlphaPortraitHolder", force)
    SetAlphaCached(frame and frame.portrait, 1, "_msufAlphaPortraitTexture", force)
end

local function ResetLegacyLayerAlphas(frame, force)
    if not frame then
        return
    end
    SetStatusBarLayerAlpha(frame.hpBar or frame.Health, 1, "_msufAlphaHealth", force)
    SetStatusBarLayerAlpha(frame.incomingHealBar, 1, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.absorbBar, 1, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.healAbsorbBar, 1, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.targetPowerBar or frame.Power or frame.powerBar, 1, "_msufAlphaPower", force)
    SetTextureLayerAlpha(frame.bg or frame.hpBarBG, 1, "_msufAlphaBackground", force)
    if frame.bg ~= frame.hpBarBG then
        SetTextureLayerAlpha(frame.hpBarBG, 1, "_msufAlphaBackground", force)
    end
    SetTextureLayerAlpha(frame.powerBarBG, 1, "_msufAlphaBackground", force)
    SetTextLayerAlpha(frame, 1, force)
    SetStatusLayerAlpha(frame, 1, force)
    SetPortraitLayerAlpha(frame, 1, force)
    frame._msufAlphaLayeredMode = nil
end


local function NormalizeAlphaLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" or mode == "backdrop" or mode == "bg" then
        return "background"
    elseif mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

local function InCombatForEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        return true
    elseif event == "PLAYER_REGEN_ENABLED" then
        return false
    elseif _G.MSUF_InCombat ~= nil then
        return _G.MSUF_InCombat == true
    end
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function AlphaPair(cfg, mode)
    if not cfg then
        return 1, 1
    end
    local inAlpha = cfg.inCombat or 1
    local outAlpha = cfg.outCombat or 1
    if cfg.layered ~= true then
        return inAlpha, outAlpha
    end
    if mode == "background" then
        return cfg.backgroundInCombat or inAlpha, cfg.backgroundOutOfCombat or outAlpha
    elseif mode == "health" then
        return cfg.healthInCombat or cfg.foregroundInCombat or inAlpha,
            cfg.healthOutOfCombat or cfg.foregroundOutOfCombat or outAlpha
    end
    return cfg.foregroundInCombat or inAlpha, cfg.foregroundOutOfCombat or outAlpha
end

local function CompileAlphaRuntime(frame, cfg, force)
    if not frame then
        return nil
    end
    if not cfg then
        frame._msufAlphaRuntimeCfg = nil
        frame._msufAlphaRuntime = nil
        return nil
    end
    if force ~= true and frame._msufAlphaRuntimeCfg == cfg and frame._msufAlphaRuntime then
        return frame._msufAlphaRuntime
    end

    local rt = frame._msufAlphaRuntime
    if not rt then
        rt = {}
        frame._msufAlphaRuntime = rt
    end
    frame._msufAlphaRuntimeCfg = cfg

    local baseIn = Clamp01(cfg.inCombat, 1)
    local baseOut = Clamp01(cfg.outCombat, 1)
    local layered = cfg.layered == true
    local layerMode = NormalizeAlphaLayerMode(cfg.layerMode)

    rt.layered = layered
    rt.frameIn = layered and 1 or baseIn
    rt.frameOut = layered and 1 or baseOut
    rt.fgIn = Clamp01(cfg.foregroundInCombat, baseIn)
    rt.fgOut = Clamp01(cfg.foregroundOutOfCombat, baseOut)
    rt.bgIn = Clamp01(cfg.backgroundInCombat, baseIn)
    rt.bgOut = Clamp01(cfg.backgroundOutOfCombat, baseOut)
    rt.hpIn = layerMode == "health" and Clamp01(cfg.healthInCombat or cfg.foregroundInCombat, baseIn) or rt.fgIn
    rt.hpOut = layerMode == "health" and Clamp01(cfg.healthOutOfCombat or cfg.foregroundOutOfCombat, baseOut) or rt.fgOut
    rt.powerIn = layerMode == "health" and 1 or rt.fgIn
    rt.powerOut = layerMode == "health" and 1 or rt.fgOut
    rt.preserveHPColor = cfg.preserveHPColor == true
    rt.baseReady = nil
    rt.baseState = nil
    return rt
end

local function CurrentAlpha(cfg, mode, event)
    local inAlpha, outAlpha = AlphaPair(cfg, mode)
    return InCombatForEvent(event) and inAlpha or outAlpha
end

local function AlphaNeedsCombatRefresh(cfg)
    return cfg and cfg.combatEvents == true
end

local function EnsureAlphaFrameSet(field)
    local frames = Alpha[field]
    if type(frames) ~= "table" then
        frames = setmetatable({}, { __mode = "k" })
        Alpha[field] = frames
    end
    return frames
end

local function TrackAlphaFrame(frame, cfg)
    if not frame then
        return
    end
    EnsureAlphaFrameSet("combatFrames")[frame] = AlphaNeedsCombatRefresh(cfg) and true or nil
end

local function AlphaCombatStateForEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        return true
    elseif event == "PLAYER_REGEN_ENABLED" then
        return false
    elseif _G.MSUF_InCombat ~= nil then
        return _G.MSUF_InCombat == true
    end
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function RefreshAlphaBase(frame, rt, event, force)
    if not rt then
        return
    end
    local needsRefresh = force == true
        or rt.baseReady ~= true
        or event == "MSUF_ALPHA_COMBAT"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED"
    if not needsRefresh then
        return
    end

    local inCombat = AlphaCombatStateForEvent(event)
    local state = inCombat and 1 or 0
    if force ~= true and rt.baseReady == true and rt.baseState == state then
        return
    end

    rt.baseReady = true
    rt.baseState = state
    rt.baseFrame = inCombat and rt.frameIn or rt.frameOut
    if rt.layered then
        rt.baseFG = inCombat and rt.fgIn or rt.fgOut
        rt.baseBG = inCombat and rt.bgIn or rt.bgOut
        rt.baseHP = inCombat and rt.hpIn or rt.hpOut
        rt.basePower = inCombat and rt.powerIn or rt.powerOut
        rt.baseHealthBG = rt.preserveHPColor == true and rt.baseHP or rt.baseBG
        rt.basePortrait = 1
        rt.baseStatus = rt.baseFG
    else
        rt.baseFG = 1
        rt.baseBG = 1
        rt.baseHP = 1
        rt.basePower = 1
        rt.baseHealthBG = 1
        rt.basePortrait = 1
        rt.baseStatus = 1
    end
end

local function UntrackAlphaFrame(frame)
    if not frame then
        return
    end
    if Alpha.combatFrames then
        Alpha.combatFrames[frame] = nil
    end
end

local function ApplyLayeredAlpha(frame, frameAlpha, fgAlpha, bgAlpha, hpAlpha, powerAlpha, healthBgAlpha, portraitAlpha, statusAlpha, force)
    SetFrameAlpha(frame, frameAlpha)
    SetStatusBarLayerAlpha(frame.hpBar or frame.Health, hpAlpha, "_msufAlphaHealth", force)
    SetStatusBarLayerAlpha(frame.incomingHealBar, hpAlpha, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.absorbBar, hpAlpha, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.healAbsorbBar, hpAlpha, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.targetPowerBar or frame.Power or frame.powerBar, powerAlpha, "_msufAlphaPower", force)
    SetTextureLayerAlpha(frame.bg or frame.hpBarBG, healthBgAlpha, "_msufAlphaBackground", force)
    if frame.bg ~= frame.hpBarBG then
        SetTextureLayerAlpha(frame.hpBarBG, healthBgAlpha, "_msufAlphaBackground", force)
    end
    SetTextureLayerAlpha(frame.powerBarBG, bgAlpha, "_msufAlphaBackground", force)
    SetTextLayerAlpha(frame, 1, force)
    SetStatusLayerAlpha(frame, statusAlpha or fgAlpha, force)
    SetPortraitLayerAlpha(frame, portraitAlpha, force)
    frame._msufAlphaLayeredMode = true
end

local function ApplyCompiledAlpha(frame, cfg, event, eventUnit, eventRange)
    if not frame then
        return
    end
    if not cfg then
        SetFrameAlpha(frame, 1)
        ResetLegacyLayerAlphas(frame, true)
        return
    end
    local force = event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" or event == "MSUF_VISUALS"
        or event == "MSUF_ALPHA"
    local rt = CompileAlphaRuntime(frame, cfg, force)
    if not rt then
        return
    end

    RefreshAlphaBase(frame, rt, event, force)

    local frameAlpha = rt.baseFrame or 1
    local fgAlpha = rt.baseFG or 1
    local bgAlpha = rt.baseBG or 1
    local hpAlpha = rt.baseHP or 1
    local powerAlpha = rt.basePower or 1
    local healthBgAlpha = rt.baseHealthBG or 1
    local portraitAlpha = rt.basePortrait or 1
    local statusAlpha = rt.baseStatus or 1

    if _G.MSUF_UnitEditModeActive == true and frameAlpha < 0.35 then
        frameAlpha = 0.35
    end

    local useLayeredApply = rt.layered
    if not force
        and frame._msufAlphaLastLayered == useLayeredApply
        and frame._msufAlphaLastFrame == frameAlpha
        and frame._msufAlphaLastFG == fgAlpha
        and frame._msufAlphaLastBG == bgAlpha
        and frame._msufAlphaLastHP == hpAlpha
        and frame._msufAlphaLastPower == powerAlpha
        and frame._msufAlphaLastHealthBG == healthBgAlpha
        and frame._msufAlphaLastPortrait == portraitAlpha
        and frame._msufAlphaLastStatus == statusAlpha then
        return
    end

    if useLayeredApply then
        ApplyLayeredAlpha(frame, frameAlpha, fgAlpha, bgAlpha, hpAlpha, powerAlpha, healthBgAlpha, portraitAlpha, statusAlpha, force)
    else
        SetFrameAlpha(frame, frameAlpha)
        if frame._msufAlphaLayeredMode == true or event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" then
            ResetLegacyLayerAlphas(frame, force)
        end
    end

    frame._msufAlphaEffective = frameAlpha
    frame._msufAlphaLastLayered = useLayeredApply
    frame._msufAlphaLastFrame = frameAlpha
    frame._msufAlphaLastFG = fgAlpha
    frame._msufAlphaLastBG = bgAlpha
    frame._msufAlphaLastHP = hpAlpha
    frame._msufAlphaLastPower = powerAlpha
    frame._msufAlphaLastHealthBG = healthBgAlpha
    frame._msufAlphaLastPortrait = portraitAlpha
    frame._msufAlphaLastStatus = statusAlpha
end

function Alpha.IsEnabled(frame, spec)
    return spec and spec.alpha and spec.alpha.active == true
end

function Alpha.GetEvents(frame, spec)
    return EMPTY_EVENTS
end

function Alpha.GetUnitlessEvents(frame, spec)
    return EMPTY_EVENTS
end

function Alpha.Apply(frame, spec)
    TrackAlphaFrame(frame, spec and spec.alpha)
    ApplyCompiledAlpha(frame, spec and spec.alpha, "MSUF_APPLY")
end

function Alpha.Update(frame, event, unit, ...)
    ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, event, unit, ...)
end

function Alpha.Disable(frame)
    if not frame then
        return
    end
    UntrackAlphaFrame(frame)
    frame._msufAlphaRuntimeCfg = nil
    frame._msufAlphaRuntime = nil
    ClearAlphaField(frame, "_msufLastAlpha")
    SetFrameAlpha(frame, 1)
    ResetLegacyLayerAlphas(frame)
end

do
    local pending
    local pendingMode

    local function MergeAlphaRefreshMode(current, requested)
        if current == "all" or requested == current then
            return current
        end
        if requested == nil or requested == false then
            return "all"
        end
        if requested == true or requested == "combat" then
            return current and (current == "combat" and "combat" or "all") or "combat"
        end
        return "all"
    end

    local function FlushAlphaRefresh()
        local mode = pendingMode
        pending = nil
        pendingMode = nil
        if mode == "combat" and _G.MSUF_RefreshCombatUnitAlphas then
            return _G.MSUF_RefreshCombatUnitAlphas()
        elseif _G.MSUF_RefreshAllUnitAlphas then
            return _G.MSUF_RefreshAllUnitAlphas()
        end
    end

    function Alpha.RequestRefresh(mode)
        if pending then
            pendingMode = MergeAlphaRefreshMode(pendingMode, mode)
            return true
        end
        pending = true
        pendingMode = MergeAlphaRefreshMode(nil, mode)
        if _G.MSUF_ScheduleOnce then
            _G.MSUF_ScheduleOnce("UF_ALPHA_FLUSH", FlushAlphaRefresh)
        elseif _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, FlushAlphaRefresh)
        else
            FlushAlphaRefresh()
        end
        return true
    end
end

_G.MSUF_RequestAlphaRefresh = function(combatOnly)
    return Alpha.RequestRefresh(combatOnly)
end

_G.MSUF_GetDesiredUnitAlpha = function(key)
    local unit = key == "boss" and "boss1" or key
    if unit == "tot" or unit == "targetoftarget" then
        unit = "targettarget"
    end
    local spec = unit and UF.Config and UF.Config.GetSpec and UF.Config.GetSpec(unit)
    local cfg = spec and spec.alpha
    if not cfg then
        return 1
    end
    return CurrentAlpha(cfg, cfg.layered == true and cfg.layerMode or "foreground", "MSUF_ALPHA")
end

local function ResolveFrameSpec(frame, key)
    if frame and frame.MSUFSpec then
        return frame.MSUFSpec
    end
    local unit = frame and frame.unit or key
    if key and key ~= "boss" and UF.IsManagedUnit and UF.IsManagedUnit(key) then
        unit = key
    end
    if unit and UF.Config then
        local getSpec = UF.Config.GetSpec
        return getSpec and getSpec(unit) or frame and frame.MSUFSpec
    end
    return frame and frame.MSUFSpec
end

_G.MSUF_ApplyUnitAlpha = function(frame, key)
    if not frame then
        return false
    end
    local spec = ResolveFrameSpec(frame, key)
    frame.MSUFSpec = spec or frame.MSUFSpec
    frame.cachedConfig = frame.MSUFSpec
    TrackAlphaFrame(frame, frame.MSUFSpec and frame.MSUFSpec.alpha)
    ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, "MSUF_ALPHA")
    return true
end

UF.ApplyAlphaFrame = function(frame, event)
    if not frame then
        return false
    end
    ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, event or "MSUF_ALPHA")
    return true
end

if CreateFrame and not Alpha.stateDriver then
    local driver = CreateFrame("Frame")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.MSUF_InCombat = true
            Alpha.RequestRefresh(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            _G.MSUF_InCombat = false
            Alpha.RequestRefresh(true)
        else
            _G.MSUF_InCombat = InCombatLockdown and InCombatLockdown() and true or false
            Alpha.RequestRefresh(false)
        end
    end)
    Alpha.stateDriver = driver
end

UF.RegisterElement("Alpha", Alpha)

local function RefreshAlphaFrameSet(frames, token, event, requireCombat)
    if type(frames) ~= "table" then
        return false
    end
    local refreshed = false
    for frame in pairs(frames) do
        local active = frame and frame._msufActiveElements
        local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.alpha
        local valid = frame and active and active.Alpha == true and cfg
        if valid and requireCombat == true and cfg.combatEvents ~= true then
            valid = false
        end
        if valid then
            if frame._msufAlphaRefreshToken ~= token then
                frame._msufAlphaRefreshToken = token
                ApplyCompiledAlpha(frame, cfg, event)
                refreshed = true
            end
        else
            frames[frame] = nil
        end
    end
    return refreshed
end

_G.MSUF_RefreshCombatUnitAlphas = function()
    Alpha.refreshToken = (Alpha.refreshToken or 0) + 1
    return RefreshAlphaFrameSet(Alpha.combatFrames, Alpha.refreshToken, "MSUF_ALPHA_COMBAT", true)
end

_G.MSUF_Alpha_UpdatePreserveMissingHP = function(frame)
    if frame then
        ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, "MSUF_ALPHA")
    end
end
