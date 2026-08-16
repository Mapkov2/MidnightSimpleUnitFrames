local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group Status & Indicators page.
-- Builds party/raid status icon, placed indicator, frame effect, and spell-indicator controls.
-- Runtime indicator dispatch remains in the GroupFrames engine.
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local Tr = M.TranslateText or M.Tr or function(text) return text end
local floor = math.floor
local max = math.max
local min = math.min
local table_concat = table.concat
local C_Timer = M.MenuTimer or _G.C_Timer
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local VT = M.ValueTextList
local WHITE_RGB = { 1, 1, 1 }
local SPELL_INDICATORS_121_PTR_DISABLED = false
local issecretvalue = _G.issecretvalue or function(_) return false end
local STATUS_ICON_RESET_FIELDS = M.WordList "size anchor x y layer iconStyle customIcon"
local AURA_ANCHORS, STATUS_ICON_ANCHORS, GF_STATUS_ICON_SPECS, GF_STATUS_ICON_VALUES, PLACED_INDICATOR_TYPES, FRAME_EFFECT_TYPES, ICON_EFFECT_TYPES, SPELL_GROWTH_VALUES, CI_SLOT_VALUES, CI_SLOT_DEFAULTS = M.PickDefaults(GP, [[AURA_ANCHORS STATUS_ICON_ANCHORS GF_STATUS_ICON_SPECS GF_STATUS_ICON_VALUES PLACED_INDICATOR_TYPES FRAME_EFFECT_TYPES ICON_EFFECT_TYPES SPELL_GROWTH_VALUES CI_SLOT_VALUES CI_SLOT_DEFAULTS]])
local GF, RefreshGFPreview, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, ScopeDropdown, ScopeSlider, ScopeColor, SpellIndicators, IconStyleValues, CurrentGFStatusSpec, QueueSpellIndicators, SpellSpecValues, SpellTrackedSpecValues, IsAllSpecsSpellSpec, CurrentSpellMultiSpec, EffectiveSpellSpec, SpellAuraValues, SetCurrentSpellAura, ClearCurrentSpellAura, CurrentSpellAura, CurrentSpellConfig, PlacedConfig, FrameEffectConfig, CICategoryValues, CIFilterValues, CIModeValues, CurrentCISlot, CICustomConfig, BindNestedSlider, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge, OptionText, ControlMeta, RegisterControl = M.Pick(GP, [[GF RefreshGFPreview Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle ScopeDropdown ScopeSlider ScopeColor SpellIndicators IconStyleValues CurrentGFStatusSpec QueueSpellIndicators SpellSpecValues SpellTrackedSpecValues IsAllSpecsSpellSpec CurrentSpellMultiSpec EffectiveSpellSpec SpellAuraValues SetCurrentSpellAura ClearCurrentSpellAura CurrentSpellAura CurrentSpellConfig PlacedConfig FrameEffectConfig CICategoryValues CIFilterValues CIModeValues CurrentCISlot CICustomConfig BindNestedSlider SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus TrackSectionRefresh OnOffBadge OptionText ControlMeta RegisterControl]])
OnOffBadge = OnOffBadge or M.OnOffBadge
OptionText = OptionText or M.OptionText
local function ResolvePlacedSpellIndicatorControlVisibility(placed)
    local placedType = type(placed) == "table" and tostring(placed.type or "none"):lower() or "none"
    local iconSelected = placedType == "icon"
    local barSelected = placedType == "bar"
    return iconSelected, barSelected, barSelected and placed.barShowTimer == true
end
SetCurrentSpellAura = SetCurrentSpellAura or function(kind, auraName)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    M.gfSpellIndicatorSelection[kind] = auraName or ""
end
ClearCurrentSpellAura = ClearCurrentSpellAura or function(kind)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    M.gfSpellIndicatorSelection[kind] = nil
end
local function IconPackValues()
    -- Style options come from the group runtime when available, with a small fallback for
    -- early load or test contexts where the runtime has not registered styles yet.
    -- No "follow global style" entry: every indicator picks its own style, and the Midnight
    -- art of each pack is listed as its own entry instead of a separate toggle.
    local gf = GF()
    if gf and type(gf.GetIconStyleItems) == "function" then return gf.GetIconStyleItems(false, true) end
    local values = {}
    local src = type(IconStyleValues) == "function" and IconStyleValues() or {}
    for i = 1, #src do
        local item = src[i]
        if type(item) == "table" then
            values[#values + 1] = {
                value = item.value or item.key,
                text = item.text or item.label or item.value or item.key,
            }
        end
    end
    return values
end
local STATUS_ICON_TAB_VALUES = VT("basic", "Basic", "advanced", "Advanced")
local GROUP_NUMBER_STYLES = VT("PAREN", "(2)", "BRACKET", "[2]", "NONE", "2")
local function SetManyEnabled(enabled, ...)
    for i = 1, select("#", ...) do SetOptionEnabled(select(i, ...), enabled) end
end
local function StepMeta(ctx, path, step)
    local meta = ControlMeta(ctx, path)
    meta.step, meta.roundStep = step, true
    if path == "spell.icon_zoom" or path == "spell.icon_scale" then
        local scope = CurrentScope()
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = path == "spell.icon_scale"
            and "Icon Scale targets Spell Indicator geometry in the selected Group scope."
            or "Icon Zoom targets Spell Indicator icons in the selected Group scope."
        local setting = path == "spell.icon_scale" and "iconScale" or "iconZoom"
        if scope == "party" then
            meta.assistantSettingKeys = { "gf_party.spellIndicators." .. setting }
        else
            meta.assistantSettingKeys = {
                "gf_raid.spellIndicators." .. setting,
                "gf_mythicraid.spellIndicators." .. setting,
            }
        end
    end
    return meta
end

local CUSTOM_BUFF_LIMIT = 10
local CUSTOM_BUFF_COLOR = { 0.45, 0.85, 1.00 }

