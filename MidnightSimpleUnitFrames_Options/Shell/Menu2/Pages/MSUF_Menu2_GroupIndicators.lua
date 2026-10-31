local addonName, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2 or {}
-- Load-time dependency handoff; runtime callbacks retain their original local bindings.
local Parts = {}
M.GroupIndicatorsParts = Parts
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load, resolved per call so a hook installed on one later still applies.
M.RequireGlobals(FILE, {
    "MSUF_SetIconTexture",
})

-- Menu2 Group Status & Indicators page.
-- Builds party/raid status icon, placed indicator, frame effect, and spell-indicator controls.
-- Runtime indicator dispatch remains in the GroupFrames engine.
local W = M.Widgets
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.GroupOptions()
local T = M.Theme
local GP = M.GroupPage or {}
local Tr = M.TranslateText or M.Tr
local floor = math.floor
local max = math.max
local min = math.min
local table_concat = table.concat
local C_Timer = M.MenuTimer or C_Timer
local VT = M.ValueTextList
local WHITE_RGB = { 1, 1, 1 }
local SPELL_INDICATORS_121_PTR_DISABLED = false
local issecretvalue = MSUF.Util.IsSecret
local STATUS_ICON_RESET_FIELDS = M.WordList "size anchor x y layer iconStyle customIcon"
local STATUS_ICON_ANCHORS, GF_STATUS_ICON_SPECS = GP.STATUS_ICON_ANCHORS or {}, GP.GF_STATUS_ICON_SPECS or {}
local GF_STATUS_ICON_VALUES, PLACED_INDICATOR_TYPES = GP.GF_STATUS_ICON_VALUES or {}, GP.PLACED_INDICATOR_TYPES or {}
local FRAME_EFFECT_TYPES, ICON_EFFECT_TYPES, SPELL_GROWTH_VALUES = GP.FRAME_EFFECT_TYPES or {}, GP.ICON_EFFECT_TYPES or {}, GP.SPELL_GROWTH_VALUES or {}
local CI_SLOT_VALUES, CI_SLOT_DEFAULTS = GP.CI_SLOT_VALUES or {}, GP.CI_SLOT_DEFAULTS or {}
local GF, RefreshGFPreview, Conf, Val, QueueGF, Set, Bool, Num = GP.GF, GP.RefreshGFPreview, GP.Conf, GP.Val, GP.QueueGF, GP.Set, GP.Bool, GP.Num
local ScopeSection, CurrentScope = GP.ScopeSection, GP.CurrentScope
local SpellIndicators, IconStyleValues = GP.SpellIndicators, GP.IconStyleValues
local CurrentGFStatusSpec, QueueSpellIndicators, SpellSpecValues = GP.CurrentGFStatusSpec, GP.QueueSpellIndicators, GP.SpellSpecValues
local SpellTrackedSpecValues, IsAllSpecsSpellSpec, CurrentSpellMultiSpec = GP.SpellTrackedSpecValues, GP.IsAllSpecsSpellSpec, GP.CurrentSpellMultiSpec
local EffectiveSpellSpec, SpellAuraValues, SetCurrentSpellAura = GP.EffectiveSpellSpec, GP.SpellAuraValues, GP.SetCurrentSpellAura
local ClearCurrentSpellAura, CurrentSpellAura, CurrentSpellConfig = GP.ClearCurrentSpellAura, GP.CurrentSpellAura, GP.CurrentSpellConfig
local PlacedConfig, FrameEffectConfig, CICategoryValues, CIFilterValues = GP.PlacedConfig, GP.FrameEffectConfig, GP.CICategoryValues, GP.CIFilterValues
local CIModeValues, CurrentCISlot, CICustomConfig = GP.CIModeValues, GP.CurrentCISlot, GP.CICustomConfig
local SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage = GP.SetOptionEnabled, GP.SetOptionsEnabled, GP.FinalizeScopePage
local SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge = GP.SetSectionBadgesAndStatus, GP.TrackSectionRefresh, GP.OnOffBadge
local OptionText, ControlMeta, RegisterControl = GP.OptionText, GP.ControlMeta, GP.RegisterControl
OnOffBadge = OnOffBadge or M.OnOffBadge
OptionText = OptionText or M.OptionText
ROW_OPTIONS.register = function(ctx, widget, row)
    RegisterControl(widget, ctx, row.path, row[4][1], row[1], row.classification, row.exact)
    Schema.Owned(widget, "group", row.classification or "visual")
