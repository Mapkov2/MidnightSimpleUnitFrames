-- Auras 3 identity gates write a region's alpha only when it changes.
-- Identity.SetAssistAlpha is the one sink of the Unit identity gate, the Group assist gate and the Group presence
-- container gate. A result the region already shows is not written again (2026-10-26 raid trace: 1,710 writes);
-- every hide, reveal, state change and config change still is. A hidden result is cached only on owners whose alpha
-- nothing but the gates writes: ButtonVisuals.SyncContainerGeometry restores lane.alpha on plain lane containers.
-- Real Identity and Presence sources on stub dependencies; the last section proves the checks catch four mutants.
-- Usage: lua tools/tests/auras3_identity_alpha_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local dir = repo .. "/MidnightSimpleUnitFrames/Auras3/Runtime/"

local function Read(name)
    local file = assert(io.open(dir .. name, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local function Mutate(source, from, to)
    local first, last = source:find(from, 1, true)
    assert(first, "mutant anchor missing, update this smoke: " .. from)
    return source:sub(1, first - 1) .. to .. source:sub(last + 1)
end

local function Compile(source, name)
    return assert(loadstring(source, "@" .. name))
end

local SECRET = { secret = true }
UnitCanAssist = function() return true end

-- One world = the Identity and Presence modules built from (optionally mutated) sources.
local function NewWorld(mutate)
    local identitySource, presenceSource = Read("MSUF_Auras3_Runtime_Identity.lua"), Read("MSUF_Auras3_Runtime_Presence.lua")
    if mutate then identitySource = mutate(identitySource) end
    local ns = {}
    function ns.Require() return function(unit) return type(unit) == "string" and unit:find("^raid%d+$") ~= nil end end
    Compile(identitySource, "Identity")("MidnightSimpleUnitFrames", ns)
    Compile(presenceSource, "Presence")("MidnightSimpleUnitFrames", ns)
    local world = { pending = {}, assist = {}, spell = 0 }
    local A3 = { Runtime = { Identity = {}, Presence = {} }, SpellIndicators = {} }
    function A3.SpellIndicators.ApplyGroupAssistGate() return false end
    function A3.SpellIndicators.ApplyUnitIdentityGate() return false end
    function A3.SpellIndicators.ApplyGroupPresenceGate() return false end
    local deps = {
        Platform = {
            RunNextFrame = function(fn) world.pending[#world.pending + 1] = fn end,
            issecretvalue = function(value) return type(value) == "table" and value.secret == true end,
            InCombat = function() return false end,
        },
        OwnerConfig = { GetGroupSlotsRootConfig = function(cfg) return cfg and cfg.groupSlotsRoot end },
        ConfigValues = {
            IsGroupFrame = function(frame) return frame ~= nil and frame.group == true end,
            UnitCanAssistForAuraIdentity = function(unit) return world.assist[unit] end,
        },
        Containers = { UpdateAuraGroupEffectiveFilters = function() end, UpdateAuraSlotEffectiveFilters = function() end },
    }
    local factories = ns.Auras3RuntimeFactories
    deps.Identity = factories.Identity("MidnightSimpleUnitFrames", ns, A3, {}, function() end, deps)
    deps.Presence = factories.Presence("MidnightSimpleUnitFrames", ns, A3, {}, function() end, deps)
    world.A3, world.Identity, world.Presence = A3, deps.Identity, deps.Presence
    function world.Flush()
        local queued = world.pending
        world.pending = {}
        for i = 1, #queued do queued[i]() end
    end
    return world
end

-- A native region double: counts the writes of the gates and models other writers separately.
local function Region(fields, alphaOnly)
    local region = fields or {}
    region.alpha, region.writes = 1, 0
    if alphaOnly then
        function region:SetAlpha(alpha) self.alpha, self.writes = alpha, self.writes + 1 end
    else
        function region:SetAlphaFromBoolean(value, whenTrue, whenFalse)
            self.writes = self.writes + 1
            if value then self.alpha = whenTrue else self.alpha = whenFalse end
        end
    end
    function region:SetEnabled(enabled) self.enabled = enabled end
    return region
end
local function Owner(mode) return Region({ _msufA3GroupSlotsRoot = true, _msufA3NativeLaneConfig = { identityCandidateMode = mode } }) end
local function SensorRoot(mode) return Region({ _msufA3NativeLaneConfig = { sensorRoot = true, identityCandidateMode = mode } }) end
local function SpellRoot(mode) return Region({ _msufA3SpellIndicatorRoot = true, _msufA3NativeLaneConfig = { identityCandidateMode = mode } }) end
local function Lane(mode, alpha) return Region({ _msufA3NativeLaneConfig = { kind = "buff", identityCandidateMode = mode, alpha = alpha } }) end
-- ButtonVisuals.SyncContainerGeometry: another writer, restoring the lane's own opacity.
local function RestoreLaneAlpha(region) region.alpha = region._msufA3NativeLaneConfig.alpha or 1 end

local function Expect(region, writes, alpha, what)
    assert(region.writes == writes, ("%s: %d writes, expected %d"):format(what, region.writes, writes))
    assert(region.alpha == alpha, ("%s: alpha %s, expected %s"):format(what, tostring(region.alpha), tostring(alpha)))
end

local function Checks(world)
    local Identity, Presence, A3 = world.Identity, world.Presence, world.A3
    local Set = Identity.SetAssistAlpha

    -- Sink: repeated state = one write, every state or opacity change = one write, on each region kind. -----------
    for name, make in pairs({ owner = Owner, sensorRoot = SensorRoot, spellRoot = SpellRoot }) do
        local region = make("assist")
        for _ = 1, 4 do assert(Set(region, true, 1) == true) end
        Expect(region, 1, 1, name .. " repeated visible")
        Set(region, false, 1)
        Set(region, false, 1)
        Set(region, false, 0.4)
        Expect(region, 2, 0, name .. " repeated hidden (sole writer)")
        Set(region, true, 1)
        Set(region, true, 0.5)
        Set(region, true, 0.5)
        Expect(region, 4, 0.5, name .. " config change rewrites once")
    end
    do
        local lane = Lane("assist", 0.5)
        Set(lane, true, 0.5)
        Set(lane, true, 0.5)
        Expect(lane, 1, 0.5, "lane repeated visible")
        Set(lane, false, 0.5)
        Set(lane, false, 0.5)
        Expect(lane, 3, 0, "lane hidden always writes (another writer restores lane.alpha)")
        RestoreLaneAlpha(lane)
        Set(lane, false, 0.5)
        Expect(lane, 4, 0, "hide after the geometry sync restored the lane")
        RestoreLaneAlpha(lane)
        Set(lane, true, 0.5)
        Set(lane, true, 0.5)
        Expect(lane, 5, 0.5, "visible after the geometry sync")
        local fallback = Region({}, true)
        Set(fallback, true, 1)
        Set(fallback, true, 1)
        Set(fallback, false, 1)
        Expect(fallback, 2, 0, "SetAlpha fallback sink")
        assert(Set(nil, true, 1) == false and Set({}, true, 1) == false, "a missing sink must report false")
    end
    do
        local region = Owner("assist")
        Set(region, true, 1)
        assert(Set(region, SECRET, 1) == true and Set(region, SECRET, 1) == true)
        Expect(region, 3, region.alpha, "a secret flag is forwarded every time and never cached")
        Set(region, true, 1)
        assert(region.writes == 4, "the plain flag after a secret write must write")
    end

    -- Unit identity owner: hide and reveal still write, a settled owner does not. --------------------------------
    for name, make in pairs({ owner = Owner, sensorRoot = SensorRoot, spellRoot = SpellRoot, lane = function(mode) return Lane(mode, 1) end }) do
        local friendly, hostile = make("assist"), make("hostile")
        friendly._msufA3NativeRegistered = true
        for _ = 1, 3 do
            Identity.SetUnitAuraIdentityOwnerReady(friendly, true, false)
            Identity.SetUnitAuraIdentityOwnerReady(friendly, true, true)
            Identity.SetUnitAuraIdentityOwnerReady(hostile, true, false)
            Identity.SetUnitAuraIdentityOwnerReady(hostile, true, true)
        end
        Expect(friendly, 6, 1, name .. " visible owner: every hide and reveal is a state change")
        assert(friendly.enabled == true, name .. ": the native enable flag must keep following the polarity")
        Expect(hostile, name == "lane" and 6 or 1, 0, name .. " polarity-hidden owner")
    end

    -- Revision cancellation survives: a stale reveal must not show the owner. ---------------------------------------
    do
        local owner = Owner("assist")
        A3._unitAuraIdentityOwnersByUnit = { target = { [owner] = true } }
        local state = Identity.EnsureUnitAuraIdentityState("target")
        state.revision, state.assistKnown, state.canAssist = 2, true, true
        Identity.SetUnitAuraIdentityOwnerReady(owner, true, false)
        Identity.ScheduleUnitAuraIdentityReveal("target", 1)
        world.Flush()
        Expect(owner, 1, 0, "stale reveal revision")
        Identity.ScheduleUnitAuraIdentityReveal("target", 2)
        world.Flush()
        Expect(owner, 2, 1, "current reveal revision")
        A3._unitAuraIdentityOwnersByUnit, A3._unitAuraIdentityState = nil, nil
    end

    -- Group assist gate and presence container gate. -----------------------------------------------------------------
    do
        local frame = { group = true }
        local primary = Owner(nil)
        primary._msufA3ParentFrame = frame
        local groupSlots = { rootKey = "GroupSlots", assistGated = true, identityCandidateMode = "assist" }
        primary._msufA3NativeLaneConfig = groupSlots
        frame.Auras = Region({ _msufA3NativeRoot = true, _msufA3Config = { group = true, enabled = true, groupSlotsRoot = groupSlots } })
        frame.Auras.GroupSlots = primary
        A3._directIdentityAuraContainers = { raid1 = { [primary] = true } }
        for _ = 1, 3 do assert(Identity.ApplyGroupAuraAssistStateToUnit("raid1", true) == true) end
        Expect(primary, 1, 1, "repeated group assist apply")
        Identity.HideGroupAuraAssistOwners("raid1", true)
        Identity.ApplyGroupAuraAssistStateToUnit("raid1", true)
        Expect(primary, 3, 1, "group hide then reveal")
        Identity.ApplyGroupAuraAssistStateToUnit("raid1", false)
        Identity.ApplyGroupAuraAssistStateToUnit("raid1", false)
        Expect(primary, 4, 0, "group assist state change")

        local plain = Owner(nil)
        plain._msufA3ParentFrame = frame
        plain._msufA3NativeLaneConfig = { kind = "groupAuraOwner" }
        A3._directIdentityAuraContainers = { raid1 = { [plain] = true } }
        for _ = 1, 3 do assert(Presence.ApplyGroupAuraPresenceStateToUnit("raid1", true, 1) == true) end
        Expect(plain, 1, 1, "repeated presence apply")
        assert(frame.Auras.writes == 3, "the presence root write is untouched: Edit Mode drag writes that root too")
        Presence.ApplyGroupAuraPresenceStateToUnit("raid1", false, 2)
        Presence.ApplyGroupAuraPresenceStateToUnit("raid1", false, 2)
        Presence.ApplyGroupAuraPresenceStateToUnit("raid1", true, 3)
        Expect(plain, 3, 1, "presence state change")
        A3._directIdentityAuraContainers = nil
    end

    -- Model check: any gate and geometry-sync sequence leaves the same alpha as writing every result. -------------
    do
        local seed = 20261026
        local function Random(n) seed = (seed * 16807) % 2147483647; return seed % n + 1 end
        local kinds = { Owner, SensorRoot, SpellRoot, function(mode) return Lane(mode, 0.5) end, function(mode) return Lane(mode, 1) end }
        local live, reference = {}, {}
        for i = 1, #kinds * 2 do live[i], reference[i] = kinds[(i - 1) % #kinds + 1]("assist"), kinds[(i - 1) % #kinds + 1]("assist") end
        local liveWrites, referenceWrites = 0, 0
        for _ = 1, 4000 do
            local i = Random(#live)
            local config = live[i]._msufA3NativeLaneConfig
            if config.kind == "buff" and Random(4) == 1 then
                RestoreLaneAlpha(live[i])
                RestoreLaneAlpha(reference[i])
            else
                local visible = Random(2) == 1
                local alpha = config.kind == "buff" and config.alpha or (Random(3) == 1 and 0.5 or 1)
                Set(live[i], visible, alpha)
                reference[i]:SetAlphaFromBoolean(visible, alpha, 0)
            end
            for j = 1, #live do
                assert(live[j].alpha == reference[j].alpha,
                    ("region %d diverged after step: alpha %s, expected %s"):format(j, tostring(live[j].alpha), tostring(reference[j].alpha)))
            end
        end
        for j = 1, #live do liveWrites, referenceWrites = liveWrites + live[j].writes, referenceWrites + reference[j].writes end
        assert(liveWrites < referenceWrites, "the cache saved nothing: " .. liveWrites .. " vs " .. referenceWrites)
    end
end

Checks(NewWorld())

-- The checks must catch a cache that is missing, too eager, or blind to secrets. ----------------------------------
local mutants = {
    ["no cache"] = function(source)
        return Mutate(source, "if region._msufA3GateAlpha == alpha then return true end", "")
    end,
    ["hidden cached on plain lanes"] = function(source)
        return Mutate(source, "(alpha ~= 0 or GatesOwnAlpha(region)) and alpha or nil", "alpha")
    end,
    ["secret flag cached"] = function(source)
        return Mutate(source, "if issecretvalue(value) == true then", "if false then")
    end,
    ["trueAlpha ignored"] = function(source)
        return Mutate(source, "local alpha = value and trueAlpha or 0", "local alpha = value and 1 or 0")
    end,
}
for name, mutate in pairs(mutants) do
    local ok = pcall(Checks, NewWorld(mutate))
    assert(not ok, "mutant survived: " .. name)
end

print("auras3_identity_alpha_smoke: OK")
