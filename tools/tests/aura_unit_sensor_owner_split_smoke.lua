-- Native aura runtime (Midnight and WoW Forever): Unit-frame Dispel/Purge
-- sensors own their native AuraContainer alone.
--
-- Blizzard_AuraContainer stops processing a container for the rest of the
-- session once one of its update passes aborts (DirtyPhaseMixin,
-- Blizzard_SharedXML/MixinUtil.lua). With the default neutral Dispel border
-- ("any dispel type") and the Purge border, the Buff lane used to be merged
-- into that sensor owner, so a failure on the sensor side froze the target
-- buffs until /reload while the separate Debuff lane kept working (2026-10-19
-- report). The real OwnerConfig factory must keep every normal lane out of
-- the unit sensor owners, for every polarity, and must leave the Group owner
-- plan (one shared GroupSlots container per member) unchanged.
-- Arguments: repository root, then optionally the OwnerConfig path (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local path = arg[2] or (root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_OwnerConfig.lua")

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local MSUF = { Auras3RuntimeFactories = {} }
local A3 = {
    SpellIndicators = {
        RootConfig = function() return nil end,
        PartitionRoot = function() return nil end,
    },
}
assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
local exports = assert(MSUF.Auras3RuntimeFactories.OwnerConfig, "OwnerConfig factory did not register")(
    "MidnightSimpleUnitFrames", MSUF, A3, {}, function() end, {
        Signatures = {
            SensorStructuralSignature = function(sensor) return "S:" .. tostring(sensor.kind) end,
            SensorLayoutSignature = function(sensor) return "L:" .. tostring(sensor.kind) end,
        },
    })
local GetNativeOwnerPlan = assert(exports.GetNativeOwnerPlan, "OwnerConfig exports no GetNativeOwnerPlan")

local function Lane(kind, rootKey, max, mode)
    return { kind = kind, rootKey = rootKey, unit = "target", enabled = true, max = max,
        identityCandidateMode = mode, alpha = 1, _msufA3StructuralSignature = kind .. ":" .. tostring(max) }
end
local function Sensor(kind, mode)
    return { sensor = true, kind = kind, unit = "target", enabled = true, max = 1, layer = 0,
        identityCandidateMode = mode }
end

local function CheckUnitPlan(label, cfg)
    local plan = GetNativeOwnerPlan(cfg)
    Check(next(plan.ownedLaneKeys) == nil,
        label .. ": a unit sensor owner still owns a normal lane (" .. tostring(next(plan.ownedLaneKeys)) .. ")")
    local sensorOwners = 0
    for key, owner in pairs(plan.owners) do
        sensorOwners = sensorOwners + 1
        Check(owner.sensorRoot == true, label .. ": unit owner " .. key .. " is no pure sensor root")
        Check(owner.flowLane == nil and owner.slotLanes == nil,
            label .. ": unit owner " .. key .. " carries an aura lane")
        Check(owner.kind == "dispelSensors", label .. ": unit owner " .. key .. " has kind " .. tostring(owner.kind))
    end
    Check(sensorOwners > 0, label .. ": precondition: no sensor owner was compiled")
    return plan
end

-- Default Target: neutral "any dispel type" border plus Purge, a 16-icon Buff
-- lane, a single-icon Debuff lane (the old slot path) and a regular one.
local defaultPlan = CheckUnitPlan("default target", {
    unit = "target", enabled = true,
    lanes = {
        buff = Lane("buff", "Buffs", 16, nil),
        debuff = Lane("debuff", "Debuffs", 1, nil),
        external = Lane("external", "Externals", 8, nil),
    },
    sensors = { dispelBorder = Sensor("dispelBorder", nil), purgeBorder = Sensor("purgeBorder", nil) },
})
local neutral = defaultPlan.owners.DispelSensorNeutral
Check(neutral and #neutral.sensors == 2, "the neutral owner lost its Dispel or Purge sensor")

-- "Dispellable by me" (assist) and enemy-only sensors next to exact-ID Custom
-- lanes of the same polarity: none of them may join a sensor owner either.
CheckUnitPlan("assist and hostile target", {
    unit = "target", enabled = true,
    lanes = {
        buff = Lane("buff", "Buffs", 12, nil),
        custom1 = Lane("custom", "CustomAuras1", 6, "assist"),
        custom2 = Lane("custom", "CustomAuras2", 1, "hostile"),
    },
    sensors = { dispelBorder = Sensor("dispelBorder", "assist"), dispelOverlay = Sensor("dispelOverlay", "hostile") },
})

-- Group frames keep their single shared owner per member.
local groupPlan = GetNativeOwnerPlan({
    unit = "party1", enabled = true, group = true,
    lanes = { buff = Lane("buff", "Buffs", 4, nil), debuff = Lane("debuff", "Debuffs", 3, nil) },
    sensors = { dispelBorder = Sensor("dispelBorder", nil) },
})
local groupSlots = groupPlan.owners.GroupSlots
Check(groupSlots and groupSlots.flowLane and groupSlots.flowLane.rootKey == "Buffs",
    "the Group owner no longer carries its Buff flow lane")
Check(groupPlan.ownedLaneKeys.Buffs == true, "the Group owner plan no longer owns the Buff lane")

print("aura unit sensor owner split smoke: OK")
