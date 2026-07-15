local timers = {}
local frames = {}
local unitExists = { boss1 = true }
local unitDead = { boss1 = false }
local unitUnconscious = { boss1 = false }
local invalidations = 0
local bossEnabled = true
local unitExistsReads = 0
local unitDeadReads = 0

_G.MSUF_MAX_BOSS_FRAMES = 1
_G.MAX_BOSS_FRAMES = 1
_G.UIParent = {}
_G.GetTime = function() return 100 end
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.UnitExists = function(unit)
    unitExistsReads = unitExistsReads + 1
    return unitExists[unit] == true
end
_G.UnitIsDeadOrGhost = function(unit)
    unitDeadReads = unitDeadReads + 1
    return unitDead[unit] == true
end
_G.UnitIsUnconscious = function(unit) return unitUnconscious[unit] == true end
_G.C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}

_G.MSUF_DB = {
    general = {
        enableBossCastbar = true,
        bossCastbarDetached = true,
        bossCastbarWidth = 240,
        bossCastbarHeight = 12,
    },
}
_G.EnsureDB = function() end
_G.MSUF_ShouldUseMSUFCastbar = function() return bossEnabled end
_G.MSUF_GetCastbarDesiredSize = function() return 240, 12 end
_G.MSUF_GetCastbarEngine = function()
    return {
        Invalidate = function(_, unit)
            assert(unit == "boss1")
            invalidations = invalidations + 1
        end,
    }
end

local function NewText()
    local text = { value = "" }
    function text:SetText(value) self.value = value or "" end
    return text
end

