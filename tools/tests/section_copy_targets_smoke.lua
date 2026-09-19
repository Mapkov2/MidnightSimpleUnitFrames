-- section_copy_targets_smoke.lua
-- The ::: section actions popup on the Unit and Group pages copies one section
-- to another frame. It may offer only frames the running client can show, and a
-- frame that is turned off stays listed but tinted, marked and unselectable.
-- It proves:
--   Popup: MSUF_Menu2_UnitSectionShared.lua AttachSectionUX with opts.targetOff
--          lists an off target as a disabled "<label> - Frame disabled" row in
--          the theme danger colour, defaults the destination to the first
--          target that is on, refuses a copy to an off target, and locks Copy
--          when every target is off. Without targetOff the rows are unchanged.
--   Unit:  on Midnight, WoW Forever, Vanilla, TBC and Mists the Unit page hands
--          the popup exactly the frames of its unit tabs (Forever: no Arena;
--          Vanilla: no Focus, Focus Target, Boss or Arena; TBC: no Boss) and
--          marks a frame off by the page's own enabled gate (Focus Target is
--          off while Focus is off).
--   Group: the Group page marks a scope off while its MSUF frames are disabled.
-- Run with plain Lua 5.1 and the repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing file: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- Source text from the first marker up to, not including, the second one.
local function Slice(source, first, stop, label)
    local start = assert(source:find(first, 1, true), label .. ": missing " .. first)
    local finish = assert(source:find(stop, start + #first, true), label .. ": missing " .. stop)
    return source:sub(start, finish - 1)
end

local OPTIONS = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local noop = function() end

-- Popup ----------------------------------------------------------------------
-- Frame doubles record scripts, text and visibility; every other widget method
-- is a no-op.
local frameMethods = {}
function frameMethods:SetScript(name, fn) self.scripts[name] = fn end
function frameMethods:HookScript(name, fn) self.scripts[name] = self.scripts[name] or fn end
function frameMethods:Show() self.shown = true end
function frameMethods:Hide() self.shown = false end
function frameMethods:IsShown() return self.shown end
function frameMethods:SetShown(shown) self.shown = shown and true or false end
function frameMethods:SetText(text) self.text = text end
function frameMethods:GetText() return self.text end
function frameMethods:GetFrameLevel() return 1 end
local frameMeta = { __index = function(_, key) return frameMethods[key] or noop end }
local function NewFrame(text, shown)
    return setmetatable({ scripts = {}, text = text, shown = shown ~= false }, frameMeta)
end

local dropdowns, buttons = {}, {}
local W = {
    TopButton = function(_, text)
        local button = NewFrame(text)
        buttons[#buttons + 1] = button
        return button
    end,
    Dropdown = function(_, label, values)
        local dropdown = NewFrame(label)
        dropdown.values = values
        function dropdown:SetValues(nextValues) self.values = nextValues end
        function dropdown:SetValue(value) self.value = value end
        function dropdown:SetOnValueChanged(fn) self.onValueChanged = fn end
        dropdowns[#dropdowns + 1] = dropdown
        return dropdown
    end,
    MoveWidget = noop,
    SetControlEnabled = function(control, enabled) control.enabled = enabled and true or false end,
}
local T = {
    Font = function(_, _, text) return NewFrame(text) end,
    colors = {
        text = { 1, 1, 1, 1 }, muted = { 0.7, 0.7, 0.7, 1 }, danger = { 0.878, 0.322, 0.369, 1 },
        coreShadow = { 0, 0, 0, 1 }, borderSoft = { 0, 0, 0, 1 }, coreSurface = { 0, 0, 0, 1 }, coreBlue = { 0, 0, 1, 1 },
    },
}
local M = {
    Widgets = W, Theme = T,
    Tr = function(text) return text end,
    TrackRefresh = noop,
    BlockCombatAction = function() return false end,
    RunWithHistory = function(_, _, fn) return fn() end,
    ShowStatusFeedback = noop,
    Refresh = noop,
    DeepCopy = function(value) return value end,
    CreateMenuPopupPanel = function() return NewFrame(nil, false) end,
    ApplyPopupFramePriority = noop,
}
_G.UIParent = NewFrame()
assert(loadstring(Read(OPTIONS .. "MSUF_Menu2_UnitSectionShared.lua"), "@MSUF_Menu2_UnitSectionShared.lua"))(
    "MidnightSimpleUnitFrames_Options", { MSUF2 = M })
local Shared = M.UnitSectionsShared
Check(type(Shared) == "table" and type(Shared.AttachSectionUX) == "function", "AttachSectionUX missing")

-- One Resource Bar section on the Focus Target page, as the Unit page wires it.
local function AttachSection(targetOff)
    local entry = { header = NewFrame(), outer = NewFrame(), label = NewFrame("Resource Bar") }
    local section = { copies = {} }
    Shared.AttachSectionUX({ key = "uf_focustarget", entry = { sections = { power_bar = { _msuf2CollapsibleEntry = entry } } } }, {
        sections = { power_bar = { fields = "powerBarHeight", copy = "power" } },
        targets = {
            { value = "player", text = "Player" }, { value = "target", text = "Target" },
            { value = "pet", text = "Pet" }, { value = "focustarget", text = "Focus Target" },
        },
        scope = function() return "focustarget" end,
        conf = function() return {} end,
        label = function(scope) return scope end,
        defaults = function() return {} end,
        copy = function(source, target, category)
            section.copies[#section.copies + 1] = source .. ">" .. target .. ":" .. category
            return true
        end,
        apply = noop,
        targetOff = targetOff,
    })
    section.more = entry._msuf2SectionActions
    Check(section.more and section.more.scripts.OnClick, "the section has no ::: button")
    return section
end

-- Opens the popup (closing it first when it is up) and returns it. The first
-- open builds the popup, so its dropdown and Copy button are the newest ones.
local function Open(section)
    local popup = section.more._msuf2GetSectionPopup()
    if popup and popup:IsShown() then section.more.scripts.OnClick(section.more) end
    section.more.scripts.OnClick(section.more)
    popup = section.more._msuf2GetSectionPopup()
    Check(popup and popup:IsShown(), "the ::: popup did not open")
    if not section.select then
        section.select = dropdowns[#dropdowns]
        for i = #buttons, 1, -1 do
            if buttons[i].text == "Copy section" then section.copy = buttons[i]; break end
        end
        Check(section.select and section.copy, "the popup has no destination dropdown or Copy button")
    end
    return popup
end

local OFF_PET = "|cffe0525ePet - Frame disabled|r"
local off = { pet = true }
local section = AttachSection(function(value) return off[value] == true end)
local popup = Open(section)
local rows = section.select.values
Check(#rows == 3, "the popup should list Player, Target and Pet without its own frame, got " .. #rows)
Check(rows[1].value == "player" and not rows[1].disabled and rows[1].text == "Player", "Player must stay a normal row")
Check(rows[3].value == "pet" and rows[3].disabled == true and rows[3].translate == false,
    "an off frame must be a disabled, already translated row")
Check(rows[3].text == OFF_PET, "off row text: " .. tostring(rows[3].text))
Check(section.select.value == "player", "the destination must default to the first frame that is on")
Check(section.copy.enabled == true, "Copy must be enabled while a frame is on")
Check(popup._msuf2CopySection("pet") == false and #section.copies == 0, "a copy to an off frame must be refused")
Check(popup._msuf2CopySection("player") == true and section.copies[1] == "focustarget>player:power",
    "a copy to a frame that is on must still run")

-- Picking a destination in the dropdown and pressing Copy.
Open(section)
section.select.onValueChanged("target")
section.copy.scripts.OnClick(section.copy)
Check(section.copies[2] == "focustarget>target:power", "the Copy button must copy to the picked frame")

-- Every frame off: the first one stays visible, marked, and Copy locks.
off.player, off.target = true, true
popup = Open(section)
rows = section.select.values
Check(#rows == 3 and rows[1].disabled and rows[2].disabled and rows[3].disabled, "every off frame must be a disabled row")
Check(section.select.value == "player", "with every frame off the first one must stay shown")
Check(section.copy.enabled == false, "Copy must lock while every frame is off")
Check(popup._msuf2CopySection("target") == false and #section.copies == 2, "no copy may run while every frame is off")

-- Turning a frame back on makes it the destination again.
off.target = nil
Open(section)
Check(section.select.value == "target" and section.copy.enabled == true, "a frame turned back on must be selectable again")

-- A page without targetOff keeps its own rows untouched.
local plain = AttachSection(nil)
Open(plain)
Check(#plain.select.values == 3 and plain.select.values[3].text == "Pet" and not plain.select.values[3].disabled,
    "without targetOff the popup must keep the page's rows")
Check(plain.select.value == "player" and plain.copy.enabled == true, "without targetOff the first row stays the destination")

-- Unit -----------------------------------------------------------------------
local sections = Read(OPTIONS .. "MSUF_Menu2_UnitSections.lua")
local tabOrder = assert(sections:match("\nlocal UNIT_TAB_ORDER = (%b{})"), "UNIT_TAB_ORDER missing")
local unitSource = table.concat({
    "local MSUF, M, UP, UnitSectionShared, UNIT_PAGE_FOR_UNIT, UnitTopLabel, UnitTopTabLabel, UnitTopTabWidth, GetConf, ReadBool = ...",
    "local UNIT_TAB_ORDER = " .. tabOrder,
    Slice(sections, "local function UnitFrameEnabled(", "local function ApplyUnitFrameEnabledGate(", "UnitSections"),
    Slice(sections, "local function SectionNumber(", "local function BuildTopActions(", "UnitSections"),
    Slice(sections, "local function BuildTopActions(", "    local scopeOpts =", "UnitSections") .. "    return scopeValues\nend",
    "return AttachUnitSectionUX, BuildTopActions",
}, "\n")

local CLIENTS = {
    { name = "Midnight", project = 1, pages = "MSUF_Menu2_Unit.lua", absent = {} },
    { name = "Forever", project = 1, forever = true, pages = "MSUF_Menu2_Unit.lua", absent = { arena = true } },
    { name = "Vanilla", project = 2, tag = "Vanilla", pages = "MSUF_Menu2_Unit_Classic.lua",
        absent = { focus = true, focustarget = true, boss = true, arena = true } },
    { name = "TBC", project = 5, tag = "TBC", pages = "MSUF_Menu2_Unit_Classic.lua", absent = { boss = true } },
    { name = "Mists", project = 19, tag = "Mists", pages = "MSUF_Menu2_Unit_Classic.lua", absent = {} },
}
local ALL_UNITS = { "player", "target", "boss", "arena", "focus", "pet", "targettarget", "focustarget" }
local db = { pet = { enabled = false }, focus = { enabled = false } }
local function ReadBool(unit, key, default)
    local value = (db[unit] or {})[key]
    if value == nil then return default and true or false end
    return value and true or false
end
for _, client in ipairs(CLIENTS) do
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
    _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
    _G.WOW_PROJECT_ID = client.project
    _G.MAX_ARENA_ENEMIES = nil
    _G.GameEvent = client.forever and { RegisterCamelotEvents = noop } or nil
    _G.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "X-MSUF-Client" then return client.tag end end }
    _G.MSUF, _G.MSUF_NS, _G.MSUF2 = nil, nil, nil
    local ns = {}
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", ns)
    Check(ns.Client.IsForever == (client.forever == true), client.name .. ": client detection")
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/MSUF_OptionsLOD_Bootstrap.lua"))("MidnightSimpleUnitFrames_Options", {})
    local menu = ns.MSUF2
    local pageSource = Read(OPTIONS .. client.pages)
    pageSource = pageSource:sub(1, assert(pageSource:find("local POWER_UNITS", 1, true), client.pages) - 1) .. "\nreturn UNIT_PAGES"
    local pages = assert(loadstring(pageSource, "@" .. client.pages))("MidnightSimpleUnitFrames_Options", ns)
    local pageForUnit = {}
    for key, page in pairs(pages) do pageForUnit[page.unit] = key end

    local captured
    local attach, tabs = assert(loadstring(unitSource, "@MSUF_Menu2_UnitSections.lua"))(ns, menu, {},
        { AttachSectionUX = function(_, opts) captured = opts end }, pageForUnit,
        function(unit) return unit end, function(unit) return unit end, function() return 50 end,
        function(unit) return db[unit] or {} end, ReadBool)
    attach({}, "player")
    Check(captured and captured.targets and captured.targetOff, client.name .. ": the Unit page did not wire the ::: popup")
    local visible = tabs({}, { width = 720 }, "player", "Player")
    Check(#captured.targets == #visible, client.name .. ": " .. #captured.targets .. " ::: targets but " .. #visible .. " unit tabs")
    local listed = {}
    for i, row in ipairs(visible) do
        local target = captured.targets[i].value
        Check(target == row.value, client.name .. ": ::: target " .. i .. " is " .. tostring(target) .. ", the unit tab is " .. tostring(row.value))
        listed[target] = true
    end
    for _, unit in ipairs(ALL_UNITS) do
        Check((listed[unit] == true) == (client.absent[unit] ~= true),
            client.name .. ": ::: target " .. unit .. (client.absent[unit] and " must not be offered" or " is missing"))
    end
    Check(captured.targetOff("pet") == true and captured.targetOff("focus") == true, client.name .. ": a disabled frame must be marked off")
    Check(captured.targetOff("focustarget") == true, client.name .. ": Focus Target must be off while Focus is off")
    Check(captured.targetOff("player") == false and captured.targetOff("target") == false and captured.targetOff("targettarget") == false,
        client.name .. ": enabled frames must stay on")
end

-- Group ----------------------------------------------------------------------
local group = Read(OPTIONS .. "MSUF_Menu2_Group.lua")
local groupSource = "local MSUF, M, Shared, SCOPE_VALUES, ScopeShortLabel, CurrentScope, Conf, Bool, GF, QueueGF, RefreshGFPreview, floor = ...\n"
    .. Slice(group, "local function AttachGroupSectionUX(", "local function FinalizeScopePage(", "Group")
    .. "\nreturn AttachGroupSectionUX"
local groupEnabled = { party = true, raid = false }
local captured
local attachGroup = assert(loadstring(groupSource, "@MSUF_Menu2_Group.lua"))({}, { Tr = function(text) return text end },
    { AttachSectionUX = function(_, opts) captured = opts end },
    { { value = "party" }, { value = "raid" } },
    function(kind) return kind end, function() return "party" end, function() return {} end,
    function(kind, key, default)
        local value = key == "enabled" and groupEnabled[kind] or nil
        if value == nil then return default and true or false end
        return value and true or false
    end,
    function() return nil end, noop, noop, math.floor)
attachGroup({})
Check(captured and captured.targetOff, "Group: the ::: popup gets no targetOff")
Check(#captured.targets == 2 and captured.targets[1].value == "party" and captured.targets[2].value == "raid",
    "Group: the ::: targets must be the page's scopes")
Check(captured.targetOff("raid") == true and captured.targetOff("party") == false, "Group: targetOff must follow the scope's enabled switch")
groupEnabled.raid = nil
Check(captured.targetOff("raid") == true, "Group: a scope without an enabled value is off, as its page shows it")

print("section_copy_targets_smoke: ok (popup, " .. #CLIENTS .. " clients, group)")
