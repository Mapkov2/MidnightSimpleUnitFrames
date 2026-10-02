local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
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
local Tr = M.TranslateText or M.Tr
local floor = math.floor
local max = math.max
local min = math.min
local table_concat = table.concat
local C_Timer = M.MenuTimer or _G.C_Timer
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local VT = M.ValueTextList
local WHITE_RGB = { 1, 1, 1 }
local SPELL_INDICATORS_121_PTR_DISABLED = false
local issecretvalue = _G.issecretvalue
local STATUS_ICON_RESET_FIELDS = M.WordList "size anchor x y layer iconStyle customIcon"
local STATUS_ICON_ANCHORS, GF_STATUS_ICON_SPECS = GP.STATUS_ICON_ANCHORS or {}, GP.GF_STATUS_ICON_SPECS or {}
local GF_STATUS_ICON_VALUES, PLACED_INDICATOR_TYPES = GP.GF_STATUS_ICON_VALUES or {}, GP.PLACED_INDICATOR_TYPES or {}
local FRAME_EFFECT_TYPES, ICON_EFFECT_TYPES, SPELL_GROWTH_VALUES = GP.FRAME_EFFECT_TYPES or {}, GP.ICON_EFFECT_TYPES or {}, GP.SPELL_GROWTH_VALUES or {}
local CI_SLOT_VALUES, CI_SLOT_DEFAULTS = GP.CI_SLOT_VALUES or {}, GP.CI_SLOT_DEFAULTS or {}
local GF, RefreshGFPreview, Conf, Val, QueueGF, Set, Bool, Num = GP.GF, GP.RefreshGFPreview, GP.Conf, GP.Val, GP.QueueGF, GP.Set, GP.Bool, GP.Num
local ScopeSection, CurrentScope, BindScopeToggle, ScopeDropdown = GP.ScopeSection, GP.CurrentScope, GP.BindScopeToggle, GP.ScopeDropdown
local ScopeSlider, SpellIndicators, IconStyleValues = GP.ScopeSlider, GP.SpellIndicators, GP.IconStyleValues
local CurrentGFStatusSpec, QueueSpellIndicators, SpellSpecValues = GP.CurrentGFStatusSpec, GP.QueueSpellIndicators, GP.SpellSpecValues
local SpellTrackedSpecValues, IsAllSpecsSpellSpec, CurrentSpellMultiSpec = GP.SpellTrackedSpecValues, GP.IsAllSpecsSpellSpec, GP.CurrentSpellMultiSpec
local EffectiveSpellSpec, SpellAuraValues, SetCurrentSpellAura = GP.EffectiveSpellSpec, GP.SpellAuraValues, GP.SetCurrentSpellAura
local ClearCurrentSpellAura, CurrentSpellAura, CurrentSpellConfig = GP.ClearCurrentSpellAura, GP.CurrentSpellAura, GP.CurrentSpellConfig
local PlacedConfig, FrameEffectConfig, CICategoryValues, CIFilterValues = GP.PlacedConfig, GP.FrameEffectConfig, GP.CICategoryValues, GP.CIFilterValues
local CIModeValues, CurrentCISlot, CICustomConfig, BindNestedSlider = GP.CIModeValues, GP.CurrentCISlot, GP.CICustomConfig, GP.BindNestedSlider
local SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage = GP.SetOptionEnabled, GP.SetOptionsEnabled, GP.FinalizeScopePage
local SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge = GP.SetSectionBadgesAndStatus, GP.TrackSectionRefresh, GP.OnOffBadge
local OptionText, ControlMeta, RegisterControl = GP.OptionText, GP.ControlMeta, GP.RegisterControl
OnOffBadge = OnOffBadge or M.OnOffBadge
OptionText = OptionText or M.OptionText
local function ResolvePlacedSpellIndicatorControlVisibility(placed)
    local placedType = type(placed) == "table" and tostring(placed.type or "none"):lower() or "none"
    local iconSelected = placedType == "icon"
    local barSelected = placedType == "bar"
    return iconSelected, barSelected, barSelected and placed.barShowTimer == true
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
        local setting = path == "spell.icon_scale" and "iconScale" or "iconZoom"
        if scope == "party" then
            meta.searchSettingKeys = { "gf_party.spellIndicators." .. setting }
        else
            meta.searchSettingKeys = {
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
    local spellID = resolver(identifier)

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

--- Name and icon of a custom buff, each nil while the client has no spell data
--- for it yet.
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
    return name, icon
end

local function SuggestedActivePlayerAuraID(spellIDs)
    if type(spellIDs) ~= "table" or #spellIDs ~= 1 then return nil end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    local enteredID = spellIDs[1]
    local spellName = CustomBuffInfo(enteredID)
    if issecretvalue(spellName) == true or type(spellName) ~= "string" or spellName == "" then return nil end
    local getByName = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataBySpellName
    if type(getByName) ~= "function" then return nil end
    local aura = getByName("player", spellName, "HELPFUL")

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
        M.Format("Configure target highlighting in %s.", M.NavPath("opt_misc", "Frame Highlights")),
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
        M.AddTooltip(openHighlights, "Open Highlights", M.NavPath("opt_misc", "Frame Highlights"), { hook = true })
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
    local focusColorHint = W.Text(focusCard, M.Format("Focus color is in %s.", M.NavPath("opt_colors", "Party & Raid Frames")), 16, -142, rightW - 32, T.colors.muted)
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
    local groupBorderColorHint = W.Text(groupBorderCard, M.Format("Border color and opacity are in %s.", M.NavPath("opt_colors", "Party & Raid Frames")), 16, -168, leftW - 32, T.colors.muted)
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

-- The Status Icons section is assembled by StatusIcons.Build from one stage per
-- card. Stages share one per-build `state` table and run in the order the
-- controls used to be created inline; the indicator helpers below read only the
-- selected scope and indicator, so they are shared by every build.
local StatusIcons = {}
function StatusIcons.IsTextSpec(spec)
    local value = spec and spec.value
    return value == "statusText" or value == "statusGhostText"
        or value == "statusAFKText" or value == "statusAFKTimer" or value == "statusDNDText"
        or value == "levelText" or value == "threatText"
end
function StatusIcons.SpecDefault(spec, value)
    if type(value) == "function" then return value(spec) end
    return value
end
function StatusIcons.PreviewEntries(spec)
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
function StatusIcons.IsRoleSpec(spec)
    local value = spec and spec.value
    return value == "roleIcon" or value == "leaderIcon" or value == "assistIcon"
end
function StatusIcons.StyleLabel(spec)
    return spec and spec.value == "roleIcon" and "Role icon style" or "Indicator style"
end
function StatusIcons.SetDropdownTitle(control, label)
    if control and control._msuf2Title and control._msuf2Title.SetText then
        control._msuf2Title:SetText(label)
    end
end
--- Each style value carries its own Midnight flag now, so the support probe runs per entry
--- and silently drops packs that ship no art for the selected indicator.
function StatusIcons.IconPackValues()
    local values = IconPackValues()
    local spec = CurrentGFStatusSpec()
    local entries = StatusIcons.PreviewEntries(spec)
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
function StatusIcons.IconAssetValues()
    local spec = CurrentGFStatusSpec()
    local entries = StatusIcons.PreviewEntries(spec)
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
function StatusIcons.ResolvePreviewIcon(style, iconType, variant, useMidnight)
    local resolver = _G.MSUF_GetStatusIconTexture
    if type(resolver) ~= "function" then
        local gf = GF()
        resolver = gf and gf.GetStatusIconTexture
    end
    if type(resolver) ~= "function" then return nil end
    return resolver(style, iconType, variant, useMidnight == true)
end
--- Profiles saved before the per-indicator split still store "DEFAULT"; resolve it through
--- the runtime so the dropdown shows the style that is actually drawn rather than an entry
--- the list no longer offers.
function StatusIcons.CurrentIconStyle()
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
    local values = StatusIcons.IconPackValues()
    for i = 1, #values do
        local item = values[i]
        if item and (item.value or item.key) == resolved then return resolved end
    end
    return "BLIZZARD"
end
--- Green (success) role marks whichever preview mode is live; the other stays neutral.
function StatusIcons.PreviewMode()
    return M.gfStatusPreviewMode == "all" and "all" or "current"
end
function StatusIcons.CurrentTab()
    local key = M.gfStatusIconTabSelection[CurrentScope()] or "basic"
    if key ~= "basic" and key ~= "advanced" then key = "basic" end
    return key
end
--- The section, its Basic/Advanced tabs and the three Basic cards.
function StatusIcons.Open(state, ctx, b, RefreshPage)
    local sicons = b:CollapsibleSection("sicons", "Status Icons", 534, false)
    local siconW = sicons._msuf2Width or ctx.width or 720
    local siconGap = 16
    local siconLeftX = 20
    local siconInnerW = max(320, siconW - 40)
    local siconLeftW = floor((siconInnerW - siconGap) * 0.46)
    local siconRightX = siconLeftX + siconLeftW + siconGap
    local siconRightW = siconInnerW - siconLeftW - siconGap
    M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
    local siconTabFrames = {}
    local siconBasicTab, siconAdvancedTab = M.UnitSectionsShared.MakeTabFrames(sicons, -64, siconW, siconTabFrames, "basic", "advanced")
    local statusTabs, RefreshStatusTabs, ReadStatusTab, SetGuidedStatusTab = W.SegmentTabs(ctx, sicons, {
        get = StatusIcons.CurrentTab,
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
                -- A difficulty-graded Level Text is painted with the five global
                -- level bands, so the picker lists those; nil keeps the group
                -- font color target every other status text uses.
                colorReferences = function()
                    local spec = CurrentGFStatusSpec()
                    if spec and spec.value == "levelText" and Bool(CurrentScope(), "levelTextDifficultyColor", true) then
                        return M._levelDifficultyColorReferences
                    end
                    if spec and spec.value == "threatText" and Bool(CurrentScope(), "threatTextColorCurve", true)
                        and M._threatCurveColorReferences and #M._threatCurveColorReferences > 0 then
                        return M._threatCurveColorReferences
                    end
                    return nil
                end,
                maxColorTargets = 5,
                capabilities = { baseline = false },
            },
        })
        selectedTextShortcut:SetShown(StatusIcons.IsTextSpec(CurrentGFStatusSpec()))
    end
    state.previewCard = W.ControlCard(siconBasicTab, "Status Preview", nil, siconRightX, -38, siconRightW, 164)
    state.placementCard = W.ControlCard(siconBasicTab, "Placement", nil, siconRightX, -220, siconRightW, 172)
    function state.RefreshStatusIconMenu()
        if M.RequestRefresh then
            M.RequestRefresh(ctx, "gf-indicators-status-icon")
        elseif M.Refresh then
            M.Refresh(ctx)
        else
            RefreshPage()
        end
    end
    state.sicons, state.siconAdvancedTab, state.selectedCard, state.selectedTextShortcut = sicons, siconAdvancedTab, selectedCard, selectedTextShortcut
    state.siconLeftX, state.siconLeftW, state.siconRightX, state.siconRightW, state.siconInnerW =
        siconLeftX, siconLeftW, siconRightX, siconRightW, siconInnerW
