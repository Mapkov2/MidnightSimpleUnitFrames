-- Additional group units and size-dependent appearance; called by the existing lazy Layout page.
local _, MSUF = ...
local M = MSUF.MSUF2
local W, T, GP = M.Widgets, M.Theme, M.GroupPage
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.GroupOptions()
local CUSTOM_OPTIONS = Schema.UnitOptions()
local max, min, floor = math.max, math.min, math.floor
-- Release links select a declared scope and retain any existing tab hook.
local EXACT_SCOPES = {
    centerSolo = { "party" }, smallRaidAsParty = { "party" },
    targetsEnabled = { "party" }, targetsIncludePlayer = { "party" },
    targetsWidth = { "party" }, targetsHeight = { "party" }, targetsX = { "party" },
    targetsY = { "party" }, targetsColumns = { "party" }, targetsTextSize = { "party" },
    collapseEmptyGroups = { "raid", "mythicraid" },
    hideMythicGroupsFiveToEight = { "mythicraid" },
    layoutTiersEnabled = { "raid", "mythicraid" },
    excludeHiddenGroups = { "raid", "mythicraid" },
}
local function WithExactGroupScope(widget, key, prepare)
    if not widget then return widget end
    local contracts = {}
    for _, scope in ipairs(EXACT_SCOPES[key] or { "party", "raid", "mythicraid" }) do
        if MSUF.Client.SupportsGroupKind(scope) then contracts[scope] = "gf_" .. scope .. "." .. key end
    end
    local previousPrepare = widget._msuf2PrepareExactSearchTarget
    widget._msuf2ExactTargetKinds = widget._msuf2ExactTargetKinds or {}
    widget._msuf2ExactTargetKinds.groupScope = true
    widget._msuf2ExactTargetContracts = widget._msuf2ExactTargetContracts or {}
    widget._msuf2ExactTargetContracts.groupScope = contracts
    widget._msuf2PrepareExactSearchTarget = function(_, exactTarget)
        if type(exactTarget) ~= "table" then return false end
        if exactTarget.prepareKind ~= "groupScope" then
            return previousPrepare and previousPrepare(widget, exactTarget) or false
        end
        local scope = tostring(exactTarget.prepareValue or "")
        local settingKey = contracts[scope]
        if not settingKey or tostring(exactTarget.settingKey or "") ~= settingKey then return false end
        M.SetMenuStateValue("gfScope", scope)
        if GP.CurrentScope() ~= scope then return false end
        return not prepare or prepare() == true
    end
    return widget
end
-- Prepare the master on the lazy shell; content reuses its widget and binding.
local function PrepareAdditionalSwitch(ctx, section, key, label, mode)
    local entry = section and section._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    -- These masters default off in every scope; read the current config once.
    local function Enabled() return MSUF.GF.GetConf(GP.CurrentScope())[key] and true or false end
    local toggle = Schema.Build(ctx, section, {
        { "sectionSwitch", key, false, { label }, get = Enabled,
            set = function(value)
                GP.Set(GP.CurrentScope(), key, value, mode)
                GP.RefreshContext(ctx)
            end,
            meta = GP.ResolveControlMeta(ctx, nil, "field." .. key), domain = mode, scope = "group" },
    }, CUSTOM_OPTIONS)[key]
    WithExactGroupScope(toggle, key)
    toggle:SetChecked(Enabled())
    return toggle
end
-- Register after the body builds so the lazy refresh reaches every new control.
-- The header master stays outside the body and other disable gates still apply.
local function BindAdditionalGate(ctx, section, key)
    local gateKey = "group-feature:" .. key
    M.TrackCollapsibleRefresh(ctx, section, function()
        M.ControlGates.Apply(section, gateKey, MSUF.GF.GetConf(GP.CurrentScope())[key])
    end)
