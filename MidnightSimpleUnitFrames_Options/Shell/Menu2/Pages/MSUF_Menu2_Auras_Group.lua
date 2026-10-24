local addonName, MSUF = ...
MSUF = MSUF or {}
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_Auras_Group.lua")
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Auras page: Group Frame scope.
-- Owns the party/raid aura config readers and writers (gf_* fan-out), the native
-- group filter tables, and the Group Style / Ordering / Filters / Blacklist
-- builders behind M.BuildAuras3GroupLaneWorkspace. Settings and control
-- primitives come from their own modules. AuraGroupSettings exposes only the
-- five configuration readers needed by the preview sibling.
local AurasPage = M.AurasPage
if type(AurasPage) ~= "table" then return end
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
-- The group aura filter tables are owned by the core's aura menu model
-- (Auras3/MenuModel/MSUF_Auras3_Menu_GroupFilters.lua), which publishes them
-- before this load-on-demand addon loads on every client.
local GF_AURA_FILTER = MSUF.Require("MSUF_GF_AuraFilter", "Shell/Menu2/Pages/MSUF_Menu2_Auras_Group.lua")
local VT = M.ValueTextList
local CreateFrame = CreateFrame
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local Schema = M.ControlSchema
-- Ordinary controls are schema rows in the "groups" scope (the row policy lives
-- in MSUF_Menu2_Auras.lua); collapsible sections declare their headers.
local function BoundAura(ctx, parent, row) return AurasPage.Row(ctx, parent, row, "groups") end
local function GroupSection(b, ...) return Schema.Section(b:CollapsibleSection(...), "groups") end
local AURA_COOLDOWN_COLOR_REFERENCES = M.AuraSettings.AURA_COOLDOWN_COLOR_REFERENCES
local AURA_SORT_DIRECTION_VALUES, ActionButton = M.AuraSettings.AURA_SORT_DIRECTION_VALUES, M.AuraControls.ActionButton
local AddAuraTooltipHelp, AddTooltip, AnchorLabel = M.AuraControls.AddAuraTooltipHelp, M.AuraControls.AddTooltip, M.AuraSettings.AnchorLabel
local AuraCatalogToken, AuraControlMeta = M.AuraControls.AuraCatalogToken, M.AuraControls.AuraControlMeta
local AuraControlMetaAtVisiblePath, AuraSortMethodValues = M.AuraControls.AuraControlMetaAtVisiblePath, M.AuraSettings.AuraSortMethodValues
local BuildLaneTabs, COOLDOWN_SWIPE_DIRECTION_VALUES, Card = M.AuraControls.BuildLaneTabs, M.AuraSettings.COOLDOWN_SWIPE_DIRECTION_VALUES, M.AuraControls.Card
local ChoiceLabel, ConfigureMaxDurationSlider, CurrentLane = M.AuraSettings.ChoiceLabel, M.AuraControls.ConfigureMaxDurationSlider, M.AuraSettings.CurrentLane
local DEBUFF_TYPE_BORDER_MODE_VALUES, DURATION_BAR_DIRECTION_VALUES =
    M.AuraSettings.DEBUFF_TYPE_BORDER_MODE_VALUES, M.AuraSettings.DURATION_BAR_DIRECTION_VALUES
local DURATION_BAR_DISPLAY_VALUES, DURATION_BAR_POSITION_VALUES = M.AuraSettings.DURATION_BAR_DISPLAY_VALUES, M.AuraSettings.DURATION_BAR_POSITION_VALUES
local GFAnchorValues, LanePlural, LaneTitle, MatchSuffix =
    M.AuraSettings.GFAnchorValues, M.AuraSettings.LanePlural, M.AuraSettings.LaneTitle, M.AuraSettings.MatchSuffix
local NATIVE_EXACT_AURA_FILTERS_ENABLED = M.AuraSettings.NATIVE_EXACT_AURA_FILTERS_ENABLED
local NATIVE_EXACT_AURA_FILTERS_TEXT, NormalizeAuraSortMethodForLane =
    M.AuraSettings.NATIVE_EXACT_AURA_FILTERS_TEXT, M.AuraSettings.NormalizeAuraSortMethodForLane
local NormalizeDebuffTypeBorderMode, QueueAurasPageRefresh = M.AuraSettings.NormalizeDebuffTypeBorderMode, M.AuraControls.QueueAurasPageRefresh
-- Blacklist edits repaint the page in place: the refreshers repaint pooled rows.
local Repaint, RegisterAuraControl, RegisterAuraTextAction = M.AuraControls.Repaint, M.AuraControls.RegisterAuraControl, M.AuraControls.RegisterAuraTextAction
local Round, ScopeLabel, SetCurrentLane, Tr = M.AuraSettings.Round, M.AuraSettings.ScopeLabel, M.AuraSettings.SetCurrentLane, M.AuraSettings.Tr
local GROUP_NATIVE_FILTER_LABELS = {
    ALL = "All",
    MSUF_GROUP_HIGHLIGHTS_V1 = "MSUF Highlights",
    Player = "Cast by Me",
    BigDefensivePlayer = "Big Defensive by Me",
    ExternalDefensivePlayer = "External Defensive by Me",
    RaidInCombatPlayer = "Raid In Combat Player",
    CancelablePlayer = "Cancelable Player",
    NotCancelablePlayer = "Not Cancelable Player",
    RaidPlayer = "Applicable and Cast by Me",
    BigDefensive = "Big Defensive",
    ExternalDefensive = "External Defensive",
    RaidInCombat = "Raid In Combat",
    Cancelable = "Cancelable",
    NotCancelable = "Not Cancelable",
    Raid = "Raid",
    INCLUDE_NAME_PLATE_ONLY = "Include Nameplate-only",
    RAID_PLAYER_DISPELLABLE = "Dispellable by Group",
    DISPELLABLE = "Any Dispel Type",
    IMPORTANT = "Important",
    CROWD_CONTROL = "Crowd Control",
    NonPlayer = "Non-Player Auras",
}
local GROUP_NATIVE_FILTER_ALLOWED = {
    buff = {
        ALL = true, MSUF_GROUP_HIGHLIGHTS_V1 = true,
        Player = true, BigDefensivePlayer = true, ExternalDefensivePlayer = true,
        BigDefensive = true, ExternalDefensive = true, RaidInCombat = true, Raid = true, RaidPlayer = true,
    },
    debuff = {
        ALL = true, Player = true, Raid = true, RaidInCombat = true,
        RAID_PLAYER_DISPELLABLE = true, DISPELLABLE = true, CROWD_CONTROL = true,
        NonPlayer = true,
    },
}
local GROUP_NATIVE_FILTER_CANONICAL = {
    ALL = "ALL",
    MSUFGROUPHIGHLIGHTSV1 = "MSUF_GROUP_HIGHLIGHTS_V1",
    PLAYER = "Player",
    BIGDEFENSIVEPLAYER = "BigDefensivePlayer",
    EXTERNALDEFENSIVEPLAYER = "ExternalDefensivePlayer",
    RAIDINCOMBATPLAYER = "RaidInCombatPlayer",
    CANCELABLEPLAYER = "CancelablePlayer",
    NOTCANCELABLEPLAYER = "NotCancelablePlayer",
    RAIDPLAYER = "RaidPlayer",
    BIGDEFENSIVE = "BigDefensive",
    EXTERNALDEFENSIVE = "ExternalDefensive",
    RAIDINCOMBAT = "RaidInCombat",
    CANCELABLE = "Cancelable",
    NOTCANCELABLE = "NotCancelable",
    RAID = "Raid",
    INCLUDENAMEPLATEONLY = "INCLUDE_NAME_PLATE_ONLY",
    RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
    DISPELLABLE = "DISPELLABLE",
    IMPORTANT = "IMPORTANT",
    CROWDCONTROL = "CROWD_CONTROL",
    NONPLAYER = "NonPlayer",
}
local function CanonicalGroupFilterValue(value, lane)
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        local key = tostring(value or "ALL"):upper():gsub("[^A-Z0-9]", "")
        local canonical = GROUP_NATIVE_FILTER_CANONICAL[key] or "ALL"
        -- A Non-player token imported from Retail is not Only mine.
        if canonical == "NonPlayer" then return lane == "debuff" and canonical or "ALL" end
        if canonical == "Player" or canonical:sub(-6) == "Player" then return "Player" end
        return "ALL"
    end
    local canonical = GF_AURA_FILTER.NormalizeFilterToken(lane, value)
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[lane == "debuff" and "debuff" or "buff"]
    return allowed[canonical] and canonical or "ALL"
