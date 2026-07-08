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
local next = next
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown

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
local pendingAlphaAll = Apply.pendingAlphaAll == true
local pendingAlphaUnits = Apply.pendingAlphaUnits or {}
local pendingCastbar = Apply.pendingCastbar == true
local pendingCastbarUnits = Apply.pendingCastbarUnits or {}
local pendingClassPowerOpts = Apply.pendingClassPowerOpts
local pendingCastbarSettingsChanged = Apply.pendingCastbarSettingsChanged == true
local pendingCastbarSettingsSource = Apply.pendingCastbarSettingsSource
local pendingAuraScopes = Apply.pendingAuraScopes or {}
local pendingAuraAll = Apply.pendingAuraAll == true
local pendingAuraReason = Apply.pendingAuraReason
local pendingAuraVisuals = Apply.pendingAuraVisuals == true
local pendingGroups = Apply.pendingGroups or {}
local pendingGroupReason = Apply.pendingGroupReason
local applyCombatDeferred = Apply.applyCombatDeferred == true
local applyCombatDeferFrame
local FlushApply

Apply.pendingUnits = pendingUnits
Apply.pendingOpts = pendingOpts
Apply.pendingAlphaUnits = pendingAlphaUnits
Apply.pendingCastbarUnits = pendingCastbarUnits
Apply.pendingClassPowerOpts = pendingClassPowerOpts
Apply.pendingCastbarSettingsChanged = pendingCastbarSettingsChanged
Apply.pendingCastbarSettingsSource = pendingCastbarSettingsSource
Apply.pendingAuraScopes = pendingAuraScopes
Apply.pendingAuraAll = pendingAuraAll
Apply.pendingAuraReason = pendingAuraReason
Apply.pendingAuraVisuals = pendingAuraVisuals
Apply.pendingGroups = pendingGroups
Apply.pendingGroupReason = pendingGroupReason

local debugprofilestop = _G.debugprofilestop
local APPLY_FLUSH_DELAY = 0.04
local UNIT_KEYS = KeySet("player", "target", "targettarget", "focustarget", "focus", "pet", "boss")
local CASTBAR_UNITS = KeySet("player", "target", "focus", "boss")

local PROFILE_APPLY_GLOBALS = Apply.PROFILE_APPLY_GLOBALS or WordList [[
    MSUF_GF_InvalidateCooldownTextCurve MSUF_GF_ForceCooldownTextRecolor MSUF_RefreshAllFrameColors MSUF_RefreshAllIdentityColors
    MSUF_RefreshAllPowerTextColors MSUF_RefreshAllFrames MSUF_UpdateAllBarTextures_Immediate
    MSUF_UpdateAllBarTextures
]]
local RESTORE_GLOBALS = Apply.RESTORE_GLOBALS or WordList [[
    MSUF_UpdateAllFonts_Immediate MSUF_UpdateAllBarTextures_Immediate MSUF_UpdateAllBarTextures
    MSUF_RefreshAllIdentityColors
    MSUF_RefreshAllPowerTextColors MSUF_RefreshAllUnitAlphas MSUF_RefreshAllFrames
]]
Apply.PROFILE_APPLY_GLOBALS = PROFILE_APPLY_GLOBALS
Apply.RESTORE_GLOBALS = RESTORE_GLOBALS

local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function EnsureApplyCombatDeferFrame()
    if applyCombatDeferFrame or type(CreateFrame) ~= "function" then
        return applyCombatDeferFrame
    end
    applyCombatDeferFrame = CreateFrame("Frame")
    applyCombatDeferFrame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        applyCombatDeferred = false
        Apply.applyCombatDeferred = false
        if FlushApply then FlushApply() end
    end)
    return applyCombatDeferFrame
end

local function DeferApplyFlushUntilCombatEnds()
    applyCombatDeferred = true
    Apply.applyCombatDeferred = true
    local frame = EnsureApplyCombatDeferFrame()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return true
end

local function MergeScopeField(target, field, scope)
    if type(target) ~= "table" or not field then return end
    local value = tostring(scope or "")
    if value == "" then value = "*" end
    local current = target[field]
    if current == nil then
        target[field] = value
    elseif current ~= value then
        target[field] = "*"
    end
end

local function NormalizeApplyScope(scope)
    scope = tostring(scope or ""):lower()
    if scope == "" then return nil end
    return scope
end

local function IsGlobalApplyScope(scope)
    scope = NormalizeApplyScope(scope)
    return scope == nil or scope == "*" or scope == "shared" or scope == "global" or scope == "all"
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

local function ApplyAuraScope(scope, reason)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if not a3 then return false end
    local model = a3.MenuModel
    if model and type(model.Apply) == "function" then
        local ok, result = Apply.SafeInvoke(model.Apply, scope, reason or "MSUF2_AURAS")
        return ok == true and result ~= false
    end
    if type(a3.RequestScope) == "function" then
        local ok, result = Apply.SafeInvoke(a3.RequestScope, scope, reason or "MSUF2_AURAS")
        return ok == true and result ~= false
    end
    if IsGlobalApplyScope(scope) and type(a3.RequestApply) == "function" then
        local ok, result = Apply.SafeInvoke(a3.RequestApply, scope or "shared", reason or "MSUF2_AURAS")
        return ok == true and result ~= false
    end
    if type(a3.RefreshUnit) == "function" then
        local ok, result = Apply.SafeInvoke(a3.RefreshUnit, scope)
        return ok == true and result ~= false
    end
    if type(a3.RequestUnit) == "function" then
        local ok, result = Apply.SafeInvoke(a3.RequestUnit, scope)
        return ok == true and result ~= false
    end
    return false
end

local function ApplyUnitAuras(unit, reason)
    return ApplyAuraScope(unit, reason or "MSUF2_UNIT_AURAS")
end

local function BumpAuraNativeVisuals()
    local a3 = MSUF and MSUF.MSUF_Auras3
    if not a3 then return false end
    a3._nativeVisualGen = (a3._nativeVisualGen or 0) + 1
    return true
end

local function QueueAuraScope(scope, reason, visuals)
    scope = NormalizeApplyScope(scope) or "shared"
    reason = reason or "MSUF2_AURAS"
    if IsGlobalApplyScope(scope) then
        pendingAuraAll = true
        Apply.pendingAuraAll = true
        WipeTable(pendingAuraScopes)
    else
        pendingAuraScopes[scope] = reason
    end
    pendingAuraReason = reason
    Apply.pendingAuraReason = reason
    if visuals == true then
        pendingAuraVisuals = true
        Apply.pendingAuraVisuals = true
    end
    pendingPreview = reason
    Apply.pendingPreview = reason
    return true
