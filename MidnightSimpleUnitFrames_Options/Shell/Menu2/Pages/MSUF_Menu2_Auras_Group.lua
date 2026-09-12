local addonName, MSUF = ...
MSUF = MSUF or {}
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
local VT = M.ValueTextList
local CreateFrame = _G.CreateFrame
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local BindSwitch, BindToggle, BindSlider = M.BindSwitchAt, M.BindToggleAt, M.BindSliderAt
local BindDropdown, BindTextInput = M.BindDropdownAt, M.BindTextInputAt
local AURA_COOLDOWN_COLOR_REFERENCES = M.AuraSettings.AURA_COOLDOWN_COLOR_REFERENCES
local AURA_DURATION_BAR_COLOR_REFERENCES, AURA_SHARED_COLOR_NOTE = M.AuraSettings.AURA_DURATION_BAR_COLOR_REFERENCES, M.AuraSettings.AURA_SHARED_COLOR_NOTE
local AURA_SORT_DIRECTION_VALUES, ActionButton = M.AuraSettings.AURA_SORT_DIRECTION_VALUES, M.AuraControls.ActionButton
local AddAuraTooltipHelp, AddTooltip, AnchorLabel = M.AuraControls.AddAuraTooltipHelp, M.AuraControls.AddTooltip, M.AuraSettings.AnchorLabel
local AuraCatalogToken, AuraControlMeta = M.AuraControls.AuraCatalogToken, M.AuraControls.AuraControlMeta
local AuraControlMetaAtVisiblePath, AuraSortMethodValues = M.AuraControls.AuraControlMetaAtVisiblePath, M.AuraSettings.AuraSortMethodValues
local BuildLaneTabs, COOLDOWN_SWIPE_DIRECTION_VALUES, Card = M.AuraControls.BuildLaneTabs, M.AuraSettings.COOLDOWN_SWIPE_DIRECTION_VALUES, M.AuraControls.Card
local ChoiceLabel, ConfigureMaxDurationSlider, CurrentLane = M.AuraSettings.ChoiceLabel, M.AuraControls.ConfigureMaxDurationSlider, M.AuraSettings.CurrentLane
local DEBUFF_TYPE_BORDER_MODE_VALUES, DURATION_BAR_DIRECTION_VALUES = M.AuraSettings.DEBUFF_TYPE_BORDER_MODE_VALUES, M.AuraSettings.DURATION_BAR_DIRECTION_VALUES
local DURATION_BAR_DISPLAY_VALUES, DURATION_BAR_POSITION_VALUES = M.AuraSettings.DURATION_BAR_DISPLAY_VALUES, M.AuraSettings.DURATION_BAR_POSITION_VALUES
local GFAnchorValues, LanePlural, LaneTitle, MatchSuffix = M.AuraSettings.GFAnchorValues, M.AuraSettings.LanePlural, M.AuraSettings.LaneTitle, M.AuraSettings.MatchSuffix
local NATIVE_EXACT_AURA_FILTERS_ENABLED = M.AuraSettings.NATIVE_EXACT_AURA_FILTERS_ENABLED
local NATIVE_EXACT_AURA_FILTERS_TEXT, NormalizeAuraSortMethodForLane = M.AuraSettings.NATIVE_EXACT_AURA_FILTERS_TEXT, M.AuraSettings.NormalizeAuraSortMethodForLane
local NormalizeDebuffTypeBorderMode, QueueAurasPageRefresh = M.AuraSettings.NormalizeDebuffTypeBorderMode, M.AuraControls.QueueAurasPageRefresh
local Rebuild, RegisterAuraControl, RegisterAuraTextAction = M.AuraControls.Rebuild, M.AuraControls.RegisterAuraControl, M.AuraControls.RegisterAuraTextAction
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
        if canonical == "Player" or canonical:sub(-6) == "Player" then return "Player" end
        return "ALL"
    end
    local auraFilter = (type(MSUF.GF) == "table" and MSUF.GF.AuraFilter) or _G.MSUF_GF_AuraFilter
    local canonical
    if auraFilter and type(auraFilter.NormalizeFilterToken) == "function" then
        canonical = auraFilter.NormalizeFilterToken(lane, value)
    else
        local key = tostring(value or "ALL"):upper():gsub("[^A-Z0-9]", "")
        canonical = GROUP_NATIVE_FILTER_CANONICAL[key] or "ALL"
    end
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[lane == "debuff" and "debuff" or "buff"]
    return allowed[canonical] and canonical or "ALL"
end
local function GF()
    if type(GP.GF) == "function" then return GP.GF() end
    return MSUF and MSUF.GF
end
local function RefreshGFPreview()
    if type(GP.RefreshGFPreview) == "function" then GP.RefreshGFPreview() end