end
local function RefreshGFPreview()
    if type(GP.RefreshGFPreview) == "function" then GP.RefreshGFPreview() end
end
local function GroupScopeKinds(scope)
    if scope == "party" then return "party" end
    return "raid", "mythicraid"
end
local GroupSearchSettingKeys = M.GroupAuraSettingKeys
local function GroupSearchBlacklistSettingKeys(scope, suffix)
    suffix = tostring(suffix or "")
    if scope == "party" then return { "gf_party" .. suffix } end
    -- Raid/Mythic share this editor and backing blacklist operation, but the
    -- Search Registry intentionally exposes one canonical Raid list key.
    return { "gf_raid" .. suffix }
end
local function GroupConf(kind)
    if type(GP.Conf) == "function" then return GP.Conf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end
local function GFAurasRoot(kind, activate)
    local conf = GroupConf(kind)
    conf.auras = conf.auras or {}
    if activate == true then conf.auras.renderer = "CUSTOM" end
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    return conf.auras
end
local function GFAuraGroup(kind, groupKey)
    local root = GFAurasRoot(kind)
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end
local function QueueGroupScope(scope, mode)
    local a, b = GroupScopeKinds(scope)
    GFAurasRoot(a, true)
    if b then GFAurasRoot(b, true) end
    if type(GP.QueueGF) == "function" then
        GP.QueueGF(a, mode or "visual")
        if b then GP.QueueGF(b, mode or "visual") end
    end
    -- Paint the menu preview from the just-written raw Aura style immediately.
    -- The coalesced group apply below still owns runtime recompilation.
    RefreshGFPreview()
end
local function GFReadRoot(scope)
    local kind = GroupScopeKinds(scope)
    return GFAurasRoot(kind)
end
local function GFReadGroup(scope, groupKey)
    local kind = GroupScopeKinds(scope)
    return GFAuraGroup(kind, groupKey)
end
local function GFWriteScopeValue(scope, mode, getTarget, key, value)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local target = getTarget(kind)
        if target[key] == value then return end
        target[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end
local function GFWriteGroupValue(scope, groupKey, key, value, mode)
    GFWriteScopeValue(scope, mode, function(kind) return GFAuraGroup(kind, groupKey) end, key, value)
end
local function GFWriteGroupValues(scope, groupKey, values, mode)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local target = GFAuraGroup(kind, groupKey)
        for key, value in pairs(values) do
            if target[key] ~= value then
                target[key] = value
                changed = true
            end
        end
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end
local function GFWriteRootValue(scope, key, value, mode)
    GFWriteScopeValue(scope, mode, GFAurasRoot, key, value)
end
local function AuraFilter() return GF_AURA_FILTER end
local function GroupFilterValues(groupKey)
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        if groupKey == "debuff" then return VT("ALL", "All", "Player", "Only mine", "NonPlayer", "Non-Player Auras") end
        return VT("ALL", "All", "Player", "Only mine")
    end
    local af = AuraFilter()
    local source = groupKey == "debuff" and af and af.DEBUFF_FILTER_ITEMS or af and af.BUFF_FILTER_ITEMS
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[groupKey == "debuff" and "debuff" or "buff"]
    local out = {}
    if type(source) == "table" then
        for i = 1, #source do
            local item = source[i]
            local value = CanonicalGroupFilterValue(item and (item.value or item.key), groupKey)
            if allowed[value] then
                out[#out + 1] = {
                    value = value,
                    text = GROUP_NATIVE_FILTER_LABELS[value] or item.text or item.label or value,
                    tooltipTitle = item.tooltipTitle,
                    tooltip = item.tooltip,
                    description = item.description,
                }
            end
        end
    end
    if #out > 0 then return out end
    if groupKey == "buff" then
        return VT(
            "ALL", "All Buffs",
            "MSUF_GROUP_HIGHLIGHTS_V1", "MSUF Highlights",
            "Player", "Cast by Me",
            "BigDefensive", "Big Defensive",
            "BigDefensivePlayer", "Big Defensive by Me",
            "ExternalDefensive", "External Defensive",
            "ExternalDefensivePlayer", "External Defensive by Me",
            "RaidInCombat", "Raid In Combat",
            "Raid", "Applicable by Me (Raid)",
            "RaidPlayer", "Applicable and Cast by Me"
        )
    end
    return VT(
        "ALL", "All Debuffs",
        "Player", "Cast by Me",
        "Raid", "Dispellable by Me (Raid)",
        "RaidInCombat", "Raid In Combat",
        "RAID_PLAYER_DISPELLABLE", "Dispellable by Group",
        "DISPELLABLE", "Any Dispel Type",
        "CROWD_CONTROL", "Crowd Control",
        "NonPlayer", "Non-Player Auras"
    )
end
local function BindGroupSwitch(ctx, parent, label, x, y, width, scope, groupKey, key, defaultValue, mode, afterSet)
    return BoundAura(ctx, parent, { "switch", nil, nil, { label, x, y, width },
        get = function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key]
            if value == nil and key == "showTooltip" then
                local root = GFReadRoot(scope)
                value = root and root.showTooltip
            end
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            GFWriteGroupValue(scope, groupKey, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end,
        meta = AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)) })
end
local function BindGroupRootSwitch(ctx, parent, label, x, y, width, scope, key, defaultValue, mode, afterSet)
    return BoundAura(ctx, parent, { "switch", nil, nil, { label, x, y, width },
        get = function()
            local root = GFReadRoot(scope)
            local value = root[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            GFWriteRootValue(scope, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end,
        meta = AuraControlMeta(ctx, "group-style.root." .. AuraCatalogToken(key)) })
end
local function BindGroupSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, groupKey, key, defaultValue, mode, afterSet, routeContract)
    return BoundAura(ctx, parent, { "slider", nil, nil, { label, minVal, maxVal, step, width }, { x, y, width },
        get = function()
            local group = GFReadGroup(scope, groupKey)
            return tonumber(group[key]) or defaultValue or 0
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            v = Round(v)
            GFWriteGroupValue(scope, groupKey, key, v, mode or "visual")
            if afterSet then afterSet(v) end
        end,
        meta = AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key), nil, routeContract) })
end
local function BindGroupDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, defaultValue, mode, afterSet, controlMeta)
    return BoundAura(ctx, parent, { "dropdown", nil, nil, { label, values, width }, { x, y, width },
        get = function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key] or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value, groupKey) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            return value
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            local value = v or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value, groupKey) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            GFWriteGroupValue(scope, groupKey, key, value, mode or "visual")
            if afterSet then afterSet(value) end
        end,
        meta = controlMeta or AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)) })
end
local function ReadGroupDebuffTypeBorderMode(scope, groupKey)
    local group = GFReadGroup(scope, groupKey or "debuff")
    if group.dispelBorderMode ~= nil then
        local mode = NormalizeDebuffTypeBorderMode(group.dispelBorderMode, "OFF")
        return (mode == "OFF" and group.showDispelBorder == true) and "SYMBOL" or mode
    end
    return group.showDispelBorder == true and "SYMBOL" or "OFF"
