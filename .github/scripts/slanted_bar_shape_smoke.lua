-- Exercise per-frame shape precedence without a live WoW client.
local Slice = assert(loadfile(".github/scripts/msuf_source_slice.lua"))()
local path = "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedSurface.lua"
local source = Slice.Read(path)
local declarations = {
    "local function UpdateSlantedBarState",
    "local function IsConfiguredEnabled",
    "local function IsEnabled",
    "local function RoundedPowerBarsEnabled",
    "local function FrameIsGroup",
    "local function SlantedScopeEnabled",
    "local function FrameConfig",
    "ResolveFrameStyle = function",
    "local function RoundedFrameEnabled",
    "local function SlantedDirection",
    "local function SurfaceMaskPath",
    "local function SurfaceEdgePath",
}
local chunks = {}
for _, declaration in ipairs(declarations) do
    chunks[#chunks + 1] = Slice.Function(source, declaration, path)
end
local harness = [[
local forceDisabled = false
local slantedBarsEnabled = true
local slantedUnitFramesEnabled = true
local slantedGroupFramesEnabled = true
local slantedPowerBarsEnabled = true
local slantedMouseoverEnabled = true
local slantedExtraSurfacesEnabled = false
local slantedCastbarsEnabled = false
local slantedClassResourcesEnabled = false
local UNIT_SHAPE_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }
local GROUP_SHAPE_KEYS = { "gf_party", "gf_raid", "gf_mythicraid" }
local roundedMaskPath, roundedEdgePath = "rounded-mask", "rounded-edge"
local SLANTED_MASK_PATHS = {
    RIGHT_DOWN = "slanted-mask", RIGHT_UP = "slanted-mask-right-up",
    LEFT_DOWN = "slanted-mask-left-down", LEFT_UP = "slanted-mask-left-up",
    BOTH_DOWN = "slanted-mask-both-down", BOTH_UP = "slanted-mask-both-up",
}
local SLANTED_EDGE_PATHS = {
    RIGHT_DOWN = "slanted-edge", RIGHT_UP = "slanted-edge-right-up",
    LEFT_DOWN = "slanted-edge-left-down", LEFT_UP = "slanted-edge-left-up",
    BOTH_DOWN = "slanted-edge-both-down", BOTH_UP = "slanted-edge-both-up",
}
local MSUF = { UF = { ConfigKeyForUnit = function(unit)
    if unit == "boss1" then return "boss" end
    if unit == "arena2" then return "arena" end
    return unit
end } }
local ResolveFrameStyle
local function ReadRoundedBool(key, fallback)
    local value = _G.MSUF_DB.bars[key]
    if value == nil then return fallback == true end
    return value == true
end
]] .. table.concat(chunks, "\n") .. [[

return ResolveFrameStyle, RoundedFrameEnabled, RoundedPowerBarsEnabled,
    SurfaceMaskPath, SurfaceEdgePath, IsConfiguredEnabled, MSUF, UpdateSlantedBarState
]]
local compile = loadstring or load
local style, enabled, power, mask, edge, configured, msuf, updateSlanted = assert(compile(harness))()
_G.MSUF_DB = {
    bars = { roundedFramesEnabled = false, roundedPowerBars = false },
    player = { frameBarShape = "SLANTED" },
    target = { frameBarShape = "SQUARE" },
    gf_party = { frameBarShape = "ROUNDED" },
    gf_raid = { frameBarShape = "SLANTED" },
    boss = { frameBarShape = "SLANTED" },
    arena = { frameBarShape = "ROUNDED" },
}
local player = { MSUFUnitKey = "player" }
local target = { MSUFUnitKey = "target" }
local focus = { MSUFUnitKey = "focus" }
local party = { _msufIsGroupFrame = true, _msufGFKind = "party" }
local raid = { _msufIsGroupFrame = true, _msufGFKind = "raid" }
local storedRaid = { _msufIsGroupFrame = true }
msuf.GF = { frames = { [storedRaid] = "raid" } }
local boss = { MSUFUnitKey = "boss1", MSUFSpec = { key = "boss" } }
local arena = { MSUFUnitKey = "arena2" }
assert(configured() and enabled(player) and style(player) == "SLANTED")
assert(mask(player) == "slanted-mask" and edge(player) == "slanted-edge" and power(player))
assert(style(party) == "ROUNDED" and mask(party) == "rounded-mask" and power(party))
assert(style(raid) == "SLANTED" and mask(raid) == "slanted-mask")
assert(style(storedRaid) == "SLANTED")
assert(style(boss) == "SLANTED" and style(arena) == "ROUNDED")
assert(style(target) == "SQUARE" and not enabled(target))
assert(style(focus) == "SQUARE" and not enabled(focus))
_G.MSUF_DB.bars.slantedUnitFrames = false
updateSlanted()
assert(style(player) == "SQUARE" and style(raid) == "SLANTED")
_G.MSUF_DB.bars.slantedUnitFrames = true
_G.MSUF_DB.bars.slantedGroupFrames = false
updateSlanted()
assert(style(player) == "SLANTED" and style(raid) == "SQUARE")
_G.MSUF_DB.bars.slantedGroupFrames = true
_G.MSUF_DB.bars.slantedPowerBars = false
updateSlanted()
assert(not power(player) and not power(raid) and power(party))
_G.MSUF_DB.bars.slantedPowerBars = true
updateSlanted()
local fullDB = _G.MSUF_DB
_G.MSUF_DB = { bars = { roundedFramesEnabled = false }, pettarget = { frameBarShape = "SLANTED" } }
assert(configured() and enabled({ MSUFUnitKey = "pettarget" }))
_G.MSUF_DB.bars.slantedBarsEnabled = false
updateSlanted()
assert(not configured() and not enabled({ MSUFUnitKey = "pettarget" }))
assert(style({ MSUFUnitKey = "pettarget" }) == "SQUARE")
_G.MSUF_DB.pettarget = nil
_G.MSUF_DB.bars.slantedBarsEnabled = true
_G.MSUF_DB.bars.slantedCastbars = true
updateSlanted()
assert(configured(), "slanted castbars alone must activate the surface controller")
_G.MSUF_DB = fullDB
_G.MSUF_DB.bars.slantedBarsEnabled = false
updateSlanted()
assert(style(player) == "SQUARE" and style(raid) == "SQUARE")
assert(style(party) == "ROUNDED" and style(arena) == "ROUNDED")
assert(not power(player) and not enabled(raid))
_G.MSUF_DB.bars.slantedBarsEnabled = true
updateSlanted()
assert(style(player) == "SLANTED" and style(raid) == "SLANTED")
_G.MSUF_DB.bars.roundedFramesEnabled = true
_G.MSUF_DB.bars.roundedUnitFrames = true
_G.MSUF_DB.bars.roundedGroupFrames = true
_G.MSUF_DB.bars.slantedBarsEnabled = false
updateSlanted()
assert(style(player) == "ROUNDED" and style(raid) == "ROUNDED",
    "disabling slanted must reveal the active rounded style")
