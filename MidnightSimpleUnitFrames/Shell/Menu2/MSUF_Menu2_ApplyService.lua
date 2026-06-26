local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local C_Timer = _G.C_Timer
local type = type
local tostring = tostring
local pairs = pairs

local function WordList(words)
    if M.WordList then return M.WordList(words) end
    local out = {}
    for word in tostring(words or ""):gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

local function KeySet(...)
    if M.KeySet then return M.KeySet(...) end
    local out = {}
    for i = 1, select("#", ...) do
        out[select(i, ...)] = true
    end
    return out
end

local Apply = M.ApplyService or {}
M.ApplyService = Apply

local pendingUnits = Apply.pendingUnits or {}
local pendingOpts = Apply.pendingOpts or {}
local pendingGeneral = Apply.pendingGeneral
local flushQueued = Apply.flushQueued == true
local pendingPreview = Apply.pendingPreview
local pendingAlpha = Apply.pendingAlpha == true
local pendingCastbar = Apply.pendingCastbar == true

Apply.pendingUnits = pendingUnits
Apply.pendingOpts = pendingOpts

local debugprofilestop = _G.debugprofilestop
local APPLY_FLUSH_DELAY = 0.04
local UNIT_KEYS = KeySet("player", "target", "targettarget", "focustarget", "focus", "pet", "boss")

local PROFILE_APPLY_GLOBALS = Apply.PROFILE_APPLY_GLOBALS or WordList [[
    MSUF_GF_InvalidateCooldownTextCurve MSUF_GF_ForceCooldownTextRecolor MSUF_RefreshAllFrameColors MSUF_RefreshAllIdentityColors
    MSUF_RefreshAllPowerTextColors MSUF_RefreshAllFrames MSUF_UpdateAllBarTextures_Immediate
    MSUF_UpdateAllBarTextures MSUF_UpdateCastbarVisuals_Immediate MSUF_ClassPower_Refresh MSUF_ClassPower_RefreshTextures
]]
local RESTORE_GLOBALS = Apply.RESTORE_GLOBALS or WordList [[
    MSUF_UpdateAllFonts_Immediate MSUF_UpdateAllBarTextures_Immediate MSUF_UpdateAllBarTextures
    MSUF_UpdateCastbarVisuals_Immediate MSUF_UpdateCastbarVisuals MSUF_RefreshAllIdentityColors
    MSUF_RefreshAllPowerTextColors MSUF_RefreshAllUnitAlphas MSUF_RefreshAllFrames
]]
Apply.PROFILE_APPLY_GLOBALS = PROFILE_APPLY_GLOBALS
Apply.RESTORE_GLOBALS = RESTORE_GLOBALS

local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end

local function ReportError(err)
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if type(handler) == "function" then
        pcall(handler, err)
    elseif print then
        print(err)
    end
end

local perf = M.PerfProfile or Apply.perfProfile or { enabled = false, buckets = {} }
perf.buckets = perf.buckets or {}
M.PerfProfile = perf
Apply.perfProfile = perf

local function ResetPerfProfile()
    perf.buckets = {}
    perf.startedAt = debugprofilestop and debugprofilestop() or nil
end

local function ProfileStart()
    if not perf.enabled then return nil end
    return debugprofilestop and debugprofilestop() or false
end

local function RecordPerf(bucketName, key, elapsed, extraCount)
    if not perf.enabled then return end
    bucketName = tostring(bucketName or "misc")
    key = tostring(key or "unknown")
    local buckets = perf.buckets
    local bucket = buckets[bucketName]
    if not bucket then
        bucket = {}
        buckets[bucketName] = bucket
    end
    local rec = bucket[key]
    if not rec then
        rec = { count = 0, total = 0, max = 0, extra = 0 }
        bucket[key] = rec
    end
    elapsed = tonumber(elapsed) or 0
    rec.count = rec.count + 1
    rec.total = rec.total + elapsed
    if elapsed > rec.max then rec.max = elapsed end
    rec.extra = rec.extra + (tonumber(extraCount) or 0)
end

local function ProfileStop(bucketName, key, started, extraCount)
    if not perf.enabled then return end
    local elapsed = 0
    if type(started) == "number" and debugprofilestop then
        elapsed = debugprofilestop() - started
    end
    RecordPerf(bucketName, key, elapsed, extraCount)
end

function Apply.SetProfiling(enabled, reset)
    perf.enabled = enabled == true
    if reset ~= false then ResetPerfProfile() end
    return perf.enabled
end

function Apply.ResetProfiling()
    ResetPerfProfile()
