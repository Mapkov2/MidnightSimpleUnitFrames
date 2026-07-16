_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_TargetedSpells.lua"
local handle = io.open(path, "r")
if not handle then path = "UnitFrames/Engine/Group/MSUF_UF_Group_TargetedSpells.lua" else handle:close() end

local conf = { enabled = true, targetedSpellsEnabled = false, targetedSpellsMode = "whenHealing" }
local inGroup = false
local confReads = 0
local eventFrame
local timerCalls = 0
local runtimeObservers = {}
local visibleNameplates = {}
local function NewWidget(parent)
    local widget = { events = {}, parent = parent, children = {}, shown = true, frameLevel = 1, frameStrata = "MEDIUM" }
    if parent and parent.children then parent.children[#parent.children + 1] = widget end
    function widget:RegisterEvent(event) self.events[event] = true end
    function widget:UnregisterEvent(event) self.events[event] = nil end
    function widget:SetScript(kind, script) self[kind] = script end
    function widget:SetAllPoints() end
    function widget:EnableMouse() end
    function widget:SetFrameLevel(level) self.frameLevel = level end
    function widget:GetFrameLevel() return self.frameLevel end
    function widget:SetFrameStrata(strata) self.frameStrata = strata end
    function widget:GetFrameStrata() return self.frameStrata end
    function widget:GetParent() return self.parent end
    function widget:SetParent(newParent) self.parent = newParent end
    function widget:SetSize(width, height) self.width, self.height = width, height end
    function widget:ClearAllPoints() self.point = nil end
    function widget:SetPoint(...) self.point = { ... } end
    function widget:SetShown(shown) self.shown = shown == true end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:IsShown() return self.shown end
    function widget:SetDrawEdge() end
    function widget:SetDrawSwipe() end
    function widget:SetSwipeColor() end
    function widget:SetReverse() end
    function widget:SetHideCountdownNumbers() end
    function widget:SetCooldown(start, duration) self.cooldownStart, self.cooldownDuration = start, duration end
    function widget:Clear() self.cooldownStart, self.cooldownDuration = nil, nil end
    function widget:CreateTexture()
        local texture = {}
        function texture:SetAllPoints() end
        function texture:SetTexCoord() end
        function texture:SetTexture(value) self.texture = value end
        return texture
    end
    return widget
end
local MSUF = {
    GF = {
        GetConf = function()
            confReads = confReads + 1
            return conf
        end,
        RefreshVisuals = function() return true end,
        RebuildAll = function() return true end,
        RegisterRuntimeObserver = function(owner, callback)
            runtimeObservers[owner] = callback
            return true
        end,
    },
    UF = { Layers = {} },
}

_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.CreateFrame = function(_, _, parent)
    local widget = NewWidget(parent)
    if not eventFrame then eventFrame = widget end
    return widget
end
_G.C_Timer = {
    After = function(_, fn)
        timerCalls = timerCalls + 1
        fn()
    end,
}
_G.C_NamePlate = { GetNamePlates = function() return visibleNameplates end }
_G.IsInGroup = function() return inGroup end
_G.IsInRaid = function() return false end
_G.IsInInstance = function() return false end
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationRole = function() return "HEALER" end
_G.UnitExists = function() return false end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitSex = function() return 2 end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetTime = function() return 100 end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local TS = assert(MSUF.GF.TargetedSpells, "targeted-spell runtime missing")
local runtimeObserver = assert(runtimeObservers.targetedSpells, "targeted-spell runtime observer missing")
assert(timerCalls == 1, "targeted-spell runtime must perform one deferred initial config read")
assert(next(eventFrame.events) == nil, "disabled targeted spells must register no runtime events")

conf.targetedSpellsEnabled = true
inGroup = true
confReads = 0
runtimeObserver("refreshVisuals", "party", nil)
assert(confReads == 1, "targeted-spell config refresh must traverse group DB once")
assert(TS.IsActive() == true, "enabled healer-party targeted spells must activate")
assert(eventFrame.events.PLAYER_ENTERING_WORLD == true, "enabled runtime must track world transitions")
assert(eventFrame.events.UNIT_SPELLCAST_START == true, "enabled runtime must track nameplate casts")

visibleNameplates = { { namePlateUnitToken = "nameplate1" } }
runtimeObserver("refreshVisuals", "party", MSUF.GF.DIRTY_ALL)
assert(TS.DebugSnapshot().trackedNameplates == 0, "visual refresh must not reseed targeted-spell nameplates")
runtimeObserver("rebuildAll", nil, MSUF.GF.DIRTY_ALL)
assert(TS.DebugSnapshot().trackedNameplates == 1, "rebuildAll observer must reseed targeted-spell nameplates")

local primary = NewWidget()
primary.unit = "party1"
primary._msufGFKind = "party"
local priority = NewWidget()
priority.unit = "party1"
priority._msufGFKind = "party"
priority._msufGFPriorityFrame = true
MSUF.GF.FrameForUnit = function(unit) return unit == "party1" and primary or nil end
MSUF.GF.priorityUnitFrames = { party1 = { [priority] = true } }
MSUF.GF.ForEachFrameForUnit = function(unit, callback, ...)
    if unit ~= "party1" then return false end
    local handled = callback(primary, unit, ...) == true
    local bucket = MSUF.GF.priorityUnitFrames and MSUF.GF.priorityUnitFrames[unit]
    if bucket and bucket[priority] and callback(priority, unit, ...) == true then handled = true end
    return handled
end

local function ActiveIndicators(frame)
    local holder = frame.MSUFGFTargetedSpellsHolder
    local count = 0
    for i = 1, holder and #holder.children or 0 do
        local icon = holder.children[i]
        if icon._msufTSCaster and icon.shown then count = count + 1 end
    end
    return count
end

local shown, shownUnit = TS.ShowTest("party1", 5)
assert(shown == true and shownUnit == "party1", "targeted-spell test indicator did not resolve party1")
assert(ActiveIndicators(primary) == 1, "targeted spell missing from authoritative Party frame")
assert(ActiveIndicators(priority) == 1, "targeted spell missing from Priority Party copy")
assert(TS.DebugSnapshot().activeCasts == 1, "duplicate indicators must remain one logical active cast")
runtimeObserver("refreshPriority", "party", MSUF.GF.DIRTY_UNIT_BINDING)
assert(ActiveIndicators(primary) == 0 and ActiveIndicators(priority) == 0,
    "Priority header mutation did not immediately release every stale cast copy")
assert(TS.DebugSnapshot().activeCasts == 0 and TS.DebugSnapshot().trackedNameplates == 1,
    "Priority reconciliation did not reset casts and reseed visible nameplates")

priority.shown = false
shown = TS.ShowTest("party1", 5)
assert(shown == true and ActiveIndicators(primary) == 1 and ActiveIndicators(priority) == 0,
    "hidden Priority copies must not retain targeted-spell indicators")
TS.HideTest()

priority.shown = true
MSUF.GF.priorityUnitFrames.party1 = nil
shown = TS.ShowTest("party1", 5)
assert(shown == true and ActiveIndicators(primary) == 1 and ActiveIndicators(priority) == 0,
    "no-duplicate Party path created or retained a Priority indicator")
TS.HideTest()

conf.targetedSpellsEnabled = false
runtimeObserver("rebuildAll")
assert(TS.IsActive() == false, "disabled targeted spells must stop")
assert(next(eventFrame.events) == nil, "disabling targeted spells must unregister every runtime event")

io.write("targeted_spells_smoke: ok\n")
