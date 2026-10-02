-- castbar_hotpath_smoke.lua <repoRoot>
--
-- Classic port of the Retail repository's .github/scripts/tests/castbar_hotpath_smoke.lua
-- (trace-driven castbar hotpath ownership). The behavioural sections run
-- unchanged against this tree: shared ColorObjects, stable outline colours,
-- native-text transition cleanup, cooldown snapshot sharing, the O(1) manager
-- refresh and the channel unit fastpath. Of Retail's source pins only the
-- castbar runtime ones are kept; the defaults, menu and preview pins belong to
-- other areas of this tree (State/Defaults, Menu2 pages and previews).
-- Instruction and allocation budgets live in castbar_hotpath_budget_smoke.lua.
--
-- Plain Lua 5.1, repo root as arg 1.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function LoadAddonFile(relativePath, namespace)
    local chunk, loadError = loadfile(root .. "/MidnightSimpleUnitFrames/" .. relativePath)
    Check(chunk ~= nil, loadError)
    chunk("MidnightSimpleUnitFrames", namespace)
end

local function NewNamespace()
    local namespace = {}
    function namespace.ExportPublic(name, value)
        _G[name] = value
        return value
    end
    return namespace
end

-- Global castbar colors share exactly one ColorObject per semantic color.
do
    local createColorCalls = 0
    _G.CreateColor = function(red, green, blue, alpha)
        createColorCalls = createColorCalls + 1
        return { id = createColorCalls, red = red, green = green, blue = blue, alpha = alpha }
    end
    _G.C_CurveUtil = {
        EvaluateColorFromBoolean = function(value, falseColor, trueColor)
            return value == true and trueColor or falseColor
        end,
    }
    _G.C_Timer = { After = function() end }
    _G.issecretvalue = function() return false end
    _G.MSUF_DB = { general = {} }
    _G.MSUF_SetStatusBarColorIfChanged = nil

    LoadAddonFile("Castbars/MSUF_CastbarUtils.lua", NewNamespace())
    local applyTint = _G.MSUF_Castbar_ApplyNonInterruptibleTint
    Check(type(applyTint) == "function", "non-interruptible tint export missing")

    local function NewTintFrame()
        local texture = {}
        function texture:SetVertexColorFromBoolean(value, falseColor, trueColor)
            self.value, self.falseColor, self.trueColor = value, falseColor, trueColor
        end
        local statusBar = { texture = texture }
        function statusBar:GetStatusBarTexture() return self.texture end
        function statusBar:SetStatusBarColor(red, green, blue, alpha)
            self.red, self.green, self.blue, self.alpha = red, green, blue, alpha
        end
        return { statusBar = statusBar }
    end

    local function Tint(frame, unavailable)
        return applyTint(
            frame,
            false,
            0.1, 0.2, 0.3, 1,
            0.4, 0.8, 0.9, 1,
            false,
            1, 0.5, 0.1, 1,
            false,
            unavailable == true
        )
    end

    local target = NewTintFrame()
    local focus = NewTintFrame()
    Check(Tint(target, false) == true, "target boolean tint failed")
    Equal(createColorCalls, 2, "global cold ColorObject count")
    Check(Tint(focus, false) == true, "focus boolean tint failed")
    Equal(createColorCalls, 2, "focus recreated global castbar colors")
    Check(target.statusBar.texture.falseColor == focus.statusBar.texture.falseColor
        and target.statusBar.texture.trueColor == focus.statusBar.texture.trueColor,
        "frames did not share global castbar ColorObjects")
    Check(Tint(target, true) == true, "unavailable tint failed")
    Equal(createColorCalls, 3, "unavailable color was not created exactly once")
    Tint(focus, true)
    Equal(createColorCalls, 3, "unchanged unavailable color was recreated")
end

