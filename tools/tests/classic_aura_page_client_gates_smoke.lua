-- classic_aura_page_client_gates_smoke.lua <repoRoot> <flavor>
--
-- Every client loads the Retail aura page (Pages/MSUF_Menu2_Auras.lua) and its
-- Group and Preview siblings. The Classic aura backends differ from the native
-- 12.1 containers in a few places, and those places are gated inside the pages on
-- M.CLASSIC_AURA_FILTERS_REDUCED (the page's MSUF.Client.IsClassic answer):
--
--   * no lane Full-Frame Effect section (no Classic runtime renders one),
--   * no "Native stealable marker" tooltip (Classic marks stealable buffs from
--     its own scan),
--   * a rectangular debuff preview keeps the atlas dispel border (the Classic
--     A3.ApplyAuraDispelPreview draws nothing for a rectangle),
--   * group blacklist writes re-apply only the Auras element,
--   * a Non-player group filter token is not read as Only mine,
--   * the group filters are Only mine and Hide permanent, with Classic tooltips
--     and the group filterToken / hidePermanent assistant keys,
--   * the group blacklist Preset opens on the lane default (SATED or RAID_BUFFS)
--     while the picked preset is not in that lane's list.
--
-- Midnight and WoW Forever keep the Retail behaviour on every one of them. The
-- Blizzard Buff & Debuff Frames section is built on every client.
--
-- Plain Lua 5.1 with the repo root as arg 1 and a client flavor as arg 2 (a
-- matrix Suffix or Forever). The widgets, theme and Menu Model are recording
-- stubs; the aura page files and the blacklist preset catalogue
-- (MSUF_Auras3_Menu_Presets.lua) are the shipped ones.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local CLASSIC = { Vanilla = true, TBC = true, Mists = true }
local MAINLINE = { Mainline = true, Forever = true }
assert(CLASSIC[flavor] or MAINLINE[flavor], "unknown flavor " .. tostring(flavor))
local IS_CLASSIC = CLASSIC[flavor] == true

local events = {}
local function Emit(text) events[#events + 1] = text end

-- Recording widgets: every capitalized method is accepted and logged.
local Name = setmetatable({}, { __mode = "k" })
local ObjMT = {}
local counter = 0
local function NewObj(kind, hint)
    counter = counter + 1
    local obj = { _shown = true }
    Name[obj] = kind .. "[" .. tostring(hint or "") .. "]#" .. counter
    return setmetatable(obj, ObjMT)
end
local Methods = {}
function Methods:CreateTexture() return NewObj("Tex") end
function Methods:CreateFontString() return NewObj("FS") end
function Methods:CreateMaskTexture() return NewObj("Mask") end
function Methods:CreateAnimationGroup() return NewObj("Anim") end
function Methods:CreateAnimation() return NewObj("AnimPart") end
function Methods:GetWidth() return 200 end
function Methods:GetHeight() return 200 end
function Methods:GetText() return "" end
function Methods:IsShown() return rawget(self, "_shown") ~= false end
function Methods:IsVisible() return rawget(self, "_shown") ~= false end
function Methods:Show() rawset(self, "_shown", true); Emit("Show " .. Name[self]) end
function Methods:Hide() rawset(self, "_shown", false) end
function Methods:SetShown(shown) rawset(self, "_shown", shown and true or false) end
function Methods:SetAtlas(atlas) Emit("SetAtlas " .. Name[self] .. " " .. tostring(atlas)) end
local clickable = {}
function Methods:SetScript(event, fn)
    local scripts = rawget(self, "_scripts") or {}
    rawset(self, "_scripts", scripts)
    scripts[event] = fn
    if event == "OnClick" and fn then clickable[#clickable + 1] = self end
end
function Methods:GetScript(event) local scripts = rawget(self, "_scripts"); return scripts and scripts[event] end
function Methods:GetNumPoints() return 0 end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", 10, "" end
function Methods:GetStringWidth() return 50 end
function Methods:GetStringHeight() return 12 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetFrameLevel() return 1 end
function Methods:GetLeft() return 0 end
function Methods:GetTop() return 200 end
function Methods:GetCenter() return 100, 100 end
function Methods:IsForbidden() return false end
function Methods:IsProtected() return false end
function Methods:GetParent() return rawget(self, "_parent") end
local function Noop() end
ObjMT.__index = function(_, key)
    if type(key) ~= "string" then return nil end
    if Methods[key] then return Methods[key] end
    if key:match("^[A-Z]") then return Noop end
    return nil
end

_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.UIParent = NewObj("UIParent")
_G.CreateFrame = function(kind, _, parent)
    local obj = NewObj("CF:" .. tostring(kind))
    rawset(obj, "_parent", parent)
    return obj
end
_G.C_Timer = { After = function(_, fn) fn() end, NewTimer = function(_, fn) fn(); return { Cancel = Noop } end }
_G.InCombatLockdown = function() return false end
_G.IsShiftKeyDown = function() return false end
_G.TextureKitConstants = { IgnoreAtlasSize = true }
_G.MSUF_GetGlobalFontSettings = function() return "Fonts\\FRIZQT__.TTF", "OUTLINE", 1, 1, 1, nil, true end
_G.MSUF_ResolveSafeFontPath = function(path) return path end
_G.MSUF_SetFontChecked = function() return true end
_G.MSUF_UF_OutlineModeEnabled = function(value, fallback)
    if value == nil then value = fallback end
    if value == true or value == false then return value end
    return tonumber(value) == 1
end

-- Profile data: one debuff Non-player group token, the rest defaults.
local function Group()
    return { auras = { renderer = "CUSTOM", blizzardTypes = {}, buff = {}, debuff = { filterToken = "NonPlayer" } } }
end
local DB = { general = {}, gf_party = Group(), gf_raid = Group(), gf_mythicraid = Group(),
    auras3 = { shared = {}, perUnit = {} } }
_G.MSUF_DB = DB

-- Menu Model: records every call; reads answer with their default argument.
local iconShape = "RECTANGLE"
local modelCalls = {}
local Model = setmetatable({}, {
    __index = function(t, key)
        local f = function(...)
            modelCalls[#modelCalls + 1] = key
            local n = select("#", ...)
            local last = n > 0 and select(n, ...) or nil
            if key == "EnsureDB" then return DB.auras3, DB.auras3.shared end
            if key == "ReadDebuffTypeBorderMode" then return "BORDER" end
            if key == "ReadSharedAppearanceIconShape" then return iconShape end
            if key:match("Values$") then return { { value = "V1", text = "V1" } } end
            if key:match("Entries$") then return {} end
            if key:match("^Add") and key:match("Group$") then return 1 end
            if key:match("^Write") or key:match("^Set") or key:match("^Add") or key:match("^Remove") then return true end
            if key:match("Enabled$") or key:match("Supported$") then return true end
            if key:match("^Read") and type(last) ~= "string" then return last end
            return nil
        end
        rawset(t, key, f)
        return f
    end,
})
local dispelPreviewShapes = {}
local A3 = {
    MenuModel = Model,
    ApplyIconStylePreview = Noop,
    ApplyAuraIconShape = function(_, shape) return shape or "RECTANGLE" end,
    PreviewDispelTypeForIndex = function() return "Magic" end,
    GetDurationBarColor = function() return 1, 1, 1 end,
}
if IS_CLASSIC then
    -- Game/Classic/Auras/MSUF_Auras3_Visuals.lua: shaped borders only.
    A3.ApplyAuraDispelPreview = function(border, _, _, mode, shape)
        dispelPreviewShapes[#dispelPreviewShapes + 1] = shape
        if mode == nil or mode == "OFF" or (shape or "RECTANGLE") == "RECTANGLE" then return false end
        border:Show()
        return true
    end
else
    A3.ApplyAuraDispelPreview = function(border, _, _, _, shape)
        dispelPreviewShapes[#dispelPreviewShapes + 1] = shape
        border:Show()
        return true
    end
    A3.NativeAuraDispelBorderPadding = function(size) return size end
    A3.ApplyPandemicVisual = Noop
end

-- Menu2 namespace.
local sections, tooltips, switches, queued = {}, {}, {}, {}
local tooltipBodies, dropdowns = {}, {}
local function ValueTextList(...)
    local values = {}
    for i = 1, select("#", ...), 2 do values[#values + 1] = { value = select(i, ...), text = select(i + 1, ...) } end
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
local function Bind(kind)
    return function(_, _, label, ...)
        local control = NewObj(kind, label)
        local get, set, meta
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "function" then if not get then get = v elseif not set then set = v end end
            if type(v) == "table" then meta = v end
        end
        if kind == "Switch" then switches[label] = { control = control, get = get, set = set, meta = meta } end
        return control
    end
end
local function Builder()
    local b = NewObj("Builder")
    rawset(b, "width", 720)
    rawset(b, "y", -20)
    rawset(b, "Section", function(_, title) sections[#sections + 1] = title; return NewObj("Section", title) end)
    rawset(b, "CollapsibleSection", function(_, id, title) sections[#sections + 1] = title; return NewObj("Collapsible", id) end)
    return b
end
local W = setmetatable({}, { __index = function(t, key)
    if type(key) ~= "string" or not key:match("^[A-Z]") then return nil end
    local f = key:match("^Measure") and function() return nil end or function(_, label)
        local obj = NewObj("W." .. key, type(label) == "string" and label or nil)
        return obj
    end
    rawset(t, key, f)
    return f
end })
W.PageBuilder = function() return Builder() end
W.Dropdown = function(_, label, values)
    local obj = NewObj("W.Dropdown", label)
    rawset(obj, "_label", label)
    rawset(obj, "_values", values)
    return obj
end
W.CreateNestedAuraBuilder = function(_, parentBuilder) return parentBuilder end
W.ToggleBadge = function(label, enabled) return { text = label .. (enabled and " On" or " Off") } end
W.SettingsRows = function() return { list = {}, resets = {}, controls = {} } end
W.FixedPreviewSection = function() return NewObj("FixedPreview"), nil, nil end
local T = setmetatable({ colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) }, {
    __index = function(t, key)
        if type(key) ~= "string" or not key:match("^[A-Z]") then return nil end
        local creates = key == "Panel" or key == "Font" or key == "Button"
        local f = function() if creates then return NewObj("T." .. key) end return nil end
        rawset(t, key, f)
        return f
    end,
})
T.FontSize = function() return 10 end
T.Space = function(_, fallback) return fallback or 8 end

local M
M = setmetatable({
    Widgets = W, Theme = T,
    ValueTextList = ValueTextList, ValueTextPairs = ValueTextPairs,
    KeySetFromWords = function(words)
        local set = {}
        for word in tostring(words or ""):gmatch("%S+") do set[word] = true end
        return set
    end,
    Format = string.format, Tr = function(text) return text end,
    Assign = function(target, values) for k, v in pairs(values) do target[k] = v end return target end,
    AppendValues = function(list, ...) for i = 1, select("#", ...) do list[#list + 1] = (select(i, ...)) end return list end,
    AccessibleNumber = function(value, fallback) return tonumber(value) or tonumber(fallback) or 0 end,
    EnsureDB = function() return DB end,
    BindSwitchAt = Bind("Switch"), BindToggleAt = Bind("Toggle"), BindSliderAt = Bind("Slider"),
    BindDropdownAt = Bind("Dropdown"), BindTextInputAt = Bind("TextInput"),
    BindColor = function(_, widget) return widget end,
    BindDropdownWidget = function(_, widget, get)
        local label = type(widget) == "table" and rawget(widget, "_label")
        if label then dropdowns[label] = { get = get, values = rawget(widget, "_values") } end
        return widget
    end,
    TrackRefresh = function(_, fn) fn() end,
    RegisterPage = function(key, spec) M.pages = M.pages or {}; M.pages[key] = spec end,
    SetMenuStateValue = function(key, value) M[key] = value end,
    AddTooltip = function(_, title, body) tooltips[#tooltips + 1] = title; tooltipBodies[title] = body end,
    GroupAuraSettingKeys = function(scope, suffix)
        if scope == "party" then return { "gf_party" .. suffix } end
        return { "gf_raid" .. suffix, "gf_mythicraid" .. suffix }
    end,
    AuraCatalogToken = function(value, fallback)
        local token = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
        return token ~= "" and token or (fallback or "control")
    end,
    BlockCombatAction = function() return false end,
    MenuTimer = _G.C_Timer,
    GroupPage = {
        Conf = function(kind)
            local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
            return DB[key]
        end,
        QueueGF = function(kind, mode) queued[#queued + 1] = tostring(kind) .. ":" .. tostring(mode) end,
        RefreshGFPreview = Noop,
    },
}, { __index = function(t, key)
    if type(key) ~= "string" or not key:match("^[A-Z]") then return nil end
    rawset(t, key, Noop)
    return Noop
end })
M.PreviewHelpers = setmetatable({}, { __index = function() return nil end })
M.ApplyService = setmetatable({}, { __index = function() return Noop end })

local Client = {
    Family = IS_CLASSIC and "Classic" or "Mainline",
    Flavor = IS_CLASSIC and flavor or "Mainline",
    IsClassic = IS_CLASSIC, IsRetail = not IS_CLASSIC, IsForever = flavor == "Forever",
    IsVanilla = flavor == "Vanilla", IsTBC = flavor == "TBC", IsMists = flavor == "Mists",
}
local MSUF = { MSUF2 = M, MSUF_Auras3 = A3, Client = Client, AddonName = "MidnightSimpleUnitFrames" }
local pages = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
for _, file in ipairs({ "MSUF_Menu2_AuraSettings.lua", "MSUF_Menu2_AuraControls.lua", "MSUF_Menu2_Auras.lua",
    "MSUF_Menu2_Auras_Group.lua", "MSUF_Menu2_Auras_Preview.lua" }) do
    assert(loadfile(pages .. file))("MidnightSimpleUnitFrames", MSUF)
end
assert(M.CLASSIC_AURA_FILTERS_REDUCED == IS_CLASSIC,
    flavor .. ": the aura page did not derive its Classic gate from MSUF.Client.IsClassic")
assert(type(M.AurasPage) == "table" and type(M.AurasPage.BuildAuraStylePreviewWorkbench) == "function"
    and type(M.AuraGroupSettings) == "table", flavor .. ": the Group and Preview siblings did not attach to the page")

local function Has(list, value)
    for i = 1, #list do if list[i] == value then return true end end
    return false
end
local function Reset()
    sections, tooltips, switches, queued, events, dispelPreviewShapes = {}, {}, {}, {}, {}, {}
    tooltipBodies, dropdowns = {}, {}
    clickable = {}
end
local function BuildUnit(unit, tab, tool)
    Reset()
    M.unitAuraTabSelection = { [unit] = tab }
    M.unitAuraToolSelection = { [unit] = { [tab] = tool } }
    M.BuildAuras3UnitSection({ key = "uf_" .. unit }, Builder(), unit)
end
local function BuildGroup(scope, lane, tool)
    Reset()
    local builder = Builder()
    M.BuildAuras3GroupLaneWorkspace({ key = "gf_auras" }, builder, scope, lane, { tool = tool, compact = true })
    return builder
end

-- 1. Target Buff Style: lane Full-Frame Effect and the native stealable note.
BuildUnit("target", "buff", "style")
assert(Has(sections, "Frame Basics") and switches["Mark Stealable Buffs"],
    flavor .. ": the target Buff Style lost its Frame Basics or stealable switch")
assert(Has(sections, "Full-Frame Effect") == not IS_CLASSIC, flavor .. (IS_CLASSIC
    and ": Classic builds the lane Full-Frame Effect that no Classic runtime renders"
    or ": the Retail lane Full-Frame Effect section is missing"))
assert(Has(tooltips, "Native stealable marker") == not IS_CLASSIC, flavor .. (IS_CLASSIC
    and ": Classic shows the native 12.1 stealable-marker note"
    or ": the Retail stealable-marker note is missing"))

-- 2. Rectangular debuff previews keep an atlas dispel border on Classic. The
-- Debuffs Appearance page renders the sample icons through the Preview sibling.
local function BuildDebuffAppearance()
    Reset()
    M.pages.auras3_debuffs.build({ key = "auras3_debuffs" })
end
iconShape = "RECTANGLE"
BuildDebuffAppearance()
local atlasDrawn = false
for i = 1, #events do
    if events[i]:find("SetAtlas ", 1, true) and events[i]:find("ui-debuff-border-magic-noicon", 1, true) then atlasDrawn = true end
end
if IS_CLASSIC then
    assert(atlasDrawn and not Has(dispelPreviewShapes, "RECTANGLE"),
        flavor .. ": a rectangular debuff preview no longer gets the atlas dispel border")
else
    assert(Has(dispelPreviewShapes, "RECTANGLE") and not atlasDrawn,
        flavor .. ": the Retail dispel preview no longer draws the rectangular border")
end
iconShape = "CIRCLE"
BuildDebuffAppearance()
assert(Has(dispelPreviewShapes, "CIRCLE"), flavor .. ": a shaped debuff preview no longer asks the aura backend")
iconShape = "RECTANGLE"

-- 3. Global Appearance: the Blizzard Buff & Debuff Frames section on every client.
Reset()
M.pages.auras3_buffs.build({ key = "auras3_buffs" })
assert(Has(sections, "Blizzard Buff & Debuff Frames") and switches["Hide Blizzard Buff Frame"]
    and switches["Hide Blizzard Debuff Frame"], flavor .. ": the Blizzard Buff & Debuff Frames section is missing")

-- 4. Group filters: Only mine on Classic; a Non-player token is not Only mine.
BuildGroup("raid", "debuff", "filters")
if IS_CLASSIC then
    local onlyMine = assert(switches["Only mine"], flavor .. ": the Classic group Only mine switch is missing")
    assert(switches["Hide permanent"] and not switches["All"] and not switches["Non-Player Auras"],
        flavor .. ": the Classic group filters are not Only mine and Hide permanent")
    assert(onlyMine.get() == false, flavor .. ": a Non-player group token reads as Only mine")
    assert(tooltipBodies["Only mine"] == "Only Debuffs applied by the player."
        and tooltipBodies["Hide permanent auras"] == "Always excludes auras without a duration.",
        flavor .. ": the Classic group filter tooltips are not the Classic texts")
    local mineKeys = onlyMine.meta and onlyMine.meta.assistantSettingKeys
    assert(onlyMine.meta and onlyMine.meta.identityKey == "auras.group-workspace.lane.debuff.filters.only-mine"
        and type(mineKeys) == "table" and #mineKeys == 2
        and mineKeys[1] == "gf_raid.auras.debuff.filterToken" and mineKeys[2] == "gf_mythicraid.auras.debuff.filterToken",
        flavor .. ": the Classic group Only mine switch lost its filterToken control id or assistant keys")
    local hideMeta = switches["Hide permanent"].meta
    local hideKeys = hideMeta and hideMeta.assistantSettingKeys
    assert(hideMeta and hideMeta.identityKey == "auras.group-workspace.lane.debuff.filters.hide-permanent"
        and type(hideKeys) == "table" and #hideKeys == 1 and hideKeys[1] == "gf_raid.auras.debuff.blacklist.hidePermanent",
        flavor .. ": the Classic group Hide permanent switch lost its control id or assistant key")
    DB.gf_raid.auras.debuff.filterToken = "RaidPlayer"
    assert(onlyMine.get() == true, flavor .. ": a player-owned group token no longer reads as Only mine")
    DB.gf_raid.auras.debuff.filterToken = "NonPlayer"
else
    assert(switches["Non-Player Auras"] and not switches["Only mine"],
        flavor .. ": the Retail group filter list is missing")
end

-- 5. Group blacklist writes: the focused Auras dirty path on Classic only.
local expectedMode = IS_CLASSIC and "auras" or "visual"
BuildGroup("raid", "debuff", "blacklist")
local buttons, clicked = clickable, 0
for i = 1, #buttons do
    local button = buttons[i]
    queued = {}
    rawget(button, "_scripts").OnClick(button, "LeftButton")
    if #queued > 0 then
        clicked = clicked + 1
        for j = 1, #queued do
            assert(queued[j]:match(":(.+)$") == expectedMode,
                flavor .. ": a group blacklist write queued " .. queued[j] .. " instead of mode " .. expectedMode)
        end
    end
end
assert(clicked > 0, flavor .. ": no group blacklist action queued a group apply")

-- 6. Group blacklist Preset with the shipped preset catalogue, whose list starts
-- with a category header that has no value. Classic opens on the lane default
-- while the picked preset is not in the lane's list; Midnight and WoW Forever keep
-- the Retail reader (the first row's value).
local presetNS = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Presets.lua"))(
    "MidnightSimpleUnitFrames", presetNS)
local presetModel = {}
local Presets = presetNS.Auras3MenuModelFactories.Presets(presetModel, {
    AuraFilter = function() return nil end,
    NormalizeKind = function(kind) return tostring(kind) == "debuff" and "debuff" or "buff" end,
    NormalizeScope = function(scope) return scope end,
    SpellInfo = function(id) return id, "Spell " .. tostring(id), 136000 end,
})
-- MSUF_Auras3_Menu_GroupFilters.lua GroupBlacklistPresetValues and GroupBlacklistSpellValues.
rawset(Model, "GroupBlacklistPresetValues", function(lane)
    return Presets.BuildBlacklistPresetValues(Presets.BlacklistPresetKeysForKind(lane))
end)
rawset(Model, "GroupBlacklistSpellValues", function(lane, key)
    if Presets.BlacklistPresetKeysForKind(lane)[tostring(key or "")] ~= true then return {} end
    return presetModel.BlacklistSpellValues(key)
end)
local firstRow = Model.GroupBlacklistPresetValues("debuff")[1]
assert(firstRow and firstRow.header and firstRow.value == nil,
    "the blacklist preset catalogue no longer starts with a header row; revisit this check")
local presetCases = {
    { lane = "debuff", picked = nil, classic = "SATED" },
    { lane = "debuff", picked = "RAID_BUFFS", classic = "SATED" },
    { lane = "buff", picked = nil, classic = "RAID_BUFFS" },
    { lane = "debuff", picked = "DESERTER", classic = "DESERTER", retail = "DESERTER" },
}
for i = 1, #presetCases do
    local case = presetCases[i]
    M.auraBlacklistPreset = case.picked
    BuildGroup("raid", case.lane, "blacklist")
    local preset = assert(dropdowns.Preset, flavor .. ": the group blacklist Preset dropdown is missing")
    local spell = assert(dropdowns.Spell, flavor .. ": the group blacklist Spell dropdown is missing")
    local want = IS_CLASSIC and case.classic or case.retail
    local got, spells = preset.get(), #spell.values()
    assert(got == want and (want == nil) == (spells == 0), string.format(
        "%s: the %s group blacklist with %s picked opened on %s (%d spells), expected %s",
        flavor, case.lane, tostring(case.picked), tostring(got), spells, tostring(want)))
end
M.auraBlacklistPreset = nil

print("classic aura page client gates smoke passed: " .. flavor)