_G.MSUF_DB.bars.slantedBarsEnabled = true
updateSlanted()
assert(style(focus) == "ROUNDED" and enabled(focus) and not power(focus))
assert(style(target) == "SQUARE" and not enabled(target))
assert(style(player) == "SLANTED" and mask(player) == "slanted-mask")
for _, direction in ipairs({ "RIGHT_DOWN", "RIGHT_UP", "LEFT_DOWN", "LEFT_UP", "BOTH_DOWN", "BOTH_UP" }) do
    _G.MSUF_DB.bars.slantedBarDirection = direction
    local suffix = direction == "RIGHT_DOWN" and "" or "-" .. direction:lower():gsub("_", "-")
    assert(mask(player) == "slanted-mask" .. suffix and edge(raid) == "slanted-edge" .. suffix, direction)
end
_G.MSUF_DB.bars.slantedBarDirection = "INVALID"
assert(mask(player) == "slanted-mask" and edge(raid) == "slanted-edge")

local helpersPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"
local helpersSource = Slice.Read(helpersPath)
local mediaFunction = Slice.Function(helpersSource, "function H.ResolveFrameBarMedia", helpersPath)
local mediaHarness = [[
local MSUF = ...
local H = { ResolveRoundedMedia = function() return "rounded-mask", "rounded-edge", 3 end }
local SLANTED_MASK_PATHS = {
    RIGHT_DOWN = "slanted-mask", RIGHT_UP = "slanted-mask-right-up",
    LEFT_DOWN = "slanted-mask-left-down", LEFT_UP = "slanted-mask-left-up",
    BOTH_DOWN = "slanted-mask-both-down", BOTH_UP = "slanted-mask-both-up",
}
local SLANTED_EDGE_PATHS = {
    RIGHT_DOWN = "slanted-edge", RIGHT_UP = "slanted-edge-right-up",
    LEFT_DOWN = "slanted-edge-left-down", LEFT_UP = "slanted-edge-left-up",
    BOTH_DOWN = "slanted-edge-both-down", BOTH_UP = "slanted-edge-both-up",
}
]] .. mediaFunction .. "\nreturn H.ResolveFrameBarMedia"
local previewMedia = assert(compile(mediaHarness))({ RoundedSurface = {
    ResolveSlantedMedia = function(scope, conf)
        local f = { configKey = scope, _msufRUFDirectionConfig = conf, _msufRUFForcedStyle = "SLANTED" }
        return mask(f), edge(f), 0
    end,
} })
for _, direction in ipairs({ "RIGHT_DOWN", "RIGHT_UP", "LEFT_DOWN", "LEFT_UP", "BOTH_DOWN", "BOTH_UP" }) do
    _G.MSUF_DB.bars.slantedBarDirection = direction
    assert(previewMedia("SLANTED") == mask(player), "preview/runtime mask mismatch: " .. direction)