-- Rebuilding a BackdropTemplate resets its border pieces to white. The castbar
-- outline must therefore reapply its cached configured color when pixel scale
-- changes the resolved edge size.
do
    local scale = 1
    local host
    _G.MSUF_DB = {
        general = {
            castbarOutlineThickness = 1,
        },
    }
    _G.PixelUtil = {
        GetNearestPixelSize = function(_, effectiveScale)
            return 1 / effectiveScale
        end,
    }
    _G.CreateFrame = function()
        host = {
            shown = false,
            SetBackdrop = function(self)
                self.borderR, self.borderG, self.borderB, self.borderA = 1, 1, 1, 1
            end,
            SetBackdropColor = function() end,
            SetBackdropBorderColor = function(self, r, g, b, a)
                self.borderR, self.borderG, self.borderB, self.borderA = r, g, b, a
            end,
            EnableMouse = function() end,
            ClearAllPoints = function() end,
            SetAllPoints = function() end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
        }
        return host
    end

    local frame = {
        GetEffectiveScale = function() return scale end,
        GetFrameLevel = function() return 1 end,
    }
    local namespace = NewNamespace()
    LoadAddonFile("Castbars/MSUF_CastbarStyle.lua", namespace)
    namespace.MSUF_CastbarStyle:ApplyCastbarOutline(frame, false)
    Equal(host.borderR, 0, "default castbar border red was not black")
    Equal(host.borderG, 0, "default castbar border green was not black")
    Equal(host.borderB, 0, "default castbar border blue was not black")
    Equal(host.borderA, 1, "default castbar border alpha was not opaque")

    local general = _G.MSUF_DB.general
    general.castbarBorderR = 0.12
    general.castbarBorderG = 0.34
    general.castbarBorderB = 0.56
    general.castbarBorderA = 0.78
    namespace.MSUF_CastbarStyle:ApplyCastbarOutline(frame, false)
    Equal(host.borderR, 0.12, "initial castbar border red was not applied")
    Equal(host.borderG, 0.34, "initial castbar border green was not applied")
    Equal(host.borderB, 0.56, "initial castbar border blue was not applied")
    Equal(host.borderA, 0.78, "initial castbar border alpha was not applied")

    scale = 2
    namespace.MSUF_CastbarStyle:ApplyCastbarOutline(frame, false)
    Equal(host.borderR, 0.12, "castbar border red reset after backdrop rebuild")
    Equal(host.borderG, 0.34, "castbar border green reset after backdrop rebuild")
    Equal(host.borderB, 0.56, "castbar border blue reset after backdrop rebuild")
    Equal(host.borderA, 0.78, "castbar border alpha reset after backdrop rebuild")
end

