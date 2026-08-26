local function Fail(message)
    error("apex_it_dev_aura_smoke: " .. tostring(message), 0)
end

local function Expect(condition, message)
    if not condition then Fail(message) end
end

local gameplay = {
    enableCombatTimer = false,
    enableCombatStateText = false,
    enableCombatCrosshair = false,
    enablePlayerTotems = false,
    enableApexItDevAura = true,
    enableApexNameplateRangeDetection = true,
    enableApexRangeCounter = false,
    enableShadowTechniquesStackHighlight = true,
    shadowTechniquesGlowColor = { 0.69, 0.50, 0.88 },
    shadowTechniquesGlowScale = 100,
    shadowTechniquesGlowStrength = 80,
    apexItFontSize = 32,
    apexItOffsetX = 0,
    apexItOffsetY = 140,
}
local specID = 261
local deathstalkerKnown = true
local inCombat = false
local secretTechniqueCooldownRemaining = 20
local chargedPowerPoints = {}
local frames = {}
local nameplateState = {
    nameplate1 = { exists = true, enemy = true, dead = false, inRange = true },
    nameplate2 = { exists = true, enemy = true, dead = false, inRange = false },
    nameplate3 = { exists = true, enemy = true, dead = false, inRange = false },
    nameplate4 = { exists = true, enemy = true, dead = false, inRange = false },
}

UIParent = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
canaccesstable = function(value) return type(value) == "table" and value.secret ~= true end
issecure = function() return false end
InCombatLockdown = function() return inCombat end
GetUnitChargedPowerPoints = function(unit)
    Expect(unit == "player", "charged combo-point query used the wrong unit")
    return chargedPowerPoints