end
--- Binders of the selected indicator's own settings, by spec field.
function StatusIcons.PrepareBinders(state, ctx)
    local StatusSpecDefault = StatusIcons.SpecDefault
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
    state.BindStatusDropdown = BindStatusDropdown
    function state.BuildStatusControls(parent, specs)
        return M.BuildControlSpecs(specs, {
            dropdown = function(s, i) return BindStatusDropdown(parent, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]), s[12] or s[5] or i end,
            slider = function(s, i) return BindStatusSlider(parent, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11], s[12], s[13], s.identitySuffix), s[14] or s[7] or i end,
        })
    end
end
--- Selected Indicator: the indicator, its switch, its style and icon, the
--- Level Text and Threat % options and the role filter.
function StatusIcons.BuildSelectedCard(state, ctx)
    local selectedCard, siconLeftW = state.selectedCard, state.siconLeftW
    local RefreshStatusIconMenu = state.RefreshStatusIconMenu
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
    local iconPack = W.Dropdown(selectedCard, "Indicator style", StatusIcons.IconPackValues, siconLeftW)
    M.BindDropdownWidget(ctx, iconPack, StatusIcons.CurrentIconStyle,
        function(value)
            local spec = CurrentGFStatusSpec()
            local key = spec and spec.iconStyle
            if not key then return end
            Set(CurrentScope(), key, value or "DEFAULT", "visual")
            RefreshGFPreview()
            if state.Refresh then state.Refresh() end
        end,
        ControlMeta(ctx, "status.selected.iconStyle"))
    W.MoveWidget(iconPack, selectedCard, 16, -106, siconLeftW - 32, "LEFT")
    local customIcon = state.BindStatusDropdown(selectedCard, "Custom icon", StatusIcons.IconAssetValues, siconLeftW, "customIcon", "", "visual", 16, -158, siconLeftW - 32,
        function()
            RefreshGFPreview()
            if state.Refresh then state.Refresh() end
        end)
    --- Level Text only: the same difficulty grading as the unit-frame level indicator.
    local levelDifficultyColor = BindScopeToggle(ctx, W.ToggleAt(selectedCard, "Color by level difficulty", 16, -106, siconLeftW - 32), "levelTextDifficultyColor", true, "visual")
    if M.AddTooltip then
        M.AddTooltip(levelDifficultyColor, "Color by level difficulty",
            "Red far above your level, white at your level, gray when trivial. Turn off to use the status text color instead.", { hook = true })
    end
    --- Threat % only (MSUF.Client.SupportsThreatText): the unit frames' threat color curve
    --- and the dark plate behind the number (on for Party, off for Raid by default).
    local threatColorCurve, threatBackground
    if MSUF.Client and MSUF.Client.SupportsThreatText == true then
        threatColorCurve = BindScopeToggle(ctx, W.ToggleAt(selectedCard, "Color by threat", 16, -106, siconLeftW - 32), "threatTextColorCurve", true, "visual")
        threatBackground = BindScopeToggle(ctx, W.ToggleAt(selectedCard, "Background", 16, -136, siconLeftW - 32), "threatTextBackground", false, "visual")
        if M.AddTooltip then
            M.AddTooltip(threatColorCurve, "Color by threat",
                "Green at low threat, yellow at half, pink at 100% when you have aggro. Turn off to use the status text color instead.", { hook = true })
            M.AddTooltip(threatBackground, "Background",
                "A dark plate behind the number keeps it readable on any bar color, red enemy bars included.", { hook = true })
        end
    end

    --- Role filter group: only visible when Role Icon indicator is selected
    local roleFilterGroup = PixelLayoutRegion(CreateFrame("Frame", nil, selectedCard))
    roleFilterGroup:SetPoint("TOPLEFT", selectedCard, "TOPLEFT", 0, -216)
    local roleFilterW = max(180, siconLeftW - 32)
    roleFilterGroup:SetSize(roleFilterW, 60)
    W.LabelAt(roleFilterGroup, "Show for:", 16, -8, siconLeftW - 32, "GameFontNormalSmall", T.colors.accent)
    local rfColW   = floor(roleFilterW / 3)
    local rfLabelW = max(34, rfColW - 30)  --- subtract checkbox(24) + gap(6) so hit areas don't overlap the next column
    local rfTank   = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Tank",   16,              -26, rfLabelW), "roleIconShowTank",   true, "visual")
    local rfHealer = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Healer", 16 + rfColW,     -26, rfLabelW), "roleIconShowHealer", true, "visual")
    local rfDPS    = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "DPS",    16 + rfColW * 2, -26, rfLabelW), "roleIconShowDPS",    true, "visual")
    state.statusEnabled, state.iconPack, state.customIcon, state.levelDifficultyColor = statusEnabled, iconPack, customIcon, levelDifficultyColor
    state.threatColorCurve, state.threatBackground = threatColorCurve, threatBackground
    state.roleFilterGroup, state.roleFilterControls = roleFilterGroup, { rfTank, rfHealer, rfDPS }