-- Native duration-text cleanup is a transition: steady disabled calls do no C work,
-- while a partially configured binding still receives a forced disable.
do
    _G.Enum = {
        StatusBarInterpolation = { Immediate = 0 },
        StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
        DurationTextBindingProperty = {
            RemainingDuration = 1,
            ElapsedDuration = 2,
            TotalDuration = 3,
        },
        NumericRuleFormatRounding = { Nearest = 1 },
    }
    _G.C_StringUtil = {
        CreateNumericRuleFormatter = function()
            return { SetBreakpoints = function() end }
        end,
    }
    _G.C_Timer = {
        NewTimer = function() return { Cancel = function() end } end,
    }
    _G.GetTime = function() return 10 end
    _G.GetTimePreciseSec = nil
    _G.issecretvalue = function() return false end
    _G.MSUF_CastbarRuntime = nil

    local createdBinding
    _G.C_DurationUtil = {
        CreateDurationTextBinding = function() return createdBinding end,
    }
    local namespace = NewNamespace()
    LoadAddonFile("Castbars/MSUF_CastbarRuntime.lua", namespace)
    local runtime = namespace.MSUF_CastbarRuntime
    Check(type(runtime) == "table", "castbar runtime missing")

    local disableCalls = 0
    local frame = {
        timeText = { _msufLastText = "native" },
        _msufNativeTimeBound = true,
        _msufDurationTextBinding = {
            Disable = function() disableCalls = disableCalls + 1 end,
        },
    }
    runtime:DisableNativeTimeText(frame)
    runtime:DisableNativeTimeText(frame)
    Equal(disableCalls, 1, "steady disabled binding repeated native Disable")
    Check(frame._msufNativeTimeBound ~= true, "successful disable retained bound flag")
    Equal(frame.timeText._msufLastText, nil, "native disable did not invalidate Lua text cache")

    -- 12.1 contract model: binding methods cannot reject; the failure surface
    -- is a client whose binding lacks a required method (the 120007 surface).
    createdBinding = {
        -- No SetFontString: PrepareNativeTimeText must bail via its type guard.
        Disable = function() end,
    }
    local partialFrame = { timeText = {} }
    Check(runtime:BindNativeTimeText(partialFrame, {}, "CURRENT") == false,
        "missing-method binding reported success")
    Check(partialFrame._msufNativeTextUnsafe == true,
        "missing-method binding did not mark native text unsafe")
    Check(partialFrame._msufNativeTimeBound ~= true, "missing-method binding marked binding live")

    local secretDuration = { secret = true }
    local nativeDuration
    local secretBinding = {
        SetFontString = function() end,
        SetUpdateInterval = function() end,
        SetTextFormat = function() end,
        SetDuration = function(_, duration) nativeDuration = duration end,
        SetEnabled = function() end,
        UpdateFontString = function() end,
    }
    _G.C_DurationUtil.CreateDurationTextBinding = function() return secretBinding end
    local secretFrame = {
        unit = "target",
        timeText = { SetText = function() end },
        MSUF_durationObj = secretDuration,
        MSUF_timerDriven = true,
        MSUF_castActive = true,
        _msufDurationSnapshotUnsafe = true,
        _msufCastLifecycleOwned = true,
    }
    local secretMask = runtime:PrepareWork(secretFrame)
    Equal(secretMask, runtime.WorkMask.UNIT_FAILSAFE,
        "native secret duration retained Lua visual polling")
    Check(secretFrame._msufNativeTimeBound == true, "secret duration did not bind native text")
    Check(nativeDuration == secretDuration, "native binding did not receive secret duration object")
    Check(secretFrame._msufCastbarGlowTick == nil, "unreadable secret duration retained glow polling")

    _G.C_DurationUtil.CreateDurationTextBinding = function()
        return {
            SetFontString = function() end,
            SetUpdateInterval = function() end,
            SetTextFormat = function() end,
            -- No SetDuration: models a binding that cannot take a duration on
            -- this client; ApplyNativeTimeText must keep the Lua fallback.
            SetEnabled = function() end,
        }
    end
    local fallbackFrame = {
        unit = "target",
        timeText = { SetText = function() end },
        MSUF_durationObj = secretDuration,
        MSUF_timerDriven = true,
        MSUF_castActive = true,
        _msufDurationSnapshotUnsafe = true,
        _msufCastLifecycleOwned = true,
    }
    local fallbackMask = runtime:PrepareWork(fallbackFrame)
    Equal(fallbackMask, runtime.WorkMask.TIME_TEXT + runtime.WorkMask.GLOW
        + runtime.WorkMask.DURATION_FALLBACK + runtime.WorkMask.UNIT_FAILSAFE,
        "failed native secret binding did not retain the proven Lua fallback")
end

