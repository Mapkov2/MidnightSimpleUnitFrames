-- Cold lifecycle for the optional resource helpers; the disabled default owns
-- no events. Spec, form and displayed-power changes rebuild the helpers on
-- their own, also while Class Resources are off and the class power refresh
-- does not run for them. In combat the helpers only hide or show what they
-- drew; the rebuild follows at combat end.
local _, MSUF = ...
MSUF.CPBuilders = MSUF.CPBuilders or {}

-- The one list of switches that need a helper. The class power controller and
-- its config ask it too. Profiles saved under the former key names are moved to
-- the current ones by the profile translator (MSUF.ProfileNormalize in
-- State/MSUF_ProfileNormalize.lua) at login, switch and import.
function MSUF.CPBuilders.ResourceExtrasWanted(b)
    return type(b) == "table" and (b.showIgnorePain == true or b.showArcaneWindow == true
        or b.manaUpcomingCost == true or b.manaRegenPause == true or b.manaGainPulse == true
        or (type(b.resourceMarks) == "table" and #b.resourceMarks > 0)) or false
end

function MSUF.CPBuilders.ResourceExtras(E)
    local helpers = {}
    local events = CreateFrame("Frame")
    local disabled, queued = false, false
    local Refresh, Disable
    local function InCombat() return InCombatLockdown and InCombatLockdown() end
    local function RefreshHelper(key, wanted)
        if wanted and not helpers[key] and MSUF.CPBuilders[key] then helpers[key] = MSUF.CPBuilders[key](E) end
        local helper = helpers[key]
        if helper then if wanted then helper.Refresh() else helper.Disable() end end
    end
    local function AnyPending()
        for _, helper in pairs(helpers) do
            if helper.IsPending and helper.IsPending() then return true end
        end
        return false
    end
    Refresh = function()
        disabled = false
        if InCombat() then
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        local b = E.db.bars or {}
        events:UnregisterAllEvents()
        if MSUF.ResourceVisibility then MSUF.ResourceVisibility.ClearExtras() end
        RefreshHelper("ExtraAuras", b.showIgnorePain == true or b.showArcaneWindow == true)
        RefreshHelper("ManaExtras", b.manaUpcomingCost == true or b.manaRegenPause == true or b.manaGainPulse == true)
        RefreshHelper("ResourceMarks", type(b.resourceMarks) == "table" and #b.resourceMarks > 0)
        if MSUF.CPBuilders.ResourceExtrasWanted(b) then
            events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
            events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
            if not E.SupportsEvent or E.SupportsEvent("PLAYER_SPECIALIZATION_CHANGED") then
                events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
            end
        end
        -- The Arcane window's global cooldown count follows spell haste.
        local auras = helpers.ExtraAuras
        if auras and auras.UsesHaste and auras.UsesHaste() then events:RegisterUnitEvent("UNIT_SPELL_HASTE", "player") end
        if AnyPending() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end
    Disable = function()
        disabled = true
        if MSUF.ResourceVisibility then MSUF.ResourceVisibility.ClearExtras() end
        events:UnregisterAllEvents()
        for _, helper in pairs(helpers) do helper.Disable() end
        -- An aura sensor cannot be parked in combat; finish at combat end.
        if AnyPending() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end
    -- One frame later, so MSUF's power element has handled the same event.
    local function ColdChange()
        queued = false
        if disabled then return end
        if InCombat() then
            for _, helper in pairs(helpers) do
                if helper.PowerChanged then helper.PowerChanged() end
            end
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            Refresh()
        end
    end
    E.RequestRefresh = function()
        if queued or disabled then return end
        queued = true
        C_Timer.After(0, ColdChange)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if disabled then Disable() else Refresh() end
        elseif event == "UNIT_SPELL_HASTE" then
            if helpers.ExtraAuras then helpers.ExtraAuras.RefreshHaste() end
        else
            E.RequestRefresh()
        end
    end)
    return { Refresh = Refresh, Disable = Disable }
end

-- Isolated sample state binds the live painters once. It never joins the live
-- extras coordinator, ResourceVisibility, Edit Mode listeners or event bus.
local Auxiliary = {}
Auxiliary.__index = Auxiliary
local function NoSampleEvent() end
local SAMPLE_MANA_CLASSES = { DRUID = true, MONK = true, PALADIN = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, EVOKER = true, HUNTER = MSUF.Client.IsClassic or MSUF.Client.IsForever }
function MSUF.CPBuilders.SampleHasMana(class) return SAMPLE_MANA_CLASSES[class] == true end
local SAMPLE_EVENTS = { RegisterEvent = NoSampleEvent, RegisterUnitEvent = NoSampleEvent,
    UnregisterAllEvents = NoSampleEvent, UnregisterEvent = NoSampleEvent, SetScript = NoSampleEvent }
local function SampleFrame(kind, _, parent, template) return CreateFrame(kind, nil, parent, template) end
function MSUF.CPBuilders.NewAuxiliarySurface(owner)
    local self = setmetatable({ owner = owner, CP = {}, PHP = {}, AM = {}, db = {}, sample = {}, auraSamples = {}, ownership = {} }, Auxiliary)
    local constants = MSUF.Require("MSUF_CP_CONST", "ClassPower/ResourceExtras")
    local powerColor = MSUF.Require("MSUF_GetPowerBarColor", "ClassPower/ResourceExtras")
    local common = MSUF.UFBarTextCommon
    local sampleCommon = setmetatable({}, { __index = common })
    sampleCommon.ClassColor = function() return common.ClassColorForToken(self.class, true) end
    sampleCommon.GradientColor = function()
        return common.PreviewHealthGradientColor(self.owner.MSUFSpec.health, self.sample.hp)
    end
    sampleCommon.ApplyHealthStatusColor = function(bar)
        bar:SetStatusBarColor(self.owner.hpBar:GetStatusBarColor())
    end
    local env = { sample = true, CP = self.CP, PHP = self.PHP, AM = self.AM, _cpDB = self.db, db = self.db,
        Common = sampleCommon, Ownership = self.ownership, events = SAMPLE_EVENTS, CreateFrame = SampleFrame, NotSecret = MSUF.Secrets.NotSecret,
        PT = constants.PT, Enum = Enum, RAID_CLASS_COLORS = RAID_CLASS_COLORS,
        ResolveTexture = MSUF.ClassPowerConfig.ResolveTexture, Texture = MSUF.ClassPowerConfig.ResolveTexture,
        GetPlayerFrame = function() return self.owner end,
        PlayerConfig = function() return self.player, MSUF_DB.general end,
        UnitHealth = function() return self.sample.hp * 1000000 end,
        UnitHealthMax = function() return 1000000 end,
        UnitHealthPercent = function() return self.sample.hp * 100 end,
        UnitClass = function() return self.class, self.class end,
        UnitPower = function() return self.sample.mana * 100 end,
        UnitPowerMax = function(_, power)
            if power == constants.PT.Mana then return MSUF.CPBuilders.SampleHasMana(self.class) and 100 or 0 end
            return power == self.CP.powerType and self.classMaximum or 100
        end,
        UnitPowerType = function() return self.powerType, self.powerToken end,
        UnitPowerPercent = function() return self.sample.power end,
        Read = function(view)
            if view.classResource then return self.classCount / math.max(1, self.classMaximum) end
            local lo, hi = view.bar:GetMinMaxValues()
            return (view.bar:GetValue() - lo) / math.max(1, hi - lo)
        end,
        ResolveClassPowerColor = function() return powerColor(0, "MANA") end,
        GetBarTexture = function() return MSUF.ClassPowerConfig.ResolveTexture(nil) end,
        GetSpec = function() return self.specIndex end,
    }
    env.SensorAPI = function()
        return { CreateClassPowerAuraSensor = function(host, key, _, initialize)
            local sample = self.auraSamples[key] or { duration = 15, remaining = 7.8 }
            self.auraSamples[key] = sample
            local button = MSUF.MSUF_Auras3.MockAuraPainter.NewNativeSample(host, sample)
            initialize(button)
            return { SetEnabled = NoSampleEvent }
        end }
    end
    self.compileConfig = MSUF.ClassPowerConfig.CreateCompiler(self.db)
    self.env = env
    local core = constants.BuilderRegistry("MSUF_CP_CORE_BUILDERS")
    self.health, self.mana = core.PLAYER_HP_VISUAL(env), core.ALT_MANA(env)
    self.manaExtras, self.marks = MSUF.CPBuilders.ManaExtras(env), MSUF.CPBuilders.ResourceMarks(env)
    return self
end
function Auxiliary:Configure(owner, cp, bars, player, class, specIndex, count, maximum, powerType, powerToken, outline)
    self.compileConfig()
    self.owner, self.player, self.class, self.specIndex = owner, player, class, specIndex
    local copy = self.bars or {}
    self.bars = copy
    for key in pairs(copy) do copy[key] = nil end
    for key, value in pairs(bars) do copy[key] = value end
    if outline == false then copy.playerHPBarOutline = 0 end
    self.db.bars = copy
    self.db.colorByType = bars.classPowerColorByType ~= false
    if self.ebonColors then self.ebonColors.InvalidateCaches() end
    if self.ebonCP then self.ebonCP._pf, self.ebonCP.container = owner, self.CP.container end
    for key in pairs(self.CP) do self.CP[key] = nil end
    for key, value in pairs(cp or {}) do self.CP[key] = value end
    self.CP.bars = self.CP.bars or {}
    self.classCount, self.classMaximum = count or 0, maximum or 1
    self.powerType, self.powerToken = powerType or 0, powerToken or "MANA"
    self.ownership.playerManaOverride = (player.playerPowerSource == "MANA" or player._msufResourceExtraMana == true)
        and MSUF.CPBuilders.SampleHasMana(class)
    self.ownership.augEvoker = class == "EVOKER" and specIndex == 3 and bars.showClassPower ~= false and bars.showEbonMight ~= false
end
function Auxiliary:PaintHP(fraction)
    self.sample.hp = fraction
    if not self.db.bars.playerHPBarEnabled then self.health.Hide() return nil end
    self.health.Create(self.owner)
    self.health.Layout(self.owner)
    self.health.Update("FULL_REFRESH")
    return self.PHP.frame, self.PHP
end
function Auxiliary:PaintMana(fraction)
    self.sample.mana = fraction
    if not self.db.bars.showAltMana or not self.mana.NeedsAltManaBar() then
        self.AM.visible = false
        if self.AM.container then self.AM.container:Hide() end
        return nil
    end
    self.mana.AM_Create(self.owner)
    self.mana.AM_Layout(self.owner)
    self.mana.AM_ApplyColor()
    self.mana.AM_UpdateValue()
    self.mana.AM_RefreshTexture()
    self.AM.visible = true
    self.AM.container:Show()
    return self.AM.container
end
function Auxiliary:PaintExtras(pain, arcane, seconds, soul)
    if self.auras then self.auras.Disable() end
    local b = self.db.bars
    local frames = self.frames or {}
    self.frames = frames
    for key, frame in pairs(frames) do frame._sampleActive = false frames[key] = nil end
    if pain or arcane then
        if not self.auras then self.auras = MSUF.CPBuilders.ExtraAuras(self.env) end
        local key = pain and "PAIN" or soul and "SOUL" or "ARCANE"
        self.auras.Sample(key, 0)
        local state = self.auras.States[key]
        local sample = state.button.sample
        sample.duration, sample.remaining = pain and 12 or soul and 10 or 15, pain and 7.8 or seconds or 3.8
        state.button:SetSample(sample)
        state.host._sampleActive, state.host._sampleLayer = true, "extras"
        frames[key] = state.host
    end
    self.manaExtras.HideSample()
    local power = self.AM.visible and self.AM.bar or self.owner.targetPowerBar
    if power and (self.AM.visible or self.powerType == 0) then
        for key, bar in pairs(self.manaExtras.PaintSample(power) or {}) do
            bar._sampleActive, bar._sampleLayer = bar:IsShown(), "power"
            if bar:IsShown() then frames[key] = bar end
        end
    end
    self.marks.Refresh()
    return frames
end
function Auxiliary:PaintEbon(enabled, remaining, duration)
    if not enabled then
        if self.ebon then self.ebon.SetActive(false) end
        return nil
    end
    local owner, host = self.owner, self.owner.targetPowerBar
    if not self.ebon then
        local constants = MSUF.Require("MSUF_CP_CONST", "ClassPower/ResourceExtras")
        local core = constants.BuilderRegistry("MSUF_CP_CORE_BUILDERS")
        local cp = { _pf = owner, container = self.CP.container }
        self.ebonCP, self.ebonSample = cp, { duration = duration, remaining = remaining }
        cp.GetEbonTextLevel = MSUF.ClassPowerConfig.CreatePowerTextLevel(cp)
        local colors = core.CONTROLLER_COLORS({ scene = true, _cpDB = self.db, POWER_TYPE_TOKENS = constants.POWER_TYPE_TOKENS })
        self.ebonColors = colors
        local style = core.CREATE_EBON_STYLE(cp, self.db, colors.ResolveClassPowerColor)
        self.ebon = core.EBON_MIGHT({ sample = true, CP = cp, EBON = constants.EBON, CreateFrame = SampleFrame,
            GetHost = function() return self.owner.targetPowerBar end, GetStyle = style, GetTextLevel = cp.GetEbonTextLevel,
            CreateSensor = function(parent, _, _, initialize)
                local button = MSUF.MSUF_Auras3.MockAuraPainter.NewNativeSample(parent, self.ebonSample)
                button.SetEnabled = NoSampleEvent
                initialize(button)
                return button
            end,
        })
    end
    self.ebonSample.duration, self.ebonSample.remaining = duration, remaining
    self.ebon.SetActive(true)
    self.ebonCP.ebonButton:SetSample(self.ebonSample)
    host:SetValue(0)
    for _, text in ipairs({ owner.powerTextLeft, owner.powerTextCenter, owner.powerText }) do if text then text:Hide() end end
    return self.ebonCP.ebonNativeText
end
function Auxiliary:TickHP(fraction)
    self.sample.hp = fraction
    self.health.Update("UNIT_HEALTH")
end
function Auxiliary:Hide()
    self.health.Hide()
    if self.AM.container then self.AM.container:Hide() end
    if self.auras then self.auras.Disable() end
    self.manaExtras.HideSample()
    if self.ebon then self.ebon.SetActive(false) end
    self.marks.Disable()
end
