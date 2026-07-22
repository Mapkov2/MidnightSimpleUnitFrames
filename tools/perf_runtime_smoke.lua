_G = _G or _ENV

table.wipe = table.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
_G.wipe = _G.wipe or table.wipe

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local root = "MidnightSimpleUnitFrames/"
if not exists(root .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua") then
    root = ""
end

local function loadAddon(path, MSUF)
    local chunk, err = loadfile(root .. path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function fontString(shown)
    local fs = { shown = shown ~= false }
    function fs:IsShown() return self.shown == true end
    function fs:SetShown(value) self.shown = value == true end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:SetText(value) self.text = value end
    function fs:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
    function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    function fs:SetFont(...) self.font = { ... } end
    function fs:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function fs:SetPoint(...) self.points = { ... } end
    function fs:SetJustifyH(value) self.justifyH = value end
    function fs:SetWidth(value) self.width = value end
    return fs
end

local function region(parent)
    local r = { parent = parent, shown = false }
    function r:IsShown() return self.shown == true end
    function r:SetShown(value) self.shown = value == true end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetAlpha(value) self.alpha = value end
    function r:SetColorTexture(r1, g1, b1, a1) self.colorTexture = { r1, g1, b1, a1 } end
    function r:SetVertexColor(r1, g1, b1, a1) self.vertexColor = { r1, g1, b1, a1 } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(...) self.points = { ... } end
    function r:SetAllPoints(target) self.allPoints = target or true end
    function r:SetHeight(value) self.height = value end
    function r:SetWidth(value) self.width = value end
    function r:SetSize(w, h) self.width, self.height = w, h or w end
    function r:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
    function r:SetValue(value) self.value = value end
    function r:SetStatusBarColor(...) self.statusBarColor = { ... } end
    function r:SetStatusBarTexture(value) self.statusBarTexture = value end
    function r:SetFrameLevel(value) self.frameLevel = value end
    function r:GetFrameLevel() return self.frameLevel or 0 end
    function r:SetFrameStrata(value) self.frameStrata = value end
    function r:GetWidth() return self.width or 0 end
    function r:GetHeight() return self.height or 0 end
    function r:SetParent(value) self.parent = value end
    function r:SetDrawLayer(layer, sub) self.drawLayer, self.subLayer = layer, sub end
    function r:GetParent() return self.parent end
    function r:EnableMouse() end
    function r:SetClampedToScreen(value) self.clampedToScreen = value end
    function r:SetBackdrop(value) self.backdrop = value end
    function r:SetBackdropColor(...) self.backdropColor = { ... } end
    function r:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    function r:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function r:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function r:SetScript(scriptType, script) self.scripts = self.scripts or {}; self.scripts[scriptType] = script; if scriptType == "OnEvent" then self.script = script end end
    function r:CreateTexture()
        local tex = region(self)
        self.createdTextures = (self.createdTextures or 0) + 1
        return tex
    end
    function r:CreateFontString()
        return fontString(true)
    end
    return r
end

local function frame()
    local f = region(nil)
    function f:CreateTexture()
        local tex = region(self)
        self.createdTextures = (self.createdTextures or 0) + 1
        return tex
    end
    return f
end

local function smokeTextRuntime()
    local MSUF = {}
    MSUF.UF = { elements = {}, RegisterElement = function(name, element) MSUF.UF.elements[name] = element end }
    MSUF.Secrets = { IsSecret = function() return false end, IsNil = function(value) return value == nil end }
    MSUF.Apply = {}
    MSUF.UFText = {
        tonumber = tonumber,
        type = type,
        format = string.format,
        floor = math.floor,
        max = math.max,
        abs = math.abs,
        GetTime = function() return 1 end,
        UnitHealth = function() return 100 end,
        UnitHealthMax = function() return 100 end,
        UnitPower = function() return 50 end,
        UnitPowerMax = function() return 100 end,
        UnitPowerType = function() return 0 end,
        UnitHealthPercent = function() return 100 end,
        UnitPowerPercent = function() return 50 end,
        IsSecret = function() return false end,
        IsNil = function(value) return value == nil end,
    }
    _G.MSUF_NS = MSUF
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua", MSUF)
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua", MSUF)

    local groupTextSpec = {
        scope = "group",
        showHealthText = true,
        showPowerText = true,
        power = { enabled = true },
        text = { healthLeft = "CURRENT", powerLeft = "CURRENT" },
    }
    local healthTextEvents = MSUF.UF.elements.HealthText.GetUnitlessEvents({ unit = "party1", MSUFUnitKey = "party1" }, groupTextSpec)
    local foundEnable, foundDisable = false, false
    for _, event in ipairs(healthTextEvents) do
        if event == "PARTY_MEMBER_ENABLE" then foundEnable = true end
        if event == "PARTY_MEMBER_DISABLE" then foundDisable = true end
    end
    assert(foundEnable and foundDisable, "HealthText must join the shared lifecycle health dispatch")
    local powerTextEvents = MSUF.UF.elements.PowerText.GetEvents({ unit = "party1", MSUFUnitKey = "party1" }, groupTextSpec)
    foundEnable, foundDisable = false, false
    for _, event in ipairs(powerTextEvents) do
        if event == "PARTY_MEMBER_ENABLE" then foundEnable = true end
        if event == "PARTY_MEMBER_DISABLE" then foundDisable = true end
    end
    assert(not foundEnable and not foundDisable,
        "PowerText must be a shared lifecycle follower instead of registering the events itself")

    local Text = MSUF.UFText
    local rtFns = assert(Text.RuntimeHotFunctions, "text runtime hot functions missing")
    local f = {
        unit = "player",
        MSUFUnitKey = "player",
        hpTextLeft = fontString(true),
        powerTextLeft = fontString(true),
    }
    local spec = {
        showHealthText = true,
        showPowerText = true,
        power = { enabled = true },
        text = {
            healthLeft = "CURRENT",
            powerLeft = "CURRENT",
            healthThrottle = 0.1,
            powerThrottle = 0.1,
        },
    }
    local rt = Text.CompileTextRuntime(f, spec, spec.text)
    assert(rt.healthHot == rtFns.healthHot, "health hot function was not compiled")
    assert(rt.healthDirty == rtFns.healthDirty, "health dirty function was not compiled")
    assert(rt.powerHot == rtFns.powerHot, "power hot function was not compiled")
    assert(rt.powerDirty == rtFns.powerDirty, "power dirty function was not compiled")

    local expectedSecretNeeds = {
        CURRENT = { true, false, false },
        MAX = { false, true, false },
        CURMAX = { true, true, false },
        MAXCUR = { true, true, false },
        PERCENT = { false, false, true },
        CURPERCENT = { true, false, true },
        PERCENTCUR = { true, false, true },
        CURMAXPERCENT = { true, true, true },
        PERCENTMAXCUR = { true, true, true },
        MAXPERCENT = { false, true, true },
        PERCENTMAX = { false, true, true },
        PERCENTCURMAX = { true, true, true },
    }
    for mode, expected in pairs(expectedSecretNeeds) do
        local slots = {}
        Text.AddTextSlot(slots, 1, fontString(true), mode, "/", false, false, 0)
        local slot = assert(slots[1], "secret text slot was not compiled for " .. mode)
        assert(type(slot.secretSetter) == "function", "secret setter was not precompiled for " .. mode)
        assert((slot.secretNeedsCur == true) == expected[1], "secret current-value flag mismatch for " .. mode)
        assert((slot.secretNeedsMax == true) == expected[2], "secret max-value flag mismatch for " .. mode)
        assert((slot.secretNeedsPct == true) == expected[3], "secret percent flag mismatch for " .. mode)
    end

    local percentSlots = {}
    local percentText = fontString(true)
    Text.AddTextSlot(percentSlots, 1, percentText, "PERCENT", "/", false, false, 0)
    local percentReads = 0
    local function ReadPercent()
        percentReads = percentReads + 1
        return 99
    end
    Text.UpdateTextSlotsSecret(percentSlots, 1, 0, 100, "player", ReadPercent, true, {}, 73, true)
    assert(percentReads == 0 and percentText.text == "73%",
        "secret text path did not reuse the dispatch percent override")
    Text.UpdateTextSlotsSecret(percentSlots, 1, 0, 100, "player", ReadPercent, true, {})
    assert(percentReads == 1 and percentText.text == "99%",
        "secret text path lost its percent API fallback")
end

local function smokeHealthEventSelection()
    local percentReads = 0
    local colorUpdates = 0
    local MSUF = {}
    MSUF.UF = {
        elements = {},
        RegisterElement = function(name, element) MSUF.UF.elements[name] = element end,
    }
    MSUF.UFBarTextCommon = {
        UF = MSUF.UF,
        CreateFrame = function(_, _, parent) return region(parent) end,
        UnitHealth = function() return 50 end,
        UnitHealthMax = function() return 100 end,
        UnitHealthPercent = function()
            percentReads = percentReads + 1
            return 50
        end,
        WHITE = "white",
        SCALE_100 = {},
        SetBarSmoothing = function() end,
        ApplyHealthStatusColor = function()
            colorUpdates = colorUpdates + 1
        end,
    }
    _G.issecretvalue = function() return false end
    _G.MSUF_NS = MSUF
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua", MSUF)

    local Health = assert(MSUF.UF.elements.Health, "health element missing")
    local f = frame()
    f.unit = "target"
    f.MSUFUnitKey = "target"
    f.hpBar = region(f)
    f.MSUFSpec = { scope = "single", health = { mode = "gradient" } }

    Health.Update(f, "UNIT_HEALTH", "target")
    assert(percentReads == 1 and colorUpdates == 1,
        "direct gradient Health.Update must preserve spec-based recoloring before Apply")

    f.MSUFSpec.health.mode = "class"
    local updateFlags = Health.SelectEventUpdate(f, f.MSUFSpec, "UNIT_FLAGS")
    assert(type(updateFlags) == "function", "UNIT_FLAGS color-only selector missing")
    local readsBefore = percentReads
    updateFlags(f, "UNIT_FLAGS", "target")
    assert(percentReads == readsBefore and colorUpdates == 2,
        "UNIT_FLAGS must recolor without a redundant health-value read")
    assert(Health.SelectEventUpdate(f, f.MSUFSpec, "UNIT_CONNECTION") == nil,
        "UNIT_CONNECTION must retain the full health update")
end

local function smokeGroupRuntime()
    local MSUF = {}
    MSUF.UF = {
        elements = {},
        RegisterElement = function(name, element) MSUF.UF.elements[name] = element end,
        IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
        ReadConnectedCached = function() return true, true end,
        ReadDeadCached = function() return false, true end,
    }
    MSUF.GF = {}
    MSUF.Secrets = { IsSecret = function() return false end, IsNil = function(value) return value == nil end, UnitMissing = function() return false end }
    MSUF.UFStatusRuntime = {}
    local statusTextUpdates = 0
    local statusDead = false
    for _, key in ipairs({
        "UpdateRaidMarker", "UpdateLeaderPair", "UpdateReadyCheck", "UpdateSummon",
        "UpdateIncomingRes", "UpdatePhase", "UpdateStatusText", "UpdateRaidGroup", "UpdateRole",
    }) do
        MSUF.UFStatusRuntime[key] = function() end
    end
    MSUF.UFStatusRuntime.UpdateStatusText = function(frame)
        statusTextUpdates = statusTextUpdates + 1
        frame._statusTextUpdates = (frame._statusTextUpdates or 0) + 1
        frame._msufStatusTextValue = statusDead and "DEAD" or nil
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_DB = { general = {}, gf_party = {} }
    _G.GetTime = function() return 1 end
    _G.GetNumGroupMembers = function() return 5 end
    _G.GetRaidRosterInfo = function() return nil end
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    _G.UnitGUID = function(unit) return unit end
    _G.UnitHealth = function() return 100 end
    _G.UnitHealthMax = function() return 100 end
    _G.UnitHealthPercent = function() return 100 end
    _G.UnitThreatSituation = function() return 1 end
    _G.UnitIsDeadOrGhost = function() return statusDead end
    _G.UnitIsConnected = function() return true end
    local afkReads, dndReads = 0, 0
    _G.UnitIsAFK = function()
        afkReads = afkReads + 1
        return false
    end
    _G.UnitIsDND = function()
        dndReads = dndReads + 1
        return false
    end
    local statusTickerCreates = 0
    _G.C_Timer = {
        NewTicker = function()
            statusTickerCreates = statusTickerCreates + 1
        end,
    }
    local createdFrames = {}
    _G.CreateFrame = function(_, _, parent)
        local holder = frame()
        holder.parent = parent
        createdFrames[#createdFrames + 1] = holder
        return holder
    end

    local conf = {
        healthFadeEnabled = true,
        deadBgEnabled = true,
        targetIndicator = true,
        hlFocusEnabled = true,
        ciEnabled = true,
        ciSlotBR = "aggro",
        statusText = true,
        statusGhostText = true,
        statusAFKText = true,
        hlOverride = true,
        enableAbsorbBar = false,
        healAbsorbEnabled = true,
        healPredEnabled = false,
        healAbsorbAnchorMode = 2,
        absorbBarHeight = 7,
        absorbBarOffsetY = -2,
        healAbsorbBarHeight = 5,
        healAbsorbBarOffsetY = 3,
        showPowerText = true,
    }
    _G.MSUF_PredictionTestModes = { party = { absorb = true } }
    MSUF.GF.GetConf = function() return conf end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua", MSUF)
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua", MSUF)

    local nativeOverlayOnly = { scope = "group", group = { dispelOverlayEnabled = true } }
    assert(MSUF.UF.elements.GroupVisuals.IsEnabled(nil, nativeOverlayOnly) == false,
        "native GroupSlots dispel overlay retained the retired GroupVisuals owner")
    local legacyStripeOnly = { scope = "group", group = { debuffStripeEnabled = true } }
    assert(MSUF.UF.elements.GroupVisuals.IsEnabled(nil, legacyStripeOnly) == true,
        "legacy debuff stripe lost its GroupVisuals owner")

    local f = frame()
    f.unit = "party1"
    f.MSUFUnitKey = "party1"
    f._msufIsGroupFrame = true
    f.hpBar = region(f)
    f.hpText = fontString(true)
    f.hpTextLeft = fontString(true)
    f.hpTextCenter = fontString(true)
    f.hpTextRight = fontString(true)
    f.bg = region(f)
    f.hpBarBG = region(f)
    f.MSUFSpec = MSUF.GF.CompileSpec("party", f, "party1")
    local prediction = f.MSUFSpec.prediction
    assert(prediction.absorb == true and prediction.absorbTest == true,
        "positive absorb test was not compiled for the selected scope")
    assert(prediction.healAbsorb == true and prediction.healAbsorbTest == false,
        "negative absorb remained coupled to the disabled positive live option")
    assert(prediction.heal == false and prediction.healTest == false,
        "positive absorb test leaked into heal prediction")
    assert(prediction.healAbsorbAnchorMode == 2 and prediction.absorbHeight == 7
        and prediction.absorbOffsetY == -2 and prediction.healAbsorbHeight == 5
        and prediction.healAbsorbOffsetY == 3,
        "scope-aware prediction geometry was not cold-compiled")
    _G.MSUF_PredictionTestModes = nil

    local groupRole = "DAMAGER"
    MSUF.GF.GetUnitGroupRole = function() return groupRole end
    MSUF.GF.GetEffectivePowerHeight = function(_, _, role)
        return role == "DAMAGER" and 0 or 6
    end
    local roleFrame = frame()
    roleFrame.MSUFUnitKey = "party2"
    local roleSpec = MSUF.GF.CompileSpec("party", roleFrame, "party2")
    assert(roleSpec.power.enabled == false and roleSpec.showPowerText == false,
        "DPS power-off retained PowerText runtime ownership")
    groupRole = "HEALER"
    roleSpec = MSUF.GF.CompileSpec("party", roleFrame, "party2")
    assert(roleSpec.power.enabled == true and roleSpec.showPowerText == true,
        "healer power-on did not restore PowerText runtime ownership")

    local hasStatusHealthEvent, hasPartyEnable, hasPartyDisable = false, false, false
    for _, event in ipairs(f.MSUFSpec.status.groupRuntimeEvents or {}) do
        if event == "UNIT_HEALTH" then hasStatusHealthEvent = true end
        if event == "PARTY_MEMBER_ENABLE" then hasPartyEnable = true end
        if event == "PARTY_MEMBER_DISABLE" then hasPartyDisable = true end
    end
    assert(not hasStatusHealthEvent, "status text must reuse the health element event instead of adding a handler")
    assert(not hasPartyEnable and not hasPartyDisable,
        "group status must reuse the shared lifecycle plan instead of adding duplicate handlers")

    MSUF.UF.elements.GroupStatusRuntime.Apply(f)
    assert(type(f.MSUFSpec.status.runtimeDispatch) == "table", "status runtimeDispatch missing")
    assert(statusTickerCreates == 0, "group status must not create a polling ticker")

    local flagsPeer = frame()
    flagsPeer.MSUFUnitKey = "party2"
    flagsPeer.MSUFSpec = MSUF.GF.CompileSpec("party", flagsPeer, "party2")
    f._msufActiveElements = { GroupStatusRuntime = true }
    flagsPeer._msufActiveElements = { GroupStatusRuntime = true }
    MSUF.GF.frames = { [f] = true, [flagsPeer] = true }
    MSUF.GF.FrameForUnit = function(unit)
        if unit == "party1" then return f end
        if unit == "party2" then return flagsPeer end
    end
    MSUF.UF.elements.GroupStatusRuntime.Apply(flagsPeer)
    local statusDriver
    for i = 1, #createdFrames do
        local candidate = createdFrames[i]
        if candidate.events and candidate.events.PLAYER_FLAGS_CHANGED then
            statusDriver = candidate
            break
        end
    end
    assert(statusDriver and type(statusDriver.script) == "function",
        "shared group status driver missing")
    local targetFlagsBefore = f._statusTextUpdates or 0
    local peerFlagsBefore = flagsPeer._statusTextUpdates or 0
    statusDriver.script(statusDriver, "PLAYER_FLAGS_CHANGED", "party1")
    assert((f._statusTextUpdates or 0) == targetFlagsBefore + 1
        and (flagsPeer._statusTextUpdates or 0) == peerFlagsBefore,
        "PLAYER_FLAGS_CHANGED broadcast beyond its indexed group unit")

    local statusUpdatesBeforeHealth = statusTextUpdates
    MSUF.UF.elements.Health.Update(f, "UNIT_HEALTH", "party1")
    assert(statusTextUpdates == statusUpdatesBeforeHealth,
        "ordinary living health must not enter the group status resolver")
    assert(afkReads == 0 and dndReads == 0,
        "UNIT_HEALTH must not reread AFK/DND flags")
    f._msufStatusTextValue = "DEAD"
    MSUF.UF.elements.Health.Update(f, "UNIT_HEALTH", "party1")
    assert(statusTextUpdates == statusUpdatesBeforeHealth + 1 and f._msufStatusTextValue == nil,
        "positive group health must recover a stale gone status")
    local statusUpdatesBeforeFlags = statusTextUpdates
    MSUF.UF.elements.GroupStatusRuntime.UpdateState(f, "UNIT_FLAGS", "party1")
    assert(statusTextUpdates == statusUpdatesBeforeFlags + 1,
        "UNIT_FLAGS must reach the shared status resolver")

    MSUF.UF.elements.GroupVisuals.Apply(f)
    assert(type(f.MSUFSpec.group.runtimeOnHealth) == "function", "group runtimeOnHealth missing")
    assert(type(f.MSUFSpec.group.runtimeOnTarget) == "function", "group runtimeOnTarget missing")
    assert(type(f.MSUFSpec.group.runtimeOnFocus) == "function", "group runtimeOnFocus missing")
    assert(type(f.MSUFSpec.group.runtimeOnRangeAlpha) == "function", "group runtimeOnRangeAlpha missing")
    assert(f._msufUpdateGroupVisualsHealthValue == nil, "unused group-health bridge must not be allocated per frame")
    assert(f._msufUpdateGroupVisualsGoneState == MSUF.UF.elements.GroupVisuals.UpdateGoneState, "gone-state bridge must reuse one shared function")
    local visualEnable, visualDisable = false, false
    for _, event in ipairs(MSUF.UF.elements.GroupVisuals.GetEvents(f, f.MSUFSpec)) do
        if event == "PARTY_MEMBER_ENABLE" then visualEnable = true end
        if event == "PARTY_MEMBER_DISABLE" then visualDisable = true end
    end
    assert(not visualEnable and not visualDisable,
        "group visuals must be a shared lifecycle follower instead of registering the events itself")

    statusDead = true
    MSUF.UF.elements.GroupStatusRuntime.UpdateState(f, "MSUF_TEST", "party1")
    assert(statusTickerCreates == 0,
        "group status recovery must remain fully event-driven")
    f.PARTY_MEMBER_ENABLE = function(self)
        MSUF.UF.elements.GroupStatusRuntime.UpdateState(self, "PARTY_MEMBER_ENABLE", self.MSUFUnitKey)
    end
    statusDead = false
    f:PARTY_MEMBER_ENABLE("PARTY_MEMBER_ENABLE", "party1")
    assert(f._msufStatusTextValue == nil and statusTickerCreates == 0,
        "the party lifecycle event must clear a stale DEAD state without polling")

    MSUF.UF.elements.GroupCornerIndicators.Apply(f)
    assert(type(f.MSUFSpec.cornerIndicators.runtimeThreat) == "function", "corner runtimeThreat missing")

    local GF = MSUF.GF
    local base = GF.CompileSpec("party")
    local serial = base._msufGFCompileSerial
    local health, border, group, corner = base.health, base.border, base.group, base.cornerIndicators
    local textColorRevision = base._msufTextColorRevision
    conf.healthColorMode = "custom"
    conf.healthCustomR = 0.27
    conf.borderR = 0.31
    conf.deadBgR = 0.43
    conf.deadBgEnabled = false
    conf.deadBgOffline = false
    conf.ciAggroColorR = 0.57
    _G.MSUF_DB.general.highlightEnabled = false
    GF.ResolveBarTexture = function() return "Interface\\TargetingFrame\\UI-StatusBar" end
    GF.ResolveBarBgTexture = function() return "Interface\\Buttons\\WHITE8X8" end
    GF.ResolveFontColor = function() return 0.11, 0.22, 0.33 end
    assert(GF.RefreshCompiledSpecDomains("party", GF.DIRTY_COLOR) == true, "color domain refresh should use the soft path")
    local colorSpec = GF.CompileSpec("party", f, "party1")
    assert(GF.CompileSpec("party") == base and base._msufGFCompileSerial == serial, "color refresh must preserve the structural base and serial")
    assert(base.health == health and base.border == border and base.group == group and base.cornerIndicators == corner, "color refresh must preserve shared domain-table identities")
    assert(base.health.r == 0.27 and base.border.r == 0.31 and base.group.deadBgR == 0.43 and base.cornerIndicators.aggroR == 0.57, "color domain values were not refreshed")
    assert(base.texture == "Interface\\TargetingFrame\\UI-StatusBar" and colorSpec.texture == base.texture
        and base.health.texture == base.texture and base.power.texture == base.texture
        and base.prediction.texture == base.texture, "color reset did not refresh group bar/prediction textures")
    assert(base.backgroundTexture == "Interface\\Buttons\\WHITE8X8" and colorSpec.backgroundTexture == base.backgroundTexture
        and base.health.backgroundTexture == base.backgroundTexture
        and base.power.backgroundTexture == base.backgroundTexture, "color reset did not refresh group background textures")
    assert(base.group.deadBgEnabled == false and base.group.deadBgOffline == false
        and base.group.hoverHighlightEnabled == false, "color reset left group visual enable-state stale")
    assert(colorSpec._msufTextColorRevision == base._msufTextColorRevision and base._msufTextColorRevision > textColorRevision, "frame color revision did not follow the soft refresh")

    local textLayoutRevision = base._msufTextLayoutRevision
    conf.nameFontSize = 17
    GF.ResolveFontPath = function() return "Fonts\\ARIALN.TTF" end
    assert(GF.RefreshCompiledSpecDomains("party", GF.DIRTY_FONT) == true, "font domain refresh should use the soft path")
    local fontSpec = GF.CompileSpec("party", f, "party1")
    assert(fontSpec == colorSpec and fontSpec.font == "Fonts\\ARIALN.TTF" and fontSpec.nameFontSize == 17, "font domain did not patch the existing frame spec")
    assert(base._msufTextLayoutRevision > textLayoutRevision and base._msufGFCompileSerial == serial, "font refresh must only advance its text revision")
    assert(GF.RefreshCompiledSpecDomains("party", GF.DIRTY_VISUAL) == false, "structural visual dirtiness must reject the soft path")
end

local function smokeGroupHeaderLayoutCountFallback()
    local MSUF = {}
    MSUF.GF = {}
    MSUF.Secrets = { IsSecret = function() return false end, UnitMissing = function() return false end }

    local groupCount = 0
    local seenCounts = {}
    local unpackValues = table.unpack or unpack

    local function testFrame(name, parent)
        local f = frame()
        f.name = name
        f.parent = parent
        f.children = {}
        f.attributes = {}
        function f:SetParent(value) self.parent = value end
        function f:GetParent() return self.parent end
        function f:IsShown() return self.shown == true end
        function f:SetAttribute(key, value) self.attributes[key] = value end
        function f:GetAttribute(key) return self.attributes[key] end
        function f:GetChildren() return unpackValues(self.children) end
        if parent and parent.children then
            parent.children[#parent.children + 1] = f
        end
        return f
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.UIParent = testFrame("UIParent")
    _G.InCombatLockdown = function() return false end
    _G.GetNumGroupMembers = function() return groupCount end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.CreateFrame = function(_, name, parent)
        return testFrame(name, parent)
    end

    local conf = {
        growth = "DOWN",
        showPlayer = true,
        showSolo = false,
        unitsPerColumn = 5,
        maxColumns = 8,
        point = "CENTER",
        offsetX = 0,
        offsetY = 0,
    }
    MSUF.GF.EnsureDB = function() end
    MSUF.GF.GetConf = function() return conf end
    MSUF.GF.GetScaledFrameMetrics = function() return 80, 32, 1 end
    MSUF.GF.GetGridMetrics = function(_, count)
        seenCounts[#seenCounts + 1] = count
        return 0, 0, count, count
    end
    local scanCalls = {}
    local rebindBegins, rebindEnds = 0, 0
    MSUF.GF.ScheduleScan = function(key, kind)
        scanCalls[#scanCalls + 1] = { key = key, kind = kind }
    end
    MSUF.GF.BeginHeaderLayoutRebind = function()
        rebindBegins = rebindBegins + 1
        return true
    end
    MSUF.GF.EndHeaderLayoutRebind = function()
        rebindEnds = rebindEnds + 1
        return true
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua", MSUF)

    groupCount = 0
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 10, "unknown raid count should use bounded fallback")
    assert(#scanCalls == 1, "new raid header should scan once")
    MSUF.GF.headers.raid:Show()

    groupCount = 4
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 4, "positive raid count should pass through")
    assert(#scanCalls == 2, "visible raid topology change should rescan once")
    assert(rebindBegins == 1 and rebindEnds == 1,
        "visible header hide/show did not bracket its synchronous rescan")

    groupCount = 0
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 4, "small last-known raid count should be reused")

    groupCount = 25
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 25, "large positive raid count should pass through")

    conf.preserveRaidGroups = true
    conf.maxColumns = 4
    groupCount = 23
    MSUF.GF.SetupHeader("raid", "raid")
    assert(MSUF.GF.headers.raid.attributes.maxColumns == 4, "preserved raid groups must honor the configured group cap")
    conf.preserveRaidGroups = false
    conf.maxColumns = 8

    groupCount = 0
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 10, "large stale raid count should clamp to bounded fallback")

    local scanCallsBeforeForce = #scanCalls
    MSUF.GF._forceScanHeaders = true
    MSUF.GF.SetupHeader("raid", "raid")
    assert(#scanCalls == scanCallsBeforeForce + 1, "roster-forced raid header should rescan unchanged children")
end

local function smokeGroupRuntimeRosterModes()
    local MSUF = {}
    MSUF.GF = { headers = {} }
    MSUF.UF = {}
    MSUF.Secrets = { IsSecret = function() return false end }

    local inGroup = true
    local inRaid = false
    local partyConf = { enabled = true, showSolo = true, showPlayer = true }
    local raidConf = { enabled = true }
    local setupCalls = {}
    local scanCalls = {}
    local retireCalls = {}
    local actions = {}
    local eventFrame
    local combat = false
    local stateRefreshes = {}
    local cornerRefreshes = {}
    local groupFrames = {
        { unit = "party1", MSUFUnitKey = "party1", kind = "party", shown = true },
        { unit = "party2", MSUFUnitKey = "party2", kind = "party", shown = false },
        { unit = "raid1", MSUFUnitKey = "raid1", kind = "raid", shown = true },
    }

    MSUF.UF.RefreshGroupFrameState = function(groupFrame, reason)
        stateRefreshes[#stateRefreshes + 1] = { groupFrame = groupFrame, reason = reason }
        return true
    end
    MSUF.GF.ForEachFrame = function(fn, includeHidden, a, b, c)
        local any = false
        for i = 1, #groupFrames do
            local groupFrame = groupFrames[i]
            if includeHidden == true or groupFrame.shown == true then
                any = fn(groupFrame, groupFrame.unit, groupFrame.kind, a, b, c) or any
            end
        end
        return any
    end
    MSUF.GF.RefreshCornerThreatState = function(reason)
        cornerRefreshes[#cornerRefreshes + 1] = reason
        return true
    end

    local function eventHost()
        local f = frame()
        f.events = {}
        function f:SetScript(_, script) self.script = script end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        return f
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.InCombatLockdown = function() return combat end
    _G.IsInGroup = function() return inGroup end
    _G.IsInRaid = function() return inRaid end
    _G.CreateFrame = function()
        eventFrame = eventHost()
        return eventFrame
    end

    MSUF.GF.EnsureDB = function() end
    MSUF.GF.GetConf = function(kind)
        if kind == "party" then return partyConf end
        return raidConf
    end
    MSUF.GF.GetLiveRaidKind = function() return "raid" end
    MSUF.GF.InvalidateCompiledSpecs = function() end
    MSUF.GF.ApplyBlizzardGroupFrameOwnership = function() end
    MSUF.GF.SetupHeader = function(key, kind)
        setupCalls[#setupCalls + 1] = { key = key, kind = kind, forced = MSUF.GF._forceRecreateHeaders == true }
        actions[#actions + 1] = "setup:" .. key
        local header = { _msufGFKind = kind, shown = false }
        function header:Show() self.shown = true end
        function header:Hide() self.shown = false end
        MSUF.GF.headers[key] = header
        return header
    end
    MSUF.GF.ScheduleScan = function(key, kind)
        scanCalls[#scanCalls + 1] = { key = key, kind = kind }
        return true
    end
    MSUF.GF.RetireHeader = function(key)
        retireCalls[#retireCalls + 1] = key
        actions[#actions + 1] = "retire:" .. key
        MSUF.GF.headers[key] = nil
        return true
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua", MSUF)
    assert(eventFrame and eventFrame.script, "group runtime event frame missing")

    raidConf.offsetX, raidConf.offsetY = 10, 20
    combat = true
    assert(MSUF.GF.EM2_NudgePreview("gf_raid", 5, 5) == true, "combat group nudge should be consumed")
    assert(raidConf.offsetX == 10 and raidConf.offsetY == 20, "combat group nudge must not change offsets")
    combat = false

    eventFrame.script(eventFrame, "PLAYER_LOGIN")
    assert(setupCalls[#setupCalls].key == "party", "party should be active while grouped")

    inGroup = false
    local scansBeforeRoster = #scanCalls
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(setupCalls[#setupCalls].key == "party", "solo party should stay active when showSolo is enabled")
    assert(#scanCalls == scansBeforeRoster + 1, "roster refresh should scan the active header exactly once")
    assert(#stateRefreshes == 1 and stateRefreshes[1].groupFrame == groupFrames[1],
        "roster catch-up must refresh only visible party frames")

    partyConf.showSolo = false
    local retireActionStart = #actions
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(actions[retireActionStart + 1] == "retire:party", "solo party should retire when showSolo is disabled")

    partyConf.showSolo = true
    inGroup = true
    inRaid = true
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(setupCalls[#setupCalls].key == "raid", "raid should be active after party to raid")

    inRaid = false
    local actionStart = #actions
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(setupCalls[#setupCalls].key == "party", "party should be active after raid to party")
    assert(actions[actionStart + 1] == "setup:party", "party should setup during raid-to-party transition")
    assert(actions[actionStart + 2] == "retire:raid", "raid should retire during raid-to-party transition")

    combat = true
    local setupBeforeCombatRoster = #setupCalls
    local refreshBeforeCombatRoster = #stateRefreshes
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(#setupCalls == setupBeforeCombatRoster, "combat roster should not rebuild immediately")
    assert(MSUF.GF._pendingGroupRuntime == true and MSUF.GF._pendingGroupRuntimeReason == "roster", "combat roster should defer group runtime")
    assert(#stateRefreshes == refreshBeforeCombatRoster,
        "combat roster must not run the visual catch-up before regen")

    combat = false
    eventFrame.script(eventFrame, "PLAYER_REGEN_ENABLED")
    assert(#setupCalls > setupBeforeCombatRoster, "deferred combat roster should rebuild after combat")
    assert(#stateRefreshes == refreshBeforeCombatRoster + 1,
        "deferred roster must catch up visible party state exactly once after combat")
    assert(#cornerRefreshes == 1 and cornerRefreshes[1] == "PLAYER_REGEN_ENABLED",
        "group runtime must route combat-exit corner cleanup through its shared regen owner")
end

local function smokeGroupRuntimeRefreshOwnership()
    local MSUF = {
        GF = { headers = {} },
        UF = {},
    }
    local appliedMasks = {}
    local frames = {
        { unit = "party1", MSUFUnitKey = "party1", _msufGFKind = "party" },
        { unit = "party2", MSUFUnitKey = "party2", _msufGFKind = "party" },
    }
    local eventFrame
    local combat = false
    local invalidations, domainRefreshes = 0, 0

    MSUF.UF.IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end
    MSUF.UF.ApplySpec = function(_, _, _, mask)
        appliedMasks[#appliedMasks + 1] = mask
        return true
    end
    MSUF.GF.CompileSpec = function() return {} end
    MSUF.GF.InvalidateCompiledSpecs = function() invalidations = invalidations + 1 end
    MSUF.GF.GetConf = function() return { enabled = false } end
    MSUF.GF.ForEachFrame = function(fn, includeHidden, a, b, c)
        local any = false
        for i = 1, #frames do
            local groupFrame = frames[i]
            any = fn(groupFrame, groupFrame.unit, groupFrame._msufGFKind, a, b, c) or any
        end
        return any
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.InCombatLockdown = function() return combat end
    _G.IsInGroup = function() return false end
    _G.IsInRaid = function() return false end
    _G.CreateFrame = function()
        eventFrame = frame()
        return eventFrame
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua", MSUF)

    local GF = MSUF.GF
    local combined = GF.DIRTY_FONT + GF.DIRTY_COLOR
    GF.RefreshCompiledSpecDomains = function(_, mask)
        domainRefreshes = domainRefreshes + 1
        return mask == combined
    end
    local firstMask = GF.ApplyMaskForDirtyMask(combined)
    assert(firstMask == GF.ApplyMaskForDirtyMask(combined), "combined group apply masks must be cached")

    local refreshOwner = GF.RefreshVisuals
    local rebuildOwner = GF.RebuildAll
    local notifications = {}
    assert(GF.RegisterRuntimeObserver("smoke", function(operation, kind, mask, result)
        notifications[#notifications + 1] = { operation, kind, mask, result }
    end) == true, "group runtime observer should register")

    assert(GF.RefreshVisuals("party", combined) == true, "group visual refresh should apply frames")
    assert(domainRefreshes == 1 and invalidations == 0, "soft group domains must bypass structural cache invalidation")
    assert(#appliedMasks == 2, "group visual refresh should visit each matching frame")
    assert(appliedMasks[1] == firstMask and appliedMasks[2] == firstMask, "one immutable apply mask must serve the whole refresh")
    assert(notifications[1][1] == "refreshVisuals" and notifications[1][2] == "party", "visual refresh observer payload mismatch")

    assert(GF.RebuildAll() == true, "group rebuild should complete")
    assert(invalidations == 1, "explicit group rebuild must still invalidate structural specs")
    assert(notifications[2][1] == "rebuildAll", "rebuild observer payload mismatch")

    combat = true
    local appliedBeforeDeferred = #appliedMasks
    assert(GF.RefreshVisuals("party", combined) == false, "combat visual refresh should defer")
    assert(#notifications == 2, "deferred refresh must not notify before a runtime mutation")
    assert(#appliedMasks == appliedBeforeDeferred, "deferred refresh must not apply frames in combat")
    combat = false
    eventFrame.script(eventFrame, "PLAYER_REGEN_ENABLED")
    assert(#notifications == 3 and notifications[3][1] == "refreshVisuals", "deferred refresh should notify once after combat")
    assert(#appliedMasks == appliedBeforeDeferred + 2, "deferred refresh should apply each frame once after combat")

    combat = true
    local notificationsBeforeRebuild = #notifications
    local appliedBeforeRebuild = #appliedMasks
    assert(GF.RebuildAll() == false, "combat rebuild should defer")
    assert(#notifications == notificationsBeforeRebuild, "deferred rebuild must not notify before a runtime mutation")
    combat = false
    eventFrame.script(eventFrame, "PLAYER_REGEN_ENABLED")
    assert(#notifications == notificationsBeforeRebuild + 1, "deferred rebuild should notify exactly once after combat")
    assert(notifications[#notifications][1] == "rebuildAll", "deferred global rebuild must preserve rebuildAll observer semantics")
    assert(notifications[#notifications][3] == GF.DIRTY_ALL, "deferred global rebuild observer must carry DIRTY_ALL")
    assert(#appliedMasks == appliedBeforeRebuild + 2, "deferred global rebuild must apply one visual pass after combat")

    assert(GF.RefreshVisuals == refreshOwner and GF.RebuildAll == rebuildOwner, "group runtime must retain sole function ownership")
    assert(GF.UnregisterRuntimeObserver("smoke") == true, "group runtime observer should unregister")
end

local function smokeGroupEM2CombatFallback()
    local MSUF = {}
    MSUF.UF = { frames = {} }
    local runtimeObserver
    MSUF.GF = {
        _previewActive = {},
        _previewLayoutFrame = {},
        GetConf = function(kind)
            if kind == "party" then
                return {
                    enabled = true,
                    showSolo = true,
                    showPlayer = true,
                    offsetX = -400,
                    offsetY = 0,
                    width = 120,
                    height = 40,
                    anchorPoint = "CENTER",
                }
            end
            return { enabled = false }
        end,
        GetGridMetrics = function()
            return 0, 0, 120, 40
        end,
        GetPositionCount = function() return 1 end,
        RegisterRuntimeObserver = function(owner, callback)
            if owner == "em2" then runtimeObserver = callback end
            return true
        end,
    }

    local nativeShow, nativeHide, nativeAnchor, nativeRefresh = 0, 0, 0, 0
    function MSUF.GF.SetPreviewAnchor() nativeAnchor = nativeAnchor + 1; return true end
    function MSUF.GF.ShowPreview() nativeShow = nativeShow + 1; return false end
    function MSUF.GF.HidePreview() nativeHide = nativeHide + 1; return true end
    function MSUF.GF.RefreshPreviewLayout() nativeRefresh = nativeRefresh + 1; return false end

    local registered = {}
    local initFrame
    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_EM2 = {
        Registry = {
            Register = function(cfg) registered[cfg.key] = cfg end,
        },
        State = {
            IsActive = function() return true end,
            GetUnitKey = function() return "gf_party" end,
        },
        Movers = {
            Show = function() end,
            SyncAll = function() end,
        },
        Ticker = {
            IsDragging = function() return false end,
        },
    }
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.UIParent = frame()
    _G.UIParent:SetSize(1920, 1080)
    _G.InCombatLockdown = function() return true end
    _G.MSUF_IsConfigCombatLocked = function() return true end
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return true end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.GetNumGroupMembers = function() return 0 end
    _G.CreateFrame = function(_, _, parent)
        local f = frame()
        f:SetParent(parent)
        initFrame = initFrame or f
        return f
    end
    _G.hooksecurefunc = function() end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua", MSUF)
    assert(initFrame and initFrame.script, "group EM2 init frame missing")
    initFrame.script(initFrame, "PLAYER_LOGIN")
    assert(type(runtimeObserver) == "function", "group EM2 runtime observer missing")

    local cfg = registered.gf_party
    assert(cfg and type(cfg.getFrame) == "function", "group EM2 party mover not registered")
    local fallback = cfg.getFrame()
    assert(fallback == nil or fallback:IsShown() == false, "combat edit mode must not move or show a group drag proxy")
    assert(nativeShow == 0, "combat edit mode must not create native group preview")
    assert(nativeHide > 0, "combat edit mode should hard-hide stale group previews")
    assert(nativeAnchor == 0, "combat edit mode must not retarget native preview anchors")
    assert(nativeRefresh == 0, "combat edit mode must not refresh native group preview")
end

local function smokeGroupEM2LiveRaidUsesRuntimeAnchor()
    local MSUF = {}
    MSUF.UF = { frames = {} }

    local liveAnchor = frame()
    liveAnchor:SetSize(320, 160)
    liveAnchor:Show()
    function liveAnchor:GetLeft() return 100 end
    function liveAnchor:GetRight() return 420 end
    function liveAnchor:GetTop() return 700 end
    function liveAnchor:GetBottom() return 540 end

    MSUF.GF = {
        anchors = { raid = liveAnchor },
        headers = {},
        _previewActive = {},
        _previewLayoutFrame = {},
        GetLiveRaidKind = function() return "raid" end,
        GetConf = function(kind)
            if kind == "raid" then
                return {
                    enabled = true,
                    offsetX = -500,
                    offsetY = 0,
                    width = 80,
                    height = 32,
                    anchorPoint = "CENTER",
                }
            end
            return { enabled = false }
        end,
        GetGridMetrics = function()
            return 0, 0, 320, 160
        end,
        GetPositionCount = function() return 23 end,
    }

    local nativeShow, nativeHide, nativeAnchor, visibility = 0, 0, 0, 0
    function MSUF.GF.SetPreviewAnchor() nativeAnchor = nativeAnchor + 1; return true end
    function MSUF.GF.ShowPreview() nativeShow = nativeShow + 1; return true end
    function MSUF.GF.HidePreview() nativeHide = nativeHide + 1; return true end
    function MSUF.GF.RefreshPreviewLayout() return true end
    function MSUF.GF.UpdateGroupVisibility() visibility = visibility + 1; return true end

    local registered = {}
    local initFrame
    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_EM2 = {
        Registry = {
            Register = function(cfg) registered[cfg.key] = cfg end,
            Get = function(key) return registered[key] end,
        },
        State = {
            IsActive = function() return true end,
            GetUnitKey = function() return "gf_raid" end,
            SetUnitKey = function() end,
        },
        Movers = {
            Show = function() end,
            SyncAll = function() end,
            Get = function() return frame() end,
        },
        Ticker = {
            IsDragging = function() return false end,
            BeginDrag = function() end,
            EndDrag = function() return true end,
        },
    }
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.UIParent = frame()
    _G.UIParent:SetSize(1920, 1080)
    _G.InCombatLockdown = function() return false end
    _G.MSUF_IsConfigCombatLocked = function() return false end
    _G.IsInRaid = function() return true end
    _G.IsInGroup = function() return true end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.GetNumGroupMembers = function() return 23 end
    _G.CreateFrame = function(_, _, parent)
        local f = frame()
        f:SetParent(parent)
        initFrame = initFrame or f
        return f
    end
    _G.hooksecurefunc = function() end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua", MSUF)
    assert(initFrame and initFrame.script, "group EM2 init frame missing")
    initFrame.script(initFrame, "PLAYER_LOGIN")

    local cfg = registered.gf_raid
    assert(cfg and type(cfg.getFrame) == "function", "group EM2 raid mover not registered")
    local dragFrame = cfg.getFrame()
    assert(dragFrame ~= liveAnchor, "live raid edit mode should use a non-secure drag proxy")
    assert(dragFrame._msufGFLiveAnchor == liveAnchor, "live raid drag proxy should track the runtime anchor")
    assert(dragFrame.scripts and dragFrame.scripts.OnMouseUp, "live raid drag proxy should use frame-safe mouse-up clicks")
    assert(not dragFrame.scripts.OnClick, "live raid drag proxy must not install Button-only OnClick")
    assert(nativeShow == 0, "live raid edit mode should not build dummy raid preview")
    assert(nativeHide > 0, "live raid edit mode should clear dummy raid preview state")
    assert(nativeAnchor > 0, "live raid edit mode should clear native preview anchors")
    assert(visibility > 0, "live raid edit mode should keep live secure headers visible")
end

local function smokeCastbarPreviewHardHide()
    _G.MSUF_DB = {
        general = {
            castbarPlayerPreviewEnabled = true,
            playerCastbarTestMode = true,
            targetCastbarTestMode = true,
            focusCastbarTestMode = true,
            bossCastbarTestMode = true,
        },
    }
    _G.MSUF_NS = {}
    _G.MSUF_InCombat = false
    _G.InCombatLockdown = function() return false end
    _G.UnitAffectingCombat = function() return false end

    local function castbarPreview()
        local f = frame()
        f.MSUF_testMode = true
        f._msufTestActive = true
        f.MSUF_testStart = 1
        f.MSUF_testDur = 4
        f.statusBar = region(f)
        local tex = region(f.statusBar)
        function f.statusBar:GetStatusBarTexture() return tex end
        f.timeText = fontString(true)
        f.latencyBar = region(f)
        f:Show()
        return f
    end

    _G.MSUF_PlayerCastbarPreview = castbarPreview()
    _G.MSUF_TargetCastbarPreview = castbarPreview()
    _G.MSUF_FocusCastbarPreview = castbarPreview()
    _G.MSUF_BossCastbarPreview = castbarPreview()
    _G.MSUF_BossCastbarPreview2 = castbarPreview()

    loadAddon("Castbars/MSUF_CastbarPreviews.lua", _G.MSUF_NS)
    assert(type(_G.MSUF_HideAllCastbarPreviews) == "function", "castbar hard-hide helper missing")
    _G.MSUF_HideAllCastbarPreviews()

    local g = _G.MSUF_DB.general
    assert(g.castbarPlayerPreviewEnabled == false, "castbar preview flag should clear")
    assert(g.playerCastbarTestMode == false and g.bossCastbarTestMode == false, "castbar test flags should clear")
    assert(_G.MSUF_PlayerCastbarPreview:IsShown() == false, "player castbar preview should hide")
    assert(_G.MSUF_TargetCastbarPreview:IsShown() == false, "target castbar preview should hide")
    assert(_G.MSUF_FocusCastbarPreview:IsShown() == false, "focus castbar preview should hide")
    assert(_G.MSUF_BossCastbarPreview:IsShown() == false, "boss castbar preview should hide")
    assert(_G.MSUF_BossCastbarPreview2:IsShown() == false, "extra boss castbar preview should hide")
end

smokeTextRuntime()
smokeHealthEventSelection()
smokeGroupRuntime()
smokeGroupHeaderLayoutCountFallback()
smokeGroupRuntimeRosterModes()
smokeGroupRuntimeRefreshOwnership()
smokeGroupEM2LiveRaidUsesRuntimeAnchor()
smokeGroupEM2CombatFallback()
smokeCastbarPreviewHardHide()

print("perf runtime smoke ok")