local function AddCustomBuffSpellID(out, seen, value)
    if issecretvalue(value) == true then return 0 end
    local id = tonumber(value)
    if not id then return 0 end
    id = floor(id + 0.5)
    if id <= 0 or seen[id] then return 0 end
    seen[id] = true
    out[#out + 1] = id
    return 1
end

local function CustomBuffSpellIDs(value)
    local out, seen = {}, {}
    if issecretvalue(value) == true then return nil end
    if type(value) == "number" then
        AddCustomBuffSpellID(out, seen, value)
        return #out > 0 and out or nil
    end
    value = tostring(value or "")
    -- Extract the actual ID from spell links first. Do not treat link payload,
    -- color codes, ranks, or digits inside a spell name as additional IDs.
    for token in value:gmatch("|Hspell:(%d+)") do AddCustomBuffSpellID(out, seen, token) end
    for token in value:gmatch("spell:(%d+)") do AddCustomBuffSpellID(out, seen, token) end
    local plain = value
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|Hspell:%d+[^|]*|h.-|h", " ")
        :gsub("spell:%d+", " ")
        :gsub("|r", "")
    if plain:match("^%s*[%d,%s;]+%s*$") then
        for token in plain:gmatch("%d+") do AddCustomBuffSpellID(out, seen, token) end
    end
    return #out > 0 and out or nil
end

local function ResolveCustomBuffSpellIDs(value)
    if issecretvalue(value) == true then return nil end
    local ids = CustomBuffSpellIDs(value)
    if ids then return ids end
    local identifier = tostring(value or ""):match("^%s*(.-)%s*$")
    if identifier == "" then return nil end
    local cs = _G.C_Spell
    local resolver = cs and cs.GetSpellIDForSpellIdentifier
    if type(resolver) ~= "function" then return nil end
    local ok, spellID = pcall(resolver, identifier)
    if not ok then return nil end
    if issecretvalue(spellID) == true then return nil end
    local out, seen = {}, {}
    AddCustomBuffSpellID(out, seen, spellID)
    return #out > 0 and out or nil
end

local function RequestCustomBuffSpellData(spellIDs)
    local request = _G.C_Spell and _G.C_Spell.RequestLoadSpellData
    if type(request) ~= "function" or type(spellIDs) ~= "table" then return end
    for i = 1, #spellIDs do request(spellIDs[i]) end
end

local function CustomBuffSpellIDListText(ids)
    if type(ids) ~= "table" or #ids == 0 then return "" end
    local parts = {}
    for i = 1, #ids do parts[i] = tostring(ids[i]) end
    return table_concat(parts, ",")
end

local function CustomBuffSpellID(value)
    local ids = CustomBuffSpellIDs(value)
    return ids and ids[1] or nil
end

local function CustomBuffInfo(spellID)
    local name, icon
    local cs = _G.C_Spell
    if cs and type(cs.GetSpellInfo) == "function" then
        local info = cs.GetSpellInfo(spellID)
        if issecretvalue(info) ~= true and type(info) == "table" then
            name = info.name
            icon = info.iconID or info.iconFileID or info.icon
        elseif issecretvalue(info) ~= true and type(info) == "string" then
            name = info
        end
    end
    if issecretvalue(name) == true then name = nil end
    if issecretvalue(icon) == true then icon = nil end
    if not name and cs and type(cs.GetSpellName) == "function" then name = cs.GetSpellName(spellID) end
    if issecretvalue(name) == true then name = nil end
    if not icon and cs and type(cs.GetSpellTexture) == "function" then icon = cs.GetSpellTexture(spellID) end
    if issecretvalue(icon) == true then icon = nil end
    if (not name or not icon) and type(_G.GetSpellInfo) == "function" then
        local n, _, tex = _G.GetSpellInfo(spellID)
        if issecretvalue(n) ~= true then name = name or n end
        if issecretvalue(tex) ~= true then icon = icon or tex end
    end
    return name or ("Buff " .. tostring(spellID)), icon or 136243
end

local function SuggestedActivePlayerAuraID(spellIDs)
    if type(spellIDs) ~= "table" or #spellIDs ~= 1 then return nil end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    local enteredID = spellIDs[1]
    local spellName = CustomBuffInfo(enteredID)
    if issecretvalue(spellName) == true or type(spellName) ~= "string" or spellName == "" or spellName == ("Buff " .. tostring(enteredID)) then return nil end
    local getByName = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataBySpellName
    if type(getByName) ~= "function" then return nil end
    local ok, aura = pcall(getByName, "player", spellName, "HELPFUL")
    if not ok then return nil end
    if issecretvalue(aura) == true then return nil end
    if aura == nil or type(aura) ~= "table" then return nil end
    local auraSpellID = aura.spellId
    if issecretvalue(auraSpellID) == true then return nil end
    auraSpellID = tonumber(auraSpellID)
    if not auraSpellID then return nil end
    auraSpellID = floor(auraSpellID + 0.5)
    if auraSpellID <= 0 or auraSpellID == enteredID then return nil end
    return auraSpellID, spellName
end

local function IsCustomBuffEntry(auraName, entry)
    return (type(entry) == "table" and entry.custom == true) or CustomBuffSpellID(auraName) ~= nil
end

local function DefaultCustomBuffPlaced(index)
    index = max(1, min(CUSTOM_BUFF_LIMIT, tonumber(index) or 1))
    local col = (index - 1) % 5
    local row = floor((index - 1) / 5)
    return {
        type = "icon",
        anchor = "TOPLEFT",
        x = 1 + col * 22,
        y = -24 - row * 22,
        size = 18,
        showCooldownSwipe = true,
        showCooldown = true,
    }
end

local function BuildIndicatorsSection(ctx, b)
    local indicators = b:CollapsibleSection("indicators", "Frame Indicators", 710, true)
    local indicatorsW = indicators._msuf2Width or ctx.width or 720
    local cardGap = 16
    local leftX = 20
    local innerW = max(320, indicatorsW - 40)
    local leftW = floor((innerW - cardGap) * 0.48)
    local rightX = leftX + leftW + cardGap
    local rightW = innerW - leftW - cardGap
    local function AddScopeSlider(list, parent, label, minValue, maxValue, step, width, key, defaultValue, mode, y, moveWidth)
        local control = ScopeSlider(ctx, parent, label, minValue, maxValue, step, width, key, defaultValue, mode, 16, y, moveWidth or (width - 58))
        M.AppendValues(list, control); return control
    end
    local function AddScopeDropdown(list, parent, label, values, width, key, defaultValue, mode, y)
        local control = ScopeDropdown(ctx, parent, label, values, width, key, defaultValue, mode, 16, y, width - 32)
        M.AppendValues(list, control); return control
    end
    local highlightCard = W.ControlCard(indicators, "Target Highlight",
        "Configure target highlighting in Appearance > Miscellaneous > Frame Highlights.",
        leftX, -38, innerW, 92)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(highlightCard, { "group.target" }, {
            title = "Target Highlight Color",
            note = "Shared by Party, Raid and Mythic Raid.",
            historySource = "menu:group-target-highlight-color",
            offsetX = -76,
        })
    end
    local function OpenFrameHighlights()
        _G.MSUF_EM2_MenuFocusRequest = {
            pageKey = "opt_misc",
            sectionId = "misc_mouseover_highlight",
            explicit = true,
            consumed = false,
        }
        if M.SelectPage and M.SelectPage("opt_misc") == false then
            _G.MSUF_EM2_MenuFocusRequest = nil
        end
    end
    local openHighlights = T.Button(highlightCard, "Open Highlights", 132, 22)
    openHighlights:SetPoint("TOPRIGHT", highlightCard, "TOPRIGHT", -16, -56)
    T.CenterButtonLabel(openHighlights)
    if M.AddTooltip then
        M.AddTooltip(openHighlights, "Open Highlights", "Appearance > Miscellaneous > Frame Highlights", { hook = true })
    end
    openHighlights:SetScript("OnClick", OpenFrameHighlights)
    RegisterControl(openHighlights, ctx, "navigation.frame_highlights", "Open Highlights", "button", "navigation", { navigationKey = "opt_misc" })
    local groupNumberCard = W.ControlCard(indicators, "Group Number", nil, leftX, -148, leftW, 320)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(groupNumberCard, {
            title = "Group Number Text Settings",
            historyLabel = "Group number text color",
            historySource = "menu:group-number-text-color",
            offsetX = -76,
            textSettings = {
                scope = function() return CurrentScope() end,
                group = true,
                kind = "status",
                subtitle = "Font style and color are synchronized with the Fonts menu for this group scope.",
                colorTitle = "Group number text color",
                capabilities = { baseline = false },
            },
        })
    end
    local groupNumberToggle = BindScopeToggle(ctx, W.SwitchAt(groupNumberCard, "Group Number", leftW - 62, -24, 0, "HIDDEN"), "showGroupNumber", false, "visual")
    groupNumberToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupNumberControls = {}
    -- Same three styles as the unit-frame Raid Group indicator, so both
    -- surfaces stay on one shared runtime formatter.
    AddScopeDropdown(groupNumberControls, groupNumberCard, "Style", GROUP_NUMBER_STYLES, leftW, "groupNumberStyle", "PAREN", "visual", -66)
    AddScopeSlider(groupNumberControls, groupNumberCard, "Size", 6, 24, 1, leftW, "groupNumberSize", 10, "font", -116)
    -- The preview handle resolves a drag to any of the nine anchor points, so
    -- the dropdown has to be able to show all nine too.
    AddScopeDropdown(groupNumberControls, groupNumberCard, "Anchor", STATUS_ICON_ANCHORS, leftW, "groupNumberAnchor", "BOTTOMRIGHT", "geometry", -166)
    AddScopeSlider(groupNumberControls, groupNumberCard, "Layer", 0, 30, 1, leftW, "groupNumberLayer", 7, "visual", -216)
    local groupNumberScopeHint = W.Text(groupNumberCard, "", 16, -268, leftW - 32, T.colors.muted)
    if groupNumberScopeHint.SetWordWrap then groupNumberScopeHint:SetWordWrap(true) end
    local focusCard = W.ControlCard(indicators, "Focus Highlight", "Shows a colored border around your Focus target. Priority: Dispel > Aggro > Target > Focus.", rightX, -148, rightW, 190)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(focusCard, { "group.focus" }, {
            title = "Focus Highlight Color",
            note = "Shared by Party, Raid and Mythic Raid.",
            historySource = "menu:group-focus-highlight-color",
            offsetX = -76,
        })
    end
    local focusToggle = BindScopeToggle(ctx, W.SwitchAt(focusCard, "Focus Highlight", rightW - 62, -24, 0, "HIDDEN"), "hlFocusEnabled", true, "visual")
    focusToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local focusHint = focusCard and focusCard.subtitle
    if focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    local focusControls = {}
    AddScopeSlider(focusControls, focusCard, "Border Thickness", 1, 6, 1, rightW, "hlFocusSize", 2, "visual", -88)
    local focusColorHint = W.Text(focusCard, "Focus color is in Global Style > Colors > Group Frame Colors.", 16, -142, rightW - 32, T.colors.muted)
    if focusColorHint.SetWordWrap then focusColorHint:SetWordWrap(true) end
    local groupBorderCard = W.ControlCard(indicators, "Group Border", nil, leftX, -486, leftW, 202)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(groupBorderCard, { "group.border" }, {
            title = "Group Border Color",
            note = "Shared by Party, Raid and Mythic Raid.",
            historySource = "menu:group-border-color",
            offsetX = -76,
        })
    end
    local groupBorderToggle = BindScopeToggle(ctx, W.SwitchAt(groupBorderCard, "Group Border", leftW - 62, -24, 0, "HIDDEN"), "groupBorderEnabled", false, "visual")
    groupBorderToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupBorderControls = {}
    AddScopeSlider(groupBorderControls, groupBorderCard, "Border Thickness", 1, 12, 1, leftW, "groupBorderSize", 1, "visual", -66)
    AddScopeSlider(groupBorderControls, groupBorderCard, "Padding", 0, 40, 1, leftW, "groupBorderPadding", 2, "visual", -116)
    local groupBorderColorHint = W.Text(groupBorderCard, "Border color and opacity are in Global Style > Colors > Group Frame Colors.", 16, -168, leftW - 32, T.colors.muted)
    if groupBorderColorHint.SetWordWrap then groupBorderColorHint:SetWordWrap(true) end
    local function RefreshIndicatorsState()
        local groupNumberEnabled = Bool(CurrentScope(), "showGroupNumber", false)
        SetOptionsEnabled(groupNumberControls, groupNumberEnabled)
        SetOptionEnabled(groupNumberToggle, true)
        -- The number is the raid subgroup, read from the raid roster. A plain
        -- 5-player party has no subgroups, so say so instead of letting the
        -- toggle look broken.
        groupNumberScopeHint:SetText(CurrentScope() == "party"
            and "Shows the raid subgroup number in a raid. Move it in Preview."
            or "Shows the raid subgroup number from the raid roster. Move it in Preview.")
        local targetEnabled = Bool(CurrentScope(), "targetIndicator", true)
        local focusEnabled = Bool(CurrentScope(), "hlFocusEnabled", true)
        SetOptionsEnabled(focusControls, focusEnabled)
        SetOptionEnabled(focusToggle, true)
        local focusColorText = focusEnabled and T.colors.muted or T.colors.dim
        focusHint:SetTextColor(focusColorText[1], focusColorText[2], focusColorText[3], focusEnabled and 1 or 0.70)
        local groupBorderEnabled = Bool(CurrentScope(), "groupBorderEnabled", false)
        SetOptionsEnabled(groupBorderControls, groupBorderEnabled)
        SetOptionEnabled(groupBorderToggle, true)
        SetSectionBadgesAndStatus(indicators, {
            OnOffBadge(targetEnabled, "Target on", "Target off"),
            OnOffBadge(focusEnabled, "Focus on", "Focus off"),
            { text = groupNumberEnabled and "Group #" or (groupBorderEnabled and "Group border" or "Clean"), kind = (groupNumberEnabled or groupBorderEnabled) and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, indicators, RefreshIndicatorsState)
end

local function BuildStatusIconsSection(ctx, b, RefreshPage)
    local sicons = b:CollapsibleSection("sicons", "Status Icons", 534, false)
    local siconW = sicons._msuf2Width or ctx.width or 720
    local siconGap = 16
    local siconLeftX = 20
    local siconInnerW = max(320, siconW - 40)
    local siconLeftW = floor((siconInnerW - siconGap) * 0.46)
    local siconRightX = siconLeftX + siconLeftW + siconGap
    local siconRightW = siconInnerW - siconLeftW - siconGap
    M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
    local function CurrentStatusIconTab()
        local key = M.gfStatusIconTabSelection[CurrentScope()] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local siconTabFrames = {}
    local siconBasicTab, siconAdvancedTab = M.UnitSectionsShared.MakeTabFrames(sicons, -64, siconW, siconTabFrames, "basic", "advanced")
    local statusTabs, RefreshStatusTabs, ReadStatusTab, SetGuidedStatusTab = W.SegmentTabs(ctx, sicons, {
        get = CurrentStatusIconTab,
        set = function(value) M.gfStatusIconTabSelection[CurrentScope()] = value or "basic" end,
        label = "", values = STATUS_ICON_TAB_VALUES, width = min(420, siconInnerW),
        frames = siconTabFrames,
        defaultTab = "basic", x = siconLeftX, y = -12,
    })
    if statusTabs._msuf2Title then statusTabs._msuf2Title:Hide() end
    RegisterControl(statusTabs, ctx, "status.workspace_tab", "Status icon controls", "segment", "ephemeral")
    sicons._msuf2GuidedSelectTab = function(tab)
        if tab ~= "basic" and tab ~= "advanced" then return false end
        if type(ReadStatusTab) == "function" and ReadStatusTab() == tab then return true end
        if type(SetGuidedStatusTab) == "function" then
            SetGuidedStatusTab(tab)
        else
            M.gfStatusIconTabSelection[CurrentScope()] = tab
            if type(RefreshStatusTabs) == "function" then RefreshStatusTabs() end
        end
        return type(ReadStatusTab) ~= "function" or ReadStatusTab() == tab
    end
    local function IsTextStatusIconSpec(spec)
        local value = spec and spec.value
        return value == "statusText" or value == "statusGhostText"
            or value == "statusAFKText" or value == "statusAFKTimer" or value == "statusDNDText"
    end
    --- The scope-wide style card is gone: it only ever changed role/leader/assist art while
    --- sitting above a per-indicator selector, which read as if it applied to the selection.
    --- Each indicator now carries its own style dropdown inside the Selected card instead.
    local selectedCard = W.ControlCard(siconBasicTab, "Selected Indicator", nil, siconLeftX, -38, siconLeftW, 316)
    local selectedTextShortcut
    if W.AttachContextColorShortcut then
        selectedTextShortcut = W.AttachContextColorShortcut(selectedCard, {
            title = "Selected Status Text Settings",
            historyLabel = "Group status text color",
            historySource = "menu:group-status-text-color",
            offsetX = -76,
            textSettings = {
                scope = function() return CurrentScope() end,
                group = true,
                kind = "status",
                subtitle = "Font style and color are synchronized with the Fonts menu for this group scope.",
                colorTitle = "Group status text color",
                capabilities = { baseline = false },
            },
        })
        selectedTextShortcut:SetShown(IsTextStatusIconSpec(CurrentGFStatusSpec()))
    end
    local previewCard = W.ControlCard(siconBasicTab, "Status Preview", nil, siconRightX, -38, siconRightW, 164)
    local placementCard = W.ControlCard(siconBasicTab, "Placement", nil, siconRightX, -220, siconRightW, 172)
    local function RefreshStatusIconMenu()
        if M.RequestRefresh then
            M.RequestRefresh(ctx, "gf-indicators-status-icon")
        elseif M.Refresh then
            M.Refresh(ctx)
        else
            RefreshPage()
        end
    end
    local function StatusSpecDefault(spec, value)
        if type(value) == "function" then return value(spec) end
        return value
    end
    local function BindStatusDropdown(parent, label, values, width, specField, defaultValue, reason, x, y, moveWidth, afterSet)
        local control = W.Dropdown(parent, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local spec = CurrentGFStatusSpec()
                local key = spec and spec[specField]
                return key and Val(CurrentScope(), key, StatusSpecDefault(spec, defaultValue)) or StatusSpecDefault(spec, defaultValue)
            end,
            function(value)
                local spec = CurrentGFStatusSpec()
                local key = spec and spec[specField]
                if not key then return end
                Set(CurrentScope(), key, value or StatusSpecDefault(spec, defaultValue), reason)
                if afterSet then afterSet(value, spec) end
            end,
            ControlMeta(ctx, "status.selected." .. tostring(specField)))
        W.MoveWidget(control, parent, x, y, moveWidth or width, "LEFT")
        return control
    end
    local function BindStatusSlider(parent, label, minValue, maxValue, step, width, specField, defaultValue, reason, x, y, moveWidth, clamp, identitySuffix)
        local control = W.Slider(parent, label, minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function()
                local spec = CurrentGFStatusSpec()
                local value = Num(CurrentScope(), spec[specField], StatusSpecDefault(spec, defaultValue))
                if clamp then
                    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
                end
                return value
            end,
            function(value)
                local spec = CurrentGFStatusSpec()
                value = floor((tonumber(value) or StatusSpecDefault(spec, defaultValue)) + 0.5)
                if clamp then
                    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
                end
                Set(CurrentScope(), spec[specField], value, reason)
            end,
            StatusSpecDefault(CurrentGFStatusSpec(), defaultValue), StepMeta(ctx,
                "status.selected." .. tostring(specField) .. (identitySuffix and ("." .. identitySuffix) or ""), step))
        W.MoveWidget(control, parent, x, y, moveWidth or width, "LEFT")
        return control
    end
    local function BuildStatusControls(parent, specs)
        return M.BuildControlSpecs(specs, {
            dropdown = function(s, i) return BindStatusDropdown(parent, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]), s[12] or s[5] or i end,
            slider = function(s, i) return BindStatusSlider(parent, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11], s[12], s[13], s.identitySuffix), s[14] or s[7] or i end,
        })
    end
    local function StatusIconPreviewEntries(spec)
        local value = spec and spec.value
        if value == "raidMarker" then return { { "raidMarker", 1 }, { "raidMarker", 5 }, { "raidMarker", 8 } } end
        if value == "readyCheckIcon" then return { { "readyCheck", "ready" }, { "readyCheck", "notready" }, { "readyCheck", "waiting" } } end
        if value == "summonIcon" then return { { "summon", 1 }, { "summon", 2 }, { "summon", 3 } } end
        if value == "resurrectIcon" then return { { "incomingRes", "resurrect" } } end
        if value == "pvpIcon" then return { { "pvp", "Alliance" }, { "pvp", "Horde" }, { "pvp", "FFA" } } end
        if value == "phaseIcon" then return { { "phase", "phase" } } end
        if value == "leaderIcon" then return { { "leader" } } end
        if value == "assistIcon" then return { { "assist" } } end
        if value == "roleIcon" then return { { "role", "TANK" }, { "role", "HEALER" }, { "role", "DAMAGER" } } end
        return nil
    end
    local function IsRoleStatusIconSpec(spec)
        local value = spec and spec.value
        return value == "roleIcon" or value == "leaderIcon" or value == "assistIcon"
    end
    local function StatusIconStyleLabel(spec)
        return spec and spec.value == "roleIcon" and "Role icon style" or "Indicator style"
    end
    local function SpecificIconLabel(spec)
        return "Custom icon"
    end
    local function SetDropdownTitle(control, label)
        if control and control._msuf2Title and control._msuf2Title.SetText then
            control._msuf2Title:SetText(Tr(label))
        end
    end
    --- Each style value carries its own Midnight flag now, so the support probe runs per entry
    --- and silently drops packs that ship no art for the selected indicator.
    local function IconPackValuesForCurrentStatus()
        local values = IconPackValues()
        local spec = CurrentGFStatusSpec()
        local entries = StatusIconPreviewEntries(spec)
        local supports = _G.MSUF_StatusIconPackSupports
        if type(supports) ~= "function" or type(entries) ~= "table" then return values end
        local out = {}
        for i = 1, #values do
            local item = values[i]
            local value = item and (item.value or item.key)
            local keep = false
            for j = 1, #entries do
                local entry = entries[j]
                if supports(value, entry[1], entry[2], false) then
                    keep = true
                    break
                end
            end
            if keep then out[#out + 1] = item end
        end
        if #out == 0 then out[1] = { value = "BLIZZARD", text = "Blizzard (Default)" } end
        return out
    end
    local function IconAssetValuesForCurrentStatus()
        local spec = CurrentGFStatusSpec()
        local entries = StatusIconPreviewEntries(spec)
        local valuesFn = _G.MSUF_GetStatusIconAssetValues
        if type(valuesFn) ~= "function" or type(entries) ~= "table" then
            return { { value = "", text = "Use default icon" } }
        end
        local out, used = {}, {}
        for i = 1, #entries do
            local entry = entries[i]
                local values = valuesFn(entry[1], entry[2], i == 1, true)
            for j = 1, #(values or {}) do
                local item = values[j]
                local value = item and item.value
                if type(value) == "string" and not used[value] then
                    used[value] = true
                    out[#out + 1] = item
                end
            end
        end
        if #out == 0 then out[1] = { value = "", text = "Use default icon" } end
        return out
    end
    local function ResolvePreviewStatusIcon(style, iconType, variant, useMidnight)
        local resolver = _G.MSUF_GetStatusIconTexture
        if type(resolver) ~= "function" then
            local gf = GF()
            resolver = gf and gf.GetStatusIconTexture
        end
        if type(resolver) ~= "function" then return nil end
        return resolver(style, iconType, variant, useMidnight == true)
    end
    local statusSelector = W.Dropdown(selectedCard, "Indicator", GF_STATUS_ICON_VALUES, siconLeftW)
    M.BindDropdownWidget(ctx, statusSelector,
        function() return CurrentGFStatusSpec().value end,
        function(value)
            for i = 1, #GF_STATUS_ICON_SPECS do
                if GF_STATUS_ICON_SPECS[i].value == value then
                    M.SetMenuStateValue("gfStatusIconSelection", value)
                    local gf = GF()
                    if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(value) end
                    RefreshStatusIconMenu()
                    return
                end
            end
        end,
        ControlMeta(ctx, "status.selector", "ephemeral"))
    W.MoveWidget(statusSelector, selectedCard, 16, -54, siconLeftW - 32, "LEFT")
    local statusEnabled = W.SwitchAt(selectedCard, "Enabled", siconLeftW - 62, -24, 0, "HIDDEN")
    statusEnabled._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, statusEnabled,
        function()
            local spec = CurrentGFStatusSpec()
            return Bool(CurrentScope(), spec.enabled, false)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.enabled, value and true or false, "visual")
            RefreshStatusIconMenu()
        end,
        ControlMeta(ctx, "status.selected.enabled"))
    local RefreshStatusIconState
    --- Profiles saved before the per-indicator split still store "DEFAULT"; resolve it through
    --- the runtime so the dropdown shows the style that is actually drawn rather than an entry
    --- the list no longer offers.
    local function CurrentStatusIconStyle()
        local spec = CurrentGFStatusSpec()
        local key = spec and spec.iconStyle
        local resolved
        local stored = key and Val(CurrentScope(), key, "DEFAULT") or "DEFAULT"
        if type(stored) == "string" and stored ~= "" and stored ~= "DEFAULT" then
            resolved = stored
        else
            local gf = GF()
            if spec and gf and type(gf.GetIndicatorIconStyle) == "function" then
                local style, midnight = gf.GetIndicatorIconStyle(CurrentScope(), spec.value)
                if type(style) == "string" and style ~= "" then
                    resolved = (midnight and type(gf.JoinIconStyle) == "function")
                        and gf.JoinIconStyle(style, true) or style
                end
            end
        end
        -- The inherited style can be one this indicator has no art for (the old global default
        -- was role-only), and that style is filtered out of the list. Show Blizzard instead of
        -- a value the dropdown cannot render.
        local values = IconPackValuesForCurrentStatus()
        for i = 1, #values do
            local item = values[i]
            if item and (item.value or item.key) == resolved then return resolved end
        end
        return "BLIZZARD"
    end
    local iconPack = W.Dropdown(selectedCard, "Indicator style", IconPackValuesForCurrentStatus, siconLeftW)
    M.BindDropdownWidget(ctx, iconPack, CurrentStatusIconStyle,
        function(value)
            local spec = CurrentGFStatusSpec()
            local key = spec and spec.iconStyle
            if not key then return end
            Set(CurrentScope(), key, value or "DEFAULT", "visual")
            M.CallIf(RefreshGFPreview)
            if RefreshStatusIconState then RefreshStatusIconState() end
        end,
        ControlMeta(ctx, "status.selected.iconStyle"))
    W.MoveWidget(iconPack, selectedCard, 16, -106, siconLeftW - 32, "LEFT")
    local customIcon = BindStatusDropdown(selectedCard, "Custom icon", IconAssetValuesForCurrentStatus, siconLeftW, "customIcon", "", "visual", 16, -158, siconLeftW - 32,
        function()
            M.CallIf(RefreshGFPreview)
            if RefreshStatusIconState then RefreshStatusIconState() end
        end)

    --- Role filter group: only visible when Role Icon indicator is selected
    local roleFilterGroup = CreateFrame("Frame", nil, selectedCard)
    roleFilterGroup:SetPoint("TOPLEFT", selectedCard, "TOPLEFT", 0, -216)
    local roleFilterW = max(180, siconLeftW - 32)
    roleFilterGroup:SetSize(roleFilterW, 60)
    W.LabelAt(roleFilterGroup, "Show for:", 16, -8, siconLeftW - 32, "GameFontNormalSmall", T.colors.accent)
    local rfColW   = floor(roleFilterW / 3)
    local rfLabelW = max(34, rfColW - 30)  --- subtract checkbox(24) + gap(6) so hit areas don't overlap the next column
    local rfTank   = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Tank",   16,              -26, rfLabelW), "roleIconShowTank",   true, "visual")
    local rfHealer = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Healer", 16 + rfColW,     -26, rfLabelW), "roleIconShowHealer", true, "visual")
    local rfDPS    = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "DPS",    16 + rfColW * 2, -26, rfLabelW), "roleIconShowDPS",    true, "visual")
    local roleFilterControls = { rfTank, rfHealer, rfDPS }
    local previewInnerW = max(190, siconRightW - 32)
    local previewButtonGap = 8
    local previewCurrentW = min(142, max(112, floor(previewInnerW * 0.58)))
    local previewAllW = min(112, max(76, previewInnerW - previewCurrentW - previewButtonGap))
    previewCurrentW = max(96, previewInnerW - previewAllW - previewButtonGap)
    --- Green (success) role marks whichever preview mode is live; the other stays neutral.
    local RefreshStatusPreviewButtons
    local function CurrentStatusPreviewMode()
        return M.gfStatusPreviewMode == "all" and "all" or "current"
    end
    local function SetStatusPreviewMode(mode)
        local gf = GF()
        M.SetMenuStateValue("gfStatusPreviewMode", mode)
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        M.CallIf(RefreshGFPreview)
        if RefreshStatusPreviewButtons then RefreshStatusPreviewButtons() end
    end
    local function PreviewActionButton(parent, label, width, semanticPath, onClick)
        local btn = W.Button(parent, label, width)
        btn:SetScript("OnClick", onClick)
        RegisterControl(btn, ctx, semanticPath, label, "button", "ephemeral")
        btn:ClearAllPoints()
        btn:SetSize(width, 24)
        return btn
    end
    local previewCurrent = PreviewActionButton(previewCard, "Preview current", previewCurrentW, "status.preview.current", function()
        SetStatusPreviewMode("current")
    end)
    previewCurrent:ClearAllPoints()
    previewCurrent:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -56)
    local previewAll = PreviewActionButton(previewCard, "Show all", previewAllW, "status.preview.all", function()
        SetStatusPreviewMode("all")
    end)
    previewAll:SetPoint("LEFT", previewCurrent, "RIGHT", previewButtonGap, 0)
    local statusReset = W.Button(previewCard, "Reset selected", min(160, previewInnerW))
    statusReset:SetScript("OnClick", function()
        local kind = CurrentScope()
        local spec = CurrentGFStatusSpec()
        local conf = Conf(kind)
        local gf = GF()
        for i = 1, #STATUS_ICON_RESET_FIELDS do
            local key = spec[STATUS_ICON_RESET_FIELDS[i]]
            if key then conf[key] = gf and gf.GetDefault and gf.GetDefault(kind, key) or nil end
        end
        QueueGF(kind, "visual")
        RefreshStatusIconMenu()
    end)
    RegisterControl(statusReset, ctx, "status.selected.reset", "Reset selected", "button", "action", {
        actionKey = "reset_selected_group_status_icon",
    })
    statusReset:ClearAllPoints()
    statusReset:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -86)
    statusReset:SetSize(min(160, previewInnerW), 24)
    local iconPreviewLabel = W.LabelAt(previewCard, "Icon preview", 16, -120, previewInnerW, "GameFontNormalSmall", T.colors.accent)
    local iconPreviewStrip = CreateFrame("Frame", nil, previewCard)
    iconPreviewStrip:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -132)
    iconPreviewStrip:SetSize(previewInnerW, 24)
    local iconPreviewTextures = {}
    for i = 1, 5 do
        local holder = CreateFrame("Frame", nil, iconPreviewStrip)
        holder:SetSize(24, 24)
        holder:SetPoint("LEFT", iconPreviewStrip, "LEFT", (i - 1) * 28, 0)
        holder.bg = holder:CreateTexture(nil, "BACKGROUND")
        holder.bg:SetAllPoints()
        holder.bg:SetColorTexture(0.020, 0.026, 0.052, 0.70)
        holder.tex = holder:CreateTexture(nil, "ARTWORK")
        holder.tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder.tex:SetSize(22, 22)
        iconPreviewTextures[i] = holder
    end
    local function RefreshIconPreviewStrip(spec, enabled)
        local entries = StatusIconPreviewEntries(spec)
        local shown = entries and spec and (IsRoleStatusIconSpec(spec) or spec.customIcon)
        iconPreviewLabel:SetShown(shown and true or false)
        iconPreviewStrip:SetShown(shown and true or false)
        if not shown then return end
        --- Preview the style the indicator itself carries; the value may hold the Midnight
        --- suffix, which the texture resolver splits off on its own.
        local style = CurrentStatusIconStyle()
        if type(style) ~= "string" or style == "" or style == "DEFAULT" then style = "BLIZZARD" end
        local customPath = spec and spec.customIcon and Val(CurrentScope(), spec.customIcon, "") or ""
        iconPreviewStrip:SetAlpha(enabled and 1 or 0.46)
        for i = 1, #iconPreviewTextures do
            local holder = iconPreviewTextures[i]
            local entry = entries[i]
            if entry then
                local path, l, r, t, b
                if type(customPath) == "string" and customPath ~= "" then
                    path, l, r, t, b = customPath, 0, 1, 0, 1
                else
                    path, l, r, t, b = ResolvePreviewStatusIcon(style, entry[1], entry[2], false)
                end
                if type(path) == "string" and path ~= "" then
                    holder.tex:SetTexture(path)
                    holder.tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                    holder.tex:SetVertexColor(1, 1, 1, 1)
                    holder:Show()
                else
                    holder:Hide()
                end
            else
                holder:Hide()
            end
        end
    end
    local statusControls = BuildStatusControls(placementCard, {
        { "slider", "Size", 6, 40, 1, siconRightW, "size", function(spec) return spec.defaultSize end, "visual", 16, -58, siconRightW - 58 },
        { "dropdown", "Anchor", STATUS_ICON_ANCHORS, siconRightW, "anchor", function(spec) return spec.defaultAnchor end, "geometry", 16, -108, siconRightW - 32 },
    })
    local advanced = {}
    advanced.card = W.ControlCard(siconAdvancedTab, "Advanced Placement", nil, siconLeftX, -38, siconInnerW, 232)
    M.Assign(advanced, BuildStatusControls(advanced.card, {
        { "slider", "Layer", 0, 30, 1, siconLeftW, "layer", function(spec) return spec.defaultLayer end, "visual", 16, -58, siconLeftW - 58, true, identitySuffix = "extended" },
    }))
    advanced.reset = W.Button(advanced.card, "Reset selected", 160)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if statusReset and statusReset.Click then statusReset:Click() end
    end)
    RegisterControl(advanced.reset, ctx, "status.advanced.reset", "Reset selected", "button", "action", {
        actionKey = "reset_selected_group_status_icon",
    })
    advanced.reset:ClearAllPoints()
    advanced.reset:SetPoint("TOPLEFT", advanced.card, "TOPLEFT", siconRightX - siconLeftX, -58)
    advanced.reset:SetSize(160, 24)
    advanced.previewCurrent = PreviewActionButton(advanced.card, "Preview current", 142, "status.advanced.preview.current", function()
        if previewCurrent and previewCurrent.Click then previewCurrent:Click() end
    end)
    advanced.previewCurrent:SetPoint("TOPLEFT", advanced.card, "TOPLEFT", 16, -150)
    advanced.previewAll = PreviewActionButton(advanced.card, "Show all", 112, "status.advanced.preview.all", function()
        if previewAll and previewAll.Click then previewAll:Click() end
    end)
    advanced.previewAll:SetPoint("LEFT", advanced.previewCurrent, "RIGHT", 12, 0)
    RefreshStatusPreviewButtons = function()
        local ApplyRole = T.ApplyButtonRole
        if not ApplyRole then return end
        local currentRole = CurrentStatusPreviewMode() == "current" and "success" or "normal"
        local allRole = currentRole == "success" and "normal" or "success"
        ApplyRole(previewCurrent, currentRole)
        ApplyRole(previewAll, allRole)
        ApplyRole(advanced.previewCurrent, currentRole)
        ApplyRole(advanced.previewAll, allRole)
    end
    local statusPlacementControls = { statusControls.size, statusControls.anchor, advanced.layer }
    local statusActionControls = { advanced.reset, advanced.previewCurrent, statusReset, previewCurrent }
    RefreshStatusIconState = function()
        local spec = CurrentGFStatusSpec()
        local enabled = Bool(CurrentScope(), spec.enabled, false)
        SetDropdownTitle(iconPack, StatusIconStyleLabel(spec))
        SetDropdownTitle(customIcon, SpecificIconLabel(spec))
        if iconPreviewLabel and iconPreviewLabel.SetText then
            iconPreviewLabel:SetText(IsRoleStatusIconSpec(spec) and Tr("Role icon preview") or Tr("Icon preview"))
        end
        SetOptionsEnabled(statusPlacementControls, enabled)
        SetOptionsEnabled(statusActionControls, spec ~= nil)
        SetManyEnabled(true, advanced.previewAll, previewAll, statusEnabled)
        RefreshStatusPreviewButtons()
        --- Style packs are only a meaningful knob for the role/leader/assist glyphs -- the
        --- remaining indicators are canonical game symbols where people replace a single
        --- texture, so they keep just the Custom icon dropdown. The count guard stays as a
        --- safety net in case a pack set ever leaves nothing but Blizzard to pick.
        local hasIconPack = IsRoleStatusIconSpec(spec) and spec.iconStyle
            and #IconPackValuesForCurrentStatus() > 1
        local hasCustomIcon = spec and spec.customIcon
        if selectedTextShortcut then selectedTextShortcut:SetShown(IsTextStatusIconSpec(spec)) end
        if W.SetControlShown then
            W.SetControlShown(iconPack, hasIconPack and true or false)
            W.SetControlShown(customIcon, hasCustomIcon and true or false)
        else
            iconPack:SetShown(hasIconPack and true or false)
            if iconPack._msuf2Title then iconPack._msuf2Title:SetShown(hasIconPack and true or false) end
            customIcon:SetShown(hasCustomIcon and true or false)
            if customIcon._msuf2Title then customIcon._msuf2Title:SetShown(hasCustomIcon and true or false) end
        end
        SetOptionEnabled(iconPack, hasIconPack and enabled)
        SetOptionEnabled(customIcon, hasCustomIcon and enabled)
        local isRoleIcon = spec.value == "roleIcon"
        roleFilterGroup:SetShown(isRoleIcon)
        if isRoleIcon then SetOptionsEnabled(roleFilterControls, enabled) end
        RefreshIconPreviewStrip(spec, enabled)
        SetSectionBadgesAndStatus(sicons, {
            OnOffBadge(enabled, "Shown", "Hidden"),
            { text = spec and (spec.text or spec.value) or "Selected", kind = enabled and "info" or "muted" },
            { text = CurrentStatusIconTab() == "advanced" and "Advanced" or "Basic", kind = "accent" },
        })
    end
    TrackSectionRefresh(ctx, sicons, RefreshStatusIconState)