-- GetSpellCooldownDuration returns a userdata object. Reuse it inside one frame,
-- but invalidate before every relevant cooldown/spec/world refresh.
do
    local now = 100
    local cooldownAPICalls = 0
    local timers = {}
    local interruptEventFrame

    _G.GetTime = function() return now end
    _G.GetTimePreciseSec = nil
    _G.UnitClass = function() return "Mage", "MAGE" end
    _G.GetSpecialization = function() return 1 end
    _G.GetSpecializationInfo = function() return 62 end
    _G.Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 77 } }
    _G.C_Spell = {
        GetSpellCooldownDuration = function(spellID)
            cooldownAPICalls = cooldownAPICalls + 1
            return {
                spellID = spellID,
                GetRemainingDuration = function() return 8 end,
                IsZero = function() return false end,
            }
        end,
    }
    _G.C_Timer = {
        After = function(delay, callback)
            timers[#timers + 1] = { delay = delay, callback = callback }
        end,
    }
    _G.C_CurveUtil = nil
    _G.issecretvalue = function() return false end
    _G.MSUF_DB = { general = { kickReadyShowTarget = true } }
    _G.CreateFrame = function()
        local frame = { scripts = {}, events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(script, callback) self.scripts[script] = callback end
        interruptEventFrame = frame
        return frame
    end

    local interruptNamespace = NewNamespace()
    -- Castbars/MSUF_CastbarUtils.lua loads first in every TOC (the interrupt-ready unit rule).
    LoadAddonFile("Castbars/MSUF_CastbarUtils.lua", interruptNamespace)
    LoadAddonFile("Castbars/MSUF_InterruptReady.lua", interruptNamespace)
    Equal(_G.MSUF_KickReady_Init(), 2139, "mage interrupt spell resolution")
    Check(_G.MSUF_KickReady_IsReady() == false, "cooldown unexpectedly ready")
    Check(_G.MSUF_KickReady_IsReady() == false, "cached cooldown unexpectedly ready")
    Equal(cooldownAPICalls, 1, "same-frame readiness calls allocated multiple DurationObjects")

    now = 101
    _G.MSUF_KickReady_GetReadyBoolForTint()
    Equal(cooldownAPICalls, 2, "new frame reused stale cooldown snapshot")

    local onEvent = interruptEventFrame and interruptEventFrame.scripts.OnEvent
    Check(type(onEvent) == "function", "interrupt event handler missing")
    onEvent(interruptEventFrame, "SPELL_UPDATE_COOLDOWN", 2139, 2139, nil, 0)
    Equal(cooldownAPICalls, 3, "relevant cooldown event did not invalidate snapshot")
    _G.MSUF_KickReady_IsReady()
    Equal(cooldownAPICalls, 3, "event refresh object was not shared with same-frame consumers")

    onEvent(interruptEventFrame, "SPELL_UPDATE_COOLDOWN", 999999, 999999, nil, 0)
    Equal(cooldownAPICalls, 3, "unrelated cooldown event queried interrupt duration")
    now = 102
    onEvent(interruptEventFrame, "SPELL_UPDATE_COOLDOWN", 2139, 2139, nil, 0)
    Equal(cooldownAPICalls, 4, "next relevant cooldown event reused stale snapshot")

    _G.MSUF_DB.general.kickReadyShowTarget = false
    _G.MSUF_KickReady_RefreshAll()
    Check(next(interruptEventFrame.events) == nil, "disabled interrupt-ready retained lifecycle events")
    Check(_G.MSUF_KickReady_GetSpellID() == nil, "disabled interrupt-ready resolved a spell")
end

-- Low-frequency register/reclassify initializes only the affected frame. High-
-- frequency initialization stays caller-owned; a complete low-bucket pass is
-- reserved for an actual frame-driver <-> ticker topology hand-off.
-- Player channel hard-stop reads the stored active token without BuildState.
do
    local now = 0
    local unitExistsCalls = {}
    local channelCalls = {}
    local channelState = { player = "Channel", vehicle = nil }
    local vehicleUI = false
    local tickerCallbacks = {}

    _G.GetTimePreciseSec = function() return now end
    _G.GetTime = function() return now end
    _G.UnitExists = function(unit)
        unitExistsCalls[unit] = (unitExistsCalls[unit] or 0) + 1
        return true
    end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitHasVehicleUI = function() return vehicleUI end
    _G.UnitChannelInfo = function(unit)
        channelCalls[#channelCalls + 1] = unit
        return channelState[unit]
    end
    _G.GetCVar = function() return "400" end
    _G.C_Timer = {
        After = function() end,
        NewTicker = function(interval, callback)
            local ticker = { interval = interval, callback = callback, cancelled = false }
            function ticker:Cancel() self.cancelled = true end
            tickerCallbacks[#tickerCallbacks + 1] = ticker
            return ticker
        end,
    }

    local FrameMethods = {}
    function FrameMethods:SetScript(script, callback) self.scripts[script] = callback end
    function FrameMethods:HookScript(script, callback) self.hooks[script] = callback end
    function FrameMethods:Show() self.shown = true end
    function FrameMethods:Hide()
        local wasShown = self.shown ~= false
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        if wasShown and self.hooks.OnHide then self.hooks.OnHide(self) end
    end
    function FrameMethods:IsShown() return self.shown ~= false end

    local function NewFrame()
        return setmetatable({ scripts = {}, hooks = {}, shown = true }, { __index = FrameMethods })
    end

    _G.MSUF_CastbarManager = nil
    _G.CreateFrame = function() return NewFrame() end
    local managerRuntime = {
        WorkMask = { UNIT_FAILSAFE = 32 },
    }
    function managerRuntime:PrepareWork(frame)
        frame._msufCastbarWorkMask = frame.testWorkMask
        return frame.testWorkMask
    end
    function managerRuntime:CancelNativeCompletion() end
    function managerRuntime:DeactivateNative() end
    function managerRuntime:ArmNativeCompletion() return false end
    _G.MSUF_CastbarRuntime = managerRuntime
    _G.MSUF_ApplyCastbarGlowFade = nil
    _G.MSUF_ResetCastbarGlowFade = nil
    _G.MSUF_RefreshCastbarStyleCache = nil

    LoadAddonFile("Castbars/MSUF_Castbars.lua", NewNamespace())
    local register = _G.MSUF_RegisterCastbar
    local unregister = _G.MSUF_UnregisterCastbar
    Check(type(register) == "function" and type(unregister) == "function", "castbar manager exports missing")

    local function NewManagedFrame(unit, workMask, empower)
        local frame = NewFrame()
        frame.unit = unit
        frame.statusBar = {}
        frame.timeText = {
            SetFormattedText = function(self) self.formatted = (self.formatted or 0) + 1 end,
            SetText = function() end,
        }
        frame.MSUF_castActive = true
        frame.MSUF_timerDriven = true
        frame._msufCastTimeEnabled = true
        frame._msufPlainEndTime = now + 5
        frame.testWorkMask = workMask
        frame.isEmpower = empower == true
        return frame
    end

    local target = NewManagedFrame("target", 1, false)
    register(target)
    Equal(unitExistsCalls.target, 1, "initial low topology did not initialize target once")

    now = 0.30
    local focus = NewManagedFrame("focus", 1, false)
    register(focus)
    Equal(unitExistsCalls.target, 1, "focus registration synchronously rescanned target")
    Equal(unitExistsCalls.focus, 1, "focus registration was not initialized immediately")

    now = 0.60
    focus._msufPlainEndTime = now + 5
    register(focus)
    Equal(unitExistsCalls.target, 1, "focus re-registration synchronously rescanned target")
    Equal(unitExistsCalls.focus, 2, "focus re-registration did not refresh only focus")

    now = 0.90
    unregister(focus)
    Equal(unitExistsCalls.target, 1, "steady low unregister synchronously rescanned target")

    now = 1.20
    local boss = NewManagedFrame("boss1", 8, true)
    register(boss)
    Equal(unitExistsCalls.target, 1, "low-to-frame topology transition rescanned low sibling early")
    Equal(unitExistsCalls.boss1, nil, "manager duplicated caller-owned high-frequency initialization")

    now = 1.50
    unregister(boss)
    Equal(unitExistsCalls.target, 2, "frame-to-low-ticker topology hand-off skipped coherent low scan")

    local effectiveUnitCalls = 0
    _G.MSUF_PlayerCastbar_GetEffectiveUnit = function()
        effectiveUnitCalls = effectiveUnitCalls + 1
        error("hard-stop rebuilt cast state")
    end
    local player = NewManagedFrame("player", 4, false)
    player.timeText = nil
    player._msufCastTimeEnabled = false
    player.MSUF_isChanneled = true
    player._msufActiveCastUnit = "player"
    now = 1.80
    register(player)
    Equal(effectiveUnitCalls, 0, "player channel hard-stop called GetEffectiveUnit/BuildState")
    Equal(channelCalls[#channelCalls], "player", "stored player channel token was not used")

    channelCalls = {}
    channelState.player = nil
    channelState.vehicle = "Vehicle Channel"
    vehicleUI = true
    player._msufActiveCastUnit = "player"
    player._msufHardStopNext = nil
    now = 2.10
    register(player)
    Equal(#channelCalls, 2, "vehicle transition did not probe exactly primary plus fallback")
    Equal(channelCalls[1], "player", "vehicle transition skipped stored primary token")
    Equal(channelCalls[2], "vehicle", "vehicle transition did not probe vehicle fallback")
    Equal(player._msufActiveCastUnit, "vehicle", "vehicle fallback did not stabilize active token")

    channelCalls = {}
    player._msufHardStopNext = nil
    now = 2.40
    register(player)
    Equal(#channelCalls, 1, "steady vehicle channel performed fallback work")
    Equal(channelCalls[1], "vehicle", "steady vehicle channel ignored stored active token")
    Equal(effectiveUnitCalls, 0, "vehicle channel hard-stop called GetEffectiveUnit/BuildState")

    unregister(player)
    unregister(target)
end

local function ReadSource(relativePath)
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/" .. relativePath, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return source
end

local castbarVisualSource = ReadSource("Castbars/MSUF_CastbarVisuals.lua")
local castbarDriverSource = ReadSource("Castbars/MSUF_CastbarDriver.lua")
local immediateRefresh = assert(castbarDriverSource:find("local function RefreshTargetFocusChanged", 1, true))
local identityInvalidation = assert(castbarDriverSource:find("InvalidateTargetFocusState(frame)", immediateRefresh, true))
local immediateBuild = assert(castbarDriverSource:find("local state = BuildState(frame)", immediateRefresh, true))
Check(identityInvalidation < immediateBuild,
    "target/focus identity did not retire the old cast before its synchronous refresh")
Check(not castbarDriverSource:find("ScheduleTargetFocusChanged", 1, true)
    and not castbarDriverSource:find("_msufTargetFocusRefreshQueued", 1, true),
    "target/focus identity retained zero-delay scheduler overhead")
Check(castbarDriverSource:find("if self.PrepareForCast then self:PrepareForCast() end", 1, true),
    "active pool casts do not validate stale geometry/font state before show")
Check(castbarVisualSource:find('DetailNum(g, prefix, "IconZoom", "castbarIconZoom", 100)', 1, true)
    and castbarVisualSource:find("texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)", 1, true),
    "live Castbar Icon Zoom is not resolved per scope")
-- The player bar resolves castbarPlayerIconZoom through the Visuals prefix.
Check(castbarVisualSource:find('if unit == "player" then return "castbarPlayer" end', 1, true),
    "player Castbar icon layout omits its zoom scope")
Check(castbarVisualSource:find('DetailNum(g, prefix, "IconBorderThickness", nil, 0)', 1, true)
    and castbarVisualSource:find('DetailString(g, prefix, "IconBorderStyle", nil, "NONE")', 1, true)
    and castbarVisualSource:find("thickness <= 0", 1, true)
    and castbarVisualSource:find("g.castbarBorderR", 1, true),
    "live Castbar icon border runtime, thickness, or shared border color was removed")

print("PASS castbar hotpaths: shared ColorObjects, stable outline colors, native-text transition cleanup, cooldown snapshot sharing, O(1) manager refresh, channel unit fastpath, scope-aware icon zoom and border thickness")
