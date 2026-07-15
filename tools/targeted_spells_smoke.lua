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
_G.CreateFrame = function()
    eventFrame = { events = {} }
    function eventFrame:RegisterEvent(event) self.events[event] = true end
    function eventFrame:UnregisterEvent(event) self.events[event] = nil end
    function eventFrame:SetScript(kind, script) self[kind] = script end
    return eventFrame
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

conf.targetedSpellsEnabled = false
runtimeObserver("rebuildAll")
assert(TS.IsActive() == false, "disabled targeted spells must stop")
assert(next(eventFrame.events) == nil, "disabling targeted spells must unregister every runtime event")

io.write("targeted_spells_smoke: ok\n")
