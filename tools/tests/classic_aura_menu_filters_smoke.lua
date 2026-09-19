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
    -- The shared nested builder returns the parent builder when the body is not
    -- a collapsible entry, which none of these stub sections are.
    CreateNestedAuraBuilder = function(_, parentBuilder) return parentBuilder end,
}

local menu
menu = {
    Widgets = widgets,
    Theme = { colors = { muted = { 1, 1, 1, 1 } } },
    -- An empty profile: no dispel overlay, symbol or outline is requested.
    EnsureDB = function() return {} end,
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
    BindSliderAt = function(_, _, label, x, y, minimum, maximum, step, width, getValue, setValue, meta)
        local control = {
            label = label,
            x = x,
            y = y,
            minimum = minimum,
            maximum = maximum,
            step = step,
            width = width,
            getValue = getValue,
            setValue = setValue,
            meta = meta,
        }
        controls[#controls + 1] = control
        return control
    end,
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

-- Classic loads the Retail aura page and its Group sibling; their Classic
-- differences are gated on M.CLASSIC_AURA_FILTERS_REDUCED inside them.
local pagesPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
for _, page in ipairs({ "MSUF_Menu2_Auras.lua", "MSUF_Menu2_Auras_Group.lua" }) do
    local pageFile = assert(io.open(pagesPath .. page, "rb"))
    local pageSource = pageFile:read("*a")
    pageFile:close()
    assert(not pageSource:match("%f[%w]VT%s*%(") or pageSource:match("\nlocal VT[%s,]"),
        page .. " retains an unresolved global VT call")
end

for _, helper in ipairs({ "AuraSettings", "AuraControls" }) do
    assert(loadfile(pagesPath .. "MSUF_Menu2_" .. helper .. ".lua"))(
        "MidnightSimpleUnitFrames", namespace)
end
assert(loadfile(pagesPath .. "MSUF_Menu2_Auras.lua"))("MidnightSimpleUnitFrames", namespace)
assert(menu.CLASSIC_AURA_FILTERS_REDUCED == true,
    "the aura page did not read the Classic client fact")
assert(loadfile(pagesPath .. "MSUF_Menu2_Auras_Group.lua"))("MidnightSimpleUnitFrames", namespace)
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

-- Unit workspace filters. Only mine and Non-player auras are mutually exclusive
-- and Classic has no Non-player control, so enabling Debuff Only mine must clear
-- a nonPlayer flag imported from Retail. Buff lanes and turning Only mine off
-- must leave nonPlayer untouched. Turning Only mine on enables the filters of
-- that one lane, the per-lane switch the Classic compile reads.
local unitFilters, unitApplies
function model.UnitSupported(unit) return unit == "target" end
function model.UnitEnabled() return true end
function model.LaneFiltersEnabled(_, lane)
    return unitFilters[lane == "buff" and "buffs" or "debuffs"].enabled ~= false
end
function model.SetLaneFiltersEnabled(_, lane, enabled)
    unitFilters[lane == "buff" and "buffs" or "debuffs"].enabled = enabled == true
end
function model.ReadFilter(_, lane, key, defaultValue)
    local value = unitFilters[lane == "buff" and "buffs" or "debuffs"][key]
    if value == nil then return defaultValue end
    return value
end
function model.WriteFilter(_, lane, key, value)
    unitFilters[lane == "buff" and "buffs" or "debuffs"][key] = value
end
function model.Apply() unitApplies = unitApplies + 1 end

local function StubObject()
    local noop = function() end
    return { Hide = noop, SetPoint = noop, SetScript = noop, SetText = noop }
end
widgets.Text = StubObject
widgets.RoleButton = StubObject
widgets.ScopeOverrideBar = function() return {} end

local unitBuilder = { width = 720 }
function unitBuilder:Section(title, height)
    local section = { sectionTitle = title, height = height, _msuf2Width = self.width }
    sections[#sections + 1] = section
    return section
end
function unitBuilder:CollapsibleSection(_, title, height)
    return { sectionTitle = title, height = height }
end

assert(type(menu.BuildAuras3UnitSection) == "function",
    "Classic unit Aura workspace builder was not exported")

for _, lane in ipairs({ "debuff", "buff" }) do
    local otherLane = lane == "buff" and "debuffs" or "buffs"
    local laneKey = lane == "buff" and "buffs" or "debuffs"
    unitFilters = {
        buffs = { enabled = false, nonPlayer = true },
        debuffs = { enabled = false, nonPlayer = true },
    }
    unitApplies = 0
    controls, sections, refreshers = {}, {}, {}
    menu.unitAuraTabSelection = { target = lane }
    menu.unitAuraToolSelection = { target = { [lane] = "filters" } }
    menu.BuildAuras3UnitSection({ key = "uf_target" }, unitBuilder, "target")

    local filterSection = sections[#sections]
    assert(filterSection and filterSection.sectionTitle == (lane == "buff" and "Buff" or "Debuff") .. " Filters"
        and filterSection.height == 118,
        lane .. " unit workspace did not build the compact Filters section")
    assert(#controls == 2, lane .. " unit filters must expose only Only mine and Hide permanent")
    local byLabel = {}
    for i = 1, #controls do byLabel[controls[i].label] = controls[i] end
    local onlyMine = assert(byLabel["Only mine"], lane .. " unit Only mine switch missing")
    assert(byLabel["Hide permanent"], lane .. " unit Hide permanent switch missing")

    assert(onlyMine.getValue() == false, lane .. " unit Only mine did not default off")
    onlyMine.setValue(true)
    assert(unitFilters[laneKey].enabled == true, lane .. " unit Only mine did not enable the lane filters")
    assert(unitFilters[otherLane].enabled == false, lane .. " unit Only mine enabled the other lane's filters")
    assert(unitFilters[laneKey].onlyMine == true and onlyMine.getValue() == true,
        lane .. " unit Only mine did not write and read back onlyMine")
    if lane == "debuff" then
        assert(unitFilters.debuffs.nonPlayer == false,
            "unit Debuff Only mine did not clear the mutually exclusive nonPlayer filter")
    else
        assert(unitFilters.buffs.nonPlayer == true,
            "unit Buff Only mine must leave the nonPlayer filter untouched")
    end
    assert(unitFilters[otherLane].nonPlayer == true,
        lane .. " unit Only mine changed the other lane's nonPlayer filter")

    unitFilters[laneKey].nonPlayer = true
    onlyMine.setValue(false)
    assert(unitFilters[laneKey].onlyMine == false and onlyMine.getValue() == false,
        lane .. " unit Only mine did not turn off")
    assert(unitFilters[laneKey].nonPlayer == true,
        lane .. " turning unit Only mine off must leave the nonPlayer filter untouched")
    assert(unitApplies == 2, lane .. " unit Only mine did not request the Aura runtime apply")
end

print("classic Aura menu filter smoke passed")
