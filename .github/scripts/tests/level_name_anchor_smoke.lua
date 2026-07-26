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

local name = { _msufJustifyH = "LEFT", text = "Astral Warden" }
function name:GetStringWidth() error("name-relative anchor must not read restricted geometry") end
local nameAnchor = { text = "Astral Warden" }

local level = { setPointCalls = 0 }
function level:ClearAllPoints() end
function level:SetPoint(point, target, relPoint, x, y)
    self.setPointCalls = self.setPointCalls + 1
    self.point, self.target, self.relPoint, self.x, self.y = point, target, relPoint, x, y
end

local levelCfg = { enabled = true, anchor = "NAMERIGHT", x = 10, y = 2 }
local frame = {
    unit = "target",
    MSUFUnitKey = "target",
    nameText = name,
    _msufNameAnchorText = nameAnchor,
    _msufNameAnchorTextActive = true,
    levelText = level,
    _msufNameRelativeStatus = true,
    MSUFSpec = { text = {}, status = { enabled = true, level = levelCfg } },
}

Check(StatusRuntime.RefreshNameRelativeAnchors(frame) == true, "name-relative level refresh did not run")
Check(level.point == "LEFT" and level.target == nameAnchor and level.relPoint == "RIGHT",
    "name-relative level did not use the secret-safe glyph-edge proxy")
Check(level.x == 10 and level.y == 2, "name-relative level offset changed")

StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.setPointCalls == 1, "unchanged name-relative anchor repeated SetPoint")
levelCfg.anchor = "NAMELEFT"
StatusRuntime.RefreshNameRelativeAnchors(frame)
Check(level.point == "RIGHT" and level.target == nameAnchor and level.relPoint == "LEFT",
    "NAMELEFT did not use the secret-safe glyph-edge proxy")
levelCfg.anchor = "NAMERIGHT"

local refreshCalls = 0
StatusRuntime.RefreshNameRelativeAnchors = function(liveFrame)
    refreshCalls = refreshCalls + 1
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
Check(name.text == "Captain Garrick", "live name text was not updated")
Check(nameAnchor.text == "Captain Garrick", "secret-safe glyph-edge proxy did not follow the live name")
Check(refreshCalls == 0, "live name update repeated cold SetPoint work")

local statusSource = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua", "rb")):read("*a")
Check(statusSource:find("name:GetStringWidth()", 1, true) == nil,
    "name-relative status anchoring regressed to restricted width arithmetic")
local layoutSource = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua", "rb")):read("*a")
Check(layoutSource:find("Text.EnsureNameAnchorProxy = EnsureNameAnchorProxy", 1, true) ~= nil,
    "secret-safe bar-name anchor proxy is not exported")
Check(layoutSource:find("proxy:SetAlpha(0)", 1, true) ~= nil,
    "bar-name anchor proxy is not visually inert")
local menuSource = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua", "rb")):read("*a")
Check(menuSource:find('local STATUS_LEVEL_ANCHORS = WithNameAnchors("Right to name", "Left to name")', 1, true) ~= nil,
    "unit status menu still labels name-relative anchors as player-only")

print("PASS level name anchor: secret-safe glyph edge tracks live names without hotpath SetPoint")