end
local function WriteGroupDebuffTypeBorderMode(scope, groupKey, value)
    value = NormalizeDebuffTypeBorderMode(value, "OFF")
    GFWriteGroupValues(scope, groupKey or "debuff", {
        dispelBorderMode = value,
        showDispelBorder = value ~= "OFF",
        showDispelSymbol = value == "SYMBOL",
    }, "visual")
end
-- The preview sibling loads after this file and reads the group config through
-- these; the page itself never needs them.
M.AuraGroupSettings = {
    GroupScopeKinds = GroupScopeKinds,
    GroupConf = GroupConf,
    GFReadRoot = GFReadRoot,
    GFReadGroup = GFReadGroup,
    ReadGroupDebuffTypeBorderMode = ReadGroupDebuffTypeBorderMode,
}
local function CreateMaxDurationWriter(scope, lane)
    return function(value)
        if type(Model.WriteGroupBlacklistMaxDuration) == "function"
        and Model.WriteGroupBlacklistMaxDuration(scope, lane, value) then
            QueueGroupScope(scope, "visual")
        end
    end
end

local function CreateHidePermanentWriter(scope, lane)
    return function(value)
        if type(Model.WriteGroupBlacklistHidePermanent) == "function"
        and Model.WriteGroupBlacklistHidePermanent(scope, lane, value) then
            QueueGroupScope(scope, "visual")
        end
    end
end

local function CreatePresetReaders(lane)
    local function PresetValues() return Model.GroupBlacklistPresetValues(lane) end
    -- Classic opens on the lane's default preset while the picked one is not in
    -- this lane's list (the list starts with a category header that has no value).
    local classicDefault = M.CLASSIC_AURA_FILTERS_REDUCED == true and (lane == "debuff" and "SATED" or "RAID_BUFFS") or nil
    local function CurrentPreset()
        local values = PresetValues()
        local key = M.auraBlacklistPreset
        if classicDefault then key = key or classicDefault end
        for i = 1, #values do if values[i].value == key then return key end end
        if classicDefault then return values[1] and values[1].value or classicDefault end
        return values[1] and values[1].value
    end
    local function PresetSpellValues() return Model.GroupBlacklistSpellValues(lane, CurrentPreset()) end
    return PresetValues, CurrentPreset, PresetSpellValues
end

-- The shared-font text color shortcut of a Group Style text section (no unit).
local function AttachGroupTextColorShortcut(section, opts, textSettings)
    AurasPage.AttachTextColorShortcut(section, nil, opts, textSettings)
end
-- The Group Style accordions share one record G (ctx, builder, scope, lane,
-- section base id, preview refresh and body width); each builds one section.
local function BuildGroupStyleBasics(G)
    local ctx, b, scope, lane, baseId, RefreshStylePreview, BodyWidth = G.ctx, G.b, G.scope, G.lane, G.baseId, G.RefreshStylePreview, G.BodyWidth
    local frameBasics = GroupSection(b, baseId .. "_frame_basics", "Basics", lane == "debuff" and 194 or 146, true)
    local basicsWidth = BodyWidth(frameBasics)
    local basicsGap = 10
    local basicsCol = max(180, floor((basicsWidth - 48 - basicsGap) / 2))
    local basicsRightX = 24 + basicsCol + basicsGap
    BindGroupSlider(ctx, frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, basicsCol,
        scope, lane, "iconZoom", 100, "visual", RefreshStylePreview, {
            searchSettingKeys = GroupSearchSettingKeys(scope, ".auras." .. lane .. ".iconZoom"),
        })
    AddAuraTooltipHelp(BindGroupSwitch(ctx, frameBasics, "Show Tooltip", basicsRightX, -48, basicsCol,
        scope, lane, "showTooltip", true, "visual", RefreshStylePreview))
    BindGroupSwitch(ctx, frameBasics, "Show Cooldown Text", 24, -106, basicsCol,
        scope, lane, "showCooldown", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, frameBasics, "Show Cooldown Swipe", basicsRightX, -106, basicsCol,
        scope, lane, "showCooldownSwipe", true, "visual", RefreshStylePreview)
    if lane == "debuff" then
        BoundAura(ctx, frameBasics, { "dropdown", nil, nil, { "Dispel-type Border",
            type(Model.DebuffTypeBorderModeValues) == "function"
                and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES, basicsCol }, { 24, -140, basicsCol },
            get = function() return ReadGroupDebuffTypeBorderMode(scope, lane) end,
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(v)
                WriteGroupDebuffTypeBorderMode(scope, lane, v)
                RefreshStylePreview()
            end,
            meta = AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".dispel-border-mode") })
    end
    return frameBasics
end
local function BuildGroupStyleCooldown(G)
    local ctx, b, scope, lane, baseId, RefreshStylePreview, BodyWidth = G.ctx, G.b, G.scope, G.lane, G.baseId, G.RefreshStylePreview, G.BodyWidth
    local cooldown = GroupSection(b, baseId .. "_cooldown", "Cooldown Text", 336, true)
    AttachGroupTextColorShortcut(cooldown, {
        title = M.Format("%s Cooldown Text Settings", Tr(LaneTitle(lane))),
        historyLabel = "Group aura cooldown text color",
        historySource = "menu:group-auras-cooldown-text-color",
    }, {
        colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
        colorTitle = M.Format("%s Cooldown Colors", Tr(LaneTitle(lane))),
        subtitle = "Group aura cooldown text follows the shared Fonts settings.",
    })
    local cw = BodyWidth(cooldown)
    -- Mode must be "auras", not "font": the DIRTY_FONT fast path refreshes the
    -- compiled spec's text domain in place and never recompiles the aura lanes,
    -- so the lane CooldownSize stays stale until an unrelated geometry write
    -- drops the cache (issue #64). "auras" invalidates the compiled spec and
    -- re-applies only the aura element.
    BindGroupSlider(ctx, cooldown, "Cooldown Font", 24, -56, 6, 24, 1, cw - 48, scope, lane, "cooldownSize", 8, "auras", RefreshStylePreview)
    BindGroupDropdown(ctx, cooldown, "Cooldown Anchor", 24, -112, GFAnchorValues(), cw - 48, scope, lane, "cooldownAnchor", "CENTER", "auras",
        RefreshStylePreview)
    local cooldownSmallW = max(120, floor((cw - 72) / 2))
    BindGroupSlider(ctx, cooldown, "Cooldown X", 24, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownX", 0, "auras", RefreshStylePreview)
    BindGroupSlider(ctx, cooldown, "Cooldown Y", 32 + cooldownSmallW, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownY", 0, "auras",
        RefreshStylePreview)
    local groupSwipeDirection = BoundAura(ctx, cooldown, { "dropdown", nil, nil,
        { "Swipe Direction", COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48 }, { 24, -230, cw - 48 },
        get = function()
            local group = GFReadGroup(scope, lane)
            return group.cooldownSwipeReverse == true and "REVERSE" or "NORMAL"
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            GFWriteGroupValue(scope, lane, "cooldownSwipeReverse", v == "REVERSE", "visual")
            RefreshStylePreview()
        end,
        meta = AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".cooldown-swipe-direction") })
    AddTooltip(groupSwipeDirection, "Cooldown swipe direction", "Reverses only the swipe overlay. Icon size and position stay unchanged.")
    local groupDecimal = BindGroupSlider(ctx, cooldown, "Decimals below sec", 24, -288, 0, 30, 1, cw - 48, scope, lane, "cooldownDecimalSeconds", 3, "visual",
        RefreshStylePreview)
    AddTooltip(groupDecimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and "
        .. "localized minutes above it. Set 0 for whole seconds only.")
    return cooldown
end
local function BuildGroupStyleDurationBar(G)
    local ctx, b, scope, lane, baseId, RefreshStylePreview, BodyWidth = G.ctx, G.b, G.scope, G.lane, G.baseId, G.RefreshStylePreview, G.BodyWidth
    local refreshDurationBarSummary
    local durationInline = (b.width or 720) >= 520
    local durationBar = GroupSection(b, baseId .. "_duration_bar", "Duration Bar", durationInline and 220 or 332, false)
    AurasPage.AttachDurationBarColor(durationBar, lane)
    local dbw = BodyWidth(durationBar)
    local durationChoiceWidth = durationInline and floor(((dbw - 48) - 20) / 3) or (dbw - 48)
    refreshDurationBarSummary = function()
        if not W.SetCollapsibleBadges then return end
        local group = GFReadGroup(scope, lane)
        local enabled = group.showDurationBar == true
        local display = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        local position = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        W.SetCollapsibleBadges(durationBar, {{
            text = enabled and (M.Format("%d px / %s / %s", Round(tonumber(group.durationBarHeight) or 2),
                ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, display, "Bar Only"), ChoiceLabel(DURATION_BAR_POSITION_VALUES, position, "Bottom"))) or "Off",
            kind = enabled and "accent" or "muted", showWhenClosed = true,
        }})
    end
    local function RefreshDurationBarPreviewAndSummary()
        RefreshStylePreview()
        refreshDurationBarSummary()
    end
    BindGroupSwitch(ctx, durationBar, "Show Duration Bar", 24, -48, dbw - 48, scope, lane, "showDurationBar", false, "visual",
        RefreshDurationBarPreviewAndSummary)
    BindGroupSlider(ctx, durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, scope, lane, "durationBarHeight", 2, "visual",
        RefreshDurationBarPreviewAndSummary)
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Display", 24, -162, DURATION_BAR_DISPLAY_VALUES, durationChoiceWidth, scope, lane, "durationBarDisplay",
        "BAR_ONLY", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar display", "Bar Only hides the aura icon. Icon + Bar keeps the icon and draws the duration bar on it.")
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Position", durationInline and (34 + durationChoiceWidth) or 24, durationInline and -162 or -220,
        DURATION_BAR_POSITION_VALUES, durationChoiceWidth, scope, lane, "durationBarPosition", "BOTTOM", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar position", "Places the duration bar at the top or bottom edge of the aura slot.")
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Fill Mode", durationInline and (44 + (durationChoiceWidth * 2)) or 24, durationInline and -162 or -278,
        DURATION_BAR_DIRECTION_VALUES, durationChoiceWidth, scope, lane, "durationBarDirection", "REMAINING", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar fill mode", "Remaining shrinks as the aura expires. Elapsed grows until the aura expires.")
    return durationBar, refreshDurationBarSummary
