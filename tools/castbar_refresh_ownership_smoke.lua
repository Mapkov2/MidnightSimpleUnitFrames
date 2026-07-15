local function read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local text = file:read("*a")
    file:close()
    return text
end

local function contains(text, needle)
    return text:find(needle, 1, true) ~= nil
end

local root = "MidnightSimpleUnitFrames/"
local core = read(root .. "Castbars/MSUF_Castbars_Core.lua")
local visuals = read(root .. "Castbars/MSUF_CastbarVisuals.lua")
local manager = read(root .. "Castbars/MSUF_Castbars.lua")
local runtime = read(root .. "Castbars/MSUF_CastbarRuntime.lua")
local driver = read(root .. "Castbars/MSUF_CastbarDriver.lua")
local boss = read(root .. "Castbars/MSUF_BossCastbars.lua")
local player = read(root .. "Castbars/MSUF_PlayerCastbarRuntime.lua")
local anchors = read(root .. "Castbars/MSUF_CastbarAnchors.lua")
local style = read(root .. "Castbars/MSUF_CastbarStyle.lua")
local utils = read(root .. "Castbars/MSUF_CastbarUtils.lua")
local fonts = read(root .. "Runtime/MSUF_FontRuntime.lua")
local interruptReady = read(root .. "Castbars/MSUF_InterruptReady.lua")
local focusKickIcon = read(root .. "Castbars/MSUF_FocusKickIcon.lua")
local ufCore = read(root .. "UnitFrames/Engine/MSUF_UF_Core.lua")

local function ownerCountFor(needle, sources)
    local count = 0
    for _, text in ipairs(sources) do
        local start = 1
        while true do
            local found = text:find(needle, start, true)
            if not found then break end
            count = count + 1
            start = found + #needle
        end
    end
    return count
end

local ownerNeedle = 'ExportPublic("MSUF_UpdateCastbarVisuals",'
local ownerCount = 0
for _, text in ipairs({ core, visuals, manager, fonts }) do
    local start = 1
    while true do
        local found = text:find(ownerNeedle, start, true)
        if not found then break end
        ownerCount = ownerCount + 1
        start = found + #ownerNeedle
    end
end

assert(ownerCount == 1, "castbar visual refresh must have exactly one public owner")
assert(contains(core, 'ExportPublic("MSUF_UpdateCastbarVisuals", UpdateCastbarVisuals)'))
assert(contains(core, 'ExportPublic("MSUF_UpdateCastbarVisuals_Immediate", UpdateCastbarVisuals)'))
assert(not contains(visuals, "previousUpdateCastbarVisuals"))
assert(not contains(manager, "InstallStyleRevisionHook"))
assert(not contains(manager, "InstallCastTimeRevisionHook"))
assert(not contains(fonts, 'ExportPublic("MSUF_UpdateCastbarVisuals",'))
assert(contains(core, 'ExportPublic("MSUF_UpdateCastbarTextures", UpdateCastbarTextures)'))
assert(contains(core, 'ExportPublic("MSUF_UpdateCastbarTextures_Immediate", UpdateCastbarTextures)'))
assert(not contains(fonts, 'ExportPublic("MSUF_UpdateCastbarTextures",'))
assert(contains(core, 'ExportPublic("MSUF_ApplyAllCastbarsAndSync", ApplyAllCastbarsAndSync)'))
assert(ownerCountFor('ExportPublic("MSUF_UpdateCastbarFillDirection",', { core, style }) == 1,
    "castbar fill direction must have exactly one public owner")
assert(contains(style, 'ExportPublic("MSUF_UpdateCastbarFillDirection",'))
assert(ownerCountFor('ExportPublic("MSUF_GetCastbarReverseFillForFrame",', { core, utils }) == 1,
    "castbar reverse-fill resolution must have exactly one public owner")
assert(contains(utils, 'ExportPublic("MSUF_GetCastbarReverseFillForFrame",'))

local coldStart = assert(core:find("local function ApplyCastbarVisualFrameCold", 1, true))
local coldEnd = assert(core:find("local function MaxBossFrames", coldStart, true))
local coldBody = core:sub(coldStart, coldEnd - 1)
local _, coldRefreshCount = coldBody:gsub("MSUF_RefreshCastbarFrame%(", "")
assert(coldRefreshCount == 1, "each Core frame pass must invoke exactly one Visuals follower")
assert(contains(coldBody, "ApplyCastbarBaseGeometry(frame, general, forcedUnit)"))
assert(contains(coldBody, "frame._msufCastbarColdGlobalRev == globalRevision"),
    "cold visual pass must skip an already-applied revision and geometry")
assert(contains(coldBody, "MSUF_RefreshCastbarFrame(frame, forcedUnit, general)"))
assert(contains(coldBody, "ApplyCastbarSparkVisual(frame, general)"))
assert(not contains(core, "MSUF_KickReady_ApplyLayout"), "Core must not duplicate Visuals followers")
assert(not contains(core, "MSUF_ApplyPlayerCastbarIconLayout"), "Core must not own configurable icon layout")
assert(not contains(core, "BuildCastbarVisualContext"), "obsolete overlapping detail context should not survive")

local refreshStart = assert(visuals:find("local function RefreshCastbarFrame", 1, true))
local refreshBody = visuals:sub(refreshStart)
local _, detailCount = refreshBody:gsub("ApplyCastbarDetailLayout%(", "")
assert(detailCount == 1, "each Visuals frame refresh must invoke detail layout exactly once")
assert(contains(refreshBody, "ApplyCastbarDetailLayout(frame, forcedUnit, general)"))