end

-- Spell data operations live outside the page builder so UI closures retain only page state.
-- All lookups continue to use the runtime's 12.1-safe AuraSlot/SpellID registries.
local function SpellIndicatorRuntime()
    local gf = GF()
    return gf and gf.SpellIndicators
end
local function EnsureSpellDefaults(kind, specKey)
    local runtime = SpellIndicatorRuntime()
    if runtime and type(runtime.EnsureSpecConfig) == "function" and specKey then
        runtime.EnsureSpecConfig(SpellIndicators(kind), specKey)
    end
end
local function SpellConfigFor(kind, specKey, auraName, create)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local cfg = SpellIndicators(kind)
    cfg.specs = cfg.specs or {}
    if create and not cfg.specs[specKey] then cfg.specs[specKey] = {} end
    local specCfg = cfg.specs[specKey]
    if create and specCfg and type(specCfg[auraName]) ~= "table" then specCfg[auraName] = { enabled = true, onlyOwn = true } end
    return specCfg and specCfg[auraName]
end
local function CurrentAuraInfo(kind)
    local runtime, specKey, auraName = SpellIndicatorRuntime(), EffectiveSpellSpec(kind), CurrentSpellAura(kind)
    local trackable = specKey and runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    for i = 1, type(trackable) == "table" and #trackable or 0 do
        if trackable[i] and trackable[i].name == auraName then return trackable[i], specKey, auraName end
    end
    return nil, specKey, auraName