end
assert(previewMedia("ROUNDED") == "rounded-mask")
_G.MSUF_DB.bars.slantedBarDirection = nil

local castbarPath = "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRounded.lua"
local castbarSource = Slice.Read(castbarPath)
local castbarStyle = Slice.Function(castbarSource, "local function SettingStyle", castbarPath)
local castbarMedia = Slice.Function(castbarSource, "local function ResolveMedia", castbarPath)
local castbarHarness = [[
local RoundedSurface = {
    ResolveMedia = function() return "rounded-cast-mask", "rounded-cast-edge" end,
    ResolveSlantedMedia = function() return "slanted-cast-mask", "slanted-cast-edge" end,
}
local function BarsDB() return _G.MSUF_DB.bars end
]] .. castbarStyle .. "\n" .. castbarMedia .. "\nreturn SettingStyle, ResolveMedia"
local castStyle, castMedia = assert(compile(castbarHarness))()
_G.MSUF_DB.bars.roundedCastbars = true
assert(castStyle() == "ROUNDED" and castMedia() == "rounded-cast-mask")
_G.MSUF_DB.bars.slantedCastbars = true
assert(castStyle() == "SLANTED" and castMedia() == "slanted-cast-mask")
_G.MSUF_DB.bars.slantedBarsEnabled = false
assert(castStyle() == "ROUNDED" and castMedia() == "rounded-cast-mask")
_G.MSUF_DB.bars.roundedCastbars = false
assert(castStyle() == nil)
_G.MSUF_DB.bars.slantedBarsEnabled = true
_G.MSUF_DB.bars.slantedCastbars = false

local unitPreviewPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua"
local unitPreview = Slice.Read(unitPreviewPath)
local previewStyle = Slice.Function(unitPreview, "local function PreviewFrameStyle", unitPreviewPath)
local previewPower = Slice.Function(unitPreview, "local function PreviewRoundedPowerBarsEnabled", unitPreviewPath)
local previewHarness = [[
local function UnitDB(key) return _G.MSUF_DB[key] end
local function ReadPreviewBarsBool(key, fallback)
    local value = _G.MSUF_DB.bars[key]
    if value == nil then return fallback == true end
    return value == true
end
]] .. previewStyle .. "\n" .. previewPower .. "\n" .. [[
return PreviewFrameStyle, PreviewRoundedPowerBarsEnabled
]]
local unitPreviewStyle, unitPreviewPower = assert(compile(previewHarness))()
assert(unitPreviewStyle("player") == "SLANTED" and unitPreviewPower("player"))
assert(unitPreviewStyle("target") == "SQUARE" and not unitPreviewPower("target"))
assert(unitPreviewStyle("focus") == "ROUNDED" and not unitPreviewPower("focus"))
_G.MSUF_DB.bars.slantedBarsEnabled = false
assert(unitPreviewStyle("player") == "ROUNDED" and not unitPreviewPower("player"))
_G.MSUF_DB.bars.slantedBarsEnabled = true
_G.MSUF_DB.bars.slantedUnitFrames = false
assert(unitPreviewStyle("player") == "ROUNDED" and not unitPreviewPower("player"))
_G.MSUF_DB.bars.slantedUnitFrames = true
_G.MSUF_DB.bars.slantedPowerBars = false
assert(unitPreviewStyle("player") == "SLANTED" and not unitPreviewPower("player"))
_G.MSUF_DB.bars.slantedPowerBars = true

local groupPreviewPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Rounded.lua"
local groupPreview = Slice.Read(groupPreviewPath)
local groupStyle = Slice.Function(groupPreview, "local function FrameStyle", groupPreviewPath)
local groupPower = Slice.Function(groupPreview, "local function RoundedPowerEnabled", groupPreviewPath)
local groupHarness = [[
local function ReadBarsBool(key, fallback)
    local value = _G.MSUF_DB.bars[key]
    if value == nil then return fallback == true end
    return value == true
end
]] .. groupStyle .. "\n" .. groupPower .. "\n" .. [[
return FrameStyle, RoundedPowerEnabled
]]
local groupPreviewStyle, groupPreviewPower = assert(compile(groupHarness))()
assert(groupPreviewStyle(_G.MSUF_DB.gf_raid) == "SLANTED" and groupPreviewPower(_G.MSUF_DB.gf_raid))
assert(groupPreviewStyle(_G.MSUF_DB.gf_party) == "ROUNDED" and groupPreviewPower(_G.MSUF_DB.gf_party))
_G.MSUF_DB.bars.slantedBarsEnabled = false
assert(groupPreviewStyle(_G.MSUF_DB.gf_raid) == "ROUNDED" and not groupPreviewPower(_G.MSUF_DB.gf_raid))
_G.MSUF_DB.bars.slantedBarsEnabled = true
_G.MSUF_DB.bars.slantedGroupFrames = false
assert(groupPreviewStyle(_G.MSUF_DB.gf_raid) == "ROUNDED" and not groupPreviewPower(_G.MSUF_DB.gf_raid))
_G.MSUF_DB.bars.slantedGroupFrames = true
_G.MSUF_DB.bars.slantedPowerBars = false
assert(groupPreviewStyle(_G.MSUF_DB.gf_raid) == "SLANTED" and not groupPreviewPower(_G.MSUF_DB.gf_raid))
_G.MSUF_DB.bars.slantedPowerBars = true

-- Execute the actual preset action: one history step, every frame scope, and
-- no reset of existing frame colors or portrait options.
local menuPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua"
local menuSource = Slice.Read(menuPath)
local roundedSetter = Slice.Function(menuSource, "local function SetRoundedBool", menuPath)
local roundedHarness = [[
local db = { bars = { roundedFramesEnabled = false, slantedBarsEnabled = true, slantedUnitFrames = true } }
local applied, refreshed, popup = 0, 0, 0
local M = { RequestRefresh = function() refreshed = refreshed + 1 end }
local function Bars() return db.bars end
local function ApplyRoundedRuntime() applied = applied + 1 end
local function ShowRoundedReloadRequiredPopup() popup = popup + 1 end
]] .. roundedSetter .. "\n" .. [[
return SetRoundedBool, db, function() return applied, refreshed, popup end
]]
local setRounded, roundedDB, roundedState = assert(compile(roundedHarness))()
setRounded("roundedFramesEnabled", true, true)
assert(roundedDB.bars.roundedFramesEnabled == true and roundedDB.bars.slantedBarsEnabled == false
    and roundedDB.bars.slantedUnitFrames == true, "rounded master must reveal rounded frames without losing slanted choices")