local function NewBossFrame(name, unit)
    local frame = {
        name = name,
        unit = unit,
        shown = false,
        width = 240,
        height = 12,
        castCalls = 0,
        events = {},
        unitEvents = {},
        unitEventRegisterCounts = {},
        hooks = {},
        statusBar = {},
        timeText = NewText(),
        castText = NewText(),
        latencyBar = { Hide = function(self) self.hidden = true end },
    }

    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, registeredUnit)
        self.unitEvents[event] = registeredUnit
        self.unitEventRegisterCounts[event] = (self.unitEventRegisterCounts[event] or 0) + 1
    end
    function frame:UnregisterEvent(event)
        self.events[event] = nil
        self.unitEvents[event] = nil
    end
    function frame:UnregisterAllEvents()
        self.events = {}
        self.unitEvents = {}
    end
    function frame:HookScript(script, callback)
        assert(script == "OnEvent")
        self.hooks[#self.hooks + 1] = callback
    end
    function frame:Fire(event, eventUnit)
        for index = 1, #self.hooks do
            self.hooks[index](self, event, eventUnit)
        end
    end
    function frame:SetFrameStrata() end
    function frame:SetFrameLevel() end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:GetPoint()
        if not self.point then return nil end
        return unpack(self.point)
    end
    function frame:SetWidth(value) self.width = value end
    function frame:GetWidth() return self.width end
    function frame:SetHeight(value) self.height = value end
    function frame:GetHeight() return self.height end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:Cast()
        self.castCalls = self.castCalls + 1
        if self.castShouldActivate == false then
            self.MSUF_castActive = false
            return
        end
        self.MSUF_castActive = true
        self:Show()
    end

    frames[name] = frame
    _G[name] = frame
    return frame
end

_G.MSUF_CreateCastBar = NewBossFrame

local lifecycleFrame
_G.CreateFrame = function()
    lifecycleFrame = {
        events = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterAllEvents = function(self) self.events = {} end,
        SetScript = function(self, script, callback)
            assert(script == "OnEvent")
            self.OnEvent = callback
        end,
    }
    return lifecycleFrame
end

local namespace = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

local function FindUpvalue(fn, expectedName)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if name == nil then break end
        if name == expectedName then return value end
    end
    return nil
end

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRuntime.lua"))("MSUF", namespace)
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarDriver.lua"))("MSUF", namespace)
local handleDriverEvent = assert(FindUpvalue(_G.MSUF_CreateCastBar, "HandleDriverEvent"),
    "could not reach the real castbar driver event handler")
_G.MSUF_CreateCastBar = NewBossFrame
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_BossCastbars.lua"))("MSUF", namespace)
assert(type(lifecycleFrame.OnEvent) == "function")
lifecycleFrame.OnEvent(lifecycleFrame, "PLAYER_LOGIN")

local boss = assert(_G.MSUF_BossCastbars and _G.MSUF_BossCastbars[1])
assert(boss.events.UNIT_TARGETABLE_CHANGED == true,
    "boss castbar did not subscribe to Blizzard's targetable lifecycle signal")
assert(boss.unitEvents.UNIT_FLAGS == "boss1",
    "boss castbar did not subscribe to the delayed dead-flag lifecycle signal")
assert(boss.unitEvents.UNIT_HEALTH == nil,
    "inactive boss castbar retained persistent UNIT_HEALTH hotpath work")

local setLifecycleActive = assert(_G.MSUF_Castbar_SetLifecycleActive)
assert(setLifecycleActive(boss, true) == true,
    "active boss castbar did not acquire lifecycle ownership")
assert(boss.unitEvents.UNIT_HEALTH == "boss1",
    "active boss castbar did not attach its unit-filtered health signal")
assert(setLifecycleActive(boss, true) == true
    and boss.unitEvents.UNIT_HEALTH == "boss1",
    "repeated active lifecycle registration was not idempotent")
assert(boss.unitEventRegisterCounts.UNIT_HEALTH == 1,
    "active lifecycle registered duplicate boss health signals")
assert(setLifecycleActive(boss, false) == true
    and boss.unitEvents.UNIT_HEALTH == nil,
    "inactive boss castbar retained its active-only health signal")

bossEnabled = false
_G.MSUF_ApplyBossCastbarsEnabled()
assert(next(boss.events) == nil and next(boss.unitEvents) == nil
    and boss._msufBossEventsRegistered == nil,
    "disabled boss castbar retained event ownership")
bossEnabled = true
_G.MSUF_ApplyBossCastbarsEnabled()
assert(boss.events.UNIT_TARGETABLE_CHANGED == true
    and boss.unitEvents.UNIT_FLAGS == "boss1",
    "re-enabled boss castbar did not restore its sparse lifecycle signals")
assert(setLifecycleActive(boss, true) == true
    and boss.unitEvents.UNIT_HEALTH == "boss1"
    and boss.unitEventRegisterCounts.UNIT_HEALTH == 2,
    "re-enabled active boss castbar did not restore exactly one health signal")

-- Execute the real driver path, not just the boss HookScript mock: an active
-- health signal must read only the cheap death flag, stop, and unregister.
boss._msufDriverBackendEnabled = true
local existsReadsBeforeHealth = unitExistsReads
local deadReadsBeforeHealth = unitDeadReads
unitDead.boss1 = true
handleDriverEvent(boss, "UNIT_HEALTH", "boss1")
assert(not boss:IsShown() and boss.MSUF_castActive == false
    and boss.unitEvents.UNIT_HEALTH == nil,
    "active UNIT_HEALTH did not terminally stop and detach the boss castbar")
assert(unitExistsReads == existsReadsBeforeHealth
    and unitDeadReads == deadReadsBeforeHealth + 1,
    "active UNIT_HEALTH performed work beyond its single death-state read")
unitDead.boss1 = false

-- A terminal boss stop must override the short interrupted-feedback hold.
boss:Show()
boss.MSUF_castActive = false
boss.interrupted = true
boss.hideTimer = true
boss._msufHideToken = 11
boss._msufInterruptHideToken = 11
local nativeCompletion = { cancelled = false }
function nativeCompletion:Cancel() self.cancelled = true end
boss._msufNativeCompletionTimer = nativeCompletion
boss._msufNativeCompletionDeadline = 101
unitDead.boss1 = true
boss:Fire("UNIT_FLAGS", "boss1")
assert(not boss:IsShown() and boss.interrupted == nil and boss.MSUF_castActive == false,
    "boss death left interrupted feedback wedged on screen")
assert(nativeCompletion.cancelled and boss._msufNativeCompletionTimer == nil,
    "terminal boss stop hid visuals without cancelling native completion")
unitDead.boss1 = false

boss:Show()
boss.MSUF_castActive = true
boss:Fire("ENCOUNTER_END")
assert(not boss:IsShown() and boss.MSUF_castActive == false,
    "encounter end did not hard-stop the active boss castbar")

-- Boss roster changes are authoritative: a removed unit is stopped, not re-cast.
boss:Show()
boss.MSUF_castActive = true
boss.castCalls = 0
unitExists.boss1 = false
boss:Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
assert(not boss:IsShown() and boss.MSUF_castActive == false and boss.castCalls == 0,
    "missing boss token was refreshed instead of terminally stopped")

-- Healthy targetable changes mirror Blizzard by invalidating and re-querying.
unitExists.boss1 = true
unitDead.boss1 = false
boss.castCalls = 0
local anchorCalls = 0
local updateAnchor = boss.UpdateAnchor
boss.UpdateAnchor = function(self, forceLayout)
    anchorCalls = anchorCalls + 1
    return updateAnchor(self, forceLayout)
end
local invalidationsBefore = invalidations
boss:Fire("UNIT_TARGETABLE_CHANGED", "boss1")
assert(boss.castCalls == 1 and invalidations == invalidationsBefore + 1,
    "healthy targetable change did not force a fresh boss cast query")
assert(anchorCalls == 0, "targetable-only refresh forced unrelated layout work")
local castsBefore = boss.castCalls
boss:Fire("UNIT_TARGETABLE_CHANGED", "target")
assert(boss.castCalls == castsBefore, "unrelated targetable event refreshed boss castbar")

-- An authoritative refresh must clear interrupt feedback even when no cast
-- remains to replace it.
boss:Show()
boss.MSUF_castActive = false
boss.interrupted = true
boss.castShouldActivate = false
castsBefore = boss.castCalls
boss:Fire("UNIT_TARGETABLE_CHANGED", "boss1")
assert(not boss:IsShown() and boss.interrupted == nil and boss.castCalls == castsBefore + 1,
    "inactive targetable refresh left interrupted boss feedback wedged")
boss.castShouldActivate = nil

-- Healthy UNIT_HEALTH is a fight hotpath and must never allocate timer work.
boss:Show()
boss.MSUF_castActive = true
unitDead.boss1 = false
local timerCount = #timers
for _ = 1, 100 do
    boss:Fire("UNIT_HEALTH", "boss1")
    if #timers > timerCount then timers[#timers].callback() end
end
assert(#timers == timerCount, "healthy UNIT_HEALTH created timer churn")
assert(boss:IsShown() and boss.MSUF_castActive == true,
    "healthy UNIT_HEALTH disturbed the active boss cast")

-- UNIT_FLAGS closes the ordering race once the ordinary death flag changes.
unitDead.boss1 = true
boss:Fire("UNIT_FLAGS", "boss1")
assert(not boss:IsShown() and boss.MSUF_castActive == false,
    "delayed UNIT_FLAGS death state did not stop the boss castbar")

unitDead.boss1 = false
unitUnconscious.boss1 = true
boss:Show()
boss.MSUF_castActive = true
boss:Fire("UNIT_FLAGS", "boss1")
assert(not boss:IsShown() and boss.MSUF_castActive == false,
    "UNIT_FLAGS unconscious boss state did not stop the boss castbar")

print("boss castbar lifecycle smoke: ok")