end
local function BuildGroupStyleStack(G)
    local ctx, b, scope, lane, baseId, RefreshStylePreview, BodyWidth = G.ctx, G.b, G.scope, G.lane, G.baseId, G.RefreshStylePreview, G.BodyWidth
    local stack = GroupSection(b, baseId .. "_stack", "Stack Count", 270, false)
    AttachGroupTextColorShortcut(stack, {
        title = M.Format("%s Stack Text Settings", Tr(LaneTitle(lane))),
        historyLabel = "Group aura stack text color",
        historySource = "menu:group-auras-stack-text-color",
    }, {
        colorReferences = { "font.global" },
        colorTitle = "Aura Stack Text Color",
        subtitle = "Group aura stack text follows the shared Fonts settings.",
    })
    local sw = BodyWidth(stack)
    BindGroupSwitch(ctx, stack, "Show Stack Count", 24, -56, sw - 48, scope, lane, "showStacks", true, "visual", RefreshStylePreview)
    -- "auras" for the same reason as Cooldown Font above: lane StackSize lives
    -- in the aura domain, which the "font" fast path never recompiles.
    BindGroupSlider(ctx, stack, "Stack Font", 24, -94, 6, 24, 1, sw - 48, scope, lane, "stackSize", 10, "auras", RefreshStylePreview)
    BindGroupDropdown(ctx, stack, "Stack Anchor", 24, -152, GFAnchorValues(), sw - 48, scope, lane, "stackAnchor", "BOTTOMRIGHT", "auras", RefreshStylePreview)
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindGroupSlider(ctx, stack, "Stack X", 24, -210, -40, 40, 1, stackSmallW, scope, lane, "stackX", 0, "auras", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Y", 32 + stackSmallW, -210, -40, 40, 1, stackSmallW, scope, lane, "stackY", 0, "auras", RefreshStylePreview)
    return stack
end
local function BuildGroupStyleLargeGroups(G)
    local largeGroups = GroupSection(G.b, G.baseId .. "_large_groups", "Large Groups", 112, false)
    local lgw = G.BodyWidth(largeGroups)
    BindGroupRootSwitch(G.ctx, largeGroups, "Scale Icons for Large Groups", 24, -48, lgw - 48, G.scope, "dynamicScale", false, "auras", G.RefreshStylePreview)
    W.Text(largeGroups, "85% above 15 members / 70% above 25", 24, -78, lgw - 48, T.colors.muted)
    return largeGroups
end
local function TrackGroupStyleBadges(G, frameBasics, cooldown, refreshDurationBarSummary, stack, largeGroups)
    local scope, lane = G.scope, G.lane
    M.TrackRefresh(G.ctx, function()
        if not W.SetCollapsibleBadges then return end
        local group = GFReadGroup(scope, lane)
        local root = GFReadRoot(scope)
        local ToggleBadge = W.ToggleBadge
        local cooldownEnabled = group.showCooldown ~= false
        local swipeEnabled = group.showCooldownSwipe ~= false
        local tooltipEnabled = group.showTooltip ~= false
        local frameBasicsBadges = {
            {
                text = M.Format("Zoom %d%%", Round(tonumber(group.iconZoom) or tonumber(root.iconZoom) or 100)),
                kind = "info", showWhenClosed = true,
            },
            ToggleBadge("Text", cooldownEnabled),
            ToggleBadge("Swipe", swipeEnabled),
            ToggleBadge("Tooltip", tooltipEnabled),
        }
        if lane == "debuff" then
            local borderMode = ReadGroupDebuffTypeBorderMode(scope, lane)
            frameBasicsBadges[#frameBasicsBadges + 1] = {
                text = M.Format("Border %s", ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode)),
                kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
            }
        end
        W.SetCollapsibleBadges(frameBasics, frameBasicsBadges)

        local decimal = Round(tonumber(group.cooldownDecimalSeconds) or 3)
        W.SetCollapsibleBadges(cooldown, {
            { text = cooldownEnabled and (M.Format("%d px / %s / %s", Round(tonumber(group.cooldownSize) or 8), AnchorLabel(group.cooldownAnchor or "CENTER"),
                Tr(group.cooldownSwipeReverse == true and "Reverse" or "Normal"))) or "Off", kind = cooldownEnabled and "accent" or "muted",
                showWhenClosed = true },
            { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
        })

        refreshDurationBarSummary()

        local stackEnabled = group.showStacks ~= false
        W.SetCollapsibleBadges(stack, {{
            text = stackEnabled and (M.Format("%d px / %s", Round(tonumber(group.stackSize) or 10), AnchorLabel(group.stackAnchor or "BOTTOMRIGHT"))) or "Off",
            kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
        }})

        W.SetCollapsibleBadges(largeGroups, {
            ToggleBadge("Large-group scaling", root.dynamicScale == true),
        })
    end)
end
local function BuildGroupStyle(ctx, b, scope, options)
    options = type(options) == "table" and options or nil
    local embeddedGroupPreview = options and options.embeddedGroupPreview == true
    local requestedLane = options and options.lane
    local lane = requestedLane == "externals" and "externals" or CurrentLane("auraStyleGFLane", "debuff")
    local refreshMiniPreview
    local function RefreshStylePreview()
        if refreshMiniPreview then
            AurasPage.RefreshMiniAuraPreviewNow(refreshMiniPreview)
        elseif embeddedGroupPreview then
            RefreshGFPreview()
        end
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local baseId = "aura_style_group_" .. tostring(scope or "group") .. "_" .. lane

    if not embeddedGroupPreview then
        refreshMiniPreview = AurasPage.BuildAuraStylePreviewWorkbench(ctx, b, scope, lane)
    end

    local G = { ctx = ctx, b = b, scope = scope, lane = lane, baseId = baseId,
        RefreshStylePreview = RefreshStylePreview, BodyWidth = BodyWidth }
    local frameBasics = BuildGroupStyleBasics(G)
    local cooldown = BuildGroupStyleCooldown(G)
    local durationBar, refreshDurationBarSummary = BuildGroupStyleDurationBar(G)
    local stack = BuildGroupStyleStack(G)
    local largeGroups = BuildGroupStyleLargeGroups(G)
    TrackGroupStyleBadges(G, frameBasics, cooldown, refreshDurationBarSummary, stack, largeGroups)
end

local function BuildGroupOrdering(ctx, b, scope, lane)
    lane = lane == "externals" and "externals" or (lane == "debuff" and "debuff" or "buff")
    local section = b:Section("Ordering", 156)
    local width = section and (section._msuf2Width or section.GetWidth and section:GetWidth()) or b.width or 720
    local function OrderingSearchRouteMetadata(suffix)
        return {
            searchSettingKeys = GroupSearchSettingKeys(scope, ".auras." .. lane .. "." .. suffix),
        }
    end
    local groupSortMethod = BindGroupDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(lane), width - 48,
        scope, lane, "sortMethod", "DEFAULT", "visual", nil,
        AuraControlMetaAtVisiblePath(ctx,
            "group-style.lane." .. AuraCatalogToken(lane) .. ".sortmethod",
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-method",
            nil, OrderingSearchRouteMetadata("sortMethod")))
    AddTooltip(groupSortMethod, "Aura sorting", "Only relevant sorting methods are shown for helpful and harmful auras.")
    local groupSortDirection = BoundAura(ctx, section, { "dropdown", nil, nil, { "Order", AURA_SORT_DIRECTION_VALUES, width - 48 }, { 24, -104, width - 48 },
        get = function()
            local group = GFReadGroup(scope, lane)
            return group.sortReverse == true and "REVERSE" or "NORMAL"
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(value)
            GFWriteGroupValue(scope, lane, "sortReverse", value == "REVERSE", "visual")
        end,
        meta = AuraControlMetaAtVisiblePath(ctx,
            "group-style.lane." .. AuraCatalogToken(lane) .. ".sort-direction",
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-direction",
            nil, OrderingSearchRouteMetadata("sortReverse")) })
    AddTooltip(groupSortDirection, "Aura sort order", "Reversed flips the complete priority order.")