end

local function FlushPendingAuras()
    if pendingAuraAll ~= true and next(pendingAuraScopes) == nil then return false end

    local reason = pendingAuraReason or "MSUF2_AURAS"
    local did = false
    if pendingAuraVisuals == true then
        pendingAuraVisuals = false
        Apply.pendingAuraVisuals = false
        did = BumpAuraNativeVisuals() or did
    end
    if pendingAuraAll == true then
        pendingAuraAll = false
        Apply.pendingAuraAll = false
        WipeTable(pendingAuraScopes)
        did = ApplyAuraScope("shared", reason) or did
    else
        for scope, scopeReason in pairs(pendingAuraScopes) do
            pendingAuraScopes[scope] = nil
            did = ApplyAuraScope(scope, scopeReason or reason) or did
        end
    end
    pendingAuraReason = nil
    Apply.pendingAuraReason = nil
    return did
end

local function NormalizeCastbarUnit(unit)
    unit = tostring(unit or "")
    if unit:match("^boss%d+$") then return "boss" end
    if CASTBAR_UNITS[unit] == true then return unit end
    return nil
end

local function ApplyUnitCastbar(unit)
    unit = NormalizeCastbarUnit(unit)
    if not unit then return false end
    if Apply.CallGlobal("MSUF_ApplyCastbarUnitAndSync", unit) then return true end
    return Apply.CallGlobal("MSUF_ApplyCastbarVisualsForUnit", unit)
end

local function WantsClassPower(opts)
    return opts and (
        opts.classpower == true
        or opts.classPower == true
        or opts.classPowerPlayerHP == true
        or opts.detachedPowerBar == true
        or opts.altMana == true)
end

local function ClassPowerAlreadyApplied(opts)
    return opts and (opts.classpowerApplied == true or opts.classPowerApplied == true)
end

local function WantsFullClassPower(opts)
    return opts and (
        opts.classpower == true
        or opts.classPower == true
        or opts.altMana == true)
end

local function ClassPowerRuntimeOptions(opts)
    if opts and type(opts.classPowerRuntime) == "table" then
        return opts.classPowerRuntime
    end
    if opts and opts.detachedPowerBar == true and opts.classPowerFull ~= true then
        return { anchor = true, cdm = true, playerHP = true, syncNow = false }
    end
    if opts and opts.classPowerPlayerHP == true and opts.classPowerFull ~= true then
        return { playerHP = true }
    end
    return { full = true, cdm = true }
end

local function EnsurePendingClassPowerOpts()
    if type(pendingClassPowerOpts) ~= "table" then
        pendingClassPowerOpts = {}
        Apply.pendingClassPowerOpts = pendingClassPowerOpts
    end
    return pendingClassPowerOpts
end

local function MergeClassPowerApplyOptions(target, opts)
    target = target or EnsurePendingClassPowerOpts()
    if type(opts) ~= "table" then
        target.full = true
        target.cdm = true
        return target
    end
    if opts.full == true or opts.structure == true or opts.layout == true then
        target.full = true
    end
    if opts.structure == true then target.structure = true end
    if opts.layout == true then target.layout = true end
    if opts.visuals == true then target.visuals = true end
    if opts.colors == true then target.colors = true end
    if opts.textures == true then target.textures = true end
    if opts.fonts == true then target.fonts = true end
    if opts.text == true then target.text = true end
    if opts.anchor == true then target.anchor = true end
    if opts.reanchor == true then target.reanchor = true end
    if opts.geometry == true then target.geometry = true end
    if opts.playerHP == true then target.playerHP = true end
    if opts.playerHPTextures == true then target.playerHPTextures = true end
    if opts.cdm == true then target.cdm = true end
    if opts.width == true then target.width = true end
    if opts.events == true then target.events = true end
    if opts.syncNow == false then target.syncNow = false end
    return target
end

local function FlushPendingClassPower()
    local opts = pendingClassPowerOpts
    if type(opts) ~= "table" then return false end
    pendingClassPowerOpts = nil
    Apply.pendingClassPowerOpts = nil
    return Apply.CallGlobal("MSUF_ClassPower_Apply", opts)
end

local function ApplyPowerLayoutForUnit(unit)
    unit = Apply.NormalizeUnit(unit)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
    if unit and Apply.CallGlobal("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", unit, true) then
        return true
    end
    return Apply.CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
end

local function ApplyDetachedPowerBarRuntime(unit, refreshTextures)
    unit = Apply.NormalizeUnit(unit) or "player"
    local did = false
    if refreshTextures ~= false and unit == "player" then
        did = Apply.CallGlobal("MSUF_DetachedPowerBar_RefreshTextures") or did
    end
    did = ApplyPowerLayoutForUnit(unit) or did
    return did
end

local function ApplyAllCastbars()
    local did = false
    did = ApplyUnitCastbar("player") or did
    did = ApplyUnitCastbar("target") or did
    did = ApplyUnitCastbar("focus") or did
    did = ApplyUnitCastbar("boss") or did
    if did then return true end
    return Apply.CallGlobal("MSUF_UpdateCastbarVisuals")
end

local function RefreshTargetedGeneral(reason, opt)
    opt = opt or {}
    reason = tostring(reason or "")
    local upper = reason:upper()
    local textScope = Apply.NormalizeUnit(opt.fontScope or opt.textScope or opt.scope)
    local powerScope = Apply.NormalizeUnit(opt.powerScope or opt.barsScope or opt.scope)
    local alphaScope = Apply.NormalizeUnit(opt.alphaScope or opt.scope)
    local textish = opt.text == true
        or upper:find("FONT", 1, true)
        or upper:find("TEXT", 1, true)
        or upper:find("NAME", 1, true)
    local powerish = opt.power == true or upper:find("POWER", 1, true)
    local alphaish = opt.alpha == true
        or upper:find("ALPHA", 1, true)
        or upper:find("OPACITY", 1, true)
        or upper:find("TRANSPARENC", 1, true)
    local detachedPowerish = opt.detachedPowerBar == true
    if detachedPowerish then powerish = true end
    local classpowerish = WantsClassPower(opt)
        or upper:find("CLASSPOWER", 1, true)
        or upper:find("CLASS_POWER", 1, true)
        or upper:find("CLASS POWER", 1, true)
    local did = false

    if textish then
        if textScope then
            did = Apply.CallGlobal("MSUF_ForceTextLayoutForUnitKey", textScope) or did
        else
            did = Apply.CallGlobal("MSUF_ForceTextLayoutForUnitKey") or did
        end
    end
    if powerish then
        if detachedPowerish then
            did = ApplyDetachedPowerBarRuntime(powerScope or "player", true) or did
        elseif powerScope then
            did = ApplyPowerLayoutForUnit(powerScope) or did
        else
            did = ApplyPowerLayoutForUnit(nil) or did
        end
    end
    if alphaish then
        if alphaScope then
            did = Apply.CallGlobal("MSUF_RefreshAllUnitAlphas", alphaScope) or did
        else
            did = Apply.CallGlobal("MSUF_RefreshAllUnitAlphas") or did
        end
    end
    if classpowerish and not ClassPowerAlreadyApplied(opt) then
        did = Apply.CallGlobal("MSUF_ClassPower_Apply", ClassPowerRuntimeOptions(opt)) or did
    end
    if opt.visual == true or opt.frames == true then
        return Apply.CallGlobal("MSUF_RefreshAllFrames")
    end
    return did or textish or powerish or alphaish or classpowerish or detachedPowerish or false
