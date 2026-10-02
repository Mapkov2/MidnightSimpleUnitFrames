--- Classic aura backend selected before the Retail 12.1 AuraContainer backend.
--- Classic Era, TBC Classic and MoP Classic expose the C_UnitAuras/AuraUtil scan contract
--- used here, while Classic does not ship the Retail native aura-container runtime.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
--- Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua
--- The Auras element of the delta-first Classic backend: per-frame UNIT_AURA
--- and identity dispatch, the frame's compiled config, enable and disable,
--- group roster and faction follow-ups, and the element's event lists.
---
--- Runtime ownership:
--- * Menu_Model writes SavedVariables and invalidates runtime config.
--- * EditMode builds fake preview groups and drag handles only.
--- * The backend files own live aura state, full scans, UNIT_AURA deltas,
---   button pools, and frame-level aura visuals for unit and group frames.
---
--- Keep gameplay aura work in the backend and keep menu/edit code out of
--- UNIT_AURA paths. Aura scans are one of the most expensive frame events in
--- MSUF, so new logic should either compile into lane config or run behind
--- the existing delta/full scan split.
---
--- Game/<Flavor>/Auras.xml loads the unit-frame aura backend after Compile.lua
--- in this order: Buttons, Filters, FrameVisuals, Lanes, UnitFrames, Requests.
--- Each file imports the earlier ones from A3._ClassicBackend at load time.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
local Backend = type(A3) == "table" and A3._ClassicBackend
if not Backend or not Backend.Lanes or Backend.Element then return end
local Compile = A3._ClassicCompile
local Lanes, FrameVisuals = Backend.Lanes, Backend.FrameVisuals

local UF = MSUF.UF
local type, tonumber, pairs, next = type, tonumber, pairs, next
local CreateFrame = _G.CreateFrame
local UnitExists = _G.UnitExists
local UnitInRange = _G.UnitInRange
local IsSecret = _G.issecretvalue or function() return false end

local MANAGED_UNITS = Compile.MANAGED_UNITS
local NormalizeRuntimeUnit = Compile.NormalizeRuntimeUnit
local IsGroupFrame = Compile.IsGroupFrame
local ResolveGroupFrameConfig = Compile.ResolveGroupFrameConfig
local FrameAuraConfig = Compile.FrameAuraConfig
local BindFrameUnit = Compile.BindFrameUnit
local BASE_LANE_ORDER = Compile.BASE_LANE_ORDER
local AuraRuntimeCombatBlocked = Compile.AuraRuntimeCombatBlocked
local TokenSerial = Backend.Filters.TokenSerial
local EMPTY_LANES = Lanes.EMPTY_LANES
local EnsureState = Lanes.EnsureState
local ApplyConfig = Lanes.ApplyConfig
local HideState = Lanes.HideState
local ClearLane = Lanes.ClearLane
local RenderLane = Lanes.RenderLane
local UpdateAuraLaneRuntime = Lanes.UpdateAuraLaneRuntime
local ClearFrameAuraVisualState = FrameVisuals.ClearFrameAuraVisualState
local FrameHasAuraVisualState = FrameVisuals.FrameHasAuraVisualState
local UpdateFrameAuraVisualState = FrameVisuals.UpdateFrameAuraVisualState

local EMPTY_EVENTS = {}
local COMBAT_AURA_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local function EmptyAuraPayload(updateInfo)
    return updateInfo and not updateInfo.isFullUpdate
        and not updateInfo.addedAuras
        and not updateInfo.updatedAuraInstanceIDs
        and not updateInfo.removedAuraInstanceIDs
end

local function ConfigHasEnabledAuraLane(cfg)
    local lanes = cfg and cfg.lanes
    for _, lane in pairs(lanes or EMPTY_LANES) do
        if lane and lane.enabled == true then return true end
    end
    return false
end

