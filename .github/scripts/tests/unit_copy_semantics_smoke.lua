local ROOT = arg and arg[1] or "."

local function Words(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function WordSet(text)
    local out = {}
    for _, word in ipairs(Words(text)) do out[word] = true end
    return out
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = DeepCopy(child) end
    return out
end

local M = {
    Widgets = {},
    navSubpageLabels = {},
    ValueTextList = function(...) return { ... } end,
    ValueTextRows = function() return {} end,
    ValueTextPairs = function() return {} end,
    KeyLabelRows = function() return {} end,
    KeySetFromWords = WordSet,
    WordList = Words,
    CopyFieldsFromSpecs = function() return {} end,
    DeepCopy = DeepCopy,
    Tr = function(text) return text end,
    RequestUnitApply = function() end,
}
function M.Assign(target, source)
    for key, value in pairs(source) do target[key] = value end
    return target
end
function M.EnsureDB()
    return assert(_G.MSUF_DB, "test DB missing")
end
function M.GetUnitDB(unit)
    return M.EnsureDB()[unit]
end
function M.GetGeneralDB()
    return M.EnsureDB().general
end

local namespace = {
    MSUF2 = M,
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
assert(loadfile(ROOT .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"))(
    "MidnightSimpleUnitFrames", namespace)
local CopyUnitSettings = assert(M.UnitPage and M.UnitPage.CopyUnitSettings)

local function NewDB()
    _G.MSUF_DB = {
        general = {},
        player = {},
        target = {},
        focus = {},
        targettarget = {},
        focustarget = {},
        pet = {},
        boss = {},
    }
    return _G.MSUF_DB
end

-- Boss uses bossCast for visual fields but bossCastbar for detachment and frame
-- offsets. Both copy directions must use the real geometry keys.
local db = NewDB()
local g = db.general
g.bossCastbarBackend = "MSUF"
g.enableBossCastbar = true
g.bossCastbarDetached = false
g.bossCastbarOffsetX = 31
g.bossCastbarOffsetY = -32
g.bossCastIconPosition = "RIGHT"
g.castbarTargetBackend = "MSUF"
g.enableTargetCastbar = true
g.castbarTargetDetached = false
g.castbarTargetOffsetX = 1
g.castbarTargetOffsetY = 2
g.castbarTargetIconPosition = "LEFT"
g.castbarTargetIconSize = 77
g.castbarTargetBarWidth = 201
g.castbarTargetBackendBeforeHide = "MSUF"
CopyUnitSettings("boss", "target", { castbar = true })
assert(g.castbarTargetOffsetX == 31 and g.castbarTargetOffsetY == -32,
    "Boss anchored offsets did not map to Target geometry keys")
assert(g.castbarTargetIconPosition == "RIGHT",
    "Boss visual prefix did not map to Target")
assert(g.castbarTargetIconSize == 77 and g.castbarTargetBarWidth == 201
    and g.castbarTargetBackendBeforeHide == "MSUF",
    "missing Boss values erased valid Target castbar settings")

g.castbarTargetOffsetX = 41
g.castbarTargetOffsetY = -42
g.castbarTargetIconPosition = "LEFT"
g.bossCastbarOffsetX = 3
g.bossCastbarOffsetY = 4
CopyUnitSettings("target", "boss", { castbar = true })
assert(g.bossCastbarOffsetX == 41 and g.bossCastbarOffsetY == -42,
    "Target anchored offsets did not map to Boss geometry keys")
assert(g.bossCastIconPosition == "LEFT",
    "Target visual prefix did not map to Boss")

-- Detached positions are absolute UIParent coordinates. A detached source or
-- destination must retain the destination position instead of stacking frames.
g.castbarTargetDetached = true
g.castbarTargetOffsetX = 501
g.castbarTargetOffsetY = 502
g.bossCastbarDetached = false
g.bossCastbarOffsetX = 61
g.bossCastbarOffsetY = 62
CopyUnitSettings("target", "boss", { castbar = true })
assert(g.bossCastbarOffsetX == 61 and g.bossCastbarOffsetY == 62,
    "detached source position leaked into anchored Boss")

g.castbarTargetDetached = false
g.bossCastbarDetached = true
g.bossCastbarOffsetX = 71
g.bossCastbarOffsetY = 72
CopyUnitSettings("target", "boss", { castbar = true })
assert(g.bossCastbarOffsetX == 71 and g.bossCastbarOffsetY == 72,
    "anchored source position overwrote detached Boss position")

-- Boss container layout has no semantic equivalent on a single unit frame.
-- Copying Player geometry to Boss must preserve all Boss-only layout fields.
db = NewDB()
db.player.width = 260
db.player.height = 42
db.player.offsetX = 12
db.player.offsetY = -14
db.player.point = "TOPLEFT"
db.player.relativePoint = "TOPLEFT"
db.player.anchorFrameName = "UIParent"
db.player.anchorToUnitframe = false
db.boss.width = 180
db.boss.height = 38
db.boss.bossLayoutMode = "HORIZONTAL_LEFT"
db.boss.invertBossOrder = true
db.boss.spacing = -123
CopyUnitSettings("player", "boss", { layout = true })
assert(db.boss.width == 260 and db.boss.height == 42
    and db.boss.offsetX == 12 and db.boss.offsetY == -14,
    "portable frame geometry was not copied to Boss")
assert(db.boss.bossLayoutMode == "HORIZONTAL_LEFT"
    and db.boss.invertBossOrder == true and db.boss.spacing == -123,
    "normal-unit layout copy erased Boss-only container layout")

db.target.bossLayoutMode = "target-sentinel"
db.target.invertBossOrder = "target-sentinel"
db.target.spacing = "target-sentinel"
CopyUnitSettings("boss", "target", { layout = true })
assert(db.target.bossLayoutMode == "target-sentinel"
    and db.target.invertBossOrder == "target-sentinel"
    and db.target.spacing == "target-sentinel",
    "Boss-only container layout leaked into a normal unit")

print("PASS unit copy semantics: Boss castbar mapping, detached guard, nil safety, Boss layout isolation")
