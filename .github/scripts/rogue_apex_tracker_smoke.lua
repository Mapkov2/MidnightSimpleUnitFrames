local function Fail(message) error("ROGUE APEX TRACKER SMOKE FAIL: " .. message, 2) end
local function Expect(condition, message) if not condition then Fail(message) end end

local now = 100
local epochBase = 1770000000
local frames = {}
local namedFrames = {}
local RawPrint = print

_G = _G or {}
MidnightRogueApexTrackerDB = { outline = "CUSTOM" }
strmatch = string.match
GetLocale = function() return "enUS" end
geterrorhandler = function() return function(message) error(message, 0) end end
bit = { band = function(a, b)
    local result, place = 0, 1
    while a > 0 and b > 0 do
        local aa, bb = a % 2, b % 2
        if aa == 1 and bb == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end }
UIParent = {
    GetCenter = function() return 960, 540 end,
    GetEffectiveScale = function() return 1 end,
}
UISpecialFrames = {}
MenuResponse = { Refresh = "refresh" }
SlashCmdList = {}
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function() return 261 end
GetTime = function() return now end
time = function() return epochBase + now end
date = function(_, timestamp) return tostring(timestamp or epochBase + now) end
print = function() end
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
local registeredSettingsPanel
local openedSettingsCategory
local registeredSettings = {}
local nativeControls = { checkbox = 0, slider = 0, dropdown = 0, color = 0, button = 0, header = 0 }
local nativeDropdowns = {}
local slidersWithFormatter = 0
local sharedMediaFonts, sharedMediaTextures
local nameplateState = {
    nameplate1 = { exists = true, enemy = true, dead = false, inRange = true },
    nameplate2 = { exists = true, enemy = true, dead = false, inRange = false },
    nameplate3 = { exists = true, enemy = true, dead = false, inRange = false },
    nameplate4 = { exists = true, enemy = true, dead = false, inRange = false },
}

local function SetInRangeCount(count)
    for index = 1, 4 do nameplateState["nameplate" .. index].inRange = index <= count end
end

local function NewInitializer(kind, setting, data)
    local initializer = { kind = kind, setting = setting, data = data }
    function initializer:SetParentInitializer(parent) self.parent = parent end
    return initializer
end

local function NewSetting(variable, variableType, getValue, setValue)
    local setting = { variable = variable, variableType = variableType }
    function setting:GetVariableType() return self.variableType end
    function setting:GetValue() return getValue() end
    function setting:SetValue(value)
        setValue(value)
        if self.callback then self.callback(self, value) end
    end
    function setting:SetValueChangedCallback(callback) self.callback = callback end
    function setting:NotifyUpdate() self.notified = true end
    function setting:IsModified() return false end
    registeredSettings[variable] = setting
    return setting
end

Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    RegisterVerticalLayoutCategory = function(name)
        local category = { name = name, GetID = function() return 7319 end }
        local layout = { initializers = {} }
        function layout:AddInitializer(initializer) self.initializers[#self.initializers + 1] = initializer end
        category.layout = layout
        return category, layout
    end,
    RegisterAddOnSetting = function(_, variable, key, db, variableType)
        return NewSetting(variable, variableType, function() return db[key] end,
            function(value) db[key] = value end)
    end,
    RegisterProxySetting = function(_, variable, variableType, _, _, getValue, setValue)
        return NewSetting(variable, variableType, getValue, setValue)
    end,
    RegisterAddOnCategory = function(category) registeredSettingsPanel = category end,
    OpenToCategory = function(categoryID) openedSettingsCategory = categoryID end,
    CreateSliderOptions = function(minimum, maximum, step)
        local options = { minimum = minimum, maximum = maximum, step = step }
        function options:SetLabelFormatter(_, formatter) self.formatter = formatter end
        return options
    end,
    CreateControlTextContainer = function()
        local container = { data = {} }
        function container:Add(value, label)
            local row = { value = value, label = label }
            self.data[#self.data + 1] = row
            return row
        end
        function container:GetData() return self.data end
        return container
    end,
    CreateCheckbox = function(category, setting)
        nativeControls.checkbox = nativeControls.checkbox + 1
        local initializer = NewInitializer("checkbox", setting)
        category.layout:AddInitializer(initializer)
        return initializer
    end,
    CreateSlider = function(category, setting, options)
        nativeControls.slider = nativeControls.slider + 1
        if type(options.formatter) == "function" then slidersWithFormatter = slidersWithFormatter + 1 end
        local initializer = NewInitializer("slider", setting, options)
        category.layout:AddInitializer(initializer)
        return initializer
    end,
    CreateDropdown = function(category, setting, optionsProvider)
        nativeControls.dropdown = nativeControls.dropdown + 1
        local data = optionsProvider()
        if setting.variable == "RAT_FONT" then sharedMediaFonts = #data end
        if setting.variable == "RAT_BACKGROUND_TEXTURE" then sharedMediaTextures = #data end
        local initializer = NewInitializer("dropdown", setting, data)
        nativeDropdowns[setting.variable] = initializer
        category.layout:AddInitializer(initializer)
        return initializer
    end,
    CreateColorSwatch = function(category, setting)
        nativeControls.color = nativeControls.color + 1
        local initializer = NewInitializer("color", setting)
        category.layout:AddInitializer(initializer)
        return initializer
    end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = "RIGHT" } }