end

local function HasTargetedGeneralRuntime(opts)
    return opts.text == true
        or opts.power == true
        or opts.alpha == true
        or opts.fonts == true
        or opts.bars == true
        or opts.barGradients == true
        or opts.barOutline == true
        or opts.roundedBars == true
        or opts.aggroBorder == true
        or opts.dispelPurgeBorder == true
        or opts.bossTargetBorder == true
        or opts.castbar == true
        or opts.castbarTextures == true
        or WantsClassPower(opts)
        or opts.colors == true
        or opts.frames == true
        or opts.visual ~= nil
end

local function WantsBarRuntime(opts)
    return opts and (
        opts.bars == true
        or opts.barGradients == true
        or opts.barOutline == true
        or opts.roundedBars == true
        or opts.aggroBorder == true
        or opts.dispelPurgeBorder == true
        or opts.bossTargetBorder == true)
end

local function UnitRuntimeNeedsSettingsCache(opt)
    return opt and opt.notify == false and (
        opt.text == true
        or opt.power == true
        or opt.detachedPowerBar == true
        or opt.auras == true
        or opt.castbar == true)
end

local function GeneralRuntimeNeedsSettingsCache(opt)
    if type(opt) ~= "table" then return false end
    if opt.applyAll ~= false and opt.notify ~= false then return false end
    return opt.text == true
        or opt.power == true
        or opt.detachedPowerBar == true
        or opt.fonts == true
        or opt.colors == true
        or opt.castbarTextures == true
        or WantsBarRuntime(opt)
        or WantsClassPower(opt)
        or opt.visual ~= nil
        or opt.frames == true
end

local function FlushScopedSettingsCache(reason)
    return Apply.CallGlobal("MSUF_UFCore_RefreshSettingsCache", reason or "MSUF2_RUNTIME")
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

local function MaskHas(mask, flag)
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return false end
    return mask % (flag * 2) >= flag
end

local function AddDirty(mask, flag)
    if not flag then return mask or 0 end
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 or MaskHas(mask, flag) then return mask end
    return mask + flag
end

local function GroupKindsForScope(scope)
    scope = NormalizeApplyScope(scope)
    if scope == "gf_party" or scope == "party" then return "party" end
    if scope == "gf_raid" or scope == "raid" then return "raid", "mythicraid" end
    if scope == "gf_mythicraid" or scope == "mythicraid" then return "mythicraid" end
    return nil
end

local function GroupKindForApplyScope(scope)
    scope = NormalizeApplyScope(scope)
    if scope == "gf_party" or scope == "party" then return "party" end
    if scope == "gf_raid" or scope == "raid" then return "raid" end
    if scope == "gf_mythicraid" or scope == "mythicraid" then return "mythicraid" end
    if scope == "group" or scope == "groups" then return "*" end
    if IsGlobalApplyScope(scope) then return "*" end
    return nil
end

local function GroupDirtyForMode(gf, mode)
    if type(gf) ~= "table" then return nil end
    mode = tostring(mode or "visual")
    if mode == "geometry" then
        local dirty = AddDirty(nil, gf.DIRTY_GEOMETRY)
        dirty = AddDirty(dirty, gf.DIRTY_LAYOUT)
        return dirty ~= 0 and dirty or gf.DIRTY_VISUAL
    end
    if mode == "config" then return gf.DIRTY_CONFIG or gf.DIRTY_ALL end
    if mode == "auras" then return gf.DIRTY_AURAS end
    if mode == "fonts" or mode == "font" then return gf.DIRTY_FONT end
    if mode == "border" or mode == "borders" then return gf.DIRTY_BORDER end
    if mode == "colors" or mode == "color" then return gf.DIRTY_COLOR end
    return gf.DIRTY_VISUAL
end

local function MergeGroupDirty(gf, current, incoming)
    if not current then return incoming end
    if not incoming then return current end
    if current == true or incoming == true then return true end
    if gf then
        if current == gf.DIRTY_ALL or incoming == gf.DIRTY_ALL then return gf.DIRTY_ALL end
        if current == gf.DIRTY_CONFIG or incoming == gf.DIRTY_CONFIG then return gf.DIRTY_CONFIG end
    end
    if type(current) ~= "number" or type(incoming) ~= "number" then return incoming end
    local out = current
    if gf then
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_VISUAL) and gf.DIRTY_VISUAL or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_FONT) and gf.DIRTY_FONT or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_COLOR) and gf.DIRTY_COLOR or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_BORDER) and gf.DIRTY_BORDER or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_GEOMETRY) and gf.DIRTY_GEOMETRY or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_LAYOUT) and gf.DIRTY_LAYOUT or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_AURAS) and gf.DIRTY_AURAS or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_UNIT_BINDING) and gf.DIRTY_UNIT_BINDING or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_CONFIG) and gf.DIRTY_CONFIG or nil)
    end
    return out
end

local function RefreshGroupPreview(kind, reason)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshPreviewLayout) == "function" then
        ProfiledGroupInvoke("RefreshPreviewLayout", gf.RefreshPreviewLayout, kind)
    elseif type(_G.MSUF_GF_RefreshPreviewLayout) == "function" then
        Apply.CallGlobal("MSUF_GF_RefreshPreviewLayout", kind)
    end
    if type(M.RefreshGFNativePreviews) == "function" then
        Apply.SafeInvoke(M.RefreshGFNativePreviews, reason or "MSUF2_GROUP")
    end
end

local function ApplyGroupTargetedSpells()
    local gf = MSUF and MSUF.GF
    local ts = gf and gf.TargetedSpells
    if ts and type(ts.RequestApply) == "function" then
        return Apply.SafeInvoke(ts.RequestApply, false)
    end
    if ts and type(ts.RefreshConfig) == "function" then
        return Apply.SafeInvoke(ts.RefreshConfig, false)
    end
    return false