--- The member behind a unit token, as a plain string, or nil. Classic has no
--- secret GUIDs; a secret one would read as unknown on both sides of the check.
local function RosterGUID(unit)
    local unitGUID = _G.UnitGUID
    local guid = unit ~= nil and type(unitGUID) == "function" and unitGUID(unit) or nil
    if guid == nil or IsSecret(guid) then return nil end
    return guid
end

local function CurrentFrameState(frame, unit)
    local state = frame and frame._msufA3State
    if frame and frame._msufA3GroupRuntime == true then
        local cfg = ResolveGroupFrameConfig(frame, unit)
        if state and state.config == cfg and state.unit == unit then
            return state, cfg
        end
        if not (cfg and cfg.enabled) then
            return state, cfg
        end
        state = ApplyConfig(frame, cfg)
        return state, cfg
    end

    -- The compile cache knows every input of a unit config (generation, the
    -- profile's auras3 table, the unit-frame spec serial, a scoped
    -- invalidation), so the applied config is current only while it is the
    -- one the cache returns.
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if state and state.config == cfg and cfg and state.unit == unit then
        return state, cfg
    end
    if not (cfg and cfg.enabled) then
        return state, cfg
    end
    state = ApplyConfig(frame, cfg)
    return state, cfg
end

--- AurasElement.Update lands here from Dispatch. Keep this function narrow:
--- normalize the unit, get/apply compiled config, update both lanes, and notify
--- frame-level aura visuals. Menu preview refreshes and DB writes belong outside.
local function UpdateAuras(frame, event, unit, updateInfo, forceFull)
    if not frame then return false end
    local frameUnit = BindFrameUnit(frame)
    if unit and IsSecret(unit) == true then
        unit = frameUnit
    elseif unit == nil then
        unit = frameUnit
    elseif unit ~= frameUnit then
        return false
    end
    local preState = frame._msufA3State
    -- A lane update that raised never reached the end of the lane loop below,
    -- so its sentinel is still set and the lanes are only partly merged: this
    -- event owes a full update whatever its payload says.
    if preState and preState.scanning == true then preState.needFullUpdate = true end
    if EmptyAuraPayload(updateInfo) and forceFull ~= true
        and not (preState and preState.needFullUpdate == true) then
        return false
    end

    -- Invalidate this unit's token-membership sets only when this event can
    -- change membership (TokenSet in Filters.lua). The config-applied case
    -- is folded in after CurrentFrameState below.
    local added = updateInfo and updateInfo.addedAuras
    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    local membershipBumped = forceFull == true or not updateInfo or updateInfo.isFullUpdate == true
        or (preState and preState.needFullUpdate == true)
        or (added ~= nil and added[1] ~= nil) or (removed ~= nil and removed[1] ~= nil)
    if membershipBumped then
        TokenSerial[unit] = (TokenSerial[unit] or 0) + 1
    end

    local state, cfg = CurrentFrameState(frame, unit)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        return false
    end

    forceFull = forceFull == true or state.config ~= cfg
    local full = forceFull == true or state.needFullUpdate == true or not updateInfo or updateInfo.isFullUpdate == true
    if full and not membershipBumped then
        -- CurrentFrameState applied a new config: the lanes rescan fully and
        -- their filters may differ, so no cached set may answer them.
        TokenSerial[unit] = (TokenSerial[unit] or 0) + 1
    end
    -- Roster stamp: the member this full refresh describes. A partyN/raidN token
    -- can change hands with no UNIT_AURA; GROUP_ROSTER_UPDATE compares the stamp
    -- with the token's current member (GroupRosterAuras).
    if full and frame._msufA3GroupRuntime == true then
        state.rosterGUID = RosterGUID(unit)
    end

    -- needFullUpdate and the scanning sentinel are cleared only where the lane
    -- state is known good again: the two lane-less exits here, and the end of
    -- the lane loop below.
    -- A direct visual reads the unit's debuffs by filter. An update-only
    -- payload refreshes auras in place: no dispel type, caster or filter
    -- membership changes, so only a full update or an add/remove re-reads it.
    if cfg.visualDirect == true and not ConfigHasEnabledAuraLane(cfg) then
        state.scanning, state.needFullUpdate = nil, false
        if not (full or membershipBumped) then return false end
        return UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
    end

    if full and UnitExists then
        local exists = UnitExists(unit)
        if not IsSecret(exists) and exists == false then
            for _, lane in pairs(state.lanes or EMPTY_LANES) do ClearLane(lane) end
            ClearFrameAuraVisualState(frame)
            state.scanning, state.needFullUpdate = nil, false
            return false
        end
    end

    local changedCount = 0
    local auraVisualDirty = false

    local order = cfg.laneOrder or BASE_LANE_ORDER
    -- Native PLAYER filter trust is a property of the unit, not the lane:
    -- evaluate UnitInRange at most once per event, for the first enabled lane
    -- that uses the native filter. The player is always in range.
    local rangeTrusted
    -- Dirty until every lane finished. A scan or delta merge that raises leaves
    -- the sentinel set and keeps a pending needFullUpdate, so the next event
    -- rescans instead of trusting half-merged lanes and their stale buttons.
    state.scanning = true
    for i = 1, #order do
        local lane = state.lanes[order[i]]
        local laneCfg = lane and lane.config
        if rangeTrusted == nil and laneCfg and laneCfg.enabled and laneCfg.nativePlayerFilter == true then
            rangeTrusted = true
            if unit ~= "player" and type(UnitInRange) == "function" then
                local inRange, checkedRange = UnitInRange(unit)
                if not IsSecret(inRange) and not IsSecret(checkedRange)
                    and checkedRange == true and inRange == false then
                    rangeTrusted = false
                end
            end
        end
        local changed, visualDirty = UpdateAuraLaneRuntime(lane, unit, updateInfo, full, rangeTrusted)
        if changed then
            changedCount = changedCount + 1
            if visualDirty then auraVisualDirty = true end
        end
    end
    state.scanning, state.needFullUpdate = nil, false

    local visualChanged = false
    if cfg.visualDirect == true then
        -- Same rule as the lane-less exit above; a lane that changed may move
        -- the debuff stripe, which follows the lane.
        if full or membershipBumped or changedCount > 0 then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    elseif auraVisualDirty == true then
        if cfg.visual ~= nil or FrameHasAuraVisualState(frame) then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    elseif full then
        local hasFrameVisual = FrameHasAuraVisualState(frame)
        if hasFrameVisual then
            visualChanged = UpdateFrameAuraVisualState(frame, state, cfg, unit) == true
        end
    end
    return changedCount > 0 or visualChanged == true
