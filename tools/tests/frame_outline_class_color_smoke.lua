-- frame_outline_class_color_smoke.lua <root> <flavor>
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local colors = { MAGE = { r = .1, g = .6, b = 1 }, WARRIOR = { r = .8, g = .5, b = .2 } }
local classes = { target = "MAGE", raid1 = "MAGE", raid2 = "WARRIOR" }
local classReads, threat = 0, 0
local targetIsPlayer = true
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    local env = h.env
    env.issecretvalue, env.type = issecretvalue, type
    local rosterExists = env.UnitExists
    env.UnitExists = function(unit) return unit == "target" or rosterExists(unit) end
    local rosterGUID = env.UnitGUID
    env.UnitGUID = function(unit)
        if unit == "raid1" then return "Player-raid1-" .. classes.raid1 end
        return rosterGUID(unit)
    end
    env.UnitIsPlayer = function(unit)
        if unit == "target" then return targetIsPlayer end
        return true
    end
    env.UnitClass = function(unit)
        classReads = classReads + 1
        return "Class", classes[unit], 1
    end
    env.UnitThreatSituation = function() return threat end
    env.RAID_CLASS_COLORS = colors
end })

local db, UF, GF = h.env.MSUF_DB, h.UF, h.GF
local target = h.env.CreateFrame("Button", nil, h.env.UIParent)
target.MSUFUnitKey = "target"
UF.frames.target = target
db.bars.barOutlineThickness = 2
db.bars.barOutlineClassColor = true
db.general.barOutlineColorR, db.general.barOutlineColorG, db.general.barOutlineColorB = .2, .3, .4
db.classColors = { MAGE = { r = .15, g = .65, b = .95 } }
db.target.hlOverride, db.target.aggroOutlineMode = true, 1
assert(UF.ApplySpec(target, UF.Config.RefreshUnit("target"), nil, { Health = true, Borders = true }))

local function Check(frame, r, g, b, source)
    local actual = assert(UF.GetActiveBorderVisual(frame), "missing outline")
    assert(actual.source == source and actual.r == r and actual.g == g and actual.b == b,
        ("%s %s outline was %s %.2f %.2f %.2f"):format(frame.MSUFUnitKey, source, actual.source, actual.r, actual.g, actual.b))
end
local function Event(frame, event)
    frame:GetScript("OnEvent")(frame, event, frame.MSUFUnitKey)
end

Check(target, .15, .65, .95, "normal")
classes.target = "WARRIOR"
Event(target, "PLAYER_TARGET_CHANGED")
Check(target, .8, .5, .2, "normal")

-- Enter and leave a highlight, even as new identity data arrives behind it.
threat = 2
Event(target, "UNIT_THREAT_SITUATION_UPDATE")
assert(UF.GetActiveBorderVisual(target).source == "aggro", "class outline hid aggro")
classes.target = "MAGE"
Event(target, "UNIT_NAME_UPDATE")
assert(UF.GetActiveBorderVisual(target).source == "aggro", "name update hid aggro")
threat = 0
classReads = 0
for _ = 1, 64 do
    Event(target, "UNIT_HEALTH")
    Event(target, "UNIT_THREAT_SITUATION_UPDATE")
end
assert(classReads == 0, "outline caused a class lookup on the health or threat route")
Check(target, .15, .65, .95, "normal")

targetIsPlayer = false
Event(target, "PLAYER_TARGET_CHANGED")
Check(target, .2, .3, .4, "normal")
targetIsPlayer = true
classes.target = nil
Event(target, "PLAYER_TARGET_CHANGED")
Check(target, .2, .3, .4, "normal")
classes.target = "MAGE"
Event(target, "UNIT_NAME_UPDATE")
Check(target, .15, .65, .95, "normal")

local sourceRoot = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local stop = Secrets.Watch({
    sourceRoot .. "MSUF_UF_Elements_Borders.lua",
    sourceRoot .. "MSUF_UF_Elements_BarsCommon.lua",
}, { strict = true })
classes.target = Secrets.New("string")
Event(target, "UNIT_NAME_UPDATE")
Check(target, .2, .3, .4, "normal")
assert(#stop() == 0, "restricted class escaped the class resolver")

db.target.barOutlineClassColor = false
UF.RefreshBorders("target")
assert(target.MSUFSpec.border.classColor == false, "explicit off did not override shared class outlines")
Check(target, .2, .3, .4, "normal")

-- Secure group children consume the same compiled color on roster changes.
local raid = GF.GetConf("raid")
raid.enabled, raid.preserveRaidGroups = true, false
raid.hlOverride, raid.barOutlineThickness = true, 2
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(2)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local member = assert(GF.FrameForUnit("raid1"), "raid member missing")
Check(member, .15, .65, .95, "normal")
classes.raid1 = "WARRIOR"
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
Check(member, .8, .5, .2, "normal")
print("frame_outline_class_color_smoke: ok " .. flavor)