end

local function FinishGroupRecord(gf, rec, kind, reason, did)
    if rec and rec.requestAuraRefresh and gf and type(gf.RequestAuraRefresh) == "function" then
        local ok = ProfiledGroupInvoke("RequestAuraRefresh", gf.RequestAuraRefresh, kind)
        did = ok == true or did
    end
    RefreshGroupPreview(kind, reason)
    return did
end

local function ApplyGroupRecord(kindKey, rec, reason)
    local gf = MSUF and MSUF.GF
    if not rec then return false end
    local kind = kindKey ~= "*" and kindKey or nil
    local dirty = rec.dirtyMask
    local did = false

    if rec.invalidateConfCache then
        if gf and type(gf.InvalidateConfCache) == "function" then
            local ok = ProfiledGroupInvoke("InvalidateConfCache", gf.InvalidateConfCache)
            did = ok == true or did
        else
            did = Apply.CallGlobal("MSUF_GF_InvalidateConfCache") or did
        end
    end
    if rec.targetedSpells then
        local ok = ApplyGroupTargetedSpells()
        did = ok == true or did
    end
    if not gf then
        if rec.rebuild and type(_G.MSUF_GF_RefreshAll) == "function" then
            did = Apply.CallGlobal("MSUF_GF_RefreshAll") or did
        elseif dirty and type(_G.MSUF_GF_RefreshVisuals) == "function" then
            did = Apply.CallGlobal("MSUF_GF_RefreshVisuals", kind, dirty) or did
        end
        return FinishGroupRecord(nil, rec, kind, reason, did)
    end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if rec.rebuild and type(gf.DeferGroupRuntime) == "function" then
            ProfiledGroupInvoke("DeferGroupRuntime:rebuild", gf.DeferGroupRuntime, "rebuild", kind, dirty)
            did = true
        elseif rec.rebuild and type(gf.Rebuild) == "function" then
            ProfiledGroupInvoke("Rebuild:combat", gf.Rebuild, kind)
            did = true
        elseif rec.geometry and type(gf.DeferGroupRuntime) == "function" then
            ProfiledGroupInvoke("DeferGroupRuntime:layout", gf.DeferGroupRuntime, "layout", kind, dirty)
            did = true
        elseif dirty and type(gf.DeferGroupRuntime) == "function" then
            ProfiledGroupInvoke("DeferGroupRuntime:refresh", gf.DeferGroupRuntime, "refresh", kind, dirty)
            did = true
        end
        return FinishGroupRecord(gf, rec, kind, reason, did)
    end

    if rec.rebuild then
        if type(gf.Rebuild) == "function" then
            ProfiledGroupInvoke("Rebuild", gf.Rebuild, kind)
            did = true
        elseif kind == nil and type(gf.RebuildAll) == "function" then
            ProfiledGroupInvoke("RebuildAll", gf.RebuildAll)
            did = true
        else
            if type(gf.RefreshGeometry) == "function" then ProfiledGroupInvoke("RefreshGeometry:rebuild", gf.RefreshGeometry, kind); did = true end
            if type(gf.RefreshUnitBindings) == "function" then ProfiledGroupInvoke("RefreshUnitBindings:rebuild", gf.RefreshUnitBindings, kind); did = true end
            if type(gf.RefreshVisuals) == "function" then ProfiledGroupInvoke("RefreshVisuals:rebuild", gf.RefreshVisuals, kind, gf.DIRTY_ALL or dirty); did = true end
        end
        return FinishGroupRecord(gf, rec, kind, reason, did)
    end

    if rec.geometry and type(gf.RefreshGeometry) == "function" then
        ProfiledGroupInvoke("RefreshGeometry", gf.RefreshGeometry, kind)
        did = true
    end
    if dirty and type(gf.RefreshVisuals) == "function" then
        ProfiledGroupInvoke("RefreshVisuals", gf.RefreshVisuals, kind, dirty)
        did = true
    end
    return FinishGroupRecord(gf, rec, kind, reason, did)
end

local function QueueGroupKey(scope)
    local normalized = NormalizeApplyScope(scope)
    local key = GroupKindForApplyScope(normalized)
    if key then return key end
    if normalized == nil or normalized == "" then return "*" end
    return "party"
end

local function QueueGroup(scope, mode, reason)
    local key = QueueGroupKey(scope)
    local rec = pendingGroups[key]
    if not rec then
        rec = {}
        pendingGroups[key] = rec
    end
    mode = tostring(mode or "visual")
    local gf = MSUF and MSUF.GF
    if mode == "targetedSpells" then
        rec.targetedSpells = true
        rec.dirtyMask = MergeGroupDirty(gf, rec.dirtyMask, gf and gf.DIRTY_VISUAL or true)
    elseif mode == "reset" then
        rec.invalidateConfCache = true
        rec.requestAuraRefresh = true
        rec.rebuild = true
        rec.dirtyMask = MergeGroupDirty(gf, rec.dirtyMask, gf and gf.DIRTY_ALL or true)
    elseif mode == "rebuild" then
        rec.rebuild = true
        rec.dirtyMask = MergeGroupDirty(gf, rec.dirtyMask, gf and gf.DIRTY_ALL or true)
    else
        if mode == "geometry" then rec.geometry = true end
        rec.dirtyMask = MergeGroupDirty(gf, rec.dirtyMask, GroupDirtyForMode(gf, mode))
    end
    pendingGroupReason = reason or pendingGroupReason or "MSUF2_GROUP"
    Apply.pendingGroupReason = pendingGroupReason
    pendingPreview = reason or pendingPreview or "MSUF2_GROUP"
    Apply.pendingPreview = pendingPreview
end

local function QueueGroupDirtyMask(scope, dirtyMask, reason)
    if not dirtyMask then return QueueGroup(scope, "visual", reason) end
    local key = QueueGroupKey(scope)
    local rec = pendingGroups[key]
    if not rec then
        rec = {}
        pendingGroups[key] = rec
    end
    local gf = MSUF and MSUF.GF
    rec.dirtyMask = MergeGroupDirty(gf, rec.dirtyMask, dirtyMask)
    pendingGroupReason = reason or pendingGroupReason or "MSUF2_GROUP"
    Apply.pendingGroupReason = pendingGroupReason
    pendingPreview = reason or pendingPreview or "MSUF2_GROUP"
    Apply.pendingPreview = pendingPreview
end

