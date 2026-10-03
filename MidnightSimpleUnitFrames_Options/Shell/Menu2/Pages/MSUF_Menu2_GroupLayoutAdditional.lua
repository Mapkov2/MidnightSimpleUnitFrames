-- Additional group units and size-dependent appearance; called by the existing lazy Layout page.
local _, MSUF = ...
local M = MSUF.MSUF2
local W, T, GP = M.Widgets, M.Theme, M.GroupPage
local max, min, floor = math.max, math.min, math.floor
local BindScopeToggle, ScopeSlider, ScopeDropdown, ScopeColor = GP.BindScopeToggle, GP.ScopeSlider, GP.ScopeDropdown, GP.ScopeColor
-- Release links select a declared scope and retain any existing tab hook.
local EXACT_SCOPES = {
    centerSolo = { "party" }, smallRaidAsParty = { "party" },
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
    local toggle = W.SectionSwitch(section, label)
    -- These masters default off in every scope; read the current config once.
    local function Enabled() return MSUF.GF.GetConf(GP.CurrentScope())[key] and true or false end
    M.BindBoolWidget(ctx, toggle, Enabled, function(value)
        GP.Set(GP.CurrentScope(), key, value, mode)
        GP.RefreshContext(ctx)
    end, GP.ResolveControlMeta(ctx, nil, "field." .. key))
    WithExactGroupScope(toggle, key)
    toggle:SetChecked(Enabled())
    return toggle
end
local function BuildAdditionalSection(ctx, b, id, title, prefix, extra)
    local height = prefix == "healerMana" and 520 or prefix == "friendlyBoss" and 536 or prefix == "pets" and 546 or 456
    local section = b:CollapsibleSection(id, title, height, false)
    local width = section._msuf2Width or b.width or 720
    local controlWidth = max(180, (width - 96) / 2)
    PrepareAdditionalSwitch(ctx, section, prefix .. "Enabled", "Enable", "rebuild")
    if extra then extra(section, controlWidth) end
    local function Slider(label, key, low, high, step, default, x, y)
        ScopeSlider(ctx, section, label, low, high, step, controlWidth, prefix .. key, default, "rebuild", x, y, controlWidth, "LEFT")
    end
    Slider("Width", "Width", 20, 500, 1, 100, 32, -128)
    Slider("Height", "Height", 10, 200, 1, 24, controlWidth + 64, -128)
    Slider("Horizontal position", "X", -2000, 2000, 1, 0, 32, -218)
    Slider("Vertical position", "Y", -2000, 2000, 1, -220, controlWidth + 64, -218)
    if prefix ~= "healerMana" then Slider("Frames per row", "Columns", 1, 8, 1, 1, 32, -308) end
    Slider("Text size", "TextSize", 7, 32, 1, 11, controlWidth + 64, -308)
    if prefix == "pets" then Slider("Pet limit", "MaxCount", 1, 40, 1, 40, 32, -398) end
    W.Text(section, "X and Y count from the middle of the screen. Secure frames take new settings once combat ends.", 32, prefix == "pets" and -482 or -392,
        width - 64, T.colors.muted)
    if prefix == "healerMana" or prefix == "friendlyBoss" then
        W.Text(section, "Healers are found by their assigned group role, not by class. Classic and Forever groups often leave roles unassigned: set them with Set Role in a member's right-click menu where the game offers it.", 32, -432, width - 64, T.colors.muted)
    end
    if prefix == "healerMana" then
        BindScopeToggle(ctx, W.ToggleAt(section, "Show mana amount", 32, -308, controlWidth), "healerManaShowValue", true, "rebuild")
        W.AttachContextColorReferences(section, { "group.healer_mana_text" }, {
            title = "Healer mana bars", historyLabel = "Text color",
            historySource = "menu:group-healer-mana-text-color", maxTargets = 1,
        })
    end
end
local function BuildTargets(ctx, b)
    BuildAdditionalSection(ctx, b, "party_targets", "Member targets", "targets", function(section, width)
        BindScopeToggle(ctx, W.ToggleAt(section, "Include your own target", 32, -72, width), "targetsIncludePlayer", false, "rebuild")
    end)
end
local function BuildPets(ctx, b) BuildAdditionalSection(ctx, b, "group_pets", "Pet frames", "pets") end
local function BuildFriendlyBosses(ctx, b)
    BuildAdditionalSection(ctx, b, "friendly_bosses", "Allied boss frames", "friendlyBoss", function(section, width)
        BindScopeToggle(ctx, W.ToggleAt(section, "Only while you are a healer", 32, -72, width), "friendlyBossHealerOnly", true, "rebuild")
    end)
end
local function BuildHealerMana(ctx, b) BuildAdditionalSection(ctx, b, "healer_mana", "Healer mana bars", "healerMana") end

-- Opacity is edited in percent and stored as 0-1: the scope slider binder saves
-- whole numbers, so a 0-1 slider could only store fully clear or opaque.
local function PercentSlider(ctx, parent, label, key, default, width, x, y)
    local control = W.Slider(parent, label, 0, 100, 5, width)
    local metadata = GP.ResolveControlMeta(ctx, nil, "field." .. key)
    metadata.step, metadata.roundStep = 1, true
    M.BindNumberWidget(ctx, control,
        function() return floor(GP.Num(GP.CurrentScope(), key, default) * 100 + 0.5) end,
        function(v) GP.Set(GP.CurrentScope(), key, max(0, min(100, floor((tonumber(v) or 0) + 0.5))) / 100, "rebuild") end,
        floor(default * 100 + 0.5), metadata)
    W.MoveWidget(control, parent, x, y, width, "LEFT")
    return control
end

local function BuildNameBar(ctx, b)
    local section = b:CollapsibleSection("name_bar", "Name strip", 300, false)
    local width = max(180, ((section._msuf2Width or b.width or 720) - 96) / 2)
    PrepareAdditionalSwitch(ctx, section, "nameBarEnabled", "Show names on a strip above the health bar", "rebuild")
    local function Slider(label, key, low, high, step, default, x, y)
        ScopeSlider(ctx, section, label, low, high, step, width, key, default, "rebuild", x, y, width, "LEFT")
    end
    Slider("Strip height", "nameBarHeight", 4, 60, 1, 14, 32, -128)
    PercentSlider(ctx, section, "Strip opacity", "nameBarAlpha", .95, width, width + 64, -128)
    ScopeColor(ctx, section, "Strip color", width, "nameBarR", "nameBarG", "nameBarB", {.05, .05, .05}, "rebuild", 32, -218, width, "LEFT")
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
    local spellAPI = _G.C_Spell
    local name = entry.spell and spellAPI and type(spellAPI.GetSpellName) == "function" and spellAPI.GetSpellName(entry.spell)
    local secret = _G.issecretvalue
    if name ~= nil and not (secret and secret(name)) and type(name) == "string" and name ~= "" then return name end
    return entry.label
end
local function BuildBuffCoverage(ctx, b)
    local section = b:CollapsibleSection("buff_coverage", "Buff coverage (Forever)", 656, false)
    local width = max(180, ((section._msuf2Width or b.width or 720) - 96) / 2)
    PrepareAdditionalSwitch(ctx, section, "buffCoverageEnabled", "Show buff coverage icons", "visual")
    for i = 1, #BUFF_COVERAGE_TOGGLES do
        local entry = BUFF_COVERAGE_TOGGLES[i]
        local x, y = i % 2 == 1 and 32 or width + 64, -78 - math.floor((i - 1) / 2) * 36
        BindScopeToggle(ctx, W.ToggleAt(section, BuffLabel(entry), x, y, width), entry.key, entry.default, "visual")
    end
    BindScopeToggle(ctx, W.ToggleAt(section, "Thorns only on tanks", 32, -194, width), "buffCoverageThornsTankOnly", true, "visual")
    BindScopeToggle(ctx, W.ToggleAt(section, "Glow missing icons", width + 64, -194, width), "buffCoverageGlow", false, "visual")
    BindScopeToggle(ctx, W.ToggleAt(section, "Keep showing during combat", 32, -230, width * 2), "buffCoverageCombat", false, "visual")
    ScopeSlider(ctx, section, "Icon size", 8, 48, 1, width, "buffCoverageSize", 14, "visual", 32, -316, width, "LEFT")
    ScopeDropdown(ctx, section, "Icon anchor", ICON_ANCHORS, width, "buffCoverageAnchor", "BOTTOM", "visual", width + 64, -316, width, "LEFT")
    ScopeSlider(ctx, section, "Horizontal offset", -200, 200, 1, width, "buffCoverageX", 0, "visual", 32, -406, width, "LEFT")
    ScopeSlider(ctx, section, "Vertical offset", -200, 200, 1, width, "buffCoverageY", 2, "visual", width + 64, -406, width, "LEFT")
    ScopeSlider(ctx, section, "Layer", 0, 30, 1, width, "buffCoverageLayer", 6, "visual", 32, -496, width, "LEFT")
    W.Text(section, "Each icon marks a buff that a class in your group can cast but this member lacks. Thorns is checked on members with the Tank role (on everyone with Thorns only on tanks off), Arcane Intellect and Divine Spirit on mana users. Combat, encounters and PvP matches hide aura data, so the icons keep their last known state until it ends.", 32, -566, width * 2 + 32, T.colors.muted)
end
local TIER_GROWTH = { {value="INHERIT",text="Same as the base layout"}, {value="DOWN",text="Down"}, {value="UP",text="Up"}, {value="LEFT",text="Left"},
    {value="RIGHT",text="Right"} }
local function BuildSizingTier(ctx, parent, prefix, fullWidth, metadata)
    local width = (fullWidth - 96) / 2
    local controls = {}
    local function Slider(label, suffix, low, high, x, y)
        local meta = metadata(prefix .. suffix, prefix)
        controls[#controls + 1] = ScopeSlider(ctx, parent, label, low, high, 1, width - 32, prefix .. suffix, 0, "rebuild", x, y, width - 32, "LEFT", meta)
        meta.label, meta.kind = label, "slider"
        M.RegisterSearchWidget(controls[#controls], meta)
        W.AttachGroupEditFocus(controls[#controls], GP.CurrentScope and function() return "gf_" .. GP.CurrentScope() end, "layout")
        if suffix == "X" or suffix == "Y" then controls[#controls]._msuf2TierPositionKey = prefix .. "Position" end
    end
    Slider("Frame width for this raid size (0 = base)", "Width", 0, 500, 32, -202)
    Slider("Frame height for this raid size (0 = base)", "Height", 0, 200, width + 64, -202)
    local growthMeta = metadata(prefix .. "Growth", prefix)
    controls[#controls + 1] = ScopeDropdown(ctx, parent, "Growth direction", TIER_GROWTH, width, prefix .. "Growth", "INHERIT", "rebuild", 32, -282,
        width, "LEFT", growthMeta)
    growthMeta.label, growthMeta.kind, growthMeta.values = "Growth direction", "dropdown", TIER_GROWTH
    M.RegisterSearchWidget(controls[#controls], growthMeta)
    local positionMeta = metadata(prefix .. "Position", prefix)
    controls[#controls + 1] = BindScopeToggle(ctx, W.ToggleAt(parent, "Own position for this raid size", width + 64, -310, width), prefix .. "Position", false, "rebuild", positionMeta)
    positionMeta.label, positionMeta.kind = "Own position for this raid size", "toggle"
    M.RegisterSearchWidget(controls[#controls], positionMeta)
    Slider("Horizontal position", "X", -2000, 2000, 32, -406)
    Slider("Vertical position", "Y", -2000, 2000, width + 64, -406)
    W.Text(parent, "Turn on raid size overrides under General to edit these. The position uses the group's anchor point.", 32, -470,
        fullWidth - 64, T.colors.muted)
    return controls
end

M.GroupFrameAdditionalSections = {
    Targets = BuildTargets, Pets = BuildPets, FriendlyBosses = BuildFriendlyBosses, HealerMana = BuildHealerMana,
    NameBar = BuildNameBar, BuffCoverage = BuildBuffCoverage,
    SizingTier = BuildSizingTier, ExactScope = WithExactGroupScope, PrepareSwitch = PrepareAdditionalSwitch,
}