end
local GFReadBlacklistCat = Model.ReadGroupBlacklistCategory

local function GFWriteBlacklistCat(scope, groupKey, catKey, value)
    if Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, value) then
        QueueGroupScope(scope, "visual")
    end
end
local function CategoryLabel(cat)
    if cat and cat.key == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    return (cat and cat.label) or (cat and cat.key) or ""
end
local function CreateHidePermanentReader(scope, lane)
    return function()
        return type(Model.ReadGroupBlacklistHidePermanent) == "function"
            and Model.ReadGroupBlacklistHidePermanent(scope, lane) == true
    end
end
local function CreateMaxDurationReader(scope, lane)
    return function()
        return type(Model.ReadGroupBlacklistMaxDuration) == "function"
            and Model.ReadGroupBlacklistMaxDuration(scope, lane) or 0
    end
end
-- Group blacklist actions keep their registered owner and fixed arguments.
local function OwnGroupAction(ctx, button, label, path, route)
    return Schema.Owned(RegisterAuraControl(ctx, button, label, "button", path, "action", route), "groups", "auras")
end
local function OwnGroupTextAction(ctx, button, input, label, path, route)
    return Schema.Owned(RegisterAuraTextAction(ctx, button, input, label, path, route), "groups", "auras")
end
-- The ephemeral Spell ID entry; state.value mirrors the typed text.
local function GroupManualInput(ctx, parent, label, x, y, width, metaPath)
    local state = { value = "" }
    local input = BoundAura(ctx, parent, { "textinput", nil, nil, { label, width }, { x, y, width },
        get = function() return state.value end,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value) state.value = value or "" end,
        meta = AuraControlMeta(ctx, metaPath, "ephemeral"), commitOnBlur = false, textAdapter = true })
    return input, state
end
-- The curated preset and spell selectors are ephemeral menu state.
local function GroupPresetDropdown(ctx, parent, x, y, width, PresetValues, CurrentPreset, metaPath)
    return BoundAura(ctx, parent, { "dropdown", nil, nil, { "Preset", PresetValues, width },
        { x, y, width }, get = CurrentPreset,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
            M.auraBlacklistPreset = value
            M.auraBlacklistSpell = nil
            QueueAurasPageRefresh(ctx, "group-aura-blacklist-preset")
        end,
        meta = AuraControlMeta(ctx, metaPath, "ephemeral") })
end
local function GroupSpellDropdown(ctx, parent, x, y, width, PresetSpellValues, CurrentSpell, metaPath)
    return BoundAura(ctx, parent, { "dropdown", nil, nil, { "Spell", PresetSpellValues, width },
        { x, y, width }, get = CurrentSpell,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value) M.auraBlacklistSpell = value end,
        meta = AuraControlMeta(ctx, metaPath, "ephemeral") })
end
-- BuildGroupFilters' card builders share one record F: ctx, scope, lane,
-- the section, its width and the lane's action path.
local function BuildGroupNativeFilterCard(F, fixedLane, originY)
    local ctx, scope, lane, section, w = F.ctx, F.scope, F.lane, F.section, F.w
    local laneText = lane == "buff" and "Buff" or "Debuff"
    local filterW = w - 48
    local filter = Card(section, M.Format("Native %s Filter", Tr(laneText)),
        M.Format("Filter token for %s group-frame %s.", Tr(ScopeLabel(scope)), Tr(LanePlural(lane))), 24, originY - 42, filterW, 296)
    W.LabelAt(filter, fixedLane and M.Format("%s Content", Tr(laneText)) or "Filter Type", 16, -72, fixedLane and 260 or 90, "GameFontNormalSmall",
        T.colors.accent)
    if not fixedLane then BuildLaneTabs(ctx, filter, "auraFilterLane", 112, -68, min(300, w - 180), "groups") end
    local dropdownW = min(360, max(240, floor((filterW - 48) * 0.55)))
    BindGroupDropdown(ctx, filter, M.Format("%s Filter", Tr(laneText)), 16, -142, GroupFilterValues(lane), dropdownW, scope, lane, "filterToken", "ALL",
        "visual")
    W.Text(filter, "Choose which auras Blizzard provides for this lane.", 40 + dropdownW, -142, max(220, filterW - dropdownW - 64), T.colors.muted)
    local hidePermanent = BoundAura(ctx, filter, { "switch", nil, nil, { "Hide permanent auras", 16, -192, dropdownW },
        get = CreateHidePermanentReader(scope, lane),
        set = CreateHidePermanentWriter(scope, lane),
        meta = AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".hide-permanent") })
    AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration. This native rule wins over SpellID blacklists and whitelists.")
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
        ConfigureMaxDurationSlider(BoundAura(ctx, filter, { "slider", nil, nil, { "Maximum duration", 0, 180, 1, filterW - 32 }, { 16, -230, filterW - 32 },
            get = CreateMaxDurationReader(scope, lane),
            set = CreateMaxDurationWriter(scope, lane),
            meta = AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".max-duration", nil, {}) }))
    end