local function FlushPendingGroups()
    if next(pendingGroups) == nil then return false end
    local reason = pendingGroupReason or "MSUF2_GROUP"
    pendingGroupReason = nil
    Apply.pendingGroupReason = nil
    local did = false
    for key, rec in pairs(pendingGroups) do
        pendingGroups[key] = nil
        did = ApplyGroupRecord(key, rec, reason) or did
    end
    return did
end

local function RefreshGroupFonts(scope)
    local gf = MSUF and MSUF.GF
    if not gf then return end
    local kindA, kindB = GroupKindsForScope(scope)
    if not kindA and not IsGlobalApplyScope(scope) then return false end
    local dirty = gf.DIRTY_FONT or 4
    if type(gf.RefreshFonts) == "function" then
        if kindA then
            local did = ProfiledGroupInvoke("RefreshFonts:" .. kindA, gf.RefreshFonts, kindA)
            if kindB then did = ProfiledGroupInvoke("RefreshFonts:" .. kindB, gf.RefreshFonts, kindB) or did end
            return did
        end
        return ProfiledGroupInvoke("RefreshFonts", gf.RefreshFonts)
    end
    if type(gf.MarkAllDirty) == "function" then
        return ProfiledGroupInvoke("MarkAllDirty:FONT", gf.MarkAllDirty, dirty)
    end
    if type(gf.RefreshVisuals) == "function" then
        if kindA then
            local did = ProfiledGroupInvoke("RefreshVisuals:FONT:" .. kindA, gf.RefreshVisuals, kindA, dirty)
            if kindB then did = ProfiledGroupInvoke("RefreshVisuals:FONT:" .. kindB, gf.RefreshVisuals, kindB, dirty) or did end
            return did
        end
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

local function RefreshGroupBarVisuals(mask, label, scope)
    local gf = MSUF and MSUF.GF
    if not gf then return end
    local dirty = mask or gf.DIRTY_VISUAL or 2
    label = label or "RefreshVisuals:BARS"
    local kindA, kindB = GroupKindsForScope(scope)
    if not kindA and not IsGlobalApplyScope(scope) then return false end
    if type(gf.RefreshVisuals) == "function" then
        if kindA then
            local did = ProfiledGroupInvoke(label .. ":" .. kindA, gf.RefreshVisuals, kindA, dirty)
            if kindB then did = ProfiledGroupInvoke(label .. ":" .. kindB, gf.RefreshVisuals, kindB, dirty) or did end
            return did
        end
        return ProfiledGroupInvoke(label, gf.RefreshVisuals, nil, dirty)
    end
    if type(gf.MarkAllDirty) == "function" then
        return ProfiledGroupInvoke("MarkAllDirty:" .. label, gf.MarkAllDirty, dirty)
    end
end

local function RefreshGroupColors(scope)
    local gf = MSUF and MSUF.GF
    if not gf then return end
    local kindA, kindB = GroupKindsForScope(scope)
    if not kindA and not IsGlobalApplyScope(scope) then return false end
    local dirty = gf.DIRTY_COLOR or 8
    if type(gf.RefreshColors) == "function" then
        if kindA then
            local did = ProfiledGroupInvoke("RefreshColors:" .. kindA, gf.RefreshColors, kindA)
            if kindB then did = ProfiledGroupInvoke("RefreshColors:" .. kindB, gf.RefreshColors, kindB) or did end
            return did
        end
        return ProfiledGroupInvoke("RefreshColors", gf.RefreshColors)
    end
    if kindA then return RefreshGroupBarVisuals(dirty, "RefreshVisuals:COLOR", scope) end
    return RefreshGroupVisuals(dirty, "RefreshVisuals:COLOR")
end

local function PushVisualUpdates()
    local api = MSUF and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then
        local ok = Apply.SafeInvoke(api.PushVisualUpdates)
        return ok == true
    end
    return false
end

local function ApplyFontRuntime(opt)
    local scope = opt and opt.fontScope
    local globalScope = IsGlobalApplyScope(scope)
    local kindA = GroupKindsForScope(scope)
    local unitScope = (not globalScope and not kindA) and NormalizeApplyScope(scope) or nil
    if globalScope then
        Apply.CallGlobal("MSUF_UpdateAllFonts_Immediate")
    elseif unitScope then
        Apply.CallGlobal("MSUF_UpdateAllFonts_Immediate", unitScope)
    end
    if not (opt and opt.colors) then
        if globalScope then
            Apply.CallGlobal("MSUF_RefreshAllIdentityColors")
            Apply.CallGlobal("MSUF_RefreshAllPowerTextColors")
        elseif unitScope then
            Apply.CallGlobal("MSUF_RefreshAllIdentityColors", unitScope)
            Apply.CallGlobal("MSUF_RefreshAllPowerTextColors", unitScope)
        end
    end
    RefreshGroupFonts(scope)
end