CreateSettingsListSectionHeaderInitializer = function(text, tooltip)
    nativeControls.header = nativeControls.header + 1
    return NewInitializer("header", nil, { text = text, tooltip = tooltip })
end
CreateSettingsButtonInitializer = function(name, text, callback, tooltip)
    nativeControls.button = nativeControls.button + 1
    return NewInitializer("button", nil, {
        name = name, text = text, callback = callback, tooltip = tooltip,
    })
end
UIDropDownMenu_SetWidth = function(frame, width) frame.dropdownWidth = width end
UIDropDownMenu_JustifyText = function(frame, justify) frame.dropdownJustify = justify end
UIDropDownMenu_Initialize = function(frame, callback) frame.dropdownInitialize = callback end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function() end
UIDropDownMenu_SetText = function(frame, text) frame.dropdownText = text end
CloseDropDownMenus = function() end
ColorPickerFrame = {
    GetColorRGB = function() return 1, 1, 1 end,
    SetupColorPickerAndShow = function(_, info) ColorPickerFrame.info = info end,
}
MenuUtil = {
    CreateContextMenu = function(owner, generator)
        local root = { rows = {} }
        function root:CreateTitle(title) self.title = title end
        function root:CreateRadio(label, isSelected, selectValue, data)
            self.rows[#self.rows + 1] = {
                label = label,
                selected = isSelected(data),
                selectValue = selectValue,
                data = data,
            }
        end
        generator(owner, root)
        owner.contextMenu = root
    end,
}