end
local SECTION_BY_ID = {}
-- Shared shell of every master-switch section: the collapsible, its group scope and its master
-- switch. Returns the section, its width, the two-column control width and the switch key.
local function BeginSection(ctx, b, id)
    local def = SECTION_BY_ID[id]
    local section = b:CollapsibleSection(id, def.title, def.height, false)
    if section._msuf2CollapsibleEntry then Schema.Section(section, "group") end
    local width = section._msuf2Width or b.width or 720
    PrepareAdditionalSwitch(ctx, section, def.key, def.label, def.mode)
    return section, width, max(180, (width - 96) / 2), def.key
end
-- Slider row of a two-column section (left column x = 32, right column x = controlWidth + 64).
local function SliderRow(key, default, label, lo, hi, x, y, width)
    return { "slider", key, default, { label, lo, hi, 1, width }, { x, y, width, "LEFT" }, domain = "rebuild", scope = "group" }
end
local function BuildAdditionalSection(ctx, b, id, prefix, extra)
    local section, width, controlWidth, gateKey = BeginSection(ctx, b, id)
    local right = controlWidth + 64
    local rows = {}
    if extra then rows[1] = { "toggle", extra[1], extra[2], { extra[3], 32, -72, controlWidth }, domain = "rebuild" } end
    rows[#rows + 1] = SliderRow(prefix .. "Width", 100, "Width", 20, 500, 32, -128, controlWidth)
    rows[#rows + 1] = SliderRow(prefix .. "Height", 24, "Height", 10, 200, right, -128, controlWidth)
    rows[#rows + 1] = SliderRow(prefix .. "X", 0, "Horizontal position", -2000, 2000, 32, -218, controlWidth)
    rows[#rows + 1] = SliderRow(prefix .. "Y", -220, "Vertical position", -2000, 2000, right, -218, controlWidth)
    if prefix ~= "healerMana" then
        rows[#rows + 1] = SliderRow(prefix .. "Columns", 1, "Frames per row", 1, 8, 32, -308, controlWidth)
    end
    rows[#rows + 1] = SliderRow(prefix .. "TextSize", 11, "Text size", 7, 32, right, -308, controlWidth)
    if prefix == "pets" then
        rows[#rows + 1] = SliderRow(prefix .. "MaxCount", 40, "Pet limit", 1, 40, 32, -398, controlWidth)
    end
    rows[#rows + 1] = { "text", "menu2.gf_layout." .. prefix .. ".position_help", nil,
            { "X and Y count from the middle of the screen. Secure frames take new settings once combat ends.",
                32, prefix == "pets" and -482 or -392, width - 64, T.colors.muted }, scope = "group" }
    if prefix == "healerMana" or prefix == "friendlyBoss" then
        rows[#rows + 1] = { "text", "menu2.gf_layout." .. prefix .. ".role_help", nil,
                { "Healers are found by their assigned group role, not by class. Classic and Forever groups often leave roles " ..
                    "unassigned: set them with Set Role in a member's right-click menu where the game offers it.",
                    32, -432, width - 64, T.colors.muted }, scope = "group" }
    end
    if prefix == "healerMana" then
        rows[#rows + 1] = { "toggle", "healerManaShowValue", true, { "Show mana amount", 32, -308, controlWidth }, domain = "rebuild" }
    end
    local controls = Schema.Build(ctx, section, rows, ROW_OPTIONS)
    for _, row in ipairs(rows) do
        if row[1] == "slider" or row[2] == "targetsIncludePlayer" then WithExactGroupScope(controls[row[2]], row[2]) end
    end
    if prefix == "healerMana" then
        W.AttachContextColorReferences(section, { "group.healer_mana_text" }, {
            title = "Healer mana bars", historyLabel = "Text color",
            historySource = "menu:group-healer-mana-text-color", maxTargets = 1,
        })
    end
    BindAdditionalGate(ctx, section, gateKey)
end
-- extra: { key, default, label } of the toggle above the sliders.
local function UnitSection(id, prefix, extra)
    return function(ctx, b) BuildAdditionalSection(ctx, b, id, prefix, extra) end
end
local BuildTargets = UnitSection("party_targets", "targets", { "targetsIncludePlayer", false, "Include your own target" })
local BuildPets = UnitSection("group_pets", "pets")
local BuildFriendlyBosses = UnitSection("friendly_bosses", "friendlyBoss", { "friendlyBossHealerOnly", true, "Only while you are a healer" })
local BuildHealerMana = UnitSection("healer_mana", "healerMana")

-- Opacity is edited in percent and stored as 0-1: the scope slider binder saves
-- whole numbers, so a 0-1 slider could only store fully clear or opaque.
local function PercentSlider(ctx, parent, label, key, default, width, x, y)
    local metadata = GP.ResolveControlMeta(ctx, nil, "field." .. key)
    metadata.step, metadata.roundStep = 1, true
    local control = Schema.Build(ctx, parent, {
        { "slider", key, floor(default * 100 + 0.5), { label, 0, 100, 5, width }, get = function() return floor(GP.Num(GP.CurrentScope(),
            key, default) * 100 + 0.5) end,
            set = function(v) GP.Set(GP.CurrentScope(), key, max(0, min(100, floor((tonumber(v) or 0) + 0.5))) / 100, "rebuild") end,
            meta = metadata, domain = "rebuild", scope = "group" },
    }, CUSTOM_OPTIONS)[key]
    W.MoveWidget(control, parent, x, y, width, "LEFT")
    return control
end

local function BuildNameBar(ctx, b)
    local section, _, width, gateKey = BeginSection(ctx, b, "name_bar")
    Schema.Build(ctx, section, { SliderRow("nameBarHeight", 14, "Strip height", 4, 60, 32, -128, width) }, ROW_OPTIONS)
    PercentSlider(ctx, section, "Strip opacity", "nameBarAlpha", .95, width, width + 64, -128)
    Schema.Build(ctx, section, {
        { "color", "nameBarColor", nil, { "Strip color" }, setting = Schema.Record({
            "gf_{scope}.nameBarR", "gf_{scope}.nameBarG", "gf_{scope}.nameBarB" }), { 32, -218, width, "LEFT" },
            get = function()
                return GP.Num(GP.CurrentScope(), "nameBarR", .05), GP.Num(GP.CurrentScope(), "nameBarG", .05), GP.Num(GP.CurrentScope(), "nameBarB", .05)
            end,
            set = function(r, g, b)
                local conf = GP.Conf(GP.CurrentScope())
                conf.nameBarR, conf.nameBarG, conf.nameBarB = r, g, b
                GP.QueueGF(GP.CurrentScope(), "rebuild")
            end,
            meta = GP.ResolveControlMeta(ctx, nil, "color.nameBar"), domain = "rebuild", scope = "group" },
    }, CUSTOM_OPTIONS)
    BindAdditionalGate(ctx, section, gateKey)
end
-- Buff coverage (WoW Forever). A toggle shows the client's own name for the
-- buff's first spell when it can read one, so every language sees the name it
-- knows from the game; the English text is the fallback and the locale key.
local BUFF_COVERAGE_TOGGLES = {
    { key = "buffCoverageWild", label = "Mark of the Wild", spell = 1126, default = true },
    { key = "buffCoverageThorns", label = "Thorns", spell = 467, default = false },
    { key = "buffCoverageIntellect", label = "Arcane Intellect", spell = 1459, default = true },
    { key = "buffCoverageBlessings", label = "Paladin blessings", default = true },
    { key = "buffCoverageStamina", label = "Power Word: Fortitude", spell = 1243, default = true },
    { key = "buffCoverageSpirit", label = "Divine Spirit", spell = 14752, default = false },
}
local ICON_ANCHORS = {
    {value="TOPLEFT",text="Top left"}, {value="TOP",text="Top"}, {value="TOPRIGHT",text="Top right"},
    {value="LEFT",text="Left"}, {value="CENTER",text="Center"}, {value="RIGHT",text="Right"},
    {value="BOTTOMLEFT",text="Bottom left"}, {value="BOTTOM",text="Bottom"}, {value="BOTTOMRIGHT",text="Bottom right"},
}
local function BuffLabel(entry)
    local spellAPI = C_Spell
    local name = entry.spell and spellAPI and type(spellAPI.GetSpellName) == "function" and spellAPI.GetSpellName(entry.spell)
    local secret = issecretvalue
    if name ~= nil and not (secret and secret(name)) and type(name) == "string" and name ~= "" then return name end
    return entry.label
end
local BLESSING_CHOICES = {
    { value = 0, text = "Follow role / any blessing" },
    { value = 1, text = "Blessing of Might" }, { value = 2, text = "Blessing of Wisdom" },
    { value = 3, text = "Blessing of Kings" }, { value = 4, text = "Blessing of Salvation" },
    { value = 5, text = "Blessing of Light" }, { value = 6, text = "Blessing of Sanctuary" },
}
local function BuildBlessingPriorities(ctx, b)
    local section, _, width, gateKey = BeginSection(ctx, b, "blessing_priorities")
    local rows = {
        { "text", "menu2.gf_layout.blessingpriorities.help", nil, { [[Choose up to three blessings per role.
Paladins use their first learned choice. Other classes use the first choice; unassigned members use DPS.]], 32, -82, width * 2 + 32, T.colors.muted },
    scope = "group" },
    }
    local roles = { { "Tank", "Tank" }, { "Healer", "Healer" }, { "DPS", "DPS" } }
    local labels = { "First choice", "Second choice", "Third choice" }
    for row, role in ipairs(roles) do
        local y = -178 - (row - 1) * 220
        rows[#rows + 1] = { "text", "menu2.gf_layout.blessingpriorities.role." .. role[1], nil, { role[2], 32, y, width * 2 + 32,
            T.colors.text }, scope = "group" }
        for rank = 1, 3 do
            local key = "buffCoverageBlessing" .. role[1] .. rank
            rows[#rows + 1] = { "dropdown", key, rank == 1 and ({ Tank = 3, Healer = 2, DPS = 4 })[role[1]] or 0, { labels[rank], BLESSING_CHOICES, width },
                    { rank == 2 and width + 64 or 32, y - 68 - (rank == 3 and 82 or 0), width, "LEFT" }, domain = "visual" }
        end
    end
    rows[#rows + 1] = { "text", "menu2.gf_layout.blessingpriorities.class_help", nil,
            { "Class exceptions replace role priorities. Paladins must know the chosen blessing.", 32, -840, width * 2 + 32, T.colors.muted }, scope = "group" }
    local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    for i, class in ipairs(classes) do
        local names = LOCALIZED_CLASS_NAMES_MALE
        local key = "buffCoverageBlessing" .. class
        rows[#rows + 1] = { "dropdown", key, 0, { names and names[class] or class, BLESSING_CHOICES, width },
            { i % 2 == 1 and 32 or width + 64, -934 - math.floor((i - 1) / 2) * 70, width, "LEFT" }, domain = "visual" }
    end
    local controls = Schema.Build(ctx, section, rows, ROW_OPTIONS)
    for _, row in ipairs(rows) do
        if row[1] == "dropdown" then WithExactGroupScope(controls[row[2]], row[2]) end
    end
    BindAdditionalGate(ctx, section, gateKey)
end
local function BuildBuffCoverage(ctx, b)
    local section, _, width, gateKey = BeginSection(ctx, b, "buff_coverage")
    local rows = {}
    for i = 1, #BUFF_COVERAGE_TOGGLES do
        local entry = BUFF_COVERAGE_TOGGLES[i]
        local x, y = i % 2 == 1 and 32 or width + 64, -78 - math.floor((i - 1) / 2) * 36
        rows[#rows + 1] = { "toggle", entry.key, entry.default, { BuffLabel(entry), x, y, width }, domain = "visual" }
    end
    local details = {
        { "toggle", "buffCoverageThornsTankOnly", true, { "Thorns only on tanks", 32, -194, width }, domain = "visual", scope = "group" },
        { "toggle", "buffCoverageGlow", false, { "Glow missing icons", width + 64, -194, width }, domain = "visual", scope = "group" },
        { "toggle", "buffCoverageCombat", false, { "Keep showing during combat", 32, -230, width * 2 }, domain = "visual", scope = "group" },
        { "slider", "buffCoverageSize", 14, { "Icon size", 8, 48, 1, width }, { 32, -316, width, "LEFT" }, domain = "visual", scope = "group" },
        { "dropdown", "buffCoverageAnchor", "BOTTOM", { "Icon anchor", ICON_ANCHORS, width }, { width + 64, -316, width, "LEFT" }, domain = "visual",
            scope = "group" },
        { "slider", "buffCoverageX", 0, { "Horizontal offset", -200, 200, 1, width }, { 32, -406, width, "LEFT" }, domain = "visual", scope = "group" },
        { "slider", "buffCoverageY", 2, { "Vertical offset", -200, 200, 1, width }, { width + 64, -406, width, "LEFT" }, domain = "visual", scope = "group" },
        { "slider", "buffCoverageLayer", 6, { "Layer", 0, 30, 1, width }, { 32, -496, width, "LEFT" }, domain = "visual", scope = "group" },
        { "text", "menu2.gf_layout.buffcoverage.help", nil,
            { "Each icon marks a buff that a class in your group can cast but this member lacks. Thorns is checked on " ..
                "members with the Tank role (on everyone with Thorns only on tanks off), Arcane Intellect and Divine Spirit on " ..
                "mana users. Combat, encounters and PvP matches hide aura data, so the icons keep their last known state until " ..
                "it ends.",
            32, -566, width * 2 + 32, T.colors.muted }, scope = "group" },
    }
    for _, row in ipairs(details) do rows[#rows + 1] = row end
    local controls = Schema.Build(ctx, section, rows, ROW_OPTIONS)
    WithExactGroupScope(controls.buffCoverageGlow, "buffCoverageGlow")
    WithExactGroupScope(controls.buffCoverageCombat, "buffCoverageCombat")
    BindAdditionalGate(ctx, section, gateKey)
end
local TIER_GROWTH = { {value="INHERIT",text="Same as the base layout"}, {value="DOWN",text="Down"}, {value="UP",text="Up"}, {value="LEFT",text="Left"},
    {value="RIGHT",text="Right"} }
local function BuildSizingTier(ctx, parent, prefix, fullWidth, metadata)
    local width = (fullWidth - 96) / 2
    local rows = {
        { "slider", prefix .. "Width", 0, { "Frame width for this raid size (0 = base)", 0, 500, 1, width - 32 }, { 32, -202, width - 32, "LEFT" } },
        { "slider", prefix .. "Height", 0, { "Frame height for this raid size (0 = base)", 0, 200, 1, width - 32 }, { width + 64, -202, width - 32, "LEFT" } },
        { "dropdown", prefix .. "Growth", "INHERIT", { "Growth direction", TIER_GROWTH, width }, { 32, -282, width, "LEFT" } },
        { "toggle", prefix .. "Position", false, { "Own position for this raid size", width + 64, -310, width } },
        { "slider", prefix .. "X", 0, { "Horizontal position", -2000, 2000, 1, width - 32 }, { 32, -406, width - 32, "LEFT" } },
        { "slider", prefix .. "Y", 0, { "Vertical position", -2000, 2000, 1, width - 32 }, { width + 64, -406, width - 32, "LEFT" } },
        { "text", "menu2.gf_layout.sizingtier.help." .. prefix, nil,
            { "Turn on raid size overrides under General to edit these. The position uses the group's anchor point.", 32, -470,
                fullWidth - 64, T.colors.muted }, scope = "group" },
    }
    local options = { bind = function(_, widget, row, kind)
        local meta = metadata(row[2], prefix)
        local binder = kind == "slider" and GP.BindScopeSlider or kind == "dropdown" and GP.BindScopeDropdown or GP.BindScopeToggle
        binder(ctx, widget, row[2], row[3], "rebuild", meta)
        Schema.Owned(widget, "group", "rebuild")._msuf2ControlSchema.setting = Schema.GroupKeys(row[2])
        meta.label, meta.kind = row[4][1], kind
        if kind == "dropdown" then meta.values = TIER_GROWTH end
        M.RegisterSearchWidget(widget, meta)
        if kind == "slider" then
            W.AttachGroupEditFocus(widget, GP.CurrentScope and function() return "gf_" .. GP.CurrentScope() end, "layout")
            if row[2] == prefix .. "X" or row[2] == prefix .. "Y" then widget._msuf2TierPositionKey = prefix .. "Position" end
        end
    end }
    local refs, controls = Schema.Build(ctx, parent, rows, options), {}
    for i = 1, 6 do controls[i] = refs[rows[i][2]] end
    return controls
end

-- One entry per section this file builds, in Layout page order: collapsible id, title and height,
-- the master switch (key, label, apply domain) and the gates the Layout page applies before it builds one.
-- clientCapability: the MSUF.Client fact that must be true for the section to
-- exist, the same capability names Search/MSUF_Menu2_Search_IndexQuery.lua
-- ties client-only static search rows to. frameScope: the unit or group scope
-- the section needs (M.SupportsFrameScope), e.g. boss units for allied bosses.
local SECTION_DEFS = {
    { sectionId = "buff_coverage", title = "Buff coverage (Forever)", height = 656, clientCapability = "IsForever", build = BuildBuffCoverage,
        key = "buffCoverageEnabled", label = "Show buff coverage icons", mode = "visual" },
    { sectionId = "blessing_priorities", title = "Blessing priorities (Forever)", height = 1330, clientCapability = "IsForever",
        build = BuildBlessingPriorities, key = "buffCoverageBlessingPriorities", label = "Use blessing priorities", mode = "visual" },
    { sectionId = "name_bar", title = "Name strip", height = 300, build = BuildNameBar,
        key = "nameBarEnabled", label = "Show names on a strip above the health bar", mode = "rebuild" },
    { sectionId = "party_targets", title = "Member targets", height = 456, groupScope = "party", build = BuildTargets,
        key = "targetsEnabled", label = "Enable", mode = "rebuild" },
    { sectionId = "group_pets", title = "Pet frames", height = 546, build = BuildPets, key = "petsEnabled", label = "Enable", mode = "rebuild" },
    { sectionId = "friendly_bosses", title = "Allied boss frames", height = 536, frameScope = "boss", build = BuildFriendlyBosses,
        key = "friendlyBossEnabled", label = "Enable", mode = "rebuild" },
    { sectionId = "healer_mana", title = "Healer mana bars", height = 520, build = BuildHealerMana,
        key = "healerManaEnabled", label = "Enable", mode = "rebuild" },
}
for _, def in ipairs(SECTION_DEFS) do SECTION_BY_ID[def.sectionId] = def end
-- Fresh Layout page specs for these sections, ready for its lazy section builder.
local function LayoutSpecs()
    local specs = {}
    for i, def in ipairs(SECTION_DEFS) do
        specs[i] = {
            sectionId = def.sectionId, title = def.title, height = def.height, build = def.build,
            clientCapability = def.clientCapability, groupScope = def.groupScope, frameScope = def.frameScope,
            prepareShell = function(ctx, section) PrepareAdditionalSwitch(ctx, section, def.key, def.label, def.mode) end,
        }
    end
    return specs
end

M.GroupFrameAdditionalSections = {
    Targets = BuildTargets, Pets = BuildPets, FriendlyBosses = BuildFriendlyBosses, HealerMana = BuildHealerMana,
    NameBar = BuildNameBar, BuffCoverage = BuildBuffCoverage, BlessingPriorities = BuildBlessingPriorities,
    SizingTier = BuildSizingTier, ExactScope = WithExactGroupScope, PrepareSwitch = PrepareAdditionalSwitch,
    LayoutSpecs = LayoutSpecs,
}