end
--- Status Preview: preview mode buttons, Reset selected and the icon strip.
function StatusIcons.BuildPreviewCard(state, ctx)
    local previewCard, siconRightW = state.previewCard, state.siconRightW
    local previewInnerW = max(190, siconRightW - 32)
    local previewButtonGap = 8
    local previewCurrentW = min(142, max(112, floor(previewInnerW * 0.58)))
    local previewAllW = min(112, max(76, previewInnerW - previewCurrentW - previewButtonGap))
    previewCurrentW = max(96, previewInnerW - previewAllW - previewButtonGap)
    local function SetStatusPreviewMode(mode)
        local gf = GF()
        M.SetMenuStateValue("gfStatusPreviewMode", mode)
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        RefreshGFPreview()
        if state.RefreshPreviewButtons then state.RefreshPreviewButtons() end
    end
    local function PreviewActionButton(parent, label, width, semanticPath, onClick)
        local btn = W.Button(parent, label, width)
        btn:SetScript("OnClick", onClick)
        RegisterControl(btn, ctx, semanticPath, label, "button", "ephemeral")
        btn:ClearAllPoints()
        btn:SetSize(width, 24)
        return btn
    end
    state.PreviewActionButton = PreviewActionButton
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
        if spec.value == "levelText" then
            conf.levelTextDifficultyColor = gf and gf.GetDefault and gf.GetDefault(kind, "levelTextDifficultyColor") or nil
        end
        if spec.value == "threatText" then
            conf.threatTextColorCurve = gf and gf.GetDefault and gf.GetDefault(kind, "threatTextColorCurve") or nil
            conf.threatTextBackground = gf and gf.GetDefault and gf.GetDefault(kind, "threatTextBackground")
        end
        -- The reset fields include anchor and offsets, which the Anchor
        -- dropdown applies with the geometry pass; size and style are visual.
        QueueGF(kind, "geometry")
        QueueGF(kind, "visual")
        state.RefreshStatusIconMenu()
    end)
    RegisterControl(statusReset, ctx, "status.selected.reset", "Reset selected", "button", "action", {
        actionKey = "reset_selected_group_status_icon",
    })
    statusReset:ClearAllPoints()
    statusReset:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -86)
    statusReset:SetSize(min(160, previewInnerW), 24)
    local iconPreviewLabel = W.LabelAt(previewCard, "Icon preview", 16, -120, previewInnerW, "GameFontNormalSmall", T.colors.accent)
    local iconPreviewStrip = PixelLayoutRegion(CreateFrame("Frame", nil, previewCard))
    iconPreviewStrip:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -132)
    iconPreviewStrip:SetSize(previewInnerW, 24)
    local iconPreviewTextures = {}
    for i = 1, 5 do
        local holder = PixelLayoutRegion(CreateFrame("Frame", nil, iconPreviewStrip))
        holder:SetSize(24, 24)
        holder:SetPoint("LEFT", iconPreviewStrip, "LEFT", (i - 1) * 28, 0)
        holder.bg = PixelLayoutRegion(holder:CreateTexture(nil, "BACKGROUND"))
        holder.bg:SetAllPoints()
        holder.bg:SetColorTexture(0.020, 0.026, 0.052, 0.70)
        holder.tex = PixelLayoutRegion(holder:CreateTexture(nil, "ARTWORK"))
        holder.tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder.tex:SetSize(22, 22)
        iconPreviewTextures[i] = holder
    end
    state.previewCurrent, state.previewAll, state.statusReset = previewCurrent, previewAll, statusReset
    state.iconPreviewLabel, state.iconPreviewStrip, state.iconPreviewTextures = iconPreviewLabel, iconPreviewStrip, iconPreviewTextures