assert(select(1, roundedState()) == 1 and select(2, roundedState()) == 1 and select(3, roundedState()) == 1)
local presetStart = assert(menuSource:find("local function BuildSlantedSection", 1, true))
local presetEnd = assert(menuSource:find("\n-- Upgrade-tour playground", presetStart, true))
local buildPreset = menuSource:sub(presetStart, presetEnd - 1)
local selectedStyles = Slice.Function(menuSource, "local function SlantedStylesSelected", menuPath)
local switchOn = Slice.Function(menuSource, "local function SlantedSwitchOn", menuPath)
local applyCount = 0
local oldApply = _G.MSUF_ApplyRoundedUnitframes
_G.MSUF_ApplyRoundedUnitframes = function() applyCount = applyCount + 1 end
local directionGet = Slice.Function(menuSource, "local function SlantedDirectionForScope", menuPath)
local directionSet = Slice.Function(menuSource, "local function SetSlantedDirectionForScope", menuPath)
local presetHarness = [[
local db = { player = { healthColorMode = "class" }, gf_party = { portraitMode = "LEFT" } }
local presetButton, historySource, refreshCount, directionSetter, previewCount, switchGet, switchSet
local scopeControls = {}
refreshCount = 0
previewCount = 0
local SLANTED_PRESET_UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }
local SLANTED_PRESET_GROUPS = { "gf_party", "gf_raid", "gf_mythicraid" }
local SLANTED_DIRECTION_VALUES = {
    { value = "RIGHT_DOWN" }, { value = "RIGHT_UP" }, { value = "LEFT_DOWN" },
    { value = "LEFT_UP" }, { value = "BOTH_DOWN" }, { value = "BOTH_UP" },
}
local M = {
    RunWithHistory = function(_, source, fn) historySource = source; return fn() end,
    RequestRefresh = function() refreshCount = refreshCount + 1 end,
    RegisterSearchWidget = function() end,
    BindDropdownWidget = function(_, _, _, setter) directionSetter = setter end,
    BindBoolWidget = function(_, _, getter, setter, meta)
        if meta.path == "slanted.enabled" then switchGet, switchSet = getter, setter
        else scopeControls[meta.path] = { get = getter, set = setter } end
    end,
    RefreshProxy = function()
        local refresh
        return function(value)
            if type(value) == "function" then refresh = value; return value end
            if refresh then refresh() end
        end
    end,
    BindGateGroup = function(_, _, entries, opts)
        return function()
            assert(entries[1].on() == switchGet())
            if opts.also then opts.also() end
        end
    end,
}
local W = {
    Text = function() end,
    Dropdown = function() return {} end,
    SwitchAt = function() return {} end,
    ToggleAt = function() return {} end,
    Button = function()
        presetButton = { SetScript = function(self, event, fn)
            assert(event == "OnClick")
            self.click = fn
        end }
        return presetButton
    end,
    MoveWidget = function() end,
}
local T = { colors = { muted = {} } }
local function CurrentBarsScope() return "shared" end
local function ScopeDBKeys() end
local function ApplyRoundedRuntime() _G.MSUF_ApplyRoundedUnitframes() end
local function DB() return db end
local function Bars() db.bars = db.bars or {}; return db.bars end
local function ReadB(key, fallback)
    local value = Bars()[key]
    if value == nil then return fallback end
    return value
end
local function CreateSlantedBarPreview() return { RefreshSlantedPreview = function() previewCount = previewCount + 1 end } end
local function min(a, b) return math.min(a, b) end
local function Meta(path) return { path = path } end
local function RegisterControl() end
]] .. selectedStyles .. "\n" .. switchOn .. "\n" .. directionGet .. "\n" .. directionSet .. "\n" .. buildPreset .. [[
return BuildSlantedSection, function()
    return presetButton, historySource, refreshCount, directionSetter, previewCount, switchGet, switchSet, scopeControls
end, db
]]
local build, state, db = assert(compile(presetHarness))()
build({}, { width = 720, CollapsibleSection = function() return {} end })
local presetButton, historySource, refreshCount = state()
assert(presetButton and type(presetButton.click) == "function")
local _, _, _, _, _, getSwitch, setSwitch = state()
assert(type(getSwitch) == "function" and type(setSwitch) == "function" and not getSwitch())
local _, _, _, _, _, _, _, scopeControls = state()
assert(not scopeControls["slanted.castbars"].get() and not scopeControls["slanted.class_resources"].get())
assert(scopeControls["slanted.units"].get() and scopeControls["slanted.groups"].get())
local _, _, _, setDirection = state()
assert(type(setDirection) == "function")
setDirection("LEFT_UP")
assert(db.bars.slantedBarDirection == "LEFT_UP" and applyCount == 1)
local _, _, _, _, previewCount = state()
assert(previewCount == 1)
setDirection("INVALID")
assert(db.bars.slantedBarDirection == "LEFT_UP" and applyCount == 1)
db.bars.roundedFramesEnabled = true
setSwitch(true)
assert(getSwitch() and db.bars.slantedBarsEnabled == true and db.bars.roundedFramesEnabled == false
    and applyCount == 2 and select(3, state()) == 2,
    "switch on: " .. tostring(getSwitch()) .. "/" .. tostring(db.bars.slantedBarsEnabled)
    .. " applies=" .. tostring(applyCount) .. " refreshes=" .. tostring(select(3, state())))