local castStart = assert(driver:find("function frame:Cast(state)", 1, true))
local interruptStart = assert(driver:find("function frame:SetInterrupted()", castStart, true))
local castBody = driver:sub(castStart, interruptStart - 1)
assert(not contains(castBody, "self.timer = true"), "ordinary casts must not arm interrupt feedback")
assert(not contains(castBody, "C_Timer.After(feedbackDuration"), "ordinary casts must not schedule feedback timers")
assert(not contains(driver, "_msufInterruptToken"), "obsolete interrupt timer token should not survive")
assert(contains(driver, "C_Timer.After(0, self._msufInactiveRecheckCB)"))
assert(contains(driver, "C_Timer.After(feedbackDuration, self._msufInterruptHideCB)"))
assert(contains(player, "C_Timer.After(0, frame._msufSoftResyncCB)"))
assert(contains(player, "C_Timer.After(duration, frame._msufPlayerInterruptHideCB)"))
assert(not contains(player, "HideIfNoLongerCasting({"), "player interrupt callback must not allocate an owner table")

assert(contains(interruptReady, "EvaluateColorValueFromBoolean"),
    "secret interrupt colors must use the allocation-free scalar evaluator")
assert(contains(interruptReady, 'ExportPublic("MSUF_KickReady_EvaluateRGBA", KickReady_EvaluateRGBA)'))
assert(contains(focusKickIcon, "_G.MSUF_KickReady_EvaluateRGBA("))
assert(not contains(focusKickIcon, "EvaluateColorFromBoolean("),
    "focus kick icon must not allocate transient ColorMixin results")
assert(not contains(focusKickIcon, 'iconFrame:SetScript("OnUpdate"'),
    "live focus-kick icon must not own a Lua OnUpdate")
assert(not contains(focusKickIcon, "MSUF_timeAccum"),
    "obsolete focus-kick polling accumulator survived")
assert(contains(focusKickIcon, "runtime:BindNativeTimeText(iconFrame, durationObj, format)"),
    "focus-kick icon must use the shared native duration binder")
assert(contains(focusKickIcon, "source._msufForceLuaTimeTextFollower = true"),
    "focus-kick degraded path must attach to the existing castbar manager")
assert(contains(manager, 'ExportPublic("MSUF_Castbar_SyncTimeTextFollower", SyncTimeTextFollower)'),
    "castbar manager must own detached fallback text propagation")
assert(contains(driver, '"UNIT_HEALTH",') and contains(driver, '"UNIT_CONNECTION",'),
    "target/focus active lifecycle event set is incomplete")
assert(contains(driver, 'ExportPublic("MSUF_Castbar_SetLifecycleActive", SetCastLifecycleActive)'),
    "castbar lifecycle owner must be shared with Runtime stop paths")
assert(contains(driver, "local function ToKnownPlainBool(value)"),
    "castbar lifecycle decisions must be secret-safe")
assert(contains(runtime, "frame._msufCastLifecycleOwned ~= true"),
    "unit failsafe must remain limited to missing/degraded lifecycle ownership")
assert(contains(boss, "frame._msufCastLifecycleOwned = true"),
    "boss encounter lifecycle must suppress redundant unit polling")
assert(contains(driver, "UF.SetHealthLifecycleSink(frame.unit, SharedUFHealthLifecycleSink, frame)"),
    "target/focus must borrow the existing UF health route first")
assert(contains(driver, 'frame._msufCastLifecycleMode = "UF"'),
    "driver must distinguish the zero-registration UF lifecycle fastpath")
local sinkAttach = assert(driver:find("UF.SetHealthLifecycleSink", 1, true))
local nativeRegister = assert(driver:find("pcall(frame.RegisterUnitEvent", sinkAttach, true))
assert(sinkAttach < nativeRegister,
    "native UNIT_HEALTH fallback was attempted before the UF lifecycle sink")
assert(contains(ufCore, "local function HealthLifecycleSinkRoute"),
    "UF Core must provide one shared lifecycle route wrapper")
assert(contains(ufCore, "function UF.SetHealthLifecycleSink(unit, sink, owner)"),
    "UF Core lifecycle sink API missing")
assert(contains(ufCore, "function UF.ClearHealthLifecycleSink(frame, owner)"),
    "UF Core lifecycle sink detach API missing")
assert(contains(ufCore, 'sink(owner, frame, "MSUF_UF_LIFECYCLE_DETACH", frame.unit)'),
    "UF route loss must promote active castbars to the native fallback")

assert(contains(anchors, 'ExportPublic("MSUF_ReanchorPlayerCastBarBase", ReanchorPlayerCastBarBase)'))
assert(contains(anchors, 'ExportPublic("MSUF_ReanchorTargetCastBarBase", ReanchorTargetCastBarBase)'))
assert(contains(anchors, 'ExportPublic("MSUF_ReanchorFocusCastBarBase", ReanchorFocusCastBarBase)'))
assert(contains(core, "_G.MSUF_ReanchorPlayerCastBarBase()"))
assert(contains(core, "_G.MSUF_ReanchorTargetCastBarBase()"))
assert(contains(core, "_G.MSUF_ReanchorFocusCastBarBase()"))
assert(not contains(visuals, 'ExportPublic("MSUF_ReanchorPlayerCastBar",'))

local sizeStart = assert(anchors:find("local function ApplyPlayerCastbarSizeAndLayout", 1, true))
local sizeEnd = assert(anchors:find("ApplyCastbarEffectiveSizeUnit = function", sizeStart, true))
local sizeBody = anchors:sub(sizeStart, sizeEnd - 1)
assert(not contains(sizeBody, "MSUF_ApplyPlayerCastbarIconLayout"))
assert(not contains(sizeBody, "CreateTexture"), "geometry stage must not create spark textures")

print("castbar refresh ownership smoke: ok")
