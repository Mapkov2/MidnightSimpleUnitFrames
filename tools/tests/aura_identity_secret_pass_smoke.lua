-- aura_identity_secret_pass_smoke.lua <repoRoot>
--
-- Strict secret pass over the native aura runtime's unit-identity owners:
-- Auras3/Runtime/MSUF_Auras3_Runtime_Identity.lua, _Presence.lua and
-- _IdentityEvents.lua, the Retail and WoW Forever code that reads unit
-- identity on every group and unit-frame edge. It uses the client-strict
-- helper (tools/tests/classpower_secrets.lua): type() answers a secret's kind,
-- arithmetic, ordering, concatenation, indexing and calls raise, and a line
-- watcher records every executed line that compares a local holding a secret
-- or truth-tests it with `not`.
--
-- Secret, as documented for a restricted unit on 12.x
-- (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua, upstream/live
-- and upstream/forever): UnitGUID, UnitPhaseReason and UnitClass
-- (SecretWhenUnitIdentityRestricted), UnitIsUnit
-- (SecretWhenUnitComparisonRestricted) and UnitInRange (SecretReturns). The
-- unit token and the connection flag of a restricted event payload are
-- secret too. UnitPosition, UnitIsConnected, UnitInOtherParty, UnitCanAssist
-- and UnitOnTaxi take secret arguments but answer plainly. The scenario
-- registers group and unit-frame owners and plays the identity, presence,
-- assist and combat edges, once per watched file.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local rawtype = type

local RUNTIME = root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/"
local FILES = { "MSUF_Auras3_Runtime_Identity.lua", "MSUF_Auras3_Runtime_Presence.lua",
    "MSUF_Auras3_Runtime_IdentityEvents.lua" }

local Region = {}
Region.__index = Region
function Region:SetAlpha(alpha) self._alpha = alpha end
function Region:SetAlphaFromBoolean(value) self._alphaBool = value end
function Region:GetParent() return self._parent end
function Region:IsShown() return true end
function Region:IsVisible() return true end
function Region:SetScript(name, handler) self[name] = handler end
function Region:RegisterEvent(event) self._events[event] = true end
function Region:RegisterUnitEvent(event) self._events[event] = true; return true end
function Region:UnregisterEvent(event) self._events[event] = nil end
function Region:UnregisterAllEvents() self._events = {} end
local function NewRegion(fields)
    local region = setmetatable({ _events = {} }, Region)
    for key, value in pairs(fields or {}) do region[key] = value end
    return region
end