local function NewMenuDescription(label)
    local description = { label = label, children = {} }
    function description:CreateTitle(text) self.title = text end
    function description:CreateRadio(text, isSelected, selectValue, data)
        local child = NewMenuDescription(text)
        child.isSelected, child.selectValue, child.data = isSelected, selectValue, data
        self.children[#self.children + 1] = child
        return child
    end
    function description:SetTitleAndTextTooltip(title, text) self.tooltip = { title, text } end
    function description:SetScrollMode(extent) self.scrollExtent = extent end
    function description:SetEnabled(enabled) self.enabled = enabled end
    return description
end

local pendingTimers = {}
C_Timer = {
    After = function(delay, callback)
        if delay == 0 then callback() else pendingTimers[#pendingTimers + 1] = callback end
    end,
    NewTimer = function(_, callback)
        local timer = { cancelled = false }
        function timer:Cancel() self.cancelled = true end
        pendingTimers[#pendingTimers + 1] = function()
            if not timer.cancelled then callback() end
        end
        return timer
    end,
}
C_Spell = {
    IsSpellInRange = function(spellID, unit)
        Expect(spellID == 196819, "standalone range scan did not use Eviscerate")
        local row = nameplateState[unit]
        return row and row.inRange
    end,
}
C_NamePlate = {
    GetNamePlates = function()
        local result = {}
        for unit, row in pairs(nameplateState) do
            if row.exists then
                local plate = { unit = unit }
                function plate:GetUnit() return self.unit end
                result[#result + 1] = plate
            end
        end
        return result
    end,
}
UnitExists = function(unit)
    local row = nameplateState[unit]
    return row and row.exists == true or false
end
UnitCanAttack = function(_, unit)
    local row = nameplateState[unit]
    return row and row.enemy == true or false
end
UnitIsDeadOrGhost = function(unit)
    local row = nameplateState[unit]
    return row and row.dead == true or false
end
C_SpellBook = { IsSpellKnown = function(spellID) return spellID == 457058 end }
local activeChallengeMapID
local activeKeystoneLevel = 12
local challengeCompletionInfo = { level = 12, onTime = true, keystoneUpgradeLevels = 2 }
C_ChallengeMode = {
    GetActiveChallengeMapID = function() return activeChallengeMapID end,
    GetMapUIInfo = function(mapID) return mapID == 399 and "Ruby Life Pools" or "Test Keystone" end,
    GetActiveKeystoneInfo = function() return activeKeystoneLevel, {}, true end,
    GetChallengeCompletionInfo = function() return challengeCompletionInfo end,
}

local function NewFontString()
    local fs = { shown = true }
    function fs:SetPoint(...) self.point = { ... } end
    function fs:SetText(text)
        if not self.font then error("FontString:SetText(): Font not set", 2) end
        self.text = text
    end
    function fs:SetFont(path, size, outline) self.font, self.size, self.outline = path, size, outline return true end
    function fs:SetTextColor(...) self.color = { ... } end
    function fs:SetShadowColor(...) self.shadowColor = { ... } end
    function fs:SetShadowOffset(...) self.shadowOffset = { ... } end
    function fs:SetJustifyH(value) self.justifyH = value end
    function fs:SetWidth(value) self.width = value end
    function fs:SetWordWrap(value) self.wordWrap = value end
    function fs:SetShown(shown) self.shown = shown == true end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    return fs
end

local function NewTexture()
    local texture = {}
    function texture:SetPoint(...) self.point = { ... } end
    function texture:SetSize(width, height) self.width, self.height = width, height end
    function texture:SetWidth(width) self.width = width end
    function texture:SetHeight(height) self.height = height end
    function texture:SetColorTexture(...) self.color = { ... } end
    function texture:SetTexture(path) self.texture = path end
    function texture:ClearAllPoints() self.point = nil end
    function texture:SetShown(shown) self.shown = shown == true end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    return texture
end

function CreateFrame(_, name)
    local frame = { events = {}, scripts = {}, shown = false, fonts = {}, scale = 1 }
    frames[#frames + 1] = frame
    if name then namedFrames[name] = frame _G[name] = frame end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.events[event] = unit end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(script, callback) self.scripts[script] = callback self[script] = callback end
    function frame:HookScript(script, callback)
        local original = self.scripts[script]
        self:SetScript(script, function(...)
            if original then original(...) end
            callback(...)
        end)
    end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:SetClampedToScreen(value) self.clamped = value end
    function frame:SetMovable(value) self.movable = value end
    function frame:RegisterForDrag(...) self.drag = { ... } end
    function frame:SetBackdrop(value) self.backdrop = value end
    function frame:SetBackdropColor(...) self.backdropColor = { ... } end
    function frame:SetBackdropBorderColor(...) self.borderColor = { ... } end
    function frame:CreateFontString() local fs = NewFontString() self.fonts[#self.fonts + 1] = fs return fs end
    function frame:CreateTexture() return NewTexture() end
    function frame:SetScale(scale) self.scale = scale end
    function frame:SetText(text) self.text = text end
    function frame:OverrideText(text) self.overrideText = text end
    function frame:SetupMenu(callback) self.menuSetup = callback end
    function frame:SetChecked(value) self.checked = value == true end
    function frame:GetChecked() return self.checked == true end
    function frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
    function frame:SetValueStep(step) self.valueStep = step end
    function frame:SetObeyStepOnDrag(value) self.obeyStep = value end
    function frame:SetOrientation(value) self.orientation = value end
    function frame:SetHitRectInsets(...) self.hitRectInsets = { ... } end
    function frame:SetThumbTexture() self.thumb = NewTexture() end
    function frame:GetThumbTexture() return self.thumb end
    function frame:SetValue(value)
        self.value = value
        if self.OnValueChanged then self:OnValueChanged(value) end
    end
    function frame:SetScrollChild(child) self.scrollChild = child end
    function frame:GetEffectiveScale() return self.scale end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(_, _, _, x, y) self.point = { x = x or 0, y = y or 0 } end
    function frame:GetCenter() return 960 + (self.point and self.point.x or 0), 540 + (self.point and self.point.y or 0) end
    function frame:EnableMouse(value) self.mouse = value end
    function frame:SetShown(value) self.shown = value == true end
    function frame:IsShown() return self.shown == true end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:SetParent(parent) self.parent = parent end
    function frame:SetAllPoints(parent) self.allPoints = parent or true end
    return frame
end

function hooksecurefunc(target, methodName, callback)
    local original = target[methodName]
    target[methodName] = function(self, ...)
        local results = { original(self, ...) }
        callback(self, ...)
        return unpack(results)
    end
end

local function NewItem(cooldownID, info, active)
    local item = { cooldownID = cooldownID, info = info, active = active == true }
    function item:GetCooldownID() return self.cooldownID end
    function item:GetCooldownInfo() return self.info end
    function item:IsActive() return self.active end
    function item:OnActiveStateChanged() end
    function item:SetActive(value)
        self.active = value == true
        self:OnActiveStateChanged()
    end
    return item
end

local darkest = NewItem(1, { spellID = 457280 }, false)
local ancient = NewItem(2, { spellID = 1269163 }, false)
local dance = NewItem(3, { spellID = 185422 }, false)
local essentialDance = NewItem(4, { spellID = 185313, linkedSpellIDs = { 185422 } }, true)

EssentialCooldownViewer = { items = { essentialDance } }
BuffIconCooldownViewer = { items = { darkest, ancient, dance } }
BuffBarCooldownViewer = { items = {} }
for _, viewer in ipairs({ EssentialCooldownViewer, BuffIconCooldownViewer, BuffBarCooldownViewer }) do
    function viewer:GetItemFrames() return self.items end
    function viewer:RefreshData() end
end

C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function(cooldownID)
        for _, item in ipairs({ darkest, ancient, dance, essentialDance }) do
            if item.cooldownID == cooldownID then return item.info end
        end
    end,
}

local addonTable = {}
assert(loadfile("RogueApexTracker/Libs/LibStub/LibStub.lua"))()
assert(loadfile("RogueApexTracker/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))()
assert(loadfile("RogueApexTracker/Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua"))()
local chunk = assert(loadfile("RogueApexTracker/Core.lua"))
chunk("RogueApexTracker", addonTable)
local historyChunk = assert(loadfile("RogueApexTracker/History.lua"))
historyChunk("RogueApexTracker", addonTable)
local optionsChunk = assert(loadfile("RogueApexTracker/OptionsClassic.lua"))
optionsChunk("RogueApexTracker", addonTable)

local eventFrame
for index = 1, #frames do
    if frames[index].events.ADDON_LOADED then eventFrame = frames[index] break end
end
Expect(eventFrame and eventFrame.OnEvent, "event frame was not created")
eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "RogueApexTracker")
eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")

local RAT = RogueApexTracker
local display = namedFrames.RogueApexTrackerFrame
local rangeEventFrame
for index = 1, #frames do
    if frames[index].events.NAME_PLATE_UNIT_ADDED then rangeEventFrame = frames[index] break end
end
Expect(RAT and RAT.db and display, "addon did not initialize")
Expect(RogueApexTrackerDB == RAT.db and MidnightRogueApexTrackerDB == nil,
    "legacy SavedVariables were not migrated to RogueApexTrackerDB")
Expect(type(RAT.db.sessionState) == "table",
    "reload-safe session SavedVariables were not initialized")
Expect(registeredSettingsPanel ~= nil, "options panel was not registered")
Expect(registeredSettingsPanel.name == "Rogue Apex Tracker",
    "native vertical settings category name drifted")
Expect(nativeControls.checkbox >= 7, "native checkbox controls were not registered")
Expect(nativeControls.slider >= 8, "native slider controls were not registered")
Expect(slidersWithFormatter == nativeControls.slider, "one or more sliders have no visible value formatter")
Expect(nativeControls.dropdown == 3, "native dropdown controls were not registered")
Expect(nativeControls.color == 3, "native color controls were not registered")
Expect(nativeControls.header >= 7, "native section headers were not registered")
Expect(nativeControls.button >= 4, "native action buttons were not registered")
Expect(sharedMediaFonts and sharedMediaFonts > 5, "embedded LibSharedMedia fonts were not discovered")
Expect(sharedMediaTextures and sharedMediaTextures > 1, "embedded LibSharedMedia textures were not discovered")
Expect(RAT.db.fontName == "Friz Quadrata TT", "legacy font name was not migrated")
Expect(RAT.db.outline == "OUTLINE", "legacy custom outline value was not normalized")
Expect(registeredSettings.RAT_BELOW_FOUR_TARGETS ~= nil,
    "the separate below-four-target setting was not registered")
Expect(rangeEventFrame and rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == true,
    "strict target tracking did not activate its own nameplate roster")
registeredSettings.RAT_BELOW_FOUR_TARGETS:SetValue(false)
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == nil,
    "disabling strict target tracking left its own nameplate roster active")
registeredSettings.RAT_BELOW_FOUR_TARGETS:SetValue(true)
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == true,
    "re-enabling strict target tracking did not restore its own nameplate roster")
SetInRangeCount(3)
rangeEventFrame:OnEvent("PLAYER_REGEN_ENABLED")
Expect(RAT._Test.DarkestNightTargetRuleEligible() == true, "three in-range targets were rejected")
SetInRangeCount(4)
rangeEventFrame:OnEvent("PLAYER_REGEN_ENABLED")
Expect(RAT._Test.DarkestNightTargetRuleEligible() == false, "four in-range targets passed the Darkest Night gate")
nameplateState.nameplate4.inRange = nil
rangeEventFrame:OnEvent("PLAYER_REGEN_ENABLED")
Expect(RAT._Test.DarkestNightTargetRuleEligible() == false, "an invalid standalone target snapshot did not fail closed")
SetInRangeCount(1)
rangeEventFrame:OnEvent("PLAYER_REGEN_ENABLED")
for _, variable in ipairs({ "RAT_FONT", "RAT_BACKGROUND_TEXTURE" }) do
    local initializer = nativeDropdowns[variable]
    Expect(initializer and type(initializer.customOptionHandler) == "function",
        variable .. " did not install the scroll handler")
    local root = { SetScrollMode = function(self, extent) self.scrollExtent = extent end }
    initializer.customOptionHandler(root)
    Expect(root.scrollExtent == 300, variable .. " did not enable a bounded scrolling menu")
    Expect(type(initializer.getSelectionTextFunc) == "function",
        variable .. " did not install plain selected-value text")
end
local previewOwner = CreateFrame("Button")
nativeDropdowns.RAT_FONT.data[1].onEnter(previewOwner)
local mediaPreview = namedFrames.RogueApexTrackerMediaPreview
Expect(mediaPreview and mediaPreview.shown == true and mediaPreview.Sample.shown == true,
    "font dropdown hover did not show its font preview")
previewOwner:OnLeave()
Expect(mediaPreview.shown == false, "font preview remained visible after leaving its row")
local dataOnlyOwner = { label = "2002", value = "2002" }
nativeDropdowns.RAT_FONT.data[1].onEnter(dataOnlyOwner)
Expect(mediaPreview.shown == true, "font preview failed for Blizzard's data-table onEnter payload")
mediaPreview:Hide()
nativeDropdowns.RAT_BACKGROUND_TEXTURE.data[1].onEnter(previewOwner)
Expect(mediaPreview.Texture.shown == true and mediaPreview.Texture.texture ~= nil,
    "texture dropdown hover did not show its texture preview")
registeredSettings.RAT_FONT:SetValue("Arial Narrow")
Expect(RAT.db.fontName == "Arial Narrow" and RAT.db.fontPath == "Fonts\\ARIALN.TTF",
    "native font dropdown did not apply its LibSharedMedia path")
registeredSettings.RAT_BACKGROUND_TEXTURE:SetValue("Blizzard")
Expect(RAT.db.backgroundTextureName == "Blizzard"
    and RAT.db.backgroundTexturePath == "Interface\\TargetingFrame\\UI-StatusBar",
    "native texture dropdown did not apply its LibSharedMedia path")
Expect(nativeDropdowns.RAT_OUTLINE.getSelectionTextFunc() == "Outline",
    "font outline dropdown did not expose its selected label")
registeredSettings.RAT_HEADER_COLOR:SetValue("FFFF0000")
Expect(RAT.db.headerColor[1] == 1 and RAT.db.headerColor[2] == 0 and RAT.db.headerColor[3] == 0,
    "native color swatch proxy did not update the runtime color")
registeredSettings.RAT_PREVIEW:SetValue(true)
Expect(RAT:IsPreviewActive() == true, "native preview checkbox did not enable preview")
registeredSettings.RAT_PREVIEW:SetValue(false)
Expect(RAT:IsPreviewActive() == false, "native preview checkbox did not disable preview")
Expect(display.shown == true, "eligible Subtlety Deathstalker did not show the tracker")
Expect(display.fonts[2].text == "ENCOUNTER 0/0  0.0%   SESSION 0/0  0.0%", "initial statistics text drifted")
Expect(eventFrame.events.UNIT_AURA == nil, "tracker registered direct UNIT_AURA traffic")
Expect(eventFrame.OnUpdate == nil, "tracker installed an OnUpdate poll")

eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
darkest:SetActive(true)
local es, ea, ss, sa = RAT:GetStats()
Expect(es == 0 and ea == 0 and ss == 0 and sa == 0, "Darkest Night alone counted a try")

SetInRangeCount(4)
rangeEventFrame:OnEvent("PLAYER_REGEN_ENABLED")
ancient:SetActive(true)
es, ea, ss, sa = RAT:GetStats()
Expect(es == 0 and ea == 0 and ss == 0 and sa == 0,
    "a four-target Darkest Night empowerment was counted")
ancient:SetActive(false)
darkest:SetActive(false)
darkest:SetActive(true)
SetInRangeCount(3)
rangeEventFrame:OnEvent("PLAYER_REGEN_ENABLED")
ancient:SetActive(true)
es, ea, ss, sa = RAT:GetStats()
Expect(es == 0 and ea == 1 and ss == 0 and sa == 1,
    "Ancient Arts after Darkest Night did not count the three-target out-of-Dance miss")
ancient:SetActive(false)
dance:SetActive(true)
es, ea, ss, sa = RAT:GetStats()
Expect(ea == 1 and sa == 1, "Essential cooldown or late Dance counted the same Darkest Night twice")

darkest:SetActive(false)
darkest:SetActive(true)
es, ea, ss, sa = RAT:GetStats()
Expect(ea == 1 and sa == 1, "a new Darkest Night counted before Ancient Arts appeared")
ancient:SetActive(true)
es, ea, ss, sa = RAT:GetStats()
Expect(es == 1 and ea == 2 and ss == 1 and sa == 2,
    "real Shadow Dance did not convert the confirmed APEX IT use into a success")
eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")
es, ea, ss, sa = RAT:GetStats()
Expect(es == 1 and ea == 2 and ss == 1 and sa == 2,
    "PLAYER_LOGIN reset statistics as it would during a UI reload")
Expect(RAT.db.sessionState.encounterAttempts == 2
    and RAT.db.sessionState.sessionAttempts == 2
    and RAT.db.sessionState.sessionSuccesses == 1,
    "live statistics were not persisted for the next UI reload")

now = now + 12
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
Expect(#RAT:GetHistory() == 1, "completed combat was not added to history")
Expect(RAT:GetHistory()[1].successes == 1 and RAT:GetHistory()[1].attempts == 2,
    "history row did not preserve encounter statistics")

darkest:SetActive(false)
ancient:SetActive(false)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
darkest:SetActive(true)
ancient:SetActive(true)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
es, ea, ss, sa = RAT:GetStats()
Expect(es == 1 and ea == 1 and ss == 2 and sa == 3,
    "new encounter reset or session accumulation was incorrect")
Expect(#RAT:GetHistory() == 2, "second combat did not prepend a history row")

RAT:ResetSession()
es, ea, ss, sa = RAT:GetStats()
Expect(es == 0 and ea == 0 and ss == 0 and sa == 0, "session reset did not clear live statistics")
Expect(#RAT:GetHistory() == 2, "session reset incorrectly erased history")
RAT:ClearHistory()
Expect(#RAT:GetHistory() == 0, "clear history did not erase stored rows")

local function TriggerApexUse(inDance)
    darkest:SetActive(false)
    ancient:SetActive(false)
    dance:SetActive(inDance == true)
    darkest:SetActive(true)
    ancient:SetActive(true)
end

eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
eventFrame.OnEvent(eventFrame, "ENCOUNTER_START", 9001, "Test Boss", 8, 5)
TriggerApexUse(true)
now = now + 8
eventFrame.OnEvent(eventFrame, "ENCOUNTER_END", 9001, "Test Boss", 8, 5, 1)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
Expect(#RAT:GetHistoryByType("combat") == 1, "boss combat snapshot was not stored independently")
Expect(#RAT:GetHistoryByType("encounter") == 1, "encounter snapshot was not stored")
Expect(RAT:GetHistoryEntry("encounter", -1).killed == true,
    "encounter result did not preserve the kill flag")

activeChallengeMapID = 399
activeKeystoneLevel = 12
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
TriggerApexUse(true)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
TriggerApexUse(false)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
now = now + 90
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
activeChallengeMapID = nil

local keyRow = RAT:GetHistoryEntry("keystone", -1)
Expect(keyRow and keyRow.mapName == "Ruby Life Pools" and keyRow.level == 12,
    "keystone snapshot did not preserve map and level")
Expect(keyRow.successes == 1 and keyRow.attempts == 2,
    "keystone snapshot did not aggregate multiple combats")
Expect(keyRow.completed == true and keyRow.onTime == true and keyRow.upgradeLevels == 2,
    "keystone completion result was not preserved")
Expect(#RAT:GetHistoryByType("combat") == 3,
    "last-combat snapshots did not remain independent from encounter and keystone snapshots")

RAT:OpenHistory("keystone", -1)
local historyFrame = namedFrames.RogueApexTrackerHistoryFrame
Expect(historyFrame and historyFrame.shown == true, "history browser did not open")
Expect(historyFrame.HistoryDropdown.overrideText == "Last Keystone Dungeon",
    "history browser did not show the selected range")
Expect(historyFrame.SummaryText.text == "APEX IN DANCE  1/2  50.0%",
    "history browser did not render selected keystone statistics")

local historyRoot = NewMenuDescription("root")
RAT._HistoryTest.SetupMenu(nil, historyRoot)
Expect(historyRoot.title == "Select History Range" and historyRoot.scrollExtent == 320,
    "history selector is not a bounded scrollable menu")
local encounterMenu, keystoneMenu
for _, child in ipairs(historyRoot.children) do
    if child.label == "Encounters" then encounterMenu = child end
    if child.label == "Keystone Dungeons" then keystoneMenu = child end
end
Expect(encounterMenu and #encounterMenu.children >= 2,
    "history selector did not expose individual encounters")
Expect(keystoneMenu and #keystoneMenu.children >= 2,
    "history selector did not expose individual keystones")

RAT.db.historyLimit = 1
RAT:NotifySettingsChanged()
Expect(#RAT:GetHistoryByType("combat") == 1 and #RAT:GetHistoryByType("encounter") == 1
    and #RAT:GetHistoryByType("keystone") == 1,
    "history limit was not enforced independently per snapshot type")
RAT.db.historyLimit = 20

RAT:SetPreview(true)
Expect(display.shown == true and display.fonts[2].text == "ENCOUNTER 3/4  75.0%   SESSION 12/15  80.0%",
    "preview did not show sample statistics")
RAT:SetPreview(false)
RAT.db.enabled = false
RAT:NotifySettingsChanged()
Expect(display.shown == false, "disabled tracker remained visible")
Expect(rangeEventFrame.events.NAME_PLATE_UNIT_ADDED == nil,
    "disabled tracker left its standalone nameplate roster active")
SlashCmdList.ROGUEAPEXTRACKER("")
Expect(openedSettingsCategory == 7319, "slash command did not open the registered options category")

local expectedEncounterSuccesses, expectedEncounterAttempts,
    expectedSessionSuccesses, expectedSessionAttempts = RAT:GetStats()
RAT._Test.State.encounterAttempts = 0
RAT._Test.State.encounterSuccesses = 0
RAT._Test.State.sessionAttempts = 0
RAT._Test.State.sessionSuccesses = 0
Expect(RAT._Test.RestoreSessionState() == true,
    "same-client reload did not restore its persisted session")
es, ea, ss, sa = RAT:GetStats()
Expect(es == expectedEncounterSuccesses and ea == expectedEncounterAttempts
    and ss == expectedSessionSuccesses and sa == expectedSessionAttempts,
    "same-client reload restored incorrect statistics")

epochBase = epochBase + 60
Expect(RAT._Test.RestoreSessionState() == false,
    "a new game-client process incorrectly reused the prior session")
es, ea, ss, sa = RAT:GetStats()
Expect(es == 0 and ea == 0 and ss == 0 and sa == 0,
    "a new game-client process did not start a fresh session")

RawPrint(string.format("rogue_apex_tracker_smoke: OK fonts=%d textures=%d",
    sharedMediaFonts or 0, sharedMediaTextures or 0))