end
local function GroupScopeKinds(scope)
    if scope == "party" then return "party" end
    return "raid", "mythicraid"
end
local GroupAssistantSettingKeys = M.GroupAuraSettingKeys
local function GroupAssistantBlacklistSettingKeys(scope, suffix)
    suffix = tostring(suffix or "")
    if scope == "party" then return { "gf_party" .. suffix } end
    -- Raid/Mythic share this editor and backing blacklist operation, but the
    -- Assistant Registry intentionally exposes one canonical Raid list key.
    return { "gf_raid" .. suffix }
end
local function GroupConf(kind)
    if type(GP.Conf) == "function" then return GP.Conf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end
local function QueueGroupScope(scope, mode)
    local a, b = GroupScopeKinds(scope)
    if type(GP.QueueGF) == "function" then
        GP.QueueGF(a, mode or "visual")
        if b then GP.QueueGF(b, mode or "visual") end
    end
    -- Paint the menu preview from the just-written raw Aura style immediately.
    -- The coalesced group apply below still owns runtime recompilation.
    RefreshGFPreview()
end
local function GFAurasRoot(kind)
    local conf = GroupConf(kind)
    conf.auras = conf.auras or {}
    if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
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
local function AuraFilter()
    local gf = GF()
    return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
end
local function GroupFilterValues(groupKey)
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
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
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key]
            if value == nil and key == "showTooltip" then
                local root = GFReadRoot(scope)
                value = root and root.showTooltip
            end
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteGroupValue(scope, groupKey, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)))
end
local function BindGroupRootSwitch(ctx, parent, label, x, y, width, scope, key, defaultValue, mode, afterSet)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local root = GFReadRoot(scope)
            local value = root[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteRootValue(scope, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end,
        AuraControlMeta(ctx, "group-style.root." .. AuraCatalogToken(key)))
end
local function BindGroupSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, groupKey, key, defaultValue, mode, afterSet, assistantContract)
    return BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            return tonumber(group[key]) or defaultValue or 0
        end,
        function(v)
            v = Round(v)
            GFWriteGroupValue(scope, groupKey, key, v, mode or "visual")
            if afterSet then afterSet(v) end
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key), nil, assistantContract))
end
local function BindGroupDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, defaultValue, mode, afterSet, controlMeta)
    return BindDropdown(ctx, parent, label, x, y, values, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key] or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value, groupKey) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            return value
        end,
        function(v)
            local value = v or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value, groupKey) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            GFWriteGroupValue(scope, groupKey, key, value, mode or "visual")
            if afterSet then afterSet(value) end
        end,
        controlMeta or AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)))
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
    local function CurrentPreset()
        local values = PresetValues()
        local key = M.auraBlacklistPreset
        for i = 1, #values do if values[i].value == key then return key end end
        return values[1] and values[1].value
    end
    local function PresetSpellValues() return Model.GroupBlacklistSpellValues(lane, CurrentPreset()) end
    return PresetValues, CurrentPreset, PresetSpellValues
end