end
-- A corner Custom Spell slot's "When: Show when missing" needs the Classic scan
-- backend (Game/Classic/Auras), the same fact the custom container reminders key
-- on. A Retail or WoW Forever AuraContainer slot never tells MSUF that its aura
-- is absent, so there the choice is offered disabled with its reason. A stored
-- "missing" stays as it is; the runtime shows such a slot while the aura is up.
local CORNER_MISSING_AVAILABLE = MSUF.Client.IsClassic == true
local CORNER_MISSING_NOTICE = "Show when missing is unavailable on this client. Saved settings are kept; the slot shows when present."
local CORNER_MISSING_NOTE_GAP = CORNER_MISSING_AVAILABLE and 0 or 32
local cornerModeSource, cornerModeValues
local function CornerModeValues()
    local values = CIModeValues()
    if CORNER_MISSING_AVAILABLE then return values end
    if cornerModeSource ~= values then
        cornerModeSource, cornerModeValues = values, {}
        for i = 1, #values do
            local copy = {}
            for key, value in pairs(values[i]) do copy[key] = value end
            if copy.value == "missing" then copy.disabled = true end
            cornerModeValues[i] = copy
        end
    end
    return cornerModeValues
end
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
    local cs = C_Spell
    local resolver = cs and cs.GetSpellIDForSpellIdentifier
    if type(resolver) ~= "function" then return nil end
    local spellID = resolver(identifier)

    if issecretvalue(spellID) == true then return nil end
    local out, seen = {}, {}
    AddCustomBuffSpellID(out, seen, spellID)
    return #out > 0 and out or nil
end

local function RequestCustomBuffSpellData(spellIDs)
    local request = C_Spell and C_Spell.RequestLoadSpellData
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
    local cs = C_Spell
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
    if (not name or not icon) and type(GetSpellInfo) == "function" then
        local n, _, tex = GetSpellInfo(spellID)
        if issecretvalue(n) ~= true then name = name or n end
        if issecretvalue(tex) ~= true then icon = icon or tex end
    end
    return name, icon
end

local function SuggestedActivePlayerAuraID(spellIDs)
    if type(spellIDs) ~= "table" or #spellIDs ~= 1 then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local enteredID = spellIDs[1]
    local spellName = CustomBuffInfo(enteredID)
    if issecretvalue(spellName) == true or type(spellName) ~= "string" or spellName == "" then return nil end
    local getByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
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

-- The color shortcut of a card whose single color is shared by Party, Raid and Mythic Raid.
local function SharedColors(card, reference, title, historySource)
    Schema.Colors(card, { reference }, {
        title = title, note = "Shared by Party, Raid and Mythic Raid.", historySource = historySource, offsetX = -76,
    })