local function ApplyBarRuntime(opt)
    local scope = opt and opt.barsScope
    local globalScope = IsGlobalApplyScope(scope)
    local kindA = GroupKindsForScope(scope)
    local unitScope = (not globalScope and not kindA) and NormalizeApplyScope(scope) or nil
    local wantsTextureRuntime = opt and opt.bars == true
    local borderDirty = (MSUF and MSUF.GF and MSUF.GF.DIRTY_BORDER) or 0x10
    local didOutlineRefresh = false
    if wantsTextureRuntime and globalScope then
        Apply.CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
        Apply.CallGlobal("MSUF_UpdateAllBarTextures")
        Apply.CallGlobal("MSUF_UpdateAbsorbBarTextures")
        Apply.CallGlobal("MSUF_InvalidateAbsorbCache")
    elseif wantsTextureRuntime and unitScope then
        Apply.CallGlobal("MSUF_UpdateAllBarTextures_Immediate", unitScope)
        Apply.CallGlobal("MSUF_UpdateAllBarTextures", unitScope)
        Apply.CallGlobal("MSUF_UpdateAbsorbBarTextures", unitScope)
        Apply.CallGlobal("MSUF_InvalidateAbsorbCache", unitScope)
    elseif wantsTextureRuntime and kindA then
        Apply.CallGlobal("MSUF_InvalidateAbsorbCache", scope)
    end
    if opt and opt.barGradients == true then
        Apply.CallGlobal("MSUF_UpdateAllBarGradients", scope)
    end
    if opt and opt.barOutline == true then
        Apply.CallGlobal("MSUF_ApplyBarOutlineThickness_All", unitScope)
        RefreshGroupBarVisuals(borderDirty, "RefreshVisuals:BAR_OUTLINE", scope)
        Apply.CallGlobal("MSUF_ApplyRoundedUnitframes")
        didOutlineRefresh = true
    end
    if opt and opt.roundedBars == true then
        Apply.CallGlobal("MSUF_ApplyRoundedUnitframes")
        RefreshGroupBarVisuals(nil, "RefreshVisuals:ROUNDED_BARS", scope)
        Apply.CallGlobal("MSUF_GF_RefreshPreviewLayout", "party")
        Apply.CallGlobal("MSUF_GF_RefreshPreviewLayout", "raid")
        Apply.CallGlobal("MSUF_GF_RefreshPreviewLayout", "mythicraid")
        Apply.CallGlobal("MSUF_GF_RefreshPreviewBox")
    end
    if opt and opt.aggroBorder == true then
        Apply.CallGlobal("MSUF_UFCore_RefreshSettingsCache", opt.reason or "MSUF2_AGGRO_BORDER")
        if not didOutlineRefresh then Apply.CallGlobal("MSUF_ApplyBarOutlineThickness_All", unitScope) end
        Apply.CallGlobal("MSUF_AggroOutline_ApplyEventRegistration")
        RefreshGroupBarVisuals(borderDirty, "RefreshVisuals:AGGRO_BORDER", scope)
        didOutlineRefresh = true
    end
    if opt and opt.dispelPurgeBorder == true then
        Apply.CallGlobal("MSUF_UFCore_RefreshSettingsCache", opt.reason or "MSUF2_DISPEL_PURGE_BORDER")
        if not didOutlineRefresh then Apply.CallGlobal("MSUF_ApplyBarOutlineThickness_All", unitScope) end
        Apply.CallGlobal("MSUF_DispelOutline_ApplyEventRegistration")
        Apply.CallGlobal("MSUF_RefreshDispelOutlineStates", true)
        Apply.CallGlobal("MSUF_RefreshUnitDispelOverlays")
        RefreshGroupBarVisuals(borderDirty, "RefreshVisuals:DISPEL_PURGE_BORDER", scope)
        didOutlineRefresh = true
    end
    if opt and opt.bossTargetBorder == true then
        Apply.CallGlobal("MSUF_UFCore_RefreshSettingsCache", opt.reason or "MSUF2_BOSS_TARGET_BORDER")
        local UF = MSUF and MSUF.UF
        if UF and type(UF.RefreshBorders) == "function" then
            Apply.SafeInvoke(UF.RefreshBorders, "boss")
        else
            Apply.CallGlobal("MSUF_ApplyBarOutlineThickness_All", "boss")
        end
    end
    if wantsTextureRuntime or (opt and opt.barGradients == true) then
        RefreshGroupBarVisuals(nil, "RefreshVisuals:BARS", scope)
    end
end

local function ApplyCastbarRuntime(opt)
    if opt and opt.castbarTextures then
        Apply.CallGlobal("MSUF_UpdateCastbarTextures_Immediate")
        Apply.CallGlobal("MSUF_UpdateCastbarTextures")
    end
    Apply.CallGlobal("MSUF_UpdateBossCastbarPreview")
end

local function QueueCastbarSettingsChanged(source)
    pendingCastbarSettingsChanged = true
    Apply.pendingCastbarSettingsChanged = true
    source = tostring(source or "menu")
    if pendingCastbarSettingsSource == nil then
        pendingCastbarSettingsSource = source
    elseif pendingCastbarSettingsSource ~= source then
        pendingCastbarSettingsSource = "menu"
    end
    Apply.pendingCastbarSettingsSource = pendingCastbarSettingsSource
end

local function FlushCastbarSettingsChanged()
    if pendingCastbarSettingsChanged ~= true then return false end
    local source = pendingCastbarSettingsSource or "menu"
    pendingCastbarSettingsChanged = false
    pendingCastbarSettingsSource = nil
    Apply.pendingCastbarSettingsChanged = false
    Apply.pendingCastbarSettingsSource = nil
    return Apply.CallGlobal("MSUF_Castbars_OnSettingsChanged", source)
end

local function ApplyClassPowerProfileRuntime()
    if Apply.CallGlobal("MSUF_ClassPower_Apply", { full = true, cdm = true }) then
        return true
    end
    local did = false
    did = Apply.CallGlobal("MSUF_ClassPower_Refresh") or did
    did = Apply.CallGlobal("MSUF_ClassPower_RefreshTextures") or did
    did = Apply.CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true) or did
    return did
end