local function BuildGroupStyle(ctx, b, scope, options)
    options = type(options) == "table" and options or nil
    local embeddedGroupPreview = options and options.embeddedGroupPreview == true
    local requestedLane = options and options.lane
    local lane = requestedLane == "externals" and "externals" or CurrentLane("auraStyleGFLane", "debuff")
    local refreshMiniPreview
    local refreshDurationBarSummary
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

    local frameBasics = b:CollapsibleSection(baseId .. "_frame_basics", "Frame Basics", lane == "debuff" and 194 or 146, true)
    local basicsWidth = BodyWidth(frameBasics)
    local basicsGap = 10
    local basicsCol = max(180, floor((basicsWidth - 48 - basicsGap) / 2))
    local basicsRightX = 24 + basicsCol + basicsGap
    BindGroupSlider(ctx, frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, basicsCol,
        scope, lane, "iconZoom", 100, "visual", RefreshStylePreview, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "Icon Zoom targets the selected Group scope's selected Aura Style lane.",
            assistantSettingKeys = GroupAssistantSettingKeys(scope, ".auras." .. lane .. ".iconZoom"),
        })
    AddAuraTooltipHelp(BindGroupSwitch(ctx, frameBasics, "Show Tooltip", basicsRightX, -48, basicsCol,
        scope, lane, "showTooltip", true, "visual", RefreshStylePreview))
    BindGroupSwitch(ctx, frameBasics, "Show Cooldown Text", 24, -106, basicsCol,
        scope, lane, "showCooldown", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, frameBasics, "Show Cooldown Swipe", basicsRightX, -106, basicsCol,
        scope, lane, "showCooldownSwipe", true, "visual", RefreshStylePreview)
    if lane == "debuff" then
        BindDropdown(ctx, frameBasics, "Dispel-type Border", 24, -140,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            basicsCol,
            function() return ReadGroupDebuffTypeBorderMode(scope, lane) end,
            function(v)
                WriteGroupDebuffTypeBorderMode(scope, lane, v)
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".dispel-border-mode"))
    end

    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", "Cooldown Text", 336, true)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(cooldown, {
            title = M.Format("%s Cooldown Text Settings", Tr(LaneTitle(lane))),
            historyLabel = "Group aura cooldown text color",
            historySource = "menu:group-auras-cooldown-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                kind = "aura",
                colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                colorTitle = M.Format("%s Cooldown Colors", Tr(LaneTitle(lane))),
                subtitle = "Group aura cooldown text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local cw = BodyWidth(cooldown)
    -- Mode must be "auras", not "font": the DIRTY_FONT fast path refreshes the
    -- compiled spec's text domain in place and never recompiles the aura lanes,
    -- so the lane CooldownSize stays stale until an unrelated geometry write
    -- drops the cache (issue #64). "auras" invalidates the compiled spec and
    -- re-applies only the aura element.
    BindGroupSlider(ctx, cooldown, "Cooldown Font", 24, -56, 6, 24, 1, cw - 48, scope, lane, "cooldownSize", 8, "auras", RefreshStylePreview)
    BindGroupDropdown(ctx, cooldown, "Cooldown Anchor", 24, -112, GFAnchorValues(), cw - 48, scope, lane, "cooldownAnchor", "CENTER", "geometry", RefreshStylePreview)
    local cooldownSmallW = max(120, floor((cw - 72) / 2))
    BindGroupSlider(ctx, cooldown, "Cooldown X", 24, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, cooldown, "Cooldown Y", 32 + cooldownSmallW, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownY", 0, "geometry", RefreshStylePreview)
    local groupSwipeDirection = BindDropdown(ctx, cooldown, "Swipe Direction", 24, -230, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48,
        function()
            local group = GFReadGroup(scope, lane)
            return group.cooldownSwipeReverse == true and "REVERSE" or "NORMAL"
        end,
        function(v)
            GFWriteGroupValue(scope, lane, "cooldownSwipeReverse", v == "REVERSE", "visual")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".cooldown-swipe-direction"))
    AddTooltip(groupSwipeDirection, "Cooldown swipe direction", "Reverses only the swipe overlay. Icon size and position stay unchanged.")
    local groupDecimal = BindGroupSlider(ctx, cooldown, "Decimals below sec", 24, -288, 0, 30, 1, cw - 48, scope, lane, "cooldownDecimalSeconds", 3, "visual", RefreshStylePreview)
    AddTooltip(groupDecimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole seconds only.")

    local durationInline = (b.width or 720) >= 520
    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar", durationInline and 220 or 332, false)
    W.AttachContextColorReferences(durationBar, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = M.Format("%s Duration Bar Color", Tr(LaneTitle(lane))),
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
    local dbw = BodyWidth(durationBar)
    local durationChoiceWidth = durationInline and floor(((dbw - 48) - 20) / 3) or (dbw - 48)
    refreshDurationBarSummary = function()
        if not W.SetCollapsibleBadges then return end
        local group = GFReadGroup(scope, lane)
        local enabled = group.showDurationBar == true
        local display = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        local position = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        W.SetCollapsibleBadges(durationBar, {{
            text = enabled and (tostring(Round(tonumber(group.durationBarHeight) or 2)) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, display, "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, position, "Bottom")) or "Off",
            kind = enabled and "accent" or "muted", showWhenClosed = true,
        }})
    end
    local function RefreshDurationBarPreviewAndSummary()
        RefreshStylePreview()
        refreshDurationBarSummary()
    end
    BindGroupSwitch(ctx, durationBar, "Show Duration Bar", 24, -48, dbw - 48, scope, lane, "showDurationBar", false, "visual", RefreshDurationBarPreviewAndSummary)
    BindGroupSlider(ctx, durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, scope, lane, "durationBarHeight", 2, "visual", RefreshDurationBarPreviewAndSummary)
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Display", 24, -162, DURATION_BAR_DISPLAY_VALUES, durationChoiceWidth, scope, lane, "durationBarDisplay", "BAR_ONLY", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar display", "Bar Only hides the aura icon. Icon + Bar keeps the icon and draws the duration bar on it.")
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Position", durationInline and (34 + durationChoiceWidth) or 24, durationInline and -162 or -220, DURATION_BAR_POSITION_VALUES, durationChoiceWidth, scope, lane, "durationBarPosition", "BOTTOM", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar position", "Places the duration bar at the top or bottom edge of the aura slot.")
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Fill Mode", durationInline and (44 + (durationChoiceWidth * 2)) or 24, durationInline and -162 or -278, DURATION_BAR_DIRECTION_VALUES, durationChoiceWidth, scope, lane, "durationBarDirection", "REMAINING", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar fill mode", "Remaining shrinks as the aura expires. Elapsed grows until the aura expires.")

    local stack = b:CollapsibleSection(baseId .. "_stack", "Stack Count", 270, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(stack, {
            title = M.Format("%s Stack Text Settings", Tr(LaneTitle(lane))),
            historyLabel = "Group aura stack text color",
            historySource = "menu:group-auras-stack-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                kind = "aura",
                colorReferences = { "font.global" },
                colorTitle = "Aura Stack Text Color",
                subtitle = "Group aura stack text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local sw = BodyWidth(stack)
    BindGroupSwitch(ctx, stack, "Show Stack Count", 24, -56, sw - 48, scope, lane, "showStacks", true, "visual", RefreshStylePreview)
    -- "auras" for the same reason as Cooldown Font above: lane StackSize lives
    -- in the aura domain, which the "font" fast path never recompiles.
    BindGroupSlider(ctx, stack, "Stack Font", 24, -94, 6, 24, 1, sw - 48, scope, lane, "stackSize", 10, "auras", RefreshStylePreview)
    BindGroupDropdown(ctx, stack, "Stack Anchor", 24, -152, GFAnchorValues(), sw - 48, scope, lane, "stackAnchor", "BOTTOMRIGHT", "geometry", RefreshStylePreview)
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindGroupSlider(ctx, stack, "Stack X", 24, -210, -40, 40, 1, stackSmallW, scope, lane, "stackX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Y", 32 + stackSmallW, -210, -40, 40, 1, stackSmallW, scope, lane, "stackY", 0, "geometry", RefreshStylePreview)

    local largeGroups = b:CollapsibleSection(baseId .. "_large_groups", "Large Groups", 112, false)
    local lgw = BodyWidth(largeGroups)
    BindGroupRootSwitch(ctx, largeGroups, "Scale Icons for Large Groups", 24, -48, lgw - 48, scope, "dynamicScale", false, "geometry", RefreshStylePreview)
    W.Text(largeGroups, "85% above 15 members / 70% above 25", 24, -78, lgw - 48, T.colors.muted)

    M.TrackRefresh(ctx, function()
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
                text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
            }
        end
        W.SetCollapsibleBadges(frameBasics, frameBasicsBadges)

        local decimal = Round(tonumber(group.cooldownDecimalSeconds) or 3)
        W.SetCollapsibleBadges(cooldown, {
            { text = cooldownEnabled and (tostring(Round(tonumber(group.cooldownSize) or 8)) .. "px / " .. AnchorLabel(group.cooldownAnchor or "CENTER") .. " / " .. (group.cooldownSwipeReverse == true and "Reverse" or "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
            { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
        })

        refreshDurationBarSummary()

        local stackEnabled = group.showStacks ~= false
        W.SetCollapsibleBadges(stack, {{
            text = stackEnabled and (tostring(Round(tonumber(group.stackSize) or 10)) .. "px / " .. AnchorLabel(group.stackAnchor or "BOTTOMRIGHT")) or "Off",
            kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
        }})

        W.SetCollapsibleBadges(largeGroups, {
            ToggleBadge("Large-group scaling", root.dynamicScale == true),
        })
    end)
end

local function BuildGroupOrdering(ctx, b, scope, lane)
    lane = lane == "externals" and "externals" or (lane == "debuff" and "debuff" or "buff")
    local section = b:Section("Ordering", 156)
    local width = section and (section._msuf2Width or section.GetWidth and section:GetWidth()) or b.width or 720
    local function OrderingAssistantContract(suffix)
        return {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This ordering control targets the selected Group Aura lane; Raid and Mythic Raid share this workspace.",
            assistantSettingKeys = GroupAssistantSettingKeys(scope, ".auras." .. lane .. "." .. suffix),
        }
    end
    local groupSortMethod = BindGroupDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(lane), width - 48,
        scope, lane, "sortMethod", "DEFAULT", "visual", nil,
        AuraControlMetaAtVisiblePath(ctx,
            "group-style.lane." .. AuraCatalogToken(lane) .. ".sortmethod",
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-method",
            nil, OrderingAssistantContract("sortMethod")))
    AddTooltip(groupSortMethod, "Aura sorting", "Only relevant sorting methods are shown for helpful and harmful auras.")
    local groupSortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, width - 48,
        function()
            local group = GFReadGroup(scope, lane)
            return group.sortReverse == true and "REVERSE" or "NORMAL"
        end,
        function(value)
            GFWriteGroupValue(scope, lane, "sortReverse", value == "REVERSE", "visual")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "group-style.lane." .. AuraCatalogToken(lane) .. ".sort-direction",
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-direction",
            nil, OrderingAssistantContract("sortReverse")))
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
    local section = opts.parent or b:CollapsibleSection("group_aura_filters_" .. tostring(scope) .. "_" .. laneKey, "Group Frame Blizzard Filters & Lists", standaloneHeight, false)
    local w = section._msuf2Width or b.width or 720
    local lane = laneKey
    local groupActionPath = "group-blacklist.scope." .. AuraCatalogToken(scope)
        .. ".lane." .. AuraCatalogToken(lane)
    local laneText = lane == "buff" and "Buff" or "Debuff"
    local function ReadHidePermanent()
        return type(Model.ReadGroupBlacklistHidePermanent) == "function"
            and Model.ReadGroupBlacklistHidePermanent(scope, lane) == true
    end
    local WriteHidePermanent = CreateHidePermanentWriter(scope, lane)
    local function ReadMaxDuration()
        return type(Model.ReadGroupBlacklistMaxDuration) == "function"
            and Model.ReadGroupBlacklistMaxDuration(scope, lane) or 0
    end
    local WriteMaxDuration = CreateMaxDurationWriter(scope, lane)
    local function AddHidePermanentTooltip(control)
        AddTooltip(control, "Hide permanent auras", "Always excludes auras without a duration. This native rule wins over SpellID blacklists and whitelists.")
    end
    local filterW = w - 48
    if embedded and tool == "" then
        W.DividerAt(section, originY - 4, 16, 16)
        W.LabelAt(section, "Blizzard Filters & Lists", 24, originY - 24, w - 48, "GameFontNormal", T.colors.accent)
    end
    if showFilter then
        local filter = Card(section, M.Format("Native %s Filter", Tr(laneText)), M.Format("Filter token for %s group-frame %s.", Tr(ScopeLabel(scope)), Tr(LanePlural(lane))), 24, originY - 42, filterW, 296)
        W.LabelAt(filter, fixedLane and M.Format("%s Content", Tr(laneText)) or Tr("Filter Type"), 16, -72, fixedLane and 260 or 90, "GameFontNormalSmall", T.colors.accent)
        if not fixedLane then BuildLaneTabs(ctx, filter, "auraFilterLane", 112, -68, min(300, w - 180)) end
        local dropdownW = min(360, max(240, floor((filterW - 48) * 0.55)))
        BindGroupDropdown(ctx, filter, M.Format("%s Filter", Tr(laneText)), 16, -142, GroupFilterValues(lane), dropdownW, scope, lane, "filterToken", "ALL", "visual")
        W.Text(filter, "Choose which auras Blizzard provides for this lane.", 40 + dropdownW, -142, max(220, filterW - dropdownW - 64), T.colors.muted)
        local hidePermanent = BindSwitch(ctx, filter, "Hide permanent auras", 16, -192, dropdownW,
            ReadHidePermanent, WriteHidePermanent,
            AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".hide-permanent"))
        AddHidePermanentTooltip(hidePermanent)
        if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
            ConfigureMaxDurationSlider(BindSlider(ctx, filter, "Maximum duration", 16, -230, 0, 180, 1, filterW - 32,
                ReadMaxDuration, WriteMaxDuration,
                AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".max-duration", nil, {
                    assistantDisposition = "compound",
                    assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
                })))
        end
    end
    if not showBlacklist then return end
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
        local toggle = BindToggle(ctx, blacklist, CategoryLabel(cat), tx, startY - row * 30, catColW,
            function() return GFReadBlacklistCat(scope, lane, cat.key) end,
            function(v) GFWriteBlacklistCat(scope, lane, cat.key, v) end,
            AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".category." .. AuraCatalogToken(cat.key)))
        if cat.tooltip then AddTooltip(toggle, CategoryLabel(cat), cat.tooltip) end
        categoryControls[#categoryControls + 1] = toggle
    end
    local direct = Card(section, "Exact SpellID Blacklist", "Frame-specific exclusions for this Group Frame lane.", 24, directY, w - 48, lane == "debuff" and 246 or 300)
    -- Debuff lane only: the free-form spell-ID entry was removed on purpose.
    -- 12.x debuff data is secret at runtime, so only the curated never-secret
    -- preset spells can actually match; entries come from the presets below.
    local directInput, directAdd, directRemove
    if lane ~= "debuff" then
        local directInputValue = ""
        local directInputW = max(260, floor((w - 96) * 0.46))
        directInput = BindTextInput(ctx, direct, "Spell ID, spell link, or spell name", 16, -72, directInputW,
            function() return directInputValue end,
            function(value) directInputValue = value or "" end,
            false, AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".manual-input", "ephemeral"))
        directAdd = ActionButton(direct, "Add", 90)
        directAdd:SetPoint("TOPLEFT", direct, "TOPLEFT", 28 + directInputW, -92)
        directAdd:SetScript("OnClick", function()
            local value = directInput and directInput.GetText and directInput:GetText() or directInputValue
            local changed = Model.AddGroupBlacklistSpell(scope, lane, value)
            if changed then
                if directInput and directInput.SetText then directInput:SetText("") end
                directInputValue = ""
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, directAdd, directInput, "Add", groupActionPath .. ".add", {
            actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
        })
        directRemove = ActionButton(direct, "Remove", 96)
        directRemove:SetPoint("LEFT", directAdd, "RIGHT", 8, 0)
        directRemove:SetScript("OnClick", function()
            local value = directInput and directInput.GetText and directInput:GetText() or directInputValue
            local changed = Model.RemoveGroupBlacklistSpell(scope, lane, value)
            if changed then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, directRemove, directInput, "Remove", groupActionPath .. ".remove", {
            actionKey = "aura_group_blacklist_remove_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
        })
    end
    local presetW = max(152, floor((w - 96) * 0.22))
    local spellW = max(210, floor((w - 96) * 0.30))
    local PresetValues, CurrentPreset, PresetSpellValues = CreatePresetReaders(lane)


    local directPresetY = lane == "debuff" and -72 or -126
    local preset = W.Dropdown(direct, "Preset", PresetValues, presetW)
    W.MoveWidget(preset, direct, 16, directPresetY, presetW)
    M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value)
        M.auraBlacklistPreset = value
        M.auraBlacklistSpell = nil
        QueueAurasPageRefresh(ctx, "group-aura-blacklist-preset")
    end, AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".preset-selection", "ephemeral"))
    local spell = W.Dropdown(direct, "Spell", PresetSpellValues, spellW)
    W.MoveWidget(spell, direct, 26 + presetW, directPresetY, spellW)
    M.BindDropdownWidget(ctx, spell,
        function()
            local values, selected = PresetSpellValues(), M.auraBlacklistSpell
            for i = 1, #values do if values[i].value == selected then return selected end end
            return values[1] and values[1].value or nil
        end,
        function(value) M.auraBlacklistSpell = value end,
        AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".spell-selection", "ephemeral"))
    local addSpell = ActionButton(direct, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", direct, "TOPLEFT", 36 + presetW + spellW, directPresetY - 22)
    addSpell:SetScript("OnClick", function()
        local values = PresetSpellValues()
        local spellID = M.auraBlacklistSpell or (values[1] and values[1].value)
        if Model.AddGroupBlacklistSpell(scope, lane, spellID) then
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
    end)
    RegisterAuraControl(ctx, addSpell, "Add spell", "button", groupActionPath .. ".add-preset-spell", "action", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
    })
    local addSet = ActionButton(direct, "Add set", 88)
    addSet:SetPoint("LEFT", addSpell, "RIGHT", 8, 0)
    addSet:SetScript("OnClick", function()
        if Model.AddGroupBlacklistPresetGroup(scope, lane, CurrentPreset()) > 0 then
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
    end)
    RegisterAuraControl(ctx, addSet, "Add set", "button", groupActionPath .. ".add-preset-set", "action", {
        actionKey = "aura_group_blacklist_add_preset", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "preset",
    })
    local prepared = W.Text(direct, "", 16, directPresetY - 84, w - 80, T.colors.accent)
    local empty = W.Text(direct, lane == "debuff" and "No blacklisted spells. Add one from the presets above."
        or "No blacklisted spells. Add one above or use a preset.", 16, directPresetY - 120, w - 80, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, direct)
    listScroll:SetPoint("TOPLEFT", direct, "TOPLEFT", 16, directPresetY - 110)
    listScroll:SetSize(w - 108, 48)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(w - 130, 48)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, direct, 28)
    local rows = {}
    local function EnsureRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, listChild)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((index - 1) * 24))
        row:SetHeight(20)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.icon:SetSize(17, 17)
        row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row:SetScript("OnClick", function(self)
            if self._spellID and Model.RemoveGroupBlacklistSpell(scope, lane, self._spellID) then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
        end)
        rows[index] = row
        return row
    end
    M.TrackRefresh(ctx, function()
        W.SetControlsEnabled(categoryControls, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        W.SetControlsEnabled({ preset, spell, addSpell, addSet }, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        if directInput then
            W.SetControlsEnabled({ directInput, directAdd, directRemove }, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        end
        local entries = type(Model.GroupBlacklistEntries) == "function" and Model.GroupBlacklistEntries(scope, lane) or {}
        prepared:SetText(#entries == 1 and Tr("1 blocked spell · click an entry to remove")
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
                RegisterAuraControl(ctx, row, entry.text or entry.value or "Blacklist entry", "button",
                    "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".entry." .. AuraCatalogToken(entry.value) .. ".remove", "action")
                row:Show()
            elseif row then
                row._spellID = nil
                row:Hide()
            end
        end
    end)
end

local function BuildCompactGroupAuraFilters(ctx, b, scope, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local values = GroupFilterValues(lane)
    local optionRows = max(1, ceil(#values / 4))
    local sectionHeight = max(150, 104 + optionRows * 32)
        + (M.CLASSIC_AURA_FILTERS_REDUCED ~= true and 58 or 0)
    local section = b:Section(laneTitle .. " Filters", sectionHeight)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    W.Text(section, "Show auras", 24, -42, colW * 2 + gap, T.colors.muted)
    local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + 2 * (colW + gap), -42, colW * 2 + gap,
        function()
            return type(Model.ReadGroupBlacklistHidePermanent) == "function"
                and Model.ReadGroupBlacklistHidePermanent(scope, lane) == true
        end,
        CreateHidePermanentWriter(scope, lane),
        AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This control targets the selected Group scope and Aura lane.",
            assistantSettingKeys = GroupAssistantBlacklistSettingKeys(scope,
                ".auras." .. lane .. ".blacklist.hidePermanent"),
        }))
    AddTooltip(hidePermanent, "Hide permanent auras",
        "Excludes auras without a duration. MSUF Highlights intentionally uses its exact curated list instead so temporary Shroud membership remains visible.")
    local selectedFilterToken = CanonicalGroupFilterValue((GFReadGroup(scope, lane) or {}).filterToken or "ALL", lane)
    for i = 1, #values do
        local item = values[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        local control = BindSwitch(ctx, section, item.text or item.value, 24 + col * (colW + gap), -78 - row * 32, colW,
            function()
                local group = GFReadGroup(scope, lane)
                return CanonicalGroupFilterValue(group.filterToken or "ALL", lane) == item.value
            end,
            function(enabled)
                local group = GFReadGroup(scope, lane)
                local current = CanonicalGroupFilterValue(group.filterToken or "ALL", lane)
                local value = enabled and item.value or (current == item.value and "ALL" or current)
                GFWriteGroupValue(scope, lane, "filterToken", value, "visual")
                QueueAurasPageRefresh(ctx, "group-native-filter-choice")
            end,
            AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.native." .. AuraCatalogToken(item.value), nil,
                item.value == selectedFilterToken and {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "The active native-filter choice represents Filter Token for the selected Group scope and Aura lane.",
                    assistantSettingKeys = GroupAssistantSettingKeys(scope,
                        ".auras." .. lane .. ".filterToken"),
                } or nil))
        AddTooltip(control, item.tooltipTitle or item.text or item.value,
            item.tooltip or item.description or "Only one filter can be active.")
    end
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
        ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -78 - optionRows * 32, 0, 180, 1, inner,
            function()
                return type(Model.ReadGroupBlacklistMaxDuration) == "function"
                    and Model.ReadGroupBlacklistMaxDuration(scope, lane) or 0
            end,
            CreateMaxDurationWriter(scope, lane),
            AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
    end
end

local function BuildCompactGroupAuraBlacklist(ctx, b, scope, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local isDebuff = lane == "debuff"
    local section = b:Section(laneTitle .. " Blacklist", isDebuff and 502 or 528)
    local groupActionPath = "group-workspace.scope." .. AuraCatalogToken(scope)
        .. ".lane." .. AuraCatalogToken(lane) .. ".blacklist"
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    if not isDebuff then
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local input = BindTextInput(ctx, section, "Enter buff Spell ID, link, or name", 24, -36, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "group-workspace.lane.buff.blacklist.manual-input", "ephemeral"))
        local add = ActionButton(section, "Add custom buff", 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local changed = Model.AddGroupBlacklistSpell(scope, lane, value)
            if changed then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, "Add custom buff", groupActionPath .. ".add", {
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
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        for i = 1, #values do
            if values[i].value == selected and not blocked[tostring(selected)] then return selected end
        end
        for i = 1, #values do
            if values[i].value ~= nil and not blocked[tostring(values[i].value)] then return values[i].value end
        end
        return nil
    end
    local preset = W.Dropdown(section, "Preset", PresetValues, presetW)
    W.MoveWidget(preset, section, 24, -36 + curatedOffset, presetW)
    M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value)
        M.auraBlacklistPreset = value
        M.auraBlacklistSpell = nil
        QueueAurasPageRefresh(ctx, "group-aura-blacklist-preset")
    end, AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection", "ephemeral"))
    local addSet = ActionButton(section, "Add entire set", 126, "primary")
    addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
    addSet:SetScript("OnClick", function()
        local count = Model.AddGroupBlacklistPresetGroup(scope, lane, CurrentPreset())
        if count > 0 then
            M.auraBlacklistSpell = nil
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
        return count > 0
    end)
    RegisterAuraControl(ctx, addSet, "Add entire set", "button", groupActionPath .. ".add-preset-set", "action", {
        actionKey = "aura_group_blacklist_add_preset", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "preset",
    })
    AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
    local selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
    local spell = W.Dropdown(section, "Spell", PresetSpellValues, spellW)
    W.MoveWidget(spell, section, 24, -120 + curatedOffset, spellW)
    M.BindDropdownWidget(ctx, spell,
        CurrentSpell,
        function(value) M.auraBlacklistSpell = value end,
        AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection", "ephemeral"))
    local addSpell = ActionButton(section, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
    addSpell:SetScript("OnClick", function()
        local changed = Model.AddGroupBlacklistSpell(scope, lane, CurrentSpell())
        if changed then
            M.auraBlacklistSpell = nil
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
        return changed and true or false
    end)
    RegisterAuraControl(ctx, addSpell, "Add spell", "button", groupActionPath .. ".add-preset-spell", "action", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
    })
    AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    local prepared = W.Text(section, "", 24, -186 + curatedOffset, inner, T.colors.accent)
    local searchValue = ""
    local refreshList
    local searchInput = BindTextInput(ctx, section, "Search", 24, -210 + curatedOffset, inner,
        function() return searchValue end,
        function(value)
            searchValue = tostring(value or "")
            if refreshList then refreshList() end
        end,
        true, AuraControlMeta(ctx, groupActionPath .. ".search", "ephemeral"))
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            searchValue = self.GetText and tostring(self:GetText() or "") or ""
            if refreshList then refreshList() end
        end)
    end
    local emptyText = isDebuff and "No blocked spells. Add one from the presets above."
        or "No blocked spells. Add one above or use a preset."
    local empty = W.Text(section, emptyText, 24, -284 + curatedOffset, inner, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, section)
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -260 + curatedOffset)
    listScroll:SetSize(inner - 20, 150)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(inner - 44, 150)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, 44)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, listChild)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
        row:SetHeight(40)
        if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.icon:SetSize(28, 28)
        row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
        row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
        row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
        row.remove = ActionButton(row, "Remove", 80)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.remove:SetScript("OnClick", function()
            if row._spellID and Model.RemoveGroupBlacklistSpell(scope, lane, row._spellID) then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
        end)
        AddTooltip(row.remove, "Remove from blacklist", "Stops blocking this aura.")
        rows[i] = row
        return row
    end
    refreshList = function()
        local entries = type(Model.GroupBlacklistEntries) == "function" and Model.GroupBlacklistEntries(scope, lane) or {}
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        local setSpells = PresetSpellValues()
        local missing = 0
        for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
        selectedSummary:SetText(missing == 0
            and M.Format("%d spells in this set - all already blocked", #setSpells)
            or M.Format("%d spells in this set - %d can still be added", #setSpells, missing))
        W.SetControlEnabled(addSet, missing > 0)
        local selectedSpell = CurrentSpell()
        W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
        local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local visible = {}
        for i = 1, #entries do
            local entry = entries[i]
            local haystack = (tostring(entry.text or "") .. " "
                .. tostring(entry.spellID or entry.value or "")):lower()
            if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
        end
        prepared:SetText(M.Format("Blocked spells (%d)", #entries) .. MatchSuffix(query, #visible))
        empty:SetText(#entries == 0 and Tr(emptyText) or M.Format(Tr("No results for \"%s\"."), query))
        empty:SetShown(#visible == 0)
        listScroll:SetShown(#visible > 0)
        listChild:SetHeight(max(150, #visible * 44))
        for i = 1, max(#rows, #visible) do
            local row, entry = rows[i], visible[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.value
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local name = tostring(entry.text or entry.value or "Spell"):gsub("%s*%(#%d+%)$", "")
                row.name:SetText(name)
                row.id:SetText(entry.spellID and (tostring("Spell ID ") .. tostring(entry.spellID)) or tostring(entry.value or ""))
                RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                    groupActionPath .. ".entry." .. AuraCatalogToken(entry.value) .. ".remove", "action")
                row:Show()
            elseif row then row._spellID = nil; row:Hide() end
        end
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