end
local function BuildIndicatorsSection(ctx, b)
    local indicators = b:CollapsibleSection("indicators", "Frame Indicators", 710, true)
    local leftX, leftW, rightX, rightW, innerW = Schema.Columns(indicators, ctx.width, 20, 16, 0.48)
    local highlightCard = W.ControlCard(indicators, "Target Highlight",
        "Shows a border around the current target in group frames. Aggro and dispel borders are controlled in Bars.",
        leftX, -38, innerW, 92)
    SharedColors(highlightCard, "group.target", "Target Highlight Color", "menu:group-target-highlight-color")
    local targetToggle = Schema.Build(ctx, highlightCard, {
        { "switch", "targetIndicator", true, { "Target Highlight", innerW - 62, -24, 0, "HIDDEN" },
            flagsAfter = { _msuf2GroupFrameGateAlwaysEnabled = true } },
    }, ROW_OPTIONS).targetIndicator
    local groupNumberCard = W.ControlCard(indicators, "Group Number", nil, leftX, -148, leftW, 320)
    Schema.Colors(groupNumberCard, nil, {
        title = "Group Number Text Settings", historyLabel = "Group number text color",
        historySource = "menu:group-number-text-color", offsetX = -76,
        textSettings = {
            scope = function() return CurrentScope() end,
            group = true,
            kind = "status",
            subtitle = "Font style and color are synchronized with the Fonts menu for this group scope.",
            colorTitle = "Group number text color",
            capabilities = { baseline = false },
        },
    })
    local groupNumber = Schema.Build(ctx, groupNumberCard, {
        { "switch", "showGroupNumber", false, { "Group Number", leftW - 62, -24, 0, "HIDDEN" },
            flagsAfter = { _msuf2GroupFrameGateAlwaysEnabled = true } },
        -- The styles and all nine anchors match the runtime formatter and preview drag handle.
        { "dropdown", "groupNumberStyle", "PAREN", { "Style", GROUP_NUMBER_STYLES, leftW }, { 16, -66, leftW - 32, "LEFT" } },
        { "slider", "groupNumberSize", 10, { "Size", 6, 24, 1, leftW }, { 16, -116, leftW - 58, "CENTER" }, domain = "font" },
        { "dropdown", "groupNumberAnchor", "BOTTOMRIGHT", { "Anchor", STATUS_ICON_ANCHORS, leftW },
            { 16, -166, leftW - 32, "LEFT" }, domain = "geometry" },
        { "slider", "groupNumberLayer", 7, { "Layer", 0, 30, 1, leftW }, { 16, -216, leftW - 58, "CENTER" } },
    }, ROW_OPTIONS)
    local groupNumberToggle = groupNumber.showGroupNumber
    local groupNumberControls = { groupNumber.groupNumberStyle, groupNumber.groupNumberSize,
        groupNumber.groupNumberAnchor, groupNumber.groupNumberLayer }
    local groupNumberScopeHint = W.Text(groupNumberCard, "", 16, -268, leftW - 32, T.colors.muted)
    if groupNumberScopeHint.SetWordWrap then groupNumberScopeHint:SetWordWrap(true) end
    local focusCard = W.ControlCard(indicators, "Focus Highlight", "Shows a colored border around your Focus target. " ..
        "Priority: Dispel > Aggro > Target > Focus.", rightX, -148, rightW, 190)
    SharedColors(focusCard, "group.focus", "Focus Highlight Color", "menu:group-focus-highlight-color")
    local focusToggle = Schema.Build(ctx, focusCard, {
        { "switch", "hlFocusEnabled", true, { "Focus Highlight", rightW - 62, -24, 0, "HIDDEN" },
            flagsAfter = { _msuf2GroupFrameGateAlwaysEnabled = true } },
    }, ROW_OPTIONS).hlFocusEnabled
    local focusHint = focusCard and focusCard.subtitle
    if focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    local focusControls = { Schema.Build(ctx, focusCard, {
        { "slider", "hlFocusSize", 2, { "Border Thickness", 1, 6, 1, rightW }, { 16, -88, rightW - 58, "CENTER" } },
    }, ROW_OPTIONS).hlFocusSize }
    local focusColorHint = W.Text(focusCard, M.Format("Focus color is in %s.",
        M.NavPath("opt_colors", "Party & Raid Frames")), 16, -142, rightW - 32, T.colors.muted)
    if focusColorHint.SetWordWrap then focusColorHint:SetWordWrap(true) end
    local groupBorderCard = W.ControlCard(indicators, "Group Border", nil, leftX, -486, leftW, 202)
    SharedColors(groupBorderCard, "group.border", "Group Border Color", "menu:group-border-color")
    local groupBorder = Schema.Build(ctx, groupBorderCard, {
        { "switch", "groupBorderEnabled", false, { "Group Border", leftW - 62, -24, 0, "HIDDEN" },
            flagsAfter = { _msuf2GroupFrameGateAlwaysEnabled = true } },
        { "slider", "groupBorderSize", 1, { "Border Thickness", 1, 12, 1, leftW }, { 16, -66, leftW - 58, "CENTER" } },
        { "slider", "groupBorderPadding", 2, { "Padding", 0, 40, 1, leftW }, { 16, -116, leftW - 58, "CENTER" } },
    }, ROW_OPTIONS)
    local groupBorderToggle = groupBorder.groupBorderEnabled
    local groupBorderControls = { groupBorder.groupBorderSize, groupBorder.groupBorderPadding }
    local groupBorderColorHint = W.Text(groupBorderCard, M.Format("Border color and opacity are in %s.",
        M.NavPath("opt_colors", "Party & Raid Frames")), 16, -168, leftW - 32, T.colors.muted)
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
        SetOptionEnabled(targetToggle, true)
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
            { text = groupNumberEnabled and "Group #" or (groupBorderEnabled and "Group border" or "Clean"), kind = (groupNumberEnabled or groupBorderEnabled)
                and "accent" or "muted" },
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
-- The pack probe and the texture resolver run from refreshes and dropdown sources, so each core
-- function is resolved once, on first use (the core publishes both before this page loads).
local packSupports
--- Each style value carries its own Midnight flag now, so the support probe runs per entry
--- and silently drops packs that ship no art for the selected indicator.
function StatusIcons.IconPackValues()
    local values = IconPackValues()
    local spec = CurrentGFStatusSpec()
    local entries = StatusIcons.PreviewEntries(spec)
    if type(entries) ~= "table" then return values end
    packSupports = packSupports or MSUF.Require("MSUF_StatusIconPackSupports", FILE)
    local supports = packSupports
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
    return M.UnitPage.StatusIconAssetValues(StatusIcons.PreviewEntries(CurrentGFStatusSpec()))
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
    local siconLeftX, siconLeftW, siconRightX, siconRightW, siconInnerW, siconW =
        Schema.Columns(sicons, ctx.width, 20, 16, 0.46)
    M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
    local siconTabFrames = {}
    local siconBasicTab, siconAdvancedTab = M.UnitSectionsShared.MakeTabFrames(sicons, -64, siconW, siconTabFrames, "basic", "advanced")
    local statusTabs, RefreshStatusTabs, ReadStatusTab, SetGuidedStatusTab = W.SegmentTabs(ctx, sicons, {
        get = StatusIcons.CurrentTab,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
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
-- Status declarations share the selected-field binder with their own GP readers.
local STATUS_ROW_OPTIONS = Schema.GroupSelectedOptions({
    selected = CurrentGFStatusSpec, specs = GF_STATUS_ICON_SPECS, scope = CurrentScope, default = StatusIcons.SpecDefault,
    bool = Bool, number = Num, value = Val, write = Set,
    path = "status.selected.", meta = ControlMeta, stepMeta = StepMeta,
})
--- Release links into the selected indicator's switch: Level Text in each
--- group scope. The hook selects the scope, the indicator and the Basic tab.
function StatusIcons.DeclareExactLevelText(state, control)
    local values = {}
    for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
        if MSUF.Client.SupportsGroupKind(scope) then values[scope .. "_levelText"] = "gf_" .. scope .. ".levelText" end
    end
    M.DeclareExactViewContract(control, "groupStatus", values, function(value)
        local scope = value:match("^(%a+)_")
        M.SetMenuStateValue("gfScope", scope)
        M.SetMenuStateValue("gfStatusIconSelection", "levelText")
        if state.sicons._msuf2GuidedSelectTab then state.sicons._msuf2GuidedSelectTab("basic") end
        state.RefreshStatusIconMenu()
        return CurrentScope() == scope and CurrentGFStatusSpec().value == "levelText"
    end)
end
--- An option of one indicator (Threat %, the Level Text difficulty color) shows
--- only while that indicator is selected and edits the current scope: an exact
--- link selects the indicator there. That is its only view, so it replaces the
--- tab contract the control inherited (the selection opens that tab itself).
function StatusIcons.DeclareExactStatusOption(state, control, status)
    if not control then return end
    control._msuf2ExactTargetKinds, control._msuf2ExactTargetContracts = nil, nil
    M.DeclareExactViewContract(control, "groupStatusOption", { [status] = true }, function(value)
        M.SetMenuStateValue("gfStatusIconSelection", value)
        if state.sicons._msuf2GuidedSelectTab then state.sicons._msuf2GuidedSelectTab("basic") end
        state.RefreshStatusIconMenu()
        return CurrentGFStatusSpec().value == value
    end)
end
--- Selected Indicator: the indicator, its switch, its style and icon, the
--- Level Text and Threat % options and the role filter.
function StatusIcons.RegisterSearchChoices(state, ctx, selector)
    for _, scopeInfo in ipairs(GP.SCOPE_VALUES) do
        local scope = scopeInfo.value
        if MSUF.Client.SupportsGroupKind(scope) then
            local section = ControlMeta(ctx, "status.section." .. scope, "navigation")
            section.kind, section.label, section.anchor, section.sectionId = "section", "Status Icons", selector, "sicons"
            section.schemaEphemeralReason = "Opens the status editor; no profile setting is written."
            section.searchIndexed, section.navigationKey, section.keywords = true, ctx.key, { scope, scopeInfo.text }
            section.searchPrepareKind, section.searchPrepareValue = "groupScope", scope
            section.prepareExactSearchTarget = function()
                M.SetMenuStateValue("gfScope", scope)
                return state.sicons._msuf2GuidedSelectTab("basic")
            end
            M.RegisterVirtualRuntimeControl(section, "group-status-section")
            for _, spec in ipairs(GF_STATUS_ICON_SPECS) do
                local meta = ControlMeta(ctx, "status.indicator." .. scope .. "." .. spec.value:lower(), "navigation")
                meta.kind, meta.label, meta.anchor = "control", spec.text, selector
                meta.schemaEphemeralReason = "Selects the status editor view; no profile setting is written."
                meta.searchIndexed, meta.navigationKey, meta.sectionId = true, ctx.key, "sicons"
                meta.keywords = { "status icons", "status indicator", scope, scopeInfo.text,
                    spec.value == "roleIcon" and "Rollensymbol" or spec.text }
                meta.searchPrepareKind, meta.searchPrepareValue = "groupStatus", scope .. "_" .. spec.value
                meta.prepareExactSearchTarget = function(_, target)
                    if target.prepareValue ~= scope .. "_" .. spec.value then return false end
                    M.SetMenuStateValue("gfScope", scope)
                    M.SetMenuStateValue("gfStatusIconSelection", spec.value)
                    if state.sicons._msuf2GuidedSelectTab("basic") == false then return false end
                    selector:SetValue(spec.value)
                    state.RefreshStatusIconMenu()
                    return CurrentGFStatusSpec().value == spec.value
                end
                M.RegisterVirtualRuntimeControl(meta, "group-status-indicator")
            end
        end
    end
end
function StatusIcons.BuildSelectedCard(state, ctx)
    local selectedCard, siconLeftW = state.selectedCard, state.siconLeftW
    local RefreshStatusIconMenu = state.RefreshStatusIconMenu
    local selectionRows = Schema.GroupCommands({ selector = {
        get = function() return CurrentGFStatusSpec().value end,
        customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(value)
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
    } }, ControlMeta, StepMeta)
    local selector = Schema.Build(ctx, selectedCard, {
        { "dropdown", "selector", nil, { "Indicator", GF_STATUS_ICON_VALUES, siconLeftW },
            { 16, -54, siconLeftW - 32, "LEFT" }, path = "status.selector", classification = "ephemeral" },
    }, selectionRows).selector
    StatusIcons.RegisterSearchChoices(state, ctx, selector)
    local statusEnabled = Schema.Build(ctx, selectedCard, {
        { "switch", "enabled", false, { "Enabled", siconLeftW - 62, -24, 0, "HIDDEN" },
            beforeBind = function(control) control._msuf2GroupFrameGateAlwaysEnabled = true end,
            afterSet = RefreshStatusIconMenu },
    }, STATUS_ROW_OPTIONS).enabled
    StatusIcons.DeclareExactLevelText(state, statusEnabled)
    local function RefreshSelectedIcon()
        RefreshGFPreview()
        if state.Refresh then state.Refresh() end
    end
    local selectedRows = Schema.Build(ctx, selectedCard, {
        { "dropdown", "iconStyle", "DEFAULT", { "Indicator style", StatusIcons.IconPackValues, siconLeftW },
            { 16, -106, siconLeftW - 32, "LEFT" }, get = StatusIcons.CurrentIconStyle, afterSet = RefreshSelectedIcon },
        { "dropdown", "customIcon", "", { "Custom icon", StatusIcons.IconAssetValues, siconLeftW },
            { 16, -158, siconLeftW - 32, "LEFT" }, afterSet = RefreshSelectedIcon },
    }, STATUS_ROW_OPTIONS)
    local iconPack, customIcon = selectedRows.iconStyle, selectedRows.customIcon
    --- Level Text only: the same difficulty grading as the unit-frame level indicator.
    local levelDifficultyColor = Schema.Build(ctx, selectedCard, {
        { "toggle", "levelTextDifficultyColor", true, { "Color by level difficulty", 16, -106, siconLeftW - 32 },
            tip = { "Color by level difficulty",
                "Red far above your level, white at your level, gray when trivial. Turn off to use the status text color instead.", { hook = true } } },
    }, ROW_OPTIONS).levelTextDifficultyColor
    StatusIcons.DeclareExactStatusOption(state, levelDifficultyColor, "levelText")
    --- Threat % only (MSUF.Client.SupportsThreatText): the unit frames' threat color curve
    --- and the dark plate behind the number (on for Party, off for Raid by default).
    local threatColorCurve, threatBackground
    if MSUF.Client.SupportsThreatText == true then
        local threatRows = Schema.Build(ctx, selectedCard, {
            { "toggle", "threatTextColorCurve", true, { "Color by threat", 16, -106, siconLeftW - 32 },
                tip = { "Color by threat",
                    "Green at low threat, yellow at half, pink at 100% when you have aggro. Turn off to use the status text color instead.",
                        { hook = true } } },
            { "toggle", "threatTextBackground", false, { "Background", 16, -136, siconLeftW - 32 },
                tip = { "Background", "A dark plate behind the number keeps it readable on any bar color, red enemy bars included.", { hook = true } } },
        }, ROW_OPTIONS)
        threatColorCurve, threatBackground = threatRows.threatTextColorCurve, threatRows.threatTextBackground
        StatusIcons.DeclareExactStatusOption(state, threatColorCurve, "threatText")
        StatusIcons.DeclareExactStatusOption(state, threatBackground, "threatText")
    end

    --- Role filter group: only visible when Role Icon indicator is selected
    local roleFilterGroup = PixelLayoutRegion(CreateFrame("Frame", nil, selectedCard))
    roleFilterGroup:SetPoint("TOPLEFT", selectedCard, "TOPLEFT", 0, -216)
    local roleFilterW = max(180, siconLeftW - 32)
    roleFilterGroup:SetSize(roleFilterW, 60)
    W.LabelAt(roleFilterGroup, "Show for:", 16, -8, siconLeftW - 32, "GameFontNormalSmall", T.colors.accent)
    local rfColW   = floor(roleFilterW / 3)
    local rfLabelW = max(34, rfColW - 30)  --- subtract checkbox(24) + gap(6) so hit areas don't overlap the next column
    local roleRows = Schema.Build(ctx, roleFilterGroup, {
        { "toggle", "roleIconShowTank", true, { "Tank", 16, -26, rfLabelW } },
        { "toggle", "roleIconShowHealer", true, { "Healer", 16 + rfColW, -26, rfLabelW } },
        { "toggle", "roleIconShowDPS", true, { "DPS", 16 + rfColW * 2, -26, rfLabelW } },
    }, ROW_OPTIONS)
    local rfTank, rfHealer, rfDPS = roleRows.roleIconShowTank, roleRows.roleIconShowHealer, roleRows.roleIconShowDPS
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
    local iconPreviewStrip, iconPreviewTextures = M.UnitPage.CreateStatusIconStrip(previewCard, -132, previewInnerW)
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
    local cfg = { style = StatusIcons.CurrentIconStyle(),
        customIcon = spec.customIcon and Val(CurrentScope(), spec.customIcon, "") or nil }
    local status = { kind = CurrentScope(), useMidnight = false }
    iconPreviewStrip:SetAlpha(enabled and 1 or 0.46)
    for i = 1, #iconPreviewTextures do
        local holder, entry = iconPreviewTextures[i], entries[i]
        if entry and MSUF.UFStatusRuntime.PaintIconSample(holder.tex, cfg, status, entry[1], entry[2]) then
            holder.tex:SetVertexColor(1, 1, 1, 1)
            holder:Show()
        else
            holder:Hide()
        end
    end
end
--- Placement (Basic tab) and Advanced Placement (Advanced tab).
function StatusIcons.BuildPlacement(state, ctx)
    local siconLeftX, siconLeftW, siconRightX, siconRightW = state.siconLeftX, state.siconLeftW, state.siconRightX, state.siconRightW
    local PreviewActionButton, statusReset, previewCurrent, previewAll = state.PreviewActionButton, state.statusReset, state.previewCurrent, state.previewAll
    state.statusControls = Schema.Build(ctx, state.placementCard, {
        { "slider", "size", function(spec) return spec.defaultSize end, { "Size", 6, 40, 1, siconRightW },
            { 16, -58, siconRightW - 58, "LEFT" }, domain = "visual" },
        { "dropdown", "anchor", function(spec) return spec.defaultAnchor end, { "Anchor", STATUS_ICON_ANCHORS, siconRightW },
            { 16, -108, siconRightW - 32, "LEFT" }, domain = "geometry" },
    }, STATUS_ROW_OPTIONS)
    local advanced = {}
    advanced.card = W.ControlCard(state.siconAdvancedTab, "Advanced Placement", nil, siconLeftX, -38, state.siconInnerW, 232)
    M.Assign(advanced, Schema.Build(ctx, advanced.card, {
        { "slider", "layer", function(spec) return spec.defaultLayer end, { "Layer", 0, 30, 1, siconLeftW },
            { 16, -58, siconLeftW - 58, "LEFT" }, domain = "visual", clamp = true, identitySuffix = "extended" },
    }, STATUS_ROW_OPTIONS))
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
    StatusIcons.BuildSelectedCard(state, ctx)
    StatusIcons.BuildPreviewCard(state, ctx)
    StatusIcons.BuildPlacement(state, ctx)
    function state.Refresh() StatusIcons.Refresh(state) end
    TrackSectionRefresh(ctx, state.sicons, state.Refresh)
end

-- Spell data operations live outside the page builder so UI closures retain only page state.
-- All lookups continue to use the runtime's 12.1-safe AuraSlot/SpellID registries.

-- Explicit load-time exports for the following responsibility modules.
Parts.AddCustomBuffSpellID = AddCustomBuffSpellID
Parts.Bool = Bool
Parts.BuildIndicatorsSection = BuildIndicatorsSection
Parts.CICategoryValues = CICategoryValues
Parts.CICustomConfig = CICustomConfig
Parts.CIFilterValues = CIFilterValues
Parts.CI_SLOT_DEFAULTS = CI_SLOT_DEFAULTS
Parts.CI_SLOT_VALUES = CI_SLOT_VALUES
Parts.CORNER_MISSING_AVAILABLE = CORNER_MISSING_AVAILABLE
Parts.CORNER_MISSING_NOTE_GAP = CORNER_MISSING_NOTE_GAP
Parts.CORNER_MISSING_NOTICE = CORNER_MISSING_NOTICE
Parts.CUSTOM_BUFF_COLOR = CUSTOM_BUFF_COLOR
Parts.CUSTOM_BUFF_LIMIT = CUSTOM_BUFF_LIMIT
Parts.C_Timer = C_Timer
Parts.ClearCurrentSpellAura = ClearCurrentSpellAura
Parts.Conf = Conf
Parts.ControlMeta = ControlMeta
Parts.CornerModeValues = CornerModeValues
Parts.CurrentCISlot = CurrentCISlot
Parts.CurrentScope = CurrentScope
Parts.CurrentSpellAura = CurrentSpellAura
Parts.CurrentSpellConfig = CurrentSpellConfig
Parts.CurrentSpellMultiSpec = CurrentSpellMultiSpec
Parts.CustomBuffInfo = CustomBuffInfo
Parts.CustomBuffSpellID = CustomBuffSpellID
Parts.CustomBuffSpellIDListText = CustomBuffSpellIDListText
Parts.CustomBuffSpellIDs = CustomBuffSpellIDs
Parts.DefaultCustomBuffPlaced = DefaultCustomBuffPlaced
Parts.EffectiveSpellSpec = EffectiveSpellSpec
Parts.FRAME_EFFECT_TYPES = FRAME_EFFECT_TYPES
Parts.FinalizeScopePage = FinalizeScopePage
Parts.FrameEffectConfig = FrameEffectConfig
Parts.GF = GF
Parts.GP = GP
Parts.ICON_EFFECT_TYPES = ICON_EFFECT_TYPES
Parts.IsAllSpecsSpellSpec = IsAllSpecsSpellSpec
Parts.IsCustomBuffEntry = IsCustomBuffEntry
Parts.OnOffBadge = OnOffBadge
Parts.OptionText = OptionText
Parts.PLACED_INDICATOR_TYPES = PLACED_INDICATOR_TYPES
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.PlacedConfig = PlacedConfig
Parts.QueueGF = QueueGF
Parts.QueueSpellIndicators = QueueSpellIndicators
Parts.ROW_OPTIONS = ROW_OPTIONS
Parts.RefreshGFPreview = RefreshGFPreview
Parts.RegisterControl = RegisterControl
Parts.RequestCustomBuffSpellData = RequestCustomBuffSpellData
Parts.ResolveCustomBuffSpellIDs = ResolveCustomBuffSpellIDs
Parts.ResolvePlacedSpellIndicatorControlVisibility = ResolvePlacedSpellIndicatorControlVisibility
Parts.SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES
Parts.SPELL_INDICATORS_121_PTR_DISABLED = SPELL_INDICATORS_121_PTR_DISABLED
Parts.STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS
Parts.Schema = Schema
Parts.ScopeSection = ScopeSection
Parts.SetCurrentSpellAura = SetCurrentSpellAura
Parts.SetManyEnabled = SetManyEnabled
Parts.SetOptionEnabled = SetOptionEnabled
Parts.SetOptionsEnabled = SetOptionsEnabled
Parts.SetSectionBadgesAndStatus = SetSectionBadgesAndStatus
Parts.SpellAuraValues = SpellAuraValues
Parts.SpellIndicators = SpellIndicators
Parts.SpellSpecValues = SpellSpecValues
Parts.SpellTrackedSpecValues = SpellTrackedSpecValues
Parts.StatusIcons = StatusIcons
Parts.StepMeta = StepMeta
Parts.SuggestedActivePlayerAuraID = SuggestedActivePlayerAuraID
Parts.T = T
Parts.Tr = Tr
Parts.TrackSectionRefresh = TrackSectionRefresh
Parts.VT = VT
Parts.Val = Val
Parts.W = W
Parts.WHITE_RGB = WHITE_RGB
Parts.floor = floor
Parts.issecretvalue = issecretvalue
Parts.max = max
Parts.min = min