end

local function RenderCachedAuras(frame, combatOnly)
    if not frame then return false end
    local unit = BindFrameUnit(frame)
    local state, cfg = CurrentFrameState(frame, unit)
    if not (state and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    if state.needFullUpdate == true or state.scanning == true then
        return UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    end

    local changed = false
    local order = cfg.laneOrder or BASE_LANE_ORDER
    for i = 1, #order do
        local lane = state.lanes[order[i]]
        local laneCfg = lane and lane.config
        if laneCfg and laneCfg.enabled and (combatOnly ~= true or laneCfg.needsCombatRefresh == true) then
            RenderLane(lane, unit)
            changed = true
        end
    end
    if changed and (cfg.visual ~= nil or FrameHasAuraVisualState(frame)) then
        UpdateFrameAuraVisualState(frame, state, cfg, unit)
    end
    return changed
end

local function ResetAurasForIdentity(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", BindFrameUnit(frame), nil, true)
end

--- GROUP_ROSTER_UPDATE for one group frame. A header keeps a partyN/raidN token
--- when the roster moves another member into it, the unchanged attribute runs no
--- aura follower, and Classic sends no UNIT_AURA for the swap. Blizzard's Classic
--- raid frames update everything on this event; one UnitGUID read and one
--- comparison per frame limit the full rescan to slots whose member changed.
local function GroupRosterAuras(frame)
    local state = frame and frame._msufA3State
    if not (state and frame._msufA3GroupRuntime == true) then return false end
    if RosterGUID(BindFrameUnit(frame)) == state.rosterGUID then return false end
    return ResetAurasForIdentity(frame)
end

--- UNIT_FACTION for one frame's own unit. Bars > Show on asks UnitCanAssist,
--- which a duel, a PvP flag or mind control flips with no UNIT_AURA; Retail's
--- identity owners re-read it on this event (IdentityEvents in Auras3/Runtime).
--- Only a Friendly or Enemy border subscribes (AurasElement.GetEvents). The
--- gate is re-applied to the lanes the frame already holds, so nothing is
--- rescanned unless the lanes owe a full update, as in RenderCachedAuras. The
--- event names a token, not a member: GROUP_ROSTER_UPDATE rescans a token that
--- changed hands (GroupRosterAuras), and the player's own payload
--- reaches every other such frame through FactionPlayerFanOut.
local function FactionAuras(frame, unit)
    if not frame then return false end
    local frameUnit = BindFrameUnit(frame)
    if unit ~= nil and unit ~= frameUnit and not IsSecret(unit) then return false end
    local state, cfg = CurrentFrameState(frame, frameUnit)
    local visual = cfg and cfg.enabled == true and cfg.visual
    if not (state and visual and visual.borderShowOn ~= nil) then return false end
    if state.needFullUpdate == true or state.scanning == true then
        return UpdateAuras(frame, "ForceUpdate", frameUnit, nil, true)
    end
    return UpdateFrameAuraVisualState(frame, state, cfg, frameUnit) == true
end

--- UNIT_FACTION for the player. A duel or mind control flips the player's own
--- side of UnitCanAssist("player", unit) while no event names the other unit.
--- Retail covers only half of that: IdentityEvents in Auras3/Runtime registers
--- UNIT_FACTION unfiltered, but on a "player" payload it re-checks every group
--- assist owner and routes its direct owners through the named unit alone, so a
--- Mainline target, focus, boss or arena dispel border stays stale until some
--- unrelated refresh. Classic follows Blizzard's own Classic TargetFrame
--- instead, which re-runs CheckFaction and UpdateAuras whenever UNIT_FACTION
--- names "player" (Blizzard_UnitFrame/Classic/TargetFrame.lua). That wider fan-
--- out is deliberate: it is a Classic-over-Mainline asymmetry, not a gap to
--- close by narrowing this back to group frames. A frame registers UNIT_FACTION
--- for its own unit only, so one shared driver listens for the player while any
--- frame - a group frame or a target, focus, boss or arena frame - holds a
--- Friendly or Enemy border (AurasElement.GetEvents keeps that set) and
--- re-applies each shown frame's gate once. A frame bound to the player is left
--- out: it already hears the payload on its own unit, and a unit change
--- re-derives the set (UF.OnUnitChanged rebuilds a frame's events), so a group
--- token that becomes or stops being "player" joins or leaves it then. A hidden
--- frame reconciles on its show edge instead (EnsureClassicAuraOnShowRefresh).
local factionPlayerFrames = setmetatable({}, { __mode = "k" })
local factionPlayerDriver

local function FactionPlayerFanOut()
    local any = false
    for frame in pairs(factionPlayerFrames) do
        -- The player's own frame already hears this event on its unit.
        if not (frame.IsShown and not frame:IsShown()) and BindFrameUnit(frame) ~= "player"
            and FactionAuras(frame, nil) then
            any = true
        end
    end
    return any
end

local function TrackFactionPlayerFrame(frame, wanted)
    local frames = factionPlayerFrames
    if wanted == true then frames[frame] = true else frames[frame] = nil end
    local driver = factionPlayerDriver
    if next(frames) ~= nil then
        if not driver then
            driver = CreateFrame("Frame")
            driver:SetScript("OnEvent", FactionPlayerFanOut)
            factionPlayerDriver = driver
        end
        if driver._msufA3Armed ~= true then
            driver:RegisterUnitEvent("UNIT_FACTION", "player")
            driver._msufA3Armed = true
        end
    elseif driver and driver._msufA3Armed == true then
        driver:UnregisterEvent("UNIT_FACTION")
        driver._msufA3Armed = nil
    end
end

local function NeedsCombatAuraEvents(cfg)
    if not (cfg and cfg.enabled and cfg.lanes) then return false end
    for _, lane in pairs(cfg.lanes) do
        if lane and lane.enabled and lane.needsCombatRefresh == true then return true end
    end
    return false
end

function A3.EnableFrame(frame)
    local unit = BindFrameUnit(frame)
    if not (unit and MANAGED_UNITS[unit]) then return false end
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(unit, frame, false)
        return false
    end
    ApplyConfig(frame, cfg)
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[unit] = frame
    A3.SetUnitFrameOwner(unit, frame, true)
    UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    return true
end

function A3.DisableFrame(frame)
    if not frame then return true end
    local unit = BindFrameUnit(frame)
    HideState(frame)
    if factionPlayerFrames[frame] then TrackFactionPlayerFrame(frame, false) end
    frame._msufA3GroupConfig = nil
    frame._msufA3GroupSource = nil
    frame._msufA3GroupUnit = nil
    frame._msufA3GroupGen = nil
    frame._msufA3GroupKind = nil
    frame._msufA3GroupRuntime = nil
    if unit then
        if A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
            A3._runtimeFrames[unit] = nil
        end
        A3.SetUnitFrameOwner(unit, frame, false)
    end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", BindFrameUnit(frame), nil, true)
end

A3.ForceUpdateFrame = A3.RenderFrame

function A3.HandleUnitAura(frame, event, unit, updateInfo)
    return UpdateAuras(frame, event, unit, updateInfo, false)
end

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

function A3.RenderUnitChangedFrame(frame, oldUnit, newUnit)
    if not frame then return false end
    newUnit = newUnit or BindFrameUnit(frame)
    if oldUnit and A3._runtimeFrames and A3._runtimeFrames[oldUnit] == frame then
        A3._runtimeFrames[oldUnit] = nil
    end
    if newUnit then
        A3.InvalidateUnitRuntimeConfig(newUnit)
    end
    if AuraRuntimeCombatBlocked() then
        -- Only the config recompile waits for combat end. The rescan below
        -- stays synchronous: a secure header can rebind this button to another
        -- unit in combat, and the scan touches only non-secure aura children.
        A3._QueueDeferredAuraRuntime(newUnit or "shared", "AURAS3_CLASSIC_UNIT_CHANGED")
    end
    -- This is a cold identity path. Blizzard's Classic TargetFrame performs a
    -- complete synchronous UpdateAuras here; delaying ours could leave a lane
    -- on the previous/partial unit until an unrelated menu apply or unit swap.
    return ResetAurasForIdentity(frame)
end

A3.OnFrameUnitChanged = A3.RenderUnitChangedFrame

local AurasElement = {
    events = { "UNIT_AURA" },
    unitlessEvents = EMPTY_EVENTS,
}

local function EnsureClassicAuraOnShowRefresh(frame)
    if not (frame and frame.HookScript) or frame._msufA3ClassicOnShowHooked == true then return end
    frame._msufA3ClassicOnShowHooked = true
    frame:HookScript("OnShow", function(owner)
        local active = owner and owner._msufActiveElements
        -- Hidden target/focus/boss frames can miss their identity event before
        -- RegisterUnitWatch shows them. The core's lean OnShow reseed excludes
        -- Auras by design, so Classic owns this one cold full scan itself.
        if active and active.Auras == true and not IsGroupFrame(owner) then
            ResetAurasForIdentity(owner)
        elseif owner and owner._msufA3ClassicHiddenStale == true
            and owner._msufGFHeaderOnShowDeferred ~= true
            and owner._msufA3GroupRuntime == true and IsGroupFrame(owner) then
            -- A hidden group child receives no UNIT_AURA, so removals delivered
            -- while it was hidden are lost. Reconcile once per show edge. A
            -- deferred header show keeps the marker and needFullUpdate instead.
            owner._msufA3ClassicHiddenStale = nil
            ResetAurasForIdentity(owner)
        end
    end)
    frame:HookScript("OnHide", function(owner)
        local state = owner and owner._msufA3State
        if state and IsGroupFrame(owner) then
            state.needFullUpdate = true
            owner._msufA3ClassicHiddenStale = true
        end
    end)
end

--- The element's event lists, built once at load. A Friendly or Enemy border
--- follows its unit's faction (FactionAuras), group frames follow roster
--- changes (GroupRosterAuras), the player's buff lane follows its weapon
--- enchants, and a stable token resets on its identity event. The combat
--- variants add the two combat edges for lanes that refresh on them.
--- maxArena: the client's arena slot count (TBC and Mists field five
--- opponents); arena1..3 always map.
local function BuildAuraEvents(maxArena)
    local events = {
        faction = { "UNIT_AURA", "UNIT_FACTION" },
        group = { "GROUP_ROSTER_UPDATE" },
        groupCombat = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" },
        weapon = { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" },
        combatWeapon = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" },
        identityByUnit = {},
        identityCombatByUnit = {},
        identity = {},
    }
    local function Identity(event, units)
        local plain = { event }
        local combat = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", event }
        events.identity[event] = true
        for i = 1, #units do
            events.identityByUnit[units[i]] = plain
            events.identityCombatByUnit[units[i]] = combat
        end
    end
    Identity("UNIT_PET", { "pet" })
    Identity("PLAYER_TARGET_CHANGED", { "target" })
    Identity("PLAYER_FOCUS_CHANGED", { "focus" })
    Identity("INSTANCE_ENCOUNTER_ENGAGE_UNIT", { "boss1", "boss2", "boss3", "boss4", "boss5" })
    local arena = {}
    for i = 1, math.max(3, maxArena) do arena[i] = "arena" .. i end
    Identity("ARENA_OPPONENT_UPDATE", arena)
    return events
end
local EVENTS = BuildAuraEvents(tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)

--- Edit Mode and menu group test frames (GF preview rows) are bound to a real
--- token, usually "player", but draw deterministic sample icons of their own.
--- The live backend never attaches to them, as on Retail (Runtime_Facade):
--- it would render the player's real auras under the samples and run every
--- player UNIT_AURA once more per test frame.
function AurasElement.IsEnabled(frame)
    local unit = BindFrameUnit(frame)
    if not unit then return false end
    if IsGroupFrame(frame) then
        if frame._msufGFIsPreviewFrame == true then return false end
        local cfg = ResolveGroupFrameConfig(frame, unit)
        return cfg and cfg.enabled == true or false
    end
    local cfg = A3.ResolveUnitFrameConfig(unit, frame.MSUFSpec)
    return cfg and cfg.enabled == true or false
end

--- Unit events, registered per frame for its own unit. UNIT_FACTION joins only
--- while Bars > Show on filters the border, so Both never receives it, and only
--- on a client that has the event.
function AurasElement.GetEvents(frame)
    local unit = BindFrameUnit(frame)
    local cfg = unit and FrameAuraConfig(frame, unit)
    local visual = cfg and cfg.enabled == true and cfg.visual
    local faction = visual and visual.borderShowOn ~= nil or false
    local client = MSUF.Client
    if faction and client and type(client.SupportsEvent) == "function" and not client.SupportsEvent("UNIT_FACTION") then
        faction = false
    end
    -- Every such frame but the player's own also hears the player's side, which
    -- flips the observer half of UnitCanAssist (FactionPlayerFanOut).
    TrackFactionPlayerFrame(frame, faction and unit ~= "player")
    return faction and EVENTS.faction or AurasElement.events
end

function AurasElement.GetUnitlessEvents(frame)
    local unit = BindFrameUnit(frame)
    local cfg = unit and FrameAuraConfig(frame, unit)
    local combat = NeedsCombatAuraEvents(cfg)
    if IsGroupFrame(frame) then
        return combat and EVENTS.groupCombat or EVENTS.group
    end
    local weapon = unit == "player" and cfg and cfg.lanes and cfg.lanes.buff
        and cfg.lanes.buff.weaponEnchants == true
    local identity = unit and EVENTS.identityByUnit[unit]
    if identity then
        return combat and EVENTS.identityCombatByUnit[unit] or identity
    end
    if combat and weapon then return EVENTS.combatWeapon end
    if weapon then return EVENTS.weapon end
    return combat and COMBAT_AURA_EVENTS or EMPTY_EVENTS
end

function AurasElement.Create(frame)
    if frame then
        EnsureState(frame)
        EnsureClassicAuraOnShowRefresh(frame)
    end
end

--- Apply only records which runtime owns the frame. UF.ApplyElementToFrame
--- (Libs/MSUFUnitFrames/MSUF_UF_Core.lua) calls Enable right after it, and
--- Enable resolves the config, applies it once and runs the one full scan.
--- Doing that here as well ran ApplyConfig and a forced scan twice per apply.
function AurasElement.Apply(frame)
    if not frame then return end
    local isGroup = IsGroupFrame(frame)
    if isGroup and frame._msufGFIsPreviewFrame == true then
        frame._msufA3GroupRuntime = nil
        HideState(frame)
        return
    end
    frame._msufA3GroupRuntime = isGroup == true or nil
end

function AurasElement.Enable(frame)
    EnsureClassicAuraOnShowRefresh(frame)
    local unit = BindFrameUnit(frame)
    if IsGroupFrame(frame) then
        if frame._msufGFIsPreviewFrame == true then
            frame._msufA3GroupRuntime = nil
            HideState(frame)
            return false
        end
        frame._msufA3GroupRuntime = true
        frame._msufA3GroupConfig = nil
        local cfg = ResolveGroupFrameConfig(frame, unit)
        if not (cfg and cfg.enabled == true) then
            HideState(frame)
            return false
        end
        local state = frame._msufA3State
        if not (state and state.config == cfg and state.unit == unit) then
            ApplyConfig(frame, cfg)
        end
        UpdateAuras(frame, "ForceUpdate", unit, nil, true)
        return true
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        return A3.HandleUnitAura(frame, event, unit, updateInfo)
    end
    if EVENTS.identity[event] == true then
        -- Classic does not guarantee a UNIT_AURA payload when a stable token
        -- (target/focus/bossN) changes GUID. Blizzard's own TargetFrame performs
        -- a full UpdateAuras from PLAYER_TARGET_CHANGED for the same reason.
        -- Keep this cold-path scan synchronous, matching Blizzard's Classic
        -- TargetFrame. Deferring it could leave a partial/previous identity
        -- visible until an unrelated menu apply or another unit swap.
        return ResetAurasForIdentity(frame)
    end
    if event == "WEAPON_ENCHANT_CHANGED" or event == "WEAPON_SLOT_CHANGED" then
        return UpdateAuras(frame, event, BindFrameUnit(frame), nil, true)
    end
    if event == "GROUP_ROSTER_UPDATE" then
        return GroupRosterAuras(frame)
    end
    if event == "UNIT_FACTION" then
        return FactionAuras(frame, unit)
    end
    if event == "MSUF_UNIT_IDENTITY_AURAS"
        or event == "MSUF_UNIT_IDENTITY_SOFT_AURAS" then
        return ResetAurasForIdentity(frame)
    end
    if event == "ForceUpdate"
        or event == "MSUF_FORCE_UPDATE"
        or event == "MSUF_UNIT_IDENTITY"
        or event == "MSUF_UNIT_IDENTITY_SOFT"
        or event == "MSUF_GF_UNIT_IDENTITY" then
        return A3.RenderFrame(frame)
    end
    if event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        return RenderCachedAuras(frame, true)
    end
    return A3.HandleUnitAura(frame, event, unit, updateInfo)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3.nativeAuraBackend = false
A3.classicAuraBackend = true
MSUF.AuraBackendEnabled = true

Backend.Element = AurasElement