end
C_Spell = {
    IsSpellInRange = function(spellID, unit)
        Expect(spellID == 196819, "range scan did not use Eviscerate")
        local state = nameplateState[unit]
        return state and state.inRange or false
    end,
    GetSpellCooldownDuration = function(spellID, ignoreGCD)
        Expect(spellID == 280719 and ignoreGCD == true,
            "Secret Technique duration request did not ignore the GCD")
        local duration = {}
        function duration:EvaluateRemainingDuration(curve)
            return curve:Evaluate(secretTechniqueCooldownRemaining)
        end
        return duration
    end,
}
C_CurveUtil = {
    CreateCurve = function()
        local curve = { points = {} }
        function curve:SetType(curveType) self.curveType = curveType end
        function curve:AddPoint(x, y) self.points[#self.points + 1] = { x = x, y = y } end
        function curve:Evaluate(value)
            local selected = self.points[1]
            for i = 1, #self.points do
                if value >= self.points[i].x then selected = self.points[i] end
            end
            return selected and selected.y or 0
        end
        return curve
    end,
}
Enum = { LuaCurveType = { Step = 1 } }
C_NamePlate = {
    GetNamePlates = function()
        local result = {}
        for unit, state in pairs(nameplateState) do
            if state.exists then
                local nameplate = { unit = unit }
                function nameplate:GetUnit() return self.unit end
                result[#result + 1] = nameplate
            end
        end
        return result
    end,
}
UnitExists = function(unit)
    local state = nameplateState[unit]
    return state and state.exists == true or false
end
UnitCanAttack = function(_, unit)
    local state = nameplateState[unit]
    return state and state.enemy == true or false
end
UnitIsDeadOrGhost = function(unit)
    local state = nameplateState[unit]
    return state and state.dead == true or false
end
C_SpellBook = {
    IsSpellKnown = function(spellID)
        return spellID == 457058 and deathstalkerKnown
    end,
}
C_CooldownViewer = {}
C_StringUtil = {
    CreateNumericRuleFormatter = function()
        local formatter = {}
        function formatter:SetBreakpoints(breakpoints) self.breakpoints = breakpoints end
        function formatter:FormatNumber(value)
            local selected = self.breakpoints and self.breakpoints[1]
            for i = 1, #(self.breakpoints or {}) do
                if value >= self.breakpoints[i].threshold then selected = self.breakpoints[i] end
            end
            return selected and string.format(selected.format, value) or ""
        end
        return formatter
    end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function() Fail("runtime performed a direct player-aura read") end,
    GetAuraDataBySpellName = function() Fail("runtime performed a direct named-aura read") end,
    GetAuraApplicationDisplayCount = function() Fail("runtime performed a direct stack read") end,
}
local pendingTimers = {}
local scheduledTimerDelays = {}
local function TimerWasScheduled(delay)
    for i = 1, #scheduledTimerDelays do
        if scheduledTimerDelays[i] == delay then return true end
    end
    return false
end
local function RunPendingTimersOnce()
    local callbacks = pendingTimers
    pendingTimers = {}
    for i = 1, #callbacks do callbacks[i]() end
end
C_Timer = {
    After = function(delay, callback)
        if delay == 0 then callback() else pendingTimers[#pendingTimers + 1] = callback end
    end,
    NewTimer = function(delay, callback)
        scheduledTimerDelays[#scheduledTimerDelays + 1] = delay
        local timer = { callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        pendingTimers[#pendingTimers + 1] = function()
            if not timer.cancelled then callback() end
        end
        return timer
    end,
}

function hooksecurefunc(target, methodName, callback)
    target._smokeHooks = target._smokeHooks or {}
    local hooks = target._smokeHooks[methodName]
    if not hooks then
        hooks = {}
        target._smokeHooks[methodName] = hooks
        local original = target[methodName]
        target[methodName] = function(...)
            original(...)
            for i = 1, #hooks do hooks[i](...) end
        end
    end
    hooks[#hooks + 1] = callback
end

local function NewFontString(name, template)
    local fontString = { shown = true, fontTemplate = template }
    local function ExpectMutable(self, operation)
        Expect(self.forbidden ~= true, operation .. " touched an AuraContainer-owned FontString")
    end
    function fontString:SetPoint(...)
        ExpectMutable(self, "SetPoint")
        self.point = { ... }
    end
    function fontString:SetText(value)
        Expect(self.fontTemplate ~= nil or self.fontPath ~= nil, "FontString:SetText called before a font was set")
        self.text = value
    end
    function fontString:GetText() return self.text or "" end
    function fontString:SetFont(path, size, flags)
        ExpectMutable(self, "SetFont")
        self.fontPath, self.fontSize, self.fontFlags = path, size, flags
        return true
    end
    function fontString:SetTextColor(...)
        ExpectMutable(self, "SetTextColor")
        self.color = { ... }
    end
    function fontString:SetAlpha(alpha)
        ExpectMutable(self, "SetAlpha")
        self.alpha = alpha
    end
    function fontString:SetShadowOffset(...)
        ExpectMutable(self, "SetShadowOffset")
        self.shadowOffset = { ... }
    end
    function fontString:SetShadowColor(...)
        ExpectMutable(self, "SetShadowColor")
        self.shadowColor = { ... }
    end
    function fontString:Show()
        ExpectMutable(self, "Show")
        self.shown = true
    end
    function fontString:Hide()
        ExpectMutable(self, "Hide")
        self.shown = false
    end
    if name then _G[name] = fontString end
    return fontString
end

local nativeAuraStates = {}
local nativeAuraSensors = {}
local nativeApplicationFontStrings = {}
local nativeApplicationBars = {}

local function RefreshNativeAuraSensors(spellID, active, stackCount)
    nativeAuraStates[spellID] = { active = active == true, stackCount = stackCount or 0 }
    for i = 1, #nativeAuraSensors do
        local sensor = nativeAuraSensors[i]
        if sensor.spellIDs[spellID] then
            if sensor.button.applicationCount then
                local display = sensor.button.applicationCount
                display.fontString:SetText(active and display.formatter:FormatNumber(stackCount or 0) or "")
            end
            if sensor.button.applicationBar then
                sensor.button.applicationBar.statusBar:SetValue(active and (stackCount or 0) or 0)
            end
        end
    end
end

MSUF_Auras3 = {
    CreateClassPowerAuraSensor = function(parent, key, spellIDs, initializeFrame)
        local sensor = { parent = parent, key = key, spellIDs = spellIDs, shown = true, enabled = true }
        function sensor:ClearAllPoints() self.point = nil end
        function sensor:SetAllPoints(relativeTo) self.point = relativeTo end
        function sensor:SetEnabled(enabled) self.enabled = enabled == true end
        function sensor:SetShown(shown) self.shown = shown == true end
        function sensor:SetAlpha(alpha) self.alpha = alpha end

        local button = { parent = sensor }
        sensor.button = button
        function button:ClearAllPoints() self.point = nil end
        function button:SetAllPoints(relativeTo) self.point = relativeTo end
        function button:GetParent() return self.parent end
        function button:SetMouseClickEnabled() end
        function button:SetMouseMotionEnabled() end
        function button:EnableMouse() end
        function button:CreateFontString(name, _, template)
            local fontString = NewFontString(name, template)
            nativeApplicationFontStrings[#nativeApplicationFontStrings + 1] = fontString
            return fontString
        end
        function button:SetApplicationCount(fontString, options)
            self.applicationCount = { fontString = fontString, formatter = options.formatter }
            for spellID in pairs(spellIDs) do
                local state = nativeAuraStates[spellID]
                fontString:SetText(state and state.active and options.formatter:FormatNumber(state.stackCount) or "")
                break
            end
        end
        function button:SetApplicationBar(statusBar, options)
            self.applicationBar = { statusBar = statusBar, maxApplications = options.maxApplications }
            nativeApplicationBars[#nativeApplicationBars + 1] = self.applicationBar
            for spellID in pairs(spellIDs) do
                local state = nativeAuraStates[spellID]
                statusBar:SetValue(state and state.active and state.stackCount or 0)
                break
            end
        end

        nativeAuraSensors[#nativeAuraSensors + 1] = sensor
        initializeFrame(button)
        if button.applicationCount then
            -- Blizzard applies AuraContainer access restrictions as soon as the
            -- initializeFrame callback returns. Later addon-side mutation is forbidden.
            button.applicationCount.fontString.forbidden = true
        end
        if button.applicationBar then button.applicationBar.statusBar.forbidden = true end
        return sensor
    end,
}

local function NewTrackedBuffItem(spellID)
    local applications = NewFontString(nil, "NumberFontNormal")
    applications:SetText("")
    local item = {
        cooldownID = spellID,
        spellID = spellID,
        active = false,
        applicationText = "",
        cooldownInfo = { spellID = spellID, linkedSpellIDs = {} },
    }
    function item:GetCooldownID() return self.cooldownID end
    function item:GetSpellID() return self.spellID end
    function item:GetCooldownInfo() return self.cooldownInfo end
    function item:IsActive() return self.active end
    function item:GetSize() return 36, 36 end
    function item:GetApplicationsFontString() return applications end
    function item:RefreshApplications() applications:SetText(self.applicationText) end
    function item:OnActiveStateChanged() end
    function item:SetAuraState(active, stackCount)
        self.active = active == true
        self.applicationText = self.active and stackCount and stackCount > 1 and tostring(stackCount) or ""
        RefreshNativeAuraSensors(self.spellID, self.active, stackCount)
        self:RefreshApplications()
        self:OnActiveStateChanged()
    end
    return item
end

local function NewTrackedCooldownItem(spellID)
    local cooldownFrame = { hooks = {} }
    function cooldownFrame:HookScript(scriptName, callback)
        self.hooks[scriptName] = self.hooks[scriptName] or {}
        self.hooks[scriptName][#self.hooks[scriptName] + 1] = callback
    end
    local item = {
        cooldownID = spellID,
        spellID = spellID,
        active = true,
        onCooldown = true,
        cooldownInfo = { spellID = spellID, linkedSpellIDs = {} },
        cooldownFrame = cooldownFrame,
    }
    function item:GetCooldownID() return self.cooldownID end
    function item:GetSpellID() return self.spellID end
    function item:GetCooldownInfo() return self.cooldownInfo end
    function item:IsActive() return self.active end
    function item:IsOnCooldown()
        if inCombat then return { secret = true } end
        return self.onCooldown
    end
    function item:GetCooldownFrame() return self.cooldownFrame end
    function item:OnActiveStateChanged() end
    function item:RefreshData() end
    function item:RefreshCooldownOnly() self:RefreshData() end
    function item:OnCooldownDone() self.onCooldown = false end
    local capturedOnCooldownDone = item.OnCooldownDone
    function item:TriggerNativeCooldownDone()
        secretTechniqueCooldownRemaining = 0
        capturedOnCooldownDone(self)
        for _, callback in ipairs(self.cooldownFrame.hooks.OnCooldownDone or {}) do
            callback(self.cooldownFrame)
        end
    end
    return item
end

local darkestNight = NewTrackedBuffItem(457280)
local ancientArts = NewTrackedBuffItem(1269163)
local shadowTechniques = NewTrackedBuffItem(196911)
local secretTechnique = NewTrackedCooldownItem(280719)
EssentialCooldownViewer = {
    itemFrames = { secretTechnique },
}
function EssentialCooldownViewer:GetItemFrames() return self.itemFrames end
function EssentialCooldownViewer:RefreshData()
    for i = 1, #self.itemFrames do self.itemFrames[i]:RefreshData() end
end
BuffIconCooldownViewer = {
    itemFrames = { darkestNight, ancientArts, shadowTechniques },
}
function BuffIconCooldownViewer:GetItemFrames() return self.itemFrames end
function BuffIconCooldownViewer:RefreshData()
    for i = 1, #self.itemFrames do
        self.itemFrames[i]:RefreshApplications()
        self.itemFrames[i]:OnActiveStateChanged()
    end
end

local function NewTexture()
    local texture = { shown = true }
    function texture:SetAlpha(alpha) self.alpha = alpha end
    function texture:SetTexture(path) self.texture = path end
    function texture:SetPoint(...) self.point = { ... } end
    function texture:ClearAllPoints() self.point = nil end
    function texture:SetSize(width, height) self.width, self.height = width, height end
    function texture:SetWidth(width) self.width = width end
    function texture:SetHeight(height) self.height = height end
    function texture:SetTexCoord(...) self.texCoord = { ... } end
    function texture:SetVertexColor(...) self.color = { ... } end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    return texture
end

function CreateFrame(frameType, name, parent)
    if name and _G[name] then return _G[name] end
    local frame = { events = {}, shown = true, parent = parent, frameType = frameType }
    frames[#frames + 1] = frame
    if name then _G[name] = frame end

    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetSize() return self.width, self.height end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:SetClampedToScreen(enabled) self.clamped = enabled == true end
    function frame:SetMovable(enabled) self.movable = enabled == true end
    function frame:RegisterForDrag(...) self.dragButtons = { ... } end
    function frame:SetScript(script, callback) self[script] = callback end
    function frame:CreateFontString(fontName, _, template) return NewFontString(fontName, template) end
    function frame:CreateTexture()
        self.textures = self.textures or {}
        local texture = NewTexture()
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:SetClipsChildren(enabled) self.clipsChildren = enabled == true end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled == true end
    function frame:SetShown(shown) self.shown = shown == true end
    function frame:IsShown() return self.shown == true end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.events[event] = unit end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    if frameType == "Cooldown" then
        function frame:SetCooldownFromDurationObject(duration) self.duration = duration end
        function frame:Clear() self.duration = nil end
    elseif frameType == "StatusBar" then
        frame.statusTexture = NewTexture()
        function frame:SetStatusBarTexture(path) self.statusTexture:SetTexture(path) end
        function frame:GetStatusBarTexture() return self.statusTexture end
        function frame:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
        function frame:SetValue(value)
            value = tonumber(value) or 0
            if self.minimum and value < self.minimum then value = self.minimum end
            if self.maximum and value > self.maximum then value = self.maximum end
            self.value = value
        end
    end
    return frame
end

local registeredModule
local MSUF = {
    Gameplay = {
        GetPlayerSpecID = function() return specID end,
        Clamp = function(value) return value end,
        RoundInt = function(value) return value end,
        SetupArrowNudge = function(frame, move, canMove)
            frame._smokeNudge = move
            frame._smokeCanNudge = canMove
        end,
        SelectNudgeFrame = function() end,
        RefreshKeyboardNudge = function() end,
        ReleaseKeyboardNudge = function() end,
        BeginHistory = function() end,
        CommitHistory = function() end,
        CheckpointHistory = function() end,
    },
    MSUF_EnsureGameplayDefaults = function() return gameplay end,
    MSUF_GetGameplayDBFast = function() return gameplay end,
    MSUF_GetGameplayFontSettings = function()
        return STANDARD_TEXT_FONT, "OUTLINE", 1, 1, 1, 24, false
    end,
    MSUF_NormalizeRGB = function(_, r, g, b) return r, g, b end,
    MSUF_GetCombatStateColors = function() return 1, 0, 0, 0, 1, 0 end,
    MSUF_RegisterModule = function(_, module) registeredModule = module end,
}

MSUF_ScheduleOnce = function(_, callback) callback() end
MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end

local borderChunk, borderLoadError = loadfile("MidnightSimpleUnitFrames/Runtime/MSUF_BorderStyles.lua")
if not borderChunk then Fail(borderLoadError) end
borderChunk("MidnightSimpleUnitFrames", MSUF)

local chunk, loadError = loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayRuntime.lua")
if not chunk then Fail(loadError) end
local partialOverlay = CreateFrame("Frame", "MSUF_ApexItDevAuraFrame", UIParent)
partialOverlay:Hide()
chunk("MidnightSimpleUnitFrames", MSUF)

local overlay = _G.MSUF_ApexItDevAuraFrame
local text = overlay and overlay._msufApexItText
local stackText = overlay and overlay._msufApexItStackText
local function NativeSoftGlowIsExposed(index)
    local binding = nativeApplicationBars[index]
    return binding and binding.statusBar.value >= binding.maxApplications or false
end
local function SoftGlowHosts()
    local result = {}
    for i = 1, #frames do
        local frame = frames[i]
        local texture = frame.textures and frame.textures[1]
        if texture and texture.texture
            and texture.texture:find("msuf_aura_border_glow.tga", 1, true) then
            result[#result + 1] = frame
        end
    end
    return result
end
local apexItSensor, apexSecTechSensor, apexBlackPowderSensor
local apexStackSensor, apexSecTechStackSensor, apexBlackPowderStackSensor
local shadowHighlightSensor
for i = 1, #nativeAuraSensors do
    local sensor = nativeAuraSensors[i]
    if sensor.key == "msuf_apex_it_label" then apexItSensor = sensor
    elseif sensor.key == "msuf_apex_sectech_label" then apexSecTechSensor = sensor
    elseif sensor.key == "msuf_apex_black_powder_label" then apexBlackPowderSensor = sensor
    elseif sensor.key == "msuf_apex_it_stacks" then apexStackSensor = sensor
    elseif sensor.key == "msuf_apex_sectech_stacks" then apexSecTechStackSensor = sensor
    elseif sensor.key == "msuf_apex_black_powder_stacks" then apexBlackPowderStackSensor = sensor
    elseif sensor.key:match("^msuf_shadow_techniques_stack_highlight_") then shadowHighlightSensor = sensor end
end
Expect(overlay == partialOverlay and text ~= nil and stackText ~= nil,
    "enabled setting did not repair the partially-created overlay")
Expect(overlay.shown == false, "overlay must start hidden without Darkest Night")
Expect(text.text == "APEX IT", "overlay text drifted")
Expect(stackText.text == nil and stackText.shown == false, "live mode did not hide the preview stack text")
Expect(#nativeApplicationFontStrings == 6, "native APEX action renderers were not created")
local softGlowHosts = SoftGlowHosts()
Expect(#nativeApplicationBars == 1 and #softGlowHosts == 1,
    "native Shadow Techniques Soft Glow renderer was not created")
Expect(apexItSensor and apexSecTechSensor and apexBlackPowderSensor
    and apexStackSensor and apexSecTechStackSensor and apexBlackPowderStackSensor,
    "native APEX action sensors were not created")
Expect(shadowHighlightSensor, "native Shadow Techniques stack-highlight sensor was not created")
Expect(apexItSensor.shown == false and apexSecTechSensor.shown == false
    and apexBlackPowderSensor.shown == false and apexStackSensor.shown == false
    and apexSecTechStackSensor.shown == false and apexBlackPowderStackSensor.shown == false,
    "native APEX action sensors did not start fail-closed")
Expect(shadowHighlightSensor.shown == true, "Shadow Techniques stack-highlight sensor did not start active")
local initialGlowTexture = softGlowHosts[1].textures[1]
Expect(initialGlowTexture.color[1] == 0.69
    and initialGlowTexture.color[2] == 0.50
    and initialGlowTexture.color[3] == 0.88
    and initialGlowTexture.color[4] == 0.8,
    "Shadow Techniques Soft Glow color/strength was not applied before native ownership")
local apexItApplicationText = apexItSensor.button.applicationCount.fontString
local apexSecTechApplicationText = apexSecTechSensor.button.applicationCount.fontString
local apexBlackPowderApplicationText = apexBlackPowderSensor.button.applicationCount.fontString
local apexStackApplicationText = apexStackSensor.button.applicationCount.fontString
local apexSecTechStackApplicationText = apexSecTechStackSensor.button.applicationCount.fontString
local apexBlackPowderStackApplicationText = apexBlackPowderStackSensor.button.applicationCount.fontString
Expect(apexItApplicationText.text == "" and apexSecTechApplicationText.text == ""
    and apexBlackPowderApplicationText.text == "" and apexStackApplicationText.text == ""
    and apexSecTechStackApplicationText.text == "" and apexBlackPowderStackApplicationText.text == ""
    and nativeApplicationBars[1].statusBar.value == 0,
    "inactive native five-stack renderers were not empty")
Expect(text.fontSize == 32, "configured text size was not applied")
Expect(stackText.fontSize == 20.8, "stack text size did not follow the configured text size")
Expect(overlay.point and overlay.point[4] == 0 and overlay.point[5] == 140, "configured position was not applied")

local eventFrame, rangeEventFrame
for i = 1, #frames do
    if frames[i].events.COOLDOWN_VIEWER_DATA_LOADED then eventFrame = frames[i] end
    if frames[i].events.NAME_PLATE_UNIT_ADDED then rangeEventFrame = frames[i] end
end
Expect(eventFrame ~= nil, "CooldownViewer driver events were not registered")
Expect(rangeEventFrame ~= nil, "APEX range driver events were not registered")
Expect(eventFrame.events.UNIT_AURA == nil, "feature retained direct UNIT_AURA handling")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == "player",
    "player finisher success event was not registered")
Expect(eventFrame.events.UNIT_POWER_POINT_CHARGE == "player",
    "supercharged combo-point event was not registered for the player")
Expect(eventFrame.events.UNIT_POWER_UPDATE == nil,
    "tracker registered the high-frequency generic power event")
Expect(eventFrame.events.PLAYER_REGEN_ENABLED == true,
    "APEX driver did not register its out-of-combat Secret Technique readiness resync")
Expect(eventFrame.events.SPELL_UPDATE_COOLDOWN == nil,
    "feature registered an unrelated cooldown event")
Expect(eventFrame.events.NAME_PLATE_UNIT_ADDED == nil and eventFrame.events.NAME_PLATE_UNIT_REMOVED == nil,
    "CooldownViewer driver absorbed nameplate target-count events")
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == true
    and rangeEventFrame.events.NAME_PLATE_UNIT_REMOVED == true
    and rangeEventFrame.events.SPELL_RANGE_CHECK_UPDATE == true
    and rangeEventFrame.events.ACTION_RANGE_CHECK_UPDATE == true,
    "range driver did not subscribe to nameplate target-count events")

gameplay.enableApexNameplateRangeDetection = false
MSUF.MSUF_RequestGameplayApply()
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == nil
    and rangeEventFrame.events.NAME_PLATE_UNIT_REMOVED == nil
    and rangeEventFrame.events.SPELL_RANGE_CHECK_UPDATE == nil
    and rangeEventFrame.events.ACTION_RANGE_CHECK_UPDATE == nil
    and rangeEventFrame.events.PLAYER_REGEN_DISABLED == nil,
    "target-detection off retained nameplate roster or scan-trigger events")
gameplay.enableApexNameplateRangeDetection = true
MSUF.MSUF_RequestGameplayApply()
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == true
    and rangeEventFrame.events.NAME_PLATE_UNIT_REMOVED == true
    and rangeEventFrame.events.SPELL_RANGE_CHECK_UPDATE == true
    and rangeEventFrame.events.ACTION_RANGE_CHECK_UPDATE == true,
    "target-detection on did not restore the APEX nameplate driver")

Expect(MSUF.MSUF_Gameplay_ApexIt_TogglePreview() == true, "preview did not turn on")
Expect(MSUF.MSUF_Gameplay_ApexIt_IsPreviewActive() == true, "preview state was not exported")
Expect(overlay.shown == true and stackText.text == "5", "preview did not show APEX IT with sample stacks")
gameplay.apexItFontSize = 48
gameplay.apexItOffsetX = 17
gameplay.apexItOffsetY = -23
MSUF.MSUF_RequestGameplayApply()
Expect(text.fontSize == 48, "preview did not apply the configured text size")
Expect(overlay.point and overlay.point[4] == 17 and overlay.point[5] == -23,
    "preview did not apply the configured position")
Expect(MSUF.MSUF_Gameplay_ApexIt_TogglePreview() == false, "preview did not turn off")
Expect(overlay.shown == false, "preview off did not restore the live hidden state")

gameplay.apexItFontSize = 32
gameplay.apexItOffsetX = 0
gameplay.apexItOffsetY = 140
MSUF.MSUF_RequestGameplayApply()

shadowTechniques:SetAuraState(true, 4)
darkestNight:SetAuraState(true)
Expect(overlay.shown == true, "Darkest Night did not activate the native render host")
Expect(text.shown == false and stackText.shown == false, "live mode exposed preview text")
Expect(apexItApplicationText.text == "" and apexSecTechApplicationText.text == ""
    and apexBlackPowderApplicationText.text == "" and apexStackApplicationText.text == ""
    and apexSecTechStackApplicationText.text == "" and apexBlackPowderStackApplicationText.text == "",
    "APEX action rendered below five Shadow Techniques stacks")
Expect(nativeApplicationBars[1].statusBar.value == 4 and not NativeSoftGlowIsExposed(1),
    "Shadow Techniques icon was highlighted below five stacks")

shadowTechniques:SetAuraState(true, 5)
Expect(apexItApplicationText.text == "APEX IT"
    and apexStackApplicationText.text == "5"
    and apexItSensor.shown == true and apexSecTechSensor.shown == false
    and apexBlackPowderSensor.shown == false,
    "APEX IT did not render at exactly five Shadow Techniques stacks")
Expect(NativeSoftGlowIsExposed(1),
    "Shadow Techniques icon was not highlighted at exactly five stacks")

gameplay.enableApexNameplateRangeDetection = false
MSUF.MSUF_RequestGameplayApply()
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == nil
    and rangeEventFrame.events.NAME_PLATE_UNIT_REMOVED == nil,
    "target-detection off retained nameplate events during an active APEX window")
Expect(overlay.shown == true
    and apexItSensor.shown == true and apexSecTechSensor.shown == false
    and apexBlackPowderSensor.shown == false
    and apexItApplicationText.text == "APEX IT"
    and apexStackApplicationText.text == "5",
    "target-detection off suppressed the base Darkest Night APEX IT fallback")
gameplay.enableApexNameplateRangeDetection = true
MSUF.MSUF_RequestGameplayApply()
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == true
    and rangeEventFrame.events.NAME_PLATE_UNIT_REMOVED == true,
    "target-detection on did not restore nameplate events during an active APEX window")

local previousShadowHighlightSensor = shadowHighlightSensor
gameplay.shadowTechniquesGlowColor = { 0.10, 0.60, 1.00 }
gameplay.shadowTechniquesGlowScale = 125
gameplay.shadowTechniquesGlowStrength = 55
MSUF.MSUF_RequestGameplayApply()
shadowHighlightSensor = nativeAuraSensors[#nativeAuraSensors]
Expect(shadowHighlightSensor ~= previousShadowHighlightSensor
    and previousShadowHighlightSensor.shown == false
    and previousShadowHighlightSensor.enabled == false,
    "changing glow appearance did not replace and retire the native sensor")
softGlowHosts = SoftGlowHosts()
local changedGlowTexture = softGlowHosts[2] and softGlowHosts[2].textures[1]
Expect(changedGlowTexture and math.abs(changedGlowTexture.width - 7.65) < 0.001,
    "changed glow size did not reach the MSUF Soft Glow renderer")
Expect(changedGlowTexture.color[1] == 0.10 and changedGlowTexture.color[2] == 0.60
    and changedGlowTexture.color[3] == 1.00 and changedGlowTexture.color[4] == 0.55,
    "changed glow color/strength did not reach the MSUF Soft Glow renderer")
Expect(NativeSoftGlowIsExposed(2),
    "replacement Soft Glow did not inherit the active five-stack state")

shadowTechniques:SetAuraState(true, 9)
Expect(apexItApplicationText.text == "APEX IT"
    and apexStackApplicationText.text == "9",
    "native Shadow Techniques stack changes were not rendered")
Expect(NativeSoftGlowIsExposed(2),
    "Shadow Techniques icon highlight did not remain active above five stacks")

ancientArts:SetAuraState(true)
Expect(overlay.shown == false, "Ancient Arts did not suppress APEX IT")
Expect(shadowHighlightSensor.shown == true
    and NativeSoftGlowIsExposed(2),
    "independent stack highlight was incorrectly gated by Ancient Arts")

ancientArts:SetAuraState(false)
Expect(overlay.shown == true, "removing Ancient Arts did not restore APEX IT")
Expect(apexStackApplicationText.text == "9", "restored APEX IT lost the native stack count")

nameplateState.nameplate2.inRange = true
nameplateState.nameplate3.inRange = true
nameplateState.nameplate4.inRange = true
chargedPowerPoints = { 2 }
eventFrame.OnEvent(eventFrame, "UNIT_POWER_POINT_CHARGE", "player")
rangeEventFrame.OnEvent(rangeEventFrame, "SPELL_RANGE_CHECK_UPDATE", 196819, true, true)
Expect(overlay.shown == true and overlay.alpha == 1
    and apexSecTechSensor.shown == true and apexSecTechSensor.alpha == 0
    and apexBlackPowderSensor.shown == true and apexBlackPowderSensor.alpha == 1
    and apexItSensor.shown == false,
    "four-target action did not fall back to APEX BLACK POWDER above the SECTECH window")
Expect(apexBlackPowderApplicationText.text == "APEX BLACK POWDER"
    and apexBlackPowderStackApplicationText.text == "9",
    "APEX BLACK POWDER did not preserve the native five-stack renderer")
Expect(TimerWasScheduled(0.10), "active APEX range snapshot did not use the faster bounded cadence")
Expect(TimerWasScheduled(0.05), "multi-target action did not arm its lightweight fast refresh")

chargedPowerPoints = { 6 }
eventFrame.OnEvent(eventFrame, "UNIT_POWER_POINT_CHARGE", "player")
Expect(apexBlackPowderSensor.shown == true,
    "an active Supercharger slot was incorrectly gated by current combo points")
chargedPowerPoints = { secret = true }
eventFrame.OnEvent(eventFrame, "UNIT_POWER_POINT_CHARGE", "player")
Expect(apexBlackPowderSensor.shown == false,
    "an inaccessible charged-point table did not fail closed")
chargedPowerPoints = {}
eventFrame.OnEvent(eventFrame, "UNIT_POWER_POINT_CHARGE", "player")
Expect(apexBlackPowderSensor.shown == false,
    "an empty charged-point table enabled APEX BLACK POWDER")
chargedPowerPoints = { 2 }
eventFrame.OnEvent(eventFrame, "UNIT_POWER_POINT_CHARGE", "player")
Expect(apexBlackPowderSensor.shown == true and apexBlackPowderSensor.alpha == 1,
    "active supercharged combo point did not restore APEX BLACK POWDER")

secretTechniqueCooldownRemaining = 4.9
RunPendingTimersOnce()
Expect(overlay.shown == true and apexSecTechSensor.shown == true
    and apexSecTechSensor.alpha == 1 and apexBlackPowderSensor.alpha == 0,
    "four-target APEX SECTECH did not appear inside its five-second window outside Shadow Dance")
secretTechniqueCooldownRemaining = 20
RunPendingTimersOnce()
Expect(apexSecTechSensor.alpha == 0 and apexBlackPowderSensor.alpha == 1,
    "four-target action did not return to BLACK POWDER after leaving the SECTECH window")
secretTechnique:TriggerNativeCooldownDone()
Expect(overlay.shown == true and apexSecTechSensor.alpha == 1
    and apexBlackPowderSensor.alpha == 0,
    "four-target APEX SECTECH did not activate when Secret Technique became ready")
inCombat = true
rangeEventFrame.OnEvent(rangeEventFrame, "PLAYER_REGEN_DISABLED")
Expect(overlay.shown == true and apexItSensor.shown == false and apexSecTechSensor.shown == true,
    "four in-range enemies did not switch the action to APEX SECTECH")
Expect(apexSecTechApplicationText.text == "APEX SECTECH"
    and apexSecTechStackApplicationText.text == "9",
    "APEX SECTECH did not preserve the native five-stack renderer")

darkestNight:SetAuraState(false)
Expect(overlay.shown == true and apexSecTechSensor.shown == true,
    "four-target APEX SECTECH incorrectly depended on Darkest Night")
gameplay.enableApexNameplateRangeDetection = false
MSUF.MSUF_RequestGameplayApply()
Expect(overlay.shown == false and apexItSensor.shown == false
    and apexSecTechSensor.shown == false and apexBlackPowderSensor.shown == false,
    "target-detection off reinterpreted a ready multi-target route as APEX IT without Darkest Night")
gameplay.enableApexNameplateRangeDetection = true
MSUF.MSUF_RequestGameplayApply()
Expect(overlay.shown == true and apexSecTechSensor.shown == true,
    "target-detection on did not restore the ready four-target APEX SECTECH route")

nameplateState.nameplate4.inRange = false
inCombat = false
rangeEventFrame.OnEvent(rangeEventFrame, "PLAYER_REGEN_ENABLED")
Expect(overlay.shown == false,
    "three-target APEX IT rendered without Darkest Night")
darkestNight:SetAuraState(true)
Expect(apexItSensor.shown == true and apexSecTechSensor.shown == false,
    "three in-range enemies did not switch the action back to APEX IT")

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-irrelevant", 53)
Expect(overlay.shown == true, "an unrelated successful spell suppressed APEX IT")
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-secret", { secret = true })
Expect(overlay.shown == true, "a secret spell ID was compared instead of failing closed")

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-eviscerate", 196819)
Expect(overlay.shown == false, "successful Eviscerate did not immediately consume APEX IT")
Expect(shadowHighlightSensor.shown == true,
    "Eviscerate incorrectly disabled the independent stack highlight")
MSUF.MSUF_RequestGameplayApply()
Expect(overlay.shown == false, "a regular apply cleared the consumed latch while Darkest Night remained active")

darkestNight:SetAuraState(false)
Expect(overlay.shown == false, "ending Darkest Night unexpectedly showed APEX IT")
darkestNight:SetAuraState(true)
Expect(overlay.shown == true, "a new Darkest Night cycle did not re-arm APEX IT")

nameplateState.nameplate4.inRange = true
inCombat = true
rangeEventFrame.OnEvent(rangeEventFrame, "PLAYER_REGEN_DISABLED")
Expect(apexSecTechSensor.shown == true, "four-target cycle did not select APEX SECTECH")
secretTechnique.onCooldown = true
secretTechniqueCooldownRemaining = 20
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-secret-technique", 280719)
Expect(overlay.shown == false, "successful Secret Technique did not immediately consume APEX SECTECH")
darkestNight:SetAuraState(false)
darkestNight:SetAuraState(true)
Expect(overlay.shown == false,
    "a new Darkest Night cycle incorrectly re-armed APEX SECTECH while it was on cooldown")
darkestNight:SetAuraState(false)
secretTechnique:TriggerNativeCooldownDone()
Expect(overlay.shown == true and apexSecTechSensor.shown == true,
    "Secret Technique cooldown completion did not re-arm APEX SECTECH without Darkest Night")
shadowTechniques:SetAuraState(false)
Expect(overlay.shown == false,
    "APEX SECTECH remained active without Shadow Techniques")
shadowTechniques:SetAuraState(true, 9)
Expect(overlay.shown == true and apexSecTechSensor.shown == true,
    "restoring Shadow Techniques did not restore the ready four-target SECTECH rule")

specID = 259
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
Expect(overlay.shown == false, "non-Subtlety spec did not hide the overlay")
Expect(shadowHighlightSensor.shown == false, "non-Subtlety spec retained the stack highlight")

specID = 261
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
Expect(overlay.shown == true, "returning to Subtlety did not restore the native driver state")
Expect(shadowHighlightSensor.shown == true, "returning to Subtlety did not restore the stack highlight")

deathstalkerKnown = false
eventFrame.OnEvent(eventFrame, "PLAYER_TALENT_UPDATE")
Expect(overlay.shown == false, "Trickster activated the Deathstalker-only APEX IT routes")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == nil,
    "Trickster retained Deathstalker-only runtime events")
Expect(eventFrame.events.UNIT_POWER_POINT_CHARGE == nil
    and eventFrame.events.UNIT_POWER_UPDATE == nil,
    "Trickster retained Deathstalker-only combo-point events")
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == nil,
    "Trickster retained Deathstalker-only nameplate range events")
Expect(shadowHighlightSensor.shown == true,
    "Trickster incorrectly disabled the spec-wide Shadow Techniques stack highlight")

gameplay.enableApexItDevAura = false
MSUF.MSUF_RequestGameplayApply()
Expect(overlay.shown == false, "disabling the setting did not hide the overlay")
Expect(shadowHighlightSensor.shown == true,
    "disabling APEX IT also disabled the independent stack highlight")
Expect(eventFrame.events.COOLDOWN_VIEWER_DATA_LOADED == true,
    "enabled stack highlight lost its CooldownViewer driver event")
Expect(eventFrame.events.UNIT_AURA == nil, "stack highlight registered direct UNIT_AURA traffic")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == nil,
    "stack-highlight-only mode retained the finisher success event")
Expect(eventFrame.events.UNIT_POWER_POINT_CHARGE == nil
    and eventFrame.events.UNIT_POWER_UPDATE == nil,
    "stack-highlight-only mode retained charged combo-point events")
Expect(registeredModule and registeredModule.IsEnabled() == true,
    "module enable state ignored the enabled stack highlight")

gameplay.enableShadowTechniquesStackHighlight = false
MSUF.MSUF_RequestGameplayApply()
Expect(shadowHighlightSensor.shown == false, "disabling the stack highlight retained its sensor")
Expect(eventFrame.events.COOLDOWN_VIEWER_DATA_LOADED == nil, "disabling retained CooldownViewer driver events")
Expect(eventFrame.events.UNIT_AURA == nil, "disabling registered direct UNIT_AURA traffic")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == nil, "disabling retained the finisher success event")
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == nil, "disabling retained a nameplate counter event")
Expect(registeredModule and registeredModule.IsEnabled() == false, "module enable state ignored the disabled setting")

print("apex_it_dev_aura_smoke: OK")