local function ApplyColorRuntime(opt)
    local scope = opt and opt.colorScope
    local globalScope = IsGlobalApplyScope(scope)
    local kindA = GroupKindsForScope(scope)
    local unitScope = (not globalScope and not kindA) and NormalizeApplyScope(scope) or nil
    local reason = (opt and opt.reason) or "MSUF2_COLORS"
    local notified = false
    if opt == nil or opt.notify ~= false then
        if globalScope then
            local called, result = Apply.CallGlobalResult("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason)
            notified = called and result ~= false or false
        elseif unitScope then
            local called, result = Apply.CallGlobalResult("MSUF_UFCore_NotifyConfigChanged", unitScope, true, true, reason)
            notified = called and result ~= false or false
        end
    end
    if globalScope then
        if not notified and not Apply.CallGlobal("MSUF_RefreshAllFrameColors") then
            Apply.CallGlobal("MSUF_RefreshAllIdentityColors")
            Apply.CallGlobal("MSUF_RefreshAllPowerTextColors")
        end
    elseif unitScope then
        if not notified and not Apply.CallGlobal("MSUF_RefreshAllFrameColors", unitScope) then
            Apply.CallGlobal("MSUF_RefreshAllIdentityColors", unitScope)
            Apply.CallGlobal("MSUF_RefreshAllPowerTextColors", unitScope)
        end
    end
    local textureScope = globalScope and nil or scope
    if not (opt and opt.bars) then Apply.CallGlobal("MSUF_UpdateAllBarTextures_Immediate", textureScope) end
    if globalScope then
        Apply.CallGlobal("MSUF_PrioRows_Reinit")
        if type(M.ApplyGameplay) == "function" then Apply.SafeInvoke(M.ApplyGameplay) end
    end
    RefreshGroupColors(scope)
    return notified or true
end

FlushApply = function()
    if InCombat() then
        return DeferApplyFlushUntilCombatEnds()
    end
    local flushStarted = perf.enabled == true and ProfileStart() or nil
    flushQueued = false
    Apply.flushQueued = false

    local wantPreview = pendingPreview
    pendingPreview = nil
    Apply.pendingPreview = nil

    local wantAlphaAll = pendingAlphaAll
    pendingAlphaAll = false
    Apply.pendingAlphaAll = false
    local wantAlphaUnits
    if not wantAlphaAll then
        for unit in pairs(pendingAlphaUnits) do
            if not wantAlphaUnits then wantAlphaUnits = {} end
            wantAlphaUnits[#wantAlphaUnits + 1] = unit
        end
    end
    WipeTable(pendingAlphaUnits)
    Apply.pendingAlpha = false

    local refreshSettingsReason
    for unit in pairs(pendingUnits) do
        if UnitRuntimeNeedsSettingsCache(pendingOpts[unit]) then
            refreshSettingsReason = pendingOpts[unit].reason or "MSUF2_UNIT_RUNTIME"
            break
        end
    end
    if not refreshSettingsReason and GeneralRuntimeNeedsSettingsCache(pendingGeneral) then
        refreshSettingsReason = pendingGeneral.reason or "MSUF2_GENERAL_RUNTIME"
    end
    if refreshSettingsReason then FlushScopedSettingsCache(refreshSettingsReason) end

    FlushCastbarSettingsChanged()

    for unit in pairs(pendingUnits) do
        local opt = pendingOpts[unit] or {}
        local notifyUnit = unit
        local applied = false

        if opt.notify ~= false then
            local called, result = Apply.CallGlobalResult("MSUF_UFCore_NotifyConfigChanged", notifyUnit, true, true, opt.reason or "MSUF2")
            applied = called and result ~= false or false
        end
        if opt.text then Apply.CallGlobal("MSUF_ForceTextLayoutForUnitKey", unit) end
        if opt.power or opt.detachedPowerBar then
            if opt.detachedPowerBar then
                ApplyDetachedPowerBarRuntime(unit, true)
            else
                ApplyPowerLayoutForUnit(unit)
            end
            if unit == "player" and not opt.classpowerApplied then
                Apply.CallGlobal("MSUF_ClassPower_Apply", { anchor = true, cdm = true, playerHP = true, syncNow = false })
            end
        end
        if opt.auras then applied = ApplyUnitAuras(unit, opt.reason) or applied end
        if not applied then applied = ApplyUnitFrame(unit) end
        if not applied then Apply.CallGlobal("MSUF_RefreshAllFrames", unit) end
        if opt.castbar then ApplyUnitCastbar(unit) end
    end
    WipeTable(pendingUnits)
    WipeTable(pendingOpts)

    FlushPendingClassPower()

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
        if WantsBarRuntime(opt) then ApplyBarRuntime(opt) end
        if opt.castbarTextures then ApplyCastbarRuntime(opt) end
        if opt.colors then ApplyColorRuntime(opt) end
        if applyAll and not applied then ApplyUnitFrame(nil) end
        if not applyAll then RefreshTargetedGeneral(opt.reason or "MSUF2_GENERAL", opt) end
    end

    FlushPendingGroups()
    FlushPendingAuras()

    if pendingCastbar then
        pendingCastbar = false
        Apply.pendingCastbar = false
        WipeTable(pendingCastbarUnits)
        ApplyAllCastbars()
    else
        for unit in pairs(pendingCastbarUnits) do
            pendingCastbarUnits[unit] = nil
            ApplyUnitCastbar(unit)
        end
    end
    if wantAlphaAll then
        Apply.CallGlobal("MSUF_RefreshAllUnitAlphas")
    elseif wantAlphaUnits then
        for i = 1, #wantAlphaUnits do
            Apply.CallGlobal("MSUF_RefreshAllUnitAlphas", wantAlphaUnits[i])
        end
    end
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
    if C_Timer and C_Timer.After then
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
            if opts.detachedPowerBar then
                o.power = true
                o.detachedPowerBar = true
            end
            if ClassPowerAlreadyApplied(opts) then o.classpowerApplied = true end
            if opts.notify == false then o.notify = false end
        if opts.fonts then
            if not pendingGeneral then pendingGeneral = {} end
            Apply.pendingGeneral = pendingGeneral
            if pendingGeneral.applyAll == nil then pendingGeneral.applyAll = false end
            pendingGeneral.reason = pendingGeneral.reason or reason or "MSUF2_FONTS"
            pendingGeneral.fonts = true
            pendingGeneral.text = true
            MergeScopeField(pendingGeneral, "fontScope", unit)
        end
        if opts.castbar then o.castbar = true end
        if opts.auras then o.auras = true end
        if opts.alpha then
            pendingAlphaUnits[unit] = true
            Apply.pendingAlpha = true
        end
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
        if opts.detachedPowerBar then
            pendingGeneral.power = true
            pendingGeneral.detachedPowerBar = true
            MergeScopeField(pendingGeneral, "powerScope", opts.powerScope or opts.scope or "player")
        end
        if opts.fonts then
            pendingGeneral.fonts = true
            pendingGeneral.text = true
            MergeScopeField(pendingGeneral, "fontScope", opts.fontScope)
        end
        if opts.bars or opts.barGradients
            or opts.barOutline or opts.roundedBars or opts.aggroBorder
            or opts.dispelPurgeBorder or opts.bossTargetBorder
        then
            if opts.bars or opts.barGradients then pendingGeneral.bars = true end
            MergeScopeField(pendingGeneral, "barsScope", opts.barsScope)
            if opts.barGradients then pendingGeneral.barGradients = true end
            if opts.barOutline then pendingGeneral.barOutline = true end
            if opts.roundedBars then pendingGeneral.roundedBars = true end
            if opts.aggroBorder then pendingGeneral.aggroBorder = true end
            if opts.dispelPurgeBorder then pendingGeneral.dispelPurgeBorder = true end
            if opts.bossTargetBorder then pendingGeneral.bossTargetBorder = true end
        end
        if opts.castbarTextures then pendingGeneral.castbarTextures = true end
        if opts.colors then
            pendingGeneral.colors = true
            MergeScopeField(pendingGeneral, "colorScope", opts.colorScope)
        end
        if opts.colorsPushed then pendingGeneral.colorsPushed = true end
        if WantsClassPower(opts) then
            pendingGeneral.classpower = true
            if WantsFullClassPower(opts) then pendingGeneral.classPowerFull = true end
            if opts.classPowerPlayerHP == true then pendingGeneral.classPowerPlayerHP = true end
            if opts.detachedPowerBar == true then pendingGeneral.detachedPowerBar = true end
            if opts.altMana == true then pendingGeneral.altMana = true end
            if ClassPowerAlreadyApplied(opts) then
                if pendingGeneral.classpowerApplied == nil then pendingGeneral.classpowerApplied = true end
            else
                pendingGeneral.classpowerApplied = false
            end
        end
        if opts.alpha then
            pendingGeneral.alpha = true
            pendingAlphaAll = true
            Apply.pendingAlphaAll = true
            Apply.pendingAlpha = true
        end
        if opts.castbar then pendingCastbar = true; Apply.pendingCastbar = true end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2_GENERAL"; Apply.pendingPreview = pendingPreview end
        if opts.visual ~= nil then pendingGeneral.visual = opts.visual and true or false end
        if opts.frames then pendingGeneral.frames = true end
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

function Apply.RequestColors(reason, scope)
    local globalScope = IsGlobalApplyScope(scope)
    local pushed = globalScope and PushVisualUpdates() or false
    return Apply.RequestGeneral(reason or "MSUF2_COLORS", {
        preview = true,
        applyAll = false,
        fonts = globalScope and not pushed,
        bars = globalScope and not pushed,
        colors = true,
        colorsPushed = pushed,
        colorScope = scope,
    })
end

function Apply.RequestFonts(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_FONTS", {
        preview = true,
        applyAll = false,
        fonts = true,
        fontScope = scope,
    })
end

function Apply.RequestBars(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_BARS", {
        preview = true,
        applyAll = false,
        bars = true,
        barsScope = scope,
    })
