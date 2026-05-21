-- MSUF_GF_Events.lua
-- Group-frame unit/global event registration and event lifecycle. Split from
-- MSUF_GF_Effects.lua so effects stay focused on visual dispatchers.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local type, pairs = type, pairs
local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitIsUnit = _G.UnitIsUnit
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer

local UNIT_DISPATCH = GF._UnitDispatch or {}

local function _MSUF_ScheduleOnce(key, fn)
    local sched = _G.MSUF_ScheduleOnce
    if sched then return sched(key, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
    if type(fn) == "function" then return fn() end
end

local function _RuntimeEnabledForFrame(f)
    local fn = GF._RuntimeEnabledForFrame
    if type(fn) == "function" then return fn(f) end
    return f and f.unit and UnitExists and UnitExists(f.unit) and true or false
end

local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value and true or false
end

local function UpdateGroupNumber(f, unit)
    local fn = GF.UpdateGroupNumberFrame
    if fn then return fn(f, unit) end
end

local function dispatchName(f, unit)
    local fn = _G.MSUF_GF_DispatchName
    if fn then return fn(f, unit) end
end

local function ApplyHealthColorWithAlpha(f, kind, unit)
    local fn = GF._ApplyHealthColor or _G.MSUF_GF_ApplyHealthColor
    if fn then return fn(f, kind, unit) end
end

local function ApplyPowerColor(f, unit)
    local fn = _G.MSUF_GF_ApplyPowerColor
    if fn then return fn(f, unit) end
end

local function UpdateStatusText(f, unit, forceAway)
    local fn = _G.MSUF_GF_UpdateStatus
    if fn then return fn(f, unit, forceAway) end
end

local function UpdateTargetIndicator(f, unit)
    local fn = _G.MSUF_GF_UpdateTarget
    if fn then return fn(f, unit) end
end

local function _GF_QuickBorderUpdate(f)
    local fn = _G.MSUF_GF_QuickBorderUpdate
    if fn then return fn(f) end
end
local function GF_OnEvent(self, event, unit, ...)
    local u = self and self.unit
    if not u then return end
    if unit ~= nil and unit ~= u then return end

    if self._msufGFEventActive ~= true and not _RuntimeEnabledForFrame(self) then
        if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(self) end
        return
    end
    -- PERF: unified hash-table dispatch. The prior hot-path if-elseif chain
    -- did 6-7 string compares (~1Ã‚Âµs) before falling through to UNIT_DISPATCH.
    -- A direct table lookup is O(1) (~0.05Ã‚Âµs). Net win: ~1Ã‚Âµs per event.
    local fn = UNIT_DISPATCH[event]
    if fn then return fn(self, u, ...) end
end
GF._OnUnitEvent = GF_OnEvent

------------------------------------------------------------------------
-- RegisterUnitEvents / UnregisterUnitEvents (replaces Phase 1 stubs)
------------------------------------------------------------------------
GF._unitEventGroups = GF._unitEventGroups or {
    base = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
    power = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
    range = { "UNIT_IN_RANGE_UPDATE", "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED" },
    threat = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" },
}

function GF._RegisterTrackedUnitEvent(f, unit, regTbl, event)
    f:RegisterUnitEvent(event, unit)
    regTbl[event] = true
end

function GF._RegisterTrackedUnitEventList(f, unit, regTbl, list)
    for i = 1, #list do
        local event = list[i]
        f:RegisterUnitEvent(event, unit)
        regTbl[event] = true
    end
end

function GF._UnregisterTrackedUnitEvents(f)
    local regTbl = f and f._msufGFRegEv
    if not regTbl then return end
    if f.UnregisterEvent then
        for event in pairs(regTbl) do
            f:UnregisterEvent(event)
        end
    end
    f._msufGFRegEv = nil
end

function GF._ShouldRegisterPowerEvents(f, unit, c)
    if not (f and unit and c and c.hasPowerElement) then return false end
    if c.anyPowerText then return true end
    return (GF._PowerBarActiveForUnit and GF._PowerBarActiveForUnit(f, unit, c)) or false
end

function GF.RegisterUnitEvents(f, unit)
    if not (f and unit) then return end
    f._msufGFFullPending = nil

    if not _RuntimeEnabledForFrame(f) then
        if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(f) end
        f._msufGFRegUnit = nil
        f._msufGFRegBits = nil
        f._msufGFEventActive = nil
        return
    end

    if not f._c then GF.BuildFrameCache(f) end
    local c = f._c
    local powerEvents = GF._ShouldRegisterPowerEvents(f, unit, c)

    -- Diff-gate: skip if same unit and same event bitmask
    local evBits = c._evBits or 0
    if not powerEvents then
        if c.hasPowerElement then evBits = evBits - 2 end
        if c.powFrequent then evBits = evBits - 2048 end
    end
    if f._msufGFRegUnit == unit and f._msufGFRegBits == evBits and f._msufGFRegEv then
        return
    end
    if f._msufGFRegUnit ~= unit then
        f._msufGFDispelKnown = nil
    end
    f._msufGFRegUnit = unit
    f._msufGFRegBits = evBits
    f._msufGFLastHealthValue = nil

    -- GUIDÃ¢â€ â€™frame map (rebuilt on roster change, used for O(1) target/focus scan)
    local guid = _G.UnitGUID and _G.UnitGUID(unit)
    if guid and not (issecretvalue and issecretvalue(guid)) then
        local gmap = GF._guidMap
        if not gmap then gmap = {}; GF._guidMap = gmap end
        gmap[guid] = f
    end

    GF._UnregisterTrackedUnitEvents(f)
    local regTbl = {}
    f._msufGFRegEv = regTbl

    GF._RegisterTrackedUnitEventList(f, unit, regTbl, GF._unitEventGroups.base)
    if c.connectionEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_CONNECTION")
    end
    if c.flagsEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_FLAGS")
    end

    if c.nameEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_NAME_UPDATE")
    end
    if powerEvents then
        GF._RegisterTrackedUnitEventList(f, unit, regTbl, GF._unitEventGroups.power)
        if c.powFrequent and UnitIsUnit and _UnsecretBool(UnitIsUnit(unit, "player")) == true then
            GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_POWER_FREQUENT")
        end
    end
    if c.rfEn then
        GF._RegisterTrackedUnitEventList(f, unit, regTbl, GF._unitEventGroups.range)
    end
    if c.needAura then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_AURA")
    end
    if c.needThreat then
        GF._RegisterTrackedUnitEventList(f, unit, regTbl, GF._unitEventGroups.threat)
    end
    if c.summonEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "INCOMING_SUMMON_CHANGED")
    end
    if c.resEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "INCOMING_RESURRECT_CHANGED")
    end
    if c.phaseEn or c.rfEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_PHASE")
    end
    if c.healPredEventEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_HEAL_PREDICTION")
    end
    if c.absorbEventEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_ABSORB_AMOUNT_CHANGED")
    end
    if c.healAbsorbEventEn then
        GF._RegisterTrackedUnitEvent(f, unit, regTbl, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    end

    f:SetScript("OnEvent", GF_OnEvent)
    f._msufGFEventActive = true
end

function GF.UnregisterUnitEvents(f)
    if not f then return end
    GF._UnregisterTrackedUnitEvents(f)
    f:SetScript("OnEvent", nil)
    f._msufGFEventActive = nil
    f._msufGFDispelKnown = nil
    if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
end

------------------------------------------------------------------------
-- Global events (not per-unit)
------------------------------------------------------------------------
local _globalFrame = CreateFrame("Frame")
GF._globalFrame = _globalFrame
_G.MSUF_GF_GlobalEventFrame = _globalFrame

-- Track current target frame for O(1) TARGET_CHANGED updates
local _gfTargetFrame = nil -- the frame whose unit was last "target"
local _gfFocusFrame  = nil -- the frame whose unit was last "focus"

function GF.ForgetEventFrameRefs(f)
    if _gfTargetFrame == f then _gfTargetFrame = nil end
    if _gfFocusFrame == f then _gfFocusFrame = nil end
end

-- PERF: Coalesced GROUP_ROSTER_UPDATE flush (one iteration per burst instead of N).
local _gfRosterPending = false
local function _gfRosterFlushFrame(f, gmap)
    if not f then return end
    if not _RuntimeEnabledForFrame(f) then return end

    local u = f.unit
    if not (u and UnitExists(u)) then
        f._msufGFRosterGUID = nil
        f._msufGFRosterUnit = nil
        f._msufGFRosterRole = nil
        f._msufGFRosterLeaderState = nil
        f._msufGFIsTarget = nil
        f._msufGFIsFocus = nil
        return
    end

    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    local UnitGUID = _G.UnitGUID
    local guid = UnitGUID and UnitGUID(u)
    local hasGUID = guid and not (issecretvalue and issecretvalue(guid))
    if hasGUID then gmap[guid] = f end

    local sameRosterUnit = hasGUID and f._msufGFRosterGUID == guid and f._msufGFRosterUnit == u
    f._msufGFRosterGUID = hasGUID and guid or nil
    f._msufGFRosterUnit = u

    local role
    local roleChanged = false
    if c and c.roleStateEn then
        role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        roleChanged = f._msufGFRosterRole ~= role
        f._msufGFRosterRole = role
    end

    local leaderState
    local leaderChanged = false
    if c and c.leaderEn then
        local isLeader = _G.UnitIsGroupLeader and _G.UnitIsGroupLeader(u)
        local isAssist = _G.UnitIsGroupAssistant and _G.UnitIsGroupAssistant(u)
        leaderState = (isLeader and 1 or 0) + (isAssist and 2 or 0)
        leaderChanged = f._msufGFRosterLeaderState ~= leaderState
        f._msufGFRosterLeaderState = leaderState
    end

    if sameRosterUnit then
        -- Same button/unit after a roster event: skip full visual refresh.
        -- Role, leader/assist and group-number metadata can still change.
        if roleChanged then GF.UpdateRoleIcon(f, u) end
        if leaderChanged then GF.UpdateLeaderIcon(f, u) end
        if (c and c.groupNumberEn)
            or (f._msufGroupNumberFS and f._msufGroupNumberFS:IsShown())
            or (f.groupNumberText and f.groupNumberText:IsShown())
        then
            UpdateGroupNumber(f, u)
        end
    else
        dispatchName(f, u)
        ApplyHealthColorWithAlpha(f, f._msufGFKind or "party", u)
        ApplyPowerColor(f, u)
        if c and (c.statusTextEn or f._msufGFStatusState ~= 0) then UpdateStatusText(f, u) end
        if c and c.roleStateEn then GF.UpdateRoleIcon(f, u) end
        if c and c.raidMarkerEn then GF.UpdateRaidMarker(f, u) end
        if c and c.leaderEn then GF.UpdateLeaderIcon(f, u) end
        if (c and c.groupNumberEn)
            or (f._msufGroupNumberFS and f._msufGroupNumberFS:IsShown())
            or (f.groupNumberText and f.groupNumberText:IsShown())
        then
            UpdateGroupNumber(f, u)
        end
    end

    if not sameRosterUnit then
        UpdateTargetIndicator(f, u)
    end
end

local function _gfRosterFlush()
    -- PERF (4.22 Beta hotfix): _gfRosterPending stays TRUE during the entire
    -- flush body. Any GROUP_ROSTER_UPDATE that fires while we are running
    -- (or, paired with the Scheduler tail-snapshot, fires inside any callback
    -- on the same flush iteration) is dropped instead of re-enqueueing.
    -- The flag is cleared at the END of this function -- the next event after
    -- our work is done can schedule the next flush normally.
    local oldTarget = _gfTargetFrame
    local oldFocus  = _gfFocusFrame
    if oldTarget then oldTarget._msufGFIsTarget = nil end
    if oldFocus then oldFocus._msufGFIsFocus = nil end
    _gfTargetFrame = nil
    _gfFocusFrame  = nil

    -- Rebuild GUID->frame map. GUID changes identify the small subset of
    -- frames that need a full visual refresh after roster churn.
    local gmap = GF._guidMap
    if gmap then
        local wipeFn = _G.wipe
        if wipeFn then wipeFn(gmap) else for k in pairs(gmap) do gmap[k] = nil end end
    else
        gmap = {}
        GF._guidMap = gmap
    end

    local list = GF.frameList
    local count = list and #list or 0
    for i = 1, count do
        _gfRosterFlushFrame(list[i], gmap)
    end
    if not list then
        for f in pairs(GF.frames) do
            _gfRosterFlushFrame(f, gmap)
        end
    end

    local UnitGUID = _G.UnitGUID
    if UnitGUID then
        local tGUID = UnitExists("target") and UnitGUID("target")
        if tGUID and not (issecretvalue and issecretvalue(tGUID)) then
            local f = gmap[tGUID]
            if f and f.unit then
                f._msufGFIsTarget = true
                _gfTargetFrame = f
            end
        end

        local fGUID = UnitExists("focus") and UnitGUID("focus")
        if fGUID and not (issecretvalue and issecretvalue(fGUID)) then
            local f = gmap[fGUID]
            if f and f.unit then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
            end
        end
    end

    if oldTarget ~= _gfTargetFrame then
        if oldTarget and oldTarget.unit then
            UpdateTargetIndicator(oldTarget, oldTarget.unit)
            _GF_QuickBorderUpdate(oldTarget)
        end
        if _gfTargetFrame and _gfTargetFrame.unit then
            UpdateTargetIndicator(_gfTargetFrame, _gfTargetFrame.unit)
            _GF_QuickBorderUpdate(_gfTargetFrame)
        end
    end

    if oldFocus ~= _gfFocusFrame then
        if oldFocus and oldFocus.unit then _GF_QuickBorderUpdate(oldFocus) end
        if _gfFocusFrame and _gfFocusFrame.unit then _GF_QuickBorderUpdate(_gfFocusFrame) end
    end

    -- Pending flag cleared at END (see header comment for rationale).
    _gfRosterPending = false
end

-- Exported for consolidated PLAYER_TARGET_CHANGED handler in UFCore
_G.MSUF_GF_OnTargetChanged = function()
    local oldTarget = _gfTargetFrame
    _gfTargetFrame = nil
    if oldTarget and oldTarget.unit then
        oldTarget._msufGFIsTarget = nil
        _GF_QuickBorderUpdate(oldTarget)
    end
    local tGUID = _G.UnitGUID and _G.UnitGUID("target")
    if tGUID and not (issecretvalue and issecretvalue(tGUID)) then
        local gmap = GF._guidMap
        local f = gmap and gmap[tGUID]
        if f and f.unit then
            f._msufGFIsTarget = true
            _gfTargetFrame = f
            _GF_QuickBorderUpdate(f)
        end
    end
end

-- READY_CHECK / READY_CHECK_FINISHED: update ready check icons
-- RAID_TARGET_UPDATE: update raid markers
function GF._AnyGroupConfFlag(key)
    if not key or not GF.GetConf then return false end
    local party = GF.GetConf("party")
    if party and party.enabled == true and party[key] ~= false then return true end
    local raidKind = (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
    local raid = GF.GetConf(raidKind)
    if raid and raid.enabled == true and raid[key] ~= false then return true end
    if raidKind ~= "raid" then
        raid = GF.GetConf("raid")
        if raid and raid.enabled == true and raid[key] ~= false then return true end
    end
    return false
end

do
    local _globalEventBits
    local _baseEventsActive
    local _globalEventSyncQueued = false
    local BASE_EVENTS = {
        "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE",
        "BARBER_SHOP_OPEN",
        "BARBER_SHOP_CLOSE",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }

    local function SetBaseEvents(active)
        active = active and true or false
        if active == _baseEventsActive then return end
        for i = 1, #BASE_EVENTS do
            local ev = BASE_EVENTS[i]
            if active then
                _globalFrame:RegisterEvent(ev)
            else
                _globalFrame:UnregisterEvent(ev)
            end
        end
        _baseEventsActive = active
    end

    local function _DoSyncGroupGlobalEvents()
        _globalEventSyncQueued = false
        if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
    end

    function GF.RequestSyncGroupGlobalEvents()
        if _globalEventSyncQueued then return end
        _globalEventSyncQueued = true
        _MSUF_ScheduleOnce("GF_GLOBAL_EVENTS_SYNC", _DoSyncGroupGlobalEvents)
    end

    function GF.SyncGroupGlobalEvents()
        if not _globalFrame then return end

        local anyEnabled = true
        if GF.UpdateAnyEnabledFlag then
            anyEnabled = GF.UpdateAnyEnabledFlag() and true or false
        elseif GF._anyEnabled == false then
            anyEnabled = false
        end

        SetBaseEvents(anyEnabled)

        local ready, raidMarker, leader, flags = false, false, false, false
        if anyEnabled then
            ready = GF._AnyGroupConfFlag("readyCheckIcon")
            raidMarker = GF._AnyGroupConfFlag("raidMarker")
            leader = GF._AnyGroupConfFlag("leaderIcon") or GF._AnyGroupConfFlag("assistIcon")
            local showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
            flags = showAFK or showDND or showDead or showGhost
        end

        local bits = 0
        if ready then bits = bits + 1 end
        if raidMarker then bits = bits + 2 end
        if leader then bits = bits + 4 end
        if flags then bits = bits + 8 end
        if bits == _globalEventBits then return end

        local prevBits = _globalEventBits
        _globalEventBits = bits

        local function setEvent(ev, active, bit)
            local wasActive = prevBits and ((prevBits % (bit + bit)) >= bit)
            if wasActive == active then return end
            if active then
                _globalFrame:RegisterEvent(ev)
            else
                _globalFrame:UnregisterEvent(ev)
            end
        end

        setEvent("READY_CHECK", ready, 1)
        setEvent("READY_CHECK_CONFIRM", ready, 1)
        setEvent("READY_CHECK_FINISHED", ready, 1)
        setEvent("RAID_TARGET_UPDATE", raidMarker, 2)
        setEvent("PARTY_LEADER_CHANGED", leader, 4)
        setEvent("PLAYER_FLAGS_CHANGED", flags, 8)
    end
end

-- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
-- OnGlobalEvent: dispatch table + shared frame-iteration helper.
-- (4.22 Beta hotfix.)
--
-- Replaces a long if/elseif chain (8+ string compares per dispatch) with a
-- single hash lookup. The per-event work itself is unchanged -- only the
-- dispatch shape and the duplicated `if list then for i=1,#list else for f
-- in pairs(GF.frames)` boilerplate (5+ identical copies) is consolidated.
--
-- All helpers, per-frame callbacks, and per-event handlers live inside
-- nested do/end blocks so each goes out of scope as soon as its handler
-- closure has captured it. This keeps simultaneously-active locals well
-- below the Lua 5.1 200-per-function limit. The dispatch table and the
-- final OnEvent function are stashed in GF (no new file-scope locals).
-- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
do
    -- Iterate either GF.frameList (preferred ordered list) or GF.frames
    -- (fallback hash). Forwards extra args to the callback. Mirrors the
    -- shape used 5+ times in the previous OnGlobalEvent body.
    local function _ForEachFrame(cb, ...)
        local list = GF.frameList
        if list then
            for i = 1, #list do
                local f = list[i]
                if _RuntimeEnabledForFrame(f) then cb(f, ...) end
            end
        else
            for f in pairs(GF.frames) do
                if _RuntimeEnabledForFrame(f) then cb(f, ...) end
            end
        end
    end

    local H = {}

    -- Events that don't need per-frame iteration: assign anonymous handlers
    -- directly into the dispatch table (no per-handler local).

    H.PLAYER_REGEN_DISABLED = function(_, event)
        _G.MSUF_InCombat = (event == "PLAYER_REGEN_DISABLED")
        local refreshOfflineAlpha = GF._offlineHideRuntimeActive or GF._offlineHideAnyEnabled
        if event == "PLAYER_REGEN_DISABLED" and GF._offlineHideRuntimeActive and GF.SuspendOfflineHideForCombat then
            GF.SuspendOfflineHideForCombat()
        end
        if refreshOfflineAlpha and GF.RefreshGroupAlphas then GF.RefreshGroupAlphas() end
        if event == "PLAYER_REGEN_ENABLED" and GF._offlineHideAnyEnabled and GF.RefreshOfflineHiddenFrames then
            GF.RefreshOfflineHiddenFrames()
        end
    end
    H.PLAYER_REGEN_ENABLED = H.PLAYER_REGEN_DISABLED

    H.PLAYER_FOCUS_CHANGED = function()
        local oldFocus = _gfFocusFrame
        _gfFocusFrame = nil
        if oldFocus and oldFocus.unit then
            oldFocus._msufGFIsFocus = nil
            _GF_QuickBorderUpdate(oldFocus)
        end
        local fGUID = _G.UnitGUID and UnitExists("focus") and _G.UnitGUID("focus")
        if fGUID and not (issecretvalue and issecretvalue(fGUID)) then
            local gmap = GF._guidMap
            local f = gmap and gmap[fGUID]
            if f and f.unit then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
                _GF_QuickBorderUpdate(f)
            end
        end
    end

    H.GROUP_ROSTER_UPDATE = function()
        -- PERF: Coalesce roster updates. At a world boss, GROUP_ROSTER_UPDATE
        -- fires 0.5/sec with 672Ã‚Âµs P50 per call (iterates all 40 GF frames Ãƒâ€” 10 functions).
        -- Multiple updates can fire in the same frame (join + promote + type change).
        -- Coalescing to next-frame eliminates burst spikes in the Blizzard profiler.
        if not _gfRosterPending then
            _gfRosterPending = true
            _MSUF_ScheduleOnce("GF_ROSTER_FLUSH", _gfRosterFlush)
        end
    end

    -- READY_CHECK / READY_CHECK_CONFIRM / READY_CHECK_FINISHED share one
    -- handler. The per-frame CB calls GF.UpdateReadyCheck and is freed
    -- when this nested do/end ends.
    do
        local function CB(f, event)
            local c = f and f._c
            if c and c.readyEn and f.unit then GF.UpdateReadyCheck(f, f.unit, event) end
        end
        local h = function(_, event)
            if not GF._AnyGroupConfFlag("readyCheckIcon") then return end
            _ForEachFrame(CB, event)
        end
        H.READY_CHECK           = h
        H.READY_CHECK_CONFIRM   = h
        H.READY_CHECK_FINISHED  = h
    end

    do
        local function CB(f)
            local c = f and f._c
            if c and c.raidMarkerEn and f.unit and UnitExists(f.unit) then GF.UpdateRaidMarker(f, f.unit) end
        end
        H.RAID_TARGET_UPDATE = function()
            if not GF._AnyGroupConfFlag("raidMarker") then return end
            _ForEachFrame(CB)
        end
    end

    do
        local function CB(f)
            local c = f and f._c
            if c and c.leaderEn and f.unit and UnitExists(f.unit) then GF.UpdateLeaderIcon(f, f.unit) end
        end
        H.PARTY_LEADER_CHANGED = function()
            if not (GF._AnyGroupConfFlag("leaderIcon") or GF._AnyGroupConfFlag("assistIcon")) then return end
            _ForEachFrame(CB)
        end
    end

    -- BARBER_SHOP: hoisted constant `KINDS` was a fresh literal each call
    -- (`for _, k in ipairs({"party","raid"})`).
    do
        local KINDS = { "party", "raid" }
        H.BARBER_SHOP_OPEN = function()
            -- hideInClientScene: hide all GF headers when entering barber/dressing room
            for i = 1, #KINDS do
                local headerKind = KINDS[i]
                local confKind = (headerKind == "raid" and GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or headerKind
                local conf = GF.GetConf(confKind)
                if conf.hideInClientScene ~= false then
                    local header = GF.headers and GF.headers[headerKind]
                    if header and not InCombatLockdown() then
                        header._msufGF_clientSceneHidden = true
                        header:SetAlpha(0)
                    end
                end
            end
        end
        H.BARBER_SHOP_CLOSE = function()
            for i = 1, #KINDS do
                local scope = KINDS[i]
                local header = GF.headers and GF.headers[scope]
                if header and header._msufGF_clientSceneHidden then
                    header._msufGF_clientSceneHidden = nil
                    header:SetAlpha(1)
                end
            end
        end
    end

    do
        local function CB(f, changedUnit)
            local c = f and f._c
            if not (c and c.statusTextEn and f.unit and UnitExists(f.unit)) then return end
            local sameUnit = (f.unit == changedUnit)
            if not sameUnit and UnitIsUnit then
                sameUnit = _UnsecretBool(UnitIsUnit(f.unit, changedUnit)) == true
            end
            if sameUnit then
                UpdateStatusText(f, f.unit, true)
            end
        end
        H.PLAYER_FLAGS_CHANGED = function(_, _, changedUnit)
            local showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
            if not (showAFK or showDND or showDead or showGhost) then return end
            if not changedUnit or changedUnit == "" then changedUnit = "player" end
            _ForEachFrame(CB, changedUnit)
        end
    end

    -- Stash dispatch entry on GF (avoids a new file-scope local).
    GF._OnGlobalEvent = function(self, event, ...)
        -- Fix 3: when GF is fully disabled, do nothing. Saves the per-event
        -- dispatch + empty-loop cost across PLAYER_FOCUS_CHANGED, READY_CHECK*,
        -- RAID_TARGET_UPDATE, PARTY_LEADER_CHANGED, GROUP_ROSTER_UPDATE,
        -- BARBER_SHOP_OPEN/CLOSE, PLAYER_FLAGS_CHANGED. Flag is maintained by
        -- RebuildAll and the PLAYER_REGEN_ENABLED retire-deferral path.
        if GF._anyEnabled == false then return end
        local h = H[event]
        if h then h(self, event, ...) end
    end
end

GF.SyncGroupGlobalEvents()
_globalFrame:SetScript("OnEvent", GF._OnGlobalEvent)

_G.MSUF_GF_OnEvent = GF._OnUnitEvent
