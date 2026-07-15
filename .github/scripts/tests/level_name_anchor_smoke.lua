-- Regression coverage for name-relative status text on full-width live name regions.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local secretWidth = {}
_G.issecretvalue = function(value) return value == secretWidth end
_G.UnitName = function() return "Captain Garrick" end

local elements = {}
local UF = {
    Layers = {},
    RegisterElement = function(name, element) elements[name] = element end,
    UnitExistsSafe = function() return true end,
    FreshUnitState = function() return nil end,
    ReadConnectedCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
}
local MSUF = { UF = UF, Secrets = { UnitMissing = function() return false end } }
_G.MSUF_NS = MSUF

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local StatusRuntime = assert(MSUF.UFStatusRuntime, "status runtime missing")

local nameWidth = 87
local name = { _msufJustifyH = "LEFT", text = "Astral Warden" }
function name:GetStringWidth() return nameWidth end

local level = { setPointCalls = 0 }
function level:ClearAllPoints() end
function level:SetPoint(point, target, relPoint, x, y)
    self.setPointCalls = self.setPointCalls + 1
    self.point, self.target, self.relPoint, self.x, self.y = point, target, relPoint, x, y
end

local levelCfg = { enabled = true, anchor = "NAMERIGHT", x = 10, y = 2 }
local frame = {
    unit = "target",
    nameText = name,
    levelText = level,
    _msufNameRelativeStatus = true,
    MSUFSpec = { text = {}, status = { enabled = true, level = levelCfg } },
}

Check(StatusRuntime.RefreshNameRelativeAnchors(frame) == true, "name-relative level refresh did not run")
Check(level.point == "LEFT" and level.target == name and level.relPoint == "LEFT",
    "left-justified name did not use its rendered left edge")
Check(level.x == 97 and level.y == 2, "level did not anchor after rendered name width plus offset")

StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.setPointCalls == 1, "unchanged name-relative anchor repeated SetPoint")
nameWidth = 120
StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.x == 130 and level.setPointCalls == 2, "changed name width did not reanchor level text")

name._msufJustifyH = "CENTER"
StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.relPoint == "CENTER" and level.x == 70, "centered name right edge was calculated incorrectly")
name._msufJustifyH = "RIGHT"
StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.relPoint == "RIGHT" and level.x == 10, "right-justified name right edge was calculated incorrectly")

name._msufJustifyH = "LEFT"
nameWidth = secretWidth
StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.relPoint == "LEFT" and level.x == 10,
    "secret name width reached anchor arithmetic instead of using the safe zero-width fallback")
nameWidth = 87

local refreshCalls = 0
local originalRefresh = StatusRuntime.RefreshNameRelativeAnchors
StatusRuntime.RefreshNameRelativeAnchors = function(liveFrame)
    refreshCalls = refreshCalls + 1
    Check(liveFrame.nameText.text == "Captain Garrick", "level refresh ran before the live name changed")
    return originalRefresh(liveFrame)
end

MSUF.UFText = {
    UnitHealth = function() return 100 end,
    UnitHealthMax = function() return 100 end,
    UnitPower = function() return 0 end,
    UnitPowerMax = function() return 0 end,
    UnitPowerType = function() return 0, "MANA" end,
    UnitName = _G.UnitName,
    GetTime = function() return 0 end,
    SetShownCached = function(region, shown) region.shown = shown == true end,
    SetTextCached = function(region, text) region.text = text or "" end,
    SetNameTextColor = function() end,
    NameTextColor = function() return 1, 1, 1 end,
    SetInlineTextColor = function() end,
    InlineTextColor = function() return 1, 1, 1 end,
    SetPowerTextColor = function() end,
    UpdateHealthTextColor = function() end,
    ResolveHealthTextModes = function() return "NONE", "NONE", "NONE" end,
    UpdateTextSlots = function() end,
    EMPTY_EVENTS = {},
    POWER_EVENTS = {},
    POWER_EVENTS_FREQUENT = {},
    floor = math.floor,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

name._msufJustifyH = "LEFT"
name.text = "Astral Warden"
MSUF.UFText.UpdateName(frame, "UNIT_NAME_UPDATE", "target")
Check(refreshCalls == 1, "live name update did not refresh the name-relative level anchor")

print("PASS level name anchor: live glyph edge tracks layout and name changes without redundant SetPoint")