end

function Apply.RequestBarGradients(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_BAR_GRADIENTS", {
        preview = true,
        applyAll = false,
        notify = false,
        bars = true,
        barGradients = true,
        barsScope = scope,
    })
end

function Apply.RequestBarOutline(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_BAR_OUTLINE", {
        preview = true,
        applyAll = false,
        notify = false,
        barOutline = true,
        barsScope = scope,
    })
end

function Apply.RequestRoundedBars(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_ROUNDED_BARS", {
        preview = true,
        applyAll = false,
        notify = false,
        roundedBars = true,
        barsScope = scope,
    })
end

function Apply.RequestAggroBorder(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_AGGRO_BORDER", {
        preview = true,
        applyAll = false,
        notify = false,
        aggroBorder = true,
        barsScope = scope,
    })
end

function Apply.RequestDispelPurgeBorder(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_DISPEL_PURGE_BORDER", {
        preview = true,
        applyAll = false,
        notify = false,
        dispelPurgeBorder = true,
        barsScope = scope,
    })
end

function Apply.RequestBossTargetBorder(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_BOSS_TARGET_BORDER", {
        preview = true,
        applyAll = false,
        notify = false,
        bossTargetBorder = true,
        barsScope = scope or "boss",
    })
end

function Apply.RequestHighlightBorders(reason, scope)
    return Apply.RequestGeneral(reason or "MSUF2_HIGHLIGHT_BORDERS", {
        preview = true,
        applyAll = false,
        notify = false,
        aggroBorder = true,
        dispelPurgeBorder = true,
        bossTargetBorder = true,
        barsScope = scope,
    })
end

function Apply.RequestGroup(scope, mode, reason)
    QueueGroup(scope, mode or "visual", reason or "MSUF2_GROUP")
    return Apply.QueueFlush()
end

function Apply.RequestGroupDirtyMask(scope, dirtyMask, reason)
    QueueGroupDirtyMask(scope, dirtyMask, reason or "MSUF2_GROUP_DIRTY")
    return Apply.QueueFlush()
end

function Apply.RequestGroupReset(reason)
    QueueGroup("group", "reset", reason or "MSUF2_GROUP_RESET")
    return Apply.QueueFlush()
end

function Apply.RequestCastbarUnit(unit, reason, source)
    unit = NormalizeCastbarUnit(unit)
    if not unit then return false end
    QueueCastbarSettingsChanged(source or "menu")
    pendingCastbarUnits[unit] = true
    pendingPreview = reason or "MSUF2_CASTBAR_UNIT"
    Apply.pendingPreview = pendingPreview
    return Apply.QueueFlush()
end

function Apply.RequestCastbars(reason, source, unit)
    unit = NormalizeCastbarUnit(unit)
    if unit then
        return Apply.RequestCastbarUnit(unit, reason or "MSUF2_CASTBARS", source)
    end
    QueueCastbarSettingsChanged(source or "menu")
    return Apply.RequestGeneral(reason or "MSUF2_CASTBARS", {
        castbar = true,
        castbarTextures = true,
        preview = true,
        applyAll = false,
    })
end

function Apply.RequestAuras(scope, reason, opts)
    QueueAuraScope(scope or "shared", reason or "MSUF2_AURAS", opts and opts.visuals == true)
    return Apply.QueueFlush()
end

function Apply.RequestAuraFonts(scope, reason)
    QueueAuraScope(scope or "shared", reason or "MSUF2_AURA_VISUALS", true)
    return Apply.QueueFlush()
end

function Apply.RequestClassPower(reason, runtimeOpts, applyFlags)
    MergeClassPowerApplyOptions(EnsurePendingClassPowerOpts(), runtimeOpts)
    if type(applyFlags) == "table" then
        applyFlags.classpowerApplied = true
        if applyFlags.unit and type(Apply.RequestUnit) == "function" then
            return Apply.RequestUnit(applyFlags.unit, reason or "MSUF2_CLASSPOWER", applyFlags)
        end
        return Apply.RequestGeneral(reason or "MSUF2_CLASSPOWER", applyFlags)
    end
    pendingPreview = reason or "MSUF2_CLASSPOWER"
    Apply.pendingPreview = pendingPreview
    return Apply.QueueFlush()
end

function Apply.RequestDetachedPowerBar(reason, runtimeOpts, applyFlags)
    return Apply.RequestClassPower(reason or "MSUF2_DETACHED_POWER_BAR",
        runtimeOpts or { anchor = true, cdm = true, playerHP = true, syncNow = false },
        applyFlags or { preview = true, applyAll = false, unit = "player", power = true, detachedPowerBar = true, classpowerApplied = true })
end

function Apply.ApplyPowerLayout(unit, detachedPowerBar, refreshTextures)
    if detachedPowerBar == true then
        return ApplyDetachedPowerBarRuntime(unit or "player", refreshTextures ~= false)
    end
    return ApplyPowerLayoutForUnit(unit)
end

function Apply.ApplyProfileFanout(reason)
    Apply.CallGlobalList(PROFILE_APPLY_GLOBALS)
    ApplyClassPowerProfileRuntime()
    ApplyAllCastbars()
    Apply.CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "MSUF2_PROFILE_APPLY")
end

function Apply.ApplyRestoreFanout(reason)
    Apply.CallGlobalList(RESTORE_GLOBALS)
    ApplyAllCastbars()
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
