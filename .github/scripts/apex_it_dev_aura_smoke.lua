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
    apexItFontSize = 32,
    apexItOffsetX = 0,
    apexItOffsetY = 140,
}
local specID = 261
local deathstalkerKnown = true
local frames = {}

UIParent = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
issecure = function() return false end
C_Spell = {}
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
C_Timer = {
    After = function(_, callback) callback() end,
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

local function RefreshNativeAuraSensors(spellID, active, stackCount)
    nativeAuraStates[spellID] = { active = active == true, stackCount = stackCount or 0 }
    for i = 1, #nativeAuraSensors do
        local sensor = nativeAuraSensors[i]
        if sensor.spellIDs[spellID] and sensor.button.applicationCount then
            local display = sensor.button.applicationCount
            display.fontString:SetText(active and display.formatter:FormatNumber(stackCount or 0) or "")
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

        nativeAuraSensors[#nativeAuraSensors + 1] = sensor
        initializeFrame(button)
        if button.applicationCount then
            -- Blizzard applies AuraContainer access restrictions as soon as the
            -- initializeFrame callback returns. Later addon-side mutation is forbidden.
            button.applicationCount.fontString.forbidden = true
        end
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

local darkestNight = NewTrackedBuffItem(457280)
local ancientArts = NewTrackedBuffItem(1269163)
local shadowTechniques = NewTrackedBuffItem(196911)
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

function CreateFrame(frameType, name)
    if name and _G[name] then return _G[name] end
    local frame = { events = {}, shown = true }
    frames[#frames + 1] = frame
    if name then _G[name] = frame end

    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:SetScript(script, callback) self[script] = callback end
    function frame:CreateFontString(fontName, _, template) return NewFontString(fontName, template) end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetShown(shown) self.shown = shown == true end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.events[event] = unit end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    if frameType == "Cooldown" then
        function frame:SetCooldownFromDurationObject(duration) self.duration = duration end
        function frame:Clear() self.duration = nil end
    end
    return frame
end

local registeredModule
local MSUF = {
    Gameplay = {
        GetPlayerSpecID = function() return specID end,
        Clamp = function(value) return value end,
        RoundInt = function(value) return value end,
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

local chunk, loadError = loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayRuntime.lua")
if not chunk then Fail(loadError) end
local partialOverlay = CreateFrame("Frame", "MSUF_ApexItDevAuraFrame", UIParent)
partialOverlay:Hide()
chunk("MidnightSimpleUnitFrames", MSUF)

local overlay = _G.MSUF_ApexItDevAuraFrame
local text = overlay and overlay._msufApexItText
local stackText = overlay and overlay._msufApexItStackText
local apexItSensor, apexStackSensor
for i = 1, #nativeAuraSensors do
    local sensor = nativeAuraSensors[i]
    if sensor.key == "msuf_apex_it_label" then apexItSensor = sensor
    elseif sensor.key == "msuf_apex_it_stacks" then apexStackSensor = sensor end
end
Expect(overlay == partialOverlay and text ~= nil and stackText ~= nil,
    "enabled setting did not repair the partially-created overlay")
Expect(overlay.shown == false, "overlay must start hidden without Darkest Night")
Expect(text.text == "APEX IT", "overlay text drifted")
Expect(stackText.text == nil and stackText.shown == false, "live mode did not hide the preview stack text")
Expect(#nativeApplicationFontStrings == 2, "native APEX IT five-stack renderers were not created")
Expect(apexItSensor and apexStackSensor, "native APEX IT sensors were not created")
Expect(apexItSensor.shown == true and apexStackSensor.shown == true,
    "native APEX IT sensors did not start active")
Expect(nativeApplicationFontStrings[1].text == "" and nativeApplicationFontStrings[2].text == "",
    "inactive native five-stack renderers were not empty")
Expect(text.fontSize == 32, "configured text size was not applied")
Expect(stackText.fontSize == 20.8, "stack text size did not follow the configured text size")
Expect(overlay.point and overlay.point[4] == 0 and overlay.point[5] == 140, "configured position was not applied")

local eventFrame
for i = 1, #frames do
    if frames[i].events.COOLDOWN_VIEWER_DATA_LOADED then eventFrame = frames[i] end
end
Expect(eventFrame ~= nil, "CooldownViewer driver events were not registered")
Expect(eventFrame.events.UNIT_AURA == nil, "feature retained direct UNIT_AURA handling")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == "player",
    "player finisher success event was not registered")
Expect(eventFrame.events.SPELL_UPDATE_COOLDOWN == nil,
    "feature registered an unrelated cooldown event")
Expect(eventFrame.events.NAME_PLATE_UNIT_ADDED == nil and eventFrame.events.NAME_PLATE_UNIT_REMOVED == nil,
    "feature registered nameplate target-count events")

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
Expect(nativeApplicationFontStrings[1].text == "" and nativeApplicationFontStrings[2].text == "",
    "APEX IT rendered below five Shadow Techniques stacks")

shadowTechniques:SetAuraState(true, 5)
Expect(nativeApplicationFontStrings[1].text == "APEX IT"
    and nativeApplicationFontStrings[2].text == "5"
    and apexItSensor.shown == true,
    "APEX IT did not render at exactly five Shadow Techniques stacks")

shadowTechniques:SetAuraState(true, 9)
Expect(nativeApplicationFontStrings[1].text == "APEX IT"
    and nativeApplicationFontStrings[2].text == "9",
    "native Shadow Techniques stack changes were not rendered")

ancientArts:SetAuraState(true)
Expect(overlay.shown == false, "Ancient Arts did not suppress APEX IT")

ancientArts:SetAuraState(false)
Expect(overlay.shown == true, "removing Ancient Arts did not restore APEX IT")
Expect(nativeApplicationFontStrings[2].text == "9", "restored APEX IT lost the native stack count")

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-irrelevant", 53)
Expect(overlay.shown == true, "an unrelated successful spell suppressed APEX IT")
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-secret", { secret = true })
Expect(overlay.shown == true, "a secret spell ID was compared instead of failing closed")

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-eviscerate", 196819)
Expect(overlay.shown == false, "successful Eviscerate did not immediately consume APEX IT")
MSUF.MSUF_RequestGameplayApply()
Expect(overlay.shown == false, "a regular apply cleared the consumed latch while Darkest Night remained active")

darkestNight:SetAuraState(false)
Expect(overlay.shown == false, "ending Darkest Night unexpectedly showed APEX IT")
darkestNight:SetAuraState(true)
Expect(overlay.shown == true, "a new Darkest Night cycle did not re-arm APEX IT")

specID = 259
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
Expect(overlay.shown == false, "non-Subtlety spec did not hide the overlay")

specID = 261
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
Expect(overlay.shown == true, "returning to Subtlety did not restore the native driver state")

deathstalkerKnown = false
eventFrame.OnEvent(eventFrame, "PLAYER_TALENT_UPDATE")
Expect(overlay.shown == false, "Trickster activated the Deathstalker-only APEX IT routes")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == nil,
    "Trickster retained Deathstalker-only runtime events")

gameplay.enableApexItDevAura = false
MSUF.MSUF_RequestGameplayApply()
Expect(overlay.shown == false, "disabling the setting did not hide the overlay")
Expect(eventFrame.events.COOLDOWN_VIEWER_DATA_LOADED == nil, "disabling retained CooldownViewer driver events")
Expect(eventFrame.events.UNIT_AURA == nil, "disabling registered direct UNIT_AURA traffic")
Expect(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED == nil, "disabling retained the finisher success event")
Expect(eventFrame.events.NAME_PLATE_UNIT_ADDED == nil, "disabling retained a nameplate counter event")
Expect(registeredModule and registeredModule.IsEnabled() == false, "module enable state ignored the disabled setting")

print("apex_it_dev_aura_smoke: OK")