local function Run(watchedFile)
    local Secret = Secrets.New
    local inCombat = false
    Secrets.Install()
    _G.MSUF_RunNextFrame = nil
    _G.InCombatLockdown = function() return inCombat end
    _G.UnitExists = function() return true end
    _G.UnitGUID = function() return Secret("string") end
    _G.UnitPhaseReason = function() return Secret("number") end
    _G.UnitClass = function() return Secret("string"), Secret("string"), Secret("number") end
    _G.UnitIsUnit = function() return Secret("boolean") end
    _G.UnitInRange = function() return Secret("boolean"), Secret("boolean") end
    _G.UnitPosition = function() return 0, 0, 0, 1 end
    _G.UnitIsConnected = function() return true end
    _G.UnitInOtherParty = function() return false end
    _G.UnitCanAssist = function() return true end
    _G.UnitOnTaxi = function() return false end
    -- Kernel/MSUF_Util.lua IsGroupUnitToken, as shipped.
    _G.MSUF_IsGroupUnitToken = function(unit)
        return type(unit) == "string" and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
    end

    -- Libs/MSUFUnitFrames/MSUF_UF_Core.lua IsBossUnit, as shipped.
    local MSUF = { Auras3RuntimeFactories = {}, UF = { IsBossUnit = function(unit)
        return unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5"
    end } }
    local A3 = {
        SpellIndicators = {
            ApplyGroupPresenceGate = function() return false end,
            ApplyGroupAssistGate = function() return false end,
        },
        _ManagedAuraContainerSupportsGeometryRepair = function() return false end,
        _NativeContainerVisible = function() return true end,
        _SyncManagedAuraContainerGeometry = function() return false end,
    }
    for _, file in ipairs(FILES) do assert(loadfile(RUNTIME .. file))("MidnightSimpleUnitFrames", MSUF) end
    local timers = {}
    local Platform = {
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
        CreateFrame = function() return NewRegion() end,
        InCombat = function() return inCombat end,
        issecretvalue = _G.issecretvalue,
    }
    local function IsGroupFrame(frame) return rawtype(frame) == "table" and frame._msufIsGroupFrame == true end
    local factories = MSUF.Auras3RuntimeFactories
    local function Export(_, value) return value end
    local Identity = factories.Identity("MidnightSimpleUnitFrames", MSUF, A3, {}, Export, {
        ConfigValues = {
            IsGroupFrame = IsGroupFrame,
            UnitCanAssistForAuraIdentity = function(unit) return _G.UnitCanAssist("player", unit) end,
        },
        OwnerConfig = { GetGroupSlotsRootConfig = function() return nil end },
        Platform = Platform,
    })
    local Presence = factories.Presence("MidnightSimpleUnitFrames", MSUF, A3, {}, Export, {
        Containers = {
            UpdateAuraGroupEffectiveFilters = function() return false end,
            UpdateAuraSlotEffectiveFilters = function() return false end,
        },
        Identity = Identity,
        Platform = Platform,
    })
    factories.IdentityEvents("MidnightSimpleUnitFrames", MSUF, A3, {}, Export, {
        Identity = Identity, Presence = Presence, Platform = Platform,
    })

    local stop = Secrets.Watch(RUNTIME .. watchedFile)
    local failures = {}
    local function Step(label, fn, ...)
        local ok, message = pcall(fn, ...)
        if not ok then failures[#failures + 1] = label .. ": " .. tostring(message) end
    end
    local function Drain()
        local pending = timers
        timers = {}
        for i = 1, #pending do Step("timer", pending[i]) end
    end

    -- Owners: assist-gated group lanes on party1/raid1, identity-gated lanes on
    -- target/focus/boss1, all through the shipped registration.
    local frames, containers = {}, {}
    for _, unit in ipairs({ "party1", "raid1", "target", "focus", "boss1" }) do
        local group = unit == "party1" or unit == "raid1"
        local frame = NewRegion({ MSUFUnitKey = unit, _msufIsGroupFrame = group or nil,
            _msufGFKind = group and (unit == "party1" and "party" or "raid") or nil })
        frame.Auras = NewRegion({ _msufA3NativeRoot = true, _parent = frame })
        frames[unit] = frame
        local container = NewRegion({ unit = unit, _msufA3ParentFrame = frame, _parent = frame,
            _msufA3NativeLaneConfig = { alpha = 1, nativeFilter = "HELPFUL",
                groupAccessGate = group or nil, identityCandidateMode = (not group) and "assist" or nil } })
        containers[#containers + 1] = container
        Step("register " .. unit, A3._RegisterDirectIdentityRefreshContainer, container)
        if group then
            Step("seed presence " .. unit, A3._SeedGroupAuraPresenceGate, frame, unit)
            Step("seed assist " .. unit, A3._SeedGroupAuraAssistGate, frame, unit)
        end
    end
    Drain()
    local driver = A3._directIdentityAuraFrame or (A3._EnsureDirectIdentityRefreshFrame and A3._EnsureDirectIdentityRefreshFrame())
    local onEvent = driver and driver.OnEvent
    if not onEvent then failures[#failures + 1] = "the identity driver has no OnEvent handler" end
    local function Event(event, unit, arg2)
        if onEvent then Step(event, onEvent, driver, event, unit, arg2) end
        Drain()
    end

    for _, combat in ipairs({ false, true }) do
        inCombat = combat
        Event("PLAYER_ENTERING_WORLD", false, false)
        Event("GROUP_ROSTER_UPDATE")
        Event("PLAYER_TARGET_CHANGED")
        Event("PLAYER_FOCUS_CHANGED")
        Event("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        Event("ARENA_OPPONENT_UPDATE", Secret("string"), Secret("string"))
        for _, event in ipairs({ "UNIT_FLAGS", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_CONNECTION",
            "UNIT_OTHER_PARTY_CHANGED", "UNIT_FACTION" }) do
            Event(event, Secret("string"), Secret("boolean"))
            Event(event, "party1", Secret("boolean"))
            Event(event, "player")
            Event(event, "target")
        end
        Event("PARTY_MEMBER_DISABLE", Secret("string"))
        Event("PARTY_MEMBER_ENABLE", Secret("string"))
        Event("PARTY_MEMBER_DISABLE", "party1")
        Event("PARTY_MEMBER_ENABLE", "party1")
        Event("ENTERED_DIFFERENT_INSTANCE_FROM_PARTY")
        Event("PLAYER_CONTROL_LOST")
    end
    inCombat = false
    Event("PLAYER_REGEN_ENABLED")

    -- Direct calls with secret inputs the events cannot carry.
    local secretFrame = NewRegion({ MSUFUnitKey = Secret("string"), _msufIsGroupFrame = true, _msufGFKind = "party" })
    secretFrame.Auras = NewRegion({ _msufA3NativeRoot = true, _parent = secretFrame })
    Step("presence seed, secret key", A3._SeedGroupAuraPresenceGate, secretFrame, "party1")
    Step("assist seed, secret key", A3._SeedGroupAuraAssistGate, secretFrame, "party1")
    Step("presence, secret unit", A3._SetGroupAuraPresenceDisabled, Secret("string"), true)
    Step("presence connection", A3._UpdateGroupAuraPresenceConnectionState, "party1", Secret("boolean"), true)
    Step("presence phase", A3._UpdateGroupAuraPresencePhaseState, "party1", true)
    Step("presence full", A3._UpdateGroupAuraPresenceState, "party1", true, true)
    Step("assist identity", A3._ReadGroupAuraAssistIdentity, "party1", true)
    Step("assist state", A3._UpdateGroupAuraAssistState, "party1", true, true, true)
    Step("assist all", A3._UpdateAllGroupAuraAssistStates, true, true)
    Step("flag bucket", A3._GroupAuraAssistFlagBucket, Secret("string"))
    Step("refresh all", A3._DirectIdentityRefreshAll, true, true)
    for _, unit in ipairs({ "target", "focus", "boss1", "party1" }) do
        Step("refresh " .. unit, A3._DirectIdentityRefreshUnitWithUnitAuraGate, unit)
    end
    Drain()
    for i = 1, #containers do Step("unregister", A3._UnregisterDirectIdentityRefreshContainer, containers[i]) end
    Drain()

    local violations = stop()
    _G.type = rawtype
    return failures, violations
end

local report, seen = {}, {}
for _, file in ipairs(FILES) do
    local failures, violations = Run(file)
    for _, failure in ipairs(failures) do
        if not seen[failure] then seen[failure] = true; report[#report + 1] = "raised: " .. failure end
    end
    for _, violation in ipairs(violations) do report[#report + 1] = "watched: " .. violation end
end
if #report > 0 then
    error("native aura identity runtime mishandles secret unit identity:\n  " .. table.concat(report, "\n  "), 0)
end
print(("aura_identity_secret_pass_smoke: ok (%d watched files)"):format(#FILES))
