local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load, called through _G so a hook installed on one later still applies.
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua", {
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
local CORNER_MISSING_AVAILABLE = MSUF.Client and MSUF.Client.IsClassic == true or false
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
    local leftX, leftW, rightX, rightW, innerW = Schema.Columns(indicators, ctx.width, 20, 16, 0.48)
    local highlightCard = W.ControlCard(indicators, "Target Highlight",
        M.Format("Configure target highlighting in %s.", M.NavPath("opt_misc", "Frame Highlights")),
        leftX, -38, innerW, 92)
    Schema.Colors(highlightCard, { "group.target" }, {
        title = "Target Highlight Color", note = "Shared by Party, Raid and Mythic Raid.",
        historySource = "menu:group-target-highlight-color", offsetX = -76,
    })
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
    local openHighlights = Schema.Build(ctx, highlightCard, {
        { "button", "openHighlights", nil, { "Open Highlights", 132, 22 }, anchor = { "TOPRIGHT", highlightCard, "TOPRIGHT", -16, -56 },
            center = true, tip = { "Open Highlights", M.NavPath("opt_misc", "Frame Highlights"), { hook = true } },
            action = OpenFrameHighlights, register = true, path = "navigation.frame_highlights",
            classification = "navigation", exact = { navigationKey = "opt_misc" } },
    }, ROW_OPTIONS).openHighlights
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
        { "switch", "showGroupNumber", false, { "Group Number", leftW - 62, -24, 0, "HIDDEN" } },
        -- The styles and all nine anchors match the runtime formatter and preview drag handle.
        { "dropdown", "groupNumberStyle", "PAREN", { "Style", GROUP_NUMBER_STYLES, leftW }, { 16, -66, leftW - 32, "LEFT" } },
        { "slider", "groupNumberSize", 10, { "Size", 6, 24, 1, leftW }, { 16, -116, leftW - 58, "CENTER" }, domain = "font" },
        { "dropdown", "groupNumberAnchor", "BOTTOMRIGHT", { "Anchor", STATUS_ICON_ANCHORS, leftW },
            { 16, -166, leftW - 32, "LEFT" }, domain = "geometry" },
        { "slider", "groupNumberLayer", 7, { "Layer", 0, 30, 1, leftW }, { 16, -216, leftW - 58, "CENTER" } },
    }, ROW_OPTIONS)
    local groupNumberToggle = groupNumber.showGroupNumber
    groupNumberToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupNumberControls = { groupNumber.groupNumberStyle, groupNumber.groupNumberSize,
        groupNumber.groupNumberAnchor, groupNumber.groupNumberLayer }
    local groupNumberScopeHint = W.Text(groupNumberCard, "", 16, -268, leftW - 32, T.colors.muted)
    if groupNumberScopeHint.SetWordWrap then groupNumberScopeHint:SetWordWrap(true) end
    local focusCard = W.ControlCard(indicators, "Focus Highlight", "Shows a colored border around your Focus target. Priority: Dispel > Aggro > Target > Focus.", rightX, -148, rightW, 190)
    Schema.Colors(focusCard, { "group.focus" }, {
        title = "Focus Highlight Color", note = "Shared by Party, Raid and Mythic Raid.",
        historySource = "menu:group-focus-highlight-color", offsetX = -76,
    })
    local focusToggle = Schema.Build(ctx, focusCard, {
        { "switch", "hlFocusEnabled", true, { "Focus Highlight", rightW - 62, -24, 0, "HIDDEN" } },
    }, ROW_OPTIONS).hlFocusEnabled
    focusToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local focusHint = focusCard and focusCard.subtitle
    if focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    local focusControls = { Schema.Build(ctx, focusCard, {
        { "slider", "hlFocusSize", 2, { "Border Thickness", 1, 6, 1, rightW }, { 16, -88, rightW - 58, "CENTER" } },
    }, ROW_OPTIONS).hlFocusSize }
    local focusColorHint = W.Text(focusCard, M.Format("Focus color is in %s.", M.NavPath("opt_colors", "Party & Raid Frames")), 16, -142, rightW - 32, T.colors.muted)
    if focusColorHint.SetWordWrap then focusColorHint:SetWordWrap(true) end
    local groupBorderCard = W.ControlCard(indicators, "Group Border", nil, leftX, -486, leftW, 202)
    Schema.Colors(groupBorderCard, { "group.border" }, {
        title = "Group Border Color", note = "Shared by Party, Raid and Mythic Raid.",
        historySource = "menu:group-border-color", offsetX = -76,
    })
    local groupBorder = Schema.Build(ctx, groupBorderCard, {
        { "switch", "groupBorderEnabled", false, { "Group Border", leftW - 62, -24, 0, "HIDDEN" } },
        { "slider", "groupBorderSize", 1, { "Border Thickness", 1, 12, 1, leftW }, { 16, -66, leftW - 58, "CENTER" } },
        { "slider", "groupBorderPadding", 2, { "Padding", 0, 40, 1, leftW }, { 16, -116, leftW - 58, "CENTER" } },
    }, ROW_OPTIONS)
    local groupBorderToggle = groupBorder.groupBorderEnabled
    groupBorderToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupBorderControls = { groupBorder.groupBorderSize, groupBorder.groupBorderPadding }
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
    return M.UnitPage.StatusIconAssetValues(StatusIcons.PreviewEntries(CurrentGFStatusSpec()))
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
    local siconLeftX, siconLeftW, siconRightX, siconRightW, siconInnerW, siconW =
        Schema.Columns(sicons, ctx.width, 20, 16, 0.46)
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
-- Status declarations share the selected-field binder with their own GP readers.
local STATUS_ROW_OPTIONS = Schema.GroupSelectedOptions({
    selected = CurrentGFStatusSpec, scope = CurrentScope, default = StatusIcons.SpecDefault,
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
function StatusIcons.BuildSelectedCard(state, ctx)
    local selectedCard, siconLeftW = state.selectedCard, state.siconLeftW
    local RefreshStatusIconMenu = state.RefreshStatusIconMenu
    local selectionRows = Schema.GroupCommands({ selector = {
        get = function() return CurrentGFStatusSpec().value end,
        set = function(value)
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
    Schema.Build(ctx, selectedCard, {
        { "dropdown", "selector", nil, { "Indicator", GF_STATUS_ICON_VALUES, siconLeftW },
            { 16, -54, siconLeftW - 32, "LEFT" }, path = "status.selector", classification = "ephemeral" },
    }, selectionRows)
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
    if MSUF.Client and MSUF.Client.SupportsThreatText == true then
        local threatRows = Schema.Build(ctx, selectedCard, {
            { "toggle", "threatTextColorCurve", true, { "Color by threat", 16, -106, siconLeftW - 32 },
                tip = { "Color by threat",
                    "Green at low threat, yellow at half, pink at 100% when you have aggro. Turn off to use the status text color instead.", { hook = true } } },
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
        if mappedAura == auraName then
            id = CustomBuffSpellID(altID)
            if id then
                return id
            end
        end
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
    if not spellID then
        SpellFeedback("Enter a valid buff Spell ID, link, or name.", "error")
        return false
    end
    if not specKey then
        SpellFeedback("No spell-indicator spec selected.", "error")
        return false
    end
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
    if not exists and customCount >= CUSTOM_BUFF_LIMIT then
        SpellFeedback("Custom buff limit reached.", "error")
        return false
    end
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
-- Escape does not answer it: a menu-owned prompt (M.ShowPrompt). Only the
-- second button picks the entered ID; a replaced question adds nothing.
local function ShowCustomBuffAuraIDSuggestion(refreshPage, kind, specKey, spellIDs, suggestedID, spellName)
    M.ShowPrompt("MSUF2_GF_SPELL_CUSTOM_BUFF_AURA_ID", {
        text = M.Format("%s is active on you with Aura ID %d. Your entered ID is %d. Track both IDs?",
            tostring(spellName or Tr("This buff")), tonumber(suggestedID) or 0, tonumber(spellIDs and spellIDs[1]) or 0),
        accept = Tr("Use both IDs"), cancel = Tr("Entered ID only"), hideOnEscape = false,
        onAccept = function()
            local combined, seen = {}, {}
            for i = 1, #(spellIDs or {}) do AddCustomBuffSpellID(combined, seen, spellIDs[i]) end
            AddCustomBuffSpellID(combined, seen, suggestedID)
            AddCustomBuffResolved(refreshPage, kind, specKey, combined)
        end,
        onCancel = function() AddCustomBuffResolved(refreshPage, kind, specKey, spellIDs) end,
    })
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
-- Blizzard's generic text-input dialog (M.ShowPrompt): it opens empty with
-- the focus in its edit box, Enter accepts, and Add waits for some text.
local function ShowCustomBuffPopup(refreshPage, kind, specKey)
    M.ShowPrompt("MSUF2_GF_SPELL_CUSTOM_BUFF_ID", {
        text = Tr("Enter buff Spell ID, link, or name"), accept = Tr("Add"), cancel = CANCEL or Tr("Cancel"),
        input = { maxLetters = 255 },
        onAccept = function(text) AddCustomBuff(refreshPage, kind, specKey, text or "") end,
    })
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
    for i = 1, #order do
        if order[i] == auraName then
            from = i
            break
        end
    end
    if not from then return end
    targetSlot = max(1, min(#order, tonumber(targetSlot) or from))
    if from == targetSlot then return end
    table.remove(order, from)
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
        GameTooltip:AddLine(Tr("Accepts a buff Spell ID, spell link, or spell name and tracks exact Aura IDs through native AuraSlot filters."), 0.75, 0.78,
            0.86)
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
    if tile._suppressNextClick then
        tile._suppressNextClick = nil
        tile._dragged = false
        return
    end
    if tile._dragged then
        tile._dragged = false
        return
    end
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
    RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(index), M.Format("Tracked spell tile %d", index), "button", "action")
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
            M.Format("Tracked spell %s", tostring(info.display or info.name or i)), "button", "action")
        local auraCfg = SpellConfigFor(kind, specKey, info.name, false)
        tile._customBuff = IsCustomBuffEntry(info.name, auraCfg) or info.custom == true
        local tileEnabled = indicatorsOn and not (auraCfg and auraCfg.enabled == false)
        local color = info.color or { 0.55, 0.65, 0.85 }
        tile._color = color
        tile.addText:Hide()
        tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tile.icon:SetVertexColor(1, 1, 1, 1)
        if runtime and type(runtime.GetAuraIcon) == "function" then
            _G.MSUF_SetIconTexture(tile.icon, runtime.GetAuraIcon(specKey, info.name), "")
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

-- IconScale owns its coalesced drag/release lifecycle; the typed row owns UI input.
local function IconScaleLifecycle(iconScale)
    local pendingApply, pendingScope, releaseScheduled
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
    return {
        get = function() return tonumber(SpellIndicators(CurrentScope()).iconScale) or 100 end,
        set = function(value)
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
        default = 100,
        afterBind = function()
            iconScale:HookScript("OnMouseUp", ScheduleRelease)
            iconScale:HookScript("OnHide", FlushRuntime)
            iconScale:HookScript("OnShow", FlushRuntime)
        end,
    }
end

GP.BuildSpellIndicatorStyleSection = function(ctx, b)
    local section = b:CollapsibleSection("si_style", "Spell Icon Style", 844, false)
    local leftX, leftW, rightX, rightW, innerW = Schema.Columns(section, ctx.width, 30, 28, 0.46, 240, 370, 240, 390)
    W.ControlCard(section, "Basics", nil, leftX - 14, -38, leftW + 28, 322)
    W.ControlCard(section, "Cooldown Text", nil, rightX - 14, -38, rightW + 28, 430)
    W.ControlCard(section, "Stack Count", nil, leftX - 14, -376, leftW + 28, 296)
    W.ControlCard(section, "Duration Bar", nil, rightX - 14, -484, rightW + 28, 312)

    local function Style(kind)
        local si = SpellIndicators(kind or CurrentScope())
        if type(si.style) ~= "table" then si.style = {} end
        return si.style
    end
    local function StyleMeta(_, path, step)
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
    local styleOwner = { config = Style, scope = CurrentScope,
        changed = function(scope) QueueSpellIndicators(scope, "auras") end,
        path = "spell.style.", meta = StyleMeta, stepMeta = StyleMeta, strictToggles = true, rawNumber = true }
    local styleRows, styleControls = Schema.GroupRecordOptions(styleOwner), {}
    styleRows.beforeBind = Track

    Schema.Build(ctx, section, {
        { "slider", "iconZoom", 100, { "Icon Zoom (%)", 100, 200, 1, leftW },
            { leftX, -72, leftW, "LEFT" }, path = "spell.icon_zoom", source = SpellIndicators },
    }, styleRows)

    Schema.Build(ctx, section, {
        { "slider", "iconScale", 100, { "Icon Scale (%)", 20, 300, 1, leftW }, { leftX, -128, leftW, "LEFT" },
            path = "spell.icon_scale", lifecycle = IconScaleLifecycle },
    }, styleRows)

    local halfRight = max(100, floor((rightW - 12) / 2))
    local halfLeft = max(100, floor((leftW - 12) / 2))
    Schema.Build(ctx, section, {
        { "slider", "alpha", 100, { "Opacity", 10, 100, 5, leftW }, { leftX, -184, leftW, "LEFT" },
            get = function() return floor(((tonumber(Style().alpha) or 1) * 100) + 0.5) end,
            convert = function(value) return min(1, max(0.1, (tonumber(value) or 100) / 100)) end },
        { "toggle", "showTooltip", true, { "Show Tooltip", leftX, -240, leftW },
            tip = { "Spell Icon tooltip", "Controls native Aura tooltips for Spell Icons only.", { hook = true } } },
        { "toggle", "showCooldownText", true, { "Show Cooldown Text", rightX, -72, rightW } },
        { "toggle", "showCooldownSwipe", true, { "Show Cooldown Swipe", rightX, -104, rightW } },
        { "slider", "cooldownSize", 8, { "Cooldown Font", 6, 24, 1, rightW }, { rightX, -148, rightW, "LEFT" } },
        { "dropdown", "cooldownAnchor", "CENTER", { "Cooldown Anchor", STATUS_ICON_ANCHORS, rightW }, { rightX, -204, rightW, "LEFT" } },
        { "slider", "cooldownX", 0, { "Cooldown X", -40, 40, 1, halfRight }, { rightX, -260, halfRight, "LEFT" } },
        { "slider", "cooldownY", 0, { "Cooldown Y", -40, 40, 1, halfRight }, { rightX + halfRight + 12, -260, halfRight, "LEFT" } },
        { "dropdown", "cooldownSwipeReverse", "NORMAL",
            { "Swipe Direction", VT("NORMAL", "Normal", "REVERSE", "Reverse"), rightW }, { rightX, -316, rightW, "LEFT" },
            get = function() return Style().cooldownSwipeReverse == true and "REVERSE" or "NORMAL" end,
            convert = function(value) return value == "REVERSE" end },
        { "slider", "cooldownDecimalSeconds", 3, { "Decimals below sec", 0, 30, 1, rightW }, { rightX, -372, rightW, "LEFT" },
            tip = { "Cooldown text format", "Below this value, remaining whole seconds may show one decimal place. Set 0 for whole seconds only.", { hook = true } } },
        { "toggle", "showStacks", true, { "Show Stack Count", leftX, -410, leftW } },
        { "slider", "stackSize", 10, { "Stack Font", 6, 24, 1, leftW }, { leftX, -452, leftW, "LEFT" } },
        { "dropdown", "stackAnchor", "BOTTOMRIGHT", { "Stack Anchor", STATUS_ICON_ANCHORS, leftW }, { leftX, -508, leftW, "LEFT" } },
        { "slider", "stackX", 0, { "Stack X", -40, 40, 1, halfLeft }, { leftX, -564, halfLeft, "LEFT" } },
        { "slider", "stackY", 0, { "Stack Y", -40, 40, 1, halfLeft }, { leftX + halfLeft + 12, -564, halfLeft, "LEFT" } },
        { "toggle", "showDurationBar", false, { "Show Duration Bar", rightX, -520, rightW } },
        { "slider", "durationBarHeight", 2, { "Height", 1, 16, 1, rightW }, { rightX, -562, rightW, "LEFT" } },
        { "dropdown", "durationBarDisplay", "BAR_ONLY", { "Display", VT("BAR_ONLY", "Bar Only", "OVERLAY", "Icon + Bar"), rightW },
            { rightX, -618, rightW, "LEFT" } },
        { "dropdown", "durationBarPosition", "BOTTOM", { "Position", VT("BOTTOM", "Bottom", "TOP", "Top"), halfRight },
            { rightX, -674, halfRight, "LEFT" } },
        { "dropdown", "durationBarDirection", "REMAINING", { "Fill Mode", VT("REMAINING", "Remaining", "ELAPSED", "Elapsed"), halfRight },
            { rightX + halfRight + 12, -674, halfRight, "LEFT" } },
    }, styleRows, styleControls)
    local swipeDirection = styleControls.cooldownSwipeReverse
    W.Text(section, M.Format("Shape, border and shadow: %s. All controls here remain Group-scope aware.", M.NavPath("auras3_buffs")),
        leftX, -814, innerW, T.colors.muted)


    RefreshStyleState = RefreshStyleState(function()
        local si = SpellIndicators(CurrentScope())
        local style = Style()
        local enabled = si.enabled == true
        SetOptionsEnabled(controls, enabled)
        SetManyEnabled(enabled and style.showCooldownText ~= false, styleControls.cooldownSize, styleControls.cooldownAnchor,
            styleControls.cooldownX, styleControls.cooldownY, styleControls.cooldownDecimalSeconds)
        SetOptionEnabled(swipeDirection, enabled and style.showCooldownSwipe ~= false)
        SetManyEnabled(enabled and style.showStacks ~= false, styleControls.stackSize, styleControls.stackAnchor,
            styleControls.stackX, styleControls.stackY)
        SetManyEnabled(enabled and style.showDurationBar == true, styleControls.durationBarHeight, styleControls.durationBarDisplay,
            styleControls.durationBarPosition, styleControls.durationBarDirection)
        local scope = CurrentScope()
        local scopeLabel = scope == "party" and "Party" or (scope == "mythicraid" and "Mythic Raid" or "Raid")
        SetSectionBadgesAndStatus(section, {
            { text = scopeLabel, kind = "info", important = true },
            { text = M.Format("Zoom %d%%", floor((tonumber(si.iconZoom) or 100) + 0.5)), kind = "info" },
            { text = "Buff Appearance", kind = "accent" },
            OnOffBadge(enabled, "Active", "Inactive"),
        })
    end)
    styleOwner.afterToggle = RefreshStyleState
    TrackSectionRefresh(ctx, section, RefreshStyleState)
end

-- The Spell Indicators section is assembled by SpellSection.Build from one stage
-- per card. Stages share one per-build `state` table and run in the order the
-- controls used to be created inline; state.RefreshState is a RefreshProxy, so
-- callbacks bound in earlier stages reach the refresh body wired last.
local SpellSection = {}
function SpellSection.Open(state, ctx, b, RefreshPage)
    local spells = b:CollapsibleSection("si", "Spell Indicators", 848, false)
    local siLeftX, siLeftW, siRightX, siRightW = Schema.Columns(spells, ctx.width, 30, 28, 0.46, 240, 370, 240, 390)
    state.spellSetCard = W.ControlCard(spells, "Choose Spells", nil, siLeftX - 14, -38, siLeftW + 28, 404)
    W.ControlCard(spells, "Edit Spell", nil, siRightX - 14, -38, siRightW + 28, 404)
    state.placedIndicatorCard = W.ControlCard(spells, "Show on Frame", nil, siLeftX - 14, -456, siLeftW + 28, 560)
    state.frameHighlightCard = W.ControlCard(spells, "Highlight Health Bar", nil, siRightX - 14, -456, siRightW + 28, 360)
    state.placedRows = Schema.GroupRecordOptions({ config = PlacedConfig, scope = CurrentScope,
        changed = QueueSpellIndicators, path = "spell.placed.", meta = ControlMeta, stepMeta = StepMeta })
    state.frameRows = Schema.GroupRecordOptions({ config = FrameEffectConfig, scope = CurrentScope,
        changed = QueueSpellIndicators, path = "spell.frame.", meta = ControlMeta, stepMeta = StepMeta })
    state.selectedRows = Schema.GroupRecordOptions({ config = CurrentSpellConfig, scope = CurrentScope,
        changed = QueueSpellIndicators, path = "spell.selected.", meta = ControlMeta, stepMeta = StepMeta })
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
    local function ChangedSpec(kind, reason)
        EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
        CurrentSpellAura(kind)
        QueueSpellIndicators(kind)
        RefreshGFPreview()
        RefreshSpellIndicatorState()
        RequestSpellControlRefresh(reason)
    end
    local commandRows = Schema.GroupCommands({
        enabled = {
        get = function()
            if SPELL_INDICATORS_121_PTR_DISABLED then return false end
            return SpellIndicators(CurrentScope()).enabled == true
        end,
        set = function(value)
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
        },
        spec = {
        get = function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        set = function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            ChangedSpec(kind, "gf-spell-spec")
        end,
        },
        multiSpec = {
        get = function() return CurrentSpellMultiSpec(CurrentScope()) end,
        set = function(value)
            local kind = CurrentScope()
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[kind] = value or ""
            ChangedSpec(kind, "gf-spell-multi-spec")
        end,
        },
        tracked = {
        get = function()
            local cfg = SpellIndicators(CurrentScope())
            local specKey = CurrentSpellMultiSpec(CurrentScope())
            if IsAllSpecsSpellSpec(specKey) then return true end
            return cfg.spec == "multi" and specKey ~= "" and cfg.multiSpecs and cfg.multiSpecs[specKey] == true
        end,
        set = function(value)
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
        },
    }, ControlMeta, StepMeta)
    local function SelectedSpellConfigTable()
        return CurrentSpellConfig(CurrentScope(), true) or SpellIndicators(CurrentScope())
    end
    local specRows = Schema.Build(ctx, spells, {
        { "switch", "enabled", nil, { "Show spell indicators", siLeftX, -72, siLeftW }, path = "spell.enabled",
            flagsBefore = { _msuf2GroupFrameGateAlwaysEnabled = true } },
        { "slider", "layer", 9, { "Layer (0-30)", 0, 30, 1, siRightW }, { siRightX, -72, siRightW, "LEFT" },
            path = "spell.selected.layer", source = SelectedSpellConfigTable, bind = Schema.GroupNestedBinding },
        { "dropdown", "spec", nil, { "Spec", SpellSpecValues, siLeftW }, { siLeftX, -116, siLeftW, "LEFT" }, path = "spell.spec" },
    }, commandRows)
    local siEnable, siLayer, specDrop = specRows.enabled, specRows.layer, specRows.spec
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
        M.AddTooltip(previewAll, "Preview all spells",
            "On previews every enabled spell of every tracked spec, including spells that only draw a frame effect. Off previews only the selected spell.",
            { hook = true })
    end
    RefreshPreviewAllButton()
    -- The Edit Spell column stacks Layer, the multi-spec pair and Aura Spell IDs
    -- above Choose spell. The multi-spec pair only shows in multi-spec mode, but
    -- it keeps its own rows so it never covers the ID input.
    local allSpecsHint
    local function PrepareTrackHint()
        allSpecsHint = W.Text(spells, "Shared entries apply to every spec.", siRightX, -184, siRightW, T.colors.accent)
        if allSpecsHint.SetWordWrap then allSpecsHint:SetWordWrap(true) end
        allSpecsHint:Hide()
    end
    local multiRows = Schema.Build(ctx, spells, {
        { "dropdown", "multiSpec", nil, { "Multi-Spec Entry", function() return SpellTrackedSpecValues() end, siRightW },
            { siRightX, -130, siRightW, "LEFT" }, path = "spell.multi_spec.selector", classification = "ephemeral" },
        { "toggle", "tracked", nil, { "Track selected multi spec", siRightX, -184, siRightW },
            path = "spell.multi_spec.tracked", beforeBind = PrepareTrackHint },
    }, commandRows)
    local multiSpecDrop, multiSpecEnabled = multiRows.multiSpec, multiRows.tracked
    state.spellGrid = SpellTileGrid.New(ctx, spells, siLeftX, -254, siLeftW, state.RefreshPage)
    state.siEnable, state.siLayer, state.specDrop, state.RefreshPreviewAllButton = siEnable, siLayer, specDrop, RefreshPreviewAllButton
    state.multiSpecDrop, state.multiSpecEnabled, state.allSpecsHint = multiSpecDrop, multiSpecEnabled, allSpecsHint
end
--- Edit Spell: Choose spell, Show this spell, Aura Spell IDs, Only show my
--- casts and Hide duplicate Buff icon.
function SpellSection.BuildSelectedSpell(state, ctx)
    local spells, siRightX, siRightW = state.spells, state.siRightX, state.siRightW
    local RefreshSpellIndicatorState, RequestSpellControlRefresh = state.RefreshState, state.RequestControlRefresh
    local rows = Schema.Build(ctx, spells, {
        { "dropdown", "aura", nil, { "Choose spell", function() return SpellAuraValues(CurrentScope()) end, siRightW },
            { siRightX, -282, siRightW, "LEFT" }, path = "spell.selected_aura", classification = "ephemeral",
            get = function() return CurrentSpellAura(CurrentScope()) end,
            set = function(value)
                SetCurrentSpellAura(CurrentScope(), value)
                RefreshGFPreview()
                RefreshSpellIndicatorState()
                RequestSpellControlRefresh("gf-spell-selection")
            end },
        { "switch", "enabled", true, { "Show this spell", siRightX, -342, siRightW } },
        { "textinput", "spells", "", { "Aura Spell IDs", siRightW }, { siRightX, -222, siRightW },
            path = "spell.selected.spell_ids", commitOnBlur = true, requireRecord = true, convert = function(value)
                local ids = CustomBuffSpellIDs(value)
                return ids and CustomBuffSpellIDListText(ids) or ""
            end },
        { "toggle", "onlyOwn", true, { "Only show my casts", siRightX, -374, siRightW }, path = "spell.selected.only_mine",
            get = function()
                local cfg = CurrentSpellConfig(CurrentScope(), false)
                if not cfg then return false end
                if cfg.custom == true and cfg._msufCustomOnlyOwnExplicit ~= true then return false end
                return cfg.onlyOwn ~= false
            end,
            set = function(value)
                local cfg = CurrentSpellConfig(CurrentScope(), true)
                if cfg then
                    if cfg.custom == true then cfg._msufCustomOnlyOwnExplicit = true end
                    cfg.onlyOwn = value and true or false
                end
                QueueSpellIndicators(CurrentScope())
            end },
        { "toggle", "autoBlacklist", false, { "Hide duplicate Buff icon", siRightX, -406, siRightW },
            path = "spell.selected.auto_blacklist", uncheckedNil = true, get = function()
                local cfg = CurrentSpellConfig(CurrentScope(), false)
                if CurrentSpellIsExternalDefensive(CurrentScope()) and ExternalAutoBlacklistActive(CurrentScope()) then return true end
                return cfg and cfg.autoBlacklist == true or false
            end },
    }, state.selectedRows)
    local spellEnabled, customSpellIDs, onlyMine, autoBlacklist = rows.enabled, rows.spells, rows.onlyOwn, rows.autoBlacklist
    if M.AddTooltip then
        M.AddTooltip(autoBlacklist, "Hide duplicate Buff icon",
            "Hides this aura from the regular Buff icons while this spell indicator is enabled. External-defensive Spell Icons follow the active External Defensives container's Auto-blacklist from Buffs setting.",
            { hook = true, titleAsLine = true })
    end
    state.spellEnabled, state.customSpellIDs, state.onlyMine, state.autoBlacklist = spellEnabled, customSpellIDs, onlyMine, autoBlacklist
end
--- Shared color-history label for the selected spell.
function SpellSection.PrepareColorScopeTag(state)
    function state.ColorScopeTag()
        local kind = CurrentScope()
        return M.Format("%s: %s", GP.ScopeLabel(kind), tostring(CurrentSpellAura(kind) or ""))
    end
end
--- Show on Frame: Display as, its shape controls and the selected spell color.
function SpellSection.BuildPlacedCard(state, ctx)
    local siLeftX, siLeftW = state.siLeftX, state.siLeftW
    local RefreshSpellIndicatorState, RefreshPage = state.RefreshState, state.RefreshPage
    local placedType = Schema.Build(ctx, state.spells, {
        { "dropdown", "placed", "none", { "Display as", PLACED_INDICATOR_TYPES, siLeftW },
            { siLeftX, -492, siLeftW, "LEFT" }, subtype = true, path = "spell.selected.placed.type", defaults =
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
        end, afterSet =
        -- Re-gate this section synchronously before the page-level refresh.
        -- A page reselect runs its refreshers behind the menu-data revision
        -- guard, and the surrounding history capture only bumps that revision
        -- after this setter returns. Without the direct call the controls of
        -- the previous shape stay as they were, so switching Icon to Square
        -- left Icon Effect visible until an unrelated interaction refreshed it.
        function()
            RefreshSpellIndicatorState()
            RefreshPage()
        end },
    }, state.selectedRows).placed
    local timerGap = 12
    local timerSliderW = floor((siLeftW - timerGap) * 0.5)
    local rows = Schema.Build(ctx, state.spells, {
        { "dropdown", "anchor", "TOPLEFT", { "Anchor", STATUS_ICON_ANCHORS, siLeftW }, { siLeftX, -546, siLeftW, "LEFT" } },
        { "slider", "size", 18, { "Size", 1, 48, 1, siLeftW }, { siLeftX, -600, siLeftW, "LEFT" } },
        { "slider", "barWidth", 42, { "Bar Width", 8, 120, 1, siLeftW }, { siLeftX, -654, siLeftW, "LEFT" } },
        { "dropdown", "growth", "RIGHTDOWN", { "Growth", SPELL_GROWTH_VALUES, siLeftW }, { siLeftX, -708, siLeftW, "LEFT" } },
        { "dropdown", "iconEffect", "none", { "Icon Effect", ICON_EFFECT_TYPES, siLeftW },
            { siLeftX, -762, siLeftW, "LEFT" }, afterSet = RefreshSpellIndicatorState },
        { "toggle", "barSmoothFill", false, { "Smooth fill", siLeftX, -762, siLeftW }, { siLeftX, -762, siLeftW, "LEFT" } },
        { "toggle", "barShowTimer", false, { "Show Timer Text", siLeftX, -802, siLeftW },
            { siLeftX, -802, siLeftW, "LEFT" }, afterSet = RefreshSpellIndicatorState },
        { "dropdown", "barTimerAnchor", "CENTER", { "Timer Anchor", STATUS_ICON_ANCHORS, siLeftW }, { siLeftX, -842, siLeftW, "LEFT" } },
        { "slider", "barTimerX", 0, { "Timer X", -100, 100, 1, timerSliderW }, { siLeftX, -896, timerSliderW, "LEFT" } },
        { "slider", "barTimerY", 0, { "Timer Y", -100, 100, 1, timerSliderW },
            { siLeftX + timerSliderW + timerGap, -896, timerSliderW, "LEFT" } },
    }, state.placedRows)
    local placedAnchor, placedSize, placedBarWidth, placedGrowth = rows.anchor, rows.size, rows.barWidth, rows.growth
    local placedIconEffect, placedBarSmoothFill, placedBarShowTimer = rows.iconEffect, rows.barSmoothFill, rows.barShowTimer
    local placedBarTimerAnchor, placedBarTimerX, placedBarTimerY = rows.barTimerAnchor, rows.barTimerX, rows.barTimerY
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
    state.frameType = Schema.Build(ctx, spells, {
        { "dropdown", "frame", "none", { "Effect", FRAME_EFFECT_TYPES, siRightW },
            { siRightX, -490, siRightW, "LEFT" }, subtype = true, path = "spell.selected.frame.type", defaults =
        function(frame)
            if not frame.color then
                local c = CurrentAuraColor(CurrentScope())
                frame.color = { c[1] or 1, c[2] or 1, c[3] or 1, 0.8 }
            end
            frame.priority = frame.priority or 5
            frame.layer = tonumber(frame.layer) or 0
            frame.strata = frame.strata or "AUTO"
        end, afterSet = state.RefreshState },
    }, state.selectedRows).frame
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
    state.framePriority = Schema.Build(ctx, spells, {
        { "slider", "priority", 5, { "Priority", 1, 10, 1, siRightW }, { siRightX, -544, siRightW, "LEFT" } },
    }, state.frameRows).priority
    local frameAlpha = Schema.Build(ctx, spells, {
        { "slider", "alpha", 25, { "Tint Alpha", 5, 100, 5, siRightW }, { siRightX, -598, siRightW, "LEFT" },
            get = function()
                local frame = FrameEffectConfig(CurrentScope(), false)
                return floor(((frame and (frame.alpha or (frame.color and frame.color[4])) or 0.25) * 100) + 0.5)
            end,
            convert = function(value) return (tonumber(value) or 25) / 100 end,
            afterWrite = function(frame, alpha) if frame.color then frame.color[4] = alpha end end },
    }, state.frameRows).alpha
    state.frameAlpha = frameAlpha
    local rows = Schema.Build(ctx, spells, {
        { "slider", "thickness", 2, { "Border / Glow Thickness", 1, 8, 1, siRightW }, { siRightX, -652, siRightW, "LEFT" } },
        { "slider", "layer", 0, { "Effect Layer (0-30)", 0, 30, 1, siRightW }, { siRightX, -706, siRightW, "LEFT" } },
    }, state.frameRows)
    state.frameThickness, state.frameLayer = rows.thickness, rows.layer
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
    SpellSection.PrepareColorScopeTag(state)
    SpellSection.BuildPlacedCard(state, ctx)
    SpellSection.BuildFrameCard(state, ctx)
    local refresh = state.RefreshState(function() SpellSection.Refresh(state) end)
    TrackSectionRefresh(ctx, state.spells, refresh)
    GP.BuildSpellIndicatorStyleSection(ctx, b)
end

GP.BuildSpellIndicatorsSection = SpellSection.Build

--- Release links into a corner slot's Custom Spell "When" (present or missing):
--- one view per group scope and slot. The hook selects both in place.
local function DeclareExactCornerMode(control)
    local values = {}
    for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
        if MSUF.Client.SupportsGroupKind(scope) then
            for i = 1, #CI_SLOT_VALUES do
                local slot = CI_SLOT_VALUES[i].value
                values[scope .. "_" .. slot] = "gf_" .. scope .. ".ciCustom" .. slot .. ".mode"
            end
        end
    end
    return M.DeclareExactViewContract(control, "groupCornerSlot", values, function(value)
        local scope, slot = value:match("^(%a+)_(%w+)$")
        M.SetMenuStateValue("gfScope", scope)
        M.SetMenuStateValue("gfCornerSlotSelection", slot)
        return CurrentScope() == scope and CurrentCISlot() == slot
    end)
end
local function CurrentCornerField()
    local slot = CurrentCISlot()
    return "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none"
end
local function BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    local corners = b:CollapsibleSection("ci", "Corner Indicators", 674, false)
    local leftX, leftW, rightX, rightW = Schema.Columns(corners, ctx.width, 30, 28, 0.46, 240, 360, 260, 440)
    local cornerEditorCard
    do
        W.ControlCardBackdrop(corners, leftX - 14, -38, leftW + 28, 224)
        W.ControlCardBackdrop(corners, leftX - 14, -272, leftW + 28, 334)
        cornerEditorCard = W.ControlCardBackdrop(corners, rightX - 14, -38, rightW + 28, 526 + CORNER_MISSING_NOTE_GAP)
        cornerEditorCard._msuf2ControlCardTitle = "Custom Spell Editor"
    end
    W.LabelAt(corners, "Global", leftX, -42, leftW, "GameFontNormalSmall", T.colors.accent)
    local cornerRows = Schema.Build(ctx, corners, {
        { "switch", "ciEnabled", false, { "Corner Indicators", leftX, -72, leftW },
            flagsAfter = { _msuf2GroupFrameGateAlwaysEnabled = true } },
        { "slider", "ciSize", 8, { "Icon Size", 4, 24, 1, leftW }, { leftX, -116, leftW, "LEFT" } },
        { "slider", "ciAlpha", 1, { "Alpha", 10, 100, 5, leftW }, { leftX, -170, leftW, "LEFT" },
            path = "corner.alpha", binding = "scopeValue", scale = 100, fallback = 100 },
        { "slider", "ciLayer", 7, { "Layer (0-30)", 0, 30, 1, leftW }, { leftX, -224, leftW, "LEFT" } },
    }, ROW_OPTIONS)
    local ciEnable, ciSize, ciAlpha, ciLayer = cornerRows.ciEnabled, cornerRows.ciSize, cornerRows.ciAlpha, cornerRows.ciLayer
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
        local field, label = "ciSlot" .. slotKey, M.Format("%s Indicator", Tr(slotInfo.text or slotKey))
        local assignmentDrop = Schema.Build(ctx, corners, {
            { "dropdown", field, CI_SLOT_DEFAULTS[slotKey] or "none", { label, CICategoryValues, w }, { p.x, p.y, w, "LEFT" },
                path = "corner.assignment." .. tostring(slotKey), binding = "scopeValue", writeDefault = "none", afterSet = RefreshPage,
                select = { "gfCornerSlotSelection", slotKey } },
        }, ROW_OPTIONS)[field]
        slotControls[#slotControls + 1] = assignmentDrop
    end
    W.LabelAt(corners, "Custom Spell Editor", rightX, -42, rightW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Pick a slot, set it to Custom Spell, then enter spell IDs. This edits one slot at a time and keeps the five slot assignments visible.", rightX, -64, rightW, T.colors.muted)
    local editorCommands = Schema.GroupCommands({
        slot = { get = CurrentCISlot, set = function(value)
            M.SetMenuStateValue("gfCornerSlotSelection", value or "TL")
            RefreshPage()
        end },
    }, ControlMeta, StepMeta)
    local slotDrop = Schema.Build(ctx, corners, {
        { "dropdown", "slot", nil, { "Editor Slot", CI_SLOT_VALUES, rightW }, { rightX, -122, rightW, "LEFT" },
            path = "corner.editor.slot", classification = "ephemeral" },
    }, editorCommands).slot
    local categoryDrop = Schema.Build(ctx, corners, {
        { "dropdown", "category", "none", { "Selected Slot Indicator", CICategoryValues, rightW }, { rightX, -176, rightW, "LEFT" },
            path = "corner.editor.category", binding = "scopeValue", writeDefault = "none", afterSet = RefreshPage, target = CurrentCornerField },
    }, ROW_OPTIONS).category
    local customStatus = W.Text(corners, "", rightX, -230, rightW, T.colors.muted)
    if customStatus.SetWordWrap then customStatus:SetWordWrap(true) end
    local customRows = Schema.GroupRecordOptions({
        config = function(scope, create) return CICustomConfig(scope, CurrentCISlot(), create) end,
        scope = CurrentScope, changed = function(scope) QueueGF(scope, "visual") end,
        path = "corner.editor.", meta = ControlMeta, stepMeta = StepMeta,
    })
    local customSpells = Schema.Build(ctx, corners, {
        { "textinput", "spells", "", { "Spell IDs (comma-separated)", rightW }, { rightX, -286, rightW },
            path = "corner.editor.spell_ids", commitOnBlur = true },
    }, customRows).spells
    local customMode = DeclareExactCornerMode(Schema.Build(ctx, corners, {
        { "dropdown", "mode", "present", { "When", CornerModeValues, rightW }, { rightX, -350, rightW, "LEFT" },
            accept = function(value) return value ~= "missing" or CORNER_MISSING_AVAILABLE end },
    }, customRows).mode)
    if not CORNER_MISSING_AVAILABLE then
        local missingNote = W.Text(corners, "", rightX, -398, rightW, T.colors.muted)
        if missingNote.SetWordWrap then missingNote:SetWordWrap(true) end
        missingNote:SetText(CORNER_MISSING_NOTICE)
    end
    local customFilter = Schema.Build(ctx, corners, {
        { "dropdown", "filter", "HELPFUL|PLAYER", { "Filter", CIFilterValues, rightW },
            { rightX, -404 - CORNER_MISSING_NOTE_GAP, rightW, "LEFT" } },
    }, customRows).filter
    local customColor = Schema.Build(ctx, corners, {
        { "color", "color", { 0.40, 1.00, 0.40 }, { "Custom Color" }, { rightX, -458 - CORNER_MISSING_NOTE_GAP, rightW },
            channels = { "r", "g", "b" }, flagsBefore = {
                _msuf2ColorLabel = "Custom spell color", _msuf2ContextColorCardOverride = cornerEditorCard } },
    }, customRows).color
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
    local customHelp = W.Text(corners, "Tip: HELPFUL|PLAYER and HARMFUL|PLAYER are the safest filters because WoW exposes your own spell IDs reliably.", rightX, -506 - CORNER_MISSING_NOTE_GAP, rightW, T.colors.dim)
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