end
local function BuildGroupCategoryBlacklist(F, meta, half, blacklistY, categoryHeight)
    local ctx, scope, lane, section, w = F.ctx, F.scope, F.lane, F.section, F.w
    local blacklist = Card(section, "Category Blacklist", nil, 24, blacklistY, w - 48, categoryHeight)
    W.LabelAt(blacklist, "Active", 16, -50, 70, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(blacklist, lane == "buff" and "Buff category blacklist" or "Debuff category blacklist", 86, -50, 260, "GameFontHighlightSmall", T.colors.text)
    W.Text(blacklist, NATIVE_EXACT_AURA_FILTERS_TEXT, 16, -72, w - 96, T.colors.muted)
    if #meta == 0 then
        W.Text(blacklist, "No public aura category data is loaded.", 16, -132, w - 96, T.colors.muted)
    end
    local catColW = max(230, floor((w - 104) / 2))
    local x2 = 16 + catColW + 24
    local startY = -152
    local categoryControls = {}
    for i = 1, #meta do
        local cat = meta[i]
        local col = i <= half and 0 or 1
        local row = col == 0 and (i - 1) or (i - half - 1)
        local tx = col == 0 and 16 or x2
        local toggle = BoundAura(ctx, blacklist, { "toggle", nil, nil, { CategoryLabel(cat), tx, startY - row * 30, catColW },
            get = function() return GFReadBlacklistCat(scope, lane, cat.key) end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
                set = function(v) GFWriteBlacklistCat(scope, lane, cat.key, v) end,
            meta = AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".category." .. AuraCatalogToken(cat.key)) })
        if cat.tooltip then AddTooltip(toggle, CategoryLabel(cat), cat.tooltip) end
        categoryControls[#categoryControls + 1] = toggle
    end
    return categoryControls
end
-- Debuff lane only: the free-form spell-ID entry was removed on purpose.
-- 12.x debuff data is secret at runtime, so only the curated never-secret
-- preset spells can actually match; entries come from the presets below.
local function BuildGroupManualBlacklist(F, direct)
    local ctx, scope, lane, w = F.ctx, F.scope, F.lane, F.w
    local directInputW = max(260, floor((w - 96) * 0.46))
    local directInput, inputState = GroupManualInput(ctx, direct, "Spell ID, spell link, or spell name", 16, -72, directInputW,
        "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".manual-input")
    local directAdd = ActionButton(direct, "Add", 90)
    directAdd:SetPoint("TOPLEFT", direct, "TOPLEFT", 28 + directInputW, -92)
    directAdd:SetScript("OnClick", function()
        local value = directInput and directInput.GetText and directInput:GetText() or inputState.value
        local changed = Model.AddGroupBlacklistSpell(scope, lane, value)
        if changed then
            if directInput and directInput.SetText then directInput:SetText("") end
            inputState.value = ""
            QueueGroupScope(scope, "visual")
            Repaint(ctx)
        end
        return changed and true or false
    end)
    OwnGroupTextAction(ctx, directAdd, directInput, "Add", F.groupActionPath .. ".add", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
    })
    local directRemove = ActionButton(direct, "Remove", 96)
    directRemove:SetPoint("LEFT", directAdd, "RIGHT", 8, 0)
    directRemove:SetScript("OnClick", function()
        local value = directInput and directInput.GetText and directInput:GetText() or inputState.value
        local changed = Model.RemoveGroupBlacklistSpell(scope, lane, value)
        if changed then
            QueueGroupScope(scope, "visual")
            Repaint(ctx)
        end
        return changed and true or false
    end)
    OwnGroupTextAction(ctx, directRemove, directInput, "Remove", F.groupActionPath .. ".remove", {
        actionKey = "aura_group_blacklist_remove_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
    })
    return directInput, directAdd, directRemove
end
local function BuildGroupPresetBlacklist(F, direct, directPresetY)
    local ctx, scope, lane, w = F.ctx, F.scope, F.lane, F.w
    local presetW = max(152, floor((w - 96) * 0.22))
    local spellW = max(210, floor((w - 96) * 0.30))
    local PresetValues, CurrentPreset, PresetSpellValues = CreatePresetReaders(lane)
    local preset = GroupPresetDropdown(ctx, direct, 16, directPresetY, presetW, PresetValues, CurrentPreset,
        "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".preset-selection")
    local spell = GroupSpellDropdown(ctx, direct, 26 + presetW, directPresetY, spellW, PresetSpellValues, function()
            local values, selected = PresetSpellValues(), M.auraBlacklistSpell
            for i = 1, #values do if values[i].value == selected then return selected end end
            return values[1] and values[1].value or nil
        end, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".spell-selection")
    local addSpell = ActionButton(direct, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", direct, "TOPLEFT", 36 + presetW + spellW, directPresetY - 22)
    addSpell:SetScript("OnClick", function()
        local values = PresetSpellValues()
        local spellID = M.auraBlacklistSpell or (values[1] and values[1].value)
        if Model.AddGroupBlacklistSpell(scope, lane, spellID, true) then
            QueueGroupScope(scope, "visual")
            Repaint(ctx)
        end
    end)
    OwnGroupAction(ctx, addSpell, "Add spell", F.groupActionPath .. ".add-preset-spell", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane, preset = true }, actionInputArg = "value",
    })
    local addSet = ActionButton(direct, "Add set", 88)
    addSet:SetPoint("LEFT", addSpell, "RIGHT", 8, 0)
    addSet:SetScript("OnClick", function()
        if Model.AddGroupBlacklistPresetGroup(scope, lane, CurrentPreset()) > 0 then
            QueueGroupScope(scope, "visual")
            Repaint(ctx)
        end
    end)
    OwnGroupAction(ctx, addSet, "Add set", F.groupActionPath .. ".add-preset-set", {
        actionKey = "aura_group_blacklist_add_preset", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "preset",
    })
    return { preset, spell, addSpell, addSet }
end
-- The blocked-spell rows: clicking one removes it. Returns the repaint.
local function BuildGroupBlacklistRows(F, direct, directPresetY)
    local ctx, scope, lane, w = F.ctx, F.scope, F.lane, F.w
    local prepared = W.Text(direct, "", 16, directPresetY - 84, w - 80, T.colors.accent)
    local empty = W.Text(direct, lane == "debuff" and "No blacklisted spells. Add one from the presets above."
        or "No blacklisted spells. Add one above or use a preset.", 16, directPresetY - 120, w - 80, T.colors.muted)
    local listScroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, direct))
    listScroll:SetPoint("TOPLEFT", direct, "TOPLEFT", 16, directPresetY - 110)
    listScroll:SetSize(w - 108, 48)
    local listChild = PixelLayoutRegion(CreateFrame("Frame", nil, listScroll))
    listChild:SetSize(w - 130, 48)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, direct, 28)
    local rows = {}
    local function EnsureRow(index)
        local row = rows[index]
        if row then return row end
        row = M.AuraControls.CompactSpellRow(listChild, index, function(self)
            if self._spellID and Model.RemoveGroupBlacklistSpell(scope, lane, self._spellID) then
                QueueGroupScope(scope, "visual")
                Repaint(ctx)
            end
        end)
        rows[index] = row
        return row
    end
    return function()
        local entries = type(Model.GroupBlacklistEntries) == "function" and Model.GroupBlacklistEntries(scope, lane) or {}
        T.SetTranslatedText(prepared, #entries == 1 and Tr("1 blocked spell · click an entry to remove")
            or M.Format("%d blocked spells · click an entry to remove", #entries))
        empty:SetShown(#entries == 0)
        listScroll:SetShown(#entries > 0)
        listChild:SetHeight(max(48, #entries * 24))
        for i = 1, max(#rows, #entries) do
            local row, entry = rows[i], entries[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.value
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.text:SetText(entry.text or entry.value)
                OwnGroupAction(ctx, row, entry.text or entry.value or "Blacklist entry",
                    "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".entry." .. AuraCatalogToken(entry.value) .. ".remove")
                row:Show()
            elseif row then
                row._spellID = nil
                row:Hide()
            end
        end
    end
end
local function BuildGroupDirectBlacklist(F, directY, categoryControls)
    local lane = F.lane
    local direct = Card(F.section, "Exact SpellID Blacklist", "Frame-specific exclusions for this Group Frame lane.", 24, directY, F.w - 48,
        lane == "debuff" and 246 or 300)
    local directInput, directAdd, directRemove
    if lane ~= "debuff" then directInput, directAdd, directRemove = BuildGroupManualBlacklist(F, direct) end
    local directPresetY = lane == "debuff" and -72 or -126
    local presetControls = BuildGroupPresetBlacklist(F, direct, directPresetY)
    local paintRows = BuildGroupBlacklistRows(F, direct, directPresetY)
    M.TrackRefresh(F.ctx, function()
        W.SetControlsEnabled(categoryControls, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        W.SetControlsEnabled(presetControls, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        if directInput then
            W.SetControlsEnabled({ directInput, directAdd, directRemove }, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        end
        paintRows()
    end)
end
local function BuildGroupFilters(ctx, b, scope, fixedLane, opts)
    opts = opts or {}
    local laneKey = fixedLane == "debuff" and "debuff" or (fixedLane == "buff" and "buff" or CurrentLane("auraFilterLane", "buff"))
    local embedded = opts.parent ~= nil
    local tool = embedded and tostring(opts.tool or "") or ""
    local showFilter = tool ~= "blacklist"
    local showBlacklist = tool ~= "filters"
    local af = AuraFilter()
    local meta = af and af.DECLASSIFIED_META
    if type(meta) ~= "table" then meta = {} end
    local half = ceil(#meta / 2)
    local categoryHeight = max(356, 180 + half * 30)
    local originY = embedded and (tonumber(opts.originY) or -400) or 0
    local blacklistY = showFilter and (originY - 362) or (originY - 42)
    local directY = blacklistY - categoryHeight - 24
    local standaloneHeight = max(930, abs(directY) + (laneKey == "debuff" and 270 or 324))
    local section = opts.parent or GroupSection(b, "group_aura_filters_" .. tostring(scope) .. "_" .. laneKey, "Group Frame Blizzard Filters & Lists",
        standaloneHeight, false)
    local w = section._msuf2Width or b.width or 720
    local lane = laneKey
    local F = { ctx = ctx, scope = scope, lane = lane, section = section, w = w,
        groupActionPath = "group-blacklist.scope." .. AuraCatalogToken(scope) .. ".lane." .. AuraCatalogToken(lane) }
    if embedded and tool == "" then
        W.DividerAt(section, originY - 4, 16, 16)
        W.LabelAt(section, "Blizzard Filters & Lists", 24, originY - 24, w - 48, "GameFontNormal", T.colors.accent)
    end
    if showFilter then BuildGroupNativeFilterCard(F, fixedLane, originY) end
    if not showBlacklist then return end
    local categoryControls = BuildGroupCategoryBlacklist(F, meta, half, blacklistY, categoryHeight)
    BuildGroupDirectBlacklist(F, directY, categoryControls)
end

local function BuildCompactGroupAuraFilters(ctx, b, scope, lane)
    local filtersTitle = lane == "debuff" and "Debuff Filters" or "Buff Filters"
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        -- Keep the supported ownership filters aligned with the unit lanes.
        local section = b:Section(filtersTitle, 118)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local gap = 12
        local colW = floor((inner - gap * 3) / 4)
        local onlyMine = BoundAura(ctx, section, { "switch", nil, nil, { "Only mine", 24, -42, colW },
            get = function()
                local group = GFReadGroup(scope, lane)
                return CanonicalGroupFilterValue(group.filterToken or "ALL", lane) == "Player"
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(value)
                GFWriteGroupValue(scope, lane, "filterToken", value == true and "Player" or "ALL", "auras")
            end,
            meta = AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.only-mine", nil, {
                searchSettingKeys = GroupSearchSettingKeys(scope,
                    ".auras." .. lane .. ".filterToken"),
            }) })
        M.AuraControls.AddCasterFilterTooltip(onlyMine, lane)
        if lane == "debuff" then
            BoundAura(ctx, section, { "switch", nil, nil, { "Non-Player Auras", 24 + 2 * (colW + gap), -42, colW },
                get = function()
                    return CanonicalGroupFilterValue(GFReadGroup(scope, lane).filterToken, lane) == "NonPlayer"
                end,
                customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(value)
                    GFWriteGroupValue(scope, lane, "filterToken", value == true and "NonPlayer" or "ALL", "auras")
                end,
                meta = AuraControlMeta(ctx, "group-workspace.lane.debuff.filters.non-player", nil, {
                    searchSettingKeys = GroupSearchSettingKeys(scope, ".auras.debuff.filterToken"),
                }) })
        end
        local hidePermanent = BoundAura(ctx, section, { "switch", nil, nil, { "Hide permanent", 24 + colW + gap, -42, colW },
            get = CreateHidePermanentReader(scope, lane),
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(value)
                if type(Model.WriteGroupBlacklistHidePermanent) == "function"
                    and Model.WriteGroupBlacklistHidePermanent(scope, lane, value) then
                    QueueGroupScope(scope, "auras")
                end
            end,
            meta = AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil, {
                searchSettingKeys = GroupSearchBlacklistSettingKeys(scope,
                    ".auras." .. lane .. ".blacklist.hidePermanent"),
            }) })
        AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration.")
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(onlyMine, true)
            W.SetControlEnabled(hidePermanent, true)
        end)
        return
    end
    local values = GroupFilterValues(lane)
    local optionRows = max(1, ceil(#values / 4))
    local sectionHeight = max(150, 104 + optionRows * 32)
        + (M.CLASSIC_AURA_FILTERS_REDUCED ~= true and 58 or 0)
    local section = b:Section(filtersTitle, sectionHeight)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    W.Text(section, "Show auras", 24, -42, colW * 2 + gap, T.colors.muted)
    local hidePermanent = BoundAura(ctx, section, { "switch", nil, nil, { "Hide permanent", 24 + 2 * (colW + gap), -42, colW * 2 + gap },
        get = CreateHidePermanentReader(scope, lane),
        set = CreateHidePermanentWriter(scope, lane),
        meta = AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil, {
            searchSettingKeys = GroupSearchBlacklistSettingKeys(scope,
                ".auras." .. lane .. ".blacklist.hidePermanent"),
        }) })
    AddTooltip(hidePermanent, "Hide permanent auras",
        "Excludes auras without a duration. MSUF Highlights intentionally uses its exact curated list instead so temporary Shroud membership remains visible.")
    local selectedFilterToken = CanonicalGroupFilterValue((GFReadGroup(scope, lane) or {}).filterToken or "ALL", lane)
    for i = 1, #values do
        local item = values[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        local control = BoundAura(ctx, section, { "switch", nil, nil, { item.text or item.value, 24 + col * (colW + gap), -78 - row * 32, colW },
            get = function()
                local group = GFReadGroup(scope, lane)
                return CanonicalGroupFilterValue(group.filterToken or "ALL", lane) == item.value
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(enabled)
                local group = GFReadGroup(scope, lane)
                local current = CanonicalGroupFilterValue(group.filterToken or "ALL", lane)
                local value = enabled and item.value or (current == item.value and "ALL" or current)
                GFWriteGroupValue(scope, lane, "filterToken", value, "visual")
                QueueAurasPageRefresh(ctx, "group-native-filter-choice")
            end,
            meta = AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.native." .. AuraCatalogToken(item.value), nil,
                item.value == selectedFilterToken and {
                    searchSettingKeys = GroupSearchSettingKeys(scope,
                        ".auras." .. lane .. ".filterToken"),
                } or nil) })
        AddTooltip(control, item.tooltipTitle or item.text or item.value,
            item.tooltip or item.description or "Only one filter can be active.")
    end
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
        ConfigureMaxDurationSlider(BoundAura(ctx, section, { "slider", nil, nil, { "Maximum duration", 0, 180, 1, inner }, { 24, -78 - optionRows * 32, inner },
            get = CreateMaxDurationReader(scope, lane),
            set = CreateMaxDurationWriter(scope, lane),
            meta = AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.max-duration", nil, {}) }))
    end
end

local function BuildCompactGroupAuraBlacklist(ctx, b, scope, lane)
    local isDebuff = lane == "debuff"
    -- The Classic aura backends re-apply only the Auras element for a blacklist
    -- change, the focused path their group filters use as well.
    local blacklistApplyMode = M.CLASSIC_AURA_FILTERS_REDUCED == true and "auras" or "visual"
    local section = b:Section(isDebuff and "Debuff Blacklist" or "Buff Blacklist", isDebuff and 502 or 528)
    local groupActionPath = "group-workspace.scope." .. AuraCatalogToken(scope)
        .. ".lane." .. AuraCatalogToken(lane) .. ".blacklist"
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    if not isDebuff then
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local input, inputState = GroupManualInput(ctx, section, "Enter buff Spell ID, link, or name", 24, -36, inputW,
            "group-workspace.lane.buff.blacklist.manual-input")
        local add = ActionButton(section, "Add custom buff", 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputState.value
            local changed = Model.AddGroupBlacklistSpell(scope, lane, value)
            if changed then
                QueueGroupScope(scope, blacklistApplyMode)
                Repaint(ctx)
            end
            if input and input.SetText then input:SetText("") end
            inputState.value = ""
            return changed and true or false
        end)
        OwnGroupTextAction(ctx, add, input, "Add custom buff", groupActionPath .. ".add", {
            actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
        })
        AddTooltip(add, "Add custom buff", "Adds one exact buff to this group's blacklist.")
    end
    local curatedOffset = isDebuff and 0 or -82
    local presetW = max(130, min(floor(inner * 0.62), inner - 138))
    local spellW = max(160, min(floor(inner * 0.68), inner - 108))
    local PresetValues, CurrentPreset, PresetSpellValues = CreatePresetReaders(lane)


    local function CurrentSpell()
        local values, selected = PresetSpellValues(), M.auraBlacklistSpell
        local entries = type(Model.GroupBlacklistEntries) == "function"
            and Model.GroupBlacklistEntries(scope, lane) or {}
        return M.AuraControls.FirstUnblockedSpell(values, selected, M.AuraControls.BlockedSet(entries))
    end
    GroupPresetDropdown(ctx, section, 24, -36 + curatedOffset, presetW, PresetValues, CurrentPreset,
        "group-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection")
    local addSet = ActionButton(section, "Add entire set", 126, "primary")
    addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
    addSet:SetScript("OnClick", function()
        local count = Model.AddGroupBlacklistPresetGroup(scope, lane, CurrentPreset())
        if count > 0 then
            M.auraBlacklistSpell = nil
            QueueGroupScope(scope, blacklistApplyMode)
            Repaint(ctx)
        end
        return count > 0
    end)
    OwnGroupAction(ctx, addSet, "Add entire set", groupActionPath .. ".add-preset-set", {
        actionKey = "aura_group_blacklist_add_preset", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "preset",
    })
    AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
    local selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
    GroupSpellDropdown(ctx, section, 24, -120 + curatedOffset, spellW, PresetSpellValues, CurrentSpell,
        "group-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection")
    local addSpell = ActionButton(section, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
    addSpell:SetScript("OnClick", function()
        local changed = Model.AddGroupBlacklistSpell(scope, lane, CurrentSpell(), true)
        if changed then
            M.auraBlacklistSpell = nil
            QueueGroupScope(scope, blacklistApplyMode)
            Repaint(ctx)
        end
        return changed and true or false
    end)
    OwnGroupAction(ctx, addSpell, "Add spell", groupActionPath .. ".add-preset-spell", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane, preset = true }, actionInputArg = "value",
    })
    AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    local prepared = W.Text(section, "", 24, -186 + curatedOffset, inner, T.colors.accent)
    local searchValue = ""
    local refreshList
    local searchInput = BoundAura(ctx, section, { "textinput", nil, nil, { "Search", inner }, { 24, -210 + curatedOffset, inner },
        get = function() return searchValue end,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
            searchValue = tostring(value or "")
            if refreshList then refreshList() end
        end,
        meta = AuraControlMeta(ctx, groupActionPath .. ".search", "ephemeral"), commitOnBlur = true, textAdapter = true })
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            searchValue = self.GetText and tostring(self:GetText() or "") or ""
            if refreshList then refreshList() end
        end)
    end
    local emptyText = isDebuff and "No blocked spells. Add one from the presets above."
        or "No blocked spells. Add one above or use a preset."
    local blockedList = M.AuraControls.BlockedSpellList(ctx, section, inner, curatedOffset, emptyText, { schemaScope = "groups",
        remove = function(spellID)
            if not Model.RemoveGroupBlacklistSpell(scope, lane, spellID) then return end
            QueueGroupScope(scope, blacklistApplyMode)
            Repaint(ctx)
        end,
        removePath = function(value) return groupActionPath .. ".entry." .. AuraCatalogToken(value) .. ".remove" end,
    })
    refreshList = function()
        local entries = type(Model.GroupBlacklistEntries) == "function" and Model.GroupBlacklistEntries(scope, lane) or {}
        local blocked = M.AuraControls.BlockedSet(entries)
        M.AuraControls.PaintPresetSummary(selectedSummary, addSet, addSpell, PresetSpellValues(), blocked, CurrentSpell)
        blockedList.Paint(entries, searchValue, prepared)
    end
    M.TrackRefresh(ctx, refreshList)
    if lane == "debuff" then
        W.Text(section,
            "Friendly debuffs: exact blocking is limited to Blizzard NeverSecret auras such as Sated/Exhaustion.",
            24, -458, inner, T.colors.muted)
    end
end

function M.BuildAuras3GroupLaneWorkspace(ctx, b, scope, lane, opts)
    lane = lane == "externals" and "externals" or (lane == "debuff" and "debuff" or "buff")
    if lane ~= "externals" then
        SetCurrentLane("auraStyleGFLane", lane)
        SetCurrentLane("auraFilterLane", lane)
    end
    if opts and opts.compact == true then
        if opts.tool == "style" then
            BuildGroupStyle(ctx, b, scope, { embeddedGroupPreview = true, lane = lane })
        elseif opts.tool == "behavior" then
            BuildGroupOrdering(ctx, b, scope, lane)
        elseif opts.tool == "blacklist" then
            BuildCompactGroupAuraBlacklist(ctx, b, scope, lane)
        else
            BuildCompactGroupAuraFilters(ctx, b, scope, lane)
        end
        return
    end
    BuildGroupFilters(ctx, b, scope, lane, opts)
end