end
function StatusIcons.RefreshIconPreviewStrip(state, spec, enabled)
    local iconPreviewStrip, iconPreviewTextures = state.iconPreviewStrip, state.iconPreviewTextures
    local entries = StatusIcons.PreviewEntries(spec)
    local shown = entries and spec and (StatusIcons.IsRoleSpec(spec) or spec.customIcon)
    state.iconPreviewLabel:SetShown(shown and true or false)
    iconPreviewStrip:SetShown(shown and true or false)
    if not shown then return end
    --- Preview the style the indicator itself carries; the value may hold the Midnight
    --- suffix, which the texture resolver splits off on its own.
    local style = StatusIcons.CurrentIconStyle()
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
                path, l, r, t, b = StatusIcons.ResolvePreviewIcon(style, entry[1], entry[2], false)
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
--- Placement (Basic tab) and Advanced Placement (Advanced tab).
function StatusIcons.BuildPlacement(state, ctx)
    local siconLeftX, siconLeftW, siconRightX, siconRightW = state.siconLeftX, state.siconLeftW, state.siconRightX, state.siconRightW
    local PreviewActionButton, statusReset, previewCurrent, previewAll = state.PreviewActionButton, state.statusReset, state.previewCurrent, state.previewAll
    state.statusControls = state.BuildStatusControls(state.placementCard, {
        { "slider", "Size", 6, 40, 1, siconRightW, "size", function(spec) return spec.defaultSize end, "visual", 16, -58, siconRightW - 58 },
        { "dropdown", "Anchor", STATUS_ICON_ANCHORS, siconRightW, "anchor", function(spec) return spec.defaultAnchor end, "geometry", 16, -108, siconRightW - 32 },
    })
    local advanced = {}
    advanced.card = W.ControlCard(state.siconAdvancedTab, "Advanced Placement", nil, siconLeftX, -38, state.siconInnerW, 232)
    M.Assign(advanced, state.BuildStatusControls(advanced.card, {
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
    function state.RefreshPreviewButtons()
        local ApplyRole = T.ApplyButtonRole
        if not ApplyRole then return end
        local currentRole = StatusIcons.PreviewMode() == "current" and "success" or "normal"
        local allRole = currentRole == "success" and "normal" or "success"
        ApplyRole(previewCurrent, currentRole)
        ApplyRole(previewAll, allRole)
        ApplyRole(advanced.previewCurrent, currentRole)
        ApplyRole(advanced.previewAll, allRole)
    end
    state.advanced = advanced
    state.statusPlacementControls = { state.statusControls.size, state.statusControls.anchor, advanced.layer }
    state.statusActionControls = { advanced.reset, advanced.previewCurrent, statusReset, previewCurrent }
end
--- Shows the selected indicator's own controls, gates them by its switch and
--- sets the section badges.
function StatusIcons.Refresh(state)
    local spec = CurrentGFStatusSpec()
    local enabled = Bool(CurrentScope(), spec.enabled, false)
    local iconPack, customIcon, iconPreviewLabel = state.iconPack, state.customIcon, state.iconPreviewLabel
    StatusIcons.SetDropdownTitle(iconPack, StatusIcons.StyleLabel(spec))
    StatusIcons.SetDropdownTitle(customIcon, "Custom icon")
    if iconPreviewLabel and iconPreviewLabel.SetText then
        iconPreviewLabel:SetText(StatusIcons.IsRoleSpec(spec) and "Role icon preview" or "Icon preview")
    end
    SetOptionsEnabled(state.statusPlacementControls, enabled)
    SetOptionsEnabled(state.statusActionControls, spec ~= nil)
    SetManyEnabled(true, state.advanced.previewAll, state.previewAll, state.statusEnabled)
    state.RefreshPreviewButtons()
    --- Style packs are only a meaningful knob for the role/leader/assist glyphs -- the
    --- remaining indicators are canonical game symbols where people replace a single
    --- texture, so they keep just the Custom icon dropdown. The count guard stays as a
    --- safety net in case a pack set ever leaves nothing but Blizzard to pick.
    local hasIconPack = StatusIcons.IsRoleSpec(spec) and spec.iconStyle
        and #StatusIcons.IconPackValues() > 1
    local hasCustomIcon = spec and spec.customIcon
    if state.selectedTextShortcut then state.selectedTextShortcut:SetShown(StatusIcons.IsTextSpec(spec)) end
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
    local isLevelText = spec.value == "levelText"
    if W.SetControlShown then
        W.SetControlShown(state.levelDifficultyColor, isLevelText)
    else
        state.levelDifficultyColor:SetShown(isLevelText)
    end
    SetOptionEnabled(state.levelDifficultyColor, isLevelText and enabled)
    local threatColorCurve, threatBackground = state.threatColorCurve, state.threatBackground
    if threatColorCurve then
        local isThreatText = spec.value == "threatText"
        if W.SetControlShown then
            W.SetControlShown(threatColorCurve, isThreatText)
            W.SetControlShown(threatBackground, isThreatText)
        else
            threatColorCurve:SetShown(isThreatText)
            threatBackground:SetShown(isThreatText)
        end
        SetOptionEnabled(threatColorCurve, isThreatText and enabled)
        SetOptionEnabled(threatBackground, isThreatText and enabled)
    end
    local isRoleIcon = spec.value == "roleIcon"
    state.roleFilterGroup:SetShown(isRoleIcon)
    if isRoleIcon then SetOptionsEnabled(state.roleFilterControls, enabled) end
    StatusIcons.RefreshIconPreviewStrip(state, spec, enabled)
    SetSectionBadgesAndStatus(state.sicons, {
        OnOffBadge(enabled, "Shown", "Hidden"),
        { text = spec and (spec.text or spec.value) or "Selected", kind = enabled and "info" or "muted" },
        { text = StatusIcons.CurrentTab() == "advanced" and "Advanced" or "Basic", kind = "accent" },
    })
end
function StatusIcons.Build(ctx, b, RefreshPage)
    local state = {}
    StatusIcons.Open(state, ctx, b, RefreshPage)
    StatusIcons.PrepareBinders(state, ctx)
    StatusIcons.BuildSelectedCard(state, ctx)
    StatusIcons.BuildPreviewCard(state, ctx)
    StatusIcons.BuildPlacement(state, ctx)
    function state.Refresh() StatusIcons.Refresh(state) end
    TrackSectionRefresh(ctx, state.sicons, state.Refresh)
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
    if M.ShowStatusFeedback then M.ShowStatusFeedback(text, kind, 3) end
end
local function RefreshSpellPage(refreshPage)
    RefreshGFPreview()
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
        -- Without spell data the runtime names the tile from the spell later
        -- (SpellRegistry EnsureTrackable); a saved placeholder would win over it.
        entry.display, entry.icon = display or entry.display, icon or entry.icon
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
    local frame = PixelLayoutRegion(CreateFrame("Frame", nil, parent, "BackdropTemplate"))
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, 150)
    frame._tiles = {}
    local self = setmetatable({
        ctx = ctx, parent = parent, frame = frame, refreshPage = refreshPage,
        label = W.LabelAt(parent, "Spells for this spec", x, y + 48, width, "GameFontNormalSmall", T.colors.accent),
        hint = W.Text(parent, "Click: edit. Right-click: toggle. Drag: reorder or preview.", x, y + 27, width, T.colors.muted),
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
        if cfg and cfg.spells and cfg.spells ~= "" then GameTooltip:AddLine(M.Format("IDs: %s", tostring(cfg.spells)), 0.55, 0.70, 0.95) end
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
        RefreshGFPreview()
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
    tile = PixelLayoutRegion(CreateFrame("Button", nil, self.frame, "BackdropTemplate"))
    tile:SetSize(self.tileSize, self.tileSize)
    tile:SetMovable(true)
    tile:EnableMouse(true)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    PixelLayoutRegion(tile, "SetBackdrop", { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    tile:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
    tile.icon = PixelLayoutRegion(tile:CreateTexture(nil, "ARTWORK"))
    tile.icon:SetSize(36, 36)
    tile.icon:SetPoint("TOP", tile, "TOP", 0, -3)
    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local addMark = PixelLayoutRegion(CreateFrame("Frame", nil, tile))
    addMark:SetSize(20, 20)
    addMark:SetPoint("CENTER", tile.icon, "CENTER")
    addMark.horizontal = PixelLayoutRegion(addMark:CreateTexture(nil, "OVERLAY"))
    addMark.horizontal:SetSize(16, 3)
    addMark.horizontal:SetPoint("CENTER")
    addMark.vertical = PixelLayoutRegion(addMark:CreateTexture(nil, "OVERLAY"))
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
    tile.label = PixelLayoutRegion(tile:CreateFontString(nil, "OVERLAY"))
    tile.label:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE")
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
    self.hint:SetText(#trackable == 0 and "No spells for this spec." or "Click: edit. Right-click: toggle. Drag: reorder or preview.")
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
    local section = b:CollapsibleSection("si_style", "Spell Icon Style", 844, false)
    local sectionW = section._msuf2Width or ctx.width or 720
    local gap, leftX = 28, 30
    local innerW = max(320, sectionW - 60)
    local leftW = max(240, min(370, floor((innerW - gap) * 0.46)))
    local rightX = leftX + leftW + gap
    local rightW = max(240, min(390, innerW - leftW - gap))
    W.ControlCard(section, "Basics", nil, leftX - 14, -38, leftW + 28, 322)
    W.ControlCard(section, "Cooldown Text", nil, rightX - 14, -38, rightW + 28, 430)
    W.ControlCard(section, "Stack Count", nil, leftX - 14, -376, leftW + 28, 296)
    W.ControlCard(section, "Duration Bar", nil, rightX - 14, -484, rightW + 28, 312)

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
            -- Scope changes refresh this page in place, so a key captured while
            -- building would become stale. The widget command resolves
            -- CurrentScope() at execution time, matching every other Group control.
            meta.searchSettingKeys = nil
            meta.searchSettingKeyPatterns = nil
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
        local control = Track(W.Slider(section, label, minValue, maxValue, step, width))
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
        local control = Track(W.ToggleAt(section, label, x, y, width))
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
        local control = Track(W.Dropdown(section, label, values, width))
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

    local iconZoom = Track(W.Slider(section, "Icon Zoom (%)", 100, 200, 1, leftW))
    local metadata = StyleMeta("spell.icon_zoom", 1)
    M.BindNumberWidget(ctx, iconZoom,
        function() return tonumber(SpellIndicators(CurrentScope()).iconZoom) or 100 end,
        function(value)
            SpellIndicators(CurrentScope()).iconZoom = tonumber(value) or 100
            ApplyStyle()
        end,
        100, metadata)
    W.MoveWidget(iconZoom, section, leftX, -72, leftW, "LEFT")

    local iconScale = Track(W.Slider(section, "Icon Scale (%)", 20, 300, 1, leftW))
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

    local opacity = Track(W.Slider(section, "Opacity", 10, 100, 5, leftW))
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
    local swipeDirection = Track(W.Dropdown(section, "Swipe Direction", VT("NORMAL", "Normal", "REVERSE", "Reverse"), rightW))
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
    W.Text(section, M.Format("Shape, border and shadow: %s. All controls here remain Group-scope aware.", M.NavPath("auras3_buffs")),
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

-- The Spell Indicators section is assembled by SpellSection.Build from one stage
-- per card. Stages share one per-build `state` table and run in the order the
-- controls used to be created inline; state.RefreshState is a RefreshProxy, so
-- callbacks bound in earlier stages reach the refresh body wired last.
local SpellSection = {}
function SpellSection.Open(state, ctx, b, RefreshPage)
    local spells = b:CollapsibleSection("si", "Spell Indicators", 848, false)
    local siW = spells._msuf2Width or ctx.width or 720
    local siGap = 28
    local siLeftX = 30
    local siInnerW = max(320, siW - 60)
    local siLeftW = max(240, min(370, floor((siInnerW - siGap) * 0.46)))
    local siRightX = siLeftX + siLeftW + siGap
    local siRightW = max(240, min(390, siInnerW - siLeftW - siGap))
    state.spellSetCard = W.ControlCard(spells, "Choose Spells", nil, siLeftX - 14, -38, siLeftW + 28, 404)
    W.ControlCard(spells, "Edit Spell", nil, siRightX - 14, -38, siRightW + 28, 404)
    state.placedIndicatorCard = W.ControlCard(spells, "Show on Frame", nil, siLeftX - 14, -456, siLeftW + 28, 560)
    state.frameHighlightCard = W.ControlCard(spells, "Highlight Health Bar", nil, siRightX - 14, -456, siRightW + 28, 360)
    state.RefreshState = M.RefreshProxy()
    function state.RequestControlRefresh(reason)
        if M.RequestRefresh then
            return M.RequestRefresh(ctx, reason or "gf-spell-indicators")
        elseif M.Refresh then
            return M.Refresh(ctx)
        end
        return RefreshPage()
    end
    state.b, state.RefreshPage, state.spells = b, RefreshPage, spells
    state.siLeftX, state.siLeftW, state.siRightX, state.siRightW = siLeftX, siLeftW, siRightX, siRightW
end
--- Show spell indicators, Layer, Spec, Preview all spells, the multi-spec pair
--- and the spell tile grid.
function SpellSection.BuildSpecControls(state, ctx)
    local spells, siLeftX, siLeftW, siRightX, siRightW = state.spells, state.siLeftX, state.siLeftW, state.siRightX, state.siRightW
    local RefreshSpellIndicatorState, RequestSpellControlRefresh = state.RefreshState, state.RequestControlRefresh
    local siEnable = W.SwitchAt(spells, "Show spell indicators", siLeftX, -72, siLeftW)
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
    local siLayer = BindNestedSlider(ctx, W.Slider(spells, "Layer (0-30)", 0, 30, 1, siRightW), SelectedSpellConfigTable, "layer", 9, "visual", "spell.selected.layer")
    W.MoveWidget(siLayer, spells, siRightX, -72, siRightW, "LEFT")
    local specDrop = W.Dropdown(spells, "Spec", SpellSpecValues, siLeftW)
    M.BindDropdownWidget(ctx, specDrop,
        function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
            CurrentSpellAura(kind)
            QueueSpellIndicators(kind)
            RefreshGFPreview()
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-spec")
        end,
        ControlMeta(ctx, "spell.spec"))
    W.MoveWidget(specDrop, spells, siLeftX, -116, siLeftW, "LEFT")
    local function PreviewAllSpecIconsEnabled()
        local previewAllState = M.gfPreviewAllSpecSpellIcons
        return type(previewAllState) == "table" and previewAllState[CurrentScope()] == true
    end
    local previewAll = T.Button(spells, "Preview all spells", siLeftW, 28)
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
        RefreshGFPreview()
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
    local multiSpecDrop = W.Dropdown(spells, "Multi-Spec Entry", function() return SpellTrackedSpecValues() end, siRightW)
    M.BindDropdownWidget(ctx, multiSpecDrop,
        function() return CurrentSpellMultiSpec(CurrentScope()) end,
        function(value)
            local kind = CurrentScope()
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[kind] = value or ""
            EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
            CurrentSpellAura(kind)
            QueueSpellIndicators(kind)
            RefreshGFPreview()
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-multi-spec")
        end,
        ControlMeta(ctx, "spell.multi_spec.selector", "ephemeral"))
    -- The Edit Spell column stacks Layer, the multi-spec pair and Aura Spell IDs
    -- above Choose spell. The multi-spec pair only shows in multi-spec mode, but
    -- it keeps its own rows so it never covers the ID input.
    W.MoveWidget(multiSpecDrop, spells, siRightX, -130, siRightW, "LEFT")
    local multiSpecEnabled = W.ToggleAt(spells, "Track selected multi spec", siRightX, -184, siRightW)
    local allSpecsHint = W.Text(spells, "Shared entries apply to every spec.", siRightX, -184, siRightW, T.colors.accent)
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
            RefreshGFPreview()
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-multi-track")
        end,
        ControlMeta(ctx, "spell.multi_spec.tracked"))
    state.spellGrid = SpellTileGrid.New(ctx, spells, siLeftX, -254, siLeftW, state.RefreshPage)
    state.siEnable, state.siLayer, state.specDrop, state.RefreshPreviewAllButton = siEnable, siLayer, specDrop, RefreshPreviewAllButton
    state.multiSpecDrop, state.multiSpecEnabled, state.allSpecsHint = multiSpecDrop, multiSpecEnabled, allSpecsHint
end
--- Edit Spell: Choose spell, Show this spell, Aura Spell IDs, Only show my
--- casts and Hide duplicate Buff icon.
function SpellSection.BuildSelectedSpell(state, ctx)
    local spells, siRightX, siRightW = state.spells, state.siRightX, state.siRightW
    local RefreshSpellIndicatorState, RequestSpellControlRefresh = state.RefreshState, state.RequestControlRefresh
    local auraDrop = W.Dropdown(spells, "Choose spell", function() return SpellAuraValues(CurrentScope()) end, siRightW)
    M.BindDropdownWidget(ctx, auraDrop,
        function() return CurrentSpellAura(CurrentScope()) end,
        function(value)
            SetCurrentSpellAura(CurrentScope(), value)
            RefreshGFPreview()
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-selection")
        end,
        ControlMeta(ctx, "spell.selected_aura", "ephemeral"))
    W.MoveWidget(auraDrop, spells, siRightX, -282, siRightW, "LEFT")
    local spellEnabled = W.SwitchAt(spells, "Show this spell", siRightX, -342, siRightW)
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
    local customSpellIDs = W.TextInput(spells, "Aura Spell IDs", siRightW)
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
    W.MoveWidget(customSpellIDs, spells, siRightX, -222, siRightW)
    local onlyMine = W.ToggleAt(spells, "Only show my casts", siRightX, -374, siRightW)
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
    local autoBlacklist = W.ToggleAt(spells, "Hide duplicate Buff icon", siRightX, -406, siRightW)
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
    state.spellEnabled, state.customSpellIDs, state.onlyMine, state.autoBlacklist = spellEnabled, customSpellIDs, onlyMine, autoBlacklist
end
--- Binders shared by the Show on Frame and Highlight Health Bar cards.
function SpellSection.PrepareBinders(state, ctx)
    local spells, siLeftX, siLeftW, siRightX, siRightW = state.spells, state.siLeftX, state.siLeftW, state.siRightX, state.siRightW
    function state.BindPlacedDropdown(label, values, key, default, y, afterSet)
        local control = W.Dropdown(spells, label, values, siLeftW)
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
        local control = W.Slider(spells, label, minValue, maxValue, step, width)
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
    state.BindConfigSlider = BindConfigSlider
    function state.BindPlacedSlider(label, minValue, maxValue, step, key, default, y)
        return BindConfigSlider(PlacedConfig, siLeftX, siLeftW, label, minValue, maxValue, step, key, default, y)
    end
    function state.BindPlacedToggle(label, key, defaultWhenPlaced, y, x, width, afterSet)
        x, width = x or siRightX, width or siRightW
        local control = W.ToggleAt(spells, label, x, y, width)
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
    function state.BindFrameSlider(label, minValue, maxValue, step, key, default, y)
        return BindConfigSlider(FrameEffectConfig, siRightX, siRightW, label, minValue, maxValue, step, key, default, y)
    end
    function state.BindSpellSubType(label, values, x, y, width, field, applyDefaults, afterSet)
        local control = W.Dropdown(spells, label, values, width)
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
    function state.ColorScopeTag()
        local kind = CurrentScope()
        return M.Format("%s: %s", GP.ScopeLabel(kind), tostring(CurrentSpellAura(kind) or ""))
    end
end
--- Show on Frame: Display as, its shape controls and the selected spell color.
function SpellSection.BuildPlacedCard(state, ctx)
    local siLeftX, siLeftW = state.siLeftX, state.siLeftW
    local RefreshSpellIndicatorState, RefreshPage = state.RefreshState, state.RefreshPage
    local BindPlacedDropdown, BindPlacedSlider, BindPlacedToggle = state.BindPlacedDropdown, state.BindPlacedSlider, state.BindPlacedToggle
    local placedType = state.BindSpellSubType("Display as", PLACED_INDICATOR_TYPES, siLeftX, -492, siLeftW, "placed",
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
        -- Re-gate this section synchronously before the page-level refresh.
        -- A page reselect runs its refreshers behind the menu-data revision
        -- guard, and the surrounding history capture only bumps that revision
        -- after this setter returns. Without the direct call the controls of
        -- the previous shape stay as they were, so switching Icon to Square
        -- left Icon Effect visible until an unrelated interaction refreshed it.
        function()
            RefreshSpellIndicatorState()
            RefreshPage()
        end)
    local placedAnchor = BindPlacedDropdown("Anchor", STATUS_ICON_ANCHORS, "anchor", "TOPLEFT", -546)
    local placedSize = BindPlacedSlider("Size", 1, 48, 1, "size", 18, -600)
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
    local placedBarTimerX = state.BindConfigSlider(PlacedConfig, siLeftX, timerSliderW,
        "Timer X", -100, 100, 1, "barTimerX", 0, -896)
    local placedBarTimerY = state.BindConfigSlider(PlacedConfig, siLeftX + timerSliderW + timerGap, timerSliderW,
        "Timer Y", -100, 100, 1, "barTimerY", 0, -896)
    state.placedColorRelevant = false
    state.placedColorShortcut = W.AttachContextColorShortcut(state.placedIndicatorCard, {
        title = "Selected Spell Color",
        note = "The selected spell color is shared by its bar, square, and icon glow.",
        tooltipTitle = "Selected Spell Color",
        tooltipText = "The selected spell color is shared by its bar, square, and icon glow.",
        scopeTag = state.ColorScopeTag,
        historySource = "menu:group-spell-indicator-color",
        isRelevant = function() return state.placedColorRelevant end,
        getTargets = function()
            local kind = CurrentScope()
            return {{
                label = "Selected Spell Color",
                getRGB = function()
                    local cfg = CurrentSpellConfig(kind, false)
                    local color = cfg and type(cfg.color) == "table" and cfg.color or CurrentAuraColor(kind)
                    return color[1] or 1, color[2] or 1, color[3] or 1
                end,
                setRGB = function(r, g, bcol)
                    local cfg = CurrentSpellConfig(kind, true)
                    if cfg then
                        local alpha = type(cfg.color) == "table" and cfg.color[4] or 1
                        cfg.color = { r, g, bcol, alpha }
                        QueueSpellIndicators(kind)
                    end
                end,
            }}
        end,
    })
    RegisterControl(state.placedColorShortcut, ctx, "spell.selected.color", "Selected Spell Color", "button", "action")
    local function RefreshPlacedControlVisibility(placed)
        local iconSelected, barSelected, barTimerSelected = ResolvePlacedSpellIndicatorControlVisibility(placed)
        if placedSize._msuf2Title then placedSize._msuf2Title:SetText(barSelected and "Height" or "Size") end
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
    state.placedType, state.placedAnchor, state.placedSize, state.placedBarWidth = placedType, placedAnchor, placedSize, placedBarWidth
    state.placedGrowth, state.placedIconEffect, state.placedBarSmoothFill = placedGrowth, placedIconEffect, placedBarSmoothFill
    state.placedBarShowTimer, state.placedBarTimerAnchor = placedBarShowTimer, placedBarTimerAnchor
    state.placedBarTimerX, state.placedBarTimerY, state.timerGap, state.timerSliderW = placedBarTimerX, placedBarTimerY, timerGap, timerSliderW
    state.RefreshPlacedControlVisibility = RefreshPlacedControlVisibility
end
--- Highlight Health Bar: Effect, its color and the effect sliders.
function SpellSection.BuildFrameCard(state, ctx)
    local spells, siRightX, siRightW = state.spells, state.siRightX, state.siRightW
    local BindFrameSlider = state.BindFrameSlider
    state.frameType = state.BindSpellSubType("Effect", FRAME_EFFECT_TYPES, siRightX, -490, siRightW, "frame",
        function(frame)
            if not frame.color then
                local c = CurrentAuraColor(CurrentScope())
                frame.color = { c[1] or 1, c[2] or 1, c[3] or 1, 0.8 }
            end
            frame.priority = frame.priority or 5
            frame.layer = tonumber(frame.layer) or 0
            frame.strata = frame.strata or "AUTO"
        end,
        state.RefreshState)
    state.frameColorRelevant = false
    state.frameColorShortcut = W.AttachContextColorShortcut(state.frameHighlightCard, {
        title = "Health bar highlight",
        tooltipTitle = "Health bar highlight",
        scopeTag = state.ColorScopeTag,
        historySource = "menu:group-spell-frame-color",
        isRelevant = function() return state.frameColorRelevant end,
        getTargets = function()
            local kind = CurrentScope()
            return {{
                label = "Health bar highlight",
                getRGB = function()
                    local frame = FrameEffectConfig(kind, false)
                    local color = frame and frame.color or CurrentAuraColor(kind)
                    return color[1] or 1, color[2] or 1, color[3] or 1
                end,
                setRGB = function(r, g, bcol)
                    local frame = FrameEffectConfig(kind, true)
                    if frame then
                        -- Same order as the Tint Alpha slider, which keeps both in step.
                        local alpha = frame.alpha or (frame.color and frame.color[4]) or 0.8
                        frame.color = { r, g, bcol, alpha }
                    end
                    QueueSpellIndicators(kind)
                end,
            }}
        end,
    })
    RegisterControl(state.frameColorShortcut, ctx, "spell.frame.color", "Health bar highlight color", "button", "action")
    state.framePriority = BindFrameSlider("Priority", 1, 10, 1, "priority", 5, -544)
    local frameAlpha = W.Slider(spells, "Tint Alpha", 5, 100, 5, siRightW)
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
    W.MoveWidget(frameAlpha, spells, siRightX, -598, siRightW, "LEFT")
    state.frameAlpha = frameAlpha
    state.frameThickness = BindFrameSlider("Border / Glow Thickness", 1, 8, 1, "thickness", 2, -652)
    state.frameLayer = BindFrameSlider("Effect Layer (0-30)", 0, 30, 1, "layer", 0, -706)
end
--- The spell grid grows by rows; the Show on Frame card and its controls move
--- down with it and the section grows to fit.
function SpellSection.RefreshGridLayout(state, rows)
    rows = max(3, tonumber(rows) or 3)
    if rows == state.spellGridLayoutRows then return end
    state.spellGridLayoutRows = rows
    local spells, spellGrid, siLeftX, siLeftW = state.spells, state.spellGrid, state.siLeftX, state.siLeftW
    local timerSliderW, timerGap = state.timerSliderW, state.timerGap
    local extra = (rows - 3) * (spellGrid.tileSize + spellGrid.gap)
    state.spellSetCard:SetHeight(404 + extra)
    state.placedIndicatorCard:ClearAllPoints()
    state.placedIndicatorCard:SetPoint("TOPLEFT", spells, "TOPLEFT", siLeftX - 14, -456 - extra)
    W.MoveWidget(state.placedType, spells, siLeftX, -492 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedAnchor, spells, siLeftX, -546 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedSize, spells, siLeftX, -600 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarWidth, spells, siLeftX, -654 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedGrowth, spells, siLeftX, -708 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedIconEffect, spells, siLeftX, -762 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarSmoothFill, spells, siLeftX, -762 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarShowTimer, spells, siLeftX, -802 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarTimerAnchor, spells, siLeftX, -842 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarTimerX, spells, siLeftX, -896 - extra, timerSliderW, "LEFT")
    W.MoveWidget(state.placedBarTimerY, spells, siLeftX + timerSliderW + timerGap, -896 - extra, timerSliderW, "LEFT")
    local contentHeight = max(1040, 1020 + extra)
    local entry = spells._msuf2CollapsibleEntry
    if entry and entry.contentHeight ~= contentHeight then
        entry.contentHeight = contentHeight
        spells:SetHeight(contentHeight)
        entry.outer:SetHeight(entry.headerHeight + (entry.open and contentHeight or 0))
        state.b:RequestRelayoutCollapsibles()
    end
end
--- One refresh gates every control of the section from the selected scope,
--- spec and spell, and sets the section badges.
function SpellSection.Refresh(state)
    local kind = CurrentScope()
    if SPELL_INDICATORS_121_PTR_DISABLED and SpellIndicators(kind).enabled ~= false then
        SpellIndicators(kind).enabled = false
        QueueSpellIndicators(kind)
    end
    EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
    SpellSection.RefreshGridLayout(state, state.spellGrid:Refresh())
    local spellCfg = SpellIndicators(kind)
    local indicatorsOn = (not SPELL_INDICATORS_121_PTR_DISABLED) and spellCfg.enabled == true
    local multi = spellCfg.spec == "multi"
    local allSpecs = multi and IsAllSpecsSpellSpec(CurrentSpellMultiSpec(kind))
    if W.SetControlShown then
        W.SetControlShown(state.multiSpecDrop, multi)
        W.SetControlShown(state.multiSpecEnabled, multi and not allSpecs)
    else
        state.multiSpecDrop:SetShown(multi)
        state.multiSpecEnabled:SetShown(multi and not allSpecs)
    end
    state.allSpecsHint:SetShown(allSpecs == true)
    local placed = PlacedConfig(kind, false)
    local hasSpell = indicatorsOn and EffectiveSpellSpec(kind) ~= nil and CurrentSpellAura(kind) ~= ""
    local currentCfg = CurrentSpellConfig(kind, false)
    local customSpell = hasSpell and IsCustomBuffEntry(CurrentSpellAura(kind), currentCfg)
    local placedEnabled = hasSpell and placed and placed.type and placed.type ~= "none"
    local frame = FrameEffectConfig(kind, false)
    local frameKind = frame and frame.type or "none"
    local hasFrame = hasSpell and frameKind ~= "none"
    state.RefreshPreviewAllButton()
    local iconSelected, barSelected, barTimerSelected = state.RefreshPlacedControlVisibility(placed)
    local cdRelevant = placedEnabled and iconSelected
    local barRelevant = placedEnabled and barSelected
    SetOptionEnabled(state.siEnable, not SPELL_INDICATORS_121_PTR_DISABLED)
    SetManyEnabled(indicatorsOn, state.siLayer, state.specDrop)
    SetOptionEnabled(state.multiSpecDrop, indicatorsOn and multi)
    SetOptionEnabled(state.multiSpecEnabled, indicatorsOn and multi and not allSpecs and CurrentSpellMultiSpec(kind) ~= "")
    local externalBlacklistManaged = hasSpell
        and CurrentSpellIsExternalDefensive(kind)
        and ExternalAutoBlacklistActive(kind)
    SetManyEnabled(hasSpell, state.spellEnabled, state.onlyMine, state.placedType)
    SetOptionEnabled(state.autoBlacklist, hasSpell and not externalBlacklistManaged)
    SetOptionEnabled(state.customSpellIDs, customSpell)
    SetManyEnabled(placedEnabled, state.placedAnchor, state.placedSize, state.placedGrowth)
    SetOptionEnabled(state.placedBarWidth, barRelevant)
    state.placedColorRelevant = placedEnabled and true or false
    if state.placedColorShortcut then state.placedColorShortcut:_msuf2RefreshContextColorVisibility() end
    SetOptionEnabled(state.placedIconEffect, cdRelevant)
    SetManyEnabled(barRelevant, state.placedBarSmoothFill, state.placedBarShowTimer)
    SetManyEnabled(barRelevant and barTimerSelected,
        state.placedBarTimerAnchor, state.placedBarTimerX, state.placedBarTimerY)
    SetOptionEnabled(state.frameType, hasSpell)
    state.frameColorRelevant = hasFrame and true or false
    if state.frameColorShortcut then state.frameColorShortcut:_msuf2RefreshContextColorVisibility() end
    SetManyEnabled(hasFrame, state.framePriority, state.frameAlpha, state.frameThickness, state.frameLayer)
    local badges = {
        OnOffBadge(indicatorsOn, "Enabled", "Disabled"),
    }
    if SPELL_INDICATORS_121_PTR_DISABLED then badges[#badges + 1] = { text = "12.1 PTR", kind = "muted", important = true } end
    badges[#badges + 1] = { text = OptionText(SpellSpecValues, SpellIndicators(kind).spec or "auto", "Auto"), kind = indicatorsOn and "info" or "muted" }
    badges[#badges + 1] = { text = hasSpell and tostring(CurrentSpellAura(kind) or "") or "No spell", kind = hasSpell and "accent" or "muted" }
    SetSectionBadgesAndStatus(state.spells, badges)
end
function SpellSection.Build(ctx, b, RefreshPage)
    local state = {}
    SpellSection.Open(state, ctx, b, RefreshPage)
    SpellSection.BuildSpecControls(state, ctx)
    SpellSection.BuildSelectedSpell(state, ctx)
    SpellSection.PrepareBinders(state, ctx)
    SpellSection.BuildPlacedCard(state, ctx)
    SpellSection.BuildFrameCard(state, ctx)
    local refresh = state.RefreshState(function() SpellSection.Refresh(state) end)
    TrackSectionRefresh(ctx, state.spells, refresh)
    GP.BuildSpellIndicatorStyleSection(ctx, b)
end

GP.BuildSpellIndicatorsSection = SpellSection.Build

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
        local slotDrop = W.Dropdown(corners, M.Format("%s Indicator", Tr(slotInfo.text or slotKey)), CICategoryValues, w)
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
            T.SetTranslatedText(customStatus, M.Format("%s is using Custom Spell. These settings are active.", Tr(slotLabel)))
            customStatus:SetTextColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 0.95)
        else
            T.SetTranslatedText(customStatus, M.Format("%s is set to %s. Set Selected Slot Indicator to Custom Spell to activate this editor.",
                Tr(slotLabel), Tr(OptionText(CICategoryValues, category, "None"))))
            customStatus:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        end
    end
    TrackSectionRefresh(ctx, corners, RefreshCornerIndicatorState)
end

local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.SelectPage(ctx.key) end
    BuildIndicatorsSection(ctx, b)
    StatusIcons.Build(ctx, b, RefreshPage)
    BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_indicators", { title = "MSUF Group Status & Indicators", build = BuildGFIndicators, version = 20 })