for _, key in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    assert(db[key].frameBarShape == "SLANTED", key)
end
scopeControls["slanted.power"].set(false)
assert(db.bars.slantedPowerBars == false and not scopeControls["slanted.power"].get())
scopeControls["slanted.units"].set(false)
assert(db.bars.slantedUnitFrames == false and db.player.frameBarShape == "SLANTED")
for _, key in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    db[key].frameBarShape = "SQUARE"
end
scopeControls["slanted.units"].set(true)
assert(db.player.frameBarShape == "SLANTED" and db.boss.frameBarShape == "SLANTED")
scopeControls["slanted.groups"].set(false)
assert(db.bars.slantedGroupFrames == false and db.gf_party.frameBarShape == "SLANTED")
scopeControls["slanted.castbars"].set(true)
scopeControls["slanted.class_resources"].set(true)
scopeControls["slanted.mouseover"].set(false)
assert(db.bars.slantedUnitFrames == true and db.bars.slantedGroupFrames == false
    and db.bars.slantedCastbars == true
    and db.bars.slantedClassResources == true and db.bars.slantedMouseover == false)
local afterScopes = applyCount
setSwitch(false)
assert(not getSwitch() and db.bars.slantedBarsEnabled == false and applyCount == afterScopes + 1)
assert(db.player.frameBarShape == "SLANTED" and db.gf_party.frameBarShape == "SLANTED")
presetButton.click()
local stateButton
stateButton, historySource, refreshCount = state()
assert(historySource == "bars:slanted-preset" and applyCount == afterScopes + 2 and refreshCount == afterScopes + 2)
assert(getSwitch() and db.bars.slantedBarsEnabled == true)
assert(db.bars.slantedGroupFrames == true, "preset must restore the group scope")
for _, key in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena",
    "gf_party", "gf_raid", "gf_mythicraid" }) do
    assert(db[key] and db[key].frameBarShape == "SLANTED", key)
end
assert(db.player.healthColorMode == "class" and db.gf_party.portraitMode == "LEFT")
presetButton.click()
stateButton, historySource, refreshCount = state()
assert(applyCount == afterScopes + 2 and refreshCount == afterScopes + 2, "preset must be idempotent")
_G.MSUF_ApplyRoundedUnitframes = oldApply
io.write("slanted_bar_shape_smoke: ok\n")
