local root = arg and arg[1] or "."

local function Read(path)
    local handle = assert(io.open(path, "r"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local function Contains(source, needle, message)
    assert(source:find(needle, 1, true), message)
end

local profile = Read(root .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
local groupConfig = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
local textLayout = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua")
local textFormat = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua")
local textRuntime = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua")
local classPower = Read(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua")

Contains(profile, "conf._msufLegacyNameAnchorToFrame = true",
    "5.73 Group profiles do not persist the full-frame name anchor contract")
Contains(groupConfig, "nameAnchorToFrame = conf._msufLegacyNameAnchorToFrame == true",
    "Group config does not compile the migrated 5.73 name anchor root")
Contains(groupConfig, "nameLegacyTruncation = conf._msufLegacyNameAnchorToFrame == true",
    "Group config does not compile the migrated 5.73 name-shortening contract")
Contains(textLayout, "text and text.nameAnchorToFrame == true and frame or BarTextHealthAnchor(frame)",
    "Group text layout does not select the 5.73 full-frame name root")
Contains(textLayout, '"anchorToBars", "nameAnchorToFrame", "nameLegacyTruncation", "nameAnchor"',
    "Group name anchor-root changes are missing from the text layout signature")
Contains(textLayout, "local maxChars = not legacyTruncation",
    "migrated 5.73 names still use the unconditional 6.0 dots renderer")
Contains(textFormat, "rt.nameLegacyTruncation = text.nameLegacyTruncation == true",
    "compiled text runtime loses the migrated 5.73 shortening contract")
Contains(textRuntime, "local function TruncateLegacyGroupName(name, rt)",
    "5.73 runtime name shortening is missing")
Contains(textRuntime, "if count <= maxChars then return name end",
    "5.73 runtime adds dots to names which are already below the character cap")

Contains(classPower, "local QUICK_DPB_HEIGHT = 6",
    "Class Resources Quick Setup lost its detached Player Power fallback height")
Contains(classPower, "local QUICK_DPB_GAP = 4",
    "Class Resources Quick Setup lost its detached Player Power gap")
Contains(classPower,
    "math.ceil(ecvH + QUICK_CDM_GAP + cpH + QUICK_DPB_GAP + dpbH)",
    "Class Resources Quick Setup does not reserve the complete stacked height")
Contains(classPower, "detachedPowerBarOffsetY = -QUICK_DPB_GAP",
    "Class Resources Quick Setup stack gap differs between placement and saved state")
Contains(classPower, 'detachedPowerBarAnchorMode = "CENTER"',
    "Class Resources Quick Setup does not replace migrated legacy anchor semantics")
Contains(classPower, "QuickApplyPhase2NoCP(QuickCalcDPBAboveCDMNoCP(ecv))",
    "Class Resources Quick Setup lost the no-class-resource Player Power fallback")
Contains(classPower, "player.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false",
    "Class Resources Quick Setup cannot detach Player Power from a hidden class-resource anchor")

-- CP.TOP is anchored to ECV.BOTTOM. With the complete offset, the detached
-- Player Power bar ends exactly QUICK_CDM_GAP above the viewer instead of
-- overlapping it.
local ecvH, cpH, dpbH, cdmGap, dpbGap = 40, 8, 6, 4, 4
local cpTop = ecvH + cdmGap + cpH + dpbGap + dpbH
local cpBottom = cpTop - cpH
local detachedBottom = cpBottom - dpbGap - dpbH
assert(detachedBottom == ecvH + cdmGap,
    "Class Resources Quick Setup stack geometry overlaps Essential Cooldowns")

-- A spec without a visible Class Resource anchors Player Power directly above
-- the viewer. These are physical screen coordinates after scale conversion.
local pfCenterX, pfBottom, pfScale = 400, 100, 1
local ecvCenterX, ecvTop, ecvScale = 600, 300, 1
local dpbX = math.floor((ecvCenterX * ecvScale - pfCenterX * pfScale) / pfScale + 0.5)
local dpbY = math.floor((ecvTop * ecvScale + (cdmGap + dpbH) * pfScale - pfBottom * pfScale) / pfScale + 0.5)
assert(pfCenterX + dpbX == ecvCenterX
    and pfBottom + dpbY - dpbH == ecvTop + cdmGap,
    "no-class-resource Player Power is not aligned above Essential Cooldowns")

-- Exercise the exact imported 5.73 string contract: dots only appear after
-- real truncation, both clipping directions remain UTF-8 safe, and secret
-- values are passed through without inspection.
local secretName = {}
_G.issecretvalue = function(value) return value == secretName end
local runtimeUF = {
    RegisterElement = function() end,
    UnitExistsSafe = function() return true end,
    FreshUnitState = function() return nil end,
    ReadConnectedCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
}
local runtimeText = {
    UnitHealth = function() return 100 end,
    UnitHealthMax = function() return 100 end,
    UnitPower = function() return 0 end,
    UnitPowerMax = function() return 0 end,
    UnitPowerType = function() return 0, "MANA" end,
    UnitName = function() return "Makosdass" end,
    GetTime = function() return 0 end,
    SetShownCached = function() end,
    SetTextCached = function() end,
    SetNameTextColor = function() end,
    NameTextColor = function() return 1, 1, 1 end,
    SetInlineTextColor = function() end,
    InlineTextColor = function() return 1, 1, 1 end,
    SetPowerTextColor = function() end,
    UpdateHealthTextColor = function() end,
    ResolveHealthTextModes = function() return "NONE", "NONE", "NONE" end,
    UpdateTextSlots = function() end,
    EMPTY_EVENTS = {}, POWER_EVENTS = {}, POWER_EVENTS_FREQUENT = {},
    floor = math.floor,
}
local runtimeNS = {
    UF = runtimeUF,
    UFText = runtimeText,
    Secrets = { UnitMissing = function() return false end },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"))(
    "MidnightSimpleUnitFrames", runtimeNS)
local truncateLegacy
for index = 1, 100 do
    local name, value = debug.getupvalue(runtimeText.UpdateName, index)
    if not name then break end
    if name == "TruncateLegacyGroupName" then truncateLegacy = value; break end
end
assert(type(truncateLegacy) == "function", "5.73 runtime truncation helper is not wired to UpdateName")
local legacyRt = {
    nameLegacyTruncation = true,
    nameLegacyShortenMax = 16,
    nameShortenSide = "RIGHT",
    nameLegacyShortenDots = true,
}
assert(truncateLegacy("Makosdass", legacyRt) == "Makosdass",
    "an imported short Group name received unconditional dots")
legacyRt.nameLegacyShortenMax = 9
assert(truncateLegacy("MakosdassLong", legacyRt) == "Makosdass..",
    "right-side 5.73 truncation changed")
legacyRt.nameLegacyShortenMax, legacyRt.nameShortenSide = 4, "LEFT"
assert(truncateLegacy("Makosdass", legacyRt) == "..dass",
    "left-side 5.73 truncation changed")
legacyRt.nameLegacyShortenMax, legacyRt.nameShortenSide = 3, "RIGHT"
assert(truncateLegacy("ÄonLong", legacyRt) == "Äon..",
    "5.73 UTF-8 truncation changed")
assert(truncateLegacy(secretName, legacyRt) == secretName,
    "secret Group name was inspected during legacy truncation")

print("PASS 5.73 Group name anchoring and Class Resources Quick Setup stack")