end

function Apply.GetProfile()
    return perf
end

function M.RecordPerf(bucketName, key, elapsed, extraCount)
    RecordPerf(bucketName, key, elapsed, extraCount)
end

function M.ProfileStart()
    return ProfileStart()
end

function M.ProfileStop(bucketName, key, started, extraCount)
    ProfileStop(bucketName, key, started, extraCount)
end

function M.SetPerfProfiling(enabled, reset)
    return Apply.SetProfiling(enabled, reset)
end

function M.GetPerfProfile()
    return perf
end

function M.ResetPerfProfile()
    ResetPerfProfile()
end

function M.PrintPerfProfile(limit)
    limit = tonumber(limit) or 8
    if not print then return perf end
    local allRows = {}
    for bucketName, bucket in pairs(perf.buckets or {}) do
        for key, rec in pairs(bucket) do
            allRows[#allRows + 1] = { bucket = bucketName, key = key, rec = rec }
        end
    end
    table.sort(allRows, function(a, b) return (a.rec.total or 0) > (b.rec.total or 0) end)
    print("MSUF2 perf profile top:")
    for i = 1, math.min(limit, #allRows) do
        local row = allRows[i]
        local rec = row.rec
        local avg = (rec.count and rec.count > 0) and ((rec.total or 0) / rec.count) or 0
        print(string.format("  %s %s: %.2fms total, %.2fms max, %.2fms avg, %d calls", row.bucket, row.key, rec.total or 0, rec.max or 0, avg, rec.count or 0))
    end
    print("MSUF2 perf profile by bucket:")
    for bucketName, bucket in pairs(perf.buckets or {}) do
        local rows = {}
        for key, rec in pairs(bucket) do
            rows[#rows + 1] = { key = key, rec = rec }
        end
        table.sort(rows, function(a, b) return (a.rec.total or 0) > (b.rec.total or 0) end)
        for i = 1, math.min(limit, #rows) do
            local rec = rows[i].rec
            local avg = (rec.count and rec.count > 0) and ((rec.total or 0) / rec.count) or 0
            print(string.format("  %s %s: %.2fms total, %.2fms max, %.2fms avg, %d calls", bucketName, rows[i].key, rec.total or 0, rec.max or 0, avg, rec.count or 0))
        end
    end
    return perf
end

function Apply.SafeInvoke(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r1, r2, r3, r4 = pcall(fn, ...)
    if not ok then
        ReportError(r1)
        return false
    end
    return true, r1, r2, r3, r4
end

function Apply.CallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then
        if perf.enabled ~= true then return Apply.SafeInvoke(fn, ...) end
        local started = ProfileStart()
        local ok, r1, r2, r3, r4 = Apply.SafeInvoke(fn, ...)
        ProfileStop("global", name, started)
        return ok, r1, r2, r3, r4
    end
    return false
end

function Apply.CallGlobalResult(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then
        if perf.enabled ~= true then return Apply.SafeInvoke(fn, ...) end
        local started = ProfileStart()
        local ok, r1, r2, r3, r4 = Apply.SafeInvoke(fn, ...)
        ProfileStop("global", name, started)
        return ok, r1, r2, r3, r4
    end
    return false, nil
end

function Apply.CallGlobalList(names)
    for i = 1, #(names or {}) do
        Apply.CallGlobal(names[i])
    end
end

function Apply.NormalizeUnit(unit)
    unit = (unit == "tot") and "targettarget" or unit
    unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    if not UNIT_KEYS[unit] then return nil end
    return unit
end

local function ApplyUnitFrame(unit)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.Apply) == "function" then
        local ok, result = Apply.SafeInvoke(UF.Apply, unit)
        return ok and result == true
    end
    return false
end

local function RefreshTargetedGeneral(reason, opt)
    opt = opt or {}
    reason = tostring(reason or "")
    local upper = reason:upper()
    local textish = opt.text == true
        or upper:find("FONT", 1, true)
        or upper:find("TEXT", 1, true)
        or upper:find("NAME", 1, true)
    local powerish = opt.power == true or upper:find("POWER", 1, true)
    local alphaish = opt.alpha == true
        or upper:find("ALPHA", 1, true)
        or upper:find("OPACITY", 1, true)
        or upper:find("TRANSPARENC", 1, true)

    if textish then
        Apply.CallGlobal("MSUF_ForceTextLayoutForUnitKey")
    end
    if powerish then
        Apply.CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    end
    if alphaish then
        Apply.CallGlobal("MSUF_RefreshAllUnitAlphas")
    end
    if opt.visual == true or opt.frames == true then
        return Apply.CallGlobal("MSUF_RefreshAllFrames")
    end
    return textish or powerish or alphaish or false
end

local function HasTargetedGeneralRuntime(opts)
    return opts.text == true
        or opts.power == true
        or opts.alpha == true
        or opts.fonts == true
        or opts.bars == true
        or opts.castbar == true
        or opts.castbarTextures == true
        or opts.classpower == true
        or opts.colors == true
        or opts.frames == true
        or opts.visual ~= nil
end

local function RefreshActiveBossPreview(reason)
    local bossPageActive = _G.MSUF2_BossUnitframePreviewActive == true
    local editPreviewActive = _G.MSUF_UnitEditModeActive == true
        and (_G.MSUF_BossTestMode == true or _G.MSUF_PreviewTestMode == true)
    if not bossPageActive and not editPreviewActive then return end
    if bossPageActive and Apply.CallGlobal("MSUF_ApplyBossUnitframePreviewState", true, reason or "MSUF2_BOSS_PREVIEW") then return end
    Apply.CallGlobal("MSUF_SyncBossUnitframePreviewWithUnitEdit")
end

local function ProfiledGroupInvoke(label, fn, ...)
    local started = ProfileStart()
    local ok, r1, r2, r3, r4 = Apply.SafeInvoke(fn, ...)
    ProfileStop("groupApply", label, started)
    return ok, r1, r2, r3, r4
end

local function RefreshGroupFonts()
    local gf = MSUF and MSUF.GF
    if not gf then return end
    local dirty = gf.DIRTY_FONT or 4
    if type(gf.RefreshFonts) == "function" then return ProfiledGroupInvoke("RefreshFonts", gf.RefreshFonts) end
    if type(gf.MarkAllDirty) == "function" then
        return ProfiledGroupInvoke("MarkAllDirty:FONT", gf.MarkAllDirty, dirty)
    end
    if type(gf.RefreshVisuals) == "function" then
        return ProfiledGroupInvoke("RefreshVisuals:FONT", gf.RefreshVisuals, nil, dirty)
    end
end

local function RefreshGroupVisuals(mask, label)
    local gf = MSUF and MSUF.GF
    if not gf then return end
    local dirty = mask or gf.DIRTY_VISUAL or 2
    label = label or "RefreshVisuals"
    if type(gf.RefreshVisuals) == "function" then return ProfiledGroupInvoke(label, gf.RefreshVisuals, nil, dirty) end
    if type(gf.MarkAllDirty) == "function" then
        return ProfiledGroupInvoke("MarkAllDirty:" .. label, gf.MarkAllDirty, dirty)
    end
end

local function RefreshGroupColors()
    local gf = MSUF and MSUF.GF
    if not gf then return end
    local dirty = gf.DIRTY_COLOR or 8
    if type(gf.RefreshColors) == "function" then return ProfiledGroupInvoke("RefreshColors", gf.RefreshColors) end
    return RefreshGroupVisuals(dirty, "RefreshVisuals:COLOR")
end

local function PushVisualUpdates()
    local api = MSUF and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then Apply.SafeInvoke(api.PushVisualUpdates) end
end

local function ApplyFontRuntime(opt)
    Apply.CallGlobal("MSUF_UpdateAllFonts_Immediate")
    if not (opt and opt.colors) then
        Apply.CallGlobal("MSUF_RefreshAllIdentityColors")
        Apply.CallGlobal("MSUF_RefreshAllPowerTextColors")
    end
    RefreshGroupFonts()
end

local function ApplyBarRuntime()
    Apply.CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    Apply.CallGlobal("MSUF_UpdateAllBarTextures")
    Apply.CallGlobal("MSUF_UpdateAbsorbBarTextures")
    Apply.CallGlobal("MSUF_InvalidateAbsorbCache")
    RefreshGroupVisuals(nil, "RefreshVisuals:BARS")
end

local function ApplyCastbarRuntime(opt)
    if opt and opt.castbarTextures then
        Apply.CallGlobal("MSUF_UpdateCastbarTextures_Immediate")
        Apply.CallGlobal("MSUF_UpdateCastbarTextures")
    end
    Apply.CallGlobal("MSUF_UpdateBossCastbarPreview")
end

local function ApplyColorRuntime(opt)
    if not Apply.CallGlobal("MSUF_RefreshAllFrameColors") then
        Apply.CallGlobal("MSUF_RefreshAllIdentityColors")
        Apply.CallGlobal("MSUF_RefreshAllPowerTextColors")
    end
    if not (opt and opt.bars) then Apply.CallGlobal("MSUF_UpdateAllBarTextures_Immediate") end
    Apply.CallGlobal("MSUF_PrioRows_Reinit")
    if type(M.ApplyGameplay) == "function" then Apply.SafeInvoke(M.ApplyGameplay) end
    RefreshGroupColors()
end

local function FlushApply()
    local flushStarted = perf.enabled == true and ProfileStart() or nil
    flushQueued = false
    Apply.flushQueued = false

    local wantPreview = pendingPreview
    pendingPreview = nil
    Apply.pendingPreview = nil

    local wantAlpha = pendingAlpha
    pendingAlpha = false
    Apply.pendingAlpha = false

    for unit in pairs(pendingUnits) do
        local opt = pendingOpts[unit] or {}
        local notifyUnit = (unit == "boss") and nil or unit
        local applied = false

        if opt.notify ~= false then
            local called, result = Apply.CallGlobalResult("MSUF_UFCore_NotifyConfigChanged", notifyUnit, true, true, opt.reason or "MSUF2")
            applied = called and result ~= false or false
        end
        if opt.text then Apply.CallGlobal("MSUF_ForceTextLayoutForUnitKey", unit) end
        if opt.power then
            if not (_G.InCombatLockdown and _G.InCombatLockdown()) then
                if not Apply.CallGlobal("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", unit, true) then
                    Apply.CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
                end
            end
            if unit == "player" then Apply.CallGlobal("MSUF_ClassPower_Refresh") end
        end
        if not applied then applied = ApplyUnitFrame(unit) end
        if not applied then Apply.CallGlobal("MSUF_RefreshAllFrames", unit) end
    end
    WipeTable(pendingUnits)
    WipeTable(pendingOpts)

    if pendingGeneral then
        local opt = pendingGeneral
        pendingGeneral = nil
        Apply.pendingGeneral = nil

        local applied = false
        local applyAll = opt.applyAll ~= false
        if applyAll and opt.notify ~= false then
            local called, result = Apply.CallGlobalResult("MSUF_UFCore_NotifyConfigChanged", nil, true, true, opt.reason or "MSUF2_GENERAL")
            applied = called and result ~= false or false
        end
        if opt.fonts then ApplyFontRuntime(opt) end
        if opt.bars then ApplyBarRuntime() end
        if opt.castbarTextures then ApplyCastbarRuntime(opt) end
        if opt.colors and not opt.colorsPushed then ApplyColorRuntime(opt) end
        if applyAll and not applied then ApplyUnitFrame(nil) end
        if not applyAll then RefreshTargetedGeneral(opt.reason or "MSUF2_GENERAL", opt) end
    end

    if pendingCastbar then
        pendingCastbar = false
        Apply.pendingCastbar = false
        Apply.CallGlobal("MSUF_UpdateCastbarVisuals")
    end
    if wantAlpha then Apply.CallGlobal("MSUF_RefreshAllUnitAlphas") end
    if wantPreview then
        Apply.CallGlobal("MSUF_UFPreview_RequestRefresh", wantPreview)
        RefreshActiveBossPreview(wantPreview)
    end
    if perf.enabled == true then ProfileStop("apply", "FlushApply", flushStarted) end
end

function Apply.QueueFlush()
    if flushQueued then return true end
    flushQueued = true
    Apply.flushQueued = true
    if type(_G.MSUF_ScheduleDelayOnce) == "function" then
        _G.MSUF_ScheduleDelayOnce("MSUF2_APPLY", APPLY_FLUSH_DELAY, FlushApply)
    elseif type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce("MSUF2_APPLY", FlushApply)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(APPLY_FLUSH_DELAY, FlushApply)
    else
        FlushApply()
    end
    return true
end

function Apply.RequestUnit(unit, reason, opts)
    unit = Apply.NormalizeUnit(unit)
    if not unit then return false end

    pendingUnits[unit] = true
    local o = pendingOpts[unit]
    if not o then
        o = {}
        pendingOpts[unit] = o
    end
    o.reason = reason or o.reason or "MSUF2"
    if opts then
        if opts.text then o.text = true end
        if opts.power then o.power = true end
        if opts.notify == false then o.notify = false end
        if opts.fonts then
            if not pendingGeneral then pendingGeneral = {} end
            Apply.pendingGeneral = pendingGeneral
            if pendingGeneral.applyAll == nil then pendingGeneral.applyAll = false end
            pendingGeneral.reason = pendingGeneral.reason or reason or "MSUF2_FONTS"
            pendingGeneral.fonts = true
            pendingGeneral.text = true
        end
        if opts.castbar then pendingCastbar = true; Apply.pendingCastbar = true end
        if opts.alpha then pendingAlpha = true; Apply.pendingAlpha = true end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2"; Apply.pendingPreview = pendingPreview end
    else
        pendingPreview = reason or "MSUF2"
        Apply.pendingPreview = pendingPreview
    end
    return Apply.QueueFlush()
end

function Apply.RequestGeneral(reason, opts)
    if not pendingGeneral then pendingGeneral = {} end
    Apply.pendingGeneral = pendingGeneral
    pendingGeneral.reason = reason or pendingGeneral.reason or "MSUF2_GENERAL"
    if opts and opts.applyAll == false then
        if pendingGeneral.applyAll == nil then pendingGeneral.applyAll = false end
    else
        pendingGeneral.applyAll = true
    end
    if opts then
        if opts.notify == false then pendingGeneral.notify = false end
        if opts.text then pendingGeneral.text = true end
        if opts.power then pendingGeneral.power = true end
        if opts.fonts then pendingGeneral.fonts = true; pendingGeneral.text = true end
        if opts.bars then pendingGeneral.bars = true end
        if opts.castbarTextures then pendingGeneral.castbarTextures = true end
        if opts.colors then pendingGeneral.colors = true end
        if opts.colorsPushed then pendingGeneral.colorsPushed = true end
        if opts.alpha then pendingGeneral.alpha = true; pendingAlpha = true; Apply.pendingAlpha = true end
        if opts.castbar then pendingCastbar = true; Apply.pendingCastbar = true end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2_GENERAL"; Apply.pendingPreview = pendingPreview end
        if opts.visual ~= nil then pendingGeneral.visual = opts.visual and true or false end
        if opts.frames then pendingGeneral.frames = true end
        if opts.applyAll == false and not HasTargetedGeneralRuntime(opts) and pendingGeneral.visual ~= true then pendingGeneral.visual = true end
    else
        pendingPreview = reason or "MSUF2_GENERAL"
        Apply.pendingPreview = pendingPreview
    end
    return Apply.QueueFlush()
end

function Apply.RequestVisuals(reason)
    PushVisualUpdates()
    return Apply.RequestGeneral(reason or "MSUF2_VISUALS", {
        preview = true,
        applyAll = false,
        fonts = true,
        bars = true,
    })
end

function Apply.RequestColors(reason)
    PushVisualUpdates()
    return Apply.RequestGeneral(reason or "MSUF2_COLORS", {
        preview = true,
        applyAll = false,
        fonts = true,
        bars = true,
        colors = true,
        colorsPushed = true,
    })
end

function Apply.RequestFonts(reason)
    return Apply.RequestGeneral(reason or "MSUF2_FONTS", {
        preview = true,
        applyAll = false,
        fonts = true,
    })
end

function Apply.RequestBars(reason)
    return Apply.RequestGeneral(reason or "MSUF2_BARS", {
        preview = true,
        applyAll = false,
        bars = true,
    })
end

function Apply.RequestCastbars(reason, source)
    Apply.CallGlobal("MSUF_Castbars_OnSettingsChanged", source or "menu")
    return Apply.RequestGeneral(reason or "MSUF2_CASTBARS", {
        castbar = true,
        castbarTextures = true,
        preview = true,
        applyAll = false,
    })
end

function Apply.ApplyProfileFanout(reason)
    Apply.CallGlobalList(PROFILE_APPLY_GLOBALS)
    Apply.CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "MSUF2_PROFILE_APPLY")
end

function Apply.ApplyRestoreFanout(reason)
    Apply.CallGlobalList(RESTORE_GLOBALS)
    Apply.CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "MSUF2_RESTORE")
end

Apply.Flush = FlushApply
Apply.RefreshTargetedGeneral = RefreshTargetedGeneral
Apply.RefreshActiveBossPreview = RefreshActiveBossPreview

ExportPublic("MSUF_Menu2_ApplyService", Apply)
ExportPublic("MSUF_Menu2_SetPerfProfiling", M.SetPerfProfiling)
ExportPublic("MSUF_Menu2_GetPerfProfile", M.GetPerfProfile)
ExportPublic("MSUF_Menu2_ResetPerfProfile", M.ResetPerfProfile)
ExportPublic("MSUF_Menu2_PrintPerfProfile", M.PrintPerfProfile)
