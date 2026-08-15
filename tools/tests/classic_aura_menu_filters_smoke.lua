local root = assert(arg[1], "repository root is required")

local function ValueTextList(...)
    local values = {}
    for i = 1, select("#", ...), 2 do
        values[#values + 1] = { value = select(i, ...), text = select(i + 1, ...) }
    end
    return values
end

local function ValueTextPairs(rows)
    local values = {}
    for row in tostring(rows or ""):gmatch("[^|]+") do
        local value, text = row:match("^([^=]+)=(.*)$")
        values[#values + 1] = { value = value, text = text }
    end
    return values
end

local function KeySetFromWords(words)
    local values = {}
    for word in tostring(words or ""):gmatch("%S+") do values[word] = true end
    return values
end

local groupConfigs = { party = {}, raid = {}, mythicraid = {} }
local queued, previews, controls, sections, refreshers = {}, 0, {}, {}, {}

local function AuraGroup(kind, lane)
    local conf = groupConfigs[kind]
    conf.auras = conf.auras or {}
    conf.auras[lane] = conf.auras[lane] or {}
    return conf.auras[lane]
end

local groupPage = {
    Conf = function(kind) return groupConfigs[kind] end,
    QueueGF = function(kind, mode)
        queued[#queued + 1] = { kind = kind, mode = mode }
    end,
    RefreshGFPreview = function() previews = previews + 1 end,
}

local widgets = {
    Text = function() return {} end,
    SetControlEnabled = function(control, enabled) control.enabled = enabled end,
}

local menu
menu = {
    Widgets = widgets,
    Theme = { colors = { muted = { 1, 1, 1, 1 } } },
    GroupPage = groupPage,
    ValueTextList = ValueTextList,
    ValueTextPairs = ValueTextPairs,
    KeySetFromWords = KeySetFromWords,
    BindSwitchAt = function(_, _, label, x, y, width, getValue, setValue, meta)
        local control = {
            label = label,
            x = x,
            y = y,
            width = width,
            getValue = getValue,
            setValue = setValue,
            meta = meta,
        }
        controls[#controls + 1] = control
        return control
    end,
    BindToggleAt = function() error("Classic group filters unexpectedly built a toggle") end,
    BindSliderAt = function() error("Classic group filters unexpectedly built a slider") end,
    AddTooltip = function() end,
    Format = string.format,
    RegisterPage = function() end,
    SetMenuStateValue = function(key, value) menu[key] = value end,
    TrackRefresh = function(_, refresh)
        refreshers[#refreshers + 1] = refresh
        refresh()
    end,
}

local model = {}
function model.ReadGroupBlacklistHidePermanent(scope, lane)
    local kind = scope == "party" and "party" or "raid"
    local blacklist = AuraGroup(kind, lane).blacklist
    return type(blacklist) == "table" and blacklist.hidePermanent == true or false
end
function model.WriteGroupBlacklistHidePermanent(scope, lane, value)
    local nextValue = value == true
    local changed = false
    local kinds = scope == "party" and { "party" } or { "raid", "mythicraid" }
    for i = 1, #kinds do
        local group = AuraGroup(kinds[i], lane)
        group.blacklist = group.blacklist or {}
        if group.blacklist.hidePermanent ~= nextValue then
            group.blacklist.hidePermanent = nextValue
            changed = true
        end
    end
    return changed
end

local namespace = {
    Client = { IsClassic = true },
    MSUF2 = menu,
    MSUF_Auras3 = { MenuModel = model },
}

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = 2
VT = nil

local auraMenuPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Classic.lua"
local auraMenuFile = assert(io.open(auraMenuPath, "rb"))
local auraMenuSource = auraMenuFile:read("*a")
auraMenuFile:close()
assert(not auraMenuSource:match("%f[%w]VT%s*%("),
    "Aura menu retains an unresolved global VT call")

assert(loadfile(auraMenuPath))("MidnightSimpleUnitFrames", namespace)
assert(type(menu.BuildAuras3GroupLaneWorkspace) == "function",
    "Classic group Aura workspace builder was not exported")

local builder = { width = 720 }
function builder:Section(title, height)
    local section = { title = title, height = height, _msuf2Width = self.width }
    sections[#sections + 1] = section
    return section
end

local function BuildClassicLane(lane)
    controls, sections, refreshers = {}, {}, {}
    menu.CLASSIC_AURA_FILTERS_REDUCED = true
    menu.BuildAuras3GroupLaneWorkspace({ key = "gf_auras" }, builder, "raid", lane,
        { compact = true, tool = "filters" })
    assert(#sections == 1 and sections[1].height == 118,
        "Classic group filters no longer match the compact UnitFrame height")
    assert(#controls == 2,
        "Classic group filters must expose only Only mine and Hide permanent")
    local byLabel = {}
    for i = 1, #controls do byLabel[controls[i].label] = controls[i] end
    local onlyMine = assert(byLabel["Only mine"], "Classic group Only mine switch missing")
    local hidePermanent = assert(byLabel["Hide permanent"], "Classic group Hide permanent switch missing")
    assert(byLabel.All == nil and byLabel["All Buffs"] == nil and byLabel["All Debuffs"] == nil,
        "Classic group filters retained the mutually exclusive Retail choice list")
    assert(onlyMine.x == 24 and onlyMine.y == -42
        and hidePermanent.x == 24 + onlyMine.width + 12 and hidePermanent.y == -42
        and hidePermanent.width == onlyMine.width,
        "Classic group filter controls do not match the UnitFrame two-column layout")
    assert(onlyMine.enabled == true and hidePermanent.enabled == true,
        "Classic group filter refresh did not keep both switches enabled")
    return onlyMine, hidePermanent
end

for _, lane in ipairs({ "buff", "debuff" }) do
    local onlyMine, hidePermanent = BuildClassicLane(lane)
    assert(onlyMine.getValue() == false, lane .. " Only mine did not default to ALL")
    onlyMine.setValue(true)
    assert(AuraGroup("raid", lane).filterToken == "Player"
        and AuraGroup("mythicraid", lane).filterToken == "Player",
        lane .. " Only mine did not fan out Player to Raid and Mythic Raid")
    assert(onlyMine.getValue() == true, lane .. " Only mine did not read back Player")
    onlyMine.setValue(false)
    assert(AuraGroup("raid", lane).filterToken == "ALL"
        and AuraGroup("mythicraid", lane).filterToken == "ALL",
        lane .. " Only mine did not fan out ALL to Raid and Mythic Raid")

    assert(hidePermanent.getValue() == false, lane .. " Hide permanent did not default off")
    hidePermanent.setValue(true)
    assert(AuraGroup("raid", lane).blacklist.hidePermanent == true
        and AuraGroup("mythicraid", lane).blacklist.hidePermanent == true,
        lane .. " Hide permanent did not fan out to Raid and Mythic Raid")
    assert(hidePermanent.getValue() == true, lane .. " Hide permanent did not read back")
end

assert(#queued == 12 and previews == 6,
    "Classic group filter changes did not use the existing coalesced Raid/Mythic apply path")
for i = 1, #queued do
    assert(queued[i].mode == "auras",
        "Classic group filter change did not request the focused Aura dirty path")
end

-- The same shared file is also loaded by this repository's Mainline TOC. Force
-- its missing-data fallback so the former nil VT call remains covered too.
controls, sections, refreshers = {}, {}, {}
menu.CLASSIC_AURA_FILTERS_REDUCED = false
namespace.GF = nil
MSUF_GF_AuraFilter = nil
menu.BuildAuras3GroupLaneWorkspace({ key = "gf_auras" }, builder, "raid", "buff",
    { compact = true, tool = "filters" })
local fallback = {}
for i = 1, #controls do fallback[controls[i].label] = true end
assert(fallback["All Buffs"] == true and fallback["Cast by Me"] == true,
    "Mainline group filter fallback did not build through M.ValueTextList")

print("classic Aura menu filter smoke passed")