end
local function CurrentSpellIsExternalDefensive(kind)
    local cfg, specKey, auraName = CurrentSpellConfig(kind, false)
    local runtime = SpellIndicatorRuntime()
    return runtime and type(runtime.IsExternalDefensiveAura) == "function"
        and runtime.IsExternalDefensiveAura(specKey, auraName, cfg) == true
end
local function ExternalAutoBlacklistActive(kind)
    local conf = Conf(kind)
    local root = type(conf and conf.auras) == "table" and conf.auras or nil
    local externals = root and type(root.externals) == "table" and root.externals or {}
    return (root == nil or root.enabled ~= false)
        and externals.enabled ~= false
        and (tonumber(externals.max) or 2) > 0
        and externals.autoBlacklistBuffs ~= false
end
local function CurrentAuraColor(kind)
    local info = CurrentAuraInfo(kind)
    return (info and info.color) or WHITE_RGB
end
local function TrackableSpellID(runtime, specKey, info)
    if type(info) ~= "table" then return nil end
    local id = CustomBuffSpellID(info.spellID or info.spellId or info.id)
    if id then return id end
    local auraName = info.name
    for _, registry in ipairs({ runtime and runtime.SpellIDs, runtime and runtime.SecretSpellIDs }) do
        id = registry and registry[specKey] and CustomBuffSpellID(registry[specKey][auraName])
        if id then return id end
    end
    local altIDs = runtime and runtime.AltSpellIDs and runtime.AltSpellIDs[specKey]
    for altID, mappedAura in pairs(type(altIDs) == "table" and altIDs or {}) do
        if mappedAura == auraName then id = CustomBuffSpellID(altID); if id then return id end end
    end
    return CustomBuffSpellID(auraName)
end
local function CustomEntryContainsSpellID(auraName, entry, spellID)
    spellID = CustomBuffSpellID(spellID)
    if not spellID then return false end
    if CustomBuffSpellID(auraName) == spellID then return true end
    if type(entry) ~= "table" then return false end
    if CustomBuffSpellID(entry.spellID or entry.spellId or entry.id) == spellID then return true end
    local ids = CustomBuffSpellIDs(entry.spells)
    for i = 1, type(ids) == "table" and #ids or 0 do if ids[i] == spellID then return true end end
    return false
end
local function ExistingAuraForSpellIDs(runtime, specKey, spellIDs, specCfg)
    if type(spellIDs) ~= "table" then return nil end
    for auraName, entry in pairs(type(specCfg) == "table" and specCfg or {}) do
        if IsCustomBuffEntry(auraName, entry) then
            for i = 1, #spellIDs do if CustomEntryContainsSpellID(auraName, entry, spellIDs[i]) then return auraName end end
        end
    end
    local trackable = specKey and runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    for i = 1, type(trackable) == "table" and #trackable or 0 do
        local info, id = trackable[i], TrackableSpellID(runtime, specKey, trackable[i])
        for j = 1, #spellIDs do
            if id == spellIDs[j] and (info.custom ~= true or (type(specCfg) == "table" and specCfg[info.name] ~= nil)) then return info.name end
        end
    end
end
local function CountCustomBuffs(specCfg)
    local count = 0
    for auraName, entry in pairs(type(specCfg) == "table" and specCfg or {}) do
        if IsCustomBuffEntry(auraName, entry) then count = count + 1 end
    end
    return count
end
local function SpellFeedback(text, kind)
    if M.ShowStatusFeedback then M.ShowStatusFeedback(Tr(text), kind, 3) end
end
local function RefreshSpellPage(refreshPage)
    M.CallIf(RefreshGFPreview)
    if refreshPage then refreshPage() end
end
local function AddCustomBuffResolved(refreshPage, kind, specKey, spellIDs)
    local spellID = spellIDs and spellIDs[1]
    if not spellID then SpellFeedback("Enter a valid buff Spell ID, link, or name.", "error"); return false end
    if not specKey then SpellFeedback("No spell-indicator spec selected.", "error"); return false end
    local runtime, key, cfg = SpellIndicatorRuntime(), tostring(spellID), SpellIndicators(kind)
    cfg.specs = cfg.specs or {}
    cfg.specs[specKey] = cfg.specs[specKey] or {}
    local specCfg = cfg.specs[specKey]
    local existingAura = ExistingAuraForSpellIDs(runtime, specKey, spellIDs, specCfg)
    if existingAura and existingAura ~= key then
        SetCurrentSpellAura(kind, existingAura)
        SpellFeedback("Buff already exists; selected existing icon.", "info")
        RefreshSpellPage(refreshPage)
        return true
    end
    local exists, customCount = type(specCfg[key]) == "table", CountCustomBuffs(specCfg)
    if not exists and customCount >= CUSTOM_BUFF_LIMIT then SpellFeedback("Custom buff limit reached.", "error"); return false end
    local display, icon = CustomBuffInfo(spellID)
    local spellIDListText = CustomBuffSpellIDListText(spellIDs)
    local function ApplyCustomBuff()
        local entry = exists and specCfg[key] or {}
        entry.enabled = true
        if entry._msufCustomOnlyOwnExplicit ~= true then entry.onlyOwn = false end
        entry.custom, entry.spellID, entry.spells = true, spellID, spellIDListText
        entry.display, entry.icon = display, icon
        if type(entry.placed) ~= "table" then entry.placed = DefaultCustomBuffPlaced(exists and max(1, customCount) or customCount + 1) end
        specCfg[key] = entry
        SetCurrentSpellAura(kind, key)
        QueueSpellIndicators(kind)
    end
    M.RunWithHistory("Add Custom Buff", "group:spellCustomAdd:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. key, ApplyCustomBuff)
    RefreshSpellPage(refreshPage)
    return true
end
local function ShowCustomBuffAuraIDSuggestion(refreshPage, kind, specKey, spellIDs, suggestedID, spellName)
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then return false end
    M.InstallStaticPopup("MSUF2_GF_SPELL_CUSTOM_BUFF_AURA_ID", {
        text = "%s", button1 = Tr("Use both IDs"), button2 = Tr("Entered ID only"), hideOnEscape = false,
        OnAccept = function(_, data)
            if type(data) ~= "table" then return end
            local combined, seen = {}, {}
            for i = 1, #(data.spellIDs or {}) do AddCustomBuffSpellID(combined, seen, data.spellIDs[i]) end
            AddCustomBuffSpellID(combined, seen, data.suggestedID)
            AddCustomBuffResolved(data.refreshPage, data.kind, data.specKey, combined)
        end,
        OnCancel = function(_, data, reason)
            if reason == "clicked" and type(data) == "table" then
                AddCustomBuffResolved(data.refreshPage, data.kind, data.specKey, data.spellIDs)
            end
        end,
    })
    local message = M.Format("%s is active on you with Aura ID %d. Your entered ID is %d. Track both IDs?",
        tostring(spellName or Tr("This buff")), tonumber(suggestedID) or 0, tonumber(spellIDs and spellIDs[1]) or 0)
    _G.StaticPopup_Show("MSUF2_GF_SPELL_CUSTOM_BUFF_AURA_ID", message, nil,
        { refreshPage = refreshPage, kind = kind, specKey = specKey, spellIDs = spellIDs, suggestedID = suggestedID })
    return true
end
local function AddCustomBuff(refreshPage, kind, specKey, rawValue)
    local spellIDs = ResolveCustomBuffSpellIDs(rawValue)
    if not spellIDs then return AddCustomBuffResolved(refreshPage, kind, specKey) end
    RequestCustomBuffSpellData(spellIDs)
    local suggestedID, spellName = SuggestedActivePlayerAuraID(spellIDs)
    if suggestedID and ShowCustomBuffAuraIDSuggestion(refreshPage, kind, specKey, spellIDs, suggestedID, spellName) then return true end
    return AddCustomBuffResolved(refreshPage, kind, specKey, spellIDs)
end
local function RemoveCustomBuff(refreshPage, kind, specKey, auraName)
    if not (kind and specKey and auraName and auraName ~= "") then return false end
    local cfg = SpellIndicators(kind)
    local specCfg = type(cfg.specs) == "table" and cfg.specs[specKey]
    local entry = type(specCfg) == "table" and specCfg[auraName]
    if not IsCustomBuffEntry(auraName, entry) then return false end
    local function ApplyRemove()
        specCfg[auraName] = nil
        local order = cfg.sortOrder and cfg.sortOrder[specKey]
        for i = type(order) == "table" and #order or 0, 1, -1 do if order[i] == auraName then table.remove(order, i) end end
        if CurrentSpellAura(kind) == auraName then ClearCurrentSpellAura(kind, specKey) end
        QueueSpellIndicators(kind)
    end
    M.RunWithHistory("Remove Custom Buff", "group:spellCustomRemove:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. tostring(auraName), ApplyRemove)
    RefreshSpellPage(refreshPage)
    return true
end
local function ShowCustomBuffPopup(refreshPage, kind, specKey)
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then return false end
    M.InstallStaticPopup("MSUF2_GF_SPELL_CUSTOM_BUFF_ID", {
        text = Tr("Enter buff Spell ID, link, or name"), button1 = Tr("Add"), button2 = _G.CANCEL or Tr("Cancel"), hasEditBox = true, maxLetters = 255,
        OnShow = function(self)
            local edit = self.editBox or self.EditBox
            if edit then edit:SetText(""); edit:SetFocus(); if edit.HighlightText then edit:HighlightText() end end
        end,
        OnAccept = function(self, data)
            local edit = self.editBox or self.EditBox
            if type(data) == "table" then AddCustomBuff(data.refreshPage, data.kind, data.specKey, edit and edit:GetText() or "") end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent and parent.button1 then parent.button1:Click() end
        end,
    })
    _G.StaticPopup_Show("MSUF2_GF_SPELL_CUSTOM_BUFF_ID", nil, nil, { refreshPage = refreshPage, kind = kind, specKey = specKey })
    return true
end

local function EnsureSpellSortOrder(siCfg, specKey, trackable)
    siCfg.sortOrder = siCfg.sortOrder or {}
    if type(siCfg.sortOrder[specKey]) ~= "table" then
        local order = {}
        for i = 1, #(trackable or {}) do order[#order + 1] = trackable[i].name end
        siCfg.sortOrder[specKey] = order
    end
    local order, seen = siCfg.sortOrder[specKey], {}
    for i = 1, #order do seen[order[i]] = true end
    for i = 1, #(trackable or {}) do
        local name = trackable[i] and trackable[i].name
        if name and not seen[name] then order[#order + 1], seen[name] = name, true end
    end
    return order
end
local function OrderedTrackable(runtime, siCfg, specKey)
    local source = runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    if type(source) ~= "table" then return nil end
    local specCfg = type(siCfg.specs) == "table" and siCfg.specs[specKey]
    local trackable = {}
    for i = 1, #source do
        local info = source[i]
        if info and (info.custom ~= true or (type(specCfg) == "table" and specCfg[info.name] ~= nil)) then trackable[#trackable + 1] = info end
    end
    local order = siCfg.sortOrder and siCfg.sortOrder[specKey]
    if type(order) ~= "table" or #order == 0 then return trackable end
    local byName, result = {}, {}
    for i = 1, #trackable do byName[trackable[i].name] = trackable[i] end
    for i = 1, #order do
        local info = byName[order[i]]
        if info then result[#result + 1], byName[order[i]] = info, nil end
    end
    for i = 1, #trackable do if byName[trackable[i].name] then result[#result + 1] = trackable[i] end end
    return result
end
local function InsertSpellAt(siCfg, specKey, trackable, auraName, targetSlot)
    local order = EnsureSpellSortOrder(siCfg, specKey, trackable)
    local from
    for i = 1, #order do if order[i] == auraName then from = i; break end end
    if not from then return end
    targetSlot = max(1, min(#order, tonumber(targetSlot) or from))
    if from == targetSlot then return end
    table.remove(order, from)
    if targetSlot > from then targetSlot = targetSlot - 1 end
    table.insert(order, targetSlot, auraName)
end
local function SetSpellTileBorder(tile, selected, color, scale, alpha)
    tile:SetBackdropBorderColor(selected and 0.38 or color[1] * scale, selected and 0.66 or color[2] * scale,
        selected and 1 or color[3] * scale, selected and 1 or alpha)
end

local SpellTileGrid = {}
SpellTileGrid.__index = SpellTileGrid
local SpellTileDragOnUpdate
function SpellTileGrid.New(ctx, parent, x, y, width, refreshPage)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, 150)
    frame._tiles = {}
    local self = setmetatable({
        ctx = ctx, parent = parent, frame = frame, refreshPage = refreshPage,
        label = W.LabelAt(parent, Tr("Spells for this spec"), x, y + 48, width, "GameFontNormalSmall", T.colors.accent),
        hint = W.Text(parent, Tr("Click: edit. Right-click: toggle. Drag: reorder or preview."), x, y + 27, width, T.colors.muted),
        tileSize = 52, gap = 8,
    }, SpellTileGrid)
    self.perRow = max(1, floor((width + self.gap) / (self.tileSize + self.gap)))
    return self
end
function SpellTileGrid:SlotPosition(slot)
    local stride = self.tileSize + self.gap
    return ((slot - 1) % self.perRow) * stride, -(floor((slot - 1) / self.perRow) * stride)
end
function SpellTileGrid:Position(tile, slot, specKey, trackable)
    local x, y = self:SlotPosition(slot)
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    tile._slot, tile._specKey, tile._trackable, tile._dragged = slot, specKey, trackable, false
end
function SpellTileGrid:OnEnter(tile)
    if tile._isAddTile then
        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Tr("Add custom buff"), 1, 1, 1)
        GameTooltip:AddLine(Tr("Accepts a buff Spell ID, spell link, or spell name and tracks exact Aura IDs through native AuraSlot filters."), 0.75, 0.78, 0.86)
        GameTooltip:AddLine(M.Format("%d / %d", tonumber(tile._customCount) or 0, CUSTOM_BUFF_LIMIT), 0.55, 0.70, 0.95)
        GameTooltip:Show()
        tile:SetBackdropColor(0.055, 0.075, 0.115, 1)
        tile:SetBackdropBorderColor(CUSTOM_BUFF_COLOR[1], CUSTOM_BUFF_COLOR[2], CUSTOM_BUFF_COLOR[3], 1)
        return
    end
    local info, color = tile._info or {}, tile._color or WHITE_RGB
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:AddLine(info.display or info.name, 1, 1, 1)
    if tile._customBuff then
        local cfg = SpellConfigFor(CurrentScope(), tile._specKey, tile._auraName, false)
        if cfg and cfg.spells and cfg.spells ~= "" then GameTooltip:AddLine("IDs: " .. tostring(cfg.spells), 0.55, 0.70, 0.95) end
    end
    if info.secret then GameTooltip:AddLine(Tr("Secret aura (name/fingerprint matched)"), 0.72, 0.62, 0.95) end
    GameTooltip:AddLine(Tr("Left-click to configure"), 0.75, 0.78, 0.86)
    GameTooltip:AddLine(Tr(tile._customBuff and "Right-click to remove" or "Right-click to toggle"), 0.55, 0.82, 0.55)
    GameTooltip:AddLine(Tr("Drag onto the Group Frame Preview to place and position it"), 0.42, 0.90, 1.00, true)
    GameTooltip:AddLine(Tr("Drop within this list to reorder"), 0.55, 0.70, 0.95)
    GameTooltip:Show()
    tile:SetBackdropColor(0.070, 0.085, 0.125, 1)
    tile:SetBackdropBorderColor(color[1], color[2], color[3], 1)
end
function SpellTileGrid:OnLeave(tile)
    GameTooltip:Hide()
    tile:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
    SetSpellTileBorder(tile, not tile._isAddTile and tile._auraName == CurrentSpellAura(CurrentScope()),
        tile._color or WHITE_RGB, tile._isAddTile and 0.72 or 0.62, 0.82)
end
function SpellTileGrid:OnDragStart(tile)
    if tile._isAddTile then return end
    GameTooltip:Hide()
    tile._dragged = true
    tile:StartMoving()
    tile:SetFrameStrata("TOOLTIP")
    local preview = M.GroupPreview
    if preview and type(preview.UpdateSpellDropTarget) == "function" then
        preview.UpdateSpellDropTarget(true, tile._info and (tile._info.display or tile._info.name) or tile._auraName)
    end
    tile:SetScript("OnUpdate", SpellTileDragOnUpdate)
end
function SpellTileGrid:OnDragStop(tile)
    if tile._isAddTile then return end
    tile:SetScript("OnUpdate", nil)
    tile:StopMovingOrSizing()
    local strata = self.frame:GetFrameStrata()
    if issecretvalue(strata) ~= true and strata then tile:SetFrameStrata(strata) end
    local preview = M.GroupPreview
    local dropped = preview and type(preview.DropSpellIndicatorAtCursor) == "function"
        and preview.DropSpellIndicatorAtCursor(tile._specKey, tile._auraName) == true
    if preview and type(preview.UpdateSpellDropTarget) == "function" then preview.UpdateSpellDropTarget(false) end
    if dropped then
        if M.Refresh then M.Refresh(self.ctx) else self.refreshPage() end
        return
    end
    local hostLeft, hostTop, cx, cy = self.frame:GetLeft(), self.frame:GetTop(), tile:GetCenter()
    if not (hostLeft and hostTop and cx and cy) then return end
    local bestSlot, bestDist = tile._slot or 1, math.huge
    for slot = 1, #(tile._trackable or {}) do
        local x, y = self:SlotPosition(slot)
        local dx, dy = cx - (hostLeft + x + self.tileSize / 2), cy - (hostTop + y - self.tileSize / 2)
        local distance = dx * dx + dy * dy
        if distance < bestDist then bestSlot, bestDist = slot, distance end
    end
    local kind = CurrentScope()
    local function Reorder()
        InsertSpellAt(SpellIndicators(kind), tile._specKey, tile._trackable, tile._auraName, bestSlot)
        QueueSpellIndicators(kind)
    end
    M.RunWithHistory("Spell Indicator Order", "group:spellOrder:" .. tostring(kind) .. ":" .. tostring(tile._specKey), Reorder)
    if M.Refresh then M.Refresh(self.ctx) else self.refreshPage() end
end
function SpellTileGrid:OnMouseUp(tile, button)
    if SpellIndicators(CurrentScope()).enabled ~= true then return end
    if tile._suppressNextClick then tile._suppressNextClick = nil; tile._dragged = false; return end
    if tile._dragged then tile._dragged = false; return end
    local kind = CurrentScope()
    if tile._isAddTile then
        if button == "LeftButton" then ShowCustomBuffPopup(self.refreshPage, kind, tile._specKey) end
        return
    end
    if button == "RightButton" then
        if tile._customBuff then
            RemoveCustomBuff(self.refreshPage, kind, tile._specKey, tile._auraName)
        else
            local function Toggle()
                local cfg = SpellConfigFor(kind, tile._specKey, tile._auraName, true)
                if cfg then cfg.enabled = cfg.enabled == false and true or false end
                QueueSpellIndicators(kind)
            end
            M.RunWithHistory("Toggle Spell Indicator", "group:spellToggle:" .. tostring(kind) .. ":" .. tostring(tile._specKey) .. ":" .. tostring(tile._auraName), Toggle)
        end
    else
        SetCurrentSpellAura(kind, tile._auraName)
        M.CallIf(RefreshGFPreview)
    end
    if M.Refresh then M.Refresh(self.ctx) else self.refreshPage() end
end
local function SpellTileOnEnter(tile) tile._grid:OnEnter(tile) end
local function SpellTileOnLeave(tile) tile._grid:OnLeave(tile) end
local function SpellTileOnMouseUp(tile, button) tile._grid:OnMouseUp(tile, button) end
SpellTileDragOnUpdate = function(tile)
    local preview = M.GroupPreview
    if preview and type(preview.UpdateSpellDropTarget) == "function" then
        preview.UpdateSpellDropTarget(true, tile._info and (tile._info.display or tile._info.name) or tile._auraName)
    end
end
local function StopSpellTilePendingDrag(tile)
    tile._pendingDrag = nil
    tile._dragStartCursorX, tile._dragStartCursorY = nil, nil
    tile:SetScript("OnUpdate", nil)
end
local function SpellTilePendingDragOnUpdate(tile)
    if not tile._pendingDrag then return StopSpellTilePendingDrag(tile) end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        StopSpellTilePendingDrag(tile)
        return
    end
    local x, y = GetCursorPosition()
    if not (x and y and tile._dragStartCursorX and tile._dragStartCursorY) then return end
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local dx, dy = (x - tile._dragStartCursorX) / scale, (y - tile._dragStartCursorY) / scale
    if (dx * dx + dy * dy) < 36 then return end
    StopSpellTilePendingDrag(tile)
    tile._grid:OnDragStart(tile)
end
local function SpellTileOnMouseDown(tile, button)
    if button ~= "LeftButton" or tile._isAddTile then return end
    tile._pendingDrag = true
    tile._dragStartCursorX, tile._dragStartCursorY = GetCursorPosition()
    tile:SetScript("OnUpdate", SpellTilePendingDragOnUpdate)
end
local function SpellTileInputMouseUp(tile, button)
    if button ~= "LeftButton" then return end
    StopSpellTilePendingDrag(tile)
    if tile._dragged then
        tile._suppressNextClick = true
        tile._grid:OnDragStop(tile)
    end
end
local function SpellTileOnHide(tile)
    StopSpellTilePendingDrag(tile)
    if tile._dragged then
        tile:StopMovingOrSizing()
        tile._dragged = false
        local preview = M.GroupPreview
        if preview and type(preview.UpdateSpellDropTarget) == "function" then preview.UpdateSpellDropTarget(false) end
    end
end
function SpellTileGrid:EnsureTile(index)
    local tile = self.frame._tiles[index]
    if tile then return tile end
    tile = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
    tile:SetSize(self.tileSize, self.tileSize)
    tile:SetMovable(true)
    tile:EnableMouse(true)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    tile:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetSize(36, 36)
    tile.icon:SetPoint("TOP", tile, "TOP", 0, -3)
    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local addMark = CreateFrame("Frame", nil, tile)
    addMark:SetSize(20, 20)
    addMark:SetPoint("CENTER", tile.icon, "CENTER")
    addMark.horizontal = addMark:CreateTexture(nil, "OVERLAY")
    addMark.horizontal:SetSize(16, 3)
    addMark.horizontal:SetPoint("CENTER")
    addMark.vertical = addMark:CreateTexture(nil, "OVERLAY")
    addMark.vertical:SetSize(3, 16)
    addMark.vertical:SetPoint("CENTER")
    function addMark:SetText() end
    function addMark:SetTextColor(r, g, b, a)
        self.horizontal:SetColorTexture(r, g, b, a)
        self.vertical:SetColorTexture(r, g, b, a)
    end
    tile.addText = addMark
    tile.addText:SetTextColor(0.70, 0.90, 1, 1)
    tile.addText:Hide()
    tile.label = tile:CreateFontString(nil, "OVERLAY")
    tile.label:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE")
    tile.label:SetPoint("BOTTOM", tile, "BOTTOM", 0, 2)
    tile.label:SetWidth(self.tileSize - 4)
    tile.label:SetMaxLines(1)
    tile.label:SetJustifyH("CENTER")
    tile._grid = self
    tile:SetScript("OnEnter", SpellTileOnEnter)
    tile:SetScript("OnLeave", SpellTileOnLeave)
    tile:SetScript("OnMouseDown", SpellTileOnMouseDown)
    tile:SetScript("OnMouseUp", SpellTileInputMouseUp)
    tile:SetScript("OnClick", SpellTileOnMouseUp)
    tile:SetScript("OnHide", SpellTileOnHide)
    tile._msuf2CommandAction = {
        kind = "button",
        valueKind = "text",
        set = function(value)
            if tile._isAddTile then
                return AddCustomBuff(self.refreshPage, CurrentScope(), tile._specKey, value)
            end
            return tile._grid:OnMouseUp(tile, "LeftButton")
        end,
    }
    RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(index), "Tracked spell tile " .. tostring(index), "button", "action")
    self.frame._tiles[index] = tile
    return tile
end
function SpellTileGrid:Refresh()
    local kind = CurrentScope()
    local indicatorsOn = SpellIndicators(kind).enabled == true
    local runtime, specKey = SpellIndicatorRuntime(), EffectiveSpellSpec(kind)
    if specKey then EnsureSpellDefaults(kind, specKey) end
    local siCfg = SpellIndicators(kind)
    local trackable = specKey and OrderedTrackable(runtime, siCfg, specKey) or {}
    local selected = CurrentSpellAura(kind)
    if self.frame.SetAlpha then self.frame:SetAlpha(indicatorsOn and 1 or 0.45) end
    if self.label and self.label.SetTextColor then
        local color = indicatorsOn and T.colors.accent or T.colors.dim
        self.label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    for i = 1, #self.frame._tiles do self.frame._tiles[i]:Hide() end
    trackable = type(trackable) == "table" and trackable or {}
    local specCfg = type(siCfg.specs) == "table" and specKey and siCfg.specs[specKey]
    local customCount = CountCustomBuffs(specCfg)
    self.hint:SetText(Tr(#trackable == 0 and "No spells for this spec." or "Click: edit. Right-click: toggle. Drag: reorder or preview."))
    if self.hint.SetTextColor then
        local color = indicatorsOn and T.colors.muted or T.colors.dim
        self.hint:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    for i = 1, #trackable do
        local info, tile = trackable[i], self:EnsureTile(i)
        self:Position(tile, i, specKey, trackable)
        tile._auraName, tile._info, tile._isAddTile = info.name, info, false
        RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(i),
            "Tracked spell " .. tostring(info.display or info.name or i), "button", "action")
        local auraCfg = SpellConfigFor(kind, specKey, info.name, false)
        tile._customBuff = IsCustomBuffEntry(info.name, auraCfg) or info.custom == true
        local tileEnabled = indicatorsOn and not (auraCfg and auraCfg.enabled == false)
        local color = info.color or { 0.55, 0.65, 0.85 }
        tile._color = color
        tile.addText:Hide()
        tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tile.icon:SetVertexColor(1, 1, 1, 1)
        if runtime and type(runtime.GetAuraIcon) == "function" then
            if type(MSUF_SetIconTexture) == "function" then MSUF_SetIconTexture(tile.icon, runtime.GetAuraIcon(specKey, info.name), "")
            else tile.icon:SetTexture(runtime.GetAuraIcon(specKey, info.name)) end
        else
            tile.icon:SetTexture(136243)
        end
        tile:EnableMouse(indicatorsOn)
        tile.icon:SetDesaturated(not tileEnabled)
        tile.icon:SetAlpha(tileEnabled and 1 or 0.35)
        tile.label:SetText(info.display or info.name)
        local textAlpha = tileEnabled and 0.92 or 0.45
        tile.label:SetTextColor(textAlpha, textAlpha, textAlpha, 1)
        SetSpellTileBorder(tile, indicatorsOn and info.name == selected, color, 0.42, indicatorsOn and 0.82 or 0.45)
        tile:Show()
    end
    if specKey and customCount < CUSTOM_BUFF_LIMIT then
        local slot, tile = #trackable + 1, self:EnsureTile(#trackable + 1)
        self:Position(tile, slot, specKey, trackable)
        tile._auraName, tile._info, tile._isAddTile, tile._customBuff = nil, nil, true, false
        RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(slot),
            "Add custom group spell indicator", "button", "action")
        tile._customCount, tile._color = customCount, CUSTOM_BUFF_COLOR
        tile.icon:SetTexture("Interface\\Buttons\\WHITE8x8")
        tile.icon:SetTexCoord(0, 1, 0, 1)
        tile.icon:SetVertexColor(0.055, 0.150, 0.220, indicatorsOn and 0.95 or 0.40)
        tile.icon:SetDesaturated(false)
        tile.icon:SetAlpha(indicatorsOn and 0.95 or 0.35)
        tile.addText:SetText("+")
        tile.addText:SetTextColor(0.70, 0.90, 1, indicatorsOn and 1 or 0.45)
        tile.addText:Show()
        tile.label:SetText(M.Format("%d/%d", customCount, CUSTOM_BUFF_LIMIT))
        tile.label:SetTextColor(indicatorsOn and 0.70 or 0.45, indicatorsOn and 0.90 or 0.45, indicatorsOn and 1 or 0.45, 1)
        tile:EnableMouse(indicatorsOn)
        SetSpellTileBorder(tile, false, CUSTOM_BUFF_COLOR, 0.72, indicatorsOn and 0.82 or 0.45)
        tile:Show()
    end
    local tileCount = #trackable + ((specKey and customCount < CUSTOM_BUFF_LIMIT) and 1 or 0)
    local rows = max(1, floor((max(1, tileCount) + self.perRow - 1) / self.perRow))
    self.frame:SetHeight((rows * (self.tileSize + self.gap)) - self.gap)
    return rows
end

GP.BuildSpellIndicatorStyleSection = function(ctx, b)
    local section = b:CollapsibleSection("si_style", Tr("Spell Icon Style"), 844, false)
    local sectionW = section._msuf2Width or ctx.width or 720
    local gap, leftX = 28, 30
    local innerW = max(320, sectionW - 60)
    local leftW = max(240, min(370, floor((innerW - gap) * 0.46)))
    local rightX = leftX + leftW + gap
    local rightW = max(240, min(390, innerW - leftW - gap))
    W.ControlCard(section, Tr("Frame Basics"), nil, leftX - 14, -38, leftW + 28, 322)
    W.ControlCard(section, Tr("Cooldown Text"), nil, rightX - 14, -38, rightW + 28, 430)
    W.ControlCard(section, Tr("Stack Count"), nil, leftX - 14, -376, leftW + 28, 296)
    W.ControlCard(section, Tr("Duration Bar"), nil, rightX - 14, -484, rightW + 28, 312)

    local function Style()
        local si = SpellIndicators(CurrentScope())
        if type(si.style) ~= "table" then si.style = {} end
        return si.style
    end
    local function ApplyStyle()
        QueueSpellIndicators(CurrentScope(), "auras")
    end
    local function StyleMeta(path, step)
        local meta = step and StepMeta(ctx, path, step) or ControlMeta(ctx, path)
        local suffix = path == "spell.icon_zoom" and "iconZoom"
            or (path == "spell.icon_scale" and "iconScale" or path:match("^spell%.style%.(.+)$"))
        if suffix then
            meta.assistantDisposition = "dynamic"
            meta.assistantDispositionReason = "This setting targets the dedicated Spell Icon Style in the selected Group scope."
            -- Scope changes refresh this page in place, so a key captured while
            -- building would become stale. The widget command resolves
            -- CurrentScope() at execution time, matching every other Group control.
            meta.assistantSettingKeys = nil
            meta.assistantSettingKeyPatterns = nil
        end
        return meta
    end
    local controls = {}
    local RefreshStyleState = M.RefreshProxy()
    local function Track(control)
        controls[#controls + 1] = control
        return control
    end
    local function BindNumber(label, x, y, width, minValue, maxValue, step, key, default, path)
        local control = Track(W.Slider(section, Tr(label), minValue, maxValue, step, width))
        local meta = StyleMeta(path or ("spell.style." .. key), step)
        M.BindNumberWidget(ctx, control,
            function() return tonumber(Style()[key]) or default end,
            function(value)
                Style()[key] = tonumber(value) or default
                ApplyStyle()
            end,
            default, meta)
        W.MoveWidget(control, section, x, y, width, "LEFT")
        return control
    end
    local function BindBool(label, x, y, width, key, default)
        local control = Track(W.ToggleAt(section, Tr(label), x, y, width))
        local meta = StyleMeta("spell.style." .. key)
        M.BindBoolWidget(ctx, control,
            function()
                local value = Style()[key]
                if value == nil then return default == true end
                return value == true
            end,
            function(value)
                Style()[key] = value == true
                ApplyStyle()
                RefreshStyleState()
            end,
            meta)
        return control
    end
    local function BindChoice(label, x, y, width, values, key, default)
        local control = Track(W.Dropdown(section, Tr(label), values, width))
        local meta = StyleMeta("spell.style." .. key)
        M.BindDropdownWidget(ctx, control,
            function() return Style()[key] or default end,
            function(value)
                Style()[key] = value or default
                ApplyStyle()
            end,
            meta)
        W.MoveWidget(control, section, x, y, width, "LEFT")
        return control
    end

    local iconZoom = Track(W.Slider(section, Tr("Icon Zoom (%)"), 100, 200, 1, leftW))
    local metadata = StyleMeta("spell.icon_zoom", 1)
    M.BindNumberWidget(ctx, iconZoom,
        function() return tonumber(SpellIndicators(CurrentScope()).iconZoom) or 100 end,
        function(value)
            SpellIndicators(CurrentScope()).iconZoom = tonumber(value) or 100
            ApplyStyle()
        end,
        100, metadata)
    W.MoveWidget(iconZoom, section, leftX, -72, leftW, "LEFT")

    local iconScale = Track(W.Slider(section, Tr("Icon Scale (%)"), 20, 300, 1, leftW))
    do
        local pendingApply, pendingScope, releaseScheduled
        local meta = StyleMeta("spell.icon_scale", 1)
        local function CombatLocked()
            if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() == true end
            return (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true
        end
        local function RefreshPreviewOnly(scope)
            if CombatLocked() then return false end
            if type(RefreshGFPreview) == "function" then RefreshGFPreview(scope or CurrentScope(), { spellOnly = true }) end
            return true
        end
        local function FlushRuntime()
            if not pendingApply then return end
            if CombatLocked() then releaseScheduled = nil; return false end
            local scope = pendingScope or CurrentScope()
            pendingApply, pendingScope, releaseScheduled = nil, nil, nil
            QueueSpellIndicators(scope, "auras")
            return true
        end
        local function ScheduleRelease()
            if not pendingApply or releaseScheduled or CombatLocked() then return end
            releaseScheduled = true
            if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, FlushRuntime) else FlushRuntime() end
        end
        M.BindNumberWidget(ctx, iconScale,
            function() return tonumber(SpellIndicators(CurrentScope()).iconScale) or 100 end,
            function(value)
                value = floor((tonumber(value) or 100) + 0.5)
                local scope = CurrentScope()
                if pendingApply and pendingScope ~= scope then FlushRuntime() end
                local si = SpellIndicators(scope)
                if si.iconScale == value then return end
                si.iconScale = value
                pendingApply = true
                pendingScope = scope
                if iconScale._msuf2SliderActive == true or releaseScheduled then RefreshPreviewOnly(scope) else FlushRuntime() end
            end,
            100, meta)
        iconScale:HookScript("OnMouseUp", ScheduleRelease)
        iconScale:HookScript("OnHide", FlushRuntime)
        iconScale:HookScript("OnShow", FlushRuntime)
    end
    W.MoveWidget(iconScale, section, leftX, -128, leftW, "LEFT")

    local opacity = Track(W.Slider(section, Tr("Opacity"), 10, 100, 5, leftW))
    local metadata = StyleMeta("spell.style.alpha", 5)
    M.BindNumberWidget(ctx, opacity,
        function() return floor(((tonumber(Style().alpha) or 1) * 100) + 0.5) end,
        function(value)
            Style().alpha = min(1, max(0.1, (tonumber(value) or 100) / 100))
            ApplyStyle()
        end,
        100, metadata)
    W.MoveWidget(opacity, section, leftX, -184, leftW, "LEFT")
    local tooltip = BindBool("Show Tooltip", leftX, -240, leftW, "showTooltip", true)

    local showCooldownText = BindBool("Show Cooldown Text", rightX, -72, rightW, "showCooldownText", true)
    local showCooldownSwipe = BindBool("Show Cooldown Swipe", rightX, -104, rightW, "showCooldownSwipe", true)
    local cooldownSize = BindNumber("Cooldown Font", rightX, -148, rightW, 6, 24, 1, "cooldownSize", 8)
    local cooldownAnchor = BindChoice("Cooldown Anchor", rightX, -204, rightW, STATUS_ICON_ANCHORS, "cooldownAnchor", "CENTER")
    local halfRight = max(100, floor((rightW - 12) / 2))
    local cooldownX = BindNumber("Cooldown X", rightX, -260, halfRight, -40, 40, 1, "cooldownX", 0)
    local cooldownY = BindNumber("Cooldown Y", rightX + halfRight + 12, -260, halfRight, -40, 40, 1, "cooldownY", 0)
    local swipeDirection = Track(W.Dropdown(section, Tr("Swipe Direction"), VT("NORMAL", "Normal", "REVERSE", "Reverse"), rightW))
    local metadata = StyleMeta("spell.style.cooldownSwipeReverse")
    M.BindDropdownWidget(ctx, swipeDirection,
        function() return Style().cooldownSwipeReverse == true and "REVERSE" or "NORMAL" end,
        function(value)
            Style().cooldownSwipeReverse = value == "REVERSE"
            ApplyStyle()
        end,
        metadata)
    W.MoveWidget(swipeDirection, section, rightX, -316, rightW, "LEFT")
    local decimals = BindNumber("Decimals below sec", rightX, -372, rightW, 0, 30, 1, "cooldownDecimalSeconds", 3)

    local showStacks = BindBool("Show Stack Count", leftX, -410, leftW, "showStacks", true)
    local stackSize = BindNumber("Stack Font", leftX, -452, leftW, 6, 24, 1, "stackSize", 10)
    local stackAnchor = BindChoice("Stack Anchor", leftX, -508, leftW, STATUS_ICON_ANCHORS, "stackAnchor", "BOTTOMRIGHT")
    local halfLeft = max(100, floor((leftW - 12) / 2))
    local stackX = BindNumber("Stack X", leftX, -564, halfLeft, -40, 40, 1, "stackX", 0)
    local stackY = BindNumber("Stack Y", leftX + halfLeft + 12, -564, halfLeft, -40, 40, 1, "stackY", 0)

    local showDurationBar = BindBool("Show Duration Bar", rightX, -520, rightW, "showDurationBar", false)
    local durationHeight = BindNumber("Height", rightX, -562, rightW, 1, 16, 1, "durationBarHeight", 2)
    local durationDisplay = BindChoice("Display", rightX, -618, rightW,
        VT("BAR_ONLY", "Bar Only", "OVERLAY", "Icon + Bar"), "durationBarDisplay", "BAR_ONLY")
    local durationPosition = BindChoice("Position", rightX, -674, halfRight,
        VT("BOTTOM", "Bottom", "TOP", "Top"), "durationBarPosition", "BOTTOM")
    local durationDirection = BindChoice("Fill Mode", rightX + halfRight + 12, -674, halfRight,
        VT("REMAINING", "Remaining", "ELAPSED", "Elapsed"), "durationBarDirection", "REMAINING")
    W.Text(section, Tr("Shape, border and shadow: Appearance > Aura Style > Buffs. All controls here remain Group-scope aware."),
        leftX, -814, innerW, T.colors.muted)

    if M.AddTooltip then
        M.AddTooltip(tooltip, "Spell Icon tooltip", "Controls native Aura tooltips for Spell Icons only.", { hook = true })
        M.AddTooltip(decimals, "Cooldown text format", "Below this value, remaining whole seconds may show one decimal place. Set 0 for whole seconds only.", { hook = true })
    end

    RefreshStyleState = RefreshStyleState(function()
        local si = SpellIndicators(CurrentScope())
        local style = Style()
        local enabled = si.enabled == true
        SetOptionsEnabled(controls, enabled)
        SetManyEnabled(enabled and style.showCooldownText ~= false, cooldownSize, cooldownAnchor, cooldownX, cooldownY, decimals)
        SetOptionEnabled(swipeDirection, enabled and style.showCooldownSwipe ~= false)
        SetManyEnabled(enabled and style.showStacks ~= false, stackSize, stackAnchor, stackX, stackY)
        SetManyEnabled(enabled and style.showDurationBar == true, durationHeight, durationDisplay, durationPosition, durationDirection)
        local scope = CurrentScope()
        local scopeLabel = scope == "party" and "Party" or (scope == "mythicraid" and "Mythic Raid" or "Raid")
        SetSectionBadgesAndStatus(section, {
            { text = scopeLabel, kind = "info", important = true },
            { text = M.Format("Zoom %d%%", floor((tonumber(si.iconZoom) or 100) + 0.5)), kind = "info" },
            { text = "Buff Appearance", kind = "accent" },
            OnOffBadge(enabled, "Active", "Inactive"),
        })
    end)
    TrackSectionRefresh(ctx, section, RefreshStyleState)
end

local function BuildSpellIndicatorsSection(ctx, b, RefreshPage)
    local spells = b:CollapsibleSection("si", Tr("Spell Indicators"), 848, false)
    local siW = spells._msuf2Width or ctx.width or 720
    local siGap = 28
    local siLeftX = 30
    local siInnerW = max(320, siW - 60)
    local siLeftW = max(240, min(370, floor((siInnerW - siGap) * 0.46)))
    local siRightX = siLeftX + siLeftW + siGap
    local siRightW = max(240, min(390, siInnerW - siLeftW - siGap))
    local spellSetCard, placedIndicatorCard, frameHighlightCard
    do
        spellSetCard = W.ControlCard(spells, Tr("Choose Spells"), nil, siLeftX - 14, -38, siLeftW + 28, 404)
        W.ControlCard(spells, Tr("Edit Spell"), nil, siRightX - 14, -38, siRightW + 28, 404)
        placedIndicatorCard = W.ControlCard(spells, Tr("Show on Frame"), nil, siLeftX - 14, -456, siLeftW + 28, 560)
        frameHighlightCard = W.ControlCard(spells, Tr("Highlight Health Bar"), nil, siRightX - 14, -456, siRightW + 28, 468)
    end
    local RefreshSpellIndicatorState = M.RefreshProxy()
    local function RequestSpellControlRefresh(reason)
        if M.RequestRefresh then
            return M.RequestRefresh(ctx, reason or "gf-spell-indicators")
        elseif M.Refresh then
            return M.Refresh(ctx)
        end
        return RefreshPage()
    end
    local siEnable = W.SwitchAt(spells, Tr("Show spell indicators"), siLeftX, -72, siLeftW)
    siEnable._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, siEnable,
        function()
            if SPELL_INDICATORS_121_PTR_DISABLED then return false end
            return SpellIndicators(CurrentScope()).enabled == true
        end,
        function(value)
            if SPELL_INDICATORS_121_PTR_DISABLED then
                SpellIndicators(CurrentScope()).enabled = false
                QueueSpellIndicators(CurrentScope())
                RefreshSpellIndicatorState()
                return
            end
            SpellIndicators(CurrentScope()).enabled = value and true or false
            EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
            QueueSpellIndicators(CurrentScope())
            RefreshSpellIndicatorState()
        end,
        ControlMeta(ctx, "spell.enabled"))
    local function SelectedSpellConfigTable()
        return CurrentSpellConfig(CurrentScope(), true) or SpellIndicators(CurrentScope())
    end
    local siLayer = BindNestedSlider(ctx, W.Slider(spells, Tr("Layer (0-30)"), 0, 30, 1, siRightW), SelectedSpellConfigTable, "layer", 9, "visual", "spell.selected.layer")
    W.MoveWidget(siLayer, spells, siRightX, -72, siRightW, "LEFT")
    local specDrop = W.Dropdown(spells, Tr("Spec"), SpellSpecValues, siLeftW)
    M.BindDropdownWidget(ctx, specDrop,
        function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
            CurrentSpellAura(kind)
            QueueSpellIndicators(kind)
            M.CallIf(RefreshGFPreview)
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-spec")
        end,
        ControlMeta(ctx, "spell.spec"))
    W.MoveWidget(specDrop, spells, siLeftX, -116, siLeftW, "LEFT")
    local function PreviewAllSpecIconsEnabled()
        local state = M.gfPreviewAllSpecSpellIcons
        return type(state) == "table" and state[CurrentScope()] == true
    end
    local previewAll = T.Button(spells, Tr("Preview all spells"), siLeftW, 28)
    if T.CenterButtonLabel then T.CenterButtonLabel(previewAll) end
    previewAll:SetPoint("TOPLEFT", spells, "TOPLEFT", siLeftX, -162)
    local function RefreshPreviewAllButton()
        local enabled = PreviewAllSpecIconsEnabled()
        if T.ApplyButtonRole then T.ApplyButtonRole(previewAll, enabled and "success" or "danger") end
        if previewAll.SetActive then previewAll:SetActive(true) end
    end
    local function SetPreviewAllSpecIcons(enabled)
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false end
        if (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true then return false end
        local kind = CurrentScope()
        M.gfPreviewAllSpecSpellIcons = M.gfPreviewAllSpecSpellIcons or {}
        M.gfPreviewAllSpecSpellIcons[kind] = enabled == true or nil
        RefreshPreviewAllButton()
        M.CallIf(RefreshGFPreview)
        RefreshSpellIndicatorState()
        return PreviewAllSpecIconsEnabled() == (enabled == true)
    end
    previewAll:SetScript("OnClick", function()
        SetPreviewAllSpecIcons(not PreviewAllSpecIconsEnabled())
    end)
    previewAll._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = PreviewAllSpecIconsEnabled,
        set = SetPreviewAllSpecIcons,
    }
    RegisterControl(previewAll, ctx, "spell.preview_all", "Preview all spells", "button", "ephemeral")
    if M.AddTooltip then
        M.AddTooltip(previewAll, "Preview all spells", "On previews every enabled spell of every tracked spec, including spells that only draw a frame effect. Off previews only the selected spell.", { hook = true })
    end
    RefreshPreviewAllButton()
    local multiSpecDrop = W.Dropdown(spells, Tr("Multi-Spec Entry"), function() return SpellTrackedSpecValues() end, siRightW)
    M.BindDropdownWidget(ctx, multiSpecDrop,
        function() return CurrentSpellMultiSpec(CurrentScope()) end,
        function(value)
            local kind = CurrentScope()
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[kind] = value or ""
            EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
            CurrentSpellAura(kind)
            QueueSpellIndicators(kind)
            M.CallIf(RefreshGFPreview)
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-multi-spec")
        end,
        ControlMeta(ctx, "spell.multi_spec.selector", "ephemeral"))
    W.MoveWidget(multiSpecDrop, spells, siRightX, -190, siRightW, "LEFT")
    local multiSpecEnabled = W.ToggleAt(spells, Tr("Track selected multi spec"), siRightX, -250, siRightW)
    local allSpecsHint = W.Text(spells, Tr("Shared entries apply to every spec."), siRightX, -250, siRightW, T.colors.accent)
    if allSpecsHint.SetWordWrap then allSpecsHint:SetWordWrap(true) end
    allSpecsHint:Hide()
    M.BindBoolWidget(ctx, multiSpecEnabled,
        function()
            local cfg = SpellIndicators(CurrentScope())
            local specKey = CurrentSpellMultiSpec(CurrentScope())
            if IsAllSpecsSpellSpec(specKey) then return true end
            return cfg.spec == "multi" and specKey ~= "" and cfg.multiSpecs and cfg.multiSpecs[specKey] == true
        end,
        function(value)
            local kind = CurrentScope()
            local cfg = SpellIndicators(kind)
            local specKey = CurrentSpellMultiSpec(kind)
            if specKey == "" or IsAllSpecsSpellSpec(specKey) then return end
            cfg.multiSpecs = cfg.multiSpecs or {}
            cfg.multiSpecs[specKey] = value and true or nil
            QueueSpellIndicators(kind)
            M.CallIf(RefreshGFPreview)
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-multi-track")
        end,
        ControlMeta(ctx, "spell.multi_spec.tracked"))
    local spellGrid = SpellTileGrid.New(ctx, spells, siLeftX, -254, siLeftW, RefreshPage)
    local auraDrop = W.Dropdown(spells, Tr("Choose spell"), function() return SpellAuraValues(CurrentScope()) end, siRightW)
    M.BindDropdownWidget(ctx, auraDrop,
        function() return CurrentSpellAura(CurrentScope()) end,
        function(value)
            SetCurrentSpellAura(CurrentScope(), value)
            M.CallIf(RefreshGFPreview)
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-selection")
        end,
        ControlMeta(ctx, "spell.selected_aura", "ephemeral"))
    W.MoveWidget(auraDrop, spells, siRightX, -282, siRightW, "LEFT")
    local spellEnabled = W.SwitchAt(spells, Tr("Show this spell"), siRightX, -342, siRightW)
    M.BindBoolWidget(ctx, spellEnabled,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.enabled ~= false or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.enabled = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end,
        ControlMeta(ctx, "spell.selected.enabled"))
    local customSpellIDs = W.TextInput(spells, Tr("Aura Spell IDs"), siRightW)
    M.BindTextInput(ctx, customSpellIDs,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.spells or ""
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if not cfg then return end
            local ids = CustomBuffSpellIDs(value)
            if ids then
                cfg.spells = CustomBuffSpellIDListText(ids)
            else
                cfg.spells = ""
            end
            QueueSpellIndicators(CurrentScope())
        end,
        true,
        ControlMeta(ctx, "spell.selected.spell_ids"))
    W.MoveWidget(customSpellIDs, spells, siRightX, -208, siRightW)
    local onlyMine = W.ToggleAt(spells, Tr("Only show my casts"), siRightX, -374, siRightW)
    M.BindBoolWidget(ctx, onlyMine,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            if not cfg then return false end
            if cfg.custom == true and cfg._msufCustomOnlyOwnExplicit ~= true then return false end
            return cfg.onlyOwn ~= false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then
                if cfg.custom == true then cfg._msufCustomOnlyOwnExplicit = true end
                cfg.onlyOwn = value and true or false
            end
            QueueSpellIndicators(CurrentScope())
        end,
        ControlMeta(ctx, "spell.selected.only_mine"))
    local autoBlacklist = W.ToggleAt(spells, Tr("Hide duplicate Buff icon"), siRightX, -406, siRightW)
    M.BindBoolWidget(ctx, autoBlacklist,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            if CurrentSpellIsExternalDefensive(CurrentScope())
                and ExternalAutoBlacklistActive(CurrentScope()) then
                return true
            end
            return cfg and cfg.autoBlacklist == true or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.autoBlacklist = value and true or nil end
            QueueSpellIndicators(CurrentScope())
        end,
        ControlMeta(ctx, "spell.selected.auto_blacklist"))
    if M.AddTooltip then
        M.AddTooltip(autoBlacklist, "Hide duplicate Buff icon",
            "Hides this aura from the regular Buff icons while this spell indicator is enabled. External-defensive Spell Icons follow the active External Defensives container's Auto-blacklist from Buffs setting.",
            { hook = true, titleAsLine = true })
    end
    local function BindPlacedDropdown(label, values, key, default, y, afterSet)
        local control = W.Dropdown(spells, Tr(label), values, siLeftW)
        M.BindDropdownWidget(ctx, control,
            function()
                local placed = PlacedConfig(CurrentScope(), false)
                return placed and placed[key] or default
            end,
            function(value)
                local placed = PlacedConfig(CurrentScope(), true)
                if placed then placed[key] = value or default end
                QueueSpellIndicators(CurrentScope())
                if afterSet then afterSet() end
            end,
            ControlMeta(ctx, "spell.placed." .. tostring(key)))
        W.MoveWidget(control, spells, siLeftX, y, siLeftW, "LEFT")
        return control
    end
    local function BindConfigSlider(configFn, x, width, label, minValue, maxValue, step, key, default, y)
        local control = W.Slider(spells, Tr(label), minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function()
                local cfg = configFn(CurrentScope(), false)
                return tonumber(cfg and cfg[key]) or default
            end,
            function(value)
                local cfg = configFn(CurrentScope(), true)
                if cfg then cfg[key] = floor((tonumber(value) or default) + 0.5) end
                QueueSpellIndicators(CurrentScope())
            end,
            default, StepMeta(ctx, "spell." .. (configFn == PlacedConfig and "placed" or "frame") .. "." .. tostring(key), step))
        W.MoveWidget(control, spells, x, y, width, "LEFT")
        return control
    end
    local function BindPlacedSlider(label, minValue, maxValue, step, key, default, y)
        return BindConfigSlider(PlacedConfig, siLeftX, siLeftW, label, minValue, maxValue, step, key, default, y)
    end
    local function BindPlacedToggle(label, key, defaultWhenPlaced, y, x, width, afterSet)
        x, width = x or siRightX, width or siRightW
        local control = W.ToggleAt(spells, Tr(label), x, y, width)
        M.BindBoolWidget(ctx, control,
            function()
                local placed = PlacedConfig(CurrentScope(), false)
                if not placed then return false end
                local value = placed[key]
                if value == nil then return defaultWhenPlaced and true or false end
                return value and true or false
            end,
            function(value)
                local placed = PlacedConfig(CurrentScope(), true)
                if placed then placed[key] = value and true or false end
                QueueSpellIndicators(CurrentScope())
                if afterSet then afterSet() end
            end,
            ControlMeta(ctx, "spell.placed." .. tostring(key)))
        W.MoveWidget(control, spells, x, y, width, "LEFT")
        return control
    end
    local function BindFrameSlider(label, minValue, maxValue, step, key, default, y)
        return BindConfigSlider(FrameEffectConfig, siRightX, siRightW, label, minValue, maxValue, step, key, default, y)
    end
    local function BindSpellSubType(label, values, x, y, width, field, applyDefaults, afterSet)
        local control = W.Dropdown(spells, Tr(label), values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local cfg = CurrentSpellConfig(CurrentScope(), false)
                local sub = cfg and cfg[field]
                return type(sub) == "table" and sub.type or "none"
            end,
            function(value)
                local cfg = CurrentSpellConfig(CurrentScope(), true)
                if not cfg then return end
                if value == "none" then
                    cfg[field] = false
                else
                    cfg[field] = type(cfg[field]) == "table" and cfg[field] or {}
                    cfg[field].type = value
                    if applyDefaults then applyDefaults(cfg[field]) end
                end
                QueueSpellIndicators(CurrentScope())
                if afterSet then afterSet() end
            end,
            ControlMeta(ctx, "spell.selected." .. tostring(field) .. ".type"))
        W.MoveWidget(control, spells, x, y, width, "LEFT")
        return control
    end
    local placedType = BindSpellSubType("Display as", PLACED_INDICATOR_TYPES, siLeftX, -492, siLeftW, "placed",
        function(placed)
            placed.type = placed.type or "icon"
            placed.anchor = placed.anchor or "TOPLEFT"
            placed.size = tonumber(placed.size) or 18
            placed.cooldownSize = tonumber(placed.cooldownSize) or 8
            placed.growth = placed.growth or "RIGHTDOWN"
            if placed.barSmoothFill == nil then placed.barSmoothFill = false end
            if placed.barShowTimer == nil then placed.barShowTimer = false end
            placed.barTimerAnchor = placed.barTimerAnchor or "CENTER"
            placed.barTimerX = tonumber(placed.barTimerX) or 0
            placed.barTimerY = tonumber(placed.barTimerY) or 0
            if placed.showCooldownSwipe == nil then placed.showCooldownSwipe = true end
        end,
        RefreshPage)
    local placedAnchor = BindPlacedDropdown("Anchor", STATUS_ICON_ANCHORS, "anchor", "TOPLEFT", -546)
    local placedSize = BindPlacedSlider("Size", 6, 48, 1, "size", 18, -600)
    local placedBarWidth = BindPlacedSlider("Bar Width", 8, 120, 1, "barWidth", 42, -654)
    local placedGrowth = BindPlacedDropdown("Growth", SPELL_GROWTH_VALUES, "growth", "RIGHTDOWN", -708)
    local placedIconEffect = BindPlacedDropdown("Icon Effect", ICON_EFFECT_TYPES, "iconEffect", "none", -762, RefreshSpellIndicatorState)
    local placedBarSmoothFill = BindPlacedToggle("Smooth fill", "barSmoothFill", false, -762,
        siLeftX, siLeftW)
    local placedBarShowTimer = BindPlacedToggle("Show Timer Text", "barShowTimer", false, -802,
        siLeftX, siLeftW, RefreshSpellIndicatorState)
    local placedBarTimerAnchor = BindPlacedDropdown("Timer Anchor", STATUS_ICON_ANCHORS,
        "barTimerAnchor", "CENTER", -842)
    local timerGap = 12
    local timerSliderW = floor((siLeftW - timerGap) * 0.5)
    local placedBarTimerX = BindConfigSlider(PlacedConfig, siLeftX, timerSliderW,
        "Timer X", -100, 100, 1, "barTimerX", 0, -896)
    local placedBarTimerY = BindConfigSlider(PlacedConfig, siLeftX + timerSliderW + timerGap, timerSliderW,
        "Timer Y", -100, 100, 1, "barTimerY", 0, -896)
    local function RefreshPlacedControlVisibility(placed)
        local iconSelected, barSelected, barTimerSelected = ResolvePlacedSpellIndicatorControlVisibility(placed)
        W.SetControlShown(placedIconEffect, iconSelected)
        W.SetControlShown(placedBarSmoothFill, barSelected)
        W.SetControlShown(placedBarShowTimer, barSelected)
        W.SetControlShown(placedBarTimerAnchor, barTimerSelected)
        W.SetControlShown(placedBarTimerX, barTimerSelected)
        W.SetControlShown(placedBarTimerY, barTimerSelected)
        return iconSelected, barSelected, barTimerSelected
    end
    -- Dropdowns are visible when constructed. Apply the selected Display-as
    -- shape immediately so a skipped/late page refresh cannot expose controls
    -- from another shape, including after toggling Preview all spells.
    RefreshPlacedControlVisibility(PlacedConfig(CurrentScope(), false))
    if M.AddTooltip then
        M.AddTooltip(placedGrowth, "Growth",
            "For Bar, the first direction controls the fill: Right fills left-to-right; Left fills right-to-left. Up or Down remains the secondary layout direction.",
            { hook = true, titleAsLine = true })
        M.AddTooltip(placedBarSmoothFill, "Smooth fill",
            "Uses Blizzard's native StatusBar interpolation when an active aura duration is refreshed. The countdown itself remains C-side.",
            { hook = true, titleAsLine = true })
    end
    local frameType = BindSpellSubType("Effect", FRAME_EFFECT_TYPES, siRightX, -490, siRightW, "frame",
        function(frame)
            if not frame.color then
                local c = CurrentAuraColor(CurrentScope())
                frame.color = { c[1] or 1, c[2] or 1, c[3] or 1, 0.8 }
            end
            frame.priority = frame.priority or 5
            frame.layer = tonumber(frame.layer) or 0
            frame.strata = frame.strata or "AUTO"
        end,
        RefreshSpellIndicatorState)
    local frameColor = W.Color(spells, Tr("Color"))
    frameColor._msuf2ColorLabel = Tr("Health bar highlight")
    frameColor._msuf2ContextColorCardOverride = frameHighlightCard
    M.BindColor(ctx, frameColor,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            local c = frame and frame.color
            if c then return c[1] or 1, c[2] or 1, c[3] or 1 end
            c = CurrentAuraColor(CurrentScope())
            return c[1] or 1, c[2] or 1, c[3] or 1
        end,
        function(r, g, bcol)
            local frame = FrameEffectConfig(CurrentScope(), true)
            if frame then
                local a = (frame.color and frame.color[4]) or frame.alpha or 0.8
                frame.color = { r, g, bcol, a }
            end
            QueueSpellIndicators(CurrentScope())
        end,
        ControlMeta(ctx, "spell.frame.color"))
    W.MoveWidget(frameColor, spells, siRightX, -544, siRightW)
    local framePriority = BindFrameSlider("Priority", 1, 10, 1, "priority", 5, -598)
    local frameAlpha = W.Slider(spells, Tr("Tint Alpha"), 5, 100, 5, siRightW)
    M.BindNumberWidget(ctx, frameAlpha,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            return floor(((frame and (frame.alpha or (frame.color and frame.color[4])) or 0.25) * 100) + 0.5)
        end,
        function(value)
            local frame = FrameEffectConfig(CurrentScope(), true)
            if frame then
                local alpha = (tonumber(value) or 25) / 100
                frame.alpha = alpha
                if frame.color then frame.color[4] = alpha end
            end
            QueueSpellIndicators(CurrentScope())
        end,
        25, StepMeta(ctx, "spell.frame.alpha", 5))
    W.MoveWidget(frameAlpha, spells, siRightX, -652, siRightW, "LEFT")
    local frameThickness = BindFrameSlider("Border / Glow Thickness", 1, 8, 1, "thickness", 2, -706)
    local frameLayer = BindFrameSlider("Effect Layer (0-30)", 0, 30, 1, "layer", 0, -760)
    local spellGridLayoutRows
    local function RefreshSpellGridLayout(rows)
        rows = max(3, tonumber(rows) or 3)
        if rows == spellGridLayoutRows then return end
        spellGridLayoutRows = rows
        local extra = (rows - 3) * (spellGrid.tileSize + spellGrid.gap)
        spellSetCard:SetHeight(404 + extra)
        placedIndicatorCard:ClearAllPoints()
        placedIndicatorCard:SetPoint("TOPLEFT", spells, "TOPLEFT", siLeftX - 16, -456 - extra)
        W.MoveWidget(placedType, spells, siLeftX, -492 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedAnchor, spells, siLeftX, -546 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedSize, spells, siLeftX, -600 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedBarWidth, spells, siLeftX, -654 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedGrowth, spells, siLeftX, -708 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedIconEffect, spells, siLeftX, -762 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedBarSmoothFill, spells, siLeftX, -762 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedBarShowTimer, spells, siLeftX, -802 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedBarTimerAnchor, spells, siLeftX, -842 - extra, siLeftW, "LEFT")
        W.MoveWidget(placedBarTimerX, spells, siLeftX, -896 - extra, timerSliderW, "LEFT")
        W.MoveWidget(placedBarTimerY, spells, siLeftX + timerSliderW + timerGap, -896 - extra, timerSliderW, "LEFT")
        local contentHeight = max(1040, 1020 + extra)
        local entry = spells._msuf2CollapsibleEntry
        if entry and entry.contentHeight ~= contentHeight then
            entry.contentHeight = contentHeight
            spells:SetHeight(contentHeight)
            entry.outer:SetHeight(entry.headerHeight + (entry.open and contentHeight or 0))
            b:RequestRelayoutCollapsibles()
        end
    end
    RefreshSpellIndicatorState = RefreshSpellIndicatorState(function()
        if SPELL_INDICATORS_121_PTR_DISABLED and SpellIndicators(CurrentScope()).enabled ~= false then
            SpellIndicators(CurrentScope()).enabled = false
            QueueSpellIndicators(CurrentScope())
        end
        EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
        RefreshSpellGridLayout(spellGrid:Refresh())
        local spellCfg = SpellIndicators(CurrentScope())
        local indicatorsOn = (not SPELL_INDICATORS_121_PTR_DISABLED) and spellCfg.enabled == true
        local multi = spellCfg.spec == "multi"
        local allSpecs = multi and IsAllSpecsSpellSpec(CurrentSpellMultiSpec(CurrentScope()))
        if W.SetControlShown then
            W.SetControlShown(multiSpecDrop, multi)
            W.SetControlShown(multiSpecEnabled, multi and not allSpecs)
        else
            multiSpecDrop:SetShown(multi)
            multiSpecEnabled:SetShown(multi and not allSpecs)
        end
        allSpecsHint:SetShown(allSpecs == true)
        local placed = PlacedConfig(CurrentScope(), false)
        local hasSpell = indicatorsOn and EffectiveSpellSpec(CurrentScope()) ~= nil and CurrentSpellAura(CurrentScope()) ~= ""
        local currentCfg = CurrentSpellConfig(CurrentScope(), false)
        local customSpell = hasSpell and IsCustomBuffEntry(CurrentSpellAura(CurrentScope()), currentCfg)
        local placedEnabled = hasSpell and placed and placed.type and placed.type ~= "none"
        local frame = FrameEffectConfig(CurrentScope(), false)
        local frameKind = frame and frame.type or "none"
        local hasFrame = hasSpell and frameKind ~= "none"
        RefreshPreviewAllButton()
        local iconSelected, barSelected, barTimerSelected = RefreshPlacedControlVisibility(placed)
        local cdRelevant = placedEnabled and iconSelected
        local barRelevant = placedEnabled and barSelected
        SetOptionEnabled(siEnable, not SPELL_INDICATORS_121_PTR_DISABLED)
        SetManyEnabled(indicatorsOn, siLayer, specDrop)
        SetOptionEnabled(multiSpecDrop, indicatorsOn and multi)
        SetOptionEnabled(multiSpecEnabled, indicatorsOn and multi and not allSpecs and CurrentSpellMultiSpec(CurrentScope()) ~= "")
        local externalBlacklistManaged = hasSpell
            and CurrentSpellIsExternalDefensive(CurrentScope())
            and ExternalAutoBlacklistActive(CurrentScope())
        SetManyEnabled(hasSpell, spellEnabled, onlyMine, placedType)
        SetOptionEnabled(autoBlacklist, hasSpell and not externalBlacklistManaged)
        SetOptionEnabled(customSpellIDs, customSpell)
        SetManyEnabled(placedEnabled, placedAnchor, placedSize, placedGrowth)
        SetOptionEnabled(placedBarWidth, barRelevant)
        SetOptionEnabled(placedIconEffect, cdRelevant)
        SetManyEnabled(barRelevant, placedBarSmoothFill, placedBarShowTimer)
        SetManyEnabled(barRelevant and barTimerSelected,
            placedBarTimerAnchor, placedBarTimerX, placedBarTimerY)
        SetOptionEnabled(frameType, hasSpell)
        SetManyEnabled(hasFrame, frameColor, framePriority, frameAlpha, frameThickness, frameLayer)
        local badges = {
            OnOffBadge(indicatorsOn, "Enabled", "Disabled"),
        }
        if SPELL_INDICATORS_121_PTR_DISABLED then badges[#badges + 1] = { text = "12.1 PTR", kind = "muted", important = true } end
        badges[#badges + 1] = { text = OptionText(SpellSpecValues, SpellIndicators(CurrentScope()).spec or "auto", "Auto"), kind = indicatorsOn and "info" or "muted" }
        badges[#badges + 1] = { text = hasSpell and tostring(CurrentSpellAura(CurrentScope()) or "") or "No spell", kind = hasSpell and "accent" or "muted" }
        SetSectionBadgesAndStatus(spells, badges)
    end)
    TrackSectionRefresh(ctx, spells, RefreshSpellIndicatorState)
    GP.BuildSpellIndicatorStyleSection(ctx, b)
end

GP.BuildSpellIndicatorsSection = BuildSpellIndicatorsSection

local function BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    local corners = b:CollapsibleSection("ci", "Corner Indicators", 674, false)
    local cornerW = corners._msuf2Width or ctx.width or 720
    local leftX = 30
    local cornerGap = 28
    local cornerInnerW = max(320, cornerW - 60)
    local leftW = max(240, min(360, floor((cornerInnerW - cornerGap) * 0.46)))
    local rightX = leftX + leftW + cornerGap
    local rightW = max(260, min(440, cornerInnerW - leftW - cornerGap))
    local cornerEditorCard
    do
        W.ControlCardBackdrop(corners, leftX - 14, -38, leftW + 28, 224)
        W.ControlCardBackdrop(corners, leftX - 14, -272, leftW + 28, 334)
        cornerEditorCard = W.ControlCardBackdrop(corners, rightX - 14, -38, rightW + 28, 526)
        cornerEditorCard._msuf2ControlCardTitle = "Custom Spell Editor"
    end
    W.LabelAt(corners, "Global", leftX, -42, leftW, "GameFontNormalSmall", T.colors.accent)
    local ciEnable = BindScopeToggle(ctx, W.SwitchAt(corners, "Corner Indicators", leftX, -72, leftW), "ciEnabled", false, "visual")
    ciEnable._msuf2GroupFrameGateAlwaysEnabled = true
    local ciSize = ScopeSlider(ctx, corners, "Icon Size", 4, 24, 1, leftW, "ciSize", 8, "visual", leftX, -116, leftW, "LEFT")
    local ciAlpha = W.Slider(corners, "Alpha", 10, 100, 5, leftW)
    M.BindNumberWidget(ctx, ciAlpha,
        function() return floor((Num(CurrentScope(), "ciAlpha", 1) * 100) + 0.5) end,
        function(value) Set(CurrentScope(), "ciAlpha", (tonumber(value) or 100) / 100, "visual") end,
        100, StepMeta(ctx, "corner.alpha", 5))
    W.MoveWidget(ciAlpha, corners, leftX, -170, leftW, "LEFT")
    local ciLayer = ScopeSlider(ctx, corners, "Layer (0-30)", 0, 30, 1, leftW, "ciLayer", 7, "visual", leftX, -224, leftW, "LEFT")
    W.LabelAt(corners, "Slot Assignments", leftX, -282, leftW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Assign what each corner dot should show. Choosing Custom Spell enables that slot's editor on the right.", leftX, -304, leftW, T.colors.muted)
    local slotControls = {}
    local slotPositions = {
        TL = { x = leftX, y = -358 },
        TR = { x = leftX + floor(leftW / 2) + 10, y = -358 },
        BL = { x = leftX, y = -440 },
        BR = { x = leftX + floor(leftW / 2) + 10, y = -440 },
        C = { x = leftX + floor(leftW / 4) + 4, y = -522 },
    }
    local slotW = floor((leftW - 12) / 2)
    for i = 1, #CI_SLOT_VALUES do
        local slotInfo = CI_SLOT_VALUES[i]
        local slotKey = slotInfo.value
        local p = slotPositions[slotKey] or { x = leftX, y = -304 - (i - 1) * 58 }
        local w = slotKey == "C" and slotW or slotW
        local slotDrop = W.Dropdown(corners, (slotInfo.text or slotKey) .. " Indicator", CICategoryValues, w)
        M.BindDropdownWidget(ctx, slotDrop,
            function()
                return Val(CurrentScope(), "ciSlot" .. slotKey, CI_SLOT_DEFAULTS[slotKey] or "none")
            end,
            function(value)
                M.SetMenuStateValue("gfCornerSlotSelection", slotKey)
                Set(CurrentScope(), "ciSlot" .. slotKey, value or "none", "visual")
                RefreshPage()
            end,
            ControlMeta(ctx, "corner.assignment." .. tostring(slotKey)))
        W.MoveWidget(slotDrop, corners, p.x, p.y, w, "LEFT")
        slotControls[#slotControls + 1] = slotDrop
    end
    W.LabelAt(corners, "Custom Spell Editor", rightX, -42, rightW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Pick a slot, set it to Custom Spell, then enter spell IDs. This edits one slot at a time and keeps the five slot assignments visible.", rightX, -64, rightW, T.colors.muted)
    local slotDrop = W.Dropdown(corners, "Editor Slot", CI_SLOT_VALUES, rightW)
    M.BindDropdownWidget(ctx, slotDrop,
        function() return CurrentCISlot() end,
        function(value)
            M.SetMenuStateValue("gfCornerSlotSelection", value or "TL")
            RefreshPage()
        end,
        ControlMeta(ctx, "corner.editor.slot", "ephemeral"))
    W.MoveWidget(slotDrop, corners, rightX, -122, rightW, "LEFT")
    local categoryDrop = W.Dropdown(corners, "Selected Slot Indicator", CICategoryValues, rightW)
    M.BindDropdownWidget(ctx, categoryDrop,
        function()
            local slot = CurrentCISlot()
            return Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        end,
        function(value)
            local slot = CurrentCISlot()
            Set(CurrentScope(), "ciSlot" .. slot, value or "none", "visual")
            RefreshPage()
        end,
        ControlMeta(ctx, "corner.editor.category"))
    W.MoveWidget(categoryDrop, corners, rightX, -176, rightW, "LEFT")
    local customStatus = W.Text(corners, "", rightX, -230, rightW, T.colors.muted)
    if customStatus.SetWordWrap then customStatus:SetWordWrap(true) end
    local customSpells = W.TextInput(corners, "Spell IDs (comma-separated)", rightW)
    M.BindTextInput(ctx, customSpells,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.spells or ""
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.spells = value or "" end
            QueueGF(CurrentScope(), "visual")
        end,
        true,
        ControlMeta(ctx, "corner.editor.spell_ids"))
    W.MoveWidget(customSpells, corners, rightX, -286, rightW)
    local function BindCICustomDropdown(label, values, key, defaultValue, y)
        local control = W.Dropdown(corners, label, values, rightW)
        M.BindDropdownWidget(ctx, control,
            function()
                local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
                return cfg and cfg[key] or defaultValue
            end,
            function(value)
                local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
                if cfg then cfg[key] = value or defaultValue end
                QueueGF(CurrentScope(), "visual")
            end,
            ControlMeta(ctx, "corner.editor." .. tostring(key)))
        W.MoveWidget(control, corners, rightX, y, rightW, "LEFT")
        return control
    end
    local customMode = BindCICustomDropdown("When", CIModeValues, "mode", "present", -350)
    local customFilter = BindCICustomDropdown("Filter", CIFilterValues, "filter", "HELPFUL|PLAYER", -404)
    local customColor = W.Color(corners, "Custom Color")
    customColor._msuf2ColorLabel = "Custom spell color"
    customColor._msuf2ContextColorCardOverride = cornerEditorCard
    M.BindColor(ctx, customColor,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return (cfg and cfg.r) or 0.40, (cfg and cfg.g) or 1.00, (cfg and cfg.b) or 0.40
        end,
        function(r, g, b)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.r, cfg.g, cfg.b = r, g, b end
            QueueGF(CurrentScope(), "visual")
        end,
        ControlMeta(ctx, "corner.editor.color"))
    W.MoveWidget(customColor, corners, rightX, -458, rightW)
    local cornerColorShortcut
    if W.AttachContextColorShortcut then
        cornerColorShortcut = W.AttachContextColorShortcut(cornerEditorCard, {
            title = "Corner Indicator Color",
            getTargets = function()
                local slot = CurrentCISlot()
                local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
                if category == "custom" then return { customColor } end
                if category == "aggro" and type(M.ResolveContextColorReferences) == "function" then
                    return M.ResolveContextColorReferences({ "group.aggro" }, {})
                end
                return {}
            end,
            note = "Uses the selected slot's Custom Spell color or the shared Corner Aggro color.",
            historySource = "menu:group-corner-indicator-color",
        })
    end
    local customHelp = W.Text(corners, "Tip: HELPFUL|PLAYER and HARMFUL|PLAYER are the safest filters because WoW exposes your own spell IDs reliably.", rightX, -506, rightW, T.colors.dim)
    if customHelp.SetWordWrap then customHelp:SetWordWrap(true) end
    local ciGlobalControls, ciEditorControls, ciCustomControls = { ciSize, ciAlpha, ciLayer }, { slotDrop, categoryDrop }, { customSpells, customMode, customFilter, customColor }
    local function RefreshCornerIndicatorState()
        local slot = CurrentCISlot()
        local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        local showCustom = category == "custom"
        local enabled = Bool(CurrentScope(), "ciEnabled", false)
        SetOptionEnabled(ciEnable, true)
        SetOptionsEnabled(ciGlobalControls, enabled)
        SetOptionsEnabled(slotControls, enabled)
        SetOptionsEnabled(ciEditorControls, enabled)
        SetOptionsEnabled(ciCustomControls, enabled and showCustom)
        if cornerColorShortcut then cornerColorShortcut:SetShown(enabled and (showCustom or category == "aggro")) end
        local slotLabel = slot
        for i = 1, #CI_SLOT_VALUES do
            if CI_SLOT_VALUES[i].value == slot then
                slotLabel = CI_SLOT_VALUES[i].text or slot
                break
            end
        end
        SetSectionBadgesAndStatus(corners, {
            OnOffBadge(enabled, "Enabled", "Disabled"),
            { text = slotLabel, kind = enabled and "info" or "muted" },
            { text = OptionText(CICategoryValues, category, "None"), kind = showCustom and "accent" or (enabled and "info" or "muted") },
        })
        if showCustom then
            customStatus:SetText(M.Format("%s is using Custom Spell. These settings are active.", slotLabel))
            customStatus:SetTextColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 0.95)
        else
            customStatus:SetText(M.Format("%s is set to %s. Set Selected Slot Indicator to Custom Spell to activate this editor.", slotLabel, tostring(category or "none")))
            customStatus:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        end
    end
    TrackSectionRefresh(ctx, corners, RefreshCornerIndicatorState)
end

local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.CallIf(M.SelectPage, ctx.key) end
    BuildIndicatorsSection(ctx, b)
    BuildStatusIconsSection(ctx, b, RefreshPage)
    BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_indicators", { title = "MSUF Group Status & Indicators", build = BuildGFIndicators, version = 20 })
